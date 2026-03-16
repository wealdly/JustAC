-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- BurstInjectionEngine.lua — Burst injection system: detect burst windows from
-- Blizzard's Assisted Combat recommendations and inject user-configured priority
-- spells at position 1.  Mirrors GapCloserEngine architecture.
--
-- Primary trigger mechanism: any Blizzard-recommended spell with a base
-- cooldown >= threshold (default 45s) starts a burst window.  Users can
-- optionally configure an explicit trigger spell list to override.

local BurstInjectionEngine = LibStub:NewLibrary("JustAC-BurstInjectionEngine", 2)
if not BurstInjectionEngine then return end

-- Hot path cache
local GetSpellBaseCooldown = GetSpellBaseCooldown ---@diagnostic disable-line: undefined-global
local ipairs = ipairs
local issecretvalue = issecretvalue ---@diagnostic disable-line: undefined-global

-- Module references (resolved at load time)
local BlizzardAPI      = LibStub("JustAC-BlizzardAPI", true)
local SpellDB          = LibStub("JustAC-SpellDB", true)

--------------------------------------------------------------------------------
-- Cached state (wiped on spec/profile change)
--------------------------------------------------------------------------------

local cachedTriggerSpells = nil    -- explicit override set: { [spellID] = true } or empty
local cachedHasExplicitTriggers = false -- true when user/defaults populate trigger list
local cachedInjectionSpells = nil  -- resolved injection list: { spellID, ... }
local cachedSpecKey = nil
local cachedTriggerThreshold = nil -- CD threshold in seconds

