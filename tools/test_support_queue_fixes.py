# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Regression coverage for shared support queues and Forever defaults.
#
# Run: python tools/test_support_queue_fixes.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).parent))
from test_forever_defaults import PRELUDE

CLASSES = [
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE",
    "WARLOCK", "DRUID",
]
RETAIL_CLASSES = CLASSES + ["DEATHKNIGHT", "DEMONHUNTER", "MONK", "EVOKER"]
RANKED_GROUPS = ["MAGE", "WARLOCK", "SHAMAN", "PALADIN", "HUNTER"]


BASE_STUBS = """
now, playerClass = 100, "MAGE"
known, auraByID, unitAuraByID, auraList, messages = {}, {}, {}, {}, {}
denySpell, denyList, denyUnit = false, false, false
inGroup, visible = false, true
spellQueries, unitQueries = 0, 0
owned, usable, toys = {}, {}, {}
function GetTime() return now end
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.AreAurasSecret = function() return false end
B.GetAnyNextCastSpell = function() return nil end
B.GetRotationSpells = function() return {} end
B.GetPlayerHealthPercentSafe = function() return nil, false end
B.GetWeaponEnhancementInfo = function() return true, 3600000 end
B.IsSpellUsable = function() return true end
B.IsSpellReady = function() return true end
function UnitClass() return playerClass, playerClass end
function UnitAffectingCombat() return false end
function InCombatLockdown() return false end
function IsPlayerSpell(id) return known[id] == true end
function IsSpellKnown(id) return known[id] == true end
function IsSpellKnownOrOverridesKnown(id) return known[id] == true end
function IsMounted() return false end
function UnitIsDeadOrGhost() return false end
function IsInGroup() return inGroup end
function IsInRaid() return false end
function issecretvalue(value) return value == secretAuraID end
secretAuraID = {}
function geterrorhandler()
    return function(message) messages[#messages + 1] = message end
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Item = {
    GetItemCount = function(id) return owned[id] or 0 end,
    IsUsableItem = function(id) return usable[id] ~= false end,
    GetItemInfo = function() return nil end,
    GetItemInfoInstant = function() return nil, nil, nil, nil, nil, 2, 0 end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        spellQueries = spellQueries + 1
        if denySpell then error("player aura denied") end
        return auraByID[id]
    end,
    GetUnitAuraBySpellID = function(unit, id)
        unitQueries = unitQueries + 1
        if denyUnit then error("unit aura denied") end
        return unitAuraByID[id]
    end,
    GetUnitAuras = function()
        if denyList then error("unit aura list denied") end
        return auraList
    end,
}
PlayerHasToy = function(id) return toys[id] == true end
C_Spell = { IsSpellInRange = function() return true end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 0, "", 0, "", "DAMAGER", 3 end,
}
function UnitExists(unit) return unit == "party1" end
function UnitIsVisible() return visible end
function UnitIsPlayer() return true end
function UnitCanAssist() return true end
function UnitIsConnected() return true end
function UnitInRange() return true end
function GetSpellBaseCooldown() return 0 end
function CreateFrame()
    return {
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
        SetScript = function() end,
    }
end
"""


def new_runtime(forever=True, precombat=True, consumables=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE + BASE_STUBS)
    if forever:
        lua.execute("WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = 18")
        lua.execute("""
            LibStub:NewLibrary("JustAC-RotationImport").RankBase = function(id) return id end
        """)
    files = ["SpellDB.lua", "Data/ChanneledSpells.lua"]
    if consumables:
        files += ["Data/HealingItems.lua", "Data/PrecombatBuffs.lua",
                  "Data/Forever/Consumables.lua"]
    if forever:
        files.append("Data/Forever/Defaults.lua")
    if precombat:
        files.append("PrecombatEngine.lua")
    for file in files:
        lua.execute((ROOT / file).read_text(encoding="utf-8"))
    lua.execute('SpellDB = LibStub("JustAC-SpellDB")')
    return lua, lua.eval('LibStub("JustAC-SpellDB")')


def seq(value):
    return [value[i] for i in range(1, len(value) + 1)]


def check(ok, why):
    if not ok:
        raise AssertionError(why)


