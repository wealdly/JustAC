-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/LiveSearchPopup - Persistent live-search popup for spell/item selection
local LiveSearchPopup = LibStub:NewLibrary("JustAC-LiveSearchPopup", 1)
if not LiveSearchPopup then return end

local MAX_ROWS   = 10
local ROW_HEIGHT = 22
local FRAME_W    = 340
local PAD        = 8

-- Active callback config set when popup is opened
local currentConfig = nil

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "JustACLiveSearchPopup", UIParent, "BackdropTemplate")
frame:SetSize(FRAME_W, PAD + 20 + PAD + 26 + PAD + MAX_ROWS * ROW_HEIGHT + PAD)
-- height = 8 + 20 + 8 + 26 + 8 + 220 + 8 = 298
frame:SetPoint("CENTER")
frame:SetFrameStrata("TOOLTIP")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile   = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0.08, 0.08, 0.08, 0.96)
frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
frame:Hide()

-- Title text
local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -PAD)
titleText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + 22), -PAD)
titleText:SetJustifyH("LEFT")
titleText:SetText("Search")

-- Close button
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetSize(22, 22)
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

-- Search EditBox
local searchEdit = CreateFrame("EditBox", "JustACLiveSearchEdit", frame, "InputBoxTemplate")
searchEdit:SetSize(FRAME_W - PAD * 2 - 16, 20)
searchEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 8, -(PAD + 20 + PAD))
searchEdit:SetAutoFocus(false)
searchEdit:SetMaxLetters(64)

-- Separator line beneath search box
local sep = frame:CreateTexture(nil, "ARTWORK")
sep:SetHeight(1)
sep:SetColorTexture(0.3, 0.3, 0.3, 0.8)
sep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD,  -(PAD + 20 + PAD + 26))
sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(PAD + 20 + PAD + 26))

-- Row container (below separator)
local rowContainer = CreateFrame("Frame", nil, frame)
rowContainer:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -(PAD + 20 + PAD + 26 + PAD))
rowContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(PAD + 20 + PAD + 26 + PAD))
rowContainer:SetHeight(MAX_ROWS * ROW_HEIGHT)

-- Hint / no-results label
local hintText = rowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintText:SetPoint("TOPLEFT",  rowContainer, "TOPLEFT",  4, -4)
hintText:SetPoint("TOPRIGHT", rowContainer, "TOPRIGHT", -4, -4)
hintText:SetJustifyH("LEFT")
hintText:SetTextColor(0.5, 0.5, 0.5)
hintText:SetText("Type to search...")

-- Result rows
local rows = {}
for i = 1, MAX_ROWS do
    local btn = CreateFrame("Button", nil, rowContainer)
    btn:SetHeight(ROW_HEIGHT)
    btn:SetPoint("TOPLEFT",  rowContainer, "TOPLEFT",  0, -(i - 1) * ROW_HEIGHT)
    btn:SetPoint("TOPRIGHT", rowContainer, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.3, 0.6, 1, 0.15)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("LEFT",  btn, "LEFT",  4, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)

    btn.lbl    = lbl
    btn.itemID = nil  -- positive = spellID, negative = -itemID

    btn:SetScript("OnClick", function()
        if btn.itemID and currentConfig and currentConfig.onSelect then
            currentConfig.onSelect(btn.itemID, btn.lbl:GetText())
        end
        frame:Hide()
    end)

    btn:Hide()
    rows[i] = btn
end

-------------------------------------------------------------------------------
-- Populate rows from a results table  {[id] = displayName}
-------------------------------------------------------------------------------
local function PopulateRows(results)
    -- Sort alphabetically, stripping color codes from the sort key
    local sorted = {}
    for id, displayName in pairs(results) do
        sorted[#sorted + 1] = { id = id, name = displayName }
    end
    table.sort(sorted, function(a, b)
        local na = a.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local nb = b.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return na < nb
    end)

    local count = math.min(#sorted, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local row = rows[i]
        if i <= count then
            local e = sorted[i]
            row.itemID = e.id
            row.lbl:SetText(e.name)
            row:Show()
        else
            row.itemID = nil
            row:Hide()
        end
    end

    if count == 0 then
        local filter = searchEdit:GetText()
        if not filter or #filter:trim() < 2 then
            hintText:SetText("Type to search...")
        else
            hintText:SetText("No matches")
        end
        hintText:Show()
    else
        hintText:Hide()
    end
end

local function RunSearch()
    if not currentConfig then return end
    local filter = searchEdit:GetText()
    local results = currentConfig.searchFunc(filter, currentConfig.excludeList)
    PopulateRows(results)
end

-- Live search: no debounce needed since we don't call NotifyChange
searchEdit:SetScript("OnTextChanged", function(_, userInput)
    if userInput then RunSearch() end
end)

searchEdit:SetScript("OnEscapePressed", function()
    frame:Hide()
end)

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Open the popup.
--
-- config = {
--   title       = string                         popup header text
--   searchFunc  = function(filterText, excludeList) → {[id]=displayName}
--   onSelect    = function(id, displayName)       called on row click
--   excludeList = optional table (passed through to searchFunc each keystroke)
--   anchor      = optional frame; popup appears to its right (defaults to CENTER)
-- }
function LiveSearchPopup.Open(config)
    currentConfig = config
    titleText:SetText(config.title or "Search")

    searchEdit:SetText("")

    for i = 1, MAX_ROWS do
        rows[i]:Hide()
        rows[i].itemID = nil
    end
    hintText:SetText("Type to search...")
    hintText:Show()

    frame:ClearAllPoints()
    if config.anchor then
        frame:SetPoint("TOPLEFT", config.anchor, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    frame:Show()
    frame:Raise()
    searchEdit:SetFocus()
end

function LiveSearchPopup.Close()
    frame:Hide()
end

function LiveSearchPopup.IsOpen()
    return frame:IsShown()
end
