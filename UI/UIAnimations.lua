-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Animations Module - Manages glow and flash animations on buttons
local UIAnimations = LibStub:NewLibrary("JustAC-UIAnimations", 12)
if not UIAnimations then return end

local GetTime = GetTime
local UnitChannelInfo = UnitChannelInfo

-- Flash animation constants
local FLASH_DURATION = 0.2

-- Sentinel value: indicates no previous OnUpdate handler existed before flash
-- Must be a unique truthy value so the guard check works correctly
local FLASH_NO_PREV_HANDLER = {}

-- Forward declarations
local StopAssistedGlow
local StopDefensiveGlow
local StopGapCloserGlow
local UpdateFlash

-- Create marching ants glow to show active abilities (Blizzard's rotation helper style)
local function CreateMarchingAntsFrame(parent, frameKey)
    local highlightFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = highlightFrame
    highlightFrame:SetPoint("CENTER")
    highlightFrame:SetSize(45, 45)
    highlightFrame:SetFrameLevel(parent:GetFrameLevel() + 4)
    if parent.isOverlayIcon then highlightFrame:SetFrameStrata("BACKGROUND") end
    
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
    if parent.isOverlayIcon then procFrame:SetFrameStrata("BACKGROUND") end
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
local function ShowProcGlow(icon)
    if not icon then return end
    
    local procFrame = icon.ProcGlowFrame
    if not procFrame then
        procFrame = CreateProcGlowFrame(icon, "ProcGlowFrame")
    end
    
    local width = icon:GetWidth()
    procFrame:SetScale(width / 45)
    
    procFrame.ProcLoopFlipbook:SetAlpha(1)
    procFrame:Show()
    
    if not procFrame.ProcLoop:IsPlaying() then
        procFrame.ProcLoop:Play()
    end
end

-- Hide proc glow
local function HideProcGlow(icon)
    if not icon or not icon.ProcGlowFrame then return end
    
    icon.ProcGlowFrame:Hide()
    if icon.ProcGlowFrame.ProcLoop:IsPlaying() then
        icon.ProcGlowFrame.ProcLoop:Stop()
    end
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
-- | Gap-closer  | GapCloserHighlightFrame    | 1.0, 0.95, 0.4| yes   | ×1.0   | no        | hasGapCloserGlow  | no          |
-- | Interrupt   | InterruptHighlightFrame    | 1.0, 0.95, 0.4| yes   | ×1.0   | no        | hasInterruptGlow  | yes         |

-- Per-type configuration tables (avoid allocations on hot path)
local GLOW_CONFIG = {
    ASSISTED = {
        frameKey    = "JustACAssistedGlow",  -- NOT "AssistedCombatHighlightFrame" — Masque auto-detects that key
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
        r = 0.3, g = 1.0, b = 0.3,          -- Green for defensive queue
        desaturate  = false,
        scaleMul    = 1.0,
        pauseOOC    = true,
        flagField   = "hasDefensiveGlow",
        pauseField  = "defensiveAnimPaused",
        clearsProc  = true,
    },
    GAP_CLOSER = {
        frameKey    = "GapCloserHighlightFrame",
        r = 1.0, g = 0.95, b = 0.4,         -- Bright gold (desaturated atlas → grey → gold tint)
        desaturate  = true,
        scaleMul    = 1.0,
        pauseOOC    = false,                 -- Always animate to draw attention
        flagField   = "hasGapCloserGlow",
        pauseField  = nil,                   -- No pause tracking needed
        clearsProc  = false,
    },
    INTERRUPT = {
        frameKey    = "InterruptHighlightFrame",
        r = 1.0, g = 0.95, b = 0.4,         -- Same gold as gap-closer
        desaturate  = true,
        scaleMul    = 1.0,
        pauseOOC    = false,                 -- Combat-only anyway, always animate
        flagField   = "hasInterruptGlow",
        pauseField  = nil,
        clearsProc  = true,
    },
}

-- Core start function — all glow types funnel through here
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
        local width = icon:GetWidth()
        highlightFrame:SetScale((width / 45) * config.scaleMul)
        TintMarchingAnts(highlightFrame, config.r, config.g, config.b, config.desaturate)
        if config.scaleMul ~= 1.0 then
            highlightFrame.Flipbook:SetAlpha(1)
        end
        highlightFrame:Show()
        icon[config.flagField] = true
    end

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
                if highlightFrame and highlightFrame.Flipbook and highlightFrame.Flipbook.Anim then
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

-- Core stop function — all glow types funnel through here
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
        HideProcGlow(icon)
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
    -- Legacy field: some callers check activeGlowStyle
    if icon then icon.activeGlowStyle = nil end
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

local function StartInterruptGlow(icon, isInCombat)
    StartMarchingAntsGlow(icon, GLOW_CONFIG.INTERRUPT, isInCombat)
end

local function StopInterruptGlow(icon)
    StopMarchingAntsGlow(icon, GLOW_CONFIG.INTERRUPT)
end

local function StartFlash(button)
    if not button.Flash then return end

    button.flashing = 1
    button.flashtime = FLASH_DURATION

    button.Flash:SetDrawLayer("OVERLAY", 2)
    button.Flash:SetAlpha(1.0)
    button.Flash:Show()

    if not button._prevFlashOnUpdate then
        local prev = button:GetScript("OnUpdate")
        if prev then
            local function wrapper(self, elapsed)
                UpdateFlash(self, elapsed)
                prev(self, elapsed)
            end
            button._prevFlashOnUpdate = prev
            button:SetScript("OnUpdate", wrapper)
        else
            local function runner(self, elapsed)
                UpdateFlash(self, elapsed)
            end
            button._prevFlashOnUpdate = FLASH_NO_PREV_HANDLER
            button:SetScript("OnUpdate", runner)
        end
    end
end

local function StopFlash(button)
    if not button then return end
    button.flashing = 0
    button.flashtime = 0
    if button.Flash then
        button.Flash:SetAlpha(0)
        button.Flash:Hide()
    end
    if button._prevFlashOnUpdate then
        if button._prevFlashOnUpdate == FLASH_NO_PREV_HANDLER then
            button:SetScript("OnUpdate", nil)
        else
            button:SetScript("OnUpdate", button._prevFlashOnUpdate)
        end
        button._prevFlashOnUpdate = nil
    end
end

UpdateFlash = function(button, elapsed)
    if not button or button.flashing ~= 1 or not button.Flash then return end

    button.flashtime = button.flashtime - elapsed

    if button.flashtime <= 0 then
        StopFlash(button)
        return
    end
end

local function HideAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            StopAssistedGlow(icon)
            StopDefensiveGlow(icon)
            StopGapCloserGlow(icon)
            StopInterruptGlow(icon)
            HideProcGlow(icon)
        end
    end
end

local function PauseAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            -- Assisted glow: stop animation (keeps frame visible but frozen)
            if icon.JustACAssistedGlow and icon.JustACAssistedGlow:IsShown() then
                if not icon.JustACAssistedGlow.Flipbook.Anim:IsPlaying() then
                    icon.JustACAssistedGlow.Flipbook.Anim:Play()
                end
                icon.JustACAssistedGlow.Flipbook.Anim:Stop()
            end
            -- Defensive glow: stop animation
            if icon.DefensiveHighlightFrame and icon.DefensiveHighlightFrame:IsShown() then
                if not icon.DefensiveHighlightFrame.Flipbook.Anim:IsPlaying() then
                    icon.DefensiveHighlightFrame.Flipbook.Anim:Play()
                end
                icon.DefensiveHighlightFrame.Flipbook.Anim:Stop()
            end
            -- Proc glow: hide entirely
            if icon.ProcGlowFrame then
                icon.ProcGlowFrame:Hide()
                if icon.ProcGlowFrame.ProcLoop then
                    icon.ProcGlowFrame.ProcLoop:Stop()
                end
            end
            -- Gap-closer/Interrupt glows deliberately excluded:
            -- they always animate (even OOC) for emphasis.
        end
    end
end

local function ResumeAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            -- Assisted glow: resume animation
            if icon.JustACAssistedGlow and icon.JustACAssistedGlow:IsShown() then
                if not icon.JustACAssistedGlow.Flipbook.Anim:IsPlaying() then
                    icon.JustACAssistedGlow.Flipbook.Anim:Play()
                end
            end
            -- Defensive glow: resume animation
            if icon.DefensiveHighlightFrame and icon.DefensiveHighlightFrame:IsShown() then
                if not icon.DefensiveHighlightFrame.Flipbook.Anim:IsPlaying() then
                    icon.DefensiveHighlightFrame.Flipbook.Anim:Play()
                end
            end
            -- Proc glow: restore if icon still has proc state
            if icon.ProcGlowFrame and icon.hasProcGlow then
                ShowProcGlow(icon)
            end
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
--   StartChannelFill(icon) — creates (once) / shows / plays for current channel
--   StopChannelFill(icon)  — stops anim, hides frame
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
    frame:SetFrameLevel(icon:GetFrameLevel() + 2)
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

-- Exports
UIAnimations.StartAssistedGlow = StartAssistedGlow
UIAnimations.StopAssistedGlow = StopAssistedGlow
UIAnimations.StartDefensiveGlow = StartDefensiveGlow
UIAnimations.StopDefensiveGlow = StopDefensiveGlow
UIAnimations.StartGapCloserGlow = StartGapCloserGlow
UIAnimations.StopGapCloserGlow = StopGapCloserGlow
UIAnimations.StartInterruptGlow = StartInterruptGlow
UIAnimations.StopInterruptGlow = StopInterruptGlow
UIAnimations.ShowProcGlow = ShowProcGlow
UIAnimations.HideProcGlow = HideProcGlow
UIAnimations.StartFlash = StartFlash
UIAnimations.StopFlash = StopFlash
UIAnimations.UpdateFlash = UpdateFlash
UIAnimations.HideAllGlows = HideAllGlows
UIAnimations.PauseAllGlows = PauseAllGlows
UIAnimations.ResumeAllGlows = ResumeAllGlows
UIAnimations.StartChannelFill = StartChannelFill
UIAnimations.StopChannelFill = StopChannelFill
