# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Pet rez/summon spell blacklist filtering on both defensive display surfaces.
#
# Run: python tools/test_pet_blacklist.py

from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "DefensiveEngine.lua"

PRELUDE = """
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
usableResults, usableAddedHere = {}, {}
proccedBuffer, nonProccedBuffer, unusableBuffer = {}, {}, {}
GetTime = function() return 0 end
BlizzardAPI = { IsPlayerAbilityLockout = function() return false end }
BlizzardAPI.IsSpellAvailable = function() return true end
blacklisted = {}
SpellQueue = {
    IsSpellBlacklisted = function(id, _, isPrimary)
        local entry = blacklisted[id]
        if entry == true then return true end
        return type(entry) == "table" and entry.fixedQueue == true and not isPrimary
    end,
}
function EvalDefensiveSpell(id)
    return {
        spellID = id,
        usableGate = true,
        unusable = false,
        realProc = false,
        isProcced = false,
    }
end
addon = {
    GetProfile = function()
        return { defensives = {} }
    end,
}
petStatus, petlessByChoice = "dead", false
specKey, playerClass, forever, foreverTree = "HUNTER_1", "HUNTER", false, nil
BlizzardAPI.GetPetStatus = function() return petStatus end
BlizzardAPI.IsPetlessByChoice = function() return petlessByChoice end
SpellDB = {
    GetSpecKey = function() return specKey, playerClass end,
    IsForever = function() return forever end,
}
LibStub = function()
    return { GetForeverTree = function() return foreverTree end }
end
petList = { 101, 303, 202 }
DefensiveEngine = {
    GetClassSpellList = function(_, key)
        assert(key == "petRezSpells")
        return petList
    end,
}
function PushEntry(results, spellID, isItem, isProcced, unusable, noResources, precombat)
    local entry = {
        spellID = spellID,
        isItem = isItem,
        isProcced = isProcced,
        unusable = unusable,
        noResources = noResources,
        precombat = precombat,
    }
    results[#results + 1] = entry
    return entry
end
"""


def extract_get_usable(text):
    start = text.index("local function GetUsableDefensiveSpells(")
    end = text.index("\nend\n\n-- Append usable defensive spells", start) + len("\nend")
    return text[start:end].replace(
        "local function GetUsableDefensiveSpells(",
        "function GetUsableDefensiveSpells(",
        1,
    )


def extract_helper(text, name, next_name=None):
    start = text.index(f"local function {name}(")
    if next_name:
        end = text.index(f"\nend\n\nlocal function {next_name}(", start) + len("\nend")
    else:
        end = text.index("\n\n--------------------------------------------------------------------------------", start)
    return text[start:end].replace(f"local function {name}(", f"function {name}(", 1)


