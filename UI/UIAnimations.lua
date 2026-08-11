-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: UI Animations Module - Manages glow and flash animations on buttons
local UIAnimations = LibStub:NewLibrary("JustAC-UIAnimations", 18)
if not UIAnimations then return end

local GetTime = GetTime
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration

-- Flash animation constants
local FLASH_DURATION = 0.2

-- Forward declarations
local StopAssistedGlow
local StopDefensiveGlow
local StopGapCloserGlow
local StopBurstGlow
local StopPrecombatGlow
local StopMaintenanceGlow

-- Create marching ants glow to show active abilities (Blizzard's rotation helper style)
local function CreateMarchingAntsFrame(parent, frameKey)
    local highlightFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = highlightFrame
    highlightFrame:SetPoint("CENTER")
    highlightFrame:SetSize(45, 45)
    highlightFrame:SetFrameLevel(parent:GetFrameLevel() + 4)
    if parent.isOverlayIcon then
        highlightFrame:SetFrameStrata("BACKGROUND")
        -- Overlay icons pack levels 0..4 (see CreateOverlayIcon): glows sit at +3,
        -- above the border (+2) and below flash/hotkey (+4).
        highlightFrame:SetFrameLevel(parent:GetFrameLevel() + 3)
    end
    
    local flipbook = highlightFrame:CreateTexture(nil, "OVERLAY")
    highlightFrame.Flipbook = flipbook
    flipbook:SetAtlas("rotationhelper_ants_flipbook")
    flipbook:SetSize(66, 66)
    flipbook:SetPoint("CENTER")
    
    local animGroup = flipbook:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    flipbook.Anim = animGroup
    
    local flipAnim = animGroup:CreateAnimation("FlipBook")
    flipAnim:SetDuration(1)
    flipAnim:SetOrder(0)
    flipAnim:SetFlipBookRows(6)
    flipAnim:SetFlipBookColumns(5)
    flipAnim:SetFlipBookFrames(30)
    flipAnim:SetFlipBookFrameWidth(0)
    flipAnim:SetFlipBookFrameHeight(0)
    
    return highlightFrame
end

-- Create proc glow using WoW's native animations to match action button style
local function CreateProcGlowFrame(parent, frameKey)
    local procFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = procFrame
    procFrame:SetPoint("CENTER")
    procFrame:SetSize(45 * 1.4, 45 * 1.4)
    procFrame:SetFrameLevel(parent:GetFrameLevel() + 5)
    if parent.isOverlayIcon then
        procFrame:SetFrameStrata("BACKGROUND")
        -- Overlay icons pack levels 0..4 (see CreateOverlayIcon): glows sit at +3.
        procFrame:SetFrameLevel(parent:GetFrameLevel() + 3)
    end
    procFrame:Hide()
    
    local procLoop = procFrame:CreateTexture(nil, "OVERLAY")
    procFrame.ProcLoopFlipbook = procLoop
    procLoop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
    procLoop:SetAllPoints(procFrame)
    procLoop:SetAlpha(1)
    
    local loopGroup = procLoop:CreateAnimationGroup()
    loopGroup:SetLooping("REPEAT")
    procFrame.ProcLoop = loopGroup
    
    local loopAlpha = loopGroup:CreateAnimation("Alpha")
    loopAlpha:SetDuration(0.001)
    loopAlpha:SetOrder(0)
    loopAlpha:SetFromAlpha(1)
    loopAlpha:SetToAlpha(1)
    
    local loopFlip = loopGroup:CreateAnimation("FlipBook")
    loopFlip:SetChildKey("ProcLoopFlipbook")
    loopFlip:SetDuration(1)
    loopFlip:SetOrder(0)
    loopFlip:SetFlipBookRows(6)
    loopFlip:SetFlipBookColumns(5)
    loopFlip:SetFlipBookFrames(30)
    loopFlip:SetFlipBookFrameWidth(0)
    loopFlip:SetFlipBookFrameHeight(0)
    
    procFrame:SetScript("OnHide", function()
        if procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Stop()
        end
    end)
    
    loopGroup:Play()
    loopGroup:Stop()
    
    return procFrame
end

-- Display proc glow to highlight instantly available abilities
local function ShowProcGlow(icon, isInCombat)
    if not icon then return end
    
    local procFrame = icon.ProcGlowFrame
    if not procFrame then
        procFrame = CreateProcGlowFrame(icon, "ProcGlowFrame")
    end
    -- The PRIMITIVE owns hasProcGlow (audit 2026-08-10): flag writes scattered
    -- across call sites left it desynced from the frame - a stale true made
    -- ResumeIconGlows resurrect a hidden glow on combat entry, a missing true
    -- (the defensive path never set it) made StopAllGlows skip the hide.
    icon.hasProcGlow = true

    local width = icon.cachedIconSize or icon:GetWidth()
    procFrame:SetScale(width / 45)

    procFrame:SetAlpha(1.0)
    procFrame:Show()
    
    if isInCombat then
        if not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Play()
        end
    else
        -- Show frame but freeze animation out of combat
        if procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Pause()
        elseif not procFrame.ProcLoop:IsPaused() then
            procFrame.ProcLoop:Play()
            procFrame.ProcLoop:Pause()
        end
    end
end

-- Hide proc glow
local function HideProcGlow(icon)
    if not icon then return end
    icon.hasProcGlow = false   -- primitive owns the flag; see ShowProcGlow
    if not icon.ProcGlowFrame then return end

    icon.ProcGlowFrame:Hide()
    if icon.ProcGlowFrame.ProcLoop:IsPlaying() then
        icon.ProcGlowFrame.ProcLoop:Stop()
    end
end

-- Colored proc glow constants (burst purple lives in GLOW_CONFIG.BURST).
--
-- SATURATION: ShowColoredProcGlow desaturates the flipbook to greyscale and then multiplies
-- by these values, so EVERY pixel ends up at the tint's full chroma - which is why fully
-- saturated values read as flat neon rather than as light. A real glow (including Blizzard's
-- own gold one) has a near-white core with the colour showing in the falloff, so these are
-- deliberately pulled toward white: the lowest channel sets how white the core goes, the
-- highest sets the hue. Red is the exception and stays saturated, because lifting its low
-- channels turns it pink and pink does not read as "danger".
-- Do NOT try to fix this with partial SetDesaturation instead: keeping the gold base means
-- cool tints multiply into muddy olive, which is worse for the cyan and blue cues.
local INTERRUPT_PROC_R, INTERRUPT_PROC_G, INTERRUPT_PROC_B = 1.0, 0.25, 0.05  -- Red
-- Soothe is CYAN, not green: it is armed over the SAME slot as the red interrupt glow, so
-- colour is the only thing telling "kick this" from "soothe this". Red vs green is the most
-- common colour-vision deficiency, which is why green was rejected for this cue.
local SOOTHE_PROC_R,    SOOTHE_PROC_G,    SOOTHE_PROC_B    = 0.55, 0.90, 1.00  -- Cyan

-- Shared helper: show a desaturated+tinted proc glow on a named frame key.
-- Set alpha on the frame itself; the internal Alpha animation forces the
-- texture alpha to 1 every loop iteration, so texture-level alpha would be
-- overridden.  Frame-level alpha stacks and is not touched by animations.
local function ShowColoredProcGlow(icon, frameKey, r, g, b)
    if not icon then return end
    local procFrame = icon[frameKey]
    if not procFrame then
        procFrame = CreateProcGlowFrame(icon, frameKey)
        procFrame.ProcLoopFlipbook:SetDesaturated(true)
        procFrame.ProcLoopFlipbook:SetVertexColor(r, g, b, 1)
    end
    local width = icon.cachedIconSize or icon:GetWidth()
    procFrame:SetScale(width / 45)
    procFrame:SetAlpha(1.0)
    procFrame:Show()
    if not procFrame.ProcLoop:IsPlaying() then
        procFrame.ProcLoop:Play()
    end
end

-- Shared helper: hide a named proc glow frame.
local function HideColoredProcGlow(icon, frameKey)
    if not icon or not icon[frameKey] then return end
    icon[frameKey]:Hide()
    if icon[frameKey].ProcLoop:IsPlaying() then
        icon[frameKey].ProcLoop:Stop()
    end
end

local function ShowInterruptProcGlow(icon)
    ShowColoredProcGlow(icon, "InterruptProcGlowFrame", INTERRUPT_PROC_R, INTERRUPT_PROC_G, INTERRUPT_PROC_B)
end

local function HideInterruptProcGlow(icon)
    HideColoredProcGlow(icon, "InterruptProcGlowFrame")
end

-- No dedicated Hide wrapper: hiding the cue frame takes the glow with it, and the one
-- explicit disarm (a spec losing its soothe spell) goes through the generic
-- HideColoredProcGlow with this frame key from UISootheCue.SetSpell.
local function ShowSootheProcGlow(icon)
    ShowColoredProcGlow(icon, "SootheProcGlowFrame", SOOTHE_PROC_R, SOOTHE_PROC_G, SOOTHE_PROC_B)
end

local function TintMarchingAnts(highlightFrame, r, g, b, desaturate)
    if highlightFrame and highlightFrame.Flipbook then
        -- The rotationhelper_ants_flipbook atlas is predominantly blue/cyan.
        -- To tint it a non-blue colour (e.g. red), desaturate to greyscale first
        -- so SetVertexColor multiplies against neutral luminance rather than blue.
        highlightFrame.Flipbook:SetDesaturated(desaturate and true or false)
        highlightFrame.Flipbook:SetVertexColor(r, g, b, 1)
    end
end

-- ── Consolidated Marching Ants Glow Engine ─────────────────────────────────
-- All glow types (assisted, defensive, gap-closer, interrupt) share the same
-- marching-ants flipbook animation with different parameters:
--
-- | Type        | Frame Key                  | Color (R,G,B) | Desat | Scale  | Pause OOC | Flag Field        | Clears Proc |
-- |-------------|----------------------------|---------------|-------|--------|-----------|-------------------|-------------|
-- | Assisted    | JustACAssistedGlow         | 1, 1, 1       | no    | ×1.02  | yes       | hasAssistedGlow   | yes         |
-- | Defensive   | DefensiveHighlightFrame    | 0.3, 1.0, 0.3 | no    | ×1.0   | yes       | hasDefensiveGlow  | yes         |
-- | Gap-closer  | GapCloserHighlightFrame    | 1.0, 0.35, 0.8| yes   | ×1.0   | no        | hasGapCloserGlow  | no          |

-- Per-type configuration tables (avoid allocations on hot path)
local GLOW_CONFIG = {
    ASSISTED = {
        frameKey    = "JustACAssistedGlow",  -- NOT "AssistedCombatHighlightFrame" - Masque auto-detects that key
        r = 1, g = 1, b = 1,                -- White/no tint (appears blue in-game from atlas)
        desaturate  = false,
        scaleMul    = 1.02,
        pauseOOC    = true,                  -- Pause animation out of combat
        flagField   = "hasAssistedGlow",
        pauseField  = "assistedAnimPaused",
        clearsProc  = true,
    },
    DEFENSIVE = {
        frameKey    = "DefensiveHighlightFrame",
        r = 0.60, g = 1.00, b = 0.60,       -- Green for defensive queue
        desaturate  = false,
        scaleMul    = 1.0,
        pauseOOC    = true,
        flagField   = "hasDefensiveGlow",
        pauseField  = "defensiveAnimPaused",
        clearsProc  = true,
    },
    GAP_CLOSER = {
        frameKey    = "GapCloserHighlightFrame",
        -- Magenta, not gold: gold is the native proc glow, and a pale-gold ring next to it
        -- read as the same cue. Magenta is the furthest hue from gold that the offensive row
        -- has left, and it stays legible with red-green colour deficiency (the red interrupt
        -- glow shares this row, which is why lime was rejected).
        r = 1.00, g = 0.35, b = 0.80,       -- Magenta (desaturated atlas → grey → magenta tint)
        desaturate  = true,
        scaleMul    = 1.0,
        pauseOOC    = false,                 -- Always animate to draw attention
        flagField   = "hasGapCloserGlow",
        pauseField  = nil,                   -- No pause tracking needed
        clearsProc  = false,
    },
    BURST = {
        frameKey    = "BurstHighlightFrame",
        r = 0.80, g = 0.55, b = 1.00,       -- Purple for burst injection
        desaturate  = true,
        scaleMul    = 1.0,
        pauseOOC    = false,                 -- Always animate to draw attention
        flagField   = "hasBurstGlow",
        pauseField  = nil,
        clearsProc  = false,
    },
    MAINTENANCE = {
        frameKey    = "MaintenanceHighlightFrame",
        -- Same blue as the maintenance proc burst it escalates into, so the two stages
        -- read as one cue getting louder rather than as two unrelated signals.
        r = 0.55, g = 0.78, b = 1.00,       -- Blue (matches MAINTENANCE_GLOW in UIRenderer)
        desaturate  = true,
        scaleMul    = 1.0,
        pauseOOC    = false,                 -- The warning is only ever raised in combat
        flagField   = "hasMaintenanceGlow",
        pauseField  = nil,
        clearsProc  = false,
    },
    PRECOMBAT = {
        frameKey    = "PrecombatHighlightFrame",
        -- Magenta, not green: these render inside the DEFENSIVE cluster next to the green glow.
        r = 1.00, g = 0.65, b = 0.88,       -- Magenta for inserted pre-combat buffs
        desaturate  = false,
        scaleMul    = 1.0,
        pauseOOC    = false,                 -- Always animate: these are the OOC call to action
        flagField   = "hasPrecombatGlow",
        pauseField  = nil,
        clearsProc  = false,
    },
}

-- Core start function - all glow types funnel through here
local function StartMarchingAntsGlow(icon, config, isInCombat)
    if not icon then return end

    local frameKey = config.frameKey
    local highlightFrame = icon[frameKey]
    local needsInit = not highlightFrame

    if needsInit then
        highlightFrame = CreateMarchingAntsFrame(icon, frameKey)
    end

    -- Only do setup work if frame was just created or not yet shown
    if needsInit or not highlightFrame:IsShown() then
        local width = icon.cachedIconSize or icon:GetWidth()
        highlightFrame:SetScale((width / 45) * config.scaleMul)
        TintMarchingAnts(highlightFrame, config.r, config.g, config.b, config.desaturate)
        if config.scaleMul ~= 1.0 then
            highlightFrame.Flipbook:SetAlpha(1)
        end
        highlightFrame:Show()
    end
    -- Unconditional (audit 2026-08-10): the set lived inside the shown-guard while
    -- StopMarchingAntsGlow clears unconditionally, so an externally-cleared flag on
    -- a still-shown frame could never re-assert - glow visible, flag false, every
    -- flag-gated stop skipping it.
    icon[config.flagField] = true

    -- Animation state management
    local pauseField = config.pauseField
    if config.pauseOOC then
        -- Assisted/Defensive: pause animation out of combat for subtle feedback
        if isInCombat then
            if (pauseField and icon[pauseField]) or not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
                if pauseField then icon[pauseField] = false end
            end
        elseif pauseField and not icon[pauseField] then
            icon[pauseField] = true
            if not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
            end
            C_Timer.After(0.05, function()
                if highlightFrame and highlightFrame.Flipbook and highlightFrame.Flipbook.Anim
                    and pauseField and icon[pauseField] then
                    highlightFrame.Flipbook.Anim:Pause()
                end
            end)
        end
    else
        -- Gap-closer/Interrupt: always animate
        if not highlightFrame.Flipbook.Anim:IsPlaying() then
            highlightFrame.Flipbook.Anim:Play()
        end
    end
end

-- Core stop function - all glow types funnel through here
local function StopMarchingAntsGlow(icon, config)
    if not icon then return end

    local frame = icon[config.frameKey]
    if frame then
        frame:Hide()
        if frame.Flipbook and frame.Flipbook.Anim then
            frame.Flipbook.Anim:Stop()
        end
    end

    if config.clearsProc then
        HideProcGlow(icon)   -- clears hasProcGlow itself; the primitive owns that flag
    end

    icon[config.flagField] = false
    if config.pauseField then
        icon[config.pauseField] = false
    end
end

-- ── Public wrappers (preserve existing API) ────────────────────────────────

local function StartAssistedGlow(icon, isInCombat)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.ASSISTED, isInCombat)
end

