-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Soothe (enrage-cleanse) cue - the "enrage interrupt". Rides the interrupt
-- system's construction (the same position-0 slot, the same border/mask/hotkey chrome, a
-- castAura-style pass-through) but is a SEPARATE frame pinned over the interrupt icon: it
-- can NOT be a child of that icon, because the kick hides when there's no cast, whereas
-- soothe must show on the active enrage aura with no cast at all.
--
-- The interrupt icon shows the KICK (branchable). This shows the player's SOOTHE while the
-- target is ENRAGED - and "enraged" is a secret in combat, so we can't branch on it or
-- texture-swap the kick. Instead: enrage == dispel type 9 (C_UnitAuras.GetAuraDispelTypeColor),
-- auraInstanceID is NeverSecret, and the (combat-secret) selector alpha sinks straight into
-- each slot's SetAlpha with no read. One COMPLETE slot per target HELPFUL aura (the OR is
-- done in render), each = soothe icon + border + hotkey + green glow + the cleansed aura's
-- icon. Drawn ABOVE the interrupt icon's hotkey (+15), so a shown slot fully replaces the
-- kick (no lingering kick hotkey / missing frame art) and, being on top, wins collisions.
-- ponytail: N complete slots + N idle glows is the cost of the secret-safe OR (can't collapse
-- N secret alphas into one). Bounded to soothe classes with an attackable target + shown frame.
local UISootheCue = LibStub:NewLibrary("JustAC-UISootheCue", 2)
if not UISootheCue then return end

local UIAnimations     = LibStub("JustAC-UIAnimations", true)
local UIFrameFactory   = LibStub("JustAC-UIFrameFactory", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local SpellDB          = LibStub("JustAC-SpellDB", true)
if not (UIAnimations and UIFrameFactory) then return end

local CreateFrame  = CreateFrame
local CreateColor  = CreateColor
local UnitExists   = UnitExists
local UnitCanAttack = UnitCanAttack
local pcall        = pcall
local math_max     = math.max
local math_floor   = math.floor
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local C_UnitAuras  = C_UnitAuras
local C_Spell      = C_Spell
local C_CurveUtil  = C_CurveUtil ---@diagnostic disable-line: undefined-global
local BORDER_ATLAS = "UI-HUD-ActionBar-IconFrame"

local MAX_SLOTS       = 5      -- target HELPFUL auras scanned (the OR); enrage past this is missed
local UPDATE_INTERVAL = 0.08

-- Selector curve (built once): alpha 1 ONLY at dispel type 9 (Enrage), else 0.
local selectorCurve
local function GetSelectorCurve()
    if selectorCurve ~= nil then return selectorCurve or nil end
    local cu       = C_CurveUtil
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor) then
        selectorCurve = false
        return nil
    end
    local c = cu.CreateColorCurve()
    c:SetType(stepType)
    c:AddPoint(0,  CreateColor(0, 0, 0, 0))
    c:AddPoint(9,  CreateColor(1, 1, 1, 1))   -- Enrage
    c:AddPoint(10, CreateColor(0, 0, 0, 0))
    selectorCurve = c
    return c
end

function UISootheCue.Available()
    return (C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
        and C_UnitAuras.GetAuraDataByIndex and GetSelectorCurve() ~= nil) and true or false
end

-- Per-frame driver: gate each slot by its aura's dispel type (secret alpha -> SetAlpha, no
-- read) and pass through that aura's icon into the slot's "cleansed aura" clone.
local function DriveCue(cue)
    local sel   = GetSelectorCurve()
    local gadbi = C_UnitAuras.GetAuraDataByIndex
    local gadtc = C_UnitAuras.GetAuraDispelTypeColor
    local live  = sel and UnitExists("target") and UnitCanAttack("player", "target")
        and not (cue.spellID and SpellDB and SpellDB.IsInterruptOnCooldown
                 and SpellDB.IsInterruptOnCooldown(cue.spellID))
    for i = 1, MAX_SLOTS do
        local slot = cue.slots[i]
        local a = live and gadbi("target", i, "HELPFUL") or nil
        if a then
            pcall(function()
                local c = gadtc("target", a.auraInstanceID, sel)
                slot:SetAlpha(c.a)  -- secret in combat; 1 iff dispel type 9
            end)
            -- Pass through the cleansed aura's icon (secret texture -> SetTexture, no read),
            -- exactly like the interrupt's castAura clones the cast icon.
            if slot.auraIcon and a.icon then slot.auraIcon:SetTexture(a.icon) end
        else
            slot:SetAlpha(0)
        end
    end
end

