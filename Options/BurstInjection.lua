-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/BurstInjection - Burst Injection settings tab + spell list management
local BurstInjection = LibStub:NewLibrary("JustAC-OptionsBurstInjection", 1)
if not BurstInjection then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local BurstEngine = LibStub("JustAC-BurstInjectionEngine", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function BurstInjection.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Burst Injection"] .. " |cFFFF8800(" .. L["Experimental"] .. ")|r",
        order = 1.5,
        args = {
            experimentalBanner = {
                type = "description",
                name = "|cFFFF8800" .. L["Burst Injection Experimental Note"] .. "|r",
                order = 0,
                fontSize = "medium",
            },
            behaviorNote = {
                type = "description",
                name = L["Burst Injection Behavior Note"],
                order = 0.5,
                fontSize = "medium",
            },
            enabled = {
                type = "toggle",
                name = L["Enable Burst Injection"],
                desc = L["Enable Burst Injection desc"],
                order = 1,
                width = "full",
                get = function()
                    local profile = addon:GetProfile()
                    return profile and profile.burstInjection and profile.burstInjection.enabled
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    if not profile then return end
                    if not profile.burstInjection then
                        profile.burstInjection = { enabled = val, showGlow = true, triggerSpells = {}, injectionSpells = {} }
                    else
                        profile.burstInjection.enabled = val
                    end
                    local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
                    if engine and engine.InvalidateBurstCache then engine.InvalidateBurstCache() end
                    BurstInjection.UpdateBurstInjectionOptions(addon)
                    addon:ForceUpdateAll()
                end,
            },
            showGlow = {
                type = "toggle",
                name = L["Show Burst Glow"],
                desc = L["Show Burst Glow desc"],
                order = 2,
                width = "full",
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.burstInjection and profile.burstInjection.enabled)
                end,
                get = function()
                    local profile = addon:GetProfile()
                    return profile and profile.burstInjection and profile.burstInjection.showGlow == true
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    if not profile then return end
                    if not profile.burstInjection then
                        profile.burstInjection = { enabled = true, showGlow = val, triggerSpells = {}, injectionSpells = {} }
                    else
                        profile.burstInjection.showGlow = val
                    end
                    addon:ForceUpdateAll()
                end,
            },
            fallbackDuration = {
                type = "range",
                name = L["Burst Window Duration"],
                desc = L["Burst Window Duration desc"],
                order = 3,
                width = "double",
                min = 5,
                max = 30,
                step = 1,
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.burstInjection and profile.burstInjection.enabled)
                end,
                get = function()
                    local profile = addon:GetProfile()
                    if not profile or not profile.burstInjection or not profile.burstInjection.fallbackDuration then
                        if not SpellDB then SpellDB = LibStub("JustAC-SpellDB", true) end
                        return (SpellDB and SpellDB.GetBurstDurationDefault and SpellDB.GetBurstDurationDefault()) or 10
                    end
                    return profile.burstInjection.fallbackDuration
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    if not profile then return end
                    if not profile.burstInjection then
                        profile.burstInjection = { enabled = true, showGlow = true, fallbackDuration = val, triggerSpells = {}, injectionSpells = {} }
                    else
                        profile.burstInjection.fallbackDuration = val
                    end
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
                desc = L["Reset Burst Injection desc"],
                order = 991,
                width = "normal",
                func = function()
                    local profile = addon:GetProfile()
                    if not profile then return end
                    if not profile.burstInjection then
                        profile.burstInjection = { enabled = false, showGlow = true, triggerSpells = {}, injectionSpells = {} }
                    end
                    profile.burstInjection.enabled = false
                    profile.burstInjection.showGlow = true
                    profile.burstInjection.fallbackDuration = nil

                    local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
                    if engine and engine.InvalidateBurstCache then engine.InvalidateBurstCache() end
                    addon:ForceUpdateAll()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
            -- TRIGGER SPELL OVERRIDE LIST (10+)
            triggerGroup = {
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
                    return "|c" .. colorCode .. (className or "Unknown") .. "|r " .. L["Burst Trigger Override"] .. " (" .. (specName or "?") .. ")"
                end,
                order = 10,
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.burstInjection and profile.burstInjection.enabled)
                end,
                args = {
                    triggerInfo = {
                        type = "description",
                        name = L["Burst Trigger Override desc"],
                        order = 11,
                        fontSize = "small",
                    },
                    detectedTriggers = {
                        type = "description",
                        name = function()
                            local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
                            if not engine or not engine.GetDetectedTriggers then
                                return L["Detected Burst Triggers"] .. " —"
                            end
                            local triggers = engine.GetDetectedTriggers(addon)
                            if not triggers or #triggers == 0 then
                                return L["Detected Burst Triggers"] .. " " .. L["Detected Burst Triggers None"]
                            end
                            local parts = {}
                            for _, t in ipairs(triggers) do
                                parts[#parts + 1] = t.name .. " (" .. math.floor(t.baseCd) .. "s)"
                            end
                            return L["Detected Burst Triggers"] .. " " .. table.concat(parts, ", ")
                        end,
                        order = 11.5,
                        fontSize = "medium",
                        hidden = function()
                            local profile = addon:GetProfile()
                            return not (profile and profile.burstInjection and profile.burstInjection.enabled)
                        end,
                    },
                    clearTriggerOverrides = {
                        type = "execute",
                        name = L["Clear Trigger Overrides"],
                        desc = L["Clear Trigger Overrides desc"],
                        order = 32,
                        width = "normal",
                        disabled = function()
                            local profile = addon:GetProfile()
                            if not profile or not profile.burstInjection then return true end
                            local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
                            local specKey = engine and engine.GetBurstSpecKey and engine.GetBurstSpecKey()
                            if not specKey then return true end
                            local triggers = profile.burstInjection.triggerSpells
                            return not (triggers and triggers[specKey] and #triggers[specKey] > 0)
                        end,
                        func = function()
                            local profile = addon:GetProfile()
                            if not profile or not profile.burstInjection then return end
                            local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
                            local specKey = engine and engine.GetBurstSpecKey and engine.GetBurstSpecKey()
                            if not specKey then return end
                            if profile.burstInjection.triggerSpells then
                                profile.burstInjection.triggerSpells[specKey] = nil
                            end
                            if engine and engine.InvalidateBurstCache then engine.InvalidateBurstCache() end
                            BurstInjection.UpdateBurstInjectionOptions(addon)
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                    -- Dynamic trigger spell entries added by UpdateBurstInjectionOptions
                },
            },
            -- INJECTION SPELL LIST (50+)
            injectionGroup = {
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
                    return "|c" .. colorCode .. (className or "Unknown") .. "|r " .. L["Burst Injection Spells"] .. " (" .. (specName or "?") .. ")"
                end,
                order = 50,
                disabled = function()
                    local profile = addon:GetProfile()
                    return not (profile and profile.burstInjection and profile.burstInjection.enabled)
                end,
                args = {
                    injectionInfo = {
                        type = "description",
                        name = L["Burst Injection Priority desc"],
                        order = 11,
                        fontSize = "small",
                    },
                    restoreInjectionDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults"],
                        desc = L["Restore Burst Injection Defaults desc"],
                        order = 32,
                        width = "normal",
                        func = function()
                            -- Restore only injection spells
                            local profile = addon:GetProfile()
                            if not profile or not profile.burstInjection then return end
                            local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
                            local specKey = engine and engine.GetBurstSpecKey and engine.GetBurstSpecKey()
                            if not specKey then return end
                            if not SpellDB then SpellDB = LibStub("JustAC-SpellDB", true) end
                            local defaults = SpellDB and SpellDB.CLASS_BURST_INJECTION_DEFAULTS and SpellDB.CLASS_BURST_INJECTION_DEFAULTS[specKey]
                            if defaults then
                                profile.burstInjection.injectionSpells[specKey] = {}
                                for i, spellID in ipairs(defaults) do
                                    profile.burstInjection.injectionSpells[specKey][i] = spellID
                                end
                            else
                                profile.burstInjection.injectionSpells[specKey] = nil
                            end
                            if engine and engine.InvalidateBurstCache then engine.InvalidateBurstCache() end
                            BurstInjection.UpdateBurstInjectionOptions(addon)
                        end,
                    },
                    -- Dynamic injection spell entries added by UpdateBurstInjectionOptions
                },
            },
        },
    }
