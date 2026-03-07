-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Animations Module - Manages glow and flash animations on buttons
local UIAnimations = LibStub:NewLibrary("JustAC-UIAnimations", 11)
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

local function StartAssistedGlow(icon, isInCombat)
    if not icon then return end

    local highlightFrame = icon.AssistedCombatHighlightFrame
    local needsInit = not highlightFrame

    if needsInit then
        highlightFrame = CreateMarchingAntsFrame(icon, "AssistedCombatHighlightFrame")
    end

    -- Only do setup work if frame was just created or not yet shown
    if needsInit or not highlightFrame:IsShown() then
        local width = icon:GetWidth()
        highlightFrame:SetScale((width / 45) * 1.02)

        -- White tint for assisted combat (RGB: 1, 1, 1 = white/no tint, appears blue in-game)
        TintMarchingAnts(highlightFrame, 1, 1, 1)
        highlightFrame.Flipbook:SetAlpha(1)
        highlightFrame:Show()

        icon.activeGlowStyle = "ASSISTED"
    end

    -- Animation state based on combat status
    -- FAST PATH: If already in correct state, exit early
    if isInCombat then
        -- In combat: ensure animation is playing
        if icon.assistedAnimPaused or not highlightFrame.Flipbook.Anim:IsPlaying() then
            highlightFrame.Flipbook.Anim:Play()
            icon.assistedAnimPaused = false
        end
    elseif not icon.assistedAnimPaused then
        -- Out of combat: set flag before scheduling to prevent duplicate timers per frame
        icon.assistedAnimPaused = true
        if not highlightFrame.Flipbook.Anim:IsPlaying() then
            highlightFrame.Flipbook.Anim:Play()
        end
        C_Timer.After(0.05, function()
            if highlightFrame and highlightFrame.Flipbook and highlightFrame.Flipbook.Anim then
                highlightFrame.Flipbook.Anim:Pause()
            end
        end)
    end

end

StopAssistedGlow = function(icon)
    if not icon then return end
    
    if icon.AssistedCombatHighlightFrame then
        icon.AssistedCombatHighlightFrame:Hide()
        if icon.AssistedCombatHighlightFrame.Flipbook and icon.AssistedCombatHighlightFrame.Flipbook.Anim then
            icon.AssistedCombatHighlightFrame.Flipbook.Anim:Stop()
        end
    end
    
    -- Hide native proc glow if present
    HideProcGlow(icon)

    icon.activeGlowStyle = nil
    icon.assistedAnimPaused = false
end

local function StartDefensiveGlow(icon, isInCombat)
    if not icon then return end

    local highlightFrame = icon.DefensiveHighlightFrame
    local needsInit = not highlightFrame

    if needsInit then
        highlightFrame = CreateMarchingAntsFrame(icon, "DefensiveHighlightFrame")
    end

    -- Only do setup work if frame was just created or not yet shown
    if needsInit or not highlightFrame:IsShown() then
        local width = icon:GetWidth()
        highlightFrame:SetScale(width / 45)

        -- Green tint for defensive queue (RGB: 0.3, 1.0, 0.3)
        TintMarchingAnts(highlightFrame, 0.3, 1.0, 0.3)

        highlightFrame:Show()
        icon.hasDefensiveGlow = true
    end

    -- Animation state based on combat status
    -- FAST PATH: If already in correct state, exit early
    if isInCombat then
        -- In combat: ensure animation is playing
        if icon.defensiveAnimPaused or not highlightFrame.Flipbook.Anim:IsPlaying() then
            highlightFrame.Flipbook.Anim:Play()
            icon.defensiveAnimPaused = false
        end
    elseif not icon.defensiveAnimPaused then
        -- Out of combat: set flag before scheduling to prevent duplicate timers per frame
        icon.defensiveAnimPaused = true
        if not highlightFrame.Flipbook.Anim:IsPlaying() then
            highlightFrame.Flipbook.Anim:Play()
        end
        C_Timer.After(0.05, function()
            if highlightFrame and highlightFrame.Flipbook and highlightFrame.Flipbook.Anim then
                highlightFrame.Flipbook.Anim:Pause()
            end
        end)
    end

end

StopDefensiveGlow = function(icon)
    if not icon then return end
    
    if icon.DefensiveHighlightFrame then
        icon.DefensiveHighlightFrame:Hide()
        if icon.DefensiveHighlightFrame.Flipbook and icon.DefensiveHighlightFrame.Flipbook.Anim then
            icon.DefensiveHighlightFrame.Flipbook.Anim:Stop()
        end
    end
    
    -- Also hide proc glow since defensive is being stopped
    HideProcGlow(icon)
    
    icon.hasDefensiveGlow = false
    icon.defensiveAnimPaused = false
