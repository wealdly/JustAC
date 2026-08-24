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
local UIMaintenanceAura = LibStub("JustAC-UIMaintenanceAura", true)
local RotationImport = LibStub("JustAC-RotationImport", true)
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
local POSITION_HOLD_TIME = 0.05

-- Glow hysteresis: require desired glow state to be stable for this duration
-- before switching animations. Prevents jarring animation restarts when proc
-- state toggles transiently (e.g. during GCD processing).
local GLOW_HOLD_TIME = 0.05

-- Normalize a raw WoW hotkey string to the MODIFIER-KEY format used by CreateKeyPressDetector.
-- Multi-modifier combos are checked first to prevent partial prefix matches.
-- Mouse abbreviations are reversed so matching uses WoW's raw binding names (BUTTON1-N).
-- Results are cached by raw input string (hotkeys rarely change; new bindings produce new keys).
local normalizeHotkeyCache = {}
local HOTKEY_NORMALIZE_PATTERNS = {
    { "^CTRL%-SHIFT[%-%+](.+)$", "CTRL-SHIFT-" },
    { "^CTRL%-ALT[%-%+](.+)$",   "CTRL-ALT-" },
    { "^SHIFT%-ALT[%-%+](.+)$",  "SHIFT-ALT-" },
    { "^SHIFT[%-%+](.+)$",       "SHIFT-" },
    { "^CTRL[%-%+](.+)$",        "CTRL-" },
    { "^ALT[%-%+](.+)$",         "ALT-" },
    { "^MOD%-(.+)$",             "MOD-" },

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
    -- 1) full-word forms with +/- separators (covers already-normalized input)
    -- 2) abbreviated forms with hyphen
    -- 3) compact abbreviated forms (no hyphen)
    -- 4) any-modifier form (+KEY)
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

-- Stock action-bar range glyph: an unbound button shows this dot, red, only while out of range.
local RANGE_INDICATOR = RANGE_INDICATOR or "\226\151\143"  -- "●"

local function SetIconHotkeyText(icon, hotkey, showHotkeys)
    if not icon or not icon.hotkeyText then return end
    local displayHotkey = showHotkeys and hotkey or ""
    -- An empty hotkey may be showing the out-of-range dot; UpdateRangeHotkeyColor owns that.
    if displayHotkey == "" and icon.hotkeyText:GetText() == RANGE_INDICATOR then return end
    if (icon.hotkeyText:GetText() or "") ~= displayHotkey then
        icon.hotkeyText:SetText(displayHotkey)
    end
end

local function SetIconNormalizedHotkey(icon, hotkey, trackPrevious)
    if not icon then return end
    if hotkey and hotkey ~= "" then
        local normalized = NormalizeHotkey(hotkey)
        if trackPrevious and icon.normalizedHotkey and icon.normalizedHotkey ~= normalized then
            icon.previousNormalizedHotkey = icon.normalizedHotkey
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
-- Scratch structs for the two numeric cooldown sources in UpdateButtonCooldowns -
-- consumed synchronously within one call, so one reusable table each replaces a
-- fresh allocation per icon per cooldown tick.
local itemCooldownScratch  = { startTime = 0, duration = 0, isEnabled = 1, modRate = 1, isActive = false }
local localCooldownScratch = { startTime = 0, duration = 0, isEnabled = 1, modRate = 1, isActive = false }

-- Release stage for an EMPOWERED cast, as a Roman numeral, or nil.
--
-- Roman rather than arabic because this shares the charge-count corner, and a bare "1"
-- next to a spell reads as "one charge left" - the single thing it must never be mistaken
-- for. No empowered spell has charges, so the two can never want the corner at the same
-- moment, and the caller only asks once the charge text has come back empty.
--
-- Static data (SimC's own `empower_to`), so this reads no combat state and is safe on the
-- render path.
local EMPOWER_NUMERAL = { "I", "II", "III", "IV" }
local function EmpowerNumeral(spellID)
    local tier = spellID and RotationImport and RotationImport.GetEmpowerTier
                 and RotationImport.GetEmpowerTier(spellID)
    return tier and (EMPOWER_NUMERAL[tier] or tostring(tier)) or nil
end

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
        -- Scratch struct (consumed synchronously below) - this ran per item icon per
        -- cooldown tick and allocated a fresh table each time.
        local ci = itemCooldownScratch
        ci.startTime, ci.duration = start or 0, duration or 0
        ci.isActive = (start or 0) > 0 and (duration or 0) > 0
        cooldownInfo = ci
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
            local ci = localCooldownScratch
            ci.startTime, ci.duration, ci.isActive = lStart, lDuration, true
            cooldownInfo = ci
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

    -- Slot-based fallback for charge text, used when the spell has no charges
    -- (maxCharges <= 1) or GetSpellCharges is unavailable.
    --
    -- MEASURED IN COMBAT: this returns a SECRET STRING. The comment here used to claim it
    -- was NeverSecret and always readable, and that was simply wrong - an attempt to test
    -- the result for emptiness threw 103 times in one fight. From this line on, chargeText
    -- may only be PASSED to SetText, never compared, tested for emptiness or concatenated.
    --
    -- The `== ""` guard on this line is the one survivor, and only by luck of TYPES: coming
    -- in, chargeText is either the plain "" or a secret NUMBER (currentCharges), and Lua
    -- settles a number-vs-string equality on the type mismatch without ever comparing the
    -- values. Same-type is what throws, which is exactly what a secret STRING would be. Do
    -- not copy this test to a point where chargeText could hold one.
    if chargeText == "" and directSlot and C_ActionBar_GetActionDisplayCount then
        chargeText = C_ActionBar_GetActionDisplayCount(directSlot)
    end

    -- An empowered cast's release stage takes the charge corner outright rather than
    -- filling it only when the count is empty. That is not a preference, it is the only
    -- legal shape: "is there a count to display" cannot be asked once chargeText is secret.
    -- Deciding by SPELL instead of by value keeps this entirely off the secret, and nothing
    -- real is displaced - an empowered ability has no charges to report.
    local empowerText = (not isItem) and EmpowerNumeral(cooldownID or id) or nil

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

    -- Apply charge / item count / empower-stage text.
    if button.chargeText then
        if empowerText then
            button.chargeText:SetText(empowerText)
        elseif isItem then
            local count = GetItemCount(id)
            button.chargeText:SetText(count and count > 1 and count or "")
        else
            -- Pass-through only: chargeText is a secret string in combat (see above).
            button.chargeText:SetText(chargeText)
        end
        button.chargeText:Show()
    end
end

local DEFAULT_QUEUE_DESATURATION = 0

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
-- Out of range is NOT an icon state: like the stock action bar, only the hotkey text
-- carries it (red), so the icon colour keeps meaning usability alone.

-- Defensive icons reuse the VS_* states/ApplyVisualState; WAITING is the one
-- defensive-only state (held-back emergency heal), painted by hand and kept
-- outside ApplyVisualState's range so leaving it always forces a repaint.
local VS_WAITING = 8

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
        if inRange ~= nil and BlizzardAPI.IsSecretValue(inRange) then inRange = nil end
    elseif BlizzardAPI.SpellInRange then
        inRange = BlizzardAPI.SpellInRange(spellID)   -- tri-state; owns the unit-arg finding
    end
    -- Fail open: only a confirmed false shows the red state.
    icon.cachedOutOfRange = (inRange == false)
    return icon.cachedOutOfRange
end

--- Update hotkey text color based on out-of-range state (stock action-bar style: the text
--- goes red; an empty hotkey becomes the RANGE_INDICATOR dot while out of range).
--- @param icon table  Icon button with .hotkeyText and .lastOutOfRange
--- @param isOutOfRange boolean
--- @param hotkeyColor table|nil  {r,g,b,a} from profile hotkey color
local function UpdateRangeHotkeyColor(icon, isOutOfRange, hotkeyColor)
    local text = icon.hotkeyText:GetText() or ""
    if text == "" or text == RANGE_INDICATOR then
        local want = isOutOfRange and RANGE_INDICATOR or ""
        if text ~= want then icon.hotkeyText:SetText(want) end
    end
    if icon.lastOutOfRange == isOutOfRange then return end
    if isOutOfRange then
        icon.hotkeyText:SetTextColor(1, 0, 0, 1)
    else
        local c = hotkeyColor
        icon.hotkeyText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1)
    end
    icon.lastOutOfRange = isOutOfRange
