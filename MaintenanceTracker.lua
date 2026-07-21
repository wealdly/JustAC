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
--      UNIT_SPELLCAST_SUCCEEDED reads plain for the PLAYER (the event is
--      SecretWhenUnitSpellCastRestricted, which exempts us - it is NOT NeverSecret, and a
--      per-spell AlwaysSecret override can still apply, so keep the IsSecretValue guard and
--      do not generalise this to another unit), auraInstanceID is plain, and
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
-- Per-entry `lead` (SECONDS before decay) overrides the fraction where a spec wants a specific
-- window rather than a proportion - Ironfur's 7s means 30% is barely 2s of warning, too tight to
-- react to while tanking. Seconds are also what a player reasons in ("give me ~3s").
-- Both paths run off lastCastAt + a static duration, because the real remaining time is secret.
-- That estimate DRIFTS if a talent extends the buff (e.g. a +2s Ironfur talent): the cue then
-- fires early. The engine-exact swipe beside it is the ground truth if the two disagree.

-- When we last cast the maintenance button. Distinct from pendingCastAt, which clears as soon
-- as the bridge binds - this one persists for the whole buff so the refresh window can be
-- measured from it.
local lastCastAt = nil

-- Bridge diagnostics for /jac inspect maintenance. Counters only - no gameplay effect. These
-- exist to answer "is the ambiguity guard starving the bind?" with data instead of a guess.
local diag = { batches = 0, ambiguous = 0, bound = 0, lastCandidates = 0, maxCandidates = 0 }
function MaintenanceTracker.GetBridgeDiag() return diag end

-- Current tracked instance for the spec's maintenance aura.
local trackedInstance = nil
-- Did we OBSERVE the buff drop, as opposed to merely failing to find it? Only an observed drop
-- justifies claiming "down" and glowing the button. Without this, "never bound" and "confirmed
-- dropped" were indistinguishable and both glowed - measured in game telling a tank to re-press
-- an Ironfur that was already up. Set only by evidence: a removal batch naming our instance, or
-- an instance the engine has stopped knowing. Cleared the moment we hold a live instance again.
local observedDrop = false
-- How we got the current instance. TRUE only when it came from a by-spell-id lookup, which is
-- proof of identity; FALSE when the cast->instance bridge guessed it, which is not - the bridge
-- can only tell "a player-cast helpful buff" from "some other player-cast helpful buff".
-- This gates the STACK COUNT: a wrong number is actionable misinformation for a tank, so the
-- count renders only on a proven bind. Measured in game, an exact bind made out of combat
-- SURVIVES into the fight - instance 416 held across recasts - so this is not merely academic.
local bindExact = false
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

--- EVERY cooldownID mapping to our spell, as a set. Resolved once per spec; Reset() clears it.
--- A set, not a single id, because the SAME spell carries a DIFFERENT cooldownID in each
--- category it belongs to. Taking the first match (categories scan 0..3) found the Utility id
--- and never looked at TrackedBar - where these maintenance buffs sit BY DEFAULT. That made the
--- join look like it required manual setup when it did not: we were hunting the wrong number.
local cachedCooldownIDs = nil

-- The buff's REAL duration, learned by observation rather than hardcoded. `entry.dur` is a
-- static book value, but talents extend these buffs (a +2s Ironfur talent exists), and the
-- refresh cue runs off lastCastAt + duration - so a stale number fires the glow seconds early
-- and there is no way to notice, because the true remaining time is secret in combat.
-- Out of combat the aura's .duration IS readable, so learn it once from a live instance and
-- keep using it. Cleared on spec change, which is also when a talent build can change.
local learnedDuration = nil

--- Read the real duration off a known-good instance. Only meaningful where the field is plain;
--- returns nil in combat rather than a secret, and never compares the value.
local function LearnDuration(instanceID)
    if not instanceID then return end
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if not fn then return end
    local ok, d = pcall(fn, "player", instanceID)
    if not ok or not d then return end
    local dur = d.duration
    -- Secrecy first, then type, then use. A secret here must not reach the arithmetic in
    -- GetState's refresh window, and 0 means "no duration" rather than "expired".
    if not IsSecret(dur) and type(dur) == "number" and dur > 0 then
        learnedDuration = dur
    end
