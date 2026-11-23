-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Target-aura observations and maintained-DoT suppression.
--
-- Own casts start bounded duration estimates. Where available, the aura-instance
-- bridge handles early removal and engine refresh state. Forever additionally
-- prefers readable Cooldown Manager aura state and cancels cast estimates on
-- best-effort target miss matching. None of these requires reading secret aura
-- identity, stacks or numeric durations.
--
-- Generated tables separate observation eligibility from unconditional DoT
-- suppression. Explicit entry refreshes may use estimates; aura prerequisites
-- require evidence. See GetTargetAuraState for that distinction.
--
-- State belongs to the current target. Forever parks records under readable
-- target GUIDs across swaps; Retail starts fresh. Combat end clears tracking.
local DotTracker = LibStub:NewLibrary("JustAC-DotTracker", 2)
if not DotTracker then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

-- Hot path cache
local GetTime = GetTime
local UnitExists = UnitExists
local next = next
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local tremove = table.remove
local C_UnitAuras = C_UnitAuras
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
-- Talent variants of a DoT (Lunar Inspiration Moonfire 155625) share a base spell
-- (8921) that the cast event and the rotation list may disagree on. Keying the
-- record AND the query under both the spell and its base makes them match either
-- way. Resolution + cache live in SpellDB.GetBaseSpell (returns nil for no base).
local RotationImport = LibStub("JustAC-RotationImport", true)
local maintenanceTracker   -- resolved on first use: Cooldown Manager aura state (loads later)
local function baseOf(spellID)
    local base = SpellDB and SpellDB.GetBaseSpell and SpellDB.GetBaseSpell(spellID)
    if base then return base end
    -- Forever ranks: a cast at one rank and a query at another meet at rank 1.
    local r1 = RotationImport and RotationImport.RankBase(spellID)
    return r1 ~= spellID and r1 or nil
end

-- Unknown-duration applications yield early rather than risk a long uptime gap.
-- Known durations and readable aura evidence take precedence.
local FALLBACK_WINDOW = 12
-- Max gap between our cast and the debuff showing up in addedAuras.
local BRIDGE_WINDOW = 2.0
-- Pandemic lead: stop suppressing this fraction of the estimated duration before
-- expiry, so the DoT reappears in time to refresh inside its pandemic window.
-- Matches WoW's 30% carry-over. Only applied when a duration estimate exists.
-- WoW Forever has no carry-over (a recast restarts the DoT and loses the ticks left), so
-- there the DoT comes back its refresh lead before it runs out (BlizzardAPI.GetPeriodicRefreshLead):
-- its cast time, plus a global cooldown for a stacking one. An instant comes back as it ends.
local FOREVER = (SpellDB and SpellDB.IsForever and SpellDB.IsForever()) and true or false
local PANDEMIC_LEAD = FOREVER and 0 or 0.30
-- Harmful auras cast by the player - Blizzard evaluates this engine-side from the
-- NeverSecret instance ID, so it stays readable in combat.
local PLAYER_DEBUFF_FILTER = "HARMFUL|PLAYER"

local function IsTrackedAura(spellID, includeMaintenance)
    if not SpellDB then return false end
    if SpellDB.IsTargetDot and SpellDB.IsTargetDot(spellID) then return true end
    if includeMaintenance and SpellDB.IsTrackedTargetAura then
        return SpellDB.IsTrackedTargetAura(spellID)
    end
    return false
end

-- The current target's record. applied[spellID] = { expiry, pandemicPoint, hadInstance,
-- instances = { [instanceID] = true } }.
local applied = {}
-- instanceToDot[instanceID] = ids (the spell-ID list to clear on removal).
local instanceToDot = {}
-- Other targets' records, by GUID. Where the target's GUID reads plain in combat (WoW
-- Forever, measured build 70245; secret for NPCs on retail) a swap parks the record and a
-- swap back restores it, so a DoT keeps its timer on the mob it was cast on. Where the
-- GUID is secret there is only the current target, and a swap starts fresh.
local byTarget = {}       -- guid -> { applied = ..., instanceToDot = ... }
local currentGUID

local function PlainTargetGUID()
    -- Forever only: on retail a player target's GUID is plain too, and parking those records
    -- (PvP) would keep a DoT dispelled while away reading as up.
    if not FOREVER then return nil end
    local g = UnitGUID and UnitGUID("target")
    if g == nil or (issecretvalue and issecretvalue(g)) then return nil end
    return g
end
-- pendingCasts: array of { ids, time } awaiting an addedAura match.
local pendingCasts = {}

