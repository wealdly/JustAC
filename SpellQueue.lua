-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Queue Module - Retrieves and caches the current Assisted Combat rotation
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 37)
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

-- NOTE: Local spell info cache was removed — now delegates to BlizzardAPI.GetCachedSpellInfo()

local lastSpellIDs = {}
local lastQueueUpdate = 0
-- Cached visibility verdict from GetCurrentSpellQueue(); read by UIRenderer via ShouldShowQueue().
-- Avoids re-evaluating the same mount/healer/OOC conditions every render frame.
local lastShouldShowQueue = true

-- Lazy-resolved references for gap-closer (GapCloserEngine loads after SpellQueue in TOC)
local cachedGapCloserEngine = nil
local cachedAddon = nil

-- Spells injected by JustAC systems (gap-closers, etc.) that should always show proc glow.
-- Populated per queue build, consumed by UIRenderer.IsSpellProcced.
local syntheticProcs = {}

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

function SpellQueue.GetCachedSpellInfo(spellID)
    return BlizzardAPI and BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(spellID) or nil
end

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

function SpellQueue.IsSpellBlacklisted(spellID)
    local charData = BlizzardAPI.GetCharData()
    if not spellID or not charData or not charData.blacklistedSpells then
        return false
    end
    -- Simplified format: blacklistedSpells[spellID] = true
    -- Also handle legacy format: { fixedQueue = true }
    local value = charData.blacklistedSpells[spellID]
    return value == true or (type(value) == "table" and value.fixedQueue == true)
end

function SpellQueue.ToggleSpellBlacklist(spellID)
    if not spellID or spellID == 0 then return end
    local charData = BlizzardAPI.GetCharData()
    if not charData then return end
    
    if not charData.blacklistedSpells then
        charData.blacklistedSpells = {}
    end

    local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"

    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if charData.blacklistedSpells[spellID] then
        charData.blacklistedSpells[spellID] = nil
        if addon and addon.DebugPrint then addon:DebugPrint("Unblacklisted: " .. spellName) end
    else
        charData.blacklistedSpells[spellID] = true  -- Simplified format
        if addon and addon.DebugPrint then addon:DebugPrint("Blacklisted: " .. spellName) end
    end
    
    local Options = LibStub("JustAC-Options", true)
    if Options and Options.UpdateBlacklistOptions and addon then
        Options.UpdateBlacklistOptions(addon)
    end
end

function SpellQueue.GetBlacklistedSpells()
    local charData = BlizzardAPI.GetCharData()
    if not charData then return {} end
    
    local spells = {}
    for spellID, _ in pairs(charData.blacklistedSpells or {}) do
        local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
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

-- Wrapper to BlizzardAPI.IsSpellAvailable
local function IsSpellAvailable(spellID)
    return BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID) or false
end

-- Wrapper to BlizzardAPI.IsSpellUsable - checks if spell can be cast (resources, cooldown, etc.)
-- Fail-open: return true if API is unavailable to show max helpful spells
-- PERFORMANCE: Removed expensive cooldown filtering - the cooldown swipe already shows this visually
local function IsSpellUsable(spellID)
    if not BlizzardAPI or not BlizzardAPI.IsSpellUsable then
        return true  -- Fail-open if API unavailable
    end
    -- Just check basic usability, skip expensive cooldown checks
    -- The renderer's cooldown swipe already shows if a spell is on cooldown
    local isUsable, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID)
    return isUsable
end

-- Helper: Check if spell passes common filters (availability, usability, redundancy)
-- Used for position 1 and spell-book proc spells — includes usability (resources, CD) check.
-- Uses per-update cache to avoid re-checking the same spell multiple times.
local function PassesSpellFilters(spellID, profile)
    -- Check cache first (valid for this update cycle only)
    local cached = filterResultCache[spellID]
    if cached ~= nil then
        return cached
    end

    -- Compute result
    local result = IsSpellAvailable(spellID)
       and IsSpellUsable(spellID)
       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(spellID, profile))

    filterResultCache[spellID] = result
    return result
