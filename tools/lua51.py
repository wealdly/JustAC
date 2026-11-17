# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Compile Lua source with a real Lua 5.1 (lupa), the runtime WoW uses.

Lua 5.1 enforces per-function limits at compile time (60 upvalues, 200 locals, the main chunk
included); crossing one kills the whole file in game. A compile here is the ground truth for
all of them. Shared by tools/luasyntax.py (the check.ps1 gate) and tools/deploy_runtime.py.
"""

_compile = None


def lua51_compile_error(src, name):
    """The Lua 5.1 compile error for `src`, None when it compiles, or False when no Lua 5.1
    runtime is installed (pip install lupa)."""
    global _compile
    if _compile is None:
        try:
            from lupa.lua51 import LuaRuntime  # type: ignore[import-not-found]
            _compile = LuaRuntime(unpack_returned_tuples=True).eval(
                "function(src, name) local f, err = loadstring(src, '@' .. name); return err end")
        except Exception:
            _compile = False
    if _compile is False:
        return False
    return _compile(src, name)
