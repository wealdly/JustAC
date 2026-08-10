-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- GapCloserEngine.lua - Gap-closer system: melee range detection, spell prioritization
-- Suggests movement spells when target is out of melee range.
-- Extracted from DefensiveEngine.lua for clarity (gap closers inject into the offensive queue).

local GapCloserEngine = LibStub:NewLibrary("JustAC-GapCloserEngine", 7)
if not GapCloserEngine then return end

-- Hot path cache
local GetTime = GetTime
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local IsStealthed = IsStealthed
local IsSpellKnown = IsSpellKnown
local C_Spell = C_Spell
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local ipairs = ipairs

-- Module references (resolved at load time)
local BlizzardAPI       = LibStub("JustAC-BlizzardAPI", true)
local SpellDB           = LibStub("JustAC-SpellDB", true)
local SpellQueue        = LibStub("JustAC-SpellQueue", true)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Hide debounce: after target returns to melee range, hold the gap-closer icon
-- briefly so it doesn't vanish on a single in-range frame.  No show debounce -
-- showing the gap closer instantly is correct because the slot would otherwise
-- fill with a rotation spell, and the subsequent debounce expiry would cause a
-- visible blink.
local GAP_CLOSER_HIDE_DEBOUNCE = 0.4   -- seconds to hold the icon after returning to range.
                                       -- Larger than the old event-driven value because we
                                       -- now POLL IsSpellInRange each build; the longer hold
                                       -- bridges boundary jitter so the icon doesn't flicker
                                       -- as the player crosses in/out of melee.
local lastOutOfRangeTime = 0

-- Post-fire debounce: after a gap closer is CONFIRMED cast (UNIT_SPELLCAST_SUCCEEDED),
-- the charge/leap is still in flight and the melee probe hasn't caught up - without
-- this the engine offers the NEXT gap closer during the travel window. Long enough
-- to cover any charge/leap travel plus the range probe settling; short enough that a
-- genuinely failed close (target blinked away) re-offers promptly.
local GAP_CLOSER_FIRED_DEBOUNCE = 3    -- seconds
local lastFiredTime = -1e9

-- Near-band gate: barely out of melee is walking distance, not a cooldown's job -
-- only offer when the target is PROVEN beyond this (or unprovable: probe coverage
-- varies by spec, and unknown fails OPEN so thin toolboxes keep their gap closers).
-- ponytail: one flat threshold; per-spell max-range bands if a spec ever needs them.
local GAP_CLOSER_NEAR_YARDS = 10

--------------------------------------------------------------------------------
-- Cached state
--------------------------------------------------------------------------------

