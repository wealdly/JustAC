-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Form Cache Module - Tracks current shapeshift form and available forms
local FormCache = LibStub:NewLibrary("JustAC-FormCache", 11)
if not FormCache then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Hot path cache
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs

local cachedFormData = {
    -- Stance bar position (1-N) matching macro [form:X] conditionals (0 = caster/no form)
    currentStanceIndex = 0,
    currentFormName = "",
    availableForms = {},
    spellToFormMap = {},
    lastUpdate = 0,
    lastFullScan = 0,
}

local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

local function GetModernSpellTabInfo(tabIndex)
    if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tabIndex)
        if skillLineInfo then
            return skillLineInfo.name, skillLineInfo.iconID, skillLineInfo.itemIndexOffset, skillLineInfo.numSpellBookItems
        end
    elseif GetSpellTabInfo then
        return GetSpellTabInfo(tabIndex)
    end
    return nil
end

local function GetModernNumSpellTabs()
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        return C_SpellBook.GetNumSpellBookSkillLines()
    elseif GetNumSpellTabs then
        return GetNumSpellTabs()
    end
    return 0
end

local function GetModernSpellBookItemInfo(spellIndex)
    if C_SpellBook and C_SpellBook.GetSpellBookItemType and Enum and Enum.SpellBookSpellBank then
        local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(spellIndex, Enum.SpellBookSpellBank.Player)
        local typeString = nil
        if itemType == Enum.SpellBookItemType.Spell then
            typeString = "SPELL"
        elseif itemType == Enum.SpellBookItemType.Flyout then
            typeString = "FLYOUT"
        elseif itemType == Enum.SpellBookItemType.FutureSpell then
            typeString = "FUTURESPELL"
        elseif itemType == Enum.SpellBookItemType.PetAction then
            typeString = "PETACTION"
        end
        return typeString, spellID or actionID
    elseif GetSpellBookItemInfo then
        return GetSpellBookItemInfo(spellIndex, BOOKTYPE_SPELL)
    end
    return nil, nil
end


local function ScanSpellbookForFormSpells()
    local formSpells = {}
    
    local numTabs = GetModernNumSpellTabs()
    for tabIndex = 1, numTabs do
        local name, texture, offset, numSpells = GetModernSpellTabInfo(tabIndex)
        
        if name and offset and numSpells then
            for spellIndex = offset + 1, offset + numSpells do
                local spellType, spellID = GetModernSpellBookItemInfo(spellIndex)
                
                if (spellType == "SPELL" or spellType == 1) and spellID then
                    local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
                    if spellInfo and spellInfo.name then
                        local spellName = spellInfo.name
                        
                        local formPatterns = {
                            "Form$", "Stance$", "Presence$", "Aspect$", "Aura$"
                        }
                        
                        local isFormSpell = false
                        for _, pattern in ipairs(formPatterns) do
                            if spellName:match(pattern) then
                                isFormSpell = true
                                break
                            end
                        end
                        
                        if not isFormSpell then
                            local numForms = BlizzardAPI.GetNumShapeshiftForms()
                            for i = 1, numForms do
                                local icon, active, castable, formSpellID = BlizzardAPI.GetShapeshiftFormInfo(i)
                                if formSpellID and formSpellID == spellID then
                                    isFormSpell = true
                                    break
                                end
                            end
                        end
                        
                        if isFormSpell then
                            formSpells[spellID] = spellName
                        end
                    end
                end
            end
        end
    end
    
    return formSpells
end

local function DetermineSpellFormTarget(spellID, spellName)
    local numForms = BlizzardAPI.GetNumShapeshiftForms()
    for i = 1, numForms do
        local icon, active, castable, formSpellID = BlizzardAPI.GetShapeshiftFormInfo(i)
        if formSpellID and formSpellID == spellID then
            return i
        end
    end
    
    local cancelPatterns = {
        "Cancel", "Normal Form", "Caster Form", "Humanoid Form"
    }
    
    for _, pattern in ipairs(cancelPatterns) do
        if spellName:find(pattern) then
            return 0
        end
    end
    
    return nil
end

local function BuildSpellToFormMapping()
    local currentTime = GetTime()
    
    if cachedFormData.lastFullScan > 0 and (currentTime - cachedFormData.lastFullScan) < 30 then
        return cachedFormData.spellToFormMap
    end
    
    local mapping = {}
    local formSpells = ScanSpellbookForFormSpells()
    
    for spellID, spellName in pairs(formSpells) do
        local targetForm = DetermineSpellFormTarget(spellID, spellName)
        if targetForm then
            mapping[spellID] = targetForm
        end
    end
    
    cachedFormData.spellToFormMap = mapping
    cachedFormData.lastFullScan = currentTime
    
    return mapping