end

--- Fade a frame out, or hide it outright when it has no fade animation.
local function FadeOutOrHide(frame)
    if frame.fadeIn then frame.fadeIn:Stop() end
    if frame.fadeOut then frame.fadeOut:Play() else frame:Hide() end
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
    if profile.greyOutWhileCasting ~= false and PlayerCastingBarFrame and PlayerCastingBarFrame.channeling == true then
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
--- Out of range never reaches the icon - the hotkey text carries it (UpdateRangeHotkeyColor).
--- @param icon table  Icon button (caches cachedIsUsable/cachedNotEnoughResources)
--- @param spellID number
--- @param isChanneledSpell boolean
--- @param isCastedSpell boolean
--- @param isChanneling boolean
--- @param isCasting boolean
--- @param showStateTint boolean  "State Tint" setting (gray desat for unavailable)
--- @param inCombat boolean
--- @param directSlot number|nil  Action bar slot for slot-based usability
--- @return number visualState
local function ResolveVisualState(icon, spellID, isChanneledSpell, isCastedSpell,
                                  isChanneling, isCasting,
                                  showStateTint, inCombat, directSlot, currentTime)
    if isChanneledSpell or isCastedSpell then
        return VS_ACTIVE_CAST
    elseif isChanneling or isCasting then
        return VS_GREYED
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
            elseif showStateTint then
                return VS_UNAVAILABLE    -- on CD / wrong form → gray desat
            end
        end
    end
    return VS_NORMAL
end

