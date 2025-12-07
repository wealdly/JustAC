-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options Module
local Options = LibStub:NewLibrary("JustAC-Options", 24)
if not Options then return end

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local UIManager = LibStub("JustAC-UIManager", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function Options.UpdateBlacklistOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not SpellQueue then return end

    local blacklistArgs = optionsTable.args.blacklist.args

    local keysToClear = {}
    for key, _ in pairs(blacklistArgs) do
        if key ~= "info" and key ~= "header" then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        blacklistArgs[key] = nil
    end

    local blacklistedSpells = addon.db.profile.blacklistedSpells
    local spellList = {}
    for spellID in pairs(blacklistedSpells) do
        table.insert(spellList, spellID)
    end

    table.sort(spellList, function(a, b)
        local nameA = (SpellQueue.GetCachedSpellInfo(a) or {}).name or ""
        local nameB = (SpellQueue.GetCachedSpellInfo(b) or {}).name or ""
        return nameA < nameB
    end)

    if #spellList == 0 then
        blacklistArgs.noSpells = {
            type = "description",
            name = L["No spells currently blacklisted"],
            order = 3,
        }
        return
    end

    for i, spellID in ipairs(spellList) do
        local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
        if spellInfo then
            blacklistArgs[tostring(spellID)] = {
                type = "group",
                name = "|T" .. spellInfo.iconID .. ":16:16:0:0|t " .. spellInfo.name,
                inline = true,
                order = i + 2,
                args = {
                    enabled = {
                        type = "toggle",
                        name = L["Hide from Queue"],
                        desc = L["Hide spell desc"],
                        order = 1,
                        width = "double",
                        get = function()
                            return blacklistedSpells[spellID] and blacklistedSpells[spellID].fixedQueue
                        end,
                        set = function(_, val)
                            if val then
                                blacklistedSpells[spellID] = { fixedQueue = true }
                            else
                                blacklistedSpells[spellID] = nil
                            end
                            addon:ForceUpdate()
                        end
                    },
                    remove = {
                        type = "execute",
                        name = L["Remove"],
                        order = 2,
                        func = function()
                            blacklistedSpells[spellID] = nil
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
    if not optionsTable or not SpellQueue then return end

    local hotkeyArgs = optionsTable.args.hotkeyOverrides.args

    -- Clear old entries (preserve static ones)
    local keysToClear = {}
    for key, _ in pairs(hotkeyArgs) do
        if key ~= "info" and key ~= "header" then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        hotkeyArgs[key] = nil
    end

    -- Get current overrides
    local hotkeyOverrides = addon.db.profile.hotkeyOverrides or {}
    local overrideList = {}
    for spellID in pairs(hotkeyOverrides) do
        table.insert(overrideList, spellID)
    end

    table.sort(overrideList, function(a, b)
        local nameA = (SpellQueue.GetCachedSpellInfo(a) or {}).name or ""
        local nameB = (SpellQueue.GetCachedSpellInfo(b) or {}).name or ""
        return nameA < nameB
    end)

    if #overrideList == 0 then
        hotkeyArgs.noOverrides = {
            type = "description",
            name = L["No custom hotkeys set"],
            order = 3,
        }
        return
    end

    for i, spellID in ipairs(overrideList) do
        local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
        if spellInfo then
            hotkeyArgs[tostring(spellID)] = {
                type = "group",
                name = "|T" .. spellInfo.iconID .. ":16:16:0:0|t " .. spellInfo.name,
                inline = true,
                order = i + 2,
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
    
    for i, spellID in ipairs(spellList) do
        local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or ("Spell " .. spellID)
        local spellIcon = spellInfo and spellInfo.iconID or 134400
        
        defensivesArgs[listType .. "_" .. i] = {
            type = "group",
            name = i .. ". |T" .. spellIcon .. ":16:16:0:0|t " .. spellName,
            inline = true,
            order = baseOrder + i,
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
                        Options.UpdateDefensivesOptions(addon)
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
                        Options.UpdateDefensivesOptions(addon)
                    end
                },
                remove = {
                    type = "execute",
                    name = L["Remove"],
                    order = 3,
                    width = 0.5,
                    func = function()
                        table.remove(spellList, i)
                        Options.UpdateDefensivesOptions(addon)
                    end
                }
            }
        }
    end
end

-- Helper to create add spell input for a list
local function CreateAddSpellInput(addon, defensivesArgs, spellList, listType, order, listName)
    defensivesArgs["add_" .. listType] = {
        type = "input",
        name = L["Add to %s"]:format(listName),
        desc = L["Add spell desc"],
        order = order,
        width = "normal",
        get = function() return "" end,
        set = function(_, val)
            if not val or val:trim() == "" then return end
            
            local spellID = tonumber(val)
            if spellID and spellID > 0 then
                -- Check if already in list
                for _, existingID in ipairs(spellList) do
                    if existingID == spellID then
                        addon:DebugPrint("Already in list")
                        return
                    end
                end
                
                table.insert(spellList, spellID)
                local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                addon:DebugPrint("Added: " .. name)
                Options.UpdateDefensivesOptions(addon)
            else
                addon:Print("Invalid spell ID")
            end
        end
    }
end

function Options.UpdateDefensivesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not SpellQueue then return end

    local defensivesArgs = optionsTable.args.defensives.args

    -- Clear old dynamic entries (preserve static elements)
    local staticKeys = {
        info = true, header = true, enabled = true, 
        selfHealThreshold = true, cooldownThreshold = true,
        behaviorHeader = true, showOnlyInCombat = true,
        position = true,
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

    -- Self-heal spells (order 22-39)
    CreateSpellListEntries(addon, defensivesArgs, defensives.selfHealSpells, "selfheal", 22)
    CreateAddSpellInput(addon, defensivesArgs, defensives.selfHealSpells, "selfheal", 40, "Self-Heals")

    -- Cooldown spells (order 52-69)  
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
                    visualHeader = {
                        type = "header",
                        name = L["Icon Layout"],
                        order = 2,
                    },
                    maxIcons = {
                        type = "range",
                        name = L["Max Icons"],
                        desc = L["Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 3,
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
                        order = 4,
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
                        order = 5,
                        width = "normal",
                        get = function() return addon.db.profile.iconSpacing or 2 end,
                        set = function(_, val) 
                            addon.db.profile.iconSpacing = val
                            addon:UpdateFrameSize()
                        end
                    },
                    firstIconScale = {
                        type = "range",
                        name = L["Primary Spell Scale"],
                        desc = L["Primary Spell Scale desc"],
                        min = 1.0, max = 2.0, step = 0.1,
                        order = 6,
                        width = "normal",
                        get = function() return addon.db.profile.firstIconScale or 1.3 end,
                        set = function(_, val)
                            addon.db.profile.firstIconScale = val
                            addon:UpdateFrameSize()
                        end
                    },
                    queueOrientation = {
                        type = "select",
                        name = L["Queue Orientation"],
                        desc = L["Queue Orientation desc"],
                        order = 7,
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
                    behaviorHeader = {
                        type = "header",
                        name = L["Display Behavior"],
                        order = 10,
                    },
                    focusEmphasis = {
                        type = "toggle",
                        name = L["Highlight Primary Spell"],
                        desc = L["Highlight Primary Spell desc"],
                        order = 11,
                        width = "full",
                        get = function() return addon.db.profile.focusEmphasis ~= false end,
                        set = function(_, val)
                            addon.db.profile.focusEmphasis = val
                            addon:ForceUpdate()
                        end
                    },
                    showTooltips = {
                        type = "toggle",
                        name = L["Show Tooltips"],
                        desc = L["Show Tooltips desc"],
                        order = 12,
                        width = "full",
                        get = function() return addon.db.profile.showTooltips ~= false end,
                        set = function(_, val)
                            addon.db.profile.showTooltips = val
                        end
                    },
                    tooltipsInCombat = {
                        type = "toggle",
                        name = L["Tooltips in Combat"],
                        desc = L["Tooltips in Combat desc"],
                        order = 13,
                        width = "full",
                        disabled = function() return not addon.db.profile.showTooltips end,
                        get = function() return addon.db.profile.tooltipsInCombat or false end,
                        set = function(_, val)
                            addon.db.profile.tooltipsInCombat = val
                        end
                    },
                    glowHeader = {
                        type = "header",
                        name = L["Visual Effects"],
                        order = 20,
                    },
                    frameOpacity = {
                        type = "range",
                        name = L["Frame Opacity"],
                        desc = L["Frame Opacity desc"],
                        min = 0.1, max = 1.0, step = 0.05,
                        order = 21,
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
                        order = 22,
                        width = "normal",
                        get = function() return addon.db.profile.queueIconDesaturation or 0 end,
                        set = function(_, val)
                            addon.db.profile.queueIconDesaturation = val
                            addon:ForceUpdate()
                        end
                    },
                    hideQueueOutOfCombat = {
                        type = "toggle",
                        name = L["Hide Queue Out of Combat"],
                        desc = L["Hide Queue Out of Combat desc"],
                        order = 23,
                        width = "full",
                        get = function() return addon.db.profile.hideQueueOutOfCombat end,
                        set = function(_, val)
                            addon.db.profile.hideQueueOutOfCombat = val
                            addon:ForceUpdate()
                        end
                    },
                    showSpellbookProcs = {
                        type = "toggle",
                        name = L["Show All Procced Abilities"],
                        desc = L["Show All Procced Abilities desc"],
                        order = 24,
                        width = "full",
                        get = function() return addon.db.profile.showSpellbookProcs or false end,
                        set = function(_, val)
                            addon.db.profile.showSpellbookProcs = val
                            addon:ForceUpdate()
                        end
                    },
                    includeHiddenAbilities = {
                        type = "toggle",
                        name = L["Include Hidden Abilities"],
                        desc = L["Include Hidden Abilities desc"],
                        order = 25,
                        width = "full",
                        get = function() return addon.db.profile.includeHiddenAbilities or false end,
                        set = function(_, val)
                            addon.db.profile.includeHiddenAbilities = val
                            addon:ForceUpdate()
                        end
                    },
                    stabilizationWindow = {
                        type = "range",
                        name = L["Stabilization Window"],
                        desc = L["Stabilization Window desc"],
                        order = 26,
                        width = "full",
                        min = 0.25,
                        max = 0.50,
                        step = 0.05,
                        get = function() return addon.db.profile.stabilizationWindow or 0.50 end,
                        set = function(_, val)
                            addon.db.profile.stabilizationWindow = val
                        end,
                        disabled = function() return not addon.db.profile.includeHiddenAbilities end,
                    },
                    systemHeader = {
                        type = "header",
                        name = L["System"],
                        order = 30,
                    },
                    panelLocked = {
                        type = "toggle",
                        name = L["Lock Panel"],
                        desc = L["Lock Panel desc"],
                        order = 31,
                        width = "full",
                        get = function() return addon.db.profile.panelLocked or false end,
                        set = function(_, val) 
                            addon.db.profile.panelLocked = val
                            local status = val and "|cffff6666LOCKED|r" or "|cff00ff00UNLOCKED|r"
                            addon:DebugPrint("Panel " .. status)
                        end
                    },
                    debugMode = {
                        type = "toggle",
                        name = L["Debug Mode"],
                        desc = L["Debug Mode desc"],
                        order = 32,
                        width = "full",
                        get = function() return addon.db.profile.debugMode or false end,
                        set = function(_, val) 
                            addon.db.profile.debugMode = val
                            addon:Print("Debug: " .. (val and "ON" or "OFF"))
                        end
                    }
                }
            },
            hotkeyOverrides = {
                type = "group",
                name = L["Hotkey Overrides"],
                order = 2,
                args = {
                    info = {
                        type = "description",
                        name = L["Hotkey Overrides Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = L["Custom Hotkey Displays"],
                        order = 2,
                    },
                },
            },
            blacklist = {
                type = "group",
                name = L["Blacklist"],
                order = 3,
                args = {
                    info = {
                        type = "description",
                        name = L["Blacklist Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = L["Blacklisted Spells"],
                        order = 2,
                    },
                },
            },
            defensives = {
                type = "group",
                name = L["Defensives"],
                order = 4,
                args = {
                    info = {
                        type = "description",
                        name = L["Defensives Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = L["Threshold Settings"],
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
                    selfHealThreshold = {
                        type = "range",
                        name = L["Self-Heal Threshold"],
                        desc = L["Self-Heal Threshold desc"],
                        min = 30, max = 90, step = 5,
                        order = 4,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.selfHealThreshold or 70 end,
                        set = function(_, val)
                            addon.db.profile.defensives.selfHealThreshold = val
                            addon:ForceUpdateAll()
                        end
                    },
                    cooldownThreshold = {
                        type = "range",
                        name = L["Cooldown Threshold"],
                        desc = L["Cooldown Threshold desc"],
                        min = 10, max = 70, step = 5,
                        order = 5,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.cooldownThreshold or 50 end,
                        set = function(_, val)
                            addon.db.profile.defensives.cooldownThreshold = val
                            addon:ForceUpdateAll()
                        end
                    },
                    behaviorHeader = {
                        type = "header",
                        name = L["Display Behavior"],
                        order = 6,
                    },
                    showOnlyInCombat = {
                        type = "toggle",
                        name = L["Only In Combat"],
                        desc = L["Only In Combat desc"],
                        order = 7,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showOnlyInCombat end,
                        set = function(_, val)
                            addon.db.profile.defensives.showOnlyInCombat = val
                            addon:ForceUpdateAll()
                        end
                    },
                    position = {
                        type = "select",
                        name = L["Icon Position"],
                        desc = L["Icon Position desc"],
                        order = 9,
                        width = "normal",
                        values = {
                            LEFT = "Left",
                            ABOVE = "Above",
                            BELOW = "Below",
                        },
                        get = function() return addon.db.profile.defensives.position or "LEFT" end,
                        set = function(_, val)
                            addon.db.profile.defensives.position = val
                            UIManager.CreateSpellIcons(addon)
                            addon:ForceUpdateAll()
                        end
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
                        order = 41,
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
                        order = 71,
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
                order = 10,
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
                    }
                }
            }
        }
    }
end

local function HandleSlashCommand(addon, input)
    if not input or input == "" or input:match("^%s*$") then
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
        Options.UpdateBlacklistOptions(addon)
        Options.UpdateHotkeyOverrideOptions(addon)
        Options.UpdateDefensivesOptions(addon)
        AceConfigDialog:Open("JustAssistedCombat")
        
    elseif command == "toggle" then
        if addon.db and addon.db.profile then
            addon.db.profile.isManualMode = not addon.db.profile.isManualMode
            if addon.db.profile.isManualMode then
                addon:StopUpdates()
                addon:DebugPrint("Paused")
            else
                addon:StartUpdates()
                addon:DebugPrint("Resumed")
            end
        end
        
    elseif command == "debug" then
        if addon.db and addon.db.profile then
            addon.db.profile.debugMode = not addon.db.profile.debugMode
            addon:Print("Debug: " .. (addon.db.profile.debugMode and "ON" or "OFF"))
        end
        
    elseif command == "test" or command == "apitest" then
        local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
        if BlizzardAPI and BlizzardAPI.TestAssistedCombatAPI then
            BlizzardAPI.TestAssistedCombatAPI()
        else
            addon:Print("BlizzardAPI test function not available")
        end
        
    elseif command == "raw" then
        local SpellQueue = LibStub("JustAC-SpellQueue", true)
        if SpellQueue and SpellQueue.ShowAssistedCombatRaw then
            SpellQueue.ShowAssistedCombatRaw()
        else
            addon:Print("SpellQueue module not available")
        end
        
    elseif command == "form" or command == "forms" then
        local FormCache = LibStub("JustAC-FormCache", true)
        if FormCache and FormCache.ShowFormDebugInfo then
            FormCache.ShowFormDebugInfo()
        else
            addon:Print("FormCache module not available")
        end
        
    elseif command == "formcheck" then
        if DebugCommands then
            DebugCommands.FormDetection(addon)
        else
            addon:Print("DebugCommands module not available")
        end
        
    elseif command == "lps" then
        local spellID = input:match("^lps%s+(%d+)")
        if DebugCommands and DebugCommands.LPSInfo then
            DebugCommands.LPSInfo(addon, spellID)
        else
            addon:Print("Usage: /jac lps <spellID>")
        end
        
    elseif command == "modules" or command == "diag" then
        if DebugCommands then
            DebugCommands.ModuleDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end
        
    elseif command == "find" then
        local spellName = input:match("^find%s+(.+)")
        if DebugCommands then
            DebugCommands.FindSpell(addon, spellName)
        else
            addon:Print("DebugCommands module not available")
        end
        
    elseif command == "reset" then
        if addon.mainFrame then
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint("CENTER", 0, -150)
            addon:SavePosition()
            addon:DebugPrint("Position reset")
        end
        
    elseif command == "profile" then
        local profileAction = input:match("^profile%s+(.+)")
        if DebugCommands then
            DebugCommands.ManageProfile(addon, profileAction)
        else
            addon:Print("DebugCommands module not available")
        end
        
    elseif command == "help" then
        if DebugCommands then
            DebugCommands.ShowHelp(addon)
        else
            addon:Print("DebugCommands module not available")
        end
        
    else
        addon:Print("Unknown command. Type '/jac help' for available commands.")
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
    end
    
    AceConfig:RegisterOptionsTable("JustAssistedCombat", addon.optionsTable)
    AceConfigDialog:AddToBlizOptions("JustAssistedCombat", "JustAssistedCombat")
    
    addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
    addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
end