def test_generated_member_aura_mappings():
    lua, spell_db = new_runtime()
    lua.execute("""
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.AreAurasSecret = function() return false end
        B.GetAnyNextCastSpell = function() return nil end
        B.GetRotationSpells = function() return {} end
        B.GetPlayerHealthPercentSafe = function() return nil, false end
        B.IsSpellUsable = function() return true end
        B.IsSpellReady = function() return true end
        B.GetWeaponEnhancementInfo = function() return true, 3600000 end
        SpellDB = LibStub("JustAC-SpellDB")
        SpellDB.GetActiveEatingAura = function() return nil, true end
        SpellDB.GetKnownTopoffHeal = function() return nil end
        SpellDB.RECUPERATE = nil
        local P = LibStub("JustAC-PrecombatEngine")
        function Query()
            P.ClearCache()
            return P.GetMissingClassBuffs(false, 90, false)
        end
        function SetActive(class, groupIndex, member, auraID, remaining)
            playerClass = class
            known, auraByID = {}, {}
            for _, id in ipairs(SpellDB.CLASS_MAINTAINED_BUFFS[class][groupIndex].group) do
                known[id] = true
            end
            auraByID[auraID] = { duration = 3600, expirationTime = now + remaining }
        end
    """)

    tests = 0
    for cls in RANKED_GROUPS:
        groups = spell_db.CLASS_MAINTAINED_BUFFS[cls]
        group_index = next(i for i in range(1, len(groups) + 1)
                           if len(groups[i].group) > 1)
        group = groups[group_index]
        members = seq(group.group)
        check(len(members) > 1, f"{cls}: expected a multi-member Forever family")
        # The second member is the active sibling. For four families it is also a
        # ranked spell, so use a non-base aura ID and verify rank detection survives.
        sibling = members[1]
        sibling_auras = seq(group.memberAuraIDs[sibling])
        aura_id = next((sid for sid in sibling_auras if sid != sibling), sibling)
        check(aura_id in sibling_auras, f"{cls}: generated member aura map missing {sibling}")
        lua.globals().SetActive(cls, group_index, sibling, aura_id, 1200)
        fresh = seq(lua.globals().Query())
        check(sibling not in fresh, f"{cls}: fresh active sibling was offered: {fresh}")
        lua.globals().SetActive(cls, group_index, sibling, aura_id, 20)
        lapsing = seq(lua.globals().Query())
        expected = [] if group.preparation else [sibling]
        check(lapsing == expected,
              f"{cls}: lapsing sibling {sibling} was misidentified: {lapsing}")
        tests += 2

        # Each family must retain its per-member rank chain. When the family has a
        # distinct rank aura, the active member's own rank is found and refreshed.
        for member in members:
            rank_auras = seq(group.memberAuraIDs[member])
            rank_id = next((sid for sid in rank_auras if sid != member), None)
            if rank_id is None:
                continue
            lua.globals().SetActive(cls, group_index, member, rank_id, 20)
            ranked = seq(lua.globals().Query())
            expected = [] if group.preparation else [member]
            check(ranked == expected,
                  f"{cls}: ranked aura {rank_id} did not resolve to member {member}: {ranked}")
            tests += 1
            break
    print(f"support queues: {tests} generated member/rank cases across five Forever families")


def test_legacy_retail_groups():
    lua, _ = new_runtime(forever=False)
    lua.execute("""
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.AreAurasSecret = function() return false end
        B.GetAnyNextCastSpell = function() return nil end
        B.GetRotationSpells = function() return {} end
        B.GetPlayerHealthPercentSafe = function() return nil, false end
        B.GetWeaponEnhancementInfo = function() return true, 3600000 end
        local S = LibStub("JustAC-SpellDB")
        S.CLASS_MAINTAINED_BUFFS = { MAGE = {
            { group = { 11, 12 }, default = 11, auraIDs = { 901 } },
            { group = { 21 }, default = 21, auraIDs = { 902 } },
        } }
        S.GetKnownTopoffHeal = function() return nil end
        S.RECUPERATE, S.RECUPERATE_AURA = 1231411, 1231418
        local P = LibStub("JustAC-PrecombatEngine")
        function QueryLegacy()
            P.ClearCache()
            return P.GetMissingClassBuffs(false, 90, false)
        end
        known = { [11] = true, [12] = true, [21] = true }
        auraByID = {
            [901] = { duration = 3600, expirationTime = now + 1200 },
            [902] = { duration = 3600, expirationTime = now + 1200 },
        }
    """)
    check(seq(lua.globals().QueryLegacy()) == [],
          "shared legacy single/multi aura families changed Retail behavior")
    print("support queues: legacy shared single/multi groups retain Retail semantics")


