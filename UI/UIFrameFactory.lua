-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Frame Factory Module - Creates and manages all UI frames and buttons
local UIFrameFactory = LibStub:NewLibrary("JustAC-UIFrameFactory", 15)
if not UIFrameFactory then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

-- Hot path cache
local wipe = wipe
local math_max = math.max
local math_floor = math.floor

-- Visual constants (shared with UIRenderer)
local HOTKEY_FONT_SCALE = 0.4
local HOTKEY_MIN_FONT_SIZE = 8
local HOTKEY_OFFSET_FIRST = -3
local HOTKEY_OFFSET_QUEUE = -2

-- Export constants for UIRenderer
UIFrameFactory.HOTKEY_FONT_SCALE = HOTKEY_FONT_SCALE
UIFrameFactory.HOTKEY_MIN_FONT_SIZE = HOTKEY_MIN_FONT_SIZE
UIFrameFactory.HOTKEY_OFFSET_FIRST = HOTKEY_OFFSET_FIRST
UIFrameFactory.HOTKEY_OFFSET_QUEUE = HOTKEY_OFFSET_QUEUE

-- Anchor presets for user-configurable text positions
-- Each preset: {ox=xOffset, oy=yOffset, jh=justifyH}
local HOTKEY_ANCHOR_PRESETS = {
    TOPRIGHT    = {ox = -2, oy = -2, jh = "RIGHT"},
    TOPLEFT     = {ox =  2, oy = -2, jh = "LEFT"},
    TOP         = {ox =  0, oy = -2, jh = "CENTER"},
    CENTER      = {ox =  0, oy =  0, jh = "CENTER"},
    BOTTOMRIGHT = {ox = -2, oy =  2, jh = "RIGHT"},
    BOTTOMLEFT  = {ox =  2, oy =  2, jh = "LEFT"},
}
local CHARGE_ANCHOR_PRESETS = {
    BOTTOMRIGHT = {ox = -4, oy = 4, jh = "RIGHT"},
    BOTTOMLEFT  = {ox =  4, oy = 4, jh = "LEFT"},
    BOTTOM      = {ox =  0, oy = 4, jh = "CENTER"},
}

-- Apply text overlay settings to a button.
-- overlaysBlock: the textOverlays sub-table (e.g. profile.textOverlays or
-- a merged block from MergeOverlayTextOverlays). Callers extract the correct block.
-- Handles font size (scale × base), color, and anchor for hotkey, cooldown, and charge text.
function UIFrameFactory.ApplyTextOverlaySettings(button, size, overlaysBlock)
    local overlays = overlaysBlock

    -- Hotkey text
    if button.hotkeyText then
        local cfg    = overlays and overlays.hotkey
        local scale  = (cfg and cfg.fontScale) or 1.0
        local fontSize = math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE * scale))
        button.hotkeyText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        local c = cfg and cfg.color
        button.hotkeyText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1)
        local anchor = (cfg and cfg.anchor) or "TOPRIGHT"
        local preset = HOTKEY_ANCHOR_PRESETS[anchor] or HOTKEY_ANCHOR_PRESETS.TOPRIGHT
        button.hotkeyText:ClearAllPoints()
        -- Anchor to hotkeyFrame (direct parent of hotkeyText) for reliable FontString positioning
        button.hotkeyText:SetPoint(anchor, button.hotkeyFrame, anchor, preset.ox, preset.oy)
        button.hotkeyText:SetJustifyH(preset.jh)
    end

    -- Cooldown countdown text
    if button.cooldownText then
        local cfg    = overlays and overlays.cooldown
        local scale  = (cfg and cfg.fontScale) or 1.0
        local font, _, flags = button.cooldownText:GetFont()
        if font then
            button.cooldownText:SetFont(font, math_floor(size * 0.25 * scale), flags)
        end
        local c = cfg and cfg.color
        button.cooldownText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 0.5)
    end

    -- Charge count text
    if button.chargeText then
        local cfg    = overlays and overlays.charges
        local scale  = (cfg and cfg.fontScale) or 1.0
        local fontSize = math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE * 0.65 * scale))
        button.chargeText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        local c = cfg and cfg.color
        button.chargeText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1)
        local anchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
        local preset = CHARGE_ANCHOR_PRESETS[anchor] or CHARGE_ANCHOR_PRESETS.BOTTOMRIGHT
        button.chargeText:ClearAllPoints()
        -- Anchor to hotkeyFrame (direct parent of chargeText) for reliable FontString positioning
        button.chargeText:SetPoint(anchor, button.hotkeyFrame, anchor, preset.ox, preset.oy)
        button.chargeText:SetJustifyH(preset.jh)
    end
end

--- Build a merged textOverlays block for the nameplate overlay.
--- Central show from profile.textOverlays; overlay-specific fontScale, color,
--- and anchor from nameplateOverlay.textOverlays with central fallback.
function UIFrameFactory.MergeOverlayTextOverlays(profile)
    if not profile then return nil end
    local central = profile.textOverlays
    if not central then return nil end
    local npoOv = profile.nameplateOverlay and profile.nameplateOverlay.textOverlays
    -- Build a shallow merged table for each sub-key
    local merged = {}
    for _, key in ipairs({"hotkey", "cooldown", "charges"}) do
        local c = central[key]
        local n = npoOv and npoOv[key]
        if c then
            merged[key] = {
                show      = c.show,
                fontScale = (n and n.fontScale) or (c and c.fontScale) or 1.0,
                color     = (n and n.color) or c.color,
                anchor    = (n and n.anchor) or c.anchor,
            }
        end
    end
    return merged
end

-- Panel interaction helpers
local function IsPanelLocked(profile)
    if not profile then return false end
    local mode = profile.panelInteraction
    if mode then return mode ~= "unlocked" end
    return profile.panelLocked or false  -- Legacy fallback
end

local function TogglePanelLock(profile)
    local mode = profile.panelInteraction or (profile.panelLocked and "locked" or "unlocked")
    if mode == "unlocked" then
        profile.panelInteraction = "locked"
    else
        profile.panelInteraction = "unlocked"
    end
    return profile.panelInteraction ~= "unlocked"
end

-- Local state
local spellIcons = {}
local defensiveIcons = {}  -- Array of defensive icon buttons (1-3)
local stdInterruptIcon = nil  -- Standard queue interrupt icon ("position 0")

-- Masque support (single group for all standard queue icons)
local Masque = LibStub("Masque", true)
local GetMasqueGroup

if Masque then
    local MasqueGroup = Masque:Group("JustAssistedCombat", "Standard Queue")

    GetMasqueGroup = function() return MasqueGroup end

    -- Re-apply text overlay settings after Masque re-skins (user changes skin).
    -- Masque's Skin_Text repositions HotKey; our ApplyTextOverlaySettings must
    -- override afterwards to restore user-configured anchors.
    local function OnStandardQueueSkinChanged(Group, Option)
        if Option ~= "SkinID" and Option ~= "Reset" and Option ~= "Disabled" then return end
        local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        if not addon or not addon.db then return end
        local profile = addon:GetProfile()
        if not profile then return end
        local overlays = profile.textOverlays
        local firstIconScale = profile.firstIconScale or 1.0
        for i, icon in ipairs(spellIcons) do
            if icon then
                local sz = (i == 1) and (profile.iconSize * firstIconScale) or profile.iconSize
                UIFrameFactory.ApplyTextOverlaySettings(icon, sz, overlays)
            end
        end
        if stdInterruptIcon then
            UIFrameFactory.ApplyTextOverlaySettings(stdInterruptIcon, profile.iconSize * firstIconScale, overlays)
        end
        local defScale = profile.defensives and profile.defensives.iconScale or 1.0
        local defSz = profile.iconSize * defScale
        for _, icon in ipairs(defensiveIcons) do
            if icon then
                UIFrameFactory.ApplyTextOverlaySettings(icon, defSz, overlays)
            end
        end
    end

    MasqueGroup:RegisterCallback(OnStandardQueueSkinChanged)