StopAssistedGlow = function(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.ASSISTED)
end

local function StartDefensiveGlow(icon, isInCombat)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.DEFENSIVE, isInCombat)
end

StopDefensiveGlow = function(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.DEFENSIVE)
end

local function StartGapCloserGlow(icon)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.GAP_CLOSER)
end

StopGapCloserGlow = function(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.GAP_CLOSER)
end

local function StartBurstGlow(icon)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.BURST)
end

StopBurstGlow = function(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.BURST)
end

local function StartMaintenanceGlow(icon, isInCombat)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.MAINTENANCE, isInCombat)
end

StopMaintenanceGlow = function(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.MAINTENANCE)
end

local function StartPrecombatGlow(icon, isInCombat)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.PRECOMBAT, isInCombat)
end

StopPrecombatGlow = function(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.PRECOMBAT)
end

local function StartFlash(button)
    if not button.Flash then return end

    -- Token so a queued hide from an earlier flash can't cut a newer one short
    local token = (button.flashToken or 0) + 1
    button.flashToken = token

    button.Flash:SetDrawLayer("OVERLAY", 2)
    button.Flash:SetAlpha(1.0)
    button.Flash:Show()

    C_Timer.After(FLASH_DURATION, function()
        if button.flashToken == token and button.Flash then
            button.Flash:SetAlpha(0)
            button.Flash:Hide()
        end
    end)
