-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Local Cooldown Tracking (12.0+ secret value workaround)
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after BlizzardAPI.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-CooldownTracking", 13
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
local C_Spell_GetBaseSpell     = C_Spell and C_Spell.GetBaseSpell
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
local cooldownEventFrame = nil

-- Unified spell tracking: spellID → category string
-- Categories: "defensive", "rotation", "burst", "gapcloser", "interrupt"
-- Only "rotation" has a CD duration gate (>3s) - all others register unconditionally.
local trackedSpells = {}

-- Local charge tracking for multi-charge spells (e.g. Frenzied Regeneration)
-- All GetSpellCharges fields are SECRET in combat - track charges locally via
-- cast events + cached recharge duration for lazy recovery evaluation.
local localCharges = {}

-- Minimum base cooldown to track - ignore GCD-only spells
local MIN_TRACKABLE_CD_SECS = 3

--- Resolve a display/override spellID to its castable base (override -> base),
--- trying both APIs and returning the first that actually differs. nil if none.
function BlizzardAPI.ResolveBaseSpellID(spellID)
    if C_Spell_GetBaseSpell then
        local ok, b = pcall(C_Spell_GetBaseSpell, spellID)
        if ok and type(b) == "number" and b > 0 and b ~= spellID then return b end
    end
    if FindBaseSpellByID then
        local ok, b = pcall(FindBaseSpellByID, spellID)
        if ok and type(b) == "number" and b > 0 and b ~= spellID then return b end
    end
    return nil
end

