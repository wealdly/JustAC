-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Offensive - Offensive tab (queue content, custom priority, burst triggers, gap closers)
local Offensive = LibStub:NewLibrary("JustAC-OptionsOffensive", 3)
if not Offensive then return end

local SpellLists = LibStub("JustAC-OptionsSpellLists")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

local fullyDisabled = W.fullyDisabled

-- Offensive queue CONTENT (what abilities the rotation surfaces). Cross-surface (affects the
-- standard queue and the nameplate overlay alike), so it lives with the other offensive
-- content tools here rather than a per-surface display panel. Moved out of the General tab.
-- Rendered as an inline group at the TOP of the Offensive "General" sub-tab, above the
-- custom-priority (Custom Queue) controls it now shares that tab with.
local function queueContentGroup(addon)
    return {
        type = "group",
        inline = true,
        -- Below the priority list: the list is what the tab is for, and these are
        -- settings you touch once.
        name = L["Queue Content"],
        order = 30,
        args = {
            includeHiddenAbilities = W.toggle(addon, "includeHiddenAbilities", {
                name = L["Include All Available Abilities"], desc = L["Include All Available Abilities desc"],
                order = 1, width = "normal", default = true,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
            showSpellbookProcs = W.toggle(addon, "showSpellbookProcs", {
                name = L["Insert Procced Abilities"], desc = L["Insert Procced Abilities desc"],
                order = 2, width = "normal", default = true,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
            hideItemAbilities = {
                type = "toggle",
                name = L["Allow Item Abilities"],
                desc = L["Allow Item Abilities desc"],
                order = 3,
                width = "normal",
                -- Inverted (toggle shows "Allow", stores "hide") - stays raw.
                get = function() return not addon.db.profile.hideItemAbilities end,
                set = function(_, val)
                    addon.db.profile.hideItemAbilities = not val
                    addon:ForceUpdate()
                end,
                disabled = function() return fullyDisabled(addon) end,
            },
            -- The switch-target arrow is not offered: it never fired reliably, because
            -- "the game re-recommended a DoT that is already up" turned out not to mean
            -- "spread it" on every spec. The engine still honours profile.showDotSpreadArrow
            -- for anyone who set it before; nothing sets it now.
            casterFiller = {
                type = "toggle",
                name = "Caster Filler (This Spec)",
                desc = "Suppress melee-weave suggestions - melee abilities and form shifts - from this healer spec's damage filler. For healers who stay at range; Blizzard's own recommendation still adapts to where you stand.",
                order = 6,
                width = "normal",
                -- Healer specs only; the melee-weave question doesn't exist elsewhere.
                hidden = function()
                    local spec = GetSpecialization()
                    return not (spec and GetSpecializationRole(spec) == "HEALER")
                end,
                get = function()
                    local SpellDB = LibStub("JustAC-SpellDB", true)
                    local key = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
                    local cf = addon.db.profile.casterFiller
                    return (key and cf and cf[key]) or false
                end,
                set = function(_, val)
                    local SpellDB = LibStub("JustAC-SpellDB", true)
                    local key = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
                    if not key then return end
                    addon.db.profile.casterFiller = addon.db.profile.casterFiller or {}
                    addon.db.profile.casterFiller[key] = val or nil
                    addon:ForceUpdate()
                end,
                disabled = function() return fullyDisabled(addon) end,
            },
        },
    }
end

-- Burst-ready cue triggers. Cross-surface queue content, so it lives with the
-- other content tools on the General sub-tab. The list shows what is in effect: your
-- own triggers, else theorycraft's burst-window markers, else curated class defaults.
-- Editing it makes it yours (Options/SpellLists.lua); Use Defaults hands it back.
local function burstTriggerGroup(addon)
    local group = {
        type = "group",
        inline = true,
        name = L["Burst"],
        order = 40,
        args = {
            -- The cue and the triggers are one feature: the triggers say WHICH cooldowns,
            -- the cue is how they announce themselves. Split across two groups, the cue read
            -- as an unrelated queue setting.
            burstCueGlow = W.toggle(addon, "burstCueGlow", {
                name = L["Burst Ready Cue"], desc = L["Burst Ready Cue desc"],
                order = 0.5, width = "full", default = true,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
        },
    }
    SpellLists.Args(addon, "burst", 1, group.args)
    -- Where the list on screen comes from, since it can be any of three.
    group.args.burstSource = {
        type = "description",
        name = function()
            local SQ = LibStub("JustAC-SpellQueue", true)
            -- Guard, THEN call: `SQ and SQ.GetBurstTriggerInfo()` keeps only the first
            -- return, and the source is the second.
            local source
            if SQ and SQ.GetBurstTriggerInfo then source = select(2, SQ.GetBurstTriggerInfo()) end
            return string.format(L["Burst Triggers From"], L["Burst Source " .. (source or "curated")])
        end,
        order = 1.15,
        fontSize = "small",
    }
    return group
end

function Offensive.CreateTabArgs(addon)
    local CustomQueue = LibStub("JustAC-OptionsCustomQueue", true)
    local GapClosers = LibStub("JustAC-OptionsGapClosers", true)

    -- "General" sub-tab = the queue-content toggles + the custom-priority (Custom Queue)
    -- controls, merged into one panel (the Defensives tab leads with a General sub-tab
    -- the same way). We reuse the Custom Queue tab as the base and inject the content group
    -- at the top; the arg KEY stays "customQueue" so UpdateCustomQueueOptions still resolves it.
    local generalTab = (CustomQueue and CustomQueue.CreateTabArgs) and CustomQueue.CreateTabArgs(addon)
    if generalTab then
        generalTab.name = L["General"]
        generalTab.order = 1
        generalTab.args.queueContentGroup = queueContentGroup(addon)
        generalTab.args.burstTriggerGroup = burstTriggerGroup(addon)
    else
        -- Fallback if the Custom Queue module is unavailable: still surface the toggles.
        generalTab = { type = "group", name = L["General"], order = 1,
                       args = { queueContentGroup = queueContentGroup(addon) } }
    end

    local tab = {
        type = "group",
        name = L["Offensive"],
        order = 4,
        childGroups = "tab",
        args = {
            -- Sub-tab 1: General (queue content + custom priority)
            customQueue = generalTab,
            -- Sub-tab 2: Gap-Closers
            -- (The Blacklist moved to the Abilities tab as the Visibility setting.)
            gapClosers = (GapClosers and GapClosers.CreateTabArgs) and GapClosers.CreateTabArgs(addon) or nil,
        },
    }
    return tab
end