end

--- Effective duration for the refresh clock: learned if we have ever seen it, else the static
--- book value. @return number|nil
local function EffectiveDuration(entry)
    return learnedDuration or (entry and entry.dur) or nil
end

local function ResolveCooldownIDs(entry)
    if cachedCooldownIDs ~= nil then return cachedCooldownIDs end
    cachedCooldownIDs = {}
    local CV = C_CooldownViewer
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo) then
        return cachedCooldownIDs
    end
    local function Matches(info)
        if type(info) ~= "table" then return false end
        local function hit(v)
            return type(v) == "number" and (v == entry.cast or v == entry.aura)
        end
        if hit(info.spellID) or hit(info.overrideSpellID)
           or hit(info.overrideTooltipSpellID) or hit(info.linkedSpellID) then return true end
        local ls = info.linkedSpellIDs
        if type(ls) == "table" then
            for i = 1, #ls do if hit(ls[i]) then return true end end
        end
        return false
    end
    -- Scan ALL four categories and keep every hit. No early return.
    for cat = 0, 3 do   -- Essential, Utility, TrackedBuff, TrackedBar
        local okC, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
        if okC and type(ids) == "table" then
            for j = 1, #ids do
                local okN, info = pcall(CV.GetCooldownViewerCooldownInfo, ids[j])
                if okN and Matches(info) and type(ids[j]) == "number" then
                    cachedCooldownIDs[ids[j]] = true
                end
            end
        end
    end
    return cachedCooldownIDs
end

