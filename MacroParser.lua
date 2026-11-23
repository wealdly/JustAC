-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Macro Parser Module - Resolves macro conditionals to find actionable spells
local MacroParser = LibStub:NewLibrary("JustAC-MacroParser", 25)
if not MacroParser then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- Hot path cache
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
local IsPlayerSpell = C_SpellBook.IsSpellKnown
local function IsSpellInBook(spellID, isPet)
    local bank = isPet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
    return C_SpellBook.IsSpellInSpellBook(spellID, bank, false)
end
local FindBaseSpellByID = C_SpellBook and C_SpellBook.FindBaseSpellByID

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
    if not C_SpecializationInfo.GetSpecialization then return 0 end
    local ok, result = pcall(C_SpecializationInfo.GetSpecialization)
    return ok and result or 0
end

local function SafeGetActionText(slot)
    if not slot or not GetActionText then return nil end
    local ok, result = pcall(GetActionText, slot)
    return ok and result or nil
end

-- Is this spell learned, at any rank? Passive talents and spells waiting on a weapon count:
-- [known] asks what the character has learned, not what can be pressed right now.
local function IsSpellLearned(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellInBook and (IsSpellInBook(spellID) or IsSpellInBook(spellID, true)) then return true end
    local RotationImport = LibStub("JustAC-RotationImport", true)
    return RotationImport ~= nil and RotationImport.HighestKnownRank ~= nil
        and RotationImport.HighestKnownRank(spellID) ~= nil
end

-- One [known:] entry: true / false, nil when a name cannot be resolved to a spell.
local function IsIdentifierKnown(identifier)
    local spellID = tonumber(identifier)
    if spellID then return IsSpellLearned(spellID) end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, spellInfo = pcall(C_Spell.GetSpellInfo, identifier)
    if not ok or not spellInfo or not spellInfo.spellID then return nil end
    return IsSpellLearned(spellInfo.spellID)
end

-- A "/" list holds when any entry does. true / false, nil when it cannot be settled.
local function IsKnownListMet(list)
    local unknown = false
    for identifier in string_gmatch(list, "[^/]+") do
        local known = IsIdentifierKnown(identifier:match("^%s*(.-)%s*$"))
        if known == true then return true end
        if known == nil then unknown = true end
    end
    if unknown then return nil end
    return false
end

-- Macros take an item type in any case; the equipment query is given the client's own spelling
-- of it. Lowercase name -> client name, for every weapon and armor type, in the client's language.
local equippedTypeNames
local function EquippedTypeName(lowerType)
    if not equippedTypeNames then
        local classes = Enum and Enum.ItemClass
        if not (classes and classes.Weapon and classes.Armor and C_Item and C_Item.GetItemSubClassInfo) then
            return nil
        end
        local names = {}
        for classID, subclasses in pairs({ [classes.Weapon] = Enum.ItemWeaponSubclass,
                                           [classes.Armor] = Enum.ItemArmorSubclass }) do
            for _, subclassID in pairs(subclasses or {}) do
                local ok, name = pcall(C_Item.GetItemSubClassInfo, classID, subclassID)
                if ok and type(name) == "string"
                   and not (BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(name)) then
                    names[GetLowercase(name)] = name
                end
            end
        end
        if not next(names) then return nil end
        equippedTypeNames = names
    end
    return equippedTypeNames[lowerType]
end

-- An [equipped:] / [worn:] list holds when any item type in it is worn (shields/daggers).
-- true / false, nil when a type is not recognized or the answer cannot be read.
local function IsEquippedListMet(list)
    if not (C_Item and C_Item.IsEquippedItemType) then return nil end
    local unknown = false
    for itemType in string_gmatch(list, "[^/]+") do
        local typeName = EquippedTypeName(itemType:match("^%s*(.-)%s*$"))
        local ok, equipped = false, nil
        if typeName then ok, equipped = pcall(C_Item.IsEquippedItemType, typeName) end
        if not ok or type(equipped) ~= "boolean"
           or (BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(equipped)) then
            unknown = true
        elseif equipped then
            return true
        end
    end
    if unknown then return nil end
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

-- The macro on an action slot, as {name, body} candidates. GetMacroInfo(name) returns the
-- FIRST macro with that name, and account macros come first, so a character macro sharing
-- an account macro's name ("M1") resolves to the wrong body. The slot's own macro index is
-- used when the client reports one (a macro showing a spell reports the spell id instead);
-- otherwise every same-named macro is a candidate and the caller keeps the one that casts
-- the spell it is looking for.
local function MacroCandidates(slot, actionText)
    local out = {}
    local okA, aType, id, subType = pcall(GetActionInfo, slot)
    if okA and aType == "macro" and type(id) == "number" and subType ~= "spell" then
        local name, _, body = SafeGetMacroInfo(id)
        if name == actionText and body and body ~= "" then
            out[1] = { name = name, body = body }
            return out
        end
    end
    local okN, numAccount, numChar = pcall(GetNumMacros)
    if okN and numAccount then
        local charBase = MAX_ACCOUNT_MACROS or 120
        local function Try(i)
            local name, _, body = SafeGetMacroInfo(i)
            if name == actionText and body and body ~= "" then
                out[#out + 1] = { name = name, body = body }
            end
        end
        for i = 1, numAccount do Try(i) end
        for i = charBase + 1, charBase + (numChar or 0) do Try(i) end
    end
    if #out == 0 then
        local name, _, body = SafeGetMacroInfo(actionText)
        if name and body and body ~= "" then out[1] = { name = name, body = body } end
    end
    return out
end

function MacroParser.InvalidateMacroCache()
    wipe(parsedMacroCache)
    wipe(spellOverrideCache)
end

--- Drop cached parses for a single action slot (ACTIONBAR_SLOT_CHANGED).
--- Cache keys are "slot_spellID_spec". spellOverrideCache is untouched:
--- a slot change can't alter spell overrides.
function MacroParser.InvalidateMacroSlot(slot)
    local prefix = slot .. "_"
    local len = #prefix
    for key in pairs(parsedMacroCache) do
        if key:sub(1, len) == prefix then
            parsedMacroCache[key] = nil
        end
    end
end

-- Event-only invalidation: spellOverrideCache is cleared by InvalidateMacroCache(),
-- which fires on form, spell, spec, bar-page and vehicle/possess changes. (A single
-- ACTIONBAR_SLOT_CHANGED only drops that slot's parses - overrides are slot-independent.)
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
    -- And the BASE, the other way along the same chain: a spell that transforms while you
    -- use it (a channel's in-flight form) reaches here as the transformed id, but a macro
    -- names the base. Without it the keyed macro stopped matching mid-channel and a keyless
    -- slot holding the plain spell - which slot matching does resolve by base - won.
    local baseSpellID = FindBaseSpellByID and FindBaseSpellByID(spellID)
    if baseSpellID and baseSpellID ~= spellID and BlizzardAPI then
        local baseInfo = BlizzardAPI.GetSpellInfo(baseSpellID)
        if baseInfo and baseInfo.name then
            spells[baseSpellID] = baseInfo.name
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

-- Shared macro-line walk for AnalyzeMacroExecutionFlow and ParseMacroForSpell.
-- Invokes callback once per spell command line with the line's clauses pre-split:
--   entries[i] = { entry = raw clause text, spellPart, conditionGroups }
-- The command is the line's first word, as the client reads it, so text that merely mentions
-- a command (/say /cast X) is not one. Every command splits into semicolon-separated branches
-- with their own [condition] brackets. /castsequence, /castrandom and /userandom then hold a
-- comma-separated list in each branch, after any reset= clause.
-- A non-nil callback return stops the walk and is returned.
local CLAUSE_COMMANDS = { ["/cast"] = true, ["/use"] = true }
local LIST_COMMANDS = { ["/castsequence"] = true, ["/castrandom"] = true, ["/userandom"] = true }

-- "/startattack [conditions]" starts the Attack spell (6603) under those conditions, so it
-- reads as a cast of Attack, by its localized name.
local attackName
local function StartAttackCommand(lowerLine)
    local rest = string_match(lowerLine, "^%s*/startattack(.*)$")
    if not rest then return nil end
    -- Cached only once the client has the name: an early fallback must not stick for the
    -- session, or a non-English client never matches.
    local name = attackName
    if not name then
        local ok, info = pcall(C_Spell.GetSpellInfo, 6603)
        if ok and info and info.name then attackName = GetLowercase(info.name) end
        name = attackName or "attack"
    end
    local conds = ""
    for b in string_gmatch(rest, "%b[]") do conds = conds .. b end
    return conds .. " " .. name
end

local function ForEachCommandLine(macroBody, callback)
    local commandIndex = 0

    for line in string_gmatch(macroBody, "[^\r\n]+") do
        local lowerLine = GetLowercase(line)
        local slashCommand, arguments = string_match(lowerLine, "^%s*(/%S+)%s+(.+)$")
        local isList = LIST_COMMANDS[slashCommand] == true
        local command
        if isList or CLAUSE_COMMANDS[slashCommand] then command = arguments end
        local isAttackLine = false
        if not command then
            command = StartAttackCommand(lowerLine)
            isAttackLine = command ~= nil
        end

        if command then
            -- A /startattack line does not move the count: "/startattack" + "/cast X"
            -- keeps X as the macro's first command, as it always scored.
            local index = commandIndex + 1
            if not isAttackLine then commandIndex = index end
            local entries = {}

            for clause in string_gmatch(command, "[^;]+") do
                local spellPart, conditionGroups = StripBracketConditions(clause)
                if isList then
                    -- The reset clause ends at its first space or comma: the first spell follows.
                    local actions = spellPart:gsub("^reset=[^%s,]+[%s,]*", "")
                    for action in string_gmatch(actions, "[^,]+") do
                        table_insert(entries, {
                            entry = action,
                            spellPart = action:match("^%s*(.-)%s*$") or "",
                            conditionGroups = conditionGroups,
                        })
                    end
                else
                    table_insert(entries, {
                        entry = clause,
                        spellPart = spellPart,
                        conditionGroups = conditionGroups,
                    })
                end
            end

            local result = callback(index, entries)
            if result ~= nil then return result end
        end
    end

    return nil
end

local function AnalyzeMacroExecutionFlow(macroBody, targetSpells)
    return ForEachCommandLine(macroBody, function(commandIndex, entries)
        local totalInLine = 0
        local clauseEntries = {}
        local targetSpellFound = false
        local targetSpellPosition = 0

        for clausePosition, clause in ipairs(entries) do
            local spellPart = clause.spellPart
            if spellPart and spellPart ~= "" then
                totalInLine = totalInLine + 1
                table_insert(clauseEntries, clause.entry)

                if DoesSpellMatch(spellPart, targetSpells) then
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
                order = commandIndex,
                positionInLine = targetSpellPosition,
                totalInLine = totalInLine,
                conditionCount = lineConditions,
                isFirstClause = targetSpellPosition == 1,
            }
        end
    end)
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
    
    local executionInfo = AnalyzeMacroExecutionFlow(macroBody, targetSpells)
    
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

-- ponytail: hand-rolled subset of Blizzard's macro-conditional grammar; unhandled
-- clauses (target/combat/stealth/mounted/outdoors/...) fail-open: they change what fires
-- this moment, not which key the spell is on. Drifts as Blizzard adds
-- conditionals - deliberately NOT SecureCmdOptionParse, which answers "what fires
-- right now" and would blank/churn a static keybind display.
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

        -- [stance] and [form] are the same conditional under two names, and so are
        -- their negations. Two shapes, not four. The id list is read after the
        -- first colon rather than by name, which is what lets one arm serve both.
        elseif trimmed:match("^noform") or trimmed:match("^nostance") then
            local formList = trimmed:match(":([%d/]+)")
            if formList then
                for formStr in formList:gmatch("([^/]+)") do
                    if tonumber(formStr) == currentForm then
                        allConditionsMet = false
                        break
                    end
                end
            elseif currentForm ~= 0 then
                -- bare [noform] / [nostance] = only pass if not in any form
                allConditionsMet = false
            end
            if not allConditionsMet then break end

        elseif trimmed:match("^form") or trimmed:match("^stance") then
            local match = false
            local formList = trimmed:match(":([%d/]+)")
            if formList then
                for formStr in formList:gmatch("([^/]+)") do
                    if tonumber(formStr) == currentForm then
                        match = true
                        break
                    end
                end
            else
                -- bare [form] / [stance] = any form active
                match = (currentForm ~= 0)
            end
            if match then formMatched = true end
            if not match then allConditionsMet = false; break end

        elseif trimmed:match("^noknown:") then
            if IsKnownListMet(trimmed:match("^noknown:(.+)") or "") == true then
                allConditionsMet = false
                break
            end

        elseif trimmed:match("^known:") then
            if IsKnownListMet(trimmed:match("^known:(.+)") or "") == false then
                allConditionsMet = false
                break
            end

        -- Worn gear decides which branch the key casts, as a form does.
        elseif trimmed:match("^noequipped:") or trimmed:match("^noworn:") then
            if IsEquippedListMet(trimmed:match(":(.+)$") or "") == true then
                allConditionsMet = false
                break
            end

        elseif trimmed:match("^equipped:") or trimmed:match("^worn:") then
            if IsEquippedListMet(trimmed:match(":(.+)$") or "") == false then
                allConditionsMet = false
                break
            end

        -- Target/combat/stealth/mounted/outdoors conditions ignored - don't affect which key to press
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

    ForEachCommandLine(macroBody, function(_, entries)
        for _, clause in ipairs(entries) do
            local spellPart = clause.spellPart
            local conditionGroups = clause.conditionGroups

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
                    -- OR-cascade: any passing bracket group casts it. A group needing no
                    -- modifier decides, so [mod:shift][] is a plain press of the key.
                    conditionsMet = false
                    for _, conditionString in ipairs(conditionGroups) do
                        local groupMet, groupMods, _, groupReq = EvaluateConditions(conditionString, currentSpec, currentForm)
                        if groupMet and (not conditionsMet or not groupReq) then
                            conditionsMet = true
                            modifiers = groupMods
                            requiresModifier = groupReq
                        end
                        if groupMet and not groupReq then break end
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
    end)

    if bestMatch then
        return true, bestMatch.modifiers
    end
    return false, nil
end

-- Does the body hold a /startattack line (any conditions)? Pressing it can start melee.
local function BodyStartsAttack(macroBody)
    for line in string_gmatch(macroBody, "[^\r\n]+") do
        if StartAttackCommand(GetLowercase(line)) then return true end
    end
    return false
end

local function AutoAttackOnly(macroBody, targetSpellID, targetSpellName)
    if targetSpellID ~= 6603 and targetSpellID ~= 5019 and targetSpellID ~= 75 then return nil end
    for line in string_gmatch(macroBody, "[^\r\n]+") do
        local lower = GetLowercase(line)
        local attackArgs = string_match(lower, "^%s*/startattack(.*)$")
        local attackOnly = targetSpellID == 6603 and attackArgs
            and string_match(attackArgs:gsub("%b[]", ""), "^%s*$")
        if not string_match(lower, "^%s*#") and not string_match(lower, "^%s*$")
           and not string_match(lower, "^%s*/cast%s+")
           and not string_match(lower, "^%s*/use%s+")
           and not attackOnly then
            return false
        end
    end
    local targetSpells = GetSpellAndOverride(targetSpellID, targetSpellName)
    local found, other = false, false
    ForEachCommandLine(macroBody, function(_, entries)
        for _, clause in ipairs(entries) do
            if DoesSpellMatch(clause.spellPart, targetSpells) then found = true
            else other = true end
        end
    end)
    return found and not other
end

function MacroParser.GetMacroSpellInfo(slot, targetSpellID, targetSpellName)
    if not slot or not targetSpellID or not targetSpellName or targetSpellName == "" then
        return nil
    end

    -- Cache by spec only - form/stealth/combat affect spell cast, not keybind
    local currentSpec = SafeGetSpecialization()
    local cacheKey = slot .. "_" .. targetSpellID .. "_" .. currentSpec

    -- false = cached negative: without it, every non-matching (slot, spell) pair
    -- re-parses the full macro body on every hotkey rebuild.
    local cached = parsedMacroCache[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    local actionText = SafeGetActionText(slot)
    if not actionText or actionText == "" then return nil end

    local name, body, modifiers
    local candidates = MacroCandidates(slot, actionText)
    for _, c in ipairs(candidates) do
        local ok, mods = MacroParser.ParseMacroForSpell(c.body, targetSpellID, targetSpellName)
        if ok then
            name, body, modifiers = c.name, c.body, mods
            break
        end
    end
    if not name then
        parsedMacroCache[cacheKey] = false
        return nil
    end

    local targetSpells = GetSpellAndOverride(targetSpellID, targetSpellName)
    local qualityScore = CalculateMacroSpecificityScore(name, body, targetSpells, GetDebugMode())
    local autoAttackOnly = AutoAttackOnly(body, targetSpellID, targetSpellName)
    if autoAttackOnly then
        for _, candidate in ipairs(candidates) do
            if not AutoAttackOnly(candidate.body, targetSpellID, targetSpellName) then
                autoAttackOnly = false
                break
            end
        end
    end
    
    -- startsAttack: pressing this macro for the spell also starts melee. Every same-named
    -- candidate must agree, since the slot's exact body is not always known.
    -- The matched body is one of the candidates, so this tests it too.
    local startsAttack = true
    for _, candidate in ipairs(candidates) do
        if not BodyStartsAttack(candidate.body) then
            startsAttack = false
            break
        end
    end

    local entry = {
        found = true,
        modifiers = modifiers,
        qualityScore = qualityScore,
        autoAttackOnly = autoAttackOnly,
        startsAttack = startsAttack,
    }
    
    parsedMacroCache[cacheKey] = entry
    return entry
end