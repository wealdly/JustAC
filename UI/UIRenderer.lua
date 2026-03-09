-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Renderer Module
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 17)
if not UIRenderer then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

if not BlizzardAPI or not ActionBarScanner or not SpellQueue or not UIAnimations or not UIFrameFactory then
    return
end

-- Localized label shown on the overlay when Assisted Combat is waiting for resources.
local WAIT_LABEL = ({
    enUS = "WAIT", enGB = "WAIT",
    deDE = "WART",
    frFR = "ATT.",
    esES = "ESPE", esMX = "ESPE",
    ptBR = "AGRD",
    ruRU = "ЖДЁМ",
    koKR = "대기",
    zhCN = "等待", zhTW = "等待",
    itIT = "ASPT",
})[GetLocale()] or "WAIT"

-- Hot path cache
local GetTime = GetTime
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor

-- Position stabilization: minimum display time before a spell at positions 2+
-- can be replaced. Prevents visual flicker from rapid proc/CD re-categorization
-- in SpellQueue. Position 1 always passes through Blizzard's suggestion.
local POSITION_HOLD_TIME = 0.15  -- 150ms

-- Glow hysteresis: require desired glow state to be stable for this duration
-- before switching animations. Prevents jarring animation restarts when proc
-- state toggles transiently (e.g. during GCD processing).
local GLOW_HOLD_TIME = 0.10  -- 100ms

-- Cast bar lingers after interrupt lands; suppress to avoid re-suggesting.
local INTERRUPT_DEBOUNCE = 1.0
local lastInterruptUsedTime = 0
local lastInterruptShownID  = nil
-- 2s covers state-registration lag; short enough for back-to-back CCs to still work.
local CC_APPLIED_SUPPRESS = 2.0
local lastCCAppliedTime   = 0

-- Interrupt alert FileDataIDs (sourced from SilverDragon).
-- Shared across renderers; debounce prevents double-fire in "both" display mode.
local INTERRUPT_ALERT_SOUNDS = {
    shing        = 566240,  -- Shing!        — sharp metallic bling
    wham         = 566946,  -- Wham!         — heavy thud, impossible to miss
    simonChime   = 566076,  -- Simon Chime   — classic alert chime
    shortCircuit = 568975,  -- Short Circuit — crisp electric snap
    pvpFlag      = 569200,  -- PvP Flag      — PVP flag taken
    pvpFlagHorde = 568165,  -- PvP Flag (H)  — Horde flag taken
    pvpAlliance  = 568320,  -- PvP Alliance  — Alliance warning fanfare
    pvpHorde     = 569112,  -- PvP Horde     — Horde warning fanfare
    thunderCrack = 566202,  -- Thunder Crack — deep outdoor crack
    warDrums     = 567275,  -- War Drums     — heavy tribal drums
    dwarfHorn    = 566064,  -- Dwarf Horn    — short brass horn
    scourgeHorn  = 567386,  -- Scourge Horn  — eerie undead horn
    explosion    = 566982,  -- Explosion     — large boom
    cheer        = 567283,  -- Cheer         — crowd cheer
    felPortal    = 569215,  -- Fel Portal    — demonic portal open
    felNova      = 568582,  -- Fel Nova      — arcane/fel pulse
    humm         = 569518,  -- Humm          — soft ambient tone
    cartoonFX    = 566543,  -- Cartoon FX    — light cartoon pop
    rubberDucky  = 566121,  -- Rubber Ducky  — squeaky duck
    pygmyDrums   = 566508,  -- Pygmy Drums   — quick drum rattle
    grimrailHorn = 1023633, -- Grimrail Horn — train horn blast
    squireHorn   = 598079,  -- Squire Horn   — mounted herald horn
    gruntlingHorn= 598196,  -- Gruntling Horn— goblin herald horn
}
local PlaySoundFile = PlaySoundFile
local lastInterruptSoundTime = 0
local INTERRUPT_SOUND_DEBOUNCE = 0.5

-- Shared between both renderers so interrupt debounce is unified.
local lastInterruptEvalTime = -1
local cachedIntResult = { shouldShow = false, spellID = nil, castBar = nil, interruptMode = nil }

local C_NamePlate = C_NamePlate
local UnitIsCrowdControlled = UnitIsCrowdControlled
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell

-- ─────────────────────────────────────────────────────────────────────────────
-- Cast bar discovery: Blizzard → Plater → ElvUI.
-- Source-verified paths (2026-03-01):
--   Blizzard : nameplate.UnitFrame.castBar  (capital U)
--   Plater   : nameplate.unitFrame.castBar  (lowercase u)
--   ElvUI    : nameplate child → .Castbar   (capital C, oUF element)
-- ─────────────────────────────────────────────────────────────────────────────
local function FindVisibleCastBar(nameplate)
    if not nameplate then return nil, nil end

    local uf = nameplate.UnitFrame
    if uf then
        local bar = uf.castBar
        if bar and bar.IsVisible and bar:IsVisible() then
            return bar, "blizzard"
        end
    end

    -- Plater: lowercase .unitFrame (Details! Framework)
    local puf = nameplate.unitFrame
    if puf and puf ~= uf then
        local bar = puf.castBar
        if bar and bar.IsShown and bar:IsShown() then
            return bar, "plater"
        end
    end

    -- ElvUI: oUF child .Castbar is not a named field, must enumerate children.
    if nameplate.GetNumChildren then
        local numKids = nameplate:GetNumChildren()
        if numKids > 0 then
            -- Avoid re-evaluating the GetChildren() vararg per iteration.
            local children = { nameplate:GetChildren() }
            for i = 1, numKids do
                local child = children[i]
                if child then
                    local cb = child.Castbar
                    if cb and cb.IsShown and cb:IsShown() then
                        return cb, "elvui"
                    end
                end
            end
        end
    end

    return nil, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Returns (isCasting, isInterruptible, castBar).
-- Cascades: event tracker → cast bar frame fields → API fallback → fail-open.
-- Only one pcall remains (notInterruptible may be a secret boolean in 12.0).
-- ─────────────────────────────────────────────────────────────────────────────
local function IsTargetCastInterruptible(nameplate)
    local evtActive, evtInterruptible, evtKnown = BlizzardAPI.GetTargetCastInterruptState()
    local bar, barSource = FindVisibleCastBar(nameplate)

    -- No bar: confirm a cast via API (unless event tracker already says "no cast").
    if not bar then
        local spell
        if evtActive or not evtKnown then
            spell = UnitCastingInfo("target")
            -- Spell name is secret in 12.0 combat; a secret value IS non-nil → cast exists.
            if not BlizzardAPI.IsSecretValue(spell) and not spell then
                spell = UnitChannelInfo("target")
            end
        end
        if not BlizzardAPI.IsSecretValue(spell) and not spell then
            return false, false, nil
        end
        barSource = "api"
    end

    -- Event tracker is definitive (real boolean, never secret).
    if evtKnown then
        return true, evtInterruptible, bar
    end

    if bar then
        -- Every cast bar field/widget may propagate secret booleans in 12.0 combat.
        -- Blizzard's CastingBarMixin does BorderShield:SetShown(self.notInterruptible),
        -- so IsShown()/GetAlpha() on sub-widgets inherit the secrecy and crash on
        -- boolean tests. Wrap each check in pcall; crash = skip to next check.

        -- Direct field: notInterruptible (secret boolean in combat)
        local niOk, ni = pcall(function() return bar.notInterruptible and true or false end)
        if niOk and ni then return true, false, bar end

        -- Icon hidden when not interruptible (IsShown inherits secret from SetShown)
        local iconOk, iconHidden = pcall(function()
            return bar.Icon and bar.HideIconWhenNotInterruptible and not bar.Icon:IsShown()
        end)
        if iconOk and iconHidden then return true, false, bar end

        -- BorderShield visible = not interruptible (IsShown/GetAlpha inherit secret)
        local shieldOk, shieldShown = pcall(function()
            return bar.BorderShield and bar.BorderShield:IsShown() and (bar.BorderShield:GetAlpha() or 0) > 0.5
        end)
        if shieldOk and shieldShown then return true, false, bar end

        -- ElvUI uses .Shield instead of .BorderShield
        if barSource == "elvui" then
            local elvOk, elvShown = pcall(function()
                return bar.Shield and bar.Shield:IsShown() and (bar.Shield:GetAlpha() or 0) > 0.5
            end)
            if elvOk and elvShown then return true, false, bar end
        end
    end

    -- API fallback when no cast bar frame is available (nameplates off + addon target frame).
    if barSource == "api" then
        local castName, notInt
        castName, _, _, _, _, _, _, notInt = UnitCastingInfo("target")
        -- Cast name is secret in 12.0 combat; secret non-nil = cast exists.
        if not BlizzardAPI.IsSecretValue(castName) and not castName then
            castName, _, _, _, _, _, notInt = UnitChannelInfo("target")
        end
        -- notInterruptible is a secret boolean in 12.0 — check before comparing.
        if BlizzardAPI.IsSecretValue(notInt) then
            return true, true, nil  -- secret → fail-open
        end
        if notInt ~= nil then
            return true, not notInt, nil
        end
    end

    -- Fail-open: no negative signal → assume interruptible.
    return true, true, bar
end

-- Gap-closers have their own red crawl path; excluded here.
local function IsSpellProcced(spellID)
    return BlizzardAPI.IsSpellProcced(spellID)
end