end

local function PauseIconGlows(icon)
    if not icon then return end

    -- Assisted glow: freeze at current frame
    if icon.JustACAssistedGlow and icon.JustACAssistedGlow:IsShown() then
        if icon.JustACAssistedGlow.Flipbook.Anim:IsPlaying() then
            icon.JustACAssistedGlow.Flipbook.Anim:Pause()
        end
        icon.assistedAnimPaused = true
    end
    -- Defensive glow: freeze at current frame
    if icon.DefensiveHighlightFrame and icon.DefensiveHighlightFrame:IsShown() then
        if icon.DefensiveHighlightFrame.Flipbook.Anim:IsPlaying() then
            icon.DefensiveHighlightFrame.Flipbook.Anim:Pause()
        end
        icon.defensiveAnimPaused = true
    end
    -- Proc glow: freeze animation (keep frame visible)
    if icon.ProcGlowFrame and icon.ProcGlowFrame:IsShown() then
        if icon.ProcGlowFrame.ProcLoop and icon.ProcGlowFrame.ProcLoop:IsPlaying() then
            icon.ProcGlowFrame.ProcLoop:Pause()
        end
    end
    -- Gap-closer/Interrupt/Burst glows deliberately excluded:
    -- they always animate (even OOC) for emphasis.
end

