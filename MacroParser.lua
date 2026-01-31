-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Macro Parser Module - Resolves macro conditionals to find actionable spells
local MacroParser = LibStub:NewLibrary("JustAC-MacroParser", 21)
if not MacroParser then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- Cache frequently used functions to reduce table lookups on every update
local type = type
local tonumber = tonumber
local string_lower = string.lower
local string_match = string.match
local string_find = string.find
local string_gmatch = string.gmatch
local string_sub = string.sub
local table_insert = table.insert

local UnitAffectingCombat = UnitAffectingCombat
local IsStealthed = IsStealthed
local IsSpellKnown = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell

local parsedMacroCache = {}
local spellOverrideCache = {}
local lastCacheFlush = 0
local CACHE_FLUSH_INTERVAL = 30
local lastPrintTime = {}
local DEBUG_THROTTLE_INTERVAL = 5

-- Verbose debug mode (for /jac find, /jac macrotest)
local verboseDebugMode = false

function MacroParser.SetVerboseDebug(enabled)
    verboseDebugMode = enabled
end

local function GetLowercase(str)
    return str and string_lower(str) or ""
end

local function GetDebugMode()
    return verboseDebugMode
end

local function SafeGetOverrideSpell(spellID)
    if not spellID or not C_Spell or not C_Spell.GetOverrideSpell then return nil end
    local ok, result = pcall(C_Spell.GetOverrideSpell, spellID)
    if ok and result and result ~= 0 and result ~= spellID then
        return result
    end
    return nil
end

local function SafeGetSpecialization()
    if not GetSpecialization then return 0 end
    local ok, result = pcall(GetSpecialization)
    return ok and result or 0
end

local function SafeGetActionText(slot)
    if not slot or not GetActionText then return nil end
    local ok, result = pcall(GetActionText, slot)
    return ok and result or nil
end

local function IsInCombat()
    return UnitAffectingCombat and UnitAffectingCombat("player") or false
end

local function IsInStealth()
    return IsStealthed and IsStealthed() or false
end

local function IsSpellKnownByIdentifier(identifier)
    if not identifier or identifier == "" then return false end
    
    local spellID = tonumber(identifier)
    if spellID then
        if BlizzardAPI and BlizzardAPI.IsSpellAvailable then
            return BlizzardAPI.IsSpellAvailable(spellID)
        elseif IsSpellKnown then
            return IsSpellKnown(spellID) or (IsPlayerSpell and IsPlayerSpell(spellID)) or false
        end
    else
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, spellInfo = pcall(C_Spell.GetSpellInfo, identifier)
            if ok and spellInfo and spellInfo.spellID then
                local sid = spellInfo.spellID
                if BlizzardAPI and BlizzardAPI.IsSpellAvailable then
                    return BlizzardAPI.IsSpellAvailable(sid)
                elseif IsSpellKnown then
                    return IsSpellKnown(sid) or (IsPlayerSpell and IsPlayerSpell(sid)) or false
                end
            end
        end
    end
    
    return false
end

local function SafeGetMacroInfo(macroName)
    if not macroName or not GetMacroInfo then return nil, nil, nil end
    local ok, name, icon, body = pcall(GetMacroInfo, macroName)
    if ok then
        return name, icon, body
    end
    return nil, nil, nil
end

function MacroParser.InvalidateMacroCache()
    wipe(parsedMacroCache)
    wipe(spellOverrideCache)
    lastCacheFlush = GetTime()
end

local function GetSpellAndOverride(spellID, spellName)
    local currentTime = GetTime()

    if currentTime - lastCacheFlush > CACHE_FLUSH_INTERVAL then
        wipe(spellOverrideCache)
        lastCacheFlush = currentTime
    end
    
    if spellOverrideCache[spellID] then
        return spellOverrideCache[spellID]
    end

    local spells = {}
    if spellID and spellID > 0 then
        spells[spellID] = spellName
    end

    local overrideSpellID = SafeGetOverrideSpell(spellID)
    if overrideSpellID and BlizzardAPI then
        local overrideSpellInfo = BlizzardAPI.GetSpellInfo(overrideSpellID)
        if overrideSpellInfo and overrideSpellInfo.name then
            spells[overrideSpellID] = overrideSpellInfo.name
        end
    end

    spellOverrideCache[spellID] = spells
    return spells
end

