-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Manager Module
local UIManager = LibStub:NewLibrary("JustAC-UIManager", 28)
if not UIManager then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local LSM = LibStub("LibSharedMedia-3.0")

-- Masque support
local Masque = LibStub("Masque", true)
local MasqueGroup = nil
local MasqueDefensiveGroup = nil

if Masque then
    MasqueGroup = Masque:Group("JustAssistedCombat", "Spell Queue")
    MasqueDefensiveGroup = Masque:Group("JustAssistedCombat", "Defensive")
end

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local UnitChannelInfo = UnitChannelInfo
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor

local function GetProfile()
    return BlizzardAPI and BlizzardAPI.GetProfile() or nil
end

-- Visual constants (defaults, profile overrides where applicable)
local DEFAULT_QUEUE_DESATURATION = 0
local QUEUE_ICON_BRIGHTNESS = 1.0
local QUEUE_ICON_OPACITY = 1.0
local CLICK_DARKEN_ALPHA = 0.4
local CLICK_INSET_PIXELS = 2

local function GetQueueDesaturation()
    local profile = GetProfile()
    return profile and profile.queueIconDesaturation or DEFAULT_QUEUE_DESATURATION
end

-- Helper function to set Hotkey to profile variables
local function ApplyHotkeyProfile(hotkeyText, button, isFirst)
    local profile = GetProfile()

    local db = profile.hotkeyText
    if not db or not hotkeyText or not button then return end

    -- Font
    local fontPath = LSM:Fetch("font", db.font or "Friz Quadrata TT")
    local fontSize = db.size or 12
    local flags = db.flags or "OUTLINE"
    local xOffset, yOffset
    
    if isFirst then
        xOffset = db.firstXOffset or -3
        yOffset = db.firstYOffset or -3
        local scale = profile.firstIconScale or 1.3
        fontSize = fontSize * scale
    else
        xOffset = db.queueXOffset or -2
        yOffset = db.queueYOffset or -2
    end
    
    hotkeyText:SetFont(fontPath, fontSize, flags)

    -- Color
    local c = db.color or { r = 1, g = 1, b = 1, a = 1 }
    hotkeyText:SetTextColor(c.r, c.g, c.b, c.a)

    -- Justification
    hotkeyText:SetJustifyH("RIGHT")

    -- Position
    hotkeyText:ClearAllPoints()

    local xOffset, yOffset
    if isFirst then
        xOffset = db.firstXOffset or -3
        yOffset = db.firstYOffset or -3
        local scale = profile.firstIconScale or 1.3
        fontSize = fontSize * scale
    else
        xOffset = db.queueXOffset or -2
        yOffset = db.queueYOffset or -2
    end

    hotkeyText:SetPoint(
        db.anchorPoint or "TOPRIGHT", -- point on hotkey text
        button,
        db.anchor or "TOPRIGHT",      -- parent anchor
        xOffset,
        yOffset
    )
end

-- Masque API access
function UIManager.GetMasqueGroup()
    return MasqueGroup
end

function UIManager.GetMasqueDefensiveGroup()
    return MasqueDefensiveGroup
end

function UIManager.IsMasqueEnabled()
    return Masque ~= nil
end

local spellIcons = {}
local defensiveIcon = nil  -- Position 0: defensive icon, positioned relative to position 1
local lastFrameState = {
    shouldShow = false,
    spellCount = 0,
    lastUpdate = 0,
}

local isInCombat = false
local hotkeysDirty = true  -- Flag to trigger hotkey refresh when action bars change

-- Invalidate hotkey cache (call when action bars or bindings change)
function UIManager.InvalidateHotkeyCache()
    hotkeysDirty = true
end

-- Forward declarations
local StopAssistedGlow
local StopDefensiveGlow

-- Helper to create a marching ants flipbook frame (reusable for different styles)
local function CreateMarchingAntsFrame(parent, frameKey)
    local highlightFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = highlightFrame
    highlightFrame:SetPoint("CENTER")
    highlightFrame:SetSize(45, 45)
    highlightFrame:SetFrameLevel(parent:GetFrameLevel() + 5)
    
    -- Create the flipbook texture
    local flipbook = highlightFrame:CreateTexture(nil, "OVERLAY")
    highlightFrame.Flipbook = flipbook
    flipbook:SetAtlas("rotationhelper_ants_flipbook")
    flipbook:SetSize(66, 66)
    flipbook:SetPoint("CENTER")
    
    -- Note: Second glow layer removed to match Blizzard's default brightness
    
    -- Create the animation group for the flipbook
    local animGroup = flipbook:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    flipbook.Anim = animGroup
    
    -- Create the flipbook animation (30 frames in 6 rows x 5 columns)
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

-- Helper to create a proc glow frame (gold spell proc animation)
-- Created at base 45x45 size (Blizzard standard), scaled via SetScale()
local function CreateProcGlowFrame(parent, frameKey)
    local procFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = procFrame
    procFrame:SetPoint("CENTER")
    procFrame:SetSize(45 * 1.4, 45 * 1.4)  -- Blizzard uses 1.4x button size
    procFrame:SetFrameLevel(parent:GetFrameLevel() + 6)
    procFrame:Hide()
    
    -- Note: Start burst removed - using loop animation only
    
    -- Create the loop animation texture (fills parent frame)
    local procLoop = procFrame:CreateTexture(nil, "OVERLAY")
    procFrame.ProcLoopFlipbook = procLoop
    procLoop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
    procLoop:SetAllPoints(procFrame)
    procLoop:SetAlpha(0)
    
    -- Create the loop animation group
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
    
    -- When frame hides, stop the loop
    procFrame:SetScript("OnHide", function()
        if procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Stop()
        end
    end)
    
    -- Initialize flipbook to first frame (Play/Stop trick to avoid showing whole atlas)
    loopGroup:Play()
    loopGroup:Stop()
    
    return procFrame
end

-- Apply color tint to marching ants flipbook
local function TintMarchingAnts(highlightFrame, r, g, b)
    if highlightFrame and highlightFrame.Flipbook then
        highlightFrame.Flipbook:SetVertexColor(r, g, b, 1)
    end
end

