-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Maintenance Tracker - follows the ONE mitigation buff a tank spec keeps rolling,
-- for the defensive maintenance slot.
--
-- Two things are wanted, and they have very different reachability in 12.0:
--   1. IS IT UP?  - a plain boolean we branch on to glow the button. Obtainable.
--   2. HOW LONG?  - secret. We never learn it. Instead we hand the aura's DurationObject
--      to a Cooldown widget and the ENGINE draws the exact swipe. Display, never a read.
--
-- Both need the aura's auraInstanceID, and getting it is the whole problem: in combat
-- aura.spellId is SECRET, so we cannot simply scan the buff list for our spell. Two paths,
-- tried in order:
--   a) direct lookup by spell id - works out of combat (spellId is plain there), and in
--      combat too IF this particular aura is not secreted. Cheap, so it is tried first.
--   b) the cast->instance bridge, the same trick DotTracker uses: our own cast id from
--      UNIT_SPELLCAST_SUCCEEDED is NeverSecret, auraInstanceID is NeverSecret, and
--      IsAuraFilteredOutByInstanceID(unit, id, "HELPFUL|PLAYER") is a readable bool. So
--      after we cast the maintenance spell, the next player buff instance that is OURS is
--      the one we just applied. Identity without ever reading spellId.
--
-- Removal is authoritative: UNIT_AURA's removedAuraInstanceIDs tells us the buff dropped,
-- so the "down" state is observed rather than guessed from a timer we cannot read.
--
-- Fail direction: when we cannot identify the instance we report UNKNOWN, not "down". A
-- false "down" would glow the button and tell a tank to re-press a buff they already have,
-- which is worse than showing nothing - so unknown renders the icon with no swipe and no
-- glow. That state is bounded, never indefinite: it lasts only while a cast is still waiting
-- on the bridge (BRIDGE_WINDOW), after which the pending flag is expired rather than leaked.
local MaintenanceTracker = LibStub:NewLibrary("JustAC-MaintenanceTracker", 7)
if not MaintenanceTracker then return end

