-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/StandardQueue - Standard Queue panel settings (sub-tabbed: Layout, Offensive Display, Defensive Display, Appearance)
local StandardQueue = LibStub:NewLibrary("JustAC-OptionsStandardQueue", 2)
if not StandardQueue then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Shared disabled helper: standard panel not active
local function panelDisabled(addon)
    local dm = addon.db.profile.displayMode or "queue"
    return dm == "disabled" or dm == "overlay"
end

function StandardQueue.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Standard Queue"],
        order = 2,
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
                    iconSize = {
                        type = "range",
                        name = L["Icon Size"],
                        desc = L["Icon Size desc"],
                        min = 20, max = 64, step = 2,
                        order = 1,
                        width = "normal",
                        get = function() return addon.db.profile.iconSize or 42 end,
                        set = function(_, val)
                            addon.db.profile.iconSize = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            if panelDisabled(addon) then return true end
                            return InCombatLockdown() and (addon.db.profile.targetFrameAnchor or "DISABLED") ~= "DISABLED"
                        end,
                    },
                    iconSpacing = {
                        type = "range",
                        name = L["Spacing"],
                        desc = L["Spacing desc"],
                        min = 0, max = 10, step = 1,
                        order = 2,
                        width = "normal",
                        get = function() return addon.db.profile.iconSpacing or 1 end,
                        set = function(_, val)
                            addon.db.profile.iconSpacing = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            if panelDisabled(addon) then return true end
                            return InCombatLockdown() and (addon.db.profile.targetFrameAnchor or "DISABLED") ~= "DISABLED"
                        end,
                    },
                    queueOrientation = {
                        type = "select",
                        name = L["Queue Orientation"],
                        desc = L["Queue Orientation desc"],
                        order = 3,
                        width = "normal",
                        values = function()
                            local anchor = addon.db.profile.targetFrameAnchor or "DISABLED"
                            if anchor == "LEFT" then
                                return {
                                    UP_LEFT   = L["Up, Sidebar Left"],
                                    DOWN_LEFT = L["Down, Sidebar Left"],
                                }
                            elseif anchor == "RIGHT" then
                                return {
                                    UP_RIGHT   = L["Up, Sidebar Right"],
                                    DOWN_RIGHT = L["Down, Sidebar Right"],
                                }
                            elseif anchor == "TOP" then
                                return {
                                    LEFT_ABOVE  = L["Left, Sidebar Above"],
                                    RIGHT_ABOVE = L["Right, Sidebar Above"],
                                }
                            elseif anchor == "BOTTOM" then
                                return {
                                    LEFT_BELOW  = L["Left, Sidebar Below"],
                                    RIGHT_BELOW = L["Right, Sidebar Below"],
                                }
                            else
                                return {
                                    LEFT_ABOVE   = L["Left, Sidebar Above"],
                                    LEFT_BELOW   = L["Left, Sidebar Below"],
                                    RIGHT_ABOVE  = L["Right, Sidebar Above"],
                                    RIGHT_BELOW  = L["Right, Sidebar Below"],
                                    UP_LEFT      = L["Up, Sidebar Left"],
                                    UP_RIGHT     = L["Up, Sidebar Right"],
                                    DOWN_LEFT    = L["Down, Sidebar Left"],
                                    DOWN_RIGHT   = L["Down, Sidebar Right"],
                                }
                            end
                        end,
                        sorting = function()
                            local anchor = addon.db.profile.targetFrameAnchor or "DISABLED"
                            if anchor == "LEFT" then
                                return { "UP_LEFT", "DOWN_LEFT" }
                            elseif anchor == "RIGHT" then
                                return { "UP_RIGHT", "DOWN_RIGHT" }
                            elseif anchor == "TOP" then
                                return { "LEFT_ABOVE", "RIGHT_ABOVE" }
                            elseif anchor == "BOTTOM" then
                                return { "LEFT_BELOW", "RIGHT_BELOW" }
                            else
                                return { "LEFT_ABOVE", "LEFT_BELOW", "RIGHT_ABOVE", "RIGHT_BELOW", "UP_LEFT", "UP_RIGHT", "DOWN_LEFT", "DOWN_RIGHT" }
                            end
                        end,
                        get = function()
                            local o = addon.db.profile.queueOrientation or "LEFT"
                            local s = addon.db.profile.defensives and addon.db.profile.defensives.position or "SIDE1"
                            if s == "LEADING" then s = "SIDE1" end
                            if o == "LEFT" or o == "RIGHT" then
                                return o .. (s == "SIDE1" and "_ABOVE" or "_BELOW")
                            else
                                return o .. (s == "SIDE1" and "_RIGHT" or "_LEFT")
                            end
                        end,
                        set = function(_, val)
                            local orientation, side = val:match("^(%u+)_(%u+)$")
                            if not orientation then return end
                            addon.db.profile.queueOrientation = orientation
                            if orientation == "LEFT" or orientation == "RIGHT" then
                                addon.db.profile.defensives.position = (side == "ABOVE") and "SIDE1" or "SIDE2"
                            else
                                addon.db.profile.defensives.position = (side == "RIGHT") and "SIDE1" or "SIDE2"
                            end
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            if panelDisabled(addon) then return true end
                            return InCombatLockdown() and (addon.db.profile.targetFrameAnchor or "DISABLED") ~= "DISABLED"
                        end,
                    },
                    targetFrameAnchor = {
                        type = "select",
                        name = L["Target Frame Anchor"],
                        desc = function()
                            if addon.IsStandardTargetFrame and not addon:IsStandardTargetFrame() then
                                return L["Target Frame Replaced"]
                            end
                            return L["Target Frame Anchor desc"]
                        end,
                        order = 4,
                        width = "normal",
                        values = function()
                            local vals = { DISABLED = L["Disabled"], LEFT = L["Left"], RIGHT = L["Right"] }
                            local buffsOnTop = TargetFrame and TargetFrame.buffsOnTop
                            if buffsOnTop == true then
                                vals.BOTTOM = L["Bottom"]
                            elseif buffsOnTop == false then
                                vals.TOP = L["Top"]
                            else
                                vals.TOP = L["Top"]
                                vals.BOTTOM = L["Bottom"]
                            end
                            return vals
                        end,
                        sorting = function()
                            local keys = { "DISABLED" }
                            local buffsOnTop = TargetFrame and TargetFrame.buffsOnTop
                            if buffsOnTop == true then
                                keys[#keys + 1] = "BOTTOM"
                            elseif buffsOnTop == false then
                                keys[#keys + 1] = "TOP"
                            else
                                keys[#keys + 1] = "TOP"
                                keys[#keys + 1] = "BOTTOM"
                            end
                            keys[#keys + 1] = "LEFT"
                            keys[#keys + 1] = "RIGHT"
                            return keys
                        end,
                        get = function() return addon.db.profile.targetFrameAnchor or "DISABLED" end,
                        set = function(_, val)
                            addon.db.profile.targetFrameAnchor = val
                            if val ~= "DISABLED" then
                                local o = addon.db.profile.queueOrientation or "LEFT"
                                local s = addon.db.profile.defensives and addon.db.profile.defensives.position or "SIDE1"
                                if s == "LEADING" then s = "SIDE1" end
                                local isH = (o == "LEFT" or o == "RIGHT")
                                if val == "LEFT" then
                                    if isH then addon.db.profile.queueOrientation = "UP" end
                                    addon.db.profile.defensives.position = "SIDE2"
                                elseif val == "RIGHT" then
                                    if isH then addon.db.profile.queueOrientation = "UP" end
                                    addon.db.profile.defensives.position = "SIDE1"
                                elseif val == "TOP" then
                                    if not isH then addon.db.profile.queueOrientation = "LEFT" end
                                    addon.db.profile.defensives.position = "SIDE1"
                                elseif val == "BOTTOM" then
                                    if not isH then addon.db.profile.queueOrientation = "LEFT" end
                                    addon.db.profile.defensives.position = "SIDE2"
                                end
                            end
                            if InCombatLockdown() then
                                addon.pendingLayoutRebuild = true
                            else
                                addon:UpdateTargetFrameAnchor()
                                addon:UpdateFrameSize()
                            end
                        end,
                        disabled = function()
                            if panelDisabled(addon) then return true end
                            if addon.IsStandardTargetFrame and not addon:IsStandardTargetFrame() then return true end
                            return InCombatLockdown()
                        end,
                    },
                    -- PANEL (20-29)
                    panelHeader = {
                        type = "header",
                        name = L["Appearance"],
                        order = 20,
                    },
                    frameOpacity = {
                        type = "range",
                        name = L["Frame Opacity"],
                        desc = L["Frame Opacity desc"],
                        min = 0.1, max = 1.0, step = 0.05,
                        order = 21,
                        width = "normal",
                        get = function() return addon.db.profile.frameOpacity or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.frameOpacity = val
                            addon:ForceUpdate()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    tooltipMode = {
                        type = "select",
                        name = L["Tooltips"],
                        desc = L["Tooltips desc"],
                        order = 22,
                        width = "normal",
                        values = {
                            never       = L["Never"],
                            outOfCombat = L["Out of Combat Only"],
                            always      = L["Always"],
                        },
                        sorting = {"never", "outOfCombat", "always"},
                        get = function()
                            if addon.db.profile.tooltipMode then
                                return addon.db.profile.tooltipMode
                            end
                            if addon.db.profile.showTooltips == false then
                                return "never"
                            elseif addon.db.profile.tooltipsInCombat then
                                return "always"
                            else
                                return "outOfCombat"
                            end
                        end,
                        set = function(_, val)
                            addon.db.profile.tooltipMode = val
                            addon.db.profile.showTooltips = nil
                            addon.db.profile.tooltipsInCombat = nil
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    panelInteraction = {
                        type = "select",
                        name = L["Panel Interaction"],
                        desc = L["Panel Interaction desc"],
                        order = 23,
                        width = "normal",
                        values = {
                            unlocked     = L["Unlocked"],
                            locked       = L["Locked"],
                            clickthrough = L["Click Through"],
                        },
                        sorting = { "unlocked", "locked", "clickthrough" },
                        get = function()
                            local profile = addon.db.profile
                            return profile.panelInteraction or (profile.panelLocked and "locked" or "unlocked")
                        end,
                        set = function(_, val)
                            addon.db.profile.panelInteraction = val
                        end,
                        disabled = function() return panelDisabled(addon) end,
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
                            local p = addon.db.profile
                            p.iconSize            = 42
                            p.iconSpacing         = 1
                            p.queueOrientation    = "LEFT"
                            p.targetFrameAnchor   = "DISABLED"
                            p.defensives.position = "SIDE1"
                            p.frameOpacity        = 1.0
                            p.tooltipMode         = "always"
                            p.panelInteraction    = "unlocked"
                            -- Clear legacy migration keys
                            p.panelLocked      = nil
                            p.showTooltips     = nil
                            p.tooltipsInCombat = nil
                            addon:UpdateFrameSize()
                            addon:ForceUpdate()
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
                        order = 1,
                        width = "normal",
                        get = function() return addon.db.profile.maxIcons or 4 end,
                        set = function(_, val)
                            addon.db.profile.maxIcons = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    firstIconScale = {
                        type = "range",
                        name = L["Primary Spell Scale"],
                        desc = L["Primary Spell Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 2,
                        width = "normal",
                        get = function() return addon.db.profile.firstIconScale or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.firstIconScale = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    glowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 3,
                        width = "normal",
                        values = {
                            all = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly = L["Proc Only"],
                            none = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function() return addon.db.profile.glowMode or "all" end,
                        set = function(_, val)
                            addon.db.profile.glowMode = val
                            addon:ForceUpdate()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    queueDesaturation = {
                        type = "range",
                        name = L["Queue Icon Fade"],
                        desc = L["Queue Icon Fade desc"],
                        min = 0, max = 1.0, step = 0.05,
                        order = 4,
                        width = "normal",
                        get = function() return addon.db.profile.queueIconDesaturation or 0 end,
                        set = function(_, val)
                            addon.db.profile.queueIconDesaturation = val
                            addon:ForceUpdate()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    -- VISIBILITY (10-19)
                    visibilityHeader = {
                        type = "header",
                        name = L["Visibility"],
                        order = 10,
                    },
                    queueVisibility = {
                        type = "select",
                        name = L["Queue Visibility"],
                        desc = L["Queue Visibility desc"],
                        order = 11,
                        width = "double",
                        values = {
                            always         = L["Always"],
                            combatOnly     = L["In Combat Only"],
                            requireHostile = L["Require Hostile Target"],
                        },
                        sorting = { "always", "combatOnly", "requireHostile" },
                        get = function()
                            local p = addon.db.profile
                            if p.queueVisibility then return p.queueVisibility end
                            -- Migrate legacy keys
                            if p.hideQueueOutOfCombat then return "combatOnly" end
                            if p.requireHostileTarget  then return "requireHostile" end
                            return "always"
                        end,
                        set = function(_, val)
                            local p = addon.db.profile
                            p.queueVisibility      = val
                            -- Clear legacy keys
                            p.hideQueueOutOfCombat = nil
                            p.requireHostileTarget = nil
                            addon:ForceUpdate()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    hideQueueWhenMounted = {
                        type = "toggle",
                        name = L["Hide When Mounted"],
                        desc = L["Hide When Mounted desc"],
                        order = 12,
                        width = "full",
                        disabled = function() return panelDisabled(addon) end,
                        get = function() return addon.db.profile.hideQueueWhenMounted end,
                        set = function(_, val)
                            addon.db.profile.hideQueueWhenMounted = val
                            addon:ForceUpdate()
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
                        desc = L["Reset Offensive Display desc"],
                        order = 991,
                        width = "normal",
                        func = function()
                            local p = addon.db.profile
                            p.maxIcons              = 4
                            p.firstIconScale        = 1.0
                            p.glowMode              = "all"
                            p.queueIconDesaturation = 0
                            p.queueVisibility       = "always"
                            p.hideQueueWhenMounted  = false
                            -- Clear legacy keys
                            p.hideQueueOutOfCombat  = nil
                            p.requireHostileTarget  = nil
                            addon:UpdateFrameSize()
                            addon:ForceUpdate()
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
                    enabled = {
                        type = "toggle",
                        name = L["Show Defensive Icons"],
                        desc = L["Enable Defensive Suggestions desc"],
                        order = 1,
                        width = "full",
                        get = function() return addon.db.profile.defensives.enabled end,
                        set = function(_, val)
                            addon.db.profile.defensives.enabled = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    displayMode = {
                        type = "select",
                        name = L["Defensive Display Mode"],
                        desc = L["Defensive Display Mode desc"],
                        order = 2,
                        width = "double",
                        values = {
                            healthBased = L["When Health Low"],
                            combatOnly = L["In Combat Only"],
                            always = L["Always"],
                        },
                        sorting = {"healthBased", "combatOnly", "always"},
                        get = function()
                            if addon.db.profile.defensives.displayMode then
                                return addon.db.profile.defensives.displayMode
                            end
                            local showOnlyInCombat = addon.db.profile.defensives.showOnlyInCombat
                            local alwaysShow = addon.db.profile.defensives.alwaysShowDefensive
                            if alwaysShow and showOnlyInCombat then
                                return "combatOnly"
                            elseif alwaysShow then
                                return "always"
                            else
                                return "healthBased"
                            end
                        end,
                        set = function(_, val)
                            addon.db.profile.defensives.displayMode = val
                            addon.db.profile.defensives.showOnlyInCombat = nil
                            addon.db.profile.defensives.alwaysShowDefensive = nil
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            return panelDisabled(addon) or not addon.db.profile.defensives.enabled
                        end,
                    },
                    maxIcons = {
                        type = "range",
                        name = L["Defensive Max Icons"],
                        desc = L["Defensive Max Icons desc"],
                        min = 1, max = 7, step = 1,
                        order = 3,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.maxIcons or 4 end,
                        set = function(_, val)
                            addon.db.profile.defensives.maxIcons = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            return panelDisabled(addon) or not addon.db.profile.defensives.enabled
                        end,
                    },
                    iconScale = {
                        type = "range",
                        name = L["Defensive Icon Scale"],
                        desc = L["Defensive Icon Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1,
                        order = 4,
                        width = "normal",
                        get = function() return addon.db.profile.defensives.iconScale or 1.0 end,
                        set = function(_, val)
                            addon.db.profile.defensives.iconScale = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function()
                            return panelDisabled(addon) or not addon.db.profile.defensives.enabled
                        end,
                    },
                    glowMode = {
                        type = "select",
                        name = L["Highlight Mode"],
                        desc = L["Highlight Mode desc"],
                        order = 5,
                        width = "normal",
                        values = {
                            all         = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly    = L["Proc Only"],
                            none        = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        get = function() return addon.db.profile.defensives.glowMode or "all" end,
                        set = function(_, val)
                            addon.db.profile.defensives.glowMode = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            return panelDisabled(addon) or not addon.db.profile.defensives.enabled
                        end,
                    },
                    -- HEALTH BARS (10-19)
                    healthBarHeader = {
                        type = "header",
                        name = L["Show Health Bars"],
                        order = 10,
                    },
                    showHealthBar = {
                        type = "toggle",
                        name = L["Show Health Bars"],
                        desc = L["Show Health Bars desc"],
                        order = 11,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showHealthBar end,
                        set = function(_, val)
                            addon.db.profile.defensives.showHealthBar = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                    },
                    showPetHealthBar = {
                        type = "toggle",
                        name = L["Show Pet Health Bar"],
                        desc = L["Show Pet Health Bar desc"],
                        order = 12,
                        width = "full",
                        get = function() return addon.db.profile.defensives.showPetHealthBar end,
                        set = function(_, val)
                            addon.db.profile.defensives.showPetHealthBar = val
                            addon:UpdateFrameSize()
                        end,
                        disabled = function() return panelDisabled(addon) end,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            if not SpellSearch then SpellSearch = LibStub("JustAC-OptionsSpellSearch", true) end
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
                            local def = addon.db.profile.defensives
                            def.enabled          = true
                            def.displayMode      = "always"
                            def.maxIcons         = 4
                            def.iconScale        = 1.0
                            def.glowMode         = "all"
                            def.showHealthBar    = true
                            def.showPetHealthBar = true
                            -- Clear legacy migration keys
                            def.showOnlyInCombat    = nil
                            def.alwaysShowDefensive = nil
                            addon:UpdateFrameSize()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                },
            },

        },
    }
end
