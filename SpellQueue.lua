-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Queue Module - Retrieves and caches the current Assisted Combat rotation
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 43)
if not SpellQueue then return end

-- Slot-1 wait sentinel: a number in item-id space that matches no real spell or item,
-- so every queue consumer treats it like an unknown item and skips it gracefully; the
-- shared icon renderer alone special-cases it into the wait display. See _StagePrimary.
SpellQueue.WAIT_SENTINEL = -999999999

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local DotTracker = LibStub("JustAC-DotTracker", true)

-- Hot path cache
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local IsMounted = IsMounted
local GetShapeshiftFormID = GetShapeshiftFormID
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitGUID = UnitGUID
local wipe = wipe
local type = type
local ipairs = ipairs

local lastSpellIDs = {}
local lastQueueUpdate = 0
-- Cached visibility verdict from GetCurrentSpellQueue(); read by UIRenderer via ShouldShowQueue().
-- Avoids re-evaluating the same mount/healer/OOC conditions every render frame.
local lastShouldShowQueue = true
-- Healer DPS mode: tail-filter state. isHealerSpec is nil-until-computed and
-- invalidated on spec change; healerTailBuf is the pooled filtered list.
-- The entry points hang off the SpellQueue table ON PURPOSE: GetCurrentSpellQueue
-- sits near Lua 5.1's 60-upvalue-per-function COMPILE limit ("more than 60
-- upvalues" kills the whole file), and module-table access rides its existing
-- SpellQueue upvalue instead of spending new slots. Do not "simplify" these
-- back to direct local references from inside that function.
local isHealerSpec = nil
local healerTailBuf = {}
local FormCache = nil   -- lazily resolved; false once known-absent
SpellQueue._rotationIsCustom = false
-- Pooled per-build context (wiped every build). Carries what the build stages
-- need so they take (b) instead of long positional signatures, and so the
-- coordinator can reference stage inputs through ONE table instead of dozens
-- of upvalue slots (see the 60-upvalue note above).
SpellQueue._b = {}

local function IsHealerSpecActive()
    if isHealerSpec == nil then
        local spec = GetSpecialization()
        isHealerSpec = (spec and GetSpecializationRole(spec) == "HEALER") or false
    end
    return isHealerSpec
end

-- Caster filler (per-spec toggle, healer specs only): suppress melee-weave
-- suggestions - melee-tagged abilities and form-shift buttons - for healers
-- who stay at range. Governs the addon's tail and the pos-1 fallback path;
-- AC's own pick still adapts to where the player stands.
local function CasterFillerActive(profile)
    if not IsHealerSpecActive() then return false end
    local key = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    return (key and profile.casterFiller and profile.casterFiller[key]) or false
end

local function IsWeaveSuggestion(spellID)
    if SpellDB and SpellDB.GetRange and SpellDB.GetRange(spellID) == "melee" then
        return true
    end
    if FormCache == nil then
        FormCache = LibStub("JustAC-FormCache", true) or false
    end
    return (FormCache and FormCache.GetFormIDBySpellID
        and FormCache.GetFormIDBySpellID(spellID) ~= nil) or false
end

--- Caster-filler verdict for the position-1 pick and its lookahead replacement.
function SpellQueue.IsCasterSuppressedPick(spellID, profile)
    return CasterFillerActive(profile) and IsWeaveSuggestion(spellID)
end

--- Healer tail filter: heals (plus melee-weave entries in caster mode) out of
--- the DPS tail. Custom queues exempt - the user's list is theirs. Fails open:
--- returns the original list when filtering would empty it.
function SpellQueue.FilterHealerTail(list, profile)
    if not (IsHealerSpecActive() and not SpellQueue._rotationIsCustom
            and SpellDB and SpellDB.IsHealingSpell) then
        return list
    end
    local casterMode = CasterFillerActive(profile)
    wipe(healerTailBuf)
    for i = 1, #list do
        local sid = list[i]
        if not SpellDB.IsHealingSpell(sid)
           and not (casterMode and IsWeaveSuggestion(sid)) then
            healerTailBuf[#healerTailBuf + 1] = sid
        end
    end
    if #healerTailBuf > 0 and #healerTailBuf < #list then
        return healerTailBuf
    end
    return list
end
-- True when Blizzard's position-1 pick is a maintained DoT that is already live on
-- the current target (and not in its refresh window) - i.e. AC wants it applied
-- ELSEWHERE, so the renderer shows a "switch target" arrow on the slot. Recomputed
-- each build; read by UIRenderer via IsDotSpreadActive().
local dotSpreadActive = false

-- Lazy-resolved references for gap-closer injection (loads after SpellQueue in TOC)
local cachedGapCloserEngine = nil
local cachedAddon = nil

-- Build counters (for /jac perf diagnostic)
local spellQueueBuildCount = 0
local spellQueueResetTime = GetTime()

-- Spells injected by JustAC systems (gap-closers, etc.) that should always show proc glow.
-- Populated per queue build, consumed by UIRenderer.IsSpellProcced.
local syntheticProcs = {}

-- Spells displaced from position 1 to position 2 by a gap-closer injection.
-- These were Blizzard's primary recommendation; they keep the blue assisted glow
-- at their new position so the player knows they're still the next cast after closing.
local displacedPrimary = {}

-- Burst-ready cue: queue entries matching a curated major-CD trigger that is off
-- cooldown. Separate from syntheticProcs so UIRenderer can apply the distinct
-- purple burst glow instead of the gap-closer magenta.
local burstCueSpells = {}

-- Burst-cue trigger set for the current spec, resolved in priority order:
--   1) profile.burstTriggers[specKey]        - user override (non-empty)
--   2) RotationImport.GetBurstTriggers()     - SimC sync anchors (what the APL
--      pots/trinkets into), generated per spec
--   3) SpellDB.CLASS_BURST_TRIGGER_DEFAULTS  - curated fallback
-- Set keyed by raw + talent-resolved ID for the queue scan; ordered list kept
-- for the tail pin. Rebuilt when the spec key moves; wiped on SPELLS_CHANGED
-- because talent overrides remap ResolveSpellID within a spec.
local cachedBurstTriggers = nil
local cachedBurstList = nil
local cachedBurstSource = nil   -- "custom" | "simc" | "curated" | nil
local cachedBurstSpecKey = nil
local function ResolveBurstTriggers()
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return nil end
    if cachedBurstTriggers and cachedBurstSpecKey == specKey then
        return cachedBurstTriggers, cachedBurstList
    end
    cachedBurstSpecKey = specKey
    cachedBurstTriggers, cachedBurstList, cachedBurstSource = {}, {}, nil

    -- Options can query before the first queue build resolves the addon ref.
    if not cachedAddon then cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
    local profile = cachedAddon and cachedAddon.db and cachedAddon.db.profile
    local src = profile and profile.burstTriggers and profile.burstTriggers[specKey]
    if src and #src > 0 then
        cachedBurstSource = "custom"
    else
        src = nil
    end
    if not src then
        local RI = LibStub("JustAC-RotationImport", true)
        src = RI and RI.GetBurstTriggers and RI.GetBurstTriggers()
        if src then cachedBurstSource = "simc" end
    end
    if not src then
        src = SpellDB and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS
            and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
        if src then cachedBurstSource = "curated" end
    end

    if src then
        for _, spellID in ipairs(src) do
            if spellID and spellID > 0 then
                cachedBurstTriggers[spellID] = true
                local resolved = BlizzardAPI.ResolveSpellID(spellID)
                if resolved ~= spellID then cachedBurstTriggers[resolved] = true end
                cachedBurstList[#cachedBurstList + 1] = resolved
            end
        end
    end
    return cachedBurstTriggers, cachedBurstList
end

--- True if a queue entry matches the trigger set (raw or display form).
local function IsBurstTrigger(triggers, spellID)
    if not spellID or spellID <= 0 then return false end
    if triggers[spellID] then return true end
    local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
    return (displayID and displayID ~= spellID and triggers[displayID]) or false
end

-- ── Reusable scratch buffers (wiped at start of each GetCurrentSpellQueue call) ────────────────
-- These are NOT persistent state; they are pooled to avoid GC pressure on the hot path.
local proccedSpells = {}
local normalSpells = {}
local cooldownSpells = {}
local addedSpellIDs = {}
local recommendedSpells = {}
-- Scratch set for gap-closer suppression marks (filtered by Always Show pins
-- before merging into addedSpellIDs; wiped per use).
local gcSuppressScratch = {}
-- Always Show pins resolved to every ID form (stored/override/base/display),
-- rebuilt with the rotation-list cache so hot-path checks are one table read.
local pinnedAlwaysShow = {}
--- "Hold until charged" spells resolved to every ID form, rebuilt with the
--- rotation-list cache alongside pinnedAlwaysShow.
local maxChargeGated = {}
--- "Hold until" resource dials, same form-resolution and rebuild cadence.
--- holdPoints[id] = N (discrete class-resource count); holdPctVal[id] = percent
--- of holdPctType[id] (Enum.PowerType) for the engine-side threshold gate.
local holdPoints = {}
local holdPctVal = {}
local holdPctType = {}
-- Parallel context-rank buffers for the fixed-queue archetype/range bias.
local proccedRank = {}
local normalRank = {}
-- Pooled pick-window set (SimC mode; see the pick-gates block in GetSpellQueue).
local pickWindowsBuf = {}

-- Situation memory: the AC pick churns faster than the situation it reveals.
--   stickyArch/-Range: last multi-target (aoe/cleave) pick, held STICKY_CTX_SECONDS.
--     An ST pick during AoE is common (the multi spells are cooling down - exactly
--     when the pick lies about target count); a multi pick on few targets is rare.
--     So multi evidence outlives the pick; ST picks alone don't clear it.
--   executeLatchGUID: enemy health only drops, so an execute reveal holds for the
--     rest of that target's life instead of flickering off while the execute
--     spell itself cools down.
-- Both cleared on combat exit (and the latch on target change).
local STICKY_CTX_SECONDS = 8
local stickyArch, stickyRange, stickyTime = nil, nil, 0
local executeLatchGUID = nil

-- Snapshot of the last build's context (post latch/sticky), for /jac inspect rank.
local lastCtx = {}

-- Per-update cache for spell filter results (cleared at start of each GetCurrentSpellQueue call)
-- Prevents re-checking the same spell multiple times per update cycle
local filterResultCache = {}
-- Separate table for rotation-filter results (avoids string concat "r_"..spellID in the hot path)
local rotationFilterCache = {}
-- ─────────────────────────────────────────────────────────────────────────────────────────────

-- Cached rotation spell list - only refreshed on RotationSpellsUpdated event
-- GetRotationSpells() returns a flat array of spell IDs that is static during combat;
-- Blizzard's AssistedCombatManager only calls it on SPELLS_CHANGED.
local cachedRotationList = nil
-- Rotation setup skip-state: the expensive half of a cold rebuild (pin resolution,
-- cooldown-tracking registration, CD seeding) only reruns when the refetched list
-- actually differs or a FULL invalidation demanded it. Target swaps re-query the
-- list defensively but the rotation is spec-level, so their setup rebuilds were
-- pure waste (heavy in tab-target fights).
local rotationSetupForced = true
local lastSetupList = {}
local lastSetupUseCustom = nil

-- Helper: resolve the blacklist table for the current spec from profile.
-- Returns the per-spec blacklist table (or nil), plus the spec key.
local function GetBlacklistTable()
    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    if not profile then return nil, nil end
    if not profile.blacklistedSpells then profile.blacklistedSpells = {} end
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return nil, nil end
    return profile.blacklistedSpells[specKey], specKey
end

-- A blacklist entry is `true` (hidden at every position) or `{ fixedQueue = true }`
-- (hidden from positions 2+ only - still shown at Blizzard's position-1 pick so its
-- dynamic recommendation keeps advancing instead of stalling on a spell we hide).
-- isPrimary marks the position-1 slot.
local function IsBlacklistedEntry(value, isPrimary)
    if value == true then return true end
    if type(value) == "table" and value.fixedQueue == true then
        return not isPrimary
    end
    return false
end

--------------------------------------------------------------------------------
-- Situational sets: named groups of abilities toggled as ONE unit from a keybind
-- (the "big-pull cooldowns" case - hide them for trash, flip them back for a boss).
-- Membership persists on the profile per spec; the ACTIVE flag is session-only and
-- resets to active on login/spec change, so nobody inherits yesterday's hidden
-- raid cooldowns. An INACTIVE set's members read as a full `true` blacklist entry -
-- hidden at EVERY position, the AC slot included (the substitute logic there takes
-- over). Big cooldowns are exactly what AC picks at position 1 the moment they are
-- ready, so a 2+-only hide left the feature a no-op for its own use case. This is a
-- gate on the blacklist reader, not a new path, so every caller inherits it.
--------------------------------------------------------------------------------
local SET_SLOTS = 3
SpellQueue.SET_SLOTS = SET_SLOTS
local setInactive = {}   -- [slot] = true while that set is switched OFF (session-only)

local function SetMembers(slot)
    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local sets = profile and specKey and profile.situationalSets
        and profile.situationalSets[specKey]
    return sets and sets[slot]
end

-- Is this spell (or its display form) a member of any INACTIVE set?
local function InInactiveSet(spellID)
    for slot = 1, SET_SLOTS do
        if setInactive[slot] then
            local m = SetMembers(slot)
            if m and m.spells then
                if m.spells[spellID] then return true end
                local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
                if displayID ~= spellID and m.spells[displayID] then return true end
            end
        end
    end
    return false
end

local function SetHasMembers(slot)
    local m = SetMembers(slot)
    return (m and m.spells and next(m.spells)) and true or false
end

--- An EMPTY set always reads active. Without this a set switched off and then emptied
--- from the card was stuck: ToggleSet refuses empty sets, so the flag could never be
--- flipped back, and the on-screen tag kept naming a set that hid nothing.
function SpellQueue.IsSetActive(slot)
    if setInactive[slot] and not SetHasMembers(slot) then setInactive[slot] = nil end
    return not setInactive[slot]
end

--- Flip a set. Returns the NEW active state, or nil when the slot has no members
--- (nothing to toggle - the caller can tell the player so).
function SpellQueue.ToggleSet(slot)
    if not SetHasMembers(slot) then
        setInactive[slot] = nil   -- see IsSetActive: empty is never "off"
        return nil
    end
    setInactive[slot] = not setInactive[slot] or nil
    SpellQueue.InvalidateRotationCache()
    return not setInactive[slot]
end

--- Login / spec change: every set comes back ACTIVE (decision: never persist "off").
function SpellQueue.ResetSets()
    wipe(setInactive)
end

-- Checks both base ID and its display/override ID against the blacklist.
-- isPrimary: true when testing Blizzard's position-1 pick (exempts 2+-only entries).
function SpellQueue.IsSpellBlacklisted(spellID, blacklist, isPrimary)
    if not spellID then return false end
    -- Situational sets: an inactive set's member is hidden everywhere, AC slot included.
    if InInactiveSet(spellID) then return true end
    if not blacklist then blacklist = GetBlacklistTable() end
    if not blacklist then return false end
    if IsBlacklistedEntry(blacklist[spellID], isPrimary) then return true end
    local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
    return displayID ~= spellID and IsBlacklistedEntry(blacklist[displayID], isPrimary)
end

function SpellQueue.ToggleSpellBlacklist(spellID)
    if not spellID or spellID == 0 then return end
    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    if not profile then return end
    if not profile.blacklistedSpells then profile.blacklistedSpells = {} end

    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return end

    if not profile.blacklistedSpells[specKey] then
        profile.blacklistedSpells[specKey] = {}
    end
    local blacklist = profile.blacklistedSpells[specKey]

    local spellInfo = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"

    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if blacklist[spellID] then
        blacklist[spellID] = nil
        if addon and addon.DebugPrint then addon:DebugPrint("Unblacklisted: " .. spellName) end
    else
        blacklist[spellID] = true
        if addon and addon.DebugPrint then addon:DebugPrint("Blacklisted: " .. spellName) end
    end

    local Options = LibStub("JustAC-Options", true)
    if Options and Options.UpdateBlacklistOptions and addon then
        Options.UpdateBlacklistOptions(addon)
    end
end


-- Position 1 / spellbook proc filter: availability + usability + redundancy.
-- Usability (C_Spell.IsSpellUsable) is NeverSecret; it covers resources and cast
-- conditions but NOT cooldowns - callers that care pair it with IsSpellReady.
-- Under a player-wide ability lockout it is not consulted at all: a stun or a bar-swapping
-- debuff makes EVERY spell uncastable, so filtering on it empties the queue outright - the
-- one moment the player most wants to see what to press next. The entries stay and the
-- renderer greys them from its own usability read. Same rule the defensive gate uses.
local function PassesSpellFilters(spellID, profile)
    local cached = filterResultCache[spellID]
    if cached ~= nil then return cached end
    local isUsable = BlizzardAPI.IsSpellUsable(spellID)
        or (BlizzardAPI.IsPlayerAbilityLockout and BlizzardAPI.IsPlayerAbilityLockout())
    local result = BlizzardAPI.IsSpellAvailable(spellID)
       and isUsable
       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(spellID, profile))
    filterResultCache[spellID] = result
    return result
