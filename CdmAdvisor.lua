-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Cooldown Manager advisor (WoW Forever). Aura reads are denied in combat there; the
-- Cooldown Manager's Tracked Buffs / Tracked Bars icons are the one exact in-combat source
-- (MaintenanceTracker reads them). This offers to add the buffs and DoTs the rotation depends
-- on to the player's layout - and only ever as a guest in it:
--   * opt in only: a button, or a prompt the player can silence for good;
--   * only entries still at Blizzard's default - anything the player moved or set to
--     "Not in bar" is their call and is never touched;
--   * into the panel the player uses least (or the one they let JustAC hide);
--   * every addition is recorded per layout, can be removed in one click, and one the player
--     removes themselves is never offered again;
--   * never in combat, never while the Cooldown Manager settings are open (its own copy of
--     the layout would overwrite ours on save, and ours theirs).
-- The write is C_CooldownViewer.SetLayoutData: a plain C call storing the saved-layout string,
-- which Blizzard's own code loads on the next /reload - no JustAC code runs inside the
-- Cooldown Manager, so nothing there is tainted. Format
-- (Blizzard_CooldownViewer/CooldownViewerSettingsDataStoreSerialization.lua):
--   "<encoding version>|" .. base64(deflate(CBOR(data))); data[2] = spec tag -> active layout
--   id, data[3] = spec tag -> layout id -> { [1] = order, [2] = category -> cooldown ids },
--   data[4] = layout id -> name. The default layout is never stored.
local CdmAdvisor = LibStub:NewLibrary("JustAC-CdmAdvisor", 1)
if not CdmAdvisor then return end

local SpellDB = LibStub("JustAC-SpellDB", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local FIELD_ACTIVE, FIELD_LAYOUTS, FIELD_NAMES = 2, 3, 4
local LAYOUT_CATEGORY_OVERRIDES = 2

local function Forever() return SpellDB and SpellDB.IsForever and SpellDB.IsForever() or false end

local function Addon()
    local AceAddon = LibStub("AceAddon-3.0", true)
    return AceAddon and AceAddon:GetAddon("JustAC", true)
end

--- The per-character record (layouts are per character): what we added, what was turned down.
local function Record()
    local a = Addon()
    local c = a and a.db and a.db.char
    if not c then return nil end
    c.cdm = c.cdm or {}
    local r = c.cdm
    r.added = r.added or {}       -- layoutKey -> { [cooldownID] = category }
    r.declined = r.declined or {} -- [cooldownID] = true: the player removed one we added
    r.asked = r.asked or {}       -- [spellID] = true: already offered in the prompt
    return r
end

-- ── Layout codec ────────────────────────────────────────────────────────────

function CdmAdvisor.Decode(s)
    local E = C_EncodingUtil
    if type(s) ~= "string" or #s == 0 then return nil, "empty (nothing saved yet)" end
    local d = s:find("|", 1, true)
    if not d then return nil, "no version prefix" end
    local ver = tonumber(s:sub(1, d - 1))
    if ver ~= 1 then return nil, "unknown encoding version " .. tostring(ver) end
    local ok, t = pcall(function()
        local raw = E.DecodeBase64(s:sub(d + 1))
        local inflated = raw and E.DecompressString(raw, Enum.CompressionMethod.Deflate)
        return inflated and E.DeserializeCBOR(inflated)
    end)
    if not ok then return nil, "decode threw: " .. tostring(t) end
    if type(t) ~= "table" then return nil, "did not decode to a table" end
    return t
end

function CdmAdvisor.Encode(t)
    local E = C_EncodingUtil
    return "1|" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(t), Enum.CompressionMethod.Deflate))
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function SpecTag()
    return CooldownViewerUtil and CooldownViewerUtil.GetCurrentClassAndSpecTag
        and CooldownViewerUtil.GetCurrentClassAndSpecTag()
end

--- The active layout for this spec (nil = the unstored default), its id, name and spec tag.
function CdmAdvisor.ActiveLayout(data)
    local tag = SpecTag()
    local id = tag and data[FIELD_ACTIVE] and data[FIELD_ACTIVE][tag]
    local layout = id and data[FIELD_LAYOUTS] and data[FIELD_LAYOUTS][tag] and data[FIELD_LAYOUTS][tag][id]
    return layout, id, id and data[FIELD_NAMES] and data[FIELD_NAMES][id], tag
