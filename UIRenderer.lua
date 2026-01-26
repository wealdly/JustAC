-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Renderer Module v2
-- Changed: Consolidated proc detection to use BlizzardAPI.IsSpellProcced()
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 2)
if not UIRenderer then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)

if not BlizzardAPI or not ActionBarScanner or not SpellQueue or not UIAnimations or not UIFrameFactory then
    return
end

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor
local string_upper = string.upper
local string_gsub = string.gsub

-- Shared hotkey normalization helper (avoids duplicate code and reduces hotpath overhead)
-- Converts abbreviated keybinds to full format: S-5 → SHIFT-5, C-5 → CTRL-5, etc.
local function NormalizeHotkey(hotkey)
    if not hotkey or hotkey == "" then return nil end
    local normalized = string_upper(hotkey)
    normalized = string_gsub(normalized, "^S%-", "SHIFT-")  -- S-5 -> SHIFT-5
    normalized = string_gsub(normalized, "^S([^H])", "SHIFT-%1")  -- S5 -> SHIFT-5 (but not SHIFT)
    normalized = string_gsub(normalized, "^C%-", "CTRL-")  -- C-5 -> CTRL-5
    normalized = string_gsub(normalized, "^C([^T])", "CTRL-%1")  -- C5 -> CTRL-5 (but not CTRL)
    normalized = string_gsub(normalized, "^A%-", "ALT-")  -- A-5 -> ALT-5
    normalized = string_gsub(normalized, "^A([^L])", "ALT-%1")  -- A5 -> ALT-5 (but not ALT)
    normalized = string_gsub(normalized, "^%+", "MOD-")  -- +5 -> MOD-5 (generic modifier)
    return normalized
end

-- Shared cooldown update helper (consolidates duplicate logic for main icons and defensive icon)
-- Updates icon.cooldown widget with caching to avoid redundant SetCooldown calls
-- Handles WoW 12.0 secret values gracefully
-- Uses tolerance-based comparison to prevent flickering from minor floating-point differences
local COOLDOWN_START_TOLERANCE = 0.05  -- Only update if start time differs by more than 50ms (new GCD)

local function UpdateIconCooldown(icon, start, duration)
    local startIsSecret = issecretvalue and issecretvalue(start)
    local durationIsSecret = issecretvalue and issecretvalue(duration)
    
    if startIsSecret or durationIsSecret then
        -- Secret values: pass to widget once, then skip until non-secret
        if not icon.lastCooldownWasSecret then
            icon.cooldown:SetCooldown(start, duration)
            icon.cooldown:Show()
            icon.lastCooldownWasSecret = true
            icon.lastCooldownStart = nil
            icon.lastCooldownDuration = nil
        end
    elseif start and start > 0 and duration and duration > 0 then
        -- Valid cooldown: update only if start time changed significantly (new GCD/cooldown)
        -- This prevents flickering from minor floating-point variations in duration
        icon.lastCooldownWasSecret = false
        local lastStart = icon.lastCooldownStart or 0
        local startChanged = math.abs(start - lastStart) > COOLDOWN_START_TOLERANCE
        
        if startChanged then
            icon.cooldown:SetCooldown(start, duration)
            icon.cooldown:Show()
            icon.lastCooldownStart = start
            icon.lastCooldownDuration = duration
        end
    else
        -- No cooldown: hide only if was showing
        icon.lastCooldownWasSecret = false
        if (icon.lastCooldownDuration or 0) > 0 then
            icon.cooldown:Hide()
            icon.lastCooldownStart = 0
            icon.lastCooldownDuration = 0
        end
    end
end

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

-- State variables
local isInCombat = false
local hotkeysDirty = true
local lastFrameState = {
    shouldShow = false,
    spellCount = 0,
    lastUpdate = 0,
}

-- Invalidate hotkey cache (call when action bars or bindings change)
function UIRenderer.InvalidateHotkeyCache()
    hotkeysDirty = true
end

-- Forward declarations
local StopAssistedGlow
local StopDefensiveGlow
local StartAssistedGlow
local StartDefensiveGlow
local TintMarchingAnts
local CreateMarchingAntsFrame
local CreateProcGlowFrame

