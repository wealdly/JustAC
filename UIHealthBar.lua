-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Health Bar Module - Shows player health bar for low-health warning
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 5)
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
local lastVisibleCount = -1  -- cached visible icon count (defensive mode only)

-- Create the health bar frame.
-- Two modes:
--   Defensives enabled  + defensives.showHealthBar → spans defensive cluster, floats ABOVE it
--   Defensives disabled + profile.showHealthBar    → spans offensive queue, sits at BAR_SPACING above mainFrame
function UIHealthBar.CreateHealthBar(addon)
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame:SetParent(nil)
        healthBarFrame = nil
    end

    if not addon or not addon.mainFrame then return nil end
    if not addon.db or not addon.db.profile then return nil end

    local profile = addon.db.profile
    local defensivesEnabled = profile.defensives and profile.defensives.enabled

    local useDefensiveDims
    if defensivesEnabled then
        if not profile.defensives.showHealthBar then return nil end
        useDefensiveDims = true
    else
        if not profile.showHealthBar then return nil end
        useDefensiveDims = false
    end

    -- Create container frame
    local frame = CreateFrame("Frame", nil, addon.mainFrame)

    local orientation = profile.queueOrientation or "LEFT"
    local iconSize    = profile.iconSize or 42
    local iconSpacing = profile.iconSpacing or 1
    local queueDimension, offset

    if useDefensiveDims then
        -- Span the defensive icon cluster; float on the far side (away from mainFrame)
        local defIconScale = profile.defensives.iconScale or 1.0
        local defIconSize  = iconSize * defIconScale
        local maxDefIcons  = math.min(profile.defensives.maxIcons or 1, 7)
        local defPosition  = profile.defensives.position or "SIDE1"

        if maxDefIcons == 1 then
            queueDimension = defIconSize
        else
            queueDimension = defIconSize * 0.90 + (maxDefIcons - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
        end
        offset = maxDefIcons == 1 and 0 or (defIconSize * 0.10)

        -- Defensive icons sit at math.max(iconSpacing, BAR_SPACING) from mainFrame edge;
        -- bar floats BAR_SPACING beyond the outer edge of that cluster.
        local defSpacing = math.max(iconSpacing, BAR_SPACING)
        local barDist    = defSpacing + defIconSize + BAR_SPACING

        if orientation == "LEFT" or orientation == "RIGHT" then
            frame:SetSize(queueDimension, BAR_HEIGHT)
        else
            frame:SetSize(BAR_HEIGHT, queueDimension)
        end

        -- SIDE1 = above (horizontal) / right (vertical)
        -- SIDE2 = below (horizontal) / left  (vertical)
        if orientation == "LEFT" then
            if defPosition == "SIDE1" then
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",      offset,   barDist)
            else
                frame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT",   offset,  -barDist)
            end
        elseif orientation == "RIGHT" then
            if defPosition == "SIDE1" then
                frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -offset,   barDist)
            else
                frame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -offset,  -barDist)
            end
        elseif orientation == "DOWN" then
            if defPosition == "SIDE1" then
                frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",    barDist,  -offset)
            else
                frame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",    -barDist,  -offset)
            end
        else -- UP
            if defPosition == "SIDE1" then
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  barDist,  offset)
            else
                frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -barDist,  offset)
            end
        end
    else
        -- Span the offensive queue; original position just above mainFrame
        local firstIconScale = profile.firstIconScale or 1.0
        local maxIcons       = profile.maxIcons or 4
        local firstIconSize  = iconSize * firstIconScale

        if maxIcons == 1 then
            queueDimension = firstIconSize
        else
            queueDimension = firstIconSize * 0.90 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.90
        end
        offset = maxIcons == 1 and 0 or (firstIconSize * 0.10)

        if orientation == "LEFT" or orientation == "RIGHT" then
            frame:SetSize(queueDimension, BAR_HEIGHT)
        else
            frame:SetSize(BAR_HEIGHT, queueDimension)
        end

        if orientation == "LEFT" then
            frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",    offset,     BAR_SPACING)
        elseif orientation == "RIGHT" then
            frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",  -offset,     BAR_SPACING)
        elseif orientation == "DOWN" then
            frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",   BAR_SPACING, -offset)
        else -- UP
            frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT", BAR_SPACING, offset)
        end
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
    frame.useDefensiveDims = useDefensiveDims
    
    healthBarFrame = frame
    lastVisibleCount = -1  -- force first resize
    
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