end

-- Rotation filter: availability + redundancy only.
-- Skips usability so on-CD spells reach the categorization pass for
-- de-prioritization instead of being filtered out entirely.
local function PassesRotationFilters(spellID, profile)
    local cached = rotationFilterCache[spellID]
    if cached ~= nil then return cached end
    local result = BlizzardAPI.IsSpellAvailable(spellID)
       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(spellID, profile))
    rotationFilterCache[spellID] = result
    return result
end

-- Per-spell proc-priority opt-out. Shared store with the defensive engine
-- (profile.defensives.spellSettings[spellID].procPriority). Default true: a procced
-- spell jumps to the proc bucket. False: it stays in source order (still glows).
-- Honored only when the master "procs first" toggle is on (bypassProcs already gates that).
local function ProcPriorityEnabled(spellID, profile)
    local ss = profile.defensives and profile.defensives.spellSettings
        and profile.defensives.spellSettings[spellID]
    return not ss or ss.procPriority ~= false
end

-- Per-entry "Always Show" pin (Custom Queue rows; stored in
-- profile.defensives.spellSettings[storedID].alwaysShow). A pinned entry
-- bypasses the redundancy drop, the DoT-park sink, and the gap-closer
-- suppression - the user asked for it explicitly, so filtering must never
-- hide it. Cooldown/range sinking still applies (physical truth) and the
-- icon greys via the normal usability visuals. Consumers read the
-- pinnedAlwaysShow set (rebuilt with the rotation cache), never the profile.
function SpellQueue.IsPinnedAlwaysShow(spellID)
    return pinnedAlwaysShow[spellID] == true
end

-- Per-spell "Hold Until" dial (Custom Queue row / ability card). One family, one
-- behavior: while its condition is unmet the ability sinks to the back of the
-- queue exactly like one on cooldown - never dropped, promoted by nothing.
--   charged - short of full charges; a chargeless spell holds until off cooldown.
--   points  - the class resource (combo points, runes, ...) is below N. Exact
--             plain read; the stored N clamps to the live max so a 7 saved on a
--             5-point build releases at 5 instead of holding forever.
--   percent - the spell's own continuous cost resource is below N% (engine-side
--             threshold curve; only the boolean crosses into Lua).
-- Every read is plain or fail-open: unreadable -> released, listed order stands.
-- FRAGILE by design: the points path rides point-widget frame state and the
-- percent path rides the curve zero-gate - both unintended surfaces a major
-- patch can close (Documentation/SECRET_VALUE_THRESHOLD_GATES.md). Fail-open
-- makes that breakage invisible-but-harmless; the release notes say so out loud.
-- `ready` is passed in because the caller has already computed it for this spell in the
-- same iteration; re-querying would double the readiness work on every build.
local holdPtsCur, holdPtsMax, holdPtsFresh = nil, nil, false
local function HeldByUserHold(spellID, displayID, ready)
    if maxChargeGated[spellID] or maxChargeGated[displayID] then
        return not (ready and BlizzardAPI.IsSpellAtMaxCharges(displayID))
    end
    local n = holdPoints[spellID] or holdPoints[displayID]
    if n then
        if not holdPtsFresh then
            -- One class-resource read serves every points-hold this build.
            holdPtsFresh = true
            holdPtsCur, holdPtsMax = nil, nil
            if BlizzardAPI.GetClassResourcePoints then
                holdPtsCur, holdPtsMax = BlizzardAPI.GetClassResourcePoints()
            end
        end
        if holdPtsCur == nil then return false end
        if holdPtsMax and n > holdPtsMax then n = holdPtsMax end
        return holdPtsCur < n
    end
    local pct = holdPctVal[spellID] or holdPctVal[displayID]
    if pct then
        return BlizzardAPI.IsUnitPowerBelow and BlizzardAPI.IsUnitPowerBelow(
            "player", pct, holdPctType[spellID] or holdPctType[displayID]) == true
    end
    return false
end

-- Any dial at all on this spell? The imported SimC resource/power gates yield
-- to an explicit dial - the narrow override the Hold Until tooltip promises.
local function HasUserHold(spellID, displayID)
    return (maxChargeGated[spellID] or maxChargeGated[displayID]
        or holdPoints[spellID] or holdPoints[displayID]
        or holdPctVal[spellID] or holdPctVal[displayID]) ~= nil
end

-- shared with /jac why: report the same sink verdict the build used. Resolves readiness
-- itself (the diagnostic has no per-iteration value to hand in) and answers false for any
-- spell that isn't gated, so callers can print a reason only when it fires.
function SpellQueue.IsHeldByHold(spellID)
    if not spellID then return false end
    holdPtsFresh = false
    local displayID = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID) or spellID
    return HeldByUserHold(spellID, displayID, BlizzardAPI.IsSpellReady(displayID))
end

-- Resolve display ID, check dedup, mark both IDs as claimed.
-- Returns displayID on success, nil if already claimed.
local function ClaimSpellID(spellID, addedSpellIDs)
    if addedSpellIDs[spellID] then return nil end
    local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
    if addedSpellIDs[displayID] then return nil end
    addedSpellIDs[spellID] = true
    addedSpellIDs[displayID] = true
    return displayID
end

--- Evaluate whether the spell queue should be visible based on profile settings.
--- Returns true if queue should be shown, or false plus the reason it is hidden. A blanked
--- queue looks identical whichever branch produced it, and "my queue vanished" is only
--- actionable with the branch name attached - /jac inspect blank prints the last one.
local function EvaluateQueueVisibility(profile, inCombat)
    -- These are the STANDARD queue's visibility settings, but they gate the shared
    -- build that also feeds the nameplate overlay. With the standard surface off, its
    -- controls are greyed out - a stale saved value ("In Combat Only") would invisibly
    -- blank the overlay with no reachable control naming the reason. The overlay
    -- applies its own visibility settings at render, so the build must stay live.
    if (profile.displayMode or "queue") == "overlay" then return true end
    -- Always non-nil: it has a profile default, and the legacy keys it replaced are
    -- migrated into it on every load.
    local queueVis = profile.queueVisibility

    if queueVis == "combatOnly" and not inCombat then
        return false, "combatOnly and out of combat"
    end

    if queueVis == "requireHostile" and not inCombat then
        local hasHostileTarget = UnitExists("target") and UnitCanAttack("player", "target")
        if not hasHostileTarget then
            return false, "requireHostile and no hostile target"
        end
    end

    if profile.hideQueueWhenMounted then
        local isMounted = IsMounted()
        local formID = GetShapeshiftFormID()
        if not isMounted and (formID == 3 or formID == 27) then
            isMounted = true
        end
        if isMounted then
            -- Form ID rides along: an effect that swaps the action bar can present as a form,
            -- and this branch then hides the queue for something that is not a mount at all.
            return false, "hideQueueWhenMounted (IsMounted=" .. tostring(IsMounted())
                .. " formID=" .. tostring(formID) .. ")"
        end
    end

    return true
end

-- Last time the queue went blank, and why. Three branches can empty it - a visibility rule,
-- alternate control (vehicle/possess), or a build that produced nothing with no previous
-- queue to fall back on - and once the icons are gone they are indistinguishable. Recorded
-- at the moment of the flip so a report can name the branch instead of guessing at it.
--
-- FIRST cause of an episode wins, and it is held until the queue shows something again. The
-- blanking branches all run every build, so recording each call would overwrite the
-- interesting cause with whatever is true a second later - stand in a corridor after the
-- fight and the report would read "no spells to show" instead of naming the debuff.
local blankInfo = nil
local blankActive = false
function SpellQueue.NoteQueueBlank(reason)
    if blankActive then return end
    blankActive = true
    blankInfo = {
        reason  = reason,
        at      = GetTime(),
        inCombat = UnitAffectingCombat("player"),
        override = HasOverrideActionBar and HasOverrideActionBar() or false,
        vehicle  = HasVehicleActionBar and HasVehicleActionBar() or false,
        possess  = IsPossessBarVisible and IsPossessBarVisible() or false,
        formID   = GetShapeshiftFormID and GetShapeshiftFormID() or -1,
    }
end
function SpellQueue.GetQueueBlankInfo()
    return blankInfo
end