-- Normalize a raw WoW hotkey string to the MODIFIER-KEY format used by CreateKeyPressDetector.
-- Multi-modifier combos are checked first to prevent partial prefix matches.
-- Mouse abbreviations are reversed so matching uses WoW's raw binding names (BUTTON1-N).
local function NormalizeHotkey(hotkey)
    local n = hotkey:upper()
    -- Full-word modifier prefixes MUST come first so "SHIFT-2" isn't misread as
    -- the single-letter "S" prefix pattern below (which would produce "SHIFT-HIFT-2").
    -- Accept both "-" and "+" separators so user-typed "Shift+2" and "Shift-2" both work.
    n = n:gsub("^CTRL%-ALT[%-%+](.+)",   "CTRL-ALT-%1")
    n = n:gsub("^CTRL%-SHIFT[%-%+](.+)", "CTRL-SHIFT-%1")
    n = n:gsub("^SHIFT%-ALT[%-%+](.+)",  "SHIFT-ALT-%1")
    n = n:gsub("^SHIFT[%-%+](.+)",       "SHIFT-%1")
    n = n:gsub("^CTRL[%-%+](.+)",        "CTRL-%1")
    n = n:gsub("^ALT[%-%+](.+)",         "ALT-%1")
    -- Abbreviated prefixes from AbbreviateKeybind: S-X, C-X, A-X, CA-X, CS-X, SA-X.
    -- Require the hyphen (%-) not optional: "^S%-?" would match the "S" in "SHIFT-..."
    -- after the full-word patterns above have already run, corrupting any remaining input.
    n = n:gsub("^CA%-(.+)",  "CTRL-ALT-%1")
    n = n:gsub("^CS%-(.+)",  "CTRL-SHIFT-%1")
    n = n:gsub("^SA%-(.+)",  "SHIFT-ALT-%1")
    n = n:gsub("^S%-(.+)",   "SHIFT-%1")
    n = n:gsub("^C%-(.+)",   "CTRL-%1")
    n = n:gsub("^A%-(.+)",   "ALT-%1")
    n = n:gsub("^%+(.+)",    "MOD-%1")
    n = n:gsub("MWU$", "MOUSEWHEELUP")
    n = n:gsub("MWD$", "MOUSEWHEELDOWN")
    n = n:gsub("M(%d+)$", "BUTTON%1")
    return n
end

-- 12.0+ DurationObject pipeline: Blizzard's opaque cooldown display bypasses secret values.
-- Detects API availability once at load time; falls back to legacy SetCooldown on pre-12.0.
local HAS_DURATION_OBJECT_API = C_Spell and C_Spell.GetSpellCooldownDuration
    and type(C_Spell.GetSpellCooldownDuration) == "function"

-- Returns true when a LuaDurationObject represents a finished/inactive cooldown.
-- Only callable out of combat (HasSecretValues() must be false first).
-- Handles two cases:
--   1. Zero-span cooldown (never started or 0s duration): IsZero() == true
--   2. Expired cooldown (e.g. charge recharge completed): remaining <= 0
local function IsDurationFinished(dur)
    if dur.IsZero and dur:IsZero() then return true end
    if dur.GetRemainingDuration then
        local ok, remaining = pcall(dur.GetRemainingDuration, dur)
        if ok and remaining and type(remaining) == "number" and remaining <= 0 then
            return true
        end
    end
    return false
end

