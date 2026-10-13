# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Weapon imbues through the real shared API, precombat checklist and redundancy filter.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
setmetatable(B, { __index = function() return function() return nil end end })
forever, combat, grouped, now = true, false, false, 100
secret = {}
B.IsForever = function() return forever end
B.IsSecretValue = function(v) return v == secret end
B.AreAurasSecret = function() return combat end
B.GetRotationSpells = function() return {} end
B.IsUnitHealthBelow = function() return false end
B.IsPassiveSpell = function() return false end
B.GetCachedSpellInfo = function() return { name = "Rockbiter Weapon" } end
function issecretvalue(v) return B.IsSecretValue(v) end
errors = {}
function geterrorhandler() return function(e) errors[#errors + 1] = e end end
local S = LibStub:NewLibrary("JustAC-SpellDB")
S.WEAPON_IMBUE_SPELLS = { 8017 }
S.WEAPON_ENCHANT_SPELLS = { [8017] = true, [8018] = true }
S.CLASS_MAINTAINED_BUFFS = {}
S.NEXT_SWING_SPELLS = { [2973] = true }
S.MAINTAINED_BUFF_MEMBERS = {}
S.StaticLookup = function(t, id) return t[id] end
melee = nil
S.IsTargetWithin = function() return melee end
local RI = LibStub:NewLibrary("JustAC-RotationImport")
RI.RankBase = function(id) if id == 8018 then return 8017 end return id end
function GetTime() return now end
function InCombatLockdown() return combat end
function UnitAffectingCombat() return combat end
function IsInGroup() return grouped end
function UnitClass() return "Shaman", "SHAMAN" end
function IsPlayerSpell(id) return id == 8017 or id == 8018 end
function UnitIsDeadOrGhost() return false end
function IsMounted() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CreateFrame()
    return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function() end }
