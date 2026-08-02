-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/General - Shared settings that apply to both display surfaces
local General = LibStub:NewLibrary("JustAC-OptionsGeneral", 8)
if not General then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- displayMode == "disabled" turns off every surface; most controls gate on it.
local function fullyDisabled(addon)
    return (addon.db.profile.displayMode or "queue") == "disabled"
end

local rebuildNPO = W.rebuildNPO

--- Push the per-panel cosmetic hides to the tracker. Shared by all four toggles.
local function ApplyCdmVisibility(a)
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    if MT and MT.ApplyViewerVisibility then MT.ApplyViewerVisibility(a.db.profile) end
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

    local tab = {
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
                    -- INTERRUPT (6-9) - own section; not a shared-behavior setting.
                    -- Order 7.5 is reserved for the future "Context Aware" CC toggle.
                    interruptHeader = {
                        type = "header",
                        name = L["Disruption"],
                        order = 6,
                    },
                    disruptionInfo = {
                        type = "description",
                        name = L["Disruption desc"],
                        order = 6.5,
                        fontSize = "small",
                    },
                    interruptMode = W.select(addon, "interruptMode", {
                        name = L["Interrupt Mode"], desc = L["Interrupt Mode desc"],
                        order = 7, width = "double", default = "kickPrefer",
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
                    includeFears = W.toggle(addon, "includeFears", {
                        name = L["Include Fears"], desc = L["Include Fears desc"],
                        order = 7.5, width = "double", default = false,
                        disabled = function()
                            local m = addon.db.profile.interruptMode or "kickPrefer"
                            -- Only relevant when CC can be suggested (kickPrefer / ccPrefer).
                            return fullyDisabled(addon) or m == "disabled" or m == "kickOnly"
                        end,
                    }),
                    -- DISRUPTION MEMBER 2: enrage cleanse. Ordered AFTER the interrupt member and
                    -- its alert sound, so the panel reads one member at a time rather than
                    -- interleaving a second feature into the interrupt's own settings.
                    showSootheCue = W.toggle(addon, "showSootheCue", {
                        name = L["Show Soothe Cue"],
                        desc = W.spellDesc("Show Soothe Cue desc", 2908),  -- Soothe
                        order = 8.5, width = "double", default = true,
                        -- Deliberately NOT disabled when the interrupt reminder is off: the two
                        -- share an icon but are independent choices, and the slot is now built
                        -- for either one. Recreate the frames, since this decides whether that
                        -- slot exists at all.
                        onSet = function() addon:UpdateFrameSize(); rebuildNPO(addon) end,
                        disabled = fullyDisabled,
                    }),
                    interruptAlertSound = W.select(addon, "interruptAlertSound", {
                        name = L["Interrupt Alert"], desc = L["Interrupt Alert Sound desc"],
                        order = 8, width = "double", default = "None",
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
                        order = 9,
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
                    -- SHARED BEHAVIOR (10-19)
                    behaviorHeader = {
                        type = "header",
                        name = L["Shared Behavior"],
                        order = 10,
                    },
                    showFlash = W.toggle(addon, "showFlash", {
                        name = L["Show Key Press Flash"], desc = L["Show Key Press Flash desc"],
                        order = 12, width = "normal", default = true, disabled = fullyDisabled,
                    }),
                    greyOutWhileCasting = W.toggle(addon, "greyOutWhileCasting", {
                        name = L["Grey Out While Casting"], desc = L["Grey Out While Casting desc"],
                        order = 13, width = "normal", default = true, disabled = fullyDisabled,
                    }),
                    greyOutWhileChanneling = W.toggle(addon, "greyOutWhileChanneling", {
                        name = L["Grey Out While Channeling"], desc = L["Grey Out While Channeling desc"],
                        order = 14, width = "normal", default = true, disabled = fullyDisabled,
                    }),
                    showUsabilityTint = W.toggle(addon, "showUsabilityTint", {
                        name = L["Show Usability Tint"], desc = L["Show Usability Tint desc"],
                        order = 15, width = "normal", default = true, disabled = fullyDisabled,
                    }),
                    showRangeTint = W.toggle(addon, "showRangeTint", {
                        name = L["Show Range Tint"], desc = L["Show Range Tint desc"],
                        order = 16, width = "normal", default = true, disabled = fullyDisabled,
                    }),
                    showImportantCastCue = W.toggle(addon, "showImportantCastCue", {
                        name = L["Show Important Cast Warning"], desc = L["Show Important Cast Warning desc"],
                        order = 16.5, width = "normal", default = false, disabled = fullyDisabled,
                    }),
                    showCastingHighlight = W.toggle(addon, "showCastingHighlight", {
                        name = L["Show Casting Highlight"], desc = L["Show Casting Highlight desc"],
                        order = 17, width = "normal", default = true, disabled = fullyDisabled,
                    }),
                    -- ABILITY MARKERS (17.1-17.2) - shared: both cues render on the offensive and defensive queues.
                    markMoveCastable = {
                        type = "toggle",
                        name = L["Mark Move-Castable Spells"], desc = L["Mark Move-Castable Spells desc"],
                        order = 17.1, width = "normal",
                        -- Raw get/set: no static default, because the default is
                        -- per-spec (see UIRenderer.MoveCastDotEnabled).
                        get = function()
                            local R = LibStub("JustAC-UIRenderer", true)
                            return (R and R.MoveCastDotEnabled and R.MoveCastDotEnabled(addon.db.profile)) or false
                        end,
                        set = function(_, val)
                            addon.db.profile.showMoveCastDot = val
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return fullyDisabled(addon) end,
                    },
                    showOffGcdDot = W.toggle(addon, "showOffGcdDot", {
                        name = "Mark Off-Global-Cooldown Spells",
                        desc = "Show an amber marker in the lower-left corner of abilities that don't "
                            .. "trigger the global cooldown - you can cast them and move straight "
                            .. "on to the next suggestion without waiting.\n\n"
                            .. "Applies to the offensive and defensive queues alike.",
                        order = 17.2, width = "normal", default = false,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = fullyDisabled,
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
                    -- COOLDOWN MANAGER (19.5-19.56). Lives here, not under a defensive
                    -- sub-section, because it is a GAME-WIDE client setting: the enable toggle
                    -- writes the same CVar as Options > Gameplay Enhancements, and the hide
                    -- toggles affect Blizzard's own panels everywhere, not just JustAC's display.
                    -- The tank maintenance slot is the feature that benefits most, but it is not
                    -- the scope of the setting.
                    cooldownManagerHeader = {
                        type = "header",
                        name = L["Cooldown Manager"],
                        order = 19.5,
                    },
                    cooldownManagerEnable = W.toggle(addon, "cooldownManagerEnable", {
                        name = L["Enable Cooldown Manager"],
                        desc = L["Enable Cooldown Manager desc"],
                        order = 19.51, width = "double", default = false,
                        onSet = function(a)
                            local MT = LibStub("JustAC-MaintenanceTracker", true)
                            if MT and MT.SetCooldownManagerEnabled then
                                local on = a.db.profile.cooldownManagerEnable and true or false
                                if not MT.SetCooldownManagerEnabled(on) then
                                    a:Print(L["Cooldown Manager combat warning"])
                                end
                                -- Opting in also warns about any panel left on Edit Mode's
                                -- "Hidden", which otherwise reads to us as the system being off.
                                if on and MT.ApplyViewerVisibility then
                                    MT.ApplyViewerVisibility(a.db.profile)
                                end
                            end
                        end,
                        -- Deliberately NOT gated on having a maintenance buff. It used to be,
                        -- back when this lived in a tank-branded defensive section - but it
                        -- writes a GAME-WIDE CVar, so greying it for non-tanks told most of the
                        -- player base that a client setting was unavailable to them, and took
                        -- the hide-panel toggles below down with it (they are gated on this
                        -- being on). Any spec may legitimately want Blizzard's panels on, or on
                        -- and hidden; only the extra precision it buys is tank-specific.
                    }),
                    -- Cosmetic only, per panel. Each stays SHOWN - that is what keeps its aura
                    -- data live and readable - and merely becomes invisible and click-through.
                    -- We never enable a panel the player disabled; this only tidies visible ones.
                    -- RAW entry, not W.toggle: buildBase only injects `addon` into hidden/disabled
                    -- for widgets it builds. A raw table's callback receives AceConfig's `info`,
                    -- so taking an `a` argument here and indexing a.db throws mid-render - which
                    -- breaks the whole panel's layout, scrollbar included. Close over `addon`.
                    hideCdmHeader = {
                        type = "description", order = 19.52, fontSize = "small",
                        name = L["Hide Panels desc"],
                        hidden = function() return not addon.db.profile.cooldownManagerEnable end,
                    },
                    hideCdmEssential = W.toggle(addon, "hideCdmEssential", {
                        name = L["Hide Essential"], order = 19.53, width = "normal", default = false,
                        onSet = ApplyCdmVisibility,
                        hidden = function(a) return not a.db.profile.cooldownManagerEnable end,
                    }),
                    hideCdmUtility = W.toggle(addon, "hideCdmUtility", {
                        name = L["Hide Utility"], order = 19.54, width = "normal", default = false,
                        onSet = ApplyCdmVisibility,
                        hidden = function(a) return not a.db.profile.cooldownManagerEnable end,
                    }),
                    hideCdmTrackedBuff = W.toggle(addon, "hideCdmTrackedBuff", {
                        name = L["Hide Tracked Buffs"], order = 19.55, width = "normal", default = false,
                        onSet = ApplyCdmVisibility,
                        hidden = function(a) return not a.db.profile.cooldownManagerEnable end,
                    }),
                    hideCdmTrackedBar = W.toggle(addon, "hideCdmTrackedBar", {
                        name = L["Hide Tracked Bars"], order = 19.56, width = "normal", default = false,
                        onSet = ApplyCdmVisibility,
                        hidden = function(a) return not a.db.profile.cooldownManagerEnable end,
                    }),
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
                        -- CVar-backed, not a profile field - stays raw.
                        get = function() return not GetCVarBool("assistedCombatHighlight") end,
                        set = function(_, val)
                            SetCVar("assistedCombatHighlight", val and 0 or 1)
                        end,
                        disabled = function() return fullyDisabled(addon) end,
                    },
                },
            },
            -- ── SUB-TAB 2: ICON LABELS ──────────────────────────────
            iconLabels = labelsTab,
            -- ── SUB-TAB 3: HOTKEY OVERRIDES ─────────────────────────
            hotkeyOverrides = hotkeysTab,
        },
    }
    tab.args.settings.args.resetHeader, tab.args.settings.args.resetDefaults =
        W.resetButton(990, L["Reset General desc"], function()
            local p = addon.db.profile
            p.displayMode         = "queue"
            p.interruptMode       = "kickPrefer"
            p.showSootheCue       = true
            p.showFlash           = true
            p.showUsabilityTint   = true
            p.showRangeTint       = true
            p.showCastingHighlight = true
            p.greyOutWhileCasting = true
            p.greyOutWhileChanneling = true
            p.gamepadIconStyle    = "xbox"
            p.inputPreference     = "auto"
            p.interruptAlertSound = "None"
            local NPO = LibStub("JustAC-UINameplateOverlay", true)
            if NPO then NPO.Destroy(addon) end  -- displayMode reset to "queue"
            addon:UpdateFrameSize()
            addon:ForceUpdateAll()
            W.NotifyChange()
        end)
    return tab
end
