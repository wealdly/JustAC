-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options Module - Provides AceConfig UI for addon settings
local Options = LibStub:NewLibrary("JustAC-Options", 30)
if not Options then return end

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIManager = LibStub("JustAC-UIManager", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Storage for hotkey value input (not spell search)
local addHotkeyValueInput = ""

-- Spellbook cache for autocomplete (populated on first options open)
local spellbookCache = {}  -- {spellID = {name = "Spell Name", icon = iconID}, ...}
local spellbookCacheBuilt = false

-- Filter state for spell search (all panels)
local spellSearchFilter = {
    selfheal = "",
    cooldown = "",
    blacklist = "",
    hotkey = "",
}

-- Preview state: first result shown in dropdown (not yet added)
local spellSearchPreview = {
    selfheal = nil,
    cooldown = nil,
    blacklist = nil,
    hotkey = nil,
}

-- Build spellbook cache (called once when options panel opens)
local function BuildSpellbookCache()
    if spellbookCacheBuilt then return end

    if not C_SpellBook or not C_SpellBook.GetSpellBookItemInfo then
        return
    end

    -- Scan player spellbook
    for i = 1, 500 do
        local spellInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
        if not spellInfo then break end

        -- Only cache actual spells (not flyouts, petactions, etc.)
        if spellInfo.itemType == Enum.SpellBookItemType.Spell and spellInfo.spellID then
            -- Skip passive spells
            local isPassive = C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellInfo.spellID)
            if not isPassive then
                local fullInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellInfo.spellID)
                if fullInfo and fullInfo.name then
                    spellbookCache[spellInfo.spellID] = {
                        name = fullInfo.name,
                        icon = fullInfo.iconID,
                    }
                end
            end
        end
    end

    spellbookCacheBuilt = true
end

-- Get filtered spells for dropdown based on search text
local function GetFilteredSpellbookSpells(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()

    -- Build exclusion set
    local excluded = {}
    if excludeList then
        for _, spellID in ipairs(excludeList) do
            excluded[spellID] = true
        end
    end

    -- If filter is too short, return empty (avoid huge dropdown)
    if filter == "" or #filter < 2 then
        return results
    end

    -- Check if filter is a spell ID (numeric)
    local filterAsID = tonumber(filter)
    if filterAsID and filterAsID > 0 and not excluded[filterAsID] then
        -- Try to get spell info for this ID
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(filterAsID)
        if spellInfo and spellInfo.name then
            results[filterAsID] = spellInfo.name .. " (ID: " .. filterAsID .. ")"
            return results  -- Exact ID match, return just this
        end
    end

    -- Search cache by name (and partial ID match)
    local count = 0
    for spellID, info in pairs(spellbookCache) do
        if not excluded[spellID] then
            local nameLower = info.name:lower()
            local idString = tostring(spellID)
            -- Match by name OR by spell ID prefix
            if nameLower:find(filterLower, 1, true) or idString:find(filter, 1, true) then
                results[spellID] = info.name .. " (" .. spellID .. ")"
                count = count + 1
                if count >= 15 then break end  -- Limit dropdown size
            end
        end
    end

    return results
end

-- Helper to look up spell ID from name
local function LookupSpellByName(spellName)
    if not spellName or spellName == "" then return nil end

    local nameLower = spellName:lower():trim()

    -- Search spellbook cache first
    for spellID, info in pairs(spellbookCache) do
        if info.name:lower() == nameLower then
            return spellID
        end
    end

    -- Try C_Spell.GetSpellInfo with the name directly (might work for some spells)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellName)
        if info and info.spellID then
            return info.spellID
        end
    end

    return nil
end