else
    GetMasqueGroup = function() return nil end
end

-- Helper: Build the shared icon skeleton used by both DPS and Defensive buttons.
-- Returns a button with all visual layers, cooldown frames, hotkey text and fade
-- animations pre-built.  Positioning is left to the caller.
--
-- Parameters:
--   parent       - parent Frame
--   size         - icon size in pixels
--   isClickable  - add Pushed/Highlight textures (false for nameplate icons)
--   isFirstIcon  - use HOTKEY_OFFSET_FIRST instead of HOTKEY_OFFSET_QUEUE
local function CreateBaseIcon(parent, size, isClickable, isFirstIcon, profile)
    local button = CreateFrame("Button", nil, parent)
    if not button then return nil end

    button:SetSize(size, size)

    if not isClickable then
        button:EnableMouse(false)
    end

    -- Slot background (Blizzard style depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    iconTexture:Hide()
    button.iconTexture = iconTexture

    -- Mask texture to clip rounded corners on all icon layers
    -- Applied to both slotBackground and iconTexture so neither bleeds outside the frame shape
    local maskPadding = math_floor(size * 0.17)
    local iconMask = button:CreateMaskTexture(nil, "ARTWORK")
    iconMask:SetPoint("TOPLEFT",     button, "TOPLEFT",     -maskPadding,  maskPadding)
    iconMask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",  maskPadding, -maskPadding)
    iconMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
    slotBackground:AddMaskTexture(iconMask)
    iconTexture:AddMaskTexture(iconMask)
    button.IconMask = iconMask

    -- Flash overlay (slightly outside the border, hidden until proc triggers it)
    local flashFrame = CreateFrame("Frame", nil, button)
    flashFrame:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    flashFrame:SetSize(size + 2, size + 2)
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 6)

    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetVertexColor(1.5, 1.2, 0.3, 1.0)
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()

    button.Flash = flashTexture
    button.FlashFrame = flashFrame
    button.flashing = 0
    button.flashtime = 0

    -- Cooldown container: SetClipsChildren clips swipe to icon bounds
    -- Glow effects are parented to button directly so they're NOT clipped
    local cooldownContainer = CreateFrame("Frame", nil, button)
    cooldownContainer:SetAllPoints(button)
    cooldownContainer:SetClipsChildren(true)
    button.cooldownContainer = cooldownContainer

    -- Main cooldown (spell CD or GCD, whichever is longer)
    local cooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    -- CooldownFrameTemplate sets setAllPoints="true" which anchors all 4 corners to the parent.
    -- ClearAllPoints removes those before we inset; without this, TOPRIGHT/BOTTOMLEFT from the
    -- template remain anchored to cooldownContainer (full button size) and override our inset.
    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      4, -4)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4,  4)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)   -- BlingTexture (star4 sparkle) renders outside frame bounds
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)

    -- Cooldown countdown text — stored for per-frame show/hide and ApplyTextOverlaySettings
    local cooldownText = cooldown:GetRegions()
    button.cooldownText = (cooldownText and cooldownText.SetFont) and cooldownText or nil

    cooldown:Clear()
    cooldown:Hide()
    button.cooldown = cooldown

    -- Charge cooldown (charge regen for multi-charge spells)
    local chargeCooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    chargeCooldown:ClearAllPoints()
    chargeCooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      4, -4)
    chargeCooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4,  4)
    -- Blizzard 12.0: charge cooldowns use the edge ring (not a swipe) to show recharge progress.
    -- SetDrawSwipe(true) causes a large dark polygon that bleeds outside the clipping container.
    -- The edge ring stays within icon bounds and is covered by borderFrame corners if it overflows.
    chargeCooldown:SetDrawSwipe(false) -- No dark swipe overlay; edge ring is the visual
    chargeCooldown:SetDrawEdge(true)   -- Edge ring shows recharge progress (matches Blizzard 12.0)
    chargeCooldown:SetDrawBling(false)
    chargeCooldown:SetHideCountdownNumbers(true)
    chargeCooldown:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    chargeCooldown:Clear()
    chargeCooldown:Hide()
    button.chargeCooldown = chargeCooldown

    -- Border overlay frame: sits ABOVE cooldowns (L+3) but BELOW glow animations (L+4+).
    -- The border texture's opaque corners physically cover any cooldown swipe corner bleed.
    -- NOTE: created after chargeCooldown so creation order puts it on top at the same level.
    local borderFrame = CreateFrame("Frame", nil, button)
    borderFrame:SetFrameLevel(button:GetFrameLevel() + 3)
    borderFrame:SetAllPoints(button)

    local normalTexture = borderFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    normalTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    normalTexture:SetSize(size, size)
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    button.borderFrame = borderFrame

    -- Casting highlight: shown while IsCurrentSpell is true for the displayed spell.
    -- Sits above the border (sublayer 1) but below glow animations (L+4+).
    local castingHighlight = borderFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    castingHighlight:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    castingHighlight:SetSize(size, size)
    castingHighlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    castingHighlight:SetVertexColor(1, 1, 1, 0.6)
    castingHighlight:Hide()
    button.castingHighlight = castingHighlight

    if isClickable then
        -- Pushed texture
        local pushedTexture = borderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        pushedTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
        pushedTexture:SetSize(size, size)
        pushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
        pushedTexture:Hide()
        button.PushedTexture = pushedTexture

        -- Highlight texture
        local highlightTexture = borderFrame:CreateTexture(nil, "HIGHLIGHT", nil, 0)
        highlightTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
        highlightTexture:SetSize(size, size)
        highlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        button.HighlightTexture = highlightTexture
    end
    -- Hotkey / overlay text (highest frame level to stay above animations)
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)

    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    local fontSize = math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE))
    hotkeyText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    hotkeyText:SetTextColor(1, 1, 1, 1)
    hotkeyText:SetJustifyH("RIGHT")
    local hotkeyOffset = isFirstIcon and HOTKEY_OFFSET_FIRST or HOTKEY_OFFSET_QUEUE
    hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", hotkeyOffset, hotkeyOffset)
    button.hotkeyText = hotkeyText
    button.hotkeyFrame = hotkeyFrame

    -- "WAIT" center indicator
    local centerText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 6)
    centerText:SetFont(STANDARD_TEXT_FONT, math_max(9, math_floor(size * 0.26)), "OUTLINE")
    centerText:SetTextColor(1, 0.9, 0.2, 1)
    centerText:SetJustifyH("CENTER")
    centerText:SetJustifyV("MIDDLE")
    centerText:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    centerText:SetText("")
    centerText:Hide()
    button.centerText = centerText

    -- Charge count (bottom-right, like Blizzard action bars)
    local chargeText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    chargeText:SetFont(STANDARD_TEXT_FONT,
        math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE * 0.65)),
        "OUTLINE")
    chargeText:SetTextColor(1, 1, 1, 1)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
    chargeText:SetText("")
    chargeText:Hide()
    button.chargeText = chargeText

    -- Fade-in / fade-out animations
    local fadeIn = button:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.1)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    button.fadeIn = fadeIn

    local fadeOut = button:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.1)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        button:Hide()
        button:SetAlpha(0)
    end)
    button.fadeOut = fadeOut

    -- State tracking fields
    button.spellID = nil
    button.itemID = nil
    button.itemCastSpellID = nil
    button.currentID = nil
    button.isItem = nil

    button._cooldownShown = false
    button._chargeCooldownShown = false
    button._cachedMaxCharges = nil
    button.castingHighlightShown = false

    button.normalizedHotkey = nil
    button.previousNormalizedHotkey = nil
    button.hotkeyChangeTime = nil
    button.spellChangeTime = nil
    button.cachedHotkey = nil

    button.hasAssistedGlow  = false
    button.hasInterruptGlow = false
    button.hasProcGlow      = false
    button.hasDefensiveGlow = false

    -- Do NOT set alpha to 0 here — defensive icons set it before showing via ShowDefensiveIcon,
    -- and DPS icons are shown directly via icon:Show() without a fadeIn:Play() call.
    button:Hide()

    -- NOTE: ApplyTextOverlaySettings is intentionally NOT called here.
    -- It must be called by each caller AFTER Masque:AddButton(), so our anchor
    -- overrides whatever position Masque's skin applies to the HotKey element.

    return button
