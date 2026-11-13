-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Debug Commands Module - Provides diagnostic commands for testing and troubleshooting
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 37)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- THE topic registry: `/jac inspect <topic>` -> method, argument spec, one-liner.
--
-- One table, three consumers - the dispatch and the usage line in Options/Core,
-- and the help listing below. It used to be three hand-kept lists, and they had
-- drifted: nine probes were dispatchable but absent from the help, so the only way
-- to find them was to read the source. A probe you cannot find is a probe you do
-- not have on the day the client changes under you.
--
-- ORDER MATTERS for the listing: entries run roughly general -> specific, so add
-- new ones next to the thing they diagnose rather than at the end.
--------------------------------------------------------------------------------
local INSPECT_TOPICS = {
    { "start",       "StartDiagnostics",         nil, "Start the shared diagnostic session on either client" },
    { "stop",        "StopDiagnostics",          nil, "Stop session-owned captures; preserve results for /reload" },
    { "status",      "DiagnosticStatus",         nil, "Show diagnostic session state and recorder ownership" },
    { "report",      "DiagnosticReport",         nil, "Summarize the latest diagnostic session" },
    { "modules",     "ModuleDiagnostics",        nil,  "Check module health" },
    { "cooldown",    "TestCooldownAPIs",         "[spell]", "Test cooldown APIs (defaults to AC suggestion)" },
    { "defensives",  "DefensiveDiagnostics",     nil,  "Diagnose defensive system" },
    { "interrupts",  "InterruptDiagnostics",     nil,  "Diagnose interrupt/CC queue state" },
    { "burst",       "BurstDiagnostics",         nil,  "Burst-ready cue state" },
    { "auras",       "AuraDiagnostics",          nil,  "Diagnose aura cache state" },
    { "buffs",       "PrecombatBuffDiagnostics", nil,  "Diagnose pre-combat buff checklist (out of combat)" },
    { "groupbuff",   "GroupBuffProbe",           nil,  "Per-member raid-buff detection, every gate's answer" },
    { "perf",        "PerformanceDiagnostics",   "[reset]", "Queue build rate + threshold-gate cost (requires debug mode)" },
    { "rank",        "ContextRankDiagnostics",   nil,  "Queue context inference and per-spell ordering ranks" },
    { "dots",        "DotDiagnostics",           nil,  "Maintained-DoT tracking state for the current target" },
    { "curses",      "CurseDiagnostics",         nil,  "Cooldown Manager curse aura signals for the current target" },
    { "gates",       "GateDiagnostics",          nil,  "SimC gate layer: buff-window tracker + live gate eval (in combat)" },
    { "simcgates",   "SimcGateProbe",            "[st|aoe|cleave]", "Evaluate this spec's SimC gates live, with their inputs" },
    { "blank",       "QueueBlankReport",         nil,  "Why the queue last went empty (run right after it vanishes)" },
    { "glows",       "GlowInventory",            nil,  "Inventory frames overlapping the queue (orphan-glow reports)" },
    { "maintenance", "MaintenanceProbe",         nil,  "Can the tank maintenance slot bind its aura exactly? (in combat)" },
    { "maintlog",    "MaintenanceLog",           "[on|off|clear]", "Record maintenance state 1/s to SavedVariables" },
    { "enemies",     "EnemyCountProbe",          nil,  "Why the direct enemy count reads what it reads (run in combat with a pack)" },
    { "overrides",   "OverrideApiDiff",          nil,  "Spellbook walk: where FindSpellOverrideByID and C_Spell.GetOverrideSpell disagree" },
    { "window",      "FightWindowDump",          "[selftest]", "The last abilities the game served and you used this fight, and what they imply" },
    { "picklog",     "PickLog",                  "[on|off|clear]", "Record the game's pick + readable facts to SavedVariables (rule decoding)" },
    { "topoff",      "TopoffWatch",              "[off]", "Watch the between-pulls heal reminder decide (transitions only)" },
    { "ccdb",        "CCImmunityDB",             "[clear]", "Mob types learned to be CC-immune (persists across sessions)" },
    { "identity",    "IdentityProbe",            "[clear]", "Hunt a plain mob identifier: snapshot every readable target surface, diff vs last run" },
    { "timeline",    "EncounterTimelineProbe",   nil,  "Can we see a big hit coming? Boss-mechanic timeline read" },

    -- Capability probes: run these when a feature stops working and you need to
    -- know whether the CLIENT changed or the addon did.
    { "cdmlayout",   "CdmLayoutProbe",           "[add <spellID>|add all]", "Forever: can JustAC add the rotation's critical buffs to the Cooldown Manager? (decode/round-trip/active layout; add writes them, then /reload)" },
    { "foreverauras", "ForeverAuraProbe",        nil,  "Forever: every aura route on player/target/pet, plus auras remembered from out of combat" },
    { "forever",     "ForeverProbe",             "[arm|off|toggle]", "Forever: snapshot of every signal; arm/off/toggle = one switch for a whole probe session (recorder + errors + audit)" },
    { "validate",    "ValidateAssumptions",      "[arm]", "START HERE if something stopped working: every secrecy/API assumption plus a self-test of each technique the addon rides on; arm = diff on combat enter/exit" },
    { "errors",      "ErrorCapture",             "[off|clear|show]", "Capture taint/secret errors (run after a fight)" },
    { "secrecy",     "SecrecyProbe",             nil,  "Measure which combat values read plain vs secret (in AND out of combat)" },
    { "secrecymap",  "SecrecyMapProbe",          nil,  "One-shot OOC: per-spell/power SecrecyLevel exemption dump" },
    { "durcurve",    "DurationCurveProbe",       "[spellID]", "Duration thresholds: percent + seconds curves, and the value-leak check" },
    { "durprobe",    "DurationProbe",            "[spell]", "Verify the scratch-Cooldown readiness probe on a spell" },
    { "textlaunder", "TextLaunderProbe",         nil,  "The FontString zero-gate: does secret text launder back plain?" },
    { "healthprobe", "HealthProbe",              nil,  "Sweep every OOC health-detection channel (run while hurt)" },
    { "healthgate",  "HealthGatePreview",        nil,  "Toggle live swatches proving the curve gate tracks health" },
    { "threshold",   "ThresholdDiagnostics",     "[health|power percent]", "One live health/power threshold verdict; defaults to configured topoff" },
    { "healprobe",   "HealProbe",                "[arm|show|watch]", "Heal-mode party probes: low-bridge, roster gates, curves, AC feed" },
    { "resource",    "ResourceDiagnostics",      nil,  "Probe secret-safe resource inference from usability" },
    { "resourcepoints", "ResourcePointProbe",    nil,  "Do class resource points (combo/holy power/chi) read plain?" },
    { "aoe",         "AoeDiagnostics",           nil,  "Probe secret-safe enemy counting (AC-independent AoE detection)" },
    { "range",       "RangeProbe",               nil,  "Both range APIs vs the current target: spell path, slot path, gap-closer verdict" },
    { "rotation",    "RotationOrderProbe",       nil,  "Is GetRotationSpells' tail live-ordered? (A/B across state)" },
    { "stacks",      "StacksProbe",              nil,  "OOC: is a stacking buff N aura instances or one secret counter?" },
    { "auraids",     "AuraInstanceIdsProbe",     nil,  "One-shot: are aura instance-ID lists plain/countable in combat?" },
    { "cdfields",    "CooldownFieldsProbe",      nil,  "One-shot: NeverSecret cooldown fields + proc overlay per rotation spell" },
    { "cvitems",     "CooldownViewerItemsProbe", nil,  "One-shot: Cooldown Manager item booleans (CD flash, buff active, pandemic)" },
    { "frames",      "FrameStateProbe",          nil,  "One-shot: laundered frame booleans (low HP, capped power, absorbs)" },
    { "enginesig",   "EngineSignalsProbe",       nil,  "One-shot: unused engine signals (batch auras, classifiers, cast-on-me)" },
    { "enrage",      "EnrageProbe",              "[off]", "Probe secret-safe enrage detection (DispelType 9 color curve)" },
    { "auradump",    "AuraDumpProbe",            nil,  "EVERY aura on the target: every filter's count, every field, plain vs secret" },
    { "auracontainer", "AuraContainerProbe",     nil,  "Can we create a 12.1 AuraContainer, and what methods does it expose?" },
    { "windowsig",   "WindowSignalProbe",        "[spellID|off]", "Continuous sampler: arm on a self-buff, play in/out of combat, then run bare for per-channel verdicts (secret-window signal hunt)" },
    { "channels",    "ChannelMatrix",            nil,  "Laundering matrix: feed a secret to every sink, read back every getter (in combat)" },
    { "aurapanels",  "AuraPanelProbe",           nil,  "Blizzard's own aura panels: is each one live, and what do its buttons expose?" },
    { "audioalerts", "AudioAlertProbe",          nil,  "Combat audio alerts: is it on, and are its stored health/power percents readable?" },
    { "hotkeys",     "HotkeyProbe",              nil,  "Why a queue icon has no keybind (run it WHILE channeling)" },
    { "enragelog",   "EnrageLog",                "[off|clear]", "Log enrage detections to SavedVariables" },
    { "castdiag",    "CastDiagnostics",          nil,  "Arm a one-shot cast-interruptibility probe" },
    { "chargediag",  "ChargeDiagnostics",        "[spell]", "Arm a 60s charge-event/secrecy probe" },
    { "selfcast",    "SelfCastProbe",            nil,  "Arm a capture of own-cast info secrecy (cast + channel something)" },
    { "locwatch",    "LossOfControlWatch",       nil,  "Arm a 10min loss-of-control capture (get CC'd; prints real locType)" },
    { "audit",       "ProbeSession",             "[off|clear]", "ARM the probe battery: auto-snapshots on combat enter/exit" },
}

