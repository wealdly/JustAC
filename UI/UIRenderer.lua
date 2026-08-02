-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: UI Renderer Module
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 44)
if not UIRenderer then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local UISootheCue = LibStub("JustAC-UISootheCue", true)
local CastInterruptTracker = LibStub("JustAC-CastInterruptTracker", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat", true)

if not BlizzardAPI or not ActionBarScanner or not SpellQueue or not UIAnimations or not UIFrameFactory then
    return
end

-- Localized label shown on the overlay when Assisted Combat is waiting for resources.
-- Centered over-icon text is standardized lowercase (matches the OOC click overlay's
-- "click"/"wait" hint). :lower() is ASCII-only, so Latin locales lowercase and CJK/Cyrillic
-- (no case) pass through unchanged.
local WAIT_LABEL = ((L and L["WAIT"]) or "WAIT"):lower()

-- Hot path cache
local GetTime = GetTime
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local C_Spell_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
-- Modern-first item APIs (same signatures); the bare legacy globals may not exist.
local GetItemCooldown = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
local GetItemSpell    = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local C_ActionBar_GetActionCooldown = C_ActionBar and C_ActionBar.GetActionCooldown
local C_ActionBar_GetActionCharges = C_ActionBar and C_ActionBar.GetActionCharges
local C_ActionBar_GetActionCooldownDuration = C_ActionBar and C_ActionBar.GetActionCooldownDuration
local C_ActionBar_GetActionChargeDuration = C_ActionBar and C_ActionBar.GetActionChargeDuration
local C_ActionBar_GetActionDisplayCount = C_ActionBar and C_ActionBar.GetActionDisplayCount
local C_AssistedCombat_GetNextCastSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
local C_Spell_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local C_Spell_GetSpellChargeDuration = C_Spell and C_Spell.GetSpellChargeDuration
local C_DurationUtil_CreateDuration = C_DurationUtil and C_DurationUtil.CreateDuration
local IS_DURATION_COOLDOWNS = BlizzardAPI.IS_DURATION_COOLDOWNS

local C_ActionBar_IsUsableAction = C_ActionBar and C_ActionBar.IsUsableAction
local C_ActionBar_IsActionInRange = C_ActionBar and C_ActionBar.IsActionInRange
local C_Spell_IsCurrentSpell = C_Spell and C_Spell.IsCurrentSpell
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local pcall = pcall
local ipairs = ipairs

-- Position stabilization: minimum display time before a spell at positions 2+
-- can be replaced. Prevents visual flicker from rapid proc/CD re-categorization
-- in SpellQueue. Position 1 always passes through Blizzard's suggestion.
local POSITION_HOLD_TIME = UIFrameFactory.POSITION_HOLD_TIME  -- 50ms

-- Glow hysteresis: require desired glow state to be stable for this duration
-- before switching animations. Prevents jarring animation restarts when proc
-- state toggles transiently (e.g. during GCD processing).
local GLOW_HOLD_TIME = UIFrameFactory.GLOW_HOLD_TIME  -- 50ms

-- Gap-closers have their own red crawl path; excluded here.
local function IsSpellProcced(spellID)
    return BlizzardAPI.IsSpellProcced(spellID)
end

-- Normalize a raw WoW hotkey string to the MODIFIER-KEY format used by CreateKeyPressDetector.
-- Multi-modifier combos are checked first to prevent partial prefix matches.
-- Mouse abbreviations are reversed so matching uses WoW's raw binding names (BUTTON1-N).
-- Results are cached by raw input string (hotkeys rarely change; new bindings produce new keys).
local normalizeHotkeyCache = {}
local HOTKEY_NORMALIZE_PATTERNS = {
    { "^CTRL%-SHIFT%-(.+)$", "CTRL-SHIFT-" },
    { "^CTRL%-ALT%-(.+)$",   "CTRL-ALT-" },
    { "^SHIFT%-ALT%-(.+)$",  "SHIFT-ALT-" },
    { "^SHIFT%-(.+)$",       "SHIFT-" },
    { "^CTRL%-(.+)$",        "CTRL-" },
    { "^ALT%-(.+)$",         "ALT-" },
    { "^MOD%-(.+)$",         "MOD-" },

    { "^CTRL%-SHIFT[%-%+](.+)$", "CTRL-SHIFT-" },
    { "^CTRL%-ALT[%-%+](.+)$",   "CTRL-ALT-" },
    { "^SHIFT%-ALT[%-%+](.+)$",  "SHIFT-ALT-" },
    { "^SHIFT[%-%+](.+)$",       "SHIFT-" },
    { "^CTRL[%-%+](.+)$",        "CTRL-" },
    { "^ALT[%-%+](.+)$",         "ALT-" },

    { "^CS%-(.+)$", "CTRL-SHIFT-" },
    { "^CA%-(.+)$", "CTRL-ALT-" },
    { "^SA%-(.+)$", "SHIFT-ALT-" },
    { "^S%-(.+)$",  "SHIFT-" },
    { "^C%-(.+)$",  "CTRL-" },
    { "^A%-(.+)$",  "ALT-" },

    { "^CS(.+)$", "CTRL-SHIFT-" },
    { "^CA(.+)$", "CTRL-ALT-" },
    { "^SA(.+)$", "SHIFT-ALT-" },
    { "^S(.+)$",  "SHIFT-" },
    { "^C(.+)$",  "CTRL-" },
    { "^A(.+)$",  "ALT-" },

    { "^%+(.+)$", "MOD-" },
}

local function NormalizeHotkey(hotkey)
    local cached = normalizeHotkeyCache[hotkey]
    if cached then return cached end
    local n = hotkey:upper()

    -- Deterministic prefix parsing (first match wins):
    -- 1) already-normalized full forms
    -- 2) full-word forms with +/- separators
    -- 3) abbreviated forms with hyphen
    -- 4) compact abbreviated forms (no hyphen)
    -- 5) any-modifier form (+KEY)
    for _, rule in ipairs(HOTKEY_NORMALIZE_PATTERNS) do
        local suffix = n:match(rule[1])
        if suffix then
            n = rule[2] .. suffix
            break
        end
    end

    n = n:gsub("MWU$", "MOUSEWHEELUP")
    n = n:gsub("MWD$", "MOUSEWHEELDOWN")
    n = n:gsub("M(%d+)$", "BUTTON%1")
    normalizeHotkeyCache[hotkey] = n
    return n
end

local function SetIconHotkeyText(icon, hotkey, showHotkeys)
    if not icon or not icon.hotkeyText then return end
    local displayHotkey = showHotkeys and hotkey or ""
    if (icon.hotkeyText:GetText() or "") ~= displayHotkey then
        icon.hotkeyText:SetText(displayHotkey)
    end
end

local function SetIconNormalizedHotkey(icon, hotkey, now, trackPrevious)
    if not icon then return end
    if hotkey and hotkey ~= "" then
        local normalized = NormalizeHotkey(hotkey)
        if trackPrevious and icon.normalizedHotkey and icon.normalizedHotkey ~= normalized then
            icon.previousNormalizedHotkey = icon.normalizedHotkey
            icon.hotkeyChangeTime = now or GetTime()
        end
        icon.normalizedHotkey = normalized
    else
        icon.normalizedHotkey = nil
    end
end

-- Cooldown/charge display via Blizzard's ActionButton_ApplyCooldown (secret-safe passthrough).
-- Display layer: pipe secret values straight to UI widgets (Blizzard renders them).
-- Logic layer: all readiness decisions use cached OOC data (CooldownTracking).
local defaultCooldownInfo = { startTime = 0, duration = 0, isEnabled = 1, modRate = 1, isActive = false }
local defaultChargeInfo   = { currentCharges = 0, maxCharges = 0, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 0, isActive = false }

local function UpdateButtonCooldowns(button)
    if not button then return end

    local isItem = button.isItem
    local id = isItem and button.itemID or button.spellID

    if not id then
        if button.cooldown then button.cooldown:Clear() end
        if button.chargeCooldown then button.chargeCooldown:Clear() end
        if button.chargeText then button.chargeText:Hide() end
        button._lastCooldownID = nil
        return
    end

    if id ~= button._lastCooldownID then
        if button.cooldown then button.cooldown:Clear() end
        if button.chargeCooldown then button.chargeCooldown:Clear(); button.chargeCooldown:Hide() end
        button._lastCooldownID = id
        button._cdStart, button._cdDuration = nil, nil  -- new spell: force swipe re-apply
    end

    -- Resolve display spellID once (spell overrides, e.g. Pyroblast → Hot Streak).
    local cooldownID = not isItem and BlizzardAPI.GetDisplaySpellID(id) or nil

    -- Find the direct action bar slot for this spell/item (one where this exact
    -- spell is the visible action). Priority: direct slot > assisted combat slot
    -- (pos1 off-bar spells). Modifier-macro slots are deliberately excluded - see
    -- the cdSlot note below.
    local directSlot
    if isItem then
        directSlot = ActionBarScanner.GetDirectSlotForItem(id)
    else
        directSlot = ActionBarScanner.GetDirectSlotForSpell(id)
        if not directSlot and C_AssistedCombat_GetNextCastSpell then
            local nextCast = C_AssistedCombat_GetNextCastSpell(true)
            if nextCast and (nextCast == id or nextCast == cooldownID) then
                directSlot = ActionBarScanner.GetAssistedCombatSlot()
            end
        end
    end
    -- Cooldown queries use ONLY a direct slot - one where this exact spell is the
    -- currently-visible action. We must NOT fall back to a modifier-macro slot here:
    -- that slot reflects whatever the macro resolves to *right now* (the base spell
    -- when the modifier isn't held), so its cooldown is the wrong spell's. The symptom
    -- is a real cooldown that only appears while the modifier is held and vanishes on
    -- release. When there's no direct slot we fall through to the spell API below, which
    -- reads THIS spell's own cooldown and persists regardless of modifier state.
    -- (Trade-off: a GCD-only swipe won't show on a modifier-gated icon while the
    -- modifier is up - acceptable; correct real-CD display matters more.)
    local cdSlot = directSlot

    -- Fetch cooldown + charge data for the swipe animation.
    -- Slot-based APIs handle secrets via passthrough; spell APIs return secret
    -- structs that ActionButton_ApplyCooldown also renders correctly.
    local cooldownInfo, chargeInfo
    -- True when cooldownInfo carries our own non-secret start/duration numbers
    -- (item or local-cache source) rather than a secret/slot struct - drives the
    -- duration-object construction below.
    local ciFromNumbers = false

    if cdSlot and C_ActionBar_GetActionCooldown then
        cooldownInfo = C_ActionBar_GetActionCooldown(cdSlot)
        chargeInfo = C_ActionBar_GetActionCharges and C_ActionBar_GetActionCharges(cdSlot)
    elseif isItem then
        local start, duration = GetItemCooldown(id)
        local active = (start or 0) > 0 and (duration or 0) > 0
        cooldownInfo = { startTime = start or 0, duration = duration or 0, isEnabled = 1, modRate = 1, isActive = active }
        ciFromNumbers = true
    elseif cooldownID then
        -- No direct slot (modifier-macro / off-bar): source the swipe from our own
        -- non-secret local cooldown tracking. These numbers are modifier-independent
        -- and readable in combat, so the swipe persists after the modifier is released
        -- instead of flickering. Fall back to the spell API only when the spell isn't
        -- locally tracked (best-effort; isActive is NeverSecret, duration renders via
        -- the secret-safe duration object below).
        local lStart, lDuration = BlizzardAPI.GetLocalCooldown(cooldownID)
        if not lStart then lStart, lDuration = BlizzardAPI.GetLocalCooldown(id) end
        -- Engine-truth guard: only trust the local cooldown if the spell is actually on
        -- a real cooldown right now. An override/combo transform (Templar Strike ->
        -- Templar Slash) can leave a stale local CD from the base that the action bar
        -- doesn't show; the ignore-GCD duration-object probe (secret-safe) catches it.
        if BlizzardAPI.IsSpellOnCooldown and not BlizzardAPI.IsSpellOnCooldown(cooldownID or id) then
            cooldownInfo = nil
        elseif lStart and lDuration and lDuration > 0 then
            cooldownInfo = { startTime = lStart, duration = lDuration, isEnabled = 1, modRate = 1, isActive = true }
            ciFromNumbers = true
        elseif C_Spell_GetSpellCooldown then
            local ok, result = pcall(C_Spell_GetSpellCooldown, cooldownID)
            if ok and result then cooldownInfo = result end
        end
    end

    -- Charge count text: determine readable currentCharges for the text overlay.
    -- Spell API is the authoritative source for charge data. Slot-based chargeInfo
    -- can be stale during modifier presses (macro resolves to a different spell).
    local chargeText = ""
    if not isItem and cooldownID and C_Spell_GetSpellCharges then
        local ok, result = pcall(C_Spell_GetSpellCharges, cooldownID)
        if ok and result then
            chargeInfo = chargeInfo or result
            -- maxCharges is NeverSecret (source-verified): safe to compare in combat.
            -- currentCharges is SECRET in combat: use IsSecretValue to gate OOC-only logic.
            local curOk = not BlizzardAPI.IsSecretValue(result.currentCharges)
            if result.maxCharges > 1 then
                if curOk then
                    -- Out of combat: prefer spell API over slot-based data (immune to modifier changes).
                    chargeInfo = result
                end
                -- currentCharges: NeverSecret OOC (direct use), SECRET in combat (SetText passthrough).
                chargeText = result.currentCharges
            end
        end
    end

    -- Slot-based fallback for charge text (NeverSecret, always readable).
    -- Used when spell has no charges (maxCharges <= 1) or GetSpellCharges unavailable.
    if chargeText == "" and directSlot and C_ActionBar_GetActionDisplayCount then
        chargeText = C_ActionBar_GetActionDisplayCount(directSlot)
    end

    -- Apply cooldown swipe animation.
    local ci = cooldownInfo or defaultCooldownInfo
    local chi = chargeInfo or defaultChargeInfo
    if IS_DURATION_COOLDOWNS and button.cooldown then
        -- Build 66562+: DurationObject path (secret-safe in tainted execution).
        local showNormal = ci.isActive
        local showCharge = chi.isActive

        -- Charge spells at 0 charges: the action-bar/spell MAIN cooldown API doesn't
        -- report the recharge (it lives in the charge layer / edge ring), so the dark
        -- "greyout" swipe Blizzard shows at 0 charges is otherwise missing from our
        -- queue. Detect 0 charges via non-secret local charge tracking and promote the
        -- recharge to the main swipe (which owns the clipped dark sweep; our charge
        -- widget is edge-only). The edge ring is suppressed below when depleted.
        local chargeDepleted = not isItem and cooldownID
            and BlizzardAPI.IsChargeSpellOnCooldown and BlizzardAPI.IsChargeSpellOnCooldown(cooldownID)

        -- Main cooldown swipe. Priority: the direct action-bar slot (most accurate,
        -- secret-safe passthrough). When that slot disappears - a modifier press/release
        -- hides the ability from the bar - we transition to the non-secret local-cache
        -- numbers and apply them ONCE; the swipe is already animating, so we then leave
        -- it alone (no per-tick duration-object rebuild) for a seamless, efficient hold.
        if showNormal or chargeDepleted then
            if chargeDepleted and cdSlot and C_ActionBar_GetActionChargeDuration then
                -- 0 charges with a visible slot: the next charge's recharge is the swipe.
                local durObj = C_ActionBar_GetActionChargeDuration(cdSlot)
                if durObj then
                    button.cooldown:SetCooldownFromDurationObject(durObj)
                else
                    button.cooldown:Clear()
                end
                button._cdStart, button._cdDuration = nil, nil
            elseif cdSlot and C_ActionBar_GetActionCooldownDuration then
                local durObj = C_ActionBar_GetActionCooldownDuration(cdSlot)
                if durObj then
                    button.cooldown:SetCooldownFromDurationObject(durObj)
                else
                    button.cooldown:Clear()
                end
                -- Slot is authoritative this tick; force the numeric fallback to
                -- re-apply fresh if/when it next takes over.
                button._cdStart, button._cdDuration = nil, nil
            elseif ciFromNumbers then
                -- Item / local-cache numbers: re-apply only when the timing changes, so
                -- the swipe set while the slot existed continues across the modifier
                -- transition instead of being rebuilt (and restarted) every tick.
                if button._cdStart ~= ci.startTime or button._cdDuration ~= ci.duration then
                    if C_DurationUtil_CreateDuration then
                        local durObj = C_DurationUtil_CreateDuration()
                        if durObj then
                            durObj:SetTimeFromStart(ci.startTime, ci.duration, ci.modRate)
                            button.cooldown:SetCooldownFromDurationObject(durObj)
                        end
                    end
                    button._cdStart, button._cdDuration = ci.startTime, ci.duration
                end
            elseif cooldownID and C_Spell_GetSpellCooldownDuration then
                local ok, durObj = pcall(C_Spell_GetSpellCooldownDuration, cooldownID)
                if ok and durObj then button.cooldown:SetCooldownFromDurationObject(durObj) end
                button._cdStart, button._cdDuration = nil, nil
            else
                button.cooldown:Clear()
                button._cdStart, button._cdDuration = nil, nil
            end
        else
            -- isActive tracks REAL cooldowns, so a pure GCD window lands here on icons
            -- whose swipe source can't see the GCD: macro-driven slots are never
            -- "direct" (their resolved spell changes with modifiers), and the
            -- local-numbers path only carries real CDs. IsSpellOnGCD (NeverSecret,
            -- true exactly during a pure GCD window; never for off-GCD abilities)
            -- gates rendering the GCD from the spell's own duration object instead
            -- of clearing - so macro/off-bar icons keep the GCD sweep.
            local gcdShown = false
            if cooldownID and C_Spell_GetSpellCooldownDuration
               and BlizzardAPI.IsSpellOnGCD and BlizzardAPI.IsSpellOnGCD(cooldownID) then
                local ok, durObj = pcall(C_Spell_GetSpellCooldownDuration, cooldownID)
                if ok and durObj then
                    button.cooldown:SetCooldownFromDurationObject(durObj)
                    gcdShown = true
                end
            end
            if not gcdShown then
                button.cooldown:Clear()
            end
            button._cdStart, button._cdDuration = nil, nil
        end

        -- Charge cooldown edge ring (only while charges remain - at 0 charges the
        -- recharge is shown as the main swipe above to match the action bar).
        if showCharge and not chargeDepleted and button.chargeCooldown then
            local chargeDurObj
            if cdSlot and C_ActionBar_GetActionChargeDuration then
                chargeDurObj = C_ActionBar_GetActionChargeDuration(cdSlot)
            elseif cooldownID and C_Spell_GetSpellChargeDuration then
                local ok, result = pcall(C_Spell_GetSpellChargeDuration, cooldownID)
                if ok then chargeDurObj = result end
            end
            if chargeDurObj then
                button.chargeCooldown:SetCooldownFromDurationObject(chargeDurObj)
            else
                button.chargeCooldown:Clear()
            end
        elseif button.chargeCooldown then
            button.chargeCooldown:Clear()
        end
    elseif ActionButton_ApplyCooldown and button.cooldown and button.chargeCooldown then
        -- Pre-66562 fallback: ActionButton_ApplyCooldown handles secrets internally.
        ActionButton_ApplyCooldown(
            button.cooldown, ci,
            button.chargeCooldown, chi,
            nil, nil
        )
    end

    -- Apply charge/item count text.
    if button.chargeText then
        if isItem then
            local count = GetItemCount(id)
            button.chargeText:SetText(count and count > 1 and count or "")
        else
            button.chargeText:SetText(chargeText)
        end
        button.chargeText:Show()
    end
end

local DEFAULT_QUEUE_DESATURATION = 0
local QUEUE_ICON_BRIGHTNESS = 1.0
local QUEUE_ICON_OPACITY = 1.0

local isInCombat = false
local isChanneling = false
local channelSpellID = nil  -- Override spellID (for fill animation matching)
local isCasting = false
local castSpellID = nil  -- Override spellID (for cast-fill matching)
local cachedChannelSpellID = nil  -- Set by UNIT_SPELLCAST_CHANNEL_START, cleared by _STOP
local cachedCastSpellID    = nil  -- Set by UNIT_SPELLCAST_START, cleared by _STOP
local CHANNEL_EARLY_UNGREY = 0.1  -- Stop greying out 100ms before channel/cast ends
local hotkeysDirty = true
local lastPanelLocked = nil
local lastFrameState = {
    shouldShow = false,
    spellCount = 0,
}

-- Swipe animates smoothly once set; no need to update every frame.
local lastCooldownUpdate = 0
local COOLDOWN_UPDATE_INTERVAL = UIFrameFactory.COOLDOWN_UPDATE_INTERVAL
local USABILITY_UPDATE_INTERVAL = UIFrameFactory.USABILITY_UPDATE_INTERVAL

-- ── Visual state constants (returned by ResolveVisualState, consumed by ApplyVisualState) ──
local VS_GREYED        = 1  -- channeling/casting a different spell (full desat)
local VS_NO_RESOURCES  = 2  -- usable but not enough resources (blue tint)
local VS_NORMAL        = 3  -- ready and usable
local VS_ACTIVE_CAST   = 4  -- this spell is currently being cast/channeled
local VS_UNAVAILABLE   = 5  -- on cooldown or wrong form (gray desat)
local VS_OUT_OF_RANGE  = 6  -- out of range, no hotkey visible (red tint)
local VS_RANGE_HOTKEY  = 7  -- out of range, hotkey visible (muted warm; hotkey text carries the red)

-- ── Defensive visual state constants (used by UpdateDefensiveVisualState) ──
local DVS_CHANNELING    = 1  -- channeling/casting a different spell (full desat)
local DVS_NO_RESOURCES  = 2  -- usable but not enough resources (blue tint)
local DVS_NORMAL        = 3  -- ready and usable
local DVS_ON_COOLDOWN   = 4  -- on cooldown or unavailable (gray desat)
local DVS_ACTIVE_CAST   = 5  -- this spell is currently being cast/channeled
local DVS_WAITING       = 6  -- held-back emergency heal above the low-health threshold (desat + WAIT tag)

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared DPS icon helpers (used by both UIRenderer and UINameplateOverlay)
-- ─────────────────────────────────────────────────────────────────────────────

--- Check whether a spell is out of range. Updates icon.cachedOutOfRange.
--- @param icon table  Icon button table
--- @param spellID number
--- @param directSlot number|nil  Action bar slot (preferred, NeverSecret)
--- @return boolean isOutOfRange
local function CheckSpellRange(icon, spellID, directSlot)
    local inRange
    if directSlot and C_ActionBar_IsActionInRange then
        inRange = C_ActionBar_IsActionInRange(directSlot, "target")
    elseif C_Spell_IsSpellInRange then
        inRange = C_Spell_IsSpellInRange(spellID)
    end
    if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
        icon.cachedOutOfRange = (inRange == false)
    else
        icon.cachedOutOfRange = false
    end
    return icon.cachedOutOfRange or false
end

--- Update hotkey text color based on out-of-range state.
--- @param icon table  Icon button with .hotkeyText and .lastOutOfRange
--- @param isOutOfRange boolean
--- @param hotkeyColor table|nil  {r,g,b,a} from profile hotkey color
local function UpdateRangeHotkeyColor(icon, isOutOfRange, hotkeyColor)
    if icon.lastOutOfRange == isOutOfRange then return end
    if isOutOfRange then
        icon.hotkeyText:SetTextColor(1, 0, 0, 1)
    else
        local c = hotkeyColor
        icon.hotkeyText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1)
    end
    icon.lastOutOfRange = isOutOfRange
