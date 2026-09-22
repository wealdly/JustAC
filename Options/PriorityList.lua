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
-- What it deliberately does NOT draw: the per-entry settings. Those stay Ace controls,
-- emitted by Options/CustomQueue.lua for the selected row, so the toggles, dials and
-- their get/set logic are not reimplemented here.
local Type, Version = "JustACPriorityList", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local PriorityList = LibStub:NewLibrary("JustAC-PriorityList", 1)
if not PriorityList then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local CreateFrame, UIParent = CreateFrame, UIParent

local ROW_H, PIN_H, TAB_H, GAP = 26, 30, 26, 4
local LOCK_TEXTURE = "Interface\\Buttons\\LockButton-Locked-Up"

-- Ace's own dialog colors, so the list reads as part of the panel rather than a guest.
local INK        = { 0.93, 0.90, 0.85 }
local INK_DIM    = { 0.66, 0.62, 0.55 }
local GOLD       = { 0.85, 0.65, 0.34 }
local GREEN      = { 0.62, 0.79, 0.50 }
local BLUE       = { 0.44, 0.62, 0.85 }

--------------------------------------------------------------------------------
-- Model: what the list shows, derived from the profile and the imported data.
--------------------------------------------------------------------------------
local function Addon() return LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
local function SpecKey()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey() or nil
end

--- Which source the QUEUE is using right now: the custom list, the imported priority, or
--- the game's own order. One reading for the tab strip and the "use this" button.
function PriorityList.LiveSource(profile)
    local specKey = SpecKey()
    local cq = specKey and profile and profile.customQueue and profile.customQueue[specKey]
    if cq and cq.enabled then return "custom" end
    return (profile and profile.contextOrder or "simc") == "simc" and "simc" or "blizzard"
end

--- Point the queue at a source. The two settings that decide it are written together, so
--- a player comparing sources flips one control instead of remembering the pair.
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

--- Copy the source the player is LOOKING AT into their own list, and switch to it. This is
--- how a list begins: there is no blank-page state to explain, and the order they just
--- compared is the order they get. The baseline is the game's pool as it stands now, so the
--- "new abilities since you made this" notice keeps working.
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
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local pool = BlizzardAPI and BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()
    cq.baseline = {}
    for i = 1, #(pool or {}) do cq.baseline[i] = pool[i] end
    cq.enabled = true
    PriorityList.Changed(addon)
end

--- The entries of one source, newest profile state each call (cheap: options are cold).
--- Returns an array of { id, name, icon, rank, cond, gameTimed }.
function PriorityList.Rows(addon, source)
    local out = {}
    local profile = addon and addon:GetProfile()
    local specKey = SpecKey()
    if not (profile and specKey) then return out end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local RI = LibStub("JustAC-RotationImport", true)
    if not BlizzardAPI then return out end

    local ids
    if source == "custom" then
        local cq = profile.customQueue and profile.customQueue[specKey]
        ids = (cq and cq.spells) or {}
    else
        ids = (BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()) or {}
    end

    -- The imported priority sorts the "simc" view; the game's own step order sorts
    -- "blizzard". A custom list is the player's order and is never re-sorted here.
    local order = {}
    for i = 1, #ids do order[i] = ids[i] end
    if source ~= "custom" and RI then
        local key = {}
        for _, id in ipairs(order) do
            local rec = RI.GetEntry and RI.GetEntry(id, "st")
            if source == "simc" then
                key[id] = (rec and rec.rank) or (1000 + ((RI.GetBlizzardRank and RI.GetBlizzardRank(id)) or 999))
            else
                key[id] = (RI.GetBlizzardRank and RI.GetBlizzardRank(id)) or 999
            end
        end
        table.sort(order, function(a, b)
            if key[a] ~= key[b] then return (key[a] or 999) < (key[b] or 999) end
            return a < b
        end)
    end

    for i = 1, #order do
        local id = order[i]
        local info = BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(id)
        local rec = RI and RI.GetEntry and RI.GetEntry(id, "st")
        out[i] = {
            id = id,
            name = (info and info.name) or tostring(id),
            icon = (info and info.iconID) or 134400,
            rank = rec and rec.rank or nil,
            -- Only the game can time a delegated entry, and an entry the imported data
            -- does not rank at all is in the same position: nothing here knows its moment.
            gameTimed = (rec == nil) or (rec.delegated == true),
            cond = PriorityList.Condition(rec),
        }
    end
    return out
end

