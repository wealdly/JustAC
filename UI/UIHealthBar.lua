-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Health Bar Module - Shows player health bar for low-health warning
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 8)
if not UIHealthBar then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Hot path cache
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
local lastVisibleCount = -1     -- cached visible icon count (defensive mode only)
local lastPetVisibleCount = -1  -- cached visible icon count for pet bar

-- Create the health bar frame.
-- Two modes:
--   Defensives enabled  + defensives.showHealthBar → spans defensive cluster, floats ABOVE it
--   Defensives disabled + defensives.showHealthBar → spans offensive queue, sits at BAR_SPACING above mainFrame
function UIHealthBar.CreateHealthBar(addon)
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame:SetParent(nil)
        healthBarFrame = nil
    end

    if not addon or not addon.db or not addon.db.profile then return nil end
    local profile = addon.db.profile
    local isDetached = profile.defensives and profile.defensives.detached

    -- Require the appropriate parent frame depending on detached mode.
    if isDetached then
        if not addon.defensiveFrame then return nil end
    else
        if not addon.mainFrame then return nil end
    end

    local defensivesEnabled = profile.defensives and profile.defensives.enabled

    -- Health bar visibility is controlled by a single toggle (defensives.showHealthBar)
    -- regardless of whether defensive suggestions are enabled.
    if not (profile.defensives and profile.defensives.showHealthBar) then return nil end

    local iconSize    = profile.iconSize or 42
    local iconSpacing = profile.iconSpacing or 1
    local queueDimension, offset
    local barIsHorizontal  -- drives StatusBar orientation and bevel direction
    local frame
    local useDefensiveDims

    if isDetached then
        -- Detached mode: parent to defensiveFrame; span and float relative to it.
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local isVert = (detachOrientation == "UP" or detachOrientation == "DOWN")
        local defIconScale = profile.defensives.iconScale or 1.0
        local defIconSize  = iconSize * defIconScale
        local maxDefIcons  = math.min(profile.defensives.maxIcons or 1, 7)

        if maxDefIcons == 1 then
            queueDimension = defIconSize
        else
            queueDimension = defIconSize * 0.90 + (maxDefIcons - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
        end
        offset = maxDefIcons == 1 and 0 or (defIconSize * 0.10)

        frame = CreateFrame("Frame", nil, addon.defensiveFrame)
        useDefensiveDims = true

        -- grabTabSpacing mirrors UpdateDefensiveFrameSize: spacing + 12 (vert) or spacing + 13 (horiz)
        local grabTabSpacing = isVert and (iconSpacing + 12) or (iconSpacing + 13)

        -- Per-orientation anchor: bar floats on the open side of the icon cluster.
        --   LEFT  → tab at RIGHT,   icons from LEFT  → bar ABOVE, left-aligned
        --   RIGHT → tab at LEFT,    icons from RIGHT → bar ABOVE, right-aligned
        --   UP    → tab at BOTTOM,  icons from BOTTOM → bar to the RIGHT, bottom-aligned above tab
        --   DOWN  → tab at TOP,     icons from TOP    → bar to the RIGHT, top-aligned below tab
        if detachOrientation == "LEFT" then
            barIsHorizontal = true
            frame:SetSize(queueDimension, BAR_HEIGHT)
            frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "TOPLEFT", offset, BAR_SPACING)
        elseif detachOrientation == "RIGHT" then
            barIsHorizontal = true
            frame:SetSize(queueDimension, BAR_HEIGHT)
            frame:SetPoint("BOTTOMRIGHT", addon.defensiveFrame, "TOPRIGHT", -offset, BAR_SPACING)
        elseif detachOrientation == "UP" then
            barIsHorizontal = false
            frame:SetSize(BAR_HEIGHT, queueDimension)
            frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "BOTTOMRIGHT", BAR_SPACING, grabTabSpacing + offset)
        else -- DOWN
            barIsHorizontal = false
            frame:SetSize(BAR_HEIGHT, queueDimension)
            frame:SetPoint("TOPLEFT", addon.defensiveFrame, "TOPRIGHT", BAR_SPACING, -(grabTabSpacing + offset))
        end
    else
        -- Attached mode: parent to mainFrame; original sizing and anchor logic.
        useDefensiveDims = defensivesEnabled or false
        frame = CreateFrame("Frame", nil, addon.mainFrame)

        local orientation = profile.queueOrientation or "LEFT"
        barIsHorizontal = (orientation == "LEFT" or orientation == "RIGHT")

        -- For RIGHT/UP, icons are shifted within the frame to keep the grab tab at a
        -- predictable position.  Health bars must match that shift to stay aligned.
        local grabTabReserve = 0
        if orientation == "RIGHT" or orientation == "UP" then
            local GRAB_TAB_LENGTH = 12
            local isVert = (orientation == "UP")
            grabTabReserve = iconSpacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
        end

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

            -- Defensive icons sit at iconSpacing from mainFrame edge (matches icon-to-icon spacing);
            -- bar floats BAR_SPACING beyond the outer edge of that cluster.
            local defSpacing = iconSpacing
            local barDist    = defSpacing + defIconSize + BAR_SPACING

            if barIsHorizontal then
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
                    frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -(offset + grabTabReserve),   barDist)
                else
                    frame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -(offset + grabTabReserve),  -barDist)
                end
            elseif orientation == "DOWN" then
                if defPosition == "SIDE1" then
                    frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",    barDist,  -offset)
                else
                    frame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",    -barDist,  -offset)
                end
            else -- UP
                if defPosition == "SIDE1" then
                    frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  barDist,  offset + grabTabReserve)
                else
                    frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -barDist,  offset + grabTabReserve)
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

            if barIsHorizontal then
                frame:SetSize(queueDimension, BAR_HEIGHT)
            else
                frame:SetSize(BAR_HEIGHT, queueDimension)
            end

            if orientation == "LEFT" then
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",    offset,     BAR_SPACING)
            elseif orientation == "RIGHT" then
                frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",  -(offset + grabTabReserve),     BAR_SPACING)
            elseif orientation == "DOWN" then
                -- Bar to the right of mainFrame (perpendicular to vertical queue)
                frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",   BAR_SPACING, -offset)
            else -- UP
                -- Bar to the right of mainFrame (perpendicular to vertical queue)
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT", BAR_SPACING, offset + grabTabReserve)
            end
        end
    end

    -- ── Shared: StatusBar, background, bevel ──────────────────────────────────
    -- Create StatusBar (accepts secret values!)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    statusBar:SetOrientation(barIsHorizontal and "HORIZONTAL" or "VERTICAL")

    -- Set initial bright green color (matches nameplate overlay bar)
    statusBar:SetStatusBarColor(0.0, 0.80, 0.0, 0.9)

    -- Solid dark-red background fills the bar frame
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.8, 0.1, 0.1, 0.9)  -- Bright red background to emphasize missing health

    -- 4-strip tube bevel on OVERLAY so the engine never clobbers them.
    -- Horizontal: symmetric alphas (bright band dead-centre on 6 px bar).
    -- Vertical:   asymmetric (near-queue heavier) — bar is wide enough.
    if barIsHorizontal then
        local shBot1 = statusBar:CreateTexture(nil, "OVERLAY")
        shBot1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shBot1:SetVertexColor(0, 0, 0, 0.35)
        shBot1:SetPoint("BOTTOMLEFT",  statusBar, "BOTTOMLEFT",  0, 0)
        shBot1:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        shBot1:SetHeight(1)

        local shBot2 = statusBar:CreateTexture(nil, "OVERLAY")
        shBot2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shBot2:SetVertexColor(0, 0, 0, 0.16)
        shBot2:SetPoint("BOTTOMLEFT",  statusBar, "BOTTOMLEFT",  0, 1)
        shBot2:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 1)
        shBot2:SetHeight(1)

        local shTop1 = statusBar:CreateTexture(nil, "OVERLAY")
        shTop1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shTop1:SetVertexColor(0, 0, 0, 0.16)
        shTop1:SetPoint("TOPLEFT",  statusBar, "TOPLEFT",  0, -1)
        shTop1:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, -1)
        shTop1:SetHeight(1)

        local shTop2 = statusBar:CreateTexture(nil, "OVERLAY")
        shTop2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shTop2:SetVertexColor(0, 0, 0, 0.35)
        shTop2:SetPoint("TOPLEFT",  statusBar, "TOPLEFT",  0, 0)
        shTop2:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
        shTop2:SetHeight(1)
    else
        local shL1 = statusBar:CreateTexture(nil, "OVERLAY")
        shL1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shL1:SetVertexColor(0, 0, 0, 0.35)
        shL1:SetPoint("TOPLEFT",    statusBar, "TOPLEFT",    0, 0)
        shL1:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 0, 0)
        shL1:SetWidth(1)

        local shL2 = statusBar:CreateTexture(nil, "OVERLAY")
        shL2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shL2:SetVertexColor(0, 0, 0, 0.16)
        shL2:SetPoint("TOPLEFT",    statusBar, "TOPLEFT",    1, 0)
        shL2:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 1, 0)
        shL2:SetWidth(1)

        local shR1 = statusBar:CreateTexture(nil, "OVERLAY")
        shR1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shR1:SetVertexColor(0, 0, 0, 0.16)
        shR1:SetPoint("TOPRIGHT",    statusBar, "TOPRIGHT",    -1, 0)
        shR1:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", -1, 0)
        shR1:SetWidth(1)

        local shR2 = statusBar:CreateTexture(nil, "OVERLAY")
        shR2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shR2:SetVertexColor(0, 0, 0, 0.35)
        shR2:SetPoint("TOPRIGHT",    statusBar, "TOPRIGHT",    0, 0)
        shR2:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        shR2:SetWidth(1)
    end

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
--- When visibleCount is 0, the bar falls back to offensive-queue positioning so it
--- remains visible even when defensive icons are hidden (e.g. "When Health Low" mode
--- at high health).
--- @param addon table  The main addon object
--- @param visibleCount number  Number of currently visible defensive icons (0 = fallback to offensive)
function UIHealthBar.ResizeToCount(addon, visibleCount)
    if not healthBarFrame then return end
    if not healthBarFrame.useDefensiveDims then return end  -- offensive-mode bar: skip

    -- Cache check: skip expensive recalc when count hasn't changed
    if visibleCount == lastVisibleCount then return end
    lastVisibleCount = visibleCount

    local profile = addon.db and addon.db.profile
    if not profile then return end

    local isDetached = profile.defensives and profile.defensives.detached
    if isDetached then
        -- Detached: no offensive fallback — just hide when no icons visible.
        if visibleCount <= 0 then
            healthBarFrame:Hide()
            return
        end
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local isVert = (detachOrientation == "UP" or detachOrientation == "DOWN")
        local iconSize    = profile.iconSize or 42
        local iconSpacing = profile.iconSpacing or 1
        local defIconScale = profile.defensives.iconScale or 1.0
        local defIconSize  = iconSize * defIconScale

        local queueDimension
        if visibleCount == 1 then
            queueDimension = defIconSize
        else
            queueDimension = defIconSize * 0.90 + (visibleCount - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
        end
        local offset = visibleCount == 1 and 0 or (defIconSize * 0.10)

        local grabTabSpacing = isVert and (iconSpacing + 12) or (iconSpacing + 13)
        healthBarFrame:ClearAllPoints()
        if detachOrientation == "LEFT" then
            healthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
            healthBarFrame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "TOPLEFT", offset, BAR_SPACING)
        elseif detachOrientation == "RIGHT" then
            healthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
            healthBarFrame:SetPoint("BOTTOMRIGHT", addon.defensiveFrame, "TOPRIGHT", -offset, BAR_SPACING)
        elseif detachOrientation == "UP" then
            healthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
            healthBarFrame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "BOTTOMRIGHT", BAR_SPACING, grabTabSpacing + offset)
        else -- DOWN
            healthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
            healthBarFrame:SetPoint("TOPLEFT", addon.defensiveFrame, "TOPRIGHT", BAR_SPACING, -(grabTabSpacing + offset))
        end
        healthBarFrame:Show()
        return
    end

    local orientation = profile.queueOrientation or "LEFT"
    local iconSize    = profile.iconSize or 42
    local iconSpacing = profile.iconSpacing or 1

    -- For RIGHT/UP, icons are shifted within the frame to keep the grab tab at a
    -- predictable position.  Health bars must match that shift to stay aligned.
    local grabTabReserve = 0
    if orientation == "RIGHT" or orientation == "UP" then
        local GRAB_TAB_LENGTH = 12
        local isVert = (orientation == "UP")
        grabTabReserve = iconSpacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
    end

    healthBarFrame:ClearAllPoints()

    if visibleCount <= 0 then
        -- No defensive icons visible → fall back to offensive queue dimensions/position
        -- so the health bar stays on screen (mirrors the non-defensive path in CreateHealthBar).
        local firstIconScale = profile.firstIconScale or 1.0
        local maxIcons       = profile.maxIcons or 4
        local firstIconSize  = iconSize * firstIconScale

        local queueDimension
        if maxIcons == 1 then
            queueDimension = firstIconSize
        else
            queueDimension = firstIconSize * 0.90 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.90
        end
        local offset = maxIcons == 1 and 0 or (firstIconSize * 0.10)

        if orientation == "LEFT" or orientation == "RIGHT" then
            healthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
        else
            healthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
        end

        if orientation == "LEFT" then
            healthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",    offset,     BAR_SPACING)
        elseif orientation == "RIGHT" then
            healthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",  -(offset + grabTabReserve),     BAR_SPACING)
        elseif orientation == "DOWN" then
            healthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",   BAR_SPACING, -offset)
        else -- UP
            healthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT", BAR_SPACING, offset + grabTabReserve)
        end

        healthBarFrame:Show()
        return
    end

    if not profile.defensives then return end

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

    if orientation == "LEFT" then
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",      offset,   barDist)
        else
            healthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT",   offset,  -barDist)
        end
    elseif orientation == "RIGHT" then
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -(offset + grabTabReserve),   barDist)
        else
            healthBarFrame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -(offset + grabTabReserve),  -barDist)
        end
    elseif orientation == "DOWN" then
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",    barDist,  -offset)
        else
            healthBarFrame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",    -barDist,  -offset)
        end
    else -- UP
        if defPosition == "SIDE1" then
            healthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  barDist,  offset + grabTabReserve)
        else
            healthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -barDist,  offset + grabTabReserve)
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

