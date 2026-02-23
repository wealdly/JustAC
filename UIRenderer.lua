-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: UI Renderer Module - Updates button icons, cooldowns, and animations each frame
local UIRenderer = LibStub:NewLibrary("JustAC-UIRenderer", 14)
if not UIRenderer then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIAnimations = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

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

-- Post-interrupt debounce: suppress interrupt reminder briefly after player
-- uses an interrupt/CC so the cast bar's lingering visibility doesn't cause
-- the addon to recommend the next spell in the list.
local INTERRUPT_DEBOUNCE = 1.0  -- seconds
local lastInterruptUsedTime = 0
local lastInterruptShownID  = nil
-- CC-applied suppression: when the player lands a CC spell on a target, suppress the
-- interrupt icon for a window so the next CC isn't suggested before the game registers
-- the CC state.  2s is enough to cover API state-registration lag; shorter than any
-- meaningful CC duration so back-to-back CCs on the same target still work.
local CC_APPLIED_SUPPRESS = 2.0  -- seconds
local lastCCAppliedTime   = 0

-- Check for proc overlay to highlight available abilities
-- BlizzardAPI.IsSpellProcced already checks both base and override IDs
local function IsSpellProcced(spellID)
    return BlizzardAPI.IsSpellProcced(spellID)
end

-- Normalize a raw WoW hotkey string to the MODIFIER-KEY format used by CreateKeyPressDetector.
-- Multi-modifier combos are checked first to prevent partial prefix matches.
local function NormalizeHotkey(hotkey)
    local n = hotkey:upper()
    n = n:gsub("^CA%-?(.+)", "CTRL-ALT-%1")
    n = n:gsub("^CS%-?(.+)", "CTRL-SHIFT-%1")
    n = n:gsub("^SA%-?(.+)", "SHIFT-ALT-%1")
    n = n:gsub("^S%-?(.+)",  "SHIFT-%1")
    n = n:gsub("^C%-?(.+)",  "CTRL-%1")
    n = n:gsub("^A%-?(.+)",  "ALT-%1")
    n = n:gsub("^%+(.+)",    "MOD-%1")
    return n
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
        -- Hide countdown text if user disabled it (template may re-show it after SetCooldown)
        if button.cooldownText then
            local cdProfile = BlizzardAPI and BlizzardAPI.GetProfile()
            local cdOverlays = cdProfile and cdProfile.textOverlays
            if cdOverlays and cdOverlays.cooldown and cdOverlays.cooldown.show == false then
                button.cooldownText:Hide()
            end
        end
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
                local chProfile = BlizzardAPI and BlizzardAPI.GetProfile()
                local chOverlays = chProfile and chProfile.textOverlays
                local showChargesCfg = not chOverlays or not chOverlays.charges or chOverlays.charges.show ~= false
                if showChargesCfg then
                    -- Pass currentCharges directly - FontString displays secret values correctly
                    button.chargeText:SetText(currentCharges)
                    button.chargeText:Show()
                else
                    button.chargeText:Hide()
                end
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

-- Visual constants (defaults, profile overrides where applicable)
local DEFAULT_QUEUE_DESATURATION = 0
local QUEUE_ICON_BRIGHTNESS = 1.0
local QUEUE_ICON_OPACITY = 1.0
local CLICK_DARKEN_ALPHA = 0.4
local CLICK_INSET_PIXELS = 2
-- Import shared visual constants from UIFrameFactory
local HOTKEY_FONT_SCALE = UIFrameFactory.HOTKEY_FONT_SCALE
local HOTKEY_MIN_FONT_SIZE = UIFrameFactory.HOTKEY_MIN_FONT_SIZE
local HOTKEY_OFFSET_FIRST = UIFrameFactory.HOTKEY_OFFSET_FIRST
local HOTKEY_OFFSET_QUEUE = UIFrameFactory.HOTKEY_OFFSET_QUEUE