-- Cached gap-closer spell list for the current class+spec (wipe on spec change)
local cachedGapCloserSpells = nil
local cachedGapCloserSpecKey = nil

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Evaluate a single gap-closer candidate: resolve → dedup → available →
--- known → ready → (optional range).  Returns resolvedID, baseID on success,
--- or nil if the spell doesn't pass all gates.
--- The gap-closer list is curated (user-configured or SpellDB defaults), so
--- the only availability gate is "does the player know this spell" - filtering
--- out default entries the player hasn't talented into.  No usability check
--- (fail-closed rejects valid spells in combat due to secret values; fail-open
--- adds no value for a curated list).  Cooldown check remains to avoid
--- suggesting spells that are on CD.
--- @param spellID      number       Base spell ID from the gap-closer list
--- @param addedSpellIDs table|nil   Set of already-queued spell IDs to skip
--- @param checkRange    boolean|nil  If true, also verify the spell's own slot is in range
local function TryGapCloserCandidate(spellID, addedSpellIDs, checkRange)
    if not spellID or spellID <= 0 then return nil end
    local resolvedID = BlizzardAPI.ResolveSpellID(spellID)

    -- Dedup: skip if already shown in the queue
    if addedSpellIDs and (addedSpellIDs[resolvedID] or addedSpellIDs[spellID]) then
        return nil
    end

    -- Known check: filter out spells the player doesn't have (untalented defaults). Use
    -- IsSpellKnown (form-independent), NOT IsSpellAvailable (castability) - the latter wrongly
    -- rejects a known gap-closer that isn't instantly castable (e.g. a Druid's form-gated
    -- Wild Charge). Cooldown is handled separately below; range by the checkRange gate.
    if IsSpellKnown and not (IsSpellKnown(spellID) or IsSpellKnown(resolvedID)) then return nil end

    -- Blacklist: suppress entries the user has hidden from all positions.
    -- Check both the curated base ID and the talent-resolved ID - the user may
    -- have blacklisted either form (IsSpellBlacklisted expands each via display override).
    if not SpellQueue then SpellQueue = LibStub("JustAC-SpellQueue", true) end
    if SpellQueue and SpellQueue.IsSpellBlacklisted
       and (SpellQueue.IsSpellBlacklisted(spellID)
            or (resolvedID ~= spellID and SpellQueue.IsSpellBlacklisted(resolvedID))) then
        return nil
    end

    -- Cooldown check: don't suggest spells on CD
    -- Ensure spell is registered for local CD tracking (idempotent after first call)
    if BlizzardAPI.RegisterSpellForTracking then
        BlizzardAPI.RegisterSpellForTracking(resolvedID, "gapcloser")
        -- Seed local CD on first registration so pre-existing CDs are detected
        if BlizzardAPI.SeedLocalCooldownIfActive then
            BlizzardAPI.SeedLocalCooldownIfActive(resolvedID)
        end
    end
    if not BlizzardAPI.IsSpellReady(resolvedID) then return nil end

    -- Range check: reject only if the spell is confirmed OUT of its OWN range (e.g. target
    -- beyond Wild Charge's max range). Spellbook IsSpellInRange (non-secret in combat,
    -- reliable in any form) - the action-slot check proved unreliable. Self-targeted spells
    -- (Sprint) return nil → not == false → pass. Secret → unknown → pass (fail-safe).
    if checkRange and C_Spell_IsSpellInRange then
        local r = C_Spell_IsSpellInRange(spellID, "target")
        if not (BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(r)) and r == false then
            return nil
        end
    end

    return resolvedID, spellID
end


--- Resolve the gap-closer spell list for the current class+spec.
--- Reads from profile (user-configured) with SpellDB defaults as fallback.
--- Returns an array of spell IDs, or nil if no gap-closers for this spec.
local function ResolveGapCloserSpells(addon)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return nil end

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

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Initialize gap-closer defaults for the current spec if not yet populated
function GapCloserEngine.InitializeGapClosers(addon)
    local profile = addon:GetProfile()
    if not profile then return end

    if not profile.gapClosers then
        profile.gapClosers = { enabled = false, classSpells = {} }
    end
    if not profile.gapClosers.classSpells then
        profile.gapClosers.classSpells = {}
    end

    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return end

    if not profile.gapClosers.classSpells[specKey] or #profile.gapClosers.classSpells[specKey] == 0 then
        local defaults = SpellDB and SpellDB.CLASS_GAPCLOSER_DEFAULTS and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
        if defaults then
            profile.gapClosers.classSpells[specKey] = {}
            for i, spellID in ipairs(defaults) do
                profile.gapClosers.classSpells[specKey][i] = spellID
            end
            GapCloserEngine.InvalidateGapCloserCache()
        end
    end

    -- Register gap-closer spells for local CD tracking and seed pre-existing CDs.
    -- Mirrors DefensiveEngine.RegisterDefensivesForTracking pattern.
    local spellList = profile.gapClosers.classSpells[specKey]
    if spellList and BlizzardAPI.RegisterSpellForTracking then
        for _, sid in ipairs(spellList) do
            if sid and sid > 0 then
                local resolvedID = BlizzardAPI.ResolveSpellID(sid)
                BlizzardAPI.RegisterSpellForTracking(resolvedID, "gapcloser")
                if BlizzardAPI.SeedLocalCooldownIfActive then
                    BlizzardAPI.SeedLocalCooldownIfActive(resolvedID)
                end
            end
        end
    end
