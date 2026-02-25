-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/GapClosers - Gap-closer settings tab + spell list management
local GapClosers = LibStub:NewLibrary("JustAC-OptionsGapClosers", 1)
if not GapClosers then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local DefensiveEngine = LibStub("JustAC-DefensiveEngine", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function GapClosers.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Gap-Closers"],
        order = 2,
        args = {
            behaviorNote = {
                type = "description",
                name = L["Gap-Closer Behavior Note"],
                order = 0,
                fontSize = "medium",
            },
            enabled = {
                type = "toggle",
                name = L["Enable Gap-Closer Suggestions"],
                desc = L["Enable Gap-Closer Suggestions desc"],
                order = 1,
                width = "full",
                get = function()
                    local profile = addon:GetProfile()
                    return profile and profile.gapClosers and profile.gapClosers.enabled
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    if not profile then return end
                    if not profile.gapClosers then
                        profile.gapClosers = { enabled = val, classSpells = {} }
                    else
                        profile.gapClosers.enabled = val
                    end
                    addon:ForceUpdateAll()
                end,
            },
            showGlow = {
                type = "toggle",
                name = L["Show Gap-Closer Glow"],
                desc = L["Show Gap-Closer Glow desc"],
                order = 2,
                width = "full",
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.gapClosers and profile.gapClosers.enabled)
                end,
                get = function()
                    local profile = addon:GetProfile()
                    return profile and profile.gapClosers and profile.gapClosers.showGlow == true
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    if not profile then return end
                    if not profile.gapClosers then
                        profile.gapClosers = { enabled = true, showGlow = val, classSpells = {} }
                    else
                        profile.gapClosers.showGlow = val
                    end
                    addon:ForceUpdateAll()
                end,
            },
            meleeRangeGroup = {
                type = "group",
                inline = true,
                name = L["Melee Range Reference"],
                order = 5,
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.gapClosers and profile.gapClosers.enabled)
                end,
                args = {
                    meleeRangeInfo = {
                        type = "description",
                        name = L["Melee Range Spell desc"],
                        order = 1,
                        fontSize = "small",
                    },
                    currentDefault = {
                        type = "description",
                        name = function()
                            local DE = DefensiveEngine or LibStub("JustAC-DefensiveEngine", true)
                            local SDB = LibStub("JustAC-SpellDB", true)
                            local specKey = DE and DE.GetGapCloserSpecKey and DE.GetGapCloserSpecKey()
                            if not specKey or not SDB or not SDB.MELEE_RANGE_REFERENCE_SPELLS then
                                return L["Default"] .. ": " .. L["Unknown"]
                            end
                            local defaults = SDB.MELEE_RANGE_REFERENCE_SPELLS[specKey]
                            local refID = defaults and defaults[1]
                            if not refID then return L["Default"] .. ": " .. L["None"] end
                            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(refID)
                            local name = info and info.name or tostring(refID)
                            return L["Default"] .. ": |cFF00FF00" .. name .. "|r (" .. refID .. ")"
                        end,
                        order = 2,
                        fontSize = "medium",
                    },
                    meleeRangeSpell = {
                        type = "input",
                        name = L["Melee Range Spell ID"],
                        desc = L["Melee Range Spell Override desc"],
                        order = 3,
                        width = "normal",
                        get = function()
                            local profile = addon:GetProfile()
                            local gc = profile and profile.gapClosers
                            local val = gc and gc.meleeRangeSpell or 0
                            return val > 0 and tostring(val) or ""
                        end,
                        set = function(_, val)
                            local profile = addon:GetProfile()
                            if not profile then return end
                            if not profile.gapClosers then
                                profile.gapClosers = { enabled = true, classSpells = {} }
                            end
                            local id = tonumber(val) or 0
                            profile.gapClosers.meleeRangeSpell = id > 0 and id or nil
                            local DE = DefensiveEngine or LibStub("JustAC-DefensiveEngine", true)
                            if DE and DE.InvalidateGapCloserCache then
                                DE.InvalidateGapCloserCache()
                            end
                            addon:ForceUpdateAll()
                        end,
                    },
                },
            },
            -- SPELL LIST (10+)
            spellListGroup = {
                type = "group",
                inline = true,
                name = function()
                    local className, playerClass = UnitClass("player")
                    local colorCode = (playerClass and SpellSearch and SpellSearch.CLASS_COLORS
                        and SpellSearch.CLASS_COLORS[playerClass]) or "FFFFFFFF"
                    local specIndex = GetSpecialization and GetSpecialization()
                    local specName
                    if specIndex then
                        local _, name = GetSpecializationInfo(specIndex)
                        specName = name
                    end
                    return "|c" .. colorCode .. (className or "Unknown") .. "|r Gap-Closers (" .. (specName or "?") .. ")"
                end,
                order = 10,
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.gapClosers and profile.gapClosers.enabled)
                end,
                args = {
                    gcHeader = {
                        type = "header",
                        name = L["Gap-Closer Priority List"],
                        order = 10,
                    },
                    gcInfo = {
                        type = "description",
                        name = L["Gap-Closer Priority desc"],
                        order = 11,
                        fontSize = "small",
                    },
                    restoreGapCloserDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults"],
                        desc = L["Restore Gap-Closer Defaults desc"],
                        order = 32,
                        width = "normal",
                        func = function()
                            local DE = DefensiveEngine or LibStub("JustAC-DefensiveEngine", true)
                            if DE and DE.RestoreGapCloserDefaults then
                                DE.RestoreGapCloserDefaults(addon)
                            end
                            GapClosers.UpdateGapCloserOptions(addon)
                        end,
                    },
                    -- Dynamic spell entries added by UpdateGapCloserOptions
                },
            },
        },
    }
