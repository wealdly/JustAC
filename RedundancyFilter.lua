-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Redundancy Filter Module
-- Filters out spells that are redundant (already active buffs, forms, pets, poisons, etc.)
-- Uses dynamic aura detection and LibPlayerSpells for enhanced spell metadata
-- NOTE: We trust Assisted Combat's suggestions - only filter truly redundant casts
--       like being in a form, having a pet, or already having weapon poisons applied.
-- COOLDOWN FILTERING: Hides abilities on cooldown >5s, shows when ≤5s remaining (prep time)
-- 12.0 COMPATIBILITY: When aura API blocked, uses whitelist (HARMFUL, BURST, COOLDOWN, IMPORTANT)
local RedundancyFilter = LibStub:NewLibrary("JustAC-RedundancyFilter", 20)
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
local LPS_RAIDBUFF = LibPlayerSpells and LibPlayerSpells.constants.RAIDBUFF or 0
local LPS_HARMFUL = LibPlayerSpells and LibPlayerSpells.constants.HARMFUL or 0
local LPS_BURST = LibPlayerSpells and LibPlayerSpells.constants.BURST or 0
local LPS_COOLDOWN = LibPlayerSpells and LibPlayerSpells.constants.COOLDOWN or 0
local LPS_IMPORTANT = LibPlayerSpells and LibPlayerSpells.constants.IMPORTANT or 0

-- Pandemic window: allow recast when aura has less than 30% duration remaining
-- This matches WoW's pandemic mechanic where refreshing extends duration
local PANDEMIC_THRESHOLD = 0.30

-- Cached aura data (invalidated on UNIT_AURA event)
local cachedAuras = {}
local lastAuraCheck = 0
local AURA_CACHE_DURATION = 0.2

-- Debug mode (BlizzardAPI caches this, only checked once per second)
local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

local function GetCachedSpellInfo(spellID)
    return BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID) or nil
end

-- Invalidate cached aura state (called on UNIT_AURA events from main addon)
function RedundancyFilter.InvalidateCache()
    wipe(cachedAuras)
    lastAuraCheck = 0
end

--------------------------------------------------------------------------------
-- Safe API Wrappers
--------------------------------------------------------------------------------

-- Generic safe call wrapper: returns fallback on error or if func doesn't exist
local function SafeCall(func, fallback, ...)
    if not func then return fallback end
    local ok, result = pcall(func, ...)
    return ok and result or fallback
end

-- Convenience wrappers using SafeCall
local function SafeUnitExists(unit) return SafeCall(UnitExists, false, unit) end
local function SafeHasPetUI() return SafeCall(HasPetUI, false) end
local function SafeHasPetSpells() return SafeCall(HasPetSpells, false) end
local function SafeIsMounted() return SafeCall(IsMounted, false) end
local function SafeIsStealthed() return SafeCall(IsStealthed, false) end

--------------------------------------------------------------------------------
-- Dynamic Aura Detection
--------------------------------------------------------------------------------

-- Build cache of current player auras (by spellID, name, and icon)
-- Now also stores duration and expiration time for pandemic window checks
local function RefreshAuraCache()
    local now = GetTime()
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
            
            -- Early exit: If aura data contains secrets, skip this aura (12.0+)
            -- Check spellId first as it's the most critical field
            if issecretvalue and (issecretvalue(auraData.spellId) or issecretvalue(auraData.name)) then
                -- Secret values detected - cache is unreliable, early exit
                -- Setting a flag so we know the cache is incomplete
                cachedAuras.hasSecrets = true
                break  -- Stop processing, cache will fail-open
            end
            
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
            
            -- Early exit: If aura data contains secrets, skip processing (12.0+)
            if issecretvalue and (issecretvalue(spellId) or issecretvalue(name)) then
                cachedAuras.hasSecrets = true
                break  -- Stop processing, cache will fail-open
            end
            
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
    
    local now = GetTime()
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

-- Check if spell is a raid buff (using LibPlayerSpells RAIDBUFF flag)
-- These are long-duration maintenance buffs like Battle Shout, Arcane Intellect
local function IsRaidBuff(spellID)
    return HasSpellFlag(spellID, LPS_RAIDBUFF)
end