end

--- Check if spellID matches targetID directly or via BlizzardAPI.GetDisplaySpellID.
--- @param spellID number  Spell to test
--- @param targetID number  Active cast/channel spell
--- @return boolean
local function MatchesSpellOrOverride(spellID, targetID)
    if spellID == targetID then return true end
    if BlizzardAPI and BlizzardAPI.GetDisplaySpellID then
        local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
        return displayID and displayID == targetID
    end
    return false
end

--- Determine whether this icon's spell matches the current cast/channel.
--- @return boolean isChanneledSpell, boolean isCastedSpell
local function MatchActiveCast(spellID, isChanneling, channelSpellID, isCasting, castSpellID)
    local isChanneledSpell = (isChanneling and channelSpellID and MatchesSpellOrOverride(spellID, channelSpellID)) or false
    local isCastedSpell    = (isCasting    and castSpellID    and MatchesSpellOrOverride(spellID, castSpellID))    or false
    return isChanneledSpell, isCastedSpell
end

--- Resolve player cast/channel state for grey-out logic.
--- Returns: isChanneling, channelSpellID, isCasting, castSpellID
local function ResolvePlayerCastState(profile, cachedChannelID, cachedCastID)
    local isChanneling = false
    local channelSpellID = nil
    local isCasting = false
    local castSpellID = nil

    -- Grey out all icons while channeling (optional, gated by profile toggle).
    -- PlayerCastingBarFrame.channeling is a plain Lua boolean (set by CastingBarMixin),
    -- not a secret value. PlayerChannelBarFrame was removed in the Dragonflight UI rework.
    -- Early ungrey: stop greying out 100ms before channel ends.
    if profile.greyOutWhileChanneling ~= false and PlayerCastingBarFrame and PlayerCastingBarFrame.channeling == true then
        isChanneling = true
        channelSpellID = cachedChannelID
        local remaining = PlayerCastingBarFrame.value
        if remaining and not BlizzardAPI.IsSecretValue(remaining) and remaining < CHANNEL_EARLY_UNGREY then
            isChanneling = false
        end
    end

    -- Grey out during hardcasts (optional, gated by profile toggle).
    if profile.greyOutWhileCasting ~= false and PlayerCastingBarFrame and PlayerCastingBarFrame.casting == true then
        isCasting = true
        castSpellID = cachedCastID
        local remaining = PlayerCastingBarFrame.value
        if remaining and not BlizzardAPI.IsSecretValue(remaining) and remaining < CHANNEL_EARLY_UNGREY then
            isCasting = false
        end
    end

    return isChanneling, channelSpellID, isCasting, castSpellID
end

--- Resolve the visual state for a DPS icon.
--- States: VS_GREYED=1 (channeling other), VS_NO_RESOURCES=2 (blue), VS_NORMAL=3,
--- VS_ACTIVE_CAST=4 (current cast/channel), VS_UNAVAILABLE=5 (gray desat),
--- VS_OUT_OF_RANGE=6 (red tint), VS_RANGE_HOTKEY=7 (muted warm; hotkey shows red).
--- @param icon table  Icon button (caches cachedIsUsable/cachedNotEnoughResources)
--- @param spellID number
--- @param isChanneledSpell boolean
--- @param isCastedSpell boolean
--- @param isChanneling boolean
--- @param isCasting boolean
--- @param isOutOfRange boolean
--- @param showRangeTint boolean
--- @param showUsabilityTint boolean
--- @param inCombat boolean
--- @param directSlot number|nil  Action bar slot for slot-based usability
--- @param hasVisibleHotkey boolean|nil  When true, hotkey text handles range feedback; icon red tint is skipped
--- @return number visualState
local function ResolveVisualState(icon, spellID, isChanneledSpell, isCastedSpell,
                                  isChanneling, isCasting, isOutOfRange,
                                  showRangeTint, showUsabilityTint, inCombat, directSlot,
                                  hasVisibleHotkey, currentTime)
    if isChanneledSpell or isCastedSpell then
        return VS_ACTIVE_CAST
    elseif isChanneling or isCasting then
        return VS_GREYED
    elseif showRangeTint and isOutOfRange then
        return hasVisibleHotkey and VS_RANGE_HOTKEY or VS_OUT_OF_RANGE
    elseif inCombat then
        local now = currentTime or GetTime()
        local shouldRefreshUsability = icon.cachedIsUsable == nil
            or icon.cachedNotEnoughResources == nil
            or not icon.lastUsabilityCheck
            or (now - icon.lastUsabilityCheck) >= USABILITY_UPDATE_INTERVAL

        if shouldRefreshUsability then
            -- Usability check: prefer slot-based (NeverSecret), fallback to spell API
            if directSlot and C_ActionBar_IsUsableAction then
                icon.cachedIsUsable, icon.cachedNotEnoughResources = C_ActionBar_IsUsableAction(directSlot)
            else
                icon.cachedIsUsable, icon.cachedNotEnoughResources = BlizzardAPI.IsSpellUsable(spellID)
            end
            icon.lastUsabilityCheck = now
        end

        if not icon.cachedIsUsable then
            if icon.cachedNotEnoughResources then
                return VS_NO_RESOURCES   -- not enough resources → blue tint
            elseif showUsabilityTint then
                return VS_UNAVAILABLE    -- on CD / wrong form → gray desat
            end
        end
    end
    return VS_NORMAL
end

--- Apply visual state colors/desaturation to an icon.
--- @param icon table  Icon button
--- @param visualState number  1-7
--- @param baseDesaturation number  Position-based desaturation
--- @param brightness number  Vertex color multiplier for state 3 (1.0 = full)
--- @param opacity number  Alpha multiplier for state 3 (1.0 = full)
local function ApplyVisualState(icon, visualState, baseDesaturation, brightness, opacity)
    local iconTexture = icon.iconTexture
    -- Skip redundant GPU calls when state + desaturation haven't changed and
    -- we're not in a channel/cast frame (which requires per-frame sync).
    local prevState = icon.lastVisualState
    local prevDesat = icon.lastBaseDesaturation
    local changed = (prevState ~= visualState) or (prevDesat ~= baseDesaturation)
    if visualState == VS_ACTIVE_CAST then
        if changed then iconTexture:SetDesaturation(baseDesaturation) end
        iconTexture:SetVertexColor(1, 1, 1)
    elseif visualState == VS_GREYED then
        if prevState ~= VS_GREYED then iconTexture:SetDesaturation(1.0) end
        iconTexture:SetVertexColor(1, 1, 1)
    elseif visualState == VS_NO_RESOURCES then
        if prevState ~= VS_NO_RESOURCES then iconTexture:SetDesaturation(0) end
        iconTexture:SetVertexColor(0.4, 0.4, 1.0)
    elseif visualState == VS_UNAVAILABLE then
        if prevState ~= VS_UNAVAILABLE then iconTexture:SetDesaturation(0.8) end
        iconTexture:SetVertexColor(0.4, 0.4, 0.4)
    elseif visualState == VS_OUT_OF_RANGE then
        if changed then iconTexture:SetDesaturation(baseDesaturation) end
        iconTexture:SetVertexColor(1.0, 0.2, 0.2)
    elseif visualState == VS_RANGE_HOTKEY then
        -- Muted warm tint - hotkey text provides the red range feedback
        if prevState ~= VS_RANGE_HOTKEY then iconTexture:SetDesaturation(0) end
        iconTexture:SetVertexColor(0.55, 0.35, 0.35)
    else  -- VS_NORMAL
        if changed then iconTexture:SetDesaturation(baseDesaturation) end
        if changed then iconTexture:SetVertexColor(brightness, brightness, brightness, opacity) end
    end
    icon.lastVisualState = visualState
    icon.lastBaseDesaturation = baseDesaturation
end

