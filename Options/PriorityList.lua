-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: the priority list as ONE custom AceGUI widget, mounted into the normal options
-- table with `dialogControl`. Everything else in the panel stays declarative Ace options.
--
-- Why a widget at all: the list is the one place the option table's layout fights the
-- content. An entry rendered as an inline group costs a bordered box, a title line and a
-- row of full-height buttons - about 84px - so four entries fill the panel and a 14-entry
-- list is mostly below the fold. Ace lays widgets out by width fraction with each widget
-- keeping its own height, so a one-line row of mixed controls cannot be expressed there.
-- One frame we draw ourselves gives a 26px row and, more importantly, lets the list say
-- things the option table cannot: which slot the game owns, and which entries the addon
-- is unable to time.
--
-- What it deliberately does NOT do itself: anything Ace or another module already owns.
-- The per-row settings are real AceGUI widgets parented into the row; the tab strip uses
-- Blizzard's own options-tab art; and the name lookup, settings store, rank sort and
-- baseline snapshot all come from the modules that own them.
local Type, Version = "JustACPriorityList", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local PriorityList = LibStub:NewLibrary("JustAC-PriorityList", 1)
if not PriorityList then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local CreateFrame = CreateFrame

local ROW_H, PIN_H, TAB_H, GAP, DETAIL_H, HEAD_H = 26, 30, 28, 4, 34, 16
local LOCK_TEXTURE = "Interface\\Buttons\\LockButton-Locked-Up"
-- Everything on a row that is NOT the two text columns: number, icon, rank, the four
-- buttons and the gaps between them. What is left is split between name and
-- condition, so a wider panel widens both instead of only one.
local ROW_FIXED = 208

local INK, INK_DIM = { 0.93, 0.90, 0.85 }, { 0.66, 0.62, 0.55 }
local GOLD, GREEN, BLUE = { 0.85, 0.65, 0.34 }, { 0.62, 0.79, 0.50 }, { 0.44, 0.62, 0.85 }

--------------------------------------------------------------------------------
-- Model
--------------------------------------------------------------------------------
local function Addon() return LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
local function SpecKey()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey() or nil
end
local function CustomQueueFor(profile)
    local specKey = SpecKey()
    return specKey and profile and profile.customQueue and profile.customQueue[specKey] or nil
end

--- Which source the QUEUE is using right now. Deliberately independent of `orderExact`:
--- "show my order literally" is a different question from "whose order", and folding both
--- into one profile field made ticking either silently move the other.
function PriorityList.LiveSource(profile)
    local cq = CustomQueueFor(profile)
    if cq and cq.enabled then return "custom" end
    return (profile and profile.contextOrder or "simc") == "simc" and "simc" or "blizzard"
end

--- The source ON SCREEN: the previewed tab, else whichever is live. Controls outside the
--- widget key off this so they can hide when they make no sense for the tab being shown.
function PriorityList.CurrentSource(profile)
    return PriorityList.view or PriorityList.LiveSource(profile)
end

--- Point the queue at a source. The settings that decide it are written together, so a
--- player comparing sources flips one control instead of remembering the pair.
function PriorityList.SetLiveSource(addon, source)
    local profile = addon and addon:GetProfile()
    local specKey = SpecKey()
    if not (profile and specKey) then return end
    profile.customQueue = profile.customQueue or {}
    profile.customQueue[specKey] = profile.customQueue[specKey] or { enabled = false, spells = {} }
    local cq = profile.customQueue[specKey]
    if source == "custom" then
        cq.enabled = true
    else
        cq.enabled = false
        profile.contextOrder = (source == "simc") and "simc" or "ac"
    end
    PriorityList.Changed(addon)
end

--- Sort ids into priority order for a source, in place. The ONE ranker: the reset button
--- and the previews below both call it, so two copies cannot drift apart.
function PriorityList.SortByPriority(ids, source)
    local RI = LibStub("JustAC-RotationImport", true)
    if not RI then return ids end
    local key = {}
    for _, id in ipairs(ids) do
        local rec = RI.GetEntry and RI.GetEntry(id, "st")
        if source == "blizzard" then
            key[id] = (RI.GetBlizzardRank and RI.GetBlizzardRank(id)) or 999
        else
            -- Unranked entries (poisons, utility) fall below everything the data ranks.
            key[id] = (rec and rec.rank) or (1000 + ((RI.GetBlizzardRank and RI.GetBlizzardRank(id)) or 999))
        end
    end
    table.sort(ids, function(a, b)
        if key[a] ~= key[b] then return (key[a] or 999) < (key[b] or 999) end
        return a < b
    end)
    return ids