local function DoesSpellMatch(spellPart, targetSpells)
    if not spellPart or spellPart == "" then return false end
    
    local lowerSpellPart = GetLowercase(spellPart)
    
    -- Strip target specifiers (@mouseover, @player, etc.) and trailing markers
    local cleanSpellPart = lowerSpellPart:gsub("%s*@[%w]+%s*$", ""):gsub("%s*%(@[%w]+%)%s*$", "")
    cleanSpellPart = cleanSpellPart:gsub("%s*%(.-%)%s*$", "")
    cleanSpellPart = cleanSpellPart:match("^%s*(.-)%s*$") or cleanSpellPart
    
    for spellID, spellName in pairs(targetSpells) do
        local lowerSpellName = GetLowercase(spellName)
        if cleanSpellPart == lowerSpellName then
            return true, spellID, spellName
        end
        if lowerSpellPart == lowerSpellName then
            return true, spellID, spellName
        end
    end
    
    return false
end

local function AnalyzeMacroExecutionFlow(macroBody, targetSpells, debugMode)
    local lineNumber = 0
    local globalExecutionOrder = 0
    
    for line in string_gmatch(macroBody, "[^\r\n]+") do
        lineNumber = lineNumber + 1
        local lowerLine = GetLowercase(line)
        
        if not string_match(lowerLine, "^%s*#") and not string_match(lowerLine, "^%s*$") and not string_match(lowerLine, "^%s*/stopcasting") then
            local command = string_match(lowerLine, "/use%s+(.+)") or 
                           string_match(lowerLine, "/cast%s+(.+)") or
                           string_match(lowerLine, "/castsequence%s+(.+)")
            
            if command then
                globalExecutionOrder = globalExecutionOrder + 1
                local simultaneousAbilities = {}
                local targetSpellFound = false
                local targetSpellPosition = 0
                local clausePosition = 0
                
                for spellEntry in string_gmatch(command, "[^;]+") do
                    clausePosition = clausePosition + 1
                    local trimmedEntry = spellEntry:match("^%s*(.-)%s*$")
                    
                    local spellPart = trimmedEntry
                    if trimmedEntry:match("^%[") then
                        local lastBracketPos = 0
                        for i = 1, #trimmedEntry do
                            if trimmedEntry:sub(i, i) == "]" then
                                lastBracketPos = i
                            end
                        end
                        
                        if lastBracketPos > 0 then
                            spellPart = trimmedEntry:sub(lastBracketPos + 1):match("^%s*(.-)%s*$") or ""
                        end
                    end
                    
                    if spellPart and spellPart ~= "" then
                        table.insert(simultaneousAbilities, spellPart)
                        
                        local isMatch = DoesSpellMatch(spellPart, targetSpells)
                        if isMatch then
                            targetSpellFound = true
                            targetSpellPosition = clausePosition
                        end
                    end
                end
                
                if targetSpellFound then
                    return {
                        order = globalExecutionOrder,
                        lineNumber = lineNumber,
                        positionInLine = targetSpellPosition,
                        totalInLine = #simultaneousAbilities,
                        simultaneousAbilities = simultaneousAbilities
                    }
                end
            end
        end
    end
    
    return nil
end

local function CalculateMacroSpecificityScore(macroName, macroBody, targetSpells, debugMode)
    local score = 500
    local lowerMacroName = GetLowercase(macroName)

    for spellID, spellName in pairs(targetSpells) do
        local lowerSpellName = GetLowercase(spellName)
        if lowerMacroName == lowerSpellName then
            score = score + 200
            break
        elseif string_find(lowerMacroName, string_sub(lowerSpellName, 1, 2)) then
            score = score + 150
            break
        end
    end
    
    local executionInfo = AnalyzeMacroExecutionFlow(macroBody, targetSpells, debugMode)
    
    if executionInfo then
        local penalty = 0
        
        if executionInfo.order > 1 then
            penalty = penalty + (executionInfo.order - 1) * 150
        end
        
        if executionInfo.positionInLine > 1 then
            penalty = penalty + (executionInfo.positionInLine - 1) * 75
        end
        
        if executionInfo.totalInLine > 2 then
            penalty = penalty + (executionInfo.totalInLine - 2) * 25
        end
        
        local targetSpellInMacro = false
        local isConditionalMatch = false
        local conditionCount = 0
        
        for spellID, spellName in pairs(targetSpells) do
            local lowerSpellName = GetLowercase(spellName)
            
            for line in string_gmatch(macroBody, "[^\r\n]+") do
                local lowerLine = GetLowercase(line)
                if string_find(lowerLine, lowerSpellName, 1, true) then
                    targetSpellInMacro = true
                    
                    local lineConditions = 0
                    for condition in string_gmatch(lowerLine, "%[[^%]]*%]") do
                        lineConditions = lineConditions + 1
                    end
                    conditionCount = conditionCount + lineConditions
                    
                    local spellsOnLine = {}
                    for spellMatch in string_gmatch(lowerLine, "/use[^;]*") do
                        local spellList = string_match(spellMatch, "/use%s+(.+)")
                        if spellList then
                            for spell in string_gmatch(spellList, "[^;]+") do
                                table_insert(spellsOnLine, spell)
                            end
                        end
                    end
                    
                    if #spellsOnLine > 1 then
                        local isFirstSpell = false
                        if spellsOnLine[1] and string_find(spellsOnLine[1], lowerSpellName, 1, true) then
                            isFirstSpell = true
                        end
                        
                        if not isFirstSpell then
                            penalty = penalty + 100
                        end
                    end
                    
                    break
                end
            end
        end
        
        if conditionCount > 0 then
            score = score + (conditionCount * 50)
        end
        
        score = score - penalty

        local now = GetTime()
        local throttleKey = "spec_" .. macroName
        if debugMode and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > DEBUG_THROTTLE_INTERVAL) then
            lastPrintTime[throttleKey] = now
            print("|JAC| Macro '" .. macroName .. "' specificity: score=" .. score .. ", penalty=" .. penalty .. ", conditions=" .. conditionCount)
        end
    end
    
    return score
