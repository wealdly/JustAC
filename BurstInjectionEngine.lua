-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- BurstInjectionEngine.lua — Burst injection system: detect burst windows from
-- Blizzard's Assisted Combat recommendations and inject user-configured priority
-- spells at position 1.  Mirrors GapCloserEngine architecture.
--
-- Trigger detection: curated per-spec major CDs (SpellDB.CLASS_BURST_TRIGGER_DEFAULTS)
-- that Blizzard recommends when burst is appropriate.  Users can optionally
-- configure an explicit trigger spell list to override.

local BurstInjectionEngine = LibStub:NewLibrary("JustAC-BurstInjectionEngine", 3)
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

local cachedTriggerSpells = nil    -- resolved trigger set: { [spellID] = true }
local cachedTriggerSource = nil   -- "explicit", "defaults", or nil
local cachedInjectionSpells = nil  -- resolved injection list: { spellID, ... }
local cachedSpecKey = nil

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
--- Uses GetSpellBaseCooldown (returns ms) with fallback to C_Spell.GetSpellCharges
--- cooldownDuration for charge-based spells where GetSpellBaseCooldown returns 0.
--- Must be called out of combat — both APIs return secrets in combat.
local function GetBaseCooldownSeconds(spellID)
    if not spellID or spellID <= 0 then return 0 end
    local cached = baseCooldownCache[spellID]
    if cached then return cached end

    local sec = 0

    -- Try GetSpellBaseCooldown first (returns ms)
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if ms and not (issecretvalue and issecretvalue(ms)) and ms > 0 then
        sec = ms / 1000
    end

    -- Fallback: charge-based spells report 0 base CD but have a recharge time
    if sec == 0 and C_Spell and C_Spell.GetSpellCharges then
        local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and charges then
            local dur = charges.cooldownDuration
            if dur and not (issecretvalue and issecretvalue(dur)) and dur > 0 then
                sec = dur
            end
        end
    end

    baseCooldownCache[spellID] = sec
    return sec
end

--- Resolve the trigger spell set for the current spec.
--- Priority: 1) user-configured explicit overrides, 2) SpellDB curated defaults.
--- Returns a set { [spellID] = true } or nil.
local function ResolveTriggerSpells(addon)
    local specKey = GetSpecKey()
    if not specKey then return nil end

    if cachedTriggerSpells and cachedSpecKey == specKey then
        return cachedTriggerSpells
    end

    cachedSpecKey = specKey
    cachedTriggerSpells = {}
    cachedTriggerSource = nil

    -- Tier 1: user-configured trigger list (explicit override)
    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    if bi and bi.triggerSpells and bi.triggerSpells[specKey] and #bi.triggerSpells[specKey] > 0 then
        cachedTriggerSource = "explicit"
        for _, spellID in ipairs(bi.triggerSpells[specKey]) do
            if spellID and spellID > 0 then
                cachedTriggerSpells[spellID] = true
                local resolved = BlizzardAPI.ResolveSpellID(spellID)
                if resolved ~= spellID then
                    cachedTriggerSpells[resolved] = true
                end
            end
        end
        return cachedTriggerSpells
    end

    -- Tier 2: SpellDB curated defaults for this spec
    if SpellDB and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS then
        local defaults = SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
        if defaults and #defaults > 0 then
            cachedTriggerSource = "defaults"
            for _, spellID in ipairs(defaults) do
                if spellID and spellID > 0 then
                    cachedTriggerSpells[spellID] = true
                    local resolved = BlizzardAPI.ResolveSpellID(spellID)
                    if resolved ~= spellID then
                        cachedTriggerSpells[resolved] = true
                    end
                end
            end
        end
    end

    return cachedTriggerSpells
end

--- Resolve the injection spell list for the current spec.
--- Reads from profile (user-configured) with SpellDB defaults as fallback.
--- Dynamically registers all resolved spells for local CD tracking.
--- Returns an ordered array of spell IDs, or nil.
local function ResolveInjectionSpells(addon)
    local specKey = GetSpecKey()
    if not specKey then return nil end

    if cachedInjectionSpells and cachedSpecKey == specKey then
        return cachedInjectionSpells
    end

    cachedSpecKey = specKey
    local spellList

    -- Check profile for user-configured list
    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    if bi and bi.injectionSpells and bi.injectionSpells[specKey] and #bi.injectionSpells[specKey] > 0 then
        spellList = bi.injectionSpells[specKey]
    end

    -- Fall back to SpellDB defaults
    if not spellList and SpellDB and SpellDB.CLASS_BURST_INJECTION_DEFAULTS then
        local defaults = SpellDB.CLASS_BURST_INJECTION_DEFAULTS[specKey]
        if defaults then
            spellList = defaults
        end
    end

    if not spellList then
        cachedInjectionSpells = nil
        return nil
    end

    -- Register every injection spell for local CD tracking (idempotent).
    -- This ensures custom user-added spells get tracked dynamically.
    if BlizzardAPI.RegisterSpellForTracking then
        for _, sid in ipairs(spellList) do
            if sid and sid > 0 then
                local resolvedID = BlizzardAPI.ResolveSpellID(sid)
                BlizzardAPI.RegisterSpellForTracking(resolvedID, "burst")
                if resolvedID ~= sid then
                    BlizzardAPI.RegisterSpellForTracking(sid, "burst")
                end
                -- Pre-cache base CD while we're at it (no-op if already cached)
                GetBaseCooldownSeconds(resolvedID)
            end
        end
    end

    cachedInjectionSpells = spellList
    return cachedInjectionSpells
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

