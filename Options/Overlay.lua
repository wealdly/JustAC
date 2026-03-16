-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Overlay - Nameplate overlay settings tab

local Overlay = LibStub:NewLibrary("JustAC-OptionsOverlay", 3)
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
                    queueVisibility = {
                        type = "select",
                        name = L["Queue Visibility"],
                        desc = L["Queue Visibility desc"],
                        order = 2,
                        width = "double",
                        values = {
                            always         = L["Always"],
                            combatOnly     = L["In Combat Only"],
                            requireHostile = L["Require Hostile Target"],
                        },
                        sorting = { "always", "combatOnly", "requireHostile" },
                        get = function() return addon.db.profile.nameplateOverlay.queueVisibility or "always" end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.queueVisibility = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    hideWhenMounted = {
                        type = "toggle",
                        name = L["Hide When Mounted"],
                        desc = L["Hide When Mounted desc"],
                        order = 3,
                        width = "full",
                        disabled = function() return overlayDisabled(addon) end,
                        get = function() return addon.db.profile.nameplateOverlay.hideWhenMounted end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.hideWhenMounted = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    -- ICON LAYOUT (10-19)
                    iconLayoutHeader = {
                        type = "header",
                        name = L["Icon Layout"],
                        order = 10,
                    },
                    reverseAnchor = {
                        type = "toggle",
                        name = L["Reverse Anchor"],
                        desc = L["Reverse Anchor desc"],
                        order = 11,
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
                        order = 12,
                        width = "normal",
                        values = {
                            out  = L["Horizontal (Out)"],
                            up   = L["Vertical - Up"],
                            down = L["Vertical - Down"],
                        },
                        sorting = { "out", "up", "down" },
                        get = function() return addon.db.profile.nameplateOverlay.expansion or "down" end,
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
                        name = L["Icon Size"],
                        desc = L["Icon Size desc"],
                        order = 13,
                        width = "normal",
                        min = 16, max = 48, step = 2,
                        get = function() return addon.db.profile.nameplateOverlay.iconSize or 32 end,
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
                        order = 14,
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
                        order = 15,
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
                        desc = L["Reset General desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local npo = addon.db.profile.nameplateOverlay
                            npo.queueVisibility = "always"
                            npo.hideWhenMounted = false
                            npo.reverseAnchor = false
                            npo.expansion     = "down"
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
                        type = "range",
                        name = L["Max Icons"],
                        desc = L["Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 10,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.maxIcons or 3 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.maxIcons = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    firstIconScale = {
                        type = "range",
                        name = L["Primary Spell Scale"],
                        desc = L["Primary Spell Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 11,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.firstIconScale or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.firstIconScale = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function() return overlayDisabled(addon) end,
                    },
                    glowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 12,
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
                    queueDesaturation = {
                        type = "range",
                        name = L["Queue Icon Fade"],
                        desc = L["Queue Icon Fade desc"],
                        min = 0, max = 1.0, step = 0.05,
                        order = 13,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.queueIconDesaturation or 0 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.queueIconDesaturation = val
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
                            npo.maxIcons              = 3
                            npo.firstIconScale        = 1.0
                            npo.glowMode              = "all"
                            npo.showGlow              = nil  -- clear legacy key
                            npo.queueIconDesaturation = 0
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
                        name = L["Show Defensive Icons"],
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
                        name = L["Defensive Display Mode"],
                        desc = L["Defensive Display Mode desc"],
                        order = 2,
                        width = "double",
                        values = {
                            healthBased = L["When Health Low"],
                            combatOnly  = L["In Combat Only"],
                            always      = L["Always"],
                        },
                        sorting = { "healthBased", "combatOnly", "always" },
                        get = function() return addon.db.profile.nameplateOverlay.defensiveDisplayMode or "always" end,
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
                        type = "range",
                        name = L["Defensive Max Icons"],
                        desc = L["Defensive Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 3,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.maxDefensiveIcons or 3 end,
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
                    defensiveIconScale = {
                        type = "range",
                        name = L["Defensive Icon Scale"],
                        desc = L["Defensive Icon Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 3.5,
                        width = "normal",
                        get = function() return addon.db.profile.nameplateOverlay.defensiveIconScale or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.defensiveIconScale = val
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
                        name = L["Show Health Bars"],
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
                    showPetHealthBar = {
                        type = "toggle",
                        name = L["Show Pet Health Bar"],
                        desc = L["Show Pet Health Bar desc"],
                        order = 6,
                        width = "full",
                        get = function() return addon.db.profile.nameplateOverlay.showPetHealthBar end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.showPetHealthBar = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                        disabled = function()
                            return overlayDisabled(addon)
                                or not addon.db.profile.nameplateOverlay.showDefensives
                        end,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            if not SDB or not pc then return true end
                            return not ((SDB.CLASS_PET_REZ_DEFAULTS and SDB.CLASS_PET_REZ_DEFAULTS[pc])
                                or (SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc]))
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
                            npo.defensiveIconScale    = 1.0
                            npo.defensiveGlowMode     = "all"
                            npo.showHealthBar         = true
                            npo.showPetHealthBar      = true
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
