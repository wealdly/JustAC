# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real rotation-pool API with controlled player spellbook and bar contents.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({NewLibrary=function(_, name)
    libs[name] = libs[name] or {}; return libs[name]
end}, {__call=function(_, name) return libs[name] end})
B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.IsSecretValue = function() return false end
local S = LibStub:NewLibrary("JustAC-SpellDB")
local RI = LibStub:NewLibrary("JustAC-RotationImport")
local ace = LibStub:NewLibrary("AceAddon-3.0")
ace.GetAddon = function() return {db={profile={contextOrder="simc"}}} end
forever = true
S.IsForever = function() return forever end
local function Base(id) if id == 1757 then return 1752 end return id end
RI.RankBase = Base
RI.RankChain = function(id) if Base(id) == 1752 then return {1752,1757} end end
RI.HighestKnownRank = function() return 1757 end
RI.IsClassAbility = function(id) return id ~= 999 and id ~= 1000 end
RI.GetInsertable = function() return {53} end
B.ResolveKnownSpellID = function(id) return id end
B.ResolveSpellID = function(id) return id end
S.IsOffensiveSpell = function() return true end
function wipe(t) for k in pairs(t) do t[k] = nil end end
errors = {}
function geterrorhandler() return function(e) errors[#errors+1] = e end end
Enum = {SpellBookSpellBank={Player=0}, SpellBookItemType={Spell=1,Flyout=2,FutureSpell=3}}
Enum.ItemClass, Enum.ItemWeaponSubclass = {Weapon=2}, {Thrown=16}
C_Item = {
    GetItemSubClassInfo=function(class,subclass)
        assert(class==2 and subclass==16)
        return "localized thrown"
    end,
    IsEquippedItemType=function(name) return thrownEquipped and name=="localized thrown" end,
}
thrownEquipped = true
bars = {[1]={"macro",42}, [2]={"spell",1752}}
function HasAction(slot) return bars[slot] ~= nil end
function GetActionInfo(slot) return table.unpack(bars[slot]) end
known = {[1752]=true,[1757]=true,[2764]=true,[53]=true,[777]=true,[999]=true,[888]=true}
function IsSpellKnown(id) return known[id] == true end
function IsPlayerSpell(id) return known[id] == true end
C_Spell = {IsSpellPassive=function(id) return id == 777 end}
lines = {{itemIndexOffset=0,numSpellBookItems=3},{itemIndexOffset=10,numSpellBookItems=5}}
slots = {
    [1]={itemType=1,spellID=2764},
    [2]={itemType=1,spellID=777,isPassive=true},
    [3]={itemType=1,spellID=1757},
    [11]={itemType=1,spellID=999},
    [12]={itemType=3,spellID=666},
    [13]={itemType=1,spellID=888,isOffSpec=true},
    [14]={itemType=2,actionID=7},
    [15]={itemType=1,spellID=1000},
}
reads, failRead = 0, false
C_SpellBook = {
    GetNumSpellBookSkillLines=function() reads=reads+1; return #lines end,
    GetSpellBookSkillLineInfo=function(line) return lines[line] end,
    GetSpellBookItemInfo=function(slot,bank)
        assert(bank==0, "only the player spellbook belongs in the DPS pool")
        if failRead then error("spellbook denied") end
        return slots[slot]
    end,
}
function GetFlyoutInfo() return "flyout","",2,true end
function GetFlyoutSlotInfo(_,slot)
    if slot==1 then return 53,nil,true end
    return 666,nil,false
end
C_AssistedCombat = {GetRotationSpells=function() return {123} end}
"""


def test_options_spellbook():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute("""
        petKnown = {}
        IsSpellKnown = function(id, pet)
            if pet then return petKnown[id] == true end
            return known[id] == true
        end
    """)
    lua.execute((ROOT / "BlizzardAPI" / "SpellQuery.lua").read_text(encoding="utf-8"))
    lua.execute("""
        SpellSearch, SpellDB, L = {}, {}, {}
        BlizzardAPI = B
        Enum.SpellBookSpellBank.Pet = 1
        petKnown, petSlots = {[501]=true}, {[1]={itemType=1,spellID=501}}
        C_Spell.GetSpellInfo = function(id) return {name='Spell '..id,iconID=id} end
        C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
            if bank == 1 then return petSlots[slot] end
            return slots[slot]
        end
        slots[15].isPassive = true
        known[1000] = true
        slots[16] = {itemType=1,spellID=12345}
        lines[2].numSpellBookItems = 6
    """)
    source = (ROOT / "Options" / "SpellSearch.lua").read_text(encoding="utf-8")
    start = source.index("local spellbookCache =")
    end = source.index("\n-- Get filtered results:", start)
    block = source[start:end].replace("local function SearchSpells(", "function SearchSpells(", 1)
    lua.execute(block)
    for forever in (False, True):
        lua.globals().forever = forever
        lua.execute("B.ClearAvailabilityCache(); SpellSearch.InvalidateSpellbookCache()")
        lua.globals().SpellSearch.BuildSpellbookCache()
        results = lua.table()
        lua.globals().SearchSpells("Spell", "spell", lua.table(), results)
        assert set(results.keys()) == {2764, 1757, 999, 501}, set(results.keys())
        reads = lua.globals().reads
        lua.globals().SpellSearch.BuildSpellbookCache()
        assert lua.globals().reads == reads, "options should reuse its spellbook cache"
        lua.execute("""
            known[2764] = false; known[12345] = true
            petKnown = {[502]=true}; petSlots = {[1]={itemType=1,spellID=502}}
            B.ClearAvailabilityCache(); SpellSearch.InvalidateSpellbookCache()
        """)
        lua.globals().SpellSearch.BuildSpellbookCache()
        results = lua.table()
        lua.globals().SearchSpells("Spell", "spell", lua.table(), results)
        assert set(results.keys()) == {1757, 999, 12345, 502}
        lua.execute("""
            known[2764] = true; known[12345] = nil
            petKnown = {[501]=true}; petSlots = {[1]={itemType=1,spellID=501}}
        """)
    core = (ROOT / "JustAC.lua").read_text(encoding="utf-8")
    start = core.index("function JustAC:OnPetChanged(")
    end = core.index("\nfunction JustAC:OnEquipmentChanged", start)
    lua.execute("""
        JustAC = {}
        updates = 0
        JustAC.OnHealthChanged = function() end
        JustAC.ForceUpdateAll = function() updates = updates + 1 end
    """)
    lua.execute(core[start:end])
    lua.execute("petKnown = {[502]=true}; petSlots = {[1]={itemType=1,spellID=502}}")
    lua.globals().JustAC.OnPetChanged(lua.globals().JustAC, "UNIT_PET", "player")
    lua.globals().SpellSearch.BuildSpellbookCache()
    results = lua.table()
    lua.globals().SearchSpells("Spell", "spell", lua.table(), results)
    assert 502 in results and 501 not in results, "pet swaps refresh searchable learned abilities"
    assert lua.globals().updates == 1


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "BlizzardAPI" / "SpellQuery.lua").read_text(encoding="utf-8"))
    g = lua.globals()

    def pool(game_only=False):
        return list(g.B.GetRotationSpells(game_only).values())

    assert pool() == [1752, 2764, 53], "macro-only Throw and known flyout enter; bar rank wins"
    assert pool(True) == [1752, 2764, 53], "baseline/priority tools see learned abilities too"
    assert g.reads == 1, "spellbook discovery is cached"
    lua.execute("bars={}; B.InvalidateBarSpells()")
    assert pool() == [2764, 1757, 53], "unbound abilities remain eligible at highest known rank"
    assert g.reads == 1, "bar changes do not rescan the spellbook"
    lua.execute("known[2764]=false; B.ClearAvailabilityCache()")
    assert pool() == [1757, 53], "spell changes invalidate learned-spell discovery"
    assert g.reads == 2
    lua.execute("known[2764]=true; B.ClearAvailabilityCache()")
    assert pool() == [2764, 1757, 53], "learning a new ability needs no reload"
    lua.execute("thrownEquipped=false; B.ClearAvailabilityCache()")
    assert pool() == [1757, 53], "unequipped ranged attack leaves the rebuilt pool"
    lua.execute("thrownEquipped=true; B.ClearAvailabilityCache()")
    assert pool() == [2764, 1757, 53], "re-equipped ranged attack returns to the rebuilt pool"
    lua.execute("forever=false")
    assert pool() == [123, 53], "Retail pool and imported additions remain unchanged"
    assert pool(True) == [123], "Retail game-only pool remains unchanged"
    lua.execute("forever=true; failRead=true; B.ClearAvailabilityCache()")
    assert pool() == [53], "reported read failure preserves imported fallback"
    assert len(g.errors) == 1 and "spellbook denied" in g.errors[1]
    lua.execute("failRead=false")
    assert pool() == [2764, 1757, 53], "failed reads are not cached as an empty spellbook"
    test_options_spellbook()
    print("Forever spellbook pool: discovery, ranks, exclusions, caching, errors and Retail passed")


if __name__ == "__main__":
    main()