-- Build one COMPLETE soothe slot with the same chrome the queue icons use.
local function BuildSlot(cue, sz)
    local slot = CreateFrame("Frame", nil, cue)
    slot:SetAllPoints(cue)
    slot:EnableMouse(false)
    slot.cachedIconSize = sz

    -- Masked soothe icon.
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(slot)
    slot.iconTexture = icon
    if UIFrameFactory.CreateRoundedActionIconMask then
        slot.IconMask = UIFrameFactory.CreateRoundedActionIconMask(slot, sz, icon)
    end

    -- Action-button frame art (generic; matches the queue's border).
    local border = slot:CreateTexture(nil, "OVERLAY")
    if UIFrameFactory.ApplyActionButtonBorderGeometry then
        UIFrameFactory.ApplyActionButtonBorderGeometry(border, slot, sz)
    else
        border:SetAllPoints(slot)
    end
    border:SetAtlas(BORDER_ATLAS)
    slot.Border = border

    -- Soothe hotkey, top-right, above the border (so it replaces the kick's hotkey rather
    -- than letting it linger). Set in SetSpell.
    local hkFrame = CreateFrame("Frame", nil, slot)
    hkFrame:SetAllPoints(slot)
    hkFrame:SetFrameLevel(slot:GetFrameLevel() + 3)
    local hk = hkFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    hk:SetFont(STANDARD_TEXT_FONT, math_max(8, math_floor(sz * 0.4)), "OUTLINE")
    hk:SetJustifyH("RIGHT")
    hk:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -3, -3)
    slot.hotkeyText = hk

    -- "Cleansed aura" clone: mirrors the interrupt's castAura - a small sub-icon above the
    -- slot showing the enrage buff we're about to remove (icon set per-frame in DriveCue).
    local auraSz = math_floor(sz * 0.7)
    local aura = CreateFrame("Frame", nil, slot)
    aura:SetSize(auraSz, auraSz)
    aura:SetPoint("BOTTOM", slot, "TOP", 0, 2)
    local aicon = aura:CreateTexture(nil, "ARTWORK")
    aicon:SetAllPoints(aura)
    slot.auraIcon = aicon
    if UIFrameFactory.CreateRoundedActionIconMask then
        UIFrameFactory.CreateRoundedActionIconMask(aura, auraSz, aicon)
    end
    local aborder = aura:CreateTexture(nil, "OVERLAY")
    if UIFrameFactory.ApplyActionButtonBorderGeometry then
        UIFrameFactory.ApplyActionButtonBorderGeometry(aborder, aura, auraSz)
    end
    aborder:SetAtlas(BORDER_ATLAS)
    slot.auraClone = aura

    slot:SetAlpha(0)
    return slot
end

--- Point the cue at a (new) soothe spell: icon + hotkey text + green cleanse glow.
function UISootheCue.SetSpell(cue, sootheSpellID)
    if not cue or cue.spellID == sootheSpellID then return end
    cue.spellID = sootheSpellID
    local info   = sootheSpellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sootheSpellID)
    local iconID = info and info.iconID
    local hotkey = (ActionBarScanner and ActionBarScanner.GetSpellHotkey
                    and ActionBarScanner.GetSpellHotkey(sootheSpellID)) or ""
    for i = 1, MAX_SLOTS do
        local slot = cue.slots[i]
        if iconID then slot.iconTexture:SetTexture(iconID) end
        if slot.hotkeyText then slot.hotkeyText:SetText(hotkey) end
        UIAnimations.ShowSootheProcGlow(slot)  -- renders only when the slot's alpha is 1
    end
end

--- Create (once) the cue pinned over `anchorIcon` (the interrupt icon = position 0).
function UISootheCue.Create(anchorIcon, sootheSpellID, iconSize)
    if not (anchorIcon and UISootheCue.Available()) then return nil end
    local cue = anchorIcon.sootheCue
    if not cue then
        -- GetWidth() is secret on nameplate-parented frames (see UIFrameFactory
        -- cachedIconSize note); never call it here.
        local sz = anchorIcon.cachedIconSize or iconSize or 32
        if sz <= 0 then sz = 32 end
        cue = CreateFrame("Frame", nil, anchorIcon:GetParent())
        cue:SetAllPoints(anchorIcon)                 -- tracks position 0 even when the kick is hidden
        cue:SetFrameStrata(anchorIcon:GetFrameStrata())
        cue:EnableMouse(false)
        local ok, lvl = pcall(function() return anchorIcon:GetFrameLevel() end)
        cue:SetFrameLevel((ok and lvl or 0) + 16)    -- above the kick's hotkeyFrame (+15) -> full replace
        cue.slots = {}
        for i = 1, MAX_SLOTS do cue.slots[i] = BuildSlot(cue, sz) end
        cue:SetScript("OnUpdate", function(self, e)
            self._t = (self._t or 0) + e
            if self._t < UPDATE_INTERVAL then return end
            self._t = 0
            DriveCue(self)
        end)
        cue:Hide()
        anchorIcon.sootheCue = cue
    end
    UISootheCue.SetSpell(cue, sootheSpellID)
    return cue
end

--- Show the cue (starts the driver). Idempotent.
function UISootheCue.Show(cue)
    if cue and not cue:IsShown() then cue:Show() end
end

--- Hide the cue (stops the driver) and blank every slot. Free when already
--- hidden: a hidden frame renders no children, so blanked-or-not is moot, and
--- the overlay's hidden-state render path calls this every pass.
function UISootheCue.Hide(cue)
    if not cue or not cue:IsShown() then return end
    if cue.slots then
        for i = 1, MAX_SLOTS do
            local slot = cue.slots[i]
            if slot then slot:SetAlpha(0) end
        end
    end
    if cue:IsShown() then cue:Hide() end
end

return UISootheCue
