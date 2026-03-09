-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Info, Usability, Rotation API, Item Detection, Availability
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after SecretValues.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-SpellQuery", 1
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime    = GetTime
local pcall      = pcall
local type       = type
local wipe       = wipe
local ipairs     = ipairs
local math_min   = math.min
local IsSpellKnown  = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell
local C_SpellBook_IsSpellInSpellBook    = C_SpellBook and C_SpellBook.IsSpellInSpellBook
local C_Spell_IsSpellPassive            = C_Spell and C_Spell.IsSpellPassive
local C_Spell_GetSpellInfo              = C_Spell and C_Spell.GetSpellInfo
local C_Spell_GetSpellCooldown          = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges           = C_Spell and C_Spell.GetSpellCharges
local C_Spell_IsSpellUsable             = C_Spell and C_Spell.IsSpellUsable
local C_Spell_GetOverrideSpell          = C_Spell and C_Spell.GetOverrideSpell
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local Enum_SpellBookSpellBank_Player    = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local FindSpellOverrideByID             = FindSpellOverrideByID
local GetInventoryItemID                = GetInventoryItemID ---@diagnostic disable-line: undefined-global
local GetItemSpell                      = GetItemSpell
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

local SpellDB = LibStub("JustAC-SpellDB", true)

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

-- checkForVisibleButton: true=visible only, false=include hidden (macro conditionals)
function BlizzardAPI.GetNextCastSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return nil end

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
    if override and override ~= 0 and override ~= spellID then
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
        if overrideID and overrideID ~= 0 and overrideID ~= spellID then
            return overrideID
        end
    end
    return spellID
end

function BlizzardAPI.IsOffensiveSpell(spellID)
    if not spellID then return true end
    if not SpellDB then return true end
    return SpellDB.IsOffensiveSpell(spellID)
end

function BlizzardAPI.IsDefensiveSpell(spellID)
    if not spellID then return false end
    if not SpellDB then return false end
    return SpellDB.IsDefensiveSpell(spellID) or SpellDB.IsHealingSpell(spellID)
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
-- and RotationSpellsUpdated via ClearAvailabilityCache(). No timer needed — spell
-- availability only changes on talent/spec/spell-grant events.
function BlizzardAPI.IsSpellAvailable(spellID)
    if not spellID or spellID == 0 then return false end

    local cached = spellAvailabilityCache[spellID]
    if cached ~= nil then
        return cached
    end

    if C_SpellBook_IsSpellInSpellBook then
        if C_SpellBook_IsSpellInSpellBook(spellID, Enum_SpellBookSpellBank_Player) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end

    if IsSpellKnown then
        if IsSpellKnown(spellID) then
            spellAvailabilityCache[spellID] = true
            return true
        end
        if IsSpellKnown(spellID, true) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end

    if C_Spell_IsSpellPassive then
        local isPassive = C_Spell_IsSpellPassive(spellID)
        if isPassive then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end

    if IsPlayerSpell and IsPlayerSpell(spellID) then
        spellAvailabilityCache[spellID] = true
        return true
    end

    spellAvailabilityCache[spellID] = false
    return false
end
