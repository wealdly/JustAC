-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Redundancy Filter Module - Hides active buffs and forms from queue
local RedundancyFilter = LibStub:NewLibrary("JustAC-RedundancyFilter", 45)
if not RedundancyFilter then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

-- Hot path cache
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local UnitAffectingCombat = UnitAffectingCombat
local table_remove = table.remove
local C_Secrets = C_Secrets

-- Talent-override variants resolve to a base spell ID the static classification
-- tables key on. Try the ID, then its base spell (SpellDB.GetBaseSpell, cached).
-- Keeps this module's own tables variant-aware like the SpellDB accessors.
local function StaticLookup(t, spellID)
    if not t or not spellID then return nil end
    local v = t[spellID]
    if v ~= nil then return v end
    local base = SpellDB and SpellDB.GetBaseSpell and SpellDB.GetBaseSpell(spellID)
    if base then return t[base] end
    return nil
end


-- Spell classification tables (static data maintained in SpellDB.lua)
-- See SpellDB.RAID_BUFF_SPELLS / PET_SUMMON_SPELLS / UNIQUE_AURA_SPELLS for contents.
local RAID_BUFF_SPELLS   = SpellDB and SpellDB.RAID_BUFF_SPELLS   or {}
local PET_SUMMON_SPELLS  = SpellDB and SpellDB.PET_SUMMON_SPELLS  or {}
local PET_SUMMON_EXCLUSIVE = SpellDB and SpellDB.PET_SUMMON_EXCLUSIVE or {}
local UNIQUE_AURA_SPELLS = SpellDB and SpellDB.UNIQUE_AURA_SPELLS or {}
local ROGUE_POISON_CAST_IDS = SpellDB and SpellDB.ROGUE_POISON_CAST_IDS or {}
local WEAPON_ENCHANT_SPELLS = SpellDB and SpellDB.WEAPON_ENCHANT_SPELLS or {}

--------------------------------------------------------------------------------
-- NeverSecret Aura Whitelist (12.0+)
-- Derived from the engine hotfix that exempted these spells, confirmed by probing
-- the aura API on live units.
-- These spells return non-secret AuraData (spellId, name, icon, duration, etc.)
-- even in combat on player/party/raid units. When the aura API reports a field
-- as "secret" for one of these spells, we can safely pcall-access it - the data
-- is guaranteed readable and the pcall verifies that guarantee holds.
-- This allows resolution of NEW auras gained during combat (no instance-map entry)
-- without waiting for the next out-of-combat refresh.
--------------------------------------------------------------------------------
local NEVER_SECRET_AURA_SPELLS = {
    -- Raid buffs merge in from SpellDB.RAID_BUFF_SPELLS below (single source);
    -- only raid-buff-like spells NOT in that table are listed here.
    [369459] = true,  -- Source of Magic (Evoker)
    [462854] = true,  -- Skyfury
    [381741] = true,  -- Blessing of the Bronze (DH)
    [381746] = true,  -- Blessing of the Bronze (DK)
    [381748] = true,  -- Blessing of the Bronze (Druid)
    [381750] = true,  -- Blessing of the Bronze (Hunter)
    [381751] = true,  -- Blessing of the Bronze (Mage)
    [381752] = true,  -- Blessing of the Bronze (Monk)
    [381753] = true,  -- Blessing of the Bronze (Paladin)
    [381754] = true,  -- Blessing of the Bronze (Priest)
    [381756] = true,  -- Blessing of the Bronze (Rogue)
    [381757] = true,  -- Blessing of the Bronze (Shaman)
    [381758] = true,  -- Blessing of the Bronze (Warlock)
    [474754] = true,  -- Symbiotic Relationship
    -- Rogue poisons merge in from SpellDB.ROGUE_POISON_CAST_IDS below (cast = buff IDs)
    -- Shaman Imbuements
    [319773] = true,  -- Windfury Weapon (aura)
    [319778] = true,  -- Flametongue Weapon (aura)
    [382021] = true,  -- Earthliving Weapon (aura, cast)
    [382022] = true,  -- Earthliving Weapon (buff)
    [457496] = true,  -- Tidecaller Guard (aura)
    [457481] = true,  -- Tidecaller Guard (buff)
    [462757] = true,  -- Thunderstrike Ward (aura)
    [462742] = true,  -- Thunderstrike Ward (buff)
    -- Resources / Class Mechanics
    [205473] = true,  -- Icicles (Mage)
    [260286] = true,  -- Tip of the Spear (Hunter)
    -- Rites (Self Buffs)
    [433568] = true,  -- Rite of Sanctification
    [433583] = true,  -- Rite of Adjuration
    -- Cooldowns
    [8690]   = true,  -- Hearthstone
    [20608]  = true,  -- Reincarnation
    -- Debuffs / Exhaustion
    [57723]  = true,  -- Exhaustion (Heroism)
    [390435] = true,  -- Exhaustion (alternate)
    [57724]  = true,  -- Sated (Bloodlust)
    [80354]  = true,  -- Temporal Displacement (Time Warp)
    [95809]  = true,  -- Insanity (Ancient Hysteria)
    [160455] = true,  -- Fatigued
    [264689] = true,  -- Fatigued (alternate)
    [26013]  = true,  -- Deserter
    [71041]  = true,  -- Dungeon Deserter
    -- Skyriding
    [427490] = true,  -- Ride Along Available
    [447959] = true,  -- Ride Along Active
    [447960] = true,  -- Ride Along Inactive
}

-- Raid buffs and poison casts single-source from SpellDB: same community-verified
-- NeverSecret guarantee, and additions there flow into this whitelist automatically.
for id in pairs(RAID_BUFF_SPELLS) do NEVER_SECRET_AURA_SPELLS[id] = true end
for id in pairs(ROGUE_POISON_CAST_IDS) do NEVER_SECRET_AURA_SPELLS[id] = true end

-- Dynamic exemption check (12.0.7+): C_Secrets.GetSpellAuraSecrecy returns a
-- plain SecrecyLevel (0=NeverSecret) and per-spell flags override the global
-- ShouldAurasBeSecret rule (validated in-game: Mark of the Wild stays readable
-- mid-combat in every context). Supersedes hand-curating the whitelist above;
-- the static list remains as seed + fallback for clients without the API.
local auraSecrecyLevelCache = {}
local C_Secrets_GetSpellAuraSecrecy = C_Secrets and C_Secrets.GetSpellAuraSecrecy
local function IsNeverSecretAura(spellID)
    if StaticLookup(NEVER_SECRET_AURA_SPELLS, spellID) then return true end
    if not C_Secrets_GetSpellAuraSecrecy then return false end
    local level = auraSecrecyLevelCache[spellID]
    if level == nil then
        local ok, v = pcall(C_Secrets_GetSpellAuraSecrecy, spellID)
        level = (ok and type(v) == "number") and v or -1
        auraSecrecyLevelCache[spellID] = level
    end
    return level == 0
end

-- Forced evaluation: NeverSecret fields carry the generic secret mark
-- (issecretvalue returns true) but their values ARE readable - index inside
-- the pcall and let genuinely-secret values throw. Unsecret() can't serve this
-- case because it trusts the generic mark. Plain-function pcall (no closure)
-- keeps the UNIT_AURA path allocation-free.
local function readNum(t, f) return t[f] + 0 end
local function readStr(t, f) return t[f] .. "" end
local function ForceReadNumber(tbl, field)
    local ok, v = pcall(readNum, tbl, field)
    if ok then return v end
    return nil