-- Check if spell is DPS-relevant for rotation queue
-- When aura detection is blocked, only show spells that are clearly offensive/rotational
local function IsDPSRelevant(spellID)
    if not spellID then return false end
    
    -- Hardcoded raid buff IDs (these should always be filtered when aura API blocked)
    -- These are common buffs that may not be in LibPlayerSpells database
    local KNOWN_RAID_BUFFS = {
        [1126] = true,    -- Mark of the Wild (Druid)
        [21562] = true,   -- Power Word: Fortitude (Priest)
        [6673] = true,    -- Battle Shout (Warrior)
        [1459] = true,    -- Arcane Intellect (Mage)
    }
    
    if KNOWN_RAID_BUFFS[spellID] then
        return false  -- Always hide raid buffs when can't check if active
    end
    
    if not LibPlayerSpells then 
        return true  -- Fail-open: if no LPS data, assume it's relevant
    end
    
    local flags = LibPlayerSpells:GetSpellInfo(spellID)
    if not flags then 
        return true  -- Not in LPS database, assume relevant
    end
    
    -- Exclude utility spells from DPS queue when we can't verify their state
    if bit_band(flags, LPS_RAIDBUFF) ~= 0 then return false end  -- Raid buffs
    if bit_band(flags, LPS_PET) ~= 0 then return false end        -- Pet summons/control
    
    -- Include DPS-relevant spells
    if bit_band(flags, LPS_HARMFUL) ~= 0 then return true end     -- Offensive spells
    if bit_band(flags, LPS_BURST) ~= 0 then return true end       -- Burst damage
    if bit_band(flags, LPS_COOLDOWN) ~= 0 then return true end    -- Meaningful CDs
    if bit_band(flags, LPS_IMPORTANT) ~= 0 then return true end   -- Important procs
    
    -- For spells with AURA flag, only include if they're offensive (HARMFUL)
    -- This filters out forms, long buffs, but keeps damage buffs
    if bit_band(flags, LPS_AURA) ~= 0 then
        return bit_band(flags, LPS_HARMFUL) ~= 0
    end
    
    return true  -- Default: include in queue
end

--------------------------------------------------------------------------------
-- Pet Detection
--------------------------------------------------------------------------------

local function HasActivePet()
    -- UnitExists/HasPetUI/HasPetSpells are fast C calls, no cache needed
    return SafeUnitExists("pet") or SafeHasPetUI() or SafeHasPetSpells()
end

-- Check if pet is alive (exists AND not dead)
local function IsPetAlive()
    if not SafeUnitExists("pet") then return false end
    -- UnitIsDead returns true if unit is dead, false if alive
    local ok, isDead = pcall(UnitIsDead, "pet")
    if not ok then return true end  -- Fail-safe: assume alive
    return not isDead
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

-- Detect if spell is a pet revive/resurrection spell
local function IsPetReviveSpell(spellName)
    if not spellName then return false end
    return spellName:find("Revive Pet") or spellName:find("Heart of the Phoenix")
end

-- Detect if spell is a stealth ability
local function IsStealthSpell(spellName)
    if not spellName then return false end
    return spellName:find("Stealth") or spellName:find("Prowl") or spellName:find("Shadowmeld")
end

--------------------------------------------------------------------------------
-- Rogue Poison Detection
-- Rogues can have max 2 poisons active (1 lethal + 1 non-lethal)
-- If both slots are filled, all poison suggestions are redundant
--------------------------------------------------------------------------------

-- All Rogue poison spell IDs (the application spells)
-- These create player buffs with the same name
local ROGUE_POISON_SPELLS = {
    -- Lethal Poisons
    [2823] = true,   -- Deadly Poison
    [8679] = true,   -- Wound Poison
    [315584] = true, -- Instant Poison
    [381664] = true, -- Atrophic Poison
    -- Non-Lethal Poisons
    [3408] = true,   -- Crippling Poison
    [5761] = true,   -- Numbing Poison
}

-- Poison buff names to check for active auras
local ROGUE_POISON_NAMES = {
    "Deadly Poison",
    "Wound Poison",
    "Instant Poison",
    "Atrophic Poison",
    "Crippling Poison",
    "Numbing Poison",
}

-- Check if a spell is a Rogue poison application spell
local function IsRoguePoisonSpell(spellID)
    return spellID and ROGUE_POISON_SPELLS[spellID]
end

-- Count how many poison buffs are currently active on the player
local function CountActivePoisonBuffs()
    local count = 0
    for _, poisonName in ipairs(ROGUE_POISON_NAMES) do
        if HasBuffByName(poisonName) then
            count = count + 1
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- Weapon Enchant Detection (for Shaman Imbues)
--------------------------------------------------------------------------------

-- Minimum time remaining to consider weapon enchant "active" (in milliseconds)
-- 10 seconds = 10000 ms - if less than this, allow refresh
local WEAPON_ENCHANT_REFRESH_THRESHOLD = 10000

-- Shaman weapon imbue spell IDs
-- Maps the spell you cast to apply the weapon enchant
local WEAPON_ENCHANT_SPELLS = {
    [33757] = true,  -- Windfury Weapon
    [318038] = true, -- Flametongue Weapon (low-level version)
    [334294] = true, -- Flametongue Weapon (retail main spell)
}

-- Check if a spell is a weapon enchant application spell (Shaman imbue)
local function IsWeaponEnchantSpell(spellID)
    return spellID and WEAPON_ENCHANT_SPELLS[spellID]
end

-- Check if main-hand weapon has enchant with sufficient time remaining
-- Returns true if main-hand has active enchant, false otherwise
local function HasActiveWeaponEnchant()
    if not GetWeaponEnchantInfo then return false end
    
    local hasMainHand, mainHandExpiration = GetWeaponEnchantInfo()
    
    -- Main-hand enchant required
    -- If missing or expiring soon, allow refresh
    if not hasMainHand then return false end
    if mainHandExpiration and mainHandExpiration < WEAPON_ENCHANT_REFRESH_THRESHOLD then return false end
    
    return true
