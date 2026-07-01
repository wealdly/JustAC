-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Health Bar Module - Shows player health bar for low-health warning
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 9)
if not UIHealthBar then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Hot path cache
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local GetTime = GetTime

-- Constants
local UPDATE_INTERVAL = 0.1   -- Update frequently enough for responsive feedback
local BAR_HEIGHT = 6          -- Compact height in pixels
local BAR_SPACING = 3         -- Spacing between health bar and queue icons

-- Export constants for UIFrameFactory to calculate defensive icon offset
UIHealthBar.BAR_HEIGHT = BAR_HEIGHT
UIHealthBar.BAR_SPACING = BAR_SPACING

-- ── Shared queue-construction math (single source of truth for every bar) ─────
-- These mirror the icon queue the bar sits next to; keeping them centralized is
-- what prevents create/resize drift (e.g. the past defSpacing mismatch).

local GRAB_TAB_LENGTH = 12

--- Pixel span + first-icon inset for a bar mirroring a queue of `count` icons.
--- The first icon may be scaled (firstSize); the rest are bodySize. The 0.90 factors
--- inset the bar slightly from the outermost icons; the returned offset shifts the bar
--- so it stays centered over the (possibly larger) first icon.
--- @return number dimension, number offset
local function ComputeBarSpan(firstSize, bodySize, spacing, count)
    if count <= 1 then
        return firstSize, 0
    end
    return firstSize * 0.90 + (count - 2) * (bodySize + spacing) + bodySize * 0.90,
           firstSize * 0.10
end

--- Grab-tab reserve length for a given axis (horizontal bars add a 1px border fudge).
local function GrabTabLength(isVertical, iconSpacing)
    return iconSpacing + GRAB_TAB_LENGTH + (isVertical and 0 or 1)
end

--- Attached mode: only RIGHT/UP shift the icons to reserve the tab edge; LEFT/DOWN keep 0.
local function GrabTabReserve(orientation, iconSpacing)
    if orientation ~= "RIGHT" and orientation ~= "UP" then return 0 end
    return GrabTabLength(orientation == "UP", iconSpacing)
end

--- Distance a bar floats beyond the defensive cluster: the cluster sits iconSpacing from
--- the mainFrame, and the bar clears it by BAR_SPACING. One formula so create/resize agree.
local function DefensiveBarDist(defIconSize, iconSpacing)
    return iconSpacing + defIconSize + BAR_SPACING
end

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
-- 1px black tube bevel on statusBar's OVERLAY layer (engine can't clobber it).
-- Horizontal bars bevel top+bottom; vertical bars bevel left+right. Alphas: 0.35 outer / 0.16 inner.
local function AddTubeBevel(statusBar, barIsHorizontal)
    local function strip(alpha, a, b, ox, oy, horizontal)
        local t = statusBar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(0, 0, 0, alpha)
        t:SetPoint(a, statusBar, a, ox, oy)
        t:SetPoint(b, statusBar, b, ox, oy)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    if barIsHorizontal then
        strip(0.35, "BOTTOMLEFT", "BOTTOMRIGHT", 0,  0, true)
        strip(0.16, "BOTTOMLEFT", "BOTTOMRIGHT", 0,  1, true)
        strip(0.16, "TOPLEFT",    "TOPRIGHT",    0, -1, true)
        strip(0.35, "TOPLEFT",    "TOPRIGHT",    0,  0, true)
    else
        strip(0.35, "TOPLEFT",  "BOTTOMLEFT",  0, 0, false)
        strip(0.16, "TOPLEFT",  "BOTTOMLEFT",  1, 0, false)
        strip(0.16, "TOPRIGHT", "BOTTOMRIGHT", -1, 0, false)
        strip(0.35, "TOPRIGHT", "BOTTOMRIGHT", 0, 0, false)
    end
end

-- Shared depleted-health background. One neutral dark tone behind every bar so the
-- fill color (player green / pet yellow / target red) is what reads as "remaining",
-- and the missing portion is clearly visible against all three.
local function AddBarBackground(statusBar)
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.12, 0.12, 0.12, 0.9)
    return bg