def test_health_threshold_detection():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("local thresholdCurves, thresholdCurveCount")
    end = source.index("\n--- Plain true/false", start)
    lua, _ = new_runtime()
    lua.execute("""
        BlizzardAPI = LibStub("JustAC-BlizzardAPI")
        math_floor, math_max, math_min = math.floor, math.max, math.min
        Enum = { LuaCurveType = { Linear = 1 } }
        C_CurveUtil = {
            CreateCurve = function()
                local c = { points = {} }
                function c:SetType(kind) assert(kind == Enum.LuaCurveType.Linear) end
                function c:AddPoint(x, y) self.points[#self.points+1] = {x,y} end
                function c:Evaluate(x)
                    for i = 2, #self.points do
                        local lo, hi = self.points[i-1], self.points[i]
                        if x <= hi[1] then
                            if hi[1] == lo[1] then return hi[2] end
                            return lo[2]+(hi[2]-lo[2])*(x-lo[1])/(hi[1]-lo[1])
                        end
                    end
                    return self.points[#self.points][2]
                end
                return c
            end,
        }
        health, denied = 85, false
        function UnitHealthPercent(unit, predicted, curve)
            assert(unit == "player" and predicted == false)
            if denied then error("health gate unavailable") end
            return curve:Evaluate(health/100)
        end
        function UnitPowerPercent(unit, power, predicted, curve)
            assert(unit == "player" and power == 0 and predicted == false)
            if denied then error("mana gate unavailable") end
            return curve:Evaluate(health/100)
        end
        BlizzardAPI.IsSecretZero = function(value) return value < 1 end
    """)
    lua.execute(source[start:end] + """
        function CheckHealth(pct) return CachedBelow("player",pct,false,nil) end
        function CheckMana(pct) return CachedBelow("player",pct,true,0) end
    """)
    g = lua.globals()
    for threshold in (50, 60, 70, 80, 90, 95):
        for health, expected in ((threshold - 1, True), (threshold + 1, False)):
            g.health = health
            g.now += 1
            check(g.CheckHealth(threshold) is expected,
                  f"real threshold evaluator: {health}% vs {threshold}%")
            check(g.CheckMana(threshold) is expected,
                  f"real mana evaluator: {health}% vs {threshold}%")
    g.denied = True
    g.now += 1
    check(g.CheckHealth(60) is None, "a denied health evaluation must remain unknown")
    check(g.CheckMana(60) is None, "a denied mana evaluation must remain unknown")
    print("health thresholds: real curve builder, self-test and evaluator cover every slider selection")


