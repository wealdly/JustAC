-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- DefensiveEngine.lua - Defensive spell system: health-based queue, proc detection, potions
-- Gap-closer system extracted to GapCloserEngine.lua.

local DefensiveEngine = LibStub:NewLibrary("JustAC-DefensiveEngine", 4)
if not DefensiveEngine then return end

-- Hot path cache
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local wipe = wipe
local ipairs = ipairs
local pairs = pairs
local math_min = math.min

-- Module references (resolved at load time - DefensiveEngine loads after all deps in TOC)
local BlizzardAPI       = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner  = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue         = LibStub("JustAC-SpellQueue", true)
local SpellDB            = LibStub("JustAC-SpellDB", true)
local UIRenderer         = LibStub("JustAC-UIRenderer", true)
local UIHealthBar        = LibStub("JustAC-UIHealthBar", true)
local UINameplateOverlay = LibStub("JustAC-UINameplateOverlay", true)

--------------------------------------------------------------------------------
-- Pooled tables - avoid GC pressure on hot paths
--------------------------------------------------------------------------------

local lastHealthUpdate = 0
local HEALTH_UPDATE_THROTTLE = 0.1  -- 100ms minimum between defensive queue updates

local dpsQueueExclusions = {}
local defensiveAlreadyAdded = {}
-- Pooled tables for GetUsableDefensiveSpells (avoids per-call allocations)
local usableResults = {}
local usableAddedHere = {}
local proccedBuffer = {}    -- procced spells (highest priority)
local nonProccedBuffer = {} -- castable non-procced spells in user list order
local unusableBuffer = {}   -- on-CD or resource-starved spells (de-prioritized to end)

-- Per-tick evaluation memo, keyed by list entry (positive spell / negative item).
-- One rebuild evaluates the defensive list up to FOUR times (procs pass + full pass,
-- x two surfaces); every pass re-ran the same per-spell C-call battery. GetTime() is
-- frame-stable, so a stamp makes passes 2-4 pure table reads. Grows only to the set
-- of entries ever seen (list-sized) - no wipe needed.
local defensiveEvalMemo = {}

-- Queue entry pooling: each surface owns a persistent results array; entry tables
-- cycle through a shared free list instead of being allocated per pass (~30-40 fresh
-- tables per rebuild otherwise, at up to 10Hz). Discipline: a table is either in
-- exactly one results array or in the pool - ReleaseResults at the start of a
-- surface's build recycles only that surface's previous entries.
local mainResultsBuf = {}
local overlayResultsBuf = {}
local entryPool = {}

