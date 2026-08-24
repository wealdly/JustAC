-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: UI Frame Factory Module - Creates and manages all UI frames and buttons
local UIFrameFactory = LibStub:NewLibrary("JustAC-UIFrameFactory", 25)
if not UIFrameFactory then return end

local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local UIHealthBar = LibStub("JustAC-UIHealthBar", true)

-- Hot path cache
local wipe = wipe
local math_max = math.max
local math_floor = math.floor

-- Hotkey text sizing/placement, applied wherever this file builds a hotkey FontString.
local HOTKEY_FONT_SCALE = 0.4
local HOTKEY_MIN_FONT_SIZE = 8
local HOTKEY_OFFSET_FIRST = -3
local HOTKEY_OFFSET_QUEUE = -2
-- Grab-tab thickness along the queue axis. Imported so the bar math in UIHealthBar,
-- which reserves space for this tab, cannot disagree with the tab we actually draw.
local GRAB_TAB_LENGTH = (UIHealthBar and UIHealthBar.GRAB_TAB_LENGTH) or 12
-- Per-ability cue colours now live with the renderer that paints them (CUE_MOVECAST /
-- CUE_OFFGCD in UIRenderer): they are applied per render to the shared cue dot's halves
-- rather than baked in at construction, since which colour a half takes depends on how
-- many cues are active.

--- Where a sub-icon attached to the interrupt slot should sit: the interrupt's cast aura and
--- the soothe cue's cleansed-aura clone BOTH hang off that slot and must agree, or one of them
--- lands on top of the maintenance button. Returning the anchor from one place is the point -
--- they were duplicated and immediately drifted.
--- The aura always extends AWAY from the queue. The tank maintenance slot (defensive
--- "position 0") occupies the first row out on the defensive cluster's side, so when a tank
--- has it the aura clears that row and sits one slot further out again. Non-tanks, and
--- detached defensives (own frame, cannot collide), keep the original tight spacing.
--- @return string point, string relativePoint, number yOffset
function UIFrameFactory.GetInterruptAuraAnchor(profile, orientation, iconSize)
    local shift = 0
    -- Static reservation: no combat gate (this anchor is set once at creation), but a slot the
    -- user turned off can never appear, so reserving its row would leave dead space.
    -- The slot serves two independent purposes, so reserve its row for EITHER. The CC-escape
    -- use is not tank-gated: any spec can be stunned, so it does not require a maintenance entry.
    local hasMaint = ((not profile or profile.showMaintenanceSlot ~= false)
            and SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive() ~= nil)
        or (profile and profile.showCCBreak) or false
    local def = profile and profile.defensives
    if hasMaint and not (def and def.detached) then
        -- The clash only exists when the defensive cluster sits on the side the aura extends
        -- toward: the aura goes DOWN for an upward queue, UP for every other orientation.
        local auraSide = (orientation == "UP") and "SIDE2" or "SIDE1"
        if (def and def.position or "SIDE1") == auraSide then
            shift = (iconSize or 0) + ((profile and profile.iconSpacing) or 4)
        end
    end
    if orientation == "UP" then
        -- Queue grows upward, interrupt is below → aura goes further below.
        return "TOP", "BOTTOM", -2 - shift
    end
    -- LEFT, RIGHT, DOWN → aura goes above the interrupt, away from the queue.
    return "BOTTOM", "TOP", 2 + shift
end

--- Manual drag = undock. Shared by the grab-tab drag and the Alt-drag (click-through
--- mode) icon drag: the Alt path used to move a docked panel WITHOUT undocking, so
--- nothing was saved, the next target change snapped it back, and the docked flag
--- kept lying to the save/clamp guards.
function UIFrameFactory.UndockAfterManualDrag(addon)
    local currentProfile = addon:GetProfile()
    if currentProfile and currentProfile.targetFrameAnchor and currentProfile.targetFrameAnchor ~= "DISABLED" then
        currentProfile.targetFrameAnchor = "DISABLED"
        addon.targetframe_anchored = false
        if addon.DebugPrint then addon:DebugPrint("Target frame anchor auto-disabled (manual drag)") end
        -- Undocking re-enables the target health bar (it's suppressed while docked,
        -- where the target frame shows the same readout). Nothing else on this path
        -- rebuilds it, and UpdateTargetVisibility no-ops while the frame is nil, so
        -- without this the bar stays missing until a reload or zone change.
        local UIHealthBarLib = LibStub("JustAC-UIHealthBar", true)
        if UIHealthBarLib and UIHealthBarLib.UpdateTargetSize then
            UIHealthBarLib.UpdateTargetSize(addon)
        end
    end
end

-- Export constants for UIRenderer and UINameplateOverlay
-- Per-frame refresh throttles for CD-swipe widgets and usability tint. Centralized
-- here so a single tune applies equally to every queue (standard, overlay, defensive)
-- instead of drifting between per-file copies.
UIFrameFactory.COOLDOWN_UPDATE_INTERVAL  = 0.08  -- ~12.5Hz: CD swipe / charge widget refresh
UIFrameFactory.USABILITY_UPDATE_INTERVAL = 0.08  -- ~12.5Hz: usability/resource tint refresh

-- Anchor presets for user-configurable text positions
-- Each preset: {ox=xOffset, oy=yOffset, jh=justifyH}
local HOTKEY_ANCHOR_PRESETS = {
    TOPRIGHT    = {ox = -2, oy = -2, jh = "RIGHT"},
    TOPLEFT     = {ox =  2, oy = -2, jh = "LEFT"},
    TOP         = {ox =  0, oy = -2, jh = "CENTER"},
    CENTER      = {ox =  0, oy =  0, jh = "CENTER"},
    BOTTOMRIGHT = {ox = -2, oy =  2, jh = "RIGHT"},
    BOTTOMLEFT  = {ox =  2, oy =  2, jh = "LEFT"},
}
local CHARGE_ANCHOR_PRESETS = {
    BOTTOMRIGHT = {ox = -4, oy = 4, jh = "RIGHT"},
    BOTTOMLEFT  = {ox =  4, oy = 4, jh = "LEFT"},
    BOTTOM      = {ox =  0, oy = 4, jh = "CENTER"},
}

