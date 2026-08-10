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
-- done in render). Each slot is built by the SHARED CreateBaseIcon - the same builder the
-- interrupt and tank-maintenance slots use - so it gets icon, border, hotkey, cooldown swipe
-- and the rest for free, plus a soothe-specific "cleansed aura" sub-icon.
-- Drawn ABOVE the interrupt icon's hotkey (+15), so a shown slot fully replaces the
-- kick (no lingering kick hotkey / missing frame art) and, being on top, wins collisions.
-- ponytail: N complete slots + N idle glows is the cost of the secret-safe OR (can't collapse
-- N secret alphas into one). Bounded to soothe classes with an attackable target + shown frame.
local UISootheCue = LibStub:NewLibrary("JustAC-UISootheCue", 8)
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
local C_UnitAuras  = C_UnitAuras
local C_Spell      = C_Spell
local C_CurveUtil  = C_CurveUtil ---@diagnostic disable-line: undefined-global

local MAX_SLOTS       = 5      -- target HELPFUL auras scanned (the OR); enrage past this is missed
-- The addon-wide widget-refresh cadence, not a private number: the cue's sink pass should
-- tick at the same rate as every other cooldown/urgency widget.
local UPDATE_INTERVAL = UIFrameFactory.COOLDOWN_UPDATE_INTERVAL or 0.08

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
    -- Cooldown swipe via the SHARED updater (resolved lazily: UIRenderer loads after this
    -- file). It covers the GCD as well as soothe's own cooldown, which is the whole point -
    -- a slot with no swipe reads as "press me" while the global is still running.
    -- Called for every slot because which one is visible is decided by a SECRET alpha, so we
    -- cannot know which. Only the WIDGET writes are change-guarded downstream; the query
    -- chain runs per slot per tick. ponytail: 5 identical query chains while the cue is
    -- live - split UpdateButtonCooldowns into query/apply if this transient state ever
    -- shows up in profiling.
    local UIRenderer = LibStub("JustAC-UIRenderer", true)
    local UpdateCooldowns = UIRenderer and UIRenderer.UpdateButtonCooldowns
    local live  = sel and UnitExists("target") and UnitCanAttack("player", "target")
        and not (cue.spellID and SpellDB and SpellDB.IsInterruptOnCooldown
                 and SpellDB.IsInterruptOnCooldown(cue.spellID))
    for i = 1, MAX_SLOTS do
        local slot = cue.slots[i]
        local a = slot and live and gadbi("target", i, "HELPFUL") or nil
        if not slot then
            -- CreateBaseIcon can fail; skip rather than erroring on every tick.
        elseif a then
            pcall(function()
                local c = gadtc("target", a.auraInstanceID, sel)
                slot:SetAlpha(c.a)  -- secret in combat; 1 iff dispel type 9
            end)
            -- Pass through the cleansed aura's icon (secret texture -> SetTexture, no read),
            -- exactly like the interrupt's castAura clones the cast icon.
            if slot.auraIcon and a.icon then slot.auraIcon:SetTexture(a.icon) end
            if UpdateCooldowns then UpdateCooldowns(slot) end
        else
            slot:SetAlpha(0)
        end
    end
end

-- Build one COMPLETE soothe slot from the SHARED CreateBaseIcon, so it inherits the cooldown
-- swipe a hand-built subset kept missing (a soothe on GCD read as castable). Cost: a full
-- button per slot instead of a light frame, times MAX_SLOTS - the N-slot trade noted up top.
local function BuildSlot(cue, sz, profile)
    -- Not clickable: this is a display overlay pinned over the interrupt, never pressed.
    local slot = UIFrameFactory.CreateBaseIcon(cue, sz, false, true)
    if not slot then return nil end
    slot:SetAllPoints(cue)
    slot:EnableMouse(false)

    -- "Cleansed aura" clone: a small sub-icon showing the enrage buff about to be removed.
    -- Stays bespoke because it is soothe-specific, exactly as the interrupt's castAura is
    -- specific to the interrupt - but it takes its ANCHOR from the shared helper so the two
    -- cannot disagree about where a sub-icon on this slot belongs.
    local aura = UIFrameFactory.CreateAuraSubIcon(slot, sz, profile, profile and profile.queueOrientation or "LEFT")
    aura:SetFrameLevel(slot:GetFrameLevel() + 4)  -- above CreateBaseIcon's borderFrame (+3)
    slot.auraIcon  = aura.iconTexture
    slot.auraFrame = aura  -- kept for ReanchorAuras (the overlay re-seats per expansion)

    -- SHOWN, at alpha 0 - not hidden. The whole cue works by handing a SECRET alpha to
    -- SetAlpha and letting the engine decide; a hidden frame draws nothing whatever its alpha,
    -- so hiding a slot does not "hide it harder", it permanently disables it.
    -- CreateBaseIcon ends with button:Hide(), which is right for every other caller (they call
    -- Show() when a spell lands) and silently wrong here - visibility is not ours to decide.
    -- This is the one line that has to differ from the shared builder's contract; without it
    -- the cue is invisible while every gate still reports healthy, because the CONTAINER is
    -- shown and only the slots inside are dead.
    slot:Show()
    slot:SetAlpha(0)
    return slot
end

--- Re-seat every slot's cleansed-aura clone for the OVERLAY's expansion. The slots
--- are built with the STANDARD queue's orientation (BuildSlot above), which put the
--- clone on the wrong side of an "up"-expansion overlay - directly over dpsIcons[1].
--- Mirrors the overlay's own castAura convention (±2, no maintenance shift: the
--- overlay's maintenance slot lives on the defensive cluster and can't collide).
function UISootheCue.ReanchorAuras(cue, expansion)
    if not cue or not cue.slots then return end
    for i = 1, MAX_SLOTS do
        local slot = cue.slots[i]
        local aura = slot and slot.auraFrame
        if aura then
            aura:ClearAllPoints()
            if expansion == "up" then
                aura:SetPoint("TOP", slot, "BOTTOM", 0, -2)
            else
                aura:SetPoint("BOTTOM", slot, "TOP", 0, 2)
            end
        end
    end
end

--- Point the cue at a (new) soothe spell: icon + hotkey text + cyan cleanse glow.
function UISootheCue.SetSpell(cue, sootheSpellID)
    if not cue or cue.spellID == sootheSpellID then return end
    cue.spellID = sootheSpellID
    local info   = sootheSpellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sootheSpellID)
    local iconID = info and info.iconID
    local hotkey = (ActionBarScanner and ActionBarScanner.GetSpellHotkey
                    and ActionBarScanner.GetSpellHotkey(sootheSpellID)) or ""
    for i = 1, MAX_SLOTS do
        local slot = cue.slots[i]
        if slot then
            if iconID then
                slot.iconTexture:SetTexture(iconID)
                slot.iconTexture:Show()   -- CreateBaseIcon leaves it hidden until a spell lands
            end
            if slot.hotkeyText then slot.hotkeyText:SetText(hotkey) end
            -- Lets the shared cooldown updater resolve this slot's swipe (GCD + soothe's own
            -- cooldown). Without it a soothe on the global looked perfectly castable.
            slot.spellID = sootheSpellID
            slot.isItem = false
            UIAnimations.ShowSootheProcGlow(slot)  -- renders only when the slot's alpha is 1
        end
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
        local addon = LibStub("AceAddon-3.0", true)
        addon = addon and addon:GetAddon("JustAssistedCombat", true)
        local profile = addon and addon.db and addon.db.profile
        for i = 1, MAX_SLOTS do cue.slots[i] = BuildSlot(cue, sz, profile) end
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
