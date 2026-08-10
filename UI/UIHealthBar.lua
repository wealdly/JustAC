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
local POWER_BAR_HEIGHT = 3   -- Resource bars are half height, distinct from health
-- Shared fill texture for every bar. Flat white keeps the tint at full brightness; the
-- gradient client texture (UI-StatusBar) is dark at its top/bottom edges, which dominate
-- and read as murky at 3-6px, so the unit-frame look comes from the colored drained-wash
-- background instead. Single knob if a brighter bar texture ever wants swapping in.
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BAR_SPACING = 3         -- Spacing between health bar and queue icons

-- Export constants for UIFrameFactory to calculate defensive icon offset
UIHealthBar.BAR_HEIGHT = BAR_HEIGHT
UIHealthBar.BAR_SPACING = BAR_SPACING
UIHealthBar.POWER_BAR_HEIGHT = POWER_BAR_HEIGHT  -- shared with the nameplate overlay's resource bars

-- ── Shared queue-construction math (single source of truth for every bar) ─────
-- These mirror the icon queue the bar sits next to; keeping them centralized is
-- what prevents create/resize drift (e.g. the past defSpacing mismatch).

local GRAB_TAB_LENGTH = 12
UIHealthBar.GRAB_TAB_LENGTH = GRAB_TAB_LENGTH  -- shared with UIFrameFactory, which draws the tab

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

-- Offensive-queue span (dimension + first-icon offset) read straight from the profile;
-- same math as the player/pet bars, via the shared ComputeBarSpan. Defined here (not
-- in the target-bar section) so the power bar - which precedes it - can use it too.
local function ComputeOffensiveSpan(profile)
    local iconSize       = profile.iconSize or 42
    local iconSpacing    = profile.iconSpacing or 1
    local firstIconScale = profile.firstIconScale or 1.0
    local maxIcons       = profile.maxIcons or 4
    return ComputeBarSpan(iconSize * firstIconScale, iconSize, iconSpacing, maxIcons)
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

--- Depth of the attached SIDE1 defensive row (0 when it can't occupy that band).
--- One owner for the predicate + formula: the danger cue's lift (UIRenderer) and
--- the resource-bar fallback below both clear this row, and two inline copies of
--- the predicate would drift.
function UIHealthBar.AttachedDefRowDepth(profile)
    local def = profile and profile.defensives
    if not (def and def.enabled ~= false and not def.detached
            and (def.position or "SIDE1") == "SIDE1") then
        return 0
    end
    return (profile.iconSpacing or 1) + (profile.iconSize or 42) * (def.iconScale or 1.0)
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
-- Returns the four strips. Pass startHidden when the caller builds BOTH orientations up
-- front and toggles them at runtime (the nameplate overlay does; its bars re-orient).
local function AddTubeBevel(statusBar, barIsHorizontal, startHidden)
    local function strip(alpha, a, b, ox, oy, horizontal)
        local t = statusBar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(0, 0, 0, alpha)
        t:SetPoint(a, statusBar, a, ox, oy)
        t:SetPoint(b, statusBar, b, ox, oy)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        if startHidden then t:Hide() end
        return t
    end
    if barIsHorizontal then
        return {
            strip(0.35, "BOTTOMLEFT", "BOTTOMRIGHT", 0,  0, true),
            strip(0.16, "BOTTOMLEFT", "BOTTOMRIGHT", 0,  1, true),
            strip(0.16, "TOPLEFT",    "TOPRIGHT",    0, -1, true),
            strip(0.35, "TOPLEFT",    "TOPRIGHT",    0,  0, true),
        }
    end
    return {
        strip(0.35, "TOPLEFT",  "BOTTOMLEFT",   0, 0, false),
        strip(0.16, "TOPLEFT",  "BOTTOMLEFT",   1, 0, false),
        strip(0.16, "TOPRIGHT", "BOTTOMRIGHT", -1, 0, false),
        strip(0.35, "TOPRIGHT", "BOTTOMRIGHT",  0, 0, false),
    }
end
UIHealthBar.AddTubeBevel = AddTubeBevel  -- shared with the nameplate overlay

-- Shared depleted-health background. One neutral dark tone behind every bar so the
-- fill color (player green / pet yellow / target red) is what reads as "remaining",
-- and the missing portion is clearly visible against all three.
local function AddBarBackground(statusBar)
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.12, 0.12, 0.12, 0.9)
    statusBar.bg = bg  -- exposed so a resource bar can re-tint it to its power color
    return bg
end

-- Glossy sheen: a white highlight fading to transparent, laid over the fill so each bar
-- reads like a lit glass tube. White-only, so it brightens the tint and never darkens it
-- (unlike a dark gradient texture, which muddies thin bars). Horizontal bars get a top
-- highlight; vertical bars a one-side highlight. Drawn just above the fill, below dividers.
local function AddBarGloss(statusBar, barIsHorizontal)
    local gloss = statusBar:CreateTexture(nil, "OVERLAY", nil, 0)
    gloss:SetTexture("Interface\\Buttons\\WHITE8X8")
    gloss:SetAllPoints(statusBar)
    local lit  = CreateColor(1, 1, 1, 0.22)
    local dark = CreateColor(1, 1, 1, 0.00)
    -- VERTICAL/HORIZONTAL gradient runs min->max = bottom->top / left->right.
    gloss:SetGradient(barIsHorizontal and "VERTICAL" or "HORIZONTAL", dark, lit)
    return gloss
