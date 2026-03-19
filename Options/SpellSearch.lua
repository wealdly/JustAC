-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/SpellSearch - Shared spellbook cache, search/filter, spell list management
local SpellSearch = LibStub:NewLibrary("JustAC-OptionsSpellSearch", 1)
if not SpellSearch then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Hot path locals
local wipe = wipe
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local GetInventoryItemID = GetInventoryItemID
local C_Container = C_Container

-------------------------------------------------------------------------------
-- Spellbook cache for autocomplete (populated on first options open)
-------------------------------------------------------------------------------
local spellbookCache = {}  -- {spellID = {name = "Spell Name", icon = iconID}, ...}
local spellbookCacheBuilt = false

-- Preview state for hotkey panel (selected spell pending confirmation)
SpellSearch.previewState = { hotkey = nil }

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

    local function CacheSpellBank(bank, limit)
        for i = 1, limit do
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(i, bank)
            if not spellInfo then break end
            if spellInfo.itemType == Enum.SpellBookItemType.Spell and spellInfo.spellID then
                local isPassive = C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellInfo.spellID)
                if not isPassive then
                    local fullInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellInfo.spellID)
                    if fullInfo and fullInfo.name then
                        -- Pre-compute search strings to avoid per-keystroke allocations
                        spellbookCache[spellInfo.spellID] = {
                            name      = fullInfo.name,
                            nameLower = fullInfo.name:lower(),
                            idStr     = tostring(spellInfo.spellID),
                            icon      = fullInfo.iconID,
                        }
                    end
                end
            end
        end
    end

    CacheSpellBank(Enum.SpellBookSpellBank.Player, 500)
    if Enum.SpellBookSpellBank.Pet then
        CacheSpellBank(Enum.SpellBookSpellBank.Pet, 200)
    end

    spellbookCacheBuilt = true
end

-- Invalidate the spellbook cache (call on spec change or SPELLS_CHANGED)
function SpellSearch.InvalidateSpellbookCache()
    wipe(spellbookCache)
    spellbookCacheBuilt = false
end