--- Show or hide the casting highlight overlay.
--- @param icon table  Icon button with .castingHighlight and .castingHighlightShown
--- @param showCastingHighlight boolean  Profile toggle
--- @param spellID number
--- @param isChanneledSpell boolean
--- @param isCastedSpell boolean
local function UpdateCastingHighlight(icon, showCastingHighlight, spellID, isChanneledSpell, isCastedSpell)
    if showCastingHighlight and icon.castingHighlight then
        local wantHighlight = (isChanneledSpell or isCastedSpell)
            or (C_Spell_IsCurrentSpell and C_Spell_IsCurrentSpell(spellID))
        if wantHighlight and not icon.castingHighlightShown then
            icon.castingHighlight:Show()
            icon.castingHighlightShown = true
        elseif not wantHighlight and icon.castingHighlightShown then
            icon.castingHighlight:Hide()
            icon.castingHighlightShown = false
        end
    elseif icon.castingHighlightShown and icon.castingHighlight then
        icon.castingHighlight:Hide()
        icon.castingHighlightShown = false
    end
end

--- Reset all per-icon state fields when an icon slot becomes empty.
--- @param icon table  Icon button
local function ClearIconState(icon)
    icon.spellID = nil
    icon.isItem = nil
    icon.itemID = nil
    icon.itemCastSpellID = nil
    icon.iconTexture:Hide()
    if icon.cooldown then icon.cooldown:Clear(); icon.cooldown:Hide() end
    if icon.chargeCooldown then icon.chargeCooldown:Clear(); icon.chargeCooldown:Hide() end
    if icon.centerText then icon.centerText:Hide() end
    if icon.chargeText then icon.chargeText:Hide() end
    icon._cooldownShown        = false
    icon._chargeCooldownShown  = false
    icon._lastCooldownID       = nil
    icon.castingHighlightShown = false
    icon.cachedHotkey          = nil
    icon.cachedIsUsable        = nil
    icon.cachedNotEnoughResources = nil
    icon.lastUsabilityCheck    = nil
    icon.isWaitingSpell        = nil
    icon.lastOutOfRange        = nil
    icon.lastVisualState       = nil
    icon.lastBaseDesaturation  = nil
    icon.cachedOutOfRange      = nil
    icon.normalizedHotkey      = nil
    icon.lastSpellSetTime      = nil
    icon.lastRenderedGlow      = nil
    icon.pendingGlowState      = nil
    icon.pendingGlowTime       = nil
    if icon.castingHighlight then
        icon.castingHighlight:Hide()
    end
    if icon.spreadArrow then
        icon.spreadArrow:Hide()
    end
    if icon.cueDot then
        icon.cueDot:Hide()
        icon._cueDotKey = nil   -- force a repaint when this pooled icon is reused
    end
    if UIAnimations then
        if icon.hasAssistedGlow  then UIAnimations.StopAssistedGlow(icon) end
        if icon.hasProcGlow      then UIAnimations.HideProcGlow(icon) end
        if icon.hasGapCloserGlow then UIAnimations.StopGapCloserGlow(icon) end
        if icon.hasBurstGlow     then UIAnimations.StopBurstGlow(icon) end
    end
    icon.hasAssistedGlow  = false
    icon.hasProcGlow      = false
    icon.hasGapCloserGlow = false
    icon.hasBurstGlow     = false
    icon.hotkeyText:SetText("")
end

-- Stale atlas markup can appear if cached hotkeys survive a binding change.
function UIRenderer.InvalidateHotkeyCache()
    hotkeysDirty = true
    local addon = BlizzardAPI.GetAddon()
    if not addon then return end
    if addon.spellIcons then
        for i = 1, #addon.spellIcons do
            local icon = addon.spellIcons[i]
            if icon then
                icon.cachedHotkey = nil
            end
        end
    end
    if addon.maintenanceIcon then addon.maintenanceIcon.cachedHotkey = nil end
end

--------------------------------------------------------------------------------
-- Unified defensive glow arbitration. The full rebuild and the per-frame visual
-- pass BOTH funnel through here so they can never disagree (two writers with
-- different rules was the source of glow flicker/stutter).
-- Priority: proc > pre-combat green > marching ants > none - a procced OOC heal
-- keeps its proc animation, per design.
-- Turning a glow ON is immediate (procs must feel instant). Turning OFF or
-- downgrading must hold stable for GLOW_SETTLE_TIME: ability casts trigger full
-- rebuilds whose momentary proc-state flaps must not blink the glow.
--------------------------------------------------------------------------------
local GLOW_SETTLE_TIME = 0.3
local function ApplyDefensiveGlow(icon, want, isInCombat, immediate)
    local have = icon.appliedDefGlowState
    if want == have then
        icon.pendingDefGlowState = nil
        return
    end
    if not immediate and have ~= nil and want ~= "proc" then
        local now = GetTime()
        if icon.pendingDefGlowState ~= want then
            icon.pendingDefGlowState = want
            icon.pendingDefGlowTime = now
            return
        elseif now - (icon.pendingDefGlowTime or 0) < GLOW_SETTLE_TIME then
            return
        end
    end
    icon.pendingDefGlowState = nil
    if have == "proc" then
        UIAnimations.HideProcGlow(icon)
    elseif have == "marching" then
        UIAnimations.StopDefensiveGlow(icon)
    elseif have == "precombat" then
        UIAnimations.StopPrecombatGlow(icon)
    else
        -- Unknown starting state (fresh icon, combat-transition reset): clear all
        UIAnimations.HideProcGlow(icon)
        UIAnimations.StopDefensiveGlow(icon)
        UIAnimations.StopPrecombatGlow(icon)
    end
    if want == "proc" then
        -- Always animated (even OOC): a procced heal is the preferred top-up
        UIAnimations.ShowProcGlow(icon, true)
    elseif want == "marching" then
        UIAnimations.StartDefensiveGlow(icon, isInCombat)
    elseif want == "precombat" then
        UIAnimations.StartPrecombatGlow(icon, isInCombat)
    end
    icon.appliedDefGlowState = want
end

-- The one glow-priority rule, computed from icon state both paths maintain.
local function ComputeDefensiveGlowState(icon, isProc)
    if icon.isWaiting then return "none" end
    local mode = icon.defGlowMode or "all"
    if isProc and (mode == "all" or mode == "procOnly") then return "proc" end
    if icon.isPrecombatBuff then return "precombat" end
    if icon.defShowGlow and (mode == "all" or mode == "primaryOnly") then return "marching" end
    return "none"
end

-- Per-frame defensive visual state: channeling, usability, cooldown tinting.
function UIRenderer.UpdateDefensiveVisualState(defensiveIcon, forceCheck)
    if not defensiveIcon or not defensiveIcon.iconTexture then return end

    local id = defensiveIcon.currentID
    if not id then return end

    -- Held-back emergency heal (above the low-health threshold with "hide until low" on):
    -- shown desaturated with a WAIT tag instead of removed. Skip the usual usability/
    -- cooldown/channel tinting - the WAIT state is intentional and fixed until it lights up.
    if defensiveIcon.isWaiting then
        if defensiveIcon.lastDefVisualState ~= DVS_WAITING then
            defensiveIcon.iconTexture:SetDesaturation(1.0)
            defensiveIcon.iconTexture:SetVertexColor(0.5, 0.5, 0.5)
            defensiveIcon.lastDefVisualState = DVS_WAITING
        end
        return
    end

    -- Items use itemCastSpellID for channel/cast matching.
    local defID = defensiveIcon.isItem and defensiveIcon.itemCastSpellID or id
    local isDefActiveSpell = false
    if defID then
        if isChanneling and channelSpellID then
            if defensiveIcon.isItem then
                isDefActiveSpell = (defID == channelSpellID)
            else
                isDefActiveSpell = MatchesSpellOrOverride(defID, channelSpellID)
            end
        end
        if not isDefActiveSpell and isCasting and castSpellID then
            if defensiveIcon.isItem then
                isDefActiveSpell = (defID == castSpellID)
            else
                isDefActiveSpell = MatchesSpellOrOverride(defID, castSpellID)
            end
        end
    end

    local isGreyingOut = (isChanneling or isCasting) and not isDefActiveSpell
    local defVisualState = isGreyingOut and DVS_CHANNELING or DVS_NORMAL
    if isDefActiveSpell then defVisualState = DVS_ACTIVE_CAST end

    local now = GetTime()
    if forceCheck or (now - (defensiveIcon.lastDefUsableCheck or 0)) >= COOLDOWN_UPDATE_INTERVAL then
        defensiveIcon.lastDefUsableCheck = now
        if defensiveIcon.isItem then
            local itemSlot
            if id and ActionBarScanner and ActionBarScanner.GetDirectSlotForItem then
                itemSlot = ActionBarScanner.GetDirectSlotForItem(id)
            end
            if itemSlot and C_ActionBar_IsUsableAction then
                local slotUsable, slotNoMana = C_ActionBar_IsUsableAction(itemSlot)
                if not BlizzardAPI.IsSecretValue(slotUsable) and not BlizzardAPI.IsSecretValue(slotNoMana) then
                    defensiveIcon.cachedDefUsable = slotUsable or false
                    defensiveIcon.cachedDefNoResource = slotNoMana or false
                else
                    defensiveIcon.cachedDefUsable = true
                    defensiveIcon.cachedDefNoResource = false
                end
            else
                defensiveIcon.cachedDefUsable = true
                defensiveIcon.cachedDefNoResource = false
            end
        else
            defensiveIcon.cachedDefUsable, defensiveIcon.cachedDefNoResource = BlizzardAPI.IsSpellUsable(id)
        end
    end

    if defVisualState ~= DVS_CHANNELING and not defensiveIcon.cachedDefUsable then
        if defensiveIcon.cachedDefNoResource then
            defVisualState = DVS_NO_RESOURCES
        else
            defVisualState = DVS_ON_COOLDOWN
        end
    end

    if defensiveIcon.lastDefVisualState ~= defVisualState
       or isChanneling or isCasting then
        if defVisualState == DVS_ACTIVE_CAST then
            defensiveIcon.iconTexture:SetDesaturation(0)
            defensiveIcon.iconTexture:SetVertexColor(1, 1, 1)
        elseif defVisualState == DVS_CHANNELING then
            defensiveIcon.iconTexture:SetDesaturation(1.0)
            defensiveIcon.iconTexture:SetVertexColor(1, 1, 1)
        elseif defVisualState == DVS_NO_RESOURCES then
            defensiveIcon.iconTexture:SetDesaturation(0)
            defensiveIcon.iconTexture:SetVertexColor(0.4, 0.4, 1.0)
        elseif defVisualState == DVS_ON_COOLDOWN then
            defensiveIcon.iconTexture:SetDesaturation(0.8)
            defensiveIcon.iconTexture:SetVertexColor(0.6, 0.6, 0.6)
        else  -- DVS_NORMAL
            defensiveIcon.iconTexture:SetDesaturation(0)
            defensiveIcon.iconTexture:SetVertexColor(1, 1, 1)
        end
        defensiveIcon.lastDefVisualState = defVisualState
    end

    -- Fill sweep while this item is the active channel - including the synthetic "eating"
    -- channel we derive from a food's on-use aura above (StartChannelFill falls back to that
    -- aura's timing when there's no real UnitChannelInfo).
    if isDefActiveSpell and isChanneling then
        if not defensiveIcon._hasChannelFill and UIAnimations then
            UIAnimations.StartChannelFill(defensiveIcon)
        end
    elseif defensiveIcon._hasChannelFill and UIAnimations then
        UIAnimations.StopChannelFill(defensiveIcon)
    end

    -- Per-frame glow re-evaluation through the unified arbiter (same rule and
    -- settle-time as the full rebuild - the two can never disagree).
    if UIAnimations then
        local procCheckID = defensiveIcon.isItem and defensiveIcon.itemCastSpellID or id
        local isProc = procCheckID and IsSpellProcced(procCheckID) or false
        ApplyDefensiveGlow(defensiveIcon,
            ComputeDefensiveGlowState(defensiveIcon, isProc), isInCombat)
    end
end

-- Combat-safe visibility toggle for defensive icons. When the main frame is anchored to
-- Blizzard's TargetFrame (Target Frame anchoring), the attached icons join its protected
-- anchor family, so calling the protected frame Show()/Hide() on them in combat is blocked
-- ("AddOn 'JustAC' tried to call the protected function 'Button:Hide()'"). SetAlpha is never
-- protected: drive visibility with alpha and keep the frame Shown so alpha stays authoritative
-- (a Hidden frame can't be revealed by alpha alone). The protected Show() is only reconciled
-- out of combat; the parent main frame still hides the whole cluster when the HUD is hidden.
-- ponytail: a "hidden" icon stays Shown at alpha 0 (a small invisible mouse rect by the queue,
-- same as the DPS-queue empty slots). Upgrade path: EnableMouse(false) at creation if it bites.
-- Nameplate-overlay icons are exempt: they anchor to non-protected nameplates and are
-- Hidden on target loss (UpdateAnchor), so their Show() is combat-safe and must not
-- wait for OOC or they stay invisible for the rest of combat.
local function SetDefensiveIconVisible(defensiveIcon, visible)
    if not defensiveIcon:IsShown() and (defensiveIcon.isOverlayIcon or not InCombatLockdown()) then
        defensiveIcon:Show()
    end
    defensiveIcon:SetAlpha(visible and 1 or 0)
end

--- True if casting this spell starts no global cooldown, so the next ability can be
--- pressed immediately. Static client data (never a secret read, so this is combat-safe).
--- The table is keyed on BASE spell ids, so an override/form variant is resolved first -
--- otherwise a transformed ability would silently lose its marker. Unknown id -> false:
--- a missing marker is harmless, a wrong one tells the player to clip a real GCD.
local offGcdCache = {}
local function IsOffGCDSpell(spellID)
    if not spellID then return false end
    local hit = offGcdCache[spellID]
    if hit ~= nil then return hit end
    local CD = LibStub("JustAC-CooldownData", true)
    local result = false
    if CD and CD.IsOffGCD then
        result = CD.IsOffGCD(spellID)
        if not result and BlizzardAPI and BlizzardAPI.ResolveBaseSpellID then
            local base = BlizzardAPI.ResolveBaseSpellID(spellID)
            result = base and CD.IsOffGCD(base) or false
        end
    end
    offGcdCache[spellID] = result
    return result
end

-- Move-cast marker classification. A spell is castable while moving when it is
-- INSTANT right now: base instants always, hardcasts only while a proc has made
-- them instant (Hot Streak, Lava Surge, ...). Channels are excluded (movement
-- breaks them) even though they also report cast time 0.
--
-- The static class is cached per spell; the proc state is read live per render.
-- castTime is static spell metadata (not a live/secret value), but the compare is
-- guarded just in case, failing safe to "hardcast" (proc-gated, never a false yes).
local issecretvalue = issecretvalue  -- 12.0 global; nil on older clients
local C_SpellActivationOverlay_IsSpellOverlayed =
    C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local moveCastClassCache = {}
local function MoveCastClass(spellID, spellInfo)
    if not spellID then return nil end
    local cached = moveCastClassCache[spellID]
    if cached ~= nil then return cached end
    local SDB = LibStub("JustAC-SpellDB", true)
    if SDB and SDB.IsChanneled and SDB.IsChanneled(spellID) then
        moveCastClassCache[spellID] = "channel"
        return "channel"
    end
    local ct = spellInfo and spellInfo.castTime
    if ct == nil then return nil end               -- no info yet; retry next render
    if issecretvalue and issecretvalue(ct) then return "hardcast" end  -- unreadable; proc-gate it
    local class = (ct == 0) and "instant" or "hardcast"
    moveCastClassCache[spellID] = class
    return class
end

-- A hardcast is castable while moving only while a proc has made it instant. Reuse
-- Blizzard's spell-activation overlay (the same "proc ready" cue that glows the
-- icon) as the live signal. Fail-safe: any error / secret -> not proc'd (no mark),
-- never a wrong "cast while moving" claim.
local function IsSpellProcActive(spellID)
    if not (spellID and C_SpellActivationOverlay_IsSpellOverlayed) then return false end
    local ok, overlayed = pcall(C_SpellActivationOverlay_IsSpellOverlayed, spellID)
    if not ok then return false end
    if issecretvalue and issecretvalue(overlayed) then return false end
    return overlayed == true
