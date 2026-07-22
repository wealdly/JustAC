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

-- PER-ENTRY state, keyed by aura id. A spec can maintain more than one buff (Prot rolls both
-- Shield Block and Ignore Pain), and each needs its own instance binding, cast clock and drop
-- evidence - a single set of module-level variables silently blended them together.
local states = {}

-- Per-frame memo for GetState. It is called several times a frame - IsSlotActive uses it, the
-- renderer uses it, and the defensive queue builder uses it through IsSlotActive - and each
-- call runs the full pick: EntryState per entry (Cooldown Manager frame walks included) plus
-- readiness and usability queries. GetTime() is constant within a frame, so keying on it
-- collapses those to one. It also removes a correctness wrinkle: the repeat calls each carried
-- the binding side effects, and two picks in one frame could disagree if state moved between.
-- Declared HERE, above Reset, which invalidates it - declaring it lower made that a global read.
local pickCache = { t = nil }

--- State bag for one entry, created on demand.
local function S(entry)
    local key = entry and entry.aura
    if not key then return nil end
    local s = states[key]
    if not s then
        s = { trackedInstance = nil, pendingCastAt = nil, lastCastAt = nil,
              observedDrop = false, bindExact = false, learnedDuration = nil,
              cooldownIDs = nil }
        states[key] = s
    end
    return s
end

-- What each per-entry state field means (all live in `states[auraID]`):
--   trackedInstance - the aura instance we believe is this buff's.
--   pendingCastAt   - a cast still waiting for the bridge to match it; clears on bind.
--   lastCastAt      - persists for the whole buff, so the refresh window measures from it.
--   observedDrop    - did we OBSERVE it drop, versus merely fail to find it? Only observed
--                     evidence justifies "down" and a glow. Without this, "never bound" and
--                     "confirmed dropped" were indistinguishable and both glowed - measured in
--                     game telling a tank to re-press an Ironfur that was already up.
--   bindExact       - TRUE only from a by-spell-id lookup (proof of identity); FALSE when the
--                     bridge guessed, which is not proof. Gates the STACK COUNT, because a
--                     wrong number is actionable misinformation for a tank.
--   learnedDuration - the real duration read off a live instance, since talents extend these.
--   cooldownIDs     - every Cooldown Manager id mapping to this spell.

-- Bridge diagnostics for /jac inspect maintenance. Counters only - no gameplay effect. These
-- exist to answer "is the ambiguity guard starving the bind?" with data instead of a guess.
-- Shared across entries deliberately: it measures the BRIDGE, not any one buff.
local diag = { batches = 0, ambiguous = 0, bound = 0, lastCandidates = 0, maxCandidates = 0 }
function MaintenanceTracker.GetBridgeDiag() return diag end

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

-- The buff's REAL duration, learned by observation rather than hardcoded. `entry.dur` is a
-- static book value, but talents extend these buffs (a +2s Ironfur talent exists), and the
-- refresh cue runs off lastCastAt + duration - so a stale number fires the glow seconds early
-- and there is no way to notice, because the true remaining time is secret in combat.
-- Out of combat the aura's .duration IS readable, so learn it once from a live instance and
-- keep using it. Cleared on spec change, which is also when a talent build can change.

--- Read the real duration off a known-good instance. Only meaningful where the field is plain;
--- returns nil in combat rather than a secret, and never compares the value.
local function LearnDuration(entry, instanceID)
    local s = S(entry)
    if not (s and instanceID) then return end
    local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    if not fn then return end
    local ok, d = pcall(fn, "player", instanceID)
    if not ok or not d then return end
    local dur = d.duration
    -- Secrecy first, then type, then use. A secret here must not reach the arithmetic in
    -- GetState's refresh window, and 0 means "no duration" rather than "expired".
    if not IsSecret(dur) and type(dur) == "number" and dur > 0 then
        s.learnedDuration = dur
    end
end

--- Effective duration for the refresh clock: learned if we have ever seen it, else the static
--- book value. @return number|nil
local function EffectiveDuration(entry)
    -- No `dur` means "this buff is NEVER time-based", not "we lack a number" - Bone Shield omits
    -- it because stacks are eaten by damage, so any clock fabricates the warning. Learning the
    -- real duration must NOT resurrect that: the aura genuinely reports 30s, which would fire a
    -- refresh cue 21s after Marrowrend, precisely what the curation forbids. Learned values only
    -- ever CORRECT a book value that exists (talent-extended Ironfur), never supply a missing one.
    if not (entry and entry.dur) then return nil end
    local s = S(entry)
    return (s and s.learnedDuration) or entry.dur
