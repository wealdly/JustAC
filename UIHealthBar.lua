-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Health Bar Module
-- Mirrors the player's health bar by reading the StatusBar widget state
-- Uses texture width ratio to avoid 12.0 secret value restrictions

-- UIHealthBar module is abandoned due to Midnight (12.0) secret value limitations.
-- Kept in repository for future reference but intentionally not loaded.
local UIHealthBar = LibStub:NewLibrary("JustAC-UIHealthBar", 2)
if not UIHealthBar then return end

-- Abandon this module immediately to avoid accidental usage
return

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Hot path optimizations
local GetTime = GetTime
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pcall = pcall

-- Constants
local UPDATE_INTERVAL = 0.03  -- ~30 FPS for smooth updates
local BAR_HEIGHT = 6          -- Compact bar height

-- Module state
local healthBarFrame = nil
local lastUpdate = 0
local isInitialized = false
local cachedPlayerHealthBar = nil

-- Color thresholds (match LowHealthFrame behavior)
local COLOR_HEALTHY = { r = 0.0, g = 0.8, b = 0.0 }   -- Green
local COLOR_LOW     = { r = 1.0, g = 0.8, b = 0.0 }   -- Yellow (~35%)
local COLOR_CRITICAL = { r = 0.8, g = 0.0, b = 0.0 }  -- Red (~20%)

-- Get the player frame's health bar widget
local function GetPlayerHealthBar()
    if cachedPlayerHealthBar and cachedPlayerHealthBar:IsVisible() then
        return cachedPlayerHealthBar
    end
    
    -- Try the global helper function first (cleanest)
    if PlayerFrame_GetHealthBar then
        cachedPlayerHealthBar = PlayerFrame_GetHealthBar()
        if cachedPlayerHealthBar then return cachedPlayerHealthBar end
    end
    
    -- Fallback: direct frame access
    if PlayerFrame and PlayerFrame.PlayerFrameContent then
        local content = PlayerFrame.PlayerFrameContent
        if content.PlayerFrameContentMain and content.PlayerFrameContentMain.HealthBarsContainer then
            cachedPlayerHealthBar = content.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            if cachedPlayerHealthBar then return cachedPlayerHealthBar end
        end
    end
    
    -- Last resort: try classic layout
    if PlayerFrame and PlayerFrame.healthbar then
        cachedPlayerHealthBar = PlayerFrame.healthbar
        return cachedPlayerHealthBar
    end
    
    return nil
end

-- Get health percentage by reading the StatusBar widget state
-- This uses visual state which should not be secret
local function GetHealthPercentFromWidget()
    local healthBar = GetPlayerHealthBar()
    if not healthBar then return nil end
    
    -- Method 1: Try StatusBar:GetValue() directly
    -- The StatusBar widget stores the value even if UnitHealth() is secret
    local success, result = pcall(function()
        local value = healthBar:GetValue()
        local minVal, maxVal = healthBar:GetMinMaxValues()
        
        -- Check if these are secret values
        if issecretvalue then
            if issecretvalue(value) or issecretvalue(maxVal) then
                return nil
            end
        end
        
        if value and maxVal and maxVal > 0 then
            return (value / maxVal) * 100
        end
        return nil
    end)
    
    if success and result then
        return result
    end
    
    -- Method 2: Read texture texcoords (preferred) or fallback to right-edge geometry
    local texture = healthBar:GetStatusBarTexture()
    if texture then
        -- Try texcoord method first (UV-based fill)
        local ok, left, right, top, bottom = pcall(function() return texture:GetTexCoord() end)
        if ok and left and right then
            -- Guard against secret values (12.0) which cannot be used in arithmetic
            local leftIsSecret = (issecretvalue and issecretvalue(left)) or false
            local rightIsSecret = (issecretvalue and issecretvalue(right)) or false
            if not leftIsSecret and not rightIsSecret then
                local delta = right - left
                if delta > 0.0001 and delta <= 1.0 then
                    return delta * 100
                end
            end
        end

        -- Fallback: right-edge geometry relative to bar
        local success2, result2 = pcall(function()
            local barLeft = healthBar:GetLeft()
            local barRight = healthBar:GetRight()
            local texRight = texture:GetRight()

            if barLeft and barRight and texRight and barRight > barLeft then
                local barWidth = barRight - barLeft
                local fillWidth = texRight - barLeft
                if fillWidth > 0 and barWidth > 0 then
                    return (fillWidth / barWidth) * 100
                end
            end
            return nil
        end)

        if success2 and result2 then
            return result2
        end
    end
    
    -- Method 3: Fall back to LowHealthFrame estimation
    if BlizzardAPI and BlizzardAPI.GetLowHealthState then
        local isLow, isCritical, alpha = BlizzardAPI.GetLowHealthState()
        if isCritical then
            -- Critical = ~20% or below
            return 15 + (1 - math_min(1, alpha or 0)) * 5
        elseif isLow then
            -- Low = ~35% or below
            return 25 + (1 - math_min(1, alpha or 0)) * 10
        else
            -- Above 35%
            return 100
        end
    end
    
    return 100  -- Default to full if all methods fail
