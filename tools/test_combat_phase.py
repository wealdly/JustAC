# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Shared combat phase and group context helpers (BlizzardAPI/StateHelpers.lua):
# readable, secret, failed and missing group probes; the fight-ending test's positive
# reads; and the three phases with post-combat straddling the end of combat.
#
# Run: python tools/test_combat_phase.py
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent


def section(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def state_source():
    return (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")


def group_helpers_lua():
    """The real IsGrouped / GetGroupContext with their ReadableBool, as one chunk. The
    caller prefixes locals for BlizzardAPI and IsSecretValue in the same execute."""
    source = state_source()
    return (section(source, "local function ReadableBool(v)", "\nend\n") + "\nend\n"
            + section(source, "-- Group membership.", "\nfunction BlizzardAPI.IsUnitHealthBelow"))


def load():
    source = state_source()
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        BlizzardAPI = {}
        secret = {}
        now = 1000
        function IsSecretValue(v) return rawequal(v, secret) end
        function GetTime() return now end
        function Reset()
            groupValue, raidValue, groupError, raidError = false, false, false, false
            hasGroupAPI = true
            IsInGroup = function()
                if groupError then error("group read denied") end
                return groupValue
            end
            IsInRaid = function()
                if raidError then error("raid read denied") end
                return raidValue
            end
            inCombat, enemies, targetExists, attackable, boss = true, 1, true, true, false
            below, belowAsked = true, nil
            BlizzardAPI.GetEngagedEnemyCount = function() return enemies end
            BlizzardAPI.IsTargetBoss = function() return boss end
            BlizzardAPI.IsUnitHealthBelow = function(unit, pct)
                assert(unit == "target")
                belowAsked = pct
                return below
            end
        end
        function UnitAffectingCombat(unit) assert(unit == "player"); return inCombat end
        function UnitExists(unit) assert(unit == "target"); return targetExists end
        function UnitCanAttack(a, b) assert(a == "player" and b == "target"); return attackable end
    """)
    lua.execute(group_helpers_lua()
                + section(source, "local POSTCOMBAT_WINDOW_SECS", "\n-- Returns (percent, isEstimate)"))
    return lua


def main():
    lua = load()
    count = 0

    def check(setup, expression, why):
        nonlocal count
        lua.execute("Reset()\n" + setup)
        assert lua.eval(expression), (why, setup, expression)
        count += 1

    # Group context: unknown stays unknown, never solo.
    check("", 'BlizzardAPI.IsGrouped() == false and BlizzardAPI.GetGroupContext() == "solo"', "solo")
    check("groupValue = true", 'BlizzardAPI.IsGrouped() == true and BlizzardAPI.GetGroupContext() == "party"', "party")
    check("groupValue, raidValue = true, true", 'BlizzardAPI.GetGroupContext() == "raid"', "raid")
    check("groupValue = secret", 'BlizzardAPI.IsGrouped() == nil and BlizzardAPI.GetGroupContext() == nil',
          "secret group read")
    check("groupError = true", 'BlizzardAPI.IsGrouped() == nil and BlizzardAPI.GetGroupContext() == nil',
          "denied group read")
    check("IsInGroup = nil", 'BlizzardAPI.IsGrouped() == nil and BlizzardAPI.GetGroupContext() == nil',
          "missing group API")
    check("groupValue, raidValue = true, secret",
          'BlizzardAPI.IsGrouped() == true and BlizzardAPI.GetGroupContext() == nil',
          "grouped, raid unknown: grouped callers still answer, party/raid stays unknown")
    check("groupValue, raidError = true, true", 'BlizzardAPI.GetGroupContext() == nil', "denied raid read")
    check("raidValue = secret", 'BlizzardAPI.GetGroupContext() == "solo"', "solo never asks the raid probe")

    # Fight ending: every clause a positive read.
    check("", "BlizzardAPI.IsFightEnding() == true and belowAsked == 20", "last dying non-boss")
    check("enemies = 3", "BlizzardAPI.IsFightEnding(1) == true", "caller-supplied count wins")
    check("", "BlizzardAPI.IsFightEnding(2) == false", "two enemies")
    check("enemies = 0", "BlizzardAPI.IsFightEnding() == false", "uncounted is not one left")
    check("enemies = 2", "BlizzardAPI.IsFightEnding() == false", "pack")
    check("boss = true", "BlizzardAPI.IsFightEnding() == false", "dying boss is an execute phase")
    check("below = nil", "BlizzardAPI.IsFightEnding() == false", "unknown health")
    check("below = false", "BlizzardAPI.IsFightEnding() == false", "healthy target")
    check("targetExists = false", "BlizzardAPI.IsFightEnding() == false and belowAsked == nil", "no target")
    check("attackable = false", "BlizzardAPI.IsFightEnding() == false", "friendly target")

    # Phases: post-combat straddles the end of combat.
    check("", 'select(1, BlizzardAPI.GetCombatPhase()) == "postcombat" '
              'and select(2, BlizzardAPI.GetCombatPhase()) == "ending"', "ending half")
    check("below = false", 'BlizzardAPI.GetCombatPhase() == "combat" '
                           'and select(2, BlizzardAPI.GetCombatPhase()) == nil', "combat")
    check("inCombat = false", 'BlizzardAPI.GetCombatPhase() == "precombat"', "never left combat")
    check("inCombat = false; BlizzardAPI.NotePlayerLeftCombat(); now = now + 5",
          'BlizzardAPI.GetCombatPhase() == "postcombat" '
          'and select(2, BlizzardAPI.GetCombatPhase()) == "after"', "after half")
    check("inCombat = false; BlizzardAPI.NotePlayerLeftCombat(); now = now + 11",
          'BlizzardAPI.GetCombatPhase() == "precombat"', "window closed")
    check("BlizzardAPI.NotePlayerLeftCombat(); below = false",
          'BlizzardAPI.GetCombatPhase() == "combat"', "a new pull inside the window is combat")

    print(f"combat phase and group context: {count} checks passed")


if __name__ == "__main__":
    main()
