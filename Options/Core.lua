-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Core - Assembles all option tabs, handles initialization & slash commands
local Options = LibStub:NewLibrary("JustAC-Options", 32)
if not Options then return end

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Sub-module references (resolved lazily)
local General       = LibStub("JustAC-OptionsGeneral", true)
local Display       = LibStub("JustAC-OptionsDisplay", true)
local Offensive     = LibStub("JustAC-OptionsOffensive", true)
local Abilities     = LibStub("JustAC-OptionsAbilities", true)
local Defensives    = LibStub("JustAC-OptionsDefensives", true)
local Profiles      = LibStub("JustAC-OptionsProfiles", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-------------------------------------------------------------------------------
-- Dynamic-list rebuild targets for RefreshAllDynamic below.
-------------------------------------------------------------------------------
local FORWARDERS = {
    { libName = "JustAC-OptionsAbilities",   methodName = "UpdateAbilitiesOptions"      },
    { libName = "JustAC-OptionsDefensives",  methodName = "UpdateDefensivesOptions"     },
    { libName = "JustAC-OptionsGapClosers",  methodName = "UpdateGapCloserOptions"      },
    { libName = "JustAC-OptionsOffensive",   methodName = "UpdateBurstTriggerOptions"   },
    { libName = "JustAC-OptionsCustomQueue", methodName = "UpdateCustomQueueOptions"    },
}

-- Kept as the external notification points (SpellQueue's right-click blacklist
-- path and JustAC's hotkey-override path call these): blacklist and hotkey
-- overrides both render on the Abilities tab now, so both repoint there.
function Options.UpdateBlacklistOptions(addon)
    local mod = LibStub("JustAC-OptionsAbilities", true)
    if mod and mod.UpdateAbilitiesOptions then
        mod.UpdateAbilitiesOptions(addon)
    end
end

Options.UpdateHotkeyOverrideOptions = Options.UpdateBlacklistOptions

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

function Options.IsFullyDisabled(addon)
    local dm = addon and addon.db and addon.db.profile and addon.db.profile.displayMode or "queue"
    return dm == "disabled"
end

--- True when NEITHER surface would show a defensive icon, so defensive-behaviour
--- options have nothing to act on. Both surfaces read the same shared builder, so
--- this must consider both - gating on the standard queue alone wrongly greys the
--- options out for an overlay-only player.
function Options.AreDefensivesUnreachable(addon)
    local profile = addon and addon.db and addon.db.profile
    if not profile then return true end
    local dm = profile.displayMode or "queue"
    if dm == "disabled" then return true end
    local npo = profile.nameplateOverlay
    local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
    return not (profile.defensives and profile.defensives.enabled) and not overlayEnabled
end

-------------------------------------------------------------------------------
-- Assemble all tabs into one AceConfig options table
-------------------------------------------------------------------------------
local function CreateOptionsTable(addon)
    local args = {}

    -- Each sub-module contributes its tab via CreateTabArgs
    if General then
        args.general = General.CreateTabArgs(addon)
    end
    if Display then
        args.display = Display.CreateTabArgs(addon)
    end
    if Offensive then
        args.offensive = Offensive.CreateTabArgs(addon)
    end
    if Abilities then
        args.abilities = Abilities.CreateTabArgs(addon)
    end
    if Defensives then
        args.defensives = Defensives.CreateTabArgs(addon)
    end

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
        -- Deliberate two-level navigation: sections in the tree sidebar, pages
        -- within a section as text-width tabs. Declared (it is also the AceConfig
        -- default) so the sidebar reads as a choice, not an omission.
        childGroups = "tree",
        args = args,
    }
end

-------------------------------------------------------------------------------
-- /jac inspect <topic> dispatch. The topic list itself lives in DebugCommands,
-- next to the methods it names, so the dispatch, the usage line and the help
-- listing cannot drift apart (they had). Every method accepts (addon, topicArg);
-- the no-arg diagnostics simply ignore topicArg.
-------------------------------------------------------------------------------
local function InspectTopics()
    local DC = LibStub("JustAC-DebugCommands", true)
    return (DC and DC.GetInspectTopics and DC.GetInspectTopics()) or {}
end
local function InspectUsage()
    local DC = LibStub("JustAC-DebugCommands", true)
    return (DC and DC.GetInspectUsage and DC.GetInspectUsage()) or "Topics: (unavailable)"
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
                addon:InvalidateCaches({spells = true})
                addon:OnHealthChanged(nil, "player")
                addon:ForceUpdateAll()
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
        -- The last way back when the panel can't be reached with the mouse, so it has to
        -- undo everything that strands it, not just the position. Moving it alone was not
        -- enough: a locked panel still refuses to drag once it arrives, click-through mode
        -- stops it taking mouse input at all, and target-frame docking used to re-anchor it
        -- away again on the very next line - which also meant SavePosition declined to
        -- record the rescue, since it refuses to save while docked.
        local p = addon.db and addon.db.profile
        if not p then return end
        p.panelInteraction  = "unlocked"
        p.panelLocked       = nil            -- legacy key: left set, it re-locks on next load
        p.targetFrameAnchor = "DISABLED"
        p.framePosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
        if p.defensives then
            p.defensives.detachedPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 100 }
        end
        addon.targetframe_anchored = false

        local UIFF = LibStub("JustAC-UIFrameFactory", true)
        if addon.mainFrame and UIFF and UIFF.ApplySavedPosition then
            addon.mainFrame:ClearAllPoints()
            UIFF.ApplySavedPosition(addon, p)
        end
        if addon.defensiveFrame then
            addon.defensiveFrame:ClearAllPoints()
            addon.defensiveFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
        if addon.UpdateFrameSize then addon:UpdateFrameSize() end
        if addon.ForceUpdateAll then addon:ForceUpdateAll() end
        -- The options panel may be open on the very settings just changed underneath it.
        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
        if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
        addon:Print("Panel unlocked, undocked and moved back to the centre of the screen.")

    elseif command == "hud" then
        local DebugHUD = LibStub("JustAC-DebugHUD", true)
        if DebugHUD and DebugHUD.Toggle then
            DebugHUD.Toggle(addon)
        else
            addon:Print("Debug HUD module not available")
        end

    elseif command == "enable" then
        -- Un-disable the current spec (clears the "DISABLED" spec-profile
        -- sentinel; healer specs get it by default at first run).
        local spec = GetSpecialization()
        if not spec then
            addon:Print("No specialization active.")
        elseif addon.db.char.specProfiles and addon.db.char.specProfiles[spec] == "DISABLED" then
            addon.db.char.specProfiles[spec] = nil
            addon:OnSpecChange()
            addon:Print("Enabled for this spec.")
        else
            addon:Print("Already enabled for this spec.")
        end
    elseif command == "profile" then
        CallDebug("ManageProfile", arg)

    elseif command == "find" then
        CallDebug("FindSpell", arg)

    elseif command == "why" then
        CallDebug("WhyDiagnostics", arg)

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
            addon:Print(InspectUsage())
            return
        end
        topic = topic:lower()
        local method = InspectTopics()[topic]
        if method then
            CallDebug(method, topicArg)
        else
            addon:Print("Unknown inspect topic: '" .. topic .. "'")
            addon:Print(InspectUsage())
        end

    elseif command == "help" then
        CallDebug("ShowHelp")

    else
        addon:Print("Unknown command. Type '/jac help' for available commands.")
    end
end

-------------------------------------------------------------------------------
-- Initialization - called from JustAC:OnInitialize
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
        -- Shallow-copy it so our modifications don't leak into other addons' panels.
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
    -- Wide enough that a three-tab row (Display, Defensive Queue) stays under the
    -- tab widget's 75%-of-width fill threshold - past it, AceGUI stretches every
    -- tab in the row to fill the panel instead of fitting them to their text.
    AceConfigDialog:SetDefaultSize("JustAssistedCombat", 800, 550)
    AceConfigDialog:AddToBlizOptions("JustAssistedCombat", "JustAssistedCombat")

    -- Populate dynamic lists at startup so Blizzard Settings has full content
    -- even before the slash command path calls RefreshAllDynamic.
    Options.RefreshAllDynamic(addon)

    addon:RegisterChatCommand("justac", function(input) HandleSlashCommand(addon, input) end)
    addon:RegisterChatCommand("jac", function(input) HandleSlashCommand(addon, input) end)
end
