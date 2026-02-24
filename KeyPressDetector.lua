-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: KeyPressDetector - Flash feedback when key press matches queued spell hotkey
local KPD = LibStub:NewLibrary("JustAC-KeyPressDetector", 1)
if not KPD then return end

local UIAnimations = LibStub("JustAC-UIAnimations", true)

-- Hot path cached globals
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local wipe = wipe
local GetTime = GetTime
local ipairs = ipairs

-- Pooled table for key press flash matching (avoids GC pressure on every key press)
local iconsToFlash = {}

-- Grace period: accept previous hotkey briefly after spell changes
-- (user pressed key for the spell that just got cast, slot shifted)
local HOTKEY_GRACE_PERIOD = 0.15

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

    frame:SetScript("OnKeyDown", function(_, key)
        if not addon or not StartFlash then return end

        -- Skip pure modifier keys early
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end

        -- Build normalized key with modifiers (matches format in UIRenderer)
        local modKey = ""
        local shift = IsShiftKeyDown()
        local ctrl = IsControlKeyDown()
        local alt = IsAltKeyDown()

        if ctrl and shift then
            modKey = "CTRL-SHIFT-"
        elseif shift and alt then
            modKey = "SHIFT-ALT-"
        elseif ctrl and alt then
            modKey = "CTRL-ALT-"
        elseif shift then
            modKey = "SHIFT-"
        elseif ctrl then
            modKey = "CTRL-"
        elseif alt then
            modKey = "ALT-"
        end

        local normalizedKey = modKey .. key:upper()

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

        -- Check defensive icons (if flash enabled)
        local defFlash = not profile or not profile.defensives or profile.defensives.showFlash ~= false
        if defFlash then
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

        -- Check nameplate DPS overlay icons (same flash logic as main queue)
        local npIcons = addon.nameplateIcons
        local npo = profile and profile.nameplateOverlay
        if npIcons and (not npo or npo.showFlash ~= false) then
            for _, npIcon in ipairs(npIcons) do
                if npIcon and npIcon:IsShown() and npIcon.normalizedHotkey == normalizedKey then
                    iconsToFlash[#iconsToFlash + 1] = npIcon
                end
            end
        end

        -- Check nameplate defensive overlay icons
        local npDefFlash = not npo or npo.showFlash ~= false
        if npDefFlash then
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
    end)
end
