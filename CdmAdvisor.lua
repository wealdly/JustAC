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
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local L =LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local FIELD_ACTIVE, FIELD_LAYOUTS, FIELD_NAMES = 2, 3, 4
local LAYOUT_CATEGORY_OVERRIDES = 2

local function Forever() return SpellDB and SpellDB.IsForever and SpellDB.IsForever() or false end

local function Addon()
    local AceAddon = LibStub("AceAddon-3.0", true)
    return AceAddon and AceAddon:GetAddon("JustAssistedCombat", true)
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
            if (g.t == "buff" or g.t == "dot" or g.t == "debuff") and g.id then set[R1(g.id)] = true end
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

local function Secret(v)
    return BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(v) or false
end

--- The category an entry shows in with no layout override, as Blizzard's settings build it
--- (CooldownViewerSettingsDataProvider CheckBuildDisplayData): flagged HideByDefault, an aura
--- or spell entry starts in its "Not displayed" group; item and racial groups are their own.
local function DefaultCategory(info, cat)
    local C, F = Enum.CooldownViewerCategory, Enum.CooldownSetSpellFlags
    local base = info.category or cat
    local flags = info.flags
    if not (F and F.HideByDefault and type(flags) == "number" and not Secret(flags)) then return base end
    if bit.band(flags, F.HideByDefault) == 0 then return base end
    if base == C.TrackedBuff or base == C.TrackedBar then return C.HiddenPassive end
    if base == C.Essential or base == C.Utility then return C.HiddenActive end
    return base
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
                if hit then out[cid] = DefaultCategory(info, cat) end
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

-- ── Coverage report ─────────────────────────────────────────────────────────
-- Read only (/jac inspect coverage). The Cooldown Manager can track only what Blizzard gave an
-- aura entry, so each of the player's periodic spells is one of: tracked, hidden (an entry
-- that could be tracked), hidden by the player, cooldown-only (an entry, but not an aura one)
-- or unavailable (no entry: cast timing is all there will ever be).

--- The player's own periodic spells from the spellbook, one per rank base:
--- { [base] = { id, kind } }, kind "dot", "debuff" (a maintained target aura) or "hot".
local function KnownPeriodicSpells()
    local out = {}
    if not (SpellDB and BlizzardAPI and BlizzardAPI.ReadSpellbookSpells) then return out end
    for _, id in ipairs(BlizzardAPI.ReadSpellbookSpells()) do
        if not Secret(id) and type(id) == "number" then
            local kind
            if SpellDB.IsTargetDot and SpellDB.IsTargetDot(id) then
                kind = "dot"
            elseif SpellDB.IsTrackedTargetAura and SpellDB.IsTrackedTargetAura(id) then
                kind = "debuff"
            elseif SpellDB.IsPeriodicHeal and SpellDB.IsPeriodicHeal(id) then
                kind = "hot"
            end
            local base = R1(id)
            if kind and not out[base] then out[base] = { id = id, kind = kind } end
        end
    end
    return out
end

local KIND_ORDER = { dot = 1, debuff = 2, hot = 3 }