end

local function ResolveCooldownIDs(entry)
    local s = S(entry)
    if not s then return nil end
    if s.cooldownIDs ~= nil then return s.cooldownIDs end
    s.cooldownIDs = {}
    local CV = C_CooldownViewer
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo) then
        return s.cooldownIDs
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
                    s.cooldownIDs[ids[j]] = true
                end
            end
        end
    end
    return s.cooldownIDs
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
    if inst then LearnDuration(entry, inst) end
    return inst
end

--------------------------------------------------------------------------------
-- Cosmetic hiding of Blizzard's Cooldown Manager viewers
--------------------------------------------------------------------------------
-- The viewer must stay SHOWN for us to read it: hiding stops its UNIT_AURA feed and freezes
-- auraInstanceID, and a hidden one cannot be revived from addon code (RefreshData throws - see
-- Documentation/AURA_IDENTITY_12.0.md). But "shown" need not mean "visible": alpha 0 with mouse
-- input off is indistinguishable from hidden to the player while Blizzard keeps updating it.
-- SetAlpha is AllowedWhenTainted, so unlike the RefreshData route this is legitimate.
-- We never Show() a viewer the player disabled - that is their setting to make.
local alphaGuard = {}
local alphaHooked = {}
local hiddenViewers = {}   -- [frame] = true while we are holding it invisible
local lastVisibilityProfile = nil   -- so Edit Mode transitions can re-apply without a caller

-- Profile key per viewer. Four separate booleans rather than a nested table because each binds
-- directly to its own options toggle. Names are the player-facing panel labels, not the frame
-- names, which is why TrackedBuff/TrackedBar do not match BuffIcon/BuffBar.
local VIEWER_OPTION_KEYS = {
    { frame = "EssentialCooldownViewer", key = "hideCdmEssential" },
    { frame = "UtilityCooldownViewer",   key = "hideCdmUtility" },
    { frame = "BuffIconCooldownViewer",  key = "hideCdmTrackedBuff" },
    { frame = "BuffBarCooldownViewer",   key = "hideCdmTrackedBar" },
}

local function ApplyViewerAlpha(viewer, hide)
    if not (viewer and viewer.SetAlpha) then return end
    -- Edit Mode must always be visible, or the player cannot configure or even find the panel
    -- they are being asked to enable.
    local editing = (EditModeManagerFrame and EditModeManagerFrame.IsShown
                     and EditModeManagerFrame:IsShown()) and true or false
    local target = (hide and not editing) and 0 or 1
    alphaGuard[viewer] = true
    pcall(viewer.SetAlpha, viewer, target)
    alphaGuard[viewer] = nil
    -- Stop it eating clicks while invisible.
    if viewer.GetChildren then
        local kids = { viewer:GetChildren() }
        for i = 1, #kids do
            local c = kids[i]
            if c and c.SetMouseMotionEnabled then pcall(c.SetMouseMotionEnabled, c, target == 1) end
        end
    end
end

--- Turn Blizzard's Cooldown Manager on or off at the CVar level. This is the ONE thing that
--- genuinely gates the whole system, and it is a game-wide setting - so it is only ever driven
--- from an explicit opt-in toggle, never implicitly. Out of combat only: CVar writes can be
--- refused mid-combat, and a silent failure there would be worse than not trying.
--- @return boolean applied
function MaintenanceTracker.SetCooldownManagerEnabled(on)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not (C_CVar and C_CVar.SetCVar) then return false end
    local ok = pcall(C_CVar.SetCVar, "cooldownViewerEnabled", on and "1" or "0")
    return ok and true or false
end