-- Base cooldown (seconds) for a spell, cached. MUST be populated OUT of combat -
-- GetSpellBaseCooldown returns secrets in combat, so an unreadable value is NOT
-- cached (it's retried on the next OOC pass). Charge-based spells report 0 base
-- CD; fall back to their per-charge recharge time. Shared by the engines.
local baseCdSecondsCache = {}
function BlizzardAPI.GetBaseCooldownSeconds(spellID)
    if not spellID or spellID <= 0 then return 0 end
    local cached = baseCdSecondsCache[spellID]
    if cached ~= nil then return cached end
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if ms == nil or IsSecretValue(ms) then
        return 0  -- unreadable (in combat): don't cache; a later OOC pass fills it
    end
    local sec = (ms > 0) and (ms / 1000) or 0
    if sec == 0 and C_Spell_GetSpellCharges then
        local ok, charges = pcall(C_Spell_GetSpellCharges, spellID)
        if ok and charges and charges.cooldownDuration
           and not IsSecretValue(charges.cooldownDuration) and charges.cooldownDuration > 0 then
            sec = charges.cooldownDuration
        end
    end
    baseCdSecondsCache[spellID] = sec
    return sec
end

--- Cache-only read of the base cooldown: never touches the API, so it is safe
--- for per-tick combat checks (returns 0 until an OOC pass has filled the cache).
function BlizzardAPI.PeekBaseCooldownSeconds(spellID)
    return (spellID and baseCdSecondsCache[spellID]) or 0
end

--- Pre-cache base cooldowns for every spell in the Blizzard rotation list.
--- Must be called OUT of combat (GetSpellBaseCooldown returns secrets in combat).
--- Safe to call repeatedly - already-cached spells are skipped above.
function BlizzardAPI.PreCacheRotationCooldowns()
    if not BlizzardAPI.GetRotationSpells then return end
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells then return end
    for _, spellID in ipairs(rotationSpells) do
        if spellID and spellID > 0 then
            BlizzardAPI.GetBaseCooldownSeconds(spellID)
        end
    end
end

-- Hidden tooltip for parsing traited cooldown values
local probeTooltip = nil

--- Parse the talent-modified cooldown from a spell's tooltip.
--- Tooltip right-side text shows values like "30 sec cooldown" or "2 min cooldown"
--- which reflect talent modifications (e.g., Beast Within reducing BW from 90s to 30s).
--- @param spellID number
--- @return number|nil duration in seconds, or nil if not found
local function ParseTooltipCooldown(spellID)
    if not spellID or type(spellID) ~= "number" or spellID == 0 then return nil end
    -- Tooltip text is secreted alongside cooldowns - skip while restricted
    if BlizzardAPI.AreCooldownsSecret() then return nil end

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

-- Static base cooldown/charge data generated from client data (Data/SpellCooldowns.lua).
-- Unlike every runtime CD API, it can't be secreted - the only source that works
-- for a spell first seen mid-combat (battle res, first engage after login).
local staticCooldownData
local function GetStaticCooldownData()
    if staticCooldownData == nil then
        staticCooldownData = LibStub("JustAC-CooldownData", true) or false
    end
    return staticCooldownData or nil
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
    -- 3. Base cooldown from API (unmodified by talents; SECRET in combat -
    --    an unguarded secret here would compare truthy and shadow tier 4)
    local baseCooldownMs = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
    if baseCooldownMs and not IsSecretValue(baseCooldownMs) and baseCooldownMs > 0 then
        return baseCooldownMs / 1000
    end
    -- 4. Static client data (base values; readable in combat - last resort)
    local staticData = GetStaticCooldownData()
    if staticData then
        local cdMs = staticData.Get(spellID)
        -- Base-resolve: the static table is keyed by base IDs, but this can be
        -- reached with a talent-override cast ID (first seen mid-combat).
        if not cdMs or cdMs == 0 then
            local base = BlizzardAPI.ResolveBaseSpellID(spellID)
            if base then cdMs = staticData.Get(base) end
        end
        if cdMs and cdMs > 0 then
            return cdMs / 1000
        end
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
    if not trackedSpells[spellID] then return end

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

    if not BlizzardAPI.AreCooldownsSecret() and C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd and cd.duration and not IsSecretValue(cd.duration) and cd.duration > 0 then
            -- Only cache if it's a real cooldown (> 3s), not a GCD read
            if cd.duration > MIN_TRACKABLE_CD_SECS then
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

--- Read the API cooldown for spellID and store it in localCooldowns if a real
--- (>1.5s, non-GCD) CD is running. OOC only - caller checks AreCooldownsSecret.
local function SeedCooldownFromAPI(spellID, now)
    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return end
    local duration = Unsecret(cd.duration)
    local startTime = Unsecret(cd.startTime)
    if duration and duration > 1.5 and startTime and startTime > 0 then
        local endTime = startTime + duration
        if endTime > now then
            localCooldowns[spellID] = {
                endTime = endTime,
                duration = duration,
                startTime = startTime,
            }
        end
    end
end

--- Resync local cooldowns from the API (out of combat only).
--- Preserves CD tracking across combat transitions by reading actual CD state
--- when the data is readable (OOC), instead of wiping it.
local function ResyncLocalCooldowns()
    if BlizzardAPI.AreCooldownsSecret() or not C_Spell_GetSpellCooldown then return end
    local now = GetTime()
    wipe(localCooldowns)
    for spellID in pairs(trackedSpells) do
        SeedCooldownFromAPI(spellID, now)
    end
    -- Charge state is resynced by ScanCooldownDurations → CacheChargesForSpell
    wipe(localCharges)
end

local function ClearCachedDurations()
    wipe(cachedDurations)
    wipe(cachedMaxCharges)
    wipe(localCooldowns)
    wipe(localCharges)
end

--- At maximum charges right now (charge regen idle, so holding it wastes recharge
--- time)? maxCharges and isActive are NeverSecret - validated in combat 2026-07-24:
--- isActive false == not recharging, which with maxCharges > 1 means capped.
--- Fail-open: any doubt reads as "not capped".
function BlizzardAPI.IsSpellChargeCapped(spellID)
    if not spellID or not C_Spell_GetSpellCharges then return false end
    local ok, ci = pcall(C_Spell_GetSpellCharges, spellID)
    if not ok or not ci then return false end
    local maxC = Unsecret(ci.maxCharges)
    if not maxC or maxC < 2 then return false end
    local active = ci.isActive
    if BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(active) then return false end
    return active == false
end

--- Cache maxCharges and current charge state for a spell.
--- Call out of combat only - currentCharges, cooldownStartTime, cooldownDuration,
--- chargeModRate are SECRET in combat. maxCharges and isActive are NeverSecret
--- (source-verified), but this function still guards against combat as a conservative
--- measure since the other fields it reads are secret.
local function CacheChargesForSpell(spellID)
    if not spellID then return end
    if C_Spell_GetSpellCharges and not BlizzardAPI.AreCooldownsSecret() then
        -- currentCharges/cooldownDuration are SECRET in combat; live read is OOC-only
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
                return
            end
        end
    end

    -- Fallback (in combat, or full live read unavailable): maxCharges is
    -- NeverSecret even in combat, so take the live talent-accurate value when
    -- readable and only the recharge duration (secret in combat) from client
    -- data. Full charges = fail-toward-usable, same as the live path's defaults,
    -- so charge spells registered mid-combat still track instead of failing open.
    if localCharges[spellID] then return end
    local liveMax
    if C_Spell_GetSpellCharges then
        local ok, ci = pcall(C_Spell_GetSpellCharges, spellID)
        if ok and ci then liveMax = Unsecret(ci.maxCharges) end
    end
    local staticData = GetStaticCooldownData()
    local staticMax, rechargeMs
    if staticData then
        local _
        _, staticMax, rechargeMs = staticData.Get(spellID)
    end
    local maxCharges = liveMax or staticMax
    if maxCharges and maxCharges > 1 then
        cachedMaxCharges[spellID] = cachedMaxCharges[spellID] or maxCharges
        localCharges[spellID] = {
            current = maxCharges,
            maxCharges = maxCharges,
            rechargeDuration = (rechargeMs or 0) / 1000,
            rechargeEndTime = 0,
        }
    end
end

--- Pre-cache cooldown durations for all tracked spells.
--- Called on PLAYER_REGEN_ENABLED - all CD fields are readable out of combat.
--- This prevents first-combat-session edge cases where RecordSpellCooldown
--- has no cached duration and falls back to unmodified GetSpellBaseCooldown.
local function ScanCooldownDurations()
    if BlizzardAPI.AreCooldownsSecret() or not C_Spell_GetSpellCooldown then return end
    local function scanSpell(spellID)
        -- Skip if already cached with a real value
        if cachedDurations[spellID] and cachedDurations[spellID] > 0 then return end
        local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
        if ok and cd then
            local duration = Unsecret(cd.duration)
            if duration and duration > 0 and duration > MIN_TRACKABLE_CD_SECS then
                cachedDurations[spellID] = duration
            end
        end
        -- Spell is ready (duration=0) but cachedDurations still nil after
        -- ClearCachedDurations: populate via tooltip+GetSpellBaseCooldown so
        -- RecordSpellCooldown has a duration available on the first cast.
        if not (cachedDurations[spellID] and cachedDurations[spellID] > 0) then
            local tooltipCD = ParseTooltipCooldown(spellID)
            if tooltipCD and tooltipCD > 0 then
                cachedDurations[spellID] = tooltipCD
            else
                local baseCdMs = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID) or 0
                if baseCdMs > 0 then
                    cachedDurations[spellID] = baseCdMs / 1000
                end
            end
        end
        -- Also cache maxCharges while we're at it
        CacheChargesForSpell(spellID)
    end
    for spellID in pairs(trackedSpells) do
        scanSpell(spellID)
    end