-- Cooldown widgets accept secret values internally — never compare or do arithmetic on them.
local function UpdateButtonCooldowns(button)
    if not button then return end

    local isItem = button.isItem
    local id = isItem and button.itemID or button.spellID

    if not id then
        if button.cooldown then button.cooldown:Clear() end
        if button.chargeCooldown then button.chargeCooldown:Clear() end
        if button.chargeText then button.chargeText:Hide() end
        button._cooldownShown = false
        button._chargeCooldownShown = false
        button._lastCooldownID = nil
        return
    end

    -- When the spell on this button changes, clear stale cooldown state before
    -- applying the new spell's cooldown.  Prevents sweep animations from a
    -- previous spell bleeding through during queue re-ordering (e.g. combat exit).
    if id ~= button._lastCooldownID then
        if button.cooldown then button.cooldown:Clear() end
        if button.chargeCooldown then button.chargeCooldown:Clear(); button.chargeCooldown:Hide() end
        button._cooldownShown = false
        button._chargeCooldownShown = false
        button._lastCooldownID = id
    end

    local cooldownInfo, chargeInfo
    local usedDurationObject = false  -- Track whether opaque pipeline was used for main CD
    local usedChargeDurationObject = false  -- Track for charge CD

    if isItem then
        local start, duration = GetItemCooldown(id)
        cooldownInfo = { startTime = start or 0, duration = duration or 0, isEnabled = 1, modRate = 1 }
    else
        -- Cached cooldownID avoids redundant override lookup.
        local cooldownID = BlizzardAPI.GetDisplaySpellID(id)

        -- 12.0+ opaque pipeline: SetCooldownFromDurationObject bypasses secret values.
        -- LuaDurationObject is fully opaque — we cannot read or branch on its values,
        -- but the Cooldown widget renders the sweep animation correctly.
        if HAS_DURATION_OBJECT_API and button.cooldown and button.cooldown.SetCooldownFromDurationObject then
            local ok, dur = pcall(C_Spell.GetSpellCooldownDuration, cooldownID)
            if ok and dur then
                -- HasSecretValues() is NeverSecret — safe to branch on in combat.
                -- When no secrets: IsDurationFinished() checks both zero-span and expired CDs.
                -- Clear() prevents the sweep from sticking at 12 o'clock.
                -- When secrets present (combat): skip the check, pass through to
                -- SetCooldownFromDurationObject which handles opaque durations correctly.
                local hasSecrets = dur.HasSecretValues and dur:HasSecretValues()
                if not hasSecrets and IsDurationFinished(dur) then
                    if button._cooldownShown then
                        button.cooldown:Clear()
                        button._cooldownShown = false
                    end
                else
                    if not button._cooldownShown then
                        button.cooldown:SetDrawSwipe(true)
                        button.cooldown:Show()
                        button._cooldownShown = true
                    end
                    button.cooldown:SetCooldownFromDurationObject(dur)
                end
                usedDurationObject = true
            end
        end

        -- Legacy cooldown info (still needed for the non-DurationObject fallback
        -- and also for charge spell detection below which needs chargeInfo).
        if not usedDurationObject or C_Spell.GetSpellCharges then
            if C_Spell.GetSpellCooldown and not usedDurationObject then
                local ok, result = pcall(C_Spell.GetSpellCooldown, cooldownID)
                if ok then cooldownInfo = result end
            end
            if C_Spell.GetSpellCharges then
                local ok, result = pcall(C_Spell.GetSpellCharges, cooldownID)
                if ok then chargeInfo = result end
            end
        end
    end

    -- Main cooldown: only use legacy path if DurationObject wasn't applied above.
    -- Guard: SetCooldown(startTime, duration) where duration==0 OR the cooldown has
    -- already expired (startTime+duration <= now) both park the sweep at 12 o'clock.
    -- Secret-value guard: if either field is opaque in 12.0 combat, pass through to
    -- SetCooldown — the widget handles secret values internally; we cannot read them.
    if not usedDurationObject then
        if button.cooldown and cooldownInfo then
            local startTime = cooldownInfo.startTime or 0
            local duration = cooldownInfo.duration or 0
            local modRate = cooldownInfo.modRate or 1
            local durationIsSecret = BlizzardAPI.IsSecretValue(duration)
            local startTimeIsSecret = BlizzardAPI.IsSecretValue(startTime)
            -- Cooldown is genuinely active when: values are secret (can't read), OR
            -- duration>0 AND the deadline hasn't passed yet.
            local cooldownActive = durationIsSecret or startTimeIsSecret
                or (duration > 0 and (startTime <= 0 or (startTime + duration) > GetTime()))
            if cooldownActive then
                if not button._cooldownShown then
                    button.cooldown:SetDrawSwipe(true)
                    button.cooldown:Show()
                    button._cooldownShown = true
                end
                button.cooldown:SetCooldown(startTime, duration, modRate)
            else
                if button._cooldownShown then
                    button.cooldown:Clear()
                    button._cooldownShown = false
                end
            end
        elseif button.cooldown then
            if button._cooldownShown then
                button.cooldown:Clear()
                button._cooldownShown = false
            end
        end
    end

    -- SetCooldown / SetCooldownFromDurationObject may re-show countdown text;
    -- hide again if user disabled it.
    if button.cooldown and button._cooldownShown and button.cooldownText then
        local cdProfile = BlizzardAPI and BlizzardAPI.GetProfile()
        local cdOverlays = cdProfile and cdProfile.textOverlays
        if cdOverlays and cdOverlays.cooldown and cdOverlays.cooldown.show == false then
            button.cooldownText:Hide()
        end
    end

    -- All GetSpellCharges fields are SECRET in combat; use cached maxCharges to decide display.
    -- When chargeInfo is nil in combat (GetSpellCharges can return nil for charge spells
    -- in some combat states), fall back to cached maxCharges to keep the charge UI stable.
    local effectiveMaxCharges = 0
    if chargeInfo then
        local maxCharges = chargeInfo.maxCharges
        if maxCharges and not BlizzardAPI.IsSecretValue(maxCharges) then
            effectiveMaxCharges = maxCharges
        else
            effectiveMaxCharges = BlizzardAPI.GetCachedMaxCharges(id) or 0
        end
    else
        -- chargeInfo is nil: check cached maxCharges to determine if this is a charge spell.
        -- If cached says multi-charge, preserve the charge display even without fresh data.
        effectiveMaxCharges = BlizzardAPI.GetCachedMaxCharges(id) or 0
    end
    local isMultiCharge = effectiveMaxCharges > 1

    if button.chargeCooldown then
        if isMultiCharge and chargeInfo then
            local chargeStart    = chargeInfo.cooldownStartTime or 0
            local chargeDuration = chargeInfo.cooldownDuration or 0
            -- Guard: SetCooldown with duration==0 OR an already-expired recharge parks
            -- the sweep at 12 o'clock. Secret-value guard: pass through if opaque.
            local chargeDurationIsSecret = BlizzardAPI.IsSecretValue(chargeDuration)
            local chargeStartIsSecret    = BlizzardAPI.IsSecretValue(chargeStart)
            local chargeCDActive = chargeDurationIsSecret or chargeStartIsSecret
                or (chargeDuration > 0 and (chargeStart <= 0 or (chargeStart + chargeDuration) > GetTime()))
            if chargeCDActive then
                if not button._chargeCooldownShown then
                    button.chargeCooldown:Show()
                    button._chargeCooldownShown = true
                end
                -- 12.0+ opaque pipeline for charge cooldown.
                if HAS_DURATION_OBJECT_API and button.chargeCooldown.SetCooldownFromDurationObject
                    and C_ActionBar and C_ActionBar.GetActionChargeDuration then
                    -- GetActionChargeDuration requires an action bar slot; look up from spellID.
                    local slot = ActionBarScanner and ActionBarScanner.GetSlotForSpell
                        and ActionBarScanner.GetSlotForSpell(BlizzardAPI.GetDisplaySpellID(id))
                    if slot then
                        local ok, dur = pcall(C_ActionBar.GetActionChargeDuration, slot)
                        if ok and dur then
                            local hasSecrets = dur.HasSecretValues and dur:HasSecretValues()
                            if not hasSecrets and IsDurationFinished(dur) then
                                if button._chargeCooldownShown then
                                    button.chargeCooldown:Clear()
                                    button.chargeCooldown:Hide()
                                    button._chargeCooldownShown = false
                                end
                            else
                                button.chargeCooldown:SetCooldownFromDurationObject(dur)
                            end
                            usedChargeDurationObject = true
                        end
                    end
                end
                if not usedChargeDurationObject then
                    button.chargeCooldown:SetCooldown(
                        chargeStart,
                        chargeDuration,
                        chargeInfo.chargeModRate or 1
                    )
                end
            else
                if button._chargeCooldownShown then
                    button.chargeCooldown:Clear()
                    button.chargeCooldown:Hide()
                    button._chargeCooldownShown = false
                end
            end
        elseif isMultiCharge and not chargeInfo then
            -- Known charge spell but no chargeInfo (secreted nil or API error).
            -- Keep charge cooldown visible if already shown; don't flicker it off.
            -- The main cooldown swipe still runs via cooldownInfo above.
        else
            if button._chargeCooldownShown then
                button.chargeCooldown:Clear()
                button.chargeCooldown:Hide()
                button._chargeCooldownShown = false
            end
        end
    end

    -- currentCharges may be secret; SetText() displays secret values correctly.
    if button.chargeText then
        if isMultiCharge then
            local chProfile = BlizzardAPI and BlizzardAPI.GetProfile()
            local chOverlays = chProfile and chProfile.textOverlays
            local showChargesCfg = not chOverlays or not chOverlays.charges or chOverlays.charges.show ~= false
            if showChargesCfg then
                if chargeInfo and chargeInfo.currentCharges then
                    button.chargeText:SetText(chargeInfo.currentCharges)
                    button.chargeText:Show()
                elseif not button.chargeText:IsShown() then
                    -- No chargeInfo but known multi-charge: keep current text if visible,
                    -- otherwise show nothing (avoid flicker).
                end
            else
                button.chargeText:Hide()
            end
        else
            button.chargeText:Hide()
        end
    end
end

local DEFAULT_QUEUE_DESATURATION = 0
local QUEUE_ICON_BRIGHTNESS = 1.0
local QUEUE_ICON_OPACITY = 1.0
local CLICK_DARKEN_ALPHA = 0.4
local CLICK_INSET_PIXELS = 2
local HOTKEY_FONT_SCALE = UIFrameFactory.HOTKEY_FONT_SCALE
local HOTKEY_MIN_FONT_SIZE = UIFrameFactory.HOTKEY_MIN_FONT_SIZE
local HOTKEY_OFFSET_FIRST = UIFrameFactory.HOTKEY_OFFSET_FIRST
local HOTKEY_OFFSET_QUEUE = UIFrameFactory.HOTKEY_OFFSET_QUEUE

local function GetQueueDesaturation()
    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    return profile and profile.queueIconDesaturation or DEFAULT_QUEUE_DESATURATION
end

local isInCombat = false
local isChanneling = false
local channelSpellID = nil  -- Override spellID from UnitChannelInfo (for fill animation matching)
local isCasting = false
local castSpellID = nil  -- Override spellID from UnitCastingInfo (for cast-fill matching)
local CHANNEL_EARLY_UNGREY = 0.1  -- Stop greying out 100ms before channel/cast ends
local hotkeysDirty = true
local lastPanelLocked = nil
local lastFrameState = {
    shouldShow = false,
    spellCount = 0,
    lastUpdate = 0,
}

-- Swipe animates smoothly once set; no need to update every frame.
local lastCooldownUpdate = 0
local COOLDOWN_UPDATE_INTERVAL = 0.08

-- Stale atlas markup can appear if cached hotkeys survive a binding change.
function UIRenderer.InvalidateHotkeyCache()
    hotkeysDirty = true
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if addon and addon.spellIcons then
        for i = 1, #addon.spellIcons do
            local icon = addon.spellIcons[i]
            if icon then
                icon.cachedHotkey = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Defensive Visual State (shared by ShowDefensiveIcon + per-frame update)
--------------------------------------------------------------------------------
-- Evaluates channeling + usability and applies the correct texture state.
-- Called per-frame from RenderSpellQueue (same cadence as offensive queue icons)
-- so defensives respond instantly to channeling transitions and resource changes.
--
-- States: 1=channeling (full desat), 2=no resources (blue tint),
--         4=on cooldown (grey desat), 3=normal (full color)
--
-- @param forceCheck  Force usability re-check (e.g. spell/item changed)
function UIRenderer.UpdateDefensiveVisualState(defensiveIcon, forceCheck)
    if not defensiveIcon or not defensiveIcon.iconTexture then return end

    local id = defensiveIcon.currentID
    if not id then return end

    -- Check if THIS defensive icon is the channeled/casted spell
    local isDefActiveSpell = false
    if not defensiveIcon.isItem and defensiveIcon.currentID then
        local defID = defensiveIcon.currentID
        if isChanneling and channelSpellID then
            if defID == channelSpellID then
                isDefActiveSpell = true
            elseif C_Spell_GetOverrideSpell then
                local overrideID = C_Spell_GetOverrideSpell(defID)
                if overrideID and overrideID == channelSpellID then isDefActiveSpell = true end
            end
        end
        if not isDefActiveSpell and isCasting and castSpellID then
            if defID == castSpellID then
                isDefActiveSpell = true
            elseif C_Spell_GetOverrideSpell then
                local overrideID = C_Spell_GetOverrideSpell(defID)
                if overrideID and overrideID == castSpellID then isDefActiveSpell = true end
            end
        end
    end

    -- Channeling/casting takes highest priority (unless THIS icon is the active spell)
    local isGreyingOut = (isChanneling or isCasting) and not isDefActiveSpell
    local defVisualState = isGreyingOut and 1 or 3
    if isDefActiveSpell then defVisualState = 5 end  -- channeling/casting THIS spell

    -- Usability check (throttled to ~80ms unless forced)
    local now = GetTime()
    if forceCheck or (now - (defensiveIcon.lastDefUsableCheck or 0)) >= COOLDOWN_UPDATE_INTERVAL then
        defensiveIcon.lastDefUsableCheck = now
        if defensiveIcon.isItem then
            local itemUsable = true
            local itemNoResource = false
            for slot = 1, 180 do
                local actionType, actionID = GetActionInfo(slot)
                if actionType == "item" and actionID == id then
                    local slotUsable, slotNoMana = C_ActionBar.IsUsableAction(slot)
                    if not BlizzardAPI.IsSecretValue(slotUsable) and not BlizzardAPI.IsSecretValue(slotNoMana) then
                        itemUsable = slotUsable or false
                        itemNoResource = slotNoMana or false
                    end
                    break
                end
            end
            defensiveIcon.cachedDefUsable = itemUsable
            defensiveIcon.cachedDefNoResource = itemNoResource
        else
            defensiveIcon.cachedDefUsable, defensiveIcon.cachedDefNoResource = BlizzardAPI.IsSpellUsable(id)
        end
    end

    -- Apply usability state (only when not channeling)
    if defVisualState ~= 1 and not defensiveIcon.cachedDefUsable then
        if defensiveIcon.cachedDefNoResource then
            defVisualState = 2  -- no resources → blue tint
        else
            defVisualState = 4  -- on cooldown → desaturated
        end
    end

    -- Force-apply every frame during channeling/casting so all icons
    -- grey/ungrey on the exact same frame (no per-icon desync).
    if defensiveIcon.lastDefVisualState ~= defVisualState
       or isChanneling or isCasting then
        if defVisualState == 5 then
            -- Channeling THIS spell: full color
            defensiveIcon.iconTexture:SetDesaturation(0)
            defensiveIcon.iconTexture:SetVertexColor(1, 1, 1)
        elseif defVisualState == 1 then
            defensiveIcon.iconTexture:SetDesaturation(1.0)
            defensiveIcon.iconTexture:SetVertexColor(1, 1, 1)
        elseif defVisualState == 2 then
            defensiveIcon.iconTexture:SetDesaturation(0)
            defensiveIcon.iconTexture:SetVertexColor(0.3, 0.3, 0.8)
        elseif defVisualState == 4 then
            defensiveIcon.iconTexture:SetDesaturation(0.8)
            defensiveIcon.iconTexture:SetVertexColor(0.6, 0.6, 0.6)
        else
            defensiveIcon.iconTexture:SetDesaturation(0)
            defensiveIcon.iconTexture:SetVertexColor(1, 1, 1)
        end
        defensiveIcon.lastDefVisualState = defVisualState
    end

    -- Channel fill animation on the channeled defensive icon (not for hardcasts)
    if isDefActiveSpell and isChanneling then
        if not defensiveIcon._hasChannelFill and UIAnimations then
            UIAnimations.StartChannelFill(defensiveIcon)
        end
    elseif defensiveIcon._hasChannelFill and UIAnimations then
        UIAnimations.StopChannelFill(defensiveIcon)
    end

    -- ── Per-frame proc glow re-evaluation ───────────────────────────────────
    -- ShowDefensiveIcon does a one-shot glow setup but proc state can change
    -- mid-combat while the icon is still displayed. Re-evaluate every frame
    -- so glow appears/disappears within one render pass (IsSpellProcced is a
    -- cache lookup, not an API call — effectively free).
    -- Glow hysteresis: require desired state to be stable for GLOW_HOLD_TIME
    -- before switching animations, preventing flicker from transient proc toggles.
    if not defensiveIcon.isItem and UIAnimations then
        local isProc = IsSpellProcced(id)
        local glowMode = defensiveIcon.defGlowMode or "all"
        local wantProcGlow = isProc and (glowMode == "all" or glowMode == "procOnly")
        local hasProcGlow = defensiveIcon.ProcGlowFrame and defensiveIcon.ProcGlowFrame:IsShown()

        -- Apply hysteresis: don't toggle glow until desired state has been
        -- stable for GLOW_HOLD_TIME (prevents animation restart on transient
        -- proc state changes).
        local now = GetTime()
        local applyChange = false
        if wantProcGlow ~= hasProcGlow then
            if defensiveIcon.pendingDefGlow == wantProcGlow then
                if now - (defensiveIcon.pendingDefGlowTime or 0) >= GLOW_HOLD_TIME then
                    applyChange = true
                    defensiveIcon.pendingDefGlow = nil
                end
            else
                defensiveIcon.pendingDefGlow = wantProcGlow
                defensiveIcon.pendingDefGlowTime = now
            end
        else
            defensiveIcon.pendingDefGlow = nil
        end

        if applyChange then
            if wantProcGlow and not hasProcGlow then
                UIAnimations.StopDefensiveGlow(defensiveIcon)
                UIAnimations.ShowProcGlow(defensiveIcon)
            elseif not wantProcGlow and hasProcGlow then
                UIAnimations.HideProcGlow(defensiveIcon)
                -- Restore marching ants if this is position 1
                local showMarching = defensiveIcon.defShowGlow
                    and (glowMode == "all" or glowMode == "primaryOnly")
                if showMarching then
                    UIAnimations.StartDefensiveGlow(defensiveIcon, isInCombat)
                end
            end
        end
    end
end

-- glowModeOverride: overrides profile.defensives.glowMode (overlay has its own setting).
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon, showGlow, glowModeOverride, showHotkeysOverride, showFlashOverride)
    if not addon or not id or not defensiveIcon then return end
    
    local iconTexture, name
    local idChanged = (defensiveIcon.currentID ~= id) or (defensiveIcon.isItem ~= isItem)
    
    if isItem then
        local itemInfo = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
        if itemInfo then
            iconTexture = itemInfo.iconFileID
            name = itemInfo.itemName
        else
            name, _, _, _, _, _, _, _, _, iconTexture = GetItemInfo(id)
        end
        if not iconTexture then return end
    else
        local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(id)
        if not spellInfo then return end
        iconTexture = spellInfo.iconID
        name = spellInfo.name
    end
    
    defensiveIcon.currentID = id
    defensiveIcon.spellID = not isItem and id or nil
    defensiveIcon.itemID = isItem and id or nil
    defensiveIcon.isItem = isItem
    
    -- Store item's cast spell ID so flash animation can match (items cast via spellID).
    defensiveIcon.itemCastSpellID = nil
    if isItem then
        local _, spellID = GetItemSpell(id)
        defensiveIcon.itemCastSpellID = spellID
    end
    
    if idChanged then
        defensiveIcon.iconTexture:SetTexture(iconTexture)
        defensiveIcon.iconTexture:Show()
        defensiveIcon.iconTexture:SetDesaturation(0)
        defensiveIcon.iconTexture:SetVertexColor(1, 1, 1, 1)
        -- Reset usability visual state so new spell gets a fresh check
        defensiveIcon.cachedDefUsable = nil
        defensiveIcon.cachedDefNoResource = nil
        defensiveIcon.lastDefVisualState = nil
    end
    
    UpdateButtonCooldowns(defensiveIcon)

    -- Needed for both display AND key press flash matching.
    local showHotkeys, showFlash
    if showHotkeysOverride ~= nil then
        showHotkeys = showHotkeysOverride
    else
        local defOverlays = addon.db and addon.db.profile and addon.db.profile.textOverlays
        showHotkeys = not defOverlays or not defOverlays.hotkey or defOverlays.hotkey.show ~= false
    end
    if showFlashOverride ~= nil then
        showFlash = showFlashOverride
    else
        showFlash = addon.db and addon.db.profile and addon.db.profile.showFlash ~= false
    end
    local hotkey = ""
    if showHotkeys or showFlash then
        if isItem then
            for slot = 1, 180 do
                local actionType, actionID = GetActionInfo(slot)
                if actionType == "item" and actionID == id then
                    hotkey = ActionBarScanner and ActionBarScanner.SelectBindingKey and ActionBarScanner.SelectBindingKey("ACTIONBUTTON" .. slot) or ""
                    if hotkey == "" then
                        local barOffset = slot > 12 and math.floor((slot - 1) / 12) or 0
                        local buttonIndex = ((slot - 1) % 12) + 1
                        hotkey = ActionBarScanner and ActionBarScanner.SelectBindingKey and ActionBarScanner.SelectBindingKey("ACTIONBUTTON" .. buttonIndex) or ""
                    end
                    break
                end
            end
        else
            hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(id) or ""
        end
    end
    
    -- When showHotkeys is off, keep hotkey for flash matching but clear display text.
    local displayHotkey = showHotkeys and hotkey or ""
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= displayHotkey then
        defensiveIcon.hotkeyText:SetText(displayHotkey)
    end

    if hotkey ~= "" then
        local normalized = NormalizeHotkey(hotkey)
        if defensiveIcon.normalizedHotkey and defensiveIcon.normalizedHotkey ~= normalized then
            defensiveIcon.previousNormalizedHotkey = defensiveIcon.normalizedHotkey
            defensiveIcon.hotkeyChangeTime = GetTime()
        end
        defensiveIcon.normalizedHotkey = normalized
    else
        defensiveIcon.normalizedHotkey = nil
    end

    -- ── Usability visual state ──────────────────────────────────────────────
    -- Handled per-frame by UpdateDefensiveVisualState() in RenderSpellQueue for
    -- instant responsiveness (same cadence as offensive queue icons).
    -- ShowDefensiveIcon only does a one-shot update on icon setup/spell change.
    UIRenderer.UpdateDefensiveVisualState(defensiveIcon, idChanged)

    -- Module-level isInCombat avoids per-icon UnitAffectingCombat calls.

    local defGlowMode = glowModeOverride
        or (addon.db and addon.db.profile and addon.db.profile.defensives and addon.db.profile.defensives.glowMode)
        or "all"

    -- Store glow context so per-frame re-evaluation in UpdateDefensiveVisualState
    -- can toggle proc glow and restore marching ants without access to caller params.
    defensiveIcon.defGlowMode = defGlowMode
    defensiveIcon.defShowGlow = showGlow

    local isProc = not isItem and IsSpellProcced(id)
    local wantProcGlow = isProc and (defGlowMode == "all" or defGlowMode == "procOnly")

    if wantProcGlow then
        -- Proc glow replaces defensive crawl to avoid confusing layered animations.
        UIAnimations.StopDefensiveGlow(defensiveIcon)
        UIAnimations.ShowProcGlow(defensiveIcon)
    else
        UIAnimations.HideProcGlow(defensiveIcon)
        local showMarching = showGlow and (defGlowMode == "all" or defGlowMode == "primaryOnly")
        if showMarching then
            UIAnimations.StartDefensiveGlow(defensiveIcon, isInCombat)
        else
            UIAnimations.StopDefensiveGlow(defensiveIcon)
        end
    end
    
    if not defensiveIcon:IsShown() then
        if defensiveIcon.fadeOut and defensiveIcon.fadeOut:IsPlaying() then
            defensiveIcon.fadeOut:Stop()
        end
        defensiveIcon:Show()
        defensiveIcon:SetAlpha(0)
        if defensiveIcon.fadeIn then
            defensiveIcon.fadeIn:Play()
        else
            defensiveIcon:SetAlpha(1)
        end
    end
