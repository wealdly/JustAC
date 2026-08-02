-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Overlay - Nameplate overlay settings tab

local Overlay = LibStub:NewLibrary("JustAC-OptionsOverlay", 3)
if not Overlay then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- Shared disabled helper: overlay not active
local function overlayDisabled(addon)
    return LibStub("JustAC-Options", true).IsOverlayDisabled(addon)
end

-- Defensive sub-options are disabled when the overlay is off OR defensives are hidden.
local function defDisabled(addon)
    return overlayDisabled(addon) or not addon.db.profile.nameplateOverlay.showDefensives
end

-- Most overlay tweaks require a full nameplate cluster rebuild.
local rebuildNPO = W.rebuildNPO

function Overlay.CreateTabArgs(addon)
    local tab = {
        type = "group",
        name = L["Nameplate Overlay"],
        order = 3,
        childGroups = "tab",
        args = {
            -- ═══════════════════════════════════════════════════════════════
            -- SUB-TAB 1: GENERAL
            -- ═══════════════════════════════════════════════════════════════
            layout = {
                type = "group",
                name = L["General"],
                order = 1,
                args = {
                    -- VISIBILITY (1-9)
                    visibilityHeader = {
                        type = "header",
                        name = L["Visibility"],
                        order = 1,
                    },
                    queueVisibility = W.select(addon, "nameplateOverlay.queueVisibility", {
                        name = L["Queue Visibility"], desc = L["Queue Visibility desc"],
                        order = 2, width = "double", default = "always",
                        values = W.QUEUE_VISIBILITY_VALUES,
                        sorting = W.QUEUE_VISIBILITY_SORTING,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = overlayDisabled,
                    }),
                    hideWhenMounted = W.toggle(addon, "nameplateOverlay.hideWhenMounted", {
                        name = L["Hide When Mounted"], desc = L["Hide When Mounted desc"],
                        order = 3, width = "full",
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = overlayDisabled,
                    }),
                    -- ICON LAYOUT (10-19)
                    iconLayoutHeader = {
                        type = "header",
                        name = L["Icon Layout"],
                        order = 10,
                    },
                    reverseAnchor = W.toggle(addon, "nameplateOverlay.reverseAnchor", {
                        name = L["Reverse Anchor"], desc = L["Reverse Anchor desc"],
                        order = 11, width = "normal",
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = overlayDisabled,
                    }),
                    expansion = W.select(addon, "nameplateOverlay.expansion", {
                        name = L["Expansion Direction"], desc = L["Expansion Direction desc"],
                        order = 12, width = "normal", default = "down",
                        values = {
                            out  = L["Horizontal (Out)"],
                            up   = L["Vertical - Up"],
                            down = L["Vertical - Down"],
                        },
                        sorting = { "out", "up", "down" },
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        notify = true,
                        disabled = overlayDisabled,
                    }),
                    iconSize = W.range(addon, "nameplateOverlay.iconSize", {
                        name = L["Icon Size"], desc = L["Icon Size desc"],
                        order = 13, width = "normal", min = 16, max = 48, step = 2, default = 32,
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = overlayDisabled,
                    }),
                    iconSpacing = W.range(addon, "nameplateOverlay.iconSpacing", {
                        name = L["Spacing"], desc = L["Spacing desc"],
                        order = 14, width = "normal", min = 0, max = 10, step = 1, default = 2,
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = overlayDisabled,
                    }),
                    opacity = W.range(addon, "nameplateOverlay.opacity", {
                        name = L["Frame Opacity"], desc = L["Frame Opacity desc"],
                        order = 15, width = "normal", min = 0.1, max = 1.0, step = 0.05, default = 1.0,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = overlayDisabled,
                    }),

                },
            },
            -- ═══════════════════════════════════════════════════════════════
            -- SUB-TAB 2: OFFENSIVE DISPLAY
            -- ═══════════════════════════════════════════════════════════════
            offensiveDisplay = {
                type = "group",
                name = L["Offensive Display"],
                order = 2,
                args = {
                    maxIcons = W.range(addon, "nameplateOverlay.maxIcons", {
                        name = L["Max Icons"], desc = L["Max Icons desc"],
                        min = 1, max = 7, step = 1, order = 10, width = "normal", default = 3,
                        onSet = function() rebuildNPO(addon) end,
                        disabled = overlayDisabled,
                    }),
                    firstIconScale = W.range(addon, "nameplateOverlay.firstIconScale", {
                        name = L["Primary Spell Scale"], desc = L["Primary Spell Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1, order = 11, width = "normal", default = 1.0,
                        onSet = function() rebuildNPO(addon) end,
                        disabled = overlayDisabled,
                    }),
                    -- Legacy showGlow bool is migrated to glowMode once at load by
                    -- MigrateOverlayGlowMode.
                    glowMode = W.select(addon, "nameplateOverlay.glowMode", {
                        name = L["Highlight Mode"], desc = L["Highlight Mode desc"],
                        order = 12, width = "normal", default = "all",
                        values = W.GLOW_VALUES,
                        sorting = W.GLOW_SORTING,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = overlayDisabled,
                    }),
                    queueDesaturation = W.range(addon, "nameplateOverlay.queueIconDesaturation", {
                        name = L["Queue Icon Fade"], desc = L["Queue Icon Fade desc"],
                        min = 0, max = 1.0, step = 0.05, order = 13, width = "normal", default = 0,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = overlayDisabled,
                    }),
                },
            },
            -- ═══════════════════════════════════════════════════════════════
            -- SUB-TAB 3: DEFENSIVE DISPLAY
            -- ═══════════════════════════════════════════════════════════════
            defensiveDisplay = {
                type = "group",
                name = L["Defensive Display"],
                order = 3,
                args = {
                    showDefensives = {
                        type = "toggle",
                        name = L["Show Defensive Icons"],
                        desc = L["Nameplate Show Defensives desc"],
                        order = 1,
                        width = "full",
                        get = function() return addon.db.profile.nameplateOverlay.showDefensives end,
                        set = function(_, val)
                            local wasEnabled = addon.db.profile.nameplateOverlay.showDefensives
                            addon.db.profile.nameplateOverlay.showDefensives = val
                            rebuildNPO(addon)
                            if val and not wasEnabled then
                                addon:InvalidateCaches({spells = true})
                                addon:OnHealthChanged(nil, "player")
                            end
                            addon:ForceUpdateAll()
                            W.NotifyChange()
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    defensiveDisplayMode = W.select(addon, "nameplateOverlay.defensiveDisplayMode", {
                        name = L["Defensive Display Mode"], desc = L["Defensive Display Mode desc"],
                        order = 2, width = "double", default = "always",
                        values = W.DEFENSIVE_DISPLAY_VALUES,
                        sorting = W.DEFENSIVE_DISPLAY_SORTING,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = defDisabled,
                    }),
                    maxDefensiveIcons = W.range(addon, "nameplateOverlay.maxDefensiveIcons", {
                        name = L["Defensive Max Icons"], desc = L["Defensive Max Icons desc"],
                        min = 1, max = 7, step = 1, order = 3, width = "normal", default = 3,
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = defDisabled,
                    }),
                    defensiveIconScale = W.range(addon, "nameplateOverlay.defensiveIconScale", {
                        name = L["Defensive Icon Scale"], desc = L["Defensive Icon Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1, order = 3.5, width = "normal", default = 1.0,
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = defDisabled,
                    }),
                    defensiveGlowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 4,
                        width = "normal",
                        values = W.GLOW_VALUES,
                        sorting = W.GLOW_SORTING,
                        get = function()
                            local npo = addon.db.profile.nameplateOverlay
                            return npo.defensiveGlowMode or npo.glowMode or "all"
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.defensiveGlowMode = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return defDisabled(addon) end,
                    },
                    showHealthBar = W.toggle(addon, "nameplateOverlay.showHealthBar", {
                        name = L["Show Health Bars"], desc = L["Nameplate Show Health Bars desc"],
                        order = 5, width = "normal",
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = defDisabled,
                    }),
                    showPetHealthBar = W.toggle(addon, "nameplateOverlay.showPetHealthBar", {
                        name = L["Show Pet Health Bar"], desc = L["Show Pet Health Bar desc"],
                        order = 6, width = "normal",
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        disabled = defDisabled,
                        hidden = W.petClassHidden,
                    }),
                    showPowerBar = W.toggle(addon, "nameplateOverlay.showPowerBar", {
                        name = L["Show Resource Bar"], desc = L["Nameplate Show Resource Bar desc"],
                        order = 7, width = "normal", default = false,
                        onSet = function() rebuildNPO(addon); addon:ForceUpdateAll() end,
                        -- Anchors to the health bars, so it needs them enabled too.
                        disabled = function()
                            return defDisabled(addon) or not addon.db.profile.nameplateOverlay.showHealthBar
                        end,
                    }),
                },
            },

        },
    }
    tab.args.layout.args.resetHeader, tab.args.layout.args.resetDefaults =
        W.resetButton(990, L["Reset General desc"], function()
            local npo = addon.db.profile.nameplateOverlay
            -- Values come from the real defaults table, never re-typed here: a second
            -- hand-written copy is what let this list drift out of sync with JustAC.lua.
            local D = addon.db.defaults.profile.nameplateOverlay
            npo.queueVisibility = D.queueVisibility
            npo.hideWhenMounted = D.hideWhenMounted
            npo.reverseAnchor = D.reverseAnchor
            npo.expansion     = D.expansion
            npo.iconSize      = D.iconSize
            npo.iconSpacing   = D.iconSpacing
            npo.opacity       = D.opacity
            rebuildNPO(addon)
            W.NotifyChange()
        end)
    tab.args.offensiveDisplay.args.resetHeader, tab.args.offensiveDisplay.args.resetDefaults =
        W.resetButton(990, L["Reset Offensive Display desc"], function()
            local npo = addon.db.profile.nameplateOverlay
            local D = addon.db.defaults.profile.nameplateOverlay
            npo.maxIcons              = D.maxIcons
            npo.firstIconScale        = D.firstIconScale
            npo.glowMode              = D.glowMode
            npo.showGlow              = nil  -- clear legacy key
            npo.queueIconDesaturation = D.queueIconDesaturation
            addon:ForceUpdate()
            rebuildNPO(addon)
            W.NotifyChange()
        end)
    tab.args.defensiveDisplay.args.resetHeader, tab.args.defensiveDisplay.args.resetDefaults =
        W.resetButton(990, L["Reset Defensive Display desc"], function()
            local npo = addon.db.profile.nameplateOverlay
            local D = addon.db.defaults.profile.nameplateOverlay
            npo.showDefensives       = D.showDefensives
            npo.defensiveDisplayMode  = D.defensiveDisplayMode
            npo.maxDefensiveIcons     = D.maxDefensiveIcons
            npo.defensiveIconScale    = D.defensiveIconScale
            npo.defensiveGlowMode     = D.defensiveGlowMode
            npo.showHealthBar         = D.showHealthBar
            npo.showPetHealthBar      = D.showPetHealthBar
            npo.showPowerBar          = D.showPowerBar
            addon:ForceUpdateAll()
            rebuildNPO(addon)
            W.NotifyChange()
        end)
    return tab
end
