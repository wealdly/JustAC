-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Manager Module
local UIManager = LibStub:NewLibrary("JustAC-UIManager", 22)
if not UIManager then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)

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
local HOTKEY_FONT_SCALE = 0.4
local HOTKEY_MIN_FONT_SIZE = 8
local HOTKEY_OFFSET_FIRST = -3
local HOTKEY_OFFSET_QUEUE = -2

local function GetQueueDesaturation()
    local profile = GetProfile()
    return profile and profile.queueIconDesaturation or DEFAULT_QUEUE_DESATURATION
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
    
    -- Create the start animation texture (burst)
    local procStart = procFrame:CreateTexture(nil, "OVERLAY")
    procFrame.ProcStartFlipbook = procStart
    procStart:SetAtlas("UI-HUD-ActionBar-Proc-Start-Flipbook")
    procStart:SetSize(150, 150)
    procStart:SetPoint("CENTER")
    procStart:SetAlpha(0)
    
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
    
    -- Create the start animation group
    local startGroup = procStart:CreateAnimationGroup()
    startGroup:SetToFinalAlpha(true)
    procFrame.ProcStartAnim = startGroup
    
    local startAlpha1 = startGroup:CreateAnimation("Alpha")
    startAlpha1:SetDuration(0.001)
    startAlpha1:SetOrder(0)
    startAlpha1:SetFromAlpha(1)
    startAlpha1:SetToAlpha(1)
    
    local startFlip = startGroup:CreateAnimation("FlipBook")
    startFlip:SetChildKey("ProcStartFlipbook")
    startFlip:SetDuration(0.7)
    startFlip:SetOrder(1)
    startFlip:SetFlipBookRows(6)
    startFlip:SetFlipBookColumns(5)
    startFlip:SetFlipBookFrames(30)
    startFlip:SetFlipBookFrameWidth(0)
    startFlip:SetFlipBookFrameHeight(0)
    
    local startAlpha2 = startGroup:CreateAnimation("Alpha")
    startAlpha2:SetChildKey("ProcStartFlipbook")
    startAlpha2:SetDuration(0.001)
    startAlpha2:SetOrder(2)
    startAlpha2:SetFromAlpha(1)
    startAlpha2:SetToAlpha(0)
    
    -- When start animation finishes, play the loop
    startGroup:SetScript("OnFinished", function()
        procFrame.ProcLoop:Play()
    end)
    
    -- When frame hides, stop the loop
    procFrame:SetScript("OnHide", function()
        if procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcLoop:Stop()
        end
    end)
    
    -- Initialize flipbooks to first frame (Play/Stop trick to avoid showing whole atlas)
    startGroup:Play()
    startGroup:Stop()
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
        
        -- Hide marching ants if showing
        if icon.AssistedCombatHighlightFrame then
            icon.AssistedCombatHighlightFrame:Hide()
            icon.AssistedCombatHighlightFrame.Flipbook.Anim:Stop()
        end
        
        -- Show and play proc animation
        procFrame:Show()
        procFrame.ProcStartFlipbook:SetAlpha(1)
        procFrame.ProcLoopFlipbook:SetAlpha(1)
        if not procFrame.ProcStartAnim:IsPlaying() and not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcStartAnim:Play()
        end
        
        icon.activeGlowStyle = style
    else
        -- Use marching ants flipbook (ASSISTED = blue)
        -- Show even out of combat, but freeze animation
        local highlightFrame = icon.AssistedCombatHighlightFrame
        if not highlightFrame then
            highlightFrame = CreateMarchingAntsFrame(icon, "AssistedCombatHighlightFrame")
        end
        
        -- Scale frame to match icon size (base size is 45)
        local width = icon:GetWidth()
        highlightFrame:SetScale(width / 45)
        
        -- Apply color based on style (ASSISTED = default blue/white, no tint needed)
        TintMarchingAnts(highlightFrame, 1, 1, 1)  -- Reset to white (atlas is already blue)
        
        -- Hide proc glow if showing
        if icon.ProcGlowFrame then
            icon.ProcGlowFrame:Hide()
            icon.ProcGlowFrame.ProcStartAnim:Stop()
            icon.ProcGlowFrame.ProcLoop:Stop()
        end
        
        highlightFrame:Show()
        
        -- Animate in combat, freeze (pause) out of combat
        -- Use Play/Stop trick to freeze on a single frame (Blizzard's approach)
        if isInCombat then
            if not highlightFrame.Flipbook.Anim:IsPlaying() then
                highlightFrame.Flipbook.Anim:Play()
            end
        else
            -- Play then Stop freezes on current frame instead of showing whole atlas
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
                end
                icon.AssistedCombatHighlightFrame.Flipbook.Anim:Stop()
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
            icon.DefensiveHighlightFrame.Flipbook.Anim:Stop()
        end
        
        -- Show and play proc animation
        procFrame:Show()
        procFrame.ProcStartFlipbook:SetAlpha(1)
        procFrame.ProcLoopFlipbook:SetAlpha(1)
        if not procFrame.ProcStartAnim:IsPlaying() and not procFrame.ProcLoop:IsPlaying() then
            procFrame.ProcStartAnim:Play()
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
            icon.ProcGlowFrame.ProcStartAnim:Stop()
            icon.ProcGlowFrame.ProcLoop:Stop()
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

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    iconTexture:Hide()  -- Start hidden, only show when spell is assigned
    button.iconTexture = iconTexture

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetDrawEdge(true)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:Hide()  -- Start hidden
    button.cooldown = cooldown
    
    local hotkeyText = button:CreateFontString(nil, "OVERLAY", nil, 3)
    local fontSize = math.max(HOTKEY_MIN_FONT_SIZE, math.floor(actualIconSize * HOTKEY_FONT_SCALE))
    hotkeyText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    hotkeyText:SetTextColor(1, 1, 1, 1)
    hotkeyText:SetJustifyH("RIGHT")
    hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", HOTKEY_OFFSET_FIRST, HOTKEY_OFFSET_FIRST)
    button.hotkeyText = hotkeyText
    
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
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= hotkey then
        defensiveIcon.hotkeyText:SetText(hotkey)
    end
    
    -- Check if defensive spell has an active proc (only for spells, not items)
    local isProc = not isItem and C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(id) or false
    
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
        if addon:GetProfile() then
            addon.mainFrame:StartMoving()
        end
    end)
    addon.mainFrame:SetScript("OnDragStop", function()
        addon.mainFrame:StopMovingOrSizing()
        UIManager.SavePosition(addon)
    end)
    
    -- Start hidden, only show when we have spells
    addon.mainFrame:Hide()
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
    if orientation == "RIGHT" then
        addon.grabTab:SetPoint("RIGHT", addon.mainFrame, "LEFT", -2, 0)
    elseif orientation == "UP" then
        addon.grabTab:SetPoint("BOTTOM", addon.mainFrame, "TOP", 0, 2)
    elseif orientation == "DOWN" then
        addon.grabTab:SetPoint("TOP", addon.mainFrame, "BOTTOM", 0, -2)
    else -- LEFT (default)
        addon.grabTab:SetPoint("LEFT", addon.mainFrame, "RIGHT", 2, 0)
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
    
    addon.grabTab:SetScript("OnDragStart", function()
        local profile = addon:GetProfile()
        if not profile then return end
        
        -- Block dragging if locked
        if profile.panelLocked then
            return
        end
        
        addon.mainFrame:StartMoving()
    end)
    
    addon.grabTab:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if IsShiftKeyDown() then
                -- Shift+Right-click: toggle lock
                local profile = addon:GetProfile()
                if profile then
                    profile.panelLocked = not profile.panelLocked
                    local status = profile.panelLocked and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                    if addon.DebugPrint then addon:DebugPrint("Panel " .. status) end
                end
            else
                -- Right-click: open options panel
                Settings.OpenToCategory("JustAssistedCombat")
            end
        end
    end)
    addon.grabTab:SetScript("OnDragStop", function()
        addon.mainFrame:StopMovingOrSizing()
        UIManager.SavePosition(addon)
    end)
    
    addon.grabTab:SetScript("OnEnter", function()
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
    
    addon.grabTab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
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
    if orientation == "RIGHT" then
        button:SetPoint("RIGHT", -offset, 0)
    elseif orientation == "UP" then
        button:SetPoint("BOTTOM", 0, offset)
    elseif orientation == "DOWN" then
        button:SetPoint("TOP", 0, -offset)
    else -- LEFT (default)
        button:SetPoint("LEFT", offset, 0)
    end

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    button.iconTexture = iconTexture

    -- Pushed texture overlay for click feedback (darkens icon when pressed)
    local pushedTexture = button:CreateTexture(nil, "OVERLAY")
    pushedTexture:SetAllPoints(button)
    pushedTexture:SetColorTexture(0, 0, 0, CLICK_DARKEN_ALPHA)
    pushedTexture:Hide()
    button.pushedTexture = pushedTexture

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetDrawEdge(true)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    button.cooldown = cooldown
    
    local hotkeyText = button:CreateFontString(nil, "OVERLAY", nil, 3)
    local fontSize = math.max(HOTKEY_MIN_FONT_SIZE, math.floor(actualIconSize * HOTKEY_FONT_SCALE))
    hotkeyText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    hotkeyText:SetTextColor(1, 1, 1, 1)
    hotkeyText:SetJustifyH("RIGHT")
    
    if isFirstIcon then
        hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", HOTKEY_OFFSET_FIRST, HOTKEY_OFFSET_FIRST)
    else
        hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", HOTKEY_OFFSET_QUEUE, HOTKEY_OFFSET_QUEUE)
    end
    
    button.hotkeyText = hotkeyText
    
    -- Click feedback: show pushed state on mouse down
    button:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" and self.spellID then
            self.pushedTexture:Show()
            -- Slight scale down for tactile feedback
            self.iconTexture:SetPoint("TOPLEFT", self, "TOPLEFT", CLICK_INSET_PIXELS, -CLICK_INSET_PIXELS)
            self.iconTexture:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -CLICK_INSET_PIXELS, CLICK_INSET_PIXELS)
        end
    end)
    
    button:SetScript("OnMouseUp", function(self, mouseButton)
        self.pushedTexture:Hide()
        -- Restore normal size
        self.iconTexture:ClearAllPoints()
        self.iconTexture:SetAllPoints(self)
    end)
    
    -- SIMPLIFIED: Only right-click for configuration, no other interactions
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self.spellID then
            -- Block interactions if panel is locked
            local profile = addon:GetProfile()
            if profile and profile.panelLocked then
                return
            end
            
            if IsShiftKeyDown() then
                addon:ToggleSpellBlacklist(self.spellID)
            else
                addon:OpenHotkeyOverrideDialog(self.spellID)
            end
        end
    end)
    
    button:SetScript("OnEnter", function(self)
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
            Pushed = button.pushedTexture,
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
    
    -- Only update frame state if it actually changed
    local frameStateChanged = (lastFrameState.shouldShow ~= shouldShowFrame)
    local spellCountChanged = (lastFrameState.spellCount ~= spellCount)
    
    -- Cache commonly accessed values
    local maxIcons = profile.maxIcons
    local focusEmphasis = profile.focusEmphasis
    local queueDesaturation = GetQueueDesaturation()
    
    -- Update individual icons (always do this part)
    for i = 1, maxIcons do
        local icon = spellIconsRef[i]
        if icon then
            local spellID = hasSpells and spellIDs[i] or nil
            local spellInfo = spellID and SpellQueue.GetCachedSpellInfo(spellID)

            if spellID and spellInfo then
                -- Only update if spell changed for this slot
                local spellChanged = (icon.spellID ~= spellID)
                icon.spellID = spellID
                
                -- Only set texture if spell changed (prevents flicker)
                if spellChanged then
                    local iconTexture = icon.iconTexture
                    iconTexture:SetTexture(spellInfo.iconID)
                    iconTexture:Show()
                end
                
                -- Apply vertex color for queue icons (brightness/opacity)
                if i > 1 then
                    icon.iconTexture:SetVertexColor(QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_OPACITY)
                else
                    icon.iconTexture:SetVertexColor(1, 1, 1, 1)
                end

                -- Update cooldown display (including GCD for timing feedback)
                local start, duration = BlizzardAPI.GetSpellCooldown(spellID)
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

                -- Check if spell has an active proc (overlay)
                local isProc = C_SpellActivationOverlay_IsSpellOverlayed and C_SpellActivationOverlay_IsSpellOverlayed(spellID)

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

                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(spellID) or ""
                
                -- Only update hotkey text if it changed (prevents flicker)
                local currentHotkey = icon.hotkeyText:GetText() or ""
                if currentHotkey ~= hotkey then
                    icon.hotkeyText:SetText(hotkey)
                end
                
                -- Update desaturation based on:
                -- 1. Queue position (fade setting for positions 2+)
                -- 2. Spell usability (grey out when not enough resources in combat)
                local iconTexture = icon.iconTexture
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                
                if isInCombat then
                    local isUsable, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID)
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
                -- No spell for this slot - hide only if currently shown
                if icon:IsShown() or icon.spellID then
                    icon.spellID = nil
                    icon.iconTexture:Hide()
                    icon.cooldown:Hide()
                    StopAssistedGlow(icon)
                    icon.hotkeyText:SetText("")
                    icon:Hide()
                end
            end
        end
    end
    
    -- Update frame visibility only when state actually changes
    if addon.mainFrame and (frameStateChanged or spellCountChanged) then
        if shouldShowFrame then
            if not addon.mainFrame:IsShown() then
                addon.mainFrame:Show()
            end
        else
            if addon.mainFrame:IsShown() then
                addon.mainFrame:Hide()
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
    local frameOpacity = profile.frameOpacity or 1.0
    if addon.mainFrame then
        addon.mainFrame:SetAlpha(frameOpacity)
    end
    if defensiveIcon then
        -- Defensive icon is separate, apply same opacity
        defensiveIcon:SetAlpha(frameOpacity)
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
    
    -- Swap width/height for vertical orientations
    if orientation == "UP" or orientation == "DOWN" then
        addon.mainFrame:SetSize(firstIconSize, totalLength)
    else
        addon.mainFrame:SetSize(totalLength, firstIconSize)
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