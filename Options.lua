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

-- Storage for manual add inputs
local addBlacklistInput = ""
local addHotkeySpellInput = ""
local addHotkeyValueInput = ""

function Options.UpdateBlacklistOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local blacklistArgs = optionsTable.args.blacklist.args

    -- Clear old entries (preserve static ones)
    local keysToClear = {}
    for key, _ in pairs(blacklistArgs) do
        if key ~= "info" then
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
    
    -- Add spell input section
    blacklistArgs.addHeader = {
        type = "header",
        name = L["Add Spell to Blacklist"],
        order = 2,
    }
    blacklistArgs.addInput = {
        type = "input",
        name = L["Spell ID"],
        desc = L["Enter the spell ID to blacklist"],
        order = 2.1,
        width = "normal",
        get = function() return addBlacklistInput end,
        set = function(_, val) addBlacklistInput = val or "" end,
    }
    blacklistArgs.addButton = {
        type = "execute",
        name = L["Add"],
        order = 2.2,
        width = "half",
        func = function()
            if not addBlacklistInput or addBlacklistInput:trim() == "" then return end
            local spellID = tonumber(addBlacklistInput)
            if spellID and spellID > 0 then
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                if not spellInfo or not spellInfo.name then
                    addon:Print("Invalid spell ID: " .. spellID .. " (spell not found)")
                    return
                end
                if blacklistedSpells[spellID] then
                    addon:Print("Spell already blacklisted: " .. spellInfo.name)
                    return
                end
                blacklistedSpells[spellID] = true
                addon:Print("Blacklisted: " .. spellInfo.name)
                addBlacklistInput = ""
                addon:ForceUpdate()
                Options.UpdateBlacklistOptions(addon)
            else
                addon:Print("Invalid spell ID (must be a positive number)")
            end
        end,
    }
    blacklistArgs.listHeader = {
        type = "header",
        name = L["Blacklisted Spells"],
        order = 2.5,
    }
    
    -- Build sorted list of spell IDs (keys are already normalized to numbers on load)
    local spellList = {}
    for spellID, _ in pairs(blacklistedSpells) do
        if type(spellID) == "number" and spellID > 0 then
            table.insert(spellList, spellID)
        end
    end

    table.sort(spellList, function(a, b)
        local infoA = C_Spell.GetSpellInfo(a)
        local infoB = C_Spell.GetSpellInfo(b)
        local nameA = infoA and infoA.name or ""
        local nameB = infoB and infoB.name or ""
        return nameA < nameB
    end)

    if #spellList == 0 then
        blacklistArgs.noSpells = {
            type = "description",
            name = L["No spells currently blacklisted"],
            order = 3,
        }
    else
        for i, spellID in ipairs(spellList) do
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            local spellName = spellInfo and spellInfo.name or ("Spell #" .. spellID)
            local spellIcon = spellInfo and spellInfo.iconID or 134400
            
            blacklistArgs[tostring(spellID)] = {
                type = "group",
                name = "|T" .. spellIcon .. ":16:16:0:0|t " .. spellName,
                inline = true,
                order = i + 3,
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
    
    -- Add hotkey input section
    hotkeyArgs.addHeader = {
        type = "header",
        name = L["Add Hotkey Override"],
        order = 2,
    }
    hotkeyArgs.addSpellInput = {
        type = "input",
        name = L["Spell ID"],
        desc = L["Enter the spell ID to add a hotkey override for"],
        order = 2.1,
        width = "normal",
        get = function() return addHotkeySpellInput end,
        set = function(_, val) addHotkeySpellInput = val or "" end,
    }
    hotkeyArgs.addHotkeyInput = {
        type = "input",
        name = L["Hotkey"],
        desc = L["Enter the hotkey text to display (e.g. 1, F1, S-2)"],
        order = 2.2,
        width = "normal",
        get = function() return addHotkeyValueInput end,
        set = function(_, val) addHotkeyValueInput = val or "" end,
    }
    hotkeyArgs.addButton = {
        type = "execute",
        name = L["Add"],
        order = 2.3,
        width = "half",
        func = function()
            if not addHotkeySpellInput or addHotkeySpellInput:trim() == "" then
                addon:Print("Please enter a spell ID")
                return
            end
            if not addHotkeyValueInput or addHotkeyValueInput:trim() == "" then
                addon:Print("Please enter a hotkey value")
                return
            end
            local spellID = tonumber(addHotkeySpellInput)
            if spellID and spellID > 0 then
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                if not spellInfo or not spellInfo.name then
                    addon:Print("Invalid spell ID: " .. spellID .. " (spell not found)")
                    return
                end
                hotkeyOverrides[spellID] = addHotkeyValueInput:trim()
                addon:Print("Hotkey set: " .. spellInfo.name .. " = '" .. addHotkeyValueInput:trim() .. "'")
                addHotkeySpellInput = ""
                addHotkeyValueInput = ""
                addon:ForceUpdate()
                Options.UpdateHotkeyOverrideOptions(addon)
            else
                addon:Print("Invalid spell ID (must be a positive number)")
            end
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
        local infoA = C_Spell.GetSpellInfo(a)
        local infoB = C_Spell.GetSpellInfo(b)
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
            local spellInfo = C_Spell.GetSpellInfo(spellID)
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
            if duration and not issecretvalue(duration) and duration > 1.5 then
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

-- Temporary storage for add spell input values
local addSpellInputValues = {}

-- Helper to create add spell input with Add button for a list
local function CreateAddSpellInput(addon, defensivesArgs, spellList, listType, order, listName)
    -- Initialize input value storage
    addSpellInputValues[listType] = addSpellInputValues[listType] or ""
    
    -- Input field for spell ID
    defensivesArgs["add_input_" .. listType] = {
        type = "input",
        name = L["Add to %s"]:format(listName),
        desc = L["Add spell desc"],
        order = order,
        width = "normal",
        get = function() return addSpellInputValues[listType] or "" end,
        set = function(_, val)
            addSpellInputValues[listType] = val or ""
        end
    }
    
    -- Add button to submit the spell ID
    defensivesArgs["add_button_" .. listType] = {
        type = "execute",
        name = L["Add"],
        order = order + 0.1,
        width = "half",
        func = function()
            local val = addSpellInputValues[listType]
            if not val or val:trim() == "" then return end
            
            local spellID = tonumber(val)
            if spellID and spellID > 0 then
                -- Validate spell exists
                local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
                if not spellInfo or not spellInfo.name then
                    addon:Print("Invalid spell ID: " .. spellID .. " (spell not found)")
                    return
                end
                
                -- Check if already in list
                for _, existingID in ipairs(spellList) do
                    if existingID == spellID then
                        addon:Print("Spell already in list: " .. spellInfo.name)
                        return
                    end
                end
                
                table.insert(spellList, spellID)
                addon:Print("Added: " .. spellInfo.name)
                addSpellInputValues[listType] = ""  -- Clear input after successful add
                Options.UpdateDefensivesOptions(addon)
            else
                addon:Print("Invalid spell ID (must be a positive number)")
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
        info = true, header = true, enabled = true, thresholdInfo = true,
        behaviorHeader = true, showOnlyInCombat = true, alwaysShowDefensive = true, showHealthBar = true,
        position = true, iconScale = true, maxIcons = true,
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
                        get = function() return addon.db.profile.firstIconScale or 1.2 end,
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
                        width = "normal",
                        get = function() return addon.db.profile.focusEmphasis ~= false end,
                        set = function(_, val)
                            addon.db.profile.focusEmphasis = val
                            addon:ForceUpdate()
                        end
                    },
                    includeHiddenAbilities = {
                        type = "toggle",
                        name = L["Include All Available Abilities"],
                        desc = L["Include All Available Abilities desc"],
                        order = 12,
                        width = "normal",
                        get = function() return addon.db.profile.includeHiddenAbilities ~= false end,
                        set = function(_, val)
                            addon.db.profile.includeHiddenAbilities = val
                            addon:ForceUpdate()
                        end
                    },
                    showTooltips = {
                        type = "toggle",
                        name = L["Show Tooltips"],
                        desc = L["Show Tooltips desc"],
                        order = 13,
                        width = "normal",
                        get = function() return addon.db.profile.showTooltips ~= false end,
                        set = function(_, val)
                            addon.db.profile.showTooltips = val
                        end
                    },
                    tooltipsInCombat = {
                        type = "toggle",
                        name = L["Tooltips in Combat"],
                        desc = L["Tooltips in Combat desc"],
                        order = 15,
                        width = "normal",
                        disabled = function() return not addon.db.profile.showTooltips end,
                        get = function() return addon.db.profile.tooltipsInCombat or false end,
                        set = function(_, val)
                            addon.db.profile.tooltipsInCombat = val
                        end
                    },
                    showSpellbookProcs = {
                        type = "toggle",
                        name = L["Insert Procced Abilities"],
                        desc = L["Insert Procced Abilities desc"],
                        order = 16,
                        width = "normal",
                        get = function() return addon.db.profile.showSpellbookProcs or false end,
                        set = function(_, val)
                            addon.db.profile.showSpellbookProcs = val
                            addon:ForceUpdate()
                        end
                    },
                    hideQueueOutOfCombat = {
                        type = "toggle",
                        name = L["Hide Out of Combat"],
                        desc = L["Hide Out of Combat desc"],
                        order = 17,
                        width = "normal",
                        get = function() return addon.db.profile.hideQueueOutOfCombat end,
                        set = function(_, val)
                            addon.db.profile.hideQueueOutOfCombat = val
                            addon:ForceUpdate()
                        end
                    },
                    hideQueueForHealers = {
                        type = "toggle",
                        name = L["Hide for Healer Specs"],
                        desc = L["Hide for Healer Specs desc"],
                        order = 18,
                        width = "normal",
                        get = function() return addon.db.profile.hideQueueForHealers end,
                        set = function(_, val)
                            addon.db.profile.hideQueueForHealers = val
                            addon:ForceUpdate()
                        end
                    },
                    hideQueueWhenMounted = {
                        type = "toggle",
                        name = L["Hide When Mounted"],
                        desc = L["Hide When Mounted desc"],
                        order = 19,
                        width = "normal",
                        get = function() return addon.db.profile.hideQueueWhenMounted end,
                        set = function(_, val)
                            addon.db.profile.hideQueueWhenMounted = val
                            addon:ForceUpdate()
                        end
                    },
                    hideItemAbilities = {
                        type = "toggle",
                        name = L["Hide Item Abilities"],
                        desc = L["Hide Item Abilities desc"],
                        order = 19.5,
                        width = "normal",
                        get = function() return addon.db.profile.hideItemAbilities end,
                        set = function(_, val)
                            addon.db.profile.hideItemAbilities = val
                            addon:ForceUpdate()
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
                            -- Refresh cached debug mode immediately
                            local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
                            if BlizzardAPI and BlizzardAPI.RefreshDebugMode then
                                BlizzardAPI.RefreshDebugMode()
                            end
                            addon:Print("Debug: " .. (val and "ON" or "OFF"))
                        end
                    }
                }
            },
            hotkeyOverrides = {
                type = "group",
                name = L["Hotkey Overrides"],
                order = 3,
                args = {
                    info = {
                        type = "description",
                        name = L["Hotkey Overrides Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                },
            },
            blacklist = {
                type = "group",
                name = L["Blacklist"],
                order = 4,
                args = {
                    info = {
                        type = "description",
                        name = L["Blacklist Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                },
            },
            defensives = {
                type = "group",
                name = L["Defensives"],
                order = 2,
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
                    thresholdInfo = {
                        type = "description",
                        name = "|cff888888Health thresholds: ~35% for heals, ~20% for cooldowns (approximate values)|r",
                        order = 4,
                        fontSize = "small",
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
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    alwaysShowDefensive = {
                        type = "toggle",
                        name = "Always Show Defensive Queue",
                        desc = "Show defensive queue even at full health (displays available defensive/heal abilities and procs). Useful for proactive defensive play.",
                        order = 7.5,
                        width = "full",
                        get = function() return addon.db.profile.defensives.alwaysShowDefensive end,
                        set = function(_, val)
                            addon.db.profile.defensives.alwaysShowDefensive = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    showHealthBar = {
                        type = "toggle",
                        name = "Show Health Bar",
                        desc = "Display a compact health bar above the main queue (visual only, no percentage text)",
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
                        disabled = function() return not addon.db.profile.defensives.enabled end,
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
                        get = function() return addon.db.profile.defensives.position or "SIDE1" end,
                        set = function(_, val)
                            addon.db.profile.defensives.position = val
                            UIManager.CreateSpellIcons(addon)
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return not addon.db.profile.defensives.enabled end,
                    },
                    iconScale = {
                        type = "range",
                        name = "Defensive Icon Scale",
                        desc = "Scale multiplier for defensive icons (same as Primary Spell Scale but independent)",
                        min = 1.0, max = 2.0, step = 0.1,
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
                        name = "Maximum Icons",
                        desc = "Number of defensive spells to show at once (1-3). Additional icons appear alongside the first.",
                        min = 1, max = 3, step = 1,
                        order = 11,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.maxIcons or 1 end,
                        set = function(_, val)
                            addon.db.profile.defensives.maxIcons = val
                            UIManager.CreateSpellIcons(addon)
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
            local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
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
    -- Store the category for version-aware opening
    addon.optionsCategoryID = AceConfigDialog:AddToBlizOptions("JustAssistedCombat", "JustAssistedCombat")
    
    addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
    addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
end