end

--- Check tracked spells with active local cooldowns for early CD completion.
--- Called on SPELL_UPDATE_COOLDOWN. Detection method:
---   isOnGCD == true → GCD only, real CD has ended (flagged rotation spells).
---   isOnGCD == false → real CD definitely running (no action needed).
---   isOnGCD == nil → unflagged spell; cannot determine CD state from API alone.
---     IsUsableAction returns true even on cooldown, so action bar cross-checks
---     produce false positives. Trust the local CD timer instead - it expires
---     naturally, and CDR edge cases self-correct at combat exit via ResyncLocalCooldowns.
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
            if ok and cd then
                if cd.isOnGCD == true then
                    -- isOnGCD=true means "GCD only, real CD done" - but ONLY for
                    -- Blizzard-flagged rotation spells (nil→false→nil CD pattern).
                    -- For unflagged interrupts/defensives/etc., isOnGCD=true fires
                    -- during the GCD window right after casting (unflagged pattern:
                    -- nil→true(GCD)→nil). Clearing here would wipe the local CD
                    -- immediately, causing IsSpellReady to fail-open and show the
                    -- spell as ready on the very next frame. Only clear for "rotation".
                    if trackedSpells[eventSpellID] == "rotation" then
                        localCooldowns[eventSpellID] = nil
                    end
                elseif cd.isOnGCD == nil and cd.isActive == false then
                    -- isActive is NeverSecret ground truth (same signal IsSpellReady
                    -- trusts): isOnGCD==nil (outside the GCD window) + isActive==false
                    -- means NO cooldown timer is running. Our local timer is stale -
                    -- a CDR/reset effect we couldn't observe - so clear it, for ALL
                    -- categories (interrupts/defensives/gap-closers, not just
                    -- rotation). Explicit ==false: nil/secret must never clear.
                    localCooldowns[eventSpellID] = nil
                end
                -- isOnGCD == false: real CD running - no action needed.
            end
        end
        return
    end

    -- Batch refresh (nil spellID): scan all tracked cooldowns
    for spellID, data in pairs(localCooldowns) do
        if GetTime() < data.endTime then
            local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
            if ok and cd then
                if cd.isOnGCD == true and trackedSpells[spellID] == "rotation" then
                    -- See targeted-check comment above: only rotation-category spells
                    -- are reliably Blizzard-flagged and use the nil→false→nil pattern.
                    localCooldowns[spellID] = nil
                elseif cd.isOnGCD == nil and cd.isActive == false then
                    -- Stale entry, all categories - see targeted-check comment above.
                    localCooldowns[spellID] = nil
                end
            end
        end
    end