--- Apply visual state colors/desaturation to an icon.
--- @param icon table  Icon button
--- @param visualState number  1-5
--- @param baseDesaturation number  Position-based desaturation
local function ApplyVisualState(icon, visualState, baseDesaturation)
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
    else  -- VS_NORMAL
        if changed then
            iconTexture:SetDesaturation(baseDesaturation)
            iconTexture:SetVertexColor(1, 1, 1)
        end
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
    if UIAnimations then UIAnimations.StopAllGlows(icon) end
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
    if isProc and (mode == "all" or mode == "procOnly") then
        -- A procced HEAL only glows while there is something to heal: at full
        -- health with nobody low, the "press me" burst is noise (field report:
        -- Clearcasting's free Regrowth bursting gold between pulls).
        -- IsHealingUnneeded is true only on a CERTAIN answer, so any doubt
        -- keeps the glow - failing toward the cue, never toward hiding one.
        -- The same gate orders the defensive list (DefensiveEngine), so glow
        -- and position can't disagree. Non-heal procs are untouched.
        local id = icon.currentID or icon.spellID
        if id and SpellDB and SpellDB.IsHealingSpell and SpellDB.IsHealingSpell(id)
            and BlizzardAPI.IsHealingUnneeded and BlizzardAPI.IsHealingUnneeded() then
            -- fall through: the icon keeps precombat/marching eligibility
        else
            return "proc"
        end
    end
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
        if defensiveIcon.lastVisualState ~= VS_WAITING then
            defensiveIcon.iconTexture:SetDesaturation(1.0)
            defensiveIcon.iconTexture:SetVertexColor(0.5, 0.5, 0.5)
            defensiveIcon.lastVisualState = VS_WAITING
        end
        return
    end

    -- Items use itemCastSpellID for channel/cast matching.
    local defID = defensiveIcon.isItem and defensiveIcon.itemCastSpellID or id
    local isDefActiveSpell = false
    if defID then
        local isChanneledSpell, isCastedSpell = MatchActiveCast(defID, isChanneling, channelSpellID, isCasting, castSpellID)
        isDefActiveSpell = isChanneledSpell or isCastedSpell
    end

    local isGreyingOut = (isChanneling or isCasting) and not isDefActiveSpell
    local defVisualState = isGreyingOut and VS_GREYED or VS_NORMAL
    if isDefActiveSpell then defVisualState = VS_ACTIVE_CAST end

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

    if defVisualState ~= VS_GREYED and not defensiveIcon.cachedDefUsable then
        if defensiveIcon.cachedDefNoResource then
            defVisualState = VS_NO_RESOURCES
        else
            defVisualState = VS_UNAVAILABLE
        end
    end

    ApplyVisualState(defensiveIcon, defVisualState, 0)

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
        local isProc = procCheckID and BlizzardAPI.IsSpellProcced(procCheckID) or false
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

--- Does the pet actually need the heal? DIRECT threshold gate, so the claim is
--- taken only when the pet is really below the configured percentage instead of
--- being taken always and hidden by engine alpha. Falls back to "not provably at
--- full" and then to the alpha curve below, which is the old behaviour.
local function PetNeedsHeal(profile)
    if not BlizzardAPI then return true end
    local pct = profile and profile.petHealThreshold
    if type(pct) ~= "number" then pct = PET_HEAL_DEFAULT_PCT end
    if BlizzardAPI.IsUnitHealthBelow then
        local below = BlizzardAPI.IsUnitHealthBelow("pet", pct)
        if below ~= nil then return below end
    end
    return not (BlizzardAPI.IsUnitFullHealth and BlizzardAPI.IsUnitFullHealth("pet") == true)
end

-- The health top-off icon used to drive its alpha through a multi-band health curve, so the
-- engine could express "emergency / top off / not needed" without us reading a secret. That
-- machinery is GONE: the zero-gate (BlizzardAPI.IsUnitFullHealth) now answers "are you at
-- full?" outright, and the reminder only ever needed that one bit. The icon is a plain
-- suggestion again - shown when offered, hidden when not, at normal opacity like every other
-- pre-combat entry. Do not reintroduce a curve here: it made this icon the only defensive
-- one with an engine-owned alpha, which the frame-opacity sweep at the end of RenderSpellQueue
-- then fought over (a visible flicker), and its band edges were never verifiable in Lua.

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
    -- Arm the glow once per display; only the alpha curve below needs re-applying
    -- per pass (target can change). Re-arming ran SetScale/Show/IsPlaying every pass.
    if not icon._executeCue then
        UIAnimations.ShowColoredProcGlow(icon, EXECUTE_GLOW_KEY,
            EXECUTE_GLOW.r, EXECUTE_GLOW.g, EXECUTE_GLOW.b)
        icon._executeCue = true
    end
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
    if UIMaintenanceAura then UIMaintenanceAura.Detach(icon) end
    UIAnimations.HideColoredProcGlow(icon, "maintenanceGlow")
    if icon.hasMaintenanceGlow then UIAnimations.StopMaintenanceGlow(icon) end
    icon:SetAlpha(0)
    icon._maintShown, icon._maintGlow, icon._maintID, icon.lastVisualState = false, nil, nil, nil
    icon.maintenanceAuraID = nil
    if icon.chargeText then icon.chargeText:Hide() end
end
UIRenderer.ClearMaintenanceSlot = ClearMaintenanceSlot

--- Render the defensive maintenance slot ("position 0" of the defensive queue).
--- The split that makes this work: the SWIPE shows the aura's real remaining time, drawn
--- by the engine from a DurationObject we never read, while our own logic only ever sees
--- the up/down/unknown boolean. So the player gets an exact timer for a value that is
--- secret to the addon.
--- Resolve a per-surface glow-mode value against the shared master. "shared" is a
--- storage sentinel that matches no mode string, so a site that forgets this resolve
--- silently disables every glow - one owner, consumed by both renderers and the
--- gap-closer options gate.
function UIRenderer.ResolveGlowMode(profile, mode)
    if mode == nil or mode == "shared" then
        return (profile and profile.glowMode) or "all"
    end
    return mode
end

-- Lazy module refs (these load after this file): resolved once, not per render pass.
local MaintenanceTrackerRef, DefensiveEngineRef, UIHealthBarRef

function UIRenderer.RenderMaintenanceSlot(addon, icon)
    if not icon then return end
    local MT = MaintenanceTrackerRef
    if not MT then
        MT = LibStub("JustAC-MaintenanceTracker", true)
        MaintenanceTrackerRef = MT
    end
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
        -- The swipe below is the CC's remaining time, not a buff's, so the engine-drawn aura
        -- displays must stand down or they would draw a second clock over it.
        if UIMaintenanceAura then UIMaintenanceAura.Detach(icon) end
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
        -- Always the burst, never the ants: being held is not an early warning. Stop the ants
        -- first in case the escape claimed a slot that was mid-warning - same escalation rule
        -- as the maintenance path below, and the states share one field.
        if icon._maintGlow ~= "burst" then
            if icon._maintGlow == "ants" then UIAnimations.StopMaintenanceGlow(icon) end
            UIAnimations.ShowColoredProcGlow(icon, "maintenanceGlow",
                MAINTENANCE_GLOW.r, MAINTENANCE_GLOW.g, MAINTENANCE_GLOW.b)
            icon._maintGlow = "burst"
        end
        return
    end

    -- EMERGENCY GROUP HEAL - the OH SHIT claimant. Several allies low at once: the biggest
    -- ready group cooldown takes the slot (Tranquility-class, press-and-done - targeted heals
    -- are out of scope by design). The claim is PLAIN (the ally-low count reads plain), so a
    -- normal `if` arbitrates: CC escape outranks it - you cannot cast while held - and it
    -- outranks the pet heal's secret alpha layer, the only legal ordering (plain above secret).
    local emergencyHealID
    if not ccSpellID then
        local DE = DefensiveEngineRef
        if not DE then
            DE = LibStub("JustAC-DefensiveEngine", true)
            DefensiveEngineRef = DE
        end
        if DE and DE.GetEmergencyHealID then
            emergencyHealID = DE.GetEmergencyHealID(addon)
        end
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
    -- Yield the slot when the pet is PROVABLY at full (zero-gate on its
    -- engine-side deficit). Before this the claim was taken unconditionally
    -- and the engine's alpha did the hiding - which is why it had to sit at
    -- the bottom of the claimant order, squatting invisibly on a slot another
    -- claimant could have used. nil (no answer) keeps the old behaviour.
    local petSpellID
    -- HasActionablePet, not UnitExists: a mounting hunter's dismissed pet lingers as an
    -- existing unit with 0 max health, which read as "needs healing" and lit this cue
    -- for a pet that was gone.
    if not ccSpellID and not emergencyHealID and profile and profile.showPetHealCue ~= false
       and profile.defensives and profile.defensives.enabled
       and BlizzardAPI.HasActionablePet and BlizzardAPI.HasActionablePet()
       and not UnitIsDeadOrGhost("pet")
       and PetNeedsHeal(profile) then
        local DE = DefensiveEngineRef
        if not DE then
            DE = LibStub("JustAC-DefensiveEngine", true)
            DefensiveEngineRef = DE
        end
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
    -- A pet-heal or emergency-heal claim makes the slot live on its own, as CC escape does.
    if petSpellID or emergencyHealID then active = true end
    local state, inst = "none", nil
    -- Plain assignment, NOT `local` - shadowing `state` here silently kills the glow.
    if active and entry and MT and MT.GetState then state, _, inst = MT.GetState() end

    -- Live if EITHER use has something to show. `entry` may legitimately be nil (CC escape with
    -- no maintenance buff), so it can no longer gate the whole slot.
    if not active or (not entry and not ccSpellID and not petSpellID and not emergencyHealID) then
        -- Guard the common case: this runs every render tick and inactive is the norm.
        if icon._maintShown then ClearMaintenanceSlot(icon) end
        return
    end

    -- No `or entry.aura` fallback: a future cast-less entry must fail loudly rather than run
    -- range and usability checks against an aura id.
    local displayID = ccSpellID or emergencyHealID or petSpellID or entry.cast

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

    -- ENGINE-DRAWN aura displays. An aura container watching this exact buff on the player
    -- renders its real remaining time and its real stack count, from untainted code, with no
    -- instance binding and no Cooldown Manager involved. Where it takes over, ours must stand
    -- down: two sweeps or two numbers on one button is worse than either alone.
    -- Only ever armed on the UPKEEP path. Every other claimant of this slot - escape, pet heal,
    -- emergency heal - draws its own ability's cooldown, which has nothing to do with the buff
    -- the container is watching; a charge-gated entry is refused inside Attach for the same
    -- reason. Returns false/false on any client or entry it cannot serve, and the ladders below
    -- are then untouched, which is why nothing here is gated on a version or a feature flag.
    local engineSweep, engineCount = false, false
    if UIMaintenanceAura then
        if entry and not (ccSpellID or petSpellID or emergencyHealID) then
            engineSweep, engineCount = UIMaintenanceAura.Attach(icon, entry)
        else
            UIMaintenanceAura.Detach(icon)
        end
    end

    if icon.cooldown then
        local applied = false
        if ccSpellID then
            -- The CC's OWN remaining time, engine-drawn: how long until you're free, which is
            -- the only clock that matters while you cannot act.
            if ccDurObj and icon.cooldown.SetCooldownFromDurationObject then
                pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, ccDurObj)
                applied = true
            end
        elseif petSpellID or emergencyHealID then
            -- The heal's OWN cooldown (Mend Pet / the emergency group heal). `entry` is nil on
            -- this path - every branch below reads it, which is why both heal claims are
            -- handled here rather than being allowed to fall through.
            if C_Spell and C_Spell.GetSpellCooldownDuration
               and icon.cooldown.SetCooldownFromDurationObject then
                local okD, durObj = pcall(C_Spell.GetSpellCooldownDuration, displayID, false)
                if okD and durObj then
                    pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durObj)
                    applied = true
                end
            end
        elseif engineSweep then
            -- The container is already drawing this buff's real remaining time. `applied` stays
            -- false on purpose, so our own cooldown is cleared below rather than left holding
            -- whatever the estimate last put there.
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
            local durObj = (not preferProjection) and exactBind and BlizzardAPI.GetAuraDurationObject
                           and BlizzardAPI.GetAuraDurationObject("player", inst) or nil
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
        if engineCount then
            shown = false   -- the container renders the true count on its own text
        elseif ccSpellID or petSpellID or emergencyHealID then
            shown = false   -- escape / pet heal / emergency heal have no meaningful count
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
    ApplyVisualState(icon, vs, 0)

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
    UpdateRangeHotkeyColor(icon, CheckSpellRange(icon, displayID, nil),
        profile.textOverlays and profile.textOverlays.hotkey and profile.textOverlays.hotkey.color)

    -- TWO stages, same blue, escalating: marching ants at the refresh threshold (~3s before
    -- decay), proc burst once the buff has actually lapsed.
    --
    -- An earlier two-stage attempt was rejected for being too quiet, and the fix is NOT that
    -- ants are louder than they were - it is that the two stages were mapped the wrong way
    -- round. The old version put the faint cue on "refresh" and the loud one on "down", so the
    -- moment you could still act on was the moment that whispered. Here the ants are an EARLY
    -- WARNING you may legitimately ignore for a couple of seconds, and the burst means you have
    -- already lost the buff - which is the state that deserves to shout.
    -- Not every entry reaches "refresh": charge-gated buffs never pre-warn, and Bone Shield has
    -- no clock at all (its stacks are eaten by damage, not time). Those go straight to the
    -- burst, exactly as they did before, so no spec loses its alarm.
    -- Same hue for both on purpose: one cue getting louder, not two signals to learn.
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
    -- nil | "ants" (early warning) | "burst" (gone). A claim on the slot by the escape, pet
    -- heal or emergency heal is always the loud one - none of those has a "soon" stage.
    local wantGlow
    if ccSpellID or petSpellID or emergencyHealID then
        wantGlow = "burst"
    elseif usable and ready then
        if state == "down" then wantGlow = "burst"
        elseif state == "refresh" then wantGlow = "ants" end
    end

    -- Marker cues, same rules as the other surfaces. Off-GCD is the valuable one here:
    -- Ignore Pain and Shield of the Righteous are off the global, so topping up your
    -- mitigation costs nothing from the rotation - exactly the call this slot exists to
    -- prompt. Always a spell, never an item or placeholder, so no markable gate is needed.
    ApplyCueDot(icon,
        MoveCastDotEnabled(profile) and IsMoveCastableNow(displayID, nil),
        profile and profile.showOffGcdDot and IsOffGCDSpell(displayID))
    if wantGlow ~= icon._maintGlow then
        -- Stop the outgoing stage before starting the incoming one: refresh -> down runs both
        -- branches on the same pass, and leaving the ants up under the burst reads as a third,
        -- muddier cue rather than an escalation.
        if icon._maintGlow == "ants" then
            UIAnimations.StopMaintenanceGlow(icon)
        elseif icon._maintGlow == "burst" then
            UIAnimations.HideColoredProcGlow(icon, "maintenanceGlow")
        end
        if wantGlow == "ants" then
            UIAnimations.StartMaintenanceGlow(icon, true)
        elseif wantGlow == "burst" then
            UIAnimations.ShowColoredProcGlow(icon, "maintenanceGlow",
                MAINTENANCE_GLOW.r, MAINTENANCE_GLOW.g, MAINTENANCE_GLOW.b)
        end
        icon._maintGlow = wantGlow
    end