end

-- ── Gold marching ants (interrupt + gap-closer) ────────────────────────────
-- Uses the same marching-ants flipbook as assisted/defensive but tinted gold.
-- Color scheme: blue/white = DPS queue, green = defensive, gold = interrupt/gap-closer.
-- Gap-closers always animate (even OOC) to draw attention to the injected spell.
-- Interrupts are combat-only anyway so they always animate too.

-- Gap-closer emphasis glow (gold marching ants, same animation as interrupt)
local function StartGapCloserGlow(icon)
    if not icon then return end

    local highlightFrame = icon.GapCloserHighlightFrame
    local needsInit = not highlightFrame

    if needsInit then
        highlightFrame = CreateMarchingAntsFrame(icon, "GapCloserHighlightFrame")
    end

    if needsInit or not highlightFrame:IsShown() then
        local width = icon:GetWidth()
        highlightFrame:SetScale(width / 45)
        -- Bright gold tint for gap-closer — desaturate atlas first (blue→grey) then tint
        TintMarchingAnts(highlightFrame, 1.0, 0.95, 0.4, true)
        highlightFrame:Show()
    end

    -- Always animate gap-closers (even OOC) to emphasise the injected spell
    if not highlightFrame.Flipbook.Anim:IsPlaying() then
        highlightFrame.Flipbook.Anim:Play()
    end
end

StopGapCloserGlow = function(icon)
    if not icon then return end
    if icon.GapCloserHighlightFrame then
        icon.GapCloserHighlightFrame:Hide()
        if icon.GapCloserHighlightFrame.Flipbook and icon.GapCloserHighlightFrame.Flipbook.Anim then
            icon.GapCloserHighlightFrame.Flipbook.Anim:Stop()
        end
    end
    icon.hasGapCloserGlow = false
end

-- Interrupt emphasis glow (gold marching ants, always animated — interrupts are combat-only)
local function StartInterruptGlow(icon, isInCombat)
    if not icon then return end

    local highlightFrame = icon.InterruptHighlightFrame
    local needsInit = not highlightFrame

    if needsInit then
        highlightFrame = CreateMarchingAntsFrame(icon, "InterruptHighlightFrame")
    end

    if needsInit or not highlightFrame:IsShown() then
        local width = icon:GetWidth()
        highlightFrame:SetScale(width / 45)
        -- Bright gold tint for interrupt — desaturate atlas first (blue→grey) then tint
        TintMarchingAnts(highlightFrame, 1.0, 0.95, 0.4, true)
        highlightFrame:Show()
    end

    -- Always animate (interrupts only show in combat)
    if not highlightFrame.Flipbook.Anim:IsPlaying() then
        highlightFrame.Flipbook.Anim:Play()
    end

    icon.hasInterruptGlow = true
end

local function StopInterruptGlow(icon)
    if not icon then return end
    if icon.InterruptHighlightFrame then
        icon.InterruptHighlightFrame:Hide()
        if icon.InterruptHighlightFrame.Flipbook and icon.InterruptHighlightFrame.Flipbook.Anim then
            icon.InterruptHighlightFrame.Flipbook.Anim:Stop()
        end
    end
    HideProcGlow(icon)  -- clear any normal proc glow shown alongside interrupt
    icon.hasInterruptGlow = false
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
        end
    end
end

local function PauseAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            if icon.AssistedCombatHighlightFrame and icon.AssistedCombatHighlightFrame:IsShown() then
                if not icon.AssistedCombatHighlightFrame.Flipbook.Anim:IsPlaying() then
                    icon.AssistedCombatHighlightFrame.Flipbook.Anim:Play()
                end
                icon.AssistedCombatHighlightFrame.Flipbook.Anim:Stop()
            end
            if icon.ProcGlowFrame then
                icon.ProcGlowFrame:Hide()
                if icon.ProcGlowFrame.Anim then
                    icon.ProcGlowFrame.Anim:Stop()
                end
            end
            -- Gap-closer glow deliberately excluded: it always animates
            -- (even OOC) and ResumeAllGlows has no matching restore code.
        end
    end
end

local function ResumeAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            if icon.AssistedCombatHighlightFrame and icon.AssistedCombatHighlightFrame:IsShown() then
                if not icon.AssistedCombatHighlightFrame.Flipbook.Anim:IsPlaying() then
                    icon.AssistedCombatHighlightFrame.Flipbook.Anim:Play()
                end
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
