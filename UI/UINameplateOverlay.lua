-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Nameplate Overlay Module
-- An independent display that anchors DPS queue icons (and optional defensives +
-- player health bar) directly to the target's nameplate.  Completely separate from
-- the main panel – either feature can be enabled without the other.
local UINameplateOverlay = LibStub:NewLibrary("JustAC-UINameplateOverlay", 14)
if not UINameplateOverlay then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIRenderer = LibStub("JustAC-UIRenderer", true)
local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local UISootheCue = LibStub("JustAC-UISootheCue", true)

if not BlizzardAPI or not UIAnimations or not UIRenderer then return end

-- Hot path cache
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack = UnitCanAttack
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local math_min = math.min
local math_floor = math.floor
local ipairs = ipairs
local C_NamePlate = C_NamePlate ---@diagnostic disable-line: undefined-global
local GetCVar = GetCVar
local SetCVar = SetCVar

-- Layout constants
local ICON_SPACING       = 2   -- px between successive icons in the cluster
local NAMEPLATE_GAP_LEFT  = 12  -- gap on LEFT side of health bar
local NAMEPLATE_GAP_RIGHT = 13  -- gap on RIGHT side; slightly larger to compensate for Blizzard's
                                -- asymmetric bgTexture (extends further past the right edge)
local BAR_HEIGHT     = 5   -- overlay health bar (thinner than UIHealthBar.BAR_HEIGHT=6)
local BAR_SPACING    = 2   -- overlay bar gap (tighter than UIHealthBar.BAR_SPACING=3)
local POWER_BAR_HEIGHT = (UIHealthBar and UIHealthBar.POWER_BAR_HEIGHT) or 3  -- resource-bar thickness
local POWER_UPDATE_INTERVAL = 0.1  -- resource-bar value throttle (mirrors UIHealthBar's cadence)

-- Cooldown update throttle (shared source with UIRenderer via UIFrameFactory export)
local lastCooldownUpdate       = 0
local COOLDOWN_UPDATE_INTERVAL = UIFrameFactory.COOLDOWN_UPDATE_INTERVAL

-- Reused ctx tables for the shared renderers (UIRenderer.RenderQueueIcon /
-- UIRenderer.RenderInterruptSlot).
local renderCtx = {}
local interruptCtx = {}

-- Module state (reset by Destroy)
local dpsIcons         = {}   -- [1..N] DPS icon buttons
local defIcons         = {}   -- [1..N] defensive icon buttons
local maintenanceIcon  = nil  -- tank maintenance slot: defensive "position 0" (see interruptIcon)
local pendingMasqueRemoval = {} -- icons whose RemoveButton was skipped in combat; cleaned on next OOC Destroy
local healthBar        = nil  -- player health StatusBar
local petHealthBar     = nil  -- pet health StatusBar (warm yellow)
local overlayPowerBar          = nil  -- primary resource bar (current displayed power)
local overlaySecondaryPowerBar = nil  -- secondary point-resource bar (combo points / chi / …)
local overlaySecondarySegments = 0    -- cached fail-closed segment count for the secondary
local lastOverlayPowerUpdate    = 0   -- throttle stamp for UpdatePowerBar
local lastOverlayHealthUpdate    = 0  -- throttle stamp for UpdateHealthBar
local lastOverlayPetHealthUpdate = 0  -- throttle stamp for UpdatePetHealthBar
local currentNameplate = nil  -- nameplate frame we're currently anchored to
local savedCCAnchors   = nil  -- saved Blizzard CC frame anchors for restoration
local interruptIcon    = nil  -- single interrupt reminder icon ("position 0")
local savedNameplateShowEnemies = nil  -- original CVar value before we forced it on
local savedShowQuestUnitCircles = nil -- original CVar value before we suppressed quest indicators
local questIndicator   = nil  -- our replacement quest "!" texture on the nameplate
local resolvedInterrupts = nil -- ordered array of known interrupt spell IDs (resolved at Create)
local resolvedSoothe     = nil -- player's enrage-dispel ("soothe") abilities (resolved at Create)
local UnitIsQuestBoss  = UnitIsQuestBoss ---@diagnostic disable-line: undefined-global

-- Masque support (separate group from standard/defensive queues)
local Masque = LibStub("Masque", true)
local MasqueOverlayGroup
local GetMasqueOverlayGroup

if Masque then
    MasqueOverlayGroup = Masque:Group("JustAssistedCombat", "Nameplate Overlay")
    GetMasqueOverlayGroup = function() return MasqueOverlayGroup end

    -- Re-apply text overlay settings after Masque re-skins (user changes skin).
    -- Masque's Skin_Text repositions HotKey; our ApplyTextOverlaySettings must
    -- override afterwards to restore user-configured anchors.
    local function OnOverlaySkinChanged(Group, Option)
        if Option ~= "SkinID" and Option ~= "Reset" and Option ~= "Disabled" then return end
        local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        if not addon or not addon.db then return end
        local profile = addon:GetProfile()
        if not profile or not profile.nameplateOverlay then return end
        local npo = profile.nameplateOverlay
        local iconSize = npo.iconSize or 32
        local mergedOverlays = UIFrameFactory and UIFrameFactory.MergeOverlayTextOverlays and UIFrameFactory.MergeOverlayTextOverlays(profile)
        if UIFrameFactory and UIFrameFactory.ApplyTextOverlaySettingsToIcons then
            UIFrameFactory.ApplyTextOverlaySettingsToIcons(dpsIcons, iconSize, mergedOverlays)
            UIFrameFactory.ApplyTextOverlaySettingsToIcons(defIcons, iconSize, mergedOverlays)
        end
        -- Kept as separate checks, not an ipairs list: a nil singleton would end the loop early.
        if interruptIcon then
            UIFrameFactory.ApplyTextOverlaySettings(interruptIcon, iconSize, mergedOverlays)
        end
        if maintenanceIcon then
            UIFrameFactory.ApplyTextOverlaySettings(maintenanceIcon, iconSize, mergedOverlays)
            -- Masque owns the Cooldown element and resets the swipe to its skin's defaults.
            UIFrameFactory.ApplyMaintenanceSwipeStyle(maintenanceIcon)
        end
    end

    MasqueOverlayGroup:RegisterCallback(OnOverlaySkinChanged)
else
    GetMasqueOverlayGroup = function() return nil end
end

-- Cached anchor params (set in AnchorToNameplate, used in Render for dynamic re-anchor)

-- Health bar layout cache: skip re-anchor when nothing changed
local lastDefVisibleCount = 0

-- Cached defensive queue: allows RefreshDefensives to re-render on the same
-- tick as the offensive overlay, eliminating the visual delay caused by
-- defensive evaluation running on a slower cadence.
local cachedDefensiveQueue = nil

-- ─────────────────────────────────────────────────────────────────────────────
-- Icon button factory
-- Produces a button compatible with:
--   • UIRenderer.UpdateButtonCooldowns  (cooldowns)
--   • UIRenderer.ShowDefensiveIcon      (defensive display)
--   • UIAnimations glow/flash functions (proc / assisted / defensive glows)
--   • JustAC:CreateKeyPressDetector     (key-press flash via normalizedHotkey)
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateOverlayIcon(iconSize, profile)
    -- Build the shared icon skeleton (textures, cooldowns, hotkey, animations).
    -- isClickable=false (always click-through), isFirstIcon=true (uses HOTKEY_OFFSET_FIRST=-3).
    local button = UIFrameFactory.CreateBaseIcon(UIParent, iconSize, false, true)
    if not button then return nil end

    -- Nameplate-specific: BACKGROUND strata so icons sit under addon UI.
    button:SetFrameStrata("BACKGROUND")
    button.FlashFrame:SetFrameStrata("BACKGROUND")
    button.cooldownContainer:SetFrameStrata("BACKGROUND")
    button.cooldown:SetFrameStrata("BACKGROUND")
    button.chargeCooldown:SetFrameStrata("BACKGROUND")
    button.borderFrame:SetFrameStrata("BACKGROUND")
    button.hotkeyFrame:SetFrameStrata("BACKGROUND")
    -- The cue dot is a child of hotkeyFrame, but this file deliberately does NOT rely on the
    -- parent cascade (see the level note below), so it needs forcing like every other subframe
    -- or it floats above other addons' nameplate UI.
    if button.cueDot then button.cueDot:SetFrameStrata("BACKGROUND") end

    -- Keep frame LEVELS at the engine floor too: strata alone isn't enough against
    -- addon UI (e.g. a unit-frame addon) that also lives at BACKGROUND - it occluded
    -- the icon body while the hotkey (+15) and glow frames (+4/+5) poked above it.
    -- Explicit absolute levels on every subframe (parent-level cascade is not relied
    -- on), packed 0..4: icon(0) < cooldowns(1) < border(2) < glows(3, clamped at
    -- lazy creation in UIAnimations) < flash/hotkey(4; hotkey is created later so it
    -- wins the tie and stays readable above the flash).
    button:SetFrameLevel(0)
    button.cooldownContainer:SetFrameLevel(1)
    button.cooldown:SetFrameLevel(1)
    button.chargeCooldown:SetFrameLevel(1)
    button.borderFrame:SetFrameLevel(2)
    button.FlashFrame:SetFrameLevel(4)
    button.hotkeyFrame:SetFrameLevel(4)
    if button.cueDot then button.cueDot:SetFrameLevel(4) end

    -- Nameplate-specific: tighter cooldown insets (3 px vs 4 px in base).
    button.cooldown:ClearAllPoints()
    button.cooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      3, -3)
    button.cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3,  3)
    button.chargeCooldown:ClearAllPoints()
    button.chargeCooldown:SetPoint("TOPLEFT",     button, "TOPLEFT",      3, -3)
    button.chargeCooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3,  3)

    -- Nameplate-specific state fields.
    button.isOverlayIcon      = true
    button.overlayOpacity     = 1
    button.hasGapCloserGlow   = false
    button.hasBurstGlow       = false

    -- Nameplate-specific Masque registration (overlay group; skip if InCombatLockdown
    -- since GetSize() returns a secret value, causing Masque to misbehave).
    -- Icons created in combat use the default Masque skin; next OOC Destroy+Create applies it.
    local MasqueGroup = (not InCombatLockdown()) and GetMasqueOverlayGroup and GetMasqueOverlayGroup()
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon           = button.iconTexture,
            Cooldown       = button.cooldown,
            ChargeCooldown = button.chargeCooldown,
            HotKey         = button.hotkeyText,
            Count          = button.chargeText,
            Normal         = button.NormalTexture,
        })
    end

    -- Apply overlay text overlay settings AFTER Masque so our anchor overrides
    -- the skin's HotKey position.
    if UIFrameFactory.ApplyTextOverlaySettings then
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
    bar:SetFrameStrata("BACKGROUND")
    bar:SetSize(initialWidth, BAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(0.0, 0.80, 0.0, 0.9)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:EnableMouse(false)

    -- Shared dark-neutral background + gloss sheen, so the overlay bar matches the
    -- standard queue's styling exactly (fill reads as remaining health, missing
    -- portion dark, lit-tube sheen). AddBarBackground sets bar.bg for later re-tint.
    UIHealthBar.AddBarBackground(bar)
    -- ponytail: gloss gradient is fixed to the create-time horizontal orientation;
    -- on a 5px bar the direction is barely perceptible once the bar renders vertical.
    UIHealthBar.AddBarGloss(bar, true)

    -- Both orientations built up front and started hidden: this bar re-orients at runtime,
    -- so the layout code just shows the matching set. Same strips the standard queue uses.
    bar.hBevelStrips = UIHealthBar.AddTubeBevel(bar, true, true)
    bar.bevelStrips  = UIHealthBar.AddTubeBevel(bar, false, true)

    bar:SetAlpha(0)
    bar:Hide()
    return bar
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Player resource / power bars (overlay-owned)
-- Mirrors the standard queue's power-bar system, but anchored to the overlay's
-- nameplate-tracking health bars with dynamic per-render orientation. A PRIMARY
-- bar for the current displayed power, plus an optional SEGMENTED SECONDARY bar
-- for a spec's point resource (combo points / runes / chi / …). Value fill is a
-- secret-safe StatusBar:SetValue passthrough; the segment helpers, colour and
-- POWER_BAR_HEIGHT are reused from UIHealthBar. The StatusBar doubles as the
-- `frame` the segment helpers expect (frame == frame.statusBar).
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateOverlayPowerBar(powerType)
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetFrameStrata("BACKGROUND")
    bar:SetSize(POWER_BAR_HEIGHT, POWER_BAR_HEIGHT)  -- real size assigned per render
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:EnableMouse(false)

    UIHealthBar.AddBarBackground(bar)         -- dark-neutral bg, re-tinted to the power colour
    UIHealthBar.AddBarGloss(bar, true)        -- lit-tube sheen (create-time horizontal)
    UIHealthBar.ApplyResourceColor(bar, powerType)

    -- Fields the shared PositionSegments/RebuildSegments helpers read; the bar is
    -- both the frame and its statusBar.
    bar.statusBar      = bar
    bar.powerType      = powerType            -- nil = current displayed power
    bar.barIsHorizontal = true

    bar:SetAlpha(0)
    bar:Hide()
    return bar