end

function UIRenderer.HideDefensiveIcon(defensiveIcon)
    if not defensiveIcon then return end
    
    if defensiveIcon:IsShown() or defensiveIcon.currentID then
        UIAnimations.StopDefensiveGlow(defensiveIcon)
        UIAnimations.HideProcGlow(defensiveIcon)
        defensiveIcon.spellID = nil
        defensiveIcon.itemID = nil
        defensiveIcon.itemCastSpellID = nil
        defensiveIcon.currentID = nil
        defensiveIcon.isItem = nil
        defensiveIcon.iconTexture:Hide()
        -- Ensure clean state on reuse.
        if defensiveIcon.cooldown then
            defensiveIcon.cooldown:Hide()
            defensiveIcon.cooldown:Clear()
        end
        if defensiveIcon.chargeCooldown then
            defensiveIcon.chargeCooldown:Hide()
            defensiveIcon.chargeCooldown:Clear()
        end
        -- Flags must be reset so UpdateButtonCooldowns re-shows widgets on reuse.
        defensiveIcon._cooldownShown = nil
        defensiveIcon._chargeCooldownShown = nil
        defensiveIcon.normalizedHotkey = nil
        defensiveIcon.previousNormalizedHotkey = nil
        defensiveIcon.hotkeyText:SetText("")
        -- Reset usability visual state
        defensiveIcon.cachedDefUsable = nil
        defensiveIcon.cachedDefNoResource = nil
        defensiveIcon.lastDefVisualState = nil
        defensiveIcon.lastDefUsableCheck = nil
        defensiveIcon.iconTexture:SetDesaturation(0)
        defensiveIcon.iconTexture:SetVertexColor(1, 1, 1, 1)
        if defensiveIcon.chargeText then
            defensiveIcon.chargeText:Hide()
        end
        
        if defensiveIcon.fadeOut and not defensiveIcon.fadeOut:IsPlaying() then
            if defensiveIcon.fadeIn and defensiveIcon.fadeIn:IsPlaying() then
                defensiveIcon.fadeIn:Stop()
            end
            defensiveIcon.fadeOut:Play()
        else
            defensiveIcon:Hide()
            defensiveIcon:SetAlpha(0)
        end
    end