end

-- Helper: Create a single defensive icon button at the specified index (0-based)
-- Position offset is calculated based on index, orientation, and defensive position.
-- When detached=true, parents to addon.defensiveFrame and lays out along detachedOrientation.
local function CreateSingleDefensiveButton(addon, profile, index, actualIconSize, defPosition, queueOrientation, spacing)
    local isDetached = profile.defensives and profile.defensives.detached
    local parentFrame = (isDetached and addon.defensiveFrame) or addon.mainFrame
    -- Build the shared icon skeleton (textures, cooldowns, hotkey text, animations)
    local button = CreateBaseIcon(parentFrame, actualIconSize, true, true, profile)
    if not button then return nil end

    -- Defensive-specific slot tracking
    button.iconIndex = index

    if isDetached then
        -- Detached mode: lay out along detachedOrientation within defensiveFrame.
        -- Mirrors the spell-icon layout in CreateSpellIcons.
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local iconOffset = index * (actualIconSize + spacing)
        local GRAB_TAB_LENGTH = 12
        -- Grab tab location per orientation:
        --   LEFT → tab at RIGHT  → icons start at LEFT, no reserve needed
        --   RIGHT → tab at LEFT  → icons start at RIGHT, no reserve needed
        --   UP   → tab at BOTTOM → icons start above tab, reserve at BOTTOM
        --   DOWN → tab at TOP    → icons start below tab, reserve at TOP
        local grabTabReserve = spacing + GRAB_TAB_LENGTH  -- used only for UP and DOWN
        if detachOrientation == "LEFT" then
            button:SetPoint("LEFT", parentFrame, "LEFT", iconOffset, 0)
        elseif detachOrientation == "RIGHT" then
            button:SetPoint("RIGHT", parentFrame, "RIGHT", -iconOffset, 0)
        elseif detachOrientation == "UP" then
            button:SetPoint("BOTTOM", parentFrame, "BOTTOM", 0, iconOffset + grabTabReserve)
        elseif detachOrientation == "DOWN" then
            button:SetPoint("TOP", parentFrame, "TOP", 0, -(iconOffset + grabTabReserve))
        end
    else
        -- Attached mode: position relative to mainFrame based on queue orientation and defensive position
        local firstIconCenter = actualIconSize / 2
        local baseSpacing = UIHealthBar and UIHealthBar.BAR_SPACING or 3
        local effectiveSpacing = math.max(spacing, baseSpacing)
        local iconOffset = index * (actualIconSize + spacing)

        -- For RIGHT/UP, icons are shifted within the frame to keep the grab tab at a
        -- predictable position (right for horizontal, bottom for vertical).
        -- Defensive icons must match that shift so they align with the queue icons.
        local grabTabReserve = 0
        if queueOrientation == "RIGHT" or queueOrientation == "UP" then
            local GRAB_TAB_LENGTH = 12
            local isVert = (queueOrientation == "UP")
            grabTabReserve = spacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
        end

        if queueOrientation == "LEFT" then
            if defPosition == "SIDE1" then
                button:SetPoint("BOTTOM", addon.mainFrame, "TOPLEFT", firstIconCenter + iconOffset, effectiveSpacing)
            elseif defPosition == "SIDE2" then
                button:SetPoint("TOP", addon.mainFrame, "BOTTOMLEFT", firstIconCenter + iconOffset, -effectiveSpacing)
            else -- LEADING
                button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -effectiveSpacing, iconOffset)
            end
        elseif queueOrientation == "RIGHT" then
            if defPosition == "SIDE1" then
                button:SetPoint("BOTTOM", addon.mainFrame, "TOPRIGHT", -firstIconCenter - iconOffset - grabTabReserve, effectiveSpacing)
            elseif defPosition == "SIDE2" then
                button:SetPoint("TOP", addon.mainFrame, "BOTTOMRIGHT", -firstIconCenter - iconOffset - grabTabReserve, -effectiveSpacing)
            else -- LEADING
                button:SetPoint("LEFT", addon.mainFrame, "RIGHT", effectiveSpacing, iconOffset)
            end
        elseif queueOrientation == "UP" then
            if defPosition == "SIDE1" then
                button:SetPoint("LEFT", addon.mainFrame, "BOTTOMRIGHT", effectiveSpacing, firstIconCenter + iconOffset + grabTabReserve)
            elseif defPosition == "SIDE2" then
                button:SetPoint("RIGHT", addon.mainFrame, "BOTTOMLEFT", -effectiveSpacing, firstIconCenter + iconOffset + grabTabReserve)
            else -- LEADING
                button:SetPoint("TOP", addon.mainFrame, "BOTTOM", iconOffset, -effectiveSpacing)
            end
        elseif queueOrientation == "DOWN" then
            if defPosition == "SIDE1" then
                button:SetPoint("LEFT", addon.mainFrame, "TOPRIGHT", effectiveSpacing, -firstIconCenter - iconOffset)
            elseif defPosition == "SIDE2" then
                button:SetPoint("RIGHT", addon.mainFrame, "TOPLEFT", -effectiveSpacing, -firstIconCenter - iconOffset)
            else -- LEADING
                button:SetPoint("BOTTOM", addon.mainFrame, "TOP", iconOffset, effectiveSpacing)
            end
        end
    end

    -- Tooltip handling
    button:SetScript("OnEnter", function(self)
        local tooltipMode = addon:GetProfile() and addon:GetProfile().tooltipMode or "outOfCombat"

        local inCombat = UnitAffectingCombat("player")
        local showTooltip = tooltipMode == "always" or (tooltipMode == "outOfCombat" and not inCombat)

        if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                
                if self.isItem and self.itemID then
                    GameTooltip:SetItemByID(self.itemID)
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                end
                
                if self.spellID or self.isItem then
                    local hotkey
                    local isOverride = false
                    if self.isItem and self.itemID then
                        hotkey = ActionBarScanner and ActionBarScanner.GetItemHotkey and ActionBarScanner.GetItemHotkey(self.itemID, self.itemCastSpellID) or ""
                        isOverride = addon:GetHotkeyOverride(-self.itemID) ~= nil
                    else
                        hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(self.spellID) or ""
                        isOverride = addon:GetHotkeyOverride(self.spellID) ~= nil
                    end
                    
                    if hotkey and hotkey ~= "" then
                        GameTooltip:AddLine(" ")
                        if isOverride then
                            GameTooltip:AddLine("|cffadd8e6Hotkey: " .. hotkey .. " (custom)|r")
                        else
                            GameTooltip:AddLine("|cff00ff00Hotkey: " .. hotkey .. "|r")
                        end
                        GameTooltip:AddLine("|cffffff00Press " .. hotkey .. " to cast|r")
                    else
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cffff6666No hotkey found|r")
                    end
                    
                    if not inCombat then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cff66ff66Right-click: Set custom hotkey|r")
                    end
                end

                GameTooltip:Show()
            end
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click for hotkey override
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if IsPanelLocked(profile) then return end

            if self.spellID and not self.isItem then
                addon:OpenHotkeyOverrideDialog(self.spellID)
            elseif self.isItem and self.itemID then
                addon:OpenHotkeyOverrideDialog(-self.itemID)
            end
        end
    end)

    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            ChargeCooldown = button.chargeCooldown,
            HotKey = button.hotkeyText,
            Count = button.chargeText,
            Normal = button.NormalTexture,
            Pushed = button.PushedTexture,
            Highlight = button.HighlightTexture,
        })
    end

    -- Apply text overlay settings AFTER Masque so our anchor overrides the skin's HotKey position.
    UIFrameFactory.ApplyTextOverlaySettings(button, actualIconSize, profile and profile.textOverlays)

    return button