-- Apply text overlay settings to a button.
-- overlaysBlock: the textOverlays sub-table (e.g. profile.textOverlays or
-- a merged block from MergeOverlayTextOverlays). Callers extract the correct block.
-- Handles font size (scale × base), color, and anchor for hotkey, cooldown, and charge text.
function UIFrameFactory.ApplyTextOverlaySettings(button, size, overlaysBlock)
    local overlays = overlaysBlock

    -- Hotkey text
    if button.hotkeyText then
        local cfg    = overlays and overlays.hotkey
        local scale  = (cfg and cfg.fontScale) or 1.0
        local fontSize = math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE * scale))
        button.hotkeyText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        local c = cfg and cfg.color
        button.hotkeyText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1)
        -- This repaint clobbers the out-of-range red; the range updater early-returns while
        -- its cached state matches, so force it to repaint on the next pass.
        button.lastOutOfRange = nil
        local anchor = (cfg and cfg.anchor) or "TOPRIGHT"
        local preset = HOTKEY_ANCHOR_PRESETS[anchor] or HOTKEY_ANCHOR_PRESETS.TOPRIGHT
        button.hotkeyText:ClearAllPoints()
        -- Anchor to hotkeyFrame (direct parent of hotkeyText) for reliable FontString positioning
        button.hotkeyText:SetPoint(anchor, button.hotkeyFrame, anchor, preset.ox, preset.oy)
        button.hotkeyText:SetJustifyH(preset.jh)
    end

    -- Cooldown countdown text
    if button.cooldownText then
        local cfg    = overlays and overlays.cooldown
        local scale  = (cfg and cfg.fontScale) or 1.0
        local font, _, flags = button.cooldownText:GetFont()
        if font then
            button.cooldownText:SetFont(font, math_floor(size * 0.25 * scale), flags)
        end
        local c = cfg and cfg.color
        button.cooldownText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 0.5)
    end

    -- Charge count text
    if button.chargeText then
        local cfg    = overlays and overlays.charges
        local scale  = (cfg and cfg.fontScale) or 1.0
        local fontSize = math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE * 0.65 * scale))
        button.chargeText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        local c = cfg and cfg.color
        button.chargeText:SetTextColor((c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1)
        local anchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
        local preset = CHARGE_ANCHOR_PRESETS[anchor] or CHARGE_ANCHOR_PRESETS.BOTTOMRIGHT
        button.chargeText:ClearAllPoints()
        -- Anchor to hotkeyFrame (direct parent of chargeText) for reliable FontString positioning
        button.chargeText:SetPoint(anchor, button.hotkeyFrame, anchor, preset.ox, preset.oy)
        button.chargeText:SetJustifyH(preset.jh)
    end

    -- The maintenance slot's engine-drawn stack count is a SEPARATE font string (it has to
    -- live inside the aura container's own button), so it does not inherit the styling just
    -- applied above. Push it across from here, the one place these settings are resolved, so
    -- both maintenance surfaces are covered without either calling site knowing about it.
    -- Resolved lazily: that module loads after this one.
    if button._maintAura then
        local UIMaintenanceAura = LibStub("JustAC-UIMaintenanceAura", true)
        if UIMaintenanceAura then UIMaintenanceAura.Restyle(button) end
    end
end

--- Apply text overlay settings to each icon in a list.
--- Nil entries are skipped.
function UIFrameFactory.ApplyTextOverlaySettingsToIcons(iconList, size, overlaysBlock)
    if not iconList then return end
    for _, icon in ipairs(iconList) do
        if icon then
            UIFrameFactory.ApplyTextOverlaySettings(icon, size, overlaysBlock)
        end
    end
end

--- Build a merged textOverlays block for the nameplate overlay.
--- show/color/anchor are central (profile.textOverlays); only fontScale is
--- per-surface (nameplateOverlay.textOverlays, which declares nothing else -
--- NormalizeSavedData strips any other field on load).
function UIFrameFactory.MergeOverlayTextOverlays(profile)
    if not profile then return nil end
    local central = profile.textOverlays
    if not central then return nil end
    local npoOv = profile.nameplateOverlay and profile.nameplateOverlay.textOverlays
    -- Build a shallow merged table for each sub-key
    local merged = {}
    for _, key in ipairs({"hotkey", "cooldown", "charges"}) do
        local c = central[key]
        local n = npoOv and npoOv[key]
        if c then
            merged[key] = {
                show      = c.show,
                fontScale = (n and n.fontScale) or 1.0,
                color     = c.color,
                anchor    = c.anchor,
            }
        end
    end
    return merged
end

-- Panel interaction helpers.
-- panelInteraction always resolves: it has a profile default, and the legacy panelLocked
-- bool it replaced is migrated into it on load, so no fallback arm is reachable.
--- Right-click on any of our draggable surfaces opens the options. Four click
--- handlers wanted the same two-line fallback; one owner means a future change to
--- how options open cannot land on three of them and miss the fourth.
local function OpenOptions(addon)
    if addon.OpenOptionsPanel then
        addon:OpenOptionsPanel()
    else
        Settings.OpenToCategory("JustAssistedCombat")
    end
end

local function IsPanelLocked(profile)
    if not profile then return false end
    return (profile.panelInteraction or "unlocked") ~= "unlocked"
end

local function TogglePanelLock(profile)
    local mode = profile.panelInteraction or "unlocked"
    if mode == "unlocked" then
        profile.panelInteraction = "locked"
    else
        profile.panelInteraction = "unlocked"
    end
    return profile.panelInteraction ~= "unlocked"
end
UIFrameFactory.TogglePanelLock = TogglePanelLock   -- shared with the minimap button

-- Shared hotkey tooltip body for icon OnEnter handlers (queue, defensive, interrupt).
-- Respects tooltipMode; shows spell/item tooltip plus hotkey and right-click hints.
-- showBlacklistHint adds the queue-only Shift+Right-click line.
local function ShowIconHotkeyTooltip(addon, icon, showBlacklistHint)
    local profile = addon:GetProfile()
    local tooltipMode = profile and profile.tooltipMode or "always"

    local inCombat = UnitAffectingCombat("player")
    local showTooltip = tooltipMode == "always" or (tooltipMode == "outOfCombat" and not inCombat)
    if not showTooltip then return end

    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")

    if icon.isItem and icon.itemID then
        GameTooltip:SetItemByID(icon.itemID)
    elseif icon.spellID then
        GameTooltip:SetSpellByID(icon.spellID)
    end

    -- Maintenance slot: name the BUFF this cast keeps up. The swipe and stack count describe
    -- the aura, not the cast, so without this the tooltip contradicts the icon - most starkly
    -- on Blood, where the button is a damage ability and the slot is about Bone Shield.
    -- Only set when the two ids differ (Ironfur casts and buffs under one id).
    -- Name only: spell descriptions embed scaling values, which are the secret-value class.
    if icon.maintenanceAuraID then
        local auraName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(icon.maintenanceAuraID)
        if auraName then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff8cc7ffMaintains: " .. auraName .. "|r")
        end
    end

    if icon.spellID or icon.isItem then
        local hotkey
        local isOverride
        if icon.isItem and icon.itemID then
            hotkey = ActionBarScanner and ActionBarScanner.GetItemHotkey and ActionBarScanner.GetItemHotkey(icon.itemID, icon.itemCastSpellID) or ""
            isOverride = addon:GetHotkeyOverride(-icon.itemID) ~= nil
        else
            hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(icon.spellID) or ""
            isOverride = addon:GetHotkeyOverride(icon.spellID) ~= nil
        end

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
            if showBlacklistHint then
                GameTooltip:AddLine("|cffff6666Shift+Right-click: Remove from queue (blacklist)|r")
            end
        end
    end

    GameTooltip:Show()
end

-- Local state
local spellIcons = {}
local defensiveIcons = {}  -- Array of defensive icon buttons (1-3)
local stdInterruptIcon = nil  -- Standard queue interrupt icon ("position 0")

--- Restyle the maintenance slot's swipe to read "your protection is running out" rather than
--- the default "on cooldown, wait" - a dark mask that clears means unavailable, the reverse of
--- what a depleting buff means. Blue veil that shrinks, bright leading edge, normal direction
--- (reversed would read as charging toward ready), engine countdown numbers on.
--- Must be re-applied after every Masque re-skin: Masque owns the Cooldown element and resets
--- these to its skin's defaults, which silently reverted the slot to a plain black swipe.
function UIFrameFactory.ApplyMaintenanceSwipeStyle(icon)
    local cd = icon and icon.cooldown
    if not cd then return end
    if cd.SetSwipeColor then cd:SetSwipeColor(0.15, 0.45, 0.95, 0.55) end
    if cd.SetDrawEdge then cd:SetDrawEdge(true) end
    if cd.SetEdgeColor then cd:SetEdgeColor(0.75, 0.92, 1.00, 1) end
    if cd.SetReverse then cd:SetReverse(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
end

--------------------------------------------------------------------------------
-- Secret health-threshold alpha gate
--
-- The same engine trick the enrage cue uses, generalised: a SECRET number is handed to the
-- engine as an INDEX into a curve we authored, and the resulting colour is sunk straight into
-- a display property. We never read the number, never compare it, never branch on it - the
-- engine decides what is visible.
-- For the enrage cue the index is a dispel type; here it is the unit's health fraction.
-- UnitHealthPercent is the only other API that takes a curve and a unit (plus UnitPowerPercent
-- for power), so this covers every health-gated cue we can ever build.
--
-- Consequences worth knowing before using this:
--   * DISPLAY ONLY. The result is secret, so it can never feed ordering, ranking or any `if`.
--     A cue built on this can light a frame; it cannot change what the queue recommends.
--   * The frame must be SHOWN at alpha 0, never hidden - a hidden frame draws nothing whatever
--     its alpha, which is exactly the bug that silently killed the enrage cue.
-- Resolved at CALL time, never captured at load: these APIs are not populated that early.
--------------------------------------------------------------------------------
-- Shared so the target health bar's colour shift and the queue icon's cue agree about when
-- "execute range" starts. Two copies of this number would drift and read as a bug.
-- ponytail: single 20% threshold, not the exact per-spec window; make it per-spec if one feels
-- off (Kill Shot and Hammer of Wrath are 20%, Touch of Death differs).
UIFrameFactory.EXECUTE_FRACTION = 0.20

-- Curves are cached by the IDENTITY of the points table, so callers must pass a module-level
-- constant rather than building one per call. Points are { fraction, alpha } pairs in ascending
-- fraction order; Step holds each until the next, so a point means "from here up, this alpha".
local healthCurves = {}       -- [pointsTable] = curve, or false once known unavailable
local belowPoints  = {}       -- [fraction] = the 2-point table for SetAlphaFromHealthBelow

local function GetHealthCurve(points)
    local cached = healthCurves[points]
    if cached ~= nil then return cached or nil end
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor) then
        healthCurves[points] = false
        return nil
    end
    local c = cu.CreateColorCurve()
    if not c then healthCurves[points] = false return nil end
    c:SetType(stepType)
    -- Domain is the 0-1 health fraction (matches the target bar's execute curve, validated
    -- in game). Colour is always white; only the ALPHA channel carries the signal.
    for i = 1, #points do
        c:AddPoint(points[i][1], CreateColor(1, 1, 1, points[i][2]))
    end
    healthCurves[points] = c
    return c
end

--- Drive `frame`'s alpha from `unit`'s health through a multi-band curve.
--- Graded rather than on/off: intermediate alphas let ONE evaluation express several
--- thresholds at once - e.g. bright below 35%, dim between 35% and 90%, invisible above -
--- so urgency is communicated without any comparison we are not allowed to make.
--- @param points table module-level constant, { {fraction, alpha}, ... } ascending
--- @param predicted boolean|nil true counts incoming heals (a healer already topping you up
---        stops the cue before it fires); false reads raw health.
function UIFrameFactory.SetAlphaFromHealthCurve(frame, unit, points, predicted)
    if not (frame and frame.SetAlpha and unit and points) then return false end
    local getPct = UnitHealthPercent ---@diagnostic disable-line: undefined-global
    if not getPct then return false end
    local curve = GetHealthCurve(points)
    if not curve then return false end
    local ok, color = pcall(getPct, unit, predicted and true or false, curve)
    if not (ok and color and color.a ~= nil) then return false end
    pcall(frame.SetAlpha, frame, color.a)
    return true
end

--- Set `frame`'s alpha from `unit`'s health: opaque below `fraction`, invisible at or above.
--- The simple on/off case of SetAlphaFromHealthCurve.
--- Returns false when the technique is unavailable, so callers can fall back rather than
--- leaving a frame stuck at whatever alpha it last had.
--- @param fraction number 0-1 health fraction threshold (0.2 = "below 20%")
function UIFrameFactory.SetAlphaFromHealthBelow(frame, unit, fraction)
    local points = belowPoints[fraction]
    if not points then
        points = { {0, 1}, {fraction, 0} }
        belowPoints[fraction] = points   -- stable identity, so the curve caches
    end
    -- Raw health, not predicted: an incoming heal must not flicker an execute cue off.
    return UIFrameFactory.SetAlphaFromHealthCurve(frame, unit, points, false)
end

-- Masque support (single group for all standard queue icons)
local Masque = LibStub("Masque", true)
local GetMasqueGroup

if Masque then
    local MasqueGroup = Masque:Group("JustAssistedCombat", "Standard Queue")

    GetMasqueGroup = function() return MasqueGroup end

    -- Re-apply text overlay settings after Masque re-skins (user changes skin).
    -- Masque's Skin_Text repositions HotKey; our ApplyTextOverlaySettings must
    -- override afterwards to restore user-configured anchors.
    local function OnStandardQueueSkinChanged(Group, Option)
        if Option ~= "SkinID" and Option ~= "Reset" and Option ~= "Disabled" then return end
        local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        if not addon or not addon.db then return end
        local profile = addon:GetProfile()
        if not profile then return end
        local overlays = profile.textOverlays
        local firstIconScale = profile.firstIconScale or 1.0
        for i, icon in ipairs(spellIcons) do
            if icon then
                local sz = (i == 1) and (profile.iconSize * firstIconScale) or profile.iconSize
                UIFrameFactory.ApplyTextOverlaySettings(icon, sz, overlays)
            end
        end
        if stdInterruptIcon then
            UIFrameFactory.ApplyTextOverlaySettings(stdInterruptIcon, profile.iconSize * firstIconScale, overlays)
        end
        local defScale = profile.defensives and profile.defensives.iconScale or 1.0
        local defSz = profile.iconSize * defScale
        UIFrameFactory.ApplyTextOverlaySettingsToIcons(defensiveIcons, defSz, overlays)
        -- The maintenance slot is not in defensiveIcons, so it needs both passes by name:
        -- its text anchors like its siblings, and its swipe restyle is Masque's to clobber.
        if addon.maintenanceIcon then
            UIFrameFactory.ApplyTextOverlaySettings(addon.maintenanceIcon, defSz, overlays)
            UIFrameFactory.ApplyMaintenanceSwipeStyle(addon.maintenanceIcon)
        end
    end

    MasqueGroup:RegisterCallback(OnStandardQueueSkinChanged)
else
    GetMasqueGroup = function() return nil end
end

-- Hand a finished button to the skinning group, then re-apply our text overlay
-- settings. Order matters: ApplyTextOverlaySettings must run AFTER AddButton so our
-- anchor overrides whatever position the skin gives the HotKey element.
local function RegisterMasque(button, actualIconSize, profile)
    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            ChargeCooldown = button.chargeCooldown,
            HotKey = button.hotkeyText,
            Count = button.chargeText,
            Normal = button.NormalTexture,
            Pushed = button.PushedTexture,
            Highlight = button.HighlightTexture,
        })
    end
    UIFrameFactory.ApplyTextOverlaySettings(button, actualIconSize, profile and profile.textOverlays)