end

function BurstInjection.UpdateBurstInjectionOptions(addon)
    -- Ensure burst injection defaults are populated before reading data
    local engine = BurstEngine or LibStub("JustAC-BurstInjectionEngine", true)
    if engine and engine.InitializeBurstInjection then
        engine.InitializeBurstInjection(addon)
    end

    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local offTab = optionsTable.args.offensive
    if not offTab then return end
    local biTab = offTab.args.burstInjection
    if not biTab then return end

    -- Update trigger spell list
    local triggerGroup = biTab.args.triggerGroup
    if triggerGroup then
        local triggerArgs = triggerGroup.args
        local triggerStatic = {
            triggerInfo = true, detectedTriggers = true, clearTriggerOverrides = true,
        }
        local keysToClear = {}
        for key, _ in pairs(triggerArgs) do
            if not triggerStatic[key] then
                keysToClear[#keysToClear + 1] = key
            end
        end
        for _, key in ipairs(keysToClear) do
            triggerArgs[key] = nil
        end

        local specKey = engine and engine.GetBurstSpecKey and engine.GetBurstSpecKey()
        if specKey then
            local profile = addon:GetProfile()
            if profile and profile.burstInjection then
                if not profile.burstInjection.triggerSpells then
                    profile.burstInjection.triggerSpells = {}
                end
                if not profile.burstInjection.triggerSpells[specKey] then
                    profile.burstInjection.triggerSpells[specKey] = {}
                end
                local triggerList = profile.burstInjection.triggerSpells[specKey]

                if #triggerList == 0 then
                    triggerArgs.emptyNote = {
                        type = "description",
                        name = L["No Burst Trigger Overrides"],
                        order = 12,
                        fontSize = "medium",
                    }
                end

                if not SpellSearch then
                    SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
                end
                if SpellSearch then
                    local triggerUpdate = function()
                        if engine and engine.InvalidateBurstCache then engine.InvalidateBurstCache() end
                        BurstInjection.UpdateBurstInjectionOptions(addon)
                        addon:ForceUpdate()
                    end
                    SpellSearch.CreateSpellListEntries(addon, triggerArgs, triggerList, "bursttrigger", 12, triggerUpdate)
                    SpellSearch.CreateAddSpellButton(addon, triggerArgs, triggerList, "bursttrigger", 30, L["Burst Trigger Override"], triggerUpdate, true)
                end
            end
        end
    end

    -- Update injection spell list
    local injectionGroup = biTab.args.injectionGroup
    if injectionGroup then
        local injectionArgs = injectionGroup.args
        local injectionStatic = {
            injectionInfo = true, restoreInjectionDefaults = true,
        }
        local keysToClear = {}
        for key, _ in pairs(injectionArgs) do
            if not injectionStatic[key] then
                keysToClear[#keysToClear + 1] = key
            end
        end
        for _, key in ipairs(keysToClear) do
            injectionArgs[key] = nil
        end

        local specKey = engine and engine.GetBurstSpecKey and engine.GetBurstSpecKey()
        if specKey then
            local profile = addon:GetProfile()
            if profile and profile.burstInjection then
                if not profile.burstInjection.injectionSpells then
                    profile.burstInjection.injectionSpells = {}
                end
                if not profile.burstInjection.injectionSpells[specKey] then
                    profile.burstInjection.injectionSpells[specKey] = {}
                end
                local injectionList = profile.burstInjection.injectionSpells[specKey]

                if #injectionList == 0 then
                    injectionArgs.emptyNote = {
                        type = "description",
                        name = L["No Burst Injection Spells"],
                        order = 12,
                        fontSize = "medium",
                    }
                end

                if not SpellSearch then
                    SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
                end
                if SpellSearch then
                    local injectionUpdate = function()
                        if engine and engine.InvalidateBurstCache then engine.InvalidateBurstCache() end
                        BurstInjection.UpdateBurstInjectionOptions(addon)
                        addon:ForceUpdate()
                    end
                    SpellSearch.CreateSpellListEntries(addon, injectionArgs, injectionList, "burstinject", 12, injectionUpdate)
                    SpellSearch.CreateAddSpellButton(addon, injectionArgs, injectionList, "burstinject", 30, L["Burst Injection Spells"], injectionUpdate, true)
                end
            end
        end
    end

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
