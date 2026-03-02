-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Info, Usability, Rotation API, Item Detection, Availability
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after SecretValues.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-SpellQuery", 1
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime    = GetTime
local pcall      = pcall
local type       = type
local wipe       = wipe
local ipairs     = ipairs
local math_min   = math.min
local UnitHealth    = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitExists    = UnitExists
local UnitIsDead    = UnitIsDead ---@diagnostic disable-line: undefined-global
local IsSpellKnown  = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell
local C_SpellBook_IsSpellInSpellBook    = C_SpellBook and C_SpellBook.IsSpellInSpellBook
local C_Spell_IsSpellPassive            = C_Spell and C_Spell.IsSpellPassive
local C_Spell_GetSpellInfo              = C_Spell and C_Spell.GetSpellInfo
local C_Spell_GetSpellCooldown          = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges           = C_Spell and C_Spell.GetSpellCharges
local C_Spell_IsSpellUsable             = C_Spell and C_Spell.IsSpellUsable
local C_Spell_GetOverrideSpell          = C_Spell and C_Spell.GetOverrideSpell
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local Enum_SpellBookSpellBank_Player    = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local FindSpellOverrideByID             = FindSpellOverrideByID
local GetInventoryItemID                = GetInventoryItemID ---@diagnostic disable-line: undefined-global
local GetItemSpell                      = GetItemSpell
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

local SpellDB = LibStub("JustAC-SpellDB", true)

--------------------------------------------------------------------------------
-- Addon Access & Profile Management
--------------------------------------------------------------------------------

local cachedAddon = nil
local function GetAddon()
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedAddon
end

-- Expose for other modules that need cached addon access
BlizzardAPI.GetAddon = GetAddon

function BlizzardAPI.GetProfile()
    local addon = GetAddon()
    if not addon or not addon.db then return nil end
    return addon.db.profile
end

function BlizzardAPI.GetCharData()
    local addon = GetAddon()
    if not addon or not addon.db then return nil end
    return addon.db.char
end

local cachedDebugMode = false
local lastDebugModeCheck = 0
local DEBUG_MODE_CACHE_DURATION = 1.0

function BlizzardAPI.GetDebugMode()
    local now = GetTime()
    if now - lastDebugModeCheck > DEBUG_MODE_CACHE_DURATION then
        local profile = BlizzardAPI.GetProfile()
        cachedDebugMode = profile and profile.debugMode or false
        lastDebugModeCheck = now
    end
    return cachedDebugMode
end

function BlizzardAPI.RefreshDebugMode()
    lastDebugModeCheck = 0
end

function BlizzardAPI.IsCurrentSpecHealer()
    local spec = GetSpecialization()
    if not spec then return false end
    local _, _, _, _, role = GetSpecializationInfo(spec)
    return role == "HEALER"
end

local function GetDebugMode()
    return BlizzardAPI.GetDebugMode()
end

--------------------------------------------------------------------------------
-- Spell Info & Rotation API
--------------------------------------------------------------------------------

function BlizzardAPI.GetSpellInfo(spellID)
    if not spellID or spellID == 0 then return nil end
    if not C_Spell_GetSpellInfo then return nil end
    return C_Spell_GetSpellInfo(spellID)
end

-- Spell info cache for GetCachedSpellInfo (prevents duplicate API calls)
local spellInfoCache = {}

function BlizzardAPI.GetCachedSpellInfo(spellID)
    if not spellID or spellID == 0 then return nil end

    -- Return immediately if already cached to avoid repeated API calls
    local cached = spellInfoCache[spellID]
    if cached then return cached end

    -- Cache spells to prevent duplicate API calls (200~ max spells per character)
    local spellInfo = BlizzardAPI.GetSpellInfo(spellID)
    if not spellInfo then return nil end

    spellInfoCache[spellID] = spellInfo
    return spellInfo
end

function BlizzardAPI.ClearSpellCache()
    wipe(spellInfoCache)
end

-- checkForVisibleButton: true=visible only, false=include hidden (macro conditionals)
function BlizzardAPI.GetNextCastSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return nil end

    local profile = BlizzardAPI.GetProfile()
    local includeHidden = profile and profile.includeHiddenAbilities or false
    local checkForVisibleButton = not includeHidden

    local success, result = pcall(C_AssistedCombat.GetNextCastSpell, checkForVisibleButton)
    if success and result and type(result) == "number" and result > 0 then
        return result
    end
    return nil
end