local function ReleaseResults(results)
    for i = #results, 1, -1 do
        entryPool[#entryPool + 1] = results[i]
        results[i] = nil
    end
end

-- Append a fully-specified entry; nil clears stale fields from a recycled table.
local function PushEntry(results, spellID, isItem, isProcced, unusable, noResources, precombat, topoff)
    local n = #entryPool
    local e
    if n > 0 then e = entryPool[n]; entryPool[n] = nil else e = {} end
    e.spellID, e.isItem, e.isProcced = spellID, isItem, isProcced
    e.unusable, e.noResources = unusable, noResources
    e.precombat, e.topoff = precombat, topoff
    e.waiting = nil
    results[#results + 1] = e
    return e
end

-- Build counters (for /jac perf diagnostic)
local defensiveBuildCount = 0
local defensiveResetTime = GetTime()

-- Lazy module refs (these load after this file): resolved once, not per rebuild.
local MaintenanceTrackerRef, PrecombatEngineRef


-- Forward declarations for functions referenced before definition
local AppendUsableSpells
local ResolveHealthState

-- Spell list type configuration - maps restoreKey (used by Options) to
-- the profile listKey and SpellDB defaults table name.
local SPELL_LIST_CONFIG = {
    { listKey = "defensiveSpells", restoreKey = "defensive", defaultsKey = "CLASS_DEFENSIVE_DEFAULTS" },
    { listKey = "petHealSpells",   restoreKey = "petheal",   defaultsKey = "CLASS_PETHEAL_DEFAULTS" },
    { listKey = "petRezSpells",    restoreKey = "petrez",    defaultsKey = "CLASS_PET_REZ_DEFAULTS" },
    -- Healer specs only: ResolveDefaults returns nil for every other spec, so
    -- the list is never created and the heal pass below finds nothing.
    { listKey = "groupHealSpells", restoreKey = "groupheal", defaultsKey = "CLASS_GROUPHEAL_DEFAULTS" },
}

-- Copy a source spell list into dest[listKey], used by init/restore.
local function CopySpellList(dest, listKey, source)
    dest[listKey] = {}
    for i, spellID in ipairs(source) do
        dest[listKey][i] = spellID
    end
end

-- Append the Emergency Potion sentinel to the defensive list unless it is already present.
-- It is deliberately NOT in CLASS_DEFENSIVE_DEFAULTS - those are spell ids and this is an
-- item tile - so anything that rebuilds the list from those defaults drops it. Shared by the
-- first-time seed AND Restore Class Defaults so the two cannot disagree about whether the
-- tile counts as "default"; restoring defaults previously wiped it permanently, because the
-- seed is guarded by a once-only flag that was already set.
local function EnsureEmergencyPotion(cs)
    if not (SpellDB and SpellDB.EMERGENCY_POTION) then return end
    cs.defensiveSpells = cs.defensiveSpells or {}
    for i = 1, #cs.defensiveSpells do
        if cs.defensiveSpells[i] == SpellDB.EMERGENCY_POTION then return end
    end
    cs.defensiveSpells[#cs.defensiveSpells + 1] = SpellDB.EMERGENCY_POTION
end

--- Record that the player deliberately removed the Emergency Potion tile from the current
--- spec's defensive list, so the seed in InitializeDefensiveSpells stops re-adding it.
--- Called only from the tile's own Remove button - nothing else may set this, or a lost
--- tile becomes permanent again.
function DefensiveEngine.MarkEmergencyPotionRemoved(addon)
    local profile = addon and addon.GetProfile and addon:GetProfile()
    local def = profile and profile.defensives
    if not (def and def.classSpells) then return end
    local specKey, playerClass
    if SpellDB and SpellDB.GetSpecKey then specKey, playerClass = SpellDB.GetSpecKey() end
    local cs = def.classSpells[specKey or playerClass]
    if cs then cs.emergencyPotionRemoved = true end
end

-- Hide the defensive icon frames.
local function HideDefensiveIconFrames(addon)
    if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
        UIRenderer.HideDefensiveIcons(addon)
    end
end

-- Resize both player and pet health bars to match visible defensive icon count.
-- (The target bar hugs the queue at a fixed gap and is not defensive-count-driven.)
local function ResizeHealthBars(addon, count)
    if UIHealthBar and UIHealthBar.ResizeToCount then UIHealthBar.ResizeToCount(addon, count) end
    if UIHealthBar and UIHealthBar.ResizePetToCount then UIHealthBar.ResizePetToCount(addon, count) end
    -- The power pair anchors to the outermost health bar, which the calls above may
    -- have just moved (e.g. the count-0 fallback position) - follow it, instead of
    -- floating over the empty cluster spot.
    if UIHealthBar and UIHealthBar.ReanchorPower then UIHealthBar.ReanchorPower(addon) end
end

-- Show or hide main-panel defensive icons based on a resolved queue.
local function ApplyMainPanelQueue(addon, defensiveQueue)
    if #defensiveQueue > 0 then
        if addon.defensiveIcons and #addon.defensiveIcons > 0 and UIRenderer and UIRenderer.ShowDefensiveIcons then
            UIRenderer.ShowDefensiveIcons(addon, defensiveQueue)
        end
        -- The cluster is padded with empty slots up to maxIcons (see ShowDefensiveIcons),
        -- so the health bar spans the full cluster width, not just the filled count.
        local def = addon:GetProfile() and addon:GetProfile().defensives
        local maxDefIcons = math_min((def and def.maxIcons) or 4, 7)
        ResizeHealthBars(addon, maxDefIcons)
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

--- Ally-low counts for the heal surface: how many party members are HURT enough
--- to be worth an area heal, and how many are in actual danger.
--- DIRECT per-ally threshold gates first - exact percentages, no accessibility
--- CVar, and they answer past party4. The alert-key path stays as the fallback
--- for clients where the gate can't answer; it has only ONE threshold, so the
--- urgent count comes back nil there and callers must not treat that as zero.
--- @return number|nil lowCount, number|nil urgentCount
local HEAL_LOW_PCT, HEAL_URGENT_PCT = 80, 50
local function GetAllyLowCounts(healing)
    if not BlizzardAPI then return nil, nil end
    local lowPct    = (healing and healing.lowThreshold) or HEAL_LOW_PCT
    local urgentPct = (healing and healing.urgentThreshold) or HEAL_URGENT_PCT
    if BlizzardAPI.GetPartyBelowCount then
        local low = BlizzardAPI.GetPartyBelowCount(lowPct)
        if low ~= nil then
            -- Skip the urgent scan when nobody is even hurt. The urgent threshold
            -- is BELOW the low one, so "below urgent" implies "below low" - a zero
            -- low count proves a zero urgent count without asking. Halves the gate
            -- calls in the common case (a healthy party, every rebuild).
            if low == 0 and urgentPct <= lowPct then return 0, 0 end
            return low, BlizzardAPI.GetPartyBelowCount(urgentPct)
        end
    end
    if BlizzardAPI.GetPartyLowCount then
        return BlizzardAPI.GetPartyLowCount(), nil
    end
    return nil, nil
end

-- Player health resolves to a BAND, not a boolean. Players think about defensives
-- in grades - "chip damage, use a wall" is a different decision from "I am about
-- to die, press the bubble" - and the threshold gates finally make the middle
-- grade knowable. Ascending boundaries; band 1 is the worst.
--
-- GRACEFUL DEGRADATION IS THE POINT HERE. Three sources, tried in order, each
-- coarser than the last, and NONE of them is assumed present:
--   1. threshold gates      - all three boundaries, exactly.
--   2. exact percent        - unrestricted contexts only, same three boundaries.
--   3. LowHealthFrame       - the vignette. An ESTIMATE, and it only knows two
--                             levels (~35% shown, ~20% critical), so it answers
--                             MAJOR and PANIC and never claims to see MITIGATE.
--                             That is honest: a band it cannot measure must read
--                             as healthy, not be guessed at.
-- If the gate layer is ever blocked, this file keeps working exactly as it did
-- before the layer existed. Nothing downstream may assume band 3 is reachable.
local HEALTH_BANDS = { 25, 50, 80 }
local BAND_PANIC, BAND_MAJOR, BAND_MITIGATE, BAND_HEALTHY = 1, 2, 3, 4
local healthBand, healthBandSource = BAND_HEALTHY, "none"
local healthBandEscalated = false

--- Which band + which source answered, for /jac inspect. Diagnostics only - which
--- is why the escalation suffix is composed HERE and not stored: the resolve path
--- runs every combat rebuild and must not allocate a string for a label nobody
--- reads unless the probe is open.
function DefensiveEngine.GetHealthBandInfo()
    return healthBand, healthBandEscalated and (healthBandSource .. "+dmg") or healthBandSource,
        HEALTH_BANDS
end

ResolveHealthState = function()
    local isLow
    healthBand, healthBandSource, healthBandEscalated = BAND_HEALTHY, "none", false
    -- 1) DIRECT: one call, short-circuiting at the first boundary it crosses, so a
    -- healthy player costs three gates and a dying one costs one. nil if ANY
    -- boundary could not be answered - a partial band is not a band.
    if BlizzardAPI and BlizzardAPI.GetHealthBand then
        local band = BlizzardAPI.GetHealthBand("player", HEALTH_BANDS)
        if band then
            healthBand, healthBandSource = band, "gate"
            isLow = band <= BAND_MAJOR
        end
    end
    -- 2) The exact percent, where the client still hands one over.
    if isLow == nil and BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
        local pct, estimated = BlizzardAPI.GetPlayerHealthPercentSafe()
        if pct and estimated == false then
            -- `<`, not `<=`: the gate path asks "below N%", and a player sitting
            -- exactly on a boundary must land in the same band either way.
            healthBand = BAND_HEALTHY
            for i = 1, #HEALTH_BANDS do
                if pct < HEALTH_BANDS[i] then healthBand = i break end
            end
            healthBandSource = "percent"
            isLow = healthBand <= BAND_MAJOR
        end
    end
    -- 3) The vignette. Two levels only - see the header.
    if isLow == nil then
        local low, isCritical
        if BlizzardAPI and BlizzardAPI.GetLowHealthState then
            low, isCritical = BlizzardAPI.GetLowHealthState()
        end
        healthBand = (isCritical == true and BAND_PANIC)
            or (low == true and BAND_MAJOR)
            or BAND_HEALTHY
        healthBandSource = "vignette"
        isLow = healthBand <= BAND_MAJOR
    end
    -- Escalation (validated in combat 2026-07-24): low health while STILL taking
    -- unabsorbed hits promotes to the critical tier - a stable 30% and a dropping
    -- 30% are different emergencies. The signal is suppressed while any absorb is
    -- up, so a shielded player never escalates on this path.
    -- A major defensive already rolling is the same kind of "already mitigated" as
    -- an absorb, so it blocks escalation too. The engine classifies it (validated
    -- in a follower-dungeon boss pull 12.0.7): only the COUNT of BIG_DEFENSIVE
    -- auras is read, never an aura's identity, so this survives combat secrecy
    -- where a curated spellId check cannot. nil = couldn't tell, so escalate as
    -- before rather than silently swallowing a real emergency.
    -- Now a promotion by ONE band rather than a jump straight to critical, which
    -- also gives the new middle band its escalation: 60% and dropping asks for a
    -- major, not just a wall.
    if healthBand > BAND_PANIC and healthBand < BAND_HEALTHY
       and BlizzardAPI and BlizzardAPI.IsActivelyTakingDamage
       and BlizzardAPI.IsActivelyTakingDamage()
       and not (BlizzardAPI.HasBigDefensive and BlizzardAPI.HasBigDefensive("player") == true) then
        healthBand = healthBand - 1
        healthBandEscalated = true
        isLow = healthBand <= BAND_MAJOR
    end
    return isLow