local function StartAssistedGlow(icon, style)
    if not icon then return end
    
    style = style or "ASSISTED"
    
    if style == "PROC" then
        -- Use native proc glow animation (gold) - only in combat
        if not isInCombat then
            StopAssistedGlow(icon)
            return
        end
        
        local procFrame = icon.ProcGlowFrame
        if not procFrame then
            procFrame = CreateProcGlowFrame(icon, "ProcGlowFrame")
        end
        
        -- Scale entire frame to match icon size (base size is 45)
        local width = icon:GetWidth()
        procFrame:SetScale(width / 45)
        
        -- Hide marching ants if showing (with fade out)
        if icon.AssistedCombatHighlightFrame and icon.AssistedCombatHighlightFrame:IsShown() then
            local antsFrame = icon.AssistedCombatHighlightFrame
            -- Quick fade out the ants while proc fades in
            if not antsFrame.FadeOut then
                antsFrame.FadeOut = antsFrame:CreateAnimationGroup()
                local fadeAlpha = antsFrame.FadeOut:CreateAnimation("Alpha")
                fadeAlpha:SetChildKey("Flipbook")
                fadeAlpha:SetFromAlpha(1)
                fadeAlpha:SetToAlpha(0)
                fadeAlpha:SetDuration(0.15)  -- 150ms fade out
                antsFrame.FadeOut:SetScript("OnFinished", function()
                    antsFrame:Hide()
                    antsFrame.Flipbook.Anim:Stop()
                end)
            end
            antsFrame.FadeOut:Play()
            
            -- Fade in proc from 0
            procFrame.ProcLoopFlipbook:SetAlpha(0)
            procFrame:Show()
            
            -- Create fade-in on the frame (not conflicting with ProcLoop)
            if not procFrame.FadeIn then
                procFrame.FadeIn = procFrame:CreateAnimationGroup()
                local fadeAlpha = procFrame.FadeIn:CreateAnimation("Alpha")
                fadeAlpha:SetChildKey("ProcLoopFlipbook")
                fadeAlpha:SetFromAlpha(0)
                fadeAlpha:SetToAlpha(1)
                fadeAlpha:SetDuration(0.15)  -- 150ms quick fade in
            end
            procFrame.FadeIn:Play()
        else
            -- No transition needed, just show at full alpha
            procFrame.ProcLoopFlipbook:SetAlpha(1)
            procFrame:Show()
        end
        
        if not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Play()
        end
        
        icon.activeGlowStyle = style
    else
        -- Use marching ants flipbook (ASSISTED = blue)
        -- Show even out of combat, but freeze animation
        local highlightFrame = icon.AssistedCombatHighlightFrame
        if not highlightFrame then
            highlightFrame = CreateMarchingAntsFrame(icon, "AssistedCombatHighlightFrame")
        end
        
        -- Scale frame to match icon size (base size is 45), slightly larger for visibility
        local width = icon:GetWidth()
        highlightFrame:SetScale((width / 45) * 1.02)  -- 2% larger than icon
        
        -- Apply color based on style (ASSISTED = default blue/white, no tint needed)
        TintMarchingAnts(highlightFrame, 1, 1, 1)  -- Reset to white (atlas is already blue)
        
        -- Hide proc glow if showing (with fade out)
        if icon.ProcGlowFrame and icon.ProcGlowFrame:IsShown() then
            local procFrame = icon.ProcGlowFrame
            -- Quick fade out the proc while ants fade in
            if not procFrame.FadeOut then
                procFrame.FadeOut = procFrame.ProcLoopFlipbook:CreateAnimationGroup()
                local fadeAlpha = procFrame.FadeOut:CreateAnimation("Alpha")
                fadeAlpha:SetFromAlpha(1)
                fadeAlpha:SetToAlpha(0)
                fadeAlpha:SetDuration(0.15)  -- 150ms fade out
                procFrame.FadeOut:SetScript("OnFinished", function()
                    procFrame:Hide()
                    procFrame.ProcLoop:Stop()
                end)
            end
            procFrame.FadeOut:Play()
            
            -- Fade in marching ants from 0
            highlightFrame.Flipbook:SetAlpha(0)
            highlightFrame:Show()
            
            -- Create fade-in on the frame (not conflicting with Flipbook.Anim)
            if not highlightFrame.FadeIn then
                highlightFrame.FadeIn = highlightFrame:CreateAnimationGroup()
                local fadeAlpha = highlightFrame.FadeIn:CreateAnimation("Alpha")
                fadeAlpha:SetChildKey("Flipbook")
                fadeAlpha:SetFromAlpha(0)
                fadeAlpha:SetToAlpha(1)
                fadeAlpha:SetDuration(0.15)  -- 150ms quick fade in
            end
            highlightFrame.FadeIn:Play()
        else
            -- No transition needed, just show at full alpha
            highlightFrame.Flipbook:SetAlpha(1)
            highlightFrame:Show()
        end
        
        -- Animate in combat, freeze (pause) out of combat
        -- Use Play/Stop trick to freeze on a single frame (Blizzard's approach)
        if isInCombat then
            if not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
                if highlightFrame.FlipbookGlow and highlightFrame.FlipbookGlow.Anim then
                    highlightFrame.FlipbookGlow.Anim:Play()
                end
            end
        else
            -- Play then Stop freezes on current frame instead of showing whole atlas
            if not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
                if highlightFrame.FlipbookGlow and highlightFrame.FlipbookGlow.Anim then
                    highlightFrame.FlipbookGlow.Anim:Play()
                end
            end
            highlightFrame.Flipbook.Anim:Stop()
            if highlightFrame.FlipbookGlow and highlightFrame.FlipbookGlow.Anim then
                highlightFrame.FlipbookGlow.Anim:Stop()
            end
        end
        
        icon.activeGlowStyle = style
    end
end

StopAssistedGlow = function(icon)
    if not icon then return end
    
    -- Stop the marching ants flipbook
    if icon.AssistedCombatHighlightFrame then
        icon.AssistedCombatHighlightFrame:Hide()
        if icon.AssistedCombatHighlightFrame.Flipbook and icon.AssistedCombatHighlightFrame.Flipbook.Anim then
            icon.AssistedCombatHighlightFrame.Flipbook.Anim:Stop()
        end
    end
    
    -- Stop the proc glow
    if icon.ProcGlowFrame then
        icon.ProcGlowFrame:Hide()
        if icon.ProcGlowFrame.ProcStartAnim then
            icon.ProcGlowFrame.ProcStartAnim:Stop()
        end
        if icon.ProcGlowFrame.ProcLoop then
            icon.ProcGlowFrame.ProcLoop:Stop()
        end
    end
    
    icon.activeGlowStyle = nil
end

-- Hide all glows completely (stop and hide frames)
local function HideAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            StopAssistedGlow(icon)
        end
    end
end

-- Pause marching ants animations (keep frames visible but frozen on first frame)
local function PauseAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            -- Pause marching ants animation - Play then Stop freezes on current frame
            -- (FlipBook animations show entire atlas grid if never played, but freeze on frame if stopped mid-play)
            if icon.AssistedCombatHighlightFrame and icon.AssistedCombatHighlightFrame:IsShown() then
                if not icon.AssistedCombatHighlightFrame.Flipbook.Anim:IsPlaying() then
                    -- If not playing, do Play/Stop to get to first frame
                    icon.AssistedCombatHighlightFrame.Flipbook.Anim:Play()
                    if icon.AssistedCombatHighlightFrame.FlipbookGlow and icon.AssistedCombatHighlightFrame.FlipbookGlow.Anim then
                        icon.AssistedCombatHighlightFrame.FlipbookGlow.Anim:Play()
                    end
                end
                icon.AssistedCombatHighlightFrame.Flipbook.Anim:Stop()
                if icon.AssistedCombatHighlightFrame.FlipbookGlow and icon.AssistedCombatHighlightFrame.FlipbookGlow.Anim then
                    icon.AssistedCombatHighlightFrame.FlipbookGlow.Anim:Stop()
                end
            end
            -- Hide proc glow out of combat (it's too flashy when frozen)
            if icon.ProcGlowFrame then
                icon.ProcGlowFrame:Hide()
                if icon.ProcGlowFrame.ProcStartAnim then
                    icon.ProcGlowFrame.ProcStartAnim:Stop()
                end
                if icon.ProcGlowFrame.ProcLoop then
                    icon.ProcGlowFrame.ProcLoop:Stop()
                end
            end
        end
    end
end

-- Resume marching ants animations
local function ResumeAllGlows(addon)
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            -- Resume marching ants animation if frame is visible
            if icon.AssistedCombatHighlightFrame and icon.AssistedCombatHighlightFrame:IsShown() then
                if not icon.AssistedCombatHighlightFrame.Flipbook.Anim:IsPlaying() then
                    icon.AssistedCombatHighlightFrame.Flipbook.Anim:Play()
                    if icon.AssistedCombatHighlightFrame.FlipbookGlow and icon.AssistedCombatHighlightFrame.FlipbookGlow.Anim then
                        icon.AssistedCombatHighlightFrame.FlipbookGlow.Anim:Play()
                    end
                end
            end
        end
    end
end

function UIManager.FreezeAllGlows(addon)
    isInCombat = false
    -- Pause animations but keep blue marching ants visible (frozen)
    PauseAllGlows(addon)
    
    -- Hide defensive glow completely (not part of main queue)
    if defensiveIcon then
        StopDefensiveGlow(defensiveIcon)
    end
end

function UIManager.UnfreezeAllGlows(addon)
    isInCombat = true
    -- Resume marching ants animations
    ResumeAllGlows(addon)
    -- Defensive glow will be shown on next health check if needed
end

--------------------------------------------------------------------------------
-- Defensive Icon Management
-- Shows a single defensive spell recommendation when health is low
--------------------------------------------------------------------------------

-- Start defensive glow - uses green-tinted marching ants, or proc glow if spell is proc'd
-- Out of combat: freeze animation on frame 1 (like main queue icons)
local function StartDefensiveGlow(icon, isProc)
    if not icon then return end
    
    if isProc then
        -- Use native proc glow animation (gold) for proc'd defensive
        local procFrame = icon.ProcGlowFrame
        if not procFrame then
            procFrame = CreateProcGlowFrame(icon, "ProcGlowFrame")
        end
        
        -- Scale entire frame to match icon size
        local width = icon:GetWidth()
        procFrame:SetScale(width / 45)
        
        -- Hide green marching ants if showing
        if icon.DefensiveHighlightFrame then
            icon.DefensiveHighlightFrame:Hide()
            if icon.DefensiveHighlightFrame.Flipbook and icon.DefensiveHighlightFrame.Flipbook.Anim then
                icon.DefensiveHighlightFrame.Flipbook.Anim:Stop()
            end
        end
        
        -- Show and play proc animation
        procFrame:Show()
        procFrame.ProcLoopFlipbook:SetAlpha(1)
        if not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Play()
        end
        
        icon.hasDefensiveGlow = true
        icon.defensiveGlowStyle = "PROC"
    else
        -- Use green-tinted marching ants for defensive
        local highlightFrame = icon.DefensiveHighlightFrame
        if not highlightFrame then
            highlightFrame = CreateMarchingAntsFrame(icon, "DefensiveHighlightFrame")
        end
        
        -- Scale frame to match icon size
        local width = icon:GetWidth()
        highlightFrame:SetScale(width / 45)
        
        -- Apply green tint
        TintMarchingAnts(highlightFrame, 0.3, 1.0, 0.3)
        
        -- Hide proc glow if showing
        if icon.ProcGlowFrame then
            icon.ProcGlowFrame:Hide()
            if icon.ProcGlowFrame.ProcLoop then
                icon.ProcGlowFrame.ProcLoop:Stop()
            end
        end
        
        highlightFrame:Show()
        
        -- Animate in combat, freeze (pause) out of combat (same as main queue icons)
        if isInCombat then
            highlightFrame.Flipbook.Anim:Play()
            if highlightFrame.FlipbookGlow and highlightFrame.FlipbookGlow.Anim then
                highlightFrame.FlipbookGlow.Anim:Play()
            end
        else
            -- Play then immediately stop to show first frame (Blizzard's trick)
            highlightFrame.Flipbook.Anim:Play()
            if highlightFrame.FlipbookGlow and highlightFrame.FlipbookGlow.Anim then
                highlightFrame.FlipbookGlow.Anim:Play()
            end
            highlightFrame.Flipbook.Anim:Stop()
            if highlightFrame.FlipbookGlow and highlightFrame.FlipbookGlow.Anim then
                highlightFrame.FlipbookGlow.Anim:Stop()
            end
        end
        
        icon.hasDefensiveGlow = true
        icon.defensiveGlowStyle = "DEFENSIVE"
    end
end

StopDefensiveGlow = function(icon)
    if not icon then return end
    
    -- Stop the green marching ants
    if icon.DefensiveHighlightFrame then
        icon.DefensiveHighlightFrame:Hide()
        if icon.DefensiveHighlightFrame.Flipbook and icon.DefensiveHighlightFrame.Flipbook.Anim then
            icon.DefensiveHighlightFrame.Flipbook.Anim:Stop()
        end
    end
    
    -- Stop the proc glow
    if icon.ProcGlowFrame then
        icon.ProcGlowFrame:Hide()
        if icon.ProcGlowFrame.ProcStartAnim then
            icon.ProcGlowFrame.ProcStartAnim:Stop()
        end
        if icon.ProcGlowFrame.ProcLoop then
            icon.ProcGlowFrame.ProcLoop:Stop()
        end
    end
    
    icon.hasDefensiveGlow = false
    icon.defensiveGlowStyle = nil
end

-- Flash animation for button press feedback (quick bright flash fade-out)
-- Flash timing and style
-- Mirror Blizzard actionbar behavior: strobe/toggle at ATTACK_BUTTON_FLASH_TIME for high visibility
local FLASH_TOGGLE_TIME = 0.4  -- Matches standard actionbar ATTACK_BUTTON_FLASH_TIME for visibility
local FLASH_INITIAL_ALPHA = 1.0  -- Full opacity for bright flash
local FLASH_MAX_SCALE = 1.12
local FLASH_SCALE_DURATION = 0.12  -- Quick scale back to normal

-- Forward declaration
local UpdateFlash

local function StartFlash(button)
    if not button then return end
    if not button.Flash then return end
    
    -- Force OVERLAY draw layer and white vertex color on both flash layers
    button.Flash:SetDrawLayer("OVERLAY", 2)
    button.Flash:SetVertexColor(1, 1, 1, 1)
    
    -- Single flash layer only: set draw layer and color
    
    -- Reset and start strobe-style flash (show/hide toggle) for good visibility
    button.flashing = 1
    button.flashtime = FLASH_TOGGLE_TIME
    -- Start a quick scale pulse on the flash frame for extra visibility
    button.flashScaleTimer = FLASH_SCALE_DURATION
    if button.FlashFrame and button.FlashFrame.SetScale then
        button.FlashFrame:SetScale(FLASH_MAX_SCALE)
    end
    button.Flash:SetAlpha(FLASH_INITIAL_ALPHA)
    button.Flash:Show()

    
    -- Set OnUpdate wrapper so UpdateFlash runs, but preserve any existing OnUpdate handler.
    -- We store the previous handler so StopFlash can restore it later.
    if not button._prevFlashOnUpdate then
        local prev = button:GetScript("OnUpdate")
        if prev then
            -- Wrap: call UpdateFlash first, then the previous handler
            local function wrapper(self, elapsed)
                UpdateFlash(self, elapsed)
                prev(self, elapsed)
            end
            button._prevFlashOnUpdate = prev
            button:SetScript("OnUpdate", wrapper)
        else
            -- No previous handler: simple UpdateFlash runner
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
    -- Restore any previously existing OnUpdate handler to avoid interfering with other code
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
    
    -- Strobe / toggle behavior used by Blizzard action buttons
    -- Check if we've crossed a toggle boundary
    if button.flashtime <= 0 then
        local overtime = -button.flashtime
        if overtime >= FLASH_TOGGLE_TIME then
            overtime = 0
        end
        button.flashtime = FLASH_TOGGLE_TIME - overtime

        if button.Flash:IsShown() then
            button.Flash:Hide()
        else
            button.Flash:Show()
        end
    end

    -- Animate scale pulse back to 1.0 (if active)
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

-- Export functions for external access
UIManager.StartFlash = StartFlash
UIManager.StopFlash = StopFlash
UIManager.UpdateFlash = UpdateFlash

-- Create the defensive icon (called from CreateSpellIcons)
local function CreateDefensiveIcon(addon, profile)
    if defensiveIcon then
        StopDefensiveGlow(defensiveIcon)
        -- Remove from Masque before cleanup
        if MasqueDefensiveGroup then
            MasqueDefensiveGroup:RemoveButton(defensiveIcon)
        end
        defensiveIcon:Hide()
        defensiveIcon:SetParent(nil)
        defensiveIcon = nil
    end
    
    if not profile.defensives or not profile.defensives.enabled then return end
    
    local button = CreateFrame("Button", nil, addon.mainFrame)
    if not button then return end
    
    -- Same size as position 1 icon (scaled)
    local firstIconScale = profile.firstIconScale or 1.2
    local actualIconSize = profile.iconSize * firstIconScale
    
    button:SetSize(actualIconSize, actualIconSize)
    
    -- Position based on user preference (LEFT, ABOVE, BELOW) relative to position 1 icon
    -- Must account for queue orientation since position 1 location changes
    local defPosition = profile.defensives.position or "LEFT"
    local queueOrientation = profile.queueOrientation or "LEFT"
    local spacing = profile.iconSpacing
    local firstIconCenter = actualIconSize / 2
    
    -- Determine position 1's anchor point based on queue orientation
    -- LEFT queue: pos1 at frame LEFT edge
    -- RIGHT queue: pos1 at frame RIGHT edge
    -- UP queue: pos1 at frame BOTTOM edge
    -- DOWN queue: pos1 at frame TOP edge
    
    if queueOrientation == "LEFT" then
        -- Queue grows left-to-right, pos1 is at LEFT of frame
        if defPosition == "ABOVE" then
            button:SetPoint("BOTTOM", addon.mainFrame, "TOPLEFT", firstIconCenter, spacing)
        elseif defPosition == "BELOW" then
            button:SetPoint("TOP", addon.mainFrame, "BOTTOMLEFT", firstIconCenter, -spacing)
        else -- LEFT
            button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -spacing, 0)
        end
    elseif queueOrientation == "RIGHT" then
        -- Queue grows right-to-left, pos1 is at RIGHT of frame
        if defPosition == "ABOVE" then
            button:SetPoint("BOTTOM", addon.mainFrame, "TOPRIGHT", -firstIconCenter, spacing)
        elseif defPosition == "BELOW" then
            button:SetPoint("TOP", addon.mainFrame, "BOTTOMRIGHT", -firstIconCenter, -spacing)
        else -- LEFT (means "before" pos1, so RIGHT side)
            button:SetPoint("LEFT", addon.mainFrame, "RIGHT", spacing, 0)
        end
    elseif queueOrientation == "UP" then
        -- Queue grows bottom-to-top, pos1 is at BOTTOM of frame
        if defPosition == "ABOVE" then
            -- "Above" in vertical means before pos1, so BELOW
            button:SetPoint("TOP", addon.mainFrame, "BOTTOM", 0, -spacing)
        elseif defPosition == "BELOW" then
            -- This doesn't make sense for UP orientation, treat as LEFT
            button:SetPoint("RIGHT", addon.mainFrame, "BOTTOMLEFT", -spacing, firstIconCenter)
        else -- LEFT
            button:SetPoint("RIGHT", addon.mainFrame, "BOTTOMLEFT", -spacing, firstIconCenter)
        end
    elseif queueOrientation == "DOWN" then
        -- Queue grows top-to-bottom, pos1 is at TOP of frame
        if defPosition == "ABOVE" then
            button:SetPoint("BOTTOM", addon.mainFrame, "TOP", 0, spacing)
        elseif defPosition == "BELOW" then
            -- "Below" means after queue end, so treat as LEFT
            button:SetPoint("RIGHT", addon.mainFrame, "TOPLEFT", -spacing, -firstIconCenter)
        else -- LEFT
            button:SetPoint("RIGHT", addon.mainFrame, "TOPLEFT", -spacing, -firstIconCenter)
        end
    end

    -- Slot background (Blizzard style depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground
    
    -- Slot art overlay
    local slotArt = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    slotArt:SetAllPoints(button)
    slotArt:SetAtlas("ui-hud-actionbar-iconframe-slot")
    slotArt:Hide()  -- Hidden: atlas texture was covering icon artwork on ARTWORK layer
    button.SlotArt = slotArt

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    iconTexture:Hide()  -- Start hidden, only show when spell is assigned
    button.iconTexture = iconTexture
    
    -- Note: Icon mask removed - atlas doesn't scale well with variable icon sizes
    
    -- Normal texture (button frame border - Blizzard style)
    local normalTexture = button:CreateTexture(nil, "OVERLAY", nil, 0)
    normalTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    normalTexture:SetSize(actualIconSize + 1, actualIconSize)
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    
    -- Flash overlay on high-level frame (+10) - above all animations, below hotkey (+15)
    local flashFrame = CreateFrame("Frame", nil, button)
    -- Anchor and size to button center so scaling remains centered
    -- Small nudge right to close visual gap on the right side of the flash art
    flashFrame:SetPoint("CENTER", button, "CENTER", 1, 0)
    -- Size the flash to match the icon (clamped to at least 1px for very small icons).
    local flashWidth = math_max(1, actualIconSize)
    flashFrame:SetSize(flashWidth, flashWidth)
    -- Place flash *below* marching-ants and proc glow so those highlight layers sit above the flash
    -- Marching ants are at +5 and proc glow at +6, so use +4 to be underneath them
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 4)
    
    -- Double-layer flash for increased brightness
    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetSize(flashWidth, flashWidth)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()
    
    button.Flash = flashTexture
    -- single-layer flash (no doubling)
    button.FlashFrame = flashFrame
    
    -- Flash animation state
    button.flashing = 0
    button.flashtime = 0

    -- Cooldown frame with Blizzard-style 3px inset from icon edges
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 3, -3)
    cooldown:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", -3, 3)
    cooldown:SetDrawEdge(false)  -- No gold edge for GCD swipe (only used for ability cooldowns)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)  -- Blizzard's swipe color
    cooldown:Hide()  -- Start hidden
    button.cooldown = cooldown
    
    -- Hotkey text on highest frame level to ensure visibility above all animations
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)  -- Above flash (+10)
    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    ApplyHotkeyProfile(hotkeyText,button, true)
    button.hotkeyText = hotkeyText
    button.hotkeyFrame = hotkeyFrame
    
    -- Tooltip (handles both spells and items)
    button:SetScript("OnEnter", function(self)
        if (self.spellID or self.itemID) and profile.showTooltips then
            local inCombat = UnitAffectingCombat("player")
            local showTooltip = not inCombat or profile.tooltipsInCombat
            
            if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ff00HEALING POTION|r")
                else
                    GameTooltip:SetSpellByID(self.spellID)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ff00DEFENSIVE SUGGESTION|r")
                end
                GameTooltip:AddLine("|cffff6666Health is low!|r")
                
                local hotkeyText = self.hotkeyText:GetText() or ""
                if hotkeyText and hotkeyText ~= "" then
                    GameTooltip:AddLine("|cffffff00Press " .. hotkeyText .. " to use|r")
                end
                GameTooltip:Show()
            end
        end
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    button.lastCooldownStart = 0
    button.lastCooldownDuration = 0
    button.spellID = nil
    button.itemID = nil
    button.itemCastSpellID = nil
    button.currentID = nil
    button.isItem = nil
    button:SetAlpha(0)  -- Start invisible for fade-in
    button:Hide()
    
    -- Create fade-in animation
    local fadeIn = button:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.2)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function()
        -- Apply user's frame opacity after fade completes
        local currentProfile = GetProfile()
        local frameOpacity = currentProfile and currentProfile.frameOpacity or 1.0
        button:SetAlpha(frameOpacity)
    end)
    button.fadeIn = fadeIn
    
    -- Create fade-out animation
    local fadeOut = button:CreateAnimationGroup()
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
    
    -- Register with Masque if available
    if MasqueDefensiveGroup then
        MasqueDefensiveGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            HotKey = button.hotkeyText,
            Normal = button.NormalTexture,
            -- Flash = button.Flash,  -- Removed: Masque skins override Flash color (causing red)
        })
    end
    
    defensiveIcon = button
    addon.defensiveIcon = defensiveIcon
