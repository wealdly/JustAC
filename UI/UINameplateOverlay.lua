-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Nameplate Overlay Module
-- An independent display that anchors DPS queue icons (and optional defensives +
-- player health bar) directly to the target's nameplate.  Completely separate from
-- the main panel – either feature can be enabled without the other.
local UINameplateOverlay = LibStub:NewLibrary("JustAC-UINameplateOverlay", 6)
if not UINameplateOverlay then return end

local BlizzardAPI      = LibStub("JustAC-BlizzardAPI",      true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local UIAnimations     = LibStub("JustAC-UIAnimations",    true)
local UIRenderer       = LibStub("JustAC-UIRenderer",      true)
local UIFrameFactory   = LibStub("JustAC-UIFrameFactory",  true)
local SpellQueue       = LibStub("JustAC-SpellQueue",      true)
local SpellDB          = LibStub("JustAC-SpellDB",         true)

if not BlizzardAPI or not UIAnimations or not UIRenderer then return end

local GetTime            = GetTime
local pcall              = pcall
local wipe               = wipe
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack      = UnitCanAttack
local UnitHealth         = UnitHealth
local UnitHealthMax      = UnitHealthMax
local UnitExists         = UnitExists
local UnitIsDead         = UnitIsDead
local math_max           = math.max
local math_min           = math.min
local math_floor         = math.floor
local ipairs             = ipairs
local C_NamePlate        = C_NamePlate ---@diagnostic disable-line: undefined-global
local GetCVar            = GetCVar
local SetCVar            = SetCVar

-- Layout constants
local ICON_SPACING   = 2   -- px between successive icons in the cluster
local NAMEPLATE_GAP  = 2   -- px between nameplate edge and nearest element
local BAR_HEIGHT     = 5   -- player health bar height (half of NamePlateConstants.SMALL_HEALTH_BAR_HEIGHT)
local BAR_SPACING    = 2   -- px between health bar and first DPS icon (matches Blizzard's 2px castBar→healthBar gap)

-- Cooldown update throttle (matches UIRenderer)
local lastCooldownUpdate       = 0
local COOLDOWN_UPDATE_INTERVAL = 0.08

-- Module state (reset by Destroy)
local dpsIcons         = {}   -- [1..N] DPS icon buttons
local defIcons         = {}   -- [1..N] defensive icon buttons
local healthBar        = nil  -- player health StatusBar
local petHealthBar     = nil  -- pet health StatusBar (warm yellow)
local currentNameplate = nil  -- nameplate frame we're currently anchored to
local savedCCAnchors   = nil  -- saved Blizzard CC frame anchors for restoration
local interruptIcon    = nil  -- single interrupt reminder icon ("position 0")
local savedNameplateShowEnemies = nil  -- original CVar value before we forced it on
local savedShowQuestUnitCircles = nil -- original CVar value before we suppressed quest indicators
local questIndicator   = nil  -- our replacement quest "!" texture on the nameplate
local interruptShown   = false -- whether interruptIcon is currently visible (controls anchor chain)
local resolvedInterrupts = nil -- ordered array of known interrupt spell IDs (resolved at Create)
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local UnitIsQuestBoss  = UnitIsQuestBoss ---@diagnostic disable-line: undefined-global

-- Cached anchor params (set in AnchorToNameplate, used in Render for dynamic re-anchor)
local anchorState = {}  -- { dpsPt, dpsEdge, dpsGapX, expansion, chainPt, chainRelPt, chainOffX, chainOffY, iconSpacing }

-- ─────────────────────────────────────────────────────────────────────────────
-- Icon button factory
-- Produces a button compatible with:
--   • UIRenderer.UpdateButtonCooldowns  (cooldowns)
--   • UIRenderer.ShowDefensiveIcon      (defensive display)
--   • UIAnimations glow/flash functions (proc / assisted / defensive glows)
--   • JustAC:CreateKeyPressDetector     (key-press flash via normalizedHotkey)
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateOverlayIcon(iconSize, profile)
    local button = CreateFrame("Button", nil, UIParent)
    button:SetSize(iconSize, iconSize)
    button:EnableMouse(false)   -- always click-through; no tooltip, no drag

    -- Slot background (Blizzard depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground

    -- Spell icon texture
    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    iconTexture:Hide()
    button.iconTexture = iconTexture

    -- Bevelled corner mask
    local maskPadding = math_floor(iconSize * 0.17)
    local iconMask = button:CreateMaskTexture(nil, "ARTWORK")
    iconMask:SetPoint("TOPLEFT",     button, "TOPLEFT",     -maskPadding,  maskPadding)
    iconMask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",  maskPadding, -maskPadding)
    iconMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
    iconTexture:AddMaskTexture(iconMask)
    slotBackground:AddMaskTexture(iconMask)

    -- Flash overlay for key-press feedback (used by UIAnimations.StartFlash)
    local flashFrame = CreateFrame("Frame", nil, button)
    flashFrame:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    flashFrame:SetSize(iconSize + 2, iconSize + 2)
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 6)
    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetVertexColor(1.5, 1.2, 0.3, 1.0)
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()
    button.Flash     = flashTexture
    button.FlashFrame = flashFrame
    button.flashing  = 0
    button.flashtime = 0

    -- Cooldown container (clips swipe to button bounds)
    local cooldownContainer = CreateFrame("Frame", nil, button)
    cooldownContainer:SetAllPoints(button)
    cooldownContainer:SetClipsChildren(true)

    -- Main cooldown (spell CD / GCD)
    local cooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    cooldown:ClearAllPoints()   -- CooldownFrameTemplate uses setAllPoints="true"; clear before insetting
    cooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      3, -3)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3,  3)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)   -- BlingTexture renders outside frame bounds
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)
    cooldown:Clear()
    cooldown:Hide()
    button.cooldown = cooldown
    -- Store cooldown text region for ApplyTextOverlaySettings and per-frame show/hide
    local cooldownText = cooldown:GetRegions()
    button.cooldownText = (cooldownText and cooldownText.SetFont) and cooldownText or nil

    -- Charge cooldown (multi-charge recharge)
    local chargeCooldown = CreateFrame("Cooldown", nil, cooldownContainer, "CooldownFrameTemplate")
    chargeCooldown:ClearAllPoints()
    chargeCooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      3, -3)
    chargeCooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3,  3)
    -- Blizzard 12.0: charge cooldowns use edge ring only (drawSwipe="false" in XML).
    -- Swipe is a filled dark polygon that can bleed; edge ring is a thin border that stays contained.
    chargeCooldown:SetDrawSwipe(false)
    chargeCooldown:SetDrawEdge(true)
    chargeCooldown:SetDrawBling(false)
    chargeCooldown:SetHideCountdownNumbers(true)
    chargeCooldown:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    chargeCooldown:Clear()
    chargeCooldown:Hide()
    button.chargeCooldown = chargeCooldown

    -- Border frame: sits above cooldowns (L+3) so its opaque edges cover swipe corner overflow.
    -- Mirrors the same fix applied to CreateBaseIcon in UIFrameFactory.
    local borderFrame = CreateFrame("Frame", nil, button)
    borderFrame:SetFrameLevel(button:GetFrameLevel() + 3)
    borderFrame:SetAllPoints(button)
    local normalTexture = borderFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    normalTexture:SetPoint("CENTER", button, "CENTER", 0.5, -0.5)
    normalTexture:SetSize(iconSize, iconSize)
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    button.borderFrame   = borderFrame

    -- Hotkey text (top-right corner; display controlled by showHotkey setting)
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)
    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    hotkeyText:SetFont(STANDARD_TEXT_FONT, math_max(8, math_floor(iconSize * 0.4)), "OUTLINE")
    hotkeyText:SetTextColor(1, 1, 1, 1)
    hotkeyText:SetJustifyH("RIGHT")
    hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -3, -3)
    button.hotkeyFrame = hotkeyFrame
    button.hotkeyText = hotkeyText

    -- Charge count text (bottom-right; required by UpdateButtonCooldowns)
    local chargeText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    chargeText:SetFont(STANDARD_TEXT_FONT, math_max(8, math_floor(iconSize * 0.26)), "OUTLINE")
    chargeText:SetTextColor(1, 1, 1, 1)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    chargeText:SetText("")
    chargeText:Hide()
    button.chargeText = chargeText

    -- Fade-in / fade-out animations (required by UIRenderer.ShowDefensiveIcon /
    -- HideDefensiveIcon; gracefully skipped if nil, but present for full parity)
    local fadeIn      = button:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.15)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function()
        -- Clamp to target opacity after fade-in completes (opacity < 1 support)
        local targetAlpha = button.overlayOpacity or 1
        if targetAlpha < 1 then button:SetAlpha(targetAlpha) end
    end)
    button.fadeIn = fadeIn

    local fadeOut      = button:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        button:Hide()
        button:SetAlpha(0)
    end)
    button.fadeOut = fadeOut

    -- State fields expected by UIRenderer.UpdateButtonCooldowns
    button.spellID              = nil
    button.itemID               = nil
    button.isItem               = nil
    button.currentID            = nil
    button._cooldownShown       = false
    button._chargeCooldownShown = false
    button._cachedMaxCharges    = nil

    -- Opacity support (set before ShowDefensiveIcon to drive OnFinished clamp)
    button.overlayOpacity = 1

    -- Hotkey tracking for CreateKeyPressDetector flash
    button.normalizedHotkey         = nil
    button.previousNormalizedHotkey = nil
    button.hotkeyChangeTime         = nil
    button.spellChangeTime          = nil
    button.cachedHotkey             = nil

    -- Glow state flags
    button.hasAssistedGlow    = false
    button.hasInterruptGlow   = false
    button.hasProcGlow        = false
    button.hasGapCloserGlow   = false
    button.hasDefensiveGlow   = false

    button:SetAlpha(0)
    button:Hide()

    -- Apply central text overlay settings with overlay-specific fontScale
    if UIFrameFactory and UIFrameFactory.ApplyTextOverlaySettings then
        local mergedOverlays = UIFrameFactory.MergeOverlayTextOverlays(profile)
        UIFrameFactory.ApplyTextOverlaySettings(button, iconSize, mergedOverlays)
    end

    return button
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Player health bar factory
-- Simple StatusBar; colour updates in UpdateHealthBar().
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateOverlayHealthBar(initialWidth)
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetSize(initialWidth, BAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0.0, 0.80, 0.0, 0.9)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:EnableMouse(false)

    -- Bright red background so lost health is immediately visible.
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.8, 0.1, 0.1, 0.9)
    bar.bg = bg

    -- Horizontal bevel strips (4-strip symmetric tube).
    -- Shown when orientation is HORIZONTAL, hidden when VERTICAL.
    local shBot1 = bar:CreateTexture(nil, "OVERLAY")
    shBot1:SetTexture("Interface\\Buttons\\WHITE8X8")
    shBot1:SetVertexColor(0, 0, 0, 0.35)
    shBot1:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    shBot1:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    shBot1:SetHeight(1)
    shBot1:Hide()

    local shBot2 = bar:CreateTexture(nil, "OVERLAY")
    shBot2:SetTexture("Interface\\Buttons\\WHITE8X8")
    shBot2:SetVertexColor(0, 0, 0, 0.16)
    shBot2:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 1)
    shBot2:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 1)
    shBot2:SetHeight(1)
    shBot2:Hide()

    local shTop1 = bar:CreateTexture(nil, "OVERLAY")
    shTop1:SetTexture("Interface\\Buttons\\WHITE8X8")
    shTop1:SetVertexColor(0, 0, 0, 0.16)
    shTop1:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, -1)
    shTop1:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -1)
    shTop1:SetHeight(1)
    shTop1:Hide()

    local shTop2 = bar:CreateTexture(nil, "OVERLAY")
    shTop2:SetTexture("Interface\\Buttons\\WHITE8X8")
    shTop2:SetVertexColor(0, 0, 0, 0.35)
    shTop2:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    shTop2:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    shTop2:SetHeight(1)
    shTop2:Hide()

    bar.hBevelStrips = { shBot1, shBot2, shTop1, shTop2 }

    -- Vertical bevel strips (symmetric, same alphas as horizontal).
    -- Shown when orientation is VERTICAL, hidden when HORIZONTAL.
    local shL1 = bar:CreateTexture(nil, "OVERLAY")
    shL1:SetTexture("Interface\\Buttons\\WHITE8X8")
    shL1:SetVertexColor(0, 0, 0, 0.35)
    shL1:SetPoint("TOPLEFT",    bar, "TOPLEFT",    0, 0)
    shL1:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    shL1:SetWidth(1)
    shL1:Hide()

    local shL2 = bar:CreateTexture(nil, "OVERLAY")
    shL2:SetTexture("Interface\\Buttons\\WHITE8X8")
    shL2:SetVertexColor(0, 0, 0, 0.16)
    shL2:SetPoint("TOPLEFT",    bar, "TOPLEFT",    1, 0)
    shL2:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 0)
    shL2:SetWidth(1)
    shL2:Hide()

    local shR1 = bar:CreateTexture(nil, "OVERLAY")
    shR1:SetTexture("Interface\\Buttons\\WHITE8X8")
    shR1:SetVertexColor(0, 0, 0, 0.16)
    shR1:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    -1, 0)
    shR1:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    shR1:SetWidth(1)
    shR1:Hide()

    local shR2 = bar:CreateTexture(nil, "OVERLAY")
    shR2:SetTexture("Interface\\Buttons\\WHITE8X8")
    shR2:SetVertexColor(0, 0, 0, 0.35)
    shR2:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    0, 0)
    shR2:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    shR2:SetWidth(1)
    shR2:Hide()

    bar.bevelStrips = { shL1, shL2, shR1, shR2 }

    bar:SetAlpha(0)
    bar:Hide()
    return bar
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CC frame displacement
-- Blizzard's CrowdControlListFrame and LossOfControlFrame anchor to the RIGHT
-- side of the health bar, which overlaps with our icon clusters when they sit
-- on that same side.  We save their original anchors, re-anchor them relative
-- to our icons, and restore the originals on detach / destroy.
-- ─────────────────────────────────────────────────────────────────────────────
local CC_GAP = 4  -- px between our icons and displaced CC frames
local BLIZZARD_AURA_HEIGHT = 25   -- NamePlateConstants.AURA_ITEM_HEIGHT
local BLIZZARD_LOC_SIZE    = 30   -- LossOfControlFrame default size (30×30)

