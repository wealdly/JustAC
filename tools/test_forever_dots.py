# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# DoT timing from our own cast (DotTracker.lua), run outside the game against the real file:
# a DoT counts as up for its duration after the cast, a dodge / miss within the hit window
# (either order) cancels it, IMMUNE holds it sunk for the target, and Forever has no early
# refresh (retail un-sinks with 30% left).
#
# Run: python tools/test_forever_dots.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.GetDisplaySpellID = function(id) return id end
B.Unsecret = function(v) return v end
local SDB = LibStub:NewLibrary("JustAC-SpellDB")
SDB.IsForever = function() return forever end
SDB.IsTargetDot = function(id) return id == 772 end
SDB.GetTargetDotDuration = function(id) if id == 772 then return 9 end end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
now = 0
function GetTime() return now end
function UnitExists() return true end
targetGUID = "Creature-A"
function UnitGUID() return targetGUID end
handlers = {}
function CreateFrame()
    local f = {}
    function f:RegisterUnitEvent(e) self.event = e end
    function f:RegisterEvent(e) self.event = e end
    function f:SetScript(_, fn) handlers[self.event] = fn end
    return f
end
C_UnitAuras = {}
-- The Cooldown Manager's answer for a tracked spell: true / false / nil (not tracked).
tracked = nil
LibStub:NewLibrary("JustAC-MaintenanceTracker").IsTrackedAuraActive = function(_, diagnostic)
    if diagnostic then diagnostic.reason = trackedReason end
    return tracked