end

-- glowModeOverride: overrides profile.defensives.glowMode (overlay has its own setting).
-- waiting: held-back emergency heal (above low-health threshold) - render desaturated
-- with a centered WAIT tag and no glow, instead of showing it as a live suggestion.
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon, showGlow, glowModeOverride, waiting, isPrecombatEntry)
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
        if not iconTexture then
            if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
            return
        end
    else
        -- Cached read: the raw C_Spell.GetSpellInfo allocates a fresh info table per
        -- call, and this runs per defensive icon per render pass on both surfaces.
        defSpellInfo = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(id)
        if not defSpellInfo then
            -- Not-yet-resolvable spell info (right after a reload, talent-override ids in
            -- particular) - the bail-out used to eat this render silently, leaving the
            -- slot at alpha 0 until the NEXT build, and out of combat that is the 1s
            -- idle timer, which on a fresh load did not tick until ~2.3s: the defensive
            -- cluster appeared seconds after the rotation. Mark dirty so the retry is
            -- next tick; nil is not cached, so the retry can succeed.
            if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
            return
        end
        iconTexture = defSpellInfo.iconID
    end
    
    defensiveIcon.currentID = id
    defensiveIcon.spellID = not isItem and id or nil
    defensiveIcon.itemID = isItem and id or nil
    defensiveIcon.isItem = isItem
    
    -- Item → cast-spell mapping is static per item; re-query on identity change,
    -- plus retry while nil - GetItemSpell returns nothing until the client has the
    -- item data cached, and latching that nil would strip the icon's hotkey
    -- fallback and cast matching for as long as it keeps the slot.
    if idChanged or (isItem and not defensiveIcon.itemCastSpellID) then
        defensiveIcon.itemCastSpellID = nil
        if isItem then
            local _, spellID = GetItemSpell(id)
            defensiveIcon.itemCastSpellID = spellID
        end
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
        defensiveIcon.lastVisualState = nil
    end

    -- Cooldown queries at the shared widget cadence, like every other icon path
    -- (RenderQueueIcon gates on spellChanged-or-tick) - this ran unthrottled per
    -- render pass, which on the overlay meant the full query chain at 20-33Hz.
    local cdNow = GetTime()
    if idChanged or (cdNow - (defensiveIcon.lastCdQueryTime or 0)) >= COOLDOWN_UPDATE_INTERVAL then
        defensiveIcon.lastCdQueryTime = cdNow
        UpdateButtonCooldowns(defensiveIcon)
    end

    -- Hotkey visibility and key-press flash are central settings (both surfaces).
    local defOverlays = addon.db and addon.db.profile and addon.db.profile.textOverlays
    local showHotkeys = not defOverlays or not defOverlays.hotkey or defOverlays.hotkey.show ~= false
    local showFlash = addon.db and addon.db.profile and addon.db.profile.showFlash ~= false
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
    SetIconNormalizedHotkey(defensiveIcon, hotkey, true)

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

    local profileForGlow = addon.db and addon.db.profile
    local defGlowMode = UIRenderer.ResolveGlowMode(profileForGlow, glowModeOverride
        or (profileForGlow and profileForGlow.defensives and profileForGlow.defensives.glowMode))

    defensiveIcon.defGlowMode = defGlowMode
    defensiveIcon.defShowGlow = showGlow

    local procCheckID = isItem and defensiveIcon.itemCastSpellID or id
    local isProc = procCheckID and BlizzardAPI.IsSpellProcced(procCheckID) or false

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
        defensiveIcon.lastVisualState = nil
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
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, showGlow, nil, entry.waiting, entry.precombat)
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
                if addon.defensiveFrame.fadeIn then
                    addon.defensiveFrame.fadeIn:Play()
                    addon.defensiveFrame.fadeInStartedAt = GetTime()
                end
            end
        elseif addon.defensiveFrame:IsShown() then
            FadeOutOrHide(addon.defensiveFrame)
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
        FadeOutOrHide(addon.defensiveFrame)
    end
