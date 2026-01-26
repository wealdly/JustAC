-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Renderer Module v6
-- Changed: Fixed cooldown overlay updates - always pass secret cooldowns through (was only updating once)
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 7)
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
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor
local string_upper = string.upper
local string_gsub = string.gsub

-- Helper: Check if spell is procced using both BlizzardAPI and ActionBarScanner
local function IsSpellProcced(spellID)
    if BlizzardAPI.IsSpellProcced(spellID) then return true end
    if ActionBarScanner and ActionBarScanner.IsSpellProcced then
        return ActionBarScanner.IsSpellProcced(spellID)
    end
    return false
end

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
-- Updates icon.cooldown widget - passes through when values change
-- Cooldown widget automatically hides when cooldown expires - we don't need to manage that
local function UpdateIconCooldown(icon, start, duration)
    -- Normalize nil to 0 (nil means "no data", treat as no cooldown)
    start = start or 0
    duration = duration or 0
    
    -- Check if values are secret (can't be compared in Lua)
    local startIsSecret = issecretvalue and issecretvalue(start)
    local durationIsSecret = issecretvalue and issecretvalue(duration)
    
    if startIsSecret or durationIsSecret then
        -- Secret values: pass through once, then skip until non-secret or cleared
        if not icon._cooldownIsSecret then
            icon.cooldown:SetCooldown(start, duration)
            icon._cooldownIsSecret = true
            icon._lastCooldownStart = nil
            icon._lastCooldownDuration = nil
        end
    elseif start > 0 and duration > 0 then
        -- Non-secret values with active cooldown: only update if changed or was secret
        if icon._cooldownIsSecret or start ~= icon._lastCooldownStart or duration ~= icon._lastCooldownDuration then
            icon.cooldown:SetCooldown(start, duration)
            icon._lastCooldownStart = start
            icon._lastCooldownDuration = duration
            icon._cooldownIsSecret = false
        end
    end
    -- Note: We don't explicitly hide cooldowns when getting 0,0 data
    -- The cooldown widget auto-hides when the cooldown expires
    -- This prevents prematurely clearing cooldowns due to API timing issues
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
local HOTKEY_FONT_SCALE = 0.4
local HOTKEY_MIN_FONT_SIZE = 8
local HOTKEY_OFFSET_FIRST = -3
local HOTKEY_OFFSET_QUEUE = -2

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
-- Show the defensive icon with a specific spell or item
-- isItem: true if id is an itemID (potion), false/nil if it's a spellID
-- showGlow: true to show green marching ants glow (only slot 1 should have this)
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon, showGlow)
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
    
    -- Update charge count display (for charge-based spells like Frenzied Regeneration)
    if defensiveIcon.chargeText then
        local showCharges = false
        if not isItem and C_Spell_GetSpellCharges then
            local success, chargeInfo = pcall(C_Spell_GetSpellCharges, id)
            if success and chargeInfo then
                local maxCharges = chargeInfo.maxCharges
                local currentCharges = chargeInfo.currentCharges
                -- Check both values are real (not secret) before comparing
                local maxIsReal = maxCharges and not (issecretvalue and issecretvalue(maxCharges))
                local currentIsReal = currentCharges and not (issecretvalue and issecretvalue(currentCharges))
                if maxIsReal and currentIsReal and maxCharges > 1 then
                    defensiveIcon.chargeText:SetText(tostring(currentCharges))
                    defensiveIcon.chargeText:Show()
                    showCharges = true
                end
            end
        end
        if not showCharges then
            defensiveIcon.chargeText:Hide()
        end
    end
    
    -- Find hotkey for item by scanning action bars
    local hotkey = ""
    if isItem then
        for slot = 1, 180 do
            local actionType, actionID = GetActionInfo(slot)
            if actionType == "item" and actionID == id then
                hotkey = GetBindingKey("ACTIONBUTTON" .. slot) or ""
                if hotkey == "" then
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
    
    local isInCombat = UnitAffectingCombat("player")
    
    -- Start green crawl glow on slot 1
    if showGlow then
        UIAnimations.StartDefensiveGlow(defensiveIcon, isInCombat)
    else
        UIAnimations.StopDefensiveGlow(defensiveIcon)
    end
    
    -- Check if defensive spell has an active proc (only for spells, not items)
    local isProc = not isItem and IsSpellProcced(id)
    
    -- Show custom proc glow if spell is procced
    if isProc then
        UIAnimations.ShowProcGlow(defensiveIcon)
    else
        UIAnimations.HideProcGlow(defensiveIcon)
    end
    
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
        UIAnimations.StopDefensiveGlow(defensiveIcon)
        UIAnimations.HideProcGlow(defensiveIcon)
        defensiveIcon.spellID = nil
        defensiveIcon.itemID = nil
        defensiveIcon.itemCastSpellID = nil
        defensiveIcon.currentID = nil
        defensiveIcon.isItem = nil
        defensiveIcon.iconTexture:Hide()
        defensiveIcon.cooldown:Hide()
        -- Reset cooldown cache for when icon gets reused
        defensiveIcon._lastCooldownStart = nil
        defensiveIcon._lastCooldownDuration = nil
        defensiveIcon._cooldownIsSecret = nil
        defensiveIcon.hotkeyText:SetText("")
        -- Hide charge count
        if defensiveIcon.chargeText then
            defensiveIcon.chargeText:Hide()
        end
        
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