local function PauseAllGlows(addon)
    if not addon then return end

    if addon.spellIcons then
        for i = 1, #addon.spellIcons do
            PauseIconGlows(addon.spellIcons[i])
        end
    end
    -- Defensive icons: RESET the proc glow instead of freezing it mid-frame -
    -- a paused flipbook reads as stuck. The combat-exit rebuild re-renders
    -- immediately and re-establishes the correct glow (green pre-combat buff,
    -- static proc glow, or marching ants).
    if addon.defensiveIcons then
        for i = 1, #addon.defensiveIcons do
            local icon = addon.defensiveIcons[i]
            PauseIconGlows(icon)
            HideProcGlow(icon)
            -- Reset the renderer's glow arbiter so the combat-exit rebuild
            -- re-applies from a clean, known state.
            icon.appliedDefGlowState = nil
            icon.pendingDefGlowState = nil
        end
    end
end

local function ResumeIconGlows(icon)
    if not icon then return end

    -- Assisted glow: resume animation
    if icon.JustACAssistedGlow and icon.JustACAssistedGlow:IsShown() then
        if not icon.JustACAssistedGlow.Flipbook.Anim:IsPlaying() then
            icon.JustACAssistedGlow.Flipbook.Anim:Play()
        end
        icon.assistedAnimPaused = false
    end
    -- Defensive glow: resume animation
    if icon.DefensiveHighlightFrame and icon.DefensiveHighlightFrame:IsShown() then
        if not icon.DefensiveHighlightFrame.Flipbook.Anim:IsPlaying() then
            icon.DefensiveHighlightFrame.Flipbook.Anim:Play()
        end
        icon.defensiveAnimPaused = false
    end
    -- Proc glow: resume animation
    if icon.ProcGlowFrame and icon.hasProcGlow then
        if not icon.ProcGlowFrame:IsShown() then
            icon.ProcGlowFrame:Show()
        end
        if icon.ProcGlowFrame.ProcLoop and not icon.ProcGlowFrame.ProcLoop:IsPlaying() then
            icon.ProcGlowFrame.ProcLoop:Play()
        end
    end
