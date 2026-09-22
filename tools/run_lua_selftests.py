# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Runs a module's SelfTest() OUTSIDE the game, in an embedded Lua with the handful of
# WoW globals it touches stubbed out. Lets the pure-logic self-checks - the ones that
# otherwise only run via /jac inspect - fail a commit instead of a raid night.
#
# Only modules whose logic is self-contained qualify: a ring buffer, a comparison, a
# parser. Anything that reads real combat state cannot be faked honestly and is left to
# the in-game command. Add one by naming it in MODULES below; it needs a SelfTest()
# returning true/false and must not call the WoW API at file scope beyond the stubs here.
#
# Run: python tools/run_lua_selftests.py

import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

REPO = Path(__file__).resolve().parent.parent

# module file -> the library name it registers (LibStub:NewLibrary)
MODULES = {
    "FightWindow.lua": "JustAC-FightWindow",
}

# The WoW globals the listed modules touch. Deliberately tiny: every stub is a place the
# harness can disagree with the game, so a module needing more than this does not belong here.
PRELUDE = """
local now = 0
function GetTime() return now end
function _SetTime(t) now = t end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local libs = {}
LibStub = setmetatable({
    NewLibrary = function(_, name, _minor) libs[name] = libs[name] or {}; return libs[name] end,
    GetLibrary = function(_, name, silent)
        if not libs[name] and not silent then error("missing library " .. tostring(name)) end
        return libs[name]
    end,
}, { __call = function(self, name, silent) return self:GetLibrary(name, silent) end })
-- Stand-in for the addon's own API surface. Identity resolution: no override chain
-- offline, which is what a self-check should assume rather than invent.
libs["JustAC-BlizzardAPI"] = {
    ResolveBaseSpellID = function(id) return id end,
    GetDisplaySpellID = function(id) return id end,
}
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    failures = 0
    for filename, libname in MODULES.items():
        path = REPO / filename
        if not path.exists():
            print(f"  {filename:24} SKIP (not in this branch)")
            continue
        try:
            lua.execute(path.read_text(encoding="utf-8"))
            lib = lua.eval(f'LibStub("{libname}", true)')
            if lib is None or lib.SelfTest is None:
                print(f"  {filename:24} SKIP (no SelfTest)")
                continue
            ok = lib.SelfTest()
        except Exception as exc:  # noqa: BLE001 - report which module, then carry on
            print(f"  {filename:24} ERROR {exc}")
            failures += 1
            continue
        print(f"  {filename:24} {'pass' if ok else 'FAIL'}")
        failures += 0 if ok else 1
    if failures:
        sys.exit(f"{failures} self-check(s) failed")
    print("all self-checks passed")


if __name__ == "__main__":
    main()
