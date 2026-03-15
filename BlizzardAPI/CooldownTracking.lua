-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Local Cooldown Tracking (12.0+ secret value workaround)
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after BlizzardAPI.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-CooldownTracking", 3
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime               = GetTime
local pcall                 = pcall
local type                  = type
local wipe                  = wipe
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local C_Spell_GetSpellCharges  = C_Spell and C_Spell.GetSpellCharges
local GetSpellBaseCooldown     = GetSpellBaseCooldown ---@diagnostic disable-line: undefined-global
local _G                       = _G                   ---@diagnostic disable-line: undefined-global
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

--------------------------------------------------------------------------------
-- Local Cooldown Tracking (12.0+ secret value workaround)
--------------------------------------------------------------------------------
-- Track cooldowns locally when API returns secrets in 12.0+ (fail-open approach)
local localCooldowns = {}
local cachedDurations = {}
local cachedMaxCharges = {}
local trackedDefensiveSpells = {}
local trackedRotationSpells = {}
local cooldownEventFrame = nil

-- Local charge tracking for multi-charge spells (e.g. Frenzied Regeneration)
-- All GetSpellCharges fields are SECRET in combat — track charges locally via
-- cast events + cached recharge duration for lazy recovery evaluation.
local localCharges = {}

-- Minimum base cooldown (ms) to track — ignore GCD-only spells
local MIN_TRACKABLE_CD_MS = 3000

-- Hidden tooltip for parsing traited cooldown values
local probeTooltip = nil

--- Parse the talent-modified cooldown from a spell's tooltip.
--- Tooltip right-side text shows values like "30 sec cooldown" or "2 min cooldown"
--- which reflect talent modifications (e.g., Beast Within reducing BW from 90s to 30s).
--- @param spellID number
--- @return number|nil duration in seconds, or nil if not found
local function ParseTooltipCooldown(spellID)
    if not spellID or type(spellID) ~= "number" or spellID == 0 then return nil end
    -- Tooltip text is secreted in combat — skip entirely
    if InCombatLockdown() then return nil end

    -- Create the hidden scanning tooltip once
    if not probeTooltip then
        probeTooltip = CreateFrame("GameTooltip", "JustACCDProbe", nil, "GameTooltipTemplate")
    end

    probeTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    probeTooltip:ClearLines()
    local ok = pcall(probeTooltip.SetSpellByID, probeTooltip, spellID)
    if not ok then return nil end

    -- Scan right-side text for cooldown patterns (line 2 is typically "Instant  30 sec cooldown")
    for i = 1, probeTooltip:NumLines() do
        local rightText = _G["JustACCDProbeTextRight" .. i]
        if rightText then
            local text = rightText:GetText()
            if text and not IsSecretValue(text) then
                -- Match "X sec cooldown" or "X.Y sec cooldown"
                local secVal = text:match("([%d%.]+) sec cooldown")
                if secVal then
                    return tonumber(secVal)
                end
                -- Match "X min cooldown" or "X.Y min cooldown"
                local minVal = text:match("([%d%.]+) min cooldown")
                if minVal then
                    return tonumber(minVal) * 60
                end
            end
        end
    end
    return nil
end

local function IsLocalCooldownActive(spellID)
    local data = localCooldowns[spellID]
    if not data then return false end
    return GetTime() < data.endTime
end

local function GetBestCooldownDuration(spellID)
    -- 1. Actual observed duration from a previous cast (most accurate)
    if cachedDurations[spellID] and cachedDurations[spellID] > 0 then
        return cachedDurations[spellID]
    end
    -- 2. Tooltip-parsed duration (reflects talent modifications)
    local tooltipCD = ParseTooltipCooldown(spellID)
    if tooltipCD and tooltipCD > 0 then
        cachedDurations[spellID] = tooltipCD
        return tooltipCD
    end
    -- 3. Base cooldown from API (unmodified by talents — last resort)
    local baseCooldownMs = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if baseCooldownMs and baseCooldownMs > 0 then
        return baseCooldownMs / 1000
    end
    return 0
end

