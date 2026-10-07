-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: alternate rotation source.
--
-- Consumes imported action priority lists (flattened, per context) and hands the
-- queue a spell list for positions 2+. Each entry may carry secret-safe GATES
-- (buff-window / cooldown / dot / execute / health / power / resource / stack / stealth) classified
-- offline by tools/gen_simc_rotations.py; SpellQueue evaluates the buff, resource, power,
-- health, stack, stealth and execute kinds (cd/dot are informational, read by the diagnostics).
-- This module reads no combat state, so it is safe under 12.0 secret values.
--
-- Data is registered by Data/SimcRotations.lua (from SimulationCraft's GPL-3.0
-- action priority lists; provenance in that file and tools/simc-apl/).

local RotationImport = LibStub:NewLibrary("JustAC-RotationImport", 1)
if not RotationImport then return end

-- specKey (e.g. "DRUID_2") -> { st = {entry,...}, aoe = {...}, burst = {id,...} }
-- entry = { id = <spellID>, gates = { {t="buff",id=..,dur=secs|nil,neg=bool}, {t="cd"}, {t="dot",id=..},
--           {t="execute",pct=..}, {t="health",pct=..}, {t="power",..}, {t="resource",..},
--           {t="stack",id=..,op=..,n=..}, {t="stealth",neg=bool} }, delegated = bool,
--           empower = <release stage for an empowered cast, absent for everything else> }
-- burst = plain spell ids: the APL's sync anchors (what SimC pots/trinkets
-- into), consumed by SpellQueue's burst-ready cue.
local rotations = RotationImport._rotations or {}
RotationImport._rotations = rotations
local lookupCache = {}  -- specKey -> ctx -> (id|baseID) -> { rank, gates, delegated }
local empowerCache = {} -- specKey -> (id|baseID) -> tier | false (contexts disagree)
local insertableCache = {} -- specKey -> ids the pool may gain (see GetInsertable)
-- SimC lines the addon could time but should still never ADD: abilities the theorycraft
-- weaves for damage that a player presses for another reason. Blizzard's list leaves these
-- out on purpose. Movement is covered separately by the spec's gap-closer list.
local NEVER_INSERT = {
    [46585]  = true,  -- Raise Dead (pet summon)
    [122470] = true,  -- Touch of Karma (defensive)
    [322101] = true,  -- Expel Harm (self-heal)
    [1160]   = true,  -- Demoralizing Shout (mitigation)
    [384110] = true,  -- Wrecking Throw (situational: absorb shields)
    [64382]  = true,  -- Shattering Throw (situational: absorb shields)
    [385952] = true,  -- Shield Charge (moves you)
    [198793] = true,  -- Vengeful Retreat (leaps you backward)
    [189110] = true,  -- Infernal Strike (leaps you)
    [1271985]= true,  -- Champion's Leap (leaps you)
    [357210] = true,  -- Deep Breath (flies you forward)
    [443454] = true,  -- Ancestral Swiftness (utility)
}
local cachedSpellDB     -- lazy module ref (see GetEntry)

--- Register GATED rotation tables (the generated format above).
function RotationImport.RegisterGated(data)
    if type(data) ~= "table" then return end
    for specKey, entry in pairs(data) do
        rotations[specKey] = entry
        lookupCache[specKey] = nil
        empowerCache[specKey] = nil
    end
    wipe(insertableCache)
end

--------------------------------------------------------------------------------
-- WoW Forever (Data/ForeverRotations.lua). One spec id per class; the guides' trees
-- (Arms / Fury / Protection...) are trait GROUPS inside it. So the class key carries
-- every tree, and the one with the most talent points spent is INSTALLED as that key's
-- rotation - after which every reader in this file works unchanged. Re-picked on every
-- InvalidateLookup (SPELLS_CHANGED fires on talent changes) and, for druids, on form
-- change (Feral covers cat and bear). Design: Documentation/FOREVER_ENGINE_DESIGN.md.
--------------------------------------------------------------------------------
local foreverTrees = {}   -- "WARRIOR_F" -> { default = "arms", arms = { st = ..., aoe = ... }, ... }
local rankBase = {}       -- any rank's id -> rank 1 id
local rankChain = {}      -- rank 1 id -> { rank1, rank2, ... } (learn order)
local installed = {}      -- specKey -> tree key installed since the last invalidation
local classAbilities = {} -- "WARRIOR_F" -> { [rank-1 id] = true } for every class ability
local BEAR_FORMS = { [5] = true, [8] = true }   -- Bear, Dire Bear (GetShapeshiftFormID)