--- Apply the per-panel cosmetic hide from the profile. Blizzard resets alpha on layout changes,
--- so each viewer is re-asserted through a hook - guarded against re-entrancy, since our own
--- SetAlpha would otherwise recurse.
--- @param profile table
function MaintenanceTracker.ApplyViewerVisibility(profile)
    for i = 1, #VIEWER_OPTION_KEYS do
        local spec = VIEWER_OPTION_KEYS[i]
        local viewer = _G[spec.frame]
        if viewer then
            local hide = (profile and profile[spec.key]) and true or false
            hiddenViewers[viewer] = hide
            if not alphaHooked[viewer] and hooksecurefunc then
                alphaHooked[viewer] = true
                hooksecurefunc(viewer, "SetAlpha", function(frame)
                    if alphaGuard[frame] then return end
                    if hiddenViewers[frame] then ApplyViewerAlpha(frame, true) end
                end)
            end
            ApplyViewerAlpha(viewer, hide)
        end
    end

    -- Entering/leaving Edit Mode changes whether we should be hiding, but nothing else calls
    -- us at that moment - so re-apply on both transitions. Hooked once, lazily, because
    -- EditModeManagerFrame may not exist yet at load.
    lastVisibilityProfile = profile
    local emf = EditModeManagerFrame
    if emf and not alphaHooked[emf] and emf.HookScript then
        alphaHooked[emf] = true
        local function reapply()
            if lastVisibilityProfile then
                MaintenanceTracker.ApplyViewerVisibility(lastVisibilityProfile)
            end
        end
        pcall(emf.HookScript, emf, "OnShow", reapply)
        pcall(emf.HookScript, emf, "OnHide", reapply)
    end
end

--- Drop a bridge request that is never going to be answered. pendingCastAt is cleared on a
--- successful bind, but a cast can produce no bindable aura at all - then GetState would
--- answer "unknown" forever instead of "down", and the glow never fires. Time it out.
local function ExpireStalePendingCast(entry)
    local s = S(entry)
    if s and s.pendingCastAt and (GetTime() - s.pendingCastAt) > BRIDGE_WINDOW then
        s.pendingCastAt = nil
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
    local list = SpellDB and SpellDB.GetMaintenanceDefensives and SpellDB.GetMaintenanceDefensives()
    if not list then return end
    local entry
    for i = 1, #list do
        if list[i].cast == spellID then entry = list[i] break end
    end
    if not entry then return end
    local s = S(entry)
    if not s then return end
    s.lastCastAt = GetTime()
    s.pendingCastAt = s.lastCastAt
    -- A successful cast is evidence the buff is (re)applied, even when we cannot identify its
    -- instance. Without this, observedDrop latched true after the first genuine lapse and could
    -- never clear - clearing needs a live bind, and on the degraded path (no Cooldown Manager,
    -- bridge starved by ambiguity) there is none. The slot then claimed "down" for the rest of
    -- the fight and glowed at a tank whose buff was actually up. Cast evidence beats a stale flag.
    s.observedDrop = false
    -- Try the exact paths immediately. In combat the Cooldown Manager can answer this outright,
    -- which skips the bridge entirely - and the bridge is measurably wrong (it bound 744/749
    -- while the true instances were 745/750).
    local exact = FindInstanceExact(entry)
    if exact then
        s.trackedInstance = exact
        s.bindExact = true          -- identity proven
        s.pendingCastAt = nil
    end
end

--- Player aura change. Binds a pending cast to its new instance, and clears the tracked
--- instance the moment the engine says it was removed.
--- @return boolean changed - true when the up/down state may have flipped (redraw)
--- Per-entry half of OnPlayerAuraUpdate. Every buff the spec maintains gets its own binding,
--- cast clock and drop evidence - blending them would let one buff's removal clear another's
--- instance.
--- @return boolean changed
local function UpdateEntry(entry, updateInfo)
    local s = S(entry)
    if not s then return false end
    local changed = false

    ExpireStalePendingCast(entry)

    -- Removal first: authoritative "it dropped".
    if updateInfo and updateInfo.removedAuraInstanceIDs and s.trackedInstance then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if id == s.trackedInstance then
                s.trackedInstance = nil
                s.observedDrop = true   -- authoritative: the engine says it went away
                changed = true
                break
            end
        end
    end

    -- Bridge: bind a waiting cast to its instance. ADDED and UPDATED both, because re-casting
    -- a live buff refreshes the aura and the engine reports that as an update, not an addition.
    if updateInfo and s.pendingCastAt and (GetTime() - s.pendingCastAt) <= BRIDGE_WINDOW then
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
            s.trackedInstance = only
            s.bindExact = false   -- bridge guess: unambiguous in this batch, still not proof
            s.pendingCastAt = nil
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
    if not s.trackedInstance then
        local exact = FindInstanceExact(entry)
        if exact then
            s.trackedInstance = exact
            s.bindExact = true
            changed = true
        end
    end

    return changed
