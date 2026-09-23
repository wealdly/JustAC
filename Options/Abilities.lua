-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Abilities - the Overrides tab: everything set on one spell or item.
--
-- Lists answer WHEN (order, on their own tabs); this tab answers HOW: visibility (the
-- blacklist) and the action bars, queue settings, item settings, sets and the hotkey label.
-- Its index is a list like the others, each row opening its ability's settings as panels
-- under it. A VIEW - it reads and writes the stores the engines already consume.
local Abilities = LibStub:NewLibrary("JustAC-OptionsAbilities", 1)
if not Abilities then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local W = LibStub("JustAC-OptionsWidgets")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- The open ability is the index's open row: the list keeps it, as every list keeps its own.
local ListWidget = LibStub("JustAC-ListWidget")
local function Selected() return ListWidget.selected.abilityindex end
local function Select(id) ListWidget.selected.abilityindex = id end

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
-- One ability's settings as options-table-shaped controls. Every place that offers one - a
-- list row's settings strip, the Overrides tab's panels (both Options/ListWidget.lua) - is
-- handed the SAME description, so they cannot drift. `onChange` runs after every write, so each surface
-- refreshes itself. The profile is read when a control is used, never captured: a
-- profile switch with the panel open would otherwise write into the old one.
-------------------------------------------------------------------------------
local Controls = {}
Abilities.Controls = Controls

--- A per-spell flag in spellSettings. Default-on flags are stored only while OFF.
function Controls.Pin(addon, id, field, name, desc, defaultOn, onChange)
    return {
        type = "toggle", name = name, desc = desc,
        get = function()
            local s = SpellSettings(addon:GetProfile(), id, false)
            if defaultOn then return not s or s[field] ~= false end
            return s and s[field] == true or false
        end,
        set = function(_, val)
            local profile = addon:GetProfile()
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
            -- Pins are read into the rotation SETUP cache, which only rebuilds on a list
            -- change - a pin changes no list, so without this it read back correctly
            -- and did nothing until a talent swap or reload.
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
            addon:ForceUpdateAll()
            if onChange then onChange() end
        end,
    }
end

function Controls.AlwaysShow(addon, id, onChange)
    local c = Controls.Pin(addon, id, "alwaysShow", L["Always Show"], L["Always Show desc"], false, onChange)
    -- Inert while this spec's visibility override (or an inactive situational set)
    -- hides the spell: the blacklist branch runs before the pin could bypass any
    -- filtering, so grey it rather than let it look live.
    c.disabled = function()
        local SQ = LibStub("JustAC-SpellQueue", true)
        return (SQ and SQ.IsSpellBlacklisted and SQ.IsSpellBlacklisted(id)) or false
    end
    return c
end

--- Proc Priority is the one pin that also acts in the defensive and pet lists.
function Controls.ProcPriority(addon, id, onChange, name, desc)
    return Controls.Pin(addon, id, "procPriority", name or L["Proc Priority"],
        desc or L["Proc Priority desc"], true, onChange)
end

--- An item's settings: an aura that means "already active", and hiding it in combat.
--- Only the defensive engine reads these, so only its lists and the Overrides tab offer them.
function Controls.Item(addon, itemID, onChange)
    local function settings(create) return ItemSettings(addon:GetProfile(), itemID, create) end
    local function prune(s)
        if not next(s) then addon:GetProfile().defensives.itemSettings[itemID] = nil end
    end
    local function changed()
        addon:ForceUpdateAll()
        if onChange then onChange() end
    end
    return {
        {
            type = "execute",
            name = function()
                local s = settings(false)
                if s and s.linkedAura then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s.linkedAura)
                    return L["Linked: %s"]:format((info and info.name) or tostring(s.linkedAura))
                end
                return L["Link Aura..."]
            end,
            desc = L["Link Aura desc"],
            func = function()
                local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
                if not LiveSearchPopup then return end
                LiveSearchPopup.Open({
                    title      = L["Link Aura..."],
                    searchFunc = SpellSearch.GetFilteredPlayerAuras,
                    onSelect   = function(auraSpellID)
                        local s = settings(true)
                        if not s then return end
                        s.linkedAura = auraSpellID
                        -- combatHide defaults ON with a link (a linked-buff item is usually
                        -- one you don't want cluttering the bar mid-fight, and its aura is
                        -- almost certainly secret in combat). Remembered as auto-set so Clear
                        -- Link can unwind it - a user who then flips the toggle themselves
                        -- owns it, and Clear leaves their choice alone.
                        if s.combatHide == nil then
                            s.combatHide = true
                            s.combatHideAuto = true
                        end
                        changed()
                    end,
                })
            end,
        },
        {
            type = "execute",
            name = L["Clear Link"],
            desc = L["Clear Link desc"],
            hidden = function()
                local s = settings(false)
                return not (s and s.linkedAura)
            end,
            func = function()
                local s = settings(false)
                if s then
                    s.linkedAura = nil
                    -- Undo the combatHide the link switched on, unless the user set it.
                    if s.combatHideAuto then s.combatHide, s.combatHideAuto = nil, nil end
                    prune(s)
                end
                changed()
            end,
        },
        {
            type = "toggle",
            name = L["Hide in Combat"],
            desc = L["Hide in Combat desc"],
            get = function()
                local s = settings(false)
                return s and s.combatHide or false
            end,
            set = function(_, val)
                local s = settings(true)
                if s then
                    s.combatHide = val or nil
                    s.combatHideAuto = nil   -- the user owns this value now
                    prune(s)
                end
                changed()
            end,
        },
    }