end

--- True if the spell can be cast while moving right now (for the queue marker).
local function IsMoveCastableNow(spellID, spellInfo)
    local class = MoveCastClass(spellID, spellInfo)
    if class == "instant" then return true end
    if class == "hardcast" then return IsSpellProcActive(spellID) end
    return false  -- "channel" / nil
end

--- Move-cast marker setting: the explicit profile toggle, or the per-spec auto default
--- (ranged DPS / healers on, melee off) when the player has never set it. Shared so the
--- defensive path resolves the default identically to the queue's ctx builder.
local function MoveCastDotEnabled(profile)
    local v = profile and profile.showMoveCastDot
    if v ~= nil then return v end
    local SDB = LibStub("JustAC-SpellDB", true)
    return (SDB and SDB.IsRangedOrHealerSpec and SDB.IsRangedOrHealerSpec()) or false
end

-- Cue-dot colours. FULLY SATURATED on purpose: this is a small solid disc drawn over arbitrary
-- spell art, so maximum chroma is what keeps it findable (unlike a glow tint, where full chroma
-- flattens the flipbook). Azure and amber differ in hue AND brightness, so the split disc stays
-- readable at icon size and for colour-blind players.
local CUE_MOVECAST = { r = 0.10, g = 0.80, b = 1.00 }   -- azure: movement
local CUE_OFFGCD   = { r = 1.00, g = 0.72, b = 0.10 }   -- amber: free cast

--- Paint the shared cue dot. Shared by the defensive and queue paths so a cue means the same
--- thing on every surface. Colours are only re-applied when the ACTIVE SET changes, so the
--- pulse animation is never restarted mid-flight by a redundant repaint.
local function ApplyCueDot(icon, moveCast, offGcd)
    local dot = icon and icon.cueDot
    if not dot then return end
    moveCast, offGcd = moveCast and true or false, offGcd and true or false

    local key = (moveCast and "M" or "") .. (offGcd and "G" or "")
    if key == icon._cueDotKey then return end
    icon._cueDotKey = key

    if key == "" then
        dot:Hide()
        return
    end

    -- Fixed order (move-cast left, off-GCD right); with one cue both halves take the same
    -- colour, so it reads as a solid dot.
    local a = moveCast and CUE_MOVECAST or CUE_OFFGCD
    local b = offGcd and CUE_OFFGCD or CUE_MOVECAST
    -- Additive stacking is what makes the fill read neon rather than as a tinted grey disc.
    for i = 1, #dot.leftLayers do dot.leftLayers[i]:SetVertexColor(a.r, a.g, a.b, 1) end
    for i = 1, #dot.rightLayers do dot.rightLayers[i]:SetVertexColor(b.r, b.g, b.b, 1) end
    -- Halo takes the first colour; a single-hue halo behind a split disc beats a gradient.
    dot.glowTex:SetVertexColor(a.r, a.g, a.b, 0.75)
    dot:Show()
end

-- Blue: "this mitigation has lapsed, put it back up". The flipbook base is gold and gets
-- desaturated before tinting, so the value has to be vivid to survive as a recognisable
-- blue rather than washing out grey.
local MAINTENANCE_GLOW = { r = 0.55, g = 0.78, b = 1.00 }

-- Orange: "the target is in execute range, this is the button". Health is SECRET in combat, so
-- this can never be a branch - the glow frame is SHOWN and its alpha handed to the engine via
-- the health curve, exactly as the enrage cue hands over its dispel-type alpha. We never learn
-- whether the target is low; the engine decides whether the glow is visible.
-- DISPLAY ONLY, by construction: a secret cannot be compared, so this can never promote the
-- spell up the queue. SpellQueue's ctxExecute keeps its own branchable inference (AC
-- recommending an execute-gated spell at position 1) for the ranking job - the two are
-- deliberately separate, and this one is the direct read the other can only infer.
local EXECUTE_GLOW = { r = 1.00, g = 0.45, b = 0.10 }
local EXECUTE_GLOW_KEY = "ExecuteGlowFrame"

-- Pet-heal cue threshold, as a 0-1 fraction. User-configurable (Defensives -> Sustain); 50 is
-- the default because it matches what the out-of-combat path used before this moved to the
-- Sustain slot, so an untouched profile behaves exactly as it did.
-- The value IS the curve's step point, and SetAlphaFromHealthBelow caches one curve per
-- distinct fraction - which is why the slider steps in 5s rather than being continuous.
local PET_HEAL_DEFAULT_PCT = 50
local function PetHealFraction(profile)
    local pct = profile and profile.petHealThreshold
    if type(pct) ~= "number" then pct = PET_HEAL_DEFAULT_PCT end
    return pct / 100
end

-- Health top-off bands. BOTH of the precombat heal's tiers in one curve, because the alpha it
-- returns is secret and cannot be compared - so the tiers cannot be an `if`. Graded alpha does
-- the job instead: the DIMMING is what distinguishes "top off between pulls" from "you are about
-- to die", with no branch anywhere.
--   below 35%  - emergency, full brightness. Matches PrecombatEngine's LOW_HEALTH_PCT.
--   35% - 90%  - the opt-in top-off nudge, dimmed. Matches RECUPERATE_HEALTH_PCT.
--   above 90%  - invisible.
-- This is what stops the open-world nag at 99%: out of combat health is secret there, so the
-- engine's arming signal (regen is running) can only prove below FULL. The curve is the only
-- thing that can honour 90% outside a rested area.
-- The upper band is user-configurable; the emergency band is NOT, deliberately - it is the
-- "you are about to die" tier and must not be reachable by a slider that could switch it off.
-- One cached points table per threshold, so SetAlphaFromHealthCurve's identity caching holds.
local TOPOFF_EMERGENCY_FRACTION = 0.35
local TOPOFF_DEFAULT_PCT = 90
local topoffBands = {}
local function TopoffBands(profile)
    local pb = profile and profile.precombatBuffs
    local pct = pb and pb.topoffThreshold
    if type(pct) ~= "number" then pct = TOPOFF_DEFAULT_PCT end
    -- Clamp above the emergency band: the option's own min is 50, but a hand-edited saved
    -- variable must not produce out-of-order curve points.
    if pct < 40 then pct = 40 end
    local bands = topoffBands[pct]
    if not bands then
        bands = { {0, 1.0}, {TOPOFF_EMERGENCY_FRACTION, 0.55}, {pct / 100, 0} }
        topoffBands[pct] = bands
    end
    return bands
end

local function ClearExecuteCue(icon)
    if not icon._executeCue then return end
    UIAnimations.HideColoredProcGlow(icon, EXECUTE_GLOW_KEY)
    icon._executeCue = false
end

--- Light the execute cue on an icon showing an HP-gated finisher, while a hostile target is
--- below the execute threshold. No-op for every other spell.
local function ApplyExecuteCue(icon, spellID)
    local isExecute = spellID and SpellDB and SpellDB.GetGate
        and SpellDB.GetGate(spellID) == "execute"
    if not (isExecute and UnitExists("target") and UnitCanAttack("player", "target")) then
        ClearExecuteCue(icon)
        return
    end
    UIAnimations.ShowColoredProcGlow(icon, EXECUTE_GLOW_KEY,
        EXECUTE_GLOW.r, EXECUTE_GLOW.g, EXECUTE_GLOW.b)
    icon._executeCue = true
    -- ShowColoredProcGlow leaves the frame at alpha 1; the curve immediately overrides that,
    -- so the glow is only actually visible inside execute range.
    local glow = icon[EXECUTE_GLOW_KEY]
    if not (glow and UIFrameFactory.SetAlphaFromHealthBelow(glow, "target",
            UIFrameFactory.EXECUTE_FRACTION)) then
        -- Technique unavailable on this build: hide it rather than leave a glow stuck on,
        -- which would tell the player "execute now" for the whole fight.
        ClearExecuteCue(icon)
    end
end

-- Single teardown for the maintenance slot: three call sites (inactive slot, main-panel
-- cluster hide, nameplate cluster hide) each used to clear a different subset.
local function ClearMaintenanceSlot(icon)
    if not icon then return end
    UIAnimations.HideColoredProcGlow(icon, "maintenanceGlow")
    icon:SetAlpha(0)
    icon._maintShown, icon._maintGlow, icon._maintID, icon.lastVisualState = false, false, nil, nil
    icon.maintenanceAuraID = nil
    if icon.chargeText then icon.chargeText:Hide() end
end
UIRenderer.ClearMaintenanceSlot = ClearMaintenanceSlot

