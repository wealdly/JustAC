-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Labels - Icon label settings (hotkey text, cooldown text, charge count)

local MAJOR, MINOR = "JustAC-OptionsLabels", 1
local Labels = LibStub:NewLibrary(MAJOR, MINOR)
if not Labels then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function Labels.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Icon Labels"],
        order = 5.5,
        args = {
            info = {
                type = "description",
                name = L["Icon Labels desc"],
                order = 1,
                fontSize = "medium",
            },
            -- ── STANDARD QUEUE ──────────────────────────────────────────────
            standardHeader = {
                type = "header",
                name = L["Standard Queue"],
                order = 2,
            },
            hotkeyGroup = {
                type = "group",
                inline = true,
                name = "Standard: " .. L["Hotkey Text"],
                order = 2.1,
                args = {
                    show = {
                        type = "toggle",
                        name = L["Show"],
                        order = 1,
                        width = "full",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return not ov or not ov.hotkey or ov.hotkey.show ~= false
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.hotkey.show = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    fontScale = {
                        type = "range",
                        name = L["Font Scale"],
                        desc = L["Font Scale desc"],
                        min = 0.5, max = 3.0, step = 0.05,
                        order = 2,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return (ov and ov.hotkey and ov.hotkey.fontScale) or 1.0
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.hotkey.fontScale = val
                            addon:UpdateFrameSize()
                        end,
                    },
                    color = {
                        type = "color",
                        name = L["Text Color"],
                        desc = L["Text Color desc"],
                        hasAlpha = true,
                        order = 3,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            local c = ov and ov.hotkey and ov.hotkey.color
                            return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1
                        end,
                        set = function(_, r, g, b, a)
                            local c = addon.db.profile.textOverlays.hotkey.color
                            c.r, c.g, c.b, c.a = r, g, b, a
                            addon:UpdateFrameSize()
                        end,
                    },
                    anchor = {
                        type = "select",
                        name = L["Text Anchor"],
                        desc = L["Hotkey Anchor desc"],
                        order = 4,
                        width = "normal",
                        values = {
                            TOPRIGHT    = L["Top Right"],
                            TOPLEFT     = L["Top Left"],
                            TOP         = L["Top Center"],
                            CENTER      = L["Center"],
                            BOTTOMRIGHT = L["Bottom Right"],
                            BOTTOMLEFT  = L["Bottom Left"],
                        },
                        sorting = {"TOPRIGHT", "TOPLEFT", "TOP", "CENTER", "BOTTOMRIGHT", "BOTTOMLEFT"},
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return (ov and ov.hotkey and ov.hotkey.anchor) or "TOPRIGHT"
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.hotkey.anchor = val
                            addon:UpdateFrameSize()
                        end,
                    },
                },
            },
            cooldownGroup = {
                type = "group",
                inline = true,
                name = "Standard: " .. L["Cooldown Text"],
                order = 2.2,
                args = {
                    show = {
                        type = "toggle",
                        name = L["Show"],
                        order = 1,
                        width = "full",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return not ov or not ov.cooldown or ov.cooldown.show ~= false
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.cooldown.show = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    fontScale = {
                        type = "range",
                        name = L["Font Scale"],
                        desc = L["Font Scale desc"],
                        min = 0.5, max = 3.0, step = 0.05,
                        order = 2,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return (ov and ov.cooldown and ov.cooldown.fontScale) or 1.0
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.cooldown.fontScale = val
                            addon:UpdateFrameSize()
                        end,
                    },
                    color = {
                        type = "color",
                        name = L["Text Color"],
                        desc = L["Text Color desc"],
                        hasAlpha = true,
                        order = 3,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            local c = ov and ov.cooldown and ov.cooldown.color
                            return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 0.5
                        end,
                        set = function(_, r, g, b, a)
                            local c = addon.db.profile.textOverlays.cooldown.color
                            c.r, c.g, c.b, c.a = r, g, b, a
                            addon:UpdateFrameSize()
                        end,
                    },
                },
            },
            chargesGroup = {
                type = "group",
                inline = true,
                name = "Standard: " .. L["Charge Count"],
                order = 2.3,
                args = {
                    show = {
                        type = "toggle",
                        name = L["Show"],
                        order = 1,
                        width = "full",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return not ov or not ov.charges or ov.charges.show ~= false
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.charges.show = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    fontScale = {
                        type = "range",
                        name = L["Font Scale"],
                        desc = L["Font Scale desc"],
                        min = 0.5, max = 3.0, step = 0.05,
                        order = 2,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return (ov and ov.charges and ov.charges.fontScale) or 1.0
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.charges.fontScale = val
                            addon:UpdateFrameSize()
                        end,
                    },
                    color = {
                        type = "color",
                        name = L["Text Color"],
                        desc = L["Text Color desc"],
                        hasAlpha = true,
                        order = 3,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            local c = ov and ov.charges and ov.charges.color
                            return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1
                        end,
                        set = function(_, r, g, b, a)
                            local c = addon.db.profile.textOverlays.charges.color
                            c.r, c.g, c.b, c.a = r, g, b, a
                            addon:UpdateFrameSize()
                        end,
                    },
                    anchor = {
                        type = "select",
                        name = L["Text Anchor"],
                        desc = L["Charge Anchor desc"],
                        order = 4,
                        width = "normal",
                        values = {
                            BOTTOMRIGHT = L["Bottom Right"],
                            BOTTOMLEFT  = L["Bottom Left"],
                            BOTTOM      = L["Bottom Center"],
                        },
                        sorting = {"BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOM"},
                        get = function()
                            local ov = addon.db.profile.textOverlays
                            return (ov and ov.charges and ov.charges.anchor) or "BOTTOMRIGHT"
                        end,
                        set = function(_, val)
                            addon.db.profile.textOverlays.charges.anchor = val
                            addon:UpdateFrameSize()
                        end,
                    },
                },
            },
            -- ── NAMEPLATE OVERLAY ────────────────────────────────────────────
            overlayHeader = {
                type = "header",
                name = L["Nameplate Overlay"] .. " Queue",
                order = 3,
            },
            npHotkeyGroup = {
                type = "group",
                inline = true,
                name = "Overlay: " .. L["Hotkey Text"],
                order = 3.1,
                args = {
                    show = {
                        type = "toggle",
                        name = L["Show"],
                        order = 1,
                        width = "full",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return not ov or not ov.hotkey or ov.hotkey.show ~= false
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.hotkey.show = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    fontScale = {
                        type = "range",
                        name = L["Font Scale"],
                        desc = L["Font Scale desc"],
                        min = 0.5, max = 3.0, step = 0.05,
                        order = 2,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return (ov and ov.hotkey and ov.hotkey.fontScale) or 1.0
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.hotkey.fontScale = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                    color = {
                        type = "color",
                        name = L["Text Color"],
                        desc = L["Text Color desc"],
                        hasAlpha = true,
                        order = 3,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            local c = ov and ov.hotkey and ov.hotkey.color
                            return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1
                        end,
                        set = function(_, r, g, b, a)
                            local c = addon.db.profile.nameplateOverlay.textOverlays.hotkey.color
                            c.r, c.g, c.b, c.a = r, g, b, a
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                    anchor = {
                        type = "select",
                        name = L["Text Anchor"],
                        desc = L["Hotkey Anchor desc"],
                        order = 4,
                        width = "normal",
                        values = {
                            TOPRIGHT    = L["Top Right"],
                            TOPLEFT     = L["Top Left"],
                            TOP         = L["Top Center"],
                            CENTER      = L["Center"],
                            BOTTOMRIGHT = L["Bottom Right"],
                            BOTTOMLEFT  = L["Bottom Left"],
                        },
                        sorting = {"TOPRIGHT", "TOPLEFT", "TOP", "CENTER", "BOTTOMRIGHT", "BOTTOMLEFT"},
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return (ov and ov.hotkey and ov.hotkey.anchor) or "TOPRIGHT"
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.hotkey.anchor = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                },
            },
            npCooldownGroup = {
                type = "group",
                inline = true,
                name = "Overlay: " .. L["Cooldown Text"],
                order = 3.2,
                args = {
                    show = {
                        type = "toggle",
                        name = L["Show"],
                        order = 1,
                        width = "full",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return not ov or not ov.cooldown or ov.cooldown.show ~= false
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.cooldown.show = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    fontScale = {
                        type = "range",
                        name = L["Font Scale"],
                        desc = L["Font Scale desc"],
                        min = 0.5, max = 3.0, step = 0.05,
                        order = 2,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return (ov and ov.cooldown and ov.cooldown.fontScale) or 1.0
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.cooldown.fontScale = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                    color = {
                        type = "color",
                        name = L["Text Color"],
                        desc = L["Text Color desc"],
                        hasAlpha = true,
                        order = 3,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            local c = ov and ov.cooldown and ov.cooldown.color
                            return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 0.5
                        end,
                        set = function(_, r, g, b, a)
                            local c = addon.db.profile.nameplateOverlay.textOverlays.cooldown.color
                            c.r, c.g, c.b, c.a = r, g, b, a
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                },
            },
            npChargesGroup = {
                type = "group",
                inline = true,
                name = "Overlay: " .. L["Charge Count"],
                order = 3.3,
                args = {
                    show = {
                        type = "toggle",
                        name = L["Show"],
                        order = 1,
                        width = "full",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return not ov or not ov.charges or ov.charges.show ~= false
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.charges.show = val
                            addon:ForceUpdateAll()
                        end,
                    },
                    fontScale = {
                        type = "range",
                        name = L["Font Scale"],
                        desc = L["Font Scale desc"],
                        min = 0.5, max = 3.0, step = 0.05,
                        order = 2,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return (ov and ov.charges and ov.charges.fontScale) or 1.0
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.charges.fontScale = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                    color = {
                        type = "color",
                        name = L["Text Color"],
                        desc = L["Text Color desc"],
                        hasAlpha = true,
                        order = 3,
                        width = "normal",
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            local c = ov and ov.charges and ov.charges.color
                            return (c and c.r) or 1, (c and c.g) or 1, (c and c.b) or 1, (c and c.a) or 1
                        end,
                        set = function(_, r, g, b, a)
                            local c = addon.db.profile.nameplateOverlay.textOverlays.charges.color
                            c.r, c.g, c.b, c.a = r, g, b, a
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                    anchor = {
                        type = "select",
                        name = L["Text Anchor"],
                        desc = L["Charge Anchor desc"],
                        order = 4,
                        width = "normal",
                        values = {
                            BOTTOMRIGHT = L["Bottom Right"],
                            BOTTOMLEFT  = L["Bottom Left"],
                            BOTTOM      = L["Bottom Center"],
                        },
                        sorting = {"BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOM"},
                        get = function()
                            local ov = addon.db.profile.nameplateOverlay.textOverlays
                            return (ov and ov.charges and ov.charges.anchor) or "BOTTOMRIGHT"
                        end,
                        set = function(_, val)
                            addon.db.profile.nameplateOverlay.textOverlays.charges.anchor = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                        end,
                    },
                },
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
                desc = L["Reset Icon Labels desc"],
                order = 991,
                width = "normal",
                func = function()
                    local p = addon.db.profile
                    p.textOverlays = {
                        hotkey   = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="TOPRIGHT" },
                        cooldown = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=0.5} },
                        charges  = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="BOTTOMRIGHT" },
                    }
                    p.nameplateOverlay.textOverlays = {
                        hotkey   = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="TOPRIGHT" },
                        cooldown = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=0.5} },
                        charges  = { show=true, fontScale=1.0, color={r=1,g=1,b=1,a=1}, anchor="BOTTOMRIGHT" },
                    }
                    addon:UpdateFrameSize()
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
        },
    }
end
