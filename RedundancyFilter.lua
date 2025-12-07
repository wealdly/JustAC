-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Redundancy Filter Module
-- Filters out spells that are redundant (already active buffs, forms, pets, etc.)
-- Uses dynamic aura detection and LibPlayerSpells for enhanced spell metadata
-- NOTE: We trust Assisted Combat's suggestions - only filter truly redundant casts
--       like being in a form or having a pet. Aura refreshes are generally allowed.
local RedundancyFilter = LibStub:NewLibrary("JustAC-RedundancyFilter", 10)
if not RedundancyFilter then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)
local LibPlayerSpells = LibStub("LibPlayerSpells-1.0", true)

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local wipe = wipe
local bit_band = bit.band

-- LibPlayerSpells constants (cached for performance)
local LPS_AURA = LibPlayerSpells and LibPlayerSpells.constants.AURA or 0
local LPS_PET = LibPlayerSpells and LibPlayerSpells.constants.PET or 0
local LPS_PERSONAL = LibPlayerSpells and LibPlayerSpells.constants.PERSONAL or 0
local LPS_UNIQUE_AURA = LibPlayerSpells and LibPlayerSpells.constants.UNIQUE_AURA or 0

-- Pandemic window: allow recast when aura has less than 30% duration remaining
-- This matches WoW's pandemic mechanic where refreshing extends duration
local PANDEMIC_THRESHOLD = 0.30

-- Pet state is invalidated on UNIT_PET events from main addon
-- No time-based caching needed - UnitExists() is a fast C call
local cachedHasPet = nil

-- Cached aura data (invalidated on UNIT_AURA event)
local cachedAuras = {}
local lastAuraCheck = 0
local AURA_CACHE_DURATION = 0.2

-- Safe wrapper for GetTime (use cached version in hot path)
local function SafeGetTime()
    return GetTime()
end

local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

local function GetCachedSpellInfo(spellID)
    return BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID) or nil
end
-- Invalidate cached state (called on UNIT_PET/UNIT_AURA events from main addon)
function RedundancyFilter.InvalidateCache()
    cachedHasPet = nil
    wipe(cachedAuras)
    lastAuraCheck = 0
end

--------------------------------------------------------------------------------
-- Safe API Wrappers
--------------------------------------------------------------------------------

local function SafeUnitExists(unit)
    if not UnitExists then return false end
    local ok, result = pcall(UnitExists, unit)
    return ok and result
end

local function SafeHasPetUI()
    if not HasPetUI then return false end
    local ok, hasUI = pcall(HasPetUI)
    return ok and hasUI
end

local function SafeHasPetSpells()
    if not HasPetSpells then return false end
    local ok, result = pcall(HasPetSpells)
    return ok and result
end

local function SafeIsMounted()
    if not IsMounted then return false end
    local ok, result = pcall(IsMounted)
    return ok and result
end

local function SafeIsStealthed()
    if not IsStealthed then return false end
    local ok, result = pcall(IsStealthed)
    return ok and result
end

--------------------------------------------------------------------------------
-- Dynamic Aura Detection
--------------------------------------------------------------------------------

