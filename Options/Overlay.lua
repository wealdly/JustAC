-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Overlay - Nameplate overlay settings tab

local MAJOR, MINOR = "JustAC-OptionsOverlay", 1
local Overlay = LibStub:NewLibrary(MAJOR, MINOR)
if not Overlay then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local wipe = wipe

function Overlay.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Nameplate Overlay"],
        order = 2,
        args = {
            info = {
                type = "description",
                name = L["Nameplate Overlay desc"],
                order = 1,
                fontSize = "medium",
            },
            reverseAnchor = {
                type = "toggle",
                name = L["Reverse Anchor"],
                desc = L["Reverse Anchor desc"],
                order = 2,
                width = "normal",
                get = function() return addon.db.profile.nameplateOverlay.reverseAnchor end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.reverseAnchor = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            expansion = {
                type = "select",
                name = L["Expansion Direction"],
                desc = L["Expansion Direction desc"],
                order = 3,
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
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            maxIcons = {
                type = "select",
                name = L["Offensive Slots"],
                desc = L["Max Icons desc"],
                order = 12,
                width = "normal",
                values = { [1] = "1", [2] = "2", [3] = "3", [4] = "4", [5] = "5" },
                sorting = { 1, 2, 3, 4, 5 },
                get = function() return addon.db.profile.nameplateOverlay.maxIcons or 1 end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.maxIcons = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            iconSize = {
                type = "range",
                name = L["Nameplate Icon Size"],
                desc = L["Icon Size desc"],
                order = 5,
                width = "normal",
                min = 16, max = 48, step = 2,
                get = function() return addon.db.profile.nameplateOverlay.iconSize or 26 end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.iconSize = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            iconSpacing = {
                type = "range",
                name = L["Spacing"],
                desc = L["Spacing desc"],
                order = 6,
                width = "normal",
                min = 0, max = 10, step = 1,
                get = function() return addon.db.profile.nameplateOverlay.iconSpacing or 2 end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.iconSpacing = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            opacity = {
                type = "range",
                name = L["Frame Opacity"],
                desc = L["Frame Opacity desc"],
                order = 7,
                width = "normal",
                min = 0.1, max = 1.0, step = 0.05,
                get = function() return addon.db.profile.nameplateOverlay.opacity or 1.0 end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.opacity = val
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            showGlow = {
                type = "select",
                name = L["Highlight Mode"],
                desc = L["Highlight Mode desc"],
                order = 8,
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
                    addon:ForceUpdateAll()  -- must trigger OnHealthChanged to re-run RenderDefensives
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            showFlash = {
                type = "toggle",
                name = L["Show Key Press Flash"],
                desc = L["Show Key Press Flash desc"],
                order = 10,
                width = "normal",
                get = function() return addon.db.profile.nameplateOverlay.showFlash ~= false end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.showFlash = val
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            offensiveSectionHeader = {
                type = "header",
                name = L["Offensive Queue"],
                order = 11,
            },
            interruptMode = {
                type = "select",
                name = L["Interrupt Mode"],
                desc = L["Interrupt Mode desc"],
                order = 13,
                width = "double",
                values = {
                    disabled      = L["Interrupt Mode Disabled"],
                    kickOnly      = L["Interrupt Mode Kick Only"],
                    ccShielded    = L["Interrupt Mode CC Shielded"],
                    ccPrefer      = L["Interrupt Mode CC Prefer"],
                },
                sorting = { "disabled", "kickOnly", "ccShielded", "ccPrefer" },
                get = function() return addon.db.profile.nameplateOverlay.interruptMode or "ccPrefer" end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.interruptMode = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            defensiveSectionHeader = {
                type = "header",
                name = L["Defensive Suggestions"],
                order = 20,
            },
            showDefensives = {
                type = "toggle",
                name = L["Nameplate Show Defensives"],
                desc = L["Nameplate Show Defensives desc"],
                order = 21,
                width = "full",
                get = function() return addon.db.profile.nameplateOverlay.showDefensives end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.showDefensives = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
            defensiveDisplayMode = {
                type = "select",
                name = L["Nameplate Defensive Display Mode"],
                desc = L["Nameplate Defensive Display Mode desc"],
                order = 22,
                width = "normal",
                values = {
                    combatOnly = L["In Combat Only"],
                    always     = L["Always"],
                },
                sorting = { "combatOnly", "always" },
                get = function() return addon.db.profile.nameplateOverlay.defensiveDisplayMode or "combatOnly" end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.defensiveDisplayMode = val
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return (dm ~= "overlay" and dm ~= "both")
                        or not addon.db.profile.nameplateOverlay.showDefensives
                end,
            },
            maxDefensiveIcons = {
                type = "select",
                name = L["Nameplate Defensive Count"],
                desc = L["Defensive Max Icons desc"],
                order = 23,
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
                    local dm = addon.db.profile.displayMode or "queue"
                    return (dm ~= "overlay" and dm ~= "both")
                        or not addon.db.profile.nameplateOverlay.showDefensives
                end,
            },
            showHealthBar = {
                type = "toggle",
                name = L["Nameplate Show Health Bars"],
                desc = L["Nameplate Show Health Bars desc"],
                order = 24,
                width = "full",
                get = function() return addon.db.profile.nameplateOverlay.showHealthBar end,
                set = function(_, val)
                    addon.db.profile.nameplateOverlay.showHealthBar = val
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm ~= "overlay" and dm ~= "both" then return true end
                    return not addon.db.profile.nameplateOverlay.showDefensives
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
                desc = L["Reset Overlay desc"],
                order = 991,
                width = "normal",
                func = function()
                    local npo = addon.db.profile.nameplateOverlay
                    wipe(npo)
                    npo.maxIcons             = 3
                    npo.reverseAnchor        = false
                    npo.expansion            = "out"
                    npo.iconSize             = 32
                    npo.iconSpacing          = 2
                    npo.opacity              = 1.0
                    npo.showGlow             = true
                    npo.glowMode             = "all"
                    npo.showFlash            = true
                    npo.showDefensives       = true
                    npo.maxDefensiveIcons    = 3
                    npo.defensiveDisplayMode = "always"
                    npo.showHealthBar        = true
                    npo.interruptMode        = "ccPrefer"
                    -- Restore textOverlays (wipe destroyed them; Labels tab depends on this)
                    npo.textOverlays = {
                        hotkey   = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="TOPRIGHT" },
                        cooldown = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=0.5} },
                        charges  = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="BOTTOMRIGHT" },
                    }
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    return dm ~= "overlay" and dm ~= "both"
                end,
            },
        },
    }
end