-- Blizzard's default CC anchor from Blizzard_NamePlates.xml:
--   <Anchor point="LEFT" relativeKey="$parent.$parent.HealthBarsContainer.healthBar" relativePoint="RIGHT" x="5"/>
-- We hardcode the restore instead of saving/restoring dynamically, because
-- GetNumPoints() / GetPoint() return secret values on restricted nameplate
-- frames in combat (causes "Can't measure restricted regions" taint errors).
local function RestoreBlizzardCCAnchor(frame, healthBar)
    if not frame or not healthBar then return end
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", healthBar, "RIGHT", 5, 0)
        frame:SetScale(1)
    end)
end

--- Restore all displaced CC frames to their original Blizzard anchoring.
local function RestoreCCFrames()
    if not savedCCAnchors then return end
    local healthBar = savedCCAnchors.healthBar
    if savedCCAnchors.ccList then
        RestoreBlizzardCCAnchor(savedCCAnchors.ccList, healthBar)
    end
    if savedCCAnchors.locFrame then
        RestoreBlizzardCCAnchor(savedCCAnchors.locFrame, healthBar)
    end
    savedCCAnchors = nil
end

--- Save original CC anchors and re-anchor relative to our icon cluster.
--- Always displaces (both default and reversed anchors have a cluster on the right).
--- Scales CC frames to match our icon size and center-aligns with our queue.
--- Horizontal ("out"): CC moves ABOVE the right-side cluster (above health bar if present).
--- Vertical ("up"/"down"): CC moves to the RIGHT of the right-side cluster (past health bar if present).
local function DisplaceCCFrames(nameplate, anchor, expansion, showDefensives, showHealthBar, iconSize)
    -- Always restore previous displacement first
    RestoreCCFrames()

    local uf = nameplate and nameplate.UnitFrame
    local af = uf and uf.AurasFrame
    if not af then return end

    local ccList   = af.CrowdControlListFrame
    local locFrame = af.LossOfControlFrame
    if not ccList and not locFrame then return end

    -- Determine which icon set occupies the RIGHT side (where CC naturally lives).
    -- anchor="RIGHT" (default)  → DPS is RIGHT, DEF is LEFT  → DPS overlaps CC
    -- anchor="LEFT"  (reversed) → DPS is LEFT,  DEF is RIGHT → DEF overlaps CC (+ health bar)
    local isLeft = (anchor == "LEFT")
    local rightIcons, rightHasHealthBar
    if isLeft then
        -- Reversed: defensive cluster is on the right
        rightIcons = showDefensives and #defIcons > 0 and defIcons or nil
        -- Health bar sits above defensive icons in horizontal, beside them in vertical
        rightHasHealthBar = showHealthBar and showDefensives and healthBar ~= nil
    else
        -- Default: DPS cluster is on the right (no health bar on DPS side)
        rightIcons = #dpsIcons > 0 and dpsIcons or nil
        rightHasHealthBar = false
    end
    if not rightIcons then return end  -- nothing on the right side → no overlap

    -- Track which frames we displaced + the Blizzard healthBar for restoration
    -- (Blizzard's HealthBarsContainer.healthBar is the restore anchor target)
    local npHealthBar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    savedCCAnchors = { healthBar = npHealthBar }
    if ccList   then savedCCAnchors.ccList   = ccList   end
    if locFrame then savedCCAnchors.locFrame = locFrame end

    -- The topmost frame our CC should sit above / beside:
    -- If the right-side cluster has a health bar, CC goes above/beside the bar;
    -- otherwise CC goes above/beside the first icon.
    local topAnchorFrame = (rightHasHealthBar and healthBar) or rightIcons[1]

    -- pcall all anchor/scale mutations — CC frames may be restricted in some
    -- combat contexts (e.g., arena) and ClearAllPoints/SetPoint could taint.
    --
    -- Scale: match CC icon visual size to our queue's iconSize.
    --   CrowdControlListFrame children are individually scaled by auraItemScale
    --   (applied per-child in NamePlateAurasMixin), so the parent frame needs:
    --     parentScale = iconSize / (AURA_ITEM_HEIGHT * auraItemScale)
    --   LossOfControlFrame is a simple 30×30 container, scale = iconSize / 30.
    -- Position: center-aligned with queue icons rather than edge-aligned.
    iconSize = iconSize or 26
    local auraItemScale = af.auraItemScale or 1
    local ccScale  = iconSize / (BLIZZARD_AURA_HEIGHT * auraItemScale)
    local locScale = iconSize / BLIZZARD_LOC_SIZE

    local ok, err = pcall(function()
        if expansion == "out" then
            -- Horizontal row: CC goes ABOVE the cluster, centered on first icon
            if ccList then
                ccList:ClearAllPoints()
                ccList:SetScale(ccScale)
                ccList:SetPoint("BOTTOM", topAnchorFrame, "TOP", 0, CC_GAP)
            end
            if locFrame then
                locFrame:ClearAllPoints()
                locFrame:SetScale(locScale)
                if ccList then
                    locFrame:SetPoint("BOTTOM", ccList, "TOP", 0, 2)
                else
                    locFrame:SetPoint("BOTTOM", topAnchorFrame, "TOP", 0, CC_GAP)
                end
            end
        else
            -- Vertical column ("up"/"down"): CC goes to the RIGHT, vertically
            -- centered on the first icon.
            if ccList then
                ccList:ClearAllPoints()
                ccList:SetScale(ccScale)
                if rightHasHealthBar and healthBar then
                    ccList:SetPoint("LEFT", healthBar, "RIGHT", CC_GAP, 0)
                else
                    ccList:SetPoint("LEFT", rightIcons[1], "RIGHT", CC_GAP, 0)
                end
            end
            if locFrame then
                locFrame:ClearAllPoints()
                locFrame:SetScale(locScale)
                if ccList then
                    locFrame:SetPoint("LEFT", ccList, "RIGHT", 2, 0)
                elseif rightHasHealthBar and healthBar then
                    locFrame:SetPoint("LEFT", healthBar, "RIGHT", CC_GAP, 0)
                else
                    locFrame:SetPoint("LEFT", rightIcons[1], "RIGHT", CC_GAP, 0)
                end
            end
        end
    end)

    if not ok then
        -- Displacement failed (restricted frame) — clean up and skip
        savedCCAnchors = nil
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: SetPoint all cluster elements to a live nameplate frame.
-- Uses a chain-anchor approach:
--   ROOT elements (healthBar, dpsIcons[1], defIcons[1]) anchor to the nameplate.
--   Subsequent icons in each cluster chain off the previous icon.
-- When the nameplate moves, the entire cluster follows automatically.
-- Health bar (when shown) floats above the nameplate for all anchor directions.
-- ─────────────────────────────────────────────────────────────────────────────
local function AnchorToNameplate(nameplate, anchor, iconSize, showHealthBar, showDefensives, expansion, iconSpacing)
    -- anchor:            "LEFT" or "RIGHT" — which side of the nameplate
    -- expansion:         "out" (horizontal, current), "up" (vertical upward), "down" (vertical downward)
    -- iconSpacing:       px between successive icons (defaults to ICON_SPACING constant)
    expansion         = expansion or "out"
    iconSpacing       = iconSpacing or ICON_SPACING

    local isLeft    = (anchor == "LEFT")
    -- Point on the icon that touches the nameplate / previous icon
    local dpsPt     = isLeft and "RIGHT" or "LEFT"
    local defPt     = isLeft and "LEFT"  or "RIGHT"
    -- Nameplate edge each cluster attaches to
    local dpsEdge   = isLeft and "LEFT"  or "RIGHT"
    local defEdge   = isLeft and "RIGHT" or "LEFT"
    -- X offset from the nameplate edge (including gap)
    local dpsGapX   = isLeft and -NAMEPLATE_GAP or  NAMEPLATE_GAP
    local defGapX   = isLeft and  NAMEPLATE_GAP or -NAMEPLATE_GAP
    -- X offset for horizontal chaining between icons
    local dpsChainX = isLeft and -iconSpacing or  iconSpacing
    local defChainX = isLeft and  iconSpacing or -iconSpacing

    -- Chain anchor params for icons after the first (icon 1 always anchors to nameplate).
    -- "out" uses opposite-edge horizontal chaining; "up"/"down" use vertical chaining.
    local chainPt, chainRelPt, chainOffX, chainOffY
    if expansion == "up" then
        chainPt, chainRelPt, chainOffX, chainOffY = "BOTTOM", "TOP", 0,  iconSpacing
    elseif expansion == "down" then
        chainPt, chainRelPt, chainOffX, chainOffY = "TOP", "BOTTOM",  0, -iconSpacing
    end

    -- Helper: anchor one icon array to the nameplate then chain-anchor subsequent icons.
    -- Closes over nameplate, expansion, and the chain params computed above.
    local function AnchorRow(icons, firstPt, firstEdge, firstGapX, outChainPt, outChainEdge, outChainX)
        for i, icon in ipairs(icons) do
            icon:ClearAllPoints()
            if i == 1 then
                icon:SetPoint(firstPt, nameplate, firstEdge, firstGapX, 0)
            elseif expansion == "out" then
                icon:SetPoint(outChainPt, icons[i-1], outChainEdge, outChainX, 0)
            else
                icon:SetPoint(chainPt, icons[i-1], chainRelPt, chainOffX, chainOffY)
            end
        end
    end

    AnchorRow(dpsIcons, dpsPt, dpsEdge, dpsGapX, dpsPt, dpsEdge, dpsChainX)
    if showDefensives then
        AnchorRow(defIcons, defPt, defEdge, defGapX, defPt, defEdge, defChainX)
    end

    -- Interrupt icon: inline "position 0" — sits between icon 1 and the
    -- nameplate edge (the leading direction, opposite queue growth).  Icon 1
    -- anchors directly to the nameplate so it never shifts when the interrupt
    -- appears/hides.  Mirrors the standard queue's CreateInterruptIcon pattern
    -- where the interrupt "overhangs outside mainFrame".
    --   "out"       → inline toward nameplate (between icon 1 and nameplate edge)
    --   "up"/"down" → inline toward nameplate (below icon 1 for "up", above for "down")
    if interruptIcon then
        interruptIcon:ClearAllPoints()
        interruptIcon:SetSize(iconSize, iconSize)
        if #dpsIcons > 0 then
            if expansion == "out" then
                -- Horizontal queue → interrupt inline, between icon 1 and nameplate
                interruptIcon:SetPoint(dpsEdge, dpsIcons[1], dpsPt, -dpsChainX, 0)
            else
                -- Vertical queue → interrupt inline before icon 1 in chain direction
                -- (below icon 1 for "up", above icon 1 for "down")
                interruptIcon:SetPoint(chainRelPt, dpsIcons[1], chainPt, -chainOffX, -chainOffY)
            end
        else
            -- Fallback: no DPS icons, anchor to nameplate directly
            interruptIcon:SetPoint(dpsPt, nameplate, dpsEdge, dpsGapX, 0)
        end
        -- Re-anchor cast aura based on expansion: the aura sits on the side
        -- of the interrupt facing away from the queue (perpendicular pop-out).
        --   "out"/"down" → above interrupt
        --   "up"         → below interrupt (away from upward-growing queue)
        if interruptIcon.castAura then
            interruptIcon.castAura:ClearAllPoints()
            if expansion == "up" then
                interruptIcon.castAura:SetPoint("TOP", interruptIcon, "BOTTOM", 0, -2)
            else
                interruptIcon.castAura:SetPoint("BOTTOM", interruptIcon, "TOP", 0, 2)
            end
        end
        interruptIcon:Hide()
        interruptShown = false
    end

    -- Cache anchor params for dynamic re-anchor in Render()
    anchorState.dpsPt      = dpsPt
    anchorState.dpsEdge    = dpsEdge
    anchorState.dpsGapX    = dpsGapX
    anchorState.dpsChainX  = dpsChainX
    anchorState.expansion  = expansion
    anchorState.chainPt    = chainPt
    anchorState.chainRelPt = chainRelPt
    anchorState.chainOffX  = chainOffX
    anchorState.chainOffY  = chainOffY
    anchorState.iconSpacing = iconSpacing
    if showDefensives then
        AnchorRow(defIcons, defPt, defEdge, defGapX, defPt, defEdge, defChainX)
    end

    -- Health bar placeholder anchor. RenderDefensives re-anchors with correct
    -- size, inset, and position once visibleCount is known.
    if healthBar then
        healthBar:ClearAllPoints()
        if showHealthBar and showDefensives and #defIcons > 0 then
            if isLeft then
                healthBar:SetPoint("BOTTOMLEFT", defIcons[1], "TOPLEFT", 0, BAR_SPACING)
            else
                healthBar:SetPoint("BOTTOMRIGHT", defIcons[1], "TOPRIGHT", 0, BAR_SPACING)
            end
            healthBar:SetSize(iconSize, BAR_HEIGHT)
        else
            healthBar:Hide()
        end
    end

    -- Pet health bar placeholder anchor. RenderDefensives re-anchors properly.
    if petHealthBar then
        petHealthBar:ClearAllPoints()
        if showHealthBar and showDefensives and #defIcons > 0 then
            -- Stack beyond the player health bar
            local petAnchor = healthBar or defIcons[1]
            local petSpacing = healthBar and BAR_SPACING or BAR_SPACING
            if isLeft then
                petHealthBar:SetPoint("BOTTOMLEFT", petAnchor, "TOPLEFT", 0, petSpacing)
            else
                petHealthBar:SetPoint("BOTTOMRIGHT", petAnchor, "TOPRIGHT", 0, petSpacing)
            end
            petHealthBar:SetSize(iconSize, BAR_HEIGHT)
        else
            petHealthBar:Hide()
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--- Build all icon buttons and the optional health bar.
--- Called from JustAC:OnEnable() and after settings changes.
function UINameplateOverlay.Create(addon)
    if not addon then return end
    local profile = addon:GetProfile()
    if not profile or not profile.nameplateOverlay then return end
    local npo = profile.nameplateOverlay
    local displayMode = profile.displayMode or "queue"
    if displayMode ~= "overlay" and displayMode ~= "both" then return end

    UINameplateOverlay.Destroy(addon)   -- clean slate

    -- Force-enable enemy nameplates so the overlay has a frame to anchor to.
    -- Save the user's original CVar only on the first Create (not on Destroy→Create
    -- rebuilds, where savedNameplateShowEnemies is already populated).
    if savedNameplateShowEnemies == nil then
        savedNameplateShowEnemies = GetCVar("nameplateShowEnemies")
    end
    if GetCVar("nameplateShowEnemies") ~= "1" then
        SetCVar("nameplateShowEnemies", "1")
    end

    local iconSize = npo.iconSize or 26
    local maxDPS   = math_min(npo.maxIcons or 1, 5)
    local maxDef   = npo.showDefensives and math_min(npo.maxDefensiveIcons or 1, 5) or 0

    for i = 1, maxDPS do dpsIcons[i] = CreateOverlayIcon(iconSize, profile) end
    for i = 1, maxDef do defIcons[i] = CreateOverlayIcon(iconSize, profile) end

    -- Interrupt reminder icon (position 0, hidden until interruptible cast detected)
    -- interruptMode is centralized in profile (no longer per-surface)
    local interruptMode = profile.interruptMode or "ccPrefer"
    if interruptMode ~= "disabled" and interruptMode ~= "off" then
        interruptIcon = CreateOverlayIcon(iconSize, profile)
        resolvedInterrupts = SpellDB.ResolveInterruptSpells()

        -- Cast aura: small icon attached to the interrupt button showing what
        -- the enemy is casting.  Anchors above or below the interrupt icon
        -- depending on expansion direction (same direction the interrupt pops).
        local auraSize = math_floor(iconSize * 0.7)
        local castAura = CreateFrame("Frame", nil, interruptIcon)
        castAura:SetSize(auraSize, auraSize)
        castAura:SetFrameLevel(interruptIcon:GetFrameLevel() + 2)
        castAura:EnableMouse(false)

        -- Aura always sits above the interrupt icon for visual consistency
        -- regardless of queue orientation or anchor side.
        castAura:SetPoint("BOTTOM", interruptIcon, "TOP", 0, 2)

        local auraIcon = castAura:CreateTexture(nil, "ARTWORK")
        auraIcon:SetAllPoints(castAura)
        castAura.iconTexture = auraIcon

        local auraMaskPadding = math_floor(auraSize * 0.17)
        local auraMask = castAura:CreateMaskTexture(nil, "ARTWORK")
        auraMask:SetPoint("TOPLEFT",     castAura, "TOPLEFT",     -auraMaskPadding,  auraMaskPadding)
        auraMask:SetPoint("BOTTOMRIGHT", castAura, "BOTTOMRIGHT",  auraMaskPadding, -auraMaskPadding)
        auraMask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask", false)
        auraIcon:AddMaskTexture(auraMask)

        local auraBorder = castAura:CreateTexture(nil, "OVERLAY")
        auraBorder:SetPoint("CENTER", castAura, "CENTER", 0.5, -0.5)
        auraBorder:SetSize(auraSize, auraSize)
        auraBorder:SetAtlas("UI-HUD-ActionBar-IconFrame")

        castAura:Hide()
        interruptIcon.castAura = castAura
    end

    if npo.showHealthBar then
        healthBar = CreateOverlayHealthBar(iconSize * 2)
        -- Pet health bar: warm yellow, only visible when pet exists
        petHealthBar = CreateOverlayHealthBar(iconSize * 2)
        petHealthBar:SetStatusBarColor(0.90, 0.75, 0.10, 0.9)
    end

    -- Quest indicator replacement: suppress engine-rendered quest circles and
    -- render our own "!" icon on the nameplate.  Our version is positioned so
    -- it cannot overlap the icon queue.
    if npo.replaceQuestIndicator ~= false then
        if savedShowQuestUnitCircles == nil then
            savedShowQuestUnitCircles = GetCVar("ShowQuestUnitCircles")
        end
        if GetCVar("ShowQuestUnitCircles") ~= "0" then
            SetCVar("ShowQuestUnitCircles", "0")
        end
        -- Create the replacement texture (hidden until UpdateAnchor detects a quest mob)
        local qSize = math_floor(iconSize * 0.65)
        questIndicator = CreateFrame("Frame", nil, UIParent)
        questIndicator:SetSize(qSize, qSize)
        questIndicator:SetFrameStrata("HIGH")
        questIndicator:EnableMouse(false)
        local qTex = questIndicator:CreateTexture(nil, "ARTWORK")
        qTex:SetAllPoints(questIndicator)
        qTex:SetAtlas("QuestNormal", false)
        questIndicator.texture = qTex
        questIndicator:Hide()
    end

    addon.nameplateIcons    = dpsIcons
    addon.nameplateDefIcons = defIcons

    UINameplateOverlay.UpdateAnchor(addon)
    -- Re-render immediately so icons appear without waiting for a health event or re-target.
    addon:ForceUpdateAll()
