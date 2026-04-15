-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Macro Parser Module - Resolves macro conditionals to find actionable spells
local MacroParser = LibStub:NewLibrary("JustAC-MacroParser", 23)
if not MacroParser then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- Hot path cache
local type = type
local tonumber = tonumber
local string_lower = string.lower
local string_match = string.match
local string_find = string.find
local string_gmatch = string.gmatch
local string_sub = string.sub
local table_insert = table.insert
local pairs = pairs
local pcall = pcall
local wipe = wipe

local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local IsStealthed = IsStealthed
local IsSpellKnown = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell

local parsedMacroCache = {}
local spellOverrideCache = {}
local lastPrintTime = {}
local DEBUG_THROTTLE_INTERVAL = 5

local function GetLowercase(str)
    return str and string_lower(str) or ""
end

-- Extract the spell name from a macro clause, stripping any [condition] brackets.
-- Returns: spellPart (string), conditionGroups (table of strings, one per [...] group)
-- OR-cascade: "[spec:1][spec:2] Maul" → {"spec:1", "spec:2"}; "Maul" → {}
local function StripBracketConditions(entry)
    if not entry then return "", {} end
    local trimmed = entry:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return "", {} end
    -- Find the last ']' efficiently using string.find with reverse search
    local lastBracketPos = 0
    local pos = 1
    while true do
        local found = string_find(trimmed, "]", pos, true)
        if not found then break end
        lastBracketPos = found
        pos = found + 1
    end
    if lastBracketPos > 0 and string_sub(trimmed, 1, 1) == "[" then
        local conditionPart = string_sub(trimmed, 1, lastBracketPos)
        local spellPart = string_match(string_sub(trimmed, lastBracketPos + 1), "^%s*(.-)%s*$") or ""
        -- Extract ALL bracket groups for OR-cascade evaluation
        local conditionGroups = {}
        for groupContent in string_gmatch(conditionPart, "%[([^%]]*)%]") do
            table_insert(conditionGroups, groupContent)
        end
        return spellPart, conditionGroups
    end
    return trimmed, {}
end

local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
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
end

