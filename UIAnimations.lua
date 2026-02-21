-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Animations Module - Manages glow and flash animations on buttons
local UIAnimations = LibStub:NewLibrary("JustAC-UIAnimations", 4)
if not UIAnimations then return end

local GetTime = GetTime

-- Flash animation constants
local FLASH_DURATION = 0.2

-- Sentinel value: indicates no previous OnUpdate handler existed before flash
-- Must be a unique truthy value so the guard check works correctly
local FLASH_NO_PREV_HANDLER = {}

-- Forward declarations
local StopAssistedGlow
local StopDefensiveGlow
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

local function TintMarchingAnts(highlightFrame, r, g, b)
    if highlightFrame and highlightFrame.Flipbook then
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

        -- Show blue/white ants frame
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
        -- Out of combat: pause after brief initialization
        -- Set flag IMMEDIATELY to prevent scheduling duplicate timers every frame
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
    -- else: already paused out of combat, nothing to do
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
        -- Out of combat: pause after brief initialization
        -- Set flag IMMEDIATELY to prevent scheduling duplicate timers every frame
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
    -- else: already paused out of combat, nothing to do
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

-- ── Interrupt Glow (red-tinted proc glow) ───────────────────────────────────
-- Uses the bright proc glow flipbook (same atlas as ShowProcGlow) but tinted
-- red for interrupt urgency.  Much more visible than the marching-ants flipbook
-- which rendered nearly black when tinted red.
-- Color scheme: blue/white = DPS,  green = defensive,  red = interrupt.

local function CreateInterruptProcGlowFrame(parent)
    local procFrame = CreateFrame("FRAME", nil, parent)
    parent.InterruptProcGlowFrame = procFrame
    procFrame:SetPoint("CENTER")
    procFrame:SetSize(45 * 1.4, 45 * 1.4)
    procFrame:SetFrameLevel(parent:GetFrameLevel() + 5)
    procFrame:Hide()

    local procLoop = procFrame:CreateTexture(nil, "OVERLAY")
    procFrame.ProcLoopFlipbook = procLoop
    procLoop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
    procLoop:SetAllPoints(procFrame)
    procLoop:SetAlpha(1)
    -- Red tint — bright enough to see flipbook detail (RGB: 1.0, 0.55, 0.55)
    procLoop:SetVertexColor(1.0, 0.55, 0.55, 1)

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

local function StartInterruptGlow(icon, isInCombat)
    if not icon then return end

    local procFrame = icon.InterruptProcGlowFrame
    if not procFrame then
        procFrame = CreateInterruptProcGlowFrame(icon)
    end

    local width = icon:GetWidth()
    procFrame:SetScale(width / 45)

    procFrame.ProcLoopFlipbook:SetAlpha(1)
    procFrame:Show()

    if not procFrame.ProcLoop:IsPlaying() then
        procFrame.ProcLoop:Play()
    end

    icon.hasInterruptGlow = true
end

local function StopInterruptGlow(icon)
    if not icon then return end

    if icon.InterruptProcGlowFrame then
        icon.InterruptProcGlowFrame:Hide()
        if icon.InterruptProcGlowFrame.ProcLoop:IsPlaying() then
            icon.InterruptProcGlowFrame.ProcLoop:Stop()
        end
    end

    -- Also hide the normal proc glow if it was shown for ImportantCast
    HideProcGlow(icon)

    icon.hasInterruptGlow = false
    icon.interruptAnimPaused = false
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

-- Exports
UIAnimations.StartAssistedGlow = StartAssistedGlow
UIAnimations.StopAssistedGlow = StopAssistedGlow
UIAnimations.StartDefensiveGlow = StartDefensiveGlow
UIAnimations.StopDefensiveGlow = StopDefensiveGlow
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