end

--- Tear down all overlay frames.
--- Called before rebuilding (settings change) or on addon disable.
function UINameplateOverlay.Destroy(addon)
    local function CleanIcon(icon)
        if UIAnimations then
            if icon.hasAssistedGlow  then UIAnimations.StopAssistedGlow(icon)  end
            if icon.hasDefensiveGlow then UIAnimations.StopDefensiveGlow(icon) end
            if icon.hasProcGlow      then UIAnimations.HideProcGlow(icon)      end
        end
        icon:ClearAllPoints()
        icon:Hide()
        icon:SetParent(nil)
    end

    for _, icon in ipairs(dpsIcons) do CleanIcon(icon) end
    for _, icon in ipairs(defIcons) do CleanIcon(icon) end

    if interruptIcon then
        CleanIcon(interruptIcon)
        interruptIcon = nil
    end
    interruptShown = false
    resolvedInterrupts = nil
    wipe(anchorState)

    if healthBar then
        healthBar:ClearAllPoints()
        healthBar:Hide()
        healthBar:SetParent(nil)
        healthBar = nil
    end
    if petHealthBar then
        petHealthBar:ClearAllPoints()
        petHealthBar:Hide()
        petHealthBar:SetParent(nil)
        petHealthBar = nil
    end

    RestoreCCFrames()  -- restore Blizzard CC frame anchors before wiping state

    -- Clean up quest indicator
    if questIndicator then
        questIndicator:ClearAllPoints()
        questIndicator:Hide()
        questIndicator:SetParent(nil)
        questIndicator = nil
    end

    wipe(dpsIcons)
    wipe(defIcons)
    currentNameplate = nil

    -- Restore the user's original nameplateShowEnemies CVar.
    -- Only restore when we actually saved a value (Create was called).
    if savedNameplateShowEnemies ~= nil then
        if GetCVar("nameplateShowEnemies") ~= savedNameplateShowEnemies then
            SetCVar("nameplateShowEnemies", savedNameplateShowEnemies)
        end
        savedNameplateShowEnemies = nil
    end

    -- Restore the user's original ShowQuestUnitCircles CVar.
    if savedShowQuestUnitCircles ~= nil then
        if GetCVar("ShowQuestUnitCircles") ~= savedShowQuestUnitCircles then
            SetCVar("ShowQuestUnitCircles", savedShowQuestUnitCircles)
        end
        savedShowQuestUnitCircles = nil
    end

    if addon then
        addon.nameplateIcons    = nil
        addon.nameplateDefIcons = nil
    end