end

function UIRenderer.ShowDefensiveIcons(addon, queue)
    if not addon or not addon.defensiveIcons then return end
    
    local icons = addon.defensiveIcons
    
    for i, icon in ipairs(icons) do
        local entry = queue[i]
        if entry and entry.spellID then
            local showGlow = (i == 1)
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, showGlow)
        else
            UIRenderer.HideDefensiveIcon(icon)
        end
    end
end

function UIRenderer.HideDefensiveIcons(addon)
    if not addon or not addon.defensiveIcons then return end
    
    for _, icon in ipairs(addon.defensiveIcons) do
        UIRenderer.HideDefensiveIcon(icon)
    end
end

-- Exported so UINameplateOverlay can reuse the same cleanup logic.
function UIRenderer.HideInterruptIcon(intIcon)
    intIcon.spellID = nil
    intIcon.iconTexture:Hide()
    if intIcon.cooldown then intIcon.cooldown:Clear(); intIcon.cooldown:Hide() end
    intIcon._cooldownShown       = false
    intIcon._chargeCooldownShown = false
    intIcon.normalizedHotkey     = nil
    intIcon.cachedHotkey         = nil
    intIcon.cachedOutOfRange     = nil
    intIcon.lastOutOfRange       = nil
    intIcon.lastVisualState      = nil
    intIcon.hotkeyText:SetText("")
    intIcon.iconTexture:SetDesaturation(0)
    if UIAnimations then
        if intIcon.hasInterruptGlow then UIAnimations.StopInterruptGlow(intIcon); intIcon.hasInterruptGlow = false end
        if intIcon.hasProcGlow      then UIAnimations.HideProcGlow(intIcon);      intIcon.hasProcGlow      = false end
    end
    if intIcon.castAura then
        intIcon.castAura:Hide()
    end
    intIcon:Hide()
end

function UIRenderer.PlayInterruptAlertSound(profile)
    local alertSound = profile.interruptAlertSound
    if not alertSound or alertSound == "none" then return end
    local soundID = INTERRUPT_ALERT_SOUNDS[alertSound]
    if not soundID then return end
    local now = GetTime()
    if (now - lastInterruptSoundTime) < INTERRUPT_SOUND_DEBOUNCE then return end
    lastInterruptSoundTime = now
    PlaySoundFile(soundID, "Master")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Glow state resolver — one clear intent instead of six cascading booleans
-- ─────────────────────────────────────────────────────────────────────────────
local GLOW_NONE       = 0   -- no glow
local GLOW_ASSISTED   = 1   -- blue/white crawl (position-1 primary suggestion)
local GLOW_PROC       = 2   -- gold burst (spell is procced / critically available)
local GLOW_GAP_CLOSER = 3   -- gold crawl (gap-closer, target out of melee range)

--- Priority: gap-closer > proc > assisted > none.
--- No WoW API calls — all inputs pre-computed by caller.
local function ResolveGlowState(position, spellID, showPrimaryGlow, showProcGlow, showGapCloserGlow)
    local isSyntheticProc = SpellQueue.IsSyntheticProc and SpellQueue.IsSyntheticProc(spellID)
    if isSyntheticProc and showGapCloserGlow then return GLOW_GAP_CLOSER end
    if BlizzardAPI.IsSpellProcced(spellID) and showProcGlow then return GLOW_PROC end
    if position == 1 and showPrimaryGlow then return GLOW_ASSISTED end
    return GLOW_NONE
end

