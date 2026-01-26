-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Debug Commands Module
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 8)
if not DebugCommands then return end

function DebugCommands.FormDetection(addon)
    addon:Print("=== FORM DETECTION DEBUG ===")
    
    -- Raw WoW API calls
    local rawFormID = GetShapeshiftFormID() or 0
    local numForms = GetNumShapeshiftForms()
    addon:Print("GetShapeshiftFormID(): " .. rawFormID)
    addon:Print("GetNumShapeshiftForms(): " .. numForms)
    
    -- Check each form slot with spell ID details
    addon:Print("Form Analysis (stance bar spell IDs):")
    for i = 1, numForms do
        local icon, active, castable, spellID = GetShapeshiftFormInfo(i)
        if spellID then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or "Unknown"
            local status = active and " |cff00ff00(ACTIVE)|r" or ""
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
        
        -- Test common form spell IDs
        addon:Print("Spell ID -> Form ID mappings:")
        local testSpells = {
            {768, "Cat Form (rotation ID)"},
            {783, "Travel Form"},
            {5487, "Bear Form"},
            {24858, "Moonkin Form"},
            {197625, "Moonkin Form (Feral)"},
        }
        for _, test in ipairs(testSpells) do
            local spellID, desc = test[1], test[2]
            local formID = FormCache.GetFormIDBySpellID(spellID)
            local color = formID and "|cff00ff00" or "|cffff0000"
            addon:Print("  " .. desc .. " (" .. spellID .. ") -> " .. color .. tostring(formID) .. "|r")
        end
        
        -- Show RedundancyFilter's view
        local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
        if RedundancyFilter and RedundancyFilter.IsSpellRedundant then
            addon:Print("Redundancy check (would spell be filtered?):")
            for _, test in ipairs(testSpells) do
                local spellID, desc = test[1], test[2]
                local isRedundant = RedundancyFilter.IsSpellRedundant(spellID)
                local color = isRedundant and "|cff00ff00YES|r" or "|cffff0000NO|r"
                addon:Print("  " .. desc .. ": " .. color)
            end
        end
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
    
    -- Check 12.0+ Feature Availability (Secret Value handling)
    -- Each secret type tracked independently
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI and BlizzardAPI.GetFeatureAvailability then
        addon:Print("")
        addon:Print("Feature Availability (12.0+ Secrets):")
        local features = BlizzardAPI.GetFeatureAvailability()
        addon:Print("  Health API (Defensives): " .. (features.healthAccess and "|cff00ff00OK|r" or "|cffff6600SECRET|r"))
        addon:Print("  Aura API (Redundancy):   " .. (features.auraAccess and "|cff00ff00OK|r" or "|cffff6600SECRET|r"))
        addon:Print("  Cooldown API (Display):  " .. (features.cooldownAccess and "|cff00ff00OK|r" or "|cffff6600SECRET|r"))
        addon:Print("  Proc API (Prioritize):   " .. (features.procAccess and "|cff00ff00OK|r" or "|cffff6600SECRET|r"))
        
        -- Show bypass states for queue filtering (use centralized helper)
        local flags = BlizzardAPI.GetBypassFlags and BlizzardAPI.GetBypassFlags() or {}
        local bypassSlot1 = flags.bypassSlot1Blacklist or (flags.bypassRedundancy or flags.bypassProcs)
        local bypassRedundancy = flags.bypassRedundancy or false
        local bypassProcs = flags.bypassProcs or false
        addon:Print("")
        addon:Print("Queue Bypass States:")
        addon:Print("  Slot 1 Blacklist: " .. (bypassSlot1 and "|cffffff00BYPASSED|r" or "|cff00ff00ACTIVE|r"))
        addon:Print("  Redundancy Filter: " .. (bypassRedundancy and "|cffffff00BYPASSED|r" or "|cff00ff00ACTIVE|r"))
        addon:Print("  Proc Prioritization: " .. (bypassProcs and "|cffffff00BYPASSED|r" or "|cff00ff00ACTIVE|r"))
        
        if BlizzardAPI.IsMidnightOrLater then
            addon:Print("")
            addon:Print("  Interface Version: " .. (BlizzardAPI.GetInterfaceVersion and BlizzardAPI.GetInterfaceVersion() or "?"))
            addon:Print("  Midnight (12.0+): " .. (BlizzardAPI.IsMidnightOrLater() and "|cffffff00YES|r" or "NO"))
        end
    end
    
    addon:Print("===========================")
