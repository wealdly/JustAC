-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Defensives - Defensive queue settings tab + spell list management
local Defensives = LibStub:NewLibrary("JustAC-OptionsDefensives", 4)
if not Defensives then return end

local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local SpellLists = LibStub("JustAC-OptionsSpellLists")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- Defensive-behaviour options are dead when neither surface would show a defensive icon.
-- Resolved per call, not at load: Options/Core.lua loads after this file.
local function defensivesUnreachable(addon)
    return LibStub("JustAC-Options", true).AreDefensivesUnreachable(addon)
end

-- Pre-combat buff options -------------------------------------------------------------
-- categories[cat]: false = off, a stat string = preference, nil = auto (optimal/recency).
local PB_STAT_ORDER = { "off", "auto", "haste", "crit", "mastery", "versatility" }

local function pbCategories(addon)
    local pb = addon.db.profile.precombatBuffs
    pb.categories = pb.categories or {}
    return pb.categories
end

-- Apply an options change immediately: drop the buff cache, then rebuild the queues.
local function pbApply(addon)
    local PE = LibStub("JustAC-PrecombatEngine", true)
    if PE and PE.ClearCache then PE.ClearCache() end
    addon:ForceUpdateAll()
end

local function pbDisabled(addon)
    return addon.db.profile.precombatBuffs.enabled == false
end

-- Label an option with the specific bag item it resolves to - "Haste  Flask of Tempered
-- Swiftness" (green, matching the OOC buff glow). Answers "which flask does this pick?".
-- Falls back to the plain label when nothing owned fits that option.
local function pbOptLabel(cat, statPref, base)
    local SDB = LibStub("JustAC-SpellDB", true)
    local entry = SDB and SDB.GetBestOwnedBuff and SDB.GetBestOwnedBuff(cat, statPref)
    local nm = entry and entry.id and (C_Item.GetItemInfo(entry.id))
    return nm and (base .. "  |cff2ecc71" .. nm .. "|r") or base
end

-- Stat-preference dropdown (flask/food): Off / Auto / a secondary stat. Each option shows
-- the specific bag item it resolves to, so the list itself answers "which flask for haste?".
-- withSpeed adds a Speed option - the Speed secondary stat (a rating that always stacks);
-- both food and flask can grant it. Kept opt-in (never surfaces under Auto), since Speed is
-- niche and most specs wouldn't want it auto-picked over their combat stat.
local function pbStatSelect(addon, cat, name, order, withSpeed)
    local sorting = withSpeed
        and { "off", "auto", "haste", "crit", "mastery", "versatility", "speed" }
        or PB_STAT_ORDER
    return {
        type = "select", name = name, order = order, sorting = sorting,
        values = function()
            local vals = {
                off = L["Off"],
                auto = pbOptLabel(cat, nil, L["Auto"]),
                haste = pbOptLabel(cat, "haste", L["Haste"]),
                crit = pbOptLabel(cat, "crit", L["Crit"]),
                mastery = pbOptLabel(cat, "mastery", L["Mastery"]),
                versatility = pbOptLabel(cat, "versatility", L["Versatility"]),
            }
            if withSpeed then vals.speed = pbOptLabel(cat, "speed", L["Speed"]) end
            return vals
        end,
        disabled = function() return pbDisabled(addon) end,
        get = function()
            local v = pbCategories(addon)[cat]
            if v == false then return "off" elseif type(v) == "string" then return v end
            return "auto"
        end,
        set = function(_, val)
            local c = pbCategories(addon)
            if val == "off" then c[cat] = false
            elseif val == "auto" then c[cat] = nil
            else c[cat] = val end
            pbApply(addon)
        end,
    }
end

