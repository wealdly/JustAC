-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
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
-- and expose RefreshAllDynamic for batch refresh call sites.
-------------------------------------------------------------------------------
local FORWARDERS = {
    { publicName = "UpdateBlacklistOptions",     libName = "JustAC-OptionsOffensive",       methodName = "UpdateBlacklistOptions"     },
    { publicName = "UpdateHotkeyOverrideOptions", libName = "JustAC-OptionsHotkeys",         methodName = "UpdateHotkeyOverrideOptions" },
    { publicName = "UpdateDefensivesOptions",     libName = "JustAC-OptionsDefensives",      methodName = "UpdateDefensivesOptions"    },
    { publicName = "UpdateGapCloserOptions",      libName = "JustAC-OptionsGapClosers",      methodName = "UpdateGapCloserOptions"     },
    { publicName = "UpdateBurstInjectionOptions", libName = "JustAC-OptionsBurstInjection",  methodName = "UpdateBurstInjectionOptions"},
    { publicName = "UpdateCustomQueueOptions",    libName = "JustAC-OptionsCustomQueue",     methodName = "UpdateCustomQueueOptions"   },
}

for _, f in ipairs(FORWARDERS) do
    Options[f.publicName] = function(addon)
        local mod = LibStub(f.libName, true)
        if mod and mod[f.methodName] then
            mod[f.methodName](addon)
        end
    end
end

-- Refresh all dynamic options lists in one call (used by JustAC.lua and slash handler).
function Options.RefreshAllDynamic(addon)
    for _, f in ipairs(FORWARDERS) do
        local mod = LibStub(f.libName, true)
        if mod and mod[f.methodName] then
            mod[f.methodName](addon)
        end
    end
end

-------------------------------------------------------------------------------
-- Shared display-mode predicates used by options sub-modules
-------------------------------------------------------------------------------
function Options.IsStandardQueueDisabled(addon)
    local dm = addon and addon.db and addon.db.profile and addon.db.profile.displayMode or "queue"
    return dm == "disabled" or dm == "overlay"
end

function Options.IsOverlayDisabled(addon)
    local dm = addon and addon.db and addon.db.profile and addon.db.profile.displayMode or "queue"
    return dm ~= "overlay" and dm ~= "both"
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
        Options.RefreshAllDynamic(addon)
        AceConfigDialog:Open("JustAssistedCombat")
        return
    end

    local command, arg = input:match("^(%S+)%s*(.-)%s*$")
    if not command then return end
    command = command:lower()
    if arg == "" then arg = nil end

    local DebugCommands = LibStub("JustAC-DebugCommands", true)

    local function CallDebug(methodName, ...)
        if not DebugCommands or type(DebugCommands[methodName]) ~= "function" then
            addon:Print("DebugCommands module not available")
            return
        end
        DebugCommands[methodName](addon, ...)
    end

    if command == "toggle" then
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

    elseif command == "reset" then
        if addon.mainFrame then
            addon.mainFrame:ClearAllPoints()
            addon.mainFrame:SetPoint("CENTER", 0, -150)
            addon:SavePosition()
            addon:UpdateTargetFrameAnchor()
            addon:Print("Position reset to center")
        end

    elseif command == "profile" then
        CallDebug("ManageProfile", arg)

    elseif command == "find" then
        CallDebug("FindSpell", arg)

    elseif command == "inspect" then
        if not DebugCommands then
            addon:Print("DebugCommands module not available")
            return
        end
        local topic, topicArg = nil, nil
        if arg then
            topic, topicArg = arg:match("^(%S+)%s*(.-)%s*$")
            if topicArg == "" then topicArg = nil end
        end
        if not topic then
            addon:Print("Usage: /jac inspect <topic>")
            addon:Print("Topics: modules, cooldown [spell], defensives, interrupts, burst, auras, perf [reset]")
            return
        end
        topic = topic:lower()
        if topic == "modules" then
            CallDebug("ModuleDiagnostics")
        elseif topic == "cooldown" then
            CallDebug("TestCooldownAPIs", topicArg)
        elseif topic == "defensives" then
            CallDebug("DefensiveDiagnostics")
        elseif topic == "interrupts" then
            CallDebug("InterruptDiagnostics")
        elseif topic == "burst" then
            CallDebug("BurstDiagnostics")
        elseif topic == "auras" then
            CallDebug("AuraDiagnostics")
        elseif topic == "perf" then
            CallDebug("PerformanceDiagnostics", topicArg)
        else
            addon:Print("Unknown inspect topic: '" .. topic .. "'")
            addon:Print("Topics: modules, cooldown [spell], defensives, interrupts, burst, auras, perf [reset]")
        end

    elseif command == "help" then
        CallDebug("ShowHelp")

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
