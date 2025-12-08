-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Blizzard API Module
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 16)
if not BlizzardAPI then return end

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
local C_Spell_IsSpellUsable = C_Spell and C_Spell.IsSpellUsable
local C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local Enum_SpellBookSpellBank_Player = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

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
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
        -- If we got data, check if any field is secret
        if auraData then
            if issecretvalue then
                if issecretvalue(auraData.spellId) or issecretvalue(auraData.name) then
                    return false
                end
            end
            if canaccessvalue then
                if not canaccessvalue(auraData.spellId) or not canaccessvalue(auraData.name) then
                    return false
                end
            end
        end
        -- No aura at index 1 is fine, API is accessible
        return true
    end
    
    -- Fallback API
    if UnitAura then
        local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", 1, "HELPFUL")
        if name then
            if issecretvalue then
                if issecretvalue(name) or issecretvalue(spellId) then
                    return false
                end
            end
            if canaccessvalue then
                if not canaccessvalue(name) or not canaccessvalue(spellId) then
                    return false
                end
            end
        end
        return true
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

-- Get the WoW interface version to detect 12.0+
-- 120000 = 12.0.0 (Midnight)
function BlizzardAPI.GetInterfaceVersion()
    local version = select(4, GetBuildInfo())
    return version or 0
end

-- Check if we're running on 12.0+ (Midnight)
function BlizzardAPI.IsMidnightOrLater()
    return BlizzardAPI.GetInterfaceVersion() >= 120000
end

-- LibPlayerSpells for spell type detection (lazy loaded)
local LibPlayerSpells = nil
local LPS_HELPFUL = 0x00004000
local LPS_PERSONAL = 0x00010000
local LPS_SURVIVAL = 0x00400000
local LPS_BURST = 0x00800000
local LPS_IMPORTANT = 0x02000000
local LPS_CROWD_CTRL = 0x40000000

local function GetLibPlayerSpells()
    if LibPlayerSpells == nil then
        LibPlayerSpells = LibStub("LibPlayerSpells-1.0", true) or false
        if LibPlayerSpells then
            LPS_HELPFUL = LibPlayerSpells.constants.HELPFUL or LPS_HELPFUL
            LPS_PERSONAL = LibPlayerSpells.constants.PERSONAL or LPS_PERSONAL
            LPS_SURVIVAL = LibPlayerSpells.constants.SURVIVAL or LPS_SURVIVAL
            LPS_BURST = LibPlayerSpells.constants.BURST or LPS_BURST
            LPS_IMPORTANT = LibPlayerSpells.constants.IMPORTANT or LPS_IMPORTANT
            LPS_CROWD_CTRL = LibPlayerSpells.constants.CROWD_CTRL or LPS_CROWD_CTRL
        end
    end
    return LibPlayerSpells
end

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
    
    print("|JAC| =====================================")
end

function BlizzardAPI.GetSpellCooldown(spellID)
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            return cd.startTime or 0, cd.duration or 0
        end
        return 0, 0
    elseif C_SpellBook and C_SpellBook.GetSpellCooldown then
        return C_SpellBook.GetSpellCooldown(spellID)
    elseif GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
    return 0, 0
end

-- Check if spell is usable (has resources, not on cooldown preventing cast, etc.)
-- Returns: isUsable, notEnoughResources
function BlizzardAPI.IsSpellUsable(spellID)
    if not spellID or spellID == 0 then return false, false end
    
    -- Modern API (10.0+) - use cached reference
    if C_Spell_IsSpellUsable then
        local success, isUsable, notEnoughResources = pcall(C_Spell_IsSpellUsable, spellID)
        if success then
            return isUsable, notEnoughResources
        end
    end
    
    -- Legacy fallback
    if IsUsableSpell then
        local success, isUsable, notEnoughMana = pcall(IsUsableSpell, spellID)
        if success then
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
function BlizzardAPI.IsSpellProcced(spellID)
    if not spellID or spellID == 0 then return false end
    
    local result = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(spellID)
    
    -- Early exit for secret values (12.0+): treat as not procced
    if issecretvalue and issecretvalue(result) then
        return false
    end
    
    return result or false
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
-- LibPlayerSpells data is pre-computed at load time, so no caching needed here
function BlizzardAPI.IsOffensiveSpell(spellID)
    if not spellID then return true end  -- Fail-open
    
    local lps = GetLibPlayerSpells()
    if not lps then return true end  -- Fail-open if LPS unavailable
    
    local flags = lps:GetSpellInfo(spellID)
    if not flags then return true end  -- Unknown spell = assume offensive
    
    local isHelpful = bit_band(flags, LPS_HELPFUL) ~= 0
    local isSurvival = bit_band(flags, LPS_SURVIVAL) ~= 0
    local isCrowdControl = bit_band(flags, LPS_CROWD_CTRL) ~= 0
    local isBurst = bit_band(flags, LPS_BURST) ~= 0
    
    -- DPS burst cooldowns are offensive, but healing bursts (BURST + SURVIVAL) are not
    local isDpsBurst = isBurst and not isSurvival
    
    return isDpsBurst or (not isHelpful and not isSurvival and not isCrowdControl)
end

-- Check if a spell is defensive (heal or survival ability)
-- LibPlayerSpells data is pre-computed at load time, so no caching needed here
function BlizzardAPI.IsDefensiveSpell(spellID)
    if not spellID then return false end  -- Fail-closed
    
    local lps = GetLibPlayerSpells()
    if not lps then return false end  -- Fail-closed if LPS unavailable
    
    local flags = lps:GetSpellInfo(spellID)
    if not flags then return false end  -- Unknown spell = assume not defensive
    
    local isHelpful = bit_band(flags, LPS_HELPFUL) ~= 0
    local isSurvival = bit_band(flags, LPS_SURVIVAL) ~= 0
    
    return isHelpful or isSurvival
end

-- Check if a spell is marked as IMPORTANT (high priority proc)
-- Uses LibPlayerSpells: spells players should react to immediately
-- Used to prioritize among multiple procced spells
function BlizzardAPI.IsImportantSpell(spellID)
    if not spellID then return false end
    
    local lps = GetLibPlayerSpells()
    if not lps then return false end
    
    local flags = lps:GetSpellInfo(spellID)
    if not flags then return false end
    
    return bit_band(flags, LPS_IMPORTANT) ~= 0
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
function BlizzardAPI.GetPetHealthPercent()
    if not UnitExists("pet") then return nil end
    
    -- Check if pet is dead first
    local isDead = UnitIsDead("pet")
    if isDead then return 0 end
    
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