end

-- Show the defensive icon with a specific spell or item
-- isItem: true if id is an itemID (potion), false/nil if it's a spellID
function UIManager.ShowDefensiveIcon(addon, id, isItem)
    if not addon or not id then return end
    
    -- Create icon if it doesn't exist
    if not defensiveIcon then
        local profile = GetProfile()
        if profile then
            CreateDefensiveIcon(addon, profile)
        end
    end
    
    if not defensiveIcon then return end
    
    local iconTexture, name
    local idChanged = (defensiveIcon.currentID ~= id) or (defensiveIcon.isItem ~= isItem)
    
    if isItem then
        -- It's an item (healing potion)
        local itemInfo = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
        if itemInfo then
            iconTexture = itemInfo.iconFileID
            name = itemInfo.itemName
        else
            -- Fallback to legacy API
            name, _, _, _, _, _, _, _, _, iconTexture = GetItemInfo(id)
        end
        if not iconTexture then return end
    else
        -- It's a spell
        local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(id)
        if not spellInfo then return end
        iconTexture = spellInfo.iconID
        name = spellInfo.name
    end
    
    defensiveIcon.currentID = id
    defensiveIcon.spellID = not isItem and id or nil  -- Only set spellID for spells
    defensiveIcon.itemID = isItem and id or nil
    defensiveIcon.isItem = isItem
    
    -- For items, store the spell ID that the item casts (for flash animation matching)
    defensiveIcon.itemCastSpellID = nil
    if isItem then
        local _, spellID = GetItemSpell(id)
        defensiveIcon.itemCastSpellID = spellID
    end
    
    if idChanged then
        defensiveIcon.iconTexture:SetTexture(iconTexture)
        defensiveIcon.iconTexture:Show()
        defensiveIcon.iconTexture:SetDesaturation(0)
        defensiveIcon.iconTexture:SetVertexColor(1, 1, 1, 1)
    end
    
    -- Update cooldown
    local start, duration
    if isItem then
        start, duration = GetItemCooldown(id)
    elseif BlizzardAPI and BlizzardAPI.GetSpellCooldown then
        start, duration = BlizzardAPI.GetSpellCooldown(id)
    end
    
    -- Early exit for secret values (12.0+): skip cooldown update if values are secret
    local startIsSecret = issecretvalue and issecretvalue(start)
    local durationIsSecret = issecretvalue and issecretvalue(duration)
    
    if not startIsSecret and not durationIsSecret then
        if start and start > 0 and duration and duration > 0 then
            if defensiveIcon.lastCooldownStart ~= start or defensiveIcon.lastCooldownDuration ~= duration then
                defensiveIcon.cooldown:SetCooldown(start, duration)
                defensiveIcon.cooldown:Show()
                defensiveIcon.lastCooldownStart = start
                defensiveIcon.lastCooldownDuration = duration
            end
        else
            if defensiveIcon.lastCooldownDuration ~= 0 then
                defensiveIcon.cooldown:Hide()
                defensiveIcon.lastCooldownStart = 0
                defensiveIcon.lastCooldownDuration = 0
            end
        end
    end
    -- If values are secret, leave cooldown display unchanged (graceful degradation)
    
    -- Update hotkey (for items, find by scanning action bars)
    local hotkey = ""
    if isItem then
        -- Find hotkey for item on action bar
        for slot = 1, 180 do
            local actionType, actionID = GetActionInfo(slot)
            if actionType == "item" and actionID == id then
                hotkey = GetBindingKey("ACTIONBUTTON" .. slot) or ""
                if hotkey == "" then
                    -- Check bonus bar bindings
                    local barOffset = slot > 12 and math.floor((slot - 1) / 12) or 0
                    local buttonIndex = ((slot - 1) % 12) + 1
                    hotkey = GetBindingKey("ACTIONBUTTON" .. buttonIndex) or ""
                end
                break
            end
        end
    else
        hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(id) or ""
    end
    
    -- Always normalize hotkey for key press matching (defensive icon doesn't use caching yet)
    if hotkey ~= "" then
        local normalized = hotkey:upper()
        -- Handle both formats: "S-5" and "S5" (ActionBarScanner uses no-dash format)
        normalized = normalized:gsub("^S%-", "SHIFT-")  -- S-5 -> SHIFT-5
        normalized = normalized:gsub("^S([^H])", "SHIFT-%1")  -- S5 -> SHIFT-5 (but not SHIFT)
        normalized = normalized:gsub("^C%-", "CTRL-")  -- C-5 -> CTRL-5
        normalized = normalized:gsub("^C([^T])", "CTRL-%1")  -- C5 -> CTRL-5 (but not CTRL)
        normalized = normalized:gsub("^A%-", "ALT-")  -- A-5 -> ALT-5
        normalized = normalized:gsub("^A([^L])", "ALT-%1")  -- A5 -> ALT-5 (but not ALT)
        normalized = normalized:gsub("^%+", "MOD-")  -- +5 -> MOD-5 (generic modifier)
        
        -- Only update previous hotkey if normalized changed (for flash grace period)
        if defensiveIcon.normalizedHotkey and defensiveIcon.normalizedHotkey ~= normalized then
            defensiveIcon.previousNormalizedHotkey = defensiveIcon.normalizedHotkey
            defensiveIcon.hotkeyChangeTime = GetTime()
        end
        defensiveIcon.normalizedHotkey = normalized
    else
        defensiveIcon.normalizedHotkey = nil
    end
    
    -- Only update hotkey text if it changed (prevents flicker)
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= hotkey then
        defensiveIcon.hotkeyText:SetText(hotkey)
    end
    
    -- Check if defensive spell has an active proc (only for spells, not items)
    local isProc = not isItem and C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(id) or false
    
    -- Early exit for secret boolean (12.0+): treat secret as no-proc
    if issecretvalue and issecretvalue(isProc) then
        isProc = false  -- Graceful degradation: no proc glow if we can't check
    end
    
    -- Start glow (green marching ants, or gold proc if spell is proc'd)
    StartDefensiveGlow(defensiveIcon, isProc)
    
    -- Show with fade-in animation if not already visible
    if not defensiveIcon:IsShown() then
        -- Stop any fade-out in progress
        if defensiveIcon.fadeOut and defensiveIcon.fadeOut:IsPlaying() then
            defensiveIcon.fadeOut:Stop()
        end
        defensiveIcon:Show()
        defensiveIcon:SetAlpha(0)
        if defensiveIcon.fadeIn then
            defensiveIcon.fadeIn:Play()
        else
            defensiveIcon:SetAlpha(1)
        end
    end
end

-- Hide the defensive icon with fade-out animation
function UIManager.HideDefensiveIcon(addon)
    if not defensiveIcon then return end
    
    if defensiveIcon:IsShown() or defensiveIcon.currentID then
        StopDefensiveGlow(defensiveIcon)
        defensiveIcon.spellID = nil
        defensiveIcon.itemID = nil
        defensiveIcon.itemCastSpellID = nil
        defensiveIcon.currentID = nil
        defensiveIcon.isItem = nil
        defensiveIcon.iconTexture:Hide()
        defensiveIcon.cooldown:Hide()
        defensiveIcon.hotkeyText:SetText("")
        
        -- Fade out instead of instant hide
        if defensiveIcon.fadeOut and not defensiveIcon.fadeOut:IsPlaying() then
            -- Stop any fade-in in progress
            if defensiveIcon.fadeIn and defensiveIcon.fadeIn:IsPlaying() then
                defensiveIcon.fadeIn:Stop()
            end
            defensiveIcon.fadeOut:Play()
        else
            defensiveIcon:Hide()
            defensiveIcon:SetAlpha(0)
        end
    end
end

function UIManager.CreateMainFrame(addon)
    local profile = addon:GetProfile()
    if not profile then return end
    
    addon.mainFrame = CreateFrame("Frame", "JustACFrame", UIParent)
    if not addon.mainFrame then return end
    
    UIManager.UpdateFrameSize(addon)
    
    local pos = profile.framePosition
    addon.mainFrame:SetPoint(pos.point, pos.x, pos.y)
    
    addon.mainFrame:EnableMouse(true)
    addon.mainFrame:SetMovable(true)
    addon.mainFrame:SetClampedToScreen(true)
    addon.mainFrame:RegisterForDrag("LeftButton")
    
    addon.mainFrame:SetScript("OnDragStart", function()
        local profile = addon:GetProfile()
        if profile and not profile.panelLocked then
            addon.mainFrame:StartMoving(true)  -- alwaysStartFromMouse = true
        end
    end)
    addon.mainFrame:SetScript("OnDragStop", function()
        addon.mainFrame:StopMovingOrSizing()
        UIManager.SavePosition(addon)
    end)
    
    -- Show/hide grab tab on hover
    addon.mainFrame:SetScript("OnEnter", function()
        if addon.grabTab and addon.grabTab.fadeIn then
            -- Stop any fade-out in progress
            if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
                addon.grabTab.fadeOut:Stop()
            end
            addon.grabTab:Show()
            addon.grabTab.fadeIn:Play()
        end
    end)
    
    addon.mainFrame:SetScript("OnLeave", function()
        if addon.grabTab and addon.grabTab.fadeOut and not addon.grabTab:IsMouseOver() and not addon.grabTab.isDragging then
            addon.grabTab.fadeOut:Play()
        end
    end)
    
    -- Right-click on main frame (empty areas) for options
    -- Note: Frame doesn't support RegisterForClicks, so we use OnMouseDown instead
    addon.mainFrame:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if not profile then return end
            
            if IsShiftKeyDown() then
                -- Toggle lock
                profile.panelLocked = not profile.panelLocked
                local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
            else
                -- Open options panel
                if addon.OpenOptionsPanel then
                    addon:OpenOptionsPanel()
                else
                    Settings.OpenToCategory("JustAssistedCombat")
                end
            end
        end
    end)
    
    -- Start hidden, only show when we have spells
    addon.mainFrame:SetAlpha(0)  -- Start invisible for fade-in
    addon.mainFrame:Hide()
    
    -- Create fade-in animation
    local fadeIn = addon.mainFrame:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.2)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function()
        -- Apply user's frame opacity after fade completes
        local currentProfile = addon:GetProfile()
        local frameOpacity = currentProfile and currentProfile.frameOpacity or 1.0
        addon.mainFrame:SetAlpha(frameOpacity)
    end)
    addon.mainFrame.fadeIn = fadeIn
    
    -- Create fade-out animation
    local fadeOut = addon.mainFrame:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        addon.mainFrame:Hide()
        addon.mainFrame:SetAlpha(0)
    end)
    addon.mainFrame.fadeOut = fadeOut