end

-- Shared with the nameplate overlay so its health bars get identical styling.
UIHealthBar.AddBarBackground = AddBarBackground
UIHealthBar.AddBarGloss      = AddBarGloss

-- ── Per-bar configuration ─────────────────────────────────────────────────────
-- Everything that differs between the player and pet health bars. Geometry,
-- textures, bevel, gloss, and update cadence are identical; only these knobs vary.
local BAR_KINDS = {
    player = {
        showKey = "showHealthBar",        -- profile.defensives visibility toggle
        color = {0.0, 0.80, 0.0, 0.9},    -- bright green (matches nameplate overlay bar)
        stacked = false,                  -- anchors at the base position
        lowHealthPulse = true,            -- throbs on the low-health binary
        deadOverlay = false,
        requiresPetClass = false,
    },
    pet = {
        showKey = "showPetHealthBar",
        color = {0.90, 0.75, 0.10, 0.9},  -- warm yellow for pet (distinct from player's green and UI blue/mana)
        stacked = true,                   -- sits one bar-height + gap beyond the player bar
        lowHealthPulse = false,
        deadOverlay = true,               -- red tint shown while the pet is dead
        requiresPetClass = true,          -- only created for pet classes
    },
}

--- Stacking offset shared by builder and resizer: a stacked bar (pet) sits one
--- bar-height + gap beyond the player bar when the player bar exists; 0 otherwise,
--- so every anchor formula below is unchanged for the player bar.
local function StackExtraOffset(kind, profile)
    if not kind.stacked then return 0 end
    local playerBarExists = (healthBarFrame ~= nil)
        and (profile.defensives and profile.defensives.showHealthBar)
    return playerBarExists and (BAR_HEIGHT + BAR_SPACING) or 0
end

-- Placement is shared with BuildHealthBar below; defined later, declared here.
local ResizeBarToCount

-- Shared builder for the player and pet health bars. Per-kind differences (toggle
-- key, fill color, stacking offset, low-health pulse, dead overlay, pet-class gate)
-- come from the BAR_KINDS entry; placement is delegated to ResizeBarToCount so the
-- builder and the dynamic resizer cannot drift.
local function BuildHealthBar(addon, kind)
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

    -- Bar visibility is controlled by a single per-kind toggle (kind.showKey)
    -- regardless of whether defensive suggestions are enabled.
    if not (profile.defensives and profile.defensives[kind.showKey]) then return nil end

    if kind.requiresPetClass then
        -- Only create for pet classes
        local _, playerClass = UnitClass("player")
        local SpellDB = LibStub("JustAC-SpellDB", true)
        if not SpellDB then return nil end
        if not SpellDB.ClassHasPetDefaults(playerClass) then return nil end
    end

    local useDefensiveDims = isDetached or (defensivesEnabled or false)

    -- Orientation drives the StatusBar fill direction and bevel direction.
    local barIsHorizontal
    if isDetached then
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        barIsHorizontal = (detachOrientation == "LEFT" or detachOrientation == "RIGHT")
    else
        local orientation = profile.queueOrientation or "LEFT"
        barIsHorizontal = (orientation == "LEFT" or orientation == "RIGHT")
    end

    local frame = CreateFrame("Frame", nil, isDetached and addon.defensiveFrame or addon.mainFrame)

    -- Placement/size come from the shared resizer: span the full defensive cluster
    -- when defensives are on (the renderer resizes to the live count right after),
    -- the offensive queue otherwise (the resizer's <=0 fallback).
    local maxDefIcons = math.min((profile.defensives and profile.defensives.maxIcons) or 4, 7)
    ResizeBarToCount(addon, frame, kind, useDefensiveDims and maxDefIcons or 0)

    -- ── Shared: StatusBar, background, bevel ──────────────────────────────────
    -- Create StatusBar (accepts secret values!)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture(BAR_TEXTURE)
    statusBar:SetOrientation(barIsHorizontal and "HORIZONTAL" or "VERTICAL")
    AddBarGloss(statusBar, barIsHorizontal)

    -- Per-kind fill color (player green / pet yellow)
    statusBar:SetStatusBarColor(kind.color[1], kind.color[2], kind.color[3], kind.color[4])

    -- Neutral dark background (shared across all bars) so missing health reads clearly.
    AddBarBackground(statusBar)

    -- 4-strip tube bevel on OVERLAY so the engine never clobbers them.
    -- Horizontal: symmetric alphas (bright band dead-centre on 6 px bar).
    -- Vertical:   asymmetric (near-queue heavier) - bar is wide enough.
    AddTubeBevel(statusBar, barIsHorizontal)

    if kind.lowHealthPulse then
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
    end

    if kind.deadOverlay then
        -- Dead overlay (red tint, hidden by default)
        local deadOverlay = frame:CreateTexture(nil, "ARTWORK")
        deadOverlay:SetAllPoints(frame)
        deadOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
        deadOverlay:SetVertexColor(0.8, 0.1, 0.1, 0.5)
        deadOverlay:Hide()
        frame.deadOverlay = deadOverlay
    end

    frame.statusBar = statusBar
    frame.useDefensiveDims = useDefensiveDims

    return frame
end

function UIHealthBar.CreateHealthBar(addon)
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame:SetParent(nil)
        healthBarFrame = nil
    end

    local frame = BuildHealthBar(addon, BAR_KINDS.player)
    if not frame then return nil end

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
-- Shared resizer for the player and pet health bars. The public wrappers handle
-- the frame / defensive-dims / count-cache guards; this resizes and repositions
-- `frame` for `visibleCount` visible defensive icons, with the pet's stacking
-- offset folded in (0 for the player, so player anchors are unchanged).
ResizeBarToCount = function(addon, frame, kind, visibleCount)
    local profile = addon.db and addon.db.profile
    if not profile then return end

    local iconSize    = profile.iconSize or 42
    local iconSpacing = profile.iconSpacing or 1

    local extraOffset = StackExtraOffset(kind, profile)

    local isDetached = profile.defensives and profile.defensives.detached
    if isDetached then
        -- Detached: no offensive fallback - just hide when no icons visible.
        if visibleCount <= 0 then
            frame:Hide()
            return
        end
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local isVert = (detachOrientation == "UP" or detachOrientation == "DOWN")
        local defIconScale = profile.defensives.iconScale or 1.0
        local defIconSize  = iconSize * defIconScale

        local queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, visibleCount)

        local grabTabSpacing = GrabTabLength(isVert, iconSpacing)
        frame:ClearAllPoints()
        if detachOrientation == "LEFT" then
            frame:SetSize(queueDimension, BAR_HEIGHT)
            frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "TOPLEFT", offset, BAR_SPACING + extraOffset)
        elseif detachOrientation == "RIGHT" then
            frame:SetSize(queueDimension, BAR_HEIGHT)
            frame:SetPoint("BOTTOMRIGHT", addon.defensiveFrame, "TOPRIGHT", -offset, BAR_SPACING + extraOffset)
        elseif detachOrientation == "UP" then
            frame:SetSize(BAR_HEIGHT, queueDimension)
            frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "BOTTOMRIGHT", BAR_SPACING + extraOffset, grabTabSpacing + offset)
        else -- DOWN
            frame:SetSize(BAR_HEIGHT, queueDimension)
            frame:SetPoint("TOPLEFT", addon.defensiveFrame, "TOPRIGHT", BAR_SPACING + extraOffset, -(grabTabSpacing + offset))
        end
        frame:Show()
        return
    end

    local orientation = profile.queueOrientation or "LEFT"

    -- For RIGHT/UP, icons are shifted within the frame to keep the grab tab at a
    -- predictable position.  Health bars must match that shift to stay aligned.
    local grabTabReserve = GrabTabReserve(orientation, iconSpacing)

    frame:ClearAllPoints()

    if visibleCount <= 0 then
        -- No defensive icons visible → fall back to offensive queue dimensions/position
        -- so the bar stays on screen (mirrors the non-defensive path in BuildHealthBar).
        local firstIconScale = profile.firstIconScale or 1.0
        local maxIcons       = profile.maxIcons or 4
        local firstIconSize  = iconSize * firstIconScale

        local queueDimension, offset = ComputeBarSpan(firstIconSize, iconSize, iconSpacing, maxIcons)

        if orientation == "LEFT" or orientation == "RIGHT" then
            frame:SetSize(queueDimension, BAR_HEIGHT)
        else
            frame:SetSize(BAR_HEIGHT, queueDimension)
        end

        local baseDist = BAR_SPACING + extraOffset
        -- Respect the configured defensive side: SIDE2 users' bars used to jump to
        -- the SIDE1 side whenever the cluster emptied, then jump back.
        local fbPosition = (profile.defensives and profile.defensives.position) or "SIDE1"

        if orientation == "LEFT" then
            if fbPosition == "SIDE1" then
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "TOPLEFT",    offset,     baseDist)
            else
                frame:SetPoint("TOPLEFT",     addon.mainFrame, "BOTTOMLEFT", offset,    -baseDist)
            end
        elseif orientation == "RIGHT" then
            if fbPosition == "SIDE1" then
                frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "TOPRIGHT",  -(offset + grabTabReserve),     baseDist)
            else
                frame:SetPoint("TOPRIGHT",    addon.mainFrame, "BOTTOMRIGHT", -(offset + grabTabReserve),  -baseDist)
            end
        elseif orientation == "DOWN" then
            if fbPosition == "SIDE1" then
                frame:SetPoint("TOPLEFT",     addon.mainFrame, "TOPRIGHT",   baseDist, -offset)
            else
                frame:SetPoint("TOPRIGHT",    addon.mainFrame, "TOPLEFT",   -baseDist, -offset)
            end
        else -- UP
            if fbPosition == "SIDE1" then
                frame:SetPoint("BOTTOMLEFT",  addon.mainFrame, "BOTTOMRIGHT", baseDist, offset + grabTabReserve)
            else
                frame:SetPoint("BOTTOMRIGHT", addon.mainFrame, "BOTTOMLEFT", -baseDist, offset + grabTabReserve)
            end
        end

        frame:Show()
        return
    end

    if not profile.defensives then return end

    local defIconScale = profile.defensives.iconScale or 1.0
    local defIconSize  = iconSize * defIconScale
    local defPosition  = profile.defensives.position or "SIDE1"

    local queueDimension, offset = ComputeBarSpan(defIconSize, defIconSize, iconSpacing, visibleCount)

    -- Resize
    if orientation == "LEFT" or orientation == "RIGHT" then
        frame:SetSize(queueDimension, BAR_HEIGHT)
    else
        frame:SetSize(BAR_HEIGHT, queueDimension)
    end

    -- Reposition to stay aligned above/below the visible cluster (BAR_SPACING gap,
    -- stacked bars one bar further out).
    local barDist = DefensiveBarDist(defIconSize, iconSpacing) + extraOffset

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

    frame:Show()
