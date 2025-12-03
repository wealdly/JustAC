-- JustAC: Blizzard API Module
local BlizzardAPI = LibStub:NewLibrary("JustAC-BlizzardAPI", 10)
if not BlizzardAPI then return end

-- Hot path optimizations: cache frequently used functions
local GetTime = GetTime
local pcall = pcall
local type = type
local wipe = wipe

-- Cached addon reference (resolved lazily)
local cachedAddon = nil
local function GetAddon()
    if not cachedAddon then
        cachedAddon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    end
    return cachedAddon
end

-- Shared profile access (used by all JustAC modules)
function BlizzardAPI.GetProfile()
    local addon = GetAddon()
    if not addon or not addon.db then return nil end
    return addon.db.profile
end

-- Shared debug mode check (used by all JustAC modules)
function BlizzardAPI.GetDebugMode()
    local profile = BlizzardAPI.GetProfile()
    return profile and profile.debugMode or false
end

-- Local aliases for internal use
local function GetDebugMode()
    return BlizzardAPI.GetDebugMode()
end

-- Wrapper with fallback to legacy GetSpellInfo
function BlizzardAPI.GetSpellInfo(spellID)
    if not spellID or spellID == 0 then return nil end
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(spellID) end
    local name, _, icon = GetSpellInfo(spellID)
    if name then return {name = name, iconID = icon} end
    return nil
end

-- Returns spell ID from C_AssistedCombat highlight (checkForVisibleButton=true)
function BlizzardAPI.GetNextCastSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return nil end
    
    -- Use checkForVisibleButton = true (like Blizzard does for highlights)
    local success, result = pcall(C_AssistedCombat.GetNextCastSpell, true)
    if success and result and type(result) == "number" and result > 0 then
        return result
    end
    return nil
end

function BlizzardAPI.GetRotationSpells()
    if not C_AssistedCombat or not C_AssistedCombat.GetRotationSpells then return nil end
    
    local success, result = pcall(C_AssistedCombat.GetRotationSpells)
    if success and result and type(result) == "table" and #result > 0 then
        -- Validate all entries are valid spell IDs
        for i = 1, #result do
            if type(result[i]) ~= "number" or result[i] <= 0 then 
                return nil 
            end
        end
        return result
    end
    return nil
end

function BlizzardAPI.IsAssistedCombatAvailable()
    if not C_AssistedCombat or not C_AssistedCombat.IsAvailable then return false, "API not available" end
    
    local success, isAvailable, failureReason = pcall(C_AssistedCombat.IsAvailable)
    if success then
        return isAvailable, failureReason
    end
    return false, "API call failed"
end

function BlizzardAPI.HasAssistedCombatActionButtons()
    if not C_ActionBar or not C_ActionBar.HasAssistedCombatActionButtons then return false end
    
    local success, result = pcall(C_ActionBar.HasAssistedCombatActionButtons)
    return success and result or false
end

function BlizzardAPI.GetActionInfo(slot)
    if not slot or not HasAction(slot) then return nil, nil, nil, nil end

    local actionType, id, subType, spell_id_from_macro = GetActionInfo(slot)

    -- Filter out assistedcombat string IDs (like Blizzard does)
    if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
        return nil, nil, nil, nil
    end

    return actionType, id, subType, spell_id_from_macro
end

