-- JustAC: Action Bar Scanner Module
local ActionBarScanner = LibStub:NewLibrary("JustAC-ActionBarScanner", 12)
if not ActionBarScanner then return end
ActionBarScanner.lastKeybindChangeTime = 0

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local MacroParser = LibStub("JustAC-MacroParser", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local HasAction = HasAction
local GetBindingKey = GetBindingKey
local C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local C_Spell_GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local math_max = math.max
local math_min = math.min
local string_byte = string.byte
local string_gsub = string.gsub

-- Cached addon reference for hot path (resolved lazily)
local cachedAddon = nil
local function GetCachedAddon()
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedAddon
end

local NUM_ACTIONBAR_BUTTONS = 12
local MAX_ACTION_SLOTS = 200

-- Caches with different invalidation triggers
local bindingKeyCache = {}
local bindingCacheValid = false
local slotMappingCache = {}
local slotMappingCacheKey = 0
local keybindCache = {}
local keybindCacheValid = false
local lastValidatedStateHash = 0
local isRebuildingBindings = false

-- Spell-to-hotkey result cache (invalidated with keybind cache)
local spellHotkeyCache = {}
local spellHotkeyCacheValid = false

-- Abbreviated keybind cache (reduces string operations)
local abbreviatedKeybindCache = {}

-- Cached state data
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

local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

local function GetProfile()
    return BlizzardAPI and BlizzardAPI.GetProfile() or nil
end

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
    local combinedHash = newKeybindHash * 10000000

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
    wipe(abbreviatedKeybindCache)
end

local function InvalidateBindingCache()
    bindingCacheValid = false
    wipe(bindingKeyCache)
    spellHotkeyCacheValid = false
    wipe(spellHotkeyCache)
    wipe(abbreviatedKeybindCache)
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
            -- Skip empty slots (continue pattern via early check)
        else
            local actionType, id, subType, macroSpellID = BlizzardAPI.GetActionInfo(slot)

            -- Skip invalid or Assisted Combat slots
            if not actionType then
                -- No action type, skip
            elseif actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
                -- Skip Assisted Combat placeholder
            elseif C_ActionBar and C_ActionBar.IsAssistedCombatAction and C_ActionBar.IsAssistedCombatAction(slot) then
                -- Skip Assisted Combat action slots
            else
                -- Valid action slot - process it
                local slotKeybind = GetOptimizedKeybind(slot)
                local hasHotkey = slotKeybind ~= nil and slotKeybind ~= ""
                
                if actionType == "spell" then
                    local isMatch = (id == spellID)
                    
                    -- Check override: slot has base spell that transforms to target spell
                    if not isMatch and id and id ~= spellID then
                        local slotSpellOverride = C_Spell_GetOverrideSpell and C_Spell_GetOverrideSpell(id)
                        if slotSpellOverride and slotSpellOverride == spellID then
                            isMatch = true
                        end
                    end
                    
                    -- Check reverse: target spell transforms to slot's spell
                    if not isMatch then
                        local targetOverride = C_Spell_GetOverrideSpell and C_Spell_GetOverrideSpell(spellID)
                        if targetOverride and targetOverride ~= 0 and targetOverride ~= spellID and id == targetOverride then
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
                            local formMatch = true
                            if parsedEntry.forms then
                                formMatch = false
                                local currentFormID = (FormCache and FormCache.GetActiveForm) and FormCache.GetActiveForm() or 0
                                for _, formID in ipairs(parsedEntry.forms) do
                                    if formID == currentFormID then
                                        formMatch = true
                                        break
                                    end
                                end
                            end

                            if formMatch then
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
    
    local prioritySlots = {}
    local stanceSlots = {}
    
    if bonusOffset > 0 then
        local formBarStart = 1 + (6 + bonusOffset - 1) * NUM_ACTIONBAR_BUTTONS
        for i = formBarStart, formBarStart + 11 do
            if slotMapping[i] then
                prioritySlots[i] = true
            end
        end
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            if slotMapping[i] then
                stanceSlots[i] = true
            end
        end
    else
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            if slotMapping[i] then
                prioritySlots[i] = true
            end
        end
    end
    
    for slot in pairs(slotMapping) do
        if slot > NUM_ACTIONBAR_BUTTONS and (bonusOffset == 0 or slot < 73 or slot > 84) then
            prioritySlots[slot] = true
        end
    end
    
    local foundSlot, slotInfo = SearchSlots(prioritySlots, 1, spellID, spellName, GetDebugMode())
    
    if not foundSlot and next(stanceSlots) then
        foundSlot, slotInfo = SearchSlots(stanceSlots, 2, spellID, spellName, GetDebugMode())
    end
    
    if foundSlot then
        return foundSlot, slotInfo.modifiers
    end
    
    return nil, nil
end

-- Note: abbreviatedKeybindCache is declared at module level (line 51)
-- to ensure InvalidateKeybindCache() properly clears it

local function AbbreviateKeybind(key)
    if not key or key == "" then return "" end
    
    -- Check cache first (hot path)
    local cached = abbreviatedKeybindCache[key]
    if cached then return cached end
    
    -- Do the gsub chain once and cache result
    local result = key
    result = string_gsub(result, "SHIFT%-", "S")
    result = string_gsub(result, "CTRL%-", "C")
    result = string_gsub(result, "ALT%-", "A")
    
    abbreviatedKeybindCache[key] = result
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

    -- Return cached value first (most common path)
    if spellHotkeyCacheValid and spellHotkeyCache[spellID] ~= nil then
        -- Check for user override (rare - only if user set one)
        local addon = GetCachedAddon()
        if addon and addon.GetHotkeyOverride then
            local override = addon:GetHotkeyOverride(spellID)
            if override and override ~= "" then
                return override
            end
        end
        return spellHotkeyCache[spellID]
    end
    
    -- Cache invalid but we have a previous value - return it while we update
    -- This prevents flicker during cache refresh
    local previousValue = spellHotkeyCache[spellID]

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo or not spellInfo.name or spellInfo.name == "" then
        -- Cache empty result too
        spellHotkeyCache[spellID] = ""
        return previousValue or ""
    end

    local foundSlot, macroModifiers = FindSpellInActions(spellID, spellInfo.name)

    if foundSlot then
        local baseKey = GetOptimizedKeybind(foundSlot)

        if baseKey then
            local abbreviatedKey = AbbreviateKeybind(baseKey)
            local finalHotkey = FormatHotkeyWithModifiers(abbreviatedKey, macroModifiers)
            -- Cache the result
            spellHotkeyCache[spellID] = finalHotkey
            spellHotkeyCacheValid = true
            return finalHotkey
        end
    end

    -- Cache empty result to avoid repeated lookups
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

-- Invalidate just the spell hotkey cache (for spell override changes like Metamorphosis)
-- Throttled version that preserves cache stability during combat
function ActionBarScanner.InvalidateHotkeyCache()
    -- Don't fully wipe - just mark invalid so next lookup refreshes
    -- This prevents flicker since cached values are still used until replaced
    spellHotkeyCacheValid = false
    -- Only wipe if cache is getting stale (more than 50 entries)
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