end

-- Full interrupt-slot teardown for RenderInterruptSlot (the overlay keeps its
-- own lighter detach path that preserves slot state for re-attach).
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
    -- Retired mode in saved data → safe fallback (this is its only handler; other
    -- retired values are rewritten by the load-time migrations).
    if interruptMode == "importantOnly" then interruptMode = "kickOnly" end

    -- Hoisted out of the block below so the soothe cue can stand down for it. Plain, and it
    -- has to be: this is the ONLY legal direction for the arbitration (see the soothe note at
    -- the end of this function).
    local interruptShown = false

    if ctx.resolvedInterrupts and ctx.active and interruptMode ~= "disabled" then
        -- Shared evaluation: both renderers see identical state and share one debounce timer.
        local intResult           = CastInterruptTracker
            and CastInterruptTracker.EvaluateInterrupt(ctx.resolvedInterrupts, interruptMode, ctx.now)
            or { shouldShow = false, spellID = nil, castBar = nil, interruptMode = interruptMode }
        local shouldShowInterrupt = intResult.shouldShow
        local intSpellID          = intResult.spellID
        local castBar             = intResult.castBar

        -- De-dup: if the interrupt spell is already shown as queue position 1, skip it
        if shouldShowInterrupt and intSpellID and ctx.spellIDs and ctx.spellIDs[1] == intSpellID then
            shouldShowInterrupt = false
        end

        if shouldShowInterrupt and intSpellID then
            interruptShown = true
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
                SetIconNormalizedHotkey(intIcon, hotkey, false)
            end

            -- Red text = out of interrupt range (per-frame; IsSpellInRange is cheap).
            UpdateRangeHotkeyColor(intIcon, CheckSpellRange(intIcon, intSpellID, nil), ctx.hotkeyColor)

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
                -- Only alert for a suggestion we can be sure the player will SEE. A kick goes
                -- through the secret alpha sink below, so the engine - not us - decides whether
                -- it renders; on a non-interruptible cast it lands at alpha 0. When our
                -- interruptibility read was a fail-open guess rather than a definite answer
                -- (12.1.0 made UnitCastingInfo's notInterruptible secret, so the API fallback
                -- always guesses), that combination gives an alert for an invisible icon -
                -- reported in game as "ding but no icon". A CC takes the plain-alpha path and
                -- is always visible, so it always alerts.
                local sinkDecides = SpellDB and SpellDB.IsInterruptTypeSpell
                    and SpellDB.IsInterruptTypeSpell(intSpellID)
                local certainVisible = not sinkDecides
                    or (intResult.interruptibleKnown and intResult.interruptible ~= false)
                if CastInterruptTracker and certainVisible then
                    CastInterruptTracker.PlayInterruptAlertSound(ctx.profile)
                end
                intIcon:Show()
                -- Fresh display: force the diffed plain writes below to re-apply.
                intIcon.lastPlainAlpha, intIcon.lastIntDesat = nil, nil
            end
            local iconOpacity = ctx.opacity or 1.0
            -- Hide a KICK suggestion on a non-interruptible cast via the secret-aware alpha
            -- sink (works under any cast-bar addon; never reads the secret). A CC suggestion
            -- stays visible - CC is the correct call on a non-interruptible cast.
            if SpellDB and SpellDB.IsInterruptTypeSpell and SpellDB.IsInterruptTypeSpell(intSpellID) then
                BlizzardAPI.ApplyInterruptIconAlpha(intIcon, iconOpacity)
                -- The sink writes an unreadable alpha; the plain stamp is now stale.
                intIcon.lastPlainAlpha = nil
            else
                -- Plain value: only write on change (the secret-aware branch above
                -- must stay unconditional - its alpha can't be read back).
                if intIcon.lastPlainAlpha ~= iconOpacity then
                    intIcon.lastPlainAlpha = iconOpacity
                    intIcon:SetAlpha(iconOpacity)
                end
            end
            -- Grey the reminder (interrupt or CC) while it's on the GCD; off-GCD
            -- interrupts stay full-color since IsSpellOnGCD is false for them.
            local intDesat = BlizzardAPI.IsSpellOnGCD(intSpellID) and 1.0 or 0
            if intIcon.lastIntDesat ~= intDesat then
                intIcon.lastIntDesat = intDesat
                intIcon.iconTexture:SetDesaturation(intDesat)
            end
        elseif intIcon.spellID or intIcon:IsShown() then
            UIRenderer.HideInterruptIcon(intIcon)
        end
    elseif intIcon.spellID or intIcon:IsShown() then
        UIRenderer.HideInterruptIcon(intIcon)
    end

    -- Soothe (enrage-cleanse) cue: a sink-gated layer over the interrupt slot, visible only
    -- while the target is ENRAGED (dispel type 9). The cue self-gates on the enrage via its
    -- per-frame sink; here we only arm it when this character has a soothe ability.
    --
    -- IT YIELDS TO A LIVE INTERRUPT SUGGESTION, and never the other way round. Two reasons,
    -- and the second is the one that makes it a rule rather than a preference:
    --   * an enrage APPLIED BY the cast in progress does not exist yet, so a cue offered
    --     during that cast is telling the player to dispel something that is not on the
    --     target - while covering the kick or CC that would have stopped it landing at all;
    --   * these two claim the same square and the layering, not the logic, used to decide it.
    --     The soothe layer is SECRET (an aura we may not read), the interrupt suggestion is
    --     PLAIN, and a plain `if` can suppress a secret layer while the reverse is impossible.
    --     So plain-above-secret is the only ordering that can be expressed at all - see
    --     Documentation/AURA_CONTAINER_12.1.md on composing plain state with the secret.
    -- Hiding the whole container is the suppression, exactly as Show() already does for the
    -- cleanse's own cooldown: our frame, our decision, no sink involved.
    if UISootheCue then
        local sid = ctx.sootheSpellID
        if ctx.profile and ctx.profile.showSootheCue == false then sid = nil end
        if sid and ctx.active and not interruptShown then
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
local function ResolveGlowState(position, spellID, showPrimaryGlow, showProcGlow, showGapCloserGlow)
    local isSyntheticProc = SpellQueue.IsSyntheticProc and SpellQueue.IsSyntheticProc(spellID)
    if isSyntheticProc and showGapCloserGlow then return GLOW_GAP_CLOSER end
    -- Burst cues are only injected while profile.burstCueGlow is on (SpellQueue gates
    -- the populator), so the primary-glow policy is the only renderer-side check needed.
    local isBurstCue = SpellQueue.IsBurstCue and SpellQueue.IsBurstCue(spellID)
    if isBurstCue and showPrimaryGlow then return GLOW_BURST end
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
--   showPrimaryGlow / showProcGlow / showGapCloserGlow
--   queueDesaturation       desaturation applied to positions 2+
--   showHotkeys             hotkey text visible
--   lookupHotkeys           query spell hotkeys at all (text display or flash matching)
--   refreshHotkeys          force hotkey re-query this pass (bindings dirty / throttle)
--   hotkeyColor             profile hotkey color table (or nil)
--   showUsabilityTint / showCastingHighlight
--   isChanneling, channelSpellID, isCasting, castSpellID   player cast state
--   firstIconScale          per-surface scale for position 1 (nil = never touch scale)
--   opacity                 per-frame alpha (nil = never touch alpha)
--   hideEmptySlots          hide the button on an empty slot (overlay) instead of
--                           showing an empty placeholder slot (standard queue)
-- ─────────────────────────────────────────────────────────────────────────────
-- Icon info for a bar item, shaped like GetCachedSpellInfo's result.
-- Cached per itemID: item icons never change, and the uncached version allocated
-- a fresh table per item icon per render pass. A miss (icon not loaded yet) is
-- deliberately NOT negative-cached so it retries until the item data streams in.
local itemIconInfoCache = {}
local function ItemIconInfo(itemID)
    local cached = itemIconInfoCache[itemID]
    if cached then return cached end
    local itemIcon = GetItemIcon and GetItemIcon(itemID) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
    if not itemIcon then return nil end
    cached = { iconID = itemIcon }
    itemIconInfoCache[itemID] = cached
    return cached
end

--- Render slot 1 as the assist's WAIT state (sentinel path - GetNextCastSpell answered
--- nil in combat while the assist was available; see SpellQueue._StagePrimary). Same
--- presentation as the placeholder-spell wait the engine hands us directly (timer icon
--- 134377 + the WAIT label), so the two shapes are indistinguishable on screen.
local function RenderWaitSlot(icon, i, ctx)
    if icon.spellID or icon.currentID then
        UIAnimations.StopAllGlows(icon)
    end
    ClearExecuteCue(icon)
    if icon._hasChannelFill then UIAnimations.StopChannelFill(icon) end
    icon.spellID, icon.currentID, icon.isItem, icon.itemID = nil, nil, nil, nil
    icon.itemCastSpellID = nil
    icon.cachedHotkey = nil
    icon.isWaitingSpell = true
    local tex = icon.iconTexture
    if tex then
        tex:SetTexture(134377)
        if not tex:IsShown() then tex:Show() end
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1)
    end
    if icon.hotkeyText then icon.hotkeyText:SetText("") end
    if icon.centerText then
        icon.centerText:SetText(WAIT_LABEL)
        icon.centerText:Show()
    end
    if icon.cooldown then icon.cooldown:Clear() end
    if icon.chargeCooldown then icon.chargeCooldown:Clear() end
    -- Same surface plumbing as the normal path: without it an overlay slot hidden
    -- by hideEmptySlots last tick would keep the wait invisible, at stale scale/alpha.
    if ctx.firstIconScale then
        local targetScale = (i == 1) and ctx.firstIconScale or 1.0
        if icon:GetScale() ~= targetScale then icon:SetScale(targetScale) end
    end
    if not icon:IsShown() then icon:Show() end
    if ctx.opacity then icon:SetAlpha(ctx.opacity) end