--- Return the active trigger spell list for the current spec.
--- Shows explicit overrides if configured, otherwise SpellDB curated defaults.
--- Filters by IsSpellAvailable (talent alternatives the player doesn't know are hidden).
--- Returns: { {spellID=number, name=string, baseCd=number}, ... } or empty table.
function BurstInjectionEngine.GetDetectedTriggers(addon)
    local result = {}
    ResolveTriggerSpells(addon)  -- ensure cache is populated

    -- Build source list from either explicit overrides or SpellDB defaults
    local sourceList
    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    local specKey = GetSpecKey()

    if cachedTriggerSource == "explicit" and bi and bi.triggerSpells and specKey then
        sourceList = bi.triggerSpells[specKey]
    elseif SpellDB and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS and specKey then
        sourceList = SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
    end

    if not sourceList then return result end

    local seen = {}
    for _, spellID in ipairs(sourceList) do
        if spellID and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            -- Filter to spells the player actually knows (e.g. Incarnation vs Berserk)
            local resolvedID = BlizzardAPI.ResolveSpellID(spellID)
            local checkID = (BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(resolvedID)) and resolvedID
                or (BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)) and spellID
                or nil
            if checkID then
                local baseCd = GetBaseCooldownSeconds(checkID)
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(checkID)
                local name = spellInfo and spellInfo.name or tostring(checkID)
                result[#result + 1] = { spellID = checkID, name = name, baseCd = baseCd }
            end
        end
    end
    return result
end

--- Per-frame trigger check: returns true when the position-1 spell qualifies
--- as a burst trigger.
--- No time-based window — injection only occurs while the trigger spell is
--- actively recommended by Blizzard in position 1.
--- Matches against: 1) user explicit overrides, or 2) SpellDB curated defaults.
function BurstInjectionEngine.CheckTrigger(addon, primarySpellID)
    if not addon or not addon.db or not addon.db.profile then return false end
    local bi = addon.db.profile.burstInjection
    if not bi or not bi.enabled then return false end

    if not primarySpellID or primarySpellID <= 0 then return false end

    local triggers = ResolveTriggerSpells(addon)
    if not triggers then return false end

    -- Direct match
    if triggers[primarySpellID] then return true end

    -- Check display/override form (talent-overridden spells)
    local displayID = BlizzardAPI.GetDisplaySpellID(primarySpellID)
    if displayID and displayID ~= primarySpellID and triggers[displayID] then
        return true
    end

    return false
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
    cachedTriggerSource = nil
    cachedInjectionSpells = nil
    cachedSpecKey = nil
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
--- Trigger spells use SpellDB curated defaults unless overridden by the user.
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

    -- Trigger spells: SpellDB curated defaults used automatically;
    -- users can add explicit overrides via Options

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
                -- Seed local CD if spell is already on cooldown at init time.
                -- Without this, spells on CD from a previous session have no
                -- UNIT_SPELLCAST_SUCCEEDED event, so IsSpellReady fails-open.
                if BlizzardAPI.SeedLocalCooldownIfActive then
                    BlizzardAPI.SeedLocalCooldownIfActive(resolvedID)
                    if resolvedID ~= sid then
                        BlizzardAPI.SeedLocalCooldownIfActive(sid)
                    end
                end
            end
        end
    end

    -- Pre-cache base cooldowns for trigger defaults (for debug display)
    if SpellDB and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS then
        local trigDefaults = SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
        if trigDefaults then
            for _, sid in ipairs(trigDefaults) do
                if sid and sid > 0 then
                    GetBaseCooldownSeconds(sid)
                end
            end
        end
    end

    -- Pre-cache base cooldowns for rotation spells (general cache warming)
    BurstInjectionEngine.PreCacheRotationCooldowns()
end

--- Pre-cache base cooldowns for all spells in the Blizzard rotation list.
--- Must be called OUT of combat (GetSpellBaseCooldown returns secrets in combat).
--- Safe to call multiple times — already-cached spells are skipped.
function BurstInjectionEngine.PreCacheRotationCooldowns()
    if not BlizzardAPI or not BlizzardAPI.GetRotationSpells then return end
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells then return end
    for _, spellID in ipairs(rotationSpells) do
        if spellID and spellID > 0 then
            GetBaseCooldownSeconds(spellID)
        end
    end
end

--- Return the cached base cooldown for a spell (seconds), or 0 if not cached.
--- Combat-safe: reads from the pre-populated cache, never calls GetSpellBaseCooldown.
function BurstInjectionEngine.GetCachedBaseCooldown(spellID)
    if not spellID then return 0 end
    return baseCooldownCache[spellID] or 0
end