end

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

        queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, maxDefIcons)

        frame = CreateFrame("Frame", nil, addon.defensiveFrame)
        useDefensiveDims = true

        -- grabTabSpacing mirrors UpdateDefensiveFrameSize: spacing + 12 (vert) or spacing + 13 (horiz)
        local grabTabSpacing = GrabTabLength(isVert, iconSpacing)

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
        local grabTabReserve = GrabTabReserve(orientation, iconSpacing)

        if useDefensiveDims then
            -- Span the defensive icon cluster; float on the far side (away from mainFrame)
            local defIconScale = profile.defensives.iconScale or 1.0
            local defIconSize  = iconSize * defIconScale
            local maxDefIcons  = math.min(profile.defensives.maxIcons or 1, 7)
            local defPosition  = profile.defensives.position or "SIDE1"

            queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, maxDefIcons)

            -- Defensive icons sit at iconSpacing from mainFrame edge; bar floats
            -- BAR_SPACING beyond the outer edge of that cluster.
            local barDist = DefensiveBarDist(defIconSize, iconSpacing)

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

            queueDimension, offset = ComputeBarSpan(firstIconSize, iconSize, iconSpacing, maxIcons)

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

    -- Neutral dark background (shared across all bars) so missing health reads clearly.
    AddBarBackground(statusBar)

    -- 4-strip tube bevel on OVERLAY so the engine never clobbers them.
    -- Horizontal: symmetric alphas (bright band dead-centre on 6 px bar).
    -- Vertical:   asymmetric (near-queue heavier) - bar is wide enough.
    AddTubeBevel(statusBar, barIsHorizontal)

    -- Low-health pulse: gently throbs the bar when GetLowHealthState() (~35% binary)
    -- crosses. Stopped by default; driven by Update on state transitions only.
    local pulse = statusBar:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local pulseAlpha = pulse:CreateAnimation("Alpha")
    pulseAlpha:SetFromAlpha(1.0)
    pulseAlpha:SetToAlpha(0.65)   -- shallow: stays clearly visible; the throb is the cue
    pulseAlpha:SetDuration(0.45)
    pulseAlpha:SetSmoothing("IN_OUT")
    statusBar.lowHealthPulse = pulse

    frame.statusBar = statusBar
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

    -- Low-health cue via the non-secret ~35% binary. Keep the green fill (high contrast
    -- against the red background) and let a gentle pulse be the signal. Applied only on
    -- state transition; the pulse animates independently.
    local isLow = (BlizzardAPI and BlizzardAPI.GetLowHealthState and BlizzardAPI.GetLowHealthState()) or false
    if isLow ~= healthBarFrame.isLowHealth then
        healthBarFrame.isLowHealth = isLow
        if statusBar.lowHealthPulse then
            if isLow then
                statusBar.lowHealthPulse:Play()
            else
                statusBar.lowHealthPulse:Stop()
                statusBar:SetAlpha(1)
            end
        end
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
        -- Detached: no offensive fallback - just hide when no icons visible.
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

        local queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, visibleCount)

        local grabTabSpacing = GrabTabLength(isVert, iconSpacing)
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
    local grabTabReserve = GrabTabReserve(orientation, iconSpacing)

    healthBarFrame:ClearAllPoints()

    if visibleCount <= 0 then
        -- No defensive icons visible → fall back to offensive queue dimensions/position
        -- so the health bar stays on screen (mirrors the non-defensive path in CreateHealthBar).
        local firstIconScale = profile.firstIconScale or 1.0
        local maxIcons       = profile.maxIcons or 4
        local firstIconSize  = iconSize * firstIconScale

        local queueDimension, offset = ComputeBarSpan(firstIconSize, iconSize, iconSpacing, maxIcons)

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

    local queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, visibleCount)

    -- Resize
    if orientation == "LEFT" or orientation == "RIGHT" then
        healthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
    else
        healthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Reposition to stay aligned above/below the visible cluster (BAR_SPACING gap).
    local barDist = DefensiveBarDist(defIconSize, iconSpacing)

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
-- UnitExists/UnitIsDead are NOT secret - used for visibility/dead state
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
    if not SpellDB.ClassHasPetDefaults(playerClass) then return nil end

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

        queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, maxDefIcons)

        frame = CreateFrame("Frame", nil, addon.defensiveFrame)
        local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
        local grabTabSpacing = GrabTabLength(isVert, iconSpacing)

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
        local grabTabReserve = GrabTabReserve(orientation, iconSpacing)

        frame = CreateFrame("Frame", nil, addon.mainFrame)

        if useDefensiveDims then
            -- Span the defensive icon cluster
            local defIconScale = profile.defensives.iconScale or 1.0
            local defIconSize  = iconSize * defIconScale
            local maxDefIcons  = math.min(profile.defensives.maxIcons or 4, 7)
            local defPosition  = profile.defensives.position or "SIDE1"

            queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, maxDefIcons)

            local barDist = DefensiveBarDist(defIconSize, iconSpacing)
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

            queueDimension, offset = ComputeBarSpan(firstIconSize, iconSize, iconSpacing, maxIcons)

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

    -- Neutral dark background (shared across all bars).
    AddBarBackground(statusBar)

    -- 4-strip tube bevel (symmetric horizontal, same as player bar).
    AddTubeBevel(statusBar, barIsHorizontal)

    -- Dead overlay (red tint, hidden by default)
    local deadOverlay = frame:CreateTexture(nil, "ARTWORK")
    deadOverlay:SetAllPoints(frame)
    deadOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    deadOverlay:SetVertexColor(0.8, 0.1, 0.1, 0.5)
    deadOverlay:Hide()

    frame.statusBar = statusBar
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
    -- UnitIsDead is NOT secret in 12.0 - safe to compare directly
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
    -- The bar will show, just with unknown fill level - better than hiding it.
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

    -- Standalone mode spans the offensive queue - no per-count resize needed
    if not petHealthBarFrame.useDefensiveDims then return end

    -- Cache check: skip expensive recalc when count hasn't changed
    if visibleCount == lastPetVisibleCount then return end
    lastPetVisibleCount = visibleCount

    local profile = addon.db and addon.db.profile
    if not profile then return end

    local isDetached = profile.defensives and profile.defensives.detached
    if isDetached then
        -- Detached: no offensive fallback - just hide when no icons visible.
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

        local queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, visibleCount)

        local playerBarExists = (healthBarFrame ~= nil) and (profile.defensives and profile.defensives.showHealthBar)
        local extraOffset = playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0

        local grabTabSpacing = GrabTabLength(isVert, iconSpacing)
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

    local grabTabReserve = GrabTabReserve(orientation, iconSpacing)

    local playerBarExists = (healthBarFrame ~= nil)
        and (profile.defensives and profile.defensives.showHealthBar)

    petHealthBarFrame:ClearAllPoints()

    if visibleCount <= 0 then
        -- No defensive icons → fall back to offensive queue dims, stacked beyond player bar
        local firstIconScale = profile.firstIconScale or 1.0
        local maxIcons       = profile.maxIcons or 4
        local firstIconSize  = iconSize * firstIconScale

        local queueDimension, offset = ComputeBarSpan(firstIconSize, iconSize, iconSpacing, maxIcons)

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

    local queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, visibleCount)

    -- Resize
    if orientation == "LEFT" or orientation == "RIGHT" then
        petHealthBarFrame:SetSize(queueDimension, BAR_HEIGHT)
    else
        petHealthBarFrame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Reposition: stack beyond the player health bar
    local barDist = DefensiveBarDist(defIconSize, iconSpacing)
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

