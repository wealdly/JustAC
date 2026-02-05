-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Frame Factory Module - Creates and manages all UI frames and buttons
local UIFrameFactory = LibStub:NewLibrary("JustAC-UIFrameFactory", 11)
if not UIFrameFactory then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
local ProfileHelpers = LibStub("JustAC-ProfileHelpers", true)

-- Cache frequently used functions to reduce table lookups on every update
local math_max = math.max
local math_floor = math.floor
local wipe = wipe

-- Visual constants (copied from UIManager.lua)
local HOTKEY_FONT_SCALE = 0.4
local HOTKEY_MIN_FONT_SIZE = 8
local HOTKEY_OFFSET_FIRST = -3
local HOTKEY_OFFSET_QUEUE = -2

-- Local state
local spellIcons = {}
local defensiveIcons = {}  -- Array of defensive icon buttons (1-3)

-- Forward declaration for UIManager access
local GetMasqueGroup, GetMasqueDefensiveGroup

-- Initialize Masque accessors (called by UIManager after module load)
function UIFrameFactory.InitializeMasqueAccessors(getMasqueGroupFunc, getMasqueDefensiveGroupFunc)
    GetMasqueGroup = getMasqueGroupFunc
    GetMasqueDefensiveGroup = getMasqueDefensiveGroupFunc
end

