-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- GapCloserEngine.lua — Gap-closer system: melee range detection, spell prioritization
-- Suggests movement spells when target is out of melee range.
-- Extracted from DefensiveEngine.lua for clarity (gap closers inject into the offensive queue).

local GapCloserEngine = LibStub:NewLibrary("JustAC-GapCloserEngine", 2)
if not GapCloserEngine then return end

-- Hot path cache
local GetTime = GetTime
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local GetSpecialization = GetSpecialization
local IsStealthed = IsStealthed
local IsActionInRange = IsActionInRange
local C_Spell = C_Spell
local ipairs = ipairs

-- Module references (resolved at load time)
local BlizzardAPI       = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner  = LibStub("JustAC-ActionBarScanner", true)
local SpellDB           = LibStub("JustAC-SpellDB", true)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Hide debounce: after target returns to melee range, hold the gap-closer icon
-- briefly so it doesn't vanish on a single in-range frame.  No show debounce —
-- showing the gap closer instantly is correct because the slot would otherwise
-- fill with a rotation spell, and the subsequent debounce expiry would cause a
-- visible blink.
local GAP_CLOSER_HIDE_DEBOUNCE = 0.15  -- seconds before icon disappears
local lastOutOfRangeTime = 0

-- Target-switch cooldown: suppress gap-closer suggestions briefly after
-- PLAYER_TARGET_CHANGED so IsActionInRange can stabilize on the new target.
-- Without this, a stale out-of-range frame from the previous target can
-- cause a false-positive gap-closer flash on the new (in-range) target.
local TARGET_SWITCH_COOLDOWN = 0.2  -- seconds
local lastTargetSwitchTime = 0

--------------------------------------------------------------------------------
-- Cached state
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Try to find an action bar slot for a spell ID (base + talent override).
--- Returns slot number or nil.
local function FindSlotForSpell(spellID)
    if not ActionBarScanner or not ActionBarScanner.GetSlotForSpell then return nil end
    local resolved = BlizzardAPI.ResolveSpellID(spellID)
    local slot = ActionBarScanner.GetSlotForSpell(resolved)
    if not slot and resolved ~= spellID then
        slot = ActionBarScanner.GetSlotForSpell(spellID)
    end
    return slot
end

--- Evaluate a single gap-closer candidate: resolve → dedup → available →
--- usable(failClosed) → action bar slot → ready.  Returns resolvedID, baseID
--- on success, or nil if the spell doesn't pass all gates.
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

    if not BlizzardAPI.IsSpellAvailable(resolvedID) then return nil end

    -- Fail closed: if we can't confirm usability (secret values), skip
    if not BlizzardAPI.IsSpellUsable(resolvedID, false) then return nil end

    -- FindSlotForSpell resolves overrides internally, so passing the base
    -- spellID checks both the resolved form and the original.
    local slot = FindSlotForSpell(spellID)
    if not slot then return nil end

    -- Optional own-range check (stealth gap closers with extended range)
    if checkRange and IsActionInRange(slot) == false then return nil end

    if not BlizzardAPI.IsSpellReady(resolvedID) then return nil end

    return resolvedID, spellID
end

-- 12.0+ push-based range check: EnableActionRangeCheck opts a slot into
-- ACTION_RANGE_CHECK_UPDATE events, eliminating poll-based IsActionInRange.
-- Detected once at load time; omitted on pre-12.0 clients.
local EnableActionRangeCheck = C_ActionBar and C_ActionBar.EnableActionRangeCheck

--- Helper: register/unregister a slot for push-based ACTION_RANGE_CHECK_UPDATE.
--- Safely no-ops on pre-12.0 clients where the API doesn't exist.
local function SetRangeCheckEnabled(slot, enabled)
    if not EnableActionRangeCheck or not slot then return end
    pcall(EnableActionRangeCheck, slot, enabled)
end