end

local function EvaluateConditions(conditionString, currentSpec, currentForm)
    local modifiers = {}
    local allConditionsMet = true
    local formMatched = false
    local requiresModifier = false

    if not conditionString or conditionString == "" then
        return true, modifiers, false, false
    end

    for condition in conditionString:gmatch("[^,]+") do
        local trimmed = condition:match("^%s*(.-)%s*$")

        if trimmed:match("^mod") then
            local modType = trimmed:match("^mod:?(.*)") or "any"
            if modType == "" then modType = "any" end
            modifiers.mod = modType
            requiresModifier = true  -- Mark clause as modifier-dependent for keybind detection

        elseif trimmed:match("^nomod") then
            modifiers.nomod = true  -- No-modifier clause = what we want for default keybind

        elseif trimmed:match("^nospec") then
            local specList = trimmed:match("nospec:([%d/]+)")
            if specList then
                for specStr in specList:gmatch("([^/]+)") do
                    local reqSpec = tonumber(specStr)
                    if reqSpec and currentSpec == reqSpec then
                        allConditionsMet = false
                        break
                    end
                end
            end
            if not allConditionsMet then break end

        elseif trimmed:match("^spec") then
            local match = false
            local specList = trimmed:match("spec:([%d/]+)")
            if specList then
                for specStr in specList:gmatch("([^/]+)") do
                    local reqSpec = tonumber(specStr)
                    if reqSpec and currentSpec == reqSpec then
                        match = true
                        break
                    end
                end
            end
            if not match then allConditionsMet = false; break end

        elseif trimmed:match("^noform") then
            local formList = trimmed:match("noform:([%d/]+)")
            if formList then
                for formStr in formList:gmatch("([^/]+)") do
                    local reqForm = tonumber(formStr)
                    if reqForm and currentForm == reqForm then
                        allConditionsMet = false
                        break
                    end
                end
            end
            if not allConditionsMet then break end

        elseif trimmed:match("^form") then
            local match = false
            local formList = trimmed:match("form:([%d/]+)")
            if formList then
                for formStr in formList:gmatch("([^/]+)") do
                    local reqForm = tonumber(formStr)
                    if reqForm and currentForm == reqForm then
                        match = true
                        formMatched = true
                        break
                    end
                end
            end
            if not match then allConditionsMet = false; break end

        elseif trimmed:match("^known") then
            local spellIdentifier = trimmed:match("known:(.+)")
            if spellIdentifier and not IsSpellKnownByIdentifier(spellIdentifier) then
                allConditionsMet = false
                break
            end

        elseif trimmed:match("^combat") then
            if not IsInCombat() then
                allConditionsMet = false
                break
            end

        elseif trimmed:match("^nocombat") then
            if IsInCombat() then
                allConditionsMet = false
                break
            end

        elseif trimmed:match("^stealth") then
            if not IsInStealth() then
                allConditionsMet = false
                break
            end

        elseif trimmed:match("^nostealth") then
            if IsInStealth() then
                allConditionsMet = false
                break
            end

        -- Target/mounted/outdoors conditions ignored - don't affect which key to press
        end
    end

    return allConditionsMet, modifiers, formMatched, requiresModifier
