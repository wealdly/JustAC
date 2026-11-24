# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Self-lockout hold (Weakened Soul, Forbearance): armed by a self-targeted SENT, started by
# the matching SUCCEEDED, parks the locked spells in the defensive queue for the lockout.
from pathlib import Path

from test_forever_defaults import load
from test_forever_protection import section

ROOT = Path(__file__).resolve().parent.parent


def setup(lua, cls="PRIEST"):
    lua.execute(f'cls = "{cls}"')
    lua.execute("""
        function UnitClass() return cls, cls end
        now, ready, usable = 100, true, true
        secret = {}
        function GetTime() return now end
        function UnitAffectingCombat() return true end
        function IsInGroup() return false end
        selfNames = {Me = true}
        function UnitIsUnit(a, b)
            if a == nil then error("bad unit") end
            return b == "player" and selfNames[a] == true
        end
        function CreateFrame() return {Hide = function() end} end
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.IsForever = function() return LibStub("JustAC-SpellDB").IsForever() end
        B.IsSecretValue = function(v) return rawequal(v, secret) end
        IsSecretValue = B.IsSecretValue
        B.Unsecret = function(v) if v == nil or B.IsSecretValue(v) then return nil end return v end
        B.ResolveSpellID = function(id) return id end
        B.IsSpellAvailable = function() return true end
        B.IsSpellReady = function() return ready end
        B.IsSpellUsable = function() return usable, not usable end
        B.IsSpellProcced = function() return false end
        B.PeekBaseCooldownSeconds = function() return 300 end
        B.IsPlayerAbilityLockout = function() return false end
        C_Spell.IsSpellUsable = function() return usable, not usable end
        function IsPlayerAbilityLockout() return false end
        function GetRedundancyFilter() return nil end
        MT = LibStub:NewLibrary("JustAC-MaintenanceTracker")
        SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue")
        SpellQueue._rotationIsCustom = false
        SpellQueue.ResolvePetRecoveryPick = function(spellID) return spellID end
        rotationFilterCache = {}
        BlizzardAPI = B
        SpellDB = LibStub("JustAC-SpellDB")
        RedundancyFilter = nil
    """)
    lua.execute((ROOT / "RotationImport.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    lua.execute(section("BlizzardAPI/StateHelpers.lua", "function BlizzardAPI.CheckDefensiveSpellState",
                        "\n--------------------------------------------------------------------------------\n-- Defensive Item"))
    lua.execute(section("SpellQueue.lua", "local function PassesRotationFilters", "\n-- Per-spell proc-priority")
                + "\nFilter = PassesRotationFilters")
    lua.execute((ROOT / "DefensiveEngine.lua").read_text(encoding="utf-8"))
    lua.execute("""
        DE = LibStub("JustAC-DefensiveEngine")
        DE.RegisterDefensivesForTracking = function() end
        profile = {defensives = {enabled = true, displayMode = "lowHealth", maxIcons = 4,
            classSpells = {PRIEST_F = {defensiveSpells = {17, 2061}, groupHelpSpells = {}},
                PALADIN_F = {defensiveSpells = {642, 498, 1022, 633}, groupHelpSpells = {}}}}}
        addon = {GetProfile = function() return profile end}
        local function Ids(onlyHeld)
            now = now + 0.5
            wipe(rotationFilterCache)
            local ids = {}
            for _, e in ipairs(DE.GetDefensiveSpellQueue(addon, true, true)) do
                if not onlyHeld or e.unusable then ids[#ids + 1] = e.spellID end
            end
            return table.concat(ids, ",")
        end
        function Queue() return Ids(false) end
        function Held() return Ids(true) end
    """)