end

-- Spell search function
function DebugCommands.FindSpell(addon, spellName)
    if not spellName or spellName == "" then
        addon:Print("Usage: /jac find <spell name>")
        return
    end
    
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local MacroParser = LibStub("JustAC-MacroParser", true)
    
    addon:Print("=== Searching for: " .. spellName .. " ===")
    
    -- First, try to get spell info
    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellName)
    if spellInfo then
        addon:Print("Spell ID: " .. spellInfo.spellID .. " | Name: " .. spellInfo.name)
        
        -- Clear the cache for this spell so we get a fresh lookup
        if ActionBarScanner and ActionBarScanner.ClearSpellHotkeyCache then
            ActionBarScanner.ClearSpellHotkeyCache(spellInfo.spellID)
            addon:Print("(Cache cleared for fresh lookup)")
        end
    else
        addon:Print("Could not find spell info for: " .. spellName)
    end
    
    local lowerSpellName = spellName:lower()
    local foundAnything = false
    
    for slot = 1, 180 do
        if HasAction(slot) then
            local actionType, actionID, subType, macroSpellID = GetActionInfo(slot)
            
            -- Check direct spells
            if actionType == "spell" and actionID then
                local slotSpellInfo = C_Spell.GetSpellInfo(actionID)
                if slotSpellInfo and slotSpellInfo.name and slotSpellInfo.name:lower():find(lowerSpellName, 1, true) then
                    local key = GetBindingKey("ACTIONBUTTON" .. slot) or GetBindingKey("ACTIONBUTTON" .. ((slot - 1) % 12 + 1))
                    addon:Print("DIRECT SPELL slot " .. slot .. ": " .. slotSpellInfo.name .. " (key: " .. tostring(key or "none") .. ")")
                    foundAnything = true
                end
            end
            
            -- Check macros - use MacroParser as the primary check, not simple string.find
            if actionType == "macro" then
                local macroName = GetActionText(slot)
                if macroName then
                    local name, icon, body = GetMacroInfo(macroName)
                    if body and MacroParser and spellInfo then
                        -- Use MacroParser as the authoritative check
                        local parsedEntry = MacroParser.GetMacroSpellInfo(slot, spellInfo.spellID, spellInfo.name)
                        if parsedEntry and parsedEntry.found then
                            local key = GetBindingKey("ACTIONBUTTON" .. slot) or GetBindingKey("ACTIONBUTTON" .. ((slot - 1) % 12 + 1))
                            addon:Print("MACRO slot " .. slot .. ": '" .. macroName .. "' |cff00ff00CASTS|r '" .. spellName .. "'")
                            addon:Print("  macroSpellID from GetActionInfo: " .. tostring(macroSpellID))
                            addon:Print("  subType: " .. tostring(subType))
                            addon:Print("  key: " .. tostring(key or "none"))
                            addon:Print("  |cff00ff00MacroParser: MATCH|r (score: " .. tostring(parsedEntry.qualityScore) .. ")")
                            foundAnything = true
                        elseif body:lower():find(lowerSpellName, 1, true) then
                            -- String found but MacroParser says NO MATCH - likely a false positive
                            local key = GetBindingKey("ACTIONBUTTON" .. slot) or GetBindingKey("ACTIONBUTTON" .. ((slot - 1) % 12 + 1))
                            addon:Print("MACRO slot " .. slot .. ": '" .. macroName .. "' |cffff8800MENTIONS|r '" .. spellName .. "' (not in /cast line)")
                            addon:Print("  key: " .. tostring(key or "none"))
                            addon:Print("  |cffff0000MacroParser: NO MATCH|r (spell not in a castable line)")
                            foundAnything = true
                        end
                    elseif body and body:lower():find(lowerSpellName, 1, true) then
                        -- MacroParser not available, fall back to simple string find
                        local key = GetBindingKey("ACTIONBUTTON" .. slot) or GetBindingKey("ACTIONBUTTON" .. ((slot - 1) % 12 + 1))
                        addon:Print("MACRO slot " .. slot .. ": '" .. macroName .. "' contains '" .. spellName .. "' (MacroParser unavailable)")
                        addon:Print("  key: " .. tostring(key or "none"))
                        foundAnything = true
                    end
                end
            end
        end
    end
    
    if not foundAnything then
        addon:Print("No matches found")
    end
    
    -- Test ActionBarScanner.GetSpellHotkey directly with verbose debug
    if spellInfo and ActionBarScanner and ActionBarScanner.GetSpellHotkey then
        addon:Print("")
        addon:Print("ActionBarScanner.GetSpellHotkey(" .. spellInfo.spellID .. "):")
        
        -- Enable verbose debug for this call only
        if ActionBarScanner.SetVerboseDebug then
            ActionBarScanner.SetVerboseDebug(true)
        end
        
        local hotkey = ActionBarScanner.GetSpellHotkey(spellInfo.spellID)
        
        -- Disable verbose debug
        if ActionBarScanner.SetVerboseDebug then
            ActionBarScanner.SetVerboseDebug(false)
        end
        
        if hotkey and hotkey ~= "" then
            addon:Print("  Result: '" .. hotkey .. "'")
        else
            addon:Print("  Result: (empty/nil)")
        end
    end
    
    addon:Print("=============================")
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
    addon:Print("/jac macrotest <name> - Test macro parsing")
    addon:Print("/jac macrodump <name> - Dump raw macro body")
    addon:Print("/jac lps <spellID> - Show native spell classification for spell")
    addon:Print("/jac reset - Reset frame position")
    addon:Print("/jac profile <n> - Switch profile")
    addon:Print("/jac profile list - List profiles")
    addon:Print("/jac raw - Show raw assisted combat data")
    addon:Print("/jac modules - Check module health")
    addon:Print("/jac blacklist - Show blacklisted spells")
    addon:Print("/jac overrides - Show hotkey overrides")
    addon:Print("/jac rawdata - Show raw saved data (for debugging)")
    addon:Print("/jac defensive - Diagnose defensive icon system")

