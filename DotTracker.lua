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
--   2. The aura-instance bridge (accuracy layer). auraInstanceID reads plain when
--      the UNIT_AURA payload does (12.1.0 can secret the whole list - unwrap first);
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
-- player's cast both implicitly refer to it. Where the target's GUID reads plain in
-- combat (WoW Forever) a target's record is parked on a swap and restored on a swap back;
-- otherwise a swap starts fresh. Tracking is cleared on leaving combat.
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
local RotationImport = LibStub("JustAC-RotationImport", true)
local maintenanceTracker   -- resolved on first use: Cooldown Manager aura state (loads later)
local function baseOf(spellID)
    local base = SpellDB and SpellDB.GetBaseSpell and SpellDB.GetBaseSpell(spellID)
    if base then return base end
    -- Forever ranks: a cast at one rank and a query at another meet at rank 1.
    local r1 = RotationImport and RotationImport.RankBase(spellID)
    return r1 ~= spellID and r1 or nil
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
-- WoW Forever has no carry-over (a recast restarts the DoT and loses the ticks left), so
-- there the DoT comes back when it runs out.
local FOREVER = (SpellDB and SpellDB.IsForever and SpellDB.IsForever()) and true or false
local PANDEMIC_LEAD = FOREVER and 0 or 0.30
-- Harmful auras cast by the player - Blizzard evaluates this engine-side from the
-- NeverSecret instance ID, so it stays readable in combat.
local PLAYER_DEBUFF_FILTER = "HARMFUL|PLAYER"

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

-- Did it land? UNIT_COMBAT on the target reports a dodge / parry / miss / immune as a plain
-- string in combat (measured on Forever). One that arrives within HIT_WINDOW of a DoT cast,
-- in either order, is taken to be that cast's result.
-- ponytail: an auto attack dodged in the same instant also cancels the timer; the DoT then
-- shows once more, the cheap direction.
local MISSED = { DODGE = true, PARRY = true, MISS = true, RESIST = true, EVADE = true,
                 DEFLECT = true, REFLECT = true, IMMUNE = true }
local HIT_WINDOW = 0.4
local lastCast        -- { ids, time } of the latest tracked DoT cast
local lastMissAt, lastMissKind

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

--- Record a tracked-DoT cast on the current target. Arms the suppression window
--- (guaranteed sink) and queues the cast for the aura-instance bridge.
--- Called from UNIT_SPELLCAST_SUCCEEDED (player): in combat, and on Forever out of combat too (the pull).
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
        -- A fresh application after a confirmed drop must trust the window again:
        -- hadInstance means "confirmed since the last cast that found no instance",
        -- not "ever confirmed" (which sank the first application only).
        if not next(e.instances) then e.hadInstance = false end
    end

    pendingCasts[#pendingCasts + 1] = { ids = ids, time = now }
    PrunePending(now)
    lastCast = { ids = ids, time = now }
    if lastMissAt and now - lastMissAt <= HIT_WINDOW then DotTracker.OnTargetCombat(lastMissKind) end
end

--- The cast did not land: drop its timer, or for IMMUNE hold it sunk for this target.
local function Missed(ids, kind)
    for _, id in ipairs(ids) do
        if kind == "IMMUNE" then GetEntry(id).immune = true else applied[id] = nil end
    end
end

--- UNIT_COMBAT for the target (the result string only).
function DotTracker.OnTargetCombat(kind)
    if (issecretvalue and issecretvalue(kind)) or not MISSED[kind] then return end
    local now = GetTime()
    lastMissAt, lastMissKind = now, kind
    if lastCast and now - lastCast.time <= HIT_WINDOW then
        Missed(lastCast.ids, kind)
        lastCast, lastMissAt = nil, nil
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

--- True when the current target already has this DoT live (so the queue should
--- sink it). Confirmed instance > early-drop > post-cast window fallback.
function DotTracker.IsDotActiveOnCurrentTarget(spellID)
    if not spellID then return false end
    -- Idle fast-path: nothing tracked -> skip the base-spell resolve entirely.
    -- This query runs per rotation spell per build, so keeping it free when no DoT
    -- is active matters for non-DoT specs and between-target lulls.
    local e = next(applied) and (applied[spellID] or applied[baseOf(spellID) or false]) or nil
    if e and e.immune then return true end         -- this target cannot take it
    -- WoW Forever: a DoT the player tracks in the Cooldown Manager is read off Blizzard's own
    -- icon for the current target - it sees a dodge, a dispel and an early fall-off that cast
    -- timing cannot. No refresh window there, so it is the whole answer. DoTs only: a tracked
    -- NON-DoT with a debuff of its own (Thunder Clap's slow) is worth recasting while that
    -- debuff is up, and reading it as "already ticking" sank it.
    if PANDEMIC_LEAD == 0 and SpellDB and SpellDB.IsTargetDot and SpellDB.IsTargetDot(spellID) then
        if maintenanceTracker == nil then
            maintenanceTracker = LibStub("JustAC-MaintenanceTracker", true) or false
        end
        -- Not `x and x.f()`: with the module missing that is false, read as "not ticking".
        local tracked
        if maintenanceTracker then tracked = maintenanceTracker.IsTrackedAuraActive(spellID) end
        if tracked ~= nil then return tracked end
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
    -- no answer here - GetAuraDurationObject requires a VALID instance - so the loop falls
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
    applied, instanceToDot = {}, {}
    wipe(byTarget)
    wipe(pendingCasts)
    lastCast, lastMissAt, currentGUID = nil, nil, PlainTargetGUID()
end

--- The target changed: park the old target's record under its GUID, restore the new one's.
function DotTracker.OnTargetChanged()
    if currentGUID and next(applied) then
        byTarget[currentGUID] = { applied = applied, instanceToDot = instanceToDot }
    end
    wipe(pendingCasts)
    lastCast, lastMissAt = nil, nil
    currentGUID = PlainTargetGUID()
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
        f:SetScript("OnEvent", function(_, _, _, kind) DotTracker.OnTargetCombat(kind) end)
    end
    local k = CreateFrame("Frame")
    k:RegisterEvent("PARTY_KILL")
    k:SetScript("OnEvent", function(_, _, _, victimGUID) DotTracker.OnKill(victimGUID) end)
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
