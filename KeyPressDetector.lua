-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
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

-- Pooled table for key press flash matching (avoids GC pressure on every key press)
local iconsToFlash = {}

-- Grace period: accept previous hotkey briefly after spell changes
-- (user pressed key for the spell that just got cast, slot shifted)
local HOTKEY_GRACE_PERIOD = 0.15

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
    frame:SetPropagateKeyboardInput(true)
    addon.keyPressFrame = frame

    -- Cache function reference at creation time (avoid table lookup in hot path)
    local StartFlash = UIAnimations and UIAnimations.StartFlash

    ---------------------------------------------------------------------------
    -- Shared: match normalizedKey against all icon groups and flash matches
    ---------------------------------------------------------------------------
    local function MatchAndFlash(normalizedKey)
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
                local matched = icon1.normalizedHotkey == normalizedKey
                if not matched and inGracePeriod then
                    -- During grace period, also accept previous hotkey
                    -- (user pressed key for the spell that just got cast)
                    matched = icon1.previousNormalizedHotkey == normalizedKey
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
                    local matched = icon.normalizedHotkey == normalizedKey

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

        -- Check defensive icons (flash uses central profile.showFlash)
        local showFlash = not profile or profile.showFlash ~= false
        if showFlash then
            local defIcons = addon.defensiveIcons
            if defIcons then
                for _, defIcon in ipairs(defIcons) do
                    if defIcon and defIcon:IsShown() and defIcon.normalizedHotkey == normalizedKey then
                        iconsToFlash[#iconsToFlash + 1] = defIcon
                    end
                end
            end

            -- Legacy single defensive icon
            local defIcon = addon.defensiveIcon
            if defIcon and defIcon:IsShown() and defIcon.normalizedHotkey == normalizedKey then
                iconsToFlash[#iconsToFlash + 1] = defIcon
            end
        end

        -- Check standard queue interrupt icon
        local intIcon = addon.interruptIcon
        if intIcon and intIcon:IsShown() and intIcon.normalizedHotkey == normalizedKey then
            iconsToFlash[#iconsToFlash + 1] = intIcon
        end

        -- Check nameplate DPS overlay icons (flash uses central profile.showFlash)
        local npIcons = addon.nameplateIcons
        if npIcons and showFlash then
            for _, npIcon in ipairs(npIcons) do
                if npIcon and npIcon:IsShown() and npIcon.normalizedHotkey == normalizedKey then
                    iconsToFlash[#iconsToFlash + 1] = npIcon
                end
            end
        end

        -- Check nameplate defensive overlay icons
        if showFlash then
            local npDefIcons = addon.nameplateDefIcons
            if npDefIcons then
                for _, npDefIcon in ipairs(npDefIcons) do
                    if npDefIcon and npDefIcon:IsShown() and npDefIcon.normalizedHotkey == normalizedKey then
                        iconsToFlash[#iconsToFlash + 1] = npDefIcon
                    end
                end
            end
        end

        -- Flash all matched icons
        for _, icon in ipairs(iconsToFlash) do
            StartFlash(icon)
        end
    end

    ---------------------------------------------------------------------------
    -- Keyboard detection (global via SetPropagateKeyboardInput)
    ---------------------------------------------------------------------------
    frame:SetScript("OnKeyDown", function(_, key)
        if not addon or not StartFlash then return end

        -- Skip pure modifier keys early
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end

        MatchAndFlash(BuildModifierPrefix() .. key:upper())
    end)

    ---------------------------------------------------------------------------
    -- Mouse button detection (poll IsMouseButtonDown for down-transitions)
    -- OnKeyDown never fires for mouse buttons, so we detect state transitions
    -- each frame. Cost: 3 IsMouseButtonDown calls + 3 boolean comparisons/frame.
    ---------------------------------------------------------------------------
    frame:SetScript("OnUpdate", function()
        if not addon or not StartFlash then return end

        for i, btn in ipairs(MOUSE_BUTTONS) do
            local down = IsMouseButtonDown(btn.api)
            if down and not prevMouseDown[i] then
                MatchAndFlash(BuildModifierPrefix() .. btn.binding)
            end
            prevMouseDown[i] = down
        end
    end)
end
