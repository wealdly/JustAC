-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Debug Commands Module
-- Consolidated diagnostic commands - for ad-hoc debugging, use /script in-game
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 9)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------
function DebugCommands.ShowHelp(addon)
    addon:Print("Available commands:")
    addon:Print("/jac - Open options panel")
    addon:Print("/jac toggle - Pause/resume display")
    addon:Print("/jac debug - Toggle debug mode")
    addon:Print("/jac reset - Reset frame position")
    addon:Print("/jac profile <name> - Switch profile")
    addon:Print("/jac profile list - List profiles")
    addon:Print("/jac modules - Check module health")
    addon:Print("/jac find <spell> - Find spell on action bars")
    addon:Print("/jac defensive - Diagnose defensive system")
    addon:Print("/jac help - Show this help")
end

--------------------------------------------------------------------------------
-- Profile Management
--------------------------------------------------------------------------------
function DebugCommands.ManageProfile(addon, profileAction)
    if not profileAction then
        addon:Print("Usage: /jac profile <name> or /jac profile list")
        return
    end
    
    if profileAction == "list" then
        local profiles = addon.db:GetProfiles()
        if profiles then
            addon:Print("Available profiles:")
            for _, name in ipairs(profiles) do
                local current = (name == addon.db:GetCurrentProfile()) and " |cff00ff00(current)|r" or ""
                addon:Print("  " .. name .. current)
            end
        else
            addon:Print("No profiles available")
        end
    else
        local success = pcall(function() addon.db:SetProfile(profileAction) end)
        if success then
            addon:Print("Switched to profile: " .. profileAction)
        else
            addon:Print("Profile not found: " .. profileAction)
        end
    end
end