--- Process any completed charge recoveries for a tracked charge spell.
--- Advances current charges by checking elapsed recharge timers.
--- Called lazily on query and before recording new casts.
local function ProcessChargeRecovery(data)
    if not data or data.rechargeDuration <= 0 then return end
    local now = GetTime()
    while data.current < data.maxCharges and data.rechargeEndTime > 0 and now >= data.rechargeEndTime do
        data.current = data.current + 1
        if data.current < data.maxCharges then
            data.rechargeEndTime = data.rechargeEndTime + data.rechargeDuration
        else
            data.rechargeEndTime = 0
        end
    end
end

local function RecordSpellCooldown(spellID)
    if not spellID or spellID == 0 then return end
    if not trackedDefensiveSpells[spellID] and not trackedRotationSpells[spellID] then return end

    -- Charge-based spells: decrement local charge count instead of recording
    -- a flat cooldown. Local CD tracking would record a full-duration CD on every
    -- cast, but charge spells remain usable while charges > 0.
    local maxCharges = cachedMaxCharges[spellID]
    if maxCharges and maxCharges > 1 then
        local data = localCharges[spellID]
        if data then
            local now = GetTime()
            ProcessChargeRecovery(data)
            data.current = data.current - 1
            if data.current < 0 then data.current = 0 end
            -- Start recharge timer if not already running
            if data.rechargeDuration > 0 and (data.rechargeEndTime <= 0 or now >= data.rechargeEndTime) then
                data.rechargeEndTime = now + data.rechargeDuration
            end
        end
        return
    end

    local now = GetTime()
    local duration = 0
    local inCombat = InCombatLockdown()

    if not inCombat and C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd and cd.duration and not IsSecretValue(cd.duration) and cd.duration > 0 then
            -- Only cache if it's a real cooldown (> 3s), not a GCD read
            if cd.duration > MIN_TRACKABLE_CD_MS / 1000 then
                duration = cd.duration
                cachedDurations[spellID] = duration
            end
        end
    end

    if duration == 0 then
        duration = GetBestCooldownDuration(spellID)
    end

    if duration > 0 then
        localCooldowns[spellID] = {
            endTime = now + duration,
            duration = duration,
            startTime = now,
        }
    end
end

local function ClearLocalCooldowns()
    wipe(localCooldowns)
    wipe(localCharges)
end

local function ClearCachedDurations()
    wipe(cachedDurations)
    wipe(cachedMaxCharges)
    wipe(localCooldowns)
    wipe(localCharges)
end

--- Cache maxCharges and current charge state for a spell.
--- Call out of combat only — all GetSpellCharges fields are SECRET in combat.
local function CacheChargesForSpell(spellID)
    if not spellID or not C_Spell_GetSpellCharges then return end
    if InCombatLockdown() then return end  -- fields are ALL SECRET in combat
    local ok, chargeInfo = pcall(C_Spell_GetSpellCharges, spellID)
    if ok and chargeInfo then
        local maxCharges = Unsecret(chargeInfo.maxCharges)
        if maxCharges then
            cachedMaxCharges[spellID] = maxCharges
            if maxCharges > 1 then
                local current = Unsecret(chargeInfo.currentCharges) or maxCharges
                local rechargeDuration = Unsecret(chargeInfo.cooldownDuration) or 0
                local rechargeEndTime = 0
                if current < maxCharges and rechargeDuration > 0 then
                    local start = Unsecret(chargeInfo.cooldownStartTime)
                    if start and start > 0 then
                        rechargeEndTime = start + rechargeDuration
                    end
                end
                localCharges[spellID] = {
                    current = current,
                    maxCharges = maxCharges,
                    rechargeDuration = rechargeDuration,
                    rechargeEndTime = rechargeEndTime,
                }
            end
        end
    end
end

