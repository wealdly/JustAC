# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""One buff refresh window for every maintained buff: re-apply once the buff could lapse inside
the next fight. 30% of the buff's duration, capped by the likely fight length, read before the
pull from the target (boss, elite) and then the group. Loads the real functions from
BlizzardAPI/StateHelpers.lua.

Run: python tools/test_buff_refresh_window.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def buff_window_lua(api="LibStub('JustAC-BlizzardAPI')"):
    """The real GetLikelyFightSeconds / GetBuffRefreshWindow, installed on a stub BlizzardAPI
    for harnesses that load the callers without StateHelpers. Unit reads resolve at call
    time, so stubs defined later apply; a stub without a boss or group read answers no/solo."""
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("-- Buff refresh window:")
    end = source.index("--- Is the target immune to crowd control?")
    return ("do local BlizzardAPI = " + api + "\n"
            "BlizzardAPI.IsTargetBoss = BlizzardAPI.IsTargetBoss or function() return false end\n"
            "BlizzardAPI.IsGrouped = BlizzardAPI.IsGrouped or function() return false end\n"
            "local IsSecretValue = BlizzardAPI.IsSecretValue or function() return false end\n"
            "local math_min = math.min\n"
            # A new value per call: harness state changes between reads, so no moment memo.
            "local function GetTime() return {} end\n"
            "local function UnitCanAttack(...) return _G.UnitCanAttack(...) end\n"
            "local function UnitIsDead(...) return _G.UnitIsDead(...) end\n"
            "local function UnitClassification(...) return _G.UnitClassification(...) end\n"
            + source[start:end] + "\nend\n")


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        secret = {}
        state = {}
        BlizzardAPI = {
            IsSecretValue = function(x) return rawequal(x, secret) end,
            IsTargetBoss = function() return state.boss == true end,
            IsGrouped = function() return state.grouped end,
        }
        function UnitCanAttack() if state.attackError then error('denied') end return state.hostile end
        function UnitIsDead() return state.dead end
        function UnitClassification() return state.class end
    """)
    lua.execute(buff_window_lua("BlizzardAPI"))

    def window(setup, duration="nil"):
        lua.execute("state = {}; " + setup)
        return lua.eval(f"BlizzardAPI.GetBuffRefreshWindow({duration})")

    hour = "3600"
    for setup, expected, why in (
        ("", 30, "solo, no target: the solo fight"),
        ("state.grouped = nil", 30, "unknown group reads solo"),
        ("state.grouped = true", 60, "grouped, no target: a group fight"),
        ("state.hostile = true; state.class = 'normal'", 30, "a normal mob solo"),
        ("state.hostile = true; state.class = 'elite'", 60, "an elite solo fights longer"),
        ("state.hostile = true; state.class = 'rareelite'", 60, "a rare elite too"),
        ("state.hostile = true; state.class = 'elite'; state.boss = true", 180, "a targeted boss"),
        ("state.hostile = true; state.class = 'elite'; state.dead = true", 30, "a dead target says nothing"),
        ("state.hostile = false; state.class = 'elite'", 30, "a friendly target says nothing"),
        ("state.hostile = secret; state.class = 'elite'", 30, "an unreadable target says nothing"),
        ("state.attackError = true; state.grouped = true", 60, "a failed read falls to the group"),
        ("state.hostile = true; state.class = secret; state.grouped = true", 60, "unreadable class: group"),
    ):
        got = window(setup, hour)
        assert got == expected, (why, got)
    assert window("", "600") == 30, "a 10-minute buff solo: the fight cap"
    assert window("state.hostile = true; state.boss = true", "600") == 180, "a boss: 10-minute buff at 3 min"
    assert window("", "30") == 9, "a 30-second seal: 30% of its duration"
    assert abs(window("state.grouped = true", "180") - 54) < 1e-9, "Battle Shout in a group: 30%"
    assert window("") == 30, "unknown duration (weapon enchants): the cap alone"
    assert window("", "secret") == 30, "secret duration: the cap alone"
    assert window("", "0") == 30, "permanent: the cap alone"
    print("Buff refresh window: 30% of the buff, capped by the likely fight from target and group")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