end

local function ResumeAllGlows(addon)
    if not addon then return end

    if addon.spellIcons then
        for i = 1, #addon.spellIcons do
            ResumeIconGlows(addon.spellIcons[i])
        end
    end
    if addon.defensiveIcons then
        for i = 1, #addon.defensiveIcons do
            ResumeIconGlows(addon.defensiveIcons[i])
        end
    end
end

--------------------------------------------------------------------------------
-- Channel Fill Animation (mirrors Blizzard's ActionButtonCastingAnimFrame)
--------------------------------------------------------------------------------
-- Lightweight clone of Blizzard's channel-fill overlay using the same atlas
-- textures (UI-HUD-ActionBar-Channel-Fill, UI-HUD-ActionBar-Channel-InnerGlow).
-- A Translation animation slides the fill texture across the icon over the
-- channel duration.  The frame is parented inside the icon's cooldownContainer
-- so SetClipsChildren keeps it within bounds, and the icon's IconMask clips it
-- to the rounded icon shape.
--
-- Lifecycle:
--   StartChannelFill(icon) - creates (once) / shows / plays for current channel
--   StopChannelFill(icon)  - stops anim, hides frame
--
-- Identification of the channeled icon uses UnitChannelInfo spellID +
-- C_Spell.GetOverrideSpell matching at the call site, not inside these helpers.

local function CreateChannelFillFrame(icon)
    -- Parent to cooldownContainer (SetClipsChildren=true clips rendering to icon bounds).
    -- Frame level: above cooldown swipe but below border (L+3) and glows (L+4+).
    local parent = icon.cooldownContainer or icon

    -- Match Blizzard's ActionButtonCastingAnimFrameTemplate: 128x128 centered on the icon.
    -- The atlas textures and translation offsets (+45, −43) are tuned for this size.
    -- cooldownContainer's SetClipsChildren clips the rendered output to ~45x45 icon bounds.
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(128, 128)
    frame:SetPoint("CENTER", icon, "CENTER")
    -- Derived from the border, not from the icon: "one below the border" is the actual intent,
    -- and the two surfaces pack their levels differently (standard queue icon+3, nameplate
    -- overlay absolute 2). The old icon+2 happened to be right on the standard queue and TIED
    -- the border on nameplates, letting the fill draw over it.
    -- ponytail: still ties the cooldown swipe one level down, resolved by creation order - the
    -- fill is built later, and Masque does not manage it. Give the border its own level if that
    -- ever stops holding.
    frame:SetFrameLevel(icon.borderFrame and (icon.borderFrame:GetFrameLevel() - 1)
        or (icon:GetFrameLevel() + 2))
    if icon.isOverlayIcon then frame:SetFrameStrata("BACKGROUND") end

    -- Inner glow (soft light behind the fill bar)
    local innerGlow = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    innerGlow:SetAtlas("UI-HUD-ActionBar-Channel-InnerGlow", true)
    innerGlow:SetPoint("CENTER")
    frame.InnerGlowTexture = innerGlow

    -- Fill bar (slides from right to left for channels)
    local castFill = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    castFill:SetAtlas("UI-HUD-ActionBar-Channel-Fill", true)
    castFill:SetBlendMode("ADD")
    frame.CastFill = castFill

    -- Mask to icon shape (reuse the icon's existing mask if available)
    if icon.IconMask then
        castFill:AddMaskTexture(icon.IconMask)
        innerGlow:AddMaskTexture(icon.IconMask)
    end

    -- Animation group: translate the fill bar across the icon
    local animGroup = castFill:CreateAnimationGroup()
    frame.CastingAnim = animGroup

    local translation = animGroup:CreateAnimation("Translation")
    translation:SetOrder(1)
    frame.CastFillTranslation = translation

    -- Fade out the fill texture at the end of the channel
    local fadeOut = animGroup:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.15)
    fadeOut:SetOrder(2)
    fadeOut:SetSmoothing("OUT")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)

    -- On finish: hide the frame cleanly
    animGroup:SetScript("OnFinished", function()
        frame:Hide()
    end)

    frame:Hide()
    icon.ChannelFillFrame = frame
    return frame
