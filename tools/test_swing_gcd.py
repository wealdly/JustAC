# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The global cooldown length and the "swing more than a GCD away" check, from the source.

BlizzardAPI.GetGCDLength remembers the last GCD seen running on the reference spell (it reports
a duration only while one runs); SpellQueue._SwingFarOff compares the next main-hand swing with
it. Either unknown answers false, so the dying-target finisher rule changes nothing.

Run: python tools/test_swing_gcd.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    query = (ROOT / "BlizzardAPI" / "SpellQuery.lua").read_text(encoding="utf-8")
    start = query.index("--- The length of the global cooldown last seen running")
    end = query.index("\nend\n", query.index("function BlizzardAPI.GetGCDLength(")) + len("\nend\n")
    queue = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    q_start = queue.index("function SpellQueue._SwingFarOff(")
    q_end = queue.index("\nend\n", q_start) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        BlizzardAPI, SpellQueue = {}, {}
        gcdStart, gcdDur, swing, now = 0, 0, nil, 100
        function GetTime() return now end
        function BlizzardAPI.GetGCDInfo() return gcdStart, gcdDur end
        function BlizzardAPI.GetSwingRemaining(kind) assert(kind == 0); return swing end
    """ + query[start:end]
        + query[query.index("function BlizzardAPI.GetGCDRemaining("):query.index("function BlizzardAPI.GetGCDInfo(")]
        + queue[q_start:q_end])
    lua.execute("""
        assert(BlizzardAPI.GetGCDLength() == nil, "no GCD seen yet")
        swing = 3
        assert(SpellQueue._SwingFarOff() == false, "unknown GCD length: no change")
        gcdDur = 1.304
        assert(BlizzardAPI.GetGCDLength() == 1.304, "a running GCD sets the length (hasted)")
        gcdDur = 0
        assert(BlizzardAPI.GetGCDLength() == 1.304, "remembered while no GCD runs")
        assert(SpellQueue._SwingFarOff() == true, "swing 3s away, GCD 1.304s")
        swing = 1.2
        assert(SpellQueue._SwingFarOff() == false, "swing inside one GCD")
        gcdDur = 1.5
        swing = 1.4
        assert(SpellQueue._SwingFarOff() == false, "the length follows the GCD actually triggered")
        gcdDur = 60
        assert(BlizzardAPI.GetGCDLength() == 1.5, "an implausible reading is ignored")
        swing = nil
        assert(SpellQueue._SwingFarOff() == false, "not swinging: no change")
        -- Decided for the end of the running GCD: steady while it runs, so the answer changes
        -- when a swing lands, not as the clock ticks.
        gcdStart, gcdDur, now = 100, 1.5, 100.5          -- 1.0 s of GCD left
        swing = 2.4                                      -- 1.4 s away when the player can act
        assert(SpellQueue._SwingFarOff() == false, "inside one GCD of the next press")
        now, swing = 100.9, 2.0                          -- both counted down 0.4 s
        assert(SpellQueue._SwingFarOff() == false, "the same answer while the GCD runs")
        now, swing = 101.2, 2.6                          -- the swing landed; the next is far
        assert(SpellQueue._SwingFarOff() == true, "a landed swing changes it, once")
        now, swing = 101.3, 2.5
        assert(SpellQueue._SwingFarOff() == true, "and it holds")
        now, swing = 101.4, 0.3                          -- the swing lands before the GCD ends
        assert(SpellQueue._SwingFarOff() == false, "a swing due before the next press is not far")
    """)
    print("Swing and GCD: remembered GCD length, swing compared with it, unknowns change nothing")

    # Per-spell GCD: recorded when our own cast starts it; the DPS cycle never runs shorter.
    tracking = (ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    g_start = tracking.index("-- The global cooldown each spell triggers")
    g_end = tracking.index("--- Record a successful player cast")
    c_start = tracking.index("--- Per cycle: the cast time, but never less than the global cooldown")
    c_end = tracking.index("function BlizzardAPI.GetDirectSpellDPS(")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        now = 100
        function GetTime() return now end
        BlizzardAPI = {}
        IsSecretValue = function() return false end
        function PlainDamageNumber(v) return type(v) == "number" and v == v end
        function geterrorhandler() return function() end end
        gcdStart, gcdDur, lastSeen, casts = 0, 0, nil, {}
        function BlizzardAPI.GetGCDInfo() return gcdStart, gcdDur end
        function BlizzardAPI.GetGCDLength() return lastSeen end
        function BlizzardAPI.GetSpellInfo(id) return {castTime = casts[id]} end
        local RI = { RankBase = function(id) if id == 8402 then return 2136 end return id end }
        function LibStub(name) if name == "JustAC-RotationImport" then return RI end end
        local rotationImport
    """ + tracking[g_start:g_end] + tracking[c_start:c_end])
    lua.execute("""
        assert(BlizzardAPI.GetSpellGCD(2136) == nil, "nothing measured, nothing seen")
        lastSeen = 1.5
        assert(BlizzardAPI.GetSpellGCD(2136) == 1.5, "falls back to the last GCD seen")
        gcdStart, gcdDur = 99.9, 1.304
        BlizzardAPI.NoteCastGCD(8402)
        assert(BlizzardAPI.GetSpellGCD(8402) == 1.304 and BlizzardAPI.GetSpellGCD(2136) == 1.304,
            "a rank's measured GCD serves the whole chain")
        gcdStart, gcdDur = 98, 1.5
        BlizzardAPI.NoteCastGCD(585)
        assert(BlizzardAPI.GetSpellGCD(585) == 1.5, "not this cast's GCD: falls back, nothing recorded")
        lastSeen = nil
        assert(BlizzardAPI.GetSpellGCD(585) == nil, "and nothing was recorded for it")
        casts[2136], casts[585] = 0, 2500
        local cycle, cast = BlizzardAPI.GetSpellCycleSeconds(2136)
        assert(cycle == 1.304 and cast == 0, "an instant cycles at its own GCD")
        assert(BlizzardAPI.GetSpellCycleSeconds(585) == 2.5, "a long cast keeps its cast time")
        casts[585] = 1000
        assert(BlizzardAPI.GetSpellCycleSeconds(585) == 1.0, "no GCD known: cast time, as before")
        gcdStart, gcdDur = 99.8, 1.5
        BlizzardAPI.NoteCastGCD(585)
        assert(BlizzardAPI.GetSpellCycleSeconds(585) == 1.5, "a short cast never cycles faster than its GCD")
        casts[999] = 0
        assert(BlizzardAPI.GetSpellCycleSeconds(999) == nil, "an instant with no GCD known stays unknown")
    """)
    print("Spell GCD: measured per spell at its own cast, any rank; DPS cycle floored at it")

    o_start = queue.index("local UNHASTED_GCD_SECONDS = 1.5")
    o_end = queue.index("\nend\n", queue.index("function SpellQueue._OneGCD(")) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("BlizzardAPI, SpellQueue, seen = {}, {}, nil\n"
                "function BlizzardAPI.GetGCDLength() return seen end\n" + queue[o_start:o_end])
    lua.execute("""
        assert(SpellQueue._OneGCD() == 1.5, "no GCD seen: the unhasted 1.5s, as before")
        seen = 1.304
        assert(SpellQueue._OneGCD() == 1.304, "the brief-wait window follows the measured GCD")
    """)
    print("One GCD: measured length for the brief-wait window, unhasted 1.5s until seen")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