local function GetQueueDesaturation()
    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
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
-- glowModeOverride: optional string ("all"/"primaryOnly"/"procOnly"/"none") that
--   replaces the profile.defensives.glowMode read — used by the nameplate overlay
--   so each display can have its own independent glow setting.
function UIRenderer.ShowDefensiveIcon(addon, id, isItem, defensiveIcon, showGlow, glowModeOverride, showHotkeysOverride, showFlashOverride)
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

    -- Hotkey lookup: needed for display AND for key press flash matching.
    -- Caller may pass overrides (e.g. overlay uses its own showHotkey/showFlash settings).
    local showHotkeys, showFlash
    if showHotkeysOverride ~= nil then
        showHotkeys = showHotkeysOverride
    else
        local defOverlays = addon.db and addon.db.profile and addon.db.profile.textOverlays
        showHotkeys = not defOverlays or not defOverlays.hotkey or defOverlays.hotkey.show ~= false
    end
    if showFlashOverride ~= nil then
        showFlash = showFlashOverride
    else
        showFlash = addon.db and addon.db.profile and addon.db.profile.defensives and addon.db.profile.defensives.showFlash ~= false
    end
    local hotkey = ""
    if showHotkeys or showFlash then
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
    -- When showHotkeys is off, clear displayed text but keep hotkey for flash matching
    local displayHotkey = showHotkeys and hotkey or ""
    local currentHotkey = defensiveIcon.hotkeyText:GetText() or ""
    if currentHotkey ~= displayHotkey then
        defensiveIcon.hotkeyText:SetText(displayHotkey)
    end

    -- Normalize hotkey for key press flash matching
    if hotkey ~= "" then
        local normalized = NormalizeHotkey(hotkey)
        if defensiveIcon.normalizedHotkey and defensiveIcon.normalizedHotkey ~= normalized then
            defensiveIcon.previousNormalizedHotkey = defensiveIcon.normalizedHotkey
            defensiveIcon.hotkeyChangeTime = GetTime()
        end
        defensiveIcon.normalizedHotkey = normalized
    else
        defensiveIcon.normalizedHotkey = nil
    end

    local isInCombat = UnitAffectingCombat("player")
    
    -- Defensive glow mode: use caller-supplied override (overlay) or fall back to
    -- the main-panel profile setting.
    local defGlowMode = glowModeOverride
        or (addon.db and addon.db.profile and addon.db.profile.defensives and addon.db.profile.defensives.glowMode)
        or "all"

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
        -- Reset cooldown state flags so UpdateButtonCooldowns re-shows widgets on reuse
        defensiveIcon._cooldownShown = nil
        defensiveIcon._chargeCooldownShown = nil
        defensiveIcon._cachedMaxCharges = nil
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

-- Reset and hide the interrupt icon, clearing all cached state and glows.
-- Exported so UINameplateOverlay can reuse the same cleanup logic.
function UIRenderer.HideInterruptIcon(intIcon)
    intIcon.spellID = nil
    intIcon.iconTexture:Hide()
    if intIcon.cooldown then intIcon.cooldown:Clear(); intIcon.cooldown:Hide() end
    intIcon._cooldownShown       = false
    intIcon._chargeCooldownShown = false
    intIcon.normalizedHotkey     = nil
    intIcon.cachedHotkey         = nil
    intIcon.cachedOutOfRange     = nil
    intIcon.lastOutOfRange       = nil
    intIcon.lastVisualState      = nil
    intIcon.hotkeyText:SetText("")
    intIcon.iconTexture:SetDesaturation(0)
    if UIAnimations then
        if intIcon.hasInterruptGlow then UIAnimations.StopInterruptGlow(intIcon); intIcon.hasInterruptGlow = false end
        if intIcon.hasProcGlow      then UIAnimations.HideProcGlow(intIcon);      intIcon.hasProcGlow      = false end
    end
    -- Hide cast aura (enemy spell indicator)
    if intIcon.castAura then
        intIcon.castAura:Hide()
    end
    intIcon:Hide()
end

