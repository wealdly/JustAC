-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Health Bar Module - Shows player health bar for low-health warning
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 4)
if not UIHealthBar then return end

-- Cache frequently used functions to reduce table lookups on every update
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
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
local petHealthBarFrame = nil
local lastUpdate = 0
local lastPetUpdate = 0

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
    -- Health bar is independent of defensive queue - only check showHealthBar setting
    if not profile.defensives or not profile.defensives.showHealthBar then
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
        -- Multiple icons: 10% inset from each outer edge
        queueDimension = firstIconSize * 0.90 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.90
    end
    
    if orientation == "LEFT" or orientation == "RIGHT" then
        -- Horizontal queue: horizontal bar (width x height)
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else -- UP or DOWN
        -- Vertical queue: vertical bar (width x height)
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end
    
    -- Positioning offset: 0 for single icon (edge-to-edge), 10% for multiple icons
    local offset = maxIcons == 1 and 0 or (firstIconSize * 0.10)
    
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
    
    -- Set initial bright green color (matches nameplate overlay bar)
    statusBar:SetStatusBarColor(0.0, 1.0, 0.0, 0.9)
    
    -- Solid dark-red background fills the bar frame
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.8, 0.1, 0.1, 0.9)  -- Bright red background to emphasize missing health
    
    frame.statusBar = statusBar
    frame.background = bg
    
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
    
    if not health or not maxHealth then return end

    local statusBar = healthBarFrame.statusBar
    if not statusBar then return end

    -- Pass-through: StatusBar:SetMinMaxValues and SetValue accept secret values directly
    -- The bar renders correctly even when values are secret
    statusBar:SetMinMaxValues(0, maxHealth)
    statusBar:SetValue(health)
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

--------------------------------------------------------------------------------
-- Pet Health Bar (mirrors player health bar, independently controlled)
-- UnitHealth("pet") is secret in combat but StatusBar:SetValue() accepts secrets
-- UnitExists/UnitIsDead are NOT secret — used for visibility/dead state
--------------------------------------------------------------------------------

-- Calculate bar dimensions based on queue layout (shared by both bars)
local function CalculateBarDimensions(profile)
    local orientation = profile.queueOrientation or "LEFT"
    local maxIcons = profile.maxIcons or 4
    local iconSize = profile.iconSize or 36
    local firstIconScale = profile.firstIconScale or 1.2
    local iconSpacing = profile.iconSpacing or 1
    local firstIconSize = iconSize * firstIconScale

    local queueDimension
    if maxIcons == 1 then
        queueDimension = firstIconSize
    else
        queueDimension = firstIconSize * 0.90 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.90
    end

    return orientation, queueDimension, firstIconSize, maxIcons
end

-- Create the pet health bar frame
function UIHealthBar.CreatePetHealthBar(addon)
    if petHealthBarFrame then
        petHealthBarFrame:Hide()
        petHealthBarFrame:SetParent(nil)
        petHealthBarFrame = nil
    end

    if not addon or not addon.mainFrame then return nil end
    if not addon.db or not addon.db.profile then return nil end

    local profile = addon.db.profile
    if not profile.defensives or not profile.defensives.showPetHealthBar then
        return nil
    end

    -- Only create for pet classes
    local _, playerClass = UnitClass("player")
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not SpellDB then return nil end
    local hasPetSpells = (SpellDB.CLASS_PET_REZ_DEFAULTS and SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass])
        or (SpellDB.CLASS_PETHEAL_DEFAULTS and SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass])
    if not hasPetSpells then return nil end

    local orientation, queueDimension, firstIconSize, maxIcons = CalculateBarDimensions(profile)

    -- Create container frame
    local frame = CreateFrame("Frame", nil, addon.mainFrame)

    if orientation == "LEFT" or orientation == "RIGHT" then
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Position: stack above/beside the player health bar if it exists, else same offset
    local offset = maxIcons == 1 and 0 or (firstIconSize * 0.10)
    local playerBarExists = (healthBarFrame ~= nil) and profile.defensives.showHealthBar
    local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0

    if orientation == "LEFT" then
        frame:SetPoint("BOTTOMLEFT", addon.mainFrame, "TOPLEFT", offset, BAR_SPACING + extraOffset)
    elseif orientation == "RIGHT" then
        frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT", -offset, BAR_SPACING + extraOffset)
    elseif orientation == "DOWN" then
        frame:SetPoint("TOPLEFT", addon.mainFrame, "TOPRIGHT", BAR_SPACING + extraOffset, -offset)
    else -- UP
        frame:SetPoint("BOTTOMLEFT", addon.mainFrame, "BOTTOMRIGHT", BAR_SPACING + extraOffset, offset)
    end

    -- Create StatusBar (accepts secret values!)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBar:GetStatusBarTexture():SetHorizTile(false)
    statusBar:GetStatusBarTexture():SetVertTile(false)

    if orientation == "LEFT" or orientation == "RIGHT" then
        statusBar:SetOrientation("HORIZONTAL")
    else
        statusBar:SetOrientation("VERTICAL")
    end

    -- Teal/blue for pet (distinct from player's green)
    statusBar:SetStatusBarColor(0.0, 0.6, 0.8, 0.9)

    -- Background (dark red when pet is hurt/missing health shows through)
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.6, 0.15, 0.15, 0.9)

    -- Dead overlay (red tint, hidden by default)
    local deadOverlay = frame:CreateTexture(nil, "ARTWORK")
    deadOverlay:SetAllPoints(frame)
    deadOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    deadOverlay:SetVertexColor(0.8, 0.1, 0.1, 0.5)
    deadOverlay:Hide()

    frame.statusBar = statusBar
    frame.background = bg
    frame.deadOverlay = deadOverlay

    petHealthBarFrame = frame

    -- Initial visibility based on pet state
    UIHealthBar.UpdatePetVisibility(addon)

    return frame