--- state as CdmAdvisor.Status, plus one row per known periodic spell, sorted by kind and name:
--- { id, kind, name, status, reads, reason }. reads is the tracked icon's live answer (true /
--- false), nil when it does not answer or the spell is not tracked; reason says why.
function CdmAdvisor.Coverage()
    local state = CdmAdvisor.Status()
    if state ~= "ok" and state ~= "nolayout" then return state, {} end
    local _, layout = LoadAndSync()
    local r = Record() or { declined = {} }
    local homes, tracked = AuraHomes(), TrackedCats()
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    local rows = {}
    for _, spell in pairs(KnownPeriodicSpells()) do
        local entries, isTracked, canAdd, playerHid = 0, false, false, false
        for cid, default in pairs(CdmAdvisor.CooldownIDsFor(spell.id)) do
            entries = entries + 1
            local eff, overridden = CdmAdvisor.EffectiveCategory(layout, cid, default)
            if tracked[eff] then
                isTracked = true
            elseif homes[eff] or homes[default] or tracked[default] then
                if overridden or r.declined[cid] then playerHid = true else canAdd = true end
            end
        end
        local status = "unavailable"
        if isTracked then status = "tracked"
        elseif canAdd then status = "hidden"
        elseif playerHid then status = "hidden-by-you"
        elseif entries > 0 then status = "cooldown-only" end
        local row = { id = spell.id, kind = spell.kind, status = status }
        row.name = C_Spell.GetSpellName(spell.id) or tostring(spell.id)
        if isTracked and MT and MT.IsTrackedAuraActive then
            local diagnostic = {}
            local ok, active = pcall(MT.IsTrackedAuraActive, spell.id, diagnostic)
            if ok and not Secret(active) then row.reads = active end
            row.reason = diagnostic.reason
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(x, y)
        if x.kind ~= y.kind then return KIND_ORDER[x.kind] < KIND_ORDER[y.kind] end
        return x.name < y.name
    end)
    return state, rows
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
local function NewLayout(data, tag, baseName, layout)
    if not tag then return nil, L["CDM state unavailable"] end
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
    if count >= MAX_LAYOUTS then return nil, L["CDM layouts full"] end
    local name, n = baseName, 1
    while taken[name] do n = n + 1; name = baseName .. " " .. n end
    local id = maxID + 1
    data[FIELD_LAYOUTS][tag] = data[FIELD_LAYOUTS][tag] or {}
    data[FIELD_LAYOUTS][tag][id] = layout
    data[FIELD_NAMES][id] = name
    data[FIELD_ACTIVE][tag] = id
    return data, layout, LayoutKey(tag, id), id, name
end

local function CreateLayout(data, tag)
    local newData, layoutOrWhy, key = NewLayout(data, tag, "JustAC", {})
    if not newData then return nil, nil, nil, layoutOrWhy end
    return newData, layoutOrWhy, key
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

-- ── Track every hidden buff (Retail and Forever) ─────────────────────────────
-- One request from the player: every aura the Cooldown Manager settings list under "Not
-- displayed" goes into a tracked panel. It is done in a layout of JustAC's own, "JAC - <spec>":
-- a copy of the spec's active layout, made active, so the player's layout is never edited and
-- switching back is the undo. Same write path as above (SetLayoutData, loaded on /reload).
-- "Not displayed" as Blizzard's settings build it (CooldownViewerSettingsDataProvider
-- CheckBuildDisplayData, CooldownViewerSettings MatchesCooldownCategory): an entry of the
-- Tracked Buffs / Bars sets flagged HideByDefault and not moved, or one the layout moved to
-- HiddenPassive. Invisible entries never show there and are left out. Unlearned ones are moved
-- too: the panels list only known entries (GetOrderedCooldownIDsForCategory without
-- allowUnknown, CooldownViewer.lua), so they stay out of sight until learned and then show
-- already tracked - one run covers later talents and ranks. Blizzard allows HiddenPassive ->
-- Tracked Buffs / Bars only, which is our move.

