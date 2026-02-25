-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- DefensiveEngine.lua — Defensive spell system: health-based queue, proc detection, potions
-- Extracted from JustAC.lua for modularity.

local MAJOR, MINOR = "JustAC-DefensiveEngine", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Hot path cache
local GetTime = GetTime
local UnitClass = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local GetSpecialization = GetSpecialization
local GetActionInfo = GetActionInfo
local IsStealthed = IsStealthed
local GetItemCount = GetItemCount
local GetItemCooldown = GetItemCooldown
local GetItemInfo = GetItemInfo
local GetItemSpell = GetItemSpell
local GetSpellDescription = GetSpellDescription
local FindSpellOverrideByID = FindSpellOverrideByID
local IsActionInRange = IsActionInRange
local C_Spell = C_Spell
local wipe = wipe
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local string_format = string.format
local math_min = math.min

-- Module references (resolved at load time — DefensiveEngine loads after all deps in TOC)
local BlizzardAPI       = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner  = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue        = LibStub("JustAC-SpellQueue", true)
local SpellDB           = LibStub("JustAC-SpellDB", true)
local UIRenderer        = LibStub("JustAC-UIRenderer", true)
local UIHealthBar       = LibStub("JustAC-UIHealthBar", true)
local UINameplateOverlay = LibStub("JustAC-UINameplateOverlay", true)

--------------------------------------------------------------------------------
-- Pooled tables — avoid GC pressure on hot paths
--------------------------------------------------------------------------------

local lastHealthUpdate = 0
local HEALTH_UPDATE_THROTTLE = 0.1  -- 100ms minimum between defensive queue updates
local dpsQueueExclusions = {}
local defensiveAlreadyAdded = {}
-- Pooled tables for GetUsableDefensiveSpells (avoids per-call allocations)
local usableResults = {}
local usableAddedHere = {}

-- Forward declarations for functions referenced before definition
local AppendUsableSpells

-- Resolve a talent override for a spell: FindSpellOverrideByID(34428) returns 202168 when
-- Impending Victory is talented, so we use the active replacement instead of the base spell.
-- Returns the original ID when no override exists.
local function ResolveSpellID(spellID)
    if FindSpellOverrideByID then
        local overrideID = FindSpellOverrideByID(spellID)
        if overrideID and overrideID ~= 0 and overrideID ~= spellID then
            return overrideID
        end
    end
    return spellID
end

-- Healing potion cache
local HEALTHSTONE_ITEM_ID = 5512
local cachedPotionID = nil
local cachedPotionSlot = nil
local potionCacheValid = false

--------------------------------------------------------------------------------
-- Spell list access
--------------------------------------------------------------------------------

-- Returns the spell list for a given type ("selfHealSpells", "cooldownSpells", "petHealSpells")
-- for the current player class from the per-class nested structure.
function lib.GetClassSpellList(addon, listKey)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return nil end

    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end

    local classSpells = profile.defensives.classSpells
    if not classSpells or not classSpells[playerClass] then return nil end

    return classSpells[playerClass][listKey]
end

