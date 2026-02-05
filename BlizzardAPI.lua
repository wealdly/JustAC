-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Blizzard API Module - Wraps WoW C_* APIs with 12.0+ secret value handling
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 28)
if not BlizzardAPI then return end

--------------------------------------------------------------------------------
-- Version Detection
--------------------------------------------------------------------------------
local WOW_VERSION_11_0_0 = 110000
local WOW_VERSION_12_0_0 = 120000
local CURRENT_VERSION = select(4, GetBuildInfo()) or 0
local IS_MIDNIGHT_OR_LATER = CURRENT_VERSION >= WOW_VERSION_12_0_0

-- Hot path: cache frequently used global functions to reduce table lookups
local GetTime = GetTime
local pcall = pcall
local type = type
local wipe = wipe
local bit_band = bit.band
local IsSpellKnown = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell
local C_SpellBook_IsSpellInSpellBook = C_SpellBook and C_SpellBook.IsSpellInSpellBook
local C_Spell_IsSpellPassive = C_Spell and C_Spell.IsSpellPassive
local C_Spell_GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local C_Spell_IsSpellUsable = C_Spell and C_Spell.IsSpellUsable
local C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local Enum_SpellBookSpellBank_Player = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

--------------------------------------------------------------------------------
-- Local Cooldown Tracking (12.0+ secret value workaround)
--------------------------------------------------------------------------------
-- Track cooldowns locally when API returns secrets in 12.0+ (fail-open approach)
local localCooldowns = {}
local cachedDurations = {}
local trackedDefensiveSpells = {}
local cooldownEventFrame = nil

local function IsLocalCooldownActive(spellID)
    local data = localCooldowns[spellID]
    if not data then return false end
    return GetTime() < data.endTime
end

local function GetBestCooldownDuration(spellID)
    if cachedDurations[spellID] and cachedDurations[spellID] > 0 then
        return cachedDurations[spellID]
    end
    local baseCooldownMs = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if baseCooldownMs and baseCooldownMs > 0 then
        return baseCooldownMs / 1000
    end
    return 0
end

local function RecordSpellCooldown(spellID)
    if not spellID or spellID == 0 then return end
    if not trackedDefensiveSpells[spellID] then return end
    
    local now = GetTime()
    local duration = 0
    local inCombat = InCombatLockdown()
    
    if not inCombat and C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd and cd.duration and cd.duration > 0 then
            if not (issecretvalue and issecretvalue(cd.duration)) then
                duration = cd.duration
                cachedDurations[spellID] = duration
            end
        end
    end
    
    if duration == 0 then
        duration = GetBestCooldownDuration(spellID)
    end
    
    if duration > 0 then
        localCooldowns[spellID] = {
            endTime = now + duration,
            duration = duration,
            startTime = now,
        }
    end
end

local function ClearLocalCooldowns()
    wipe(localCooldowns)
end

local function ClearCachedDurations()
    wipe(cachedDurations)
    wipe(localCooldowns)
end

local function InitCooldownTracking()
    if cooldownEventFrame then return end
    
    cooldownEventFrame = CreateFrame("Frame")
    cooldownEventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    cooldownEventFrame:RegisterEvent("PLAYER_DEAD")
    cooldownEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    cooldownEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    cooldownEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    cooldownEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    
    cooldownEventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, castGUID, spellID = ...
            if unit == "player" and spellID then
                RecordSpellCooldown(spellID)
            end
        elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
            ClearLocalCooldowns()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
            ClearCachedDurations()
        end
    end)
end

function BlizzardAPI.RegisterDefensiveSpell(spellID)
    if not spellID or spellID == 0 then return end
    trackedDefensiveSpells[spellID] = true
    if not cooldownEventFrame then
        InitCooldownTracking()
    end
end

function BlizzardAPI.ClearTrackedDefensives()
    wipe(trackedDefensiveSpells)
    wipe(localCooldowns)
end