end

--- SPELL_UPDATE_CHARGES sweep: on the charges struct, chargeInfo.isActive is
--- NeverSecret in combat while every other field except maxCharges is secret
--- (field-verified 2026-07-01 via /jac inspect chargediag). isActive == false
--- means no recharge is running, which is only possible at FULL charges - so a
--- local count below max is stale (talent charge refund, haste-drifted recharge
--- timer) and snaps to full. Refunds that don't reach full (0/2 -> 1/2) stay
--- invisible here (isActive remains true) - those are covered by the
--- usable-flip hint and the AC-pick oracle. The event carries no payload
--- (verified same date), so sweep all tracked charge spells.
local function CheckChargeCorrections()
    if not C_Spell_GetSpellCharges then return end
    for spellID, data in pairs(localCharges) do
        if data.current < data.maxCharges then
            local ok, ci = pcall(C_Spell_GetSpellCharges, spellID)
            if ok and ci and ci.isActive == false then
                data.current = data.maxCharges
                data.rechargeEndTime = 0
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Secret-safe readiness probes (12.0). Cooldown-remaining and aura durations are
-- secret in combat, but a DurationObject fed into a scratch Cooldown widget drives
-- that widget's SHOWN state, and IsShown() is a plain, branchable boolean. So we
-- read "on cooldown?" / "buff active?" as engine truth without ever touching the
-- secret numbers. (Verified in combat: numeric startTime SECRET, probe still correct.)
-- The remaining TIME stays unreadable - only the boolean is exposed, which is all a
-- gate needs. Reads fail safe: no duration object / no aura -> false.
-- This is an UNINTENDED workaround Blizzard could close - see
-- Documentation/SECRET_VALUE_READINESS_PROBE.md for the /jac inspect durprobe
-- detector and the fallback ladder if it stops working.
local scratchCooldown
local function DurationObjectActive(durObj)
    if durObj == nil then return false end
    if not scratchCooldown then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()  -- parent hidden -> the probe frame never renders
        scratchCooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    end
    if not scratchCooldown.SetCooldownFromDurationObject then return false end
    scratchCooldown:SetCooldownFromDurationObject(durObj)
    local shown = scratchCooldown:IsShown()
    scratchCooldown:SetCooldown(0, 0)
    return shown and true or false
end

--- True while spellID is on a REAL cooldown (GCD excluded), read as engine truth.
function BlizzardAPI.IsSpellOnCooldown(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldownDuration) then return false end
    return DurationObjectActive(C_Spell.GetSpellCooldownDuration(spellID, true))
end

--- True while our own self-buff (spellID) is active on the player. The aura's
--- DurationObject is engine truth - no cast-time bookkeeping or shipped duration DB.
--- @param spellID number the buff id a SimC buff-window gate references (5217, ...)
function BlizzardAPI.IsBuffWindowActive(spellID)
    if not (spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            and C_UnitAuras.GetAuraDuration) then
        return false
    end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    local instId = aura and aura.auraInstanceID
    if not instId then return false end
    return DurationObjectActive(C_UnitAuras.GetAuraDuration("player", instId))
