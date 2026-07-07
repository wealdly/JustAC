-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/StandardQueue - Standard Queue panel settings (sub-tabbed: Layout, Offensive Display, Defensive Display, Appearance)
local StandardQueue = LibStub:NewLibrary("JustAC-OptionsStandardQueue", 4)
if not StandardQueue then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- Shared disabled helper: standard panel not active
local function panelDisabled(addon)
    local Options = LibStub("JustAC-Options", true)
    if Options and Options.IsStandardQueueDisabled then
        return Options.IsStandardQueueDisabled(addon)
    end
    local dm = addon.db.profile.displayMode or "queue"
    return dm == "disabled" or dm == "overlay"
end

-- Defensive Display subtab is always accessible when defensives are detached
-- (detached defensives are independent of displayMode).
local function defensiveDisabled(addon)
    local profile = addon.db.profile
    if profile.defensives and profile.defensives.detached then
        return false
    end
    return panelDisabled(addon)
end

-- Layout controls (size/spacing/orientation) lock while anchored to the target
-- frame in combat - protected frames can't be resized mid-fight.
local function layoutDisabled(addon)
    if panelDisabled(addon) then return true end
    return InCombatLockdown() and (addon.db.profile.targetFrameAnchor or "DISABLED") ~= "DISABLED"
end

-- Defensive sub-options gate on the panel being active AND defensives enabled.
local function defEnabledDisabled(addon)
    return defensiveDisabled(addon) or not addon.db.profile.defensives.enabled
end

