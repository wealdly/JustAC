-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Health Bar Module
-- Compact health bar using StatusBar:SetValue() which accepts secret values directly
-- Positioned above the main DPS queue (below defensive icon when ABOVE)
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 3)
if not UIHealthBar then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Hot path optimizations
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local GetTime = GetTime

-- Constants
local UPDATE_INTERVAL = 0.1   -- Update 10 times per second (smooth enough, not too spammy)
local BAR_HEIGHT = 5          -- Compact height in pixels
local BAR_SPACING = 3         -- Spacing between health bar and queue icons

-- Color gradient: Green → Yellow → Red
local COLOR_HIGH = { r = 0.0, g = 0.8, b = 0.0 }  -- Green (100% - 50%)
local COLOR_MID  = { r = 1.0, g = 1.0, b = 0.0 }  -- Yellow (50% - 25%)
local COLOR_LOW  = { r = 1.0, g = 0.0, b = 0.0 }  -- Red (25% - 0%)

-- Module state
local healthBarFrame = nil
local lastUpdate = 0

-- Interpolate between two colors based on ratio (0.0 to 1.0)
local function LerpColor(c1, c2, ratio)
    return {
        r = c1.r + (c2.r - c1.r) * ratio,
        g = c1.g + (c2.g - c1.g) * ratio,
        b = c1.b + (c2.b - c1.b) * ratio
    }
end

-- Get color for health percentage (0-100)
local function GetHealthColor(percent)
    if percent >= 50 then
        -- Green to Yellow (100% → 50%)
        local ratio = (100 - percent) / 50  -- 0.0 at 100%, 1.0 at 50%
        return LerpColor(COLOR_HIGH, COLOR_MID, ratio)
    elseif percent >= 25 then
        -- Yellow to Red (50% → 25%)
        local ratio = (50 - percent) / 25  -- 0.0 at 50%, 1.0 at 25%
        return LerpColor(COLOR_MID, COLOR_LOW, ratio)
    else
        -- Solid Red (25% → 0%)
        return COLOR_LOW
    end
end

-- Create the health bar frame
function UIHealthBar.CreateHealthBar(addon)
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame:SetParent(nil)
        healthBarFrame = nil
    end
    
    if not addon or not addon.mainFrame then return nil end
    if not addon.db or not addon.db.profile then return nil end
    
    local profile = addon.db.profile
    if not profile.defensives or not profile.defensives.enabled or not profile.defensives.showHealthBar then
        return nil
    end
    
    -- Create container frame
    local frame = CreateFrame("Frame", nil, addon.mainFrame)
    
    -- Calculate width/height based on visible icons
    local orientation = profile.queueOrientation or "LEFT"
    local maxIcons = profile.maxIcons or 4
    local iconSize = profile.iconSize or 36
    local firstIconScale = profile.firstIconScale or 1.2
    local iconSpacing = profile.iconSpacing or 1
    
    local firstIconSize = iconSize * firstIconScale
    local queueDimension
    
    if maxIcons == 1 then
        -- Single icon: span full width
        queueDimension = firstIconSize
    else
        -- Multiple icons: center of icon 1 to center of last icon
        -- Distance = (firstIconSize - iconSize)/2 + (maxIcons - 1)*(iconSize + iconSpacing)
        queueDimension = (firstIconSize - iconSize) / 2 + (maxIcons - 1) * (iconSize + iconSpacing)
    end
    
    if orientation == "LEFT" or orientation == "RIGHT" then
        -- Horizontal queue: calculated width, BAR_HEIGHT for height
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else -- UP or DOWN
        -- Vertical queue: BAR_HEIGHT for width, calculated height
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end
    
    -- Position above position 1 icon, accounting for queue orientation and defensive position
    local defensivePosition = profile.defensives and profile.defensives.position or "LEFT"
    
    -- Positioning offset depends on whether we have 1 or multiple icons
    local centerOffset = (maxIcons == 1) and 0 or (firstIconSize / 2)
    
    -- Health bar is always above the main queue
    -- When defensive icon is ABOVE, defensive goes above health bar
    if orientation == "LEFT" then
        -- Horizontal queue left-to-right
        frame:SetPoint("BOTTOMLEFT", addon.mainFrame, "TOPLEFT", centerOffset, BAR_SPACING)
    elseif orientation == "RIGHT" then
        -- Horizontal queue right-to-left
        frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT", -centerOffset, BAR_SPACING)
    elseif orientation == "DOWN" then
        -- Vertical queue downward
        frame:SetPoint("BOTTOM", addon.mainFrame, "TOP", 0, BAR_SPACING + centerOffset)
    else -- UP
        -- Vertical queue upward
        frame:SetPoint("TOP", addon.mainFrame, "BOTTOM", 0, -BAR_SPACING - centerOffset)
    end
    
    -- Create StatusBar (accepts secret values!)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:GetStatusBarTexture():SetHorizTile(false)
    statusBar:GetStatusBarTexture():SetVertTile(false)
    statusBar:SetOrientation("HORIZONTAL")
    -- Set initial green color (will update to gradient when health changes)
    statusBar:SetStatusBarColor(0.0, 0.8, 0.0, 1.0)
    
    -- Background
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)  -- Dark background
    
    -- Border frame for visual definition
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetAllPoints(frame)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame.statusBar = statusBar
    frame.background = bg
    frame.border = border
    
    healthBarFrame = frame
    
    -- Initial update
    UIHealthBar.Update(addon)
    
    return frame