-------------------------------------------------------------------------------
-- Private: fill `results` with matching spellbook entries.
-- Returns true if an exact numeric ID was matched (caller should return early).
-------------------------------------------------------------------------------
local function SearchSpells(filter, filterLower, excluded, results)
    local filterAsID = tonumber(filter)
    if filterAsID and filterAsID > 0 and not excluded[filterAsID] then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(filterAsID)
        if spellInfo and spellInfo.name then
            results[filterAsID] = spellInfo.name .. " (ID: " .. filterAsID .. ")"
            return true
        end
    end
    local count = 0
    for spellID, info in pairs(spellbookCache) do
        if not excluded[spellID] then
            if info.nameLower:find(filterLower, 1, true) or info.idStr:find(filter, 1, true) then
                results[spellID] = info.name .. " (" .. info.idStr .. ")"
                count = count + 1
                if count >= 15 then break end
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Get filtered results: spells from spellbook + items from equipped slots,
-- action bars, and bags. Returns combined table:
--   positive key = spellID, negative key = -itemID
-- Used by panels that accept both spells and items (defensive lists, blacklist).
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredResults(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()

    if filter == "" or #filter < 2 then return results end

    local excluded = {}
    if excludeList then
        for _, entry in ipairs(excludeList) do excluded[entry] = true end
    end

    if SearchSpells(filter, filterLower, excluded, results) then return results end

    -- ── Items ─────────────────────────────────────────────────────────────────

    local itemPrefixID = filter:match("^[iI]tem:(%d+)$")
    local seen = {}
    local itemCount = 0
    local MAX_ITEMS = 10

    local function TryAddItem(itemID)
        if itemCount >= MAX_ITEMS or seen[itemID] or excluded[-itemID] then return end
        local itemName = GetItemInfo(itemID)
        if not itemName then return end
        local matched
        if itemPrefixID then
            matched = tostring(itemID) == itemPrefixID
        else
            matched = itemName:lower():find(filterLower, 1, true) or tostring(itemID):find(filter, 1, true)
        end
        if matched then
            seen[itemID] = true
            results[-itemID] = "|cff00ccff" .. itemName .. "|r (item:" .. itemID .. ")"
            itemCount = itemCount + 1
        end
    end

    -- Source 1: Equipped gear slots (trinkets, on-use items, etc.)
    for slot = 1, 19 do
        if itemCount >= MAX_ITEMS then break end
        local itemID = GetInventoryItemID("player", slot)
        if itemID then TryAddItem(itemID) end
    end

    -- Source 2: Action bar slots
    for slot = 1, 180 do
        if itemCount >= MAX_ITEMS then break end
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then TryAddItem(id) end
    end

    -- Source 3: Bags (backpack + 4 bags)
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            if itemCount >= MAX_ITEMS then break end
            local numSlots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                if itemCount >= MAX_ITEMS then break end
                local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                if containerInfo and containerInfo.itemID then TryAddItem(containerInfo.itemID) end
            end
        end
    end

    return results
end

-------------------------------------------------------------------------------
-- Spells-only search — for panels where items are not applicable
-- (gap-closers, hotkeys, melee range override).
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredSpellbookSpells(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()

    if filter == "" or #filter < 2 then return results end

    local excluded = {}
    if excludeList then
        for _, spellID in ipairs(excludeList) do excluded[spellID] = true end
    end

    SearchSpells(filter, filterLower, excluded, results)
    return results
end

-------------------------------------------------------------------------------
-- Aura search — returns active player buffs for linking to items.
-- Empty/short text → all active buffs. Text input → filter by name or spell ID.
-- Returns {[spellID] = "Aura Name (ID: 12345)"} — positive keys (auras are spells).
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredPlayerAuras(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()
    local filterAsNumber = tonumber(filter)

    local excluded = {}
    if excludeList then
        for _, id in ipairs(excludeList) do excluded[id] = true end
    end

    -- Scan active player buffs
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not data then break end
            local spellId = data.spellId
            local name = data.name
            if spellId and name and not excluded[spellId] then
                local isSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and (BlizzardAPI.IsSecretValue(spellId) or BlizzardAPI.IsSecretValue(name))
                if not isSecret then
                    local match = false
                    if filter == "" or #filter < 2 then
                        match = true  -- show all active buffs on empty search
                    elseif name:lower():find(filterLower, 1, true) then
                        match = true
                    elseif filterAsNumber and spellId == filterAsNumber then
                        match = true
                    end
                    if match then
                        results[spellId] = name .. " |cff888888(ID: " .. spellId .. ")|r"
                    end
                end
            end
        end
    end

    -- Allow direct spellID entry even if not currently active
    if filterAsNumber and filterAsNumber > 0 and not results[filterAsNumber] and not excluded[filterAsNumber] then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(filterAsNumber)
        if info and info.name then
            results[filterAsNumber] = info.name .. " |cffff8800(not active)|r |cff888888(ID: " .. filterAsNumber .. ")|r"
        end
    end

    return results
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
function SpellSearch.CreateSpellListEntries(_addon, defensivesArgs, spellList, listType, baseOrder, updateFunc)
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
                        local profile = _addon:GetProfile()
                        -- Clean up item settings when removing an item entry
                        if isItemEntry then
                            local itemID = -entry
                            if profile and profile.defensives and profile.defensives.itemSettings then
                                profile.defensives.itemSettings[itemID] = nil
                            end
                        else
                            -- Clean up spell settings when removing a spell entry
                            if profile and profile.defensives and profile.defensives.spellSettings then
                                profile.defensives.spellSettings[entry] = nil
                            end
                        end
                        table.remove(spellList, i)
                        updateFunc()
                    end
                }
            }
        }

        -- Per-item controls: Link Aura + Hide in Combat
        if isItemEntry then
            local itemID = -entry
            local entryArgs = defensivesArgs[listType .. "_" .. i].args

            entryArgs.linkAura = {
                type = "execute",
                order = 4,
                width = 0.7,
                name = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
                    if settings and settings.linkedAura then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(settings.linkedAura)
                        local auraName = info and info.name or tostring(settings.linkedAura)
                        return L["Linked: %s"]:format(auraName)
                    end
                    return L["Link Aura..."]
                end,
                desc = L["Link Aura desc"],
                func = function()
                    local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
                    if not LiveSearchPopup then return end

                    LiveSearchPopup.Open({
                        title = L["Link Aura..."],
                        searchFunc = SpellSearch.GetFilteredPlayerAuras,
                        onSelect = function(auraSpellID, _)
                            local profile = _addon:GetProfile()
                            if not profile or not profile.defensives then return end
                            if not profile.defensives.itemSettings then profile.defensives.itemSettings = {} end
                            if not profile.defensives.itemSettings[itemID] then profile.defensives.itemSettings[itemID] = {} end
                            profile.defensives.itemSettings[itemID].linkedAura = auraSpellID
                            -- Default to hiding in combat when linking an aura
                            -- (item auras are almost certainly secret in combat)
                            if profile.defensives.itemSettings[itemID].combatHide == nil then
                                profile.defensives.itemSettings[itemID].combatHide = true
                            end
                            updateFunc()
                        end,
                    })
                end,
            }

            entryArgs.clearLink = {
                type = "execute",
                order = 5,
                width = 0.3,
                name = L["Clear Link"],
                desc = L["Clear Link desc"],
                hidden = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
                    return not (settings and settings.linkedAura)
                end,
                func = function()
                    local profile = _addon:GetProfile()
                    if profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID] then
                        profile.defensives.itemSettings[itemID].linkedAura = nil
                    end
                    updateFunc()
                end,
            }

            entryArgs.combatHide = {
                type = "toggle",
                order = 6,
                width = 0.7,
                name = L["Hide in Combat"],
                desc = L["Hide in Combat desc"],
                get = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
                    return settings and settings.combatHide or false
                end,
                set = function(_, val)
                    local profile = _addon:GetProfile()
                    if not profile or not profile.defensives then return end
                    if not profile.defensives.itemSettings then profile.defensives.itemSettings = {} end
                    if not profile.defensives.itemSettings[itemID] then profile.defensives.itemSettings[itemID] = {} end
                    profile.defensives.itemSettings[itemID].combatHide = val
                end,
            }
        end

        -- Per-spell controls: Proc Priority toggle (spells only, not items)
        if not isItemEntry then
            local spellID = entry
            local entryArgs = defensivesArgs[listType .. "_" .. i].args

            entryArgs.procPriority = {
                type = "toggle",
                order = 4,
                width = 0.7,
                name = L["Proc Priority"],
                desc = L["Proc Priority desc"],
                get = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.spellSettings and profile.defensives.spellSettings[spellID]
                    -- Default to true (procced spells jump to front by default)
                    return not settings or settings.procPriority ~= false
                end,
                set = function(_, val)
                    local profile = _addon:GetProfile()
                    if not profile or not profile.defensives then return end
                    if not profile.defensives.spellSettings then profile.defensives.spellSettings = {} end
                    if not profile.defensives.spellSettings[spellID] then profile.defensives.spellSettings[spellID] = {} end
                    profile.defensives.spellSettings[spellID].procPriority = val
                end,
            }
        end
    end
