# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Evidence grades and miss counts in DotTracker.lua (diagnostics; the queue does not decide
from them).

A DoT verdict carries how good its evidence is: "confirmed" when the game answered (Cooldown
Manager, an aura instance), "estimated" when it is our cast time plus a duration, "policy" for
immunity and "none" before any cast. Misses matched to a cast are counted with what makes the
match doubtful: grouped, our own melee swing in the window, a dodge or parry on a non-melee cast.

Run: python tools/test_evidence_grades.py
"""
import sys
from pathlib import Path

from lupa import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_forever_dots import PRELUDE, ROOT  # noqa: E402

REND = 772


def tracker():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().forever = True
    lua.execute(PRELUDE + """
        local B = LibStub("JustAC-BlizzardAPI")
        grouped, swingAt, maxRange, defense, speed = false, nil, 5, 2, 0
        B.IsSecretValue = function() return false end
        B.IsGrouped = function() return grouped end
        B.GetSwingWindow = function(swingType) if swingType == 0 then return swingAt end end
        B.GetCachedSpellInfo = function() return { maxRange = maxRange } end
        -- Defense type (1 magic, 2 melee, 3 ranged) and missile speed, as the spell data gives them.
        LibStub("JustAC-SpellDB").GetAuraDelivery = function() return defense, speed end
    """)
    lua.execute((ROOT / "DotTracker.lua").read_text(encoding="utf-8"))
    return lua, lua.eval('LibStub("JustAC-DotTracker")')


def main():
    count = 0

    def check(condition, why):
        nonlocal count
        assert condition, why
        count += 1

    lua, tracker_lib = tracker()
    g = lua.globals()

    def evidence():
        return tuple(tracker_lib.GetDotEvidence(REND))

    def miss(kind):
        lua.eval("handlers.UNIT_COMBAT")(None, "UNIT_COMBAT", "target", kind)

    check(evidence() == (False, "none", "untracked"), "before any cast there is no evidence")
    check(tuple(tracker_lib.GetDotEvidence(1)) == (False, "none", "not-tracked"), "an untracked spell has none")

    g.now = 10
    tracker_lib.OnCastSucceeded(REND)
    g.now = 11
    check(evidence() == (True, "estimated", "cast-estimate"), "a cast with no confirmation is an estimate")
    check(tracker_lib.IsDotActiveOnCurrentTarget(REND) is True, "the queue's verdict is unchanged")
    check(tracker_lib.GetTargetAuraState(REND, False) is None, "a prerequisite does not accept an estimate")
    check(tracker_lib.GetTargetAuraState(REND, True) is True, "a refresh policy does")

    g.tracked = True
    check(evidence() == (True, "confirmed", "cooldown-manager"), "the Cooldown Manager confirms it")
    check(tracker_lib.GetTargetAuraState(REND, False) is True, "confirmed evidence satisfies a prerequisite")
    g.tracked = False
    g.now = 20
    check(evidence() == (False, "confirmed", "cooldown-manager"), "and confirms it gone")
    g.tracked = None

    # Miss counts: a cancelled timer, with each doubt marker.
    stats = tracker_lib.DebugState().misses
    check(stats.matched == 0, "no miss matched yet")
    g.now = 30
    tracker_lib.OnCastSucceeded(REND)
    g.now = 30.05
    miss("DODGE")
    check((stats.matched, stats.cancelled, stats.kinds.DODGE) == (1, 1, 1), "a dodge in the window cancels and is counted")
    check((stats.grouped, stats.ownSwing, stats.dodgedMissile) == (0, 0, 0), "solo melee cast: no doubt markers")
    check(evidence() == (False, "none", "untracked"), "the cancelled timer leaves no evidence")

    # A swing that only just started has not reported yet: the result is the cast's.
    g.grouped, g.swingAt = True, 40.05
    g.now = 40
    tracker_lib.OnCastSucceeded(REND)
    g.now = 40.08
    miss("PARRY")
    check((stats.matched, stats.cancelled) == (2, 2), "second match counted")
    check((stats.grouped, stats.ownSwing, stats.dodgedMissile) == (1, 1, 0),
          "grouped and own swing in the window are each marked")

    # A spell is never parried or dodged: the timer stays, and a later resist still cancels it.
    g.grouped, g.swingAt, g.maxRange, g.defense = False, None, 30, 1
    g.now = 42
    tracker_lib.OnCastSucceeded(REND)
    g.now = 42.05
    miss("PARRY")
    miss("DODGE")
    check((stats.matched, stats.notOutcome) == (2, 2), "a parry or dodge is not a spell's result")
    check(evidence() == (True, "estimated", "cast-estimate"), "the spell's timer stays")
    miss("RESIST")
    check((stats.matched, stats.cancelled) == (3, 3), "a resist in the same window still cancels it")

    # A ranged attack: its dodge stays possible, a parry does not.
    g.defense, g.speed = 3, 40
    g.now = 44
    tracker_lib.OnCastSucceeded(REND)
    g.now = 44.1
    miss("PARRY")
    check(stats.notOutcome == 3, "a ranged attack is not parried")
    miss("DODGE")
    check((stats.matched, stats.dodgedMissile) == (4, 1), "its dodge is matched, and marked doubtful")

    # A white swing reports about 0.4s after it starts (measured 0.34 to 0.47s): a result
    # arriving then is the swing's, and the timer stays. That swing takes one result only.
    # A cast the spell data does not describe: the result window is the wide 0.4s one.
    g.defense, g.speed, g.swingAt = None, 0, 45.9
    g.now = 46
    tracker_lib.OnCastSucceeded(REND)
    g.now = 46.3
    miss("DODGE")
    check((stats.matched, stats.toSwing) == (4, 1), "a dodge 0.4s after our swing started is the swing's")
    check(evidence() == (True, "estimated", "cast-estimate"), "the melee DoT's timer stays")
    miss("DODGE")
    check((stats.matched, stats.toSwing) == (5, 1), "a second result goes to the cast")

    # The result arrives before the cast event, where the swing is due: the swing's on replay.
    g.swingAt = 47.6
    g.now = 48
    miss("MISS")
    g.now = 48.3
    tracker_lib.OnCastSucceeded(REND)
    check((stats.matched, stats.toSwing) == (5, 2), "replayed result keeps its own time")
    check(evidence() == (True, "estimated", "cast-estimate"), "and the timer stays")

    # A result sharing the timestamp of a cast with no missile is that cast's, even where a
    # swing is also due to report.
    g.defense, g.swingAt, g.now = 2, 48.2, 48.4
    tracker_lib.OnTargetChanged()
    tracker_lib.OnCastSucceeded(REND)
    g.now = 48.6
    tracker_lib.OnCastSucceeded(REND)
    miss("DODGE")
    check((stats.matched, stats.toSwing) == (6, 2), "same timestamp as an instant cast: the cast's")
    g.defense = None
    g.now = 48.61
    tracker_lib.OnCastSucceeded(REND)

    # A resist is never an auto attack's result.
    g.swingAt = 48.6
    g.now = 48.6
    miss("RESIST")
    check(stats.matched == 7, "a resist goes to the cast whatever the swing timing")

    # No flight: the result comes in the same instant, so one 0.2s later is someone else's.
    g.swingAt, g.maxRange, g.defense, g.speed = None, 5, 2, 0
    g.now = 49
    tracker_lib.OnCastSucceeded(REND)
    g.now = 49.2
    miss("DODGE")
    check(stats.matched == 7, "a result 0.2s after a cast with no flight is not that cast's")
    check(evidence() == (True, "estimated", "cast-estimate"), "its timer stays")

    # A ranged shot: nothing arrives before it is fired, or after its longest flight.
    g.maxRange, g.defense, g.speed = 35, 3, 40
    g.now = 49.5
    miss("MISS")
    g.now = 49.8
    tracker_lib.OnCastSucceeded(REND)
    check(stats.matched == 7, "a miss 0.3s before the shot is not replayed onto it")
    g.now = 51.1
    miss("MISS")
    check(stats.matched == 7, "a miss 1.3s after a 35 yard shot is past its flight")

    # The measured case: the shot's immunity arrives 0.78s after the cast.
    g.now = 52
    tracker_lib.OnCastSucceeded(REND)
    g.now = 52.78
    miss("IMMUNE")
    check((stats.matched, stats.immune) == (8, 1), "immunity is counted apart from cancels")
    check(evidence() == (True, "policy", "immune-policy"), "immunity is a policy, not an observation")

    # Measured on a second target: another attacker's miss arrives first, then the shot's
    # immunity. The miss cancels the timer; the immunity still registers.
    g.targetGUID = "Creature-B"
    tracker_lib.OnTargetChanged()
    g.now = 54
    tracker_lib.OnCastSucceeded(REND)
    g.now = 54.49
    miss("MISS")
    check(evidence() == (False, "none", "untracked"), "the earlier miss cancels the timer")
    miss("MISS")
    check(stats.matched == 9, "a second miss is not matched to the same cast")
    g.now = 54.66
    miss("IMMUNE")
    check((stats.matched, stats.immune) == (10, 2), "immunity after a miss in the window still registers")
    check(evidence() == (True, "policy", "immune-policy"), "and holds the shot back for this target")

    g.now = 60
    miss("MISS")
    check(stats.matched == 10, "a miss with no cast in the window is not matched")
    lua.eval("handlers.UNIT_COMBAT")(None, "UNIT_COMBAT", "target", "MISS", "", 0, 8)
    check(stats.schools["MISS/8"] == 1, "the school mask is counted per result")
    print(f"ok ({count} checks)")


if __name__ == "__main__":
    main()