--- Path (a0), the only source of EXACT identity in combat: Blizzard's Cooldown Manager.
--- Its viewer runs UNTAINTED, so it may legally read the secret aura.spellId, match it against
--- a tracked cooldown, and cache the answer as a plain frame field. We read that materialized
--- number - never the secret. Confirmed in game: bridge bound 744/749 while this returned the
--- true 745/750, i.e. the bridge was off by one and this was right.
--- Conditional on player config: CVar on, viewer laid out, spell added to that bar. Returns nil
--- otherwise and the cast bridge stays as the fallback.
local VIEWER_NAMES = { "UtilityCooldownViewer", "EssentialCooldownViewer",
                       "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

local function FindInstanceViaCooldownManager(entry)
    local wantIDs = ResolveCooldownIDs(entry)
    if not (wantIDs and next(wantIDs)) then return nil end
    for v = 1, #VIEWER_NAMES do
        local viewer = _G[VIEWER_NAMES[v]]
        -- A HIDDEN viewer never computes auraInstanceID (OnHide drops its UNIT_AURA
        -- registration) and serves a stale id forever. Measured: hidden => cooldownID nil on
        -- every pooled frame. Alpha 0 is fine - only Hide() empties the pool.
        local shown = viewer and viewer.IsShown and viewer:IsShown()
        local pool = shown and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            -- Re-resolve every call: frames are pooled by layoutIndex and RefreshLayout
            -- releases the whole pool, so a cached frame reference goes stale silently.
            for item in pool:EnumerateActive() do
                local okC, cid = pcall(item.GetCooldownID, item)
                if okC and type(cid) == "number" and wantIDs[cid] then
                    -- NEVER item:GetSpellID() - that returns the SECRET auraSpellID.
                    local okA, inst = pcall(item.GetAuraSpellInstanceID, item)
                    local okU, unit = pcall(item.GetAuraDataUnit, item)
                    if okA and type(inst) == "number" and not IsSecret(inst)
                       and okU and unit == "player" then
                        return inst
                    end
                    -- Our frame, but no live aura on it. Keep scanning rather than bailing:
                    -- the spell can sit on more than one bar, and only one of those frames
                    -- carries the live instance.
                end
            end
        end
    end
    return nil
end

--- Every EXACT path, in order of reliability. Both prove identity, so either may set
--- bindExact: the Cooldown Manager because untainted code did the spellId match for us, the
--- direct lookup because the aura was readable enough to match by id ourselves. The cast
--- bridge is deliberately NOT here - it guesses, and is only reached when both of these fail.
local function FindInstanceExact(entry)
    local inst = FindInstanceViaCooldownManager(entry) or FindInstanceBySpellID(entry.aura)
    -- Opportunistic: whenever we hold a PROVEN instance and the field happens to be readable
    -- (out of combat), learn the real duration. Costs one table read on an already-fetched
    -- aura, and only ever runs on an instance we know is ours - learning off a bridge guess
    -- would cache some other buff's length and silently skew every refresh cue afterwards.
    if inst then LearnDuration(inst) end
    return inst
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
    -- A successful cast is evidence the buff is (re)applied, even when we cannot identify its
    -- instance. Without this, observedDrop latched true after the first genuine lapse and could
    -- never clear - clearing needs a live bind, and on the degraded path (no Cooldown Manager,
    -- bridge starved by ambiguity) there is none. The slot then claimed "down" for the rest of
    -- the fight and glowed at a tank whose buff was actually up. Cast evidence beats a stale flag.
    observedDrop = false
    -- Try the exact paths immediately. In combat the Cooldown Manager can answer this outright,
    -- which skips the bridge entirely - and the bridge is measurably wrong (it bound 744/749
    -- while the true instances were 745/750).
    local exact = FindInstanceExact(entry)
    if exact then
        trackedInstance = exact
        bindExact = true          -- identity proven
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
                observedDrop = true   -- authoritative: the engine says it went away
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
        local function IsCandidate(id)
            return not IsSecret(id) and type(id) == "number" and IsOurs(id)
        end
        -- IsOurs answers "a player-cast helpful buff", NOT "the maintenance buff" - spellId is
        -- secret in combat, so nothing here can tell two of our own buffs apart. Taking the
        -- first match meant a trinket/talent proc landing in the same batch could win the bind,
        -- and the slot then rendered THAT aura's applications as your stack count.
        -- So: bind only when the batch offers exactly ONE candidate. Two or more is genuinely
        -- ambiguous, and this module's fail direction is to stay UNKNOWN (icon, no swipe, no
        -- glow) rather than state a confident wrong number. pendingCastAt is deliberately left
        -- set so a later, cleaner batch can still bind before ExpireStalePendingCast drops it.
        local only, count = nil, 0
        local function Collect(id)
            if IsCandidate(id) then
                count = count + 1
                if only == nil then only = id end
            end
        end
        if updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                if aura then Collect(aura.auraInstanceID) end
            end
        end
        -- Only fall through to updates when ADDED offered nothing; an ambiguous ADDED batch
        -- must not be rescued by a different aura merely refreshing in the same tick.
        if count == 0 and updateInfo.updatedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                Collect(id)
            end
        end
        diag.batches = diag.batches + 1
        diag.lastCandidates = count
        if count > diag.maxCandidates then diag.maxCandidates = count end
        if count == 1 then
            trackedInstance = only
            bindExact = false     -- bridge guess: unambiguous in this batch, still not proof
            pendingCastAt = nil
            changed = true
            diag.bound = diag.bound + 1
        elseif count > 1 then
            diag.ambiguous = diag.ambiguous + 1
        end
    end

    -- Re-sync from an exact source. Also picks the buff up after a /reload or spec change,
    -- where no cast of ours was ever observed. No aurasReadable guard: the Cooldown Manager
    -- path works while auras are secret, and the by-spell-id path already returns nil safely
    -- when they are - gating both on a GLOBAL readability flag suppressed the one source that
    -- still works in combat.
    if not trackedInstance then
        local exact = FindInstanceExact(entry)
        if exact then
            trackedInstance = exact
            bindExact = true
            changed = true
        end
    end

    return changed
end

--- Clear tracking. Called on SPEC CHANGE only (JustAC.lua) - deliberately NOT on combat exit:
--- Bone Shield (30s) and a fast Ironfur re-pull (<7s) both legitimately outlive a combat
--- boundary, so wiping there would drop a buff that is still up.
function MaintenanceTracker.Reset()
    trackedInstance = nil
    pendingCastAt = nil
    lastCastAt = nil
    observedDrop = false
    bindExact = false
    cachedCooldownIDs = nil  -- spec change: a different spec has different cooldownIDs
    learnedDuration = nil    -- ...and a different buff, whose length must be re-learned
end

