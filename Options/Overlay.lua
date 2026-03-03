-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Overlay - Nameplate overlay settings tab

local MAJOR, MINOR = "JustAC-OptionsOverlay", 2
local Overlay = LibStub:NewLibrary(MAJOR, MINOR)
if not Overlay then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local wipe = wipe

-- Shared disabled helper: overlay not active
local function overlayDisabled(addon)
    local dm = addon.db.profile.displayMode or "queue"
    return dm ~= "overlay" and dm ~= "both"
end

function Overlay.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Nameplate Overlay"],
        order = 3,
        childGroups = "tab",
        args = {
            -- ═══════════════════════════════════════════════════════════════
            -- SUB-TAB 1: LAYOUT
            -- ═══════════════════════════════════════════════════════════════
            layout = {
                type = "group",
                name = L["Icon Layout"],
                order = 1,
                args = {
                    reverseAnchor = {
                        type = "toggle",
                        name = L["Reverse Anchor"],
                        desc = L["Reverse Anchor desc"],
                        order = 1,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.reverseAnchor end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.reverseAnchor = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    expansion = {
                        type = "select",
                        name = L["Expansion Direction"],
                        desc = L["Expansion Direction desc"],
                        order = 2,
                        width = "normal",
                        values = {
                            out  = L["Horizontal (Out)"],
                            up   = L["Vertical - Up"],
                            down = L["Vertical - Down"],
                        },
                        sorting = { "out", "up", "down" },
                        get = function() return addon.db.profile.nameplateOverlay.expansion or "out" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.expansion = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    iconSize = {
                        type = "range",
                        name = L["Nameplate Icon Size"],
                        desc = L["Icon Size desc"],
                        order = 3,
                        width = "normal",
                        min = 16, max = 48, step = 2,
                        get = function() return addon.db.profile.nameplateOverlay.iconSize or 26 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.iconSize = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    iconSpacing = {
                        type = "range",
                        name = L["Spacing"],
                        desc = L["Spacing desc"],
                        order = 4,
                        width = "normal",
                        min = 0, max = 10, step = 1,
                        get = function() return addon.db.profile.nameplateOverlay.iconSpacing or 2 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.iconSpacing = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    opacity = {
                        type = "range",
                        name = L["Frame Opacity"],
                        desc = L["Frame Opacity desc"],
                        order = 5,
                        width = "normal",
                        min = 0.1, max = 1.0, step = 0.05,
                        get = function() return addon.db.profile.nameplateOverlay.opacity or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.opacity = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    -- RESET
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Layout desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local npo = addon.db.profile.nameplateOverlay
                            npo.reverseAnchor = false
                            npo.expansion     = "out"
                            npo.iconSize      = 32
                            npo.iconSpacing   = 2
                            npo.opacity       = 1.0
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
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
                    maxIcons = {
                        type = "select",
                        name = L["Offensive Slots"],
                        desc = L["Max Icons desc"],
                        order = 1,
                        width = "normal",
                        values = { [1] = "1", [2] = "2", [3] = "3", [4] = "4", [5] = "5" },
                        sorting = { 1, 2, 3, 4, 5 },
                        get = function() return addon.db.profile.nameplateOverlay.maxIcons or 1 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.maxIcons = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    glowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 2,
                        width = "normal",
                        values = {
                            all         = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly    = L["Proc Only"],
                            none        = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function()
                            local npo = addon.db.profile.nameplateOverlay
                            -- migrate old showGlow boolean to glowMode string
                            if npo.glowMode then return npo.glowMode end
                            return npo.showGlow ~= false and "all" or "none"
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.glowMode = val
                            addon.db.profile.nameplateOverlay.showGlow = nil  -- clear legacy key
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    -- RESET
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Offensive Display desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local npo = addon.db.profile.nameplateOverlay
                            npo.maxIcons = 3
                            npo.glowMode = "all"
                            npo.showGlow = nil  -- clear legacy key
                            addon:ForceUpdateAll()
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
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
                        name = L["Nameplate Show Defensives"],
                        desc = L["Nameplate Show Defensives desc"],
                        order = 1,
                        width = "full",
                        get = function() return addon.db.profile.nameplateOverlay.showDefensives end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showDefensives = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    defensiveDisplayMode = {
                        type = "select",
                        name = L["Nameplate Defensive Display Mode"],
                        desc = L["Nameplate Defensive Display Mode desc"],
                        order = 2,
                        width = "normal",
                        values = {
                            healthBased = L["When Health Low"],
                            combatOnly  = L["In Combat Only"],
                            always      = L["Always"],
                        },
                        sorting = { "healthBased", "combatOnly", "always" },
                        get = function() return addon.db.profile.nameplateOverlay.defensiveDisplayMode or "combatOnly" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.defensiveDisplayMode = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            return overlayDisabled(addon)
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                    },
                    maxDefensiveIcons = {
                        type = "select",
                        name = L["Nameplate Defensive Count"],
                        desc = L["Defensive Max Icons desc"],
                        order = 3,
                        width = "normal",
                        values = { [1] = "1", [2] = "2", [3] = "3", [4] = "4", [5] = "5" },
                        sorting = { 1, 2, 3, 4, 5 },
                        get = function() return addon.db.profile.nameplateOverlay.maxDefensiveIcons or 1 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.maxDefensiveIcons = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            return overlayDisabled(addon)
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                    },
                    defensiveGlowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 4,
                        width = "normal",
                        values = {
                            all         = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly    = L["Proc Only"],
                            none        = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function()
                            local npo = addon.db.profile.nameplateOverlay
                            return npo.defensiveGlowMode or npo.glowMode or "all"
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.defensiveGlowMode = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            return overlayDisabled(addon)
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                    },
                    showHealthBar = {
                        type = "toggle",
                        name = L["Nameplate Show Health Bars"],
                        desc = L["Nameplate Show Health Bars desc"],
                        order = 5,
                        width = "full",
                        get = function() return addon.db.profile.nameplateOverlay.showHealthBar end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showHealthBar = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            return overlayDisabled(addon)
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                    },
                    -- RESET
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 990,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = L["Reset to Defaults"],
                        desc = L["Reset Defensive Display desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local npo = addon.db.profile.nameplateOverlay
                            npo.showDefensives       = true
                            npo.defensiveDisplayMode  = "always"
                            npo.maxDefensiveIcons     = 3
                            npo.defensiveGlowMode     = "all"
                            npo.showHealthBar         = true
                            addon:ForceUpdateAll()
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                },
            },
        },
    }
end