--- Get the melee range reference spell + slot for the current spec.
--- Priority chain: user override → SpellDB default[1] → SpellDB default[2].
--- First spell found on the action bar wins.  Caches result until spec change
--- or InvalidateGapCloserCache().
local function ResolveMeleeReference(addon)
    local specKey, playerClass
    if SpellDB and SpellDB.GetSpecKey then
        specKey, playerClass = SpellDB.GetSpecKey()
    end
    if not playerClass then return nil, nil end

    -- Return cache if still valid
    if cachedMeleeRefSpecKey == specKey and cachedMeleeRefSlot then
        return cachedMeleeRefSpellID, cachedMeleeRefSlot
    end

    -- If switching to a different slot, disable range check on the old one.
    local previousSlot = cachedMeleeRefSlot

    -- 1) Check profile for user override
    local profile = addon and addon.db and addon.db.profile
    local gc = profile and profile.gapClosers
    if gc and gc.meleeRangeSpell and gc.meleeRangeSpell > 0 then
        local slot = FindSlotForSpell(gc.meleeRangeSpell)
        if slot then
            if previousSlot and previousSlot ~= slot then
                SetRangeCheckEnabled(previousSlot, false)
            end
            cachedMeleeRefSpellID = gc.meleeRangeSpell
            cachedMeleeRefSlot = slot
            cachedMeleeRefSpecKey = specKey
            SetRangeCheckEnabled(slot, true)
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
                        if previousSlot and previousSlot ~= slot then
                            SetRangeCheckEnabled(previousSlot, false)
                        end
                        cachedMeleeRefSpellID = refID
                        cachedMeleeRefSlot = slot
                        cachedMeleeRefSpecKey = specKey
                        SetRangeCheckEnabled(slot, true)
                        return cachedMeleeRefSpellID, cachedMeleeRefSlot
                    end
                end
            end
        end
    end

    -- No slot found — disable range check on previous slot if any.
    if previousSlot then
        SetRangeCheckEnabled(previousSlot, false)
    end
    cachedMeleeRefSpecKey = specKey
    cachedMeleeRefSpellID = nil
    cachedMeleeRefSlot = nil
    return nil, nil
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

--- Get the gap-closer spell list key for the current spec
function GapCloserEngine.GetGapCloserSpecKey()
    if SpellDB and SpellDB.GetSpecKey then
        return SpellDB.GetSpecKey()
    end
    return nil
end

--- Initialize gap-closer defaults for the current spec if not yet populated
function GapCloserEngine.InitializeGapClosers(addon)
    local profile = addon:GetProfile()
    if not profile then return end

    if not profile.gapClosers then
        profile.gapClosers = { enabled = true, classSpells = {} }
    end
    if not profile.gapClosers.classSpells then
        profile.gapClosers.classSpells = {}
    end

    local specKey = GapCloserEngine.GetGapCloserSpecKey()
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
end

--- Called from JustAC:OnActionRangeUpdate(slot, isInRange, checksRange)
--- Returns true if this event was for the melee reference slot (caller uses
--- this to decide whether to trigger a queue rebuild).
function GapCloserEngine.OnActionRangeUpdate(slot, isInRange, checksRange)
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
function GapCloserEngine.ClearRangeState()
    lastOutOfRangeTime = 0
    lastTargetSwitchTime = GetTime()
    -- Don't clear cachedMeleeRefSlot here — the reference spell's slot
    -- doesn't change between targets, only the range state does.
    -- Slot is invalidated by InvalidateGapCloserCache() on spec/profile change.
end

--- Invalidate cached gap-closer spell list (spec change, profile change)
function GapCloserEngine.InvalidateGapCloserCache()
    -- Disable push-based range check on the old melee reference slot.
    if cachedMeleeRefSlot then
        SetRangeCheckEnabled(cachedMeleeRefSlot, false)
    end
    cachedGapCloserSpells = nil
    cachedGapCloserSpecKey = nil
    cachedMeleeRefSpellID = nil
    cachedMeleeRefSlot = nil
    cachedMeleeRefSpecKey = nil
end

