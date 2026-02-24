-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Hotkeys - Hotkey override settings tab
local Hotkeys = LibStub:NewLibrary("JustAC-OptionsHotkeys", 1)
if not Hotkeys then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function Hotkeys.CreateTabArgs(addon)
    return {
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
    }
end

-------------------------------------------------------------------------------
-- Dynamic hotkey override rebuild
-------------------------------------------------------------------------------
function Hotkeys.UpdateHotkeyOverrideOptions(addon)
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
    SpellSearch.BuildSpellbookCache()

    -- Initialize filter storage
    SpellSearch.filterState.hotkey = SpellSearch.filterState.hotkey or ""

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
        get = function() return SpellSearch.filterState.hotkey or "" end,
        set = function(_, val)
            SpellSearch.filterState.hotkey = val or ""
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
            local results = SpellSearch.GetFilteredSpellbookSpells(SpellSearch.filterState.hotkey, excludeList)
            local filter = (SpellSearch.filterState.hotkey or ""):trim()
            if next(results) == nil and #filter >= 2 then
                SpellSearch.previewState.hotkey = nil
                return {[0] = "|cff888888" .. L["No matches"] .. "|r"}
            end
            -- Set preview to first result (shown in dropdown, not yet added)
            SpellSearch.previewState.hotkey = next(results)
            return results
        end,
        get = function() return SpellSearch.previewState.hotkey end,
        set = function(_, spellID)
            if spellID == 0 then return end
            -- When spell selected from dropdown, put it in search field for Add button
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                SpellSearch.filterState.hotkey = tostring(spellID)
                SpellSearch.previewState.hotkey = spellID  -- Update preview to match selection
                if AceConfigRegistry then
                    AceConfigRegistry:NotifyChange("JustAssistedCombat")
                end
            end
        end,
        disabled = function()
            local filter = (SpellSearch.filterState.hotkey or ""):trim()
            return #filter < 2
        end,
    }
    hotkeyArgs.addHotkeyInput = {
        type = "input",
        name = L["Hotkey"],
        desc = L["Enter the hotkey text to display (e.g. 1, F1, S-2)"],
        order = 2.3,
        width = "normal",
        get = function() return SpellSearch.addHotkeyValueInput end,
        set = function(_, val) SpellSearch.addHotkeyValueInput = val or "" end,
    }
    hotkeyArgs.addButton = {
        type = "execute",
        name = L["Add"],
        desc = L["Add hotkey desc"],
        order = 2.4,
        width = "half",
        func = function()
            local val = (SpellSearch.filterState.hotkey or ""):trim()
            if val == "" then
                addon:Print(L["Please search and select a spell first"])
                return
            end
            if not SpellSearch.addHotkeyValueInput or SpellSearch.addHotkeyValueInput:trim() == "" then
                addon:Print(L["Please enter a hotkey value"])
                return
            end

            local spellID = tonumber(val)
            if not spellID then
                spellID = SpellSearch.LookupSpellByName(val)
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

            hotkeyOverrides[spellID] = SpellSearch.addHotkeyValueInput:trim()
            addon:Print("Hotkey set: " .. spellInfo.name .. " = '" .. SpellSearch.addHotkeyValueInput:trim() .. "'")
            SpellSearch.filterState.hotkey = ""
            SpellSearch.addHotkeyValueInput = ""
            addon:ForceUpdate()
            Hotkeys.UpdateHotkeyOverrideOptions(addon)
        end,
        disabled = function()
            local filter = (SpellSearch.filterState.hotkey or ""):trim()
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
                Hotkeys.UpdateHotkeyOverrideOptions(addon)
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
                            Hotkeys.UpdateHotkeyOverrideOptions(addon)
                        end
                    },
                    remove = {
                        type = "execute",
                        name = L["Remove"],
                        order = 2,
                        func = function()
                            hotkeyOverrides[spellID] = nil
                            Hotkeys.UpdateHotkeyOverrideOptions(addon)
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
