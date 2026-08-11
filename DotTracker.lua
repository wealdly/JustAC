-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: DoT Tracker - sinks maintained enemy DoTs to the back of the queue
-- while their debuff is already live on the current target.
--
-- 12.0 combat hides target-debuff identity (spellId/name/isFromPlayerOrPlayerPet
-- are all secret; GetPlayerAuraBySpellID returns nil for secret auras), so we
-- cannot read "is Rake on the target" directly. UnitGUID("target") is ALSO secret
-- for NPCs in combat, so it can't key a table either. Two NeverSecret signals let
-- us reconstruct DoT state without any of that:
--   1. Our own casts. UNIT_SPELLCAST_SUCCEEDED spellID is readable. Casting a
--      tracked DoT arms a suppression window - this alone guarantees the sink.
--   2. The aura-instance bridge (accuracy layer). auraInstanceID is NeverSecret;
--      IsAuraFilteredOutByInstanceID(unit, id, "HARMFUL|PLAYER") is a readable
--      bool that tells us an instance is a harmful aura WE cast. On the target's
--      addedAuras we map the new debuff instance to the cast that produced it;
--      on removedAuraInstanceIDs we drop it, so a DoT that falls off early (drop,
--      dispel, immune, miss) un-sinks immediately. Stack count and duration stay
--      secret in combat, so we never read them - the generated list excludes
--      recast-to-stack DoTs (passively-ramping ones like Agony are included),
--      and duration estimates come from static data.
--
-- Everything here is scoped to the CURRENT target: UNIT_AURA("target") and the
-- player's cast both implicitly refer to it, so no per-GUID bookkeeping is needed.
-- Tracking is cleared on target change and on leaving combat.
--
-- Safety net: AC's position-1 pick re-surfaces any DoT that actually needs
-- refreshing, so an over-long window or a missed bridge only ever delays an
-- un-sink; it never hides a DoT the player needs to recast.
local DotTracker = LibStub:NewLibrary("JustAC-DotTracker", 1)
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
local function baseOf(spellID)
    return SpellDB and SpellDB.GetBaseSpell and SpellDB.GetBaseSpell(spellID) or nil
end

-- Unconfirmed fallback: how long after casting a DoT we assume it's still up when
-- the aura-instance bridge hasn't confirmed it. A generous upper bound on DoT
-- durations; confirmed presence overrides it and AC re-surfaces real refreshes.
-- ponytail: one constant, not per-spell durations (unreadable in combat anyway);
-- add SpellDuration-derived per-spell windows if the flat bound ever feels stale.
local FALLBACK_WINDOW = 30
-- Max gap between our cast and the debuff showing up in addedAuras.
local BRIDGE_WINDOW = 2.0
-- Pandemic lead: stop suppressing this fraction of the estimated duration before
-- expiry, so the DoT reappears in time to refresh inside its pandemic window.
-- Matches WoW's 30% carry-over. Only applied when a duration estimate exists.
local PANDEMIC_LEAD = 0.30
-- Harmful auras cast by the player - Blizzard evaluates this engine-side from the
-- NeverSecret instance ID, so it stays readable in combat.
local PLAYER_DEBUFF_FILTER = "HARMFUL|PLAYER"

-- Current target only. applied[spellID] = { expiry, pandemicPoint, hadInstance,
-- instances = { [instanceID] = true } }.
local applied = {}
-- instanceToDot[instanceID] = ids (the spell-ID list to clear on removal).
local instanceToDot = {}
-- pendingCasts: array of { ids, time } awaiting an addedAura match.
local pendingCasts = {}

local function GetEntry(spellID)
    local e = applied[spellID]
    if not e then e = { instances = {}, hadInstance = false, expiry = 0 }; applied[spellID] = e end
    return e
end