-- Off / Auto dropdown for categories with no stat choice (augment rune, weapon enchant, xp,
-- speed). The Auto option is labelled with the winning bag item. `defaultOff` flips the
-- default so xp/speed stay off until chosen (stored as an explicit truthy value, since a nil
-- would revert to the AceDB `false` default).
local function pbOnOffSelect(addon, cat, name, order, defaultOff, desc)
    return {
        type = "select", name = name, order = order, desc = desc, sorting = { "off", "auto" },
        values = function()
            return { off = L["Off"], auto = pbOptLabel(cat, nil, L["Auto"]) }
        end,
        disabled = function() return pbDisabled(addon) end,
        get = function()
            local v = pbCategories(addon)[cat]
            if defaultOff then return v == true and "auto" or "off" end
            return v == false and "off" or "auto"
        end,
        set = function(_, val)
            -- Explicit if/else for the default-on branch: `(val == "off") and false or nil`
            -- can never yield false (`x and false` is false, `false or nil` is nil), so
            -- choosing Off on a default-on category wrote nil and read straight back as
            -- Auto - the category could not be turned off. Same trap as the Abilities pins.
            local cats = pbCategories(addon)
            if defaultOff then
                cats[cat] = (val == "auto") or false
            elseif val == "off" then
                cats[cat] = false
            else
                cats[cat] = nil
            end
            pbApply(addon)
        end,
    }
end

--- The current spec's maintenance entry when it runs on a CLOCK (Shield of the Righteous,
--- Ignore Pain, Ironfur), else nil. Bone Shield is eaten by damage and charge-gated buffs
--- never pre-warn, so a warning time or a "needs refreshing" sound means nothing for those.
local function ClockedMaintenance()
    local SDB = LibStub("JustAC-SpellDB", true)
    local e = SDB and SDB.GetMaintenanceDefensive and SDB.GetMaintenanceDefensive()
    if e and e.dur and not e.chargeGated then return e end
    return nil
end

local function ChargeGatedMaintenance()
    local SDB = LibStub("JustAC-SpellDB", true)
    local e = SDB and SDB.GetMaintenanceDefensive and SDB.GetMaintenanceDefensive()
    return (e and e.chargeGated) and true or false
end

--- Returns true when the current spec has a maintenance mitigation buff (tank specs with a
--- curated entry). Brewmaster is a tank but has no entry, so this is spec-level, not role-level.
local function HasMaintenanceDefensive()
    local SDB = LibStub("JustAC-SpellDB", true)
    return (SDB and SDB.GetMaintenanceDefensive and SDB.GetMaintenanceDefensive() ~= nil) or false
end

--- Returns true when the player's class has pet heal defaults.
local function IsPetHealClass()
    local _, pc = UnitClass("player")
    local SDB = LibStub("JustAC-SpellDB", true)
    return SDB and SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc]
end

-- Managed party-health-alert state. Stored in the ACCOUNT-wide saved variable,
-- not a profile: the thing being remembered is the player's own game CVars, and
-- those are client-wide - a per-profile snapshot would hand back the wrong
-- values (or none) after a profile switch.
local function ManagedAlertStore()
    _G.JustACGlobal = _G.JustACGlobal or {}
    _G.JustACGlobal.managedPartyAlert = _G.JustACGlobal.managedPartyAlert or {}
    return _G.JustACGlobal.managedPartyAlert
end

--- Managed setup is ON exactly while we are holding the player's original
--- values (the snapshot IS the record - no separate flag to drift out of sync).
local function ManagedAlertActive()
    local g = _G.JustACGlobal
    local store = g and g.managedPartyAlert
    return (store and type(store.saved) == "table") and true or false
end

--- Hand the alert CVars back if we are managing them. Called when the managed
--- toggle is switched off AND when Group Heals itself is - the settings exist
--- for that feature, so they go home with it.
local function ReleaseManagedAlert(addon)
    if not ManagedAlertActive() then return end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.RestoreManagedPartyAlert then
        BAPI.RestoreManagedPartyAlert(ManagedAlertStore())
        if addon and addon.Print then
            addon:Print("Party health alert restored to your previous settings.")
        end
    end
