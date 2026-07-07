-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/GapClosers - Gap-closer settings tab + spell list management
local GapClosers = LibStub:NewLibrary("JustAC-OptionsGapClosers", 1)
if not GapClosers then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local W = LibStub("JustAC-OptionsWidgets")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local GapCloserEngine = LibStub("JustAC-GapCloserEngine", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function GapClosers.CreateTabArgs(addon)
    local tab = {
        type = "group",
        name = L["Gap-Closers"],
        order = 3,
        args = {
            rangedSpecNote = {
                type = "description",
                name = "|cFFFF8800" .. L["Gap-Closer Ranged Spec Note"] .. "|r",
                order = -1,
                fontSize = "medium",
                hidden = function()
                    if not SpellDB then SpellDB = LibStub("JustAC-SpellDB", true) end
                    return not SpellDB or not SpellDB.IsMeleeSpec or SpellDB.IsMeleeSpec()
                end,
            },
            behaviorNote = {
                type = "description",
                name = L["Gap-Closer Behavior Note"],
                order = 0,
                fontSize = "medium",
            },
            enabled = W.toggle(addon, "gapClosers.enabled", {
                name = L["Enable Gap-Closer Suggestions"], desc = L["Enable Gap-Closer Suggestions desc"],
                order = 1, width = "full",
                onSet = function() addon:ForceUpdate() end,
            }),
            showGlow = W.toggle(addon, "gapClosers.showGlow", {
                name = L["Show Gap-Closer Glow"], desc = L["Show Gap-Closer Glow desc"],
                order = 2, width = "full",
                onSet = function() addon:ForceUpdate() end,
                disabled = function(a)
                    local profile = a:GetProfile()
                    return not (profile and profile.gapClosers and profile.gapClosers.enabled)
                end,
            }),
            -- SPELL LIST (10+)
            spellListGroup = {
                type = "group",
                inline = true,
                name = SpellSearch.SpecHeader(L["Gap-Closers"]),
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
                            local GCE = GapCloserEngine or LibStub("JustAC-GapCloserEngine", true)
                            if GCE and GCE.RestoreGapCloserDefaults then
                                GCE.RestoreGapCloserDefaults(addon)
                            end
                            GapClosers.UpdateGapCloserOptions(addon)
                        end,
                    },
                    -- Dynamic spell entries added by UpdateGapCloserOptions
                },
            },
        },
    }
    tab.args.resetHeader, tab.args.resetDefaults = W.resetButton(990, L["Reset Gap-Closers desc"], function()
        local profile = addon:GetProfile()
        if not profile then return end
        if not profile.gapClosers then
            profile.gapClosers = { enabled = false, classSpells = {} }
        end
        profile.gapClosers.enabled = false
        profile.gapClosers.showGlow = true  -- default: true (glow on by default)
        local GCE = GapCloserEngine or LibStub("JustAC-GapCloserEngine", true)
        if GCE and GCE.InvalidateGapCloserCache then
            GCE.InvalidateGapCloserCache()
        end
        addon:ForceUpdate()
        if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
    end)
    return tab
end

function GapClosers.UpdateGapCloserOptions(addon)
    -- Ensure gap-closer defaults are populated before reading data
    -- (covers profile reset, first load, spec change without prior init)
    local GCE = GapCloserEngine or LibStub("JustAC-GapCloserEngine", true)
    if GCE and GCE.InitializeGapClosers then
        GCE.InitializeGapClosers(addon)
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
    SpellSearch.ClearDynamicArgs(spellListArgs, staticKeys)

    local GCE = GapCloserEngine or LibStub("JustAC-GapCloserEngine", true)
    local specKey = GCE and GCE.GetGapCloserSpecKey and GCE.GetGapCloserSpecKey()
    if not specKey then return end

    local profile = addon:GetProfile()
    if not profile then return end

    -- Ensure gapClosers structure exists
    if not profile.gapClosers then
        profile.gapClosers = { enabled = false, classSpells = {} }
    end
    if not profile.gapClosers.classSpells then
        profile.gapClosers.classSpells = {}
    end

    -- Ensure spell list table exists (mirrors defensive initialization pattern)
    -- so CreateAddSpellButton closures receive a valid reference for add/remove
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
        local engine = GapCloserEngine or LibStub("JustAC-GapCloserEngine", true)
        if engine and engine.InvalidateGapCloserCache then
            engine.InvalidateGapCloserCache()
        end
        GapClosers.UpdateGapCloserOptions(addon)
        addon:ForceUpdate()
    end

    -- Gap-closer spells (order 12.0-29.9, allowing 180 entries)
    SpellSearch.CreateSpellListEntries(addon, spellListArgs, spellList, "gapcloser", 12, updateFunc)
    SpellSearch.CreateAddSpellButton(addon, spellListArgs, spellList, "gapcloser", 30, "Gap-Closers", updateFunc, true)

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
