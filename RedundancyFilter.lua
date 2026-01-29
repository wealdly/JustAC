-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Redundancy Filter Module v33
-- Changed: Migrated to BlizzardAPI.IsSecretValue() and GetAuraTiming() for centralized secret handling
-- Changed: Field-level secret checks allow partial aura data when some fields are secret
-- 12.0 COMPATIBILITY: Uses API-specific helpers for incremental API access
local RedundancyFilter = LibStub:NewLibrary("JustAC-RedundancyFilter", 33)
if not RedundancyFilter then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- Hot path optimizations
local GetTime = GetTime
local pcall = pcall
local wipe = wipe


-- Spell classification tables (manual, covers essential spells)

-- Raid buffs
local RAID_BUFF_SPELLS = {
    [1126] = true,    -- Mark of the Wild (Druid)
    [21562] = true,   -- Power Word: Fortitude (Priest)
    [6673] = true,    -- Battle Shout (Warrior)
    [1459] = true,    -- Arcane Intellect (Mage)
    [264761] = true,  -- Blessing of the Bronze (Evoker)
    [381732] = true,  -- Blessing of the Bronze (alternate)
}

-- Pet summon spells
local PET_SUMMON_SPELLS = {
    -- Hunter
    [883] = true,     -- Call Pet 1
    [83242] = true,   -- Call Pet 2
    [83243] = true,   -- Call Pet 3
    [83244] = true,   -- Call Pet 4
    [83245] = true,   -- Call Pet 5
    -- Warlock
    [688] = true,     -- Summon Imp
    [697] = true,     -- Summon Voidwalker
    [712] = true,     -- Summon Succubus
    [691] = true,     -- Summon Felhunter
    [30146] = true,   -- Summon Felguard
    -- Death Knight
    [46584] = true,   -- Raise Dead (permanent ghoul)
    [46585] = true,   -- Raise Dead (temporary)
    [42650] = true,   -- Army of the Dead
    [49206] = true,   -- Summon Gargoyle
    -- Mage
    [31687] = true,   -- Summon Water Elemental
    -- Shaman
    [51533] = true,   -- Feral Spirit
    [198103] = true,  -- Earth Elemental
    [198067] = true,  -- Fire Elemental
    [192249] = true,  -- Storm Elemental
}

-- Unique Aura Spells: Buffs that can only have one instance active
-- These should be filtered when already active (outside pandemic window)
local UNIQUE_AURA_SPELLS = {
    -- Druid Forms
    [768] = true,     -- Cat Form
    [5487] = true,    -- Bear Form
    [783] = true,     -- Travel Form
    [24858] = true,   -- Moonkin Form
    [197625] = true,  -- Moonkin Form (affinity)
    [114282] = true,  -- Tree of Life
    -- Warrior Stances
    [386164] = true,  -- Battle Stance
    [386208] = true,  -- Defensive Stance
    -- Paladin Auras
    [465] = true,     -- Devotion Aura
    [183435] = true,  -- Retribution Aura
    [32223] = true,   -- Crusader Aura
    -- Rogue Stealth
    [1784] = true,    -- Stealth
    [115191] = true,  -- Stealth (Subterfuge)
    -- Hunter Aspects
    [5118] = true,    -- Aspect of the Cheetah
    [186257] = true,  -- Aspect of the Cheetah
    [186265] = true,  -- Aspect of the Turtle
    [186289] = true,  -- Aspect of the Eagle
    -- Raid Buffs (unique - can only have one active)
    [1126] = true,    -- Mark of the Wild (Druid)
    [21562] = true,   -- Power Word: Fortitude (Priest)
    [6673] = true,    -- Battle Shout (Warrior)
    [1459] = true,    -- Arcane Intellect (Mage)
    [264761] = true,  -- Blessing of the Bronze (Evoker)
    [381732] = true,  -- Blessing of the Bronze (alternate)
}

-- Personal Aura Spells: Self-only buffs (subset that we recognize)
-- Used for determining if a spell applies a personal buff
local PERSONAL_AURA_SPELLS = {
    -- These are spells that apply personal buffs
    -- Form spells are implicitly personal
    [768] = true, [5487] = true, [783] = true, [24858] = true,
    -- Stealth
    [1784] = true, [115191] = true,
    -- Aspects
    [5118] = true, [186257] = true, [186265] = true, [186289] = true,
}

