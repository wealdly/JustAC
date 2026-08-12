-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: alternate rotation source.
--
-- Consumes imported action priority lists (flattened, per context) and hands the
-- queue a spell list for positions 2+. Each entry may carry secret-safe GATES
-- (cooldown / dot / proc / buff-window / execute / targets) classified offline by
-- tools/gen_simc_rotations.py; the runtime evaluator (SpellQueue) applies them.
-- This module reads no combat state, so it is safe under 12.0 secret values.
--
-- Data is registered by Data/SimcRotations.lua (from SimulationCraft's GPL-3.0
-- action priority lists; provenance in that file and tools/simc-apl/).

local RotationImport = LibStub:NewLibrary("JustAC-RotationImport", 1)
if not RotationImport then return end

-- specKey (e.g. "DRUID_2") -> { st = {entry,...}, aoe = {...}, burst = {id,...} }
-- entry = { id = <spellID>, gates = { {t="cd"}, {t="dot",id=..}, {t="proc"},
--           {t="buff",id=..,neg=bool}, {t="execute"}, {t="targets",..} }, delegated = bool,
--           empower = <release stage for an empowered cast, absent for everything else> }
-- burst = plain spell ids: the APL's sync anchors (what SimC pots/trinkets
-- into), consumed by SpellQueue's burst-ready cue.
local rotations = RotationImport._rotations or {}
RotationImport._rotations = rotations
local lookupCache = {}  -- specKey -> ctx -> (id|baseID) -> { rank, gates, delegated }
local empowerCache = {} -- specKey -> (id|baseID) -> tier | false (contexts disagree)
local cachedSpellDB     -- lazy module ref (see GetEntry)

--- Register GATED rotation tables (the generated format above).
function RotationImport.RegisterGated(data)
    if type(data) ~= "table" then return end
    for specKey, entry in pairs(data) do
        rotations[specKey] = entry
        lookupCache[specKey] = nil
        empowerCache[specKey] = nil
    end
end

local function EntriesFor(context)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local entry = specKey and rotations[specKey]
    if not entry then return nil end
    local list = entry[context or "st"] or entry.st
    return (type(list) == "table") and list or nil
end

--- Gated entries for the current spec + context, filtered to spells the player
--- knows/has talented (IsPlayerSpell is static -> secret-safe). nil if none.
--- Diagnostic accessor: the runtime reaches entries through GetEntry instead.
--- @param context string|nil - "st" (default) | "aoe"
function RotationImport.GetRotationGated(context)
    local list = EntriesFor(context)
    if not list then return nil end
    local out, n = {}, 0
    for i = 1, #list do
        local e = list[i]
        if e and e.id and (not IsPlayerSpell or IsPlayerSpell(e.id)) then
            n = n + 1
            out[n] = e
        end
    end
    return n > 0 and out or nil
end

--- The same list flattened to bare spell IDs.
--- @param context string|nil - "st" (default) | "aoe"
function RotationImport.GetRotation(context)
    local gated = RotationImport.GetRotationGated(context)
    if not gated then return nil end
    local out = {}
    for i = 1, #gated do out[i] = gated[i].id end
    return out
end

--- True when this module has data for the current spec.
function RotationImport.HasRotation()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    return specKey ~= nil and rotations[specKey] ~= nil
end

