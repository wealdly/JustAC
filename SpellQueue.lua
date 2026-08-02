-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Queue Module - Retrieves and caches the current Assisted Combat rotation
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 43)
if not SpellQueue then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local DotTracker = LibStub("JustAC-DotTracker", true)

-- Hot path cache
local GetTime = GetTime
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
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
-- True when Blizzard's position-1 pick is a maintained DoT that is already live on
-- the current target (and not in its refresh window) - i.e. AC wants it applied
-- ELSEWHERE, so the renderer shows a "switch target" arrow on the slot. Recomputed
-- each build; read by UIRenderer via IsDotSpreadActive().
local dotSpreadActive = false

-- Lazy-resolved references for gap-closer and burst injection (load after SpellQueue in TOC)
local cachedGapCloserEngine = nil
local cachedBurstEngine = nil
local cachedAddon = nil

-- Build counters (for /jac perf diagnostic)
local spellQueueBuildCount = 0
local spellQueueResetTime = GetTime()

-- Spells injected by JustAC systems (gap-closers, etc.) that should always show proc glow.
-- Populated per queue build, consumed by UIRenderer.IsSpellProcced.
local syntheticProcs = {}

-- Spells displaced from position 1 to position 2 by a gap-closer/burst injection.
-- These were Blizzard's primary recommendation; they keep the blue assisted glow
-- at their new position so the player knows they're still the next cast after closing.
local displacedPrimary = {}

-- Spells injected by the burst injection system.  Separate from syntheticProcs
-- so UIRenderer can apply a distinct purple glow instead of the gap-closer magenta.
local burstInjectedSpells = {}

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
-- Parallel context-rank buffers for the fixed-queue archetype/range bias.
local proccedRank = {}
local normalRank = {}

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

function SpellQueue.ClearSpellCache()
    if BlizzardAPI and BlizzardAPI.ClearSpellCache then
        BlizzardAPI.ClearSpellCache()
    end
end

function SpellQueue.ClearAvailabilityCache()
    if BlizzardAPI and BlizzardAPI.ClearAvailabilityCache then
        BlizzardAPI.ClearAvailabilityCache()
    end
end

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

-- Checks both base ID and its display/override ID against the blacklist.
-- isPrimary: true when testing Blizzard's position-1 pick (exempts 2+-only entries).
function SpellQueue.IsSpellBlacklisted(spellID, blacklist, isPrimary)
    if not spellID then return false end
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
-- Usability (C_Spell.IsSpellUsable) is NeverSecret; includes resource + CD check.
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

-- Per-spell "Hold Until Charged" opt-in (Custom Queue row toggle). True while the
-- ability is short of full charges - the caller sinks it to the back of the queue
-- (never drops it), so a charge ability isn't pushed at 1/2 and spent into an
-- overcap, but stays visible while it banks. For a spell without charges this
-- degrades to "sink while on cooldown", which is the same intent and matches what
-- the cooldown sink already does. Both reads are non-secret local tracking, so
-- this is safe to branch on in combat.
-- `ready` is passed in because the caller has already computed it for this spell in the
-- same iteration; re-querying would double the readiness work on every build.
local function HeldUntilCharged(spellID, displayID, ready)
    if not (maxChargeGated[spellID] or maxChargeGated[displayID]) then return false end
    return not (ready and BlizzardAPI.IsSpellAtMaxCharges(displayID))
end