end

-- Update pet health bar value on timer
function UIHealthBar.UpdatePet(addon)
    if not petHealthBarFrame or not petHealthBarFrame:IsVisible() then return end

    local now = GetTime()
    if now - lastPetUpdate < UPDATE_INTERVAL then return end
    lastPetUpdate = now

    -- Check pet state for dead overlay
    local exists = UnitExists("pet")
    if not exists then
        petHealthBarFrame:Hide()
        return
    end

    local ok, isDead = pcall(UnitIsDead, "pet")
    -- UnitIsDead is NOT secret in 12.0 — safe to compare directly
    if ok and isDead and not (issecretvalue and issecretvalue(isDead)) then
        -- Pet is dead: show empty bar with red overlay
        if petHealthBarFrame.statusBar then
            petHealthBarFrame.statusBar:SetValue(0)
        end
        if petHealthBarFrame.deadOverlay then
            petHealthBarFrame.deadOverlay:Show()
        end
        return
    else
        if petHealthBarFrame.deadOverlay then
            petHealthBarFrame.deadOverlay:Hide()
        end
    end

    -- UnitHealth("pet") is secret in 12.0 combat, but StatusBar:SetValue()
    -- accepts secret values and renders correctly (Blizzard handles internally).
    -- The bar will show, just with unknown fill level — better than hiding it.
    local health = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")

    if not health or not maxHealth then return end

    local statusBar = petHealthBarFrame.statusBar
    if not statusBar then return end

    statusBar:SetMinMaxValues(0, maxHealth)
    statusBar:SetValue(health)
end

-- Show/hide pet health bar based on pet existence
function UIHealthBar.UpdatePetVisibility(addon)
    if not petHealthBarFrame then return end

    local exists = UnitExists("pet")
    if exists then
        petHealthBarFrame:Show()
        UIHealthBar.UpdatePet(addon)
    else
        petHealthBarFrame:Hide()
    end
end

function UIHealthBar.ShowPet()
    if petHealthBarFrame and UnitExists("pet") then
        petHealthBarFrame:Show()
    end
end

function UIHealthBar.HidePet()
    if petHealthBarFrame then
        petHealthBarFrame:Hide()
    end
end

function UIHealthBar.GetPetFrame()
    return petHealthBarFrame
end

function UIHealthBar.UpdatePetSize(addon)
    if not addon or not addon.db or not addon.db.profile then return end
    if petHealthBarFrame then
        UIHealthBar.DestroyPet()
    end
    UIHealthBar.CreatePetHealthBar(addon)
end

function UIHealthBar.DestroyPet()
    if petHealthBarFrame then
        petHealthBarFrame:Hide()
        petHealthBarFrame:SetParent(nil)
        petHealthBarFrame = nil
    end
    lastPetUpdate = 0
end
