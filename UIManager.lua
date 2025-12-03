-- JustAC: UI Manager Module
local UIManager = LibStub:NewLibrary("JustAC-UIManager", 19)
if not UIManager then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local C_SpellActivationOverlay = C_SpellActivationOverlay
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor

local function GetProfile()
    return BlizzardAPI and BlizzardAPI.GetProfile() or nil
end

-- Visual constants (defaults, profile overrides where applicable)
local DEFAULT_GLOW_COLOR = {0.3, 0.7, 1.0, 1}
local DEFAULT_GLOW_ALPHA = 0.75
local GLOW_OFFSET_MULTIPLIER = 0.07
local DEFAULT_QUEUE_DESATURATION = 0.35
local QUEUE_ICON_BRIGHTNESS = 1.0
local QUEUE_ICON_OPACITY = 1.0
local CLICK_DARKEN_ALPHA = 0.4
local CLICK_INSET_PIXELS = 2
local HOTKEY_FONT_SCALE = 0.4
local HOTKEY_MIN_FONT_SIZE = 8
local HOTKEY_OFFSET_FIRST = -3
local HOTKEY_OFFSET_QUEUE = -2

local function GetGlowAlpha()
    local profile = GetProfile()
    return profile and profile.glowAlpha or DEFAULT_GLOW_ALPHA
end

local function GetGlowColor()
    local profile = GetProfile()
    if profile then
        return {profile.glowColorR or 0.3, profile.glowColorG or 0.7, profile.glowColorB or 1.0, 1}
    end
    return DEFAULT_GLOW_COLOR
end

local function GetQueueDesaturation()
    local profile = GetProfile()
    return profile and profile.queueIconDesaturation or DEFAULT_QUEUE_DESATURATION
end

-- Get defensive glow color (green by default)
local function GetDefensiveGlowColor()
    local profile = GetProfile()
    if profile and profile.defensives then
        return {
            profile.defensives.glowColorR or 0.0,
            profile.defensives.glowColorG or 1.0,
            profile.defensives.glowColorB or 0.0,
            1
        }
    end
    return {0.0, 1.0, 0.0, 1}  -- Green default
end

local spellIcons = {}
local defensiveIcon = nil  -- Single defensive icon, positioned left of position 1
local lastFrameState = {
    shouldShow = false,
    spellCount = 0,
    lastUpdate = 0,
}

local function GetGlowColorForStyle(style)
    if style == "PROC" then
        return nil  -- Use default gold for procs
    end
    return GetGlowColor()
end

local function UpdateGlowColor(glowFrame, style)
    if not glowFrame then return end
    
    local color = GetGlowColorForStyle(style)
    if color then
        -- Apply tint via desaturation + vertex color
        if glowFrame.ProcStart then
            glowFrame.ProcStart:SetDesaturated(1)
            glowFrame.ProcStart:SetVertexColor(color[1], color[2], color[3], color[4])
        end
        if glowFrame.ProcLoop then
            glowFrame.ProcLoop:SetDesaturated(1)
            glowFrame.ProcLoop:SetVertexColor(color[1], color[2], color[3], color[4])
        end
    else
        -- Default gold (no desaturation, full color)
        if glowFrame.ProcStart then
            glowFrame.ProcStart:SetDesaturated(nil)
            glowFrame.ProcStart:SetVertexColor(1, 1, 1, 1)
        end
        if glowFrame.ProcLoop then
            glowFrame.ProcLoop:SetDesaturated(nil)
            glowFrame.ProcLoop:SetVertexColor(1, 1, 1, 1)
        end
    end
end

local isInCombat = false

local function ShouldPauseAnimation()
    return not isInCombat
end