function RotationImport.RegisterForever(classes, chains, abilities)
    if type(classes) ~= "table" then return end
    -- WoW Forever only. Without this, retail registered every Forever rank chain too, and the
    -- 131 rank-1 ids retail shares (Rend, Moonfire, Polymorph...) resolved through Forever's
    -- ranks everywhere a rank is consulted. Here, not in the data file: it survives regeneration.
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not (SpellDB and SpellDB.IsForever and SpellDB.IsForever()) then return end
    for key, trees in pairs(classes) do foreverTrees[key] = trees end
    for key, ids in pairs(abilities or {}) do
        local set = {}
        for i = 1, #ids do set[ids[i]] = true end
        classAbilities[key] = set
    end
    for r1, chain in pairs(chains or {}) do
        rankChain[r1] = chain
        for i = 1, #chain do rankBase[chain[i]] = r1 end
    end
    RotationImport.InvalidateLookup()
end

--- Rank 1 of id's rank chain; id itself when it has no ranks.
function RotationImport.RankBase(id)
    return id and rankBase[id] or id
end

--- id's whole rank chain (rank 1 first), or nil when it has no ranks (all of retail).
function RotationImport.RankChain(id)
    local r1 = id and rankBase[id]
    return r1 and rankChain[r1] or nil
end

--- The highest rank of id's chain the player knows, or nil when they know none. Forever
--- keeps every learned rank and never upgrades a button, so "known" alone is not enough.
function RotationImport.HighestKnownRank(id)
    if not id or not IsPlayerSpell then return nil end
    local chain = rankChain[rankBase[id] or id]
    if not chain then return IsPlayerSpell(id) and id or nil end
    for i = #chain, 1, -1 do
        if IsPlayerSpell(chain[i]) then return chain[i] end
    end
    return nil
end

