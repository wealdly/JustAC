-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- GapCloserEngine.lua — Gap-closer system: melee range detection, spell prioritization
-- Suggests movement spells when target is out of melee range.
-- Extracted from DefensiveEngine.lua for clarity (gap closers inject into the offensive queue).

local MAJOR, MINOR = "JustAC-GapCloserEngine", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Hot path cache
local GetTime = GetTime
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local GetSpecialization = GetSpecialization
local IsStealthed = IsStealthed
local FindSpellOverrideByID = FindSpellOverrideByID
local IsActionInRange = IsActionInRange
local C_Spell = C_Spell
local ipairs = ipairs

-- Module references (resolved at load time)
local BlizzardAPI       = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner  = LibStub("JustAC-ActionBarScanner", true)
local SpellDB           = LibStub("JustAC-SpellDB", true)

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Get the gap-closer spell list key for the current spec
function lib.GetGapCloserSpecKey()
    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    return playerClass .. "_" .. spec
end

--- Initialize gap-closer defaults for the current spec if not yet populated
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
