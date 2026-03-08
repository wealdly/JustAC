-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Offensive - Offensive queue settings tab + blacklist management
local Offensive = LibStub:NewLibrary("JustAC-OptionsOffensive", 1)
if not Offensive then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function Offensive.CreateTabArgs(addon)
    local GapClosers = LibStub("JustAC-OptionsGapClosers", true)
    return {
        type = "group",
        name = L["Offensive"],
        order = 4,
        childGroups = "tab",
        args = {
            -- Sub-tab 1: Gap-Closers
            gapClosers = (GapClosers and GapClosers.CreateTabArgs) and GapClosers.CreateTabArgs(addon) or nil,
            -- Sub-tab 2: Blacklist
            blacklist = {
                type = "group",
                name = function()
                    local specIndex = GetSpecialization and GetSpecialization()
                    local specName
                    if specIndex then
                        local _, name = GetSpecializationInfo(specIndex)
                        specName = name
                    end
                    return L["Blacklist"] .. (specName and (" (" .. specName .. ")") or "")
                end,
                order = 3,
                args = {
                    info = {
                        type = "description",
                        name = L["Blacklist Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    blacklistPosition1 = {
                        type = "toggle",
                        name = L["Blacklist Position 1"],
                        desc = L["Blacklist Position 1 desc"],
                        order = 1.5,
                        width = "full",
                        get = function() return addon.db.profile.blacklistPosition1 end,
                        set = function(_, val)
                            addon.db.profile.blacklistPosition1 = val
                            addon:ForceUpdate()
                        end,
                    },
                    -- Dynamic blacklist entries added by UpdateBlacklistOptions
                },
            },
        },
    }
end

-------------------------------------------------------------------------------
-- Dynamic blacklist rebuild
-------------------------------------------------------------------------------
function Offensive.UpdateBlacklistOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local blacklistTab = optionsTable.args.offensive.args.blacklist
    if not blacklistTab then return end
    local blacklistArgs = blacklistTab.args

    -- Static keys to preserve (defined in CreateTabArgs)
    local staticKeys = {
        info = true,
        blacklistPosition1 = true,
    }

    local keysToClear = {}
    for key, _ in pairs(blacklistArgs) do
        if not staticKeys[key] then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        blacklistArgs[key] = nil
    end

    if not addon.db.profile.blacklistedSpells then
        addon.db.profile.blacklistedSpells = {}
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return end
    if not addon.db.profile.blacklistedSpells[specKey] then
        addon.db.profile.blacklistedSpells[specKey] = {}
    end
    local blacklistedSpells = addon.db.profile.blacklistedSpells[specKey]

    SpellSearch.BuildSpellbookCache()

    blacklistArgs.addHeader = {
        type = "header",
        name = L["Add Spell to Blacklist"],
        order = 22,
    }
    blacklistArgs.addSpellButton = {
        type  = "execute",
        name  = L["Add"] .. " " .. L["Blacklist"] .. "...",
        desc  = L["Search spell desc"],
        order = 22.1,
        width = "normal",
        func  = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end

            -- Snapshot current blacklist as exclusion set
            local excludeList = {}
            for spellID, _ in pairs(blacklistedSpells) do
                excludeList[#excludeList + 1] = spellID
            end

            LiveSearchPopup.Open({
                title      = L["Add Spell to Blacklist"],
                searchFunc = SpellSearch.GetFilteredResults,
                excludeList = excludeList,
                onSelect   = function(id, _)
                    if not id or id == 0 then return end
                    if blacklistedSpells[id] then return end
                    local displayName
                    if id > 0 then
                        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                        if not spellInfo or not spellInfo.name then return end
                        displayName = spellInfo.name
                    else
                        local itemName = GetItemInfo(-id)
                        if not itemName then return end
                        displayName = itemName .. " |cff00ccff[Item]|r"
                    end
                    blacklistedSpells[id] = true
                    addon:Print("Blacklisted: " .. displayName)
                    addon:ForceUpdate()
                    Offensive.UpdateBlacklistOptions(addon)
                end,
            })
        end,
    }
    blacklistArgs.listHeader = {
        type = "header",
        name = L["Blacklisted Spells"],
        order = 22.5,
    }

    -- Collect all blacklisted entries (spells: positive IDs, items: negative IDs)
    local entryList = {}
    for id, _ in pairs(blacklistedSpells) do
        if type(id) == "number" and id ~= 0 then
            local displayName, displayIcon
            if id > 0 then
                local info = BlizzardAPI and BlizzardAPI.GetSpellInfo(id) or (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id))
                displayName = info and info.name or ("Spell #" .. id)
                displayIcon = info and info.iconID or 134400
            else
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(-id)
                displayName = (itemName or ("Item #" .. (-id))) .. " |cff00ccff[Item]|r"
                displayIcon = itemTexture or 134400
            end
            entryList[#entryList + 1] = { id = id, name = displayName, icon = displayIcon }
        end
    end

    table.sort(entryList, function(a, b)
        local na = a.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local nb = b.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return na < nb
    end)

    if #entryList == 0 then
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
                Offensive.UpdateBlacklistOptions(addon)
            end,
        }
        for i, entry in ipairs(entryList) do
            local idKey = "bl_" .. tostring(entry.id)
            local idStr = entry.id > 0
                and ("|cff888888ID: " .. entry.id .. "|r")
                or  ("|cff888888item:" .. (-entry.id) .. "|r")

            blacklistArgs[idKey] = {
                type = "group",
                name = "|T" .. entry.icon .. ":16:16:0:0|t " .. entry.name,
                inline = true,
                order = i + 23,
                args = {
                    entryInfo = {
                        type = "description",
                        name = idStr,
                        order = 1,
                        width = "double",
                    },
                    remove = {
                        type = "execute",
                        name = L["Remove"],
                        order = 2,
                        func = function()
                            blacklistedSpells[entry.id] = nil
                            addon:ForceUpdate()
                            Offensive.UpdateBlacklistOptions(addon)
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