end
"""


def tracker(forever):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().forever = forever
    lua.execute(PRELUDE)
    lua.execute((ROOT / "DotTracker.lua").read_text(encoding="utf-8"))
    return lua, lua.eval('LibStub("JustAC-DotTracker")')


def main():
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    lua, D = tracker(True)
    g = lua.globals()

    def at(t):
        g.now = t

    def unit_combat(kind):
        lua.eval("handlers.UNIT_COMBAT")(None, "UNIT_COMBAT", "target", kind)

    def swap(guid):
        g.targetGUID = guid
        D.OnTargetChanged()

    at(0); D.OnCastSucceeded(772)
    at(5); check(D.IsDotActiveOnCurrentTarget(772) is True, "landed Rend counts as up mid-duration")
    at(8.5); check(D.IsDotActiveOnCurrentTarget(772) is True, "Forever: still sunk near the end (no early refresh)")
    at(9.1); check(D.IsDotActiveOnCurrentTarget(772) is False, "back once it runs out")

    D.Reset(); at(20); D.OnCastSucceeded(772); at(20.1); unit_combat("DODGE")
    check(D.IsDotActiveOnCurrentTarget(772) is False, "dodged right after the cast: not up")

    D.Reset(); at(30); unit_combat("PARRY"); at(30.1); D.OnCastSucceeded(772)
    check(D.IsDotActiveOnCurrentTarget(772) is False, "parry reported before the cast event: not up")

    D.Reset(); at(40); D.OnCastSucceeded(772); at(41); unit_combat("DODGE")
    check(D.IsDotActiveOnCurrentTarget(772) is True, "a later dodge (auto attack) leaves the timer alone")
    at(41.1); unit_combat("WOUND")
    check(D.IsDotActiveOnCurrentTarget(772) is True, "a hit is not a miss")

    D.Reset(); at(50); D.OnCastSucceeded(772); at(50.1); unit_combat("IMMUNE")
    at(200); check(D.IsDotActiveOnCurrentTarget(772) is True, "immune target: stays sunk")
    D.Reset(); check(D.IsDotActiveOnCurrentTarget(772) is False, "new target: immunity forgotten")

    # Has this DoT already run on the target? It stays true after the DoT ends.
    D.Reset(); check(D.HasRunOnTarget(772) is False, "never cast here: has not run")
    at(51); D.OnCastSucceeded(772); check(D.HasRunOnTarget(772) is True, "landed: has run")
    at(60.5); check(D.HasRunOnTarget(772) is True, "ran out: still has run on this target")
    D.Reset(); at(51); D.OnCastSucceeded(772); at(51.1); unit_combat("DODGE")
    check(D.HasRunOnTarget(772) is False, "dodged: it never ran")
    D.Reset(); at(51); D.OnCastSucceeded(772); at(51.1); unit_combat("IMMUNE")
    check(D.HasRunOnTarget(772) is False, "immune: it never ran")

    # Target swaps (plain GUIDs, Forever): each mob keeps its own Rend timer.
    D.Reset(); at(60); D.OnCastSucceeded(772)                # Rend on A
    at(62); swap("Creature-B")
    check(D.IsDotActiveOnCurrentTarget(772) is False, "swapped to B: no Rend on B")
    at(64); swap("Creature-A")
    check(D.IsDotActiveOnCurrentTarget(772) is True, "back on A inside 9s: A's Rend still counted")
    at(66); swap("Creature-B"); D.OnCastSucceeded(772)       # Rend on B too
    at(68); swap("Creature-A")
    check(D.IsDotActiveOnCurrentTarget(772) is True, "A and B each keep their own")
    at(69.5)
    check(D.IsDotActiveOnCurrentTarget(772) is False, "A's runs out on its own clock")
    lua.eval("handlers.PARTY_KILL")(None, "PARTY_KILL", "Player-1", "Creature-B")
    at(70); swap("Creature-B")
    check(D.IsDotActiveOnCurrentTarget(772) is False, "B died: its record is gone")
    # Secret GUIDs (retail NPCs): a swap starts fresh, as before.
    lua.execute("issecretvalue = function(v) return v == 'secret' end")
    D.Reset(); g.targetGUID = "secret"; D.OnTargetChanged(); at(80); D.OnCastSucceeded(772)
    at(81); swap("secret")
    check(D.IsDotActiveOnCurrentTarget(772) is False, "secret GUID: a swap cannot be told apart, starts fresh")
    lua.execute("issecretvalue = nil")

    # Tracked in the Cooldown Manager (Forever): Blizzard's icon is the answer, except that it
    # trails our own cast; inside the bridge window an inactive icon means "not applied yet".
    D.Reset(); g.tracked = False; at(90); D.OnCastSucceeded(772)
    check(D.IsDotActiveOnCurrentTarget(772) is True, "icon lagging the cast: just-cast DoT stays sunk through the GCD")
    check(D.GetTargetAuraState(772, True) is True, "refresh gates see the pending cast")
    check(D.GetTargetAuraState(772, False) is None, "a pending cast is not presence evidence")
    check(D.DebugState().entries[1].source == "cast-pending", "pending application is labeled")
    at(92.1)
    check(D.IsDotActiveOnCurrentTarget(772) is False, "icon never showed: not on the target, whatever the cast said")
    D.Reset(); g.tracked = False; at(93); D.OnCastSucceeded(772); at(93.1); unit_combat("DODGE")
    check(D.IsDotActiveOnCurrentTarget(772) is False, "a dodge inside the pending window re-offers at once")
    D.Reset(); g.tracked = True; at(94); D.OnCastSucceeded(772)
    check(D.IsDotActiveOnCurrentTarget(772) is True, "icon showing after the cast")
    g.tracked = False; at(94.5)
    check(D.IsDotActiveOnCurrentTarget(772) is False, "icon shown then gone: dropped, even inside the window")
    D.Reset(); g.tracked = False; at(95); D.OnCastSucceeded(772); swap("Creature-B")
    check(D.IsDotActiveOnCurrentTarget(772) is False, "pending cast does not follow a target swap")
    swap("Creature-A")
    D.Reset(); g.tracked = True
    check(D.IsDotActiveOnCurrentTarget(772) is True, "icon showing: up, even with no cast seen")
    D.Reset(); at(100); D.OnCastSucceeded(772); at(100.1); unit_combat("IMMUNE"); g.tracked = False
    check(D.IsDotActiveOnCurrentTarget(772) is True, "immune still wins: never re-offer on an immune mob")
    # A tracked NON-DoT with a debuff of its own (Thunder Clap's slow) is never "already ticking".
    D.Reset(); g.tracked = True
    check(D.IsDotActiveOnCurrentTarget(6343) is False, "Thunder Clap's icon showing must not sink it as a DoT")
    g.tracked = None

    # Provenance uses the same decision path, including pre-cast CDM reads.
    D.Reset()
    for tracked, expected, source in (
        (True, True, "cooldown-manager"),
        (False, False, "cooldown-manager"),
        (None, False, "untracked"),
    ):
        g.tracked = tracked
        g.trackedReason = "test-cdm-reason"
        state = D.DebugState(lua.table_from([772, 772]))
        check(len(state.entries) == 1, "precast candidates are deduplicated")
        entry = state.entries[1]
        check(entry.active is expected and entry.source == source, "exact decision provenance")
        check(entry.cooldownManager is tracked, "CDM tri-state preserved")
        check(entry.cooldownManagerReason == "test-cdm-reason", "CDM reason preserved")
        check(entry.confirmed is False and entry.expiresIn is None, "no invented cast or binding")
    D.OnCastSucceeded(772)
    entry = D.DebugState().entries[1]
    check(entry.source == "cast-estimate", "post-cast estimate is labeled")
    check(entry.active is D.IsDotActiveOnCurrentTarget(772), "diagnostic and queue agree")

    # Refresh lead (Forever): a cast-time DoT comes back its cast time before it runs out, so
    # the recast lands as the last tick goes; a stacking one a global cooldown earlier still.
    lua, D = tracker(True)
    g = lua.globals()
    lua.execute("""
        local B, SDB = LibStub("JustAC-BlizzardAPI"), LibStub("JustAC-SpellDB")
        SDB.IsTargetDot = function(id) return id == 772 or id == 348 or id == 414644 end
        SDB.GetTargetDotDuration = function(id) return ({[772] = 9, [348] = 15, [414644] = 15})[id] end
        SDB.IsStackingAura = function(id) return id == 414644 end
        B.GetPeriodicRefreshLead = function(id, stacking)
            local cast = ({[348] = 2})[id] or 0
            if stacking then cast = cast + 1.5 end
            return cast
        end
    """)
    at(0); D.OnCastSucceeded(348)
    at(12.9); check(D.IsDotActiveOnCurrentTarget(348) is True, "cast-time DoT: sunk until its cast time from the end")
    at(13.0); check(D.IsDotActiveOnCurrentTarget(348) is False, "cast-time DoT: back 2s (its cast) before it ends")
    check(D.DebugState().entries[1].refreshLead == 2, "probe shows the lead")
    D.Reset(); at(20); D.OnCastSucceeded(414644)
    at(33.4); check(D.IsDotActiveOnCurrentTarget(414644) is True, "stacking instant: sunk until a GCD from the end")
    at(33.5); check(D.IsDotActiveOnCurrentTarget(414644) is False, "stacking instant: back a GCD early")
    D.Reset(); at(40); D.OnCastSucceeded(772)
    at(48.9); check(D.IsDotActiveOnCurrentTarget(772) is True, "instant, not stacking: no lead")
    # Cooldown Manager icon still showing: the lead still brings a cast-time DoT back early.
    D.Reset(); g.tracked = True; at(50); D.OnCastSucceeded(348)
    at(62.9); check(D.IsDotActiveOnCurrentTarget(348) is True, "icon showing, outside the lead: up")
    at(63.0); check(D.IsDotActiveOnCurrentTarget(348) is False, "icon showing, inside the lead: refresh")
    check(D.GetTargetAuraState(348, True) is False, "refresh gates see the lead")
    check(D.GetTargetAuraState(348, False) is None, "a lead estimate is not absence evidence")
    D.Reset(); at(70); D.OnCastSucceeded(772)
    at(78.9); check(D.IsDotActiveOnCurrentTarget(772) is True, "icon showing, no lead: the icon decides")
    g.tracked = None
    # Engine timer, where an instance is held: seconds left against the lead.
    lua.execute("""
        local B = LibStub("JustAC-BlizzardAPI")
        B.GetAuraDurationObject = function() return {} end
        B.IsDurationBelowPercent = function() return false end
        B.IsDurationBelowSeconds = function(_, seconds) asked = seconds; return engineBelow end
    """)
    D.Reset(); at(80); D.OnCastSucceeded(348)
    D.OnTargetAuraUpdate("target", lua.eval("{addedAuras = {{auraInstanceID = 5}}}"))
    g.engineBelow = False; at(93)
    check(D.IsDotActiveOnCurrentTarget(348) is True and g.asked == 2,
          "engine: the aura's own seconds left against the cast-time lead")
    g.engineBelow = True
    check(D.IsDotActiveOnCurrentTarget(348) is False, "engine inside the lead: refresh")

    # Time left on my DoT (Ferocious Bite while Rip has 3+ seconds): my timer from the cast,
    # the engine's timer when an instance is held, none once it is known gone, else unknown.
    lua, D = tracker(True)
    g = lua.globals()
    check(D.IsTimeLeftBelow(772, 3) is None, "never cast on this target: unknown")
    at(0); D.OnCastSucceeded(772)
    at(5); check(D.IsTimeLeftBelow(772, 3) is False, "4s left: not below 3")
    at(6.5); check(D.IsTimeLeftBelow(772, 3) is True, "2.5s left: below 3")
    at(9.5); check(D.IsTimeLeftBelow(772, 3) is True, "run out: none left")
    check(D.IsTimeLeftBelow(772, 0) is True, "run out is below even zero")
    D.Reset(); g.tracked = False; at(20); D.OnCastSucceeded(772); at(23)
    check(D.IsTimeLeftBelow(772, 3) is True, "icon shows it gone: none left")
    g.tracked = None
    D.Reset(); at(30); D.OnCastSucceeded(772); at(30.1); unit_combat("IMMUNE")
    check(D.IsTimeLeftBelow(772, 3) is None, "immune target: unknown")
    lua.execute("""
        local B = LibStub("JustAC-BlizzardAPI")
        B.GetAuraDurationObject = function() return {} end
        B.IsDurationBelowSeconds = function(_, seconds) asked = seconds; return engineBelow end
    """)
    D.Reset(); at(40); D.OnCastSucceeded(772)
    D.OnTargetAuraUpdate("target", lua.eval("{addedAuras = {{auraInstanceID = 9}}}"))
    g.engineBelow = True; at(41)
    check(D.IsTimeLeftBelow(772, 3) is True and g.asked == 3, "engine timer decides over my estimate")
    g.engineBelow = False
    check(D.IsTimeLeftBelow(772, 3) is False, "engine: time to spare")

    # Stacks of my stacking target aura (Sunder Armor), counted from my landed casts.
    lua, D = tracker(True)
    g = lua.globals()
    lua.execute("""
        local SDB = LibStub("JustAC-SpellDB")
        SDB.IsTrackedTargetAura = function(id) return id == 7386 end
        SDB.GetTargetAuraDuration = function(id) if id == 7386 then return 30 end end
        SDB.GetStackingMax = function(id) if id == 7386 then return 5 end end
    """)
    check(D.GetOwnStacks(7386) is None, "never cast here: unknown")
    for i in range(1, 7):
        at(i); D.OnCastSucceeded(7386)
    check(D.GetOwnStacks(7386) == 5, "six landed casts: capped at five")
    at(6.1); unit_combat("PARRY")
    check(D.GetOwnStacks(7386) == 5, "a parried cast takes back only its own stack")
    D.Reset(); at(10); D.OnCastSucceeded(7386); at(11); D.OnCastSucceeded(7386)
    at(11.1); unit_combat("DODGE")
    check(D.GetOwnStacks(7386) == 1, "dodged second cast: one stack left")
    at(39.9); check(D.GetOwnStacks(7386) == 1, "the first stack keeps its own timer")
    at(40.1); check(D.GetOwnStacks(7386) == 0, "run out: none")
    at(50); D.OnCastSucceeded(7386)
    check(D.GetOwnStacks(7386) == 1, "after it ran out, a cast starts again at one")
    D.Reset(); at(60); D.OnCastSucceeded(7386); at(60.1); unit_combat("DODGE")
    check(D.GetOwnStacks(7386) is None, "first cast dodged: nothing there")
    check(D.GetOwnStacks(772) is None, "not a stacking aura: unknown")

    lua, D = tracker(False)
    check(D.IsTimeLeftBelow(772, 3) is None, "retail: no time-left reads")
    check(D.GetOwnStacks(7386) is None, "retail: no stack counting")
    lua.globals().now = 0; D.OnCastSucceeded(772)
    lua.globals().now = 6.5
    check(D.IsDotActiveOnCurrentTarget(772) is False, "retail: un-sinks inside the 30% refresh window")
    check(D.GetTargetAuraState(772, True) is None,
          "retail: a pandemic refresh verdict is not absence evidence for Forever prerequisites")
    check(D.DebugState().entries[1].source == "estimated-refresh", "retail refresh estimate labeled")
    check(D.DebugState().entries[1].cooldownManagerReason == "not-consulted",
          "retail does not add a CDM read to the gameplay path")
    check(lua.eval("handlers.UNIT_COMBAT") is None,
          "retail: no hit check (UNIT_COMBAT has no source there; a party member's parry would wipe timers)")
    lua.globals().now = 10; D.OnCastSucceeded(772)
    lua.globals().targetGUID = "Player-B"; D.OnTargetChanged()
    lua.globals().targetGUID = "Creature-A"; D.OnTargetChanged()
    check(D.IsDotActiveOnCurrentTarget(772) is False, "retail: a swap starts fresh, even with plain GUIDs")

    for forever in (True, False):
        lua, D = tracker(forever)
        lua.execute('LibStub("JustAC-SpellDB").IsTrackedTargetAura=function(id) return id == 6343 end')
        D.OnCastSucceeded(6343)
        D.OnCastSucceeded(999)
        entries = D.DebugState().entries
        check(len(entries) == 1 and entries[1].spellID == 6343,
              "only eligible maintenance casts start observations")
        check(D.IsDotActiveOnCurrentTarget(6343) is False,
              "observing a maintenance cast does not enable unconditional DoT suppression")
        expected = True if forever else None
        check(D.GetTargetAuraState(6343, True) is expected,
              "maintenance estimates stay scoped to the Forever observation policy")
        lua.globals().tracked = True
        check(D.IsDotActiveOnCurrentTarget(6343) is False,
              "CDM presence does not turn an observation-only spell into a DoT")
        check(D.GetTargetAuraState(999, True) is None,
              "untracked spells do not acquire CDM presence through the observation path")
        lua.globals().tracked = None
        D.Reset()
        lua.execute('LibStub("JustAC-SpellDB").GetTargetDotDuration=function() return nil end')
        lua.globals().now = 0
        D.OnCastSucceeded(772)
        lua.globals().now = 11.9
        check(D.IsDotActiveOnCurrentTarget(772) is True, "unknown duration: estimate lasts until 12s")
        lua.globals().now = 12
        check(D.IsDotActiveOnCurrentTarget(772) is False, "unknown duration: estimate expires at 12s")
        if forever:
            lua.globals().tracked = True
            check(D.IsDotActiveOnCurrentTarget(772) is True, "live CDM presence outlasts the fallback")
            lua.globals().tracked = False
            check(D.IsDotActiveOnCurrentTarget(772) is False, "live CDM absence overrides the estimate")
        lua.globals().tracked = None
        lua.execute('LibStub("JustAC-SpellDB").GetTargetDotDuration=function() return 60 end')
        D.Reset()
        lua.globals().now = 0
        D.OnCastSucceeded(772)
        lua.globals().now = 35
        check(D.IsDotActiveOnCurrentTarget(772) is True, "known duration is not capped by fallback")
        lua.globals().now = 60 if forever else 42
        check(D.IsDotActiveOnCurrentTarget(772) is False, "known duration retains client refresh policy")

    for why in bad:
        print("  FAIL", why)
    print("forever dots: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
