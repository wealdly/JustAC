-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: TargetFrameAnchor - Anchor main frame to Blizzard's TargetFrame
local TFA = LibStub:NewLibrary("JustAC-TargetFrameAnchor", 1)
if not TFA then return end

-- Hot path cached globals
local GetScreenWidth = GetScreenWidth
local GetScreenHeight = GetScreenHeight
local InCombatLockdown = InCombatLockdown
local math_max = math.max

-------------------------------------------------------------------------------
-- Screen bounds check
-------------------------------------------------------------------------------

-- Lightweight bounds check: if the saved position puts the frame entirely
-- off-screen (resolution change, UI scale change, etc.), reset to center.
-- Only touches framePosition in the profile; does NOT fight with target
-- frame anchoring (that runs immediately after).
function TFA.ClampFrameToScreen(addon)
    if not addon.mainFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.framePosition then return end

    local scale = addon.mainFrame:GetEffectiveScale()
    if not scale or scale <= 0 then return end

    local screenW, screenH = GetScreenWidth(), GetScreenHeight()
    if not screenW or screenW == 0 then return end

    -- Convert saved offset to approximate screen position
    -- (most anchor points use UIParent center as reference)
    local pos = profile.framePosition
    local x, y = pos.x or 0, pos.y or 0
    local fw = (addon.mainFrame:GetWidth() or 0) * 0.5
    local fh = (addon.mainFrame:GetHeight() or 0) * 0.5
    local halfW, halfH = screenW * 0.5, screenH * 0.5

    -- Rough center-of-frame in screen coords (works for CENTER-based points)
    local cx, cy = halfW + x, halfH + y

    -- Allow partial overlap (at least 20 px visible on any edge)
    local margin = 20
    if cx + fw < margin or cx - fw > screenW - margin
       or cy + fh < margin or cy - fh > screenH - margin then
        -- Off-screen: reset to default
        pos.point = "CENTER"
        pos.x = 0
        pos.y = -150
        addon.mainFrame:ClearAllPoints()
        addon.mainFrame:SetPoint("CENTER", 0, -150)
        addon:DebugPrint("Frame was off-screen — reset to center")
    end
end

-------------------------------------------------------------------------------
-- Standard TargetFrame detection
-------------------------------------------------------------------------------

-- Cached result: nil=unchecked, true=standard frame active, false=replaced
local standardTargetFrameStatus = nil

-- Whitelist check: is the genuine Blizzard TargetFrame active?
-- Returns false if a unit-frame addon (ElvUI, SUF, oUF, Pitbull, etc.) replaced it.
-- Cached per session — invalidated on PLAYER_ENTERING_WORLD / reload.
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
    local BAR_SPACING  = 3  -- matches UIHealthBar.BAR_SPACING
    local BAR_HEIGHT   = 6  -- matches UIHealthBar.BAR_HEIGHT
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
            addon.targetframe_anchored = false
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
        end
        return
    end

    -- Whitelist: only anchor to the genuine Blizzard TargetFrame
    if not TFA.IsStandardTargetFrame(addon) then
        if addon.targetframe_anchored then
            addon.targetframe_anchored = false
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
        end
        return
    end

    -- Guard: respect Edit Mode "Buffs on Top" setting.
    -- TOP anchor conflicts when buffs are above the target frame; BOTTOM conflicts when below.
    local buffsOnTop = TargetFrame.buffsOnTop
    if (buffsOnTop == true and anchor == "TOP") or (buffsOnTop == false and anchor == "BOTTOM") then
        if addon.targetframe_anchored then
            addon.targetframe_anchored = false
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
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
