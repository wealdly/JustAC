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
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges  = C_Spell and C_Spell.GetSpellCharges
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

-- Version constants set by BlizzardAPI.lua (root) before this file loads.
local IS_MIDNIGHT_OR_LATER = BlizzardAPI.IS_MIDNIGHT_OR_LATER
local _interfaceVersion    = BlizzardAPI._interfaceVersion

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
        local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
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

-- Check if a spell is ready (not on a real cooldown).
-- 12.0 combat: duration/startTime are blanket-secreted.
-- isOnGCD is NeverSecret with three observable states:
--   true  → GCD only (spell is ready, just on GCD)
--   false → real cooldown running (only for spells Blizzard flags internally;
--           typically short-CD rotation spells like Judgment, Blade of Justice)
--   nil   → absent (spell off CD OR unflagged spell on CD — ambiguous)
-- When isOnGCD is nil in combat, fall back to local cooldown tracking
-- and action bar usability to detect real cooldowns.
function BlizzardAPI.IsSpellReady(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return true end
    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return true end

    -- isOnGCD == true → on GCD only, spell is effectively ready
    if cd.isOnGCD == true then return true end

    -- isOnGCD == false → real cooldown running (definitive for flagged spells)
    if cd.isOnGCD == false then return false end

    -- Out of combat: duration/startTime are readable
    local duration = Unsecret(cd.duration)
    if duration then
        return cd.startTime == 0 or (cd.startTime + duration) <= GetTime()
    end

    -- In combat with secreted values and isOnGCD == nil:
    -- Spell is either off cooldown OR on CD but unflagged (major CDs like
    -- Divine Toll, Execution Sentence, Shadow Blades) — use fallback chain

    -- Local cooldown tracking (timer from UNIT_SPELLCAST_SUCCEEDED)
    if BlizzardAPI.IsSpellOnLocalCooldown(spellID) then return false end

    -- Charge-based: if we have charges, spell is usable
    if C_Spell_GetSpellCharges then
        local csOk, chargeInfo = pcall(C_Spell_GetSpellCharges, spellID)
        if csOk and chargeInfo and chargeInfo.currentCharges then
            local currentCharges = Unsecret(chargeInfo.currentCharges)
            if currentCharges then
                return currentCharges > 0
            end
            -- currentCharges is SECRET — use cached maxCharges to know if this
            -- is even a charge spell (if not, skip to action bar fallback)
            local cached = BlizzardAPI.GetCachedMaxCharges(spellID)
            if cached and cached > 1 then
                -- Multi-charge spell but charges are secret — fail-open (assume usable)
                return true
            end
        end
    end

    -- Action bar usability (visual state, NeverSecret)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
        local slot = ActionBarScanner.GetSlotForSpell(spellID)
        if slot and C_ActionBar and C_ActionBar.IsUsableAction then
            local actionUsable, notEnoughMana = C_ActionBar.IsUsableAction(slot)
            if not IsSecretValue(actionUsable) and not IsSecretValue(notEnoughMana) then
                -- Not usable AND not a mana issue → likely on cooldown
                if actionUsable == false and not notEnoughMana then return false end
                -- Usable → spell is ready
                if actionUsable == true then return true end
            end
        end
    end

    -- Fail-open: assume ready when we can't determine state
    return true
end

function BlizzardAPI.GetAuraSpellID(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil end
    return Unsecret(aura.spellId)
end

function BlizzardAPI.GetAuraTiming(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil, nil end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil, nil end
    return Unsecret(aura.duration), Unsecret(aura.expirationTime)
end

function BlizzardAPI.GetSpellCharges(spellID)
    if not spellID or not C_Spell_GetSpellCharges then return nil, nil end
    local chargeInfo = C_Spell_GetSpellCharges(spellID)
    if not chargeInfo then return nil, nil end
    return Unsecret(chargeInfo.currentCharges), Unsecret(chargeInfo.maxCharges)
end

--------------------------------------------------------------------------------
-- Secrecy API Wrappers (12.0+)
--------------------------------------------------------------------------------

function BlizzardAPI.GetSpellCooldownSecrecy(spellID)
    if C_Secrets and C_Secrets.GetSpellCooldownSecrecy then
        local ok, lvl = pcall(C_Secrets.GetSpellCooldownSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

-- Returns nil, nil when values are secret
function BlizzardAPI.GetSafeSpellCooldown(spellID)
    if not C_Spell_GetSpellCooldown then return nil, nil end
    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return nil, nil end
    return Unsecret(cd.startTime), Unsecret(cd.duration)
end

function BlizzardAPI.GetSpellAuraSecrecy(spellID)
    if C_Secrets and C_Secrets.GetSpellAuraSecrecy then
        local ok, lvl = pcall(C_Secrets.GetSpellAuraSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

function BlizzardAPI.GetSpellCastSecrecy(spellID)
    if C_Secrets and C_Secrets.GetSpellCastSecrecy then
        local ok, lvl = pcall(C_Secrets.GetSpellCastSecrecy, spellID)
        if ok then return lvl end
    end
    return nil
end

function BlizzardAPI.ShouldUnitHealthMaxBeSecret(unitToken)
    if C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret then
        local ok, res = pcall(C_Secrets.ShouldUnitHealthMaxBeSecret, unitToken)
        if ok then return res end
    end
    return nil
end

function BlizzardAPI.GetInterfaceVersion()
    return _interfaceVersion
end

function BlizzardAPI.IsMidnightOrLater()
    return IS_MIDNIGHT_OR_LATER
end

function BlizzardAPI.VersionCall(pre12Func, post12Func, ...)
    if IS_MIDNIGHT_OR_LATER then
        return post12Func and post12Func(...) or nil
    else
        return pre12Func and pre12Func(...) or nil
    end
end

--------------------------------------------------------------------------------
-- C_Secrets Namespace Wrappers (12.0+)
--------------------------------------------------------------------------------

function BlizzardAPI.ShouldSpellCooldownBeSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
        local ok, result = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        if ok then return result end
    end
    return nil
end

function BlizzardAPI.ShouldSpellAuraBeSecret(spellID)
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, result = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
        if ok then return result end
    end
    return nil
end

function BlizzardAPI.ShouldUnitSpellCastBeSecret(unit)
    if C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret then
        local ok, result = pcall(C_Secrets.ShouldUnitSpellCastBeSecret, unit)
        if ok then return result end
    end
    return nil
end
