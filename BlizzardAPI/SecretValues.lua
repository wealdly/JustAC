-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Secret Value Utilities, Feature Availability, Secrecy API Wrappers (12.0+)
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after CooldownTracking.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-SecretValues", 2
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime    = GetTime
local pcall      = pcall
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

--------------------------------------------------------------------------------
-- Feature Availability (12.0+ secret value graceful degradation)
--------------------------------------------------------------------------------

-- Aura access is NOT cached here: BlizzardAPI.AreAurasSecret() is one live C
-- call that flips exactly at combat edges (validated in-game 12.0.7), so it is
-- consulted directly wherever aura availability matters.
local featureAvailability = {
    healthAccess = true,
    procAccess = true,
    lastCheck = 0,
}
local FEATURE_CHECK_INTERVAL = 30.0  -- Safety net only; events (PLAYER_REGEN_*) are the primary trigger

-- UnitHealth("player") confirmed NOT secret as of 12.0 Alpha 6
local function TestHealthAccess()
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    return not IsSecretValue(health) and not IsSecretValue(maxHealth)
end

-- IsSpellOverlayed may return secret boolean in 12.0
-- GetRotationSpells() returns a flat array of spell ID numbers (not objects)
local function TestProcAccess()
    if not C_SpellActivationOverlay_IsSpellOverlayed then return true end

    local ok, result = pcall(function()
        if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
            local spells = C_AssistedCombat.GetRotationSpells()
            if spells and spells[1] then
                local hasProc = C_SpellActivationOverlay_IsSpellOverlayed(spells[1])
                if IsSecretValue(hasProc) then return false end
            end
        end
        return true
    end)

    if not ok then return true end
    return result
end