--- One line of plain words for an entry's conditions, or nil when it has none we read.
function PriorityList.Condition(rec)
    if not rec then return L["Priority Cond Unknown"] end
    local gates = rec.gates
    if not gates or #gates == 0 then return L["Priority Cond None"] end
    local parts = {}
    for i = 1, #gates do
        local g = gates[i]
        local piece
        if g.t == "buff" and g.id then
            local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
            local info = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(g.id)
            local nm = (info and info.name) or tostring(g.id)
            piece = string.format(g.neg and L["Priority Cond Not During"] or L["Priority Cond During"], nm)
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
local function MakeButton(parent, label, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(22, 18)
    b:SetText(label)
    local fs = b:GetFontString()
    if fs then fs:SetFont(fs:GetFont(), 10, "") end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
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

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.name:SetJustifyH("LEFT")

    row.cond = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.cond:SetJustifyH("LEFT")
    row.cond:SetWidth(190)

    row.lock = row:CreateTexture(nil, "ARTWORK")
    row.lock:SetSize(12, 14)
    row.lock:SetTexture(LOCK_TEXTURE)
    row.lock:SetVertexColor(unpack(GOLD))

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetWidth(44)
    row.rank:SetJustifyH("RIGHT")

    -- Hovering the lock explains the one thing users misread about the queue.
    row.lockHit = CreateFrame("Frame", nil, row)
    row.lockHit:SetSize(16, ROW_H)
    row.lockHit:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Priority Locked Tip"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.lockHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.up = MakeButton(row, "^", L["Move up desc"], function()
        local i = row.index
        local list = self:List()
        if not list or i <= 1 then return end
        list[i - 1], list[i] = list[i], list[i - 1]
        PriorityList.Changed(self.addon)
    end)
    row.down = MakeButton(row, "v", L["Move down desc"], function()
        local i = row.index
        local list = self:List()
        if not list or i >= #list then return end
        list[i + 1], list[i] = list[i], list[i + 1]
        PriorityList.Changed(self.addon)
    end)
    row.edit = MakeButton(row, "...", L["Priority Edit Tip"], function()
        -- The settings themselves stay Ace controls: this only says which entry the
        -- option table should render them for.
        PriorityList.selected = (PriorityList.selected == row.id) and nil or row.id
        PriorityList.Changed(self.addon)
    end)
    row.remove = MakeButton(row, "x", L["Remove"], function()
        local i = row.index
        local list = self:List()
        if not list or not list[i] then return end
        table.remove(list, i)
        if PriorityList.selected == row.id then PriorityList.selected = nil end
        PriorityList.Changed(self.addon)
    end)

    self.rows[index] = row
    return row
end

local methods = {}

function methods:OnAcquire()
    self.addon = Addon()
    self.view = nil
    self:SetHeight(TAB_H + PIN_H + GAP)
    self:SetWidth(560)
    self:Refresh()
end

function methods:OnRelease()
    self.addon, self.view = nil, nil
end

-- AceConfigDialog drives a description control with these; the list draws itself, so the
-- option's own name and image are not used. Tolerant no-ops keep the mount type flexible.
function methods:SetText() end
function methods:SetLabel() end
function methods:SetFontObject() end
function methods:SetImage() end
function methods:SetImageSize() end
function methods:SetColor() end
function methods:SetDisabled(disabled) self.disabled = disabled and true or false end

function methods:OnWidthSet() self:Refresh() end