end

-- GetShapeshiftForm() returns nil during loading; iteration is always reliable
local function FindActiveStanceIndex(numForms)
    for i = 1, numForms do
        local icon, active, castable, spellID = BlizzardAPI.GetShapeshiftFormInfo(i)
        if active and active ~= 0 then
            return i
        end
    end
    return 0  -- No active form = caster form
end

local function UpdateFormCache()
    local currentTime = GetTime()
    
    if (currentTime - cachedFormData.lastUpdate) < 0.1 then
        return
    end
    
    local numForms = BlizzardAPI.GetNumShapeshiftForms()
    
    local stanceIndex = FindActiveStanceIndex(numForms)
    
    local formName = ""
    if stanceIndex > 0 and stanceIndex <= numForms then
        local icon, active, castable, spellID = BlizzardAPI.GetShapeshiftFormInfo(stanceIndex)
        if spellID then
            local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                formName = spellInfo.name
            end
        end
        
        if formName == "" then
            formName = "Form " .. stanceIndex
        end
    else
        local playerClass = select(2, UnitClass("player")) or "UNKNOWN"
        if playerClass == "DRUID" then
            formName = "Caster Form"
        elseif playerClass == "WARRIOR" then
            formName = "Normal Stance"
        elseif playerClass == "DEATHKNIGHT" then
            formName = "Normal Presence"
        else
            formName = "Normal Form"
        end
    end
    
    local availableForms = {}
    
    availableForms[0] = {
        id = 0,
        name = formName,
        available = true,
        current = (stanceIndex == 0),
        spellID = nil
    }
    
    for i = 1, numForms do
        local icon, active, castable, spellID = BlizzardAPI.GetShapeshiftFormInfo(i)
        if icon and spellID then
            local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or ("Form " .. i)
            
            availableForms[i] = {
                id = i,
                name = name,
                icon = icon,
                available = active ~= nil,
                current = (stanceIndex == i),
                spellID = spellID
            }
        end
    end
    
    local formChanged = cachedFormData.currentStanceIndex ~= stanceIndex
    cachedFormData.currentStanceIndex = stanceIndex
    cachedFormData.currentFormName = formName
    cachedFormData.availableForms = availableForms
    cachedFormData.lastUpdate = currentTime
    
    if formChanged or (currentTime - cachedFormData.lastFullScan) > 30 then
        BuildSpellToFormMapping()
    end
end

function FormCache.GetActiveForm()
    UpdateFormCache()
    return cachedFormData.currentStanceIndex
end

function FormCache.GetActiveFormName()
    UpdateFormCache()
    return cachedFormData.currentFormName
end

function FormCache.InvalidateCache()
    cachedFormData.lastUpdate = 0
end

function FormCache.InvalidateSpellMapping()
    cachedFormData.lastFullScan = 0
    wipe(cachedFormData.spellToFormMap)
end

function FormCache.OnPlayerLogin()
    FormCache.InvalidateCache()
    FormCache.InvalidateSpellMapping()
    
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if addon and addon.ScheduleTimer then
        addon:ScheduleTimer(function()
            UpdateFormCache()
        end, 1.0)
    else
        UpdateFormCache()
    end
end

function FormCache.GetFormIDBySpellID(spellID)
    if not spellID then return nil end
    
    UpdateFormCache()
    
    local mapping = cachedFormData.spellToFormMap
    if mapping[spellID] then
        return mapping[spellID]
    end
    
    for formID, formData in pairs(cachedFormData.availableForms) do
        if formData.spellID and formData.spellID == spellID then
            return formID
        end
    end
    
    -- Rotation may return base ID while stance bar uses override spell
    if C_Spell and C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID ~= spellID then
            if mapping[overrideID] then
                mapping[spellID] = mapping[overrideID]
                return mapping[overrideID]
            end
            for formID, formData in pairs(cachedFormData.availableForms) do
                if formData.spellID and formData.spellID == overrideID then
                    mapping[spellID] = formID
                    return formID
                end
            end
        end
    end
    
    -- Fallback: match by name when rotation uses different spell ID for same form
    local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
    if spellInfo and spellInfo.name then
        local spellName = spellInfo.name
        for formID, formData in pairs(cachedFormData.availableForms) do
            if formData.name and formData.name == spellName then
                mapping[spellID] = formID
                return formID
            end
        end
    end
    
    BuildSpellToFormMapping()
    mapping = cachedFormData.spellToFormMap
    return mapping[spellID]
end