end

--- Player aura change. Runs every maintained buff independently.
--- @return boolean changed - true when any entry's up/down state may have flipped (redraw)
function MaintenanceTracker.OnPlayerAuraUpdate(updateInfo)
    local list = SpellDB and SpellDB.GetMaintenanceDefensives and SpellDB.GetMaintenanceDefensives()
    if not list then return false end
    local changed = false
    for e = 1, #list do
        if UpdateEntry(list[e], updateInfo) then changed = true end
    end
    return changed
end

--- Clear tracking. Called on SPEC CHANGE only (JustAC.lua) - deliberately NOT on combat exit:
--- Bone Shield (30s) and a fast Ironfur re-pull (<7s) both legitimately outlive a combat
--- boundary, so wiping there would drop a buff that is still up.
function MaintenanceTracker.Reset()
    -- Drop every entry's state wholesale: a different spec has different buffs, different
    -- cooldownIDs and different durations, so nothing here survives the switch.
    wipe(states)
    -- And invalidate the per-frame pick, or a spec change inside one frame would keep serving
    -- the OLD spec's entry until the next tick.
    pickCache.t = nil
    MaintenanceTracker._activeEntry = nil
end

--- Local-clock fallback for the swipe: our own cast time plus the entry's static duration.
--- Plain numbers, no secret involved. Used ONLY when the bind is unproven - drawing the bound
--- aura's real DurationObject there can render a completely foreign timer (a 20s trinket proc
--- on a 7s buff), which reads as "wildly wrong" rather than "slightly off". An estimate that
--- drifts by a talent's worth of seconds is far better than a confidently wrong other clock.
--- @param entry table|nil - defaults to the entry the slot is currently showing
--- @return number|nil startTime, number|nil duration
function MaintenanceTracker.GetEstimatedCooldown(entry)
    entry = entry or MaintenanceTracker._activeEntry
    local s = S(entry)
    local effDur = EffectiveDuration(entry)
    if not (s and effDur and s.lastCastAt) then return nil, nil end
    return s.lastCastAt, effDur
end

--- Was the current instance resolved by spell id (proof), or guessed by the bridge?
--- Gates the stack count: the engine renders the true number, but only off the right instance.
--- @param entry table|nil - defaults to the entry the slot is currently showing
--- @return boolean
function MaintenanceTracker.IsBindExact(entry)
    entry = entry or MaintenanceTracker._activeEntry
    local s = S(entry)
    return (s and s.trackedInstance ~= nil and s.bindExact) or false
end

--- Current state of the spec's maintenance buff.
--- @return string state - "up" (live, plenty of time) | "refresh" (live but inside its
---         refresh window - press it) | "down" | "unknown" | "none" (spec has none)
--- @return table|nil entry - the MAINTENANCE_DEFENSIVE entry
--- @return number|nil auraInstanceID - live instance, for the duration display
local function EntryState(entry)
    local s = S(entry)
    if not (entry and s) then return "none", nil, nil end
    local trackedInstance, lastCastAt = s.trackedInstance, s.lastCastAt
    ExpireStalePendingCast(entry)

    if trackedInstance and InstanceAlive(trackedInstance) then
        -- We have the instance, so nothing is waiting on the bridge any more. Clearing here
        -- covers the refresh case, where the recast never produced an addedAuras entry to
        -- bind against because the aura was updated rather than added.
        s.pendingCastAt = nil
        -- Single funnel for the drop flag: every bind path (cast, bridge, direct reseed) ends
        -- up here holding a live instance, so clearing it once here beats four call sites.
        s.observedDrop = false
        -- Buff is live - but "live" is not the same as "leave it alone". Once it is inside
        -- its refresh window the answer is press it again, so distinguish the two. Only when
        -- the entry carries a duration: Bone Shield deliberately has none, because its stacks
        -- are consumed by damage rather than expiring on a clock, so elapsed time would be a
        -- fabricated warning (see the note on the DEATHKNIGHT_1 entry).
        -- chargeGated: the button is limited by CHARGES, not by resources, so it cannot be held
        -- up perpetually and pressing early throws away buff time you may not get back. For
        -- those, skip the early "refresh" cue entirely and only signal once it has actually
        -- dropped - re-press then, if a charge happens to be banked. The pre-warning only makes
        -- sense for a resource dump (Ironfur, Marrowrend) where an early press costs nothing.
        local effDur = entry.chargeGated and nil or EffectiveDuration(entry)
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
        s.trackedInstance = nil
        s.observedDrop = true
    end

    -- One more exact attempt before declaring it down. The Cooldown Manager answers this even
    -- mid-combat when the player has the spell on a shown viewer; the by-spell-id path covers
    -- out of combat and any aura that is not secreted.
    local direct = FindInstanceExact(entry)
    if direct then
        s.trackedInstance = direct
        s.bindExact = true
        s.observedDrop = false
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
        s.observedDrop = true
        return "down", entry, nil
    end

    -- The aura is unreadable and we hold no instance, so the lookup proves nothing. Claim
    -- "down" ONLY on evidence we actually saw it go away; otherwise this is ignorance, and
    -- ignorance must render as UNKNOWN (icon, no swipe, no glow) rather than a confident cue
    -- to re-press. Measured in game: an unbound tracker reported "down" for minutes while
    -- Ironfur was up, because "never bound" and "confirmed dropped" shared this return.
    if s.observedDrop then
        return "down", entry, nil
    end
    return "unknown", entry, nil
