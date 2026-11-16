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
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_runtime import ROOT, toc_closure  # noqa: E402


def main():
    files = sorted(f for f in toc_closure(ROOT / "JustAC.toc")
                   if f.endswith(".lua") and not f.startswith("Libs/"))
    out = subprocess.run([sys.executable, str(ROOT / "tools" / "luasyntax.py"), *files],
                         cwd=ROOT, capture_output=True, text=True).stdout
    over = [line for line in out.splitlines() if "WARN" in line or line.startswith("FAIL")]
    assert files and not over, "Lua 5.1 upvalue headroom (warn line 55):\n" + "\n".join(over)
    print(f"lua limits: {len(files)} addon files below the 55-upvalue warning line")
    return 0


if __name__ == "__main__":
    sys.exit(main())
