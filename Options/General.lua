-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/General - Shared settings that apply to both display surfaces
local General = LibStub:NewLibrary("JustAC-OptionsGeneral", 8)
if not General then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

local fullyDisabled = W.fullyDisabled

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
    -- One flat panel: Disruption, input, and Blizzard UI integration.
    -- Everything visual lives on the Display tab (surfaces + Shared Behavior).
    local tab = {
        type = "group",
        name = L["General"],
        order = 1,
        args = {
                    info = {
                        type = "description",
                        name = L["General Tab desc"],
                        order = 1,
                        fontSize = "medium"
                    },
                    -- (Display Mode retired: each surface is enabled at the top of its own
                    -- tab - Standard Queue / Overlay Queue - via W.SetSurfaceEnabled, which
                    -- still writes the displayMode enum every gate reads.)
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
                    -- DISRUPTION MEMBER 3: dangerous-cast warning. Watches enemy casts like
                    -- the interrupt member, so it lives with the Disruption family.
                    showImportantCastCue = W.toggle(addon, "showImportantCastCue", {
                        name = L["Show Important Cast Warning"], desc = L["Show Important Cast Warning desc"],
                        order = 9.5, width = "double", default = false, disabled = fullyDisabled,
                    }),
                    interruptAlertSound = W.select(addon, "interruptAlertSound", {
                        name = L["Interrupt Alert"], desc = L["Interrupt Alert Sound desc"],
                        order = 8, width = "double", default = "None",
                        dialogControl = "LSM30_Sound",
                        values = function()
                            local LSM = LibStub("LibSharedMedia-3.0", true)
                            return LSM and LSM:HashTable(LSM.MediaType.SOUND) or {}
                        end,
                        -- The sound only plays on the interrupt icon's show transition,
                        -- which never happens with the interrupt reminder off.
                        disabled = function()
                            return fullyDisabled(addon)
                                or (addon.db.profile.interruptMode or "kickPrefer") == "disabled"
                        end,
                    }),
                    -- No separate Test button: the sound picker's own speaker icons play
                    -- through the identical path the real alert uses (LSM fetch +
                    -- PlaySoundFile on the Master channel), so the preview IS the test.
                    -- INPUT (15-19)
                    inputHeader = {
                        type = "header",
                        name = L["Input"],
                        order = 15,
                    },
                    inputPreference = W.select(addon, "inputPreference", {
                        name = L["Input Preference"], desc = L["Input Preference desc"],
                        order = 18, width = "normal", default = "auto",
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
                    gamepadIconStyle = W.select(addon, "gamepadIconStyle", {
                        name = L["Gamepad Icon Style"], desc = L["Gamepad Icon Style desc"],
                        order = 19, width = "normal", default = "xbox",
                        values = { generic = L["Generic"], xbox = L["Xbox"], playstation = L["PlayStation"] },
                        onSet = function() clearScannerCaches() end,
                        -- Applies to both queue and overlay hotkeys; irrelevant on keyboard-only.
                        hidden = function() return addon.db.profile.inputPreference == "keyboard" end,
                        disabled = fullyDisabled,
                    }),
                    -- BLIZZARD UI (19.4-19.56): the game's own on-bar suggestion highlight
                    -- and the Cooldown Manager. GAME-WIDE client settings, not JustAC display
                    -- state: the CDM enable writes the same CVar as Options > Gameplay
                    -- Enhancements, and the hide toggles affect Blizzard's own panels
                    -- everywhere, not just JustAC's display.
                    blizzardUIHeader = {
                        type = "header",
                        name = L["Blizzard UI"],
                        order = 19.3,
                    },
                    -- CVar-backed, not a profile field - stays raw.
                    disableBlizzardHighlight = {
                        type = "toggle",
                        name = L["Disable Blizzard Highlight"],
                        desc = L["Disable Blizzard Highlight desc"],
                        order = 19.4,
                        width = "full",
                        get = function() return not GetCVarBool("assistedCombatHighlight") end,
                        set = function(_, val)
                            SetCVar("assistedCombatHighlight", val and 0 or 1)
                        end,
                        disabled = function() return fullyDisabled(addon) end,
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
        },
    }

    -- ── Situational sets: name the three keybind-toggled groups ─────────────
    -- Membership is set per ability on the Abilities tab; the keys are bound in
    -- Blizzard's Key Bindings UI (Addons > JustAssistedCombat). This is per-spec.
    tab.args.setsHeader = {
        type = "header",
        name = SpellSearch.SpecHeader(L["Situational Sets"]),
        order = 30,
    }
    tab.args.setsDesc = {
        type = "description",
        name = L["Situational Sets desc"],
        order = 30.1,
        fontSize = "medium",
    }
    local SQ = LibStub("JustAC-SpellQueue", true)
    for slot = 1, (SQ and SQ.SET_SLOTS or 3) do
        tab.args["setName" .. slot] = {
            type = "input",
            name = string.format(L["Set Name"], slot),
            desc = L["Set Name desc"],
            order = 30.1 + slot * 0.1,
            width = "normal",
            get = function()
                local sk = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
                local sets = sk and addon.db.profile.situationalSets and addon.db.profile.situationalSets[sk]
                local s = sets and sets[slot]
                return s and s.name or ""
            end,
            set = function(_, val)
                local sk = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
                if not sk then return end
                local p = addon.db.profile
                p.situationalSets = p.situationalSets or {}
                p.situationalSets[sk] = p.situationalSets[sk] or {}
                p.situationalSets[sk][slot] = p.situationalSets[sk][slot] or { spells = {} }
                val = val and val:trim() or ""
                p.situationalSets[sk][slot].name = val ~= "" and val or nil
                local UIR = LibStub("JustAC-UIRenderer", true)
                if UIR and UIR.RefreshSetIndicator then UIR.RefreshSetIndicator(addon) end
                W.NotifyChange()
            end,
        }
    end
    tab.args.setsBindHint = {
        type = "description",
        name = "|cff888888" .. L["Situational Sets Bind Hint"] .. "|r",
        order = 30.9,
        fontSize = "small",
    }

    tab.args.resetHeader, tab.args.resetDefaults =
        W.resetButton(990, L["Reset General desc"], function()
            local p = addon.db.profile
            -- displayMode deliberately untouched: the surface enables live on the
            -- Display tab now, and a General reset must not turn a surface on/off.
            p.interruptMode       = "kickPrefer"
            p.showSootheCue       = true
            p.showImportantCastCue = false
            p.includeFears        = false
            p.gamepadIconStyle    = "xbox"
            p.inputPreference     = "auto"
            p.interruptAlertSound = "None"
            addon:UpdateFrameSize()
            rebuildNPO(addon)  -- interruptMode decides whether the overlay's kick icon exists
            addon:ForceUpdateAll()
            W.NotifyChange()
        end)
    return tab
end