end

--- The category a cooldown ID sits in under this layout, and whether the layout overrides it.
function CdmAdvisor.EffectiveCategory(layout, cid, default)
    local overrides = layout and layout[LAYOUT_CATEGORY_OVERRIDES]
    for cat, ids in pairs(overrides or {}) do
        for _, v in ipairs(ids) do if v == cid then return cat, true end end
    end
    return default, false
end

local function Unplace(layout, cid)
    for _, ids in pairs(layout[LAYOUT_CATEGORY_OVERRIDES] or {}) do
        for i = #ids, 1, -1 do if ids[i] == cid then table.remove(ids, i) end end
    end
end

local function Place(layout, cid, cat)
    layout[LAYOUT_CATEGORY_OVERRIDES] = layout[LAYOUT_CATEGORY_OVERRIDES] or {}
    Unplace(layout, cid)
    local overrides = layout[LAYOUT_CATEGORY_OVERRIDES]
    overrides[cat] = overrides[cat] or {}
    table.insert(overrides[cat], cid)
end

-- ── What the rotation needs ─────────────────────────────────────────────────

local function R1(id)
    local RI = LibStub("JustAC-RotationImport", true)
    return RI and RI.RankBase(id) or id
end

--- The buffs and debuffs the installed rotation list depends on: every buff and DoT condition
--- (Battle Shout upkeep, buff windows, Rend), plus the attack-speed buffs judged from swings.
function CdmAdvisor.CriticalSpells()
    local RI = LibStub("JustAC-RotationImport", true)
    local set = {}
    local function walk(gates)
        for _, g in ipairs(gates or {}) do
            if (g.t == "buff" or g.t == "dot") and g.id then set[R1(g.id)] = true end
            if g.g then walk(g.g) end
        end
    end
    for _, id in pairs(RI and RI.GetInsertable and RI.GetInsertable() or {}) do
        for _, tier in ipairs({ "st", "cleave", "aoe" }) do
            local rec = RI.GetEntry(id, tier)
            if rec then walk(rec.gates) end
        end
    end
    for id in pairs(SpellDB and SpellDB.HASTE_BUFFS or {}) do set[id] = true end
    return set
end

--- Every Cooldown Manager entry for a spell (any rank): cooldownID -> its default category.
function CdmAdvisor.CooldownIDsFor(spellID)
    local CV, out = C_CooldownViewer, {}
    local r1 = R1(spellID)
    for _, cat in pairs(Enum.CooldownViewerCategory or {}) do
        local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
        for _, cid in ipairs(ok and ids or {}) do
            local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, cid)
            if okI and type(info) == "table" then
                local hit = info.spellID and R1(info.spellID) == r1
                    or info.overrideSpellID and R1(info.overrideSpellID) == r1
                for _, l in ipairs(info.linkedSpellIDs or {}) do hit = hit or R1(l) == r1 end
                if hit then out[cid] = info.category or cat end
            end
        end
    end
    return out
end

-- Blizzard lets only an AURA entry into Tracked Buffs / Bars (CooldownViewerSettings.lua,
-- legalOriginalSourceCategoryToTargetCategory). Ours start in one of its not-shown aura homes.
local function AuraHomes()
    local C = Enum.CooldownViewerCategory
    local t = {}
    for _, k in ipairs({ "HiddenPassive", "EquipSlotTracked", "SpecAgnosticTracked" }) do
        if C[k] then t[C[k]] = true end
    end
    return t
end

local function TrackedCats()
    local C = Enum.CooldownViewerCategory
    return { [C.TrackedBuff] = true, [C.TrackedBar] = true }
end

