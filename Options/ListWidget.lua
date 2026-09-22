-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: the rows every ability list in the panel is drawn with. One 26px line per entry:
-- number, the ability seated in an action button, its name, one right-hand column, and
-- settings / remove buttons. Rows drag to reorder, and the open entry's settings draw
-- under it rather than below the whole list.
--
-- Two widgets are built from these. The priority list (Options/PriorityList.lua) adds its
-- tabs, the pinned first slot and the comparison columns; the plain list
-- (Options/SpellLists.lua) is what every other list tab mounts. What a row does is here,
-- once, so a fix to a row is a fix to every list.
--
-- A widget using these rows provides:
--   widget.listKey             which list, for remembering the open entry
--   widget.ordered             false for a list whose order means nothing (no numbers, no drag)
--   widget:List()              the editable array, or nil when the view is read-only
--   widget:Commit()            after the list itself changes
--   widget:Reflow()            after a change that only moves things on screen
--   widget:RowTitle(row)       optional: set the hovered row's tooltip title
--   widget:RowTooltip(row)     optional: add lines under it
--   widget:OnRowCreated(row)   optional: add columns to a new row
--   widget:OnRemove(id)        optional: just before an entry is removed
--   widget:RemoveRequested(id) optional: take a removal over (to ask first); true = handled
--   widget:RowClickable()      optional: true when a left click on a row means something
--   widget:OnRowClick(id)      optional: that click
-- A LEFT click on a row with settings opens them under it (as its "..." does); a RIGHT
-- click opens that ability on the Overrides tab.
local ListWidget = LibStub:NewLibrary("JustAC-ListWidget", 1)
if not ListWidget then return end