def test_precombat_visibility():
    source = (ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        PrecombatEngine = {}
        inCombat, visible = false, true
        InCombatLockdown = function() return inCombat end
        R1 = function(id)
            if id == 303 then return 202 end
            return id
        end
        icon = {
            spellID = 202,
            isPrecombatBuff = true,
            IsVisible = function() return visible end,
        }
        BlizzardAPI = { GetAddon = function() return { defensiveIcons = {icon} } end }
        profile = { defensives = {enabled = true}, precombatBuffs = {enabled = true} }
    """)
    lua.execute(source[source.index("function PrecombatEngine.IsOfferingNow("):])
    lua.execute("""
        assert(PrecombatEngine.IsOfferedNow(202, profile))
        assert(PrecombatEngine.IsOfferedNow(303, profile))
        assert(not PrecombatEngine.IsOfferedNow(101, profile))
        visible = false
        assert(not PrecombatEngine.IsOfferedNow(202, profile))
        visible = true; inCombat = true
        assert(not PrecombatEngine.IsOfferedNow(202, profile))
        inCombat = false; profile.defensives.enabled = false
        assert(not PrecombatEngine.IsOfferedNow(202, profile))
        profile.defensives.enabled = true; profile.precombatBuffs.enabled = false
        assert(not PrecombatEngine.IsOfferedNow(202, profile))
        profile.precombatBuffs.enabled = true; icon.isPrecombatBuff = false
        assert(not PrecombatEngine.IsOfferedNow(202, profile))
    """)


def test_petless_aura_cache():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        forever = false
        restricted, mounted, vehicle = false, false, false
        IsMounted = function() return mounted end
        UnitHasVehicleUI = function() return vehicle end
        auraCache = { byID = {}, complete = true }
        BlizzardAPI = {
            IsForever = function() return forever end,
            AreAurasSecret = function() return restricted end,
            GetPetStatus = function() return petStatus end,
        }
        function GetRedundancyFilter()
            return { GetAuraCache = function() return auraCache end }
        end
    """)
    start = source.index("function BlizzardAPI.IsAuraActive(")
    end = source.index("\nend", start) + len("\nend")
    lua.execute(source[start:end])
    start = source.index("local PETLESS_BY_CHOICE_AURAS =")
    end = source.index("\n-- Player UNIT_HEALTH event activity:", start)
    lua.execute(source[start:end])
    engine = SOURCE.read_text(encoding="utf-8")
    lua.execute("""
        addon = {}
        DefensiveEngine = { GetClassSpellList = function() return {101} end }
        BlizzardAPI.IsSpellAvailable = function() return true end
    """)
    lua.execute(extract_helper(engine, "PetNeedsRez", "IsPetCombatPrioritySpec"))
    lua.execute("local needs = PetNeedsRez; PetNeedsRez = function() return (needs(addon)) end")
    retail_auras = (155228, 196099)
    forever_auras = (18789, 18790, 18791, 18792, 415370, 1310684)
    for is_forever, supported in ((False, retail_auras), (True, forever_auras)):
        lua.globals().forever = is_forever
        for aura_id in (*retail_auras, *forever_auras, 18788, 409979, 415372):
            lua.globals().auraCache.byID = lua.table_from({aura_id: True})
            expected = aura_id in supported
            assert lua.globals().BlizzardAPI.IsPetlessByChoice() is expected, (
                is_forever, aura_id, expected
            )
            for status in ("dead", "missing", "alive", None):
                lua.globals().petStatus = status
                assert lua.globals().PetNeedsRez() is (
                    status in ("dead", "missing") and not expected
                )
        for state in (
            "auraCache = nil",
            "auraCache = { byID = {} }",
            "auraCache = { byID = {}, complete = false, hasSecrets = true }",
            "auraCache = { byID = {}, complete = true }; restricted = true",
        ):
            lua.execute(state)
            assert lua.globals().BlizzardAPI.IsPetlessByChoice() is None
            lua.globals().petStatus = "missing"
            assert lua.globals().PetNeedsRez() is False
        # Combat exit alone does not make a still-partial cache authoritative.
        lua.execute("restricted = false; auraCache.complete = false")
        assert lua.globals().BlizzardAPI.IsPetlessByChoice() is None
        lua.execute("auraCache.complete = true")
        assert lua.globals().BlizzardAPI.IsPetlessByChoice() is False
        assert lua.globals().PetNeedsRez() is True
        for reason in ("mounted", "vehicle"):
            lua.globals()[reason] = True
            assert lua.globals().PetNeedsRez() is False
            lua.globals()[reason] = False
        # Known presence remains enough to suppress a reminder during restrictions.
        lua.globals().auraCache.byID = lua.table_from({supported[0]: True})
        lua.execute("auraCache.complete = false; restricted = true")
        assert lua.globals().BlizzardAPI.IsPetlessByChoice() is True
        lua.execute("restricted = false; auraCache = { byID = {}, complete = true }")