-- Helper: Create a single defensive icon button at the specified index (0-based)
-- Position offset is calculated based on index, orientation, and defensive position
local function CreateSingleDefensiveButton(addon, profile, index, actualIconSize, defPosition, queueOrientation, spacing, healthBarOffset)
    local button = CreateFrame("Button", nil, addon.mainFrame)
    if not button then return nil end

    button:SetSize(actualIconSize, actualIconSize)

    -- Cooldown container: clips cooldown swipes but glows parent to button directly (not clipped)
    local cooldownContainer = CreateFrame("Frame", nil, button)
    cooldownContainer:SetAllPoints(button)
    cooldownContainer:SetClipsChildren(true)
    button.cooldownContainer = cooldownContainer

    local firstIconCenter = actualIconSize / 2
    -- Use health bar offset for SIDE1 when health bar shown, otherwise use consistent base spacing
    -- Base spacing is BAR_SPACING (3px) minimum to visually separate from the queue
    local baseSpacing = UIHealthBar and UIHealthBar.BAR_SPACING or 3
    local effectiveSpacing = healthBarOffset > 0 and healthBarOffset or math.max(spacing, baseSpacing)
    
    -- Calculate offset for additional icons (index 0 has no offset)
    -- SIDE1/SIDE2: horizontal layout (along queue direction)
    -- LEADING: stacking layout (perpendicular to leading edge)
    local iconOffset = index * (actualIconSize + spacing)
    
    if queueOrientation == "LEFT" then
        -- Queue grows left-to-right (grab tab on right)
        if defPosition == "SIDE1" then
            -- SIDE1 = above (health bar side), icons grow rightward
            button:SetPoint("BOTTOM", addon.mainFrame, "TOPLEFT", firstIconCenter + iconOffset, effectiveSpacing)
        elseif defPosition == "SIDE2" then
            -- SIDE2 = below, icons grow rightward
            button:SetPoint("TOP", addon.mainFrame, "BOTTOMLEFT", firstIconCenter + iconOffset, -effectiveSpacing)
        else -- LEADING
            -- LEADING = left side, icons stack upward
            button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -effectiveSpacing, iconOffset)
        end
    elseif queueOrientation == "RIGHT" then
        -- Queue grows right-to-left (grab tab on left)
        if defPosition == "SIDE1" then
            -- SIDE1 = above, icons grow leftward
            button:SetPoint("BOTTOM", addon.mainFrame, "TOPRIGHT", -firstIconCenter - iconOffset, effectiveSpacing)
        elseif defPosition == "SIDE2" then
            -- SIDE2 = below, icons grow leftward
            button:SetPoint("TOP", addon.mainFrame, "BOTTOMRIGHT", -firstIconCenter - iconOffset, -effectiveSpacing)
        else -- LEADING
            -- LEADING = right side, icons stack upward
            button:SetPoint("LEFT", addon.mainFrame, "RIGHT", effectiveSpacing, iconOffset)
        end
    elseif queueOrientation == "UP" then
        -- Queue grows bottom-to-top (grab tab on top)
        if defPosition == "SIDE1" then
            -- SIDE1 = right side, icons grow upward
            button:SetPoint("LEFT", addon.mainFrame, "BOTTOMRIGHT", effectiveSpacing, firstIconCenter + iconOffset)
        elseif defPosition == "SIDE2" then
            -- SIDE2 = left side, icons grow upward
            button:SetPoint("RIGHT", addon.mainFrame, "BOTTOMLEFT", -effectiveSpacing, firstIconCenter + iconOffset)
        else -- LEADING
            -- LEADING = bottom side, icons stack rightward
            button:SetPoint("TOP", addon.mainFrame, "BOTTOM", iconOffset, -effectiveSpacing)
        end
    elseif queueOrientation == "DOWN" then
        -- Queue grows top-to-bottom (grab tab on bottom)
        if defPosition == "SIDE1" then
            -- SIDE1 = right side, icons grow downward
            button:SetPoint("LEFT", addon.mainFrame, "TOPRIGHT", effectiveSpacing, -firstIconCenter - iconOffset)
        elseif defPosition == "SIDE2" then
            -- SIDE2 = left side, icons grow downward
            button:SetPoint("RIGHT", addon.mainFrame, "TOPLEFT", -effectiveSpacing, -firstIconCenter - iconOffset)
        else -- LEADING
            -- LEADING = top side, icons stack rightward
            button:SetPoint("BOTTOM", addon.mainFrame, "TOP", iconOffset, effectiveSpacing)
        end
    end

    -- Slot background (Blizzard style depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground
    
    -- Slot art overlay (created but hidden to prevent visual artifacts)
    local slotArt = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    slotArt:SetAllPoints(button)
    slotArt:SetAtlas("ui-hud-actionbar-iconframe-slot")
    slotArt:Hide()

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    iconTexture:Hide()
    button.iconTexture = iconTexture
    
    -- Mask texture to clip icon corners
    local maskPadding = math_floor(actualIconSize * 0.17)
    local iconMask = button:CreateMaskTexture(nil, "ARTWORK")
    iconMask:SetPoint("TOPLEFT", button, "TOPLEFT", -maskPadding, maskPadding)
    iconMask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", maskPadding, -maskPadding)
    iconMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
    iconTexture:AddMaskTexture(iconMask)
    button.IconMask = iconMask
    
    -- Normal texture (button frame border)
    local normalTexture = button:CreateTexture(nil, "OVERLAY", nil, 0)
    normalTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    normalTexture:SetSize(actualIconSize, actualIconSize)
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    
    -- Pushed texture
    local pushedTexture = button:CreateTexture(nil, "OVERLAY", nil, 1)
    pushedTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    pushedTexture:SetSize(actualIconSize, actualIconSize)
    pushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
    pushedTexture:Hide()
    button.PushedTexture = pushedTexture
    
    -- Highlight texture
    local highlightTexture = button:CreateTexture(nil, "HIGHLIGHT", nil, 0)
    highlightTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    highlightTexture:SetSize(actualIconSize, actualIconSize)
    highlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    button.HighlightTexture = highlightTexture
    
    -- Flash overlay
    local flashFrame = CreateFrame("Frame", nil, button)
    flashFrame:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    flashFrame:SetSize(actualIconSize + 2, actualIconSize + 2)
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 10)  -- Higher level to ensure visibility
    
    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 7)  -- High sublevel on OVERLAY
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetVertexColor(1.5, 1.2, 0.3, 1.0)
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()
    
    button.Flash = flashTexture
    button.FlashFrame = flashFrame
    button.flashing = 0
    button.flashtime = 0

    -- Cooldown frames (matching Blizzard's ActionButtonTemplate structure)
    -- Parent to cooldownContainer so swipes are clipped to button bounds (glows parent to button, not clipped)
    -- Main cooldown frame (handles spell cooldown OR GCD, whichever is longer)
    local cooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 4, -4)
    cooldown:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", -4, 4)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)

    -- Make countdown numbers smaller and more transparent (don't overlap hotkey text)
    -- Access the countdown text region and modify its appearance
    local cooldownText = cooldown:GetRegions()
    if cooldownText and cooldownText.SetFont then
        local font, _, flags = cooldownText:GetFont()
        if font then
            local smallerSize = math_floor(actualIconSize * 0.25)  -- 25% of icon size (was ~33%)
            cooldownText:SetFont(font, smallerSize, flags)
            cooldownText:SetTextColor(1, 1, 1, 0.5)  -- 50% alpha (more transparent)
        end
    end

    -- Clear cooldown to prevent visual artifacts on load
    cooldown:Clear()
    cooldown:Hide()  -- Hide until a cooldown is actually set
    button.cooldown = cooldown

    -- Charge cooldown frame (shows charge regeneration for multi-charge spells)
    -- Same 4px inset as main cooldown to match Blizzard's ActionButtonTemplate
    local chargeCooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    chargeCooldown:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 4, -4)
    chargeCooldown:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", -4, 4)
    chargeCooldown:SetDrawEdge(true)
    chargeCooldown:SetDrawSwipe(true)
    chargeCooldown:SetHideCountdownNumbers(true)  -- No countdown numbers on charge cooldown
    chargeCooldown:SetFrameLevel(cooldown:GetFrameLevel() + 1)  -- Above main cooldown so edge is visible
    chargeCooldown:Clear()  -- Clear to prevent visual artifacts on load
    chargeCooldown:Hide()
    button.chargeCooldown = chargeCooldown
    
    -- Hotkey text
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)
    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    ProfileHelpers.ApplyHotkeyProfile(addon, hotkeyText, button, true)
    
    button.hotkeyText = hotkeyText
    button.hotkeyFrame = hotkeyFrame
    
    -- Center text for "WAIT" indicator
    local centerText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 6)
    local centerFontSize = math_max(9, math_floor(actualIconSize * 0.26))
    centerText:SetFont(STANDARD_TEXT_FONT, centerFontSize, "OUTLINE")
    centerText:SetTextColor(1, 0.9, 0.2, 1)
    centerText:SetJustifyH("CENTER")
    centerText:SetJustifyV("MIDDLE")
    centerText:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    centerText:SetText("")
    centerText:Hide()
    button.centerText = centerText
    
    -- Charge count text (bottom-right, like action bar charges)
    local chargeText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    ProfileHelpers.ApplyChargeTextProfile(addon, chargeText, button)
    
    chargeText:SetText("")
    chargeText:Hide()
    button.chargeText = chargeText

    -- State tracking
    button.lastCooldownStart = 0
    button.lastCooldownDuration = 0
    button.spellID = nil
    button.itemID = nil
    button.itemCastSpellID = nil
    button.currentID = nil
    button.isItem = nil
    button.iconIndex = index  -- Track which slot this is

    -- Tooltip handling
    button:SetScript("OnEnter", function(self)
        local tooltipMode = addon.db and addon.db.profile and addon.db.profile.tooltipMode
        -- Migration: handle old settings
        if not tooltipMode and addon.db and addon.db.profile then
            if addon.db.profile.showTooltips == false then
                tooltipMode = "never"
            elseif addon.db.profile.tooltipsInCombat then
                tooltipMode = "always"
            else
                tooltipMode = "outOfCombat"
            end
        end
        tooltipMode = tooltipMode or "outOfCombat"

        local inCombat = UnitAffectingCombat("player")
        local showTooltip = tooltipMode == "always" or (tooltipMode == "outOfCombat" and not inCombat)

        if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                
                if self.isItem and self.itemID then
                    GameTooltip:SetItemByID(self.itemID)
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                end
                
                if self.spellID or (self.isItem and self.itemCastSpellID) then
                    local lookupID = self.spellID or self.itemCastSpellID
                    local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(lookupID) or ""
                    local isOverride = self.spellID and addon:GetHotkeyOverride(self.spellID) ~= nil
                    
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
                    
                    if not inCombat and self.spellID and not self.isItem then
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
            if profile and profile.panelLocked then return end
            
            if self.spellID and not self.isItem then
                addon:OpenHotkeyOverrideDialog(self.spellID)
            end
        end
    end)

    -- Fade-in animation
    local fadeIn = button:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.15)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    button.fadeIn = fadeIn
    
    -- Fade-out animation
    local fadeOut = button:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        button:Hide()
        button:SetAlpha(0)
    end)
    button.fadeOut = fadeOut

    button:SetAlpha(0)
    button:Hide()
    
    -- Register with Masque if available
    local MasqueDefensiveGroup = GetMasqueDefensiveGroup and GetMasqueDefensiveGroup()
    if MasqueDefensiveGroup then
        MasqueDefensiveGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            HotKey = button.hotkeyText,
            Normal = button.NormalTexture,
        })
    end
    
    return button