end

--- Diagnostic: which of the given self-buff ids are active right now.
--- @param ids number[] spell ids to probe
--- @return table snapshot array of { id, active }
function BlizzardAPI.GetBuffWindowSnapshot(ids)
    local out = {}
    if type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        out[#out + 1] = { id = id, active = BlizzardAPI.IsBuffWindowActive(id) }
    end
    return out
end

local function InitCooldownTracking()
    if cooldownEventFrame then return end

    cooldownEventFrame = CreateFrame("Frame")
    -- Unit-filtered: fires for every unit in the area otherwise (heavy in cities)
    cooldownEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    cooldownEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    cooldownEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    -- Deliberately NOT wiping on PLAYER_DEAD: real cooldowns persist through death,
    -- and wiping left the tracker empty after a battle res (the OOC-only resync
    -- can't run mid-combat), failing everything open. Stale entries self-heal via
    -- the isActive clear in CheckCooldownCompletions + the combat-exit resync.
    cooldownEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    cooldownEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    cooldownEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    cooldownEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    cooldownEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    cooldownEventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit == "player" and spellID then
                RecordSpellCooldown(spellID)
            end
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            -- spellID payload is NeverSecret in combat (verified 2026-02-25)
            local spellID = ...
            CheckCooldownCompletions(spellID)
        elseif event == "SPELL_UPDATE_CHARGES" then
            CheckChargeCorrections()
        elseif event == "PLAYER_ENTERING_WORLD" then
            ClearLocalCooldowns()
            -- Re-scan OOC after world load - rotation list may not be registered yet
            -- so this is a best-effort pre-cache for any already-registered spells.
            ScanCooldownDurations()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Combat exit: resync from API instead of wiping, so CDs that are
            -- still ticking survive into the next combat session.
            ResyncLocalCooldowns()
            ScanCooldownDurations()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
            ClearCachedDurations()
            -- Re-scan with new talent-adjusted durations (OOC only - in-combat
            -- talent changes are impossible under normal gameplay conditions)
            ScanCooldownDurations()
        end
    end)
end

--- Register a spell for local cooldown tracking.
--- @param spellID number
--- @param category string One of: "defensive", "rotation", "burst", "gapcloser", "interrupt"
---   Only "rotation" has a CD duration gate (>3s) - all others register unconditionally.
---   Duration is always cached regardless of category (needed by RecordSpellCooldown).
function BlizzardAPI.RegisterSpellForTracking(spellID, category)
    if not spellID or spellID == 0 then return end
    if trackedSpells[spellID] then return end  -- already registered

    -- Resolve the best-known duration for the rotation gate below. The tooltip
    -- tier self-caches into cachedDurations; static tier-4 values are deliberately
    -- NOT persisted - ScanCooldownDurations' already-cached guard would otherwise
    -- block the talent-accurate OOC refresh with a stale base value for the session.
    local bestDuration = cachedDurations[spellID]
    if not bestDuration or bestDuration <= 0 then
        bestDuration = GetBestCooldownDuration(spellID)
    end

    -- A charge ability's cooldown lives on its per-charge recharge, so GetSpellBaseCooldown
    -- reads ~0 and the rotation gate below would drop it - leaving IsSpellReady and the
    -- charge UI with no charge data. maxCharges is NeverSecret (readable in combat,
    -- verified 2026-06-30), so detect charge spells directly and exempt them from the gate.
    local isChargeSpell = false
    if C_Spell_GetSpellCharges then
        local ok, ci = pcall(C_Spell_GetSpellCharges, spellID)
        if ok and ci and (Unsecret(ci.maxCharges) or 0) > 1 then isChargeSpell = true end
    end

    -- Only "rotation" category has the CD duration gate; charge spells are exempt.
    if category == "rotation" and not isChargeSpell then
        if bestDuration * 1000 < MIN_TRACKABLE_CD_SECS * 1000 then return end
    end

    trackedSpells[spellID] = category or "rotation"
    CacheChargesForSpell(spellID)
    if not cooldownEventFrame then
        InitCooldownTracking()
    end
end

function BlizzardAPI.ClearTrackedDefensives()
    for spellID, cat in pairs(trackedSpells) do
        if cat == "defensive" then
            trackedSpells[spellID] = nil
        end
    end
    wipe(localCooldowns)
end

function BlizzardAPI.ClearTrackedRotationSpells()
    for spellID, cat in pairs(trackedSpells) do
        if cat == "rotation" then
            trackedSpells[spellID] = nil
        end
    end
    -- Don't wipe localCooldowns here - other categories still need them.
    -- Stale rotation entries expire naturally via endTime.
end

function BlizzardAPI.IsSpellOnLocalCooldown(spellID)
    return IsLocalCooldownActive(spellID)
end

--- The AC pick is a readiness oracle: Blizzard's engine never recommends an
--- uncastable spell. A proc-driven CD reset or charge refund fires no
--- UNIT_SPELLCAST_SUCCEEDED, so the local tracker can hold a stale entry that
--- keeps sinking the spell in the queue - the pick corrects it. Called from
--- SpellQueue on every build with the current recommendation.
--- Freshness guard: the pick lags a just-completed cast (Blizzard refreshes it
--- on its own cadence), so an entry recorded within the last RECOMMEND_GRACE_SECS
--- is the cast we just observed, not a stale one - leave it alone.
local RECOMMEND_GRACE_SECS = 1.5
function BlizzardAPI.NoteSpellRecommended(spellID)
    if not spellID or spellID == 0 then return end
    local now = GetTime()
    local data = localCooldowns[spellID]
    if data and (now - data.startTime) > RECOMMEND_GRACE_SECS then
        localCooldowns[spellID] = nil
    end
    local cdata = localCharges[spellID]
    if cdata then
        ProcessChargeRecovery(cdata)
        if cdata.current < 1 then
            -- rechargeEndTime - rechargeDuration = when the last charge was spent
            local rechargeStart = cdata.rechargeEndTime - cdata.rechargeDuration
            if cdata.rechargeEndTime <= 0 or (now - rechargeStart) > RECOMMEND_GRACE_SECS then
                cdata.current = 1
            end
        end
    end
end

--- Non-secret locally-tracked cooldown timing for the swipe display.
--- Returns startTime, duration (our own numbers - NeverSecret, readable in combat),
--- or nil when the spell isn't tracked or its cooldown has elapsed. Used for the
--- cooldown swipe on modifier-macro / off-bar icons, where the action-bar slot
--- can't be trusted (it reflects the macro's current resolution) and the spell
--- API's start/duration are secret in combat. Because these are stable, modifier-
--- independent numbers, the swipe set from them keeps running after the modifier
--- is released instead of flickering away.
function BlizzardAPI.GetLocalCooldown(spellID)
    local data = localCooldowns[spellID]
    if data and GetTime() < data.endTime then
        return data.startTime, data.duration
    end
    -- Charge spells are tracked separately (localCharges), not as a flat cooldown.
    -- Only when down to 0 charges is the ability fully unavailable - then the next
    -- charge's recharge is effectively the spell's cooldown, so surface it for the
    -- main swipe. With charges in hand we return nil (the ability is usable; the
    -- recharge shows on the charge edge ring, not the full swipe).
    local cdata = localCharges[spellID]
    if cdata then
        ProcessChargeRecovery(cdata)
        if cdata.current <= 0 and cdata.rechargeDuration > 0 and cdata.rechargeEndTime > 0 then
            return cdata.rechargeEndTime - cdata.rechargeDuration, cdata.rechargeDuration
        end
    end
    return nil
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

