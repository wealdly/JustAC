-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: UI Renderer Module
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 24)
if not UIRenderer then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
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
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor

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
        if lStart and lDuration and lDuration > 0 then
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
local CLICK_DARKEN_ALPHA = 0.4
local CLICK_INSET_PIXELS = 2
local HOTKEY_FONT_SCALE = UIFrameFactory.HOTKEY_FONT_SCALE
local HOTKEY_MIN_FONT_SIZE = UIFrameFactory.HOTKEY_MIN_FONT_SIZE
local HOTKEY_OFFSET_FIRST = UIFrameFactory.HOTKEY_OFFSET_FIRST
local HOTKEY_OFFSET_QUEUE = UIFrameFactory.HOTKEY_OFFSET_QUEUE

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
    if icon.centerText then icon.centerText:Hide() end
    if icon.chargeText then icon.chargeText:Hide() end
    icon._cooldownShown        = false
    icon._chargeCooldownShown  = false
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
    if addon and addon.spellIcons then
        for i = 1, #addon.spellIcons do
            local icon = addon.spellIcons[i]
            if icon then
                icon.cachedHotkey = nil
            end
        end
    end
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

    -- Per-frame proc glow re-evaluation with hysteresis.
    if UIAnimations then
        local procCheckID = defensiveIcon.isItem and defensiveIcon.itemCastSpellID or id
        local isProc = procCheckID and IsSpellProcced(procCheckID) or false
        local glowMode = defensiveIcon.defGlowMode or "all"
        local wantProcGlow = isProc and (glowMode == "all" or glowMode == "procOnly")
        local hasProcGlow = defensiveIcon.ProcGlowFrame and defensiveIcon.ProcGlowFrame:IsShown()

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
                -- Always animate defensive procs (even OOC): a procced heal is the
                -- preferred post-combat top-up, same emphasis rule as gap-closer/
                -- interrupt/burst glows.
                UIAnimations.ShowProcGlow(defensiveIcon, true)
            elseif not wantProcGlow and hasProcGlow then
                UIAnimations.HideProcGlow(defensiveIcon)
                local showMarching = defensiveIcon.defShowGlow
                    and (glowMode == "all" or glowMode == "primaryOnly")
                if showMarching then
                    UIAnimations.StartDefensiveGlow(defensiveIcon, isInCombat)
                end
            end
        end
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

-- glowModeOverride: overrides profile.defensives.glowMode (overlay has its own setting).
-- waiting: held-back emergency heal (above low-health threshold) - render desaturated
-- with a centered WAIT tag and no glow, instead of showing it as a live suggestion.
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon, showGlow, glowModeOverride, showHotkeysOverride, showFlashOverride, waiting)
    if not addon or not id or not defensiveIcon then return end
    
    local iconTexture, name
    local idChanged = (defensiveIcon.currentID ~= id) or (defensiveIcon.isItem ~= isItem)
    
    if isItem then
        if C_Item and C_Item.GetItemIconByID then
            iconTexture = C_Item.GetItemIconByID(id)
        end
        if C_Item and C_Item.GetItemInfo then
            name, _, _, _, _, _, _, _, _, iconTexture = C_Item.GetItemInfo(id)
        elseif GetItemInfo then
            name, _, _, _, _, _, _, _, _, iconTexture = GetItemInfo(id)
        end
        if not iconTexture then
            iconTexture = GetItemIcon and GetItemIcon(id)
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
    local wantProcGlow = isProc and (defGlowMode == "all" or defGlowMode == "procOnly")

    -- Inserted pre-combat buffs get their own vivid-green glow (out of combat) so they read
    -- as distinct, important "use me" icons rather than ordinary defensive suggestions.
    local SDB = LibStub("JustAC-SpellDB", true)
    local isBuff = not isInCombat and SDB and (
        (isItem and SDB.IsPrecombatBuffItem and SDB.IsPrecombatBuffItem(id))
        or (not isItem and SDB.IsClassMaintainedBuff and SDB.IsClassMaintainedBuff(id)))
    defensiveIcon.isPrecombatBuff = isBuff or nil  -- click-overlay reads this for its "click" hint
    if waiting then
        -- Held-back heal parked at the bottom: no "use me" glow until it lights up at 35%.
        UIAnimations.StopPrecombatGlow(defensiveIcon)
        UIAnimations.HideProcGlow(defensiveIcon)
        UIAnimations.StopDefensiveGlow(defensiveIcon)
    elseif isBuff then
        UIAnimations.HideProcGlow(defensiveIcon)
        UIAnimations.StopDefensiveGlow(defensiveIcon)
        UIAnimations.StartPrecombatGlow(defensiveIcon, isInCombat)
    elseif wantProcGlow then
        UIAnimations.StopPrecombatGlow(defensiveIcon)
        UIAnimations.StopDefensiveGlow(defensiveIcon)
        -- Always animate defensive procs (even OOC): a procced heal is the
        -- preferred post-combat top-up, same emphasis rule as gap-closer/
        -- interrupt/burst glows.
        UIAnimations.ShowProcGlow(defensiveIcon, true)
    else
        UIAnimations.StopPrecombatGlow(defensiveIcon)
        UIAnimations.HideProcGlow(defensiveIcon)
        local showMarching = showGlow and (defGlowMode == "all" or defGlowMode == "primaryOnly")
        if showMarching then
            UIAnimations.StartDefensiveGlow(defensiveIcon, isInCombat)
        else
            UIAnimations.StopDefensiveGlow(defensiveIcon)
        end
    end
    
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
        defensiveIcon.spellID = nil
        defensiveIcon.itemID = nil
        defensiveIcon.itemCastSpellID = nil
        defensiveIcon.currentID = nil
        defensiveIcon.isItem = nil
        defensiveIcon.isPrecombatBuff = nil
        defensiveIcon.isWaiting = nil
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
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, showGlow, nil, nil, nil, entry.waiting)
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

    -- Re-seat the out-of-combat click layers over any inserted pre-combat buff icons.
    local PrecombatOverlay = LibStub("JustAC-PrecombatOverlay", true)
    if PrecombatOverlay and PrecombatOverlay.Refresh then PrecombatOverlay.Refresh() end
