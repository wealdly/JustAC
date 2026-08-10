-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: KeyPressDetector - Flash feedback when key/mouse press matches queued spell hotkey
local KPD = LibStub:NewLibrary("JustAC-KeyPressDetector", 2)
if not KPD then return end

local UIAnimations = LibStub("JustAC-UIAnimations", true)

-- Hot path cache
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local IsMouseButtonDown = IsMouseButtonDown
local wipe = wipe
local GetTime = GetTime
local ipairs = ipairs
local string_sub = string.sub
local string_match = string.match

-- Pooled table for key press flash matching (avoids GC pressure on every key press)
local iconsToFlash = {}

-- Grace period: accept previous hotkey briefly after spell changes
-- (user pressed key for the spell that just got cast, slot shifted)
local HOTKEY_GRACE_PERIOD = 0.20

-- Mouse button polling: detect down-transitions for flash matching.
-- OnKeyDown doesn't fire for mouse buttons, so we poll IsMouseButtonDown each frame.
-- Buttons 1-2 (left/right) are excluded: they fire constantly and are almost never
-- bound to combat spells. Buttons 3-5 cover middle-click and side buttons.
-- Gaming mice with extra buttons (6+) typically remap them to keyboard keys in driver
-- software, so WoW sees them as regular keyboard input handled by OnKeyDown.
local MOUSE_BUTTONS = {
    { api = "MiddleButton", binding = "BUTTON3" },
    { api = "Button4",      binding = "BUTTON4" },
    { api = "Button5",      binding = "BUTTON5" },
}
local prevMouseDown = {}

local function IsAnyModifierDown()
    return IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
end

local function HotkeyMatches(boundHotkey, pressedHotkey, hasAnyModifier)
    if not boundHotkey or not pressedHotkey then return false end
    if boundHotkey == pressedHotkey then return true end

    -- "+X" binds normalize to MOD-X (any modifier + key).
    -- Match when a modifier is held and the key portion matches.
    if hasAnyModifier and string_sub(boundHotkey, 1, 4) == "MOD-" then
        local pressedBase = string_match(pressedHotkey, "^[A-Z%-]+%-(.+)$")
        return pressedBase and string_sub(boundHotkey, 5) == pressedBase
    end

    return false
end

