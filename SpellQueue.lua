-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Queue Module - Retrieves and caches the current Assisted Combat rotation
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 40)
if not SpellQueue then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)

-- Hot path cache
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local IsMounted = IsMounted
local GetShapeshiftFormID = GetShapeshiftFormID
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
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

-- Reusable pooled tables (wiped at start of each queue build to avoid GC pressure)
local proccedSpells = {}
local normalSpells = {}
local cooldownSpells = {}
local addedSpellIDs = {}
local recommendedSpells = {}

-- Per-update cache for spell filter results (cleared at start of each GetCurrentSpellQueue call)
-- Prevents re-checking the same spell multiple times per update cycle
local filterResultCache = {}
-- Separate table for rotation-filter results (avoids string concat "r_"..spellID in the hot path)
local rotationFilterCache = {}

-- Cached rotation spell list — only refreshed on RotationSpellsUpdated event
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
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return nil, nil end
    return profile.blacklistedSpells[specKey], specKey
end

local function IsBlacklistedEntry(value)
    return value == true or (type(value) == "table" and value.fixedQueue == true)
end

-- Checks both base ID and its display/override ID against the blacklist.
function SpellQueue.IsSpellBlacklisted(spellID, blacklist)
    if not spellID then return false end
    if not blacklist then blacklist = GetBlacklistTable() end
    if not blacklist then return false end
    if IsBlacklistedEntry(blacklist[spellID]) then return true end
    local displayID = BlizzardAPI.GetDisplaySpellID(spellID)
    return displayID ~= spellID and IsBlacklistedEntry(blacklist[displayID])
end

function SpellQueue.ToggleSpellBlacklist(spellID)
    if not spellID or spellID == 0 then return end
    local profile = BlizzardAPI and BlizzardAPI.GetProfile()
    if not profile then return end
    if not profile.blacklistedSpells then profile.blacklistedSpells = {} end

    local SpellDB = LibStub("JustAC-SpellDB", true)
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

function SpellQueue.GetBlacklistedSpells()
    local blacklist = GetBlacklistTable()
    if not blacklist then return {} end

    local spells = {}
    for spellID, _ in pairs(blacklist) do
        local spellInfo = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo(spellID)
        if spellInfo and spellInfo.name then
            spells[#spells + 1] = {
                id = spellID,
                name = spellInfo.name,
                icon = spellInfo.iconID
            }
        end
    end

    table.sort(spells, function(a, b) return a.name < b.name end)
    return spells
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