def test_topoff_slider_thresholds():
    source = (ROOT / "Options" / "Defensives.lua").read_text(encoding="utf-8")
    slider = source[source.index("                    topoffThreshold = {"):]
    slider = slider[:slider.index("                    stealthReminder = {")]
    check("min = 50, max = 90, step = 10" in slider, "topoff slider must use 10% selections")
    check("topoffThreshold or 80" in slider, "slider fallback must default to 80%")
    check("pb.topoffThreshold = 80" in source, "reset must restore the 80% default")
    defaults = (ROOT / "JustAC.lua").read_text(encoding="utf-8")
    check("topoffThreshold = 80," in defaults, "new profiles must default to 80%")
    for forever in (True, False):
        lua, _ = new_runtime(forever, precombat=False)
        lua.execute("""
            local B = LibStub("JustAC-BlizzardAPI")
            local S = LibStub("JustAC-SpellDB")
            S.CLASS_MAINTAINED_BUFFS = {}
            S.CLASS_TOPOFF_HEALS.MAGE = {139}
            S.RECUPERATE, S.RECUPERATE_AURA = 1231411, 1231418
            known = { [1231411] = true, [139] = true }
            exact, health, gateUnknown = false, 85, false
            B.GetPlayerHealthPercentSafe = function()
                if exact then return health, false end
                return 100, true
            end
            B.IsUnitHealthBelow = function(unit, pct)
                assert(unit == "player")
                queriedThreshold = pct
                if gateUnknown then return nil end
                return health < pct
            end
            B.IsUnitFullHealth = function() return health == 100 end
            B.IsPartyLowAvailable = function() return true end
            B.IsUnitLow = function() return true end
            B.HasSustainedPlayerHealthActivity = function() return true end
            B.IsInPostCombatDowntime = function() return true end
        """)
        lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
        lua.execute("""
            P = LibStub("JustAC-PrecombatEngine")
            function Offer(threshold, enabled)
                P.ClearCache()
                return P.GetMissingClassBuffs(enabled ~= false, threshold, false, {healthRecovery=false})
            end
        """)
        g = lua.globals()
        for exact in (True, False):
            g.exact = exact
            for threshold in (50, 60, 70, 80, 90, 95):
                g.health = threshold + 1
                check(seq(g.Offer(threshold)) == [], "above selected topoff threshold")
                g.health = threshold - 1
                if not exact:
                    check(seq(g.Offer(threshold)) == [], "threshold gate onset is debounced")
                    g.now += 3
                check(seq(g.Offer(threshold)) == [139],
                      f"{forever=}, {exact=}: below {threshold}% did not offer topoff")
                g.health = threshold + 1
                check(seq(g.Offer(threshold)) == [], "above threshold clears topoff immediately")
        g.exact = False
        g.health = 75
        g.Offer(None)
        g.now += 3
        check(seq(g.Offer(None)) == [139] and g.queriedThreshold == 80,
              "unset saved threshold must query the default 80% gate")
        g.health = 85
        check(seq(g.Offer(None)) == [], "default 80% gate must not offer at 85%")
        g.gateUnknown = True
        g.now += 3
        check(seq(g.Offer(60)) == [],
              "below-full/regen/party/postcombat signals cannot substitute for selected 60%")
        g.gateUnknown = False
        g.health = 55
        check(seq(g.Offer(60)) == [], "unknown reads reset the onset, not retain stale arming")
        g.now += 3
        check(seq(g.Offer(60)) == [139], "confirmed threshold recovery re-arms normally")
        g.exact = True
        g.health = 30
        check(seq(g.Offer(60, False)) == [139], "emergency floor stays independent of slider")
    print("topoff slider: 10% selections plus legacy 95%, both clients, exact/gate, default and unknown passed")


