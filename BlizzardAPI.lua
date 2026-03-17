-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Blizzard API Module - entry point, version detection and LibStub registration.
-- Public functions are defined in the BlizzardAPI\ submodules, loaded immediately
-- after this file in JustAC.toc: CooldownTracking, SecretValues, SpellQuery, StateHelpers.
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 34)
if not BlizzardAPI then return end

--------------------------------------------------------------------------------
-- Version Detection
--------------------------------------------------------------------------------
local CURRENT_VERSION = select(4, GetBuildInfo()) or 0
BlizzardAPI.IS_MIDNIGHT_OR_LATER = CURRENT_VERSION >= 120000
BlizzardAPI._interfaceVersion    = CURRENT_VERSION

--------------------------------------------------------------------------------
-- Secret Value Primitives
--------------------------------------------------------------------------------
-- Defined here (root) so every submodule can upvalue them at load time.
-- Blizzard's `issecretvalue` global may not exist on pre-12.0 clients.

--- Returns true if the value is a secret (cannot be compared or used in arithmetic).
--- Try the direct API call first; guard the result with this before any comparison.
--- @param value any
--- @return boolean
function BlizzardAPI.IsSecretValue(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

--- Extract a readable value — returns fallback when secret or nil.
--- Optimistic: assumes the value IS readable (Blizzard may loosen restrictions
--- over time), only falls back when it provably isn't.
---
---   local dur = BlizzardAPI.Unsecret(cd.duration)          -- nil if secret
---   local hp  = BlizzardAPI.Unsecret(health, 100)          -- 100 if secret
---
--- @param value    any          The potentially-secret value
--- @param fallback any|nil      Returned when value is nil or secret (default nil)
--- @return any                  value if readable, fallback otherwise
function BlizzardAPI.Unsecret(value, fallback)
    if value == nil then return fallback end
    if issecretvalue ~= nil and issecretvalue(value) then return fallback end
    return value
end

--------------------------------------------------------------------------------
-- Action Bar Usability Helper (shared by IsSpellReady + IsSpellUsable)
--------------------------------------------------------------------------------
-- Event-driven usability cache, populated by ACTION_USABLE_CHANGED.
-- Keyed by absolute action slot number → {usable, noMana}.
-- Macro modifier effects are handled by the C engine: when a modifier changes
-- the effective spell on a slot, ACTION_USABLE_CHANGED re-fires for that slot
-- with updated usability reflecting the newly-resolved spell.
local slotUsabilityCache = {}
local wipe = wipe

--- Process ACTION_USABLE_CHANGED batched payload.
--- @param changes table Array of {slot=luaIndex, usable=bool, noMana=bool}
function BlizzardAPI.OnActionUsableChanged(changes)
    for _, change in ipairs(changes) do
        slotUsabilityCache[change.slot] = change
    end
    -- Detect CD completion via usability flips (Phase 2 CDR detection)
    if BlizzardAPI.CheckUsabilityFlips then
        BlizzardAPI.CheckUsabilityFlips(changes)
    end
end

--- Wipe slot usability cache (call when slot content changes, e.g. bar page
--- switch, ACTIONBAR_SLOT_CHANGED, vehicle enter/exit).
function BlizzardAPI.InvalidateSlotUsabilityCache()
    wipe(slotUsabilityCache)
    -- Also invalidate the reverse slot→spell map for CDR flip detection
    if BlizzardAPI.InvalidateReverseSlotMap then
        BlizzardAPI.InvalidateReverseSlotMap()
    end
end

--- Returns the action bar usability state for a spell, or nil if unavailable.
--- NeverSecret API — safe in combat. Uses ActionBarScanner to find the slot.
--- Falls back to assisted combat slot when spell isn't on the player's bars.
--- Checks the event-driven cache first; falls back to live API.
--- @param spellID number
--- @return boolean|nil usable, boolean|nil notEnoughMana
function BlizzardAPI.GetActionBarUsability(spellID)
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    if not ABS or not ABS.GetSlotForSpell then return nil, nil end
    local slot = ABS.GetSlotForSpell(spellID)

    -- Assisted combat slot fallback: if the spell isn't on any bar but matches
    -- the current assistant recommendation, use that slot for usability checks.
    if not slot and ABS.GetAssistedCombatSlot then
        local C_AssistedCombat = C_AssistedCombat
        if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local nextCast = C_AssistedCombat.GetNextCastSpell(true)
            local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
            if nextCast and (nextCast == spellID or nextCast == displayID) then
                slot = ABS.GetAssistedCombatSlot()
            end
        end
    end

    if not slot then return nil, nil end

    -- Prefer event-driven cache (ACTION_USABLE_CHANGED)
    local cached = slotUsabilityCache[slot]
    if cached then
        return cached.usable, cached.noMana
    end

    -- Fallback to live API (cache not yet populated for this slot)
    if not C_ActionBar or not C_ActionBar.IsUsableAction then return nil, nil end
    local usable, noMana = C_ActionBar.IsUsableAction(slot)
    if BlizzardAPI.IsSecretValue(usable) or BlizzardAPI.IsSecretValue(noMana) then return nil, nil end
    return usable, noMana
end
