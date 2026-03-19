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
            defensiveDetached = {
                type = "toggle",
                name = L["Independent Positioning"],
                desc = L["Independent Positioning desc"],
                order = 3,
                width = "full",
                get = function()
                    return addon.db.profile.defensives and addon.db.profile.defensives.detached or false
                end,
                set = function(_, val)
                    addon.db.profile.defensives = addon.db.profile.defensives or {}
                    addon.db.profile.defensives.detached = val
                    addon:UpdateFrameSize()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
            },
            detachedOrientation = {
                type = "select",
                name = L["Detached Orientation"],
                desc = L["Detached Orientation desc"],
                order = 4,
                width = "normal",
                values = {
                    LEFT  = L["Left"],
                    RIGHT = L["Right"],
                    UP    = L["Up"],
                    DOWN  = L["Down"],
                },
                sorting = { "LEFT", "RIGHT", "UP", "DOWN" },
                get = function()
                    return (addon.db.profile.defensives and addon.db.profile.defensives.detachedOrientation) or "LEFT"
                end,
                set = function(_, val)
                    addon.db.profile.defensives = addon.db.profile.defensives or {}
                    addon.db.profile.defensives.detachedOrientation = val
                    addon:UpdateFrameSize()
                    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                end,
                hidden = function()
                    return not (addon.db.profile.defensives and addon.db.profile.defensives.detached)
                end,
            },
            resetDefensivePosition = {
                type = "execute",
                name = L["Reset Defensive Frame Position"],
                order = 5,
                func = function()
                    local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
                    if addon.defensiveFrame then
                        addon.defensiveFrame:ClearAllPoints()
                        addon.defensiveFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
                        if UIFrameFactory and UIFrameFactory.SaveDefensivePosition then
                            UIFrameFactory.SaveDefensivePosition(addon)
                        end
                    end
                end,
                hidden = function()
                    return not (addon.db.profile.defensives and addon.db.profile.defensives.detached)
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
                    kickPrefer    = L["Interrupt Mode Kick Prefer"],
                    ccPrefer      = L["Interrupt Mode CC Prefer"],
                },
                sorting = { "disabled", "kickOnly", "kickPrefer", "ccPrefer" },
                get = function() return addon.db.profile.interruptMode or "kickPrefer" end,
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
            showUsabilityTint = {
                type = "toggle",
                name = L["Show Usability Tint"],
                desc = L["Show Usability Tint desc"],
                order = 15,
                width = "full",
                get = function() return addon.db.profile.showUsabilityTint ~= false end,
                set = function(_, val)
                    addon.db.profile.showUsabilityTint = val
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            showRangeTint = {
                type = "toggle",
                name = L["Show Range Tint"],
                desc = L["Show Range Tint desc"],
                order = 16,
                width = "full",
                get = function() return addon.db.profile.showRangeTint ~= false end,
                set = function(_, val)
                    addon.db.profile.showRangeTint = val
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            showCastingHighlight = {
                type = "toggle",
                name = L["Show Casting Highlight"],
                desc = L["Show Casting Highlight desc"],
                order = 17,
                width = "full",
                get = function() return addon.db.profile.showCastingHighlight ~= false end,
                set = function(_, val)
                    addon.db.profile.showCastingHighlight = val
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            gamepadIconStyle = {
                type = "select",
                name = L["Gamepad Icon Style"],
                desc = L["Gamepad Icon Style desc"],
                order = 18,
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
                order = 19,
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
            -- PERFORMANCE (20-22)
            performanceHeader = {
                type = "header",
                name = L["Performance"],
                order = 20,
            },
            disableBlizzardHighlight = {
                type = "toggle",
                name = L["Disable Blizzard Highlight"],
                desc = L["Disable Blizzard Highlight desc"],
                order = 21,
                width = "full",
                get = function() return not GetCVarBool("assistedCombatHighlight") end,
                set = function(_, val)
                    SetCVar("assistedCombatHighlight", val and 0 or 1)
                end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            -- SOUNDS (23-29)
            soundsHeader = {
                type = "header",
                name = L["Sounds"],
                order = 23,
            },
            interruptAlertSound = {
                type = "select",
                name = L["Interrupt Alert"],
                desc = L["Interrupt Alert Sound desc"],
                order = 24,
                width = "double",
                dialogControl = "LSM30_Sound",
                values = function()
                    local LSM = LibStub("LibSharedMedia-3.0", true)
                    return LSM and LSM:HashTable(LSM.MediaType.SOUND) or {}
                end,
                get = function() return addon.db.profile.interruptAlertSound or "None" end,
                set = function(_, val) addon.db.profile.interruptAlertSound = val end,
                disabled = function()
                    return (addon.db.profile.displayMode or "queue") == "disabled"
                end,
            },
            testInterruptSound = {
                type = "execute",
                name = "|TInterface\\Common\\VoiceChat-Speaker:0|t Test",
                order = 25,
                width = "half",
                func = function()
                    local UIRenderer = LibStub("JustAC-UIRenderer", true)
                    if UIRenderer and UIRenderer.PlayInterruptAlertSound then
                        UIRenderer.PlayInterruptAlertSound(addon.db.profile)
                    end
                end,
                disabled = function()
                    local s = addon.db.profile.interruptAlertSound
                    return not s or s == "None" or (addon.db.profile.displayMode or "queue") == "disabled"
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
                    p.interruptMode       = "kickPrefer"
                    p.showFlash           = true
                    p.showUsabilityTint   = true
                    p.showRangeTint       = true
                    p.showCastingHighlight = true
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