function BlizzardAPI.IsSpellOnLocalCooldown(spellID)
    return IsLocalCooldownActive(spellID)
end

--------------------------------------------------------------------------------
-- Feature Availability (12.0+ secret value graceful degradation)
--------------------------------------------------------------------------------

local featureAvailability = {
    healthAccess = true,
    auraAccess = true,
    cooldownAccess = true,
    procAccess = true,
    lastCheck = 0,
}
local FEATURE_CHECK_INTERVAL = 5.0

-- UnitHealth("player") confirmed NOT secret as of 12.0 Alpha 6
local function TestHealthAccess()
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    
    -- Check for secrets
    if issecretvalue then
        if issecretvalue(health) or issecretvalue(maxHealth) then
            return false
        end
    end
    if canaccessvalue then
        if not canaccessvalue(health) or not canaccessvalue(maxHealth) then
            return false
        end
    end
    
    return true
end

-- Aura CONTENTS may be secret in 12.0, but VECTORS are not
local function TestAuraAccess()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local accessibleCount = 0
        local secretCount = 0

        for i = 1, 5 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end  -- No more auras
            
            local hasSecret = false
            if issecretvalue then
                if issecretvalue(auraData.spellId) or issecretvalue(auraData.name) then
                    hasSecret = true
                    secretCount = secretCount + 1
                end
            end
            if not hasSecret and canaccessvalue then
                if not canaccessvalue(auraData.spellId) or not canaccessvalue(auraData.name) then
                    hasSecret = true
                    secretCount = secretCount + 1
                end
            end
            
            if not hasSecret then
                accessibleCount = accessibleCount + 1
            end
        end

        return accessibleCount > 0 or (accessibleCount == 0 and secretCount == 0)
    end

    if UnitAura then
        local accessibleCount = 0
        local secretCount = 0
        
        for i = 1, 5 do
            local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
            if not name then break end
            
            local hasSecret = false
            if issecretvalue then
                if issecretvalue(name) or issecretvalue(spellId) then
                    hasSecret = true
                    secretCount = secretCount + 1
                end
            end
            if not hasSecret and canaccessvalue then
                if not canaccessvalue(name) or not canaccessvalue(spellId) then
                    hasSecret = true
                    secretCount = secretCount + 1
                end
            end
            
            if not hasSecret then
                accessibleCount = accessibleCount + 1
            end
        end
        
        return accessibleCount > 0 or (accessibleCount == 0 and secretCount == 0)
    end

    return false
end

-- Cooldowns flagged spell-by-spell as non-secret in 12.0
local function TestCooldownAccess()
    if not C_Spell_GetSpellCooldown then return true end

    local ok, result = pcall(function()
        if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
            local spells = C_AssistedCombat.GetRotationSpells()
            if spells and spells[1] and spells[1].spellId then
                local cooldownInfo = C_Spell_GetSpellCooldown(spells[1].spellId)
                if cooldownInfo then
                    if issecretvalue then
                        if issecretvalue(cooldownInfo.startTime) or issecretvalue(cooldownInfo.duration) then
                            return false
                        end
                    end
                end
            end
        end
        return true
    end)
    
    if not ok then return true end
    return result
end

-- IsSpellOverlayed may return secret boolean in 12.0
local function TestProcAccess()
    if not C_SpellActivationOverlay_IsSpellOverlayed then return true end
    
    local ok, result = pcall(function()
        if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
            local spells = C_AssistedCombat.GetRotationSpells()
            if spells and spells[1] and spells[1].spellId then
                local hasProc = C_SpellActivationOverlay_IsSpellOverlayed(spells[1].spellId)
                if hasProc ~= nil and issecretvalue then
                    if issecretvalue(hasProc) then
                        return false
                    end
                end
            end
        end
        return true
    end)
    
    if not ok then return true end
    return result
end