local function StartAssistedGlow(icon, style)
    if not icon then return end
    
    style = style or "ASSISTED"
    local LibCustomGlow = LibStub("LibCustomGlow-1.0", true)
    if not LibCustomGlow then return end
    
    -- Use single key "MAIN" to avoid stop/start flicker on style changes
    local glowKey = "MAIN"
    local glowFrame = icon["_ProcGlow" .. glowKey]
    
    if glowFrame and icon.activeGlowStyle then
        glowFrame:SetAlpha(GetGlowAlpha())
        
        if icon.activeGlowStyle ~= style then
            UpdateGlowColor(glowFrame, style)
            icon.activeGlowStyle = style
        else
            UpdateGlowColor(glowFrame, style)
        end
        
        -- Sync animation state with combat status
        if glowFrame.ProcLoopAnim then
            if ShouldPauseAnimation() then
                if glowFrame.ProcLoopAnim:IsPlaying() then
                    glowFrame.ProcLoopAnim:Pause()
                end
            else
                if not glowFrame.ProcLoopAnim:IsPlaying() then
                    glowFrame.ProcLoopAnim:Play()
                end
            end
        end
        return
    end
    
    local width, height = icon:GetSize()
    local extraOffset = width * GLOW_OFFSET_MULTIPLIER
    
    LibCustomGlow.ProcGlow_Start(icon, {
        key = glowKey,
        color = GetGlowColorForStyle(style),
        startAnim = false,
        xOffset = extraOffset,
        yOffset = extraOffset,
    })
    
    glowFrame = icon["_ProcGlow" .. glowKey]
    if glowFrame then
        glowFrame:SetAlpha(GetGlowAlpha())
        if ShouldPauseAnimation() and glowFrame.ProcLoopAnim then
            glowFrame.ProcLoopAnim:Pause()
        end
    end
    
    icon.activeGlowStyle = style
end

local function StopAssistedGlow(icon)
    if not icon then return end
    
    local LibCustomGlow = LibStub("LibCustomGlow-1.0", true)
    if LibCustomGlow then
        LibCustomGlow.ProcGlow_Stop(icon, "MAIN")
    end
    
    icon.activeGlowStyle = nil
end

local function SetGlowAnimationPaused(icon, paused)
    if not icon then return end
    
    -- Handle both MAIN (spell icons) and DEFENSIVE (defensive icon) glow keys
    local glowKeys = {"MAIN", "DEFENSIVE"}
    for _, key in ipairs(glowKeys) do
        local glowFrame = icon["_ProcGlow" .. key]
        if glowFrame and glowFrame.ProcLoopAnim then
            if paused then
                glowFrame.ProcLoopAnim:Pause()
            else
                if not glowFrame.ProcLoopAnim:IsPlaying() then
                    glowFrame.ProcLoopAnim:Play()
                end
            end
        end
    end
end

function UIManager.FreezeAllGlows(addon)
    isInCombat = false
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            SetGlowAnimationPaused(icon, true)
        end
    end
    
    -- Also freeze defensive icon if present
    if defensiveIcon then
        SetGlowAnimationPaused(defensiveIcon, true)
    end
end

function UIManager.UnfreezeAllGlows(addon)
    isInCombat = true
    if not addon or not addon.spellIcons then return end
    
    for i = 1, #addon.spellIcons do
        local icon = addon.spellIcons[i]
        if icon then
            SetGlowAnimationPaused(icon, false)
        end
    end
    
    -- Also unfreeze defensive icon if present
    if defensiveIcon then
        SetGlowAnimationPaused(defensiveIcon, false)
    end
end

--------------------------------------------------------------------------------
-- Defensive Icon Management
-- Shows a single defensive spell recommendation when health is low
--------------------------------------------------------------------------------