-- Event-only invalidation: spellOverrideCache is cleared by InvalidateMacroCache()
-- which fires on UPDATE_SHAPESHIFT_FORM, SPELLS_CHANGED, PLAYER_SPECIALIZATION_CHANGED,
-- ACTIONBAR_SLOT_CHANGED, and vehicle/possess events. No timer needed.
local function GetSpellAndOverride(spellID, spellName)
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
    
    -- Strip leading ! (repeat-cast toggle), target specifiers (@mouseover, @player, etc.) and trailing markers
    local cleanSpellPart = lowerSpellPart:gsub("^!", ""):gsub("%s*@[%w]+%s*$", ""):gsub("%s*%(@[%w]+%)%s*$", "")
    cleanSpellPart = cleanSpellPart:gsub("%s*%(.-%)%s*$", "")
    cleanSpellPart = cleanSpellPart:match("^%s*(.-)%s*$") or cleanSpellPart
    
    local checkOriginal = cleanSpellPart ~= lowerSpellPart
    for spellID, spellName in pairs(targetSpells) do
        local lowerSpellName = GetLowercase(spellName)
        if cleanSpellPart == lowerSpellName then
            return true, spellID, spellName
        end
        if checkOriginal and lowerSpellPart == lowerSpellName then
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
                           string_match(lowerLine, "/cast%s+(.+)")
            local isCastseq = false

            if not command then
                local castseq = string_match(lowerLine, "/castsequence%s+(.+)")
                if castseq then
                    isCastseq = true
                    local seqSpellPart = StripBracketConditions(castseq)
                    command = seqSpellPart:gsub("^reset=[^,]+,%s*", ""):gsub("^reset=[^%s]+%s*", "")
                end
            end

            if command then
                globalExecutionOrder = globalExecutionOrder + 1
                local simultaneousAbilities = {}
                local clauseEntries = {}
                local targetSpellFound = false
                local targetSpellPosition = 0
                local clausePosition = 0
                local entryPattern = isCastseq and "[^,]+" or "[^;]+"

                for spellEntry in string_gmatch(command, entryPattern) do
                    clausePosition = clausePosition + 1
                    local spellPart
                    if isCastseq then
                        spellPart = spellEntry:match("^%s*(.-)%s*$") or ""
                    else
                        spellPart = StripBracketConditions(spellEntry)
                    end

                    if spellPart and spellPart ~= "" then
                        table.insert(simultaneousAbilities, spellPart)
                        table.insert(clauseEntries, spellEntry)

                        local isMatch = DoesSpellMatch(spellPart, targetSpells)
                        if isMatch then
                            targetSpellFound = true
                            targetSpellPosition = clausePosition
                        end
                    end
                end

                if targetSpellFound then
                    -- Count [condition] brackets in the matching clause only
                    local matchingEntry = clauseEntries[targetSpellPosition] or ""
                    local lineConditions = 0
                    for _ in string_gmatch(matchingEntry, "%[[^%]]*%]") do
                        lineConditions = lineConditions + 1
                    end
                    return {
                        order = globalExecutionOrder,
                        lineNumber = lineNumber,
                        positionInLine = targetSpellPosition,
                        totalInLine = #simultaneousAbilities,
                        simultaneousAbilities = simultaneousAbilities,
                        conditionCount = lineConditions,
                        isFirstClause = targetSpellPosition == 1,
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
        elseif #lowerSpellName >= 4 and string_find(lowerMacroName, string_sub(lowerSpellName, 1, 4), 1, true) then
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
        
        -- Multi-spell line penalty: if target spell is not the first clause
        if executionInfo.totalInLine > 1 and not executionInfo.isFirstClause then
            penalty = penalty + 100
        end
        
        local conditionCount = executionInfo.conditionCount or 0
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
        local trimmed = GetLowercase(condition:match("^%s*(.-)%s*$"))

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
            else
                -- bare [noform] = only pass if not in any form
                if currentForm ~= 0 then allConditionsMet = false end
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
            else
                -- bare [form] = any form active
                match = (currentForm ~= 0)
                if match then formMatched = true end
            end
            if not match then allConditionsMet = false; break end

        elseif trimmed:match("^nostance") then
            local stanceList = trimmed:match("nostance:([%d/]+)")
            if stanceList then
                for stanceStr in stanceList:gmatch("([^/]+)") do
                    local reqForm = tonumber(stanceStr)
                    if reqForm and currentForm == reqForm then
                        allConditionsMet = false
                        break
                    end
                end
            else
                -- bare [nostance] = only pass if not in any stance
                if currentForm ~= 0 then allConditionsMet = false end
            end
            if not allConditionsMet then break end

        elseif trimmed:match("^stance") then
            local match = false
            local stanceList = trimmed:match("stance:([%d/]+)")
            if stanceList then
                for stanceStr in stanceList:gmatch("([^/]+)") do
                    local reqForm = tonumber(stanceStr)
                    if reqForm and currentForm == reqForm then
                        match = true
                        formMatched = true
                        break
                    end
                end
            else
                -- bare [stance] = any stance active
                match = (currentForm ~= 0)
                if match then formMatched = true end
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

    local bestMatch = nil

    for line in string_gmatch(macroBody, "[^\r\n]+") do
        local lowerLine = GetLowercase(line)

        if not string_match(lowerLine, "^%s*#") then
            local command = string_match(lowerLine, "/use%s+(.+)") or
                            string_match(lowerLine, "/cast%s+(.+)")
            local castseqGroups  -- sequence-level condition groups for /castsequence

            if not command then
                local castseq = string_match(lowerLine, "/castsequence%s+(.+)")
                if castseq then
                    local seqSpellPart, seqGroups = StripBracketConditions(castseq)
                    castseqGroups = seqGroups
                    command = seqSpellPart:gsub("^reset=[^,]+,%s*", ""):gsub("^reset=[^%s]+%s*", "")
                end
            end

            if command then
                local entryPattern = castseqGroups and "[^,]+" or "[^;]+"
                for spellEntry in string_gmatch(command, entryPattern) do
                    local spellPart, conditionGroups
                    if castseqGroups then
                        spellPart = spellEntry:match("^%s*(.-)%s*$") or ""
                        conditionGroups = castseqGroups
                    else
                        spellPart, conditionGroups = StripBracketConditions(spellEntry)
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

                        if conditionGroups and #conditionGroups > 0 then
                            -- OR-cascade: first passing bracket group wins
                            conditionsMet = false
                            for _, conditionString in ipairs(conditionGroups) do
                                if conditionString == "" then
                                    -- bare [] = unconditional fallback
                                    conditionsMet = true
                                    break
                                end
                                local groupMet, groupMods, _, groupReq = EvaluateConditions(conditionString, currentSpec, currentForm)
                                if groupMet then
                                    conditionsMet = true
                                    modifiers = groupMods
                                    requiresModifier = groupReq
                                    break
                                end
                            end
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