end

function MacroParser.ParseMacroForSpell(macroBody, targetSpellID, targetSpellName)
    if not macroBody or not targetSpellID or not targetSpellName or targetSpellName == "" then 
        return false, nil 
    end

    local targetSpells = GetSpellAndOverride(targetSpellID, targetSpellName)
    local currentSpec = SafeGetSpecialization()
    -- Use FormCache which returns form index (1-N), not GetShapeshiftFormID which returns constant IDs
    local currentForm = FormCache and FormCache.GetActiveForm() or 0
    local debugMode = GetDebugMode()

    local foundLines = {}
    local bestMatch = nil

    for line in string_gmatch(macroBody, "[^\r\n]+") do
        local lowerLine = GetLowercase(line)

        if not string_match(lowerLine, "^%s*#") then
            local command = string_match(lowerLine, "/use%s+(.+)") or 
                            string_match(lowerLine, "/cast%s+(.+)") or
                            string_match(lowerLine, "/castsequence%s+(.+)")

            if command then
                for spellEntry in string_gmatch(command, "[^;]+") do
                    local trimmedEntry = string_match(spellEntry, "^%s*(.-)%s*$")
                    local conditions, spellPart = nil, nil
                    local lastBracketPos = 0
                    for i = 1, #trimmedEntry do
                        if string_sub(trimmedEntry, i, i) == "]" then
                            lastBracketPos = i
                        end
                    end

                    if lastBracketPos > 0 and string_sub(trimmedEntry, 1, 1) == "[" then
                        local conditionPart = string_sub(trimmedEntry, 1, lastBracketPos)
                        spellPart = string_match(string_sub(trimmedEntry, lastBracketPos + 1), "^%s*(.-)%s*$")
                        local firstCondition = string_match(conditionPart, "^%[([^%]]*)%]")
                        if firstCondition and firstCondition ~= "" then
                            conditions = firstCondition
                        end
                    else
                        spellPart = trimmedEntry
                    end

                    if not spellPart or spellPart == "" then
                        spellPart = trimmedEntry
                    end

                    local isMatch, matchedSpellID, matchedSpellName = DoesSpellMatch(spellPart, targetSpells)

                    if isMatch then
                        local now = GetTime()
                        local throttleKey = "match_" .. matchedSpellID
                        if debugMode and (not lastPrintTime[throttleKey] or now - lastPrintTime[throttleKey] > DEBUG_THROTTLE_INTERVAL) then
                            lastPrintTime[throttleKey] = now
                            print("|JAC| Found macro match: '" .. spellPart .. "' -> " .. matchedSpellName .. " (ID: " .. matchedSpellID .. ")")
                        end

                        local modifiers = {}
                        local conditionsMet = true
                        local requiresModifier = false

                        if conditions then
                            conditionsMet, modifiers, _, requiresModifier = EvaluateConditions(conditions, currentSpec, currentForm)
                        end

                        if conditionsMet then
                            -- Prefer no-modifier clause for default keybind detection
                            if not bestMatch or (not requiresModifier and bestMatch.requiresModifier) then
                                bestMatch = {modifiers = modifiers, requiresModifier = requiresModifier}
                            end
                        end
                    end
                end
            end
        end
    end

    if bestMatch then
        return true, bestMatch.modifiers
    end
    return false, nil
end

function MacroParser.GetMacroSpellInfo(slot, targetSpellID, targetSpellName)
    if not slot or not targetSpellID or not targetSpellName or targetSpellName == "" then
        return nil
    end

    -- Cache by spec only - form/stealth/combat affect spell cast, not keybind
    local currentSpec = SafeGetSpecialization()
    local cacheKey = slot .. "_" .. targetSpellID .. "_" .. currentSpec

    local cached = parsedMacroCache[cacheKey]
    if cached then return cached end

    local actionText = SafeGetActionText(slot)
    if not actionText or actionText == "" then return nil end
    
    local name, _, body = SafeGetMacroInfo(actionText)
    if not name or not body or body == "" then return nil end
    
    local found, modifiers = MacroParser.ParseMacroForSpell(body, targetSpellID, targetSpellName)
    if not found then return nil end

    local targetSpells = GetSpellAndOverride(targetSpellID, targetSpellName)
    local qualityScore = CalculateMacroSpecificityScore(name, body, targetSpells, GetDebugMode())
    
    local entry = {
        found = true,
        modifiers = modifiers,
        qualityScore = qualityScore,
    }
    
    parsedMacroCache[cacheKey] = entry
    return entry
end