end

--- Copy the source the player is LOOKING AT into their own list, and switch to it. This is
--- how a list begins: there is no blank-page state to explain, and the order they just
--- compared is the order they get.
function PriorityList.StartFrom(addon, source)
    local profile = addon and addon:GetProfile()
    local specKey = SpecKey()
    if not (profile and specKey) then return end
    local rows = PriorityList.Rows(addon, source)
    if #rows == 0 then return end
    profile.customQueue = profile.customQueue or {}
    profile.customQueue[specKey] = profile.customQueue[specKey] or {}
    local cq = profile.customQueue[specKey]
    cq.spells = {}
    for i = 1, #rows do cq.spells[i] = rows[i].id end
    -- The baseline is the game's pool as it stands now, so the "new abilities since you
    -- made this" notice keeps working. Same snapshot the reset button takes.
    local CustomQueue = LibStub("JustAC-OptionsCustomQueue", true)
    if CustomQueue and CustomQueue.SnapshotBaseline then CustomQueue.SnapshotBaseline(cq) end
    cq.enabled = true
    PriorityList.selected = nil
    PriorityList.Changed(addon)
end

--- Empty the list and hand the queue back to the game. Leaves the entries' own settings
--- alone: those are ability-level and shared with the other lists.
function PriorityList.ClearList(addon)
    local cq = CustomQueueFor(addon and addon:GetProfile())
    if not cq then return end
    cq.spells, cq.baseline, cq.enabled = {}, nil, false
    PriorityList.selected = nil
    PriorityList.Changed(addon)
end

--- Upkeep, not rotation: poisons, weapon imbues and long-duration self/raid buffs. The
--- game surfaces these one at a time out of combat and holds its other picks until each is
--- applied, so a list that owns the order can sit on one of them and never move on. They
--- belong to the pre-combat reminder, which offers them without blocking the queue.
function PriorityList.IsUpkeep(spellID)
    if not spellID or spellID <= 0 then return false end
    local RF = LibStub("JustAC-RedundancyFilter", true)
    if RF and RF.IsUpkeepSpell then return RF.IsUpkeepSpell(spellID) end
    return false
end