end

-- Get color based on health percentage
local function GetHealthColor(percent)
    if not percent then return COLOR_HEALTHY end
    
    if percent <= 20 then
        return COLOR_CRITICAL
    elseif percent <= 35 then
        return COLOR_LOW
    else
        return COLOR_HEALTHY
    end
end

-- Create the health bar frame
local function CreateHealthBar(parentFrame, profile)
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame = nil
    end
    
    if not parentFrame then return nil end
    
    -- Create container frame
    local frame = CreateFrame("Frame", nil, parentFrame)
    frame:SetHeight(BAR_HEIGHT + 2)  -- +2 for border
    
    -- Background (dark)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    frame.background = bg
    
    -- Border
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.2, 0.2, 0.2, 1)
    frame.border = border
    
    -- Health fill bar (clone player's statusbar texture if available)
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetWidth(0)  -- Will be updated dynamically
    fill:SetColorTexture(0, 0.8, 0, 1)  -- Green by default
    frame.fill = fill

    -- Percent label (only shown when numeric percent available)
    local percentText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    percentText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    percentText:SetJustifyH("CENTER")
    percentText:SetTextColor(1, 1, 1, 0.95)
    percentText:SetText("")
    percentText:Hide()
    frame.percentText = percentText

    -- Try to copy player's status bar texture for visual fidelity
    local playerBar = GetPlayerHealthBar()
    if playerBar then
        local ok, ptex = pcall(function() return playerBar:GetStatusBarTexture() end)
        if ok and ptex then
            -- Try atlas first
            local atlas = (pcall(function() return ptex:GetAtlas() end) and ptex:GetAtlas()) or nil
            if atlas then
                pcall(function() fill:SetAtlas(atlas, true) end)
                fill._isTextured = true
            else
                local texPath = (pcall(function() return ptex:GetTexture() end) and ptex:GetTexture()) or nil
                if texPath then
                    pcall(function() fill:SetTexture(texPath) end)
                    fill._isTextured = true
                end
            end
        end
    end
    
    -- Store reference to parent for width calculation
    frame.parentFrame = parentFrame
    frame.maxFillWidth = 0
    frame.lastPercentNumeric = false
    
    healthBarFrame = frame
    return frame
end

-- Update the health bar display
local function UpdateHealthBar()
    if not healthBarFrame or not healthBarFrame:IsShown() then return end
    
    local now = GetTime()
    if now - lastUpdate < UPDATE_INTERVAL then return end
    lastUpdate = now
    
    -- Try to copy player's texture if we didn't earlier (late load cases)
    if healthBarFrame.fill and not healthBarFrame.fill._isTextured then
        local playerBar = GetPlayerHealthBar()
        if playerBar then
            local ok, ptex = pcall(function() return playerBar:GetStatusBarTexture() end)
            if ok and ptex then
                local atlas = (pcall(function() return ptex:GetAtlas() end) and ptex:GetAtlas()) or nil
                if atlas then
                    pcall(function() healthBarFrame.fill:SetAtlas(atlas, true) end)
                    healthBarFrame.fill._isTextured = true
                else
                    local texPath = (pcall(function() return ptex:GetTexture() end) and ptex:GetTexture()) or nil
                    if texPath then
                        pcall(function() healthBarFrame.fill:SetTexture(texPath) end)
                        healthBarFrame.fill._isTextured = true
                    end
                end
            end
        end
    end

    -- Attempt to mirror the source texture's texcoords directly (no arithmetic)
    local mirrored = false
    do
        local ok, ptex = pcall(function()
            local playerBar = GetPlayerHealthBar()
            if not playerBar then return nil end
            return playerBar:GetStatusBarTexture()
        end)
        if ok and ptex then
            local got, l, r, t, b = pcall(function() return ptex:GetTexCoord() end)
            if got and l and r then
                local leftIsSecret = (issecretvalue and issecretvalue(l)) or false
                local rightIsSecret = (issecretvalue and issecretvalue(r)) or false
                if not leftIsSecret and not rightIsSecret then
                    -- Copy the texture/atlas if not already done
                    if not healthBarFrame.fill._isTextured then
                        local atlas = (pcall(function() return ptex:GetAtlas() end) and ptex:GetAtlas()) or nil
                        if atlas then
                            pcall(function() healthBarFrame.fill:SetAtlas(atlas, true) end)
                            healthBarFrame.fill._isTextured = true
                        else
                            local texPath = (pcall(function() return ptex:GetTexture() end) and ptex:GetTexture()) or nil
                            if texPath then
                                pcall(function() healthBarFrame.fill:SetTexture(texPath) end)
                                healthBarFrame.fill._isTextured = true
                            end
                        end
                    end

                    -- Set our fill to full width and copy texcoords directly (video mirror)
                    local maxWidth = healthBarFrame.maxFillWidth
                    if maxWidth and maxWidth > 2 then
                        healthBarFrame.fill:SetWidth(maxWidth)
                        pcall(function() healthBarFrame.fill:SetTexCoord(l, r, t, b) end)
                        mirrored = true
                    end
                else
                    -- If texcoords are secret or not usable, anchor to the source texture directly as a visual mirror
                    local anchorOk = pcall(function()
                        healthBarFrame.fill:ClearAllPoints()
                        healthBarFrame.fill:SetAllPoints(ptex)
                    end)
                    if anchorOk then
                        healthBarFrame.fill._anchoredToSource = true
                        mirrored = true                    else
                        -- Try anchoring to the StatusBar frame itself if texture anchoring failed
                        local playerBar = GetPlayerHealthBar()
                        if playerBar then
                            local anchorOk2 = pcall(function()
                                healthBarFrame.fill:ClearAllPoints()
                                healthBarFrame.fill:SetAllPoints(playerBar)
                            end)
                            if anchorOk2 then
                                healthBarFrame.fill._anchoredToSource = true
                                mirrored = true
                            end
                        end                    end
                end
            else
                -- No texcoord info; try anchoring if possible
                local anchorOk2 = pcall(function()
                    healthBarFrame.fill:ClearAllPoints()
                    healthBarFrame.fill:SetAllPoints(ptex)
                end)
                if anchorOk2 then
                    healthBarFrame.fill._anchoredToSource = true
                    mirrored = true
                end
            end
        end
    end

    if mirrored then
        -- If anchored to source, we may not own positioning; tint by low/critical state if possible
        local pct = GetHealthPercentFromWidget()
        local color = GetHealthColor(pct)
        if healthBarFrame.fill._isTextured then
            pcall(function() healthBarFrame.fill:SetVertexColor(color.r, color.g, color.b, 1) end)
        else
            -- If anchored to source but not textured, ensure fill covers source area and color it
            if healthBarFrame.fill._anchoredToSource then
                -- Keep whatever the source shows; add subtle overlay by setting a small alpha
                pcall(function() healthBarFrame.fill:SetColorTexture(color.r, color.g, color.b, 0.2) end)
            else
                healthBarFrame.fill:SetColorTexture(color.r, color.g, color.b, 1)
            end
        end
        -- Hide percent text since we don't have a reliable numeric percent
        if healthBarFrame.percentText then healthBarFrame.percentText:Hide() end
        healthBarFrame.lastPercentNumeric = false
        return
    end

    -- Fallback: compute percent-based width (may not be exact if values are secret)
    local percent = GetHealthPercentFromWidget()
    local percentNumeric = (type(percent) == "number")
    if not percent then
        percent = 100  -- Default to full if unknown
    end
    percent = math_max(0, math_min(100, percent))
    
    -- Update fill width
    local maxWidth = healthBarFrame.maxFillWidth
    if maxWidth > 2 then
        local fillWidth = (percent / 100) * maxWidth
        healthBarFrame.fill:SetWidth(math_max(1, fillWidth))
    end
    
    -- Update color based on health
    local color = GetHealthColor(percent)
    if healthBarFrame.fill._isTextured then
        -- Tint the textured fill
        pcall(function() healthBarFrame.fill:SetVertexColor(color.r, color.g, color.b, 1) end)
    else
        healthBarFrame.fill:SetColorTexture(color.r, color.g, color.b, 1)
    end

    -- Update percent label: only show when we have a numeric percent (non-secret)
    if healthBarFrame.percentText then
        if percentNumeric then
            local pctText = string.format("%d%%", math_floor(percent + 0.5))
            healthBarFrame.percentText:SetText(pctText)
            healthBarFrame.percentText:Show()
            healthBarFrame.lastPercentNumeric = true
        else
            healthBarFrame.percentText:Hide()
            healthBarFrame.lastPercentNumeric = false
        end
    end
end

-- Position and size the health bar based on queue layout
function UIHealthBar.LayoutHealthBar(addon, profile)
    if not healthBarFrame then return end
    if not addon or not addon.mainFrame then return end
    
    local mainFrame = addon.mainFrame
    local firstIconScale = profile.firstIconScale or 1.2
    local iconSize = profile.iconSize or 36
    local actualIconSize = iconSize * firstIconScale
    local iconSpacing = profile.iconSpacing or 1
    local maxIcons = profile.maxIcons or 4
    local queueOrientation = profile.queueOrientation or "LEFT"
    
    -- Calculate queue width/height based on orientation
    local queueWidth, queueHeight
    if queueOrientation == "LEFT" or queueOrientation == "RIGHT" then
        -- Horizontal queue: width = first icon + queue icons
        local queueIconScale = iconSize  -- Queue icons are unscaled
        queueWidth = actualIconSize + (maxIcons - 1) * (queueIconScale + iconSpacing)
        queueHeight = actualIconSize
    else
        -- Vertical queue
        local queueIconScale = iconSize
        queueWidth = actualIconSize
        queueHeight = actualIconSize + (maxIcons - 1) * (queueIconScale + iconSpacing)
    end
    
    -- Position health bar below the queue
    healthBarFrame:ClearAllPoints()
    healthBarFrame:SetWidth(queueWidth)
    healthBarFrame:SetPoint("TOP", mainFrame, "BOTTOM", 0, -2)
    
    -- Store max fill width (accounting for border insets)
    healthBarFrame.maxFillWidth = queueWidth - 2
    
    healthBarFrame:Show()
end

-- Initialize the health bar system
function UIHealthBar.Initialize(addon, profile)
    if not addon or not addon.mainFrame then return end
    if not profile.defensives or not profile.defensives.showHealthBar then return end
    
    local frame = CreateHealthBar(addon.mainFrame, profile)
    if frame then
        UIHealthBar.LayoutHealthBar(addon, profile)
        isInitialized = true
    end
end

-- Cleanup
function UIHealthBar.Cleanup()
    if healthBarFrame then
        healthBarFrame:Hide()
        healthBarFrame = nil
    end
    isInitialized = false
end

-- Called every frame update
function UIHealthBar.OnUpdate()
    if isInitialized then
        UpdateHealthBar()
    end
end

-- Check if health bar is enabled in settings
function UIHealthBar.IsEnabled(profile)
    return profile and profile.defensives and profile.defensives.showHealthBar
end

-- Toggle visibility
function UIHealthBar.SetShown(shown)
    if healthBarFrame then
        healthBarFrame:SetShown(shown)
    end
end

-- Get the health bar frame (for debugging)
function UIHealthBar.GetFrame()
    return healthBarFrame
end
-- Debug function - get current health reading method and value
function UIHealthBar.GetDebugInfo()
    local info = {
        initialized = isInitialized,
        frameExists = healthBarFrame ~= nil,
        frameVisible = healthBarFrame and healthBarFrame:IsShown() or false,
        playerBarFound = GetPlayerHealthBar() ~= nil,
        healthPercent = nil,
        method = "none"
    }
    
    local healthBar = GetPlayerHealthBar()
    if healthBar then
        -- Test Method 1: GetValue
        local success, result = pcall(function()
            local value = healthBar:GetValue()
            local minVal, maxVal = healthBar:GetMinMaxValues()
            
            info.rawValue = value
            info.rawMax = maxVal
            info.valueIsSecret = issecretvalue and issecretvalue(value) or false
            info.maxIsSecret = issecretvalue and issecretvalue(maxVal) or false
            
            if not info.valueIsSecret and not info.maxIsSecret and value and maxVal and maxVal > 0 then
                return (value / maxVal) * 100
            end
            return nil
        end)
        
        if success and result then
            info.healthPercent = result
            info.method = "statusbar_value"
            return info
        end
        
        -- Test Method 2: Texture bounds
        local texture = healthBar:GetStatusBarTexture()
        if texture then
            -- Check texcoords first (guarded)
            local ok, l, r, t, b = pcall(function() return texture:GetTexCoord() end)
            if ok and l and r then
                local leftIsSecret = (issecretvalue and issecretvalue(l)) or false
                local rightIsSecret = (issecretvalue and issecretvalue(r)) or false
                info.texCoordLeft = leftIsSecret and "SECRET" or l
                info.texCoordRight = rightIsSecret and "SECRET" or r
                if not leftIsSecret and not rightIsSecret then
                    local delta = r - l
                    if delta and delta > 0.0001 then
                        info.healthPercent = delta * 100
                        info.method = "texcoord"
                        return info
                    end
                else
                    info.method = "texcoord_secret"
                    -- don't compute percentage when texcoords are secret
                    return info
                end
            end

            -- Fallback to geometry bounds
            local success2, result2 = pcall(function()
                local barLeft = healthBar:GetLeft()
                local barRight = healthBar:GetRight()
                local texRight = texture:GetRight()

                info.barLeft = barLeft
                info.barRight = barRight
                info.texRight = texRight

                if barLeft and barRight and texRight and barRight > barLeft then
                    local barWidth = barRight - barLeft
                    local fillWidth = texRight - barLeft
                    if fillWidth > 0 and barWidth > 0 then
                        return (fillWidth / barWidth) * 100
                    end
                end
                return nil
            end)

            if success2 and result2 then
                info.healthPercent = result2
                info.method = "texture_bounds"
                return info
            end
        end
        
        info.method = "lowhealth_fallback"
    end
    
    -- Final value from main function
    info.healthPercent = GetHealthPercentFromWidget()
    
    -- Fill texture info
    if healthBarFrame and healthBarFrame.fill then
        info.fillIsTextured = healthBarFrame.fill._isTextured or false
        info.fillAnchoredToSource = healthBarFrame.fill._anchoredToSource or false
    end

    -- Percent debug
    info.lastPercentNumeric = healthBarFrame and healthBarFrame.lastPercentNumeric or false
    if healthBarFrame and healthBarFrame.lastPercentNumeric and healthBarFrame.percentText then
        info.lastPercentText = healthBarFrame.percentText:GetText()
    else
        info.lastPercentText = nil
    end

    return info
end