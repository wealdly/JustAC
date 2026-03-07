-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/General - Shared settings that apply to both display surfaces
local General = LibStub:NewLibrary("JustAC-OptionsGeneral", 4)
if not General then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

function General.CreateTabArgs(addon)
    local Labels  = LibStub("JustAC-OptionsLabels", true)
    local Hotkeys = LibStub("JustAC-OptionsHotkeys", true)

    -- Build sub-tab args for Icon Labels and Hotkey Overrides
    local labelsTab  = Labels  and Labels.CreateTabArgs  and Labels.CreateTabArgs(addon)  or nil
    local hotkeysTab = Hotkeys and Hotkeys.CreateTabArgs and Hotkeys.CreateTabArgs(addon) or nil
    -- Re-order sub-tabs: Settings=1, Icon Labels=2, Hotkey Overrides=3
    if labelsTab  then labelsTab.order  = 2 end
    if hotkeysTab then hotkeysTab.order = 3 end

    return {
        type = "group",
        name = L["General"],
        order = 1,
        childGroups = "tab",
        args = {
            -- ── SUB-TAB 1: SETTINGS ─────────────────────────────────
            settings = {
                type = "group",
                name = L["Settings"],
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
            greyOutWhileCasting = {
                type = "toggle",
                name = L["Grey Out While Casting"],
                desc = L["Grey Out While Casting desc"],
                order = 13,
                width = "full",
                get = function() return addon.db.profile.greyOutWhileCasting ~= false end,
                set = function(_, val)
                    addon.db.profile.greyOutWhileCasting = val
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            greyOutWhileChanneling = {
                type = "toggle",
                name = L["Grey Out While Channeling"],
                desc = L["Grey Out While Channeling desc"],
                order = 14,
                width = "full",
                get = function() return addon.db.profile.greyOutWhileChanneling ~= false end,
                set = function(_, val)
                    addon.db.profile.greyOutWhileChanneling = val
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            gamepadIconStyle = {
                type = "select",
                name = L["Gamepad Icon Style"],
                desc = L["Gamepad Icon Style desc"],
                order = 15,
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
                order = 16,
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
            -- OFFENSIVE QUEUE CONTENT (30-39)
            offensiveQueueHeader = {
                type = "header",
                name = L["Offensive Queue"],
                order = 30,
            },
            includeHiddenAbilities = {
                type = "toggle",
                name = L["Include All Available Abilities"],
                desc = L["Include All Available Abilities desc"],
                order = 31,
                width = "full",
                get = function() return addon.db.profile.includeHiddenAbilities ~= false end,
                set = function(_, val)
                    addon.db.profile.includeHiddenAbilities = val
                    addon:ForceUpdate()
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            showSpellbookProcs = {
                type = "toggle",
                name = L["Insert Procced Abilities"],
                desc = L["Insert Procced Abilities desc"],
                order = 32,
                width = "full",
                get = function() return addon.db.profile.showSpellbookProcs or false end,
                set = function(_, val)
                    addon.db.profile.showSpellbookProcs = val
                    addon:ForceUpdate()
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            hideItemAbilities = {
                type = "toggle",
                name = L["Allow Item Abilities"],
                desc = L["Allow Item Abilities desc"],
                order = 33,
                width = "full",
                get = function() return not addon.db.profile.hideItemAbilities end,
                set = function(_, val)
                    addon.db.profile.hideItemAbilities = not val
                    addon:ForceUpdate()
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            -- DEFENSIVE QUEUE CONTENT (40-49)
            defensiveQueueHeader = {
                type = "header",
                name = L["Defensive Queue"],
                order = 40,
            },
            showDefensiveProcs = {
                type = "toggle",
                name = L["Insert Procced Defensives"],
                desc = L["Insert Procced Defensives desc"],
                order = 41,
                width = "full",
                get = function() return addon.db.profile.defensives.showProcs ~= false end,
                set = function(_, val)
                    addon.db.profile.defensives.showProcs = val
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" then return true end
                    local standardEnabled = addon.db.profile.defensives.enabled
                    local npo = addon.db.profile.nameplateOverlay
                    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                    return not standardEnabled and not overlayEnabled
                end,
            },
            allowDefensiveItems = {
                type = "toggle",
                name = L["Allow Items in Spell Lists"],
                desc = L["Allow Items in Spell Lists desc"],
                order = 42,
                width = "full",
                get = function() return addon.db.profile.defensives.allowItems == true end,
                set = function(_, val)
                    addon.db.profile.defensives.allowItems = val
                    local Defensives = LibStub("JustAC-OptionsDefensives", true)
                    if Defensives then Defensives.UpdateDefensivesOptions(addon) end
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" then return true end
                    local standardEnabled = addon.db.profile.defensives.enabled
                    local npo = addon.db.profile.nameplateOverlay
                    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                    return not standardEnabled and not overlayEnabled
                end,
            },
            autoInsertPotions = {
                type = "toggle",
                name = L["Auto-Insert Health Potions"],
                desc = L["Auto-Insert Health Potions desc"],
                order = 43,
                width = "full",
                get = function() return addon.db.profile.defensives.autoInsertPotions ~= false end,
                set = function(_, val)
                    addon.db.profile.defensives.autoInsertPotions = val
                    addon:ForceUpdateAll()
                end,
                disabled = function()
                    local dm = addon.db.profile.displayMode or "queue"
                    if dm == "disabled" then return true end
                    local standardEnabled = addon.db.profile.defensives.enabled
                    local npo = addon.db.profile.nameplateOverlay
                    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                    return not standardEnabled and not overlayEnabled
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
                    p.greyOutWhileCasting = true
                    p.greyOutWhileChanneling = true
                    p.gamepadIconStyle    = "xbox"
                    p.inputPreference     = "auto"
                    p.interruptAlertSound = "none"
                    -- Offensive queue content
                    p.includeHiddenAbilities = true
                    p.showSpellbookProcs     = true
                    p.hideItemAbilities      = false
                    -- Defensive queue content
                    p.defensives.showProcs        = true
                    p.defensives.allowItems       = true
                    p.defensives.autoInsertPotions = true
                    local NPO = LibStub("JustAC-UINameplateOverlay", true)
                    if NPO then NPO.Destroy(addon) end  -- displayMode reset to "queue"
                    addon:UpdateFrameSize()
                    addon:ForceUpdateAll()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
                },
            },
            -- ── SUB-TAB 2: ICON LABELS ──────────────────────────────
            iconLabels = labelsTab,
            -- ── SUB-TAB 3: HOTKEY OVERRIDES ─────────────────────────
            hotkeyOverrides = hotkeysTab,
        },
    }
end
