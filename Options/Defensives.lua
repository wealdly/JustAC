-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Defensives - Defensive queue settings tab + spell list management
local Defensives = LibStub:NewLibrary("JustAC-OptionsDefensives", 1)
if not Defensives then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function Defensives.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Defensives"],
        order = 4,
        childGroups = "tab",
        args = {
            -- ── SUB-TAB 1: QUEUE SETTINGS ───────────────────────────────────
            settings = {
                type = "group",
                name = L["Queue Settings"],
                order = 1,
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
                    Defensives.UpdateDefensivesOptions(addon)
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
            glowMode = {
                type = "select",
                name = L["Highlight Mode"],
                desc = L["Highlight Mode desc"],
                order = 7,
                width = "normal",
                values = {
                    all         = L["All Glows"],
                    primaryOnly = L["Primary Only"],
                    procOnly    = L["Proc Only"],
                    none        = L["No Glows"],
                },
                sorting = {"all", "primaryOnly", "procOnly", "none"},
                get = function()
                    return addon.db.profile.defensives.glowMode or "all"
                end,
                set = function(_, val)
                    addon.db.profile.defensives.glowMode = val
                    addon:ForceUpdateAll()
                end,
                disabled = function() return not addon.db.profile.defensives.enabled end,
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
                    def.position         = "SIDE1"
                    def.showHealthBar    = true
                    def.showPetHealthBar = true
                    def.iconScale        = 1.0
                    def.maxIcons         = 4
                    def.selfHealThreshold = 80
                    def.petHealThreshold  = 50
                    def.allowItems        = true
                    def.autoInsertPotions = true
                    def.displayMode       = "always"
                    def.glowMode          = "all"
                    -- Clear legacy migration keys
                    def.showOnlyInCombat    = nil
                    def.alwaysShowDefensive = nil
                    def.showHotkeys         = nil
                    def.ignoreHealthPriority = nil
                    def.cooldownThreshold   = nil
                    addon:UpdateFrameSize()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
                },
            },
            -- ── SUB-TAB 2: PRIORITY LISTS ────────────────────────────────────
            priorityLists = {
                type = "group",
                name = L["Priority Lists"],
                order = 2,
                args = {
            spellListGroup = {
                type = "group",
                inline = true,
                name = function()
                    local className, playerClass = UnitClass("player")
                    local colorCode = (playerClass and SpellSearch.CLASS_COLORS[playerClass]) or "FFFFFFFF"
                    return "|c" .. colorCode .. (className or "Unknown") .. "|r Defensive Spells"
                end,
                order = 20,
                args = {
                    selfHealHeader = {
                        type = "header",
                        name = L["Defensive Priority List"],
                        order = 20,
                    },
                    selfHealInfo = {
                        type = "description",
                        name = L["Defensive Priority desc"],
                        order = 21,
                        fontSize = "small"
                    },
                    restoreSelfHealDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults"],
                        desc = L["Restore Defensive Defaults desc"],
                        order = 42,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("defensive")
                            Defensives.UpdateDefensivesOptions(addon)
                        end,
                    },
                    -- Dynamic defensiveSpells entries added by UpdateDefensivesOptions
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
                            Defensives.UpdateDefensivesOptions(addon)
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
                            Defensives.UpdateDefensivesOptions(addon)
                        end,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc])
                        end,
                    },
                    -- Dynamic petHealSpells entries added by UpdateDefensivesOptions
                },
            },
                },
            },
        },
    }
end

function Defensives.UpdateDefensivesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not SpellQueue then return end

    local priorityTab = optionsTable.args.defensives.args.priorityLists
    if not priorityTab then return end
    local spellListGroup = priorityTab.args.spellListGroup
    if not spellListGroup then return end
    local spellListArgs = spellListGroup.args

    -- Clear dynamic entries, preserve static ones
    local staticKeys = {
        selfHealHeader = true, selfHealInfo = true, restoreSelfHealDefaults = true,
        petRezHeader = true, petRezInfo = true, restorePetRezDefaults = true,
        petHealHeader = true, petHealInfo = true, restorePetHealDefaults = true,
    }

    local keysToClear = {}
    for key, _ in pairs(spellListArgs) do
        if not staticKeys[key] then
            table.insert(keysToClear, key)
        end
    end
    for _, key in ipairs(keysToClear) do
        spellListArgs[key] = nil
    end

    local defensives = addon.db.profile.defensives
    if not defensives then return end

    local _, playerClass = UnitClass("player")
    local defensiveSpells, petRezSpells, petHealSpells
    if playerClass and defensives.classSpells and defensives.classSpells[playerClass] then
        defensiveSpells = defensives.classSpells[playerClass].defensiveSpells
        petRezSpells = defensives.classSpells[playerClass].petRezSpells
        petHealSpells = defensives.classSpells[playerClass].petHealSpells
    end

    -- Determine if this is a pet class (has rez or heal defaults)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local isPetClass = SpellDB and (
        (SpellDB.CLASS_PET_REZ_DEFAULTS and SpellDB.CLASS_PET_REZ_DEFAULTS[playerClass])
        or (SpellDB.CLASS_PETHEAL_DEFAULTS and SpellDB.CLASS_PETHEAL_DEFAULTS[playerClass])
    )

    local updateFunc = function() Defensives.UpdateDefensivesOptions(addon) end

    -- Unified defensive spells (order 22.0-39.9, allowing 180 entries)
    SpellSearch.CreateSpellListEntries(addon, spellListArgs, defensiveSpells, "defensive", 22, updateFunc)
    SpellSearch.CreateAddSpellInput(addon, spellListArgs, defensiveSpells, "defensive", 40, "Defensives", updateFunc)

    -- Pet Rez/Summon spells (order 82.0-99.9, pet classes only)
    if isPetClass and petRezSpells then
        SpellSearch.CreateSpellListEntries(addon, spellListArgs, petRezSpells, "petrez", 82, updateFunc)
        SpellSearch.CreateAddSpellInput(addon, spellListArgs, petRezSpells, "petrez", 100, "Pet Rez/Summon", updateFunc)
    end

    -- Pet Heal spells (order 112.0-129.9, pet classes only)
    if isPetClass and petHealSpells then
        SpellSearch.CreateSpellListEntries(addon, spellListArgs, petHealSpells, "petheal", 112, updateFunc)
        SpellSearch.CreateAddSpellInput(addon, spellListArgs, petHealSpells, "petheal", 130, "Pet Heals", updateFunc)
    end

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
