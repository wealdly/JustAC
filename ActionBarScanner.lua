-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Action Bar Scanner Module - Caches action bar slots and keybind mappings
local ActionBarScanner = LibStub:NewLibrary("JustAC-ActionBarScanner", 33)
if not ActionBarScanner then return end
ActionBarScanner.lastKeybindChangeTime = 0

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local MacroParser = LibStub("JustAC-MacroParser", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- Cache frequently used functions to reduce table lookups on every update
local GetTime = GetTime
local HasAction = HasAction
local GetBindingKey = GetBindingKey
local GetActionCooldown = GetActionCooldown
local C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local C_Spell_GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local FindBaseSpellByID = FindBaseSpellByID
local FindSpellOverrideByID = FindSpellOverrideByID
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local math_max = math.max
local math_min = math.min

-- Gamepad face button atlas mappings by style (using _64 atlas with outline for better visibility)
-- Format: {PAD1, PAD2, PAD3, PAD4, PAD5, PAD6}
-- Atlas format: |A:name:height:width|a
-- Normal size (14:14) for single buttons, small size (10:10) for modifier combos
local GAMEPAD_FACE_BUTTONS = {
    generic = {
        normal = {
            "|A:Gamepad_Gen_1_64:14:14|a",
            "|A:Gamepad_Gen_2_64:14:14|a",
            "|A:Gamepad_Gen_3_64:14:14|a",
            "|A:Gamepad_Gen_4_64:14:14|a",
            "|A:Gamepad_Gen_5_64:14:14|a",
            "|A:Gamepad_Gen_6_64:14:14|a",
        },
        small = {
            "|A:Gamepad_Gen_1_64:10:10|a",
            "|A:Gamepad_Gen_2_64:10:10|a",
            "|A:Gamepad_Gen_3_64:10:10|a",
            "|A:Gamepad_Gen_4_64:10:10|a",
            "|A:Gamepad_Gen_5_64:10:10|a",
            "|A:Gamepad_Gen_6_64:10:10|a",
        },
    },
    xbox = {
        normal = {
            "|A:Gamepad_Ltr_A_64:14:14|a",
            "|A:Gamepad_Ltr_B_64:14:14|a",
            "|A:Gamepad_Ltr_X_64:14:14|a",
            "|A:Gamepad_Ltr_Y_64:14:14|a",
            "|A:Gamepad_Gen_5_64:14:14|a",
            "|A:Gamepad_Gen_6_64:14:14|a",
        },
        small = {
            "|A:Gamepad_Ltr_A_64:10:10|a",
            "|A:Gamepad_Ltr_B_64:10:10|a",
            "|A:Gamepad_Ltr_X_64:10:10|a",
            "|A:Gamepad_Ltr_Y_64:10:10|a",
            "|A:Gamepad_Gen_5_64:10:10|a",
            "|A:Gamepad_Gen_6_64:10:10|a",
        },
    },
    playstation = {
        normal = {
            "|A:Gamepad_Shp_Cross_64:14:14|a",
            "|A:Gamepad_Shp_Circle_64:14:14|a",
            "|A:Gamepad_Shp_Square_64:14:14|a",
            "|A:Gamepad_Shp_Triangle_64:14:14|a",
            "|A:Gamepad_Shp_MicMute_64:14:14|a",
            "|A:Gamepad_Shp_TouchpadR_64:14:14|a",
        },
        small = {
            "|A:Gamepad_Shp_Cross_64:10:10|a",
            "|A:Gamepad_Shp_Circle_64:10:10|a",
            "|A:Gamepad_Shp_Square_64:10:10|a",
            "|A:Gamepad_Shp_Triangle_64:10:10|a",
            "|A:Gamepad_Shp_MicMute_64:10:10|a",
            "|A:Gamepad_Shp_TouchpadR_64:10:10|a",
        },
    },
}

-- Helper to get face button atlas based on current setting
-- size: "normal" (14:14) or "small" (10:10) for modifier combos
local function GetGamepadFaceButton(buttonNum, size)
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    local style = (addon and addon.db and addon.db.profile.gamepadIconStyle) or "xbox"
    local styleButtons = GAMEPAD_FACE_BUTTONS[style] or GAMEPAD_FACE_BUTTONS.xbox
    local sizeButtons = styleButtons[size or "normal"] or styleButtons.normal
    return sizeButtons[buttonNum] or sizeButtons[1]
end
local string_byte = string.byte
local string_gsub = string.gsub

local cachedAddon = nil
local function GetCachedAddon()
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedAddon
end

local NUM_ACTIONBAR_BUTTONS = 12
local MAX_ACTION_SLOTS = 200

-- Three-level cache to avoid repeated API calls: action slots → keybinds → hotkeys
local bindingKeyCache = {}
local bindingCacheValid = false
local slotMappingCache = {}
local slotMappingCacheKey = 0
local keybindCache = {}
local keybindCacheValid = false
local lastValidatedStateHash = 0
local isRebuildingBindings = false

local spellHotkeyCache = {}
local spellHotkeyCacheValid = false

-- Cache slot mappings so hotkey lookups don't fail when spell changes mid-GCD
local spellSlotCache = {}

-- PERFORMANCE: Cache abbreviated keybinds (50+ gsub calls per abbreviation is expensive)
-- Key: raw binding string, Value: abbreviated string
local abbreviatedKeyCache = {}
local abbreviatedKeyCacheSize = 0
local MAX_ABBREVIATED_CACHE_SIZE = 100

-- PERFORMANCE: Rate-limit full hotkey lookups (FindSpellInActions is VERY expensive)
-- When cache is invalid, we return stale value immediately and only refresh periodically
local lastHotkeyRefreshTime = 0
local HOTKEY_REFRESH_INTERVAL = 0.25  -- Refresh stale entries max 4x/sec (enough for responsiveness)

local verboseDebugMode = false

function ActionBarScanner.SetVerboseDebug(enabled)
    verboseDebugMode = enabled
end

-- Track page, form, and override state to detect when keybinds need refresh
local cachedStateData = {
    page = 1,
    bonusOffset = 0,
    form = 0,
    hasOverride = false,
    hasVehicle = false,
    hasTemp = false,
    hash = 0,
    valid = false,
}

local function UpdateCachedState()
    cachedStateData.page = GetActionBarPage and GetActionBarPage() or 1
    cachedStateData.bonusOffset = GetBonusBarOffset and GetBonusBarOffset() or 0
    -- FormCache uses reliable iteration; fallback to 0 (caster form) if unavailable
    cachedStateData.form = FormCache and FormCache.GetActiveForm() or 0
    cachedStateData.hasOverride = HasOverrideActionBar and HasOverrideActionBar() or false
    cachedStateData.hasVehicle = HasVehicleActionBar and HasVehicleActionBar() or false
    cachedStateData.hasTemp = HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() or false
    
    cachedStateData.hash = cachedStateData.page + (cachedStateData.bonusOffset * 100) + (cachedStateData.form * 10000)
    if cachedStateData.hasOverride then cachedStateData.hash = cachedStateData.hash + 1000000 end
    if cachedStateData.hasVehicle then cachedStateData.hash = cachedStateData.hash + 2000000 end
    if cachedStateData.hasTemp then cachedStateData.hash = cachedStateData.hash + 4000000 end
    
    cachedStateData.valid = true
end

local function GetCachedStateHash()
    if not cachedStateData.valid then
        UpdateCachedState()
    end
    return cachedStateData.hash
end

-- PERFORMANCE: Cache the binding hash value - only recompute when bindings actually change
local cachedBindingHash = 0

local function RebuildBindingCache()
    wipe(bindingKeyCache)
    local patterns = {
        "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON",
        "MULTIACTIONBAR3BUTTON", "MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON",
        "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON",
    }
    
    for i, pattern in ipairs(patterns) do
        for j = 1, NUM_ACTIONBAR_BUTTONS do
            local bindingKey = pattern .. j
            bindingKeyCache[bindingKey] = GetBindingKey(bindingKey) or ""
        end
    end
    
    -- PERFORMANCE: Compute hash once when rebuilding cache, not on every validation check
    local hash = 0
    for bindingKey, key in pairs(bindingKeyCache) do
        if key and key ~= "" then
            for k = 1, #key do
                local byte = string.byte(key, k)
                if byte then
                    hash = (hash * 31 + byte) % 2147483647
                end
            end
        end
    end
    cachedBindingHash = hash
    
    bindingCacheValid = true
end

local function GetCachedBindingKey(bindingKey)
    if not bindingCacheValid then
        RebuildBindingCache()
    end
    return bindingKeyCache[bindingKey] or ""
end

-- PERFORMANCE: Return cached hash instead of recomputing every call
local function CalculateKeybindHash()
    if not bindingCacheValid then
        RebuildBindingCache()
    end
    return cachedBindingHash
end

local function CalculateActionSlot(buttonID, barType)
    if not cachedStateData.valid then
        UpdateCachedState()
    end
    
    local page = 1
    
    if barType == "main" then
        page = cachedStateData.page
        if cachedStateData.bonusOffset > 0 then
            page = 6 + cachedStateData.bonusOffset
        end
    elseif barType == "multibar1" then
        page = 6
    elseif barType == "multibar2" then
        page = 5
    elseif barType == "multibar3" then
        page = 3
    elseif barType == "multibar4" then
        page = 4
    elseif barType == "multibar5" then
        page = 13
    elseif barType == "multibar6" then
        page = 14
    elseif barType == "multibar7" then
        page = 15
    end
    
    local safePage = math.max(1, page)
    local safeButtonID = math.max(1, math.min(buttonID, NUM_ACTIONBAR_BUTTONS))
    
    return safeButtonID + ((safePage - 1) * NUM_ACTIONBAR_BUTTONS)
end

local function GetCachedSlotMapping()
    local currentHash = GetCachedStateHash()
    
    if slotMappingCacheKey == currentHash and next(slotMappingCache) then
        return slotMappingCache
    end
    
    local mapping = {}
    
    for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
        local slot = CalculateActionSlot(buttonID, "main")
        mapping[slot] = "ACTIONBUTTON" .. buttonID
    end
    
    for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
        mapping[buttonID] = "ACTIONBUTTON" .. buttonID
    end
    
    local barMappings = {
        {barType = "multibar1", pattern = "MULTIACTIONBAR1BUTTON"},
        {barType = "multibar2", pattern = "MULTIACTIONBAR2BUTTON"},
        {barType = "multibar3", pattern = "MULTIACTIONBAR3BUTTON"},
        {barType = "multibar4", pattern = "MULTIACTIONBAR4BUTTON"},
        {barType = "multibar5", pattern = "MULTIACTIONBAR5BUTTON"},
        {barType = "multibar6", pattern = "MULTIACTIONBAR6BUTTON"},
        {barType = "multibar7", pattern = "MULTIACTIONBAR7BUTTON"},
    }
    
    for _, barData in ipairs(barMappings) do
        for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
            local slot = CalculateActionSlot(buttonID, barData.barType)
            mapping[slot] = barData.pattern .. buttonID
        end
    end
    
    slotMappingCache = mapping
    slotMappingCacheKey = currentHash
    
    return mapping
end

local function ValidateAndBuildKeybindCache()
    local newKeybindHash = CalculateKeybindHash()
    local stateHash = GetCachedStateHash()
    local combinedHash = newKeybindHash * 10000000 + stateHash  -- Form changes trigger rebuild

    if keybindCacheValid and lastValidatedStateHash == combinedHash then
        return
    end

    lastValidatedStateHash = combinedHash

    wipe(keybindCache)
    local slotMapping = GetCachedSlotMapping()

    for slot, keybindPattern in pairs(slotMapping) do
        local key = GetCachedBindingKey(keybindPattern)
        if key and key ~= "" then
            keybindCache[slot] = key
        end
    end

    keybindCacheValid = true
end

local function InvalidateKeybindCache()
    keybindCacheValid = false
    lastValidatedStateHash = 0
    wipe(keybindCache)
    spellHotkeyCacheValid = false
    wipe(spellHotkeyCache)
    wipe(spellSlotCache)
end

local function InvalidateBindingCache()
    bindingCacheValid = false
    wipe(bindingKeyCache)
    -- NOTE: Do NOT clear abbreviatedKeyCache here - it's keyed by raw keybind strings
    -- (like "SHIFT-PAD1") and the abbreviation only depends on gamepad icon style,
    -- not on which spells are bound. Clearing it on every binding change defeats caching.
    InvalidateKeybindCache()
end

local function InvalidateStateCache()
    cachedStateData.valid = false
    slotMappingCacheKey = 0
    wipe(slotMappingCache)
    spellHotkeyCacheValid = false
    wipe(spellHotkeyCache)
end

local function GetOptimizedKeybind(slot)
    if not slot or slot < 1 or slot > MAX_ACTION_SLOTS then
        return nil
    end
    
    ValidateAndBuildKeybindCache()
    return keybindCache[slot]
end

local function SearchSlots(slotSet, priority, spellID, spellName, debugMode)
    local candidates = {}
    
    for slot in pairs(slotSet) do
        if not HasAction(slot) then
            -- empty slot
        else
            local actionType, id, subType, macroSpellID = BlizzardAPI.GetActionInfo(slot)

            if not actionType then
                -- invalid
            elseif actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
                -- Assisted Combat placeholder
            elseif C_ActionBar and C_ActionBar.IsAssistedCombatAction and C_ActionBar.IsAssistedCombatAction(slot) then
                -- Assisted Combat slot
            else
                local slotKeybind = GetOptimizedKeybind(slot)
                local hasHotkey = slotKeybind ~= nil and slotKeybind ~= ""
                
                if actionType == "spell" then
                    local isMatch = (id == spellID)

                    -- Slot's base transforms to our target (e.g., Pyroblast → Hot Streak)
                    if not isMatch and id and id ~= spellID then
                        local slotSpellOverride = C_Spell_GetOverrideSpell and C_Spell_GetOverrideSpell(id)
                        if slotSpellOverride and slotSpellOverride == spellID then
                            isMatch = true
                        end
                    end

                    -- Our target transforms to slot's spell (reverse)
                    if not isMatch then
                        local targetOverride = C_Spell_GetOverrideSpell and C_Spell_GetOverrideSpell(spellID)
                        if targetOverride and targetOverride ~= 0 and targetOverride ~= spellID and id == targetOverride then
                            isMatch = true
                        end
                    end

                    -- Target is override, slot has base
                    if not isMatch and FindBaseSpellByID then
                        local baseSpellID = FindBaseSpellByID(spellID)
                        if baseSpellID and baseSpellID ~= spellID and baseSpellID == id then
                            isMatch = true
                        end
                    end

                    -- Slot has override, we want base
                    if not isMatch and FindBaseSpellByID and id then
                        local slotBaseSpellID = FindBaseSpellByID(id)
                        if slotBaseSpellID and slotBaseSpellID ~= id and slotBaseSpellID == spellID then
                            isMatch = true
                        end
                    end
                    
                    if isMatch then
                        candidates[#candidates + 1] = {
                            slot = slot,
                            type = "direct",
                            modifiers = {},
                            priority = priority,
                            score = hasHotkey and 1000 or -500
                        }
                    end
                elseif actionType == "macro" then
                    if subType == "spell" and macroSpellID and macroSpellID > 0 then
                        local macroIconSpellInfo = C_Spell_GetSpellInfo and C_Spell_GetSpellInfo(macroSpellID)
                        if macroIconSpellInfo and macroIconSpellInfo.name == spellName then
                            candidates[#candidates + 1] = {
                                slot = slot,
                                type = "macro_visible",
                                modifiers = {},
                                priority = priority,
                                score = hasHotkey and 900 or -600
                            }
                        end
                    end

                    if MacroParser and MacroParser.GetMacroSpellInfo then
                        local parsedEntry = MacroParser.GetMacroSpellInfo(slot, spellID, spellName)
                        if parsedEntry and parsedEntry.found then
                            local baseScore = parsedEntry.qualityScore or 500
                            candidates[#candidates + 1] = {
                                slot = slot,
                                type = "macro_conditional",
                                modifiers = parsedEntry.modifiers or {},
                                priority = priority,
                                score = hasHotkey and baseScore or (baseScore - 1000)
                            }
                        end
                    end
                end
            end
        end
    end
    
    -- Early exit if no candidates found
    if #candidates == 0 then
        return nil, nil
    end
    
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.slot < b.slot
    end)
    
    local bestCandidate = candidates[1]
    
    if debugMode then
        print("|JAC| Selected slot " .. bestCandidate.slot .. " with score " .. bestCandidate.score)
    end
    
    return bestCandidate.slot, bestCandidate