end

function Defensives.CreateTabArgs(addon)
    local tab = {
        type = "group",
        name = L["Defensives"],
        order = 5,
        childGroups = "tab",
        args = {
            -- ── SUB-TAB 1: GENERAL (the lists, queue behavior, the Sustain slot) ──
            -- Laid out like the Offensive tab's General: the priority first, under the same
            -- spec header, then the settings that act on it.
            general = {
                type = "group",
                name = L["General"],
                order = 1,
                args = {
            spellListGroup = {
                type = "group",
                inline = true,
                name = SpellSearch.SpecHeader(L["Priority Section"]),
                order = 1,
                -- Each list is one call: header, what it is for, the rows, Add, Restore.
                -- The pet lists hide themselves on a class without pets.
                args = SpellLists.Args(addon, "petheal", 110,
                    SpellLists.Args(addon, "petrez", 80,
                        SpellLists.Args(addon, "defensive", 20))),
            },
            -- Its own box, not a third list in the one above: it is not ranked with your
            -- defensives - it only leads when the party is hurting. The same split as the
            -- Offensive tab's Burst box beside its priority.
            groupHelpGroup = {
                type = "group",
                inline = true,
                name = L["Group Help List"],
                order = 2,
                args = SpellLists.Args(addon, "grouphelp", 1),
            },
            -- Defensive queue CONTENT behavior (cross-surface: standard queue + overlay).
            -- Frame/display settings (enable, health bars, display mode, positioning)
            -- live in Standard Queue -> Defensive Display.
            queueContentGroup = {
                type = "group",
                inline = true,
                -- Same name as the Offensive tab's box: both hold how the list is treated.
                name = L["Custom Queue Ordering"],
                order = 5,
                args = {
                    showDefensiveProcs = W.toggle(addon, "defensives.showProcs", {
                        name = L["Insert Procced Defensives"],
                        desc = W.spellDesc("Insert Procced Defensives desc", 34428),  -- Victory Rush
                        order = 1, width = "full", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = defensivesUnreachable,
                    }),
                    -- CONTENT behaviour, not display: it reorders which defensives the queue
                    -- recommends. Lived under Standard Queue -> Defensive Display, which was
                    -- wrong on the tab's own stated split, and worse than untidy - it is read in
                    -- GetDefensiveSpellQueue, the SHARED builder, so it governs the nameplate
                    -- overlay too. An overlay-only player had to open the Standard Queue tab to
                    -- change how their overlay behaves.
                    hideEmergencyUntilLow = W.toggle(addon, "defensives.hideEmergencyUntilLow", {
                        name = L["Hide Emergency Until Low"], desc = L["Hide Emergency Until Low desc"],
                        order = 2, width = "full", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        -- Same cross-surface gate as the toggle above (the old one only knew
                        -- about the standard queue), plus: meaningless in "When Health Low"
                        -- mode, where everything is already gated on health. The overlay has
                        -- its own display mode, so grey out only when EVERY reachable
                        -- defensive surface is health-based.
                        disabled = function(a)
                            if defensivesUnreachable(a) then return true end
                            local p = a.db.profile
                            local npo = p.nameplateOverlay
                            local std = W.SurfaceEnabled(a, "queue") and p.defensives.enabled
                            local ov  = W.SurfaceEnabled(a, "overlay") and npo and npo.showDefensives
                            local stdHB = (p.defensives.displayMode or "always") == "healthBased"
                            local ovHB  = ((npo and npo.defensiveDisplayMode) or "always") == "healthBased"
                            return (not std or stdHB) and (not ov or ovHB)
                        end,
                    }),
                },
            },
            -- SUSTAIN - defensive "position 0". NOT tank-only: the tank mitigation
            -- buff is one member, crowd-control escape is another and works on any
            -- spec, and the pet-heal cue is a third. Only the mitigation-buff TOGGLE
            -- is tank-gated; the section is not.
            -- Shown but greyed off-spec, unlike the class-gated pet lists above, which
            -- hide: spec is switchable, so a Feral still needs to discover it exists.
            sustainGroup = {
                type = "group",
                inline = true,
                name = L["Sustain"],
                order = 10,
                args = {
                    maintenanceInfo = {
                        type = "description",
                        -- The section is universal - crowd-control escape claims this slot on
                        -- ANY spec - so the tank-only caveat belongs to the mitigation-buff
                        -- toggle below, not to the header. Attaching it here told every
                        -- non-tank the whole slot was unavailable to them, which was wrong.
                        name = function()
                            if HasMaintenanceDefensive() then return L["Sustain desc"] end
                            return L["Sustain desc"] .. "\n\n"
                                .. "|cffff9900The mitigation-buff part is tank-only; your escape "
                                .. "from crowd control still uses this slot.|r"
                        end,
                        order = 1,
                        fontSize = "small",
                    },
                    showMaintenanceSlot = W.toggle(addon, "showMaintenanceSlot", {
                        name = L["Maintenance Slot"],
                        desc = L["Maintenance Slot desc"],
                        order = 2, width = "normal", default = true,
                        -- Rebuild, not just refresh: the interrupt icon's cast-aura
                        -- clearance reserves this slot's row at CREATION time, so a
                        -- plain refresh left the aura overlapping (or floating a dead
                        -- row out) until a spec change or reload.
                        onSet = function() addon:UpdateFrameSize(); W.rebuildNPO(addon); addon:ForceUpdateAll() end,
                        -- Dead when every surface is off, or when no defensive display is
                        -- actually showing, since the slot renders inside that cluster.
                        disabled = function(a)
                            return not HasMaintenanceDefensive() or defensivesUnreachable(a)
                        end,
                    }),
                    -- Tuning for the buff above. Each shows only where it means something for
                    -- the spec in hand, and greys with the slot.
                    maintenanceLead = {
                        type = "select",
                        name = L["Maintenance Lead"],
                        desc = L["Maintenance Lead desc"],
                        order = 2.1,
                        width = "normal",
                        hidden = function() return not ClockedMaintenance() end,
                        disabled = function() return addon.db.profile.showMaintenanceSlot == false end,
                        -- Up to a second short of the buff itself: warning for its whole
                        -- duration is not a warning.
                        values = function()
                            local e = ClockedMaintenance()
                            local out = { auto = L["Wait Auto"] }
                            for n = 1, math.min(6, math.floor(((e and e.dur) or 2) - 1)) do
                                out[n] = string.format(L["Seconds Short"], n)
                            end
                            return out
                        end,
                        sorting = function()
                            local e = ClockedMaintenance()
                            local out = { "auto" }
                            for n = 1, math.min(6, math.floor(((e and e.dur) or 2) - 1)) do out[#out + 1] = n end
                            return out
                        end,
                        get = function()
                            local SDB = LibStub("JustAC-SpellDB", true)
                            local sk = SDB and SDB.GetSpecKey and SDB.GetSpecKey()
                            local t = addon.db.profile.maintenanceLead
                            return (sk and t and t[sk]) or "auto"
                        end,
                        set = function(_, v)
                            local SDB = LibStub("JustAC-SpellDB", true)
                            local sk = SDB and SDB.GetSpecKey and SDB.GetSpecKey()
                            if not sk then return end
                            local p = addon.db.profile
                            p.maintenanceLead = p.maintenanceLead or {}
                            if v == "auto" then p.maintenanceLead[sk] = nil else p.maintenanceLead[sk] = v end
                            addon:ForceUpdateAll()
                        end,
                    },
                    maintenanceSound = W.select(addon, "maintenanceSound", {
                        name = L["Maintenance Sound"], desc = L["Maintenance Sound desc"],
                        order = 2.2, width = "normal", default = "None",
                        dialogControl = W.soundControl(),
                        values = W.soundValues,
                        hidden = function() return not HasMaintenanceDefensive() end,
                        disabled = function(a) return a.db.profile.showMaintenanceSlot == false end,
                    }),
                    maintenanceSoundAt = W.select(addon, "maintenanceSoundAt", {
                        name = L["Maintenance Sound At"], desc = L["Maintenance Sound At desc"],
                        order = 2.3, width = "normal", default = "drop",
                        values = {
                            drop = L["Maintenance Sound Drop"],
                            refresh = L["Maintenance Sound Refresh"],
                            both = L["Maintenance Sound Both"],
                        },
                        sorting = { "drop", "refresh", "both" },
                        -- Only a buff with a clock ever reaches "needs refreshing".
                        hidden = function() return not ClockedMaintenance() end,
                        disabled = function(a)
                            local p = a.db.profile
                            return p.showMaintenanceSlot == false or (p.maintenanceSound or "None") == "None"
                        end,
                    }),
                    maintenanceCapGlow = W.toggle(addon, "maintenanceCapGlow", {
                        name = L["Maintenance Cap Glow"], desc = L["Maintenance Cap Glow desc"],
                        order = 2.4, width = "full", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        hidden = function() return not ChargeGatedMaintenance() end,
                        disabled = function(a) return a.db.profile.showMaintenanceSlot == false end,
                    }),
                    -- Group heals: healer specs only. Rides the defensive cluster
                    -- for now, so it lives beside the other cluster content.
                    groupHeals = {
                        type = "toggle",
                        name = "Group Heal Suggestions",
                        desc = "In combat, when a party member drops below Blizzard's party health alert threshold, your group heals - the ones that heal several allies at once - join the defensive queue in priority order. When several allies are low, your strongest ready group cooldown claims the slot beside the queue as an emergency cue.\n\n"
                            .. "Single-target heals are deliberately left out: aiming a heal at a person is your party frames' job. Cast a group heal with no target and it lands on you, still covering the group.\n\n"
                            .. "Renders in the defensive cluster, so that must be enabled for a display.\n\n"
                            .. "Reads each party member's health directly. On a client where that isn't available it falls back to the game's party health alert (Accessibility settings), which only reports that SOMEONE crossed a line - never who. Either way, your party frames stay the place you read the details.",
                        order = 2.5,
                        width = "double",
                        hidden = function()
                            local SpellDB = LibStub("JustAC-SpellDB", true)
                            return not (SpellDB and SpellDB.SpecHasGroupHeals and SpellDB.SpecHasGroupHeals())
                        end,
                        get = function()
                            local h = addon.db.profile.healing
                            return (h and h.enabled) or false
                        end,
                        set = function(_, val)
                            addon.db.profile.healing = addon.db.profile.healing or {}
                            addon.db.profile.healing.enabled = val
                            -- Turning the feature off hands back any game settings
                            -- we changed on its behalf.
                            if not val then ReleaseManagedAlert(addon) end
                            addon:InitializeDefensiveSpells()   -- seed the list on first enable
                            addon:ForceUpdateAll()
                        end,
                        -- Raw AceConfig entry: `disabled` is called with the info
                        -- table, NOT the addon (W.toggle is what passes the addon).
                        -- Capture it instead, or this greys itself permanently.
                        disabled = function() return defensivesUnreachable(addon) end,
                    },
                    -- Both prerequisites are invisible from here (one lives on
                    -- another tab, one in Blizzard's settings), so a greyed or
                    -- silent toggle must say WHICH one is missing.
                    groupHealsStatus = {
                        type = "description",
                        name = function()
                            if defensivesUnreachable(addon) then
                                return "|cffff6600The defensive cluster is off|r - heal suggestions render there. Turn on Defensive Icons for a display (Display tab) first."
                            end
                            local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
                            if not BlizzardAPI then return "" end
                            if BlizzardAPI.IsThresholdGateAvailable and BlizzardAPI.IsThresholdGateAvailable() then
                                return "|cff2ecc71Reading ally health directly|r - no game settings needed."
                            end
                            if BlizzardAPI.IsPartyLowAvailable and BlizzardAPI.IsPartyLowAvailable() then
                                return "|cff2ecc71Using the party health alert|r (fallback) - suggestions can appear."
                            end
                            return "|cffff6600No ally-health signal available|r - direct reading is unavailable on this client and the party health alert is off. Use \"Set Up The Alert For Me\" below, or enable it in Blizzard's Accessibility settings."
                        end,
                        order = 2.6,
                        fontSize = "small",
                        hidden = function()
                            local SpellDB = LibStub("JustAC-SpellDB", true)
                            if not (SpellDB and SpellDB.SpecHasGroupHeals and SpellDB.SpecHasGroupHeals()) then
                                return true
                            end
                            -- Visible while the toggle is on, and while it is greyed
                            -- (that is exactly when the reason is needed).
                            local h = addon.db.profile.healing
                            return not ((h and h.enabled) or defensivesUnreachable(addon))
                        end,
                    },
                    -- The alert lives in Blizzard's Accessibility settings, which is
                    -- most of the reason this feature goes unused. Offer to set it
                    -- up - and say exactly what changes, since these are the
                    -- player's own game settings, not ours.
                    managedAlert = {
                        type = "toggle",
                        name = "Set Up The Alert For Me",
                        desc = "Turn on the game's party health alert the way this feature needs it, without the voice:\n\n"
                            .. "- Combat audio alerts: on\n"
                            .. "- Party health alert: below 50%\n"
                            .. "- Party health alert volume: 0 (silent)\n\n"
                            .. "Your previous values are remembered and put back when you switch this off (or turn Group Heal Suggestions off). "
                            .. "Other combat audio alert categories keep their own settings - if you had them speaking, they still will.",
                        order = 2.7,
                        width = "double",
                        hidden = function()
                            local SpellDB = LibStub("JustAC-SpellDB", true)
                            return not (SpellDB and SpellDB.SpecHasGroupHeals and SpellDB.SpecHasGroupHeals())
                        end,
                        get = function() return ManagedAlertActive() end,
                        set = function(_, val)
                            local BAPI = LibStub("JustAC-BlizzardAPI", true)
                            if val then
                                if not (BAPI and BAPI.ApplyManagedPartyAlert) then return end
                                local ok, pct = BAPI.ApplyManagedPartyAlert(ManagedAlertStore(), 50)
                                if ok then
                                    addon:Print(("Party health alert enabled at below %d%%, silent. Your previous settings are saved."):format(pct or 50))
                                else
                                    addon:Print("Could not change the party health alert right now - try again out of combat.")
                                end
                            else
                                ReleaseManagedAlert(addon)
                            end
                            addon:ForceUpdateAll()
                        end,
                        disabled = function()
                            local h = addon.db.profile.healing
                            return not (h and h.enabled) or defensivesUnreachable(addon)
                        end,
                    },
                    -- Pet heal: hidden rather than greyed for non-pet classes - class is
                    -- not switchable, so there is nothing to discover.
                    showPetHealCue = W.toggle(addon, "showPetHealCue", {
                        name = L["Pet Heal Cue"],
                        desc = L["Pet Heal Cue desc"],
                        order = 3, width = "double", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        hidden = function() return not IsPetHealClass() end,
                    }),
                    -- Stepped in 5s deliberately: the threshold becomes a curve point, and each
                    -- distinct value builds and caches its own curve. A continuous slider would
                    -- mint one per pixel dragged; 5% steps cap it at ~16 for the whole session.
                    petHealThreshold = W.range(addon, "petHealThreshold", {
                        name = L["Pet Heal Threshold"],
                        desc = L["Pet Heal Threshold desc"],
                        order = 4, width = "double", min = 10, max = 90, step = 5, default = 50,
                        onSet = function() addon:ForceUpdateAll() end,
                        hidden = function() return not IsPetHealClass() end,
                        disabled = function(a) return a.db.profile.showPetHealCue == false end,
                    }),
                    -- CROWD-CONTROL ESCAPE - a MEMBER of Sustain, not a rival section. It
                    -- keeps its own header purely as a visual divider - the toggles below
                    -- are its own, and it works on any spec whether or not the
                    -- mitigation-buff toggle is on.
                    ccBreakHeader = {
                        type = "header",
                        name = L["CC Escape"],
                        order = 10,
                    },
                    ccBreakInfo = {
                        type = "description",
                        name = L["CC Escape info"],
                        order = 11,
                        fontSize = "small",
                    },
                    showCCBreak = W.toggle(addon, "showCCBreak", {
                        name = L["CC Break"],
                        desc = L["CC Break desc"],
                        order = 12, width = "normal", default = false,
                        -- Rebuild for the same cast-aura clearance reason as the
                        -- Maintenance Slot toggle above (the slot serves both uses).
                        onSet = function(a) a:UpdateFrameSize(); W.rebuildNPO(a); a:ForceUpdateAll() end,
                    }),
                    -- DRUID ONLY. Roots, snares and slows are broken by shapeshifting, but that
                    -- break is engine behaviour attached to the shift action, not a spell effect,
                    -- so no generated table can find it. The player designates their /cancelform
                    -- macro; the slot then surfaces ITS keybind. A select (not auto-detect) is the
                    -- point: the player owns which macro, so a macro that also casts something is
                    -- their informed choice - and the description shows the body so it is visible.
                    ccBreakMacro = {
                        type = "select",
                        name = L["CC Break Macro"],
                        desc = L["CC Break Macro desc"],
                        order = 13,
                        width = "double",
                        hidden = function()
                            return select(2, UnitClass("player")) ~= "DRUID"
                                or not addon.db.profile.showCCBreak
                        end,
                        values = function()
                            local out = { [""] = NONE or "None" }
                            if not GetMacroInfo then return out end
                            -- Global macros then per-character; names are what the runtime matches
                            -- against action slots, so store names, not shifting indices.
                            for idx = 1, 138 do
                                local name, _, body = GetMacroInfo(idx)
                                if name and body and body:lower():find("/cancelform", 1, true) then
                                    out[name] = name
                                end
                            end
                            return out
                        end,
                        get = function() return addon.db.profile.ccBreakMacro or "" end,
                        set = function(_, val)
                            addon.db.profile.ccBreakMacro = (val ~= "" and val) or nil
                            addon:ForceUpdateAll()
                        end,
                    },
                    ccBreakMacroBody = {
                        type = "description",
                        order = 14,
                        fontSize = "small",
                        hidden = function()
                            return select(2, UnitClass("player")) ~= "DRUID"
                                or not addon.db.profile.showCCBreak
                                or not addon.db.profile.ccBreakMacro
                        end,
                        name = function()
                            local m = addon.db.profile.ccBreakMacro
                            local body
                            if m and GetMacroInfo then
                                body = select(3, GetMacroInfo(m))
                            end
                            if not body then return L["CC Break Macro missing"] end
                            return "|cff888888" .. body:gsub("\n", " | ") .. "|r"
                        end,
                    },
                },
            },
                },
            },
            -- ── SUB-TAB 2: PRE-COMBAT BUFFS ─────────────────────────────────────
            precombat = {
                type = "group",
                name = L["Pre-combat Buffs"],
                order = 2,
                -- Pre-combat suggestions render on the defensive bar; with defensives
                -- disabled they have no surface, so the whole section grays out.
                disabled = function() return not addon.db.profile.defensives.enabled end,
                args = {
                    pbEnabled = {
                        type = "toggle",
                        name = L["Enable Pre-combat Buffs"],
                        desc = L["Pre-combat Buffs desc"],
                        order = 1,
                        width = "full",
                        get = function() return addon.db.profile.precombatBuffs.enabled ~= false end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.enabled = v
                            pbApply(addon)
                        end,
                    },
                    topoffHeal = {
                        type = "toggle",
                        name = L["Health Top-off"],
                        desc = L["Health Top-off desc"],
                        order = 2,
                        width = "full",
                        disabled = function() return pbDisabled(addon) end,
                        get = function() return addon.db.profile.precombatBuffs.topoffHeal == true end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.topoffHeal = v
                            pbApply(addon)
                        end,
                    },
                    -- Only meaningful since the cue moved onto a health curve: before that the
                    -- threshold was honoured solely where an exact health read works (rested
                    -- areas), and degraded to "below full" everywhere else - so a slider would
                    -- have been a lie in the open world. Stepped in 5s for the same reason as
                    -- the pet slider: each distinct value builds and caches its own curve.
                    topoffThreshold = {
                        type = "range",
                        name = L["Health Top-off Threshold"],
                        desc = L["Health Top-off Threshold desc"],
                        order = 2.1, width = "full",
                        min = 50, max = 95, step = 5,
                        disabled = function()
                            return pbDisabled(addon)
                                or addon.db.profile.precombatBuffs.topoffHeal ~= true
                        end,
                        get = function() return addon.db.profile.precombatBuffs.topoffThreshold or 90 end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.topoffThreshold = v
                            pbApply(addon)
                        end,
                    },
                    stealthReminder = {
                        type = "toggle",
                        name = L["Stealth Reminder"],
                        desc = L["Stealth Reminder desc"],
                        order = 3,
                        width = "full",
                        hidden = function()
                            local PE = LibStub("JustAC-PrecombatEngine", true)
                            local entry = PE and PE.STEALTH_REMINDER[select(2, UnitClass("player"))]
                            return not entry or (entry.spec and GetSpecialization() ~= entry.spec)
                        end,
                        disabled = function() return pbDisabled(addon) end,
                        get = function() return addon.db.profile.precombatBuffs.stealth ~= false end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.stealth = v
                            pbApply(addon)
                        end,
                    },
                    flask = pbStatSelect(addon, "flask", L["Flask"], 10, true),
                    food = pbStatSelect(addon, "food", L["Food"], 11, true),
                    augmentRune = pbOnOffSelect(addon, "augmentRune", L["Augment Rune"], 12, false),
                    weaponEnchant = pbOnOffSelect(addon, "weaponEnchant", L["Weapon Enchant"], 13, false),
                    xp = pbOnOffSelect(addon, "xp", L["XP"], 15, true, L["XP desc"]),
                },
            },
        },
    }
    -- One reset for the whole Defensive Queue tab (scalar settings across all
    -- sub-tabs; the priority lists are per-spec seeded and stay untouched).
    tab.args.general.args.resetHeader, tab.args.general.args.resetDefaults =
        W.resetButton(990, L["Reset Defensives desc"], function()
            local p = addon.db.profile
            local def = p.defensives
            def.showProcs             = true
            def.hideEmergencyUntilLow = true
            def.emergencyPotionChoice = nil
            def.emergencyPotionWaitBelow = nil
            p.showMaintenanceSlot = true
            p.maintenanceSound    = "None"
            p.maintenanceSoundAt  = "drop"
            p.maintenanceCapGlow  = true
            if p.maintenanceLead then wipe(p.maintenanceLead) end
            p.showPetHealCue      = true
            p.petHealThreshold    = 50
            p.showCCBreak         = false
            p.ccBreakMacro        = nil
            local pb = p.precombatBuffs
            pb.enabled         = true
            pb.topoffHeal      = false
            pb.topoffThreshold = 90
            pb.stealth         = true
            -- Fresh table: assigning the defaults one would alias it into the profile.
            pb.categories      = { xp = false }
            pbApply(addon)
            W.NotifyChange()
        end)
    return tab
end