end

-- Cache the secondary segment count. The fail-CLOSED secret-value rule (a spec without
-- the resource stays hidden) lives in UIHealthBar so both surfaces cannot drift on it.
local function RefreshOverlaySecondaryCache()
    overlaySecondarySegments =
        UIHealthBar.ResolveSegmentCount(overlaySecondaryPowerBar, overlaySecondarySegments)
end

-- Size + orient one bar beyond `anchorBar` at the given thickness, matching the
-- cluster expansion. `barWidth`/`barHeight` come from the health-bar sizing (one
-- is nil per orientation - only the used one matters).
local function AnchorOverlayBar(bar, anchorBar, expansion, isLeft, barWidth, barHeight, thickness)
    bar:ClearAllPoints()
    if expansion == "out" then
        bar:SetOrientation("HORIZONTAL")
        bar:SetSize(barWidth, thickness)
        if isLeft then
            bar:SetPoint("BOTTOMLEFT",  anchorBar, "TOPLEFT",  0, BAR_SPACING)
        else
            bar:SetPoint("BOTTOMRIGHT", anchorBar, "TOPRIGHT", 0, BAR_SPACING)
        end
    else
        bar:SetOrientation("VERTICAL")
        bar:SetSize(thickness, barHeight)
        if expansion == "up" then
            if isLeft then
                bar:SetPoint("BOTTOMLEFT",  anchorBar, "BOTTOMRIGHT",  BAR_SPACING, 0)
            else
                bar:SetPoint("BOTTOMRIGHT", anchorBar, "BOTTOMLEFT",  -BAR_SPACING, 0)
            end
        else  -- "down"
            if isLeft then
                bar:SetPoint("TOPLEFT",  anchorBar, "TOPRIGHT",  BAR_SPACING, 0)
            else
                bar:SetPoint("TOPRIGHT", anchorBar, "TOPLEFT",  -BAR_SPACING, 0)
            end
        end
    end
end

-- Show the bevel strips matching the bar's orientation, hide the other set.
local function SetBevelOrientation(bar, horizontal)
    if bar.hBevelStrips then
        for _, s in ipairs(bar.hBevelStrips) do s:SetShown(horizontal) end
    end
    if bar.bevelStrips then
        for _, s in ipairs(bar.bevelStrips) do s:SetShown(not horizontal) end
    end
end

-- Resource-bar variant: POWER_BAR_HEIGHT thickness, plus the fill-direction flag
-- the segment layout reads.
local function AnchorOverlayPowerBar(bar, anchorBar, expansion, isLeft, barWidth, barHeight)
    AnchorOverlayBar(bar, anchorBar, expansion, isLeft, barWidth, barHeight, POWER_BAR_HEIGHT)
    bar.barIsHorizontal = (expansion == "out")
end

-- Stack the resource bars beyond the outermost shown health bar and (re)segment the
-- secondary for the current orientation/size. Called from the health-bar re-anchor block.
local function PositionOverlayPowerBars(npo, expansion, isLeft, barWidth, barHeight, opacity)
    if not (overlayPowerBar and npo.showPowerBar and healthBar) then
        if overlayPowerBar then overlayPowerBar:Hide() end
        if overlaySecondaryPowerBar then overlaySecondaryPowerBar:Hide() end
        return
    end

    local outer = (petHealthBar and petHealthBar:IsShown()) and petHealthBar or healthBar
    AnchorOverlayPowerBar(overlayPowerBar, outer, expansion, isLeft, barWidth, barHeight)
    overlayPowerBar:SetAlpha(opacity)
    overlayPowerBar:Show()

    if overlaySecondaryPowerBar then
        RefreshOverlaySecondaryCache()
        if overlaySecondarySegments > 0 then
            AnchorOverlayPowerBar(overlaySecondaryPowerBar, overlayPowerBar, expansion, isLeft, barWidth, barHeight)
            -- Explicit non-secret dims: the bar anchors into the secret nameplate, so its
            -- GetWidth/GetHeight are secret. Segments run along the bar's length; the other
            -- axis is POWER_BAR_HEIGHT. (out = horizontal, up/down = vertical.)
            local horizontal = (expansion == "out")
            local segW = horizontal and barWidth or POWER_BAR_HEIGHT
            local segH = horizontal and POWER_BAR_HEIGHT or barHeight
            if overlaySecondaryPowerBar.segmentCount ~= overlaySecondarySegments then
                UIHealthBar.RebuildSegments(overlaySecondaryPowerBar, overlaySecondarySegments, segW, segH)
            else
                UIHealthBar.PositionSegments(overlaySecondaryPowerBar, segW, segH)  -- re-lay-out for new size/orientation
            end
            overlaySecondaryPowerBar:SetAlpha(opacity)
            overlaySecondaryPowerBar:Show()
        else
            overlaySecondaryPowerBar:Hide()
        end
    end
end

-- Secret-safe value passthrough for one resource bar. Shared with the standard queue's
-- bars: overlay bars set `bar.statusBar = bar`, so they satisfy the same shape.
local UpdateOneOverlayPowerBar = UIHealthBar and UIHealthBar.UpdateOneResourceBar

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