end

--- Urgency of one entry, lower = more deserving of the slot. This is the mini-queue: the slot
--- is an extension of the defensive queue for buffs a tank KEEPS UP, so it ranks by "which of
--- my rolling buffs needs a press", not by "which defensive suits this situation" (that is the
--- defensive queue's job, and the two must not duplicate each other).
--- Pressability matters as much as state: cueing a charge-gated button with no charge banked is
--- noise, so an unpressable entry sinks below a pressable one whatever its state.
local function Urgency(entry, state)
    -- IsSpellReady is CHARGE-AWARE: a charge spell counts as ready while any charge remains,
    -- even with another recharging underneath. IsSpellOnCooldown alone reports that recharge
    -- as "on cooldown" and would sink a Shield Block the player can actually press.
    local ready = true
    if BlizzardAPI and BlizzardAPI.IsSpellReady then
        ready = BlizzardAPI.IsSpellReady(entry.cast) and true or false
    end
    -- Resources too: readiness does not cover rage/holy power.
    if ready and BlizzardAPI and BlizzardAPI.IsSpellUsable then
        if BlizzardAPI.IsSpellUsable(entry.cast) == false then ready = false end
    end
    -- Nothing actionable -> yield the slot outright, below even a healthy buff. Shield Block
    -- with no charges banked is not upkeep information, it is noise occupying the one slot
    -- another buff could be using. Only if EVERY entry is unpressable does one of these win,
    -- and then the icon simply renders greyed.
    if not ready then return 9 end
    if state == "down"    then return 1 end
    if state == "refresh" then return 2 end
    if state == "unknown" then return 3 end   -- no claim; still beats a buff that is fine
    return 4                                   -- "up" with time left: nothing to say
end

--- The entry the slot should show right now, picked across everything the spec maintains.
--- Falls back to the first entry so the slot always has an icon to draw.
--- @return string state, table|nil entry, number|nil auraInstanceID
function MaintenanceTracker.GetState()
    local now = GetTime()
    if pickCache.t == now then return pickCache.state, pickCache.entry, pickCache.inst end
    -- Store on EVERY exit, not just the timestamp: setting `t` alone made the second call in a
    -- frame hit the cache and return nils, blanking the slot.
    local function memo(state, entry, inst)
        pickCache.t, pickCache.state, pickCache.entry, pickCache.inst = now, state, entry, inst
        MaintenanceTracker._activeEntry = entry
        return state, entry, inst
    end
    local list = SpellDB and SpellDB.GetMaintenanceDefensives and SpellDB.GetMaintenanceDefensives()
    if not list then
        return memo("none", nil, nil)
    end
    -- Single-entry specs are the norm (currently all of them), and ranking one candidate can
    -- only ever pick that candidate - so skip Urgency entirely, which also skips its readiness
    -- and usability queries. The ranking stays for when a spec maintains two buffs again; it
    -- just stops costing anything while it cannot discriminate.
    if #list == 1 then
        local st, en, inst = EntryState(list[1])
        return memo(st or "unknown", en or list[1], inst)
    end
    local bestState, bestEntry, bestInst, bestRank
    for i = 1, #list do
        local st, en, inst = EntryState(list[i])
        local rank = Urgency(list[i], st)
        -- Strictly less-than, so ties keep LIST ORDER - the spec's own priority (Shield Block
        -- before Ignore Pain for Prot), which matches the defensive ordering already curated.
        if bestRank == nil or rank < bestRank then
            bestState, bestEntry, bestInst, bestRank = st, en or list[i], inst, rank
        end
    end
    -- memo also records _activeEntry: GetEstimatedCooldown/IsBindExact are called by the
    -- renderer without an entry argument, and must answer about the buff actually on screen.
    return memo(bestState or "unknown", bestEntry, bestInst)