def test_topoff_threshold_and_protected_aura_paths():
    lua, spell_db = new_runtime()
    lua.execute("""
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.AreAurasSecret = function() return false end
        B.GetAnyNextCastSpell = function() return nil end
        B.GetRotationSpells = function() return {} end
        B.GetPlayerHealthPercentSafe = function() return exactPct, false end
        B.IsUnitHealthBelow = function(_, pct) return pct == 70 end
        B.IsUnitFullHealth = function() return exactPct == 100 end
        B.IsSpellUsable = function() return true end
        B.IsSpellReady = function() return true end
        B.GetWeaponEnhancementInfo = function() return true, 3600000 end
        local S = LibStub("JustAC-SpellDB")
        S.CLASS_MAINTAINED_BUFFS = {}
        realEatingReader = S.GetActiveEatingAura
        S.GetActiveEatingAura = function() return nil, true end
        S.CLASS_TOPOFF_HEALS.MAGE = {139}
        S.RECUPERATE, S.RECUPERATE_AURA = 1231411, 1231418
        known = { [1231411] = true, [139] = true }
        exactPct, denySpell = 85, false
        local P = LibStub("JustAC-PrecombatEngine")
        function Offer(topoff, threshold)
            P.ClearCache()
            return P.GetMissingClassBuffs(topoff, threshold, false, {healthRecovery=false})
        end
    """)
    check(seq(lua.globals().Offer(True, 80)) == [],
          "85% health incorrectly triggers an 80% configured topoff")
    check(seq(lua.globals().Offer(True, 95)) == [139],
          "92% health does not trigger a 95% configured topoff")
    lua.globals().exactPct = 79
    check(seq(lua.globals().Offer(True, None)) == [139],
          "nil topoff threshold no longer defaults to 80%")
    lua.globals().exactPct = 81
    check(seq(lua.globals().Offer(True, None)) == [],
          "default 80% threshold offers above its line")
    lua.globals().exactPct = 30
    check(seq(lua.globals().Offer(False, 95)) == [139],
          "the critical-health emergency floor was disabled with topoff off")

    # A denied main class-buff probe is unknown, not evidence that the group is absent.
    lua.execute("""
        playerClass = "MAGE"
        local S = LibStub("JustAC-SpellDB")
        S.CLASS_MAINTAINED_BUFFS = {
            MAGE = { { group = { 168, 7302 }, default = 168 } }
        }
        known = { [168] = true, [7302] = true }
        denySpell = true
        exactPct = nil
    """)
    denied = seq(lua.globals().Offer(False, 90))
    check(denied == [], f"denied class-buff aura query produced offers: {denied}")
    check(len(lua.globals().messages) == 1, "denied aura errors were not reported once")
    check(seq(lua.globals().Offer(False, 90)) == [], "repeat denied query changed offers")
    check(len(lua.globals().messages) == 1, "aura error was reported repeatedly within the throttle")

    # Party by-ID nil is absence only for a visible unit. Throws and invisibility
    # remain unknown, while a visible, plain nil still permits the group reminder.
    lua.execute("""
        local S = LibStub("JustAC-SpellDB")
        S.CLASS_MAINTAINED_BUFFS = {
            MAGE = { { group = { 1459 }, default = 1459, raidWide = true, auraIDs = { 1459 } } }
        }
        known, auraByID, unitAuraByID = { [1459] = true },
            { [1459] = { duration = 3600, expirationTime = now + 1200 } }, {}
        denySpell, denyUnit, inGroup, visible = false, true, true, true
        unitQueries = 0
    """)
    check(seq(lua.globals().Offer(False, 90)) == [],
          "denied party aura lookup produced an uncertain group-buff offer")
    check(lua.globals().unitQueries == 1 and len(lua.globals().messages) == 2,
          "party aura denial was not protected and reported once")
    check(seq(lua.globals().Offer(False, 90)) == [],
          "repeated denied party lookup changed the queue")
    check(len(lua.globals().messages) == 2,
          "party aura denial was repeatedly reported within the throttle")
    lua.execute("denyUnit = false; visible = false")
    check(seq(lua.globals().Offer(False, 90)) == [],
          "a non-visible party unit's nil aura lookup was treated as absence")
    check(lua.globals().unitQueries == 2,
          "a non-visible party member was queried for aura absence")
    lua.execute("visible = true")
    check(seq(lua.globals().Offer(False, 90)) == [1459],
          "a visible member's plain absent aura did not offer the group buff")

    # Unreadable aura enumeration cannot be mistaken for an absent pre-combat buff.
    lua.execute("""
        local S = LibStub("JustAC-SpellDB")
        S.GetPrecombatBuffCategories = function() return { "fixture" } end
        S.GetPrecombatBuffSet = function() return { [555] = true } end
        S.GetBestOwnedBuff = function() return { id = 1001, source = "item" } end
        denyList = true
        denySpell = false
    """)
    missing = seq(lua.eval("(function() return LibStub('JustAC-PrecombatEngine').GetMissingBuffs() end)()"))
    check(missing == [], f"denied buff list produced an uncertain offer: {missing}")

    # A denied eating-aura scan blocks recovery before the Recently Bandaged query;
    # a denied bandage query also suppresses the bandage itself.
    lua.execute("""
        local S = LibStub("JustAC-SpellDB")
        S.IsForever = function() return true end
        S.GetBestRecoveryItem = function(kind)
            if kind == "bandage" then return 1251 end
            return nil
        end
        S.GetActiveEatingAura = realEatingReader
        denyList, denySpell = true, true
        spellQueries = 0
    """)
    # The loaded SpellDB eating reader returns an explicit unknown result on denial.
    lua.execute("SpellDB.GetBestRecoveryItem = function(kind) if kind == 'bandage' then return 1251 end end")
    output = seq(lua.eval(
        "(function() local o = {} LibStub('JustAC-PrecombatEngine').AddRecoveryItems(o) return o end)()"
    ))
    check(output == [], f"unknown eating state bypassed bandage suppression: {output}")
    check(lua.globals().spellQueries == 0,
          "Recently Bandaged was queried after eating-aura state was denied")

    # Make the eating scan readable, then deny only Recently Bandaged.
    lua.execute("now = now + 1; denyList = false; auraList = {}; denySpell = true")
    lua.execute("""
        local P = LibStub("JustAC-PrecombatEngine")
        P.ClearCache()
        hpLow = true
        local B = LibStub("JustAC-BlizzardAPI")
        B.IsUnitHealthBelow = function(_, pct) return pct == 70 end
        function UnitIsDeadOrGhost() return false end
        function CapturedThreshold()
            for i = 1, 20 do
                local name, value = debug.getupvalue(P.AddRecoveryItems, i)
                if name == "BlizzardAPI" then return value.IsUnitHealthBelow("player", 70) end
            end
        end
    """)
    check(lua.eval('LibStub("JustAC-BlizzardAPI").IsUnitHealthBelow("player", 70) == true'),
          "recovery health-threshold fixture was not installed")
    check(lua.globals().CapturedThreshold() is True,
          "PrecombatEngine captured a different BlizzardAPI table")
    output = seq(lua.eval(
        "(function() local o = {} LibStub('JustAC-PrecombatEngine').AddRecoveryItems(o) return o end)()"
    ))
    check(output == [], f"denied Recently Bandaged query offered a bandage: {output}")
    check(lua.globals().spellQueries == 1,
          "Recently Bandaged query did not execute after readable eating state")
    check(len(lua.globals().messages) <= 4,
          "aura error reporting was not deduplicated and throttled across support surfaces")
    print("support queues: configured topoff, denied/unreadable aura and recovery cases passed")