function Options.UpdateBlacklistOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local blacklistArgs = optionsTable.args.offensive.args

    -- Static keys to preserve (defined in InitOptionsTable)
    local staticKeys = {
        info = true, contentHeader = true, includeHiddenAbilities = true,
        showSpellbookProcs = true, hideItemAbilities = true, showHotkeys = true,
        blacklistHeader = true, blacklistInfo = true,
    }

    -- Clear old dynamic entries
    local keysToClear = {}
    for key, _ in pairs(blacklistArgs) do
        if not staticKeys[key] then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        blacklistArgs[key] = nil
    end

    -- Ensure blacklistedSpells table exists in saved variables
    if not addon.db.char.blacklistedSpells then
        addon.db.char.blacklistedSpells = {}
    end
    local blacklistedSpells = addon.db.char.blacklistedSpells
    
    -- Ensure spellbook cache is built
    BuildSpellbookCache()

    -- Initialize filter storage
    spellSearchFilter.blacklist = spellSearchFilter.blacklist or ""

    -- Add spell input section with autocomplete
    blacklistArgs.addHeader = {
        type = "header",
        name = L["Add Spell to Blacklist"],
        order = 22,
    }
    blacklistArgs.searchInput = {
        type = "input",
        name = L["Search spell name or ID"],
        desc = L["Search spell desc"],
        order = 22.1,
        width = "double",
        get = function() return spellSearchFilter.blacklist or "" end,
        set = function(_, val)
            spellSearchFilter.blacklist = val or ""
            if AceConfigRegistry then
                AceConfigRegistry:NotifyChange("JustAssistedCombat")
            end
        end
    }
    blacklistArgs.searchDropdown = {
        type = "select",
        name = "",
        desc = L["Select spell to blacklist"],
        order = 22.2,
        width = "double",
        values = function()
            -- Convert blacklist dict to array for exclusion
            local excludeList = {}
            for spellID, _ in pairs(blacklistedSpells) do
                table.insert(excludeList, spellID)
            end
            local results = GetFilteredSpellbookSpells(spellSearchFilter.blacklist, excludeList)
            local filter = (spellSearchFilter.blacklist or ""):trim()
            if next(results) == nil and #filter >= 2 then
                spellSearchPreview.blacklist = nil
                return {[0] = "|cff888888" .. L["No matches"] .. "|r"}
            end
            -- Set preview to first result (shown in dropdown, not yet added)
            spellSearchPreview.blacklist = next(results)
            return results
        end,
        get = function() return spellSearchPreview.blacklist end,
        set = function(_, spellID)
            if spellID == 0 then return end
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                blacklistedSpells[spellID] = true
                addon:Print("Blacklisted: " .. spellInfo.name)
                spellSearchFilter.blacklist = ""
                addon:ForceUpdate()
                Options.UpdateBlacklistOptions(addon)
            end
        end,
        disabled = function()
            local filter = (spellSearchFilter.blacklist or ""):trim()
            return #filter < 2
        end,
    }
    blacklistArgs.addButton = {
        type = "execute",
        name = L["Add"],
        desc = L["Add spell manual desc"],
        order = 22.3,
        width = "half",
        func = function()
            local val = (spellSearchFilter.blacklist or ""):trim()
            if val == "" then return end

            local spellID = tonumber(val)
            if not spellID then
                spellID = LookupSpellByName(val)
                if not spellID and C_Spell and C_Spell.GetSpellInfo then
                    local info = C_Spell.GetSpellInfo(val)
                    if info and info.spellID then
                        spellID = info.spellID
                    end
                end
            end

            if not spellID then
                addon:Print("Spell not found: " .. val)
                return
            end

            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if not spellInfo or not spellInfo.name then
                addon:Print("Invalid spell ID: " .. spellID)
                return
            end

            if blacklistedSpells[spellID] then
                addon:Print("Spell already blacklisted: " .. spellInfo.name)
                return
            end

            blacklistedSpells[spellID] = true
            addon:Print("Blacklisted: " .. spellInfo.name)
            spellSearchFilter.blacklist = ""
            addon:ForceUpdate()
            Options.UpdateBlacklistOptions(addon)
        end,
        disabled = function()
            local filter = (spellSearchFilter.blacklist or ""):trim()
            return #filter < 1
        end,
    }
    blacklistArgs.listHeader = {
        type = "header",
        name = L["Blacklisted Spells"],
        order = 22.5,
    }
    
    -- Build sorted list of spell IDs (keys are already normalized to numbers on load)
    local spellList = {}
    for spellID, _ in pairs(blacklistedSpells) do
        if type(spellID) == "number" and spellID > 0 then
            table.insert(spellList, spellID)
        end
    end

    table.sort(spellList, function(a, b)
        local infoA = BlizzardAPI and BlizzardAPI.GetSpellInfo(a) or C_Spell.GetSpellInfo(a)
        local infoB = BlizzardAPI and BlizzardAPI.GetSpellInfo(b) or C_Spell.GetSpellInfo(b)
        local nameA = infoA and infoA.name or ""
        local nameB = infoB and infoB.name or ""
        return nameA < nameB
    end)

    if #spellList == 0 then
        blacklistArgs.noSpells = {
            type = "description",
            name = L["No spells currently blacklisted"],
            order = 23,
        }
    else
        for i, spellID in ipairs(spellList) do
            local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID) or C_Spell.GetSpellInfo(spellID)
            local spellName = spellInfo and spellInfo.name or ("Spell #" .. spellID)
            local spellIcon = spellInfo and spellInfo.iconID or 134400

            blacklistArgs[tostring(spellID)] = {
                type = "group",
                name = "|T" .. spellIcon .. ":16:16:0:0|t " .. spellName,
                inline = true,
                order = i + 23,
                args = {
                    spellInfo = {
                        type = "description",
                        name = "|cff888888ID: " .. spellID .. "|r",
                        order = 1,
                        width = "double",
                    },
                    remove = {
                        type = "execute",
                        name = L["Remove"],
                        order = 2,
                        func = function()
                            blacklistedSpells[spellID] = nil
                            addon:ForceUpdate()
                            Options.UpdateBlacklistOptions(addon)
                        end
                    }
                }
            }
        end
    end
    
    -- Notify AceConfig that the options table changed
    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end

function Options.UpdateHotkeyOverrideOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local hotkeyArgs = optionsTable.args.hotkeyOverrides.args

    -- Clear old entries (preserve static ones)
    local keysToClear = {}
    for key, _ in pairs(hotkeyArgs) do
        if key ~= "info" then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        hotkeyArgs[key] = nil
    end

    local hotkeyOverrides = addon.db.char.hotkeyOverrides or {}

    -- Ensure spellbook cache is built
    BuildSpellbookCache()

    -- Initialize filter storage
    spellSearchFilter.hotkey = spellSearchFilter.hotkey or ""

    -- Add hotkey input section with autocomplete
    hotkeyArgs.addHeader = {
        type = "header",
        name = L["Add Hotkey Override"],
        order = 2,
    }
    hotkeyArgs.searchInput = {
        type = "input",
        name = L["Search spell name or ID"],
        desc = L["Search spell desc"],
        order = 2.1,
        width = "double",
        get = function() return spellSearchFilter.hotkey or "" end,
        set = function(_, val)
            spellSearchFilter.hotkey = val or ""
            if AceConfigRegistry then
                AceConfigRegistry:NotifyChange("JustAssistedCombat")
            end
        end
    }
    hotkeyArgs.searchDropdown = {
        type = "select",
        name = "",
        desc = L["Select spell for hotkey"],
        order = 2.2,
        width = "double",
        values = function()
            -- Convert overrides dict to array for exclusion
            local excludeList = {}
            for spellID, _ in pairs(hotkeyOverrides) do
                table.insert(excludeList, spellID)
            end
            local results = GetFilteredSpellbookSpells(spellSearchFilter.hotkey, excludeList)
            local filter = (spellSearchFilter.hotkey or ""):trim()
            if next(results) == nil and #filter >= 2 then
                spellSearchPreview.hotkey = nil
                return {[0] = "|cff888888" .. L["No matches"] .. "|r"}
            end
            -- Set preview to first result (shown in dropdown, not yet added)
            spellSearchPreview.hotkey = next(results)
            return results
        end,
        get = function() return spellSearchPreview.hotkey end,
        set = function(_, spellID)
            if spellID == 0 then return end
            -- When spell selected from dropdown, put it in search field for Add button
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                spellSearchFilter.hotkey = tostring(spellID)
                spellSearchPreview.hotkey = spellID  -- Update preview to match selection
                if AceConfigRegistry then
                    AceConfigRegistry:NotifyChange("JustAssistedCombat")
                end
            end
        end,
        disabled = function()
            local filter = (spellSearchFilter.hotkey or ""):trim()
            return #filter < 2
        end,
    }
    hotkeyArgs.addHotkeyInput = {
        type = "input",
        name = L["Hotkey"],
        desc = L["Enter the hotkey text to display (e.g. 1, F1, S-2)"],
        order = 2.3,
        width = "normal",
        get = function() return addHotkeyValueInput end,
        set = function(_, val) addHotkeyValueInput = val or "" end,
    }
    hotkeyArgs.addButton = {
        type = "execute",
        name = L["Add"],
        desc = L["Add hotkey desc"],
        order = 2.4,
        width = "half",
        func = function()
            local val = (spellSearchFilter.hotkey or ""):trim()
            if val == "" then
                addon:Print(L["Please search and select a spell first"])
                return
            end
            if not addHotkeyValueInput or addHotkeyValueInput:trim() == "" then
                addon:Print(L["Please enter a hotkey value"])
                return
            end

            local spellID = tonumber(val)
            if not spellID then
                spellID = LookupSpellByName(val)
                if not spellID and C_Spell and C_Spell.GetSpellInfo then
                    local info = C_Spell.GetSpellInfo(val)
                    if info and info.spellID then
                        spellID = info.spellID
                    end
                end
            end

            if not spellID then
                addon:Print("Spell not found: " .. val)
                return
            end

            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if not spellInfo or not spellInfo.name then
                addon:Print("Invalid spell ID: " .. spellID)
                return
            end

            hotkeyOverrides[spellID] = addHotkeyValueInput:trim()
            addon:Print("Hotkey set: " .. spellInfo.name .. " = '" .. addHotkeyValueInput:trim() .. "'")
            spellSearchFilter.hotkey = ""
            addHotkeyValueInput = ""
            addon:ForceUpdate()
            Options.UpdateHotkeyOverrideOptions(addon)
        end,
        disabled = function()
            local filter = (spellSearchFilter.hotkey or ""):trim()
            return #filter < 1
        end,
    }
    hotkeyArgs.listHeader = {
        type = "header",
        name = L["Custom Hotkeys"],
        order = 2.5,
    }
    
    -- Build sorted list of spell IDs (keys are already normalized to numbers on load)
    local overrideList = {}
    for spellID, hotkeyValue in pairs(hotkeyOverrides) do
        if type(spellID) == "number" and spellID > 0 and type(hotkeyValue) == "string" then
            table.insert(overrideList, spellID)
        end
    end

    table.sort(overrideList, function(a, b)
        local infoA = BlizzardAPI and BlizzardAPI.GetSpellInfo(a) or C_Spell.GetSpellInfo(a)
        local infoB = BlizzardAPI and BlizzardAPI.GetSpellInfo(b) or C_Spell.GetSpellInfo(b)
        local nameA = infoA and infoA.name or ""
        local nameB = infoB and infoB.name or ""
        return nameA < nameB
    end)

    if #overrideList == 0 then
        hotkeyArgs.noOverrides = {
            type = "description",
            name = L["No custom hotkeys set"],
            order = 3,
        }
    else
        for i, spellID in ipairs(overrideList) do
            local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID) or C_Spell.GetSpellInfo(spellID)
            local spellName = spellInfo and spellInfo.name or ("Spell #" .. spellID)
            local spellIcon = spellInfo and spellInfo.iconID or 134400
            
            hotkeyArgs[tostring(spellID)] = {
                type = "group",
                name = "|T" .. spellIcon .. ":16:16:0:0|t " .. spellName,
                inline = true,
                order = i + 3,
                args = {
                    currentHotkey = {
                        type = "input",
                        name = L["Custom Hotkey"],
                        desc = L["Custom Hotkey desc"],
                        order = 1,
                        width = "double",
                        get = function()
                            return hotkeyOverrides[spellID] or ""
                        end,
                        set = function(_, val)
                            if val and val:trim() ~= "" then
                                hotkeyOverrides[spellID] = val:trim()
                            else
                                hotkeyOverrides[spellID] = nil
                            end
                            addon:ForceUpdate()
                            Options.UpdateHotkeyOverrideOptions(addon)
                        end
                    },
                    remove = {
                        type = "execute",
                        name = L["Remove"],
                        order = 2,
                        func = function()
                            hotkeyOverrides[spellID] = nil
                            Options.UpdateHotkeyOverrideOptions(addon)
                            addon:ForceUpdate()
                        end
                    }
                }
            }
        end
    end
    
    -- Notify AceConfig that the options table changed
    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end

-- Helper to create spell list entries for a given list
local function CreateSpellListEntries(addon, defensivesArgs, spellList, listType, baseOrder)
    if not spellList then return end

    local updateFunc = function()
        Options.UpdateDefensivesOptions(addon)
    end
    
    for i, spellID in ipairs(spellList) do
        local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or ("Spell " .. spellID)
        local spellIcon = spellInfo and spellInfo.iconID or 134400
        
        -- Add cooldown info if available
        local cooldownInfo = ""
        if spellInfo and C_Spell and C_Spell.GetSpellCooldown then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            -- Handle secret values (WoW 12.0+) - duration may be secret in combat
            local duration = cdInfo and cdInfo.duration
            local isSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(duration)
            if duration and not isSecret and duration > 1.5 then
                cooldownInfo = " |cff888888(" .. math.floor(duration) .. "s)|r"
            end
        end
        
        defensivesArgs[listType .. "_" .. i] = {
            type = "group",
            name = i .. ". |T" .. spellIcon .. ":16:16:0:0|t " .. spellName .. cooldownInfo,
            inline = true,
            order = baseOrder + (i * 0.1),
            args = {
                moveUp = {
                    type = "execute",
                    name = L["Up"],
                    desc = L["Move up desc"],
                    order = 1,
                    width = 0.3,
                    disabled = function() return i == 1 end,
                    func = function()
                        local temp = spellList[i - 1]
                        spellList[i - 1] = spellList[i]
                        spellList[i] = temp
                        updateFunc()
                    end
                },
                moveDown = {
                    type = "execute",
                    name = L["Dn"],
                    desc = L["Move down desc"],
                    order = 2,
                    width = 0.3,
                    disabled = function() return i == #spellList end,
                    func = function()
                        local temp = spellList[i + 1]
                        spellList[i + 1] = spellList[i]
                        spellList[i] = temp
                        updateFunc()
                    end
                },
                remove = {
                    type = "execute",
                    name = L["Remove"],
                    order = 3,
                    width = 0.5,
                    func = function()
                        table.remove(spellList, i)
                        updateFunc()
                    end
                }
            }
        }
    end
end

-- Helper to add a spell to a list (used by both dropdown and manual input)
local function AddSpellToList(addon, spellList, spellID)
    if not spellID or spellID <= 0 then return false end

    -- Validate spell exists
    local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then
        addon:Print("Invalid spell ID: " .. spellID .. " (spell not found)")
        return false
    end

    -- Check if already in list
    for _, existingID in ipairs(spellList) do
        if existingID == spellID then
            addon:Print("Spell already in list: " .. spellInfo.name)
            return false
        end
    end

    table.insert(spellList, spellID)
    addon:Print("Added: " .. spellInfo.name)
    return true
end