--- Render the defensive maintenance slot ("position 0" of the defensive queue).
--- The split that makes this work: the SWIPE shows the aura's real remaining time, drawn
--- by the engine from a DurationObject we never read, while our own logic only ever sees
--- the up/down/unknown boolean. So the player gets an exact timer for a value that is
--- secret to the addon.
function UIRenderer.RenderMaintenanceSlot(addon, icon)
    if not icon then return end
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    local profile = addon.db and addon.db.profile

    -- Visibility comes from MT.IsSlotActive, the SHARED predicate: the defensive queue builder
    -- excludes this ability using the same call, and if the two disagreed you would get the
    -- icon twice or an ability that vanished from both. Combat-only, and that gates the DISPLAY
    -- only - the tracker keeps binding the aura out of combat, so the slot has a correct timer
    -- from the first second of a pull instead of an empty swipe that fills in late.
    -- CROWD-CONTROL ESCAPE. This is not a sub-feature of upkeep - it is the frame's OTHER use,
    -- and it can claim the slot on its own. Any spec can be held, so it does not require a
    -- maintenance entry or even a tank spec; a caster with upkeep disabled still gets it.
    -- Resolved FIRST because being stunned outranks any upkeep decision, and because the slot
    -- may be live for this reason alone (entry will be nil then).
    -- Offered only when there is something to PRESS: with no counter ready the slot falls back
    -- to upkeep rather than spending itself telling the player they are stuck.
    -- Nothing here is secret - C_LossOfControl reads plain in combat - so unlike the aura path
    -- there is no identity gate, no estimate and no unknown state.
    local ccSpellID, ccDurObj
    local ccMacro
    if profile and profile.showCCBreak and MT then
        if MT.GetCCBreak then
            local sid, _, durObj = MT.GetCCBreak()
            ccSpellID, ccDurObj = sid, durObj
        end
        -- Macro escape is the fallback for root/snare/slow, where a real breaker spell often
        -- does not exist - prefer a spell breaker when one is ready (it does not drop a druid's
        -- form), else fall back to the player's /cancelform macro.
        if not ccSpellID and MT.GetCCBreakMacro then
            local name, durObj = MT.GetCCBreakMacro(profile)
            if name then ccMacro, ccDurObj = name, durObj end
        end
    end

    -- MACRO ESCAPE render: fully self-contained, because a macro has no spellID and every spell
    -- API below (usability, charges, range, GetSpellHotkey) would be wrong for it. Icon + key
    -- come from macro APIs, the swipe is the CC's remaining time, and it always glows - it is
    -- only ever offered while the player is actually held.
    if ccMacro then
        local mIcon = select(2, GetMacroInfo(ccMacro))
        local key = ActionBarScanner and ActionBarScanner.GetMacroHotkey
            and ActionBarScanner.GetMacroHotkey(ccMacro) or ""
        -- No bound slot => no key to press => the escape is not actionable, so show nothing
        -- rather than an unpressable icon. The option UI warns about this case.
        if not mIcon or key == "" then
            if icon._maintShown then ClearMaintenanceSlot(icon) end
            return
        end
        SetDefensiveIconVisible(icon, true)
        icon:SetAlpha(icon.overlayOpacity or 1)
        icon._maintShown = true
        icon._maintID = nil                 -- spell-path change detection must re-fire after this
        -- itemID with the rest: leaving it behind is a stale identity waiting for the first
        -- reader that trusts it on its own rather than checking isItem first.
        icon.spellID, icon.isItem, icon.itemID = nil, false, nil
        icon.maintenanceAuraID = nil
        icon.iconTexture:SetTexture(mIcon)
        icon.iconTexture:Show()
        icon.iconTexture:SetDesaturation(0)
        if icon.cooldown then
            if ccDurObj and icon.cooldown.SetCooldownFromDurationObject then
                pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, ccDurObj)
            else
                icon.cooldown:SetCooldown(0, 0)
            end
        end
        if icon.chargeText then icon.chargeText:Hide() end
        local to = profile.textOverlays
        local showHotkeys = not to or not to.hotkey or to.hotkey.show ~= false
        icon.cachedHotkey = key
        SetIconHotkeyText(icon, key, showHotkeys)
        if not icon._maintGlow then
            UIAnimations.ShowColoredProcGlow(icon, "maintenanceGlow",
                MAINTENANCE_GLOW.r, MAINTENANCE_GLOW.g, MAINTENANCE_GLOW.b)
            icon._maintGlow = true
        end
        return
    end

    -- PET HEAL, the Sustain slot's third claimant. Pet health is SECRET in combat, so unlike
    -- upkeep and CC escape this one can never be decided by us: the icon is shown unconditionally
    -- while a live pet exists, and its ALPHA is handed to the engine keyed on the pet's health
    -- fraction. We never learn whether the pet is hurt.
    --
    -- Ranked lists cannot hold a secret (ordering needs a comparison), which is exactly why this
    -- moved out of the defensive queue and into a slot of its own.
    --
    -- Priority: CC escape outranks it, and that arbitration is only possible because CC escape is
    -- the PLAIN claimant - a normal `if` suppresses the secret layer. It would be unsolvable the
    -- other way round. Upkeep never collides: pet-heal classes (Hunter, Warlock) have no tank
    -- spec, so the slot is otherwise dead space for them.
    local petSpellID
    if not ccSpellID and profile and profile.showPetHealCue ~= false
       and profile.defensives and profile.defensives.enabled
       and UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
        local DE = LibStub("JustAC-DefensiveEngine", true)
        local getList = DE and DE.GetClassSpellList
        local list = getList and getList(addon, "petHealSpells")
        -- Skip any pet heal that is ALSO in the player's own defensive list - Exhilaration is
        -- the only one today (it heals hunter and pet), and the queue is already showing it.
        -- Two identical icons on two surfaces is worse than one, and the queue is the right
        -- home for it: unlike the tank maintenance buff, this is a genuine personal defensive,
        -- so excluding it from the QUEUE instead would delete a hunter's main self-heal for as
        -- long as a pet is out. Nothing is lost here - the button is still on screen.
        -- Linear scan, no table build: both lists are tiny and this runs every render tick.
        local ownList = getList and getList(addon, "defensiveSpells")
        for i = 1, (list and #list or 0) do
            local sid = list[i]
            local dual = false
            for j = 1, (ownList and #ownList or 0) do
                if ownList[j] == sid then dual = true break end
            end
            if sid and sid > 0 and not dual
               and BlizzardAPI.CheckDefensiveSpellState(sid, profile) then
                petSpellID = sid
                break
            end
        end
    end

    local active, entry = false, nil
    if MT and MT.IsSlotActive then active, entry = MT.IsSlotActive(profile) end
    -- A pet-heal claim makes the slot live on its own, exactly as CC escape does.
    if petSpellID then active = true end
    local state, inst = "none", nil
    -- Plain assignment, NOT `local` - shadowing `state` here silently kills the glow.
    if active and entry and MT and MT.GetState then state, _, inst = MT.GetState() end

    -- Live if EITHER use has something to show. `entry` may legitimately be nil (CC escape with
    -- no maintenance buff), so it can no longer gate the whole slot.
    if not active or (not entry and not ccSpellID and not petSpellID) then
        -- Guard the common case: this runs every render tick and inactive is the norm.
        if icon._maintShown then ClearMaintenanceSlot(icon) end
        return
    end

    -- No `or entry.aura` fallback: a future cast-less entry must fail loudly rather than run
    -- range and usability checks against an aura id.
    local displayID = ccSpellID or petSpellID or entry.cast

    -- Icon art only changes on a spec change, so refresh it on transition.
    if icon._maintID ~= displayID then
        icon._maintID = displayID
        icon.spellID = displayID
        icon.currentID = displayID
        icon.isItem = false
        -- Tooltip names the buff this cast maintains, when it is a different spell. Nil in the
        -- CC-escape case: `entry` may not exist at all there, and the tooltip should describe
        -- the escape ability itself rather than an unrelated maintenance buff.
        icon.maintenanceAuraID = (entry and entry.aura ~= displayID) and entry.aura or nil
        local info = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(displayID)
        if info and info.iconID then
            icon.iconTexture:SetTexture(info.iconID)
            icon.iconTexture:Show()
        end
        icon.cachedHotkey = nil
    end

    SetDefensiveIconVisible(icon, true)
    icon:SetAlpha(icon.overlayOpacity or 1)
    icon._maintShown = true

    -- Pet-heal claim: hand the alpha we just set straight over to the engine, keyed on the pet's
    -- health. SHOWN at whatever alpha the curve returns - never hidden, because a hidden frame
    -- draws nothing regardless of alpha (the bug that silently killed the enrage cue for weeks).
    -- If the technique is unavailable on this build the icon simply stays visible at the opacity
    -- above, which is the old out-of-combat behaviour and a safe fallback.
    if petSpellID then
        UIFrameFactory.SetAlphaFromHealthBelow(icon, "pet", PetHealFraction(profile))
    end

    -- TWO fundamentally different kinds of maintenance button, and they want different data:
    --
    --   chargeGated (Shield Block, Demon Spikes) - you track the ABILITY. Uptime is capped by
    --     recharge, so what matters is "have I got a charge, and when does the next one land".
    --     The buff is a consequence of pressing, not the thing being managed. Show the
    --     ability's recharge swipe and its CHARGE count.
    --
    --   otherwise (Ironfur, Bone Shield, Ignore Pain, Shield of the Righteous) - you track the
    --     BUFF. The button is limited by RESOURCE generation, not recharge, so it can be held
    --     up; what matters is whether the buff is still on you and how strong. Show the aura's
    --     remaining time and its stack count.
    --
    -- Conflating them showed a tank the buff timer on a button whose real constraint was the
    -- charge, which is the wrong question answered precisely.
    local exactBind = MT and MT.IsBindExact and MT.IsBindExact()
    if icon.cooldown then
        local applied = false
        if ccSpellID then
            -- The CC's OWN remaining time, engine-drawn: how long until you're free, which is
            -- the only clock that matters while you cannot act.
            if ccDurObj and icon.cooldown.SetCooldownFromDurationObject then
                pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, ccDurObj)
                applied = true
            end
        elseif petSpellID then
            -- The heal's OWN cooldown (Mend Pet and friends). `entry` is nil on this path -
            -- every branch below reads it, which is why pet heal is handled here rather than
            -- being allowed to fall through.
            if C_Spell and C_Spell.GetSpellCooldownDuration
               and icon.cooldown.SetCooldownFromDurationObject then
                local okD, durObj = pcall(C_Spell.GetSpellCooldownDuration, displayID, false)
                if okD and durObj then
                    pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durObj)
                    applied = true
                end
            end
        elseif entry.chargeGated then
            -- The ability's own recharge. Secret-safe: the DurationObject goes straight to the
            -- engine, never read. `false` = include the GCD, so a fresh press reads as busy.
            if C_Spell and C_Spell.GetSpellCooldownDuration
               and icon.cooldown.SetCooldownFromDurationObject then
                local okD, durObj = pcall(C_Spell.GetSpellCooldownDuration, displayID, false)
                if okD and durObj then
                    pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durObj)
                    applied = true
                end
            end
        else
            -- The aura's remaining time, in descending order of trust:
            --   1. exact bind -> the aura's real DurationObject, engine-drawn, never read.
            --      SKIPPED for stacking projected entries: an exact instance is still only ONE
            --      stack, so its timer hops as stacks expire - the exact bug the projection
            --      exists to fix. Our own clock is worse in precision and better in meaning.
            --   2. anything but a confirmed "down" -> our own cast clock. Keyed on STATE, not on
            --      holding an instance: a successful cast already tells us the buff started and
            --      how long it lasts, and neither fact needs an aura binding. Note this is
            --      deliberately OUR numbers, never the bound instance's - drawing that would
            --      render a foreign timer (a 20s proc on a 7s buff) whenever the bind is wrong.
            --   3. confirmed "down" -> nothing. Telling a tank they are covered when they are
            --      not is actionable misinformation, and every "down" verdict comes from a
            --      source more authoritative than our own clock.
            -- "unknown" is included on purpose: it means we never saw it drop, not that it is
            -- gone. An expired estimate draws nothing anyway, so a stale clock is self-limiting.
            local preferProjection = entry.project and entry.stacks
            local durObj = (not preferProjection) and exactBind and MT and MT.GetDurationObject
                           and MT.GetDurationObject(inst) or nil
            if durObj and icon.cooldown.SetCooldownFromDurationObject then
                pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durObj)
                applied = true
            elseif (state == "up" or state == "refresh" or state == "unknown")
                   and MT and MT.GetEstimatedCooldown then
                local st, len = MT.GetEstimatedCooldown(entry)
                if st and len then
                    icon.cooldown:SetCooldown(st, len)   -- plain numbers, no secret
                    applied = true
                end
            end
        end
        if not applied then icon.cooldown:SetCooldown(0, 0) end
    end

    -- Stack count, gated on an IDENTITY-EXACT bind. The number itself is never read: the engine
    -- renders it from the instance id, and the 3rd arg is an engine-side "only show if >= 2"
    -- threshold, so there is no comparison in Lua either. Correctness therefore rests entirely
    -- on having the RIGHT instance - which the cast->instance bridge cannot prove, since spellId
    -- is secret (see Documentation/AURA_IDENTITY_12.0.md). So: render only on a by-spell-id
    -- bind, hide on a bridge guess. Right or absent, never wrong - a mis-drawn mitigation count
    -- is actionable misinformation for a tank. An exact bind made out of combat survives into
    -- the fight across refreshes, so this is not a dead branch.
    -- SetText marks this FontString's Text aspect secret PERMANENTLY - keep it off any
    -- width-measured layout path. Nothing here measures it.
    if icon.chargeText then
        local shown = false
        if ccSpellID or petSpellID then
            shown = false   -- neither an escape button nor a pet heal has a meaningful count
        elseif entry.chargeGated then
            -- CHARGES, not aura stacks. maxCharges is NeverSecret so it is safe to compare;
            -- currentCharges is SECRET in combat, so it goes straight to SetText and the engine
            -- renders it - same pass-through rule as everywhere else. No identity gate needed:
            -- this reads the ABILITY by spell id, which was never ambiguous.
            if C_Spell and C_Spell.GetSpellCharges then
                local okC, ci = pcall(C_Spell.GetSpellCharges, displayID)
                if okC and ci and type(ci.maxCharges) == "number" and ci.maxCharges > 1 then
                    local okT = pcall(icon.chargeText.SetText, icon.chargeText, ci.currentCharges)
                    if okT then icon.chargeText:Show() shown = true end
                end
            end
        elseif entry.project and entry.stacks and MT and MT.GetProjectedStacks then
            -- Projected stacks: one per unexpired cast of ours. A PLAIN number we computed, so
            -- unlike the engine path it needs no instance and no identity proof - the count is
            -- exact as long as the casts landed, which for a self-buff that cannot miss is
            -- always. Same ">= 2" threshold as the engine path so a single stack stays quiet.
            local okN, n = pcall(MT.GetProjectedStacks, entry)
            if okN and type(n) == "number" and n >= 2 then
                icon.chargeText:SetText(n)
                icon.chargeText:Show()
                shown = true
            end
        elseif entry.stacks then
            -- Aura stacks, gated on a PROVEN bind: the engine renders the true count, but only
            -- off the right instance. The 3rd arg is an engine-side "only show if >= 2".
            local fn = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
            -- Reuse exactBind from above: same entry, same frame, same answer.
            if exactBind and fn and inst then
                local ok, text = pcall(fn, "player", inst, 2)
                if ok and text then
                    icon.chargeText:SetText(text)
                    icon.chargeText:Show()
                    shown = true
                end
            end
        end
        if not shown then icon.chargeText:Hide() end
    end

    -- Usability goes through the SHARED ApplyVisualState. IsSpellUsable is never-secret, so it
    -- reads fine in combat. Desaturation therefore means what it means everywhere else - "you
    -- cannot press this" - and is NOT reused for "the buff lapsed"; the glow carries that.
    -- Read once: it drives both the visual state and whether the glow may fire.
    local usable, noResource = true, false
    if BlizzardAPI and BlizzardAPI.IsSpellUsable then
        usable, noResource = BlizzardAPI.IsSpellUsable(displayID)
    end
    local vs = VS_NORMAL
    if not usable then
        vs = noResource and VS_NO_RESOURCES or VS_UNAVAILABLE
    end
    ApplyVisualState(icon, vs, 0, 1, 1)

    -- Hotkey + range colouring, so a rotational button in this slot (Blood's Marrowrend)
    -- still tells the player whether they can actually reach and afford it.
    -- Same polarity as every other surface: a MISSING textOverlays table means "not configured",
    -- which defaults to SHOW. The inverted form (`overlays and overlays.hotkey and ...`) read
    -- naturally but defaulted this one slot to HIDE, so a profile without the table would have
    -- lost its keybind here alone. AceDB supplies a default today, which is the only reason that
    -- never surfaced - do not "simplify" this back.
    local to = profile.textOverlays
    local showHotkeys = not to or not to.hotkey or to.hotkey.show ~= false
    if not icon.cachedHotkey then
        icon.cachedHotkey = (ActionBarScanner and ActionBarScanner.GetSpellHotkey
            and ActionBarScanner.GetSpellHotkey(displayID)) or ""
    end
    SetIconHotkeyText(icon, icon.cachedHotkey, showHotkeys)
    if showHotkeys and icon.cachedHotkey ~= "" then
        local outOfRange = CheckSpellRange(icon, displayID, nil)
        UpdateRangeHotkeyColor(icon, outOfRange,
            profile.textOverlays and profile.textOverlays.hotkey and profile.textOverlays.hotkey.color)
    end

    -- ONE cue: the proc burst, raised at the refresh threshold (~3s before decay) and held if
    -- the buff actually lapses. A two-stage version was tried - marching-ants crawl for
    -- "refresh", burst for "down" - and rejected in play: the crawl is too faint to register
    -- mid-pull, which defeats the point of a cue you must catch at a glance. Do not reintroduce
    -- a low-contrast stage here; if "soon" and "gone" ever need distinguishing, find a
    -- difference that survives a busy screen.
    -- Never on "unknown": that state means we could not identify the aura, and glowing there
    -- tells a tank to re-press a buff that may well be live.
    -- Gated on usable AND ready. `usable` alone is NOT enough: C_Spell.IsSpellUsable reports
    -- resources and state, never cooldown, so a charge-gated button with every charge spent
    -- still reads usable and we would cue a press that cannot happen.
    -- Use IsSpellReady, not IsSpellOnCooldown: it is charge-aware, treating a spell with a
    -- banked charge as ready even while another recharges. IsSpellOnCooldown would call that
    -- recharge "on cooldown" and kill the glow on a Shield Block you can press right now.
    local ready = true
    if BlizzardAPI and BlizzardAPI.IsSpellReady then
        ready = BlizzardAPI.IsSpellReady(displayID) and true or false
    end
    -- A CC break always glows: it is only ever offered when the player is actually held AND
    -- owns a counter that is ready, so there is no state in which showing it quietly is right.
    -- Pet heal glows like the escape does, and for the same reason: it is only ever resolved
    -- when the spell is actually usable, so there is no "glowing at a button you can't press"
    -- case to guard. Safe despite the secret gate because frame alpha cascades to children -
    -- with the icon at alpha 0 the glow is invisible too, so it can only appear once the engine
    -- has decided the pet is actually hurt.
    local wantGlow = (ccSpellID or petSpellID) and true
        or ((state == "down" or state == "refresh") and usable and ready)

    -- Marker cues, same rules as the other surfaces. Off-GCD is the valuable one here:
    -- Ignore Pain and Shield of the Righteous are off the global, so topping up your
    -- mitigation costs nothing from the rotation - exactly the call this slot exists to
    -- prompt. Always a spell, never an item or placeholder, so no markable gate is needed.
    ApplyCueDot(icon,
        MoveCastDotEnabled(profile) and IsMoveCastableNow(displayID, nil),
        profile and profile.showOffGcdDot and IsOffGCDSpell(displayID))
    if wantGlow ~= icon._maintGlow then
        if wantGlow then
            UIAnimations.ShowColoredProcGlow(icon, "maintenanceGlow",
                MAINTENANCE_GLOW.r, MAINTENANCE_GLOW.g, MAINTENANCE_GLOW.b)
        else
            UIAnimations.HideColoredProcGlow(icon, "maintenanceGlow")
        end
        icon._maintGlow = wantGlow
    end
end

-- glowModeOverride: overrides profile.defensives.glowMode (overlay has its own setting).
-- waiting: held-back emergency heal (above low-health threshold) - render desaturated
-- with a centered WAIT tag and no glow, instead of showing it as a live suggestion.
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon, showGlow, glowModeOverride, showHotkeysOverride, showFlashOverride, waiting, isPrecombatEntry)
    if not addon or not id or not defensiveIcon then return end
    
    local iconTexture
    -- Hoisted: the move-cast marker below needs spellInfo.castTime, not just the icon.
    local defSpellInfo
    local idChanged = (defensiveIcon.currentID ~= id) or (defensiveIcon.isItem ~= isItem)

    -- Clear identity before anything can bail out below. These slots are pooled, so a
    -- bail-out otherwise leaves the icon still claiming its PREVIOUS occupant - and
    -- everything that reads these fields (tooltip, hotkey handler, and the out-of-combat
    -- click layer, which binds a real cast to them) would act on a spell this slot no
    -- longer offers. The success path re-assigns all four a few lines down.
    defensiveIcon.currentID = nil
    defensiveIcon.spellID = nil
    defensiveIcon.itemID = nil
    defensiveIcon.isItem = nil

    if isItem then
        if C_Item and C_Item.GetItemIconByID then
            iconTexture = C_Item.GetItemIconByID(id)
        end
        -- Into a temp, not straight onto iconTexture: GetItemInfo returns nil for an item
        -- the client hasn't cached yet, which would erase the icon GetItemIconByID already
        -- resolved from the ID alone and send us down the bail-out path for nothing.
        local cachedIcon
        if C_Item and C_Item.GetItemInfo then
            _, _, _, _, _, _, _, _, _, cachedIcon = C_Item.GetItemInfo(id)
        elseif GetItemInfo then
            _, _, _, _, _, _, _, _, _, cachedIcon = GetItemInfo(id)
        end
        iconTexture = cachedIcon or iconTexture
        if not iconTexture then
            iconTexture = GetItemIcon and GetItemIcon(id)
        end
        if not iconTexture then return end
    else
        defSpellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(id)
        if not defSpellInfo then return end
        iconTexture = defSpellInfo.iconID
    end
    
    defensiveIcon.currentID = id
    defensiveIcon.spellID = not isItem and id or nil
    defensiveIcon.itemID = isItem and id or nil
    defensiveIcon.isItem = isItem
    
    defensiveIcon.itemCastSpellID = nil
    if isItem then
        local _, spellID = GetItemSpell(id)
        defensiveIcon.itemCastSpellID = spellID
    end

    -- Marker cues, same rules as the offensive queue: spells only (items follow a separate
    -- use path) and never on a waiting / pre-combat placeholder.
    --   off-GCD  - defensives are where this matters most: Shield of the Righteous, Rune Tap
    --              and friends are off the global, so firing one costs no rotation cast.
    --   move-cast - a defensive you can use while repositioning is exactly the one you want
    --              when the fight is making you run, so it belongs here as much as on the queue.
    -- Re-evaluated every render because proc state is live, unlike the static off-GCD data.
    local profile = addon.db and addon.db.profile
    local markable = not isItem and not waiting and not isPrecombatEntry
    ApplyCueDot(defensiveIcon,
        markable and MoveCastDotEnabled(profile) and IsMoveCastableNow(id, defSpellInfo),
        markable and profile and profile.showOffGcdDot and IsOffGCDSpell(id))
    
    if idChanged then
        defensiveIcon.iconTexture:SetTexture(iconTexture)
        defensiveIcon.iconTexture:Show()
        defensiveIcon.iconTexture:SetDesaturation(0)
        defensiveIcon.iconTexture:SetVertexColor(1, 1, 1, 1)
        defensiveIcon.cachedDefUsable = nil
        defensiveIcon.cachedDefNoResource = nil
        defensiveIcon.lastDefVisualState = nil
    end
    
    UpdateButtonCooldowns(defensiveIcon)

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
            hotkey = ActionBarScanner and ActionBarScanner.GetItemHotkey and ActionBarScanner.GetItemHotkey(id, defensiveIcon.itemCastSpellID) or ""
        else
            hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(id) or ""
        end
    end
    
    -- When showHotkeys is off, keep normalized hotkey for flash matching.
    SetIconHotkeyText(defensiveIcon, hotkey, showHotkeys)
    SetIconNormalizedHotkey(defensiveIcon, hotkey, GetTime(), true)

    defensiveIcon.isWaiting = waiting or nil
    if defensiveIcon.centerText then
        if waiting then
            defensiveIcon.centerText:SetText(WAIT_LABEL)
            defensiveIcon.centerText:Show()
        else
            defensiveIcon.centerText:Hide()
        end
    end

    UIRenderer.UpdateDefensiveVisualState(defensiveIcon, idChanged)

    local defGlowMode = glowModeOverride
        or (addon.db and addon.db.profile and addon.db.profile.defensives and addon.db.profile.defensives.glowMode)
        or "all"

    defensiveIcon.defGlowMode = defGlowMode
    defensiveIcon.defShowGlow = showGlow

    local procCheckID = isItem and defensiveIcon.itemCastSpellID or id
    local isProc = procCheckID and IsSpellProcced(procCheckID) or false

    -- Inserted pre-combat buffs get their own vivid-green glow (out of combat) so they read
    -- as distinct, important "use me" icons rather than ordinary defensive suggestions.
    -- Keyed on entry PROVENANCE (the queue entry's precombat flag), never on spell
    -- identity: dual-role spells (Regrowth is both a defensive-list entry and an OOC
    -- top-off offer) must only glow green when suggested BY the pre-combat system.
    local isBuff = (not isInCombat and isPrecombatEntry) or false
    defensiveIcon.isPrecombatBuff = isBuff or nil  -- click-overlay reads this for its "click" hint
    -- Unified glow arbitration (proc > green > marching > none). idChanged
    -- applies immediately - a new spell in the slot deserves its correct glow
    -- now; same-spell transitions ride the settle-time debounce.
    ApplyDefensiveGlow(defensiveIcon,
        ComputeDefensiveGlowState(defensiveIcon, isProc), isInCombat, idChanged)
    
    -- Per-icon fades are disabled everywhere; appear instantly. Nameplate callers set
    -- their overlay opacity right after this returns (overriding the alpha 1 below).
    SetDefensiveIconVisible(defensiveIcon, true)
end

-- keepSlot: when true, clear the icon's spell content but leave the button shown as
-- an empty placeholder slot (SlotBackground + border), mirroring the DPS queue. Used
-- to pad the defensive cluster up to maxIcons instead of collapsing it.
function UIRenderer.HideDefensiveIcon(defensiveIcon, keepSlot)
    if not defensiveIcon then return end

    if defensiveIcon:IsShown() or defensiveIcon.currentID then
        UIAnimations.StopDefensiveGlow(defensiveIcon)
        UIAnimations.StopPrecombatGlow(defensiveIcon)
        UIAnimations.HideProcGlow(defensiveIcon)
        defensiveIcon.appliedDefGlowState = nil
        defensiveIcon.pendingDefGlowState = nil
        defensiveIcon.spellID = nil
        defensiveIcon.itemID = nil
        defensiveIcon.itemCastSpellID = nil
        defensiveIcon.currentID = nil
        defensiveIcon.isItem = nil
        defensiveIcon.isPrecombatBuff = nil
        defensiveIcon.isWaiting = nil
        -- Clear both markers with the rest of the slot state, or a pooled icon reused for
        -- an on-GCD / non-move-castable spell keeps a stale cue.
        ApplyCueDot(defensiveIcon, false, false)
        if defensiveIcon.centerText then defensiveIcon.centerText:Hide() end
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

        -- Per-icon fades are disabled everywhere; show/hide instantly. Never call the
        -- protected frame Hide()/Show() here (see SetDefensiveIconVisible): alpha 0 hides.
        SetDefensiveIconVisible(defensiveIcon, keepSlot)
    elseif keepSlot then
        -- Already-empty icon: surface it as a placeholder slot.
        defensiveIcon.iconTexture:Hide()
        SetDefensiveIconVisible(defensiveIcon, true)
    end
end

function UIRenderer.ShowDefensiveIcons(addon, queue)
    if not addon or not addon.defensiveIcons then return end

    local icons = addon.defensiveIcons
    local anyVisible = false

    -- When at least one defensive is suggested, pad the remaining positions with empty
    -- placeholder slots (up to maxIcons) so the cluster keeps a consistent width like the
    -- DPS queue, instead of collapsing. When nothing is suggested, hide the slots entirely
    -- (the whole cluster fades out below).
    local hasReal = #queue > 0

    for i, icon in ipairs(icons) do
        local entry = queue[i]
        if entry and entry.spellID then
            local showGlow = (i == 1)
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, showGlow, nil, nil, nil, entry.waiting, entry.precombat)
            -- Health top-off: hand the alpha ShowDefensiveIcon just set straight to the engine.
            -- Must come AFTER it, since that call sets alpha itself.
            if entry.topoff then
                UIFrameFactory.SetAlphaFromHealthCurve(icon, "player",
                    TopoffBands(addon.db and addon.db.profile), true)
            end
            anyVisible = true
        else
            UIRenderer.HideDefensiveIcon(icon, hasReal)
        end
    end

    -- Show/hide the detached container frame on state transitions only.
    -- Guarding on IsShown() prevents restarting the fade animation every tick.
    if addon.defensiveFrame then
        if anyVisible then
            if not addon.defensiveFrame:IsShown() then
                if addon.defensiveFrame.fadeOut then addon.defensiveFrame.fadeOut:Stop() end
                addon.defensiveFrame:Show()
                if addon.defensiveFrame.fadeIn then addon.defensiveFrame.fadeIn:Play() end
            end
        else
            if addon.defensiveFrame:IsShown() then
                if addon.defensiveFrame.fadeIn then addon.defensiveFrame.fadeIn:Stop() end
                if addon.defensiveFrame.fadeOut then
                    addon.defensiveFrame.fadeOut:Play()
                else
                    addon.defensiveFrame:Hide()
                end
            end
        end
    end

    -- Maintenance slot rides with the defensive cluster: same pass, same visibility rules.
    UIRenderer.RenderMaintenanceSlot(addon, addon.maintenanceIcon)

    -- Re-seat the out-of-combat click layers over any inserted pre-combat buff icons.
    local PrecombatOverlay = LibStub("JustAC-PrecombatOverlay", true)
    if PrecombatOverlay and PrecombatOverlay.Refresh then PrecombatOverlay.Refresh() end