--------------------------------------------------------------------------------
-- Target Health Bar (hostile-only). Always spans the OFFENSIVE queue and hugs the
-- OPPOSITE edge from the player/pet bars (below for horizontal queues, left for
-- vertical), a fixed BAR_SPACING gap from the queue. No defensive-cluster spanning,
-- no detached mode, no per-count resize - it hugs the queue directly.
-- UnitHealth("target") is secret in combat but StatusBar:SetValue accepts secrets;
-- UnitExists/UnitCanAttack gate visibility (NeverSecret OOC, secret-safe in combat).
-- ponytail: if defensive icons sit on SIDE2 (below a horizontal queue) this bar can
-- overlap that cluster; defaults put defensives on SIDE1 (above), so it's clear in
-- the common case. Add a SIDE2-aware offset only if users actually hit this.
--------------------------------------------------------------------------------

local targetHealthBarFrame = nil
local lastTargetUpdate = 0

-- Offensive-queue span (dimension + first-icon offset) read straight from the profile;
-- same math as the player/pet bars, via the shared ComputeBarSpan.
local function ComputeOffensiveSpan(profile)
    local iconSize       = profile.iconSize or 42
    local iconSpacing    = profile.iconSpacing or 1
    local firstIconScale = profile.firstIconScale or 1.0
    local maxIcons       = profile.maxIcons or 4
    return ComputeBarSpan(iconSize * firstIconScale, iconSize, iconSpacing, maxIcons)
end