end
local function ForceReadString(tbl, field)
    local ok, v = pcall(readStr, tbl, field)
    if ok then return v end
    return nil
end

-- Pandemic window: allow recast when aura has less than 30% duration remaining
-- This matches WoW's pandemic mechanic where refreshing extends duration
local PANDEMIC_THRESHOLD = 0.30
-- Time-remaining threshold for long-duration buffs (poisons, raid buffs, etc). When less
-- than this many seconds remain, stop filtering - show the recast suggestion so the player
-- can reapply before or immediately after entering combat. Owned by PrecombatEngine so the
-- queue hides a buff for exactly as long as the pre-combat checklist stays quiet about it.
-- expirationTime is cached out of combat as a plain Lua number (GetTime() timestamp),
-- so remaining = expirationTime - GetTime() is valid arithmetic even in combat.
-- auraInstanceID → expirationTime mapping (instanceToTimingMap) carries this into combat.
local precombatEngine  -- resolved on first use: that module loads after this one
local function GetPrecombatEngine()
    precombatEngine = precombatEngine or LibStub("JustAC-PrecombatEngine", true)
    return precombatEngine
end
local function RefreshWindow()
    local PE = GetPrecombatEngine()
    if PE and PE.RefreshWindow then
        return PE.RefreshWindow()
    end
    return 180  -- solo default, if the checklist module ever isn't loaded
end
local LONG_BUFF_DURATION_CUTOFF = 600  -- Only apply the flat window to buffs >= 10 min

-- Cache auras to avoid repeated API calls (refreshed on UNIT_AURA event)
-- UNIT_AURA events invalidate the cache, so 0.5s is safe and reduces API calls by 60%
local cachedAuras = {}
local lastAuraCheck = 0
local AURA_CACHE_DURATION = 0.5

-- Out-of-combat trusted cache (persists into combat to handle long-duration buffs)
-- When we check auras out of combat and they're valid, cache them longer
-- Trust them in combat even if aura API returns secrets (handles 50min poisons, etc)
-- Invalidated by UNIT_AURA events, so safe to keep for extended duration
local trustedOutOfCombatCache = {}
local lastTrustedCacheTime = 0
local TRUSTED_CACHE_DURATION = 600  -- Trust out-of-combat checks for 10 minutes (invalidated by events)
local TRUSTED_CACHE_RECENT_THRESHOLD = 300  -- Cache younger than 5 min uses exact expiration; older uses 80% threshold
local nextExpirationCheck = 0  -- Throttle expiration checking to once per 5 seconds
local EXPIRATION_CHECK_INTERVAL = 5

--------------------------------------------------------------------------------
-- Aura Instance ID Mapping (12.0 Combat-Safe Aura Detection)
-- auraInstanceID is NeverSecret in 12.0 - it's always readable even in combat.
-- We build a map of instanceID → spellID out of combat (when spellId is readable),
-- then use it in combat to resolve secret spellId fields back to real values.
-- UNIT_AURA addedAuras/removedAuraInstanceIDs keep the map current during combat.
--------------------------------------------------------------------------------
local instanceToSpellMap = {}   -- auraInstanceID → spellID
local instanceToNameMap = {}    -- auraInstanceID → spell name
local instanceToIconMap = {}    -- auraInstanceID → icon texture
local instanceToTimingMap = {}  -- auraInstanceID → {duration, expirationTime, count, halfwayThreshold}

-- Fraction of an aura's duration still remaining at the pandemic window: refreshing at or
-- past this point no longer clips the existing application.
local PANDEMIC_REMAINING = 0.2

--- Build the timing record every aura cache stores, including the pandemic threshold as an
--- ABSOLUTE timestamp. The subtraction has to happen here, at capture time, because in
--- combat duration/expirationTime are secret and cannot be read or subtracted - only the
--- already-computed threshold can be compared against `now` later. Every caller goes
--- through this so that rule (and the 0.2) is stated once.
local function BuildAuraTiming(dur, exp, count)
    dur, exp = dur or 0, exp or 0
    local halfwayThreshold
    if dur > 0 and exp > 0 then
        halfwayThreshold = exp - (dur * PANDEMIC_REMAINING)
    end
    return {
        duration = dur,
        expirationTime = exp,
        count = count or 1,
        halfwayThreshold = halfwayThreshold,
    }
end

-- Track spellIDs explicitly removed during combat (via UNIT_AURA removedAuraInstanceIDs)
-- Prevents trustedOutOfCombatCache from re-adding auras the player manually cancelled
-- Cleared on leaving combat (ClearActivationTracking)
local combatRemovedSpellIDs = {}

-- Pending activation queue: bridges UNIT_SPELLCAST_SUCCEEDED → UNIT_AURA addedAuras
-- When a spell is cast in combat, we know the spellID but not the new auraInstanceID.
-- When addedAuras fires with a secret spellId, we match by timing to map the instance.
-- This enables proper removal tracking on subsequent remove/reapply cycles.
local PENDING_ACTIVATION_WINDOW = 2.0  -- Max seconds between cast and UNIT_AURA addedAuras
local pendingActivations = {}  -- Array of {spellID, timestamp}

-- In-combat activation tracking (mirrors proc detection system)
-- When player casts a spell in combat, record it so we know they have the buff/form
-- Clear activation state on leaving combat to reset for next pull
local inCombatActivations = {}

-- Throttle debug prints (per-message-type timestamps)
local lastPrintTime = {}

-- Runs per spell per queue build (~2Hz out of combat) - unthrottled prints flood chat
local function DebugPrintThrottled(key, msg)
    local now = GetTime()
    if lastPrintTime[key] and now - lastPrintTime[key] <= 5 then return end
    lastPrintTime[key] = now
    print(msg)
end

-- Forward declaration for RefreshAuraCache (defined in Dynamic Aura Detection section)
-- Required because PruneExpiredActivations uses it before the full definition
local RefreshAuraCache

-- Debug mode (BlizzardAPI caches this, only checked once per second)
local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

-- Hot-path alias for BlizzardAPI.GetCachedSpellInfo (avoids repeated nil guards)
local GetCachedSpellInfo = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo or function() return nil end

-- Invalidate aura cache on UNIT_AURA; keep inCombatActivations until combat ends
-- Preserve trusted out-of-combat snapshot while in combat to avoid gaps caused by secret values
-- Preserve instanceToSpellMap always - it's our combat-safe aura identity resolution
function RedundancyFilter.InvalidateCache()
    wipe(cachedAuras)
    lastAuraCheck = 0

    -- Only invalidate trusted cache and instance maps when out of combat
    -- In combat, keep the pre-combat snapshot and instance maps intact
    if not UnitAffectingCombat("player") then
        wipe(trustedOutOfCombatCache)
        lastTrustedCacheTime = 0
        nextExpirationCheck = 0
        -- Instance maps are rebuilt on next RefreshAuraCache out of combat
        -- Don't wipe them here - they may still be valid and are cheap to rebuild
    end

    -- Prune expired activations (handles toggleable auras being turned off)
    RedundancyFilter.PruneExpiredActivations()