end

-- Show blacklisted spells
function DebugCommands.ShowBlacklist(addon)
    local charData = addon.db and addon.db.char
    if not charData then
        addon:Print("No character data loaded")
        return
    end
    
    local blacklist = charData.blacklistedSpells
    if not blacklist then
        addon:Print("Blacklist table is nil")
        return
    end
    
    addon:Print("=== Blacklisted Spells (Character-Specific) ===")
    local count = 0
    for spellID, data in pairs(blacklist) do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local name = spellInfo and spellInfo.name or "Unknown"
        addon:Print(string.format("  [%s] %s = %s", tostring(spellID), name, tostring(data)))
        count = count + 1
    end
    addon:Print("Total: " .. count .. " spells")
end

-- Show hotkey overrides
function DebugCommands.ShowOverrides(addon)
    local charData = addon.db and addon.db.char
    if not charData then
        addon:Print("No character data loaded")
        return
    end
    
    local overrides = charData.hotkeyOverrides
    if not overrides then
        addon:Print("Overrides table is nil")
        return
    end
    
    addon:Print("=== Hotkey Overrides (Character-Specific) ===")
    local count = 0
    for spellID, hotkey in pairs(overrides) do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local name = spellInfo and spellInfo.name or "Unknown"
        addon:Print(string.format("  [%s] %s = '%s'", tostring(spellID), name, tostring(hotkey)))
        count = count + 1
    end
    addon:Print("Total: " .. count .. " overrides")
end

