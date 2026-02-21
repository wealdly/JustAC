-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Nameplate Overlay Module
-- An independent display that anchors DPS queue icons (and optional defensives +
-- player health bar) directly to the target's nameplate.  Completely separate from
-- the main panel – either feature can be enabled without the other.
local UINameplateOverlay = LibStub:NewLibrary("JustAC-UINameplateOverlay", 1)
if not UINameplateOverlay then return end

local BlizzardAPI     = LibStub("JustAC-BlizzardAPI",     true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local UIAnimations    = LibStub("JustAC-UIAnimations",    true)
local UIRenderer      = LibStub("JustAC-UIRenderer",      true)
local SpellQueue      = LibStub("JustAC-SpellQueue",      true)

if not BlizzardAPI or not UIAnimations or not UIRenderer then return end

local GetTime            = GetTime
local pcall              = pcall
local wipe               = wipe
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack      = UnitCanAttack
local UnitHealth         = UnitHealth
local UnitHealthMax      = UnitHealthMax
local math_max           = math.max
local math_floor         = math.floor
local C_NamePlate        = C_NamePlate ---@diagnostic disable-line: undefined-global

-- Layout constants
local ICON_SPACING   = 2   -- px between successive icons in the cluster
local NAMEPLATE_GAP  = 2   -- px between nameplate edge and nearest element
local BAR_HEIGHT     = 5   -- player health bar height (half of NamePlateConstants.SMALL_HEALTH_BAR_HEIGHT)
local BAR_SPACING    = 2   -- px between health bar and first DPS icon (matches Blizzard's 2px castBar→healthBar gap)

-- Cooldown update throttle (matches UIRenderer)
local lastCooldownUpdate       = 0
local COOLDOWN_UPDATE_INTERVAL = 0.15

-- Module state (reset by Destroy)
local dpsIcons         = {}   -- [1..N] DPS icon buttons
local defIcons         = {}   -- [1..N] defensive icon buttons
local healthBar        = nil  -- player health StatusBar
local currentNameplate = nil  -- nameplate frame we're currently anchored to

-- ─────────────────────────────────────────────────────────────────────────────
-- Icon button factory
-- Produces a button compatible with:
--   • UIRenderer.UpdateButtonCooldowns  (cooldowns)
--   • UIRenderer.ShowDefensiveIcon      (defensive display)
--   • UIAnimations glow/flash functions (proc / assisted / defensive glows)
--   • JustAC:CreateKeyPressDetector     (key-press flash via normalizedHotkey)
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateOverlayIcon(iconSize)
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
    button.hasAssistedGlow  = false
    button.hasProcGlow      = false
    button.hasDefensiveGlow = false

    button:SetAlpha(0)
    button:Hide()
    return button
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Player health bar factory
-- Simple StatusBar; colour updates in UpdateHealthBar().
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateOverlayHealthBar(initialWidth)
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetSize(initialWidth, BAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:GetStatusBarTexture():SetHorizTile(false)
    bar:GetStatusBarTexture():SetVertTile(false)
    bar:SetStatusBarColor(0.0, 1.0, 0.0, 0.9)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:EnableMouse(false)

    -- Bright red background so lost health is immediately visible.
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.8, 0.1, 0.1, 0.9)
    bar.bg = bg

    bar:SetAlpha(0)
    bar:Hide()
    return bar
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: SetPoint all cluster elements to a live nameplate frame.
-- Uses a chain-anchor approach:
--   ROOT elements (healthBar, dpsIcons[1], defIcons[1]) anchor to the nameplate.
--   Subsequent icons in each cluster chain off the previous icon.
-- When the nameplate moves, the entire cluster follows automatically.
-- Health bar (when shown) floats above the nameplate for all anchor directions.
-- ─────────────────────────────────────────────────────────────────────────────
local function AnchorToNameplate(nameplate, anchor, iconSize, showHealthBar, showDefensives, expansion, healthBarPosition, iconSpacing)
    -- anchor:            "LEFT" or "RIGHT" — which side of the nameplate
    -- expansion:         "out" (horizontal, current), "up" (vertical upward), "down" (vertical downward)
    -- healthBarPosition: "outside" (far end of cluster) or "inside" (nameplate end of cluster)
    --                    only meaningful for "up"/"down" expansion; ignored for "out".
    -- iconSpacing:       px between successive icons (defaults to ICON_SPACING constant)
    expansion         = expansion or "out"
    healthBarPosition = healthBarPosition or "outside"
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

    local iconSize = npo.iconSize or 26
    local maxDPS   = math.min(npo.maxIcons or 1, 3)
    local maxDef   = npo.showDefensives and math.min(npo.maxDefensiveIcons or 1, 3) or 0

    for i = 1, maxDPS do dpsIcons[i] = CreateOverlayIcon(iconSize) end
    for i = 1, maxDef do defIcons[i] = CreateOverlayIcon(iconSize) end

    if npo.showHealthBar then
        healthBar = CreateOverlayHealthBar(iconSize * 2)
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

    if healthBar then
        healthBar:ClearAllPoints()
        healthBar:Hide()
        healthBar:SetParent(nil)
        healthBar = nil
    end

    wipe(dpsIcons)
    wipe(defIcons)
    currentNameplate = nil

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
        local healthBarPosition = npo.healthBarPosition or "outside"
        AnchorToNameplate(nameplate, anchor, iconSize, showHealthBar, showDefensives, expansion, healthBarPosition, npo.iconSpacing or ICON_SPACING)
        -- Individual icons become visible when Render() / RenderDefensives() fills them
    else
        currentNameplate = nil

        -- Detach and hide every element
        for _, icon in ipairs(dpsIcons) do
            if UIAnimations then
                if icon.hasAssistedGlow  then UIAnimations.StopAssistedGlow(icon);  icon.hasAssistedGlow  = false end
                if icon.hasProcGlow      then UIAnimations.HideProcGlow(icon);       icon.hasProcGlow      = false end
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
    local showHotkey   = npo.showHotkey
    local opacity      = npo.opacity or 1.0
    local now        = GetTime()
    local shouldUpdateCooldowns = (now - lastCooldownUpdate) >= COOLDOWN_UPDATE_INTERVAL
    if shouldUpdateCooldowns then lastCooldownUpdate = now end
    local inCombat = UnitAffectingCombat("player")

    local GetCachedSpellInfo = SpellQueue  and SpellQueue.GetCachedSpellInfo
    local IsSpellProcced     = BlizzardAPI and BlizzardAPI.IsSpellProcced
    local GetSpellHotkey     = ActionBarScanner and ActionBarScanner.GetSpellHotkey

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

            local isProc = IsSpellProcced and IsSpellProcced(spellID)
            if isProc and (npoGlowMode == "all" or npoGlowMode == "procOnly") then
                if not icon.hasProcGlow then UIAnimations.ShowProcGlow(icon); icon.hasProcGlow = true end
            elseif icon.hasProcGlow then
                UIAnimations.HideProcGlow(icon); icon.hasProcGlow = false
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
    local npoGlowMode   = npo.glowMode or "all"
    local opacity       = npo.opacity or 1.0
    local iconSpacing   = npo.iconSpacing or ICON_SPACING

    local visibleCount = 0
    for i, icon in ipairs(defIcons) do
        local entry = defensiveQueue and defensiveQueue[i]
        if entry and entry.spellID then
            icon.overlayOpacity = opacity
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, i == 1, npoGlowMode, npo.showHotkey, npo.showFlash ~= false)
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

                if expansion == "out" then
                    -- Horizontal cluster: symmetric 10% inset on both outer edges.
                    -- clusterWidth = n*size + (n-1)*spacing; barWidth = clusterWidth - 2*inset.
                    local clusterWidth = visibleCount * iconSize + (visibleCount - 1) * iconSpacing
                    local inset = (visibleCount == 1) and 0 or math_floor(iconSize * 0.10)
                    local barWidth = math_floor(clusterWidth - 2 * inset)
                    healthBar:SetOrientation("HORIZONTAL")
                    healthBar:SetSize(barWidth, BAR_HEIGHT)
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
                    local barHeight = math_floor(clusterHeight - 2 * inset)
                    healthBar:SetOrientation("VERTICAL")  -- fills bottom→top
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
            end
        else
            healthBar:Hide()
        end
    end
end

--- Hide all defensive overlay icons (called when defensive queue is empty).
function UINameplateOverlay.HideDefensiveIcons()
    for _, icon in ipairs(defIcons) do
        UIRenderer.HideDefensiveIcon(icon)
    end
    if healthBar then healthBar:Hide() end
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
end