end

--- Re-anchor the entire cluster to the current target's nameplate.
--- Called on PLAYER_TARGET_CHANGED, NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED.
--- No InCombatLockdown() guard: nameplates are non-secure frames.
function UINameplateOverlay.UpdateAnchor(addon)
    if not addon then return end
    local profile = addon:GetProfile()
    if not profile or not profile.nameplateOverlay then return end
    local npo = profile.nameplateOverlay
    local displayMode = profile.displayMode or "queue"
    if displayMode ~= "overlay" and displayMode ~= "both" then return end
    if #dpsIcons == 0 then return end

    -- Only show overlay on targets the player can actually attack (excludes
    -- friendly players, friendly/neutral NPCs, and non-damageable units)
    local nameplate = UnitCanAttack("player", "target") and C_NamePlate.GetNamePlateForUnit("target", false) or nil
    if nameplate then
        currentNameplate = nameplate
        local anchor       = npo.reverseAnchor and "LEFT" or "RIGHT"
        local iconSize     = npo.iconSize or 26
        -- Health bar is tied to the defensive queue: only show when defensives are enabled
        local showDefensives = npo.showDefensives
        local showHealthBar  = npo.showHealthBar and showDefensives

        local expansion         = npo.expansion or "out"
        AnchorToNameplate(nameplate, anchor, iconSize, showHealthBar, showDefensives, expansion, npo.iconSpacing or ICON_SPACING)
        -- Displace Blizzard CC frames so they don't overlap our icon cluster
        DisplaceCCFrames(nameplate, anchor, expansion, showDefensives, showHealthBar, iconSize)
        -- Individual icons become visible when Render() / RenderDefensives() fills them

        -- Quest indicator: show our replacement "!" on quest-relevant targets.
        -- Anchored ABOVE the nameplate center so it never collides with our side-anchored queue.
        if questIndicator then
            questIndicator:ClearAllPoints()
            local isQuest = UnitIsQuestBoss and UnitIsQuestBoss("target")
            if isQuest then
                questIndicator:SetParent(nameplate)
                questIndicator:SetPoint("BOTTOM", nameplate, "TOP", 0, 2)
                questIndicator:Show()
            else
                questIndicator:Hide()
            end
        end
    else
        currentNameplate = nil
        RestoreCCFrames()  -- put CC frames back when we detach

        -- Hide quest indicator when no valid nameplate
        if questIndicator then
            questIndicator:ClearAllPoints()
            questIndicator:Hide()
        end

        -- Detach and hide every element
        for _, icon in ipairs(dpsIcons) do
            if UIAnimations then
                if icon.hasAssistedGlow    then UIAnimations.StopAssistedGlow(icon);    icon.hasAssistedGlow    = false end
                if icon.hasProcGlow        then UIAnimations.HideProcGlow(icon);        icon.hasProcGlow        = false end
                if icon.hasGapCloserGlow   then UIAnimations.StopGapCloserGlow(icon);   icon.hasGapCloserGlow   = false end
            end
            icon:ClearAllPoints()
            icon:Hide()
        end
        for _, icon in ipairs(defIcons) do
            if UIAnimations then
                if icon.hasDefensiveGlow then UIAnimations.StopDefensiveGlow(icon); icon.hasDefensiveGlow = false end
                if icon.hasProcGlow      then UIAnimations.HideProcGlow(icon);      icon.hasProcGlow      = false end
            end
            icon:ClearAllPoints()
            icon:Hide()
        end
        if healthBar then
            healthBar:ClearAllPoints()
            healthBar:Hide()
        end
        if petHealthBar then
            petHealthBar:ClearAllPoints()
            petHealthBar:Hide()
        end
        if interruptIcon then
            if UIAnimations then
                if interruptIcon.hasInterruptGlow then UIAnimations.StopInterruptGlow(interruptIcon); interruptIcon.hasInterruptGlow = false end
                if interruptIcon.hasProcGlow     then UIAnimations.HideProcGlow(interruptIcon);       interruptIcon.hasProcGlow      = false end
            end
            interruptIcon:ClearAllPoints()
            interruptIcon:Hide()
            interruptShown = false
        end
    end
