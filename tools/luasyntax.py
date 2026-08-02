#!/usr/bin/env python3
"""Fast Lua syntax gate for the JustAC addon.

Parses each given .lua file with luaparser (Lua grammar). WoW runs Lua 5.1;
luaparser targets 5.3, which is a syntactic superset for every construct WoW
uses (WoW code has no goto/labels or // operator), so a clean parse here means
the file will at least load without a syntax error. This does NOT catch
undefined globals - that's luacheck's job; this is the brace/paren/statement gate.

Usage: python luasyntax.py <file.lua> [file2.lua ...]
Exit 0 = all clean, 1 = at least one failure.
"""
import sys
from luaparser import ast
from luaparser.ast import SyntaxException

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

def main(paths):
    errs = 0
    for path in paths:
        try:
            src = read(path)
        except Exception as e:
            print(f"READ-ERR {path}: {e}")
            errs += 1
            continue
        try:
            ast.parse(src)
            print(f"OK   {path}")
        except SyntaxException as e:
            print(f"FAIL {path}: {e}")
            errs += 1
        except Exception as e:  # tokenizer / recursion / anything else
            print(f"FAIL {path}: {type(e).__name__}: {e}")
            errs += 1
    print(f"\n{'-'*40}\n{len(paths)-errs}/{len(paths)} clean, {errs} failed")
    return 1 if errs else 0

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python luasyntax.py <file.lua> ...")
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