-- shared with /jac why: report the same sink verdict the build used. Resolves readiness
-- itself (the diagnostic has no per-iteration value to hand in) and answers false for any
-- spell that isn't gated, so callers can print a reason only when it fires.
function SpellQueue.IsHeldUntilCharged(spellID)
    if not spellID then return false end
    local displayID = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID) or spellID
    return HeldUntilCharged(spellID, displayID, BlizzardAPI.IsSpellReady(displayID))
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
    local queueVis = profile.queueVisibility
    if not queueVis then
        if profile.hideQueueOutOfCombat then
            queueVis = "combatOnly"
        elseif profile.requireHostileTarget then
            queueVis = "requireHostile"
        else
            queueVis = "always"
        end
    end

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
local function AddSpellbookProcs(profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems)
    local spellbookProcs = ActionBarScanner and ActionBarScanner.GetSpellbookProccedSpells and ActionBarScanner.GetSpellbookProccedSpells()
    if not spellbookProcs then return spellCount end

    for _, procSpellID in ipairs(spellbookProcs) do
        if spellCount >= maxIcons then break end
        if procSpellID and not addedSpellIDs[procSpellID] then
            local displayID = ClaimSpellID(procSpellID, addedSpellIDs)
            if displayID
               and BlizzardAPI.IsOffensiveSpell(procSpellID)
               and ActionBarScanner.HasKeybind(procSpellID)
               and not SpellQueue.IsSpellBlacklisted(procSpellID, blacklist)
               and not (hideItems and BlizzardAPI.IsItemSpell(procSpellID))
               and PassesSpellFilters(procSpellID, profile) then
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
local function ContextRank(spellID, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee)
    if ctxExecute and SpellDB and SpellDB.GetGate and SpellDB.GetGate(spellID) == "execute" then
        return 0
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
    if not C_Spell_IsSpellInRange then return false end
    local r = C_Spell_IsSpellInRange(spellID, "target")
    if r == nil or (BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(r)) then
        return false
    end
    return r == false
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
local function IsSpenderSpell(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return false end
    for i = 1, #costs do
        local c = costs[i]
        local amt = c and c.cost
        if type(amt) == "number" and not (issecretvalue and issecretvalue(amt)) and amt > 0 then
            return true
        end
    end
    return false
end

local function SimcResourceGateBlocks(gates, resCount, resName)
    if not gates or not resCount then return false end
    for i = 1, #gates do
        local g = gates[i]
        if g.t == "resource" and g.res == resName and g.op and g.n then
            local ok
            if     g.op == ">=" then ok = resCount >= g.n
            elseif g.op == "<=" then ok = resCount <= g.n
            elseif g.op == ">"  then ok = resCount >  g.n
            elseif g.op == "<"  then ok = resCount <  g.n
            elseif g.op == "="  then ok = resCount == g.n
            elseif g.op == "!=" then ok = resCount ~= g.n
            end
            if ok == false then return true end
        end
    end
    return false
end

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

local function CategorizeAndAssembleRotation(rotationList, profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems, bypassProcs, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee, contextOrder, sinkCooldowns, simcCtx, pickWindows)
    wipe(proccedSpells)
    wipe(normalSpells)
    wipe(proccedRank)
    wipe(normalRank)
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
    local resCount, resName
    if simcMode and BlizzardAPI.GetClassResourcePoints then
        local c, _, r = BlizzardAPI.GetClassResourcePoints()
        resCount, resName = c, r
    end
    -- Primary resource capped (engine full-power pulse, plain - validated in combat
    -- 2026-07-24): promote ready, affordable spenders so regen stops going to waste.
    -- Read once per build; false for power types without a full-power animation.
    local powerCapped = BlizzardAPI.IsPrimaryPowerCapped and BlizzardAPI.IsPrimaryPowerCapped()
    local function rankOf(spellID, simcRec)
        if simcMode then
            local ctx = ContextRank(spellID, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee)
            local simc = (simcRec and simcRec.rank) or SIMC_UNRANKED
            if simc > SIMC_UNRANKED then simc = SIMC_UNRANKED end
            return ctx * CONTEXT_STRIDE + simc
        elseif contextOrder == "ac" then
            return ContextRank(spellID, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee)
        end
        return 1
    end

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
                    -- "Hold Until Charged": treat a part-charged ability exactly like one
                    -- that isn't ready - sink it, never drop it. It keeps its place in the
                    -- queue rather than being filtered out, though like anything in the
                    -- cooldown tail it can fall past maxIcons and off screen on a full queue.
                    -- Gated on sinkCooldowns so the whole feature is genuinely inert when
                    -- "Unavailable last" is off, which is what the option's tooltip promises -
                    -- otherwise it would still strip proc promotion below and quietly reorder.
                    local held = sinkCooldowns and HeldUntilCharged(spellID, displayID, ready)
                    local simcRec = (simcMode and RotationImport and RotationImport.GetEntry)
                        and RotationImport.GetEntry(spellID, simcCtx) or nil
                    -- Resource-gated (delegated) SimC entries are spenders: sink them when
                    -- you can't afford them right now (IsSpellUsable's insufficientPower is
                    -- NeverSecret), so builders surface while you're starved and the spender
                    -- rises once you can pay for it. Fail-safe - only sink on a definite "no".
                    local starved = false
                    if simcRec and simcRec.delegated then
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
                    -- their ordering.
                    local chargeCapped = not locLocked and BlizzardAPI.IsSpellChargeCapped
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
                                and not SimcResourceGateBlocks(simcRec.gates, resCount, resName)))
                       and ProcPriorityEnabled(spellID, profile) then
                        proccedCount = proccedCount + 1
                        proccedSpells[proccedCount] = displayID
                        proccedRank[proccedCount] = rankOf(spellID, simcRec)
                    elseif sinkCooldowns and (not ready or starved or held or locLocked
                           or (simcRec and SimcResourceGateBlocks(simcRec.gates, resCount, resName))
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
        -- return is the only path that runs OOC, and a stale execute latch must not
        -- survive into the next fight (evade-reset mobs return at full health).
        if not inCombat then
            stickyArch, stickyRange, executeLatchGUID = nil, nil, nil
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
    wipe(burstInjectedSpells)
    wipe(cooldownSpells)
    local maxIcons = SpellQueue.GetEffectiveMaxIcons(profile)
    local spellCount = 0
    local hideItems = profile.hideItemAbilities

    -- Resolve late-bound engine refs (load after SpellQueue in TOC; resolved once, then cached).
    if not cachedAddon then cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true) end
    if not cachedGapCloserEngine then cachedGapCloserEngine = LibStub("JustAC-GapCloserEngine", true) end
    if not cachedBurstEngine then cachedBurstEngine = LibStub("JustAC-BurstInjectionEngine", true) end

    -- Position 1: Blizzard's primary suggestion. A full blacklist entry hides it here too
    -- (which can stall Blizzard's dynamic recommendation); a 2+-only entry is exempt at
    -- position 1 (isPrimary=true) so the rotation keeps advancing.
    local primarySpellID = BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()

    -- Spread-DoT signal: AC re-recommends a maintained DoT that's already live on
    -- the current target (outside its refresh window), which means it wants the DoT
    -- on OTHER targets. IsDotActiveOnCurrentTarget returns false during the pandemic
    -- window, so a genuine refresh-this-target pick does not trigger the arrow.
    dotSpreadActive = false
    if profile.showDotSpreadArrow == true and primarySpellID and primarySpellID > 0
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

    if primarySpellID and primarySpellID > 0 then
        local displaySpellID = ClaimSpellID(primarySpellID, addedSpellIDs)
        if displaySpellID
           and not SpellQueue.IsSpellBlacklisted(primarySpellID, blacklist, true) then
            spellCount = spellCount + 1
            recommendedSpells[spellCount] = displaySpellID
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
                   and not SpellQueue.IsSpellBlacklisted(hlSpellID, blacklist, true) then
                    local hlDisplay = ClaimSpellID(hlSpellID, addedSpellIDs)
                    if hlDisplay then
                        spellCount = spellCount + 1
                        recommendedSpells[spellCount] = hlDisplay
                    end
                end
            end
        end
    end

    -- Gap-closer injection: promote to position 1 when target is out of melee range.
    if spellCount < maxIcons then
        if cachedGapCloserEngine and cachedGapCloserEngine.GetGapCloserSpell and cachedAddon then
            local pos1Display = recommendedSpells[1]
            local pos1IsGapCloser = false
            if cachedGapCloserEngine.IsGapCloserSpell then
                pos1IsGapCloser = (primarySpellID and cachedGapCloserEngine.IsGapCloserSpell(cachedAddon, primarySpellID))
                    or (pos1Display and pos1Display ~= primarySpellID and cachedGapCloserEngine.IsGapCloserSpell(cachedAddon, pos1Display))
            end

            if not pos1IsGapCloser then
                local gcSpell, gcBase = cachedGapCloserEngine.GetGapCloserSpell(cachedAddon, addedSpellIDs)
                if gcSpell then
                    local gcDisplay = BlizzardAPI.GetDisplaySpellID(gcSpell)
                    if spellCount >= 1 then
                        if pos1Display then displacedPrimary[pos1Display] = true end
                        if primarySpellID and primarySpellID ~= pos1Display then
                            displacedPrimary[primarySpellID] = true
                        end
                        for i = spellCount, 1, -1 do
                            recommendedSpells[i + 1] = recommendedSpells[i]
                        end
                        recommendedSpells[1] = gcSpell
                    else
                        recommendedSpells[1] = gcSpell
                    end
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
        end
    end

    -- Burst injection: inject priority spell at position 1 when burst window is active.
    -- Two-phase: "pending" = trigger CD at pos 1 (glow only, no injection),
    --            "active"  = trigger aura on player (inject from injection list).
    if spellCount < maxIcons then
        if cachedBurstEngine and cachedBurstEngine.CheckTrigger and cachedAddon then
            local burstPhase, triggerPosition = cachedBurstEngine.CheckTrigger(cachedAddon, primarySpellID, recommendedSpells)
            -- Phase "pending": trigger CD is visible in the queue. Mark it as burst so
            -- renderers can show the burst glow (signal to press it), but don't
            -- inject anything - let Blizzard's recommendation stand.
            if burstPhase == "pending" and triggerPosition and spellCount >= triggerPosition then
                local triggerDisplay = recommendedSpells[triggerPosition]
                if triggerDisplay then
                    burstInjectedSpells[triggerDisplay] = true
                end
                -- Also mark underlying spell ID if different from display (talent overrides)
                if triggerPosition == 1 and primarySpellID and primarySpellID ~= triggerDisplay then
                    burstInjectedSpells[primarySpellID] = true
                end
            end
            -- Phase "active": trigger aura is on the player. Inject from injection list.
            if burstPhase == "active" then
                local biSpell, biBase = cachedBurstEngine.GetBurstInjectionSpell(cachedAddon, addedSpellIDs)
                if biSpell then
                    local biDisplay = BlizzardAPI.GetDisplaySpellID(biSpell)
                    if spellCount >= 1 then
                        local pos1Display = recommendedSpells[1]
                        if pos1Display then displacedPrimary[pos1Display] = true end
                        if primarySpellID and primarySpellID ~= pos1Display then
                            displacedPrimary[primarySpellID] = true
                        end
                        for i = spellCount, 1, -1 do
                            recommendedSpells[i + 1] = recommendedSpells[i]
                        end
                        recommendedSpells[1] = biSpell
                    else
                        recommendedSpells[1] = biSpell
                    end
                    spellCount = spellCount + 1
                    addedSpellIDs[biSpell] = true
                    addedSpellIDs[biDisplay] = true
                    if biBase and biBase ~= biSpell then
                        addedSpellIDs[biBase] = true
                    end
                    burstInjectedSpells[biSpell] = true
                    burstInjectedSpells[biDisplay] = true

                    -- Suppress burst injection spells from rotation list - only when
                    -- we actually injected one, so they show normally when all on CD.
                    if cachedBurstEngine.MarkBurstInjectionSpellIDs then
                        cachedBurstEngine.MarkBurstInjectionSpellIDs(cachedAddon, addedSpellIDs)
                    end
                end
            end
        end
    end

    if profile.showSpellbookProcs then
        spellCount = AddSpellbookProcs(profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems)
    end

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
        -- Resolve Always Show pins once per list rebuild (cold): the pin lives
        -- on the user's STORED id, but queue entries may be normalized to a
        -- known variant and gap-closer marks carry base+override forms - key
        -- the set by every form so hot-path checks are one table read. The
        -- options setter invalidates this cache on toggle; at worst one build
        -- (0.03-0.05s) sees the previous pin state.
        wipe(pinnedAlwaysShow)
        wipe(maxChargeGated)
        local pinStore = cachedAddon and cachedAddon.db and cachedAddon.db.profile
            and cachedAddon.db.profile.defensives
            and cachedAddon.db.profile.defensives.spellSettings
        if pinStore then
            -- One pass, two sets: both settings live on the user's STORED id and both
            -- are read per-entry on the hot path, so each resolves to every ID form here.
            local function markForms(set, id)
                set[id] = true
                local disp = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(id)
                if disp then set[disp] = true end
                local base = BlizzardAPI.ResolveBaseSpellID and BlizzardAPI.ResolveBaseSpellID(id)
                if base then set[base] = true end
                local known = BlizzardAPI.ResolveKnownSpellID and BlizzardAPI.ResolveKnownSpellID(id)
                if known then set[known] = true end
            end
            for id, ss in pairs(pinStore) do
                if ss and type(id) == "number" and id > 0 then
                    if ss.alwaysShow == true then markForms(pinnedAlwaysShow, id) end
                    -- Hold Until Charged applies ONLY while the custom queue is the rotation
                    -- source. The toggle that sets it lives on custom-queue rows, and that
                    -- whole panel hides when the custom queue is off - so honouring the key
                    -- outside custom-queue mode would keep demoting a spell with no reachable
                    -- control to undo it. (alwaysShow needs no such guard: it only ever adds
                    -- visibility, so a stale one is harmless.)
                    if useCustom and ss.holdUntilCharged == true then
                        markForms(maxChargeGated, id)
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
    end
    -- Fixed-queue context: bias positions 2+ by the archetype of Blizzard's position-1
    -- pick (the original recommendation, before any gap-closer/burst injection).
    local ctxArch, ctxRange, ctxRole, ctxExecute
    if primarySpellID and SpellDB then
        ctxArch  = SpellDB.GetArch  and SpellDB.GetArch(primarySpellID)
        ctxRange = SpellDB.GetRange and SpellDB.GetRange(primarySpellID)
        ctxRole  = SpellDB.GetRole  and SpellDB.GetRole(primarySpellID)
        ctxExecute = SpellDB.GetGate and SpellDB.GetGate(primarySpellID) == "execute"
    end
    -- Direct enemy count (secret-safe, AC-independent): promote the context to
    -- cleave/aoe from the number of enemies actually engaged with us, catching AoE
    -- that a single AC-pick archetype misses. Promote-only - never downgrades AC's
    -- own aoe/cleave read.
    if inCombat and BlizzardAPI.GetEngagedEnemyCount then
        local enemies = BlizzardAPI.GetEngagedEnemyCount()
        if enemies >= 2 then
            ctxArch = (enemies >= 3 or ctxArch == "aoe") and "aoe" or "cleave"
        end
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
    if cachedRotationList then
        -- Master ordering toggles (profile-level; apply to both the custom list and
        -- Blizzard's default rotation). Default nil → true (smart order):
        -- "procs first" off folds procced spells into the normal bucket (kept in source
        -- order); "context aware" off neutralizes ContextRank; "cooldowns last" off leaves
        -- on-CD spells in their source slot instead of trailing.
        local effectiveBypassProcs = bypassProcs or profile.orderProcsFirst == false
        local sinkCooldowns = profile.orderSinkCooldowns ~= false
        -- Context ordering: "off" | "ac" (match Blizzard's pick, the old default) |
        -- "simc" (theorycraft priority). Migrate the old boolean orderContextAware.
        local contextOrder = profile.contextOrder
        if not contextOrder then
            contextOrder = (profile.orderContextAware == false) and "off" or "ac"
        end
        -- SimC ordering needs data for this spec; otherwise fall back to the AC heuristic.
        local simcCtx = (ctxArch == "aoe" and "aoe") or (ctxArch == "cleave" and "cleave") or "st"
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
                        pickWindows = pickWindows or {}
                        pickWindows[g.id] = true
                    end
                end
            end
        end
        lastCtx.pickWindows = pickWindows   -- for /jac inspect gates
        spellCount = CategorizeAndAssembleRotation(cachedRotationList, profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems, effectiveBypassProcs, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee, contextOrder, sinkCooldowns, simcCtx, pickWindows)
    end

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
    return ContextRank(spellID, lastCtx.arch, lastCtx.range, lastCtx.role, lastCtx.execute, lastCtx.outOfMelee)
end

--- Returns true if spellID was injected as a synthetic proc (gap-closer, etc.)
--- by the most recent GetCurrentSpellQueue() call.
function SpellQueue.IsSyntheticProc(spellID)
    return syntheticProcs[spellID] == true
end

--- Returns true if spellID was injected by the burst injection system this frame.
function SpellQueue.IsBurstInjection(spellID)
    return burstInjectedSpells[spellID] == true
end

--- Returns true if spellID was displaced from position 1 to position 2 by a
--- gap-closer injection in the most recent GetCurrentSpellQueue() call.
--- UIRenderer uses this to keep the blue assisted glow on the displaced spell.
function SpellQueue.IsDisplacedPrimary(spellID)
    return displacedPrimary[spellID] == true
end

--- Returns true if spellID is ANY known gap-closer for the current spec
--- (regardless of whether it was injected by our system this frame).
--- Used by renderers to keep the gap-closer glow when Blizzard suggests a
--- gap closer at position 1 after our injection is removed (in-range transition).
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
    if not cachedBurstEngine then cachedBurstEngine = LibStub("JustAC-BurstInjectionEngine", true) end
    SpellQueue.ClearSpellCache()
    SpellQueue.ForceUpdate()
end

function SpellQueue.OnSpellsChanged()
    SpellQueue.ClearSpellCache()
    SpellQueue.InvalidateRotationCache()
    -- SimC rank lookup bakes in talent-dependent override resolution. Invalidate
    -- HERE (SPELLS_CHANGED fires on every talent change) and not in
    -- InvalidateRotationCache, which also fires on every target swap and would
    -- force a full lookup rebuild per target change for no reason.
    if RotationImport and RotationImport.InvalidateLookup then
        RotationImport.InvalidateLookup()
    end
    SpellQueue.ForceUpdate()
end

-- Invalidate the cached rotation list - called on RotationSpellsUpdated and SPELLS_CHANGED
function SpellQueue.InvalidateRotationCache()
    cachedRotationList = nil
    -- Clear rotation spell registrations; they'll be re-registered on next fetch
    if BlizzardAPI and BlizzardAPI.ClearTrackedRotationSpells then
        BlizzardAPI.ClearTrackedRotationSpells()
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