end

-- Helper: Build the shared icon skeleton used by both DPS and Defensive buttons.
-- Returns a button with all visual layers, cooldown frames, hotkey text and fade
-- animations pre-built.  Positioning is left to the caller.
--
-- Parameters:
--   parent       - parent Frame
--   size         - icon size in pixels
--   isClickable  - add Pushed/Highlight textures (false for nameplate icons)
--   isFirstIcon  - use HOTKEY_OFFSET_FIRST instead of HOTKEY_OFFSET_QUEUE
local function CreateRoundedActionIconMask(parent, size, ...)
    local maskSize = math_floor((size * 1.5) + 0.5)
    local iconMask = parent:CreateMaskTexture(nil, "ARTWORK")
    iconMask:SetPoint("CENTER", parent, "CENTER", 0, 0)
    iconMask:SetSize(maskSize, maskSize)
    iconMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)

    for i = 1, select("#", ...) do
        local texture = select(i, ...)
        if texture then texture:AddMaskTexture(iconMask) end
    end

    return iconMask
end

local function ApplyActionButtonBorderGeometry(texture, parent, size)
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    texture:SetSize(size + 1, size)
end

UIFrameFactory.CreateRoundedActionIconMask = CreateRoundedActionIconMask
UIFrameFactory.ApplyActionButtonBorderGeometry = ApplyActionButtonBorderGeometry

--- A small icon pinned to a parent slot, showing an aura related to that slot (what the enemy
--- is casting, what is about to be soothed). Shared so every surface anchors it the same way.
--- The caller owns the parts that legitimately differ: frame level, strata, mouse, initial
--- visibility. Nothing here hides it - a caller that needs it hidden hides it itself.
--- @return table frame - with .iconTexture, .IconMask and .Border
function UIFrameFactory.CreateAuraSubIcon(parent, iconSize, profile, orientation)
    local auraSize = math_floor(iconSize * 0.7)
    local aura = CreateFrame("Frame", nil, parent)
    aura:SetSize(auraSize, auraSize)
    aura:SetFrameLevel(parent:GetFrameLevel() + 2)

    local pt, relPt, y = UIFrameFactory.GetInterruptAuraAnchor(profile, orientation, iconSize)
    aura:SetPoint(pt, parent, relPt, 0, y)

    local icon = aura:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(aura)
    aura.iconTexture = icon
    aura.IconMask = CreateRoundedActionIconMask(aura, auraSize, icon)

    local border = aura:CreateTexture(nil, "OVERLAY")
    ApplyActionButtonBorderGeometry(border, aura, auraSize)
    border:SetAtlas("UI-HUD-ActionBar-IconFrame")
    aura.Border = border

    return aura
end

