-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Queue Module v30
-- Changed: Added usability filtering for queue positions 2+ (cooldown/resource checks)
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 30)
if not SpellQueue then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local wipe = wipe
local type = type

local spellInfoCache = {}
local lastSpellIDs = {}
local lastQueueUpdate = 0
local lastDisplayUpdate = 0

-- Primary spell stabilization to prevent flicker during rapid transitions
-- Holds the primary spell briefly if the new one matches what was just in slot 2
local lastPrimarySpellID = nil
local lastPrimaryChangeTime = 0
local PRIMARY_STABILIZATION_WINDOW = 0.05  -- 50ms - very tight, just enough to smooth GCD transitions

-- Reusable tables to avoid GC pressure in hot loop
-- Using paired arrays: proccedBase[i]/proccedDisplay[i] for base/display spell IDs
local proccedBase = {}
local proccedDisplay = {}
local normalBase = {}
local normalDisplay = {}

-- Throttle interval for queue updates
-- 0.1s in combat = 10 updates/sec (fast enough for responsiveness, slow enough to reduce flicker)
-- 0.15s out of combat = slightly more relaxed when timing doesn't matter
local function GetQueueThrottleInterval()
    local inCombat = UnitAffectingCombat("player")
    return inCombat and 0.10 or 0.15
end

function SpellQueue.GetCachedSpellInfo(spellID)
    if not spellID or spellID == 0 then return nil end
    
    -- Fast path: return cached value
    local cached = spellInfoCache[spellID]
    if cached then return cached end
    
    -- Cache miss: fetch and store (unbounded is fine, spell IDs per character are finite ~200 max)
    local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(spellID) or C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return nil end
    
    spellInfoCache[spellID] = spellInfo
    return spellInfo
end

function SpellQueue.ClearSpellCache()
    wipe(spellInfoCache)
end

function SpellQueue.ClearAvailabilityCache()
    if BlizzardAPI and BlizzardAPI.ClearAvailabilityCache then
        BlizzardAPI.ClearAvailabilityCache()
    end
end

function SpellQueue.CompareSpellArrays(arr1, arr2)
    if arr1 == arr2 then return true end
    if not arr1 or not arr2 then return false end
    
    local len1, len2 = #arr1, #arr2
    if len1 ~= len2 then return false end
    if len1 == 0 then return true end
    
    for i = 1, len1 do
        if arr1[i] ~= arr2[i] then return false end
    end
    return true
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
    
    -- Refresh options panel if open
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
-- Returns true if usable OR if API unavailable (fail-open)
local function IsSpellUsable(spellID)
    if not BlizzardAPI or not BlizzardAPI.IsSpellUsable then
        return true  -- Fail-open if API unavailable
    end
    local isUsable, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID)
    -- Also check cooldown - don't show spells with >2s real cooldown remaining (ignore GCD)
    if isUsable and BlizzardAPI.IsSpellOnRealCooldown then
        if BlizzardAPI.IsSpellOnRealCooldown(spellID) then
            -- Use GetSpellCooldownValues which sanitizes secrets to 0
            local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)
            if start and start > 0 and duration and duration > 0 then
                local remaining = (start + duration) - GetTime()
                if remaining > 2.0 then  -- Hide if more than 2s remaining on real cooldown
                    return false
                end
            end
        end
    end
    return isUsable
end

-- Helper: Check if either base or display spell ID is blacklisted
local function IsSpellOrDisplayBlacklisted(baseSpellID, displaySpellID)
    return SpellQueue.IsSpellBlacklisted(displaySpellID) or 
           (baseSpellID ~= displaySpellID and SpellQueue.IsSpellBlacklisted(baseSpellID))
end