function BlizzardAPI.GetRotationSpells()
    if not C_AssistedCombat or not C_AssistedCombat.GetRotationSpells then return nil end

    local success, result = pcall(C_AssistedCombat.GetRotationSpells)
    if success and result and type(result) == "table" and #result > 0 then
        for i = 1, #result do
            if type(result[i]) ~= "number" or result[i] <= 0 then
                return nil
            end
        end
        return result
    end
    return nil
end

function BlizzardAPI.IsAssistedCombatAvailable()
    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable then return false, "API not available" end

    local success, isAvailable, failureReason = pcall(C_AssistedCombat.IsAvailable)
    if success then
        return isAvailable, failureReason
    end
    return false, "API call failed"
end

function BlizzardAPI.HasAssistedCombatActionButtons()
    if not C_ActionBar or not C_ActionBar.HasAssistedCombatActionButtons then return false end

    local success, result = pcall(C_ActionBar.HasAssistedCombatActionButtons)
    return success and result or false
end

function BlizzardAPI.GetActionInfo(slot)
    if not slot or not HasAction(slot) then return nil, nil, nil, nil end

    local actionType, id, subType, spell_id_from_macro = GetActionInfo(slot)

    -- Filter Assisted Combat placeholder slots (Blizzard uses subType == "assistedcombat")
    if actionType == "spell" and (subType == "assistedcombat" or (type(id) == "string" and id == "assistedcombat")) then
        return nil, nil, nil, nil
    end

    return actionType, id, subType, spell_id_from_macro
end