-- Helper to create a marching ants flipbook frame (reusable for different styles)
CreateMarchingAntsFrame = function(parent, frameKey)
    local highlightFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = highlightFrame
    highlightFrame:SetPoint("CENTER")
    highlightFrame:SetSize(45, 45)
    highlightFrame:SetFrameLevel(parent:GetFrameLevel() + 4)
    
    -- Create the flipbook texture
    local flipbook = highlightFrame:CreateTexture(nil, "OVERLAY")
    highlightFrame.Flipbook = flipbook
    flipbook:SetAtlas("rotationhelper_ants_flipbook")
    flipbook:SetSize(66, 66)
    flipbook:SetPoint("CENTER")
    
    -- Create the animation group for the flipbook
    local animGroup = flipbook:CreateAnimationGroup()
    animGroup:SetLooping("REPEAT")
    animGroup:SetToFinalAlpha(true)  -- Critical: ensures animation plays correctly
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

    -- When frame hides, stop the loop
    highlightFrame:SetScript("OnHide", function()
        if flipbook.Anim:IsPlaying() then
            flipbook.Anim:Stop()
        end
    end)

    -- Don't initialize - let it start naturally when Play() is called
    -- (initialization can interfere with subsequent Play() calls)
    
    return highlightFrame
end

-- Helper to create a proc glow frame (gold spell proc animation)
-- Created at base 45x45 size (Blizzard standard), scaled via SetScale()
CreateProcGlowFrame = function(parent, frameKey)
    local procFrame = CreateFrame("FRAME", nil, parent)
    parent[frameKey] = procFrame
    procFrame:SetPoint("CENTER")
    procFrame:SetSize(45 * 1.4, 45 * 1.4)  -- Blizzard uses 1.4x button size
    procFrame:SetFrameLevel(parent:GetFrameLevel() + 5)
    procFrame:Hide()
    
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

TintMarchingAnts = function(highlightFrame, r, g, b)
    if highlightFrame and highlightFrame.Flipbook then
        highlightFrame.Flipbook:SetVertexColor(r, g, b, 1)
    end
end

StartAssistedGlow = function(icon, style)
    if not icon then return end
    
    style = style or "ASSISTED"
    
    if style == "PROC" then
        -- Use native proc glow animation (gold) - only in combat
        -- Check combat directly instead of relying on state variable
        if not UnitAffectingCombat("player") then
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
        
        -- Animate in combat, freeze out of combat
        if isInCombat then
            -- Always ensure animation is playing (like proc animation)
            highlightFrame.Flipbook.Anim:Play()
        else
            -- Stop animation, but ensure it was played at least once first
            -- (stops on current frame instead of showing entire atlas)
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

-- Start defensive glow - uses green-tinted marching ants, or proc glow if spell is proc'd
-- Out of combat: freeze animation on frame 1 (like main queue icons)
StartDefensiveGlow = function(icon, isProc)
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
        else
            -- Play then immediately stop to show first frame (Blizzard's trick)
            highlightFrame.Flipbook.Anim:Play()
            highlightFrame.Flipbook.Anim:Stop()
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
        if icon.ProcGlowFrame.ProcLoop then
            icon.ProcGlowFrame.ProcLoop:Stop()
        end
    end
    
    icon.hasDefensiveGlow = false
    icon.defensiveGlowStyle = nil
end

-- Show the defensive icon with a specific spell or item
-- isItem: true if id is an itemID (potion), false/nil if it's a spellID
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon)
    if not addon or not id or not defensiveIcon then return end
    
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
        -- Reset cooldown cache so new spell/item's cooldown is properly applied
        defensiveIcon.lastCooldownStart = nil
        defensiveIcon.lastCooldownDuration = nil
        defensiveIcon.lastCooldownWasSecret = false
    end
    
    -- Update cooldown using shared helper
    local start, duration
    if isItem then
        start, duration = GetItemCooldown(id)
    elseif BlizzardAPI and BlizzardAPI.GetSpellCooldown then
        start, duration = BlizzardAPI.GetSpellCooldown(id)
    end
    UpdateIconCooldown(defensiveIcon, start, duration)
    
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
    
    -- Normalize hotkey for key press matching (use shared helper)
    local normalized = NormalizeHotkey(hotkey)
    
    -- Only update previous hotkey if normalized changed (for flash grace period)
    if defensiveIcon.normalizedHotkey and defensiveIcon.normalizedHotkey ~= normalized then
        defensiveIcon.previousNormalizedHotkey = defensiveIcon.normalizedHotkey
        defensiveIcon.hotkeyChangeTime = GetTime()
    end
    defensiveIcon.normalizedHotkey = normalized
    
    -- Only update hotkey text if it changed (prevents flicker)
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= hotkey then
        defensiveIcon.hotkeyText:SetText(hotkey)
    end
    
    -- Check if defensive spell has an active proc (only for spells, not items)
    -- Use centralized wrapper that handles secret values
    local isProc = not isItem and BlizzardAPI.IsSpellProcced(id) or false
    
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
function UIRenderer.HideDefensiveIcon(defensiveIcon)
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
        -- Reset cooldown cache for when icon gets reused
        defensiveIcon.lastCooldownStart = nil
        defensiveIcon.lastCooldownDuration = nil
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