--------------------------------------------------------------------------------
-- Immunity learned per kind of creature (WoW Forever).
-- A creature's immunities are fixed per creature on the server and are in no client table,
-- so the first cast on each mob used to be wasted. An IMMUNE result matched to our cast is
-- remembered by (npc id, spell rank base):
--   * fighting alone with no pet, one sighting holds the spell back on every mob of that
--     npc id for the session: nobody else could have caused the result;
--   * with a pet out, in a group, or when that cannot be read, the result may be theirs (the
--     event names no attacker), so only the count below is kept;
--   * sightings on two different mobs are kept in the account saved variables and hold the
--     spell from then on. Counted, so a single fluke (a shield, an immune phase, another
--     attacker's result) never counts as knowledge;
--   * the Cooldown Manager showing the DoT on such a mob, or its aura instance arriving,
--     forgets the entry: the creature is not immune after all.
-- The npc id comes from the target GUID, plain in combat on Forever (measured build 70959).
-- Never generalised to a creature type: only what was seen on that npc id.
--------------------------------------------------------------------------------
local NPC_IMMUNE_CONFIRM = 2     -- sightings, each on a different mob, before disk counts
local NPC_IMMUNE_DB_CAP = 500
local NPC_SIGHTING_CAP = 2048
local sessionNpcImmune = {}      -- [npcID] = { [base] = true }
local countedSightings = {}      -- [guid] = { [base] = true }: one sighting per mob
local sightingOrder, sightingNext = {}, 1
local immuneOwner, immuneCache, immuneOrder, immuneSlots, immuneNext
local currentNPC                 -- npc id of the current target, or nil

local function NpcIdOf(guid)
    if type(guid) ~= "string" or not (BlizzardAPI and BlizzardAPI.NpcIDFromGUID) then return nil end
    return BlizzardAPI.NpcIDFromGUID(guid)
end

--- The saved table (JustACGlobal.dotImmuneNPCs[npcID][base] = sightings) and its owner, or nil.
local function ImmuneDB()
    local g = _G.JustACGlobal
    return g and g.dotImmuneNPCs, g
end

local function PrepareImmuneDB()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    if not g.dotImmuneNPCs then g.dotImmuneNPCs = {} end
    local db = g.dotImmuneNPCs
    if immuneOwner ~= g or immuneCache ~= db then
        immuneOwner, immuneCache, immuneOrder, immuneSlots, immuneNext = g, db, {}, {}, 1
        for npc in pairs(db) do
            immuneOrder[#immuneOrder + 1] = npc
            immuneSlots[npc] = #immuneOrder
        end
        g.dotImmuneNPCsN = #immuneOrder
    end
    return db, g
end

local function RemoveImmuneNPC(npc)
    local slot = immuneSlots[npc]
    if not slot then return end
    local last = #immuneOrder
    local moved = immuneOrder[last]
    if slot ~= last then
        immuneOrder[slot] = moved
        immuneSlots[moved] = slot
    end
    immuneOrder[last], immuneSlots[npc] = nil, nil
    if immuneNext > #immuneOrder then immuneNext = 1 end
end

local function ImmuneBase(spellID)
    return baseOf(spellID) or spellID
end

--- Is this spell known not to work on the current target's kind of creature?
local function NpcImmune(spellID)
    if not currentNPC then return false end
    local session, db = sessionNpcImmune[currentNPC], ImmuneDB()
    local saved = db and db[currentNPC]
    if not (session or saved) then return false end
    local base = ImmuneBase(spellID)
    if session and session[base] then return true end
    return saved ~= nil and (saved[base] or 0) >= NPC_IMMUNE_CONFIRM
end

--- Could anyone but us have produced a result on the target? True unless we are known to be
--- fighting alone with no pet.
local function OthersAttacking()
    if not (BlizzardAPI and BlizzardAPI.IsGrouped) or BlizzardAPI.IsGrouped() ~= false then return true end
    local ok, pet = pcall(UnitExists, "pet")
    if not ok or (issecretvalue and issecretvalue(pet)) then return true end
    return pet == true
end

--- An IMMUNE result was matched to our cast of these ids on the current target.
local function NoteNpcImmune(ids)
    if not (currentNPC and currentGUID) then return end
    local base = ImmuneBase(ids[1])
    if not OthersAttacking() then
        local session = sessionNpcImmune[currentNPC]
        if not session then session = {}; sessionNpcImmune[currentNPC] = session end
        session[base] = true
    end
    local counted = countedSightings[currentGUID]
    if not counted then
        if #sightingOrder >= NPC_SIGHTING_CAP then
            countedSightings[sightingOrder[sightingNext]] = nil
        end
        sightingOrder[sightingNext] = currentGUID
        sightingNext = sightingNext % NPC_SIGHTING_CAP + 1
        counted = {}
        countedSightings[currentGUID] = counted
    end
    if counted[base] then return end
    counted[base] = true
    local db, g = PrepareImmuneDB()
    local saved = db[currentNPC]
    if not saved then
        if #immuneOrder >= NPC_IMMUNE_DB_CAP then
            local evicted = immuneOrder[immuneNext]
            db[evicted], immuneSlots[evicted], sessionNpcImmune[evicted] = nil, nil, nil
            immuneOrder[immuneNext] = currentNPC
            immuneSlots[currentNPC] = immuneNext
            immuneNext = immuneNext % #immuneOrder + 1
        else
            immuneOrder[#immuneOrder + 1] = currentNPC
            immuneSlots[currentNPC] = #immuneOrder
        end
        saved = {}
        db[currentNPC] = saved
        g.dotImmuneNPCsN = #immuneOrder
    end
    saved[base] = math.min(NPC_IMMUNE_CONFIRM, (saved[base] or 0) + 1)
end

--- The spell was seen on a mob of this kind: whatever was learned about it is wrong.
local function ForgetNpcImmune(spellID)
    if not currentNPC then return end
    local base = ImmuneBase(spellID)
    local session = sessionNpcImmune[currentNPC]
    if session then session[base] = nil end
    local db, g = ImmuneDB()
    local saved = db and db[currentNPC]
    if saved and saved[base] then
        saved[base] = nil
        if not next(saved) then
            PrepareImmuneDB()
            db[currentNPC] = nil
            RemoveImmuneNPC(currentNPC)
            g.dotImmuneNPCsN = #immuneOrder
        end
    end
end

-- Did it land? UNIT_COMBAT on the target reports a dodge / parry / miss / immune as a plain
-- string in combat (measured on Forever). One that arrives within the cast's result window
-- is taken to be that cast's result, with two exceptions (the event names no attacker): a
-- result the cast cannot produce (a parried or dodged spell), and a result arriving where
-- one of our own white swings is due to report.
-- The window depends on how the cast travels (SpellDB.GetAuraDelivery, from the spell data;
-- timings measured build 70959). A cast with no missile reports in the same instant, in
-- either event order (5 of 5 melee results at 0.00s): INSTANT_WINDOW. A missile reports when
-- it arrives (Serpent Sting immune at +0.78s): from the cast to its flight over the spell's
-- maximum range plus FLIGHT_SLACK. A cast the data does not describe, or a missile whose
-- range cannot be read, keeps the old HIT_WINDOW both ways.
-- ponytail: a party member's or pet's miss, a cast landing on our swing (Heroic Strike)
-- beside a melee DoT, or a missed Auto Shot arriving during a sting's flight still cancels
-- the timer;
-- the DoT then shows once more, the cheap direction.
local MISSED = { DODGE = true, PARRY = true, MISS = true, RESIST = true, EVADE = true,
                 DEFLECT = true, REFLECT = true, IMMUNE = true }
local HIT_WINDOW = 0.4
local INSTANT_WINDOW = 0.1
local FLIGHT_SLACK = 0.25
-- The latest tracked DoT cast: { ids, time, before, after (its result window), defense (its
-- defense type, nil when unknown), missile (it flies), cancelled (a miss already took it) }.
local lastCast
local lastMissAt, lastMissKind

-- How good is the evidence behind each EvaluateDot source? "confirmed": the game or its own
-- aura instance answered. "estimated": our cast time plus a duration, never seen on the
-- target. "policy": a standing decision (immunity). Anything else is "none".
-- GetTargetAuraState and the diagnostics share this one table.
local EVIDENCE = {
    ["cooldown-manager"] = "confirmed", ["aura-instance"] = "confirmed",
    ["instance-removed"] = "confirmed", ["engine-refresh"] = "confirmed",
    ["cast-estimate"] = "estimated", ["cast-pending"] = "estimated",
    ["estimated-refresh"] = "estimated", ["estimated-expiry"] = "estimated",
    ["immune-policy"] = "policy", ["immune-known"] = "policy",
}

-- Session counts of target misses matched to a tracked cast (diagnostics only; nothing
-- reads them to decide). The match is by timing alone, so three counts mark matches that may
-- be someone else's attack: grouped, ownSwing (our own melee swing in the same window) and
-- dodgedMissile (a dodge matched to a missile, which a nearby melee swing explains as well).
-- Two more count misses in the window that were NOT given to the cast: notOutcome (a result the
-- cast cannot produce) and toSwing (nearer to our own auto attack). schools counts each
-- result by the event's school mask, to learn whether the mask separates casts from swings.
local missStats = { matched = 0, cancelled = 0, restored = 0, immune = 0,
                    grouped = 0, ownSwing = 0, dodgedMissile = 0, kinds = {},
                    notOutcome = 0, toSwing = 0, schools = {} }
-- Which avoidance each defense type allows (SpellCategories.DefenseType: 1 magic, 2 melee,
-- 3 ranged). A spell is never parried or dodged; a ranged attack is never parried.
local AVOIDANCE = { DODGE = true, PARRY = true }
local AVOIDABLE = {
    [1] = {},
    [2] = { DODGE = true, PARRY = true },
    [3] = { DODGE = true },
}
-- Results an auto attack can produce, per swing type (0 main hand, 1 off hand).
-- A white swing reports its result a little AFTER its PLAYER_SWING: 0.34 to 0.47s over 19
-- swings (builds 70938 and 70959). Results that share a swing's timestamp belong to a cast
-- landing on that swing (Heroic Strike, Raptor Strike), not to the swing.
-- Ranged shots are left out: their result arrives after the flight, 0.4 to 1.3s later.
local SWING_RESULTS = {
    [0] = { DODGE = true, PARRY = true, MISS = true },
    [1] = { DODGE = true, PARRY = true, MISS = true },
}
local SWING_RESULT_MIN, SWING_RESULT_MAX = 0.3, 0.52
-- A cast with no missile reports in the same timestamp as its cast event (5 of 5 at 0.000s):
-- a result this close to such a cast is the cast's, whatever a swing was doing.
local SAME_INSTANT = 0.02
local claimedSwing = {}   -- swing start time already given a result, per swing type

--- A spell's plain maximum range in yards, or nil when it cannot be read.
local function PlainMaxRange(spellID)
    if not (BlizzardAPI and BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.IsSecretValue) then return nil end
    local ok, info = pcall(BlizzardAPI.GetCachedSpellInfo, spellID)
    if not ok or type(info) ~= "table" then return nil end
    local maxRange = info.maxRange
    if BlizzardAPI.IsSecretValue(maxRange) or type(maxRange) ~= "number" or maxRange <= 0 then return nil end
    return maxRange
end

--- A record of this cast for result matching: its window and what can avoid it.
local function NewCast(spellID, ids, now)
    local cast = { ids = ids, time = now, before = HIT_WINDOW, after = HIT_WINDOW }
    local defense, speed
    if SpellDB.GetAuraDelivery then defense, speed = SpellDB.GetAuraDelivery(spellID) end
    if not defense then return cast end
    cast.defense = defense
    if not (speed and speed > 0) then
        cast.before, cast.after = INSTANT_WINDOW, INSTANT_WINDOW
        return cast
    end
    cast.missile = true
    local maxRange = PlainMaxRange(spellID)
    if maxRange then cast.before, cast.after = INSTANT_WINDOW, maxRange / speed + FLIGHT_SLACK end
    return cast
end

local function GetEntry(spellID)
    local e = applied[spellID]
    if not e then e = { instances = {}, hadInstance = false, expiry = 0 }; applied[spellID] = e end
    return e
end

--- Drop pending casts the bridge window has passed (no addedAura will match them now).
local function PrunePending(now)
    for i = #pendingCasts, 1, -1 do
        if now - pendingCasts[i].time > BRIDGE_WINDOW then tremove(pendingCasts, i) end
    end
end

--- Record a tracked aura application on the current target. Arms a bounded estimate
--- and queues the cast for the aura-instance bridge; entry policy decides suppression.
--- Called from UNIT_SPELLCAST_SUCCEEDED (player): in combat, and on Forever out of combat too (the pull).
function DotTracker.OnCastSucceeded(spellID)
    if not spellID or not IsTrackedAura(spellID, true) then return end
    if not UnitExists("target") then return end
    local now = GetTime()

    -- Refresh (pandemic) point: un-sink this long before the estimated expiry so
    -- the DoT reappears in time to reapply. nil when duration is unknown (rely on
    -- the removal bridge / AC instead of guessing).
    local getDuration = SpellDB.GetTargetAuraDuration or SpellDB.GetTargetDotDuration
    local dur = getDuration and getDuration(spellID)
    local lead = 0
    if FOREVER and BlizzardAPI and BlizzardAPI.GetPeriodicRefreshLead then
        lead = BlizzardAPI.GetPeriodicRefreshLead(spellID, SpellDB.IsStackingAura and SpellDB.IsStackingAura(spellID))
    end
    local pandemicPoint = dur and (now + math.max(0, dur * (1 - PANDEMIC_LEAD) - lead)) or nil

    -- Key under the cast ID, its display/override ID, and its base spell so the
    -- query (which uses the queue's ID for the same ability - possibly a different
    -- talent variant) matches regardless of which variant each side names.
    local ids = { spellID }
    local disp = BlizzardAPI and BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID)
    if disp and disp ~= spellID then ids[#ids + 1] = disp end
    local base = baseOf(spellID)
    if base then ids[#ids + 1] = base end
    -- A stacking aura I apply (Sunder Armor) counts my landed applications: one more while the
    -- last is still running, else a fresh first stack. The previous state is kept so a miss
    -- reported for this cast takes back only this stack.
    local maxStacks = SpellDB.GetStackingMax and SpellDB.GetStackingMax(spellID)
    for _, id in ipairs(ids) do
        local e = GetEntry(id)
        if maxStacks then
            local running = e.castAt and e.stacks and now < e.expiry and not e.immune
                and not (e.hadInstance and not next(e.instances))
            if running then
                e.prevStacks, e.prevExpiry, e.prevCastAt = e.stacks, e.expiry, e.castAt
                e.stacks = math.min(maxStacks, e.stacks + 1)
            else
                e.prevStacks, e.stacks = 0, 1
            end
        end
        e.expiry = now + (dur or FALLBACK_WINDOW)
        e.pandemicPoint, e.lead = pandemicPoint, lead
        e.castAt, e.cdmSeen = now, nil
        -- A fresh application after a confirmed drop must trust the window again:
        -- hadInstance means "confirmed since the last cast that found no instance",
        -- not "ever confirmed" (which sank the first application only).
        if not next(e.instances) then e.hadInstance = false end
    end

    pendingCasts[#pendingCasts + 1] = { ids = ids, time = now }
    PrunePending(now)
    lastCast = NewCast(spellID, ids, now)
    -- A result that arrived just ahead of this cast event: OnTargetCombat applies the window.
    if lastMissAt then DotTracker.OnTargetCombat(lastMissKind, lastMissAt) end
end

--- Can this cast produce this result? false only when its defense type rules it out.
local function CastCanProduce(cast, kind)
    if not AVOIDANCE[kind] then return true end
    local allowed = AVOIDABLE[cast.defense]
    if not allowed then return true end
    return allowed[kind] == true
end

--- Is one of our own auto attacks the owner of this result rather than the cast? True when
--- it arrives where a white swing's result is expected after that swing, unless it shares
--- the timestamp of a cast with no missile. That swing is then spent: a second result in
--- the window goes to the cast.
local function SwingTakes(kind, missAt, cast)
    if not (BlizzardAPI and BlizzardAPI.GetSwingWindow) then return false end
    if not cast.missile and math.abs(missAt - cast.time) <= SAME_INSTANT then return false end
    for swingType = 0, 1 do
        if SWING_RESULTS[swingType][kind] then
            local swingAt = BlizzardAPI.GetSwingWindow(swingType)
            if type(swingAt) == "number" and claimedSwing[swingType] ~= swingAt then
                local since = missAt - swingAt
                if since >= SWING_RESULT_MIN and since <= SWING_RESULT_MAX then
                    claimedSwing[swingType] = swingAt
                    return true
                end
            end
        end
    end
    return false
end

--- Count a matched miss and what makes its attribution doubtful. Plain reads only; a failed
--- or unreadable read leaves that count alone.
local function NoteMatchedMiss(cast, kind, now)
    local stats = missStats
    stats.matched = stats.matched + 1
    stats.kinds[kind] = (stats.kinds[kind] or 0) + 1
    local e = applied[cast.ids[1]]
    if kind == "IMMUNE" then
        stats.immune = stats.immune + 1
    elseif e and e.prevStacks and e.prevStacks > 0 then
        stats.restored = stats.restored + 1
    else
        stats.cancelled = stats.cancelled + 1
    end
    if not BlizzardAPI then return end
    if BlizzardAPI.IsGrouped and BlizzardAPI.IsGrouped() == true then stats.grouped = stats.grouped + 1 end
    local swingAt = BlizzardAPI.GetSwingWindow and BlizzardAPI.GetSwingWindow(0)
    if type(swingAt) == "number" and math.abs(now - swingAt) <= HIT_WINDOW then
        stats.ownSwing = stats.ownSwing + 1
    end
    if kind == "DODGE" and cast.missile then stats.dodgedMissile = stats.dodgedMissile + 1 end
end

--- The cast did not land: drop its timer, or for IMMUNE hold it sunk for this target.
local function Missed(ids, kind)
    if kind == "IMMUNE" then NoteNpcImmune(ids) end
    for _, id in ipairs(ids) do
        local e = applied[id]
        if kind == "IMMUNE" then
            GetEntry(id).immune = true
        elseif e and e.prevStacks and e.prevStacks > 0 then
            -- A missed stacking cast leaves the stacks already there, on their own timer.
            e.stacks, e.expiry, e.castAt = e.prevStacks, e.prevExpiry, e.prevCastAt
            if e.pandemicPoint then e.pandemicPoint = e.expiry - (e.lead or 0) end
            e.prevStacks = nil
        else
            applied[id] = nil
        end
    end
end

--- UNIT_COMBAT for the target: the result string, and the school mask for the counts only.
--- missAt is given when a result that arrived before its cast event is replayed.
--- The result goes to the cast unless the cast cannot produce it or one of our own auto
--- attacks is the nearer owner; either way the cast stays open for a later result.
function DotTracker.OnTargetCombat(kind, missAt, school)
    if (issecretvalue and issecretvalue(kind)) or not MISSED[kind] then return end
    local replayed = missAt ~= nil
    missAt = missAt or GetTime()
    if not replayed then
        lastMissAt, lastMissKind = missAt, kind
        if type(school) == "number" and not (issecretvalue and issecretvalue(school)) then
            local key = kind .. "/" .. school
            missStats.schools[key] = (missStats.schools[key] or 0) + 1
        end
    end
    if not lastCast then return end
    local sinceCast = missAt - lastCast.time
    if sinceCast < -lastCast.before or sinceCast > lastCast.after then return end
    -- A miss already took this cast. Only immunity may still follow in the window (measured:
    -- another attacker's miss 0.17s ahead of a sting's own immune result), and it wins.
    if lastCast.cancelled and kind ~= "IMMUNE" then return end
    lastMissAt = nil   -- judged against this cast: never replayed onto it again
    if not CastCanProduce(lastCast, kind) then
        missStats.notOutcome = missStats.notOutcome + 1
        return
    end
    if SwingTakes(kind, missAt, lastCast) then
        missStats.toSwing = missStats.toSwing + 1
        return
    end
    NoteMatchedMiss(lastCast, kind, missAt)
    Missed(lastCast.ids, kind)
    if kind == "IMMUNE" then
        lastCast = nil
    else
        lastCast.cancelled = true
    end
end

--- Map a confirmed player-debuff instance on the target to the cast that made it.
local function ConfirmInstance(ids, instanceID)
    instanceToDot[instanceID] = ids
    ForgetNpcImmune(ids[1])
    for _, id in ipairs(ids) do
        local e = GetEntry(id)
        e.instances[instanceID] = true
        e.hadInstance = true
    end
end

--- Process a target UNIT_AURA update: bridge added debuffs to our casts, and
--- drop removed ones. Called from JustAC:OnUnitAura for unit == "target".
--- Returns true if a tracked DoT instance was added or removed, so the caller
--- can refresh the queue promptly without churning on unrelated target auras.
function DotTracker.OnTargetAuraUpdate(unit, updateInfo)
    if not updateInfo then return false end
    -- Idle fast-path: with no confirmed instances and no pending cast, no target
    -- aura change can affect us. This keeps the newly-registered (high-frequency)
    -- target UNIT_AURA stream essentially free - removals have nothing to match and
    -- additions have nothing to bridge - which matters most for specs that never
    -- cast a tracked DoT (they still receive the events but do zero work).
    if not next(instanceToDot) and #pendingCasts == 0 then return false end
    local changed = false

    -- 12.1.0: these payload lists are secret in combat, so ipairs() on one throws.
    -- Unwrap first; secret means no incremental update this tick and the post-cast
    -- window fallback carries the DoT until a readable batch arrives.
    local removed = BlizzardAPI and BlizzardAPI.Unsecret(updateInfo.removedAuraInstanceIDs)
    if removed then
        for _, instanceID in ipairs(removed) do
            local ids = instanceToDot[instanceID]
            if ids then
                for _, id in ipairs(ids) do
                    local e = applied[id]
                    if e then e.instances[instanceID] = nil end
                end
                instanceToDot[instanceID] = nil
                changed = true
            end
        end
    end

    local added = BlizzardAPI and BlizzardAPI.Unsecret(updateInfo.addedAuras)
    if added and #pendingCasts > 0 then
        PrunePending(GetTime())
        -- Pair each confirmed added aura with one pending cast, oldest first
        -- (aura batch order follows cast order), consuming the pending entry so
        -- two DoTs confirming in the same UNIT_AURA batch don't both map to the
        -- most recent cast.
        for _, auraData in ipairs(added) do
            if #pendingCasts == 0 then break end
            -- Unwrapped like the sibling trackers: a secret id as a table key throws.
            local instanceID = BlizzardAPI and BlizzardAPI.Unsecret(auraData.auraInstanceID)
            if instanceID then
                -- Keep only harmful auras WE cast (engine-side, NeverSecret bool).
                -- If the API is unavailable, fall through and match by timing alone.
                local mine = true
                if IsAuraFilteredOutByInstanceID then
                    local ok, filtered = pcall(IsAuraFilteredOutByInstanceID, unit, instanceID, PLAYER_DEBUFF_FILTER)
                    mine = ok and (filtered == false)
                end
                if mine then
                    local pending = tremove(pendingCasts, 1)
                    ConfirmInstance(pending.ids, instanceID)
                    changed = true
                end
            end
        end
    end

    return changed
end

--- Is this entry's DoT under a threshold, according to the ENGINE? With `seconds`, the
--- aura's seconds left against them (Forever's refresh lead, a time-left gate); without,
--- the retail pandemic share. true / false / nil (no confirmed instance, or the technique
--- is unavailable).
local function EngineBelow(e, seconds)
    if not (e and next(e.instances) and BlizzardAPI and BlizzardAPI.GetAuraDurationObject) then
        return nil
    end
    local check, threshold
    if seconds then
        check, threshold = BlizzardAPI.IsDurationBelowSeconds, seconds
    else
        check, threshold = BlizzardAPI.IsDurationBelowPercent, PANDEMIC_LEAD * 100
    end
    if not check then return nil end
    -- The LONGEST-lived application decides, so a single "has time left" settles it.
    -- Returning the first instance that answered would let an old or nearly-spent
    -- application outvote a fresh one - `pairs` order is arbitrary, and an entry can
    -- hold more than one instance (a re-application can mint a new id, and 12.0.5
    -- re-randomises ids on encounter start, so a spent one can linger a moment).
    -- The result would be a reapply cue on a DoT that is actually full.
    local answered = false
    for instanceID in pairs(e.instances) do
        local durObj = BlizzardAPI.GetAuraDurationObject("target", instanceID)
        local below = durObj and check(durObj, threshold)
        if below ~= nil then
            answered = true
            if not below then return false end   -- one application still has time
        end
    end
    -- Answered by at least one, and every one of them was inside the window.
    return answered or nil
end
--- Is this entry's DoT inside its refresh window, according to the ENGINE? Shared by the
--- live query and the /jac inspect dots probe so the probe can never report on a code path
--- production does not take.
local function EnginePandemicVerdict(e)
    local lead = e and e.lead
    if lead and lead <= 0 then lead = nil end
    return EngineBelow(e, lead)
end

--- True when the current target already has this DoT live (so the queue should
--- sink it). Confirmed instance > early-drop > post-cast window fallback.
-- This target's record for a spell, under its own id or its base/rank-1 id. nil when none.
local function EntryFor(spellID)
    if not spellID or not next(applied) then return nil end
    local e = applied[spellID]
    if e then return e end
    local base = baseOf(spellID)
    if base then return applied[base] end
    return nil
end

local function EvaluateDot(spellID, diagnostic, observation, readCache)
    if not spellID then return false, "invalid-spell" end
    -- Idle fast-path: nothing tracked -> skip the base-spell resolve entirely.
    -- This query runs per rotation spell per build, so keeping it free when no DoT
    -- is active matters for non-DoT specs and between-target lulls.
    local e = EntryFor(spellID)
    if e and e.immune then return true, "immune-policy" end
    -- Learned for this kind of creature. The icon read below still runs first: seeing the DoT
    -- on the target overrules what was learned, and forgets it.
    local knownImmune = NpcImmune(spellID)
    local tracked, trackedReason
    -- WoW Forever: a DoT the player tracks in the Cooldown Manager is read off Blizzard's own
    -- icon for the current target - it sees a dodge, a dispel and an early fall-off that cast
    -- timing cannot. No refresh window there, so it is the whole answer. DoTs only: a tracked
    -- NON-DoT with a debuff of its own can still be worth recasting. Such a spell is
    -- observed only for an explicit entry condition, never unconditionally suppressed.
    if FOREVER and IsTrackedAura(spellID, observation) then
        if maintenanceTracker == nil then
            maintenanceTracker = LibStub("JustAC-MaintenanceTracker", true) or false
        end
        -- Not `x and x.f()`: with the module missing that is false, read as "not ticking".
        if maintenanceTracker then
            tracked = maintenanceTracker.IsTrackedAuraActive(spellID, diagnostic, readCache)
            trackedReason = diagnostic and diagnostic.reason
        else
            trackedReason = "module-unavailable"
        end
        if tracked == true and e then e.cdmSeen = true end
        if knownImmune then
            if tracked ~= true then return true, "immune-known", tracked, trackedReason end
            ForgetNpcImmune(spellID)
            knownImmune = false
        end
        -- The icon says only "ticking". With a refresh lead (a cast-time or stacking DoT) the
        -- recast starts before it ends: the engine's timer when we hold the instance, else
        -- our own from the cast.
        if tracked == true and e and e.lead and e.lead > 0 then
            local engineBelow = EnginePandemicVerdict(e)
            if engineBelow ~= nil then
                return not engineBelow, "engine-refresh", tracked, trackedReason, engineBelow
            end
            if e.pandemicPoint and GetTime() >= e.pandemicPoint then
                return false, "estimated-refresh", tracked, trackedReason
            end
        end
        -- The icon trails our cast (server round trip, projectile travel). Until it has
        -- shown once, "inactive" inside the bridge window means "not applied yet", so the
        -- just-cast DoT stays sunk through the GCD. A miss/immune result still wins.
        if tracked == false and e and e.castAt and not e.cdmSeen
           and GetTime() - e.castAt < BRIDGE_WINDOW then
            return true, "cast-pending", tracked, trackedReason
        end
        if tracked ~= nil then return tracked, "cooldown-manager", tracked, trackedReason end
    end
    if knownImmune then return true, "immune-known", tracked, trackedReason end
    if not e then return false, "untracked", tracked, trackedReason end
    local now = GetTime()
    -- ENGINE TRUTH for the pandemic window, wherever we hold a confirmed instance.
    -- This is not merely more precise than the estimate below - it fixes a class of
    -- error the estimate CANNOT express. Refreshing a DoT carries up to 30% of the
    -- remaining time into the new application, so a refreshed DoT really runs up to
    -- 1.3x its book duration, while `castTime + dur * 0.7` still assumes exactly the
    -- book value. Every refreshed DoT therefore reaches its reapply cue early, and
    -- the error compounds the longer a DoT is kept rolling. Asking the aura for its
    -- own remaining time removes all of it, and needs no duration data at all -
    -- talent and haste scaling come for free.
    -- A stale instance id (a DoT that expired between target updates) simply yields
    -- no answer here - GetAuraDurationObject requires a VALID instance - so the loop falls
    -- through to the estimate instead of trusting a dead binding.
    -- Inside the window -> report NOT active, which un-sinks the DoT so the player
    -- reapplies. Outside it -> live, keep it sunk.
    local engineBelow = EnginePandemicVerdict(e)
    if engineBelow ~= nil then return not engineBelow, "engine-refresh", tracked, trackedReason, engineBelow end
    -- Inside the pandemic refresh window: un-sink so the player can reapply, even
    -- though the debuff is still technically live. For known durations this also
    -- caps a stale confirmed instance (a DoT that expired between target updates).
    if e.pandemicPoint and now >= e.pandemicPoint then
        return false, "estimated-refresh", tracked, trackedReason
    end
    if next(e.instances) then
        -- Unknown-duration DoTs have no pandemic cap, so fall back to the post-cast
        -- window as a ceiling - a stale instance can't then suppress indefinitely.
        if not e.pandemicPoint and now >= e.expiry then
            return false, "estimated-expiry", tracked, trackedReason
        end
        return true, "aura-instance", tracked, trackedReason
    end
    if e.hadInstance then return false, "instance-removed", tracked, trackedReason end
    return now < e.expiry, "cast-estimate", tracked, trackedReason
end

--- Our own window for this DoT on the current target: cast time and book duration. Only a
--- known duration (no fallback window), only before its expiry, and nil once the aura was
--- confirmed removed or the target is immune. Our numbers, never an aura's.
function DotTracker.GetCastWindow(spellID)
    local e = EntryFor(spellID)
    if not (e and e.castAt and e.pandemicPoint) or e.immune then return nil end
    if e.hadInstance and not next(e.instances) then return nil end
    if GetTime() >= e.expiry then return nil end
    return e.castAt, e.expiry - e.castAt
end

--- Has my cast of this DoT landed on the current target at some point in this fight, running or
--- not? A miss takes its record back, and an immune target does not count.
function DotTracker.HasRunOnTarget(spellID)
    local e = EntryFor(spellID)
    return e ~= nil and e.castAt ~= nil and not e.immune
end

--- The engine's own timer for this DoT on the current target: a DurationObject from a
--- confirmed aura instance, passed through untouched (drawn by the engine, never read). nil when
--- no instance answers (none bound, a stale id, or access refused while auras are secret).
function DotTracker.GetDurationObject(spellID)
    local e = EntryFor(spellID)
    if not e or e.immune or not BlizzardAPI.GetAuraDurationObject then return nil end
    for instanceID in pairs(e.instances) do
        local durObj = BlizzardAPI.GetAuraDurationObject("target", instanceID)
        if durObj then return durObj end
    end
    return nil
end

function DotTracker.IsDotActiveOnCurrentTarget(spellID, readCache)
    if not IsTrackedAura(spellID) then return false end
    local active = EvaluateDot(spellID, nil, nil, readCache)
    return active
end

--- Presence prerequisites need evidence, not the absence of an observed cast.
--- Only refresh policy may use the existing bounded post-cast estimate.
function DotTracker.GetTargetAuraState(spellID, allowEstimate, readCache)
    if not FOREVER then return nil end
    local active, source = EvaluateDot(spellID, nil, true, readCache)
    local grade = EVIDENCE[source]
    if grade == "confirmed" then return active end
    if allowEstimate and (grade == "estimated" or grade == "policy") then return active end
    return nil
end

--- The suppression verdict for this DoT with the quality of the evidence behind it:
--- active, grade ("confirmed" / "estimated" / "policy" / "none"), source. Diagnostics: the
--- queue reads IsDotActiveOnCurrentTarget, which gives the same `active`.
function DotTracker.GetDotEvidence(spellID)
    if not IsTrackedAura(spellID) then return false, "none", "not-tracked" end
    local active, source = EvaluateDot(spellID)
    return active, EVIDENCE[source] or "none", source
end


--- Has my DoT on the current target fewer than `seconds` left? true / false / nil (unknown).
--- Forever only. The engine's own timer when an instance is held (the longest-lived one
--- decides); else my timer from the cast, while a known duration runs; a DoT known to be
--- off the target (Cooldown Manager inactive, its instance removed, its timer run out) has
--- none left. Never cast on this target, immune, or no timer: unknown. Ferocious Bite while
--- Rip has 3+ seconds, Ghostly Strike before Rupture runs out.
local GONE = { ["cooldown-manager"] = true, ["instance-removed"] = true }
function DotTracker.IsTimeLeftBelow(spellID, seconds, readCache)
    if not FOREVER or type(seconds) ~= "number" then return nil end
    local e = EntryFor(spellID)
    if not e or e.immune then return nil end
    if next(e.instances) then
        if seconds <= 0 then return false end
        local below = EngineBelow(e, seconds)
        if below ~= nil then return below end
    else
        local active, source = EvaluateDot(spellID, nil, true, readCache)
        if active == false and GONE[source] then return true end
    end
    -- My own timer: only for a known duration (the fallback window is a guess).
    if not (e.castAt and e.pandemicPoint) then return nil end
    local left = e.expiry - GetTime()
    return left <= 0 or left < seconds
end

--- My stacks of a stacking aura on the current target (Sunder Armor), counted from my landed
--- casts: a number, 0 once it is known gone, nil when unknown (never cast on this target,
--- immune, not a stacking aura, or a live instance whose stacks cannot be read). Forever only;
--- other players' stacks are not counted.
function DotTracker.GetOwnStacks(spellID)
    if not FOREVER then return nil end
    local e = EntryFor(spellID)
    if not e or e.immune or not e.stacks then return nil end
    if e.hadInstance and not next(e.instances) then return 0 end
    if e.castAt and GetTime() >= e.expiry and not next(e.instances) then return 0 end
    return e.stacks
end

--- Drop all tracking. Called on target change (state is current-target only) and
--- on leaving combat.
function DotTracker.Reset()
    applied, instanceToDot = {}, {}
    wipe(byTarget)
    wipe(pendingCasts)
    lastCast, lastMissAt, currentGUID = nil, nil, PlainTargetGUID()
    currentNPC = NpcIdOf(currentGUID)
end

--- What has been learned about creature immunity (/jac inspect immunedb): how many npc ids
--- are saved, the sightings needed to count, the current target's npc id and its entries
--- as { base, saved = sightings on disk, session = held this session }.
function DotTracker.GetImmunityInfo()
    local db, g = ImmuneDB()
    local entries = {}
    if currentNPC then
        local saved = db and db[currentNPC] or {}
        local session = sessionNpcImmune[currentNPC] or {}
        for base, sightings in pairs(saved) do
            entries[#entries + 1] = { base = base, saved = sightings, session = session[base] == true }
        end
        for base in pairs(session) do
            if not saved[base] then entries[#entries + 1] = { base = base, saved = 0, session = true } end
        end
        table.sort(entries, function(x, y) return x.base < y.base end)
    end
    return (g and g.dotImmuneNPCsN) or 0, NPC_IMMUNE_CONFIRM, currentNPC, entries
end

--- Throw away everything learned, on disk and for the session.
function DotTracker.ClearLearnedImmunity()
    local _, g = ImmuneDB()
    if g then g.dotImmuneNPCs, g.dotImmuneNPCsN = nil, nil end
    immuneOwner, immuneCache, immuneOrder, immuneSlots, immuneNext = nil, nil, nil, nil, nil
    wipe(sessionNpcImmune)
    wipe(countedSightings)
    wipe(sightingOrder)
    sightingNext = 1
end

--- The target changed: park the old target's record under its GUID, restore the new one's.
function DotTracker.OnTargetChanged()
    if currentGUID and next(applied) then
        byTarget[currentGUID] = { applied = applied, instanceToDot = instanceToDot }
    end
    wipe(pendingCasts)
    lastCast, lastMissAt = nil, nil
    currentGUID = PlainTargetGUID()
    currentNPC = NpcIdOf(currentGUID)
    local saved = currentGUID and byTarget[currentGUID]
    if saved then
        applied, instanceToDot = saved.applied, saved.instanceToDot
        byTarget[currentGUID] = nil
    else
        applied, instanceToDot = {}, {}
    end
end

--- A kill (PARTY_KILL carries the victim's GUID plain): that mob's DoTs are gone.
function DotTracker.OnKill(victimGUID)
    if victimGUID == nil or (issecretvalue and issecretvalue(victimGUID)) then return end
    byTarget[victimGUID] = nil
    if victimGUID == currentGUID then applied, instanceToDot = {}, {} end
end

do
    local f = CreateFrame("Frame")
    -- Forever only: retail's UNIT_COMBAT carries no source, so a party member's parried swing
    -- or our own missed white hit beside a DoT cast would wipe that DoT's timer.
    if FOREVER then
        f:RegisterUnitEvent("UNIT_COMBAT", "target")
        f:SetScript("OnEvent", function(_, _, _, kind, _, _, school)
            DotTracker.OnTargetCombat(kind, nil, school)
        end)
    end
    local k = CreateFrame("Frame")
    k:RegisterEvent("PARTY_KILL")
    k:SetScript("OnEvent", function(_, _, _, victimGUID) DotTracker.OnKill(victimGUID) end)
end

--- Diagnostic snapshot for the current target (/jac inspect dots). Non-secret.
function DotTracker.DebugState(spellIDs)
    local now = GetTime()
    local out = { hasTarget = UnitExists("target"), pending = #pendingCasts, entries = {},
                  misses = missStats }
    local seen = {}
    local function capture(spellID, e)
        if seen[spellID] then return end
        seen[spellID] = true
        local diagnostic = {}
        local active, source, tracked, reason, engineBelow = EvaluateDot(spellID, diagnostic, true)
        out.entries[#out.entries + 1] = {
            spellID = spellID,
            active = active,
            source = source,
            evidence = EVIDENCE[source] or "none",
            cooldownManager = tracked,
            cooldownManagerReason = reason or "not-consulted",
            confirmed = e ~= nil and next(e.instances) ~= nil,
            expiresIn = e and (e.expiry - now),
            pandemicIn = e and e.pandemicPoint and (e.pandemicPoint - now),
            refreshLead = e and e.lead,
            enginePandemic = engineBelow,
        }
    end
    for spellID, e in pairs(applied) do capture(spellID, e) end
    for i = 1, math.min(#(spellIDs or {}), 12) do
        local id = spellIDs[i]
        capture(id, applied[id] or applied[baseOf(id) or false])
    end
    return out
end