local SpellDB = LibStub("JustAC-SpellDB", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

local C_UnitAuras = C_UnitAuras
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local pcall = pcall
local ipairs = ipairs

-- Max gap between our cast and the buff appearing in addedAuras (mirrors DotTracker).
local BRIDGE_WINDOW = 2.0

-- Fraction of the buff's duration during which we say "refresh it NOW". Matches DotTracker's
-- PANDEMIC_LEAD and WoW's own 30% carry-over convention. This exists because glowing only
-- once the buff is GONE fires after mitigation has already lapsed - useless for a buff whose
-- entire job is to be permanently up. Estimated from cast time + static duration, since the
-- real remaining time is secret; the swipe beside it stays engine-exact.
local REFRESH_LEAD = 0.30

-- When we last cast the maintenance button. Distinct from pendingCastAt, which clears as soon
-- as the bridge binds - this one persists for the whole buff so the refresh window can be
-- measured from it.
local lastCastAt = nil

-- Current tracked instance for the spec's maintenance aura.
local trackedInstance = nil
-- Time of the last maintenance cast still awaiting an addedAuras match.
local pendingCastAt = nil

--- Is this instance one of OUR helpful auras? Engine-evaluated from the NeverSecret
--- instance id, so it stays readable in combat - unlike aura.spellId.
local function IsOurs(instanceID)
    local fn = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
    if not (fn and instanceID) then return false end
    local ok, filteredOut = pcall(fn, "player", instanceID, "HELPFUL|PLAYER")
    -- filteredOut == false means it MATCHED the filter, i.e. it is a player-cast buff.
    return ok and filteredOut == false
end

--- type() is NOT a secrecy guard: a SECRET number reports type "number", so a
--- `type(v) == "number"` test passes and the comparison after it throws. Only
--- issecretvalue can tell them apart. This bit us once; do not reintroduce it.
local IsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue or function() return false end

--- Path (a): find the instance by spell id. Works OUT of combat, where spellId is plain, and
--- in combat too whenever this aura happens not to be secreted. In combat identity otherwise
--- comes from the cast->instance bridge.
local function FindInstanceBySpellID(auraID)
    -- O(1) and safe either way: returns nil for a secret aura rather than a secret value.
    local byID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if byID then
        local ok, data = pcall(byID, auraID)
        if ok and data then
            local inst = data.auraInstanceID
            -- Secrecy first, THEN type, THEN compare. Any other order throws.
            if not IsSecret(inst) and type(inst) == "number" then return inst end
        end
    end
    return nil
end

--- Drop a bridge request that is never going to be answered. pendingCastAt is cleared on a
--- successful bind, but a cast can produce no bindable aura at all - then GetState would
--- answer "unknown" forever instead of "down", and the glow never fires. Time it out.
local function ExpireStalePendingCast()
    if pendingCastAt and (GetTime() - pendingCastAt) > BRIDGE_WINDOW then
        pendingCastAt = nil
    end
end

--- Still live? An instance id we hold is only meaningful while the engine still knows it.
local function InstanceAlive(instanceID)
    if not instanceID then return false end
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if not fn then return IsOurs(instanceID) end
    local ok, d = pcall(fn, "player", instanceID)
    return ok and d ~= nil
end

--- Player cast something. If it is the spec's maintenance button, open a bridge window so
--- the next OUR-buff instance to appear gets bound to it.
function MaintenanceTracker.OnCastSucceeded(spellID)
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    if not entry or not entry.cast or spellID ~= entry.cast then return end
    lastCastAt = GetTime()
    pendingCastAt = lastCastAt
    -- Try the cheap path immediately: out of combat this binds without needing the bridge.
    local direct = FindInstanceBySpellID(entry.aura)
    if direct then
        trackedInstance = direct
        pendingCastAt = nil
    end
end

--- Player aura change. Binds a pending cast to its new instance, and clears the tracked
--- instance the moment the engine says it was removed.
--- @return boolean changed - true when the up/down state may have flipped (redraw)
function MaintenanceTracker.OnPlayerAuraUpdate(updateInfo)
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    if not entry then return false end
    local changed = false

    ExpireStalePendingCast()

    -- Removal first: authoritative "it dropped".
    if updateInfo and updateInfo.removedAuraInstanceIDs and trackedInstance then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if id == trackedInstance then
                trackedInstance = nil
                changed = true
                break
            end
        end
    end

    -- Bridge: bind a waiting cast to its instance. ADDED and UPDATED both, because re-casting
    -- a live buff refreshes the aura and the engine reports that as an update, not an addition.
    if updateInfo and pendingCastAt and (GetTime() - pendingCastAt) <= BRIDGE_WINDOW then
        -- auraInstanceID is documented NeverSecret, but guard anyway: these get compared
        -- against trackedInstance later, and the cost of being wrong is a throw.
        local function TryBind(id)
            if not IsSecret(id) and type(id) == "number" and IsOurs(id) then
                trackedInstance = id
                pendingCastAt = nil
                changed = true
                return true
            end
            return false
        end
        if updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                if aura and TryBind(aura.auraInstanceID) then break end
            end
        end
        if not trackedInstance and updateInfo.updatedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if TryBind(id) then break end
            end
        end
    end

    -- Out of combat spellId is plain, so re-sync cheaply - this also picks the buff up
    -- after a /reload or a spec change, where no cast of ours was ever observed.
    local aurasReadable = not (BlizzardAPI and BlizzardAPI.AreAurasSecret
                               and BlizzardAPI.AreAurasSecret())
    if not trackedInstance and aurasReadable then
        local direct = FindInstanceBySpellID(entry.aura)
        if direct then
            trackedInstance = direct
            changed = true
        end
    end

    return changed
end

--- Clear tracking (spec change, leaving combat, reload).
function MaintenanceTracker.Reset()
    trackedInstance = nil
    pendingCastAt = nil
    lastCastAt = nil
end

--- Current state of the spec's maintenance buff.
--- @return string state - "up" (live, plenty of time) | "refresh" (live but inside its
---         refresh window - press it) | "down" | "unknown" | "none" (spec has none)
--- @return table|nil entry - the MAINTENANCE_DEFENSIVE entry
--- @return number|nil auraInstanceID - live instance, for the duration display
function MaintenanceTracker.GetState()
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    if not entry then return "none", nil, nil end
    ExpireStalePendingCast()

    if trackedInstance and InstanceAlive(trackedInstance) then
        -- We have the instance, so nothing is waiting on the bridge any more. Clearing here
        -- covers the refresh case, where the recast never produced an addedAuras entry to
        -- bind against because the aura was updated rather than added.
        pendingCastAt = nil
        -- Buff is live - but "live" is not the same as "leave it alone". Once it is inside
        -- its refresh window the answer is press it again, so distinguish the two. Only when
        -- the entry carries a duration: Bone Shield deliberately has none, because its stacks
        -- are consumed by damage rather than expiring on a clock, so elapsed time would be a
        -- fabricated warning (see the note on the DEATHKNIGHT_1 entry).
        if entry.dur and lastCastAt then
            local elapsed = GetTime() - lastCastAt
            if elapsed >= entry.dur * (1 - REFRESH_LEAD) then
                return "refresh", entry, trackedInstance
            end
        end
        return "up", entry, trackedInstance
    end
    if trackedInstance then
        -- Held an id the engine no longer knows: it expired without a removal batch.
        trackedInstance = nil
    end

    -- One more direct attempt before declaring it down - out of combat this is exact, and
    -- in combat it succeeds whenever this aura happens not to be secreted.
    local direct = FindInstanceBySpellID(entry.aura)
    if direct then
        trackedInstance = direct
        return "up", entry, direct
    end

    -- Out of combat the direct lookup is reliable, so a miss really means it is down.
    -- In combat a miss is ambiguous until a cast binds the bridge, so say UNKNOWN and let
    -- the renderer show the icon without claiming anything.
    -- Readable auras mean the lookup above was authoritative, so a miss really is "down".
    if not (BlizzardAPI and BlizzardAPI.AreAurasSecret and BlizzardAPI.AreAurasSecret()) then
        return "down", entry, nil
    end
    return (pendingCastAt and "unknown" or "down"), entry, nil
end

--- Is the maintenance slot actually on screen right now? Shared by the renderer (which draws
--- it) and the defensive queue builder (which must then NOT also list the same ability, since
--- the slot sits inside the defensive cluster and would show the icon twice in one row).
--- @param profile table
--- @return boolean active, table|nil entry
function MaintenanceTracker.IsSlotActive(profile)
    if not profile or profile.showMaintenanceSlot == false then return false, nil end
    -- Combat only, matching the renderer - out of combat the ability belongs in the normal
    -- defensive queue like any other, so the exclusion must lift with the slot.
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return false, nil end
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    if not entry then return false, nil end
    return true, entry
end

--- The aura's stack count, RAW and possibly secret. Never read, compared or defaulted here -
--- the engine renders a number we are not allowed to know. Same division as the duration swipe.
--- @param instanceID number|nil - from GetState's 3rd return
--- @return any|nil applications - opaque; pass to C_StringUtil.RoundToNearestString, nothing else
function MaintenanceTracker.GetApplications(instanceID)
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if not (fn and instanceID) then return nil end
    local ok, d = pcall(fn, "player", instanceID)
    if not ok or not d then return nil end
    return d.applications
end

--- The aura's remaining time as a DurationObject for a Cooldown widget. NEVER read the
--- value - hand it straight to SetCooldownFromDurationObject and let the engine draw it.
--- @param instanceID number|nil - from GetState's 3rd return
--- @return any|nil durationObject
function MaintenanceTracker.GetDurationObject(instanceID)
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if not (fn and instanceID) then return nil end
    local ok, dur = pcall(fn, "player", instanceID)
    if not ok then return nil end
    return dur
end