end

-- Lighter filter for rotation list positions 2+ and defensive queue spells.
-- Does NOT check IsSpellUsable or IsSpellReady: most cooldown info is secreted
-- in 12.0 combat (GetSpellCooldown duration/startTime are secret). isOnGCD has
-- three NeverSecret states: true=GCD only (ready), false=real CD (flagged spells
-- like Judgment/BoJ/Wake only), nil=ambiguous (off CD OR unflagged on CD).
-- Since isOnGCD==false only covers Blizzard-flagged rotation builders, not major
-- CDs, filtering here would be partial. Local cooldown tracking
-- (via UNIT_SPELLCAST_SUCCEEDED) is handled separately in the categorization
-- pass to de-prioritize (not filter) on-CD spells.
local function PassesRotationFilters(spellID, profile)
    local cached = rotationFilterCache[spellID]
    if cached ~= nil then
        return cached
    end

    local result = IsSpellAvailable(spellID)
       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(spellID, profile))

    rotationFilterCache[spellID] = result
    return result
end

function SpellQueue.GetCurrentSpellQueue()
    local profile = BlizzardAPI.GetProfile()
    if not profile or profile.isManualMode then
        return lastSpellIDs or {}
    end

    local now = GetTime()
    -- Compute inCombat once; reused for both the throttle interval and all visibility checks below.
    -- 0.05s in combat = 20 updates/sec; 0.12s out of combat when timing is less critical.
    local inCombat = UnitAffectingCombat("player")
    local throttleInterval = inCombat and 0.05 or 0.12

    if now - lastQueueUpdate < throttleInterval then
        return lastSpellIDs or {}
    end
    
    -- Check if queue should be hidden based on settings
    if profile.hideQueueOutOfCombat and not inCombat then
        lastShouldShowQueue = false
        lastQueueUpdate = now
        return lastSpellIDs or {}
    end
    
    if profile.hideQueueWhenMounted then
        local isMounted = IsMounted()
        if not isMounted then
            local formID = GetShapeshiftFormID()
            if formID == 3 or formID == 27 then  -- Druid Travel/Flight Form
                isMounted = true
            end
        end
        if isMounted then
            lastShouldShowQueue = false
            lastQueueUpdate = now
            return lastSpellIDs or {}
        end
    end
    
    if profile.requireHostileTarget and not inCombat then
        local hasHostileTarget = UnitExists("target") and UnitCanAttack("player", "target")
        if not hasHostileTarget then
            lastShouldShowQueue = false
            lastQueueUpdate = now
            return lastSpellIDs or {}
        end
    end

    -- All visibility conditions passed: queue should be shown.
    lastShouldShowQueue = true
    lastQueueUpdate = now

    -- PERFORMANCE: Clear per-update caches at start of each update cycle
    wipe(filterResultCache)
    wipe(rotationFilterCache)
    if BlizzardAPI.ClearProcCache then
        BlizzardAPI.ClearProcCache()
    end
    
    -- Check if proc detection is blocked by secret values
    local bypassProcs = BlizzardAPI and BlizzardAPI.IsProcFeatureAvailable
        and not BlizzardAPI.IsProcFeatureAvailable() or false
    
    -- Reuse pooled tables to avoid GC pressure
    wipe(recommendedSpells)
    wipe(addedSpellIDs)
    wipe(syntheticProcs)
    wipe(cooldownSpells)
    local maxIcons = profile.maxIcons or 10
    local spellCount = 0
    
    local hideItems = profile.hideItemAbilities

    -- Position 1: Get the spell Blizzard highlights on action bars (GetNextCastSpell)
    -- By default, position 1 is never filtered — Blizzard's single-button assistant
    -- won't advance until this spell is cast; hiding it freezes the entire rotation.
    -- Optional: blacklistPosition1 applies the blacklist to position 1 as well.
    local primarySpellID = BlizzardAPI and BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()
    
    if primarySpellID and primarySpellID > 0 then
        local displaySpellID = BlizzardAPI.GetDisplaySpellID(primarySpellID)
        local blacklisted = profile.blacklistPosition1
            and (SpellQueue.IsSpellBlacklisted(primarySpellID) or SpellQueue.IsSpellBlacklisted(displaySpellID))

        if not blacklisted then
            addedSpellIDs[displaySpellID] = true
            addedSpellIDs[primarySpellID] = true

            spellCount = spellCount + 1
            recommendedSpells[spellCount] = displaySpellID
        end
    end

    -- Gap-closer injection.
    -- Promote gap closer to position 1: the primary spell is out of range so
    -- the gap closer is always the correct first action.  Existing spells shift
    -- right to make room.
    -- Skip entirely if position 1 is already a gap closer (Blizzard's assisted
    -- combat system can suggest gap closers like Charge as the primary spell).
    -- GapCloserEngine loads after SpellQueue in the TOC, so we resolve it lazily.
    if spellCount < maxIcons then
        if not cachedGapCloserEngine then
            cachedGapCloserEngine = LibStub("JustAC-GapCloserEngine", true)
        end
        if not cachedAddon then
            cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
        end
        if cachedGapCloserEngine and cachedGapCloserEngine.GetGapCloserSpell and cachedAddon then
            -- If position 1 is already a gap closer, skip injection entirely
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
                        -- Promote gap closer to position 1: the primary spell is
                        -- out of range so you can't cast it — the gap closer is
                        -- always the correct first action.
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

            -- Suppress ALL gap-closer spells from the rotation list (positions 2+).
            -- When the gap-closer system is enabled, our insertion controls when
            -- these spells appear — letting them leak into the rotation causes
            -- duplicates or inconsistent position changes.
            if cachedGapCloserEngine.MarkGapCloserSpellIDs then
                cachedGapCloserEngine.MarkGapCloserSpellIDs(cachedAddon, addedSpellIDs)
            end
        end
    end

    -- Check for procced spells from spellbook that aren't in the rotation list
    -- These should be shown immediately after position 1 (e.g., Fel Blade procs)
    -- Only enabled if showSpellbookProcs setting is on
    if profile.showSpellbookProcs then
        local spellbookProcs = ActionBarScanner and ActionBarScanner.GetSpellbookProccedSpells and ActionBarScanner.GetSpellbookProccedSpells()
        if spellbookProcs then
            for _, procSpellID in ipairs(spellbookProcs) do
                if spellCount >= maxIcons then break end
                
                -- Get display spell ID to check for duplicates (handles overrides)
                local displayProcSpellID = BlizzardAPI.GetDisplaySpellID(procSpellID)
                
                if procSpellID and not addedSpellIDs[procSpellID] and not addedSpellIDs[displayProcSpellID] then
                    -- Filter: offensive, keybind, not blacklisted, not item, passes availability/usability/redundancy
                    local isItemSpell = hideItems and BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(procSpellID)
                    if BlizzardAPI.IsOffensiveSpell(procSpellID)
                       and ActionBarScanner.HasKeybind(procSpellID)
                       and not SpellQueue.IsSpellBlacklisted(procSpellID)
                       and not SpellQueue.IsSpellBlacklisted(displayProcSpellID)
                       and not isItemSpell
                       and PassesSpellFilters(procSpellID, profile) then
                        spellCount = spellCount + 1
                        recommendedSpells[spellCount] = procSpellID
                        -- Track both base and display IDs to prevent duplicates
                        addedSpellIDs[procSpellID] = true
                        addedSpellIDs[displayProcSpellID] = true
                    end
                end
            end
        end
    end

    -- Positions 2+: Get the rotation spell list (priority queue)
    -- These are additional spells Blizzard exposes, shown in JustAC's queue slots 2+
    -- Apply all filters: no duplicates of position 1, blacklist, availability, usability, redundancy
    -- Procced spells are prioritized and moved to the front of the queue
    -- PERFORMANCE: Use cached rotation list; only refreshed via InvalidateRotationCache()
    if not cachedRotationList and BlizzardAPI and BlizzardAPI.GetRotationSpells then
        cachedRotationList = BlizzardAPI.GetRotationSpells()
        -- Register rotation spells for local cooldown tracking (spells with base CD > 3s)
        if cachedRotationList and BlizzardAPI.RegisterRotationSpell then
            for i = 1, #cachedRotationList do
                local sid = cachedRotationList[i]
                if sid then
                    BlizzardAPI.RegisterRotationSpell(sid)
                    -- Also register the display/override spell ID
                    local displaySid = BlizzardAPI.GetDisplaySpellID(sid)
                    if displaySid and displaySid ~= sid then
                        BlizzardAPI.RegisterRotationSpell(displaySid)
                    end
                end
            end
        end
    end
    local rotationList = cachedRotationList
    if rotationList then
        wipe(proccedSpells)
        wipe(normalSpells)
        local proccedCount, normalCount, cooldownCount = 0, 0, 0
        local rotationCount = #rotationList

        -- First pass: categorize into procced (priority), normal, and on-cooldown (deprioritized)
        for i = 1, rotationCount do
            local spellID = rotationList[i]
            if spellID and not addedSpellIDs[spellID] then
                if not SpellQueue.IsSpellBlacklisted(spellID) then
                    local actualSpellID = BlizzardAPI.GetDisplaySpellID(spellID)

                    if not addedSpellIDs[actualSpellID] then
                        local isItemSpell = hideItems and BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(actualSpellID)
                        if not SpellQueue.IsSpellBlacklisted(actualSpellID)
                           and not isItemSpell
                           and PassesRotationFilters(actualSpellID, profile) then
                            addedSpellIDs[actualSpellID] = true
                            addedSpellIDs[spellID] = true

                            -- Check local cooldown tracking (spells with base CD > 3s)
                            local isOnLocalCD = BlizzardAPI and BlizzardAPI.IsSpellOnLocalCooldown
                                and BlizzardAPI.IsSpellOnLocalCooldown(actualSpellID)
                            if isOnLocalCD then
                                cooldownCount = cooldownCount + 1
                                cooldownSpells[cooldownCount] = actualSpellID
                            else
                                local isProcced = not bypassProcs and BlizzardAPI.IsSpellProcced(actualSpellID)
                                if isProcced then
                                    proccedCount = proccedCount + 1
                                    proccedSpells[proccedCount] = actualSpellID
                                else
                                    normalCount = normalCount + 1
                                    normalSpells[normalCount] = actualSpellID
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Second pass: append procced first, then normal, then on-cooldown (deprioritized)
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
        -- On-cooldown spells last (de-prioritized, not filtered)
        for i = 1, cooldownCount do
            if spellCount >= maxIcons then break end
            spellCount = spellCount + 1
            recommendedSpells[spellCount] = cooldownSpells[i]
        end
    end

    -- Copy to lastSpellIDs (separate table so wipe(recommendedSpells) doesn't destroy cached results)
    wipe(lastSpellIDs)
    for i = 1, spellCount do
        lastSpellIDs[i] = recommendedSpells[i]
    end
    return lastSpellIDs
end

function SpellQueue.ForceUpdate()
    lastQueueUpdate = 0
end

--- Returns the cached visibility verdict from the last GetCurrentSpellQueue() build.
--- True when all profile conditions (OOC, healer, mounted, hostile target) allow display.
--- UIRenderer reads this instead of re-evaluating the same conditions every render frame.
function SpellQueue.ShouldShowQueue()
    return lastShouldShowQueue
end

--- Returns true if spellID was injected as a synthetic proc (gap-closer, etc.)
--- by the most recent GetCurrentSpellQueue() call.
function SpellQueue.IsSyntheticProc(spellID)
    return syntheticProcs[spellID] == true
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