end

--- Update DPS icon textures, cooldowns, glows, and hotkey tracking.
--- Called from JustAC:UpdateSpellQueue() with the same spellIDs array
--- already passed to UIRenderer.RenderSpellQueue — zero extra queue cost.
function UINameplateOverlay.Render(addon, spellIDs)
    if not currentNameplate then return end
    if not addon then return end
    local profile = addon:GetProfile()
    if not profile or not profile.nameplateOverlay then return end
    local npo = profile.nameplateOverlay
    local displayMode = profile.displayMode or "queue"
    if displayMode ~= "overlay" and displayMode ~= "both" then return end
    if #dpsIcons == 0 then return end

    local hasSpells   = spellIDs and #spellIDs > 0
    local npoGlowMode  = npo.glowMode or "all"
    local npoShowProcGlow = (npoGlowMode == "all" or npoGlowMode == "procOnly")
    local showGapCloserGlow = profile.gapClosers and profile.gapClosers.showGlow == true
    local centralOverlays = profile.textOverlays
    local showHotkey   = not centralOverlays or not centralOverlays.hotkey or centralOverlays.hotkey.show ~= false
    local opacity      = npo.opacity or 1.0
    local now        = GetTime()
    local shouldUpdateCooldowns = (now - lastCooldownUpdate) >= COOLDOWN_UPDATE_INTERVAL
    if shouldUpdateCooldowns then lastCooldownUpdate = now end
    local inCombat = UnitAffectingCombat("player")

    local GetCachedSpellInfo = SpellQueue  and SpellQueue.GetCachedSpellInfo
    local IsSyntheticProc    = SpellQueue  and SpellQueue.IsSyntheticProc
    local IsSpellProcced_raw = BlizzardAPI and BlizzardAPI.IsSpellProcced
    local GetSpellHotkey     = ActionBarScanner and ActionBarScanner.GetSpellHotkey

    -- Check if player is channeling (grey out icons to emphasize not interrupting)
    -- PlayerChannelBarFrame is a visual frame — NeverSecret, avoids pcall for UnitChannelInfo
    local isChanneling = PlayerChannelBarFrame and PlayerChannelBarFrame:IsShown() or false

    -- ── Interrupt reminder (position 0) ─────────────────────────────────────
    -- Detect interruptible cast via the nameplate's cast bar frame state.
    -- Uses Icon:IsShown() for 12.0-safe interruptibility detection.
    -- interruptMode: centralized in profile (no longer per-surface)
    -- "disabled" | "kickOnly" | "ccPrefer"
    -- ("importantOnly" reserved for future — all important-cast signals are SECRET in 12.0)
    local npoInterruptMode = profile.interruptMode or "ccPrefer"
    -- Fallback: if saved data contains retired "importantOnly", treat as "kickOnly"
    if npoInterruptMode == "importantOnly" then npoInterruptMode = "kickOnly" end
    if interruptIcon and resolvedInterrupts and npoInterruptMode ~= "disabled" then
        -- Delegate to UIRenderer.EvaluateInterrupt() — single evaluation shared between
        -- RenderSpellQueue and UINameplateOverlay.Render so both renderers see identical
        -- interrupt state and share a single debounce timer (one player, one interrupt).
        local intResult           = UIRenderer.EvaluateInterrupt(resolvedInterrupts, npoInterruptMode, now)
        local shouldShowInterrupt = intResult.shouldShow
        local intSpellID          = intResult.spellID
        local castBar             = intResult.castBar

        -- De-dup: if the interrupt spell is already shown as overlay DPS position 1, skip it
        if shouldShowInterrupt and intSpellID and spellIDs and spellIDs[1] == intSpellID then
            shouldShowInterrupt = false
        end

        if shouldShowInterrupt and intSpellID then
            local spellChanged = (interruptIcon.spellID ~= intSpellID)
            if spellChanged then
                interruptIcon.spellID = intSpellID
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(intSpellID)
                if info and info.iconID then
                    interruptIcon.iconTexture:SetTexture(info.iconID)
                    interruptIcon.iconTexture:Show()
                end
                interruptIcon._cooldownShown       = false
                interruptIcon._chargeCooldownShown = false
                interruptIcon._cachedMaxCharges    = nil
                interruptIcon.cachedHotkey         = nil
            end

            -- Cooldowns
            if spellChanged or shouldUpdateCooldowns then
                UIRenderer.UpdateButtonCooldowns(interruptIcon)
            end

            -- Hotkey
            if spellChanged or shouldUpdateCooldowns or not interruptIcon.cachedHotkey then
                local hotkey = GetSpellHotkey and GetSpellHotkey(intSpellID) or ""
                interruptIcon.cachedHotkey = hotkey
                local displayHotkey = showHotkey and hotkey or ""
                if (interruptIcon.hotkeyText:GetText() or "") ~= displayHotkey then
                    interruptIcon.hotkeyText:SetText(displayHotkey)
                end
                if hotkey ~= "" then
                    interruptIcon.normalizedHotkey = UIRenderer.NormalizeHotkey and UIRenderer.NormalizeHotkey(hotkey) or nil
                else
                    interruptIcon.normalizedHotkey = nil
                end
            end

            -- Out-of-range: red hotkey text when target is beyond interrupt range
            if showHotkey and interruptIcon.cachedHotkey and interruptIcon.cachedHotkey ~= "" then
                if spellChanged or shouldUpdateCooldowns then
                    local inRange = C_Spell_IsSpellInRange and C_Spell_IsSpellInRange(intSpellID)
                    if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
                        interruptIcon.cachedOutOfRange = (inRange == false)
                    else
                        interruptIcon.cachedOutOfRange = false
                    end
                end
                local isOutOfRange = interruptIcon.cachedOutOfRange or false
                if interruptIcon.lastOutOfRange ~= isOutOfRange then
                    if isOutOfRange then
                        interruptIcon.hotkeyText:SetTextColor(1, 0, 0, 1)
                    else
                        local hkc = npoOverlays and npoOverlays.hotkey and npoOverlays.hotkey.color
                        interruptIcon.hotkeyText:SetTextColor((hkc and hkc.r) or 1, (hkc and hkc.g) or 1, (hkc and hkc.b) or 1, (hkc and hkc.a) or 1)
                    end
                    interruptIcon.lastOutOfRange = isOutOfRange
                end
            end

            -- Channeling grey-out: desaturate when player is channeling (can't interrupt)
            local intVisualState = isChanneling and 1 or 3
            if interruptIcon.lastVisualState ~= intVisualState then
                if intVisualState == 1 then
                    interruptIcon.iconTexture:SetDesaturation(1.0)
                else
                    interruptIcon.iconTexture:SetDesaturation(0)
                end
                interruptIcon.lastVisualState = intVisualState
            end

            -- Glow: red-tinted proc glow for interrupt urgency
            if not interruptIcon.hasInterruptGlow and UIAnimations then
                UIAnimations.StartInterruptGlow(interruptIcon, inCombat)
                interruptIcon.hasInterruptGlow = true
            end

            -- Cast aura: passthrough the enemy cast bar icon texture from the
            -- nameplate (textures can be secret values in 12.0 — pass directly
            -- to SetTexture without any comparison; Blizzard handles secrets in UI)
            if interruptIcon.castAura then
                local castIcon = castBar and castBar.Icon
                if castIcon and castIcon.GetTexture then
                    interruptIcon.castAura.iconTexture:SetTexture(castIcon:GetTexture())
                    if not interruptIcon.castAura:IsShown() then interruptIcon.castAura:Show() end
                    interruptIcon.castAura:SetAlpha(opacity)
                else
                    if interruptIcon.castAura:IsShown() then interruptIcon.castAura:Hide() end
                end
            end

            if not interruptIcon:IsShown() then
                UIRenderer.PlayInterruptAlertSound(profile)
                interruptIcon:Show()
            end
            interruptIcon:SetAlpha(opacity)
        else
            UIRenderer.HideInterruptIcon(interruptIcon)
        end

        -- Track interrupt visibility state (no re-anchor needed — interrupt
        -- icon is at inline position 0, never displaces dpsIcons[1]).
        interruptShown = shouldShowInterrupt
    end
    -- ── End interrupt reminder ───────────────────────────────────────────────

    for i, icon in ipairs(dpsIcons) do
        local spellID  = hasSpells and spellIDs[i] or nil
        local spellInfo = spellID and GetCachedSpellInfo and GetCachedSpellInfo(spellID) or nil

        if spellID and spellInfo then
            local spellChanged = (icon.spellID ~= spellID)

            if spellChanged then
                -- Track previous spell for key-press grace period
                if icon.spellID then
                    icon.previousSpellID = icon.spellID
                    icon.spellChangeTime = now
                    icon.previousNormalizedHotkey = icon.normalizedHotkey
                end
                icon.spellID = spellID
                icon.iconTexture:SetTexture(spellInfo.iconID)
                icon.iconTexture:Show()
                -- Reset cooldown state for new spell
                icon._cooldownShown       = false
                icon._chargeCooldownShown = false
                icon._cachedMaxCharges    = nil
                icon.cachedHotkey         = nil
            end

            -- Cooldowns (throttled, same interval as main panel)
            if spellChanged or shouldUpdateCooldowns then
                UIRenderer.UpdateButtonCooldowns(icon)
            end

            -- Glows
            if i == 1 and (npoGlowMode == "all" or npoGlowMode == "primaryOnly") then
                UIAnimations.StartAssistedGlow(icon, inCombat)
                icon.hasAssistedGlow = true
            elseif icon.hasAssistedGlow then
                UIAnimations.StopAssistedGlow(icon)
                icon.hasAssistedGlow = false
            end

            local isSyntheticProc = IsSyntheticProc and IsSyntheticProc(spellID)
            local isGapCloser = isSyntheticProc
                or (SpellQueue and SpellQueue.IsGapCloserSpell and SpellQueue.IsGapCloserSpell(spellID))
            local isRealProc = IsSpellProcced_raw and IsSpellProcced_raw(spellID)

            -- Gap-closer glow takes priority over standard proc glow
            local wantGapCloserGlow = isGapCloser and showGapCloserGlow
            local wantProcGlow = isRealProc and npoShowProcGlow and not wantGapCloserGlow

            if wantProcGlow then
                if not icon.hasProcGlow then UIAnimations.ShowProcGlow(icon); icon.hasProcGlow = true end
            elseif icon.hasProcGlow then
                UIAnimations.HideProcGlow(icon); icon.hasProcGlow = false
            end

            if isGapCloser and showGapCloserGlow then
                if not icon.hasGapCloserGlow then UIAnimations.StartGapCloserGlow(icon); icon.hasGapCloserGlow = true end
            elseif icon.hasGapCloserGlow then
                UIAnimations.StopGapCloserGlow(icon); icon.hasGapCloserGlow = false
            end

            -- Hotkey: look up on spell change or throttle interval; always track
            -- normalizedHotkey for flash matching even when display is off
            if spellChanged or shouldUpdateCooldowns or not icon.cachedHotkey then
                local hotkey = GetSpellHotkey and GetSpellHotkey(spellID) or ""
                local hotkeyChanged = (icon.cachedHotkey ~= hotkey)
                icon.cachedHotkey = hotkey

                local displayHotkey = showHotkey and hotkey or ""
                if (icon.hotkeyText:GetText() or "") ~= displayHotkey then
                    icon.hotkeyText:SetText(displayHotkey)
                end

                -- Only re-normalize when hotkey actually changed (mirrors UIRenderer optimization)
                if hotkeyChanged then
                    if hotkey ~= "" then
                        local n = UIRenderer.NormalizeHotkey(hotkey)
                        if icon.normalizedHotkey ~= n then
                            icon.previousNormalizedHotkey = icon.normalizedHotkey
                            icon.hotkeyChangeTime         = now
                        end
                        icon.normalizedHotkey = n
                    else
                        icon.normalizedHotkey = nil
                    end
                end
            end

            -- Out-of-range indicator: red hotkey text if out of range, white otherwise
            if showHotkey and icon.cachedHotkey and icon.cachedHotkey ~= "" and C_Spell_IsSpellInRange then
                if spellChanged or shouldUpdateCooldowns then
                    local inRange = C_Spell_IsSpellInRange(spellID)
                    if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
                        icon.cachedOutOfRange = (inRange == false)
                    else
                        icon.cachedOutOfRange = false
                    end
                end
                local isOutOfRange = icon.cachedOutOfRange or false
                if icon.lastOutOfRange ~= isOutOfRange then
                    icon.hotkeyText:SetTextColor(isOutOfRange and 1 or 1, isOutOfRange and 0 or 1, isOutOfRange and 0 or 1, 1)
                    icon.lastOutOfRange = isOutOfRange
                end
            end

            -- Channeling grey-out: desaturate when player is channeling
            local visualState = isChanneling and 1 or 3
            if icon.lastVisualState ~= visualState then
                if visualState == 1 then
                    icon.iconTexture:SetDesaturation(1.0)
                else
                    icon.iconTexture:SetDesaturation(0)
                end
                icon.lastVisualState = visualState
            end

            if not icon:IsShown() then icon:Show() end
            icon:SetAlpha(opacity)
        else
            -- Empty slot: clear icon
            if icon.spellID then
                icon.spellID = nil
                icon.iconTexture:Hide()
                if icon.cooldown then icon.cooldown:Clear(); icon.cooldown:Hide() end
                icon._cooldownShown       = false
                icon._chargeCooldownShown = false
                icon.normalizedHotkey     = nil
                icon.cachedHotkey         = nil
                if UIAnimations then
                    if icon.hasAssistedGlow then UIAnimations.StopAssistedGlow(icon); icon.hasAssistedGlow = false end
                    if icon.hasProcGlow     then UIAnimations.HideProcGlow(icon);     icon.hasProcGlow     = false end
                end
            end
            icon:Hide()
        end
    end
end

--- Update defensive icon display from the same queue computed in OnHealthChanged.
--- Delegates directly to UIRenderer.ShowDefensiveIcon / HideDefensiveIcon so
--- defensive icons on the overlay have full feature parity with the main panel
--- (hotkeys, proc glow, assisted glow, fade animations).
function UINameplateOverlay.RenderDefensives(addon, defensiveQueue)
    if not currentNameplate then return end
    if #defIcons == 0 then return end

    local npo          = addon:GetProfile() and addon:GetProfile().nameplateOverlay or {}
    local profile      = addon:GetProfile() or {}
    local npoGlowMode   = npo.defensiveGlowMode or npo.glowMode or "all"
    local opacity       = npo.opacity or 1.0
    local iconSpacing   = npo.iconSpacing or ICON_SPACING
    -- Read hotkey visibility from central textOverlays (Labels tab)
    local centralOverlays = profile.textOverlays
    local npoShowHotkey  = not centralOverlays or not centralOverlays.hotkey or centralOverlays.hotkey.show ~= false
    -- showFlash is centralized in profile (no longer per-surface)
    local showFlash      = profile.showFlash ~= false

    local visibleCount = 0
    for i, icon in ipairs(defIcons) do
        local entry = defensiveQueue and defensiveQueue[i]
        if entry and entry.spellID then
            icon.overlayOpacity = opacity
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, i == 1, npoGlowMode, npoShowHotkey, showFlash)
            -- Apply opacity to already-shown icons (fade-in handles newly-shown via OnFinished)
            if icon:IsShown() and not (icon.fadeIn and icon.fadeIn:IsPlaying()) then
                icon:SetAlpha(opacity)
            end
            visibleCount = visibleCount + 1
        else
            UIRenderer.HideDefensiveIcon(icon)
        end
    end

    -- Sync health bar size and position with the visible defensive slot count.
    -- Mirrors UIHealthBar.lua's inset logic:
    --   1 icon  → full iconSize, no inset
    --   2+ icons → inset 25% of iconSize from each outer edge, bar spans inner 50%+middle
    if healthBar then
        if visibleCount > 0 then
            if npo and npo.showHealthBar then
                local iconSize          = npo.iconSize or 26
                local anchor    = npo.reverseAnchor and "LEFT" or "RIGHT"
                local expansion = npo.expansion or "out"
                local isLeft    = (anchor == "LEFT")

                healthBar:ClearAllPoints()

                -- Compute bar dimensions once for both player and pet bars
                local barWidth, barHeight
                if expansion == "out" then
                    -- Horizontal cluster: symmetric 10% inset on both outer edges.
                    -- clusterWidth = n*size + (n-1)*spacing; barWidth = clusterWidth - 2*inset.
                    local clusterWidth = visibleCount * iconSize + (visibleCount - 1) * iconSpacing
                    local inset = (visibleCount == 1) and 0 or math_floor(iconSize * 0.10)
                    barWidth = math_floor(clusterWidth - 2 * inset)
                    healthBar:SetOrientation("HORIZONTAL")
                    healthBar:SetSize(barWidth, BAR_HEIGHT)
                    -- Show horizontal bevel strips; hide vertical ones
                    if healthBar.hBevelStrips then
                        for _, s in ipairs(healthBar.hBevelStrips) do s:Show() end
                    end
                    if healthBar.bevelStrips then
                        for _, s in ipairs(healthBar.bevelStrips) do s:Hide() end
                    end
                    if isLeft then
                        -- defIcons[1] is innermost (leftmost); cluster grows rightward.
                        healthBar:SetPoint("BOTTOMLEFT", defIcons[1], "TOPLEFT", inset, BAR_SPACING)
                    else
                        -- defIcons[1] is innermost (rightmost); cluster grows leftward.
                        healthBar:SetPoint("BOTTOMRIGHT", defIcons[1], "TOPRIGHT", -inset, BAR_SPACING)
                    end
                else
                    -- Vertical cluster: VERTICAL bar spans beside the column on the outer side.
                    -- Same inset rule as horizontal: 10% of iconSize per edge for 2+ icons.
                    local clusterHeight = visibleCount * iconSize + (visibleCount - 1) * iconSpacing
                    local inset = (visibleCount == 1) and 0 or math_floor(iconSize * 0.10)
                    barHeight = math_floor(clusterHeight - 2 * inset)
                    healthBar:SetOrientation("VERTICAL")  -- fills bottom→top
                    -- Show vertical bevel strips; hide horizontal ones
                    if healthBar.bevelStrips then
                        for _, s in ipairs(healthBar.bevelStrips) do s:Show() end
                    end
                    if healthBar.hBevelStrips then
                        for _, s in ipairs(healthBar.hBevelStrips) do s:Hide() end
                    end
                    healthBar:SetSize(BAR_HEIGHT, barHeight)
                    if expansion == "up" then
                        -- defIcons[1] is at the bottom of the column; chain grows upward.
                        -- Bar anchors by its bottom corner to defIcons[1]'s bottom outer corner.
                        if isLeft then
                            -- DEF cluster is RIGHT of nameplate; outer side is further right.
                            healthBar:SetPoint("BOTTOMLEFT",  defIcons[1], "BOTTOMRIGHT",  BAR_SPACING,  inset)
                        else
                            healthBar:SetPoint("BOTTOMRIGHT", defIcons[1], "BOTTOMLEFT",  -BAR_SPACING,  inset)
                        end
                    else  -- "down"
                        -- defIcons[1] is at the top of the column; chain grows downward.
                        -- Bar anchors by its top corner to defIcons[1]'s top outer corner.
                        if isLeft then
                            healthBar:SetPoint("TOPLEFT",  defIcons[1], "TOPRIGHT",  BAR_SPACING, -inset)
                        else
                            healthBar:SetPoint("TOPRIGHT", defIcons[1], "TOPLEFT",  -BAR_SPACING, -inset)
                        end
                    end
                end

                healthBar:SetAlpha(opacity)
                if not healthBar:IsShown() then healthBar:Show() end

                -- Pet health bar: same size/orientation as player bar, stacked one bar further out.
                -- Auto-hides when no pet exists.
                if petHealthBar then
                    if UnitExists("pet") then
                        petHealthBar:ClearAllPoints()
                        if expansion == "out" then
                            petHealthBar:SetOrientation("HORIZONTAL")
                            petHealthBar:SetSize(barWidth, BAR_HEIGHT)
                            if petHealthBar.hBevelStrips then
                                for _, s in ipairs(petHealthBar.hBevelStrips) do s:Show() end
                            end
                            if petHealthBar.bevelStrips then
                                for _, s in ipairs(petHealthBar.bevelStrips) do s:Hide() end
                            end
                            if isLeft then
                                petHealthBar:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, BAR_SPACING)
                            else
                                petHealthBar:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, BAR_SPACING)
                            end
                        else
                            petHealthBar:SetOrientation("VERTICAL")
                            petHealthBar:SetSize(BAR_HEIGHT, barHeight)
                            if petHealthBar.bevelStrips then
                                for _, s in ipairs(petHealthBar.bevelStrips) do s:Show() end
                            end
                            if petHealthBar.hBevelStrips then
                                for _, s in ipairs(petHealthBar.hBevelStrips) do s:Hide() end
                            end
                            if expansion == "up" then
                                if isLeft then
                                    petHealthBar:SetPoint("BOTTOMLEFT",  healthBar, "BOTTOMRIGHT",  BAR_SPACING, 0)
                                else
                                    petHealthBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMLEFT",  -BAR_SPACING, 0)
                                end
                            else  -- "down"
                                if isLeft then
                                    petHealthBar:SetPoint("TOPLEFT",  healthBar, "TOPRIGHT",  BAR_SPACING, 0)
                                else
                                    petHealthBar:SetPoint("TOPRIGHT", healthBar, "TOPLEFT",  -BAR_SPACING, 0)
                                end
                            end
                        end
                        petHealthBar:SetAlpha(opacity)
                        if not petHealthBar:IsShown() then petHealthBar:Show() end
                    else
                        petHealthBar:Hide()
                    end
                end
            end
        else
            healthBar:Hide()
            if petHealthBar then petHealthBar:Hide() end
        end
    end