end

function UIManager.CreateGrabTab(addon)
    addon.grabTab = CreateFrame("Button", nil, addon.mainFrame, "BackdropTemplate")
    if not addon.grabTab then return end
    
    local profile = addon:GetProfile()
    local orientation = profile and profile.queueOrientation or "LEFT"
    local isVertical = (orientation == "UP" or orientation == "DOWN")
    
    -- Swap dimensions for vertical orientations
    if isVertical then
        addon.grabTab:SetSize(20, 12)
    else
        addon.grabTab:SetSize(12, 20)
    end
    
    -- Position at the end of the queue based on orientation
    -- Grab tab goes at the trailing edge with no additional offset
    if orientation == "RIGHT" then
        -- Icons grow left from right edge, grab tab at left
        addon.grabTab:SetPoint("LEFT", addon.mainFrame, "LEFT", 0, 0)
    elseif orientation == "UP" then
        -- Icons grow down from bottom, grab tab at top
        addon.grabTab:SetPoint("TOP", addon.mainFrame, "TOP", 0, 0)
    elseif orientation == "DOWN" then
        -- Icons grow up from top, grab tab at bottom
        addon.grabTab:SetPoint("BOTTOM", addon.mainFrame, "BOTTOM", 0, 0)
    else -- LEFT (default)
        -- Icons grow right from left edge, grab tab at right
        addon.grabTab:SetPoint("RIGHT", addon.mainFrame, "RIGHT", 0, 0)
    end
    
    addon.grabTab:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    
    addon.grabTab:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
    addon.grabTab:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    
    -- Dots arranged based on orientation (vertical vs horizontal grab tab)
    local dot1 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot1:SetSize(2, 2)
    dot1:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    local dot2 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot2:SetSize(2, 2)
    dot2:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    local dot3 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot3:SetSize(2, 2)
    dot3:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    if isVertical then
        -- Horizontal dot arrangement for vertical orientations
        dot1:SetPoint("CENTER", addon.grabTab, "CENTER", -4, 0)
        dot2:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 0)
        dot3:SetPoint("CENTER", addon.grabTab, "CENTER", 4, 0)
    else
        -- Vertical dot arrangement for horizontal orientations
        dot1:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 4)
        dot2:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 0)
        dot3:SetPoint("CENTER", addon.grabTab, "CENTER", 0, -4)
    end
    
    addon.grabTab:EnableMouse(true)
    addon.grabTab:RegisterForDrag("LeftButton")
    addon.grabTab:RegisterForClicks("RightButtonUp")
    
    addon.grabTab:SetScript("OnDragStart", function(self)
        local profile = addon:GetProfile()
        if not profile then return end
        
        -- Block dragging if locked
        if profile.panelLocked then
            return
        end
        
        -- Mark as dragging to prevent fade-out
        self.isDragging = true
        
        -- Stop any fade animation and ensure fully visible
        if self.fadeOut and self.fadeOut:IsPlaying() then
            self.fadeOut:Stop()
        end
        if self.fadeIn and self.fadeIn:IsPlaying() then
            self.fadeIn:Stop()
        end
        self:SetAlpha(1)
        
        -- Move the main frame (grab tab follows since it's anchored to it)
        -- Use alwaysStartFromMouse=true to prevent offset when dragging from child frame
        addon.mainFrame:StartMoving(true)
    end)
    
    addon.grabTab:SetScript("OnDragStop", function(self)
        addon.mainFrame:StopMovingOrSizing()
        UIManager.SavePosition(addon)
        
        -- Clear dragging flag and fade out if mouse isn't over frame/tab
        self.isDragging = false
        if not addon.mainFrame:IsMouseOver() and not self:IsMouseOver() and self.fadeOut then
            self.fadeOut:Play()
        end
    end)
    
    addon.grabTab:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if IsShiftKeyDown() then
                -- Shift+Right-click: toggle lock (safe in combat - only modifies addon db)
                local profile = addon:GetProfile()
                if profile then
                    profile.panelLocked = not profile.panelLocked
                    local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                end
            else
                -- Right-click: open options panel
                if addon.OpenOptionsPanel then
                    addon:OpenOptionsPanel()
                else
                    Settings.OpenToCategory("JustAssistedCombat")
                end
            end
        end
    end)
    
    addon.grabTab:SetScript("OnEnter", function()
        -- Stop any fade-out in progress and ensure fully visible
        if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
            addon.grabTab.fadeOut:Stop()
        end
        addon.grabTab:SetAlpha(1)
        
        local profile = addon:GetProfile()
        local isLocked = profile and profile.panelLocked
        
        GameTooltip:SetOwner(addon.grabTab, "ANCHOR_RIGHT")
        GameTooltip:SetText("JustAssistedCombat")
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
        GameTooltip:Show()
    end)
    
    addon.grabTab:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Hide grab tab if mouse leaves and isn't over main frame or being dragged
        if not addon.mainFrame:IsMouseOver() and not self.isDragging and addon.grabTab.fadeOut then
            addon.grabTab.fadeOut:Play()
        end
    end)
    
    -- Create fade-in animation
    local fadeIn = addon.grabTab:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.15)
    fadeInAlpha:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    addon.grabTab.fadeIn = fadeIn
    
    -- Create fade-out animation
    local fadeOut = addon.grabTab:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOutAlpha:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        addon.grabTab:Hide()
        addon.grabTab:SetAlpha(0)
    end)
    addon.grabTab.fadeOut = fadeOut
    
    -- Start hidden with alpha 0, show on hover
    addon.grabTab:SetAlpha(0)
    addon.grabTab:Hide()