local function CreateBaseIcon(parent, size, isClickable, isFirstIcon)
    local button = CreateFrame("Button", nil, parent)
    if not button then return nil end

    button:SetSize(size, size)
    button.cachedIconSize = size  -- NeverSecret fallback for UIAnimations (GetWidth() is secret on nameplate-parented frames)

    if not isClickable then
        button:EnableMouse(false)
    end

    -- Slot background (Blizzard style depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    iconTexture:Hide()
    button.iconTexture = iconTexture

    -- Match Blizzard action-button mask geometry. The mask needs to be larger than the
    -- visible button; a smaller edge-anchored mask leaves the slot background visible at
    -- the bottom when Masque is not skinning the icon.
    local iconMask = CreateRoundedActionIconMask(button, size, slotBackground, iconTexture)
    button.IconMask = iconMask

    -- Flash overlay (slightly outside the border, hidden until proc triggers it)
    local flashFrame = CreateFrame("Frame", nil, button)
    flashFrame:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    flashFrame:SetSize(size + 2, size + 2)
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 6)

    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetVertexColor(1.5, 1.2, 0.3, 1.0)
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()

    button.Flash = flashTexture
    button.FlashFrame = flashFrame

    -- Cooldown container: SetClipsChildren clips swipe to icon bounds
    -- Glow effects are parented to button directly so they're NOT clipped
    local cooldownContainer = CreateFrame("Frame", nil, button)
    cooldownContainer:SetAllPoints(button)
    cooldownContainer:SetClipsChildren(true)
    button.cooldownContainer = cooldownContainer

    -- Main cooldown (spell CD or GCD, whichever is longer)
    local cooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    -- CooldownFrameTemplate sets setAllPoints="true" which anchors all 4 corners to the parent.
    -- ClearAllPoints removes those before we inset; without this, TOPRIGHT/BOTTOMLEFT from the
    -- template remain anchored to cooldownContainer (full button size) and override our inset.
    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      4, -4)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4,  4)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)   -- BlingTexture (star4 sparkle) renders outside frame bounds
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)

    -- Cooldown countdown text - stored for per-frame show/hide and ApplyTextOverlaySettings
    local cooldownText = cooldown:GetRegions()
    button.cooldownText = (cooldownText and cooldownText.SetFont) and cooldownText or nil

    cooldown:Clear()
    cooldown:Hide()
    button.cooldown = cooldown

    -- Charge cooldown (charge regen for multi-charge spells)
    local chargeCooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    chargeCooldown:ClearAllPoints()
    chargeCooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      4, -4)
    chargeCooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4,  4)
    -- Blizzard 12.0: charge cooldowns use the edge ring (not a swipe) to show recharge progress.
    -- SetDrawSwipe(true) causes a large dark polygon that bleeds outside the clipping container.
    -- The edge ring stays within icon bounds and is covered by borderFrame corners if it overflows.
    chargeCooldown:SetDrawSwipe(false) -- No dark swipe overlay; edge ring is the visual
    chargeCooldown:SetDrawEdge(true)   -- Edge ring shows recharge progress (matches Blizzard 12.0)
    chargeCooldown:SetDrawBling(false)
    chargeCooldown:SetHideCountdownNumbers(true)
    -- Same level as the main cooldown, NOT +1: at +1 it tied borderFrame (L+3) and the z-order
    -- fell back to creation order, which a Masque re-skin (it owns both Cooldown elements)
    -- reorders - the swipe/edge then draws over the border and reads as a flicker. The two
    -- never draw together anyway (the ring is suppressed at 0 charges, where the recharge is
    -- promoted to the main swipe), so the +1 bought nothing.
    chargeCooldown:SetFrameLevel(cooldown:GetFrameLevel())
    chargeCooldown:Clear()
    chargeCooldown:Hide()
    button.chargeCooldown = chargeCooldown

    -- Border overlay frame: sits ABOVE cooldowns (both L+2) but BELOW glow animations (L+4+).
    -- The border texture's opaque corners physically cover any cooldown swipe corner bleed.
    -- Strictly above by LEVEL, never by creation order - see the chargeCooldown note.
    local borderFrame = CreateFrame("Frame", nil, button)
    borderFrame:SetFrameLevel(button:GetFrameLevel() + 3)
    borderFrame:SetAllPoints(button)

    local normalTexture = borderFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    ApplyActionButtonBorderGeometry(normalTexture, button, size)
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    button.borderFrame = borderFrame

    -- Casting highlight: shown while IsCurrentSpell is true for the displayed spell.
    -- Sits above the border (sublayer 1) but below glow animations (L+4+).
    local castingHighlight = borderFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    ApplyActionButtonBorderGeometry(castingHighlight, button, size)
    castingHighlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    castingHighlight:SetVertexColor(1, 1, 1, 0.6)
    castingHighlight:Hide()
    button.castingHighlight = castingHighlight

    if isClickable then
        -- Pushed texture
        local pushedTexture = borderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        ApplyActionButtonBorderGeometry(pushedTexture, button, size)
        pushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
        pushedTexture:Hide()
        button.PushedTexture = pushedTexture

        -- Highlight texture
        local highlightTexture = borderFrame:CreateTexture(nil, "HIGHLIGHT", nil, 0)
        ApplyActionButtonBorderGeometry(highlightTexture, button, size)
        highlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        button.HighlightTexture = highlightTexture
    end
    -- Hotkey / overlay text (highest frame level to stay above animations)
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)

    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    local fontSize = math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE))
    hotkeyText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    hotkeyText:SetTextColor(1, 1, 1, 1)
    hotkeyText:SetJustifyH("RIGHT")
    local hotkeyOffset = isFirstIcon and HOTKEY_OFFSET_FIRST or HOTKEY_OFFSET_QUEUE
    hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", hotkeyOffset, hotkeyOffset)
    button.hotkeyText = hotkeyText
    button.hotkeyFrame = hotkeyFrame

    -- "Switch target" arrow: shown on slot 1 when AC re-recommends a DoT already
    -- live on the current target (spread cue). On hotkeyFrame so it sits above the
    -- border and glow layers. Only ever shown at position 1; created on every
    -- pooled icon since a frame can occupy position 1 on a later build.
    local spreadArrow = hotkeyFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    -- Prefer the bold NPE arrow; fall back to the always-present forward-arrow
    -- atlas if this client doesn't have it (avoids a blank overlay).
    local arrowAtlas = "common-icon-forwardarrow"
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("NPE_RightArrow") then
        arrowAtlas = "NPE_RightArrow"
    end
    spreadArrow:SetAtlas(arrowAtlas)
    local arrowSize = math_max(12, math_floor(size * 0.5))
    spreadArrow:SetSize(arrowSize, arrowSize)
    spreadArrow:SetPoint("CENTER", button, "CENTER", 0, 0)
    spreadArrow:Hide()
    button.spreadArrow = spreadArrow

    -- "WAIT" center indicator
    local centerText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 6)
    centerText:SetFont(STANDARD_TEXT_FONT, math_max(9, math_floor(size * 0.26)), "OUTLINE")
    centerText:SetTextColor(1, 0.9, 0.2, 1)
    centerText:SetJustifyH("CENTER")
    centerText:SetJustifyV("MIDDLE")
    centerText:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    centerText:SetText("")
    centerText:Hide()
    button.centerText = centerText

    -- Charge count (bottom-right, like Blizzard action bars)
    local chargeText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    chargeText:SetFont(STANDARD_TEXT_FONT,
        math_max(HOTKEY_MIN_FONT_SIZE, math_floor(size * HOTKEY_FONT_SCALE * 0.65)),
        "OUTLINE")
    chargeText:SetTextColor(1, 1, 1, 1)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
    chargeText:SetText("")
    chargeText:Hide()
    button.chargeText = chargeText

    -- CUE DOT (lower-left): one indicator carrying every per-ability cue, tinted per render by
    -- UIRenderer's ApplyCueDot. Indicator-Gray is a plain round texture present on every client,
    -- so it is tinted here rather than depending on an atlas that might not exist.
    -- The glow behind pulses on its own; the dot itself stays steady.
    local dotInset = math_max(3, math_floor(size * 0.1))
    local cueSize  = math_max(9, math_floor(size * 0.30))
    local cueDot = CreateFrame("Frame", nil, hotkeyFrame)
    cueDot:SetSize(cueSize, cueSize)
    cueDot:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", dotInset, dotInset)

    -- Soft additive halo, in its own frame so ONLY the glow pulses.
    local cueGlowFrame = CreateFrame("Frame", nil, cueDot)
    cueGlowFrame:SetAllPoints(cueDot)
    local cueGlow = cueGlowFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    cueGlow:SetTexture("Interface\\COMMON\\Indicator-Gray")
    cueGlow:SetBlendMode("ADD")
    cueGlow:SetSize(math_floor(cueSize * 2.0), math_floor(cueSize * 2.0))
    cueGlow:SetPoint("CENTER", cueGlowFrame, "CENTER", 0, 0)
    cueDot.glowTex = cueGlow

    -- Dark backing disc, slightly larger than the dot: a built-in outline so the cue survives
    -- being drawn over pale spell art (holy golds, frost whites) where a bright dot alone
    -- would vanish. Cheaper and more reliable than trying to pick colours that happen to
    -- contrast with every icon in the game.
    local cueBackFrame = CreateFrame("Frame", nil, cueDot)
    cueBackFrame:SetAllPoints(cueDot)
    cueBackFrame:SetFrameLevel(cueGlowFrame:GetFrameLevel() + 1)
    local cueBack = cueBackFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    cueBack:SetTexture("Interface\\COMMON\\Indicator-Gray")
    cueBack:SetVertexColor(0, 0, 0, 0.85)
    cueBack:SetSize(math_floor(cueSize * 1.35), math_floor(cueSize * 1.35))
    cueBack:SetPoint("CENTER", cueBackFrame, "CENTER", 0, 0)

    -- Two halves of one disc. Each is the full round texture clipped to its side, so together
    -- they form a seamless circle and can be tinted independently.
    --
    -- BRIGHTNESS: Indicator-Gray is a GREY source and SetVertexColor MULTIPLIES, so a tint can
    -- never come out brighter than the texture it is applied to - which is why a single pass
    -- looked dark and muddy no matter how saturated the colour was. Each half is therefore
    -- drawn in layers: one normal BLEND pass for the shape, then ADDITIVE passes stacked on
    -- top that add light rather than replacing it. That is what takes the fill from "tinted
    -- grey" to neon, and it sits over the dark backing disc so it still has contrast.
    local cueGlyphFrame = CreateFrame("Frame", nil, cueDot)
    cueGlyphFrame:SetAllPoints(cueDot)
    cueGlyphFrame:SetFrameLevel(cueBackFrame:GetFrameLevel() + 1)
    local halfW = cueSize / 2
    local CUE_ADD_PASSES = 2   -- additive layers per half; more = brighter

    -- side: "LEFT"/"RIGHT", coords clip the round texture to that half.
    local function BuildHalf(side, u1, u2)
        local layers = {}
        for pass = 0, CUE_ADD_PASSES do
            local t = cueGlyphFrame:CreateTexture(nil, "OVERLAY", nil, 1 + pass)
            t:SetTexture("Interface\\COMMON\\Indicator-Gray")
            t:SetTexCoord(u1, u2, 0, 1)
            t:SetSize(halfW, cueSize)
            t:SetPoint(side, cueGlyphFrame, side, 0, 0)
            -- Pass 0 lays the shape down; the rest add light on top of it.
            if pass > 0 then t:SetBlendMode("ADD") end
            layers[#layers + 1] = t
        end
        return layers
    end
    cueDot.leftLayers  = BuildHalf("LEFT",  0,   0.5)
    cueDot.rightLayers = BuildHalf("RIGHT", 0.5, 1)

    local cuePulse = cueGlowFrame:CreateAnimationGroup()
    cuePulse:SetLooping("BOUNCE")
    local cuePulseAnim = cuePulse:CreateAnimation("Alpha")
    cuePulseAnim:SetFromAlpha(1.0)
    cuePulseAnim:SetToAlpha(0.3)
    cuePulseAnim:SetDuration(0.9)
    cuePulseAnim:SetSmoothing("IN_OUT")
    cueDot.pulse = cuePulse
    cueDot:SetScript("OnShow", function(self) self.pulse:Play() end)
    cueDot:SetScript("OnHide", function(self) self.pulse:Stop() end)

    cueDot:Hide()
    button.cueDot = cueDot

    -- State tracking fields
    button.spellID = nil
    button.itemID = nil
    button.itemCastSpellID = nil
    button.currentID = nil
    button.isItem = nil

    button._cooldownShown = false
    button._chargeCooldownShown = false
    button.castingHighlightShown = false

    button.normalizedHotkey = nil
    button.previousNormalizedHotkey = nil
    button.spellChangeTime = nil
    button.cachedHotkey = nil

    button.hasAssistedGlow  = false
    button.hasInterruptGlow = false
    button.hasProcGlow      = false
    button.hasDefensiveGlow = false
    button.hasPrecombatGlow = false

    -- Do NOT set alpha to 0 here - defensive icons set it before showing via ShowDefensiveIcon,
    -- and DPS icons are shown directly via icon:Show() without a fadeIn:Play() call.
    button:Hide()

    -- NOTE: ApplyTextOverlaySettings is intentionally NOT called here.
    -- It must be called by each caller AFTER Masque:AddButton(), so our anchor
    -- overrides whatever position Masque's skin applies to the HotKey element.

    return button
end
-- Export for UINameplateOverlay (builds the shared skeleton; callers handle strata + Masque)
UIFrameFactory.CreateBaseIcon = CreateBaseIcon

-- Helper: Create a single defensive icon button at the specified index (0-based)
-- Position offset is calculated based on index, orientation, and defensive position.
-- When detached=true, parents to addon.defensiveFrame and lays out along detachedOrientation.
local function CreateSingleDefensiveButton(addon, profile, index, actualIconSize, defPosition, queueOrientation, spacing)
    local isDetached = profile.defensives and profile.defensives.detached
    local parentFrame = (isDetached and addon.defensiveFrame) or addon.mainFrame
    -- Build the shared icon skeleton (textures, cooldowns, hotkey text, animations)
    local button = CreateBaseIcon(parentFrame, actualIconSize, true, true)
    if not button then return nil end

    -- Born Shown at alpha 0: defensive visibility is alpha-driven (SetDefensiveIconVisible),
    -- and the real Show() is skipped in combat (blocked when target-frame anchoring makes the
    -- family protected). A /reload DURING combat creates these buttons mid-lockdown - born
    -- Hidden they'd stay invisible until the next out-of-combat render. At creation the
    -- anchor family is never protected yet, so this Show() is always combat-safe.
    button:SetAlpha(0)
    button:Show()

    if isDetached then
        -- Detached mode: lay out along detachedOrientation within defensiveFrame.
        -- Mirrors the spell-icon layout in CreateSpellIcons.
        local detachOrientation = profile.defensives.detachedOrientation or "LEFT"
        local iconOffset = index * (actualIconSize + spacing)
        -- Grab tab location per orientation:
        --   LEFT → tab at RIGHT  → icons start at LEFT, no reserve needed
        --   RIGHT → tab at LEFT  → icons start at RIGHT, no reserve needed
        --   UP   → tab at BOTTOM → icons start above tab, reserve at BOTTOM
        --   DOWN → tab at TOP    → icons start below tab, reserve at TOP
        local grabTabReserve = spacing + GRAB_TAB_LENGTH  -- used only for UP and DOWN
        if detachOrientation == "LEFT" then
            button:SetPoint("LEFT", parentFrame, "LEFT", iconOffset, 0)
        elseif detachOrientation == "RIGHT" then
            button:SetPoint("RIGHT", parentFrame, "RIGHT", -iconOffset, 0)
        elseif detachOrientation == "UP" then
            button:SetPoint("BOTTOM", parentFrame, "BOTTOM", 0, iconOffset + grabTabReserve)
        elseif detachOrientation == "DOWN" then
            button:SetPoint("TOP", parentFrame, "TOP", 0, -(iconOffset + grabTabReserve))
        end
    else
        -- Attached mode: position relative to mainFrame based on queue orientation and defensive position
        -- Use spacing directly so the queue-to-queue gap matches the icon-to-icon gap.
        -- UIHealthBar.lua positions the health bar relative to the defensive icon edges (spacing + defIconSize + BAR_SPACING)
        -- so the BAR_SPACING clearance above the defensive icons is preserved regardless of spacing value.
        local firstIconCenter = actualIconSize / 2
        local effectiveSpacing = spacing
        local iconOffset = index * (actualIconSize + spacing)

        -- For RIGHT/UP, icons are shifted within the frame to keep the grab tab at a
        -- predictable position (right for horizontal, bottom for vertical).
        -- Defensive icons must match that shift so they align with the queue icons.
        local grabTabReserve = 0
        if queueOrientation == "RIGHT" or queueOrientation == "UP" then
            local isVert = (queueOrientation == "UP")
            grabTabReserve = spacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
        end

        if queueOrientation == "LEFT" then
            if defPosition == "SIDE1" then
                button:SetPoint("BOTTOM", addon.mainFrame, "TOPLEFT", firstIconCenter + iconOffset, effectiveSpacing)
            elseif defPosition == "SIDE2" then
                button:SetPoint("TOP", addon.mainFrame, "BOTTOMLEFT", firstIconCenter + iconOffset, -effectiveSpacing)
            else -- LEADING
                button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -effectiveSpacing, iconOffset)
            end
        elseif queueOrientation == "RIGHT" then
            if defPosition == "SIDE1" then
                button:SetPoint("BOTTOM", addon.mainFrame, "TOPRIGHT", -firstIconCenter - iconOffset - grabTabReserve, effectiveSpacing)
            elseif defPosition == "SIDE2" then
                button:SetPoint("TOP", addon.mainFrame, "BOTTOMRIGHT", -firstIconCenter - iconOffset - grabTabReserve, -effectiveSpacing)
            else -- LEADING
                button:SetPoint("LEFT", addon.mainFrame, "RIGHT", effectiveSpacing, iconOffset)
            end
        elseif queueOrientation == "UP" then
            if defPosition == "SIDE1" then
                button:SetPoint("LEFT", addon.mainFrame, "BOTTOMRIGHT", effectiveSpacing, firstIconCenter + iconOffset + grabTabReserve)
            elseif defPosition == "SIDE2" then
                button:SetPoint("RIGHT", addon.mainFrame, "BOTTOMLEFT", -effectiveSpacing, firstIconCenter + iconOffset + grabTabReserve)
            else -- LEADING
                button:SetPoint("TOP", addon.mainFrame, "BOTTOM", iconOffset, -effectiveSpacing)
            end
        elseif queueOrientation == "DOWN" then
            if defPosition == "SIDE1" then
                button:SetPoint("LEFT", addon.mainFrame, "TOPRIGHT", effectiveSpacing, -firstIconCenter - iconOffset)
            elseif defPosition == "SIDE2" then
                button:SetPoint("RIGHT", addon.mainFrame, "TOPLEFT", -effectiveSpacing, -firstIconCenter - iconOffset)
            else -- LEADING
                button:SetPoint("BOTTOM", addon.mainFrame, "TOP", iconOffset, effectiveSpacing)
            end
        end
    end

    -- Tooltip handling
    button:SetScript("OnEnter", function(self)
        ShowIconHotkeyTooltip(addon, self)
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click for hotkey override
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if IsPanelLocked(profile) then return end

            if self.spellID and not self.isItem then
                addon:OpenHotkeyOverrideDialog(self.spellID)
            elseif self.isItem and self.itemID then
                addon:OpenHotkeyOverrideDialog(-self.itemID)
            end
        end
    end)

    RegisterMasque(button, actualIconSize, profile)

    return button
