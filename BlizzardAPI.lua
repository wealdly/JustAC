-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Blizzard API Module - entry point, version detection and LibStub registration.
-- Public functions are defined in the BlizzardAPI\ submodules, loaded immediately
-- after this file in JustAC.toc: CooldownTracking, SecretValues, SpellQuery, StateHelpers.
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 33)
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
--- Returns the action bar usability state for a spell, or nil if unavailable.
--- NeverSecret API — safe in combat. Uses ActionBarScanner to find the slot.
--- @param spellID number
--- @return boolean|nil usable, boolean|nil notEnoughMana
function BlizzardAPI.GetActionBarUsability(spellID)
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    if not ABS or not ABS.GetSlotForSpell then return nil, nil end
    local slot = ABS.GetSlotForSpell(spellID)
    if not slot or not C_ActionBar or not C_ActionBar.IsUsableAction then return nil, nil end
    local usable, noMana = C_ActionBar.IsUsableAction(slot)
    if BlizzardAPI.IsSecretValue(usable) or BlizzardAPI.IsSecretValue(noMana) then return nil, nil end
    return usable, noMana
end
