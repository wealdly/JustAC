-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: WoW Forever context stages of the queue build: the pushback model and response,
-- the weapon filler comparison, the near-melee hint and the opt-in mana-efficiency finish.
-- Extends the JustAC-SpellQueue library. Loaded by JustAC.toc after SpellQueue.lua, whose
-- shared build state it captures once below. A separate file keeps SpellQueue.lua's main
-- chunk under Lua 5.1's 200-local cap.
local SUBMAJOR, SUBMINOR = "JustAC-SpellQueue-Forever", 1
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local SpellQueue = LibStub("JustAC-SpellQueue", true)
if not SpellQueue then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local RotationImport = LibStub("JustAC-RotationImport", true)

-- Hot path cache
local GetTime = GetTime
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitClassification = UnitClassification ---@diagnostic disable-line: undefined-global
local UnitGUID = UnitGUID ---@diagnostic disable-line: undefined-global
local UnitCastingInfo = UnitCastingInfo ---@diagnostic disable-line: undefined-global
local UnitChannelInfo = UnitChannelInfo ---@diagnostic disable-line: undefined-global
local wipe = wipe
local type = type
local ipairs = ipairs

-- SpellQueue.lua build state and helpers
local AUTO_ATTACK_SPELL = SpellQueue._AUTO_ATTACK_SPELL
local LEAD_BARRED_PENALTY = SpellQueue._LEAD_BARRED_PENALTY
local syntheticProcs = SpellQueue._syntheticProcs
local displacedPrimary = SpellQueue._displacedPrimary
local sunkSet = SpellQueue._sunkSet
local lastCtx = SpellQueue._lastCtx
local PassesRotationFilters = SpellQueue._PassesRotationFilters
local HeldByUserHold = SpellQueue._HeldByUserHold
local IsLiveAttackableTarget = SpellQueue._IsLiveAttackableTarget
local IsUnusableNonResource = SpellQueue.IsUnusableNonResource
local CostsMana = SpellQueue._CostsMana
local GatesConfirmed = SpellQueue._GatesConfirmed
local PlaceQueueSpell = SpellQueue._PlaceQueueSpell
local PushbackRead = SpellQueue._PushbackRead
local PushbackReady = SpellQueue._PushbackReady

local lastPushbackAt
local PUSHBACK_WINDOW = 5
-- Unabsorbed hits on the player (UNIT_COMBAT WOUND) in the last Hits.WINDOW give a hit rate;
-- absorbed hits never push (measured). Pushback per cast, measured on Forever 2026-11-16:
-- each hit pushes the next Hits.STEPS second, never more than the cast's progress so far.
-- A fifth push was not observed, so expected pushback stops at four. Pushback resistance
-- (Concentration Aura, talents) is not seen.
local Hits = { times = {}, WINDOW = 3, STEPS = { 1.0, 0.8, 0.6, 0.4 } }

local function Recent(at, now, window)
    return at ~= nil and now ~= nil and now >= at and now - at <= window
end

function SpellQueue.NotePushback()
    lastPushbackAt = GetTime()
end

function Hits.Prune(now)
    local times = Hits.times
    while times[1] and not Recent(times[1], now, Hits.WINDOW) do table.remove(times, 1) end
end

