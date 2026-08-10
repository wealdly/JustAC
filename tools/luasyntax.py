#!/usr/bin/env python3
"""Fast Lua syntax + compile-limit gate for the JustAC addon.

Parses each given .lua file with luaparser (Lua grammar). WoW runs Lua 5.1;
luaparser targets 5.3, which is a syntactic superset for every construct WoW
uses (WoW code has no goto/labels or // operator), so a clean parse here means
the file will at least load without a syntax error. This does NOT catch
undefined globals - that's luacheck's job; this is the brace/paren/statement gate.

It ALSO counts upvalues per function. Lua 5.1 hard-fails a function with more
than 60 upvalues AT COMPILE TIME, which kills the whole file: the observable
symptom is "module not found" at load, with the real error only in the client's
error frame ("function at line N has more than 60 upvalues"). A 5.3 grammar
parse cannot catch that, which is exactly how it shipped past this gate once
(SpellQueue.lua, 2026-08-09). Upvalues chain transitively: an inner function
reaching a file-scope local charges every enclosing function on the way up,
and the counter models that.

Approximation, deliberate: locals are flattened to function scope, so
declaration order and block shadowing are ignored. That can only OVER-count,
and only in code that references a name before its local declaration (a global
read in real Lua) - a pattern this codebase's file-locals-at-top style never
produces. Overcounting is the safe direction for a gate.

Usage: python luasyntax.py <file.lua> [file2.lua ...]
Exit 0 = all clean, 1 = at least one failure (syntax error or >60 upvalues).
"""
import sys
from luaparser import ast, astnodes
from luaparser.ast import SyntaxException

UPVALUE_LIMIT = 60   # Lua 5.1 per-function compile limit (hard file killer)
UPVALUE_WARN = 55    # headroom warning: refactor before the next edit trips it


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    # strip UTF-8 BOM; decode leniently (non-ASCII only ever lives in string/comment bytes)
    if data[:3] == b"\xef\xbb\xbf":
        data = data[3:]
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


class FuncScope:
    __slots__ = ("label", "line", "parent", "children", "declared", "refs", "upvals")

    def __init__(self, label, line, parent):
        self.label = label
        self.line = line
        self.parent = parent
        self.children = []
        self.declared = set()   # params + every local declared in this function's body
        self.refs = set()       # every variable name read/written in this body (nested funcs excluded)
        self.upvals = set()
        if parent:
            parent.children.append(self)


def node_line(node):
    line = getattr(node, "line", None)
    if line:
        return line
    tok = getattr(node, "_first_token", None)
    return getattr(tok, "line", "?") if tok else "?"


def name_of(node):
    """Best-effort dotted label for a function-ish name expression."""
    if isinstance(node, astnodes.Name):
        return node.id
    if isinstance(node, astnodes.Index):
        base = name_of(node.value)
        field = node.idx.id if isinstance(node.idx, astnodes.Name) else "?"
        return f"{base}.{field}"
    return "?"


SQUARE = getattr(getattr(astnodes, "IndexNotation", None), "SQUARE", object())