end

function GapClosers.UpdateGapCloserOptions(addon)
    -- Ensure gap-closer defaults are populated before reading data
    -- (covers profile reset, first load, spec change without prior init)
    local DE = DefensiveEngine or LibStub("JustAC-DefensiveEngine", true)
    if DE and DE.InitializeGapClosers then
        DE.InitializeGapClosers(addon)
    end

    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local offTab = optionsTable.args.offensive
    if not offTab then return end
    local gcTab = offTab.args.gapClosers
    if not gcTab then return end
    local spellListGroup = gcTab.args.spellListGroup
    if not spellListGroup then return end
    local spellListArgs = spellListGroup.args

    -- Clear dynamic entries, preserve static ones
    local staticKeys = {
        gcHeader = true, gcInfo = true, restoreGapCloserDefaults = true,
    }

    local keysToClear = {}
    for key, _ in pairs(spellListArgs) do
        if not staticKeys[key] then
            keysToClear[#keysToClear + 1] = key
        end
    end
    for _, key in ipairs(keysToClear) do
        spellListArgs[key] = nil
    end

    local DE = DefensiveEngine or LibStub("JustAC-DefensiveEngine", true)
    local specKey = DE and DE.GetGapCloserSpecKey and DE.GetGapCloserSpecKey()
    if not specKey then return end

    local profile = addon:GetProfile()
    if not profile then return end

    -- Ensure gapClosers structure exists
    if not profile.gapClosers then
        profile.gapClosers = { enabled = true, classSpells = {} }
    end
    if not profile.gapClosers.classSpells then
        profile.gapClosers.classSpells = {}
    end

    -- Ensure spell list table exists (mirrors defensive initialization pattern)
    -- so CreateAddSpellInput receives a valid reference for add/remove closures
    if not profile.gapClosers.classSpells[specKey] then
        profile.gapClosers.classSpells[specKey] = {}
    end
    local spellList = profile.gapClosers.classSpells[specKey]

    -- Show empty-state description if no spells configured
    if #spellList == 0 then
        spellListArgs.emptyNote = {
            type = "description",
            name = L["No Gap-Closer Spells"],
            order = 12,
            fontSize = "medium",
        }
    end

    if not SpellSearch then
        SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
    end
    if not SpellSearch then return end

    local updateFunc = function()
        -- Invalidate engine cache so ResolveGapCloserSpells picks up changes
        local DE = DefensiveEngine or LibStub("JustAC-DefensiveEngine", true)
        if DE and DE.InvalidateGapCloserCache then
            DE.InvalidateGapCloserCache()
        end
        GapClosers.UpdateGapCloserOptions(addon)
    end

    -- Gap-closer spells (order 12.0-29.9, allowing 180 entries)
    SpellSearch.CreateSpellListEntries(addon, spellListArgs, spellList, "gapcloser", 12, updateFunc)
    SpellSearch.CreateAddSpellInput(addon, spellListArgs, spellList, "gapcloser", 30, "Gap-Closers", updateFunc)

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
