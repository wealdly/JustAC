-- JustAC: Spell Queue Module
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 16)
if not SpellQueue then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local C_Spell_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local tinsert = table.insert
local wipe = wipe

local spellInfoCache = {}
local cacheSize = 0
local lastSpellIDs = {}
local lastQueueUpdate = 0
local lastDisplayUpdate = 0

-- More responsive throttling
local function GetQueueThrottleInterval()
    local inCombat = UnitAffectingCombat("player")
    return inCombat and 0.03 or 0.08  -- Faster updates, especially in combat
end

local function GetDebugMode()
    return BlizzardAPI and BlizzardAPI.GetDebugMode() or false
end

local function GetProfile()
    return BlizzardAPI and BlizzardAPI.GetProfile() or nil
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

function SpellQueue.IsSpellBlacklisted(spellID, queueType)
    local profile = GetProfile()
    if not spellID or not queueType or not profile or not profile.blacklistedSpells then 
        return false 
    end

    local settings = profile.blacklistedSpells[spellID]
    if not settings then 
        return false
    end

    if queueType == "combatAssist" then
        return settings.combatAssist == true
    elseif queueType == "fixedQueue" then
        return settings.fixedQueue == true
    end

    return false
end

function SpellQueue.ToggleSpellBlacklist(spellID)
    if not spellID or spellID == 0 then return end
    local profile = GetProfile()
    if not profile then return end

    local spellInfo = SpellQueue.GetCachedSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"

    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if profile.blacklistedSpells[spellID] then
        profile.blacklistedSpells[spellID] = nil
        if addon then addon:Print("Removed " .. spellName .. " from blacklist") end
    else
        profile.blacklistedSpells[spellID] = { combatAssist = true, fixedQueue = true }
        if addon then addon:Print("Added " .. spellName .. " to blacklist") end
    end
end

function SpellQueue.GetBlacklistedSpells()
    local profile = GetProfile()
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
    local profile = GetProfile()
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

    -- Position 1: Get the spell Blizzard highlights on action bars (GetNextCastSpell)
    local primarySpellID = BlizzardAPI and BlizzardAPI.GetNextCastSpell and BlizzardAPI.GetNextCastSpell()
    
    if primarySpellID and primarySpellID > 0 then
        -- Resolve override to get displayed spell (single API call)
        local primaryOverride = C_Spell_GetOverrideSpell and C_Spell_GetOverrideSpell(primarySpellID)
        local primaryActual = (primaryOverride and primaryOverride ~= 0 and primaryOverride ~= primarySpellID) and primaryOverride or primarySpellID
        
        -- Check blacklist on DISPLAYED spell only (what user sees and shift+clicks)
        if not SpellQueue.IsSpellBlacklisted(primaryActual, "combatAssist") 
           and IsSpellAvailable(primaryActual) then
            if not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(primaryActual) then
                spellCount = spellCount + 1
                recommendedSpells[spellCount] = primaryActual
                addedSpellIDs[primaryActual] = true
                addedSpellIDs[primarySpellID] = true
            end
        end
    end

    -- Positions 2+: Get the rotation spell list (priority queue)
    -- These are additional spells Blizzard exposes, shown in JustAC's queue slots 2+
    local rotationList = BlizzardAPI and BlizzardAPI.GetRotationSpells and BlizzardAPI.GetRotationSpells()
    if rotationList then
        local rotationCount = #rotationList
        for i = 1, rotationCount do
            if spellCount >= maxIcons then break end  -- Early exit if at max
            
            local spellID = rotationList[i]
            if spellID and not addedSpellIDs[spellID] then
                -- Get the actual spell we'd display (might be an override) - single API call
                local override = C_Spell_GetOverrideSpell and C_Spell_GetOverrideSpell(spellID)
                local actualSpellID = (override and override ~= 0 and override ~= spellID) and override or spellID
                
                -- Check blacklist on DISPLAYED spell only (what user sees and shift+clicks)
                if not SpellQueue.IsSpellBlacklisted(actualSpellID, "fixedQueue")
                   and IsSpellAvailable(actualSpellID) then
                    if not RedundancyFilter or not RedundancyFilter.IsSpellRedundant(actualSpellID) then
                        spellCount = spellCount + 1
                        recommendedSpells[spellCount] = actualSpellID
                        addedSpellIDs[actualSpellID] = true
                        addedSpellIDs[spellID] = true
                    end
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
    -- Don't wipe lastSpellIDs to avoid blinking
end

function SpellQueue.OnSpecChange()
    SpellQueue.ClearSpellCache()
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