-- Create the pet health bar frame.
-- Three modes (mirrors CreateHealthBar):
--   Detached            + defensives.showPetHealthBar → spans detached defensiveFrame, stacks beyond player bar
--   Defensives enabled  + defensives.showPetHealthBar → spans defensive cluster on mainFrame, stacks beyond player bar
--   Defensives disabled + defensives.showPetHealthBar → spans offensive queue, stacks beyond player bar
function UIHealthBar.CreatePetHealthBar(addon)
    if petHealthBarFrame then
        petHealthBarFrame:Hide()
        petHealthBarFrame:SetParent(nil)
        petHealthBarFrame = nil
    end

    if not addon or not addon.db or not addon.db.profile then return nil end
    local profile = addon.db.profile
    local isDetached = profile.defensives and profile.defensives.detached

    if isDetached then
        if not addon.defensiveFrame then return nil end
    else
        if not addon.mainFrame then return nil end
    end

    local defensivesEnabled = profile.defensives and profile.defensives.enabled

    -- Pet health bar visibility controlled by defensives.showPetHealthBar
    -- regardless of whether defensive suggestions are enabled.
    if not (profile.defensives and profile.defensives.showPetHealthBar) then return nil end

    local useDefensiveDims = isDetached or (defensivesEnabled or false)

    -- Only create for pet classes
    local _, playerClass = UnitClass("player")
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not SpellDB then return nil end
    local hasPetSpells = (SpellDB.CLASS_PET_REZ_DEFAULTS and SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass])
        or (SpellDB.CLASS_PETHEAL_DEFAULTS and SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass])
    if not hasPetSpells then return nil end

    local iconSize    = profile.iconSize or 42
    local iconSpacing = profile.iconSpacing or 1
    local queueDimension, offset
    local barIsHorizontal
    local frame

    local playerBarExists = (healthBarFrame ~= nil) and (profile.defensives and profile.defensives.showHealthBar)

    if isDetached then
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local isVert = (detachOrientation == "UP" or detachOrientation == "DOWN")
        local defIconScale = profile.defensives.iconScale or 1.0
        local defIconSize  = iconSize * defIconScale
        local maxDefIcons  = math.min(profile.defensives.maxIcons or 1, 7)

        if maxDefIcons == 1 then
            queueDimension = defIconSize
        else
            queueDimension = defIconSize * 0.90 + (maxDefIcons - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
        end
        offset = maxDefIcons == 1 and 0 or (defIconSize * 0.10)

        frame = CreateFrame("Frame", nil, addon.defensiveFrame)
        local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
        local grabTabSpacing = isVert and (iconSpacing + 12) or (iconSpacing + 13)

        if detachOrientation == "LEFT" then
            barIsHorizontal = true
            frame:SetSize(queueDimension, BAR_HEIGHT)
            frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "TOPLEFT", offset, BAR_SPACING + extraOffset)
        elseif detachOrientation == "RIGHT" then
            barIsHorizontal = true
            frame:SetSize(queueDimension, BAR_HEIGHT)
            frame:SetPoint("BOTTOMRIGHT", addon.defensiveFrame, "TOPRIGHT", -offset, BAR_SPACING + extraOffset)
        elseif detachOrientation == "UP" then
            barIsHorizontal = false
            frame:SetSize(BAR_HEIGHT, queueDimension)
            frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "BOTTOMRIGHT", BAR_SPACING + extraOffset, grabTabSpacing + offset)
        else -- DOWN
            barIsHorizontal = false
            frame:SetSize(BAR_HEIGHT, queueDimension)
            frame:SetPoint("TOPLEFT", addon.defensiveFrame, "TOPRIGHT", BAR_SPACING + extraOffset, -(grabTabSpacing + offset))
        end
    else
        -- Attached mode: parent to mainFrame
        local orientation = profile.queueOrientation or "LEFT"
        barIsHorizontal = (orientation == "LEFT" or orientation == "RIGHT")

        -- For RIGHT/UP, icons are shifted within the frame to keep the grab tab at a
        -- predictable position.  Pet health bars must match that shift.
        local grabTabReserve = 0
        if orientation == "RIGHT" or orientation == "UP" then
            local GRAB_TAB_LENGTH = 12
            local isVert = (orientation == "UP")
            grabTabReserve = iconSpacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
        end

        frame = CreateFrame("Frame", nil, addon.mainFrame)

        if useDefensiveDims then
            -- Span the defensive icon cluster
            local defIconScale = profile.defensives.iconScale or 1.0
            local defIconSize  = iconSize * defIconScale
            local maxDefIcons  = math.min(profile.defensives.maxIcons or 4, 7)
            local defPosition  = profile.defensives.position or "SIDE1"

            if maxDefIcons == 1 then
                queueDimension = defIconSize
            else
                queueDimension = defIconSize * 0.90 + (maxDefIcons - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
            end
            offset = maxDefIcons == 1 and 0 or (defIconSize * 0.10)

            local defSpacing = math.max(iconSpacing, BAR_SPACING)
            local barDist    = defSpacing + defIconSize + BAR_SPACING
            local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
            local dist = barDist + extraOffset

            if barIsHorizontal then
                frame:SetSize(queueDimension, BAR_HEIGHT)
            else
                frame:SetSize(BAR_HEIGHT, queueDimension)
            end

            -- SIDE1/SIDE2 positioning, offset one bar-height further out
            if orientation == "LEFT" then
                if defPosition == "SIDE1" then
                    frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",      offset,  dist)
                else
                    frame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT",   offset, -dist)
                end
            elseif orientation == "RIGHT" then
                if defPosition == "SIDE1" then
                    frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -(offset + grabTabReserve),  dist)
                else
                    frame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -(offset + grabTabReserve), -dist)
                end
            elseif orientation == "DOWN" then
                if defPosition == "SIDE1" then
                    frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",     dist,   -offset)
                else
                    frame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",     -dist,   -offset)
                end
            else -- UP
                if defPosition == "SIDE1" then
                    frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  dist,    offset + grabTabReserve)
                else
                    frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -dist,    offset + grabTabReserve)
                end
            end
        else
            -- Span the offensive queue; stack beyond player bar above mainFrame
            local firstIconScale = profile.firstIconScale or 1.0
            local maxIcons       = profile.maxIcons or 4
            local firstIconSize  = iconSize * firstIconScale

            if maxIcons == 1 then
                queueDimension = firstIconSize
            else
                queueDimension = firstIconSize * 0.90 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.90
            end
            offset = maxIcons == 1 and 0 or (firstIconSize * 0.10)

            if barIsHorizontal then
                frame:SetSize(queueDimension, BAR_HEIGHT)
            else
                frame:SetSize(BAR_HEIGHT, queueDimension)
            end

            local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
            local baseDist = BAR_SPACING + extraOffset

            if orientation == "LEFT" then
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",    offset,     baseDist)
            elseif orientation == "RIGHT" then
                frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",  -(offset + grabTabReserve),     baseDist)
            elseif orientation == "DOWN" then
                frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",   baseDist, -offset)
            else -- UP
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT", baseDist, offset + grabTabReserve)
            end
        end
    end

    -- ── Shared: StatusBar, background, bevel ──────────────────────────────────
    -- Create StatusBar (accepts secret values!)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    statusBar:SetOrientation(barIsHorizontal and "HORIZONTAL" or "VERTICAL")

    -- Warm yellow for pet (distinct from player's green and UI blue/mana)
    statusBar:SetStatusBarColor(0.90, 0.75, 0.10, 0.9)

    -- Background (dark red when pet is hurt/missing health shows through)
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.6, 0.15, 0.15, 0.9)

    -- 4-strip tube bevel (symmetric horizontal, same as player bar).
    if barIsHorizontal then
        local shBot1 = statusBar:CreateTexture(nil, "OVERLAY")
        shBot1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shBot1:SetVertexColor(0, 0, 0, 0.35)
        shBot1:SetPoint("BOTTOMLEFT",  statusBar, "BOTTOMLEFT",  0, 0)
        shBot1:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        shBot1:SetHeight(1)

        local shBot2 = statusBar:CreateTexture(nil, "OVERLAY")
        shBot2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shBot2:SetVertexColor(0, 0, 0, 0.16)
        shBot2:SetPoint("BOTTOMLEFT",  statusBar, "BOTTOMLEFT",  0, 1)
        shBot2:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 1)
        shBot2:SetHeight(1)

        local shTop1 = statusBar:CreateTexture(nil, "OVERLAY")
        shTop1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shTop1:SetVertexColor(0, 0, 0, 0.16)
        shTop1:SetPoint("TOPLEFT",  statusBar, "TOPLEFT",  0, -1)
        shTop1:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, -1)
        shTop1:SetHeight(1)

        local shTop2 = statusBar:CreateTexture(nil, "OVERLAY")
        shTop2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shTop2:SetVertexColor(0, 0, 0, 0.35)
        shTop2:SetPoint("TOPLEFT",  statusBar, "TOPLEFT",  0, 0)
        shTop2:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
        shTop2:SetHeight(1)
    else
        local shL1 = statusBar:CreateTexture(nil, "OVERLAY")
        shL1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shL1:SetVertexColor(0, 0, 0, 0.35)
        shL1:SetPoint("TOPLEFT",    statusBar, "TOPLEFT",    0, 0)
        shL1:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 0, 0)
        shL1:SetWidth(1)

        local shL2 = statusBar:CreateTexture(nil, "OVERLAY")
        shL2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shL2:SetVertexColor(0, 0, 0, 0.16)
        shL2:SetPoint("TOPLEFT",    statusBar, "TOPLEFT",    1, 0)
        shL2:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 1, 0)
        shL2:SetWidth(1)

        local shR1 = statusBar:CreateTexture(nil, "OVERLAY")
        shR1:SetTexture("Interface\\Buttons\\WHITE8X8")
        shR1:SetVertexColor(0, 0, 0, 0.16)
        shR1:SetPoint("TOPRIGHT",    statusBar, "TOPRIGHT",    -1, 0)
        shR1:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", -1, 0)
        shR1:SetWidth(1)

        local shR2 = statusBar:CreateTexture(nil, "OVERLAY")
        shR2:SetTexture("Interface\\Buttons\\WHITE8X8")
        shR2:SetVertexColor(0, 0, 0, 0.35)
        shR2:SetPoint("TOPRIGHT",    statusBar, "TOPRIGHT",    0, 0)
        shR2:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        shR2:SetWidth(1)
    end

    -- Dead overlay (red tint, hidden by default)
    local deadOverlay = frame:CreateTexture(nil, "ARTWORK")
    deadOverlay:SetAllPoints(frame)
    deadOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    deadOverlay:SetVertexColor(0.8, 0.1, 0.1, 0.5)
    deadOverlay:Hide()

    frame.statusBar = statusBar
    frame.background = bg
    frame.deadOverlay = deadOverlay
    frame.useDefensiveDims = useDefensiveDims

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
    if ok and isDead and not BlizzardAPI.IsSecretValue(isDead) then
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

