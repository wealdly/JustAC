-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Blizzard API Module v26
-- Changed: Added API-specific secret helpers (GetCooldownForDisplay, IsSpellReady, GetAuraTiming, GetSpellCharges)
-- Changed: Purpose-specific helpers check only needed fields for incremental 12.0 API access
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 26)
if not BlizzardAPI then return end

--------------------------------------------------------------------------------
-- Version Detection Constants
-- Use these for conditional code paths when 12.0 introduces breaking changes
--------------------------------------------------------------------------------
local WOW_VERSION_11_0_0 = 110000  -- The War Within (current retail)
local WOW_VERSION_12_0_0 = 120000  -- Midnight (upcoming)
local CURRENT_VERSION = select(4, GetBuildInfo()) or 0
local IS_MIDNIGHT_OR_LATER = CURRENT_VERSION >= WOW_VERSION_12_0_0

-- Hot path optimizations: cache frequently used functions
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
-- Local cooldown tracking (workaround for 12.0+ secret values)
-- Limitation: Uses GetSpellBaseCooldown (no talent/haste mods) when API secret
local localCooldowns = {}  -- [spellID] = { endTime, duration }
local cachedDurations = {} -- [spellID] = actual duration (from cast)
local trackedDefensiveSpells = {}  -- [spellID] = true
local cooldownEventFrame = nil

-- Check if spell is on cooldown (local tracking)
local function IsLocalCooldownActive(spellID)
    local data = localCooldowns[spellID]
    if not data then return false end
    return GetTime() < data.endTime
end

-- Get cooldown duration (prioritize cached actual, fallback to base)
local function GetBestCooldownDuration(spellID)
    -- Check if we have a cached actual duration from previous out-of-combat cast
    if cachedDurations[spellID] and cachedDurations[spellID] > 0 then
        return cachedDurations[spellID]
    end
    
    -- Fall back to base cooldown (unmodified by talents/haste)
    local baseCooldownMs = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if baseCooldownMs and baseCooldownMs > 0 then
        return baseCooldownMs / 1000
    end
    
    return 0
end

-- Record spell cast for cooldown tracking
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

-- Clear local cooldown tracking
local function ClearLocalCooldowns()
    wipe(localCooldowns)
end

-- Clear cached durations (on spec/talent change)
local function ClearCachedDurations()
    wipe(cachedDurations)
    wipe(localCooldowns)
end

-- Initialize event frame for tracking spell casts
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
            -- Talents changed - clear cached durations as they may be different now
            ClearCachedDurations()
        end
    end)
end

-- Register a spell for local cooldown tracking
-- Called when defensive spell lists are configured
function BlizzardAPI.RegisterDefensiveSpell(spellID)
    if not spellID or spellID == 0 then return end
    trackedDefensiveSpells[spellID] = true
    
    -- Ensure event frame is initialized
    if not cooldownEventFrame then
        InitCooldownTracking()
    end
end

-- Unregister all defensive spells (for profile changes)
function BlizzardAPI.ClearTrackedDefensives()
    wipe(trackedDefensiveSpells)
    wipe(localCooldowns)
end

-- Check local cooldown tracker (exported for use in IsSpellOnRealCooldown)
function BlizzardAPI.IsSpellOnLocalCooldown(spellID)
    return IsLocalCooldownActive(spellID)
end

--------------------------------------------------------------------------------
-- Feature Availability System (12.0+ Secret Value Handling)
-- When APIs return "secret" values, features that depend on them are disabled
--------------------------------------------------------------------------------

local featureAvailability = {
    healthAccess = true,       -- Can we read player/pet health? (needed for defensives)
    auraAccess = true,         -- Can we read player auras? (needed for redundancy filter)
    cooldownAccess = true,     -- Can we read spell cooldowns? (needed for cooldown display)
    procAccess = true,         -- Can we detect spell procs? (needed for proc glow)
    lastCheck = 0,
}
local FEATURE_CHECK_INTERVAL = 5.0  -- Re-check every 5 seconds

-- Test if we can access health values (player health for defensive suggestions)
-- NOTE: As of 12.0 Alpha 6, UnitHealth("player") is confirmed NOT secret
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