local AceGUI = LibStub("AceGUI-3.0", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local CreateFrame = CreateFrame

local ROW_H, DETAIL_H = 26, 44
ListWidget.ROW_H, ListWidget.DETAIL_H = ROW_H, DETAIL_H

ListWidget.INK, ListWidget.INK_DIM = { 0.93, 0.90, 0.85 }, { 0.66, 0.62, 0.55 }
ListWidget.GOLD, ListWidget.GREEN = { 0.85, 0.65, 0.34 }, { 0.62, 0.79, 0.50 }
ListWidget.BLUE, ListWidget.RED = { 0.44, 0.62, 0.85 }, { 0.80, 0.47, 0.47 }
local INK, INK_DIM, GOLD, GREEN = ListWidget.INK, ListWidget.INK_DIM, ListWidget.GOLD, ListWidget.GREEN

-- A row's ability sits in an action button. The background plate alone is invisible
-- behind a filled icon, so the frame is drawn OVER the art; the game draws it a pixel
-- proud of the button so it frames the art instead of covering it.
ListWidget.BUTTON_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
ListWidget.BUTTON_FRAME_ATLAS = "UI-HUD-ActionBar-IconFrame"

function ListWidget.HasAtlas(atlas)
    return (C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(atlas) ~= nil) or false
end
local HasAtlas = ListWidget.HasAtlas

--- Can this entry be opened on the Abilities tab? Not the Emergency Potion entry: it stands
--- for whichever pot is best, so there is no one ability behind it.
function ListWidget.CanOpenAbility(id)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return type(id) == "number" and id ~= 0 and not (SpellDB and id == SpellDB.EMERGENCY_POTION)
end

--- Every setting an ability has, in one place: a list row shows only its own list's.
function ListWidget.OpenAbility(id)
    if not ListWidget.CanOpenAbility(id) then return end
    local Abilities = LibStub("JustAC-OptionsAbilities", true)
    if Abilities and Abilities.Open then Abilities.Open(id) end
end

--- Take `id` out of the widget's list. Found by id at the moment of removal rather than by
--- the row's position: a refresh the dialog has not drawn yet can have moved the row, and
--- acting on a position then removed whatever sat there instead.
function ListWidget.RemoveEntry(w, id)
    local key, list = w.listKey, w:List()
    local at
    for i = 1, (list and #list or 0) do
        if list[i] == id then at = i break end
    end
    if not at then return end
    if w.OnRemove then w:OnRemove(id) end
    table.remove(list, at)
    if ListWidget.selected[key] == id then ListWidget.selected[key] = nil end
    w:Commit()
end

--- The open entry per list. Module state, not widget state: any edit rebuilds the options
--- table, which releases the widget and mounts a fresh one from the pool, so anything kept
--- on the instance was forgotten on every click.
ListWidget.selected = {}

--- An options-table member: a function is called, anything else is the value.
local function Eval(v)
    if type(v) == "function" then return v() end
    return v
end

--- `body` adds a second line. `hook` is for a frame that already has an OnEnter of its
--- own - Ace's widgets use theirs for the highlight, so replacing it would trade one
--- cue for the other.
function ListWidget.Tooltip(frame, text, body, hook)
    if not frame then return end
    local bind = hook and frame.HookScript or frame.SetScript
    bind(frame, "OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        if body then GameTooltip:AddLine(body, 0.82, 0.78, 0.70, true) end
        GameTooltip:Show()
    end)
    bind(frame, "OnLeave", function() GameTooltip:Hide() end)
end
local Tooltip = ListWidget.Tooltip

function ListWidget.MakeButton(parent, label, tip, onClick, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 22, 18)
    b:SetText(label)
    local fs = b:GetFontString()
    if fs then fs:SetFont(fs:GetFont(), 10, "") end
    b:SetScript("OnClick", onClick)
    Tooltip(b, tip)
    return b
end
local MakeButton = ListWidget.MakeButton

--------------------------------------------------------------------------------
-- Settings strip
--------------------------------------------------------------------------------
-- Controls are described the way an options table describes them - type, name, desc,
-- get / set / func, values, sorting, disabled, hidden - so the ability card hands the SAME
-- description to Ace that a list row hands to this strip, and the two cannot drift. A
-- control's own set / func refreshes whatever it changed; the strip only draws it.
--
-- The Ace widgets are made once per strip and re-pointed at whichever entry is open,
-- never handed back to Ace's pool: a checkbox whose own click rebuilds the panel would
-- otherwise be released in the middle of its callback, and anything drawn onto a pooled
-- dropdown (the label inside it) would turn up on the next option that borrowed it.

--- Ask before doing something that is not easily undone. The dialog is raised above the
--- options panel, which otherwise covers it.
function ListWidget.Confirm(text, fn)
    StaticPopupDialogs["JUSTAC_LIST_CONFIRM"] = StaticPopupDialogs["JUSTAC_LIST_CONFIRM"] or {
        text = "%s",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function(dialog)
            if dialog.data and dialog.data.fn then dialog.data.fn() end
        end,
    }
    local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
    if UIFrameFactory then UIFrameFactory.ShowPopupAbove("JUSTAC_LIST_CONFIRM", { fn = fn }, text) end
end

local function ShowControlTip(c)
    local spec = c.spec
    if not spec then return end
    GameTooltip:SetOwner(c.frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(Eval(spec.name) or "", 1, 1, 1, 1, true)
    local desc = Eval(spec.desc)
    if desc then GameTooltip:AddLine(desc, 0.82, 0.78, 0.70, true) end
    GameTooltip:Show()
end

local function MakeControl(d, kind)
    local c
    if kind == "toggle" then
        c = AceGUI:Create("CheckBox")
        c:SetCallback("OnValueChanged", function(_, _, val)
            if c.spec and c.spec.set then c.spec.set(nil, val) end
        end)
    elseif kind == "execute" then
        c = AceGUI:Create("Button")
        c:SetHeight(20)
        c:SetCallback("OnClick", function()
            local spec = c.spec
            if not (spec and spec.func) then return end
            -- `confirm` as an options table has it: a question to ask first.
            local question = Eval(spec.confirm)
            if type(question) == "string" then
                ListWidget.Confirm(question, function() spec.func() end)
            else
                spec.func()
            end
        end)
    elseif kind == "input" then
        c = AceGUI:Create("EditBox")
        c:SetLabel("")
        c:SetCallback("OnEnterPressed", function(_, _, text)
            if c.spec and c.spec.set then c.spec.set(nil, text) end
        end)
    elseif kind == "text" then
        -- A line of words, not an Ace widget: one row, cut with "...", its full text in the
        -- tooltip. A frame around it so it can have one.
        local f = CreateFrame("Frame", nil, d)
        f:SetHeight(20)
        f:EnableMouse(true)
        c = { frame = f, SetDisabled = function() end }
        c.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.text:SetAllPoints()
        c.text:SetJustifyH("LEFT")
        c.text:SetWordWrap(false)
        f:SetScript("OnEnter", function() ShowControlTip(c) end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return c
    else
        c = AceGUI:Create("Dropdown")
        -- No label ON the widget: Ace stacks it above the control and grows the frame to
        -- 40, which leaves the control sitting low against checkboxes that are centred.
        -- The label lives INSIDE the closed control instead, on its left, with the value
        -- on the right where Ace already puts it.
        c:SetLabel("")
        c:SetCallback("OnValueChanged", function(_, _, key)
            if c.spec and c.spec.set then c.spec.set(nil, key) end
        end)
        local host = c.dropdown or c.frame
        c.inside = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        c.inside:SetTextColor(unpack(INK_DIM))
        -- The dropdown art's left cap eats the first 16 or so; this is the inset past it.
        c.inside:SetPoint("LEFT", host, "LEFT", 30, 0)
        c.inside:SetJustifyH("LEFT")
        c.inside:SetWordWrap(false)
    end
    c:SetCallback("OnEnter", ShowControlTip)
    c:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    c.frame:SetParent(d)
    return c
end

function ListWidget.BuildDetail(parent)
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
    d.made = { toggle = {}, execute = {}, select = {}, input = {}, text = {} }
    d.panelFrames = {}
    d:Hide()
    return d
end

--- Point the strip at one entry's controls. A dropdown's LIST is rebuilt only when the
--- entry changes: rebuilding it closes an open menu, and a refresh can fire from a resize.
function ListWidget.BindDetail(d, key, specs)
    local fresh = (d.key ~= key)
    d.key = key
    d:SetHeight(DETAIL_H)
    local used = { toggle = 0, execute = 0, select = 0, input = 0, text = 0 }
    local left, right = 40, -20
    for _, spec in ipairs(specs) do
        local kind = spec.type
        if used[kind] and not Eval(spec.hidden) then
            used[kind] = used[kind] + 1
            local c = d.made[kind][used[kind]]
            if not c then
                c = MakeControl(d, kind)
                d.made[kind][used[kind]] = c
            end
            c.spec = spec
            c.frame:SetParent(d)   -- a panel may have held it last
            c.frame:ClearAllPoints()
            if kind == "toggle" then
                c:SetLabel(Eval(spec.name) or "")
                -- 24 for the box itself, then whatever the words actually measure.
                local w = 24 + ((c.text and c.text:GetStringWidth()) or 120) + 8
                c:SetWidth(w)
                c:SetValue(spec.get and spec.get() or false)
                c.frame:SetPoint("LEFT", d, "LEFT", left, 0)
                left = left + w + 16
            elseif kind == "execute" then
                c:SetText(Eval(spec.name) or "")
                local w = ((c.text and c.text:GetStringWidth()) or 80) + 30
                c:SetWidth(w)
                c.frame:SetPoint("LEFT", d, "LEFT", left, 0)
                left = left + w + 8
            else
                c.inside:SetText(Eval(spec.name) or "")
                if fresh then
                    local list = Eval(spec.values) or {}
                    c:SetList(list, Eval(spec.sorting))
                    -- Wide enough for the label inside AND the longest value, so neither
                    -- runs into the other. Measured on the value text itself, which
                    -- SetValue below puts back.
                    local widest = 0
                    for _, text in pairs(list) do
                        c.text:SetText(text)
                        widest = math.max(widest, c.text:GetStringWidth() or 0)
                    end
                    c.fitW = 30 + (c.inside:GetStringWidth() or 60) + 12 + widest + 43
                end
                local w = math.min(300, math.max(150, c.fitW or 150))
                c:SetWidth(w)
                c:SetValue(spec.get and spec.get())
                -- Right-anchored: a fixed left offset pushed it past the pane when narrow.
                c.frame:SetPoint("RIGHT", d, "RIGHT", right, 0)
                right = right - w - 8
            end
            c:SetDisabled(Eval(spec.disabled) and true or false)
            c.frame:Show()
        end
    end
    for kind, made in pairs(d.made) do
        for i = used[kind] + 1, #made do
            made[i].spec = nil
            made[i].frame:Hide()
        end
    end
    for i = 1, #d.panelFrames do d.panelFrames[i]:Hide() end
    if d.footer then d.footer:Hide() end
    return DETAIL_H
end

--------------------------------------------------------------------------------
-- Panels: a strip that holds several titled sections
--------------------------------------------------------------------------------
-- The strip above is one line. An entry with more to set than fits one line - every override
-- an ability can have - hands the strip PANELS instead:
--   { panels = { { title = ..., lines = { {spec, spec}, {spec} } }, ... }, footer = ... }
-- Each panel is a small bordered box inside the strip with its title and its controls in
-- lines, left to right. Panels flow across the strip and wrap when the next would not fit.
-- Same tint and edge around them as the one-line strip, so an open entry reads the same in
-- every list. Specs add two kinds to the one-line strip's three: "description" (a line of
-- words) and "input" (a text box).
local PANEL_PAD, PANEL_TITLE_H, LINE_H, PANEL_GAP, EDGE = 8, 20, 28, 8, 12
local KIND = { toggle = "toggle", execute = "execute", select = "select", input = "input", description = "text" }

local function MakePanel(d)
    local p = CreateFrame("Frame", nil, d, "BackdropTemplate")
    p:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    p:SetBackdropColor(0, 0, 0, 0.25)
    p:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", PANEL_PAD, -6)
    p.title:SetJustifyH("LEFT")
    return p
end

--- Draw one control into a panel line, centred on the line. Returns the width it took.
local function PlaceIn(parent, c, kind, spec, x, y, fresh)
    c.spec = spec
    c.frame:SetParent(parent)
    c.frame:ClearAllPoints()
    local w
    if kind == "toggle" then
        c:SetLabel(Eval(spec.name) or "")
        w = 24 + ((c.text and c.text:GetStringWidth()) or 120) + 8
        c:SetWidth(w)
        c:SetValue(spec.get and spec.get() or false)
    elseif kind == "execute" then
        c:SetText(Eval(spec.name) or "")
        w = ((c.text and c.text:GetStringWidth()) or 80) + 30
        c:SetWidth(w)
    elseif kind == "select" then
        c.inside:SetText(Eval(spec.name) or "")
        if fresh or not c.fitW then
            local list = Eval(spec.values) or {}
            c:SetList(list, Eval(spec.sorting))
            local widest = 0
            for _, text in pairs(list) do
                c.text:SetText(text)
                widest = math.max(widest, c.text:GetStringWidth() or 0)
            end
            c.fitW = 30 + (c.inside:GetStringWidth() or 60) + 12 + widest + 43
        end
        w = math.min(300, math.max(150, c.fitW))
        c:SetWidth(w)
        c:SetValue(spec.get and spec.get())
    elseif kind == "input" then
        w = 150
        c:SetWidth(w)
        -- Not while it is being typed in: a refresh mid-edit would put the old text back.
        if not (c.editbox and c.editbox:HasFocus()) then c:SetText(spec.get and spec.get() or "") end
    else
        c.text:SetText(Eval(spec.name) or "")
        w = math.min(380, (c.text:GetStringWidth() or 0) + 4)
        c.frame:SetWidth(w)
    end
    c.frame:SetPoint("LEFT", parent, "TOPLEFT", x, y - LINE_H / 2)
    c:SetDisabled(Eval(spec.disabled) and true or false)
    c.frame:Show()
    return w
end

--- Point the strip at an entry's panels. `avail` is the width there is to lay them out in.
--- @return number the strip's height
function ListWidget.BindPanels(d, key, spec, avail)
    local fresh = (d.key ~= key)
    d.key = key
    local used = { toggle = 0, execute = 0, select = 0, input = 0, text = 0 }
    local function take(kind)
        used[kind] = used[kind] + 1
        local c = d.made[kind][used[kind]]
        if not c then
            c = MakeControl(d, kind)
            d.made[kind][used[kind]] = c
        end
        return c
    end
    local right = math.max(300, (avail or 600) - EDGE)
    local shown, laid = 0, {}
    for _, ps in ipairs(spec.panels) do
        -- Only the lines with something to show; a panel with none is not drawn at all.
        local lines = {}
        for _, line in ipairs(ps.lines) do
            local keep = {}
            for _, cs in ipairs(line) do
                if cs and KIND[cs.type] and not Eval(cs.hidden) then keep[#keep + 1] = cs end
            end
            if #keep > 0 then lines[#lines + 1] = keep end
        end
        if #lines > 0 then
            shown = shown + 1
            local p = d.panelFrames[shown]
            if not p then
                p = MakePanel(d)
                d.panelFrames[shown] = p
            end
            p.title:SetText(Eval(ps.title) or "")
            local pw = PANEL_PAD * 2 + (p.title:GetStringWidth() or 0)
            local row = 0
            for _, line in ipairs(lines) do
                local lx = PANEL_PAD
                for _, cs in ipairs(line) do
                    local kind = KIND[cs.type]
                    local c = take(kind)
                    local w = PlaceIn(p, c, kind, cs, lx, -(PANEL_TITLE_H + row * LINE_H), fresh)
                    -- No room left on this line: carry on under it.
                    if lx > PANEL_PAD and lx + w + PANEL_PAD > right - EDGE then
                        row, lx = row + 1, PANEL_PAD
                        w = PlaceIn(p, c, kind, cs, lx, -(PANEL_TITLE_H + row * LINE_H), false)
                    end
                    lx = lx + w + 10
                    pw = math.max(pw, lx - 10 + PANEL_PAD)
                end
                row = row + 1
            end
            laid[#laid + 1] = { p = p, w = pw, h = PANEL_TITLE_H + row * LINE_H + 4 }
        end
    end

    -- Rows of panels, each row stretched to the strip's full width and its panels given one
    -- height, so an open entry is a tidy block rather than boxes of whatever width their
    -- words came to. Contents sit at each panel's top left, so widening only adds room.
    local y, first = -8, 1
    local function placeRow(last)
        local natural, rowH = PANEL_GAP * (last - first), 0
        for i = first, last do
            natural = natural + laid[i].w
            rowH = math.max(rowH, laid[i].h)
        end
        local extra = math.max(0, (right - EDGE) - natural) / (last - first + 1)
        local x = EDGE
        for i = first, last do
            local L = laid[i]
            L.p:SetSize(L.w + extra, rowH)
            L.p:ClearAllPoints()
            L.p:SetPoint("TOPLEFT", d, "TOPLEFT", x, y)
            L.p:Show()
            x = x + L.w + extra + PANEL_GAP
        end
        y = y - rowH - PANEL_GAP
    end
    local x = EDGE
    for i = 1, #laid do
        -- Wrap when this panel would run past the edge, unless it is first on its row.
        if i > first and x + laid[i].w > right then
            placeRow(i - 1)
            first, x = i, EDGE
        end
        x = x + laid[i].w + PANEL_GAP
    end
    if #laid > 0 then
        placeRow(#laid)
        y = y + PANEL_GAP   -- no gap owed after the last row
    end
    for i = shown + 1, #d.panelFrames do d.panelFrames[i]:Hide() end
    for kind, made in pairs(d.made) do
        for i = used[kind] + 1, #made do
            made[i].spec = nil
            made[i].frame:Hide()
        end
    end
    local footer = Eval(spec.footer)
    if footer then
        if not d.footer then
            d.footer = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            d.footer:SetJustifyH("LEFT")
            d.footer:SetWordWrap(false)
        end
        d.footer:ClearAllPoints()
        d.footer:SetPoint("TOPLEFT", d, "TOPLEFT", EDGE + 2, y - 6)
        d.footer:SetPoint("RIGHT", d, "RIGHT", -EDGE, 0)
        d.footer:SetText(footer)
        d.footer:Show()
        y = y - 22
    elseif d.footer then
        d.footer:Hide()
    end
    local h = 8 - y
    d:SetHeight(h)
    return h
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- Where the entry would land if dropped now, and where to draw the line saying so.
--- Dropping on the upper half of a row means "above it", the lower half "below".
local function DropTarget(w)
    local _, cy = GetCursorPosition()
    cy = cy / (w.content:GetEffectiveScale() or 1)
    for i = 1, #w.rows do
        local r = w.rows[i]
        if r:IsShown() and r:GetTop() then
            local mid = (r:GetTop() + r:GetBottom()) / 2
            if cy >= mid then return r.index, r:GetTop() end
            if cy >= r:GetBottom() then return r.index + 1, r:GetBottom() end
        end
    end
    return nil
end

local function EndDrag(w, commit)
    local from, id = w.dragFrom, w.dragID
    w.dragFrom, w.dragID = nil, nil
    w.dropLine:Hide()
    w.content:SetScript("OnUpdate", nil)
    for i = 1, #w.rows do w.rows[i].dragTint:Hide() end
    if not (commit and from) then return end
    local list, to = w:List(), DropTarget(w)
    -- The dragged entry must still be where the drag began: a refresh the dialog had not
    -- drawn yet would otherwise move whatever took its place.
    if not (list and to and list[from] == id) then return end
    -- Removing first shifts everything after it up one, so a downward move overshoots by
    -- exactly one unless the target is corrected for the gap the entry leaves behind.
    if to > from then to = to - 1 end
    if to == from or to < 1 then return end
    table.remove(list, from)
    table.insert(list, math.min(to, #list + 1), id)
    w:Commit()
end

function ListWidget.AcquireRow(w, index)
    local row = w.rows[index]
    if row then return row end
    -- A Button, not a Frame: a plain frame takes mouse motion (so hover and tooltips
    -- worked) but does not reliably deliver the button press that starts a drag.
    row = CreateFrame("Button", nil, w.content)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(r, button)
        if not r.id then return end
        if button == "RightButton" then
            ListWidget.OpenAbility(r.id)
        elseif w.RowClickable and w:RowClickable() then
            w:OnRowClick(r.id)
        elseif r.edit:IsShown() and r.edit:IsEnabled() then
            -- The row's own settings, same as its "..." button.
            r.edit:Click()
        end
    end)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row:EnableMouse(true)
    -- Newer clients split motion from clicks; ask for both explicitly where the calls exist.
    if row.SetMouseClickEnabled then row:SetMouseClickEnabled(true) end
    if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(true) end
    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if w.RowTitle then
            w:RowTitle(self)
        else
            GameTooltip:SetText(self.tipName or "", 1, 1, 1)
        end
        if self.canDrag then
            GameTooltip:AddLine(L["Priority Drag Hint"], GREEN[1], GREEN[2], GREEN[3])
        end
        local clickable = w.RowClickable and w:RowClickable()
        if clickable or (self.edit:IsShown() and self.edit:IsEnabled()) then
            GameTooltip:AddLine(L["List Click Hint"], GREEN[1], GREEN[2], GREEN[3])
        end
        if not clickable and ListWidget.CanOpenAbility(self.id) then
            GameTooltip:AddLine(L["List Right Click Hint"], GREEN[1], GREEN[2], GREEN[3])
        end
        if w.RowTooltip then w:RowTooltip(self) end
        GameTooltip:Show()
        self.hover:Show()
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.hover:Hide()
    end)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(r)
        if not r.canDrag then return end
        GameTooltip:Hide()
        w.dragFrom, w.dragID = r.index, r.id
        r.dragTint:Show()
        -- The line follows the cursor rather than the row: the rows themselves never
        -- move, so the only feedback is where the entry would land.
        w.content:SetScript("OnUpdate", function()
            local _, y = DropTarget(w)
            if y then
                w.dropLine:ClearAllPoints()
                w.dropLine:SetPoint("LEFT", w.content, "LEFT", 5, 0)
                w.dropLine:SetPoint("RIGHT", w.content, "RIGHT", -5, 0)
                w.dropLine:SetPoint("TOP", w.content, "TOP", 0, y - (w.content:GetTop() or 0))
                w.dropLine:Show()
            else
                w.dropLine:Hide()
            end
        end)
    end)
    row:SetScript("OnDragStop", function() EndDrag(w, true) end)
    row:SetScript("OnHide", function(r)
        if w.dragFrom == r.index then EndDrag(w, false) end
        GameTooltip:Hide()
        r.hover:Hide()
    end)

    row.dragTint = row:CreateTexture(nil, "ARTWORK")
    row.dragTint:SetAllPoints()
    row.dragTint:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
    row.dragTint:Hide()

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.05)
    row.hover:Hide()

    row.idx = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.idx:SetPoint("LEFT", 6, 0)
    row.idx:SetWidth(20)
    row.idx:SetJustifyH("CENTER")

    row.slot = row:CreateTexture(nil, "BACKGROUND")
    row.slot:SetSize(16, 16)
    row.slot:SetPoint("LEFT", row.idx, "RIGHT", 6, 0)
    if HasAtlas(ListWidget.BUTTON_ATLAS) then row.slot:SetAtlas(ListWidget.BUTTON_ATLAS) else row.slot:Hide() end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints(row.slot)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.frame = row:CreateTexture(nil, "OVERLAY")
    row.frame:SetSize(18, 18)
    row.frame:SetPoint("CENTER", row.slot, "CENTER")
    if HasAtlas(ListWidget.BUTTON_FRAME_ATLAS) then
        row.frame:SetAtlas(ListWidget.BUTTON_FRAME_ATLAS)
    else
        row.frame:Hide()
    end

    -- Everything below is anchored and coloured ONCE: only the row's own position, its
    -- text and the column widths change per refresh.
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetWordWrap(false)   -- clipped with an ellipsis; the tooltip has it in full
    row.name:SetPoint("LEFT", row.slot, "RIGHT", 7, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(unpack(INK))

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.right:SetJustifyH("RIGHT")
    row.right:SetWidth(46)

    local key = function() return w.listKey end
    row.remove = MakeButton(row, "x", L["Remove"], function()
        local id = row.id
        if not id then return end
        if w.RemoveRequested and w:RemoveRequested(id) then return end
        ListWidget.RemoveEntry(w, id)
    end)
    row.edit = MakeButton(row, "...", L["Priority Edit Tip"], function()
        -- Explicit if/else, never `x and nil or y`: `true and nil` is nil and `nil or y`
        -- is y, so that idiom can never produce nil - the open row could not be closed.
        if ListWidget.selected[key()] == row.id then
            ListWidget.selected[key()] = nil
        else
            ListWidget.selected[key()] = row.id
        end
        w:Reflow()
    end)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.edit:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    -- Anchored to the buttons, not to the text: a disabled button keeps its position, so
    -- the column lands in the same place whether the row is editable or read-only.
    row.right:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)

    if w.OnRowCreated then w:OnRowCreated(row) end
    w.rows[index] = row
    return row
end

--- The dark bordered pane every list sits on - Ace's own inline-group backdrop, so it matches
--- the bordered groups around it. It is what the alternating stripes and the button frames
--- read against: without it the rows floated on the panel and looked like loose text.
--- `top` leaves room above it (the priority list's tab strip sits there).
function ListWidget.Pane(frame, top)
    local body = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(top or 0))
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    body:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    body:SetBackdropColor(0.09, 0.085, 0.07, 1)
    body:SetBackdropBorderColor(0.4, 0.4, 0.4)
    return body
end

--- Give a widget its rows, the drop line and the settings strip, all on `content`.
function ListWidget.Attach(w, content)
    w.rows, w.content = {}, content
    w.dropLine = content:CreateTexture(nil, "OVERLAY")
    w.dropLine:SetHeight(2)
    w.dropLine:SetColorTexture(unpack(GOLD))
    w.dropLine:Hide()
    w.detail = ListWidget.BuildDetail(content)
end

--- For a widget's OnRelease. Widgets are pooled: anything left here is inherited by the
--- next option that mounts this type.
function ListWidget.Reset(w)
    if w.dragFrom then EndDrag(w, false) end
    -- A strip left bound would keep the previous mount's dropdown contents.
    if w.detail then w.detail.key = nil end
end

--- Lay out one row per entry from `y` down, with the open entry's settings under it.
--- rows[i] = { id, name, icon, num, right, rightColor, tipName, controls }, where
--- `controls` is a function returning the entry's control descriptions - built only for
--- the entry that is open. `each(row, data, i)` fills any extra columns. Returns the y
--- below the last thing drawn and whether a settings strip is showing.
function ListWidget.PlaceRows(w, rows, y, editable, each)
    local open = ListWidget.selected[w.listKey]
    local detailShown = false
    for i = 1, #rows do
        local data = rows[i]
        local row = ListWidget.AcquireRow(w, i)
        row.index, row.id, row.tipName = i, data.id, data.tipName or data.name
        row.wait = data.wait
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", w.content, "TOPLEFT", 5, y)
        row:SetPoint("TOPRIGHT", w.content, "TOPRIGHT", -5, y)
        row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)
        row.idx:SetText(data.num or "")
        row.icon:SetTexture(data.icon)
        row.name:SetText(data.name)
        row.right:SetText(data.right or "")
        row.right:SetTextColor(unpack(data.rightColor or INK_DIM))
        -- An entry with nothing to set has no settings button at all, rather than one
        -- that opens an empty strip.
        row.edit:SetShown(data.controls ~= nil)
        row.edit:SetEnabled(editable)
        row.remove:SetEnabled(editable)
        row.canDrag = editable and w.ordered ~= false
        if each then each(row, data, i) end
        row:Show()
        y = y - ROW_H

        local specs = editable and data.controls and open == data.id and data.controls()
        if specs then
            detailShown = true
            w.detail:ClearAllPoints()
            w.detail:SetPoint("TOPLEFT", w.content, "TOPLEFT", 5, y)
            w.detail:SetPoint("TOPRIGHT", w.content, "TOPRIGHT", -5, y)
            local h
            if specs.panels then
                h = ListWidget.BindPanels(w.detail, data.id, specs, (w.content:GetWidth() or 0) - 10)
            else
                h = ListWidget.BindDetail(w.detail, data.id, specs)
            end
            w.detail:Show()
            y = y - h
        end
    end
    for i = #rows + 1, #w.rows do w.rows[i]:Hide() end
    if not detailShown then
        w.detail:Hide()
        w.detail.key = nil   -- so reopening the same row rebuilds its dropdowns
    end
    return y, detailShown
end