end

local function StartChannelFill(icon)
    if not icon then return end

    -- Get channel timing from UnitChannelInfo (all NeverSecret, verified 2026-03-05)
    local _, _, _, startMS, endMS = UnitChannelInfo("player")
    -- Aura-based application (eating food) is not a real channel - fall back to the item's
    -- on-use aura, then the generic eating aura, for timing so the sweep still tracks.
    if (not startMS or not endMS) and C_UnitAuras then
        local aura = icon.itemCastSpellID
            and C_UnitAuras.GetPlayerAuraBySpellID(icon.itemCastSpellID)
        local eating = false
        if not aura then
            local SDB = LibStub("JustAC-SpellDB", true)
            if SDB and SDB.GetActiveEatingAura then
                aura = SDB.GetActiveEatingAura()
                eating = aura ~= nil
            end
        end
        -- 12.0.7: aura timing can be secret even out of combat - comparing or doing
        -- arithmetic on a secret throws, so a secret-timed aura gets no fill sweep.
        if aura and issecretvalue
           and (issecretvalue(aura.duration) or issecretvalue(aura.expirationTime)) then
            aura = nil
        end
        if aura and aura.expirationTime and aura.duration and aura.duration > 0 then
            startMS = (aura.expirationTime - aura.duration) * 1000
            -- Well Fed lands after ~10s of eating, not the full ~20s aura - track that
            -- window so the sweep completes exactly when the buff is granted.
            endMS = eating and (startMS + math.min(aura.duration, 10) * 1000)
                or aura.expirationTime * 1000
        end
    end
    if not startMS or not endMS then return end

    local totalDuration = (endMS - startMS) / 1000
    if totalDuration <= 0 then return end

    -- Elapsed time since channel started
    local elapsed = GetTime() - (startMS / 1000)
    local remaining = totalDuration - elapsed
    if remaining <= 0 then return end

    local frame = icon.ChannelFillFrame or CreateChannelFillFrame(icon)

    -- Position fill bar: start at right side (CENTER +45), translate left (-43)
    -- Blizzard's channel fill slides right→left (draining)
    frame.CastFill:ClearAllPoints()
    frame.CastFill:SetPoint("CENTER", 45, 0)
    frame.CastFillTranslation:SetOffset(-43, 0)
    frame.CastFillTranslation:SetDuration(totalDuration)

    -- If channel is already partway through, set start offset proportionally.
    -- The Translation animation supports SetStartDelay but not mid-seek, so we
    -- reposition the fill bar to where it would be and shorten the duration.
    if elapsed > 0.05 then
        local progress = elapsed / totalDuration  -- 0..1
        local startX = 45 - (43 * progress)       -- lerp from 45 to 2
        frame.CastFill:ClearAllPoints()
        frame.CastFill:SetPoint("CENTER", startX, 0)
        frame.CastFillTranslation:SetOffset(-(43 * (1 - progress)), 0)
        frame.CastFillTranslation:SetDuration(remaining)
    end

    frame.CastingAnim:Stop()
    frame:Show()
    frame.CastFill:SetAlpha(1)
    frame.InnerGlowTexture:SetAlpha(1)
    frame.CastingAnim:Play()
    icon._hasChannelFill = true
