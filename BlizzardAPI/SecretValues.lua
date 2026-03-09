-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Secret Value Utilities, Feature Availability, Secrecy API Wrappers (12.0+)
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after CooldownTracking.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-SecretValues", 1
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

-- Version constants set by BlizzardAPI.lua (root) before this file loads.
local IS_MIDNIGHT_OR_LATER = BlizzardAPI.IS_MIDNIGHT_OR_LATER

--------------------------------------------------------------------------------
-- Feature Availability (12.0+ secret value graceful degradation)
--------------------------------------------------------------------------------

local featureAvailability = {
    healthAccess = true,
    auraAccess = true,
    procAccess = true,
    lastCheck = 0,
}
local FEATURE_CHECK_INTERVAL = 5.0

-- UnitHealth("player") confirmed NOT secret as of 12.0 Alpha 6
local function TestHealthAccess()
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    return not IsSecretValue(health) and not IsSecretValue(maxHealth)
end

-- Aura CONTENTS may be secret in 12.0, but VECTORS are not
local function TestAuraAccess()
    -- 12.0+ fast pre-check: C_Secrets.ShouldAurasBeSecret() is a NeverSecret boolean.
    -- When true, all aura fields will be secret — skip the per-aura loop entirely.
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return false
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local accessibleCount = 0
        local secretCount = 0

        for i = 1, 5 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end  -- No more auras

            if IsSecretValue(auraData.spellId) or IsSecretValue(auraData.name) then
                secretCount = secretCount + 1
            else
                accessibleCount = accessibleCount + 1
            end
        end

        return accessibleCount > 0 or (accessibleCount == 0 and secretCount == 0)
    end

    return false
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
    local oldAuraAccess = featureAvailability.auraAccess
    local oldProcAccess = featureAvailability.procAccess

    featureAvailability.healthAccess = TestHealthAccess()
    featureAvailability.auraAccess = TestAuraAccess()
    featureAvailability.procAccess = TestProcAccess()
    featureAvailability.lastCheck = now

    local debugMode = BlizzardAPI.GetDebugMode()
    if debugMode then
        local addon = BlizzardAPI.GetAddon and BlizzardAPI.GetAddon()
        if addon and addon.Print then
            if oldHealthAccess ~= featureAvailability.healthAccess then
                addon:Print("Health API access: " .. (featureAvailability.healthAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldAuraAccess ~= featureAvailability.auraAccess then
                addon:Print("Aura API access: " .. (featureAvailability.auraAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldProcAccess ~= featureAvailability.procAccess then
                addon:Print("Proc API access: " .. (featureAvailability.procAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
        end
    end
end

function BlizzardAPI.IsRedundancyFilterAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.auraAccess
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
        auraAccess = featureAvailability.auraAccess,
        procAccess = featureAvailability.procAccess,
    }
end

-- IsSecretValue() and Unsecret() are defined in BlizzardAPI.lua (root)
-- so all submodules can upvalue them. No additional definitions needed here.

--------------------------------------------------------------------------------
-- API-Specific Secret-Aware Helpers
--------------------------------------------------------------------------------

function BlizzardAPI.GetAuraTiming(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil, nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil, nil end
    return Unsecret(aura.duration), Unsecret(aura.expirationTime)
end

function BlizzardAPI.IsMidnightOrLater()
    return IS_MIDNIGHT_OR_LATER
end


