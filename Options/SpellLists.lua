-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: every ability list the player edits, described once.
--
-- Each list says where it lives, how to make it editable, what to refresh after an edit,
-- what can go in it and what an entry's settings are. The list tabs mount the same plain
-- list widget (below) for each, the Abilities tab's "which lists is this in" rows read the
-- same descriptions, and nothing else knows how any one list is stored.
--
-- The offensive priority list is the exception: it has tabs, a pinned first slot and
-- comparison columns, so it draws itself (Options/PriorityList.lua). It is still listed
-- here, for the Abilities tab and for its Add button.
--
-- READ vs EDIT. `resolve` returns what is in effect and must never be written to: for
-- the gap-closer and burst lists that can be the shipped defaults themselves. `ensure`
-- returns a list that is safe to edit, copying the effective one into the profile first
-- if it has to, so an edit refines what the player was looking at instead of replacing
-- it. The two agree entry for entry, which is what lets a row act on an index.
local SpellLists = LibStub:NewLibrary("JustAC-OptionsSpellLists", 1)
if not SpellLists then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local ListWidget = LibStub("JustAC-ListWidget")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch")
local W = LibStub("JustAC-OptionsWidgets")
local AceGUI = LibStub("AceGUI-3.0", true)
local CreateFrame = CreateFrame

local WIDGET_TYPE = "JustACSpellList"

local function Addon() return LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
local function SpecKey()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
end
local function NotifyChange()
    local reg = LibStub("AceConfigRegistry-3.0", true)
    if reg then reg:NotifyChange("JustAssistedCombat") end