function UIRenderer.RenderSpellQueue(addon, spellIDs)
    if not addon then return end
    local spellIconsRef = addon.spellIcons
    if not spellIconsRef then return end

    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    if not profile then return end

    local currentTime = GetTime()
    local hasSpells = spellIDs and #spellIDs > 0
    local spellCount = hasSpells and #spellIDs or 0
    
    -- Determine if frame should be visible
    local shouldShowFrame = hasSpells

    -- Hide main queue when displayMode excludes it
    local displayMode = profile.displayMode or "queue"
    if displayMode == "disabled" or displayMode == "overlay" then
        shouldShowFrame = false
    end

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
    -- PlayerChannelBarFrame is a visual frame — NeverSecret, avoids pcall for UnitChannelInfo
    local isChanneling = PlayerChannelBarFrame and PlayerChannelBarFrame:IsShown() or false
    
    -- Cache frequently called functions to reduce table lookups in hot path
    local IsSpellUsable = BlizzardAPI.IsSpellUsable
    local overlays = profile.textOverlays
    local showHotkeys = not overlays or not overlays.hotkey or overlays.hotkey.show ~= false
    local showFlash = profile.showFlash ~= false
    -- Look up hotkeys when displaying text OR when flash needs normalizedHotkey for matching
    local GetSpellHotkey = (showHotkeys or showFlash) and ActionBarScanner and ActionBarScanner.GetSpellHotkey or nil
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

    -- ── Interrupt reminder (position 0) ─────────────────────────────────────
    -- Detect interruptible cast via the target nameplate's cast bar frame
    -- state.  Uses Icon:IsShown() for 12.0-safe interruptibility detection.
    local intIcon = addon.interruptIcon
    local resolvedInts = addon.resolvedInterrupts
    local showInterrupt = profile.showInterrupt ~= false
    local ccRegularMobs = profile.ccRegularMobs ~= false
    if intIcon and resolvedInts and shouldShowFrame and showInterrupt then
        local shouldShowInterrupt = false
        local intSpellID = nil

        -- Debounce: if we just used an interrupt/CC, suppress for a short window
        -- so the lingering cast bar doesn't trigger the next spell in the list.
        local debounceActive = (currentTime - lastInterruptUsedTime) < INTERRUPT_DEBOUNCE
                            or (currentTime - lastCCAppliedTime) < CC_APPLIED_SUPPRESS

        if not debounceActive then
            -- Look up the target nameplate to read its cast bar state
            local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target", false)
            local castBar = nameplate and nameplate.UnitFrame and nameplate.UnitFrame.castBar
            if castBar then
                local visOk, isVis = pcall(castBar.IsVisible, castBar)
                local visTestOk, castVisible = pcall(function() return isVis and true or false end)
                if visOk and visTestOk and castVisible then
                    local interruptible = true  -- fail-open default
                    -- Primary: Icon hidden = uninterruptible (12.0-safe).
                    -- Nameplate castbars have HideIconWhenNotInterruptible=true;
                    -- Blizzard's secure ShouldIconBeShown() resolves barType
                    -- taint internally and returns a plain literal boolean, so
                    -- Icon:IsShown() is NeverSecret on nameplate castbars.
                    if castBar.Icon and castBar.HideIconWhenNotInterruptible then
                        local iconOk, iconShown = pcall(castBar.Icon.IsShown, castBar.Icon)
                        if iconOk and iconShown == false then
                            interruptible = false  -- Icon hidden → cast not interruptible
                        end
                    -- Fallback: BorderShield (pre-12.0 or castbars without Icon hiding)
                    elseif castBar.BorderShield then
                        local shOk, shShown = pcall(castBar.BorderShield.IsShown, castBar.BorderShield)
                        local shTestOk, shieldVisible = pcall(function() return shShown and true or false end)
                        if shOk and shTestOk and shieldVisible then
                            interruptible = false  -- shield visible → uninterruptible
                        end
                    end

                    if interruptible then
                        -- Target is casting an interruptible spell — find best
                        -- available interrupt or CC.
                        local targetCCImmune = BlizzardAPI.IsTargetCCImmune()
                        -- NeverSecret when available; nil-guarded for versions where API doesn't exist
                        local targetAlreadyCC = UnitIsCrowdControlled and UnitIsCrowdControlled("target") or false
                        -- ccRegularMobs: prefer CC on non-boss mobs, save kick
                        local preferCC = ccRegularMobs and not targetCCImmune
                        if preferCC then
                            -- First pass: try CC spells only
                            -- Skip if target is already CC'd (no point re-CCing an incapacitated mob)
                            if not targetAlreadyCC then
                                for _, entry in ipairs(resolvedInts) do
                                    local sid = entry.spellID
                                    -- IsSpellUsable: checks current castability (form, stealth, resources)
                                    -- IsSpellAvailable only checks if the spell is learned, not if it's castable now
                                    if entry.type == "cc" and BlizzardAPI.IsSpellUsable(sid) and not SpellDB.IsInterruptOnCooldown(sid) then
                                        intSpellID = sid
                                        shouldShowInterrupt = true
                                        break
                                    end
                                end
                            end
                        end
                        -- Fallback (or boss / CC disabled): use any available spell
                        if not shouldShowInterrupt then
                            for _, entry in ipairs(resolvedInts) do
                                local sid = entry.spellID
                                local stype = entry.type
                                -- Skip: CC vs bosses (immune), or any interrupt vs already-CC'd target (can't cast while CC'd)
                                if (stype == "cc" and targetCCImmune) or targetAlreadyCC then
                                    -- skip
                                elseif BlizzardAPI.IsSpellUsable(sid) and not SpellDB.IsInterruptOnCooldown(sid) then
                                    intSpellID = sid
                                    shouldShowInterrupt = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Track when the shown interrupt goes on cooldown → start debounce.
        -- NOTE: the CD check intentionally runs even when shouldShowInterrupt=true (another
        -- spell ready): if the previously tracked spell just went on CD (was cast), we still
        -- start the debounce so the game has time to register the CC state before we show
        -- the next suggestion.  Without this, a second CC briefly flashes immediately after
        -- the first one lands.
        if lastInterruptShownID then
            if SpellDB.IsInterruptOnCooldown(lastInterruptShownID) then
                lastInterruptUsedTime = currentTime  -- start debounce regardless of next spell
                lastInterruptShownID = nil
            elseif not shouldShowInterrupt then
                lastInterruptShownID = nil  -- cast bar gone / target changed: just clear
            end
        end

        -- De-dup: if the interrupt spell is already shown as offensive queue position 1, skip it
        if shouldShowInterrupt and intSpellID and spellIDs and spellIDs[1] == intSpellID then
            shouldShowInterrupt = false
        end

        if shouldShowInterrupt and intSpellID then
            lastInterruptShownID = intSpellID
            local spellChanged = (intIcon.spellID ~= intSpellID)
            if spellChanged then
                intIcon.spellID = intSpellID
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(intSpellID)
                if info and info.iconID then
                    intIcon.iconTexture:SetTexture(info.iconID)
                    intIcon.iconTexture:Show()
                end
                intIcon._cooldownShown       = false
                intIcon._chargeCooldownShown = false
                intIcon._cachedMaxCharges    = nil
                intIcon.cachedHotkey         = nil
            end

            -- Cooldowns (throttled)
            if spellChanged or shouldUpdateCooldowns then
                UpdateButtonCooldowns(intIcon)
            end

            -- Hotkey
            local intOverlays = profile.textOverlays
            local intShowHotkeys = not intOverlays or not intOverlays.hotkey or intOverlays.hotkey.show ~= false
            if spellChanged or shouldUpdateCooldowns or not intIcon.cachedHotkey then
                local hotkey = ActionBarScanner and ActionBarScanner.GetSpellHotkey and ActionBarScanner.GetSpellHotkey(intSpellID) or ""
                intIcon.cachedHotkey = hotkey
                local displayHotkey = intShowHotkeys and hotkey or ""
                if (intIcon.hotkeyText:GetText() or "") ~= displayHotkey then
                    intIcon.hotkeyText:SetText(displayHotkey)
                end
                if hotkey ~= "" then
                    intIcon.normalizedHotkey = NormalizeHotkey(hotkey)
                else
                    intIcon.normalizedHotkey = nil
                end
            end

            -- Out-of-range: red hotkey text when target is beyond interrupt range
            if intShowHotkeys and intIcon.cachedHotkey and intIcon.cachedHotkey ~= "" then
                if spellChanged or shouldUpdateCooldowns then
                    local inRange = C_Spell_IsSpellInRange and C_Spell_IsSpellInRange(intSpellID)
                    if inRange ~= nil and not BlizzardAPI.IsSecretValue(inRange) then
                        intIcon.cachedOutOfRange = (inRange == false)
                    else
                        intIcon.cachedOutOfRange = false
                    end
                end
                local isOutOfRange = intIcon.cachedOutOfRange or false
                if intIcon.lastOutOfRange ~= isOutOfRange then
                    if isOutOfRange then
                        intIcon.hotkeyText:SetTextColor(1, 0, 0, 1)
                    else
                        local hkc = intOverlays and intOverlays.hotkey and intOverlays.hotkey.color
                        intIcon.hotkeyText:SetTextColor((hkc and hkc.r) or 1, (hkc and hkc.g) or 1, (hkc and hkc.b) or 1, (hkc and hkc.a) or 1)
                    end
                    intIcon.lastOutOfRange = isOutOfRange
                end
            end

            -- Channeling grey-out: desaturate when player is channeling (can't interrupt)
            local intVisualState = isChanneling and 1 or 3
            if intIcon.lastVisualState ~= intVisualState then
                if intVisualState == 1 then
                    intIcon.iconTexture:SetDesaturation(1.0)
                else
                    intIcon.iconTexture:SetDesaturation(0)
                end
                intIcon.lastVisualState = intVisualState
            end

            -- Glow: red-tinted proc glow for interrupt urgency
            if not intIcon.hasInterruptGlow then
                UIAnimations.StartInterruptGlow(intIcon, isInCombat)
                intIcon.hasInterruptGlow = true
            end

            -- Cast aura: passthrough the enemy cast bar icon texture from the nameplate
            -- (castBar textures can be secret values in 12.0 combat — never compare them,
            --  just pass through to SetTexture unconditionally; Blizzard handles secrets in UI)
            if intIcon.castAura then
                local castIcon = castBar and castBar.Icon
                if castIcon and castIcon.GetTexture then
                    intIcon.castAura.iconTexture:SetTexture(castIcon:GetTexture())
                    if not intIcon.castAura:IsShown() then intIcon.castAura:Show() end
                else
                    if intIcon.castAura:IsShown() then intIcon.castAura:Hide() end
                end
            end

            if not intIcon:IsShown() then intIcon:Show() end
            local frameOpacity = profile.frameOpacity or 1.0
            intIcon:SetAlpha(frameOpacity)
        else
            -- Hide interrupt icon
            if intIcon.spellID or intIcon:IsShown() then
                UIRenderer.HideInterruptIcon(intIcon)
            end
        end
    elseif intIcon and (intIcon.spellID or intIcon:IsShown()) then
        -- Feature disabled or frame hidden — ensure interrupt icon is cleaned up
        UIRenderer.HideInterruptIcon(intIcon)
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
                -- When showHotkeys is off, clear displayed text but keep hotkey for flash matching
                local displayHotkey = showHotkeys and hotkey or ""
                local currentHotkey = icon.hotkeyText:GetText() or ""
                if currentHotkey ~= displayHotkey then
                    icon.hotkeyText:SetText(displayHotkey)
                end

                -- Normalize hotkey for key press flash matching
                -- Only normalize when hotkey actually changed (string ops are expensive)
                if hotkeyChanged and hotkey ~= "" then
                    local normalized = NormalizeHotkey(hotkey)
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
                if displayHotkey ~= "" and C_Spell_IsSpellInRange then
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
                    if isOutOfRange then
                        icon.hotkeyText:SetTextColor(1, 0, 0, 1)
                    else
                        local hkc = overlays and overlays.hotkey and overlays.hotkey.color
                        icon.hotkeyText:SetTextColor((hkc and hkc.r) or 1, (hkc and hkc.g) or 1, (hkc and hkc.b) or 1, (hkc and hkc.a) or 1)
                    end
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
                    icon._cooldownShown = nil
                    icon._chargeCooldownShown = nil
                    icon._cachedMaxCharges = nil
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

    -- ── Burst CD Indicator ──────────────────────────────────────────────────
    -- Small icon near position 1 that lights up when a major offensive CD is ready.
    local burstIcon = addon.burstCDIndicator
    if burstIcon and burstIcon.burstSpells then
        local burstProfile = profile.burstCDIndicator
        local burstEnabled = not burstProfile or burstProfile.enabled ~= false
        if shouldShowFrame and burstEnabled and isInCombat then
            -- Find the first burst spell that is ready (off CD)
            local readySpellID = nil
            local onCDSpellID = nil
            local onCDRemaining = 0
            local onCDDuration = 0
            for _, sid in ipairs(burstIcon.burstSpells) do
                local isOnCD, remaining, duration = BlizzardAPI.GetBurstCooldownState(sid)
                if not isOnCD then
                    readySpellID = sid
                    break
                else
                    -- Track the one closest to being ready for CD swipe display
                    if not onCDSpellID or remaining < onCDRemaining then
                        onCDSpellID = sid
                        onCDRemaining = remaining
                        onCDDuration = duration
                    end
                end
            end

            local displaySpellID = readySpellID or onCDSpellID
            if displaySpellID then
                local spellChanged = (burstIcon.currentSpellID ~= displaySpellID)
                if spellChanged then
                    burstIcon.currentSpellID = displaySpellID
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(displaySpellID)
                    if info and info.iconID then
                        burstIcon.iconTexture:SetTexture(info.iconID)
                        burstIcon.iconTexture:Show()
                    end
                end

                -- Ready vs on-CD visuals
                local wasReady = burstIcon.isReady
                burstIcon.isReady = (readySpellID ~= nil)

                if burstIcon.isReady then
                    -- Spell is ready: bright icon + green pulsing glow
                    burstIcon.iconTexture:SetDesaturation(0)
                    burstIcon.iconTexture:SetVertexColor(1, 1, 1, 1)
                    if burstIcon.cooldown then burstIcon.cooldown:Clear(); burstIcon.cooldown:Hide() end
                    if not wasReady then
                        burstIcon.glowTexture:Show()
                        if burstIcon.pulseAnim and not burstIcon.pulseAnim:IsPlaying() then
                            burstIcon.pulseAnim:Play()
                        end
                    end
                else
                    -- On cooldown: desaturated icon + CD swipe, no glow
                    burstIcon.iconTexture:SetDesaturation(0.7)
                    burstIcon.iconTexture:SetVertexColor(0.6, 0.6, 0.6, 0.8)
                    burstIcon.glowTexture:Hide()
                    if burstIcon.pulseAnim and burstIcon.pulseAnim:IsPlaying() then
                        burstIcon.pulseAnim:Stop()
                    end
                    -- Show CD swipe (approximate via local tracking)
                    if onCDDuration > 0 and burstIcon.cooldown then
                        local startTime = GetTime() - (onCDDuration - onCDRemaining)
                        burstIcon.cooldown:SetCooldown(startTime, onCDDuration)
                        burstIcon.cooldown:Show()
                    end
                end

                -- Show the indicator
                if not burstIcon:IsShown() then
                    burstIcon:SetAlpha(0)
                    burstIcon:Show()
                    if burstIcon.fadeIn then burstIcon.fadeIn:Play() end
                end
                burstIcon:SetAlpha(profile.frameOpacity or 1.0)
            else
                -- No burst spells tracked, hide
                if burstIcon:IsShown() then burstIcon:Hide() end
            end
        else
            -- Frame hidden or out of combat or disabled: hide burst indicator
            if burstIcon:IsShown() then
                burstIcon.glowTexture:Hide()
                if burstIcon.pulseAnim and burstIcon.pulseAnim:IsPlaying() then
                    burstIcon.pulseAnim:Stop()
                end
                burstIcon:Hide()
                burstIcon.isReady = false
            end
        end
    end
    
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
    
    local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
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

-- Public exports (locals need explicit assignment)
UIRenderer.UpdateButtonCooldowns = UpdateButtonCooldowns
UIRenderer.NormalizeHotkey       = NormalizeHotkey

-- Called by JustAC when the player successfully casts a CC spell.
-- Activates the CC_APPLIED_SUPPRESS window so the next CC suggestion is held
-- back until the game can register the CC state on the target.
function UIRenderer.NotifyCCApplied()
    lastCCAppliedTime = GetTime()
end