end

function UIManager.CreateSpellIcons(addon)
    if not addon.db or not addon.db.profile or not addon.mainFrame then return end
    
    -- Remove old buttons from Masque before cleanup
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
    
    local profile = addon.db.profile
    local currentOffset = 0
    
    for i = 1, profile.maxIcons do
        local button = UIManager.CreateSingleSpellIcon(addon, i, currentOffset, profile)
        if button then
            spellIcons[i] = button
            -- Consistent spacing between all icons
            currentOffset = currentOffset + button:GetWidth() + profile.iconSpacing
        end
    end
    
    addon.spellIcons = spellIcons
    
    -- Create defensive icon (positioned relative to position 1 based on user settings)
    CreateDefensiveIcon(addon, profile)
end

-- SIMPLIFIED: Pure display-only icons with configuration only
function UIManager.CreateSingleSpellIcon(addon, index, offset, profile)
    local button = CreateFrame("Button", nil, addon.mainFrame)
    if not button then return nil end
    
    local isFirstIcon = (index == 1)
    local firstIconScale = profile.firstIconScale or 1.3
    local actualIconSize = isFirstIcon and (profile.iconSize * firstIconScale) or profile.iconSize
    local orientation = profile.queueOrientation or "LEFT"
    
    button:SetSize(actualIconSize, actualIconSize)
    
    -- Position based on orientation
    -- Icons start from one edge, grab tab is at the opposite edge
    if orientation == "RIGHT" then
        button:SetPoint("RIGHT", -offset, 0)
    elseif orientation == "UP" then
        button:SetPoint("BOTTOM", 0, offset)
    elseif orientation == "DOWN" then
        button:SetPoint("TOP", 0, -offset)
    else -- LEFT (default)
        button:SetPoint("LEFT", offset, 0)
    end

    -- Slot background (Blizzard style depth effect)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    slotBackground:SetAllPoints(button)
    slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    button.SlotBackground = slotBackground
    
    -- Slot art overlay
    local slotArt = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    slotArt:SetAllPoints(button)
    slotArt:SetAtlas("ui-hud-actionbar-iconframe-slot")
    slotArt:Hide()  -- Hidden: atlas texture was covering icon artwork on ARTWORK layer
    button.SlotArt = slotArt

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    button.iconTexture = iconTexture
    
    -- Note: Icon mask removed - atlas doesn't scale well with variable icon sizes
    -- The NormalTexture frame border provides the visual framing instead
    
    -- Normal texture (button frame border - Blizzard style)
    local normalTexture = button:CreateTexture(nil, "OVERLAY", nil, 0)
    normalTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    normalTexture:SetSize(actualIconSize + 1, actualIconSize)  -- Blizzard uses 46x45 for 45x45 button
    normalTexture:SetAtlas("UI-HUD-ActionBar-IconFrame")
    button.NormalTexture = normalTexture
    
    -- Pushed texture (shown when button is pressed - Blizzard style)
    local pushedTexture = button:CreateTexture(nil, "OVERLAY", nil, 1)
    pushedTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    pushedTexture:SetSize(actualIconSize + 1, actualIconSize)
    pushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
    pushedTexture:Hide()
    button.PushedTexture = pushedTexture
    
    -- Highlight texture (shown on mouseover - Blizzard style)
    local highlightTexture = button:CreateTexture(nil, "HIGHLIGHT", nil, 0)
    highlightTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    highlightTexture:SetSize(actualIconSize + 1, actualIconSize)
    highlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    button.HighlightTexture = highlightTexture
    
    -- Flash overlay on high-level frame (+10) - above all animations, below hotkey (+15)
    local flashFrame = CreateFrame("Frame", nil, button)
    -- Anchor and size to button center so scaling remains centered
    -- Small nudge right to close visual gap on the right side of the flash art
    flashFrame:SetPoint("CENTER", button, "CENTER", 1, 0)
    -- Defensive icon: size the flash to match the icon (clamped to at least 1px)
    local defFlashWidth = math_max(1, actualIconSize)
    flashFrame:SetSize(defFlashWidth, defFlashWidth)
    -- Defensive icon: also ensure flash is underneath proc/ants overlays
    flashFrame:SetFrameLevel(button:GetFrameLevel() + 4)
    
    -- Double-layer flash for increased brightness
    local flashTexture = flashFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    flashTexture:SetAllPoints(flashFrame)
    flashTexture:SetSize(defFlashWidth, defFlashWidth)
    flashTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    flashTexture:SetBlendMode("ADD")
    flashTexture:Hide()
    
    -- Only a single flash layer is required for defensive icons; ensure it's hidden by default
    -- (previous code mistakenly created a second texture which remained visible)
    button.Flash = flashTexture
    button.FlashFrame = flashFrame
    
    -- Flash animation state
    button.flashing = 0
    button.flashtime = 0

    -- Cooldown frame with Blizzard-style 3px inset from icon edges
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", 3, -3)
    cooldown:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", -3, 3)
    cooldown:SetDrawEdge(false)  -- No gold edge for GCD swipe (only used for ability cooldowns)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)  -- Blizzard's swipe color
    button.cooldown = cooldown
    
    -- Hotkey text on highest frame level to ensure visibility above all animations
    local hotkeyFrame = CreateFrame("Frame", nil, button)
    hotkeyFrame:SetAllPoints(button)
    hotkeyFrame:SetFrameLevel(button:GetFrameLevel() + 15)  -- Above flash (+10)
    local hotkeyText = hotkeyFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    ApplyHotkeyProfile(hotkeyText,button, isFirstIcon)
    
    button.hotkeyText = hotkeyText
    button.hotkeyFrame = hotkeyFrame
    
    -- Enable dragging from icons (delegates to main frame)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        local profile = addon:GetProfile()
        if not profile or profile.panelLocked then return end
        addon.mainFrame:StartMoving(true)  -- alwaysStartFromMouse = true
    end)
    
    button:SetScript("OnDragStop", function(self)
        addon.mainFrame:StopMovingOrSizing()
        UIManager.SavePosition(addon)
    end)
    
    -- Right-click menu for configuration
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local profile = addon:GetProfile()
            if profile and profile.panelLocked then return end
            
            if self.spellID then
                -- Spell-specific options
                if IsShiftKeyDown() then
                    addon:ToggleSpellBlacklist(self.spellID)
                else
                    addon:OpenHotkeyOverrideDialog(self.spellID)
                end
            else
                -- Empty slot - show general options
                if IsShiftKeyDown() then
                    -- Toggle lock
                    profile.panelLocked = not profile.panelLocked
                    local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                else
                    -- Open options panel
                    if addon.OpenOptionsPanel then
                        addon:OpenOptionsPanel()
                    else
                        Settings.OpenToCategory("JustAssistedCombat")
                    end
                end
            end
        end
    end)
    
    button:SetScript("OnEnter", function(self)
        -- Show grab tab when hovering over icons
        if addon.grabTab and addon.grabTab.fadeIn then
            -- Stop any fade-out in progress
            if addon.grabTab.fadeOut and addon.grabTab.fadeOut:IsPlaying() then
                addon.grabTab.fadeOut:Stop()
            end
            addon.grabTab:Show()
            addon.grabTab.fadeIn:Play()
        end
        
        if self.spellID and addon.db and addon.db.profile and addon.db.profile.showTooltips then
            local inCombat = UnitAffectingCombat("player")
            local showTooltip = not inCombat or addon.db.profile.tooltipsInCombat
            
            if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                
                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(self.spellID) or ""
                local isOverride = addon:GetHotkeyOverride(self.spellID) ~= nil
                
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
                    local isBlacklisted = SpellQueue and SpellQueue.IsSpellBlacklisted and SpellQueue.IsSpellBlacklisted(self.spellID)
                    if isBlacklisted then
                        GameTooltip:AddLine("|cffff6666Shift+Right-click: Remove from blacklist|r")
                    else
                        GameTooltip:AddLine("|cffff6666Shift+Right-click: Add to blacklist|r")
                    end
                end
                
                GameTooltip:Show()
            end
        end
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Hide grab tab if mouse isn't over main frame or grab tab, and not dragging
        if addon.grabTab and addon.grabTab.fadeOut and not addon.mainFrame:IsMouseOver() and not addon.grabTab:IsMouseOver() and not addon.grabTab.isDragging then
            addon.grabTab.fadeOut:Play()
        end
    end)
    
    button.lastCooldownStart = 0
    button.lastCooldownDuration = 0
    button.spellID = nil
    button:Hide()
    
    -- Register with Masque if available
    if MasqueGroup then
        MasqueGroup:AddButton(button, {
            Icon = button.iconTexture,
            Cooldown = button.cooldown,
            HotKey = button.hotkeyText,
            Normal = button.NormalTexture,
            Pushed = button.PushedTexture,
            Highlight = button.HighlightTexture,
            -- Flash = button.Flash,  -- Removed: Masque skins override Flash color (causing red)
        })
    end
    
    return button
