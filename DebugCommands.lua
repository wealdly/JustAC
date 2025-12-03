-- JustAC: Debug Commands Module
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 1)
if not DebugCommands then return end

function DebugCommands.FormDetection(addon)
    addon:Print("=== FORM DETECTION DEBUG ===")
    
    -- Raw WoW API calls
    local rawFormID = GetShapeshiftFormID() or 0
    local numForms = GetNumShapeshiftForms()
    addon:Print("GetShapeshiftFormID(): " .. rawFormID)
    addon:Print("GetNumShapeshiftForms(): " .. numForms)
    
    -- Check each form slot
    addon:Print("Form Analysis:")
    for i = 1, numForms do
        local icon, active, castable, spellID = GetShapeshiftFormInfo(i)
        if spellID then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or "Unknown"
            local status = active and " (ACTIVE)" or ""
            addon:Print("  Form " .. i .. ": " .. name .. " (ID:" .. spellID .. ")" .. status)
        end
    end
    
    -- FormCache comparison
    local FormCache = LibStub("JustAC-FormCache", true)
    if FormCache then
        local cacheFormID = FormCache.GetActiveForm()
        local cacheFormName = FormCache.GetActiveFormName()
        addon:Print("FormCache says:")
        addon:Print("  Current form: " .. cacheFormID .. " (" .. cacheFormName .. ")")
        
        -- Bear Form test
        local bearFormID = FormCache.GetFormIDBySpellID(5487)
        addon:Print("  Bear Form (5487) maps to: " .. tostring(bearFormID))
    else
        addon:Print("FormCache not available")
    end
    
    -- Player state
    local playerClass = select(2, UnitClass("player"))
    local isMounted = IsMounted()
    addon:Print("Player: " .. playerClass .. ", Mounted: " .. tostring(isMounted))
    
    addon:Print("=============================")
end