-- Check if the system is properly configured
function BlizzardAPI.ValidateAssistedCombatSetup()
    local debugMode = GetDebugMode()
    local issues = {}
    
    -- Check API availability
    local isAvailable, failureReason = BlizzardAPI.IsAssistedCombatAvailable()
    if not isAvailable then
        issues[#issues + 1] = "Assisted Combat not available: " .. (failureReason or "unknown reason")
    end
    
    -- Check CVars
    local assistedMode = GetCVarBool("assistedMode")
    if not assistedMode then
        issues[#issues + 1] = "assistedMode CVar is disabled (try: /console assistedMode 1)"
    end
    
    local assistedHighlight = GetCVarBool("assistedCombatHighlight")
    if not assistedHighlight then
        issues[#issues + 1] = "assistedCombatHighlight CVar is disabled (try: /console assistedCombatHighlight 1)"
    end
    
    -- Check action buttons
    local hasActionButtons = BlizzardAPI.HasAssistedCombatActionButtons()
    if not hasActionButtons then
        issues[#issues + 1] = "No assisted combat action buttons found"
    end
    
    -- Check if we can get rotation spells
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells or #rotationSpells == 0 then
        issues[#issues + 1] = "No rotation spells returned (may be normal out of combat)"
    end
    
    if debugMode then
        if #issues == 0 then
            print("|JAC| Assisted Combat setup validation: ALL GOOD")
        else
            print("|JAC| Assisted Combat setup validation: " .. #issues .. " issues found")
            for i, issue in ipairs(issues) do
                print("|JAC|   " .. i .. ". " .. issue)
            end
        end
    end
    
    return #issues == 0, issues
end

-- Enhanced debug function that matches Blizzard's approach
function BlizzardAPI.TestAssistedCombatAPI()
    print("|JAC| === Assisted Combat API Test (Blizzard-Style) ===")
    
    -- Check basic availability
    local isAvailable, failureReason = BlizzardAPI.IsAssistedCombatAvailable()
    print("|JAC| IsAvailable: " .. tostring(isAvailable) .. " (" .. (failureReason or "no reason") .. ")")
    
    -- Check player state
    local inCombat = UnitAffectingCombat("player")
    local spec = GetSpecialization()
    local level = UnitLevel("player")
    local class = select(2, UnitClass("player"))
    
    print("|JAC| Player State:")
    print("|JAC|   Class: " .. tostring(class))
    print("|JAC|   Level: " .. tostring(level))
    print("|JAC|   Spec: " .. tostring(spec))
    print("|JAC|   In Combat: " .. tostring(inCombat))
    
    -- Check CVars (critical for system to work)
    local assistedMode = GetCVarBool("assistedMode")
    local assistedHighlight = GetCVarBool("assistedCombatHighlight")
    local updateRate = tonumber(GetCVar("assistedCombatIconUpdateRate")) or 0
    
    print("|JAC| CVars:")
    print("|JAC|   assistedMode: " .. tostring(assistedMode))
    print("|JAC|   assistedCombatHighlight: " .. tostring(assistedHighlight))
    print("|JAC|   assistedCombatIconUpdateRate: " .. tostring(updateRate))
    
    -- Check action button system
    local hasActionButtons = BlizzardAPI.HasAssistedCombatActionButtons()
    print("|JAC| HasAssistedCombatActionButtons: " .. tostring(hasActionButtons))
    
    -- Test rotation spells
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if rotationSpells and #rotationSpells > 0 then
        print("|JAC| Current rotation spells: " .. #rotationSpells .. " entries")
        for i = 1, math.min(#rotationSpells, 5) do
            local spellInfo = BlizzardAPI.GetSpellInfo(rotationSpells[i])
            local name = spellInfo and spellInfo.name or "Unknown"
            print("|JAC|   " .. i .. ": " .. name .. " (" .. tostring(rotationSpells[i]) .. ")")
        end
        if #rotationSpells > 5 then
            print("|JAC|   ... and " .. (#rotationSpells - 5) .. " more")
        end
    else
        print("|JAC| No rotation spells returned")
    end
    
    -- Test next cast spell (using correct parameter)
    local nextCastSpell = BlizzardAPI.GetNextCastSpell()
    if nextCastSpell then
        local spellInfo = BlizzardAPI.GetSpellInfo(nextCastSpell)
        local name = spellInfo and spellInfo.name or "Unknown"
        print("|JAC| GetNextCastSpell(true): " .. name .. " (" .. tostring(nextCastSpell) .. ")")
    else
        print("|JAC| GetNextCastSpell(true): No spell")
    end
    
    -- Validation summary
    local isValid, issues = BlizzardAPI.ValidateAssistedCombatSetup()
    print("|JAC| System Status: " .. (isValid and "READY" or "NEEDS SETUP"))
    
    if not isValid then
        print("|JAC| Setup Issues:")
        for i, issue in ipairs(issues) do
            print("|JAC|   " .. i .. ". " .. issue)
        end
        print("|JAC| Quick Fix Commands:")
        print("|JAC|   /console assistedMode 1")
        print("|JAC|   /console assistedCombatHighlight 1")
        print("|JAC|   /reload")
    end
    
    print("|JAC| =====================================")
end

function BlizzardAPI.GetSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(spellID)
        if cd then
            return cd.startTime or 0, cd.duration or 0
        end
    elseif C_SpellBook and C_SpellBook.GetSpellCooldown then
        return C_SpellBook.GetSpellCooldown(spellID)
    elseif GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
    -- fallback
    return 0, 0
end

--------------------------------------------------------------------------------
-- 12.0 (Midnight) Compatibility Utilities
-- These functions prepare for WoW 12.0 "Secret Values" system
--------------------------------------------------------------------------------

-- Check if a value is a "secret" (opaque) value in 12.0+
-- Returns false on pre-12.0 clients where issecretvalue doesn't exist
function BlizzardAPI.IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

-- Check if we can access/compare a value (not secret, or we have untainted access)
-- Returns true on pre-12.0 clients
function BlizzardAPI.CanAccessValue(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end
    return true
end

-- Check if current execution context can access secrets
-- Returns true on pre-12.0 clients
function BlizzardAPI.CanAccessSecrets()
    if canaccesssecrets then
        return canaccesssecrets()
    end
    return true
end

-- Safely compare two values, handling secrets
-- Returns nil if comparison not possible due to secrets
function BlizzardAPI.SafeCompare(a, b)
    if BlizzardAPI.IsSecretValue(a) or BlizzardAPI.IsSecretValue(b) then
        return nil  -- Can't compare secrets
    end
    return a == b
end

-- Get the WoW interface version to detect 12.0+
function BlizzardAPI.GetInterfaceVersion()
    local version = select(4, GetBuildInfo())
    return version or 0
end

-- Spell availability cache (checks if spell is known/castable)
local spellAvailabilityCache = {}
local spellAvailabilityCacheTime = 0
local AVAILABILITY_CACHE_DURATION = 2.0

function BlizzardAPI.ClearAvailabilityCache()
    wipe(spellAvailabilityCache)
    spellAvailabilityCacheTime = 0
end

-- Check if a spell is actually known/available to the player (cached)
function BlizzardAPI.IsSpellAvailable(spellID)
    if not spellID or spellID == 0 then return false end
    
    -- Check cache first (hot path)
    local now = GetTime()
    if now - spellAvailabilityCacheTime < AVAILABILITY_CACHE_DURATION then
        local cached = spellAvailabilityCache[spellID]
        if cached ~= nil then
            return cached
        end
    else
        -- Cache expired, clear it
        wipe(spellAvailabilityCache)
        spellAvailabilityCacheTime = now
    end
    
    -- Fast path: check if spell is in spellbook first (most common case for known spells)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        if C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end
    
    -- Check IsSpellKnown (fast API call)
    if IsSpellKnown then
        if IsSpellKnown(spellID) then
            spellAvailabilityCache[spellID] = true
            return true
        end
        -- Also check pet spells
        if IsSpellKnown(spellID, true) then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end
    
    -- Check override spells (morphed abilities like Metamorphosis)
    if C_Spell and C_Spell.GetOverrideSpell then
        local override = C_Spell.GetOverrideSpell(spellID)
        if override and override ~= spellID then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end
    
    -- Now do slower checks - filter out passives
    if C_Spell and C_Spell.IsSpellPassive then
        local isPassive = C_Spell.IsSpellPassive(spellID)
        if isPassive then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end
    
    -- Also check spell subtext for "Passive" as backup
    if C_Spell and C_Spell.GetSpellSubtext then
        local subtext = C_Spell.GetSpellSubtext(spellID)
        if subtext and subtext:lower():find("passive") then
            spellAvailabilityCache[spellID] = false
            return false
        end
    end
    
    -- Fallback: if we can get spell info, assume Blizzard filtered correctly
    if C_Spell and C_Spell.GetSpellInfo then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name then
            spellAvailabilityCache[spellID] = true
            return true
        end
    end
    
    spellAvailabilityCache[spellID] = false
    return false
end

-- Check if we're running on 12.0+ (Midnight)
function BlizzardAPI.IsMidnightOrLater()
    return BlizzardAPI.GetInterfaceVersion() >= 120000
end

-- Get player health as percentage (0-100), returns nil if secrets block access
-- Safe for 12.0: UnitHealth/UnitHealthMax don't return secrets for player units
function BlizzardAPI.GetPlayerHealthPercent()
    if not UnitExists("player") then return nil end
    
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    
    -- Handle potential secrets in 12.0+ (fail-safe)
    if BlizzardAPI.IsSecretValue(health) or BlizzardAPI.IsSecretValue(maxHealth) then
        return nil
    end
    
    if not BlizzardAPI.CanAccessValue(health) or not BlizzardAPI.CanAccessValue(maxHealth) then
        return nil
    end
    
    if not maxHealth or maxHealth == 0 then return 100 end
    return (health / maxHealth) * 100
end