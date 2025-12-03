-- JustAC: Redundancy Filter Module
-- Filters out spells that are redundant (already active buffs, forms, pets, etc.)
-- Uses dynamic aura detection and LibPlayerSpells for enhanced spell metadata
local RedundancyFilter = LibStub:NewLibrary("JustAC-RedundancyFilter", 9)
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
-- Reserved for future use: UNIQUE_AURA, SURVIVAL, BURST, COOLDOWN

-- Cached pet state (invalidated on UNIT_PET event)
local cachedHasPet = nil
local lastPetCheck = 0
local PET_CACHE_DURATION = 0.5

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
    lastPetCheck = 0
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
local function RefreshAuraCache()
    local now = SafeGetTime()
    if cachedAuras.byID and (now - lastAuraCheck) < AURA_CACHE_DURATION then
        return cachedAuras
    end
    
    wipe(cachedAuras)
    cachedAuras.byID = {}
    cachedAuras.byName = {}
    cachedAuras.byIcon = {}
    
    -- Modern API (11.0+)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            if auraData.spellId then
                cachedAuras.byID[auraData.spellId] = true
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
            local ok, name, icon, _, _, _, _, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok or not name then break end
            if spellId then
                cachedAuras.byID[spellId] = true
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
-- Returns: isAura, isPersonalAura
local function IsAuraSpell(spellID)
    if not LibPlayerSpells or not spellID then return false, false end
    local flags = LibPlayerSpells:GetSpellInfo(spellID)
    if not flags then return false, false end
    
    local isAura = bit_band(flags, LPS_AURA) ~= 0
    local isPersonal = bit_band(flags, LPS_PERSONAL) ~= 0
    
    return isAura, (isAura and isPersonal)
end

-- Check if spell is a pet-related ability (using LibPlayerSpells PET flag)
local function IsPetSpell(spellID)
    return HasSpellFlag(spellID, LPS_PET)
end

--------------------------------------------------------------------------------
-- Pet Detection
--------------------------------------------------------------------------------

local function HasActivePet()
    local now = GetTime()
    
    -- Fast path: return cached value if still valid
    if cachedHasPet ~= nil and (now - lastPetCheck) < PET_CACHE_DURATION then
        return cachedHasPet
    end
    
    -- Check methods in order of speed/reliability
    -- Method 1: Standard API (fastest, most common)
    local hasPet = SafeUnitExists("pet") or SafeHasPetUI() or SafeHasPetSpells()
    
    cachedHasPet = hasPet
    lastPetCheck = now
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
    local isKnownAuraSpell, isPersonalAura = IsAuraSpell(spellID)
    
    if debugMode then
        local lpsTag = ""
        if isPersonalAura then
            lpsTag = " [LPS:PERSONAL+AURA]"
        elseif isKnownAuraSpell then
            lpsTag = " [LPS:AURA]"
        end
        print("|JAC| Checking redundancy for: " .. spellName .. " (ID: " .. spellID .. ")" .. lpsTag)
    end
    
    -- 1. FORM/STANCE REDUNDANCY
    -- If this is a form spell and we're already in that form, skip it
    if IsFormChangeSpell(spellID) and FormCache then
        local currentFormID = FormCache.GetActiveForm()
        local targetFormID = FormCache.GetFormIDBySpellID(spellID)
        
        if targetFormID and targetFormID == currentFormID then
            if debugMode then
                print("|JAC| REDUNDANT: Already in target form " .. targetFormID)
            end
            return true
        end
    end
    
    -- 2. AURA SPELL REDUNDANCY (LibPlayerSpells primary check)
    -- If LPS knows this spell applies an aura, check if the buff is already active
    if isKnownAuraSpell then
        -- Check by spell ID first (most accurate)
        if HasBuffBySpellID(spellID) then
            if debugMode then
                print("|JAC| REDUNDANT: LPS aura spell - buff active by ID " .. spellID)
            end
            return true
        end
        
        -- Check by name (handles ID mismatches between cast and buff)
        if HasBuffByName(spellName) then
            if debugMode then
                print("|JAC| REDUNDANT: LPS aura spell - buff active by name '" .. spellName .. "'")
            end
            return true
        end
        
        -- Check by icon (only for PERSONAL auras where we KNOW it's a self-buff)
        -- Non-personal auras might share icons with unrelated effects
        if isPersonalAura and spellInfo.iconID and HasBuffByIcon(spellInfo.iconID) then
            if debugMode then
                print("|JAC| REDUNDANT: LPS personal aura - buff active by icon " .. spellInfo.iconID)
            end
            return true
        end
    else
        -- 3. FALLBACK: SAME-NAME BUFF CHECK (for spells not in LPS database)
        -- Only check by name to avoid false positives from icon matching
        if HasSameNameBuff(spellName) then
            if debugMode then
                print("|JAC| REDUNDANT: Fallback - already have buff '" .. spellName .. "'")
            end
            return true
        end
    end
    
    -- 4. PET SUMMON REDUNDANCY
    -- Use LibPlayerSpells PET flag if available, otherwise fall back to name patterns
    local isPetSpellByLPS = IsPetSpell(spellID)
    if (isPetSpellByLPS or IsPetSummonSpell(spellName)) and HasActivePet() then
        if debugMode then
            local source = isPetSpellByLPS and "LPS:PET" or "name pattern"
            print("|JAC| REDUNDANT: Pet summon (" .. source .. ") but pet already exists")
        end
        return true
    end
    
    -- 5. STEALTH REDUNDANCY
    -- Use IsStealthed() API - more reliable than buff checking
    if IsStealthSpell(spellName) then
        if SafeIsStealthed() then
            if debugMode then
                print("|JAC| REDUNDANT: Stealth spell but already stealthed")
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
                print("|JAC| REDUNDANT: Mount spell but already mounted")
            end
            return true
        end
    end
    
    if debugMode then
        print("|JAC| Spell " .. spellName .. " -> NOT REDUNDANT")
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