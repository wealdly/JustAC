# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Lua 5.1 compile-limit headroom for every addon file the TOC loads.

WoW compiles each file with Lua 5.1, where a function with more than 60 upvalues kills the
whole file. tools/luasyntax.py hard-fails above 60 and warns from 55; this test fails at the
warning line, so a large function (the queue build, CategorizeAndAssembleRotation) cannot
creep back to the limit unnoticed. Grow such a function through the module table or a state
table it already captures, never through new file-locals (Documentation/STYLE_GUIDE_JUSTAC.md).

Run: python tools/test_lua_limits.py
"""
import re
import subprocess
import sys
from pathlib import Path

MAIN_CHUNK_LOCAL_WARN = 195

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_runtime import ROOT, toc_closure  # noqa: E402


def main():
    files = sorted(f for f in toc_closure(ROOT / "JustAC.toc")
                   if f.endswith(".lua") and not f.startswith("Libs/"))
    out = subprocess.run([sys.executable, str(ROOT / "tools" / "luasyntax.py"), *files],
                         cwd=ROOT, capture_output=True, text=True).stdout
    over = [line for line in out.splitlines() if "WARN" in line or line.startswith("FAIL")]
    assert files and not over, "Lua 5.1 upvalue headroom (warn line 55):\n" + "\n".join(over)
    # Lua 5.1 also caps a function at 200 locals, and a file's main chunk is a function: every
    # file-level `local` counts. Compile each file for real, and keep headroom below the cap.
    from lupa.lua51 import LuaRuntime  # type: ignore[import-not-found]
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_ok = lua.eval("function(src, name) local f, err = loadstring(src, name); return f ~= nil, err end")
    crowded = []
    for name in files:
        source = (ROOT / name).read_text(encoding="utf-8")
        ok, err = compile_ok(source, name)
        assert ok, f"Lua 5.1 will not compile {name}: {err}"
        count = 0
        for line in source.splitlines():
            m = re.match(r"local function \w+", line)
            if m:
                count += 1
                continue
            m = re.match(r"local ([\w, ]+?)\s*(=|$)", line)
            if m:
                count += len([n for n in m.group(1).split(",") if n.strip()])
        if count > MAIN_CHUNK_LOCAL_WARN:
            crowded.append(f"{name}: about {count} file-level locals")
    assert not crowded, ("Lua 5.1 main-chunk locals (cap 200, warn line "
                         f"{MAIN_CHUNK_LOCAL_WARN}); group new state into a table:\n" + "\n".join(crowded))
    print(f"lua limits: {len(files)} addon files compile under Lua 5.1, below the 55-upvalue and "
          f"{MAIN_CHUNK_LOCAL_WARN}-file-local warning lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
