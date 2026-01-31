-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Health Bar Module - Shows player health bar for low-health warning
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 3)
if not UIHealthBar then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Cache frequently used functions to reduce table lookups on every update
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local GetTime = GetTime

-- Constants
local UPDATE_INTERVAL = 0.1   -- Update frequently enough for responsive feedback
local BAR_HEIGHT = 6          -- Compact height in pixels
local BAR_SPACING = 3         -- Spacing between health bar and queue icons

-- Export constants for UIFrameFactory to calculate defensive icon offset
UIHealthBar.BAR_HEIGHT = BAR_HEIGHT
UIHealthBar.BAR_SPACING = BAR_SPACING

-- Module state
local healthBarFrame = nil
local lastUpdate = 0

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
        -- Single icon: full width edge-to-edge
        queueDimension = firstIconSize
    else
        -- Multiple icons: 25% into icon 1 to 75% into last icon
        -- = 75% of firstIcon + middle icons + 75% of last icon
        queueDimension = firstIconSize * 0.75 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.75
    end
    
    if orientation == "LEFT" or orientation == "RIGHT" then
        -- Horizontal queue: horizontal bar (width x height)
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else -- UP or DOWN
        -- Vertical queue: vertical bar (width x height)
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end
    
    -- Position above position 1 icon, accounting for queue orientation and defensive position
    local defensivePosition = profile.defensives and profile.defensives.position or "LEFT"
    
    -- Positioning offset: 0 for single icon (edge-to-edge), 25% for multiple icons
    local offset = maxIcons == 1 and 0 or (firstIconSize * 0.25)
    
    -- Position health bar based on queue orientation
    if orientation == "LEFT" then
        -- Horizontal queue left-to-right: bar above, starting at offset from left
        frame:SetPoint("BOTTOMLEFT", addon.mainFrame, "TOPLEFT", offset, BAR_SPACING)
    elseif orientation == "RIGHT" then
        -- Horizontal queue right-to-left: bar above, ending at offset from right
        frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT", -offset, BAR_SPACING)
    elseif orientation == "DOWN" then
        -- Vertical queue downward: vertical bar to the right, starting at offset from top
        frame:SetPoint("TOPLEFT", addon.mainFrame, "TOPRIGHT", BAR_SPACING, -offset)
    else -- UP
        -- Vertical queue upward: vertical bar to the right, starting at offset from bottom
        frame:SetPoint("BOTTOMLEFT", addon.mainFrame, "BOTTOMRIGHT", BAR_SPACING, offset)
    end
    
    -- Create StatusBar (accepts secret values!)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:GetStatusBarTexture():SetHorizTile(false)
    statusBar:GetStatusBarTexture():SetVertTile(false)
    
    -- Set orientation based on queue direction
    if orientation == "LEFT" or orientation == "RIGHT" then
        statusBar:SetOrientation("HORIZONTAL")
    else
        statusBar:SetOrientation("VERTICAL")
    end
    
    -- Set initial green color
    statusBar:SetStatusBarColor(0.0, 0.8, 0.0, 1.0)
    
    -- Background
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.8, 0.1, 0.1, 0.9)  -- Bright red background to emphasize missing health
    
    -- Border frame for visual definition
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetAllPoints(frame)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Tick marks at 25%, 50%, 75% for visual percentage reference
    local tickMarks = {}
    for i, percent in ipairs({0.25, 0.5, 0.75}) do
        local tick = border:CreateTexture(nil, "OVERLAY")
        tick:SetTexture("Interface\\Buttons\\WHITE8X8")
        tick:SetVertexColor(0.5, 0.5, 0.5, 0.8)  -- Grey
        
        if orientation == "LEFT" or orientation == "RIGHT" then
            -- Horizontal bar: vertical tick marks
            tick:SetSize(1, BAR_HEIGHT)
            tick:SetPoint("BOTTOM", frame, "BOTTOMLEFT", queueDimension * percent, 0)
        else
            -- Vertical bar: horizontal tick marks
            tick:SetSize(BAR_HEIGHT, 1)
            tick:SetPoint("LEFT", frame, "BOTTOMLEFT", 0, queueDimension * percent)
        end
        
        tickMarks[i] = tick
    end
    
    frame.statusBar = statusBar
    frame.background = bg
    frame.border = border
    frame.tickMarks = tickMarks
    
    healthBarFrame = frame
    
    -- Initial update
    UIHealthBar.Update(addon)
    
    return frame
end

-- Update health bar on state changes and timer intervals
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
    
    -- Color gradient: Green → Yellow → Red based on health percentage
    -- Only update color if not dealing with secret values
    if BlizzardAPI and not BlizzardAPI.IsSecretValue(health) and not BlizzardAPI.IsSecretValue(maxHealth) then
        local healthPercent = health / maxHealth
        local r, g, b
        
        if healthPercent > 0.5 then
            -- Green to Yellow (100% → 50%)
            r = (1.0 - healthPercent) * 2  -- 0.0 → 1.0
            g = 0.8
            b = 0.0
        else
            -- Yellow to Red (50% → 0%)
            r = 1.0
            g = healthPercent * 1.6  -- 0.8 → 0.0
            b = 0.0
        end
        
        statusBar:SetStatusBarColor(r, g, b, 1.0)
    end
    -- Color stays green (set at creation) - visual fill shows health level
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
-- Recreate on orientation change to ensure layout and tick correctness
function UIHealthBar.UpdateSize(addon)
    if not addon or not addon.db or not addon.db.profile then return end
    
    -- If orientation might have changed, safer to recreate
    -- Simple resize won't update StatusBar orientation or tick marks
    if healthBarFrame then
        UIHealthBar.Destroy()
    end
    
    UIHealthBar.CreateHealthBar(addon)
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
