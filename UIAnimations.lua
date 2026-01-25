-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Animations Module
local UIAnimations = LibStub:NewLibrary("JustAC-UIAnimations", 1)
if not UIAnimations then return end

local GetTime = GetTime

-- Flash animation constants
local FLASH_DURATION = 0.2
local FLASH_MAX_SCALE = 1.12
local FLASH_SCALE_DURATION = 0.12

-- Forward declarations
local StopAssistedGlow
local StopDefensiveGlow
local UpdateFlash

-- Create a marching ants flipbook frame
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

-- Create a proc glow frame
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
    procLoop:SetAlpha(0)
    
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

local function TintMarchingAnts(highlightFrame, r, g, b)
    if highlightFrame and highlightFrame.Flipbook then
        highlightFrame.Flipbook:SetVertexColor(r, g, b, 1)
    end
end

local function StartAssistedGlow(icon, style, isInCombat)
    if not icon then return end
    
    style = style or "ASSISTED"
    
    if style == "PROC" then
        if not isInCombat then
            StopAssistedGlow(icon)
            return
        end
        
        local procFrame = icon.ProcGlowFrame
        if not procFrame then
            procFrame = CreateProcGlowFrame(icon, "ProcGlowFrame")
        end
        
        local width = icon:GetWidth()
        procFrame:SetScale(width / 45)
        
        if icon.AssistedCombatHighlightFrame and icon.AssistedCombatHighlightFrame:IsShown() then
            local antsFrame = icon.AssistedCombatHighlightFrame
            if not antsFrame.FadeOut then
                antsFrame.FadeOut = antsFrame:CreateAnimationGroup()
                local fadeAlpha = antsFrame.FadeOut:CreateAnimation("Alpha")
                fadeAlpha:SetChildKey("Flipbook")
                fadeAlpha:SetFromAlpha(1)
                fadeAlpha:SetToAlpha(0)
                fadeAlpha:SetDuration(0.15)
                antsFrame.FadeOut:SetScript("OnFinished", function()
                    antsFrame:Hide()
                    antsFrame.Flipbook.Anim:Stop()
                end)
            end
            antsFrame.FadeOut:Play()
            
            procFrame.ProcLoopFlipbook:SetAlpha(0)
            procFrame:Show()
            
            if not procFrame.FadeIn then
                procFrame.FadeIn = procFrame:CreateAnimationGroup()
                local fadeAlpha = procFrame.FadeIn:CreateAnimation("Alpha")
                fadeAlpha:SetChildKey("ProcLoopFlipbook")
                fadeAlpha:SetFromAlpha(0)
                fadeAlpha:SetToAlpha(1)
                fadeAlpha:SetDuration(0.15)
            end
            procFrame.FadeIn:Play()
        else
            procFrame.ProcLoopFlipbook:SetAlpha(1)
            procFrame:Show()
        end
        
        if not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Play()
        end
        
        icon.activeGlowStyle = style
    else
        local highlightFrame = icon.AssistedCombatHighlightFrame
        if not highlightFrame then
            highlightFrame = CreateMarchingAntsFrame(icon, "AssistedCombatHighlightFrame")
        end
        
        local width = icon:GetWidth()
        highlightFrame:SetScale((width / 45) * 1.02)
        
        TintMarchingAnts(highlightFrame, 1, 1, 1)
        
        if icon.ProcGlowFrame and icon.ProcGlowFrame:IsShown() then
            local procFrame = icon.ProcGlowFrame
            if not procFrame.FadeOut then
                procFrame.FadeOut = procFrame.ProcLoopFlipbook:CreateAnimationGroup()
                local fadeAlpha = procFrame.FadeOut:CreateAnimation("Alpha")
                fadeAlpha:SetFromAlpha(1)
                fadeAlpha:SetToAlpha(0)
                fadeAlpha:SetDuration(0.15)
                procFrame.FadeOut:SetScript("OnFinished", function()
                    procFrame:Hide()
                    procFrame.ProcLoop:Stop()
                end)
            end
            procFrame.FadeOut:Play()
            
            highlightFrame.Flipbook:SetAlpha(0)
            highlightFrame:Show()
            
            if not highlightFrame.FadeIn then
                highlightFrame.FadeIn = highlightFrame:CreateAnimationGroup()
                local fadeAlpha = highlightFrame.FadeIn:CreateAnimation("Alpha")
                fadeAlpha:SetChildKey("Flipbook")
                fadeAlpha:SetFromAlpha(0)
                fadeAlpha:SetToAlpha(1)
                fadeAlpha:SetDuration(0.15)
            end
            highlightFrame.FadeIn:Play()
        else
            highlightFrame.Flipbook:SetAlpha(1)
            highlightFrame:Show()
        end
        
        if isInCombat then
            if not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
            end
        else
            if not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
            end
            highlightFrame.Flipbook.Anim:Stop()
        end
        
        icon.activeGlowStyle = style
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
    
    if icon.ProcGlowFrame then
        icon.ProcGlowFrame:Hide()
        if icon.ProcGlowFrame.ProcLoop then
            icon.ProcGlowFrame.ProcLoop:Stop()
        end
    end
    
    icon.activeGlowStyle = nil