--- Returns the first usable gap-closer spell ID for the current spec, or nil.
--- "Usable" = known, IsSpellUsable(failOpen=false), on an action bar slot, and
--- not on a real cooldown (isOnGCD ~= false).
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

    -- Target-switch cooldown: suppress gap-closer suggestions briefly after
    -- switching targets so IsActionInRange can settle on the new target.
    -- Without this, a stale out-of-range frame from the old target can cause
    -- a false-positive gap-closer flash on a new target that's already in range.
    if lastTargetSwitchTime > 0 and (GetTime() - lastTargetSwitchTime) < TARGET_SWITCH_COOLDOWN then
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
            if spellID and spellID > 0 and SpellDB.GAP_CLOSER_REQUIRES_STEALTH
                and SpellDB.GAP_CLOSER_REQUIRES_STEALTH[spellID] then
                local resolved, base = TryGapCloserCandidate(spellID, addedSpellIDs, true)
                if resolved then return resolved, base end
            end
        end
    end

    -- Melee range reference check.  If no reference resolves (ranged spec or
    -- nothing on the action bar), skip non-stealth gap closers entirely.
    local _, meleeRefSlot = ResolveMeleeReference(addon)
    if not meleeRefSlot then return nil end

    -- If the primary reference spell is currently showing a different spell on
    -- its slot (state-driven transform, e.g. Stormstrike → Windstrike during
    -- Ascendance), IsActionInRange would report the override's wider range.
    -- Fall back to the SpellDB backup candidate [2] if it's on the action bar.
    -- GetDisplaySpellID (C_Spell.GetOverrideSpell) covers aura/stance transforms;
    -- the stealth guard below still handles talent-driven overrides separately.
    local activeRefSlot = meleeRefSlot
    if cachedMeleeRefSpellID then
        local displayID = BlizzardAPI.GetDisplaySpellID(cachedMeleeRefSpellID)
        if displayID and displayID ~= cachedMeleeRefSpellID then
            local specKey = GapCloserEngine.GetGapCloserSpecKey()
            local defaults = specKey and SpellDB.MELEE_RANGE_REFERENCE_SPELLS
                and SpellDB.MELEE_RANGE_REFERENCE_SPELLS[specKey]
            local backupID = defaults and defaults[2]
            if backupID then
                local backupSlot = FindSlotForSpell(backupID)
                if backupSlot then activeRefSlot = backupSlot end
            end
        end
    end

    -- Check range using the (possibly backup) melee reference slot
    local inRange = IsActionInRange(activeRefSlot)
    local outOfRange = (inRange == false)  -- false=out of range, nil=no range check, true=in range
    local now = GetTime()

    -- If stealthed and the melee reference spell is overridden to a stealth
    -- gap closer with extended range (e.g. Backstab slot shows Shadowstrike
    -- at 25yd), the range check is unreliable.  Force "out of range" so
    -- non-stealth gap closers like Shadowstep and Sprint can still fire.
    if not outOfRange and stealthed and cachedMeleeRefSpellID then
        local overrideID = BlizzardAPI.ResolveSpellID(cachedMeleeRefSpellID)
        if overrideID ~= cachedMeleeRefSpellID and SpellDB.GAP_CLOSER_REQUIRES_STEALTH
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
            -- Skip stealth-only gap closers in the normal loop.
            -- When stealthed: already evaluated in the dedicated stealth path above.
            -- When not stealthed: gap-closer component is inactive (no teleport).
            local resolvedID = BlizzardAPI.ResolveSpellID(spellID)
            local isStealth = SpellDB.GAP_CLOSER_REQUIRES_STEALTH
                and (SpellDB.GAP_CLOSER_REQUIRES_STEALTH[spellID] or SpellDB.GAP_CLOSER_REQUIRES_STEALTH[resolvedID])
            if not isStealth then
                local resolved, base = TryGapCloserCandidate(spellID, addedSpellIDs)
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
function GapCloserEngine.IsGapCloserSpell(addon, spellID)
    if not spellID or spellID == 0 then return false end

    -- Helper: scan a spell list for a match (base ID or talent override)
    local function ListContains(list)
        if not list then return false end
        for _, gcSpellID in ipairs(list) do
            if gcSpellID == spellID then return true end
            if BlizzardAPI.ResolveSpellID(gcSpellID) == spellID then return true end
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
function GapCloserEngine.MarkGapCloserSpellIDs(addon, spellIDSet)
    if not addon or not spellIDSet then return end
    local spellList = ResolveGapCloserSpells(addon)
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

--- Restore gap-closer defaults for the current spec
function GapCloserEngine.RestoreGapCloserDefaults(addon)
    local profile = addon:GetProfile()
    if not profile or not profile.gapClosers then return end

    local specKey = GapCloserEngine.GetGapCloserSpecKey()
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
