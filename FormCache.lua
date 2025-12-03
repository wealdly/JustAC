-- JustAC: Form Cache Module
-- Note: "Form" in macro conditionals uses stance bar index (1-N), NOT constant form IDs
-- We use GetShapeshiftFormInfo iteration (reliable) rather than GetShapeshiftForm (unreliable during loading)
local FormCache = LibStub:NewLibrary("JustAC-FormCache", 10)
if not FormCache then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local wipe = wipe

local cachedFormData = {
    -- currentStanceIndex: The stance bar position (1-N), matches macro [form:X] conditionals
    -- 0 = caster/no form, 1 = first form on bar, 2 = second, etc.
    currentStanceIndex = 0,
    currentFormName = "",
    availableForms = {},
    spellToFormMap = {},
    lastUpdate = 0,
    lastFullScan = 0,
    valid = false,
}

local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

-- Safe wrapper for C_Spell.GetSpellInfo
local function SafeGetSpellInfo(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellInfo then return nil end
    local ok, result = pcall(C_Spell.GetSpellInfo, spellID)
    return ok and result or nil
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
        -- Returns: itemType (Enum.SpellBookItemType), actionID, spellID
        local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(spellIndex, Enum.SpellBookSpellBank.Player)
        -- Convert enum to string for compatibility, use spellID (3rd return)
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
        -- Use spellID if available, fall back to actionID
        return typeString, spellID or actionID
    elseif GetSpellBookItemInfo then
        return GetSpellBookItemInfo(spellIndex, BOOKTYPE_SPELL)
    end
    return nil, nil
end

local function SafeGetNumShapeshiftForms()
    local ok, result = pcall(GetNumShapeshiftForms)
    return ok and result or 0
end

local function SafeGetShapeshiftFormInfo(index)
    local ok, icon, active, castable, spellID = pcall(GetShapeshiftFormInfo, index)
    if ok then
        return icon, active, castable, spellID
    end
    return nil, nil, nil, nil
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
                    local spellInfo = SafeGetSpellInfo(spellID)
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
                            local numForms = SafeGetNumShapeshiftForms()
                            for i = 1, numForms do
                                local icon, active, castable, formSpellID = SafeGetShapeshiftFormInfo(i)
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
    local numForms = SafeGetNumShapeshiftForms()
    for i = 1, numForms do
        local icon, active, castable, formSpellID = SafeGetShapeshiftFormInfo(i)
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

-- Find active form by iterating GetShapeshiftFormInfo
-- Always reliable, unlike GetShapeshiftForm() which returns nil during loading
local function FindActiveStanceIndex(numForms)
    for i = 1, numForms do
        local icon, active, castable, spellID = SafeGetShapeshiftFormInfo(i)
        if active and active ~= 0 then
            return i
        end
    end
    return 0  -- No active form = caster form
end

local function UpdateFormCache()
    local currentTime = GetTime()
    
    if cachedFormData.valid and (currentTime - cachedFormData.lastUpdate) < 0.1 then
        return
    end
    
    local numForms = SafeGetNumShapeshiftForms()
    
    -- Use iteration approach - always reliable, even during loading
    -- GetShapeshiftForm() can return nil before UPDATE_SHAPESHIFT_FORMS fires
    local stanceIndex = FindActiveStanceIndex(numForms)
    
    local formName = ""
    if stanceIndex > 0 and stanceIndex <= numForms then
        local icon, active, castable, spellID = SafeGetShapeshiftFormInfo(stanceIndex)
        if spellID then
            local spellInfo = SafeGetSpellInfo(spellID)
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
        local icon, active, castable, spellID = SafeGetShapeshiftFormInfo(i)
        if icon and spellID then
            local spellInfo = SafeGetSpellInfo(spellID)
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
    cachedFormData.valid = true
    
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

function FormCache.GetFormInfo(formID)
    UpdateFormCache()
    if formID == nil then
        return {
            id = cachedFormData.currentStanceIndex,
            name = cachedFormData.currentFormName,
            current = true
        }
    end
    return cachedFormData.availableForms[formID]
end

function FormCache.GetAvailableForms()
    UpdateFormCache()
    local forms = {}
    for formID, formData in pairs(cachedFormData.availableForms) do
        forms[#forms + 1] = formData
    end
    table.sort(forms, function(a, b) return a.id < b.id end)
    return forms
end

function FormCache.InvalidateCache()
    cachedFormData.valid = false
    cachedFormData.lastUpdate = 0
end

function FormCache.InvalidateSpellMapping()
    cachedFormData.lastFullScan = 0
    wipe(cachedFormData.spellToFormMap)
end

function FormCache.OnFormChanged()
    FormCache.InvalidateCache()
    UpdateFormCache()
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

function FormCache.OnSpellsChanged()
    FormCache.InvalidateSpellMapping()
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
    
    BuildSpellToFormMapping()
    mapping = cachedFormData.spellToFormMap
    return mapping[spellID]
end

function FormCache.ShowFormDebugInfo()
    UpdateFormCache()
    local playerClass = select(2, UnitClass("player")) or "UNKNOWN"
    
    print("|JAC| === Form Debug Information ===")
    print("|JAC| Player Class: " .. playerClass)
    print("|JAC| Current Form: " .. cachedFormData.currentFormName .. " (Stance Index: " .. cachedFormData.currentStanceIndex .. ")")
    print("|JAC| Note: Stance Index matches macro [form:X] conditional")
    print("|JAC| Available Forms:")
    
    local availableForms = FormCache.GetAvailableForms()
    for _, formData in ipairs(availableForms) do
        local status = formData.current and " (CURRENT)" or ""
        local available = formData.available and "✓" or "✗"
        local spellInfo = formData.spellID and (" spellID:" .. formData.spellID) or " (no spell)"
        print("|JAC|   [" .. available .. "] " .. formData.name .. " (Index: " .. formData.id .. ")" .. spellInfo .. status)
    end
    
    print("|JAC| Spell-to-Form Mapping:")
    local mapping = cachedFormData.spellToFormMap
    local count = 0
    for spellID, formIndex in pairs(mapping) do
        local spellInfo = SafeGetSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        print("|JAC|   " .. spellName .. " (" .. spellID .. ") -> stance index " .. formIndex)
        count = count + 1
    end
    
    if count == 0 then
        print("|JAC|   (No mapped spells)")
    end
    
    print("|JAC| ===========================")
end