-- Test if we can access aura data (needed for redundancy filtering)
-- NOTE: In 12.0, aura CONTENTS may be secret, but aura VECTORS are not
local function TestAuraAccess()
    -- Try modern API first
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        -- Check multiple aura slots - if ANY are accessible, API is available
        -- (Some auras may be secret even out of combat, but most should be accessible)
        local accessibleCount = 0
        local secretCount = 0
        
        for i = 1, 5 do  -- Check first 5 auras (enough to detect API availability)
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
        
        -- If we found at least one accessible aura, API is available
        -- If we checked 0 auras (none present), assume API is available
        return accessibleCount > 0 or (accessibleCount == 0 and secretCount == 0)
    end
    
    -- Fallback API
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
    
    -- No aura API available
    return false
end

-- Test if we can access cooldown data (needed for cooldown display)
-- NOTE: In 12.0, cooldowns are being flagged spell-by-spell as non-secret
local function TestCooldownAccess()
    if not C_Spell_GetSpellCooldown then return true end
    
    -- Try to get cooldown for a common spell (global cooldown check)
    -- We don't need a specific spell - if ANY cooldown check works, we're good
    local ok, result = pcall(function()
        -- Use the Assisted Combat API as a test - if that works, cooldowns are accessible
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
    
    if not ok then return true end  -- API error, assume accessible
    return result
end

-- Test if we can detect spell procs (needed for proc glow)
-- NOTE: In 12.0, IsSpellOverlayed may return secret boolean
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
    
    if not ok then return true end  -- API error, assume accessible
    return result
end

-- Refresh feature availability checks
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
    
    -- Log changes to debug (only when status changes)
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

-- Public API: Check if defensive suggestions feature is available
function BlizzardAPI.IsDefensivesFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.healthAccess
end

-- Public API: Check if redundancy filtering is available
function BlizzardAPI.IsRedundancyFilterAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.auraAccess
end

-- Public API: Check if cooldown display feature is available
function BlizzardAPI.IsCooldownFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.cooldownAccess
end

-- Public API: Check if proc glow detection is available
function BlizzardAPI.IsProcFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.procAccess
end

-- Convenience helper: centralize feature bypass flags used elsewhere
-- Returns a table of booleans indicating which features should be bypassed
-- (true = bypass because the underlying feature is unavailable/secret)
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

-- Public API: Force re-check of feature availability (call on login/reload)
function BlizzardAPI.RefreshFeatureAvailability()
    featureAvailability.lastCheck = 0
    RefreshFeatureAvailability()
end

-- Public API: Get all feature availability status (for debug commands)
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
-- Secret Value Utilities (12.0+ Compatibility)
--------------------------------------------------------------------------------

-- Check if a value is a secret value (12.0+)
function BlizzardAPI.IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

-- Check if we can access a value (not secret, or we have access)
function BlizzardAPI.CanAccessValue(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true  -- Pre-12.0: all values accessible
end

-- Check if the current execution context can access secrets
function BlizzardAPI.CanAccessSecrets()
    if canaccesssecrets then
        return canaccesssecrets()
    end
    return true  -- Pre-12.0: always can access
end

-- Safely compare two values, handling secrets
-- Returns nil if comparison not possible due to secrets
function BlizzardAPI.SafeCompare(a, b)
    if BlizzardAPI.IsSecretValue(a) or BlizzardAPI.IsSecretValue(b) then
        return nil  -- Can't compare secrets in tainted code
    end
    return a == b
end

--------------------------------------------------------------------------------
-- API-Specific Secret-Aware Helpers
-- Each helper checks only the fields it needs for its specific use case
-- Allows field-level granularity as Blizzard releases API access incrementally
--------------------------------------------------------------------------------

-- Get cooldown info for display (UI rendering)
-- Returns: startTime, duration (either may be nil if secret)
function BlizzardAPI.GetCooldownForDisplay(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return nil, nil end
    local cd = C_Spell_GetSpellCooldown(spellID)
    if not cd then return nil, nil end
    
    local start = BlizzardAPI.IsSecretValue(cd.startTime) and nil or cd.startTime
    local dur = BlizzardAPI.IsSecretValue(cd.duration) and nil or cd.duration
    return start, dur
end

-- Check if spell is ready (usability check)
-- Returns: boolean, fail-open if secret (true = assume ready)
function BlizzardAPI.IsSpellReady(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return true end
    local cd = C_Spell_GetSpellCooldown(spellID)
    if not cd then return true end
    
    -- If startTime is secret, we can't know - fail-open (assume ready)
    if BlizzardAPI.IsSecretValue(cd.startTime) then return true end
    return cd.startTime == 0 or (cd.startTime + cd.duration) <= GetTime()
end

-- Get aura spell ID (for redundancy filtering)
-- Returns: spellID or nil
function BlizzardAPI.GetAuraSpellID(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil end
    
    -- Check if spellId is secret
    if BlizzardAPI.IsSecretValue(aura.spellId) then return nil end
    return aura.spellId
end

-- Get aura timing info (for pandemic window calculations)
-- Returns: duration, expirationTime (either may be nil if secret)
function BlizzardAPI.GetAuraTiming(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil, nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil, nil end
    
    local dur = BlizzardAPI.IsSecretValue(aura.duration) and nil or aura.duration
    local exp = BlizzardAPI.IsSecretValue(aura.expirationTime) and nil or aura.expirationTime
    return dur, exp
end

-- Get spell charge info (for charge-based abilities)
-- Returns: currentCharges, maxCharges (either may be nil if secret)
function BlizzardAPI.GetSpellCharges(spellID)
    if not spellID or not C_Spell_GetSpellCharges then return nil, nil end
    local chargeInfo = C_Spell_GetSpellCharges(spellID)
    if not chargeInfo then return nil, nil end
    
    local current = BlizzardAPI.IsSecretValue(chargeInfo.currentCharges) and nil or chargeInfo.currentCharges
    local max = BlizzardAPI.IsSecretValue(chargeInfo.maxCharges) and nil or chargeInfo.maxCharges
    return current, max
end

--------------------------------------------------------------------------------
-- Secrecy helpers (12.0+ wrappers)
-- These provide centralized, safe access to spell secrecy APIs and cooldowns
--------------------------------------------------------------------------------

-- Wrapper for GetSpellCooldownSecrecy (if available on client)
-- Returns a non-secret enum/string if the API exists, otherwise nil
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

-- Safe getter for spell cooldowns: returns start, duration when values are non-secret and accessible
-- Returns nil, nil when cooldown values are secret or inaccessible
function BlizzardAPI.GetSafeSpellCooldown(spellID)
    -- Prefer C_Spell API when available
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

    -- If either value is a secret, avoid returning numeric values
    if BlizzardAPI.IsSecretValue and (BlizzardAPI.IsSecretValue(start) or BlizzardAPI.IsSecretValue(duration)) then
        return nil, nil
    end

    -- Respect CanAccessValue when available
    if BlizzardAPI.CanAccessValue and ((start ~= nil and not BlizzardAPI.CanAccessValue(start)) or (duration ~= nil and not BlizzardAPI.CanAccessValue(duration))) then
        return nil, nil
    end

    return start, duration
end

-- Wrapper for GetSpellAuraSecrecy (if available)
function BlizzardAPI.GetSpellAuraSecrecy(spellID)
    if GetSpellAuraSecrecy then
        local ok, lvl = pcall(GetSpellAuraSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

-- Wrapper for GetSpellCastSecrecy (if available)
function BlizzardAPI.GetSpellCastSecrecy(spellID)
    if GetSpellCastSecrecy then
        local ok, lvl = pcall(GetSpellCastSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

-- Wrapper for ShouldUnitHealthMaxBeSecret (if available)
function BlizzardAPI.ShouldUnitHealthMaxBeSecret(unitToken)
    if ShouldUnitHealthMaxBeSecret then
        local ok, res = pcall(ShouldUnitHealthMaxBeSecret, unitToken)
        if ok then return res end
    end
    return nil
end

-- Get the WoW interface version to detect 12.0+
-- Returns: version number (e.g., 110207, 120000)
function BlizzardAPI.GetInterfaceVersion()
    return CURRENT_VERSION
end

-- Check if we're running on 12.0+ (Midnight)
-- Use this for conditional code paths when 12.0 has breaking API changes
function BlizzardAPI.IsMidnightOrLater()
    return IS_MIDNIGHT_OR_LATER
end

-- Version-aware API wrapper helper
-- Usage: local result = BlizzardAPI.VersionCall(pre12Func, post12Func, ...args)
function BlizzardAPI.VersionCall(pre12Func, post12Func, ...)
    if IS_MIDNIGHT_OR_LATER then
        return post12Func and post12Func(...) or nil
    else
        return pre12Func and pre12Func(...) or nil
    end
end

-- Native spell classification (replaces LibPlayerSpells)
local SpellDB = LibStub("JustAC-SpellDB", true)

-- Cached addon reference (resolved lazily)
local cachedAddon = nil
local function GetAddon()
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedAddon
end

-- Shared profile access (used by all JustAC modules)
function BlizzardAPI.GetProfile()
    local addon = GetAddon()
    if not addon or not addon.db then return nil end
    return addon.db.profile
end

-- Shared character-specific data access (used for blacklist, hotkey overrides)
function BlizzardAPI.GetCharData()
    local addon = GetAddon()
    if not addon or not addon.db then return nil end
    return addon.db.char
end

-- Cached debug mode (reduces table lookups in hot paths)
local cachedDebugMode = false
local lastDebugModeCheck = 0
local DEBUG_MODE_CACHE_DURATION = 1.0  -- Check actual value once per second

-- Shared debug mode check (used by all JustAC modules)
-- Cached to reduce overhead in hot loops (10-50 calls/sec in combat)
function BlizzardAPI.GetDebugMode()
    local now = GetTime()
    if now - lastDebugModeCheck > DEBUG_MODE_CACHE_DURATION then
        local profile = BlizzardAPI.GetProfile()
        cachedDebugMode = profile and profile.debugMode or false
        lastDebugModeCheck = now
    end
    return cachedDebugMode
end

-- Force refresh debug mode cache (call when user toggles debug)
function BlizzardAPI.RefreshDebugMode()
    lastDebugModeCheck = 0
end

-- Check if current spec is a healer role
function BlizzardAPI.IsCurrentSpecHealer()
    local spec = GetSpecialization()
    if not spec then return false end
    local _, _, _, _, role = GetSpecializationInfo(spec)
    return role == "HEALER"
end

-- Local aliases for internal use
local function GetDebugMode()
    return BlizzardAPI.GetDebugMode()
end

-- Wrapper with fallback to legacy GetSpellInfo
function BlizzardAPI.GetSpellInfo(spellID)
    if not spellID or spellID == 0 then return nil end
    if C_Spell_GetSpellInfo then return C_Spell_GetSpellInfo(spellID) end
    local name, _, icon = GetSpellInfo(spellID)
    if name then return {name = name, iconID = icon} end
    return nil
end

-- Returns spell ID from C_AssistedCombat recommendation
-- checkForVisibleButton controls whether hidden abilities are included:
--   true  = Only visible action bar abilities (Blizzard default, no flickering)
--   false = Include abilities behind macro conditionals (needs stabilization)
function BlizzardAPI.GetNextCastSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return nil end
    
    -- Check profile setting for whether to include hidden abilities
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
        -- Validate all entries are valid spell IDs
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

    -- Filter out assistedcombat string IDs (like Blizzard does)
    if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
        return nil, nil, nil, nil
    end

    return actionType, id, subType, spell_id_from_macro
end

-- Check if the system is properly configured
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

-- GetSpellCooldown returns raw values (may be secret in 12.0+)
-- The Cooldown widget can handle secret values directly via SetCooldown
-- Use GetSpellCooldownValues for logic comparisons (sanitized to 0,0 for secrets)
function BlizzardAPI.GetSpellCooldown(spellID)
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            -- Return raw values - may be secret, but Cooldown widget handles them
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

-- GetSpellCooldownValues returns sanitized values safe for comparison
-- Returns 0, 0 if values are secret (fail-open: assume off cooldown)
function BlizzardAPI.GetSpellCooldownValues(spellID)
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            local startTime = cd.startTime
            local duration = cd.duration
            -- 12.0: Handle secret values - treat as 0 for comparisons
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

-- GCD Detection using Blizzard's dummy GCD spell (ID 61304)
-- This spell always returns the current GCD state regardless of class/spec
local GCD_SPELL_ID = 61304

-- Get the current GCD info (start time and duration)
-- Returns: startTime, duration (0, 0 if not on GCD)
function BlizzardAPI.GetGCDInfo()
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
        if cd then
            local startTime = cd.startTime
            local duration = cd.duration
            -- 12.0: Handle secret values - treat as 0 (assume no GCD)
            if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
                return 0, 0
            end
            return startTime or 0, duration or 0
        end
    end
    return 0, 0
end

-- Check if a spell is currently only on GCD (not on its own cooldown)
-- Returns: true if spell is on GCD only, false if on actual cooldown or off cooldown
function BlizzardAPI.IsSpellOnGCD(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return false end
    
    local spellCD = C_Spell_GetSpellCooldown(spellID)
    if not spellCD then return false end
    
    -- 12.0: Handle secret values - treat as not on GCD (fail-open)
    local spellStart = spellCD.startTime
    local spellDuration = spellCD.duration
    if issecretvalue and (issecretvalue(spellStart) or issecretvalue(spellDuration)) then
        return false
    end
    
    if not spellDuration or spellDuration == 0 then
        return false  -- Spell is not on any cooldown
    end
    
    local gcdCD = C_Spell_GetSpellCooldown(GCD_SPELL_ID)
    if not gcdCD then return false end
    
    local gcdStart = gcdCD.startTime
    local gcdDuration = gcdCD.duration
    if issecretvalue and (issecretvalue(gcdStart) or issecretvalue(gcdDuration)) then
        return false
    end
    
    if not gcdDuration or gcdDuration == 0 then
        return false  -- No active GCD
    end
    
    -- If spell's cooldown matches GCD exactly, it's only on GCD
    return spellStart == gcdStart and spellDuration == gcdDuration
end

-- Check if a spell is on a real cooldown (longer than just GCD)
-- Returns: true if on actual cooldown, false if only on GCD or off cooldown
-- 12.0: When secrets block cooldown API, falls back to:
--   1. Action bar usability check (if spell is on action bar)
--   2. Local cooldown tracking (if spell was cast and we tracked it)
function BlizzardAPI.IsSpellOnRealCooldown(spellID)
    if not spellID then return false end
    
    -- Use sanitized values safe for comparisons
    local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)
    
    -- If we got real values (non-zero), use them
    if start and start > 0 and duration and duration > 0 then
        -- Check if it's just the GCD
        if BlizzardAPI.IsSpellOnGCD(spellID) then
            return false  -- Only on GCD, not a real cooldown
        end
        return true  -- On actual cooldown
    end
    
    -- We got 0,0 - either spell is off cooldown OR API returned secrets
    -- Try fallback methods in order of reliability
    
    -- Fallback 0: Check if this is a charge-based spell with no charges
    -- C_Spell.GetSpellCharges returns nil for non-charge spells, or chargeInfo table
    if C_Spell_GetSpellCharges then
        local success, chargeInfo = pcall(C_Spell_GetSpellCharges, spellID)
        if success and chargeInfo then
            -- It's a charge spell - check if currentCharges is available
            local currentCharges = chargeInfo.currentCharges
            if currentCharges and not (issecretvalue and issecretvalue(currentCharges)) then
                -- We have a real value
                if currentCharges == 0 then
                    return true  -- No charges = on cooldown
                else
                    return false  -- Has charges = usable
                end
            end
            -- currentCharges is secret or nil, fall through to other checks
        end
    end
    
    -- Fallback 1: Check local cooldown tracking (most reliable for tracked spells)
    if IsLocalCooldownActive(spellID) then
        return true
    end
    
    -- Fallback 2: Check if spell is usable via action bar
    -- If spell is on an action bar, the visual state reflects usability
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
        local slot = ActionBarScanner.GetSlotForSpell(spellID)
        if slot and C_ActionBar and C_ActionBar.IsUsableAction then
            local actionUsable, notEnoughMana = C_ActionBar.IsUsableAction(slot)
            -- If action bar says not usable and not because of mana, likely on cooldown
            if actionUsable == false and not notEnoughMana then
                return true
            end
            -- If action bar says usable, it's not on cooldown
            if actionUsable == true then
                return false
            end
        end
    end
    
    -- Fallback 3: Check C_Spell.IsSpellUsable (may also be secret, but worth trying)
    local isUsable, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID)
    
    -- If not usable AND it's not because of resources, it's likely on cooldown
    if not isUsable and not notEnoughResources then
        -- Make sure it's not on GCD only
        if not BlizzardAPI.IsSpellOnGCD(spellID) then
            return true
        end
    end
    
    -- All fallbacks exhausted - assume not on cooldown (fail-open)
    return false
end

-- Check if spell is usable (has resources, not on cooldown preventing cast, etc.)
-- Returns: isUsable, notEnoughResources
-- 12.0: These may return secrets in some contexts
-- When secret, falls back to checking action bar button state (desaturation indicates unusable)
function BlizzardAPI.IsSpellUsable(spellID)
    if not spellID or spellID == 0 then return false, false end
    
    -- Modern API (10.0+) - use cached reference
    if C_Spell_IsSpellUsable then
        local success, isUsable, notEnoughResources = pcall(C_Spell_IsSpellUsable, spellID)
        if success then
            -- 12.0: Check for secret values
            if issecretvalue and (issecretvalue(isUsable) or issecretvalue(notEnoughResources)) then
                -- Try action bar fallback: C_ActionBar.IsUsableAction reflects icon desaturation
                -- This is visible state, not protected combat data
                local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                if ActionBarScanner and ActionBarScanner.GetSlotForSpell and C_ActionBar and C_ActionBar.IsUsableAction then
                    local slot = ActionBarScanner.GetSlotForSpell(spellID)
                    if slot then
                        local actionUsable, actionNotEnoughMana = C_ActionBar.IsUsableAction(slot)
                        -- Only use if not secret (action bar state should be visible)
                        if not (issecretvalue(actionUsable) or issecretvalue(actionNotEnoughMana)) then
                            return actionUsable or false, actionNotEnoughMana or false
                        end
                    end
                end
                -- No action bar fallback available, fail-open
                return true, false
            end
            return isUsable, notEnoughResources
        end
    end
    
    -- Legacy fallback
    if IsUsableSpell then
        local success, isUsable, notEnoughMana = pcall(IsUsableSpell, spellID)
        if success then
            -- 12.0: Check for secret values
            if issecretvalue and (issecretvalue(isUsable) or issecretvalue(notEnoughMana)) then
                return true, false  -- Fail-open
            end
            return isUsable, notEnoughMana
        end
    end
    
    -- Default to usable if API unavailable
    return true, false
end

--------------------------------------------------------------------------------
-- Centralized Utility Functions (used by multiple modules)
--------------------------------------------------------------------------------

-- Check if a spell is procced (has Blizzard overlay glow)
-- Centralized to avoid duplicate implementations across modules
-- Returns false if the result is a secret value (12.0+ graceful degradation)
-- Checks BOTH the provided ID and its override ID (events may fire with different IDs)
function BlizzardAPI.IsSpellProcced(spellID)
    if not spellID or spellID == 0 then return false end
    
    -- Check the provided spell ID first
    local result = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(spellID)
    
    -- Handle secret values (12.0+)
    if issecretvalue and issecretvalue(result) then
        return false
    end
    
    if result then return true end
    
    -- Also check the override spell ID (events may fire with base ID, UI uses override)
    local overrideID = BlizzardAPI.GetDisplaySpellID(spellID)
    if overrideID and overrideID ~= spellID then
        local overrideResult = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(overrideID)
        if issecretvalue and issecretvalue(overrideResult) then
            return false
        end
        if overrideResult then return true end
    end
    
    -- Check reverse direction: maybe we were passed the override, check if base is procced
    -- This is harder because we don't have a "GetBaseSpellID" function easily
    -- The event-driven activeProcs cache in ActionBarScanner handles this by storing both
    
    return false
end

-- Get the display spell ID (resolves override spells like Metamorphosis transformations)
-- Returns the override if one exists, otherwise returns the original spellID
function BlizzardAPI.GetDisplaySpellID(spellID)
    if not spellID or spellID == 0 then return spellID end
    if not C_Spell_GetOverrideSpell then return spellID end
    
    local override = C_Spell_GetOverrideSpell(spellID)
    if override and override ~= 0 and override ~= spellID then
        return override
    end
    return spellID
end

-- Check if a spell is offensive (damage dealing or DPS buff, not utility/heal/CC)
-- Uses native SpellDB for 12.0 compatibility
function BlizzardAPI.IsOffensiveSpell(spellID)
    if not spellID then return true end  -- Fail-open
    if not SpellDB then return true end  -- Fail-open if SpellDB unavailable
    return SpellDB.IsOffensiveSpell(spellID)
end

-- Check if a spell is defensive (heal or survival ability)
-- Uses native SpellDB for 12.0 compatibility
function BlizzardAPI.IsDefensiveSpell(spellID)
    if not spellID then return false end  -- Fail-closed
    if not SpellDB then return false end
    return SpellDB.IsDefensiveSpell(spellID) or SpellDB.IsHealingSpell(spellID)
end

-- Check if a spell is crowd control
-- Uses native SpellDB for 12.0 compatibility
function BlizzardAPI.IsCrowdControlSpell(spellID)
    if not spellID then return false end
    if not SpellDB then return false end
    return SpellDB.IsCrowdControlSpell(spellID)
end

-- Check if a spell is utility (movement, rez, taunt, external, etc.)
-- Uses native SpellDB for 12.0 compatibility
function BlizzardAPI.IsUtilitySpell(spellID)
    if not spellID then return false end
    if not SpellDB then return false end
    return SpellDB.IsUtilitySpell(spellID)
end

-- Check if a spell is marked as IMPORTANT (high priority proc)
-- Currently returns false - can be extended with IMPORTANT_SPELLS table if needed
function BlizzardAPI.IsImportantSpell(spellID)
    -- TODO: Add IMPORTANT_SPELLS table to SpellDB if priority sorting needed
    return false
end

--------------------------------------------------------------------------------
-- Item Spell Detection
-- Checks if a spellID belongs to an equipped item (trinket, engineering tinker, etc.)
--------------------------------------------------------------------------------

-- Equipment slots that can have on-use/activatable effects:
-- Trinkets (most common), Belt/Cloak/Gloves (engineering tinkers)
local ITEM_USE_SLOTS = {
    6,   -- INVSLOT_WAIST (Belt) - engineering tinkers like Nitro Boosts
    10,  -- INVSLOT_HAND (Gloves) - engineering tinkers like Rocket Gloves
    13,  -- INVSLOT_TRINKET1
    14,  -- INVSLOT_TRINKET2
    15,  -- INVSLOT_BACK (Cloak) - engineering tinkers, some on-use cloaks
}

-- Cache for item spell lookups (itemID -> spellID)
local itemSpellCache = {}
local itemSpellCacheTime = 0
local ITEM_SPELL_CACHE_DURATION = 10.0  -- Refresh every 10 seconds (gear changes are rare)

-- Hot path: cache API references
local GetInventoryItemID = GetInventoryItemID
local GetItemSpell = GetItemSpell
local C_Item_GetItemSpell = C_Item and C_Item.GetItemSpell

-- Rebuild the item spell cache by checking equipped items
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

-- Check if a spellID belongs to an equipped item
-- Returns: true if the spell is from an equipped item, false otherwise
function BlizzardAPI.IsItemSpell(spellID)
    if not spellID or spellID == 0 then return false end
    
    -- Refresh cache if stale
    local now = GetTime()
    if now - itemSpellCacheTime > ITEM_SPELL_CACHE_DURATION then
        RebuildItemSpellCache()
    end
    
    return itemSpellCache[spellID] ~= nil
end

-- Force refresh item spell cache (call on PLAYER_EQUIPMENT_CHANGED)
function BlizzardAPI.RefreshItemSpellCache()
    itemSpellCacheTime = 0  -- Force refresh on next check
end

-- Get spell classification for debug purposes
function BlizzardAPI.GetSpellClassification(spellID)
    if not spellID then return "unknown" end
    if not SpellDB then return "unknown" end
    return SpellDB.GetSpellClassification(spellID)
end

-- Spell availability cache (checks if spell is known/castable)
local spellAvailabilityCache = {}
local spellAvailabilityCacheTime = 0
local AVAILABILITY_CACHE_DURATION = 2.0

function BlizzardAPI.ClearAvailabilityCache()
    wipe(spellAvailabilityCache)
    spellAvailabilityCacheTime = 0
end

-- Check if a spell is actually known/available to the player (cached)
function BlizzardAPI.IsSpellAvailable(spellID)
    if not spellID or spellID == 0 then return false end
    
    -- Check cache first (hot path)
    local now = GetTime()
    if now - spellAvailabilityCacheTime < AVAILABILITY_CACHE_DURATION then
        local cached = spellAvailabilityCache[spellID]
        if cached ~= nil then
            return cached
        end
    else
        -- Cache expired, clear it
        wipe(spellAvailabilityCache)
        spellAvailabilityCacheTime = now
    end
    
    -- Fast path: check if spell is in spellbook first (most common case for known spells)
    if C_SpellBook_IsSpellInSpellBook then
        if C_SpellBook_IsSpellInSpellBook(spellID, Enum_SpellBookSpellBank_Player) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end
    
    -- Check IsSpellKnown (fast API call)
    if IsSpellKnown then
        if IsSpellKnown(spellID) then
            spellAvailabilityCache[spellID] = true
            return true
        end
        -- Also check pet spells
        if IsSpellKnown(spellID, true) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end
    
    -- Now do slower checks - filter out passives
    if C_Spell_IsSpellPassive then
        local isPassive = C_Spell_IsSpellPassive(spellID)
        if isPassive then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end
    
    -- Also check spell subtext for "Passive" as backup
    if C_Spell and C_Spell.GetSpellSubtext then
        local subtext = C_Spell.GetSpellSubtext(spellID)
        if subtext and subtext:lower():find("passive") then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end
    
    -- Final check: Use IsPlayerSpell if available (most accurate for "do I have this?")
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        spellAvailabilityCache[spellID] = true
        return true
    end
    
    -- If we got here, the spell wasn't confirmed as known to the player
    -- Don't rely on GetSpellInfo - it returns data for ANY valid spell ID
    spellAvailabilityCache[spellID] = false
    return false
end

-- Get player health as percentage (0-100), returns nil if secrets block access
-- Safe for 12.0: UnitHealth/UnitHealthMax don't return secrets for player units
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

-- Get pet health as percentage (0-100), returns nil if no pet or secrets block access
-- 12.0: Pet health CAN be secret unlike player health
function BlizzardAPI.GetPetHealthPercent()
    if not UnitExists("pet") then return nil end
    
    -- Check if pet is dead first (also check for secret)
    local ok, isDead = pcall(UnitIsDead, "pet")
    if ok then
        if issecretvalue and issecretvalue(isDead) then
            -- Can't determine dead status - try to read health anyway
        elseif isDead then
            return 0
        end
    end
    
    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")
    
    -- Handle potential secrets in 12.0+
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
-- New APIs for testing secrecy conditions before making API calls
--------------------------------------------------------------------------------

-- Check if a spell's cooldown would be secret (uses new 12.0 C_Secrets namespace)
function BlizzardAPI.ShouldSpellCooldownBeSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local ok, result = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if ok then return result end
    end
    return nil  -- API not available
end

-- Check if a spell's aura would be secret
function BlizzardAPI.ShouldSpellAuraBeSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, result = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
        if ok then return result end
    end
    return nil
end

-- Check if a unit's spellcast info would be secret
function BlizzardAPI.ShouldUnitSpellCastBeSecret(unit)
    if C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret then
        local ok, result = pcall(C_Secrets.ShouldUnitSpellCastBeSecret, unit)
        if ok then return result end
    end
    return nil
end

--------------------------------------------------------------------------------
-- 12.0 Low Health Detection via LowHealthFrame
-- When UnitHealth() returns secrets, we can detect low health via the visual overlay
--------------------------------------------------------------------------------

-- Check if player is in low health state (uses LowHealthFrame visual indicator)
-- Returns: isLow, isCritical, alpha (severity 0-1, higher = more critical)
-- This works even when UnitHealth() returns secrets
function BlizzardAPI.GetLowHealthState()
    local frame = LowHealthFrame
    if not frame then
        return false, false, 0
    end
    
    local isShown = frame:IsShown()
    if not isShown then
        return false, false, 0
    end
    
    -- Alpha indicates severity: higher = more critical
    -- Typically ~0.3-0.5 at 35% health, ~0.8-1.0 at very low health
    local alpha = frame:GetAlpha() or 0
    local isCritical = alpha > 0.5  -- Roughly below 20% health
    
    return true, isCritical, alpha
end

-- Combined health detection: tries exact percentage first, falls back to LowHealthFrame
-- Returns: healthPercent (0-100), isEstimated (true if using LowHealthFrame)
-- When using LowHealthFrame: returns 30 for low, 15 for critical (estimates)
function BlizzardAPI.GetPlayerHealthPercentSafe()
    -- Try exact health first
    local exactPct = BlizzardAPI.GetPlayerHealthPercent()
    if exactPct then
        return exactPct, false
    end

    -- Health is secret - use LowHealthFrame
    local isLow, isCritical, alpha = BlizzardAPI.GetLowHealthState()
    if isCritical then
        -- Map alpha 0.5-1.0 to roughly 5-20%
        local pct = 20 - (alpha - 0.5) * 30
        return math.max(5, math.min(20, pct)), true
    elseif isLow then
        -- Map alpha 0.0-0.5 to roughly 20-35%
        local pct = 35 - alpha * 30
        return math.max(20, math.min(35, pct)), true
    else
        -- Not showing low health overlay = above 35%
        return 100, true  -- Assume full health if overlay not showing
    end
end