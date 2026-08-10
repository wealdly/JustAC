-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Display - the one tab for everything visual: the two surface
-- panels (Main Queue / Nameplate Queue) plus the Shared Behavior panel that both
-- follow (glow policy, icon behavior toggles, ability markers, icon labels).
local Display = LibStub:NewLibrary("JustAC-OptionsDisplay", 1)
if not Display then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

local fullyDisabled = W.fullyDisabled

-- ── Shared panel: cross-surface display behavior + icon labels ───────────────
local function BuildSharedPanel(addon)
    local Labels = LibStub("JustAC-OptionsLabels", true)

    local panel = {
        type = "group",
        name = L["Shared Behavior"],
        order = 3,
        args = {
            info = {
                type = "description",
                name = L["General description"],
                order = 1,
                fontSize = "medium",
            },
            -- The shared Highlight Mode: every surface follows this unless its own
            -- panel overrides it ("Use Shared Setting" is the per-surface default).
            glowMode = W.select(addon, "glowMode", {
                name = L["Highlight Mode"], desc = L["Shared Highlight Mode desc"],
                order = 11, width = "double", default = "all",
                values = W.GLOW_VALUES,
                sorting = W.GLOW_SORTING,
                onSet = function() addon:ForceUpdateAll() end,
                disabled = fullyDisabled,
            }),
            showFlash = W.toggle(addon, "showFlash", {
                name = L["Show Key Press Flash"], desc = L["Show Key Press Flash desc"],
                order = 12, width = "normal", default = true, disabled = fullyDisabled,
            }),
            greyOutWhileCasting = W.toggle(addon, "greyOutWhileCasting", {
                name = L["Grey Out While Casting"], desc = L["Grey Out While Casting desc"],
                order = 13, width = "normal", default = true, disabled = fullyDisabled,
            }),
            showUsabilityTint = W.toggle(addon, "showUsabilityTint", {
                name = L["Show Usability Tint"], desc = L["Show Usability Tint desc"],
                order = 15, width = "normal", default = true, disabled = fullyDisabled,
            }),
            showCastingHighlight = W.toggle(addon, "showCastingHighlight", {
                name = L["Show Casting Highlight"], desc = L["Show Casting Highlight desc"],
                order = 17, width = "normal", default = true, disabled = fullyDisabled,
            }),
            -- ABILITY MARKERS - shared: both cues render on the DPS and defensive queues.
            markMoveCastable = {
                type = "toggle",
                name = L["Mark Move-Castable Spells"], desc = L["Mark Move-Castable Spells desc"],
                order = 18, width = "normal",
                -- Raw get/set: no static default, because the default is
                -- per-spec (see UIRenderer.MoveCastDotEnabled).
                get = function()
                    local R = LibStub("JustAC-UIRenderer", true)
                    return (R and R.MoveCastDotEnabled and R.MoveCastDotEnabled(addon.db.profile)) or false
                end,
                set = function(_, val)
                    addon.db.profile.showMoveCastDot = val
                    addon:ForceUpdateAll()
                end,
                disabled = function() return fullyDisabled(addon) end,
            },
            showOffGcdDot = W.toggle(addon, "showOffGcdDot", {
                name = "Mark Off-Global-Cooldown Spells",
                desc = "Show an amber marker in the lower-left corner of abilities that don't "
                    .. "trigger the global cooldown - you can cast them and move straight "
                    .. "on to the next suggestion without waiting.\n\n"
                    .. "Applies to the DPS and defensive queues alike.",
                order = 19, width = "normal", default = false,
                onSet = function() addon:ForceUpdateAll() end,
                disabled = fullyDisabled,
            }),
            -- Icon Labels (shared show/scale/color/anchor + nameplate font scales)
            -- injected below by Labels.AddLabelArgs at orders 30+.
        },
    }

    if Labels and Labels.AddLabelArgs then
        Labels.AddLabelArgs(addon, panel.args, 30)
    end

    panel.args.resetHeader, panel.args.resetDefaults =
        W.resetButton(990, L["Reset Shared desc"], function()
            local p = addon.db.profile
            local D = addon.db.defaults.profile
            p.glowMode             = D.glowMode
            p.showFlash            = D.showFlash
            p.greyOutWhileCasting  = D.greyOutWhileCasting
            p.showUsabilityTint    = D.showUsabilityTint
            p.showCastingHighlight = D.showCastingHighlight
            p.showMoveCastDot      = nil  -- back to the per-spec auto default
            p.showOffGcdDot        = D.showOffGcdDot
            if Labels and Labels.ResetToDefaults then Labels.ResetToDefaults(addon) end
            addon:ForceUpdateAll()
            W.NotifyChange()
        end)
    return panel
end

function Display.CreateTabArgs(addon)
    local StandardQueue = LibStub("JustAC-OptionsStandardQueue", true)
    local Overlay = LibStub("JustAC-OptionsOverlay", true)

    return {
        type = "group",
        name = L["Display"],
        order = 2,
        childGroups = "tab",
        args = {
            main      = StandardQueue and StandardQueue.CreateTabArgs(addon) or nil,
            nameplate = Overlay and Overlay.CreateTabArgs(addon) or nil,
            shared    = BuildSharedPanel(addon),
        },
    }
end