end

-- Creates the detached defensive frame (UIParent child) with fade animations.
-- Mirrors CreateMainFrame pattern. Called by CreateDefensiveIcons when detached=true.
local function CreateDetachedDefensiveFrame(addon)
    -- Destroy any existing detached frame
    if addon.defensiveFrame then
        addon.defensiveFrame:Hide()
        addon.defensiveFrame:SetParent(nil)
        addon.defensiveFrame = nil
    end
    if addon.defensiveGrabTab then
        addon.defensiveGrabTab:Hide()
        addon.defensiveGrabTab:SetParent(nil)
        addon.defensiveGrabTab = nil
    end

    local profile = addon:GetProfile()
    if not profile then return end

    local frame = CreateFrame("Frame", "JustACDefensiveFrame", UIParent)
    if not frame then return end
    addon.defensiveFrame = frame

    -- Restore saved position
    local dpos = profile.defensives and profile.defensives.detachedPosition
    if dpos and dpos.point then
        frame:SetPoint(dpos.point, UIParent, dpos.point, dpos.x or 0, dpos.y or 100)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    frame:SetScript("OnLeave", function()
        if addon.defensiveGrabTab and addon.defensiveGrabTab.fadeOut
            and not addon.defensiveGrabTab:IsMouseOver()
            and not addon.defensiveGrabTab.isDragging then
            addon.defensiveGrabTab.fadeOut:Play()
        end
    end)

    frame:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if addon.OpenOptionsPanel then
                addon:OpenOptionsPanel()
            else
                Settings.OpenToCategory("JustAssistedCombat")
            end
        end
    end)

    -- Fade-in animation
    local fadeIn = frame:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.1)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function()
        local currentProfile = addon:GetProfile()
        local frameOpacity = currentProfile and currentProfile.frameOpacity or 1.0
        frame:SetAlpha(frameOpacity)
    end)
    frame.fadeIn = fadeIn

    -- Fade-out animation
    local fadeOut = frame:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.1)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(0)
    end)
    frame.fadeOut = fadeOut

    frame:SetAlpha(0)
    frame:Hide()
end

-- Creates the drag handle for the detached defensive frame.
-- Position based on detachedOrientation (mirrors CreateGrabTab for mainFrame).
local function CreateDefensiveGrabTab(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    local orientation = profile and profile.defensives and profile.defensives.detachedOrientation or "LEFT"
    local isVertical = (orientation == "UP" or orientation == "DOWN")

    local tab = CreateFrame("Button", nil, addon.defensiveFrame, "BackdropTemplate")
    if not tab then return end
    addon.defensiveGrabTab = tab

    if isVertical then
        tab:SetSize(20, 12)
    else
        tab:SetSize(12, 20)
    end
    tab:SetHitRectInsets(-6, -6, -6, -6)

    -- Grab tab sits at the "end" of the icon growth direction:
    --   LEFT  → icons grow left-to-right  → grab tab on RIGHT
    --   RIGHT → icons grow right-to-left  → grab tab on LEFT
    --   UP    → icons grow bottom-to-top  → grab tab on BOTTOM
    --   DOWN  → icons grow top-to-bottom  → grab tab on TOP
    if orientation == "LEFT" then
        tab:SetPoint("RIGHT", addon.defensiveFrame, "RIGHT", 0, 0)
    elseif orientation == "RIGHT" then
        tab:SetPoint("LEFT", addon.defensiveFrame, "LEFT", 0, 0)
    elseif orientation == "UP" then
        tab:SetPoint("BOTTOM", addon.defensiveFrame, "BOTTOM", 0, 0)
    elseif orientation == "DOWN" then
        tab:SetPoint("TOP", addon.defensiveFrame, "TOP", 0, 0)
    end

    tab:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    tab:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
    tab:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

    local dot1 = tab:CreateTexture(nil, "OVERLAY")
    dot1:SetSize(2, 2)
    dot1:SetColorTexture(0.8, 0.8, 0.8, 1)
    local dot2 = tab:CreateTexture(nil, "OVERLAY")
    dot2:SetSize(2, 2)
    dot2:SetColorTexture(0.8, 0.8, 0.8, 1)
    local dot3 = tab:CreateTexture(nil, "OVERLAY")
    dot3:SetSize(2, 2)
    dot3:SetColorTexture(0.8, 0.8, 0.8, 1)
    if isVertical then
        dot1:SetPoint("CENTER", tab, "CENTER", -4, 0)
        dot2:SetPoint("CENTER", tab, "CENTER",  0, 0)
        dot3:SetPoint("CENTER", tab, "CENTER",  4, 0)
    else
        dot1:SetPoint("CENTER", tab, "CENTER", 0,  4)
        dot2:SetPoint("CENTER", tab, "CENTER", 0,  0)
        dot3:SetPoint("CENTER", tab, "CENTER", 0, -4)
    end

    tab:EnableMouse(true)
    tab:RegisterForDrag("LeftButton")
    tab:RegisterForClicks("RightButtonUp")

    tab:SetScript("OnDragStart", function(self)
        local p = addon:GetProfile()
        if p and IsPanelLocked(p) then return end
        self.isDragging = true
        addon.isDragging = true
        if self.fadeOut and self.fadeOut:IsPlaying() then self.fadeOut:Stop() end
        if self.fadeIn  and self.fadeIn:IsPlaying()  then self.fadeIn:Stop()  end
        self:SetAlpha(1)
        addon.defensiveFrame:StartMoving(true)
    end)

    tab:SetScript("OnDragStop", function(self)
        addon.defensiveFrame:StopMovingOrSizing()
        UIFrameFactory.SaveDefensivePosition(addon)
        self.isDragging = false
        addon.isDragging = false
        if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end

        if not addon.defensiveFrame:IsMouseOver() and not self:IsMouseOver() and self.fadeOut then
            self.fadeOut:Play()
        end
    end)

    tab:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if addon.OpenOptionsPanel then
                addon:OpenOptionsPanel()
            else
                Settings.OpenToCategory("JustAssistedCombat")
            end
        end
    end)

    tab:SetScript("OnEnter", function(self)
        if self.fadeOut and self.fadeOut:IsPlaying() then self.fadeOut:Stop() end
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("JustAssistedCombat")
        GameTooltip:AddLine("Defensive Panel — Drag to move", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    tab:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not addon.defensiveFrame:IsMouseOver() and not self.isDragging and self.fadeOut then
            self.fadeOut:Play()
        end
    end)

    -- Fade animations
    local fadeIn = tab:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.15)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    tab.fadeIn = fadeIn

    local fadeOut = tab:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        tab:SetAlpha(0)
    end)
    tab.fadeOut = fadeOut

    tab:SetAlpha(0)
    tab:Show()
end

