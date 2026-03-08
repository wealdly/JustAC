-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Hotkeys - Hotkey override settings tab
local Hotkeys = LibStub:NewLibrary("JustAC-OptionsHotkeys", 1)
if not Hotkeys then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function Hotkeys.CreateTabArgs()
    return {
        type = "group",
        name = L["Hotkey Overrides"],
        order = 7,
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

    local generalArgs = optionsTable.args.general and optionsTable.args.general.args
    if not generalArgs or not generalArgs.hotkeyOverrides then return end
    local hotkeyArgs = generalArgs.hotkeyOverrides.args

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

    SpellSearch.BuildSpellbookCache()

    hotkeyArgs.addHeader = {
        type = "header",
        name = L["Add Hotkey Override"],
        order = 2,
    }
    hotkeyArgs.selectSpellButton = {
        type  = "execute",
        name  = L["Select Spell..."],
        order = 2.1,
        width = "normal",
        func  = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end
            SpellSearch.BuildSpellbookCache()

            -- Exclude spells that already have overrides
            local excludeList = {}
            for spellID, _ in pairs(hotkeyOverrides) do
                excludeList[#excludeList + 1] = spellID
            end

            LiveSearchPopup.Open({
                title      = L["Add Hotkey Override"],
                searchFunc = SpellSearch.GetFilteredSpellbookSpells,
                excludeList = excludeList,
                onSelect   = function(spellID, _)
                    SpellSearch.previewState.hotkey = spellID
                    if AceConfigRegistry then
                        AceConfigRegistry:NotifyChange("JustAssistedCombat")
                    end
                end,
            })
        end,
    }
    hotkeyArgs.selectedSpellDesc = {
        type = "description",
        name = function()
            local spellID = SpellSearch.previewState.hotkey
            if not spellID then return "|cff888888" .. L["No spell selected"] .. "|r" end
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if info and info.name then
                return "|cffFFD100" .. info.name .. "|r (ID: " .. spellID .. ")"
            end
            return "|cff888888" .. L["No spell selected"] .. "|r"
        end,
        order = 2.2,
        fontSize = "medium",
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
            local spellID = SpellSearch.previewState.hotkey
            if not spellID then
                addon:Print(L["Please search and select a spell first"])
                return
            end
            if not SpellSearch.addHotkeyValueInput or SpellSearch.addHotkeyValueInput:trim() == "" then
                addon:Print(L["Please enter a hotkey value"])
                return
            end

            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if not spellInfo or not spellInfo.name then
                addon:Print("Invalid spell ID: " .. spellID)
                return
            end

            hotkeyOverrides[spellID] = SpellSearch.addHotkeyValueInput:trim()
            addon:Print("Hotkey set: " .. spellInfo.name .. " = '" .. SpellSearch.addHotkeyValueInput:trim() .. "'")
            SpellSearch.previewState.hotkey = nil
            SpellSearch.addHotkeyValueInput = ""
            addon:ForceUpdate()
            Hotkeys.UpdateHotkeyOverrideOptions(addon)
        end,
        disabled = function()
            return not SpellSearch.previewState.hotkey
        end,
    }
    hotkeyArgs.listHeader = {
        type = "header",
        name = L["Custom Hotkeys"],
        order = 2.5,
    }

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

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
