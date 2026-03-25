-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Core - Assembles all option tabs, handles initialization & slash commands
local Options = LibStub:NewLibrary("JustAC-Options", 32)
if not Options then return end

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Sub-module references (resolved lazily)
local General       = LibStub("JustAC-OptionsGeneral", true)
local StandardQueue = LibStub("JustAC-OptionsStandardQueue", true)
local Offensive     = LibStub("JustAC-OptionsOffensive", true)
local Overlay     = LibStub("JustAC-OptionsOverlay", true)
local Defensives  = LibStub("JustAC-OptionsDefensives", true)
local GapClosers      = LibStub("JustAC-OptionsGapClosers", true)
local BurstInjection  = LibStub("JustAC-OptionsBurstInjection", true)
local Labels          = LibStub("JustAC-OptionsLabels", true)
local Hotkeys     = LibStub("JustAC-OptionsHotkeys", true)
local Profiles    = LibStub("JustAC-OptionsProfiles", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-------------------------------------------------------------------------------
-- Forward Update functions so external code using Options.UpdateX still works
-------------------------------------------------------------------------------
function Options.UpdateBlacklistOptions(addon)
    if not Offensive then Offensive = LibStub("JustAC-OptionsOffensive", true) end
    if Offensive and Offensive.UpdateBlacklistOptions then
        Offensive.UpdateBlacklistOptions(addon)
    end
end

function Options.UpdateHotkeyOverrideOptions(addon)
    if not Hotkeys then Hotkeys = LibStub("JustAC-OptionsHotkeys", true) end
    if Hotkeys and Hotkeys.UpdateHotkeyOverrideOptions then
        Hotkeys.UpdateHotkeyOverrideOptions(addon)
    end
end

function Options.UpdateDefensivesOptions(addon)
    if not Defensives then Defensives = LibStub("JustAC-OptionsDefensives", true) end
    if Defensives and Defensives.UpdateDefensivesOptions then
        Defensives.UpdateDefensivesOptions(addon)
    end
end

function Options.UpdateGapCloserOptions(addon)
    if not GapClosers then GapClosers = LibStub("JustAC-OptionsGapClosers", true) end
    if GapClosers and GapClosers.UpdateGapCloserOptions then
        GapClosers.UpdateGapCloserOptions(addon)
    end
end

function Options.UpdateBurstInjectionOptions(addon)
    if not BurstInjection then BurstInjection = LibStub("JustAC-OptionsBurstInjection", true) end
    if BurstInjection and BurstInjection.UpdateBurstInjectionOptions then
        BurstInjection.UpdateBurstInjectionOptions(addon)
    end
end

local CustomQueue = LibStub("JustAC-OptionsCustomQueue", true)
function Options.UpdateCustomQueueOptions(addon)
    if not CustomQueue then CustomQueue = LibStub("JustAC-OptionsCustomQueue", true) end
    if CustomQueue and CustomQueue.UpdateCustomQueueOptions then
        CustomQueue.UpdateCustomQueueOptions(addon)
    end
end

-------------------------------------------------------------------------------
-- Assemble all tabs into one AceConfig options table
-------------------------------------------------------------------------------
local function CreateOptionsTable(addon)
    local args = {}

    -- Each sub-module contributes its tab via CreateTabArgs
    if General       then args.general          = General.CreateTabArgs(addon)       end
    if StandardQueue then args.standardQueue    = StandardQueue.CreateTabArgs(addon)  end
    if Overlay       then args.nameplateOverlay = Overlay.CreateTabArgs(addon)        end
    if Offensive then args.offensive        = Offensive.CreateTabArgs(addon) end
    if Defensives then args.defensives      = Defensives.CreateTabArgs(addon) end

    -- Profiles placeholder (replaced with AceDBOptions in Initialize)
    args.profiles = {
        type = "group",
        name = L["Profiles"],
        desc = L["Profiles desc"],
        order = 6,
        args = {},
    }

    return {
        name = L["JustAssistedCombat"],
        handler = addon,
        type = "group",
        args = args,
    }
end

-------------------------------------------------------------------------------
-- Slash command handler
-------------------------------------------------------------------------------
local function HandleSlashCommand(addon, input)
    if not input or input == "" or input:match("^%s*$") then
        if addon.InitializeDefensiveSpells then
            addon:InitializeDefensiveSpells()
        end
        Options.UpdateBlacklistOptions(addon)
        Options.UpdateHotkeyOverrideOptions(addon)
        Options.UpdateDefensivesOptions(addon)
        Options.UpdateGapCloserOptions(addon)
        Options.UpdateBurstInjectionOptions(addon)
        Options.UpdateCustomQueueOptions(addon)
        AceConfigDialog:Open("JustAssistedCombat")
        return
    end

    local command, arg = input:match("^(%S+)%s*(.-)$")
    if not command then return end
    command = command:lower()

    local DebugCommands = LibStub("JustAC-DebugCommands", true)

    if command == "config" or command == "options" then
        if addon.InitializeDefensiveSpells then
            addon:InitializeDefensiveSpells()
        end
        Options.UpdateBlacklistOptions(addon)
        Options.UpdateHotkeyOverrideOptions(addon)
        Options.UpdateDefensivesOptions(addon)
        Options.UpdateGapCloserOptions(addon)
        Options.UpdateBurstInjectionOptions(addon)
        Options.UpdateCustomQueueOptions(addon)
        AceConfigDialog:Open("JustAssistedCombat")

    elseif command == "toggle" then
        if addon.db and addon.db.profile then
            addon.db.profile.isManualMode = not addon.db.profile.isManualMode
            if addon.db.profile.isManualMode then
                addon:StopUpdates()
                addon:Print("Display paused")
            else
                addon:StartUpdates()
                addon:Print("Display resumed")
            end
        end

    elseif command == "debug" then
        if addon.db and addon.db.profile then
            addon.db.profile.debugMode = not addon.db.profile.debugMode
            if BlizzardAPI and BlizzardAPI.RefreshDebugMode then
                BlizzardAPI.RefreshDebugMode()
            end
            addon:Print("Debug mode: " .. (addon.db.profile.debugMode and "ON" or "OFF"))
        end

    elseif command == "modules" or command == "diag" then
        if DebugCommands and DebugCommands.ModuleDiagnostics then
            DebugCommands.ModuleDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "find" then
        local spellName = input:match("^find%s+(.+)")
        if DebugCommands and DebugCommands.FindSpell then
            DebugCommands.FindSpell(addon, spellName)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "testcd" then
        local spellName = input:match("^testcd%s+(.+)")
        if DebugCommands and DebugCommands.TestCooldownAPIs then
            DebugCommands.TestCooldownAPIs(addon, spellName)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "reset" then
        if addon.mainFrame then
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint("CENTER", 0, -150)
            addon:SavePosition()
            addon:UpdateTargetFrameAnchor()
            addon:Print("Position reset to center")
        end

    elseif command == "profile" then
        local profileAction = input:match("^profile%s+(.+)")
        if DebugCommands and DebugCommands.ManageProfile then
            DebugCommands.ManageProfile(addon, profileAction)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "defensive" or command == "def" then
        if DebugCommands and DebugCommands.DefensiveDiagnostics then
            DebugCommands.DefensiveDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "poisons" or command == "poison" then
        if DebugCommands and DebugCommands.PoisonDiagnostics then
            DebugCommands.PoisonDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "burst" then
        if DebugCommands and DebugCommands.BurstDiagnostics then
            DebugCommands.BurstDiagnostics(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    elseif command == "help" then
        if DebugCommands and DebugCommands.ShowHelp then
            DebugCommands.ShowHelp(addon)
        else
            addon:Print("DebugCommands module not available")
        end

    else
        addon:Print("Unknown command. Type '/jac help' for available commands.")
    end
end

-------------------------------------------------------------------------------
-- Initialization — called from JustAC:OnInitialize
-------------------------------------------------------------------------------
function Options.Initialize(addon)
    local AceConfig = LibStub("AceConfig-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")

    if not AceConfig or not AceConfigDialog then
        if addon.Print then
            addon:Print("Warning: AceConfig dependencies not found. Options panel will not be available.")
        end
        addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
        addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
        return
    end

    addon.optionsTable = CreateOptionsTable(addon)

    if AceDBOptions then
        addon.optionsTable.args.profiles = AceDBOptions:GetOptionsTable(addon.db)
        addon.optionsTable.args.profiles.order = 6

        -- AceDBOptions uses a shared args table across ALL addons.
        -- Shallow-copy it so our modifications don't leak into BigWigs, DBM, etc.
        local sharedArgs = addon.optionsTable.args.profiles.args
        local localArgs = {}
        for k, v in pairs(sharedArgs) do
            localArgs[k] = v
        end
        addon.optionsTable.args.profiles.args = localArgs

        -- Remove verbose AceDBOptions descriptions to save vertical space
        if localArgs.desc then localArgs.desc = { type = "description", name = "", order = localArgs.desc.order } end
        if localArgs.descreset then localArgs.descreset = { type = "description", name = "", order = localArgs.descreset.order } end
        if localArgs.choosedesc then localArgs.choosedesc = { type = "description", name = "", order = localArgs.choosedesc.order } end
        if localArgs.copydesc then localArgs.copydesc = { type = "description", name = "", order = localArgs.copydesc.order } end
        if localArgs.deldesc then localArgs.deldesc = { type = "description", name = "", order = localArgs.deldesc.order } end
        if localArgs.resetdesc then localArgs.resetdesc = { type = "description", name = "", order = localArgs.resetdesc.order } end

        -- Add per-spec profile switching to the profiles section
        if not Profiles then Profiles = LibStub("JustAC-OptionsProfiles", true) end
        if Profiles and Profiles.AddSpecProfileOptions then
            Profiles.AddSpecProfileOptions(addon)
        end
    end

    AceConfig:RegisterOptionsTable("JustAssistedCombat", addon.optionsTable)
    -- Store the category for version-aware opening
    addon.optionsCategoryID = AceConfigDialog:AddToBlizOptions("JustAssistedCombat", "JustAssistedCombat")

    addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
    addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
end