-- Build cache of current player auras (by spellID, name, and icon)
-- Now also stores duration and expiration time for pandemic window checks
local function RefreshAuraCache()
    local now = SafeGetTime()
    if cachedAuras.byID and (now - lastAuraCheck) < AURA_CACHE_DURATION then
        return cachedAuras
    end
    
    wipe(cachedAuras)
    cachedAuras.byID = {}
    cachedAuras.byName = {}
    cachedAuras.byIcon = {}
    cachedAuras.auraInfo = {}  -- Stores {duration, expirationTime, count} by spellID
    
    -- Modern API (11.0+)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            if auraData.spellId then
                cachedAuras.byID[auraData.spellId] = true
                -- Store aura timing info for pandemic check
                cachedAuras.auraInfo[auraData.spellId] = {
                    duration = auraData.duration or 0,
                    expirationTime = auraData.expirationTime or 0,
                    count = auraData.applications or 1,  -- Stack count
                }
            end
            if auraData.name then
                cachedAuras.byName[auraData.name] = auraData.spellId or true
            end
            if auraData.icon then
                cachedAuras.byIcon[auraData.icon] = auraData.name or true
            end
        end
    -- Fallback for older clients
    elseif UnitAura then
        for i = 1, 40 do
            local ok, name, icon, count, _, duration, expirationTime, _, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok or not name then break end
            if spellId then
                cachedAuras.byID[spellId] = true
                cachedAuras.auraInfo[spellId] = {
                    duration = duration or 0,
                    expirationTime = expirationTime or 0,
                    count = count or 1,
                }
            end
            if name then
                cachedAuras.byName[name] = spellId or true
            end
            if icon then
                cachedAuras.byIcon[icon] = name or true
            end
        end
    end
    
    lastAuraCheck = now
    return cachedAuras
end

-- Check if player has a buff by spell ID
local function HasBuffBySpellID(spellID)
    if not spellID then return false end
    local auras = RefreshAuraCache()
    return auras.byID and auras.byID[spellID]
end

-- Get aura info (duration, expiration, count) by spell ID
local function GetAuraInfo(spellID)
    if not spellID then return nil end
    local auras = RefreshAuraCache()
    return auras.auraInfo and auras.auraInfo[spellID]
end

-- Check if aura is within pandemic window (last 30% of duration)
-- Returns true if aura should be allowed to refresh
local function IsInPandemicWindow(spellID)
    local info = GetAuraInfo(spellID)
    if not info then return true end  -- No aura = definitely allow
    
    local duration = info.duration
    local expirationTime = info.expirationTime
    
    -- Auras with 0 duration are permanent/passive - don't consider them for refresh
    if duration <= 0 then return false end
    
    local now = SafeGetTime()
    local remaining = expirationTime - now
    
    -- Allow refresh if remaining time is less than pandemic threshold
    local pandemicTime = duration * PANDEMIC_THRESHOLD
    return remaining <= pandemicTime
end

-- Check if player has a buff by exact name
local function HasBuffByName(buffName)
    if not buffName then return false end
    local auras = RefreshAuraCache()
    return auras.byName and auras.byName[buffName]
end

-- Check if player has a buff with the same icon as the spell
-- Useful for spells where buff name differs from spell name but icon is same
local function HasBuffByIcon(iconID)
    if not iconID then return false end
    local auras = RefreshAuraCache()
    return auras.byIcon and auras.byIcon[iconID]
end

-- Check if casting this spell would apply a buff we already have
-- This is the key insight: if spell X applies buff X, and we have buff X, skip spell X
local function HasSameNameBuff(spellName)
    if not spellName then return false end
    return HasBuffByName(spellName)
end

--------------------------------------------------------------------------------
-- LibPlayerSpells Integration
--------------------------------------------------------------------------------

-- Check if spell has a specific flag using LibPlayerSpells
local function HasSpellFlag(spellID, flag)
    if not LibPlayerSpells or not spellID or flag == 0 then return false end
    local flags = LibPlayerSpells:GetSpellInfo(spellID)
    if not flags then return false end
    return bit_band(flags, flag) ~= 0
end

-- Check if spell applies an aura (using LibPlayerSpells AURA flag)
-- Returns: isAura, isPersonalAura, isUniqueAura
local function IsAuraSpell(spellID)
    if not LibPlayerSpells or not spellID then return false, false, false end
    local flags = LibPlayerSpells:GetSpellInfo(spellID)
    if not flags then return false, false, false end
    
    local isAura = bit_band(flags, LPS_AURA) ~= 0
    local isPersonal = bit_band(flags, LPS_PERSONAL) ~= 0
    local isUnique = bit_band(flags, LPS_UNIQUE_AURA) ~= 0
    
    return isAura, (isAura and isPersonal), isUnique