def test_aura_read_completeness():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function wipe(t) for k in pairs(t) do t[k] = nil end return t end
        now, restricted, combat = 10, false, false
        secretValue = {}
        GetTime = function() return now end
        UnitAffectingCombat = function() return combat end
        readMode = "batch"
        liveList = {}
        C_UnitAuras = {
            GetUnitAuras = function()
                if readMode ~= "batch" then error("batch denied") end
                return liveList
            end,
            GetAuraDataByIndex = function(_, i)
                if readMode == "denied" or (readMode == "partial" and i == 2) then
                    error("index denied")
                end
                if readMode == "capped" then return {spellId = 900} end
                return liveList[i]
            end,
        }
        BlizzardAPI = {
            IsSecretValue = function(v) return v == secretValue end,
            Unsecret = function(v) if v ~= secretValue then return v end end,
            AreAurasSecret = function() return restricted end,
            GetAuraTiming = function() return nil, nil end,
        }
        cachedAuras, trustedOutOfCombatCache = {}, {}
        instanceToSpellMap, instanceToTimingMap, instanceToNameMap = {}, {}, {}
        combatRemovedSpellIDs = {}
        lastAuraCheck, AURA_CACHE_DURATION = 0, 0.1
        function BuildAuraTiming() return {} end
        function IsNeverSecretAura() return false end
        function ForceReadNumber() return nil end
        function PruneTrustedCacheExpiration() end
        function MergeTrustedCacheFallback() end
    """)
    source = (ROOT / "BlizzardAPI" / "SecretValues.lua").read_text(encoding="utf-8")
    start = source.index("local GetUnitAuras =")
    end = source.index("\n--------------------------------------------------------------------------------", start)
    lua.execute(source[start:end])
    source = (ROOT / "RedundancyFilter.lua").read_text(encoding="utf-8")
    start = source.index("RefreshAuraCache = function()")
    end = source.index("\n-- A cast remembered", start)
    lua.execute(source[start:end])
    lua.execute("""
        BlizzardAPI.IsForever = function() return true end
        BlizzardAPI.GetPetStatus = function() return "missing" end
        GetRedundancyFilter = function()
            return { GetAuraCache = RefreshAuraCache }
        end
    """)
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("local PETLESS_BY_CHOICE_AURAS =")
    end = source.index("\n-- Player UNIT_HEALTH event activity:", start)
    lua.execute(source[start:end])
    lua.execute(extract_helper(SOURCE.read_text(encoding="utf-8"), "PetNeedsRez", "IsPetCombatPrioritySpec"))
    lua.execute("""
        addon = {}
        DefensiveEngine = { GetClassSpellList = function() return {101} end }
        BlizzardAPI.IsSpellAvailable = function() return true end
        local needs = PetNeedsRez; PetNeedsRez = function() return (needs(addon)) end
    """)
    for mode, complete in (
        ("batch", True), ("index", True), ("partial", False),
        ("denied", False), ("capped", False),
    ):
        lua.execute("now = now + 1; liveList = {{spellId = 900, name = 'Other'}}")
        lua.globals().readMode = mode
        _, enumerated = lua.globals().BlizzardAPI.GetAuras("player", "HELPFUL")
        assert enumerated is complete, mode
        cache = lua.globals().RefreshAuraCache()
        assert cache.complete is complete, mode
        assert lua.globals().PetNeedsRez() is complete, mode
        assert lua.globals().trustedOutOfCombatCache.byID[900] is True, mode
    lua.execute("now = now + 1; readMode = 'batch'; liveList = {}")
    assert lua.globals().RefreshAuraCache().complete is True
    for payload in ("{secretValue}", "{{spellId = secretValue}}", "{{name = 'Unknown'}}"):
        lua.execute(f"now = now + 1; liveList = {payload}")
        assert lua.globals().RefreshAuraCache().complete is False
        assert lua.globals().PetNeedsRez() is False
    lua.execute("now = now + 1; restricted = true; combat = false; liveList = {}")
    assert lua.globals().RefreshAuraCache().complete is False
    assert lua.globals().PetNeedsRez() is False
    lua.execute("now = now + 1; combat = true")
    assert lua.globals().RefreshAuraCache().complete is False
    lua.execute("now = now + 1; restricted = false; combat = false")
    assert lua.globals().RefreshAuraCache().complete is True
    assert lua.globals().PetNeedsRez() is True
    source = (ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8")
    start = source.index("local function IsSecret(")
    end = source.index("\n-- Top-off", start)
    lua.execute("issecretvalue = BlizzardAPI.IsSecretValue; ReportAuraReadError = function() end")
    lua.execute(source[start:end].replace("local function SafeAuraList(", "function SafeAuraList(", 1))
    lua.execute("C_UnitAuras.GetUnitAuras = nil; readMode = 'capped'")
    assert lua.globals().SafeAuraList("player", "HELPFUL") == (None, False)
    lua.execute("readMode = 'index'; liveList = {}")
    _, complete = lua.globals().SafeAuraList("player", "HELPFUL")
    assert complete is True


def test_pet_status():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        BlizzardAPI = {}
        exists, dead = true, false
        secretValue = {}
        function IsSecretValue(v) return v == secretValue end
        errors = {}
        function geterrorhandler()
            return function(err) errors[#errors + 1] = err end
        end
        function UnitExists()
            if denyExists then error("existence denied") end
            return exists
        end
        function UnitIsDead()
            if denyDead then error("death denied") end
            return dead
        end
    """)
    start = source.index("function BlizzardAPI.GetPetStatus()")
    end = source.index("\nend", start) + len("\nend")
    lua.execute(source[start:end])
    for setup, expected in (
        ("exists = true; dead = false", "alive"),
        ("dead = true", "dead"),
        ("exists = false", "missing"),
        ("exists = nil", None),
        ("exists = secretValue", None),
        ("exists = true; dead = secretValue", None),
        ("dead = nil", None),
        ("denyExists = true", None),
        ("denyExists = false; denyDead = true", None),
    ):
        lua.execute(setup)
        assert lua.globals().BlizzardAPI.GetPetStatus() == expected, setup
    assert len(lua.globals().errors) == 2