local function RefreshFeatureAvailability()
    local now = GetTime()
    if now - featureAvailability.lastCheck < FEATURE_CHECK_INTERVAL then
        return
    end

    local oldHealthAccess = featureAvailability.healthAccess
    local oldAuraAccess = featureAvailability.auraAccess
    local oldCooldownAccess = featureAvailability.cooldownAccess
    local oldProcAccess = featureAvailability.procAccess

    featureAvailability.healthAccess = TestHealthAccess()
    featureAvailability.auraAccess = TestAuraAccess()
    featureAvailability.cooldownAccess = TestCooldownAccess()
    featureAvailability.procAccess = TestProcAccess()
    featureAvailability.lastCheck = now

    local debugMode = BlizzardAPI.GetDebugMode()
    if debugMode then
        local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        if addon and addon.Print then
            if oldHealthAccess ~= featureAvailability.healthAccess then
                addon:Print("Health API access: " .. (featureAvailability.healthAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldAuraAccess ~= featureAvailability.auraAccess then
                addon:Print("Aura API access: " .. (featureAvailability.auraAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldCooldownAccess ~= featureAvailability.cooldownAccess then
                addon:Print("Cooldown API access: " .. (featureAvailability.cooldownAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldProcAccess ~= featureAvailability.procAccess then
                addon:Print("Proc API access: " .. (featureAvailability.procAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
        end
    end
end

function BlizzardAPI.IsDefensivesFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.healthAccess
end

function BlizzardAPI.IsRedundancyFilterAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.auraAccess
end

function BlizzardAPI.IsCooldownFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.cooldownAccess
end

function BlizzardAPI.IsProcFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.procAccess
end

function BlizzardAPI.GetBypassFlags()
    RefreshFeatureAvailability()
    local bypassRedundancy = not BlizzardAPI.IsRedundancyFilterAvailable()
    local bypassProcs = not BlizzardAPI.IsProcFeatureAvailable()
    local bypassCooldown = not BlizzardAPI.IsCooldownFeatureAvailable()
    local bypassDefensives = not BlizzardAPI.IsDefensivesFeatureAvailable()
    local bypassSlot1Blacklist = bypassRedundancy or bypassProcs

    return {
        bypassRedundancy = bypassRedundancy,
        bypassProcs = bypassProcs,
        bypassCooldown = bypassCooldown,
        bypassDefensives = bypassDefensives,
        bypassSlot1Blacklist = bypassSlot1Blacklist,
    }
end

function BlizzardAPI.RefreshFeatureAvailability()
    featureAvailability.lastCheck = 0
    RefreshFeatureAvailability()
end

function BlizzardAPI.GetFeatureAvailability()
    RefreshFeatureAvailability()
    return {
        healthAccess = featureAvailability.healthAccess,
        auraAccess = featureAvailability.auraAccess,
        cooldownAccess = featureAvailability.cooldownAccess,
        procAccess = featureAvailability.procAccess,
    }
end

--------------------------------------------------------------------------------
-- Secret Value Utilities (12.0+)
--------------------------------------------------------------------------------

function BlizzardAPI.IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

function BlizzardAPI.CanAccessValue(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

function BlizzardAPI.CanAccessSecrets()
    if canaccesssecrets then
        return canaccesssecrets()
    end
    return true
end

function BlizzardAPI.SafeCompare(a, b)
    if BlizzardAPI.IsSecretValue(a) or BlizzardAPI.IsSecretValue(b) then
        return nil
    end
    return a == b
end

--------------------------------------------------------------------------------
-- API-Specific Secret-Aware Helpers
--------------------------------------------------------------------------------

function BlizzardAPI.GetCooldownForDisplay(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return nil, nil end
    local cd = C_Spell_GetSpellCooldown(spellID)
    if not cd then return nil, nil end
    
    local start = BlizzardAPI.IsSecretValue(cd.startTime) and nil or cd.startTime
    local dur = BlizzardAPI.IsSecretValue(cd.duration) and nil or cd.duration
    return start, dur
end

-- Fail-open if secret (assume ready)
function BlizzardAPI.IsSpellReady(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return true end
    local cd = C_Spell_GetSpellCooldown(spellID)
    if not cd then return true end
    -- Check BOTH values for secret before any comparison or arithmetic
    if BlizzardAPI.IsSecretValue(cd.startTime) or BlizzardAPI.IsSecretValue(cd.duration) then
        return true  -- Fail-open: assume ready
    end
    return cd.startTime == 0 or (cd.startTime + cd.duration) <= GetTime()
end

function BlizzardAPI.GetAuraSpellID(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil end
    if BlizzardAPI.IsSecretValue(aura.spellId) then return nil end
    return aura.spellId
end

function BlizzardAPI.GetAuraTiming(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil, nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil, nil end
    
    local dur = BlizzardAPI.IsSecretValue(aura.duration) and nil or aura.duration
    local exp = BlizzardAPI.IsSecretValue(aura.expirationTime) and nil or aura.expirationTime
    return dur, exp
end

function BlizzardAPI.GetSpellCharges(spellID)
    if not spellID or not C_Spell_GetSpellCharges then return nil, nil end
    local chargeInfo = C_Spell_GetSpellCharges(spellID)
    if not chargeInfo then return nil, nil end

    local current = BlizzardAPI.IsSecretValue(chargeInfo.currentCharges) and nil or chargeInfo.currentCharges
    local max = BlizzardAPI.IsSecretValue(chargeInfo.maxCharges) and nil or chargeInfo.maxCharges
    return current, max
end

--------------------------------------------------------------------------------
-- Secrecy API Wrappers (12.0+)
--------------------------------------------------------------------------------

function BlizzardAPI.GetSpellCooldownSecrecy(spellID)
    if GetSpellCooldownSecrecy then
        local ok, lvl = pcall(GetSpellCooldownSecrecy, spellID)
        if ok then return lvl end
    end

    -- Fallback heuristic: inspect the cooldown values and treat them as secret
    if C_Spell_GetSpellCooldown then
        local ok, start, duration = pcall(function()
            local s, d = C_Spell_GetSpellCooldown(spellID)
            return s, d
        end)
        if ok and (BlizzardAPI.IsSecretValue(start) or BlizzardAPI.IsSecretValue(duration)) then
            return "SECRET"
        end
    end
    return nil
end

-- Returns nil, nil when values are secret
function BlizzardAPI.GetSafeSpellCooldown(spellID)
    local ok, start, duration = pcall(function()
        if C_Spell_GetSpellCooldown then
            return C_Spell_GetSpellCooldown(spellID)
        elseif GetSpellCooldown then
            return GetSpellCooldown(spellID)
        end
        return nil, nil
    end)

    if not ok then return nil, nil end
    if start == nil and duration == nil then return nil, nil end

    if BlizzardAPI.IsSecretValue and (BlizzardAPI.IsSecretValue(start) or BlizzardAPI.IsSecretValue(duration)) then
        return nil, nil
    end

    if BlizzardAPI.CanAccessValue and ((start ~= nil and not BlizzardAPI.CanAccessValue(start)) or (duration ~= nil and not BlizzardAPI.CanAccessValue(duration))) then
        return nil, nil
    end

    return start, duration
end

function BlizzardAPI.GetSpellAuraSecrecy(spellID)
    if GetSpellAuraSecrecy then
        local ok, lvl = pcall(GetSpellAuraSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

function BlizzardAPI.GetSpellCastSecrecy(spellID)
    if GetSpellCastSecrecy then
        local ok, lvl = pcall(GetSpellCastSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

function BlizzardAPI.ShouldUnitHealthMaxBeSecret(unitToken)
    if ShouldUnitHealthMaxBeSecret then
        local ok, res = pcall(ShouldUnitHealthMaxBeSecret, unitToken)
        if ok then return res end
    end
    return nil
end

function BlizzardAPI.GetInterfaceVersion()
    return CURRENT_VERSION
end

function BlizzardAPI.IsMidnightOrLater()
    return IS_MIDNIGHT_OR_LATER
end

function BlizzardAPI.VersionCall(pre12Func, post12Func, ...)
    if IS_MIDNIGHT_OR_LATER then
        return post12Func and post12Func(...) or nil
    else
        return pre12Func and pre12Func(...) or nil
    end
end

local SpellDB = LibStub("JustAC-SpellDB", true)

local cachedAddon = nil
local function GetAddon()
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedAddon
end

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

function BlizzardAPI.GetSpellInfo(spellID)
    if not spellID or spellID == 0 then return nil end
    if C_Spell_GetSpellInfo then return C_Spell_GetSpellInfo(spellID) end
    local name, _, icon = GetSpellInfo(spellID)
    if name then return {name = name, iconID = icon} end
    return nil
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

    if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
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
    
    -- Check CVars
    local assistedMode = GetCVarBool("assistedMode")
    if not assistedMode then
        issues[#issues + 1] = "assistedMode CVar is disabled (try: /console assistedMode 1)"
    end
    
    local assistedHighlight = GetCVarBool("assistedCombatHighlight")
    if not assistedHighlight then
        issues[#issues + 1] = "assistedCombatHighlight CVar is disabled (try: /console assistedCombatHighlight 1)"
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
        for i = 1, math.min(#rotationSpells, 5) do
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
        print("|JAC| Quick Fix Commands:")
        print("|JAC|   /console assistedMode 1")
        print("|JAC|   /console assistedCombatHighlight 1")
        print("|JAC|   /reload")
    end

    -- Secrecy API quick test: surface results for the sample spell (primary or first rotation)
    local sample = nextCastSpell or (rotationSpells and rotationSpells[1])
    if sample then
        local cdLevel = BlizzardAPI.GetSpellCooldownSecrecy and BlizzardAPI.GetSpellCooldownSecrecy(sample)
        local auraLevel = BlizzardAPI.GetSpellAuraSecrecy and BlizzardAPI.GetSpellAuraSecrecy(sample)
        local castLevel = BlizzardAPI.GetSpellCastSecrecy and BlizzardAPI.GetSpellCastSecrecy(sample)
        local start, dur = BlizzardAPI.GetSafeSpellCooldown and BlizzardAPI.GetSafeSpellCooldown(sample)
        print("|JAC| Secrecy for sample spell (" .. tostring(sample) .. "):")
        print("|JAC|   cooldown secrecy: " .. tostring(cdLevel) .. ", aura secrecy: " .. tostring(auraLevel) .. ", cast secrecy: " .. tostring(castLevel))
        print("|JAC|   safe cooldown read: start=" .. tostring(start) .. ", duration=" .. tostring(dur))
    end
    
    print("|JAC| =====================================")
end

-- Raw values (may be secret); Cooldown widget handles them
function BlizzardAPI.GetSpellCooldown(spellID)
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            return cd.startTime, cd.duration
        end
        return 0, 0
    elseif C_SpellBook and C_SpellBook.GetSpellCooldown then
        return C_SpellBook.GetSpellCooldown(spellID)
    elseif GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
    return 0, 0
end

-- Sanitized values for comparison (0,0 if secret)
function BlizzardAPI.GetSpellCooldownValues(spellID)
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            local startTime = cd.startTime
            local duration = cd.duration
            if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
                return 0, 0
            end
            return startTime or 0, duration or 0
        end
        return 0, 0
    elseif C_SpellBook and C_SpellBook.GetSpellCooldown then
        return C_SpellBook.GetSpellCooldown(spellID)
    elseif GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
    return 0, 0
end

-- Blizzard's dummy GCD spell always returns current GCD state
local GCD_SPELL_ID = 61304

function BlizzardAPI.GetGCDInfo()
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
        if cd then
            local startTime = cd.startTime
            local duration = cd.duration
            if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
                return 0, 0
            end
            return startTime or 0, duration or 0
        end
    end
    return 0, 0
end

function BlizzardAPI.IsSpellOnGCD(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return false end

    local spellCD = C_Spell_GetSpellCooldown(spellID)
    if not spellCD then return false end

    local spellStart = spellCD.startTime
    local spellDuration = spellCD.duration
    if issecretvalue and (issecretvalue(spellStart) or issecretvalue(spellDuration)) then
        return false
    end

    if not spellDuration or spellDuration == 0 then
        return false
    end

    local gcdCD = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
    if not gcdCD then return false end

    local gcdStart = gcdCD.startTime
    local gcdDuration = gcdCD.duration
    if issecretvalue and (issecretvalue(gcdStart) or issecretvalue(gcdDuration)) then
        return false
    end

    if not gcdDuration or gcdDuration == 0 then
        return false
    end

    return spellStart == gcdStart and spellDuration == gcdDuration
end

-- 12.0 fallbacks: action bar usability, local cooldown tracking
function BlizzardAPI.IsSpellOnRealCooldown(spellID)
    if not spellID then return false end

    local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)

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
                if issecretvalue and issecretvalue(currentCharges) then
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
    if IsLocalCooldownActive(spellID) then
        return true
    end

    -- Action bar usability
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
        local slot = ActionBarScanner.GetSlotForSpell(spellID)
        if slot and C_ActionBar and C_ActionBar.IsUsableAction then
            local actionUsable, notEnoughMana = C_ActionBar.IsUsableAction(slot)
            -- Check for secrets before comparing - fail-open (assume usable = show)
            if issecretvalue and (issecretvalue(actionUsable) or issecretvalue(notEnoughMana)) then
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

-- 12.0: Falls back to action bar state when secret
function BlizzardAPI.IsSpellUsable(spellID)
    if not spellID or spellID == 0 then return false, false end

    if C_Spell_IsSpellUsable then
        local success, isUsable, notEnoughResources = pcall(C_Spell_IsSpellUsable, spellID)
        if success then
            if issecretvalue and (issecretvalue(isUsable) or issecretvalue(notEnoughResources)) then
                local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                if ActionBarScanner and ActionBarScanner.GetSlotForSpell and C_ActionBar and C_ActionBar.IsUsableAction then
                    local slot = ActionBarScanner.GetSlotForSpell(spellID)
                    if slot then
                        local actionUsable, actionNotEnoughMana = C_ActionBar.IsUsableAction(slot)
                        if not (issecretvalue(actionUsable) or issecretvalue(actionNotEnoughMana)) then
                            return actionUsable or false, actionNotEnoughMana or false
                        end
                    end
                end
                return true, false
            end
            return isUsable, notEnoughResources
        end
    end

    if IsUsableSpell then
        local success, isUsable, notEnoughMana = pcall(IsUsableSpell, spellID)
        if success then
            if issecretvalue and (issecretvalue(isUsable) or issecretvalue(notEnoughMana)) then
                return true, false
            end
            return isUsable, notEnoughMana
        end
    end

    return true, false
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

    if issecretvalue and issecretvalue(result) then
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
        if issecretvalue and issecretvalue(overrideResult) then
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

function BlizzardAPI.IsImportantSpell(spellID)
    return false
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

local GetInventoryItemID = GetInventoryItemID
local GetItemSpell = GetItemSpell
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
    
    -- Handle potential secrets in 12.0+ (fail-safe)
    if BlizzardAPI.IsSecretValue(health) or BlizzardAPI.IsSecretValue(maxHealth) then
        return nil
    end
    
    if not BlizzardAPI.CanAccessValue(health) or not BlizzardAPI.CanAccessValue(maxHealth) then
        return nil
    end
    
    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end

-- Pet health CAN be secret in 12.0 unlike player health
function BlizzardAPI.GetPetHealthPercent()
    if not UnitExists("pet") then return nil end

    local ok, isDead = pcall(UnitIsDead, "pet")
    if ok then
        if issecretvalue and issecretvalue(isDead) then
            -- Can't determine dead status
        elseif isDead then
            return 0
        end
    end

    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")

    if BlizzardAPI.IsSecretValue(health) or BlizzardAPI.IsSecretValue(maxHealth) then
        return nil
    end

    if not BlizzardAPI.CanAccessValue(health) or not BlizzardAPI.CanAccessValue(maxHealth) then
        return nil
    end

    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end

--------------------------------------------------------------------------------
-- C_Secrets Namespace Wrappers (12.0+)
--------------------------------------------------------------------------------

function BlizzardAPI.ShouldSpellCooldownBeSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local ok, result = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if ok then return result end
    end
    return nil
end

function BlizzardAPI.ShouldSpellAuraBeSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, result = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
        if ok then return result end
    end
    return nil
end

function BlizzardAPI.ShouldUnitSpellCastBeSecret(unit)
    if C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret then
        local ok, result = pcall(C_Secrets.ShouldUnitSpellCastBeSecret, unit)
        if ok then return result end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Defensive Spell State Helper (consolidates common validation pattern)
--------------------------------------------------------------------------------

-- Cache for RedundancyFilter lookup (lazy-loaded)
local cachedRedundancyFilter = nil
local function GetRedundancyFilter()
    if cachedRedundancyFilter == nil then
        cachedRedundancyFilter = LibStub("JustAC-RedundancyFilter", true) or false
    end
    return cachedRedundancyFilter or nil
end

-- Check defensive spell usability in one call (avoids repeated API lookups)
-- Returns: isUsable, isKnown, isRedundant, onCooldown, isProcced
-- isUsable = isKnown AND NOT isRedundant AND NOT onCooldown
function BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
    if not spellID or spellID == 0 then
        return false, false, false, false, false
    end
    
    -- Check if spell is known/available
    local isKnown = BlizzardAPI.IsSpellAvailable(spellID)
    if not isKnown then
        return false, false, false, false, false
    end
    
    -- Check if procced (instant/free cast available)
    local isProcced = BlizzardAPI.IsSpellProcced(spellID)
    
    -- Check redundancy (buff already active)
    local RedundancyFilter = GetRedundancyFilter()
    local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant(spellID, profile, true) or false
    if isRedundant then
        return false, true, true, false, isProcced
    end
    
    -- Check cooldown
    local onCooldown = BlizzardAPI.IsSpellOnRealCooldown(spellID)
    if onCooldown then
        return false, true, false, true, isProcced
    end
    
    -- Spell is usable
    return true, true, false, false, isProcced
end

--------------------------------------------------------------------------------
-- Low Health Detection via LowHealthFrame (works when UnitHealth() is secret)
--------------------------------------------------------------------------------

function BlizzardAPI.GetLowHealthState()
    local frame = LowHealthFrame
    if not frame then
        return false, false, 0
    end

    local isShown = frame:IsShown()
    if not isShown then
        return false, false, 0
    end

    -- Alpha indicates severity (~0.3-0.5 at 35%, ~0.8-1.0 at critical)
    local alpha = frame:GetAlpha() or 0
    local isCritical = alpha > 0.5

    return true, isCritical, alpha
end

-- Falls back to LowHealthFrame when UnitHealth() returns secrets
function BlizzardAPI.GetPlayerHealthPercentSafe()
    local exactPct = BlizzardAPI.GetPlayerHealthPercent()
    if exactPct then
        return exactPct, false
    end

    local isLow, isCritical, alpha = BlizzardAPI.GetLowHealthState()
    if isCritical then
        local pct = 20 - (alpha - 0.5) * 30
        return math.max(5, math.min(20, pct)), true
    elseif isLow then
        local pct = 35 - alpha * 30
        return math.max(20, math.min(35, pct)), true
    else
        return 100, true
    end
end