end

-- Check if spell is a pet-related ability (using LibPlayerSpells PET flag)
local function IsPetSpell(spellID)
    return HasSpellFlag(spellID, LPS_PET)
end

--------------------------------------------------------------------------------
-- Pet Detection
--------------------------------------------------------------------------------

local function HasActivePet()
    -- Fast path: return cached value (invalidated by UNIT_PET events)
    if cachedHasPet ~= nil then
        return cachedHasPet
    end
    
    -- Check methods in order of speed/reliability
    local hasPet = SafeUnitExists("pet") or SafeHasPetUI() or SafeHasPetSpells()
    
    cachedHasPet = hasPet
    return hasPet
end

--------------------------------------------------------------------------------
-- Form/Stance Detection
--------------------------------------------------------------------------------

local function IsFormChangeSpell(spellID)
    if not spellID then return false end
    if not FormCache then return false end
    
    -- Fast path: check direct spell-to-form mapping first
    local targetFormID = FormCache.GetFormIDBySpellID(spellID)
    if targetFormID then return true end
    
    -- Fallback: check by name patterns (Form, Stance, Presence, etc.)
    local spellInfo = GetCachedSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then return false end
    
    local name = spellInfo.name
    return name:match("Form$") or name:match("Stance$") or name:match("Presence$")
end

--------------------------------------------------------------------------------
-- Spell Category Detection (dynamic, no hardcoded spell lists)
--------------------------------------------------------------------------------

-- Detect if spell is a pet summon based on name patterns
local function IsPetSummonSpell(spellName)
    if not spellName then return false end
    
    -- Common pet summon patterns
    local patterns = {
        "^Call Pet",
        "^Summon",
        "Raise Dead",
        "Army of the Dead",
        "Dire Beast",
        "Feral Spirit",
    }
    
    for _, pattern in ipairs(patterns) do
        if spellName:find(pattern) then
            return true
        end
    end

    return false
end

-- Detect if spell is a stealth ability
local function IsStealthSpell(spellName)
    if not spellName then return false end
    return spellName:find("Stealth") or spellName:find("Prowl") or spellName:find("Shadowmeld")
end

--------------------------------------------------------------------------------
-- Main Redundancy Check
--------------------------------------------------------------------------------