def test_source_aware_buff_usability():
    lua, spell_db = new_runtime(consumables=True)
    lua.execute("""
        SpellDB = LibStub("JustAC-SpellDB")
        playerClass = "MAGE"
        owned = { [3383] = 1 }
        usable = { [3383] = false }
    """)
    check(spell_db.GetBestOwnedBuff("flask") is None,
          "an owned but unusable item buff was returned")
    lua.execute("""
        local S = LibStub("JustAC-SpellDB")
        S.RegisterPrecombatBuffsExtra({
            { category = "sourceFixture", id = 940001, buff = 940001, source = "toy" },
            { category = "sourceFixture", id = 940002, buff = 940002, source = "spell" },
            { category = "sourceFixture", id = 940003, buff = 940003, source = "item" },
        })
        toys[940001] = true
        known[940002] = true
        owned[940003] = 1
        usable[940001], usable[940002], usable[940003] = false, false, false
    """)
    result = spell_db.GetBestOwnedBuff("sourceFixture")
    check(result is not None and result.id == 940001,
          "toy availability was incorrectly filtered through item usability")
    lua.execute("toys[940001] = false")
    result = spell_db.GetBestOwnedBuff("sourceFixture")
    check(result is not None and result.id == 940002,
          "known-spell availability was incorrectly filtered through item usability")
    print("support queues: item usability is applied only to item-backed entries")