local function AddMatchedIcons(out, iconList, normalizedKey, hasAnyModifier)
    if not iconList then return end
    for _, icon in ipairs(iconList) do
        if icon and icon:IsShown() and HotkeyMatches(icon.normalizedHotkey, normalizedKey, hasAnyModifier) then
            out[#out + 1] = icon
        end
    end
end

-------------------------------------------------------------------------------
-- Build modifier key prefix from current keyboard state
-------------------------------------------------------------------------------
local function BuildModifierPrefix()
    local shift = IsShiftKeyDown()
    local ctrl = IsControlKeyDown()
    local alt = IsAltKeyDown()

    if ctrl and shift then
        return "CTRL-SHIFT-"
    elseif shift and alt then
        return "SHIFT-ALT-"
    elseif ctrl and alt then
        return "CTRL-ALT-"
    elseif shift then
        return "SHIFT-"
    elseif ctrl then
        return "CTRL-"
    elseif alt then
        return "ALT-"
    end
    return ""
end

-------------------------------------------------------------------------------
-- Create the key press detector frame
-------------------------------------------------------------------------------
function KPD.Create(addon)
    if addon.keyPressFrame then return end

    local frame = CreateFrame("Frame", "JustACKeyPressFrame", UIParent)
    addon.keyPressFrame = frame
    -- SetPropagateKeyboardInput is PROTECTED in combat (9.1.5+); the keyboard hook
    -- arms together with it further down - see ArmKeyboardHook.

    -- Cache function reference at creation time (avoid table lookup in hot path)
    local StartFlash = UIAnimations and UIAnimations.StartFlash

    ---------------------------------------------------------------------------
    -- Shared: match normalizedKey against all icon groups and flash matches
    ---------------------------------------------------------------------------
    local function MatchAndFlash(normalizedKey, hasAnyModifier)
        if not addon or not StartFlash then return end

        -- Reuse pooled table to avoid GC pressure
        wipe(iconsToFlash)
        local now = GetTime()
        local slot1PrevSpellID = nil

        local profile = addon.db and addon.db.profile

        -- Check offensive icons (if flash enabled)
        local spellIcons = addon.spellIcons
        if spellIcons and (not profile or profile.showFlash ~= false) then
            -- Check slot 1 first (special handling for spell change timing)
            local icon1 = spellIcons[1]
            if icon1 and icon1:IsShown() and icon1.spellID then
                -- Grace period uses spellChangeTime (not hotkeyChangeTime) because
                -- the hotkey often stays the same when spell changes (same action bar slot)
                local inGracePeriod = icon1.spellChangeTime and (now - icon1.spellChangeTime) < HOTKEY_GRACE_PERIOD
                if icon1.previousSpellID and inGracePeriod then
                    slot1PrevSpellID = icon1.previousSpellID
                end

                -- Match: current hotkey, previous hotkey, OR any match during grace period
                local matched = HotkeyMatches(icon1.normalizedHotkey, normalizedKey, hasAnyModifier)
                if not matched and inGracePeriod then
                    -- During grace period, also accept previous hotkey
                    -- (user pressed key for the spell that just got cast)
                    matched = HotkeyMatches(icon1.previousNormalizedHotkey, normalizedKey, hasAnyModifier)
                end
                if matched then
                    iconsToFlash[#iconsToFlash + 1] = icon1
                end
            end

            -- Check remaining slots
            for i = 2, #spellIcons do
                local icon = spellIcons[i]
                if icon and icon:IsShown() and icon.spellID then
                    -- Inline match check
                    local matched = HotkeyMatches(icon.normalizedHotkey, normalizedKey, hasAnyModifier)

                    -- Skip if same spell that was in slot 1 (just moved)
                    if matched and slot1PrevSpellID and icon.spellID == slot1PrevSpellID then
                        matched = false
                    end

                    if matched then
                        iconsToFlash[#iconsToFlash + 1] = icon
                    end
                end
            end
        end

        local showFlash = not profile or profile.showFlash ~= false

        -- Check defensive icons (flash uses central profile.showFlash)
        if showFlash then
            AddMatchedIcons(iconsToFlash, addon.defensiveIcons, normalizedKey, hasAnyModifier)

            -- Nameplate overlay icons
            AddMatchedIcons(iconsToFlash, addon.nameplateIcons, normalizedKey, hasAnyModifier)
            AddMatchedIcons(iconsToFlash, addon.nameplateDefIcons, normalizedKey, hasAnyModifier)
        end

        -- Standard queue interrupt icon is always eligible
        local intIcon = addon.interruptIcon
        if intIcon and intIcon:IsShown() and HotkeyMatches(intIcon.normalizedHotkey, normalizedKey, hasAnyModifier) then
            iconsToFlash[#iconsToFlash + 1] = intIcon
        end

        -- Flash all matched icons; stamp lastPressTime on pos1 so UIRenderer
        -- can hold its display briefly after a confirmed keypress (prevents the
        -- icon from visually changing right as the player commits to it).
        local now2 = GetTime()
        local overlayIcons = addon.nameplateIcons
        for _, icon in ipairs(iconsToFlash) do
            StartFlash(icon)
            -- Stamp lastPressTime on whichever surface's slot-1 icon matched so the
            -- renderer can hold its display briefly after a confirmed keypress.
            if icon == (spellIcons and spellIcons[1])
               or icon == (overlayIcons and overlayIcons[1]) then
                icon.lastPressTime = now2
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Keyboard detection (global via SetPropagateKeyboardInput)
    ---------------------------------------------------------------------------
    -- Propagation and the key hook arm TOGETHER: SetPropagateKeyboardInput is a
    -- protected call in combat (9.1.5+), and a /reload mid-fight re-runs OnEnable
    -- under lockdown. Arming the hook without propagation would swallow every
    -- keypress, so under lockdown both wait for combat exit (mouse-button flash
    -- via the OnUpdate poll below works throughout).
    local function ArmKeyboardHook()
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(_, key)
            if not addon or not StartFlash then return end

            -- Skip pure modifier keys early
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
                return
            end

            MatchAndFlash(BuildModifierPrefix() .. key:upper(), IsAnyModifierDown())
        end)
    end
    if InCombatLockdown() then
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(f)
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", nil)
            ArmKeyboardHook()
        end)
    else
        ArmKeyboardHook()
    end

    ---------------------------------------------------------------------------
    -- Mouse button detection (poll IsMouseButtonDown for down-transitions)
    -- OnKeyDown never fires for mouse buttons, so we detect state transitions
    -- each frame. Throttled to ~30Hz - max 33ms detection latency, which is
    -- imperceptible for flash feedback (human reaction time ~150-300ms).
    ---------------------------------------------------------------------------
    local mouseUpdateAccum = 0
    local MOUSE_POLL_INTERVAL = 0.033  -- ~30Hz
    frame:SetScript("OnUpdate", function(_, elapsed)
        mouseUpdateAccum = mouseUpdateAccum + elapsed
        if mouseUpdateAccum < MOUSE_POLL_INTERVAL then return end
        mouseUpdateAccum = 0

        if not addon or not StartFlash then return end

        for i, btn in ipairs(MOUSE_BUTTONS) do
            local down = IsMouseButtonDown(btn.api)
            if down and not prevMouseDown[i] then
                MatchAndFlash(BuildModifierPrefix() .. btn.binding, IsAnyModifierDown())
            end
            prevMouseDown[i] = down
        end
    end)
end
