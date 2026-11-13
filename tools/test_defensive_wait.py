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
    ResolveSpellID = function(id) return id end,
    IsUnitHealthBelow = function(_, pct) return health and health(pct) end,
    GetPlayerHealthPercentSafe = function()
        if exact then return exact[1], exact[2] end
        return nil
    end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
holdWorthy, tiers, autoLevels = {}, {}, {}
SpellDB = { GetDefaultWaitBelow = function(id) return autoLevels[id] end }
function IsHoldWorthy(id) return holdWorthy[id] == true end
function TierOf(id) return tiers[id] or 3 end
BAND_PANIC, healthBand, healthBandSource = 1, 4, "gate"
function entry(t) return t end
function waits(def, e, isLow) return EntryWaits(def, e, isLow) end
function sunk(def, list, isLow) return table.concat(SinkWaiting(def, list, isLow), ",") end
"""


def extract(text):
    """From the potion id's declaration to the end of SinkWaiting."""
    start = text.index("local resolvedPotionID = nil")
    end = text.index("\nend\n", text.index("local function SinkWaiting(", start))
    block = text[start:end + len("\nend\n")]
    return (block.replace("local resolvedPotionID", "resolvedPotionID", 1)
                 .replace("local function WaitSetting", "function WaitSetting", 1)
                 .replace("local function PlayerBelow", "function PlayerBelow", 1)
                 .replace("local function AutoLive", "function AutoLive", 1)
                 .replace("local function AutoWaitBelow", "function AutoWaitBelow", 1)
                 .replace("local function EntryWaits", "function EntryWaits", 1)
                 .replace("local function SinkWaiting", "function SinkWaiting", 1))


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(extract(SRC.read_text(encoding="utf-8").replace("\r\n", "\n")))
    run = lua.eval("function(src) return assert(load(src))() end")
    bad = []
    cases = 0

    def check(want, src, why):
        nonlocal cases
        cases += 1
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

    # Auto with a level of its own (a cheap heal at 80%, say).
    run("autoLevels[15] = 80")
    run("health = function(pct) return 95 < pct end")        # at 95% health
    check(True, "return waits(def, entry{ spellID = 15 }, false)", "auto level: waits above it")
    run("health = function(pct) return 70 < pct end")        # at 70% health
    check(False, "return waits(def, entry{ spellID = 15 }, false)", "auto level: live below it")
    run("health = nil")
    check(False, "return waits(def, entry{ spellID = 15 }, false)", "FAIL SAFE: unreadable health never holds an auto level")
    run("exact = { 70, true }")
    check(False, "return waits(def, entry{ spellID = 15 }, false)", "FAIL SAFE: an estimate never holds an auto level")
    run("exact = nil; health = function(pct) return 95 < pct end")
    check(True, "return waits(def, entry{ spellID = 99, storedID = 15 }, false)", "auto level: found through a talent swap")
    run("holdWorthy[15] = true")
    check(True, "return waits(def, entry{ spellID = 15 }, true)", "auto level: beats the low-band rule for a panic button")
    run("def.spellSettings[15] = { waitBelow = 'off' }")
    check(False, "return waits(def, entry{ spellID = 15 }, false)", "auto level: the player's own setting wins")
    run("def.spellSettings[15] = nil; def.hideEmergencyUntilLow = false")
    check(False, "return waits(def, entry{ spellID = 15 }, false)", "auto level: follows the list-wide switch")
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

    # Ordering: entries that wait move behind the live ones before the cluster is cut.
    run("autoLevels = {}; holdWorthy = {}; def.spellSettings = { [2] = { waitBelow = 40 } }")
    run("health = function(pct) return 70 < pct end")        # at 70% health
    check("1,3,2", "return sunk(def, {1,2,3}, false)", "a waiting entry sinks behind the live ones")
    run("health = nil")
    check("1,2,3", "return sunk(def, {1,2,3}, false)", "FAIL SAFE: unreadable health keeps the order")

    # Exempt entries.
    check(False, "return waits(def, entry{ spellID = 10, isProcced = true }, false)", "a proc never waits")
    check(False, "return waits(def, entry{ spellID = 10, precombat = true }, false)", "a pre-combat buff never waits")

    # Use the production defaults and lookup, including Forever rank resolution.
    spellDB = (SRC.parent / "SpellDB.lua").read_text(encoding="utf-8")
    lookupStart = spellDB.index("local RotationImport_")
    lookupEnd = spellDB.index("\nSpellDB.StaticLookup =", lookupStart)
    defaultsStart = spellDB.index("local CAST_TIME_HEALS = {")
    defaultsEnd = spellDB.index("\nend\n", spellDB.index("function SpellDB.GetDefaultWaitBelow(", defaultsStart))
    run("""
        function LibStub()
            return { RankBase = function(id)
                if id == 900635 then return 635 end
                if id == 9002061 then return 2061 end
                return id
            end }
        end
        SpellDB.GetSpecKey = function() return "PALADIN_1" end
    """)
    lua.execute(spellDB[lookupStart:lookupEnd] + "\n"
                + spellDB[defaultsStart:defaultsEnd + len("\nend\n")])
    castHealIDs = (331, 596, 635, 1064, 2060, 2061, 5185, 8004, 8936, 19750,
                   32546, 50464, 77472, 82326, 116670, 124682, 186263, 194509,
                   265202, 399491, 900635, 9002061)
    for sid in castHealIDs:
        check(60, f"return SpellDB.GetDefaultWaitBelow({sid})",
              f"cast-time heal {sid}: shared default is 60%")
        run("def = { hideEmergencyUntilLow = true, spellSettings = {} }; exact = nil")
        for pct, expected in ((100, True), (60, True), (59, False)):
            run(f"health = function(threshold) return {pct} < threshold end")
            check(expected, f"return waits(def, entry{{ spellID = {sid} }}, false)",
                  f"cast-time heal {sid}: {pct}% health")
        run("health = function(threshold) return 100 < threshold end")
        check(False, f"return waits(def, entry{{ spellID = {sid}, isProcced = true }}, false)",
              f"cast-time heal {sid}: proc handling preserved")
        check(False, f"return waits(def, entry{{ spellID = {sid}, precombat = true }}, false)",
              f"cast-time heal {sid}: precombat handling preserved")
        run("health = nil")
        check(False, f"return waits(def, entry{{ spellID = {sid} }}, false)",
              f"cast-time heal {sid}: unknown health")
        run("health = function(threshold) return 100 < threshold end")
        run(f"def.spellSettings[{sid}] = {{ waitBelow = 'off' }}")
        check(False, f"return waits(def, entry{{ spellID = {sid} }}, false)",
              f"cast-time heal {sid}: explicit off wins")
        run(f"def.spellSettings[{sid}] = {{ waitBelow = 80 }}")
        run("health = function(threshold) return 70 < threshold end")
        check(False, f"return waits(def, entry{{ spellID = {sid} }}, false)",
              f"cast-time heal {sid}: explicit 80% wins")
        run("def.spellSettings = {}; def.hideEmergencyUntilLow = false")
        run("health = function(threshold) return 100 < threshold end")
        check(False, f"return waits(def, entry{{ spellID = {sid} }}, false)",
              f"cast-time heal {sid}: list-wide switch respected")

    for sid, expected in ((774, 90), (85673, 80), (633, 25), (370960, 50),
                          (234153, 60), (53563, None), (116680, None),
                          (198898, None), (6603, None), (999999, None)):
        check(expected, f"return SpellDB.GetDefaultWaitBelow({sid})",
              f"non-cast-heal {sid}: existing default preserved")
    run('SpellDB.GetSpecKey = function() return "DEATHKNIGHT_1" end')
    check(None, "return SpellDB.GetDefaultWaitBelow(49998)",
          "Blood Death Strike keeps its no-threshold override")
    run('SpellDB.GetSpecKey = function() return "PALADIN_2" end')
    check(25, "return SpellDB.GetDefaultWaitBelow(642)",
          "Protection Divine Shield keeps its emergency override")

    for line in bad:
        print(line)
    print("defensive wait: %d case(s), %d failure(s)" % (cases, len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