def test_empty_defensive_lists_and_overrides():
    totals = 0
    for forever, classes in ((True, CLASSES), (False, RETAIL_CLASSES)):
        lua, spell_db = new_runtime(forever=forever, precombat=False)
        lua.execute("""
            playerClass = "WARRIOR"
            local S = LibStub("JustAC-SpellDB")
            SpellDB = S
            S.GetSpecKey = function()
                if S.IsForever() then return playerClass .. "_F", playerClass end
                return playerClass .. "_1", playerClass
            end
        """)
        lua.execute((ROOT / "DefensiveEngine.lua").read_text(encoding="utf-8"))
        lua.execute("""
            local DE = LibStub("JustAC-DefensiveEngine")
            DE.RegisterDefensivesForTracking = function() end
            function InitProfile(p)
                return DE.InitializeDefensiveSpells({ GetProfile = function() return p end })
            end
        """)
        for index, cls in enumerate(classes):
            lua.globals().playerClass = cls
            lua.execute("""
                profile = { defensives = { enabled = true, classSpells = {} } }
                InitProfile(profile)
                local specKey = SpellDB.GetSpecKey()
                local cs = profile.defensives.classSpells[specKey]
                local defaults = SpellDB.ResolveDefaults(SpellDB.CLASS_DEFENSIVE_DEFAULTS, specKey, playerClass)
                assert(cs.personalDefensiveListInitialized == true)
                assert(defaults and cs.defensiveSpells[1] == defaults[1])
                assert(cs.defensiveSpells[#cs.defensiveSpells] == SpellDB.EMERGENCY_POTION)
            """)
            totals += 1

            lua.execute("""
                local specKey = SpellDB.GetSpecKey()
                profile = { defensives = { enabled = true, classSpells = {
                    [specKey] = {
                        defensiveSpells = {}, emergencyPotionRemoved = true,
                        groupHelpSpells = {}, groupHelpMoved = true,
                        groupHealSpells = {}, groupHealAoeReseed = true,
                        customSetting = "keep",
                    },
                } } }
                InitProfile(profile)
                local cs = profile.defensives.classSpells[specKey]
                assert(#cs.defensiveSpells == 0)
                assert(cs.personalDefensiveListInitialized == true)
                assert(cs.customSetting == "keep")
                InitProfile(profile)
                assert(#cs.defensiveSpells == 0)
            """)
            totals += 1

            lua.execute(f"""
                local specKey = SpellDB.GetSpecKey()
                local custom = {900000 + index}
                profile = {{ defensives = {{
                    enabled = false,
                    customProfileValue = "retain",
                    classSpells = {{ [specKey] = {{
                        defensiveSpells = {{ custom }},
                        petHealSpells = {{ custom + 1 }},
                        petRezSpells = {{ custom + 2 }},
                        groupHelpSpells = {{ custom + 3 }},
                        groupHealSpells = {{ custom + 4 }},
                        groupHelpMoved = true,
                        groupHealAoeReseed = true,
                        emergencyPotionRemoved = true,
                    }} }}
                }} }}
                InitProfile(profile)
                local cs = profile.defensives.classSpells[specKey]
                assert(cs.defensiveSpells[1] == custom and #cs.defensiveSpells == 1)
                assert(cs.petHealSpells[1] == custom + 1)
                assert(cs.petRezSpells[1] == custom + 2)
                assert(cs.groupHelpSpells[1] == custom + 3)
                assert(cs.groupHealSpells[1] == custom + 4)
                assert(profile.defensives.enabled == false)
                assert(profile.defensives.customProfileValue == "retain")
            """)
            totals += 1

    print(f"support defaults: {totals} seed/empty/reload/override cases across 9 Forever and 13 Retail classes")


def test_forever_empty_fallbacks():
    _, forever = new_runtime(forever=True, precombat=False)
    _, retail = new_runtime(forever=False, precombat=False)
    check(len(forever.CLASS_GROUP_HELP_DEFAULTS.WARRIOR_F) == 0,
          "Forever Warrior inherited Retail Rallying Cry")
    check(len(forever.CLASS_GROUP_HELP_DEFAULTS.MAGE_F) == 0,
          "Forever Mage inherited Retail Mass Barrier")
    check(len(forever.CLASS_TOPOFF_HEALS.ROGUE) == 0,
          "Forever Rogue inherited Retail Crimson Vial")
    check(97462 in seq(retail.CLASS_GROUP_HELP_DEFAULTS.WARRIOR),
          "Retail Rallying Cry default changed")
    check(414660 in seq(retail.CLASS_GROUP_HELP_DEFAULTS.MAGE),
          "Retail Mass Barrier default changed")
    check(185311 in seq(retail.CLASS_TOPOFF_HEALS.ROGUE),
          "Retail Crimson Vial default changed")
    print("support defaults: Forever fallback lists are explicit-empty; Retail defaults remain")