local function RefreshFeatureAvailability()
    local now = GetTime()
    if now - featureAvailability.lastCheck < FEATURE_CHECK_INTERVAL then
        return
    end

    local oldHealthAccess = featureAvailability.healthAccess
    local oldProcAccess = featureAvailability.procAccess

    featureAvailability.healthAccess = TestHealthAccess()
    featureAvailability.procAccess = TestProcAccess()
    featureAvailability.lastCheck = now

    local debugMode = BlizzardAPI.GetDebugMode()
    if debugMode then
        local addon = BlizzardAPI.GetAddon and BlizzardAPI.GetAddon()
        if addon and addon.Print then
            if oldHealthAccess ~= featureAvailability.healthAccess then
                addon:Print("Health API access: " .. (featureAvailability.healthAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldProcAccess ~= featureAvailability.procAccess then
                addon:Print("Proc API access: " .. (featureAvailability.procAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
        end
    end
end

function BlizzardAPI.IsProcFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.procAccess
end

function BlizzardAPI.RefreshFeatureAvailability()
    featureAvailability.lastCheck = 0
    RefreshFeatureAvailability()
end

function BlizzardAPI.GetFeatureAvailability()
    RefreshFeatureAvailability()
    return {
        healthAccess = featureAvailability.healthAccess,
        auraAccess = not BlizzardAPI.AreAurasSecret(),
        procAccess = featureAvailability.procAccess,
    }
end

-- IsSecretValue() and Unsecret() are defined in BlizzardAPI.lua (root)
-- so all submodules can upvalue them. No additional definitions needed here.

--------------------------------------------------------------------------------
-- API-Specific Secret-Aware Helpers
--------------------------------------------------------------------------------

-- Branchable "is this (possibly secret) amount zero or absent?" - the
-- scratch-FontString emptiness gate, in-game validated 2026-08-10
-- (`/jac inspect textlaunder`). The legal mechanics it composes:
--   * C_StringUtil.TruncateWhenZero accepts secrets and yields nil for zero,
--     a (secret) string otherwise - the engine makes the only decision.
--   * SetText("") reads back as PLAIN nil even on a widget whose Text aspect
--     is already poisoned, so ONE pooled widget is safe here: the sticky-aspect
--     trap only bites PLAIN-content readback, which this never does.
--   * Truthiness of the secret-string readback is legal (non-boolean rule).
-- Returns true (zero/absent), false (non-zero), or NIL when the technique is
-- unavailable on this client - callers MUST treat nil as "no answer" and fall
-- back to their heuristics, never as either verdict.
local zeroScratch
local TruncateWhenZero = C_StringUtil and C_StringUtil.TruncateWhenZero
function BlizzardAPI.IsSecretZero(v)
    if v == nil then return true end
    if not (IsSecretValue and IsSecretValue(v)) then
        -- Plain fast path: no widget needed, and non-numbers are "no answer".
        if type(v) == "number" then return v == 0 end
        return nil
    end
    if not TruncateWhenZero then return nil end
    if not zeroScratch then
        local holder = CreateFrame("Frame")
        holder:Hide()
        zeroScratch = holder:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    end
    local ok = pcall(function()
        zeroScratch:SetText(TruncateWhenZero(v) or "")
    end)
    if not ok then return nil end
    return not zeroScratch:GetText()
end

function BlizzardAPI.GetAuraTiming(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil, nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil, nil end
    return Unsecret(aura.duration), Unsecret(aura.expirationTime)
end

--------------------------------------------------------------------------------
-- Batch aura reads (12.0 C_UnitAuras.GetUnitAuras)
--
-- MEASURED in combat with restrictions latched (follower-dungeon boss, 12.0.7):
-- the returned TABLE and its length are PLAIN; only the per-aura FIELDS are
-- secret. That is the documented `ConditionalSecretContents` behaviour, and it
-- means one C call replaces the up-to-40 GetAuraDataByIndex calls every caller
-- used to make. Field-level secrecy is unchanged, so each caller keeps its own
-- secret handling - this helper only supplies the list.
--------------------------------------------------------------------------------

local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras

--- Array of AuraData for unit/filter, or nil if auras can't be enumerated at all.
--- Falls back to the index loop on clients without the batch call.
function BlizzardAPI.GetAuras(unit, filter)
    if not unit then return nil end
    if GetUnitAuras then
        local ok, list = pcall(GetUnitAuras, unit, filter)
        if ok and type(list) == "table" then return list end
        -- Fall through to the index loop: a throw here means this unit/filter
        -- combination is rejected, not that the API is missing.
    end
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not byIndex then return nil end
    local list = {}
    for i = 1, 40 do
        local ok, data = pcall(byIndex, unit, i, filter)
        if not ok or not data then break end
        list[i] = data
    end
    return list
end

-- Unknown category tokens FAIL OPEN: the engine silently IGNORES a token it does
-- not recognise and returns the unfiltered set rather than erroring (measured -
-- a bogus token returned all 31 helpful auras while BIG_DEFENSIVE returned 1).
-- So a token retired by a future patch would degrade into a permanently-true
-- gate instead of a visible failure. Guard: if a narrowed filter ever returns
-- exactly as many auras as its own base filter - with more than one aura in
-- play, since a single aura could legitimately be the match - the token is not
-- being honoured and that filter is abandoned for the session.
local filterVerdict = {}   -- filter string -> true (honoured) | false (ignored)

--- Count of auras matching an engine category filter, or nil when the filter
--- cannot be trusted. nil means "unknown" - callers fail open.
function BlizzardAPI.CountAuras(unit, filter)
    unit = unit or "player"
    if filterVerdict[filter] == false then return nil end
    local list = BlizzardAPI.GetAuras(unit, filter)
    if not list then return nil end
    local n = #list
    -- Only a narrowed filter can be ignored, and only a multi-aura sample can
    -- reveal it. Once proven honoured, stop paying for the second call.
    local base = filter and filter:match("^[^|]+")
    if n > 1 and base and base ~= filter and filterVerdict[filter] == nil then
        local all = BlizzardAPI.GetAuras(unit, base)
        if all and #all == n then
            filterVerdict[filter] = false
            return nil
        end
        filterVerdict[filter] = true
    end
    return n
end

--- True when the unit has a major defensive cooldown up. The engine does the
--- classification, so this needs no curated list and reads no secret: only the
--- COUNT is consulted, never an aura's identity. nil = unknown (fail open).
function BlizzardAPI.HasBigDefensive(unit)
    local n = BlizzardAPI.CountAuras(unit or "player", "HELPFUL|BIG_DEFENSIVE")
    if n == nil then return nil end
    return n > 0
end


