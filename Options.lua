-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options Module - Provides AceConfig UI for addon settings
local Options = LibStub:NewLibrary("JustAC-Options", 30)
if not Options then return end

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
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

-- Get filtered items from action bars and bags for dropdown
-- Returns {[-itemID] = "ItemName [Item]"} — negative keys for AddSpellToList convention
local function GetFilteredActionBarItems(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()

    if filter == "" or #filter < 2 then return results end

    -- Strip item: prefix for filtering (user might type "item:5512" or just "health")
    local itemPrefixID = filter:match("^[iI]tem:(%d+)$")

    -- Build exclusion set (list stores negative values for items)
    local excluded = {}
    if excludeList then
        for _, entry in ipairs(excludeList) do
            excluded[entry] = true
        end
    end

    local seen = {}  -- deduplicate items across sources
    local count = 0
    local MAX_ITEMS = 10

    local function TryAddItem(itemID)
        if count >= MAX_ITEMS then return end
        if seen[itemID] then return end
        if excluded[-itemID] then return end  -- stored as -itemID in list

        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
        if not itemName then return end

        -- Match by name, item ID string, or exact item: prefix
        local matched = false
        if itemPrefixID then
            matched = (tostring(itemID) == itemPrefixID)
        else
            local nameLower = itemName:lower()
            local idString = tostring(itemID)
            matched = nameLower:find(filterLower, 1, true) or idString:find(filter, 1, true)
        end

        if matched then
            seen[itemID] = true
            results[-itemID] = "|cff00ccff" .. itemName .. "|r (item:" .. itemID .. ")"
            count = count + 1
        end
    end

    -- Source 1: Action bar slots (items placed on bars)
    for slot = 1, 180 do
        if count >= MAX_ITEMS then break end
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then
            TryAddItem(id)
        end
    end

    -- Source 2: Bag items (backpack + 4 bags)
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            if count >= MAX_ITEMS then break end
            local numSlots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                if count >= MAX_ITEMS then break end
                local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                if containerInfo and containerInfo.itemID then
                    TryAddItem(containerInfo.itemID)
                end
            end
        end
    end

    return results
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
        showSpellbookProcs = true, hideItemAbilities = true, showInterrupt = true, ccAllCasts = true,
        displayHeader = true, maxIcons = true, firstIconScale = true, showHotkeys = true, glowMode = true, showFlash = true,
        blacklistHeader = true, blacklistInfo = true,
        resetHeader = true, resetDefaults = true,
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
        blacklistArgs.clearAll = {
            type = "execute",
            name = L["Clear All"],
            desc = L["Clear All Blacklist desc"],
            order = 22.6,
            width = "half",
            confirm = true,
            func = function()
                wipe(blacklistedSpells)
                addon:ForceUpdate()
                Options.UpdateBlacklistOptions(addon)
            end,
        }
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

    local hotkeyOverrides = addon.db.profile.hotkeyOverrides or {}

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
        hotkeyArgs.clearAll = {
            type = "execute",
            name = L["Clear All"],
            desc = L["Clear All Hotkeys desc"],
            order = 2.6,
            width = "half",
            confirm = true,
            func = function()
                wipe(hotkeyOverrides)
                addon:ForceUpdate()
                Options.UpdateHotkeyOverrideOptions(addon)
            end,
        }
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
    
    for i, entry in ipairs(spellList) do
        local isItemEntry = (entry < 0)
        local displayName, displayIcon, cooldownInfo

        if isItemEntry then
            -- Negative entry = item ID
            local itemID = -entry
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            displayName = itemName and (itemName .. " |cff00ccff[Item]|r") or ("Item " .. itemID)
            displayIcon = itemTexture or 134400
            cooldownInfo = ""
        else
            -- Positive entry = spell ID
            local spellInfo = SpellQueue.GetCachedSpellInfo(entry)
            displayName = spellInfo and spellInfo.name or ("Spell " .. entry)
            displayIcon = spellInfo and spellInfo.iconID or 134400
            cooldownInfo = ""
            if spellInfo and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(entry)
                local duration = cdInfo and cdInfo.duration
                local isSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(duration)
                if duration and not isSecret and duration > 1.5 then
                    cooldownInfo = " |cff888888(" .. math.floor(duration) .. "s)|r"
                end
            end
        end
        
        defensivesArgs[listType .. "_" .. i] = {
            type = "group",
            name = i .. ". |T" .. displayIcon .. ":16:16:0:0|t " .. displayName .. cooldownInfo,
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

-- Helper to add a spell or item to a list (used by both dropdown and manual input)
-- Positive ID = spell, negative ID = item (stored as -itemID in the list)
local function AddSpellToList(addon, spellList, id)
    if not spellList then return false end
    if not id or id == 0 then return false end

    if id < 0 then
        -- Item entry: validate item exists
        local itemID = -id
        local itemName = GetItemInfo(itemID)
        if not itemName then
            addon:Print("Invalid item ID: " .. itemID .. " (item not found or not cached)")
            return false
        end

        -- Check if already in list
        for _, existingID in ipairs(spellList) do
            if existingID == id then
                addon:Print("Item already in list: " .. itemName)
                return false
            end
        end

        table.insert(spellList, id)
        addon:Print("Added item: " .. itemName)
        return true
    end

    -- Positive ID: spell entry (original behavior)
    -- Validate spell exists
    local spellInfo = SpellQueue.GetCachedSpellInfo(id)
    if not spellInfo or not spellInfo.name then
        addon:Print("Invalid spell ID: " .. id .. " (spell not found)")
        return false
    end

    -- Check if already in list
    for _, existingID in ipairs(spellList) do
        if existingID == id then
            addon:Print("Spell already in list: " .. spellInfo.name)
            return false
        end
    end

    table.insert(spellList, id)
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

    -- Search input field (type to filter by name or ID, or -itemID/item:ID for items)
    local allowItems = addon.db and addon.db.profile
        and addon.db.profile.defensives and addon.db.profile.defensives.allowItems == true
    local searchDesc = L["Search spell desc"]
    if allowItems then
        searchDesc = searchDesc .. "\nFor items: use -itemID or item:ID (e.g., -5512 or item:5512)"
    end
    defensivesArgs["search_input_" .. listType] = {
        type = "input",
        name = L["Add to %s"]:format(listName),
        desc = searchDesc,
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
            -- Merge item results from action bars + bags (only when allowItems is enabled)
            if addon.db and addon.db.profile
                and addon.db.profile.defensives and addon.db.profile.defensives.allowItems == true then
                local itemResults = GetFilteredActionBarItems(spellSearchFilter[listType], spellList)
                for k, v in pairs(itemResults) do
                    results[k] = v
                end
            end
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

    -- Add button for manual entry (spell ID, item:ID, -itemID, or exact name)
    local addDesc = L["Add spell dropdown desc"]
    if allowItems then
        addDesc = addDesc .. "\nFor items: use -itemID (e.g., -5512) or item:ID (e.g., item:5512)"
    end
    defensivesArgs["add_button_" .. listType] = {
        type = "execute",
        name = L["Add"],
        desc = addDesc,
        order = order + 0.2,
        width = "half",
        func = function()
            local val = (spellSearchFilter[listType] or ""):trim()
            if val == "" then return end

            local itemsEnabled = addon.db and addon.db.profile
                and addon.db.profile.defensives and addon.db.profile.defensives.allowItems == true

            -- Check for "item:ID" syntax (user-friendly alternative to negative numbers)
            local itemPrefix = val:match("^[iI]tem:(%d+)$")
            if itemPrefix then
                if not itemsEnabled then
                    addon:Print("Enable 'Allow Items in Spell Lists' to add items")
                    return
                end
                local itemID = tonumber(itemPrefix)
                if itemID and itemID > 0 then
                    if AddSpellToList(addon, spellList, -itemID) then
                        spellSearchFilter[listType] = ""
                        updateFunc()
                    end
                    return
                end
            end

            local numVal = tonumber(val)

            -- Negative number = item ID
            if numVal and numVal < 0 then
                if not itemsEnabled then
                    addon:Print("Enable 'Allow Items in Spell Lists' to add items")
                    return
                end
                if AddSpellToList(addon, spellList, numVal) then
                    spellSearchFilter[listType] = ""
                    updateFunc()
                end
                return
            end

            -- Positive number = spell ID
            local spellID = numVal

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
                    addon:Print("Spell/item not found: " .. val .. " (for items, use -itemID or item:ID)")
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

-- WoW class color codes for Options panel headers
local CLASS_COLORS = {
    DEATHKNIGHT = "FFC41E3A",
    DEMONHUNTER = "FFA330C9",
    DRUID       = "FFFF7C0A",
    EVOKER      = "FF33937F",
    HUNTER      = "FFAAD372",
    MAGE        = "FF3FC7EB",
    MONK        = "FF00FF98",
    PALADIN     = "FFF48CBA",
    PRIEST      = "FFFFFFFF",
    ROGUE       = "FFFFF468",
    SHAMAN      = "FF0070DD",
    WARLOCK     = "FF8788EE",
    WARRIOR     = "FFC69B6D",
}

function Options.UpdateDefensivesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not SpellQueue then return end

    local defensivesArgs = optionsTable.args.defensives.args

    -- Clear old dynamic entries (preserve static elements)
    local staticKeys = {
        info = true, header = true, enabled = true, showProcs = true,
        itemsHeader = true, allowItems = true, autoInsertPotions = true,
        displayHeader = true, iconScale = true, maxIcons = true, position = true,
        showHotkeys = true, glowMode = true, showFlash = true, displayMode = true, showHealthBar = true,
        showPetHealthBar = true,
        selfHealHeader = true, selfHealInfo = true, restoreSelfHealDefaults = true,
        cooldownHeader = true, cooldownInfo = true, restoreCooldownDefaults = true,
        petRezHeader = true, petRezInfo = true, restorePetRezDefaults = true,
        petHealHeader = true, petHealInfo = true, restorePetHealDefaults = true,
        classColorHeader = true,
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

    -- Resolve per-class spell lists
    local _, playerClass = UnitClass("player")
    local selfHealSpells, cooldownSpells, petRezSpells, petHealSpells
    if playerClass and defensives.classSpells and defensives.classSpells[playerClass] then
        selfHealSpells = defensives.classSpells[playerClass].selfHealSpells
        cooldownSpells = defensives.classSpells[playerClass].cooldownSpells
        petRezSpells = defensives.classSpells[playerClass].petRezSpells
        petHealSpells = defensives.classSpells[playerClass].petHealSpells
    end

    -- Determine if this is a pet class (has rez or heal defaults)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local isPetClass = SpellDB and (
        (SpellDB.CLASS_PET_REZ_DEFAULTS and SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass])
        or (SpellDB.CLASS_PETHEAL_DEFAULTS and SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass])
    )

    -- Inject class-colored header so user knows which class spells they're editing
    local className = playerClass and (UnitClass("player")) or "Unknown"
    local colorCode = (playerClass and CLASS_COLORS[playerClass]) or "FFFFFFFF"
    defensivesArgs.classColorHeader = {
        type = "description",
        name = "|c" .. colorCode .. className .. "|r Defensive Spells",
        fontSize = "large",
        order = 19.5,
    }

    -- Self-heal spells (order 22.0-39.9, allowing 180 entries)
    CreateSpellListEntries(addon, defensivesArgs, selfHealSpells, "selfheal", 22)
    CreateAddSpellInput(addon, defensivesArgs, selfHealSpells, "selfheal", 40, "Self-Heals")

    -- Cooldown spells (order 52.0-69.9, allowing 180 entries)  
    CreateSpellListEntries(addon, defensivesArgs, cooldownSpells, "cooldown", 52)
    CreateAddSpellInput(addon, defensivesArgs, cooldownSpells, "cooldown", 70, "Cooldowns")

    -- Pet Rez/Summon spells (order 82.0-99.9, pet classes only)
    if isPetClass and petRezSpells then
        CreateSpellListEntries(addon, defensivesArgs, petRezSpells, "petrez", 82)
        CreateAddSpellInput(addon, defensivesArgs, petRezSpells, "petrez", 100, "Pet Rez/Summon")
    end

    -- Pet Heal spells (order 112.0-129.9, pet classes only)
    if isPetClass and petHealSpells then
        CreateSpellListEntries(addon, defensivesArgs, petHealSpells, "petheal", 112)
        CreateAddSpellInput(addon, defensivesArgs, petHealSpells, "petheal", 130, "Pet Heals")
    end
    
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
                    displayMode = {
                        type = "select",
                        name = L["Display Mode"],
                        desc = L["Display Mode desc"],
                        order = 2,
                        width = "normal",
                        values = {
                            disabled = L["Disabled"],
                            queue    = L["Standard Queue"],
                            overlay  = L["Nameplate Overlay"],
                            both     = L["Both"],
                        },
                        sorting = { "disabled", "queue", "overlay", "both" },
                        get = function() return addon.db.profile.displayMode or "queue" end,
                        set = function(_, val)
                            addon.db.profile.displayMode = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then
                                NPO.Destroy(addon)
                                if val == "overlay" or val == "both" then
                                    NPO.Create(addon)
                                end
                            end
                            addon:ForceUpdate()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                    -- ICON LAYOUT (10-19)
                    layoutHeader = {
                        type = "header",
                        name = L["Icon Layout"],
                        order = 10,
                    },
                    iconSize = {
                        type = "range",
                        name = L["Icon Size"],
                        desc = L["Icon Size desc"],
                        min = 20, max = 64, step = 2,
                        order = 12,
                        width = "normal",
                        get = function() return addon.db.profile.iconSize or 42 end,
                        set = function(_, val)
                            addon.db.profile.iconSize = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    iconSpacing = {
                        type = "range",
                        name = L["Spacing"],
                        desc = L["Spacing desc"],
                        min = 0, max = 10, step = 1,
                        order = 13,
                        width = "normal",
                        get = function() return addon.db.profile.iconSpacing or 1 end,
                        set = function(_, val)
                            addon.db.profile.iconSpacing = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                            -- Reset target frame anchor if it's invalid for the new axis
                            local isHorizontal = (val == "LEFT" or val == "RIGHT")
                            local anchor = addon.db.profile.targetFrameAnchor or "DISABLED"
                            if isHorizontal and (anchor == "LEFT" or anchor == "RIGHT") then
                                addon.db.profile.targetFrameAnchor = "DISABLED"
                                addon:UpdateTargetFrameAnchor()
                            elseif not isHorizontal and (anchor == "TOP" or anchor == "BOTTOM") then
                                addon.db.profile.targetFrameAnchor = "DISABLED"
                                addon:UpdateTargetFrameAnchor()
                            end
                            -- Migrate LEADING to SIDE1 (no longer a valid option)
                            if addon.db.profile.defensives.position == "LEADING" then
                                addon.db.profile.defensives.position = "SIDE1"
                            end
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    targetFrameAnchor = {
                        type = "select",
                        name = L["Target Frame Anchor"],
                        desc = L["Target Frame Anchor desc"],
                        order = 16,
                        width = "normal",
                        values = function()
                            local o = addon.db.profile.queueOrientation or "LEFT"
                            if o == "LEFT" or o == "RIGHT" then
                                local buffsOnTop = TargetFrame and TargetFrame.buffsOnTop
                                if buffsOnTop == true then
                                    return { DISABLED = L["Disabled"], BOTTOM = L["Bottom"] }
                                elseif buffsOnTop == false then
                                    return { DISABLED = L["Disabled"], TOP = L["Top"] }
                                else
                                    return { DISABLED = L["Disabled"], TOP = L["Top"], BOTTOM = L["Bottom"] }
                                end
                            else
                                return { DISABLED = L["Disabled"], LEFT = L["Left"], RIGHT = L["Right"] }
                            end
                        end,
                        sorting = function()
                            local o = addon.db.profile.queueOrientation or "LEFT"
                            if o == "LEFT" or o == "RIGHT" then
                                local buffsOnTop = TargetFrame and TargetFrame.buffsOnTop
                                if buffsOnTop == true then
                                    return { "DISABLED", "BOTTOM" }
                                elseif buffsOnTop == false then
                                    return { "DISABLED", "TOP" }
                                else
                                    return { "DISABLED", "TOP", "BOTTOM" }
                                end
                            else
                                return { "DISABLED", "LEFT", "RIGHT" }
                            end
                        end,
                        get = function() return addon.db.profile.targetFrameAnchor or "DISABLED" end,
                        set = function(_, val)
                            addon.db.profile.targetFrameAnchor = val
                            addon:UpdateTargetFrameAnchor()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return addon.db.profile.hideQueueOutOfCombat
                                or dm == "disabled" or dm == "overlay"
                        end,
                        get = function() return addon.db.profile.requireHostileTarget end,
                        set = function(_, val)
                            addon.db.profile.requireHostileTarget = val
                            addon:ForceUpdate()
                        end
                    },
                    showHealthBar = {
                        type = "toggle",
                        name = function()
                            if addon.db.profile.defensives.enabled then
                                return L["Show Health Bar"] .. "  |cff888888(" .. L["disabled when Defensive Queue is enabled"] .. ")|r"
                            end
                            return L["Show Health Bar"]
                        end,
                        desc = L["Show Health Bar desc"],
                        order = 24,
                        width = "full",
                        get = function() return addon.db.profile.showHealthBar end,
                        set = function(_, val)
                            addon.db.profile.showHealthBar = val
                            if UIHealthBar and UIHealthBar.Destroy then
                                UIHealthBar.Destroy()
                            end
                            if val and UIHealthBar and UIHealthBar.CreateHealthBar then
                                UIHealthBar.CreateHealthBar(addon)
                            end
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            if dm == "disabled" or dm == "overlay" then return true end
                            return addon.db.profile.defensives.enabled
                        end,
                    },
                    -- APPEARANCE (30-39)
                    appearanceHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 30,
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
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    gamepadIconStyle = {
                        type = "select",
                        name = L["Gamepad Icon Style"],
                        desc = L["Gamepad Icon Style desc"],
                        order = 35,
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
                        end,
                        -- Applies to both queue and overlay hotkeys; only useless when fully disabled
                        disabled = function()
                            return (addon.db.profile.displayMode or "queue") == "disabled"
                        end,
                    },
                    -- SYSTEM (40-49)
                    systemHeader = {
                        type = "header",
                        name = L["System"],
                        order = 40,
                    },
                    panelInteraction = {
                        type = "select",
                        name = L["Panel Interaction"],
                        desc = L["Panel Interaction desc"],
                        order = 41,
                        width = "normal",
                        values = {
                            unlocked = L["Unlocked"],
                            locked = L["Locked"],
                            clickthrough = L["Click Through"],
                        },
                        sorting = { "unlocked", "locked", "clickthrough" },
                        get = function()
                            local profile = addon.db.profile
                            return profile.panelInteraction or (profile.panelLocked and "locked" or "unlocked")
                        end,
                        set = function(_, val)
                            addon.db.profile.panelInteraction = val
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    -- RESET (990+)
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset General desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local p = addon.db.profile
                            p.displayMode           = "queue"
                            p.iconSize              = 42
                            p.iconSpacing           = 1
                            p.queueOrientation      = "LEFT"
                            p.targetFrameAnchor     = "DISABLED"
                            p.hideQueueOutOfCombat  = false
                            p.hideQueueWhenMounted  = false
                            p.requireHostileTarget  = false
                            p.tooltipMode           = "always"
                            p.frameOpacity          = 1.0
                            p.queueIconDesaturation = 0
                            p.gamepadIconStyle      = "xbox"
                            p.panelInteraction      = "unlocked"
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon) end  -- displayMode reset to "queue"
                            addon:UpdateFrameSize()
                            Options.UpdateDefensivesOptions(addon)
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                }
            },
            offensive = {
                type = "group",
                name = L["Offensive"],
                order = 3,
                args = {
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
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    hideItemAbilities = {
                        type = "toggle",
                        name = L["Allow Item Abilities"],
                        desc = L["Allow Item Abilities desc"],
                        order = 13,
                        width = "full",
                        get = function() return not addon.db.profile.hideItemAbilities end,
                        set = function(_, val)
                            addon.db.profile.hideItemAbilities = not val
                            addon:ForceUpdate()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    showInterrupt = {
                        type = "select",
                        name = L["Interrupt Mode"],
                        desc = L["Interrupt Mode desc"],
                        order = 14,
                        width = "double",
                        values = {
                            important = L["Interrupt Important"],
                            all       = L["Interrupt All"],
                            off       = L["Interrupt Off"],
                        },
                        sorting = { "important", "all", "off" },
                        get = function() return addon.db.profile.interruptMode or "important" end,
                        set = function(_, val)
                            addon.db.profile.interruptMode = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    ccAllCasts = {
                        type = "toggle",
                        name = L["CC All Casts"],
                        desc = L["CC All Casts desc"],
                        order = 14.5,
                        width = "double",
                        get = function() return addon.db.profile.ccAllCasts end,
                        set = function(_, val)
                            addon.db.profile.ccAllCasts = val
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            if dm == "disabled" or dm == "overlay" then return true end
                            return (addon.db.profile.interruptMode or "important") == "off"
                        end,
                    },
                    -- DISPLAY (15-19)
                    displayHeader = {
                        type = "header",
                        name = L["Display"],
                        order = 15,
                    },
                    maxIcons = {
                        type = "range",
                        name = L["Max Icons"],
                        desc = L["Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 15.5,
                        width = "normal",
                        get = function() return addon.db.profile.maxIcons or 4 end,
                        set = function(_, val)
                            addon.db.profile.maxIcons = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    firstIconScale = {
                        type = "range",
                        name = L["Primary Spell Scale"],
                        desc = L["Primary Spell Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 16,
                        width = "normal",
                        get = function() return addon.db.profile.firstIconScale or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.firstIconScale = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    showHotkeys = {
                        type = "toggle",
                        name = L["Show Offensive Hotkeys"],
                        desc = L["Show Offensive Hotkeys desc"],
                        order = 17,
                        width = "full",
                        get = function() return addon.db.profile.showOffensiveHotkeys ~= false end,
                        set = function(_, val)
                            addon.db.profile.showOffensiveHotkeys = val
                            local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                            if ActionBarScanner and ActionBarScanner.ClearAllCaches then
                                ActionBarScanner.ClearAllCaches()
                            end
                            addon:ForceUpdate()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    glowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 18,
                        width = "normal",
                        values = {
                            all = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly = L["Proc Only"],
                            none = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function() return addon.db.profile.glowMode or "all" end,
                        set = function(_, val)
                            addon.db.profile.glowMode = val
                            addon:ForceUpdate()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
                    showFlash = {
                        type = "toggle",
                        name = L["Show Key Press Flash"],
                        desc = L["Show Key Press Flash desc"],
                        order = 19,
                        width = "full",
                        get = function() return addon.db.profile.showFlash ~= false end,
                        set = function(_, val)
                            addon.db.profile.showFlash = val
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
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
                    -- RESET (990+)
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Offensive desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local p = addon.db.profile
                            p.maxIcons               = 4
                            p.firstIconScale         = 1.0
                            p.showOffensiveHotkeys   = true
                            p.glowMode               = "all"
                            p.showFlash              = true
                            p.includeHiddenAbilities = true
                            p.showSpellbookProcs     = true
                            p.hideItemAbilities      = false
                            p.interruptMode          = "important"
                            addon:UpdateFrameSize()
                            addon:ForceUpdate()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm == "disabled" or dm == "overlay"
                        end,
                    },
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
            nameplateOverlay = {
                type = "group",
                name = L["Nameplate Overlay"],
                order = 2,
                args = {
                    info = {
                        type = "description",
                        name = L["Nameplate Overlay desc"],
                        order = 1,
                        fontSize = "medium",
                    },
                    reverseAnchor = {
                        type = "toggle",
                        name = L["Reverse Anchor"],
                        desc = L["Reverse Anchor desc"],
                        order = 2,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.reverseAnchor end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.reverseAnchor = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    healthBarPosition = {
                        type = "select",
                        name = L["Health Bar Position"],
                        desc = L["Health Bar Position desc"],
                        order = 25,
                        width = "normal",
                        values = {
                            outside = L["Outside"],
                            inside  = L["Inside"],
                        },
                        sorting = { "outside", "inside" },
                        get = function() return addon.db.profile.nameplateOverlay.healthBarPosition or "outside" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.healthBarPosition = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            if dm ~= "overlay" and dm ~= "both" then return true end
                            local npo = addon.db.profile.nameplateOverlay
                            if not npo.showDefensives or not npo.showHealthBar then return true end
                            -- Only meaningful for vertical expansion (up/down)
                            return (npo.expansion or "out") == "out"
                        end,
                    },
                    expansion = {
                        type = "select",
                        name = L["Expansion Direction"],
                        desc = L["Expansion Direction desc"],
                        order = 3,
                        width = "normal",
                        values = {
                            out  = L["Horizontal (Out)"],
                            up   = L["Vertical - Up"],
                            down = L["Vertical - Down"],
                        },
                        sorting = { "out", "up", "down" },
                        get = function() return addon.db.profile.nameplateOverlay.expansion or "out" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.expansion = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    maxIcons = {
                        type = "select",
                        name = L["Offensive Slots"],
                        order = 13,
                        width = "normal",
                        values = { [1] = "1", [2] = "2", [3] = "3", [4] = "4", [5] = "5" },
                        sorting = { 1, 2, 3, 4, 5 },
                        get = function() return addon.db.profile.nameplateOverlay.maxIcons or 1 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.maxIcons = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    iconSize = {
                        type = "range",
                        name = L["Nameplate Icon Size"],
                        order = 5,
                        width = "normal",
                        min = 16, max = 48, step = 2,
                        get = function() return addon.db.profile.nameplateOverlay.iconSize or 26 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.iconSize = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    iconSpacing = {
                        type = "range",
                        name = L["Spacing"],
                        order = 6,
                        width = "normal",
                        min = 0, max = 10, step = 1,
                        get = function() return addon.db.profile.nameplateOverlay.iconSpacing or 2 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.iconSpacing = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    opacity = {
                        type = "range",
                        name = L["Frame Opacity"],
                        order = 7,
                        width = "normal",
                        min = 0.1, max = 1.0, step = 0.05,
                        get = function() return addon.db.profile.nameplateOverlay.opacity or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.opacity = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    showGlow = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 8,
                        width = "normal",
                        values = {
                            all         = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly    = L["Proc Only"],
                            none        = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function()
                            local npo = addon.db.profile.nameplateOverlay
                            -- migrate old showGlow boolean to glowMode string
                            if npo.glowMode then return npo.glowMode end
                            return npo.showGlow ~= false and "all" or "none"
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.glowMode = val
                            addon.db.profile.nameplateOverlay.showGlow = nil  -- clear legacy key
                            addon:ForceUpdateAll()  -- must trigger OnHealthChanged to re-run RenderDefensives
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    showHotkey = {
                        type = "toggle",
                        name = L["Show Hotkeys"],
                        order = 9,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.showHotkey end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showHotkey = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    showFlash = {
                        type = "toggle",
                        name = L["Show Key Press Flash"],
                        order = 10,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.showFlash ~= false end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showFlash = val
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    offensiveSectionHeader = {
                        type = "header",
                        name = L["Offensive Queue"],
                        order = 11,
                    },
                    showInterrupt = {
                        type = "select",
                        name = L["Interrupt Mode"],
                        desc = L["Interrupt Mode desc"],
                        order = 12,
                        width = "double",
                        values = {
                            important = L["Interrupt Important"],
                            all       = L["Interrupt All"],
                            off       = L["Interrupt Off"],
                        },
                        sorting = { "important", "all", "off" },
                        get = function() return addon.db.profile.nameplateOverlay.interruptMode or "important" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.interruptMode = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    npoCCAllCasts = {
                        type = "toggle",
                        name = L["CC All Casts"],
                        desc = L["CC All Casts desc"],
                        order = 12.5,
                        width = "double",
                        get = function() return addon.db.profile.nameplateOverlay.ccAllCasts end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.ccAllCasts = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            if dm ~= "overlay" and dm ~= "both" then return true end
                            return (addon.db.profile.nameplateOverlay.interruptMode or "important") == "off"
                        end,
                    },
                    defensiveSectionHeader = {
                        type = "header",
                        name = L["Defensive Suggestions"],
                        order = 20,
                    },
                    showDefensives = {
                        type = "toggle",
                        name = L["Nameplate Show Defensives"],
                        desc = L["Nameplate Show Defensives desc"],
                        order = 21,
                        width = "full",
                        get = function() return addon.db.profile.nameplateOverlay.showDefensives end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showDefensives = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    defensiveDisplayMode = {
                        type = "select",
                        name = L["Nameplate Defensive Display Mode"],
                        desc = L["Nameplate Defensive Display Mode desc"],
                        order = 22,
                        width = "normal",
                        values = {
                            combatOnly = L["In Combat Only"],
                            always     = L["Always"],
                        },
                        sorting = { "combatOnly", "always" },
                        get = function() return addon.db.profile.nameplateOverlay.defensiveDisplayMode or "combatOnly" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.defensiveDisplayMode = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return (dm ~= "overlay" and dm ~= "both")
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                    },
                    maxDefensiveIcons = {
                        type = "select",
                        name = L["Nameplate Defensive Count"],
                        order = 23,
                        width = "normal",
                        values = { [1] = "1", [2] = "2", [3] = "3", [4] = "4", [5] = "5" },
                        sorting = { 1, 2, 3, 4, 5 },
                        get = function() return addon.db.profile.nameplateOverlay.maxDefensiveIcons or 1 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.maxDefensiveIcons = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return (dm ~= "overlay" and dm ~= "both")
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                    },
                    showHealthBar = {
                        type = "toggle",
                        name = L["Nameplate Show Health Bar"],
                        desc = L["Nameplate Show Health Bar desc"],
                        order = 24,
                        width = "full",
                        get = function() return addon.db.profile.nameplateOverlay.showHealthBar end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showHealthBar = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                    -- RESET (990+)
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Overlay desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local npo = addon.db.profile.nameplateOverlay
                            wipe(npo)
                            npo.maxIcons             = 3
                            npo.reverseAnchor        = false
                            npo.expansion            = "out"
                            npo.healthBarPosition    = "outside"
                            npo.iconSize             = 32
                            npo.iconSpacing          = 2
                            npo.opacity              = 1.0
                            npo.showGlow             = true
                            npo.glowMode             = "all"
                            npo.showHotkey           = true
                            npo.showFlash            = true
                            npo.showDefensives       = true
                            npo.maxDefensiveIcons    = 3
                            npo.defensiveDisplayMode = "combatOnly"
                            npo.showHealthBar        = true
                            npo.interruptMode        = "important"
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                        disabled = function()
                            local dm = addon.db.profile.displayMode or "queue"
                            return dm ~= "overlay" and dm ~= "both"
                        end,
                    },
                },
            },
            defensives = {
                type = "group",
                name = L["Defensives"],
                order = 4,
                args = {
                    -- QUEUE CONTENT (2-4)
                    header = {
                        type = "header",
                        name = L["Queue Content"],
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
                            addon:UpdateFrameSize()
                        end
                    },
                    showProcs = {
                        type = "toggle",
                        name = L["Insert Procced Defensives"],
                        desc = L["Insert Procced Defensives desc"],
                        order = 4,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showProcs ~= false end,
                        set = function(_, val)
                            addon.db.profile.defensives.showProcs = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    -- ITEMS (4.3-4.9)
                    itemsHeader = {
                        type = "header",
                        name = L["Items"],
                        order = 4.3,
                    },
                    allowItems = {
                        type = "toggle",
                        name = L["Allow Items in Spell Lists"],
                        desc = L["Allow Items in Spell Lists desc"],
                        order = 4.5,
                        width = "full",
                        get = function() return addon.db.profile.defensives.allowItems == true end,
                        set = function(_, val)
                            addon.db.profile.defensives.allowItems = val
                            Options.UpdateDefensivesOptions(addon)
                        end,
                        disabled = function()
                            return not addon.db.profile.defensives.enabled
                        end,
                    },
                    autoInsertPotions = {
                        type = "toggle",
                        name = L["Auto-Insert Health Potions"],
                        desc = L["Auto-Insert Health Potions desc"],
                        order = 4.6,
                        width = "full",
                        get = function() return addon.db.profile.defensives.autoInsertPotions ~= false end,
                        set = function(_, val)
                            addon.db.profile.defensives.autoInsertPotions = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            return not addon.db.profile.defensives.enabled
                        end,
                    },
                    -- DISPLAY (5-9)
                    displayHeader = {
                        type = "header",
                        name = L["Display"],
                        order = 5,
                    },
                    maxIcons = {
                        type = "range",
                        name = L["Defensive Max Icons"],
                        desc = L["Defensive Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 6,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.maxIcons or 3 end,
                        set = function(_, val)
                            addon.db.profile.defensives.maxIcons = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    iconScale = {
                        type = "range",
                        name = L["Defensive Icon Scale"],
                        desc = L["Defensive Icon Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 6.5,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.iconScale or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.defensives.iconScale = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    position = {
                        type = "select",
                        name = L["Icon Position"],
                        desc = L["Icon Position desc"],
                        order = 7,
                        width = "normal",
                        values = function()
                            local o = addon.db.profile.queueOrientation or "LEFT"
                            if o == "LEFT" or o == "RIGHT" then
                                return { SIDE1 = L["Top"], SIDE2 = L["Bottom"] }
                            else
                                return { SIDE1 = L["Right"], SIDE2 = L["Left"] }
                            end
                        end,
                        sorting = { "SIDE1", "SIDE2" },
                        get = function() return addon.db.profile.defensives.position or "SIDE1" end,
                        set = function(_, val)
                            addon.db.profile.defensives.position = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    showHotkeys = {
                        type = "toggle",
                        name = L["Show Defensive Hotkeys"],
                        desc = L["Show Defensive Hotkeys desc"],
                        order = 7.5,
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
                    glowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 7.6,
                        width = "normal",
                        values = {
                            all = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly = L["Proc Only"],
                            none = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function() return addon.db.profile.defensives.glowMode or "all" end,
                        set = function(_, val)
                            addon.db.profile.defensives.glowMode = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    showFlash = {
                        type = "toggle",
                        name = L["Show Key Press Flash"],
                        desc = L["Show Key Press Flash desc"],
                        order = 7.7,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showFlash ~= false end,
                        set = function(_, val)
                            addon.db.profile.defensives.showFlash = val
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    displayMode = {
                        type = "select",
                        name = L["Defensive Display Mode"],
                        desc = L["Defensive Display Mode desc"],
                        order = 8,
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
                        order = 9,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showHealthBar end,
                        set = function(_, val)
                            addon.db.profile.defensives.showHealthBar = val
                            addon:UpdateFrameSize()
                        end,
                        -- Health bar works independently of defensive queue
                    },
                    showPetHealthBar = {
                        type = "toggle",
                        name = L["Show Pet Health Bar"],
                        desc = L["Show Pet Health Bar desc"],
                        order = 9.5,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showPetHealthBar end,
                        set = function(_, val)
                            addon.db.profile.defensives.showPetHealthBar = val
                            addon:UpdateFrameSize()
                        end,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            if not SDB or not pc then return true end
                            return not ((SDB.CLASS_PET_REZ_DEFAULTS and SDB.CLASS_PET_REZ_DEFAULTS[pc])
                                or (SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc]))
                        end,
                    },
                    -- SELF-HEAL PRIORITY LIST (20+)
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
                        desc = L["Restore Cooldowns Defaults desc"],
                        order = 72,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("cooldown")
                            Options.UpdateDefensivesOptions(addon)
                        end,
                    },
                    -- Dynamic cooldownSpells entries added by UpdateDefensivesOptions
                    -- PET REZ/SUMMON PRIORITY LIST (80+, pet classes only)
                    petRezHeader = {
                        type = "header",
                        name = L["Pet Rez/Summon Priority List"],
                        order = 80,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PET_REZ_DEFAULTS and SDB.CLASS_PET_REZ_DEFAULTS[pc])
                        end,
                    },
                    petRezInfo = {
                        type = "description",
                        name = L["Pet Rez/Summon Priority desc"],
                        order = 81,
                        fontSize = "small",
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PET_REZ_DEFAULTS and SDB.CLASS_PET_REZ_DEFAULTS[pc])
                        end,
                    },
                    restorePetRezDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults name"],
                        desc = L["Restore Pet Rez Defaults desc"],
                        order = 102,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("petrez")
                            Options.UpdateDefensivesOptions(addon)
                        end,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PET_REZ_DEFAULTS and SDB.CLASS_PET_REZ_DEFAULTS[pc])
                        end,
                    },
                    -- Dynamic petRezSpells entries added by UpdateDefensivesOptions
                    -- PET HEAL PRIORITY LIST (110+, pet classes only)
                    petHealHeader = {
                        type = "header",
                        name = L["Pet Heal Priority List"],
                        order = 110,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc])
                        end,
                    },
                    petHealInfo = {
                        type = "description",
                        name = L["Pet Heal Priority desc"],
                        order = 111,
                        fontSize = "small",
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc])
                        end,
                    },
                    restorePetHealDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults name"],
                        desc = L["Restore Pet Heal Defaults desc"],
                        order = 132,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("petheal")
                            Options.UpdateDefensivesOptions(addon)
                        end,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc])
                        end,
                    },
                    -- Dynamic petHealSpells entries added by UpdateDefensivesOptions
                    -- RESET (990+)
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Defensives desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local def = addon.db.profile.defensives
                            -- Synced with JustAC.lua profile defaults
                            def.enabled          = true
                            def.showProcs        = true
                            def.glowMode         = "all"
                            def.showFlash        = true
                            def.showHotkeys      = true
                            def.position         = "SIDE1"
                            def.showHealthBar    = true
                            def.showPetHealthBar = true
                            def.iconScale        = 1.0
                            def.maxIcons         = 4
                            def.selfHealThreshold = 80
                            def.cooldownThreshold = 60
                            def.petHealThreshold  = 50
                            def.allowItems        = true
                            def.autoInsertPotions = true
                            def.displayMode       = "always"
                            addon:UpdateFrameSize()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                },
            },
            profiles = {
                type = "group",
                name = L["Profiles"],
                desc = L["Profiles desc"],
                order = 6,
                args = {}
            },
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
            -- Re-apply target frame anchor if enabled
            addon:UpdateTargetFrameAnchor()
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