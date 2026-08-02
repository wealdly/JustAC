-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Debug HUD - a movable, live-updating overlay of the signals the queue
-- runs on (context / engaged-enemy count / rotation source / AC pick / buff
-- windows). Toggle with /jac hud. Purely diagnostic and reads only secret-safe
-- values, so it is safe to leave up in combat.
local DebugHUD = LibStub:NewLibrary("JustAC-DebugHUD", 1)
if not DebugHUD then return end

local hud
local addonRef

local function nm(id)
    if not id then return "-" end
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return n or tostring(id)
end

--- Assemble the current diagnostic snapshot (one string, newline-separated).
local function BuildText()
    local SQ = LibStub("JustAC-SpellQueue", true)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local L = {}

    -- Context + engaged-enemy count (the AC-independent AoE signal).
    local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
    local arch = (ctx and ctx.arch) or "st"
    local enemies = (BAPI and BAPI.GetEngagedEnemyCount and BAPI.GetEngagedEnemyCount()) or 0
    local acol = (arch == "aoe" and "ff44ff44") or (arch == "cleave" and "ffffcc44") or "ff8888ff"
    L[#L + 1] = string.format("|cff00ccffcontext|r  |c%s%s|r  |cffaaaaaa%d engaged|r",
        acol, arch:upper(), enemies)

    -- Queue source + ordering mode.
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local prof = addonRef and addonRef.db and addonRef.db.profile
    local cq = prof and prof.customQueue and specKey and prof.customQueue[specKey]
    local src = (cq and cq.enabled) and "Custom" or "Blizzard AC"
    local order = (prof and prof.contextOrder)
        or (prof and prof.orderContextAware == false and "off") or "simc"
    -- Mirror the runtime fallback: SimC ordering needs data for this spec.
    if order == "simc" then
        local RI = LibStub("JustAC-RotationImport", true)
        if not (RI and RI.HasRotation and RI.HasRotation()) then order = "ac" end
    end
    L[#L + 1] = "|cff00ccffsource|r   " .. src .. "  |cffaaaaaaorder:" .. order .. "|r"

    -- Blizzard's live pick (kept as context source even when hidden).
    local pick = BAPI and BAPI.GetNextCastSpell and BAPI.GetNextCastSpell()
    L[#L + 1] = "|cff00ccffAC pick|r  " .. nm(pick)

    -- Active self-buffs (engine-truth via duration-object probe; remaining % is secret).
    local rot = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
    local snap = rot and BAPI.GetBuffWindowSnapshot and BAPI.GetBuffWindowSnapshot(rot)
    local parts = {}
    if snap then
        for _, w in ipairs(snap) do
            if w.active then parts[#parts + 1] = nm(w.id) end
        end
    end
    L[#L + 1] = "|cff00ccffwindows|r " .. (#parts > 0 and table.concat(parts, "  ")
        or "|cff888888none|r")

    return table.concat(L, "\n")
end

local function OnUpdate(self, delta)
    self._t = (self._t or 0) + delta
    if self._t < 0.1 then return end   -- 10 Hz is plenty for a readout
    self._t = 0
    self.text:SetText(BuildText())
    self:SetWidth(math.max(170, self.text:GetStringWidth() + 16))
    self:SetHeight(self.text:GetStringHeight() + 12)
end

local function EnsureFrame()
    if hud then return hud end
    local f = CreateFrame("Frame", "JustAC_DebugHUD", UIParent, "BackdropTemplate")
    f:SetSize(200, 80)
    f:SetPoint("CENTER", 0, 220)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.6)
        f:SetBackdropBorderColor(0, 0.8, 1, 0.4)
    end
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", 8, -6)
    t:SetJustifyH("LEFT")
    t:SetJustifyV("TOP")
    f.text = t
    f:SetScript("OnUpdate", OnUpdate)
    f:Hide()
    hud = f
    return f
end

--- Toggle the HUD (/jac hud).
function DebugHUD.Toggle(addon)
    addonRef = addon or addonRef
        or (LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true))
    local f = EnsureFrame()
    if f:IsShown() then
        f:Hide()
        if addonRef and addonRef.Print then addonRef:Print("Debug HUD hidden") end
    else
        f.text:SetText(BuildText())
        f:Show()
        if addonRef and addonRef.Print then
            addonRef:Print("Debug HUD shown - drag to move, /jac hud to hide")
        end
    end
end