end

local function FindSpellInActions(spellID, spellName)
    if not spellID or spellID == 0 or not spellName or spellName == "" then 
        return nil, nil 
    end
    
    local slotMapping = GetCachedSlotMapping()
    
    if not cachedStateData.valid then
        UpdateCachedState()
    end
    local bonusOffset = cachedStateData.bonusOffset
    
    -- Form bars replace main bar visually; keybinds follow what's currently shown
    local currentBarSlots = {}
    local fallbackSlots = {}

    if bonusOffset > 0 then
        -- Form bar active: use form slots, keep base slots as fallback
        local formBarStart = 1 + (6 + bonusOffset - 1) * NUM_ACTIONBAR_BUTTONS
        for i = formBarStart, formBarStart + 11 do
            if slotMapping[i] then
                currentBarSlots[i] = true
            end
        end
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            if slotMapping[i] then
                fallbackSlots[i] = true
            end
        end
    else
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            if slotMapping[i] then
                currentBarSlots[i] = true
            end
        end
    end

    -- Multi-bar slots (always visible)
    for slot in pairs(slotMapping) do
        if slot > NUM_ACTIONBAR_BUTTONS then
            local isFormBarSlot = false
            if bonusOffset > 0 then
                local formBarStart = 1 + (6 + bonusOffset - 1) * NUM_ACTIONBAR_BUTTONS
                if slot >= formBarStart and slot <= formBarStart + 11 then
                    isFormBarSlot = true
                end
            end
            if not isFormBarSlot then
                currentBarSlots[slot] = true
            end
        end
    end

    local foundSlot, slotInfo = SearchSlots(currentBarSlots, 1, spellID, spellName, verboseDebugMode)

    if not foundSlot and next(fallbackSlots) then
        foundSlot, slotInfo = SearchSlots(fallbackSlots, 2, spellID, spellName, verboseDebugMode)
    end
    
    if foundSlot then
        return foundSlot, slotInfo.modifiers
    end
    
    return nil, nil