--- Inject procced spellbook spells (e.g. Fel Blade) after position 1.
local function AddSpellbookProcs(b)
    -- Unpacked build context; body unchanged from the positional-argument era.
    local profile, blacklist = b.profile, b.blacklist
    local addedSpellIDs, recommendedSpells = b.addedSpellIDs, b.recommendedSpells
    local spellCount, maxIcons, hideItems = b.spellCount, b.maxIcons, b.hideItems
    local spellbookProcs = ActionBarScanner and ActionBarScanner.GetSpellbookProccedSpells and ActionBarScanner.GetSpellbookProccedSpells()
    if not spellbookProcs then return spellCount end

    for _, procSpellID in ipairs(spellbookProcs) do
        if spellCount >= maxIcons then break end
        if procSpellID and not addedSpellIDs[procSpellID] then
            local displayID = ClaimSpellID(procSpellID, addedSpellIDs)
            if displayID
               and (not SpellDB or SpellDB.IsOffensiveSpell(procSpellID))
               and (ActionBarScanner.GetSpellHotkey(procSpellID) or "") ~= ""
               and not SpellQueue.IsSpellBlacklisted(procSpellID, blacklist)
               and not (hideItems and BlizzardAPI.IsItemSpell(procSpellID))
               and PassesSpellFilters(procSpellID, profile)
               -- A proc glow that outlives its cast (execute-type spells inside a
               -- window) kept seating the spell here ON COOLDOWN, swipe and all, ahead
               -- of the whole tail - usability never looks at cooldowns. Not ready ->
               -- leave it unclaimed: a rotation spell then reaches the tail and sinks
               -- (still glowing); a spellbook-only proc simply waits its cooldown out.
               and BlizzardAPI.IsSpellReady(procSpellID) then
                spellCount = spellCount + 1
                recommendedSpells[spellCount] = procSpellID
            else
                -- Undo claim if filters rejected the spell
                if displayID then
                    addedSpellIDs[procSpellID] = nil
                    addedSpellIDs[displayID] = nil
                end
            end
        end
    end
    return spellCount
end

--- Profile-distance rank for the queue (positions after the AC slot). LOWER = closer match
--- to the AC pick's profile, so it sorts earlier within its bucket; a large sink value trails.
--- Rationale: the AC pick encodes the current situation, so the queue ability whose profile
--- (archetype + geometry + build/spend role) is CLOSEST to it is the best same-situation DPS.
--- Graded distance, NOT a gate: a slightly-off ability (e.g. a ranged AoE when the pick is a
--- melee/PBAoE AoE) ranks just behind the exact match rather than being flattened to neutral.
--- Axes fold into the distance (all tunable via the constants below). Each spell reduces to
--- a target pattern: single | melee-multi | ranged-multi (see pattern()). Cleave counts as
--- melee-multi - a cleave ability is treated as equivalent to a melee/PBAoE AoE.
---   pattern  same +0 | multi<->multi with different geometry (melee<->ranged) +GEOM_PEN
---            | multi<->single +ARCH_MISS | untagged +ARCH_UNK (neutral middle)
---   role     same build/spend phase +0 | different +ROLE_PEN | untagged +0
--- Two overrides sit OUTSIDE the distance:
---   execute - when the pick is execute-gated the target is in execute range (secret-free
---             target-HP read), so every execute-gated spell floats to 0 regardless of profile.
---   sink    - a melee spell with the target CONFIRMED out of melee (real IsSpellInRange-based
---             read via SpellDB.IsTargetWithin(5)) is uncastable, so it trails at RANK_SINK.
---   dying   - the last thing fighting us is nearly dead and is not a boss, so the spec's
---             major cooldowns trail at RANK_SINK too (see the guard in _StageContext).
--- Fail-safe: an untagged pick (ctxArch nil) makes every spell ARCH_UNK -> uniform -> source
--- order preserved. ctxOutOfMelee is only true on a confirmed read; unknown -> no sink.
--- Target count is AC's to read, not ours: when AC offers a cleave ability while an AoE sits
--- available in the kit, it has REVEALED a cleave-tier count (it would have offered the AoE
--- otherwise). So ctxArch already encodes the target-count regime we can't read directly - no
--- nameplate count needed to know the situation; it would only help rank untagged picks.
local ARCH_MISS = 4   -- multi-target <-> single-target: a real situational mismatch
local ARCH_UNK  = 3   -- one side untagged: neutral middle, neither boost nor bury
local GEOM_PEN  = 1   -- melee-multi <-> ranged-multi: same AoE need, different delivery
local ROLE_PEN  = 1   -- builder <-> spender: wrong resource phase
local RANK_SINK = 9   -- uncastable (melee, target out of range): trails everything
-- Wasted-cooldown guard threshold (see _StageContext). 20%, matching the execute
-- probe, so the two share one memo entry per tick instead of costing two curve
-- evaluations; it is also where a lone trash mob is genuinely a few globals from
-- dead. Bosses are excluded before this is ever asked.
local DYING_TARGET_PCT = 20
-- SimC-mode blend: a ranked entry sorts by ctx*CONTEXT_STRIDE + simc, so the ContextRank
-- fit-bucket (0..RANK_SINK) always dominates and the SimC list index only orders within a
-- bucket. STRIDE exceeds any SimC rank component; an ability the SimC list omits takes
-- SIMC_UNRANKED (trails the ranked ones inside its own context bucket, not the whole queue).
local CONTEXT_STRIDE = 1000
local SIMC_UNRANKED  = 999
-- Reduce (archetype, range) to a target pattern. Cleave counts as melee-multi: a cleave
-- ability is treated as equivalent to a melee/PBAoE AoE. AoE keeps its own geometry
-- (melee/PBAoE vs ranged/ground); ST is single-target. Untagged -> nil -> neutral.
local function pattern(arch, range)
    if arch == "aoe"    then return (range == "ranged") and "rmulti" or "mmulti" end
    if arch == "cleave" then return "mmulti" end
    if arch == "st"     then return "st" end
    return nil
end
local function ContextRank(spellID, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee, ctxDying)
    if ctxExecute and SpellDB and SpellDB.GetGate and SpellDB.GetGate(spellID) == "execute" then
        return 0
    end
    -- Below the execute float on purpose: an execute-gated finisher is exactly the
    -- right press on a dying mob and keeps its promotion. It is the multi-minute
    -- cooldowns that buy nothing here.
    if ctxDying then
        local triggers = ResolveBurstTriggers()
        if triggers and IsBurstTrigger(triggers, spellID) then return RANK_SINK end
    end
    local range = SpellDB and SpellDB.GetRange and SpellDB.GetRange(spellID)
    if ctxOutOfMelee and range == "melee" then
        return RANK_SINK
    end
    if not ctxArch then return ARCH_UNK end   -- no context to match against: uniform neutral
    local dist = 0
    local arch = SpellDB and SpellDB.GetArch and SpellDB.GetArch(spellID)
    local pat = pattern(arch, range)
    local ctxPat = pattern(ctxArch, ctxRange)
    if not pat or not ctxPat then
        dist = dist + ARCH_UNK
    elseif pat ~= ctxPat then
        if pat ~= "st" and ctxPat ~= "st" then
            dist = dist + GEOM_PEN    -- both multi, different geometry (melee vs ranged)
        else
            dist = dist + ARCH_MISS   -- multi vs single-target
        end
    end
    local role = SpellDB and SpellDB.GetRole and SpellDB.GetRole(spellID)
    if role and ctxRole and role ~= ctxRole then
        dist = dist + ROLE_PEN
    end
    return dist
end

--- Structurally unusable: the action bar reports a confirmed-unusable state that is NOT
--- resource starvation. Catches condition-gated spells the cooldown model can't see -
--- Confirmed unusable for a NON-resource reason (wrong form/stance, no stealth,
--- missing required aura, disabled), via the never-secret C_Spell.IsSpellUsable.
--- The game evaluates form, talents, stealth, and cast conditions for us, so no
--- static form/stealth/caster-aura tables are needed (it also knows form-bypass
--- hero talents the static data can't see). Resource starvation (energy/rage
--- refills every GCD) is transient and must NOT sink or the queue churns every
--- press, so notEnoughResources is excluded. A secret/unknown read fails open to
--- "usable" (BlizzardAPI.IsSpellUsable handles that fallback) and leaves order alone.
local function IsUnusableNonResource(spellID)
    local usable, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID, true)
    return usable == false and not notEnoughResources
end
SpellQueue.IsUnusableNonResource = IsUnusableNonResource  -- shared with /jac why