end

function UIHealthBar.ResizeToCount(addon, visibleCount)
    if not healthBarFrame then return end
    if not healthBarFrame.useDefensiveDims then return end  -- offensive-mode bar: skip

    -- Cache check: skip expensive recalc when count hasn't changed
    if visibleCount == lastVisibleCount then return end
    lastVisibleCount = visibleCount

    ResizeBarToCount(addon, healthBarFrame, BAR_KINDS.player, visibleCount)
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

    local frame = BuildHealthBar(addon, BAR_KINDS.pet)
    if not frame then return nil end

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
        lastPetUpdate = 0  -- force fresh values now (pet just (re)summoned / shown)
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

    ResizeBarToCount(addon, petHealthBarFrame, BAR_KINDS.pet, visibleCount)
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
-- Player Resource Bars. Secret-safe display (UnitPower is secret in combat, but
-- StatusBar:SetValue accepts secrets - the proven health-bar pattern). A PRIMARY
-- bar for the current displayed power, plus an optional SECONDARY bar for a spec's
-- point resource (combo points / runes / chi / holy power / soul shards / arcane
-- charges / essence) as a fullness gauge - the count is secret in combat, but the
-- fill still renders. Both anchor to the outermost health bar, so they stack in
-- EVERY health-bar mode (offensive / defensive-cluster / detached) and follow its
-- resize. UnitPower/UnitPowerMax passthrough; UnitPowerType/PowerBarColor never secret.
--------------------------------------------------------------------------------