-- In click-through mode, icons become drag handles when Alt is held for the hold threshold.
-- A C_Timer delay filters out brief Alt taps used in macros so they never trigger drag mode.
-- Registered once on first CreateGrabTab call; re-calls are no-ops via addon.clickThroughModListener.
function UIFrameFactory.SetupClickThroughIconDrag(addon)
    if addon.clickThroughModListener then return end

    local altHoldTimer = nil
    local dragModeActive = false

    local function DisableIconDragMode()
        dragModeActive = false
        for _, icon in ipairs(addon.spellIcons or {}) do
            icon:EnableMouse(false)
            icon:RegisterForDrag()
            icon:SetScript("OnDragStart", nil)
            icon:SetScript("OnDragStop", nil)
        end
        for _, icon in ipairs(addon.defensiveIcons or {}) do
            icon:EnableMouse(false)
            icon:RegisterForDrag()
            icon:SetScript("OnDragStart", nil)
            icon:SetScript("OnDragStop", nil)
        end
    end

    local function EnableIconDragMode()
        dragModeActive = true
        for _, icon in ipairs(addon.spellIcons or {}) do
            icon:EnableMouse(true)
            icon:RegisterForDrag("LeftButton")
            icon:SetScript("OnDragStart", function()
                addon.isDragging = true
                addon.mainFrame:StartMoving(true)
            end)
            icon:SetScript("OnDragStop", function()
                addon.mainFrame:StopMovingOrSizing()
                addon.isDragging = false
                UIFrameFactory.SavePosition(addon)
                if addon.MarkQueueDirty then addon:MarkQueueDirty() end
                if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
                DisableIconDragMode()
            end)
        end
        for _, icon in ipairs(addon.defensiveIcons or {}) do
            icon:EnableMouse(true)
            icon:RegisterForDrag("LeftButton")
            icon:SetScript("OnDragStart", function()
                addon.isDragging = true
                if addon.defensiveFrame then addon.defensiveFrame:StartMoving(true) end
            end)
            icon:SetScript("OnDragStop", function()
                if addon.defensiveFrame then addon.defensiveFrame:StopMovingOrSizing() end
                addon.isDragging = false
                UIFrameFactory.SaveDefensivePosition(addon)
                if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
                DisableIconDragMode()
            end)
        end
    end

    local listener = CreateFrame("Frame")
    listener:RegisterEvent("MODIFIER_STATE_CHANGED")
    listener:SetScript("OnEvent", function()
        local p = addon:GetProfile()
        if not p then return end
        local mode = p.panelInteraction or (p.panelLocked and "locked" or "unlocked")
        if mode ~= "clickthrough" then
            if altHoldTimer then altHoldTimer:Cancel() altHoldTimer = nil end
            if dragModeActive then DisableIconDragMode() end
            return
        end
        if IsAltKeyDown() then
            if not altHoldTimer and not dragModeActive then
                altHoldTimer = C_Timer.NewTimer(0.4, function()
                    altHoldTimer = nil
                    if IsAltKeyDown() then EnableIconDragMode() end
                end)
            end
        else
            if altHoldTimer then altHoldTimer:Cancel() altHoldTimer = nil end
            if dragModeActive and not addon.isDragging then
                DisableIconDragMode()
            end
        end
    end)
    addon.clickThroughModListener = listener
end

function UIFrameFactory.SaveDefensivePosition(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end
    local point, _, _, x, y = addon.defensiveFrame:GetPoint()
    if not point then return end
    profile.defensives.detachedPosition = { point = point, x = x or 0, y = y or 100 }
end

function UIFrameFactory.UpdateDefensiveFrameSize(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local defOrientation = profile.defensives.detachedOrientation or "LEFT"
    local isVertical = (defOrientation == "UP" or defOrientation == "DOWN")
    local iconSize    = profile.iconSize or 42
    local iconScale   = profile.defensives.iconScale or 1.0
    local actualIconSize = iconSize * iconScale
    local iconSpacing = profile.iconSpacing or 1
    local maxIcons    = math.min(profile.defensives.maxIcons or 4, 7)

    local grabTabLength = 12
    local grabTabSpacing
    if isVertical then
        grabTabSpacing = iconSpacing + grabTabLength
    else
        grabTabSpacing = iconSpacing + grabTabLength + 1
    end

    local totalLength = maxIcons * actualIconSize + (maxIcons - 1) * iconSpacing

    if isVertical then
        addon.defensiveFrame:SetSize(actualIconSize, totalLength + grabTabSpacing)
    else
        addon.defensiveFrame:SetSize(totalLength + grabTabSpacing, actualIconSize)
    end
end

local function CreateDefensiveIcons(addon, profile)
    local StopDefensiveGlow = UIAnimations and UIAnimations.StopDefensiveGlow

    -- Preserve state before destroying old icons
    local savedStates = {}
    for i, icon in ipairs(defensiveIcons) do
        if icon and icon.currentID then
            savedStates[i] = {
                id = icon.currentID,
                isItem = icon.isItem,
                isShown = icon:IsShown(),
            }
        end
    end

    -- Cleanup all existing defensive icons
    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    for _, icon in ipairs(defensiveIcons) do
        if icon then
            if StopDefensiveGlow then StopDefensiveGlow(icon) end
            if MasqueGroup then MasqueGroup:RemoveButton(icon) end
            icon:Hide()
            icon:SetParent(nil)
        end
    end
    wipe(defensiveIcons)
    addon.defensiveIcons = nil
    addon.defensiveIcon = nil

    -- Always destroy the detached frame on rebuild; recreated below if still detached.
    if addon.defensiveFrame then
        addon.defensiveFrame:Hide()
        addon.defensiveFrame:SetParent(nil)
        addon.defensiveFrame = nil
    end
    if addon.defensiveGrabTab then
        addon.defensiveGrabTab:Hide()
        addon.defensiveGrabTab:SetParent(nil)
        addon.defensiveGrabTab = nil
    end

    if not profile.defensives or not profile.defensives.enabled then return end

    -- When detached, create the independent frame BEFORE parenting icons to it.
    local isDetached = profile.defensives.detached
    if isDetached then
        CreateDetachedDefensiveFrame(addon)
        if not addon.defensiveFrame then return end  -- frame creation failed
    end

    -- Calculate shared sizing
    local defensiveIconScale = profile.defensives.iconScale or 1.0
    local actualIconSize = profile.iconSize * defensiveIconScale
    local defPosition = profile.defensives.position or "SIDE1"
    local queueOrientation = profile.queueOrientation or "LEFT"
    local spacing = profile.iconSpacing

    -- Don't reuse module-level table to avoid stale reference issues.
    local maxIcons = profile.defensives.maxIcons or 4
    maxIcons = math.min(maxIcons, 7)  -- Cap at 7 (same as offensive queue)

    local newIcons = {}
    for i = 1, maxIcons do
        local button = CreateSingleDefensiveButton(addon, profile, i - 1, actualIconSize, defPosition, queueOrientation, spacing)
        if button then
            newIcons[i] = button
            defensiveIcons[i] = button  -- Also update module-level for cleanup on next call
        end
    end

    -- Expose to addon (use the fresh table, not the module-level one)
    addon.defensiveIcons = newIcons
    addon.defensiveIcon = newIcons[1]  -- Backward compatibility

    -- When detached, size the container frame and create its grab tab.
    if isDetached then
        UIFrameFactory.UpdateDefensiveFrameSize(addon)
        CreateDefensiveGrabTab(addon)
        -- Skip fade-in on first show after a rebuild so icons appear instantly.
        if addon.defensiveFrame then
            addon.defensiveFrame.skipNextFade = true
        end
    end

    local UIRenderer = LibStub("JustAC-UIRenderer", true)
    for i, state in pairs(savedStates) do
        if newIcons[i] and state.isShown and UIRenderer and UIRenderer.ShowDefensiveIcon then
            local showGlow = (i == 1)
            UIRenderer.ShowDefensiveIcon(addon, state.id, state.isItem, newIcons[i], showGlow)
        end
    end
end

function UIFrameFactory.CreateMainFrame(addon)
    local profile = addon:GetProfile()
    if not profile then return end
    
    addon.mainFrame = CreateFrame("Frame", "JustACFrame", UIParent)
    if not addon.mainFrame then return end
    
    UIFrameFactory.UpdateFrameSize(addon)
    
    local pos = profile.framePosition
    addon.mainFrame:SetPoint(pos.point, pos.x, pos.y)
    
    addon.mainFrame:EnableMouse(true)
    addon.mainFrame:SetMovable(true)   -- Required: grab tab delegates StartMoving() to mainFrame
    addon.mainFrame:SetClampedToScreen(true)
    
    addon.mainFrame:SetScript("OnEnter", function()
        -- intentionally empty: grab tab only appears on direct hover
    end)
    
    addon.mainFrame:SetScript("OnLeave", function()
        if addon.grabTab and addon.grabTab.fadeOut and not addon.grabTab:IsMouseOver() and not addon.grabTab.isDragging then
            addon.grabTab.fadeOut:Play()
        end
    end)
    
    -- Right-click on main frame (empty areas) for options
    -- Use OnMouseDown because the frame lacks RegisterForClicks support
    addon.mainFrame:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if not profile then return end
            
            if IsShiftKeyDown() then
                local nowLocked = TogglePanelLock(profile)
                local status = nowLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
            else
                if addon.OpenOptionsPanel then
                    addon:OpenOptionsPanel()
                else
                    Settings.OpenToCategory("JustAssistedCombat")
                end
            end
        end
    end)
    
    -- Start hidden to avoid showing an empty UI; fade in when spells appear
    addon.mainFrame:SetAlpha(0)  -- Start invisible for fade-in
    addon.mainFrame:Hide()
    
    -- Create fade-in animation
    local fadeIn = addon.mainFrame:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.1)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function()
        -- Apply user's frame opacity after fade completes
        local currentProfile = addon:GetProfile()
        local frameOpacity = currentProfile and currentProfile.frameOpacity or 1.0
        addon.mainFrame:SetAlpha(frameOpacity)
    end)
    addon.mainFrame.fadeIn = fadeIn

    -- Create fade-out animation
    local fadeOut = addon.mainFrame:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.1)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        addon.mainFrame:Hide()
        addon.mainFrame:SetAlpha(0)
    end)
    addon.mainFrame.fadeOut = fadeOut