end

local function RenderQueueIcon(icon, i, ctx)
    -- WAIT sentinel first: it is a number in item-id space, and everything below
    -- treats numeric ids as spells/items - this is the one consumer that knows it.
    if SpellQueue and ctx.spellIDs and ctx.spellIDs[i] == SpellQueue.WAIT_SENTINEL then
        RenderWaitSlot(icon, i, ctx)
        return
    end
    local currentTime = ctx.now
    local spellIDs = ctx.spellIDs
    local spellCount = ctx.hasSpells and #spellIDs or 0
    local spellID = ctx.hasSpells and spellIDs[i] or nil
    local isItemEntry = spellID and spellID < 0
    local itemID = isItemEntry and -spellID or nil
    local GetCachedSpellInfo = BlizzardAPI.GetCachedSpellInfo
    local spellInfo
    if isItemEntry then
        spellInfo = ItemIconInfo(itemID)
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
                    oldInfo = ItemIconInfo(-icon.spellID)
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
        local glowState = ResolveGlowState(i, spellID, ctx.showPrimaryGlow, ctx.showProcGlow, ctx.showGapCloserGlow)

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
            SetIconNormalizedHotkey(icon, hotkey, true)
        end

        -- Range/usability support: slot-based with spell fallback.
        local directSlot
        if isItemEntry then
            directSlot = ActionBarScanner.GetDirectSlotForItem and ActionBarScanner.GetDirectSlotForItem(itemID)
        else
            directSlot = ActionBarScanner.GetDirectSlotForSpell(spellID)
        end

        -- Range is hotkey-text only, stock action-bar style; always evaluated (cheap).
        UpdateRangeHotkeyColor(icon, CheckSpellRange(icon, spellID, directSlot), ctx.hotkeyColor)

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
            ctx.showUsabilityTint, ctx.inCombat, directSlot, currentTime)

        ApplyVisualState(icon, visualState, baseDesaturation)

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
    -- Clear the attached SIDE1 defensive row: the old fixed TOP+6 anchor drew the
    -- cue straight across it. Re-checked per pass (settings are runtime toggles);
    -- the SetPoint only fires when the lift actually changes.
    local UIHealthBar = UIHealthBarRef
    if not UIHealthBar then
        UIHealthBar = LibStub("JustAC-UIHealthBar", true)
        UIHealthBarRef = UIHealthBar
    end
    local lift = 6 + (UIHealthBar and UIHealthBar.AttachedDefRowDepth(profile) or 0)
    if cue.lastLift ~= lift then
        cue.lastLift = lift
        cue:SetPoint("BOTTOM", mf, "TOP", 0, lift)
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