function StandardQueue.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Standard Queue"],
        order = 2,
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
                    -- Legacy keys (hideQueueOutOfCombat/requireHostileTarget) are migrated
                    -- to queueVisibility once at load by MigrateQueueVisibility.
                    queueVisibility = W.select(addon, "queueVisibility", {
                        name = L["Queue Visibility"], desc = L["Queue Visibility desc"],
                        order = 2, width = "double", default = "always",
                        values = {
                            always         = L["Always"],
                            combatOnly     = L["In Combat Only"],
                            requireHostile = L["Require Hostile Target"],
                        },
                        sorting = { "always", "combatOnly", "requireHostile" },
                        onSet = function() addon:ForceUpdate() end,
                        disabled = panelDisabled,
                    }),
                    hideQueueWhenMounted = W.toggle(addon, "hideQueueWhenMounted", {
                        name = L["Hide When Mounted"], desc = L["Hide When Mounted desc"],
                        order = 3, width = "full",
                        onSet = function() addon:ForceUpdate() end,
                        disabled = panelDisabled,
                    }),
                    -- ICON LAYOUT (10-19)
                    iconLayoutHeader = {
                        type = "header",
                        name = L["Icon Layout"],
                        order = 10,
                    },
                    iconSize = W.range(addon, "iconSize", {
                        name = L["Icon Size"], desc = L["Icon Size desc"],
                        min = 20, max = 64, step = 2, order = 11, width = "normal", default = 42,
                        onSet = function() addon:UpdateFrameSize() end,
                        disabled = layoutDisabled,
                    }),
                    iconSpacing = W.range(addon, "iconSpacing", {
                        name = L["Spacing"], desc = L["Spacing desc"],
                        min = 0, max = 10, step = 1, order = 12, width = "normal", default = 1,
                        onSet = function() addon:UpdateFrameSize() end,
                        disabled = layoutDisabled,
                    }),
                    queueOrientation = {
                        type = "select",
                        name = L["Queue Orientation"],
                        desc = function()
                            local detached = addon.db.profile.defensives and addon.db.profile.defensives.detached
                            return detached and L["Queue Orientation detached desc"] or L["Queue Orientation desc"]
                        end,
                        order = 13,
                        width = "normal",
                        values = function()
                            local detached = addon.db.profile.defensives and addon.db.profile.defensives.detached
                            if detached then
                                return {
                                    LEFT  = L["Left"],
                                    RIGHT = L["Right"],
                                    UP    = L["Up"],
                                    DOWN  = L["Down"],
                                }
                            end
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
                            local detached = addon.db.profile.defensives and addon.db.profile.defensives.detached
                            if detached then
                                return { "LEFT", "RIGHT", "UP", "DOWN" }
                            end
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
                            local detached = addon.db.profile.defensives and addon.db.profile.defensives.detached
                            if detached then
                                return addon.db.profile.queueOrientation or "LEFT"
                            end
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
                            local detached = addon.db.profile.defensives and addon.db.profile.defensives.detached
                            if detached then
                                addon.db.profile.queueOrientation = val
                            else
                                local orientation, side = val:match("^(%u+)_(%u+)$")
                                if not orientation then return end
                                addon.db.profile.queueOrientation = orientation
                                if orientation == "LEFT" or orientation == "RIGHT" then
                                    addon.db.profile.defensives.position = (side == "ABOVE") and "SIDE1" or "SIDE2"
                                else
                                    addon.db.profile.defensives.position = (side == "RIGHT") and "SIDE1" or "SIDE2"
                                end
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
                        order = 14,
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
                                local detached = addon.db.profile.defensives and addon.db.profile.defensives.detached
                                local o = addon.db.profile.queueOrientation or "LEFT"
                                local isH = (o == "LEFT" or o == "RIGHT")
                                if val == "LEFT" then
                                    if isH then addon.db.profile.queueOrientation = "UP" end
                                    if not detached then addon.db.profile.defensives.position = "SIDE2" end
                                elseif val == "RIGHT" then
                                    if isH then addon.db.profile.queueOrientation = "UP" end
                                    if not detached then addon.db.profile.defensives.position = "SIDE1" end
                                elseif val == "TOP" then
                                    if not isH then addon.db.profile.queueOrientation = "LEFT" end
                                    if not detached then addon.db.profile.defensives.position = "SIDE1" end
                                elseif val == "BOTTOM" then
                                    if not isH then addon.db.profile.queueOrientation = "LEFT" end
                                    if not detached then addon.db.profile.defensives.position = "SIDE2" end
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
                    frameOpacity = W.range(addon, "frameOpacity", {
                        name = L["Frame Opacity"], desc = L["Frame Opacity desc"],
                        min = 0.1, max = 1.0, step = 0.05, order = 21, width = "normal", default = 1.0,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = panelDisabled,
                    }),
                    -- Legacy tooltip keys (showTooltips/tooltipsInCombat) are migrated to
                    -- tooltipMode once at load by MigrateLegacySettings.
                    tooltipMode = W.select(addon, "tooltipMode", {
                        name = L["Tooltips"], desc = L["Tooltips desc"],
                        order = 22, width = "normal", default = "always",
                        values = {
                            never       = L["Never"],
                            outOfCombat = L["Out of Combat Only"],
                            always      = L["Always"],
                        },
                        sorting = {"never", "outOfCombat", "always"},
                        disabled = panelDisabled,
                    }),
                    -- Legacy panelLocked bool is migrated to panelInteraction once at
                    -- load by MigrateLegacySettings.
                    panelInteraction = W.select(addon, "panelInteraction", {
                        name = L["Panel Interaction"], desc = L["Panel Interaction desc"],
                        order = 23, width = "normal", default = "unlocked",
                        values = {
                            unlocked     = L["Unlocked"],
                            locked       = L["Locked"],
                            clickthrough = L["Click Through"],
                        },
                        sorting = { "unlocked", "locked", "clickthrough" },
                        disabled = panelDisabled,
                    }),
                    clickToCastOOC = W.toggle(addon, "clickToCastOOC", {
                        name = L["Click to Cast"], desc = L["Click to Cast desc"],
                        order = 24, width = "full", default = true,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = panelDisabled,
                    }),
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
                            local p = addon.db.profile
                            p.queueVisibility      = "always"
                            p.hideQueueWhenMounted  = false
                            -- Clear legacy visibility keys
                            p.hideQueueOutOfCombat  = nil
                            p.requireHostileTarget  = nil
                            p.iconSize            = 42
                            p.iconSpacing         = 1
                            p.queueOrientation    = "LEFT"
                            p.targetFrameAnchor   = "DISABLED"
                            p.defensives.position = "SIDE1"
                            p.frameOpacity        = 1.0
                            p.tooltipMode         = "always"
                            p.panelInteraction    = "unlocked"
                            p.clickToCastOOC      = true
                            -- Clear legacy migration keys
                            p.panelLocked      = nil
                            p.showTooltips     = nil
                            p.tooltipsInCombat = nil
                            addon:UpdateFrameSize()
                            addon:ForceUpdate()
                            W.NotifyChange()
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
                    maxIcons = W.range(addon, "maxIcons", {
                        name = L["Max Icons"], desc = L["Max Icons desc"],
                        min = 1, max = 7, step = 1, order = 1, width = "normal", default = 4,
                        onSet = function() addon:UpdateFrameSize() end,
                        disabled = panelDisabled,
                    }),
                    firstIconScale = W.range(addon, "firstIconScale", {
                        name = L["Primary Spell Scale"], desc = L["Primary Spell Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1, order = 2, width = "normal", default = 1.0,
                        onSet = function() addon:UpdateFrameSize() end,
                        disabled = panelDisabled,
                    }),
                    glowMode = W.select(addon, "glowMode", {
                        name = L["Highlight Mode"], desc = L["Highlight Mode desc"],
                        order = 3, width = "normal", default = "all",
                        values = {
                            all = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly = L["Proc Only"],
                            none = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        onSet = function() addon:ForceUpdate() end,
                        disabled = panelDisabled,
                    }),
                    queueDesaturation = W.range(addon, "queueIconDesaturation", {
                        name = L["Queue Icon Fade"], desc = L["Queue Icon Fade desc"],
                        min = 0, max = 1.0, step = 0.05, order = 4, width = "normal", default = 0,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = panelDisabled,
                    }),
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
                            addon:UpdateFrameSize()
                            addon:ForceUpdate()
                            W.NotifyChange()
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
                            local wasEnabled = addon.db.profile.defensives.enabled
                            addon.db.profile.defensives.enabled = val
                            if val and not wasEnabled then
                                addon:InvalidateCaches({spells = true})
                                addon:OnHealthChanged(nil, "player")
                            end
                            addon:UpdateFrameSize()
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return defensiveDisabled(addon) end,
                    },
                    -- Legacy keys (showOnlyInCombat/alwaysShowDefensive) are migrated to
                    -- defensives.displayMode once at load by MigrateDefensiveDisplayMode.
                    displayMode = W.select(addon, "defensives.displayMode", {
                        name = L["Defensive Display Mode"], desc = L["Defensive Display Mode desc"],
                        order = 2, width = "double", default = "always",
                        values = {
                            healthBased = L["When Health Low"],
                            combatOnly = L["In Combat Only"],
                            always = L["Always"],
                        },
                        sorting = {"healthBased", "combatOnly", "always"},
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = defEnabledDisabled,
                    }),
                    maxIcons = W.range(addon, "defensives.maxIcons", {
                        name = L["Defensive Max Icons"], desc = L["Defensive Max Icons desc"],
                        min = 1, max = 7, step = 1, order = 3, width = "normal", default = 4,
                        onSet = function() addon:UpdateFrameSize(); addon:ForceUpdateAll() end,
                        disabled = defEnabledDisabled,
                    }),
                    iconScale = W.range(addon, "defensives.iconScale", {
                        name = L["Defensive Icon Scale"], desc = L["Defensive Icon Scale desc"],
                        min = 0.5, max = 2.0, step = 0.1, order = 4, width = "normal", default = 1.0,
                        onSet = function() addon:UpdateFrameSize(); addon:ForceUpdateAll() end,
                        disabled = defEnabledDisabled,
                    }),
                    glowMode = W.select(addon, "defensives.glowMode", {
                        name = L["Highlight Mode"], desc = L["Highlight Mode desc"],
                        order = 5, width = "normal", default = "all",
                        values = {
                            all         = L["All Glows"],
                            primaryOnly = L["Primary Only"],
                            procOnly    = L["Proc Only"],
                            none        = L["No Glows"],
                        },
                        sorting = {"all", "primaryOnly", "procOnly", "none"},
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = defEnabledDisabled,
                    }),
                    hideEmergencyUntilLow = W.toggle(addon, "defensives.hideEmergencyUntilLow", {
                        name = L["Hide Emergency Until Low"], desc = L["Hide Emergency Until Low desc"],
                        order = 6, width = "full", default = false,
                        onSet = function() addon:ForceUpdateAll() end,
                        -- Meaningless in "When Health Low" mode (everything is already gated).
                        disabled = function()
                            return defEnabledDisabled(addon)
                                or (addon.db.profile.defensives.displayMode or "always") == "healthBased"
                        end,
                    }),
                    -- HEALTH BARS (10-19)
                    healthBarHeader = {
                        type = "header",
                        name = L["Show Health Bars"],
                        order = 10,
                    },
                    showHealthBar = W.toggle(addon, "defensives.showHealthBar", {
                        name = L["Show Health Bars"], desc = L["Show Health Bars desc"],
                        order = 11, width = "normal",
                        onSet = function() addon:UpdateFrameSize(); addon:ForceUpdateAll() end,
                        disabled = defensiveDisabled,
                    }),
                    showPetHealthBar = W.toggle(addon, "defensives.showPetHealthBar", {
                        name = L["Show Pet Health Bar"], desc = L["Show Pet Health Bar desc"],
                        order = 12, width = "normal",
                        onSet = function() addon:UpdateFrameSize(); addon:ForceUpdateAll() end,
                        disabled = defensiveDisabled,
                        hidden = function()
                            local _, pc = UnitClass("player")
                            local SDB = LibStub("JustAC-SpellDB", true)
                            return not (SDB and SDB.ClassHasPetDefaults(pc))
                        end,
                    }),
                    showTargetHealthBar = W.toggle(addon, "defensives.showTargetHealthBar", {
                        name = L["Show Target Health Bar"], desc = L["Show Target Health Bar desc"],
                        order = 13, width = "normal",
                        onSet = function() addon:UpdateFrameSize(); addon:ForceUpdateAll() end,
                        disabled = defensiveDisabled,
                    }),
                    showPowerBar = W.toggle(addon, "defensives.showPowerBar", {
                        name = "Show Resource Bar",
                        desc = "Show a compact bar for your primary resource (mana, energy, combo points, etc.), stacked above your health bar. Colored by resource type.",
                        order = 14, width = "normal", default = false,
                        onSet = function() addon:UpdateFrameSize(); addon:ForceUpdateAll() end,
                        disabled = defensiveDisabled,
                    }),
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
                            def.hideEmergencyUntilLow = false
                            def.showHealthBar    = true
                            def.showPetHealthBar = true
                            def.showTargetHealthBar = true
                            def.showPowerBar     = false
                            -- Clear legacy migration keys
                            def.showOnlyInCombat    = nil
                            def.alwaysShowDefensive = nil
                            addon:UpdateFrameSize()
                            addon:ForceUpdateAll()
                            W.NotifyChange()
                        end,
                    },
                },
            },

        },
    }
end