--- Cache of base cooldown durations (seconds) for spells seen via CheckTrigger.
--- Populated lazily; survives across cache invalidations (spell CDs don't change).
local baseCooldownCache = {}       -- { [spellID] = seconds }

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Build the spec key for the current player.
local function GetSpecKey()
    if SpellDB and SpellDB.GetSpecKey then
        return SpellDB.GetSpecKey()
    end
    return nil
end

--- Return the base cooldown of a spell in seconds (cached).
--- Uses GetSpellBaseCooldown (returns ms). In combat this API returns secret
--- values — never cache secrets (they compare truthy and break threshold logic).
local function GetBaseCooldownSeconds(spellID)
    if not spellID or spellID <= 0 then return 0 end
    local cached = baseCooldownCache[spellID]
    if cached then return cached end
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if not ms or (issecretvalue and issecretvalue(ms)) then return 0 end
    local sec = ms > 0 and (ms / 1000) or 0
    baseCooldownCache[spellID] = sec
    return sec
end

--- Resolve the trigger CD threshold from profile or SpellDB constant.
local function ResolveTriggerThreshold(addon)
    if cachedTriggerThreshold then return cachedTriggerThreshold end
    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    if bi and bi.triggerThreshold and bi.triggerThreshold > 0 then
        cachedTriggerThreshold = bi.triggerThreshold
    else
        cachedTriggerThreshold = (SpellDB and SpellDB.BURST_TRIGGER_THRESHOLD_DEFAULT) or 45
    end
    return cachedTriggerThreshold
end

--- Resolve the explicit trigger spell set for the current spec (override only).
--- If the user has configured trigger spells, returns a populated set.
--- Otherwise returns an empty table (threshold-based detection is primary).
local function ResolveTriggerSpells(addon)
    local specKey = GetSpecKey()
    if not specKey then return nil end

    if cachedTriggerSpells and cachedSpecKey == specKey then
        return cachedTriggerSpells
    end

    cachedSpecKey = specKey
    cachedTriggerSpells = {}
    cachedHasExplicitTriggers = false

    -- Check profile for user-configured trigger list (explicit override)
    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    if bi and bi.triggerSpells and bi.triggerSpells[specKey] and #bi.triggerSpells[specKey] > 0 then
        cachedHasExplicitTriggers = true
        for _, spellID in ipairs(bi.triggerSpells[specKey]) do
            if spellID and spellID > 0 then
                cachedTriggerSpells[spellID] = true
                -- Also map talent-overridden form
                local resolved = BlizzardAPI.ResolveSpellID(spellID)
                if resolved ~= spellID then
                    cachedTriggerSpells[resolved] = true
                end
            end
        end
    end

    return cachedTriggerSpells
end

--- Resolve the injection spell list for the current spec.
--- Reads from profile (user-configured) with SpellDB defaults as fallback.
--- Returns an ordered array of spell IDs, or nil.
local function ResolveInjectionSpells(addon)
    local specKey = GetSpecKey()
    if not specKey then return nil end

    if cachedInjectionSpells and cachedSpecKey == specKey then
        return cachedInjectionSpells
    end

    -- Check profile for user-configured list
    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    if bi and bi.injectionSpells and bi.injectionSpells[specKey] and #bi.injectionSpells[specKey] > 0 then
        cachedInjectionSpells = bi.injectionSpells[specKey]
        return cachedInjectionSpells
    end

    -- Fall back to SpellDB defaults
    if SpellDB and SpellDB.CLASS_BURST_INJECTION_DEFAULTS then
        local defaults = SpellDB.CLASS_BURST_INJECTION_DEFAULTS[specKey]
        if defaults then
            cachedInjectionSpells = defaults
            return cachedInjectionSpells
        end
    end

    cachedInjectionSpells = nil
    return nil
end

--- Evaluate a single injection candidate.
--- Returns resolvedID, baseID on success, or nil.
local function TryInjectionCandidate(spellID, addedSpellIDs)
    if not spellID or spellID <= 0 then return nil end
    local resolvedID = BlizzardAPI.ResolveSpellID(spellID)

    -- Dedup: skip if already shown in the queue
    if addedSpellIDs and (addedSpellIDs[resolvedID] or addedSpellIDs[spellID]) then
        return nil
    end

    -- Known check: filter out spells the player doesn't have
    if not BlizzardAPI.IsSpellAvailable(resolvedID) then return nil end

    -- Register for local CD tracking (idempotent)
    if BlizzardAPI.RegisterSpellForTracking then
        BlizzardAPI.RegisterSpellForTracking(resolvedID, "burst")
    end

    -- Cooldown check: don't suggest spells on CD
    if not BlizzardAPI.IsSpellReady(resolvedID) then return nil end

    return resolvedID, spellID
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Get the spec key for the current player (exposed for Options).
function BurstInjectionEngine.GetBurstSpecKey()
    return GetSpecKey()
end

--- Return rotation spells that meet the current CD threshold.
--- Used by Options to show which spells would trigger a burst window.
--- Returns: { {spellID=number, name=string, baseCd=number}, ... } or empty table.
function BurstInjectionEngine.GetDetectedTriggers(addon)
    local result = {}
    if not BlizzardAPI or not BlizzardAPI.GetRotationSpells then return result end
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells then return result end

    local threshold = ResolveTriggerThreshold(addon)
    local seen = {}
    for _, spellID in ipairs(rotationSpells) do
        if spellID and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            local baseCd = GetBaseCooldownSeconds(spellID)
            if baseCd >= threshold then
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or tostring(spellID)
                result[#result + 1] = { spellID = spellID, name = name, baseCd = baseCd }
            end
        end
    end
    return result
end

--- Check if the given primarySpellID (Blizzard's pos-1 recommendation) is a
--- Per-frame trigger check: returns true when the position-1 spell qualifies
--- as a burst trigger AND at least one injection spell is usable.
--- No time-based window — injection only occurs while the trigger spell is
--- actively recommended by Blizzard in position 1.
--- Two-tier detection:
---   1. If user has explicit trigger spells configured, match against those.
---   2. Otherwise, trigger on any spell with base CD >= threshold (default 45s).
function BurstInjectionEngine.CheckTrigger(addon, primarySpellID)
    if not addon or not addon.db or not addon.db.profile then return false end
    local bi = addon.db.profile.burstInjection
    if not bi or not bi.enabled then return false end

    if not primarySpellID or primarySpellID <= 0 then return false end

    local triggers = ResolveTriggerSpells(addon)
    local isTrigger = false

    if cachedHasExplicitTriggers and triggers then
        -- Tier 1: explicit trigger list (user override)
        isTrigger = triggers[primarySpellID]
        if not isTrigger then
            local displayID = BlizzardAPI.GetDisplaySpellID(primarySpellID)
            if displayID and displayID ~= primarySpellID then
                isTrigger = triggers[displayID]
            end
        end
    else
        -- Tier 2: CD threshold detection (primary mechanism)
        local threshold = ResolveTriggerThreshold(addon)
        local baseCd = GetBaseCooldownSeconds(primarySpellID)
        if baseCd < threshold then
            -- Also check the display/override form
            local displayID = BlizzardAPI.GetDisplaySpellID(primarySpellID)
            if displayID and displayID ~= primarySpellID then
                baseCd = GetBaseCooldownSeconds(displayID)
            end
        end
        isTrigger = (baseCd >= threshold)
    end

    return isTrigger
end

--- Returns true if a burst window is currently active.
--- Kept for API compatibility (UI glow checks, etc.) — now always false
--- since the window concept is removed.
function BurstInjectionEngine.IsBurstActive()
    return false
end

--- No-op — window concept removed. Kept for API compatibility.
function BurstInjectionEngine.ClearBurstState()
end

--- Invalidate cached spell lists (spec change, profile change).
function BurstInjectionEngine.InvalidateBurstCache()
    cachedTriggerSpells = nil
    cachedHasExplicitTriggers = false
    cachedInjectionSpells = nil
    cachedSpecKey = nil
    cachedTriggerThreshold = nil
end

--- Returns the first usable injection spell for the current burst window.
--- Returns: resolvedID, baseID  or nil.
function BurstInjectionEngine.GetBurstInjectionSpell(addon, addedSpellIDs)
    if not addon or not addon.db or not addon.db.profile then return nil end

    local spellList = ResolveInjectionSpells(addon)
    if not spellList then return nil end

    for _, spellID in ipairs(spellList) do
        local resolved, base = TryInjectionCandidate(spellID, addedSpellIDs)
        if resolved then return resolved, base end
    end

    -- All injection spells on CD or already shown — nothing to inject.
    return nil
end

--- Mark all burst injection spell IDs into a set.
--- Called by SpellQueue to suppress these from the rotation list when burst
--- injection is enabled — our insertion controls when they appear.
function BurstInjectionEngine.MarkBurstInjectionSpellIDs(addon, spellIDSet)
    if not addon or not spellIDSet then return end
    local spellList = ResolveInjectionSpells(addon)
    if not spellList then return end
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

--- Initialize burst injection defaults for the current spec if not yet populated.
--- Trigger spells are NOT auto-populated — CD threshold is the default mechanism.
--- Users who want explicit triggers can add them manually in Options.
function BurstInjectionEngine.InitializeBurstInjection(addon)
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end

    if not profile.burstInjection then
        profile.burstInjection = {
            enabled = false,  -- experimental: opt-in
            showGlow = true,
            triggerSpells = {},
            injectionSpells = {},
        }
    end
    if not profile.burstInjection.triggerSpells then
        profile.burstInjection.triggerSpells = {}
    end
    if not profile.burstInjection.injectionSpells then
        profile.burstInjection.injectionSpells = {}
    end

    local specKey = GetSpecKey()
    if not specKey then return end

    -- Trigger spells: left empty by default (CD threshold is primary detection)
    -- Users can add explicit overrides via Options

    -- Populate injection spells from defaults if empty
    if not profile.burstInjection.injectionSpells[specKey]
       or #profile.burstInjection.injectionSpells[specKey] == 0 then
        local injectionDefaults = SpellDB and SpellDB.CLASS_BURST_INJECTION_DEFAULTS
            and SpellDB.CLASS_BURST_INJECTION_DEFAULTS[specKey]
        if injectionDefaults then
            profile.burstInjection.injectionSpells[specKey] = {}
            for i, spellID in ipairs(injectionDefaults) do
                profile.burstInjection.injectionSpells[specKey][i] = spellID
            end
        end
    end

    BurstInjectionEngine.InvalidateBurstCache()

    -- Pre-cache base cooldowns AND register for local CD tracking while out
    -- of combat. GetSpellBaseCooldown and RegisterSpellForTracking both need
    -- non-secret API values — in combat they fail silently.
    local injList = profile.burstInjection.injectionSpells[specKey]
    if injList then
        for _, sid in ipairs(injList) do
            if sid and sid > 0 then
                GetBaseCooldownSeconds(sid)
                local resolvedID = BlizzardAPI.ResolveSpellID(sid)
                if BlizzardAPI.RegisterSpellForTracking then
                    BlizzardAPI.RegisterSpellForTracking(resolvedID, "burst")
                    if resolvedID ~= sid then
                        BlizzardAPI.RegisterSpellForTracking(sid, "burst")
                    end
                end
            end
        end
    end
end
