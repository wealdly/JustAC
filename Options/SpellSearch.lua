-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/SpellSearch - Shared spellbook cache, search/filter, spell list management
local SpellSearch = LibStub:NewLibrary("JustAC-OptionsSpellSearch", 1)
if not SpellSearch then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Hot path cache
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
local type = type
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs

-------------------------------------------------------------------------------
-- Spellbook cache for autocomplete (populated on first options open)
-------------------------------------------------------------------------------
local spellbookCache = {}  -- {spellID = {name = "Spell Name", icon = iconID}, ...}
local spellbookCacheBuilt = false

-- Filter state for spell search (all panels)
SpellSearch.filterState = {
    defensive  = "",
    selfheal   = "",
    cooldown   = "",
    blacklist  = "",
    hotkey     = "",
    petrez     = "",
    petheal    = "",
    gapcloser  = "",
    meleerange = "",
}

-- Preview state: first result shown in dropdown (not yet added)
SpellSearch.previewState = {
    defensive  = nil,
    selfheal   = nil,
    cooldown   = nil,
    blacklist  = nil,
    hotkey     = nil,
    petrez     = nil,
    petheal    = nil,
    gapcloser  = nil,
    meleerange = nil,
}

-- Storage for hotkey value input (not spell search)
SpellSearch.addHotkeyValueInput = ""

-- WoW class color codes for Options panel headers
SpellSearch.CLASS_COLORS = {
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

-------------------------------------------------------------------------------
-- Build spellbook cache (called once when options panel opens)
-------------------------------------------------------------------------------
function SpellSearch.BuildSpellbookCache()
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

-------------------------------------------------------------------------------
-- Get filtered items from action bars and bags for dropdown
-- Returns {[-itemID] = "ItemName [Item]"} — negative keys for AddSpellToList convention
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredActionBarItems(filterText, excludeList)
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

-------------------------------------------------------------------------------
-- Get filtered spells for dropdown based on search text
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredSpellbookSpells(filterText, excludeList)
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

-------------------------------------------------------------------------------
-- Helper to look up spell ID from name
-------------------------------------------------------------------------------
function SpellSearch.LookupSpellByName(spellName)
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

-------------------------------------------------------------------------------
-- Helper to add a spell or item to a list (used by both dropdown and manual input)
-- Positive ID = spell, negative ID = item (stored as -itemID in the list)
-------------------------------------------------------------------------------
function SpellSearch.AddSpellToList(addon, spellList, id)
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
    local spellInfo = BlizzardAPI.GetCachedSpellInfo(id)
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

-------------------------------------------------------------------------------
-- Helper to create spell list entries for a given list (defensives/etc.)
-------------------------------------------------------------------------------
function SpellSearch.CreateSpellListEntries(addon, defensivesArgs, spellList, listType, baseOrder, updateFunc)
    if not spellList then return end

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
            local spellInfo = BlizzardAPI.GetCachedSpellInfo(entry)
            displayName = spellInfo and spellInfo.name or ("Spell " .. entry)
            displayIcon = spellInfo and spellInfo.iconID or 134400
            cooldownInfo = ""
            if spellInfo and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(entry)
                local duration = cdInfo and cdInfo.duration
                local isSecret = BlizzardAPI.IsSecretValue(duration)
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

-------------------------------------------------------------------------------
-- Helper to create add spell input with autocomplete dropdown
-------------------------------------------------------------------------------
function SpellSearch.CreateAddSpellInput(addon, defensivesArgs, spellList, listType, order, listName, updateFunc)
    SpellSearch.BuildSpellbookCache()
    SpellSearch.filterState[listType] = SpellSearch.filterState[listType] or ""

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
        get = function() return SpellSearch.filterState[listType] or "" end,
        set = function(_, val)
            SpellSearch.filterState[listType] = val or ""
            -- Refresh options to update dropdown
            if AceConfigRegistry then
                AceConfigRegistry:NotifyChange("JustAssistedCombat")
            end
        end
    }

    defensivesArgs["search_dropdown_" .. listType] = {
        type = "select",
        name = "",
        desc = L["Select spell to add"],
        order = order + 0.1,
        width = "double",
        values = function()
            local results = SpellSearch.GetFilteredSpellbookSpells(SpellSearch.filterState[listType], spellList)
            if addon.db and addon.db.profile
                and addon.db.profile.defensives and addon.db.profile.defensives.allowItems == true then
                local itemResults = SpellSearch.GetFilteredActionBarItems(SpellSearch.filterState[listType], spellList)
                for k, v in pairs(itemResults) do
                    results[k] = v
                end
            end
            -- If no results and filter looks like valid input, show helper text
            local filter = (SpellSearch.filterState[listType] or ""):trim()
            if next(results) == nil and #filter >= 2 then
                SpellSearch.previewState[listType] = nil
                return {[0] = "|cff888888" .. L["No matches"] .. "|r"}
            end
            SpellSearch.previewState[listType] = next(results)
            return results
        end,
        get = function() return SpellSearch.previewState[listType] end,  -- Show first result as preview
        set = function(_, spellID)
            if spellID == 0 then return end  -- Ignore "no matches" placeholder
            if SpellSearch.AddSpellToList(addon, spellList, spellID) then
                SpellSearch.filterState[listType] = ""  -- Clear search
                SpellSearch.previewState[listType] = nil  -- Clear preview
                updateFunc()
            end
        end,
        disabled = function()
            local filter = (SpellSearch.filterState[listType] or ""):trim()
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
            local val = (SpellSearch.filterState[listType] or ""):trim()
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
                    if SpellSearch.AddSpellToList(addon, spellList, -itemID) then
                        SpellSearch.filterState[listType] = ""
                        updateFunc()
                    end
                    return
                end
            end

            local numVal = tonumber(val)

            if numVal and numVal < 0 then
                if not itemsEnabled then
                    addon:Print("Enable 'Allow Items in Spell Lists' to add items")
                    return
                end
                if SpellSearch.AddSpellToList(addon, spellList, numVal) then
                    SpellSearch.filterState[listType] = ""
                    updateFunc()
                end
                return
            end

            local spellID = numVal

            if not spellID then
                spellID = SpellSearch.LookupSpellByName(val)
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

            if SpellSearch.AddSpellToList(addon, spellList, spellID) then
                SpellSearch.filterState[listType] = ""  -- Clear input
                updateFunc()
            end
        end,
        disabled = function()
            local filter = (SpellSearch.filterState[listType] or ""):trim()
            return #filter < 1
        end,
    }
end