end

--- Hide all defensive overlay icons (called when defensive queue is empty).
function UINameplateOverlay.HideDefensiveIcons()
    for _, icon in ipairs(defIcons) do
        UIRenderer.HideDefensiveIcon(icon)
    end
    if healthBar then healthBar:Hide() end
    if petHealthBar then petHealthBar:Hide() end
end

--- Return the base RGB for the overlay health bar, mirroring the user's
--- WoW nameplate / raid-frame health-bar colour settings (new in 12.0).
--- Falls back to solid green on pre-12.0 clients or if CVars are absent.
--- Update the player health bar fill value and colour.
--- Fill: StatusBar:SetValue() accepts Blizzard secret values natively.
--- Colour: fixed bright green base, tinted orange/red at low health using
--- GetPlayerHealthPercentSafe() so it works even when values are secret (12.0+).
function UINameplateOverlay.UpdateHealthBar()
    if not healthBar or not healthBar:IsShown() then return end

    -- Drive fill from raw UnitHealth — secret-safe, tracks continuously.
    local health    = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    if health and maxHealth and maxHealth > 0 then
        healthBar:SetMinMaxValues(0, maxHealth)
        healthBar:SetValue(health)
    end

    -- Fixed bright green base; tint orange/red at low health thresholds.
    local r, g, b = 0.0, 1.0, 0.0
    local healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()

    if isEstimated then
        -- In 12.0 combat UnitHealth() is secret; use binary low-health states for colour only.
        local lowState, critState = false, false
        if BlizzardAPI.GetLowHealthState then
            lowState, critState = BlizzardAPI.GetLowHealthState()
        end
        if critState then
            r, g, b = 0.8, 0.1, 0.1
        elseif lowState then
            r, g, b = 0.9, 0.5, 0.1
        end
    elseif healthPercent then
        local pct = healthPercent / 100
        if     pct <= 0.2  then r, g, b = 0.8, 0.1, 0.1
        elseif pct <= 0.35 then r, g, b = 0.9, 0.5, 0.1 end
    end
    healthBar:SetStatusBarColor(r, g, b, 0.9)
