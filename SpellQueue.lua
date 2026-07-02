-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Spell Queue Module - Retrieves and caches the current Assisted Combat rotation
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 41)
if not SpellQueue then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
local SpellDB = LibStub("JustAC-SpellDB", true)

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
-- so UIRenderer can apply a distinct purple glow instead of the gap-closer gold.
local burstInjectedSpells = {}

-- ── Reusable scratch buffers (wiped at start of each GetCurrentSpellQueue call) ────────────────
-- These are NOT persistent state; they are pooled to avoid GC pressure on the hot path.
local proccedSpells = {}
local normalSpells = {}
local cooldownSpells = {}
local addedSpellIDs = {}
local recommendedSpells = {}
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
local function PassesSpellFilters(spellID, profile)
    local cached = filterResultCache[spellID]
    if cached ~= nil then return cached end
    local isUsable = BlizzardAPI.IsSpellUsable(spellID)
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
--- Returns true if queue should be shown, false to hide it.
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
        return false
    end

    if queueVis == "requireHostile" and not inCombat then
        local hasHostileTarget = UnitExists("target") and UnitCanAttack("player", "target")
        if not hasHostileTarget then
            return false
        end
    end

    if profile.hideQueueWhenMounted then
        local isMounted = IsMounted()
        if not isMounted then
            local formID = GetShapeshiftFormID()
            if formID == 3 or formID == 27 then
                isMounted = true
            end
        end
        if isMounted then
            return false
        end
    end

    return true
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
--- HP-gated finishers (Execute, Kill Shot), stealth-gated openers - via the never-secret
--- ACTION_USABLE_CHANGED cache. Resource starvation (noMana) is transient (rage/energy
--- refill every GCD) and must NOT sink or the queue would churn every press; an unknown
--- read (spell on no bar, secret fallback) fails open to "usable" and leaves order alone.
local function IsConfirmedUnusable(spellID)
    local usable, noMana = BlizzardAPI.GetActionBarUsability(spellID)
    return usable == false and not noMana
end

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

--- Append a bucket's entries to recommendedSpells in profile-distance order
--- (closest match first), stable within each rank. Returns the new spellCount.
local function AppendRankedBucket(bucket, ranks, count, recommendedSpells, spellCount, maxIcons)
    for rank = 0, RANK_SINK do
        for i = 1, count do
            if spellCount >= maxIcons then return spellCount end
            if ranks[i] == rank then
                spellCount = spellCount + 1
                recommendedSpells[spellCount] = bucket[i]
            end
        end
    end
    return spellCount
end

--- Categorize rotation spells into procced/normal/cooldown buckets and assemble
--- in priority order: proc > normal > on-cooldown. Within the proc and normal
--- buckets, entries are ordered by ContextRank (profile-distance to the AC pick), so the
--- ability closest to what Assisted Combat is recommending surfaces first. ctxArch is nil
--- when the AC pick is untagged → uniform rank → no reorder.
local function CategorizeAndAssembleRotation(rotationList, profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems, bypassProcs, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee, contextBias, sinkCooldowns)
    wipe(proccedSpells)
    wipe(normalSpells)
    wipe(proccedRank)
    wipe(normalRank)
    local proccedCount, normalCount, cooldownCount = 0, 0, 0
    -- rankOf: neutral (1, list order preserved) when the situation bias is toggled off.
    local function rankOf(spellID)
        if not contextBias then return 1 end
        return ContextRank(spellID, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee)
    end

    for i = 1, #rotationList do
        local spellID = rotationList[i]
        if spellID and not addedSpellIDs[spellID] then
            if spellID < 0 then
                -- Item entry (negative ID): use item-specific APIs.
                -- Items are only present via Custom Queue - skip spell filters.
                local itemID = -spellID
                addedSpellIDs[spellID] = true
                local isUsable, hasItem, onCooldown = BlizzardAPI.CheckDefensiveItemState(itemID)
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
                if displayID
                   and not (hideItems and BlizzardAPI.IsItemSpell(displayID))
                   and PassesRotationFilters(displayID, profile) then
                    -- Proc check BEFORE the cooldown sink: the proc overlay is
                    -- Blizzard's NeverSecret "press this now" signal and outranks our
                    -- readiness inference, which goes stale on unobserved resets/refunds
                    -- (a proc-driven CD reset or charge refund fires no cast event).
                    if not bypassProcs and BlizzardAPI.IsSpellProcced(displayID)
                       and ProcPriorityEnabled(spellID, profile) then
                        proccedCount = proccedCount + 1
                        proccedSpells[proccedCount] = displayID
                        proccedRank[proccedCount] = rankOf(spellID)
                    elseif sinkCooldowns and (not BlizzardAPI.IsSpellReady(displayID)
                           or IsConfirmedUnusable(displayID)
                           or IsConfirmedOutOfRange(displayID)) then
                        cooldownCount = cooldownCount + 1
                        cooldownSpells[cooldownCount] = displayID
                    else
                        normalCount = normalCount + 1
                        normalSpells[normalCount] = displayID
                        normalRank[normalCount] = rankOf(spellID)
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

function SpellQueue.GetCurrentSpellQueue()
    local profile = BlizzardAPI.GetProfile()
    if not profile or profile.isManualMode then
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
    
    if not EvaluateQueueVisibility(profile, inCombat) then
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
    local maxIcons = profile.maxIcons or 4
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
            if cachedGapCloserEngine.MarkGapCloserSpellIDs then
                cachedGapCloserEngine.MarkGapCloserSpellIDs(cachedAddon, addedSpellIDs)
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
                -- Copy the user's custom spell list as the rotation source
                local cq = cqProfile[specKey]
                cachedRotationList = {}
                for i, sid in ipairs(cq.spells) do
                    cachedRotationList[i] = sid
                end
                useCustom = true
            end
        end
        if not useCustom and BlizzardAPI.GetRotationSpells then
            cachedRotationList = BlizzardAPI.GetRotationSpells()
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
    -- Temporal smoothing of the revealed context (see module-state comment):
    -- latch execute per target, hold multi evidence for STICKY_CTX_SECONDS.
    local stickyApplied, executeLatched = false, false
    if inCombat then
        local targetGUID = UnitGUID("target")
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
        local contextBias  = profile.orderContextAware ~= false
        local sinkCooldowns = profile.orderSinkCooldowns ~= false
        spellCount = CategorizeAndAssembleRotation(cachedRotationList, profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems, effectiveBypassProcs, ctxArch, ctxRange, ctxRole, ctxExecute, ctxOutOfMelee, contextBias, sinkCooldowns)
    end

    -- When Blizzard returns no spells (e.g. target out of range OOC) but
    -- visibility conditions passed, preserve the previous queue so the frame
    -- stays visible with stale icons instead of hiding entirely.
    if spellCount > 0 then
        wipe(lastSpellIDs)
        for i = 1, spellCount do
            lastSpellIDs[i] = recommendedSpells[i]
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