--- The editable array behind the current view, or nil when the view is a preview of a
--- source the player does not own (the game's list, the imported one).
function methods:List()
    if self:Source() ~= "custom" then return nil end
    local profile = self.addon and self.addon:GetProfile()
    local specKey = SpecKey()
    local cq = profile and specKey and profile.customQueue and profile.customQueue[specKey]
    return cq and cq.spells or nil
end

function methods:Source()
    if self.view then return self.view end
    local profile = self.addon and self.addon:GetProfile()
    return PriorityList.LiveSource(profile)
end

function methods:Refresh()
    if not self.addon then return end
    local source = self:Source()
    local profile = self.addon:GetProfile()
    local live = PriorityList.LiveSource(profile)
    local specKey = SpecKey()
    local cq = specKey and profile and profile.customQueue and profile.customQueue[specKey]
    local leads = (cq and cq.enabled and cq.myListLeads == true) or false
    local editable = (source == "custom")

    -- Tabs
    for key, tab in pairs(self.tabs) do
        local on = (key == source)
        tab:SetNormalFontObject(on and "GameFontNormalSmall" or "GameFontDisableSmall")
        tab.underline:SetShown(on)
        tab.liveDot:SetShown(key == live)
    end

    -- Position 1. The row the whole panel exists to explain: with the list leading it is
    -- contested, otherwise it is simply the game's and the list below starts at 2.
    self.pin.lock:SetVertexColor(unpack(leads and GOLD or GREEN))
    self.pin.title:SetText(leads and L["Priority Pin Contested"] or L["Priority Pin Blizzard"])
    self.pin.title:SetTextColor(unpack(leads and GOLD or GREEN))
    self.pin.note:SetText(leads and L["Priority Pin Contested Note"] or L["Priority Pin Blizzard Note"])
    self.pin.bg:SetColorTexture(leads and 0.17 or 0.11, leads and 0.14 or 0.18, 0.09, 0.55)

    local rows = PriorityList.Rows(self.addon, source)
    local width = self.frame:GetWidth() or 560
    local y = -(TAB_H + PIN_H + GAP)
    local start = leads and 1 or 2

    for i = 1, #rows do
        local data = rows[i]
        local row = AcquireRow(self, i)
        row.index, row.id = i, data.id
        row:SetParent(self.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, y)
        row.bg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.18 or 0.08)
        row.idx:SetText(i + start - 1)
        row.icon:SetTexture(data.icon)
        row.name:SetText(data.name)
        row.name:SetTextColor(unpack(INK))
        row.name:SetWidth(math.max(80, width - 430))
        row.cond:SetText(data.cond or "")
        row.cond:SetTextColor(unpack(INK_DIM))
        row.cond:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.lock:SetShown(data.gameTimed)
        row.lock:SetPoint("LEFT", row.cond, "RIGHT", 6, 0)
        row.lockHit:SetPoint("LEFT", row.cond, "RIGHT", 4, 0)
        row.lockHit:SetShown(data.gameTimed)
        row.rank:SetText(data.rank and ("#" .. data.rank) or "")
        row.rank:SetTextColor(unpack(BLUE))
        row.rank:SetPoint("LEFT", row.lock, "RIGHT", 6, 0)

        row.remove:SetPoint("RIGHT", -4, 0)
        row.edit:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
        row.down:SetPoint("RIGHT", row.edit, "LEFT", -2, 0)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        for _, b in ipairs({ row.up, row.down, row.edit, row.remove }) do
            b:SetShown(editable and not self.disabled)
        end
        row.edit:SetShown(editable and not self.disabled)
        row:Show()
        y = y - ROW_H
    end
    for i = #rows + 1, #self.rows do self.rows[i]:Hide() end

    -- One button, three states: an empty list starts FROM what is on screen, a list that
    -- exists is switched to, and the source already live needs no button at all.
    local haveList = cq and cq.spells and #cq.spells > 0
    self.starting = (source ~= "custom") and not haveList
    self.useThis:SetShown(not self.disabled and (self.starting or source ~= live))
    self.useThis:SetText(self.starting and L["Priority Start From"] or L["Priority Use Source"])
    self.useThis:SetWidth(self.starting and 150 or 110)
    self.useThis:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -2)

    -- An empty own-list is the one view with nothing to draw: say where a list comes from.
    self.emptyNote:SetShown(source == "custom" and not haveList)
    self.emptyNote:SetText(L["Priority Empty Hint"])

    self:SetHeight(TAB_H + PIN_H + GAP + (#rows * ROW_H) + ((#rows == 0) and 28 or 4))
end

--------------------------------------------------------------------------------
local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()

    local widget = { frame = frame, type = Type, rows = {}, tabs = {} }
    for method, func in pairs(methods) do widget[method] = func end

    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints()
    widget.content = content

    -- Tab strip: the source the list is showing. Switching tabs PREVIEWS a source;
    -- committing is the separate button, so a comparison never changes the queue by
    -- accident.
    local defs = { { "blizzard", L["Priority Tab Blizzard"] }, { "simc", L["Priority Tab Simc"] }, { "custom", L["Priority Tab Custom"] } }
    local prev
    for _, def in ipairs(defs) do
        local key, label = def[1], def[2]
        local tab = CreateFrame("Button", nil, frame)
        tab:SetHeight(TAB_H - 4)
        tab:SetNormalFontObject("GameFontDisableSmall")
        tab:SetText(label)
        tab:SetWidth((tab:GetFontString() and tab:GetFontString():GetStringWidth() or 40) + 26)
        tab:SetPoint("TOPLEFT", prev or frame, prev and "TOPRIGHT" or "TOPLEFT", prev and 2 or 0, prev and 0 or -2)
        tab.underline = tab:CreateTexture(nil, "ARTWORK")
        tab.underline:SetHeight(2)
        tab.underline:SetPoint("BOTTOMLEFT", 6, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -6, 0)
        tab.underline:SetColorTexture(unpack(GOLD))
        tab.liveDot = tab:CreateTexture(nil, "ARTWORK")
        tab.liveDot:SetSize(5, 5)
        tab.liveDot:SetPoint("TOPRIGHT", -4, -3)
        tab.liveDot:SetColorTexture(unpack(GREEN))
        tab:SetScript("OnClick", function()
            widget.view = key
            widget:Refresh()
        end)
        widget.tabs[key] = tab
        prev = tab
    end

    widget.useThis = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    widget.useThis:SetSize(120, 20)
    widget.useThis:SetScript("OnClick", function()
        if widget.starting then
            PriorityList.StartFrom(widget.addon, widget:Source())
        else
            PriorityList.SetLiveSource(widget.addon, widget:Source())
        end
        widget.view = nil
        widget:Refresh()
    end)

    widget.emptyNote = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.emptyNote:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(TAB_H + PIN_H + 6))
    widget.emptyNote:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    widget.emptyNote:SetJustifyH("LEFT")

    -- Position-1 row, always present, never editable.
    local pin = CreateFrame("Frame", nil, frame)
    pin:SetHeight(PIN_H - GAP)
    pin:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TAB_H)
    pin:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -TAB_H)
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
    widget.pin = pin

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