function UIRenderer.RenderSpellQueue(addon, spellIDs)
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
    
    -- Hide queue when mounted if option is enabled
    -- Also treats Druid Travel Form (3) and Flight Form (27) as "mounted"
    if shouldShowFrame and profile.hideQueueWhenMounted then
        local isMounted = IsMounted()
        if not isMounted then
            -- Check for Druid mount forms (Travel Form = 3, Flight Form = 27)
            local formID = GetShapeshiftFormID()
            if formID == 3 or formID == 27 then
                isMounted = true
            end
        end
        if isMounted then
            shouldShowFrame = false
        end
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
    
    -- Pre-pass: collect cooldowns for all icons so we can detect if any icon is actively on cooldown
    local iconCooldowns = {}
    for i = 1, maxIcons do
        local spellID = hasSpells and spellIDs[i] or nil
        if spellID then
            -- Fetch raw cooldown and sanitized values
            local rawStart, rawDuration = GetSpellCooldown(spellID)
            local rawStartIsSecret = issecretvalue and issecretvalue(rawStart)
            local rawDurationIsSecret = issecretvalue and issecretvalue(rawDuration)

            -- Action bar fallback for missing/secret/zero cooldowns
            if not rawStart or not rawDuration or rawStartIsSecret or rawDurationIsSecret or rawDuration == 0 then
                local slot = ActionBarScanner and ActionBarScanner.GetSlotForSpell and ActionBarScanner.GetSlotForSpell(spellID)
                if slot then
                    if C_ActionBar and C_ActionBar.GetActionCooldown then
                        local ok, cd = pcall(C_ActionBar.GetActionCooldown, slot)
                        if ok and cd and cd.startTime and cd.duration and not (issecretvalue and (issecretvalue(cd.startTime) or issecretvalue(cd.duration))) then
                            rawStart = cd.startTime
                            rawDuration = cd.duration
                            -- Note: Removed debug output here - was extremely spammy (fires every frame)
                        end
                    elseif GetActionCooldown then
                        local ok, s, d = pcall(GetActionCooldown, slot)
                        if ok and s and d and not (issecretvalue and (issecretvalue(s) or issecretvalue(d))) then
                            rawStart = s
                            rawDuration = d
                            -- Note: Removed debug output here - was extremely spammy
                        end
                    end
                end
            end

            local cmpStart, cmpDuration = BlizzardAPI.GetSpellCooldownValues(spellID)
            iconCooldowns[i] = {
                spellID = spellID,
                rawStart = rawStart,
                rawDuration = rawDuration,
                cmpStart = cmpStart,
                cmpDuration = cmpDuration,
            }
        else
            iconCooldowns[i] = nil
        end
    end

    -- Get GCD state from dummy spell (ID 61304) - always accurate regardless of which spell triggered it
    local gcdStart, gcdDuration = BlizzardAPI.GetGCDInfo()
    local durTol = 0.05   -- tolerance for duration comparison when checking for long cooldowns

    -- When GCD is active, propagate GCD swipe to all icons lacking their own longer cooldowns
    -- The GCD is global - if ANY ability triggers it, ALL GCD-bound abilities share it
    -- Previously required anyIconOnGCD=true, but that detection can fail for instant-cast abilities
    -- whose own cooldown returns 0 even when the GCD is active
    if gcdDuration and gcdDuration > 0 then
        local gcdOffset = math.min(math.max(gcdDuration * 0.1, 0.1), 0.2)
        for i = 1, maxIcons do
            local cd = iconCooldowns[i]
            if cd then
                -- If icon has its own cooldown significantly longer than GCD, skip (off-GCD ability or long CD)
                local hasLongCooldown = false
                if cd.cmpDuration and cd.cmpDuration > (gcdDuration + durTol) then
                    hasLongCooldown = true
                else
                    local rawDuration = cd.rawDuration
                    local rawDurationIsSecret = issecretvalue and issecretvalue(rawDuration)
                    if rawDuration and not rawDurationIsSecret and rawDuration > (gcdDuration + durTol) then
                        hasLongCooldown = true
                    end
                end
                if not hasLongCooldown then
                    -- Propagate GCD start/duration (apply early-end offset so swipe ends slightly before GCD)
                    cd.rawStart = gcdStart
                    cd.rawDuration = math.max(gcdDuration - gcdOffset, 0)
                    -- Debug output removed - was extremely spammy (fires every frame during GCD)
                    -- Use /jac test or /jac modules for diagnostics instead
                end
            end
        end
    end

    -- Update individual icons (always do this part)
    for i = 1, maxIcons do
        local icon = spellIconsRef[i]
        if icon then
            local spellID = hasSpells and spellIDs[i] or nil
            local spellInfo = spellID and GetCachedSpellInfo(spellID)

            if spellID and spellInfo then
                -- Only update if spell changed for this slot
                local spellChanged = (icon.spellID ~= spellID)
                
                -- Reset cooldown cache when spell changes (including first-time assignment)
                if spellChanged then
                    -- Track previous spell ID for grace period logic (avoid flashing spell that just moved)
                    if icon.spellID then
                        icon.previousSpellID = icon.spellID
                    end
                    -- Reset cooldown cache so new spell's cooldown is properly applied
                    icon.lastCooldownStart = nil
                    icon.lastCooldownDuration = nil
                    icon.lastCooldownWasSecret = false  -- Reset secret flag for new spell
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
                
                -- Check for "Waiting for..." spells (Assisted Combat's resource-wait indicator)
                -- These spells tell the player to wait for energy/mana/rage/etc to regenerate
                local isWaitingSpell = spellInfo.name and spellInfo.name:find("^Waiting for")
                local centerText = icon.centerText
                if centerText then
                    if isWaitingSpell then
                        centerText:SetText("WAIT")
                        centerText:Show()
                    else
                        centerText:Hide()
                    end
                end
                
                -- Apply vertex color for queue icons (brightness/opacity)
                if i > 1 then
                    iconTexture:SetVertexColor(QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_OPACITY)
                else
                    iconTexture:SetVertexColor(1, 1, 1, 1)
                end

                -- Update cooldown display using precomputed values
                local cd = iconCooldowns[i]
                local displayStart = cd and cd.rawStart or nil
                local displayDuration = cd and cd.rawDuration or nil
                UpdateIconCooldown(icon, displayStart, displayDuration)

                -- Check if spell has an active proc (overlay)
                -- Use centralized wrapper that handles secret values
                local isProc = BlizzardAPI.IsSpellProcced(spellID)

                if i == 1 and focusEmphasis then
                    local style = isProc and "PROC" or "ASSISTED"
                    StartAssistedGlow(icon, style, isInCombat)
                elseif isProc then
                    StartAssistedGlow(icon, "PROC", isInCombat)
                else
                    StopAssistedGlow(icon)
                end

                -- Hotkey lookup optimization: only query ActionBarScanner when action bars change
                -- Store result in icon.cachedHotkey and reuse until invalidated by ACTIONBAR_SLOT_CHANGED/UPDATE_BINDINGS
                local hotkey
                local hotkeyChanged = false
                if hotkeysDirty or spellChanged or not icon.cachedHotkey then
                    hotkey = GetSpellHotkey and GetSpellHotkey(spellID) or ""
                    hotkeyChanged = (icon.cachedHotkey ~= hotkey)
                    icon.cachedHotkey = hotkey
                    
                    -- Only normalize when hotkey actually changes (expensive gsub calls)
                    if hotkeyChanged or not icon.cachedNormalizedHotkey then
                        local normalized = NormalizeHotkey(hotkey)
                        
                        -- Track previous for flash grace period
                        if icon.normalizedHotkey and icon.normalizedHotkey ~= normalized then
                            icon.previousNormalizedHotkey = icon.normalizedHotkey
                            icon.hotkeyChangeTime = currentTime
                        end
                        icon.normalizedHotkey = normalized
                        icon.cachedNormalizedHotkey = normalized
                    end
                else
                    hotkey = icon.cachedHotkey
                    -- Use cached normalized value (no gsub calls)
                    if not icon.normalizedHotkey and icon.cachedNormalizedHotkey then
                        icon.normalizedHotkey = icon.cachedNormalizedHotkey
                    end
                end
                
                -- Only update hotkey text if it changed (prevents flicker)
                local currentHotkey = icon.hotkeyText:GetText() or ""
                if currentHotkey ~= hotkey then
                    icon.hotkeyText:SetText(hotkey)
                end
                
                -- Out-of-range indicator
                if hotkey ~= "" and C_Spell_IsSpellInRange then
                    local inRange = C_Spell_IsSpellInRange(spellID)
                    if inRange == false then
                        -- Out of range - red hotkey text (Blizzard standard)
                        icon.hotkeyText:SetTextColor(1, 0, 0, 1)
                    else
                        -- In range or no target - white hotkey text
                        icon.hotkeyText:SetTextColor(1, 1, 1, 1)
                    end
                else
                    -- No hotkey or API unavailable - default white
                    icon.hotkeyText:SetTextColor(1, 1, 1, 1)
                end
                
                -- Update icon color/desaturation based on:
                -- 1. Channeling (grey out all icons to emphasize not interrupting)
                -- 2. Queue position (fade setting for positions 2+)
                -- 3. Spell usability (blue tint when not enough resources, Blizzard standard)
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                
                if isChanneling then
                    -- Channeling - grey out entire queue to emphasize not interrupting
                    iconTexture:SetDesaturation(1.0)
                    iconTexture:SetVertexColor(1, 1, 1)  -- Reset color
                elseif isInCombat then
                    local isUsable, notEnoughResources = IsSpellUsable(spellID)
                    if not isUsable and notEnoughResources then
                        -- Not enough resources - darker blue tint (vs Blizzard's lighter 0.5, 0.5, 1.0)
                        iconTexture:SetDesaturation(0)  -- Remove desaturation
                        iconTexture:SetVertexColor(0.3, 0.3, 0.8)  -- Darker blue tint
                    else
                        -- Usable or on cooldown - normal color, apply queue fade setting
                        iconTexture:SetDesaturation(baseDesaturation)
                        iconTexture:SetVertexColor(1, 1, 1)  -- Full white
                    end
                else
                    -- Out of combat - normal color, apply queue fade setting
                    iconTexture:SetDesaturation(baseDesaturation)
                    iconTexture:SetVertexColor(1, 1, 1)  -- Full white
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
                    if icon.centerText then icon.centerText:Hide() end
                    -- Reset all caches for when slot gets reused
                    icon.lastCooldownStart = nil
                    icon.lastCooldownDuration = nil
                    icon.lastCooldownWasSecret = false
                    icon.cachedHotkey = nil
                    icon.cachedNormalizedHotkey = nil
                    icon.normalizedHotkey = nil
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
    if addon.defensiveIcon then
        addon.defensiveIcon:EnableMouse(not isLocked)
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
    if addon.defensiveIcon then
        -- Defensive icon is separate, apply same opacity
        -- Also skip if fading
        local isFading = (addon.defensiveIcon.fadeIn and addon.defensiveIcon.fadeIn:IsPlaying()) or
                         (addon.defensiveIcon.fadeOut and addon.defensiveIcon.fadeOut:IsPlaying())
        if not isFading then
            addon.defensiveIcon:SetAlpha(frameOpacity)
        end
    end
    
    -- Update tracking state
    lastFrameState.shouldShow = shouldShowFrame
    lastFrameState.spellCount = spellCount
    lastFrameState.lastUpdate = currentTime
end

function UIRenderer.OpenHotkeyOverrideDialog(addon, spellID)
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

-- Set combat state (affects glow animation behavior)
function UIRenderer.SetCombatState(inCombat)
    isInCombat = inCombat
end

-- Public exports
UIRenderer.RenderSpellQueue = UIRenderer.RenderSpellQueue
UIRenderer.ShowDefensiveIcon = UIRenderer.ShowDefensiveIcon
UIRenderer.HideDefensiveIcon = UIRenderer.HideDefensiveIcon
UIRenderer.OpenHotkeyOverrideDialog = UIRenderer.OpenHotkeyOverrideDialog
UIRenderer.InvalidateHotkeyCache = UIRenderer.InvalidateHotkeyCache
UIRenderer.SetCombatState = UIRenderer.SetCombatState