end

--------------------------------------------------------------------------------
-- Crowd-control break: what can I press to get out of THIS?
--------------------------------------------------------------------------------
-- Unlike everything else in this file, none of it is secret. C_LossOfControl's index-based
-- reads carry no SecretWhen* flag (only the ByUnit variant is restricted), so the type of CC
-- on the player, its spell and its duration are all plainly readable in combat. No bridge, no
-- instance binding, no exact-bind gate - the engine simply answers.
--
-- locType is a cstring from the engine; SpellMechanic ids are what the breaker data is keyed
-- on, so this maps between them. Several types share a mechanic set on purpose (a fear break
-- generally also covers horrify/turn). An unrecognised locType yields nothing rather than a
-- guess: suggesting the wrong escape to a stunned tank is worse than suggesting none.
local LOC_TYPE_MECHANICS = {
    STUN            = { 12, 13 },       -- stunned, frozen
    STUN_MECHANIC   = { 12, 13 },
    FEAR            = { 5, 23, 24 },    -- fleeing, turned, horrified
    FEAR_MECHANIC   = { 5, 23, 24 },
    HORROR          = { 24, 23 },
    ROOT            = { 7, 13 },        -- rooted, frozen
    SNARE           = { 11, 8 },        -- snared, slowed
    CHARM           = { 1 },            -- charmed
    POSSESS         = { 1 },
    CONFUSE         = { 2 },            -- disoriented
    SLEEP           = { 10 },           -- asleep
    INCAPACITATE    = { 14, 17, 2 },    -- incapacitated, polymorphed, disoriented
    DISARM          = { 3 },            -- disarmed
    -- SILENCE / PACIFYSILENCE / SCHOOL_INTERRUPT are deliberately absent: almost nothing
    -- breaks them, and an empty result is the honest answer.
}

--- Mechanics for one loss-of-control entry, or nil.
--- IMPORTANT: locType is NOT flagged NeverSecret in LossOfControlData (only priority,
--- displayType and auraInstanceID are), so it CAN be a secret value - the restricted PvP
--- context is the likely case. Indexing a table with a secret key throws, so guard it: a
--- secret locType yields nil (no break shown) rather than breaking combat. The player's own
--- CC via the non-ByUnit GetActiveLossOfControlData reads plain in normal play, so this only
--- fails safe in the edge case, never in the common one.
local function MechanicsFromLoC(data)
    local lt = data and data.locType
    if IsSecret(lt) or type(lt) ~= "string" then return nil end
    return LOC_TYPE_MECHANICS[lt]
end