local function StartDefensiveGlow(icon)
    if not icon then return end
    
    local LibCustomGlow = LibStub("LibCustomGlow-1.0", true)
    if not LibCustomGlow then return end
    
    local glowKey = "DEFENSIVE"
    local glowFrame = icon["_ProcGlow" .. glowKey]
    
    if glowFrame and icon.hasDefensiveGlow then
        glowFrame:SetAlpha(GetGlowAlpha())
        
        -- Update color in case settings changed
        local color = GetDefensiveGlowColor()
        if glowFrame.ProcStart then
            glowFrame.ProcStart:SetDesaturated(1)
            glowFrame.ProcStart:SetVertexColor(color[1], color[2], color[3], color[4])
        end
        if glowFrame.ProcLoop then
            glowFrame.ProcLoop:SetDesaturated(1)
            glowFrame.ProcLoop:SetVertexColor(color[1], color[2], color[3], color[4])
        end
        
        -- Sync animation with combat state
        if glowFrame.ProcLoopAnim then
            if not isInCombat then
                if glowFrame.ProcLoopAnim:IsPlaying() then
                    glowFrame.ProcLoopAnim:Pause()
                end
            else
                if not glowFrame.ProcLoopAnim:IsPlaying() then
                    glowFrame.ProcLoopAnim:Play()
                end
            end
        end
        return
    end
    
    local width, height = icon:GetSize()
    local extraOffset = width * GLOW_OFFSET_MULTIPLIER
    
    LibCustomGlow.ProcGlow_Start(icon, {
        key = glowKey,
        color = GetDefensiveGlowColor(),
        startAnim = false,
        xOffset = extraOffset,
        yOffset = extraOffset,
    })
    
    glowFrame = icon["_ProcGlow" .. glowKey]
    if glowFrame then
        glowFrame:SetAlpha(GetGlowAlpha())
        if not isInCombat and glowFrame.ProcLoopAnim then
            glowFrame.ProcLoopAnim:Pause()
        end
    end
    
    icon.hasDefensiveGlow = true
end

local function StopDefensiveGlow(icon)
    if not icon then return end
    
    local LibCustomGlow = LibStub("LibCustomGlow-1.0", true)
    if LibCustomGlow then
        LibCustomGlow.ProcGlow_Stop(icon, "DEFENSIVE")
    end
    
    icon.hasDefensiveGlow = false
end

-- Create the defensive icon (called from CreateSpellIcons)
local function CreateDefensiveIcon(addon, profile)
    if defensiveIcon then
        StopDefensiveGlow(defensiveIcon)
        defensiveIcon:Hide()
        defensiveIcon:SetParent(nil)
        defensiveIcon = nil
    end
    
    if not profile.defensives or not profile.defensives.enabled then return end
    
    local button = CreateFrame("Button", nil, addon.mainFrame)
    if not button then return end
    
    -- Same size as first icon (scaled)
    local firstIconScale = profile.firstIconScale or 1.4
    local actualIconSize = profile.iconSize * firstIconScale
    
    button:SetSize(actualIconSize, actualIconSize)
    -- Position left of the main frame with spacing
    button:SetPoint("RIGHT", addon.mainFrame, "LEFT", -profile.iconSpacing - 4, 0)

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
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if self.spellID and profile.showTooltips then
            local inCombat = UnitAffectingCombat("player")
            local showTooltip = not inCombat or profile.tooltipsInCombat
            
            if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00ff00DEFENSIVE SUGGESTION|r")
                GameTooltip:AddLine("|cffff6666Health is low!|r")
                
                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(self.spellID) or ""
                if hotkey and hotkey ~= "" then
                    GameTooltip:AddLine("|cffffff00Press " .. hotkey .. " to cast|r")
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
    button:Hide()
    
    defensiveIcon = button
    addon.defensiveIcon = defensiveIcon
end

