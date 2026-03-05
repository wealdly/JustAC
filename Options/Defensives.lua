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
        order = 5,
        childGroups = "tab",
        args = {
            -- ── SUB-TAB 1: QUEUE CONTENT ─────────────────────────────────
            settings = {
                type = "group",
                name = L["Queue Content"],
                order = 1,
                args = {
            showProcs = {
                type = "toggle",
                name = L["Insert Procced Defensives"],
                desc = L["Insert Procced Defensives desc"],
                order = 1,
                width = "full",
                get = function() return addon.db.profile.defensives.showProcs ~= false end,
                set = function(_, val)
                    addon.db.profile.defensives.showProcs = val
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" then return true end
                    local standardEnabled = addon.db.profile.defensives.enabled
                    local npo = addon.db.profile.nameplateOverlay
                    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                    return not standardEnabled and not overlayEnabled
                end,
            },
            -- ITEMS (3-5)
            itemsHeader = {
                type = "header",
                name = L["Items"],
                order = 3,
            },
            allowItems = {
                type = "toggle",
                name = L["Allow Items in Spell Lists"],
                desc = L["Allow Items in Spell Lists desc"],
                order = 4,
                width = "full",
                get = function() return addon.db.profile.defensives.allowItems == true end,
                set = function(_, val)
                    addon.db.profile.defensives.allowItems = val
                    Defensives.UpdateDefensivesOptions(addon)
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" then return true end
                    local standardEnabled = addon.db.profile.defensives.enabled
                    local npo = addon.db.profile.nameplateOverlay
                    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                    return not standardEnabled and not overlayEnabled
                end,
            },
            autoInsertPotions = {
                type = "toggle",
                name = L["Auto-Insert Health Potions"],
                desc = L["Auto-Insert Health Potions desc"],
                order = 5,
                width = "full",
                get = function() return addon.db.profile.defensives.autoInsertPotions ~= false end,
                set = function(_, val)
                    addon.db.profile.defensives.autoInsertPotions = val
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" then return true end
                    local standardEnabled = addon.db.profile.defensives.enabled
                    local npo = addon.db.profile.nameplateOverlay
                    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                    return not standardEnabled and not overlayEnabled
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
                    def.showProcs        = true
                    def.allowItems       = true
                    def.autoInsertPotions = true
                    addon:ForceUpdateAll()
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
                    local specIndex = GetSpecializationInfo and GetSpecialization and GetSpecialization()
                    local specName
                    if specIndex then
                        local _, name = GetSpecializationInfo(specIndex)
                        specName = name
                    end
                    return "|c" .. colorCode .. (className or "Unknown") .. "|r Defensive Spells" .. (specName and (" (" .. specName .. ")") or "")
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

    local DefensiveEngine = LibStub("JustAC-DefensiveEngine", true)
    local specKey, playerClass
    if DefensiveEngine and DefensiveEngine.GetDefensiveSpecKey then
        specKey, playerClass = DefensiveEngine.GetDefensiveSpecKey()
    else
        local _
        _, playerClass = UnitClass("player")
    end

    -- Resolve spell lists using spec→class fallback
    local defensiveSpells, petRezSpells, petHealSpells
    local targetKey = specKey  -- prefer spec key
    if targetKey and defensives.classSpells and defensives.classSpells[targetKey] then
        defensiveSpells = defensives.classSpells[targetKey].defensiveSpells
        petRezSpells = defensives.classSpells[targetKey].petRezSpells
        petHealSpells = defensives.classSpells[targetKey].petHealSpells
    elseif playerClass and defensives.classSpells and defensives.classSpells[playerClass] then
        -- Class-level fallback (legacy data not yet migrated to per-spec)
        targetKey = playerClass
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