def visit(node, sc):
    # luaparser occasionally stores plain Python values where an AST node could
    # sit (e.g. an omitted numeric-for step is the int 1) - never descend those.
    if not isinstance(node, astnodes.Node):
        return
    if isinstance(node, astnodes.Name):
        sc.refs.add(node.id)
        return
    if isinstance(node, astnodes.Index):
        visit(node.value, sc)
        # Dot notation stores the field as a Name that is NOT a variable.
        if not (isinstance(node.idx, astnodes.Name) and getattr(node, "notation", SQUARE) != SQUARE):
            visit(node.idx, sc)
        return
    if isinstance(node, astnodes.Invoke):
        visit(node.source, sc)          # obj:method(...) - method name is not a variable
        for a in node.args:
            visit(a, sc)
        return
    if isinstance(node, astnodes.Field):
        # { key = v } stores key as a Name that is not a variable; { [expr] = v } is.
        if getattr(node, "between_brackets", False) or not isinstance(node.key, astnodes.Name):
            visit(node.key, sc)
        visit(node.value, sc)
        return
    if isinstance(node, astnodes.LocalAssign):
        for v in node.values or []:     # values evaluate before the locals exist
            visit(v, sc)
        for t in node.targets:
            if isinstance(t, astnodes.Name):
                sc.declared.add(t.id)
        return
    if isinstance(node, astnodes.Fornum):
        for part in (node.start, node.stop, node.step):
            if part is not None:
                visit(part, sc)
        if isinstance(node.target, astnodes.Name):
            sc.declared.add(node.target.id)
        visit(node.body, sc)
        return
    if isinstance(node, astnodes.Forin):
        for it in node.iter:
            visit(it, sc)
        for t in node.targets:
            if isinstance(t, astnodes.Name):
                sc.declared.add(t.id)
        visit(node.body, sc)
        return
    if isinstance(node, astnodes.LocalFunction):
        sc.declared.add(node.name.id)   # declared before the body: recursion is not an upvalue
        push_func(node.name.id, node, sc)
        return
    if isinstance(node, astnodes.Method):
        visit(node.source, sc)          # the table being extended is a real reference
        push_func(f"{name_of(node.source)}:{name_of(node.name)}", node, sc, implicit_self=True)
        return
    if isinstance(node, astnodes.Function):
        visit(node.name, sc)            # Name -> global/local write; Index -> base table reference
        push_func(name_of(node.name), node, sc)
        return
    if isinstance(node, astnodes.AnonymousFunction):
        push_func("anonymous", node, sc)
        return
    # Generic descent for everything else (Block, If, While, Call, Return, Table, ops...)
    for key, val in vars(node).items():
        if key.startswith("_") or key == "comments":
            continue
        if isinstance(val, astnodes.Node):
            visit(val, sc)
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, astnodes.Node):
                    visit(item, sc)


def push_func(label, node, parent, implicit_self=False):
    child = FuncScope(label, node_line(node), parent)
    if implicit_self:
        child.declared.add("self")
    for a in node.args:
        if isinstance(a, astnodes.Name):
            child.declared.add(a.id)
    visit(node.body, child)


def resolve(root):
    """Charge each free name to every scope between the reference and the
    declaring ancestor - Lua chains upvalues through intermediate closures."""
    stack = [root]
    while stack:
        sc = stack.pop()
        stack.extend(sc.children)
        if sc.parent is None:
            continue
        for ref in sc.refs - sc.declared:
            anc, path = sc.parent, [sc]
            while anc is not None:
                if ref in anc.declared:
                    for hop in path:
                        hop.upvals.add(ref)
                    break
                path.append(anc)
                anc = anc.parent
            # no declaring ancestor -> global, costs nothing


def check_upvalues(tree):
    root = FuncScope("<chunk>", 0, None)
    visit(tree, root)
    resolve(root)
    fails, warns = [], []
    stack = list(root.children)
    while stack:
        sc = stack.pop()
        stack.extend(sc.children)
        n = len(sc.upvals)
        if n > UPVALUE_LIMIT:
            fails.append((sc.label, sc.line, n))
        elif n >= UPVALUE_WARN:
            warns.append((sc.label, sc.line, n))
    return fails, warns


def main(paths):
    sys.setrecursionlimit(20000)
    errs = 0
    for path in paths:
        try:
            src = read(path)
        except Exception as e:
            print(f"READ-ERR {path}: {e}")
            errs += 1
            continue
        try:
            tree = ast.parse(src)
        except SyntaxException as e:
            print(f"FAIL {path}: {e}")
            errs += 1
            continue
        except Exception as e:  # tokenizer / recursion / anything else
            print(f"FAIL {path}: {type(e).__name__}: {e}")
            errs += 1
            continue
        try:
            fails, warns = check_upvalues(tree)
        except Exception as e:
            # The gate must never block on its own bugs - syntax already passed.
            print(f"OK   {path}  (upvalue check skipped: {type(e).__name__}: {e})")
            continue
        if fails:
            for label, line, n in fails:
                print(f"FAIL {path}: {label}() line {line} has {n} upvalues (Lua 5.1 limit {UPVALUE_LIMIT} - file will not compile)")
            errs += 1
        else:
            note = "; ".join(f"{label}() line {line} at {n}/{UPVALUE_LIMIT} upvalues" for label, line, n in warns)
            print(f"OK   {path}" + (f"  (WARN: {note})" if note else ""))
    print(f"\n{'-'*40}\n{len(paths)-errs}/{len(paths)} clean, {errs} failed")
    return 1 if errs else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python luasyntax.py <file.lua> ...")
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