local powerBarFrame = nil           -- primary (current displayed power)
local secondaryPowerBarFrame = nil  -- secondary point resource
local lastPowerUpdate = 0
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType

-- Power-type colors, matched to unit-frame-addon norms (combo points gold, holy power
-- pale gold, soul shards purple, chi teal, arcane charges blue, runes grey, essence
-- light blue, etc.). Keyed by numeric power type; built defensively so a missing Enum
-- field is skipped rather than crashing on a nil table key.
local POWER_COLOR = {}
do
    local P = Enum and Enum.PowerType or {}
    local function pc(pt, r, g, b) if pt ~= nil then POWER_COLOR[pt] = {r, g, b} end end
    pc(P.Mana,          0.30, 0.50, 0.85)
    pc(P.Rage,          0.70, 0.13, 0.15)
    pc(P.Focus,         1.00, 0.50, 0.25)
    pc(P.Energy,        1.00, 0.85, 0.10)
    pc(P.RunicPower,    0.35, 0.45, 0.60)
    pc(P.LunarPower,    0.30, 0.52, 0.90)
    pc(P.Maelstrom,     0.00, 0.50, 1.00)
    pc(P.Insanity,      0.40, 0.00, 0.80)
    pc(P.Fury,          0.788, 0.259, 0.992)
    pc(P.Pain,          0.78, 0.05, 0.05)
    pc(P.ComboPoints,   1.00, 0.80, 0.00)
    pc(P.HolyPower,     0.95, 0.90, 0.60)
    pc(P.SoulShards,    0.58, 0.51, 0.79)
    pc(P.ArcaneCharges, 0.10, 0.10, 0.98)
    pc(P.Chi,           0.71, 1.00, 0.92)
    pc(P.Runes,         0.50, 0.50, 0.50)
    pc(P.Essence,       0.40, 0.80, 1.00)
end