end

function UIManager.RenderSpellQueue(addon, spellIDs)
    if not addon then return end
    local spellIconsRef = addon.spellIcons
    if not spellIconsRef then return end

    local profile = GetProfile()
    if not profile then return end

    local currentTime = GetTime()
    local hasSpells = spellIDs and #spellIDs > 0
    local spellCount = hasSpells and #spellIDs or 0
    
    -- Determine if frame should be visible
    local shouldShowFrame = hasSpells
    
    -- Hide queue out of combat if option is enabled
    if shouldShowFrame and profile.hideQueueOutOfCombat and not isInCombat then
        shouldShowFrame = false
    end
    
    -- Hide queue for healer specs if option is enabled
    if shouldShowFrame and profile.hideQueueForHealers and BlizzardAPI and BlizzardAPI.IsCurrentSpecHealer and BlizzardAPI.IsCurrentSpecHealer() then
        shouldShowFrame = false
    end
    
    -- Only update frame state if it actually changed
    local frameStateChanged = (lastFrameState.shouldShow ~= shouldShowFrame)
    local spellCountChanged = (lastFrameState.spellCount ~= spellCount)
    
    -- Cache commonly accessed values
    local maxIcons = profile.maxIcons
    local focusEmphasis = profile.focusEmphasis
    local queueDesaturation = GetQueueDesaturation()
    
    -- Check if player is channeling (grey out queue to emphasize not interrupting)
    local isChanneling = UnitChannelInfo("player") ~= nil
    
    -- Cache frequently called functions for hot path (avoid repeated table lookups)
    local GetSpellCooldown = BlizzardAPI.GetSpellCooldown
    local IsSpellUsable = BlizzardAPI.IsSpellUsable
    local GetSpellHotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey
    local GetCachedSpellInfo = SpellQueue.GetCachedSpellInfo
    
    -- Update individual icons (always do this part)
    for i = 1, maxIcons do
        local icon = spellIconsRef[i]
        if icon then
            local spellID = hasSpells and spellIDs[i] or nil
            local spellInfo = spellID and GetCachedSpellInfo(spellID)

            if spellID and spellInfo then
                -- Only update if spell changed for this slot
                local spellChanged = (icon.spellID ~= spellID)
                
                -- Track previous spell ID for grace period logic (avoid flashing spell that just moved)
                if spellChanged and icon.spellID then
                    icon.previousSpellID = icon.spellID
                end
                
                icon.spellID = spellID
                
                -- Cache icon texture reference for multiple accesses
                local iconTexture = icon.iconTexture
                
                -- Set texture when spell changes OR if texture has never been set (fixes missing artwork)
                if spellChanged or not iconTexture:GetTexture() then
                    iconTexture:SetTexture(spellInfo.iconID)
                end
                
                -- Always ensure texture is shown when spell is assigned (fixes missing artwork after reload)
                if not iconTexture:IsShown() then
                    iconTexture:Show()
                end
                
                -- Apply vertex color for queue icons (brightness/opacity)
                if i > 1 then
                    iconTexture:SetVertexColor(QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_OPACITY)
                else
                    iconTexture:SetVertexColor(1, 1, 1, 1)
                end

                -- Update cooldown display (including GCD for timing feedback)
                local start, duration = GetSpellCooldown(spellID)
                
                -- Early exit for secret values (12.0+): skip cooldown update if values are secret
                local startIsSecret = issecretvalue and issecretvalue(start)
                local durationIsSecret = issecretvalue and issecretvalue(duration)
                
                if not startIsSecret and not durationIsSecret then
                    if start and start > 0 and duration and duration > 0 then
                        -- Only update cooldown if values changed significantly
                        if icon.lastCooldownStart ~= start or icon.lastCooldownDuration ~= duration then
                            icon.cooldown:SetCooldown(start, duration)
                            icon.cooldown:Show()
                            icon.lastCooldownStart = start
                            icon.lastCooldownDuration = duration
                        end
                    else
                        if icon.lastCooldownDuration ~= 0 then
                            icon.cooldown:Hide()
                            icon.lastCooldownStart = 0
                            icon.lastCooldownDuration = 0
                        end
                    end
                end
                -- If values are secret, leave cooldown display unchanged (graceful degradation)

                -- Check if spell has an active proc (overlay)
                local isProc = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(spellID)
                
                -- Early exit for secret boolean (12.0+): treat secret as no-proc
                if issecretvalue and issecretvalue(isProc) then
                    isProc = false  -- Graceful degradation: no proc glow if we can't check
                end

                if i == 1 and focusEmphasis then
                    -- First icon: blue glow normally, gold when proc'd
                    local style = isProc and "PROC" or "ASSISTED"
                    StartAssistedGlow(icon, style)
                elseif isProc then
                    -- Queue icons (2+): gold glow only when proc'd
                    StartAssistedGlow(icon, "PROC")
                else
                    -- No glow for non-proc'd queue icons
                    StopAssistedGlow(icon)
                end

                -- Hotkey lookup optimization: only query ActionBarScanner when action bars change
                -- Store result in icon.cachedHotkey and reuse until invalidated by ACTIONBAR_SLOT_CHANGED/UPDATE_BINDINGS
                local hotkey
                if hotkeysDirty or spellChanged or not icon.cachedHotkey then
                    hotkey = GetSpellHotkey and GetSpellHotkey(spellID) or ""
                    icon.cachedHotkey = hotkey
                else
                    hotkey = icon.cachedHotkey
                end
                
                -- Always normalize hotkey for key press matching (even if cached)
                -- This ensures normalizedHotkey is set even when hotkey text hasn't changed
                if hotkey ~= "" then
                    local normalized = hotkey:upper()
                    -- Handle both formats: "S-5" and "S5" (ActionBarScanner uses no-dash format)
                    normalized = normalized:gsub("^S%-", "SHIFT-")  -- S-5 -> SHIFT-5
                    normalized = normalized:gsub("^S([^H])", "SHIFT-%1")  -- S5 -> SHIFT-5 (but not SHIFT)
                    normalized = normalized:gsub("^C%-", "CTRL-")  -- C-5 -> CTRL-5
                    normalized = normalized:gsub("^C([^T])", "CTRL-%1")  -- C5 -> CTRL-5 (but not CTRL)
                    normalized = normalized:gsub("^A%-", "ALT-")  -- A-5 -> ALT-5
                    normalized = normalized:gsub("^A([^L])", "ALT-%1")  -- A5 -> ALT-5 (but not ALT)
                    normalized = normalized:gsub("^%+", "MOD-")  -- +5 -> MOD-5 (generic modifier)
                    
                    -- Only update previous hotkey if normalized changed (for flash grace period)
                    if icon.normalizedHotkey and icon.normalizedHotkey ~= normalized then
                        icon.previousNormalizedHotkey = icon.normalizedHotkey
                        icon.hotkeyChangeTime = currentTime
                    end
                    icon.normalizedHotkey = normalized
                else
                    icon.normalizedHotkey = nil
                end
                
                -- Only update hotkey text if it changed (prevents flicker)
                local currentHotkey = icon.hotkeyText:GetText() or ""
                if currentHotkey ~= hotkey then
                    icon.hotkeyText:SetText(hotkey)
                end
                
                -- Update desaturation based on:
                -- 1. Channeling (grey out all icons to emphasize not interrupting)
                -- 2. Queue position (fade setting for positions 2+)
                -- 3. Spell usability (grey out when not enough resources in combat)
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                
                if isChanneling then
                    -- Channeling - grey out entire queue to emphasize not interrupting
                    iconTexture:SetDesaturation(1.0)
                elseif isInCombat then
                    local isUsable, notEnoughResources = IsSpellUsable(spellID)
                    if not isUsable and notEnoughResources then
                        -- Not enough resources - full grey out (overrides fade setting)
                        iconTexture:SetDesaturation(1.0)
                    else
                        -- Usable or on cooldown - apply queue fade setting
                        iconTexture:SetDesaturation(baseDesaturation)
                    end
                else
                    -- Out of combat - just apply queue fade setting
                    iconTexture:SetDesaturation(baseDesaturation)
                end

                -- Only show if not already shown
                if not icon:IsShown() then
                    icon:Show()
                end
            else
                -- No spell for this slot - show empty slot (background + border only)
                if icon.spellID then
                    icon.spellID = nil
                    icon.iconTexture:Hide()
                    icon.cooldown:Hide()
                    StopAssistedGlow(icon)
                    icon.hotkeyText:SetText("")
                    -- Keep SlotBackground and NormalTexture visible for empty slot appearance
                    -- Don't hide the entire icon frame
                end
                
                -- Ensure empty slot is visible (shows background texture + border)
                if not icon:IsShown() then
                    icon:Show()
                end
            end
        end
    end
    
    -- Clear hotkey dirty flag after processing all icons
    hotkeysDirty = false
    
    -- Update frame visibility with fade animations only when state actually changes
    if addon.mainFrame and (frameStateChanged or spellCountChanged) then
        if shouldShowFrame then
            if not addon.mainFrame:IsShown() then
                -- Stop any fade-out in progress
                if addon.mainFrame.fadeOut and addon.mainFrame.fadeOut:IsPlaying() then
                    addon.mainFrame.fadeOut:Stop()
                end
                addon.mainFrame:Show()
                addon.mainFrame:SetAlpha(0)
                if addon.mainFrame.fadeIn then
                    addon.mainFrame.fadeIn:Play()
                else
                    -- Fallback if no animation (shouldn't happen)
                    addon.mainFrame:SetAlpha(profile.frameOpacity or 1.0)
                end
            end
        else
            if addon.mainFrame:IsShown() then
                -- Fade out instead of instant hide
                if addon.mainFrame.fadeOut and not addon.mainFrame.fadeOut:IsPlaying() then
                    -- Stop any fade-in in progress
                    if addon.mainFrame.fadeIn and addon.mainFrame.fadeIn:IsPlaying() then
                        addon.mainFrame.fadeIn:Stop()
                    end
                    addon.mainFrame.fadeOut:Play()
                else
                    -- Fallback or already fading out
                    if not addon.mainFrame.fadeOut then
                        addon.mainFrame:Hide()
                        addon.mainFrame:SetAlpha(0)
                    end
                end
            end
        end
    end
    
    -- Update click-through state based on lock (check every render for responsiveness)
    local isLocked = profile.panelLocked
    
    -- Main frame click-through (but grab tab stays interactive for unlock)
    if addon.mainFrame then
        addon.mainFrame:EnableMouse(not isLocked)
    end
    
    for i = 1, maxIcons do
        local icon = spellIconsRef[i]
        if icon then
            -- EnableMouse(false) = click-through, EnableMouse(true) = interactive
            icon:EnableMouse(not isLocked)
        end
    end
    if defensiveIcon then
        defensiveIcon:EnableMouse(not isLocked)
    end
    
    -- Apply global frame opacity (affects main frame and defensive icon)
    -- Skip if fade animation is playing to avoid interrupting the fade
    local frameOpacity = profile.frameOpacity or 1.0
    if addon.mainFrame then
        local isFading = (addon.mainFrame.fadeIn and addon.mainFrame.fadeIn:IsPlaying()) or
                         (addon.mainFrame.fadeOut and addon.mainFrame.fadeOut:IsPlaying())
        if not isFading then
            addon.mainFrame:SetAlpha(frameOpacity)
        end
    end
    if defensiveIcon then
        -- Defensive icon is separate, apply same opacity
        -- Also skip if fading
        local isFading = (defensiveIcon.fadeIn and defensiveIcon.fadeIn:IsPlaying()) or
                         (defensiveIcon.fadeOut and defensiveIcon.fadeOut:IsPlaying())
        if not isFading then
            defensiveIcon:SetAlpha(frameOpacity)
        end
    end
    
    -- Update tracking state
    lastFrameState.shouldShow = shouldShowFrame
    lastFrameState.spellCount = spellCount
    lastFrameState.lastUpdate = currentTime
end

function UIManager.UpdateFrameSize(addon)
    local profile = addon:GetProfile()
    if not profile or not addon.mainFrame then return end

    local newMaxIcons = profile.maxIcons
    local newIconSize = profile.iconSize
    local newIconSpacing = profile.iconSpacing
    local firstIconScale = profile.firstIconScale or 1.3
    local orientation = profile.queueOrientation or "LEFT"

    UIManager.CreateSpellIcons(addon)
    
    -- Recreate grab tab to update position/size for new orientation
    if addon.grabTab then
        addon.grabTab:Hide()
        addon.grabTab:SetParent(nil)
        addon.grabTab = nil
    end
    UIManager.CreateGrabTab(addon)

    local firstIconSize = newIconSize * firstIconScale
    local remainingIconsSize = (newMaxIcons > 1) and ((newMaxIcons - 1) * newIconSize) or 0
    local totalSpacing = (newMaxIcons > 1) and ((newMaxIcons - 1) * newIconSpacing) or 0
    local totalLength = firstIconSize + remainingIconsSize + totalSpacing
    
    -- Calculate grab tab spacing: always at least as large as icon spacing
    local isVertical = (orientation == "UP" or orientation == "DOWN")
    local grabTabLength = 12

    -- The normalTexture used for icon borders extends 1px beyond the button
    -- width which visually reduces the gap. We want the visual gap between
    -- the last icon and the grab tab to equal `newIconSpacing`.
    --
    -- Compute grabTabSpacing so that (grabTabSpacing - grabTabLength - visualOverflow) == newIconSpacing
    local visualOverflow = 1 -- visual overflow of icon borders
    local grabTabSpacing
    if isVertical then
        -- For vertical queues: spacing down/up should equal icon spacing + grab tab length
        grabTabSpacing = newIconSpacing + grabTabLength
    else
        -- For horizontal queues: account for 1px icon border overflow
        grabTabSpacing = newIconSpacing + grabTabLength + visualOverflow
    end

    -- Expand main frame to include grab tab area + consistent spacing
    if isVertical then
        addon.mainFrame:SetSize(firstIconSize, totalLength + grabTabSpacing)
    else
        addon.mainFrame:SetSize(totalLength + grabTabSpacing, firstIconSize)
    end
end

function UIManager.SavePosition(addon)
    if not addon.mainFrame then return end
    local profile = addon:GetProfile()
    if not profile then return end
    
    local point, _, _, x, y = addon.mainFrame:GetPoint()
    profile.framePosition = {
        point = point or "CENTER",
        x = x or 0,
        y = y or -150
    }
end

function UIManager.OpenHotkeyOverrideDialog(addon, spellID)
    if not addon or not spellID then return end
    
    local spellInfo = addon:GetCachedSpellInfo(spellID)
    if not spellInfo then return end
    
    StaticPopupDialogs["JUSTAC_HOTKEY_OVERRIDE"] = {
        text = "Set custom hotkey display for:\n|T" .. (spellInfo.iconID or 0) .. ":16:16:0:0|t " .. spellInfo.name,
        button1 = "Set",
        button2 = "Remove", 
        button3 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 200,
        OnShow = function(self)
            local currentHotkey = addon:GetHotkeyOverride(self.data.spellID) or ""
            self.EditBox:SetText(currentHotkey)
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end,
        OnAccept = function(self)
            local newHotkey = self.EditBox:GetText()
            addon:SetHotkeyOverride(self.data.spellID, newHotkey)
        end,
        OnAlt = function(self)
            addon:SetHotkeyOverride(self.data.spellID, nil)
        end,
        EditBoxOnEnterPressed = function(self)
            local newHotkey = self:GetText()
            addon:SetHotkeyOverride(self:GetParent().data.spellID, newHotkey)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    
    StaticPopup_Show("JUSTAC_HOTKEY_OVERRIDE", nil, nil, {spellID = spellID})
end