-- Helper to create add spell input with autocomplete dropdown
local function CreateAddSpellInput(addon, defensivesArgs, spellList, listType, order, listName)
    -- Ensure spellbook cache is built
    BuildSpellbookCache()

    -- Initialize filter storage
    spellSearchFilter[listType] = spellSearchFilter[listType] or ""

    local updateFunc = function()
        Options.UpdateDefensivesOptions(addon)
    end

    -- Search input field (type to filter by name or ID)
    defensivesArgs["search_input_" .. listType] = {
        type = "input",
        name = L["Add to %s"]:format(listName),
        desc = L["Search spell desc"],
        order = order,
        width = "double",
        get = function() return spellSearchFilter[listType] or "" end,
        set = function(_, val)
            spellSearchFilter[listType] = val or ""
            -- Refresh options to update dropdown
            if AceConfigRegistry then
                AceConfigRegistry:NotifyChange("JustAssistedCombat")
            end
        end
    }

    -- Dynamic dropdown showing filtered spells
    defensivesArgs["search_dropdown_" .. listType] = {
        type = "select",
        name = "",
        desc = L["Select spell to add"],
        order = order + 0.1,
        width = "double",
        values = function()
            local results = GetFilteredSpellbookSpells(spellSearchFilter[listType], spellList)
            -- If no results and filter looks like valid input, show helper text
            local filter = (spellSearchFilter[listType] or ""):trim()
            if next(results) == nil and #filter >= 2 then
                spellSearchPreview[listType] = nil
                return {[0] = "|cff888888" .. L["No matches"] .. "|r"}
            end
            -- Set preview to first result (shown in dropdown, not yet added)
            spellSearchPreview[listType] = next(results)
            return results
        end,
        get = function() return spellSearchPreview[listType] end,  -- Show first result as preview
        set = function(_, spellID)
            if spellID == 0 then return end  -- Ignore "no matches" placeholder
            if AddSpellToList(addon, spellList, spellID) then
                spellSearchFilter[listType] = ""  -- Clear search
                spellSearchPreview[listType] = nil  -- Clear preview
                updateFunc()
            end
        end,
        disabled = function()
            local filter = (spellSearchFilter[listType] or ""):trim()
            return #filter < 2
        end,
    }

    -- Add button for manual entry (spell ID or exact name not in spellbook)
    defensivesArgs["add_button_" .. listType] = {
        type = "execute",
        name = L["Add"],
        desc = L["Add spell dropdown desc"],
        order = order + 0.2,
        width = "half",
        func = function()
            local val = (spellSearchFilter[listType] or ""):trim()
            if val == "" then return end

            local spellID = tonumber(val)

            -- If not a number, try looking up by name
            if not spellID then
                spellID = LookupSpellByName(val)
                if not spellID then
                    -- Try C_Spell directly for spells not in cache
                    if C_Spell and C_Spell.GetSpellInfo then
                        local info = C_Spell.GetSpellInfo(val)
                        if info and info.spellID then
                            spellID = info.spellID
                        end
                    end
                end
                if not spellID then
                    addon:Print("Spell not found: " .. val)
                    return
                end
            end

            if AddSpellToList(addon, spellList, spellID) then
                spellSearchFilter[listType] = ""  -- Clear input
                updateFunc()
            end
        end,
        disabled = function()
            local filter = (spellSearchFilter[listType] or ""):trim()
            return #filter < 1
        end,
    }
end

function Options.UpdateDefensivesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not SpellQueue then return end

    local defensivesArgs = optionsTable.args.defensives.args

    -- Clear old dynamic entries (preserve static elements)
    local staticKeys = {
        info = true, header = true, enabled = true, showProcs = true, 
        thresholdHeader = true, selfHealThreshold = true, cooldownThreshold = true, petHealThreshold = true, thresholdNote = true,
        behaviorHeader = true, displayMode = true, showHealthBar = true,
        position = true, iconScale = true, maxIcons = true, showHotkeys = true,
        selfHealHeader = true, selfHealInfo = true, restoreSelfHealDefaults = true,
        cooldownHeader = true, cooldownInfo = true, restoreCooldownDefaults = true,
    }
    
    local keysToClear = {}
    for key, _ in pairs(defensivesArgs) do
        if not staticKeys[key] then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        defensivesArgs[key] = nil
    end

    local defensives = addon.db.profile.defensives
    if not defensives then return end

    -- Self-heal spells (order 22.0-39.9, allowing 180 entries)
    CreateSpellListEntries(addon, defensivesArgs, defensives.selfHealSpells, "selfheal", 22)
    CreateAddSpellInput(addon, defensivesArgs, defensives.selfHealSpells, "selfheal", 40, "Self-Heals")

    -- Cooldown spells (order 52.0-69.9, allowing 180 entries)  
    CreateSpellListEntries(addon, defensivesArgs, defensives.cooldownSpells, "cooldown", 52)
    CreateAddSpellInput(addon, defensivesArgs, defensives.cooldownSpells, "cooldown", 70, "Cooldowns")
    
    -- Notify AceConfig that the options table changed
    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end