function RedundancyFilter.IsSpellRedundant(spellID)
    if not spellID then return false end
    
    local spellInfo = GetCachedSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then return false end
    
    local spellName = spellInfo.name
    local debugMode = GetDebugMode()  -- Check debug mode after early exits
    local isKnownAuraSpell, isPersonalAura, isUniqueAura = IsAuraSpell(spellID)
    
    if debugMode then
        local lpsTag = ""
        if isUniqueAura then
            lpsTag = " [LPS:UNIQUE_AURA]"
        elseif isPersonalAura then
            lpsTag = " [LPS:PERSONAL+AURA]"
        elseif isKnownAuraSpell then
            lpsTag = " [LPS:AURA]"
        end
        print("|cff66ccffJAC|r Checking redundancy for: " .. spellName .. " (ID: " .. spellID .. ")" .. lpsTag)
    end
    
    -- 1. FORM/STANCE REDUNDANCY
    -- If this is a form spell and we're already in that form, skip it
    -- Forms are always unique - can't be in two forms at once
    if IsFormChangeSpell(spellID) and FormCache then
        local currentFormID = FormCache.GetActiveForm()
        local targetFormID = FormCache.GetFormIDBySpellID(spellID)
        
        if targetFormID and targetFormID == currentFormID then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Already in target form " .. targetFormID)
            end
            return true
        end
    end
    
    -- 2. AURA SPELL REDUNDANCY
    -- IMPORTANT: Only filter auras that are UNIQUE (can't stack) and not in pandemic window
    -- Many abilities can stack (Immolation Aura, etc.) - trust Assisted Combat's judgment
    if isKnownAuraSpell then
        -- Only UNIQUE_AURA spells should be filtered when active
        -- Non-unique auras may stack or have other reasons to recast
        if isUniqueAura then
            -- Check if buff is active
            local hasBuff = HasBuffBySpellID(spellID) or HasBuffByName(spellName)
            
            if hasBuff then
                -- Check pandemic window - allow refresh if aura is about to expire
                if IsInPandemicWindow(spellID) then
                    if debugMode then
                        print("|cff66ccffJAC|r |cff00ff00ALLOWED|r: Unique aura in pandemic window - refresh allowed")
                    end
                    return false  -- Allow the cast
                end
                
                if debugMode then
                    print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Unique aura already active (not in pandemic window)")
                end
                return true
            end
        else
            -- Non-unique aura spells: trust Assisted Combat
            -- These may stack, refresh for damage, or have other valid reasons
            if debugMode and (HasBuffBySpellID(spellID) or HasBuffByName(spellName)) then
                print("|cff66ccffJAC|r |cff00ff00ALLOWED|r: Non-unique aura - may stack or have refresh benefit")
            end
        end
    end
    
    -- 3. FALLBACK: For spells NOT in LibPlayerSpells
    -- Be conservative - only filter if we're confident it's truly redundant
    -- If Assisted Combat suggests it, there's probably a reason
    -- Skip this check - trust Assisted Combat for unlisted spells
    
    -- 4. PET SUMMON REDUNDANCY
    -- Use LibPlayerSpells PET flag if available, otherwise fall back to name patterns
    local isPetSpellByLPS = IsPetSpell(spellID)
    if (isPetSpellByLPS or IsPetSummonSpell(spellName)) and HasActivePet() then
        if debugMode then
            local source = isPetSpellByLPS and "LPS:PET" or "name pattern"
            print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Pet summon (" .. source .. ") but pet already exists")
        end
        return true
    end
    
    -- 5. STEALTH REDUNDANCY
    -- Use IsStealthed() API - more reliable than buff checking
    if IsStealthSpell(spellName) then
        if SafeIsStealthed() then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Stealth spell but already stealthed")
            end
            return true
        end
    end
    
    -- 6. MOUNT REDUNDANCY
    -- Use IsMounted() API
    if SafeIsMounted() then
        -- Check if this is a mount spell (avoid false positives)
        if spellInfo.name:find("Mount") or 
           (C_MountJournal and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountFromSpell(spellID)) then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Mount spell but already mounted")
            end
            return true
        end
    end
    
    if debugMode then
        print("|cff66ccffJAC|r |cff00ff00NOT REDUNDANT|r: " .. spellName)
    end
    return false
end

--------------------------------------------------------------------------------
-- Debug / Diagnostic Functions
--------------------------------------------------------------------------------

-- Get LibPlayerSpells info for a spell (for debugging)
function RedundancyFilter.GetLPSInfo(spellID)
    if not LibPlayerSpells or not spellID then
        return { available = false }
    end
    
    local flags, providers, modifiers = LibPlayerSpells:GetSpellInfo(spellID)
    if not flags then
        return { available = true, known = false }
    end
    
    local constants = LibPlayerSpells.constants
    return {
        available = true,
        known = true,
        flags = flags,
        isAura = bit.band(flags, constants.AURA) ~= 0,
        isUniqueAura = bit.band(flags, constants.UNIQUE_AURA) ~= 0,
        isSurvival = bit.band(flags, constants.SURVIVAL) ~= 0,
        isBurst = bit.band(flags, constants.BURST) ~= 0,
        isCooldown = bit.band(flags, constants.COOLDOWN) ~= 0,
        isPet = bit.band(flags, constants.PET) ~= 0,
        isPersonal = bit.band(flags, constants.PERSONAL) ~= 0,
        providers = providers,
        modifiers = modifiers,
    }
end

-- Check if LibPlayerSpells is loaded and functional
function RedundancyFilter.IsLibPlayerSpellsAvailable()
    return LibPlayerSpells ~= nil
end