end

function UIFrameFactory.CreateGrabTab(addon)
    addon.grabTab = CreateFrame("Button", nil, addon.mainFrame, "BackdropTemplate")
    if not addon.grabTab then return end
    
    local profile = addon:GetProfile()
    local orientation = profile and profile.queueOrientation or "LEFT"
    local isVertical = (orientation == "UP" or orientation == "DOWN")
    
    -- Swap dimensions for vertical orientations
    if isVertical then
        addon.grabTab:SetSize(20, 12)
    else
        addon.grabTab:SetSize(12, 20)
    end

    -- Extend the clickable hit area beyond the visible tab (negative insets = larger area)
    -- Makes the small tab much easier to grab, especially on high-DPI displays
    addon.grabTab:SetHitRectInsets(-6, -6, -6, -6)
    
    -- Predictable position: always at the right end (horizontal) or bottom (vertical).
    -- For RIGHT/UP orientations the icons are shifted within the frame to make room.
    if isVertical then
        addon.grabTab:SetPoint("BOTTOM", addon.mainFrame, "BOTTOM", 0, 0)
    else
        addon.grabTab:SetPoint("RIGHT", addon.mainFrame, "RIGHT", 0, 0)
    end
    
    addon.grabTab:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    
    addon.grabTab:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
    addon.grabTab:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    
    -- Dots arranged based on orientation (vertical vs horizontal grab tab)
    local dot1 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot1:SetSize(2, 2)
    dot1:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    local dot2 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot2:SetSize(2, 2)
    dot2:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    local dot3 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot3:SetSize(2, 2)
    dot3:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    if isVertical then
        -- Horizontal dot arrangement for vertical orientations
        dot1:SetPoint("CENTER", addon.grabTab, "CENTER", -4, 0)
        dot2:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 0)
        dot3:SetPoint("CENTER", addon.grabTab, "CENTER", 4, 0)
    else
        -- Vertical dot arrangement for horizontal orientations
        dot1:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 4)
        dot2:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 0)
        dot3:SetPoint("CENTER", addon.grabTab, "CENTER", 0, -4)
    end
    
    addon.grabTab:EnableMouse(true)
    addon.grabTab:RegisterForDrag("LeftButton")
    addon.grabTab:RegisterForClicks("RightButtonUp")
    
    addon.grabTab:SetScript("OnDragStart", function(self)
        local profile = addon:GetProfile()
        if not profile then return end
        
        -- Block dragging if locked
        if IsPanelLocked(profile) then
            return
        end
        
        -- Mark as dragging (addon-level for OnUpdate freeze, tab-level for fade logic)
        self.isDragging = true
        addon.isDragging = true
        
        -- Stop any fade animation and ensure fully visible
        if self.fadeOut and self.fadeOut:IsPlaying() then
            self.fadeOut:Stop()
        end
        if self.fadeIn and self.fadeIn:IsPlaying() then
            self.fadeIn:Stop()
        end
        self:SetAlpha(1)
        
        -- Detach from target frame anchor before dragging so position saves correctly
        if addon.targetframe_anchored then
            addon.targetframe_anchored = false
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
        end
        
        -- Move the main frame (grab tab follows since it's anchored to it)
        -- Use alwaysStartFromMouse=true to prevent offset when dragging from child frame
        addon.mainFrame:StartMoving(true)
    end)
    
    addon.grabTab:SetScript("OnDragStop", function(self)
        addon.mainFrame:StopMovingOrSizing()

        -- User manually dragged — auto-disable target frame anchor so it doesn't snap back
        local profile = addon:GetProfile()
        if profile and profile.targetFrameAnchor and profile.targetFrameAnchor ~= "DISABLED" then
            profile.targetFrameAnchor = "DISABLED"
            addon.targetframe_anchored = false
            if addon.DebugPrint then addon:DebugPrint("Target frame anchor auto-disabled (manual drag)") end
        end

        UIFrameFactory.SavePosition(addon)

        self.isDragging = false
        addon.isDragging = false

        -- Mark queues dirty so icons refresh immediately at new position
        if addon.MarkQueueDirty then addon:MarkQueueDirty() end
        if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end

        -- Fade out if mouse isn't over frame/tab
        if not addon.mainFrame:IsMouseOver() and not self:IsMouseOver() and self.fadeOut then
            self.fadeOut:Play()
        end
    end)
    
    addon.grabTab:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if IsShiftKeyDown() then
                -- Safe in combat: only modifies addon db, no restricted API calls
                local profile = addon:GetProfile()
                if profile then
                    local nowLocked = TogglePanelLock(profile)
                    local status = nowLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                end
            else
                if addon.OpenOptionsPanel then
                    addon:OpenOptionsPanel()
                else
                    Settings.OpenToCategory("JustAssistedCombat")
                end
            end
        end
    end)

    addon.grabTab:SetScript("OnEnter", function()
        if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
            addon.grabTab.fadeOut:Stop()
        end
        addon.grabTab:SetAlpha(1)

        local profile = addon:GetProfile()
        local isLocked = IsPanelLocked(profile)
        local interactionMode = profile and (profile.panelInteraction or (profile.panelLocked and "locked" or "unlocked"))

        GameTooltip:SetOwner(addon.grabTab, "ANCHOR_RIGHT")
        GameTooltip:SetText("JustAssistedCombat")
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        if isLocked then
            GameTooltip:AddLine("|cffff6666Panel Locked|r", 1, 1, 1)
            GameTooltip:AddLine("Shift+Right-click to unlock", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("|cff00ff00Panel Unlocked|r", 1, 1, 1)
            GameTooltip:AddLine("Shift+Right-click to lock", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    
    addon.grabTab:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Hide grab tab if mouse leaves and isn't over main frame or being dragged
        if not addon.mainFrame:IsMouseOver() and not self.isDragging and addon.grabTab.fadeOut then
            addon.grabTab.fadeOut:Play()
        end
    end)
    
    -- Create fade-in animation
    local fadeIn = addon.grabTab:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.15)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    addon.grabTab.fadeIn = fadeIn
    
    -- Create fade-out animation
    local fadeOut = addon.grabTab:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        -- Stay shown (alpha=0) so the frame keeps receiving mouse events
        addon.grabTab:SetAlpha(0)
    end)
    addon.grabTab.fadeOut = fadeOut
    
    -- Start invisible but shown so mouse detection works immediately
    addon.grabTab:SetAlpha(0)
    addon.grabTab:Show()

    -- Wire icon drag mode for click-through (once, guarded against re-registration).
    UIFrameFactory.SetupClickThroughIconDrag(addon)