end

-------------------------------------------------------------------------------
-- Helper to create a single "Add..." button that opens the live-search popup.
-- spellsOnly = true  → spellbook only (gap-closers, hotkeys, melee range override)
-- spellsOnly = false → spellbook + inventory items (defensives, blacklist)
-------------------------------------------------------------------------------
function SpellSearch.CreateAddSpellButton(addon, argsTable, spellList, listType, order, listName, updateFunc, spellsOnly)
    SpellSearch.BuildSpellbookCache()

    argsTable["add_popup_" .. listType] = {
        type  = "execute",
        name  = L["Add"] .. " " .. listName .. "...",
        desc  = L["Search spell desc"],
        order = order,
        width = "normal",
        func  = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end

            -- Snapshot the current list as exclusion set for the popup session
            local excludeList = {}
            for _, entry in ipairs(spellList) do
                excludeList[#excludeList + 1] = entry
            end

            local searchFunc = spellsOnly and SpellSearch.GetFilteredSpellbookSpells
                                          or  SpellSearch.GetFilteredResults

            LiveSearchPopup.Open({
                title       = L["Add"] .. " " .. listName,
                searchFunc  = searchFunc,
                excludeList = excludeList,
                onSelect    = function(id, _)
                    if SpellSearch.AddSpellToList(addon, spellList, id) then
                        updateFunc()
                    end
                end,
            })
        end,
    }
end
