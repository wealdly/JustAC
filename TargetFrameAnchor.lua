-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: TargetFrameAnchor - Anchor main frame to Blizzard's TargetFrame
local TFA = LibStub:NewLibrary("JustAC-TargetFrameAnchor", 1)
if not TFA then return end

-- Hot path cache
local GetScreenWidth = GetScreenWidth
local GetScreenHeight = GetScreenHeight
local InCombatLockdown = InCombatLockdown
local math_max = math.max

-------------------------------------------------------------------------------
-- Screen bounds check
-------------------------------------------------------------------------------

-- Default position, matching the profile defaults in JustAC.lua. framePosition can be
-- absent on a fresh or reset profile, and every restore path below would otherwise index
-- straight through it.
local DEFAULT_POINT, DEFAULT_X, DEFAULT_Y = "CENTER", 0, -150

--- Put the main frame back where the user last left it. Shared by every path that stops
--- docking to the target frame, so they can't drift apart.
local function RestoreSavedPosition(addon, profile)
    local pos = profile.framePosition
    local point = pos and pos.point or DEFAULT_POINT
    addon.targetframe_anchored = false
    addon.mainFrame:ClearAllPoints()
    -- Five-argument form to carry the saved relativePoint, matching how the frame is
    -- anchored at creation - the short form would quietly force relativePoint == point.
    addon.mainFrame:SetPoint(point, UIParent, pos and pos.relativePoint or point,
        pos and pos.x or DEFAULT_X, pos and pos.y or DEFAULT_Y)
end

-- Lightweight bounds check: if the saved position puts the frame entirely
-- off-screen (resolution change, UI scale change, etc.), reset to center.
-- Only touches framePosition in the profile; does NOT fight with target
-- frame anchoring (that runs immediately after).
function TFA.ClampFrameToScreen(addon)
    if not addon.mainFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.framePosition then return end

    local screenW, screenH = GetScreenWidth(), GetScreenHeight()
    if not screenW or screenW == 0 then return end

    -- Measure where the frame actually is rather than reconstructing it from the saved
    -- offset. The saved point is whatever GetPoint() returned after the last drag, which
    -- need not be CENTER - and an offset measured from a corner means something entirely
    -- different from one measured from the middle, so reconstructing it misjudges by up to
    -- half a screen. That cuts both ways: dragging a perfectly visible frame back to the
    -- centre, or leaving a genuinely lost one out of reach. The frame is already positioned
    -- by the time this runs, so just ask it.
    local f = addon.mainFrame
    local left, right, bottom, top = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
    if not left or not bottom then return end   -- not laid out yet: nothing to judge

    -- GetLeft() and friends report in the frame's own coordinate space; GetScreenWidth() is
    -- in UIParent's. Normalise before comparing, or a scaled frame is measured against the
    -- wrong ruler.
    local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, right, bottom, top = left * scale, right * scale, bottom * scale, top * scale

    -- Allow partial overlap (at least 20 px of the frame stays reachable on every edge)
    local margin = 20
    if right < margin or left > screenW - margin
       or top < margin or bottom > screenH - margin then
        -- Off-screen: reset to default
        local pos = profile.framePosition
        -- relativePoint with the rest: leaving the old one behind would have the next
        -- restore anchor CENTER-to-something-else and land nowhere near the centre.
        pos.point, pos.relativePoint, pos.x, pos.y = DEFAULT_POINT, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y
        addon.mainFrame:ClearAllPoints()
        addon.mainFrame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y)
        addon:DebugPrint("Frame was off-screen - reset to center")
    end
end

-------------------------------------------------------------------------------
-- Standard TargetFrame detection
-------------------------------------------------------------------------------

-- Cached result: nil=unchecked, true=standard frame active, false=replaced
local standardTargetFrameStatus = nil

-- Whitelist check: is the genuine Blizzard TargetFrame active?
-- Returns false if a third-party unit-frame addon replaced it.
-- Cached per session - invalidated on PLAYER_ENTERING_WORLD / reload.
function TFA.IsStandardTargetFrame(addon)
    if standardTargetFrameStatus ~= nil then
        return standardTargetFrameStatus
    end

    local tf = TargetFrame
    if not tf or type(tf) ~= "table" then
        standardTargetFrameStatus = false
        return false
    end

    if type(tf.IsForbidden) == "function" and tf:IsForbidden() then
        standardTargetFrameStatus = false
        return false
    end

    -- Core whitelist signal: UnitFrame_Initialize registers UNIT_NAME_UPDATE.
    -- Every replacement addon calls UnregisterAllEvents(), stripping this event.
    if type(tf.IsEventRegistered) ~= "function" or not tf:IsEventRegistered("UNIT_NAME_UPDATE") then
        standardTargetFrameStatus = false
        if addon and addon.DebugPrint then
            addon:DebugPrint("Target frame anchor unavailable: standard TargetFrame not active (events stripped by another addon)")
        end
        return false
    end

    -- Must be positioned (not orphaned by reparenting to nil/hidden ancestor)
    if type(tf.GetPoint) ~= "function" or not tf:GetPoint() then
        standardTargetFrameStatus = false
        if addon and addon.DebugPrint then
            addon:DebugPrint("Target frame anchor unavailable: TargetFrame has no anchor points")
        end
        return false
    end

    standardTargetFrameStatus = true
    return true