-- Class -> its secondary point-resource power type. Shown only when the current
-- spec/form actually has it. Class-keyed with Enum VALUES (a missing Enum field
-- just yields a nil value -> no secondary, never a nil table key).
local SECONDARY = {
    ROGUE       = Enum.PowerType.ComboPoints,
    DRUID       = Enum.PowerType.ComboPoints,
    PALADIN     = Enum.PowerType.HolyPower,
    WARLOCK     = Enum.PowerType.SoulShards,
    MONK        = Enum.PowerType.Chi,
    MAGE        = Enum.PowerType.ArcaneCharges,
    DEATHKNIGHT = Enum.PowerType.Runes,
    EVOKER      = Enum.PowerType.Essence,
}

-- The secondary power type for the player's class, or nil.
local function GetClassSecondary()
    local _, class = UnitClass("player")
    return class and SECONDARY[class] or nil
end
UIHealthBar.GetClassSecondary = GetClassSecondary  -- shared with the nameplate overlay

-- Cached segment count for the secondary = readable UnitPowerMax (0 = resource absent
-- or unknown). Existence/segment-count only changes on a form/spec change (which fires
-- UNIT_DISPLAYPOWER, where the value is readable), so in combat - where max may be
-- secret - we reuse the cached count rather than fail-open and show a secondary bar for
-- a spec that has none (e.g. Balance Druid, Brewmaster Monk). Fail-CLOSED.
-- Returns the segment count for `bar`, or `current` unchanged when max is secret.
-- Shared with the nameplate overlay so the fail-closed rule lives in exactly one place.
local function ResolveSegmentCount(bar, current)
    if not bar then return 0 end
    local maxP = UnitPowerMax("player", bar.powerType)
    local IsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue
    if maxP and not (IsSecret and IsSecret(maxP)) then
        return (maxP > 0) and maxP or 0
    end
    return current
end
UIHealthBar.ResolveSegmentCount = ResolveSegmentCount

local secondarySegments = 0
local function RefreshSecondaryCache()
    secondarySegments = ResolveSegmentCount(secondaryPowerBarFrame, secondarySegments)
end

-- Reposition segment dividers proportionally along the bar (on size change / rebuild).
local function PositionSegments(frame, w, h)
    local segs = frame and frame.segments
    local n = frame and frame.segmentCount or 0
    if not segs or n <= 1 then return end
    local sb = frame.statusBar
    -- Explicit dims for callers whose GetWidth/GetHeight are secret: the nameplate
    -- overlay anchors its bars into the (secret) nameplate, so a live-size read there
    -- returns a secret number that can't be compared. Standard queue passes neither.
    w = w or sb:GetWidth()
    h = h or sb:GetHeight()
    for i = 1, n - 1 do
        local tex = segs[i]
        if tex and tex:IsShown() then
            local frac = i / n
            tex:ClearAllPoints()
            if frame.barIsHorizontal then
                tex:SetSize(1, h > 0 and h or BAR_HEIGHT)
                tex:SetPoint("LEFT", sb, "LEFT", frac * w, 0)
            else
                tex:SetSize(w > 0 and w or BAR_HEIGHT, 1)
                tex:SetPoint("BOTTOM", sb, "BOTTOM", 0, frac * h)
            end
        end
    end
end
UIHealthBar.PositionSegments = PositionSegments  -- shared with the nameplate overlay

-- Draw n-1 dividers so the (passthrough-filled) secondary reads as n discrete segments
-- - combo points / holy power / chi / etc. are point resources, not a continuous pool.
local function RebuildSegments(frame, n, w, h)
    frame.segments = frame.segments or {}
    for i = 1, #frame.segments do frame.segments[i]:Hide() end
    frame.segmentCount = n
    if n <= 1 then return end
    for i = 1, n - 1 do
        local tex = frame.segments[i]
        if not tex then
            tex = frame.statusBar:CreateTexture(nil, "OVERLAY", nil, 1)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            tex:SetVertexColor(0, 0, 0, 1)  -- solid dark divider between segments
            frame.segments[i] = tex
        end
        tex:Show()
    end
    PositionSegments(frame, w, h)
end
UIHealthBar.RebuildSegments = RebuildSegments  -- shared with the nameplate overlay

