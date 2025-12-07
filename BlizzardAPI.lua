-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Blizzard API Module
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 14)
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

-- LibPlayerSpells for spell type detection (lazy loaded)
local LibPlayerSpells = nil
local LPS_HELPFUL = 0x00004000
local LPS_SURVIVAL = 0x00400000

local function GetLibPlayerSpells()
    if LibPlayerSpells == nil then
        LibPlayerSpells = LibStub("LibPlayerSpells-1.0", true) or false
        if LibPlayerSpells then
            LPS_HELPFUL = LibPlayerSpells.constants.HELPFUL or LPS_HELPFUL
            LPS_SURVIVAL = LibPlayerSpells.constants.SURVIVAL or LPS_SURVIVAL
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

-- Shared debug mode check (used by all JustAC modules)
function BlizzardAPI.GetDebugMode()
    local profile = BlizzardAPI.GetProfile()
    return profile and profile.debugMode or false
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
function BlizzardAPI.IsSpellProcced(spellID)
    if not spellID or spellID == 0 then return false end
    return C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(spellID) or false
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

-- Spell type cache (shared by IsOffensiveSpell and IsDefensiveSpell)
local spellTypeCache = {}

function BlizzardAPI.ClearSpellTypeCache()
    wipe(spellTypeCache)
end

-- Check if a spell is offensive (not a heal or defensive)
-- Uses LibPlayerSpells: offensive = NOT (HELPFUL or SURVIVAL)
-- Cached for hot loop performance
function BlizzardAPI.IsOffensiveSpell(spellID)
    if not spellID then return true end  -- Fail-open
    
    local cached = spellTypeCache[spellID]
    if cached ~= nil then return cached.offensive end
    
    local lps = GetLibPlayerSpells()
    if not lps then
        spellTypeCache[spellID] = {offensive = true, defensive = false}
        return true  -- Fail-open
    end
    
    local flags = lps:GetSpellInfo(spellID)
    if not flags then
        spellTypeCache[spellID] = {offensive = true, defensive = false}
        return true  -- Fail-open
    end
    
    local isHelpful = bit_band(flags, LPS_HELPFUL) ~= 0
    local isSurvival = bit_band(flags, LPS_SURVIVAL) ~= 0
    local isOffensive = not isHelpful and not isSurvival
    local isDefensive = isHelpful or isSurvival
    
    spellTypeCache[spellID] = {offensive = isOffensive, defensive = isDefensive}
    return isOffensive
end

-- Check if a spell is defensive (heal or survival ability)
-- Uses LibPlayerSpells: defensive = HELPFUL or SURVIVAL
-- Cached for hot loop performance
function BlizzardAPI.IsDefensiveSpell(spellID)
    if not spellID then return false end  -- Fail-closed
    
    local cached = spellTypeCache[spellID]
    if cached ~= nil then return cached.defensive end
    
    local lps = GetLibPlayerSpells()
    if not lps then
        spellTypeCache[spellID] = {offensive = true, defensive = false}
        return false  -- Fail-closed
    end
    
    local flags = lps:GetSpellInfo(spellID)
    if not flags then
        spellTypeCache[spellID] = {offensive = true, defensive = false}
        return false  -- Fail-closed
    end
    
    local isHelpful = bit_band(flags, LPS_HELPFUL) ~= 0
    local isSurvival = bit_band(flags, LPS_SURVIVAL) ~= 0
    local isOffensive = not isHelpful and not isSurvival
    local isDefensive = isHelpful or isSurvival
    
    spellTypeCache[spellID] = {offensive = isOffensive, defensive = isDefensive}
    return isDefensive
end

--------------------------------------------------------------------------------
-- 12.0 (Midnight) Compatibility Utilities
-- These functions prepare for WoW 12.0 "Secret Values" system
--------------------------------------------------------------------------------

-- Check if a value is a "secret" (opaque) value in 12.0+
-- Returns false on pre-12.0 clients where issecretvalue doesn't exist
function BlizzardAPI.IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

-- Check if we can access/compare a value (not secret, or we have untainted access)
-- Returns true on pre-12.0 clients
function BlizzardAPI.CanAccessValue(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

-- Check if current execution context can access secrets
-- Returns true on pre-12.0 clients
function BlizzardAPI.CanAccessSecrets()
    if canaccesssecrets then
        return canaccesssecrets()
    end
    return true
end

-- Safely compare two values, handling secrets
-- Returns nil if comparison not possible due to secrets
function BlizzardAPI.SafeCompare(a, b)
    if BlizzardAPI.IsSecretValue(a) or BlizzardAPI.IsSecretValue(b) then
        return nil  -- Can't compare secrets
    end
    return a == b
end

-- Get the WoW interface version to detect 12.0+
function BlizzardAPI.GetInterfaceVersion()
    local version = select(4, GetBuildInfo())
    return version or 0
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

-- Check if we're running on 12.0+ (Midnight)
function BlizzardAPI.IsMidnightOrLater()
    return BlizzardAPI.GetInterfaceVersion() >= 120000
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