def test_surface_dispatch():
    source = SOURCE.read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute("""
        now = 10
        GetTime = function() return now end
        inCombat, mounted = true, false
        UnitAffectingCombat = function() return inCombat end
        IsMounted = function() return mounted end
        BlizzardAPI.HiddenInContent = function() return false end
        HEALTH_UPDATE_THROTTLE, lastHealthUpdate = 0.1, 0
        profile = {
            displayMode = "both", maxIcons = 4,
            defensives = { enabled = true, maxIcons = 2 },
            nameplateOverlay = { showDefensives = true, maxDefensiveIcons = 2 },
            precombatBuffs = { enabled = false },
        }
        addon.GetProfile = function() return profile end
        UINameplateOverlay = {}
        dpsQueueExclusions, overlayExclusions = {}, {}
        function FillExclusions(set) wipe(set) end
        function ResolveHealthState() return false end
        function HideDefensiveIconFrames() mainShown = nil end
        function ResizeHealthBars() end
        baseCount = 0
        DefensiveEngine.GetDefensiveSpellQueue = function()
            local results = {}
            for i = 1, baseCount do results[i] = {spellID = 900 + i} end
            return results, {}
        end
        function ApplyMainPanelQueue(_, results) mainShown = results end
        function ApplyOverlayQueue(_, results) overlayShown = results end
    """)
    lua.execute(extract_helper(source, "PetNeedsRez", "IsPetCombatPrioritySpec"))
    lua.execute(extract_helper(source, "IsPetCombatPrioritySpec"))
    lua.execute(extract_get_usable(source))
    start = source.index("AppendUsableSpells = function(")
    end = source.index("\nlocal precombatPetAdded", start)
    lua.execute(source[start:end])
    start = source.index("function DefensiveEngine.OnHealthChanged(")
    end = source.index("\n--------------------------------------------------------------------------------", start)
    lua.execute(source[start:end])
    for is_forever in (False, True):
        lua.globals().forever = is_forever
        lua.execute("foreverTree = 'beast_mastery'; specKey = 'HUNTER_1'; playerClass = 'HUNTER'")
        for setup, expected in (
            ("petlessByChoice = false; petStatus = 'missing'", 1),
            ("petStatus = 'dead'", 1),
            ("petStatus = 'alive'; petlessByChoice = nil", 0),
            ("petStatus = 'alive'", 0),
            ("petStatus = nil", 0),
            ("petStatus = 'missing'; petlessByChoice = nil", 0),
            ("petlessByChoice = true", 0),
            ("petlessByChoice = false; mounted = true", 0),
            ("mounted = false; baseCount = 2", 2),
            ("baseCount = 0; blacklisted[101] = true; blacklisted[303] = true; blacklisted[202] = true", 0),
            ("blacklisted = {}; inCombat = false", 0),
            ("inCombat = true; specKey = 'HUNTER_2'; foreverTree = 'marksmanship'", 0),
        ):
            lua.execute(setup + "; now = now + 1")
            lua.globals().DefensiveEngine.OnHealthChanged(lua.globals().addon, None, "pet")
            assert len(lua.globals().mainShown) == expected, (is_forever, setup, "main")
            assert len(lua.globals().overlayShown) == expected, (is_forever, setup, "overlay")
        # Overlay-only remains independent of the disabled main panel.
        lua.execute("""
            specKey = 'HUNTER_1'; foreverTree = 'beast_mastery'
            profile.displayMode = 'overlay'; profile.defensives.enabled = false
            now = now + 1
        """)
        lua.globals().DefensiveEngine.OnHealthChanged(lua.globals().addon, None, "pet")
        assert lua.globals().mainShown is None
        assert len(lua.globals().overlayShown) == 1
        lua.execute("profile.defensives.enabled = true; profile.displayMode = 'both'")
        lua.execute("""
            stateReads = 0
            BlizzardAPI.GetPetStatus = function() stateReads = stateReads + 1; return 'missing' end
            BlizzardAPI.IsSpellAvailable = function() return false end
            now = now + 1
        """)
        lua.globals().DefensiveEngine.OnHealthChanged(lua.globals().addon, None, "pet")
        assert lua.globals().stateReads == 0
        assert len(lua.globals().mainShown) == 0 and len(lua.globals().overlayShown) == 0
        lua.execute("BlizzardAPI.IsSpellAvailable = function() return true end")
        lua.execute("""
            petlessReads = 0
            BlizzardAPI.GetPetStatus = function() return 'alive' end
            BlizzardAPI.IsPetlessByChoice = function() petlessReads = petlessReads + 1; return nil end
        """)
        for _ in range(5):
            lua.execute("now = now + 1")
            lua.globals().DefensiveEngine.OnHealthChanged(lua.globals().addon, None, "pet")
            assert len(lua.globals().mainShown) == 0 and len(lua.globals().overlayShown) == 0
        assert lua.globals().petlessReads == 0, "a live pet needs no aura evidence"
        assert lua.globals().DefensiveEngine.GetPetReminderState(
            lua.globals().addon
        ) == (False, "pet alive")
        lua.execute("""
            BlizzardAPI.GetPetStatus = function() return petStatus end
            BlizzardAPI.IsPetlessByChoice = function() return petlessByChoice end
        """)


