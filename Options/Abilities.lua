-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Abilities - one per-ability card over the existing stores.
--
-- Lists answer WHEN (order, on their own tabs); this card answers HOW: visibility
-- (the blacklist), pins, item settings, list membership, and the hotkey override,
-- all for one searched ability. The card is a VIEW - it reads and writes the same
-- nine stores the engines already consume; no storage moved and no migration.
local Abilities = LibStub:NewLibrary("JustAC-OptionsAbilities", 1)
if not Abilities then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Session-only selection; the card is rebuilt around it.
local selectedID = nil

local function GetSpecKey()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
end

local function NotifyChange()
    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
end

-------------------------------------------------------------------------------
-- Store accessors (create-on-write; nil-safe on read)
-------------------------------------------------------------------------------
local function BlacklistTable(profile, create)
    local specKey = GetSpecKey()
    if not specKey then return nil end
    if not profile.blacklistedSpells then
        if not create then return nil end
        profile.blacklistedSpells = {}
    end
    if not profile.blacklistedSpells[specKey] then
        if not create then return nil end
        profile.blacklistedSpells[specKey] = {}
    end
    return profile.blacklistedSpells[specKey]
end

local function SpellSettings(profile, id, create)
    local d = profile.defensives
    if not d then return nil end
    if not d.spellSettings then
        if not create then return nil end
        d.spellSettings = {}
    end
    if not d.spellSettings[id] then
        if not create then return nil end
        d.spellSettings[id] = {}
    end
    return d.spellSettings[id]
end

-- Overt per-spec declaration: "I want the game's assist itself to skip this ability"
-- (which the engine only does for spells with no visible action-bar button). A separate
-- store from the blacklist VALUE deliberately: the blacklist says "don't show it to me",
-- this says "and I intend it off my bars" - a player may hide an ability from the queue
-- while keeping it on bars for manual presses, and the two intents must not be conflated
-- (that conflation is exactly what made the earlier bar hint a false-positive nag).
local function EngineHideIntent(profile, create)
    local specKey = GetSpecKey()
    if not specKey then return nil end
    if not profile.engineHideIntent then
        if not create then return nil end
        profile.engineHideIntent = {}
    end
    if not profile.engineHideIntent[specKey] then
        if not create then return nil end
        profile.engineHideIntent[specKey] = {}
    end
    return profile.engineHideIntent[specKey]
end

local function ItemSettings(profile, itemID, create)
    local d = profile.defensives
    if not d then return nil end
    if not d.itemSettings then
        if not create then return nil end
        d.itemSettings = {}
    end
    if not d.itemSettings[itemID] then
        if not create then return nil end
        d.itemSettings[itemID] = {}
    end
    return d.itemSettings[itemID]
end

-------------------------------------------------------------------------------
-- List descriptors for the membership section. resolve() returns the live list
-- table for the current spec (nil = list unavailable right now); after() runs
-- the same refresh chain that list's own tab uses. fits(id, roleFam) filters the
-- row by ability type - an ability already IN a list always shows its row, so
-- Remove can never be filtered away. roleFam is "offensive"/"defensive"/"both"
-- from SpellSearch.RoleTag ("both" covers Disruption, Utility, and items).
-------------------------------------------------------------------------------
local function FitsOffense(_, roleFam) return roleFam ~= "defensive" end
local function FitsDefense(_, roleFam) return roleFam ~= "offensive" end

-- Gap-closers: only the spec's curated movement spells qualify.
local function FitsGapCloser(id)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = GetSpecKey()
    local defaults = SpellDB and specKey and SpellDB.CLASS_GAPCLOSER_DEFAULTS
        and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
    if not defaults then return false end
    for _, sid in ipairs(defaults) do
        if sid == id then return true end
    end
    return false
end

-- Burst triggers: offensive-family with a real cooldown - the spec's curated
-- trigger defaults qualify outright; anything else needs a base CD >= 30s.
local function FitsBurstTrigger(id, roleFam)
    if roleFam == "defensive" then return false end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = GetSpecKey()
    local defaults = SpellDB and specKey and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS
        and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
    if defaults then
        for _, sid in ipairs(defaults) do
            if sid == id then return true end
        end
    end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local cd = BlizzardAPI and BlizzardAPI.GetBaseCooldownSeconds
        and BlizzardAPI.GetBaseCooldownSeconds(id)
    return (cd or 0) >= 30
end