--- topic -> method name, for the slash dispatch.
function DebugCommands.GetInspectTopics()
    local map = {}
    for i = 1, #INSPECT_TOPICS do
        local topic = INSPECT_TOPICS[i]
        if type(DebugCommands[topic[2]]) == "function" then map[topic[1]] = topic[2] end
    end
    return map
end

--- The one-line "Topics: ..." usage string.
function DebugCommands.GetInspectUsage()
    local parts = {}
    for i = 1, #INSPECT_TOPICS do
        local t = INSPECT_TOPICS[i]
        if type(DebugCommands[t[2]]) == "function" then
            parts[#parts + 1] = t[3] and (t[1] .. " " .. t[3]) or t[1]
        end
    end
    return "Topics: " .. table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------
function DebugCommands.ShowHelp(addon)
    addon:Print("Available commands:")
    addon:Print("/jac - Open options panel")
    addon:Print("/jac toggle - Pause/resume display")
    addon:Print("/jac debug - Toggle debug mode")
    addon:Print("/jac reset - Unlock, undock and re-centre the panel (use if you can't find or move it)")
    addon:Print("/jac enable - Enable the addon for the current spec (if it was disabled)")
    addon:Print("/jac profile <name> - Switch profile")
    addon:Print("/jac profile list - List profiles")
    addon:Print("/jac find [spell] - Find spell on action bars (defaults to AC suggestion)")
    addon:Print("/jac why <spell> - Explain why a spell is or isn't showing in the queue")
    for i = 1, #INSPECT_TOPICS do
        -- Indexed, NOT unpack(): the no-argument rows carry a nil in slot 3, and the
        -- length of a table with a hole is undefined - unpack would truncate them.
        local t = INSPECT_TOPICS[i]
        if type(DebugCommands[t[2]]) == "function" then
            addon:Print(string.format("/jac inspect %s%s - %s",
                t[1], t[3] and (" " .. t[3]) or "", t[4]))
        end
    end
    addon:Print("/jac hud - Toggle a live diagnostic HUD (context, source, AC pick, buff windows)")
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
        -- SetProfile silently creates unknown profiles; check existence so a
        -- typo doesn't create an empty profile and "reset" all settings.
        local exists = false
        for _, name in ipairs(addon.db:GetProfiles()) do
            if name == profileAction then
                exists = true
                break
            end
        end
        if exists then
            addon.db:SetProfile(profileAction)
            addon:Print("Switched to profile: " .. profileAction)
        else
            addon:Print("Profile not found: " .. profileAction)
        end
    end
end