end

function UIRenderer.HideDefensiveIcons(addon)
    if not addon or not addon.defensiveIcons then return end

    for _, icon in ipairs(addon.defensiveIcons) do
        UIRenderer.HideDefensiveIcon(icon)
    end

    -- The maintenance slot hides with the cluster it belongs to - otherwise it would hang
    -- there alone in vehicle/possess mode with a stale timer.
    ClearMaintenanceSlot(addon.maintenanceIcon)

    -- Tell the click overlay the icons are gone. Without this the secure layers stay
    -- shown and armed over slots that no longer exist, so a click on empty space fires
    -- whatever was last suggested there.
    local PrecombatOverlay = LibStub("JustAC-PrecombatOverlay", true)
    if PrecombatOverlay and PrecombatOverlay.Refresh then PrecombatOverlay.Refresh() end

    -- Hide the detached container frame (covers vehicle/possess mode).
    if addon.defensiveFrame and addon.defensiveFrame:IsShown() then
        if addon.defensiveFrame.fadeIn then addon.defensiveFrame.fadeIn:Stop() end
        if addon.defensiveFrame.fadeOut then
            addon.defensiveFrame.fadeOut:Play()
        else
            addon.defensiveFrame:Hide()
        end
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
        UIAnimations.HideInterruptProcGlow(intIcon)
        UIAnimations.HideInterruptCastBar(intIcon)
        if intIcon.hasProcGlow then UIAnimations.HideProcGlow(intIcon); intIcon.hasProcGlow = false end
        intIcon.hasInterruptGlow = false
    end
    if intIcon.castAura then
        intIcon.castAura:Hide()
    end
    intIcon:Hide()
end

function UIRenderer.PlayInterruptAlertSound(profile)
    if CastInterruptTracker then CastInterruptTracker.PlayInterruptAlertSound(profile) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared interrupt "position 0" render (standard queue + nameplate overlay):
-- retired-mode remap, shared evaluation/debounce, position-1 de-dup, cooldown/
-- hotkey/range upkeep, cast-aura texture passthrough, GCD grey-out, and the
-- soothe cue armed over the same slot. ctx fields (built once per pass):
--   now, updateCooldowns       pass timing (same meaning as RenderQueueIcon)
--   active                     surface is visible this pass (false hides everything)
--   resolvedInterrupts         ordered interrupt list from SpellDB
--   interruptMode              raw profile value (retired modes remapped here)
--   spellIDs                   queue array for the position-1 de-dup
--   profile                    profile table (interrupt alert sound settings)
--   showHotkeys, hotkeyColor   hotkey display settings
--   opacity                    per-surface icon alpha (nil = 1.0)
--   sootheSpellID              player's enrage-dispel spell (nil = no soothe cue)
-- ─────────────────────────────────────────────────────────────────────────────
function UIRenderer.RenderInterruptSlot(intIcon, ctx)
    if not intIcon then return end

    local interruptMode = ctx.interruptMode or "kickPrefer"
    -- Retired modes in saved data → safe fallback.
    if interruptMode == "importantOnly" then interruptMode = "kickOnly" end
    if interruptMode == "ccShielded" then interruptMode = "kickPrefer" end

    if ctx.resolvedInterrupts and ctx.active and interruptMode ~= "disabled" then
        -- Shared evaluation: both renderers see identical state and share one debounce timer.
        local intResult           = UIRenderer.EvaluateInterrupt(ctx.resolvedInterrupts, interruptMode, ctx.now)
        local shouldShowInterrupt = intResult.shouldShow
        local intSpellID          = intResult.spellID
        local castBar             = intResult.castBar

        -- De-dup: if the interrupt spell is already shown as queue position 1, skip it
        if shouldShowInterrupt and intSpellID and ctx.spellIDs and ctx.spellIDs[1] == intSpellID then
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

            if spellChanged or ctx.updateCooldowns then
                UpdateButtonCooldowns(intIcon)
            end

            if spellChanged or ctx.updateCooldowns or not intIcon.cachedHotkey then
                local hotkey = ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(intSpellID) or ""
                intIcon.cachedHotkey = hotkey
                SetIconHotkeyText(intIcon, hotkey, ctx.showHotkeys)
                SetIconNormalizedHotkey(intIcon, hotkey, nil, false)
            end

            -- Red text = out of interrupt range (per-frame; IsSpellInRange is cheap).
            if ctx.showHotkeys and intIcon.cachedHotkey and intIcon.cachedHotkey ~= "" then
                local isOutOfRange = CheckSpellRange(intIcon, intSpellID, nil)
                UpdateRangeHotkeyColor(intIcon, isOutOfRange, ctx.hotkeyColor)
            end

            -- No channeling grey-out for interrupts: they are urgent actions the
            -- player may want to cancel a channel to use.

            -- Marker cues, same rules as the other surfaces. Both matter here:
            --   off-GCD   - several kicks and CCs are off the global, so you can fire one
            --               without giving up a rotation cast. That is worth knowing on the
            --               most time-critical button on screen.
            --   move-cast - interrupts and CCs frequently need to be used mid-reposition.
            ApplyCueDot(intIcon,
                MoveCastDotEnabled(ctx.profile) and IsMoveCastableNow(intSpellID, nil),
                ctx.profile and ctx.profile.showOffGcdDot and IsOffGCDSpell(intSpellID))

            if not intIcon.hasInterruptGlow then
                UIAnimations.ShowInterruptProcGlow(intIcon)
                intIcon.hasInterruptGlow = true
            end

            -- Secret-aware target cast-progress bar with a kick-zone (engine-driven).
            UIAnimations.ShowInterruptCastBar(intIcon)

            -- Cast aura: cast bar textures can be secret in 12.0 - pass through
            -- unconditionally. No explicit alpha: the aura is a child of the icon
            -- and inherits its opacity; setting it again would double-apply.
            if intIcon.castAura then
                local castIcon = castBar and castBar.Icon
                local castTexture = castIcon and castIcon.GetTexture and castIcon:GetTexture()
                -- API fallback: when third-party addons hide the Blizzard cast bar,
                -- retrieve the cast icon directly from UnitCastingInfo / UnitChannelInfo.
                if not castTexture then
                    local _, _, tex = UnitCastingInfo("target")
                    if not tex then _, _, tex = UnitChannelInfo("target") end
                    -- In 12.0 combat, texture may be secret - still pass through.
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
                UIRenderer.PlayInterruptAlertSound(ctx.profile)
                intIcon:Show()
            end
            local iconOpacity = ctx.opacity or 1.0
            -- Hide a KICK suggestion on a non-interruptible cast via the secret-aware alpha
            -- sink (works under any cast-bar addon; never reads the secret). A CC suggestion
            -- stays visible - CC is the correct call on a non-interruptible cast.
            if SpellDB and SpellDB.IsInterruptTypeSpell and SpellDB.IsInterruptTypeSpell(intSpellID) then
                BlizzardAPI.ApplyInterruptIconAlpha(intIcon, iconOpacity)
            else
                intIcon:SetAlpha(iconOpacity)
            end
            -- Grey the reminder (interrupt or CC) while it's on the GCD; off-GCD
            -- interrupts stay full-color since IsSpellOnGCD is false for them.
            intIcon.iconTexture:SetDesaturation(BlizzardAPI.IsSpellOnGCD(intSpellID) and 1.0 or 0)
        elseif intIcon.spellID or intIcon:IsShown() then
            UIRenderer.HideInterruptIcon(intIcon)
        end
    elseif intIcon.spellID or intIcon:IsShown() then
        UIRenderer.HideInterruptIcon(intIcon)
    end

    -- Soothe (enrage-cleanse) cue: a sink-gated green layer over the interrupt slot,
    -- visible only while the target is ENRAGED (dispel type 9). Independent of the kick's
    -- own visibility (shows even with no interruptible cast) and drawn above it, so on a
    -- kick/soothe collision the soothe wins. The cue self-gates on the enrage via its
    -- per-frame sink; here we only arm/show it when this character has a soothe ability.
    if UISootheCue then
        local sid = ctx.sootheSpellID
        if ctx.profile and ctx.profile.showSootheCue == false then sid = nil end
        if sid and ctx.active then
            UISootheCue.Show(UISootheCue.Create(intIcon, sid, intIcon.cachedIconSize))
        elseif intIcon.sootheCue then
            UISootheCue.Hide(intIcon.sootheCue)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Glow state resolver - one clear intent instead of six cascading booleans