-- Pandemic window: allow recast when aura has less than 30% duration remaining
-- This matches WoW's pandemic mechanic where refreshing extends duration
local PANDEMIC_THRESHOLD = 0.30

-- Cached aura data (invalidated on UNIT_AURA event)
local cachedAuras = {}
local lastAuraCheck = 0
local AURA_CACHE_DURATION = 0.2

-- Out-of-combat trusted cache (persists into combat to handle long-duration buffs)
-- When we check auras out of combat and they're valid, cache them longer
-- Trust them in combat even if aura API returns secrets (handles 50min poisons, etc)
-- Invalidated by UNIT_AURA events, so safe to keep for extended duration
local trustedOutOfCombatCache = {}
local lastTrustedCacheTime = 0
local TRUSTED_CACHE_DURATION = 600  -- Trust out-of-combat checks for 10 minutes (invalidated by events)
local nextExpirationCheck = 0  -- Throttle expiration checking to once per 5 seconds
local EXPIRATION_CHECK_INTERVAL = 5

-- In-combat activation tracking (mirrors proc detection system)
-- When player casts a spell in combat, record it so we know they have the buff/form
-- Cleared on leaving combat (PLAYER_REGEN_ENABLED)
local inCombatActivations = {}

-- Throttle debug prints (per-message-type timestamps)
local lastPrintTime = {}

-- Forward declaration for RefreshAuraCache (defined in Dynamic Aura Detection section)
-- Required because PruneExpiredActivations uses it before the full definition
local RefreshAuraCache

-- Debug mode (BlizzardAPI caches this, only checked once per second)
local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

local function GetCachedSpellInfo(spellID)
    return BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID) or nil
end

-- Invalidate cached aura state (called on UNIT_AURA events from main addon)
-- NOTE: Does NOT clear inCombatActivations - those persist until leaving combat
-- UNIT_AURA confirms auras changed, but activation tracking is independent
-- IMPORTANT: Only wipe trustedOutOfCombatCache when OUT of combat!
-- In combat, we need to preserve the pre-combat snapshot since aura APIs return secrets.
function RedundancyFilter.InvalidateCache()
    wipe(cachedAuras)
    lastAuraCheck = 0

    -- Only invalidate trusted cache when out of combat
    -- In combat, keep the pre-combat snapshot intact
    if not UnitAffectingCombat("player") then
        wipe(trustedOutOfCombatCache)
        lastTrustedCacheTime = 0
        nextExpirationCheck = 0
    end

    -- Prune expired activations (handles toggleable auras being turned off)
    RedundancyFilter.PruneExpiredActivations()
end

-- Clear activation tracking (called only on leaving combat)
function RedundancyFilter.ClearActivationTracking()
    wipe(inCombatActivations)
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

-- Prune expired activations by checking current aura state
-- Called after aura cache refresh to remove toggle-off spells
-- CRITICAL: Only prunes if aura API is accessible (not blocked by secrets)
-- ALSO checks non-aura detection methods (forms, stealth, pets) which work in combat
function RedundancyFilter.PruneExpiredActivations()
    if not next(inCombatActivations) then return end
    
    -- Check each tracked activation
    for spellID, timestamp in pairs(inCombatActivations) do
        local shouldKeep = false
        
        -- Method 1: Form/stance detection (always works - not secret)
        if FormCache then
            local targetFormID = FormCache.GetFormIDBySpellID(spellID)
            if targetFormID then
                local currentFormID = FormCache.GetActiveForm()
                if targetFormID == currentFormID then
                    shouldKeep = true  -- Still in this form
                end
            end
        end
        
        -- Method 2: Stealth detection (always works - not secret)
        if not shouldKeep then
            local spellInfo = GetCachedSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                local name = spellInfo.name
                if name:match("Stealth") or name:match("Vanish") then
                    if SafeIsStealthed() then
                        shouldKeep = true  -- Still stealthed
                    end
                end
            end
        end
        
        -- Method 3: Pet detection (always works - not secret)
        if not shouldKeep and PET_SUMMON_SPELLS[spellID] then
            if SafeHasPetUI() then
                shouldKeep = true  -- Pet still exists
            end
        end
        
        -- Method 4: Mount detection (always works - not secret)
        if not shouldKeep then
            local spellInfo = GetCachedSpellInfo(spellID)
            if spellInfo and spellInfo.name and spellInfo.name:find("Mount") then
                if SafeIsMounted() then
                    shouldKeep = true  -- Still mounted
                end
            end
        end
        
        -- Method 5: Aura API (only when accessible, not blocked by secrets)
        if not shouldKeep then
            local auraAPIAvailable = BlizzardAPI and BlizzardAPI.IsRedundancyFilterAvailable and BlizzardAPI.IsRedundancyFilterAvailable()
            if auraAPIAvailable and RefreshAuraCache then
                local auras = RefreshAuraCache()
                if auras and auras.byID and not auras.hasSecrets then
                    -- Aura data is reliable - check if buff still active
                    if auras.byID[spellID] then
                        shouldKeep = true  -- Aura still present
                    end
                else
                    -- Aura data unreliable - keep activation (conservative)
                    shouldKeep = true
                end
            else
                -- Aura API blocked - keep activation (conservative)
                shouldKeep = true
            end
        end
        
        -- Remove if no detection method confirms it's still active
        if not shouldKeep then
            inCombatActivations[spellID] = nil
        end
    end