end

-- Creates the detached defensive frame (UIParent child) with fade animations.
-- Mirrors CreateMainFrame pattern. Called by CreateDefensiveIcons when detached=true.
-- Attaches frame.fadeIn / frame.fadeOut Alpha animation groups (0↔1, SetToFinalAlpha).
-- onInFinished / onOutFinished: optional OnFinished callbacks.
local function AddFadeAnims(frame, duration, onInFinished, onOutFinished)
    local fadeIn = frame:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(duration)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    if onInFinished then fadeIn:SetScript("OnFinished", onInFinished) end
    frame.fadeIn = fadeIn

    local fadeOut = frame:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(duration)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    if onOutFinished then fadeOut:SetScript("OnFinished", onOutFinished) end
    frame.fadeOut = fadeOut
end

-- Sole caller (CreateDefensiveIcons) destroys any existing detached frame/grab tab first.
local function CreateDetachedDefensiveFrame(addon)
    local profile = addon:GetProfile()
    if not profile then return end

    local frame = CreateFrame("Frame", "JustACDefensiveFrame", UIParent)
    if not frame then return end
    addon.defensiveFrame = frame

    -- Restore saved position (older saves carry no relativePoint; fall back to the
    -- symmetric point-to-point apply they were written for)
    local dpos = profile.defensives and profile.defensives.detachedPosition
    if dpos and dpos.point then
        frame:SetPoint(dpos.point, UIParent, dpos.relativePoint or dpos.point, dpos.x or 0, dpos.y or 100)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    frame:SetScript("OnLeave", function()
        if addon.defensiveGrabTab and addon.defensiveGrabTab.fadeOut
            and not addon.defensiveGrabTab:IsMouseOver()
            and not addon.defensiveGrabTab.isDragging then
            addon.defensiveGrabTab.fadeOut:Play()
        end
    end)

    frame:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "RightButton" then
            -- Locked panels offer no menu (the standard-queue body has the same rule).
            if IsPanelLocked(addon:GetProfile()) then return end
            OpenOptions(addon)
        end
    end)

    -- Fade animations
    AddFadeAnims(frame, 0.1, function()
        local currentProfile = addon:GetProfile()
        local frameOpacity = currentProfile and currentProfile.frameOpacity or 1.0
        frame:SetAlpha(frameOpacity)
    end, function()
        frame:Hide()
        frame:SetAlpha(0)
    end)

    frame:SetAlpha(0)
    frame:Hide()
end