-- Show multiple defensive icons from a queue of spells
-- queue: array of {spellID, isItem, isProcced} entries
function UIRenderer.ShowDefensiveIcons(addon, queue)
    if not addon or not addon.defensiveIcons then return end
    
    local icons = addon.defensiveIcons
    
    -- Render each queue entry to corresponding icon slot
    for i, icon in ipairs(icons) do
        local entry = queue[i]
        if entry and entry.spellID then
            -- Only show glow on slot 1
            local showGlow = (i == 1)
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, showGlow)
        else
            -- No spell for this slot, hide it
            UIRenderer.HideDefensiveIcon(icon)
        end
    end
end

-- Hide all defensive icons
function UIRenderer.HideDefensiveIcons(addon)
    if not addon or not addon.defensiveIcons then return end
    
    for _, icon in ipairs(addon.defensiveIcons) do
        UIRenderer.HideDefensiveIcon(icon)
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

    -- When GCD is active, apply GCD to icons that don't have their own longer cooldown
    -- This uses the same cooldown frame as spell cooldowns - simpler and more reliable
    -- Icons with long cooldowns keep their spell cooldown, icons without get GCD applied
    if gcdDuration and gcdDuration > 0 then
        local gcdOffset = math.min(math.max(gcdDuration * 0.1, 0.1), 0.2)
        for i = 1, maxIcons do
            local cd = iconCooldowns[i]
            local icon = spellIconsRef[i]
            if cd and icon then
                -- Check if icon has its own cooldown longer than GCD
                -- Check BOTH current API data AND currently displayed cooldown (prevents flicker on cast)
                local hasLongCooldown = false
                local rawDuration = cd.rawDuration
                local rawDurationIsSecret = issecretvalue and issecretvalue(rawDuration)
                
                -- Check current API data
                if rawDuration and not rawDurationIsSecret and rawDuration > (gcdDuration + durTol) then
                    hasLongCooldown = true
                elseif cd.cmpDuration and cd.cmpDuration > (gcdDuration + durTol) then
                    hasLongCooldown = true
                end
                
                -- Also check currently displayed cooldown (prevents overwriting during brief API gaps)
                if not hasLongCooldown and icon._lastCooldownDuration then
                    local displayedDuration = icon._lastCooldownDuration
                    if not (issecretvalue and issecretvalue(displayedDuration)) and displayedDuration > (gcdDuration + durTol) then
                        hasLongCooldown = true
                    end
                end
                
                if not hasLongCooldown then
                    -- No long cooldown: apply GCD to this icon's cooldown data
                    cd.rawStart = gcdStart
                    cd.rawDuration = math.max(gcdDuration - gcdOffset, 0)
                end
                -- Icons with long cooldowns keep their original cd.rawStart/rawDuration
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
                local displayStart = cd and cd.rawStart or 0
                local displayDuration = cd and cd.rawDuration or 0
                UpdateIconCooldown(icon, displayStart, displayDuration)
                
                -- Update charge count display (for charge-based spells)
                if icon.chargeText then
                    local showCharges = false
                    if C_Spell_GetSpellCharges then
                        local success, chargeInfo = pcall(C_Spell_GetSpellCharges, spellID)
                        if success and chargeInfo then
                            local maxCharges = chargeInfo.maxCharges
                            local currentCharges = chargeInfo.currentCharges
                            -- Check both values are real (not secret) before comparing
                            local maxIsReal = maxCharges and not (issecretvalue and issecretvalue(maxCharges))
                            local currentIsReal = currentCharges and not (issecretvalue and issecretvalue(currentCharges))
                            if maxIsReal and currentIsReal and maxCharges > 1 then
                                icon.chargeText:SetText(tostring(currentCharges))
                                icon.chargeText:Show()
                                showCharges = true
                            end
                        end
                    end
                    if not showCharges then
                        icon.chargeText:Hide()
                    end
                end

                -- Check if spell has an active proc (overlay)
                local isProc = IsSpellProcced(spellID)

                -- Show blue/white assisted crawl on position 1 if focus emphasis enabled
                local shouldShowAssisted = (i == 1 and focusEmphasis)
                if shouldShowAssisted and not icon.hasAssistedGlow then
                    UIAnimations.StartAssistedGlow(icon, isInCombat)
                    icon.hasAssistedGlow = true
                elseif not shouldShowAssisted and icon.hasAssistedGlow then
                    UIAnimations.StopAssistedGlow(icon)
                    icon.hasAssistedGlow = false
                end
                
                -- Show custom proc glow if spell is procced (any position)
                if isProc and not icon.hasProcGlow then
                    UIAnimations.ShowProcGlow(icon)
                    icon.hasProcGlow = true
                elseif not isProc and icon.hasProcGlow then
                    UIAnimations.HideProcGlow(icon)
                    icon.hasProcGlow = false
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
                
                -- Out-of-range indicator: red text if out of range, white otherwise
                local inRange = hotkey ~= "" and C_Spell_IsSpellInRange and C_Spell_IsSpellInRange(spellID)
                icon.hotkeyText:SetTextColor(inRange == false and 1 or 1, inRange == false and 0 or 1, inRange == false and 0 or 1, 1)
                
                -- Icon appearance: grey when channeling, blue tint when not enough resources, fade based on position
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                
                if isChanneling then
                    iconTexture:SetDesaturation(1.0)
                    iconTexture:SetVertexColor(1, 1, 1)
                elseif isInCombat then
                    local isUsable, notEnoughResources = IsSpellUsable(spellID)
                    if not isUsable and notEnoughResources then
                        -- Not enough resources - darker blue tint
                        iconTexture:SetDesaturation(0)
                        iconTexture:SetVertexColor(0.3, 0.3, 0.8)
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
                    if icon.chargeText then icon.chargeText:Hide() end
                    -- Reset all caches for when slot gets reused
                    icon._lastCooldownStart = nil
                    icon._lastCooldownDuration = nil
                    icon._cooldownIsSecret = nil
                    icon.cachedHotkey = nil
                    icon.cachedNormalizedHotkey = nil
                    icon.normalizedHotkey = nil
                    icon.hasAssistedGlow = false
                    icon.hasProcGlow = false
                    UIAnimations.StopAssistedGlow(icon)
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
    
    -- Update defensive icon cooldowns (continuous update, like DPS icons)
    -- This runs every frame to ensure GCD swipe and cooldown updates are current
    local defensiveIconsList = addon.defensiveIcons or (addon.defensiveIcon and {addon.defensiveIcon})
    if defensiveIconsList then
        for _, defensiveIcon in ipairs(defensiveIconsList) do
            if defensiveIcon and defensiveIcon:IsShown() then
                local defSpellID = defensiveIcon.spellID
                local isItem = defensiveIcon.isItem
                
                if defSpellID and not isItem then
                    -- Spell (not item): check for GCD vs own cooldown
                    local defStart, defDuration = BlizzardAPI.GetSpellCooldown(defSpellID)
                    local defCmpStart, defCmpDuration = BlizzardAPI.GetSpellCooldownValues(defSpellID)
                    
                    -- Determine if this is GCD or own cooldown
                    local gcdStart, gcdDuration = BlizzardAPI.GetGCDInfo()
                    local durTol = 0.05
                    
                    if gcdDuration and gcdDuration > 0 then
                        -- GCD is active
                        local defHasLongCooldown = defCmpDuration and defCmpDuration > (gcdDuration + durTol)
                        
                        if defHasLongCooldown then
                            -- Own cooldown longer than GCD - show own cooldown
                            UpdateIconCooldown(defensiveIcon, defStart, defDuration)
                        else
                            -- On GCD - show GCD swipe (with early-end offset)
                            local gcdOffset = math.min(math.max(gcdDuration * 0.1, 0.1), 0.2)
                            UpdateIconCooldown(defensiveIcon, gcdStart, math.max(gcdDuration - gcdOffset, 0))
                        end
                    else
                        -- No GCD active - show own cooldown if any
                        UpdateIconCooldown(defensiveIcon, defStart, defDuration)
                    end
                elseif isItem and defensiveIcon.itemID then
                    -- Item: use GetItemCooldown
                    local start, duration = GetItemCooldown(defensiveIcon.itemID)
                    UpdateIconCooldown(defensiveIcon, start, duration)
                end
            end
        end
    end
    
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
            -- Icons always need mouse enabled for tooltips
            -- When locked, RegisterForClicks("") prevents clicks while keeping tooltips
            icon:EnableMouse(true)
            if isLocked then
                icon:RegisterForClicks()  -- No clicks = locked but tooltips work
            else
                icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")  -- Both clicks enabled
            end
        end
    end
    if addon.defensiveIcon then
        -- Defensive icon also needs mouse enabled for tooltips
        addon.defensiveIcon:EnableMouse(true)
        if isLocked then
            addon.defensiveIcon:RegisterForClicks()  -- No clicks = locked but tooltips work
        else
            addon.defensiveIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")  -- Both clicks enabled
        end
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
UIRenderer.ShowDefensiveIcons = UIRenderer.ShowDefensiveIcons
UIRenderer.HideDefensiveIcons = UIRenderer.HideDefensiveIcons
UIRenderer.OpenHotkeyOverrideDialog = UIRenderer.OpenHotkeyOverrideDialog
UIRenderer.InvalidateHotkeyCache = UIRenderer.InvalidateHotkeyCache
UIRenderer.SetCombatState = UIRenderer.SetCombatState