-- Module diagnostics
function DebugCommands.ModuleDiagnostics(addon)
    addon:Print("=== Module Diagnostics ===")
    
    -- Check all LibStub modules
    local modules = {
        {"JustAC-UIManager", "UIManager"},
        {"JustAC-SpellQueue", "SpellQueue"},
        {"JustAC-ActionBarScanner", "ActionBarScanner"},
        {"JustAC-BlizzardAPI", "BlizzardAPI"},
        {"JustAC-MacroParser", "MacroParser"},
        {"JustAC-FormCache", "FormCache"},
        {"JustAC-RedundancyFilter", "RedundancyFilter"},
        {"JustAC-Options", "Options"},
        {"JustAC-DebugCommands", "DebugCommands"},
        {"LibPlayerSpells-1.0", "LibPlayerSpells"},
    }
    
    for _, moduleInfo in ipairs(modules) do
        local libName, displayName = moduleInfo[1], moduleInfo[2]
        local module = LibStub(libName, true)
        if module then
            addon:Print("|cff00ff00✓|r " .. displayName .. " - Loaded")
            
            -- Test key functions
            if libName == "JustAC-SpellQueue" then
                local testResult = pcall(function() return module.GetCurrentSpellQueue and module.GetCurrentSpellQueue() end)
                addon:Print("  GetCurrentSpellQueue: " .. (testResult and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
            elseif libName == "JustAC-ActionBarScanner" then
                local testResult = pcall(function() return module.GetSpellHotkey and module.GetSpellHotkey(1) end)
                addon:Print("  GetSpellHotkey: " .. (testResult and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
            elseif libName == "JustAC-MacroParser" then
                local testResult = pcall(function() return module.ParseMacroForSpell and type(module.ParseMacroForSpell) == "function" end)
                addon:Print("  ParseMacroForSpell: " .. (testResult and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
            elseif libName == "JustAC-FormCache" then
                local testResult = pcall(function() return module.GetActiveForm and module.GetActiveForm() end)
                addon:Print("  GetActiveForm: " .. (testResult and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
            elseif libName == "JustAC-BlizzardAPI" then
                local testResult = pcall(function() return module.GetRotationSpells and module.GetRotationSpells() end)
                addon:Print("  GetRotationSpells: " .. (testResult and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
                
                -- Test API availability
                if module.IsAssistedCombatAvailable then
                    local isAvailable, reason = module.IsAssistedCombatAvailable()
                    addon:Print("  API Available: " .. (isAvailable and "|cff00ff00YES|r" or ("|cffff0000NO|r (" .. (reason or "unknown") .. ")")))
                end
            end
        else
            addon:Print("|cffff0000✗|r " .. displayName .. " - NOT LOADED")
        end
    end
    
    -- Check WoW API functions
    addon:Print("")
    addon:Print("WoW API Functions:")
    local wowFunctions = {
        "GetSpecialization", "GetShapeshiftFormID", "GetShapeshiftFormInfo",
        "C_AssistedCombat.GetNextCastSpell", "C_AssistedCombat.GetRotationSpells", "C_AssistedCombat.IsAvailable",
        "GetActionInfo", "HasAction", "GetBindingKey"
    }
    
    for _, funcName in ipairs(wowFunctions) do
        local func = _G
        for part in funcName:gmatch("[^.]+") do
            func = func and func[part]
        end
        addon:Print("  " .. funcName .. ": " .. (func and "|cff00ff00OK|r" or "|cffff0000MISSING|r"))
    end
    
    -- Check Critical CVars
    addon:Print("")
    addon:Print("Critical CVars:")
    local assistedMode = GetCVarBool("assistedMode")
    local assistedHighlight = GetCVarBool("assistedCombatHighlight")
    local updateRate = tonumber(GetCVar("assistedCombatIconUpdateRate")) or 0
    
    addon:Print("  assistedMode: " .. (assistedMode and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    addon:Print("  assistedCombatHighlight: " .. (assistedHighlight and "|cff00ff00ENABLED|r" or "|cffffff00DISABLED|r"))
    addon:Print("  assistedCombatIconUpdateRate: " .. tostring(updateRate))
    
    -- Check database
    addon:Print("")
    addon:Print("Database:")
    addon:Print("  Profile: " .. (addon.db and addon.db.profile and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
    addon:Print("  Debug Mode: " .. (addon.db and addon.db.profile and addon.db.profile.debugMode and "|cff00ff00ON|r" or "|cffaaaaaa OFF|r"))
    
    addon:Print("===========================")
end

-- Spell search function
function DebugCommands.FindSpell(addon, spellName)
    if not spellName or spellName == "" then
        addon:Print("Usage: /jac find <spell name>")
        return
    end
    
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    if ActionBarScanner and ActionBarScanner.FindSpellInSlots then
        ActionBarScanner.FindSpellInSlots(spellName)
    else
        addon:Print("ActionBarScanner not available")
    end
end

-- Profile management
function DebugCommands.ManageProfile(addon, profileAction)
    if not profileAction then
        addon:Print("Usage: /jac profile <n> or /jac profile list")
        return
    end
    
    if profileAction == "list" then
        local profiles = addon.db:GetProfiles()
        if profiles then
            addon:Print("Available profiles:")
            for _, name in ipairs(profiles) do
                local current = (name == addon.db:GetCurrentProfile()) and " (current)" or ""
                addon:Print("  " .. name .. current)
            end
        else
            addon:Print("No profiles available")
        end
    else
        local success, errorMsg = pcall(function() return addon.db:SetProfile(profileAction) end)
        if success then
            addon:Print("Switched to profile: " .. profileAction)
        else
            addon:Print("Profile not found: " .. profileAction)
        end
    end
end

-- Help function
function DebugCommands.ShowHelp(addon)
    addon:Print("Available commands:")
    addon:Print("/jac - Open options")
    addon:Print("/jac toggle - Pause/resume display") 
    addon:Print("/jac debug - Toggle debug mode")
    addon:Print("/jac test - Test Blizzard API functions")
    addon:Print("/jac find <spell> - Find spell on action bars")
    addon:Print("/jac form - Show form debug info")
    addon:Print("/jac formcheck - Check current form detection")
    addon:Print("/jac lps <spellID> - Show LibPlayerSpells info for spell")
    addon:Print("/jac reset - Reset frame position")
    addon:Print("/jac profile <n> - Switch profile")
    addon:Print("/jac profile list - List profiles")
    addon:Print("/jac raw - Show raw assisted combat data")
    addon:Print("/jac modules - Check module health")
end

-- LibPlayerSpells spell info lookup
function DebugCommands.LPSInfo(addon, spellIDStr)
    if not spellIDStr or spellIDStr == "" then
        addon:Print("Usage: /jac lps <spellID>")
        return
    end
    
    local spellID = tonumber(spellIDStr)
    if not spellID then
        addon:Print("Invalid spell ID: " .. spellIDStr)
        return
    end
    
    -- Get spell name from WoW
    local spellInfo = C_Spell and C_Spell.GetSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"
    
    addon:Print("=== LibPlayerSpells Info: " .. spellName .. " (" .. spellID .. ") ===")
    
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    if not RedundancyFilter or not RedundancyFilter.GetLPSInfo then
        addon:Print("|cffff0000RedundancyFilter not available|r")
        return
    end
    
    local info = RedundancyFilter.GetLPSInfo(spellID)
    
    if not info.available then
        addon:Print("|cffff0000LibPlayerSpells not loaded|r")
        return
    end
    
    if not info.known then
        addon:Print("|cffffff00Spell not in LibPlayerSpells database|r")
        return
    end
    
    -- Display flags
    local flags = {}
    if info.isAura then table.insert(flags, "|cff00ff00AURA|r") end
    if info.isUniqueAura then table.insert(flags, "|cff00ffffUNIQUE_AURA|r") end
    if info.isSurvival then table.insert(flags, "|cffff8800SURVIVAL|r") end
    if info.isBurst then table.insert(flags, "|cffff0000BURST|r") end
    if info.isCooldown then table.insert(flags, "|cff8888ffCOOLDOWN|r") end
    if info.isPet then table.insert(flags, "|cff88ff88PET|r") end
    if info.isPersonal then table.insert(flags, "|cffffcc00PERSONAL|r") end
    
    if #flags > 0 then
        addon:Print("Flags: " .. table.concat(flags, ", "))
    else
        addon:Print("Flags: (none)")
    end
    
    -- Display providers
    if info.providers then
        if type(info.providers) == "number" then
            local providerInfo = C_Spell and C_Spell.GetSpellInfo(info.providers)
            local providerName = providerInfo and providerInfo.name or "Unknown"
            addon:Print("Provider: " .. providerName .. " (" .. info.providers .. ")")
        elseif type(info.providers) == "table" then
            addon:Print("Providers:")
            for _, pID in ipairs(info.providers) do
                local pInfo = C_Spell and C_Spell.GetSpellInfo(pID)
                local pName = pInfo and pInfo.name or "Unknown"
                addon:Print("  - " .. pName .. " (" .. pID .. ")")
            end
        end
    end
    
    -- Display modifiers
    if info.modifiers then
        if type(info.modifiers) == "number" then
            local modInfo = C_Spell and C_Spell.GetSpellInfo(info.modifiers)
            local modName = modInfo and modInfo.name or "Unknown"
            addon:Print("Modifies: " .. modName .. " (" .. info.modifiers .. ")")
        elseif type(info.modifiers) == "table" then
            addon:Print("Modifies:")
            for _, mID in ipairs(info.modifiers) do
                local mInfo = C_Spell and C_Spell.GetSpellInfo(mID)
                local mName = mInfo and mInfo.name or "Unknown"
                addon:Print("  - " .. mName .. " (" .. mID .. ")")
            end
        end
    end
    
    addon:Print("Raw flags value: " .. tostring(info.flags))
    addon:Print("==========================================")
end