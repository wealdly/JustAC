# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Charge look-ahead: a spell that carries the player to the target (spell effect CHARGE) makes
the queue order melee abilities for arrival until the real melee reading confirms it, the target
changes, or the window passes. Loads the real functions from SpellQueueForever.lua.

Run: python tools/test_landing_lookahead.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "SpellQueueForever.lua").read_text(encoding="utf-8")
    start = source.index("-- Look-ahead: a spell that carries the player to the target")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        now, target, within5, secret = 100, "Creature-A", nil, {}
        function GetTime() return now end
        function UnitGUID(unit) assert(unit == "target"); return target end
        SpellQueue = {}
        SpellDB = {
            LandsAtTarget = function(id) return id == 100 or id == 6178 end,
            IsTargetWithin = function(yards) assert(yards == 5); return within5 end,
            GetEnergize = function(id)
                if id == 100 then return 1, 9 end
                if id == 6178 then return 1, 12 end
            end,
        }
        infos = {}
        BlizzardAPI = {
            IsSecretValue = function(v) return v == secret end,
            IsMeleeSwingSpell = function(id) return id == 6603 or id == 78 end,
            GetCachedSpellInfo = function(id) return infos[id] end,
        }
    """ + source[start:])
    lua.execute("""
        local Q = SpellQueue
        assert(Q._LandingInFlight(now) == false, "nothing cast")
        Q.NoteLandingCast(772)
        assert(Q._LandingInFlight(now) == false, "Rend does not carry the player")
        Q.NoteLandingCast(6178)
        assert(Q._LandingInFlight(now + 1) == true, "a higher Charge rank is in flight")
        within5 = false
        assert(Q._LandingInFlight(now + 1) == true, "still out of reach while flying")
        within5 = true
        assert(Q._LandingInFlight(now + 1) == false, "arrived: the real reading takes over")
        within5 = nil
        assert(Q._LandingInFlight(now + 1) == false, "and the landing is spent")
        Q.NoteLandingCast(100)
        assert(Q._LandingInFlight(now + 3) == true, "inside the window")
        assert(Q._LandingInFlight(now + 3.01) == false, "the window passed")
        Q.NoteLandingCast(100)
        target = "Creature-B"
        assert(Q._LandingInFlight(now + 1) == false, "a different target is not the one charged")
        target = secret
        Q.NoteLandingCast(100)
        assert(Q._LandingInFlight(now + 1) == false, "an unreadable target records nothing")
        -- The carrier's gain (spell data) is due on landing, and only while in flight.
        target = "Creature-A"
        Q.NoteLandingCast(6178)
        assert(Q._PendingGain(1, now + 1) == 12, "Charge rank 2: 12 rage due on landing")
        assert(Q._PendingGain(3, now + 1) == nil, "no energy due")
        within5 = true
        assert(Q._PendingGain(1, now + 1) == nil, "landed: the game's own reading takes over")
        within5 = nil
        -- Melee reach: swing spells, no reported maximum, or 5 yards or less.
        infos[1715] = {maxRange = 0}
        infos[772] = {maxRange = 5}
        infos[355] = {}
        infos[3018] = {maxRange = 30}
        infos[999] = {maxRange = secret}
        assert(Q._IsMeleeReach(78) and Q._IsMeleeReach(6603), "Attack and next-swing attacks")
        assert(Q._IsMeleeReach(1715) and Q._IsMeleeReach(772) and Q._IsMeleeReach(355), "melee-range spells")
        assert(not Q._IsMeleeReach(3018), "a ranged spell keeps its own reading")
        assert(not Q._IsMeleeReach(999), "a hidden range is not melee")
        assert(not Q._IsMeleeReach(12345), "an unknown spell is not melee")
    """)
    print("Charge look-ahead: data-marked closers, until arrival, same target, bounded window; melee reach")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
