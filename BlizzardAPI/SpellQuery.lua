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
local C_Spell_IsSpellPassive            = C_Spell and C_Spell.IsSpellPassive
local C_Spell_GetSpellInfo              = C_Spell and C_Spell.GetSpellInfo
local C_Spell_GetSpellCooldown          = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_IsSpellUsable             = C_Spell and C_Spell.IsSpellUsable
local C_Spell_GetOverrideSpell          = C_Spell and C_Spell.GetOverrideSpell
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local GetInventoryItemID                = GetInventoryItemID ---@diagnostic disable-line: undefined-global
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
-- Two sources, because they disagree: the SPELL's own passive flag, and the SPELLBOOK
-- ENTRY's. A talent can turn a castable button passive without touching the spell (Ret's
-- Crusading Strikes: Crusader Strike 35395 still reads known, usable and non-passive, while
-- its spellbook entry says Passive and the button cannot be pressed). Memoized; wiped with
-- the availability cache on talent/spec/spellbook changes, since the book half can flip.
local passiveMemo = {}
local function IsPassiveID(spellID)
    local v = passiveMemo[spellID]
    if v ~= nil then return v end
    v = false
    if C_Spell_IsSpellPassive then
        local ok, isPassive = pcall(C_Spell_IsSpellPassive, spellID)
        v = (ok and isPassive) and true or false
    end
    if not v and C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.GetSpellBookItemInfo then
        local ok, slot, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID)
        if ok and slot then
            local okI, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot,
                bank or (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0)
            if okI and type(info) == "table" and info.isPassive == true then v = true end
        end
    end
    passiveMemo[spellID] = v
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
        -- EXCEPT the assist's own wait placeholders ("Waiting for Energy" and kin):
        -- they are passive-flagged in DB2 but are the engine's DELIBERATE display
        -- state, and the renderer has first-class handling for them (isWaitingSpell,
        -- WAIT label). Filtering them silently killed the wait icon and let the
        -- ranked tail shift up into the AC slot (regression, user-reported on Feral:
        -- base Moonfire wearing the primary glow while Blizzard's button showed the
        -- watch). Detected by the shared timer icon 134377 - the same locale-safe
        -- check the renderer uses; file ids are identical across locales.
        if IsPassiveID(result) and not BlizzardAPI.IsWaitPlaceholder(result) then
            return nil
        end
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

-- Blizzard's rotation list can omit core abilities (field report: the Devourer list is five
-- spells, with no Voidblade). Part of what SimC ordering means: append every SimC ability the addon can time by itself
-- (RotationImport.GetInsertable) that the character knows. Everything downstream - cooldown
-- and usability filters, SimC ranking and gates - treats them like any other pool spell.
-- The ids the last WithAdditions pass ADDED to the game's pool: abilities the game itself
-- never recommends (its live list omits them). Safe Lead evidence class 1 reads this.
local insertedIDs = {}
function BlizzardAPI.IsInsertedSpell(spellID)
    return spellID ~= nil and insertedIDs[spellID] == true
end

local function WithAdditions(list)
    wipe(insertedIDs)
    local profile = BlizzardAPI.GetProfile()
    if not profile or (profile.contextOrder or "simc") ~= "simc" then
        return list
    end
    local RI = LibStub("JustAC-RotationImport", true)
    local simc = RI and RI.GetInsertable and RI.GetInsertable()
    if not simc then return list end
    local SpellDB = LibStub("JustAC-SpellDB", true)

    -- Same BUTTON, not same id: the SimC data and Blizzard's list can name one ability
    -- by different ids across an override chain.
    local have = {}
    for i = 1, #list do
        have[list[i]] = true
        have[BlizzardAPI.ResolveSpellID(list[i]) or list[i]] = true
    end
    local out
    for i = 1, #simc do
        local raw = simc[i]
        local id = BlizzardAPI.ResolveKnownSpellID(raw)
        if id and not have[id] and not have[raw]
           and not (SpellDB and SpellDB.IsOffensiveSpell and not SpellDB.IsOffensiveSpell(id)) then
            if not out then
                out = {}
                for j = 1, #list do out[j] = list[j] end   -- never grow Blizzard's own table
            end
            out[#out + 1] = id
            insertedIDs[id] = true
            have[id], have[raw] = true, true
        end
    end
    return out or list
end

--- The engine's own "wait" answer: a passive-flagged spell wearing the shared timer
--- icon. It is a DELIBERATE display state, not a real recommendation, and it is the
--- second shape a wait arrives in - the first being no answer at all. Three places
--- tested the icon id by hand; the id is locale-safe but the test is worth naming.
function BlizzardAPI.IsWaitPlaceholder(spellID)
    if not spellID then return false end
    local info = BlizzardAPI.GetCachedSpellInfo(spellID)
    return (info and info.iconID == 134377) or false
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
            return WithAdditions(filtered)
        end
        return WithAdditions(result)
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

    -- Auto-expire BEFORE the cache read, or a hit never expires on its own and
    -- render-path callers (no per-build ClearProcCache) read frozen verdicts.
    local now = GetTime()
    if now - procCacheTime > PROC_CACHE_DURATION then
        wipe(procResultCache)
        procCacheTime = now
    end
    local cached = procResultCache[spellID]
    if cached ~= nil then
        return cached
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
    -- <= 0 covers items (negative by our convention) and the queue's wait sentinel:
    -- neither has an override, and the C call's behavior on such ids is not something
    -- we guess at (project rule). Identity is the correct answer for both.
    if not spellID or spellID <= 0 then return spellID end
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

--- The talent/transform override for a spell, or spellID itself. One resolver: this used
--- to be a second copy over FindSpellOverrideByID, documented as "distinct from
--- GetDisplaySpellID" - measured 2026-09-21 across a Druid's whole spellbook, in and out
--- of form, the two APIs never disagreed (0 of 111). Same passive refusal, one cache.
BlizzardAPI.ResolveSpellID = BlizzardAPI.GetDisplaySpellID

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
            local _, spellID
            if C_Item_GetItemSpell then _, spellID = C_Item_GetItemSpell(itemID) end
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
    wipe(passiveMemo)   -- the spellbook half of IsPassiveID moves with talents
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
    if IsPassiveID(spellID) then
        spellAvailabilityCache[spellID] = false
        return false
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

    -- (No spellbook fallback: IsSpellInSpellBook also answers true for unselected
    -- choice-node talents, and the two authoritative checks above have already
    -- said no, so its only possible verdict here was "false".)
    spellAvailabilityCache[spellID] = false
    return false
end