end

-- "Wait until below": a defensive shows greyed out, marked WAIT, until health drops under
-- the level picked. The engine fails safe (DefensiveEngine WaitSetting): it waits only on a
-- DEFINITE reading, so the tooltip has to say the setting can silently stop holding.
local WAIT_STEPS = { 90, 80, 70, 60, 50, 40, 30, 20 }

--- autoPct: the level Auto means for this ability, when it has one of its own.
local function WaitControl(addon, read, write, onChange, autoPct)
    local auto = L["Wait Auto"]
    if autoPct then auto = auto .. " (" .. string.format(L["Wait Pct"], autoPct) .. ")" end
    local values, sorting = { auto = auto, off = L["Wait Never"] }, { "auto" }
    for _, pct in ipairs(WAIT_STEPS) do
        values[pct] = string.format(L["Wait Pct"], pct)
        sorting[#sorting + 1] = pct
    end
    sorting[#sorting + 1] = "off"
    return {
        type = "select",
        name = L["Wait Until Below"],
        desc = L["Wait Until Below desc"],
        values = values,
        sorting = sorting,
        get = function()
            local v = read()
            if v == nil then return "auto" end
            return v
        end,
        set = function(_, v)
            if v == "auto" then v = nil end
            write(v)
            addon:ForceUpdateAll()
            if onChange then onChange() end
        end,
    }
end

--- The dial for a list entry: a spell id, or a NEGATIVE id for an item.
function Controls.WaitBelow(addon, id, onChange)
    local itemID = (id < 0) and -id or nil
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local autoPct = SpellDB and SpellDB.GetDefaultWaitBelow and SpellDB.GetDefaultWaitBelow(id)
    local function store(create)
        local profile = addon:GetProfile()
        if itemID then return ItemSettings(profile, itemID, create) end
        return SpellSettings(profile, id, create)
    end
    return WaitControl(addon,
        function()
            local s = store(false)
            return s and s.waitBelow
        end,
        function(v)
            local s = store(v ~= nil)
            if not s then return end
            s.waitBelow = v
            if next(s) then return end
            local def = addon:GetProfile().defensives
            if itemID then def.itemSettings[itemID] = nil else def.spellSettings[id] = nil end
        end, onChange, autoPct)
end

--- The Emergency Potion entry's own dial. Kept apart from any item's, because the pot it
--- fires changes with what is in your bags.
function Controls.PotionWaitBelow(addon, onChange)
    return WaitControl(addon,
        function()
            local def = addon:GetProfile().defensives
            return def and def.emergencyPotionWaitBelow
        end,
        function(v)
            local def = addon:GetProfile().defensives
            if def then def.emergencyPotionWaitBelow = v end
        end, onChange)
end

-- Sections that apply to every spec say so, the way per-spec ones carry the class and spec
-- (SpellSearch.SpecHeader). Without it a setting quietly followed the player to their
-- other spec, or quietly did not.
local function AllSpecs(label)
    return label .. "  |cff888888(" .. L["Scope All Specs"] .. ")|r"
end

-- The lists themselves - where each lives, what fits it, how to edit it - are described
-- once in Options/SpellLists.lua. Looked up on use: that file loads first but reads its
-- controls from here, so neither captures the other at load time.
local function Lists() return LibStub("JustAC-OptionsSpellLists") end

-- ── Off the action bars ──────────────────────────────────────────────────
-- What JustAC took off the bars, per character and spec (bar layouts are both), so Put
-- Back can return it: { [spellID] = { slots = { {slot, id} }, prevVisibility } }.
local function BarRecords(addon, create)
    local c = addon.db and addon.db.char
    local sk = GetSpecKey()
    if not (c and sk) then return nil end
    if not c.barRemovals then
        if not create then return nil end
        c.barRemovals = {}
    end
    if not c.barRemovals[sk] then
        if not create then return nil end
        c.barRemovals[sk] = {}
    end
    return c.barRemovals[sk]
end

--- "Action Bar 1 button 5": the names Edit Mode uses, so the player can find the slot.
local function SlotName(slot)
    local button = ((slot - 1) % 12) + 1
    if slot <= 12 then return string.format(L["Bar Slot"], 1, button) end
    if slot <= 24 then return string.format(L["Bar Slot Page 2"], button) end
    if slot <= 36 then return string.format(L["Bar Slot"], 4, button) end
    if slot <= 48 then return string.format(L["Bar Slot"], 5, button) end
    if slot <= 60 then return string.format(L["Bar Slot"], 3, button) end
    if slot <= 72 then return string.format(L["Bar Slot"], 2, button) end
    if slot <= 120 then return string.format(L["Bar Slot Stance"], math.floor((slot - 73) / 12) + 1, button) end
    return string.format(L["Bar Slot"], 6 + math.floor((slot - 145) / 12), button)
end

local function SlotNames(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = SlotName(s.slot) end
    return table.concat(out, ", ")
end

local function AbilityName(id)
    local name = SpellSearch.DisplayInfo(id)
    return name and SpellSearch.StripColor(name) or tostring(id)
end

--- Take an ability off every action bar slot it is on, and stop suggesting it here too.
function Abilities.RemoveFromBars(addon, id)
    if InCombatLockdown() then return end
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    if not (ABS and ABS.FindSpellSlots) then return end
    local slots, macros = ABS.FindSpellSlots(id)
    if #slots == 0 then return end
    local cleared = ABS.ClearSlots(slots)
    local profile = addon:GetProfile()
    local rec, bl = BarRecords(addon, true), BlacklistTable(profile, true)
    if not (rec and bl) then return end
    rec[id] = { slots = slots, prevVisibility = bl[id] }
    bl[id] = true
    addon:Print(string.format(L["Bars Removed Chat"], AbilityName(id), cleared, SlotNames(slots)))
    if #macros > 0 then addon:Print(string.format(L["Bars Macro Chat"], SlotNames(macros))) end
    addon:ForceUpdateAll()
    Abilities.UpdateAbilitiesOptions(addon)
end

--- Undo it: back into the same slots where they are still empty, and suggested as before.
function Abilities.PutBackOnBars(addon, id)
    if InCombatLockdown() then return end
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    local rec = BarRecords(addon, false)
    local r = rec and rec[id]
    if not (ABS and ABS.PlaceSpells and r) then return end
    local placed, taken = ABS.PlaceSpells(r.slots)
    local bl = BlacklistTable(addon:GetProfile(), true)
    if bl then bl[id] = r.prevVisibility end
    rec[id] = nil
    addon:Print(string.format(L["Bars Put Back Chat"], AbilityName(id), placed))
    if taken > 0 then addon:Print(string.format(L["Bars Slots Taken Chat"], taken)) end
    addon:ForceUpdateAll()
    Abilities.UpdateAbilitiesOptions(addon)
end

--- Wipe every customization this tab can set for one ability: visibility, queue and item
--- settings, sets, hotkey label, its entries in every priority list, and - if JustAC took
--- it off the action bars - put it back. The index row's x runs this; keeping "everything"
--- in one function means a setting added later is cleared too.
local function ClearAbility(addon, profile, id)
    local rec = BarRecords(addon, false)
    if rec and rec[id] and not InCombatLockdown() then Abilities.PutBackOnBars(addon, id) end
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
    -- Pins live in the rotation setup cache (see Controls.Pin) - clearing them needs the
    -- same invalidation or the old pin keeps applying until the next list change.
    local SQ = LibStub("JustAC-SpellQueue", true)
    if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
    for _, desc in ipairs(Lists().LISTS) do
        if not (desc.inactive and desc.inactive(addon))
           and Lists().Remove(addon, desc, id) then
            desc.after(addon)
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
local function CollectCustomizations(profile, addon)
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
    -- One badge per setting, saying which: "pinned" covered four different things, and
    -- read wrongly for the wait level, which is not a pin at all.
    local function waitBadge(id, w)
        if type(w) == "number" then badge(id, string.format(L["Wait Badge"], w))
        elseif w == "off" then badge(id, L["Badge Never Waits"]) end
    end
    local ss = profile.defensives and profile.defensives.spellSettings
    if ss then
        for id, s in pairs(ss) do
            if type(id) == "number" and type(s) == "table" then
                if s.holdMode ~= nil or s.holdUntilCharged == true then badge(id, L["Badge Hold"]) end
                if s.alwaysShow == true then badge(id, L["Badge Always"]) end
                if s.procPriority == false then badge(id, L["Badge Proc Off"]) end
                waitBadge(id, s.waitBelow)
            end
        end
    end
    local is = profile.defensives and profile.defensives.itemSettings
    if is then
        for itemID, s in pairs(is) do
            if type(itemID) == "number" and type(s) == "table" then
                if s.linkedAura then badge(-itemID, L["Badge Linked"]) end
                if s.combatHide then badge(-itemID, L["Badge Combat Hide"]) end
                waitBadge(-itemID, s.waitBelow)
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
    -- Taken off the action bars by us (this spec): the one change that lives outside the
    -- profile, so it must show here or it would be invisible.
    local barRec = addon and BarRecords(addon, false)
    if barRec then
        for id in pairs(barRec) do badge(id, L["Badge Off Bars"]) end
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
-- An ability's settings, as the panels its row opens in the index. The list draws them
-- (ListWidget.BindPanels) inside its own pane: the same tinted strip every list opens under
-- an entry, one small titled panel per section, each title saying its scope.
-------------------------------------------------------------------------------
local function CardPanels(addon, id)
    local profile = addon:GetProfile()
    local isItem = id < 0
    local specKey = GetSpecKey()
    local roleTag, roleFam = SpellSearch.RoleTag(id)
    roleFam = roleFam or "both"  -- items: role is context-specific, fits everywhere
    local function refresh() Abilities.UpdateAbilitiesOptions(addon) end
    local panels = {}

    -- ── Visibility (per spec), and whether the game's own assist can see it ──
    -- Spells only: nothing reads the blacklist on the item paths, and items do not go
    -- through the game's assist, so an item's "visibility" IS its list membership.
    if not isItem then
        local ABS = LibStub("JustAC-ActionBarScanner", true)
        local function record()
            local rec = BarRecords(addon, false)
            return rec and rec[id]
        end
        local function find()
            if not (ABS and ABS.FindSpellSlots) then return {}, {} end
            return ABS.FindSpellSlots(id)
        end
        -- Where it is, said before anything is pressed, so the button's effect is plain.
        local function barText()
            local r = record()
            if r then return "|cffffcc66" .. string.format(L["Bars Status Removed"], SlotNames(r.slots)) .. "|r" end
            local slots = find()
            if #slots > 0 then return string.format(L["Bars Status On"], SlotNames(slots)) end
            return "|cff888888" .. L["Bars Status Off"] .. "|r"
        end
        panels[#panels + 1] = {
            title = SpellSearch.SpecHeader(L["Ability Visibility"]),
            lines = {
                { {
                    type = "select",
                    name = L["Ability Visibility"],
                    -- The action-bar advice lives here: shown on its own it nagged players who
                    -- keep a hidden ability on their bars for manual presses.
                    desc = function() return L["Ability Visibility desc"] .. "\n\n" .. L["Visibility Bar Tip"] end,
                    values = {
                        normal     = L["Visibility Normal"],
                        queueOnly  = L["Visibility Queue Only"],
                        everywhere = L["Visibility Everywhere"],
                    },
                    sorting = { "normal", "queueOnly", "everywhere" },
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
                        refresh()
                    end,
                    disabled = function() return not specKey end,
                } },
                { { type = "description", name = barText } },
                { {
                    type = "description",
                    name = function()
                        local _, macros = find()
                        return string.format(L["Bars Status Macro"], SlotNames(macros))
                    end,
                    hidden = function()
                        local _, macros = find()
                        return #macros == 0
                    end,
                } },
                { {
                    type = "execute",
                    name = W.risky(L["Bars Remove"]),
                    desc = L["Bars Remove desc"],
                    hidden = function() return record() ~= nil or #(find()) == 0 end,
                    disabled = function() return InCombatLockdown() end,
                    -- The question names every slot it will empty and what changes as a result.
                    confirm = function()
                        return string.format(L["Bars Remove Confirm"], AbilityName(id), SlotNames((find())))
                    end,
                    func = function() Abilities.RemoveFromBars(addon, id) end,
                }, {
                    type = "execute",
                    name = L["Bars Put Back"],
                    desc = L["Bars Put Back desc"],
                    hidden = function() return record() == nil end,
                    disabled = function() return InCombatLockdown() end,
                    func = function() Abilities.PutBackOnBars(addon, id) end,
                } },
            },
        }

        -- ── Queue settings (all specs) ───────────────────────────────────────────
        -- Each shows only where it can matter: it is read by one kind of list, so an ability
        -- that neither fits that kind nor sits in such a list gets a line saying so instead
        -- of a control that does nothing. Proc Priority is read by every list.
        local SL = Lists()
        local function inList(key)
            local d = SL.Get(key)
            return d and SL.IndexOf(d.resolve(addon), id) ~= nil
        end
        local offensive = roleFam ~= "defensive" or inList("custom")
        local defensive = roleFam ~= "offensive" or inList("defensive")
        -- One line; the panel wraps it if it runs out of room.
        local queue = {}
        if offensive then queue[#queue + 1] = Controls.AlwaysShow(addon, id, refresh) end
        queue[#queue + 1] = Controls.ProcPriority(addon, id, refresh)
        if offensive and SpellSearch.HoldModeControl then
            -- Acts only while your own list is the rotation source; the shared control greys
            -- the "unavailable last" half itself and takes this half as extraDisabled.
            queue[#queue + 1] = SpellSearch.HoldModeControl(addon, id, function()
                local p = addon.db.profile
                local sk = GetSpecKey()
                local cq = sk and p.customQueue and p.customQueue[sk]
                return not (cq and cq.enabled)
            end, refresh)
        end
        if defensive then queue[#queue + 1] = Controls.WaitBelow(addon, id, refresh) end
        local lines = { queue }
        if not (offensive and defensive) then
            lines[2] = { { type = "description", name = "|cff888888" .. L["Ability Settings Filtered"] .. "|r" } }
        end
        panels[#panels + 1] = { title = AllSpecs(L["Ability Queue Settings"]), lines = lines }
    end

    -- ── Item settings (all specs) ───────────────────────────────────────────────
    if isItem then
        local item = Controls.Item(addon, -id, refresh)
        panels[#panels + 1] = {
            title = AllSpecs(L["Item Settings"]),
            lines = { { item[1], item[2] }, { item[3], Controls.WaitBelow(addon, id, refresh) } },
        }
    end

    -- ── Situational sets (per spec; toggled by keybind) ──────────────────────
    -- Storage: profile.situationalSets[specKey][slot] = { name = "...", spells = { [id] = true } }.
    if not isItem and specKey then
        local SQ = LibStub("JustAC-SpellQueue", true)
        local line = {}
        for slot = 1, (SQ and SQ.SET_SLOTS or 3) do
            line[slot] = {
                type = "toggle",
                name = function() return addon:GetSituationalSetName(slot) end,
                desc = L["Situational Sets Note"],
                get = function()
                    local sets = profile.situationalSets and profile.situationalSets[specKey]
                    local st = sets and sets[slot]
                    return st and st.spells and st.spells[id] == true or false
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
                    refresh()
                end,
            }
        end
        panels[#panels + 1] = { title = SpellSearch.SpecHeader(L["Situational Sets"]), lines = { line } }
    end

    -- ── Hotkey label (all specs) ─────────────────────────────────────────────
    panels[#panels + 1] = {
        title = AllSpecs(L["Custom Hotkey"]),
        lines = { { {
            type = "input",
            name = L["Custom Hotkey"],
            desc = L["Enter the hotkey text to display (e.g. 1, F1, S-2)"],
            get = function()
                return (profile.hotkeyOverrides and profile.hotkeyOverrides[id]) or ""
            end,
            set = function(_, val)
                if not profile.hotkeyOverrides then profile.hotkeyOverrides = {} end
                local trimmed = val and val:trim() or ""
                profile.hotkeyOverrides[id] = trimmed ~= "" and trimmed or nil
                addon:InvalidateCaches({hotkeys = true})   -- icons cache the string
                addon:ForceUpdate()
                refresh()
            end,
        } } },
    }

    -- ── Footer: which of this spec's lists hold it, its ID and role ──────────
    -- Read-only: adding and removing happen on the list tabs.
    local parts = {}
    local SL = Lists()
    for _, desc in ipairs(SL.LISTS) do
        local pos = (not desc.available or desc.available()) and SL.IndexOf(desc.resolve(addon), id)
        if pos then parts[#parts + 1] = desc.name .. " |cff2ecc71#" .. pos .. "|r" end
    end
    local footer = "|cff888888(" .. (isItem and ("item:" .. -id) or ("ID: " .. id)) .. ")|r"
        .. (roleTag and ("  " .. roleTag) or "") .. "    "
        .. ((#parts > 0) and (L["In Your Lists"] .. " " .. table.concat(parts, ", ")) or L["In No Lists"])
    return { panels = panels, footer = footer }
end

-- ── The customizations index ────────────────────────────────────────────────
-- Drawn with the rows every list uses; a row opens its ability's panels under it like any
-- list opens an entry, and a second click closes them. A VIEW, not a list: worked out from
-- the stores each time, and registered apart from the lists, so nothing that walks them sees
-- it. The x clears every override without opening it - the quick way, and why it asks first.
local indexBadges, indexNames = {}, {}
local function IndexIDs(addon)
    local rows = CollectCustomizations(addon:GetProfile(), addon)
    wipe(indexBadges)
    wipe(indexNames)
    local ids = {}
    for i, r in ipairs(rows) do
        ids[i] = r.id
        indexBadges[r.id], indexNames[r.id] = r.badges, r.name
    end
    -- An ability searched for with nothing set yet still gets a row - at the top, where the
    -- search was - so it opens the same way as the rest. It stays only while it is open.
    local open = Selected()
    if open and not Lists().IndexOf(ids, open) then table.insert(ids, 1, open) end
    return ids
end

Lists().RegisterView("abilityindex", {
    name = L["Your Customizations"], empty = L["No Customizations"], ordered = false,
    resolve = IndexIDs, ensure = IndexIDs,
    after = function(addon) Abilities.UpdateAbilitiesOptions(addon) end,
    controls = function(addon, id) return CardPanels(addon, id) end,
    -- What is set reads beside the name; the cooldown column means nothing here.
    decorate = function(_, id, row)
        -- The open one in gold, so it is plain which row a second click closes.
        if id == Selected() then row.name = "|cffffd100" .. row.name .. "|r" end
        row.name = row.name .. "  |cff888888" .. (indexBadges[id] or L["Nothing Set Yet"]) .. "|r"
        if id > 0 then row.right = nil end
    end,
    -- A second click on the open ability closes it again. Explicit if/else, never
    -- `x and nil or y`: that idiom cannot produce nil, so it could never close.
    click = function(addon, id)
        if Selected() == id then Select(nil) else Select(id) end
        Abilities.UpdateAbilitiesOptions(addon)
    end,
    confirmRemove = function(_, id)
        return string.format(L["Remove Customizations confirm"],
            SpellSearch.StripColor(indexNames[id] or AbilityName(id)))
    end,
    forget = function(addon, id)
        ClearAbility(addon, addon:GetProfile(), id)
        if Selected() == id then Select(nil) end
        Abilities.UpdateAbilitiesOptions(addon)
    end,
})

function Abilities.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Overrides Tab"],
        order = 5.5,  -- exceptions come after the queues they override, above Profiles
        args = {
            info = {
                type = "description",
                name = L["Abilities Intro"],
                order = 1,
                fontSize = "medium",
            },
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
                title      = L["Overrides Tab"],
                searchFunc = SpellSearch.GetFilteredResults,
                onSelect   = function(id)
                    if not id or id == 0 then return end
                    Select(id)
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            })
        end,
    }
    args.customHeader = { type = "header", name = L["Your Customizations"], order = 60 }
    args.indexList = Lists().Control("abilityindex", 61)
    NotifyChange()
end

--- Open an ability from anywhere - a list row's right click. Every setting it has is here,
--- where a list row can show only its own list's.
function Abilities.Open(id)
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if not (addon and id) then return end
    Select(id)
    Abilities.UpdateAbilitiesOptions(addon)
    local ACD = LibStub("AceConfigDialog-3.0", true)
    if ACD then ACD:SelectGroup("JustAssistedCombat", "abilities") end
end