function SpellQueue.GetCurrentSpellQueue()
    local profile = BlizzardAPI.GetProfile()
    if not profile or profile.isManualMode then 
        return lastSpellIDs or {}
    end

    local now = GetTime()
    local throttleInterval = GetQueueThrottleInterval()
    
    -- More responsive throttling - don't skip updates as much
    if now - lastQueueUpdate < throttleInterval then
        return lastSpellIDs or {}
    end
    lastQueueUpdate = now
    
    -- Early check: determine which features are bypassed due to secrets
    -- bypassProcs is used for proc categorization in the rotation list
    local flags = BlizzardAPI and BlizzardAPI.GetBypassFlags and BlizzardAPI.GetBypassFlags() or {}
    local bypassProcs = flags.bypassProcs or false
    
    local recommendedSpells = {}
    local addedSpellIDs = {}
    local maxIcons = profile.maxIcons or 10
    local spellCount = 0
    
    -- Cache hideItemAbilities setting for this update
    local hideItems = profile.hideItemAbilities

    -- Position 1: Get the spell Blizzard highlights on action bars (GetNextCastSpell)
    -- ALWAYS apply blacklist - if slot 1 is blacklisted, rotation spells shift up to fill it
    local primarySpellID = BlizzardAPI and BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()
    
    if primarySpellID and primarySpellID > 0 then
        local baseSpellID = primarySpellID
        
        -- Resolve override once for display (handles morphed spells like Metamorphosis)
        local displaySpellID = BlizzardAPI.GetDisplaySpellID(baseSpellID)
        
        -- Check blacklist and item filter - ALWAYS apply, rotation spells will shift up if filtered
        local isBlacklisted = IsSpellOrDisplayBlacklisted(baseSpellID, displaySpellID)
        local isItemSpell = hideItems and BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(displaySpellID)
        local shouldFilter = isBlacklisted or isItemSpell
        
        if shouldFilter then
            -- Filtered spell - don't add to queue, rotation spells will fill slot 1
            -- Reset stabilization so we don't try to hold a filtered spell
            if lastPrimarySpellID == displaySpellID or lastPrimarySpellID == baseSpellID then
                lastPrimarySpellID = nil
                lastPrimaryChangeTime = 0
            end
            -- Track to prevent duplicates in rotation list (we don't want it anywhere)
            addedSpellIDs[displaySpellID] = true
            addedSpellIDs[baseSpellID] = true
        else
            -- Not blacklisted - apply minimal stabilization
            -- If primary changed to what was slot 2, hold briefly to smooth transition
            local previousSlot2 = lastSpellIDs and lastSpellIDs[2]
            if displaySpellID ~= lastPrimarySpellID then
                -- Primary changed
                if previousSlot2 and displaySpellID == previousSlot2 then
                    -- New primary matches old slot 2 - this is a "shift up" after execution
                    -- Hold the previous primary briefly to smooth the transition
                    -- But only if the previous primary is not blacklisted
                    local prevBlacklisted = lastPrimarySpellID and SpellQueue.IsSpellBlacklisted(lastPrimarySpellID)
                    if (now - lastPrimaryChangeTime) < PRIMARY_STABILIZATION_WINDOW and lastPrimarySpellID and not prevBlacklisted then
                        -- Still in stabilization window, use previous primary
                        displaySpellID = lastPrimarySpellID
                        baseSpellID = lastPrimarySpellID  -- Keep consistent
                    else
                        -- Stabilization window passed, first change, or prev was blacklisted
                        lastPrimarySpellID = displaySpellID
                        lastPrimaryChangeTime = now
                    end
                else
                    -- Different change (not a shift-up), accept immediately
                    lastPrimarySpellID = displaySpellID
                    lastPrimaryChangeTime = now
                end
            end
            
            -- Track to prevent duplicates in rotation list
            addedSpellIDs[displaySpellID] = true
            addedSpellIDs[baseSpellID] = true
            
            -- Position 1 is shown
            spellCount = spellCount + 1
            recommendedSpells[spellCount] = displaySpellID
        end
    else
        -- No primary spell, reset stabilization tracking
        lastPrimarySpellID = nil
        lastPrimaryChangeTime = 0
    end

    -- Check for procced spells from spellbook that aren't in the rotation list
    -- These should be shown immediately after position 1 (e.g., Fel Blade procs)
    -- Only enabled if showSpellbookProcs setting is on
    if profile.showSpellbookProcs then
        local spellbookProcs = ActionBarScanner and ActionBarScanner.GetSpellbookProccedSpells and ActionBarScanner.GetSpellbookProccedSpells()
        if spellbookProcs then
            for _, procSpellID in ipairs(spellbookProcs) do
                if spellCount >= maxIcons then break end
                if procSpellID and not addedSpellIDs[procSpellID] then
                    -- Apply filters: must be offensive, have keybind, not blacklisted, not item (if hiding), available, usable
                    -- Always check redundancy - form/stance checks work even when aura secrets detected
                    local isItemSpell = hideItems and BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(procSpellID)
                    if BlizzardAPI.IsOffensiveSpell(procSpellID)
                       and ActionBarScanner.HasKeybind(procSpellID)
                       and not SpellQueue.IsSpellBlacklisted(procSpellID)
                       and not isItemSpell
                       and IsSpellAvailable(procSpellID)
                       and IsSpellUsable(procSpellID)
                       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(procSpellID, profile)) then
                        spellCount = spellCount + 1
                        recommendedSpells[spellCount] = procSpellID
                        addedSpellIDs[procSpellID] = true
                    end
                end
            end
        end
    end

    -- Positions 2+: Get the rotation spell list (priority queue)
    -- These are additional spells Blizzard exposes, shown in JustAC's queue slots 2+
    -- Apply all filters: no duplicates of position 1, blacklist, availability, usability, redundancy
    -- Procced spells are prioritized and moved to the front of the queue
    local rotationList = BlizzardAPI and BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()
    if rotationList then
        -- Reuse pooled tables to avoid GC pressure (paired arrays for base/display spell IDs)
        -- Split procced into important vs regular for priority sorting
        wipe(proccedBase)
        wipe(proccedDisplay)
        wipe(normalBase)
        wipe(normalDisplay)
        local importantProccedCount, regularProccedCount, normalCount = 0, 0, 0
        local rotationCount = #rotationList
        
        -- First pass: categorize spells into important procs, regular procs, and normal
        for i = 1, rotationCount do
            local spellID = rotationList[i]
            if spellID and not addedSpellIDs[spellID] then
                -- Early blacklist check on base spell ID (before GetDisplaySpellID call)
                if not SpellQueue.IsSpellBlacklisted(spellID) then
                    -- Get the actual spell we'd display (might be an override)
                    local actualSpellID = BlizzardAPI.GetDisplaySpellID(spellID)
                    
                    -- Skip if this override already shown (e.g., position 1 has same spell)
                    if not addedSpellIDs[actualSpellID] then
                        -- Apply filters: blacklist (display ID), item filter, availability, usability, redundancy
                        -- Always check redundancy - form/stance checks work even when aura secrets detected
                        -- IsSpellRedundant handles internal bypass logic for aura-dependent checks
                        local isItemSpell = hideItems and BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(actualSpellID)
                        if not SpellQueue.IsSpellBlacklisted(actualSpellID)
                           and not isItemSpell
                           and IsSpellAvailable(actualSpellID)
                           and IsSpellUsable(actualSpellID)
                           and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(actualSpellID, profile)) then
                            -- Mark as added NOW to prevent duplicates within the rotation list
                            -- (e.g., same actualSpellID from different base spell IDs)
                            addedSpellIDs[actualSpellID] = true
                            addedSpellIDs[spellID] = true
                            
                            -- Categorize by proc state and importance
                            -- Proc detection bypassed independently if proc secrets detected
                            -- When bypassed, all spells go to "normal" category (Blizzard's order)
                            local isProcced = not bypassProcs and BlizzardAPI.IsSpellProcced(actualSpellID)
                            if isProcced then
                                -- IMPORTANT procs go to front of procced list
                                if BlizzardAPI.IsImportantSpell(actualSpellID) then
                                    importantProccedCount = importantProccedCount + 1
                                    -- Insert at front by shifting (rare, usually 0-2 important procs)
                                    for j = importantProccedCount, 2, -1 do
                                        proccedBase[j] = proccedBase[j - 1]
                                        proccedDisplay[j] = proccedDisplay[j - 1]
                                    end
                                    proccedBase[1] = spellID
                                    proccedDisplay[1] = actualSpellID
                                else
                                    regularProccedCount = regularProccedCount + 1
                                    local idx = importantProccedCount + regularProccedCount
                                    proccedBase[idx] = spellID
                                    proccedDisplay[idx] = actualSpellID
                                end
                            else
                                normalCount = normalCount + 1
                                normalBase[normalCount] = spellID
                                normalDisplay[normalCount] = actualSpellID
                            end
                        end
                    end
                end
            end
        end
        
        local proccedCount = importantProccedCount + regularProccedCount
        
        -- Second pass: add procced spells first (IMPORTANT ones are already at front), then normal
        -- Note: addedSpellIDs already updated in first pass, no need to update again
        -- Extra safety check: verify no duplicates slip through (shouldn't happen but failsafe)
        for i = 1, proccedCount do
            if spellCount >= maxIcons then break end
            local spellToAdd = proccedDisplay[i]
            -- Paranoid duplicate check (should already be in addedSpellIDs)
            if not recommendedSpells[1] or spellToAdd ~= recommendedSpells[1] then
                spellCount = spellCount + 1
                recommendedSpells[spellCount] = spellToAdd
            end
        end
        
        -- Only process normal spells if we still have room
        if spellCount < maxIcons then
            for i = 1, normalCount do
                if spellCount >= maxIcons then break end
                local spellToAdd = normalDisplay[i]
                -- Paranoid duplicate check against position 1
                if not recommendedSpells[1] or spellToAdd ~= recommendedSpells[1] then
                    spellCount = spellCount + 1
                    recommendedSpells[spellCount] = spellToAdd
                end
            end
        end
    end

    lastSpellIDs = recommendedSpells
    return recommendedSpells
end

function SpellQueue.ForceUpdate()
    lastQueueUpdate = 0
    lastDisplayUpdate = 0
    -- Reset stabilization to allow immediate response
    lastPrimarySpellID = nil
    lastPrimaryChangeTime = 0
    -- Don't wipe lastSpellIDs to avoid blinking
end

function SpellQueue.OnSpecChange()
    SpellQueue.ClearSpellCache()
    -- Reset stabilization for new spec
    lastPrimarySpellID = nil
    lastPrimaryChangeTime = 0
    SpellQueue.ForceUpdate()
end

function SpellQueue.OnSpellsChanged()
    SpellQueue.ClearSpellCache()
    SpellQueue.ForceUpdate()
end

-- Debug function for testing
function SpellQueue.ShowAssistedCombatRaw()
    print("|JAC| === Raw Assisted Combat Data ===")
    
    local primarySpell = BlizzardAPI and BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()
    local rotationSpells = BlizzardAPI and BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()
    
    print("|JAC| Primary Spell: " .. tostring(primarySpell))
    if primarySpell and primarySpell > 0 then
        local spellInfo = SpellQueue.GetCachedSpellInfo(primarySpell)
        if spellInfo then
            print("|JAC|   Name: " .. spellInfo.name)
        end
    end
    
    print("|JAC| Rotation Spells:")
    if rotationSpells and #rotationSpells > 0 then
        for i, spellID in ipairs(rotationSpells) do
            local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or "Unknown"
            print("|JAC|   " .. i .. ": " .. name .. " (" .. spellID .. ")")
        end
    else
        print("|JAC|   None")
    end
    
    local currentQueue = SpellQueue.GetCurrentSpellQueue()
    print("|JAC| Current Queue:")
    if currentQueue and #currentQueue > 0 then
        for i, spellID in ipairs(currentQueue) do
            local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or "Unknown"
            print("|JAC|   " .. i .. ": " .. name .. " (" .. spellID .. ")")
        end
    else
        print("|JAC|   Empty")
    end
    
    print("|JAC| ================================")
end