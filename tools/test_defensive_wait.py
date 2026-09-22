# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# "Wait until below" on the defensive list, checked outside the game.
#
# The health reading behind it is a secret-value workaround the game can block in some
# content or a future patch, so the rule that matters most is the one a player can never
# see fail: an UNREADABLE health must show the defensive, never hold it back. The other
# cases pin down how the per-ability setting sits over the list-wide Auto rule.
#
# Run: python tools/test_defensive_wait.py

import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "DefensiveEngine.lua"

PRELUDE = """
health = nil            -- what IsUnitHealthBelow answers: true / false / nil (unreadable)
exact = nil             -- what GetPlayerHealthPercentSafe answers: { pct, estimated } or nil
BlizzardAPI = {
    IsUnitHealthBelow = function(_, pct) return health and health(pct) end,
    GetPlayerHealthPercentSafe = function()
        if exact then return exact[1], exact[2] end
        return nil
    end,
}
holdWorthy, tiers = {}, {}
function IsHoldWorthy(id) return holdWorthy[id] == true end
function TierOf(id) return tiers[id] or 3 end
BAND_PANIC, healthBand, healthBandSource = 1, 4, "gate"
function entry(t) return t end
function waits(def, e, isLow)
    e.waiting = nil
    MarkWaiting(def, { e }, isLow)
    return e.waiting == true
end
"""


def extract(text):
    """From the potion id's declaration to the end of MarkWaiting."""
    start = text.index("local resolvedPotionID = nil")
    end = text.index("\nend\n", text.index("local function MarkWaiting(", start))
    block = text[start:end + len("\nend\n")]
    return (block.replace("local resolvedPotionID", "resolvedPotionID", 1)
                 .replace("local function WaitSetting", "function WaitSetting", 1)
                 .replace("local function PlayerBelow", "function PlayerBelow", 1)
                 .replace("local function AutoLive", "function AutoLive", 1)
                 .replace("local function MarkWaiting", "function MarkWaiting", 1))


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(extract(SRC.read_text(encoding="utf-8").replace("\r\n", "\n")))
    run = lua.eval("function(src) return assert(load(src))() end")
    bad = []

    def check(want, src, why):
        got = run(src)
        if want != got:
            bad.append("  FAIL %-58s got %r, want %r" % (why, got, want))

    run("def = { hideEmergencyUntilLow = true, spellSettings = {}, itemSettings = {} }")

    # A spell with its own 40% threshold.
    run("def.spellSettings[10] = { waitBelow = 40 }")
    run("health = function(pct) return 70 < pct end")        # at 70% health
    check(True, "return waits(def, entry{ spellID = 10 }, false)", "above the threshold: waits")
    run("health = function(pct) return 30 < pct end")        # at 30% health
    check(False, "return waits(def, entry{ spellID = 10 }, true)", "below the threshold: live")
    run("health = nil")                                      # the reading is blocked
    check(False, "return waits(def, entry{ spellID = 10 }, false)", "FAIL SAFE: unreadable health never holds it")
    run("exact = { 70, false }")                             # ...but the client hands over a percent
    check(True, "return waits(def, entry{ spellID = 10 }, false)", "blocked gate: an exact percent still decides")
    run("exact = { 30, true }")                              # only the vignette's guess
    check(False, "return waits(def, entry{ spellID = 10 }, false)", "FAIL SAFE: an estimate never holds it")
    run("exact = nil")

    # Stored under the id in the list, reached through the talent-swapped form.
    run("def.spellSettings[11] = { waitBelow = 40 }; health = function(pct) return 70 < pct end")
    check(True, "return waits(def, entry{ spellID = 99, storedID = 11 }, false)",
          "the list's id is found when a talent swaps the spell")

    # Never and Auto.
    run("def.spellSettings[12] = { waitBelow = 'off' }; holdWorthy[12] = true")
    check(False, "return waits(def, entry{ spellID = 12 }, false)", "never: a panic button stays live")
    run("holdWorthy[13] = true")
    check(True, "return waits(def, entry{ spellID = 13 }, false)", "auto: panic button waits above low")
    check(False, "return waits(def, entry{ spellID = 13 }, true)", "auto: ...and not once low")
    # Auto for an immunity bubble: live only in the worst band, when the band can see it.
    run("holdWorthy[14] = true; tiers[14] = 1; healthBand = 2")
    check(True, "return waits(def, entry{ spellID = 14 }, true)", "auto: a bubble still waits in the low band")
    run("healthBand = 1")
    check(False, "return waits(def, entry{ spellID = 14 }, true)", "auto: ...and goes live in the worst band")
    run("healthBand, healthBandSource = 2, 'vignette'")
    check(False, "return waits(def, entry{ spellID = 14 }, true)",
          "auto: a band that cannot see the worst grade keeps the old rule")
    run("healthBand, healthBandSource = 4, 'gate'")
    run("def.hideEmergencyUntilLow = false")
    check(False, "return waits(def, entry{ spellID = 13 }, false)", "auto: follows the list-wide switch")
    run("def.hideEmergencyUntilLow = true")

    # Items, and the Emergency Potion entry's own setting.
    run("def.itemSettings[500] = { waitBelow = 40 }")
    check(True, "return waits(def, entry{ spellID = 500, isItem = true }, false)", "an item's own threshold")
    run("resolvedPotionID = 600; def.emergencyPotionWaitBelow = 40")
    check(True, "return waits(def, entry{ spellID = 600, isItem = true }, true)",
          "the potion entry's threshold follows the pot it became")
    run("def.itemSettings[600] = { waitBelow = 'off' }")
    check(False, "return waits(def, entry{ spellID = 600, isItem = true }, true)",
          "...but that pot's own setting wins")

    # Exempt entries.
    check(False, "return waits(def, entry{ spellID = 10, isProcced = true }, false)", "a proc never waits")
    check(False, "return waits(def, entry{ spellID = 10, precombat = true }, false)", "a pre-combat buff never waits")

    for line in bad:
        print(line)
    print("defensive wait: 18 case(s), %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
