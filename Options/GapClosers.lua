-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/GapClosers - Gap-closer settings tab + spell list management
local GapClosers = LibStub:NewLibrary("JustAC-OptionsGapClosers", 1)
if not GapClosers then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local W = LibStub("JustAC-OptionsWidgets")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local SpellLists = LibStub("JustAC-OptionsSpellLists")
local SpellDB = LibStub("JustAC-SpellDB", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function GapClosers.CreateTabArgs(addon)
    -- Shared gate: control is inert while gap-closers are disabled.
    local function gcDisabled()
        local profile = addon:GetProfile()
        return not (profile and profile.gapClosers and profile.gapClosers.enabled)
    end
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
            farOnly = W.toggle(addon, "gapClosers.farOnly", {
                name = L["Only Suggest For Real Gaps"], desc = L["Only Suggest For Real Gaps desc"],
                order = 1.5, width = "full", default = true,
                onSet = function() addon:ForceUpdate() end,
                disabled = gcDisabled,
            }),
            showGlow = W.toggle(addon, "gapClosers.showGlow", {
                name = L["Show Gap-Closer Glow"], desc = L["Show Gap-Closer Glow desc"],
                order = 2, width = "full",
                onSet = function() addon:ForceUpdate() end,
                -- Both renderers AND this with the surface's primary-glow policy, so it
                -- is inert unless some enabled surface's highlight mode includes primary
                -- glows ("shared" resolves against the central Highlight Mode).
                disabled = function()
                    if gcDisabled() then return true end
                    local p = addon:GetProfile()
                    if not p then return true end
                    local UIR = LibStub("JustAC-UIRenderer", true)
                    local function primaryOn(mode)
                        mode = UIR and UIR.ResolveGlowMode(p, mode) or mode
                        return mode == "all" or mode == "primaryOnly"
                    end
                    local std = W.SurfaceEnabled(addon, "queue") and primaryOn(p.glowMode)
                    local npo = p.nameplateOverlay
                    local ov = W.SurfaceEnabled(addon, "overlay") and primaryOn(npo and npo.glowMode)
                    return not (std or ov)
                end,
            }),
            -- SPELL LIST (10+)
            spellListGroup = {
                type = "group",
                inline = true,
                name = SpellSearch.SpecHeader(L["Gap-Closers"]),
                order = 10,
                disabled = gcDisabled,
                args = SpellLists.Args(addon, "gap", 10),
            },
        },
    }
    tab.args.resetHeader, tab.args.resetDefaults = W.resetButton(990, L["Reset Gap-Closers desc"], function()
        local profile = addon:GetProfile()
        if not profile then return end
        if not profile.gapClosers then
            profile.gapClosers = { enabled = true, classSpells = {} }
        end
        profile.gapClosers.enabled = true
        profile.gapClosers.showGlow = true  -- default: true (glow on by default)
        profile.gapClosers.farOnly = true   -- default: true (skip walking-distance gaps)
        addon:ForceUpdate()
        if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
    end)
    return tab
end
