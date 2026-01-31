-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Action Bar Scanner Module - Caches action bar slots and keybind mappings
local ActionBarScanner = LibStub:NewLibrary("JustAC-ActionBarScanner", 30)
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
    bindingCacheValid = true
end

local function GetCachedBindingKey(bindingKey)
    if not bindingCacheValid then
        RebuildBindingCache()
    end
    return bindingKeyCache[bindingKey] or ""
end

local function CalculateKeybindHash()
    if not bindingCacheValid then
        RebuildBindingCache()
    end
    
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
    
    return hash
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

    local result = key

    -- Modifiers
    result = string_gsub(result, "SHIFT%-", "S")
    result = string_gsub(result, "CTRL%-", "C")
    result = string_gsub(result, "ALT%-", "A")

    -- Common keys
    result = string_gsub(result, "BUTTON(%d+)", "M%1")
    result = string_gsub(result, "MOUSEWHEELUP", "MwU")
    result = string_gsub(result, "MOUSEWHEELDOWN", "MwD")
    result = string_gsub(result, "NUMPAD", "N")  -- NUMPAD1 -> N1, NUMPAD0 -> N0
    result = string_gsub(result, "PAGEUP", "PgU")
    result = string_gsub(result, "PAGEDOWN", "PgD")
    result = string_gsub(result, "INSERT", "Ins")
    result = string_gsub(result, "DELETE", "Del")
    result = string_gsub(result, "HOME", "Hm")
    result = string_gsub(result, "END", "End")
    result = string_gsub(result, "BACKSPACE", "BkSp")
    result = string_gsub(result, "CAPSLOCK", "Caps")
    result = string_gsub(result, "ESCAPE", "Esc")
    result = string_gsub(result, "PRINTSCREEN", "PrtSc")
    result = string_gsub(result, "SCROLLLOCK", "ScrLk")
    result = string_gsub(result, "SPACE", "Spc")
    
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

    if not verboseDebugMode and spellHotkeyCacheValid and spellHotkeyCache[spellID] ~= nil then
        return spellHotkeyCache[spellID]
    end

    -- Return stale value during refresh to prevent flicker
    local previousValue = spellHotkeyCache[spellID]
    
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