end

local function StopChannelFill(icon)
    if not icon or not icon.ChannelFillFrame then return end
    icon.ChannelFillFrame.CastingAnim:Stop()
    icon.ChannelFillFrame:Hide()
    icon._hasChannelFill = false
end

--------------------------------------------------------------------------------
-- Interrupt cast-progress bar (secret-aware)
--------------------------------------------------------------------------------
-- Reflects the TARGET's cast progress on the interrupt icon without ever reading
-- a (12.0-secret) timing value: a unit-keyed cast Duration object drives a
-- StatusBar through the engine's SetTimerDuration sink, so the engine animates
-- the fill and we compute nothing.  A static "kick zone" segment marks the final
-- quarter; the engine-driven fill animates into it (press when it enters).  Casts
-- fill forward; channels drain.  Self-disables on clients without the timer API.
local HAS_CAST_TIMER = UnitCastingDuration and Enum
    and Enum.StatusBarTimerDirection and Enum.StatusBarInterpolation and true or false

local INTERRUPT_KICKZONE_FRAC = 0.25

local function CreateInterruptCastBar(icon)
    local bar = CreateFrame("StatusBar", nil, icon)
    bar:SetPoint("BOTTOMLEFT",  icon, "BOTTOMLEFT",   1, 1)
    bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    bar:SetFrameLevel(icon:GetFrameLevel() + 3)
    if icon.isOverlayIcon then bar:SetFrameStrata("BACKGROUND") end

    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fill = bar:GetStatusBarTexture()
    if fill then fill:SetVertexColor(1.0, 0.82, 0.0, 1) end  -- gold fill

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.6)

    local zone = bar:CreateTexture(nil, "OVERLAY")
    zone:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    0, 0)
    zone:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    zone:SetColorTexture(1.0, 0.2, 0.1, 0.40)  -- static "press now" zone
    bar.KickZone = zone

    bar:Hide()
    icon.InterruptCastBar = bar
    return bar
end

local function ShowInterruptCastBar(icon)
    if not icon or not HAS_CAST_TIMER then return end
    local bar = icon.InterruptCastBar or CreateInterruptCastBar(icon)

    -- Arm once per cast; only latch on a successful drive so a transient nil
    -- duration retries next frame instead of leaving the bar blank.
    if icon._castBarArmed and bar:IsShown() then return end

    -- Size to the current icon (icons scale with firstIconScale); zone = final quarter.
    -- Behind the armed check: the values only depend on icon size, so re-writing
    -- them per pass while the bar was already driving was pure widget churn.
    local size = icon.cachedIconSize or icon:GetWidth() or 0
    if size > 0 then
        bar:SetHeight(math.max(4, size * 0.18))
        bar.KickZone:SetWidth(math.max(1, (size - 2) * INTERRUPT_KICKZONE_FRAC))
    end

    local durObj, isChannel
    local ok, d = pcall(UnitCastingDuration, "target")
    if ok and d and type(d) == "userdata" then durObj, isChannel = d, false end
    if not durObj and UnitChannelDuration then
        ok, d = pcall(UnitChannelDuration, "target")
        if ok and d and type(d) == "userdata" then durObj, isChannel = d, true end
    end

    if not durObj or not bar.SetTimerDuration then
        bar:Hide()
        icon._castBarArmed = false
        return
    end

    local dir = isChannel and Enum.StatusBarTimerDirection.RemainingTime
                          or  Enum.StatusBarTimerDirection.ElapsedTime
    bar:SetMinMaxValues(0, 1)
    bar:SetTimerDuration(durObj, Enum.StatusBarInterpolation.Immediate, dir)
    bar:Show()
    icon._castBarArmed = true