-- Size + anchor the target bar: spans the offensive queue and hugs the OPPOSITE
-- mainFrame edge to the player/pet bars (below for horizontal queues, left for
-- vertical), a BAR_SPACING gap from the queue. Returns whether the bar is
-- horizontal (for StatusBar setup).
--
-- Note: this hugs the QUEUE, not "the same distance as the player bar." The player
-- bar's larger gap is filled by the defensive icon cluster between it and the queue;
-- there are no icons on the target side, so matching that distance would just leave
-- an empty gap. Hugging the queue keeps the same visual tightness (3px to nearest UI).
local function PositionTargetBar(frame, mainFrame, profile)
    local orientation = profile.queueOrientation or "LEFT"
    local barIsHorizontal = (orientation == "LEFT" or orientation == "RIGHT")
    local iconSpacing = profile.iconSpacing or 1

    -- RIGHT/UP shift icons within the frame to keep the grab tab predictable;
    -- match that shift so the bar stays aligned with the icons.
    local grabTabReserve = GrabTabReserve(orientation, iconSpacing)

    local queueDimension, offset = ComputeOffensiveSpan(profile)
    if barIsHorizontal then
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end

    frame:ClearAllPoints()
    if orientation == "LEFT" then
        frame:SetPoint("TOPLEFT",     mainFrame, "BOTTOMLEFT",   offset,                     -BAR_SPACING)
    elseif orientation == "RIGHT" then
        frame:SetPoint("TOPRIGHT",    mainFrame, "BOTTOMRIGHT", -(offset + grabTabReserve),  -BAR_SPACING)
    elseif orientation == "DOWN" then
        frame:SetPoint("TOPRIGHT",    mainFrame, "TOPLEFT",     -BAR_SPACING,                -offset)
    else -- UP
        frame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMLEFT",  -BAR_SPACING,                 offset + grabTabReserve)
    end
    return barIsHorizontal
end

-- Show the bar only for an existing, attackable target. UnitCanAttack can be
-- secret in combat - when unreadable, fall back to showing (a visible bar beats
-- hiding a valid target).
local function ShouldShowTargetBar()
    if not UnitExists("target") then return false end
    if not UnitCanAttack then return true end
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    if ok and canAttack ~= nil and not (BlizzardAPI and BlizzardAPI.IsSecretValue(canAttack)) then
        return canAttack == true
    end
    return true
end

function UIHealthBar.CreateTargetHealthBar(addon)
    if targetHealthBarFrame then
        targetHealthBarFrame:Hide()
        targetHealthBarFrame:SetParent(nil)
        targetHealthBarFrame = nil
    end

    if not addon or not addon.db or not addon.db.profile then return nil end
    local profile = addon.db.profile
    if not (profile.defensives and profile.defensives.showTargetHealthBar) then return nil end
    if not addon.mainFrame then return nil end

    local frame = CreateFrame("Frame", nil, addon.mainFrame)
    local barIsHorizontal = PositionTargetBar(frame, addon.mainFrame, profile)

    -- StatusBar (accepts secrets), shared dark background, red fill.
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    statusBar:SetOrientation(barIsHorizontal and "HORIZONTAL" or "VERTICAL")
    statusBar:SetStatusBarColor(0.85, 0.10, 0.10, 0.9)  -- red (hostile target)

    AddBarBackground(statusBar)
    AddTubeBevel(statusBar, barIsHorizontal)

    frame.statusBar = statusBar
    targetHealthBarFrame = frame

    UIHealthBar.UpdateTargetVisibility(addon)
    return frame
end

-- Update target health value on timer.
function UIHealthBar.UpdateTarget(addon)
    if not targetHealthBarFrame or not targetHealthBarFrame:IsVisible() then return end

    local now = GetTime()
    if now - lastTargetUpdate < UPDATE_INTERVAL then return end
    lastTargetUpdate = now

    if not UnitExists("target") then
        targetHealthBarFrame:Hide()
        return
    end

    local health = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")
    if not health or not maxHealth then return end

    local statusBar = targetHealthBarFrame.statusBar
    if not statusBar then return end

    -- SetMinMaxValues/SetValue accept secret values directly (rendered by Blizzard).
    statusBar:SetMinMaxValues(0, maxHealth)
    statusBar:SetValue(health)
end

-- Show/hide based on target existence + hostility.
function UIHealthBar.UpdateTargetVisibility(addon)
    if not targetHealthBarFrame then return end
    if ShouldShowTargetBar() then
        targetHealthBarFrame:Show()
        UIHealthBar.UpdateTarget(addon)
    else
        targetHealthBarFrame:Hide()
    end
end

function UIHealthBar.HideTarget()
    if targetHealthBarFrame then
        targetHealthBarFrame:Hide()
    end
end

-- Recreate on size/orientation change (mirrors UpdateSize/UpdatePetSize).
function UIHealthBar.UpdateTargetSize(addon)
    if not addon or not addon.db or not addon.db.profile then return end
    if targetHealthBarFrame then
        UIHealthBar.DestroyTarget()
    end
    UIHealthBar.CreateTargetHealthBar(addon)
end

function UIHealthBar.DestroyTarget()
    if targetHealthBarFrame then
        targetHealthBarFrame:Hide()
        targetHealthBarFrame:SetParent(nil)
        targetHealthBarFrame = nil
    end
    lastTargetUpdate = 0
end
