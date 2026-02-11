-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Renderer Module - Updates button icons, cooldowns, and animations each frame
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 13)
if not UIRenderer then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)

if not BlizzardAPI or not ActionBarScanner or not SpellQueue or not UIAnimations or not UIFrameFactory then
    return
end

-- Cache frequently used functions to reduce table lookups on every update
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local C_Spell_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local pairs = pairs
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor

-- Check for proc overlay to highlight available abilities
-- BlizzardAPI.IsSpellProcced already checks both base and override IDs
local function IsSpellProcced(spellID)
    return BlizzardAPI.IsSpellProcced(spellID)
end

-- Update button cooldowns - Cooldown widgets handle secret values internally
-- Cooldown frames can handle secret values internally, so we avoid all comparisons/arithmetic
local function UpdateButtonCooldowns(button)
    if not button then return end

    -- Check if this is an item or spell button
    local isItem = button.isItem
    local id = isItem and button.itemID or button.spellID

    if not id then
        -- Clear cooldowns if no spell/item
        if button.cooldown then button.cooldown:Clear() end
        if button.chargeCooldown then button.chargeCooldown:Clear() end
        if button.chargeText then button.chargeText:Hide() end
        return
    end

    local cooldownInfo, chargeInfo

    if isItem then
        -- Items: use GetItemCooldown (returns start, duration directly, not a table)
        local start, duration = GetItemCooldown(id)
        cooldownInfo = { startTime = start or 0, duration = duration or 0, isEnabled = 1, modRate = 1 }
        chargeInfo = nil  -- Items don't have charges
    else
        -- Spells: use C_Spell APIs (same as Blizzard's ActionButton line 871-872)
        -- PERFORMANCE: Use cached cooldownID from BlizzardAPI (avoids redundant override lookup)
        local cooldownID = BlizzardAPI.GetDisplaySpellID(id)
        cooldownInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(cooldownID)
        chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(cooldownID)
    end

    -- ALWAYS pass values to cooldown widgets without checking them
    -- The Cooldown widget accepts secret values and handles them internally
    -- NO comparisons, NO arithmetic - just pass through

    if button.cooldown and cooldownInfo then
        -- Main cooldown (spell cooldown OR GCD, decided by Blizzard's API)
        local startTime = cooldownInfo.startTime or 0
        local duration = cooldownInfo.duration or 0
        local modRate = cooldownInfo.modRate or 1

        -- Always pass values to the cooldown widget - it handles secrets internally
        -- The widget will show/hide the swipe based on the values it receives
        if not button._cooldownShown then
            button.cooldown:SetDrawSwipe(true)
            button.cooldown:Show()
            button._cooldownShown = true
        end
        -- Always update - widget handles everything including secret values
        button.cooldown:SetCooldown(startTime, duration, modRate)
    elseif button.cooldown then
        -- No cooldown info - clear the display only if needed
        if button._cooldownShown then
            button.cooldown:Clear()
            button._cooldownShown = false
        end
    end

    -- Charge cooldown (recharging next charge)
    -- maxCharges is spell structure (rarely secret), currentCharges is combat state (can be secret)
    -- For multi-charge spells (maxCharges > 1), always pass values through to the widget
    if button.chargeCooldown then
        local maxCharges = chargeInfo and chargeInfo.maxCharges
        local currentCharges = chargeInfo and chargeInfo.currentCharges
        
        if maxCharges and currentCharges then
            -- Cache maxCharges when known (spell structure, rarely changes)
            if not BlizzardAPI.IsSecretValue(maxCharges) then
                button._cachedMaxCharges = maxCharges
            end
            
            -- Use cached or current maxCharges to determine if multi-charge spell
            local effectiveMaxCharges = button._cachedMaxCharges or (not BlizzardAPI.IsSecretValue(maxCharges) and maxCharges) or 0
            local isMultiCharge = effectiveMaxCharges > 1
            
            if isMultiCharge then
                -- Multi-charge spell: always show and pass values through
                -- Widget handles the display, including secret values
                if not button._chargeCooldownShown then
                    button.chargeCooldown:SetDrawSwipe(true)
                    button.chargeCooldown:Show()
                    button._chargeCooldownShown = true
                end
                -- Always update - widget handles secrets internally
                button.chargeCooldown:SetCooldown(
                    chargeInfo.cooldownStartTime or 0,
                    chargeInfo.cooldownDuration or 0,
                    chargeInfo.chargeModRate or 1
                )
            else
                -- Not a multi-charge spell - hide
                if button._chargeCooldownShown then
                    button.chargeCooldown:Clear()
                    button.chargeCooldown:Hide()
                    button._chargeCooldownShown = false
                end
            end
        else
            -- No charge info - clear and hide only if needed
            if button._chargeCooldownShown then
                button.chargeCooldown:Clear()
                button.chargeCooldown:Hide()
                button._chargeCooldownShown = false
            end
        end
    end

    -- Show charge count only for multi-charge spells
    -- IMPORTANT: currentCharges can be a secret value in combat
    -- We check maxCharges to decide whether to show charges at all
    -- SetText() can display secret values directly - they render as the actual number
    if button.chargeText and chargeInfo then
        local maxCharges = chargeInfo.maxCharges
        local currentCharges = chargeInfo.currentCharges

        -- maxCharges defines spell structure (static), currentCharges is combat state (can be secret)
        if maxCharges and currentCharges then
            -- Safe comparison: maxCharges is usually not secret (spell structure)
            local showCharges = false
            if not BlizzardAPI.IsSecretValue(maxCharges) then
                showCharges = maxCharges > 1
            elseif button._cachedMaxCharges then
                -- Fall back to cached value if current is somehow secret
                showCharges = button._cachedMaxCharges > 1
            end

            -- Cache maxCharges when it's a real value
            if not BlizzardAPI.IsSecretValue(maxCharges) then
                button._cachedMaxCharges = maxCharges
            end

            if showCharges then
                -- Pass currentCharges directly - FontString displays secret values correctly
                button.chargeText:SetText(currentCharges)
                button.chargeText:Show()
            else
                button.chargeText:Hide()
            end
        else
            button.chargeText:Hide()
        end
    elseif button.chargeText then
        button.chargeText:Hide()
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
local lastPanelLocked = nil
local lastFrameState = {
    shouldShow = false,
    spellCount = 0,
    lastUpdate = 0,
}

-- PERFORMANCE: Throttle cooldown updates (cooldown swipe animates smoothly once set)
local lastCooldownUpdate = 0
local COOLDOWN_UPDATE_INTERVAL = 0.15  -- Update cooldowns max 6-7 times/sec (enough for responsiveness)

-- Invalidate hotkey cache (call when action bars or bindings change)
-- Also clears per-icon cached hotkeys to prevent displaying stale atlas markup
function UIRenderer.InvalidateHotkeyCache()
    hotkeysDirty = true
    -- Clear cached hotkeys on all icons immediately to prevent visual glitches
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if addon and addon.spellIcons then
        for i = 1, #addon.spellIcons do
            local icon = addon.spellIcons[i]
            if icon then
                icon.cachedHotkey = nil
            end
        end
    end
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
    
    -- Update cooldowns using Blizzard's logic (handles GCD, spell CD, and charges)
    UpdateButtonCooldowns(defensiveIcon)

    -- Ensure cooldown frame is visible (may have been hidden by HideDefensiveIcon)
    if defensiveIcon.cooldown then
        defensiveIcon.cooldown:Show()
    end

    -- Hotkey display (skip lookup entirely when disabled for performance)
    local showHotkeys = addon.db and addon.db.profile and addon.db.profile.defensives and addon.db.profile.defensives.showHotkeys ~= false
    local hotkey = ""
    if showHotkeys then
        -- Find hotkey for item by scanning action bars
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
    end
    
    -- Only update hotkey text if it changed (prevents flicker)
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= hotkey then
        defensiveIcon.hotkeyText:SetText(hotkey)
    end

    -- Normalize hotkey for key press flash matching
    if hotkey ~= "" then
        local normalized = hotkey:upper()
        -- Expand modifier prefixes only when followed by a key (dash + key or key directly)
        -- Anchored patterns with lookahead via capture to avoid false positives on bare S/A/C keys
        normalized = normalized:gsub("^CA%-?(.+)", "CTRL-ALT-%1")
        normalized = normalized:gsub("^CS%-?(.+)", "CTRL-SHIFT-%1")
        normalized = normalized:gsub("^SA%-?(.+)", "SHIFT-ALT-%1")
        normalized = normalized:gsub("^S%-?(.+)", "SHIFT-%1")
        normalized = normalized:gsub("^C%-?(.+)", "CTRL-%1")
        normalized = normalized:gsub("^A%-?(.+)", "ALT-%1")
        normalized = normalized:gsub("^%+(.+)", "MOD-%1")

        if defensiveIcon.normalizedHotkey and defensiveIcon.normalizedHotkey ~= normalized then
            defensiveIcon.previousNormalizedHotkey = defensiveIcon.normalizedHotkey
            defensiveIcon.hotkeyChangeTime = GetTime()
        end
        defensiveIcon.normalizedHotkey = normalized
    else
        defensiveIcon.normalizedHotkey = nil
    end

    local isInCombat = UnitAffectingCombat("player")
    
    -- Defensive glow mode (independent from offensive glowMode)
    local defGlowMode = addon.db and addon.db.profile and addon.db.profile.defensives and addon.db.profile.defensives.glowMode or "all"

    -- Start green crawl glow on slot 1 if glow mode includes primary
    local showMarching = showGlow and (defGlowMode == "all" or defGlowMode == "primaryOnly")
    if showMarching then
        UIAnimations.StartDefensiveGlow(defensiveIcon, isInCombat)
    else
        UIAnimations.StopDefensiveGlow(defensiveIcon)
    end

    -- Check if defensive spell has an active proc (only for spells, not items)
    local isProc = not isItem and IsSpellProcced(id)

    -- Show custom proc glow if spell is procced and glow mode includes proc
    local wantProcGlow = isProc and (defGlowMode == "all" or defGlowMode == "procOnly")
    if wantProcGlow then
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
        -- Hide and clear cooldown frames to ensure clean state on reuse
        if defensiveIcon.cooldown then
            defensiveIcon.cooldown:Hide()
            defensiveIcon.cooldown:Clear()
        end
        if defensiveIcon.chargeCooldown then
            defensiveIcon.chargeCooldown:Hide()
            defensiveIcon.chargeCooldown:Clear()
        end
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

    -- Hide queue if no hostile target when option is enabled (only applies out of combat)
    if shouldShowFrame and profile.requireHostileTarget and not isInCombat then
        local hasHostileTarget = UnitExists("target") and UnitCanAttack("player", "target")
        if not hasHostileTarget then
            shouldShowFrame = false
        end
    end

    -- Only update frame state if it actually changed
    local frameStateChanged = (lastFrameState.shouldShow ~= shouldShowFrame)
    local spellCountChanged = (lastFrameState.spellCount ~= spellCount)
    
    -- Cache commonly accessed values
    local maxIcons = profile.maxIcons
    local glowMode = profile.glowMode or (profile.focusEmphasis == false and "procOnly") or "all"
    local showPrimaryGlow = (glowMode == "all" or glowMode == "primaryOnly")
    local showProcGlow = (glowMode == "all" or glowMode == "procOnly")
    local queueDesaturation = GetQueueDesaturation()
    
    -- Check if player is channeling (grey out queue to emphasize not interrupting)
    local isChanneling = UnitChannelInfo("player") ~= nil
    
    -- Cache frequently called functions to reduce table lookups in hot path
    local GetSpellCooldown = BlizzardAPI.GetSpellCooldown
    local IsSpellUsable = BlizzardAPI.IsSpellUsable
    local showHotkeys = profile.showOffensiveHotkeys ~= false
    local GetSpellHotkey = showHotkeys and ActionBarScanner and ActionBarScanner.GetSpellHotkey or nil
    local GetCachedSpellInfo = SpellQueue.GetCachedSpellInfo
    
    -- PERFORMANCE: Throttle cooldown updates - swipe animates smoothly once set
    -- Only update cooldowns every COOLDOWN_UPDATE_INTERVAL, not every frame
    local shouldUpdateCooldowns = (currentTime - lastCooldownUpdate) >= COOLDOWN_UPDATE_INTERVAL
    if shouldUpdateCooldowns then
        lastCooldownUpdate = currentTime
    end
    
    -- When frame should be hidden (mounted, out of combat, etc.), stop all glows and skip icon updates
    -- This prevents highlight frames from appearing with incorrect scaling when auto-hide is enabled
    if not shouldShowFrame then
        for i = 1, maxIcons do
            local icon = spellIconsRef[i]
            if icon then
                -- Stop all glow effects to prevent "large highlight frame" bug
                if icon.hasAssistedGlow then
                    UIAnimations.StopAssistedGlow(icon)
                    icon.hasAssistedGlow = false
                end
                if icon.hasProcGlow then
                    UIAnimations.HideProcGlow(icon)
                    icon.hasProcGlow = false
                end
                if icon.hasDefensiveGlow then
                    UIAnimations.StopDefensiveGlow(icon)
                    icon.hasDefensiveGlow = false
                end
            end
        end
    end
    
    -- Update individual icons (only when frame should be visible)
    if shouldShowFrame then
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
                    -- Track previous spell and change time for flash grace period
                    if icon.spellID then
                        icon.previousSpellID = icon.spellID
                        icon.spellChangeTime = currentTime  -- Used by key flash grace period
                        -- Preserve current hotkey as previous (even if new spell has same hotkey)
                        -- This ensures flash works when user presses key right as spell changes
                        if icon.normalizedHotkey then
                            icon.previousNormalizedHotkey = icon.normalizedHotkey
                        end
                    end
                    -- Reset cooldown cache so new spell's cooldown is properly applied
                    icon.lastCooldownStart = nil
                    icon.lastCooldownDuration = nil
                    icon.lastCooldownWasSecret = false  -- Reset secret flag for new spell
                end
                
                icon.spellID = spellID
                
                -- Reuse texture reference to avoid repeated lookup
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
                -- Cache the pattern check result when spell changes to avoid repeated string operations
                if spellChanged then
                    icon.isWaitingSpell = spellInfo.name and spellInfo.name:find("^Waiting for") or false
                end
                local centerText = icon.centerText
                if centerText then
                    if icon.isWaitingSpell then
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

                -- Update cooldowns using Blizzard's logic (handles GCD, spell CD, and charges)
                -- PERFORMANCE: Only update cooldowns when spell changed OR throttle interval passed
                -- The cooldown swipe animates smoothly once set, no need to update every frame
                if spellChanged or shouldUpdateCooldowns then
                    UpdateButtonCooldowns(icon)
                end

                -- Check if spell has an active proc (overlay)
                -- NOTE: Proc check is cheap (table lookup), so we check every frame for responsiveness
                -- Proc glows should appear instantly when ability becomes available
                local isProc = IsSpellProcced(spellID)

                -- Show blue/white assisted crawl on position 1 if glow mode includes primary
                local shouldShowAssisted = (i == 1 and showPrimaryGlow)
                if shouldShowAssisted then
                    -- Call every frame to update animation state based on combat status
                    UIAnimations.StartAssistedGlow(icon, isInCombat)
                    icon.hasAssistedGlow = true
                elseif icon.hasAssistedGlow then
                    UIAnimations.StopAssistedGlow(icon)
                    icon.hasAssistedGlow = false
                end

                -- Show custom proc glow if spell is procced (any position)
                local wantProcGlow = isProc and showProcGlow
                if wantProcGlow and not icon.hasProcGlow then
                    UIAnimations.ShowProcGlow(icon)
                    icon.hasProcGlow = true
                elseif not wantProcGlow and icon.hasProcGlow then
                    UIAnimations.HideProcGlow(icon)
                    icon.hasProcGlow = false
                end

                -- Hotkey lookup optimization: only query ActionBarScanner when action bars change
                -- Store result in icon.cachedHotkey and reuse until invalidated by ACTIONBAR_SLOT_CHANGED/UPDATE_BINDINGS
                local hotkey
                local hotkeyChanged = false
                if hotkeysDirty or spellChanged or not icon.cachedHotkey then
                    hotkey = GetSpellHotkey and GetSpellHotkey(spellID) or ""
                    if icon.cachedHotkey ~= hotkey then
                        hotkeyChanged = true
                    end
                    icon.cachedHotkey = hotkey
                else
                    hotkey = icon.cachedHotkey
                end
                
                -- Only update hotkey text if it changed (prevents flicker)
                local currentHotkey = icon.hotkeyText:GetText() or ""
                if currentHotkey ~= hotkey then
                    icon.hotkeyText:SetText(hotkey)
                end

                -- Normalize hotkey for key press flash matching
                -- PERFORMANCE: Only normalize when hotkey actually changed (string ops are expensive)
                if hotkeyChanged and hotkey ~= "" then
                    local normalized = hotkey:upper()
                    -- Expand modifier prefixes only when followed by a key (dash + key or key directly)
                    -- Multi-modifier combos must be checked first to avoid partial matches
                    normalized = normalized:gsub("^CA%-?(.+)", "CTRL-ALT-%1")
                    normalized = normalized:gsub("^CS%-?(.+)", "CTRL-SHIFT-%1")
                    normalized = normalized:gsub("^SA%-?(.+)", "SHIFT-ALT-%1")
                    normalized = normalized:gsub("^S%-?(.+)", "SHIFT-%1")
                    normalized = normalized:gsub("^C%-?(.+)", "CTRL-%1")
                    normalized = normalized:gsub("^A%-?(.+)", "ALT-%1")
                    normalized = normalized:gsub("^%+(.+)", "MOD-%1")  -- +5 -> MOD-5 (generic modifier)

                    -- Track previous hotkey for grace period (spell position changes)
                    if icon.normalizedHotkey and icon.normalizedHotkey ~= normalized then
                        icon.previousNormalizedHotkey = icon.normalizedHotkey
                        icon.hotkeyChangeTime = currentTime
                    end
                    icon.cachedNormalizedHotkey = normalized
                    icon.normalizedHotkey = normalized
                elseif hotkeyChanged then
                    -- Hotkey became empty
                    icon.cachedNormalizedHotkey = nil
                    icon.normalizedHotkey = nil
                end

                -- Note: Flash pass-through removed - Blizzard's flash is tied to the button
                -- that was pressed, not the spell. Cannot reliably mirror flash from action bars.
                
                -- Out-of-range indicator: red text if out of range, white otherwise
                -- Note: C_Spell.IsSpellInRange may return secret values in combat, fail-safe to white text
                -- PERFORMANCE: Only check range when spell changed OR throttle interval passed
                local isOutOfRange = false
                if hotkey ~= "" and C_Spell_IsSpellInRange then
                    if spellChanged or shouldUpdateCooldowns then
                        local inRange = C_Spell_IsSpellInRange(spellID)
                        if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
                            icon.cachedOutOfRange = (inRange == false)
                        else
                            icon.cachedOutOfRange = false
                        end
                    end
                    isOutOfRange = icon.cachedOutOfRange or false
                end
                -- PERFORMANCE: Only update text color when it actually changes
                if icon.lastOutOfRange ~= isOutOfRange then
                    icon.hotkeyText:SetTextColor(isOutOfRange and 1 or 1, isOutOfRange and 0 or 1, isOutOfRange and 0 or 1, 1)
                    icon.lastOutOfRange = isOutOfRange
                end
                
                -- Icon appearance: grey when channeling, blue tint when not enough resources, fade based on position
                local baseDesaturation = (i > 1) and queueDesaturation or 0
                
                -- PERFORMANCE: Calculate visual state and only update when changed
                local visualState  -- 1 = channeling, 2 = no resources, 3 = normal
                if isChanneling then
                    visualState = 1
                elseif isInCombat then
                    -- Cache usability check per icon - update when spell changes or at throttle interval
                    -- Use same interval as cooldowns (0.15s) for responsive resource feedback
                    if spellChanged or shouldUpdateCooldowns then
                        icon.cachedIsUsable, icon.cachedNotEnoughResources = IsSpellUsable(spellID)
                    end
                    if not icon.cachedIsUsable and icon.cachedNotEnoughResources then
                        visualState = 2
                    else
                        visualState = 3
                    end
                else
                    visualState = 3
                end
                
                -- Only call SetDesaturation/SetVertexColor when visual state changes
                if icon.lastVisualState ~= visualState or icon.lastBaseDesaturation ~= baseDesaturation then
                    if visualState == 1 then
                        iconTexture:SetDesaturation(1.0)
                        iconTexture:SetVertexColor(1, 1, 1)
                    elseif visualState == 2 then
                        iconTexture:SetDesaturation(0)
                        iconTexture:SetVertexColor(0.3, 0.3, 0.8)
                    else
                        iconTexture:SetDesaturation(baseDesaturation)
                        iconTexture:SetVertexColor(1, 1, 1)
                    end
                    icon.lastVisualState = visualState
                    icon.lastBaseDesaturation = baseDesaturation
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
                    icon.cachedIsUsable = nil
                    icon.cachedNotEnoughResources = nil
                    icon.isWaitingSpell = nil
                    icon.hasAssistedGlow = false
                    icon.hasProcGlow = false
                    icon.lastOutOfRange = nil
                    icon.lastVisualState = nil
                    icon.lastBaseDesaturation = nil
                    icon.cachedOutOfRange = nil
                    icon.cachedNormalizedHotkey = nil
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
    end  -- Close if shouldShowFrame then block
    
    -- Clear hotkey dirty flag after processing all icons
    hotkeysDirty = false
    
    -- Note: Defensive icon cooldowns are updated separately by UpdateDefensiveCooldowns()
    -- No need to update them here to avoid redundant calls
    
    -- Update frame visibility when state changes OR when actual visibility is out of sync
    -- The out-of-sync check catches a race where fadeOut's OnFinished hides the frame
    -- after lastFrameState.shouldShow was already set back to true (e.g., spells briefly
    -- cleared during Fel Rush then immediately restored)
    if addon.mainFrame then
        local isFadingOut = addon.mainFrame.fadeOut and addon.mainFrame.fadeOut:IsPlaying()
        local actuallyVisible = addon.mainFrame:IsShown() and not isFadingOut
        local visibilityDesynced = shouldShowFrame ~= actuallyVisible

        if frameStateChanged or spellCountChanged or visibilityDesynced then
            if shouldShowFrame then
                if not addon.mainFrame:IsShown() or isFadingOut then
                    -- Stop any fade-out in progress
                    if isFadingOut then
                        addon.mainFrame.fadeOut:Stop()
                    end
                    addon.mainFrame:Show()
                    addon.mainFrame:SetAlpha(0)
                    if addon.mainFrame.fadeIn then
                        addon.mainFrame.fadeIn:Play()
                    else
                        addon.mainFrame:SetAlpha(profile.frameOpacity or 1.0)
                    end
                end
            else
                if addon.mainFrame:IsShown() then
                    -- Fade out instead of instant hide
                    if addon.mainFrame.fadeOut and not isFadingOut then
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
    end
    
    -- Update interaction mode only when it changes (not every frame)
    local interactionMode = profile.panelInteraction or (profile.panelLocked and "locked" or "unlocked")

    if lastPanelLocked ~= interactionMode then
        lastPanelLocked = interactionMode
        local isClickThrough = interactionMode == "clickthrough"
        local isLocked = interactionMode == "locked" or isClickThrough

        if addon.mainFrame then
            addon.mainFrame:EnableMouse(not isLocked)
        end

        for i = 1, maxIcons do
            local icon = spellIconsRef[i]
            if icon then
                icon:EnableMouse(not isClickThrough)
                if isLocked then
                    icon:RegisterForClicks()
                else
                    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                end
            end
        end
        if addon.defensiveIcon then
            addon.defensiveIcon:EnableMouse(not isClickThrough)
            if isLocked then
                addon.defensiveIcon:RegisterForClicks()
            else
                addon.defensiveIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end
        end
        -- Defensive icon array
        if addon.defensiveIcons then
            for _, defIcon in ipairs(addon.defensiveIcons) do
                if defIcon then
                    defIcon:EnableMouse(not isClickThrough)
                    if isLocked then
                        defIcon:RegisterForClicks()
                    else
                        defIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    end
                end
            end
        end
        -- Grab tab stays interactive unless click-through (so users can still unlock)
        if addon.grabTab then
            addon.grabTab:EnableMouse(not isClickThrough)
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
UIRenderer.UpdateButtonCooldowns = UpdateButtonCooldowns