local function CopyDeep(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = CopyDeep(v) end
    return o
end

local function Say(msg)
    local a = Addon()
    if a and msg then a:Print(msg) end
end

local function BulkAvailable()
    local CV, C, F = C_CooldownViewer, Enum.CooldownViewerCategory, Enum.CooldownSetSpellFlags
    if not (CV and CV.GetLayoutData and CV.SetLayoutData and CV.GetCooldownViewerCategorySet
            and CV.GetCooldownViewerCooldownInfo and C_EncodingUtil) then
        return false
    end
    if not (C and C.TrackedBuff and C.TrackedBar and C.HiddenPassive and F and F.HideByDefault) then
        return false
    end
    return true
end

--- A Cooldown Manager entry we may move: readable and not invisible (learned or not).
local function Listed(info)
    if type(info) ~= "table" then return false end
    if Secret(info.flags) or Secret(info.isInvisible) then return false end
    return type(info.flags) == "number" and not info.isInvisible
end

--- Every movable aura entry under this layout (nil = Default): the "Not displayed" ones (sorted),
--- the learned ones (set: cooldownID -> true) and each one's spell for names (cooldownID -> id).
local function ScanAuras(layout)
    local CV, C = C_CooldownViewer, Enum.CooldownViewerCategory
    local hidden, learned, spells, seen = {}, {}, {}, {}
    for _, cat in ipairs({ C.TrackedBuff, C.TrackedBar }) do
        local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
        if ok and type(ids) == "table" and not Secret(ids) then
            for _, cid in ipairs(ids) do
                if not seen[cid] then
                    seen[cid] = true
                    local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, cid)
                    if okI and Listed(info) then
                        if not Secret(info.isKnown) and info.isKnown == true then learned[cid] = true end
                        local spell = info.overrideSpellID
                        if Secret(spell) or type(spell) ~= "number" then spell = info.spellID end
                        if not Secret(spell) and type(spell) == "number" then spells[cid] = spell end
                        local default = DefaultCategory(info, cat)
                        if CdmAdvisor.EffectiveCategory(layout, cid, default) == C.HiddenPassive then
                            hidden[#hidden + 1] = cid
                        end
                    end
                end
            end
        end
    end
    table.sort(hidden)
    return hidden, learned, spells
end

--- The cooldown IDs the settings list as "Not displayed" under this layout (nil = Default).
function CdmAdvisor.HiddenAuraIDs(layout)
    return (ScanAuras(layout))
end

--- "JAC - <spec>" (the class name where specs are unknown), if the game accepts it as a name.
local function JacBaseName()
    local name
    local S = C_SpecializationInfo
    if S and S.GetSpecialization and S.GetSpecializationInfo then
        local ok, spec = pcall(S.GetSpecialization)
        if ok and type(spec) == "number" then
            local okI, _, specName = pcall(S.GetSpecializationInfo, spec)
            if okI and type(specName) == "string" and specName ~= "" then name = specName end
        end
    end
    if not name and UnitClass then
        local className = UnitClass("player")
        if type(className) == "string" and className ~= "" then name = className end
    end
    if not name then return "JAC" end
    local full = "JAC - " .. name
    -- Blizzard's own check for a layout name (CooldownViewerSettingsLayoutManager IsValidLayoutName).
    if C_EditMode and C_EditMode.IsValidLayoutName then
        local ok, approved = pcall(C_EditMode.IsValidLayoutName, full)
        if not ok or approved ~= true then return "JAC" end
    end
    return full
end

--- The JAC layout recorded for this spec, if it still exists: layout, id, name, record.
local function JacLayout(data, tag)
    local r = Record()
    local rec = r and r.jac and r.jac[tag]
    local id = rec and rec.id
    local byTag = id and data and data[FIELD_LAYOUTS] and data[FIELD_LAYOUTS][tag]
    local layout = byTag and byTag[id]
    if not layout then return nil, nil, nil, rec end
    return layout, id, data[FIELD_NAMES] and data[FIELD_NAMES][id], rec
end

--- What tracking every hidden buff (or only those in `only` = { [cooldownID] = true }) would do
--- now, without writing: a plan { data, tag, layout, id, name, prev, cids, target }, or nil and
--- why not.
function CdmAdvisor.PlanTrackHidden(only)
    if not BulkAvailable() then return nil, L["CDM state unavailable"] end
    if not (GetCVarBool and GetCVarBool("cooldownViewerEnabled")) then return nil, L["CDM state disabled"] end
    local tag = SpecTag()
    if not tag then return nil, L["CDM state unavailable"] end
    local data, why = LoadData()
    if why == "unreadable" then return nil, L["CDM state unreadable"] end
    local activeID = data and data[FIELD_ACTIVE] and data[FIELD_ACTIVE][tag]
    local plan = { tag = tag }
    local layout, id, name, rec = JacLayout(data, tag)
    if layout then
        plan.data, plan.layout, plan.id, plan.name = data, layout, id, name
        -- Already on it: keep the layout recorded to go back to. Switched away since: that one.
        if activeID == id then plan.prev = rec.prev else plan.prev = activeID or false end
    else
        local active = data and CdmAdvisor.ActiveLayout(data)
        local newData, newLayout, _, newID, newName = NewLayout(data, tag, JacBaseName(), CopyDeep(active) or {})
        if not newData then return nil, newLayout end
        plan.data, plan.layout, plan.id, plan.name = newData, newLayout, newID, newName
        plan.prev = activeID or false
    end
    plan.cids, plan.learned, plan.learnedCount = {}, {}, 0
    local hidden, learned = ScanAuras(plan.layout)
    for _, cid in ipairs(hidden) do
        if not only or only[cid] then
            plan.cids[#plan.cids + 1] = cid
            if learned[cid] then
                plan.learned[cid] = true
                plan.learnedCount = plan.learnedCount + 1
            end
        end
    end
    if #plan.cids == 0 then return nil, L["CDM no hidden"] end
    -- Always Tracked Buffs: icons take far less room than a column of bars, so a player who uses
    -- the panels is least disturbed by a large batch; one who hides them never sees it.
    plan.target = Enum.CooldownViewerCategory.TrackedBuff
    return plan
end

--- Move every hidden buff (or only those in `only`) into the JAC layout and make it this spec's
--- active one. Returns the count, layout name and target panel, or 0 and why not.
function CdmAdvisor.TrackHidden(only)
    local ok, why = CanWrite()
    if not ok then return 0, why end
    local r = Record()
    if not r then return 0, L["CDM state unavailable"] end
    local plan, whyNot = CdmAdvisor.PlanTrackHidden(only)
    if not plan then return 0, whyNot end
    for _, cid in ipairs(plan.cids) do Place(plan.layout, cid, plan.target) end
    plan.data[FIELD_ACTIVE] = plan.data[FIELD_ACTIVE] or {}
    plan.data[FIELD_ACTIVE][plan.tag] = plan.id
    if not Write(plan.data) then return 0, L["CDM write failed"] end
    r.jac = r.jac or {}
    r.jac[plan.tag] = { id = plan.id, prev = plan.prev, snapshot = CopyDeep(plan.layout) }
    return #plan.cids, plan.name, plan.target
end

--- Switch this spec back to the layout it used before; delete the JAC layout if the player has
--- not changed it (a changed one is theirs to keep). Returns true, the layout switched to and
--- whether the JAC layout was kept, or false and why not.
function CdmAdvisor.UndoTrackHidden()
    local ok, why = CanWrite()
    if not ok then return false, why end
    if not BulkAvailable() then return false, L["CDM state unavailable"] end
    local tag = SpecTag()
    local r = Record()
    local rec = tag and r and r.jac and r.jac[tag]
    if not rec then return false, L["CDM nothing to undo"] end
    local data, notRead = LoadData()
    if notRead == "unreadable" then return false, L["CDM state unreadable"] end
    local layout, id = JacLayout(data, tag)
    if not layout then
        r.jac[tag] = nil
        return false, L["CDM nothing to undo"]
    end
    local layouts = data[FIELD_LAYOUTS][tag]
    local prev = rec.prev
    if not (prev and layouts[prev]) then prev = nil end
    local kept = not DeepEqual(layout, rec.snapshot)
    data[FIELD_ACTIVE] = data[FIELD_ACTIVE] or {}
    local wasActive = data[FIELD_ACTIVE][tag] == id
    if not kept then
        layouts[id] = nil
        if not next(layouts) then data[FIELD_LAYOUTS][tag] = nil end
        data[FIELD_NAMES][id] = nil
    end
    -- Switched away from it already: the player's choice of active layout stands.
    if wasActive then data[FIELD_ACTIVE][tag] = prev end
    if not Write(data) then return false, L["CDM write failed"] end
    r.jac[tag] = nil
    local nowID = data[FIELD_ACTIVE][tag]
    local nowName = L["CDM default layout"]
    if nowID and data[FIELD_NAMES] and data[FIELD_NAMES][nowID] then nowName = data[FIELD_NAMES][nowID] end
    return true, nowName, kept
end

--- Is this spec on a JAC layout JustAC can switch back from?
function CdmAdvisor.HasTrackHidden()
    if not BulkAvailable() then return false end
    local tag = SpecTag()
    local r = Record()
    return (tag and r and r.jac and r.jac[tag]) ~= nil
end

local function PanelName(cat)
    if cat == Enum.CooldownViewerCategory.TrackedBuff then return L["Tracked Buffs"] end
    return L["Tracked Bars"]
end

--- One line for the options panel: how many buffs are hidden, and the JAC layout in use.
function CdmAdvisor.TrackHiddenStatus()
    local lines = {}
    local plan, why = CdmAdvisor.PlanTrackHidden()
    if plan then
        lines[1] = L["CDM hidden count"]:format(#plan.cids, PanelName(plan.target), plan.name)
    elseif why then
        lines[1] = why
    end
    if CdmAdvisor.HasTrackHidden() then
        local data = LoadData()
        local _, _, name = JacLayout(data, SpecTag())
        if name then lines[#lines + 1] = L["CDM on jac layout"]:format(name) end
    end
    return table.concat(lines, "\n")
end

-- Add All (learned or not: unlearned ones show once learned) or only the ones learned now.
-- Index callbacks, as for the prompts below; data = the learned set from the plan shown.
StaticPopupDialogs["JUSTAC_CDM_TRACK_HIDDEN"] = {
    text = "%s",
    button1 = L["CDM add all"],
    button2 = L["CDM add learned"],
    button3 = CANCEL or L["Not now"],
    selectCallbackByIndex = true,
    OnButton1 = function() C_Timer.After(0, function() CdmAdvisor.RunTrackHidden() end) end,
    OnButton2 = function(_, learned)
        C_Timer.After(0, function() CdmAdvisor.RunTrackHidden(learned) end)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

--- Button and /jac cdm track-hidden: refuse now if a write is not allowed, else confirm first.
function CdmAdvisor.ConfirmTrackHidden()
    local ok, why = CanWrite()
    if not ok then Say(why); return end
    local plan, whyNot = CdmAdvisor.PlanTrackHidden()
    if not plan then Say(whyNot); return end
    StaticPopup_Show("JUSTAC_CDM_TRACK_HIDDEN",
        L["CDM track hidden confirm"]:format(PanelName(plan.target), plan.name, plan.learnedCount, #plan.cids),
        nil, plan.learned)
end

function CdmAdvisor.RunTrackHidden(only)
    local n, nameOrWhy, target = CdmAdvisor.TrackHidden(only)
    if n > 0 then
        CdmAdvisor.OfferReload(L["CDM track hidden done"]:format(n, PanelName(target), nameOrWhy))
    else
        Say(nameOrWhy)
    end
end

--- Button and /jac cdm undo.
function CdmAdvisor.RunUndoTrackHidden()
    local ok, nameOrWhy, kept = CdmAdvisor.UndoTrackHidden()
    if not ok then Say(nameOrWhy); return end
    if kept then
        CdmAdvisor.OfferReload(L["CDM undo kept"]:format(nameOrWhy))
    else
        CdmAdvisor.OfferReload(L["CDM undo done"]:format(nameOrWhy))
    end
end

-- ── Prompts ─────────────────────────────────────────────────────────────────
-- Both clients, short, out of combat, and only two kinds:
--   * once per spec, the first time this runs: the Cooldown Manager is off -> offer to turn it on
--     (kept invisible, or shown) and track every hidden buff; on -> offer to track the buffs it
--     hides (and to make its panels invisible);
--   * after that, only when a newly learned skill brings a buff the Cooldown Manager hides.
-- Every prompt can add all. "Not now" is not asked again for the same buffs; "Don't ask again"
-- (or the options dropdown) stops them. Turning the Cooldown Manager on writes a game-wide
-- setting, so it is only ever the player's click (MaintenanceTracker.SetCooldownManagerEnabled).

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

--- "detect" (prompt for new hidden buffs) or "manual". The old "Don't ask again" means manual.
function CdmAdvisor.GetMode()
    local r = Record()
    if not r then return "manual" end
    if r.mode then return r.mode end
    if r.neverAsk then return "manual" end
    return "detect"
end

function CdmAdvisor.SetMode(mode)
    local r = Record()
    if not r then return end
    r.mode = mode
    if mode == "detect" then
        r.neverAsk = nil
        CdmAdvisor.MaybePrompt()
    end
end

local CDM_HIDE_KEYS = { "hideCdmEssential", "hideCdmUtility", "hideCdmTrackedBuff", "hideCdmTrackedBar" }

--- Turn the Cooldown Manager on for JustAC (game setting + "let JustAC manage it"), and with
--- `hide` make every panel invisible (they keep working). Returns true, or false after saying why.
local function EnableCooldownManager(hide)
    local a = Addon()
    local profile = a and a.db and a.db.profile
    if not profile then return false end
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    if not (GetCVarBool and GetCVarBool("cooldownViewerEnabled")) then
        local applied, reason = false, "unavailable"
        if MT and MT.SetCooldownManagerEnabled then applied, reason = MT.SetCooldownManagerEnabled(true) end
        if not applied then
            if reason == "combat" then Say(L["Cooldown Manager combat warning"])
            else Say(L["Cooldown Manager enable failed"]:format(tostring(reason))) end
            return false
        end
    end
    profile.cooldownManagerEnable = true
    if hide then
        for _, key in ipairs(CDM_HIDE_KEYS) do profile[key] = true end
    end
    if MT and MT.ApplyViewerVisibility then MT.ApplyViewerVisibility(profile) end
    return true
end

local function AddAll(enable, hide)
    if enable and not EnableCooldownManager(hide) then return end
    CdmAdvisor.RunTrackHidden()
end

local function NeverAsk() CdmAdvisor.SetMode("manual") end

-- Index callbacks (StaticPopup_OnClick selectCallbackByIndex, both clients): without them a
-- fourth button falls through to OnCancel. Each returns nil so the dialog closes; a follow-up
-- popup (reload) opens once this one has closed.
local function Then(enable, hide)
    return function() C_Timer.After(0, function() AddAll(enable, hide) end) end
end

StaticPopupDialogs["JUSTAC_CDM_OFF"] = {
    text = L["CDM off prompt"],
    button1 = L["CDM on hidden"],
    button2 = L["CDM on visible"],
    button3 = L["Not now"],
    button4 = L["Don't ask again"],
    selectCallbackByIndex = true,
    OnButton1 = Then(true, true),
    OnButton2 = Then(true, false),
    OnButton4 = NeverAsk,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["JUSTAC_CDM_INTRO"] = {
    text = L["CDM intro prompt"],
    button1 = L["CDM add all"],
    button2 = L["CDM add all hide"],
    button3 = L["Not now"],
    button4 = L["Don't ask again"],
    selectCallbackByIndex = true,
    OnButton1 = Then(false, false),
    OnButton2 = Then(true, true),
    OnButton4 = NeverAsk,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- One prompt for every new buff: ones learned while it is open are merged into it, and one
-- learned while a reload is still on offer replaces that offer (Add offers it again; the other
-- answers put it back), so the player never reloads between two of these.
local shownNew      -- cooldownID set in the open new-buff prompt
local reloadDue     -- a written layout still waits for the reload this prompt replaced

local function ReofferReload()
    if reloadDue then
        reloadDue = false
        C_Timer.After(0, function() CdmAdvisor.OfferReload(L["CDM reload pending"]) end)
    end
end

StaticPopupDialogs["JUSTAC_CDM_NEW"] = {
    text = L["CDM new prompt"],
    button1 = L["CDM add"],
    button2 = L["CDM add all"],
    button3 = L["Not now"],
    button4 = L["Don't ask again"],
    selectCallbackByIndex = true,
    OnButton1 = function(_, only)
        shownNew, reloadDue = nil, false
        C_Timer.After(0, function() CdmAdvisor.RunTrackHidden(only) end)
    end,
    OnButton2 = function()
        shownNew, reloadDue = nil, false
        C_Timer.After(0, function() AddAll(false, false) end)
    end,
    OnButton3 = function() shownNew = nil; ReofferReload() end,
    OnButton4 = function() shownNew = nil; NeverAsk(); ReofferReload() end,
    -- A button answers it: Escape would skip the reload it may stand in for.
    timeout = 0, whileDead = true, hideOnEscape = false,
}

local POPUPS = { "JUSTAC_CDM_OFF", "JUSTAC_CDM_INTRO", "JUSTAC_CDM_NEW", "JUSTAC_CDM_TRACK_HIDDEN", "JUSTAC_CDM_RELOAD" }

local pending   -- a check is due once combat ends

local function SpellNames(cids, spells)
    local names = {}
    for _, cid in ipairs(cids) do
        local id = spells[cid]
        local ok, name = false, nil
        if id and C_Spell and C_Spell.GetSpellName then ok, name = pcall(C_Spell.GetSpellName, id) end
        if ok and type(name) == "string" and not Secret(name) and name ~= "" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

--- Check for a prompt: the first one for this spec, or newly learned hidden buffs.
function CdmAdvisor.MaybePrompt()
    local r = Record()
    if not r or CdmAdvisor.GetMode() ~= "detect" then return end
    if InCombatLockdown() then pending = true; return end
    if CooldownViewerSettings and CooldownViewerSettings:IsShown() then return end
    local newOpen, reloadOpen = false, false
    if StaticPopup_Visible then
        for _, name in ipairs(POPUPS) do
            if StaticPopup_Visible(name) then
                if name == "JUSTAC_CDM_NEW" then newOpen = true
                elseif name == "JUSTAC_CDM_RELOAD" then reloadOpen = true
                else return end
            end
        end
    end
    if not BulkAvailable() then return end
    local tag = SpecTag()
    if not tag then return end
    r.intro = r.intro or {}
    r.seen = r.seen or {}
    local on = GetCVarBool and GetCVarBool("cooldownViewerEnabled")
    if not on then
        -- One offer to turn it on, per character (the setting is game-wide).
        if not r.offeredOn then
            r.offeredOn = true
            r.intro[tag] = true
            StaticPopup_Show("JUSTAC_CDM_OFF")
        end
        return
    end
    local data, why = LoadData()
    if why == "unreadable" then return end
    local hidden, learned, spells = ScanAuras(data and CdmAdvisor.ActiveLayout(data))
    local seen = r.seen[tag]
    local fresh, freshSet = {}, {}
    for _, cid in ipairs(hidden) do
        if learned[cid] and not (seen and seen[cid]) then fresh[#fresh + 1] = cid; freshSet[cid] = true end
    end
    -- What is learned now is the baseline: later only a newly learned hidden buff prompts.
    r.seen[tag] = seen or {}
    for cid in pairs(learned) do r.seen[tag][cid] = true end
    -- Its first prompt already went (the offer to turn the Cooldown Manager on): baseline only.
    if not seen and r.intro[tag] then return end
    if #fresh == 0 then
        r.intro[tag] = true
        return
    end
    if not r.intro[tag] then
        r.intro[tag] = true
        StaticPopup_Show("JUSTAC_CDM_INTRO", #fresh)
        return
    end
    -- Fold in what the open prompt already offers, then show one prompt for all of it.
    if newOpen and shownNew then
        for cid in pairs(shownNew) do
            if not freshSet[cid] then fresh[#fresh + 1] = cid; freshSet[cid] = true end
        end
    end
    local names = SpellNames(fresh, spells)
    if #names == 0 then return end
    if newOpen then StaticPopup_Hide("JUSTAC_CDM_NEW") end
    if reloadOpen then
        StaticPopup_Hide("JUSTAC_CDM_RELOAD")
        reloadDue = true
    end
    shownNew = freshSet
    StaticPopup_Show("JUSTAC_CDM_NEW", table.concat(names, ", "), nil, freshSet)
end

do
    local f = CreateFrame("Frame")
    local timer
    local function Later(sec)
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(sec, function() timer = nil; CdmAdvisor.MaybePrompt() end)
    end
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("SPELLS_CHANGED")      -- a new skill, rank or talent can bring a new buff
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then pending = false; Later(2) end
        else
            Later(event == "PLAYER_ENTERING_WORLD" and 10 or 3)
        end
    end)
end
