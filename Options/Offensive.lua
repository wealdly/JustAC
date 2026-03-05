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
            -- Sub-tab 1: Queue Content
            settings = {
                type = "group",
                name = L["Queue Content"],
                order = 1,
                args = {
                    includeHiddenAbilities = {
                        type = "toggle",
                        name = L["Include All Available Abilities"],
                        desc = L["Include All Available Abilities desc"],
                        order = 1,
                        width = "full",
                        get = function() return addon.db.profile.includeHiddenAbilities ~= false end,
                        set = function(_, val)
                            addon.db.profile.includeHiddenAbilities = val
                            addon:ForceUpdate()
                        end,
                        disabled = function()
                            return (addon.db.profile.displayMode or "queue") == "disabled"
                        end,
                    },
                    showSpellbookProcs = {
                        type = "toggle",
                        name = L["Insert Procced Abilities"],
                        desc = L["Insert Procced Abilities desc"],
                        order = 2,
                        width = "full",
                        get = function() return addon.db.profile.showSpellbookProcs or false end,
                        set = function(_, val)
                            addon.db.profile.showSpellbookProcs = val
                            addon:ForceUpdate()
                        end,
                        disabled = function()
                            return (addon.db.profile.displayMode or "queue") == "disabled"
                        end,
                    },
                    hideItemAbilities = {
                        type = "toggle",
                        name = L["Allow Item Abilities"],
                        desc = L["Allow Item Abilities desc"],
                        order = 3,
                        width = "full",
                        get = function() return not addon.db.profile.hideItemAbilities end,
                        set = function(_, val)
                            addon.db.profile.hideItemAbilities = not val
                            addon:ForceUpdate()
                        end,
                        disabled = function()
                            return (addon.db.profile.displayMode or "queue") == "disabled"
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
                        desc = L["Reset Offensive desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local p = addon.db.profile
                            p.includeHiddenAbilities = true
                            p.showSpellbookProcs     = true
                            p.hideItemAbilities      = false
                            p.blacklistPosition1     = false
                            addon:ForceUpdate()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                },
            },
            -- Sub-tab 2: Gap-Closers
            gapClosers = (GapClosers and GapClosers.CreateTabArgs) and GapClosers.CreateTabArgs(addon) or nil,
            -- Sub-tab 3: Blacklist
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
    SpellSearch.filterState.blacklist = SpellSearch.filterState.blacklist or ""

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
        get = function() return SpellSearch.filterState.blacklist or "" end,
        set = function(_, val)
            SpellSearch.filterState.blacklist = val or ""
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
            local excludeList = {}
            for spellID, _ in pairs(blacklistedSpells) do
                table.insert(excludeList, spellID)
            end
            local results = SpellSearch.GetFilteredSpellbookSpells(SpellSearch.filterState.blacklist, excludeList)
            local filter = (SpellSearch.filterState.blacklist or ""):trim()
            if next(results) == nil and #filter >= 2 then
                SpellSearch.previewState.blacklist = nil
                return {[0] = "|cff888888" .. L["No matches"] .. "|r"}
            end
            SpellSearch.previewState.blacklist = next(results)
            return results
        end,
        get = function() return SpellSearch.previewState.blacklist end,
        set = function(_, spellID)
            if spellID == 0 then return end
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                blacklistedSpells[spellID] = true
                addon:Print("Blacklisted: " .. spellInfo.name)
                SpellSearch.filterState.blacklist = ""
                addon:ForceUpdate()
                Offensive.UpdateBlacklistOptions(addon)
            end
        end,
        disabled = function()
            local filter = (SpellSearch.filterState.blacklist or ""):trim()
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
            local val = (SpellSearch.filterState.blacklist or ""):trim()
            if val == "" then return end

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

            if blacklistedSpells[spellID] then
                addon:Print("Spell already blacklisted: " .. spellInfo.name)
                return
            end

            blacklistedSpells[spellID] = true
            addon:Print("Blacklisted: " .. spellInfo.name)
            SpellSearch.filterState.blacklist = ""
            addon:ForceUpdate()
            Offensive.UpdateBlacklistOptions(addon)
        end,
        disabled = function()
            local filter = (SpellSearch.filterState.blacklist or ""):trim()
            return #filter < 1
        end,
    }
    blacklistArgs.listHeader = {
        type = "header",
        name = L["Blacklisted Spells"],
        order = 22.5,
    }
    
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
                Offensive.UpdateBlacklistOptions(addon)
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