--- Remove upkeep abilities from a stored list. Older lists were snapshotted from the
--- game's pool, which carries every poison the spec can use, and those entries stall the
--- queue (see IsUpkeep). Runs when the panel builds, so a list repairs itself once.
--- @return number how many were dropped
function PriorityList.PruneUpkeep(addon)
    local cq = CustomQueueFor(addon and addon:GetProfile())
    local list = cq and cq.spells
    if not list then return 0 end
    local kept, dropped = {}, 0
    for i = 1, #list do
        if PriorityList.IsUpkeep(list[i]) then dropped = dropped + 1 else kept[#kept + 1] = list[i] end
    end
    if dropped > 0 then cq.spells = kept end
    return dropped
end

--- How many abilities a source holds, without the per-row name and icon lookups Rows()
--- does. Cheap enough to ask for all three sources on every refresh.
function PriorityList.CountFor(addon, source)
    local profile = addon and addon:GetProfile()
    if not (profile and SpecKey()) then return 0 end
    if source == "custom" then
        local cq = CustomQueueFor(profile)
        return cq and cq.spells and #cq.spells or 0
    end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local pool = BlizzardAPI and BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()
    local n = 0
    for _, id in ipairs(pool or {}) do
        if not PriorityList.IsUpkeep(id) then n = n + 1 end
    end
    return n
end

--- The entries of one source: { id, name, icon, rank, cond, gameTimed, upkeep }.
function PriorityList.Rows(addon, source)
    local out = {}
    local profile = addon and addon:GetProfile()
    if not (profile and SpecKey()) then return out end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
    local RI = LibStub("JustAC-RotationImport", true)
    if not BlizzardAPI then return out end

    local ids = {}
    if source == "custom" then
        local cq = CustomQueueFor(profile)
        for i, id in ipairs((cq and cq.spells) or {}) do ids[i] = id end
    else
        for i, id in ipairs((BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()) or {}) do
            ids[i] = id
        end
        PriorityList.SortByPriority(ids, source)   -- a custom list is the player's own order
        -- The game's pool carries every poison; a list must not, so the preview a list is
        -- started from does not offer them either.
        local keep = {}
        for _, id in ipairs(ids) do
            if not PriorityList.IsUpkeep(id) then keep[#keep + 1] = id end
        end
        ids = keep
    end

    for i = 1, #ids do
        local id = ids[i]
        -- DisplayInfo owns the awkward cases: items arrive as NEGATIVE ids, and a
        -- transform form is labelled with the button it belongs to.
        local name, icon
        if SpellSearch and SpellSearch.DisplayInfo then name, icon = SpellSearch.DisplayInfo(id) end
        local rec = (id > 0) and RI and RI.GetEntry and RI.GetEntry(id, "st") or nil
        out[i] = {
            id = id,
            name = name or tostring(id),
            icon = icon or 134400,
            rank = rec and rec.rank or nil,
            upkeep = PriorityList.IsUpkeep(id),
            cond = (id > 0) and (PriorityList.IsUpkeep(id) and L["Priority Cond Upkeep"]
                or PriorityList.Condition(rec)) or nil,
        }
    end
    return out
end

--- One line of plain words for an entry's conditions.
function PriorityList.Condition(rec)
    if not rec then return L["Priority Cond Unknown"] end
    local gates = rec.gates
    if not gates or #gates == 0 then return L["Priority Cond None"] end
    local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
    local parts = {}
    for i = 1, #gates do
        local g, piece = gates[i], nil
        if g.t == "buff" and g.id then
            local nm = SpellSearch and SpellSearch.DisplayInfo and SpellSearch.DisplayInfo(g.id)
            piece = string.format(g.neg and L["Priority Cond Not During"] or L["Priority Cond During"],
                nm or tostring(g.id))
        elseif g.t == "stealth" then
            piece = g.neg and L["Priority Cond Unstealthed"] or L["Priority Cond Stealthed"]
        elseif (g.t == "resource" or g.t == "power") and g.op and g.n then
            piece = string.format("%s %s %d", g.res or "?", g.op, g.n)
        elseif g.t == "execute" and g.pct then
            piece = string.format(L["Priority Cond Execute"], g.pct)
        elseif g.t == "health" and g.pct then
            piece = string.format(L["Priority Cond Health"], g.pct)
        elseif g.t == "stack" and g.n then
            piece = string.format(L["Priority Cond Stacks"], g.n)
        elseif g.t == "dot" then
            piece = L["Priority Cond Dot"]
        elseif g.t == "cd" then
            piece = L["Priority Cond Cd"]
        end
        if piece then parts[#parts + 1] = piece end
    end
    if #parts == 0 then return L["Priority Cond None"] end
    return table.concat(parts, " \194\183 ")   -- middle dot
end

--- Anything that edits the list routes through here: one place that refreshes the queue
--- and the panel, so a new control cannot forget half of it.
function PriorityList.Changed(addon)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    if SpellQueue and SpellQueue.InvalidateRotationCache then SpellQueue.InvalidateRotationCache(true) end
    local CustomQueue = LibStub("JustAC-OptionsCustomQueue", true)
    if CustomQueue and CustomQueue.UpdateCustomQueueOptions and addon then
        CustomQueue.UpdateCustomQueueOptions(addon)
    end
    if addon and addon.ForceUpdateAll then addon:ForceUpdateAll() end
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
end

--------------------------------------------------------------------------------
-- The widget
--------------------------------------------------------------------------------
local function Tooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeButton(parent, label, tip, onClick, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 22, 18)
    b:SetText(label)
    local fs = b:GetFontString()
    if fs then fs:SetFont(fs:GetFont(), 10, "") end
    b:SetScript("OnClick", onClick)
    Tooltip(b, tip)
    return b
end

--- One tab, in Blizzard's own options-tab art - the same three-slice the Ace tab container
--- uses, so the strip belongs to the panel instead of imitating it.
local ACTIVE_TAB = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab"
local INACTIVE_TAB = "Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab"
local function MakeTab(parent, label)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(TAB_H)
    tab:SetNormalFontObject("GameFontNormalSmall")
    tab:SetHighlightFontObject("GameFontHighlightSmall")
    tab:SetText(label)
    local slices = {}
    for i, cut in ipairs({ { 0, 0.15625, 20 }, { 0.15625, 0.84375, 0 }, { 0.84375, 1, 20 } }) do
        local t = tab:CreateTexture(nil, "BORDER")
        t:SetTexCoord(cut[1], cut[2], 0, 1)
        t:SetHeight(TAB_H)
        if cut[3] > 0 then t:SetWidth(cut[3]) end
        -- The end caps pin to the tab's own corners and the middle spans BETWEEN them.
        -- Anchoring the right cap to the middle as well made each depend on the other,
        -- which the layout engine refuses outright ("cannot anchor to a region dependent
        -- on it") - and the throw came from inside Ace's tree, taking the tab with it.
        if i == 1 then
            t:SetPoint("BOTTOMLEFT")
        elseif i == 3 then
            t:SetPoint("BOTTOMRIGHT")
        end
        slices[i] = t
    end
    slices[2]:SetPoint("LEFT", slices[1], "RIGHT")
    slices[2]:SetPoint("RIGHT", slices[3], "LEFT")
    tab.slices = slices
    -- "This is the one the queue is using." Anchored to the LABEL, not to a corner of the
    -- tab: the label shifts a pixel when a tab is selected, and a corner-pinned dot drifted
    -- away from the text and read as floating debris above the strip.
    tab.liveDot = tab:CreateTexture(nil, "OVERLAY")
    tab.liveDot:SetSize(10, 10)
    tab.liveDot:SetPoint("RIGHT", tab:GetFontString(), "LEFT", -4, 0)
    -- Blizzard's own round status indicator: a flat colour swatch read as a stray square.
    tab.liveDot:SetTexture("Interface\\COMMON\\Indicator-Green")
    --- Label plus how many abilities that source holds. Re-measured because the count
    --- changes as a list is edited.
    function tab:SetLabel(text)
        self:SetText(text)
        self:SetWidth((self:GetFontString() and self:GetFontString():GetStringWidth() or 40) + 50)
    end
    tab:SetLabel(label)
    function tab:SetSelected(on)
        for _, t in ipairs(self.slices) do t:SetTexture(on and ACTIVE_TAB or INACTIVE_TAB) end
        self:SetNormalFontObject(on and "GameFontNormalSmall" or "GameFontDisableSmall")
        -- Blizzard's art draws the selected tab two pixels taller; matching it is what
        -- makes the strip read as tabs rather than buttons.
        self:GetFontString():SetPoint("CENTER", self.liveDot:IsShown() and 5 or 0, on and -1 or -2)
    end
    return tab
end

--- Settings for the open row, drawn INSIDE the list so they appear under that ability
--- rather than below the whole table. One strip, re-bound as the open row changes; the
--- controls are Ace's own, so the look and the keyboard behaviour come free.
local function BuildDetail(widget, parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetHeight(DETAIL_H)
    d.bg = d:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAllPoints()
    d.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
    d.edge = d:CreateTexture(nil, "ARTWORK")
    d.edge:SetPoint("TOPLEFT")
    d.edge:SetPoint("BOTTOMLEFT")
    d.edge:SetWidth(2)
    d.edge:SetColorTexture(unpack(GOLD))

    local function checkbox(label, field, defaultOn, x)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetWidth(150)
        cb.frame:SetParent(d)
        cb.frame:SetPoint("LEFT", d, "LEFT", x, 0)
        cb.frame:Show()
        cb:SetCallback("OnValueChanged", function(_, _, val)
            local Abilities = LibStub("JustAC-OptionsAbilities", true)
            local profile = widget.addon and widget.addon:GetProfile()
            local s = d.spellID and profile and Abilities and Abilities.SpellSettings
                and Abilities.SpellSettings(profile, d.spellID, true)
            if not s then return end
            -- Explicit if/else, never `(not val) and false or nil`: that idiom cannot
            -- produce false, so a default-ON box could not be unchecked at all
            -- (Options/Abilities.lua documents the same bug from a user report).
            if defaultOn then
                if val then s[field] = nil else s[field] = false end
            else
                if val then s[field] = true else s[field] = nil end
            end
            PriorityList.Changed(widget.addon)
        end)
        return cb
    end

    d.always = checkbox(L["Always Show"], "alwaysShow", false, 40)
    d.proc = checkbox(L["Custom Queue Procs First"], "procPriority", true, 190)

    -- The dial reuses the option control's own values/get/set, so the widget never owns a
    -- second copy of what the modes mean.
    d.hold = AceGUI:Create("Dropdown")
    d.hold:SetLabel(L["Hold Until"])
    d.hold:SetWidth(150)
    d.hold.frame:SetParent(d)
    -- Right-anchored: a fixed left offset pushed it past the pane on a narrow panel.
    d.hold.frame:SetPoint("RIGHT", d, "RIGHT", -8, -6)
    d.hold.frame:Show()

    --- Re-bind to one ability. The dropdown's LIST is rebuilt only when the ability
    --- changes: rebuilding it closes an open menu, and a refresh can fire from a resize.
    d.Rebind = function(spellID)
        local changed = (d.spellID ~= spellID)
        d.spellID = spellID
        if not spellID then return end
        local Abilities = LibStub("JustAC-OptionsAbilities", true)
        local profile = widget.addon and widget.addon:GetProfile()
        local s = profile and Abilities and Abilities.SpellSettings
            and Abilities.SpellSettings(profile, spellID, false)
        d.always:SetValue(s and s.alwaysShow == true or false)
        d.proc:SetValue(not s or s.procPriority ~= false)

        local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
        local ctl = SpellSearch and SpellSearch.HoldModeControl
            and SpellSearch.HoldModeControl(widget.addon, spellID, 1)
        if not ctl then d.hold.frame:Hide() return end
        d.hold.frame:Show()
        if changed then
            d.hold:SetList(ctl.values(), ctl.sorting and ctl.sorting() or nil)
            d.hold:SetCallback("OnValueChanged", function(_, _, key)
                ctl.set(nil, key)
                PriorityList.Changed(widget.addon)
            end)
        end
        d.hold:SetValue(ctl.get())
        d.hold:SetDisabled(ctl.disabled and ctl.disabled() or false)
    end
    return d
end

local function AcquireRow(self, index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, self.content)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.idx = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.idx:SetPoint("LEFT", 6, 0)
    row.idx:SetWidth(20)
    row.idx:SetJustifyH("RIGHT")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row.idx, "RIGHT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Everything below is anchored and coloured ONCE: only the row's own position, its
    -- text and the two column widths change per refresh.
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetTextColor(unpack(INK))

    row.cond = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.cond:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.cond:SetJustifyH("LEFT")
    -- Never wrap: the row is a fixed 26px, and a second line silently broke the grid.
    row.cond:SetWordWrap(false)
    row.cond:SetTextColor(unpack(INK_DIM))

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetWidth(40)
    row.rank:SetJustifyH("RIGHT")

    row.rank:SetTextColor(unpack(BLUE))

    row.remove = MakeButton(row, "x", L["Remove"], function()
        local list = self:List()
        if not (list and list[row.index]) then return end
        table.remove(list, row.index)
        if PriorityList.selected == row.id then PriorityList.selected = nil end
        PriorityList.Changed(self.addon)
    end)
    row.edit = MakeButton(row, "...", L["Priority Edit Tip"], function()
        PriorityList.selected = (PriorityList.selected == row.id) and nil or row.id
        PriorityList.Changed(self.addon)
    end)
    row.down = MakeButton(row, "v", L["Move down desc"], function()
        local list, i = self:List(), row.index
        if not list or i >= #list then return end
        list[i + 1], list[i] = list[i], list[i + 1]
        PriorityList.Changed(self.addon)
    end)
    row.up = MakeButton(row, "^", L["Move up desc"], function()
        local list, i = self:List(), row.index
        if not list or i <= 1 then return end
        list[i - 1], list[i] = list[i], list[i - 1]
        PriorityList.Changed(self.addon)
    end)
    row.remove:SetPoint("RIGHT", -4, 0)
    -- Anchored to the buttons, not to the text: a hidden frame keeps its position, so the
    -- rank lands in the same place whether the row is editable or read-only.
    row.edit:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.down:SetPoint("RIGHT", row.edit, "LEFT", -2, 0)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.rank:SetPoint("RIGHT", row.up, "LEFT", -6, 0)

    self.rows[index] = row
    return row
end

local methods = {}

function methods:OnAcquire()
    self.addon = Addon()
    self.disabled = false
    self:SetHeight(TAB_H + HEAD_H + PIN_H + GAP + 10)
    self:SetWidth(560)
    self:Refresh()
end

function methods:OnRelease()
    -- Widgets are pooled: anything left here is inherited by the next option that mounts
    -- this type.
    self.addon, self.disabled = nil, false
end

-- AceConfigDialog drives a description control with SetText/SetFontObject, and every
-- control with SetDisabled. The list draws itself, so the option's own text is unused.
function methods:SetText() end
function methods:SetFontObject() end
function methods:SetDisabled(disabled)
    self.disabled = disabled and true or false
    -- Ace sets the width (which refreshes) BEFORE disabled, so without this pass the
    -- buttons would keep the previous answer.
    self:Refresh()
end

function methods:OnWidthSet() self:Refresh() end

--- The editable array behind the current view, or nil when previewing a source the player
--- does not own.
function methods:List()
    if self:Source() ~= "custom" then return nil end
    local cq = CustomQueueFor(self.addon and self.addon:GetProfile())
    return cq and cq.spells or nil
end

function methods:Source()
    -- Module state, not instance state: editing anything rebuilds the options table, which
    -- releases and re-acquires this widget. Kept on the instance, the previewed tab was
    -- lost on every click and the panel jumped back to whichever source is live.
    return PriorityList.CurrentSource(self.addon and self.addon:GetProfile())
end

function methods:Refresh()
    if not self.addon then return end
    local profile = self.addon:GetProfile()
    local source, live = self:Source(), PriorityList.LiveSource(profile)
    local cq = CustomQueueFor(profile)
    local haveList = cq and cq.spells and #cq.spells > 0
    local leads = (cq and cq.enabled and cq.myListLeads == true) or false
    local editable = (source == "custom") and not self.disabled

    for key, tab in pairs(self.tabs) do
        tab:SetLabel(string.format("%s (%d)", tab.baseLabel, PriorityList.CountFor(self.addon, key)))
        tab.liveDot:SetShown(key == live)   -- before SetSelected: it re-centres around the dot
        tab:SetSelected(key == source)
        Tooltip(tab, key == live and L["Priority Tab Live Tip"] or L["Priority Tab Preview Tip"])
    end

    -- Position 1. The row the whole panel exists to explain: with the list leading it is
    -- contested, otherwise it is simply the game's and the list below starts at 2.
    self.pin.lock:SetVertexColor(unpack(leads and GOLD or GREEN))
    self.pin.title:SetText(leads and L["Priority Pin Contested"] or L["Priority Pin Blizzard"])
    self.pin.title:SetTextColor(unpack(leads and GOLD or GREEN))
    self.pin.note:SetText(leads and L["Priority Pin Contested Note"] or L["Priority Pin Blizzard Note"])
    self.pin.bg:SetColorTexture(leads and 0.20 or 0.11, leads and 0.16 or 0.20, 0.09, 1)

    local rows = PriorityList.Rows(self.addon, source)
    -- Share the free width between the two text columns rather than fixing the condition
    -- and giving the name whatever is left: ability names run long in every language.
    local free = math.max(200, (self.frame:GetWidth() or 560) - ROW_FIXED)
    local nameW = math.floor(free * 0.46)
    local condW = free - nameW
    local y = -(TAB_H + HEAD_H + PIN_H + GAP + 4)
    local detailShown = false

    for i = 1, #rows do
        local data = rows[i]
        local row = AcquireRow(self, i)
        row.index, row.id = i, data.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 5, y)
        row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -5, y)
        row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)
        row.idx:SetText(i + (leads and 0 or 1))
        row.icon:SetTexture(data.icon)
        row.name:SetText(data.name)
        row.name:SetWidth(nameW)
        row.cond:SetText(data.cond or "")
        row.cond:SetTextColor(unpack(data.upkeep and GOLD or INK_DIM))
        row.cond:SetWidth(condW)
        row.rank:SetText(data.rank and ("#" .. data.rank) or "")
        for _, b in ipairs({ row.up, row.down, row.edit, row.remove }) do b:SetShown(editable) end
        row:Show()
        y = y - ROW_H

        -- The open ability's settings belong under IT, inside the list - not below the
        -- whole table, where the row they belong to has scrolled out of sight.
        if editable and PriorityList.selected == data.id and data.id > 0 then
            detailShown = true
            self.detail:ClearAllPoints()
            self.detail:SetPoint("TOPLEFT", self.content, "TOPLEFT", 5, y)
            self.detail:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -5, y)
            self.detail.Rebind(data.id)
            self.detail:Show()
            y = y - DETAIL_H
        end
    end
    for i = #rows + 1, #self.rows do self.rows[i]:Hide() end
    if not detailShown then
        self.detail:Hide()
        self.detail.spellID = nil   -- so reopening the same row rebuilds its dial
    end

    -- Actions. Previewing a source you do not use offers to take it; your own list offers
    -- to start over. Both are the same button slot, so the strip never grows.
    self.starting = (source ~= "custom") and not haveList
    self.useThis:SetShown(not self.disabled and (self.starting or source ~= live))
    self.useThis:SetText(self.starting and L["Priority Start From"] or L["Priority Use Source"])
    self.useThis:SetWidth(self.starting and 160 or 116)
    self.clear:SetShown(not self.disabled and source == "custom" and haveList)

    self.emptyNote:SetShown(source == "custom" and not haveList)
    self.emptyNote:SetText(L["Priority Empty Hint"])

    -- Only the columns that follow the resizing name field actually move.
    self.head:SetShown(#rows > 0)
    if #rows > 0 then
        self.head.cond:ClearAllPoints()
        self.head.cond:SetPoint("LEFT", self.head, "LEFT", 55 + nameW + 8, 0)
        self.head.rank:ClearAllPoints()
        self.head.rank:SetPoint("RIGHT", self.head, "RIGHT", editable and -104 or -6, 0)
    end

    -- +10: the pane's own top and bottom border insets.
    self:SetHeight(TAB_H + HEAD_H + PIN_H + GAP + 10 + (#rows * ROW_H)
        + (detailShown and DETAIL_H or 0) + ((#rows == 0) and 28 or 4))
end

--------------------------------------------------------------------------------
local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()

    local widget = { frame = frame, type = Type, rows = {}, tabs = {} }
    for method, func in pairs(methods) do widget[method] = func end

    -- The list needs a pane for the tabs to sit ON, or they float over the panel with
    -- nothing joining them to the rows. Ace's own inline-group backdrop, so the pane
    -- matches every other bordered group around it; the tab strip then overlaps its top
    -- edge by two pixels, which is what reads as "joined".
    local body = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(TAB_H - 2))
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    body:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    body:SetBackdropColor(0.09, 0.085, 0.07, 1)
    body:SetBackdropBorderColor(0.4, 0.4, 0.4)
    widget.body = body

    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints()
    -- Above the tabs, below the rows: the pane is what hides each tab's lower edge, and
    -- the rows must still draw on top of the pane.
    body:SetFrameLevel(frame:GetFrameLevel() + 2)
    content:SetFrameLevel(body:GetFrameLevel() + 1)
    widget.content = content

    -- Tab strip: the source the list is showing. Switching tabs PREVIEWS a source;
    -- committing is the separate button, so a comparison never changes the queue by
    -- accident.
    local defs = {
        { "blizzard", L["Priority Tab Blizzard"] },
        { "simc", L["Priority Tab Simc"] },
        { "custom", L["Priority Tab Custom"] },
    }
    local prev
    for _, def in ipairs(defs) do
        local key, label = def[1], def[2]
        local tab = MakeTab(frame, label)
        tab:SetPoint("BOTTOMLEFT", prev or body, prev and "BOTTOMRIGHT" or "TOPLEFT",
            prev and -6 or 6, prev and 0 or -5)
        tab:SetFrameLevel(math.max(0, body:GetFrameLevel() - 1))
        tab:SetScript("OnClick", function()
            PriorityList.view = key
            widget:Refresh()
        end)
        tab.baseLabel = label
        widget.tabs[key] = tab
        prev = tab
    end

    widget.useThis = MakeButton(frame, "", "", function()
        if widget.starting then
            PriorityList.StartFrom(widget.addon, widget:Source())
        else
            PriorityList.SetLiveSource(widget.addon, widget:Source())
        end
        PriorityList.view = nil
        widget:Refresh()
    end, 116)
    widget.useThis:SetHeight(20)
    widget.useThis:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -3)

    widget.clear = MakeButton(frame, L["Priority Clear"], L["Priority Clear desc"], function()
        PriorityList.ClearList(widget.addon)
        PriorityList.view = nil
        widget:Refresh()
    end, 92)
    widget.clear:SetHeight(20)
    widget.clear:SetPoint("RIGHT", widget.useThis, "LEFT", -4, 0)

    -- Column header. Its moving labels are re-anchored in Refresh, so a name column that
    -- resizes with the panel cannot drift away from its heading.
    local head = CreateFrame("Frame", nil, frame)
    head:SetHeight(HEAD_H)
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -(TAB_H + 4))
    head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -(TAB_H + 4))
    local function headLabel(text, justify)
        local fs = head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetText(text)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end
    head.slot = headLabel(L["Priority Head Slot"], "RIGHT")
    head.slot:SetPoint("LEFT", head, "LEFT", 6, 0)
    head.slot:SetWidth(20)
    head.name = headLabel(L["Priority Head Ability"])
    head.name:SetPoint("LEFT", head, "LEFT", 55, 0)
    head.cond = headLabel(L["Priority Head When"])
    head.rank = headLabel(L["Priority Head Rank"], "RIGHT")
    head.rank:SetWidth(40)
    head.rule = head:CreateTexture(nil, "ARTWORK")
    head.rule:SetHeight(1)
    head.rule:SetPoint("BOTTOMLEFT", 4, 0)
    head.rule:SetPoint("BOTTOMRIGHT", -4, 0)
    head.rule:SetColorTexture(1, 1, 1, 0.08)
    widget.head = head

    -- Position-1 row, always present, never editable.
    local pin = CreateFrame("Frame", nil, frame)
    pin:SetHeight(PIN_H - GAP)
    pin:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -(TAB_H + HEAD_H + 4))
    pin:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -(TAB_H + HEAD_H + 4))
    pin.bg = pin:CreateTexture(nil, "BACKGROUND")
    pin.bg:SetAllPoints()
    pin.num = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.num:SetPoint("LEFT", 6, 0)
    pin.num:SetWidth(20)
    pin.num:SetJustifyH("RIGHT")
    pin.num:SetText("1")
    pin.lock = pin:CreateTexture(nil, "ARTWORK")
    pin.lock:SetSize(12, 14)
    pin.lock:SetTexture(LOCK_TEXTURE)
    pin.lock:SetPoint("LEFT", pin.num, "RIGHT", 8, 0)
    pin.title = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.title:SetPoint("LEFT", pin.lock, "RIGHT", 7, 0)
    pin.note = pin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pin.note:SetPoint("LEFT", pin.title, "RIGHT", 8, 0)
    pin.note:SetPoint("RIGHT", -6, 0)
    pin.note:SetJustifyH("LEFT")
    pin.note:SetWordWrap(false)
    widget.pin = pin

    widget.emptyNote = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.emptyNote:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(TAB_H + HEAD_H + PIN_H + 6))
    widget.emptyNote:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    widget.emptyNote:SetJustifyH("LEFT")

    widget.detail = BuildDetail(widget, content)
    widget.detail:Hide()

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