-- Nameplate aura frames (the CC/stun list, LoC, and the enrage buff) are children of the
-- nameplate, so they inherit the target nameplate's scale - bumped up by default via
-- nameplateSelectedScale. Our queue icons are UIParent children, so without compensation
-- the auras render noticeably bigger. Return the UIParent/AurasFrame effective-scale ratio
-- so a list-frame scale lands the aura item at the intended UIParent-space pixel size.
-- GetEffectiveScale can be blocked on a restricted nameplate in combat → pcall and reuse
-- the last good value (the target nameplate's scale is stable across a fight).
local cachedAuraScaleRatio = nil
local function AuraFrameScaleRatio(af)
    local IsSecret = BlizzardAPI.IsSecretValue
    local ok, ratio = pcall(function()
        local afEff = af:GetEffectiveScale()
        local uiEff = UIParent:GetEffectiveScale()
        if afEff and uiEff and afEff > 0
           and not (IsSecret and (IsSecret(afEff) or IsSecret(uiEff))) then
            return uiEff / afEff
        end
    end)
    if ok and ratio and ratio > 0 then cachedAuraScaleRatio = ratio end
    return cachedAuraScaleRatio or 1
end

-- List-frame scale that renders one aura item at targetPx (UIParent space), accounting for
-- Blizzard's per-item auraItemScale and the nameplate scale-space ratio above.
local function AuraListScaleForQueue(af, targetPx)
    local auraItemScale = af.auraItemScale or 1
    return (targetPx / (BLIZZARD_AURA_HEIGHT * auraItemScale)) * AuraFrameScaleRatio(af)
end

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

-- ─────────────────────────────────────────────────────────────────────────────
-- Enrage indicator (Blizzard's enemy BuffListFrame)
-- The engine renders enemy important/stealable buffs - ENRAGE among them - in the
-- nameplate BuffListFrame. We reposition it to sit as "position 0" of the DEFENSIVE
-- queue (the mirror of the interrupt icon on the offensive queue) and restore it on
-- detach. This is the only secret-safe enrage signal available: the engine renders it,
-- we only move the frame - we never read the aura.
-- ─────────────────────────────────────────────────────────────────────────────
-- Where the defensive row meets the nameplate, captured while AnchorToNameplate lays the
-- row out. PositionEnrageIndicator needs it to anchor against the NAMEPLATE rather than
-- against one of our own icons - see the note there. Cleared on detach so a nameplate swap
-- can never place the indicator against the frame the previous one used.
local defRowAnchor = {}

-- Likewise for whichever row ends up on the RIGHT of the nameplate - that's where the
-- crowd-control and loss-of-control frames get displaced to, and DisplaceCCFrames has the
-- same problem: it must reach that spot without anchoring Blizzard's frames to ours.
local rightRowAnchor = {}

local savedEnrageFrame       = nil  -- Blizzard BuffListFrame we repositioned (restore on detach)
local savedEnrageClassAnchor = nil  -- its XML default anchor target (ClassificationFrame)
local lastEnrageCount        = -1   -- defensive visibleCount at last enrage re-anchor

-- Restore the BuffListFrame to its XML default: RIGHT of ClassificationFrame.LEFT,
-- scale 1 (Blizzard_NamePlates.xml). Hardcoded because GetPoint() is secret in combat.
local function RestoreEnrageIndicator()
    if not savedEnrageFrame then return end
    pcall(function()
        savedEnrageFrame:ClearAllPoints()
        if savedEnrageClassAnchor then
            savedEnrageFrame:SetPoint("RIGHT", savedEnrageClassAnchor, "LEFT", -5, 0)
        end
        savedEnrageFrame:SetScale(1)
    end)
    savedEnrageFrame       = nil
    savedEnrageClassAnchor = nil
end

-- (Rect measurement helpers are gone deliberately: rects of nameplate-parented
-- frames are refused in combat, so every consumer now works from the analytic
-- layout state in defRowAnchor/rightRowAnchor instead.)

-- Position the BuffListFrame as position 0 of the defensive queue, scaled to the queue
-- icon size so it reads as part of the defensive column.
--   "down" → inline above defIcons[1]        "up" → inline below defIcons[1]
--   "out"  → perpendicular pop-out above the health/resource stack (stackTop), so the
--            enrage never overlaps those bars.
--
-- Anchored to the nameplate, never to defIcons[1] - even though the icon is what we're
-- lining up with. This frame is Blizzard's and restricted; anchoring it to one of ours
-- would make that icon, and everything its rect depends on, geometry-protected in combat,
-- and the anchor dependency isn't suspended while the frame is hidden. Our icons get moved
-- every frame, so that trade is not available. Same reasoning as the out-of-combat click
-- overlay, which copies rects rather than anchoring across the boundary.
--
-- ponytail: sub-item centering inside Blizzard's list frame may want a small x nudge -
-- tune by eye in-game; the structural anchor is what matters here.
local function PositionEnrageIndicator(npo, expansion)
    local uf        = currentNameplate and currentNameplate.UnitFrame
    local af        = uf and uf.AurasFrame
    local buffFrame = af and af.BuffListFrame
    local anchorFrame = defRowAnchor.frame
    if not buffFrame or not anchorFrame or #defIcons == 0 then RestoreEnrageIndicator(); return false end

    local iconSize = npo.iconSize or 32
    local defScale = npo.defensiveIconScale or 1  -- defensive icons render at iconSize * this
    -- Match the defensive icons' rendered size, compensating for the nameplate scale space.
    local scale    = AuraListScaleForQueue(af, iconSize * defScale)
    -- Effective spacing: icons chain in their own scaled space (see AnchorToNameplate).
    local spacing  = (npo.iconSpacing or ICON_SPACING) * defScale

    -- SetPoint offsets are read in the positioned frame's own (scaled) space, while every
    -- distance below is measured in UIParent space. One conversion factor covers all of them.
    local perPx = AuraFrameScaleRatio(af) / (scale > 0 and scale or 1)

    -- Horizontal centre of the defensive row as an offset from the nameplate edge it hangs
    -- off. defIcons[1] anchors LEFT/RIGHT (so, vertically centred) at exactly this gap, which
    -- puts its centre half an icon further along and its top half an icon above.
    -- defRowAnchor carries EFFECTIVE (scaled) geometry.
    local half = (defRowAnchor.iconSize or iconSize * defScale) * 0.5
    local cx   = (defRowAnchor.gapX or 0) + (defRowAnchor.isLeft and half or -half)

    -- "out" stacks the indicator above the health/resource bars instead of the icon row,
    -- using the ANALYTIC stack extent RenderDefensives captured - measuring the bars via
    -- GetRect is refused in combat (their rects hang off the restricted nameplate), which
    -- used to silently skip this placement for entire fights.
    local dx, dy = 0, 0
    if expansion == "out" and (defRowAnchor.stackOut or 0) > 0 then
        dy = defRowAnchor.stackOut
        dx = (defRowAnchor.isLeft and 1 or -1) * (defRowAnchor.stackShift or 0)
    end

    local ok = pcall(function()
        buffFrame:ClearAllPoints()
        buffFrame:SetScale(scale)
        if expansion == "up" then
            -- One slot below the row: the indicator's TOP meets icon 1's BOTTOM.
            buffFrame:SetPoint("TOP", anchorFrame, defRowAnchor.edge,
                cx * perPx, -(half + spacing) * perPx)
        else
            -- "down" and "out": the indicator's BOTTOM sits above icon 1, or above the stack
            -- when one is measured (dx/dy are zero when stackTop IS icon 1, so they agree).
            buffFrame:SetPoint("BOTTOM", anchorFrame, defRowAnchor.edge,
                (cx + dx) * perPx, (half + dy + spacing) * perPx)
        end
    end)
    if ok then
        savedEnrageFrame       = buffFrame
        savedEnrageClassAnchor = uf.ClassificationFrame
    end
    return ok
end

--- Restore all displaced CC/classification frames to their original Blizzard anchoring.
local function RestoreCCFrames()
    RestoreEnrageIndicator()  -- independent of savedCCAnchors; always attempt
    if not savedCCAnchors then return end
    local healthBar = savedCCAnchors.healthBar
    if savedCCAnchors.ccList then
        RestoreBlizzardCCAnchor(savedCCAnchors.ccList, healthBar)
    end
    if savedCCAnchors.locFrame then
        RestoreBlizzardCCAnchor(savedCCAnchors.locFrame, healthBar)
    end
    -- Restore elite/boss classification icon: default is RIGHT of RaidTargetFrame at scale 1
    if savedCCAnchors.classificationFrame and savedCCAnchors.raidTargetFrame then
        pcall(function()
            savedCCAnchors.classificationFrame:ClearAllPoints()
            savedCCAnchors.classificationFrame:SetPoint("RIGHT", savedCCAnchors.raidTargetFrame, "LEFT")
            savedCCAnchors.classificationFrame:SetScale(1)
        end)
    end
    -- Restore RaidTargetFrame: default is RIGHT of HealthBarsContainer.LEFT (center height)
    if savedCCAnchors.raidTarget and savedCCAnchors.healthBar then
        pcall(function()
            savedCCAnchors.raidTarget:ClearAllPoints()
            savedCCAnchors.raidTarget:SetPoint("RIGHT", savedCCAnchors.healthBar, "LEFT", 0, 0)
        end)
    end
    savedCCAnchors = nil
end

--- Place the CC/LoC list frames beside/above the right-side cluster. Split from
--- DisplaceCCFrames so RenderDefensives can RE-place them whenever the bar stack
--- changes. Every offset is ANALYTIC, from layout state captured in
--- rightRowAnchor/defRowAnchor - nothing is measured. The old measured version was
--- broken two ways: GetRect on nameplate-parented frames is refused in combat
--- (so every in-combat placement silently skipped), and on a fresh anchor pass the
--- health bar had just been unanchored, so the reversed-anchor case always failed
--- with no retry.
---
--- Anchors to the NAMEPLATE, never to our own icons or bars: these are Blizzard's
--- restricted frames, and anchoring one to ours makes ours - plus everything its
--- rect depends on - geometry-protected in combat, while we move these icons every
--- frame. Same approach as PositionEnrageIndicator.
---
--- Scale: match CC icon visual size to our queue's iconSize.
---   CrowdControlListFrame children are individually scaled by auraItemScale
---   (applied per-child in NamePlateAurasMixin), so the parent frame needs:
---     parentScale = iconSize / (AURA_ITEM_HEIGHT * auraItemScale)
---   LossOfControlFrame is a simple 30x30 container, scale = iconSize / 30.
local function PlaceCCListFrames(expansion)
    if not savedCCAnchors then return end
    local ccList, locFrame = savedCCAnchors.ccList, savedCCAnchors.locFrame
    if not ccList and not locFrame then return end
    local npAnchor = rightRowAnchor.frame
    if not npAnchor then return end
    local uf = currentNameplate and currentNameplate.UnitFrame
    local af = uf and uf.AurasFrame
    if not af then return end

    local iconSize = savedCCAnchors.iconSize or 32
    -- Scale CC/stun + LoC to the queue icon size, compensating for the nameplate scale
    -- space (see AuraListScaleForQueue) - otherwise both render bigger than our icons.
    local ccScale  = AuraListScaleForQueue(af, iconSize)
    local locScale = (iconSize / BLIZZARD_LOC_SIZE) * AuraFrameScaleRatio(af)
    local uiRatio  = AuraFrameScaleRatio(af)

    local rowGapX = rightRowAnchor.gapX or 0
    local rowIcon = rightRowAnchor.iconSize or iconSize
    -- Bar-stack clearance: nonzero only when the DEFENSIVE cluster is the right row
    -- (reversed anchor) and RenderDefensives has laid its bars out.
    local stackOut, stackShift = 0, 0
    if rightRowAnchor.isDefSide then
        stackOut   = defRowAnchor.stackOut or 0
        stackShift = defRowAnchor.stackShift or 0
    end

    -- SetPoint offsets are read in the positioned frame's own scaled space, and each of
    -- these frames carries a different scale, so the conversion is per frame.
    local function Place(frame, frameScale, point, x, y)
        local per = uiRatio / (frameScale > 0 and frameScale or 1)
        frame:ClearAllPoints()
        frame:SetScale(frameScale)
        frame:SetPoint(point, npAnchor, rightRowAnchor.edge, x * per, y * per)
    end

    local ok = pcall(function()
        local point, x, y
        if expansion == "out" then
            -- Horizontal row: CC goes ABOVE the cluster (above the bar stack when
            -- present), centred on the stack / first icon.
            point = "BOTTOM"
            x = rowGapX + rowIcon * 0.5 + stackShift
            y = rowIcon * 0.5 + stackOut + CC_GAP
        else
            -- Vertical column ("up"/"down"): CC goes to the RIGHT, past the bar
            -- stack, vertically centred on it.
            point = "LEFT"
            x = rowGapX + rowIcon + stackOut + CC_GAP
            y = (expansion == "up") and stackShift or -stackShift
        end
        if ccList then Place(ccList, ccScale, point, x, y) end
        if locFrame then
            if ccList then
                -- Blizzard frame to Blizzard frame: chaining these two is already safe.
                locFrame:ClearAllPoints()
                locFrame:SetScale(locScale)
                if expansion == "out" then
                    locFrame:SetPoint("BOTTOM", ccList, "TOP", 0, 2)
                else
                    locFrame:SetPoint("LEFT", ccList, "RIGHT", 2, 0)
                end
            else
                Place(locFrame, locScale, point, x, y)
            end
        end
    end)
    if not ok then
        -- Restricted frame (arena): fully unwind. The old "savedCCAnchors = nil"
        -- destroyed the restore record AFTER the badge/marker were already moved,
        -- stranding them on a RECYCLED plate for whatever unit it served next.
        RestoreCCFrames()
    end
end

--- Save original CC anchors and re-anchor relative to our icon cluster.
--- Always displaces (both default and reversed anchors have a cluster on the right).
local function DisplaceCCFrames(nameplate, anchor, expansion, showDefensives, iconSize)
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
    local rightIcons
    if isLeft then
        rightIcons = showDefensives and #defIcons > 0 and defIcons or nil
    else
        rightIcons = #dpsIcons > 0 and dpsIcons or nil
    end
    if not rightIcons then return end  -- nothing on the right side → no overlap

    -- Record EVERYTHING we are about to touch BEFORE any mutation. Restores are
    -- idempotent (restoring an unmoved frame just re-asserts its XML default), so a
    -- partial failure can always unwind - recording on success left frames stranded
    -- when a later step failed.
    local npHealthBar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    savedCCAnchors = { healthBar = npHealthBar, iconSize = iconSize or 32 }
    if ccList   then savedCCAnchors.ccList   = ccList   end
    if locFrame then savedCCAnchors.locFrame = locFrame end

    -- Displace ClassificationFrame (elite/boss/rare badge) when our defensive icons
    -- occupy the LEFT side of the health bar - the badge's default position floats
    -- to the LEFT of the bar center and collides with defIcons[1].
    -- Fix: overlay the badge on the top-left corner of the health bar at 80% scale.
    -- Covers default mode (DEF on left) and reversed anchor mode (DPS on left).
    local defOnLeft = not isLeft and showDefensives and #defIcons > 0
    if (defOnLeft or isLeft) and npHealthBar and uf.ClassificationFrame and uf.RaidTargetFrame then
        local classFrame = uf.ClassificationFrame
        savedCCAnchors.classificationFrame = classFrame
        savedCCAnchors.raidTargetFrame     = uf.RaidTargetFrame
        pcall(function()
            classFrame:ClearAllPoints()
            classFrame:SetPoint("CENTER", npHealthBar, "TOPLEFT", 0, 0)
            classFrame:SetScale(0.80)
        end)
    end

    -- Displace RaidTargetFrame (skull/cross/star raid markers) - default anchor is
    -- RIGHT of HealthBarsContainer.LEFT at center height, directly in front of our
    -- left-side defensive cluster.
    -- Fix: move it above the health bar, centered, so it clears both clusters.
    if npHealthBar and uf.RaidTargetFrame then
        local raidTarget = uf.RaidTargetFrame
        savedCCAnchors.raidTarget = raidTarget
        pcall(function()
            raidTarget:ClearAllPoints()
            raidTarget:SetPoint("BOTTOM", npHealthBar, "TOP", 0, 2)
        end)
    end

    PlaceCCListFrames(expansion)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: SetPoint all cluster elements to a live nameplate frame.
-- Uses a chain-anchor approach:
--   ROOT elements (healthBar, dpsIcons[1], defIcons[1]) anchor to the nameplate.
--   Subsequent icons in each cluster chain off the previous icon.
-- When the nameplate moves, the entire cluster follows automatically.
-- Health bar (when shown) floats above the nameplate for all anchor directions.
-- ─────────────────────────────────────────────────────────────────────────────
local function AnchorToNameplate(nameplate, anchor, iconSize, showDefensives, expansion, iconSpacing, npo)
    -- anchor:            "LEFT" or "RIGHT" - which side of the nameplate
    -- expansion:         "out" (horizontal), "up" (vertical upward), "down" (vertical downward)
    -- iconSpacing:       px between successive icons (defaults to ICON_SPACING constant)
    -- npo:               overlay profile block (per-icon scales for the anchor records)
    expansion         = expansion or "down"
    iconSpacing       = iconSpacing or ICON_SPACING
    -- Icons are SetScale'd (defensive cluster / first DPS icon), which scales their
    -- SetPoint offsets too - the anchor records below carry EFFECTIVE plate-space
    -- geometry so the CC/enrage consumers line up with what actually renders.
    local defScale  = (npo and npo.defensiveIconScale) or 1
    local dpsScale1 = (npo and npo.firstIconScale) or 1
    -- Anchor to HealthBarsContainer so icons center on the health bar strip,
    -- not on the root nameplate frame (which also includes auras/name/castbar).
    local uf          = nameplate.UnitFrame
    local anchorFrame = (uf and uf.HealthBarsContainer) or nameplate

    local isLeft    = (anchor == "LEFT")
    -- Point on the icon that touches the nameplate / previous icon
    local dpsPt     = isLeft and "RIGHT" or "LEFT"
    local defPt     = isLeft and "LEFT"  or "RIGHT"
    -- Nameplate edge each cluster attaches to
    local dpsEdge   = isLeft and "LEFT"  or "RIGHT"
    local defEdge   = isLeft and "RIGHT" or "LEFT"
    -- X offset from the health bar edge (including gap)
    -- Right side uses a larger gap because Blizzard's bgTexture extends ~4px further
    -- past the RIGHT edge of HealthBarsContainer than the LEFT edge.
    local gapRight  = NAMEPLATE_GAP_RIGHT
    local gapLeft   = NAMEPLATE_GAP_LEFT
    local dpsGapX   = isLeft and -gapLeft  or  gapRight
    local defGapX   = isLeft and  gapRight or -gapLeft
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
    -- Closes over anchorFrame, expansion, and the chain params computed above.
    local function AnchorRow(icons, firstPt, firstEdge, firstGapX, outChainPt, outChainEdge, outChainX)
        for i, icon in ipairs(icons) do
            icon:ClearAllPoints()
            if i == 1 then
                icon:SetPoint(firstPt, anchorFrame, firstEdge, firstGapX, 0)
            elseif expansion == "out" then
                icon:SetPoint(outChainPt, icons[i-1], outChainEdge, outChainX, 0)
            else
                icon:SetPoint(chainPt, icons[i-1], chainRelPt, chainOffX, chainOffY)
            end
        end
    end

    AnchorRow(dpsIcons, dpsPt, dpsEdge, dpsGapX, dpsPt, dpsEdge, dpsChainX)

    -- The right-hand row, for the CC frames. Both layouts put a row on the right attached
    -- by its LEFT edge to the nameplate's RIGHT - it's the DPS row by default and the
    -- defensive row when the clusters are reversed. Effective (scaled) geometry - see above.
    local rightScale = isLeft and defScale or dpsScale1
    rightRowAnchor.frame     = anchorFrame
    rightRowAnchor.edge      = isLeft and defEdge or dpsEdge
    rightRowAnchor.gapX      = (isLeft and defGapX or dpsGapX) * rightScale
    rightRowAnchor.iconSize  = iconSize * rightScale
    rightRowAnchor.isDefSide = isLeft

    if showDefensives then
        AnchorRow(defIcons, defPt, defEdge, defGapX, defPt, defEdge, defChainX)

        -- Hand the row's nameplate attachment to the enrage indicator, which has to reach
        -- the same spot without anchoring to our icons. Captured here so the two can't drift
        -- apart: whatever the row attaches to is what it attaches to. Effective geometry.
        defRowAnchor.frame,  defRowAnchor.edge     = anchorFrame, defEdge
        defRowAnchor.gapX,   defRowAnchor.isLeft   = defGapX * defScale, isLeft
        defRowAnchor.iconSize = iconSize * defScale
        -- Bar stack is not laid out yet on a fresh anchor; RenderDefensives fills these
        -- in (and re-places the CC list) once its bars exist.
        defRowAnchor.stackOut, defRowAnchor.stackShift = 0, 0

        -- Maintenance slot: the defensive row's "position 0". Mirrors the interrupt icon's
        -- relationship to dpsIcons[1] below, using the same expansion rules, so defIcons[1]
        -- never shifts when the slot appears or hides.
        if maintenanceIcon then
            maintenanceIcon:ClearAllPoints()
            maintenanceIcon:SetSize(iconSize, iconSize)
            if #defIcons > 0 then
                if expansion == "out" then
                    maintenanceIcon:SetPoint("BOTTOM", defIcons[1], "TOP", 0, iconSpacing)
                else
                    maintenanceIcon:SetPoint(chainRelPt, defIcons[1], chainPt, -chainOffX, -chainOffY)
                end
            else
                maintenanceIcon:SetPoint(defPt, anchorFrame, defEdge, defGapX, 0)
            end
        end
    end

    -- Interrupt icon: "position 0" - sits outside the queue so it never
    -- displaces dpsIcons[1].  Icon 1 anchors directly to the nameplate and
    -- never shifts when the interrupt appears/hides.
    --   "out"       → above icon 1 (perpendicular, away from nameplate)
    --   "up"/"down" → inline toward nameplate (below icon 1 for "up", above for "down")
    if interruptIcon then
        interruptIcon:ClearAllPoints()
        interruptIcon:SetSize(iconSize, iconSize)
        if #dpsIcons > 0 then
            if expansion == "out" then
                -- Horizontal queue → interrupt above icon 1 (perpendicular pop-out)
                interruptIcon:SetPoint("BOTTOM", dpsIcons[1], "TOP", 0, iconSpacing)
            else
                -- Vertical queue → interrupt inline before icon 1 in chain direction
                -- (below icon 1 for "up", above icon 1 for "down")
                interruptIcon:SetPoint(chainRelPt, dpsIcons[1], chainPt, -chainOffX, -chainOffY)
            end
        else
            -- Fallback: no DPS icons, anchor to health bar frame directly
            interruptIcon:SetPoint(dpsPt, anchorFrame, dpsEdge, dpsGapX, 0)
        end
        -- Re-anchor cast aura: sits on the opposite side of the interrupt
        -- from the queue (perpendicular pop-out).
        --   "out"       → above interrupt (further from nameplate)
        --   "down"      → above interrupt
        --   "up"        → below interrupt (away from upward-growing queue)
        if interruptIcon.castAura then
            interruptIcon.castAura:ClearAllPoints()
            if expansion == "up" then
                interruptIcon.castAura:SetPoint("TOP", interruptIcon, "BOTTOM", 0, -2)
            else
                interruptIcon.castAura:SetPoint("BOTTOM", interruptIcon, "TOP", 0, 2)
            end
        end
        -- The soothe cue's cleansed-aura clones hang off the same slot and must follow
        -- the same expansion rule - they were built with the STANDARD queue's
        -- orientation and popped over dpsIcons[1] on "up" overlays.
        if interruptIcon.sootheCue and UISootheCue.ReanchorAuras then
            UISootheCue.ReanchorAuras(interruptIcon.sootheCue, expansion)
        end
        interruptIcon:Hide()
    end

    -- Hide health bars so RenderDefensives can show them at the correct
    -- expansion-aware position. lastDefVisibleCount=0 (set on new nameplate)
    -- ensures RenderDefensives always re-anchors on its first call.
    if healthBar    then healthBar:ClearAllPoints();    healthBar:Hide()    end
    if petHealthBar then petHealthBar:ClearAllPoints(); petHealthBar:Hide() end
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
        -- pcall: nameplate CVars have been combat/instance-restricted on some clients,
        -- and this path is reachable mid-combat (options rebuild).
        pcall(SetCVar, "nameplateShowEnemies", "1")
    end

    local iconSize = npo.iconSize or 32
    local maxDPS   = math_min(npo.maxIcons or 3, 7)
    local maxDef   = npo.showDefensives and math_min(npo.maxDefensiveIcons or 3, 7) or 0

    for i = 1, maxDPS do dpsIcons[i] = CreateOverlayIcon(iconSize, profile) end
    for i = 1, maxDef do defIcons[i] = CreateOverlayIcon(iconSize, profile) end

    -- Tank maintenance slot: the defensive row's "position 0", exactly as the interrupt icon
    -- is the DPS row's. Built whenever defensives are shown rather than gated on spec here -
    -- spec can change without rebuilding the overlay, and the renderer hides it for anyone
    -- without a maintenance buff.
    if maxDef > 0 then
        maintenanceIcon = CreateOverlayIcon(iconSize, profile)
        -- Same blue "running out" swipe the standard-queue slot gets: it is the same button on
        -- a different surface, and this was previously only applied there.
        UIFrameFactory.ApplyMaintenanceSwipeStyle(maintenanceIcon)
    end

    -- Interrupt reminder icon (position 0, hidden until interruptible cast detected)
    -- interruptMode is centralized in profile (no longer per-surface)
    -- Same rule as the standard queue's slot: the enrage cleanse cue shares this icon but is
    -- an independent choice, so build it when either feature wants it. The kick self-gates on
    -- interruptMode in RenderInterruptSlot, so "off + cleanse on" shows only the cleanse.
    local interruptMode = profile.interruptMode or "kickPrefer"
    local kickWanted = interruptMode ~= "disabled"
    if kickWanted or (profile.showSootheCue ~= false and SpellDB.ResolveSootheSpells() ~= nil) then
        interruptIcon = CreateOverlayIcon(iconSize, profile)
        resolvedInterrupts = SpellDB.ResolveInterruptSpells()
        resolvedSoothe = SpellDB.ResolveSootheSpells()

        -- Cast aura: small icon attached to the interrupt button showing what the enemy is
        -- casting. The construction-time anchor here is provisional - UpdateAnchor re-seats it
        -- on every layout from the overlay's own expansion direction.
        local castAura = UIFrameFactory.CreateAuraSubIcon(
            interruptIcon, iconSize, profile, profile.queueOrientation or "LEFT")
        castAura:SetFrameStrata("BACKGROUND")
        castAura:EnableMouse(false)
        castAura:Hide()
        interruptIcon.castAura = castAura
    end

    if npo.showHealthBar then
        healthBar = CreateOverlayHealthBar(iconSize * 2)
        -- Pet health bar: warm yellow, only visible when pet exists + setting enabled
        if npo.showPetHealthBar ~= false then
            petHealthBar = CreateOverlayHealthBar(iconSize * 2)
            petHealthBar:SetStatusBarColor(0.90, 0.75, 0.10, 0.9)
        end

        -- Resource bars anchor to the health bars, so they require them. Primary =
        -- current displayed power; secondary = the class point resource (if any).
        if npo.showPowerBar then
            overlayPowerBar = CreateOverlayPowerBar(nil)
            local secType = UIHealthBar.GetClassSecondary()
            if secType then
                overlaySecondaryPowerBar = CreateOverlayPowerBar(secType)
            end
        end
    end

    -- Quest indicator replacement: suppress engine-rendered quest circles and
    -- render our own "!" icon on the nameplate.  Our version is positioned so
    -- it cannot overlap the icon queue.  Always active when overlay is enabled.
    do
        if savedShowQuestUnitCircles == nil then
            savedShowQuestUnitCircles = GetCVar("ShowQuestUnitCircles")
        end
        if GetCVar("ShowQuestUnitCircles") ~= "0" then
            pcall(SetCVar, "ShowQuestUnitCircles", "0")
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
        if UIAnimations then UIAnimations.StopAllGlows(icon) end
        icon:ClearAllPoints()
        icon:Hide()
        icon:SetParent(nil)
    end

    -- Remove all overlay icons from Masque before cleanup.
    -- In combat, Masque's SkinButton calls Button:GetSize() which returns a secret value (12.0).
    -- Skip RemoveButton in combat; track in pendingMasqueRemoval for cleanup on next OOC Destroy.
    local inCombat = InCombatLockdown()
    local MasqueGroup = GetMasqueOverlayGroup and GetMasqueOverlayGroup()
    if not inCombat and MasqueGroup and next(pendingMasqueRemoval) then
        for icon in pairs(pendingMasqueRemoval) do MasqueGroup:RemoveButton(icon) end
        wipe(pendingMasqueRemoval)
    end
    for _, icon in ipairs(dpsIcons) do
        if MasqueGroup then
            if inCombat then pendingMasqueRemoval[icon] = true else MasqueGroup:RemoveButton(icon) end
        end
        CleanIcon(icon)
    end
    for _, icon in ipairs(defIcons) do
        if MasqueGroup then
            if inCombat then pendingMasqueRemoval[icon] = true else MasqueGroup:RemoveButton(icon) end
        end
        CleanIcon(icon)
    end

    if interruptIcon then
        if interruptIcon.sootheCue then
            interruptIcon.sootheCue:Hide()
            interruptIcon.sootheCue:SetParent(nil)
        end
        if MasqueGroup then
            if inCombat then pendingMasqueRemoval[interruptIcon] = true else MasqueGroup:RemoveButton(interruptIcon) end
        end
        CleanIcon(interruptIcon)
        interruptIcon = nil
    end
    if maintenanceIcon then
        if MasqueGroup then
            if inCombat then pendingMasqueRemoval[maintenanceIcon] = true
            else MasqueGroup:RemoveButton(maintenanceIcon) end
        end
        CleanIcon(maintenanceIcon)
        maintenanceIcon = nil
    end
    resolvedInterrupts = nil
    resolvedSoothe = nil
    lastDefVisibleCount = 0
    cachedDefensiveQueue = nil

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
    if overlayPowerBar then
        overlayPowerBar:ClearAllPoints()
        overlayPowerBar:Hide()
        overlayPowerBar:SetParent(nil)
        overlayPowerBar = nil
    end
    if overlaySecondaryPowerBar then
        overlaySecondaryPowerBar:ClearAllPoints()
        overlaySecondaryPowerBar:Hide()
        overlaySecondaryPowerBar:SetParent(nil)
        overlaySecondaryPowerBar = nil
    end
    overlaySecondarySegments = 0
    lastOverlayPowerUpdate = 0

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
    defRowAnchor.frame = nil
    rightRowAnchor.frame = nil

    -- Restore the user's original nameplateShowEnemies CVar.
    -- Only restore when we actually saved a value (Create was called). Keep the saved
    -- value when a (possibly combat-restricted) write fails, so the next Destroy - or
    -- a Create that finds the value still saved - can retry instead of losing it.
    if savedNameplateShowEnemies ~= nil then
        local restored = true
        if GetCVar("nameplateShowEnemies") ~= savedNameplateShowEnemies then
            restored = pcall(SetCVar, "nameplateShowEnemies", savedNameplateShowEnemies)
        end
        if restored then savedNameplateShowEnemies = nil end
    end

    -- Restore the user's original ShowQuestUnitCircles CVar (same retry contract).
    if savedShowQuestUnitCircles ~= nil then
        local restored = true
        if GetCVar("ShowQuestUnitCircles") ~= savedShowQuestUnitCircles then
            restored = pcall(SetCVar, "ShowQuestUnitCircles", savedShowQuestUnitCircles)
        end
        if restored then savedShowQuestUnitCircles = nil end
    end

    if addon then
        addon.nameplateIcons    = nil
        addon.nameplateDefIcons = nil
    end
end

--- Re-anchor the entire cluster to the current target's nameplate.
--- Called on PLAYER_TARGET_CHANGED, NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED.
--- No InCombatLockdown() guard: nameplates are non-secure frames.
--- Shared interrupt-slot teardown (glows, cast bar, soothe cue).
--- clearPoints detaches it from the nameplate as well (UpdateAnchor path).
local function HideInterruptSlot(clearPoints)
    if not interruptIcon then return end
    if UIAnimations then
        UIAnimations.HideInterruptProcGlow(interruptIcon)
        UIAnimations.HideInterruptCastBar(interruptIcon)
        if interruptIcon.hasProcGlow then UIAnimations.HideProcGlow(interruptIcon); interruptIcon.hasProcGlow = false end
        interruptIcon.hasInterruptGlow = false
    end
    if clearPoints then interruptIcon:ClearAllPoints() end
    interruptIcon:Hide()
    -- The soothe cue is a sibling pinned over the icon (UIParent-parented),
    -- so hiding the icon does not hide it.
    if interruptIcon.sootheCue then UISootheCue.Hide(interruptIcon.sootheCue) end
end

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
        lastDefVisibleCount = 0  -- force health bar re-anchor on new nameplate
        lastEnrageCount     = -1 -- force enrage-indicator re-anchor on new nameplate
        local anchor       = npo.reverseAnchor and "LEFT" or "RIGHT"
        local iconSize     = npo.iconSize or 32
        local showDefensives = npo.showDefensives

        local expansion         = npo.expansion or "down"
        AnchorToNameplate(nameplate, anchor, iconSize, showDefensives, expansion, npo.iconSpacing or ICON_SPACING, npo)
        -- Displace Blizzard CC frames so they don't overlap our icon cluster.
        -- (Bar-stack clearance is applied later by RenderDefensives, which re-places
        -- the CC list once its bars are laid out - the stack state is zero here.)
        DisplaceCCFrames(nameplate, anchor, expansion, showDefensives, iconSize)
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
        defRowAnchor.frame = nil
    rightRowAnchor.frame = nil
        RestoreCCFrames()  -- put CC frames back when we detach

        -- Hide quest indicator when no valid nameplate
        if questIndicator then
            questIndicator:ClearAllPoints()
            questIndicator:Hide()
        end

        -- Detach and hide every element
        for _, icon in ipairs(dpsIcons) do
            if UIAnimations then UIAnimations.StopAllGlows(icon) end
            icon:ClearAllPoints()
            icon:Hide()
        end
        for _, icon in ipairs(defIcons) do
            -- StopAllGlows also resets UIRenderer's glow arbiter, so the next
            -- RenderDefensives restarts the glow on the new target.
            if UIAnimations then UIAnimations.StopAllGlows(icon) end
            icon:ClearAllPoints()
            icon:Hide()
        end
        -- The maintenance slot is anchored off defIcons[1], which was just cleared.
        -- Clear THROUGH the shared helper: a bare Hide() left the maintenance glow
        -- frame shown and _maintGlow true, so the re-show skipped re-arming.
        if maintenanceIcon then
            if UIRenderer and UIRenderer.ClearMaintenanceSlot then
                UIRenderer.ClearMaintenanceSlot(maintenanceIcon)
            end
            maintenanceIcon:ClearAllPoints()
            maintenanceIcon:Hide()
        end
        if healthBar then
            healthBar:ClearAllPoints()
            healthBar:Hide()
        end
        if petHealthBar then
            petHealthBar:ClearAllPoints()
            petHealthBar:Hide()
        end
        HideInterruptSlot(true)
    end
end

--- Update DPS icon textures, cooldowns, glows, and hotkey tracking.
--- Called from JustAC:UpdateSpellQueue() with the same spellIDs array
--- already passed to UIRenderer.RenderSpellQueue - zero extra queue cost.
function UINameplateOverlay.Render(addon, spellIDs)
    if not currentNameplate then return end
    if not addon then return end
    local profile = addon:GetProfile()
    if not profile or not profile.nameplateOverlay then return end
    local npo = profile.nameplateOverlay
    local displayMode = profile.displayMode or "queue"
    if displayMode ~= "overlay" and displayMode ~= "both" then return end
    if #dpsIcons == 0 then return end

    -- Overlay-specific visibility (independent settings, but the same-named options
    -- behave identically to the standard queue's SpellQueue.EvaluateQueueVisibility).
    -- "requireHostile" needs no branch here: the overlay only renders on an attackable
    -- target's nameplate, so a saved value behaves as "always" (option retired from the
    -- overlay dropdown for the same reason).
    local queueVis = npo.queueVisibility or "always"
    local shouldHide = false
    if queueVis == "combatOnly" and not UnitAffectingCombat("player") then
        shouldHide = true
    end
    if not shouldHide and npo.hideWhenMounted then
        local isMounted = IsMounted()
        if not isMounted then
            -- Druid travel (3) / flight (27) form counts as mounted, matching the standard queue.
            local formID = GetShapeshiftFormID()
            if formID == 3 or formID == 27 then isMounted = true end
        end
        if isMounted then shouldHide = true end
    end
    if shouldHide then
        for _, icon in ipairs(dpsIcons) do icon:Hide() end
        if interruptIcon then
            interruptIcon:Hide()
            if interruptIcon.sootheCue then UISootheCue.Hide(interruptIcon.sootheCue) end
        end
        return
    end

    local hasSpells   = spellIDs and #spellIDs > 0
    local npoGlowMode       = UIRenderer.ResolveGlowMode(profile, npo.glowMode)
    local npoShowPrimaryGlow = (npoGlowMode == "all" or npoGlowMode == "primaryOnly")
    local npoShowProcGlow    = (npoGlowMode == "all" or npoGlowMode == "procOnly")
    local showGapCloserGlow  = npoShowPrimaryGlow and profile.gapClosers and profile.gapClosers.showGlow == true
    local npoDesaturation = npo.queueIconDesaturation or 0
    local npoFirstIconScale = npo.firstIconScale or 1.0
    local centralOverlays = profile.textOverlays
    local showHotkey   = not centralOverlays or not centralOverlays.hotkey or centralOverlays.hotkey.show ~= false
    local showUsabilityTint = profile.showUsabilityTint ~= false
    local showCastingHighlight = profile.showCastingHighlight ~= false
    local opacity      = npo.opacity or 1.0
    local now        = GetTime()
    local shouldUpdateCooldowns = (now - lastCooldownUpdate) >= COOLDOWN_UPDATE_INTERVAL
    if shouldUpdateCooldowns then lastCooldownUpdate = now end
    local inCombat = UnitAffectingCombat("player")

    local isChanneling, channelSpellID, isCasting, castSpellID
    if UIRenderer and UIRenderer.ResolvePlayerCastState then
        isChanneling, channelSpellID, isCasting, castSpellID = UIRenderer.ResolvePlayerCastState(profile)
    else
        isChanneling, channelSpellID, isCasting, castSpellID = false, nil, false, nil
    end

    -- (Defensive icon visual states are handled by RefreshDefensives, which the
    -- update loop runs right after this render on the same tick - a second loop
    -- here double-processed every shown defensive icon per pass.)

    -- ── Interrupt reminder (position 0) + soothe cue (shared renderer) ──────
    -- interruptMode is centralized in profile (no longer per-surface). The overlay
    -- is already known-visible here (hidden overlays returned early above), so
    -- active is always true; per-surface opacity comes from npo.opacity.
    if interruptIcon then
        local ictx = interruptCtx
        ictx.now                = now
        ictx.updateCooldowns    = shouldUpdateCooldowns
        ictx.active             = true
        ictx.resolvedInterrupts = resolvedInterrupts
        ictx.interruptMode      = profile.interruptMode
        ictx.spellIDs           = spellIDs
        ictx.profile            = profile
        ictx.showHotkeys        = showHotkey
        ictx.hotkeyColor        = centralOverlays and centralOverlays.hotkey and centralOverlays.hotkey.color
        ictx.opacity            = opacity
        ictx.sootheSpellID      = resolvedSoothe and resolvedSoothe[1] and resolvedSoothe[1].spellID
        UIRenderer.RenderInterruptSlot(interruptIcon, ictx)
    end

    -- Shared per-icon render (UIRenderer.RenderQueueIcon): position hold, glow
    -- resolution + hysteresis (including the out-of-combat bypass that prevents a
    -- proc glow sticking at positions 2+ after combat), hotkey caching, range and
    -- usability tinting, channel fill, cooldown wiring. ctx carries the overlay's
    -- per-surface parameters: nameplateOverlay option keys, first-icon scale,
    -- per-frame opacity, and hidden (not placeholder) empty slots.
    local ctx = renderCtx
    ctx.now                 = now
    ctx.inCombat            = inCombat
    ctx.updateCooldowns     = shouldUpdateCooldowns
    ctx.spellIDs            = spellIDs
    ctx.hasSpells           = hasSpells
    ctx.showPrimaryGlow     = npoShowPrimaryGlow
    ctx.showProcGlow        = npoShowProcGlow
    ctx.showGapCloserGlow   = showGapCloserGlow
    ctx.queueDesaturation   = npoDesaturation
    ctx.showHotkeys         = showHotkey
    ctx.lookupHotkeys       = true
    ctx.refreshHotkeys      = shouldUpdateCooldowns
    ctx.hotkeyColor         = centralOverlays and centralOverlays.hotkey and centralOverlays.hotkey.color
    ctx.showUsabilityTint   = showUsabilityTint
    ctx.showCastingHighlight = showCastingHighlight
    ctx.showOffGcdDot       = profile.showOffGcdDot
    -- Via the shared resolver, not a local copy: the move-cast default is PER-SPEC
    -- (ranged/healers on, melee off) and duplicating that rule here would let the two
    -- surfaces disagree about the same setting.
    ctx.showMoveCastDot     = UIRenderer.MoveCastDotEnabled and UIRenderer.MoveCastDotEnabled(profile)
    ctx.isChanneling        = isChanneling
    ctx.channelSpellID      = channelSpellID
    ctx.isCasting           = isCasting
    ctx.castSpellID         = castSpellID
    ctx.firstIconScale      = npoFirstIconScale
    ctx.opacity             = opacity
    ctx.hideEmptySlots      = true

    for i, icon in ipairs(dpsIcons) do
        UIRenderer.RenderQueueIcon(icon, i, ctx)
    end
end

--- Update defensive icon display from the same queue computed in OnHealthChanged.
--- Delegates directly to UIRenderer.ShowDefensiveIcon / HideDefensiveIcon so
--- defensive icons on the overlay have full feature parity with the main panel
--- (hotkeys, proc glow, assisted glow, fade animations).
function UINameplateOverlay.RenderDefensives(addon, defensiveQueue)
    if not currentNameplate then return end
    if #defIcons == 0 then return end

    -- Cache for RefreshDefensives (same-tick re-render from UpdateSpellQueue)
    cachedDefensiveQueue = defensiveQueue

    local npo          = addon:GetProfile() and addon:GetProfile().nameplateOverlay or {}
    local profile      = addon:GetProfile() or {}
    local npoGlowMode   = UIRenderer.ResolveGlowMode(profile, npo.defensiveGlowMode)
    local npoDefScale   = npo.defensiveIconScale or 1.0
    local opacity       = npo.opacity or 1.0
    local iconSpacing   = npo.iconSpacing or ICON_SPACING

    local visibleCount = 0
    for i, icon in ipairs(defIcons) do
        local entry = defensiveQueue and defensiveQueue[i]
        if entry and entry.spellID then
            icon.overlayOpacity = opacity
            if icon:GetScale() ~= npoDefScale then icon:SetScale(npoDefScale) end
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, i == 1, npoGlowMode, entry.waiting, entry.precombat)
            icon:SetAlpha(opacity)
            visibleCount = visibleCount + 1
        else
            UIRenderer.HideDefensiveIcon(icon)
        end
    end

    -- Maintenance slot rides with the defensive cluster, same as on the standard queue. Scale
    -- and opacity are stashed BEFORE the call, because the renderer applies overlayOpacity.
    if maintenanceIcon then
        if maintenanceIcon:GetScale() ~= npoDefScale then maintenanceIcon:SetScale(npoDefScale) end
        maintenanceIcon.overlayOpacity = opacity
    end
    UIRenderer.RenderMaintenanceSlot(addon, maintenanceIcon)

    -- Sync health bar size and position with the visible defensive slot count.
    -- Only re-anchor when visibleCount changes to avoid per-tick repositioning flicker.
    if healthBar then
        if visibleCount > 0 then
            if npo and npo.showHealthBar then
                if visibleCount ~= lastDefVisibleCount then
                    lastDefVisibleCount = visibleCount
                    local iconSize  = npo.iconSize or 32
                    local anchor    = npo.reverseAnchor and "LEFT" or "RIGHT"
                    local expansion = npo.expansion or "down"
                    local isLeft    = (anchor == "LEFT")
                    -- EFFECTIVE sizes: the icons render at SetScale(defensiveIconScale),
                    -- which scales their chain offsets too - span math must match or the
                    -- bars read too long/short at any non-1.0 scale.
                    local effSize    = iconSize * npoDefScale
                    local effSpacing = iconSpacing * npoDefScale

                    healthBar:ClearAllPoints()

                    -- Compute bar dimensions once for both player and pet bars
                    local barWidth, barHeight
                    if expansion == "out" then
                        -- Horizontal cluster: symmetric 10% inset on both outer edges.
                        -- clusterWidth = n*size + (n-1)*spacing; barWidth = clusterWidth - 2*inset.
                        local clusterWidth = visibleCount * effSize + (visibleCount - 1) * effSpacing
                        local inset = (visibleCount == 1) and 0 or math_floor(effSize * 0.10)
                        barWidth = math_floor(clusterWidth - 2 * inset)
                        healthBar:SetOrientation("HORIZONTAL")
                        healthBar:SetSize(barWidth, BAR_HEIGHT)
                        SetBevelOrientation(healthBar, true)
                        if isLeft then
                            healthBar:SetPoint("BOTTOMLEFT", defIcons[1], "TOPLEFT", inset, BAR_SPACING)
                        else
                            healthBar:SetPoint("BOTTOMRIGHT", defIcons[1], "TOPRIGHT", -inset, BAR_SPACING)
                        end
                    else
                        -- Vertical cluster: VERTICAL bar spans beside the column on the outer side.
                        local clusterHeight = visibleCount * effSize + (visibleCount - 1) * effSpacing
                        local inset = (visibleCount == 1) and 0 or math_floor(effSize * 0.10)
                        barHeight = math_floor(clusterHeight - 2 * inset)
                        healthBar:SetOrientation("VERTICAL")
                        SetBevelOrientation(healthBar, false)
                        healthBar:SetSize(BAR_HEIGHT, barHeight)
                        if expansion == "up" then
                            if isLeft then
                                healthBar:SetPoint("BOTTOMLEFT",  defIcons[1], "BOTTOMRIGHT",  BAR_SPACING,  inset)
                            else
                                healthBar:SetPoint("BOTTOMRIGHT", defIcons[1], "BOTTOMLEFT",  -BAR_SPACING,  inset)
                            end
                        else  -- "down"
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
                    if petHealthBar then
                        if UnitExists("pet") then
                            AnchorOverlayBar(petHealthBar, healthBar, expansion, isLeft, barWidth, barHeight, BAR_HEIGHT)
                            SetBevelOrientation(petHealthBar, expansion == "out")
                            petHealthBar:SetAlpha(opacity)
                            if not petHealthBar:IsShown() then petHealthBar:Show() end
                        else
                            petHealthBar:Hide()
                        end
                    end

                    -- Resource/power bars: stack beyond the outermost shown health
                    -- bar at the current orientation (re-segments the secondary).
                    PositionOverlayPowerBars(npo, expansion, isLeft, barWidth, barHeight, opacity)

                    -- Analytic bar-stack extent for the CC/enrage/maintenance consumers:
                    -- DERIVED, never measured - rects of nameplate-parented frames are
                    -- refused in combat, which silently killed every in-combat
                    -- re-placement under the old GetRect approach.
                    --   stackOut   = how far the stack extends beyond defIcons[1]'s outer edge
                    --   stackShift = the bars' centre offset from icon 1's centre along the row
                    local stackOut = BAR_SPACING + BAR_HEIGHT
                    if petHealthBar and petHealthBar:IsShown() then
                        stackOut = stackOut + BAR_SPACING + BAR_HEIGHT
                    end
                    if overlayPowerBar and overlayPowerBar:IsShown() then
                        stackOut = stackOut + BAR_SPACING + POWER_BAR_HEIGHT
                    end
                    if overlaySecondaryPowerBar and overlaySecondaryPowerBar:IsShown() then
                        stackOut = stackOut + BAR_SPACING + POWER_BAR_HEIGHT
                    end
                    local clusterSpan = visibleCount * effSize + (visibleCount - 1) * effSpacing
                    defRowAnchor.stackOut   = stackOut
                    defRowAnchor.stackShift = (clusterSpan - effSize) * 0.5
                    PlaceCCListFrames(expansion)

                    -- Maintenance slot ("out"): AnchorToNameplate parks it above
                    -- defIcons[1] - exactly the band the bar stack now occupies.
                    -- Lift it above the stack. Offset is read in the slot's scaled
                    -- space, hence the division. (The enrage indicator also clears
                    -- the stack; the two can still meet on a tank with an enraged
                    -- target - pre-existing and rarer, accepted.)
                    if maintenanceIcon and expansion == "out" and #defIcons > 0 then
                        maintenanceIcon:ClearAllPoints()
                        maintenanceIcon:SetPoint("BOTTOM", defIcons[1], "TOP", 0,
                            iconSpacing + stackOut / (npoDefScale > 0 and npoDefScale or 1))
                    end
                else
                    -- visibleCount unchanged: just update opacity
                    healthBar:SetAlpha(opacity)
                    if petHealthBar and petHealthBar:IsShown() then petHealthBar:SetAlpha(opacity) end
                    if overlayPowerBar and overlayPowerBar:IsShown() then overlayPowerBar:SetAlpha(opacity) end
                    if overlaySecondaryPowerBar and overlaySecondaryPowerBar:IsShown() then overlaySecondaryPowerBar:SetAlpha(opacity) end
                end
            end
        else
            lastDefVisibleCount = 0
            healthBar:Hide()
            if petHealthBar then petHealthBar:Hide() end
            if overlayPowerBar then overlayPowerBar:Hide() end
            if overlaySecondaryPowerBar then overlaySecondaryPowerBar:Hide() end
            -- Stack gone: pull the CC list back in beside the bare row.
            if (defRowAnchor.stackOut or 0) ~= 0 then
                defRowAnchor.stackOut, defRowAnchor.stackShift = 0, 0
                PlaceCCListFrames(npo and npo.expansion or "down")
            end
        end
    end

    -- Enrage indicator: place Blizzard's enemy BuffListFrame as position 0 of the
    -- defensive queue. Re-anchored on visible-count change (same granularity as the
    -- health bar); horizontal clears the health/resource stack via the analytic
    -- stack extent captured above. Latch the count only on SUCCESS - a failed
    -- placement (restricted frame) retries next pass instead of never attaching
    -- for the rest of the fight.
    -- ponytail: a pet/power bar appearing without a count change won't re-nudge it -
    -- force via lastEnrageCount = -1 (as UpdatePowerColor does for the health bar).
    if visibleCount > 0 then
        if visibleCount ~= lastEnrageCount then
            if PositionEnrageIndicator(npo, npo.expansion or "down") then
                lastEnrageCount = visibleCount
            end
        end
    else
        lastEnrageCount = 0
        RestoreEnrageIndicator()
    end
end

--- Hide all defensive overlay icons (called when defensive queue is empty).
function UINameplateOverlay.HideDefensiveIcons()
    cachedDefensiveQueue = nil
    for _, icon in ipairs(defIcons) do
        UIRenderer.HideDefensiveIcon(icon)
    end
    -- The maintenance slot hides with the cluster it belongs to.
    UIRenderer.ClearMaintenanceSlot(maintenanceIcon)
    if healthBar then healthBar:Hide() end
    if petHealthBar then petHealthBar:Hide() end
    if overlayPowerBar then overlayPowerBar:Hide() end
    if overlaySecondaryPowerBar then overlaySecondaryPowerBar:Hide() end
end

--- Force the next RenderDefensives pass to re-run bar anchoring, the CC placement,
--- and the enrage placement. Needed when bar VISIBILITY changes without a defensive
--- count change - pet summon/dismiss - which the count-keyed cache can't see.
function UINameplateOverlay.InvalidateBarLayout()
    lastDefVisibleCount = -1
    lastEnrageCount     = -1
end

--- Re-render defensive icons using the last cached queue.
--- Called from UpdateSpellQueue so defensive overlay refreshes on the same
--- tick as the offensive overlay (eliminates visual delay from the slower
--- defensive evaluation cadence).
function UINameplateOverlay.RefreshDefensives(addon)
    if cachedDefensiveQueue then
        UINameplateOverlay.RenderDefensives(addon, cachedDefensiveQueue)
    end
end

--- Update the player health bar fill value and colour.
--- Fill: StatusBar:SetValue() accepts Blizzard secret values natively.
--- Colour: fixed bright green base, tinted orange/red at low health using
--- GetPlayerHealthPercentSafe() so it works even when values are secret (12.0+).
function UINameplateOverlay.UpdateHealthBar()
    if not healthBar then return end

    -- Same 0.1s cadence as every other bar path: this is called per UNIT_HEALTH
    -- event (10-30/sec in raid combat) ahead of the defensive-queue throttle.
    -- Time-based only - the values written below are secret and can't be diffed.
    local hbNow = GetTime()
    if hbNow - lastOverlayHealthUpdate < POWER_UPDATE_INTERVAL then return end
    lastOverlayHealthUpdate = hbNow

    -- Drive fill from raw UnitHealth - secret-safe, tracks continuously.
    -- Truthiness only: UnitHealthMax can be secret in combat and a `> 0`
    -- comparison throws. StatusBar accepts secret values directly.
    local health    = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    if health and maxHealth then
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

--- Update the pet health bar fill value.
--- UnitHealth("pet") is secret in 12.0 combat but StatusBar:SetValue() accepts secrets.
--- Auto-hides when no pet exists.
function UINameplateOverlay.UpdatePetHealthBar()
    if not petHealthBar then return end

    -- Same 0.1s cadence + secret-values rationale as UpdateHealthBar above.
    local hbNow = GetTime()
    if hbNow - lastOverlayPetHealthUpdate < POWER_UPDATE_INTERVAL then return end
    lastOverlayPetHealthUpdate = hbNow

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

    -- Truthiness only: UnitHealthMax can be secret in combat (see UpdateHealthBar).
    local health    = UnitHealth("pet")
    local maxHealth = UnitHealthMax("pet")
    if health and maxHealth then
        petHealthBar:SetMinMaxValues(0, maxHealth)
        petHealthBar:SetValue(health)
    end

    -- Warm yellow base colour
    petHealthBar:SetStatusBarColor(0.90, 0.75, 0.10, 0.9)
end

--- Update resource-bar fill values (throttled, mirrors UpdateHealthBar's cadence).
--- UnitPower/UnitPowerMax are secret in combat but StatusBar:SetValue accepts them.
function UINameplateOverlay.UpdatePowerBar(addon)
    if not overlayPowerBar then return end
    local profile = addon and addon:GetProfile()
    local npo = profile and profile.nameplateOverlay
    if not (npo and npo.showPowerBar) or not UpdateOneOverlayPowerBar then return end
    local now = GetTime()
    if now - lastOverlayPowerUpdate < POWER_UPDATE_INTERVAL then return end
    lastOverlayPowerUpdate = now
    UpdateOneOverlayPowerBar(overlayPowerBar)
    UpdateOneOverlayPowerBar(overlaySecondaryPowerBar)
end

--- Power-type changed (form/stance): recolour the primary (UnitPowerType is never
--- secret), re-cache the secondary, and force the next render to re-anchor/re-segment
--- it for the new form. Values re-applied immediately via the throttle reset.
function UINameplateOverlay.UpdatePowerColor(addon)
    if overlayPowerBar then
        UIHealthBar.ApplyResourceColor(overlayPowerBar, overlayPowerBar.powerType)
    end
    if overlaySecondaryPowerBar then
        RefreshOverlaySecondaryCache()
        if overlaySecondarySegments <= 0 then overlaySecondaryPowerBar:Hide() end
        lastDefVisibleCount = -1  -- force RenderDefensives to re-anchor/re-show the pair
    end
    lastOverlayPowerUpdate = 0
    UINameplateOverlay.UpdatePowerBar(addon)
end

--- Re-resolve the module-local interrupt/soothe spell lists.
--- Called from JustAC:OnSpellsChanged() / OnSpecChange() when talents may have
--- changed which interrupt/CC spells are available.
function UINameplateOverlay.RefreshInterruptSpells()
    if SpellDB and SpellDB.ResolveInterruptSpells then
        resolvedInterrupts = SpellDB.ResolveInterruptSpells()
    end
    if SpellDB and SpellDB.ResolveSootheSpells then
        resolvedSoothe = SpellDB.ResolveSootheSpells()
    end
end

--- Returns true when the overlay is currently anchored to a nameplate.
--- Used by UIRenderer/DefensiveEngine to decide whether to fall back to the main panel.
function UINameplateOverlay.IsAnchored()
    return currentNameplate ~= nil
end

--- Clear cached hotkeys on all overlay icons so they re-query on the next
--- cooldown throttle tick. Called from JustAC's binding-change invalidation.
function UINameplateOverlay.InvalidateHotkeyCache()
    for _, icon in ipairs(dpsIcons) do
        icon.cachedHotkey = nil
    end
    for _, icon in ipairs(defIcons) do
        icon.cachedHotkey = nil
    end
    if interruptIcon then
        interruptIcon.cachedHotkey = nil
    end
    if maintenanceIcon then
        maintenanceIcon.cachedHotkey = nil
    end
end

--- Hide every overlay element (called from EnterDisabledMode).
function UINameplateOverlay.HideAll()
    for _, icon in ipairs(dpsIcons) do
        if UIAnimations then UIAnimations.StopAllGlows(icon) end
        icon:Hide()
    end
    for _, icon in ipairs(defIcons) do
        if UIAnimations then UIAnimations.StopAllGlows(icon) end
        icon:Hide()
    end
    if maintenanceIcon then
        -- Same rule as UpdateAnchor's detach: clear through the shared helper so
        -- the glow frame and _maintGlow can't go stale across the hide.
        if UIRenderer and UIRenderer.ClearMaintenanceSlot then
            UIRenderer.ClearMaintenanceSlot(maintenanceIcon)
        end
        maintenanceIcon:Hide()
    end
    if healthBar then healthBar:Hide() end
    if petHealthBar then petHealthBar:Hide() end
    if overlayPowerBar then overlayPowerBar:Hide() end
    if overlaySecondaryPowerBar then overlaySecondaryPowerBar:Hide() end
    HideInterruptSlot(false)
end