-- Shared grab-tab builder for the main queue and the detached defensive frame.
-- Builds the backdrop, dot textures, drag/click/fade scripts. opts:
--   frame            - frame the tab attaches to and moves (StartMoving/StopMovingOrSizing)
--   isVertical       - tab orientation (swaps size and dot arrangement)
--   anchorPoint      - point on `frame` where the tab sits ("RIGHT"/"LEFT"/"BOTTOM"/"TOP")
--   onDragStart      - optional; called with (tab, profile) after fades stop, before StartMoving
--   onDragStop       - called with (tab) after StopMovingOrSizing; saves position, marks dirty
--   onShiftRightClick - optional; plain right-click always opens the options panel
--   addTooltipLines  - adds body lines after the "JustAssistedCombat" title
local function BuildGrabTab(addon, opts)
    local frame = opts.frame
    local tab = CreateFrame("Button", nil, frame, "BackdropTemplate")
    if not tab then return nil end

    if opts.isVertical then
        tab:SetSize(20, GRAB_TAB_LENGTH)
    else
        tab:SetSize(GRAB_TAB_LENGTH, 20)
    end

    -- Extend the clickable hit area beyond the visible tab (negative insets = larger area)
    -- Makes the small tab much easier to grab, especially on high-DPI displays
    tab:SetHitRectInsets(-6, -6, -6, -6)
    tab:SetPoint(opts.anchorPoint, frame, opts.anchorPoint, 0, 0)

    tab:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    tab:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
    tab:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

    -- Three grip dots, arranged across the tab's short axis
    for i = -1, 1 do
        local dot = tab:CreateTexture(nil, "OVERLAY")
        dot:SetSize(2, 2)
        dot:SetColorTexture(0.8, 0.8, 0.8, 1)
        if opts.isVertical then
            dot:SetPoint("CENTER", tab, "CENTER", i * 4, 0)
        else
            dot:SetPoint("CENTER", tab, "CENTER", 0, i * 4)
        end
    end

    tab:EnableMouse(true)
    tab:RegisterForClicks("RightButtonUp")

    -- Press-grab, NOT RegisterForDrag: the drag threshold delayed the pickup until
    -- the cursor had already traveled off the tab, and StartMoving's snap-to-mouse
    -- then preserved that gap for the whole drag - the frame trailed beside the
    -- cursor. Grabbing on press starts instantly, and plain StartMoving keeps the
    -- cursor exactly where it grabbed the tab.
    tab:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local profile = addon:GetProfile()
        if not profile or IsPanelLocked(profile) then return end

        -- Mark as dragging (addon-level for OnUpdate freeze, tab-level for fade logic)
        self.isDragging = true
        addon.isDragging = true

        -- Stop any fade animation and ensure fully visible
        if self.fadeOut and self.fadeOut:IsPlaying() then self.fadeOut:Stop() end
        if self.fadeIn  and self.fadeIn:IsPlaying()  then self.fadeIn:Stop()  end
        self:SetAlpha(1)

        self.dragFromX, self.dragFromY = GetCursorPosition()
        if opts.onDragStart then opts.onDragStart(self, profile) end

        -- Move the owning frame (grab tab follows since it's anchored to it)
        frame:StartMoving()
    end)

    tab:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.isDragging then return end
        frame:StopMovingOrSizing()
        self.isDragging = false
        addon.isDragging = false

        -- A press without movement is a click, not a drag: skip the drop handling
        -- so a stray left-click can't undock the frame or churn the saved position.
        -- StopMovingOrSizing did convert a docked frame's anchor to an absolute
        -- point, so re-run the anchor pass - it re-pins when docking is on and
        -- no-ops otherwise (the frame hasn't moved).
        local x, y = GetCursorPosition()
        local dx, dy = x - (self.dragFromX or x), y - (self.dragFromY or y)
        if dx * dx + dy * dy > 16 then
            opts.onDragStop(self)
        elseif addon.UpdateTargetFrameAnchor then
            addon:UpdateTargetFrameAnchor()
        end

        -- Fade out if mouse isn't over frame/tab
        if not frame:IsMouseOver() and not self:IsMouseOver() and self.fadeOut then
            self.fadeOut:Play()
        end
    end)

    tab:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "RightButton" then return end
        if opts.onShiftRightClick and IsShiftKeyDown() then
            opts.onShiftRightClick()
        else
            -- Belt-and-braces: a locked panel hides its tabs (UIRenderer), but a tab that
            -- is somehow shown must still not open the menu while locked.
            if IsPanelLocked(addon:GetProfile()) then return end
            OpenOptions(addon)
        end
    end)

    tab:SetScript("OnEnter", function(self)
        if self.fadeOut and self.fadeOut:IsPlaying() then self.fadeOut:Stop() end
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("JustAssistedCombat")
        opts.addTooltipLines()
        GameTooltip:Show()
    end)

    tab:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Hide grab tab if mouse leaves and isn't over the owning frame or being dragged
        if not frame:IsMouseOver() and not self.isDragging and self.fadeOut then
            self.fadeOut:Play()
        end
    end)

    -- Fade animations. Stay shown (alpha=0) so the frame keeps receiving mouse events.
    AddFadeAnims(tab, 0.15, nil, function()
        tab:SetAlpha(0)
    end)

    -- Start invisible but shown so mouse detection works immediately
    tab:SetAlpha(0)
    tab:Show()
    -- ...unless the panel is locked or click-through: a tab exists to drag and to open
    -- the menu, and a locked panel offers neither. Applied HERE, at birth, because tabs
    -- are rebuilt on every UpdateFrameSize and the renderer's mode block only re-runs
    -- on a mode CHANGE - so a settings tweak on a locked panel resurrected the tab.
    if IsPanelLocked(addon:GetProfile()) then
        tab:Hide()
        tab:EnableMouse(false)
    end

    return tab
end