end

local function HideInterruptCastBar(icon)
    if not icon or not icon.InterruptCastBar then return end
    icon.InterruptCastBar:Hide()
    icon._castBarArmed = false
end

-- Stop every glow an icon can carry and clear the flags. Callers that tear an icon
-- down (pool release, detach, hide-all) want all of them regardless of which pool the
-- icon came from, and each arm is already a no-op when its flag is false - so one
-- superset here beats a per-site subset that silently misses a type when a new glow
-- is added.
local function StopAllGlows(icon)
    if not icon then return end
    if icon.hasAssistedGlow  then StopAssistedGlow(icon)  end
    if icon.hasDefensiveGlow then StopDefensiveGlow(icon) end
    if icon.hasGapCloserGlow then StopGapCloserGlow(icon) end
    if icon.hasBurstGlow     then StopBurstGlow(icon)     end
    if icon.hasPrecombatGlow then StopPrecombatGlow(icon) end
    if icon.hasMaintenanceGlow then StopMaintenanceGlow(icon) end
    if icon.hasProcGlow      then HideProcGlow(icon)      end
    icon.hasAssistedGlow  = false
    icon.hasDefensiveGlow = false
    icon.hasGapCloserGlow = false
    icon.hasBurstGlow     = false
    icon.hasPrecombatGlow = false
    icon.hasMaintenanceGlow = false
    icon.hasProcGlow      = false
    -- We just force-hid the defensive glow from outside UIRenderer's arbiter, so its
    -- cached state would still claim the glow is applied and the next RenderDefensives
    -- would see want == have and never restart it. Resetting here rather than at each
    -- call site is what makes that invariant impossible to forget.
    icon.appliedDefGlowState = nil
    icon.pendingDefGlowState = nil
end

-- Exports
UIAnimations.StopAllGlows = StopAllGlows
UIAnimations.StartAssistedGlow = StartAssistedGlow
UIAnimations.StopAssistedGlow = StopAssistedGlow
UIAnimations.StartDefensiveGlow = StartDefensiveGlow
UIAnimations.StopDefensiveGlow = StopDefensiveGlow
UIAnimations.StartGapCloserGlow = StartGapCloserGlow
UIAnimations.StopGapCloserGlow = StopGapCloserGlow
UIAnimations.StartBurstGlow = StartBurstGlow
UIAnimations.StopBurstGlow = StopBurstGlow
UIAnimations.StartMaintenanceGlow = StartMaintenanceGlow
UIAnimations.StopMaintenanceGlow = StopMaintenanceGlow
UIAnimations.StartPrecombatGlow = StartPrecombatGlow
UIAnimations.StopPrecombatGlow = StopPrecombatGlow
UIAnimations.ShowProcGlow = ShowProcGlow
UIAnimations.HideProcGlow = HideProcGlow
UIAnimations.ShowInterruptProcGlow = ShowInterruptProcGlow
-- Exported for the maintenance slot, which picks its own tint rather than using one of the
-- fixed wrappers. frameKey scopes the glow so it cannot collide on a pooled icon.
UIAnimations.ShowColoredProcGlow = ShowColoredProcGlow
UIAnimations.HideColoredProcGlow = HideColoredProcGlow
UIAnimations.HideInterruptProcGlow = HideInterruptProcGlow
UIAnimations.ShowSootheProcGlow = ShowSootheProcGlow
UIAnimations.StartFlash = StartFlash
UIAnimations.PauseAllGlows = PauseAllGlows
UIAnimations.ResumeAllGlows = ResumeAllGlows
UIAnimations.StartChannelFill = StartChannelFill
UIAnimations.StopChannelFill = StopChannelFill
UIAnimations.ShowInterruptCastBar = ShowInterruptCastBar
UIAnimations.HideInterruptCastBar = HideInterruptCastBar
