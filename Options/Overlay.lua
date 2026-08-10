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
    -- One flat panel (a sub-tab of the Display tab): the former sub-tabs are
    -- inline sections, so their controls keep local orders and arg keys.
    local tab = {
        type = "group",
        name = L["Nameplate Overlay"],
        order = 2,
        args = {
            -- ── SECTION 1: LAYOUT / VISIBILITY ──────────────────────────────
            layout = {
                type = "group",
                inline = true,
                name = "",
                order = 1,
                args = {
                    -- Deliberately NOT gated on overlayDisabled: this is the way back on.
                    enableOverlay = {
                        type = "toggle",
                        name = L["Enable Overlay Queue"],
                        desc = L["Enable Overlay Queue desc"],
                        order = 0.1,
                        width = "full",
                        get = function() return W.SurfaceEnabled(addon, "overlay") end,
                        set = function(_, v) W.SetSurfaceEnabled(addon, "overlay", v) end,
                    },
                    -- VISIBILITY (1-9)
                    visibilityHeader = {
                        type = "header",
                        name = L["Visibility"],
                        order = 1,
                    },
                    -- No "Require Hostile Target" here: the overlay only renders on an
                    -- attackable target's nameplate, so that value is structurally
                    -- identical to "Always" (a legacy saved value reads as Always).
                    queueVisibility = W.select(addon, "nameplateOverlay.queueVisibility", {
                        name = L["Queue Visibility"], desc = L["Nameplate Queue Visibility desc"],
                        order = 2, width = "double", default = "always",
                        values = {
                            always     = L["Always"],
                            combatOnly = L["In Combat Only"],
                        },
                        sorting = { "always", "combatOnly" },
                        get = function()
                            local v = addon.db.profile.nameplateOverlay.queueVisibility or "always"
                            if v == "requireHostile" then v = "always" end
                            return v
                        end,
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
            -- ── SECTION 2: DPS ICONS ────────────────────────────────────────
            offensiveDisplay = {
                type = "group",
                inline = true,
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
                        name = L["Highlight Mode"], desc = L["Highlight Mode Shared desc"],
                        order = 12, width = "normal", default = "shared",
                        values = W.GLOW_VALUES_SHARED,
                        sorting = W.GLOW_SORTING_SHARED,
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
            -- ── SECTION 3: DEFENSIVE ICONS ──────────────────────────────────
            defensiveDisplay = {
                type = "group",
                inline = true,
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
                    defensiveGlowMode = W.select(addon, "nameplateOverlay.defensiveGlowMode", {
                        name = L["Highlight Mode"], desc = L["Highlight Mode Shared desc"],
                        order = 4, width = "normal", default = "shared",
                        values = W.GLOW_VALUES_SHARED,
                        sorting = W.GLOW_SORTING_SHARED,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = defDisabled,
                    }),
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
                        -- Only built inside the health-bar cluster, so it needs that enabled.
                        disabled = function()
                            return defDisabled(addon) or not addon.db.profile.nameplateOverlay.showHealthBar
                        end,
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
    -- One reset for the whole surface panel (the former per-sub-tab resets merged).
    tab.args.resetHeader, tab.args.resetDefaults =
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
            npo.maxIcons              = D.maxIcons
            npo.firstIconScale        = D.firstIconScale
            npo.glowMode              = D.glowMode
            npo.showGlow              = nil  -- clear legacy key
            npo.queueIconDesaturation = D.queueIconDesaturation
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