end

-- Create a single interrupt icon positioned in the "leading" direction before slot 1.
-- The icon overhangs outside mainFrame (like defensive icons).
local function CreateInterruptIcon(addon, profile)
    -- Cleanup any existing interrupt icon
    if stdInterruptIcon then
        if UIAnimations then
            if stdInterruptIcon.hasInterruptGlow then UIAnimations.StopInterruptGlow(stdInterruptIcon) end
            if stdInterruptIcon.hasProcGlow      then UIAnimations.HideProcGlow(stdInterruptIcon)      end
        end
        local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
        if MasqueGroup then
            MasqueGroup:RemoveButton(stdInterruptIcon)
        end
        stdInterruptIcon:Hide()
        stdInterruptIcon:SetParent(nil)
        stdInterruptIcon = nil
    end
    addon.interruptIcon = nil
    addon.resolvedInterrupts = nil

    if (profile.interruptMode or "kickPrefer") == "disabled" then return end

    local firstIconScale = profile.firstIconScale or 1.0
    local actualIconSize = profile.iconSize * firstIconScale
    local orientation = profile.queueOrientation or "LEFT"
    local spacing = profile.iconSpacing or 1

    local button = CreateBaseIcon(addon.mainFrame, actualIconSize, true, true, profile)
    if not button then return end

    -- Position before slot 1 (opposite of queue growth direction)
    local baseSpacing = UIHealthBar and UIHealthBar.BAR_SPACING or 3
    local effectiveSpacing = math.max(spacing, baseSpacing)

    -- For RIGHT/UP, icon 1 is shifted inward by grabTabReserve to make room for
    -- the grab tab at the same edge.  We mirror that shift here so the interrupt
    -- sits adjacent to icon 1 (effectiveSpacing gap) rather than beyond the grab tab.
    if orientation == "LEFT" then
        -- Queue grows left-to-right; interrupt goes to the LEFT of mainFrame
        button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -effectiveSpacing, 0)
    elseif orientation == "RIGHT" then
        -- Queue grows right-to-left; interrupt adjacent to icon 1 (covers grab tab)
        local GRAB_TAB_LENGTH = 12
        local grabTabReserve = spacing + GRAB_TAB_LENGTH + 1
        button:SetPoint("LEFT", addon.mainFrame, "RIGHT", -(grabTabReserve - effectiveSpacing), 0)
    elseif orientation == "UP" then
        -- Queue grows bottom-to-top; interrupt adjacent to icon 1 (covers grab tab)
        local GRAB_TAB_LENGTH = 12
        local grabTabReserve = spacing + GRAB_TAB_LENGTH
        button:SetPoint("TOP", addon.mainFrame, "BOTTOM", 0, grabTabReserve - effectiveSpacing)
    elseif orientation == "DOWN" then
        -- Queue grows top-to-bottom; interrupt goes ABOVE mainFrame
        button:SetPoint("BOTTOM", addon.mainFrame, "TOP", 0, effectiveSpacing)
    end

    -- Ensure interrupt renders above the grab tab when they overlap (RIGHT/UP)
    button:SetFrameLevel(button:GetFrameLevel() + 5)

    -- Tooltip handling
    button:SetScript("OnEnter", function(self)
        if not self.spellID then return end

        local tooltipMode = addon:GetProfile() and addon:GetProfile().tooltipMode or "outOfCombat"

        local inCombat = UnitAffectingCombat("player")
        local showTooltip = tooltipMode == "always" or (tooltipMode == "outOfCombat" and not inCombat)

        if showTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)

            local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(self.spellID) or ""
            local isOverride = addon:GetHotkeyOverride(self.spellID) ~= nil

            if hotkey and hotkey ~= "" then
                GameTooltip:AddLine(" ")
                if isOverride then
                    GameTooltip:AddLine("|cffadd8e6Hotkey: " .. hotkey .. " (custom)|r")
                else
                    GameTooltip:AddLine("|cff00ff00Hotkey: " .. hotkey .. "|r")
                end
                GameTooltip:AddLine("|cffffff00Press " .. hotkey .. " to cast|r")
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffff6666No hotkey found|r")
            end

            if not inCombat then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff66ff66Right-click: Set custom hotkey|r")
            end

            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click for hotkey override
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if IsPanelLocked(profile) then return end

            if self.spellID then
                addon:OpenHotkeyOverrideDialog(self.spellID)
            end
        end
    end)

    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            ChargeCooldown = button.chargeCooldown,
            HotKey = button.hotkeyText,
            Count = button.chargeText,
            Normal = button.NormalTexture,
            Pushed = button.PushedTexture,
            Highlight = button.HighlightTexture,
        })
    end

    -- Apply text overlay settings AFTER Masque so our anchor overrides the skin's HotKey position.
    UIFrameFactory.ApplyTextOverlaySettings(button, actualIconSize, profile and profile.textOverlays)

    -- Cast aura: small icon showing what the enemy is casting, attached to
    -- the interrupt button.  Always placed on the side away from the queue
    -- so it doesn't overlap icon 1.
    local auraSize = math.floor(actualIconSize * 0.7)
    local castAura = CreateFrame("Frame", nil, button)
    castAura:SetSize(auraSize, auraSize)
    castAura:SetFrameLevel(button:GetFrameLevel() + 2)

    if orientation == "UP" then
        -- Queue grows upward, interrupt is below → aura goes further below
        castAura:SetPoint("TOP", button, "BOTTOM", 0, -2)
    else
        -- LEFT, RIGHT, DOWN → aura goes above interrupt (away from queue)
        castAura:SetPoint("BOTTOM", button, "TOP", 0, 2)
    end

    local auraIcon = castAura:CreateTexture(nil, "ARTWORK")
    auraIcon:SetAllPoints(castAura)
    castAura.iconTexture = auraIcon

    -- Rounded corner mask (matches queue icon style)
    local auraMaskPadding = math.floor(auraSize * 0.17)
    local auraMask = castAura:CreateMaskTexture(nil, "ARTWORK")
    auraMask:SetPoint("TOPLEFT",     castAura, "TOPLEFT",     -auraMaskPadding,  auraMaskPadding)
    auraMask:SetPoint("BOTTOMRIGHT", castAura, "BOTTOMRIGHT",  auraMaskPadding, -auraMaskPadding)
    auraMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
    auraIcon:AddMaskTexture(auraMask)

    local auraBorder = castAura:CreateTexture(nil, "OVERLAY")
    auraBorder:SetPoint("CENTER", castAura, "CENTER", 0.5, -0.5)
    auraBorder:SetSize(auraSize, auraSize)
    auraBorder:SetAtlas("UI-HUD-ActionBar-IconFrame")

    castAura.spellID = nil
    castAura:Hide()
    button.castAura = castAura

    button:Hide()  -- Hidden until an interruptible cast is detected

    stdInterruptIcon = button
    addon.interruptIcon = button
    addon.resolvedInterrupts = SpellDB.ResolveInterruptSpells()
end