--- Confirmed out of range on the current target. Catches range gates usability can't see:
--- a minimum range (Heroic Throw inside 8yd), melee against a kited target. IsSpellInRange's
--- boolean is never secret (only the yardage is - same read the icon's red range tint uses).
--- nil (no range requirement, no valid target) or a secret fails open and leaves order alone.
--- No debounce: the flip only happens on genuine positional change, and the queue is
--- context-live by design (melee sink, execute float) - the red tint explains the move.
local function IsConfirmedOutOfRange(spellID)
    -- Fail open: nil (unknown) leaves the order alone; only a confirmed false sinks.
    return (BlizzardAPI and BlizzardAPI.SpellInRange
            and BlizzardAPI.SpellInRange(spellID)) == false
end
SpellQueue.IsConfirmedOutOfRange = IsConfirmedOutOfRange  -- shared with /jac why

--- Append a bucket's entries to recommendedSpells in profile-distance order
--- (closest match first), stable within each rank. Returns the new spellCount.
local rankSortIdx = {}
-- Comparator hoisted to module scope (reads the sortRanks upvalue set below) so the
-- hot path doesn't allocate a fresh closure on every call - AppendRankedBucket runs
-- ~2x per queue build (proc + normal buckets), ~30Hz in combat.
local sortRanks
local function rankSortComparator(a, b)
    if sortRanks[a] ~= sortRanks[b] then return sortRanks[a] < sortRanks[b] end
    return a < b
end
local function AppendRankedBucket(bucket, ranks, count, recommendedSpells, spellCount, maxIcons)
    -- Stable sort by rank (ascending = higher priority), ties keeping insertion order.
    -- Handles both ContextRank (0..RANK_SINK) and SimC priority ranks (a list index that
    -- can exceed RANK_SINK, plus a large unranked sentinel) - the old 0..RANK_SINK
    -- bucket-iteration silently dropped anything ranked above RANK_SINK.
    wipe(rankSortIdx)
    for i = 1, count do rankSortIdx[i] = i end
    sortRanks = ranks
    table.sort(rankSortIdx, rankSortComparator)
    for k = 1, count do
        if spellCount >= maxIcons then break end
        spellCount = spellCount + 1
        recommendedSpells[spellCount] = bucket[rankSortIdx[k]]
    end
    return spellCount
end

--- Categorize rotation spells into procced/normal/cooldown buckets and assemble
--- in priority order: proc > normal > on-cooldown. Within the proc and normal buckets,
--- entries are ordered by ContextRank (profile-distance to the AC pick) so the ability
--- closest to what Assisted Combat is recommending surfaces first; SimC mode refines that
--- ordering with the theorycraft rank as a tiebreaker within each fit. ctxArch is nil when
--- the AC pick is untagged → uniform rank → no reorder.
local RotationImport = LibStub("JustAC-RotationImport", true)

-- True if any positive SimC buff-window gate is active (engine-truth via the
-- duration-object probe). A ranked ability with its window up promotes like a proc.
local function SimcBuffWindowActive(gates)
    if not gates then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "buff" and not g.neg and g.id
           and BlizzardAPI.IsBuffWindowActive and BlizzardAPI.IsBuffWindowActive(g.id) then
            return true
        end
    end
    return false
end

-- True if a positive buff-window gate is one the AC pick ALREADY revealed as active. AC only
-- recommends a window-gated spell inside its window, so its pick launders the window state even
-- when the buff aura is secret (the aura probe above can't see secret auras). This promotes a
-- sibling that shares the pick's window that the probe alone would miss.
local function GateInPickWindows(gates, pickWindows)
    if not gates or not pickWindows then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "buff" and not g.neg and g.id and pickWindows[g.id] then return true end
    end
    return false
end

--- True when the entry carries any positive buff-window gate at all - i.e. the
--- SimC data DEFINES a window this ability belongs to (vs. "cast on cooldown").
local function HasPositiveBuffGate(gates)
    if not gates then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "buff" and not g.neg and g.id then return true end
    end
    return false
end

--- True when one of the entry's positive window gates IS Blizzard's current pick
--- (raw or display form) - AC is recommending the very ability that opens this
--- window (e.g. pick = Tiger's Fury while Berserk is gated on the TF buff), so
--- the window is about to exist even though no aura is up yet.
local function TriggerWindowOpenerIsPick(gates, pickID, pickDisplay)
    if not gates or not pickID then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "buff" and not g.neg and g.id
           and (g.id == pickID or g.id == pickDisplay) then
            return true
        end
    end
    return false
end

-- True if a NEGATIVE buff gate (!buff[Y], "must NOT have Y") is CONFIRMED active - the window
-- condition is currently violated, so the entry must not promote (e.g. Rip's `!buff.berserk`
-- during Berserk). Uses the same aura probe; a secret/unreadable Y reads as not-active and fails
-- OPEN (no block), mirroring how the positive side already treats secrets - so this never sinks a
-- promotion on an unreadable negative, it only blocks one we can actually see is violated.
-- True when a resource gate is present, EVALUABLE, and NOT satisfied - the entry is not worth
-- surfacing yet (Shred once you are already at 5 combo points, Hand of Gul'dan under 3 shards).
-- The count is plain frame state from BlizzardAPI.GetClassResourcePoints, never a secret read.
-- Unknown - bar hidden (and therefore frozen), secret, or a different resource than this gate
-- names - FAILS OPEN (false), so the entry keeps its previous delegated behaviour rather than
-- being buried on a guess.
--- Does this spell spend power? Plain metadata (GetSpellPowerCost is unannotated),
--- used only while the primary resource is capped, so the extra call is rare.
-- Verdict cached per spellID (cost tables are static per talent build; the API
-- allocates a fresh table per call and this runs per candidate per build while
-- power-capped). Wiped with the spell cache on SPELLS_CHANGED.
local spenderCache = {}
local function IsSpenderSpell(spellID)
    local cached = spenderCache[spellID]
    if cached ~= nil then return cached end
    local verdict = false
    if C_Spell and C_Spell.GetSpellPowerCost then
        local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
        if ok and type(costs) == "table" then
            for i = 1, #costs do
                local c = costs[i]
                local amt = c and c.cost
                if type(amt) == "number" and not (issecretvalue and issecretvalue(amt)) and amt > 0 then
                    verdict = true
                    break
                end
            end
        end
    end
    spenderCache[spellID] = verdict
    return verdict
end

-- Discrete point-style power types: exact plain count via GetClassResourcePoints;
-- everything else is continuous and gates through the engine threshold curve.
local DISCRETE_POWER = {}
do
    local PT = Enum and Enum.PowerType
    if PT then
        for _, k in ipairs({ "ComboPoints", "Runes", "SoulShards", "HolyPower",
                             "Chi", "ArcaneCharges", "Essence" }) do
            if PT[k] then DISCRETE_POWER[PT[k]] = true end
        end
    end
end

--- The resource a "Hold Until" dial gates on: the spell's OWN cost rows, discrete
--- row preferred - points are the strategic resource, while a continuous cost is
--- usually a tax the starved sink already covers. Returns kind ("pts"|"pct"),
--- Enum.PowerType, localized power name; nil when the spell has no cost row.
--- Shared with the options dial builder so both shape from the same rule.
function SpellQueue.GetHoldResource(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return nil end
    local cont
    for i = 1, #costs do
        local c = costs[i]
        local t = c and c.type
        if type(t) == "number" and not (issecretvalue and issecretvalue(t)) then
            if DISCRETE_POWER[t] then
                return "pts", t, c.name and _G[c.name] or nil
            elseif not cont and type(c.cost) == "number"
                   and not (issecretvalue and issecretvalue(c.cost)) and c.cost > 0 then
                cont = c
            end
        end
    end
    if cont then return "pct", cont.type, cont.name and _G[cont.name] or nil end
    return nil
end

local function SimcResourceGateBlocks(gates, resCount, resName, resMax)
    if not gates or not resCount then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "resource" and g.res == resName and g.op and g.n then
            -- `.deficit` asks how much ROOM is left (max - current). For countable
            -- resources both numbers are plain - the point-widget read returns
            -- current AND max - so this is ordinary arithmetic and needs no gate.
            -- Unknown max -> skip this one rather than guess (fails open).
            local value = resCount
            if g.deficit then
                value = (type(resMax) == "number" and resMax > 0) and (resMax - resCount) or nil
            end
            if value then
                local ok
                if     g.op == ">=" then ok = value >= g.n
                elseif g.op == "<=" then ok = value <= g.n
                elseif g.op == ">"  then ok = value >  g.n
                elseif g.op == "<"  then ok = value <  g.n
                elseif g.op == "="  then ok = value == g.n
                elseif g.op == "!=" then ok = value ~= g.n
                end
                if ok == false then return true end
            end
        end
    end
    return false
end

-- SimC resource token -> Enum.PowerType, resolved lazily so a missing Enum can
-- never break file load. Only CONTINUOUS resources belong here; the countable
-- ones (combo points, chi, shards...) have their own exact read above.
local simcPowerTypes
local function SimcPowerType(res)
    if not simcPowerTypes then
        local E = (Enum and Enum.PowerType) or {}
        simcPowerTypes = {
            mana = E.Mana, rage = E.Rage, focus = E.Focus, energy = E.Energy,
            runic_power = E.RunicPower, astral_power = E.LunarPower,
            maelstrom = E.Maelstrom, insanity = E.Insanity,
            fury = E.Fury, pain = E.Pain,
        }
    end
    return simcPowerTypes[res]
end

--- The ONE verdict rule for every threshold gate: given the engine's
--- below/at-or-above answer, does this gate block? An unreadable answer (nil)
--- never blocks - an unevaluable gate must keep the entry's delegated behaviour
--- rather than bury it on a guess.
--- `.deficit` inverts the sense: "lots of room left" IS "the level is low".
local function ThresholdGateBlocks(g, below)
    if below == nil then return false end
    local wantBelow
    if     g.op == ">=" or g.op == ">"  then wantBelow = false
    elseif g.op == "<"  or g.op == "<=" then wantBelow = true
    else return false end                      -- = / != are not thresholds
    if g.deficit then wantBelow = not wantBelow end
    return below ~= wantBelow
end

--- The percentage a continuous-resource gate resolves to, plus its power type.
--- SimC states these in ABSOLUTE units while the gate takes a percentage, so the
--- conversion goes through UnitPowerMax - plain, and read LIVE because talents
--- move maximums. `.pct` forms arrive as percentages already; `.deficit` asks
--- about the room left, so the threshold becomes max-N (the comparison flips in
--- ThresholdGateBlocks). Shared with the simcgates probe so the number it
--- displays is the number this actually uses.
function SpellQueue.PowerGateThreshold(g)
    local pt = g and g.res and SimcPowerType(g.res)
    if not (pt and g.n) then return nil, nil end
    if g.ispct and not g.deficit then return g.n, pt end
    local max = UnitPowerMax("player", pt)
    if type(max) ~= "number" or max <= 0
       or (issecretvalue and issecretvalue(max)) then return nil, pt end
    return (g.deficit and (100 * (max - g.n) / max) or (100 * g.n / max)), pt
end

local function SimcPowerGateBlocks(gates)
    if not gates or not BlizzardAPI.IsUnitPowerBelow then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "power" and g.op and g.n and g.res then
            local pct, pt = SpellQueue.PowerGateThreshold(g)
            if pct and ThresholdGateBlocks(g, BlizzardAPI.IsUnitPowerBelow("player", pct, pt)) then
                return true
            end
        end
    end
    return false
end

--- Health threshold gates. "execute" asks about the TARGET (its percentage comes
--- from SimC's APLs, the only place per-spell execute thresholds exist - DB2 has
--- no health-threshold column); "health" asks the same question of the PLAYER,
--- which defensive APL lines lean on. One loop, since only the unit differs.
--- No target = no opinion on execute gates (fail open).
local function SimcHealthGateBlocks(gates)
    if not gates or not BlizzardAPI.IsUnitHealthBelow then return false end
    local haveTarget = UnitExists("target") and UnitCanAttack("player", "target")
    for i = 1, #gates do
        local g = gates[i]
        if g.pct and g.op then
            local unit
            if g.t == "execute" then
                unit = (haveTarget and not g.neg) and "target" or nil
            elseif g.t == "health" then
                unit = "player"
            end
            if unit and ThresholdGateBlocks(g, BlizzardAPI.IsUnitHealthBelow(unit, g.pct)) then
                return true
            end
        end
    end
    return false
end

--- Aura-STACK gates. The count is secret, but the engine renders it only at or
--- above a minimum we name, so "at least N" is the one question available - and
--- every SimC comparison reduces to one or two of them. `=` is the only form that
--- costs two. Unanswerable at any step -> nil -> the gate does not block.
local function StackAtLeast(unit, id, k)
    if k <= 0 then return true end
    return BlizzardAPI.GetAuraStackAtLeast(unit, id, k)
end

--- Does one stack gate HOLD? true / false / nil (unanswerable).
local function StackHolds(unit, g)
    local n, op, id = g.n, g.op, g.id
    if op == ">=" then return StackAtLeast(unit, id, n) end
    if op == ">"  then return StackAtLeast(unit, id, n + 1) end
    local a
    if op == "<" then
        a = StackAtLeast(unit, id, n)
    elseif op == "<=" then
        a = StackAtLeast(unit, id, n + 1)
    elseif op == "=" then
        a = StackAtLeast(unit, id, n)
        if a == nil then return nil end
        if not a then return false end          -- below n, so not equal to n
        local hi = StackAtLeast(unit, id, n + 1)
        if hi == nil then return nil end
        return not hi                            -- at n, and not above it
    else
        return nil
    end
    if a == nil then return nil end
    return not a
end

local function SimcStackGateBlocks(gates)
    if not (gates and BlizzardAPI.GetAuraStackAtLeast) then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "stack" and g.id and g.op and g.n then
            -- `tgt` gates read the TARGET's debuff; no target means no opinion.
            local unit = g.tgt and "target" or "player"
            if not g.tgt or UnitExists("target") then
                if StackHolds(unit, g) == false then return true end
            end
        end
    end
    return false
end
SpellQueue._StackHolds = StackHolds            -- diagnostics (/jac inspect simcgates)

--- Every evaluable SimC gate in ONE call. Any single unsatisfied gate blocks.
--- Both call sites use this rather than the individual blockers, so a new gate
--- type cannot be wired into one and forgotten at the other.
local function SimcGateBlocks(gates, resCount, resName, resMax, skipResource)
    if not gates then return false end
    -- skipResource: an explicit Hold Until dial replaces the imported resource
    -- and power conditions for that spell; window/health/stack gates still apply.
    return (not skipResource and (SimcResourceGateBlocks(gates, resCount, resName, resMax)
                or SimcPowerGateBlocks(gates)))
        or SimcHealthGateBlocks(gates)
        or SimcStackGateBlocks(gates)
end
SpellQueue._SimcGateBlocks = SimcGateBlocks   -- diagnostics (/jac inspect simcgates)

local function SimcNegativeBuffBlocks(gates)
    if not gates then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "buff" and g.neg and g.id
           and BlizzardAPI.IsBuffWindowActive and BlizzardAPI.IsBuffWindowActive(g.id) then
            return true
        end
    end
    return false
end

-- Hoisted rank helper: upvalues are set once per build by CategorizeAndAssembleRotation
-- below (same pattern as rankSortComparator) - defining this inline allocated a closure
-- every build tick.
local rankSimcMode, rankContextOrder
local rankCtxArch, rankCtxRange, rankCtxRole, rankCtxExecute, rankCtxOutOfMelee, rankCtxDying
local function rankOf(spellID, simcRec)
    if rankSimcMode then
        local ctx = ContextRank(spellID, rankCtxArch, rankCtxRange, rankCtxRole, rankCtxExecute, rankCtxOutOfMelee, rankCtxDying)
        local simc = (simcRec and simcRec.rank) or SIMC_UNRANKED
        if simc > SIMC_UNRANKED then simc = SIMC_UNRANKED end
        return ctx * CONTEXT_STRIDE + simc
    elseif rankContextOrder == "ac" then
        return ContextRank(spellID, rankCtxArch, rankCtxRange, rankCtxRole, rankCtxExecute, rankCtxOutOfMelee, rankCtxDying)
    end
    return 1
end

local function CategorizeAndAssembleRotation(rotationList, b)
    -- Unpack the build context once; the body below is unchanged from the
    -- 18-positional-argument era.
    local profile, blacklist = b.profile, b.blacklist
    local addedSpellIDs, recommendedSpells = b.addedSpellIDs, b.recommendedSpells
    local spellCount, maxIcons, hideItems = b.spellCount, b.maxIcons, b.hideItems
    local bypassProcs = b.effectiveBypassProcs
    local ctxArch, ctxRange, ctxRole = b.ctxArch, b.ctxRange, b.ctxRole
    local ctxExecute, ctxOutOfMelee, ctxDying = b.ctxExecute, b.ctxOutOfMelee, b.ctxDying
    local contextOrder, sinkCooldowns = b.contextOrder, b.sinkCooldowns
    local simcCtx, pickWindows = b.simcCtx, b.pickWindows
    wipe(proccedSpells)
    wipe(normalSpells)
    wipe(proccedRank)
    wipe(normalRank)
    holdPtsFresh = false   -- fresh class-resource read for this build's holds
    local proccedCount, normalCount, cooldownCount = 0, 0, 0
    -- rankOf: "off" = neutral (source order); "ac" = ContextRank alone (profile-distance to
    -- the AC pick); "simc" = that SAME context distance REFINED by SimC's theorycraft priority.
    -- AC owns the AC slot and, able to read the state we can't, carries the real
    -- context - so even in SimC mode we rank primarily by how well an ability COMPLEMENTS that
    -- pick (ContextRank), using the SimC rank only to break ties among equally-fitting abilities.
    -- Encoding ctx*CONTEXT_STRIDE + simc makes context dominate: a better fit outranks a higher
    -- SimC rank, and a spell the SimC list omits still sorts by context (no longer dumped to the
    -- back). e.g. fits-pick + SimC #3 -> 3; fits-pick but unlisted -> 999; off-pattern + SimC #1
    -- -> 1001. The SimC entry is pre-fetched per spell and passed in to avoid a second lookup.
    local simcMode = (contextOrder == "simc")
    -- Discrete class-resource count once per build (combo points / holy power / chi / shards /
    -- runes / essence / arcane charges), for the SimC resource gates. nil = unknown -> those
    -- gates fail open. Only needed in SimC mode, where gates exist.
    local resCount, resName, resMax
    if simcMode and BlizzardAPI.GetClassResourcePoints then
        local c, m, r = BlizzardAPI.GetClassResourcePoints()
        resCount, resName, resMax = c, r, m   -- max feeds the `.deficit` gates
    end
    -- Primary resource capped (engine full-power pulse, plain - validated in combat
    -- 2026-07-24): promote ready, affordable spenders so regen stops going to waste.
    -- Read once per build; false for power types without a full-power animation.
    -- Ranked modes only: with Context ordering OFF the list is the user's, and only
    -- Blizzard's own proc overlay may jump it. The charge-cap and power-cap promotions
    -- are ranking heuristics, not procs - a full-charge Death and Decay seated ahead
    -- of a fixed custom list read as "the order is broken".
    local heuristicPromos = contextOrder ~= "off"
    local powerCapped = heuristicPromos and BlizzardAPI.IsPrimaryPowerCapped and BlizzardAPI.IsPrimaryPowerCapped()
    -- Arm the hoisted rankOf for this build (see its definition above).
    rankSimcMode, rankContextOrder = simcMode, contextOrder
    rankCtxArch, rankCtxRange, rankCtxRole, rankCtxExecute, rankCtxOutOfMelee, rankCtxDying =
        ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee, ctxDying

    for i = 1, #rotationList do
        local spellID = rotationList[i]
        if spellID and not addedSpellIDs[spellID] then
            if spellID < 0 then
                -- Item entry (negative ID): use item-specific APIs.
                -- Items are only present via Custom Queue - skip spell filters.
                local itemID = -spellID
                addedSpellIDs[spellID] = true
                local _, hasItem, onCooldown = BlizzardAPI.CheckDefensiveItemState(itemID)
                if hasItem then
                    if onCooldown and sinkCooldowns then
                        cooldownCount = cooldownCount + 1
                        cooldownSpells[cooldownCount] = spellID
                    else
                        normalCount = normalCount + 1
                        normalSpells[normalCount] = spellID
                        normalRank[normalCount] = 1  -- items: neutral
                    end
                end
            elseif not SpellQueue.IsSpellBlacklisted(spellID, blacklist) then
                local displayID = ClaimSpellID(spellID, addedSpellIDs)
                local alwaysShow = pinnedAlwaysShow[spellID]
                if displayID
                   and not (hideItems and BlizzardAPI.IsItemSpell(displayID))
                   and (PassesRotationFilters(displayID, profile)
                        or (alwaysShow and BlizzardAPI.IsSpellAvailable(displayID))) then
                    -- The proc overlay is Blizzard's NeverSecret "press this now" signal,
                    -- but it lingers on a spell consumed into its own cooldown (an execute
                    -- proc like Shadow Word: Death glows on, then cools down after the cast).
                    -- A proc you can't act on yet must not hold a front slot - gate the proc
                    -- bucket on readiness so it sinks with the other cooldowns (still glowing)
                    -- until usable again. This does NOT undo mid-combat reset detection: for a
                    -- flat cooldown IsSpellReady reads the authoritative isActive, so a real
                    -- proc-driven CD *reset* reports ready and keeps its proc slot.
                    -- ponytail: charge-refund procs are unreadable in combat (charges secret),
                    -- so IsSpellReady falls back to stale local charge counts and such a proc
                    -- could sink early. Rare; exempt charge spells here if one ever regresses.
                    local ready = BlizzardAPI.IsSpellReady(displayID)
                    -- "Hold Until" dial (charged / points / percent): treat a held ability
                    -- exactly like one that isn't ready - sink it, never drop it. It keeps
                    -- its place in the queue rather than being filtered out, though like
                    -- anything in the cooldown tail it can fall past maxIcons and off screen.
                    -- Gated on sinkCooldowns so the whole feature is genuinely inert when
                    -- "Unavailable last" is off, which is what the option's tooltip promises -
                    -- otherwise it would still strip proc promotion below and quietly reorder.
                    local held = sinkCooldowns and HeldByUserHold(spellID, displayID, ready)
                    local simcRec = (simcMode and RotationImport and RotationImport.GetEntry)
                        and RotationImport.GetEntry(spellID, simcCtx) or nil
                    -- Explicit dial -> the imported resource gates yield for this spell.
                    local dialSet = simcRec and HasUserHold(spellID, displayID) or false
                    -- Spenders sink while you can't afford them (IsSpellUsable's
                    -- insufficientPower is NeverSecret), so builders surface while you're
                    -- starved and the spender rises once you can pay. Every mode, every
                    -- spell with a power cost: only delegated SimC entries were checked
                    -- before, so a custom Frost list could not tell Obliterate from Frost
                    -- Strike by runes vs runic power. Fail-safe - only sink on a definite "no".
                    -- ponytail: churns on energy/rage classes as the pool refills each GCD;
                    -- scope to discrete-resource classes if that shows in play.
                    local starved = false
                    if (simcRec and simcRec.delegated) or IsSpenderSpell(displayID) then
                        local _, notEnough = BlizzardAPI.IsSpellUsable(displayID, true)
                        starved = notEnough and true or false
                    end
                    -- Loss-of-control lockout: THIS spell can't be cast right now (a stun
                    -- locks everything, a kick locks one school). NeverSecret boolean,
                    -- validated both states in-game 2026-07-24. Sinks with the cooldowns
                    -- and blocks proc promotion; costs one count read when not CC'd.
                    local locLocked = BlizzardAPI.IsSpellLoCLocked
                        and BlizzardAPI.IsSpellLoCLocked(displayID) or false
                    -- Capped charges idle the recharge timer - surfacing the spell gets a
                    -- charge spent. Promotes through the proc bucket under the same
                    -- ProcPriorityEnabled gate, so users who disable proc jumps keep
                    -- their ordering. Ranked modes only (heuristicPromos).
                    local chargeCapped = heuristicPromos and not locLocked and BlizzardAPI.IsSpellChargeCapped
                        and BlizzardAPI.IsSpellChargeCapped(displayID) or false
                    -- A ranked ability whose SimC buff-window is up promotes like a proc, so
                    -- it surfaces inside its window (e.g. Rip during Tiger's Fury) - but never
                    -- an unaffordable spender.
                    -- Blizzard's proc overlay is authoritative ("press this now") and promotes
                    -- outright. A SimC buff-window promotion (probe or pick-implied) is instead
                    -- vetoed by a confirmed-active negative gate, so a window spender doesn't
                    -- surface while its "not during X" condition is visibly violated.
                    if not bypassProcs and ready and not starved and not held and not locLocked
                       and (BlizzardAPI.IsSpellProcced(displayID)
                            or chargeCapped
                            or (powerCapped and IsSpenderSpell(displayID))
                            or (simcRec
                                and (SimcBuffWindowActive(simcRec.gates)
                                     or GateInPickWindows(simcRec.gates, pickWindows))
                                and not SimcNegativeBuffBlocks(simcRec.gates)
                                and not SimcGateBlocks(simcRec.gates, resCount, resName, resMax, dialSet)))
                       and ProcPriorityEnabled(spellID, profile) then
                        proccedCount = proccedCount + 1
                        proccedSpells[proccedCount] = displayID
                        proccedRank[proccedCount] = rankOf(spellID, simcRec)
                    elseif sinkCooldowns and (not ready or starved or held or locLocked
                           or (simcRec and SimcGateBlocks(simcRec.gates, resCount, resName, resMax, dialSet))
                           or IsUnusableNonResource(displayID)
                           or IsConfirmedOutOfRange(displayID)
                           or (not alwaysShow and DotTracker
                               and DotTracker.IsDotActiveOnCurrentTarget(displayID))) then
                        -- On cooldown / uncastable / DoT already live on target: sink to
                        -- the back. A DoT un-sinks on cleanse/expiry or inside its pandemic
                        -- refresh window (DotTracker), and a proc still wins (checked above).
                        cooldownCount = cooldownCount + 1
                        cooldownSpells[cooldownCount] = displayID
                    else
                        normalCount = normalCount + 1
                        normalSpells[normalCount] = displayID
                        normalRank[normalCount] = rankOf(spellID, simcRec)
                    end
                else
                    -- Undo claim if filters rejected
                    if displayID then
                        addedSpellIDs[spellID] = nil
                        addedSpellIDs[displayID] = nil
                    end
                end
            end
        end
    end

    -- Procs stay the highest-priority bucket; normal follows; both ordered by context
    -- rank. Cooldown (not-ready) spells trail, unranked.
    spellCount = AppendRankedBucket(proccedSpells, proccedRank, proccedCount, recommendedSpells, spellCount, maxIcons)
    spellCount = AppendRankedBucket(normalSpells, normalRank, normalCount, recommendedSpells, spellCount, maxIcons)
    for i = 1, cooldownCount do
        if spellCount >= maxIcons then break end
        spellCount = spellCount + 1
        recommendedSpells[spellCount] = cooldownSpells[i]
    end
    return spellCount
end

--- Largest icon count any active surface shows - the queue array is built to
--- this cap. The nameplate overlay renders from the same array, so it is sized
--- to whichever surface shows more icons (a lower standard Max Icons must not
--- starve the overlay's independently-configured Max Icons).
function SpellQueue.GetEffectiveMaxIcons(profile)
    local maxIcons = profile.maxIcons or 4
    local npo = profile.nameplateOverlay
    if npo and (profile.displayMode == "overlay" or profile.displayMode == "both") then
        local npoMax = npo.maxIcons or 3
        if npoMax > 7 then npoMax = 7 end
        if npoMax > maxIcons then maxIcons = npoMax end
    end
    return maxIcons
end

--------------------------------------------------------------------------------
-- Build stages. Each takes the pooled build context `b` (SpellQueue._b) and
-- mutates it (b.spellCount in particular). Module-table functions on purpose:
-- the coordinator rides its single SpellQueue upvalue slot, and every stage
-- gets a fresh Lua 5.1 60-upvalue budget (see the compile-limit note above).
--------------------------------------------------------------------------------

--- Clears the situation memory (sticky context + execute latch). Called from
--- the coordinator's OOC visibility early-return so a stale latch never
--- survives into the next fight (evade-reset mobs return at full health).
function SpellQueue._ClearSituationMemory()
    stickyArch, stickyRange, executeLatchGUID = nil, nil, nil
end

--- Stage E - context inference: the AC pick's archetype/range/role/execute
--- tags, enemy-count promotion, sticky/latch temporal smoothing, the
--- out-of-melee probe, and the /jac inspect rank snapshot. Fills b.ctx*.
function SpellQueue._StageContext(b)
    local primarySpellID, inCombat, now = b.primarySpellID, b.inCombat, b.now
    -- Fixed-queue context: bias positions 2+ by the archetype of Blizzard's position-1
    -- pick (the original recommendation, before any gap-closer injection).
    local ctxArch, ctxRange, ctxRole, ctxExecute
    if primarySpellID and SpellDB then
        ctxArch  = SpellDB.GetArch  and SpellDB.GetArch(primarySpellID)
        ctxRange = SpellDB.GetRange and SpellDB.GetRange(primarySpellID)
        ctxRole  = SpellDB.GetRole  and SpellDB.GetRole(primarySpellID)
        ctxExecute = SpellDB.GetGate and SpellDB.GetGate(primarySpellID) == "execute"
    end
    -- Execute phase, DETECTED rather than inferred. The line above only learns of
    -- execute range when AC happens to pick an execute spell; a target-health
    -- threshold gate answers whenever there IS a target, so it leads and the
    -- AC-pick inference becomes the fallback.
    -- 20% deliberately, not 35: every execute-class finisher is live at 20%, so a
    -- hit here can't boost something the player cannot press. The 20-35% window
    -- belongs to Massacre-class talents whose per-spell thresholds we do not have
    -- (DB2 carries no health-threshold column) - and that window is exactly what
    -- the AC-pick fallback still covers, because AC will pick such a spell when it
    -- is live. Direct where it is certain, inference where it is not.
    if not ctxExecute and inCombat and BlizzardAPI.IsUnitHealthBelow
        and UnitExists("target") and UnitCanAttack("player", "target") then
        ctxExecute = BlizzardAPI.IsUnitHealthBelow("target", 20) == true
    end
    -- Direct enemy count (secret-safe, AC-independent): promote the context to
    -- cleave/aoe from the number of enemies actually engaged with us, catching AoE
    -- that a single AC-pick archetype misses. Promote-only - never downgrades AC's
    -- own aoe/cleave read.
    local enemies = (inCombat and BlizzardAPI.GetEngagedEnemyCount
        and BlizzardAPI.GetEngagedEnemyCount()) or 0
    if enemies >= 2 then
        ctxArch = (enemies >= 3 or ctxArch == "aoe") and "aoe" or "cleave"
    end
    -- Wasted-cooldown guard: the one thing still fighting us is nearly dead and is
    -- not a boss, so a multi-minute cooldown spent now is spent on a corpse. Sinks
    -- the spec's own burst triggers in positions 2+ (ContextRank) and silences the
    -- burst-ready cue (Stage G) - it never HIDES anything, so a player who wants it
    -- anyway just presses it.
    -- Every clause must be a POSITIVE read, because each unknown has to leave the
    -- guard off:
    --   * exactly one engaged enemy. 0 means we could not count (nameplates off,
    --     no threat table yet), which must not read as "only one left".
    --   * not a boss. A boss below the threshold is an execute phase, where burning
    --     everything is correct - the opposite call.
    --   * a CONFIRMED below-threshold health gate (== true, never just non-false).
    local ctxDying = false
    if inCombat and enemies == 1 and BlizzardAPI.IsUnitHealthBelow
        and UnitExists("target") and UnitCanAttack("player", "target")
        and not (BlizzardAPI.IsTargetBoss and BlizzardAPI.IsTargetBoss()) then
        ctxDying = BlizzardAPI.IsUnitHealthBelow("target", DYING_TARGET_PCT) == true
    end
    -- Temporal smoothing of the revealed context (see module-state comment):
    -- latch execute per target, hold multi evidence for STICKY_CTX_SECONDS.
    local stickyApplied, executeLatched = false, false
    if inCombat then
        -- UnitGUID("target") is SECRET for NPCs in combat (see DotTracker header);
        -- treat a secret GUID as no-GUID so the latch never compares a secret.
        local targetGUID = UnitGUID("target")
        if targetGUID and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(targetGUID) then
            targetGUID = nil
        end
        if ctxExecute and targetGUID then
            executeLatchGUID = targetGUID
        elseif executeLatchGUID then
            if targetGUID == executeLatchGUID then
                ctxExecute = true
                executeLatched = true
            else
                executeLatchGUID = nil
            end
        end
        if ctxArch == "aoe" or ctxArch == "cleave" then
            stickyArch, stickyRange, stickyTime = ctxArch, ctxRange, now
        elseif stickyArch then
            if now - stickyTime <= STICKY_CTX_SECONDS then
                ctxArch, ctxRange = stickyArch, stickyRange
                stickyApplied = true
            else
                stickyArch, stickyRange = nil, nil
            end
        end
    else
        stickyArch, stickyRange = nil, nil
        executeLatchGUID = nil
    end
    -- Out-of-melee: a REAL range check (IsSpellInRange-based), not inferred from archetype.
    -- True only on a CONFIRMED beyond-5yd read; unknown (no probe / low level) → false →
    -- no demote (fail-safe). Lets us sink uncastable melee spells in positions 2+.
    local ctxOutOfMelee = SpellDB and SpellDB.IsTargetWithin and SpellDB.IsTargetWithin(5) == false
    -- Snapshot for /jac inspect rank.
    lastCtx.pickID = primarySpellID
    lastCtx.arch, lastCtx.range, lastCtx.role = ctxArch, ctxRange, ctxRole
    lastCtx.execute, lastCtx.outOfMelee = ctxExecute or false, ctxOutOfMelee or false
    lastCtx.stickyApplied, lastCtx.executeLatched = stickyApplied, executeLatched
    lastCtx.dying, lastCtx.enemies = ctxDying, enemies
    b.ctxArch, b.ctxRange, b.ctxRole = ctxArch, ctxRange, ctxRole
    b.ctxExecute, b.ctxOutOfMelee, b.ctxDying = ctxExecute, ctxOutOfMelee, ctxDying
end

--- Stage F - tail ordering and assembly: ordering settings, the SimC->AC
--- fallback, pick-revealed buff windows, the healer tail filter, and the
--- categorize/assemble pass over positions 2+.
function SpellQueue._StageTail(b)
    if not cachedRotationList then return end
    local profile, primarySpellID = b.profile, b.primarySpellID
    -- Ordering settings (profile-level; apply to both the custom list and
    -- Blizzard's default rotation): "procs first" off folds procced spells into
    -- the normal bucket (kept in source order); "cooldowns last" off leaves
    -- on-CD spells in their source slot instead of trailing.
    local effectiveBypassProcs = b.bypassProcs or profile.orderProcsFirst == false
    local sinkCooldowns = profile.orderSinkCooldowns ~= false
    -- Context ordering: "off" | "ac" (match Blizzard's pick) | "simc" (theorycraft
    -- priority, the default - falls back to "ac" below when no data for this spec).
    local contextOrder = profile.contextOrder or "simc"
    -- SimC ordering needs data for this spec; otherwise fall back to the AC heuristic.
    local simcCtx = (b.ctxArch == "aoe" and "aoe") or (b.ctxArch == "cleave" and "cleave") or "st"
    if contextOrder == "simc" and not (RotationImport and RotationImport.HasRotation
       and RotationImport.HasRotation()) then
        contextOrder = "ac"
    end
    -- Buff windows the AC pick IMPLIES: AC only recommends a window-gated spell inside its
    -- window, so the pick's positive buff gates reveal those windows are up - readable even
    -- when the buff aura itself is secret (IsBuffWindowActive's aura probe is blind to secret
    -- auras). Siblings sharing a revealed window then promote like a live proc.
    local pickWindows
    if contextOrder == "simc" and RotationImport and RotationImport.GetEntry and primarySpellID then
        local pickRec = RotationImport.GetEntry(primarySpellID, simcCtx)
        if pickRec and pickRec.gates then
            for i = 1, #pickRec.gates do
                local g = pickRec.gates[i]
                if g.t == "buff" and not g.neg and g.id then
                    -- Pooled: wiped on first acquisition each build (stays nil on
                    -- builds with no windows, which downstream checks rely on).
                    if not pickWindows then
                        wipe(pickWindowsBuf)
                        pickWindows = pickWindowsBuf
                    end
                    pickWindows[g.id] = true
                end
            end
        end
    end
    lastCtx.pickWindows = pickWindows   -- for /jac inspect gates
    b.effectiveBypassProcs = effectiveBypassProcs
    b.contextOrder, b.sinkCooldowns = contextOrder, sinkCooldowns
    b.simcCtx, b.pickWindows = simcCtx, pickWindows
    -- Healer specs: heals (and melee-weave entries in caster mode) out of
    -- the DPS tail - see SpellQueue.FilterHealerTail. Position 1 (the AC
    -- pick) is inserted elsewhere and is never filtered.
    local rotationList = SpellQueue.FilterHealerTail(cachedRotationList, profile)
    b.spellCount = CategorizeAndAssembleRotation(rotationList, b)
end

--- Stage G - burst-ready cue: emphasize a burst trigger only when a burst
--- window is actually CALLED FOR - inferred from Blizzard's recommendation
--- system, the only system that can read the secret in-combat context. The
--- signals, per trigger, evaluated against its own SimC burst condition
--- (positive buff-window gates - e.g. Feral's Berserk is gated on Tiger's Fury):
---   1) AC's pick IS the trigger                    -> glow position 1.
---   2) The trigger's window is up: plain self-buff probe, or revealed by the
---      pick's own gates when the aura is secret (pickWindows).
---   3) AC's pick IS the window opener (pick = Tiger's Fury while the trigger
---      needs the TF buff) - the window is about to exist.
--- A trigger whose SimC entry has NO window gate AND is not delegated is a
--- cast-on-cooldown CD by the data (Darkglare, DRW): ready-in-combat is its
--- window, negative gates still veto. A DELEGATED entry without a window gate
--- (Convoke: resource/state conditions we can't read) gets NO readiness cue -
--- its condition lives in state only AC can see, so the only signal left is
--- AC picking it (signal 1). USER-ADDED triggers are the exception: an explicit
--- custom list is intent, so those cue whenever ready (only their own active
--- window vetoes). The cued trigger surfaces at position 2 (promoted or
--- inserted) - never position 1, which stays AC's alone. In-combat only.
--- The wasted-cooldown guard (b.ctxDying) silences the whole stage: "press your
--- big cooldown" is the wrong shout at a lone mob that is about to fall over, and
--- a glow shouting it is more misleading than a tail position.
function SpellQueue._StageBurstCue(b)
    if not (b.inCombat and b.profile.burstCueGlow == true) or b.ctxDying then return end
    local blacklist, recommendedSpells = b.blacklist, b.recommendedSpells
    local addedSpellIDs, primarySpellID = b.addedSpellIDs, b.primarySpellID
    local simcCtx, pickWindows = b.simcCtx, b.pickWindows
    local spellCount, maxIcons = b.spellCount, b.maxIcons
    local triggers, triggerList = ResolveBurstTriggers()
    if triggers and triggerList then
        local pos1 = recommendedSpells[1]
        if pos1 and IsBurstTrigger(triggers, pos1) then
            -- Signal 1: Blizzard says press it. Glow, touch nothing.
            burstCueSpells[pos1] = true
            if primarySpellID and primarySpellID ~= pos1 then
                burstCueSpells[primarySpellID] = true
            end
        else
            local pos1Display = pos1 and BlizzardAPI.GetDisplaySpellID(pos1) or pos1
            for i = 1, #triggerList do
                local tid = triggerList[i]
                local display = BlizzardAPI.GetDisplaySpellID(tid) or tid
                -- Shared reader: any blacklist entry (full or 2+-only) AND an OFF
                -- situational set veto - the cue surfaces at position 2, which all
                -- cover. Reading the table raw here bypassed the set gate, so a
                -- switched-off cooldown was re-inserted the moment it came ready.
                if not SpellQueue.IsSpellBlacklisted(tid, blacklist)
                   and BlizzardAPI.IsSpellAvailable(display)
                   and not BlizzardAPI.IsSpellOnCooldown(display) then
                    local rec = RotationImport and RotationImport.GetEntry
                        and RotationImport.GetEntry(tid, simcCtx)
                    local called = false
                    if cachedBurstSource == "custom" then
                        -- Explicit intent: the user put this spell on the list,
                        -- so ready cues it; only its own running window vetoes.
                        called = not (rec and SimcNegativeBuffBlocks(rec.gates))
                    elseif rec then
                        local gates = rec.gates
                        if HasPositiveBuffGate(gates) then
                            called = (SimcBuffWindowActive(gates)
                                    or GateInPickWindows(gates, pickWindows)
                                    or TriggerWindowOpenerIsPick(gates, primarySpellID, pos1Display))
                                and not SimcNegativeBuffBlocks(gates)
                        elseif not rec.delegated then
                            -- Unconditional by the data: SimC's own line is
                            -- "cast on cooldown".
                            called = not SimcNegativeBuffBlocks(gates)
                        end
                        -- else: delegated with no window gate - condition
                        -- unreadable, wait for AC to pick it (signal 1).
                    end
                    if called then
                        -- Locate in the assembled queue: promote to position 2,
                        -- or insert there when AC's rotation list omits it.
                        local at, atSid
                        for p = 2, spellCount do
                            local s = recommendedSpells[p]
                            if s == display or s == tid then at, atSid = p, s break end
                        end
                        if at then
                            if at > 2 then
                                -- Shift 2..at-1 down one, seat the trigger at 2.
                                for j = at, 3, -1 do
                                    recommendedSpells[j] = recommendedSpells[j - 1]
                                end
                                recommendedSpells[2] = atSid
                            end
                            burstCueSpells[atSid] = true
                        else
                            -- ponytail: on a full queue the last icon falls off -
                            -- the cue outranks the lowest-priority tail slot.
                            local insertAt = (spellCount >= 1) and 2 or 1
                            if spellCount < maxIcons then spellCount = spellCount + 1 end
                            for j = spellCount, insertAt + 1, -1 do
                                recommendedSpells[j] = recommendedSpells[j - 1]
                            end
                            recommendedSpells[insertAt] = display
                            addedSpellIDs[tid] = true
                            addedSpellIDs[display] = true
                            burstCueSpells[display] = true
                        end
                        break
                    end
                end
            end
        end
    end
    b.spellCount = spellCount
end

--- Stage H - finalize: blank-episode bookkeeping, pet-summon dedup, and the
--- copy into lastSpellIDs (the shared return buffer).
function SpellQueue._StageFinalize(b)
    local spellCount, recommendedSpells = b.spellCount, b.recommendedSpells
    -- When Blizzard returns no spells (e.g. target out of range OOC) but
    -- visibility conditions passed, preserve the previous queue so the frame
    -- stays visible with stale icons instead of hiding entirely.
    if spellCount == 0 and #lastSpellIDs == 0 then
        -- Nothing built AND nothing to fall back on: the frame really does go away here.
        SpellQueue.NoteQueueBlank("build produced no spells and no previous queue to hold")
    end
    if spellCount > 0 then
        blankActive = false   -- icons are back: the next blank starts a new episode
        wipe(lastSpellIDs)
        -- Pet summons are ALTERNATIVES, so only the first survives. Every summon you know is
        -- individually non-redundant while you have no pet out, and the per-spell filter is
        -- stateless, so nothing upstream can notice they are the same decision offered three
        -- times (measured: Felguard, Imp and Felhunter queued together on a petless Warlock).
        -- Done here rather than in the filter because "is one already queued" is a property of
        -- the queue, not of the spell. Keeping the FIRST preserves the engine's own pick.
        local haveSummon = false
        for i = 1, spellCount do
            local sid = recommendedSpells[i]
            local isSummon = RedundancyFilter and RedundancyFilter.IsPetSummonSpell
                and RedundancyFilter.IsPetSummonSpell(sid)
            if isSummon and haveSummon then
                -- skip: a second way to solve a problem already solved at position 1
            else
                if isSummon then haveSummon = true end
                lastSpellIDs[#lastSpellIDs + 1] = sid
            end
        end
    end
end

--- Stage D - rotation-source resolution: the cached positions-2+ list (user
--- custom queue or Blizzard's rotation), with the setup skip, Always Show pin
--- resolution, tracking registration, and CD seeding on list change.
function SpellQueue._StageResolveSource(b)
    -- Positions 2+: rotation spells, cached until InvalidateRotationCache().
    -- Custom Queue: if enabled for this spec, use user-defined spell list instead.
    if not cachedRotationList then
        local useCustom = false
        if cachedAddon and cachedAddon.db and cachedAddon.db.profile then
            local cqProfile = cachedAddon.db.profile.customQueue
            local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
            if specKey and cqProfile and cqProfile[specKey]
               and cqProfile[specKey].enabled and cqProfile[specKey].spells
               and #cqProfile[specKey].spells > 0 then
                -- Copy the user's custom spell list as the rotation source.
                -- Variant normalization: a stored ID the player doesn't literally know
                -- (talent swapped away, or an override ID captured under another build)
                -- would silently fail IsSpellAvailable and vanish from the queue.
                -- ResolveKnownSpellID picks the first KNOWN form (stored/override/base);
                -- never write back - the user's stored list stays theirs.
                local cq = cqProfile[specKey]
                cachedRotationList = {}
                for i, sid in ipairs(cq.spells) do
                    if sid and sid > 0 and BlizzardAPI.ResolveKnownSpellID then
                        local known = BlizzardAPI.ResolveKnownSpellID(sid)
                        if known then sid = known end
                    end
                    cachedRotationList[i] = sid
                end
                useCustom = true
            end
        end
        if not useCustom and BlizzardAPI.GetRotationSpells then
            cachedRotationList = BlizzardAPI.GetRotationSpells()
        end
        SpellQueue._rotationIsCustom = useCustom
        -- Setup skip: identical list from the same source with no full invalidation
        -- pending means pins, tracking registrations, and CD seeds are already
        -- correct (see rotationSetupForced above).
        local newList = cachedRotationList
        local sameSetup = newList ~= nil
            and not rotationSetupForced
            and lastSetupUseCustom == useCustom
            and #lastSetupList == #newList
        if sameSetup then
            for i = 1, #newList do
                if lastSetupList[i] ~= newList[i] then sameSetup = false; break end
            end
        end
        if not sameSetup then
        rotationSetupForced = false
        lastSetupUseCustom = useCustom
        wipe(lastSetupList)
        if newList then
            for i = 1, #newList do lastSetupList[i] = newList[i] end
        end
        -- Clear prior rotation registrations; re-registered just below.
        if BlizzardAPI.ClearTrackedRotationSpells then
            BlizzardAPI.ClearTrackedRotationSpells()
        end
        -- Resolve Always Show pins once per list rebuild (cold): the pin lives
        -- on the user's STORED id, but queue entries may be normalized to a
        -- known variant and gap-closer marks carry base+override forms - key
        -- the set by every form so hot-path checks are one table read. The
        -- options setter invalidates this cache on toggle; at worst one build
        -- (0.03-0.05s) sees the previous pin state.
        wipe(pinnedAlwaysShow)
        wipe(maxChargeGated)
        wipe(holdPoints)
        wipe(holdPctVal)
        wipe(holdPctType)
        local pinStore = cachedAddon and cachedAddon.db and cachedAddon.db.profile
            and cachedAddon.db.profile.defensives
            and cachedAddon.db.profile.defensives.spellSettings
        if pinStore then
            -- One pass, two sets: both settings live on the user's STORED id and both
            -- are read per-entry on the hot path, so each resolves to every ID form here.
            local function markForms(set, id, v)
                if v == nil then v = true end
                set[id] = v
                local disp = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(id)
                if disp then set[disp] = v end
                local base = BlizzardAPI.ResolveBaseSpellID and BlizzardAPI.ResolveBaseSpellID(id)
                if base then set[base] = v end
                local known = BlizzardAPI.ResolveKnownSpellID and BlizzardAPI.ResolveKnownSpellID(id)
                if known then set[known] = v end
            end
            for id, ss in pairs(pinStore) do
                if ss and type(id) == "number" and id > 0 then
                    if ss.alwaysShow == true then markForms(pinnedAlwaysShow, id) end
                    -- Hold Until dials apply ONLY while the custom queue is the rotation
                    -- source; a stale key must never demote a spell with no live control
                    -- behind it. Both places that set them - the custom-queue rows and the
                    -- Ability Overrides card - grey out under the same condition.
                    -- (alwaysShow needs no such guard: it only ever adds visibility, so a
                    -- stale one is harmless.)
                    if useCustom then
                        -- holdMode: "charged" | "pts:N" | "pct:N". The legacy
                        -- holdUntilCharged boolean still reads as "charged" so old
                        -- profiles keep working; the dial rewrites it on next touch.
                        local mode = ss.holdMode
                        if mode == nil and ss.holdUntilCharged == true then mode = "charged" end
                        if mode == "charged" then
                            markForms(maxChargeGated, id)
                        elseif type(mode) == "string" then
                            local kind, n = mode:match("^(%a+):(%d+)$")
                            n = tonumber(n)
                            if kind == "pts" and n and n > 0 then
                                markForms(holdPoints, id, n)
                            elseif kind == "pct" and n and n > 0 and n < 100 then
                                -- Gate power type from the spell's own cost row; no
                                -- continuous cost -> dial inert (fail-open).
                                local hk, pt = SpellQueue.GetHoldResource(id)
                                if hk == "pct" and pt then
                                    markForms(holdPctVal, id, n)
                                    markForms(holdPctType, id, pt)
                                end
                            end
                        end
                    end
                end
            end
        end
        if cachedRotationList and BlizzardAPI.RegisterSpellForTracking then
            for i = 1, #cachedRotationList do
                local sid = cachedRotationList[i]
                if sid and sid > 0 then
                    BlizzardAPI.RegisterSpellForTracking(sid, "rotation")
                    local displaySid = BlizzardAPI.GetDisplaySpellID(sid)
                    if displaySid ~= sid then BlizzardAPI.RegisterSpellForTracking(displaySid, "rotation") end
                end
            end
            -- Seed local CD entries for spells already on cooldown at login/spec-change.
            -- Without this, pre-existing CDs have no UNIT_SPELLCAST_SUCCEEDED event,
            -- so IsSpellReady fails-open for unflagged spells. OOC-only (safe to call always).
            if BlizzardAPI.SeedLocalCooldownIfActive then
                for i = 1, #cachedRotationList do
                    local sid = cachedRotationList[i]
                    if sid and sid > 0 then
                        BlizzardAPI.SeedLocalCooldownIfActive(sid)
                        local displaySid = BlizzardAPI.GetDisplaySpellID(sid)
                        if displaySid ~= sid then BlizzardAPI.SeedLocalCooldownIfActive(displaySid) end
                    end
                end
            end
        end
        end  -- if not sameSetup
    end
end

--- Stage B - gap-closer injection: promote a gap closer to position 1 when the
--- target is out of melee range, and suppress gap closers from the rotation
--- tail (a user's Always Show pin beats the suppression).
function SpellQueue._StageGapCloser(b)
    -- Resolve late-bound engine refs here, the first per-build user (they load
    -- after SpellQueue in the TOC; resolved once, then cached). Stage D's
    -- custom-queue lookup relies on cachedAddon being resolved by this point.
    if not cachedAddon then cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
    if not cachedGapCloserEngine then cachedGapCloserEngine = LibStub("JustAC-GapCloserEngine", true) end
    if b.spellCount >= b.maxIcons then return end
    if not (cachedGapCloserEngine and cachedGapCloserEngine.GetGapCloserSpell and cachedAddon) then return end
    local spellCount = b.spellCount
    local recommendedSpells, addedSpellIDs = b.recommendedSpells, b.addedSpellIDs
    local primarySpellID = b.primarySpellID

    local pos1Display = recommendedSpells[1]
    local pos1IsGapCloser = false
    if cachedGapCloserEngine.IsGapCloserSpell then
        -- My List Leads: the AC pick is adviser-only and NOT at slot 1, so it must
        -- not suppress our injection - AC picks the gap closer exactly when the
        -- target is out of range, which is exactly when the slot needs filling.
        pos1IsGapCloser = (not b.myListLeads and primarySpellID
                and cachedGapCloserEngine.IsGapCloserSpell(cachedAddon, primarySpellID))
            or (pos1Display and pos1Display ~= primarySpellID and cachedGapCloserEngine.IsGapCloserSpell(cachedAddon, pos1Display))
    end

    if not pos1IsGapCloser then
        local gcSpell, gcBase = cachedGapCloserEngine.GetGapCloserSpell(cachedAddon, addedSpellIDs)
        if gcSpell then
            local gcDisplay = BlizzardAPI.GetDisplaySpellID(gcSpell)
            -- The wait sentinel rides this shift to position 2 ON PURPOSE: the gap
            -- closer takes slot 1 (it is the actionable move), while the wait icon
            -- stays visible so the player still sees the assist wants to wait.
            if spellCount >= 1 then
                if pos1Display then displacedPrimary[pos1Display] = true end
                if primarySpellID and primarySpellID ~= pos1Display then
                    displacedPrimary[primarySpellID] = true
                end
                for i = spellCount, 1, -1 do
                    recommendedSpells[i + 1] = recommendedSpells[i]
                end
            end
            recommendedSpells[1] = gcSpell
            spellCount = spellCount + 1
            addedSpellIDs[gcSpell] = true
            addedSpellIDs[gcDisplay] = true
            if gcBase and gcBase ~= gcSpell then
                addedSpellIDs[gcBase] = true
            end
            syntheticProcs[gcSpell] = true
            syntheticProcs[gcDisplay] = true
        end
    end

    -- Suppress gap-closers from rotation list - our injection controls placement.
    -- (MarkGapCloserSpellIDs is a no-op while gap-closers are disabled.) Marks go
    -- through a scratch set so a user's Always Show pin can beat the suppression:
    -- a pinned gap-closer stays visible in the queue AND still injects at slot 1
    -- when the target leaves melee range. pinnedAlwaysShow carries every ID form,
    -- so this is a pure table read per marked spell.
    if cachedGapCloserEngine.MarkGapCloserSpellIDs then
        wipe(gcSuppressScratch)
        cachedGapCloserEngine.MarkGapCloserSpellIDs(cachedAddon, gcSuppressScratch)
        for sid in pairs(gcSuppressScratch) do
            if not pinnedAlwaysShow[sid] then
                addedSpellIDs[sid] = true
            end
        end
    end

    b.spellCount = spellCount
end

--- Stage A - position 1: the spread-DoT signal, stale local-CD expiry, and
--- Blizzard's primary pick inserted with caster/blacklist awareness plus the
--- highlight-lookahead fallback.
function SpellQueue._StagePrimary(b)
    local profile, primarySpellID = b.profile, b.primarySpellID
    local blacklist, addedSpellIDs = b.blacklist, b.addedSpellIDs
    local recommendedSpells = b.recommendedSpells

    -- "My List Leads" (experimental): the custom list owns slot 1 as well. The AC
    -- pick is still FETCHED and threaded through the build - context inference,
    -- burst-cue signals, and the stale-CD oracle keep consuming it - it just stops
    -- being displayed or claiming a slot, so the first eligible list entry
    -- surfaces at position 1. The wait sentinel is skipped with it: with the list
    -- leading there is always a next-best suggestion to show. The dot-spread
    -- arrow is a slot-1-is-AC concept, so it sleeps in this mode too.
    local myListLeads
    do
        local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
        local cq = specKey and profile.customQueue and profile.customQueue[specKey]
        myListLeads = (cq and cq.enabled and cq.myListLeads == true
            and cq.spells and #cq.spells > 0) and true or false
    end
    b.myListLeads = myListLeads

    -- Spread-DoT signal: AC re-recommends a maintained DoT that's already live on
    -- the current target (outside its refresh window), which means it wants the DoT
    -- on OTHER targets. IsDotActiveOnCurrentTarget returns false during the pandemic
    -- window, so a genuine refresh-this-target pick does not trigger the arrow.
    dotSpreadActive = false
    if not myListLeads and profile.showDotSpreadArrow == true and primarySpellID and primarySpellID > 0
       and DotTracker and DotTracker.IsDotActiveOnCurrentTarget
       and SpellDB and SpellDB.IsTargetDot then
        local pd = BlizzardAPI.GetDisplaySpellID(primarySpellID)
        if (SpellDB.IsTargetDot(primarySpellID) or SpellDB.IsTargetDot(pd))
           and DotTracker.IsDotActiveOnCurrentTarget(pd) then
            dotSpreadActive = true
        end
    end

    -- AC never recommends an uncastable spell: expire any stale local CD/charge
    -- entry (an unobserved proc-driven reset/refund leaves one behind) so it
    -- can't keep sinking this spell in later builds.
    if primarySpellID and primarySpellID > 0 and BlizzardAPI.NoteSpellRecommended then
        BlizzardAPI.NoteSpellRecommended(primarySpellID)
        local primaryDisplay = BlizzardAPI.GetDisplaySpellID(primarySpellID)
        if primaryDisplay ~= primarySpellID then
            BlizzardAPI.NoteSpellRecommended(primaryDisplay)
        end
    end

    if myListLeads then
        -- Slot 1 belongs to the list (or the gap-closer injection); the AC pick
        -- was consumed above as adviser and is deliberately not inserted.
        local _ = nil
    elseif primarySpellID and primarySpellID > 0 then
        -- Caster filler treats a melee/form pick like a blacklisted one: the
        -- highlight lookahead below supplies AC's next-best suggestion.
        local casterSuppressed = SpellQueue.IsCasterSuppressedPick(primarySpellID, profile)
        local displaySpellID = ClaimSpellID(primarySpellID, addedSpellIDs)
        if displaySpellID
           and not casterSuppressed
           and not SpellQueue.IsSpellBlacklisted(primarySpellID, blacklist, true) then
            b.spellCount = b.spellCount + 1
            recommendedSpells[b.spellCount] = displaySpellID
        else
            -- Undo claim if blacklisted
            if displaySpellID then
                addedSpellIDs[primarySpellID] = nil
                addedSpellIDs[displaySpellID] = nil
            end
            -- Highlight-mode lookahead: if the blacklisted spell is hidden from
            -- action bars (removed or behind a modifier macro), Blizzard's
            -- visible-button-only mode may return the next rotation spell instead.
            if BlizzardAPI.GetHighlightCastSpell then
                local hlSpellID = BlizzardAPI.GetHighlightCastSpell()
                if hlSpellID and hlSpellID > 0
                   and hlSpellID ~= primarySpellID
                   and not SpellQueue.IsCasterSuppressedPick(hlSpellID, profile)
                   and not SpellQueue.IsSpellBlacklisted(hlSpellID, blacklist, true) then
                    local hlDisplay = ClaimSpellID(hlSpellID, addedSpellIDs)
                    if hlDisplay then
                        b.spellCount = b.spellCount + 1
                        recommendedSpells[b.spellCount] = hlDisplay
                    end
                end
            end
        end
    else
        -- WAIT: the assist is running but deliberately recommends nothing - the engine
        -- shows the watch icon on its own button and GetNextCastSpell answers nil.
        -- Slot 1 is BLIZZARD'S SLOT: without this reservation the ranked tail shifted
        -- up one and our own pick wore the primary glow (user-reported: base Moonfire
        -- surfacing on a Feral during wait - known to every druid, uncastable in form).
        -- Combat-gated: out of combat a nil pick legitimately means "no demand", and
        -- the precombat/tail content owns the queue as it always has.
        if b.inCombat and BlizzardAPI.IsAssistedCombatAvailable
           and BlizzardAPI.IsAssistedCombatAvailable() then
            b.spellCount = 1
            b.recommendedSpells[1] = SpellQueue.WAIT_SENTINEL
        end
    end
end

function SpellQueue.GetCurrentSpellQueue()
    local profile = BlizzardAPI.GetProfile()
    if not profile or profile.isManualMode then
        return lastSpellIDs or {}
    end

    -- Channel-hold: while channeling, the current suggestion IS being executed - rebuilding
    -- mid-channel only flickers the queue as the engine's pick churns. Freeze CONTENT here,
    -- at the single source every caller shares, so rendering keeps running and the channel
    -- grey-out/fill actually paints. (This hold used to live in the main loop, where it
    -- skipped the whole render pass - the channeled spell then still LOOKED available.)
    -- Own-channel info is plain in combat (validated 2026-07-24).
    if BlizzardAPI.IsPlayerChanneling and BlizzardAPI.IsPlayerChanneling() then
        return lastSpellIDs or {}
    end

    local now = GetTime()
    -- Compute inCombat once; reused for both the throttle interval and all visibility checks below.
    -- Internal safety throttle - main loop in JustAC.lua is the primary rate limiter
    -- (CVar-driven, min 0.03s).  These match the main loop's minimum intervals so
    -- SpellQueue never bottlenecks the caller.
    local inCombat = UnitAffectingCombat("player")
    local throttleInterval = inCombat and 0.03 or 0.05

    if now - lastQueueUpdate < throttleInterval then
        return lastSpellIDs or {}
    end
    
    local queueVisible, hiddenReason = EvaluateQueueVisibility(profile, inCombat)
    if not queueVisible then
        if #lastSpellIDs > 0 then SpellQueue.NoteQueueBlank(hiddenReason) end
        lastShouldShowQueue = false
        lastQueueUpdate = now
        -- Clear situation memory here too: with combat-only visibility this early
        -- return is the only path that runs OOC.
        if not inCombat then
            SpellQueue._ClearSituationMemory()
        end
        wipe(lastSpellIDs)
        return lastSpellIDs
    end

    -- All visibility conditions passed: queue should be shown.
    lastShouldShowQueue = true
    lastQueueUpdate = now
    if profile.debugMode then
        if spellQueueBuildCount == 0 then
            spellQueueResetTime = now
        end
        spellQueueBuildCount = spellQueueBuildCount + 1
    end

    wipe(filterResultCache)
    wipe(rotationFilterCache)
    if BlizzardAPI.ClearProcCache then BlizzardAPI.ClearProcCache() end

    local bypassProcs = BlizzardAPI.IsProcFeatureAvailable
        and not BlizzardAPI.IsProcFeatureAvailable() or false
    local blacklist = GetBlacklistTable()

    wipe(recommendedSpells)
    wipe(addedSpellIDs)
    wipe(syntheticProcs)
    wipe(displacedPrimary)
    wipe(burstCueSpells)
    wipe(cooldownSpells)
    local maxIcons = SpellQueue.GetEffectiveMaxIcons(profile)
    local hideItems = profile.hideItemAbilities

    -- Per-build context: pooled, wiped, threaded through the build stages.
    -- Stages read their inputs from b and mutate it (b.spellCount especially).
    local b = SpellQueue._b
    wipe(b)
    b.profile, b.blacklist, b.inCombat, b.now = profile, blacklist, inCombat, now
    b.addedSpellIDs, b.recommendedSpells = addedSpellIDs, recommendedSpells
    b.maxIcons, b.hideItems, b.bypassProcs = maxIcons, hideItems, bypassProcs
    b.spellCount = 0

    -- Position 1: Blizzard's primary suggestion. A full blacklist entry hides it here too
    -- (which can stall Blizzard's dynamic recommendation); a 2+-only entry is exempt at
    -- position 1 (isPrimary=true) so the rotation keeps advancing.
    b.primarySpellID = BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()

    SpellQueue._StagePrimary(b)        -- A: spread-DoT signal, stale-CD expiry, position-1 insert
    SpellQueue._StageGapCloser(b)      -- B: gap-closer injection + rotation suppression marks
    if profile.showSpellbookProcs then -- C: spellbook proc injection
        b.spellCount = AddSpellbookProcs(b)
    end
    SpellQueue._StageResolveSource(b)  -- D: rotation source (fills cachedRotationList)
    SpellQueue._StageContext(b)        -- E: context inference (fills b.ctx*)
    SpellQueue._StageTail(b)           -- F: tail ordering + assembly over positions 2+
    SpellQueue._StageBurstCue(b)       -- G: burst-ready cue at position 2
    SpellQueue._StageFinalize(b)       -- H: blank bookkeeping, dedup, copy-out
    return lastSpellIDs
end

function SpellQueue.ForceUpdate()
    lastQueueUpdate = 0
end

--- Cached visibility verdict from last queue build - avoids re-evaluating per render frame.
function SpellQueue.ShouldShowQueue()
    return lastShouldShowQueue
end

--- True when the position-1 pick is a DoT already live on the target (spread cue).
--- UIRenderer shows the "switch target" arrow on slot 1 when this is set.
function SpellQueue.IsDotSpreadActive()
    return dotSpreadActive
end

--- Last build's context (post latch/sticky). Diagnostic only (/jac inspect rank).
function SpellQueue.DebugContextState()
    return lastCtx
end

--- Rank a spell against the last build's context. Diagnostic only (/jac inspect rank).
function SpellQueue.DebugRankSpell(spellID)
    return ContextRank(spellID, lastCtx.arch, lastCtx.range, lastCtx.role, lastCtx.execute,
        lastCtx.outOfMelee, lastCtx.dying)
end

--- Returns true if spellID was injected as a synthetic proc (gap-closer, etc.)
--- by the most recent GetCurrentSpellQueue() call.
function SpellQueue.IsSyntheticProc(spellID)
    return syntheticProcs[spellID] == true
end

--- Returns true if spellID carries the burst-ready cue (trigger off cooldown,
--- visible in the queue) as of the most recent GetCurrentSpellQueue().
function SpellQueue.IsBurstCue(spellID)
    return burstCueSpells[spellID] == true
end

--- Effective burst-trigger list and its source ("custom" | "simc" | "curated").
--- Options panel + /jac inspect burst.
function SpellQueue.GetBurstTriggerInfo()
    local _, list = ResolveBurstTriggers()
    return list, cachedBurstSource
end

--- Wipe the trigger cache (user edited overrides, profile switched).
function SpellQueue.InvalidateBurstTriggers()
    cachedBurstTriggers = nil
end

--- Returns true if spellID was displaced from position 1 to position 2 by a
--- gap-closer injection in the most recent GetCurrentSpellQueue() call.
--- UIRenderer uses this to keep the blue assisted glow on the displaced spell.
function SpellQueue.IsDisplacedPrimary(spellID)
    return displacedPrimary[spellID] == true
end

--- Returns true if spellID is ANY known gap-closer for the current spec
--- (regardless of whether it was injected by our system this frame).
--- Diagnostic-only: renderers resolve the engine directly; the sole caller
--- is the /jac inspect path.
function SpellQueue.IsGapCloserSpell(spellID)
    if not cachedGapCloserEngine or not cachedGapCloserEngine.IsGapCloserSpell then
        if not cachedGapCloserEngine then
            cachedGapCloserEngine = LibStub("JustAC-GapCloserEngine", true)
        end
        if not cachedGapCloserEngine or not cachedGapCloserEngine.IsGapCloserSpell then
            return false
        end
    end
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedGapCloserEngine.IsGapCloserSpell(cachedAddon, spellID)
end

function SpellQueue.OnSpecChange()
    -- Eagerly resolve late-bound refs; by spec-change time all engines are loaded.
    if not cachedAddon then cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
    if not cachedGapCloserEngine then cachedGapCloserEngine = LibStub("JustAC-GapCloserEngine", true) end
    isHealerSpec = nil   -- recomputed lazily on the next build
    BlizzardAPI.ClearSpellCache()
    SpellQueue.ForceUpdate()
end

function SpellQueue.OnSpellsChanged()
    BlizzardAPI.ClearSpellCache()
    SpellQueue.InvalidateRotationCache()
    -- Power costs are talent-dependent; re-derive spender verdicts.
    wipe(spenderCache)
    -- Burst-cue trigger set bakes in talent-resolved IDs; rebuild on talent change.
    cachedBurstTriggers = nil
    -- SimC rank lookup bakes in talent-dependent override resolution. Invalidate
    -- HERE (SPELLS_CHANGED fires on every talent change) and not in
    -- InvalidateRotationCache, which also fires on every target swap and would
    -- force a full lookup rebuild per target change for no reason.
    if RotationImport and RotationImport.InvalidateLookup then
        RotationImport.InvalidateLookup()
    end
    SpellQueue.ForceUpdate()
end

-- Invalidate the cached rotation list - called on RotationSpellsUpdated, SPELLS_CHANGED,
-- options changes, and (with keepSetupIfUnchanged) every target swap. The next build
-- re-fetches the list; tracking registrations are cleared and rebuilt inside the cold
-- rebuild's setup branch, which is skipped entirely when the refetched list is
-- unchanged and no full invalidation is pending.
function SpellQueue.InvalidateRotationCache(keepSetupIfUnchanged)
    cachedRotationList = nil
    if not keepSetupIfUnchanged then
        rotationSetupForced = true
    end
end

function SpellQueue.GetBuildStats()
    return {
        buildCount = spellQueueBuildCount,
        resetTime = spellQueueResetTime,
    }
end

function SpellQueue.ResetBuildStats()
    spellQueueBuildCount = 0
    spellQueueResetTime = GetTime()
end