--- Categorize rotation spells into procced/normal/cooldown buckets and assemble
--- in priority order: proc > normal > on-cooldown.
local function CategorizeAndAssembleRotation(rotationList, profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems, bypassProcs)
    wipe(proccedSpells)
    wipe(normalSpells)
    local proccedCount, normalCount, cooldownCount = 0, 0, 0

    for i = 1, #rotationList do
        local spellID = rotationList[i]
        if spellID and not addedSpellIDs[spellID] then
            if spellID < 0 then
                -- Item entry (negative ID): use item-specific APIs.
                -- Items are only present via Custom Queue — skip spell filters.
                local itemID = -spellID
                addedSpellIDs[spellID] = true
                local isUsable, hasItem, onCooldown = BlizzardAPI.CheckDefensiveItemState(itemID)
                if hasItem then
                    if onCooldown then
                        cooldownCount = cooldownCount + 1
                        cooldownSpells[cooldownCount] = spellID
                    else
                        normalCount = normalCount + 1
                        normalSpells[normalCount] = spellID
                    end
                end
            elseif not SpellQueue.IsSpellBlacklisted(spellID, blacklist) then
                local displayID = ClaimSpellID(spellID, addedSpellIDs)
                if displayID
                   and not (hideItems and BlizzardAPI.IsItemSpell(displayID))
                   and PassesRotationFilters(displayID, profile) then
                    if not BlizzardAPI.IsSpellReady(displayID) then
                        cooldownCount = cooldownCount + 1
                        cooldownSpells[cooldownCount] = displayID
                    elseif not bypassProcs and BlizzardAPI.IsSpellProcced(displayID) then
                        proccedCount = proccedCount + 1
                        proccedSpells[proccedCount] = displayID
                    else
                        normalCount = normalCount + 1
                        normalSpells[normalCount] = displayID
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

    for i = 1, proccedCount do
        if spellCount >= maxIcons then break end
        spellCount = spellCount + 1
        recommendedSpells[spellCount] = proccedSpells[i]
    end
    for i = 1, normalCount do
        if spellCount >= maxIcons then break end
        spellCount = spellCount + 1
        recommendedSpells[spellCount] = normalSpells[i]
    end
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
    -- Internal safety throttle — main loop in JustAC.lua is the primary rate limiter
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
        wipe(lastSpellIDs)
        return lastSpellIDs
    end

    -- All visibility conditions passed: queue should be shown.
    lastShouldShowQueue = true
    lastQueueUpdate = now

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

    -- Position 1: Blizzard's primary suggestion. Blacklist applies to all positions.
    -- Hiding pos 1 can freeze the rotation — users are warned in the blacklist UI.
    local primarySpellID = BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()

    if primarySpellID and primarySpellID > 0 then
        local displaySpellID = ClaimSpellID(primarySpellID, addedSpellIDs)
        if displaySpellID
           and not SpellQueue.IsSpellBlacklisted(primarySpellID, blacklist) then
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
                   and not SpellQueue.IsSpellBlacklisted(hlSpellID, blacklist) then
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
    -- GapCloserEngine loads after SpellQueue, so we resolve it lazily.
    if spellCount < maxIcons then
        if not cachedGapCloserEngine then
            cachedGapCloserEngine = LibStub("JustAC-GapCloserEngine", true)
        end
        if not cachedAddon then
            cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        end
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

            -- Suppress gap-closers from rotation list — our injection controls placement.
            if cachedGapCloserEngine.MarkGapCloserSpellIDs then
                cachedGapCloserEngine.MarkGapCloserSpellIDs(cachedAddon, addedSpellIDs)
            end
        end
    end

    -- Burst injection: inject priority spell at position 1 when burst window is active.
    -- Two-phase: "pending" = trigger CD at pos 1 (glow only, no injection),
    --            "active"  = trigger aura on player (inject from injection list).
    -- BurstInjectionEngine loads after SpellQueue, so we resolve it lazily.
    if spellCount < maxIcons then
        if not cachedBurstEngine then
            cachedBurstEngine = LibStub("JustAC-BurstInjectionEngine", true)
        end
        if not cachedAddon then
            cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        end
        if cachedBurstEngine and cachedBurstEngine.CheckTrigger and cachedAddon then
            local burstPhase, triggerPosition = cachedBurstEngine.CheckTrigger(cachedAddon, primarySpellID, recommendedSpells)
            -- Phase "pending": trigger CD is visible in the queue. Mark it as burst so
            -- renderers can show the burst glow (signal to press it), but don't
            -- inject anything — let Blizzard's recommendation stand.
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

                    -- Suppress burst injection spells from rotation list — only when
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
        if not cachedAddon then
            cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        end
        if cachedAddon and cachedAddon.db and cachedAddon.db.profile then
            local cqProfile = cachedAddon.db.profile.customQueue
            local SpellDB = LibStub("JustAC-SpellDB", true)
            local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
            if specKey and cqProfile and cqProfile[specKey]
               and cqProfile[specKey].enabled and cqProfile[specKey].spells
               and #cqProfile[specKey].spells > 0 then
                -- Copy the user's custom spell list as the rotation source
                cachedRotationList = {}
                for i, sid in ipairs(cqProfile[specKey].spells) do
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
    if cachedRotationList then
        spellCount = CategorizeAndAssembleRotation(cachedRotationList, profile, blacklist, addedSpellIDs, recommendedSpells, spellCount, maxIcons, hideItems, bypassProcs)
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

--- Cached visibility verdict from last queue build — avoids re-evaluating per render frame.
function SpellQueue.ShouldShowQueue()
    return lastShouldShowQueue
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
    SpellQueue.ClearSpellCache()
    SpellQueue.ForceUpdate()
end

function SpellQueue.OnSpellsChanged()
    SpellQueue.ClearSpellCache()
    SpellQueue.InvalidateRotationCache()
    SpellQueue.ForceUpdate()
end

-- Invalidate the cached rotation list — called on RotationSpellsUpdated and SPELLS_CHANGED
function SpellQueue.InvalidateRotationCache()
    cachedRotationList = nil
    -- Clear rotation spell registrations; they'll be re-registered on next fetch
    if BlizzardAPI and BlizzardAPI.ClearTrackedRotationSpells then
        BlizzardAPI.ClearTrackedRotationSpells()
    end
end