function UIRenderer.RenderSpellQueue(addon, spellIDs)
    if not addon then return end
    local spellIconsRef = addon.spellIcons
    if not spellIconsRef then return end

    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    if not profile then return end

    local currentTime = GetTime()
    local hasSpells = spellIDs and #spellIDs > 0
    local spellCount = hasSpells and #spellIDs or 0
    
    -- Visibility conditions (OOC, healer, mounted, hostile target) are owned by
    -- SpellQueue; UIRenderer only checks display mode and whether spells exist.
    local displayMode = profile.displayMode or "queue"
    local shouldShowFrame = hasSpells
        and displayMode ~= "disabled"
        and displayMode ~= "overlay"
        and SpellQueue.ShouldShowQueue()

    local frameStateChanged = (lastFrameState.shouldShow ~= shouldShowFrame)
    local spellCountChanged = (lastFrameState.spellCount ~= spellCount)
    
    local maxIcons = profile.maxIcons
    local glowMode = profile.glowMode or "all"
    local showPrimaryGlow = (glowMode == "all" or glowMode == "primaryOnly")
    local showProcGlow = (glowMode == "all" or glowMode == "procOnly")
    local showGapCloserGlow = profile.gapClosers and profile.gapClosers.showGlow == true
    local queueDesaturation = GetQueueDesaturation()
    
    -- Grey out all icons while channeling (optional, gated by profile toggle).
    -- PlayerCastingBarFrame.channeling is a plain Lua boolean (set by CastingBarMixin),
    -- not a secret value. PlayerChannelBarFrame was removed in the Dragonflight UI rework.
    -- Early ungrey: stop greying out 100ms before channel ends so the player can
    -- see what ability to press next as the channel finishes.
    isChanneling = false
    channelSpellID = nil
    if profile.greyOutWhileChanneling ~= false and PlayerCastingBarFrame and PlayerCastingBarFrame.channeling == true then
        isChanneling = true
        -- Get the channeled spellID for fill animation matching.
        -- UnitChannelInfo returns the override spellID (e.g. 234153 for Drain Life base 689).
        local _, _, _, _, _, _, _, chID = UnitChannelInfo("player")
        channelSpellID = chID
        local remaining = PlayerCastingBarFrame.value
        if remaining and not BlizzardAPI.IsSecretValue(remaining) and remaining < CHANNEL_EARLY_UNGREY then
            isChanneling = false
        end
    end

    -- Grey out during hardcasts (optional, gated by profile toggle).
    isCasting = false
    castSpellID = nil
    if profile.greyOutWhileCasting ~= false and PlayerCastingBarFrame and PlayerCastingBarFrame.casting == true then
        isCasting = true
        local _, _, _, _, _, _, _, _, csID = UnitCastingInfo("player")
        castSpellID = csID
        local remaining = PlayerCastingBarFrame.value
        if remaining and not BlizzardAPI.IsSecretValue(remaining) and remaining < CHANNEL_EARLY_UNGREY then
            isCasting = false
        end
    end

    -- Cooldown throttle: shared by defensive and offensive icon updates below.
    local shouldUpdateCooldowns = (currentTime - lastCooldownUpdate) >= COOLDOWN_UPDATE_INTERVAL
    if shouldUpdateCooldowns then
        lastCooldownUpdate = currentTime
    end

    -- Update defensive icon visual states every frame (channeling + usability +
    -- proc glow), giving them the same responsiveness as offensive queue icons.
    -- Also refresh hotkeys when bindings change and poll cooldown widgets so CD
    -- resets (talent procs) are reflected promptly.
    if addon.defensiveIcons then
        for _, defIcon in ipairs(addon.defensiveIcons) do
            if defIcon:IsShown() then
                UIRenderer.UpdateDefensiveVisualState(defIcon)
                -- Hotkey refresh: re-lookup when bindings changed or cached value
                -- is empty (proc override may not have propagated on first frame).
                if hotkeysDirty or not defIcon.cachedHotkey or defIcon.cachedHotkey == "" then
                    local defID = defIcon.currentID
                    if defID then
                        local defHotkey
                        if defIcon.isItem then
                            defHotkey = ""
                            for slot = 1, 180 do
                                local actionType, actionID = GetActionInfo(slot)
                                if actionType == "item" and actionID == defID then
                                    defHotkey = ActionBarScanner and ActionBarScanner.SelectBindingKey and ActionBarScanner.SelectBindingKey("ACTIONBUTTON" .. slot) or ""
                                    if defHotkey == "" then
                                        local buttonIndex = ((slot - 1) % 12) + 1
                                        defHotkey = ActionBarScanner and ActionBarScanner.SelectBindingKey and ActionBarScanner.SelectBindingKey("ACTIONBUTTON" .. buttonIndex) or ""
                                    end
                                    break
                                end
                            end
                        else
                            defHotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(defID) or ""
                        end
                        if defIcon.cachedHotkey ~= defHotkey then
                            defIcon.cachedHotkey = defHotkey
                            local defOverlays = profile.textOverlays
                            local defShowHotkeys = not defOverlays or not defOverlays.hotkey or defOverlays.hotkey.show ~= false
                            local displayDefHotkey = defShowHotkeys and defHotkey or ""
                            defIcon.hotkeyText:SetText(displayDefHotkey)
                            if defHotkey ~= "" then
                                local normalized = NormalizeHotkey(defHotkey)
                                if defIcon.normalizedHotkey and defIcon.normalizedHotkey ~= normalized then
                                    defIcon.previousNormalizedHotkey = defIcon.normalizedHotkey
                                    defIcon.hotkeyChangeTime = currentTime
                                end
                                defIcon.normalizedHotkey = normalized
                            end
                        end
                    end
                end
                -- Cooldown widget refresh on the same 0.08s throttle as offensive icons
                -- so CD resets are reflected promptly (swipe self-animates but won't
                -- clear on a reset without an explicit UpdateButtonCooldowns call).
                if shouldUpdateCooldowns then
                    UpdateButtonCooldowns(defIcon)
                end
            end
        end
    end
    
    local IsSpellUsable = BlizzardAPI.IsSpellUsable
    local overlays = profile.textOverlays
    local showHotkeys = not overlays or not overlays.hotkey or overlays.hotkey.show ~= false
    local showFlash = profile.showFlash ~= false
    local GetSpellHotkey = (showHotkeys or showFlash) and ActionBarScanner and ActionBarScanner.GetSpellHotkey or nil
    local GetCachedSpellInfo = BlizzardAPI.GetCachedSpellInfo
    
    -- Glow frames at incorrect scale appear when hidden with active glows.
    if not shouldShowFrame then
        for i = 1, maxIcons do
            local icon = spellIconsRef[i]
            if icon then
                if icon.hasAssistedGlow   then UIAnimations.StopAssistedGlow(icon);  icon.hasAssistedGlow   = false end
                if icon.hasProcGlow       then UIAnimations.HideProcGlow(icon);       icon.hasProcGlow       = false end
                if icon.hasGapCloserGlow  then UIAnimations.StopGapCloserGlow(icon);  icon.hasGapCloserGlow  = false end
                if icon.hasDefensiveGlow  then UIAnimations.StopDefensiveGlow(icon);  icon.hasDefensiveGlow  = false end
            end
        end
    end

    -- ── Interrupt reminder (position 0) ─────────────────────────────────────
    -- Detect interruptible cast via the target nameplate's cast bar frame
    -- state.  Uses Icon:IsShown() for 12.0-safe interruptibility detection.
    -- interruptMode: "disabled" | "kickOnly" | "ccPrefer"
    -- ("importantOnly" reserved for future — all important-cast signals are SECRET in 12.0)
    local intIcon = addon.interruptIcon
    local resolvedInts = addon.resolvedInterrupts
    local interruptMode = profile.interruptMode or "ccPrefer"
    -- Retired mode in saved data → safe fallback.
    if interruptMode == "importantOnly" then interruptMode = "kickOnly" end
    if intIcon and resolvedInts and shouldShowFrame and interruptMode ~= "disabled" then
        -- Shared evaluation: both renderers see identical state and share one debounce timer.
        local intResult           = UIRenderer.EvaluateInterrupt(resolvedInts, interruptMode, currentTime)
        local shouldShowInterrupt = intResult.shouldShow
        local intSpellID          = intResult.spellID
        local castBar             = intResult.castBar

        -- De-dup: if the interrupt spell is already shown as offensive queue position 1, skip it
        if shouldShowInterrupt and intSpellID and spellIDs and spellIDs[1] == intSpellID then
            shouldShowInterrupt = false
        end

        if shouldShowInterrupt and intSpellID then
            local spellChanged = (intIcon.spellID ~= intSpellID)
            if spellChanged then
                intIcon.spellID = intSpellID
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(intSpellID)
                if info and info.iconID then
                    intIcon.iconTexture:SetTexture(info.iconID)
                    intIcon.iconTexture:Show()
                end
                intIcon._cooldownShown       = false
                intIcon._chargeCooldownShown = false
                intIcon.cachedHotkey         = nil
            end

            if spellChanged or shouldUpdateCooldowns then
                UpdateButtonCooldowns(intIcon)
            end

            local intOverlays = profile.textOverlays
            local intShowHotkeys = not intOverlays or not intOverlays.hotkey or intOverlays.hotkey.show ~= false
            if spellChanged or shouldUpdateCooldowns or not intIcon.cachedHotkey then
                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(intSpellID) or ""
                intIcon.cachedHotkey = hotkey
                local displayHotkey = intShowHotkeys and hotkey or ""
                if (intIcon.hotkeyText:GetText() or "") ~= displayHotkey then
                    intIcon.hotkeyText:SetText(displayHotkey)
                end
                if hotkey ~= "" then
                    intIcon.normalizedHotkey = NormalizeHotkey(hotkey)
                else
                    intIcon.normalizedHotkey = nil
                end
            end

            -- Red text = out of interrupt range (per-frame; IsSpellInRange is cheap).
            if intShowHotkeys and intIcon.cachedHotkey and intIcon.cachedHotkey ~= "" then
                do
                    local inRange = C_Spell_IsSpellInRange and C_Spell_IsSpellInRange(intSpellID)
                    if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
                        intIcon.cachedOutOfRange = (inRange == false)
                    else
                        intIcon.cachedOutOfRange = false
                    end
                end
                local isOutOfRange = intIcon.cachedOutOfRange or false
                if intIcon.lastOutOfRange ~= isOutOfRange then
                    if isOutOfRange then
                        intIcon.hotkeyText:SetTextColor(1, 0, 0, 1)
                    else
                        local hkc = intOverlays and intOverlays.hotkey and intOverlays.hotkey.color
                        intIcon.hotkeyText:SetTextColor((hkc and hkc.r) or 1, (hkc and hkc.g) or 1, (hkc and hkc.b) or 1, (hkc and hkc.a) or 1)
                    end
                    intIcon.lastOutOfRange = isOutOfRange
                end
            end

            -- No channeling grey-out for interrupts: they are urgent actions the
            -- player may want to cancel a channel to use.

            if not intIcon.hasInterruptGlow then
                UIAnimations.StartInterruptGlow(intIcon, isInCombat)
                intIcon.hasInterruptGlow = true
            end

            -- Cast bar textures can be secret in 12.0 — pass through unconditionally.
            if intIcon.castAura then
                local castIcon = castBar and castBar.Icon
                local castTexture = castIcon and castIcon.GetTexture and castIcon:GetTexture()
                -- API fallback: when third-party addons hide the Blizzard cast bar,
                -- retrieve the cast icon directly from UnitCastingInfo / UnitChannelInfo.
                if not castTexture then
                    local _, _, tex = UnitCastingInfo("target")
                    if not tex then _, _, tex = UnitChannelInfo("target") end
                    -- In 12.0 combat, texture may be secret — still pass through.
                    castTexture = tex
                end
                if castTexture then
                    intIcon.castAura.iconTexture:SetTexture(castTexture)
                    if not intIcon.castAura:IsShown() then intIcon.castAura:Show() end
                else
                    if intIcon.castAura:IsShown() then intIcon.castAura:Hide() end
                end
            end

            if not intIcon:IsShown() then
                UIRenderer.PlayInterruptAlertSound(profile)
                intIcon:Show()
            end
            local frameOpacity = profile.frameOpacity or 1.0
            intIcon:SetAlpha(frameOpacity)
        else
            if intIcon.spellID or intIcon:IsShown() then
                UIRenderer.HideInterruptIcon(intIcon)
            end
        end
    elseif intIcon and (intIcon.spellID or intIcon:IsShown()) then
        UIRenderer.HideInterruptIcon(intIcon)
    end

    if shouldShowFrame then
    for i = 1, maxIcons do
        local icon = spellIconsRef[i]
        if icon then
            local spellID = hasSpells and spellIDs[i] or nil
            local spellInfo = spellID and GetCachedSpellInfo(spellID)

            -- Position stabilization (positions 2+): hold the current spell for
            -- POSITION_HOLD_TIME before replacing it. Prevents rapid position
            -- shuffling when SpellQueue re-categorizes spells (proc gained/lost,
            -- CD expired). If the old spell is no longer anywhere in the queue
            -- (consumed/cast), allow immediate replacement.
            -- Position 1 always passes through the Blizzard assistant suggestion.
            if i > 1 and spellID and icon.spellID and icon.spellID ~= spellID then
                local holdElapsed = currentTime - (icon.lastSpellSetTime or 0)
                if holdElapsed < POSITION_HOLD_TIME then
                    local oldStillQueued = false
                    for j = 1, spellCount do
                        if spellIDs[j] == icon.spellID then
                            oldStillQueued = true
                            break
                        end
                    end
                    if oldStillQueued then
                        local oldInfo = GetCachedSpellInfo(icon.spellID)
                        if oldInfo then
                            spellID = icon.spellID
                            spellInfo = oldInfo
                        end
                    end
                end
            end

            if spellID and spellInfo then
                local spellChanged = (icon.spellID ~= spellID)
                
                if spellChanged then
                    -- Flash grace period: preserve previous spell/hotkey so key press
                    -- still triggers flash right as the queue rotates.
                    if icon.spellID then
                        icon.previousSpellID = icon.spellID
                        icon.spellChangeTime = currentTime
                        if icon.normalizedHotkey then
                            icon.previousNormalizedHotkey = icon.normalizedHotkey
                        end
                    end
                    icon.lastSpellSetTime = currentTime
                end
                
                icon.spellID = spellID
                
                local iconTexture = icon.iconTexture
                
                -- Fixes missing artwork on first assignment or after UI reload.
                if spellChanged or not iconTexture:GetTexture() then
                    iconTexture:SetTexture(spellInfo.iconID)
                end
                
                if not iconTexture:IsShown() then
                    iconTexture:Show()
                end
                
                -- "Waiting for..." = Assisted Combat's resource-wait indicator.
                -- Detected by iconID 134377, the shared timer icon Blizzard uses for
                -- all "Waiting for [resource]" placeholder spells. File IDs are the
                -- same across all locales, so this check is locale-safe.
                if spellChanged then
                    icon.isWaitingSpell = spellInfo.iconID == 134377
                end
                local centerText = icon.centerText
                if centerText then
                    if icon.isWaitingSpell then
                        centerText:SetText(WAIT_LABEL)
                        centerText:Show()
                    else
                        centerText:Hide()
                    end
                end
                
                if i > 1 then
                    iconTexture:SetVertexColor(QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_OPACITY)
                else
                    iconTexture:SetVertexColor(1, 1, 1, 1)
                end

                -- Swipe animates smoothly once set; only refresh on change or throttle tick.
                if spellChanged or shouldUpdateCooldowns then
                    UpdateButtonCooldowns(icon)
                end

                -- Proc glow replaces all other glows to avoid confusing layered animations.
                local glowState = ResolveGlowState(i, spellID, showPrimaryGlow, showProcGlow, showGapCloserGlow)

                -- Glow hysteresis (positions 2+): require desired glow state to be
                -- stable for GLOW_HOLD_TIME before switching animations. Prevents
                -- jarring animation restarts from transient proc toggles.
                -- Position 1 always reflects current state immediately.
                if i > 1 then
                    if spellChanged then
                        -- Spell changed: reset hysteresis, apply immediately
                        icon.lastRenderedGlow = glowState
                        icon.pendingGlowState = nil
                    elseif icon.lastRenderedGlow and glowState ~= icon.lastRenderedGlow then
                        if icon.pendingGlowState == glowState then
                            if currentTime - (icon.pendingGlowTime or 0) >= GLOW_HOLD_TIME then
                                icon.lastRenderedGlow = glowState
                                icon.pendingGlowState = nil
                            end
                        else
                            icon.pendingGlowState = glowState
                            icon.pendingGlowTime = currentTime
                        end
                        glowState = icon.lastRenderedGlow
                    else
                        icon.lastRenderedGlow = glowState
                        icon.pendingGlowState = nil
                    end
                end

                if glowState == GLOW_ASSISTED then
                    UIAnimations.StartAssistedGlow(icon, isInCombat)
                    icon.hasAssistedGlow = true
                elseif icon.hasAssistedGlow then
                    UIAnimations.StopAssistedGlow(icon)
                    icon.hasAssistedGlow = false
                end

                if glowState == GLOW_PROC then
                    if icon.hasGapCloserGlow then UIAnimations.StopGapCloserGlow(icon); icon.hasGapCloserGlow = false end
                    if not icon.hasProcGlow then UIAnimations.ShowProcGlow(icon); icon.hasProcGlow = true end
                else
                    if icon.hasProcGlow then UIAnimations.HideProcGlow(icon); icon.hasProcGlow = false end
                    -- Stale flag guard: re-sync if external code hid the frame without clearing the flag.
                    if icon.hasGapCloserGlow and icon.GapCloserHighlightFrame
                        and not icon.GapCloserHighlightFrame:IsShown() then
                        icon.hasGapCloserGlow = false
                    end
                    if glowState == GLOW_GAP_CLOSER and not icon.hasGapCloserGlow then
                        UIAnimations.StartGapCloserGlow(icon)
                        icon.hasGapCloserGlow = true
                    elseif glowState ~= GLOW_GAP_CLOSER and icon.hasGapCloserGlow then
                        UIAnimations.StopGapCloserGlow(icon)
                        icon.hasGapCloserGlow = false
                    end
                end

                -- Re-query only when action bars or bindings change.
                -- Empty results ("") are retried so the scanner's 0.25s refresh
                -- can resolve proc overrides (Infernal Bolt, Ruination, etc.)
                -- that miss on the first frame before GetOverrideSpell propagates.
                local hotkey
                local hotkeyChanged = false
                if hotkeysDirty or spellChanged or not icon.cachedHotkey or icon.cachedHotkey == "" then
                    hotkey = GetSpellHotkey and GetSpellHotkey(spellID) or ""
                    if icon.cachedHotkey ~= hotkey then
                        hotkeyChanged = true
                    end
                    icon.cachedHotkey = hotkey
                else
                    hotkey = icon.cachedHotkey
                end
                
                -- When showHotkeys is off, keep hotkey for flash matching but clear display text.
                local displayHotkey = showHotkeys and hotkey or ""
                local currentHotkey = icon.hotkeyText:GetText() or ""
                if currentHotkey ~= displayHotkey then
                    icon.hotkeyText:SetText(displayHotkey)
                end

                if hotkeyChanged and hotkey ~= "" then
                    local normalized = NormalizeHotkey(hotkey)
                    -- Track previous hotkey for grace period (spell position changes)
                    if icon.normalizedHotkey and icon.normalizedHotkey ~= normalized then
                        icon.previousNormalizedHotkey = icon.normalizedHotkey
                        icon.hotkeyChangeTime = currentTime
                    end
                    icon.normalizedHotkey = normalized
                elseif hotkeyChanged then
                    icon.normalizedHotkey = nil
                end

                -- Blizzard's flash is button-bound, not spell-bound — can't mirror it.
                
                -- IsSpellInRange: per-frame check (cheap NeverSecret API, no throttle).
                local isOutOfRange = false
                if displayHotkey ~= "" and C_Spell_IsSpellInRange then
                    local inRange = C_Spell_IsSpellInRange(spellID)
                    if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
                        icon.cachedOutOfRange = (inRange == false)
                    else
                        icon.cachedOutOfRange = false
                    end
                    isOutOfRange = icon.cachedOutOfRange or false
                end
                if icon.lastOutOfRange ~= isOutOfRange then
                    if isOutOfRange then
                        icon.hotkeyText:SetTextColor(1, 0, 0, 1)
                    else
                        local hkc = overlays and overlays.hotkey and overlays.hotkey.color
                        icon.hotkeyText:SetTextColor((hkc and hkc.r) or 1, (hkc and hkc.g) or 1, (hkc and hkc.b) or 1, (hkc and hkc.a) or 1)
                    end
                    icon.lastOutOfRange = isOutOfRange
                end
                
                -- 1 = channeling (grey), 2 = no resources (blue tint), 3 = normal,
                -- 4 = channeling THIS spell (fill animation, full color)
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                -- Match via UnitChannelInfo spellID + GetOverrideSpell (IsCurrentSpell
                -- returns false for channels). UnitChannelInfo returns the override
                -- spellID (e.g. 234153) while the queue has the base (e.g. 689).
                local isChanneledSpell = false
                if isChanneling and channelSpellID then
                    if spellID == channelSpellID then
                        isChanneledSpell = true
                    elseif C_Spell_GetOverrideSpell then
                        local overrideID = C_Spell_GetOverrideSpell(spellID)
                        isChanneledSpell = (overrideID and overrideID == channelSpellID)
                    end
                end
                local isCastedSpell = false
                if isCasting and castSpellID then
                    if spellID == castSpellID then
                        isCastedSpell = true
                    elseif C_Spell_GetOverrideSpell then
                        local overrideID = C_Spell_GetOverrideSpell(spellID)
                        isCastedSpell = (overrideID and overrideID == castSpellID)
                    end
                end
                local visualState
                if isChanneledSpell or isCastedSpell then
                    visualState = 4
                elseif isChanneling or isCasting then
                    visualState = 1
                elseif isInCombat then
                    -- Per-frame usability check (IsSpellUsable is NeverSecret and
                    -- lightweight) so resource-based tinting responds instantly.
                    icon.cachedIsUsable, icon.cachedNotEnoughResources = IsSpellUsable(spellID)
                    if not icon.cachedIsUsable and icon.cachedNotEnoughResources then
                        visualState = 2
                    else
                        visualState = 3
                    end
                else
                    visualState = 3
                end
                
                -- Force-apply every frame during channeling/casting so all icons
                -- grey/ungrey on the exact same frame (no per-icon desync).
                if icon.lastVisualState ~= visualState or icon.lastBaseDesaturation ~= baseDesaturation
                   or isChanneling or isCasting then
                    if visualState == 4 then
                        -- Channeling THIS spell: full color + cooldown sweep showing channel progress
                        iconTexture:SetDesaturation(baseDesaturation)
                        iconTexture:SetVertexColor(1, 1, 1)
                    elseif visualState == 1 then
                        iconTexture:SetDesaturation(1.0)
                        iconTexture:SetVertexColor(1, 1, 1)
                    elseif visualState == 2 then
                        iconTexture:SetDesaturation(0)
                        iconTexture:SetVertexColor(0.3, 0.3, 0.8)
                    else
                        iconTexture:SetDesaturation(baseDesaturation)
                        iconTexture:SetVertexColor(1, 1, 1)
                    end
                    icon.lastVisualState = visualState
                    icon.lastBaseDesaturation = baseDesaturation
                end

                -- Channel/cast fill animation: Blizzard-style sliding fill on the active icon.
                -- Uses the same atlas textures as the action bar (UI-HUD-ActionBar-Channel-Fill).
                -- StartChannelFill reads UnitChannelInfo timing (NeverSecret) internally.
                -- Only shown for channels (not hardcasts) — casts just grey out.
                if isChanneledSpell then
                    if not icon._hasChannelFill then
                        UIAnimations.StartChannelFill(icon)
                    end
                elseif icon._hasChannelFill then
                    UIAnimations.StopChannelFill(icon)
                end

                if not icon:IsShown() then
                    icon:Show()
                end
            else
                if icon.spellID then
                    icon.spellID = nil
                    icon.iconTexture:Hide()
                    icon.cooldown:Hide()
                    if icon.centerText then icon.centerText:Hide() end
                    if icon.chargeText then icon.chargeText:Hide() end
                    icon._cooldownShown = nil
                    icon._chargeCooldownShown = nil
                    icon.cachedHotkey = nil
                    icon.cachedIsUsable = nil
                    icon.cachedNotEnoughResources = nil
                    icon.isWaitingSpell = nil
                    icon.hasAssistedGlow   = false
                    icon.hasProcGlow        = false
                    icon.hasGapCloserGlow   = false
                    icon.lastOutOfRange = nil
                    icon.lastVisualState = nil
                    icon.lastBaseDesaturation = nil
                    icon.cachedOutOfRange = nil
                    icon.normalizedHotkey = nil  -- Stale value causes wrong previousNormalizedHotkey on refill.
                    icon.lastSpellSetTime = nil
                    icon.lastRenderedGlow = nil
                    icon.pendingGlowState = nil
                    icon.pendingGlowTime = nil
                    UIAnimations.StopAssistedGlow(icon)
                    UIAnimations.HideProcGlow(icon)
                    UIAnimations.StopGapCloserGlow(icon)
                    icon.hotkeyText:SetText("")
                end
                
                if not icon:IsShown() then
                    icon:Show()
                end
            end
        end
    end
    end  -- Close if shouldShowFrame then block
    
    hotkeysDirty = false
    
    -- Defensive cooldowns + hotkeys + glow are now updated per-frame in the
    -- defensive icon loop above (alongside UpdateDefensiveVisualState).
    
    -- fadeOut's OnFinished can hide the frame after shouldShow flipped back to true
    -- (e.g. spells briefly cleared during Fel Rush), so also check for desync.
    if addon.mainFrame then
        local isFadingOut = addon.mainFrame.fadeOut and addon.mainFrame.fadeOut:IsPlaying()
        local actuallyVisible = addon.mainFrame:IsShown() and not isFadingOut
        local visibilityDesynced = shouldShowFrame ~= actuallyVisible

        if frameStateChanged or spellCountChanged or visibilityDesynced then
            if shouldShowFrame then
                if not addon.mainFrame:IsShown() or isFadingOut then
                    if isFadingOut then
                        addon.mainFrame.fadeOut:Stop()
                    end
                    addon.mainFrame:Show()
                    addon.mainFrame:SetAlpha(0)
                    if addon.mainFrame.fadeIn then
                        addon.mainFrame.fadeIn:Play()
                    else
                        addon.mainFrame:SetAlpha(profile.frameOpacity or 1.0)
                    end
                end
            else
                if addon.mainFrame:IsShown() then
                    if addon.mainFrame.fadeOut and not isFadingOut then
                        if addon.mainFrame.fadeIn and addon.mainFrame.fadeIn:IsPlaying() then
                            addon.mainFrame.fadeIn:Stop()
                        end
                        addon.mainFrame.fadeOut:Play()
                    else
                        if not addon.mainFrame.fadeOut then
                            addon.mainFrame:Hide()
                            addon.mainFrame:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end
    
    local interactionMode = profile.panelInteraction or (profile.panelLocked and "locked" or "unlocked")

    if lastPanelLocked ~= interactionMode then
        lastPanelLocked = interactionMode
        local isClickThrough = interactionMode == "clickthrough"
        local isLocked = interactionMode == "locked" or isClickThrough

        if addon.mainFrame then
            addon.mainFrame:EnableMouse(not isLocked)
        end

        for i = 1, maxIcons do
            local icon = spellIconsRef[i]
            if icon then
                icon:EnableMouse(not isClickThrough)
                if isLocked then
                    icon:RegisterForClicks()
                else
                    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                end
            end
        end
        if addon.defensiveIcon then
            addon.defensiveIcon:EnableMouse(not isClickThrough)
            if isLocked then
                addon.defensiveIcon:RegisterForClicks()
            else
                addon.defensiveIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
        end
        if addon.defensiveIcons then
            for _, defIcon in ipairs(addon.defensiveIcons) do
                if defIcon then
                    defIcon:EnableMouse(not isClickThrough)
                    if isLocked then
                        defIcon:RegisterForClicks()
                    else
                        defIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    end
                end
            end
        end
        -- Grab tab stays interactive unless click-through so users can still unlock.
        if addon.grabTab then
            addon.grabTab:EnableMouse(not isClickThrough)
        end
    end
    
    -- Skip if fade animation is playing to avoid interrupting it.
    local frameOpacity = profile.frameOpacity or 1.0
    if addon.mainFrame then
        local isFading = (addon.mainFrame.fadeIn and addon.mainFrame.fadeIn:IsPlaying()) or
                         (addon.mainFrame.fadeOut and addon.mainFrame.fadeOut:IsPlaying())
        if not isFading then
            addon.mainFrame:SetAlpha(frameOpacity)
        end
    end
    if addon.defensiveIcon then
        local isFading = (addon.defensiveIcon.fadeIn and addon.defensiveIcon.fadeIn:IsPlaying()) or
                         (addon.defensiveIcon.fadeOut and addon.defensiveIcon.fadeOut:IsPlaying())
        if not isFading then
            addon.defensiveIcon:SetAlpha(frameOpacity)
        end
    end
    
    lastFrameState.shouldShow = shouldShowFrame
    lastFrameState.spellCount = spellCount
    lastFrameState.lastUpdate = currentTime