end

-- Create multiple defensive icons (1-3 based on maxIcons setting)
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
    local MasqueDefensiveGroup = GetMasqueDefensiveGroup and GetMasqueDefensiveGroup()
    for _, icon in ipairs(defensiveIcons) do
        if icon then
            if StopDefensiveGlow then
                StopDefensiveGlow(icon)
            end
            if MasqueDefensiveGroup then
                MasqueDefensiveGroup:RemoveButton(icon)
            end
            icon:Hide()
            icon:SetParent(nil)
        end
    end
    wipe(defensiveIcons)
    addon.defensiveIcons = nil
    addon.defensiveIcon = nil
    
    if not profile.defensives or not profile.defensives.enabled then return end
    
    -- Calculate shared sizing
    local defensiveIconScale = profile.defensives.iconScale or 1.2
    local actualIconSize = profile.iconSize * defensiveIconScale
    local defPosition = profile.defensives.position or "SIDE1"
    local queueOrientation = profile.queueOrientation or "LEFT"
    local spacing = profile.iconSpacing
    
    -- Health bar offset calculation:
    -- Health bar bottom = BAR_SPACING above mainFrame
    -- Health bar top = BAR_SPACING + BAR_HEIGHT above mainFrame
    -- Defensive bottom = BAR_SPACING above health bar top
    -- So: defensive bottom = BAR_SPACING + BAR_HEIGHT + BAR_SPACING = BAR_HEIGHT + 2*BAR_SPACING
    -- Add 1px visual compensation for Blizzard's -0.5px texture offset on both elements
    local healthBarOffset = 0
    if profile.defensives.showHealthBar and UIHealthBar and defPosition == "SIDE1" then
        local barSpacing = UIHealthBar.BAR_SPACING
        local barHeight = UIHealthBar.BAR_HEIGHT
        healthBarOffset = barHeight + (barSpacing * 2)
    end
    
    -- Create maxIcons defensive buttons using a FRESH table
    -- (Don't reuse module-level table to avoid stale reference issues)
    local maxIcons = profile.defensives.maxIcons or 1
    maxIcons = math.min(maxIcons, 3)  -- Cap at 3
    
    local newIcons = {}
    for i = 1, maxIcons do
        local button = CreateSingleDefensiveButton(addon, profile, i - 1, actualIconSize, defPosition, queueOrientation, spacing, healthBarOffset)
        if button then
            newIcons[i] = button
            defensiveIcons[i] = button  -- Also update module-level for cleanup on next call
        end
    end
    
    -- Expose to addon (use the fresh table, not the module-level one)
    addon.defensiveIcons = newIcons
    addon.defensiveIcon = newIcons[1]  -- Backward compatibility
    
    -- Restore saved states
    local UIRenderer = LibStub("JustAC-UIRenderer", true)
    for i, state in pairs(savedStates) do
        if newIcons[i] and state.isShown and UIRenderer and UIRenderer.ShowDefensiveIcon then
            -- Only show glow on slot 1
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
    addon.mainFrame:SetMovable(true)
    addon.mainFrame:SetClampedToScreen(true)
    addon.mainFrame:RegisterForDrag("LeftButton")
    
    addon.mainFrame:SetScript("OnDragStart", function()
        local profile = addon:GetProfile()
        if profile and not profile.panelLocked then
            addon.mainFrame:StartMoving(true)  -- alwaysStartFromMouse = true
        end
    end)
    addon.mainFrame:SetScript("OnDragStop", function()
        addon.mainFrame:StopMovingOrSizing()
        UIFrameFactory.SavePosition(addon)
    end)
    
    -- Show/hide grab tab on hover
    addon.mainFrame:SetScript("OnEnter", function()
        if addon.grabTab and addon.grabTab.fadeIn then
            -- Stop any fade-out in progress
            if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
                addon.grabTab.fadeOut:Stop()
            end
            addon.grabTab:Show()
            addon.grabTab.fadeIn:Play()
        end
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
                -- Toggle lock
                profile.panelLocked = not profile.panelLocked
                local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
            else
                -- Open options panel
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
    fadeInAlpha:SetDuration(0.2)
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
    fadeOutAlpha:SetDuration(0.15)
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
    
    -- Position at the end of the queue based on orientation
    -- Grab tab goes at the trailing edge with no additional offset
    if orientation == "RIGHT" then
        -- Icons grow left from right edge, grab tab at left
        addon.grabTab:SetPoint("LEFT", addon.mainFrame, "LEFT", 0, 0)
    elseif orientation == "UP" then
        -- Icons grow down from bottom, grab tab at top
        addon.grabTab:SetPoint("TOP", addon.mainFrame, "TOP", 0, 0)
    elseif orientation == "DOWN" then
        -- Icons grow up from top, grab tab at bottom
        addon.grabTab:SetPoint("BOTTOM", addon.mainFrame, "BOTTOM", 0, 0)
    else -- LEFT (default)
        -- Icons grow right from left edge, grab tab at right
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
        if profile.panelLocked then
            return
        end
        
        -- Mark as dragging to prevent fade-out
        self.isDragging = true
        
        -- Stop any fade animation and ensure fully visible
        if self.fadeOut and self.fadeOut:IsPlaying() then
            self.fadeOut:Stop()
        end
        if self.fadeIn and self.fadeIn:IsPlaying() then
            self.fadeIn:Stop()
        end
        self:SetAlpha(1)
        
        -- Move the main frame (grab tab follows since it's anchored to it)
        -- Use alwaysStartFromMouse=true to prevent offset when dragging from child frame
        addon.mainFrame:StartMoving(true)
    end)
    
    addon.grabTab:SetScript("OnDragStop", function(self)
        addon.mainFrame:StopMovingOrSizing()
        UIFrameFactory.SavePosition(addon)
        
        -- Clear dragging flag and fade out if mouse isn't over frame/tab
        self.isDragging = false
        if not addon.mainFrame:IsMouseOver() and not self:IsMouseOver() and self.fadeOut then
            self.fadeOut:Play()
        end
    end)
    
    addon.grabTab:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if IsShiftKeyDown() then
                -- Shift+Right-click: toggle lock (safe in combat - only modifies addon db)
                local profile = addon:GetProfile()
                if profile then
                    profile.panelLocked = not profile.panelLocked
                    local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                end
            else
                -- Right-click: open options panel
                if addon.OpenOptionsPanel then
                    addon:OpenOptionsPanel()
                else
                    Settings.OpenToCategory("JustAssistedCombat")
                end
            end
        end
    end)
    
    addon.grabTab:SetScript("OnEnter", function()
        -- Stop any fade-out in progress and ensure fully visible
        if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
            addon.grabTab.fadeOut:Stop()
        end
        addon.grabTab:SetAlpha(1)
        
        local profile = addon:GetProfile()
        local isLocked = profile and profile.panelLocked
        
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
        addon.grabTab:Hide()
        addon.grabTab:SetAlpha(0)
    end)
    addon.grabTab.fadeOut = fadeOut
    
    -- Start hidden with alpha 0, show on hover
    addon.grabTab:SetAlpha(0)
    addon.grabTab:Hide()
end

function UIFrameFactory.CreateSpellIcons(addon)
    if not addon.db or not addon.db.profile or not addon.mainFrame then return end
    
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
    
    local profile = addon.db.profile
    local currentOffset = 0
    
    for i = 1, profile.maxIcons do
        local button = UIFrameFactory.CreateSingleSpellIcon(addon, i, currentOffset, profile)
        if button then
            spellIcons[i] = button
            -- Consistent spacing between all icons
            currentOffset = currentOffset + button:GetWidth() + profile.iconSpacing
        end
    end
    
    addon.spellIcons = spellIcons
    
    -- Create defensive icons (1-3 positioned relative to position 1 based on user settings)
    CreateDefensiveIcons(addon, profile)
end

-- SIMPLIFIED: Pure display-only icons with configuration only
function UIFrameFactory.CreateSingleSpellIcon(addon, index, offset, profile)
    local button = CreateFrame("Button", nil, addon.mainFrame)
    if not button then return nil end
    
    local isFirstIcon = (index == 1)
    local firstIconScale = profile.firstIconScale or 1.2
    local actualIconSize = isFirstIcon and (profile.iconSize * firstIconScale) or profile.iconSize
    local orientation = profile.queueOrientation or "LEFT"
    
    button:SetSize(actualIconSize, actualIconSize)
    
    -- Position based on orientation
    -- Icons start from one edge, grab tab is at the opposite edge
    if orientation == "RIGHT" then
        button:SetPoint("RIGHT", -offset, 0)
    elseif orientation == "UP" then
        button:SetPoint("BOTTOM", 0, offset)
    elseif orientation == "DOWN" then
        button:SetPoint("TOP", 0, -offset)
    else -- LEFT (default)
        button:SetPoint("LEFT", offset, 0)
    end

    -- Slot background (Blizzard style depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground
    
    -- Slot art overlay (created but hidden to prevent visual artifacts)
    local slotArt = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    slotArt:SetAllPoints(button)
    slotArt:SetAtlas("ui-hud-actionbar-iconframe-slot")
    slotArt:Hide()  -- Hidden: atlas texture was covering icon artwork on ARTWORK layer

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    -- Icon fills button completely
    iconTexture:SetAllPoints(button)
    button.iconTexture = iconTexture
    
    -- Mask texture to clip icon corners to beveled frame shape
    -- Padding scales with icon size (17% on each side compensates for atlas internal padding)
    local maskPadding = math_floor(actualIconSize * 0.17)
    local iconMask = button:CreateMaskTexture(nil, "ARTWORK")
    iconMask:SetPoint("TOPLEFT", button, "TOPLEFT", -maskPadding, maskPadding)
    iconMask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", maskPadding, -maskPadding)
    iconMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
    iconTexture:AddMaskTexture(iconMask)
    button.IconMask = iconMask
    
    -- Normal texture (button frame border - Blizzard style, centered)
    -- 0.5, -0.5 offset matches Blizzard's half-pixel alignment
    local normalTexture = button:CreateTexture(nil, "OVERLAY", nil, 0)
    normalTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    normalTexture:SetSize(actualIconSize, actualIconSize)
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    
    -- Pushed texture (shown when button is pressed - Blizzard style)
    local pushedTexture = button:CreateTexture(nil, "OVERLAY", nil, 1)
    pushedTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    pushedTexture:SetSize(actualIconSize, actualIconSize)
    pushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
    pushedTexture:Hide()
    button.PushedTexture = pushedTexture
    
    -- Highlight texture (shown on mouseover - Blizzard style)
    -- 0.5, -0.5 offset matches Blizzard's half-pixel alignment
    local highlightTexture = button:CreateTexture(nil, "HIGHLIGHT", nil, 0)
    highlightTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    highlightTexture:SetSize(actualIconSize, actualIconSize)
    highlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    button.HighlightTexture = highlightTexture
    
    -- Anchored at CENTER so scale animation grows evenly in all directions
    local flashFrame = CreateFrame("Frame", nil, button)
    flashFrame:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    flashFrame:SetSize(actualIconSize + 2, actualIconSize + 2)  -- Slightly larger than icon
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 6)
    
    -- Flash texture - uses Blizzard's mouseover atlas (beveled corners)
    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetVertexColor(1.5, 1.2, 0.3, 1.0)  -- Bright gold (values >1 boost ADD blend)
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()
    
    button.Flash = flashTexture
    button.FlashFrame = flashFrame
    
    button.flashing = 0
    button.flashtime = 0

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    -- Cooldown frames (matching Blizzard's ActionButtonTemplate structure)
    -- Main cooldown frame (handles spell cooldown OR GCD, whichever is longer)
    cooldown:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 4, -4)
    cooldown:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", -4, 4)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)

    -- Make countdown numbers smaller and more transparent (don't overlap hotkey text)
    -- Access the countdown text region and modify its appearance
    local cooldownText = cooldown:GetRegions()
    if cooldownText and cooldownText.SetFont then
        local font, _, flags = cooldownText:GetFont()
        if font then
            local smallerSize = math_floor(actualIconSize * 0.25)  -- 25% of icon size (was ~33%)
            cooldownText:SetFont(font, smallerSize, flags)
            cooldownText:SetTextColor(1, 1, 1, 0.5)  -- 50% alpha (more transparent)
        end
    end

    -- Clear cooldown to prevent visual artifacts on load
    cooldown:Clear()
    cooldown:Hide()  -- Hide until a cooldown is actually set
    button.cooldown = cooldown

    -- Charge cooldown frame (shows charge regeneration for multi-charge spells)
    -- Same 4px inset as main cooldown to match Blizzard's ActionButtonTemplate
    local chargeCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    chargeCooldown:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 4, -4)
    chargeCooldown:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", -4, 4)
    chargeCooldown:SetDrawEdge(true)
    chargeCooldown:SetDrawSwipe(true)
    chargeCooldown:SetHideCountdownNumbers(true)  -- No countdown numbers on charge cooldown
    chargeCooldown:SetFrameLevel(cooldown:GetFrameLevel() + 1)  -- Above main cooldown so edge is visible
    chargeCooldown:Clear()  -- Clear to prevent visual artifacts on load
    chargeCooldown:Hide()
    button.chargeCooldown = chargeCooldown
    
    -- Hotkey text on highest frame level to ensure visibility above all animations
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)  -- Above flash (+10)
    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    ProfileHelpers.ApplyHotkeyProfile(addon, hotkeyText, button, isFirstIcon)
    
    button.hotkeyText = hotkeyText
    button.hotkeyFrame = hotkeyFrame
    
    -- Center text for "WAIT" indicator when Assisted Combat suggests waiting for resources
    local centerText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 6)
    local centerFontSize = math_max(9, math_floor(actualIconSize * 0.26))
    centerText:SetFont(STANDARD_TEXT_FONT, centerFontSize, "OUTLINE")
    centerText:SetTextColor(1, 0.9, 0.2, 1)  -- Gold/yellow color
    centerText:SetJustifyH("CENTER")
    centerText:SetJustifyV("MIDDLE")
    centerText:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    centerText:SetText("")
    centerText:Hide()
    button.centerText = centerText
    
    -- Charge count text (bottom-right, like action bar charges)
    local chargeText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    ProfileHelpers.ApplyChargeTextProfile(addon, chargeText, button)
    
    chargeText:SetText("")
    chargeText:Hide()
    button.chargeText = chargeText



    -- Enable dragging from icons (delegates to main frame)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        local profile = addon:GetProfile()
        if not profile or profile.panelLocked then return end
        addon.mainFrame:StartMoving(true)  -- alwaysStartFromMouse = true
    end)
    
    button:SetScript("OnDragStop", function(self)
        addon.mainFrame:StopMovingOrSizing()
        UIFrameFactory.SavePosition(addon)
    end)
    
    -- Right-click menu for configuration
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if profile and profile.panelLocked then return end
            
            if self.spellID then
                -- Spell-specific options
                if IsShiftKeyDown() then
                    addon:ToggleSpellBlacklist(self.spellID)
                else
                    addon:OpenHotkeyOverrideDialog(self.spellID)
                end
            else
                -- Empty slot - show general options
                if IsShiftKeyDown() then
                    -- Toggle lock
                    profile.panelLocked = not profile.panelLocked
                    local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                else
                    -- Open options panel
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
        -- Show grab tab when hovering over icons
        if addon.grabTab and addon.grabTab.fadeIn then
            -- Stop any fade-out in progress
            if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
                addon.grabTab.fadeOut:Stop()
            end
            addon.grabTab:Show()
            addon.grabTab.fadeIn:Play()
        end
        
        if self.spellID then
            local tooltipMode = addon.db and addon.db.profile and addon.db.profile.tooltipMode
            -- Migration: handle old settings
            if not tooltipMode and addon.db and addon.db.profile then
                if addon.db.profile.showTooltips == false then
                    tooltipMode = "never"
                elseif addon.db.profile.tooltipsInCombat then
                    tooltipMode = "always"
                else
                    tooltipMode = "outOfCombat"
                end
            end
            tooltipMode = tooltipMode or "outOfCombat"

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
                        GameTooltip:AddLine("|cffff6666Shift+Right-click: Add to blacklist|r")
                    end
                end
                
                GameTooltip:Show()
            end
        end
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Hide grab tab if mouse isn't over main frame or grab tab, and not dragging
        if addon.grabTab and addon.grabTab.fadeOut and not addon.mainFrame:IsMouseOver() and not addon.grabTab:IsMouseOver() and not addon.grabTab.isDragging then
            addon.grabTab.fadeOut:Play()
        end
    end)
    
    button.lastCooldownStart = 0
    button.lastCooldownDuration = 0
    button.spellID = nil
    button:Hide()
    
    -- Register with Masque if available
    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            HotKey = button.hotkeyText,
            Normal = button.NormalTexture,
            Pushed = button.PushedTexture,
            Highlight = button.HighlightTexture,
            -- Flash = button.Flash,  -- Removed: Masque skins override Flash color (causing red)
        })
    end
    
    return button
end

function UIFrameFactory.UpdateFrameSize(addon)
    local profile = addon:GetProfile()
    if not profile or not addon.mainFrame then return end

    local newMaxIcons = profile.maxIcons
    local newIconSize = profile.iconSize
    local newIconSpacing = profile.iconSpacing
    local firstIconScale = profile.firstIconScale or 1.2
    local orientation = profile.queueOrientation or "LEFT"

    UIFrameFactory.CreateSpellIcons(addon)
    
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
    
    local point, _, _, x, y = addon.mainFrame:GetPoint()
    profile.framePosition = {
        point = point or "CENTER",
        x = x or 0,
        y = y or -150
    }
end

-- Export public functions
UIFrameFactory.GetDefensiveIcon = function() return defensiveIcon end
UIFrameFactory.GetSpellIcons = function() return spellIcons end