-- Show the defensive icon with a specific spell
function UIManager.ShowDefensiveIcon(addon, spellID)
    if not addon or not spellID then return end
    
    -- Create icon if it doesn't exist
    if not defensiveIcon then
        local profile = GetProfile()
        if profile then
            CreateDefensiveIcon(addon, profile)
        end
    end
    
    if not defensiveIcon then return end
    
    local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(spellID)
    if not spellInfo then return end
    
    local spellChanged = (defensiveIcon.spellID ~= spellID)
    defensiveIcon.spellID = spellID
    
    if spellChanged then
        defensiveIcon.iconTexture:SetTexture(spellInfo.iconID)
        defensiveIcon.iconTexture:Show()
        defensiveIcon.iconTexture:SetDesaturation(0)
        defensiveIcon.iconTexture:SetVertexColor(1, 1, 1, 1)
    end
    
    -- Update cooldown
    local start, duration
    if BlizzardAPI and BlizzardAPI.GetSpellCooldown then
        start, duration = BlizzardAPI.GetSpellCooldown(spellID)
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
    
    -- Update hotkey
    local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(spellID) or ""
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= hotkey then
        defensiveIcon.hotkeyText:SetText(hotkey)
    end
    
    -- Start green glow
    StartDefensiveGlow(defensiveIcon)
    
    if not defensiveIcon:IsShown() then
        defensiveIcon:Show()
    end
end

-- Hide the defensive icon
function UIManager.HideDefensiveIcon(addon)
    if not defensiveIcon then return end
    
    if defensiveIcon:IsShown() or defensiveIcon.spellID then
        StopDefensiveGlow(defensiveIcon)
        defensiveIcon.spellID = nil
        defensiveIcon.iconTexture:Hide()
        defensiveIcon.cooldown:Hide()
        defensiveIcon.hotkeyText:SetText("")
        defensiveIcon:Hide()
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
    
    UIManager.CreateGrabTab(addon)
end

