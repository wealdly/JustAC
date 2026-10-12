# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real role data, rotation filter, totem probe, defensive queue and default migration.
from pathlib import Path

from test_forever_defaults import load

ROOT = Path(__file__).resolve().parent.parent


def section(file, start, end):
    text = (ROOT / file).read_text(encoding="utf-8")
    return text[text.index(start):text.index(end, text.index(start))]


def main():
    lua = load(True)
    lua.execute("""
        function UnitClass() return "Shaman", "SHAMAN" end
        now, occupied, failed, missing, locked, ready, usable = 100, {}, false, false, false, true, true
        errors = {}
        function GetTime() return now end
        function UnitAffectingCombat() return true end
        function IsInGroup() return false end
        function geterrorhandler() return function(e) errors[#errors + 1] = e end end
        function GetTotemDuration(slot)
            if failed then error("totem read denied") end
            if missing then return nil end
            return {active = occupied[slot] == true}
        end
        function CreateFrame(kind)
            return {
                Hide = function() end,
                SetCooldownFromDurationObject = function(self, d) self.active = d.active end,
                IsShown = function(self) return self.active end,
                SetCooldown = function(self) self.active = false end,
            }
        end
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.IsForever = function() return LibStub("JustAC-SpellDB").IsForever() end
        B.IsSecretValue = function() return false end
        IsSecretValue = B.IsSecretValue
        B.ResolveSpellID = function(id) return id end
        B.IsSpellAvailable = function() return true end
        B.IsSpellReady = function() return ready end
        B.IsSpellUsable = function() return usable, not usable end
        B.IsSpellProcced = function() return false end
        B.IsPlayerAbilityLockout = function() return locked end
        C_Spell.IsSpellUsable = function() return usable, not usable end
        function IsPlayerAbilityLockout() return locked end
        function GetRedundancyFilter() return nil end
        SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue")
        SpellQueue._rotationIsCustom = false
        rotationFilterCache = {}
        BlizzardAPI = B
        SpellDB = LibStub("JustAC-SpellDB")
        RedundancyFilter = nil
    """)
    lua.execute((ROOT / "RotationImport.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    lua.execute(
        section("BlizzardAPI/CooldownTracking.lua", "local scratchCooldown", "\n--------------------------------------------------------------------------------\n-- Group buffs")
        + section("BlizzardAPI/CooldownTracking.lua", "local totemSlotMemo", "\n--- True while spellID"))
    lua.execute(section("BlizzardAPI/StateHelpers.lua", "function BlizzardAPI.CheckDefensiveSpellState", "\n--------------------------------------------------------------------------------\n-- Defensive Item"))
    lua.execute(section("SpellQueue.lua", "local function PassesRotationFilters", "\n-- Per-spell proc-priority")
                + "\nFilter = PassesRotationFilters")
    lua.execute((ROOT / "DefensiveEngine.lua").read_text(encoding="utf-8"))
    lua.execute("""
        DE = LibStub("JustAC-DefensiveEngine")
        DE.RegisterDefensivesForTracking = function() end
        profile = {defensives = {enabled = true, displayMode = "lowHealth", maxIcons = 4,
            classSpells = {SHAMAN_F = {defensiveSpells = {8004, 331, 8071}, groupHelpSpells = {}}}}}
        addon = {GetProfile = function() return profile end}
        function Next()
            now = now + 1
            wipe(rotationFilterCache)
        end
        function Queue(low, combat)
            Next()
            return DE.GetDefensiveSpellQueue(addon, low, combat)
        end
    """)
    count = 0

    def check(expression):
        nonlocal count
        assert lua.eval(expression), expression
        count += 1

    check('SpellDB.GetForeverAbilityRole(8154) == "protection"')
    check("SpellDB.GetForeverTotemSlot(8154) == 2")
    check("SpellDB.IsMaintainedProtection(8154)")
    for sid in (8071, 5277, 22812, 5384, 543, 6143, 6197, 5675, 2565):
        check(f"not Filter({sid}, profile)")
    for sid in (689, 6789, 1311606, 15237, 20925, 20230, 402927, 8042, 403):
        check(f"Filter({sid}, profile)")
    lua.execute("SpellQueue._rotationIsCustom = true; Next()")
    check("Filter(8071, profile)")
    lua.execute("SpellQueue._rotationIsCustom = false; Next()")
    check("Filter(8075, profile)")
    check("#Queue(false, true) == 1 and Queue(false, true)[1].spellID == 8071")
    check("Queue(true, true)[1].spellID == 8004 and Queue(true, true)[3].spellID == 8071")
    check("#Queue(false, false) == 1")
    lua.execute('profile.defensives.displayMode = "combatOnly"')
    check("#Queue(false, false) == 0")
    lua.execute('profile.defensives.displayMode = "lowHealth"; occupied[2] = true; Next()')
    check("not Filter(8075, profile)")
    check("#Queue(false, true) == 0")
    check("not BlizzardAPI.CheckDefensiveSpellState(8154, profile)")
    lua.execute("occupied[2] = false")
    check("#Queue(false, true) == 1")
    lua.execute("ready = false")
    check("#Queue(false, true) == 0")
    lua.execute("ready = true; usable = false")
    check("#Queue(false, true) == 0")
    lua.execute("usable = true; locked = true")
    check("#Queue(false, true) == 0")
    lua.execute("locked = false; failed = true")
    check("#Queue(false, true) == 0 and #errors == 1")
    check("#Queue(false, true) == 0 and #errors == 1")
    check("BlizzardAPI.IsTotemSlotOccupied(2) == nil")
    lua.execute("failed = false; missing = true")
    check("#Queue(false, true) == 1 and #errors == 1")
    lua.execute("missing = false; profile.defensives.maxIcons = 1")
    check("Queue(true, true)[1].spellID == 8004")
    lua.execute("profile.defensives.classSpells.SHAMAN_F.defensiveSpells = {8004, 331}")
    check("#Queue(false, true) == 0")

    for setup, expected in (
        ("{8004, 331, 20594, 1299026}", True),
        ("{331, 8004, 20594, 1299026}", False),
        ("{8004, 331}", False),
        ("{}", False),
    ):
        lua.execute(f"""
            profile.defensives.classSpells.SHAMAN_F = {{
                defensiveSpells = {setup}, emergencyPotionRemoved = true,
                groupHelpSpells = {{}}, groupHelpMoved = true
            }}
            DE.InitializeDefensiveSpells(addon)
            migrated = false
            for _, id in ipairs(profile.defensives.classSpells.SHAMAN_F.defensiveSpells) do
                if id == 8071 then migrated = true end
            end
        """)
        check(f"migrated == {'true' if expected else 'false'}")
    lua.execute("""
        profile.defensives.classSpells.SHAMAN_F.defensiveSpells = {8004, 331}
        DE.InitializeDefensiveSpells(addon)
    """)
    check("#profile.defensives.classSpells.SHAMAN_F.defensiveSpells == 2")

    lua.execute("BlizzardAPI.IsForever = function() return false end; occupied[2] = true; Next()")
    check("Filter(8071, profile) and Filter(8075, profile)")

    retail = load(False)
    for field in ("FOREVER_ABILITY_ROLES", "FOREVER_TOTEM_SLOTS", "FOREVER_MAINTAINED_PROTECTION"):
        assert retail.eval(f'LibStub("JustAC-SpellDB").{field} == nil')
        count += 1
    assert retail.eval('LibStub("JustAC-SpellDB").GetForeverAbilityRole(8071) == nil')
    print(f"forever protection: {count + 1} checks passed")


if __name__ == "__main__":
    main()