--- Local-clock fallback for the swipe: our own cast time plus the entry's static duration.
--- Plain numbers, no secret involved. Used ONLY when the bind is unproven - drawing the bound
--- aura's real DurationObject there can render a completely foreign timer (a 20s trinket proc
--- on a 7s buff), which reads as "wildly wrong" rather than "slightly off". An estimate that
--- drifts by a talent's worth of seconds is far better than a confidently wrong other clock.
--- @return number|nil startTime, number|nil duration
function MaintenanceTracker.GetEstimatedCooldown()
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    local effDur = EffectiveDuration(entry)
    if not (effDur and lastCastAt) then return nil, nil end
    return lastCastAt, effDur
end

--- Was the current instance resolved by spell id (proof), or guessed by the bridge?
--- Gates the stack count: the engine renders the true number, but only off the right instance.
--- @return boolean
function MaintenanceTracker.IsBindExact()
    return trackedInstance ~= nil and bindExact
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
        -- Single funnel for the drop flag: every bind path (cast, bridge, direct reseed) ends
        -- up here holding a live instance, so clearing it once here beats four call sites.
        observedDrop = false
        -- Buff is live - but "live" is not the same as "leave it alone". Once it is inside
        -- its refresh window the answer is press it again, so distinguish the two. Only when
        -- the entry carries a duration: Bone Shield deliberately has none, because its stacks
        -- are consumed by damage rather than expiring on a clock, so elapsed time would be a
        -- fabricated warning (see the note on the DEATHKNIGHT_1 entry).
        local effDur = EffectiveDuration(entry)
        if effDur and lastCastAt then
            local elapsed = GetTime() - lastCastAt
            -- lead in SECONDS if the entry specifies one, else the proportional fallback.
            local fireAt = entry.lead and (effDur - entry.lead)
                           or (effDur * (1 - REFRESH_LEAD))
            if fireAt < 0 then fireAt = 0 end
            if elapsed >= fireAt then
                return "refresh", entry, trackedInstance
            end
        end
        return "up", entry, trackedInstance
    end
    if trackedInstance then
        -- Held an id the engine no longer knows: it expired without a removal batch. Still
        -- evidence of a drop - we watched a live instance stop existing.
        trackedInstance = nil
        observedDrop = true
    end

    -- One more exact attempt before declaring it down. The Cooldown Manager answers this even
    -- mid-combat when the player has the spell on a shown viewer; the by-spell-id path covers
    -- out of combat and any aura that is not secreted.
    local direct = FindInstanceExact(entry)
    if direct then
        trackedInstance = direct
        bindExact = true
        observedDrop = false
        return "up", entry, direct
    end

    -- Was the lookup above AUTHORITATIVE? That is a per-SPELL question, not a global one.
    -- This used to ask the global ShouldAurasBeSecret, which can answer "auras are readable"
    -- while THIS aura is still unreadable - secrecy is per spell (Ironfur measures
    -- ContextuallySecret, /jac inspect maintenance Q1). On that path a miss became a confident
    -- "down", glowing the button to tell a tank to re-press a buff they already have: the exact
    -- false-down this module says is worse than showing nothing. Ask about our spell.
    local auraUnreadable = true
    local CS = C_Secrets
    if CS and CS.ShouldSpellAuraBeSecret then
        local okS, isSecret = pcall(CS.ShouldSpellAuraBeSecret, entry.aura)
        if okS then auraUnreadable = isSecret and true or false end
    elseif BlizzardAPI and BlizzardAPI.AreAurasSecret then
        auraUnreadable = BlizzardAPI.AreAurasSecret() and true or false
    end
    if not auraUnreadable then
        -- This spell's aura reads plain right now, so the miss really does mean it is down.
        observedDrop = true
        return "down", entry, nil
    end

    -- The aura is unreadable and we hold no instance, so the lookup proves nothing. Claim
    -- "down" ONLY on evidence we actually saw it go away; otherwise this is ignorance, and
    -- ignorance must render as UNKNOWN (icon, no swipe, no glow) rather than a confident cue
    -- to re-press. Measured in game: an unbound tracker reported "down" for minutes while
    -- Ironfur was up, because "never bound" and "confirmed dropped" shared this return.
    if observedDrop then
        return "down", entry, nil
    end
    return "unknown", entry, nil
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