--- Pre-cache cooldown durations for all tracked spells.
--- Called on PLAYER_REGEN_ENABLED — all CD fields are readable out of combat.
--- This prevents first-combat-session edge cases where RecordSpellCooldown
--- has no cached duration and falls back to unmodified GetSpellBaseCooldown.
local function ScanCooldownDurations()
    if InCombatLockdown() or not C_Spell_GetSpellCooldown then return end
    local function scanSpell(spellID)
        -- Skip if already cached with a real value
        if cachedDurations[spellID] and cachedDurations[spellID] > 0 then return end
        local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
        if ok and cd then
            local duration = Unsecret(cd.duration)
            if duration and duration > 0 and duration > MIN_TRACKABLE_CD_MS / 1000 then
                cachedDurations[spellID] = duration
            end
        end
        -- Also cache maxCharges while we're at it
        CacheChargesForSpell(spellID)
    end
    for spellID in pairs(trackedRotationSpells) do
        scanSpell(spellID)
    end
    for spellID in pairs(trackedDefensiveSpells) do
        scanSpell(spellID)
    end
end

--- Check tracked spells with active local cooldowns for early CD completion.
--- Called on SPELL_UPDATE_COOLDOWN — if isOnGCD is true for a spell we think
--- is on cooldown, the real CD has ended (e.g., CDR proc reduced it).
--- NOTE: Only works for spells that trigger GCD. Off-GCD spells (Shadow Blades,
--- Shadow Dance, etc.) go from nil→nil so this can't detect their early completion.
--- For those, the local timer naturally expires or action bar usability catches it.
---
--- @param eventSpellID number|nil  spellID from SPELL_UPDATE_COOLDOWN payload.
---   NeverSecret in combat (verified 2026-02-25). When non-nil, only that spell
---   is checked (O(1) instead of O(n)). When nil (batch "refresh all" signal),
---   falls back to iterating all tracked cooldowns.
local function CheckCooldownCompletions(eventSpellID)
    if not C_Spell_GetSpellCooldown then return end

    -- Targeted check: event told us exactly which spell changed
    if eventSpellID then
        local data = localCooldowns[eventSpellID]
        if data and GetTime() < data.endTime then
            local ok, cd = pcall(C_Spell_GetSpellCooldown, eventSpellID)
            if ok and cd and cd.isOnGCD == true then
                localCooldowns[eventSpellID] = nil
            end
        end
        return
    end

    -- Batch refresh (nil spellID): scan all tracked cooldowns
    for spellID, data in pairs(localCooldowns) do
        if GetTime() < data.endTime then
            local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
            if ok and cd then
                -- isOnGCD is NeverSecret: true = GCD only (real CD done)
                if cd.isOnGCD == true then
                    localCooldowns[spellID] = nil
                end
            end
        end
    end
end

local function InitCooldownTracking()
    if cooldownEventFrame then return end

    cooldownEventFrame = CreateFrame("Frame")
    cooldownEventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    cooldownEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    cooldownEventFrame:RegisterEvent("PLAYER_DEAD")
    cooldownEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    cooldownEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    cooldownEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    cooldownEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    cooldownEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    cooldownEventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, castGUID, spellID = ...
            if unit == "player" and spellID then
                RecordSpellCooldown(spellID)
            end
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            -- spellID payload is NeverSecret in combat (verified 2026-02-25)
            local spellID = ...
            CheckCooldownCompletions(spellID)
        elseif event == "PLAYER_DEAD" or event == "PLAYER_ENTERING_WORLD" then
            ClearLocalCooldowns()
            -- Re-scan OOC after world load — rotation list may not be registered yet
            -- so this is a best-effort pre-cache for any already-registered spells.
            ScanCooldownDurations()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Combat exit: scan all tracked spells while CD fields are readable
            ClearLocalCooldowns()
            ScanCooldownDurations()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
            ClearCachedDurations()
            -- Re-scan with new talent-adjusted durations (OOC only — in-combat
            -- talent changes are impossible under normal gameplay conditions)
            ScanCooldownDurations()
        end
    end)
end

function BlizzardAPI.RegisterDefensiveSpell(spellID)
    if not spellID or spellID == 0 then return end
    trackedDefensiveSpells[spellID] = true
    -- Pre-cache charges while out of combat (ALL fields SECRET in combat)
    CacheChargesForSpell(spellID)
    if not cooldownEventFrame then
        InitCooldownTracking()
    end
end

function BlizzardAPI.ClearTrackedDefensives()
    wipe(trackedDefensiveSpells)
    wipe(localCooldowns)
