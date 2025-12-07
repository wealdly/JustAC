-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spell Queue Module
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 24)
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
local cacheSize = 0
local lastSpellIDs = {}
local lastQueueUpdate = 0
local lastDisplayUpdate = 0

-- Stabilization: prevent rapid flickering of position 1
local lastPrimarySpellID = nil
local lastPrimaryChangeTime = 0

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
    
    -- Cache miss: fetch and store
    local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(spellID) or C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return nil end
    
    -- Prevent unbounded cache growth (check before adding)
    if cacheSize >= 100 then
        SpellQueue.ClearSpellCache()
    end
    
    spellInfoCache[spellID] = spellInfo
    cacheSize = cacheSize + 1
    
    return spellInfo
end

function SpellQueue.ClearSpellCache()
    wipe(spellInfoCache)
    cacheSize = 0
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
    local profile = BlizzardAPI.GetProfile()
    if not spellID or not profile or not profile.blacklistedSpells then 
        return false 
    end

    local settings = profile.blacklistedSpells[spellID]
    return settings and settings.fixedQueue == true
end

function SpellQueue.ToggleSpellBlacklist(spellID)
    if not spellID or spellID == 0 then return end
    local profile = BlizzardAPI.GetProfile()
    if not profile then return end

    local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"

    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if profile.blacklistedSpells[spellID] then
        profile.blacklistedSpells[spellID] = nil
        if addon and addon.DebugPrint then addon:DebugPrint("Unblacklisted: " .. spellName) end
    else
        profile.blacklistedSpells[spellID] = { fixedQueue = true }
        if addon and addon.DebugPrint then addon:DebugPrint("Blacklisted: " .. spellName) end
    end
end

function SpellQueue.GetBlacklistedSpells()
    local profile = BlizzardAPI.GetProfile()
    if not profile then return {} end
    
    local spells = {}
    for spellID, _ in pairs(profile.blacklistedSpells or {}) do
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

    local recommendedSpells = {}
    local addedSpellIDs = {}
    local maxIcons = profile.maxIcons or 10
    local spellCount = 0
    
    -- Check if stabilization is needed (only when includeHiddenAbilities is on)
    local useStabilization = profile.includeHiddenAbilities or false

    -- Position 1: Get the spell Blizzard highlights on action bars (GetNextCastSpell)
    -- NEVER filter position 1 - this is Blizzard's primary recommendation
    local primarySpellID = BlizzardAPI and BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()
    
    if primarySpellID and primarySpellID > 0 then
        local baseSpellID = primarySpellID
        
        -- Stabilization: prevent rapid flickering when includeHiddenAbilities is on
        -- Keep showing previous spell unless: proc fired, old spell on cooldown, or window expired
        if useStabilization and lastPrimarySpellID and lastPrimarySpellID ~= baseSpellID then
            local stabilizationWindow = profile.stabilizationWindow or 0.50
            if (now - lastPrimaryChangeTime) < stabilizationWindow then
                local newSpellProcced = BlizzardAPI.IsSpellProcced(baseSpellID)
                local oldSpellOnCooldown = false
                if BlizzardAPI and BlizzardAPI.GetSpellCooldown then
                    local start, duration = BlizzardAPI.GetSpellCooldown(lastPrimarySpellID)
                    oldSpellOnCooldown = start and start > 0 and duration and duration > 1.5
                end
                if not newSpellProcced and not oldSpellOnCooldown then
                    baseSpellID = lastPrimarySpellID
                end
            end
        end
        
        -- Track base spell for stabilization
        if baseSpellID ~= lastPrimarySpellID then
            lastPrimarySpellID = baseSpellID
            lastPrimaryChangeTime = now
        end
        
        -- Resolve override once for display (handles morphed spells like Metamorphosis)
        local displaySpellID = BlizzardAPI.GetDisplaySpellID(baseSpellID)
        
        -- Position 1 is always shown - no filtering
        spellCount = spellCount + 1
        recommendedSpells[spellCount] = displaySpellID
        addedSpellIDs[displaySpellID] = true
        addedSpellIDs[baseSpellID] = true
    else
        -- No spell recommended - clear stabilization state
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
                    -- Apply filters: must be offensive, have keybind, not blacklisted, available, not redundant
                    if BlizzardAPI.IsOffensiveSpell(procSpellID)
                       and ActionBarScanner.HasKeybind(procSpellID)
                       and not SpellQueue.IsSpellBlacklisted(procSpellID)
                       and IsSpellAvailable(procSpellID)
                       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(procSpellID)) then
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
    -- Apply all filters: no duplicates of position 1, blacklist, availability, redundancy
    -- Procced spells are prioritized and moved to the front of the queue
    local rotationList = BlizzardAPI and BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()
    if rotationList then
        -- Reuse pooled tables to avoid GC pressure (paired arrays for base/display spell IDs)
        wipe(proccedBase)
        wipe(proccedDisplay)
        wipe(normalBase)
        wipe(normalDisplay)
        local proccedCount, normalCount = 0, 0
        local rotationCount = #rotationList
        
        -- First pass: categorize spells into procced vs normal
        for i = 1, rotationCount do
            local spellID = rotationList[i]
            if spellID and not addedSpellIDs[spellID] then
                -- Get the actual spell we'd display (might be an override)
                local actualSpellID = BlizzardAPI.GetDisplaySpellID(spellID)
                
                -- Skip if this override already shown (e.g., position 1 has same spell)
                if not addedSpellIDs[actualSpellID] then
                    -- Apply filters: blacklist, availability, redundancy
                    if not SpellQueue.IsSpellBlacklisted(actualSpellID)
                       and IsSpellAvailable(actualSpellID)
                       and (not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(actualSpellID)) then
                        -- Categorize by proc state
                        if BlizzardAPI.IsSpellProcced(actualSpellID) then
                            proccedCount = proccedCount + 1
                            proccedBase[proccedCount] = spellID
                            proccedDisplay[proccedCount] = actualSpellID
                        else
                            normalCount = normalCount + 1
                            normalBase[normalCount] = spellID
                            normalDisplay[normalCount] = actualSpellID
                        end
                    end
                end
            end
        end
        
        -- Second pass: add procced spells first, then normal spells
        for i = 1, proccedCount do
            if spellCount >= maxIcons then break end
            spellCount = spellCount + 1
            recommendedSpells[spellCount] = proccedDisplay[i]
            addedSpellIDs[proccedDisplay[i]] = true
            addedSpellIDs[proccedBase[i]] = true
        end
        
        -- Only process normal spells if we still have room
        if spellCount < maxIcons then
            for i = 1, normalCount do
                if spellCount >= maxIcons then break end
                spellCount = spellCount + 1
                recommendedSpells[spellCount] = normalDisplay[i]
                addedSpellIDs[normalDisplay[i]] = true
                addedSpellIDs[normalBase[i]] = true
            end
        end
    end

    lastSpellIDs = recommendedSpells
    return recommendedSpells
end

function SpellQueue.ForceUpdate()
    lastQueueUpdate = 0
    lastDisplayUpdate = 0
    -- Don't wipe lastSpellIDs to avoid blinking
end

function SpellQueue.OnSpecChange()
    SpellQueue.ClearSpellCache()
    if BlizzardAPI.ClearSpellTypeCache then
        BlizzardAPI.ClearSpellTypeCache()
    end
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