-- Color a resource bar from POWER_COLOR. powerType nil = the current displayed power
-- (UnitPowerType's numeric index is NeverSecret). Falls back to mana-blue. The empty
-- portion is tinted to a dim wash of the same color (unit-frame convention: the drained
-- part reads as the resource, not neutral grey), which also makes each unfilled segment
-- of the point-resource bar glow faintly like an empty pip.
local MANA_FALLBACK = {0.30, 0.50, 0.85}
local function ApplyResourceColor(statusBar, powerType)
    local pt = powerType
    if pt == nil then pt = UnitPowerType("player") end
    local c = (pt and POWER_COLOR[pt]) or MANA_FALLBACK
    statusBar:SetStatusBarColor(c[1], c[2], c[3], 0.9)
    if statusBar.bg then statusBar.bg:SetVertexColor(c[1], c[2], c[3], 0.22) end
end
UIHealthBar.ApplyResourceColor = ApplyResourceColor  -- shared with the nameplate overlay

-- Anchor a resource bar to anchorBar (inherits its span/position in every mode and
-- follows its resize), or to the offensive-queue position when anchorBar is nil.
local function AnchorResourceBar(frame, mainFrame, profile, anchorBar, flush)
    -- Orientation follows the DETACHED cluster only when there is an anchor bar to
    -- follow (the bar inherits that chain's geometry). The nil-anchorBar fallback
    -- parks at the OFFENSIVE queue, so it must use the queue's own orientation -
    -- mixing detachedOrientation with mainFrame geometry pinned a vertical bar to
    -- a horizontal queue whenever the two axes differed.
    local orientation = profile.queueOrientation or "LEFT"
    if anchorBar and profile.defensives and profile.defensives.detached then
        orientation = profile.defensives.detachedOrientation or "LEFT"
    end
    local barIsHorizontal = (orientation == "LEFT" or orientation == "RIGHT")

    frame:ClearAllPoints()
    if anchorBar then
        -- flush = stack directly against the anchor (secondary reads as one bar with
        -- the primary); otherwise leave the standard gap off the health bar.
        local gap = flush and 0 or BAR_SPACING
        if barIsHorizontal then
            frame:SetHeight(POWER_BAR_HEIGHT)
            frame:SetPoint("BOTTOMLEFT",  anchorBar, "TOPLEFT",  0, gap)
            frame:SetPoint("BOTTOMRIGHT", anchorBar, "TOPRIGHT", 0, gap)
        else
            frame:SetWidth(POWER_BAR_HEIGHT)
            frame:SetPoint("BOTTOMLEFT", anchorBar, "BOTTOMRIGHT", gap, 0)
            frame:SetPoint("TOPLEFT",    anchorBar, "TOPRIGHT",    gap, 0)
        end
        return barIsHorizontal
    end

    local iconSpacing = profile.iconSpacing or 1
    local grabTabReserve = GrabTabReserve(orientation, iconSpacing)
    local queueDimension, offset = ComputeOffensiveSpan(profile)
    if barIsHorizontal then
        frame:SetSize(queueDimension, POWER_BAR_HEIGHT)
    else
        frame:SetSize(POWER_BAR_HEIGHT, queueDimension)
    end
    -- This fallback parks on the SIDE1 side of the queue - the same band attached
    -- SIDE1 defensive icons occupy. Clear their row or the resource bar draws
    -- across the defensive icons whenever health bars are off.
    local depth = UIHealthBar.AttachedDefRowDepth(profile)
    local gap = depth > 0 and (depth + BAR_SPACING) or BAR_SPACING
    if orientation == "LEFT" then
        frame:SetPoint("BOTTOMLEFT",  mainFrame, "TOPLEFT",     offset,                    gap)
    elseif orientation == "RIGHT" then
        frame:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT",   -(offset + grabTabReserve), gap)
    elseif orientation == "DOWN" then
        frame:SetPoint("TOPLEFT",     mainFrame, "TOPRIGHT",    gap,                      -offset)
    else -- UP
        frame:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMRIGHT", gap,                       offset + grabTabReserve)
    end
    return barIsHorizontal
end

-- Build one resource statusBar. powerType nil = current displayed power. Unit-frame
-- styling: flat fill in the power color over a dim same-color wash for the drained part
-- (no tube bevel - too heavy on a 3px bar; the color wash carries the look instead).
local function BuildResourceBar(addon, profile, powerType, anchorBar, flush)
    local frame = CreateFrame("Frame", nil, addon.mainFrame)
    local barIsHorizontal = AnchorResourceBar(frame, addon.mainFrame, profile, anchorBar, flush)

    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture(BAR_TEXTURE)
    statusBar:SetOrientation(barIsHorizontal and "HORIZONTAL" or "VERTICAL")
    AddBarGloss(statusBar, barIsHorizontal)
    AddBarBackground(statusBar)          -- sets statusBar.bg, then tinted to the power color
    ApplyResourceColor(statusBar, powerType)

    -- Flush bar (the secondary): a faint line along the seam so the pair still reads as
    -- two bars despite touching. Anchored to a static edge, so no reposition needed.
    if flush then
        local div = statusBar:CreateTexture(nil, "OVERLAY", nil, 2)
        div:SetTexture("Interface\\Buttons\\WHITE8X8")
        div:SetVertexColor(0, 0, 0, 0.5)
        if barIsHorizontal then
            div:SetHeight(1)
            div:SetPoint("BOTTOMLEFT",  statusBar, "BOTTOMLEFT",  0, 0)
            div:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        else
            div:SetWidth(1)
            div:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 0, 0)
            div:SetPoint("TOPLEFT",    statusBar, "TOPLEFT",    0, 0)
        end
    end

    frame.statusBar = statusBar
    frame.powerType = powerType
    frame.barIsHorizontal = barIsHorizontal
    statusBar:SetScript("OnSizeChanged", function() PositionSegments(frame) end)
    frame:Show()
    return frame
end

--- Refresh the secondary bar for the current spec/form: cache the segment count, then
--- show it (rebuilding its segments) only when the resource exists, else hide. Combo
--- points exist in Cat but not Boomkin, chi for Windwalker only, etc. No recreation.
function UIHealthBar.RefreshSecondaryPowerVisibility(addon)
    if not secondaryPowerBarFrame then return end
    local prev = secondarySegments
    RefreshSecondaryCache()
    if secondarySegments > 0 then
        -- Rebuild only when the count actually changed (form/spec swap, or a talent that
        -- raises the cap - e.g. a rogue trait taking combo points past 5). Keeps this
        -- safe to call from high-frequency max-power events.
        if secondarySegments ~= prev then
            RebuildSegments(secondaryPowerBarFrame, secondarySegments)
        end
        secondaryPowerBarFrame:Show()
    else
        secondaryPowerBarFrame:Hide()
    end
end

-- Outermost currently-SHOWN player/pet health bar the resource bars stack beyond. The
-- IsShown() check (matching the nameplate overlay) means a hidden pet bar - pet class
-- with the pet bar on but no pet out - doesn't leave a reserved gap; the pair re-anchors
-- flush to the player bar and shifts back out when a pet is summoned (see ReanchorPower).
local function OuterHealthBar()
    if petHealthBarFrame and petHealthBarFrame:IsShown() then return petHealthBarFrame end
    return healthBarFrame
end

function UIHealthBar.CreatePowerBar(addon)
    UIHealthBar.DestroyPower()  -- clears primary + secondary

    if not addon or not addon.db or not addon.db.profile then return nil end
    local profile = addon.db.profile
    if not (profile.defensives and profile.defensives.showPowerBar) then return nil end
    if not addon.mainFrame then return nil end

    -- Primary: displayed power, anchored beyond the outermost shown health bar.
    powerBarFrame = BuildResourceBar(addon, profile, nil, OuterHealthBar())

    -- Secondary: created when the class HAS a point resource, then shown/hidden (and
    -- segmented) per spec/form. Stacked one bar-height beyond the primary.
    local secType = GetClassSecondary()
    if secType then
        secondaryPowerBarFrame = BuildResourceBar(addon, profile, secType, powerBarFrame, true)
        UIHealthBar.RefreshSecondaryPowerVisibility(addon)
    end

    UIHealthBar.UpdatePower(addon)
    return powerBarFrame
end

-- Re-anchor the primary to the outermost SHOWN health bar (the secondary follows via its
-- static SetPoint to the primary). Called when pet-bar visibility flips - summon/dismiss -
-- so the pair neither floats over a hidden pet slot nor overlaps a freshly shown one.
function UIHealthBar.ReanchorPower(addon)
    if not powerBarFrame then return end
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end
    AnchorResourceBar(powerBarFrame, addon.mainFrame, profile, OuterHealthBar())
end

local function UpdateOneResourceBar(frame)
    if not frame or not frame:IsVisible() or not frame.statusBar then return end
    local power = UnitPower("player", frame.powerType)
    local maxPower = UnitPowerMax("player", frame.powerType)
    if not power or not maxPower then return end
    -- Both are secret in combat; StatusBar renders them engine-side without us reading.
    frame.statusBar:SetMinMaxValues(0, maxPower)
    frame.statusBar:SetValue(power)
end
UIHealthBar.UpdateOneResourceBar = UpdateOneResourceBar  -- shared with the nameplate overlay

-- Update power values on timer / power events. UnitPower is secret in combat but
-- StatusBar:SetValue accepts it (rendered by the engine).
function UIHealthBar.UpdatePower(addon)
    if not powerBarFrame or not powerBarFrame:IsVisible() then return end
    local now = GetTime()
    if now - lastPowerUpdate < UPDATE_INTERVAL then return end
    lastPowerUpdate = now
    UpdateOneResourceBar(powerBarFrame)
    UpdateOneResourceBar(secondaryPowerBarFrame)
end

--- Power-type changed (form/stance): recolor the primary and re-evaluate whether the
--- secondary is active for the new form, then refresh values.
function UIHealthBar.UpdatePowerColor(addon)
    if powerBarFrame and powerBarFrame.statusBar then
        ApplyResourceColor(powerBarFrame.statusBar, powerBarFrame.powerType)
    end
    UIHealthBar.RefreshSecondaryPowerVisibility(addon)
    lastPowerUpdate = 0  -- force the throttled UpdatePower to apply fresh values now
    UIHealthBar.UpdatePower(addon)
end

function UIHealthBar.HidePower()
    if powerBarFrame then powerBarFrame:Hide() end
    if secondaryPowerBarFrame then secondaryPowerBarFrame:Hide() end
end

--- Counterpart to HidePower (disabled-mode exit). Nothing else Show()s the primary -
--- UpdatePower early-outs while it is hidden - so without this, leaving disabled mode
--- left the segmented secondary floating alone once UNIT_DISPLAYPOWER re-showed it.
function UIHealthBar.ShowPower(addon)
    if not powerBarFrame then return end
    local profile = addon and addon.db and addon.db.profile
    if not (profile and profile.defensives and profile.defensives.showPowerBar) then return end
    powerBarFrame:Show()
    UIHealthBar.ReanchorPower(addon)
    UIHealthBar.RefreshSecondaryPowerVisibility(addon)
    lastPowerUpdate = 0
    UIHealthBar.UpdatePower(addon)
end

function UIHealthBar.UpdatePowerSize(addon)
    if not addon or not addon.db or not addon.db.profile then return end
    UIHealthBar.DestroyPower()
    UIHealthBar.CreatePowerBar(addon)
end

function UIHealthBar.DestroyPower()
    if secondaryPowerBarFrame then
        secondaryPowerBarFrame:Hide()
        secondaryPowerBarFrame:SetParent(nil)
        secondaryPowerBarFrame = nil
    end
    if powerBarFrame then
        powerBarFrame:Hide()
        powerBarFrame:SetParent(nil)
        powerBarFrame = nil
    end
    lastPowerUpdate = 0
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

-- ── Execute-range color cue (target bar) ──────────────────────────────────────
-- When the target's health drops into execute range the bar shifts color as a
-- "finish it" cue. Health is secret in combat, so we can't read a fraction to
-- branch on - instead we map the secret fraction through a non-secret color curve
-- entirely in the engine (Midnight: UnitHealthPercent + C_CurveUtil.CreateColorCurve).
-- The curve domain is the 0-1 health fraction; below EXECUTE_FRACTION -> execute
-- color, at/above -> normal hostile red. Feature-detected + pcall'd; without the
-- API (or on error) the bar keeps its static red. Newer APIs are resolved at CALL
-- time, never captured at load (they aren't populated this early).
-- ponytail: single 20% threshold (the common execute / "very low" cue), not the
-- exact per-spec execute %; make it per-spec if a spec's window feels off.
local EXECUTE_FRACTION = 0.20
local executeColorCurve  -- built lazily once the curve API is present
local function GetExecuteColorCurve()
    if executeColorCurve then return executeColorCurve end
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor) then return nil end
    local c = cu.CreateColorCurve()
    if not c then return nil end
    c:SetType(stepType)
    c:AddPoint(0, CreateColor(1.0, 0.55, 0.0, 0.95))                -- execute: bright orange
    c:AddPoint(EXECUTE_FRACTION, CreateColor(0.55, 0.06, 0.06, 0.9)) -- normal hostile red
    executeColorCurve = c
    return c
end

--- Apply the execute-range color to a target statusBar from its (secret) health
--- fraction, in-engine. No-op (leaves static red) when the API is unavailable.
local function ApplyExecuteColor(statusBar, unit)
    local getPct = UnitHealthPercent ---@diagnostic disable-line: undefined-global
    if not getPct then return end
    local curve = GetExecuteColorCurve()
    if not curve then return end
    local ok, color = pcall(getPct, unit, false, curve)  -- false = raw health, no absorbs
    if ok and color and color.GetRGBA then
        pcall(statusBar.SetStatusBarColor, statusBar, color:GetRGBA())
    end
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
    -- Docked to Blizzard's target frame: that frame carries the same health readout
    -- immediately beside the queue, so our bar would be a second copy of it. The
    -- option is greyed to match while docked. Note this also drops the execute-range
    -- colour cue (ApplyExecuteColor below), which the target frame has no equivalent
    -- for - undock, or re-enable the bar here, to get it back.
    if addon.targetframe_anchored then return nil end
    if not addon.mainFrame then return nil end

    local frame = CreateFrame("Frame", nil, addon.mainFrame)
    local barIsHorizontal = PositionTargetBar(frame, addon.mainFrame, profile)

    -- StatusBar (accepts secrets), shared dark background, red fill.
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints(frame)
    statusBar:SetStatusBarTexture(BAR_TEXTURE)
    statusBar:SetOrientation(barIsHorizontal and "HORIZONTAL" or "VERTICAL")
    AddBarGloss(statusBar, barIsHorizontal)
    statusBar:SetStatusBarColor(0.55, 0.06, 0.06, 0.9)  -- red (hostile target)

    AddBarBackground(statusBar)
    AddTubeBevel(statusBar, barIsHorizontal)

    frame.statusBar = statusBar
    targetHealthBarFrame = frame

    UIHealthBar.UpdateTargetVisibility(addon)
    return frame
end

-- Update target health value (throttled to UPDATE_INTERVAL). Callers reacting to
-- a target switch / visibility change reset lastTargetUpdate = 0 first so the new
-- target's health applies immediately instead of being throttled out by a recent
-- UNIT_HEALTH tick from the old target (same idiom as UpdatePowerColor).
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

    -- Execute-range color cue (engine-side, secret-safe; static red fallback).
    ApplyExecuteColor(statusBar, "target")
end

-- Show/hide based on target existence + hostility.
function UIHealthBar.UpdateTargetVisibility(addon)
    if not targetHealthBarFrame then return end
    if ShouldShowTargetBar() then
        targetHealthBarFrame:Show()
        lastTargetUpdate = 0  -- force fresh values now (target/visibility just changed)
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