end


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

--------------------------------------------------------------------------------
-- Initialization & registration
--------------------------------------------------------------------------------

function DefensiveEngine.InitializeDefensiveSpells(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local specKey, playerClass
    if SpellDB and SpellDB.GetSpecKey then specKey, playerClass = SpellDB.GetSpecKey() end
    if not playerClass then return end

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

    -- One-time reseed: the group-heal list's contract changed to MULTI-TARGET
    -- HEALS ONLY (see SpellDB.CLASS_GROUPHEAL_DEFAULTS) after early builds
    -- seeded it with single-target heals. The feature never shipped, so a
    -- stored list from those builds is a stale seed, not player customization -
    -- replace it once. The populate-empty loop above can't do this: it only
    -- fires on lists that don't exist yet.
    if not cs.groupHealAoeReseed then
        cs.groupHealAoeReseed = true
        local defaults = SpellDB and SpellDB.CLASS_GROUPHEAL_DEFAULTS
            and SpellDB.ResolveDefaults(SpellDB.CLASS_GROUPHEAL_DEFAULTS, specKey, playerClass)
        if defaults then
            CopySpellList(cs, "groupHealSpells", defaults)
        end
    end

    -- Emergency Potion tile: default on, appended at the bottom. Removing it must STICK,
    -- so the suppressor is an explicit record of the player REMOVING it, not a record of
    -- us having added it once. The older "added once" flag could not tell a deliberate
    -- removal from a tile the list lost some other way, so any loss was permanent and
    -- Restore Class Defaults was the only way back. Absent the removal record we re-add,
    -- which means an accidental loss now heals itself on the next load.
    if SpellDB and SpellDB.EMERGENCY_POTION and not cs.emergencyPotionRemoved then
        EnsureEmergencyPotion(cs)
    end

    DefensiveEngine.RegisterDefensivesForTracking(addon)
end

-- Enables 12.0 compatibility when C_Spell.GetSpellCooldown returns secrets
function DefensiveEngine.RegisterDefensivesForTracking(addon)
    if not BlizzardAPI or not BlizzardAPI.RegisterSpellForTracking then return end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    if BlizzardAPI.ClearTrackedDefensives then
        BlizzardAPI.ClearTrackedDefensives()
    end

    -- Register all defensive spell lists, seeding local CD entries as we go.
    -- Seeding covers defensives already on cooldown at login/spec-change: without
    -- it, pre-existing CDs have no UNIT_SPELLCAST_SUCCEEDED event, so IsSpellReady
    -- fails-open for unflagged spells. OOC-only (safe to call always).
    for _, cfg in ipairs(SPELL_LIST_CONFIG) do
        local spellList = DefensiveEngine.GetClassSpellList(addon, cfg.listKey)
        if spellList then
            for _, entry in ipairs(spellList) do
                -- Only register positive entries (spells) - negative entries are items
                if entry and entry > 0 then
                    BlizzardAPI.RegisterSpellForTracking(entry, "defensive")
                    if BlizzardAPI.SeedLocalCooldownIfActive then
                        BlizzardAPI.SeedLocalCooldownIfActive(entry)
                    end
                end
            end
        end
    end

    -- Cache base cooldowns OOC so the "hold-worthy" test (long-CD panic button vs rotational
    -- heal) is a pure table read in combat - never a live/secret GetSpellBaseCooldown call.
    DefensiveEngine.PreCacheDefensiveCooldowns(addon)
end

function DefensiveEngine.RestoreDefensiveDefaults(addon, listType)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local specKey, playerClass
    if SpellDB and SpellDB.GetSpecKey then specKey, playerClass = SpellDB.GetSpecKey() end
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
                -- Restoring DEFAULTS must restore the Emergency Potion tile too: it is on by
                -- default, but lives outside CLASS_DEFENSIVE_DEFAULTS, so the copy above just
                -- dropped it. Re-adding here is also what the player asked for - the once-only
                -- seed flag exists so that manually REMOVING the tile sticks, and an explicit
                -- "restore defaults" is not a manual removal.
                if cfg.listKey == "defensiveSpells" then
                    cs.emergencyPotionRemoved = nil
                    EnsureEmergencyPotion(cs)
                end
            end
            break
        end
    end

    DefensiveEngine.RegisterDefensivesForTracking(addon)
    DefensiveEngine.OnHealthChanged(addon, nil, "player")
end

--------------------------------------------------------------------------------
-- Health change handler - main defensive queue dispatch
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
        if UINameplateOverlay.UpdatePowerBar then UINameplateOverlay.UpdatePowerBar(addon) end
    end

    -- Throttle defensive queue updates (expensive: table allocations, spell lookups).
    -- Unconditional: the synthetic periodic call (event=nil) used to bypass this,
    -- which let every dirty-flag burst trigger the full double-surface rebuild at
    -- frame rate instead of the 0.1s cadence the throttle promises. Returns false
    -- so the update loop keeps its dirty flag and retries next tick instead of
    -- treating the skipped rebuild as done.
    local now = GetTime()
    if now - lastHealthUpdate < HEALTH_UPDATE_THROTTLE then return false end
    lastHealthUpdate = now

    -- Skip queue work if neither path needs it
    local needsDefensives = (def and def.enabled) or (overlayActive and npo.showDefensives)
    if not needsDefensives then return end

    -- Health state - computed once, shared by main panel and overlay paths
    local inCombat = UnitAffectingCombat("player")
    local isLow = ResolveHealthState()

    -- Pet HEAL no longer lives in this queue at all - it moved to the Sustain slot, which can
    -- show it in combat. 12.0 makes UnitHealth("pet") secret, and a ranked list cannot hold a
    -- secret (ordering needs a comparison), so the queue could only ever offer it out of combat.
    -- The slot has no such limit: it hands the pet's health fraction to the engine as a curve
    -- index and lets the alpha decide, so the cue finally works when it actually matters.
    -- Pet REZ stays here - UnitIsDead/UnitExists are not secret, so it ranks normally.

    -- UnitIsDead/UnitExists are NOT secret - pet rez/summon works reliably in combat.
    -- Suppress when the player is petless on purpose (Lone Wolf / sacrificed pet) so
    -- those specs aren't nagged to summon a pet they intentionally don't run.
    local petStatus = BlizzardAPI and BlizzardAPI.GetPetStatus and BlizzardAPI.GetPetStatus()
    local petlessByChoice = BlizzardAPI and BlizzardAPI.IsPetlessByChoice and BlizzardAPI.IsPetlessByChoice()
    local petNeedsRez = (petStatus == "dead" or petStatus == "missing") and not petlessByChoice

    -- DPS exclusions shared by both paths (reuse pooled table)
    wipe(dpsQueueExclusions)
    if SpellQueue and SpellQueue.GetCurrentSpellQueue then
        local dpsQueue = SpellQueue.GetCurrentSpellQueue()
        local maxDpsIcons = profile.maxIcons or 4
        for i = 1, math_min(#dpsQueue, maxDpsIcons) do
            if dpsQueue[i] then dpsQueueExclusions[dpsQueue[i]] = true end
        end
    end

    -- The tank maintenance slot renders INSIDE the defensive cluster, so an ability shown
    -- there must not also be listed in the queue beside it - that is the same icon twice in
    -- one row. (Contrast the DPS queue, which is a separate cluster: Blood's Marrowrend is
    -- allowed to appear both there and in the slot, because those carry different meanings.)
    local MaintenanceTracker = MaintenanceTrackerRef
    if not MaintenanceTracker then
        MaintenanceTracker = LibStub("JustAC-MaintenanceTracker", true)
        MaintenanceTrackerRef = MaintenanceTracker
    end
    if MaintenanceTracker and MaintenanceTracker.IsSlotActive then
        local slotActive, mEntry = MaintenanceTracker.IsSlotActive(profile)
        -- Exclude ONLY the buff currently ON SCREEN in the slot. Excluding every maintained
        -- buff instead removed the one waiting its turn from the queue as well, so on Prot
        -- Ignore Pain vanished from both surfaces whenever Shield Block held the slot.
        -- The slot takes the most urgent; the other still flows through the normal queue.
        if slotActive and mEntry and mEntry.cast then
            dpsQueueExclusions[mEntry.cast] = true
        end
    end

    -- Main panel defensive queue (gated by defensives.enabled)
    if def and def.enabled then
        local defensiveQueue, mainAddedSet = DefensiveEngine.GetDefensiveSpellQueue(addon, isLow, inCombat, dpsQueueExclusions)
        local maxIcons = def.maxIcons or 4

        -- Pet rez/summon: HIGH priority - pet dead or missing (reliable in combat).
        -- Cap at one icon: getting the pet back is a single action, not a queue.
        if petNeedsRez and #defensiveQueue < maxIcons then
            AppendUsableSpells(addon, defensiveQueue, DefensiveEngine.GetClassSpellList(addon, "petRezSpells"), #defensiveQueue + 1, mainAddedSet)
        end

        -- (Pet heals are rendered by the Sustain slot now - see the note above.)
        ApplyMainPanelQueue(addon, defensiveQueue)
    else
        -- Defensives disabled on main panel: ensure icons are hidden
        HideDefensiveIconFrames(addon)
        ResizeHealthBars(addon, 0)
    end

    -- Nameplate overlay defensive queue - independent of defensives.enabled.
    -- Uses its own display mode and icon count settings.
    if overlayActive and npo.showDefensives then
        local npoDisplayMode = npo.defensiveDisplayMode or "always"
        local npoMaxIcons    = npo.maxDefensiveIcons or 3
        local npoQueue, npoAddedSet = DefensiveEngine.GetDefensiveSpellQueue(addon, isLow, inCombat, dpsQueueExclusions, {displayMode=npoDisplayMode, maxIcons=npoMaxIcons})

        -- Pet rez: parity with main panel (capped at one icon). Pet HEAL is the Sustain slot's
        -- now, on both surfaces - the overlay has its own maintenance icon and renders through
        -- the same RenderMaintenanceSlot, so it picks the cue up without a second code path.
        if petNeedsRez and #npoQueue < npoMaxIcons then
            AppendUsableSpells(addon, npoQueue, DefensiveEngine.GetClassSpellList(addon, "petRezSpells"), #npoQueue + 1, npoAddedSet)
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
--   1. Procced spells (instant/free cast available - highest priority)
--   2. Castable non-procced spells + usable items (mid priority, user list order)
--   3. Unusable spells (on CD or lacking resources - de-prioritized to end)
-- Ready-to-use defensives always appear before on-cooldown ones.
-- Aura-linked hints (SpellDB.DEFENSIVE_AURA_HINTS) can float a ready button into the
-- procced tier (its trigger aura is present, e.g. heavy stagger → purify) or sink one
-- to the unusable tier (its mitigation buff is already active).
-- Evaluate one positive list entry, memoized per GetTime() tick. The memo table
-- doubles as the tier-buffer element: spellID/isItem/isProcced/unusable/noResources
-- are the display fields AppendUsableSpells copies out; usableGate/realProc drive
-- the buffer choice. All the semantics from the old inline body live here - see the
-- comments; only the per-pass re-execution was removed.
local function EvalDefensiveSpell(entry, profile, locActive, now)
    local m = defensiveEvalMemo[entry]
    if not m then m = {}; defensiveEvalMemo[entry] = m
    elseif m.t == now then return m end
    m.t = now

    local resolvedID = BlizzardAPI.ResolveSpellID(entry)
    m.spellID, m.isItem = resolvedID, false
    m.isProcced, m.unusable, m.noResources, m.realProc = false, nil, nil, false

    local isUsable, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(resolvedID, profile)
    m.usableGate = isUsable or false
    if not isUsable then return m end

    -- Aura-linked ordering hints (tank active mitigation), base-resolved.
    local hint = SpellDB and SpellDB.GetDefensiveAuraHint and SpellDB.GetDefensiveAuraHint(entry)
    if hint and hint.sinkAura and not isProcced
        and BlizzardAPI.IsAuraActive("player", hint.sinkAura) then
        -- Mitigation buff already rolling: a re-press isn't the priority.
        -- Order-only park with the on-CD entries; the icon renders normally.
        m.unusable, m.noResources = true, false
    elseif isProcced then
        m.isProcced, m.realProc = true, true
    else
        -- Cooldown check via centralized IsSpellReady (handles isOnGCD,
        -- local CD w/ CDR cross-check, charge tracking, action bar fallback).
        -- Under loss of control the castability check is skipped: the CC
        -- reports every spell uncastable, which would collapse the ready vs
        -- on-CD split and shuffle the whole queue the moment a stun lands.
        -- IsSpellReady is local CD tracking, so it stays honest while CC'd -
        -- the order holds and the renderer greys the icons on its own.
        if not BlizzardAPI.IsSpellReady(resolvedID) then
            m.unusable, m.noResources = true, false
        elseif not locActive then
            local castable, notEnoughResources = BlizzardAPI.IsSpellUsable(resolvedID)
            if not castable then
                m.unusable, m.noResources = true, notEnoughResources
            end
        end
        if not m.unusable and hint and hint.floatAuras then
            -- Aura-linked float: trigger aura present and the button is ready
            -- (e.g. heavy stagger → purify). Treated like a proc: front of the
            -- queue, surfaced at any health level. Unlike real procs this only
            -- applies to READY buttons - the ready/resource checks above ran.
            for _, auraID in ipairs(hint.floatAuras) do
                if BlizzardAPI.IsAuraActive("player", auraID) then
                    m.isProcced = true
                    break
                end
            end
        end
    end
    return m
end

-- Item counterpart (negative list entry); same memo contract.
local function EvalDefensiveItem(entry, profile, now)
    local m = defensiveEvalMemo[entry]
    if not m then m = {}; defensiveEvalMemo[entry] = m
    elseif m.t == now then return m end
    m.t = now

    local itemID = -entry
    m.spellID, m.isItem = itemID, true
    m.isProcced, m.unusable, m.noResources, m.realProc = false, nil, nil, false

    -- Per-item settings: combat hide + linked aura suppression
    local itemSettings = profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
    local suppress = false
    if itemSettings then
        if itemSettings.combatHide and InCombatLockdown() then
            suppress = true
        end
        if not suppress and itemSettings.linkedAura and BlizzardAPI.IsAuraActive("player", itemSettings.linkedAura) then
            suppress = true
        end
    end
    if suppress then
        m.usableGate = false
        return m
    end
    local isUsable, hasItem = BlizzardAPI.CheckDefensiveItemState(itemID, profile)
    m.usableGate = hasItem or false
    if hasItem and not isUsable then
        -- Item on cooldown - show greyed out (parity with spell behavior)
        m.unusable, m.noResources = true, false
    end
    return m
end

local function GetUsableDefensiveSpells(addon, spellList, maxCount, alreadyAdded)
    wipe(usableResults)
    if not spellList or maxCount <= 0 then return usableResults end

    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return usableResults end

    alreadyAdded = alreadyAdded or {}
    wipe(usableAddedHere)
    wipe(proccedBuffer)
    wipe(nonProccedBuffer)
    wipe(unusableBuffer)

    local now = GetTime()
    -- Resolved once per build: stun/fear/silence is a state of the PLAYER, not of any
    -- one spell, so it must not feed the per-spell ordering decisions below.
    local locActive = BlizzardAPI.IsLossOfControlActive and BlizzardAPI.IsLossOfControlActive()

    -- Single pass: categorize spells into three priority tiers:
    --   1. Procced (instant/free cast - highest priority)
    --   2. Castable non-procced (usable, off CD - mid priority, user list order)
    --   3. Unusable (on CD or lacking resources - de-prioritized to end)
    -- Per-spell state comes from the per-tick memo; this loop is pure categorization.
    for _, entry in ipairs(spellList) do
        if entry and entry > 0 then
            local m = EvalDefensiveSpell(entry, profile, locActive, now)
            local resolvedID = m.spellID
            -- Check both the original and resolved IDs to handle proc injection cross-dedup
            if m.usableGate and not alreadyAdded[entry] and not alreadyAdded[resolvedID]
                and not usableAddedHere[resolvedID] then
                if m.unusable then
                    unusableBuffer[#unusableBuffer + 1] = m
                elseif m.realProc then
                    -- Check per-spell proc-priority setting (default true)
                    local spellSettings = profile.defensives.spellSettings and profile.defensives.spellSettings[resolvedID]
                    -- A free heal with nothing to heal (player provably full, nobody
                    -- low) does not get to reorder the cluster around itself - the
                    -- same gate that suppresses its glow, so the two can't disagree.
                    -- Still marked procced: if the situation changes mid-list it
                    -- renders normally on the next build.
                    local healNotNeeded = SpellDB and SpellDB.IsHealingSpell
                        and SpellDB.IsHealingSpell(resolvedID)
                        and BlizzardAPI.IsHealingUnneeded and BlizzardAPI.IsHealingUnneeded()
                    if healNotNeeded then
                        nonProccedBuffer[#nonProccedBuffer + 1] = m
                    elseif not spellSettings or spellSettings.procPriority ~= false then
                        proccedBuffer[#proccedBuffer + 1] = m
                    else
                        -- Procced but priority disabled: keep in list order, still marked procced for glow
                        nonProccedBuffer[#nonProccedBuffer + 1] = m
                    end
                elseif m.isProcced then
                    -- Aura-linked float (see EvalDefensiveSpell): proc-tier placement.
                    proccedBuffer[#proccedBuffer + 1] = m
                else
                    nonProccedBuffer[#nonProccedBuffer + 1] = m
                end
                usableAddedHere[resolvedID] = true
                usableAddedHere[entry] = true  -- also mark original so it isn't reprocessed
            end
        elseif entry and entry < 0 and not alreadyAdded[entry] and not alreadyAdded[-entry] and not usableAddedHere[entry] then
            local m = EvalDefensiveItem(entry, profile, now)
            if m.usableGate then
                if m.unusable then
                    unusableBuffer[#unusableBuffer + 1] = m
                else
                    nonProccedBuffer[#nonProccedBuffer + 1] = m
                end
                usableAddedHere[entry] = true
                usableAddedHere[m.spellID] = true
            end
        end
    end

    -- Merge in priority order: procced → castable → on-CD/unusable.
    for _, e in ipairs(proccedBuffer) do
        if #usableResults >= maxCount then break end
        usableResults[#usableResults + 1] = e
    end
    for _, e in ipairs(nonProccedBuffer) do
        if #usableResults >= maxCount then break end
        usableResults[#usableResults + 1] = e
    end
    for _, e in ipairs(unusableBuffer) do
        if #usableResults >= maxCount then break end
        usableResults[#usableResults + 1] = e
    end

    return usableResults
end

-- Append usable defensive spells from a spell list into a results table with dedup tracking.
-- If procsOnly is true, only entries with isProcced=true are appended.
-- The evaluation tables returned by GetUsableDefensiveSpells are per-tick memo state;
-- entries are COPIED into pooled result tables here so the queue a surface holds on to
-- is never mutated by a later pass or the other surface's build.
AppendUsableSpells = function(addon, results, spellList, maxIcons, alreadyAdded, procsOnly)
    if #results >= maxIcons then return end
    local spells = GetUsableDefensiveSpells(addon, spellList, maxIcons - #results, alreadyAdded)
    for _, m in ipairs(spells) do
        if not procsOnly or m.isProcced then
            PushEntry(results, m.spellID, m.isItem, m.isProcced, m.unusable, m.noResources)
            alreadyAdded[m.spellID] = true
        end
    end
end

-- Reorder a defensive list by health band, stable within each tier so the user's
-- configured order is preserved as the tiebreaker. One ordering per band, which is
-- the whole point of grading the health read: what leads the cluster should be what
-- the situation actually calls for.
--   MITIGATE - chip damage. Cheap walls lead, panic buttons sit at the bottom.
--   MAJOR    - a real hit taken. Big heals lead, walls behind them.
--   PANIC    - about to die. Immunity bubbles jump everything.
-- Returns a fresh table. ponytail: one small table per rebuild - rebuilds are
-- cached/throttled, so this is not worth pooling harder than it already is.
local emergencyOrderBuf = {}
local TIER_ORDER_BY_BAND = {
    [BAND_PANIC]    = { 1, 2, 4, 3 },  -- bubble -> big heal -> wall -> rest
    [BAND_MAJOR]    = { 2, 4, 1, 3 },  -- big heal -> wall -> bubble -> rest
    [BAND_MITIGATE] = { 4, 3, 2, 1 },  -- wall -> rest -> big heal -> bubble
}
local function OrderByEmergencyTier(list)
    wipe(emergencyOrderBuf)
    -- BAND_MAJOR is the fallback, not BAND_MITIGATE: this is only reached when the
    -- caller has decided the cluster needs reordering at all, and under-reacting to
    -- an unreadable band is the worse of the two mistakes.
    local order = TIER_ORDER_BY_BAND[healthBand] or TIER_ORDER_BY_BAND[BAND_MAJOR]
    local n = 0
    for i = 1, #order do
        local tier = order[i]
        for _, sid in ipairs(list) do
            if (SpellDB and SpellDB.GetDefenseTier and SpellDB.GetDefenseTier(sid) or 3) == tier then
                n = n + 1
                emergencyOrderBuf[n] = sid
            end
        end
    end
    -- Sweep whatever no order array named. Walking the order arrays used to mean a
    -- tier missing from one of them vanished from the queue outright - a lost
    -- defensive, not a mis-sorted one - enforced only by a comment. This turns that
    -- into "it trails", so adding a fifth tier can never silently hide a button.
    -- ponytail: O(n^2) sweep, but n is the icon count (<=7) and the guard means it
    -- does not run at all while the arrays are complete.
    if n < #list then
        for _, sid in ipairs(list) do
            local seen = false
            for j = 1, n do
                if emergencyOrderBuf[j] == sid then seen = true break end
            end
            if not seen then
                n = n + 1
                emergencyOrderBuf[n] = sid
            end
        end
    end
    return emergencyOrderBuf
end

-- Pre-cache base cooldowns for the current spec's defensive list. MUST run OUT of combat.
-- Only tier-2 big heals actually need it (bubbles + items are always hold-worthy), but
-- caching the whole list is cheap and keeps the combat-time reads pure table lookups.
-- GetBaseCooldownSeconds self-caches OOC (shared impl in BlizzardAPI/CooldownTracking).
function DefensiveEngine.PreCacheDefensiveCooldowns(addon)
    local list = DefensiveEngine.GetClassSpellList(addon, "defensiveSpells")
    if not list then return end
    for _, sid in ipairs(list) do
        if sid and sid > 0 then
            BlizzardAPI.GetBaseCooldownSeconds(sid)
            local resolved = BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(sid)
            if resolved and resolved ~= sid then BlizzardAPI.GetBaseCooldownSeconds(resolved) end
        end
    end
end

-- "Hold-worthy" = a genuine save-it-for-emergency panic button: immunity bubbles (always),
-- heal items (pots / healthstone), and big instant heals whose BASE cooldown is long enough
-- to be worth holding (>= HOLD_MIN_COOLDOWN). Short / resource-gated rotational heals (Death
-- Strike, Victory Rush, Word of Glory) have ~0 base CD, so they're NOT held - they show and
-- order normally. Base CD is a pure read from the OOC-populated cache; never a live/secret read.
local HOLD_MIN_COOLDOWN = 60  -- seconds

local function TierOf(sid)
    return (SpellDB and SpellDB.GetDefenseTier and SpellDB.GetDefenseTier(sid)) or 3
end

-- sid = raw list id (negative = heal item) OR a resolved entry's spellID with
-- isItem passed explicitly (entry.spellID, entry.isItem). Items are always held.
local function IsHoldWorthy(sid, isItem)
    if isItem then return true end
    if not sid then return false end
    if sid < 0 then return true end
    local tier = TierOf(sid)
    if tier == 1 then return true end                                   -- immunity bubble
    -- Tier 4 (pre-emptive walls) falls through to false below: they are meant to be pressed
    -- BEFORE the damage lands, so parking them until low health inverts the advice.
    -- Cache-only peek: this runs per defensive rebuild in combat, and the full
    -- getter would re-hit GetSpellBaseCooldown on every call while its result
    -- is secret (misses are deliberately not cached). The OOC precache fills it.
    if tier == 2 then return BlizzardAPI.PeekBaseCooldownSeconds(sid) >= HOLD_MIN_COOLDOWN end
    return false
end

-- Bottom-ordering rank above the low-health threshold: 0 = filler/mitigation + rotational
-- heals (stay up top in the user's order), 1 = hold-worthy big heal / heal item, 2 = immunity
-- bubble (very bottom). Combat-safe: tier is static, base CD is a cached OOC value.
local function EmergencyRank(sid)
    if not IsHoldWorthy(sid) then return 0 end
    if sid > 0 and TierOf(sid) == 1 then return 2 end  -- immunity bubble → very bottom
    return 1  -- hold-worthy big heal / heal item
end

-- Reorder so emergency panic buttons sink to the end (big heals, then bubbles at the very
-- bottom), keeping fillers/mitigation up top in the user's order. Stable within each rank.
-- Fresh pooled table; consume before the next call (mutually exclusive with
-- OrderByEmergencyTier - low- vs high-health branches).
local emergencyLastBuf = {}
local function OrderEmergencyLast(list)
    wipe(emergencyLastBuf)
    for rank = 0, 2 do
        for _, sid in ipairs(list) do
            if EmergencyRank(sid) == rank then
                emergencyLastBuf[#emergencyLastBuf + 1] = sid
            end
        end
    end
    return emergencyLastBuf
end

-- Display order: instant procs first, then unified defensive list in user priority order.
-- overrides (optional table): displayMode, maxIcons, showProcs - override profile defaults for
-- alternate display contexts (e.g. nameplate overlay uses its own mode and icon count).
-- Replace the Emergency Potion sentinel (a user-positioned tile in the defensive list)
-- with the chosen or best owned healing item, as an item entry. Returns the list as-is
-- when no sentinel is present; otherwise a resolved copy (never mutates the saved list).
-- choice: -1 = off (drop it), 0/nil = auto best owned, >0 = a specific owned item.
local emergencyResolveBuf = {}
local emergencyResolveTime, emergencyResolveSrc, emergencyResolveResult = -1, nil, nil
local function ResolveEmergencyDefensives(list, profile)
    if not list or not SpellDB or not SpellDB.EMERGENCY_POTION then return list end
    -- Per-tick cache: both surfaces resolve the same list within one rebuild, and the
    -- second call re-ran the sentinel scan + bag lookups and allocated a fresh copy.
    local now = GetTime()
    if emergencyResolveTime == now and emergencyResolveSrc == list then
        return emergencyResolveResult
    end

    local sentinel = SpellDB.EMERGENCY_POTION
    local hasSentinel = false
    for i = 1, #list do if list[i] == sentinel then hasSentinel = true; break end end

    local result
    if not hasSentinel then
        result = list
    else
        local choice = profile.defensives.emergencyPotionChoice
        local potID
        if choice == -1 then
            potID = nil  -- disabled via the tile dropdown
        elseif choice and choice > 0 and (GetItemCount(choice) or 0) > 0 then
            potID = choice
        elseif SpellDB.GetBestHealingItem then
            potID = SpellDB.GetBestHealingItem()
        end

        wipe(emergencyResolveBuf)
        for i = 1, #list do
            local e = list[i]
            if e == sentinel then
                if potID then emergencyResolveBuf[#emergencyResolveBuf + 1] = -potID end
            else
                emergencyResolveBuf[#emergencyResolveBuf + 1] = e
            end
        end
        result = emergencyResolveBuf
    end
    emergencyResolveTime, emergencyResolveSrc, emergencyResolveResult = now, list, result
    return result
end

function DefensiveEngine.GetDefensiveSpellQueue(addon, passedIsLow, passedInCombat, passedExclusions, overrides)
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return {} end

    if profile.debugMode then
        if defensiveBuildCount == 0 then
            defensiveResetTime = GetTime()
        end
        defensiveBuildCount = defensiveBuildCount + 1
    end

    local maxIcons = (overrides and overrides.maxIcons) or profile.defensives.maxIcons or 4
    local showProcs
    if overrides and overrides.showProcs ~= nil then
        showProcs = overrides.showProcs
    else
        showProcs = profile.defensives.showProcs ~= false
    end
    -- Per-surface persistent results array (overrides present = overlay build).
    -- Previous entries recycle through the entry pool; the returned array identity is
    -- stable per surface, so the overlay's cachedDefensiveQueue always sees the
    -- current build.
    local results = overrides and overlayResultsBuf or mainResultsBuf
    ReleaseResults(results)
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
        isLow = ResolveHealthState()
        inCombat = UnitAffectingCombat("player")
    end

    local displayMode = (overrides and overrides.displayMode) or profile.defensives.displayMode

    -- Out of combat: insert missing pre-combat buffs at the FRONT of the queue so the
    -- existing defensive icons shift back. Display rides the normal item-icon path; the
    -- click-to-use layer (UIPrecombatOverlay) sits invisibly over these icons, OOC only.
    -- Main panel only (not overrides) - the nameplate overlay has no click layers, and
    -- buffs on a target's nameplate make no sense.
    -- Explicitly gated on defensives.enabled (IsOfferingNow): pre-combat suggestions are a
    -- feature of the defensive bar. The current main-panel caller is already behind that
    -- flag, but the guarantee must hold even if a future caller reaches here without
    -- overrides. That gate is PrecombatEngine's because the DPS queue consults it too -
    -- an ability offered here as a clickable buff is dropped from the queue beside it.
    local PrecombatEngine = PrecombatEngineRef
    if not PrecombatEngine then
        PrecombatEngine = LibStub("JustAC-PrecombatEngine", true)
        PrecombatEngineRef = PrecombatEngine
    end
    if not inCombat and not overrides
        and PrecombatEngine and PrecombatEngine.IsOfferingNow
        and PrecombatEngine.IsOfferingNow(profile) then
        if PrecombatEngine.GetMissingBuffItems then
            for _, itemID in ipairs(PrecombatEngine.GetMissingBuffItems(profile.precombatBuffs.categories)) do
                if #results >= maxIcons then break end
                if not alreadyAdded[itemID] then
                    PushEntry(results, itemID, true, false, nil, nil, true)
                    alreadyAdded[itemID] = true
                end
            end
        end
        -- Class maintained buffs (poisons, imbues) as spell entries, gated by IsPlayerSpell.
        -- These deliberately BYPASS dpsQueueExclusions: this queue wins the tie. The offer
        -- here is clickable and the offensive one is not, so out of combat the buff belongs
        -- on this bar - honoring the exclusion would hide it from the only cluster that can
        -- act on it. The offensive queue drops its own copy in the same pass (RedundancyFilter
        -- asks IsOfferedNow), so the ability appears once, here.
        -- GetMissingClassBuffs returns distinct spells, so no in-loop dedupe is needed; mark
        -- alreadyAdded so the later proc/defensive passes don't re-add them.
        if PrecombatEngine.GetMissingClassBuffs then
            local offerTopoff = profile.precombatBuffs.topoffHeal == true
            local topoffPct = profile.precombatBuffs.topoffThreshold
            for _, spellID in ipairs(PrecombatEngine.GetMissingClassBuffs(offerTopoff, topoffPct)) do
                if #results >= maxIcons then break end
                -- topoff: the health top-off heal specifically, not the poisons/imbues beside
                -- it. Flagged because the renderer drives ITS alpha from a health curve - out
                -- of combat in the open world health is secret, so the arming signal ("regen
                -- is running") can only prove below FULL, not below the configured threshold.
                -- Without this the reminder nags at 99%.
                PushEntry(results, spellID, false, false, nil, nil,
                    true, (spellID == PrecombatEngine.offeredTopoffHeal) or nil)
                alreadyAdded[spellID] = true
            end
        end
    end

    -- Out-of-combat recovery is handled by the pre-combat buff path (Recuperate), so
    -- combatOnly hides everything else the moment combat ends. This gate sits ABOVE the
    -- proc passes deliberately: a procced self-heal is still a defensive suggestion, and
    -- leaving it below meant "In Combat Only" showed free heals out of combat forever.
    if displayMode == "combatOnly" and not inCombat then
        return results, alreadyAdded
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
                            -- Skip proc injection for spells with proc-priority disabled
                            local spellSettings = profile.defensives.spellSettings and profile.defensives.spellSettings[resolvedID]
                            local procPriority = not spellSettings or spellSettings.procPriority ~= false
                            if procPriority then
                                PushEntry(results, resolvedID, false, true)
                                alreadyAdded[resolvedID] = true
                                alreadyAdded[spellID] = true  -- also mark original ID
                            end
                        end
                    end
                end
            end
        end
    end

    -- Early exit: proc injection already filled the queue
    if #results >= maxIcons then return results, alreadyAdded end

    -- Unified defensive spell list (user-ordered priority); resolve the Emergency Potion
    -- tile's sentinel into the chosen/best owned item before the usability passes.
    local defensiveSpells = DefensiveEngine.GetClassSpellList(addon, "defensiveSpells")
    defensiveSpells = ResolveEmergencyDefensives(defensiveSpells, profile)

    -- Procced spells from configured list (any health level)
    AppendUsableSpells(addon, results, defensiveSpells, maxIcons, alreadyAdded, true)

    -- Early exit: proc passes filled the queue
    if #results >= maxIcons then return results, alreadyAdded end

    -- Group heals: offered while at least one party member is below the alert
    -- threshold. Two constraints, both measured in a live dungeon run:
    --   * IN COMBAT ONLY. The low-keys persist out of combat (a party walking
    --     around at partial health keeps the count non-zero), so without this
    --     the heal list would sit on screen permanently between pulls.
    --   * Availability, not health, decides which heal shows: the count says
    --     SOMEONE needs healing, never who or how badly - that stays the
    --     player's read off their own frames.
    -- Placed above the self-defensive pass on purpose: with allies dropping,
    -- the heals are the answer, and the cluster is only maxIcons wide.
    if inCombat and profile.healing and profile.healing.enabled
       and SpellDB and SpellDB.SpecHasGroupHeals and SpellDB.SpecHasGroupHeals()
       and (GetAllyLowCounts(profile.healing) or 0) > 0 then
        local healList = DefensiveEngine.GetClassSpellList(addon, "groupHealSpells")
        if healList then
            AppendUsableSpells(addon, results, healList, maxIcons, alreadyAdded)
            if #results >= maxIcons then return results, alreadyAdded end
        end
    end

    -- Past the gate above (which returned early out of combat), combatOnly implies in-combat
    local showAllAvailable = displayMode == "always" or displayMode == "combatOnly"
    if showAllAvailable or isLow then
        -- Order the unified list by health state: below ~35% survival floats up; above it,
        -- emergency panic buttons sink to the end. Procs were already placed on top by the
        -- proc pass; on-CD spells still sink within GetUsableDefensiveSpells.
        local listToShow = defensiveSpells
        if defensiveSpells then
            if healthBand < BAND_HEALTHY then
                -- Hurt at all: one ordering per band - walls, then majors, then
                -- bubbles as it gets worse. See OrderByEmergencyTier.
                listToShow = OrderByEmergencyTier(defensiveSpells)
            else
                -- At (or unreadably near) full: park emergency panic buttons at the end
                -- (big heals, immunity bubbles at the very bottom); fillers stay up top.
                -- Also where every client whose band read is blocked above MAJOR lands,
                -- which is exactly the behaviour that shipped before bands existed.
                listToShow = OrderEmergencyLast(defensiveSpells)
            end
        end
        AppendUsableSpells(addon, results, listToShow, maxIcons, alreadyAdded)

        -- With "hide until low" on and above the threshold, don't remove the parked panic
        -- buttons - flag them so the renderer shows them desaturated with a centered WAIT
        -- tag. Procs are exempt (free, highlighted opportunities placed by the proc pass).
        if not isLow and profile.defensives.hideEmergencyUntilLow then
            for _, entry in ipairs(results) do
                -- Pre-combat buffs (food/flask/class buffs) are use-now, not held-back
                -- emergency buttons: never tag them waiting, or their icon shows a "wait"
                -- label that collides with the OOC click overlay's "click"/"wait" hint.
                if not entry.isProcced and not entry.precombat and IsHoldWorthy(entry.spellID, entry.isItem) then
                    entry.waiting = true
                end
            end
        end
    end

    return results, alreadyAdded
end

--------------------------------------------------------------------------------
-- Emergency group heal - the Sustain slot's OH SHIT claimant. When several
-- allies are low at once, the biggest ready group cooldown claims defensive
-- slot 0 (arbitrated in UIRenderer.RenderMaintenanceSlot: CC escape outranks
-- it, it outranks the pet heal's secret alpha layer - legal only because this
-- claim is PLAIN). Targeted heals are out of scope by design: directing a heal
-- at a person is group-frame territory; this addon only suggests
-- press-and-done casts.
--------------------------------------------------------------------------------

local emergencyHealID = nil
local emergencyCheckTime = 0
local emergencyHeldUntil = 0    -- sticky hold: the low-flags flap at the
                                -- threshold (measured in a live dungeon run),
                                -- so an emergency, once called, holds ~8s
local EMERGENCY_MEMO = 0.1
local EMERGENCY_HOLD_SECONDS = 8

--- First spell in `ladder` that is known and ready (local CD tracking).
local function FirstReadyInLadder(ladder)
    if not ladder then return nil end
    for i = 1, #ladder do
        local id = ladder[i]
        if BlizzardAPI.IsSpellAvailable(id)
           and (not BlizzardAPI.IsSpellReady or BlizzardAPI.IsSpellReady(id)) then
            return id
        end
    end
    return nil
end

--- SpellID of the emergency group heal while the claim is live, else nil.
--- Memoized at 0.1s - the render tick calls this every frame.
function DefensiveEngine.GetEmergencyHealID(addon)
    local now = GetTime()
    if now - emergencyCheckTime < EMERGENCY_MEMO then
        return emergencyHealID
    end
    emergencyCheckTime = now
    emergencyHealID = nil

    local profile = addon and addon:GetProfile()
    local healing = profile and profile.healing
    if not (healing and healing.enabled) then return nil end
    if not (SpellDB and SpellDB.SpecHasGroupHeals and SpellDB.SpecHasGroupHeals()) then return nil end
    if not UnitAffectingCombat("player") then return nil end
    if not BlizzardAPI then return nil end

    -- Two ways in, and the second is the one direct gates made possible: several
    -- allies merely hurt, OR anyone in real danger. The alert-key fallback can
    -- only express the first (one threshold), so urgent is nil there rather than
    -- zero - and nil must not read as "nobody is in danger".
    local low, urgent = GetAllyLowCounts(healing)
    if (low or 0) >= (healing.emergencyCount or 3) or (urgent or 0) > 0 then
        emergencyHeldUntil = now + EMERGENCY_HOLD_SECONDS
    end
    if now >= emergencyHeldUntil then return nil end

    local specKey = SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    emergencyHealID = specKey
        and FirstReadyInLadder(SpellDB.HEAL_EMERGENCY_LADDER and SpellDB.HEAL_EMERGENCY_LADDER[specKey])
        or nil
    return emergencyHealID
end

function DefensiveEngine.GetBuildStats()
    return {
        buildCount = defensiveBuildCount,
        resetTime = defensiveResetTime,
    }
end

function DefensiveEngine.ResetBuildStats()
    defensiveBuildCount = 0
    defensiveResetTime = GetTime()
end