end

function TFA.InvalidateCache()
    standardTargetFrameStatus = nil
end

-------------------------------------------------------------------------------
-- Sidebar offset calculation
-------------------------------------------------------------------------------

-- For vertical orientations, defensive icons and health bar extend sideways from
-- the main frame.  When anchored to the target frame, this sidebar can overlap it.
-- Returns the additional offset needed to keep the sidebar clear.
local function GetVerticalSidebarOffset(profile, anchorSide)
    local defProfile = profile.defensives
    if not defProfile or defProfile.enabled == false then return 0 end

    local defPosition = defProfile.position or "SIDE1"
    -- SIDE1 extends RIGHT (vertical), SIDE2 extends LEFT (vertical)
    -- LEFT anchor: conflict if SIDE1 (extends right, toward target frame)
    -- RIGHT anchor: conflict if SIDE2 (extends left, toward target frame)
    local conflicts = (anchorSide == "LEFT" and defPosition == "SIDE1")
                   or (anchorSide == "RIGHT" and defPosition == "SIDE2")
    if not conflicts then return 0 end

    local iconSize     = profile.iconSize or 42
    local defIconScale = defProfile.iconScale or 1.0
    local defIconSize  = iconSize * defIconScale
    local iconSpacing  = profile.iconSpacing or 1
    -- Imported, not re-typed: these must track the bars this reserves space for.
    local UIHealthBar  = LibStub("JustAC-UIHealthBar", true)
    local BAR_SPACING  = (UIHealthBar and UIHealthBar.BAR_SPACING) or 3
    local BAR_HEIGHT   = (UIHealthBar and UIHealthBar.BAR_HEIGHT) or 6
    local effectiveSpacing = math_max(iconSpacing, BAR_SPACING)

    -- Defensive icon column extends: effectiveSpacing + one icon width
    local width = effectiveSpacing + defIconSize
    -- Health bar sits beyond the defensive cluster
    if defProfile.showHealthBar then
        width = width + BAR_SPACING + BAR_HEIGHT
    end
    return width
end

-------------------------------------------------------------------------------
-- Main anchor logic
-------------------------------------------------------------------------------

function TFA.UpdateTargetFrameAnchor(addon)
    if not addon.mainFrame then return end
    -- Guard against taint: TargetFrame is secure; SetPoint against it in combat
    -- can spread taint to the action bar system causing "action blocked" errors
    if InCombatLockdown() then return end
    local profile = addon:GetProfile()
    if not profile then return end

    local anchor = profile.targetFrameAnchor
    if not anchor or anchor == "DISABLED" then
        -- Restore to saved position if we were previously anchored
        if addon.targetframe_anchored then
            RestoreSavedPosition(addon, profile)
        end
        return
    end

    -- Whitelist: only anchor to the genuine Blizzard TargetFrame
    if not TFA.IsStandardTargetFrame(addon) then
        if addon.targetframe_anchored then
            RestoreSavedPosition(addon, profile)
        end
        return
    end

    -- Guard: respect Edit Mode "Buffs on Top" setting.
    -- TOP anchor conflicts when buffs are above the target frame; BOTTOM conflicts when below.
    local buffsOnTop = TargetFrame.buffsOnTop
    if (buffsOnTop == true and anchor == "TOP") or (buffsOnTop == false and anchor == "BOTTOM") then
        if addon.targetframe_anchored then
            RestoreSavedPosition(addon, profile)
        end
        return
    end

    local orientation = profile.queueOrientation or "LEFT"
    local isVertical  = (orientation == "UP" or orientation == "DOWN")

    addon.targetframe_anchored = true
    addon.mainFrame:ClearAllPoints()
    if anchor == "TOP" then
        addon.mainFrame:SetPoint("BOTTOM", TargetFrame, "TOP", 0, 2)
    elseif anchor == "BOTTOM" then
        addon.mainFrame:SetPoint("TOP", TargetFrame, "BOTTOM", 0, -2)
    elseif anchor == "LEFT" then
        local gap = 2
        if isVertical then gap = gap + GetVerticalSidebarOffset(profile, "LEFT") end
        addon.mainFrame:SetPoint("RIGHT", TargetFrame, "LEFT", -gap, 0)
    elseif anchor == "RIGHT" then
        local gap = 2
        if isVertical then gap = gap + GetVerticalSidebarOffset(profile, "RIGHT") end
        addon.mainFrame:SetPoint("LEFT", TargetFrame, "RIGHT", gap, 0)
    end
end