end

--- Re-resolve the module-local interrupt spell list.
--- Called from JustAC:OnSpellsChanged() / OnSpecChange() when talents may have
--- changed which interrupt/CC spells are available.

--- Update the pet health bar fill value.
--- UnitHealth("pet") is secret in 12.0 combat but StatusBar:SetValue() accepts secrets.
--- Auto-hides when no pet exists.
function UINameplateOverlay.UpdatePetHealthBar()
    if not petHealthBar then return end

    local exists = UnitExists("pet")
    if not exists then
        petHealthBar:Hide()
        return
    end

    -- Only show if the bar is supposed to be visible (set by RenderDefensives)
    if not petHealthBar:IsShown() then return end

    local ok, isDead = pcall(UnitIsDead, "pet")
    if ok and isDead and not BlizzardAPI.IsSecretValue(isDead) then
        petHealthBar:SetStatusBarColor(0.8, 0.1, 0.1, 0.9)
        petHealthBar:SetValue(0)
        return
    end

    local health    = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")
    if health and maxHealth and maxHealth > 0 then
        petHealthBar:SetMinMaxValues(0, maxHealth)
        petHealthBar:SetValue(health)
    end

    -- Warm yellow base colour
    petHealthBar:SetStatusBarColor(0.90, 0.75, 0.10, 0.9)