end

--- Register a rotation spell for local cooldown tracking.
--- Only tracks spells with effective CD > MIN_TRACKABLE_CD_MS (3s)
--- to avoid treating GCD-only spells as on-cooldown.
function BlizzardAPI.RegisterRotationSpell(spellID)
    if not spellID or spellID == 0 then return end
    -- Already registered — skip redundant tooltip scan
    if trackedRotationSpells[spellID] then return end

    -- Only track spells with a real cooldown (> 3s)
    -- Check cached duration first (avoids tooltip scan if already known)
    local effectiveCdMs
    if cachedDurations[spellID] and cachedDurations[spellID] > 0 then
        effectiveCdMs = cachedDurations[spellID] * 1000
    else
        -- Tooltip reflects talent modifications (only works out of combat)
        local tooltipCD = ParseTooltipCooldown(spellID)
        if tooltipCD and tooltipCD > 0 then
            effectiveCdMs = tooltipCD * 1000
            cachedDurations[spellID] = tooltipCD
        else
            -- Fall back to base CD (unmodified by talents)
            effectiveCdMs = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID) or 0
        end
    end
    if effectiveCdMs < MIN_TRACKABLE_CD_MS then return end
    trackedRotationSpells[spellID] = true
    -- Pre-cache charges while out of combat (ALL fields SECRET in combat)
    CacheChargesForSpell(spellID)
    if not cooldownEventFrame then
        InitCooldownTracking()
    end
end

function BlizzardAPI.ClearTrackedRotationSpells()
    wipe(trackedRotationSpells)
    -- Don't wipe localCooldowns here — defensives may still need them.
    -- Stale rotation entries expire naturally via endTime.
end

function BlizzardAPI.IsSpellOnLocalCooldown(spellID)
    return IsLocalCooldownActive(spellID)
end

--- Get cached maxCharges for a spell. Returns nil if unknown.
--- Populated at spell registration (out of combat) and refreshed on combat exit.
--- ALL GetSpellCharges fields are SECRET in combat (verified 2026-02-25).
function BlizzardAPI.GetCachedMaxCharges(spellID)
    return cachedMaxCharges[spellID]
end

--- Returns true when a charge-based spell has 0 charges remaining.
--- Uses local charge tracking (cast decrements + lazy recharge recovery).
--- Returns false (fail-open) if the spell has no cached charge data.
function BlizzardAPI.IsChargeSpellOnCooldown(spellID)
    local data = localCharges[spellID]
    if not data then return false end
    ProcessChargeRecovery(data)
    return data.current <= 0
end

--------------------------------------------------------------------------------
-- Spell Readiness (moved from SecretValues — depends on local CD tracking state)
--------------------------------------------------------------------------------

--- Check if a spell is ready (not on a real cooldown).
--- 12.0 combat: duration/startTime are blanket-secreted.
--- isOnGCD is NeverSecret with three observable states:
---   true  → GCD only (spell is ready, just on GCD)
---   false → real cooldown running (only for spells Blizzard flags internally;
---           typically short-CD rotation spells like Judgment, Blade of Justice)
---   nil   → absent (spell off CD OR unflagged spell on CD — ambiguous)
--- When isOnGCD is nil in combat, fall back to local cooldown tracking
--- and action bar usability to detect real cooldowns.
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
    if IsLocalCooldownActive(spellID) then return false end

    -- Charge-based: use local charge tracking (lazy recovery evaluation)
    local cached = cachedMaxCharges[spellID]
    if cached and cached > 1 then
        local data = localCharges[spellID]
        if data then
            ProcessChargeRecovery(data)
            return data.current > 0
        end
        -- No local charge data — fall through to action bar fallback
    end

    -- Action bar usability (visual state, NeverSecret)
    local actionUsable, notEnoughMana = BlizzardAPI.GetActionBarUsability(spellID)
    if actionUsable ~= nil then
        -- Not usable AND not a mana issue → likely on cooldown
        if actionUsable == false and not notEnoughMana then return false end
        -- Usable → spell is ready
        if actionUsable == true then return true end
    end

    -- Fail-open: assume ready when we can't determine state
    return true
end