-- Show raw saved data for debugging key types
function DebugCommands.ShowRawData(addon)
    local charData = addon.db and addon.db.char
    if not charData then
        addon:Print("No character data loaded")
        return
    end
    
    addon:Print("=== Raw Saved Data Debug (Character-Specific) ===")
    
    -- Blacklist
    addon:Print("Blacklist:")
    local blacklist = charData.blacklistedSpells or {}
    local blCount = 0
    for key, value in pairs(blacklist) do
        local keyType = type(key)
        local valueType = type(value)
        addon:Print(string.format("  key=%s (%s), value=%s (%s)", 
            tostring(key), keyType, tostring(value), valueType))
        blCount = blCount + 1
    end
    if blCount == 0 then addon:Print("  (empty)") end
    
    -- Hotkey overrides
    addon:Print("Hotkey Overrides:")
    local overrides = charData.hotkeyOverrides or {}
    local hkCount = 0
    for key, value in pairs(overrides) do
        local keyType = type(key)
        local valueType = type(value)
        addon:Print(string.format("  key=%s (%s), value=%s (%s)", 
            tostring(key), keyType, tostring(value), valueType))
        hkCount = hkCount + 1
    end
    if hkCount == 0 then addon:Print("  (empty)") end
end

-- Defensive system diagnostics
function DebugCommands.DefensiveDiagnostics(addon)
    addon:Print("=== Defensive System Diagnostics ===")
    
    local profile = addon:GetProfile()
    if not profile then
        addon:Print("|cffff0000ERROR: No profile loaded|r")
        return
    end
    
    -- Check defensive settings
    addon:Print("")
    addon:Print("Settings:")
    local defSettings = profile.defensives or {}
    addon:Print("  Enabled: " .. (defSettings.enabled and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    addon:Print("  Show Only In Combat: " .. (defSettings.showOnlyInCombat and "YES" or "NO"))
    addon:Print("  Position: " .. (defSettings.position or "LEFT"))
    
    -- Health Bar (module removed/abandoned)
    addon:Print("")
    addon:Print("Health Bar:")
    addon:Print("  Status: |cffff0000ABANDONED|r")
    addon:Print("  Module: |cffff0000NOT LOADED|r")
    

    
    -- Check defensive icon status
    addon:Print("")
    addon:Print("Defensive Icon:")
    if addon.defensiveIcon then
        addon:Print("  Frame: |cff00ff00EXISTS|r")
        addon:Print("  Visible: " .. (addon.defensiveIcon:IsShown() and "|cff00ff00YES|r" or "NO"))
        addon:Print("  Alpha: " .. string.format("%.2f", addon.defensiveIcon:GetAlpha()))
        addon:Print("  CurrentID: " .. tostring(addon.defensiveIcon.currentID or "nil"))
        addon:Print("  IsItem: " .. tostring(addon.defensiveIcon.isItem or false))
    else
        addon:Print("  Frame: |cffff0000NOT CREATED|r (this is the bug!)")
    end
    
    -- Check UIFrameFactory getter
    local UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
    if UIFrameFactory and UIFrameFactory.GetDefensiveIcon then
        local factoryIcon = UIFrameFactory.GetDefensiveIcon()
        addon:Print("  Factory icon: " .. (factoryIcon and "|cff00ff00EXISTS|r" or "|cffff0000nil|r"))
    end
    
    -- Check BlizzardAPI health access
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("")
    addon:Print("Health API:")
    if BlizzardAPI then
        local healthAvail = BlizzardAPI.IsDefensivesFeatureAvailable and BlizzardAPI.IsDefensivesFeatureAvailable()
        addon:Print("  Feature Available: " .. (healthAvail and "|cff00ff00YES|r" or "|cffff0000NO (secrets)|r"))
        
        local healthPct = BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
        addon:Print("  Current Health: " .. (healthPct and string.format("%.1f%%", healthPct) or "|cffff0000nil|r"))
        
        local petPct = BlizzardAPI.GetPetHealthPercent and BlizzardAPI.GetPetHealthPercent()
        addon:Print("  Pet Health: " .. (petPct and string.format("%.1f%%", petPct) or "N/A"))
    else
        addon:Print("  |cffff0000BlizzardAPI not loaded|r")
    end
    
    -- Check combat status
    addon:Print("")
    addon:Print("Combat Status:")
    local inCombat = UnitAffectingCombat("player")
    addon:Print("  In Combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))
    
    -- Check spell lists
    addon:Print("")
    addon:Print("Configured Spells:")
    
    local function PrintSpellList(name, list)
        if not list or #list == 0 then
            addon:Print("  " .. name .. ": (empty)")
            return
        end
        addon:Print("  " .. name .. ":")
        for i, spellID in ipairs(list) do
            if spellID and spellID > 0 then
                local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                local knownStr = isKnown and "|cff00ff00✓|r" or "|cffff0000✗|r"
                addon:Print("    " .. i .. ". " .. knownStr .. " " .. name .. " (" .. spellID .. ")")
            end
        end
    end
    
    PrintSpellList("Self-Heals", defSettings.selfHealSpells)
    PrintSpellList("Cooldowns", defSettings.cooldownSpells)
    PrintSpellList("Pet Heals", defSettings.petHealSpells)
    
    -- Test what would show right now (secret-safe)
    addon:Print("")
    addon:Print("Current Decision:")

    -- Helper: safe percent formatter that handles secret values
    local function fmtPercent(p)
        if not p then return "|cffff0000nil|r" end
        if issecretvalue and issecretvalue(p) then return "|cffff0000SECRET|r" end
        if type(p) == "number" then return string.format("%.1f%%", p) end
        return tostring(p)
    end

    -- Prefer procs first (would be shown at any health)
    local procSpell = addon.GetProccedDefensiveSpell and addon:GetProccedDefensiveSpell()
    if procSpell then
        local sname = C_Spell.GetSpellInfo and select(1, C_Spell.GetSpellInfo(procSpell)) or tostring(procSpell)
        addon:Print("  Result: Would show |cff00ff00PROC|r (" .. sname .. ")")
    elseif not defSettings.enabled then
        addon:Print("  Result: |cffff0000DISABLED|r")
    elseif defSettings.showOnlyInCombat and not inCombat then
        addon:Print("  Result: |cffffff00HIDDEN (out of combat, 'only in combat' enabled)|r")
    else
        -- Use LowHealthFrame estimation when exact percent is secret
        local low, crit = false, false
        if BlizzardAPI and BlizzardAPI.GetLowHealthState then
            low, crit = BlizzardAPI.GetLowHealthState()
        end

        if crit then
            addon:Print("  Result: Would show |cffff0000COOLDOWN|r (critical health)")
        elseif low then
            addon:Print("  Result: Would show |cffffff00SELF-HEAL|r (low health)")
        else
            local maybePct = BlizzardAPI and BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
            addon:Print("  Result: |cff00ff00HIDDEN|r (health " .. fmtPercent(maybePct) .. ")")
        end
    end

    addon:Print("======================================")
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
    
    addon:Print("=== Spell Classification: " .. spellName .. " (" .. spellID .. ") ===")
    
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    if not RedundancyFilter or not RedundancyFilter.GetSpellClassification then
        addon:Print("|cffff0000RedundancyFilter not available|r")
        return
    end
    
    local info = RedundancyFilter.GetSpellClassification(spellID)
    
    if not info.known then
        addon:Print("|cffffff00Spell not classified|r")
        return
    end
    
    -- Display classification source
    addon:Print("Source: |cff00ff00" .. (info.source or "native") .. "|r (12.0 compliant)")
    
    -- Display flags using native classification
    local flags = {}
    if info.isRaidBuff then table.insert(flags, "|cff00ff00RAID_BUFF|r") end
    if info.isPetSummon then table.insert(flags, "|cff88ff88PET_SUMMON|r") end
    if info.isAura then table.insert(flags, "|cff8888ffAURA|r") end
    if info.isPersonalAura then table.insert(flags, "|cffffcc00PERSONAL|r") end
    if info.isUniqueAura then table.insert(flags, "|cff88aaffUNIQUE|r") end
    if info.isRoguePoison then table.insert(flags, "|cff00ff88POISON|r") end
    if info.isWeaponEnchant then table.insert(flags, "|cffff8800WEAPON_ENCHANT|r") end
    if info.isDPSRelevant then table.insert(flags, "|cffff0000DPS_RELEVANT|r") end
    
    if #flags > 0 then
        addon:Print("Flags: " .. table.concat(flags, ", "))
    else
        addon:Print("Flags: (none - will be allowed through filters)")
    end
    
    -- Additional info for forms
    if FormCache then
        local formID = FormCache.GetFormIDBySpellID(spellID)
        if formID then
            addon:Print("Form ID: |cff00ffff" .. formID .. "|r (maps to stance bar)")
        end
    end
    
    addon:Print("==========================================")
end

-- Test macro parsing for a specific spell
function DebugCommands.TestMacroParsing(addon, macroName)
    if not macroName or macroName == "" then
        addon:Print("Usage: /jac macrotest <macro name>")
        addon:Print("Tests how MacroParser handles the named macro")
        return
    end
    
    local MacroParser = LibStub("JustAC-MacroParser", true)
    local FormCache = LibStub("JustAC-FormCache", true)
    
    if not MacroParser then
        addon:Print("MacroParser module not available")
        return
    end
    
    -- Get macro body
    local name, icon, body = GetMacroInfo(macroName)
    if not name or not body then
        addon:Print("Macro not found: " .. macroName)
        return
    end
    
    addon:Print("=== Macro Parse Test: " .. name .. " ===")
    addon:Print("Body:")
    for line in body:gmatch("[^\r\n]+") do
        addon:Print("  " .. line)
    end
    
    -- Show current state
    local currentSpec = GetSpecialization() or 0
    local currentForm = FormCache and FormCache.GetActiveForm() or 0
    local inCombat = UnitAffectingCombat("player")
    local inStealth = IsStealthed and IsStealthed() or false
    
    addon:Print("")
    addon:Print("Current State:")
    addon:Print("  Spec: " .. currentSpec)
    addon:Print("  Form: " .. currentForm)
    addon:Print("  Combat: " .. tostring(inCombat))
    addon:Print("  Stealth: " .. tostring(inStealth))
    
    -- Test parsing against current queue
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    if SpellQueue and SpellQueue.GetCurrentSpellQueue then
        local queue = SpellQueue.GetCurrentSpellQueue()
        if queue and #queue > 0 then
            addon:Print("")
            addon:Print("Testing against current queue:")
            for i, spellEntry in ipairs(queue) do
                -- Handle both formats: simple spell ID or spell entry table
                local spellID, spellName
                if type(spellEntry) == "number" then
                    spellID = spellEntry
                    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                    spellName = spellInfo and spellInfo.name or "Unknown"
                else
                    spellID = spellEntry.spellID or spellEntry
                    spellName = spellEntry.spellName or "Unknown"
                end
                
                local found, modifiers = MacroParser.ParseMacroForSpell(body, spellID, spellName)
                local status = found and "|cff00ff00MATCH|r" or "|cffff0000NO MATCH|r"
                addon:Print("  " .. i .. ". " .. spellName .. " (" .. spellID .. "): " .. status)
                if found and modifiers then
                    for k, v in pairs(modifiers) do
                        addon:Print("      modifier: " .. k .. " = " .. tostring(v))
                    end
                end
            end
        else
            addon:Print("No spells in queue (enter combat to test)")
        end
    end
    
    addon:Print("==========================================")
end

-- Dump raw macro body for debugging
function DebugCommands.DumpMacroBody(addon, macroName)
    if not macroName or macroName == "" then
        addon:Print("Usage: /jac macrodump <macro name>")
        addon:Print("Shows the raw macro body for debugging")
        return
    end
    
    local name, icon, body = GetMacroInfo(macroName)
    if not name or not body then
        addon:Print("Macro not found: " .. macroName)
        return
    end
    
    addon:Print("=== Macro Dump: " .. name .. " ===")
    addon:Print("Raw body (" .. #body .. " chars):")
    -- Print each line with line numbers
    local lineNum = 0
    for line in body:gmatch("[^\r\n]+") do
        lineNum = lineNum + 1
        addon:Print(string.format("  %02d: %s", lineNum, line))
    end
    addon:Print("==========================================")
end