end

--------------------------------------------------------------------------------
-- Main Redundancy Check
--------------------------------------------------------------------------------

function RedundancyFilter.IsSpellRedundant(spellID, profile)
    if not spellID then return false end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return false end
    
    -- ALWAYS check cooldown - hide abilities on CD >5s, show when coming off CD (≤5s)
    -- This keeps queue focused on ready/soon-ready abilities regardless of secrets
    if BlizzardAPI and BlizzardAPI.GetSpellCooldown then
        local start, duration = BlizzardAPI.GetSpellCooldown(spellID)
        if start and duration and start > 0 and duration > 1.5 then  -- Ignore GCD
            local remaining = (start + duration) - GetTime()
            if remaining > 5.0 then  -- Hide if more than 5s remaining
                if GetDebugMode() then
                    print(string.format("|cff66ccffJAC|r |cffff6666FILTERED|r: On cooldown (%.1fs remaining)", remaining))
                end
                return true
            end
        end
    end
    
    -- Check if aura API is accessible (12.0+ secret values may block this)
    -- Test both API availability check AND cache refresh for secrets
    local auraAPIBlocked = BlizzardAPI and BlizzardAPI.IsRedundancyFilterAvailable and not BlizzardAPI.IsRedundancyFilterAvailable()
    local auras = RefreshAuraCache()
    
    -- If aura API blocked OR cache detected secrets, use whitelist: only show DPS-relevant spells
    if auraAPIBlocked or (auras and auras.hasSecrets) then
        if not IsDPSRelevant(spellID) then
            if GetDebugMode() then
                local reason = auraAPIBlocked and "aura API blocked" or "secrets detected in cache"
                print("|cff66ccffJAC|r |cffff6666FILTERED|r: Non-DPS spell (" .. reason .. ")")
            end
            return true  -- Hide non-DPS spells
        end
        return false  -- Show DPS-relevant spells
    end
    
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
    
    -- 3. PET SPELL REDUNDANCY
    -- Revive Pet: redundant if pet is ALIVE (can't revive alive pet)
    -- Summon Pet: redundant if pet EXISTS (alive or dead - already have a pet)
    if IsPetReviveSpell(spellName) then
        -- Revive is redundant only if pet is alive
        if IsPetAlive() then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Revive Pet but pet is alive")
            end
            return true
        end
    else
        -- Pet summon spells: redundant if any pet exists
        local isPetSpellByLPS = IsPetSpell(spellID)
        if (isPetSpellByLPS or IsPetSummonSpell(spellName)) and HasActivePet() then
            if debugMode then
                local source = isPetSpellByLPS and "LPS:PET" or "name pattern"
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Pet summon (" .. source .. ") but pet already exists")
            end
            return true
        end
    end
    
    -- 4. STEALTH REDUNDANCY
    -- Use IsStealthed() API - more reliable than buff checking
    if IsStealthSpell(spellName) then
        if SafeIsStealthed() then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Stealth spell but already stealthed")
            end
            return true
        end
    end
    
    -- 5. MOUNT REDUNDANCY
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
    
    -- 6. ROGUE POISON REDUNDANCY
    -- Rogues can have max 2 poisons active (1 lethal + 1 non-lethal)
    -- If both slots are filled, all poison suggestions are redundant
    if IsRoguePoisonSpell(spellID) then
        local activePoisons = CountActivePoisonBuffs()
        if activePoisons >= 2 then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Already have " .. activePoisons .. " poisons active (max 2)")
            end
            return true
        else
            if debugMode then
                print("|cff66ccffJAC|r |cff00ff00ALLOWED|r: Poison slot available (" .. activePoisons .. "/2 active)")
            end
        end
    end
    
    -- 7. WEAPON ENCHANT REDUNDANCY (Shaman Imbues)
    -- If this is a Shaman imbue spell and weapon already has active enchant, skip it
    -- Only check if enchants have sufficient time remaining (>10s)
    if IsWeaponEnchantSpell(spellID) then
        if HasActiveWeaponEnchant() then
            if debugMode then
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Weapon enchant already active with time remaining")
            end
            return true
        else
            if debugMode then
                print("|cff66ccffJAC|r |cff00ff00ALLOWED|r: Weapon enchant needed (missing or expiring)")
            end
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
        isHelpful = bit.band(flags, constants.HELPFUL) ~= 0,
        isHarmful = bit.band(flags, constants.HARMFUL) ~= 0,
        isCrowdControl = bit.band(flags, constants.CROWD_CTRL) ~= 0,
        isImportant = bit.band(flags, constants.IMPORTANT) ~= 0,
        providers = providers,
        modifiers = modifiers,
    }
end

-- Check if LibPlayerSpells is loaded and functional
function RedundancyFilter.IsLibPlayerSpellsAvailable()
    return LibPlayerSpells ~= nil
end