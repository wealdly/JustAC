-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/General - Shared settings that apply to both display surfaces
local General = LibStub:NewLibrary("JustAC-OptionsGeneral", 4)
if not General then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- displayMode == "disabled" turns off every surface; most controls gate on it.
local function fullyDisabled(addon)
    return (addon.db.profile.displayMode or "queue") == "disabled"
end

local function rebuildNPO(addon)
    local NPO = LibStub("JustAC-UINameplateOverlay", true)
    if NPO then NPO.Destroy(addon); NPO.Create(addon) end
end

local function clearScannerCaches()
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    if ActionBarScanner and ActionBarScanner.ClearAllCaches then
        ActionBarScanner.ClearAllCaches()
    end
end

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
                            local previous = addon.db.profile.displayMode or "queue"
                            addon.db.profile.displayMode = val
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then
                                NPO.Destroy(addon)
                                if val == "overlay" or val == "both" then
                                    NPO.Create(addon)
                                end
                            end
                            if previous == "disabled" and val ~= "disabled" then
                                addon:InvalidateCaches({spells = true})
                                addon:OnHealthChanged(nil, "player")
                            end
                            addon:ForceUpdateAll()
                            W.NotifyChange()
                        end,
                    },
                    defensiveDetached = W.toggle(addon, "defensives.detached", {
                        name = L["Independent Positioning"], desc = L["Independent Positioning desc"],
                        order = 3, width = "full", default = false,
                        onSet = function() addon:UpdateFrameSize() end,
                        notify = true,
                    }),
                    detachedOrientation = W.select(addon, "defensives.detachedOrientation", {
                        name = L["Detached Orientation"], desc = L["Detached Orientation desc"],
                        order = 4, width = "normal", default = "LEFT",
                        values = { LEFT = L["Left"], RIGHT = L["Right"], UP = L["Up"], DOWN = L["Down"] },
                        sorting = { "LEFT", "RIGHT", "UP", "DOWN" },
                        onSet = function() addon:UpdateFrameSize() end,
                        notify = true,
                        hidden = function()
                            return not (addon.db.profile.defensives and addon.db.profile.defensives.detached)
                        end,
                    }),
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
                    interruptMode = W.select(addon, "interruptMode", {
                        name = L["Interrupt Mode"], desc = L["Interrupt Mode desc"],
                        order = 11, width = "double", default = "kickPrefer",
                        values = {
                            disabled   = L["Interrupt Mode Disabled"],
                            kickOnly   = L["Interrupt Mode Kick Only"],
                            kickPrefer = L["Interrupt Mode Kick Prefer"],
                            ccPrefer   = L["Interrupt Mode CC Prefer"],
                        },
                        sorting = { "disabled", "kickOnly", "kickPrefer", "ccPrefer" },
                        -- Recreate overlay to add/remove interrupt icon
                        onSet = function() addon:UpdateFrameSize(); rebuildNPO(addon) end,
                        disabled = fullyDisabled,
                    }),
                    showFlash = W.toggle(addon, "showFlash", {
                        name = L["Show Key Press Flash"], desc = L["Show Key Press Flash desc"],
                        order = 12, width = "full", default = true, disabled = fullyDisabled,
                    }),
                    greyOutWhileCasting = W.toggle(addon, "greyOutWhileCasting", {
                        name = L["Grey Out While Casting"], desc = L["Grey Out While Casting desc"],
                        order = 13, width = "full", default = true, disabled = fullyDisabled,
                    }),
                    greyOutWhileChanneling = W.toggle(addon, "greyOutWhileChanneling", {
                        name = L["Grey Out While Channeling"], desc = L["Grey Out While Channeling desc"],
                        order = 14, width = "full", default = true, disabled = fullyDisabled,
                    }),
                    showUsabilityTint = W.toggle(addon, "showUsabilityTint", {
                        name = L["Show Usability Tint"], desc = L["Show Usability Tint desc"],
                        order = 15, width = "full", default = true, disabled = fullyDisabled,
                    }),
                    showRangeTint = W.toggle(addon, "showRangeTint", {
                        name = L["Show Range Tint"], desc = L["Show Range Tint desc"],
                        order = 16, width = "full", default = true, disabled = fullyDisabled,
                    }),
                    showCastingHighlight = W.toggle(addon, "showCastingHighlight", {
                        name = L["Show Casting Highlight"], desc = L["Show Casting Highlight desc"],
                        order = 17, width = "full", default = true, disabled = fullyDisabled,
                    }),
                    gamepadIconStyle = W.select(addon, "gamepadIconStyle", {
                        name = L["Gamepad Icon Style"], desc = L["Gamepad Icon Style desc"],
                        order = 18, width = "normal", default = "xbox",
                        values = { generic = L["Generic"], xbox = L["Xbox"], playstation = L["PlayStation"] },
                        onSet = function() clearScannerCaches() end,
                        -- Applies to both queue and overlay hotkeys; only useless when fully disabled
                        disabled = fullyDisabled,
                    }),
                    inputPreference = W.select(addon, "inputPreference", {
                        name = L["Input Preference"], desc = L["Input Preference desc"],
                        order = 19, width = "normal", default = "auto",
                        values = { auto = L["Auto-Detect"], keyboard = L["Keyboard"], gamepad = L["Gamepad"] },
                        sorting = { "auto", "keyboard", "gamepad" },
                        onSet = function()
                            clearScannerCaches()
                            local UIRenderer = LibStub("JustAC-UIRenderer", true)
                            if UIRenderer and UIRenderer.InvalidateHotkeyCache then
                                UIRenderer.InvalidateHotkeyCache()
                            end
                        end,
                        disabled = fullyDisabled,
                    }),
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
                        -- CVar-backed, not a profile field — stays raw.
                        get = function() return not GetCVarBool("assistedCombatHighlight") end,
                        set = function(_, val)
                            SetCVar("assistedCombatHighlight", val and 0 or 1)
                        end,
                        disabled = function() return fullyDisabled(addon) end,
                    },
                    -- SOUNDS (23-29)
                    soundsHeader = {
                        type = "header",
                        name = L["Sounds"],
                        order = 23,
                    },
                    interruptAlertSound = W.select(addon, "interruptAlertSound", {
                        name = L["Interrupt Alert"], desc = L["Interrupt Alert Sound desc"],
                        order = 24, width = "double", default = "None",
                        dialogControl = "LSM30_Sound",
                        values = function()
                            local LSM = LibStub("LibSharedMedia-3.0", true)
                            return LSM and LSM:HashTable(LSM.MediaType.SOUND) or {}
                        end,
                        disabled = fullyDisabled,
                    }),
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
                    includeHiddenAbilities = W.toggle(addon, "includeHiddenAbilities", {
                        name = L["Include All Available Abilities"], desc = L["Include All Available Abilities desc"],
                        order = 31, width = "full", default = true,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = fullyDisabled,
                    }),
                    showSpellbookProcs = W.toggle(addon, "showSpellbookProcs", {
                        name = L["Insert Procced Abilities"], desc = L["Insert Procced Abilities desc"],
                        order = 32, width = "full", default = false,
                        onSet = function() addon:ForceUpdate() end,
                        disabled = fullyDisabled,
                    }),
                    hideItemAbilities = {
                        type = "toggle",
                        name = L["Allow Item Abilities"],
                        desc = L["Allow Item Abilities desc"],
                        order = 33,
                        width = "full",
                        -- Inverted (toggle shows "Allow", stores "hide") — stays raw.
                        get = function() return not addon.db.profile.hideItemAbilities end,
                        set = function(_, val)
                            addon.db.profile.hideItemAbilities = not val
                            addon:ForceUpdate()
                        end,
                        disabled = function() return fullyDisabled(addon) end,
                    },
                    -- DEFENSIVE QUEUE CONTENT (40-49)
                    defensiveQueueHeader = {
                        type = "header",
                        name = L["Defensive Queue"],
                        order = 40,
                    },
                    showDefensiveProcs = W.toggle(addon, "defensives.showProcs", {
                        name = L["Insert Procced Defensives"], desc = L["Insert Procced Defensives desc"],
                        order = 41, width = "full", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = function(a)
                            local dm = a.db.profile.displayMode or "queue"
                            if dm == "disabled" then return true end
                            local standardEnabled = a.db.profile.defensives.enabled
                            local npo = a.db.profile.nameplateOverlay
                            local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                            return not standardEnabled and not overlayEnabled
                        end,
                    }),
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
                            p.interruptAlertSound = "None"
                            -- Offensive queue content
                            p.includeHiddenAbilities = true
                            p.showSpellbookProcs     = true
                            p.hideItemAbilities      = false
                            -- Defensive queue content
                            p.defensives.showProcs   = true
                            local NPO = LibStub("JustAC-UINameplateOverlay", true)
                            if NPO then NPO.Destroy(addon) end  -- displayMode reset to "queue"
                            addon:UpdateFrameSize()
                            addon:ForceUpdateAll()
                            W.NotifyChange()
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
