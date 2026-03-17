-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- BurstInjectionEngine.lua — Burst injection system: detect burst windows and
-- inject user-configured priority spells at position 1.
--
-- Two-phase trigger detection:
--   Phase 1 ("pending"): Blizzard recommends a trigger CD at position 1.
--     → Show burst glow on the trigger to signal "press this to start burst".
--     → No injection yet (let Blizzard's recommendation stand).
--   Phase 2 ("active"): Trigger CD's self-buff aura is active on the player.
--     → Inject priority spells from the injection list at position 1.
--     → Window ends when aura expires OR all injection spells are on cooldown.
--
-- Trigger spells: curated per-spec major CDs (SpellDB.CLASS_BURST_TRIGGER_DEFAULTS)
-- with optional user overrides.  Aura IDs resolved via SpellDB.GetTriggerAuraID().

local BurstInjectionEngine = LibStub:NewLibrary("JustAC-BurstInjectionEngine", 4)
if not BurstInjectionEngine then return end

-- Hot path cache
local GetSpellBaseCooldown = GetSpellBaseCooldown ---@diagnostic disable-line: undefined-global
local GetTime = GetTime
local ipairs = ipairs
local issecretvalue = issecretvalue ---@diagnostic disable-line: undefined-global

-- Module references (resolved at load time)
local BlizzardAPI        = LibStub("JustAC-BlizzardAPI", true)
local SpellDB            = LibStub("JustAC-SpellDB", true)
local RedundancyFilter   = LibStub("JustAC-RedundancyFilter", true)

--------------------------------------------------------------------------------
-- Cached state (wiped on spec/profile change)
--------------------------------------------------------------------------------

local cachedTriggerSpells = nil    -- resolved trigger set: { [spellID] = true }
local cachedTriggerAuraIDs = nil   -- resolved aura set: { [auraSpellID] = true }
local cachedTriggerSource = nil   -- "explicit", "defaults", or nil
local cachedInjectionSpells = nil  -- resolved injection list: { spellID, ... }
local cachedSpecKey = nil

--- Cache of base cooldown durations (seconds) for spells seen via CheckTrigger.
--- Populated lazily; survives across cache invalidations (spell CDs don't change).
local baseCooldownCache = {}       -- { [spellID] = seconds }

--- Timer fallback state for non-aura triggers (pet summons, target debuffs).
--- When a trigger spell is cast but no matching aura appears on the player,
--- the engine falls back to a fixed-duration window.
local AURA_GRACE_PERIOD = 0.5      -- seconds to wait for aura before using timer fallback
local timerFallbackExpiry = 0       -- GetTime() when timer fallback window ends (0 = inactive)
local timerTriggerCastTime = 0      -- GetTime() when a trigger spell was last cast

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

--- Build the trigger aura ID set from the trigger spell set.
--- Maps each trigger spellID → its aura spellID via SpellDB.GetTriggerAuraID().
--- Also adds ResolveSpellID variants so talent overrides are covered.
local function BuildTriggerAuraIDSet(sourceList)
    cachedTriggerAuraIDs = {}
    if not sourceList then return end
    local GetTriggerAuraID = SpellDB and SpellDB.GetTriggerAuraID
    for _, spellID in ipairs(sourceList) do
        if spellID and spellID > 0 then
            local auraID = GetTriggerAuraID and GetTriggerAuraID(spellID) or spellID
            cachedTriggerAuraIDs[auraID] = true
            -- Also add the resolved variant (talent overrides may remap)
            local resolved = BlizzardAPI.ResolveSpellID(auraID)
            if resolved ~= auraID then
                cachedTriggerAuraIDs[resolved] = true
            end
            -- If spell itself resolves to something different, add that aura too
            local resolvedSpell = BlizzardAPI.ResolveSpellID(spellID)
            if resolvedSpell ~= spellID then
                local resolvedAura = GetTriggerAuraID and GetTriggerAuraID(resolvedSpell) or resolvedSpell
                cachedTriggerAuraIDs[resolvedAura] = true
            end
        end
    end
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
    cachedTriggerAuraIDs = {}
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
        BuildTriggerAuraIDSet(bi.triggerSpells[specKey])
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
            BuildTriggerAuraIDSet(defaults)
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

--- Return class default trigger spells for the current spec (ignores overrides).
--- Shows all defaults regardless of talent status — for display in options panel.
--- Returns: { {spellID=number, name=string, baseCd=number}, ... } or empty table.
function BurstInjectionEngine.GetDefaultTriggers()
    local specKey = GetSpecKey()
    if not specKey or not SpellDB or not SpellDB.CLASS_BURST_TRIGGER_DEFAULTS then return {} end
    local defaults = SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
    if not defaults then return {} end
    local result = {}
    for _, spellID in ipairs(defaults) do
        if spellID and spellID > 0 then
            local resolvedID = BlizzardAPI.ResolveSpellID(spellID)
            local displayID = resolvedID or spellID
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(displayID)
            if not spellInfo then
                spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            end
            local name = spellInfo and spellInfo.name or tostring(spellID)
            local baseCd = GetBaseCooldownSeconds(displayID)
            result[#result + 1] = { spellID = displayID, name = name, baseCd = baseCd }
        end
    end
    return result
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

--- Two-phase burst trigger check.
--- Returns: phase, isTriggerAtPos1
---   phase = "active"  → trigger aura is on player, inject from injection list
---   phase = "pending" → Blizzard recommends trigger CD at pos 1 (show glow, don't inject)
---   phase = nil        → no burst condition detected
---   isTriggerAtPos1    → true when primarySpellID is itself a trigger (for glow)
function BurstInjectionEngine.CheckTrigger(addon, primarySpellID)
    if not addon or not addon.db or not addon.db.profile then return nil, false end
    local bi = addon.db.profile.burstInjection
    if not bi or not bi.enabled then return nil, false end

    local triggers = ResolveTriggerSpells(addon)
    if not triggers then return nil, false end

    -- Phase 2a: is a trigger aura currently active on the player?
    -- Lazy-resolve RedundancyFilter (loaded later in TOC order)
    if not RedundancyFilter then
        RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    end
    local auraActive = false
    if RedundancyFilter and RedundancyFilter.IsAnyAuraActive and cachedTriggerAuraIDs then
        auraActive = RedundancyFilter.IsAnyAuraActive(cachedTriggerAuraIDs)
    end

    -- Phase 2b: timer fallback for non-aura triggers (pet summons, target debuffs).
    -- If a trigger was cast recently but no matching aura appeared after the grace
    -- period, fall back to a fixed-duration window.
    local now = GetTime()
    local timerActive = false
    if not auraActive and timerFallbackExpiry > 0 and now < timerFallbackExpiry then
        -- Only activate timer fallback after the grace period (give aura time to appear)
        if now - timerTriggerCastTime > AURA_GRACE_PERIOD then
            timerActive = true
        end
    end

    if auraActive or timerActive then
        -- Check position-1 match for glow signal
        local triggerAtPos1 = false
        if primarySpellID and primarySpellID > 0 then
            if triggers[primarySpellID] then
                triggerAtPos1 = true
            else
                local displayID = BlizzardAPI.GetDisplaySpellID(primarySpellID)
                if displayID and displayID ~= primarySpellID and triggers[displayID] then
                    triggerAtPos1 = true
                end
            end
        end
        return "active", triggerAtPos1
    end

    -- Phase 1: is Blizzard recommending a trigger spell at position 1?
    if primarySpellID and primarySpellID > 0 then
        if triggers[primarySpellID] then return "pending", true end
        local displayID = BlizzardAPI.GetDisplaySpellID(primarySpellID)
        if displayID and displayID ~= primarySpellID and triggers[displayID] then
            return "pending", true
        end
    end

    return nil, false
end

--- Returns true if a burst window is currently active (trigger aura on player
--- or timer fallback running).
function BurstInjectionEngine.IsBurstActive(addon)
    if not addon then return false end
    local phase = BurstInjectionEngine.CheckTrigger(addon, nil)
    return phase == "active"
end

--- Record that a trigger spell was just cast.
--- Called from JustAC:OnSpellcastSucceeded. Starts the timer fallback window
--- so non-aura triggers (pet summons, target debuffs) still get a burst window.
function BurstInjectionEngine.RecordTriggerCast(addon, spellID)
    if not spellID or not cachedTriggerSpells then return end
    -- Check if this spell (or its resolved/display form) is a trigger
    local isTrigger = cachedTriggerSpells[spellID]
    if not isTrigger then
        local resolved = BlizzardAPI.ResolveSpellID(spellID)
        isTrigger = cachedTriggerSpells[resolved]
        if not isTrigger then
            local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
            isTrigger = displayID and cachedTriggerSpells[displayID]
        end
    end
    if not isTrigger then return end
    local now = GetTime()
    timerTriggerCastTime = now
    -- Duration: profile override → CLASS_BURST_DURATION_DEFAULTS → 10s
    local profile = addon and addon.db and addon.db.profile
    local duration = profile and profile.burstInjection and profile.burstInjection.fallbackDuration
    if not duration then
        duration = (SpellDB and SpellDB.GetBurstDurationDefault and SpellDB.GetBurstDurationDefault())
            or 10
    end
    timerFallbackExpiry = now + duration
end

--- Clear timer fallback state (combat end, spec change).
function BurstInjectionEngine.ClearBurstState()
    timerFallbackExpiry = 0
    timerTriggerCastTime = 0
end

--- Invalidate cached spell lists (spec change, profile change).
function BurstInjectionEngine.InvalidateBurstCache()
    cachedTriggerSpells = nil
    cachedTriggerAuraIDs = nil
    cachedTriggerSource = nil
    cachedInjectionSpells = nil
    cachedSpecKey = nil
    BurstInjectionEngine.ClearBurstState()
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