end

-- Clear activation tracking (called only on leaving combat)
function RedundancyFilter.ClearActivationTracking()
    wipe(inCombatActivations)
    wipe(combatRemovedSpellIDs)
    wipe(pendingActivations)
end

--- Flush all four aura instance ID maps.
--- Called on ENCOUNTER_START and CHALLENGE_MODE_START because WoW 12.0.5
--- re-randomizes auraInstanceID values at encounter entry, invalidating any
--- pre-built instance→spell mappings.  The maps are rebuilt immediately from
--- the next batch of UNIT_AURA addedAuras events.
function RedundancyFilter.FlushInstanceMaps()
    wipe(instanceToSpellMap)
    wipe(instanceToNameMap)
    wipe(instanceToIconMap)
    wipe(instanceToTimingMap)
    lastAuraCheck = 0       -- force RefreshAuraCache on next out-of-combat tick
end

--------------------------------------------------------------------------------
-- UNIT_AURA Incremental Update (12.0 Instance Map Maintenance)
-- Called from JustAC:OnUnitAura with the updateInfo payload.
-- Processes addedAuras (new auras with possibly non-secret data even in combat)
-- and removedAuraInstanceIDs (clean removal from instance maps).
--------------------------------------------------------------------------------
function RedundancyFilter.OnUnitAuraUpdate(updateInfo)
    if not updateInfo then return end
    
    if updateInfo.removedAuraInstanceIDs then
        for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            -- Record the spellID before removing, so trusted cache merge doesn't re-add it
            local removedSpellID = instanceToSpellMap[instanceID]
            if removedSpellID then
                combatRemovedSpellIDs[removedSpellID] = true
                -- Also clear from inCombatActivations (player may have cast then cancelled)
                inCombatActivations[removedSpellID] = nil
            end
            instanceToSpellMap[instanceID] = nil
            instanceToNameMap[instanceID] = nil
            instanceToIconMap[instanceID] = nil
            instanceToTimingMap[instanceID] = nil
        end
    end
    
    -- Process added auras: populate instance maps for new auras
    -- In 12.0, addedAuras is an array of AuraData tables for newly applied auras.
    -- The spellId/name may be secret in combat, but we try anyway - if readable,
    -- we get immediate mapping; if secret, match against pendingActivations by timing.
    if updateInfo.addedAuras then
        local now = GetTime()
        
        for i = #pendingActivations, 1, -1 do
            if now - pendingActivations[i].time > PENDING_ACTIVATION_WINDOW then
                table_remove(pendingActivations, i)
            end
        end
        
        for _, auraData in ipairs(updateInfo.addedAuras) do
            local instanceID = auraData.auraInstanceID
            if instanceID then
                local spellIdIsSecret = BlizzardAPI.IsSecretValue(auraData.spellId)
                local nameIsSecret = BlizzardAPI.IsSecretValue(auraData.name)
                local resolvedSpellID = nil
                
                -- Determine if this is a beneficial aura (everything we track is helpful)
                -- isHelpful/isHarmful may or may not be secret; fail-open if unreadable
                local isHelpful = auraData.isHelpful
                local isHarmful = auraData.isHarmful
                if BlizzardAPI.IsSecretValue(isHelpful) then isHelpful = nil end
                if BlizzardAPI.IsSecretValue(isHarmful) then isHarmful = nil end
                -- Skip harmful auras entirely - we only track beneficial spells
                local isDefinitelyHarmful = (isHarmful == true) or (isHelpful == false)
                
                local exemptReadable = false
                if not isDefinitelyHarmful then
                    if not spellIdIsSecret and auraData.spellId then
                        resolvedSpellID = auraData.spellId
                    elseif spellIdIsSecret then
                        -- NeverSecret exemption: per-spell flags override the global
                        -- rule, so the field may be readable despite the generic
                        -- secret mark. Forced evaluation + exemption check gives
                        -- immediate mapping for exempt auras gained mid-combat
                        -- (raid buff recast, poison reapply) without waiting for
                        -- the timing match below.
                        local realSpellId = ForceReadNumber(auraData, "spellId")
                        if realSpellId and IsNeverSecretAura(realSpellId) then
                            resolvedSpellID = realSpellId
                            exemptReadable = true
                        end
                    end
                    if not resolvedSpellID and spellIdIsSecret and #pendingActivations > 0 then
                        -- Secret spellId: match against pending activations by timing.
                        -- Only safe when exactly one pending activation exists -
                        -- with multiple pending, we can't reliably determine which
                        -- cast produced this aura, so skip and fail-open (show spell).
                        -- Only matches helpful auras (harmful ones skipped above).
                        if #pendingActivations == 1 then
                            local pending = pendingActivations[1]
                            if now - pending.time <= PENDING_ACTIVATION_WINDOW then
                                resolvedSpellID = pending.spellID
                                table_remove(pendingActivations, 1)
                            end
                        end
                    end
                end
                
                if resolvedSpellID then
                    instanceToSpellMap[instanceID] = resolvedSpellID
                    combatRemovedSpellIDs[resolvedSpellID] = nil
                    
                    local dur = auraData.duration
                    local exp = auraData.expirationTime
                    local durIsSecret = BlizzardAPI.IsSecretValue(dur)
                    local expIsSecret = BlizzardAPI.IsSecretValue(exp)
                    if (durIsSecret or expIsSecret) and exemptReadable then
                        local d = ForceReadNumber(auraData, "duration")
                        local e = ForceReadNumber(auraData, "expirationTime")
                        if d and e then
                            dur, exp = d, e
                            durIsSecret, expIsSecret = false, false
                        end
                    end
                    if not durIsSecret and not expIsSecret and dur and exp then
                        instanceToTimingMap[instanceID] =
                            BuildAuraTiming(dur, exp, auraData.applications)
                    end
                    
                    -- Copy name/icon from previous mapping if we have them
                    local prevName = instanceToNameMap[instanceID]
                    if not prevName then
                        -- Try to get from spell info cache (non-secret out of combat)
                        local spellInfo = BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(resolvedSpellID)
                        if spellInfo and spellInfo.name and not BlizzardAPI.IsSecretValue(spellInfo.name) then
                            instanceToNameMap[instanceID] = spellInfo.name
                        end
                    end
                end
                if not nameIsSecret and auraData.name then
                    instanceToNameMap[instanceID] = auraData.name
                end
                if auraData.icon and not BlizzardAPI.IsSecretValue(auraData.icon) then
                    instanceToIconMap[instanceID] = auraData.icon
                end
            end
        end
    end
    
    -- updatedAuraInstanceIDs: auras that changed (e.g., stack count change)
    -- We don't need to do anything special here - the cache invalidation will
    -- cause RefreshAuraCache to re-read the current aura state on next access.
    -- The instance map entries remain valid (same instanceID = same aura).
end

-- Spell ID sets used by multiple functions below -- defined here so all
-- dependent functions can reference them regardless of declaration order.
-- Uses spell IDs instead of English name patterns for locale safety.

local PET_REVIVE_SPELL_IDS = {
    [982]   = true,  -- Revive Pet
    [55709] = true,  -- Heart of the Phoenix
}
local function IsPetReviveSpell(spellID)
    return PET_REVIVE_SPELL_IDS[spellID] ~= nil