-- Creates the drag handle for the detached defensive frame.
-- Position based on detachedOrientation (mirrors CreateGrabTab for mainFrame).
local function CreateDefensiveGrabTab(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    local orientation = profile and profile.defensives and profile.defensives.detachedOrientation or "LEFT"
    local isVertical = (orientation == "UP" or orientation == "DOWN")

    -- Grab tab sits at the "end" of the icon growth direction:
    --   LEFT  → icons grow left-to-right  → grab tab on RIGHT
    --   RIGHT → icons grow right-to-left  → grab tab on LEFT
    --   UP    → icons grow bottom-to-top  → grab tab on BOTTOM
    --   DOWN  → icons grow top-to-bottom  → grab tab on TOP
    local anchorPoint
    if orientation == "RIGHT" then
        anchorPoint = "LEFT"
    elseif orientation == "UP" then
        anchorPoint = "BOTTOM"
    elseif orientation == "DOWN" then
        anchorPoint = "TOP"
    else -- LEFT (default)
        anchorPoint = "RIGHT"
    end

    addon.defensiveGrabTab = BuildGrabTab(addon, {
        frame = addon.defensiveFrame,
        isVertical = isVertical,
        anchorPoint = anchorPoint,
        onDragStop = function()
            UIFrameFactory.SaveDefensivePosition(addon)
            if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
        end,
        addTooltipLines = function()
            GameTooltip:AddLine("Defensive Panel - Drag to move", 1, 1, 1)
            GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
        end,
    })
end

-- In click-through mode, icons become drag handles when Alt is held for the hold threshold.
-- A C_Timer delay filters out brief Alt taps used in macros so they never trigger drag mode.
-- Registered once on first CreateGrabTab call; re-calls are no-ops via addon.clickThroughModListener.
function UIFrameFactory.SetupClickThroughIconDrag(addon)
    if addon.clickThroughModListener then return end

    local altHoldTimer = nil
    local dragModeActive = false

    local function DisableIconDragMode()
        dragModeActive = false
        for _, icon in ipairs(addon.spellIcons or {}) do
            icon:EnableMouse(false)
            icon:SetScript("OnMouseDown", nil)
            icon:SetScript("OnMouseUp", nil)
        end
        for _, icon in ipairs(addon.defensiveIcons or {}) do
            icon:EnableMouse(false)
            icon:SetScript("OnMouseDown", nil)
            icon:SetScript("OnMouseUp", nil)
        end
    end

    -- Press-grab, same pattern (and reasons) as the grab tab: the drag threshold
    -- delayed the pickup and snap-to-mouse kept the resulting gap. A press without
    -- movement releases in place with no side effects (drag mode stays armed while
    -- Alt is held).
    local dragFromX, dragFromY
    local function IconPressMoved()
        local x, y = GetCursorPosition()
        local dx, dy = x - (dragFromX or x), y - (dragFromY or y)
        return dx * dx + dy * dy > 16
    end

    local function EnableIconDragMode()
        dragModeActive = true
        for _, icon in ipairs(addon.spellIcons or {}) do
            icon:EnableMouse(true)
            icon:SetScript("OnMouseDown", function(_, button)
                if button ~= "LeftButton" then return end
                addon.isDragging = true
                dragFromX, dragFromY = GetCursorPosition()
                addon.mainFrame:StartMoving()
            end)
            icon:SetScript("OnMouseUp", function(_, button)
                if button ~= "LeftButton" or not addon.isDragging then return end
                addon.mainFrame:StopMovingOrSizing()
                addon.isDragging = false
                if IconPressMoved() then
                    -- Same undock rule as the grab tab: SavePosition no-ops while
                    -- docked, so a docked Alt-drag was silently thrown away.
                    UIFrameFactory.UndockAfterManualDrag(addon)
                    UIFrameFactory.SavePosition(addon)
                    if addon.MarkQueueDirty then addon:MarkQueueDirty() end
                    if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
                    DisableIconDragMode()
                elseif addon.UpdateTargetFrameAnchor then
                    addon:UpdateTargetFrameAnchor()
                end
            end)
        end
        for _, icon in ipairs(addon.defensiveIcons or {}) do
            icon:EnableMouse(true)
            icon:SetScript("OnMouseDown", function(_, button)
                if button ~= "LeftButton" then return end
                addon.isDragging = true
                dragFromX, dragFromY = GetCursorPosition()
                if addon.defensiveFrame then addon.defensiveFrame:StartMoving() end
            end)
            icon:SetScript("OnMouseUp", function(_, button)
                if button ~= "LeftButton" or not addon.isDragging then return end
                if addon.defensiveFrame then addon.defensiveFrame:StopMovingOrSizing() end
                addon.isDragging = false
                if IconPressMoved() then
                    UIFrameFactory.SaveDefensivePosition(addon)
                    if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
                    DisableIconDragMode()
                end
            end)
        end
    end

    local listener = CreateFrame("Frame")
    listener:RegisterEvent("MODIFIER_STATE_CHANGED")
    listener:SetScript("OnEvent", function()
        local p = addon:GetProfile()
        if not p then return end
        if (p.panelInteraction or "unlocked") ~= "clickthrough" then
            if altHoldTimer then altHoldTimer:Cancel() altHoldTimer = nil end
            if dragModeActive then
                -- Mode switched away mid-press: end any live drag BEFORE tearing the
                -- scripts down - nil'ing OnMouseUp mid-drag would leave the frame
                -- glued to the cursor and the isDragging freeze stuck.
                if addon.isDragging then
                    if addon.mainFrame then addon.mainFrame:StopMovingOrSizing() end
                    if addon.defensiveFrame then addon.defensiveFrame:StopMovingOrSizing() end
                    addon.isDragging = false
                end
                DisableIconDragMode()
            end
            return
        end
        if IsAltKeyDown() then
            if not altHoldTimer and not dragModeActive then
                altHoldTimer = C_Timer.NewTimer(0.4, function()
                    altHoldTimer = nil
                    if IsAltKeyDown() then EnableIconDragMode() end
                end)
            end
        else
            if altHoldTimer then altHoldTimer:Cancel() altHoldTimer = nil end
            if dragModeActive and not addon.isDragging then
                DisableIconDragMode()
            end
        end
    end)
    addon.clickThroughModListener = listener
end

function UIFrameFactory.SaveDefensivePosition(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end
    -- Keep relativePoint: dropping it and re-applying point-to-point shifts the
    -- frame on reload whenever the two differ - the exact lossy-save hazard the
    -- main frame's SavePosition documents and avoids.
    local point, _, relativePoint, x, y = addon.defensiveFrame:GetPoint()
    if not point then return end
    profile.defensives.detachedPosition =
        { point = point, relativePoint = relativePoint, x = x or 0, y = y or 100 }
end

function UIFrameFactory.UpdateDefensiveFrameSize(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local defOrientation = profile.defensives.detachedOrientation or "LEFT"
    local isVertical = (defOrientation == "UP" or defOrientation == "DOWN")
    local iconSize    = profile.iconSize or 42
    local iconScale   = profile.defensives.iconScale or 1.0
    local actualIconSize = iconSize * iconScale
    local iconSpacing = profile.iconSpacing or 1
    local maxIcons    = math.min(profile.defensives.maxIcons or 4, 7)

    local grabTabSpacing
    if isVertical then
        grabTabSpacing = iconSpacing + GRAB_TAB_LENGTH
    else
        grabTabSpacing = iconSpacing + GRAB_TAB_LENGTH + 1
    end

    local totalLength = maxIcons * actualIconSize + (maxIcons - 1) * iconSpacing

    if isVertical then
        addon.defensiveFrame:SetSize(actualIconSize, totalLength + grabTabSpacing)
    else
        addon.defensiveFrame:SetSize(totalLength + grabTabSpacing, actualIconSize)
    end
end

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
    local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
    for _, icon in ipairs(defensiveIcons) do
        if icon then
            if StopDefensiveGlow then StopDefensiveGlow(icon) end
            if MasqueGroup then MasqueGroup:RemoveButton(icon) end
            icon:Hide()
            icon:SetParent(nil)
        end
    end
    wipe(defensiveIcons)
    addon.defensiveIcons = nil

    -- Tear the maintenance slot down with its siblings, ABOVE the "defensives disabled" early
    -- return below - otherwise turning defensives off orphans the button on screen and leaks
    -- it out of the skinning group.
    if addon.maintenanceIcon then
        if UIAnimations then UIAnimations.HideColoredProcGlow(addon.maintenanceIcon, "maintenanceGlow") end
        if MasqueGroup then MasqueGroup:RemoveButton(addon.maintenanceIcon) end
        addon.maintenanceIcon:Hide()
        addon.maintenanceIcon:SetParent(nil)
        addon.maintenanceIcon = nil
    end

    -- Always destroy the detached frame on rebuild; recreated below if still detached.
    if addon.defensiveFrame then
        addon.defensiveFrame:Hide()
        addon.defensiveFrame:SetParent(nil)
        addon.defensiveFrame = nil
    end
    if addon.defensiveGrabTab then
        addon.defensiveGrabTab:Hide()
        addon.defensiveGrabTab:SetParent(nil)
        addon.defensiveGrabTab = nil
    end

    if not profile.defensives or not profile.defensives.enabled then return end

    -- When detached, create the independent frame BEFORE parenting icons to it.
    local isDetached = profile.defensives.detached
    if isDetached then
        CreateDetachedDefensiveFrame(addon)
        if not addon.defensiveFrame then return end  -- frame creation failed
    end

    -- Calculate shared sizing
    local defensiveIconScale = profile.defensives.iconScale or 1.0
    local actualIconSize = profile.iconSize * defensiveIconScale
    local defPosition = profile.defensives.position or "SIDE1"
    local queueOrientation = profile.queueOrientation or "LEFT"
    local spacing = profile.iconSpacing

    -- Don't reuse module-level table to avoid stale reference issues.
    local maxIcons = profile.defensives.maxIcons or 4
    maxIcons = math.min(maxIcons, 7)  -- Cap at 7 (same as offensive queue)

    local newIcons = {}
    for i = 1, maxIcons do
        local button = CreateSingleDefensiveButton(addon, profile, i - 1, actualIconSize, defPosition, queueOrientation, spacing)
        if button then
            newIcons[i] = button
            defensiveIcons[i] = button  -- Also update module-level for cleanup on next call
        end
    end

    -- Defensive maintenance slot - "position 0" of the defensive row, the mirror of the
    -- interrupt slot on the offensive queue. Built at index -1 so it lands one slot BEFORE
    -- the first defensive icon, reusing the same layout maths for every orientation,
    -- both sides, and detached mode - no separate anchoring to keep in sync.
    -- Only tank specs have a maintenance buff, but the button is built regardless: spec can
    -- change without a frame rebuild, and an unused button simply stays hidden.
    local maint = CreateSingleDefensiveButton(addon, profile, -1, actualIconSize, defPosition, queueOrientation, spacing)
    if maint then
        maint:SetAlpha(0)   -- alpha-driven like its siblings; the renderer reveals it
        -- Applied here and again from the Masque skin-changed callback, never per render.
        UIFrameFactory.ApplyMaintenanceSwipeStyle(maint)
        addon.maintenanceIcon = maint
    end

    -- Expose to addon (use the fresh table, not the module-level one)
    addon.defensiveIcons = newIcons

    -- When detached, size the container frame and create its grab tab.
    if isDetached then
        UIFrameFactory.UpdateDefensiveFrameSize(addon)
        CreateDefensiveGrabTab(addon)
    end

    local UIRenderer = LibStub("JustAC-UIRenderer", true)
    for i, state in pairs(savedStates) do
        if newIcons[i] and state.isShown and UIRenderer and UIRenderer.ShowDefensiveIcon then
            local showGlow = (i == 1)
            UIRenderer.ShowDefensiveIcon(addon, state.id, state.isItem, newIcons[i], showGlow)
        end
    end
end

--- Anchor the main frame to its saved position. Explicit five-argument SetPoint so the
--- saved relativePoint survives the round-trip, and every field defaulted because
--- framePosition can be absent on a fresh or reset profile.
function UIFrameFactory.ApplySavedPosition(addon, profile)
    if not addon.mainFrame then return end
    local pos = profile and profile.framePosition
    local point = pos and pos.point or "CENTER"
    addon.mainFrame:SetPoint(point, UIParent, pos and pos.relativePoint or point,
        pos and pos.x or 0, pos and pos.y or -150)
end
local ApplySavedPosition = UIFrameFactory.ApplySavedPosition

function UIFrameFactory.CreateMainFrame(addon)
    local profile = addon:GetProfile()
    if not profile then return end

    addon.mainFrame = CreateFrame("Frame", "JustACFrame", UIParent)
    if not addon.mainFrame then return end

    UIFrameFactory.UpdateFrameSize(addon)

    ApplySavedPosition(addon, profile)

    addon.mainFrame:EnableMouse(true)
    addon.mainFrame:SetMovable(true)   -- Required: grab tab delegates StartMoving() to mainFrame
    addon.mainFrame:SetClampedToScreen(true)
    
    addon.mainFrame:SetScript("OnEnter", function()
        -- intentionally empty: grab tab only appears on direct hover
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
                -- Announced out loud, not to the debug channel. Locking removes the only way
                -- to move the panel, and shift+right-click on an icon means "blacklist this
                -- spell" - so a near-miss on an icon lands here instead and silently takes
                -- dragging away, leaving nothing on screen to explain why. One owner for
                -- toggle+announce (JustAC:TogglePanelLock) - the minimap button uses it too.
                if addon.TogglePanelLock then addon:TogglePanelLock() end
            else
                OpenOptions(addon)
            end
        end
    end)
    
    -- Start hidden to avoid showing an empty UI; fade in when spells appear
    addon.mainFrame:SetAlpha(0)  -- Start invisible for fade-in
    addon.mainFrame:Hide()
    
    -- Fade animations
    AddFadeAnims(addon.mainFrame, 0.1, function()
        -- Apply user's frame opacity after fade completes
        local currentProfile = addon:GetProfile()
        local frameOpacity = currentProfile and currentProfile.frameOpacity or 1.0
        addon.mainFrame:SetAlpha(frameOpacity)
    end, function()
        addon.mainFrame:Hide()
        addon.mainFrame:SetAlpha(0)
    end)
end

function UIFrameFactory.CreateGrabTab(addon)
    local profile = addon:GetProfile()
    local orientation = profile and profile.queueOrientation or "LEFT"
    local isVertical = (orientation == "UP" or orientation == "DOWN")

    -- Predictable position: always at the right end (horizontal) or bottom (vertical).
    -- For RIGHT/UP orientations the icons are shifted within the frame to make room.
    addon.grabTab = BuildGrabTab(addon, {
        frame = addon.mainFrame,
        isVertical = isVertical,
        anchorPoint = isVertical and "BOTTOM" or "RIGHT",
        onDragStart = function()
            -- Docked: drop the flag only. StartMoving picks the frame up right where
            -- it sits (under the cursor at the dock) and StopMovingOrSizing leaves it
            -- with an absolute anchor for SavePosition. The old teleport-to-saved-
            -- position here yanked the frame across the screen at drag start - it
            -- existed to compensate for the snap-to-mouse drag, which is gone.
            addon.targetframe_anchored = false
        end,
        onDragStop = function()
            -- User manually dragged - auto-disable target frame anchor so it doesn't snap back
            UIFrameFactory.UndockAfterManualDrag(addon)

            UIFrameFactory.SavePosition(addon)

            -- Mark queues dirty so icons refresh immediately at new position
            if addon.MarkQueueDirty then addon:MarkQueueDirty() end
            if addon.MarkDefensiveDirty then addon:MarkDefensiveDirty() end
        end,
        onShiftRightClick = function()
            -- Safe in combat: only modifies addon db, no restricted API calls
            local currentProfile = addon:GetProfile()
            if currentProfile then
                local nowLocked = TogglePanelLock(currentProfile)
                local status = nowLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
            end
        end,
        addTooltipLines = function()
            local currentProfile = addon:GetProfile()
            local isLocked = IsPanelLocked(currentProfile)
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
        end,
    })
    if not addon.grabTab then return end

    -- Wire icon drag mode for click-through (once, guarded against re-registration).
    UIFrameFactory.SetupClickThroughIconDrag(addon)
end

-- Create a single interrupt icon positioned in the "leading" direction before slot 1.
-- The icon overhangs outside mainFrame (like defensive icons).
local function CreateInterruptIcon(addon, profile)
    -- Cleanup any existing interrupt icon
    if stdInterruptIcon then
        if UIAnimations then
            if stdInterruptIcon.hasInterruptGlow then UIAnimations.HideInterruptProcGlow(stdInterruptIcon) end
            if stdInterruptIcon.hasProcGlow      then UIAnimations.HideProcGlow(stdInterruptIcon)      end
        end
        local MasqueGroup = GetMasqueGroup and GetMasqueGroup()
        if MasqueGroup then
            MasqueGroup:RemoveButton(stdInterruptIcon)
        end
        if stdInterruptIcon.sootheCue then
            stdInterruptIcon.sootheCue:Hide()
            stdInterruptIcon.sootheCue:SetParent(nil)
        end
        stdInterruptIcon:Hide()
        stdInterruptIcon:SetParent(nil)
        stdInterruptIcon = nil
    end
    addon.interruptIcon = nil
    addon.resolvedInterrupts = nil
    addon.resolvedSoothe = nil

    -- The icon is the shared "position 0" slot, not the kick's private property: the enrage
    -- cleanse cue rides it too, and those are independent choices. Build it when EITHER wants
    -- it. Existing does not mean visible - the kick self-gates on interruptMode inside
    -- RenderInterruptSlot, so a player who turned interrupt reminders off but kept the cleanse
    -- cue gets a slot that only ever shows the cleanse.
    -- ResolveSootheSpells is spec-dependent, so this also means no wasted frame for the many
    -- specs that have no cleanse at all.
    if (profile.interruptMode or "kickPrefer") == "disabled" then
        local wantSoothe = profile.showSootheCue ~= false
            and SpellDB.ResolveSootheSpells() ~= nil
        if not wantSoothe then return end
    end

    local firstIconScale = profile.firstIconScale or 1.0
    local actualIconSize = profile.iconSize * firstIconScale
    local orientation = profile.queueOrientation or "LEFT"
    local spacing = profile.iconSpacing or 1

    local button = CreateBaseIcon(addon.mainFrame, actualIconSize, true, true)
    if not button then return end

    -- Position before slot 1 (opposite of queue growth direction)
    -- No health bar is associated with the interrupt icon, so use spacing directly.
    local effectiveSpacing = spacing

    -- For RIGHT/UP, icon 1 is shifted inward by grabTabReserve to make room for
    -- the grab tab at the same edge.  We mirror that shift here so the interrupt
    -- sits adjacent to icon 1 (effectiveSpacing gap) rather than beyond the grab tab.
    if orientation == "LEFT" then
        -- Queue grows left-to-right; interrupt goes to the LEFT of mainFrame
        button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -effectiveSpacing, 0)
    elseif orientation == "RIGHT" then
        -- Queue grows right-to-left; interrupt adjacent to icon 1 (covers grab tab)
        local grabTabReserve = spacing + GRAB_TAB_LENGTH + 1
        button:SetPoint("LEFT", addon.mainFrame, "RIGHT", -(grabTabReserve - effectiveSpacing), 0)
    elseif orientation == "UP" then
        -- Queue grows bottom-to-top; interrupt adjacent to icon 1 (covers grab tab)
        local grabTabReserve = spacing + GRAB_TAB_LENGTH
        button:SetPoint("TOP", addon.mainFrame, "BOTTOM", 0, grabTabReserve - effectiveSpacing)
    elseif orientation == "DOWN" then
        -- Queue grows top-to-bottom; interrupt goes ABOVE mainFrame
        button:SetPoint("BOTTOM", addon.mainFrame, "TOP", 0, effectiveSpacing)
    end

    -- Ensure interrupt renders above the grab tab when they overlap (RIGHT/UP)
    button:SetFrameLevel(button:GetFrameLevel() + 5)

    -- Tooltip handling
    button:SetScript("OnEnter", function(self)
        if not self.spellID then return end
        ShowIconHotkeyTooltip(addon, self)
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Right-click for hotkey override
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if IsPanelLocked(profile) then return end

            if self.spellID then
                addon:OpenHotkeyOverrideDialog(self.spellID)
            end
        end
    end)

    RegisterMasque(button, actualIconSize, profile)

    -- Cast aura: small icon showing what the enemy is casting, attached to
    -- the interrupt button.  Always placed on the side away from the queue
    -- so it doesn't overlap icon 1.
    local castAura = UIFrameFactory.CreateAuraSubIcon(button, actualIconSize, profile, orientation)
    castAura.spellID = nil
    castAura:Hide()  -- shown only while an interruptible cast is up (driven by UIRenderer)
    button.castAura = castAura

    button:Hide()  -- Hidden until an interruptible cast is detected

    stdInterruptIcon = button
    addon.interruptIcon = button
    addon.resolvedInterrupts = SpellDB.ResolveInterruptSpells()
    addon.resolvedSoothe = SpellDB.ResolveSootheSpells()
end

function UIFrameFactory.CreateSpellIcons(addon)
    local profile = addon:GetProfile()
    if not profile or not addon.mainFrame then return end
    
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
    
    local orientation = profile.queueOrientation or "LEFT"
    
    -- For RIGHT/UP, reserve space at the icon-start edge so the grab tab
    -- can sit at a predictable position (right for horizontal, bottom for vertical)
    local currentOffset = 0
    if orientation == "RIGHT" or orientation == "UP" then
        local isVert = (orientation == "UP")
        currentOffset = profile.iconSpacing + GRAB_TAB_LENGTH + (isVert and 0 or 1)
    end
    
    for i = 1, profile.maxIcons do
        local button = UIFrameFactory.CreateSingleSpellIcon(addon, i, currentOffset, profile)
        if button then
            spellIcons[i] = button
            -- Consistent spacing between all icons
            currentOffset = currentOffset + button:GetWidth() + profile.iconSpacing
        end
    end
    
    addon.spellIcons = spellIcons
    
    -- Create interrupt icon (position 0, hidden until interruptible cast detected)
    CreateInterruptIcon(addon, profile)
    -- NOTE: CreateDefensiveIcons is called separately from UpdateFrameSize, not here,
    -- so that defensive icon creation is not gated by the mainFrame guard above.
end

-- SIMPLIFIED: Pure display-only icons with configuration only
function UIFrameFactory.CreateSingleSpellIcon(addon, index, offset, profile)
    local isFirstIcon = (index == 1)
    local firstIconScale = profile.firstIconScale or 1.0
    local actualIconSize = isFirstIcon and (profile.iconSize * firstIconScale) or profile.iconSize
    local orientation = profile.queueOrientation or "LEFT"

    local button = CreateBaseIcon(addon.mainFrame, actualIconSize, true, isFirstIcon)
    if not button then return nil end

    -- Position based on orientation
    if orientation == "RIGHT" then
        button:SetPoint("RIGHT", -offset, 0)
    elseif orientation == "UP" then
        button:SetPoint("BOTTOM", 0, offset)
    elseif orientation == "DOWN" then
        button:SetPoint("TOP", 0, -offset)
    else -- LEFT (default)
        button:SetPoint("LEFT", offset, 0)
    end

    -- Right-click menu for configuration
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if IsPanelLocked(profile) then return end

            if self.spellID then
                if IsShiftKeyDown() then
                    -- Blacklist: hides the spell from every position (incl. position 1).
                    -- Reordering the fixed queue (positions 2+) is done in the options tab.
                    addon:ToggleSpellBlacklist(self.spellID)
                else
                    addon:OpenHotkeyOverrideDialog(self.spellID)
                end
            else
                if IsShiftKeyDown() then
                    local nowLocked = TogglePanelLock(profile)
                    local status = nowLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                else
                    OpenOptions(addon)
                end
            end
        end
    end)

    button:SetScript("OnEnter", function(self)
        if self.spellID then
            ShowIconHotkeyTooltip(addon, self, true)
        end
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if addon.grabTab and addon.grabTab.fadeOut and not addon.mainFrame:IsMouseOver() and not addon.grabTab:IsMouseOver() and not addon.grabTab.isDragging then
            addon.grabTab.fadeOut:Play()
        end
    end)

    RegisterMasque(button, actualIconSize, profile)

    return button
end

function UIFrameFactory.UpdateFrameSize(addon)
    local profile = addon:GetProfile()
    if not profile or not addon.mainFrame then return end

    local newMaxIcons = profile.maxIcons
    local newIconSize = profile.iconSize
    local newIconSpacing = profile.iconSpacing
    local firstIconScale = profile.firstIconScale or 1.0
    local orientation = profile.queueOrientation or "LEFT"

    UIFrameFactory.CreateSpellIcons(addon)
    -- Defensives are decoupled from CreateSpellIcons and always created here,
    -- so they are not gated by CreateSpellIcons's mainFrame guard.
    CreateDefensiveIcons(addon, profile)

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

    -- The normalTexture used for icon borders extends 1px beyond the button
    -- width which visually reduces the gap. We want the visual gap between
    -- the last icon and the grab tab to equal `newIconSpacing`.
    --
    -- Compute grabTabSpacing so that (grabTabSpacing - GRAB_TAB_LENGTH - visualOverflow) == newIconSpacing
    local visualOverflow = 1 -- visual overflow of icon borders
    local grabTabSpacing
    if isVertical then
        -- For vertical queues: spacing down/up should equal icon spacing + grab tab length
        grabTabSpacing = newIconSpacing + GRAB_TAB_LENGTH
    else
        -- For horizontal queues: account for 1px icon border overflow
        grabTabSpacing = newIconSpacing + GRAB_TAB_LENGTH + visualOverflow
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
    
    -- Guard: don't save while anchored to TargetFrame - GetPoint() would return
    -- TargetFrame-relative offsets which are meaningless as a saved position.
    if addon.targetframe_anchored then return end

    -- relativePoint is kept, not discarded: the restore below re-anchors with the explicit
    -- five-argument form, and the short form would silently force relativePoint == point.
    -- Those agree for everything we set today, so dropping it happened to round-trip - but
    -- it makes the save lossy, and the day something leaves the frame anchored corner-to-
    -- centre it reloads somewhere else entirely.
    local point, _, relativePoint, x, y = addon.mainFrame:GetPoint()
    if not point then return end
    profile.framePosition = {
        point = point,
        relativePoint = relativePoint or point,
        x = x or 0,
        y = y or -150,
    }
end

