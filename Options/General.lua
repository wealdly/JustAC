-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/General - General settings tab (display mode, layout, visibility, appearance, system)
local General = LibStub:NewLibrary("JustAC-OptionsGeneral", 1)
if not General then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function General.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["General"],
        order = 1,
        args = {
            info = {
                type = "description",
                name = L["General description"],
                order = 1,
                fontSize = "medium"
            },
            displayMode = {
                type = "select",
                name = L["Display Mode"],
                desc = L["Display Mode desc"],
                order = 2,
                width = "normal",
                values = {
                    disabled = L["Disabled"],
                    queue    = L["Standard Queue"],
                    overlay  = L["Nameplate Overlay"],
                    both     = L["Both"],
                },
                sorting = { "disabled", "queue", "overlay", "both" },
                get = function() return addon.db.profile.displayMode or "queue" end,
                set = function(_, val)
                    addon.db.profile.displayMode = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then
                        NPO.Destroy(addon)
                        if val == "overlay" or val == "both" then
                            NPO.Create(addon)
                        end
                    end
                    addon:ForceUpdate()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
            -- ICON LAYOUT (10-19)
            layoutHeader = {
                type = "header",
                name = L["Icon Layout"],
                order = 10,
            },
            iconSize = {
                type = "range",
                name = L["Icon Size"],
                desc = L["Icon Size desc"],
                min = 20, max = 64, step = 2,
                order = 12,
                width = "normal",
                get = function() return addon.db.profile.iconSize or 42 end,
                set = function(_, val)
                    addon.db.profile.iconSize = val
                    addon:UpdateFrameSize()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" or dm == "overlay" then return true end
                    -- ClearAllPoints on an anchored frame is blocked in combat
                    return InCombatLockdown() and (addon.db.profile.targetFrameAnchor or "DISABLED") ~= "DISABLED"
                end,
            },
            iconSpacing = {
                type = "range",
                name = L["Spacing"],
                desc = L["Spacing desc"],
                min = 0, max = 10, step = 1,
                order = 13,
                width = "normal",
                get = function() return addon.db.profile.iconSpacing or 1 end,
                set = function(_, val)
                    addon.db.profile.iconSpacing = val
                    addon:UpdateFrameSize()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" or dm == "overlay" then return true end
                    return InCombatLockdown() and (addon.db.profile.targetFrameAnchor or "DISABLED") ~= "DISABLED"
                end,
            },
            queueOrientation = {
                type = "select",
                name = L["Queue Orientation"],
                desc = L["Queue Orientation desc"],
                order = 15,
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
                    -- Migrate LEADING
                    if s == "LEADING" then s = "SIDE1" end
                    -- Map SIDE1/SIDE2 to human directions based on orientation axis
                    if o == "LEFT" or o == "RIGHT" then
                        -- Horizontal: SIDE1 = above, SIDE2 = below
                        return o .. (s == "SIDE1" and "_ABOVE" or "_BELOW")
                    else
                        -- Vertical: SIDE1 = right, SIDE2 = left
                        return o .. (s == "SIDE1" and "_RIGHT" or "_LEFT")
                    end
                end,
                set = function(_, val)
                    -- Split compound key: e.g. "LEFT_ABOVE" → orientation "LEFT", side "ABOVE"
                    local orientation, side = val:match("^(%u+)_(%u+)$")
                    if not orientation then return end
                    addon.db.profile.queueOrientation = orientation
                    -- Map human direction back to SIDE1/SIDE2
                    if orientation == "LEFT" or orientation == "RIGHT" then
                        -- Horizontal: ABOVE = SIDE1, BELOW = SIDE2
                        addon.db.profile.defensives.position = (side == "ABOVE") and "SIDE1" or "SIDE2"
                    else
                        -- Vertical: RIGHT = SIDE1, LEFT = SIDE2
                        addon.db.profile.defensives.position = (side == "RIGHT") and "SIDE1" or "SIDE2"
                    end
                    addon:UpdateFrameSize()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" or dm == "overlay" then return true end
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
                order = 16,
                width = "normal",
                values = function()
                    -- Show all anchor positions; setter handles axis transitions
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
                    -- Auto-transition layout if current is incompatible with new anchor
                    if val ~= "DISABLED" then
                        local o = addon.db.profile.queueOrientation or "LEFT"
                        local s = addon.db.profile.defensives and addon.db.profile.defensives.position or "SIDE1"
                        if s == "LEADING" then s = "SIDE1" end
                        local isH = (o == "LEFT" or o == "RIGHT")
                        if val == "LEFT" then
                            -- Need vertical + sidebar left (SIDE2)
                            if isH then addon.db.profile.queueOrientation = "UP" end
                            addon.db.profile.defensives.position = "SIDE2"
                        elseif val == "RIGHT" then
                            -- Need vertical + sidebar right (SIDE1)
                            if isH then addon.db.profile.queueOrientation = "UP" end
                            addon.db.profile.defensives.position = "SIDE1"
                        elseif val == "TOP" then
                            -- Queue above target → sidebar above (SIDE1, away from target)
                            if not isH then addon.db.profile.queueOrientation = "LEFT" end
                            addon.db.profile.defensives.position = "SIDE1"
                        elseif val == "BOTTOM" then
                            -- Queue below target → sidebar below (SIDE2, away from target)
                            if not isH then addon.db.profile.queueOrientation = "LEFT" end
                            addon.db.profile.defensives.position = "SIDE2"
                        end
                    end
                    if InCombatLockdown() then
                        -- SetPoint against TargetFrame is protected in combat.
                        -- Defer both the anchor move and layout rebuild; the
                        -- PLAYER_REGEN_ENABLED handler will apply both together.
                        addon.pendingLayoutRebuild = true
                    else
                        addon:UpdateTargetFrameAnchor()
                        addon:UpdateFrameSize()
                    end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" or dm == "overlay" then return true end
                    if addon.IsStandardTargetFrame and not addon:IsStandardTargetFrame() then return true end
                    return InCombatLockdown()  -- SetPoint to TargetFrame is protected in combat
                end,
            },
            -- VISIBILITY (20-29)
            visibilityHeader = {
                type = "header",
                name = L["Visibility"],
                order = 20,
            },
            hideQueueOutOfCombat = {
                type = "toggle",
                name = L["Hide Out of Combat"],
                desc = L["Hide Out of Combat desc"],
                order = 21,
                width = "full",
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm == "disabled" or dm == "overlay"
                end,
                get = function() return addon.db.profile.hideQueueOutOfCombat end,
                set = function(_, val)
                    addon.db.profile.hideQueueOutOfCombat = val
                    addon:ForceUpdate()
                end
            },
            hideQueueWhenMounted = {
                type = "toggle",
                name = L["Hide When Mounted"],
                desc = L["Hide When Mounted desc"],
                order = 22,
                width = "full",
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm == "disabled" or dm == "overlay"
                end,
                get = function() return addon.db.profile.hideQueueWhenMounted end,
                set = function(_, val)
                    addon.db.profile.hideQueueWhenMounted = val
                    addon:ForceUpdate()
                end
            },
            requireHostileTarget = {
                type = "toggle",
                name = L["Require Hostile Target"],
                desc = L["Require Hostile Target desc"],
                order = 23,
                width = "full",
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return addon.db.profile.hideQueueOutOfCombat
                        or dm == "disabled" or dm == "overlay"
                end,
                get = function() return addon.db.profile.requireHostileTarget end,
                set = function(_, val)
                    addon.db.profile.requireHostileTarget = val
                    addon:ForceUpdate()
                end
            },
            showHealthBar = {
                type = "toggle",
                name = function()
                    if addon.db.profile.defensives.enabled then
                        return L["Show Health Bar"] .. "  |cff888888(" .. L["disabled when Defensive Queue is enabled"] .. ")|r"
                    end
                    return L["Show Health Bar"]
                end,
                desc = L["Show Health Bar desc"],
                order = 24,
                width = "full",
                get = function() return addon.db.profile.showHealthBar end,
                set = function(_, val)
                    addon.db.profile.showHealthBar = val
                    if UIHealthBar and UIHealthBar.Destroy then
                        UIHealthBar.Destroy()
                    end
                    if val and UIHealthBar and UIHealthBar.CreateHealthBar then
                        UIHealthBar.CreateHealthBar(addon)
                    end
                    -- Recreate pet bar so it picks up the new player-bar stacking offset
                    if UIHealthBar and UIHealthBar.DestroyPet then
                        UIHealthBar.DestroyPet()
                    end
                    if addon.db.profile.showPetHealthBar and UIHealthBar and UIHealthBar.CreatePetHealthBar then
                        UIHealthBar.CreatePetHealthBar(addon)
                    end
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" or dm == "overlay" then return true end
                    return addon.db.profile.defensives.enabled
                end,
            },
            showPetHealthBar = {
                type = "toggle",
                name = function()
                    if addon.db.profile.defensives.enabled then
                        return L["Show Pet Health Bar"] .. "  |cff888888(" .. L["disabled when Defensive Queue is enabled"] .. ")|r"
                    end
                    return L["Show Pet Health Bar"]
                end,
                desc = L["Show Pet Health Bar desc"],
                order = 25,
                width = "full",
                get = function() return addon.db.profile.showPetHealthBar end,
                set = function(_, val)
                    addon.db.profile.showPetHealthBar = val
                    if UIHealthBar and UIHealthBar.DestroyPet then
                        UIHealthBar.DestroyPet()
                    end
                    if val and UIHealthBar and UIHealthBar.CreatePetHealthBar then
                        UIHealthBar.CreatePetHealthBar(addon)
                    end
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" or dm == "overlay" then return true end
                    return addon.db.profile.defensives.enabled
                end,
            },
            -- APPEARANCE (30-39)
            appearanceHeader = {
                type = "header",
                name = L["Appearance"],
                order = 30,
            },
            tooltipMode = {
                type = "select",
                name = L["Tooltips"],
                desc = L["Tooltips desc"],
                order = 32,
                width = "normal",
                values = {
                    never = L["Never"],
                    outOfCombat = L["Out of Combat Only"],
                    always = L["Always"],
                },
                sorting = {"never", "outOfCombat", "always"},
                get = function()
                    -- Migration: convert old settings to new mode
                    if addon.db.profile.tooltipMode then
                        return addon.db.profile.tooltipMode
                    end
                    -- Migrate from old settings
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
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm == "disabled" or dm == "overlay"
                end,
            },
            frameOpacity = {
                type = "range",
                name = L["Frame Opacity"],
                desc = L["Frame Opacity desc"],
                min = 0.1, max = 1.0, step = 0.05,
                order = 33,
                width = "normal",
                get = function() return addon.db.profile.frameOpacity or 1.0 end,
                set = function(_, val)
                    addon.db.profile.frameOpacity = val
                    addon:ForceUpdate()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm == "disabled" or dm == "overlay"
                end,
            },
            queueDesaturation = {
                type = "range",
                name = L["Queue Icon Fade"],
                desc = L["Queue Icon Fade desc"],
                min = 0, max = 1.0, step = 0.05,
                order = 34,
                width = "normal",
                get = function() return addon.db.profile.queueIconDesaturation or 0 end,
                set = function(_, val)
                    addon.db.profile.queueIconDesaturation = val
                    addon:ForceUpdate()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm == "disabled" or dm == "overlay"
                end,
            },
            gamepadIconStyle = {
                type = "select",
                name = L["Gamepad Icon Style"],
                desc = L["Gamepad Icon Style desc"],
                order = 35,
                width = "normal",
                values = {
                    generic = L["Generic"],
                    xbox = L["Xbox"],
                    playstation = L["PlayStation"],
                },
                get = function() return addon.db.profile.gamepadIconStyle or "xbox" end,
                set = function(_, val)
                    addon.db.profile.gamepadIconStyle = val
                    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                    if ActionBarScanner and ActionBarScanner.ClearAllCaches then
                        ActionBarScanner.ClearAllCaches()
                    end
                end,
                -- Applies to both queue and overlay hotkeys; only useless when fully disabled
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            -- SYSTEM (40-49)
            systemHeader = {
                type = "header",
                name = L["System"],
                order = 40,
            },
            panelInteraction = {
                type = "select",
                name = L["Panel Interaction"],
                desc = L["Panel Interaction desc"],
                order = 41,
                width = "normal",
                values = {
                    unlocked = L["Unlocked"],
                    locked = L["Locked"],
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
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm == "disabled" or dm == "overlay"
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
                desc = L["Reset General desc"],
                order = 991,
                width = "normal",
                func = function()
                    local Options = LibStub("JustAC-Options", true)
                    local p = addon.db.profile
                    p.displayMode           = "queue"
                    p.iconSize              = 42
                    p.iconSpacing           = 1
                    p.queueOrientation      = "LEFT"
                    p.targetFrameAnchor     = "DISABLED"
                    p.defensives.position   = "SIDE1"   -- compound dropdown: LEFT + SIDE1 = "Left, Sidebar Above"
                    p.hideQueueOutOfCombat  = false
                    p.hideQueueWhenMounted  = false
                    p.requireHostileTarget  = false
                    p.showHealthBar         = false
                    p.showPetHealthBar      = false
                    p.tooltipMode           = "always"
                    p.frameOpacity          = 1.0
                    p.queueIconDesaturation = 0
                    p.gamepadIconStyle      = "xbox"
                    p.panelInteraction      = "unlocked"
                    -- Clear legacy migration keys
                    p.panelLocked           = nil
                    p.showTooltips          = nil
                    p.tooltipsInCombat      = nil
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon) end  -- displayMode reset to "queue"
                    addon:UpdateFrameSize()
                    if Options and Options.UpdateDefensivesOptions then
                        Options.UpdateDefensivesOptions(addon)
                    end
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
        }
    }
end