function UIManager.CreateGrabTab(addon)
    addon.grabTab = CreateFrame("Frame", nil, addon.mainFrame, "BackdropTemplate")
    if not addon.grabTab then return end
    
    addon.grabTab:SetSize(12, 20)
    addon.grabTab:SetPoint("LEFT", addon.mainFrame, "RIGHT", 2, 0)
    
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
    
    local dot1 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot1:SetSize(2, 2)
    dot1:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 4)
    dot1:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    local dot2 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot2:SetSize(2, 2)
    dot2:SetPoint("CENTER", addon.grabTab, "CENTER", 0, 0)
    dot2:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    local dot3 = addon.grabTab:CreateTexture(nil, "OVERLAY")
    dot3:SetSize(2, 2)
    dot3:SetPoint("CENTER", addon.grabTab, "CENTER", 0, -4)
    dot3:SetColorTexture(0.8, 0.8, 0.8, 1)
    
    addon.grabTab:EnableMouse(true)
    addon.grabTab:SetMovable(true)
    addon.grabTab:RegisterForDrag("LeftButton")
    
    addon.grabTab:SetScript("OnDragStart", function()
        if addon:GetProfile() then
            addon.mainFrame:StartMoving()
        end
    end)
    addon.grabTab:SetScript("OnDragStop", function()
        addon.mainFrame:StopMovingOrSizing()
        UIManager.SavePosition(addon)
    end)
    
    addon.grabTab:SetScript("OnEnter", function()
        GameTooltip:SetOwner(addon.grabTab, "ANCHOR_RIGHT")
        GameTooltip:SetText("JustAssistedCombat")
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    addon.grabTab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function UIManager.CreateSpellIcons(addon)
    if not addon.db or not addon.db.profile or not addon.mainFrame then return end
    
    for i = 1, #spellIcons do
        if spellIcons[i] then
            if spellIcons[i].cooldown then
                spellIcons[i].cooldown:Hide()
            end
            spellIcons[i]:Hide()
            spellIcons[i]:SetParent(nil)
        end
    end
    wipe(spellIcons)
    
    local profile = addon.db.profile
    local currentX = 0
    local firstIconScale = profile.firstIconScale or 1.4
    
    for i = 1, profile.maxIcons do
        local button = UIManager.CreateSingleSpellIcon(addon, i, currentX, profile)
        if button then
            spellIcons[i] = button
            -- Add extra spacing after first icon if it's scaled larger (for glow overflow)
            local extraGlowSpacing = 0
            if i == 1 and firstIconScale > 1.0 then
                -- Extra spacing proportional to how much larger the first icon is
                extraGlowSpacing = profile.iconSize * (firstIconScale - 1.0) * 0.3
            end
            currentX = currentX + button:GetWidth() + profile.iconSpacing + extraGlowSpacing
        end
    end
    
    addon.spellIcons = spellIcons
    
    -- Create defensive icon (positioned left of main frame)
    CreateDefensiveIcon(addon, profile)
end

-- SIMPLIFIED: Pure display-only icons with configuration only
function UIManager.CreateSingleSpellIcon(addon, index, xPos, profile)
    local button = CreateFrame("Button", nil, addon.mainFrame)
    if not button then return nil end
    
    local isFirstIcon = (index == 1)
    local firstIconScale = profile.firstIconScale or 1.4
    local actualIconSize = isFirstIcon and (profile.iconSize * firstIconScale) or profile.iconSize
    
    button:SetSize(actualIconSize, actualIconSize)
    button:SetPoint("LEFT", xPos, 0)

    local iconTexture = button:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(button)
    button.iconTexture = iconTexture

    -- Pushed texture overlay for click feedback (darkens icon when pressed)
    local pushedTexture = button:CreateTexture(nil, "OVERLAY")
    pushedTexture:SetAllPoints(button)
    pushedTexture:SetColorTexture(0, 0, 0, CLICK_DARKEN_ALPHA)
    pushedTexture:Hide()
    button.pushedTexture = pushedTexture

    -- Proc glow is managed by LibCustomGlow, no static textures needed
    button.hasProcGlow = false

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
                    local isBlacklisted = SpellQueue and SpellQueue.IsSpellBlacklisted and
                        (SpellQueue.IsSpellBlacklisted(self.spellID, "combatAssist") or SpellQueue.IsSpellBlacklisted(self.spellID, "fixedQueue"))
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
    
    -- Only update frame state if it actually changed
    local frameStateChanged = (lastFrameState.shouldShow ~= shouldShowFrame)
    local spellCountChanged = (lastFrameState.spellCount ~= spellCount)
    
    -- Cache commonly accessed values
    local maxIcons = profile.maxIcons
    local focusEmphasis = profile.focusEmphasis
    local greyoutNoHotkey = profile.greyoutNoHotkey
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
                    
                    -- Set saturation/color only on spell change
                    if i > 1 then
                        iconTexture:SetDesaturation(queueDesaturation)
                        iconTexture:SetVertexColor(QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_BRIGHTNESS, QUEUE_ICON_OPACITY)
                    else
                        iconTexture:SetDesaturation(0)
                        iconTexture:SetVertexColor(1, 1, 1, 1)
                    end
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
                local isProc = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed and C_SpellActivationOverlay.IsSpellOverlayed(spellID)

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
                
                -- Update desaturation based on hotkey presence
                if hotkey ~= "" then
                    if i == 1 then
                        icon.iconTexture:SetDesaturated(false)
                    end
                else
                    if greyoutNoHotkey then
                        icon.iconTexture:SetDesaturated(true)
                    end
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
    local firstIconScale = profile.firstIconScale or 1.4

    UIManager.CreateSpellIcons(addon)

    local firstIconSize = newIconSize * firstIconScale
    local remainingIconsWidth = (newMaxIcons > 1) and ((newMaxIcons - 1) * newIconSize) or 0
    local totalSpacing = (newMaxIcons > 1) and ((newMaxIcons - 1) * newIconSpacing) or 0
    -- Add extra glow spacing after first icon if scaled larger
    local extraGlowSpacing = (firstIconScale > 1.0) and (newIconSize * (firstIconScale - 1.0) * 0.3) or 0
    local totalWidth = firstIconSize + remainingIconsWidth + totalSpacing + extraGlowSpacing
    
    local frameHeight = firstIconSize
    
    addon.mainFrame:SetSize(totalWidth, frameHeight)
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