--- "Beast Mastery" -> "beast_mastery".
local function TreeSlug(name)
    if type(name) ~= "string" then return nil end
    return (name:lower():gsub("[^%a]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

--- Talent points spent per trait group, the same reads Forever's talent frame makes.
--- Shared with `/jac inspect forever` so the probe measures exactly what the pick reads.
--- @return table|nil displays, table spent (groupID -> points)
function RotationImport.SpentByTree()
    if not (C_ClassTalents and C_Traits and C_SpecializationInfo) then return nil end
    local okCfg, configID = pcall(C_ClassTalents.GetActiveConfigID)
    local spec = C_SpecializationInfo.GetSpecialization()
    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
    local okTree, treeID = pcall(C_ClassTalents.GetTraitTreeForSpec, specID)
    if not (okCfg and configID and okTree and treeID) then return nil end
    local okD, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    if not okD or type(displays) ~= "table" then return nil end
    local ids = {}
    for i, d in ipairs(displays) do ids[i] = d.groupID end
    local okC, infos = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
    local spent = {}
    for _, gi in ipairs((okC and type(infos) == "table") and infos or {}) do
        local c = gi.currencyInfos and gi.currencyInfos[1]
        spent[gi.traitNodeGroupID] = c and (c.spentInTree or c.spent)
    end
    return displays, spent
end

local function InBearForm()
    return GetShapeshiftFormID and BEAR_FORMS[GetShapeshiftFormID() or 0] or false
end

--- The tree to run: most points spent wins; none spent (or unreadable) is the class default.
local function PickTree(trees)
    local best, bestSpent = nil, 0
    local displays, spent = RotationImport.SpentByTree()
    for _, d in ipairs(displays or {}) do
        local n = spent[d.groupID]
        if type(n) == "number" and not (issecretvalue and issecretvalue(n)) and n > bestSpent then
            local slug = TreeSlug(d.displayName)
            local first = slug and slug:match("^[^_]+")   -- "feral_combat" -> "feral"
            local key = (slug and trees[slug] and slug) or (first and trees[first] and first)
            if key then best, bestSpent = key, n end
        end
    end
    best = best or trees.default
    if best == "feral" and trees.feral_bear and InBearForm() then best = "feral_bear" end
    return best
end

--- THE rotation reader: the registered table for specKey, installing the Forever tree first.
local function Rot(specKey)
    local trees = specKey and foreverTrees[specKey]
    if trees and not installed[specKey] then
        local key = PickTree(trees)
        rotations[specKey] = type(trees[key]) == "table" and trees[key] or nil
        installed[specKey] = key or "none"   -- truthy: no re-pick per read until invalidated
    end
    return specKey and rotations[specKey]
end

local function CurrentSpecKey()
    local SpellDB = cachedSpellDB or LibStub("JustAC-SpellDB", true)
    cachedSpellDB = SpellDB
    return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
end

--- Is id one of the player's class abilities (any rank), as opposed to a profession,
--- tracking or racial spell that happens to sit on a bar (Find Minerals)? true when there
--- is no data to say (retail).
function RotationImport.IsClassAbility(id)
    local set = classAbilities[CurrentSpecKey()]
    if not set then return true end
    return set[RotationImport.RankBase(id)] == true
end

--- The Forever tree currently installed for this character, or nil (diagnostics).
function RotationImport.GetForeverTree()
    local specKey = CurrentSpecKey()
    Rot(specKey)
    return specKey and installed[specKey] or nil
end

--- A shapeshift happened. Only the Feral tree's cat / bear choice depends on form, so only
--- that flip re-picks. @return true when the installed list changed.
function RotationImport.OnFormChanged()
    local key = installed[CurrentSpecKey() or ""]
    if key ~= "feral" and key ~= "feral_bear" then return false end
    if (key == "feral_bear") == (InBearForm() and true or false) then return false end
    RotationImport.InvalidateLookup()
    return true
end

local function EntriesFor(context)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local entry = Rot(specKey)
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

--- Spell ids the SimC data could ADD to the pool for the current spec: every line for the
--- spell, in every context, is one the addon can evaluate itself (not delegated). A
--- delegated line means "only Blizzard's pick knows when", and inserting that would be
--- suggesting an ability with no idea whether this is its moment - which is also what keeps
--- out the movement abilities SimC weaves for damage. Static per spec, so built once.
function RotationImport.GetInsertable()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = CurrentSpecKey()
    local rot = Rot(specKey)
    if not rot then return nil end
    local cached = insertableCache[specKey]
    if cached then return cached end
    -- "Delegated" means "condition unreadable". Only a game pick can time such an entry, so
    -- with no pick (Forever) it still belongs in the pool - the lead rule keeps it off slot 1.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local insertDelegated = not (BAPI and BAPI.HasGamePick and BAPI.HasGamePick())
    local ok, order = {}, {}
    for ctx, list in pairs(rot) do
        if ctx ~= "burst" and type(list) == "table" then
            for i = 1, #list do
                local e = list[i]
                if e and e.id then
                    if ok[e.id] == nil then order[#order + 1] = e.id end
                    ok[e.id] = (ok[e.id] ~= false) and (insertDelegated or not e.delegated)
                end
            end
        end
    end
    local moves = {}
    for _, id in ipairs(SpellDB.CLASS_GAPCLOSER_DEFAULTS and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey] or {}) do
        moves[id] = true
    end
    local out = {}
    for i = 1, #order do
        local id = order[i]
        -- Forever lists name rank 1; offer the rank the player would actually press
        -- (an id without ranks passes through unchanged).
        if ok[id] and not NEVER_INSERT[id] and not moves[id] then
            out[#out + 1] = RotationImport.HighestKnownRank(id) or id
        end
    end
    insertableCache[specKey] = out
    return out
end

--- True when this module has data for the current spec.
function RotationImport.HasRotation()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    return specKey ~= nil and Rot(specKey) ~= nil
end

--- SimC burst anchors for the current spec (ordered cast ids), or nil.
--- The offline generator derives these from potion/trinket/external-buff sync
--- conditions - SimC's explicit marker for the spec's burst window.
function RotationImport.GetBurstTriggers()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local entry = Rot(specKey)
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
    -- Forever: any rank of a chain is its rank 1, the id the data names - the ONE place
    -- ranks are resolved for lookup (a button keeps the rank it was dragged with).
    local r1 = rankBase[id]
    if r1 then return r1 end
    if not BlizzardAPI then BlizzardAPI = LibStub("JustAC-BlizzardAPI", true) end
    return (BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(id)) or id
end

--------------------------------------------------------------------------------
-- Blizzard's own priority order (Data/AssistedCombatOrder.lua, from the client's
-- assisted-combat tables): spec -> spell id -> rank, a spell's unconditional position.
-- The tiebreaker for "Match Blizzard's pick", whose context rank leaves most of the
-- tail tied. No data, or an unlisted spell, answers nil and the caller keeps today's
-- behaviour - Blizzard can reshape these tables in any patch.
--------------------------------------------------------------------------------
local blizzardOrder = {}
function RotationImport.RegisterBlizzardOrder(data)
    if type(data) == "table" then blizzardOrder = data end
end

--- Blizzard's rank for spellID in the current spec (lower = earlier), or nil.
function RotationImport.GetBlizzardRank(spellID)
    local SpellDB = cachedSpellDB or LibStub("JustAC-SpellDB", true)
    cachedSpellDB = SpellDB
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local order = specKey and blizzardOrder[specKey]
    if not order or not spellID then return nil end
    return order[spellID] or order[baseID(spellID)]
end

local function BuildLookup(specKey)
    local rot = Rot(specKey)
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
    -- Forever: talents (or a druid's form) may now pick another tree, and the insertable
    -- ranks depend on which ranks are known.
    wipe(installed)
    wipe(insertableCache)
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
    local rot = Rot(specKey)
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