-- ─────────────────────────────────────────────────────────────────────────────
local GLOW_NONE       = 0   -- no glow
local GLOW_ASSISTED   = 1   -- blue/white crawl (position-1 primary suggestion)
local GLOW_PROC       = 2   -- gold burst (spell is procced / critically available)
local GLOW_GAP_CLOSER = 3   -- magenta crawl (gap-closer, target out of melee range)
local GLOW_BURST      = 4   -- purple crawl (burst injection, burst window active)

--- Priority: gap-closer > burst > proc > assisted > none.
--- No WoW API calls - all inputs pre-computed by caller.
local function ResolveGlowState(position, spellID, showPrimaryGlow, showProcGlow, showGapCloserGlow, showBurstGlow)
    local isSyntheticProc = SpellQueue.IsSyntheticProc and SpellQueue.IsSyntheticProc(spellID)
    if isSyntheticProc and showGapCloserGlow then return GLOW_GAP_CLOSER end
    local isBurstInjection = SpellQueue.IsBurstInjection and SpellQueue.IsBurstInjection(spellID)
    if isBurstInjection and showBurstGlow then return GLOW_BURST end
    if BlizzardAPI.IsSpellProcced(spellID) and showProcGlow then return GLOW_PROC end
    if position == 1 and showPrimaryGlow then return GLOW_ASSISTED end
    -- Spell displaced to position 2 by a gap-closer injection keeps its blue glow
    -- so the player knows it is still Blizzard's next recommended cast.
    local isDisplaced = SpellQueue.IsDisplacedPrimary and SpellQueue.IsDisplacedPrimary(spellID)
    if isDisplaced and showPrimaryGlow then return GLOW_ASSISTED end
    return GLOW_NONE
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared per-icon DPS queue render (standard queue + nameplate overlay).
-- ctx is built once per render pass by the caller and carries every per-surface
-- parameter, so the two surfaces can never drift on the icon logic again:
--   now                     GetTime() for this pass
--   inCombat                player combat state (surface-specific source)
--   updateCooldowns         throttled cooldown-refresh tick
--   spellIDs, hasSpells     the queue array and whether it has entries
--   showPrimaryGlow / showProcGlow / showGapCloserGlow / showBurstGlow
--   queueDesaturation       desaturation applied to positions 2+
--   showHotkeys             hotkey text visible
--   lookupHotkeys           query spell hotkeys at all (text display or flash matching)
--   refreshHotkeys          force hotkey re-query this pass (bindings dirty / throttle)
--   hotkeyColor             profile hotkey color table (or nil)
--   showRangeTint / showUsabilityTint / showCastingHighlight
--   isChanneling, channelSpellID, isCasting, castSpellID   player cast state
--   firstIconScale          per-surface scale for position 1 (nil = never touch scale)
--   opacity                 per-frame alpha (nil = never touch alpha)
--   hideEmptySlots          hide the button on an empty slot (overlay) instead of
--                           showing an empty placeholder slot (standard queue)
-- ─────────────────────────────────────────────────────────────────────────────
local function RenderQueueIcon(icon, i, ctx)
    local currentTime = ctx.now
    local spellIDs = ctx.spellIDs
    local spellCount = ctx.hasSpells and #spellIDs or 0
    local spellID = ctx.hasSpells and spellIDs[i] or nil
    local isItemEntry = spellID and spellID < 0
    local itemID = isItemEntry and -spellID or nil
    local GetCachedSpellInfo = BlizzardAPI.GetCachedSpellInfo
    local spellInfo
    if isItemEntry then
        local itemIcon = GetItemIcon and GetItemIcon(itemID) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
        if itemIcon then spellInfo = { iconID = itemIcon } end
    else
        spellInfo = spellID and GetCachedSpellInfo(spellID)
    end

    -- Position stabilization (positions 2+): hold the current spell for
    -- POSITION_HOLD_TIME before replacing it. Prevents rapid position
    -- shuffling when SpellQueue re-categorizes spells (proc gained/lost,
    -- CD expired). If the old spell is no longer anywhere in the queue
    -- (consumed/cast), allow immediate replacement.
    -- Position 1: hold display briefly after a confirmed keypress so the
    -- icon doesn't change right as the player commits to it.
    if i == 1 and spellID and icon.spellID and icon.spellID ~= spellID then
        if icon.lastPressTime and (currentTime - icon.lastPressTime) < POSITION_HOLD_TIME then
            spellID = icon.spellID
            spellInfo = GetCachedSpellInfo(icon.spellID)
            if not spellInfo then spellID = nil end
        end
    elseif i > 1 and spellID and icon.spellID and icon.spellID ~= spellID then
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
                local oldInfo
                if icon.spellID < 0 then
                    local oldItemID = -icon.spellID
                    local oldItemIcon = GetItemIcon and GetItemIcon(oldItemID) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(oldItemID))
                    if oldItemIcon then oldInfo = { iconID = oldItemIcon } end
                else
                    oldInfo = GetCachedSpellInfo(icon.spellID)
                end
                if oldInfo then
                    spellID = icon.spellID
                    spellInfo = oldInfo
                    isItemEntry = spellID < 0
                    itemID = isItemEntry and -spellID or nil
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
            icon._cooldownShown       = false
            icon._chargeCooldownShown = false
            icon.cachedIsUsable = nil
            icon.cachedNotEnoughResources = nil
            icon.lastUsabilityCheck = nil
        end

        icon.spellID = spellID

        -- Track item state for UpdateButtonCooldowns and hotkey lookup.
        if isItemEntry then
            icon.isItem = true
            icon.itemID = itemID
            if spellChanged then
                local _, castSpellID = GetItemSpell(itemID)
                icon.itemCastSpellID = castSpellID
            end
        elseif icon.isItem then
            icon.isItem = nil
            icon.itemID = nil
            icon.itemCastSpellID = nil
        end

        local iconTexture = icon.iconTexture

        -- Fixes missing artwork on first assignment or after UI reload.
        if spellChanged or not iconTexture:GetTexture() then
            iconTexture:SetTexture(spellInfo.iconID)
        end

        if not iconTexture:IsShown() then
            iconTexture:Show()
        end

        -- Spell-change is an instant swap (no fade). The per-icon fade-in felt
        -- sluggish and masked rapid churn rather than smoothing it.

        -- "Waiting for..." = Assisted Combat's resource-wait indicator.
        -- Detected by iconID 134377, the shared timer icon Blizzard uses for
        -- all "Waiting for [resource]" placeholder spells. File IDs are the
        -- same across all locales, so this check is locale-safe.
        if spellChanged then
            icon.isWaitingSpell = not isItemEntry and spellInfo.iconID == 134377
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

        -- Position-based vertex color is applied inside the visual
        -- state machine below to avoid overwriting the resource tint
        -- (blue/purple) on every frame.

        -- Swipe animates smoothly once set; only refresh on change or throttle tick.
        if spellChanged or ctx.updateCooldowns then
            UpdateButtonCooldowns(icon)
        end

        -- Proc glow replaces all other glows to avoid confusing layered animations.
        local glowState = ResolveGlowState(i, spellID, ctx.showPrimaryGlow, ctx.showProcGlow, ctx.showGapCloserGlow, ctx.showBurstGlow)

        -- Glow hysteresis (positions 2+): require desired glow state to be
        -- stable for GLOW_HOLD_TIME before switching animations. Prevents
        -- jarring animation restarts from transient proc toggles.
        -- Position 1 always reflects current state immediately.
        -- Displaced primaries (injected down from pos 1) also bypass
        -- hysteresis so the blue glow appears instantly.
        local isDisplaced = SpellQueue.IsDisplacedPrimary and SpellQueue.IsDisplacedPrimary(spellID)
        if i > 1 then
            if spellChanged or isDisplaced or not ctx.inCombat then
                -- Spell changed, displaced from pos 1, or out of combat: apply
                -- immediately. OOC there is no combat proc-flicker to smooth, and
                -- holding a glow-OFF change here is what left a proc glow stuck at
                -- position 2 after combat when rendering went idle mid-hysteresis.
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
            UIAnimations.StartAssistedGlow(icon, ctx.inCombat)
            icon.hasAssistedGlow = true
        elseif icon.hasAssistedGlow then
            UIAnimations.StopAssistedGlow(icon)
            icon.hasAssistedGlow = false
        end

        -- "Switch target" arrow: slot 1 only, when AC re-recommends a DoT
        -- already live on the current target (spread cue from SpellQueue).
        if icon.spreadArrow then
            if i == 1 and SpellQueue.IsDotSpreadActive and SpellQueue.IsDotSpreadActive() then
                icon.spreadArrow:Show()
            elseif icon.spreadArrow:IsShown() then
                icon.spreadArrow:Hide()
            end
        end

        if glowState == GLOW_PROC then
            if icon.hasGapCloserGlow then UIAnimations.StopGapCloserGlow(icon); icon.hasGapCloserGlow = false end
            if icon.hasBurstGlow then UIAnimations.StopBurstGlow(icon); icon.hasBurstGlow = false end
            if not icon.hasProcGlow then UIAnimations.ShowProcGlow(icon, ctx.inCombat); icon.hasProcGlow = true end
        else
            if icon.hasProcGlow then UIAnimations.HideProcGlow(icon); icon.hasProcGlow = false end
            -- Stale flag guard: re-sync if external code hid the frame without clearing the flag.
            if icon.hasGapCloserGlow and icon.GapCloserHighlightFrame
                and not icon.GapCloserHighlightFrame:IsShown() then
                icon.hasGapCloserGlow = false
            end
            if icon.hasBurstGlow and icon.BurstHighlightFrame
                and not icon.BurstHighlightFrame:IsShown() then
                icon.hasBurstGlow = false
            end
            if glowState == GLOW_GAP_CLOSER and not icon.hasGapCloserGlow then
                UIAnimations.StartGapCloserGlow(icon)
                icon.hasGapCloserGlow = true
            elseif glowState ~= GLOW_GAP_CLOSER and icon.hasGapCloserGlow then
                UIAnimations.StopGapCloserGlow(icon)
                icon.hasGapCloserGlow = false
            end
            if glowState == GLOW_BURST and not icon.hasBurstGlow then
                UIAnimations.StartBurstGlow(icon)
                icon.hasBurstGlow = true
            elseif glowState ~= GLOW_BURST and icon.hasBurstGlow then
                UIAnimations.StopBurstGlow(icon)
                icon.hasBurstGlow = false
            end
        end

        -- Re-query only when action bars or bindings change.
        -- Empty results ("") are retried so the scanner's 0.25s refresh
        -- can resolve proc overrides (Infernal Bolt, Ruination, etc.)
        -- that miss on the first frame before GetOverrideSpell propagates.
        local hotkey
        local hotkeyChanged = false
        if ctx.refreshHotkeys or spellChanged or not icon.cachedHotkey or icon.cachedHotkey == "" then
            if isItemEntry then
                hotkey = ActionBarScanner.GetItemHotkey and ActionBarScanner.GetItemHotkey(itemID, icon.itemCastSpellID) or ""
            else
                hotkey = (ctx.lookupHotkeys and ActionBarScanner.GetSpellHotkey) and ActionBarScanner.GetSpellHotkey(spellID) or ""
            end
            if icon.cachedHotkey ~= hotkey then
                hotkeyChanged = true
            end
            icon.cachedHotkey = hotkey
        else
            hotkey = icon.cachedHotkey
        end

        -- When showHotkeys is off, keep normalized hotkey for flash matching.
        SetIconHotkeyText(icon, hotkey, ctx.showHotkeys)
        if hotkeyChanged then
            SetIconNormalizedHotkey(icon, hotkey, currentTime, true)
        end

        local hasVisibleHotkey = ctx.showHotkeys and hotkey ~= ""
        local needRangeCheck = ctx.showRangeTint or hasVisibleHotkey
        local needsDirectSlot = needRangeCheck or ctx.inCombat

        -- Range/usability support: slot-based with spell fallback.
        local directSlot
        if needsDirectSlot then
            if isItemEntry then
                directSlot = ActionBarScanner.GetDirectSlotForItem and ActionBarScanner.GetDirectSlotForItem(itemID)
            else
                directSlot = ActionBarScanner.GetDirectSlotForSpell(spellID)
            end
        end

        local isOutOfRange = false
        if needRangeCheck then
            isOutOfRange = CheckSpellRange(icon, spellID, directSlot)
            if hasVisibleHotkey then
                UpdateRangeHotkeyColor(icon, isOutOfRange, ctx.hotkeyColor)
            end
        end

        local baseDesaturation = (i > 1) and ctx.queueDesaturation or 0
        local isChanneledSpell, isCastedSpell
        if isItemEntry then
            isChanneledSpell, isCastedSpell = false, false
        else
            isChanneledSpell, isCastedSpell = MatchActiveCast(
                spellID, ctx.isChanneling, ctx.channelSpellID, ctx.isCasting, ctx.castSpellID)
        end

        local visualState = ResolveVisualState(icon, spellID,
            isChanneledSpell, isCastedSpell, ctx.isChanneling, ctx.isCasting,
            isOutOfRange, ctx.showRangeTint, ctx.showUsabilityTint, ctx.inCombat, directSlot,
            hasVisibleHotkey, currentTime)

        local qb = (i > 1) and QUEUE_ICON_BRIGHTNESS or 1
        local qa = (i > 1) and QUEUE_ICON_OPACITY or 1
        ApplyVisualState(icon, visualState, baseDesaturation, qb, qa)

        UpdateCastingHighlight(icon, ctx.showCastingHighlight, spellID, isChanneledSpell, isCastedSpell)

        -- Cue dot: one lower-left indicator carrying both per-ability cues, split into
        -- halves when both apply.
        --   move-cast - castable while moving RIGHT NOW: base instants always, hardcasts
        --               only while a proc has made them instant, channels never. Live state,
        --               so it is re-evaluated every render.
        --   off-GCD   - starts no global cooldown, so you can fire it and move straight on.
        --               Static per spell, but still re-checked because a pooled icon changes
        --               which spell it shows.
        -- ctx.showMoveCastDot folds in the per-spec auto default.
        local markable = not isItemEntry and not icon.isWaitingSpell
        ApplyCueDot(icon,
            markable and ctx.showMoveCastDot and IsMoveCastableNow(spellID, spellInfo),
            markable and ctx.showOffGcdDot and IsOffGCDSpell(spellID))

        -- First icon scale (overlay only; scale is icon-local, never a secret read).
        if ctx.firstIconScale then
            local targetScale = (i == 1) and ctx.firstIconScale or 1.0
            if icon:GetScale() ~= targetScale then
                icon:SetScale(targetScale)
            end
        end

        -- Channel fill animation (channels only, not hardcasts).
        if isChanneledSpell then
            if not icon._hasChannelFill then
                UIAnimations.StartChannelFill(icon)
            end
        elseif icon._hasChannelFill then
            UIAnimations.StopChannelFill(icon)
        end

        ApplyExecuteCue(icon, spellID)

        if not icon:IsShown() then
            icon:Show()
        end
        if ctx.opacity then
            icon:SetAlpha(ctx.opacity)
        end
    else
        ClearExecuteCue(icon)
        if icon.spellID then
            ClearIconState(icon)
        end

        if ctx.hideEmptySlots then
            icon:Hide()
        elseif not icon:IsShown() then
            icon:Show()
        end
    end
end

-- Reused ctx tables for RenderSpellQueue (avoids per-pass table allocations).
local renderCtx = {}
local interruptCtx = {}