function BlizzardAPI.ValidateAssistedCombatSetup()
    local debugMode = GetDebugMode()
    local issues = {}

    -- Check API availability
    local isAvailable, failureReason = BlizzardAPI.IsAssistedCombatAvailable()
    if not isAvailable then
        issues[#issues + 1] = "Assisted Combat not available: " .. (failureReason or "unknown reason")
    end

    -- Check action buttons
    local hasActionButtons = BlizzardAPI.HasAssistedCombatActionButtons()
    if not hasActionButtons then
        issues[#issues + 1] = "No assisted combat action buttons found"
    end

    -- Check if we can get rotation spells
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells or #rotationSpells == 0 then
        issues[#issues + 1] = "No rotation spells returned (may be normal out of combat)"
    end

    if debugMode then
        if #issues == 0 then
            print("|JAC| Assisted Combat setup validation: ALL GOOD")
        else
            print("|JAC| Assisted Combat setup validation: " .. #issues .. " issues found")
            for i, issue in ipairs(issues) do
                print("|JAC|   " .. i .. ". " .. issue)
            end
        end
    end

    return #issues == 0, issues
end

-- Enhanced debug function that matches Blizzard's approach
function BlizzardAPI.TestAssistedCombatAPI()
    print("|JAC| === Assisted Combat API Test (Blizzard-Style) ===")

    -- Check basic availability
    local isAvailable, failureReason = BlizzardAPI.IsAssistedCombatAvailable()
    print("|JAC| IsAvailable: " .. tostring(isAvailable) .. " (" .. (failureReason or "no reason") .. ")")

    -- Check player state
    local inCombat = UnitAffectingCombat("player")
    local spec = GetSpecialization()
    local level = UnitLevel("player")
    local class = select(2, UnitClass("player"))

    print("|JAC| Player State:")
    print("|JAC|   Class: " .. tostring(class))
    print("|JAC|   Level: " .. tostring(level))
    print("|JAC|   Spec: " .. tostring(spec))
    print("|JAC|   In Combat: " .. tostring(inCombat))

    -- Check CVars (critical for system to work)
    local assistedMode = GetCVarBool("assistedMode")
    local assistedHighlight = GetCVarBool("assistedCombatHighlight")
    local updateRate = tonumber(GetCVar("assistedCombatIconUpdateRate")) or 0

    print("|JAC| CVars:")
    print("|JAC|   assistedMode: " .. tostring(assistedMode))
    print("|JAC|   assistedCombatHighlight: " .. tostring(assistedHighlight))
    print("|JAC|   assistedCombatIconUpdateRate: " .. tostring(updateRate))

    -- Check action button system
    local hasActionButtons = BlizzardAPI.HasAssistedCombatActionButtons()
    print("|JAC| HasAssistedCombatActionButtons: " .. tostring(hasActionButtons))

    -- Test rotation spells
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if rotationSpells and #rotationSpells > 0 then
        print("|JAC| Current rotation spells: " .. #rotationSpells .. " entries")
        for i = 1, math_min(#rotationSpells, 5) do
            local spellInfo = BlizzardAPI.GetSpellInfo(rotationSpells[i])
            local name = spellInfo and spellInfo.name or "Unknown"
            print("|JAC|   " .. i .. ": " .. name .. " (" .. tostring(rotationSpells[i]) .. ")")
        end
        if #rotationSpells > 5 then
            print("|JAC|   ... and " .. (#rotationSpells - 5) .. " more")
        end
    else
        print("|JAC| No rotation spells returned")
    end

    -- Test next cast spell (using correct parameter)
    local nextCastSpell = BlizzardAPI.GetNextCastSpell()
    if nextCastSpell then
        local spellInfo = BlizzardAPI.GetSpellInfo(nextCastSpell)
        local name = spellInfo and spellInfo.name or "Unknown"
        print("|JAC| GetNextCastSpell(true): " .. name .. " (" .. tostring(nextCastSpell) .. ")")
    else
        print("|JAC| GetNextCastSpell(true): No spell")
    end

    -- Validation summary
    local isValid, issues = BlizzardAPI.ValidateAssistedCombatSetup()
    print("|JAC| System Status: " .. (isValid and "READY" or "NEEDS SETUP"))

    if not isValid then
        print("|JAC| Setup Issues:")
        for i, issue in ipairs(issues) do
            print("|JAC|   " .. i .. ". " .. issue)
        end
    end

    -- Secrecy API quick test: surface results for the sample spell (primary or first rotation)
    local sample = nextCastSpell or (rotationSpells and rotationSpells[1])
    if sample then
        local cdLevel = BlizzardAPI.GetSpellCooldownSecrecy and BlizzardAPI.GetSpellCooldownSecrecy(sample)
        local auraLevel = BlizzardAPI.GetSpellAuraSecrecy and BlizzardAPI.GetSpellAuraSecrecy(sample)
        local castLevel = BlizzardAPI.GetSpellCastSecrecy and BlizzardAPI.GetSpellCastSecrecy(sample)
        local start, dur = BlizzardAPI.GetSafeSpellCooldown(sample)
        print("|JAC| Secrecy for sample spell (" .. tostring(sample) .. "):")
        print("|JAC|   cooldown secrecy: " .. tostring(cdLevel) .. ", aura secrecy: " .. tostring(auraLevel) .. ", cast secrecy: " .. tostring(castLevel))
        print("|JAC|   safe cooldown read: start=" .. tostring(start) .. ", duration=" .. tostring(dur))
    end

    print("|JAC| =====================================")
end

-- Raw values (may be secret); Cooldown widget handles them
function BlizzardAPI.GetSpellCooldown(spellID)
    if not C_Spell_GetSpellCooldown then return 0, 0 end
    local cd = C_Spell_GetSpellCooldown(spellID)
    if cd then
        return cd.startTime, cd.duration
    end
    return 0, 0
end

-- Sanitized values for comparison.
-- Returns start, duration, isOnRealCooldown (three returns).
-- When secreted: returns 0, 0 but uses isOnGCD + local tracking to infer cooldown state.
-- Third return: true = definitely on real CD, false = definitely not, nil = unknown
function BlizzardAPI.GetSpellCooldownValues(spellID)
    if not C_Spell_GetSpellCooldown then return 0, 0, false end
    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return 0, 0, false end
    local startTime = cd.startTime
    local duration = cd.duration
    if IsSecretValue(startTime) or IsSecretValue(duration) then
        -- Values are secret in combat.
        -- isOnGCD == true → GCD only, not on real CD
        if cd.isOnGCD == true then return 0, 0, false end
        -- isOnGCD == false → real cooldown running (flagged spells)
        if cd.isOnGCD == false then return 0, 0, true end
        -- isOnGCD == nil → ambiguous (off CD or unflagged spell on CD)
        -- Use local cooldown tracking as tiebreaker
        if BlizzardAPI.IsSpellOnLocalCooldown(spellID) then return 0, 0, true end
        -- No local tracking data → unknown, report nil
        return 0, 0, nil
    end
    return startTime or 0, duration or 0, false
end

-- Blizzard's dummy GCD spell always returns current GCD state
local GCD_SPELL_ID = 61304

function BlizzardAPI.GetGCDInfo()
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
        if cd then
            local startTime = cd.startTime
            local duration = cd.duration
            if IsSecretValue(startTime) or IsSecretValue(duration) then
                return 0, 0
            end
            return startTime or 0, duration or 0
        end
    end
    return 0, 0
end

-- Check if a spell is only on GCD (not a real cooldown).
-- 12.0 combat: isOnGCD == true is the only reliable in-combat signal.
-- isOnGCD is absent (nil) for both "off CD" and "real CD" — cannot distinguish.
function BlizzardAPI.IsSpellOnGCD(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return false end

    local ok, spellCD = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not spellCD then return false end

    -- isOnGCD is NeverSecret — true means "only GCD, no real CD"
    if spellCD.isOnGCD == true then return true end

    -- isOnGCD is nil → either no cooldown or real cooldown (indistinguishable in combat)
    -- Fall back to comparing start/duration when values are readable (out of combat)
    if IsSecretValue(spellCD.startTime) or IsSecretValue(spellCD.duration) then
        return false
    end

    local spellDuration = spellCD.duration
    if not spellDuration or spellDuration == 0 then
        return false
    end

    local gcdCD = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
    if not gcdCD then return false end

    local gcdStart = gcdCD.startTime
    local gcdDuration = gcdCD.duration
    if IsSecretValue(gcdStart) or IsSecretValue(gcdDuration) then
        return false
    end

    if not gcdDuration or gcdDuration == 0 then
        return false
    end

    return spellCD.startTime == gcdStart and spellDuration == gcdDuration
end

-- 12.0 fallbacks: local cooldown tracking, action bar usability
function BlizzardAPI.IsSpellOnRealCooldown(spellID)
    if not spellID then return false end

    local start, duration, onRealCD = BlizzardAPI.GetSpellCooldownValues(spellID)

    -- If values were secret with definitive answer from tracking
    if onRealCD == true then return true end

    if start and start > 0 and duration and duration > 0 then
        if BlizzardAPI.IsSpellOnGCD(spellID) then
            return false
        end
        return true
    end

    -- Charge-based spell check
    if C_Spell_GetSpellCharges then
        local success, chargeInfo = pcall(C_Spell_GetSpellCharges, spellID)
        if success and chargeInfo then
            local currentCharges = chargeInfo.currentCharges
            if currentCharges then
                if IsSecretValue(currentCharges) then
                    -- Secret value: fail-open (assume usable) to prevent hiding spells
                    -- that may have charges available
                    return false
                end
                if currentCharges == 0 then
                    return true
                else
                    return false
                end
            end
        end
    end

    -- Local cooldown tracking
    if BlizzardAPI.IsSpellOnLocalCooldown(spellID) then
        return true
    end

    -- Action bar usability
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
        local slot = ActionBarScanner.GetSlotForSpell(spellID)
        if slot and C_ActionBar and C_ActionBar.IsUsableAction then
            local actionUsable, notEnoughMana = C_ActionBar.IsUsableAction(slot)
            -- Check for secrets before comparing - fail-open (assume usable = show)
            if IsSecretValue(actionUsable) or IsSecretValue(notEnoughMana) then
                return false  -- Fail-open: assume NOT on cooldown (show)
            end
            if actionUsable == false and not notEnoughMana then
                return true
            end
            if actionUsable == true then
                return false
            end
        end
    end

    local isUsable, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID)
    if not isUsable and not notEnoughResources then
        if not BlizzardAPI.IsSpellOnGCD(spellID) then
            return true
        end
    end

    return false
end

-- 12.0: Falls back to action bar state when secret.
-- failOpen (default true): return true when usability can't be determined.
-- Pass false for gap closers where suggesting an unusable spell is worse than skipping.
function BlizzardAPI.IsSpellUsable(spellID, failOpen)
    if failOpen == nil then failOpen = true end
    if not spellID or spellID == 0 then return false, false end

    if C_Spell_IsSpellUsable then
        local success, isUsable, notEnoughResources = pcall(C_Spell_IsSpellUsable, spellID)
        if success then
            if IsSecretValue(isUsable) or IsSecretValue(notEnoughResources) then
                local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                if ActionBarScanner and ActionBarScanner.GetSlotForSpell and C_ActionBar and C_ActionBar.IsUsableAction then
                    local slot = ActionBarScanner.GetSlotForSpell(spellID)
                    if slot then
                        local actionUsable, actionNotEnoughMana = C_ActionBar.IsUsableAction(slot)
                        if not IsSecretValue(actionUsable) and not IsSecretValue(actionNotEnoughMana) then
                            return actionUsable or false, actionNotEnoughMana or false
                        end
                    end
                end
                return failOpen, false
            end
            return isUsable, notEnoughResources
        end
    end

    return failOpen, false
end

--------------------------------------------------------------------------------
-- Centralized Utility Functions
--------------------------------------------------------------------------------

-- Per-update cache for proc results (cleared by ClearProcCache, called from SpellQueue)
local procResultCache = {}
local procCacheTime = 0
local PROC_CACHE_DURATION = 0.05  -- 50ms - cleared on each update cycle

-- Override spell cache - spell morphs change infrequently (Metamorphosis, etc.)
-- Cache per update cycle, cleared along with proc cache
local overrideSpellCache = {}

function BlizzardAPI.ClearProcCache()
    wipe(procResultCache)
    wipe(overrideSpellCache)  -- Also clear override cache each update cycle
    procCacheTime = GetTime()
end

-- Checks both provided ID and override ID (events may fire with different IDs)
-- Results cached per update cycle to avoid redundant API calls
function BlizzardAPI.IsSpellProcced(spellID)
    if not spellID or spellID == 0 then return false end

    -- Check cache first (valid for this update cycle)
    local cached = procResultCache[spellID]
    if cached ~= nil then
        return cached
    end

    -- Auto-expire cache if not cleared by caller
    local now = GetTime()
    if now - procCacheTime > PROC_CACHE_DURATION then
        wipe(procResultCache)
        procCacheTime = now
    end

    local result = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(spellID)

    if IsSecretValue(result) then
        procResultCache[spellID] = false
        return false
    end

    if result then
        procResultCache[spellID] = true
        return true
    end

    local overrideID = BlizzardAPI.GetDisplaySpellID(spellID)
    if overrideID and overrideID ~= spellID then
        local overrideResult = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(overrideID)
        if IsSecretValue(overrideResult) then
            procResultCache[spellID] = false
            return false
        end
        if overrideResult then
            procResultCache[spellID] = true
            return true
        end
    end

    procResultCache[spellID] = false
    return false
end

-- Resolves override spells (e.g., Metamorphosis transformations)
-- PERFORMANCE: Cache results per update cycle (overrides change infrequently)
function BlizzardAPI.GetDisplaySpellID(spellID)
    if not spellID or spellID == 0 then return spellID end
    if not C_Spell_GetOverrideSpell then return spellID end

    -- Check cache first (cleared each update cycle by ClearProcCache)
    local cached = overrideSpellCache[spellID]
    if cached ~= nil then
        return cached
    end

    local override = C_Spell_GetOverrideSpell(spellID)
    if override and override ~= 0 and override ~= spellID then
        overrideSpellCache[spellID] = override
        return override
    end
    overrideSpellCache[spellID] = spellID  -- Cache "no override" as well
    return spellID
end

--- Resolves a talent override for a spell using FindSpellOverrideByID.
--- Used by DefensiveEngine and GapCloserEngine for proc/rotation dedup.
--- Distinct from GetDisplaySpellID (which uses C_Spell.GetOverrideSpell for
--- action-bar display transforms like Metamorphosis).
--- Returns the override ID when a talent replaces the spell, or spellID otherwise.
function BlizzardAPI.ResolveSpellID(spellID)
    if FindSpellOverrideByID then
        local overrideID = FindSpellOverrideByID(spellID)
        if overrideID and overrideID ~= 0 and overrideID ~= spellID then
            return overrideID
        end
    end
    return spellID
end

function BlizzardAPI.IsOffensiveSpell(spellID)
    if not spellID then return true end
    if not SpellDB then return true end
    return SpellDB.IsOffensiveSpell(spellID)
end

function BlizzardAPI.IsDefensiveSpell(spellID)
    if not spellID then return false end
    if not SpellDB then return false end
    return SpellDB.IsDefensiveSpell(spellID) or SpellDB.IsHealingSpell(spellID)
end

function BlizzardAPI.IsCrowdControlSpell(spellID)
    if not spellID then return false end
    if not SpellDB then return false end
    return SpellDB.IsCrowdControlSpell(spellID)
end

function BlizzardAPI.IsUtilitySpell(spellID)
    if not spellID then return false end
    if not SpellDB then return false end
    return SpellDB.IsUtilitySpell(spellID)
end

--------------------------------------------------------------------------------
-- Item Spell Detection
--------------------------------------------------------------------------------

local ITEM_USE_SLOTS = {
    6,   -- Belt
    10,  -- Gloves
    13,  -- Trinket1
    14,  -- Trinket2
    15,  -- Cloak
}

local itemSpellCache = {}
local itemSpellCacheTime = 0
local ITEM_SPELL_CACHE_DURATION = 10.0

local C_Item_GetItemSpell = C_Item and C_Item.GetItemSpell

local function RebuildItemSpellCache()
    wipe(itemSpellCache)
    for _, slot in ipairs(ITEM_USE_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            -- Try modern API first, fallback to legacy
            local _, spellID
            if C_Item_GetItemSpell then
                _, spellID = C_Item_GetItemSpell(itemID)
            elseif GetItemSpell then
                _, spellID = GetItemSpell(itemID)
            end
            if spellID and spellID > 0 then
                itemSpellCache[spellID] = itemID
            end
        end
    end
    itemSpellCacheTime = GetTime()
end

function BlizzardAPI.IsItemSpell(spellID)
    if not spellID or spellID == 0 then return false end

    local now = GetTime()
    if now - itemSpellCacheTime > ITEM_SPELL_CACHE_DURATION then
        RebuildItemSpellCache()
    end

    return itemSpellCache[spellID] ~= nil
end

function BlizzardAPI.RefreshItemSpellCache()
    itemSpellCacheTime = 0
end

function BlizzardAPI.GetSpellClassification(spellID)
    if not spellID then return "unknown" end
    if not SpellDB then return "unknown" end
    return SpellDB.GetSpellClassification(spellID)
end

local spellAvailabilityCache = {}
local spellAvailabilityCacheTime = 0
local AVAILABILITY_CACHE_DURATION = 2.0

function BlizzardAPI.ClearAvailabilityCache()
    wipe(spellAvailabilityCache)
    spellAvailabilityCacheTime = 0
end

function BlizzardAPI.IsSpellAvailable(spellID)
    if not spellID or spellID == 0 then return false end

    local now = GetTime()
    if now - spellAvailabilityCacheTime < AVAILABILITY_CACHE_DURATION then
        local cached = spellAvailabilityCache[spellID]
        if cached ~= nil then
            return cached
        end
    else
        wipe(spellAvailabilityCache)
        spellAvailabilityCacheTime = now
    end

    if C_SpellBook_IsSpellInSpellBook then
        if C_SpellBook_IsSpellInSpellBook(spellID, Enum_SpellBookSpellBank_Player) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end

    if IsSpellKnown then
        if IsSpellKnown(spellID) then
            spellAvailabilityCache[spellID] = true
            return true
        end
        if IsSpellKnown(spellID, true) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end

    if C_Spell_IsSpellPassive then
        local isPassive = C_Spell_IsSpellPassive(spellID)
        if isPassive then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end

    if C_Spell and C_Spell.GetSpellSubtext then
        local subtext = C_Spell.GetSpellSubtext(spellID)
        if subtext and subtext:lower():find("passive") then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end

    if IsPlayerSpell and IsPlayerSpell(spellID) then
        spellAvailabilityCache[spellID] = true
        return true
    end

    spellAvailabilityCache[spellID] = false
    return false
end

-- UnitHealth/UnitHealthMax don't return secrets for player units
function BlizzardAPI.GetPlayerHealthPercent()
    if not UnitExists("player") then return nil end

    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")

    if BlizzardAPI.IsSecretValue(health) or BlizzardAPI.IsSecretValue(maxHealth) then
        return nil
    end
    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end

-- Pet health IS secret in 12.0 combat (PvE and PvP). Returns nil when secret.
-- This means pet heals only trigger out of combat. Pet rez/summon uses
-- GetPetStatus() instead, which relies on UnitIsDead/UnitExists (not secret).
function BlizzardAPI.GetPetHealthPercent()
    if not UnitExists("pet") then return nil end

    local ok, isDead = pcall(UnitIsDead, "pet")
    if ok then
        if IsSecretValue(isDead) then
            -- Can't determine dead status
        elseif isDead then
            return 0
        end
    end

    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")

    if IsSecretValue(health) or IsSecretValue(maxHealth) then
        return nil
    end
    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end

-- Returns pet status string: "dead", "missing", "alive", or nil (no pet class)
-- UnitExists and UnitIsDead are NOT secret — reliable in combat
-- Pet health IS secret in combat — use GetPetHealthPercent() for best-effort health
function BlizzardAPI.GetPetStatus()
    local ok, exists = pcall(UnitExists, "pet")
    if not ok or not exists then
        return "missing"
    end

    local ok2, isDead = pcall(UnitIsDead, "pet")
    if ok2 and isDead and not IsSecretValue(isDead) then
        return "dead"
    end

    return "alive"
end