end
local function Copy(list)
    local out = {}
    for i = 1, (list and #list or 0) do out[i] = list[i] end
    return out
end
local function IndexOf(list, id)
    for i = 1, (list and #list or 0) do
        if list[i] == id then return i end
    end
    return nil
end
local function EmergencyPotion()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.EMERGENCY_POTION
end
local function Controls() return LibStub("JustAC-OptionsAbilities").Controls end


--------------------------------------------------------------------------------
-- The defensive family: lists stored side by side per spec, seeded from class defaults
-- at login.
--------------------------------------------------------------------------------
local function ClassList(listField)
    return function(addon)
        local DE = LibStub("JustAC-DefensiveEngine", true)
        return DE and DE.GetClassSpellList and DE.GetClassSpellList(addon, listField) or nil
    end
end

-- Create-on-demand twin of the above. The read returns nil until the spec has been given
-- that list, and Add was greyed out on exactly the lists that were empty with nothing to
-- say why (a fresh Hunter's pet lists). Seeds the way DefensiveEngine does at login, so a
-- list born here is indistinguishable from one born there.
local function EnsureClassList(listField)
    local resolve = ClassList(listField)
    return function(addon)
        local have = resolve(addon)
        if have then return have end
        local profile = addon:GetProfile()
        local specKey = SpecKey()
        if not (profile and profile.defensives and specKey) then return nil end
        local def = profile.defensives
        def.classSpells = def.classSpells or {}
        def.classSpells[specKey] = def.classSpells[specKey] or {}
        local DE = LibStub("JustAC-DefensiveEngine", true)
        local SpellDB = LibStub("JustAC-SpellDB", true)
        local defaultsKey = DE and DE.DefaultsKeyForList and DE.DefaultsKeyForList(listField)
        local _, playerClass = UnitClass("player")
        local defaults = defaultsKey and SpellDB and SpellDB[defaultsKey]
            and SpellDB.ResolveDefaults and SpellDB.ResolveDefaults(SpellDB[defaultsKey], specKey, playerClass)
        def.classSpells[specKey][listField] = Copy(defaults)
        return def.classSpells[specKey][listField]
    end
end

local function AfterDefensiveList(addon)
    local DE = LibStub("JustAC-DefensiveEngine", true)
    if DE and DE.RegisterDefensivesForTracking then DE.RegisterDefensivesForTracking(addon) end
    addon:ForceUpdateAll()
    NotifyChange()
end

local function PetDefaults(tableName)
    return function()
        local _, pc = UnitClass("player")
        local SpellDB = LibStub("JustAC-SpellDB", true)
        return (SpellDB and SpellDB[tableName] and SpellDB[tableName][pc]) and true or false
    end
end

local function RestoreDefensive(listType)
    return function(addon)
        addon:RestoreDefensiveDefaults(listType)
        AfterDefensiveList(addon)
    end
end

--- Which pot the Emergency Potion entry fires, or off. Only that entry has it.
local function PotionControl(addon, onChange)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return {
        type = "select",
        name = L["Emergency Potion Use"],
        width = "double",
        desc = function()
            local rule = L["Emergency Potion Auto Desc"]
            local info = SpellDB and SpellDB.GetBestHealingItemInfo and SpellDB.GetBestHealingItemInfo()
            if not info then return rule end
            local restores
            if info.isPct then
                restores = info.value .. "%"
                if info.heal and info.heal > 0 then
                    restores = restores .. " (~" .. BreakUpLargeNumbers(math.floor(info.heal)) .. ")"
                end
            elseif info.value and info.value > 0 then
                restores = "~" .. BreakUpLargeNumbers(info.value)
            end
            local best = "|cff00ff00" .. info.name .. "|r"
            if restores then best = best .. " - " .. restores .. " " .. L["health"] end
            if info.owned > 1 then
                best = best .. " (" .. L["best of"] .. " " .. info.owned .. ")"
            end
            return rule .. "\n\n" .. L["Best in bags"] .. ": " .. best
        end,
        values = function()
            local vals = { [-1] = L["Emergency Potion Off"], [0] = L["Auto best owned"] }
            if SpellDB and SpellDB.GetOwnedHealingItems then
                for _, it in ipairs(SpellDB.GetOwnedHealingItems()) do vals[it.id] = it.name end
            end
            return vals
        end,
        get = function()
            local p = addon:GetProfile()
            return (p and p.defensives and p.defensives.emergencyPotionChoice) or 0
        end,
        set = function(_, v)
            local p = addon:GetProfile()
            if p and p.defensives then p.defensives.emergencyPotionChoice = v end
            onChange()
        end,
    }
end

--- The Emergency Potion entry's name says which pot it will reach for.
local function PotionLabel(addon)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local p = addon:GetProfile()
    local choice = (p and p.defensives and p.defensives.emergencyPotionChoice) or 0
    local label
    if choice == -1 then
        label = "|cff888888" .. L["Emergency Potion Off"] .. "|r"
    elseif choice > 0 then
        label = (C_Item.GetItemInfo(choice)) or ("Item " .. choice)
    else
        local bestID = SpellDB and SpellDB.GetBestHealingItem and SpellDB.GetBestHealingItem()
        local bestName = bestID and (C_Item.GetItemInfo(bestID))
        label = bestName and (L["Auto"] .. ": " .. bestName) or L["Auto best owned"]
    end
    return L["Emergency Potion"] .. " |cff00ccff(" .. label .. ")|r"
end

--- Settings for an entry of a list the defensive engine reads. That engine is the only
--- reader of item settings and of Proc Priority outside the offensive list, so no other
--- list offers either. `wait` adds "Wait until below", which only the main defensive list
--- honours. Dropdowns fill from the right, so the dial is listed first to sit at the end.
local function DefensiveControls(allowItems, wait)
    return function(addon, entry, onChange)
        local C = Controls()
        local out
        if entry == EmergencyPotion() then
            out = { PotionControl(addon, onChange) }
            if wait then table.insert(out, 1, C.PotionWaitBelow(addon, onChange)) end
            return out
        end
        if entry < 0 then
            if not allowItems then return nil end
            out = C.Item(addon, -entry, onChange)
        else
            out = { C.ProcPriority(addon, entry, onChange) }
        end
        if wait then out[#out + 1] = C.WaitBelow(addon, entry, onChange) end
        return out
    end
end

--- The "wait until below" an entry of the defensive list has: a percent, "off" or nil.
local function DefensiveWait(addon, entry)
    local def = addon:GetProfile().defensives
    if not def then return nil end
    if entry == EmergencyPotion() then return def.emergencyPotionWaitBelow end
    local s
    if entry < 0 then
        s = def.itemSettings and def.itemSettings[-entry]
    else
        s = def.spellSettings and def.spellSettings[entry]
    end
    return s and s.waitBelow
end

--------------------------------------------------------------------------------
-- Gap-closers and burst triggers: an EMPTY stored list means "use the defaults", so the
-- effective list is read through to them and materialised before the first edit.
--------------------------------------------------------------------------------
local function GapResolve(addon)
    local specKey = SpecKey()
    if not specKey then return nil end
    local profile = addon:GetProfile()
    local stored = profile and profile.gapClosers and profile.gapClosers.classSpells
        and profile.gapClosers.classSpells[specKey]
    if stored and #stored > 0 then return stored end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.CLASS_GAPCLOSER_DEFAULTS and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
end

local function GapEnsure(addon)
    local specKey = SpecKey()
    local profile = addon:GetProfile()
    if not (specKey and profile) then return nil end
    profile.gapClosers = profile.gapClosers or { enabled = false }
    profile.gapClosers.classSpells = profile.gapClosers.classSpells or {}
    local cs = profile.gapClosers.classSpells
    if not cs[specKey] or #cs[specKey] == 0 then cs[specKey] = Copy(GapResolve(addon)) end
    return cs[specKey]
end

local function BurstOverride(addon, create)
    local specKey = SpecKey()
    local profile = addon:GetProfile()
    if not (specKey and profile) then return nil end
    if create then
        profile.burstTriggers = profile.burstTriggers or {}
        profile.burstTriggers[specKey] = profile.burstTriggers[specKey] or {}
    end
    return profile.burstTriggers and profile.burstTriggers[specKey]
end

-- The override when there is one, else what the queue is actually using (theorycraft
-- markers, else curated defaults). The override is read RAW rather than from the queue's
-- resolved copy, which swaps talent forms in, so a row's id is the stored one.
local function BurstResolve(addon)
    local ov = BurstOverride(addon, false)
    if ov and #ov > 0 then return ov end
    local SQ = LibStub("JustAC-SpellQueue", true)
    return SQ and SQ.GetBurstTriggerInfo and SQ.GetBurstTriggerInfo() or nil
end

local function BurstEnsure(addon)
    local ov = BurstOverride(addon, true)
    if ov and #ov == 0 then
        local eff = BurstResolve(addon)
        for i = 1, (eff and #eff or 0) do ov[i] = eff[i] end
    end
    return ov
end

local function AfterBurst(addon)
    local SQ = LibStub("JustAC-SpellQueue", true)
    if SQ and SQ.InvalidateBurstTriggers then SQ.InvalidateBurstTriggers() end
    addon:ForceUpdate()
    NotifyChange()
end

--------------------------------------------------------------------------------
-- The registry
--   name / header / info / empty   words the tab shows (header=false: the group has one)
--   spellsOnly                     no items (the add search looks at the spellbook only)
--   ordered                        false when position means nothing
--   available()                    false hides the list for this character
--   inactive(addon)                why the list is not in use right now, or nil
--   resolve / ensure / after       read, edit, refresh (see the file header)
--   controls(addon, entry, onChange)  that entry's settings, or nil
--   wait(addon, entry)             that entry's "wait until below", for the row to show
--   restore                        { name, desc, func(addon), disabled(addon) }
--   onRemove(addon, entry)         just before an entry leaves the list
--------------------------------------------------------------------------------
local LISTS = {
    {
        key = "custom", name = L["Priority Tab Custom"],
        spellsOnly = false,
        resolve = function(addon)
            local specKey = SpecKey()
            local profile = addon:GetProfile()
            local cq = specKey and profile and profile.customQueue and profile.customQueue[specKey]
            return cq and cq.spells
        end,
        -- Kept while the queue is not using your list: the Abilities tab says so rather
        -- than offering to edit a list that changes nothing.
        inactive = function(addon)
            local specKey = SpecKey()
            local profile = addon:GetProfile()
            local cq = specKey and profile and profile.customQueue and profile.customQueue[specKey]
            if cq and cq.enabled then return nil end
            return L["Custom Priority Disabled"]
        end,
        ensure = function(addon)
            local specKey = SpecKey()
            local profile = addon:GetProfile()
            if not (specKey and profile) then return nil end
            profile.customQueue = profile.customQueue or {}
            profile.customQueue[specKey] = profile.customQueue[specKey] or { enabled = false }
            local cq = profile.customQueue[specKey]
            cq.spells = cq.spells or {}
            return cq.spells
        end,
        after = function(addon)
            local PL = LibStub("JustAC-PriorityList", true)
            if PL and PL.Changed then PL.Changed(addon) else addon:ForceUpdateAll() end
        end,
    },
    {
        key = "defensive", name = L["Defensive Priority List"], info = L["Defensive Priority desc"],
        spellsOnly = false,
        resolve = ClassList("defensiveSpells"), ensure = EnsureClassList("defensiveSpells"),
        after = AfterDefensiveList, controls = DefensiveControls(true, true), wait = DefensiveWait,
        restore = { name = L["Restore Class Defaults"], desc = L["Restore Defensive Defaults desc"],
                    func = RestoreDefensive("defensive") },
        onRemove = function(addon, entry)
            -- Record the intent, so the tile stays gone. Everything else that can drop it
            -- is treated as accidental and re-seeded.
            if entry ~= EmergencyPotion() then return end
            local DE = LibStub("JustAC-DefensiveEngine", true)
            if DE and DE.MarkEmergencyPotionRemoved then DE.MarkEmergencyPotionRemoved(addon) end
        end,
    },
    {
        -- Party-wide buttons. Only honoured in combat, so like the gap-closer and burst
        -- lists it has no per-entry settings.
        -- Spell names come from the game (W.spellDesc): Rallying Cry, Darkness, Vampiric Embrace.
        key = "grouphelp", name = L["Group Help List"], header = false,
        info = W.spellDesc("Group Help desc", 97462, 196718, 15286),
        spellsOnly = true,
        resolve = ClassList("groupHelpSpells"), ensure = EnsureClassList("groupHelpSpells"),
        after = AfterDefensiveList,
        restore = { name = L["Restore Class Defaults name"], desc = L["Restore Group Help Defaults desc"],
                    func = RestoreDefensive("grouphelp") },
    },
    {
        key = "gap", name = L["Gap-Closers"], header = L["Gap-Closer Priority List"],
        info = L["Gap-Closer Priority desc"], empty = L["No Gap-Closer Spells"],
        spellsOnly = true,
        resolve = GapResolve, ensure = GapEnsure,
        after = function(addon)
            addon:ForceUpdate()
            NotifyChange()
        end,
        restore = { name = L["Restore Class Defaults"], desc = L["Restore Gap-Closer Defaults desc"],
                    func = function(addon)
                        local GCE = LibStub("JustAC-GapCloserEngine", true)
                        if GCE and GCE.RestoreGapCloserDefaults then GCE.RestoreGapCloserDefaults(addon) end
                        addon:ForceUpdate()
                        NotifyChange()
                    end },
    },
    {
        key = "burst", name = L["Burst Triggers"], header = false,
        info = L["Burst Triggers List desc"], empty = L["Burst Triggers None"],
        spellsOnly = true, ordered = false,
        resolve = BurstResolve, ensure = BurstEnsure, after = AfterBurst,
        restore = { name = L["Clear Burst Triggers"], desc = L["Clear Burst Triggers desc"],
                    func = function(addon)
                        local specKey = SpecKey()
                        local profile = addon:GetProfile()
                        if profile and specKey and profile.burstTriggers then
                            profile.burstTriggers[specKey] = nil
                        end
                        AfterBurst(addon)
                    end,
                    disabled = function(addon)
                        local ov = BurstOverride(addon, false)
                        return not (ov and #ov > 0)
                    end },
    },
    {
        key = "petrez", name = L["Pet Rez/Summon Priority List"], info = L["Pet Rez/Summon Priority desc"],
        spellsOnly = true, available = PetDefaults("CLASS_PET_REZ_DEFAULTS"),
        resolve = ClassList("petRezSpells"), ensure = EnsureClassList("petRezSpells"),
        after = AfterDefensiveList, controls = DefensiveControls(false),
        restore = { name = L["Restore Class Defaults name"], desc = L["Restore Pet Rez Defaults desc"],
                    func = RestoreDefensive("petrez") },
    },
    {
        key = "petheal", name = L["Pet Heal Priority List"], info = L["Pet Heal Priority desc"],
        spellsOnly = false, available = PetDefaults("CLASS_PETHEAL_DEFAULTS"),
        resolve = ClassList("petHealSpells"), ensure = EnsureClassList("petHealSpells"),
        after = AfterDefensiveList, controls = DefensiveControls(true),
        restore = { name = L["Restore Class Defaults name"], desc = L["Restore Pet Heal Defaults desc"],
                    func = RestoreDefensive("petheal") },
    },
}
local BY_KEY = {}
for _, d in ipairs(LISTS) do BY_KEY[d.key] = d end

SpellLists.LISTS = LISTS
SpellLists.IndexOf = IndexOf
function SpellLists.Get(key) return BY_KEY[key] end

--- A read-only VIEW drawn with the same widget - the Abilities tab's index, say. Kept out of
--- LISTS on purpose: everything that walks LISTS (the membership rows, "clear everywhere")
--- is about lists a player edits, and a view is worked out from the stores each time.
--- Beyond the list fields a view can have:
---   decorate(addon, entry, row)   adjust a row before it is drawn
---   click(addon, entry)           what a left click on a row does
---   confirmRemove(addon, entry)   the question to ask before x acts
---   forget(addon, entry)          what x does once answered
function SpellLists.RegisterView(key, d)
    d.key = key
    BY_KEY[key] = d
end

--- Take an entry out of a list, if it is in it. Through `ensure`, so a list read through
--- to its defaults is copied before anything is removed from it rather than the shipped
--- defaults being edited in place.
--- @return boolean removed
function SpellLists.Remove(addon, d, id)
    local shown = d.resolve(addon)
    if not IndexOf(shown, id) then return false end
    local live = d.ensure(addon)
    local at = IndexOf(live, id)
    if not at then return false end
    if d.onRemove then d.onRemove(addon, id) end
    table.remove(live, at)
    return true
end

--------------------------------------------------------------------------------
-- The options for one list
--------------------------------------------------------------------------------

--- An "Add ability..." button for a list. The target is resolved when a pick is made, not
--- when the button was built: a re-snapshot replaces the list table, and adding to the
--- captured one was a silent no-op. Nothing is copied until something is actually picked,
--- so opening the search and cancelling leaves a read-through list reading through.
function SpellLists.AddButton(addon, key, order)
    local d = BY_KEY[key]
    return {
        type = "execute",
        name = L["Priority Add"],
        desc = L["Search spell desc"],
        order = order,
        width = "normal",
        func = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end
            SpellSearch.BuildSpellbookCache()
            LiveSearchPopup.Open({
                title = L["Add"] .. ": " .. d.name,
                searchFunc = d.spellsOnly and SpellSearch.GetFilteredSpellbookSpells
                    or SpellSearch.GetFilteredResults,
                excludeList = Copy(d.resolve(addon)),
                onSelect = function(id)
                    if SpellSearch.AddSpellToList(addon, d.ensure(addon), id) then d.after(addon) end
                end,
            })
        end,
    }
end


--- The option that mounts the list widget for a list or view.
function SpellLists.Control(key, order)
    return {
        type = "description", name = "", order = order, width = "full",
        arg = key,   -- handed to the widget by AceConfigDialog (SetCustomData)
        dialogControl = (AceGUI and AceGUI:GetWidgetVersion(WIDGET_TYPE)) and WIDGET_TYPE or nil,
    }
end

--- Write one list's options into `args` (a new table when nil) from `order` up: its
--- header, what it is for, the rows, then Add and the reset. Every list tab is this call.
function SpellLists.Args(addon, key, order, args)
    args = args or {}
    local d = BY_KEY[key]
    local hidden = d.available and function() return not d.available() end or nil
    if d.header ~= false then
        args[key .. "Header"] = { type = "header", name = d.header or d.name, order = order, hidden = hidden }
    end
    if d.info then
        args[key .. "Info"] = { type = "description", name = d.info, order = order + 0.1,
                                fontSize = "small", hidden = hidden }
    end
    args[key .. "List"] = SpellLists.Control(key, order + 0.2)
    args[key .. "List"].hidden = hidden
    args[key .. "Add"] = SpellLists.AddButton(addon, key, order + 0.3)
    args[key .. "Add"].hidden = hidden
    if d.restore then
        local r = d.restore
        args[key .. "Restore"] = {
            type = "execute", name = r.name, desc = r.desc, order = order + 0.4, width = "normal",
            hidden = hidden,
            disabled = r.disabled and function() return r.disabled(addon) end or nil,
            func = function() r.func(addon) end,
        }
    end
    return args
end

--------------------------------------------------------------------------------
-- The widget
--------------------------------------------------------------------------------

local function CooldownText(id)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local cd = BlizzardAPI and BlizzardAPI.GetBaseCooldownSeconds and BlizzardAPI.GetBaseCooldownSeconds(id)
    cd = math.floor(cd or 0)
    if cd < 2 then return nil end
    if cd < 60 then return cd .. "s" end
    if cd % 60 == 0 then return string.format("%dm", cd / 60) end
    return string.format("%dm %ds", math.floor(cd / 60), cd % 60)
end

local function RowData(addon, d, entry, i)
    local name, icon, right
    if entry == EmergencyPotion() then
        name, icon = PotionLabel(addon), 134832
    elseif entry < 0 then
        name, icon = SpellSearch.DisplayInfo(entry)
        name = name or ("Item " .. -entry)
        right = L["List Item Tag"]
    else
        name, icon = SpellSearch.DisplayInfo(entry)
        right = CooldownText(entry)
    end
    local wait = d.wait and d.wait(addon, entry)
    if type(wait) == "number" then right = string.format(L["Wait Badge"], wait) end
    local controls
    if d.controls then
        controls = function() return d.controls(addon, entry, function() d.after(addon) end) end
    end
    local row = {
        id = entry,
        name = name or tostring(entry),
        icon = icon or 134400,
        num = (d.ordered ~= false) and i or nil,
        right = right,
        wait = wait,
        controls = controls,
    }
    if d.decorate then d.decorate(addon, entry, row) end
    return row
end

local methods = {}

function methods:OnAcquire()
    self.addon = Addon()
    self.disabled, self.listKey = false, nil
    self:SetHeight(32)
end

function methods:OnRelease()
    ListWidget.Reset(self)
    self.addon, self.listKey, self.disabled, self.refreshing = nil, nil, false, nil
end

-- AceConfigDialog drives a description control with SetText / SetFontObject, and every
-- control with SetDisabled. The list draws itself, so the option's own text is unused.
function methods:SetText() end
function methods:SetFontObject() end
function methods:SetDisabled(disabled)
    self.disabled = disabled and true or false
    self:Refresh()
end
function methods:OnWidthSet() self:Refresh() end

--- The option's `arg`: which list this mount shows.
function methods:SetCustomData(key)
    self.listKey = key
    local d = BY_KEY[key]
    self.ordered = not (d and d.ordered == false)
    self:Refresh()
end

function methods:List()
    local d = BY_KEY[self.listKey]
    return d and self.addon and d.ensure(self.addon) or nil
end
function methods:Commit()
    local d = BY_KEY[self.listKey]
    if d and self.addon then d.after(self.addon) end
end
function methods:Reflow() NotifyChange() end
function methods:RowClickable()
    local d = BY_KEY[self.listKey]
    return (d and d.click) ~= nil
end
function methods:OnRowClick(id)
    local d = BY_KEY[self.listKey]
    if d and d.click and self.addon then d.click(self.addon, id) end
end
--- A view that asks before x acts. What runs on Yes is the view's own `forget`, captured
--- with the addon now: the dialog outlives this widget, which the panel may have recycled
--- by the time the answer comes.
function methods:RemoveRequested(id)
    local d = BY_KEY[self.listKey]
    if not (d and d.confirmRemove and d.forget and self.addon) then return false end
    local addon = self.addon
    ListWidget.Confirm(d.confirmRemove(addon, id), function() d.forget(addon, id) end)
    return true
end
function methods:OnRemove(id)
    local d = BY_KEY[self.listKey]
    if d and d.onRemove then d.onRemove(self.addon, id) end
end
--- The game's own tooltip for the ability, which already says everything about it.
function methods:RowTitle(row)
    if row.id == EmergencyPotion() then
        GameTooltip:SetText(L["Emergency Potion"], 1, 1, 1)
    elseif row.id < 0 then
        GameTooltip:SetItemByID(-row.id)
    else
        GameTooltip:SetSpellByID(row.id)
    end
end
function methods:RowTooltip(row)
    local w = row.wait
    if type(w) == "number" then
        GameTooltip:AddLine(string.format(L["Wait Row Note"], w), 1, 0.82, 0.4, true)
    elseif w == "off" then
        GameTooltip:AddLine(L["Wait Row Never"], 1, 0.82, 0.4, true)
    end
end
function methods:OnRowCreated(row)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
end

function methods:Refresh()
    if not (self.addon and self.listKey) or self.refreshing then return end
    self.refreshing = true
    local d = BY_KEY[self.listKey]
    local list = d.resolve(self.addon) or {}
    local rows = {}
    for i, entry in ipairs(list) do rows[i] = RowData(self.addon, d, entry, i) end
    local y, detailShown = ListWidget.PlaceRows(self, rows, -6, not self.disabled)
    -- A greyed-out section (its feature switched off) still shows what is in the list.
    self.content:SetAlpha(self.disabled and 0.5 or 1)
    self.emptyNote:SetShown(#rows == 0 and d.empty ~= nil)
    self.emptyNote:SetText(d.empty or "")
    self:SetHeight((#rows == 0) and (d.empty and 34 or 12) or (6 - y))
    self.refreshing = nil
    return detailShown
end

local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    local widget = { frame = frame, type = WIDGET_TYPE }
    for method, func in pairs(methods) do widget[method] = func end
    -- The same pane the priority list sits on, rows above it.
    local body = ListWidget.Pane(frame)
    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints()
    body:SetFrameLevel(frame:GetFrameLevel() + 1)
    content:SetFrameLevel(body:GetFrameLevel() + 1)
    ListWidget.Attach(widget, content)
    widget.emptyNote = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.emptyNote:SetPoint("TOPLEFT", 10, -10)
    widget.emptyNote:SetPoint("RIGHT", -8, 0)
    widget.emptyNote:SetJustifyH("LEFT")
    return AceGUI:RegisterAsWidget(widget)
end

if AceGUI then AceGUI:RegisterWidgetType(WIDGET_TYPE, Constructor, 1) end