--- The CC currently on the player that we can actually do something about.
--- @return number|nil spellID to press
--- @return number|nil itemID non-zero when an item grants it
--- @return any|nil durationObject the CC's remaining time, for the swipe
function MaintenanceTracker.GetCCBreak()
    local LOC = C_LossOfControl
    if not (LOC and LOC.GetActiveLossOfControlDataCount and LOC.GetActiveLossOfControlData) then
        return nil
    end
    local okC, count = pcall(LOC.GetActiveLossOfControlDataCount)
    if not okC or IsSecret(count) or (count or 0) < 1 then return nil end

    local CCB = LibStub("JustAC-CCBreakers", true)
    if not (CCB and CCB.GetBreakers) then return nil end

    for i = 1, count do
        local okD, data = pcall(LOC.GetActiveLossOfControlData, i)
        local mechanics = okD and MechanicsFromLoC(data)
        if mechanics then
            for m = 1, #mechanics do
                local breakers = CCB.GetBreakers(mechanics[m])
                if breakers then
                    for spellID, itemID in pairs(breakers) do
                        -- Castability is also the passive filter: the generated table is
                        -- sourced from mechanic-immunity effects, which includes passives and
                        -- abilities that are only immune mid-cast. Requiring "known and ready
                        -- right now" drops those without hand-maintaining an exclusion list.
                        if itemID == 0 and BlizzardAPI
                           and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                           and (not BlizzardAPI.IsSpellReady or BlizzardAPI.IsSpellReady(spellID)) then
                            local okDur, dur = pcall(LOC.GetActiveLossOfControlDuration, "player", i)
                            return spellID, 0, okDur and dur or nil
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Mechanics a druid form-cancel escapes AND that we can actually DETECT. Shifting breaks roots,
-- snares and slows - but C_LossOfControl only reports hard loss-of-control, and a pure movement
-- slow is not one: measured in game, a slow gave count=0. There is no non-secret fallback either
-- (GetUnitSpeed is SecretWhenUnitStatsRestricted). So of the three, ONLY roots are detectable,
-- and only roots can be offered. Do not re-add 8/11 without a detection path that exists.
local FORM_ESCAPABLE = { [7] = true }  -- rooted (the only form-escapable CC C_LossOfControl reports)

--- A druid-only escape via the player's selected /cancelform macro, for the root/snare/slow
--- cases the breaker table misses. Returns the macro's name + duration when the player is held
--- by a form-escapable mechanic AND has designated a macro. Kept separate from GetCCBreak: that
--- returns a spell to render, this returns a MACRO, which the renderer draws differently.
--- @param profile table
--- @return string|nil macroName, any|nil durationObject
function MaintenanceTracker.GetCCBreakMacro(profile)
    local macroName = profile and profile.ccBreakMacro
    if not macroName or macroName == "" then return nil end
    local LOC = C_LossOfControl
    if not (LOC and LOC.GetActiveLossOfControlDataCount and LOC.GetActiveLossOfControlData) then
        return nil
    end
    local okC, count = pcall(LOC.GetActiveLossOfControlDataCount)
    if not okC or IsSecret(count) or (count or 0) < 1 then return nil end
    for i = 1, count do
        local okD, data = pcall(LOC.GetActiveLossOfControlData, i)
        local mechanics = okD and MechanicsFromLoC(data)
        if mechanics then
            for m = 1, #mechanics do
                if FORM_ESCAPABLE[mechanics[m]] then
                    local okDur, dur = pcall(LOC.GetActiveLossOfControlDuration, "player", i)
                    return macroName, okDur and dur or nil
                end
            end
        end
    end
    return nil
end

--- Is the maintenance slot actually on screen right now? Shared by the renderer (which draws
--- it) and the defensive queue builder (which must then NOT also list the same ability, since
--- the slot sits inside the defensive cluster and would show the icon twice in one row).
--- @param profile table
--- @return boolean active, table|nil entry
function MaintenanceTracker.IsSlotActive(profile)
    if not profile then return false, nil end
    -- Combat only, matching the renderer - out of combat the ability belongs in the normal
    -- defensive queue like any other, so the exclusion must lift with the slot.
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return false, nil end
    -- The frame has TWO independent uses, not one feature with a sub-feature: upkeep, and
    -- escaping crowd control. Either can claim it alone. A caster with no maintenance buff can
    -- still want the escape button, and a tank can want upkeep without it - so the slot is live
    -- if EITHER is enabled and has something to say.
    -- No entry is returned for the CC case: nothing is being maintained, so the defensive queue
    -- has nothing to exclude.
    if profile.showCCBreak and MaintenanceTracker.GetCCBreak and MaintenanceTracker.GetCCBreak() then
        return true, nil
    end
    if profile.showMaintenanceSlot == false then return false, nil end
    -- The PICKED entry, not list[1]. This used to return the spec's first entry, so a spec
    -- maintaining two buffs always drew the first one while GetState reported the other's
    -- state - the icon said Shield Block while the timer belonged to Ignore Pain. It also
    -- decides what the defensive queue excludes, so returning the wrong one hid the buff that
    -- was not being shown from BOTH surfaces.
    local _, entry = MaintenanceTracker.GetState()
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