--- Record a tracked-DoT cast on the current target. Arms the suppression window
--- (guaranteed sink) and queues the cast for the aura-instance bridge.
--- Called from UNIT_SPELLCAST_SUCCEEDED (player), in combat only.
function DotTracker.OnCastSucceeded(spellID)
    if not spellID or not SpellDB or not SpellDB.IsTargetDot or not SpellDB.IsTargetDot(spellID) then
        return
    end
    if not UnitExists("target") then return end
    local now = GetTime()

    -- Refresh (pandemic) point: un-sink this long before the estimated expiry so
    -- the DoT reappears in time to reapply. nil when duration is unknown (rely on
    -- the removal bridge / AC instead of guessing).
    local dur = SpellDB.GetTargetDotDuration and SpellDB.GetTargetDotDuration(spellID)
    local pandemicPoint = dur and (now + dur * (1 - PANDEMIC_LEAD)) or nil

    -- Key under the cast ID, its display/override ID, and its base spell so the
    -- query (which uses the queue's ID for the same ability - possibly a different
    -- talent variant) matches regardless of which variant each side names.
    local ids = { spellID }
    local disp = BlizzardAPI and BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID)
    if disp and disp ~= spellID then ids[#ids + 1] = disp end
    local base = baseOf(spellID)
    if base then ids[#ids + 1] = base end
    for _, id in ipairs(ids) do
        local e = GetEntry(id)
        e.expiry = now + FALLBACK_WINDOW
        e.pandemicPoint = pandemicPoint
    end

    pendingCasts[#pendingCasts + 1] = { ids = ids, time = now }
    for i = #pendingCasts, 1, -1 do
        if now - pendingCasts[i].time > BRIDGE_WINDOW then tremove(pendingCasts, i) end
    end
end

--- Map a confirmed player-debuff instance on the target to the cast that made it.
local function ConfirmInstance(ids, instanceID)
    instanceToDot[instanceID] = ids
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
        local now = GetTime()
        for i = #pendingCasts, 1, -1 do
            if now - pendingCasts[i].time > BRIDGE_WINDOW then tremove(pendingCasts, i) end
        end
        -- Pair each confirmed added aura with one pending cast, oldest first
        -- (aura batch order follows cast order), consuming the pending entry so
        -- two DoTs confirming in the same UNIT_AURA batch don't both map to the
        -- most recent cast.
        for _, auraData in ipairs(added) do
            if #pendingCasts == 0 then break end
            local instanceID = auraData.auraInstanceID
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

--- True when the current target already has this DoT live (so the queue should
--- sink it). Confirmed instance > early-drop > post-cast window fallback.
--- Is this entry's DoT inside its pandemic window, according to the ENGINE?
--- true / false / nil (no confirmed instance, or the technique is unavailable).
--- Shared by the live query and the /jac inspect dots probe so the probe can never
--- report on a code path production does not take.
local function EnginePandemicVerdict(e)
    if not (e and next(e.instances) and BlizzardAPI
            and BlizzardAPI.IsDurationBelowPercent and BlizzardAPI.GetAuraDurationObject) then
        return nil
    end
    -- The LONGEST-lived application decides, so a single "has time left" settles it.
    -- Returning the first instance that answered would let an old or nearly-spent
    -- application outvote a fresh one - `pairs` order is arbitrary, and an entry can
    -- hold more than one instance (a re-application can mint a new id, and 12.0.5
    -- re-randomises ids on encounter start, so a spent one can linger a moment).
    -- The result would be a reapply cue on a DoT that is actually full.
    local answered = false
    for instanceID in pairs(e.instances) do
        local durObj = BlizzardAPI.GetAuraDurationObject("target", instanceID)
        local below = durObj and BlizzardAPI.IsDurationBelowPercent(durObj, PANDEMIC_LEAD * 100)
        if below ~= nil then
            answered = true
            if not below then return false end   -- one application still has time
        end
    end
    -- Answered by at least one, and every one of them was inside the window.
    return answered or nil
end

function DotTracker.IsDotActiveOnCurrentTarget(spellID)
    -- Idle fast-path: nothing tracked -> skip the base-spell resolve entirely.
    -- This query runs per rotation spell per build, so keeping it free when no DoT
    -- is active matters for non-DoT specs and between-target lulls.
    if not spellID or not next(applied) then return false end
    local e = applied[spellID]
    if not e then
        local base = baseOf(spellID)
        e = base and applied[base]
    end
    if not e then return false end
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
    -- no answer here - GetAuraDuration requires a VALID instance - so the loop falls
    -- through to the estimate instead of trusting a dead binding.
    -- Inside the window -> report NOT active, which un-sinks the DoT so the player
    -- reapplies. Outside it -> live, keep it sunk.
    local engineBelow = EnginePandemicVerdict(e)
    if engineBelow ~= nil then return not engineBelow end
    -- Inside the pandemic refresh window: un-sink so the player can reapply, even
    -- though the debuff is still technically live. For known durations this also
    -- caps a stale confirmed instance (a DoT that expired between target updates).
    if e.pandemicPoint and now >= e.pandemicPoint then return false end
    if next(e.instances) then
        -- Unknown-duration DoTs have no pandemic cap, so fall back to the post-cast
        -- window as a ceiling - a stale instance can't then suppress indefinitely.
        if not e.pandemicPoint and now >= e.expiry then return false end
        return true                                -- confirmed live
    end
    if e.hadInstance then return false end         -- was confirmed, now dropped (expiry/cleanse)
    return now < e.expiry                          -- unconfirmed: trust the window
end

--- Drop all tracking. Called on target change (state is current-target only) and
--- on leaving combat.
function DotTracker.Reset()
    wipe(applied)
    wipe(instanceToDot)
    wipe(pendingCasts)
end

--- Diagnostic snapshot for the current target (/jac inspect dots). Non-secret.
function DotTracker.DebugState()
    local now = GetTime()
    local out = { hasTarget = UnitExists("target"), pending = #pendingCasts, entries = {} }
    for spellID, e in pairs(applied) do
        out.entries[#out.entries + 1] = {
            spellID = spellID,
            active = DotTracker.IsDotActiveOnCurrentTarget(spellID),
            confirmed = next(e.instances) ~= nil,
            expiresIn = e.expiry - now,
            pandemicIn = e.pandemicPoint and (e.pandemicPoint - now) or nil,
            -- Which source actually decided, and what the engine says. The estimate
            -- and the engine disagree exactly when the estimate is wrong (a
            -- pandemic-refreshed DoT), so showing only the verdict would hide the
            -- one case this is here to fix.
            enginePandemic = EnginePandemicVerdict(e),
        }
    end
    return out
end