--- How many entries sit in a panel under this layout (the player's use of it).
local function PanelCount(layout, cat)
    local CV, n = C_CooldownViewer, 0
    local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, false)
    for _, cid in ipairs(ok and ids or {}) do
        if CdmAdvisor.EffectiveCategory(layout, cid, cat) == cat then n = n + 1 end
    end
    local moved = layout and layout[LAYOUT_CATEGORY_OVERRIDES] and layout[LAYOUT_CATEGORY_OVERRIDES][cat]
    return n + (moved and #moved or 0)
end

--- The panel our additions go to: the one the player lets JustAC hide, else the one they use
--- least (Tracked Bars on a tie - icons are the panel players arrange by hand).
function CdmAdvisor.TargetCategory(layout)
    local C = Enum.CooldownViewerCategory
    local a = Addon()
    local p = a and a.db and a.db.profile
    if p and p.hideCdmTrackedBar and not p.hideCdmTrackedBuff then return C.TrackedBar end
    if p and p.hideCdmTrackedBuff and not p.hideCdmTrackedBar then return C.TrackedBuff end
    if PanelCount(layout, C.TrackedBuff) < PanelCount(layout, C.TrackedBar) then return C.TrackedBuff end
    return C.TrackedBar
end

local function LayoutKey(tag, id) return tostring(tag) .. ":" .. tostring(id) end

-- ── Status ──────────────────────────────────────────────────────────────────

--- Reconcile the record with the layout: an addition the player moved or removed is theirs now
--- (declined - never offered again). Returns the decoded data, active layout and its key.
local MAX_LAYOUTS = 5         -- per character (CooldownViewerSettingsLayoutManager GetMaxLayoutsForType)
local SAVE_FORMAT_VERSION = 5 -- a first-ever save (DataStoreSerialization GetCurrentSaveFormatVersion)

--- The saved layouts: a table, or nil plus "empty" (nothing saved - safe to start fresh) or
--- "unreadable" (an encoding we do not know - never written over).
local function LoadData()
    local s = C_CooldownViewer.GetLayoutData()
    if type(s) ~= "string" or #s == 0 then return nil, "empty" end
    local data = CdmAdvisor.Decode(s)
    if not data then return nil, "unreadable" end
    return data
end

--- Reconcile the record with the layout: an addition the player moved or removed is theirs now
--- (declined - never offered again). Returns the data, active layout, its key and the spec tag,
--- or nil and why the data could not be read.
local function LoadAndSync()
    local data, why = LoadData()
    if not data then return nil, nil, nil, SpecTag(), why end
    local layout, id, _, tag = CdmAdvisor.ActiveLayout(data)
    local r = Record()
    if not (layout and r) then return data, layout, nil, tag end
    local key = LayoutKey(tag, id)
    local mine = r.added[key]
    for cid, cat in pairs(mine or {}) do
        if CdmAdvisor.EffectiveCategory(layout, cid, nil) ~= cat then
            r.declined[cid] = true
            mine[cid] = nil
        end
    end
    return data, layout, key, tag
end

--- state: "unavailable" (not Forever / no Cooldown Manager), "disabled" (switched off),
--- "unreadable" (saved layouts JustAC cannot decode - left alone), "nolayout" (this spec is on
--- the unsaved default layout: adding creates a JustAC layout) or "ok"; plus the spells that can
--- be added { {id, name, cid} }, the ones the player hid, and how many JustAC has added here.
function CdmAdvisor.Status()
    local CV = C_CooldownViewer
    if not (Forever() and CV and CV.GetLayoutData and CV.SetLayoutData and C_EncodingUtil
            and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff) then
        return "unavailable", {}, {}, 0
    end
    if not (GetCVarBool and GetCVarBool("cooldownViewerEnabled")) then return "disabled", {}, {}, 0 end
    local _, layout, key, _, why = LoadAndSync()
    if why == "unreadable" then return "unreadable", {}, {}, 0 end
    local r = Record() or { declined = {}, added = {} }
    local homes, tracked, RI = AuraHomes(), TrackedCats(), LibStub("JustAC-RotationImport", true)
    local can, hidden = {}, {}
    for id in pairs(CdmAdvisor.CriticalSpells()) do
        if (RI and RI.HighestKnownRank(id)) or (IsPlayerSpell and IsPlayerSpell(id)) then
            local isTracked, candidate, playerHid = false, nil, false
            for cid, default in pairs(CdmAdvisor.CooldownIDsFor(id)) do
                local eff, overridden = CdmAdvisor.EffectiveCategory(layout, cid, default)
                if tracked[eff] then isTracked = true end
                if homes[default] and not tracked[eff] then
                    if overridden or r.declined[cid] then playerHid = true
                    else candidate = candidate or cid end
                end
            end
            if not isTracked then
                local name = C_Spell.GetSpellName(id) or tostring(id)
                if candidate then can[#can + 1] = { id = id, name = name, cid = candidate }
                elseif playerHid then hidden[#hidden + 1] = { id = id, name = name } end
            end
        end
    end
    table.sort(can, function(x, y) return x.name < y.name end)
    local added = 0
    for _ in pairs(key and r.added[key] or {}) do added = added + 1 end
    return layout and "ok" or "nolayout", can, hidden, added
end

--- One line for a state other than "ok" (options panel, chat replies).
function CdmAdvisor.StateText(state)
    if state == "disabled" then return L["CDM state disabled"] end
    if state == "nolayout" then return L["CDM state nolayout"] end
    if state == "unreadable" then return L["CDM state unreadable"] end
    return L["CDM state unavailable"]
end

-- ── Writes ──────────────────────────────────────────────────────────────────

local function CanWrite()
    if InCombatLockdown() then return false, L["CDM not in combat"] end
    if CooldownViewerSettings and CooldownViewerSettings:IsShown() then
        return false, L["CDM close settings"]
    end
    return true
end

local function Write(data)
    local out = CdmAdvisor.Encode(data)
    local back = CdmAdvisor.Decode(out)
    if not (back and DeepEqual(back, data)) then return false end
    C_CooldownViewer.SetLayoutData(out)
    return true
end

--- A spec on the unsaved default layout: create a layout named JustAC (numbered if the name is
--- taken) and make it this spec's active one - the default plus our additions, nothing of the
--- player's lost, and Default is one click away in the Cooldown Manager. The same shape
--- Blizzard writes for a new layout (SerializeLayouts): a name, an id one past the largest, an
--- empty override table. Returns data, layout, key, or nil and why not.
local function CreateLayout(data, tag)
    if not tag then return nil, nil, nil, L["CDM state unavailable"] end
    data = data or { SAVE_FORMAT_VERSION }
    data[FIELD_ACTIVE] = data[FIELD_ACTIVE] or {}
    data[FIELD_LAYOUTS] = data[FIELD_LAYOUTS] or {}
    data[FIELD_NAMES] = data[FIELD_NAMES] or {}
    local count, maxID, taken = 0, 0, {}
    for lid, lname in pairs(data[FIELD_NAMES]) do
        count = count + 1
        if type(lid) == "number" and lid > maxID then maxID = lid end
        taken[lname] = true
    end
    if count >= MAX_LAYOUTS then return nil, nil, nil, L["CDM layouts full"] end
    local name, n = "JustAC", 1
    while taken[name] do n = n + 1; name = "JustAC " .. n end
    local id = maxID + 1
    data[FIELD_LAYOUTS][tag] = data[FIELD_LAYOUTS][tag] or {}
    local layout = {}
    data[FIELD_LAYOUTS][tag][id] = layout
    data[FIELD_NAMES][id] = name
    data[FIELD_ACTIVE][tag] = id
    return data, layout, LayoutKey(tag, id)
end

--- Add the candidates (all, or only `onlyIDs` = { [spellID] = true }). Returns the count and a
--- message. Takes effect on the next /reload (Blizzard loads the layout in its own code).
function CdmAdvisor.Add(onlyIDs)
    local ok, why = CanWrite()
    if not ok then return 0, why end
    local state, can = CdmAdvisor.Status()
    if state ~= "ok" and state ~= "nolayout" then return 0, CdmAdvisor.StateText(state) end
    local r = Record()
    if not r then return 0, L["CDM state unavailable"] end
    local data, layout, key, tag, notRead = LoadAndSync()
    if notRead == "unreadable" then return 0, L["CDM state unreadable"] end
    local created = false
    if not layout then
        local whyNot
        data, layout, key, whyNot = CreateLayout(data, tag)
        if not layout then return 0, whyNot end
        created = true
    end
    local cat = CdmAdvisor.TargetCategory(layout)
    r.added[key] = r.added[key] or {}
    local n = 0
    for _, c in ipairs(can) do
        if not onlyIDs or onlyIDs[c.id] then
            Place(layout, c.cid, cat)
            r.added[key][c.cid] = cat
            r.asked[c.id] = true
            n = n + 1
        end
    end
    if n == 0 then return 0, L["CDM nothing to add"] end
    if not Write(data) then
        r.added[key] = nil
        return 0, L["CDM write failed"]
    end
    if created then
        r.created = r.created or {}
        r.created[key] = true
    end
    return n
end

--- Is a layout JustAC created still exactly what it made - our entries and nothing else?
local function OnlyOurs(layout, mine)
    for k, v in pairs(layout) do
        if k ~= LAYOUT_CATEGORY_OVERRIDES and (type(v) ~= "table" or next(v) ~= nil) then return false end
    end
    for _, ids in pairs(layout[LAYOUT_CATEGORY_OVERRIDES] or {}) do
        for _, cid in ipairs(ids) do if not mine[cid] then return false end end
    end
    return true
end

--- Put back every entry JustAC added to this layout that is still where we put it. A layout
--- JustAC created and the player never changed goes entirely: the spec is back on Default.
function CdmAdvisor.RemoveAdded()
    local ok, why = CanWrite()
    if not ok then return 0, why end
    local data, layout, key, tag = LoadAndSync()
    local r = Record()
    local mine = key and r and r.added[key]
    if not (data and layout and mine and next(mine)) then return 0, L["CDM nothing added"] end
    local n = 0
    for _ in pairs(mine) do n = n + 1 end
    if r.created and r.created[key] and OnlyOurs(layout, mine) then
        local id = data[FIELD_ACTIVE][tag]
        data[FIELD_LAYOUTS][tag][id] = nil
        if not next(data[FIELD_LAYOUTS][tag]) then data[FIELD_LAYOUTS][tag] = nil end
        data[FIELD_NAMES][id] = nil
        data[FIELD_ACTIVE][tag] = nil
    else
        for cid in pairs(mine) do Unplace(layout, cid) end
    end
    if not Write(data) then return 0, L["CDM write failed"] end
    r.added[key] = nil
    if r.created then r.created[key] = nil end
    return n
end

-- ── Prompt ──────────────────────────────────────────────────────────────────
-- Not at first login (nothing to judge yet, and a wall of popups greets every new install).
-- Instead, the first time the rotation needs a buff or DoT the Cooldown Manager could track and
-- does not: out of combat, once per spell, silenced for good by "Don't ask again".

StaticPopupDialogs["JUSTAC_CDM_RELOAD"] = {
    text = "%s",
    button1 = RELOADUI or "Reload UI",
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

--- The layout loads on /reload; offer it now with `message` (already formatted).
function CdmAdvisor.OfferReload(message)
    StaticPopup_Show("JUSTAC_CDM_RELOAD", message)
end

StaticPopupDialogs["JUSTAC_CDM_TRACK"] = {
    text = L["CDM prompt text"],
    button1 = L["CDM track"],
    button2 = L["Not now"],
    button3 = L["Don't ask again"],
    OnAccept = function(_, onlyIDs)
        local n, why = CdmAdvisor.Add(onlyIDs)
        local a = Addon()
        if n > 0 then CdmAdvisor.OfferReload(L["CDM reload text"]:format(n))
        elseif a and why then a:Print(why) end
    end,
    OnAlt = function()
        local r = Record()
        if r then r.neverAsk = true end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local pending   -- a prompt is due once combat ends

function CdmAdvisor.MaybePrompt()
    local r = Record()
    if not r or r.neverAsk then return end
    if InCombatLockdown() then pending = true; return end
    if CooldownViewerSettings and CooldownViewerSettings:IsShown() then return end
    if StaticPopup_Visible and (StaticPopup_Visible("JUSTAC_CDM_TRACK") or StaticPopup_Visible("JUSTAC_CDM_RELOAD")) then return end
    local state, can = CdmAdvisor.Status()
    if state ~= "ok" and state ~= "nolayout" then return end
    local fresh, names = {}, {}
    for _, c in ipairs(can) do
        if not r.asked[c.id] then fresh[c.id] = true; names[#names + 1] = c.name end
    end
    if #names == 0 then return end
    for id in pairs(fresh) do r.asked[id] = true end   -- "Not now" means not for these again
    StaticPopup_Show("JUSTAC_CDM_TRACK", table.concat(names, ", "), nil, fresh)
end

do
    if Forever() then
        local f = CreateFrame("Frame")
        local timer
        local function Later(sec)
            if timer then timer:Cancel() end
            timer = C_Timer.NewTimer(sec, function() timer = nil; CdmAdvisor.MaybePrompt() end)
        end
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("SPELLS_CHANGED")      -- a new ability (levelling) can bring a new aura
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                if pending then pending = false; Later(2) end
            else
                Later(event == "PLAYER_ENTERING_WORLD" and 10 or 3)
            end
        end)
    end
end