def test_primary_pet_recovery():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellQueue = {}
        class, status, summonUsable, summonPower = 'HUNTER', 'dead', true, false
        reviveUsable, ready, learned, blocked = true, true, true, false
        configured = {982, 883}
        function UnitClass() return '', class end
        RedundancyFilter = {
            IsPetSummonSpell=function(id) return id==883 or id==688 end,
            IsPetReviveSpell=function(id) return id==982 end,
        }
        BlizzardAPI = {
            GetPetStatus=function() return status end,
            IsSpellUsable=function(id)
                if id==982 then return reviveUsable, false end
                return summonUsable, summonPower
            end,
            GetAddon=function() return {} end,
            GetDisplaySpellID=function(id) return id end,
            IsSpellAvailable=function() return learned end,
            IsSpellReady=function() return ready end,
        }
        SpellQueue.IsSpellBlacklisted=function() return blocked end
        LibStub=function()
            return {GetClassSpellList=function() return configured end}
        end
    """)
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("function SpellQueue.ResolvePetRecoveryPick(")
    end = source.index("\nfunction SpellQueue._StagePrimary", start)
    lua.execute(source[start:end])
    fn = lua.globals().SpellQueue.ResolvePetRecoveryPick
    assert fn(883, lua.table()) == 982, "dead hunter pet needs revive, not call"
    for setup in ("reviveUsable=false", "ready=false", "learned=false", "blocked=true", "configured={}; summonUsable=false"):
        lua.execute("reviveUsable=true; ready=true; learned=true; blocked=false; configured={982,883}")
        lua.execute(setup)
        assert fn(883, lua.table()) is None, setup
    lua.execute("configured={982,883}; learned=true; blocked=false; status='missing'; summonUsable=false")
    assert fn(883, lua.table()) == 982, "engine castability can establish usable recovery"
    lua.execute("status='alive'")
    assert fn(883, lua.table()) is None
    lua.execute("status=nil; summonUsable=nil")
    assert fn(883, lua.table()) == 883, "unknown is not proof of death"
    lua.execute("status='missing'; summonUsable=false; summonPower=true")
    assert fn(883, lua.table()) == 883, "resource shortfall is not proof of death"
    lua.execute("class='WARLOCK'; configured={688}; status='dead'; summonUsable=true; summonPower=false")
    assert fn(688, lua.table()) == 688, "warlocks resummon dead demons"
    assert fn(19574, lua.table()) == 19574, "ordinary AC picks unchanged"
    lua.execute("""
        class='HUNTER'; configured={982,883}; status='dead'; summonUsable=true
        SpellQueue.LeadMode=function() return 'game' end
        SpellQueue.IsCasterSuppressedPick=function() return false end
        BlizzardAPI.IsForever=function() return forever end
        BlizzardAPI.GetHighlightCastSpell=function() return highlight end
        function NotePick() end
        function ClaimSpellID(id, added)
            if added[id] then return nil end
            added[id]=true; return id
        end
    """)
    primary_start = source.index("function SpellQueue._StagePrimary(b)")
    primary_end = source.index("\nfunction SpellQueue.GetCurrentSpellQueue()", primary_start)
    lua.execute(source[primary_start:primary_end])
    for forever in (False, True):
        lua.globals().forever = forever
        for primary, highlight in ((883, None), (19574, 883)):
            lua.globals().highlight = highlight
            lua.execute("ready=true; learned=true; blocked=false; reviveUsable=true")
            b = lua.table_from({
                "profile": lua.table(), "primarySpellID": primary,
                "blacklist": lua.table(), "addedSpellIDs": lua.table(),
                "recommendedSpells": lua.table(), "spellCount": 0,
            })
            if primary == 19574:
                lua.execute("SpellQueue.IsCasterSuppressedPick=function(id) return id==19574 end")
            else:
                lua.execute("SpellQueue.IsCasterSuppressedPick=function() return false end")
            lua.globals().SpellQueue._StagePrimary(b)
            assert b.recommendedSpells[1] == 982, (forever, primary, highlight)
    lua.execute("""
        SpellQueue.NoteQueueBlank=function() end
        SpellQueue._ApplySafeLead=function() end
        lastSpellIDs={883,19574}
        reviveUsable=false
    """)
    finalize_start = source.index("function SpellQueue._StageFinalize(b)")
    finalize_end = source.index("\n--- Stage D", finalize_start)
    lua.execute(source[finalize_start:finalize_end])
    lua.globals().SpellQueue._StageFinalize(lua.table_from({
        "spellCount": 0, "recommendedSpells": lua.table(), "blacklist": lua.table(),
    }))
    assert list(lua.globals().lastSpellIDs.values()) == [19574], "empty build cannot retain blocked summon"


def main():
    source = SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(extract_helper(source, "PetNeedsRez", "IsPetCombatPrioritySpec"))
    lua.execute(extract_helper(source, "IsPetCombatPrioritySpec"))
    lua.execute(extract_get_usable(source))
    start = source.index("local precombatPetAdded = {}")
    end = source.index("\nend\n\n-- Reorder a defensive list", start) + len("\nend")
    helper = source[start:end].replace(
        "local function AppendPrecombatPetRez(",
        "function AppendPrecombatPetRez(",
        1,
    )
    lua.execute(helper)
    lua.execute("""
        function spell_ids(spells, limit, respectBlacklist)
            local result = GetUsableDefensiveSpells(addon, spells, limit, {}, respectBlacklist)
            local ids = {}
            for i, entry in ipairs(result) do ids[i] = entry.storedID end
            return ids
        end
    """)

    lua.execute("blacklisted[101] = true; blacklisted[303] = { fixedQueue = true }")
    assert list(lua.globals().spell_ids(lua.table_from([101, 303, 202]), 1, True).values()) == [202]
    assert list(lua.globals().spell_ids(lua.table_from([101, 303, 202]), 3, False).values()) == [101, 303, 202]
    assert list(lua.globals().spell_ids(lua.table_from([101]), 1, True).values()) == []

    results, added = lua.table(), lua.table()
    lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
    assert results[1].spellID == 202 and results[1].precombat is True
    assert added[202] is True
    for is_forever in (False, True):
        lua.globals().forever = is_forever
        results, added = lua.table(), lua.table_from({202: True})
        lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
        assert len(results) == 1 and results[1].spellID == 202
        assert results[1].precombat is True
        lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
        assert len(results) == 1

        lua.execute("blacklisted[202] = true")
        results, added = lua.table(), lua.table_from({202: True})
        lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
        assert len(results) == 0
        lua.execute("blacklisted[202] = { fixedQueue = true }")
        lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
        assert len(results) == 0
        lua.execute("blacklisted[202] = nil")
    results, added = lua.table(), lua.table()
    lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 0)
    assert len(results) == 0
    lua.execute("petStatus = 'alive'")
    results, added = lua.table(), lua.table()
    lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
    assert len(results) == 0
    lua.execute("petStatus = 'dead'; petlessByChoice = true")
    results, added = lua.table(), lua.table()
    lua.globals().AppendPrecombatPetRez(lua.globals().addon, results, added, 3)
    assert len(results) == 0

    priority = lua.globals().IsPetCombatPrioritySpec
    lua.execute("petlessByChoice = false; forever = false; specKey = 'HUNTER_1'; playerClass = 'HUNTER'")
    assert priority() is True
    lua.execute("specKey = 'HUNTER_2'")
    assert priority() is False
    lua.execute("specKey = 'WARLOCK_2'; playerClass = 'WARLOCK'")
    assert priority() is True
    lua.execute("specKey = 'WARLOCK_1'")
    assert priority() is False
    lua.execute("forever = true; playerClass = 'HUNTER'; foreverTree = 'beast_mastery'")
    assert priority() is True
    lua.execute("foreverTree = 'survival'")
    assert priority() is False
    lua.execute("playerClass = 'WARLOCK'; foreverTree = 'demonology'")
    assert priority() is True
    lua.execute("foreverTree = 'affliction'")
    assert priority() is False

    pet_calls = [
        line for line in source.splitlines()
        if "AppendUsableSpells(" in line and "GetClassSpellList(addon, \"petRezSpells\")" in line
    ]
    assert len(pet_calls) == 2 and all(", true)" in line for line in pet_calls)
    assert "AppendPrecombatPetRez(addon, results, alreadyAdded, maxIcons)" in source
    test_precombat_visibility()
    test_petless_aura_cache()
    test_aura_read_completeness()
    test_pet_status()
    test_surface_dispatch()
    test_primary_pet_recovery()
    print("pet reminders: complete/partial/denied/secret aura reads, tri-state pet status, both clients/surfaces passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