end

--- Reset range state on target change / combat end: clears the hide-debounce timestamp so
--- a new target doesn't inherit the previous target's "recently out of range" hold.
--- The post-fire debounce is deliberately NOT cleared here: switching targets mid-flight
--- is exactly when offering a second gap closer wastes it, and 3s self-expires anyway.
function GapCloserEngine.ClearRangeState()
    lastOutOfRangeTime = 0
end

--- Called from the player's UNIT_SPELLCAST_SUCCEEDED: arm the post-fire debounce when
--- the cast was one of this spec's gap closers (user list or defaults, either ID form).
function GapCloserEngine.NoteSpellcastSucceeded(addon, spellID)
    local profile = addon and addon.db and addon.db.profile
    if not (profile and profile.gapClosers and profile.gapClosers.enabled) then return end
    if GapCloserEngine.IsGapCloserSpell(addon, spellID) then
        lastFiredTime = GetTime()
    end
end

--- Invalidate cached gap-closer spell list (spec change, profile change)
function GapCloserEngine.InvalidateGapCloserCache()
    cachedGapCloserSpells = nil
    cachedGapCloserSpecKey = nil
end

--- Returns the first usable gap-closer spell ID for the current spec, or nil.
--- "Usable" = known (IsSpellKnown), not blacklisted, not on a real cooldown
--- (IsSpellReady), and - for the melee-range gate - in range (IsSpellInRange).
--- No castability/usability check: fail-closed rejects valid spells in combat
--- (secret values), fail-open adds nothing for a curated list.
--- Returns: resolvedID, baseID  (resolvedID is the talent-overridden form;
---   baseID is the original list entry, e.g. Roll vs Chi Torpedo).
--- @param addon table              The JustAC addon object
--- @param addedSpellIDs table|nil  Set of already-queued spell IDs to skip (prevent duplicates)
function GapCloserEngine.GetGapCloserSpell(addon, addedSpellIDs)
    if not addon or not addon.db or not addon.db.profile then return nil end
    local gc = addon.db.profile.gapClosers
    if not gc or not gc.enabled then return nil end

    -- Must have a hostile target that is alive
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        return nil
    end

    -- (No target-switch cooldown needed: that delay existed to wait out IsActionInRange's
    -- stale-frame lag on target swap. IsSpellInRange reads the CURRENT target fresh every
    -- call, so there's no stale frame - the gap closer can evaluate immediately on acquire.)

    -- IsStealthed() is NeverSecret and covers Stealth, Vanish, Shadow Dance, etc.
    local stealthed = IsStealthed and IsStealthed() or false
    local spellList = ResolveGapCloserSpells(addon)

    ----------------------------------------------------------------------------
    -- STEALTH GAP CLOSERS - evaluate before the melee range gate.
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
            if spellID and spellID > 0 and SpellDB.GAP_CLOSER_REQUIRES_STEALTH
                and SpellDB.GAP_CLOSER_REQUIRES_STEALTH[spellID] then
                local resolved, base = TryGapCloserCandidate(spellID, addedSpellIDs, true)
                if resolved then return resolved, base end
            end
        end
    end

    -- Post-fire debounce: a gap closer just landed a cast; while it travels, offer
    -- nothing from the whole category (the fired spell itself is on CD, but the
    -- NEXT list entry would otherwise fill the slot mid-flight).
    local now = GetTime()
    if (now - lastFiredTime) < GAP_CLOSER_FIRED_DEBOUNCE then return nil end

    -- Melee detection via the shared range-reference system (SpellDB.IsTargetWithin), so the
    -- gap closer and ContextRank use ONE melee check - all melee specs covered bar-free
    -- (5yd probes in Data/RangeReferences.lua). IsTargetWithin polls every melee ability the
    -- player actually knows, so no per-spec reference or user override is needed.
    -- nil (no probe known / can't tell) → false → not out of melee (fail-safe).
    local outOfRange = (SpellDB.IsTargetWithin and SpellDB.IsTargetWithin(5) == false) or false

    -- Near-band suppression (gapClosers.farOnly, default ON via ~= false): proven
    -- within GAP_CLOSER_NEAR_YARDS means the gap isn't worth a cooldown - treat it
    -- like melee range (same hide-debounce smoothing). Only a positive proof
    -- suppresses; nil (out of probe coverage) falls through and the offer stands,
    -- so this can only ever REMOVE wasted offers, never valid ones.
    if outOfRange and gc.farOnly ~= false
        and SpellDB.IsTargetWithin and SpellDB.IsTargetWithin(GAP_CLOSER_NEAR_YARDS) == true then
        outOfRange = false
    end

    if outOfRange then
        -- Maintain the hide-debounce timestamp from the poll itself, so the bar-free
        -- (spellbook) path gets the same smoothing as the action-range event path.
        lastOutOfRangeTime = now
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
            -- Skip stealth-only gap closers in the normal loop.
            -- When stealthed: already evaluated in the dedicated stealth path above.
            -- When not stealthed: gap-closer component is inactive (no teleport).
            local resolvedID = BlizzardAPI.ResolveSpellID(spellID)
            local isStealth = SpellDB.GAP_CLOSER_REQUIRES_STEALTH
                and (SpellDB.GAP_CLOSER_REQUIRES_STEALTH[spellID] or SpellDB.GAP_CLOSER_REQUIRES_STEALTH[resolvedID])
            if not isStealth then
                local resolved, base = TryGapCloserCandidate(spellID, addedSpellIDs, true)
                if resolved then return resolved, base end
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
-- Scan a spell list for a match (base ID or talent override). Module-level:
-- defining it inside IsGapCloserSpell allocated a closure per call, and SpellQueue
-- calls that up to twice per build.
local function ListContains(list, spellID)
    if not list then return false end
    for _, gcSpellID in ipairs(list) do
        if gcSpellID == spellID then return true end
        if BlizzardAPI.ResolveSpellID(gcSpellID) == spellID then return true end
    end
    return false
end

function GapCloserEngine.IsGapCloserSpell(addon, spellID)
    if not spellID or spellID == 0 then return false end

    -- Check user-configured list
    if addon then
        local userList = ResolveGapCloserSpells(addon)
        if ListContains(userList, spellID) then return true end
    end

    -- Check SpellDB defaults (catches spells the user removed from their list)
    local defaults = SpellDB and SpellDB.GetGapCloserDefaults and SpellDB.GetGapCloserDefaults()
    if defaults and ListContains(defaults, spellID) then return true end

    return false
end

--- Mark all gap-closer spell IDs (base + talent-resolved forms) into a set.
--- Called by SpellQueue to suppress gap-closer spells from the rotation list
--- when the gap-closer system is enabled - our insertion controls when they appear.
--- With the feature DISABLED this marks nothing: the spells are then ordinary
--- rotation abilities and must flow through the queue like any other.
function GapCloserEngine.MarkGapCloserSpellIDs(addon, spellIDSet)
    if not addon or not spellIDSet then return end
    local profile = addon.db and addon.db.profile
    if not (profile and profile.gapClosers and profile.gapClosers.enabled) then return end
    BlizzardAPI.MarkResolvedIDs(ResolveGapCloserSpells(addon), spellIDSet)
end

--- Restore gap-closer defaults for the current spec
function GapCloserEngine.RestoreGapCloserDefaults(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.gapClosers then return end

    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
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

    GapCloserEngine.InvalidateGapCloserCache()
end