end

local STEALTH_SPELL_IDS = {
    [1784]  = true,  -- Stealth (Rogue)
    [1856]  = true,  -- Vanish (Rogue)
    [5215]  = true,  -- Prowl (Druid)
    [58984] = true,  -- Shadowmeld (Night Elf)
}
local function IsStealthSpell(spellID)
    return STEALTH_SPELL_IDS[spellID] ~= nil
end

local function IsMountSpell(spellID)
    return C_MountJournal and C_MountJournal.GetMountFromSpell
        and C_MountJournal.GetMountFromSpell(spellID) ~= nil
end

-- Prune expired activations only when aura API is reliable; otherwise retain activations conservatively
-- Also checks non-aura detection methods (forms, stealth, pets) which work in combat
function RedundancyFilter.PruneExpiredActivations()
    if not next(inCombatActivations) then return end

    -- Hoist outside the loop: same result for every iteration
    local auraAPIAvailable = BlizzardAPI and BlizzardAPI.IsRedundancyFilterAvailable and BlizzardAPI.IsRedundancyFilterAvailable()

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
            if IsStealthSpell(spellID) and IsStealthed() then
                shouldKeep = true  -- Still stealthed
            end
        end

        -- Method 3: Pet detection (always works - not secret)
        if not shouldKeep and StaticLookup(PET_SUMMON_SPELLS, spellID) then
            if HasPetUI() then
                shouldKeep = true  -- Pet still exists
            end
        end

        -- Method 4: Mount detection (always works - not secret)
        if not shouldKeep then
            if IsMountSpell(spellID) and IsMounted() then
                shouldKeep = true  -- Still mounted
            end
        end
        
        -- Method 5: Aura API (only when accessible, not blocked by secrets)
        if not shouldKeep then
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
-- Also queues a pending activation so addedAuras can map the auraInstanceID
function RedundancyFilter.RecordSpellActivation(spellID)
    if not spellID then return end
    local now = GetTime()
    inCombatActivations[spellID] = now
    
    -- Queue for instance mapping: addedAuras will match by timing
    -- Only queue known aura spells to avoid noise from damage abilities
    if StaticLookup(UNIQUE_AURA_SPELLS, spellID) or StaticLookup(RAID_BUFF_SPELLS, spellID) then
        pendingActivations[#pendingActivations + 1] = { spellID = spellID, time = now }
    end
end

--------------------------------------------------------------------------------
-- Dynamic Aura Detection
--------------------------------------------------------------------------------

--- Prune expired entries from the trusted out-of-combat cache.
--- Throttled to once every EXPIRATION_CHECK_INTERVAL seconds.
--- Uses conservative 80% threshold for old caches, exact expiration for recent ones.
local function PruneTrustedCacheExpiration(now)
    if now < nextExpirationCheck then return end
    nextExpirationCheck = now + EXPIRATION_CHECK_INTERVAL

    local auraInfo = trustedOutOfCombatCache.auraInfo
    if not auraInfo then return end

    local cacheAge = now - lastTrustedCacheTime
    local useConservativeThreshold = cacheAge > TRUSTED_CACHE_RECENT_THRESHOLD

    for spellID, info in pairs(auraInfo) do
        local shouldInvalidate = false
        if useConservativeThreshold then
            if info.halfwayThreshold and now >= info.halfwayThreshold then
                shouldInvalidate = true
            end
        else
            if info.expirationTime and info.expirationTime > 0 and now >= info.expirationTime then
                shouldInvalidate = true
            end
        end
        if shouldInvalidate then
            trustedOutOfCombatCache.byID[spellID] = nil
            auraInfo[spellID] = nil
        end
    end
end

--- Merge trusted out-of-combat cache as fallback when in-combat aura resolution
--- has unresolved secrets. Skips spellIDs that were explicitly removed in combat,
--- and auras whose cached expiration shows they'll expire within the threshold.
local function MergeTrustedCacheFallback(now)
    for spellID, v in pairs(trustedOutOfCombatCache.byID) do
        if not cachedAuras.byID[spellID] and not combatRemovedSpellIDs[spellID] then
            local info = trustedOutOfCombatCache.auraInfo and trustedOutOfCombatCache.auraInfo[spellID]
            local skipExpiring = info
                and info.expirationTime and info.expirationTime > 0
                and info.duration and info.duration >= LONG_BUFF_DURATION_CUTOFF
                and (info.expirationTime - now) < RefreshWindow()
            if not skipExpiring then
                cachedAuras.byID[spellID] = v
            end
        end
    end
    for name, v in pairs(trustedOutOfCombatCache.byName or {}) do
        if not cachedAuras.byName[name] then
            local nameSpellID = (type(v) == "number") and v
            if not nameSpellID or not combatRemovedSpellIDs[nameSpellID] then
                cachedAuras.byName[name] = v
            end
        end
    end
    for spellID, info in pairs(trustedOutOfCombatCache.auraInfo or {}) do
        if not cachedAuras.auraInfo[spellID] and not combatRemovedSpellIDs[spellID] then
            cachedAuras.auraInfo[spellID] = info
        end
    end
end

-- Build cache of current player auras (by spellID, name, and icon)
-- Now also stores duration and expiration time for pandemic window checks
-- 12.0: Uses auraInstanceID mapping to resolve secret values in combat
RefreshAuraCache = function()
    local now = GetTime()
    local inCombat = UnitAffectingCombat("player")
    
    -- If in combat and we have a recent trusted out-of-combat cache, use it as FALLBACK
    -- The instance map resolution below may produce better results, but if it can't
    -- resolve everything, we still have trustedOutOfCombatCache as a safety net.
    -- CRITICAL: Only compare timestamps in combat - no arithmetic with cached values (may be secrets)
    if inCombat and trustedOutOfCombatCache.byID and (now - lastTrustedCacheTime) < TRUSTED_CACHE_DURATION then
        PruneTrustedCacheExpiration(now)
    end
    
    if cachedAuras.byID and (now - lastAuraCheck) < AURA_CACHE_DURATION then
        return cachedAuras
    end
    
    wipe(cachedAuras)
    cachedAuras.byID = {}
    cachedAuras.byName = {}
    cachedAuras.byIcon = {}
    cachedAuras.auraInfo = {}  -- Stores {duration, expirationTime, count} by spellID
    
    local unresolvedSecrets = 0  -- Track how many auras we couldn't resolve
    
    -- 12.0+ fast pre-check: skip the full aura scan when all fields are known secret.
    -- When true (combat), the loop below would just hit secret values on every aura,
    -- so we skip it entirely and rely on trustedOutOfCombatCache + instance maps.
    local aurasAreSecret = BlizzardAPI.AreAurasSecret()
    
    if aurasAreSecret then
        -- Populate from instance maps maintained by OnUnitAuraUpdate (addedAuras/removedAuraInstanceIDs).
        -- This avoids 40 pcall(GetAuraDataByIndex) calls that would all return secret fields.
        for instanceID, spellID in pairs(instanceToSpellMap) do
            cachedAuras.byID[spellID] = true
            local timing = instanceToTimingMap[instanceID]
            if timing then cachedAuras.auraInfo[spellID] = timing end
            local name = instanceToNameMap[instanceID]
            if name then cachedAuras.byName[name] = spellID end
            local icon = instanceToIconMap[instanceID]
            if icon then cachedAuras.byIcon[icon] = name or true end
        end
        -- Flag for trusted cache merge (covers auras not in instance maps)
        cachedAuras.hasSecrets = true
    -- Modern API (11.0+)
    elseif BlizzardAPI.GetAuras then
        -- One batch call instead of up to 40 index reads. The table and its length
        -- are plain even in combat; only the fields below are secret, so the
        -- per-aura secret handling is unchanged. GetAuras absorbs the throw risk
        -- (compound tokens, hotfixes) and falls back to the index loop itself.
        local playerAuras = BlizzardAPI.GetAuras("player", "HELPFUL") or {}
        for i = 1, #playerAuras do
            local auraData = playerAuras[i]

            -- auraInstanceID is NeverSecret in 12.0 - always readable
            local instanceID = auraData.auraInstanceID
            local spellIdIsSecret = BlizzardAPI.IsSecretValue(auraData.spellId)
            local nameIsSecret = BlizzardAPI.IsSecretValue(auraData.name)
            
            if spellIdIsSecret or nameIsSecret then
                -- 12.0 NeverSecret whitelist: Some auras are guaranteed non-secret
                -- even in combat. For these, pcall-access the fields directly -
                -- if readable, skip the instance-map resolution path entirely.
                -- This handles auras gained during combat that have no instance map entry.
                local whitelistResolved = false
                if spellIdIsSecret then
                    local realSpellId = ForceReadNumber(auraData, "spellId")
                    if realSpellId and IsNeverSecretAura(realSpellId) then
                        -- spellId was readable (NeverSecret) despite IsSecretValue
                        -- returning true. Process as a normal non-secret aura,
                        -- force-reading timing the same way (GetAuraTiming can't
                        -- serve this - it trusts the generic secret mark).
                        cachedAuras.byID[realSpellId] = true
                        local dur = ForceReadNumber(auraData, "duration")
                        local exp = ForceReadNumber(auraData, "expirationTime")
                        local timingInfo = BuildAuraTiming(dur, exp, auraData.applications)
                        cachedAuras.auraInfo[realSpellId] = timingInfo
                        if instanceID then
                            instanceToSpellMap[instanceID] = realSpellId
                            instanceToTimingMap[instanceID] = timingInfo
                        end
                        -- Try reading name/icon too (also NeverSecret for whitelisted)
                        local realName = ForceReadString(auraData, "name")
                        if realName then
                            cachedAuras.byName[realName] = realSpellId
                            if instanceID then instanceToNameMap[instanceID] = realName end
                        end
                        if auraData.icon then
                            cachedAuras.byIcon[auraData.icon] = realName or true
                            if instanceID then instanceToIconMap[instanceID] = auraData.icon end
                        end
                        whitelistResolved = true
                    end
                end

                if not whitelistResolved then
                -- 12.0 Instance Map Resolution: Use instanceID to look up known spellID
                local mappedSpellID = instanceID and instanceToSpellMap[instanceID]
                local mappedName = instanceID and instanceToNameMap[instanceID]
                local mappedIcon = instanceID and instanceToIconMap[instanceID]
                
                if mappedSpellID then
                    cachedAuras.byID[mappedSpellID] = true
                    -- Use pre-cached timing from instance map (timing values are secret in combat)
                    local mappedTiming = instanceToTimingMap[instanceID]
                    if mappedTiming then
                        cachedAuras.auraInfo[mappedSpellID] = mappedTiming
                    end
                    if mappedName then
                        cachedAuras.byName[mappedName] = mappedSpellID
                    end
                    if mappedIcon then
                        cachedAuras.byIcon[mappedIcon] = mappedName or true
                    end
                else
                    -- Instance ID not in our map (new aura gained during combat)
                    unresolvedSecrets = unresolvedSecrets + 1
                end
                end  -- not whitelistResolved
            else
                -- Not secret - process normally and update instance maps
                if auraData.spellId then
                    cachedAuras.byID[auraData.spellId] = true
                    -- Store aura timing info for pandemic check (use API-specific helper)
                    local dur, exp = BlizzardAPI.GetAuraTiming("player", i, "HELPFUL")
                    local timingInfo = BuildAuraTiming(dur, exp, auraData.applications)
                    cachedAuras.auraInfo[auraData.spellId] = timingInfo
                    
                    -- Update instance maps (always, so they're current for combat)
                    if instanceID then
                        instanceToSpellMap[instanceID] = auraData.spellId
                        instanceToTimingMap[instanceID] = timingInfo
                        if auraData.name then
                            instanceToNameMap[instanceID] = auraData.name
                        end
                        if auraData.icon then
                            instanceToIconMap[instanceID] = auraData.icon
                        end
                    end
                end
                if auraData.name then
                    cachedAuras.byName[auraData.name] = auraData.spellId or true
                end
                if auraData.icon then
                    cachedAuras.byIcon[auraData.icon] = auraData.name or true
                end
            end
        end
    -- Fallback for older clients (no instance ID support)
    elseif UnitAura then
        for i = 1, 40 do
            local ok, name, icon, count, _, duration, expirationTime, _, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok or not name then break end
            
            -- Best-effort: skip secret auras but continue processing others
            local spellIdIsSecret = BlizzardAPI.IsSecretValue(spellId)
            local nameIsSecret = BlizzardAPI.IsSecretValue(name)
            
            if spellIdIsSecret or nameIsSecret then
                unresolvedSecrets = unresolvedSecrets + 1
            else
                if spellId then
                    cachedAuras.byID[spellId] = true
                    local durIsSecret = BlizzardAPI.IsSecretValue(duration)
                    local expIsSecret = BlizzardAPI.IsSecretValue(expirationTime)
                    local dur = (not durIsSecret and duration) or 0
                    local exp = (not expIsSecret and expirationTime) or 0
                    cachedAuras.auraInfo[spellId] = BuildAuraTiming(dur, exp, count)
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
    
    -- Mark hasSecrets only when there are UNRESOLVED secrets
    -- If all secret auras were resolved via instance map, we have complete data
    if unresolvedSecrets > 0 then
        cachedAuras.hasSecrets = true
    end
    
    lastAuraCheck = now
    
    -- If out of combat and we got clean data (no secrets), save as trusted cache
    if not inCombat and not cachedAuras.hasSecrets then
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
                count = v.count,
                halfwayThreshold = v.halfwayThreshold  -- Pre-calculated threshold (safe for in-combat comparison)
            }
        end
        lastTrustedCacheTime = now
        
        -- Out of combat, we have authoritative data - prune stale entries.
        -- Only prune against a list we actually got: treating a failed enumeration
        -- as "nothing is active" would wipe every instance map wholesale.
        local liveAuras = BlizzardAPI.GetAuras and BlizzardAPI.GetAuras("player", "HELPFUL")
        if liveAuras then
            local activeInstances = {}
            for i = 1, #liveAuras do
                local instanceID = liveAuras[i].auraInstanceID
                if instanceID then activeInstances[instanceID] = true end
            end
            for instanceID in pairs(instanceToSpellMap) do
                if not activeInstances[instanceID] then
                    instanceToSpellMap[instanceID] = nil
                    instanceToNameMap[instanceID] = nil
                    instanceToIconMap[instanceID] = nil
                    instanceToTimingMap[instanceID] = nil
                end
            end
        end
    end
    
    -- In combat with unresolved secrets: merge trustedOutOfCombatCache as fallback
    if inCombat and cachedAuras.hasSecrets and trustedOutOfCombatCache.byID then
        MergeTrustedCacheFallback(GetTime())
    end
    
    return cachedAuras
end

-- Check if player has a buff by spell ID
local function HasBuffBySpellID(spellID)
    if not spellID then return false end
    
    if inCombatActivations[spellID] then return true end
    
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
    if not info then
        -- No timing info available. Two scenarios:
        -- 1) Buff is gone → allow recast (return true)
        -- 2) Buff exists via inCombatActivations but timing data is secret → just cast, full duration
        -- Check inCombatActivations to distinguish: if we KNOW it's active, don't allow refresh
        if inCombatActivations[spellID] then
            return false  -- Just cast in combat, assume full duration remaining
        end
        return true  -- No aura info and not tracked → allow
    end
    
    local duration = info.duration
    local expirationTime = info.expirationTime
    
    -- Auras with 0 duration are permanent/passive - don't consider them for refresh
    if duration <= 0 then return false end
    
    local now = GetTime()
    local remaining = expirationTime - now

    -- Allow refresh if remaining time is less than pandemic threshold
    local pandemicTime = duration * PANDEMIC_THRESHOLD

    -- For long-duration buffs (>= 10 min, e.g. poisons, Mark of the Wild) the pandemic
    -- fraction is the wrong shape entirely: 30% of a 60-minute buff is 18 minutes, so the
    -- recast would sit in the queue for most of an evening. Use the flat pre-combat window
    -- instead - what matters is whether the buff outlasts the pull, not what fraction is left.
    -- expirationTime is a plain Lua number cached out of combat - arithmetic is safe in combat.
    -- The auraInstanceID → timing mapping (instanceToTimingMap) carries this value into combat
    -- even when the aura API returns secret values for expirationTime directly.
    if duration >= LONG_BUFF_DURATION_CUTOFF then
        pandemicTime = RefreshWindow()
    end

    return remaining <= pandemicTime