end

local function StartDefensiveGlow(icon, isProc, isInCombat)
    if not icon then return end
    
    if isProc then
        local procFrame = icon.ProcGlowFrame
        if not procFrame then
            procFrame = CreateProcGlowFrame(icon, "ProcGlowFrame")
        end
        
        local width = icon:GetWidth()
        procFrame:SetScale(width / 45)
        
        if icon.DefensiveHighlightFrame then
            icon.DefensiveHighlightFrame:Hide()
            if icon.DefensiveHighlightFrame.Flipbook and icon.DefensiveHighlightFrame.Flipbook.Anim then
                icon.DefensiveHighlightFrame.Flipbook.Anim:Stop()
            end
        end
        
        procFrame:Show()
        procFrame.ProcLoopFlipbook:SetAlpha(1)
        if not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Play()
        end
        
        icon.hasDefensiveGlow = true
        icon.defensiveGlowStyle = "PROC"
    else
        local highlightFrame = icon.DefensiveHighlightFrame
        if not highlightFrame then
            highlightFrame = CreateMarchingAntsFrame(icon, "DefensiveHighlightFrame")
        end
        
        local width = icon:GetWidth()
        highlightFrame:SetScale(width / 45)
        
        TintMarchingAnts(highlightFrame, 0.3, 1.0, 0.3)
        
        if icon.ProcGlowFrame then
            icon.ProcGlowFrame:Hide()
            if icon.ProcGlowFrame.ProcLoop then
                icon.ProcGlowFrame.ProcLoop:Stop()
            end
        end
        
        highlightFrame:Show()
        
        if isInCombat then
            highlightFrame.Flipbook.Anim:Play()
        else
            highlightFrame.Flipbook.Anim:Play()
            highlightFrame.Flipbook.Anim:Stop()
        end
        
        icon.hasDefensiveGlow = true
        icon.defensiveGlowStyle = "DEFENSIVE"
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
    
    if icon.ProcGlowFrame then
        icon.ProcGlowFrame:Hide()
        if icon.ProcGlowFrame.ProcLoop then
            icon.ProcGlowFrame.ProcLoop:Stop()
        end
    end
    
    icon.hasDefensiveGlow = false
    icon.defensiveGlowStyle = nil
end

local function StartFlash(button)
    if not button.Flash then return end
    
    button.flashing = 1
    button.flashtime = FLASH_DURATION
    
    button.Flash:SetDrawLayer("OVERLAY", 2)
    button.Flash:SetVertexColor(1, 1, 1, 1)
    button.Flash:SetAlpha(1.0)
    button.Flash:Show()
    
    button.flashScaleTimer = FLASH_SCALE_DURATION
    if button.FlashFrame and button.FlashFrame.SetScale then
        button.FlashFrame:SetScale(FLASH_MAX_SCALE)
    end
    
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
            button._prevFlashOnUpdate = nil
            button:SetScript("OnUpdate", runner)
        end
    end
end

local function StopFlash(button)
    if not button then return end
    button.flashing = 0
    button.flashtime = 0
    button.flashScaleTimer = nil
    if button.Flash then
        button.Flash:SetAlpha(0)
        button.Flash:Hide()
    end
    if button._prevFlashOnUpdate then
        button:SetScript("OnUpdate", button._prevFlashOnUpdate)
        button._prevFlashOnUpdate = nil
    else
        button:SetScript("OnUpdate", nil)
    end
end

UpdateFlash = function(button, elapsed)
    if not button or button.flashing ~= 1 or not button.Flash then return end
    
    button.flashtime = button.flashtime - elapsed
    
    if button.flashtime <= 0 then
        StopFlash(button)
        return
    end
    
    if button.flashScaleTimer and button.FlashFrame and button.FlashFrame.SetScale then
        local st = button.flashScaleTimer - elapsed
        if st <= 0 then
            button.flashScaleTimer = nil
            button.FlashFrame:SetScale(1)
        else
            button.flashScaleTimer = st
            local progress = 1 - (st / FLASH_SCALE_DURATION)
            local curScale = FLASH_MAX_SCALE - ((FLASH_MAX_SCALE - 1) * progress)
            button.FlashFrame:SetScale(curScale)
        end
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
                if icon.ProcGlowFrame.ProcLoop then
                    icon.ProcGlowFrame.ProcLoop:Stop()
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
UIAnimations.StartFlash = StartFlash
UIAnimations.StopFlash = StopFlash
UIAnimations.UpdateFlash = UpdateFlash
UIAnimations.HideAllGlows = HideAllGlows
UIAnimations.PauseAllGlows = PauseAllGlows
UIAnimations.ResumeAllGlows = ResumeAllGlows