end

local function AbbreviateKeybind(key)
    if not key or key == "" then return "" end

    -- PERFORMANCE: Check cache first (50+ gsub calls is very expensive)
    local cached = abbreviatedKeyCache[key]
    if cached then
        return cached
    end

    local result = key

    -- Check if this is a gamepad combo (modifier + PAD button)
    -- WoW maps gamepad triggers to keyboard modifiers: LT→SHIFT, RT→CTRL
    -- Quick pre-check: most keys don't contain "PAD", skip expensive checks for keyboard binds
    local hasGamepadButton = false
    if string.find(key, "PAD") then
        hasGamepadButton = string.find(key, "PAD%d") or string.find(key, "PADD") or
                           string.find(key, "PADLSTICK") or string.find(key, "PADRSTICK") or
                           string.find(key, "PAD[LR]SHOULDER") or string.find(key, "PAD[LR]TRIGGER") or
                           string.find(key, "PADPADDLE") or string.find(key, "PADFORWARD") or
                           string.find(key, "PADBACK") or string.find(key, "PADSYSTEM") or string.find(key, "PADSOCIAL")
    end
    local isGamepadModifierCombo = hasGamepadButton and (string.find(key, "^SHIFT%-") or string.find(key, "^CTRL%-"))
    local iconSize = isGamepadModifierCombo and "10:10" or "14:14"
    
    -- Convert keyboard modifiers to gamepad trigger icons when combined with PAD buttons
    -- LT = SHIFT, RT = CTRL (WoW's internal gamepad→keyboard mapping)
    if isGamepadModifierCombo then
        result = string_gsub(result, "^SHIFT%-", "|A:Gamepad_Gen_LTrigger_64:" .. iconSize .. "|a")
        result = string_gsub(result, "^CTRL%-", "|A:Gamepad_Gen_RTrigger_64:" .. iconSize .. "|a")
    else
        -- Regular keyboard modifiers (no gamepad button involved)
        result = string_gsub(result, "SHIFT%-", "S")
        result = string_gsub(result, "CTRL%-", "C")
    end
    result = string_gsub(result, "ALT%-", "A")

    -- PERFORMANCE: Skip all gamepad button replacements for keyboard-only binds
    -- This avoids ~40 unnecessary string.gsub calls when hasGamepadButton is false
    if hasGamepadButton then
        -- Gamepad modifier buttons as prefixes (native PADLTRIGGER- format, if WoW ever uses it)
        result = string_gsub(result, "PADLSHOULDER%-", "|A:Gamepad_Gen_LShoulder_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSHOULDER%-", "|A:Gamepad_Gen_RShoulder_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADLTRIGGER%-", "|A:Gamepad_Gen_LTrigger_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRTRIGGER%-", "|A:Gamepad_Gen_RTrigger_64:" .. iconSize .. "|a")
        -- Stick directions (must come before stick click abbreviations)
        result = string_gsub(result, "PADLSTICKUP", "|A:Gamepad_Gen_LStickUp_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADLSTICKDOWN", "|A:Gamepad_Gen_LStickDown_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADLSTICKLEFT", "|A:Gamepad_Gen_LStickLeft_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADLSTICKRIGHT", "|A:Gamepad_Gen_LStickRight_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSTICKUP", "|A:Gamepad_Gen_RStickUp_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSTICKDOWN", "|A:Gamepad_Gen_RStickDown_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSTICKLEFT", "|A:Gamepad_Gen_RStickLeft_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSTICKRIGHT", "|A:Gamepad_Gen_RStickRight_64:" .. iconSize .. "|a")
        -- Stick clicks
        result = string_gsub(result, "PADLSTICK", "|A:Gamepad_Gen_LStickIn_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSTICK", "|A:Gamepad_Gen_RStickIn_64:" .. iconSize .. "|a")
        -- D-pad (must come before arrow key abbreviations - PADDDOWN contains DOWN)
        result = string_gsub(result, "PADDUP", "|A:Gamepad_Gen_Up_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADDDOWN", "|A:Gamepad_Gen_Down_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADDLEFT", "|A:Gamepad_Gen_Left_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADDRIGHT", "|A:Gamepad_Gen_Right_64:" .. iconSize .. "|a")
        -- Shoulders and triggers (standalone, not as modifiers)
        result = string_gsub(result, "PADLSHOULDER", "|A:Gamepad_Gen_LShoulder_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRSHOULDER", "|A:Gamepad_Gen_RShoulder_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADLTRIGGER", "|A:Gamepad_Gen_LTrigger_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADRTRIGGER", "|A:Gamepad_Gen_RTrigger_64:" .. iconSize .. "|a")
        -- Paddles (must come before face buttons - PADPADDLE1 contains PAD substring)
        result = string_gsub(result, "PADPADDLE1", "|A:Gamepad_Gen_Paddle1_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADPADDLE2", "|A:Gamepad_Gen_Paddle2_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADPADDLE3", "|A:Gamepad_Gen_Paddle3_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADPADDLE4", "|A:Gamepad_Gen_Paddle4_64:" .. iconSize .. "|a")
        -- System buttons (must come before face buttons)
        result = string_gsub(result, "PADFORWARD", "|A:Gamepad_Gen_Forward_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADBACK", "|A:Gamepad_Gen_Back_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADSYSTEM", "|A:Gamepad_Gen_System_64:" .. iconSize .. "|a")
        result = string_gsub(result, "PADSOCIAL", "|A:Gamepad_Gen_Share_64:" .. iconSize .. "|a")
        -- Face buttons (style-dependent: Generic/Xbox/PlayStation)
        local faceSize = isGamepadModifierCombo and "small" or "normal"
        result = string_gsub(result, "PAD1", GetGamepadFaceButton(1, faceSize))
        result = string_gsub(result, "PAD2", GetGamepadFaceButton(2, faceSize))
        result = string_gsub(result, "PAD3", GetGamepadFaceButton(3, faceSize))
        result = string_gsub(result, "PAD4", GetGamepadFaceButton(4, faceSize))
        result = string_gsub(result, "PAD5", GetGamepadFaceButton(5, faceSize))
        result = string_gsub(result, "PAD6", GetGamepadFaceButton(6, faceSize))
    end

    -- Mouse buttons
    result = string_gsub(result, "BUTTON(%d+)", "M%1")
    result = string_gsub(result, "MOUSEWHEELUP", "MwU")
    result = string_gsub(result, "MOUSEWHEELDOWN", "MwD")
    
    -- Numpad special keys (must come before generic NUMPAD replacement)
    result = string_gsub(result, "NUMPADDIVIDE", "N/")
    result = string_gsub(result, "NUMPADMULTIPLY", "N*")
    result = string_gsub(result, "NUMPADMINUS", "N%-")
    result = string_gsub(result, "NUMPADPLUS", "N+")
    result = string_gsub(result, "NUMPADDECIMAL", "N%.")
    result = string_gsub(result, "NUMPADENTER", "NE")
    result = string_gsub(result, "NUMLOCK", "NLk")
    result = string_gsub(result, "NUMPAD", "N")  -- NUMPAD0-9 -> N0-N9

    -- Navigation keys
    result = string_gsub(result, "PAGEUP", "PU")
    result = string_gsub(result, "PAGEDOWN", "PD")
    result = string_gsub(result, "INSERT", "Ins")
    result = string_gsub(result, "DELETE", "Del")
    result = string_gsub(result, "HOME", "Hm")
    result = string_gsub(result, "END", "End")
    
    -- Arrow keys (only abbreviate if they get too long with modifiers)
    result = string_gsub(result, "UP", "Up")
    result = string_gsub(result, "DOWN", "Dn")
    result = string_gsub(result, "LEFT", "Lt")
    result = string_gsub(result, "RIGHT", "Rt")
    
    -- Function/special keys
    result = string_gsub(result, "BACKSPACE", "BS")
    result = string_gsub(result, "CAPSLOCK", "CL")
    result = string_gsub(result, "ESCAPE", "Esc")
    result = string_gsub(result, "PRINTSCREEN", "PS")
    result = string_gsub(result, "SCROLLLOCK", "SL")
    result = string_gsub(result, "PAUSE", "Pa")
    result = string_gsub(result, "SPACE", "Spc")
    result = string_gsub(result, "TAB", "Tab")
    result = string_gsub(result, "ENTER", "Ent")
    
    -- Punctuation/symbol keys (tilde, brackets, etc. - keep short)
    result = string_gsub(result, "BACKQUOTE", "`")  -- ` or ~ key
    result = string_gsub(result, "TILDE", "~")
    result = string_gsub(result, "MINUS", "%-")
    result = string_gsub(result, "EQUALS", "=")
    result = string_gsub(result, "LEFTBRACKET", "%[")
    result = string_gsub(result, "RIGHTBRACKET", "%]")
    result = string_gsub(result, "BACKSLASH", "\\")
    result = string_gsub(result, "SEMICOLON", ";")
    result = string_gsub(result, "QUOTE", "'")
    result = string_gsub(result, "COMMA", ",")
    result = string_gsub(result, "PERIOD", "%.")
    result = string_gsub(result, "SLASH", "/")

    -- PERFORMANCE: Cache the result (50+ gsub calls avoided on subsequent lookups)
    if abbreviatedKeyCacheSize < MAX_ABBREVIATED_CACHE_SIZE then
        abbreviatedKeyCache[key] = result
        abbreviatedKeyCacheSize = abbreviatedKeyCacheSize + 1
    end

    return result
end

local function FormatHotkeyWithModifiers(baseKey, macroModifiers)
    if not baseKey or baseKey == "" then
        return ""
    end
    
    if not macroModifiers or not macroModifiers.mod then
        return baseKey
    end
    
    local modType = macroModifiers.mod
    if modType == "any" or modType == "" then
        return "+" .. baseKey
    elseif modType:match("shift") then
        return "S" .. baseKey
    elseif modType:match("ctrl") then
        return "C" .. baseKey
    elseif modType:match("alt") then
        return "A" .. baseKey
    else
        return "+" .. baseKey
    end
end

function ActionBarScanner.GetSpellHotkey(spellID)
    if not spellID or spellID == 0 then
        return ""
    end

    -- User override takes priority
    local addon = GetCachedAddon()
    if addon and addon.GetHotkeyOverride then
        local override = addon:GetHotkeyOverride(spellID)
        if override and override ~= "" then
            return override
        end
    end

    -- FAST PATH: Valid cache hit - return immediately
    if not verboseDebugMode and spellHotkeyCacheValid and spellHotkeyCache[spellID] ~= nil then
        return spellHotkeyCache[spellID]
    end

    -- PERFORMANCE: If we have a cached value (even stale), return it immediately
    -- and only do expensive lookup if refresh interval has passed
    local previousValue = spellHotkeyCache[spellID]
    local now = GetTime()

    if previousValue ~= nil then
        -- We have a cached value - check if we should refresh
        if (now - lastHotkeyRefreshTime) < HOTKEY_REFRESH_INTERVAL then
            -- Too soon to refresh - return stale value (usually correct anyway)
            return previousValue
        end
        -- Mark this refresh time
        lastHotkeyRefreshTime = now
    end

    if verboseDebugMode then
        print("|JAC| GetSpellHotkey(" .. spellID .. "): cache bypass, doing fresh lookup")
    end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo or not spellInfo.name or spellInfo.name == "" then
        -- Cache empty result too
        spellHotkeyCache[spellID] = ""
        if verboseDebugMode then
            print("|JAC| GetSpellHotkey(" .. spellID .. "): no spell info, returning empty")
        end
        return previousValue or ""
    end

    local foundSlot, macroModifiers = FindSpellInActions(spellID, spellInfo.name)

    if foundSlot then
        local baseKey = GetOptimizedKeybind(foundSlot)

        if baseKey then
            local abbreviatedKey = AbbreviateKeybind(baseKey)
            local finalHotkey = FormatHotkeyWithModifiers(abbreviatedKey, macroModifiers)
            -- Cache the result and the slot for transform lookups
            spellHotkeyCache[spellID] = finalHotkey
            spellSlotCache[spellID] = foundSlot
            spellHotkeyCacheValid = true
            return finalHotkey
        end
    end
    
    -- Transform fast path: slot doesn't change, only displayed spell
    if FindBaseSpellByID then
        local baseSpellID = FindBaseSpellByID(spellID)
        if baseSpellID and baseSpellID ~= spellID then
            local cachedSlot = spellSlotCache[baseSpellID]
            if cachedSlot then
                local baseKey = GetOptimizedKeybind(cachedSlot)
                if baseKey then
                    local abbreviatedKey = AbbreviateKeybind(baseKey)
                    local finalHotkey = abbreviatedKey
                    spellHotkeyCache[spellID] = finalHotkey
                    spellSlotCache[spellID] = cachedSlot
                    spellHotkeyCacheValid = true
                    return finalHotkey
                end
            end

            local baseSpellInfo = C_Spell.GetSpellInfo(baseSpellID)
            if baseSpellInfo and baseSpellInfo.name then
                local baseFoundSlot, baseMacroModifiers = FindSpellInActions(baseSpellID, baseSpellInfo.name)
                if baseFoundSlot then
                    local baseKey = GetOptimizedKeybind(baseFoundSlot)
                    if baseKey then
                        local abbreviatedKey = AbbreviateKeybind(baseKey)
                        local finalHotkey = FormatHotkeyWithModifiers(abbreviatedKey, baseMacroModifiers)
                        spellHotkeyCache[spellID] = finalHotkey
                        spellHotkeyCache[baseSpellID] = finalHotkey
                        spellSlotCache[spellID] = baseFoundSlot
                        spellSlotCache[baseSpellID] = baseFoundSlot
                        spellHotkeyCacheValid = true
                        return finalHotkey
                    end
                end
            end
        end
    end

    spellHotkeyCache[spellID] = ""
    spellHotkeyCacheValid = true
    return previousValue or ""
end

function ActionBarScanner.FindSpellInActions(spellID, spellName)
    return FindSpellInActions(spellID, spellName)
end

function ActionBarScanner.InvalidateKeybindCache()
    InvalidateKeybindCache()
end

-- Soft invalidation: mark invalid but keep values to prevent flicker
function ActionBarScanner.InvalidateHotkeyCache()
    spellHotkeyCacheValid = false
    if next(spellHotkeyCache) then
        local count = 0
        for _ in pairs(spellHotkeyCache) do
            count = count + 1
            if count > 50 then
                wipe(spellHotkeyCache)
                break
            end
        end
    end
end

function ActionBarScanner.RebuildKeybindCache()
    InvalidateKeybindCache()
    ValidateAndBuildKeybindCache()
end

function ActionBarScanner.OnSpecialBarChanged()
    InvalidateStateCache()
end

function ActionBarScanner.OnKeybindsChanged()
    local now = GetTime()

    if isRebuildingBindings then
        return
    end

    if (now - ActionBarScanner.lastKeybindChangeTime) < 0.2 then
        return
    end

    ActionBarScanner.lastKeybindChangeTime = now
    isRebuildingBindings = true
    InvalidateBindingCache()
    InvalidateKeybindCache()
    isRebuildingBindings = false
    
    -- Gamepad bindings may not be committed when UPDATE_BINDINGS fires
    -- Schedule a delayed second refresh to catch late-committed gamepad data
    C_Timer.After(0.3, function()
        InvalidateBindingCache()
        InvalidateKeybindCache()
        -- Also invalidate UIRenderer's per-icon caches
        local UIRenderer = LibStub("JustAC-UIRenderer", true)
        if UIRenderer and UIRenderer.InvalidateHotkeyCache then
            UIRenderer.InvalidateHotkeyCache()
        end
    end)
end

function ActionBarScanner.OnUIChanged()
    InvalidateStateCache()
end

function ActionBarScanner.FindSpellInSlots(spellName)
    if not spellName or spellName == "" then
        print("|JAC| Error: No spell name provided")
        return {}
    end
    
    print("|JAC| Searching for: " .. tostring(spellName))
    
    local foundSlots = {}
    local lowerSpellName = spellName:lower()
    local slotMapping = GetCachedSlotMapping()
    
    for slot = 1, MAX_ACTION_SLOTS do
        if HasAction(slot) then
            -- Always use BlizzardAPI.GetActionInfo (no fallback to GetActionInfo)
            local actionType, actionID = BlizzardAPI.GetActionInfo(slot)
            local isValid = slotMapping[slot] ~= nil
            
            -- Skip the single-button assistant using multiple detection methods
            local isAssistantButton = (actionType == "spell" and type(actionID) == "string" and actionID == "assistedcombat")
            local isAssistedCombatAction = C_ActionBar and C_ActionBar.IsAssistedCombatAction and C_ActionBar.IsAssistedCombatAction(slot)
            
            if not isAssistantButton and not isAssistedCombatAction and actionType == "spell" and actionID then
                local spellInfo = C_Spell.GetSpellInfo(actionID)
                if spellInfo and spellInfo.name and spellInfo.name:lower():find(lowerSpellName, 1, true) then
                    local key = GetOptimizedKeybind(slot)
                    local status = isValid and "VALID" or "INVALID"
                    print("|JAC| Found: '" .. tostring(spellInfo.name) .. "' in slot " .. tostring(slot) .. " (" .. status .. ") (key: " .. tostring(key or "none") .. ")")
                    
                    table.insert(foundSlots, {
                        slot = slot,
                        spellID = actionID,
                        spellName = spellInfo.name,
                        valid = isValid
                    })
                end
            end
        end
    end
    
    if #foundSlots == 0 then
        print("|JAC| No matches found for '" .. tostring(spellName) .. "'")
    end
    
    return foundSlots
end

--------------------------------------------------------------------------------
-- Event-Driven Proc Tracking (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE)
--------------------------------------------------------------------------------

local activeProcs = {}
local activeProcsList = {}
local procListDirty = true
local defensiveProcsListDirty = true

function ActionBarScanner.OnProcShow(spellID)
    if spellID and spellID > 0 and not activeProcs[spellID] then
        activeProcs[spellID] = true
        procListDirty = true
        defensiveProcsListDirty = true

        -- Track override spell too
        local displayID = BlizzardAPI and BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID)
        if displayID and displayID ~= spellID and displayID > 0 then
            activeProcs[displayID] = true
        end
    end
end

function ActionBarScanner.OnProcHide(spellID)
    if spellID and spellID > 0 then
        local displayID = BlizzardAPI and BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID)
        
        if activeProcs[spellID] then
            activeProcs[spellID] = nil
            procListDirty = true
            defensiveProcsListDirty = true
        end
        
        if displayID and displayID ~= spellID and activeProcs[displayID] then
            activeProcs[displayID] = nil
            procListDirty = true
            defensiveProcsListDirty = true
        end
    end
end

local function RebuildProcList()
    if not procListDirty then return end
    wipe(activeProcsList)
    for spellID in pairs(activeProcs) do
        activeProcsList[#activeProcsList + 1] = spellID
    end
    procListDirty = false
end

function ActionBarScanner.GetSpellbookProccedSpells()
    RebuildProcList()
    return activeProcsList
end

function ActionBarScanner.IsSpellProcced(spellID)
    if not spellID or spellID == 0 then return false end
    if activeProcs[spellID] then return true end
    -- Proc events may fire with different ID than display ID
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI and BlizzardAPI.GetDisplaySpellID then
        local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
        if displayID and displayID ~= spellID and activeProcs[displayID] then
            return true
        end
    end
    return false
end

function ActionBarScanner.HasKeybind(spellID)
    if not spellID then return false end
    local hotkey = ActionBarScanner.GetSpellHotkey(spellID)
    return hotkey and hotkey ~= ""
end

function ActionBarScanner.ClearSpellHotkeyCache(spellID)
    if spellID then
        spellHotkeyCache[spellID] = nil
        spellSlotCache[spellID] = nil
    end
end

function ActionBarScanner.ClearAllCaches()
    wipe(spellHotkeyCache)
    wipe(spellSlotCache)
    spellHotkeyCacheValid = false
end

-- Uses cached slot from GetSpellHotkey lookups
function ActionBarScanner.GetSlotForSpell(spellID)
    if not spellID then return nil end

    local cachedSlot = spellSlotCache[spellID]
    if cachedSlot then
        return cachedSlot
    end

    -- Trigger hotkey lookup to populate cache
    local _ = ActionBarScanner.GetSpellHotkey(spellID)
    return spellSlotCache[spellID]
end

-- Returns action bar cooldown (Blizzard's ground truth for GCD vs spell CD)
function ActionBarScanner.GetActionBarCooldown(spellID)
    if not spellID then return nil, nil end

    local slot = ActionBarScanner.GetSlotForSpell(spellID)
    if not slot then return nil, nil end

    if GetActionCooldown then
        return GetActionCooldown(slot)
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- Defensive Proc Tracking (HELPFUL/SURVIVAL spells only)
--------------------------------------------------------------------------------

local defensiveProcsList = {}

-- Validates procs via API to catch stale event cache
local function RebuildDefensiveProcList()
    if not defensiveProcsListDirty then return end

    wipe(defensiveProcsList)
    local toRemove = {}

    for spellID in pairs(activeProcs) do
        local stillProcced = BlizzardAPI.IsSpellProcced and BlizzardAPI.IsSpellProcced(spellID)

        if not stillProcced then
            toRemove[#toRemove + 1] = spellID
        else
            local actualID = BlizzardAPI.GetDisplaySpellID(spellID)
            if BlizzardAPI.IsDefensiveSpell(actualID) or BlizzardAPI.IsDefensiveSpell(spellID) then
                defensiveProcsList[#defensiveProcsList + 1] = actualID
            end
        end
    end

    for _, staleID in ipairs(toRemove) do
        activeProcs[staleID] = nil
        procListDirty = true
    end

    defensiveProcsListDirty = false
end

-- Force revalidation: stale procs cause visible glow color issues
function ActionBarScanner.GetDefensiveProccedSpells()
    defensiveProcsListDirty = true
    RebuildDefensiveProcList()
    return defensiveProcsList
end
