-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/General - Shared settings that apply to both display surfaces
local General = LibStub:NewLibrary("JustAC-OptionsGeneral", 2)
if not General then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
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
            -- SHARED BEHAVIOR (10-19)
            behaviorHeader = {
                type = "header",
                name = L["Shared Behavior"],
                order = 10,
            },
            interruptMode = {
                type = "select",
                name = L["Interrupt Mode"],
                desc = L["Interrupt Mode desc"],
                order = 11,
                width = "double",
                values = {
                    disabled      = L["Interrupt Mode Disabled"],
                    kickOnly      = L["Interrupt Mode Kick Only"],
                    ccShielded    = L["Interrupt Mode CC Shielded"],
                    ccPrefer      = L["Interrupt Mode CC Prefer"],
                },
                sorting = { "disabled", "kickOnly", "ccShielded", "ccPrefer" },
                get = function() return addon.db.profile.interruptMode or "ccPrefer" end,
                set = function(_, val)
                    addon.db.profile.interruptMode = val
                    addon:UpdateFrameSize()
                    -- Recreate overlay to add/remove interrupt icon
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            showFlash = {
                type = "toggle",
                name = L["Show Key Press Flash"],
                desc = L["Show Key Press Flash desc"],
                order = 12,
                width = "full",
                get = function() return addon.db.profile.showFlash ~= false end,
                set = function(_, val)
                    addon.db.profile.showFlash = val
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            gamepadIconStyle = {
                type = "select",
                name = L["Gamepad Icon Style"],
                desc = L["Gamepad Icon Style desc"],
                order = 13,
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
            inputPreference = {
                type = "select",
                name = L["Input Preference"],
                desc = L["Input Preference desc"],
                order = 14,
                width = "normal",
                values = {
                    auto = L["Auto-Detect"],
                    keyboard = L["Keyboard"],
                    gamepad = L["Gamepad"],
                },
                sorting = { "auto", "keyboard", "gamepad" },
                get = function() return addon.db.profile.inputPreference or "auto" end,
                set = function(_, val)
                    addon.db.profile.inputPreference = val
                    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
                    if ActionBarScanner and ActionBarScanner.ClearAllCaches then
                        ActionBarScanner.ClearAllCaches()
                    end
                    local UIRenderer = LibStub("JustAC-UIRenderer", true)
                    if UIRenderer and UIRenderer.InvalidateHotkeyCache then
                        UIRenderer.InvalidateHotkeyCache()
                    end
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            -- SOUNDS (20-29)
            soundsHeader = {
                type = "header",
                name = L["Sounds"],
                order = 20,
            },
            interruptAlertSound = {
                type = "select",
                name = L["Interrupt Alert"],
                desc = L["Interrupt Alert Sound desc"],
                order = 21,
                width = "double",
                values = {
                    none          = L["Disabled"],
                    shing         = "Shing!",
                    wham          = "Wham!",
                    simonChime    = "Simon Chime",
                    shortCircuit  = "Short Circuit",
                    pvpFlag       = "PvP Flag",
                    pvpFlagHorde  = "PvP Flag (Horde)",
                    pvpAlliance   = "PvP Alliance",
                    pvpHorde      = "PvP Horde",
                    thunderCrack  = "Thunder Crack",
                    warDrums      = "War Drums",
                    dwarfHorn     = "Dwarf Horn",
                    scourgeHorn   = "Scourge Horn",
                    explosion     = "Explosion",
                    cheer         = "Cheer",
                    felPortal     = "Fel Portal",
                    felNova       = "Fel Nova",
                    humm          = "Humm",
                    cartoonFX     = "Cartoon FX",
                    rubberDucky   = "Rubber Ducky",
                    pygmyDrums    = "Pygmy Drums",
                    grimrailHorn  = "Grimrail Horn",
                    squireHorn    = "Squire Horn",
                    gruntlingHorn = "Gruntling Horn",
                },
                sorting = { "none", "shing", "wham", "simonChime", "shortCircuit", "pvpFlag", "pvpFlagHorde", "pvpAlliance", "pvpHorde", "thunderCrack", "warDrums", "dwarfHorn", "scourgeHorn", "explosion", "cheer", "felPortal", "felNova", "humm", "cartoonFX", "rubberDucky", "pygmyDrums", "grimrailHorn", "squireHorn", "gruntlingHorn" },
                get = function() return addon.db.profile.interruptAlertSound or "none" end,
                set = function(_, val) addon.db.profile.interruptAlertSound = val end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
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
                    local p = addon.db.profile
                    p.displayMode         = "queue"
                    p.interruptMode       = "ccPrefer"
                    p.showFlash           = true
                    p.gamepadIconStyle    = "xbox"
                    p.inputPreference     = "auto"
                    p.interruptAlertSound = "none"
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon) end  -- displayMode reset to "queue"
                    addon:UpdateFrameSize()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
        }
    }
end