--- Record an unabsorbed hit on the player. Returns true when no other hit is in the window.
function SpellQueue.NoteIncomingHit()
    local now = GetTime()
    Hits.Prune(now)
    Hits.times[#Hits.times + 1] = now
    return #Hits.times == 1
end

--- Unabsorbed hits per second over the last window.
function Hits.Rate(now)
    if not now then return 0 end
    Hits.Prune(now)
    return #Hits.times / Hits.WINDOW
end

--- Are you being hit (an unabsorbed hit in the last Hits.WINDOW seconds)? Our own observation
--- (UNIT_COMBAT), so true or false, never unknown: casts started now expect pushback.
function SpellQueue._BeingHit(now)
    now = now or (GetTime and GetTime())
    if not now then return false end
    return Hits.Rate(now) > 0
end

--- Expected pushback seconds for a cast of `cast` seconds at `rate` hits per second. The first
--- push is capped by the cast's progress: for a hit anywhere in the cast it averages
--- min(1, t) over t in [0, cast]. A pushed cast stays open longer, so the hits are counted once
--- more over the pushed length.
function Hits.Pushback(hits, first)
    local seconds = 0
    for i, step in ipairs(Hits.STEPS) do
        if hits <= 0 then break end
        if i == 1 then step = first end
        seconds = seconds + step * math.min(1, hits)
        hits = hits - 1
    end
    return seconds
end
function Hits.Expected(cast, rate)
    if rate <= 0 then return 0 end
    local first
    if cast >= 1 then first = (cast - 0.5) / cast else first = cast / 2 end
    return Hits.Pushback(rate * (cast + Hits.Pushback(rate * cast, first)), first)
end
SpellQueue._ExpectedPushback = Hits.Expected   -- tests

function SpellQueue.ResetPushback()
    lastPushbackAt = nil
    wipe(Hits.times)
end

-- The weapon the comparison chose against this target (in combat). It stays chosen while
-- its moment-to-moment reads waver; target change, leaving combat or a real exclusion ends it.
local weaponPhaseID

function SpellQueue._ResetWeaponPhase()
    weaponPhaseID = nil
end

local EFFICIENCY_ATTACKS = {5019, 75, AUTO_ATTACK_SPELL} -- wand, Auto Shot, melee
local EFFICIENCY_SAFE_HEALTH_PCT = 80
local EFFICIENCY_DEFAULT_MANA_PCT = 40
local EFFICIENCY_DEFAULT_RECOVERY_SECONDS = 10
local efficiencyDetails = {}

local function EfficiencyRead(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not BlizzardAPI.IsSecretValue(value) then return value end
    return nil
end

local function EfficiencyFreeAttack(id, b)
    if SpellQueue.IsSpellBlacklisted(id, b.blacklist) then return false, "blacklisted" end
    if SpellQueue.IsCasterSuppressedPick(id, b.profile) then return false, "caster filler" end
    if EfficiencyRead(IsPlayerSpell, id) ~= true then return false, "not learned or unknown" end
    if EfficiencyRead(BlizzardAPI.HasRequiredAttackWeapon, id) ~= true then
        return false, "required weapon missing or unknown"
    end
    if SpellQueue.IsHeldByHold(id) then return false, "held" end
    if EfficiencyRead(BlizzardAPI.IsSpellReady, id) ~= true then return false, "not ready or unknown" end
    if EfficiencyRead(BlizzardAPI.IsSpellUsable, id, false) ~= true then return false, "unusable or unknown" end
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return false, "costs unavailable" end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
    if not ok then return false, "costs denied" end
    if BlizzardAPI.IsSecretValue(costs) then return false, "costs secret" end
    -- The API documents nil for no resource cost as well as unknown spells;
    -- learned, ready and usable were confirmed above.
    if costs == nil then return true, "eligible" end
    if type(costs) ~= "table" then return false, "costs unknown" end
    for _, cost in ipairs(costs) do
        if BlizzardAPI.IsSecretValue(cost) or type(cost) ~= "table"
           or BlizzardAPI.IsSecretValue(cost.cost) or type(cost.cost) ~= "number"
           or cost.cost ~= 0 then return false, "not confirmed free" end
    end
    return true, "eligible"
end

local function EfficiencyCandidate(b)
    local mode = b.profile.efficiencyMode
    if mode == nil or mode == "off" then return nil, "off" end
    if mode ~= "solo" and mode ~= "always" then return nil, "invalid mode" end
    if SpellQueue._rotationIsCustom or b.contextOrder == "off" then return nil, "explicit order" end
    if not b.inCombat then return nil, "out of combat" end
    if b.ctxEnemies ~= 1 then return nil, "enemy count not exactly one" end
    if b.ctxArch == "aoe" or b.ctxArch == "cleave" then return nil, "multi-target context" end
    if EfficiencyRead(UnitExists, "target") ~= true
       or EfficiencyRead(UnitCanAttack, "player", "target") ~= true then return nil, "no confirmed hostile target" end
    if EfficiencyRead(BlizzardAPI.IsTargetBoss) ~= false then return nil, "boss or unknown" end
    if EfficiencyRead(UnitClassification, "target") ~= "normal" then return nil, "not a normal target" end
    if EfficiencyRead(UnitIsPVP, "player") ~= false
       or EfficiencyRead(UnitIsPVPFreeForAll, "player") ~= false
       or EfficiencyRead(UnitIsPlayer, "target") ~= false
       or EfficiencyRead(UnitPlayerControlled, "target") ~= false
       or EfficiencyRead(UnitIsDeadOrGhost, "player") ~= false
       or EfficiencyRead(UnitIsDeadOrGhost, "target") ~= false then return nil, "unsafe or unreadable units" end
    if mode == "solo" and (BlizzardAPI.IsGrouped() ~= false
       or EfficiencyRead(IsInInstance) ~= false) then return nil, "not solo open world" end
    if EfficiencyRead(BlizzardAPI.IsUnitHealthBelow, "player", EFFICIENCY_SAFE_HEALTH_PCT) ~= false then
        return nil, "health unsafe or unknown"
    end
    local pct = b.profile.efficiencyManaThreshold
    if pct == nil then pct = EFFICIENCY_DEFAULT_MANA_PCT end
    if type(pct) ~= "number" or not (pct >= 10 and pct <= 80) then return nil, "invalid mana threshold" end
    local seconds = b.profile.efficiencyRecoverySeconds
    if seconds == nil then seconds = EFFICIENCY_DEFAULT_RECOVERY_SECONDS end
    if type(seconds) ~= "number" or not (seconds >= 5 and seconds <= 60) then
        return nil, "invalid recovery threshold"
    end
    local full, source, baseFull = BlizzardAPI.GetManaRecoveryEstimate()
    lastCtx.efficiencyRecoverySource = source
    lastCtx.efficiencyFullSeconds, lastCtx.efficiencyBaseFullSeconds = full, baseFull
    if source == "no mana" then return nil, "no mana resource" end
    if b.ctxDying then
        lastCtx.efficiencyResourceDecision = "dying target"
    elseif source == "readable" then
        lastCtx.efficiencyResourceDecision = "recovery estimate"
        if full < seconds then return nil, "fast mana recovery" end
    elseif source == "no combat regeneration" then
        lastCtx.efficiencyResourceDecision = "no combat regeneration"
    else
        lastCtx.efficiencyResourceDecision = "mana threshold fallback"
        local below = EfficiencyRead(BlizzardAPI.IsUnitPowerBelow, "player", pct, Enum.PowerType.Mana)
        lastCtx.efficiencyManaBelow = below
        if below == false then return nil, "mana at or above threshold" end
        if below ~= true then return nil, "mana threshold unreadable" end
    end
    local lead = b.recommendedSpells[1]
    if not lead or lead <= 0 or syntheticProcs[lead] or not SpellDB or SpellDB.GetArch(lead) ~= "st"
       or not SpellDB.IsOffensiveSpell(lead) or not CostsMana(lead)
       or EfficiencyRead(BlizzardAPI.IsSpellProcced, lead) ~= false then return nil, "preserve leading ability" end
    -- Native rotation feeds can omit auto attacks. Learned/actionable checks,
    -- not rotation membership, establish whether a free finisher is available.
    local candidate, candidateRank, candidateRange, candidateWaiting
    wipe(efficiencyDetails)
    for _, id in ipairs(EFFICIENCY_ATTACKS) do
        local eligible, reason = EfficiencyFreeAttack(id, b)
        if eligible then
            local range = EfficiencyRead(BlizzardAPI.AbilityInRange, id, "target")
            local running
            if id == AUTO_ATTACK_SPELL then
                running = EfficiencyRead(C_Spell.IsCurrentSpell, id)
            else
                running = EfficiencyRead(C_Spell.IsAutoRepeatSpell, id)
            end
            local waiting = range == true and running == true
            local rangeText = "unknown"
            if range == true then rangeText = "in range"
            elseif range == false then rangeText = "out of range" end
            -- A running wand or Auto Shot is never displaced: starting melee would cancel it.
            -- Running melee still yields to an in-range ranged attack.
            local rank = 3
            if waiting and id == AUTO_ATTACK_SPELL then rank = 2
            elseif waiting then rank = 0
            elseif range == true then rank = 1
            elseif range == false then rank = 4 end
            reason = reason .. ": " .. rangeText
            if running == true then reason = reason .. ", running" end
            if not candidateRank or rank < candidateRank then
                candidate, candidateRank, candidateRange, candidateWaiting = id, rank, rangeText, waiting
            end
        end
        efficiencyDetails[#efficiencyDetails + 1] = id .. "=" .. reason
    end
    lastCtx.efficiencyCandidates = table.concat(efficiencyDetails, "; ")
    lastCtx.efficiencyRange = candidateRange
    if candidateWaiting then return candidate, "wait for auto attack" end
    if candidate then return candidate, "conserve mana" end
    return nil, "no confirmed free attack"
end

function SpellQueue._StageEfficiency(b)
    b.efficiencyWaiting = nil
    lastCtx.efficiencyManaBelow = nil
    lastCtx.efficiencyRecoverySource, lastCtx.efficiencyResourceDecision = nil, nil
    lastCtx.efficiencyFullSeconds, lastCtx.efficiencyBaseFullSeconds = nil, nil
    lastCtx.efficiencyCandidates, lastCtx.efficiencyRange = nil, nil
    local id, reason = EfficiencyCandidate(b)
    lastCtx.efficiencyReason, lastCtx.efficiencyID = reason, id
    if not id then return end
    b.efficiencyWaiting = reason == "wait for auto attack"
    local queue = b.recommendedSpells
    if b.primarySpellID and queue[1] == b.primarySpellID then
        displacedPrimary[b.primarySpellID] = true
    end
    local position
    for i = 1, b.spellCount do
        if queue[i] == id then position = i; break end
    end
    local display = id
    if b.efficiencyWaiting then
        display = SpellQueue.WAIT_SENTINEL
    end
    PlaceQueueSpell(b, display, 1, position)
    b.addedSpellIDs[id] = true
end

local PUSHBACK_AUTOS = { [AUTO_ATTACK_SPELL] = true, [3018] = true }

--- The spell's current mana cost: 0 when it costs none, nil when any cost row is unreadable.
--- Not cached: free-cast effects (Clearcasting, Inner Focus) change it.
local function ManaCost(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or BlizzardAPI.IsSecretValue(costs) or type(costs) ~= "table" then return nil end
    local total = 0
    for i = 1, #costs do
        local c = costs[i]
        if BlizzardAPI.IsSecretValue(c) or type(c) ~= "table" or BlizzardAPI.IsSecretValue(c.type) then
            return nil
        end
        if c.type == 0 then
            local cost = c.cost
            if BlizzardAPI.IsSecretValue(cost) or type(cost) ~= "number" or not (cost >= 0) then return nil end
            total = total + cost
        end
    end
    return total
end

local function PushbackCastTime(id)
    local info = PushbackRead(BlizzardAPI.GetCachedSpellInfo, id)
    if type(info) ~= "table" then return nil end
    local castTime = info.castTime
    if BlizzardAPI.IsSecretValue(castTime) or type(castTime) ~= "number" then return nil end
    return castTime
end

local function HasRequiredStack(gates)
    for _, gate in ipairs(gates or {}) do
        if (gate.t == "stack" and gate.required) or (gate.g and HasRequiredStack(gate.g)) then return true end
    end
    return false
end

local NEAR_MELEE_HINT_SECONDS = 3

function SpellQueue._UpdateNearMeleeHint(b)
    local state, now = SpellQueue._nearMeleeState, b.now
    b.nearMeleeHint = false
    state.activityAt, state.source = nil, nil
    if not BlizzardAPI.IsForever() or not b.inCombat or not now
       or SpellQueue._rotationIsCustom or b.contextOrder == "off" or not b.sinkCooldowns
       or not IsLiveAttackableTarget()
       or PushbackRead(SpellDB.IsTargetWithin, 5) ~= nil then
        SpellQueue.ResetNearMeleeHint()
        return
    end
    local function useMeleeActivity()
        local at = PushbackRead(BlizzardAPI.GetMeleeActivityTime)
        if type(at) == "number" and now >= at and now - at <= NEAR_MELEE_HINT_SECONDS then
            state.activityAt, state.source = at, "melee-activity"
            b.nearMeleeHint = true
        end
    end
    for _, id in ipairs(EFFICIENCY_ATTACKS) do
        if id ~= AUTO_ATTACK_SPELL and PushbackRead(BlizzardAPI.IsSpellAvailable, id) == true then
            local info = PushbackRead(BlizzardAPI.GetCachedSpellInfo, id)
            if type(info) == "table"
               and not BlizzardAPI.IsSecretValue(info.minRange)
               and not BlizzardAPI.IsSecretValue(info.maxRange)
               and type(info.minRange) == "number" and info.minRange > 0
               and type(info.maxRange) == "number" and info.maxRange > info.minRange then
                local range = PushbackRead(BlizzardAPI.AbilityInRange, id)
                if type(range) ~= "boolean" then
                    SpellQueue.ResetNearMeleeHint()
                    useMeleeActivity()
                    return
                end
                if range == false and PushbackRead(SpellDB.IsTargetWithin, info.maxRange) == false then
                    SpellQueue.ResetNearMeleeHint()
                    return
                end
                if state.id ~= id then SpellQueue.ResetNearMeleeHint() end
                if range == true then
                    state.hintAt = nil
                elseif PushbackRead(SpellDB.IsTargetWithin, info.maxRange) == true
                   or ((state.inRange == true or state.hintAt ~= nil)
                       and state.observedAt and now >= state.observedAt
                       and now - state.observedAt <= NEAR_MELEE_HINT_SECONDS) then
                    -- Ordering cue only: this could also be a target retreating past maximum range.
                    state.hintAt = now
                else
                    state.hintAt = nil
                end
                state.id, state.inRange, state.observedAt = id, range, now
                if state.hintAt and now >= state.hintAt
                   and now - state.hintAt <= NEAR_MELEE_HINT_SECONDS then
                    b.nearMeleeHint = true
                    state.source = "shooting-range"
                end
                if range == false then useMeleeActivity() end
                return
            end
        end
    end
    SpellQueue.ResetNearMeleeHint()
    useMeleeActivity()
end

function SpellQueue._PrepareWeaponFillers(rotationList, b)
    local fillers = SpellQueue._weaponFillers
    wipe(fillers.ids)
    wipe(fillers.ranks)
    wipe(fillers.dps)
    fillers.count, fillers.leadRank = 0, nil
    b.weaponFillerID, b.weaponFillerDPS, b.weaponFillerRunning = nil, nil, nil
    lastCtx.weaponReason = "no eligible weapon comparison"
    lastCtx.weaponLead, lastCtx.weaponID, lastCtx.weaponSpellDPS, lastCtx.weaponDPS = nil, nil, nil, nil
    if not BlizzardAPI.IsForever() or SpellQueue._rotationIsCustom or b.contextOrder == "off"
       or b.spellCount ~= 0 or not (RotationImport and SpellDB and IsLiveAttackableTarget())
       or not BlizzardAPI.GetDirectSpellDPS or not BlizzardAPI.GetAutoAttackDPS
       or b.ctxArch == "aoe" or b.ctxArch == "cleave"
       or (b.inCombat and b.ctxEnemies ~= 1 and b.ctxEnemies ~= 0)
       or PushbackRead(BlizzardAPI.IsTargetBoss) ~= false
       or PushbackRead(UnitIsPlayer, "target") ~= false
       or PushbackRead(UnitPlayerControlled, "target") ~= false then return end
    if not b.inCombat and BlizzardAPI.RefreshDamageBaseline then BlizzardAPI.RefreshDamageBaseline() end
    local best, bestDPS, bestRunning, phaseEligible
    if not b.inCombat then weaponPhaseID = nil end
    -- Wand wins equal DPS; melee never asks the player to move into reach.
    for _, id in ipairs(EFFICIENCY_ATTACKS) do
        if not SpellQueue.IsSpellBlacklisted(id, b.blacklist)
           and PassesRotationFilters(id, b.profile, id)
           and PushbackRead(BlizzardAPI.IsSpellAvailable, id) == true
           and PushbackRead(BlizzardAPI.AbilityInRange, id) == true
           and not (BlizzardAPI.IsSpellLoCLocked and BlizzardAPI.IsSpellLoCLocked(id))
           and not HeldByUserHold(id, id, true) then
            if id == weaponPhaseID then phaseEligible = true end
            local running = BlizzardAPI.RunningAutoSwing(id)
            local usable, notEnough = BlizzardAPI.IsSpellUsable(id, false)
            if usable == true and not notEnough
               and (running == 0 or running == 2 or PushbackReady(id)) then
                local dps = PushbackRead(BlizzardAPI.GetAutoAttackDPS, id, true)
                if type(dps) == "number" and dps > 0
                   and (not bestDPS or dps > bestDPS) then
                    best, bestDPS, bestRunning = id, dps, running
                end
            end
        end
    end
    -- The phase weapon still passes every real exclusion; only its moment-to-moment reads
    -- (usable, running, between shots) wavered, so it stays the choice for this target.
    if not best and phaseEligible then
        local dps = PushbackRead(BlizzardAPI.GetAutoAttackDPS, weaponPhaseID, true)
        if type(dps) == "number" and dps > 0 then
            best, bestDPS, bestRunning = weaponPhaseID, dps, BlizzardAPI.RunningAutoSwing(weaponPhaseID)
        end
    end
    if b.inCombat and best then weaponPhaseID = best end
    lastCtx.weaponDPS = bestDPS
    if not best then lastCtx.weaponReason = "weapon unavailable or damage unknown"; return end
    if b.inCombat and b.ctxEnemies == 0 and bestRunning ~= 2 then return end
    -- A cast's cycle is its cast time (longer while being hit, for pushback) plus the time
    -- base regeneration needs to earn its mana back; the weapon spends none. An unreadable
    -- cost or regeneration rate leaves the mana part out, never estimated.
    local hitRate = Hits.Rate(b.now)
    local regen = BlizzardAPI.GetBaselineManaRegen and BlizzardAPI.GetBaselineManaRegen()
    for _, source in ipairs(rotationList) do
        if type(source) == "number" and source > 0 then
            local id = BlizzardAPI.GetDisplaySpellID(source)
            if id and SpellDB.GetArch and SpellDB.GetArch(id) == "st"
               and not SpellDB.IsTargetDot(id) and not SpellDB.IsChanneled(id) then
                -- base: the cast time, never shorter than the spell's own GCD (an instant counts
                -- one GCD); pushback lengthens only the cast part.
                local dps = PushbackRead(BlizzardAPI.GetDirectSpellDPS, id, nil, true)
                local base, cast
                if dps and BlizzardAPI.GetSpellCycleSeconds then
                    base, cast = BlizzardAPI.GetSpellCycleSeconds(id)
                end
                if base then
                    local cycle = base
                    if cast > 0 then cycle = cycle + Hits.Expected(cast, hitRate) end
                    local cost = regen and ManaCost(id)
                    if cost then cycle = cycle + cost / regen end
                    fillers.dps[id] = dps * base / cycle
                end
            end
        end
    end
    lastCtx.weaponHitRate, lastCtx.weaponManaRegen = hitRate, regen
    if not next(fillers.dps) then lastCtx.weaponReason = "no comparable spell filler"; return end
    b.weaponFillerID, b.weaponFillerDPS = best, bestDPS
    b.weaponFillerRunning = bestRunning
end

function SpellQueue._AddWeaponFiller(id, rank, ready, rec, b)
    local auto = id == 5019 or id == 75 or id == AUTO_ATTACK_SPELL
    local fillers = SpellQueue._weaponFillers
    local dps = fillers.dps[id]
    if not auto and not rec and RotationImport.GetEntry then rec = RotationImport.GetEntry(id, b.simcCtx) end
    if not auto and (not dps or syntheticProcs[id]
       or PushbackRead(BlizzardAPI.IsSpellProcced, id) ~= false
       or (rec and HasRequiredStack(rec.gates))) then return false end
    if not ready and BlizzardAPI.RunningAutoSwing(id) == nil
       and not (b.weaponFillerRunning == 2 and RotationImport.GetPushbackDamageCooldown
                and RotationImport.GetPushbackDamageCooldown(id) == 0) then return false end
    local score = LEAD_BARRED_PENALTY + rank
    if auto then
        score = 2 * LEAD_BARRED_PENALTY + rank
        if id == b.weaponFillerID then score = LEAD_BARRED_PENALTY end
    else
        if dps >= b.weaponFillerDPS * 1.20 then score = rank end
        if not fillers.leadRank or rank < fillers.leadRank then
            fillers.leadRank = rank
            lastCtx.weaponLead, lastCtx.weaponSpellDPS = id, dps
        end
    end
    fillers.count = fillers.count + 1
    fillers.ids[fillers.count], fillers.ranks[fillers.count] = id, score
    return true
end

--- Prefer short-cooldown instants after observed pushback.
function SpellQueue._StagePushback(b, rotationList)
    lastCtx.pushbackReason = "no eligible pushback response"
    lastCtx.pushbackID = nil
    if not (b.inCombat and BlizzardAPI.IsForever() and Recent(lastPushbackAt, b.now, PUSHBACK_WINDOW))
       or SpellQueue._rotationIsCustom or b.contextOrder == "off"
       or not (rotationList and RotationImport and RotationImport.GetPushbackDamageCooldown
               and SpellDB and IsLiveAttackableTarget()) then return end
    local queue = b.recommendedSpells
    local lead = queue[1]
    if not lead or lead <= 0 then return end
    local insertAt = 2
    if not syntheticProcs[lead] and PushbackRead(BlizzardAPI.IsSpellProcced, lead) ~= true then
        local leadRec = RotationImport.GetEntry and RotationImport.GetEntry(lead, b.simcCtx)
        if not (leadRec and HasRequiredStack(leadRec.gates)) then
            local leadCastTime = PushbackCastTime(lead)
            if sunkSet[lead] or (leadCastTime and leadCastTime > 0) then
                insertAt = 1
            end
        end
    end
    if insertAt > b.maxIcons then return end

    local resCount, resMax, resName
    if BlizzardAPI.GetClassResourcePoints then
        resCount, resMax, resName = BlizzardAPI.GetClassResourcePoints()
    end
    local best, bestSource, bestCooldown, bestInterrupt
    for _, source in ipairs(rotationList) do
        if type(source) == "number" and source > 0 then
            local cooldown = RotationImport.GetPushbackDamageCooldown(source)
            local id = BlizzardAPI.GetDisplaySpellID(source)
            if cooldown and cooldown < 10 and id and not PUSHBACK_AUTOS[id]
               and not SpellDB.IsForeverRangedFiller(id) and not sunkSet[id]
               and not SpellQueue.IsSpellBlacklisted(source, b.blacklist)
               and not SpellQueue.IsSpellBlacklisted(id, b.blacklist)
               and SpellDB.IsOffensiveSpell(id)
               and not SpellDB.IsTargetDot(id) and not SpellDB.IsChanneled(id)
               and not (BlizzardAPI.IsMeleeSwingSpell and BlizzardAPI.IsMeleeSwingSpell(id))
               and PushbackCastTime(id) == 0
               and PushbackRead(C_Spell and C_Spell.IsSpellHarmful, id) == true
               and PushbackRead(BlizzardAPI.IsSpellAvailable, id) == true
               and PushbackReady(id)
               and PushbackRead(BlizzardAPI.AbilityInRange, id) == true
               and not (BlizzardAPI.IsOffGCDSpell and BlizzardAPI.IsOffGCDSpell(id))
               and not (BlizzardAPI.IsSpellLoCLocked and BlizzardAPI.IsSpellLoCLocked(id))
               and not HeldByUserHold(source, id, true)
               and not (RedundancyFilter and RedundancyFilter.IsSpellRedundant
                        and RedundancyFilter.IsSpellRedundant(id, b.profile)) then
                local usable, notEnough = BlizzardAPI.IsSpellUsable(id, false)
                if usable == true and not notEnough and not IsUnusableNonResource(id, usable, notEnough) then
                    local interrupt = SpellDB.IsInterruptTypeSpell(id)
                    local role = SpellDB.GetForeverAbilityRole(id)
                    local rec = RotationImport.GetEntry and RotationImport.GetEntry(id, b.simcCtx)
                    local interruptSafe = not interrupt
                    if interrupt and BlizzardAPI.GetTargetCastInterruptState
                       and BlizzardAPI.HasTargetCastSinceSelected then
                        interruptSafe = BlizzardAPI.GetTargetCastInterruptState() == false
                            and BlizzardAPI.HasTargetCastSinceSelected() == false
                            and PushbackRead(UnitIsPlayer, "target") == false
                            and PushbackRead(UnitPlayerControlled, "target") == false
                            and PushbackRead(BlizzardAPI.IsTargetBoss) == false
                    end
                    if interruptSafe
                       and (not role or role == "mixed" or (interrupt and role == "utility"))
                       and ((rec and not rec.delegated and GatesConfirmed(rec.gates, resCount, resName, resMax))
                            or (interrupt and not rec))
                       and (not best or (bestInterrupt and not interrupt)
                            or (bestInterrupt == interrupt and cooldown < bestCooldown)) then
                        best, bestSource, bestCooldown, bestInterrupt = id, source, cooldown, interrupt
                    end
                end
            end
        end
    end
    if best and lastCtx.pushbackID ~= best then
        lastCtx.pushbackReason, lastCtx.pushbackID = "instant damage after observed pushback", best
    end
    if not best or best == lead then return end
    local position
    for i = insertAt, b.spellCount do
        if queue[i] == best then position = i; break end
    end
    PlaceQueueSpell(b, best, insertAt, position)
    b.addedSpellIDs[best], b.addedSpellIDs[bestSource] = true, true
end

--- Can this be pressed right now: off cooldown, usable, affordable and not out of range?
--- Only plain positive answers count.
function SpellQueue._PressableNow(id)
    if BlizzardAPI.IsSpellReady(id) ~= true then return false end
    local usable, notEnough = BlizzardAPI.IsSpellUsable(id, false)
    if usable ~= true or notEnough == true then return false end
    return BlizzardAPI.AbilityInRange(id) ~= false
end

-- A target that holds its range (a caster or an archer) is never slowed into melee, so an
-- attack whose extra value is its slow (Frostbolt) is worth less than a stronger one that does
-- not slow (Fireball). Evidence only, per target (plain GUID on Forever), in combat: the target
-- casting while out of melee reach, or the player being hit by a lone target that has stayed
-- out of reach for a few seconds. A target that reaches melee, or no evidence, keeps the list's
-- own order: the slow is what a melee mob closing on a ranged player is worth slowing for.
local HOLD_RANGE_AFTER = 3
local holdGUID, holdSince, holdConfirmed

local function TargetCasting()
    for _, read in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
        if read then
            local ok, name = pcall(read, "target")
            if ok and name ~= nil and not BlizzardAPI.IsSecretValue(name) then return true end
        end
    end
    return false
end

function SpellQueue._TargetHoldsRange(b)
    if not b.inCombat then holdGUID, holdSince, holdConfirmed = nil, nil, false; return false end
    local ok, guid = pcall(UnitGUID, "target")
    if not ok or BlizzardAPI.IsSecretValue(guid) or type(guid) ~= "string" then return false end
    if guid ~= holdGUID then holdGUID, holdSince, holdConfirmed = guid, b.now, false end
    local within = SpellDB.IsTargetWithin and SpellDB.IsTargetWithin(5)
    if within == true then
        holdSince, holdConfirmed = b.now, false
        return false
    end
    if within == false and not holdConfirmed then
        if TargetCasting() then
            holdConfirmed = true
        elseif b.ctxEnemies == 1 and b.now - holdSince >= HOLD_RANGE_AFTER and SpellQueue._BeingHit(b.now) then
            holdConfirmed = true
        end
    end
    return holdConfirmed
end

--- Whole damage per second of one cast (its hit plus any damage over time that follows), from
--- the data model: nil when unknown.
local function WholeSpellDPS(id)
    local hit = PushbackRead(BlizzardAPI.GetDirectSpellHit, id, nil, true)
    local cycle = BlizzardAPI.GetSpellCycleSeconds and BlizzardAPI.GetSpellCycleSeconds(id)
    if type(hit) ~= "number" or type(cycle) ~= "number" or cycle <= 0 then return nil end
    return hit / cycle
end

--- Against a target holding its range, the first slowing attack in the queue gives its place to
--- the strongest pool attack that does not slow and the list does not name (the list's own
--- order stands when it names both), ready, castable and in range now.
function SpellQueue._StageRangedFiller(b, rotationList)
    lastCtx.holdsRange, lastCtx.rangedSwap = nil, nil
    if not BlizzardAPI.IsForever() or SpellQueue._rotationIsCustom or b.spellCount == 0
       or not (SpellDB.IsSlowingAttack and BlizzardAPI.GetDirectSpellHit and rotationList) then return end
    local holds = SpellQueue._TargetHoldsRange(b)
    lastCtx.holdsRange = holds
    if not holds then return end
    local queue = b.recommendedSpells
    local slowAt
    for i = 1, b.spellCount do
        local id = queue[i]
        if type(id) == "number" and id > 0 and not sunkSet[id] and SpellDB.IsSlowingAttack(id) then
            slowAt = i
            break
        end
    end
    if not slowAt then return end
    local slowDPS = WholeSpellDPS(queue[slowAt])
    if not slowDPS then return end
    local best, bestDPS
    for _, source in ipairs(rotationList) do
        local id = type(source) == "number" and source > 0 and BlizzardAPI.GetDisplaySpellID(source)
        if id and not SpellDB.IsSlowingAttack(id)
           and not (RotationImport and RotationImport.GetEntry and RotationImport.GetEntry(id, b.simcCtx))
           and not SpellQueue.IsSpellBlacklisted(id, b.blacklist)
           and PassesRotationFilters(id, b.profile, source) and not HeldByUserHold(id, id, true)
           and PushbackReady(id) and PushbackRead(BlizzardAPI.AbilityInRange, id) == true then
            local usable, notEnough = BlizzardAPI.IsSpellUsable(id, false)
            local dps = usable == true and not notEnough and WholeSpellDPS(id)
            if dps and dps > slowDPS and (not bestDPS or dps > bestDPS) then best, bestDPS = id, dps end
        end
    end
    if not best then return end
    -- Out of its old place, then into the slow attack's.
    for i = 1, b.spellCount do
        if queue[i] == best then
            for k = i, b.spellCount - 1 do queue[k] = queue[k + 1] end
            queue[b.spellCount] = nil
            b.spellCount = b.spellCount - 1
            if i < slowAt then slowAt = slowAt - 1 end
            break
        end
    end
    PlaceQueueSpell(b, best, slowAt)
    lastCtx.rangedSwap = best
end

-- A next-swing attack (Heroic Strike) costs no global cooldown: queued now, it lands on the
-- coming swing and the GCD ability is still pressed the moment it is ready. So a lead that cannot
-- be pressed yet (a wait, or a cooldown or cost due within one GCD kept in place by the "soon"
-- rules) does not hold slot 1 over a next-swing attack that is either pressable now or already
-- queued; a queued one is in progress, the next thing that happens, shown with its swing timer.
-- It moves up to slot 1 and the waiting lead follows it.
function SpellQueue._StageSwingPress(b)
    if not (b.inCombat and BlizzardAPI.IsForever() and SpellDB and SpellDB.NEXT_SWING_SPELLS) then return end
    local queue, count = b.recommendedSpells, b.spellCount or 0
    local lead = queue[1]
    if count < 2 or type(lead) ~= "number" or lead <= 0 or SpellDB.NEXT_SWING_SPELLS[lead]
       or SpellQueue._PressableNow(lead) then
        return
    end
    for j = 2, count do
        local id = queue[j]
        if type(id) == "number" and SpellDB.NEXT_SWING_SPELLS[id] then
            local queued = BlizzardAPI.RunningAutoSwing(id) == 0
            if queued or (not sunkSet[id] and SpellQueue._PressableNow(id)) then
                for k = j, 2, -1 do queue[k] = queue[k - 1] end
                queue[1] = id
                return
            end
        end
    end
end

-- Look-ahead: a spell that carries the player to the target (SpellDB.LandsAtTarget: Charge,
-- Intercept, Feral Charge) means melee reach is coming. From our own successful cast until the
-- real melee reading confirms arrival, the target changes, or LANDING_WINDOW passes, the queue
-- orders melee abilities as they will rank on arrival instead of reshuffling as we land.
-- Ordering only: range tints still show the game's own reading.
local landing = {}
local LANDING_WINDOW = 3

function SpellQueue.NoteLandingCast(spellID)
    if not (SpellDB and SpellDB.LandsAtTarget and SpellDB.LandsAtTarget(spellID)) then return end
    local ok, guid = pcall(UnitGUID, "target")
    if not ok or BlizzardAPI.IsSecretValue(guid) or type(guid) ~= "string" then return end
    landing.at, landing.guid = GetTime(), guid
    -- What the carrier pays on arrival (Charge: rage), from the spell data.
    landing.gainType, landing.gain = nil, nil
    if SpellDB.GetEnergize then landing.gainType, landing.gain = SpellDB.GetEnergize(spellID) end
end

--- A resource gain due on landing, while the carrier is in flight: amount of powerType, or nil.
function SpellQueue._PendingGain(powerType, now)
    if landing.gainType ~= powerType or not SpellQueue._LandingInFlight(now) then return nil end
    return landing.gain
end

function SpellQueue._LandingInFlight(now)
    local at = landing.at
    if not at then return false end
    local ok, guid = pcall(UnitGUID, "target")
    if not now or now < at or now - at > LANDING_WINDOW
       or not ok or BlizzardAPI.IsSecretValue(guid) or guid ~= landing.guid
       or (SpellDB.IsTargetWithin and SpellDB.IsTargetWithin(5) == true) then
        landing.at, landing.guid, landing.gainType, landing.gain = nil, nil, nil, nil
        return false
    end
    return true
end

--- A melee-reach ability: Attack or a next-swing attack, or one whose range the client reports
--- as melee (no maximum, or 5 yards or less). Ranged spells keep their own reading.
function SpellQueue._IsMeleeReach(spellID)
    if BlizzardAPI.IsMeleeSwingSpell and BlizzardAPI.IsMeleeSwingSpell(spellID) then return true end
    local info = BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(spellID)
    if type(info) ~= "table" then return false end
    local maxRange = info.maxRange
    if BlizzardAPI.IsSecretValue(maxRange) then return false end
    return maxRange == nil or (type(maxRange) == "number" and maxRange <= 5)
end