-- Migrate pre-3.25 flat spell lists (selfHealSpells/cooldownSpells/petHealSpells)
-- into the new per-class classSpells structure. Safe to call multiple times.
function lib.MigrateDefensiveSpellsToClassSpells(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    local def = profile.defensives
    local hasFlatData = (def.selfHealSpells and #def.selfHealSpells > 0)
        or (def.cooldownSpells and #def.cooldownSpells > 0)
        or (def.petHealSpells and #def.petHealSpells > 0)

    if not hasFlatData then return end

    -- Ensure classSpells table exists
    if not def.classSpells then def.classSpells = {} end

    -- Only migrate if this class doesn't already have nested data
    if not def.classSpells[playerClass] then
        def.classSpells[playerClass] = {}
    end
    local cs = def.classSpells[playerClass]

    -- Move flat lists into per-class structure (don't overwrite existing)
    if def.selfHealSpells and #def.selfHealSpells > 0 and (not cs.selfHealSpells or #cs.selfHealSpells == 0) then
        cs.selfHealSpells = {}
        for i, spellID in ipairs(def.selfHealSpells) do
            cs.selfHealSpells[i] = spellID
        end
    end

    if def.cooldownSpells and #def.cooldownSpells > 0 and (not cs.cooldownSpells or #cs.cooldownSpells == 0) then
        cs.cooldownSpells = {}
        for i, spellID in ipairs(def.cooldownSpells) do
            cs.cooldownSpells[i] = spellID
        end
    end

    if def.petHealSpells and #def.petHealSpells > 0 and (not cs.petHealSpells or #cs.petHealSpells == 0) then
        cs.petHealSpells = {}
        for i, spellID in ipairs(def.petHealSpells) do
            cs.petHealSpells[i] = spellID
        end
    end

    -- Clear flat keys so migration won't re-trigger
    def.selfHealSpells = nil
    def.cooldownSpells = nil
    def.petHealSpells = nil

    addon:DebugPrint("Migrated flat defensive spells to classSpells[" .. playerClass .. "]")
end

--------------------------------------------------------------------------------
-- Initialization & registration
--------------------------------------------------------------------------------

function lib.InitializeDefensiveSpells(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    -- Migrate legacy flat lists on first load
    lib.MigrateDefensiveSpellsToClassSpells(addon)

    -- Ensure classSpells table structure exists
    local def = profile.defensives
    if not def.classSpells then def.classSpells = {} end
    if not def.classSpells[playerClass] then def.classSpells[playerClass] = {} end
    local cs = def.classSpells[playerClass]

    if not cs.selfHealSpells or #cs.selfHealSpells == 0 then
        local healDefaults = SpellDB and SpellDB.CLASS_SELFHEAL_DEFAULTS and SpellDB.CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            cs.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                cs.selfHealSpells[i] = spellID
            end
        end
    end

    if not cs.cooldownSpells or #cs.cooldownSpells == 0 then
        local cdDefaults = SpellDB and SpellDB.CLASS_COOLDOWN_DEFAULTS and SpellDB.CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            cs.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                cs.cooldownSpells[i] = spellID
            end
        end
    end

    if not cs.petHealSpells or #cs.petHealSpells == 0 then
        local petDefaults = SpellDB and SpellDB.CLASS_PETHEAL_DEFAULTS and SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            cs.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                cs.petHealSpells[i] = spellID
            end
        end
    end

    if not cs.petRezSpells or #cs.petRezSpells == 0 then
        local rezDefaults = SpellDB and SpellDB.CLASS_PET_REZ_DEFAULTS and SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass]
        if rezDefaults then
            cs.petRezSpells = {}
            for i, spellID in ipairs(rezDefaults) do
                cs.petRezSpells[i] = spellID
            end
        end
    end

    lib.RegisterDefensivesForTracking(addon)
end

--- Populate gap-closer defaults into the profile if the current spec's list is empty.
--- Mirrors the defensive auto-population pattern so the Options panel shows entries
--- without requiring the user to click "Restore Class Defaults".
function lib.InitializeGapClosers(addon)
    local profile = addon:GetProfile()
    if not profile then return end

    if not profile.gapClosers then
        profile.gapClosers = { enabled = true, classSpells = {} }
    end
    if not profile.gapClosers.classSpells then
        profile.gapClosers.classSpells = {}
    end

    local specKey = lib.GetGapCloserSpecKey()
    if not specKey then return end

    if not profile.gapClosers.classSpells[specKey] or #profile.gapClosers.classSpells[specKey] == 0 then
        local defaults = SpellDB and SpellDB.CLASS_GAPCLOSER_DEFAULTS and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
        if defaults then
            profile.gapClosers.classSpells[specKey] = {}
            for i, spellID in ipairs(defaults) do
                profile.gapClosers.classSpells[specKey][i] = spellID
            end
            lib.InvalidateGapCloserCache()
        end
    end
end

-- Enables 12.0 compatibility when C_Spell.GetSpellCooldown returns secrets
function lib.RegisterDefensivesForTracking(addon)
    if not BlizzardAPI or not BlizzardAPI.RegisterDefensiveSpell then return end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    if BlizzardAPI.ClearTrackedDefensives then
        BlizzardAPI.ClearTrackedDefensives()
    end

    -- Table-driven iteration: register all defensive spell lists
    local spellListTypes = { "selfHealSpells", "cooldownSpells", "petHealSpells", "petRezSpells" }
    for _, listType in ipairs(spellListTypes) do
        local spellList = lib.GetClassSpellList(addon, listType)
        if spellList then
            for _, entry in ipairs(spellList) do
                -- Only register positive entries (spells) — negative entries are items
                if entry and entry > 0 then
                    BlizzardAPI.RegisterDefensiveSpell(entry)
                end
            end
        end
    end
end

function lib.RestoreDefensiveDefaults(addon, listType)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    -- Ensure classSpells structure exists
    if not profile.defensives.classSpells then profile.defensives.classSpells = {} end
    if not profile.defensives.classSpells[playerClass] then profile.defensives.classSpells[playerClass] = {} end
    local cs = profile.defensives.classSpells[playerClass]

    if listType == "selfheal" then
        local healDefaults = SpellDB and SpellDB.CLASS_SELFHEAL_DEFAULTS and SpellDB.CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            cs.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                cs.selfHealSpells[i] = spellID
            end
        end
    elseif listType == "cooldown" then
        local cdDefaults = SpellDB and SpellDB.CLASS_COOLDOWN_DEFAULTS and SpellDB.CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            cs.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                cs.cooldownSpells[i] = spellID
            end
        end
    elseif listType == "petheal" then
        local petDefaults = SpellDB and SpellDB.CLASS_PETHEAL_DEFAULTS and SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            cs.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                cs.petHealSpells[i] = spellID
            end
        end
    elseif listType == "petrez" then
        local rezDefaults = SpellDB and SpellDB.CLASS_PET_REZ_DEFAULTS and SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass]
        if rezDefaults then
            cs.petRezSpells = {}
            for i, spellID in ipairs(rezDefaults) do
                cs.petRezSpells[i] = spellID
            end
        end
    end

    lib.RegisterDefensivesForTracking(addon)
    lib.OnHealthChanged(addon, nil, "player")
end

--------------------------------------------------------------------------------
-- Health change handler — main defensive queue dispatch
--------------------------------------------------------------------------------

function lib.OnHealthChanged(addon, event, unit)
    if addon.isDisabledMode then return end
    if unit ~= "player" and unit ~= "pet" then return end

    local profile = addon:GetProfile()
    local def = profile and profile.defensives

    -- Resolve overlay state once (UINameplateOverlay may not be loaded)
    local npo = UINameplateOverlay and (profile and profile.nameplateOverlay)
    local overlayDM = profile and profile.displayMode or "queue"
    local overlayActive = npo and (overlayDM == "overlay" or overlayDM == "both")

    -- When main panel defensives are off, hide any icons that may be visible from a
    -- previous enabled state.  Must happen before the early exits below because if
    -- showHealthBar is also off, needsAnyWork is false and the normal else-branch that
    -- hides icons is never reached.
    if def and not def.enabled then
        if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
            UIRenderer.HideDefensiveIcons(addon)
        elseif addon.defensiveIcon and UIRenderer and UIRenderer.HideDefensiveIcon then
            UIRenderer.HideDefensiveIcon(addon.defensiveIcon)
        end
    end

    -- Early exit: nothing at all to do for health events
    local needsAnyWork = (def and (def.enabled or def.showHealthBar or def.showPetHealthBar))
        or (overlayActive and (npo.showHealthBar or npo.showDefensives))
    if not needsAnyWork then return end

    -- Health bars are cheap; update them without throttling
    if def then
        if def.showHealthBar and UIHealthBar and UIHealthBar.Update then UIHealthBar.Update(addon) end
        if def.showPetHealthBar and UIHealthBar and UIHealthBar.UpdatePet then UIHealthBar.UpdatePet(addon) end
    end
    if overlayActive and npo.showHealthBar then
        UINameplateOverlay.UpdateHealthBar()
        UINameplateOverlay.UpdatePetHealthBar()
    end

    -- Throttle defensive queue updates (expensive: table allocations, spell lookups)
    local now = GetTime()
    if event and now - lastHealthUpdate < HEALTH_UPDATE_THROTTLE then return end
    lastHealthUpdate = now

    -- Skip queue work if neither path needs it
    local needsDefensives = (def and def.enabled) or (overlayActive and npo.showDefensives)
    if not needsDefensives then return end

    -- Health state — computed once, shared by main panel and overlay paths
    local inCombat = UnitAffectingCombat("player")

    -- Falls back to LowHealthFrame when UnitHealth() returns secrets
    local healthPercent, isEstimated = nil, false
    if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
        healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
    end

    local selfHealThreshold = def and def.selfHealThreshold or 80
    local cooldownThreshold = def and def.cooldownThreshold or 60

    -- 12.0: UnitHealth() is secret in combat (PvE and PvP). When isEstimated=true,
    -- thresholds above are ignored — we use Blizzard's LowHealthFrame binary states:
    --   "low"  = ~35% health → shows self-heals
    --   "critical" = ~20% health → shows major cooldowns
    -- Thresholds only matter out of combat (between pulls, open world, etc.)
    local isCritical, isLow
    if isEstimated then
        local lowState, critState = false, false
        if BlizzardAPI.GetLowHealthState then
            lowState, critState = BlizzardAPI.GetLowHealthState()
        end
        isCritical = critState
        isLow = lowState
    elseif healthPercent then
        isLow = healthPercent <= selfHealThreshold
        isCritical = healthPercent <= cooldownThreshold
    else
        isCritical = false
        isLow = false
    end

    -- 12.0: UnitHealth("pet") is secret in combat → GetPetHealthPercent() returns nil.
    -- Pet heals only trigger out of combat (between pulls, open world). This is by design.
    local petHealthPercent = BlizzardAPI and BlizzardAPI.GetPetHealthPercent and BlizzardAPI.GetPetHealthPercent()
    local petHealThreshold = def and def.petHealThreshold or 50
    local petNeedsHeal = petHealthPercent and petHealthPercent <= petHealThreshold

    -- UnitIsDead/UnitExists are NOT secret — pet rez/summon works reliably in combat
    local petStatus = BlizzardAPI and BlizzardAPI.GetPetStatus and BlizzardAPI.GetPetStatus()
    local petNeedsRez = (petStatus == "dead" or petStatus == "missing")

    -- DPS exclusions shared by both paths (reuse pooled table)
    wipe(dpsQueueExclusions)
    if SpellQueue and SpellQueue.GetCurrentSpellQueue then
        local dpsQueue = SpellQueue.GetCurrentSpellQueue()
        local maxDpsIcons = profile.maxIcons or 4
        for i = 1, math_min(#dpsQueue, maxDpsIcons) do
            if dpsQueue[i] then dpsQueueExclusions[dpsQueue[i]] = true end
        end
    end

    -- Main panel defensive queue (gated by defensives.enabled)
    if def and def.enabled then
        local defensiveQueue = lib.GetDefensiveSpellQueue(addon, isLow, isCritical, inCombat, dpsQueueExclusions)
        local maxIcons = def.maxIcons or 1

        -- Pet rez/summon: HIGH priority — pet dead or missing (reliable in combat)
        -- Uses defensiveAlreadyAdded from GetDefensiveSpellQueue to avoid duplicates
        if petNeedsRez and #defensiveQueue < maxIcons then
            AppendUsableSpells(addon, defensiveQueue, lib.GetClassSpellList(addon, "petRezSpells"), maxIcons, defensiveAlreadyAdded)
        end

        -- Pet heals: LOWER priority — out-of-combat only (health is secret in combat)
        if petNeedsHeal and not petNeedsRez and #defensiveQueue < maxIcons then
            AppendUsableSpells(addon, defensiveQueue, lib.GetClassSpellList(addon, "petHealSpells"), maxIcons, defensiveAlreadyAdded)
        end

        if #defensiveQueue > 0 then
            if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.ShowDefensiveIcons then
                UIRenderer.ShowDefensiveIcons(addon, defensiveQueue)
            elseif addon.defensiveIcon and UIRenderer and UIRenderer.ShowDefensiveIcon then
                UIRenderer.ShowDefensiveIcon(addon, defensiveQueue[1].spellID, defensiveQueue[1].isItem, addon.defensiveIcon)
            end
            -- Scale health bars to match visible defensive icon count
            if UIHealthBar and UIHealthBar.ResizeToCount then UIHealthBar.ResizeToCount(addon, #defensiveQueue) end
            if UIHealthBar and UIHealthBar.ResizePetToCount then UIHealthBar.ResizePetToCount(addon, #defensiveQueue) end
        else
            if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
                UIRenderer.HideDefensiveIcons(addon)
            elseif addon.defensiveIcon and UIRenderer and UIRenderer.HideDefensiveIcon then
                UIRenderer.HideDefensiveIcon(addon.defensiveIcon)
            end
            -- No defensive icons visible; collapse health bars
            if UIHealthBar and UIHealthBar.ResizeToCount then UIHealthBar.ResizeToCount(addon, 0) end
            if UIHealthBar and UIHealthBar.ResizePetToCount then UIHealthBar.ResizePetToCount(addon, 0) end
        end
    else
        -- Defensives disabled on main panel: ensure icons are hidden
        if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
            UIRenderer.HideDefensiveIcons(addon)
        elseif addon.defensiveIcon and UIRenderer and UIRenderer.HideDefensiveIcon then
            UIRenderer.HideDefensiveIcon(addon.defensiveIcon)
        end
        -- Collapse health bars when defensives disabled
        if UIHealthBar and UIHealthBar.ResizeToCount then UIHealthBar.ResizeToCount(addon, 0) end
        if UIHealthBar and UIHealthBar.ResizePetToCount then UIHealthBar.ResizePetToCount(addon, 0) end
    end

    -- Nameplate overlay defensive queue — independent of defensives.enabled.
    -- Uses its own display mode and icon count settings. GetDefensiveSpellQueue wipes
    -- defensiveAlreadyAdded at the start of each call, so no bleed from the main panel path.
    if overlayActive and npo.showDefensives then
        local npoDisplayMode = npo.defensiveDisplayMode or "combatOnly"
        local npoMaxIcons    = npo.maxDefensiveIcons or 1
        local npoQueue = lib.GetDefensiveSpellQueue(addon, isLow, isCritical, inCombat, dpsQueueExclusions, npoDisplayMode, npoMaxIcons, true)
        if #npoQueue > 0 then
            UINameplateOverlay.RenderDefensives(addon, npoQueue)
        else
            UINameplateOverlay.HideDefensiveIcons()
        end
    end
end

--------------------------------------------------------------------------------
-- Proc detection
--------------------------------------------------------------------------------

-- Returns any procced defensive spell (Victory Rush, etc.) at ANY health level
function lib.GetProccedDefensiveSpell(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return nil end

    -- Check if proc detection is enabled
    if profile.defensives.showProcs == false then return nil end

    -- Check ActionBarScanner for procced defensive spells
    if ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs and #defensiveProcs > 0 then
            for _, spellID in ipairs(defensiveProcs) do
                if spellID and spellID > 0 then
                    local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
                    if isUsable and isProcced then
                        return spellID
                    end
                end
            end
        end
    end

    local selfHealSpells = lib.GetClassSpellList(addon, "selfHealSpells")
    local cooldownSpells = lib.GetClassSpellList(addon, "cooldownSpells")
    for pass = 1, 2 do
        local spellList = pass == 1 and selfHealSpells or cooldownSpells
        if spellList then
            for _, entry in ipairs(spellList) do
                -- Items (negative entries) can't proc, skip them
                if entry and entry > 0 then
                    local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(entry, profile)
                    if isUsable and isProcced then
                        return entry
                    end
                end
            end
        end
    end

    return nil
end

-- First usable spell from list, prioritizing procs (Victory Rush, free heal procs)
function lib.GetBestDefensiveSpell(addon, spellList)
    if not spellList then return nil end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return nil end

    local debugMode = profile.debugMode
    if debugMode then
        addon:DebugPrint("GetBestDefensiveSpell called with " .. #spellList .. " spells in list")
    end

    -- Procced spells from spellbook take priority (free/instant)
    if profile.defensives.showProcs ~= false and ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs then
            for _, spellID in ipairs(defensiveProcs) do
                if spellID and spellID > 0 then
                    local isUsable = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
                    if isUsable then
                        return spellID
                    end
                end
            end
        end
    end

    for i, entry in ipairs(spellList) do
        if entry and entry > 0 then
            local isUsable, isKnown, isRedundant, onCooldown, isProcced = BlizzardAPI.CheckDefensiveSpellState(entry, profile)

            if debugMode then
                local spellInfo = C_Spell.GetSpellInfo(entry)
                local name = spellInfo and spellInfo.name or "Unknown"
                addon:DebugPrint(string_format("Checking defensive spell %d/%d: %s (%d)", i, #spellList, name, entry))

                if not isKnown then
                    addon:DebugPrint(string_format("  SKIP: %s - not known/available", name))
                elseif isRedundant then
                    addon:DebugPrint(string_format("  SKIP: %s - redundant (buff active)", name))
                elseif onCooldown then
                    local start, duration = BlizzardAPI.GetSpellCooldownValues(entry)
                    addon:DebugPrint(string_format("  SKIP: %s - on cooldown (start=%s, duration=%s)",
                        name, tostring(start or 0), tostring(duration or 0)))
                else
                    local start, duration = BlizzardAPI.GetSpellCooldownValues(entry)
                    addon:DebugPrint(string_format("  PASS: %s - onCooldown=false, start=%s, duration=%s",
                        name, tostring(start or 0), tostring(duration or 0)))
                end
            end

            if isUsable then
                return entry
            end
        elseif entry and entry < 0 then
            -- Negative entry = item ID
            local itemID = -entry
            local isUsable = BlizzardAPI.CheckDefensiveItemState(itemID, profile)

            if debugMode then
                local itemName = GetItemInfo(itemID) or "Unknown Item"
                addon:DebugPrint(string_format("Checking defensive item %d/%d: %s (item:%d)", i, #spellList, itemName, itemID))
                if isUsable then
                    addon:DebugPrint(string_format("  PASS: %s - usable", itemName))
                else
                    addon:DebugPrint(string_format("  SKIP: %s - not usable", itemName))
                end
            end

            if isUsable then
                return itemID, true  -- return itemID, isItem=true
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Spell queue building
--------------------------------------------------------------------------------

-- Returns up to maxCount usable spells/items, prioritizing procs
-- Uses module-level pooled tables (usableResults/usableAddedHere) to avoid per-call allocations
-- IMPORTANT: Caller must consume results before next call (table is reused)
-- List entries: positive = spell ID, negative = item ID (-itemID)
function lib.GetUsableDefensiveSpells(addon, spellList, maxCount, alreadyAdded)
    wipe(usableResults)
    if not spellList or maxCount <= 0 then return usableResults end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return usableResults end

    alreadyAdded = alreadyAdded or {}
    wipe(usableAddedHere)

    -- First pass: add procced spells (higher priority) - items can't proc
    for _, entry in ipairs(spellList) do
        if #usableResults >= maxCount then break end
        if entry and entry > 0 then
            local resolvedID = ResolveSpellID(entry)
            -- Check both the original and resolved IDs to handle proc injection cross-dedup
            if not alreadyAdded[entry] and not alreadyAdded[resolvedID] and not usableAddedHere[resolvedID] then
                local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(resolvedID, profile)
                if isUsable and isProcced then
                    usableResults[#usableResults + 1] = {spellID = resolvedID, isItem = false, isProcced = true}
                    usableAddedHere[resolvedID] = true
                    usableAddedHere[entry] = true  -- also mark original so it isn't reprocessed
                end
            end
        end
    end

    -- Second pass: add non-procced usable spells AND usable items
    local itemsEnabled = profile.defensives and profile.defensives.allowItems
    for _, entry in ipairs(spellList) do
        if #usableResults >= maxCount then break end
        if entry and entry > 0 then
            local resolvedID = ResolveSpellID(entry)
            if not alreadyAdded[entry] and not alreadyAdded[resolvedID] and not usableAddedHere[resolvedID] then
                -- Positive entry = spell
                local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(resolvedID, profile)
                if isUsable then
                    usableResults[#usableResults + 1] = {spellID = resolvedID, isItem = false, isProcced = isProcced}
                    usableAddedHere[resolvedID] = true
                    usableAddedHere[entry] = true  -- also mark original so it isn't reprocessed
                end
            end
        elseif itemsEnabled and entry and entry < 0 and not alreadyAdded[entry] and not alreadyAdded[-entry] and not usableAddedHere[entry] then
            -- Negative entry = item (stored as -itemID)
            local itemID = -entry
            local isUsable = BlizzardAPI.CheckDefensiveItemState(itemID, profile)
            if isUsable then
                usableResults[#usableResults + 1] = {spellID = itemID, isItem = true, isProcced = false}
                usableAddedHere[entry] = true
                -- Also mark the positive itemID to prevent FindHealingPotionOnActionBar duplicates
                usableAddedHere[itemID] = true
            end
        end
    end

    return usableResults
end

-- Append usable defensive spells from a spell list into a results table with dedup tracking.
-- If procsOnly is true, only entries with isProcced=true are appended.
-- Callers MUST consume results before next GetUsableDefensiveSpells call (pooled table).
AppendUsableSpells = function(addon, results, spellList, maxIcons, alreadyAdded, procsOnly)
    if #results >= maxIcons then return end
    local spells = lib.GetUsableDefensiveSpells(addon, spellList, maxIcons - #results, alreadyAdded)
    for _, entry in ipairs(spells) do
        if not procsOnly or entry.isProcced then
            results[#results + 1] = entry
            alreadyAdded[entry.spellID] = true
        end
    end
end

-- Display order: instant procs first, then by health threshold (higher priority first)
function lib.GetDefensiveSpellQueue(addon, passedIsLow, passedIsCritical, passedInCombat, passedExclusions, overrideDisplayMode, overrideMaxIcons, overrideShowProcs)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return {} end

    local maxIcons = overrideMaxIcons or profile.defensives.maxIcons or 1
    local showProcs = (overrideShowProcs ~= nil) and overrideShowProcs or (profile.defensives.showProcs ~= false)
    local results = {}
    -- Reuse pooled table for tracking added spells
    wipe(defensiveAlreadyAdded)
    local alreadyAdded = defensiveAlreadyAdded

    if passedExclusions then
        for spellID, _ in pairs(passedExclusions) do
            alreadyAdded[spellID] = true
        end
    end

    local isLow, isCritical, inCombat
    if passedIsLow ~= nil then
        isLow = passedIsLow
        isCritical = passedIsCritical or false
        inCombat = passedInCombat or UnitAffectingCombat("player")
    else
        local healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
        inCombat = UnitAffectingCombat("player")
        if isEstimated then
            local lowState, critState = false, false
            if BlizzardAPI.GetLowHealthState then
                lowState, critState = BlizzardAPI.GetLowHealthState()
            end
            isLow = lowState
            isCritical = critState
        else
            local selfHealThreshold = profile.defensives.selfHealThreshold or 80
            local cooldownThreshold = profile.defensives.cooldownThreshold or 60
            isLow = healthPercent <= selfHealThreshold
            isCritical = healthPercent <= cooldownThreshold
        end
    end

    local displayMode = overrideDisplayMode or profile.defensives.displayMode
    if not displayMode then
        local showOnlyInCombat = profile.defensives.showOnlyInCombat
        local alwaysShow = profile.defensives.alwaysShowDefensive
        if alwaysShow and showOnlyInCombat then
            displayMode = "combatOnly"
        elseif alwaysShow then
            displayMode = "always"
        else
            displayMode = "healthBased"
        end
    end

    -- Procced spells shown at ANY health level
    if showProcs and ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs then
            for _, spellID in ipairs(defensiveProcs) do
                if #results >= maxIcons then break end
                if spellID and spellID > 0 then
                    -- Resolve talent override so proc and list entries share the same tracking key
                    -- (e.g. Victory Rush proc 34428 → Impending Victory 202168)
                    local resolvedID = ResolveSpellID(spellID)
                    if not alreadyAdded[spellID] and not alreadyAdded[resolvedID] then
                        local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(resolvedID, profile)
                        if isUsable and isProcced then
                            results[#results + 1] = {spellID = resolvedID, isItem = false, isProcced = true}
                            alreadyAdded[resolvedID] = true
                            alreadyAdded[spellID] = true  -- also mark original ID
                        end
                    end
                end
            end
        end
    end

    -- Resolve per-class spell lists once for this update cycle
    local selfHealSpells = lib.GetClassSpellList(addon, "selfHealSpells")
    local cooldownSpells = lib.GetClassSpellList(addon, "cooldownSpells")

    -- Procced spells from configured lists (any health level)
    AppendUsableSpells(addon, results, selfHealSpells, maxIcons, alreadyAdded, true)
    AppendUsableSpells(addon, results, cooldownSpells, maxIcons, alreadyAdded, true)

    if displayMode == "combatOnly" and not inCombat then
        return results
    end

    local showAllAvailable = (displayMode == "always") or (displayMode == "combatOnly" and inCombat)
    if showAllAvailable and not isLow and not isCritical then
        AppendUsableSpells(addon, results, selfHealSpells, maxIcons, alreadyAdded)
        AppendUsableSpells(addon, results, cooldownSpells, maxIcons, alreadyAdded)
        return results
    end

    if isCritical then
        AppendUsableSpells(addon, results, cooldownSpells, maxIcons, alreadyAdded)
        AppendUsableSpells(addon, results, selfHealSpells, maxIcons, alreadyAdded)
        if #results < maxIcons and profile.defensives.autoInsertPotions ~= false then
            local potionID = lib.FindHealingPotionOnActionBar(addon)
            if potionID and not alreadyAdded[potionID] then
                results[#results + 1] = {spellID = potionID, isItem = true, isProcced = false}
                alreadyAdded[potionID] = true
            end
        end
    elseif isLow then
        AppendUsableSpells(addon, results, selfHealSpells, maxIcons, alreadyAdded)
        AppendUsableSpells(addon, results, cooldownSpells, maxIcons, alreadyAdded)
    end

    return results
end

--------------------------------------------------------------------------------
-- Healing potion subsystem
--------------------------------------------------------------------------------

function lib.InvalidatePotionCache()
    potionCacheValid = false
end

local function IsHealingConsumable(itemID)
    if not itemID then return false end
    if itemID == HEALTHSTONE_ITEM_ID then return true end

    local _, _, _, _, _, _, classID, subclassID = GetItemInfo(itemID)
    if not classID or classID ~= 0 or subclassID ~= 1 then
        return false
    end

    local spellName, spellID = GetItemSpell(itemID)
    if not spellName then return false end

    local lowerName = spellName:lower()
    if lowerName:find("heal") or lowerName:find("restore") or lowerName:find("life") then
        return true
    end

    if spellID then
        local desc = GetSpellDescription(spellID)
        if desc then
            local lowerDesc = desc:lower()
            if lowerDesc:find("restore") and lowerDesc:find("health") then
                return true
            end
            if lowerDesc:find("heal") then
                return true
            end
        end
    end

    return false
end

-- Returns itemID, actionSlot for first usable healing consumable (Healthstone prioritized)
-- Uses cached result from last action bar scan; call InvalidatePotionCache() on bar/bag changes
function lib.FindHealingPotionOnActionBar(addon)
    if potionCacheValid then
        -- Still check cooldown/count on cached result (these change in combat)
        if cachedPotionID then
            local count = GetItemCount(cachedPotionID) or 0
            if count > 0 then
                local start, duration = GetItemCooldown(cachedPotionID)
                local onCooldown = false
                if start and duration then
                    local startIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(start)
                    local durIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(duration)
                    if not startIsSecret and not durIsSecret then
                        onCooldown = start > 0 and duration > 1.5
                    end
                end
                if not onCooldown then
                    return cachedPotionID, cachedPotionSlot
                end
            end
        end
        return nil, nil
    end

    -- Full 180-slot scan (expensive, only on cache miss)
    local bestPotion = nil
    local bestSlot = nil

    for slot = 1, 180 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then
            local count = GetItemCount(id) or 0
            if count > 0 then
                local start, duration = GetItemCooldown(id)
                -- Fail-open: if values are secret or nil, assume NOT on cooldown (show item)
                local onCooldown = false
                if start and duration then
                    local startIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(start)
                    local durIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(duration)
                    if not startIsSecret and not durIsSecret then
                        onCooldown = start > 0 and duration > 1.5
                    end
                    -- If secret, onCooldown stays false (fail-open: show the item)
                end

                if not onCooldown then
                    if id == HEALTHSTONE_ITEM_ID then
                        cachedPotionID = id
                        cachedPotionSlot = slot
                        potionCacheValid = true
                        return id, slot
                    end

                    if not bestPotion and IsHealingConsumable(id) then
                        bestPotion = id
                        bestSlot = slot
                    end
                end
            end
        end
    end

    cachedPotionID = bestPotion
    cachedPotionSlot = bestSlot
    potionCacheValid = true
    return bestPotion, bestSlot
end

--------------------------------------------------------------------------------
-- Cooldown polling
--------------------------------------------------------------------------------

function lib.UpdateDefensiveCooldowns(addon)
    if addon.isDisabledMode then return end
    if not addon.db or not addon.db.profile or addon.db.profile.isManualMode then return end

    -- Update cooldowns on all visible main-panel defensive icons (requires defensives.enabled)
    local def = addon.db.profile.defensives
    if def and def.enabled then
        if addon.defensiveIcons and #addon.defensiveIcons > 0 then
            for _, icon in ipairs(addon.defensiveIcons) do
                if icon and icon:IsShown() then
                    UIRenderer.UpdateButtonCooldowns(icon)
                end
            end
        elseif addon.defensiveIcon and addon.defensiveIcon:IsShown() then
            UIRenderer.UpdateButtonCooldowns(addon.defensiveIcon)
        end
    end

    -- Update cooldowns on nameplate overlay defensive icons.
    -- These are only rendered on UNIT_HEALTH events (which are suppressed in combat when
    -- health is a secret value), so their cooldowns would freeze without this explicit poll.
    if addon.nameplateDefIcons and #addon.nameplateDefIcons > 0 then
        for _, icon in ipairs(addon.nameplateDefIcons) do
            if icon and icon:IsShown() then
                UIRenderer.UpdateButtonCooldowns(icon)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Gap-Closer System
-- Suggests a gap-closer spell (Charge, Shadowstep, etc.) when the target is out
-- of melee range.  Triggered by ACTION_RANGE_CHECK_UPDATE (NeverSecret event).
-- The spell is injected into the spell queue at position 2 — position 1 is always
-- Blizzard's single-button assistant suggestion and is never replaced.
--------------------------------------------------------------------------------

-- Debounce: prevent icon flickering when standing at the edge of melee range.
-- HIDE debounce only: hold the icon briefly after coming back into range so it
-- doesn't vanish on a single in-range frame.  No show debounce — showing the gap
-- closer instantly is correct because the slot would otherwise fill with a rotation
-- spell, and the subsequent debounce expiry would cause a visible blink.
local GAP_CLOSER_HIDE_DEBOUNCE = 0.15  -- seconds before icon disappears
local lastOutOfRangeTime = 0

-- Cached gap-closer spell list for the current class+spec (wipe on spec change)
local cachedGapCloserSpells = nil
local cachedGapCloserSpecKey = nil

-- Melee range reference: a fixed per-spec spell whose action bar slot we poll
-- with IsActionInRange() to decide "out of melee range".  Replaces the old
-- broad slotRangeState approach that tracked all 120 slots and could fire
-- false-positive out-of-range on non-melee abilities.
local cachedMeleeRefSpellID = nil
local cachedMeleeRefSlot = nil
local cachedMeleeRefSpecKey = nil

--- Try to find an action bar slot for a spell ID (base + talent override).
--- Returns slot number or nil.
local function FindSlotForSpell(spellID)
    if not ActionBarScanner or not ActionBarScanner.GetSlotForSpell then return nil end
    local resolved = ResolveSpellID(spellID)
    local slot = ActionBarScanner.GetSlotForSpell(resolved)
    if not slot and resolved ~= spellID then
        slot = ActionBarScanner.GetSlotForSpell(spellID)
    end
    return slot
end

--- Get the melee range reference spell + slot for the current spec.
--- Priority chain: user override → SpellDB default[1] → SpellDB default[2].
--- First spell found on the action bar wins.  Caches result until spec change
--- or InvalidateGapCloserCache().
local function ResolveMeleeReference(addon)
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil, nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil, nil end
    local specKey = playerClass .. "_" .. spec

    -- Return cache if still valid
    if cachedMeleeRefSpecKey == specKey and cachedMeleeRefSlot then
        return cachedMeleeRefSpellID, cachedMeleeRefSlot
    end

    -- 1) Check profile for user override
    local profile = addon and addon.db and addon.db.profile
    local gc = profile and profile.gapClosers
    if gc and gc.meleeRangeSpell and gc.meleeRangeSpell > 0 then
        local slot = FindSlotForSpell(gc.meleeRangeSpell)
        if slot then
            cachedMeleeRefSpellID = gc.meleeRangeSpell
            cachedMeleeRefSlot = slot
            cachedMeleeRefSpecKey = specKey
            return cachedMeleeRefSpellID, cachedMeleeRefSlot
        end
    end

    -- 2) Try SpellDB defaults: [1] primary, [2] hidden backup
    if SpellDB and SpellDB.MELEE_RANGE_REFERENCE_SPELLS then
        local defaults = SpellDB.MELEE_RANGE_REFERENCE_SPELLS[specKey]
        if defaults then
            for i = 1, 2 do
                local refID = defaults[i]
                if refID then
                    local slot = FindSlotForSpell(refID)
                    if slot then
                        cachedMeleeRefSpellID = refID
                        cachedMeleeRefSlot = slot
                        cachedMeleeRefSpecKey = specKey
                        return cachedMeleeRefSpellID, cachedMeleeRefSlot
                    end
                end
            end
        end
    end

    cachedMeleeRefSpecKey = specKey
    cachedMeleeRefSpellID = nil
    cachedMeleeRefSlot = nil
    return nil, nil
end

--- Called from JustAC:OnActionRangeUpdate(slot, isInRange, checksRange)
--- Returns true if this event was for the melee reference slot (caller uses
--- this to decide whether to trigger a queue rebuild).
function lib.OnActionRangeUpdate(slot, isInRange, checksRange)
    if not slot then return false end
    if checksRange == false then return false end
    -- Only track the melee reference spell's slot
    if cachedMeleeRefSlot and slot == cachedMeleeRefSlot then
        if not isInRange then
            lastOutOfRangeTime = GetTime()
        end
        return true
    end
    return false
end

--- Clear range state (target changed, combat ended, etc.)
function lib.ClearRangeState()
    lastOutOfRangeTime = 0
    -- Don't clear cachedMeleeRefSlot here — the reference spell's slot
    -- doesn't change between targets, only the range state does.
    -- Slot is invalidated by InvalidateGapCloserCache() on spec/profile change.
end

--- Invalidate cached gap-closer spell list (spec change, profile change)
function lib.InvalidateGapCloserCache()
    cachedGapCloserSpells = nil
    cachedGapCloserSpecKey = nil
    cachedMeleeRefSpellID = nil
    cachedMeleeRefSlot = nil
    cachedMeleeRefSpecKey = nil
end

--- Resolve the gap-closer spell list for the current class+spec.
--- Reads from profile (user-configured) with SpellDB defaults as fallback.
--- Returns an array of spell IDs, or nil if no gap-closers for this spec.
local function ResolveGapCloserSpells(addon)
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    local specKey = playerClass .. "_" .. spec

    -- Return cache if still valid
    if cachedGapCloserSpells and cachedGapCloserSpecKey == specKey then
        return cachedGapCloserSpells
    end

    -- Check profile for user-configured list
    local profile = addon:GetProfile()
    local gc = profile and profile.gapClosers
    if gc and gc.classSpells and gc.classSpells[specKey] and #gc.classSpells[specKey] > 0 then
        cachedGapCloserSpells = gc.classSpells[specKey]
        cachedGapCloserSpecKey = specKey
        return cachedGapCloserSpells
    end

    -- Fall back to SpellDB defaults
    if SpellDB and SpellDB.CLASS_GAPCLOSER_DEFAULTS then
        local defaults = SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
        if defaults then
            cachedGapCloserSpells = defaults
            cachedGapCloserSpecKey = specKey
            return cachedGapCloserSpells
        end
    end

    cachedGapCloserSpecKey = specKey
    cachedGapCloserSpells = nil
    return nil
end

--- Check whether the target is out of melee range by polling the melee
--- reference spell's action bar slot.  Uses a fixed per-spec ability (e.g.
--- Backstab, Crusader Strike) so ranged/utility slots can't cause false
--- positives.  Returns true = out of melee range.
local function IsMeleeTargetOutOfRange(addon)
    local _, slot = ResolveMeleeReference(addon)
    if not slot then return false end  -- fail-closed: no reference = no gap closer
    local inRange = IsActionInRange(slot)
    return inRange == false  -- false=out of range, nil=no range check, true=in range
end

--- Returns the first usable gap-closer spell ID for the current spec, or nil.
--- "Usable" = known, IsSpellUsable(failOpen=false), on an action bar slot, and
--- not on a real cooldown (isOnGCD ~= false).
--- Returns: resolvedID, baseID  (resolvedID is the talent-overridden form;
---   baseID is the original list entry, e.g. Roll vs Chi Torpedo).
--- @param addon table              The JustAC addon object
--- @param addedSpellIDs table|nil  Set of already-queued spell IDs to skip (prevent duplicates)
function lib.GetGapCloserSpell(addon, addedSpellIDs)
    if not addon or not addon.db or not addon.db.profile then return nil end
    local gc = addon.db.profile.gapClosers
    if not gc or not gc.enabled then return nil end

    -- Must have a hostile target that is alive
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        return nil
    end

    -- IsStealthed() is NeverSecret and covers Stealth, Vanish, Shadow Dance, etc.
    local stealthed = IsStealthed and IsStealthed() or false
    local spellList = ResolveGapCloserSpells(addon)

    ----------------------------------------------------------------------------
    -- STEALTH GAP CLOSERS — evaluate before the melee range gate.
    -- When stealthed, the melee reference spell may transform on the action bar
    -- (e.g. Backstab → Shadowstrike with 25yd range), causing IsActionInRange
    -- on its slot to report the override's range instead of true melee range.
    -- Stealth gap closers like Shadowstrike teleport TO the target, so their
    -- own castable range IS the gap-closer range.  We check their own slot
    -- directly.  Dedup via addedSpellIDs prevents showing them when Blizzard's
    -- assisted combat already suggests them at position 1.
    ----------------------------------------------------------------------------
    if stealthed and spellList then
        for _, spellID in ipairs(spellList) do
            if spellID and spellID > 0 and SpellDB and SpellDB.GAP_CLOSER_REQUIRES_STEALTH
                and SpellDB.GAP_CLOSER_REQUIRES_STEALTH[spellID] then
                local resolvedID = ResolveSpellID(spellID)
                if not (addedSpellIDs and (addedSpellIDs[resolvedID] or addedSpellIDs[spellID])) then
                    local isAvailable = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(resolvedID)
                    if isAvailable then
                        local isUsable = false
                        if BlizzardAPI.IsSpellUsable then
                            isUsable = BlizzardAPI.IsSpellUsable(resolvedID, false)
                        end
                        if isUsable then
                            local slot = nil
                            if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
                                slot = ActionBarScanner.GetSlotForSpell(resolvedID)
                                if not slot and resolvedID ~= spellID then
                                    slot = ActionBarScanner.GetSlotForSpell(spellID)
                                end
                            end
                            if slot then
                                -- Check spell's own range (e.g. 25yd for Shadowstrike)
                                local ownInRange = IsActionInRange(slot)
                                if ownInRange ~= false then
                                    local isReady = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(resolvedID)
                                    if isReady then
                                        return resolvedID, spellID
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Melee range reference check.  If no reference resolves (ranged spec or
    -- nothing on the action bar), skip non-stealth gap closers entirely.
    local _, meleeRefSlot = ResolveMeleeReference(addon)
    if not meleeRefSlot then return nil end

    -- Check range using the melee reference slot
    local inRange = IsActionInRange(meleeRefSlot)
    local outOfRange = (inRange == false)  -- false=out of range, nil=no range check, true=in range
    local now = GetTime()

    -- If stealthed and the melee reference spell is overridden to a stealth
    -- gap closer with extended range (e.g. Backstab slot shows Shadowstrike
    -- at 25yd), the range check is unreliable.  Force "out of range" so
    -- non-stealth gap closers like Shadowstep and Sprint can still fire.
    if not outOfRange and stealthed and cachedMeleeRefSpellID then
        local overrideID = ResolveSpellID(cachedMeleeRefSpellID)
        if overrideID ~= cachedMeleeRefSpellID and SpellDB and SpellDB.GAP_CLOSER_REQUIRES_STEALTH
            and SpellDB.GAP_CLOSER_REQUIRES_STEALTH[overrideID] then
            outOfRange = true
        end
    end

    if outOfRange then
        -- No show debounce: display gap closer immediately when out of range.
        -- A show debounce would cause slot 2 to blink (rotation spell fills it
        -- during the debounce window, then gets displaced by the gap closer).
    else
        -- Hide debounce: hold the icon briefly after returning to range
        if lastOutOfRangeTime == 0 or (now - lastOutOfRangeTime) > GAP_CLOSER_HIDE_DEBOUNCE then
            return nil
        end
    end

    if not spellList then return nil end

    for _, spellID in ipairs(spellList) do
        if spellID and spellID > 0 then
            -- Resolve talent overrides (e.g., Chi Torpedo replacing Roll)
            local resolvedID = ResolveSpellID(spellID)

            -- Skip stealth-only gap closers in the normal loop.
            -- When stealthed: already evaluated in the dedicated stealth path above.
            -- When not stealthed: gap-closer component is inactive (no teleport).
            if SpellDB and SpellDB.GAP_CLOSER_REQUIRES_STEALTH
                and (SpellDB.GAP_CLOSER_REQUIRES_STEALTH[spellID] or SpellDB.GAP_CLOSER_REQUIRES_STEALTH[resolvedID]) then
                -- skip: handled by stealth gap-closer path or inactive
            -- Skip if already in the queue
            elseif addedSpellIDs and (addedSpellIDs[resolvedID] or addedSpellIDs[spellID]) then
                -- skip: already shown
            else
                -- Check: spell is known
                local isAvailable = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(resolvedID)
                if isAvailable then
                    -- Gap closers fail CLOSED (failOpen=false): if we can't confirm
                    -- usability (secret values), skip to the next spell rather than
                    -- suggesting an unusable ability.
                    local isUsable = false
                    if BlizzardAPI.IsSpellUsable then
                        isUsable = BlizzardAPI.IsSpellUsable(resolvedID, false)
                    end
                    if isUsable then
                        -- Check: spell is actually on an action bar slot.
                        -- Some spells may not be on any bar slot (e.g. the button
                        -- shows a different spell via override). Skip spells with no
                        -- slot — they can't get a keybind anyway.
                        if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
                            local slot = ActionBarScanner.GetSlotForSpell(resolvedID)
                            if not slot then
                                -- Also try the base spell ID (in case override resolves differently)
                                if resolvedID ~= spellID then
                                    slot = ActionBarScanner.GetSlotForSpell(spellID)
                                end
                                if not slot then
                                    -- Not on any action bar — skip to next candidate
                                    -- (e.g. Shadowstep will be tried next)
                                end
                            end
                            if slot then
                                -- Check: spell is ready (not on a real cooldown)
                                -- 12.0: isOnGCD==true means GCD-only; nil is ambiguous,
                                -- so IsSpellReady also checks local CD tracking + action bar state
                                local isReady = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(resolvedID)
                                if isReady then
                                    return resolvedID, spellID
                                end
                            end
                        else
                            -- No ActionBarScanner: fall back to cooldown check only
                            local isReady = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(resolvedID)
                            if isReady then
                                return resolvedID, spellID
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

--- Returns true if the given spellID is ANY known gap-closer for the current spec.
--- Checks both the user's configured list AND the SpellDB defaults, plus their
--- active talent overrides.  This ensures that even if a user removes a spell
--- from their personal list, Blizzard suggesting it at position 1 still suppresses
--- our gap-closer injection at position 2.
function lib.IsGapCloserSpell(addon, spellID)
    if not spellID or spellID == 0 then return false end

    -- Helper: scan a spell list for a match (base ID or talent override)
    local function ListContains(list)
        if not list then return false end
        for _, gcSpellID in ipairs(list) do
            if gcSpellID == spellID then return true end
            if ResolveSpellID(gcSpellID) == spellID then return true end
        end
        return false
    end

    -- Check user-configured list
    if addon then
        local userList = ResolveGapCloserSpells(addon)
        if ListContains(userList) then return true end
    end

    -- Check SpellDB defaults (catches spells the user removed from their list)
    local defaults = SpellDB and SpellDB.GetGapCloserDefaults and SpellDB.GetGapCloserDefaults()
    if defaults and ListContains(defaults) then return true end

    return false
end

--- Mark all gap-closer spell IDs (base + talent-resolved forms) into a set.
--- Called by SpellQueue to suppress gap-closer spells from the rotation list
--- when the gap-closer system is enabled — our insertion controls when they appear.
function lib.MarkGapCloserSpellIDs(addon, spellIDSet)
    if not addon or not spellIDSet then return end
    local spellList = ResolveGapCloserSpells(addon)
    if not spellList then return end
    for _, spellID in ipairs(spellList) do
        if spellID and spellID > 0 then
            spellIDSet[spellID] = true
            local resolvedID = ResolveSpellID(spellID)
            if resolvedID ~= spellID then
                spellIDSet[resolvedID] = true
            end
        end
    end
end

--- Restore gap-closer defaults for the current spec
function lib.RestoreGapCloserDefaults(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.gapClosers then return end

    local specKey = lib.GetGapCloserSpecKey()
    if not specKey then return end

    if not profile.gapClosers.classSpells then
        profile.gapClosers.classSpells = {}
    end

    local defaults = SpellDB and SpellDB.CLASS_GAPCLOSER_DEFAULTS and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
    if defaults then
        profile.gapClosers.classSpells[specKey] = {}
        for i, spellID in ipairs(defaults) do
            profile.gapClosers.classSpells[specKey][i] = spellID
        end
    else
        profile.gapClosers.classSpells[specKey] = nil
    end

    lib.InvalidateGapCloserCache()
end

--- Get the gap-closer spell list key for the current spec
function lib.GetGapCloserSpecKey()
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    return playerClass .. "_" .. spec
end