end

-- Check if player has a buff by exact name. The name is a WEAKER key than the spell ID -
-- distinct spells share names, and a collision here suppresses an ability whose buff is not
-- actually up, which is the opposite of this module's fail-open direction. So it only answers
-- while the ID index is known INCOMPLETE (hasSecrets: aura fields came back secret and some
-- auras resolved to a name but not to an id - the one case where the name is the only
-- evidence there is). When the ID index is complete, its "no" is the answer and this must not
-- second-guess it. Nothing is lost on the live paths: both write byName alongside byID, so a
-- name-only entry can arise only in the legacy UnitAura branch, which 12.0 never reaches.
local function HasBuffByName(buffName)
    if not buffName then return false end
    local auras = RefreshAuraCache()
    if not auras.hasSecrets then return false end
    return auras.byName and auras.byName[buffName]
end

--------------------------------------------------------------------------------
-- Native Spell Classification Functions (12.0 Compliant)
--------------------------------------------------------------------------------

-- Check if spell applies an aura (using native tables + name pattern fallback)
-- Returns: isAura, isUniqueAura
local function IsAuraSpell(spellID)
    if not spellID then return false, false end
    
    -- Check our known unique aura table first (fast path)
    if StaticLookup(UNIQUE_AURA_SPELLS, spellID) then
        -- Client-data veto: an aura that stacks is never "unique already active"
        -- (guards the curated list against patch drift)
        if SpellDB and SpellDB.GetAuraMaxStacks and SpellDB.GetAuraMaxStacks(spellID) then
            return true, false
        end
        return true, true
    end
    
    -- Fallback: FormCache ID-based detection for unknown spells
    -- GetFormIDBySpellID returns non-nil for any known shapeshift form spell
    if FormCache and FormCache.GetFormIDBySpellID
            and FormCache.GetFormIDBySpellID(spellID) ~= nil then
        return true, true  -- Treat as unique personal aura
    end

    -- Curated defensive tier: a defensive carrying a sinkAura hint that points at ITS
    -- OWN id is an explicit statement that re-casting REPLACES the buff rather than
    -- adding to it (an absorb barrier throws away whatever shield was left). That is
    -- exactly the judgement this function needs and the one the client data cannot
    -- make: Ironfur stacks per application and carries no stack data, so it is only
    -- safe to suppress a defensive we have named by hand. Identity with the cast id is
    -- required because the redundancy check tests the buff under the CAST id - a hint
    -- pointing elsewhere (Shield Block -> 132404) would look up an aura that is not there.
    if SpellDB and SpellDB.GetDefensiveAuraHint then
        local hint = SpellDB.GetDefensiveAuraHint(spellID)
        if hint and hint.sinkAura == spellID then
            return true, true
        end
    end

    -- Client-data tier: spells whose every effect is a non-stacking self-applied
    -- aura are unique by construction (generated across all classes - covers
    -- curation gaps like Slice and Dice). Pandemic refresh still applies.
    -- Defensives/heals are excluded: their redundancy is curated deliberately,
    -- and application-stacking (Ironfur - each cast adds a stack the data
    -- can't see) must never be suppressed.
    if SpellDB and SpellDB.IsPureSelfAura and SpellDB.IsPureSelfAura(spellID)
        and not (SpellDB.IsDefensiveSpell and SpellDB.IsDefensiveSpell(spellID))
        and not (SpellDB.IsHealingSpell and SpellDB.IsHealingSpell(spellID)) then
        return true, true
    end

    return false, false
end

-- Check if spell is a pet-related ability (known pet-summon table only; the old
-- name-pattern fallback was removed, so unknown pet summons fail-open).
local function IsPetSpell(spellID)
    return StaticLookup(PET_SUMMON_SPELLS, spellID) ~= nil
end

--- True for one of the interchangeable pet summons. Public so the queue builder can enforce
--- that only one ever appears: they are alternatives, not a sequence, and per-spell redundancy
--- cannot see that - with no pet out, every summon you know is individually non-redundant,
--- which is how a Warlock ended up with Felguard, Imp and Felhunter queued at once.
--- Reads PET_SUMMON_EXCLUSIVE, NOT the broader PET_SUMMON_SPELLS: the latter includes Army of
--- the Dead, Feral Spirit and the elementals, which are cooldowns that belong in the queue
--- together. See the note on that table.
function RedundancyFilter.IsPetSummonSpell(spellID)
    if not spellID then return false end
    return StaticLookup(PET_SUMMON_EXCLUSIVE, spellID) ~= nil
end

-- Check if spell is DPS-relevant for rotation queue
-- When aura detection is blocked, only show spells that are clearly offensive/rotational
-- Uses name-based heuristics since we don't have LibPlayerSpells flags
local function IsDPSRelevant(spellID)
    if not spellID then return false end
    
    -- Known raid buffs: Always hide when can't check if active
    if StaticLookup(RAID_BUFF_SPELLS, spellID) then
        return false
    end
    
    -- Known pet summons: Hide when can't check if pet exists
    if StaticLookup(PET_SUMMON_SPELLS, spellID) then
        return false
    end
    
    -- Known unique auras (forms/stances): Hide when can't check if active
    if StaticLookup(UNIQUE_AURA_SPELLS, spellID) then
        return false
    end
    
    -- Form/stance spells not already in UNIQUE_AURA_SPELLS: check FormCache
    if FormCache and FormCache.GetFormIDBySpellID
            and FormCache.GetFormIDBySpellID(spellID) ~= nil then
        return false
    end

    -- Pet revive (ID-based)
    if IsPetReviveSpell(spellID) then
        return false
    end

    -- Default: Include in queue (fail-open for combat relevance)
    return true
end

--------------------------------------------------------------------------------
-- Pet Detection
--------------------------------------------------------------------------------

-- Check if pet is alive (exists AND not dead)
-- 12.0: UnitIsDead result may be secret for non-player units
local function IsPetAlive()
    if not UnitExists("pet") then return false end
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

--------------------------------------------------------------------------------
-- Spell Category Detection (dynamic, no hardcoded spell lists)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Rogue Poison Detection (cast-based inference)
-- Poisons are hour-long buffs; once observed via cast tracking assume active until combat ends
-- This avoids querying aura state which may return secret values
--------------------------------------------------------------------------------

-- Poison CAST spell IDs (what C_AssistedCombat recommends) are single-sourced from
-- SpellDB.ROGUE_POISON_CAST_IDS (captured at the top of this file; derived there
-- from CLASS_MAINTAINED_BUFFS.ROGUE). Tracked via UNIT_SPELLCAST_SUCCEEDED ->
-- inCombatActivations; hour-long buffs, safe to assume active once cast observed.

-- Poison AURA spell IDs (what appears in the player's buff list)
-- Source: 12.0 Midnight Exclusion Whitelist
-- Primary detection uses cast tracking (inCombatActivations) for reliability
local ROGUE_POISON_BUFF_IDS = {
    -- Lethal Poisons (aura IDs from whitelist)
    [2823] = true,   -- Deadly Poison
    [8679] = true,   -- Wound Poison
    [315584] = true, -- Instant Poison
    [381637] = true, -- Atrophic Poison
    -- Non-Lethal Poisons (aura IDs from whitelist)
    [3408] = true,   -- Crippling Poison
    [5761] = true,   -- Numbing Poison
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
    -- Also checks cached expirationTime: if less than the refresh window remains,
    -- don't count the poison as "active" - the player should reapply before or at combat start.
    -- expirationTime is a plain Lua number from the out-of-combat snapshot (or instanceToTimingMap),
    -- so the arithmetic is valid even when the aura API returns secret values in combat.
    if auras.byID then
        local now_poison = GetTime()
        for spellID in pairs(ROGUE_POISON_BUFF_IDS) do
            if auras.byID[spellID] then
                local auraInfo = auras.auraInfo and auras.auraInfo[spellID]
                local expiringSoon = auraInfo
                    and auraInfo.expirationTime and auraInfo.expirationTime > 0
                    and (auraInfo.expirationTime - now_poison) < RefreshWindow()
                if not expiringSoon then
                    local spellInfo = GetCachedSpellInfo(spellID)
                    local name = spellInfo and spellInfo.name
                    if name and not foundNames[name] then
                        count = count + 1
                        foundNames[name] = true
                    end
                else
                    -- Still record the name so FALLBACK 2 doesn't re-count this expiring poison
                    local spellInfo = GetCachedSpellInfo(spellID)
                    if spellInfo and spellInfo.name then
                        foundNames[spellInfo.name] = true
                    end
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

-- Shaman weapon imbue cast IDs (1 hour duration) are single-sourced from
-- SpellDB.WEAPON_ENCHANT_SPELLS (captured at the top of this file).

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

-- Returns redundant, reason. The reason (a constant string, diagnostics only -
-- /jac why prints it) rides as a second return; hot-path callers truncate it
-- for free, matching BlizzardAPI.IsSpellReady's pattern.
function RedundancyFilter.IsSpellRedundant(spellID, profile, isDefensiveCheck)
    if not spellID then return false end

    -- 0. ALREADY OFFERED OUT OF COMBAT. The defensive bar shows missing pre-combat buffs as
    -- clickable icons; listing the same ability in the offensive queue beside them is the
    -- same suggestion twice, and only one of the two can be clicked. The defensive copy wins,
    -- so this queue drops its own. Never applied to the defensive check itself (isDefensiveCheck)
    -- - that is the copy we are keeping.
    if not isDefensiveCheck then
        local PE = GetPrecombatEngine()
        if PE and PE.IsOfferedNow and PE.IsOfferedNow(spellID, profile) then
            return true, "already offered as a pre-combat buff on the defensive bar"
        end
    end

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
                return true, "already in that form/stance"
            end
        else
            -- Fallback: spell not in FormCache mapping - compare localized spell name
            -- directly against the active form name (both strings are from the game,
            -- so this comparison is locale-safe regardless of client language).
            local spellInfo = GetCachedSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                local name = spellInfo.name
                local currentFormName = FormCache.GetActiveFormName()
                if currentFormName and currentFormName == name then
                    local now = GetTime()
                    local throttleKey = "form_name_" .. name
                    if debugMode and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > 5) then
                        lastPrintTime[throttleKey] = now
                        print("|cff66ccffJAC|r |cffff6666REDUNDANT|r: " .. name .. " - already active (name match)")
                    end
                    return true, "already in that form (name match)"
                end
            end
        end
    end
    
    -- 2. MAINTENANCE BUFF COMBAT SUPPRESSION
    -- Long-duration maintenance buffs (poisons, imbues, raid buffs, rites) should never
    -- take priority over DPS mid-combat. Filter them out - they can wait until combat ends.
    -- Covers aura IDs (NEVER_SECRET_AURA_SPELLS) and cast IDs (poison/imbue cast tables).
    if UnitAffectingCombat("player") then
        if StaticLookup(NEVER_SECRET_AURA_SPELLS, spellID) or IsRoguePoisonSpell(spellID) or IsWeaponEnchantSpell(spellID) then
            return true, "maintenance buff suppressed during combat (re-offered after combat)"
        end
    end

    -- NOTE: Cooldown filtering moved to SpellQueue.IsSpellUsable() which uses a 2s threshold
    -- Position 1 doesn't get usability filtering (shows what Blizzard recommends)
    -- Positions 2+ get filtered by SpellQueue before reaching RedundancyFilter
    
    -- Check if we have incomplete aura data (unresolved secrets after instance map resolution)
    -- Instance maps make the raw auraAPIBlocked check redundant - hasSecrets is the
    -- authoritative indicator of whether our aura cache is complete
    local auras = RefreshAuraCache()
    local auraDataIncomplete = auras and auras.hasSecrets
    
    -- If cache has UNRESOLVED secrets, filter non-DPS spells as safety measure
    -- EXCEPTION 1: Defensive checks bypass this filter (heals are not "DPS-relevant" but are valid defensives)
    -- EXCEPTION 2: If we have no trusted cache (logged in during combat), fail-open to avoid hiding valid spells
    -- EXCEPTION 3: Skip if we have definitive knowledge about this spell's state:
    --   - cachedAuras.byID[spellID]: resolved present via instance map → let unique aura check handle it
    --   - combatRemovedSpellIDs[spellID]: explicitly removed during combat → let unique aura check handle it
    -- IMPORTANT: Continue to remaining checks (pet/stealth/mount/etc) even when aura data incomplete
    if auraDataIncomplete then
        -- Skip non-DPS gate if we know this specific spell's state (present or removed)
        local spellStateKnown = (auras.byID and auras.byID[spellID]) or combatRemovedSpellIDs[spellID]
        
        if not spellStateKnown then
            -- Check if we have any trusted pre-combat data to validate against
            local hasTrustedData = trustedOutOfCombatCache.byID and next(trustedOutOfCombatCache.byID)
            
            -- Only filter non-DPS spells if we have trusted data OR are doing defensive checks
            -- If no trusted data and not defensive, fail-open (allow spell through) to avoid false negatives
            if not isDefensiveCheck and not IsDPSRelevant(spellID) then
                if hasTrustedData then
                    -- Have pre-combat snapshot - safe to filter non-DPS spells
                    local now = GetTime()
                    local throttleKey = "nondps_" .. spellID
                    if GetDebugMode() and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > 5) then
                        lastPrintTime[throttleKey] = now
                        local reason = "unresolved secrets in cache"
                        local spellInfo = GetCachedSpellInfo(spellID)
                        local spellName = spellInfo and spellInfo.name or "Unknown"
                        print("|cff66ccffJAC|r |cffff6666FILTERED|r: " .. spellName .. " (ID: " .. spellID .. ") - Non-DPS spell (" .. reason .. ", have trusted cache)")
                    end
                    return true, "aura data partly secret; non-rotational spell hidden as a safety measure"
                else
                    -- No trusted cache - fail-open for safety (avoid hiding valid spells)
                    if GetDebugMode() then
                        local spellInfo = GetCachedSpellInfo(spellID)
                        local spellName = spellInfo and spellInfo.name or "Unknown"
                        print("|cff66ccffJAC|r |cffffff00ALLOWED|r: " .. spellName .. " (ID: " .. spellID .. ") - No trusted cache, fail-open")
                    end
                end
            end
        end
        -- Fall through for both defensive checks AND DPS-relevant spells
        -- Continue to pet/stealth/mount checks even when aura checks are blocked
    end
    
    local spellInfo = GetCachedSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then return false end
    
    local spellName = spellInfo.name
    local isKnownAuraSpell, isUniqueAura = IsAuraSpell(spellID)

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
                        DebugPrintThrottled("pandemic_" .. spellID, "|cff66ccffJAC|r |cff00ff00ALLOWED|r: " .. spellName .. " - unique aura in pandemic window, refresh allowed")
                    end
                    return false  -- Allow the cast
                end

                if debugMode then
                    DebugPrintThrottled("aura_" .. spellID, "|cff66ccffJAC|r |cffff6666REDUNDANT|r: " .. spellName .. " - unique aura already active (not in pandemic window)")
                end
                return true, "its buff is already active (reappears in the pandemic refresh window)"
            end
        else
            -- Non-unique aura spells: trust Assisted Combat
            -- These may stack, refresh for damage, or have other valid reasons
            if debugMode and (HasBuffBySpellID(spellID) or HasBuffByName(spellName)) then
                DebugPrintThrottled("nonunique_" .. spellID, "|cff66ccffJAC|r |cff00ff00ALLOWED|r: " .. spellName .. " - non-unique aura, may stack or have refresh benefit")
            end
        end
    end
    
    -- 4. PET SPELL REDUNDANCY
    -- Revive Pet: redundant if pet is ALIVE (can't revive alive pet)
    -- Summon Pet: redundant if pet EXISTS (alive or dead - already have a pet)
    if IsPetReviveSpell(spellID) then
        -- Revive is redundant only if pet is alive
        if IsPetAlive() then
            if debugMode then
                DebugPrintThrottled("petrez_" .. spellID, "|cff66ccffJAC|r |cffff6666REDUNDANT|r: Revive Pet but pet is alive")
            end
            return true, "pet is alive"
        end
    else
        -- Pet summon spells: redundant if any pet exists
        if IsPetSpell(spellID) and HasPetUI() then
            if debugMode then
                DebugPrintThrottled("petsummon_" .. spellID, "|cff66ccffJAC|r |cffff6666REDUNDANT|r: Pet summon but pet already exists")
            end
            return true, "pet already exists"
        end
    end
    
    -- 5. STEALTH REDUNDANCY
    -- Use IsStealthed() API - more reliable than buff checking
    if IsStealthSpell(spellID) then
        if IsStealthed() then
            if debugMode then
                DebugPrintThrottled("stealth_" .. spellID, "|cff66ccffJAC|r |cffff6666REDUNDANT|r: Stealth spell but already stealthed")
            end
            return true, "already stealthed"
        end
    end
    
    -- 6. MOUNT REDUNDANCY
    -- Use IsMounted() API
    if IsMounted() then
        -- Check if this is a mount spell (avoid false positives)
        if IsMountSpell(spellID) then
            if debugMode then
                DebugPrintThrottled("mount_" .. spellID, "|cff66ccffJAC|r |cffff6666REDUNDANT|r: Mount spell but already mounted")
            end
            return true, "already mounted"
        end
    end
    
    -- 7. ROGUE POISON REDUNDANCY
    -- Out of combat: Rogues can have max 2 poisons active (1 lethal + 1 non-lethal)
    -- If both slots are filled, all poison suggestions are redundant
    -- (In-combat suppression handled by step 2 above)
    if IsRoguePoisonSpell(spellID) then
        local activePoisons = CountActivePoisonBuffs()
        if activePoisons >= 2 then
            return true, "both poison slots already active"
        end
    end
    
    -- 8. WEAPON ENCHANT REDUNDANCY (Shaman Imbues)
    -- Out of combat: if weapon already has active enchant with sufficient time, skip it
    -- (In-combat suppression handled by step 2 above)
    if IsWeaponEnchantSpell(spellID) then
        if HasActiveWeaponEnchant() then
            if debugMode then
                DebugPrintThrottled("enchant_" .. spellID, "|cff66ccffJAC|r |cffff6666REDUNDANT|r: " .. spellName .. " - weapon enchant already active with time remaining")
            end
            return true, "weapon enchant already active with time remaining"
        else
            if debugMode then
                DebugPrintThrottled("enchantok_" .. spellID, "|cff66ccffJAC|r |cff00ff00ALLOWED|r: " .. spellName .. " - weapon enchant needed (missing or expiring)")
            end
        end
    end
    
    return false
end

--------------------------------------------------------------------------------
-- Aura Query API
--------------------------------------------------------------------------------

--- Returns true if ANY spellID in the given set is active as a player aura.
--- Efficient single-pass scan for checking multiple trigger auras at once.
function RedundancyFilter.IsAnyAuraActive(spellIDSet)
    if not spellIDSet then return false end
    for _, mapSpellID in pairs(instanceToSpellMap) do
        if spellIDSet[mapSpellID] then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Debug / Diagnostic Functions
--------------------------------------------------------------------------------



-- Expose aura cache for diagnostics
function RedundancyFilter.GetAuraCache()
    return RefreshAuraCache()
end