--- Returns true when a charge-based spell has ALL of its charges banked.
--- Uses the same non-secret local tracking as IsChargeSpellOnCooldown, so it is
--- readable in combat. A spell with no charge data (single-charge, or not yet
--- scanned) returns true - callers pair this with IsSpellReady, which supplies
--- the plain off-cooldown answer for those.
function BlizzardAPI.IsSpellAtMaxCharges(spellID)
    local data = localCharges[spellID]
    if not data then return true end
    ProcessChargeRecovery(data)
    return data.current >= data.maxCharges
end

-- Debug: report a spell's presence in the tracking caches. Diagnoses the sink/readiness
-- gap where a spell falls outside local CD/charge tracking and IsSpellReady fails open in
-- combat. Returns: category|nil, maxCharges|nil, currentCharges|nil, localCDActive(bool).
function BlizzardAPI.DebugTrackingState(spellID)
    if not spellID then return nil, nil, nil, false end
    local cdata = localCharges[spellID]
    return trackedSpells[spellID], cachedMaxCharges[spellID], cdata and cdata.current, localCooldowns[spellID] ~= nil
end

--------------------------------------------------------------------------------
-- Spell Readiness (moved from SecretValues - depends on local CD tracking state)
--------------------------------------------------------------------------------

--- Check if a spell is ready (not on a real cooldown).
--- 12.0 combat: duration/startTime are blanket-secreted.
--- isOnGCD is NeverSecret with three observable states:
---   true  → GCD only (spell is ready, just on GCD)
---   false → real cooldown running (only for spells Blizzard flags internally;
---           typically short-CD rotation spells like Judgment, Blade of Justice)
---   nil   → absent (spell off CD OR unflagged spell on CD - ambiguous)
--- When isOnGCD is nil in combat, SpellCooldownInfo.isActive (NeverSecret) is
--- used as ground truth: true → real unflagged CD running; false → spell ready.
--- Returns true if the spell is known to NOT trigger the global cooldown.
--- Second return (diagnostics only, e.g. /jac why): a short string naming which
--- signal decided the verdict. Callers on hot paths ignore it (no allocation).
function BlizzardAPI.IsSpellReady(spellID)
    if not spellID or not C_Spell_GetSpellCooldown then return true, "no cooldown API" end

    -- Charge-based spells are "ready" while any charge remains, even with a charge
    -- recharging underneath (C_Spell.GetSpellCooldown reflects that recharge and
    -- would otherwise misreport the spell as on cooldown). Use the non-secret local
    -- charge tracking - readable in combat. Only 0 charges counts as not ready.
    -- Spells without tracked charge data fall through to the cooldown logic below.
    local maxCharges = cachedMaxCharges[spellID]
    if maxCharges and maxCharges > 1 then
        local cdata = localCharges[spellID]
        if cdata then
            ProcessChargeRecovery(cdata)
            return cdata.current >= 1, "local charge tracking"
        end
    end

    local ok, cd = pcall(C_Spell_GetSpellCooldown, spellID)
    if not ok or not cd then return true, "cooldown query failed (fail-open)" end

    -- isOnGCD == true → GCD only for unflagged spells.
    -- However, unflagged spells with real CDs also show isOnGCD=true during
    -- GCD (~1.5s). Check local tracking: if a real CD is ticking underneath,
    -- don't short-circuit - the spell is NOT ready.
    if cd.isOnGCD == true then
        -- Is a REAL cooldown ticking under the GCD? The ignore-GCD duration object
        -- answers this as engine truth - immune to the CDR / proc-reset / refund drift
        -- the local timer suffers. Fall back to local tracking only if that API is absent.
        local realCD
        if C_Spell and C_Spell.GetSpellCooldownDuration then
            realCD = BlizzardAPI.IsSpellOnCooldown(spellID)
        else
            realCD = IsLocalCooldownActive(spellID)
        end
        if not realCD then
            return true, "isOnGCD (GCD only)"
        end
        -- Real CD ticking under the GCD - fall through (not ready).
    end

    -- isOnGCD == false → real cooldown running (definitive for flagged spells)
    if cd.isOnGCD == false then return false, "isOnGCD flag (real cooldown)" end

    -- Out of combat: duration/startTime are readable. Unsecret both together -
    -- the secret system is volatile enough that one field can read plain while
    -- the other is still marked.
    local duration = Unsecret(cd.duration)
    local startTime = duration and Unsecret(cd.startTime)
    if duration and startTime then
        return startTime == 0 or (startTime + duration) <= GetTime(), "cooldown timer (out of combat)"
    end

    -- In combat with secreted values and isOnGCD == nil:
    -- Spell is either off cooldown OR on CD but unflagged (major CDs like
    -- Divine Toll, Execution Sentence, Shadow Blades) - use fallback chain

    -- SpellCooldownInfo.isActive is NeverSecret (source-verified).
    -- At this point isOnGCD is nil and duration is secret (combat) - both the
    -- isOnGCD true and false cases already exited above, and Unsecret(duration)
    -- returned nil (OOC path already exited). We are definitively in combat.
    --
    -- isOnGCD == nil + isActive == true  → real unflagged CD running (Cloak of
    --   Shadows, Shadow Blades, Execution Sentence, etc. - long CDs Blizzard
    --   doesn't flag, so isOnGCD never transitions to false).
    -- isOnGCD == nil + isActive == false → no CD timer running; spell is ready.
    --
    -- isActive is ground truth from Blizzard's state machine; no further
    -- fallback chain needed - local tracking / charge tracking / usability
    -- checks would all be redundant here.
    return not cd.isActive, "isActive (in combat)"
end

--------------------------------------------------------------------------------
-- ACTION_USABLE_CHANGED CD Flip Detection (Phase 2)
--------------------------------------------------------------------------------
-- Reverse map: action slot → tracked spellID.
-- Populated lazily on first CheckUsabilityFlips call, invalidated alongside
-- slot caches (ACTIONBAR_SLOT_CHANGED, form change, etc.).
local slotToTrackedSpell = {}
local reverseMapValid = false

local function BuildReverseSlotMap()
    wipe(slotToTrackedSpell)
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    if not ABS or not ABS.GetSlotForSpell then
        reverseMapValid = true
        return
    end
    for spellID in pairs(trackedSpells) do
        local slot = ABS.GetSlotForSpell(spellID)
        if slot then
            slotToTrackedSpell[slot] = spellID
        end
    end
    reverseMapValid = true
end

--- Invalidate the reverse slot map (call on ACTIONBAR_SLOT_CHANGED, form change).
function BlizzardAPI.InvalidateReverseSlotMap()
    reverseMapValid = false
end

--- Seed a local cooldown entry for a spell if it's currently on CD (OOC only).
--- Call after RegisterSpellForTracking to catch pre-existing CDs at login/spec-change.
--- Without this, spells already on CD have no UNIT_SPELLCAST_SUCCEEDED event to
--- start local tracking, so IsSpellReady fails-open for unflagged spells.
function BlizzardAPI.SeedLocalCooldownIfActive(spellID)
    if not spellID or spellID == 0 then return end
    if BlizzardAPI.AreCooldownsSecret() or not C_Spell_GetSpellCooldown then return end
    -- Skip if already tracked
    if localCooldowns[spellID] then return end
    SeedCooldownFromAPI(spellID, GetTime())
end

--- Detect CD completion via ACTION_USABLE_CHANGED slot transitions.
--- When a slot becomes usable (or only resource-blocked), and the mapped spell
--- Detect CD completion via ACTION_USABLE_CHANGED slot transitions.
--- NOTE: IsUsableAction returns true even when a spell is on cooldown, so a
--- usable=true transition does NOT mean the real CD expired - it fires on energy
--- ticks, target changes, and other unrelated transitions. Any CD clearing here
--- produces false positives that wipe still-active local CDs.
--- The correct CD expiry signals are:
---   - Local timer (endTime): expires naturally; reliable for all categories.
---   - SPELL_UPDATE_COOLDOWN + isOnGCD==true: "rotation" category early-clear.
---   - ResyncLocalCooldowns (PLAYER_REGEN_ENABLED): API resync at combat exit.
--- Charge recovery is still advanced here (usable=true is a valid hint that
--- at least one charge is available, consistent with the fail-open charge design).
--- @param changes table Array of {slot=luaIndex, usable=bool, noMana=bool}
function BlizzardAPI.CheckUsabilityFlips(changes)
    if not reverseMapValid then BuildReverseSlotMap() end

    for _, change in ipairs(changes) do
        if change.usable or change.noMana then
            local spellID = slotToTrackedSpell[change.slot]
            if spellID then
                -- DO NOT clear flat localCooldowns here: IsUsableAction returns
                -- true even on cooldown, so usable=true is not a CD-expired signal.

                -- Advance charge recovery if charge spell at 0 charges.
                -- usable=true is a valid hint that a charge has recharged.
                local chargeData = localCharges[spellID]
                if chargeData and chargeData.current <= 0 then
                    ProcessChargeRecovery(chargeData)
                    if chargeData.current <= 0 then
                        chargeData.current = 1
                    end
                end
            end
        end
    end
end