--- On-screen cue for situational sets: a small tag above the panel naming every set
--- currently switched OFF, so hidden cooldowns are never silently hidden. Event-driven
--- (toggle, spec change) rather than per-frame - the state changes a few times a
--- session, not per tick. Hidden when every set is active.
function UIRenderer.RefreshSetIndicator(addon)
    local mf = addon and addon.mainFrame
    if not mf or not SpellQueue or not SpellQueue.IsSetActive then return end
    local off = {}
    for slot = 1, (SpellQueue.SET_SLOTS or 3) do
        if not SpellQueue.IsSetActive(slot) then
            off[#off + 1] = addon.GetSituationalSetName and addon:GetSituationalSetName(slot) or tostring(slot)
        end
    end
    if #off == 0 then
        if mf.jacSetTag then mf.jacSetTag:Hide() end
        return
    end
    if not mf.jacSetTag then
        local fs = mf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOMRIGHT", mf, "TOPRIGHT", 0, 2)
        fs:SetJustifyH("RIGHT")
        mf.jacSetTag = fs
    end
    mf.jacSetTag:SetText("|cffff8844" .. string.format(L["Set Off Tag"], table.concat(off, ", ")) .. "|r")
    mf.jacSetTag:Show()
end

--- Apply the panel interaction mode (unlocked / locked / clickthrough) to every mouse
--- surface: icon click registration, grab tabs, detached frame. Runs on mode CHANGE
--- from the render loop, and DIRECTLY from JustAC:TogglePanelLock - the render loop
--- early-returns while the display is paused (isManualMode), so a lock toggle from the
--- minimap button while paused would otherwise not hide/show the handles until unpause.
function UIRenderer.ApplyInteractionMode(addon, profile)
    if not (addon and profile) then return end
    local interactionMode = profile.panelInteraction or "unlocked"
    if lastPanelLocked == interactionMode then return end
    lastPanelLocked = interactionMode
    local isClickThrough = interactionMode == "clickthrough"
    local isLocked = interactionMode == "locked" or isClickThrough
    local spellIconsRef = addon.spellIcons or {}
    local maxIcons = profile.maxIcons or #spellIconsRef

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
    -- Grab tabs exist to drag the panel and to open the menu on right-click. Both are
    -- things a LOCKED panel must not offer, so the tabs are hidden whenever the panel
    -- is not plainly unlocked - locked as well as click-through. Locked used to keep
    -- them shown and mouse-enabled, so they still popped on hover and right-click
    -- still opened the options (user-reported). Shift+right-click on the panel body
    -- remains the way back out of a lock; nothing here removes it.
    if addon.grabTab then
        if isLocked then
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
        if isLocked then
            addon.defensiveGrabTab:Hide()
            addon.defensiveGrabTab:EnableMouse(false)
        else
            addon.defensiveGrabTab:Show()
            addon.defensiveGrabTab:EnableMouse(true)
        end
    end
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
    local queueDesaturation = profile.queueIconDesaturation or DEFAULT_QUEUE_DESATURATION
    local showUsabilityTint = profile.showUsabilityTint ~= false
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
            and profile.greyOutWhileCasting ~= false
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
                            SetIconNormalizedHotkey(defIcon, defHotkey, true)
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
                UIAnimations.StopAllGlows(icon)
                -- StopAllGlows doesn't know the execute cue's frameKey; without this
                -- the orange rim survives the hide with _executeCue still true.
                ClearExecuteCue(icon)
                if icon.spreadArrow and icon.spreadArrow:IsShown() then icon.spreadArrow:Hide() end
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
        ctx.queueDesaturation   = queueDesaturation
        ctx.showHotkeys         = showHotkeys
        ctx.lookupHotkeys       = showHotkeys or showFlash
        ctx.refreshHotkeys      = hotkeysDirty
        ctx.hotkeyColor         = textOverlays and textOverlays.hotkey and textOverlays.hotkey.color
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
                        addon.mainFrame.fadeInStartedAt = currentTime
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
    
    UIRenderer.ApplyInteractionMode(addon, profile)
    
    -- Skip if fade animation is playing to avoid interrupting it.
    local frameOpacity = profile.frameOpacity or 1.0
    if addon.mainFrame then
        local mf = addon.mainFrame
        local fadingIn = mf.fadeIn and mf.fadeIn:IsPlaying()
        -- A STALLED fade-in is not a fade-in. The animation is 0.1s, yet on a fresh
        -- reload the client leaves it "playing" at alpha 0 for ~3s (animation groups
        -- do not advance until the frame has been laid out once, and that first paint
        -- is deferred at load) - and this sweep politely deferred to it the whole time,
        -- so BOTH queues sat painted and invisible until the engine got round to it
        -- (traced live: parent alpha 0.00, fadeIn=true, from 0.07s to ~3.5s). Past a
        -- generous multiple of its own duration, stop the stalled group and set the
        -- alpha directly. Never touches a fade that is genuinely running.
        if fadingIn and mf.fadeInStartedAt and (currentTime - mf.fadeInStartedAt) > 0.5 then
            mf.fadeIn:Stop()
            fadingIn = false
        end
        local isFading = fadingIn or (mf.fadeOut and mf.fadeOut:IsPlaying())
        if not isFading then
            mf:SetAlpha(frameOpacity)
        end
    end
    -- Apply frameOpacity to the detached container (icons inherit) or all individual icons.
    if addon.defensiveFrame then
        local df = addon.defensiveFrame
        local fadingIn = df.fadeIn and df.fadeIn:IsPlaying()
        -- Same stalled-fade rescue as the main frame above.
        if fadingIn and df.fadeInStartedAt and (currentTime - df.fadeInStartedAt) > 0.5 then
            df.fadeIn:Stop()
            fadingIn = false
        end
        local isFading = fadingIn or (df.fadeOut and df.fadeOut:IsPlaying())
        if not isFading then
            df:SetAlpha(frameOpacity)
        end
    elseif addon.defensiveIcons then
        -- Blanket alpha write, on the MAIN queue's cadence rather than the defensive
        -- rebuild's. Nothing here may have an engine-driven alpha: this sweep would
        -- overwrite it on a different beat and the icon would flicker (that is exactly
        -- what the health top-off's old health curve did). Anything needing engine-owned
        -- alpha belongs outside this array, like the maintenance slot.
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
UIRenderer.RenderQueueIcon       = RenderQueueIcon