end

-- Record spell activation during combat (called from UNIT_SPELLCAST_SUCCEEDED)
-- Mirrors proc detection system - reliable even with combat log restrictions
function RedundancyFilter.RecordSpellActivation(spellID)
    if not spellID then return end
    local now = GetTime()
    inCombatActivations[spellID] = now
end

--------------------------------------------------------------------------------
-- Dynamic Aura Detection
--------------------------------------------------------------------------------

-- Build cache of current player auras (by spellID, name, and icon)
-- Now also stores duration and expiration time for pandemic window checks
RefreshAuraCache = function()
    local now = GetTime()
    local inCombat = UnitAffectingCombat("player")
    
    -- If in combat and we have a recent trusted out-of-combat cache, use it
    -- But filter out any auras that have expired based on cached expiration times
    -- Throttle expiration checks to once per 5s (UNIT_AURA handles most invalidation)
    if inCombat and trustedOutOfCombatCache.byID and (now - lastTrustedCacheTime) < TRUSTED_CACHE_DURATION then
        -- Only check for expired auras every 5 seconds (not every cache access)
        if now >= nextExpirationCheck then
            nextExpirationCheck = now + EXPIRATION_CHECK_INTERVAL
            for spellID, auraInfo in pairs(trustedOutOfCombatCache.auraInfo or {}) do
                if auraInfo.expirationTime and auraInfo.expirationTime > 0 and now >= auraInfo.expirationTime then
                    -- This aura expired, remove it from trusted cache
                    trustedOutOfCombatCache.byID[spellID] = nil
                    trustedOutOfCombatCache.auraInfo[spellID] = nil
                end
            end
        end
        -- If we still have data, use trusted cache
        if trustedOutOfCombatCache.byID and next(trustedOutOfCombatCache.byID) then
            return trustedOutOfCombatCache
        end
        -- Trusted cache empty or fully expired, fall through to refresh
    end
    
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
            
            -- Best-effort: If critical fields are secret, skip this aura but continue processing others
            -- auraInstanceID is documented as NeverSecret in 12.0, so we can always track it
            local spellIdIsSecret = BlizzardAPI.IsSecretValue(auraData.spellId)
            local nameIsSecret = BlizzardAPI.IsSecretValue(auraData.name)
            
            if spellIdIsSecret or nameIsSecret then
                -- Mark that we encountered secrets (cache may be incomplete)
                cachedAuras.hasSecrets = true
                -- Continue to next aura - don't break! Best-effort: process what we can
            else
                -- Safe to process this aura
                if auraData.spellId then
                    cachedAuras.byID[auraData.spellId] = true
                    -- Store aura timing info for pandemic check (use API-specific helper)
                    local dur, exp = BlizzardAPI.GetAuraTiming("player", i, "HELPFUL")
                    cachedAuras.auraInfo[auraData.spellId] = {
                        duration = dur or 0,
                        expirationTime = exp or 0,
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
        end
    -- Fallback for older clients
    elseif UnitAura then
        for i = 1, 40 do
            local ok, name, icon, count, _, duration, expirationTime, _, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok or not name then break end
            
            -- Best-effort: skip secret auras but continue processing others
            local spellIdIsSecret = BlizzardAPI.IsSecretValue(spellId)
            local nameIsSecret = BlizzardAPI.IsSecretValue(name)
            
            if spellIdIsSecret or nameIsSecret then
                cachedAuras.hasSecrets = true
                -- Continue to next aura - don't break!
            else
                if spellId then
                    cachedAuras.byID[spellId] = true
                    local durIsSecret = BlizzardAPI.IsSecretValue(duration)
                    local expIsSecret = BlizzardAPI.IsSecretValue(expirationTime)
                    cachedAuras.auraInfo[spellId] = {
                        duration = (not durIsSecret and duration) or 0,
                        expirationTime = (not expIsSecret and expirationTime) or 0,
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
    end
    
    lastAuraCheck = now
    
    -- If out of combat and we got clean data (no secrets), save as trusted cache
    if not inCombat and not cachedAuras.hasSecrets then
        -- Deep copy to trusted cache
        wipe(trustedOutOfCombatCache)
        trustedOutOfCombatCache.byID = {}
        trustedOutOfCombatCache.byName = {}
        trustedOutOfCombatCache.byIcon = {}
        trustedOutOfCombatCache.auraInfo = {}
        for k, v in pairs(cachedAuras.byID) do trustedOutOfCombatCache.byID[k] = v end
        for k, v in pairs(cachedAuras.byName) do trustedOutOfCombatCache.byName[k] = v end
        for k, v in pairs(cachedAuras.byIcon) do trustedOutOfCombatCache.byIcon[k] = v end
        for k, v in pairs(cachedAuras.auraInfo) do 
            trustedOutOfCombatCache.auraInfo[k] = {
                duration = v.duration,
                expirationTime = v.expirationTime,
                count = v.count
            }
        end
        lastTrustedCacheTime = now
    end
    
    return cachedAuras
end

-- Check if player has a buff by spell ID
local function HasBuffBySpellID(spellID)
    if not spellID then return false end
    
    -- Check in-combat activation tracking first (mirrors proc detection)
    if inCombatActivations[spellID] then return true end
    
    -- Then check cached aura data
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

--------------------------------------------------------------------------------
-- Native Spell Classification Functions (12.0 Compliant)
--------------------------------------------------------------------------------

-- Check if spell applies an aura (using native tables + name pattern fallback)
-- Returns: isAura, isPersonalAura, isUniqueAura
local function IsAuraSpell(spellID)
    if not spellID then return false, false, false end
    
    -- Check our known unique aura table first (fast path)
    if UNIQUE_AURA_SPELLS[spellID] then
        local isPersonal = PERSONAL_AURA_SPELLS[spellID] or false
        return true, isPersonal, true
    end
    
    -- Check personal auras
    if PERSONAL_AURA_SPELLS[spellID] then
        return true, true, false
    end
    
    -- Fallback: Name-based detection for unknown spells
    -- Forms, Stances, Presences, Aspects are typically unique self-auras
    local spellInfo = GetCachedSpellInfo(spellID)
    if spellInfo and spellInfo.name then
        local name = spellInfo.name
        if name:match("Form$") or name:match("Stance$") or 
           name:match("Presence$") or name:match("Aspect of") then
            return true, true, true  -- Treat as unique personal aura
        end
    end
    
    return false, false, false
end

-- Check if spell is a pet-related ability (native table + name pattern)
local function IsPetSpell(spellID)
    if not spellID then return false end
    
    -- Check known pet summon table
    if PET_SUMMON_SPELLS[spellID] then
        return true
    end
    
    -- Name pattern fallback handled by IsPetSummonSpell below
    return false
end

-- Check if spell is DPS-relevant for rotation queue
-- When aura detection is blocked, only show spells that are clearly offensive/rotational
-- Uses name-based heuristics since we don't have LibPlayerSpells flags
local function IsDPSRelevant(spellID)
    if not spellID then return false end
    
    -- Known raid buffs: Always hide when can't check if active
    if RAID_BUFF_SPELLS[spellID] then
        return false
    end
    
    -- Known pet summons: Hide when can't check if pet exists
    if PET_SUMMON_SPELLS[spellID] then
        return false
    end
    
    -- Known unique auras (forms/stances): Hide when can't check if active
    if UNIQUE_AURA_SPELLS[spellID] then
        return false
    end
    
    -- Get spell info for name-based filtering
    local spellInfo = GetCachedSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then
        return true  -- Unknown spell, fail-open
    end
    
    local name = spellInfo.name
    
    -- Filter out known utility spell patterns when aura API blocked
    if name:match("Form$") or name:match("Stance$") or name:match("Presence$") then
        return false  -- Forms/stances should not show
    end
    
    if name:match("^Summon") or name:match("^Call Pet") then
        return false  -- Pet summons
    end
    
    if name:match("Revive") and name:match("Pet") then
        return false  -- Pet revive
    end
    
    -- Default: Include in queue (fail-open for combat relevance)
    return true
end

--------------------------------------------------------------------------------
-- Pet Detection
--------------------------------------------------------------------------------

local function HasActivePet()
    -- UnitExists/HasPetUI/HasPetSpells are fast C calls, no cache needed
    return SafeUnitExists("pet") or SafeHasPetUI() or SafeHasPetSpells()
end

-- Check if pet is alive (exists AND not dead)
-- 12.0: UnitIsDead result may be secret for non-player units
local function IsPetAlive()
    if not SafeUnitExists("pet") then return false end
    -- UnitIsDead returns true if unit is dead, false if alive
    local ok, isDead = pcall(UnitIsDead, "pet")
    if not ok then return true end  -- Fail-safe: assume alive
    
    -- 12.0: Check if result is secret - fail-open (assume alive if can't determine)
    if BlizzardAPI.IsSecretValue(isDead) then
        return true  -- Fail-open: assume pet is alive
    end
    
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
-- With Dragon-Tempered Blades talent: 2 lethal + 2 non-lethal (4 total)
-- If slots are filled, poison suggestions are redundant
--
-- WOW 12.0 CAST-BASED INFERENCE:
-- Poisons are HOUR-LONG buffs (Category A - Always Safe for cast inference)
-- Once cast is observed via UNIT_SPELLCAST_SUCCEEDED, assume active until
-- combat ends. No need to query aura state which may return secrets.
--------------------------------------------------------------------------------

-- Poison CAST spell IDs (what C_AssistedCombat recommends)
-- These are tracked via UNIT_SPELLCAST_SUCCEEDED -> inCombatActivations
-- Duration: 1 HOUR - safe to assume active once cast observed
local ROGUE_POISON_CAST_IDS = {
    [2823] = true,   -- Deadly Poison (Lethal)
    [8679] = true,   -- Wound Poison (Lethal)
    [315584] = true, -- Instant Poison (Lethal)
    [381664] = true, -- Atrophic Poison (Lethal)
    [3408] = true,   -- Crippling Poison (Non-Lethal)
    [5761] = true,   -- Numbing Poison (Non-Lethal)
}

-- Poison BUFF spell IDs (what appears in the player's aura list)
-- Include BOTH cast IDs and known alternate IDs for aura cache fallback
-- Note: Primary detection is via inCombatActivations (cast tracking)
local ROGUE_POISON_BUFF_IDS = {
    -- Lethal Poisons
    [2823] = true,   -- Deadly Poison (cast ID)
    [2818] = true,   -- Deadly Poison (possible buff ID)
    [8679] = true,   -- Wound Poison (cast ID)
    [8680] = true,   -- Wound Poison (possible buff ID)
    [315584] = true, -- Instant Poison (same for cast/buff)
    [381637] = true, -- Atrophic Poison (confirmed buff ID)
    [381664] = true, -- Atrophic Poison (cast ID)
    -- Non-Lethal Poisons
    [3408] = true,   -- Crippling Poison (cast ID)
    [3409] = true,   -- Crippling Poison (possible buff ID)
    [5761] = true,   -- Numbing Poison (cast ID)
    [5760] = true,   -- Numbing Poison (possible buff ID)
}

-- Poison buff names (fallback detection)
local ROGUE_POISON_NAMES = {
    ["Deadly Poison"] = true,
    ["Wound Poison"] = true,
    ["Instant Poison"] = true,
    ["Atrophic Poison"] = true,
    ["Crippling Poison"] = true,
    ["Numbing Poison"] = true,
}

-- Check if a spell is a Rogue poison application spell
local function IsRoguePoisonSpell(spellID)
    return spellID and ROGUE_POISON_CAST_IDS[spellID]
end

-- Count how many poison buffs are currently active on the player
-- Count active poison buffs using cast-based inference (12.0 compatible)
-- Priority: Cast tracking > Aura cache by ID > Aura cache by name
-- Poisons are 1-hour buffs, safe to assume active once cast is observed
local function CountActivePoisonBuffs()
    local auras = RefreshAuraCache()
    local count = 0
    local foundNames = {}  -- Track poison names to avoid double-counting

    -- PRIMARY: Cast-based inference via UNIT_SPELLCAST_SUCCEEDED
    -- Most reliable in combat - doesn't depend on aura API (may return secrets)
    -- Poisons are hour-long buffs, safe to assume active until combat ends
    for spellID in pairs(ROGUE_POISON_CAST_IDS) do
        if inCombatActivations[spellID] then
            count = count + 1
            local spellInfo = GetCachedSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                foundNames[spellInfo.name] = true
            end
        end
    end

    -- FALLBACK 1: Aura cache by buff spell ID (works out of combat, pre-combat buffs)
    if auras.byID then
        for spellID in pairs(ROGUE_POISON_BUFF_IDS) do
            if auras.byID[spellID] then
                local spellInfo = GetCachedSpellInfo(spellID)
                local name = spellInfo and spellInfo.name
                if name and not foundNames[name] then
                    count = count + 1
                    foundNames[name] = true
                end
            end
        end
    end

    -- FALLBACK 2: Aura cache by name (catches unknown buff IDs)
    if auras.byName then
        for poisonName in pairs(ROGUE_POISON_NAMES) do
            if auras.byName[poisonName] and not foundNames[poisonName] then
                count = count + 1
                foundNames[poisonName] = true
            end
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
-- isDefensiveCheck: optional flag to skip DPS-relevance filter (for defensive spell selection)
--------------------------------------------------------------------------------

function RedundancyFilter.IsSpellRedundant(spellID, profile, isDefensiveCheck)
    if not spellID then return false end
    
    local debugMode = GetDebugMode()
    
    -- 1. FORM/STANCE REDUNDANCY (check FIRST - unaffected by 12.0 secrets)
    -- Stance bar APIs are client-side UI state, always accessible
    -- If this is a form spell and we're already in that form, skip it
    if FormCache then
        local targetFormID = FormCache.GetFormIDBySpellID(spellID)
        if targetFormID then
            local currentFormID = FormCache.GetActiveForm()
            if targetFormID == currentFormID then
                -- Throttle debug output (once per spell per 5 seconds)
                local now = GetTime()
                local throttleKey = "form_" .. spellID
                if debugMode and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > 5) then
                    lastPrintTime[throttleKey] = now
                    local spellInfo = GetCachedSpellInfo(spellID)
                    local spellName = spellInfo and spellInfo.name or tostring(spellID)
                    print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: " .. spellName .. " - already in form " .. targetFormID)
                end
                return true
            end
        else
            -- Fallback: check by name patterns (Form, Stance, Presence, etc.)
            local spellInfo = GetCachedSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                local name = spellInfo.name
                if name:match("Form$") or name:match("Stance$") or name:match("Presence$") then
                    -- It's a form spell but not in our mapping - check if name matches current form
                    local currentFormName = FormCache.GetActiveFormName()
                    if currentFormName and currentFormName == name then
                        -- Throttle debug output
                        local now = GetTime()
                        local throttleKey = "form_name_" .. name
                        if debugMode and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > 5) then
                            lastPrintTime[throttleKey] = now
                            print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: " .. name .. " - already active (name match)")
                        end
                        return true
                    end
                end
            end
        end
    end
    
    -- NOTE: Cooldown filtering moved to SpellQueue.IsSpellUsable() which uses a 2s threshold
    -- Position 1 doesn't get usability filtering (shows what Blizzard recommends)
    -- Positions 2+ get filtered by SpellQueue before reaching RedundancyFilter
    
    -- Check if aura API is accessible (12.0+ secret values may block this)
    -- Test both API availability check AND cache refresh for secrets
    local auraAPIBlocked = BlizzardAPI and BlizzardAPI.IsRedundancyFilterAvailable and not BlizzardAPI.IsRedundancyFilterAvailable()
    local auras = RefreshAuraCache()
    
    -- If aura API blocked OR cache detected secrets, filter non-DPS spells
    -- EXCEPTION: Defensive checks bypass this filter (heals are not "DPS-relevant" but are valid defensives)
    -- IMPORTANT: Continue to remaining checks (pet/stealth/mount/etc) even when aura API blocked
    if auraAPIBlocked or (auras and auras.hasSecrets) then
        if not isDefensiveCheck and not IsDPSRelevant(spellID) then
            -- Throttle this debug message to avoid spam (once per spell per 5 seconds)
            local now = GetTime()
            local throttleKey = "nondps_" .. spellID
            if GetDebugMode() and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > 5) then
                lastPrintTime[throttleKey] = now
                local reason = auraAPIBlocked and "aura API blocked" or "secrets detected in cache"
                local spellInfo = GetCachedSpellInfo(spellID)
                local spellName = spellInfo and spellInfo.name or "Unknown"
                print("|cff66ccffJAC|r |cffff6666FILTERED|r: " .. spellName .. " (ID: " .. spellID .. ") - Non-DPS spell (" .. reason .. ")")
            end
            return true  -- Hide non-DPS spells
        end
        -- Fall through for both defensive checks AND DPS-relevant spells
        -- Continue to pet/stealth/mount checks even when aura checks are blocked
    end
    
    local spellInfo = GetCachedSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then return false end
    
    local spellName = spellInfo.name
    local isKnownAuraSpell, isPersonalAura, isUniqueAura = IsAuraSpell(spellID)
    
    -- Note: Removed verbose "Checking redundancy" debug output - was extremely spammy
    -- Use /jac test or /jac find for diagnostics instead
    
    -- 3. AURA SPELL REDUNDANCY
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
    
    -- 4. PET SPELL REDUNDANCY
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
        local isPetSpellByTable = IsPetSpell(spellID)
        if (isPetSpellByTable or IsPetSummonSpell(spellName)) and SafeHasPetUI() then
            if debugMode then
                local source = isPetSpellByTable and "native table" or "name pattern"
                print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: Pet summon (" .. source .. ") but pet already exists")
            end
            return true
        end
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
    
    -- 7. ROGUE POISON REDUNDANCY
    -- Rogues can have max 2 poisons active (1 lethal + 1 non-lethal)
    -- If both slots are filled, all poison suggestions are redundant
    if IsRoguePoisonSpell(spellID) then
        local activePoisons = CountActivePoisonBuffs()
        if activePoisons >= 2 then
            -- Throttle debug output - only print once per interval
            -- (This check runs every frame, would spam without throttle)
            return true
        end
    end
    
    -- 8. WEAPON ENCHANT REDUNDANCY (Shaman Imbues)
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
    
    -- Note: Removed verbose "NOT REDUNDANT" debug output - was extremely spammy
    return false
end

--------------------------------------------------------------------------------
-- Debug / Diagnostic Functions
--------------------------------------------------------------------------------

-- Get native spell classification info for a spell (for debugging)
-- Replaces legacy GetLPSInfo - now uses native tables instead of LibPlayerSpells
function RedundancyFilter.GetSpellClassification(spellID)
    if not spellID then
        return { spellID = nil, known = false }
    end
    
    local spellInfo = GetCachedSpellInfo(spellID)
    local isAura, isPersonal, isUnique = IsAuraSpell(spellID)
    
    return {
        spellID = spellID,
        name = spellInfo and spellInfo.name or "Unknown",
        known = true,
        -- Native classification flags
        isRaidBuff = RAID_BUFF_SPELLS[spellID] or false,
        isPetSummon = PET_SUMMON_SPELLS[spellID] or false,
        isUniqueAura = isUnique,
        isPersonalAura = isPersonal,
        isAura = isAura,
        -- Derived from checks
        isDPSRelevant = IsDPSRelevant(spellID),
        isRoguePoison = IsRoguePoisonSpell(spellID),
        isWeaponEnchant = IsWeaponEnchantSpell(spellID),
        -- 12.0 compliance note
        source = "native",  -- Was "LibPlayerSpells", now "native"
    }
end

-- Legacy alias for backwards compatibility (was GetLPSInfo when using LibPlayerSpells)
function RedundancyFilter.GetLPSInfo(spellID)
    return RedundancyFilter.GetSpellClassification(spellID)
end

-- Legacy function - always returns false since we no longer use LibPlayerSpells
function RedundancyFilter.IsLibPlayerSpellsAvailable()
    return false
end

-- Expose aura cache for diagnostics
function RedundancyFilter.GetAuraCache()
    return RefreshAuraCache()
end