end

function UIRenderer.OpenHotkeyOverrideDialog(addon, spellID)
    if not addon or not spellID then return end
    
    local spellInfo = BlizzardAPI.GetCachedSpellInfo(spellID)
    if not spellInfo then return end
    
    StaticPopupDialogs["JUSTAC_HOTKEY_OVERRIDE"] = {
        text = "Set custom hotkey display for:\n|T" .. (spellInfo.iconID or 0) .. ":16:16:0:0|t " .. spellInfo.name,
        button1 = "Set",
        button2 = "Remove", 
        button3 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 200,
        OnShow = function(self)
            local currentHotkey = addon:GetHotkeyOverride(self.data.spellID) or ""
            self.EditBox:SetText(currentHotkey)
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end,
        OnAccept = function(self)
            local newHotkey = self.EditBox:GetText()
            addon:SetHotkeyOverride(self.data.spellID, newHotkey)
        end,
        OnAlt = function(self)
            addon:SetHotkeyOverride(self.data.spellID, nil)
        end,
        EditBoxOnEnterPressed = function(self)
            local newHotkey = self:GetText()
            addon:SetHotkeyOverride(self:GetParent().data.spellID, newHotkey)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    
    StaticPopup_Show("JUSTAC_HOTKEY_OVERRIDE", nil, nil, {spellID = spellID})
end

--- Cached per-frame (≤0.015 s); both renderers share the same answer and debounce timer.
---
--- @param resolvedInts  table?   ordered {spellID, type} array from SpellDB.ResolveInterruptSpells
--- @param interruptMode string   "kickOnly" | "ccPrefer"
--- @param currentTime   number   GetTime() value from the caller
--- @return table  { shouldShow, spellID, castBar } — reused each call; do NOT hold across frames
function UIRenderer.EvaluateInterrupt(resolvedInts, interruptMode, currentTime)
    -- Keyed on time AND interruptMode so different renderer modes don't share stale results.
    if (currentTime - lastInterruptEvalTime) < 0.015
        and cachedIntResult.interruptMode == interruptMode then
        return cachedIntResult
    end
    lastInterruptEvalTime = currentTime
    cachedIntResult.interruptMode = interruptMode

    local shouldShow = false
    local intSpellID = nil
    local castBar    = nil

    local debounceActive = (currentTime - lastInterruptUsedTime) < INTERRUPT_DEBOUNCE
                        or (currentTime - lastCCAppliedTime)    < CC_APPLIED_SUPPRESS

    if not debounceActive and resolvedInts and BlizzardAPI.IsTargetInterruptWorthy() then
        local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target", false)

        -- Unified interruptibility check: event tracker → cast bar fields → API fallback.
        local isCasting, interruptible, bar = IsTargetCastInterruptible(nameplate)

        if isCasting then
            local targetCCImmune  = BlizzardAPI.IsTargetCCImmune()
            local targetAlreadyCC = UnitIsCrowdControlled and UnitIsCrowdControlled("target") or false
            local canCC = not targetCCImmune and not targetAlreadyCC
            -- ccShielded / ccPrefer: when cast is shielded, only CC spells can stop it.
            local ccOnly = not interruptible and canCC
                and (interruptMode == "ccShielded" or interruptMode == "ccPrefer")
            local preferCC = interruptMode == "ccPrefer" and canCC

            -- Uninterruptible + kickOnly → nothing useful to suggest.
            if not interruptible and not ccOnly then
                -- fall through to no-show
            else
                -- Single-pass spell selection: prefer CC when configured, otherwise first usable.
                local fallbackID = nil
                for _, entry in ipairs(resolvedInts) do
                    local sid, stype = entry.spellID, entry.type
                    -- In ccOnly mode, skip non-CC spells (kicks can't stop shielded casts).
                    if ccOnly and stype ~= "cc" then
                        -- skip
                    elseif (stype == "cc" and targetCCImmune) or targetAlreadyCC then
                        -- CC spells unusable on immune / already CC'd targets — skip.
                    elseif BlizzardAPI.IsSpellUsable(sid) and not SpellDB.IsInterruptOnCooldown(sid) then
                        if (preferCC or ccOnly) and stype == "cc" then
                            intSpellID = sid; shouldShow = true; break
                        elseif not fallbackID then
                            fallbackID = sid
                            if not preferCC and not ccOnly then break end
                        end
                    end
                end
                if not shouldShow and fallbackID then
                    intSpellID = fallbackID; shouldShow = true
                end
            end
            -- castBar is nil for API fallback; callers gracefully hide cast aura.
            if shouldShow then castBar = bar end
        end
    end

    -- Runs every frame: detects when suggested spell goes on CD (≈ was cast).
    if lastInterruptShownID then
        if SpellDB.IsInterruptOnCooldown(lastInterruptShownID) then
            lastInterruptUsedTime = currentTime
            lastInterruptShownID  = nil
        elseif not shouldShow then
            lastInterruptShownID = nil
        end
    end
    if shouldShow and intSpellID then
        lastInterruptShownID = intSpellID
    end

    cachedIntResult.shouldShow = shouldShow
    cachedIntResult.spellID    = intSpellID
    cachedIntResult.castBar    = castBar
    return cachedIntResult
end

function UIRenderer.SetCombatState(inCombat)
    isInCombat = inCombat
end

UIRenderer.UpdateButtonCooldowns = UpdateButtonCooldowns
UIRenderer.NormalizeHotkey       = NormalizeHotkey

-- Suppresses CC suggestions until the game registers the CC state on the target.
function UIRenderer.NotifyCCApplied()
    lastCCAppliedTime = GetTime()
end