-- Small ST / CLEAVE / AOE readout above the queue (debug mode only) so the active
-- context is a glance, not guesswork. Lazily created; hidden when debug is off.
-- Danger cue: "a mob near you is casting something lethal". One texture per nearby caster,
-- all stacked in the same spot - each one's alpha is driven from that caster's (possibly
-- secret) important-cast verdict, so ANY of them lighting up lights the cue. Stacking is what
-- replaces the OR we are not allowed to compute: the verdicts can never be read, only poured
-- into a sink. See BlizzardAPI.DriveImportantCastAlphas.
-- One slot per nameplate token, so every visible enemy has a region of its own and no mob
-- can be crowded out by scan order (the verdicts are unreadable, so we cannot rank them).
-- Forty alpha-0 textures on one frame cost nothing; being blind to the seventh caster does.
local DANGER_CUE_SLOTS = 40
local DANGER_CUE_INTERVAL = 0.2 -- scanning 40 unit tokens every frame buys nothing
local lastDangerCueAt = 0
local function UpdateImportantCastCue(addon, profile)
    local mf = addon.mainFrame
    if not mf then return end
    if not profile.showImportantCastCue then
        if mf.jacDangerCue then mf.jacDangerCue:Hide() end
        return
    end
    local cue = mf.jacDangerCue
    if not cue then
        cue = CreateFrame("Frame", nil, mf)
        cue:SetSize(48, 16)
        cue:SetPoint("BOTTOM", mf, "TOP", 0, 6)
        cue.slots = {}
        for i = 1, DANGER_CUE_SLOTS do
            -- Blizzard's own important-cast art, so the cue reads as the same language the
            -- nameplate speaks when the setting for it happens to be on.
            local t = cue:CreateTexture(nil, "OVERLAY")
            t:SetAtlas("ui-hud-nameplates-importantcast")
            t:SetAllPoints(cue)
            t:SetAlpha(0)
            cue.slots[i] = t
        end
        mf.jacDangerCue = cue
    end
    cue:Show()
    local now = GetTime()
    if now - lastDangerCueAt < DANGER_CUE_INTERVAL then return end
    lastDangerCueAt = now
    if BlizzardAPI and BlizzardAPI.DriveImportantCastAlphas then
        BlizzardAPI.DriveImportantCastAlphas(cue.slots, 1)
    end
end

local function UpdateContextIndicator(addon, profile)
    local mf = addon.mainFrame
    if not mf then return end
    if not profile.debugMode then
        if mf.jacContextTag then mf.jacContextTag:Hide() end
        return
    end
    if not mf.jacContextTag then
        local fs = mf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOMLEFT", mf, "TOPLEFT", 0, 2)
        mf.jacContextTag = fs
    end
    local ctx = SpellQueue.DebugContextState and SpellQueue.DebugContextState()
    local arch = ctx and ctx.arch
    local label, color
    if arch == "aoe" then
        label, color = "AOE", "ff44ff44"
    elseif arch == "cleave" then
        label, color = "CLEAVE", "ffffcc44"
    else
        label, color = "ST", "ff8888ff"
    end
    mf.jacContextTag:SetText("|c" .. color .. label .. "|r")
    mf.jacContextTag:Show()
end

function UIRenderer.RenderSpellQueue(addon, spellIDs)
    if not addon then return end
    local spellIconsRef = addon.spellIcons

    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    if not profile then return end

    UpdateContextIndicator(addon, profile)
    UpdateImportantCastCue(addon, profile)

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
    local textOverlays = profile.textOverlays
    local glowMode = profile.glowMode or "all"
    local showPrimaryGlow = (glowMode == "all" or glowMode == "primaryOnly")
    local showProcGlow = (glowMode == "all" or glowMode == "procOnly")
    local showGapCloserGlow = showPrimaryGlow and profile.gapClosers and profile.gapClosers.showGlow == true
    local showBurstGlow = showPrimaryGlow and profile.burstInjection and profile.burstInjection.showGlow == true
    local queueDesaturation = profile.queueIconDesaturation or DEFAULT_QUEUE_DESATURATION
    local showUsabilityTint = profile.showUsabilityTint ~= false
    local showRangeTint = profile.showRangeTint ~= false
    local showCastingHighlight = profile.showCastingHighlight ~= false
    
    -- Shared cast/channel state (used by both standard queue and nameplate overlay).
    isChanneling, channelSpellID, isCasting, castSpellID = ResolvePlayerCastState(profile, cachedChannelSpellID, cachedCastSpellID)

    -- Eating is aura-based, NOT a spell channel (no cast bar, no UnitChannelInfo), and uses a
    -- generic "Food" aura distinct from the food's on-use spell. While it's granting the buff,
    -- treat the shown food buff icon as the channel target so the queue greys out and it shows
    -- the fill. Ends when Well Fed lands (~10s), not when the meal does - same window the fill
    -- sweep runs to, so the grey-out lifts exactly as the sweep completes.
    local SDB = LibStub("JustAC-SpellDB", true)
    if not isChanneling and not isCasting and addon.defensiveIcons
            and profile.greyOutWhileChanneling ~= false
            and SDB and SDB.IsEatingForBuff and SDB.IsEatingForBuff() then
        for _, dicon in ipairs(addon.defensiveIcons) do
            if dicon:IsShown() and dicon.isItem and dicon.itemCastSpellID
                    and SDB.GetPrecombatBuffCategory
                    and SDB.GetPrecombatBuffCategory(dicon.itemID) == "food" then
                isChanneling = true
                channelSpellID = dicon.itemCastSpellID
                break
            end
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
                            defHotkey = ActionBarScanner and ActionBarScanner.GetItemHotkey and ActionBarScanner.GetItemHotkey(defID, defIcon.itemCastSpellID) or ""
                        else
                            defHotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(defID) or ""
                        end
                        local defShowHotkeys = not textOverlays or not textOverlays.hotkey or textOverlays.hotkey.show ~= false
                        if defIcon.cachedHotkey ~= defHotkey then
                            defIcon.cachedHotkey = defHotkey
                            SetIconNormalizedHotkey(defIcon, defHotkey, currentTime, true)
                        end
                        SetIconHotkeyText(defIcon, defHotkey, defShowHotkeys)
                    end
                end
                -- Throttled cooldown widget refresh.
                if shouldUpdateCooldowns then
                    UpdateButtonCooldowns(defIcon)
                end
            end
        end
    end

    -- Offensive icon rendering requires spellIcons; defensive loop above runs regardless.
    if not spellIconsRef then return end

    local showHotkeys = not textOverlays or not textOverlays.hotkey or textOverlays.hotkey.show ~= false
    local showFlash = profile.showFlash ~= false

    -- Glow frames at incorrect scale appear when hidden with active glows.
    if not shouldShowFrame then
        for i = 1, maxIcons do
            local icon = spellIconsRef[i]
            if icon then
                if icon.hasAssistedGlow   then UIAnimations.StopAssistedGlow(icon);  icon.hasAssistedGlow   = false end
                if icon.hasProcGlow       then UIAnimations.HideProcGlow(icon);       icon.hasProcGlow       = false end
                if icon.hasGapCloserGlow  then UIAnimations.StopGapCloserGlow(icon);  icon.hasGapCloserGlow  = false end
                if icon.hasBurstGlow      then UIAnimations.StopBurstGlow(icon);      icon.hasBurstGlow      = false end
                if icon.spreadArrow and icon.spreadArrow:IsShown() then icon.spreadArrow:Hide() end
                if icon.hasDefensiveGlow  then UIAnimations.StopDefensiveGlow(icon);  icon.hasDefensiveGlow  = false end
            end
        end
    end

    -- ── Interrupt reminder (position 0) + soothe cue (shared renderer) ──────
    local intIcon = addon.interruptIcon
    if intIcon then
        local soothe = addon.resolvedSoothe
        local ictx = interruptCtx
        ictx.now                = currentTime
        ictx.updateCooldowns    = shouldUpdateCooldowns
        ictx.active             = shouldShowFrame
        ictx.resolvedInterrupts = addon.resolvedInterrupts
        ictx.interruptMode      = profile.interruptMode
        ictx.spellIDs           = spellIDs
        ictx.profile            = profile
        ictx.showHotkeys        = showHotkeys
        ictx.hotkeyColor        = textOverlays and textOverlays.hotkey and textOverlays.hotkey.color
        ictx.opacity            = profile.frameOpacity
        ictx.sootheSpellID      = soothe and soothe[1] and soothe[1].spellID
        UIRenderer.RenderInterruptSlot(intIcon, ictx)
    end

    -- Move-cast dot visibility: explicit profile toggle, or the per-spec auto
    -- default (ranged DPS / healers on, melee off) when the player hasn't set it.
    local showMoveCastDot = MoveCastDotEnabled(profile)

    if shouldShowFrame then
        -- Per-pass ctx for the shared icon renderer (see RenderQueueIcon docs).
        local ctx = renderCtx
        ctx.now                 = currentTime
        ctx.inCombat            = isInCombat
        ctx.updateCooldowns     = shouldUpdateCooldowns
        ctx.spellIDs            = spellIDs
        ctx.hasSpells           = hasSpells
        ctx.showPrimaryGlow     = showPrimaryGlow
        ctx.showProcGlow        = showProcGlow
        ctx.showGapCloserGlow   = showGapCloserGlow
        ctx.showBurstGlow       = showBurstGlow
        ctx.queueDesaturation   = queueDesaturation
        ctx.showHotkeys         = showHotkeys
        ctx.lookupHotkeys       = showHotkeys or showFlash
        ctx.refreshHotkeys      = hotkeysDirty
        ctx.hotkeyColor         = textOverlays and textOverlays.hotkey and textOverlays.hotkey.color
        ctx.showRangeTint       = showRangeTint
        ctx.showUsabilityTint   = showUsabilityTint
        ctx.showCastingHighlight = showCastingHighlight
        ctx.showMoveCastDot     = showMoveCastDot
        ctx.showOffGcdDot       = profile.showOffGcdDot
        ctx.isChanneling        = isChanneling
        ctx.channelSpellID      = channelSpellID
        ctx.isCasting           = isCasting
        ctx.castSpellID         = castSpellID
        ctx.firstIconScale      = nil
        ctx.opacity             = nil
        ctx.hideEmptySlots      = nil

        for i = 1, maxIcons do
            local icon = spellIconsRef[i]
            if icon then
                RenderQueueIcon(icon, i, ctx)
            end
        end
    end
    
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
        -- In click-through mode, grab tabs are fully hidden; icons become drag handles on Alt hold.
        if addon.grabTab then
            if isClickThrough then
                addon.grabTab:Hide()
                addon.grabTab:EnableMouse(false)
            else
                addon.grabTab:Show()
                addon.grabTab:EnableMouse(true)
            end
        end
        if addon.defensiveFrame then
            addon.defensiveFrame:EnableMouse(not isLocked)
        end
        if addon.defensiveGrabTab then
            if isClickThrough then
                addon.defensiveGrabTab:Hide()
                addon.defensiveGrabTab:EnableMouse(false)
            else
                addon.defensiveGrabTab:Show()
                addon.defensiveGrabTab:EnableMouse(true)
            end
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
    -- Apply frameOpacity to the detached container (icons inherit) or all individual icons.
    if addon.defensiveFrame then
        local isFading = (addon.defensiveFrame.fadeIn and addon.defensiveFrame.fadeIn:IsPlaying()) or
                         (addon.defensiveFrame.fadeOut and addon.defensiveFrame.fadeOut:IsPlaying())
        if not isFading then
            addon.defensiveFrame:SetAlpha(frameOpacity)
        end
    elseif addon.defensiveIcons then
        for _, defIcon in ipairs(addon.defensiveIcons) do
            if defIcon then
                defIcon:SetAlpha(frameOpacity)
            end
        end
    end
    
    lastFrameState.shouldShow = shouldShowFrame
    lastFrameState.spellCount = spellCount
end

function UIRenderer.OpenHotkeyOverrideDialog(addon, id)
    if not addon or not id then return end

    local isItem = id < 0
    local displayName, displayIcon

    if isItem then
        local itemID = -id
        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
        displayName = itemName or ("Item #" .. itemID)
        displayIcon = itemIcon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400
    else
        local spellInfo = BlizzardAPI.GetCachedSpellInfo(id)
        if not spellInfo then return end
        displayName = spellInfo.name
        displayIcon = spellInfo.iconID or 0
    end

    StaticPopupDialogs["JUSTAC_HOTKEY_OVERRIDE"] = {
        text = "Set custom hotkey display for:\n|T" .. displayIcon .. ":16:16:0:0|t " .. displayName,
        button1 = "Set",
        button2 = "Remove", 
        button3 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 200,
        OnShow = function(self)
            local currentHotkey = addon:GetHotkeyOverride(self.data.id) or ""
            self.EditBox:SetText(currentHotkey)
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end,
        OnAccept = function(self)
            local newHotkey = self.EditBox:GetText()
            addon:SetHotkeyOverride(self.data.id, newHotkey)
        end,
        OnAlt = function(self)
            addon:SetHotkeyOverride(self.data.id, nil)
        end,
        EditBoxOnEnterPressed = function(self)
            local newHotkey = self:GetText()
            addon:SetHotkeyOverride(self:GetParent().data.id, newHotkey)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    
    StaticPopup_Show("JUSTAC_HOTKEY_OVERRIDE", nil, nil, {id = id})
end

--- Cached per-frame (≤0.015 s); both renderers share the same answer and debounce timer.
--- Delegates to CastInterruptTracker which owns all interrupt state.
---
--- @param resolvedInts  table?   ordered {spellID, type} array from SpellDB.ResolveInterruptSpells
--- @param interruptMode string   "kickOnly" | "ccPrefer"
--- @param currentTime   number   GetTime() value from the caller
--- @return table  { shouldShow, spellID, castBar } - reused each call; do NOT hold across frames
function UIRenderer.EvaluateInterrupt(resolvedInts, interruptMode, currentTime)
    if CastInterruptTracker then
        return CastInterruptTracker.EvaluateInterrupt(resolvedInts, interruptMode, currentTime)
    end
    return { shouldShow = false, spellID = nil, castBar = nil, interruptMode = interruptMode }
end

function UIRenderer.SetCombatState(inCombat)
    isInCombat = inCombat
end

function UIRenderer.SetCastSpellID(spellID)
    cachedCastSpellID = spellID
end

function UIRenderer.SetChannelSpellID(spellID)
    cachedChannelSpellID = spellID
end

function UIRenderer.ResolvePlayerCastState(profile)
    return ResolvePlayerCastState(profile, cachedChannelSpellID, cachedCastSpellID)
end

UIRenderer.UpdateButtonCooldowns = UpdateButtonCooldowns
UIRenderer.MoveCastDotEnabled    = MoveCastDotEnabled
UIRenderer.NormalizeHotkey       = NormalizeHotkey
UIRenderer.SetIconHotkeyText     = SetIconHotkeyText
UIRenderer.SetIconNormalizedHotkey = SetIconNormalizedHotkey
UIRenderer.CheckSpellRange       = CheckSpellRange
UIRenderer.UpdateRangeHotkeyColor = UpdateRangeHotkeyColor
UIRenderer.MatchActiveCast       = MatchActiveCast
UIRenderer.ResolveVisualState    = ResolveVisualState
UIRenderer.ApplyVisualState      = ApplyVisualState
UIRenderer.UpdateCastingHighlight = UpdateCastingHighlight
UIRenderer.ClearIconState        = ClearIconState
UIRenderer.RenderQueueIcon       = RenderQueueIcon
UIRenderer.WAIT_LABEL            = WAIT_LABEL

-- Suppresses CC suggestions until the game registers the CC state on the target.
function UIRenderer.NotifyCCApplied()
    if CastInterruptTracker then CastInterruptTracker.NotifyCCApplied() end
end