--- SimC burst anchors for the current spec (ordered cast ids), or nil.
--- The offline generator derives these from potion/trinket/external-buff sync
--- conditions - SimC's explicit marker for the spec's burst window.
function RotationImport.GetBurstTriggers()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local entry = specKey and rotations[specKey]
    local b = entry and entry.burst
    return (type(b) == "table" and #b > 0) and b or nil
end

--------------------------------------------------------------------------------
-- Refiner lookup: rank + gates for AC's fixed-queue spells.
-- The queue hands us AC's rotation spell ids; we return the SimC priority RANK
-- (list index, lower = higher priority) and the entry's secret-safe gates. Ids are
-- matched directly AND by talent-base id (BlizzardAPI.ResolveSpellID) so AC's ids
-- line up with the SimC data ids across override chains.
--------------------------------------------------------------------------------
local BlizzardAPI
local function baseID(id)
    if not BlizzardAPI then BlizzardAPI = LibStub("JustAC-BlizzardAPI", true) end
    return (BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(id)) or id
end

local function BuildLookup(specKey)
    local rot = rotations[specKey]
    if not rot then return nil end
    local byCtx = {}
    for ctx, list in pairs(rot) do
        -- "burst" holds plain ids for the cue, not gated entries - never a context.
        if ctx ~= "burst" and type(list) == "table" then
            local m = {}
            for i = 1, #list do
                local e = list[i]
                if e and e.id and not m[e.id] then
                    local rec = { rank = i, gates = e.gates, delegated = e.delegated }
                    m[e.id] = rec
                    local b = baseID(e.id)
                    if b ~= e.id and not m[b] then m[b] = rec end
                end
            end
            byCtx[ctx] = m
        end
    end
    lookupCache[specKey] = byCtx
    return byCtx
end

--- Wipe the rank-lookup cache. BuildLookup bakes talent-DEPENDENT override
--- resolution (baseID via ResolveSpellID) into the map, so a talent change
--- within the same spec must invalidate it - specKey alone doesn't move.
function RotationImport.InvalidateLookup()
    wipe(lookupCache)
    wipe(empowerCache)
end

--------------------------------------------------------------------------------
-- Empower release tier
--------------------------------------------------------------------------------
-- An empowered cast (Evoker's Fire Breath / Eternity Surge, Blood's Consumption) is held
-- and released at a stage. `empower` on an entry is SimC's chosen stage for that line.
-- It is data, never a gate: it does not decide whether to press, only how long to hold.
--
-- Answered WITHOUT a context argument on purpose. The tier IS context-sensitive in
-- principle - Eternity Surge picks its stage by target count - so instead of plumbing the
-- queue's context down to the icon for one spell, a tier is reported only when every
-- context list naming the spell agrees on it. That is the same fail direction the
-- generator already takes when SimC's own lines disagree, and it means the number on the
-- icon is right or absent, never wrong. Today exactly one entry in the whole dataset is
-- ambiguous this way (Devastation's Eternity Surge: tier 1 at single target, undecidable
-- in AoE because SimC's thresholds there are talent-dependent), so the cost is one hint.
local function BuildEmpower(specKey)
    local rot = rotations[specKey]
    if not rot then return nil end
    local m, seenAt = {}, {}
    for ctx, list in pairs(rot) do
        if ctx ~= "burst" and type(list) == "table" then
            for i = 1, #list do
                local e = list[i]
                if e and e.id then
                    -- A spell PRESENT in a list with no tier is a disagreement, not a
                    -- missing data point: SimC named it there and declined to say. Record
                    -- the sighting separately from the value so `nil` still counts.
                    if seenAt[e.id] and m[e.id] ~= e.empower then
                        m[e.id] = false
                    elseif not seenAt[e.id] then
                        m[e.id] = e.empower
                    end
                    seenAt[e.id] = true
                end
            end
        end
    end
    -- Mirror onto talent-base ids, exactly as the rank lookup does, so AC's ids line up
    -- across override chains. Collected first and written after: inserting keys into a
    -- table while pairs() is walking it is undefined in Lua.
    local mirrored
    for id, tier in pairs(m) do
        local b = baseID(id)
        if b ~= id and m[b] == nil then
            mirrored = mirrored or {}
            mirrored[b] = tier
        end
    end
    if mirrored then
        for b, tier in pairs(mirrored) do
            if m[b] == nil then m[b] = tier end
        end
    end
    empowerCache[specKey] = m
    return m
end

--- SimC's release stage for an empowered cast, or nil when there is none or the lists
--- disagree. Plain static data - reads no combat state.
function RotationImport.GetEmpowerTier(spellID)
    if not spellID then return nil end
    local SpellDB = cachedSpellDB
    if not SpellDB then
        SpellDB = LibStub("JustAC-SpellDB", true)
        cachedSpellDB = SpellDB
    end
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return nil end
    local m = empowerCache[specKey] or BuildEmpower(specKey)
    if not m then return nil end
    local tier = m[spellID]
    if tier == nil then tier = m[baseID(spellID)] end
    if tier == false then return nil end   -- contexts disagreed: say nothing
    return tier
end

-- A missing context tier falls back to a broader/base one.
local CTX_FALLBACK = { st = { "st" }, cleave = { "cleave", "aoe", "st" }, aoe = { "aoe", "st" } }

--- { rank, gates, delegated } for spellID in the current spec + context, or nil.
--- @param context string|nil "st" (default) | "cleave" | "aoe"
function RotationImport.GetEntry(spellID, context)
    if not spellID then return nil end
    -- Lazy module ref: this runs per rotation spell per build in SimC mode, and the
    -- LibStub lookup per call was pure overhead (GetSpecKey memoizes on its own).
    local SpellDB = cachedSpellDB
    if not SpellDB then
        SpellDB = LibStub("JustAC-SpellDB", true)
        cachedSpellDB = SpellDB
    end
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return nil end
    local byCtx = lookupCache[specKey] or BuildLookup(specKey)
    if not byCtx then return nil end
    -- Use the best AVAILABLE context list, then look up ONLY in it. A spell the
    -- generator excluded from that context (e.g. a single-target ability absent from
    -- the AoE list) must sink to unranked - NOT inherit a rank from a broader context.
    local order = CTX_FALLBACK[context or "st"] or CTX_FALLBACK.st
    local m
    for i = 1, #order do
        if byCtx[order[i]] then m = byCtx[order[i]]; break end
    end
    if not m then return nil end
    return m[spellID] or m[baseID(spellID)]
end