end

-- Update health bar (call on UNIT_HEALTH and timer)
function UIHealthBar.Update(addon)
    if not healthBarFrame or not healthBarFrame:IsVisible() then return end
    
    local now = GetTime()
    if now - lastUpdate < UPDATE_INTERVAL then return end
    lastUpdate = now
    
    -- Get health values - StatusBar:SetValue() accepts secrets!
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    
    if not health or not maxHealth or maxHealth == 0 then return end
    
    local statusBar = healthBarFrame.statusBar
    if not statusBar then return end
    
    -- Set min/max and value (both accept secrets directly)
    statusBar:SetMinMaxValues(0, maxHealth)
    statusBar:SetValue(health)
    
    -- Color gradient - try to calculate percentage even with secrets
    local percent = nil
    
    -- Method 1: Direct calculation if not secret
    if not (issecretvalue and issecretvalue(health)) and not (issecretvalue and issecretvalue(maxHealth)) then
        percent = (health / maxHealth) * 100
    else
        -- Method 2: Try UnitPercentHealthFromGUID (may not be secret)
        local guid = UnitGUID("player")
        if guid then
            local pct = UnitPercentHealthFromGUID(guid)
            if pct and not (issecretvalue and issecretvalue(pct)) then
                percent = pct
            end
        end
    end
    
    -- Update color if we got a valid percentage
    if percent then
        local color = GetHealthColor(percent)
        statusBar:SetStatusBarColor(color.r, color.g, color.b, 1.0)
    end
end

-- Show the health bar
function UIHealthBar.Show()
    if healthBarFrame then
        healthBarFrame:Show()
    end
end

-- Hide the health bar
function UIHealthBar.Hide()
    if healthBarFrame then
        healthBarFrame:Hide()
    end
end

-- Get the health bar frame (for external positioning/debugging)
function UIHealthBar.GetFrame()
    return healthBarFrame
end

-- Update health bar size to match current queue dimensions
function UIHealthBar.UpdateSize(addon)
    if not healthBarFrame or not addon or not addon.db or not addon.db.profile then return end
    
    local profile = addon.db.profile
    local orientation = profile.queueOrientation or "LEFT"
    local maxIcons = profile.maxIcons or 4
    local iconSize = profile.iconSize or 36
    local firstIconScale = profile.firstIconScale or 1.2
    local iconSpacing = profile.iconSpacing or 1
    
    -- Calculate queue dimension (same as CreateHealthBar)
    local firstIconSize = iconSize * firstIconScale
    local queueDimension
    
    if maxIcons == 1 then
        -- Single icon: span full width
        queueDimension = firstIconSize
    else
        -- Multiple icons: center of icon 1 to center of last icon
        queueDimension = (firstIconSize - iconSize) / 2 + (maxIcons - 1) * (iconSize + iconSpacing)
    end
    
    if orientation == "LEFT" or orientation == "RIGHT" then
        healthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
    else -- UP or DOWN
        healthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
    end
end

-- Clean up
function UIHealthBar.Destroy()
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame:SetParent(nil)
        healthBarFrame = nil
    end
    lastUpdate = 0
end