function UIFrameFactory.CreateSpellIcons(addon)
    local profile = addon:GetProfile()
    if not profile or not addon.mainFrame then return end
    
    -- Remove old buttons from Masque before cleanup
    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    for i = 1, #spellIcons do
        if spellIcons[i] then
            if MasqueGroup then
                MasqueGroup:RemoveButton(spellIcons[i])
            end
            if spellIcons[i].cooldown then
                spellIcons[i].cooldown:Hide()
            end
            spellIcons[i]:Hide()
            spellIcons[i]:SetParent(nil)
        end
    end
    wipe(spellIcons)
    
    local orientation = profile.queueOrientation or "LEFT"
    
    -- For RIGHT/UP, reserve space at the icon-start edge so the grab tab
    -- can sit at a predictable position (right for horizontal, bottom for vertical)
    local currentOffset = 0
    if orientation == "RIGHT" or orientation == "UP" then
        local GRAB_TAB_LENGTH = 12
        local isVert = (orientation == "UP")
        currentOffset = profile.iconSpacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
    end
    
    for i = 1, profile.maxIcons do
        local button = UIFrameFactory.CreateSingleSpellIcon(addon, i, currentOffset, profile)
        if button then
            spellIcons[i] = button
            -- Consistent spacing between all icons
            currentOffset = currentOffset + button:GetWidth() + profile.iconSpacing
        end
    end
    
    addon.spellIcons = spellIcons
    
    -- Create interrupt icon (position 0, hidden until interruptible cast detected)
    CreateInterruptIcon(addon, profile)
    -- NOTE: CreateDefensiveIcons is called separately from UpdateFrameSize, not here,
    -- so that defensive icon creation is not gated by the mainFrame guard above.
end

-- SIMPLIFIED: Pure display-only icons with configuration only
function UIFrameFactory.CreateSingleSpellIcon(addon, index, offset, profile)
    local isFirstIcon = (index == 1)
    local firstIconScale = profile.firstIconScale or 1.0
    local actualIconSize = isFirstIcon and (profile.iconSize * firstIconScale) or profile.iconSize
    local orientation = profile.queueOrientation or "LEFT"

    local button = CreateBaseIcon(addon.mainFrame, actualIconSize, true, isFirstIcon, profile)
    if not button then return nil end

    -- Position based on orientation
    if orientation == "RIGHT" then
        button:SetPoint("RIGHT", -offset, 0)
    elseif orientation == "UP" then
        button:SetPoint("BOTTOM", 0, offset)
    elseif orientation == "DOWN" then
        button:SetPoint("TOP", 0, -offset)
    else -- LEFT (default)
        button:SetPoint("LEFT", offset, 0)
    end

    -- Right-click menu for configuration
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if IsPanelLocked(profile) then return end

            if self.spellID then
                if IsShiftKeyDown() then
                    addon:ToggleSpellBlacklist(self.spellID)
                else
                    addon:OpenHotkeyOverrideDialog(self.spellID)
                end
            else
                if IsShiftKeyDown() then
                    local nowLocked = TogglePanelLock(profile)
                    local status = nowLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                else
                    if addon.OpenOptionsPanel then
                        addon:OpenOptionsPanel()
                    else
                        Settings.OpenToCategory("JustAssistedCombat")
                    end
                end
            end
        end
    end)

    button:SetScript("OnEnter", function(self)
        if self.spellID then
            local tooltipMode = addon:GetProfile() and addon:GetProfile().tooltipMode or "outOfCombat"

            local inCombat = UnitAffectingCombat("player")
            local showTooltip = tooltipMode == "always" or (tooltipMode == "outOfCombat" and not inCombat)

            if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)

                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(self.spellID) or ""
                local isOverride = addon:GetHotkeyOverride(self.spellID) ~= nil

                if hotkey and hotkey ~= "" then
                    GameTooltip:AddLine(" ")
                    if isOverride then
                        GameTooltip:AddLine("|cffadd8e6Hotkey: " .. hotkey .. " (custom)|r")
                    else
                        GameTooltip:AddLine("|cff00ff00Hotkey: " .. hotkey .. "|r")
                    end
                    GameTooltip:AddLine("|cffffff00Press " .. hotkey .. " to cast|r")
                else
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffff6666No hotkey found|r")
                end

                if not inCombat then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff66ff66Right-click: Set custom hotkey|r")
                    local isBlacklisted = SpellQueue and SpellQueue.IsSpellBlacklisted and SpellQueue.IsSpellBlacklisted(self.spellID)
                    if isBlacklisted then
                        GameTooltip:AddLine("|cffff6666Shift+Right-click: Remove from blacklist|r")
                    else
                        GameTooltip:AddLine("|cffff6666Shift+Right-click: Add to blacklist (positions 2+ only)|r")
                    end
                end

                GameTooltip:Show()
            end
        end
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if addon.grabTab and addon.grabTab.fadeOut and not addon.mainFrame:IsMouseOver() and not addon.grabTab:IsMouseOver() and not addon.grabTab.isDragging then
            addon.grabTab.fadeOut:Play()
        end
    end)

    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            ChargeCooldown = button.chargeCooldown,
            HotKey = button.hotkeyText,
            Count = button.chargeText,
            Normal = button.NormalTexture,
            Pushed = button.PushedTexture,
            Highlight = button.HighlightTexture,
        })
    end

    -- Apply text overlay settings AFTER Masque so our anchor overrides the skin's HotKey position.
    UIFrameFactory.ApplyTextOverlaySettings(button, actualIconSize, profile and profile.textOverlays)

    return button
end

function UIFrameFactory.UpdateFrameSize(addon)
    local profile = addon:GetProfile()
    if not profile or not addon.mainFrame then return end

    local newMaxIcons = profile.maxIcons
    local newIconSize = profile.iconSize
    local newIconSpacing = profile.iconSpacing
    local firstIconScale = profile.firstIconScale or 1.0
    local orientation = profile.queueOrientation or "LEFT"

    UIFrameFactory.CreateSpellIcons(addon)
    -- Defensives are decoupled from CreateSpellIcons and always created here,
    -- so they are not gated by CreateSpellIcons's mainFrame guard.
    CreateDefensiveIcons(addon, profile)

    -- Recreate grab tab to update position/size for new orientation
    if addon.grabTab then
        addon.grabTab:Hide()
        addon.grabTab:SetParent(nil)
        addon.grabTab = nil
    end
    UIFrameFactory.CreateGrabTab(addon)

    local firstIconSize = newIconSize * firstIconScale
    local remainingIconsSize = (newMaxIcons > 1) and ((newMaxIcons - 1) * newIconSize) or 0
    local totalSpacing = (newMaxIcons > 1) and ((newMaxIcons - 1) * newIconSpacing) or 0
    local totalLength = firstIconSize + remainingIconsSize + totalSpacing
    
    -- Calculate grab tab spacing: always at least as large as icon spacing
    local isVertical = (orientation == "UP" or orientation == "DOWN")
    local grabTabLength = 12

    -- The normalTexture used for icon borders extends 1px beyond the button
    -- width which visually reduces the gap. We want the visual gap between
    -- the last icon and the grab tab to equal `newIconSpacing`.
    --
    -- Compute grabTabSpacing so that (grabTabSpacing - grabTabLength - visualOverflow) == newIconSpacing
    local visualOverflow = 1 -- visual overflow of icon borders
    local grabTabSpacing
    if isVertical then
        -- For vertical queues: spacing down/up should equal icon spacing + grab tab length
        grabTabSpacing = newIconSpacing + grabTabLength
    else
        -- For horizontal queues: account for 1px icon border overflow
        grabTabSpacing = newIconSpacing + grabTabLength + visualOverflow
    end

    -- Expand main frame to include grab tab area + consistent spacing
    if isVertical then
        addon.mainFrame:SetSize(firstIconSize, totalLength + grabTabSpacing)
    else
        addon.mainFrame:SetSize(totalLength + grabTabSpacing, firstIconSize)
    end
end

function UIFrameFactory.SavePosition(addon)
    if not addon.mainFrame then return end
    local profile = addon:GetProfile()
    if not profile then return end
    
    -- Guard: don't save while anchored to TargetFrame — GetPoint() would return
    -- TargetFrame-relative offsets which are meaningless as a saved position.
    if addon.targetframe_anchored then return end
    
    local point, _, _, x, y = addon.mainFrame:GetPoint()
    if not point then return end
    profile.framePosition = {
        point = point,
        x = x or 0,
        y = y or -150,
    }
end

-- Export public functions
UIFrameFactory.GetSpellIcons = function() return spellIcons end
