-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- DefensiveEngine.lua — Defensive spell system: health-based queue, proc detection, potions
-- Gap-closer system extracted to GapCloserEngine.lua.

local DefensiveEngine = LibStub:NewLibrary("JustAC-DefensiveEngine", 1)
if not DefensiveEngine then return end

-- Hot path cache
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local GetItemCount = GetItemCount
local GetItemCooldown = GetItemCooldown
local wipe = wipe
local ipairs = ipairs
local pairs = pairs
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
local proccedBuffer = {}          -- procced spells (highest priority)
local castableBuffer = {}         -- castable non-procced spells (mid priority)
local resourceBlockedBuffer = {}  -- known/non-redundant but currently unusable (lowest priority)

-- Stable in-place sort: move unusable entries to the end of the queue
-- while preserving relative order within each group (castable vs blocked).
local function SortUnusableToEnd(results)
    if #results <= 1 then return end
    local sortCastable = {}
    local sortBlocked = {}
    local hasBlocked = false
    for _, entry in ipairs(results) do
        if entry.unusable then
            sortBlocked[#sortBlocked + 1] = entry
            hasBlocked = true
        else
            sortCastable[#sortCastable + 1] = entry
        end
    end
    if not hasBlocked then return end  -- nothing to reorder
    local idx = 0
    for _, e in ipairs(sortCastable) do idx = idx + 1; results[idx] = e end
    for _, e in ipairs(sortBlocked)  do idx = idx + 1; results[idx] = e end
end

-- Forward declarations for functions referenced before definition
local AppendUsableSpells
local ResolveHealthState

-- Spell list type configuration — maps restoreKey (used by Options) to
-- the profile listKey and SpellDB defaults table name.
local SPELL_LIST_CONFIG = {
    { listKey = "defensiveSpells", restoreKey = "defensive", defaultsKey = "CLASS_DEFENSIVE_DEFAULTS" },
    { listKey = "petHealSpells",   restoreKey = "petheal",   defaultsKey = "CLASS_PETHEAL_DEFAULTS" },
    { listKey = "petRezSpells",    restoreKey = "petrez",    defaultsKey = "CLASS_PET_REZ_DEFAULTS" },
}

-- Copy a source spell list into dest[listKey], used by init/migrate/restore.
local function CopySpellList(dest, listKey, source)
    dest[listKey] = {}
    for i, spellID in ipairs(source) do
        dest[listKey][i] = spellID
    end
end

-- Hide multi-icon or single-icon defensive frames (handles both layouts).
local function HideDefensiveIconFrames(addon)
    if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
        UIRenderer.HideDefensiveIcons(addon)
    elseif addon.defensiveIcon and UIRenderer and UIRenderer.HideDefensiveIcon then
        UIRenderer.HideDefensiveIcon(addon.defensiveIcon)
    end
end

-- Resize both player and pet health bars to match visible defensive icon count.
local function ResizeHealthBars(addon, count)
    if UIHealthBar and UIHealthBar.ResizeToCount then UIHealthBar.ResizeToCount(addon, count) end
    if UIHealthBar and UIHealthBar.ResizePetToCount then UIHealthBar.ResizePetToCount(addon, count) end
end

-- Show or hide main-panel defensive icons based on a resolved queue.
local function ApplyMainPanelQueue(addon, defensiveQueue)
    if #defensiveQueue > 0 then
        if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.ShowDefensiveIcons then
            UIRenderer.ShowDefensiveIcons(addon, defensiveQueue)
        elseif addon.defensiveIcon and UIRenderer and UIRenderer.ShowDefensiveIcon then
            UIRenderer.ShowDefensiveIcon(addon, defensiveQueue[1].spellID, defensiveQueue[1].isItem, addon.defensiveIcon)
        end
        ResizeHealthBars(addon, #defensiveQueue)
    else
        HideDefensiveIconFrames(addon)
        ResizeHealthBars(addon, 0)
    end
end

-- Show or hide nameplate overlay defensive icons based on a resolved queue.
local function ApplyOverlayQueue(addon, npoQueue)
    if #npoQueue > 0 then
        UINameplateOverlay.RenderDefensives(addon, npoQueue)
    else
        UINameplateOverlay.HideDefensiveIcons()
    end
end

-- Secret-safe item cooldown check. Returns true when the item is on a real cooldown
-- (duration > 1.5s, excluding GCD). Fail-open: returns false when values are secret.
local function IsItemOnCooldown(itemID)
    local start, duration = GetItemCooldown(itemID)
    if not start or not duration then return false end
    if BlizzardAPI.IsSecretValue(start) or BlizzardAPI.IsSecretValue(duration) then return false end
    return start > 0 and duration > 1.5
end

-- Resolve player health into isLow boolean.
-- 12.0: UnitHealth() is secret in combat — falls back to LowHealthFrame binary states.
-- In combat (secret): GetPlayerHealthPercentSafe returns 100 (not low) or ≤35
-- (LowHealthFrame shown, ~35% threshold, NeverSecret). Configurable thresholds
-- are impossible since we only have a binary signal.
-- Out of combat: real health available, uses fixed 80% threshold.
ResolveHealthState = function(profile)
    local healthPercent = BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe
        and BlizzardAPI.GetPlayerHealthPercentSafe()
    if healthPercent then
        return healthPercent <= 80
    end
    return false
end

-- Healing potion cache
local HEALTHSTONE_ITEM_ID = 5512
local cachedPotionID = nil
local cachedPotionSlot = nil
local potionCacheValid = false

--------------------------------------------------------------------------------
-- Spell list access
--------------------------------------------------------------------------------

-- Returns the spell list for a given type ("defensiveSpells", "petHealSpells", "petRezSpells")
-- for the current player class+spec from the per-spec nested structure.
-- Resolution order: specKey ("CLASS_N") → class fallback ("CLASS").
function DefensiveEngine.GetClassSpellList(addon, listKey)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return nil end

    local specKey, playerClass
    if SpellDB and SpellDB.GetSpecKey then
        specKey, playerClass = SpellDB.GetSpecKey()
    end
    if not playerClass then return nil end

    local classSpells = profile.defensives.classSpells
    if not classSpells then return nil end

    -- Try spec-specific first, then class fallback (legacy data)
    if specKey and classSpells[specKey] and classSpells[specKey][listKey] then
        return classSpells[specKey][listKey]
    end
    if classSpells[playerClass] and classSpells[playerClass][listKey] then
        return classSpells[playerClass][listKey]
    end
    return nil
end

--- Returns the spec key used for defensive spell storage.
--- Exposed so Options/Defensives can display the correct spec context.
function DefensiveEngine.GetDefensiveSpecKey()
    if SpellDB and SpellDB.GetSpecKey then
        return SpellDB.GetSpecKey()
    end
    return nil, nil
end

-- Migrate pre-3.25 flat spell lists (selfHealSpells/cooldownSpells/petHealSpells)
-- into the new per-spec classSpells structure. Safe to call multiple times.
function DefensiveEngine.MigrateDefensiveSpellsToClassSpells(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local specKey, playerClass = DefensiveEngine.GetDefensiveSpecKey()
    if not playerClass then return end
    -- Need spec key for per-spec storage; fall back to class key if spec unavailable
    local targetKey = specKey or playerClass

    local def = profile.defensives
    local hasFlatData = (def.selfHealSpells and #def.selfHealSpells > 0)
        or (def.cooldownSpells and #def.cooldownSpells > 0)
        or (def.petHealSpells and #def.petHealSpells > 0)

    if hasFlatData then
        -- Ensure classSpells table exists
        if not def.classSpells then def.classSpells = {} end
        if not def.classSpells[targetKey] then def.classSpells[targetKey] = {} end
        local cs = def.classSpells[targetKey]

        -- Move flat lists into per-spec structure (don't overwrite existing)
        -- Note: uses legacy keys selfHealSpells/cooldownSpells for this migration path
        local legacyKeys = { "selfHealSpells", "cooldownSpells", "petHealSpells" }
        for _, listKey in ipairs(legacyKeys) do
            local flatList = def[listKey]
            if flatList and #flatList > 0 and (not cs[listKey] or #cs[listKey] == 0) then
                CopySpellList(cs, listKey, flatList)
            end
        end

        -- Clear flat keys so migration won't re-trigger
        def.selfHealSpells = nil
        def.cooldownSpells = nil
        def.petHealSpells = nil

        addon:DebugPrint("Migrated flat defensive spells to classSpells[" .. targetKey .. "]")
    end

    -- Merge selfHealSpells + cooldownSpells → defensiveSpells (unified list migration).
    -- Runs after flat→classSpells migration so both paths feed into the merge.
    DefensiveEngine.MergeLegacyDefensiveLists(addon)
end

-- Merge legacy per-spec selfHealSpells + cooldownSpells into the unified defensiveSpells
-- list.  Self-heals come first (natural priority), then cooldowns.  Deduplicates.
-- Idempotent: skips if defensiveSpells already exists.  Old keys are preserved for
-- safe downgrade to older addon versions.
function DefensiveEngine.MergeLegacyDefensiveLists(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local specKey, playerClass = DefensiveEngine.GetDefensiveSpecKey()
    if not playerClass then return end
    local targetKey = specKey or playerClass

    local def = profile.defensives
    if not def.classSpells or not def.classSpells[targetKey] then return end
    local cs = def.classSpells[targetKey]

    -- Already merged — skip
    if cs.defensiveSpells and #cs.defensiveSpells > 0 then return end

    local selfHeals  = cs.selfHealSpells
    local cooldowns  = cs.cooldownSpells
    if (not selfHeals or #selfHeals == 0) and (not cooldowns or #cooldowns == 0) then return end

    -- Concatenate: self-heals first, then cooldowns, deduplicating
    local merged = {}
    local seen = {}
    if selfHeals then
        for _, id in ipairs(selfHeals) do
            if not seen[id] then
                merged[#merged + 1] = id
                seen[id] = true
            end
        end
    end
    if cooldowns then
        for _, id in ipairs(cooldowns) do
            if not seen[id] then
                merged[#merged + 1] = id
                seen[id] = true
            end
        end
    end

    cs.defensiveSpells = merged
    -- Keep selfHealSpells/cooldownSpells for safe downgrade — do NOT wipe them.

    addon:DebugPrint("Merged selfHealSpells+cooldownSpells → defensiveSpells[" .. targetKey .. "] (" .. #merged .. " spells)")
end

--------------------------------------------------------------------------------
-- Initialization & registration
--------------------------------------------------------------------------------

function DefensiveEngine.InitializeDefensiveSpells(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local specKey, playerClass = DefensiveEngine.GetDefensiveSpecKey()
    if not playerClass then return end

    -- Migrate legacy flat lists on first load
    DefensiveEngine.MigrateDefensiveSpellsToClassSpells(addon)

    -- Determine target key: prefer spec key, fall back to class key for pre-spec data
    local targetKey = specKey or playerClass

    -- Ensure classSpells table structure exists
    local def = profile.defensives
    if not def.classSpells then def.classSpells = {} end
    if not def.classSpells[targetKey] then def.classSpells[targetKey] = {} end
    local cs = def.classSpells[targetKey]

    -- Populate empty spell lists from SpellDB defaults (spec→class fallback)
    for _, cfg in ipairs(SPELL_LIST_CONFIG) do
        if not cs[cfg.listKey] or #cs[cfg.listKey] == 0 then
            local defaults = SpellDB and SpellDB[cfg.defaultsKey]
                and SpellDB.ResolveDefaults(SpellDB[cfg.defaultsKey], specKey, playerClass)
            if defaults then
                CopySpellList(cs, cfg.listKey, defaults)
            end
        end
    end

    DefensiveEngine.RegisterDefensivesForTracking(addon)
end

-- Enables 12.0 compatibility when C_Spell.GetSpellCooldown returns secrets
function DefensiveEngine.RegisterDefensivesForTracking(addon)
    if not BlizzardAPI or not BlizzardAPI.RegisterDefensiveSpell then return end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    if BlizzardAPI.ClearTrackedDefensives then
        BlizzardAPI.ClearTrackedDefensives()
    end

    -- Table-driven iteration: register all defensive spell lists
    local spellListTypes = { "defensiveSpells", "petHealSpells", "petRezSpells" }
    for _, listType in ipairs(spellListTypes) do
        local spellList = DefensiveEngine.GetClassSpellList(addon, listType)
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

function DefensiveEngine.RestoreDefensiveDefaults(addon, listType)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local specKey, playerClass = DefensiveEngine.GetDefensiveSpecKey()
    if not playerClass then return end
    local targetKey = specKey or playerClass

    -- Ensure classSpells structure exists
    if not profile.defensives.classSpells then profile.defensives.classSpells = {} end
    if not profile.defensives.classSpells[targetKey] then profile.defensives.classSpells[targetKey] = {} end
    local cs = profile.defensives.classSpells[targetKey]

    for _, cfg in ipairs(SPELL_LIST_CONFIG) do
        if cfg.restoreKey == listType then
            local defaults = SpellDB and SpellDB[cfg.defaultsKey]
                and SpellDB.ResolveDefaults(SpellDB[cfg.defaultsKey], specKey, playerClass)
            if defaults then
                CopySpellList(cs, cfg.listKey, defaults)
            end
            break
        end
    end

    DefensiveEngine.RegisterDefensivesForTracking(addon)
    DefensiveEngine.OnHealthChanged(addon, nil, "player")
end

--------------------------------------------------------------------------------
-- Health change handler — main defensive queue dispatch
--------------------------------------------------------------------------------

function DefensiveEngine.OnHealthChanged(addon, event, unit)
    if addon.isDisabledMode then return end
    if unit ~= "player" and unit ~= "pet" then return end

    local profile = addon:GetProfile()
    local def = profile and profile.defensives

    -- Resolve overlay state once (UINameplateOverlay may not be loaded)
    local npo = UINameplateOverlay and (profile and profile.nameplateOverlay)
    local overlayDM = profile and profile.displayMode or "queue"
    local overlayActive = npo and (overlayDM == "overlay" or overlayDM == "both")

    -- When main panel defensives are off, hide any icons that may be visible
    -- from a previous enabled state.
    if def and not def.enabled then
        HideDefensiveIconFrames(addon)
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
    local isLow = ResolveHealthState(profile)

    -- 12.0: UnitHealth("pet") is secret in combat → GetPetHealthPercent() returns nil.
    -- Pet heals only trigger out of combat (between pulls, open world). This is by design.
    local petHealthPercent = BlizzardAPI and BlizzardAPI.GetPetHealthPercent and BlizzardAPI.GetPetHealthPercent()
    local petNeedsHeal = petHealthPercent and petHealthPercent <= 50

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
        local defensiveQueue = DefensiveEngine.GetDefensiveSpellQueue(addon, isLow, inCombat, dpsQueueExclusions)
        local maxIcons = def.maxIcons or 4

        -- Pet rez/summon: HIGH priority — pet dead or missing (reliable in combat)
        -- Uses defensiveAlreadyAdded from GetDefensiveSpellQueue to avoid duplicates
        if petNeedsRez and #defensiveQueue < maxIcons then
            AppendUsableSpells(addon, defensiveQueue, DefensiveEngine.GetClassSpellList(addon, "petRezSpells"), maxIcons, defensiveAlreadyAdded)
        end

        -- Pet heals: LOWER priority — out-of-combat only (health is secret in combat)
        if petNeedsHeal and not petNeedsRez and #defensiveQueue < maxIcons then
            AppendUsableSpells(addon, defensiveQueue, DefensiveEngine.GetClassSpellList(addon, "petHealSpells"), maxIcons, defensiveAlreadyAdded)
        end

        ApplyMainPanelQueue(addon, defensiveQueue)
    else
        -- Defensives disabled on main panel: ensure icons are hidden
        HideDefensiveIconFrames(addon)
        ResizeHealthBars(addon, 0)
    end

    -- Nameplate overlay defensive queue — independent of defensives.enabled.
    -- Uses its own display mode and icon count settings. GetDefensiveSpellQueue wipes
    -- defensiveAlreadyAdded at the start of each call, so no bleed from the main panel path.
    if overlayActive and npo.showDefensives then
        local npoDisplayMode = npo.defensiveDisplayMode or "always"
        local npoMaxIcons    = npo.maxDefensiveIcons or 3
        local npoQueue = DefensiveEngine.GetDefensiveSpellQueue(addon, isLow, inCombat, dpsQueueExclusions, {displayMode=npoDisplayMode, maxIcons=npoMaxIcons, showProcs=(profile.defensives.showProcs ~= false)})

        -- Pet rez/heal: parity with main panel (same priority order)
        if petNeedsRez and #npoQueue < npoMaxIcons then
            AppendUsableSpells(addon, npoQueue, DefensiveEngine.GetClassSpellList(addon, "petRezSpells"), npoMaxIcons, defensiveAlreadyAdded)
        end
        if petNeedsHeal and not petNeedsRez and #npoQueue < npoMaxIcons then
            AppendUsableSpells(addon, npoQueue, DefensiveEngine.GetClassSpellList(addon, "petHealSpells"), npoMaxIcons, defensiveAlreadyAdded)
        end

        ApplyOverlayQueue(addon, npoQueue)
    end
end

--------------------------------------------------------------------------------
-- Spell queue building
--------------------------------------------------------------------------------

-- Returns up to maxCount usable spells/items, prioritizing procs
-- Uses module-level pooled tables (usableResults/usableAddedHere) to avoid per-call allocations
-- IMPORTANT: Caller must consume results before next call (table is reused)
-- List entries: positive = spell ID, negative = item ID (-itemID)
--
-- Single-pass design: iterates spellList once, categorizing into three priority tiers:
--   1. Procced spells (instant/free cast available — highest priority)
--   2. Castable non-procced spells + usable items (mid priority)
--   3. Unusable spells (known + non-redundant but on CD or lacking resources — lowest priority)
-- Each spell is checked by CheckDefensiveSpellState exactly once.
function DefensiveEngine.GetUsableDefensiveSpells(addon, spellList, maxCount, alreadyAdded)
    wipe(usableResults)
    if not spellList or maxCount <= 0 then return usableResults end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return usableResults end

    alreadyAdded = alreadyAdded or {}
    wipe(usableAddedHere)
    wipe(proccedBuffer)
    wipe(castableBuffer)
    wipe(resourceBlockedBuffer)

    -- Single pass: categorize spells and items into priority tiers
    local itemsEnabled = profile.defensives and profile.defensives.allowItems
    for _, entry in ipairs(spellList) do
        if entry and entry > 0 then
            local resolvedID = BlizzardAPI.ResolveSpellID(entry)
            -- Check both the original and resolved IDs to handle proc injection cross-dedup
            if not alreadyAdded[entry] and not alreadyAdded[resolvedID] and not usableAddedHere[resolvedID] then
                local isUsable, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(resolvedID, profile)
                if isUsable then
                    if isProcced then
                        -- Procced: top priority (instant/free cast)
                        proccedBuffer[#proccedBuffer + 1] = {spellID = resolvedID, isItem = false, isProcced = true}
                    else
                        -- Check local cooldown tracking (works in combat via 12.0 CooldownTracking).
                        -- Skip for charge-based spells: local CD fires on every cast but charges
                        -- mean the spell may still be usable. IsSpellUsable handles this correctly.
                        local cachedMaxCharges = BlizzardAPI.GetCachedMaxCharges and BlizzardAPI.GetCachedMaxCharges(resolvedID)
                        local isChargeSpell = cachedMaxCharges and cachedMaxCharges > 1
                        local isOnLocalCD = not isChargeSpell
                            and BlizzardAPI.IsSpellOnLocalCooldown
                            and BlizzardAPI.IsSpellOnLocalCooldown(resolvedID)
                        if isOnLocalCD then
                            -- On cooldown: deprioritize but keep in queue for visual feedback.
                            resourceBlockedBuffer[#resourceBlockedBuffer + 1] = {spellID = resolvedID, isItem = false, isProcced = false, unusable = true, noResources = false}
                        else
                            -- Not on local CD (or charge spell): check if actually castable.
                            -- IsSpellUsable is NeverSecret (falls back to C_ActionBar.IsUsableAction).
                            -- Returns false for both cooldown-blocked AND resource-blocked spells.
                            -- For charge spells, returns false only when ALL charges are depleted.
                            local castable, notEnoughResources = BlizzardAPI.IsSpellUsable(resolvedID)
                            if castable then
                                castableBuffer[#castableBuffer + 1] = {spellID = resolvedID, isItem = false, isProcced = false}
                            else
                                -- Unusable: deprioritize but keep in queue for visual feedback.
                                resourceBlockedBuffer[#resourceBlockedBuffer + 1] = {spellID = resolvedID, isItem = false, isProcced = false, unusable = true, noResources = notEnoughResources}
                            end
                        end
                    end
                    usableAddedHere[resolvedID] = true
                    usableAddedHere[entry] = true  -- also mark original so it isn't reprocessed
                end
            end
        elseif itemsEnabled and entry and entry < 0 and not alreadyAdded[entry] and not alreadyAdded[-entry] and not usableAddedHere[entry] then
            -- Negative entry = item (stored as -itemID)
            local itemID = -entry
            local isUsable = BlizzardAPI.CheckDefensiveItemState(itemID, profile)
            if isUsable then
                castableBuffer[#castableBuffer + 1] = {spellID = itemID, isItem = true, isProcced = false}
                usableAddedHere[entry] = true
                -- Also mark the positive itemID to prevent FindHealingPotionOnActionBar duplicates
                usableAddedHere[itemID] = true
            end
        end
    end

    -- Merge in priority order: procced → castable (spells + items) → blocked
    for _, e in ipairs(proccedBuffer) do
        if #usableResults >= maxCount then break end
        usableResults[#usableResults + 1] = e
    end
    for _, e in ipairs(castableBuffer) do
        if #usableResults >= maxCount then break end
        usableResults[#usableResults + 1] = e
    end
    for _, e in ipairs(resourceBlockedBuffer) do
        if #usableResults >= maxCount then break end
        usableResults[#usableResults + 1] = e
    end

    return usableResults
end

-- Append usable defensive spells from a spell list into a results table with dedup tracking.
-- If procsOnly is true, only entries with isProcced=true are appended.
-- Callers MUST consume results before next GetUsableDefensiveSpells call (pooled table).
AppendUsableSpells = function(addon, results, spellList, maxIcons, alreadyAdded, procsOnly)
    if #results >= maxIcons then return end
    local spells = DefensiveEngine.GetUsableDefensiveSpells(addon, spellList, maxIcons - #results, alreadyAdded)
    for _, entry in ipairs(spells) do
        if not procsOnly or entry.isProcced then
            results[#results + 1] = entry
            alreadyAdded[entry.spellID] = true
        end
    end
end

-- Display order: instant procs first, then unified defensive list in user priority order.
-- overrides (optional table): displayMode, maxIcons, showProcs — override profile defaults for
-- alternate display contexts (e.g. nameplate overlay uses its own mode and icon count).
function DefensiveEngine.GetDefensiveSpellQueue(addon, passedIsLow, passedInCombat, passedExclusions, overrides)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return {} end

    local maxIcons = (overrides and overrides.maxIcons) or profile.defensives.maxIcons or 4
    local showProcs
    if overrides and overrides.showProcs ~= nil then
        showProcs = overrides.showProcs
    else
        showProcs = profile.defensives.showProcs ~= false
    end
    local results = {}
    -- Reuse pooled table for tracking added spells
    wipe(defensiveAlreadyAdded)
    local alreadyAdded = defensiveAlreadyAdded

    if passedExclusions then
        for spellID, _ in pairs(passedExclusions) do
            alreadyAdded[spellID] = true
        end
    end

    local isLow, inCombat
    if passedIsLow ~= nil then
        isLow = passedIsLow
        inCombat = passedInCombat or UnitAffectingCombat("player")
    else
        -- Safety net: resolve health state from scratch if caller didn't pass it
        isLow = ResolveHealthState(profile)
        inCombat = UnitAffectingCombat("player")
    end

    local displayMode = (overrides and overrides.displayMode) or profile.defensives.displayMode
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
                    local resolvedID = BlizzardAPI.ResolveSpellID(spellID)
                    if not alreadyAdded[spellID] and not alreadyAdded[resolvedID] then
                        local isUsable, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(resolvedID, profile)
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

    -- Early exit: proc injection already filled the queue
    if #results >= maxIcons then return results end

    -- Unified defensive spell list (user-ordered priority)
    local defensiveSpells = DefensiveEngine.GetClassSpellList(addon, "defensiveSpells")

    -- Procced spells from configured list (any health level)
    AppendUsableSpells(addon, results, defensiveSpells, maxIcons, alreadyAdded, true)

    -- Early exit: proc passes filled the queue
    if #results >= maxIcons then return results end

    if displayMode == "combatOnly" and not inCombat then
        SortUnusableToEnd(results)
        return results
    end

    local showAllAvailable = (displayMode == "always") or (displayMode == "combatOnly" and inCombat)
    if showAllAvailable or isLow then
        AppendUsableSpells(addon, results, defensiveSpells, maxIcons, alreadyAdded)
        -- Auto-insert potions when health is low (unified: no separate "critical" tier)
        if isLow and #results < maxIcons and profile.defensives.autoInsertPotions ~= false then
            local potionID = DefensiveEngine.FindHealingPotionOnActionBar(addon)
            if potionID and not alreadyAdded[potionID] then
                results[#results + 1] = {spellID = potionID, isItem = true, isProcced = false}
                alreadyAdded[potionID] = true
            end
        end
    end

    SortUnusableToEnd(results)
    return results
end

--------------------------------------------------------------------------------
-- Healing potion subsystem
--------------------------------------------------------------------------------

function DefensiveEngine.InvalidatePotionCache()
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
function DefensiveEngine.FindHealingPotionOnActionBar(addon)
    if potionCacheValid then
        -- Still check cooldown/count on cached result (these change in combat)
        if cachedPotionID then
            local count = GetItemCount(cachedPotionID) or 0
            if count > 0 and not IsItemOnCooldown(cachedPotionID) then
                return cachedPotionID, cachedPotionSlot
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
            if count > 0 and not IsItemOnCooldown(id) then
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

    cachedPotionID = bestPotion
    cachedPotionSlot = bestSlot
    potionCacheValid = true
    return bestPotion, bestSlot
end

--------------------------------------------------------------------------------
-- Cooldown polling
--------------------------------------------------------------------------------

function DefensiveEngine.UpdateDefensiveCooldowns(addon)
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
    -- The main OnUpdate loop now does full queue rebuilds periodically, but this
    -- explicit poll keeps cooldown swipes smooth between rebuilds.
    if addon.nameplateDefIcons and #addon.nameplateDefIcons > 0 then
        for _, icon in ipairs(addon.nameplateDefIcons) do
            if icon and icon:IsShown() then
                UIRenderer.UpdateButtonCooldowns(icon)
            end
        end
    end
end
