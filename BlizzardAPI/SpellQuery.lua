-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Info, Usability, Rotation API, Item Detection, Availability
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after SecretValues.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-SpellQuery", 2
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime    = GetTime
local pcall      = pcall
local type       = type
local wipe       = wipe
local ipairs     = ipairs
local IsSpellKnown  = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell
local C_SpellBook_IsSpellInSpellBook    = C_SpellBook and C_SpellBook.IsSpellInSpellBook
local C_Spell_IsSpellPassive            = C_Spell and C_Spell.IsSpellPassive
local C_Spell_GetSpellInfo              = C_Spell and C_Spell.GetSpellInfo
local C_Spell_GetSpellCooldown          = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_IsSpellUsable             = C_Spell and C_Spell.IsSpellUsable
local C_Spell_GetOverrideSpell          = C_Spell and C_Spell.GetOverrideSpell
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local Enum_SpellBookSpellBank_Player    = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local FindSpellOverrideByID             = FindSpellOverrideByID
local GetInventoryItemID                = GetInventoryItemID ---@diagnostic disable-line: undefined-global
local GetItemSpell                      = GetItemSpell
local IsSecretValue = BlizzardAPI.IsSecretValue

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

local cachedDebugMode = false

function BlizzardAPI.GetDebugMode()
    return cachedDebugMode
end

-- Event-only invalidation: called from Options/Core.lua on toggle,
-- RefreshConfig() on profile change, and InitializeCaches() on login.
function BlizzardAPI.RefreshDebugMode()
    local profile = BlizzardAPI.GetProfile()
    cachedDebugMode = profile and profile.debugMode or false
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

-- Passive filter for ids arriving from Blizzard's assist APIs. Their data can hand
-- back a passive (observed live: a passive talent's id as the "next cast" on a
-- Priest) - the id is real, just not castable, so showing it draws a suggestion
-- nothing can press. IsSpellAvailable already refuses passives for OUR lists; these
-- two ingest points returned Blizzard's ids verbatim, bypassing it. Memoized:
-- passive-ness is static spell data, and the demand probe runs per queue build.
local passiveMemo = {}
local function IsPassiveID(spellID)
    if not C_Spell_IsSpellPassive then return false end
    local v = passiveMemo[spellID]
    if v == nil then
        local ok, isPassive = pcall(C_Spell_IsSpellPassive, spellID)
        v = (ok and isPassive) and true or false
        passiveMemo[spellID] = v
    end
    return v
end
-- Exported for gates that deliberately can't use IsSpellAvailable (its castability
-- half wrongly rejects form-gated spells) but still need its passive refusal.
BlizzardAPI.IsPassiveSpell = IsPassiveID

-- checkForVisibleButton: true=visible only, false=include hidden (macro conditionals)
local function QueryNextCastSpell(checkForVisibleButton)
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return nil end
    local success, result = pcall(C_AssistedCombat.GetNextCastSpell, checkForVisibleButton)
    if success and result and type(result) == "number" and result > 0 then
        -- nil, not the passive: "no demand" lets every caller's fallback chain run,
        -- where a passive id would freeze slot 1 / the demand hold on a dead entry.
        if IsPassiveID(result) then return nil end
        return result
    end
    return nil
end

function BlizzardAPI.GetNextCastSpell()
    local profile = BlizzardAPI.GetProfile()
    local includeHidden = profile and profile.includeHiddenAbilities or false
    return QueryNextCastSpell(not includeHidden)
end

--- Highlight-mode lookahead: always calls GetNextCastSpell(true) so the engine
--- skips spells that have no visible action bar button. When a blacklisted spell
--- is hidden from bars (removed or behind a modifier macro), this returns the
--- next spell Blizzard would highlight instead.
function BlizzardAPI.GetHighlightCastSpell()
    return QueryNextCastSpell(true)
end

--- Demand probe: the opposite of the highlight lookahead - always includes spells
--- with NO visible action-bar button. The pre-combat engine reads the assisted
--- rotation's current maintained-buff demand through this: poisons and shields
--- rarely sit on anyone's bars, so the visible-only variants never surface them.
function BlizzardAPI.GetAnyNextCastSpell()
    return QueryNextCastSpell(false)
end

