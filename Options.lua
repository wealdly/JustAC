-- JustAC: Options Module
local Options = LibStub:NewLibrary("JustAC-Options", 22)
if not Options then return end

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)

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
            name = "No spells currently blacklisted. Shift+Right-click a spell in the queue to add it.",
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
                    combatAssist = {
                        type = "toggle",
                        name = "Combat Assist",
                        desc = "Hide this spell from the primary 'Combat Assist' slot.",
                        order = 1,
                        get = function()
                            return blacklistedSpells[spellID] and blacklistedSpells[spellID].combatAssist
                        end,
                        set = function(_, val)
                            if not blacklistedSpells[spellID] then blacklistedSpells[spellID] = {} end
                            blacklistedSpells[spellID].combatAssist = val
                            addon:ForceUpdate()
                        end
                    },
                    fixedQueue = {
                        type = "toggle",
                        name = "Fixed Queue",
                        desc = "Hide this spell from the secondary 'Fixed Queue' slots.",
                        order = 2,
                        get = function()
                            return blacklistedSpells[spellID] and blacklistedSpells[spellID].fixedQueue
                        end,
                        set = function(_, val)
                            if not blacklistedSpells[spellID] then blacklistedSpells[spellID] = {} end
                            blacklistedSpells[spellID].fixedQueue = val
                            addon:ForceUpdate()
                        end
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 3,
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
            name = "No custom hotkeys set. Right-click a spell in the queue to set a custom hotkey display.",
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
                        name = "Custom Hotkey",
                        desc = "Text to display as hotkey (e.g., 'F1', 'Ctrl+Q', 'Mouse4')",
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
                        name = "Remove",
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
                    name = "▲",
                    desc = "Move up in priority",
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
                    name = "▼",
                    desc = "Move down in priority",
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
                    name = "Remove",
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
        name = "Add to " .. listName,
        desc = "Enter a spell ID (e.g., 48707) to add",
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
                        addon:Print("Spell already in " .. listName)
                        return
                    end
                end
                
                table.insert(spellList, spellID)
                local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                addon:Print("Added " .. name .. " to " .. listName)
                Options.UpdateDefensivesOptions(addon)
            else
                addon:Print("Invalid spell ID: " .. val)
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
        showOnlyInCombat = true, showOnlyUsable = true, 
        glowHeader = true, glowColor = true, 
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
        name = "JustAssistedCombat",
        handler = addon,
        type = "group",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    info = {
                        type = "description",
                        name = "Configure the appearance and behavior of the spell queue display.",
                        order = 1,
                        fontSize = "medium"
                    },
                    visualHeader = {
                        type = "header",
                        name = "Icon Layout",
                        order = 2,
                    },
                    maxIcons = {
                        type = "range",
                        name = "Max Icons",
                        desc = "Number of spell icons to display (higher = more spells visible)",
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
                        name = "Icon Size",
                        desc = "Base size of spell icons in pixels (higher = larger icons)",
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
                        name = "Spacing",
                        desc = "Space between icons in pixels (higher = more spread out)",
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
                        name = "Primary Spell Scale",
                        desc = "Scale multiplier for the first spell icon (1.0 = same size, 2.0 = double size)",
                        min = 1.0, max = 2.0, step = 0.1,
                        order = 6,
                        width = "normal",
                        get = function() return addon.db.profile.firstIconScale or 1.4 end,
                        set = function(_, val)
                            addon.db.profile.firstIconScale = val
                            addon:UpdateFrameSize()
                        end
                    },
                    behaviorHeader = {
                        type = "header",
                        name = "Display Behavior",
                        order = 10,
                    },
                    focusEmphasis = {
                        type = "toggle",
                        name = "Highlight Primary Spell",
                        desc = "Show animation on the first recommended spell",
                        order = 11,
                        width = "full",
                        get = function() return addon.db.profile.focusEmphasis ~= false end,
                        set = function(_, val)
                            addon.db.profile.focusEmphasis = val
                            addon:ForceUpdate()
                        end
                    },
                    greyoutNoHotkey = {
                        type = "toggle",
                        name = "Grey Unbound Spells",
                        desc = "Desaturate icons without hotkeys",
                        order = 12,
                        width = "full",
                        get = function() return addon.db.profile.greyoutNoHotkey ~= false end,
                        set = function(_, val) 
                            addon.db.profile.greyoutNoHotkey = val
                            addon:ForceUpdate()
                        end
                    },
                    showTooltips = {
                        type = "toggle",
                        name = "Show Tooltips",
                        desc = "Display spell tooltips on hover",
                        order = 13,
                        width = "full",
                        get = function() return addon.db.profile.showTooltips ~= false end,
                        set = function(_, val)
                            addon.db.profile.showTooltips = val
                        end
                    },
                    tooltipsInCombat = {
                        type = "toggle",
                        name = "Tooltips in Combat",
                        desc = "Show tooltips during combat (when tooltips are enabled)",
                        order = 14,
                        width = "full",
                        disabled = function() return not addon.db.profile.showTooltips end,
                        get = function() return addon.db.profile.tooltipsInCombat or false end,
                        set = function(_, val)
                            addon.db.profile.tooltipsInCombat = val
                        end
                    },
                    glowHeader = {
                        type = "header",
                        name = "Glow Effects",
                        order = 20,
                    },
                    glowAlpha = {
                        type = "range",
                        name = "Glow Intensity",
                        desc = "Visibility of the glow effect (0 = invisible, 1 = fully visible)",
                        min = 0.1, max = 1.0, step = 0.05,
                        order = 21,
                        width = "normal",
                        get = function() return addon.db.profile.glowAlpha or 0.75 end,
                        set = function(_, val)
                            addon.db.profile.glowAlpha = val
                            addon:ForceUpdate()
                        end
                    },
                    glowColor = {
                        type = "color",
                        name = "Assisted Glow Color",
                        desc = "Color tint for the primary spell highlight (proc'd spells always glow gold)",
                        order = 22,
                        width = "normal",
                        hasAlpha = false,
                        get = function()
                            return addon.db.profile.glowColorR or 0.3,
                                   addon.db.profile.glowColorG or 0.7,
                                   addon.db.profile.glowColorB or 1.0
                        end,
                        set = function(_, r, g, b)
                            addon.db.profile.glowColorR = r
                            addon.db.profile.glowColorG = g
                            addon.db.profile.glowColorB = b
                            addon:ForceUpdate()
                        end
                    },
                    queueDesaturation = {
                        type = "range",
                        name = "Queue Icon Fade",
                        desc = "Desaturation for icons in positions 2+ (0 = full color, 1 = grayscale)",
                        min = 0, max = 1.0, step = 0.05,
                        order = 23,
                        width = "normal",
                        get = function() return addon.db.profile.queueIconDesaturation or 0.35 end,
                        set = function(_, val)
                            addon.db.profile.queueIconDesaturation = val
                            addon:ForceUpdate()
                        end
                    },
                    systemHeader = {
                        type = "header",
                        name = "System",
                        order = 30,
                    },
                    autoEnableAssistedMode = {
                        type = "toggle",
                        name = "Auto-Enable Assisted Combat",
                        desc = "Automatically enable Blizzard's Assisted Combat mode on login (recommended)",
                        order = 31,
                        width = "full",
                        get = function() return addon.db.profile.autoEnableAssistedMode ~= false end,
                        set = function(_, val)
                            addon.db.profile.autoEnableAssistedMode = val
                        end
                    },
                    debugMode = {
                        type = "toggle",
                        name = "Debug Mode",
                        desc = "Show detailed addon information in chat for troubleshooting",
                        order = 32,
                        width = "full",
                        get = function() return addon.db.profile.debugMode or false end,
                        set = function(_, val) 
                            addon.db.profile.debugMode = val
                            addon:Print("Debug mode: " .. (val and "ON" or "OFF"))
                        end
                    }
                }
            },
            hotkeyOverrides = {
                type = "group",
                name = "Hotkey Overrides",
                order = 2,
                args = {
                    info = {
                        type = "description",
                        name = "Set custom hotkey text for spells when automatic detection fails or for personal preference.\n\n|cff00ff00Right-click|r a spell icon in the queue to set a custom hotkey.\n|cffff6666Shift+Right-click|r to blacklist a spell.",
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = "Custom Hotkey Displays",
                        order = 2,
                    },
                },
            },
            blacklist = {
                type = "group",
                name = "Blacklist",
                order = 3,
                args = {
                    info = {
                        type = "description",
                        name = "Shift+Right-click a spell icon in the queue to add it to this list. You can then customize where it should be hidden.",
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = "Blacklisted Spells",
                        order = 2,
                    },
                },
            },
            defensives = {
                type = "group",
                name = "Defensives",
                order = 4,
                args = {
                    info = {
                        type = "description",
                        name = "Two-tier defensive system:\n|cff00ff00• Self-Heals|r (higher threshold): Quick abilities to weave into rotation\n|cffff6666• Major Cooldowns|r (lower threshold): Emergency defensives when critically low\n\nThe icon appears |cff00ff00left of position 1|r with a green glow.",
                        order = 1,
                        fontSize = "medium"
                    },
                    header = {
                        type = "header",
                        name = "Threshold Settings",
                        order = 2,
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enable Defensive Suggestions",
                        desc = "Show a defensive spell suggestion when health is low",
                        order = 3,
                        width = "full",
                        get = function() return addon.db.profile.defensives.enabled end,
                        set = function(_, val)
                            addon.db.profile.defensives.enabled = val
                            addon:ForceUpdate()
                        end
                    },
                    selfHealThreshold = {
                        type = "range",
                        name = "Self-Heal Threshold",
                        desc = "Show self-heal suggestions when health falls below this percentage (higher = triggers sooner)",
                        min = 30, max = 90, step = 5,
                        order = 4,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.selfHealThreshold or 70 end,
                        set = function(_, val)
                            addon.db.profile.defensives.selfHealThreshold = val
                        end
                    },
                    cooldownThreshold = {
                        type = "range",
                        name = "Cooldown Threshold",
                        desc = "Show major cooldown suggestions when health falls below this percentage (higher = triggers sooner)",
                        min = 10, max = 70, step = 5,
                        order = 5,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.cooldownThreshold or 50 end,
                        set = function(_, val)
                            addon.db.profile.defensives.cooldownThreshold = val
                        end
                    },
                    behaviorHeader = {
                        type = "header",
                        name = "Display Behavior",
                        order = 6,
                    },
                    showOnlyInCombat = {
                        type = "toggle",
                        name = "Only In Combat",
                        desc = "Only show defensive suggestions during combat",
                        order = 7,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showOnlyInCombat end,
                        set = function(_, val)
                            addon.db.profile.defensives.showOnlyInCombat = val
                        end
                    },
                    showOnlyUsable = {
                        type = "toggle",
                        name = "Only Usable Spells",
                        desc = "Skip spells that are on cooldown",
                        order = 8,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showOnlyUsable end,
                        set = function(_, val)
                            addon.db.profile.defensives.showOnlyUsable = val
                        end
                    },
                    glowHeader = {
                        type = "header",
                        name = "Glow Effects",
                        order = 9,
                    },
                    glowColor = {
                        type = "color",
                        name = "Defensive Glow Color",
                        desc = "Color for the defensive spell highlight (green by default)",
                        order = 10,
                        width = "normal",
                        hasAlpha = false,
                        get = function()
                            return addon.db.profile.defensives.glowColorR or 0.0,
                                   addon.db.profile.defensives.glowColorG or 1.0,
                                   addon.db.profile.defensives.glowColorB or 0.0
                        end,
                        set = function(_, r, g, b)
                            addon.db.profile.defensives.glowColorR = r
                            addon.db.profile.defensives.glowColorG = g
                            addon.db.profile.defensives.glowColorB = b
                            addon:ForceUpdate()
                        end
                    },
                    selfHealHeader = {
                        type = "header",
                        name = "Self-Heal Priority List (checked first)",
                        order = 20,
                    },
                    selfHealInfo = {
                        type = "description",
                        name = "Quick heals/absorbs to weave into your rotation. First usable spell is suggested.",
                        order = 21,
                        fontSize = "small"
                    },
                    restoreSelfHealDefaults = {
                        type = "execute",
                        name = "Restore Class Defaults",
                        desc = "Reset the self-heal list to default spells for your class",
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
                        name = "Major Cooldowns Priority List (emergency)",
                        order = 50,
                    },
                    cooldownInfo = {
                        type = "description",
                        name = "Big defensives for emergencies. Only checked if no self-heal is available and health is critically low.",
                        order = 51,
                        fontSize = "small"
                    },
                    restoreCooldownDefaults = {
                        type = "execute",
                        name = "Restore Class Defaults",
                        desc = "Reset the cooldown list to default spells for your class",
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
                name = "Profiles",
                desc = "Character and spec profile management",
                order = 10,
                args = {}
            },
            about = {
                type = "group",
                name = "About",
                order = 11,
                args = {
                    aboutHeader = {
                        type = "header",
                        name = "About JustAssistedCombat",
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
                        name = "|cffffff00Slash Commands:|r\n|cff88ff88/jac|r - Open options\n|cff88ff88/jac toggle|r - Pause/resume\n|cff88ff88/jac debug|r - Toggle debug mode\n|cff88ff88/jac test|r - Test Blizzard API\n|cff88ff88/jac formcheck|r - Check form detection\n|cff88ff88/jac find <spell>|r - Locate spell\n|cff88ff88/jac reset|r - Reset position\n\nType |cff88ff88/jac help|r for full command list",
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
                addon:Print("Display paused.")
            else
                addon:StartUpdates()
                addon:Print("Display resumed.")
            end
        end
        
    elseif command == "debug" then
        if addon.db and addon.db.profile then
            addon.db.profile.debugMode = not addon.db.profile.debugMode
            addon:Print("Debug mode: " .. (addon.db.profile.debugMode and "ON" or "OFF"))
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
            addon:Print("Frame position reset")
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