end

function UIRenderer.HideDefensiveIcons(addon)
    if not addon or not addon.defensiveIcons then return end

    for _, icon in ipairs(addon.defensiveIcons) do
        UIRenderer.HideDefensiveIcon(icon)
    end

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
-- Glow state resolver - one clear intent instead of six cascading booleans
-- ─────────────────────────────────────────────────────────────────────────────
local GLOW_NONE       = 0   -- no glow
local GLOW_ASSISTED   = 1   -- blue/white crawl (position-1 primary suggestion)
local GLOW_PROC       = 2   -- gold burst (spell is procced / critically available)
local GLOW_GAP_CLOSER = 3   -- gold crawl (gap-closer, target out of melee range)
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

function UIRenderer.RenderSpellQueue(addon, spellIDs)
    if not addon then return end
    local spellIconsRef = addon.spellIcons

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
    -- generic "Food" aura distinct from the food's on-use spell. When it's active, treat the
    -- shown food buff icon as the channel target so the queue greys out and it shows the fill.
    local SDB = LibStub("JustAC-SpellDB", true)
    if not isChanneling and not isCasting and addon.defensiveIcons
            and profile.greyOutWhileChanneling ~= false
            and SDB and SDB.GetActiveEatingAura and SDB.GetActiveEatingAura() then
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

    local IsSpellUsable = BlizzardAPI.IsSpellUsable
    local showHotkeys = not textOverlays or not textOverlays.hotkey or textOverlays.hotkey.show ~= false
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
                if icon.hasBurstGlow      then UIAnimations.StopBurstGlow(icon);      icon.hasBurstGlow      = false end
                if icon.hasDefensiveGlow  then UIAnimations.StopDefensiveGlow(icon);  icon.hasDefensiveGlow  = false end
            end
        end
    end

    -- ── Interrupt reminder (position 0) ─────────────────────────────────────
    local intIcon = addon.interruptIcon
    local resolvedInts = addon.resolvedInterrupts
    local interruptMode = profile.interruptMode or "kickPrefer"
    -- Retired modes in saved data → safe fallback.
    if interruptMode == "importantOnly" then interruptMode = "kickOnly" end
    if interruptMode == "ccShielded" then interruptMode = "kickPrefer" end
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

            local intShowHotkeys = not textOverlays or not textOverlays.hotkey or textOverlays.hotkey.show ~= false
            if spellChanged or shouldUpdateCooldowns or not intIcon.cachedHotkey then
                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(intSpellID) or ""
                intIcon.cachedHotkey = hotkey
                SetIconHotkeyText(intIcon, hotkey, intShowHotkeys)
                SetIconNormalizedHotkey(intIcon, hotkey, nil, false)
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
                        local hkc = textOverlays and textOverlays.hotkey and textOverlays.hotkey.color
                        intIcon.hotkeyText:SetTextColor((hkc and hkc.r) or 1, (hkc and hkc.g) or 1, (hkc and hkc.b) or 1, (hkc and hkc.a) or 1)
                    end
                    intIcon.lastOutOfRange = isOutOfRange
                end
            end

            -- No channeling grey-out for interrupts: they are urgent actions the
            -- player may want to cancel a channel to use.

            if not intIcon.hasInterruptGlow then
                UIAnimations.ShowInterruptProcGlow(intIcon)
                intIcon.hasInterruptGlow = true
            end

            -- Secret-aware target cast-progress bar with a kick-zone (engine-driven).
            UIAnimations.ShowInterruptCastBar(intIcon)

            -- Cast bar textures can be secret in 12.0 - pass through unconditionally.
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
                UIRenderer.PlayInterruptAlertSound(profile)
                intIcon:Show()
            end
            local frameOpacity = profile.frameOpacity or 1.0
            -- Hide a KICK suggestion on a non-interruptible cast via the secret-aware alpha
            -- sink (works under any cast-bar addon; never reads the secret). A CC suggestion
            -- stays visible - CC is the correct call on a non-interruptible cast.
            if SpellDB and SpellDB.IsInterruptTypeSpell and SpellDB.IsInterruptTypeSpell(intSpellID) then
                BlizzardAPI.ApplyInterruptIconAlpha(intIcon, frameOpacity)
            else
                intIcon:SetAlpha(frameOpacity)
            end
            -- Grey the reminder (interrupt or CC) while it's on the GCD; off-GCD
            -- interrupts stay full-color since IsSpellOnGCD is false for them.
            intIcon.iconTexture:SetDesaturation(BlizzardAPI.IsSpellOnGCD(intSpellID) and 1.0 or 0)
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
            local isItemEntry = spellID and spellID < 0
            local itemID = isItemEntry and -spellID or nil
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
                if spellChanged or shouldUpdateCooldowns then
                    UpdateButtonCooldowns(icon)
                end

                -- Proc glow replaces all other glows to avoid confusing layered animations.
                local glowState = ResolveGlowState(i, spellID, showPrimaryGlow, showProcGlow, showGapCloserGlow, showBurstGlow)

                -- Glow hysteresis (positions 2+): require desired glow state to be
                -- stable for GLOW_HOLD_TIME before switching animations. Prevents
                -- jarring animation restarts from transient proc toggles.
                -- Position 1 always reflects current state immediately.
                -- Displaced primaries (injected down from pos 1) also bypass
                -- hysteresis so the blue glow appears instantly.
                local isDisplaced = SpellQueue.IsDisplacedPrimary and SpellQueue.IsDisplacedPrimary(spellID)
                if i > 1 then
                    if spellChanged or isDisplaced then
                        -- Spell changed or displaced from pos 1: apply immediately
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
                    if icon.hasBurstGlow then UIAnimations.StopBurstGlow(icon); icon.hasBurstGlow = false end
                    if not icon.hasProcGlow then UIAnimations.ShowProcGlow(icon, isInCombat); icon.hasProcGlow = true end
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
                if hotkeysDirty or spellChanged or not icon.cachedHotkey or icon.cachedHotkey == "" then
                    if isItemEntry then
                        hotkey = ActionBarScanner and ActionBarScanner.GetItemHotkey and ActionBarScanner.GetItemHotkey(itemID, icon.itemCastSpellID) or ""
                    else
                        hotkey = GetSpellHotkey and GetSpellHotkey(spellID) or ""
                    end
                    if icon.cachedHotkey ~= hotkey then
                        hotkeyChanged = true
                    end
                    icon.cachedHotkey = hotkey
                else
                    hotkey = icon.cachedHotkey
                end
                
                -- When showHotkeys is off, keep normalized hotkey for flash matching.
                SetIconHotkeyText(icon, hotkey, showHotkeys)
                if hotkeyChanged then
                    SetIconNormalizedHotkey(icon, hotkey, currentTime, true)
                end

                local hasVisibleHotkey = showHotkeys and hotkey ~= ""
                local needRangeCheck = showRangeTint or hasVisibleHotkey
                local needsDirectSlot = needRangeCheck or isInCombat

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
                        local hkc = textOverlays and textOverlays.hotkey and textOverlays.hotkey.color
                        UpdateRangeHotkeyColor(icon, isOutOfRange, hkc)
                    end
                end
                
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                local isChanneledSpell, isCastedSpell
                if isItemEntry then
                    isChanneledSpell, isCastedSpell = false, false
                else
                    isChanneledSpell, isCastedSpell = MatchActiveCast(
                        spellID, isChanneling, channelSpellID, isCasting, castSpellID)
                end

                local visualState = ResolveVisualState(icon, spellID,
                    isChanneledSpell, isCastedSpell, isChanneling, isCasting,
                    isOutOfRange, showRangeTint, showUsabilityTint, isInCombat, directSlot,
                    hasVisibleHotkey, currentTime)
                
                local qb = (i > 1) and QUEUE_ICON_BRIGHTNESS or 1
                local qa = (i > 1) and QUEUE_ICON_OPACITY or 1
                ApplyVisualState(icon, visualState, baseDesaturation, qb, qa)

                UpdateCastingHighlight(icon, showCastingHighlight, spellID, isChanneledSpell, isCastedSpell)

                -- Channel fill animation (channels only, not hardcasts).
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
                    ClearIconState(icon)
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
UIRenderer.WAIT_LABEL            = WAIT_LABEL

-- Suppresses CC suggestions until the game registers the CC state on the target.
function UIRenderer.NotifyCCApplied()
    if CastInterruptTracker then CastInterruptTracker.NotifyCCApplied() end
end