--- Dynamically resize the health bar to match the number of visible defensive icons.
--- Only operates when the bar is in defensive-dims mode (useDefensiveDims = true).
--- @param addon table  The main addon object
--- @param visibleCount number  Number of currently visible defensive icons (0 = hide)
function UIHealthBar.ResizeToCount(addon, visibleCount)
    if not healthBarFrame then return end
    if not healthBarFrame.useDefensiveDims then return end  -- offensive-mode bar: skip

    -- Cache check: skip expensive recalc when count hasn't changed
    if visibleCount == lastVisibleCount then return end
    lastVisibleCount = visibleCount

    if visibleCount <= 0 then
        healthBarFrame:Hide()
        return
    end

    local profile = addon.db and addon.db.profile
    if not profile or not profile.defensives then return end

    local orientation  = profile.queueOrientation or "LEFT"
    local iconSize     = profile.iconSize or 42
    local iconSpacing  = profile.iconSpacing or 1
    local defIconScale = profile.defensives.iconScale or 1.0
    local defIconSize  = iconSize * defIconScale
    local defPosition  = profile.defensives.position or "SIDE1"

    local queueDimension
    if visibleCount == 1 then
        queueDimension = defIconSize
    else
        queueDimension = defIconSize * 0.90 + (visibleCount - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
    end
    local offset = visibleCount == 1 and 0 or (defIconSize * 0.10)

    -- Resize
    if orientation == "LEFT" or orientation == "RIGHT" then
        healthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
    else
        healthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Reposition to stay aligned above/below the visible cluster
    local defSpacing = math.max(iconSpacing, BAR_SPACING)
    local barDist    = defSpacing + defIconSize + BAR_SPACING

    healthBarFrame:ClearAllPoints()
    if orientation == "LEFT" then
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",      offset,   barDist)
        else
            healthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT",   offset,  -barDist)
        end
    elseif orientation == "RIGHT" then
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -offset,   barDist)
        else
            healthBarFrame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -offset,  -barDist)
        end
    elseif orientation == "DOWN" then
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",    barDist,  -offset)
        else
            healthBarFrame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",    -barDist,  -offset)
        end
    else -- UP
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  barDist,  offset)
        else
            healthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -barDist,  offset)
        end
    end

    healthBarFrame:Show()
end

-- Clean up
function UIHealthBar.Destroy()
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame:SetParent(nil)
        healthBarFrame = nil
    end
    lastUpdate = 0
    lastVisibleCount = -1
end

--------------------------------------------------------------------------------
-- Pet Health Bar (mirrors player health bar, independently controlled)
-- UnitHealth("pet") is secret in combat but StatusBar:SetValue() accepts secrets
-- UnitExists/UnitIsDead are NOT secret — used for visibility/dead state
--------------------------------------------------------------------------------

-- Calculate bar dimensions based on the defensive icon cluster (shared by both bars)
local function CalculateBarDimensions(profile)
    local orientation  = profile.queueOrientation or "LEFT"
    local iconSize     = profile.iconSize or 42
    local iconSpacing  = profile.iconSpacing or 1
    local defIconScale = profile.defensives and profile.defensives.iconScale or 1.0
    local defIconSize  = iconSize * defIconScale
    local maxDefIcons  = math.min(profile.defensives and profile.defensives.maxIcons or 1, 7)
    local defPosition  = profile.defensives and profile.defensives.position or "SIDE1"

    local queueDimension
    if maxDefIcons == 1 then
        queueDimension = defIconSize
    else
        queueDimension = defIconSize * 0.90 + (maxDefIcons - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
    end

    local defSpacing = math.max(iconSpacing, BAR_SPACING)
    local barDist    = defSpacing + defIconSize + BAR_SPACING

    return orientation, queueDimension, defIconSize, maxDefIcons, defPosition, barDist
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

    local orientation, queueDimension, defIconSize, maxDefIcons, defPosition, barDist = CalculateBarDimensions(profile)

    -- Create container frame
    local frame = CreateFrame("Frame", nil, addon.mainFrame)

    if orientation == "LEFT" or orientation == "RIGHT" then
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Stack the pet bar beyond the player health bar when both are shown
    local offset = maxDefIcons == 1 and 0 or (defIconSize * 0.10)
    local playerBarExists = (healthBarFrame ~= nil) and profile.defensives.showHealthBar
    local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
    local dist = barDist + extraOffset

    -- Mirror CreateHealthBar's SIDE1/SIDE2 logic, offset one bar-height further out
    if orientation == "LEFT" then
        if defPosition == "SIDE1" then
            frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",      offset,  dist)
        else
            frame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT",   offset, -dist)
        end
    elseif orientation == "RIGHT" then
        if defPosition == "SIDE1" then
            frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -offset,  dist)
        else
            frame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -offset, -dist)
        end
    elseif orientation == "DOWN" then
        if defPosition == "SIDE1" then
            frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",     dist,   -offset)
        else
            frame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",     -dist,   -offset)
        end
    else -- UP
        if defPosition == "SIDE1" then
            frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  dist,    offset)
        else
            frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -dist,    offset)
        end
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

    -- Teal-green for pet (green-leaning but distinct from player's pure green)
    statusBar:SetStatusBarColor(0.0, 0.85, 0.4, 0.9)

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
