# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Attack vs Auto Shot in the redundancy filter (RedundancyFilter.lua), run outside the game
# against the real file. Swing range, IsCurrentSpell and IsAutoRepeatSpell are plain on Forever.
#
# Run: python tools/test_forever_autoattack.py
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
-- Everything past the auto-attack rules is out of scope here: unknown API reads as nil.
setmetatable(B, { __index = function() return function() return nil end end })
forever = false
B.IsForever = function() return forever end
inRange, attacking, shooting, knowsAutoShot = nil, false, false, true
B.IsTargetInSwingRange = function() return inRange end
C_Spell = {
    IsCurrentSpell = function() return attacking end,
    IsAutoRepeatSpell = function() return shooting end,
}
IsPlayerSpell = function(id) return id == 75 and knowsAutoShot end
GetTime = function() return 0 end
UnitAffectingCombat = function() return true end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
"""


def main():
    lua = LuaRuntime()
    lua.execute(PRELUDE)
    lua.execute((ROOT / "RedundancyFilter.lua").read_text(encoding="utf-8"))
    g = lua.globals()
    red = lua.eval('function(id) return (LibStub("JustAC-RedundancyFilter").IsSpellRedundant(id, {})) end')

    g.forever = True
    g.inRange = True
    assert not red(6603), "Attack in melee range"
    assert red(75), "Auto Shot in melee range (inside its minimum range)"
    g.inRange = False
    assert not red(75), "Auto Shot out of melee, not running"
    assert red(6603), "Attack out of melee range yields to Auto Shot"
    g.knowsAutoShot = False
    assert not red(6603), "no Auto Shot: Attack stays"
    g.inRange = None
    g.knowsAutoShot = True
    assert not red(6603), "no swing-range reading (retail): Attack stays"
    g.attacking = True
    assert not red(6603), "Forever: a running Attack stays (sunk, with its swing timer)"
    g.forever, g.inRange = False, None
    assert not red(6603), "retail: unchanged (no swing range), a running Attack stays"
    g.forever, g.inRange = True, False   # out of melee: Auto Shot range
    g.shooting = True
    assert not red(75), "a running Auto Shot stays (sunk, with its timer)"
    print("ok")


if __name__ == "__main__":
    main()