end

function UINameplateOverlay.RefreshInterruptSpells()
    if SpellDB and SpellDB.ResolveInterruptSpells then
        resolvedInterrupts = SpellDB.ResolveInterruptSpells()
    end
end

--- Returns true when the overlay is currently anchored to a nameplate.
--- Used by UIRenderer/DefensiveEngine to decide whether to fall back to the main panel.
function UINameplateOverlay.IsAnchored()
    return currentNameplate ~= nil
end

--- Hide every overlay element (called from EnterDisabledMode).
function UINameplateOverlay.HideAll()
    for _, icon in ipairs(dpsIcons) do
        if UIAnimations then
            if icon.hasAssistedGlow  then UIAnimations.StopAssistedGlow(icon);  icon.hasAssistedGlow  = false end
            if icon.hasProcGlow      then UIAnimations.HideProcGlow(icon);       icon.hasProcGlow      = false end
        end
        icon:Hide()
    end
    for _, icon in ipairs(defIcons) do
        if UIAnimations then
            if icon.hasDefensiveGlow then UIAnimations.StopDefensiveGlow(icon); icon.hasDefensiveGlow = false end
            if icon.hasProcGlow      then UIAnimations.HideProcGlow(icon);      icon.hasProcGlow      = false end
        end
        icon:Hide()
    end
    if healthBar then healthBar:Hide() end
    if petHealthBar then petHealthBar:Hide() end
    if interruptIcon then
        if UIAnimations then
            if interruptIcon.hasInterruptGlow then UIAnimations.StopInterruptGlow(interruptIcon); interruptIcon.hasInterruptGlow = false end
            if interruptIcon.hasProcGlow     then UIAnimations.HideProcGlow(interruptIcon);       interruptIcon.hasProcGlow      = false end
        end
        interruptIcon:Hide()
        interruptShown = false
    end
end

-- Called by JustAC when the player successfully casts a CC spell.
-- Delegates to UIRenderer.NotifyCCApplied() so the shared debounce state
-- (now consolidated there) is updated regardless of which renderer is active.
function UINameplateOverlay.NotifyCCApplied()
    if UIRenderer and UIRenderer.NotifyCCApplied then UIRenderer.NotifyCCApplied() end
end