local function CreateOptionsTable(addon)
    return {
        name = L["JustAssistedCombat"],
        handler = addon,
        type = "group",
        args = {
            general = {
                type = "group",
                name = L["General"],
                order = 1,
                args = {
                    info = {
                        type = "description",
                        name = L["General description"],
                        order = 1,
                        fontSize = "medium"
                    },
                    -- ICON LAYOUT (10-19)
                    layoutHeader = {
                        type = "header",
                        name = L["Icon Layout"],
                        order = 10,
                    },
                    maxIcons = {
                        type = "range",
                        name = L["Max Icons"],
                        desc = L["Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 11,
                        width = "normal",
                        get = function() return addon.db.profile.maxIcons or 5 end,
                        set = function(_, val)
                            addon.db.profile.maxIcons = val
                            addon:UpdateFrameSize()
                        end
                    },
                    iconSize = {
                        type = "range",
                        name = L["Icon Size"],
                        desc = L["Icon Size desc"],
                        min = 20, max = 64, step = 2,
                        order = 12,
                        width = "normal",
                        get = function() return addon.db.profile.iconSize or 36 end,
                        set = function(_, val)
                            addon.db.profile.iconSize = val
                            addon:UpdateFrameSize()
                        end
                    },
                    iconSpacing = {
                        type = "range",
                        name = L["Spacing"],
                        desc = L["Spacing desc"],
                        min = 0, max = 10, step = 1,
                        order = 13,
                        width = "normal",
                        get = function() return addon.db.profile.iconSpacing or 2 end,
                        set = function(_, val)
                            addon.db.profile.iconSpacing = val
                            addon:UpdateFrameSize()
                        end
                    },
                    queueOrientation = {
                        type = "select",
                        name = L["Queue Orientation"],
                        desc = L["Queue Orientation desc"],
                        order = 15,
                        width = "normal",
                        values = {
                            LEFT = L["Left to Right"],
                            RIGHT = L["Right to Left"],
                            UP = L["Bottom to Top"],
                            DOWN = L["Top to Bottom"],
                        },
                        get = function() return addon.db.profile.queueOrientation or "LEFT" end,
                        set = function(_, val)
                            addon.db.profile.queueOrientation = val
                            addon:UpdateFrameSize()
                        end
                    },
                    gamepadIconStyle = {
                        type = "select",
                        name = L["Gamepad Icon Style"],
                        desc = L["Gamepad Icon Style desc"],
                        order = 16,
                        width = "normal",
                        values = {
                            generic = L["Generic"],
                            xbox = L["Xbox"],
                            playstation = L["PlayStation"],
                        },
                        get = function() return addon.db.profile.gamepadIconStyle or "xbox" end,
                        set = function(_, val)
                            addon.db.profile.gamepadIconStyle = val
                            -- Force keybind cache refresh
                            local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                            if ActionBarScanner and ActionBarScanner.ClearAllCaches then
                                ActionBarScanner.ClearAllCaches()
                            end
                        end
                    },
                    -- VISIBILITY (20-29)
                    visibilityHeader = {
                        type = "header",
                        name = L["Visibility"],
                        order = 20,
                    },
                    hideQueueOutOfCombat = {
                        type = "toggle",
                        name = L["Hide Out of Combat"],
                        desc = L["Hide Out of Combat desc"],
                        order = 21,
                        width = "full",
                        get = function() return addon.db.profile.hideQueueOutOfCombat end,
                        set = function(_, val)
                            addon.db.profile.hideQueueOutOfCombat = val
                            addon:ForceUpdate()
                        end
                    },
                    hideQueueWhenMounted = {
                        type = "toggle",
                        name = L["Hide When Mounted"],
                        desc = L["Hide When Mounted desc"],
                        order = 22,
                        width = "full",
                        get = function() return addon.db.profile.hideQueueWhenMounted end,
                        set = function(_, val)
                            addon.db.profile.hideQueueWhenMounted = val
                            addon:ForceUpdate()
                        end
                    },
                    requireHostileTarget = {
                        type = "toggle",
                        name = L["Require Hostile Target"],
                        desc = L["Require Hostile Target desc"],
                        order = 23,
                        width = "full",
                        disabled = function() return addon.db.profile.hideQueueOutOfCombat end,
                        get = function() return addon.db.profile.requireHostileTarget end,
                        set = function(_, val)
                            addon.db.profile.requireHostileTarget = val
                            addon:ForceUpdate()
                        end
                    },
                    -- APPEARANCE (30-39)
                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 30,
                    },
                    focusEmphasis = {
                        type = "toggle",
                        name = L["Highlight Primary Spell"],
                        desc = L["Highlight Primary Spell desc"],
                        order = 31,
                        width = "normal",
                        get = function() return addon.db.profile.focusEmphasis ~= false end,
                        set = function(_, val)
                            addon.db.profile.focusEmphasis = val
                            addon:ForceUpdate()
                        end
                    },
                    tooltipMode = {
                        type = "select",
                        name = L["Tooltips"],
                        desc = L["Tooltips desc"],
                        order = 32,
                        width = "normal",
                        values = {
                            never = L["Never"],
                            outOfCombat = L["Out of Combat Only"],
                            always = L["Always"],
                        },
                        sorting = {"never", "outOfCombat", "always"},
                        get = function()
                            -- Migration: convert old settings to new mode
                            if addon.db.profile.tooltipMode then
                                return addon.db.profile.tooltipMode
                            end
                            -- Migrate from old settings
                            if addon.db.profile.showTooltips == false then
                                return "never"
                            elseif addon.db.profile.tooltipsInCombat then
                                return "always"
                            else
                                return "outOfCombat"
                            end
                        end,
                        set = function(_, val)
                            addon.db.profile.tooltipMode = val
                            -- Clear old settings after migration
                            addon.db.profile.showTooltips = nil
                            addon.db.profile.tooltipsInCombat = nil
                        end
                    },
                    frameOpacity = {
                        type = "range",
                        name = L["Frame Opacity"],
                        desc = L["Frame Opacity desc"],
                        min = 0.1, max = 1.0, step = 0.05,
                        order = 33,
                        width = "normal",
                        get = function() return addon.db.profile.frameOpacity or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.frameOpacity = val
                            addon:ForceUpdate()
                        end
                    },
                    queueDesaturation = {
                        type = "range",
                        name = L["Queue Icon Fade"],
                        desc = L["Queue Icon Fade desc"],
                        min = 0, max = 1.0, step = 0.05,
                        order = 34,
                        width = "normal",
                        get = function() return addon.db.profile.queueIconDesaturation or 0 end,
                        set = function(_, val)
                            addon.db.profile.queueIconDesaturation = val
                            addon:ForceUpdate()
                        end
                    },
                    -- SYSTEM (40-49)
                    systemHeader = {
                        type = "header",
                        name = L["System"],
                        order = 40,
                    },
                    panelLocked = {
                        type = "toggle",
                        name = L["Lock Panel"],
                        desc = L["Lock Panel desc"],
                        order = 41,
                        width = "full",
                        get = function() return addon.db.profile.panelLocked or false end,
                        set = function(_, val)
                            addon.db.profile.panelLocked = val
                            local status = val and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                            addon:DebugPrint("Panel " .. status)
                        end
                    },
                }
            },
            offensive = {
                type = "group",
                name = L["Offensive"],
                order = 2,
                args = {
                    info = {
                        type = "description",
                        name = L["Offensive Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    -- QUEUE CONTENT (10-19)
                    contentHeader = {
                        type = "header",
                        name = L["Queue Content"],
                        order = 10,
                    },
                    includeHiddenAbilities = {
                        type = "toggle",
                        name = L["Include All Available Abilities"],
                        desc = L["Include All Available Abilities desc"],
                        order = 11,
                        width = "full",
                        get = function() return addon.db.profile.includeHiddenAbilities ~= false end,
                        set = function(_, val)
                            addon.db.profile.includeHiddenAbilities = val
                            addon:ForceUpdate()
                        end
                    },
                    showSpellbookProcs = {
                        type = "toggle",
                        name = L["Insert Procced Abilities"],
                        desc = L["Insert Procced Abilities desc"],
                        order = 12,
                        width = "full",
                        get = function() return addon.db.profile.showSpellbookProcs or false end,
                        set = function(_, val)
                            addon.db.profile.showSpellbookProcs = val
                            addon:ForceUpdate()
                        end
                    },
                    hideItemAbilities = {
                        type = "toggle",
                        name = L["Hide Item Abilities"],
                        desc = L["Hide Item Abilities desc"],
                        order = 13,
                        width = "full",
                        get = function() return addon.db.profile.hideItemAbilities end,
                        set = function(_, val)
                            addon.db.profile.hideItemAbilities = val
                            addon:ForceUpdate()
                        end
                    },
                    showHotkeys = {
                        type = "toggle",
                        name = L["Show Offensive Hotkeys"],
                        desc = L["Show Offensive Hotkeys desc"],
                        order = 14,
                        width = "full",
                        get = function() return addon.db.profile.showOffensiveHotkeys ~= false end,
                        set = function(_, val)
                            addon.db.profile.showOffensiveHotkeys = val
                            local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                            if ActionBarScanner and ActionBarScanner.ClearAllCaches then
                                ActionBarScanner.ClearAllCaches()
                            end
                            addon:ForceUpdate()
                        end
                    },
                    firstIconScale = {
                        type = "range",
                        name = L["Primary Spell Scale"],
                        desc = L["Primary Spell Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 15,
                        width = "normal",
                        get = function() return addon.db.profile.firstIconScale or 1.2 end,
                        set = function(_, val)
                            addon.db.profile.firstIconScale = val
                            addon:UpdateFrameSize()
                        end
                    },
                    -- BLACKLIST (20+)
                    blacklistHeader = {
                        type = "header",
                        name = L["Blacklist"],
                        order = 20,
                    },
                    blacklistInfo = {
                        type = "description",
                        name = L["Blacklist Info"],
                        order = 21,
                        fontSize = "medium"
                    },
                    -- Dynamic blacklist entries added by UpdateBlacklistOptions
                },
            },
            hotkeyOverrides = {
                type = "group",
                name = L["Hotkey Overrides"],
                order = 5,
                args = {
                    info = {
                        type = "description",
                        name = L["Hotkey Overrides Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                },
            },
            defensives = {
                type = "group",
                name = L["Defensives"],
                order = 3,
                args = {
                    info = {
                        type = "description",
                        name = L["Defensives Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = L["Defensive Icon"],
                        order = 2,
                    },
                    enabled = {
                        type = "toggle",
                        name = L["Enable Defensive Suggestions"],
                        desc = L["Enable Defensive Suggestions desc"],
                        order = 3,
                        width = "full",
                        get = function() return addon.db.profile.defensives.enabled end,
                        set = function(_, val)
                            addon.db.profile.defensives.enabled = val
                            UIManager.CreateSpellIcons(addon)
                            addon:ForceUpdateAll()
                        end
                    },
                    showProcs = {
                        type = "toggle",
                        name = L["Insert Procced Defensives"],
                        desc = L["Insert Procced Defensives desc"],
                        order = 3.5,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showProcs ~= false end,
                        set = function(_, val)
                            addon.db.profile.defensives.showProcs = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    thresholdHeader = {
                        type = "header",
                        name = L["Threshold Settings"],
                        order = 4,
                    },
                    selfHealThreshold = {
                        type = "range",
                        name = L["Self-Heal Threshold"],
                        desc = L["Self-Heal Threshold desc"],
                        min = 1, max = 100, step = 1,
                        order = 4.1,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.selfHealThreshold or 80 end,
                        set = function(_, val)
                            addon.db.profile.defensives.selfHealThreshold = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    cooldownThreshold = {
                        type = "range",
                        name = L["Major Cooldown Threshold"],
                        desc = L["Major Cooldown Threshold desc"],
                        min = 1, max = 100, step = 1,
                        order = 4.2,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.cooldownThreshold or 60 end,
                        set = function(_, val)
                            addon.db.profile.defensives.cooldownThreshold = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    petHealThreshold = {
                        type = "range",
                        name = L["Pet Heal Threshold"],
                        desc = L["Pet Heal Threshold desc"],
                        min = 1, max = 100, step = 1,
                        order = 4.3,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.petHealThreshold or 50 end,
                        set = function(_, val)
                            addon.db.profile.defensives.petHealThreshold = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    thresholdNote = {
                        type = "description",
                        name = L["Threshold Note"],
                        order = 4.9,
                        fontSize = "small",
                    },
                    behaviorHeader = {
                        type = "header",
                        name = L["Display Behavior"],
                        order = 6,
                    },
                    displayMode = {
                        type = "select",
                        name = L["Defensive Display Mode"],
                        desc = L["Defensive Display Mode desc"],
                        order = 7,
                        width = "double",
                        values = {
                            healthBased = L["When Health Low"],
                            combatOnly = L["In Combat Only"],
                            always = L["Always"],
                        },
                        sorting = {"healthBased", "combatOnly", "always"},
                        get = function()
                            -- Migration from old settings
                            if addon.db.profile.defensives.displayMode then
                                return addon.db.profile.defensives.displayMode
                            end
                            -- Convert old toggles to new mode
                            local showOnlyInCombat = addon.db.profile.defensives.showOnlyInCombat
                            local alwaysShow = addon.db.profile.defensives.alwaysShowDefensive
                            if alwaysShow and showOnlyInCombat then
                                return "combatOnly"
                            elseif alwaysShow then
                                return "always"
                            else
                                return "healthBased"
                            end
                        end,
                        set = function(_, val)
                            addon.db.profile.defensives.displayMode = val
                            -- Clear old settings
                            addon.db.profile.defensives.showOnlyInCombat = nil
                            addon.db.profile.defensives.alwaysShowDefensive = nil
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    showHealthBar = {
                        type = "toggle",
                        name = L["Show Health Bar"],
                        desc = L["Show Health Bar desc"],
                        order = 8,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showHealthBar end,
                        set = function(_, val)
                            addon.db.profile.defensives.showHealthBar = val
                            if UIManager.DestroyHealthBar then UIManager.DestroyHealthBar() end
                            if val and UIManager.CreateHealthBar then
                                UIManager.CreateHealthBar(addon)
                            end
                            -- Recreate defensive icon to update spacing based on health bar state
                            if UIManager.CreateSpellIcons then
                                UIManager.CreateSpellIcons(addon)
                            end
                            addon:ForceUpdateAll()
                        end,
                        -- Health bar works independently of defensive queue
                    },
                    position = {
                        type = "select",
                        name = L["Icon Position"],
                        desc = L["Icon Position desc"],
                        order = 9,
                        width = "normal",
                        values = {
                            SIDE1 = L["Side 1 (Health Bar)"],
                            SIDE2 = L["Side 2"],
                            LEADING = L["Leading Edge"],
                        },
                        get = function() return addon.db.profile.defensives.position or "SIDE1" end,  -- Default: SIDE1
                        set = function(_, val)
                            addon.db.profile.defensives.position = val
                            UIManager.CreateSpellIcons(addon)
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    iconScale = {
                        type = "range",
                        name = L["Defensive Icon Scale"],
                        desc = L["Defensive Icon Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 10,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.iconScale or 1.2 end,
                        set = function(_, val)
                            addon.db.profile.defensives.iconScale = val
                            UIManager.CreateSpellIcons(addon)
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    maxIcons = {
                        type = "range",
                        name = L["Defensive Max Icons"],
                        desc = L["Defensive Max Icons desc"],
                        min = 1, max = 3, step = 1,
                        order = 11,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.maxIcons or 3 end,
                        set = function(_, val)
                            addon.db.profile.defensives.maxIcons = val
                            UIManager.CreateSpellIcons(addon)
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    showHotkeys = {
                        type = "toggle",
                        name = L["Show Defensive Hotkeys"],
                        desc = L["Show Defensive Hotkeys desc"],
                        order = 8.5,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showHotkeys ~= false end,
                        set = function(_, val)
                            addon.db.profile.defensives.showHotkeys = val
                            local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                            if ActionBarScanner and ActionBarScanner.ClearAllCaches then
                                ActionBarScanner.ClearAllCaches()
                            end
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },

                    selfHealHeader = {
                        type = "header",
                        name = L["Self-Heal Priority List"],
                        order = 20,
                    },
                    selfHealInfo = {
                        type = "description",
                        name = L["Self-Heal Priority desc"],
                        order = 21,
                        fontSize = "small"
                    },
                    restoreSelfHealDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults"],
                        desc = L["Restore Class Defaults desc"],
                        order = 42,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("selfheal")
                            Options.UpdateDefensivesOptions(addon)
                        end,
                    },
                    -- Dynamic selfHealSpells entries added by UpdateDefensivesOptions
                    cooldownHeader = {
                        type = "header",
                        name = L["Major Cooldowns Priority List"],
                        order = 50,
                    },
                    cooldownInfo = {
                        type = "description",
                        name = L["Major Cooldowns Priority desc"],
                        order = 51,
                        fontSize = "small"
                    },
                    restoreCooldownDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults name"],
                        desc = L["Restore Class Defaults desc"],
                        order = 72,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("cooldown")
                            Options.UpdateDefensivesOptions(addon)
                        end,
                    },
                    -- Dynamic cooldownSpells entries added by UpdateDefensivesOptions
                },
            },
            profiles = {
                type = "group",
                name = L["Profiles"],
                desc = L["Profiles desc"],
                order = 4,
                args = {}
            },
            about = {
                type = "group",
                name = L["About"],
                order = 11,
                args = {
                    aboutHeader = {
                        type = "header",
                        name = L["About JustAssistedCombat"],
                        order = 1,
                    },
                    version = {
                        type = "description",
                        name = function()
                            local version = addon.db.global.version or "2.6"
                            return "|cff00ff00JustAssistedCombat v" .. version .. "|r\n\nEnhances WoW's Assisted Combat system with advanced features for better gameplay experience.\n\n|cffffff00Key Features:|r\n• Smart hotkey detection with custom override support\n• Advanced macro parsing with conditional modifiers\n• Intelligent spell filtering and blacklist management\n• Enhanced visual feedback and tooltips\n• Seamless integration with Blizzard's native highlights\n• Zero performance impact on global cooldowns\n\n|cffffff00How It Works:|r\nJustAC automatically detects your action bar setup and displays the recommended rotation with proper hotkeys. When automatic detection fails, you can set custom hotkey displays via right-click.\n\n|cffffff00Optional Enhancements:|r\n|cffffffff/console assistedMode 1|r - Enables Blizzard's assisted combat system\n|cffffffff/console assistedCombatHighlight 1|r - Adds native button highlighting\n\nThese console commands enhance the experience but are not required for JustAC to function."
                        end,
                        order = 2,
                        fontSize = "medium"
                    },
                    commands = {
                        type = "description",
                        name = L["Slash Commands"],
                        order = 3,
                        fontSize = "medium"
                    },
                    debugHeader = {
                        type = "header",
                        name = L["Developer"],
                        order = 10,
                    },
                    debugMode = {
                        type = "toggle",
                        name = L["Debug Mode"],
                        desc = L["Debug Mode desc"],
                        order = 11,
                        width = "full",
                        get = function() return addon.db.profile.debugMode or false end,
                        set = function(_, val)
                            addon.db.profile.debugMode = val
                            if BlizzardAPI and BlizzardAPI.RefreshDebugMode then
                                BlizzardAPI.RefreshDebugMode()
                            end
                            addon:Print("Debug: " .. (val and "ON" or "OFF"))
                        end
                    },
                }
            }
        }
    }
end

local function HandleSlashCommand(addon, input)
    if not input or input == "" or input:match("^%s*$") then
        -- Ensure defensive spells initialized before opening panel
        if addon.InitializeDefensiveSpells then
            addon:InitializeDefensiveSpells()
        end
        Options.UpdateBlacklistOptions(addon)
        Options.UpdateHotkeyOverrideOptions(addon)
        Options.UpdateDefensivesOptions(addon)
        AceConfigDialog:Open("JustAssistedCombat")
        return
    end
    
    local command, arg = input:match("^(%S+)%s*(.-)$")
    if not command then return end
    command = command:lower()
    
    local DebugCommands = LibStub("JustAC-DebugCommands", true)
    
    if command == "config" or command == "options" then
        -- Ensure defensive spells initialized before opening panel
        if addon.InitializeDefensiveSpells then
            addon:InitializeDefensiveSpells()
        end
        Options.UpdateBlacklistOptions(addon)
        Options.UpdateHotkeyOverrideOptions(addon)
        Options.UpdateDefensivesOptions(addon)
        AceConfigDialog:Open("JustAssistedCombat")
        
    elseif command == "toggle" then
        if addon.db and addon.db.profile then
            addon.db.profile.isManualMode = not addon.db.profile.isManualMode
            if addon.db.profile.isManualMode then
                addon:StopUpdates()
                addon:Print("Display paused")
            else
                addon:StartUpdates()
                addon:Print("Display resumed")
            end
        end
        
    elseif command == "debug" then
        if addon.db and addon.db.profile then
            addon.db.profile.debugMode = not addon.db.profile.debugMode
            -- Refresh cached debug mode immediately
            if BlizzardAPI and BlizzardAPI.RefreshDebugMode then
                BlizzardAPI.RefreshDebugMode()
            end
            addon:Print("Debug mode: " .. (addon.db.profile.debugMode and "ON" or "OFF"))
        end
        
    elseif command == "modules" or command == "diag" then
        if DebugCommands and DebugCommands.ModuleDiagnostics then
            DebugCommands.ModuleDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end
        
    elseif command == "find" then
        local spellName = input:match("^find%s+(.+)")
        if DebugCommands and DebugCommands.FindSpell then
            DebugCommands.FindSpell(addon, spellName)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "testcd" then
        local spellName = input:match("^testcd%s+(.+)")
        if DebugCommands and DebugCommands.TestCooldownAPIs then
            DebugCommands.TestCooldownAPIs(addon, spellName)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "reset" then
        if addon.mainFrame then
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint("CENTER", 0, -150)
            addon:SavePosition()
            addon:Print("Position reset to center")
        end
        
    elseif command == "profile" then
        local profileAction = input:match("^profile%s+(.+)")
        if DebugCommands and DebugCommands.ManageProfile then
            DebugCommands.ManageProfile(addon, profileAction)
        else
            addon:Print("DebugCommands module not available")
        end
    
    elseif command == "defensive" or command == "def" then
        if DebugCommands and DebugCommands.DefensiveDiagnostics then
            DebugCommands.DefensiveDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "poisons" or command == "poison" then
        if DebugCommands and DebugCommands.PoisonDiagnostics then
            DebugCommands.PoisonDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "help" then
        if DebugCommands and DebugCommands.ShowHelp then
            DebugCommands.ShowHelp(addon)
        else
            addon:Print("DebugCommands module not available")
        end
        
    else
        addon:Print("Unknown command. Type '/jac help' for available commands.")
    end
end

-- Add per-spec profile switching options to the profiles section
local function AddSpecProfileOptions(addon)
    local profilesArgs = addon.optionsTable.args.profiles.args
    if not profilesArgs then return end

    -- Helper to get list of profiles plus special values
    local function GetProfileValues()
        local values = {
            [""] = L["(No change)"],
        }
        -- Add all existing profiles
        local profiles = addon.db:GetProfiles()
        if profiles then
            for _, name in ipairs(profiles) do
                values[name] = name
            end
        end
        -- Add disabled option at the end
        values["DISABLED"] = L["(Disabled)"]
        return values
    end

    -- Sorting function to ensure (No change) first, profiles alphabetically, (Disabled) last
    local function GetProfileSorting()
        local order = { "" }  -- (No change) first
        local profiles = addon.db:GetProfiles()
        if profiles then
            table.sort(profiles)  -- Alphabetical order
            for _, name in ipairs(profiles) do
                table.insert(order, name)
            end
        end
        table.insert(order, "DISABLED")  -- (Disabled) always last
        return order
    end

    -- Helper to get spec name with icon (called dynamically when panel renders)
    local function GetSpecName(specIndex)
        local _, specName, _, specIcon = GetSpecializationInfo(specIndex)
        if specName then
            local iconString = specIcon and ("|T" .. specIcon .. ":16:16:0:0|t ") or ""
            return iconString .. specName
        end
        return "Spec " .. specIndex
    end

    -- Helper to check if spec exists (called dynamically)
    local function SpecExists(specIndex)
        local numSpecs = GetNumSpecializations()
        return specIndex <= numSpecs
    end

    -- Add inline group for spec-based switching
    profilesArgs.specSwitching = {
        type = "group",
        name = L["Spec-Based Switching"],
        inline = true,
        order = 100,
        args = {
            enabled = {
                type = "toggle",
                name = L["Auto-switch profile by spec"],
                order = 1,
                width = "full",
                get = function() return addon.db.char.specProfilesEnabled end,
                set = function(_, val)
                    addon.db.char.specProfilesEnabled = val
                    -- Refresh options panel to show/hide spec dropdowns
                    if AceConfigRegistry then
                        AceConfigRegistry:NotifyChange("JustAssistedCombat")
                    end
                    -- If enabling and current spec has a mapping, apply it
                    if val then
                        local currentSpec = GetSpecialization()
                        if currentSpec and addon.db.char.specProfiles[currentSpec] then
                            addon:OnSpecChange()
                        end
                    elseif addon.isDisabledMode then
                        -- If disabling feature while in disabled mode, exit it
                        addon:ExitDisabledMode()
                    end
                end,
            },
        },
    }

    -- Add spec dropdowns for all possible specs (max 4)
    -- Use dynamic hidden/name to handle specs that don't exist yet at init time
    for i = 1, 4 do
        local specIndex = i  -- Capture for closure
        profilesArgs.specSwitching.args["spec" .. i] = {
            type = "select",
            name = function() return GetSpecName(specIndex) end,
            order = 10 + i,
            width = 1.2,
            values = GetProfileValues,
            sorting = GetProfileSorting,
            hidden = function()
                return not addon.db.char.specProfilesEnabled or not SpecExists(specIndex)
            end,
            get = function()
                return addon.db.char.specProfiles[specIndex] or ""
            end,
            set = function(_, val)
                if val == "" then
                    addon.db.char.specProfiles[specIndex] = nil
                else
                    addon.db.char.specProfiles[specIndex] = val
                end
                -- If this is the current spec, apply the change
                local currentSpec = GetSpecialization()
                if currentSpec == specIndex then
                    addon:OnSpecChange()
                end
            end,
        }
    end

end

function Options.Initialize(addon)
    local AceConfig = LibStub("AceConfig-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")
    
    if not AceConfig or not AceConfigDialog then
        if addon.Print then
            addon:Print("Warning: AceConfig dependencies not found. Options panel will not be available.")
        end
        addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
        addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
        return
    end
    
    addon.optionsTable = CreateOptionsTable(addon)
    
    if AceDBOptions then
        addon.optionsTable.args.profiles = AceDBOptions:GetOptionsTable(addon.db)
        addon.optionsTable.args.profiles.order = 10

        -- Remove verbose AceDBOptions descriptions to save vertical space
        local profileArgs = addon.optionsTable.args.profiles.args
        if profileArgs then
            if profileArgs.desc then profileArgs.desc.name = "" end
            if profileArgs.descreset then profileArgs.descreset.name = "" end
            if profileArgs.choosedesc then profileArgs.choosedesc.name = "" end
            if profileArgs.copydesc then profileArgs.copydesc.name = "" end
            if profileArgs.deldesc then profileArgs.deldesc.name = "" end
            if profileArgs.resetdesc then profileArgs.resetdesc.name = "" end
        end

        -- Add per-spec profile switching to the profiles section
        AddSpecProfileOptions(addon)
    end
    
    AceConfig:RegisterOptionsTable("JustAssistedCombat", addon.optionsTable)
    -- Store the category for version-aware opening
    addon.optionsCategoryID = AceConfigDialog:AddToBlizOptions("JustAssistedCombat", "JustAssistedCombat")
    
    addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
    addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
end