local LISTS = {
    {
        key = "custom", nameKey = "Custom Queue Spells",
        spellsOnly = false, fits = FitsOffense,
        resolve = function(profile)
            local specKey = GetSpecKey()
            local cq = specKey and profile.customQueue and profile.customQueue[specKey]
            if not (cq and cq.enabled) then return nil, L["Custom Priority Disabled"] end
            return cq.spells
        end,
        after = function(addon)
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
            local CQ = LibStub("JustAC-OptionsCustomQueue", true)
            if CQ and CQ.UpdateCustomQueueOptions then CQ.UpdateCustomQueueOptions(addon) end
            addon:ForceUpdateAll()
        end,
    },
    {
        key = "defensive", nameKey = "Defensive Priority List",
        spellsOnly = false, listField = "defensiveSpells", fits = FitsDefense,
    },
    {
        key = "gap", nameKey = "Gap-Closers",
        spellsOnly = true, fits = FitsGapCloser,
        resolve = function(profile)
            local specKey = GetSpecKey()
            local gc = specKey and profile.gapClosers and profile.gapClosers.classSpells
            return gc and gc[specKey]
        end,
        after = function(addon)
            local GCE = LibStub("JustAC-GapCloserEngine", true)
            if GCE and GCE.InvalidateGapCloserCache then GCE.InvalidateGapCloserCache() end
            local GC = LibStub("JustAC-OptionsGapClosers", true)
            if GC and GC.UpdateGapCloserOptions then GC.UpdateGapCloserOptions(addon) end
            addon:ForceUpdate()
        end,
    },
    {
        key = "burst", nameKey = "Burst Triggers",
        spellsOnly = true, fits = FitsBurstTrigger,
        -- READ the EFFECTIVE list (custom override, else SimC, else curated) so the
        -- card's status and Add/Remove label reflect what actually drives the burst
        -- cue. The old resolver returned the raw override table, which is EMPTY for
        -- most players - so a live SimC trigger read "not in list", and pressing Add
        -- appended one entry to the empty override, which then WON outright and
        -- silently discarded the whole SimC/curated set (SpellQueue.ResolveBurstTriggers
        -- treats non-empty override as authoritative). Audit-found, 2026-08-16.
        resolve = function(profile)
            local specKey = GetSpecKey()
            if not specKey then return nil end
            local SQ = LibStub("JustAC-SpellQueue", true)
            local list = SQ and SQ.GetBurstTriggerInfo and SQ.GetBurstTriggerInfo()
            return list or (profile.burstTriggers and profile.burstTriggers[specKey]) or {}
        end,
        -- EDIT path: materialise the effective list into the override before the first
        -- edit, so Add/Remove refine what the player already sees instead of replacing
        -- it wholesale. Idempotent once the override exists.
        ensure = function(profile)
            local specKey = GetSpecKey()
            if not specKey then return nil end
            profile.burstTriggers = profile.burstTriggers or {}
            local ov = profile.burstTriggers[specKey]
            if not ov or #ov == 0 then
                local SQ = LibStub("JustAC-SpellQueue", true)
                local eff = SQ and SQ.GetBurstTriggerInfo and SQ.GetBurstTriggerInfo()
                ov = {}
                for i = 1, (eff and #eff or 0) do ov[i] = eff[i] end
                profile.burstTriggers[specKey] = ov
            end
            return ov
        end,
        after = function(addon)
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.InvalidateBurstTriggers then SQ.InvalidateBurstTriggers() end
            local Off = LibStub("JustAC-OptionsOffensive", true)
            if Off and Off.UpdateBurstTriggerOptions then Off.UpdateBurstTriggerOptions(addon) end
            addon:ForceUpdate()
        end,
    },
    {
        key = "petrez", nameKey = "Pet Rez/Summon Priority List",
        spellsOnly = true, listField = "petRezSpells", petOnly = true, fits = FitsDefense,
    },
    {
        key = "petheal", nameKey = "Pet Heal Priority List",
        spellsOnly = false, listField = "petHealSpells", petOnly = true, fits = FitsDefense,
    },
}

-- Shared resolve/after for the three defensive-family lists (listField set above).
local function ResolveClassList(profile, listField)
    local specKey = GetSpecKey()
    local cs = specKey and profile.defensives and profile.defensives.classSpells
        and profile.defensives.classSpells[specKey]
    return cs and cs[listField]
end

-- Create-on-demand twin of ResolveClassList, for the Add/Remove buttons. The read-only
-- form returns nil until the spec has been given that list - and the button was disabled
-- on nil, so Add was greyed out precisely on the lists that were empty, with nothing to
-- say why (a fresh Hunter's pet lists). Seeds the same way DefensiveEngine does at login
-- (spec key, then class-key fallback for pre-spec data; defaults copied in), so a list
-- born here is indistinguishable from one born at login.
local function EnsureClassList(profile, listField)
    local specKey = GetSpecKey()
    if not (specKey and profile.defensives) then return nil end
    local def = profile.defensives
    def.classSpells = def.classSpells or {}
    def.classSpells[specKey] = def.classSpells[specKey] or {}
    local cs = def.classSpells[specKey]
    if not cs[listField] then
        local DE = LibStub("JustAC-DefensiveEngine", true)
        local SpellDB = LibStub("JustAC-SpellDB", true)
        local defaultsKey = DE and DE.DefaultsKeyForList and DE.DefaultsKeyForList(listField)
        local _, playerClass = UnitClass("player")
        local defaults = defaultsKey and SpellDB and SpellDB[defaultsKey]
            and SpellDB.ResolveDefaults and SpellDB.ResolveDefaults(SpellDB[defaultsKey], specKey, playerClass)
        local list = {}
        for i = 1, (defaults and #defaults or 0) do list[i] = defaults[i] end
        cs[listField] = list
    end
    return cs[listField]
end

-- Same for the gap-closer list. An EMPTY stored list is read by the engine as "use the
-- defaults", so a bare {} would make Remove a no-op (the removed spell comes straight
-- back from the defaults). Materialise the effective defaults first, then edit those.
local function EnsureGapCloserList(profile)
    local specKey = GetSpecKey()
    if not specKey then return nil end
    profile.gapClosers = profile.gapClosers or {}
    profile.gapClosers.classSpells = profile.gapClosers.classSpells or {}
    local cs = profile.gapClosers.classSpells
    if not cs[specKey] or #cs[specKey] == 0 then
        local SpellDB = LibStub("JustAC-SpellDB", true)
        local defaults = SpellDB and SpellDB.CLASS_GAPCLOSER_DEFAULTS
            and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
        local list = {}
        for i = 1, (defaults and #defaults or 0) do list[i] = defaults[i] end
        cs[specKey] = list
    end
    return cs[specKey]
end

local function AfterDefensiveList(addon)
    local Def = LibStub("JustAC-OptionsDefensives", true)
    if Def and Def.UpdateDefensivesOptions then Def.UpdateDefensivesOptions(addon) end
    local DE = LibStub("JustAC-DefensiveEngine", true)
    if DE and DE.RegisterDefensivesForTracking then DE.RegisterDefensivesForTracking(addon) end
    addon:ForceUpdateAll()
end

local function IsPetClass()
    local _, pc = UnitClass("player")
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.ClassHasPetDefaults and SpellDB.ClassHasPetDefaults(pc)
end

local function ListIndexOf(list, id)
    if not list then return nil end
    for i, v in ipairs(list) do
        if v == id then return i end
    end
    return nil
end

--- Wipe every customization this tab can set for one ability: visibility, pins, item
--- settings, hotkey override, and its entries in every priority list. ONE implementation
--- shared by the card's Clear button and the index rows' Remove buttons - two copies of
--- "everything" would drift the moment a new setting was added to one of them.
local function ClearAbility(addon, profile, id)
    local isItem = id < 0
    local bl = BlacklistTable(profile, false)
    if bl then bl[id] = nil end
    if profile.defensives then
        if profile.defensives.spellSettings then profile.defensives.spellSettings[id] = nil end
        if isItem and profile.defensives.itemSettings then profile.defensives.itemSettings[-id] = nil end
    end
    if profile.hotkeyOverrides then
        profile.hotkeyOverrides[id] = nil
        addon:InvalidateCaches({hotkeys = true})
    end
    do
        local intent = EngineHideIntent(profile, false)
        if intent then intent[id] = nil end
    end
    -- Situational-set membership for this spec.
    do
        local specKey = GetSpecKey()
        local sets = specKey and profile.situationalSets and profile.situationalSets[specKey]
        if sets then
            for _, s in pairs(sets) do
                if type(s) == "table" and type(s.spells) == "table" then s.spells[id] = nil end
            end
            local UIR = LibStub("JustAC-UIRenderer", true)
            if UIR and UIR.RefreshSetIndicator then UIR.RefreshSetIndicator(addon) end
        end
    end
    -- Pins live in the rotation setup cache (see pinToggle) - clearing them needs the
    -- same invalidation or the old pin keeps applying until the next list change.
    local SQ = LibStub("JustAC-SpellQueue", true)
    if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
    for _, desc in ipairs(LISTS) do
        -- Explicit branch, NOT `a and f(x) or g(x)`: ResolveClassList legitimately
        -- returns nil (the spec has no such list yet - a hunter's pet lists, say),
        -- and the idiom then fell through to desc.resolve, which listField entries
        -- don't define - "attempt to call a nil value" (user-reported).
        local list
        if desc.listField then
            list = ResolveClassList(profile, desc.listField)
        else
            list = desc.resolve(profile)
        end
        local at = ListIndexOf(list, id)
        if at then
            table.remove(list, at)
            local after = desc.listField and AfterDefensiveList or desc.after
            after(addon)
        end
    end
    addon:ForceUpdateAll()
    local Opt = LibStub("JustAC-Options", true)
    if Opt and Opt.RefreshAllDynamic then Opt.RefreshAllDynamic(addon) end
end

-------------------------------------------------------------------------------
-- The customizations index: every ability with non-default state.
-- Bare list membership is deliberately NOT a customization (the defensive lists
-- are auto-seeded; indexing them would flood this with defaults).
-------------------------------------------------------------------------------
local function CollectCustomizations(profile)
    local seen = {}
    local function badge(id, text)
        if not seen[id] then seen[id] = {} end
        seen[id][#seen[id] + 1] = text
    end

    local bl = BlacklistTable(profile, false)
    if bl then
        for id, v in pairs(bl) do
            if type(id) == "number" and id ~= 0 then
                badge(id, v == true and L["Visibility Everywhere Badge"] or L["Visibility Queue Badge"])
            end
        end
    end
    local ss = profile.defensives and profile.defensives.spellSettings
    if ss then
        for id, s in pairs(ss) do
            if type(id) == "number" and type(s) == "table"
               and (s.procPriority == false or s.alwaysShow == true
                    or s.holdUntilCharged == true or s.holdMode ~= nil) then
                badge(id, L["Pinned Badge"])
            end
        end
    end
    local is = profile.defensives and profile.defensives.itemSettings
    if is then
        for itemID, s in pairs(is) do
            if type(itemID) == "number" and type(s) == "table"
               and (s.linkedAura or s.combatHide) then
                badge(-itemID, L["Item Settings Badge"])
            end
        end
    end
    if profile.hotkeyOverrides then
        for id, v in pairs(profile.hotkeyOverrides) do
            if type(id) == "number" and id ~= 0 and type(v) == "string" then
                badge(id, string.format(L["Hotkey Badge"], v))
            end
        end
    end
    -- The off-bars declaration is a customization too - without this badge an
    -- ability whose ONLY setting is that toggle would vanish from this list.
    local intent = EngineHideIntent(profile, false)
    if intent then
        for id in pairs(intent) do
            if type(id) == "number" and id > 0 then
                badge(id, L["Keep Off Action Bars"])
            end
        end
    end
    -- Situational-set membership (current spec) is a customization too.
    local specKey = GetSpecKey()
    local sets = specKey and profile.situationalSets and profile.situationalSets[specKey]
    if sets then
        for slot, s in pairs(sets) do
            if type(s) == "table" and type(s.spells) == "table" then
                for id in pairs(s.spells) do
                    if type(id) == "number" then badge(id, L["Set Badge"]) end
                end
            end
        end
    end

    local out = {}
    for id, badges in pairs(seen) do
        local name = SpellSearch.DisplayInfo(id)
        out[#out + 1] = {
            id = id,
            name = name or ((id < 0 and "Item #" or "Spell #") .. math.abs(id)),
            badges = table.concat(badges, " · "),
        }
    end
    table.sort(out, function(a, b)
        return SpellSearch.StripColor(a.name) < SpellSearch.StripColor(b.name)
    end)
    return out
end

-------------------------------------------------------------------------------
-- Card builder: writes the dynamic args for the selected ability.
-------------------------------------------------------------------------------
local function BuildCard(addon, args, profile)
    local id = selectedID
    local name, icon = SpellSearch.DisplayInfo(id)
    local isItem = id < 0
    local displayName = name or ((isItem and "Item #" or "Spell #") .. math.abs(id))
    if isItem and name then displayName = displayName .. " |cff00ccff[Item]|r" end
    local specKey = GetSpecKey()

    local roleTag, roleFam = SpellSearch.RoleTag(id)
    roleFam = roleFam or "both"  -- items: role is context-specific, fits everywhere

    -- Card header: icon, name, id, role. Every section below sits under its own header
    -- (Visibility, Pins, Item Settings, Lists, Custom Hotkey, Reset), so the card reads
    -- as chunks rather than one stream - the design pass found the first two sections
    -- unheaded and the visual grouping fell apart at the top of the card.
    args.cardHeader = {
        type = "description",
        name = "|T" .. (icon or 134400) .. ":24:24:0:0|t  |cffFFD100" .. displayName .. "|r  |cff888888("
            .. (isItem and ("item:" .. -id) or ("ID: " .. id)) .. ")|r"
            .. (roleTag and ("  " .. roleTag) or ""),
        order = 10,
        fontSize = "large",
    }

    -- ── Visibility (per-spec; the blacklist behind its real name) ───────────
    if not isItem then
        args.visibilityHeader = {
            type = "header",
            name = SpellSearch.SpecHeader(L["Ability Visibility"]),
            order = 10.5,
        }
    end
    args.visibility = {
        type = "select",
        name = L["Ability Visibility"],
        desc = L["Ability Visibility desc"],
        order = 11,
        width = "double",
        values = function()
            local v = {
                normal     = L["Visibility Normal"],
                everywhere = L["Visibility Everywhere"],
            }
            -- Items never appear in the AC slot, so the middle state is spells-only.
            if not isItem then v.queueOnly = L["Visibility Queue Only"] end
            return v
        end,
        sorting = function()
            return isItem and { "normal", "everywhere" }
                or { "normal", "queueOnly", "everywhere" }
        end,
        get = function()
            local bl = BlacklistTable(profile, false)
            local v = bl and bl[id]
            if v == true then return "everywhere" end
            if type(v) == "table" then return "queueOnly" end
            return "normal"
        end,
        set = function(_, val)
            local bl = BlacklistTable(profile, true)
            if not bl then return end
            if val == "normal" then bl[id] = nil
            elseif val == "queueOnly" then bl[id] = { fixedQueue = true }
            else bl[id] = true end
            addon:ForceUpdate()
            Abilities.UpdateAbilitiesOptions(addon)
        end,
        disabled = function() return not specKey end,
        -- Items: nothing reads the blacklist on the item paths (SpellQueue's item branch
        -- runs before the blacklist check; DefensiveEngine has none). An item is shown
        -- exactly when it is in a list, so its "visibility" IS its list membership below.
        -- Hidden rather than left as a dead control that appears to save.
        hidden = isItem,
    }
    -- The engine-honored half of hiding an ability: the game's assist SKIPS spells
    -- with no visible action-bar button and re-plans around them server-side -
    -- strictly stronger than our display-side hide. Gated on DECLARED intent, not
    -- inferred from bar state: a bare "it's blacklisted and on a bar" hint nagged
    -- players who keep a hidden ability on bars for manual presses, or manage it
    -- behind a macro (user-identified false positives). The toggle appears once the
    -- ability is "Never suggested"; with it set, the card reports honestly in both
    -- directions - still-on-bars (amber) or off-bars-and-skipped (green).
    local function hasEngineIntent()
        local intent = EngineHideIntent(profile, false)
        return intent and intent[id] == true or false
    end
    local function onBars()
        local ABS = LibStub("JustAC-ActionBarScanner", true)
        return (ABS and ABS.GetDirectSlotForSpell and ABS.GetDirectSlotForSpell(id)) and true or false
    end
    args.engineHide = {
        type = "toggle",
        name = L["Keep Off Action Bars"],
        desc = L["Keep Off Action Bars desc"],
        order = 11.05,
        width = "double",
        -- A standalone declaration, deliberately NOT chained behind "Never suggested":
        -- the engine-skip is real whatever the display setting says, and the coupling
        -- was invisible logic (nothing in the UI explained why the toggle came and went).
        hidden = isItem,
        get = hasEngineIntent,
        set = function(_, val)
            local intent = EngineHideIntent(profile, true)
            if intent then intent[id] = val or nil end
        end,
    }
    args.visibilityBarHint = {
        type = "description",
        name = function()
            if onBars() then
                return "|cffffcc66" .. L["Visibility Bar Hint"] .. "|r"
            end
            return "|cff2ecc71" .. L["Visibility Bar Hint OK"] .. "|r"
        end,
        order = 11.1,
        fontSize = "small",
        hidden = function()
            return isItem or not hasEngineIntent()
        end,
    }

    -- ── Pins (global across specs; effective while the ability is in a list) ─
    local function pinToggle(field, nameL, descL, order, defaultOn)
        return {
            type = "toggle",
            name = L[nameL],
            desc = L[descL],
            order = order,
            width = "normal",
            get = function()
                local s = SpellSettings(profile, id, false)
                if defaultOn then return not s or s[field] ~= false end
                return s and s[field] == true or false
            end,
            set = function(_, val)
                local s = SpellSettings(profile, id, true)
                if not s then return end
                -- Explicit if/else, NOT `(not val) and false or nil`: that idiom cannot
                -- produce false - `x and false` is false, and `false or nil` is nil - so
                -- unchecking a default-on pin wrote nil, which reads back as "on". The
                -- Proc Priority box could not be unchecked at all (user-reported).
                if defaultOn then
                    if val then s[field] = nil else s[field] = false end
                else
                    if val then s[field] = true else s[field] = nil end
                end
                if not next(s) then profile.defensives.spellSettings[id] = nil end
                -- alwaysShow / holdUntilCharged are read into the rotation SETUP cache,
                -- which only rebuilds on a list change - a pin toggle changes no list, so
                -- without this the toggle read back correctly and did nothing until a
                -- talent swap or reload. The twin control on the queue tab already does
                -- this; the card was missing it (audit-found).
                local SQ = LibStub("JustAC-SpellQueue", true)
                if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
                addon:ForceUpdateAll()
                Abilities.UpdateAbilitiesOptions(addon)
            end,
        }
    end
    -- Spells only: no item path reads spellSettings (EvalDefensiveItem and SpellQueue's
    -- item branch both skip it), so for an item every pin was a toggle that saved and
    -- did nothing - and still earned a "Pinned" badge in the index. Hidden as a block.
    if not isItem then
        args.pinHeader = { type = "header", name = L["Ability Pins"], order = 11.5 }
        -- Same family order as the custom-queue rows: Hold -> Always Show -> Proc
        -- Priority. Proc Priority reads last (and never greys on visibility): it
        -- is the one pin that also acts in the defensive and pet lists.
        args.pinProc   = pinToggle("procPriority", "Proc Priority", "Proc Priority desc", 14, true)
        args.pinAlways = pinToggle("alwaysShow", "Always Show", "Always Show desc", 13, false)
        -- Inert while this spec's visibility override (or an inactive situational
        -- set) hides the spell: the blacklist branch runs before the pin could
        -- bypass any filtering, so grey it rather than let it look live.
        args.pinAlways.disabled = function()
            local SQ = LibStub("JustAC-SpellQueue", true)
            return (SQ and SQ.IsSpellBlacklisted and SQ.IsSpellBlacklisted(id)) or false
        end
        -- The Hold Until dial acts only while the custom queue is the rotation
        -- source AND "Unavailable last" sinking is on; the shared control greys
        -- the sink half itself and takes the custom-queue half as extraDisabled.
        args.pinHold = SpellSearch and SpellSearch.HoldModeControl
            and SpellSearch.HoldModeControl(addon, id, 12, "normal", function()
                local p = addon.db.profile
                local sk = GetSpecKey()
                local cq = sk and p.customQueue and p.customQueue[sk]
                return not (cq and cq.enabled)
            end) or nil
        args.pinNote = {
            type = "description",
            name = "|cff888888" .. L["Ability Pins Note"] .. "|r",
            order = 15,
            fontSize = "small",
        }
    end

    -- ── Item settings (mirror the defensive-row controls) ───────────────────
    if isItem then
        local itemID = -id
        -- Item cards skip Visibility and Pins, so this is their first section: without a
        -- header the card opened straight into a "Link Aura..." button under the name.
        args.itemHeader = { type = "header", name = L["Item Settings"], order = 15.5 }
        args.linkAura = {
            type = "execute",
            name = function()
                local s = ItemSettings(profile, itemID, false)
                if s and s.linkedAura then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s.linkedAura)
                    return (info and info.name) or tostring(s.linkedAura)
                end
                return L["Link Aura..."]
            end,
            desc = L["Link Aura desc"],
            order = 16,
            width = "double",
            func = function()
                local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
                if not LiveSearchPopup then return end
                LiveSearchPopup.Open({
                    title      = L["Link Aura..."],
                    searchFunc = SpellSearch.GetFilteredPlayerAuras,
                    onSelect   = function(auraSpellID)
                        local s = ItemSettings(profile, itemID, true)
                        if not s then return end
                        s.linkedAura = auraSpellID
                        -- combatHide defaults ON with a link (a linked-buff item is usually
                        -- one you don't want cluttering the bar mid-fight). Remembered as
                        -- auto-set so Clear Link can unwind it - a user who then flips the
                        -- toggle themselves owns it, and Clear leaves their choice alone.
                        if s.combatHide == nil then
                            s.combatHide = true
                            s.combatHideAuto = true
                        end
                        addon:ForceUpdateAll()
                        Abilities.UpdateAbilitiesOptions(addon)
                    end,
                })
            end,
        }
        args.clearAura = {
            type = "execute",
            name = L["Clear Link"],
            desc = L["Clear Link desc"],
            order = 17,
            width = "half",
            hidden = function()
                local s = ItemSettings(profile, itemID, false)
                return not (s and s.linkedAura)
            end,
            func = function()
                local s = ItemSettings(profile, itemID, false)
                if s then
                    s.linkedAura = nil
                    -- Undo the combatHide the link switched on, unless the user set it.
                    if s.combatHideAuto then s.combatHide, s.combatHideAuto = nil, nil end
                    if not next(s) then profile.defensives.itemSettings[itemID] = nil end
                end
                addon:ForceUpdateAll()
                Abilities.UpdateAbilitiesOptions(addon)
            end,
        }
        args.combatHide = {
            type = "toggle",
            name = L["Hide in Combat"],
            desc = L["Hide in Combat desc"],
            order = 18,
            width = "normal",
            get = function()
                local s = ItemSettings(profile, itemID, false)
                return s and s.combatHide or false
            end,
            set = function(_, val)
                local s = ItemSettings(profile, itemID, true)
                if s then
                    s.combatHide = val or nil
                    s.combatHideAuto = nil   -- the user owns this value now
                    if not next(s) then profile.defensives.itemSettings[itemID] = nil end
                end
                addon:ForceUpdateAll()
                Abilities.UpdateAbilitiesOptions(addon)   -- the index badge tracks this
            end,
        }
    end

    -- ── Situational sets (spells only; per-spec; toggled by keybind) ─────────
    -- Membership lives here beside the ability; the sets are named on the General
    -- tab and flipped from Key Bindings. Storage: profile.situationalSets[specKey][slot]
    -- = { name = "...", spells = { [id] = true } }.
    if not isItem and specKey then
        args.setsHeader = { type = "header", name = SpellSearch.SpecHeader(L["Situational Sets"]), order = 18 }
        args.setsNote = {
            type = "description",
            name = "|cff888888" .. L["Situational Sets Note"] .. "|r",
            order = 18.1,
            fontSize = "small",
        }
        local SQ = LibStub("JustAC-SpellQueue", true)
        for slot = 1, (SQ and SQ.SET_SLOTS or 3) do
            args["set" .. slot] = {
                type = "toggle",
                name = function() return addon:GetSituationalSetName(slot) end,
                desc = L["Situational Set Member desc"],
                order = 18.1 + slot * 0.1,
                width = "normal",
                get = function()
                    local sets = profile.situationalSets and profile.situationalSets[specKey]
                    local s = sets and sets[slot]
                    return s and s.spells and s.spells[id] == true or false
                end,
                set = function(_, val)
                    profile.situationalSets = profile.situationalSets or {}
                    profile.situationalSets[specKey] = profile.situationalSets[specKey] or {}
                    local sets = profile.situationalSets[specKey]
                    sets[slot] = sets[slot] or { spells = {} }
                    sets[slot].spells = sets[slot].spells or {}
                    if val then sets[slot].spells[id] = true else sets[slot].spells[id] = nil end
                    if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
                    -- Membership can change what the OFF tag should say (removing the last
                    -- member of an OFF set makes it active again - see IsSetActive).
                    local UIR = LibStub("JustAC-UIRenderer", true)
                    if UIR and UIR.RefreshSetIndicator then UIR.RefreshSetIndicator(addon) end
                    addon:ForceUpdate()
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            }
        end
    end

    -- ── List membership ─────────────────────────────────────────────────────
    args.listsHeader = {
        type = "header",
        name = SpellSearch.SpecHeader(L["Ability Lists"]),
        order = 20,
    }
    local order = 21
    for _, desc in ipairs(LISTS) do
        local list, naText
        if desc.listField then
            list = ResolveClassList(profile, desc.listField)
        else
            list, naText = desc.resolve(profile)
        end
        local pos = ListIndexOf(list, id)

        -- Type-filtered: a row appears when the ability is already in that list
        -- (Remove must always be reachable) or genuinely fits it.
        if (not desc.petOnly or IsPetClass())
           and not (desc.spellsOnly and isItem)
           and (pos or desc.fits(id, roleFam)) then
            local after = desc.listField and AfterDefensiveList or desc.after

            args["list_" .. desc.key] = {
                type = "description",
                name = L[desc.nameKey] .. ": " .. (pos and ("|cff2ecc71#" .. pos .. "|r")
                    or ("|cff888888" .. (naText or L["Not In List"]) .. "|r")),
                order = order,
                width = "double",
            }
            -- Resolved at PRESS time, not captured from the card build: a rotation
            -- re-snapshot replaces the underlying table (SnapshotRotation builds a
            -- fresh one), and mutating the stale capture was a silent no-op.
            local function LiveList()
                if desc.listField then return ResolveClassList(profile, desc.listField) end
                return (desc.resolve(profile))
            end
            -- The list to EDIT: created on demand (defaults materialised) so Add works
            -- on a spec that has never stored one, and Remove edits a real list rather
            -- than a defaults fallback the removed spell would resurface from.
            local function EditList()
                if desc.listField then return EnsureClassList(profile, desc.listField) end
                if desc.key == "gap" then return EnsureGapCloserList(profile) end
                if desc.ensure then return desc.ensure(profile) end
                return (desc.resolve(profile))
            end
            args["listbtn_" .. desc.key] = {
                type = "execute",
                name = pos and L["Remove"] or L["Add"],
                order = order + 0.1,
                width = "half",
                -- Disabled only when the list can never exist here (no spec key, or the
                -- Custom Queue is switched off) - not merely because it is empty.
                disabled = function()
                    if desc.listField or desc.key == "gap" then return not GetSpecKey() end
                    return not LiveList()
                end,
                func = function()
                    local live = EditList()
                    if not live then return end
                    local at = ListIndexOf(live, id)
                    if at then
                        table.remove(live, at)
                    else
                        if not SpellSearch.AddSpellToList(addon, live, id) then return end
                    end
                    after(addon)
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            }
            order = order + 1
        end
    end

    -- ── Hotkey override (global) ────────────────────────────────────────────
    args.hotkeyHeader = { type = "header", name = L["Custom Hotkey"], order = 40 }
    args.hotkey = {
        type = "input",
        name = L["Custom Hotkey"],
        desc = L["Enter the hotkey text to display (e.g. 1, F1, S-2)"],
        order = 41,
        width = "normal",
        get = function()
            return (profile.hotkeyOverrides and profile.hotkeyOverrides[id]) or ""
        end,
        set = function(_, val)
            if not profile.hotkeyOverrides then profile.hotkeyOverrides = {} end
            local trimmed = val and val:trim() or ""
            profile.hotkeyOverrides[id] = trimmed ~= "" and trimmed or nil
            addon:InvalidateCaches({hotkeys = true})   -- icons cache the string
            addon:ForceUpdate()
            Abilities.UpdateAbilitiesOptions(addon)
        end,
    }

    -- ── Clear everything for this ability ───────────────────────────────────
    -- Own section, under its own header: without one it landed on the same visual row as
    -- the hotkey field and read as that field's control (user-reported). It is the one
    -- destructive action on the card, so it should look set apart, not attached.
    args.clearHeader = { type = "header", name = L["Reset Ability"], order = 49 }
    args.clearAbility = {
        type = "execute",
        name = L["Clear Ability"],
        desc = L["Clear Ability desc"],
        order = 50,
        width = "normal",
        confirm = true,
        func = function() ClearAbility(addon, profile, id) end,
    }
    -- Done closes the card. It lives HERE, at the foot beside Reset - where you finish
    -- with the card - not up by the picker where it first went: an affordance far from
    -- the thing it dismisses is one the eye does not connect. Without it a selected card
    -- sat open until another ability was picked, and the customizations list below read
    -- as a page you could not get back to (user-reported).
    args.closeAbility = {
        type = "execute",
        name = L["Done"],
        desc = L["Done desc"],
        order = 51,
        width = "half",
        func = function()
            selectedID = nil
            Abilities.UpdateAbilitiesOptions(addon)
        end,
    }
end

-------------------------------------------------------------------------------
-- Tab skeleton + dynamic rebuild
-------------------------------------------------------------------------------
function Abilities.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Abilities"],
        order = 5.5,  -- exceptions come after the queues they override, above Profiles
        args = {
            info = {
                type = "description",
                name = L["Abilities Info"],
                order = 1,
                fontSize = "medium",
            },
            -- Dynamic content added by UpdateAbilitiesOptions
        },
    }
end

function Abilities.UpdateAbilitiesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not optionsTable.args.abilities then return end
    local args = optionsTable.args.abilities.args
    local profile = addon:GetProfile()
    if not profile then return end

    SpellSearch.ClearDynamicArgs(args, { info = true })

    args.selectAbility = {
        type = "execute",
        name = L["Select Spell..."],
        order = 2,
        width = "normal",
        func = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end
            SpellSearch.BuildSpellbookCache()
            LiveSearchPopup.Open({
                title      = L["Abilities"],
                searchFunc = SpellSearch.GetFilteredResults,
                onSelect   = function(id)
                    if not id or id == 0 then return end
                    selectedID = id
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            })
        end,
    }

    if selectedID then
        BuildCard(addon, args, profile)
    end

    -- ── Customizations index ────────────────────────────────────────────────
    args.customHeader = {
        type = "header",
        name = L["Your Customizations"],
        order = 60,
    }
    local rows = CollectCustomizations(profile)
    if #rows == 0 then
        args.noCustomizations = {
            type = "description",
            name = "|cff888888" .. L["No Customizations"] .. "|r",
            order = 61,
        }
    else
        for i, row in ipairs(rows) do
            local _, icon = SpellSearch.DisplayInfo(row.id)
            -- Two controls per row, not one full-width bar: the ability (opens its card)
            -- and a compact Remove that wipes every customization without opening it.
            args["cust_" .. tostring(row.id)] = {
                type = "execute",
                name = "|T" .. (icon or 134400) .. ":16:16:0:0|t " .. row.name
                    .. "  |cff888888" .. row.badges .. "|r",
                desc = L["Open Ability desc"],
                order = 60 + i,
                width = "double",
                func = function()
                    selectedID = row.id
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            }
            args["custrm_" .. tostring(row.id)] = {
                type = "execute",
                name = L["Remove"],
                desc = L["Clear Ability desc"],
                order = 60 + i + 0.5,
                width = "half",
                confirm = true,
                confirmText = string.format(L["Remove Customizations confirm"], row.name),
                func = function()
                    ClearAbility(addon, profile, row.id)
                    if selectedID == row.id then selectedID = nil end
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            }
        end
    end

    NotifyChange()
end