def test_recovery_heal_preference():
    for forever in (True, False):
        lua, _ = new_runtime(forever, precombat=False)
        lua.execute("""
            playerClass="PALADIN";known={[639]=true,[19750]=true,[633]=true}
            local S=LibStub("JustAC-SpellDB")
            S.CLASS_MAINTAINED_BUFFS={}
            S.CLASS_TOPOFF_HEALS.PALADIN={635,19750}
            S.GetActiveEatingAura=function() return nil,true end
            S.GetBestRecoveryItem=function(kind) return kind=="drink" and 2001 or 2002 end
            local RI=LibStub:NewLibrary("JustAC-RotationImport")
            RI.HighestKnownRank=function(id)
                if id==635 and known[639] then return 639 end
                if known[id] then return id end
            end
            RI.RankBase=function(id) if id==639 then return 635 end return id end
            local B=LibStub("JustAC-BlizzardAPI")
            B.GetPlayerHealthPercentSafe=function() return health,false end
            B.IsUnitHealthBelow=function(_,pct) return health<pct end
            B.IsUnitPowerBelow=function() return lowMana end
            B.IsSpellUsable=function(id,failOpen) assert(failOpen==false);return usableHeals[id] end
            B.IsSpellReady=function(id) return readyHeals[id] end
            health=60;lowMana=false
            Enum={PowerType={Mana=0}}
            usableHeals={[639]=true,[19750]=true};readyHeals={[639]=true,[19750]=true}
            P=LibStub("JustAC-PrecombatEngine")
            settings={healthRecovery=true}
            function Recover()
                P.ClearCache()
                return P.GetMissingClassBuffs(false,80,false,settings)
            end
            function Items()
                local out={};P.AddRecoveryItems(out,80,settings);return out
            end
        """)
        lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
        lua.execute('P=LibStub("JustAC-PrecombatEngine")')
        g = lua.globals()
        check(seq(g.P.GetRecoveryHeals()) == [639, 19750], "learned ranks only; major healing cooldowns are excluded")
        check(seq(g.Recover()) == ([639] if forever else []), "Auto uses a class heal without requiring Recuperate")
        check(seq(g.Items()) == [], "a usable cast heal saves health recovery items")
        lua.execute("settings.healthRecovery=19750")
        check(seq(g.Recover()) == ([19750] if forever else []), "explicit short-cooldown heal preference")
        lua.execute("readyHeals[19750]=false")
        check(seq(g.Recover()) == [], "an unavailable selected heal cannot take priority")
        check(seq(g.Items()) == ([2002] if forever else []), "health items remain the fallback")
        lua.execute("settings.healthRecovery=true;readyHeals[639]=false;readyHeals[19750]=true")
        check(seq(g.Recover()) == ([19750] if forever else []), "Auto considers the next ready class heal")
        lua.execute("usableHeals[19750]=nil")
        check(seq(g.Recover()) == [], "unknown usability does not authorize a cast heal")
        lua.execute("usableHeals[19750]=true;readyHeals[639]=true;settings.healthRecovery='items'")
        check(seq(g.Recover()) == [], "items-only preserves explicit consumable preference")
        check(seq(g.Items()) == ([2002] if forever else []), "items-only remains available with learned heals")
        lua.execute("settings.healthRecovery=true;lowMana=true")
        check(seq(g.Items()) == ([2001] if forever else []), "self-healing does not suppress independent mana recovery")
        lua.execute("auraByID[639]={duration=15,expirationTime=now+15};lowMana=false")
        check(seq(g.Recover()) == [], "an active recovery heal is not recast")
        check(seq(g.Items()) == [], "ongoing recovery does not consume health items")
        lua.execute("auraByID={};known={};health=60")
        check(seq(g.Recover()) == [], "classes without available recovery heals retain item recovery")
        check(seq(g.Items()) == ([2002] if forever else []), "no class heal leaves food eligible")
    print("recovery preference: learned ranks, Auto/selected/items-only, readiness, unknown, active healing and independent mana passed")


def main():
    test_recovery_heal_preference()
    test_health_threshold_detection()
    test_topoff_slider_thresholds()
    test_generated_member_aura_mappings()
    test_legacy_retail_groups()
    test_topoff_threshold_and_protected_aura_paths()
    test_source_aware_buff_usability()
    test_empty_defensive_lists_and_overrides()
    test_forever_empty_fallbacks()


if __name__ == "__main__":
    main()