function UIHealthBar.HidePet()
    if petHealthBarFrame then
        petHealthBarFrame:Hide()
    end
end

--- Dynamically resize the pet health bar to match the number of visible defensive icons.
--- Mirrors ResizeToCount but stacks beyond the player health bar.
--- When visibleCount is 0, falls back to offensive-queue positioning (stacked
--- beyond the player health bar) so the pet bar stays visible.
--- @param addon table  The main addon object
--- @param visibleCount number  Number of currently visible defensive icons (0 = fallback to offensive)
function UIHealthBar.ResizePetToCount(addon, visibleCount)
    if not petHealthBarFrame then return end

    -- Standalone mode spans the offensive queue — no per-count resize needed
    if not petHealthBarFrame.useDefensiveDims then return end

    -- Cache check: skip expensive recalc when count hasn't changed
    if visibleCount == lastPetVisibleCount then return end
    lastPetVisibleCount = visibleCount

    local profile = addon.db and addon.db.profile
    if not profile then return end

    local isDetached = profile.defensives and profile.defensives.detached
    if isDetached then
        -- Detached: no offensive fallback — just hide when no icons visible.
        if visibleCount <= 0 then
            petHealthBarFrame:Hide()
            return
        end
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local isVert = (detachOrientation == "UP" or detachOrientation == "DOWN")
        local iconSize    = profile.iconSize or 42
        local iconSpacing = profile.iconSpacing or 1
        local defIconScale = profile.defensives.iconScale or 1.0
        local defIconSize  = iconSize * defIconScale

        local queueDimension
        if visibleCount == 1 then
            queueDimension = defIconSize
        else
            queueDimension = defIconSize * 0.90 + (visibleCount - 2) * (defIconSize + iconSpacing) + defIconSize * 0.90
        end
        local offset = visibleCount == 1 and 0 or (defIconSize * 0.10)

        local playerBarExists = (healthBarFrame ~= nil) and (profile.defensives and profile.defensives.showHealthBar)
        local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0

        local grabTabSpacing = isVert and (iconSpacing + 12) or (iconSpacing + 13)
        petHealthBarFrame:ClearAllPoints()
        if detachOrientation == "LEFT" then
            petHealthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
            petHealthBarFrame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "TOPLEFT", offset, BAR_SPACING + extraOffset)
        elseif detachOrientation == "RIGHT" then
            petHealthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
            petHealthBarFrame:SetPoint("BOTTOMRIGHT", addon.defensiveFrame, "TOPRIGHT", -offset, BAR_SPACING + extraOffset)
        elseif detachOrientation == "UP" then
            petHealthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
            petHealthBarFrame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "BOTTOMRIGHT", BAR_SPACING + extraOffset, grabTabSpacing + offset)
        else -- DOWN
            petHealthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
            petHealthBarFrame:SetPoint("TOPLEFT", addon.defensiveFrame, "TOPRIGHT", BAR_SPACING + extraOffset, -(grabTabSpacing + offset))
        end
        petHealthBarFrame:Show()
        return
    end

    local orientation = profile.queueOrientation or "LEFT"
    local iconSize    = profile.iconSize or 42
    local iconSpacing = profile.iconSpacing or 1

    local grabTabReserve = 0
    if orientation == "RIGHT" or orientation == "UP" then
        local GRAB_TAB_LENGTH = 12
        local isVert = (orientation == "UP")
        grabTabReserve = iconSpacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
    end

    local playerBarExists = (healthBarFrame ~= nil)
        and (profile.defensives and profile.defensives.showHealthBar)

    petHealthBarFrame:ClearAllPoints()

    if visibleCount <= 0 then
        -- No defensive icons → fall back to offensive queue dims, stacked beyond player bar
        local firstIconScale = profile.firstIconScale or 1.0
        local maxIcons       = profile.maxIcons or 4
        local firstIconSize  = iconSize * firstIconScale

        local queueDimension
        if maxIcons == 1 then
            queueDimension = firstIconSize
        else
            queueDimension = firstIconSize * 0.90 + (maxIcons - 2) * (iconSize + iconSpacing) + iconSize * 0.90
        end
        local offset = maxIcons == 1 and 0 or (firstIconSize * 0.10)

        if orientation == "LEFT" or orientation == "RIGHT" then
            petHealthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
        else
            petHealthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
        end

        local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
        local baseDist = BAR_SPACING + extraOffset

        if orientation == "LEFT" then
            petHealthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",    offset,     baseDist)
        elseif orientation == "RIGHT" then
            petHealthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",  -(offset + grabTabReserve),     baseDist)
        elseif orientation == "DOWN" then
            petHealthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",   baseDist, -offset)
        else -- UP
            petHealthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT", baseDist, offset + grabTabReserve)
        end

        petHealthBarFrame:Show()
        return
    end

    if not profile.defensives then return end

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
        petHealthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
    else
        petHealthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Reposition: stack beyond the player health bar
    local defSpacing = math.max(iconSpacing, BAR_SPACING)
    local barDist    = defSpacing + defIconSize + BAR_SPACING
    local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
    local dist = barDist + extraOffset

    if orientation == "LEFT" then
        if defPosition == "SIDE1" then
            petHealthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",      offset,  dist)
        else
            petHealthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT",   offset, -dist)
        end
    elseif orientation == "RIGHT" then
        if defPosition == "SIDE1" then
            petHealthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",    -(offset + grabTabReserve),  dist)
        else
            petHealthBarFrame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -(offset + grabTabReserve), -dist)
        end
    elseif orientation == "DOWN" then
        if defPosition == "SIDE1" then
            petHealthBarFrame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",     dist,   -offset)
        else
            petHealthBarFrame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",     -dist,   -offset)
        end
    else -- UP
        if defPosition == "SIDE1" then
            petHealthBarFrame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT",  dist,    offset + grabTabReserve)
        else
            petHealthBarFrame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT",  -dist,    offset + grabTabReserve)
        end
    end

    petHealthBarFrame:Show()
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
    lastPetVisibleCount = -1
end