end
Enum = { ItemEnchantType = { Permanent = 1, Temporary = 2, Imbue = 3 } }
enchants, legacyHas, legacyTime, failRead = {}, false, 0, false
C_Item = {
    GetWeaponEnchantInfo = function(slot)
        if failRead then error("enchant read refused") end
        return enchants[slot] or {}
    end,
}
function GetWeaponEnchantInfo() return legacyHas, legacyTime, 0, 0, false, 0 end
C_Spell = { IsSpellInRange = function() return true end }
C_ActionBar = { IsActionInRange = function() return true end }
LibStub:NewLibrary("JustAC-ActionBarScanner").GetDirectSlotForSpell = function() return 1 end
C_UnitAuras = { GetPlayerAuraBySpellID = function() end }
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    for path in ("BlizzardAPI/StateHelpers.lua", "PrecombatEngine.lua", "RedundancyFilter.lua"):
        lua.execute((ROOT / path).read_text(encoding="utf-8"))
    api = lua.eval('LibStub("JustAC-BlizzardAPI")')
    engine = lua.eval('LibStub("JustAC-PrecombatEngine")')
    redundant = lua.eval(
        'function() return LibStub("JustAC-RedundancyFilter").IsSpellRedundant(8017, {}) end'
    )

    def offers():
        engine.ClearCache()
        return list(engine.GetMissingClassBuffs(False, None, False).values())

    assert offers() == [8017], "bare main hand offers Rockbiter"
    engine.NoteClassBuffApplied(8018)
    assert offers() == [], "higher-rank application immediately suppresses the offer"
    lua.execute("now = now + 3")
    assert offers() == [8017], "unsuccessful application returns after the grace period"
    lua.execute("""
        enchants[0] = {
            { hasEnchant = false, enchantType = 2, timeLeft = 0 },
            { hasEnchant = true, enchantType = 3, timeLeft = 3600000 },
        }
    """)
    assert offers() == [], "Imbue entry suppresses Rockbiter even when legacy reports none"
    assert redundant()[0] is True, "active Rockbiter is redundant in the offensive queue"
    assert api.GetWeaponEnhancementInfo(0, False)[0] is False, "imbue is not a weapon oil"
    lua.execute("enchants[0][2].timeLeft = 180000")
    assert offers() == [8017], "solo refresh at exactly three minutes"
    assert redundant() is False, "redundancy agrees at the exact refresh threshold"
    lua.execute("grouped = true; enchants[0][2].timeLeft = 300000")
    assert offers() == [8017], "group refresh at exactly five minutes"
    lua.execute("enchants[0][2].timeLeft = 300001")
    assert offers() == [], "group buff holds above five minutes"
    lua.execute("enchants[0][2].timeLeft = secret")
    assert offers() == [], "unreadable duration does not nag"
    assert redundant()[0] is True, "unreadable duration is never used in arithmetic"
    lua.execute("""
        enchants[0] = {
            { hasEnchant = true, enchantType = 1, timeLeft = 3600000 },
            { hasEnchant = true, enchantType = 2, timeLeft = 3600000 },
        }
    """)
    assert offers() == [8017], "oil and permanent enchants do not stand in for an imbue"
    assert api.GetWeaponEnhancementInfo(0, False) == (True, 3600000)
    lua.execute("enchants[1] = { { hasEnchant = true, enchantType = 3, timeLeft = 600000 } }")
    assert api.GetWeaponEnhancementInfo(1, True) == (True, 600000), "off-hand is independent"
    lua.execute("failRead = true")
    assert offers() == [], "failed read does not produce a false missing-buff cue"
    assert len(lua.globals().errors) == 1, "read failure is explicitly reported"
    lua.execute("failRead = false; forever = false; legacyHas = true; legacyTime = 3600000")
    assert offers() == [], "retail still uses the legacy weapon-enchant API"
    lua.execute("legacyHas = false")
    assert offers() == [8017], "retail bare weapon still offers its known imbue"

    lua.execute("forever = true; melee = false")
    assert api.SpellInRange(6603, "target") is False, "Attack uses melee evidence, not raw true"
    assert api.SpellInRange(2973, "target") is False, "next-swing ability uses the same evidence"
    assert api.AbilityInRange(6603) is False, "raw action range cannot overturn confirmed melee range"
    assert api.AbilityInRange(2973) is False, "next-swing action range cannot overturn melee range"
    renderer = (ROOT / "UI" / "UIRenderer.lua").read_text(encoding="utf-8")
    start = renderer.index("local function CheckSpellRange(icon, spellID, directSlot)")
    end = renderer.index("\nend", start) + len("\nend")
    lua.execute('BlizzardAPI = LibStub("JustAC-BlizzardAPI"); C_ActionBar_IsActionInRange = C_ActionBar.IsActionInRange')
    lua.execute(renderer[start:end] + "\nCheckRange = CheckSpellRange")
    assert lua.globals().CheckRange(None, 6603, 1) is True, "Attack range tint agrees with sinking"
    lua.execute("melee = true")
    assert api.SpellInRange(6603, "target") is True, "walking into melee updates without an event"
    lua.execute("melee = nil")
    assert api.SpellInRange(6603, "target") is None, "unknown melee range stays unknown"
    lua.execute("forever = false")
    assert api.SpellInRange(6603, "target") is True, "retail spell range is unchanged"
    assert lua.globals().CheckRange(None, 6603, 1) is False, "retail action-button range tint is unchanged"
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("local function IsForeverPullSpell(")
    end = source.index("\n--- Largest icon count", start)
    lua.execute("""
        SpellQueue = { IsSpellBlacklisted = function() return false end }
        proccedSpells, normalSpells, proccedRank, normalRank = {}, {}, {}, {}
        cooldownSpells, sunkSet, unavailableTier, formEntryBase, pinnedAlwaysShow = {}, {}, {}, {}, {}
        function NoteManaStarved() end
        function ClaimSpellID(id, added) added[id] = true; return id end
        function PassesRotationFilters() return true end
        function HeldByUserHold() return false end
        function IsSpenderSpell() return false end
        function MissingMinimumResource() return false end
        function IsBarGreyedOut() return false end
        function IsRearAttackBlocked() return false end
        function IsConfirmedOutOfRange(id) return BlizzardAPI.AbilityInRange(id) == false end
        function rankOf() return 1 end
        function AppendRankedBucket(bucket, _, count, queue, size)
            for i = 1, count do size = size + 1; queue[size] = bucket[i] end
            return size
        end
        BlizzardAPI.IsSpellReady = function() return true end
        BlizzardAPI.IsSpellUsable = function() return true, false end
        BlizzardAPI.GetDisplaySpellID = function(id) return id end
        BlizzardAPI.HasGamePick = function() return not forever end
        BlizzardAPI.IsItemSpell = function() return false end
    """)
    lua.execute(source[start:end] + """
        function BuildQueue(sink)
            wipe(sunkSet); wipe(unavailableTier)
            local b = {
                profile = {}, blacklist = {}, addedSpellIDs = {}, recommendedSpells = {},
                spellCount = 0, maxIcons = 4, effectiveBypassProcs = true,
                contextOrder = "off", sinkCooldowns = sink,
            }
            CategorizeAndAssembleRotation({ 6603, 403 }, b)
            return b.recommendedSpells
        end
    """)
    build = lua.globals().BuildQueue
    for in_combat in (False, True):
        lua.globals().combat = in_combat
        lua.execute("forever = true; melee = false")
        assert list(build(True).values()) == [403, 6603], "out-of-melee Attack trails Lightning Bolt"
        lua.execute("melee = true")
        assert list(build(True).values()) == [6603, 403], "walking into melee restores source order"
        lua.execute("melee = nil")
        assert list(build(True).values()) == [6603, 403], "unknown range preserves order"
        lua.execute("melee = false")
        assert list(build(False).values()) == [6603, 403], "Unavailable last off preserves order"
        lua.execute("forever = false")
        assert list(build(True).values()) == [6603, 403], "retail Attack ordering is unchanged"
    print("weapon enchant and melee-range regressions: passed")


if __name__ == "__main__":
    main()