function BlizzardAPI.GetRotationSpells()
    if not C_AssistedCombat or not C_AssistedCombat.GetRotationSpells then return nil end

    local success, result = pcall(C_AssistedCombat.GetRotationSpells)
    if success and result and type(result) == "table" and #result > 0 then
        local hasPassive = false
        for i = 1, #result do
            if type(result[i]) ~= "number" or result[i] <= 0 then
                return nil
            end
            if IsPassiveID(result[i]) then hasPassive = true end
        end
        -- Same filter as the demand probe. Copy only on a hit: the common case
        -- (no passives) returns Blizzard's table untouched.
        if hasPassive then
            local filtered = {}
            for i = 1, #result do
                if not IsPassiveID(result[i]) then filtered[#filtered + 1] = result[i] end
            end
            if #filtered == 0 then return nil end
            return filtered
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

-- Raw values (may be secret); Cooldown widget handles them
function BlizzardAPI.GetSpellCooldown(spellID)
    if not C_Spell_GetSpellCooldown then return 0, 0 end
    local cd = C_Spell_GetSpellCooldown(spellID)
    if cd then
        return cd.startTime, cd.duration
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
            if IsSecretValue(startTime) or IsSecretValue(duration) then
                return 0, 0
            end
            return startTime or 0, duration or 0
        end
    end
    return 0, 0
end

-- True only when spellID is idle except for the shared GCD (off-GCD spells like most
-- interrupts return false). Used to grey a reminder that's momentarily unavailable
-- purely because a GCD is ticking. isOnGCD is NeverSecret, so this is safe in combat.
function BlizzardAPI.IsSpellOnGCD(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return false end
    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return false end
    return cd.isOnGCD == true
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
                local actionUsable, actionNotEnoughMana = BlizzardAPI.GetActionBarUsability(spellID)
                if actionUsable ~= nil then
                    return actionUsable or false, actionNotEnoughMana or false
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
    -- Never resolve INTO a passive: the client's override data can map a castable onto
    -- a passive talent's id (the id is real; it is just not a button). Every consumer
    -- of this function wants "the id to DISPLAY/cast", so a passive override is always
    -- wrong - keep the castable input id instead.
    if override and override ~= 0 and override ~= spellID and not IsPassiveID(override) then
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
        -- Same passive refusal as GetDisplaySpellID above; this is the hop every
        -- defensive/precombat entry takes on its way to an icon (user-confirmed live:
        -- the topoff heal's Renew resolved to a passive Priest talent and rendered it).
        if overrideID and overrideID ~= 0 and overrideID ~= spellID
           and not IsPassiveID(overrideID) then
            return overrideID
        end
    end
    return spellID
end

--- Resolve a possibly-stale stored spellID to a form the player actually knows:
--- the ID itself, its current talent override, or its base spell - in that
--- order. Returns knownID, source ("stored"|"override"|"base"), or nil when no
--- known form exists. Cold paths only (list-cache rebuilds, diagnostics) - the
--- resolution chain pcalls C APIs.
function BlizzardAPI.ResolveKnownSpellID(spellID)
    if not spellID or spellID <= 0 then return nil end
    if BlizzardAPI.IsSpellAvailable(spellID) then return spellID, "stored" end
    local override = BlizzardAPI.ResolveSpellID(spellID)
    if override and override ~= spellID and BlizzardAPI.IsSpellAvailable(override) then
        return override, "override"
    end
    local base = BlizzardAPI.ResolveBaseSpellID and BlizzardAPI.ResolveBaseSpellID(spellID)
    if base and base ~= spellID and BlizzardAPI.IsSpellAvailable(base) then
        return base, "base"
    end
    return nil
end

--- Mark each spell ID and its talent-resolved variant into a set. Used by the
--- gap-closer engine to suppress its spells from the rotation list (its own
--- insertion controls when they appear).
function BlizzardAPI.MarkResolvedIDs(spellList, spellIDSet)
    if not spellList or not spellIDSet then return end
    for _, spellID in ipairs(spellList) do
        if spellID and spellID > 0 then
            spellIDSet[spellID] = true
            local resolvedID = BlizzardAPI.ResolveSpellID(spellID)
            if resolvedID ~= spellID then
                spellIDSet[resolvedID] = true
            end
        end
    end
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
local itemSpellCacheBuilt = false

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
    itemSpellCacheBuilt = true
end

-- Event-only invalidation: rebuilt on PLAYER_EQUIPMENT_CHANGED and
-- once at login (delayed by InitializeCaches to cover cold item cache).
function BlizzardAPI.IsItemSpell(spellID)
    if not spellID or spellID == 0 then return false end

    if not itemSpellCacheBuilt then
        RebuildItemSpellCache()
    end

    return itemSpellCache[spellID] ~= nil
end

function BlizzardAPI.RefreshItemSpellCache()
    RebuildItemSpellCache()
end

local spellAvailabilityCache = {}

function BlizzardAPI.ClearAvailabilityCache()
    wipe(spellAvailabilityCache)
end

-- Event-only invalidation: cleared by SPELLS_CHANGED, PLAYER_SPECIALIZATION_CHANGED,
-- and RotationSpellsUpdated via ClearAvailabilityCache(). No timer needed - spell
-- availability only changes on talent/spec/spell-grant events.
function BlizzardAPI.IsSpellAvailable(spellID)
    if not spellID or spellID == 0 then return false end

    local cached = spellAvailabilityCache[spellID]
    if cached ~= nil then
        return cached
    end

    -- Passives are never suggestible: they cannot be cast, they own no action-bar
    -- slot (so any glow or hotkey drawn for one is anchored to nothing), and both
    -- authoritative checks below answer TRUE for a passive you know. This must
    -- therefore run BEFORE them - it used to sit at the bottom, where it could
    -- only ever confirm a false the function was already returning.
    if C_Spell_IsSpellPassive then
        local ok, isPassive = pcall(C_Spell_IsSpellPassive, spellID)
        if ok and isPassive then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end

    -- Authoritative checks first: IsSpellKnown/IsPlayerSpell are definitive
    -- for active spells and correctly exclude unselected choice-node talents.
    if IsSpellKnown then
        if IsSpellKnown(spellID) or IsSpellKnown(spellID, true) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end

    if IsPlayerSpell and IsPlayerSpell(spellID) then
        spellAvailabilityCache[spellID] = true
        return true
    end

    -- Spellbook fallback: catches edge cases (e.g. racial abilities) but includes
    -- unselected choice-node talents. Cross-check with IsSpellKnown to filter those.
    if C_SpellBook_IsSpellInSpellBook then
        if C_SpellBook_IsSpellInSpellBook(spellID, Enum_SpellBookSpellBank_Player) then
            -- Choice-node guard: spellbook returns true for all options in a
            -- talent choice row, even unselected ones. If IsSpellKnown explicitly
            -- returned false above, this is an unselected talent - reject it.
            if IsSpellKnown and not IsSpellKnown(spellID) and not IsPlayerSpell(spellID) then
                spellAvailabilityCache[spellID] = false
                return false
            end
            spellAvailabilityCache[spellID] = true
            return true
        end
    end

    spellAvailabilityCache[spellID] = false
    return false
end