--------------------------------------------------------------------------------
-- Module Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.ModuleDiagnostics(addon)
    addon:Print("=== JustAC Module Diagnostics ===")
    
    -- Check all LibStub modules
    local modules = {
        {"JustAC-BlizzardAPI", "BlizzardAPI"},
        {"JustAC-FormCache", "FormCache"},
        {"JustAC-MacroParser", "MacroParser"},
        {"JustAC-ActionBarScanner", "ActionBarScanner"},
        {"JustAC-RedundancyFilter", "RedundancyFilter"},
        {"JustAC-SpellQueue", "SpellQueue"},
        {"JustAC-UIManager", "UIManager"},
        {"JustAC-Options", "Options"},
    }
    
    for _, moduleInfo in ipairs(modules) do
        local libName, displayName = moduleInfo[1], moduleInfo[2]
        local module = LibStub(libName, true)
        if module then
            addon:Print("|cff00ff00✓|r " .. displayName)
        else
            addon:Print("|cffff0000✗|r " .. displayName .. " - NOT LOADED")
        end
    end
    
    -- Check critical WoW APIs
    addon:Print("")
    addon:Print("Assisted Combat API:")
    local hasAPI = C_AssistedCombat and C_AssistedCombat.GetRotationSpells
    addon:Print("  C_AssistedCombat: " .. (hasAPI and "|cff00ff00OK|r" or "|cffff0000MISSING|r"))
    
    local assistedMode = GetCVarBool("assistedMode")
    addon:Print("  assistedMode CVar: " .. (assistedMode and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    
    -- Check 12.0+ features
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI then
        if BlizzardAPI.IsMidnightOrLater and BlizzardAPI.IsMidnightOrLater() then
            addon:Print("  WoW Version: |cffffff0012.0+ (Midnight)|r")
        end
        
        if BlizzardAPI.GetFeatureAvailability then
            local features = BlizzardAPI.GetFeatureAvailability()
            local secretCount = 0
            if not features.healthAccess then secretCount = secretCount + 1 end
            if not features.cooldownAccess then secretCount = secretCount + 1 end
            if not features.auraAccess then secretCount = secretCount + 1 end
            if secretCount > 0 then
                addon:Print("  Secret Values: |cffffff00" .. secretCount .. " API(s) returning secrets|r")
            else
                addon:Print("  Secret Values: |cff00ff00None detected|r")
            end
        end
    end
    
    -- Database status
    addon:Print("")
    addon:Print("Database: " .. (addon.db and addon.db.profile and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
    addon:Print("Debug Mode: " .. (addon.db and addon.db.profile and addon.db.profile.debugMode and "|cff00ff00ON|r" or "OFF"))
    
    addon:Print("===========================")
end

--------------------------------------------------------------------------------
-- Find Spell on Action Bars
--------------------------------------------------------------------------------
function DebugCommands.FindSpell(addon, spellName)
    if not spellName or spellName == "" then
        addon:Print("Usage: /jac find <spell name>")
        return
    end
    
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local MacroParser = LibStub("JustAC-MacroParser", true)
    
    addon:Print("=== Searching for: " .. spellName .. " ===")
    
    -- Get spell info
    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellName)
    if spellInfo then
        addon:Print("Spell ID: " .. spellInfo.spellID .. " | Name: " .. spellInfo.name)
    else
        addon:Print("Could not find spell info for: " .. spellName)
    end
    
    local lowerSpellName = spellName:lower()
    local foundAnything = false
    
    for slot = 1, 180 do
        if HasAction(slot) then
            local actionType, actionID = GetActionInfo(slot)
            
            -- Check direct spells
            if actionType == "spell" and actionID then
                local slotSpellInfo = C_Spell.GetSpellInfo(actionID)
                if slotSpellInfo and slotSpellInfo.name and slotSpellInfo.name:lower():find(lowerSpellName, 1, true) then
                    local bar = math.ceil(slot / 12)
                    local button = ((slot - 1) % 12) + 1
                    local key = GetBindingKey("ACTIONBUTTON" .. button) or ""
                    addon:Print(string.format("  Slot %d (Bar %d, Btn %d): %s [%s]", 
                        slot, bar, button, slotSpellInfo.name, key ~= "" and key or "no key"))
                    foundAnything = true
                end
            end
            
            -- Check macros
            if actionType == "macro" then
                local macroName = GetActionText(slot)
                if macroName then
                    local _, _, body = GetMacroInfo(macroName)
                    if body and body:lower():find(lowerSpellName, 1, true) then
                        local bar = math.ceil(slot / 12)
                        local button = ((slot - 1) % 12) + 1
                        local key = GetBindingKey("ACTIONBUTTON" .. button) or ""
                        
                        -- Use MacroParser to check if it actually casts the spell
                        local casts = false
                        if MacroParser and spellInfo then
                            local entry = MacroParser.GetMacroSpellInfo(slot, spellInfo.spellID, spellInfo.name)
                            casts = entry and entry.found
                        end
                        
                        local castStr = casts and "|cff00ff00CASTS|r" or "|cffffff00mentions|r"
                        addon:Print(string.format("  Slot %d (Bar %d, Btn %d): Macro '%s' %s spell [%s]",
                            slot, bar, button, macroName, castStr, key ~= "" and key or "no key"))
                        foundAnything = true
                    end
                end
            end
        end
    end
    
    if not foundAnything then
        addon:Print("No matches found on action bars")
    end
    
    -- Show what ActionBarScanner would return
    if spellInfo and ActionBarScanner and ActionBarScanner.GetSpellHotkey then
        local hotkey = ActionBarScanner.GetSpellHotkey(spellInfo.spellID)
        addon:Print("")
        addon:Print("ActionBarScanner result: " .. (hotkey and hotkey ~= "" and ("'" .. hotkey .. "'") or "(none)"))
    end
    
    addon:Print("=============================")
end

--------------------------------------------------------------------------------
-- Defensive System Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.DefensiveDiagnostics(addon)
    addon:Print("=== Defensive System Diagnostics ===")
    
    local profile = addon.db and addon.db.profile
    if not profile then
        addon:Print("|cffff0000ERROR: No profile loaded|r")
        return
    end
    
    local defSettings = profile.defensives or {}
    
    -- Settings
    addon:Print("Settings:")
    addon:Print("  Enabled: " .. (defSettings.enabled and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    addon:Print("  Show Only In Combat: " .. (defSettings.showOnlyInCombat and "YES" or "NO"))
    addon:Print("  Position: " .. (defSettings.position or "LEFT"))
    
    -- Defensive icon frame
    addon:Print("")
    addon:Print("Defensive Icon:")
    if addon.defensiveIcon then
        addon:Print("  Frame: |cff00ff00EXISTS|r")
        addon:Print("  Visible: " .. (addon.defensiveIcon:IsShown() and "|cff00ff00YES|r" or "NO"))
        addon:Print("  CurrentID: " .. tostring(addon.defensiveIcon.currentID or "nil"))
    else
        addon:Print("  Frame: |cffff0000NOT CREATED|r")
    end
    
    -- Health API status
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("")
    addon:Print("Health API:")
    if BlizzardAPI then
        local healthPct = BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
        if healthPct then
            if issecretvalue and issecretvalue(healthPct) then
                addon:Print("  Current Health: |cffff6600SECRET|r")
            else
                addon:Print("  Current Health: " .. string.format("%.1f%%", healthPct))
            end
        else
            addon:Print("  Current Health: |cffff0000nil|r")
        end
    end
    
    -- Combat status
    local inCombat = UnitAffectingCombat("player")
    addon:Print("  In Combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))
    
    -- Configured spells summary
    addon:Print("")
    addon:Print("Configured Spells:")
    local selfHeals = defSettings.selfHealSpells or {}
    local cooldowns = defSettings.cooldownSpells or {}
    addon:Print("  Self-Heals: " .. #selfHeals .. " spells")
    addon:Print("  Cooldowns: " .. #cooldowns .. " spells")
    
    addon:Print("======================================")
end