def main():
    lua = load(True)
    setup(lua)
    count = 0

    def check(expression):
        nonlocal count
        assert lua.eval(expression), (expression, lua.eval("Queue()"))
        count += 1

    check("SpellDB.GetSelfLockout(17).aura == 6788")
    check("SpellDB.GetSelfLockout(10901).aura == 6788")   # a higher rank resolves to rank 1
    check("SpellDB.GetSelfLockout(2061) == nil")
    check('Queue() == "17,2061"')

    # A shield on another player holds nothing, even when it succeeds.
    lua.execute('DE.NoteSpellcastSent("Ally", "g1", 17)')
    check('DE.NoteSpellcastSucceeded("g1") == false and Queue() == "17,2061"')
    # Unknown identity holds nothing: secret name, secret spell, empty name.
    for args in ('secret, "g2", 17', '"Me", "g2", secret', '"", "g2", 17', '"Me", secret, 17'):
        lua.execute(f"DE.NoteSpellcastSent({args})")
        check('DE.NoteSpellcastSucceeded("g2") == false and Queue() == "17,2061"')
    # A refused ("immune") self-recast: SENT without SUCCEEDED starts nothing, and a later
    # unrelated success does not pick it up.
    lua.execute('DE.NoteSpellcastSent("Me", "g3", 17); DE.NoteSpellcastSent("Me", "g4", 2061)')
    check('DE.NoteSpellcastSucceeded("g3") == false and Queue() == "17,2061"')

    # A confirmed self-shield (any rank) parks it behind ready spells for 15s.
    lua.execute('DE.NoteSpellcastSent("Me", "g5", 10901)')
    check('DE.NoteSpellcastSucceeded("g5") == true')
    check('DE.IsSelfLockedOut(17) and DE.IsSelfLockedOut(10901)')
    check('Queue():sub(1, 4) == "2061"')
    lua.execute("now = now + 13")
    check('DE.IsSelfLockedOut(17)')
    lua.execute("now = now + 1.5")
    check('not DE.IsSelfLockedOut(17) and Queue() == "17,2061"')

    # A pure heal over time is held the same way after a self-cast: Renew ticks for 15s, and a
    # recast would only restart it. Heals with a direct part or a cooldown are not held.
    check("SpellDB.GetPureHotDuration(139) == 15 and SpellDB.GetPureHotDuration(6078) == 15")
    check("SpellDB.GetPureHotDuration(774) == 12")           # Rejuvenation
    check("SpellDB.GetPureHotDuration(2061) == nil")         # Flash Heal
    check("SpellDB.GetPureHotDuration(8936) == nil")         # Regrowth: a direct heal too
    check("SpellDB.GetPureHotDuration(408521) == nil")       # Riptide: paced by its cooldown
    lua.execute("profile.defensives.classSpells.PRIEST_F.defensiveSpells = {139, 2061}")
    check('Queue() == "139,2061"')
    lua.execute('DE.NoteSpellcastSent("Ally", "h1", 139)')
    check('DE.NoteSpellcastSucceeded("h1") == false and Queue() == "139,2061"')
    lua.execute('DE.NoteSpellcastSent("Me", "h2", 6078)')    # a higher rank holds every rank
    check('DE.NoteSpellcastSucceeded("h2") == true')
    check('DE.IsSelfLockedOut(139) and DE.IsSelfLockedOut(6078) and not DE.IsSelfLockedOut(2061)')
    check('Queue():sub(1, 4) == "2061" and Held() == "139"')
    lua.execute("now = now + 13")
    check('DE.IsSelfLockedOut(139)')
    lua.execute("now = now + 1.5")
    check('not DE.IsSelfLockedOut(139) and Queue() == "139,2061"')
    # A refresh lead (a cast time) shortens the hold by that much.
    lua.execute("""
        LibStub("JustAC-BlizzardAPI").GetPeriodicRefreshLead = function() return 2 end
        DE.NoteSpellcastSent("Me", "h3", 139)
    """)
    check('DE.NoteSpellcastSucceeded("h3") == true')
    lua.execute("now = now + 12")
    check('DE.IsSelfLockedOut(139)')
    lua.execute("now = now + 1.5")
    check('not DE.IsSelfLockedOut(139)')

    # Ended early (dispelled): only a tracked icon that showed it ticking and now shows it gone
    # ends the hold. An icon that never showed it, or does not answer, ends nothing.
    lua.execute("""
        LibStub("JustAC-BlizzardAPI").GetPeriodicRefreshLead = function() return 0 end
        iconSays = nil
        MT.IsTrackedAuraActive = function(id) if id == 139 then return iconSays end end
        DE.NoteSpellcastSent("Me", "h4", 139)
    """)
    check('DE.NoteSpellcastSucceeded("h4") == true and DE.IsSelfLockedOut(139)')
    lua.execute("iconSays = false; now = now + 0.1")
    check('DE.IsSelfLockedOut(139)')            # not seen ticking yet: the icon trails the cast
    lua.execute("iconSays = true; now = now + 0.1")
    check('DE.IsSelfLockedOut(139)')
    lua.execute("iconSays = false; now = now + 0.1")
    check('not DE.IsSelfLockedOut(139) and Queue() == "139,2061"')
    # A new cast starts over: the earlier sighting does not carry into it.
    lua.execute('DE.NoteSpellcastSent("Me", "h5", 139)')
    check('DE.NoteSpellcastSucceeded("h5") == true and DE.IsSelfLockedOut(139)')
    lua.execute("iconSays = secret; now = now + 0.1")
    check('DE.IsSelfLockedOut(139)')
    lua.execute("iconSays = nil; now = now + 16")
    check('not DE.IsSelfLockedOut(139)')

    # A leech DoT is a maintained DoT like any other (Devouring Plague, every rank); a
    # channeled leech (Drain Life) is not.
    check("SpellDB.IsTargetDot(2944) and SpellDB.IsTargetDot(19280) and SpellDB.GetTargetDotDuration(2944) == 24")
    check("not SpellDB.IsTargetDot(689)")

    # Retail: no PRIEST_F key, so no entry and no hold.
    retail = load(False)
    setup(retail)
    assert retail.eval("SpellDB.GetSelfLockout(17) == nil")
    retail.execute('DE.NoteSpellcastSent("Me", "r1", 17)')
    assert retail.eval('DE.NoteSpellcastSucceeded("r1") == false')
    count += 2

    # Forbearance: one cast holds Divine Shield, Divine Protection and Blessing of Protection.
    pal = load(True)
    setup(pal, "PALADIN")

    def pcheck(expression):
        nonlocal count
        assert pal.eval(expression), (expression, pal.eval("Queue()"))
        count += 1

    # The emergency order already puts the big cooldowns behind Lay on Hands; what the hold
    # changes is whether they read held (unusable).
    pcheck('Held() == ""')
    pcheck("SpellDB.GetSelfLockout(1020).aura == 25771")      # Divine Shield rank 2
    pcheck("SpellDB.GetSelfLockout(10278).aura == 25771")     # Blessing of Protection rank 3
    # Blessing of Protection on another player holds nothing.
    pal.execute('DE.NoteSpellcastSent("Ally", "p1", 1022)')
    pcheck('DE.NoteSpellcastSucceeded("p1") == false and Held() == ""')
    # Divine Shield is self-only: an empty or secret target name still holds all three.
    pal.execute('DE.NoteSpellcastSent("", "p2", 1020)')
    pcheck('DE.NoteSpellcastSucceeded("p2") == true')
    pcheck('Held() == "642,498,1022" and DE.IsSelfLockedOut(5599)')
    pal.execute("now = now + 60")
    pcheck('Held() == ""')
    pal.execute('DE.NoteSpellcastSent(secret, "p3", 498)')
    pcheck('DE.NoteSpellcastSucceeded("p3") == true and Held() == "642,498,1022"')
    pal.execute("now = now + 60")
    # Blessing of Protection on yourself (any rank) holds the other two as well.
    pal.execute('DE.NoteSpellcastSent("Me", "p4", 10278)')
    pcheck('DE.NoteSpellcastSucceeded("p4") == true and Held() == "642,498,1022"')
    pal.execute("now = now + 60")
    # Avenging Wrath gives Forbearance but is not blocked by it.
    pal.execute('DE.NoteSpellcastSent("", "p5", 407788)')
    pcheck('DE.NoteSpellcastSucceeded("p5") == true')
    pcheck('not DE.IsSelfLockedOut(407788) and Held() == "642,498,1022"')
    # Weakened Soul is a priest entry only.
    pcheck("SpellDB.GetSelfLockout(17) == nil")
    # A debuff that weakens the enemy (Hex of Weakness here) is held from your own cast for its
    # duration, whoever the target, and dropped on a new target: it says nothing about that one.
    check("SpellDB.GetEnemyMitigationDuration(9035) == 120 and SpellDB.GetEnemyMitigationDuration(19285) == 120")
    check("SpellDB.GetEnemyMitigationDuration(1160) == 45 and SpellDB.GetEnemyMitigationDuration(99) == 30")
    check("SpellDB.GetEnemyMitigationDuration(2061) == nil")
    lua.execute("LibStub('JustAC-BlizzardAPI').GetPeriodicRefreshLead = nil")
    lua.execute("profile.defensives.classSpells.PRIEST_F.defensiveSpells = {9035, 2061}")
    check('Queue() == "9035,2061"')
    lua.execute('DE.NoteSpellcastSent("Enemy Mob", "x1", 19284)')    # cast on an enemy, any rank
    check('DE.NoteSpellcastSucceeded("x1") == true')
    check('DE.IsSelfLockedOut(9035) and Held() == "9035" and Queue():sub(1, 4) == "2061"')
    lua.execute("now = now + 100")
    check('DE.IsSelfLockedOut(9035)')
    lua.execute("now = now + 21")
    check('not DE.IsSelfLockedOut(9035) and Queue() == "9035,2061"')
    lua.execute('DE.NoteSpellcastSent("Enemy Mob", "x2", 9035)')
    check('DE.NoteSpellcastSucceeded("x2") == true and DE.IsSelfLockedOut(9035)')
    lua.execute("DE.OnTargetChanged()")
    check('not DE.IsSelfLockedOut(9035) and Queue() == "9035,2061"')
    # An area debuff (Demoralizing Shout: every enemy within 10 yards) stays held on a new target
    # within its radius; one farther away, or out of any range read, gets it offered again.
    check("SpellDB.GetEnemyMitigationRadius(1160) == 10 and SpellDB.GetEnemyMitigationRadius(11556) == 10")
    check("SpellDB.GetEnemyMitigationRadius(99) == 10 and SpellDB.GetEnemyMitigationRadius(9035) == nil")
    lua.execute("within = {}; SpellDB.IsTargetWithin = function(y) return within[y] end")
    lua.execute('DE.NoteSpellcastSent("", "s1", 1160)')
    check('DE.NoteSpellcastSucceeded("s1") == true and DE.IsSelfLockedOut(1160)')
    lua.execute("within[10] = true; DE.OnTargetChanged()")
    check('DE.IsSelfLockedOut(1160)')
    lua.execute("within[10] = nil; now = now + 1")
    check('DE.IsSelfLockedOut(1160)')   # decided once, at the first read after the change
    lua.execute("within[10] = false; DE.OnTargetChanged()")
    check('not DE.IsSelfLockedOut(1160)')
    lua.execute('DE.NoteSpellcastSent("", "s2", 1160)')
    check('DE.NoteSpellcastSucceeded("s2") == true and DE.IsSelfLockedOut(1160)')
    lua.execute("within[10] = nil; DE.OnTargetChanged()")
    check('not DE.IsSelfLockedOut(1160)')   # no range read settles it: offered again
    # A heal over time held on yourself is not dropped by a new target.
    lua.execute("profile.defensives.classSpells.PRIEST_F.defensiveSpells = {139, 2061}")
    lua.execute('DE.NoteSpellcastSent("Me", "x3", 139)')
    check('DE.NoteSpellcastSucceeded("x3") == true')
    lua.execute("DE.OnTargetChanged()")
    check('DE.IsSelfLockedOut(139)')

    # Saved lists: one identical to any earlier default (the emergency potion aside) becomes the
    # current default once per version; an edited list stays.
    lua.execute("""
        SpellDB.EMERGENCY_POTION = SpellDB.EMERGENCY_POTION or -9000000
        local current = SpellDB.ResolveDefaults(SpellDB.CLASS_DEFENSIVE_DEFAULTS, "PRIEST_F", "PRIEST")
        currentText = table.concat(current, ",")
        function Saved(list)
            profile.defensives.classSpells.PRIEST_F = {defensiveSpells = list, groupHelpSpells = {}}
            DE.InitializeDefensiveSpells(addon)
            local out = {}
            for _, id in ipairs(profile.defensives.classSpells.PRIEST_F.defensiveSpells) do
                if id ~= SpellDB.EMERGENCY_POTION then out[#out + 1] = id end
            end
            return table.concat(out, ",")
        end
    """)
    check('Saved({17, 13908, 139, 2061, 20594, 1299026}) == currentText')               # the first default
    check('Saved({17, 13908, 2651, 139, 2061, 20594, 1299026, -9000000}) == currentText')   # the second, with a potion
    check('Saved({17, 13908, 139, 20594, 1299026}) == "17,13908,139,20594,1299026"')     # edited: kept
    check('currentText:find("9035") and currentText:find("2050")')                         # Hex, Lesser Heal
    print(f"self lockout: {count} checks passed")


if __name__ == "__main__":
    main()
