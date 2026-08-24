-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Debug Commands Module - Provides diagnostic commands for testing and troubleshooting
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 37)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- Shared probe primitives.
--
-- Every probe in this file has to answer the same first question - "did that read
-- come back plain, secret, absent, or blocked?" - and the whole point of the file
-- is that those answers stay trustworthy when the client changes underneath us. So
-- there is ONE definition of each, and the probes format it rather than re-deriving
-- it. Copies drift, and a probe that disagrees with the next probe about what
-- "secret" means is worse than no probe at all: it sends you looking in the wrong
-- layer. (One did exactly that - the heal grid used the weak test below and would
-- print a struct field as plain when it was not.)
--------------------------------------------------------------------------------

-- The ENGINE primitive, not our wrapper around it. BlizzardAPI.IsSecretValue is a
-- nil-guarded passthrough to exactly this, and a probe should measure the client
-- rather than the addon's opinion of the client - if the two ever disagree, that
-- disagreement is the finding.
local function IsSecret(v)
    return v ~= nil and issecretvalue ~= nil and issecretvalue(v) or false
end

-- The STRONG secrecy test, and the reason SafeSecret is not just IsSecret: event
-- args and struct fields can be secret in ways IsSecretValue misses, so force the
-- value through the operations a secret throws on (compare + concat) inside a
-- pcall and treat any throw as secret.
-- @return string|nil plain text, or nil when the value is secret
local function PlainText(v)
    local ok, s = pcall(function()
        local str = tostring(v)
        local _ = (str == "")
        return str .. ""
    end)
    if ok and type(s) == "string" then return s end
    return nil
end

-- Print-safe stringify: "nil" for nil, "<secret>" for secret values, else the
-- plain string.
local function SafeSecret(v)
    if v == nil then return "nil" end
    return PlainText(v) or "<secret>"
end

--- Perform one candidate read and classify what came back. THE primitive every
--- probe's per-read verdict is built on.
--- @param fn function the read, called under pcall
--- @param cap number|nil truncate the plain text to this many characters
--- @return string status one of "err" | "nil" | "secret" | "plain"
--- @return string text the error message, "nil", "<secret>", or the plain value
--- @return any value the raw value, for probes that need to measure it further
local function ProbeRead(fn, cap)
    local ok, v = pcall(fn)
    if not ok then
        return "err", tostring(v):gsub("^.-:%d+: ", ""):sub(1, 52), nil
    end
    if v == nil then return "nil", "nil", nil end
    local s = PlainText(v)
    if not s then return "secret", "<secret>", v end
    if cap and #s > cap then s = s:sub(1, cap) .. ".." end
    return "plain", s, v
end

--- Forward declaration: ClassifyRead is defined with the secrecy sweeps further
--- down (it needs their branch/compare columns), but ProbeReport below closes over
--- it. Without this the closure would bind a nil global instead of the upvalue.
local ClassifyRead

--- The line shape the capability sweeps print: "  <label> = <classified read>".
--- Returns a closure so the sweeps read as a flat list of the things they measure
--- rather than repeating the formatting on every row.
local function ProbeReport(addon)
    return function(label, fn)
        addon:Print("  " .. label .. " = " .. ClassifyRead(fn))
    end
end

--- Walk a global frame path, nil-safe at every hop: FramePath("PlayerFrame",
--- "PlayerFrameContent", ...). Blizzard renames and re-nests these between
--- patches, which is the whole reason the probes read them - so a missing hop is
--- an ANSWER ("that node is gone"), not an error.
local function FramePath(root, ...)
    local node = _G[root]
    for i = 1, select("#", ...) do
        if node == nil then return nil end
        node = node[select(i, ...)]
    end
    return node
end

--- The player health bar, wherever it currently lives. Two probes read this and
--- they must agree: if one resolved the frame and the other did not, the reports
--- would disagree about whether the FRAME moved or the READ broke - which is the
--- exact question they exist to answer. The retail path first, then the legacy
--- alias a unit-frame replacement addon may still expose.
local function PlayerHealthBar()
    return FramePath("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain",
                     "HealthBarsContainer", "HealthBar")
        or FramePath("PlayerFrame", "healthbar")
end

--- The nameplate cast bar, resolved the way PRODUCTION resolves it. Every probe below used
--- to hardcode `np.UnitFrame.castBar`, which 12.x emptied by nesting the bar under
--- CastBarsContainer - so the probes reported "no cast bar" on a client that has one, and
--- would have blamed a third-party addon for a path change. A probe that re-derives a frame
--- differently from the code it is diagnosing answers a question nobody asked.
local function NameplateCastBar(np)
    if not np then return nil end
    local CIT = LibStub("JustAC-CastInterruptTracker", true)
    if CIT and CIT.DebugFindCastBar then
        local bar = CIT.DebugFindCastBar(np)
        if bar then return bar end
    end
    local uf = np.UnitFrame
    if not uf then return nil end
    return (uf.CastBarsContainer and uf.CastBarsContainer.castBar) or uf.castBar
end

--- "Name (id)" for a spell, or "? (id)" when the client has not streamed it in.
local function SpellLabel(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return (n or "?") .. " (" .. tostring(id) .. ")"
end

--- One colour per status, so a green cell means the same thing in every probe.
local function ProbeColour(status)
    return (status == "err" and "|cffff6666") or (status == "nil" and "|cff888888")
        or (status == "secret" and "|cffff6600") or "|cff2ecc71"
end

--- ProbeRead, pre-coloured for a report line.
--- @return string coloured cell
--- @return string status
--- @return any value
local function ProbeCell(fn, cap)
    local status, text, value = ProbeRead(fn, cap)
    return ProbeColour(status) .. text .. "|r", status, value
end

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
    { "gates",       "GateDiagnostics",          nil,  "SimC gate layer: buff-window tracker + live gate eval (in combat)" },
    { "simcgates",   "SimcGateProbe",            "[st|aoe|cleave]", "Evaluate this spec's SimC gates live, with their inputs" },
    { "blank",       "QueueBlankReport",         nil,  "Why the queue last went empty (run right after it vanishes)" },
    { "glows",       "GlowInventory",            nil,  "Inventory frames overlapping the queue (orphan-glow reports)" },
    { "maintenance", "MaintenanceProbe",         nil,  "Can the tank maintenance slot bind its aura exactly? (in combat)" },
    { "maintlog",    "MaintenanceLog",           "[on|off|clear]", "Record maintenance state 1/s to SavedVariables" },
    { "topoff",      "TopoffWatch",              "[off]", "Watch the between-pulls heal reminder decide (transitions only)" },
    { "ccdb",        "CCImmunityDB",             "[clear]", "Mob types learned to be CC-immune (persists across sessions)" },
    { "timeline",    "EncounterTimelineProbe",   nil,  "Can we see a big hit coming? Boss-mechanic timeline read" },

    -- Capability probes: run these when a feature stops working and you need to
    -- know whether the CLIENT changed or the addon did.
    { "validate",    "ValidateAssumptions",      "[arm]", "START HERE if something stopped working: every secrecy/API assumption plus a self-test of each technique the addon rides on; arm = diff on combat enter/exit" },
    { "errors",      "ErrorCapture",             "[off|clear|show]", "Capture taint/secret errors (run after a fight)" },
    { "secrecy",     "SecrecyProbe",             nil,  "Measure which combat values read plain vs secret (in AND out of combat)" },
    { "secrecymap",  "SecrecyMapProbe",          nil,  "One-shot OOC: per-spell/power SecrecyLevel exemption dump" },
    { "durcurve",    "DurationCurveProbe",       "[spellID]", "Duration thresholds: percent + seconds curves, and the value-leak check" },
    { "durprobe",    "DurationProbe",            "[spell]", "Verify the scratch-Cooldown readiness probe on a spell" },
    { "textlaunder", "TextLaunderProbe",         nil,  "The FontString zero-gate: does secret text launder back plain?" },
    { "healthprobe", "HealthProbe",              nil,  "Sweep every OOC health-detection channel (run while hurt)" },
    { "healthgate",  "HealthGatePreview",        nil,  "Toggle live swatches proving the curve gate tracks health" },
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
    for i = 1, #INSPECT_TOPICS do map[INSPECT_TOPICS[i][1]] = INSPECT_TOPICS[i][2] end
    return map
end

--- The one-line "Topics: ..." usage string.
function DebugCommands.GetInspectUsage()
    local parts = {}
    for i = 1, #INSPECT_TOPICS do
        local t = INSPECT_TOPICS[i]
        parts[i] = t[3] and (t[1] .. " " .. t[3]) or t[1]
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
        addon:Print(string.format("/jac inspect %s%s - %s",
            t[1], t[3] and (" " .. t[3]) or "", t[4]))
    end
    addon:Print("/jac hud - Toggle a live diagnostic HUD (context, source, AC pick, buff windows)")
    addon:Print("/jac help - Show this help")
end

--------------------------------------------------------------------------------
-- OOC Health Detection Probe
-- One-shot sweep of every plausible channel for reading player health out of
-- combat in 12.0.7 secret-restricted zones. Run while HURT in the open world;
-- every read is pcall-guarded, nothing is written or branched on a secret.
--------------------------------------------------------------------------------
function DebugCommands.HealthProbe(addon)
    -- Read via pcall; classify: threw / <secret> / the plain value. The shared
    -- primitive uses the STRONGER secrecy test than this probe used to (compare +
    -- concat, not IsSecretValue alone), so struct fields stop reading as plain.
    local safe = SafeSecret
    local rd = ProbeCell

    addon:Print("===== OOC Health Probe (run while HURT) =====")

    -- A. Context: which restriction regime are we in, and why?
    local name, instanceType = GetInstanceInfo()
    addon:Print("A. context:")
    addon:Print("  zone=" .. safe(name) .. " instanceType=" .. safe(instanceType)
        .. " inCombat=" .. tostring(InCombatLockdown()))
    addon:Print("  HasSecretRestrictions=" .. rd(function() return C_Secrets.HasSecretRestrictions() end)
        .. " ShouldAurasBeSecret=" .. rd(function() return C_Secrets.ShouldAurasBeSecret() end))
    addon:Print("  warModeDesired=" .. rd(function() return C_PvP.IsWarModeDesired() end)
        .. " warModeActive=" .. rd(function() return C_PvP.IsWarModeActive() end)
        .. "  (tests the war-mode-causes-it hypothesis)")

    -- B. Raw unit APIs: which values are actually secret right now?
    addon:Print("B. raw APIs:")
    addon:Print("  UnitHealth=" .. rd(function() return UnitHealth("player") end)
        .. " UnitHealthMax=" .. rd(function() return UnitHealthMax("player") end))
    addon:Print("  UnitPower=" .. rd(function() return UnitPower("player") end)
        .. " UnitPowerMax=" .. rd(function() return UnitPowerMax("player") end)
        .. " UnitIsDeadOrGhost=" .. rd(function() return UnitIsDeadOrGhost("player") end))
    addon:Print("  UnitGetTotalAbsorbs=" .. rd(function() return UnitGetTotalAbsorbs("player") end)
        .. " UnitGetIncomingHeals=" .. rd(function() return UnitGetIncomingHeals("player") end))

    -- C. Alternative APIs: call them, don't just check existence. A readable
    --    (possibly quantized) percent here is the sanctioned clean fix.
    addon:Print("C. candidate APIs (called live):")
    if UnitHealthPercent then
        addon:Print("  UnitHealthPercent('player')=" .. rd(function() return UnitHealthPercent("player") end)
            .. "  ('player', true)=" .. rd(function() return UnitHealthPercent("player", true) end))
    else
        addon:Print("  UnitHealthPercent: absent")
    end
    if UnitPercentHealthFromGUID then
        addon:Print("  UnitPercentHealthFromGUID(playerGUID)=" .. rd(function()
            return UnitPercentHealthFromGUID(UnitGUID("player")) end))
    else
        addon:Print("  UnitPercentHealthFromGUID: absent")
    end
    addon:Print("  C_UnitHealth=" .. tostring(type(C_UnitHealth))
        .. " UnitCastingDuration=" .. tostring(type(UnitCastingDuration))
        .. "  (duration-object pattern; a health analog would be the clean fix)")

    -- D. Secret-handling API surface: function names are plain strings - list them.
    --    An unnoticed comparison/percent helper here would be the sanctioned answer.
    local function dumpKeys(label, t)
        if type(t) ~= "table" then addon:Print("  " .. label .. ": absent"); return end
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        addon:Print("  " .. label .. " (" .. #keys .. "): " .. table.concat(keys, ", "))
    end
    addon:Print("D. secret-API surface:")
    dumpKeys("C_Secrets", C_Secrets)
    dumpKeys("C_CurveUtil", C_CurveUtil)

    -- E. Frame-derived reads: Blizzard frames consume the secret engine-side;
    --    is any RESULTING widget state an ordinary number?
    addon:Print("E. frame-derived reads:")
    local hb = PlayerHealthBar()
    if hb then
        addon:Print("  PlayerFrame bar: GetValue=" .. rd(function() return hb:GetValue() end)
            .. " minmax=" .. rd(function() local _, mx = hb:GetMinMaxValues(); return mx end))
        addon:Print("    fillWidth=" .. rd(function()
                local tex = hb:GetStatusBarTexture(); return tex and tex:GetWidth() end)
            .. " barWidth=" .. rd(function() return hb:GetWidth() end)
            .. "  (both plain numbers = ratio is readable health!)")
        addon:Print("    fillTexCoordRight=" .. rd(function()
                local tex = hb:GetStatusBarTexture()
                if not tex then return nil end
                local _, _, _, _, _, _, r = tex:GetTexCoord(); return r end))
        local txt = hb.TextString or hb.text or (hb.HealthBarText)
        addon:Print("    statusText=" .. (txt and rd(function() return txt:GetText() end) or "|cff888888no fontstring|r")
            .. "  (needs status text enabled in Blizzard options)")
    else
        addon:Print("  PlayerFrame health bar: not found")
    end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit("player", false)
    local phb = plate and plate.UnitFrame and plate.UnitFrame.healthBar
    if phb then
        addon:Print("  personal-plate bar: GetValue=" .. rd(function() return phb:GetValue() end)
            .. " fillWidth=" .. rd(function()
                local tex = phb:GetStatusBarTexture(); return tex and tex:GetWidth() end)
            .. " barWidth=" .. rd(function() return phb:GetWidth() end))
    else
        addon:Print("  personal-plate bar: not shown (enable Personal Resource Display to test)")
    end

    -- F. The SANCTIONED secret-safe gate: map the secret health fraction through a
    --    non-secret step curve to an alpha, then sink that (secret) alpha straight
    --    into SetAlpha - never read, never branched. This is the exact idiom that
    --    already ships in UISootheCue (enrage gate) and ApplyExecuteColor (execute
    --    cue); the only open question is whether it round-trips for the PLAYER, OOC,
    --    in a secret zone. If it does, the OOC top-off suggestion can be gated on
    --    TRUE health across the whole 0-99% range, retiring the UNIT_HEALTH cadence
    --    heuristic (HasSustainedPlayerHealthActivity) and the ~35% vignette entirely.
    addon:Print("F. curve-gated alpha (UnitHealthPercent + C_CurveUtil -> SetAlpha):")
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor and UnitHealthPercent) then
        addon:Print("  |cffff6666unavailable|r (C_CurveUtil / UnitHealthPercent / Step missing)")
    else
        -- Reused throwaway swatch (never shown) so the probe leaks nothing across runs.
        DebugCommands._probeSwatch = DebugCommands._probeSwatch or UIParent:CreateTexture(nil, "BACKGROUND")
        local swatch = DebugCommands._probeSwatch
        -- ponytail: UnitHealthPercent's curve-input domain is unconfirmed - ApplyExecuteColor
        -- treats it as the 0-1 fraction, MIDNIGHT research notes 0-100. Test BOTH; the one
        -- whose swatch alpha tracks real health (visible while hurt) is the live domain.
        local function buildGate(hidePoint)
            local c = cu.CreateColorCurve()
            c:SetType(stepType)
            c:AddPoint(0,         CreateColor(1, 1, 1, 1))   -- below full -> show (a=1)
            c:AddPoint(hidePoint, CreateColor(0, 0, 0, 0))   -- at full    -> hide (a=0)
            return c
        end
        for _, dom in ipairs({ { "fraction", 1.0 }, { "0-100", 100 } }) do
            local label, hide = dom[1], dom[2]
            local ok, color = pcall(UnitHealthPercent, "player", false, buildGate(hide))
            if not ok then
                addon:Print("  " .. label .. " domain: |cffff6666SEALED|r (call threw)")
            elseif type(color) ~= "table" or not color.GetRGBA then
                addon:Print("  " .. label .. " domain: returned " .. safe(color) .. " (not a color)")
            else
                local aOk = pcall(function() swatch:SetAlpha(color.a) end)
                addon:Print("  " .. label .. " domain: color OK, .a=" ..
                    (IsSecret(color.a) and "|cffff6600<secret>|r" or safe(color.a)) ..
                    "  SetAlpha=" .. (aOk and "|cff00ff00OK|r" or "|cffff6666threw|r"))
            end
        end
        addon:Print("  verdict: 'color OK ... SetAlpha=OK' = the reliable gate works;")
        addon:Print("  a <secret> .a is EXPECTED and fine (it is what feeds SetAlpha).")
    end

    addon:Print("G. verdict guide: any GREEN number in E that tracks your real health")
    addon:Print("   percent = a readable channel; all SEALED/<secret> = heuristics stay.")
    addon:Print("=============================================")
end

--------------------------------------------------------------------------------
-- Live health-gate preview (toggle)
-- The one-shot HealthProbe confirms UnitHealthPercent+curve->SetAlpha round-trips
-- but CANNOT show that the (secret) alpha actually tracks health, nor which curve
-- input domain is live. This drops two on-screen swatches - one per domain - whose
-- alpha is driven every frame by the gate curve (alpha 1 below full, 0 at full).
-- Watch while healing: the swatch VISIBLE while hurt and GONE at full marks the
-- correct domain and proves the production gate works. Run again to remove.
--------------------------------------------------------------------------------
function DebugCommands.HealthGatePreview(addon)
    if DebugCommands._healthGateFrame then
        DebugCommands._healthGateFrame:Hide()
        DebugCommands._healthGateFrame:SetParent(nil)
        DebugCommands._healthGateFrame = nil
        addon:Print("Health-gate preview: OFF")
        return
    end
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor and UnitHealthPercent) then
        addon:Print("Health-gate preview: |cffff6666unavailable|r (curve API missing)")
        return
    end

    -- Gate curve: alpha 1 below the hide-point, 0 at/above it (one per domain hypothesis).
    local function gate(hidePoint)
        local c = cu.CreateColorCurve()
        c:SetType(stepType)
        c:AddPoint(0,         CreateColor(1, 1, 1, 1))
        c:AddPoint(hidePoint, CreateColor(0, 0, 0, 0))
        return c
    end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(240, 90)
    f:SetPoint("CENTER", 0, 220)

    local function swatch(xoff, label, hidePoint)
        local box = f:CreateTexture(nil, "ARTWORK")
        box:SetColorTexture(0.1, 0.9, 0.2, 1)  -- solid green; the GATE drives its alpha
        box:SetSize(96, 56)
        box:SetPoint("TOPLEFT", xoff, -24)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOM", box, "TOP", 0, 2)
        fs:SetText(label)
        return { tex = box, curve = gate(hidePoint) }
    end

    f._swatches = { swatch(8, "fraction", 1.0), swatch(136, "0-100", 100) }

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    title:SetText("visible while HURT, gone at FULL = live domain")

    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.1 then return end
        self._t = 0
        for _, s in ipairs(self._swatches) do
            -- Never read the color; sink its (secret) alpha straight into SetAlpha.
            local ok, color = pcall(UnitHealthPercent, "player", false, s.curve)
            if ok and type(color) == "table" then
                pcall(function() s.tex:SetAlpha(color.a) end)
            end
        end
    end)

    DebugCommands._healthGateFrame = f
    addon:Print("Health-gate preview: ON (top-center). Take damage, then heal to full.")
    addon:Print("The swatch VISIBLE while hurt and GONE at full marks the live domain.")
    addon:Print("Run /jac inspect healthgate again to remove it.")
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

--------------------------------------------------------------------------------
-- Module Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.ModuleDiagnostics(addon)
    addon:Print("=== JustAC Module Diagnostics ===")

    local modules = {
        {"JustAC-BlizzardAPI", "BlizzardAPI"},
        {"JustAC-FormCache", "FormCache"},
        {"JustAC-MacroParser", "MacroParser"},
        {"JustAC-ActionBarScanner", "ActionBarScanner"},
        {"JustAC-RedundancyFilter", "RedundancyFilter"},
        {"JustAC-SpellQueue", "SpellQueue"},
        {"JustAC-UIRenderer", "UIRenderer"},
        {"JustAC-UIFrameFactory", "UIFrameFactory"},
        {"JustAC-UIAnimations", "UIAnimations"},
        {"JustAC-UIHealthBar", "UIHealthBar"},
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

    addon:Print("")
    addon:Print("Assisted Combat API:")
    local hasAPI = C_AssistedCombat and C_AssistedCombat.GetRotationSpells
    addon:Print("  C_AssistedCombat: " .. (hasAPI and "|cff00ff00OK|r" or "|cffff0000MISSING|r"))

    -- IsAvailable() is the authority, not the CVar. On 12.1.0 the assistedMode CVar reads
    -- false while IsAvailable() returns true and the rotation is live - it was the master
    -- switch when this line was written, and no longer answers for the API. Reporting the
    -- CVar first put a red DISABLED directly under a healthy "C_AssistedCombat: OK", which
    -- is a diagnostic sending you after a problem you do not have. Lead with the truth and
    -- keep the CVar as a footnote, distinguishing "off" from "no such CVar".
    local available, reason
    if C_AssistedCombat and C_AssistedCombat.IsAvailable then
        available, reason = C_AssistedCombat.IsAvailable()
    end
    addon:Print("  IsAvailable(): " .. (available and "|cff00ff00YES|r"
        or ("|cffff0000NO|r" .. (reason and (" (" .. tostring(reason) .. ")") or ""))))

    local cvar = GetCVar("assistedMode")
    addon:Print("  assistedMode CVar: " .. (cvar == nil and "|cff808080not present on this client|r"
        or (GetCVarBool("assistedMode") and "|cff00ff00on|r" or "|cffffff00off|r")
           .. " |cff808080(informational - IsAvailable() decides)|r"))

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI then
        if BlizzardAPI.IS_MIDNIGHT_OR_LATER then
            addon:Print("  WoW Version: |cffffff0012.0+ (Midnight)|r")
        end
        
        if BlizzardAPI.GetFeatureAvailability then
            local features = BlizzardAPI.GetFeatureAvailability()
            local secretCount = 0
            if not features.healthAccess then secretCount = secretCount + 1 end
            if not features.auraAccess then secretCount = secretCount + 1 end
            if not features.procAccess then secretCount = secretCount + 1 end
            if secretCount > 0 then
                addon:Print("  Secret Values: |cffffff00" .. secretCount .. " API(s) returning secrets|r")
            else
                addon:Print("  Secret Values: |cff00ff00None detected|r")
            end
        end
    end

    addon:Print("")
    addon:Print("Database: " .. (addon.db and addon.db.profile and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
    addon:Print("Debug Mode: " .. (addon.db and addon.db.profile and addon.db.profile.debugMode and "|cff00ff00ON|r" or "OFF"))
    
    addon:Print("===========================")
end

--------------------------------------------------------------------------------
-- Find Spell on Action Bars
--------------------------------------------------------------------------------
function DebugCommands.FindSpell(addon, spellArg)
    local spellName = type(spellArg) == "string" and spellArg:match("^%s*(.-)%s*$") or spellArg
    if spellName == "" then spellName = nil end
    local contextSpellID = nil  -- spell ID when using AC context default
    if not spellName then
        -- Context default: use AC next cast suggestion
        if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local ok, nextID = pcall(C_AssistedCombat.GetNextCastSpell)
            if ok and nextID and type(nextID) == "number" then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(nextID)
                if info and info.name then
                    spellName = info.name
                    contextSpellID = nextID
                end
            end
        end
        if not spellName then
            addon:Print("Usage: /jac find [spell]")
            addon:Print("No active AC suggestion found. Specify a spell name to search.")
            return
        end
    end
    
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local MacroParser = LibStub("JustAC-MacroParser", true)
    
    addon:Print("=== Searching for: " .. spellName .. " ===")

    -- Re-use the ID we already have from the context path, or look it up by name
    local spellInfo
    if contextSpellID then
        spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(contextSpellID)
    else
        spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellName)
    end
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

            if actionType == "macro" then
                local macroName = GetActionText(slot)
                if macroName then
                    local _, _, body = GetMacroInfo(macroName)
                    if body and body:lower():find(lowerSpellName, 1, true) then
                        local bar = math.ceil(slot / 12)
                        local button = ((slot - 1) % 12) + 1
                        local key = GetBindingKey("ACTIONBUTTON" .. button) or ""

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
    
    if spellInfo and ActionBarScanner and ActionBarScanner.GetSpellHotkey then
        local hotkey = ActionBarScanner.GetSpellHotkey(spellInfo.spellID)
        addon:Print("")
        addon:Print("ActionBarScanner result: " .. (hotkey and hotkey ~= "" and ("'" .. hotkey .. "'") or "(none)"))
    end
    
    addon:Print("=============================")
end

--------------------------------------------------------------------------------
-- /jac why <spell> - walk the offensive-queue filter pipeline for one spell and
-- print a verdict per stage, so "my ability is missing" gets a concrete reason.
-- Mirrors the real order in SpellQueue.CategorizeAndAssembleRotation; every
-- possibly-secret read is guarded.
--------------------------------------------------------------------------------
function DebugCommands.WhyDiagnostics(addon, spellArg)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    local DotTracker = LibStub("JustAC-DotTracker", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not (BlizzardAPI and SpellQueue) then
        addon:Print("|cffff6666Required modules not loaded.|r")
        return
    end
    if not spellArg or spellArg == "" then
        addon:Print("Usage: /jac why <spellID or spell name>")
        return
    end

    local spellID = tonumber(spellArg)
    if not spellID and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        spellID = C_Spell.GetSpellIDForSpellIdentifier(spellArg)
    end
    if not spellID then
        addon:Print("|cffff6666Spell not found:|r " .. tostring(spellArg))
        return
    end
    local profile = addon.db and addon.db.profile
    if not profile then return end

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = (info and info.name) or ("Spell " .. spellID)
    addon:Print("=== Why: " .. name .. " (" .. spellID .. ") ===")

    local function line(label, ok, detail)
        addon:Print("  " .. (ok and "|cff2ecc71PASS|r " or "|cffff6666FAIL|r ") .. label
            .. (detail and (" - " .. detail) or ""))
    end
    local function note(text)
        addon:Print("  |cffaaaaaa....|r " .. text)
    end

    -- Source: custom queue membership for the current spec
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local cq = specKey and profile.customQueue and profile.customQueue[specKey]
    local cqLen
    if cq and cq.enabled and cq.spells and #cq.spells > 0 then
        cqLen = #cq.spells
        local pos
        for i, sid in ipairs(cq.spells) do
            if sid == spellID then pos = i; break end
        end
        addon:Print(pos and ("  Source: Custom Queue entry #" .. pos .. " of " .. cqLen)
            or "  Source: Custom Queue is active but this spell is NOT in its list - only listed spells appear")
    else
        addon:Print("  Source: Blizzard rotation (no Custom Queue for this spec)")
    end

    -- 1. Availability + variant resolution (full drop when unknown) - the SAME
    -- resolution the queue's list normalization uses, so verdicts can't drift.
    local effectiveID, source = spellID, nil
    if BlizzardAPI.ResolveKnownSpellID then
        effectiveID, source = BlizzardAPI.ResolveKnownSpellID(spellID)
    end
    local avail = effectiveID ~= nil
    line("Known", avail,
        (source == "stored" and "known as entered")
        or (source == "override" and ("known via talent override " .. tostring(effectiveID)))
        or (source == "base" and ("known via base spell " .. tostring(effectiveID)))
        or "this character doesn't know it (unlearned, other spec, or a talent-variant ID) - never shown")
    effectiveID = effectiveID or spellID

    local displayID = (BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(effectiveID)) or effectiveID

    -- 2. Blacklist (full drop)
    local blk = SpellQueue.IsSpellBlacklisted and SpellQueue.IsSpellBlacklisted(spellID)
    line("Not blacklisted", not blk, blk and "Shift+Right-click its icon to un-blacklist" or nil)

    -- 2b. Gap-closer management: while the feature is ON, listed gap-closers are
    -- reserved for the slot-1 out-of-range injection and suppressed from the queue.
    if SpellQueue.IsGapCloserSpell and SpellQueue.IsGapCloserSpell(spellID) then
        local gcOn = profile.gapClosers and profile.gapClosers.enabled
        local pinned = SpellQueue.IsPinnedAlwaysShow
            and (SpellQueue.IsPinnedAlwaysShow(spellID) or SpellQueue.IsPinnedAlwaysShow(effectiveID))
        if gcOn and not pinned then
            line("Not gap-closer-managed", false,
                "it's in your Gap-Closers list, so it only appears as the slot-1 suggestion when the target is out of melee range. To also keep it in the queue: pin it with Always Show (Custom Queue) or turn Gap-Closers off")
        elseif gcOn and pinned then
            note("Gap-closer entry, pinned with Always Show - stays in the queue and still injects at slot 1 out of range")
        else
            note("Gap-closer list entry, but the feature is off - flows through the queue normally")
        end
    end

    -- 3. Item-ability filter (full drop when off)
    if BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(displayID) then
        line("Item abilities allowed", not profile.hideItemAbilities,
            profile.hideItemAbilities and "General tab: Allow Item Abilities is OFF" or "equipped-item ability")
    end

    -- 4. Redundancy (full drop)
    if RedundancyFilter and RedundancyFilter.IsSpellRedundant then
        local redundant, reason = RedundancyFilter.IsSpellRedundant(displayID, profile)
        line("Not redundant", not redundant, redundant and (reason or "hidden by the redundancy filter") or nil)
    end

    -- 5. Sink signals (reorder to the back of the queue, never a drop). Uses the
    -- queue's OWN exported predicates so this report matches what the build did.
    local ready, readySource = BlizzardAPI.IsSpellReady(displayID)
    line("Off cooldown", ready, readySource .. (ready and "" or " - sinks behind ready abilities"))
    local unusableHard = SpellQueue.IsUnusableNonResource and SpellQueue.IsUnusableNonResource(displayID)
    local _, noRes = BlizzardAPI.IsSpellUsable(displayID, true)
    line("Usable", not unusableHard,
        unusableHard and "form/stance/conditions block it right now - sinks behind usable abilities"
        or (noRes and "lacking resources - sinks behind affordable abilities" or nil))
    local outOfRange = SpellQueue.IsConfirmedOutOfRange and SpellQueue.IsConfirmedOutOfRange(displayID) or false
    if outOfRange then
        line("In range of target", false, "sinks behind in-range abilities")
    else
        note("Range: in range, no range requirement, or unreadable (does not sink)")
    end
    local dotParked = DotTracker and DotTracker.IsDotActiveOnCurrentTarget
        and DotTracker.IsDotActiveOnCurrentTarget(displayID) or false
    if dotParked then
        line("DoT not already on target", false,
            "active on target - parked at the back; returns for the pandemic refresh window")
    end
    local heldByDial = SpellQueue.IsHeldByHold
        and SpellQueue.IsHeldByHold(spellID) or false
    if heldByDial then
        line("Hold released", false,
            "a Hold Until dial is set for this ability and its condition is not met - "
            .. "parked at the back until it is")
    end

    -- SimC ordering context (blended: context fit first, SimC theorycraft rank refines)
    if profile.contextOrder == "simc" then
        local RI = LibStub("JustAC-RotationImport", true)
        local rec = RI and RI.GetEntry and RI.GetEntry(spellID)
        local ctx = SpellQueue.DebugRankSpell and SpellQueue.DebugRankSpell(spellID)
        local ctxNote = ctx and (" (context fit " .. ctx .. ", lower = closer to Blizzard's pick)") or ""
        addon:Print(rec
            and ("  SimC ordering: context fit first, then theorycraft rank #" .. tostring(rec.rank)
                 .. " as a tiebreaker" .. ctxNote)
            or ("  SimC ordering: not in the imported list - sorts by context fit, after ranked "
                 .. "abilities in the same fit" .. ctxNote))
    end

    -- Live verdict: where is it right now?
    local maxIcons = (SpellQueue.GetEffectiveMaxIcons and SpellQueue.GetEffectiveMaxIcons(profile))
        or profile.maxIcons or 4
    local queue = SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue()
    local found
    if type(queue) == "table" then
        for i = 1, #queue do
            local q = queue[i]
            if not BlizzardAPI.IsSecretValue(q)
               and (q == spellID or q == displayID or q == effectiveID) then
                found = i
                break
            end
        end
    end
    if found then
        addon:Print("  |cff2ecc71Currently shown|r at queue position " .. found .. ".")
    elseif not avail or blk then
        addon:Print("  |cffff6666Not shown|r - see the FAIL line above.")
    elseif not ready or unusableHard or outOfRange or dotParked then
        local capNote = (cqLen and cqLen > maxIcons)
            and (" Your list has " .. cqLen .. " entries but only " .. maxIcons
                .. " icons are shown - raise Max Icons (Standard Queue tab) or trim the list.")
            or ""
        addon:Print("  |cffff6666Not visible right now|r - it sank to the back (see FAIL lines) and didn't fit the "
            .. maxIcons .. " shown icons." .. capNote)
    else
        addon:Print("  Not in this queue build - it may be the AC slot itself (position 1 is unreadable in combat), "
            .. "or a duplicate of a spell already shown.")
    end
    addon:Print("==============================")
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
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

    addon:Print("Settings:")
    addon:Print("  Enabled: " .. (defSettings.enabled and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    addon:Print("  Display Mode: " .. (defSettings.displayMode or "healthBased"))
    addon:Print("  Position: " .. (defSettings.position or "LEFT"))

    addon:Print("")
    addon:Print("Defensive Icons:")
    local defensiveIcons = addon.defensiveIcons or {}
    if #defensiveIcons == 0 then
        addon:Print("  Frames: |cffff0000NOT CREATED|r")
    else
        for i, icon in ipairs(defensiveIcons) do
            addon:Print("  [Position " .. i .. "]")
            -- Visibility is Shown AND alpha > 0: icons are born Shown at alpha 0 and
            -- driven by alpha (combat-safe), so IsShown alone doesn't prove visible.
            local alphaPct = math.floor((icon:GetAlpha() or 0) * 100 + 0.5)
            addon:Print("    Visible: " .. (icon:IsShown() and "|cff00ff00shown|r" or "|cffff0000HIDDEN|r")
                .. " (alpha " .. alphaPct .. "%)")
            addon:Print("    CurrentID: " .. tostring(icon.currentID or "nil"))
            addon:Print("    SpellID: " .. tostring(icon.spellID or "nil"))
            addon:Print("    isItem: " .. tostring(icon.isItem or "nil"))

            if icon.cooldown then
                addon:Print("    Cooldown frame: |cff00ff00EXISTS|r")
                addon:Print("      CD Visible: " .. (icon.cooldown:IsShown() and "|cff00ff00YES|r" or "|cffff0000NO|r"))
                addon:Print("      DrawSwipe: " .. tostring(icon.cooldown:GetDrawSwipe()))
                addon:Print("      DrawEdge: " .. tostring(icon.cooldown:GetDrawEdge()))

                local cdStart, cdDuration = icon.cooldown:GetCooldownTimes()
                if cdStart and cdDuration and BlizzardAPI and (BlizzardAPI.IsSecretValue(cdStart) or BlizzardAPI.IsSecretValue(cdDuration)) then
                    -- In combat GetCooldownTimes() returns secret numbers; arithmetic would taint.
                    addon:Print("      CD Active: |cffff6600SECRET|r (combat)")
                elseif cdStart and cdDuration then
                    cdStart = cdStart / 1000  -- Convert from ms
                    cdDuration = cdDuration / 1000
                    if cdDuration > 0 then
                        local remaining = (cdStart + cdDuration) - GetTime()
                        addon:Print(string.format("      CD Active: |cff00ff00YES|r (%.1fs remaining)", remaining))
                    else
                        addon:Print("      CD Active: NO (duration=0)")
                    end
                else
                    addon:Print("      CD Active: NO (no times)")
                end
            else
                addon:Print("    Cooldown frame: |cffff0000MISSING|r")
            end
        end
    end

    addon:Print("")
    addon:Print("Health API:")
    if BlizzardAPI then
        local healthPct = BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
        if healthPct then
            if BlizzardAPI.IsSecretValue(healthPct) then
                addon:Print("  Current Health: |cffff6600SECRET|r")
            else
                addon:Print("  Current Health: " .. string.format("%.1f%%", healthPct))
            end
        else
            addon:Print("  Current Health: |cffff0000nil|r")
        end
    end

    local inCombat = UnitAffectingCombat("player")
    addon:Print("  In Combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))

    addon:Print("")
    addon:Print("Positioning (pixels):")
    local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
    if UIHealthBar then
        local barSpacing = UIHealthBar.BAR_SPACING or 3
        local barHeight = UIHealthBar.BAR_HEIGHT or 6
        local healthBarOffset = barHeight + (barSpacing * 2)
        addon:Print("  BAR_SPACING: " .. barSpacing)
        addon:Print("  BAR_HEIGHT: " .. barHeight)
        addon:Print("  Gap DPS->HealthBar: " .. barSpacing .. "px")
        addon:Print("  Gap HealthBar->Defensive: " .. (healthBarOffset - barSpacing - barHeight) .. "px")
        addon:Print("  (Should be equal: " .. barSpacing .. "px each)")
    end

    addon:Print("")
    addon:Print("Configured Spells:")
    local _, playerClass = UnitClass("player")
    local defensives = addon:GetClassSpellList("defensiveSpells") or {}
    local petHeals = addon:GetClassSpellList("petHealSpells") or {}
    local petRez = addon:GetClassSpellList("petRezSpells") or {}
    addon:Print("  Class: " .. (playerClass or "UNKNOWN"))
    addon:Print("  Defensives: " .. #defensives .. " spells")
    if #petRez > 0 then
        addon:Print("  Pet Rez/Summon: " .. #petRez .. " spells")
    end
    if #petHeals > 0 then
        addon:Print("  Pet Heals: " .. #petHeals .. " spells")
    end

    -- Pet status (reliable in combat: UnitExists/UnitIsDead are NOT secret)
    if BlizzardAPI and BlizzardAPI.GetPetStatus then
        local petStatus = BlizzardAPI.GetPetStatus()
        addon:Print("  Pet Status: " .. (petStatus or "N/A"))
        if petStatus == "alive" and BlizzardAPI.GetPetHealthPercent then
            local petHP = BlizzardAPI.GetPetHealthPercent()
            addon:Print("  Pet Health: " .. (petHP and string.format("%.0f%%", petHP) or "secret"))
        end
    end

    -- GetHaste(): verified SECRET in combat (2026-07-01) - not usable for live
    -- recharge/CD scaling; kept here as a probe in case a patch changes it.
    addon:Print("")
    addon:Print("Haste API:")
    if GetHaste then ---@diagnostic disable-line: undefined-global
        local haste = GetHaste() ---@diagnostic disable-line: undefined-global
        if BlizzardAPI and BlizzardAPI.IsSecretValue(haste) then
            addon:Print("  GetHaste(): |cffff6600SECRET|r")
        else
            addon:Print("  GetHaste(): " .. string.format("%.2f%%", haste))
        end
    else
        addon:Print("  GetHaste(): |cffff0000not available|r")
    end
    
    addon:Print("======================================")
end

--------------------------------------------------------------------------------
-- Cooldown API Testing (diagnose GCD vs spell cooldown issues)
--------------------------------------------------------------------------------
function DebugCommands.TestCooldownAPIs(addon, spellArg)
    local spellID = nil
    local spellName = nil
    local normalizedArg = type(spellArg) == "string" and spellArg:match("^%s*(.-)%s*$") or spellArg
    if normalizedArg == "" then normalizedArg = nil end

    if not normalizedArg then
        -- Context default: use AC next cast suggestion
        if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local ok, nextID = pcall(C_AssistedCombat.GetNextCastSpell)
            if ok and nextID and type(nextID) == "number" then
                spellID = nextID
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                spellName = (info and info.name) or ("ID:" .. spellID)
            end
        end
        if not spellID then
            addon:Print("Usage: /jac inspect cooldown [spell]")
            addon:Print("No active AC suggestion found. Specify a spell name to inspect.")
            return
        end
    else
        spellName = normalizedArg

        -- Spellbook search is more accurate than brute-force ID iteration
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            -- Iterate through player's spellbook slots
            for i = 1, 1000 do
                local spellInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
                if not spellInfo then
                    break -- End of spellbook
                end
                if spellInfo.name and spellInfo.name:lower() == spellName:lower() then
                    spellID = spellInfo.spellID
                    break
                end
            end
        end

        -- Fallback: client name→ID resolver (replaces a 500k-ID brute-force scan
        -- that hitched the client for seconds)
        if not spellID and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
            spellID = C_Spell.GetSpellIDForSpellIdentifier(spellName)
        end

        if not spellID then
            addon:Print("|cffff0000Spell not found:|r " .. spellName)
            addon:Print("Tip: Make sure the spell is in your spellbook or try the exact spell name")
            return
        end
    end

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)

    -- Secret values can't be used in string operations
    local function SafeFormat(value, isSecret)
        if isSecret then
            return "SECRET"
        elseif value == nil then
            return "nil"
        else
            -- Use pcall to safely convert to string
            local ok, result = pcall(tostring, value)
            return ok and result or "ERROR"
        end
    end

    addon:Print("=== Cooldown API Test: " .. spellName .. " (ID: " .. spellID .. ") ===")
    addon:Print("")

    addon:Print("1. C_SpellBook.GetSpellCooldown:")
    if C_SpellBook and C_SpellBook.GetSpellCooldown then
        local ok, cd = pcall(C_SpellBook.GetSpellCooldown, spellID)
        if ok and cd then
            local startSecret = BlizzardAPI.IsSecretValue(cd.startTime)
            local durSecret = BlizzardAPI.IsSecretValue(cd.duration)

            addon:Print("   startTime: " .. SafeFormat(cd.startTime, startSecret) ..
                (startSecret and " |cffff6600(SECRET)|r" or ""))
            addon:Print("   duration: " .. SafeFormat(cd.duration, durSecret) ..
                (durSecret and " |cffff6600(SECRET)|r" or ""))

            if not startSecret and not durSecret and cd.startTime and cd.duration and cd.duration > 0 then
                local remaining = (cd.startTime + cd.duration) - GetTime()
                addon:Print(string.format("   remaining: %.2fs", remaining))
            end
        else
            addon:Print("   |cffff0000ERROR or nil|r")
        end
    else
        addon:Print("   |cffff0000API not available|r")
    end

    addon:Print("")

    addon:Print("2. BlizzardAPI.GetSpellCooldown (C_Spell):")
    if BlizzardAPI and BlizzardAPI.GetSpellCooldown then
        local start, dur = BlizzardAPI.GetSpellCooldown(spellID)
        local startSecret = BlizzardAPI.IsSecretValue(start)
        local durSecret = BlizzardAPI.IsSecretValue(dur)

        addon:Print("   start: " .. SafeFormat(start, startSecret) ..
            (startSecret and " |cffff6600(SECRET)|r" or ""))
        addon:Print("   duration: " .. SafeFormat(dur, durSecret) ..
            (durSecret and " |cffff6600(SECRET)|r" or ""))

        if not startSecret and not durSecret and start and dur and dur > 0 then
            local remaining = (start + dur) - GetTime()
            addon:Print(string.format("   remaining: %.2fs", remaining))
        end
    else
        addon:Print("   |cffff0000API not available|r")
    end

    addon:Print("")

    addon:Print("3. Action Bar Cooldown:")
    if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
        local slot = ActionBarScanner.GetSlotForSpell(spellID)
        if slot then
            local direct = ActionBarScanner.GetDirectSlotForSpell
                and ActionBarScanner.GetDirectSlotForSpell(spellID)
            local actionType = GetActionInfo and GetActionInfo(slot) or "?"
            addon:Print("   Slot: " .. slot .. " (" .. tostring(actionType) .. ")  Direct: "
                .. (direct and "|cff00ff00YES|r (slot drives swipe+GCD)"
                    or "|cffff6600NO|r (macro/unbound: swipe from local numbers, GCD via fallback)"))
            if ActionBarScanner.GetActionBarCooldown then
                local start, dur = ActionBarScanner.GetActionBarCooldown(spellID)
                local startSecret = BlizzardAPI.IsSecretValue(start)
                local durSecret = BlizzardAPI.IsSecretValue(dur)

                addon:Print("   start: " .. SafeFormat(start, startSecret) ..
                    (startSecret and " |cffff6600(SECRET)|r" or ""))
                addon:Print("   duration: " .. SafeFormat(dur, durSecret) ..
                    (durSecret and " |cffff6600(SECRET)|r" or ""))

                if not startSecret and not durSecret and start and dur and dur > 0 then
                    local remaining = (start + dur) - GetTime()
                    addon:Print(string.format("   remaining: %.2fs", remaining))
                end
            end
        else
            addon:Print("   |cff888888Not on action bar|r")
        end
    else
        addon:Print("   |cffff0000ActionBarScanner not available|r")
    end

    addon:Print("")

    addon:Print("4. GCD (dummy spell 61304):")
    if BlizzardAPI and BlizzardAPI.GetGCDInfo then
        local gcdStart, gcdDur = BlizzardAPI.GetGCDInfo()
        local startSecret = BlizzardAPI.IsSecretValue(gcdStart)
        local durSecret = BlizzardAPI.IsSecretValue(gcdDur)

        addon:Print("   start: " .. SafeFormat(gcdStart, startSecret) ..
            (startSecret and " |cffff6600(SECRET)|r" or ""))
        addon:Print("   duration: " .. SafeFormat(gcdDur, durSecret) ..
            (durSecret and " |cffff6600(SECRET)|r" or ""))

        if not startSecret and not durSecret and gcdStart and gcdDur and gcdDur > 0 then
            local remaining = (gcdStart + gcdDur) - GetTime()
            addon:Print(string.format("   remaining: %.2fs", remaining))
        end
    else
        addon:Print("   |cffff0000API not available|r")
    end

    addon:Print("")

    addon:Print("5. C_Spell.GetSpellCooldown (raw isOnGCD + local CD tracking):")
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and cd then
            local isOnGCDSecret = BlizzardAPI.IsSecretValue(cd.isOnGCD)
            local durSecret = BlizzardAPI.IsSecretValue(cd.duration)
            local startSecret = BlizzardAPI.IsSecretValue(cd.startTime)

            local isOnGCDStr
            if isOnGCDSecret then
                isOnGCDStr = "SECRET"
            elseif cd.isOnGCD == nil then
                isOnGCDStr = "nil (ambiguous - off CD OR unflagged CD running)"
            elseif cd.isOnGCD == true then
                isOnGCDStr = "true (GCD only - spell ready once GCD clears)"
            elseif cd.isOnGCD == false then
                isOnGCDStr = "false (real CD running - Blizzard-flagged spell)"
            else
                isOnGCDStr = tostring(cd.isOnGCD)
            end
            addon:Print("   isOnGCD: " .. isOnGCDStr)
            addon:Print("   duration: " .. SafeFormat(cd.duration, durSecret) ..
                (durSecret and " |cffff6600(SECRET)|r" or ""))
            addon:Print("   startTime: " .. SafeFormat(cd.startTime, startSecret) ..
                (startSecret and " |cffff6600(SECRET)|r" or ""))
        else
            addon:Print("   |cffff0000pcall failed or nil|r")
        end
    else
        addon:Print("   |cffff0000C_Spell.GetSpellCooldown not available|r")
    end

    addon:Print("")
    addon:Print("6. Local CD tracking (JustAC in-combat timer):")
    if BlizzardAPI and BlizzardAPI.IsSpellOnLocalCooldown then
        local localCD = BlizzardAPI.IsSpellOnLocalCooldown(spellID)
        addon:Print("   IsSpellOnLocalCooldown: " .. (localCD and "|cffff6600true (CD active)|r" or "|cff00ff00false (no local CD)|r"))
    else
        addon:Print("   |cffff0000BlizzardAPI.IsSpellOnLocalCooldown not available|r")
    end
    if BlizzardAPI and BlizzardAPI.IsSpellReady then
        local ready = BlizzardAPI.IsSpellReady(spellID)
        addon:Print("   IsSpellReady: " .. (ready and "|cff00ff00true (ready)|r" or "|cffff6600false (on CD)|r"))
    end
    if BlizzardAPI and BlizzardAPI.DebugTrackingState then
        local cat, maxCh, curCh, localCD = BlizzardAPI.DebugTrackingState(spellID)
        addon:Print("   Tracked: " .. (cat and ("|cff00ff00" .. tostring(cat) .. "|r") or "|cffff0000NO (not registered)|r"))
        if maxCh then
            addon:Print("   Charge cache: maxCharges=" .. tostring(maxCh) ..
                (curCh and (", current=" .. tostring(curCh)) or "") .. ", localCD=" .. tostring(localCD))
        else
            addon:Print("   Charge cache: |cffff6600none|r, localCD=" .. tostring(localCD))
        end
        local displayID = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID)
        if displayID and displayID ~= spellID then
            local dcat = BlizzardAPI.DebugTrackingState(displayID)
            addon:Print("   (display ID " .. tostring(displayID) .. " tracked: " ..
                (dcat and ("|cff00ff00" .. tostring(dcat) .. "|r") or "|cffff0000NO|r") .. ")")
        end
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if SpellDB and SpellDB.IsInterruptOnCooldown then
        local intCD = SpellDB.IsInterruptOnCooldown(spellID)
        addon:Print("   IsInterruptOnCooldown: " .. (intCD and "|cffff6600true (blocked)|r" or "|cff00ff00false (usable)|r"))
    end

    addon:Print("")
    addon:Print("Cast the spell and run this command again to see cooldown behavior!")
    addon:Print("===========================================")
end

--------------------------------------------------------------------------------
-- Interrupt Queue Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.InterruptDiagnostics(addon)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)

    addon:Print("=== Interrupt Queue Diagnostics ===")

    local resolvedInts = addon and addon.resolvedInterrupts
    if not resolvedInts or #resolvedInts == 0 then
        addon:Print("|cffff6600No resolved interrupt spells. Try /reload or check spec.|r")
        return
    end

    addon:Print("Resolved interrupt/CC list (" .. #resolvedInts .. " entries):")
    for i, entry in ipairs(resolvedInts) do
        local sid, stype = entry.spellID, entry.type
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
        local name = (spellInfo and spellInfo.name) or "?"

        local localCD = BlizzardAPI and BlizzardAPI.IsSpellOnLocalCooldown and BlizzardAPI.IsSpellOnLocalCooldown(sid)
        local ready = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(sid)
        local intCD = SpellDB and SpellDB.IsInterruptOnCooldown and SpellDB.IsInterruptOnCooldown(sid)
        local usable = BlizzardAPI and BlizzardAPI.IsSpellUsable and BlizzardAPI.IsSpellUsable(sid, stype ~= "cc")

        local isOnGCD = nil
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, cd = pcall(C_Spell.GetSpellCooldown, sid)
            if ok and cd then isOnGCD = cd.isOnGCD end
        end

        local isOnGCDStr = "nil"
        if BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(isOnGCD) then
            isOnGCDStr = "SECRET"
        elseif isOnGCD == true then
            isOnGCDStr = "|cffffff00true|r"
        elseif isOnGCD == false then
            isOnGCDStr = "|cffff6600false|r"
        end

        local cdColor = intCD and "|cffff6600" or "|cff00ff00"
        local cdStr = intCD and "ON_CD" or "ready"
        addon:Print(string.format("  %d. %s (%d) [%s]  %sIsIntOnCD=%s|r  localCD=%s  IsReady=%s  usable=%s  isOnGCD=%s",
            i, name, sid, stype,
            cdColor, cdStr,
            tostring(localCD), tostring(ready), tostring(usable), isOnGCDStr))
    end

    -- The two things this probe could not previously answer, and which decide everything:
    -- WHICH spell the tracker actually picked, and what the icon then did with it. A list of
    -- healthy candidates plus a missing icon tells you nothing about where the chain broke -
    -- selection, show, texture, or alpha are four different bugs with one symptom.
    local CIT = LibStub("JustAC-CastInterruptTracker", true)
    local prof = addon.db and addon.db.profile
    if CIT and CIT.EvaluateInterrupt and SpellDB and SpellDB.ResolveInterruptSpells then
        local mode = (prof and prof.interruptMode) or "kickPrefer"
        local ok, res = pcall(CIT.EvaluateInterrupt, SpellDB.ResolveInterruptSpells(), mode, GetTime())
        if ok and res then
            local pickName = res.spellID and SpellLabel(res.spellID) or "none"
            addon:Print(string.format("verdict: shouldShow=%s  pick=%s  castBar=%s",
                res.shouldShow and "|cff00ff00true|r" or "|cffff6600false|r",
                pickName, res.castBar and "found" or "|cff888888nil|r"))
            if res.spellID and SpellDB.IsInterruptTypeSpell then
                -- Decides the ALPHA PATH: a kick goes through the secret sink and is hidden on
                -- a non-interruptible cast; a CC takes the plain path and must stay visible.
                addon:Print("   alpha path: " .. (SpellDB.IsInterruptTypeSpell(res.spellID)
                    and "|cffffff00secret sink|r (kick - hides on non-interruptible)"
                    or "|cff00ff00plain|r (cc - should be visible)"))
            end
        else
            addon:Print("verdict: |cffff6600EvaluateInterrupt threw|r")
        end
    end

    -- Cast-bar discovery. CC substitution needs a BRANCHABLE interruptibility answer, and in
    -- 12.x exactly one exists: Blizzard hides the nameplate cast bar's spell Icon on a
    -- non-interruptible cast, and Icon:IsShown() is a concrete non-secret boolean. Everything
    -- else (BorderShield, barType, UnitCastingInfo's notInterruptible) is secret.
    -- That signal has three ways to vanish, and all three look identical from the outside:
    --   * no nameplate for the target        -> nothing to read
    --   * HideIconWhenNotInterruptible=false -> the CLASSIC cast bar style deliberately does
    --     not hide the icon (Blizzard_NamePlates.lua ShouldHideIconWhenNotInterruptible),
    --     so the signal is switched off at the source
    --   * look ~= "UNITFRAME" / showIcon=false -> a reskin, or the player turned the icon off
    -- Without the signal we fail OPEN to "interruptible", pick the kick, and the secret alpha
    -- sink then hides it - a ding with no icon, and no CC offered.
    if CIT and CIT.DebugFindCastBar then
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit("target", false)
        local bar, src = CIT.DebugFindCastBar(np)
        addon:Print(string.format("cast bar: nameplate=%s  bar=%s  source=%s",
            np and "|cff00ff00yes|r" or "|cffff6600NO|r",
            bar and "|cff00ff00found|r" or "|cffff6600none|r", tostring(src)))
        if bar then
            local function f(fn) return ProbeRead(fn) end
            addon:Print(string.format(
                "   HideIconWhenNotInterruptible=%s  showIcon=%s  look=%s  Icon:IsShown=%s",
                f(function() return bar.HideIconWhenNotInterruptible end),
                f(function() return bar.showIcon end),
                f(function() return bar.look end),
                f(function() return bar.Icon and bar.Icon:IsShown() end)))
            local okH, hide = pcall(function() return bar.HideIconWhenNotInterruptible end)
            if okH and hide == false then
                addon:Print("   |cffff6600CLASSIC cast bar style|r - Blizzard does not hide the icon"
                    .. " on this style, so the only readable interruptibility signal does not exist."
                    .. " Switch the nameplate cast bar style to restore CC substitution.")
            end
        end
    end

    local icon = addon.interruptIcon
    if icon then
        local tex = icon.iconTexture
        addon:Print(string.format("icon: shown=%s  alpha=%s  spellID=%s  texShown=%s  tex=%s",
            tostring(icon:IsShown()), ProbeRead(function() return icon:GetAlpha() end),
            tostring(icon.spellID), tex and tostring(tex:IsShown()) or "no texture object",
            tex and ProbeRead(function() return tex:GetTexture() end) or "-"))
        -- The soothe cue is a SEPARATE frame pinned over this icon at +16, so a slot left at a
        -- non-zero alpha covers the kick/CC completely. Its slot alphas are secret once the
        -- enrage sink has written them, hence ProbeRead rather than a bare GetAlpha.
        local cue = icon.sootheCue
        if cue then
            local parts = {}
            for i = 1, 5 do
                local s = cue.slots and cue.slots[i]
                parts[#parts + 1] = s and ProbeRead(function() return s:GetAlpha() end) or "-"
            end
            -- The filter decides how many slots ever hold an aura, and therefore how much of
            -- this overlay is sitting over position 0 at any moment. "err" alphas are normal:
            -- a slot frame descends from a container button, so reading one is denied.
            -- Pipes DOUBLED for display: "|" opens a chat escape, so an aura filter string
            -- prints with its components eaten - "HELPFUL|RAID_..." came out as
            -- "HELPFULAID_..." because |R is the colour-reset code. Any probe printing a
            -- filter string has to do this.
            local shownFilter = tostring(cue._filter):gsub("|", "||")
            addon:Print("soothe overlay: shown=" .. tostring(cue:IsShown())
                .. "  filter=" .. shownFilter
                .. "  slots=" .. tostring(cue.slots and #cue.slots or 0)
                .. " (pool batches at 10; only maxFrameCount can be live)"
                .. "  alphas=" .. table.concat(parts, ","))
            if cue._filter == "HELPFUL" then
                addon:Print("   |cffff6600narrow filter refused|r - a slot exists for EVERY target"
                    .. " buff, not just enrages")
            end
        end
    else
        addon:Print("icon: |cff888888addon.interruptIcon is nil (standard queue not built?)|r")
    end

    addon:Print("")
    addon:Print("Target interrupt-worthy: " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetInterruptWorthy and BlizzardAPI.IsTargetInterruptWorthy()))
    addon:Print("Target CC-immune: " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetCCImmune and BlizzardAPI.IsTargetCCImmune())
        .. "  (signal: " .. tostring(BlizzardAPI and BlizzardAPI.GetCCImmuneSignal and BlizzardAPI.GetCCImmuneSignal()) .. ")")
    -- Already crowd-controlled: this alone suppresses every CC suggestion, and on a
    -- practice mob you CC repeatedly it is the most likely reason a working substitution
    -- looks intermittent - the second cast genuinely should not be offered a CC.
    -- IN COMBAT THIS CANNOT ANSWER: GetUnitAuraInstanceIDs is RequiresUnitAuraAccess as of
    -- 12.1.0, so it fails open to false and a CC is offered onto an already-CC'd target.
    -- Reported as "unavailable" rather than "false" so the probe does not present a
    -- fail-open default as a measurement.
    local ccKnown = not (BlizzardAPI and BlizzardAPI.AreAurasSecret and BlizzardAPI.AreAurasSecret())
    local alreadyCC = (BlizzardAPI and BlizzardAPI.IsUnitCrowdControlled
        and BlizzardAPI.IsUnitCrowdControlled("target")) or false
    addon:Print("Target already CC'd: "
        .. (ccKnown and tostring(alreadyCC) or "|cffff6600unavailable in combat|r (reads false)")
        .. (ccKnown and alreadyCC and "  |cffff6600<- CC suggestions suppressed while true|r" or ""))

    -- The two debounce windows. Both are deliberate, both silence the slot, and neither
    -- was visible here before - so a report of "inconsistent" could not be told apart from
    -- a detection failure.
    if CIT and CIT.DebugSuppression then
        local sinceInt, intWin, sinceCC, ccWin = CIT.DebugSuppression()
        local intHot, ccHot = sinceInt < intWin, sinceCC < ccWin
        addon:Print(string.format("suppression: sinceInterrupt=%.1fs/%.1f%s  sinceCC=%.1fs/%.1f%s",
            sinceInt, intWin, intHot and " |cffff6600ACTIVE|r" or "",
            sinceCC, ccWin, ccHot and " |cffff6600ACTIVE|r" or ""))
    end

    local interruptMode = addon.db and addon.db.profile and (addon.db.profile.interruptMode or "kickPrefer") or "n/a"
    addon:Print("Interrupt mode: " .. interruptMode)
    addon:Print("===================================")
end

--------------------------------------------------------------------------------
-- Aura Cache Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.AuraDiagnostics(addon)
    addon:Print("=== Aura Cache Diagnostics ===")

    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    if not RedundancyFilter then
        addon:Print("|cffff0000RedundancyFilter not loaded|r")
        return
    end

    local auras = nil
    if RedundancyFilter.GetAuraCache then
        auras = RedundancyFilter.GetAuraCache()
    end

    if not auras then
        addon:Print("|cffff0000Could not access aura cache|r")
        return
    end

    local function countTable(t)
        if not t then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    local inCombat = UnitAffectingCombat("player")
    addon:Print("")
    addon:Print("Aura Cache Status:")
    addon:Print("  In Combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))
    addon:Print("  hasSecrets: " .. tostring(auras.hasSecrets or false))
    addon:Print("  byID entries: " .. countTable(auras.byID))
    addon:Print("  byName entries: " .. countTable(auras.byName))

    addon:Print("")
    addon:Print("Cached auras by ID (first 20):")
    if auras.byID then
        local shown = 0
        local total = countTable(auras.byID)
        for spellID in pairs(auras.byID) do
            if shown < 20 then
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                local name = (spellInfo and spellInfo.name) or "?"
                addon:Print("  " .. tostring(spellID) .. " (" .. name .. ")")
                shown = shown + 1
            end
        end
        if total > 20 then
            addon:Print("  ... (" .. (total - 20) .. " more)")
        end
    else
        addon:Print("  (empty)")
    end

    addon:Print("")
    addon:Print("All player buffs (first 20):")
    local count = 0
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            count = count + 1
            if count <= 20 then
                -- spellId/name are secret in combat; SafeSecret pcalls the tostring.
                addon:Print("  [" .. i .. "] ID:" .. SafeSecret(auraData.spellId) .. " Name:" .. SafeSecret(auraData.name))
            end
        end
    else
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
            if not name and not spellId then break end
            count = count + 1
            if count <= 20 then
                addon:Print("  [" .. i .. "] ID:" .. SafeSecret(spellId) .. " Name:" .. SafeSecret(name))
            end
        end
    end
    addon:Print("  Total buffs: " .. count)

    addon:Print("==============================")
end

--------------------------------------------------------------------------------
-- Burst-Ready Cue Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.BurstDiagnostics(addon)
    addon:Print("=== Burst-Ready Cue Diagnostics ===")

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)

    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    addon:Print("Spec key: " .. (specKey or "|cffff0000unknown|r"))

    local profile = addon and addon.db and addon.db.profile
    local cueOn = profile and profile.burstCueGlow == true
    addon:Print("Cue glow: " .. (cueOn and "|cff00ff00ON|r" or "|cff888888off (default)|r"))

    -- Effective trigger list: cue fires when one of these is visible in the queue
    -- and off cooldown (ready-but-absent triggers get pinned to the tail).
    -- Source chain: profile override -> SimC sync anchors -> curated defaults.
    addon:Print("")
    local defaults, source
    if SpellQueue and SpellQueue.GetBurstTriggerInfo then
        defaults, source = SpellQueue.GetBurstTriggerInfo()
    end
    addon:Print("Burst Triggers (" .. (specKey or "?") .. ", source: "
        .. (source or "|cff888888none|r") .. "):")
    if defaults and #defaults > 0 then
        for i, spellID in ipairs(defaults) do
            local name = "?"
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then name = spellInfo.name end

            local resolvedID = BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(spellID) or spellID
            local resolvedTag = (resolvedID ~= spellID) and (" -> " .. resolvedID) or ""

            local known = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(resolvedID)
            local knownTag = known and "|cff00ff00known|r" or "|cffff6666not known|r"

            local stateTag = ""
            if known then
                local onCd = BlizzardAPI and BlizzardAPI.IsSpellOnCooldown and BlizzardAPI.IsSpellOnCooldown(resolvedID)
                stateTag = onCd and " |cffff6600on CD|r" or " |cff00ff00READY|r"
                -- The cue table is keyed by the QUEUE entry id (display form) plus the
                -- raw AC pick - probe all three forms so this mirrors the runtime keys.
                local displayID = BlizzardAPI and BlizzardAPI.GetDisplaySpellID
                    and BlizzardAPI.GetDisplaySpellID(resolvedID) or resolvedID
                if SpellQueue and SpellQueue.IsBurstCue
                   and (SpellQueue.IsBurstCue(spellID) or SpellQueue.IsBurstCue(resolvedID)
                        or SpellQueue.IsBurstCue(displayID)) then
                    stateTag = stateTag .. " |cffb048f8CUED|r"
                end
            end

            addon:Print("  " .. i .. ". " .. name .. " (" .. spellID .. resolvedTag .. ") " .. knownTag .. stateTag)
        end
    else
        addon:Print("  |cff888888(none defined for this spec)|r")
    end

    addon:Print("==================================")
end

--------------------------------------------------------------------------------
-- Pre-combat buff checklist diagnostics
--------------------------------------------------------------------------------
function DebugCommands.PrecombatBuffDiagnostics(addon)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local Engine  = LibStub("JustAC-PrecombatEngine", true)
    addon:Print("===== Pre-combat Buffs =====")
    if not SpellDB or not SpellDB.GetPrecombatBuffCategories or not Engine then
        addon:Print("|cffff6666PrecombatEngine / data not loaded.|r")
        return
    end
    if InCombatLockdown() then
        addon:Print("|cffffff00In combat - detection is out-of-combat only. Re-run after combat.|r")
        return
    end

    for _, cat in ipairs(SpellDB.GetPrecombatBuffCategories()) do
        local items = SpellDB.GetPrecombatBuffItems(cat) or {}
        local satisfied = Engine.IsCategorySatisfied(cat)
        local best = SpellDB.GetBestOwnedBuff(cat)
        local bestName = best and ((GetItemInfo(best.id)) or ("item " .. best.id))
        local statTag = best and best.stat and (" |cff888888[" .. best.stat .. "]|r") or ""
        local state = satisfied and "|cff00ff00active|r"
            or (best and "|cffff6666MISSING|r" or "|cff888888missing, none owned|r")
        addon:Print(string.format("%s (%d known): %s%s%s", cat, #items, state,
            bestName and ("  best owned: " .. bestName) or "", statTag))
    end

    local missing = Engine.GetMissingBuffs()
    addon:Print("---- would surface ----")
    if #missing == 0 then
        addon:Print("|cff00ff00Nothing missing (or nothing owned to fix it).|r")
    else
        for _, m in ipairs(missing) do
            local nm = (GetItemInfo(m.entry.id)) or ("item " .. m.entry.id)
            addon:Print("  " .. m.category .. " -> " .. nm)
        end
    end

    -- Class maintained buffs (poisons/shields): dump the AC demand chain the picks
    -- defer to, so a wrong pick can be traced to its source (api read / queue head /
    -- rotation list / default fallback).
    local class = select(2, UnitClass("player"))
    local groups = SpellDB.CLASS_MAINTAINED_BUFFS and class
        and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function SpellName(id)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name or "spell") .. " (" .. id .. ")"
    end
    local anyNext = BAPI and BAPI.GetAnyNextCastSpell and BAPI.GetAnyNextCastSpell()
    local SQ = LibStub("JustAC-SpellQueue", true)
    local queue = SQ and SQ.GetCurrentSpellQueue and SQ.GetCurrentSpellQueue()
    local head = type(queue) == "table" and queue[1] or nil
    if head and issecretvalue and issecretvalue(head) then head = nil end
    if groups then
        addon:Print("---- class buffs (AC deference) ----")
        addon:Print("  AC demand: api(any)=" .. (anyNext and SpellName(anyNext) or "|cff888888nil|r")
            .. "  queue[1]=" .. (head and SpellName(head) or "|cff888888nil|r"))
        local rot = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
        for gi, grp in ipairs(groups) do
            local inRot = {}
            for _, id in ipairs(grp.group) do
                if rot then
                    for i = 1, #rot do
                        if rot[i] == id then inRot[#inRot + 1] = SpellName(id) break end
                    end
                end
            end
            addon:Print(string.format("  group %d: rotation-listed: %s", gi,
                #inRot > 0 and table.concat(inRot, ", ") or "|cff888888none|r"))
        end
        for _, s in ipairs(Engine.GetMissingClassBuffs(addon.db.profile.precombatBuffs.topoffHeal,
                addon.db.profile.precombatBuffs.topoffThreshold) or {}) do
            addon:Print("  offering: " .. SpellName(s))
        end
    end

    -- TEMPORARY probe: Paladin Auras as maintained-buff candidates. A data audit
    -- (2026-08-09) found 465/32223/183435 fit the maintained-group pattern, but
    -- Auras are stance-style toggles - before adding a PALADIN group we must see
    -- (a) whether the by-cast-id aura probe detects an active Aura (else the group
    -- would false-nag every paladin), and (b) whether AC ever demands one (the
    -- demand line above). Run with each Aura active in turn, and once with none.
    if class == "PALADIN" then
        addon:Print("---- paladin aura probe ----")
        addon:Print("  AC demand: api(any)=" .. (anyNext and SpellName(anyNext) or "|cff888888nil|r")
            .. "  queue[1]=" .. (head and SpellName(head) or "|cff888888nil|r"))
        local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        for _, id in ipairs({ 465, 32223, 183435 }) do
            local a = get and get(id)
            addon:Print(string.format("  %s known=%s auraByCastId=%s", SpellName(id),
                tostring(IsPlayerSpell(id)), a and "|cff00ff00YES|r" or "|cffff6666no|r"))
        end
        -- Discovery dump: every readable helpful aura on the player, so a differing
        -- aura id (cast id != aura id) shows up by name.
        local auras = BAPI and BAPI.GetAuras and BAPI.GetAuras("player", "HELPFUL")
        if auras then
            for i = 1, #auras do
                local sid, nm = auras[i].spellId, auras[i].name
                if sid and not (issecretvalue and issecretvalue(sid))
                   and not (nm and issecretvalue and issecretvalue(nm)) then
                    addon:Print("  helpful: " .. tostring(nm) .. " (" .. sid .. ")")
                end
            end
        end
    end

    -- Recuperate gate-by-gate probe (health-conditioned class buff)
    addon:Print("---- Recuperate ----")
    if not SpellDB.RECUPERATE then
        addon:Print("|cffff6666SpellDB.RECUPERATE not defined (old data?).|r")
    else
        local sid = SpellDB.RECUPERATE
        local known = IsPlayerSpell(sid)
        local knownAlt = (IsSpellKnown and IsSpellKnown(sid)) or false
        local restricted = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
        local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        local hotUp = get and get(SpellDB.RECUPERATE_AURA) ~= nil
        local activeUp = get and get(sid) ~= nil
        local BAPI = LibStub("JustAC-BlizzardAPI", true)
        local pct = BAPI and BAPI.GetPlayerHealthPercent and BAPI.GetPlayerHealthPercent()
        local safePct, estimated
        if BAPI and BAPI.GetPlayerHealthPercentSafe then
            safePct, estimated = BAPI.GetPlayerHealthPercentSafe()
        end
        local hasRestrictions = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
        addon:Print("  known: IsPlayerSpell=" .. tostring(known) .. " IsSpellKnown=" .. tostring(knownAlt))
        addon:Print("  aura restricted: " .. tostring(restricted or false)
            .. "  secret restrictions: " .. tostring(hasRestrictions or false))
        addon:Print("  HoT (" .. tostring(SpellDB.RECUPERATE_AURA) .. ") up: " .. tostring(hotUp)
            .. "  active aura (" .. sid .. ") up: " .. tostring(activeUp))
        local activity = BAPI and BAPI.HasRecentPlayerHealthActivity and BAPI.HasRecentPlayerHealthActivity()
        local sustained = BAPI and BAPI.HasSustainedPlayerHealthActivity and BAPI.HasSustainedPlayerHealthActivity()
        addon:Print("  health exact: " .. (pct and string.format("%.1f%%", pct) or "|cffff6666unreadable|r")
            .. "  safe: " .. (safePct and string.format("%.1f%%", safePct) or "nil")
            .. (estimated and " |cffffff00(vignette estimate)|r" or "")
            .. " (offer below 90%)" .. (dead and "  |cffff6666DEAD/GHOST|r" or ""))
        addon:Print("  health event activity: recent=" .. tostring(activity or false)
            .. " sustained=" .. tostring(sustained or false) .. " (sustained drives the offer)")
        -- Fill-width probe: Blizzard's player frame sets its health fill from the
        -- secret value engine-side. If the fill texture's LAID-OUT width reads as a
        -- plain number, width/barWidth = exact health fraction even where UnitHealth
        -- is secret - that would replace the activity heuristic outright.
        local function FillRatio()
            local hb = PlayerHealthBar()
            if not hb then return "|cff888888no healthbar frame found|r" end
            local ok, ratio = pcall(function()
                local tex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
                local w = tex and tex:GetWidth()
                local full = hb:GetWidth()
                if w and full and full > 0 then return (w / full) * 100 end
                return nil
            end)
            if not ok then return "|cffff6666SEALED (read threw - idea dead)|r" end
            if not ratio then return "|cff888888no width available|r" end
            return string.format("|cff00ff00%.1f%% (READABLE - compare to your real health!)|r", ratio)
        end
        addon:Print("  health-bar fill-width probe: " .. FillRatio())
        local surfaced = false
        for _, s in ipairs(Engine.GetMissingClassBuffs(addon.db.profile.precombatBuffs.topoffHeal,
                addon.db.profile.precombatBuffs.topoffThreshold) or {}) do
            if s == sid then surfaced = true break end
        end
        addon:Print("  would surface: " .. (surfaced and "|cff00ff00YES|r" or "|cffff6666NO|r"))
    end
    addon:Print("============================")
end

--------------------------------------------------------------------------------
-- Fixed-Queue Context Rank Diagnostics
--------------------------------------------------------------------------------
-- Dumps the inferred combat context (from the AC pick, post execute-latch and
-- sticky-multi smoothing) and each queue spell's profile-distance rank. Every
-- value shown is non-secret by construction, so this is safe to run in combat.
function DebugCommands.ContextRankDiagnostics(addon)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not SpellQueue or not SpellQueue.DebugContextState then
        addon:Print("|cffff0000SpellQueue not loaded|r")
        return
    end

    local function spellName(id)
        if id < 0 then
            local name = GetItemInfo and GetItemInfo(-id)
            return name or ("item " .. -id)
        end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name) or "?"
    end

    local ctx = SpellQueue.DebugContextState()
    addon:Print("=== Fixed-Queue Context Rank ===")
    if ctx.pickID then
        addon:Print("AC pick: " .. spellName(ctx.pickID) .. " (" .. ctx.pickID .. ")")
    else
        addon:Print("AC pick: |cff888888none|r")
    end
    addon:Print(string.format("Context: arch=%s range=%s role=%s%s",
        tostring(ctx.arch), tostring(ctx.range), tostring(ctx.role),
        ctx.stickyApplied and " |cffadd8e6(sticky multi)|r" or ""))
    addon:Print(string.format("Execute: %s%s  OutOfMelee: %s",
        tostring(ctx.execute),
        ctx.executeLatched and " |cffadd8e6(latched)|r" or "",
        tostring(ctx.outOfMelee)))
    -- Wasted-cooldown guard. Prints WHY it is off as well as whether it is: the
    -- enemy count and the boss read are the two clauses that silently keep it off,
    -- and a guard that never fires looks identical to one that is broken.
    -- Fetched locally: BlizzardAPI is not a file-local here, and reading it bare
    -- would be a nil global (a probe that errors instead of reporting).
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local dyingWhy
    if ctx.dying then
        dyingWhy = "|cffff8800sinking burst cooldowns|r"
    elseif (ctx.enemies or 0) ~= 1 then
        dyingWhy = string.format("|cff888888off - engaged enemies = %d (needs exactly 1)|r",
            ctx.enemies or 0)
    elseif BAPI and BAPI.IsTargetBoss and BAPI.IsTargetBoss() then
        dyingWhy = "|cff888888off - target is a boss (execute phase, burn everything)|r"
    elseif not UnitExists("target") then
        dyingWhy = "|cff888888off - no target|r"
    else
        dyingWhy = "|cff888888off - target above the threshold (or gate unavailable)|r"
    end
    addon:Print("Dying-target guard: " .. dyingWhy)

    -- State the ACTIVE ordering mode, not just the disabled case. In "simc" - the default -
    -- the sort key is a COMPOSITE (context * stride + SimC position), applied within buckets
    -- that run procs -> normal -> unavailable. Printing the bare context rank there shows the
    -- major key only, so a spell sunk for being uncastable reads as a mis-sorted one. That is
    -- how a healthy queue (Rip rank=4 below Rake rank=5, because Rip was in the sunk bucket)
    -- looks like an ordering bug.
    local profile = addon.db and addon.db.profile
    local mode = (profile and profile.contextOrder) or "simc"
    if mode == "off" then
        addon:Print("|cffffff00Ordering: OFF|r - source order; ranks below are NOT applied.")
    elseif mode == "ac" then
        addon:Print("|cff00ff00Ordering: ac|r - the rank below IS the sort key.")
    else
        addon:Print("|cff00ff00Ordering: simc|r - sort key is |cffffff00ctx*stride + simc|r, "
            .. "bucketed procs -> normal -> unavailable. The rank below is the ctx part only.")
    end

    addon:Print("")
    addon:Print("Queue (rank 0 = best match ... 9 = uncastable sink; the AC slot is never reordered):")
    local queue = SpellQueue.GetCurrentSpellQueue()
    if not queue or #queue == 0 then
        addon:Print("  |cff888888(empty)|r")
        addon:Print("================================")
        return
    end
    for i, sid in ipairs(queue) do
        if sid > 0 then
            local arch = SpellDB and SpellDB.GetArch and SpellDB.GetArch(sid)
            local range = SpellDB and SpellDB.GetRange and SpellDB.GetRange(sid)
            local role = SpellDB and SpellDB.GetRole and SpellDB.GetRole(sid)
            local gate = SpellDB and SpellDB.GetGate and SpellDB.GetGate(sid)
            -- In simc mode show the SimC component too: context alone cannot explain the
            -- order, and the pair does - two spells sharing a context rank are separated by
            -- it, and one sitting below a worse context rank was bucketed, not mis-sorted.
            local rankTag
            if i == 1 then
                rankTag = "|cff888888AC slot|r"
            else
                rankTag = "rank=" .. tostring(SpellQueue.DebugRankSpell and SpellQueue.DebugRankSpell(sid))
                if mode ~= "off" and mode ~= "ac" then
                    local RI = LibStub("JustAC-RotationImport", true)
                    local simcCtx = (ctx.arch == "aoe" and "aoe")
                        or (ctx.arch == "cleave" and "cleave") or "st"
                    local rec = RI and RI.GetEntry and RI.GetEntry(sid, simcCtx)
                    rankTag = rankTag .. " simc=" .. tostring((rec and rec.rank) or "unranked")
                end
            end
            addon:Print(string.format("  %d. %s (%d)  arch=%s range=%s role=%s gate=%s  %s",
                i, spellName(sid), sid, tostring(arch), tostring(range), tostring(role), tostring(gate), rankTag))
        else
            addon:Print(string.format("  %d. %s (item)  rank=1 (neutral)", i, spellName(sid)))
        end
    end
    addon:Print("================================")
end

--------------------------------------------------------------------------------
-- DoT Tracker Diagnostics
--------------------------------------------------------------------------------
--- Dumps the maintained-DoT tracking state for the current target: which tracked
--- DoTs are considered live (sunk), whether presence is confirmed via the aura
--- instance bridge or the post-cast window, and the pandemic-refresh countdown.
--- Every value is non-secret (our own cast timing + NeverSecret instance IDs).
function DebugCommands.DotDiagnostics(addon)
    local DotTracker = LibStub("JustAC-DotTracker", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not DotTracker or not DotTracker.DebugState then
        addon:Print("|cffff0000DotTracker not loaded|r")
        return
    end

    local function spellName(id)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name) or "?"
    end

    local s = DotTracker.DebugState()
    addon:Print("=== Maintained DoT Tracking (current target) ===")
    addon:Print(string.format("Target: %s  |  pending casts: %d",
        s.hasTarget and "yes" or "|cff888888none|r", s.pending))
    if not s.hasTarget then
        addon:Print("|cff888888(no target)|r")
        addon:Print("================================")
        return
    end
    if #s.entries == 0 then
        addon:Print("  |cff888888No tracked DoTs applied to this target.|r")
        addon:Print("================================")
        return
    end
    for _, e in ipairs(s.entries) do
        local est = SpellDB and SpellDB.GetTargetDotDuration and SpellDB.GetTargetDotDuration(e.spellID)
        -- engine= is what DECIDED when it is not nil; est/pandemicIn is the
        -- cast-time projection it replaced. They diverge on a pandemic-refreshed
        -- DoT, where the projection fires early - the case this exists to fix.
        local engine = (e.enginePandemic == nil) and "|cff888888n/a (estimate used)|r"
            or (e.enginePandemic and "|cffffaa00INSIDE pandemic|r" or "|cff2ecc71live|r")
        addon:Print(string.format("  %s (%d)  %s  src=%s  expiresIn=%.1fs%s  est=%s  engine=%s",
            spellName(e.spellID), e.spellID,
            e.active and "|cffff5555SUNK|r" or "|cff55ff55shown|r",
            e.confirmed and "instance" or "window",
            e.expiresIn,
            e.pandemicIn and string.format("  pandemicIn=%.1fs", e.pandemicIn) or "",
            est and (est .. "s") or "unknown", engine))
    end
    addon:Print("================================")
end

--------------------------------------------------------------------------------
-- SimC Gate Diagnostics
--------------------------------------------------------------------------------
--- /jac inspect gates - SimC gate layer: the self-buff-window tracker plus a LIVE
--- per-entry gate evaluation for the current spec. Run it in combat to watch the
--- secret-safe signals (cooldown / dot / proc / buff-window) actually fire, so we
--- can tell whether the gate layer works against the 12.0 secret limits or silently
--- does nothing.
function DebugCommands.GateDiagnostics(addon)
    local RI = LibStub("JustAC-RotationImport", true)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local DotTracker = LibStub("JustAC-DotTracker", true)
    if not (RI and RI.HasRotation and RI.HasRotation()) then
        addon:Print("|cffff6600No SimC gate data for this spec.|r")
        return
    end

    local nm = SpellLabel

    addon:Print("|cff00ccff== SimC gate diagnostics ==|r")

    -- Buff windows the AC pick IMPLIES - revealed even when the aura is secret (the probe below
    -- can't see secret auras). Siblings gated on these promote off the pick.
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local pickWindows = (SpellQueue and SpellQueue.DebugContextState and SpellQueue.DebugContextState() or {}).pickWindows
    if pickWindows and next(pickWindows) then
        local names = {}
        for id in pairs(pickWindows) do names[#names + 1] = nm(id) end
        addon:Print("|cffffff00AC pick implies window up:|r " .. table.concat(names, ", "))
    end

    -- Self-buff windows (engine-truth via duration-object probe).
    local stList = RI.GetRotation and RI.GetRotation("st")
    local snap = stList and BAPI and BAPI.GetBuffWindowSnapshot and BAPI.GetBuffWindowSnapshot(stList)
    if snap and #snap > 0 then
        addon:Print("|cffffff00Self-buffs on the ST list:|r")
        for _, w in ipairs(snap) do
            addon:Print(string.format("  %s  %s", nm(w.id),
                w.active and "|cff00ff00ACTIVE|r" or "|cff888888--|r"))
        end
    end

    -- Live per-entry gate evaluation for each context.
    local function gateStr(e)
        if not e.gates or #e.gates == 0 then
            return e.delegated and "|cff888888delegated, no gates|r" or "no gates"
        end
        local parts, negBlocked = {}, false
        for _, g in ipairs(e.gates) do
            if g.t == "cd" then
                local ok = BAPI.IsSpellReady and BAPI.IsSpellReady(e.id)
                parts[#parts + 1] = "cd=" .. (ok and "|cff00ff00rdy|r" or "|cffff6600cd|r")
            elseif g.t == "dot" then
                local live = DotTracker and DotTracker.IsDotActiveOnCurrentTarget
                    and DotTracker.IsDotActiveOnCurrentTarget(g.id)
                parts[#parts + 1] = "dot=" .. (live and "|cffff6600up|r" or "|cff00ff00refresh|r")
            elseif g.t == "proc" then
                local ok = BAPI.IsSpellProcced and BAPI.IsSpellProcced(e.id)
                parts[#parts + 1] = "proc=" .. (ok and "|cff00ff00Y|r" or "|cff888888n|r")
            elseif g.t == "buff" then
                local ok = BAPI.IsBuffWindowActive and BAPI.IsBuffWindowActive(g.id)
                local viaPick = pickWindows and pickWindows[g.id]
                local state = ok and "|cff00ff00up|r"
                    or (viaPick and "|cff00ff00up(pick)|r" or "|cff888888--|r")
                if g.neg and ok then negBlocked = true end
                parts[#parts + 1] = (g.neg and "!" or "") .. "buff[" .. tostring(g.id) .. "]=" .. state
            elseif g.t == "targets" then
                parts[#parts + 1] = "|cff888888targets|r"
            elseif g.t == "execute" then
                parts[#parts + 1] = "|cff888888execute|r"
            end
        end
        local s = table.concat(parts, " ")
        if negBlocked then s = s .. " |cffff6600[neg-blocked]|r" end
        if e.delegated then s = s .. " |cff888888[deleg]|r" end
        return s
    end

    for _, ctx in ipairs({ "st", "aoe" }) do
        local entries = RI.GetRotationGated and RI.GetRotationGated(ctx)
        if entries then
            addon:Print("|cffffff00" .. ctx:upper() .. ":|r")
            for _, e in ipairs(entries) do
                addon:Print("  " .. nm(e.id) .. "  " .. gateStr(e))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Duration-object boolean probe (secret-safe readiness)
--------------------------------------------------------------------------------
--- /jac inspect durprobe [spell] - verify the scratch-Cooldown IsShown() technique:
--- feed a DurationObject (real cooldown / self-buff aura) into a hidden Cooldown
--- frame and read IsShown() as a plain, branchable boolean. The remaining TIME stays
--- secret, but the active/inactive boolean is readable - which is all a gate needs.
--- Run it in combat with a cooldown down and a self-buff up to confirm both read
--- correctly; this boolean is the foundation the SimC gate layer will branch on.
function DebugCommands.DurationProbe(addon, arg)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        addon:Print("|cffff6600C_Spell.GetSpellCooldownDuration unavailable - can't probe|r")
        return
    end

    -- Reusable Cooldown frame under a HIDDEN holder (never renders). Its shown state
    -- is driven by SetCooldownFromDurationObject, so IsShown() is a plain boolean =
    -- "cooldown/aura active" without ever reading the secret remaining time.
    local scratch = DebugCommands._durScratch
    if not scratch then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        scratch = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
        DebugCommands._durScratch = scratch
    end
    local function durActive(durObj)
        if durObj == nil or not scratch.SetCooldownFromDurationObject then return nil end
        scratch:SetCooldownFromDurationObject(durObj)
        local shown = scratch:IsShown()
        scratch:SetCooldown(0, 0)
        return shown
    end
    local function boolTag(b, t, f)
        if b == nil then return "|cff888888nil|r" end
        return b and ("|cff00ff00" .. t .. "|r") or ("|cffcccccc" .. f .. "|r")
    end
    local nm = SpellLabel

    addon:Print("|cff00ccff== duration-object boolean probe ==|r")
    addon:Print("combat: " .. (UnitAffectingCombat("player")
        and "|cff00ff00YES|r" or "|cff888888no (probe is only meaningful in combat)|r"))

    -- Which spells: explicit arg, else AC's rotation list (first 6).
    local ids = {}
    if arg and arg ~= "" then
        local id = tonumber(arg)
        if not id and C_Spell.GetSpellIDForSpellIdentifier then
            id = C_Spell.GetSpellIDForSpellIdentifier(arg)
        end
        if id then ids[1] = id end
    end
    if #ids == 0 and BAPI and BAPI.GetRotationSpells then
        local list = BAPI.GetRotationSpells()
        if list then for i = 1, math.min(6, #list) do ids[i] = list[i] end end
    end
    if #ids == 0 then
        addon:Print("no spells to probe - pass a spellID/name, or use a spec with a rotation")
        return
    end

    addon:Print("|cffffff00Cooldown (ignore-GCD duration object -> IsShown):|r")
    for _, id in ipairs(ids) do
        local onCD = durActive(C_Spell.GetSpellCooldownDuration(id, true))
        -- Cross-check the numeric API so you can see what is secret vs. what we read.
        local numStr = "no data"
        local ci = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
        if ci then
            local st, act = ci.startTime, ci.isActive
            numStr = IsSecret(st) and "|cffff6600startTime SECRET|r" or ("startTime=" .. tostring(st))
            if not IsSecret(act) and act ~= nil then
                numStr = numStr .. " isActive=" .. tostring(act)
            end
        end
        local secrecy = C_Secrets and C_Secrets.GetSpellCooldownSecrecy
            and C_Secrets.GetSpellCooldownSecrecy(id)
        addon:Print(string.format("  %-26s probe=%s  %s%s", nm(id),
            boolTag(onCD, "ON-CD", "ready"), numStr,
            secrecy ~= nil and ("  secrecy=" .. tostring(secrecy)) or ""))
    end

    -- Direct method sweep (68887 audit): the docs claim IsActive/IsZero/HasStarted/
    -- HasExpired/HasSecretValues return PLAIN booleans even on a secret-backed
    -- duration object. If IsActive() reads plain in combat and agrees with the
    -- scratch probe, it supersedes the scratch-Cooldown technique entirely.
    local function methodSweep(label, durObj, scratchResult)
        if durObj == nil then
            addon:Print("  " .. label .. ": |cff888888no duration object|r")
            return
        end
        local parts = {}
        for _, m in ipairs({ "IsActive", "IsZero", "HasStarted", "HasExpired", "HasSecretValues" }) do
            local fn = durObj[m]
            if type(fn) ~= "function" then
                parts[#parts + 1] = m .. "=|cff888888absent|r"
            else
                local ok, v = pcall(fn, durObj)
                if not ok then
                    parts[#parts + 1] = m .. "=|cffff6600THREW|r"
                elseif IsSecret(v) then
                    parts[#parts + 1] = m .. "=|cffff6600SECRET|r"
                else
                    parts[#parts + 1] = m .. "=|cff00ff00" .. tostring(v) .. "|r"
                end
            end
        end
        addon:Print(string.format("  %s: %s  (scratch says %s)", label,
            table.concat(parts, " "), tostring(scratchResult)))
    end
    addon:Print("|cffffff00DurationObject method sweep (plain per 68887 docs - verify):|r")
    do
        local id = ids[1]
        local durObj = C_Spell.GetSpellCooldownDuration(id, true)
        methodSweep("cd " .. nm(id), durObj, durActive(durObj))
    end

    addon:Print("|cffffff00Self-buffs present (aura duration object -> IsShown):|r")
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetAuraDuration) then
        addon:Print("  |cffff6600C_UnitAuras.GetAuraDuration unavailable|r")
        return
    end
    local anyAura = false
    for _, id in ipairs(ids) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
        local instId = aura and aura.auraInstanceID
        if instId then
            local durObj = C_UnitAuras.GetAuraDuration("player", instId)
            local active = durActive(durObj)
            addon:Print(string.format("  %-26s probe=%s", nm(id), boolTag(active, "ACTIVE", "expired")))
            if not anyAura then -- method sweep on the first aura duration object only
                methodSweep("aura " .. nm(id), durObj, active)
            end
            anyAura = true
        end
    end
    if not anyAura then
        addon:Print("  |cff888888(none of the probed spells are active self-buffs right now)|r")
    end
    addon:Print("|cff888888Goal: in combat, numeric SECRET but probe still reads ON-CD/ready + ACTIVE.|r")
end

--------------------------------------------------------------------------------
-- Enrage-detection probe
--------------------------------------------------------------------------------
--- /jac inspect enrage [off] - validate the DispelType==9 (Enrage) secret-safe path.
--- dispelName hides Enrage, but GetAuraDispelTypeColor maps an aura's NUMERIC dispel
--- type (9 = Enrage) through a color curve; auraInstanceID is NeverSecret, and the
--- combat-secret color sinks into SetVertexColor (AllowedWhenTainted) with no read.
--- This arms a LIVE on-screen row - one slot per target buff - each slot lit WHITE ==
--- that buff is a DispelType-9 enrage. Pull a confirmed-soothe-able mob and watch a
--- slot light up: that is the whole "target enraged -> Soothe cue" chain, proven, with
--- zero reads. The text scan also decodes each buff's type where readable (OOC) to
--- calibrate the number line (a Magic buff -> type=1 == its dispelName).
--- '/jac inspect enrage off' hides the row.
function DebugCommands.EnrageProbe(addon, arg)
    local cu       = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    local gadtc    = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
    local gadbi    = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not (cu and cu.CreateColorCurve and stepType and CreateColor and gadtc and gadbi) then
        addon:Print("|cffff6600Missing API (need CreateColorCurve + LuaCurveType.Step + GetAuraDispelTypeColor)|r")
        return
    end

    if arg == "off" then
        if DebugCommands._enrSwatch then DebugCommands._enrSwatch:Hide() end
        addon:Print("enrage live indicator hidden.")
        return
    end

    addon:Print("|cff00ccff== enrage probe (DispelType 9 via GetAuraDispelTypeColor) ==|r")

    -- Selector curve the real feature uses: white/alpha 1 only when dispel type == 9.
    local sel = cu.CreateColorCurve()
    sel:SetType(stepType)
    sel:AddPoint(0,  CreateColor(0, 0, 0, 0))
    sel:AddPoint(9,  CreateColor(1, 1, 1, 1))
    sel:AddPoint(10, CreateColor(0, 0, 0, 0))

    -- Identity curve: r = dispelTypeId/32 (Step holds each point), so OOC we can read the
    -- raw dispel type back for calibration (a Magic buff should decode to 1, etc.).
    local ident = cu.CreateColorCurve()
    ident:SetType(stepType)
    for k = 0, 15 do ident:AddPoint(k, CreateColor(k / 32, 0, 0, 1)) end

    -- Text scan: decode each unit's HELPFUL auras where readable (secret in combat).
    local function scan(unit)
        if not UnitExists(unit) then return end
        addon:Print("|cffffff00" .. unit .. ":|r")
        local any = false
        for i = 1, 40 do
            local a = gadbi(unit, i, "HELPFUL")
            if not a then break end
            any = true
            local decoded, note, idc
            if pcall(function() idc = gadtc(unit, a.auraInstanceID, ident) end) and idc then
                if IsSecret(idc.r) then note = "SECRET" else decoded = math.floor((idc.r or 0) * 32 + 0.5) end
            else
                note = "call-failed"
            end
            local name = (a.name and not IsSecret(a.name)) and tostring(a.name) or "|cff888888?secret?|r"
            local dn   = a.dispelName
            local dnStr = (dn and not IsSecret(dn) and dn ~= "") and (" dispelName=" .. dn) or ""
            local dtStr = decoded and ("type=" .. decoded .. (decoded == 9 and " |cffff3333<ENRAGE>|r" or ""))
                                  or ("type=|cffff6600" .. tostring(note) .. "|r")
            addon:Print(string.format("  [%s] %-20s %s%s", tostring(a.auraInstanceID), name, dtStr, dnStr))
        end
        if not any then addon:Print("  |cff888888(no HELPFUL auras)|r") end
    end
    scan("player")
    scan("target")

    -- Feature-path gates. The scans above answer "is this enrage DETECTABLE"; they say nothing
    -- about why the cue is not on screen, which is a different question with six separate ways
    -- to fail. Walk them in the order the real code does and name the first one that is false.
    addon:Print("|cff00ccff== soothe cue gates ==|r")
    local function gate(label, ok, detail)
        addon:Print(string.format("  %s %s%s", ok and "|cff00ff00PASS|r" or "|cffff3333FAIL|r",
            label, detail and (" |cff888888(" .. detail .. ")|r") or ""))
        return ok
    end

    local UISootheCue = LibStub("JustAC-UISootheCue", true)
    local SDB = LibStub("JustAC-SpellDB", true)
    local profile = addon.db and addon.db.profile

    gate("UISootheCue library loaded", UISootheCue ~= nil)
    if UISootheCue then
        gate("UISootheCue.Available() (API + selector curve)", UISootheCue.Available())
    end

    -- interruptMode "disabled" destroys the interrupt icon, and the cue is parented to it -
    -- so a disabled kick reminder silently takes the soothe cue with it.
    local mode = profile and profile.interruptMode or "kickPrefer"
    gate("interruptMode ~= disabled", mode ~= "disabled", "mode=" .. tostring(mode))
    local dm = profile and profile.displayMode or "queue"
    addon:Print(string.format("  |cff888888displayMode=%s (the standard-queue cue needs queue/both; "
        .. "overlay has its own)|r", tostring(dm)))

    local soothe = addon.resolvedSoothe
    local sid = soothe and soothe[1] and soothe[1].spellID
    if gate("ResolveSootheSpells() returned a spell", sid ~= nil,
            sid and ("spellID=" .. sid) or "nil - no known soothe for this spec") and SDB then
        -- The castability gate inside UISootheCue.Show: an on-cooldown soothe hides the whole
        -- cue, so a stuck cooldown state looks exactly like "detection broken".
        local onCD = SDB.IsInterruptOnCooldown and SDB.IsInterruptOnCooldown(sid)
        gate("soothe not on cooldown (UISootheCue.Show gate)", not onCD,
             onCD and "IsSpellReady says NOT ready" or "ready")
    end

    local intIcon = addon.interruptIcon
    gate("interrupt icon exists (cue anchor)", intIcon ~= nil)
    if intIcon then
        local cue = intIcon.sootheCue
        gate("cue frame created", cue ~= nil)
        if cue then gate("cue frame shown", cue:IsShown()) end
    end

    gate("target exists", UnitExists("target"))
    gate("target attackable", UnitExists("target") and UnitCanAttack("player", "target") or false)

    -- Live on-screen indicator: a slot per target HELPFUL aura, driven each frame by the
    -- selector via SetVertexColor. A slot lit WHITE == that buff is a DispelType-9 enrage.
    -- Works IN COMBAT: the secret color sinks straight into the fill; we never read it.
    local sw = DebugCommands._enrSwatch
    if not sw then
        sw = CreateFrame("Frame", nil, UIParent)
        sw:SetSize(8 * 30 + 12, 54)
        sw:SetPoint("CENTER", 0, 170)
        sw:SetFrameStrata("HIGH")
        local bg = sw:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
        local t = sw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("TOP", 0, -3)
        t:SetText("enrage test: a slot glows = DispelType-9 enrage   (/jac inspect enrage off)")
        sw.slots = {}
        for i = 1, 8 do
            local s = CreateFrame("Frame", nil, sw)
            s:SetSize(26, 26)
            s:SetPoint("BOTTOMLEFT", 6 + (i - 1) * 30, 5)
            local d = s:CreateTexture(nil, "BACKGROUND"); d:SetAllPoints(); d:SetColorTexture(0.16, 0.16, 0.16, 1)
            local f = s:CreateTexture(nil, "ARTWORK");    f:SetAllPoints(); f:SetColorTexture(1, 1, 1, 1)
            local l = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l:SetPoint("TOP", s, "BOTTOM", 0, -1)
            s.fill = f; s.lbl = l
            sw.slots[i] = s
        end
        DebugCommands._enrSwatch = sw
    end
    sw.sel = sel
    sw:SetScript("OnUpdate", function(self, e)
        self._t = (self._t or 0) + e
        if self._t < 0.1 then return end
        self._t = 0
        for i = 1, 8 do
            local s = self.slots[i]
            local a = UnitExists("target") and C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL") or nil
            if a then
                s:Show()
                s.lbl:SetText(tostring(a.auraInstanceID))
                pcall(function()
                    local c = C_UnitAuras.GetAuraDispelTypeColor("target", a.auraInstanceID, self.sel)
                    s.fill:SetVertexColor(c.r, c.g, c.b, c.a)
                end)
            else
                s:Hide()
            end
        end
    end)
    sw:Show()

    addon:Print("|cff888888Live row armed. Pull your confirmed-soothe-able mob - the slot for the enrage buff should glow WHITE (selector fires at type 9): full chain proven, no reads. '/jac inspect enrage off' to hide.|r")
end

--------------------------------------------------------------------------------
-- AoE-context probe
--------------------------------------------------------------------------------
--- /jac inspect range - settle which range API answers against the CURRENT target.
--- The SPELL path (C_Spell.IsSpellInRange) feeds IsTargetWithin - so the gap closer,
--- the melee sink, and off-bar hotkey reds. The SLOT path (C_ActionBar.IsActionInRange)
--- feeds on-bar hotkey reds. Run it three times: on a fresh target while the gap
--- closer shows, after it wedges, and right after retargeting - whichever column
--- changes between runs is the culprit.
function DebugCommands.RangeProbe(addon)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local GapCloser = LibStub("JustAC-GapCloserEngine", true)
    addon:Print("=== Range probe ===")
    if not UnitExists("target") then
        addon:Print("No target - target the mob first, then run this again.")
        return
    end
    local isSecret = BlizzardAPI and BlizzardAPI.IsSecretValue
    local function fmt(v)
        if v == nil then return "|cff888888nil|r" end
        if isSecret and isSecret(v) then return "|cffff00ffSECRET|r" end
        if v == true or v == 1 then return "|cff2ecc71in|r" end
        return "|cffff6666OUT|r"
    end
    local function nameOf(id)
        local info = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(id)
        return (info and info.name) or ("spell " .. tostring(id))
    end

    -- 1. The melee/near verdicts the gap closer consumes.
    if SpellDB and SpellDB.IsTargetWithin then
        local parts = {}
        for _, y in ipairs({ 5, 8, 10, 25, 40 }) do
            local v = SpellDB.IsTargetWithin(y)
            parts[#parts + 1] = y .. "yd=" .. (v == nil and "|cff888888nil|r" or tostring(v))
        end
        addon:Print("  IsTargetWithin: " .. table.concat(parts, "  "))
    end

    -- 2. Every known range reference, raw spell-path answer.
    if SpellDB and SpellDB.DebugRangeProbes then
        local probes = SpellDB.DebugRangeProbes()
        addon:Print("  References (" .. #probes .. " known):")
        for i = 1, #probes do
            local p = probes[i]
            addon:Print(string.format("    %s (%d, %dyd): %s", nameOf(p.id), p.id, p.ref, fmt(p.r)))
        end
    end

    -- 3. Current queue spells: spell path vs slot path side by side.
    local queue = SpellQueue and SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue() or {}
    addon:Print("  Queue (spell path / slot path):")
    for i = 1, math.min(#queue, 6) do
        local sid = queue[i]
        if sid and sid > 0 then
            local spellR = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(sid, "target")
            local slot = ActionBarScanner and ActionBarScanner.GetDirectSlotForSpell
                and ActionBarScanner.GetDirectSlotForSpell(sid)
            local slotR
            if slot and C_ActionBar and C_ActionBar.IsActionInRange then
                slotR = C_ActionBar.IsActionInRange(slot, "target")
            end
            addon:Print(string.format("    %d. %s: spell=%s  slot=%s%s", i, nameOf(sid), fmt(spellR),
                slot and fmt(slotR) or "|cff888888no direct slot|r",
                slot and (" (#" .. slot .. ")") or ""))
        end
    end

    -- 4. The gap-closer verdict, plus each candidate's OWN gates - the verdict can
    -- flip on the candidate's own cast range (e.g. Wild Charge's ~25yd cap) while
    -- every melee-band reading above stays constant, so print the discriminators.
    if GapCloser and GapCloser.GetGapCloserSpell then
        local gid = GapCloser.GetGapCloserSpell(addon, {})
        addon:Print("  Gap closer verdict: " .. (gid and (nameOf(gid) .. " (" .. gid .. ")") or "|cff888888none|r"))
        if GapCloser.MarkGapCloserSpellIDs then
            local set = {}
            GapCloser.MarkGapCloserSpellIDs(addon, set)
            for id in pairs(set) do
                local ownR = BlizzardAPI and BlizzardAPI.SpellInRange and BlizzardAPI.SpellInRange(id)
                local ready = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(id)
                addon:Print(string.format("    candidate %s (%d): own-range=%s  ready=%s",
                    nameOf(id), id, ownR == nil and "|cff888888nil|r" or fmt(ownR), tostring(ready)))
            end
        end
    end
end

--- /jac inspect aoe - Test whether we can count nearby enemies DIRECTLY (nameplate
--- enumeration + per-unit checks) without tripping 12.0 secret values, i.e. an
--- AC-independent AoE signal. Every value is tested with issecretvalue BEFORE it is
--- branched on, so the probe itself never trips a secret.
function DebugCommands.AoeDiagnostics(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("|cff00ccff== AoE-context probe (secret-safe enemy counting) ==|r")
    local pc = UnitAffectingCombat("player")
    addon:Print("player in combat: " .. (IsSecret(pc) and "|cffff6600SECRET|r"
        or "|cff00ff00" .. tostring(pc) .. "|r"))

    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        addon:Print("|cffff6600C_NamePlate.GetNamePlates unavailable|r")
        return
    end
    local plates = C_NamePlate.GetNamePlates()
    local total = plates and #plates or 0
    addon:Print("nameplates enumerated: " .. total
        .. "  (count secret=" .. tostring(IsSecret(total)) .. ")")

    -- Nameplate FRAMES are restricted in 12.0 (their fields read secret/nil), so
    -- resolve via the unit TOKENS directly (nameplate1..40) and filter: hostile,
    -- then within AoE range. Range - not "in combat" - is the useful AoE proxy,
    -- since you AoE targets that are NEAR you before they're engaged.
    local nUnits, nHostile, nRange, nCombat, nThreat = 0, 0, 0, 0, 0
    local sExists, sHostile, sRange, sCombat, sThreat = false, false, false, false, false
    local RANGE_PROBE = 1822  -- Rake (melee ~5yd); placeholder AoE-range check
    for i = 1, 40 do
        local u = "nameplate" .. i
        local ex = UnitExists(u)
        if IsSecret(ex) then
            sExists = true
        elseif ex then
            nUnits = nUnits + 1
            local ca = UnitCanAttack("player", u)   -- value first, secret-test before branching
            if IsSecret(ca) then
                sHostile = true
            elseif ca then
                nHostile = nHostile + 1
                local r = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(RANGE_PROBE, u)
                if IsSecret(r) then sRange = true elseif r then nRange = nRange + 1 end
                local ic = UnitAffectingCombat(u)              -- engaged with anyone
                if IsSecret(ic) then sCombat = true elseif ic then nCombat = nCombat + 1 end
                local threatFn = _G.UnitThreatSituation         -- on its threat table = fighting ME
                if threatFn then
                    local ts = threatFn("player", u)
                    if IsSecret(ts) then sThreat = true elseif ts ~= nil then nThreat = nThreat + 1 end
                end
            end
        end
    end

    local function line(label, n, s)
        addon:Print(string.format("  %-36s %d  %s", label, n,
            s and "|cffff6600<hit SECRET>|r" or "|cff00ff00secret-safe|r"))
    end
    line("nameplate units", nUnits, sExists)
    line("hostile (UnitCanAttack)", nHostile, sHostile)
    line("+ in melee range", nRange, sRange)
    line("+ engaged (UnitAffectingCombat)", nCombat, sCombat)
    line("+ fighting me (UnitThreatSituation)", nThreat, sThreat)

    -- Compare with AC's own context signal (the thing we're trying to replicate
    -- WITHOUT AC). AC's pick + its archetype is exactly how the queue infers AoE today.
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local pick = BAPI and BAPI.GetNextCastSpell and BAPI.GetNextCastSpell()
    local arch = pick and SpellDB and SpellDB.GetArch and SpellDB.GetArch(pick)
    addon:Print(string.format("|cffffff00AC view:|r pick=%s  archetype=|cff00ccff%s|r",
        pick and tostring(pick) or "none", tostring(arch or "?")))
    addon:Print("|cff888888Pull 1 vs 3+ mobs and re-run: does the direct hostile count track "
        .. "reality (secret-safe), and does it agree with AC's archetype?|r")
end

--------------------------------------------------------------------------------
-- Resource-inference probe
--------------------------------------------------------------------------------
--- /jac inspect resource - Test whether we can infer resource availability from
--- per-ability usability WITHOUT reading the (secret) resource value. Confirms the
--- direct UnitPower read is secret, then checks C_Spell.IsSpellUsable's
--- insufficientPower flag per rotation ability (secret-tested before use).
function DebugCommands.ResourceDiagnostics(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("|cff00ccff== Resource-inference probe ==|r")

    -- 1. The direct read we're routing around (expected SECRET in combat).
    if UnitPower and UnitPowerType then
        local pt = UnitPowerType("player")
        local val = UnitPower("player", pt)
        addon:Print("UnitPower direct read: " .. (IsSecret(val)
            and "|cffff6600SECRET (can't read)|r" or "|cff00ff00" .. tostring(val) .. "|r"))
    end

    -- 2. Per-ability usability: C_Spell.IsSpellUsable -> (usable, insufficientPower).
    local RI = LibStub("JustAC-RotationImport", true)
    local list = (RI and RI.GetRotation and RI.GetRotation("st"))
        or (BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells())
    if not list or #list == 0 then
        addon:Print("|cffff6600no spell list for this spec|r")
        return
    end

    -- Static resource cost per ability (NeverSecret spell data), so the ladder is visible.
    local function costStr(id)
        local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(id)
        if type(costs) ~= "table" or #costs == 0 then return "-" end
        local parts = {}
        for _, c in ipairs(costs) do
            local pn = (c.name or ""):lower():gsub("_", ""):sub(1, 6)
            parts[#parts + 1] = tostring(c.cost or "?") .. (pn ~= "" and (" " .. pn) or "")
        end
        return table.concat(parts, "+")
    end

    local anySecret = false
    addon:Print("|cffffff00ability | cost | cd | usable | resource|r")
    for _, id in ipairs(list) do
        local ready = BAPI.IsSpellReady and BAPI.IsSpellReady(id)
        local usable, noPower = C_Spell.IsSpellUsable(id)
        local secHit = IsSecret(usable) or IsSecret(noPower)
        if secHit then anySecret = true end
        local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or id
        local tag
        if secHit then
            tag = "|cffff6600SECRET|r"
        else
            tag = (ready and "rdy" or "|cff888888cd|r")
                .. " | " .. (usable and "|cff00ff00usable|r" or "no")
                .. " | " .. (noPower and "|cffffcc00LOW|r" or "|cff00ff00ok|r")
        end
        addon:Print(string.format("  %-20s %-12s %s", tostring(name), costStr(id), tag))
    end
    if anySecret then
        addon:Print("|cffff6600IsSpellUsable returned SECRET - resource inference not viable.|r")
    else
        addon:Print("|cff888888'LOW' = blocked by resource specifically. Spend down and re-run: "
            .. "the costliest ability still 'ok' brackets your resource - no secret read needed. "
            .. "(Pooled accumulators like combo points don't hard-gate, so they show no floor.)|r")
    end
end

--------------------------------------------------------------------------------
-- Rotation-order probe: is GetRotationSpells' tail LIVE?
--------------------------------------------------------------------------------
--- /jac inspect rotation - settle whether C_AssistedCombat.GetRotationSpells() is a LIVE
--- priority list (positions 2+ re-ordered against the secret state each call) or a static
--- rotation set where only [1] tracks the live pick. Dumps the current list beside the
--- GetNextCastSpell pick, then diffs against the previous run so you can A/B it: run, change
--- state (burn a proc, dump resources, add or drop a target), run again. If positions 2+
--- reorder between runs, Blizzard is handing us its own "what to press after slot 1" and we
--- could lean on it directly instead of inferring; if only [1] moves, only the pick is live.
--- Spell IDs and the pick are NeverSecret, so nothing here reads a secret value.
local lastRotationSnap  -- { ids = {...}, pick = id } from the previous invocation
function DebugCommands.RotationOrderProbe(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function nm(id)
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or ("spell " .. tostring(id))
    end
    if not (BAPI and BAPI.GetRotationSpells) then
        addon:Print("GetRotationSpells API unavailable")
        return
    end
    local list = BAPI.GetRotationSpells()
    local pick = BAPI.GetNextCastSpell and BAPI.GetNextCastSpell()
    if not list or #list == 0 then
        addon:Print("|cffff6600GetRotationSpells returned nothing|r - target an enemy / enter combat and retry")
        return
    end

    addon:Print(string.format("|cff00ccff== Rotation-order probe ==|r  %d entries   pick (GetNextCastSpell): %s",
        #list, pick and nm(pick) or "|cff888888none|r"))
    for i = 1, #list do
        local mark = (pick and list[i] == pick) and "  |cff2ecc71<- AC pick|r" or ""
        addon:Print(string.format("  %2d. %-26s (%d)%s", i, nm(list[i]), list[i], mark))
    end
    if pick then
        addon:Print("  [1] tracks the live pick: " .. (list[1] == pick
            and "|cff2ecc71yes|r" or "|cffff6666NO (list[1] != GetNextCastSpell)|r"))
    end

    -- Single-run verdict: an ascending-by-spell-ID list is the rotation SET sorted by id, not a
    -- priority order - so its tail carries no ranking and only GetNextCastSpell is live.
    local idSorted = true
    for i = 2, #list do
        if list[i] < list[i - 1] then idSorted = false break end
    end
    if idSorted then
        addon:Print("  |cffffd100order is ascending by spell ID|r - the id-sorted rotation SET, not a "
            .. "priority list; only GetNextCastSpell carries live priority (tail unusable for ordering)")
    end

    -- Diff vs the previous run to expose whether the TAIL re-orders with state.
    local prev = lastRotationSnap
    if prev then
        local now = {}
        for i = 1, #list do now[list[i]] = i end
        local prevSet = {}
        for i = 1, #prev.ids do prevSet[prev.ids[i]] = i end
        local addedIds, removedIds = {}, {}
        for i = 1, #list do if not prevSet[list[i]] then addedIds[#addedIds + 1] = list[i] end end
        for i = 1, #prev.ids do if not now[prev.ids[i]] then removedIds[#removedIds + 1] = prev.ids[i] end end
        -- Pair a same-NAME add+remove as one form/talent VARIANT swap (Moonfire 8921<->155625 on
        -- shifting to cat form), so it reads as a swap instead of a spurious add+remove.
        local swaps, added, removed, usedAdd = {}, {}, {}, {}
        for _, rid in ipairs(removedIds) do
            local paired = false
            for j, aid in ipairs(addedIds) do
                if not usedAdd[j] and nm(aid) == nm(rid) then
                    usedAdd[j] = true
                    swaps[#swaps + 1] = string.format("%s %d->%d", nm(rid), rid, aid)
                    paired = true
                    break
                end
            end
            if not paired then removed[#removed + 1] = nm(rid) .. " (" .. rid .. ")" end
        end
        for j, aid in ipairs(addedIds) do
            if not usedAdd[j] then added[#added + 1] = nm(aid) .. " (" .. aid .. ")" end
        end

        local sameSeq = (#list == #prev.ids)
        if sameSeq then
            for i = 1, #list do
                if list[i] ~= prev.ids[i] then sameSeq = false break end
            end
        end

        -- Tail relative-order test: among ids in BOTH prev[2..] and now, did any pair swap
        -- relative order? (excludes prev's old head, which a cast would legitimately consume).
        local commonTail = {}
        for i = 2, #prev.ids do
            if now[prev.ids[i]] then commonTail[#commonTail + 1] = prev.ids[i] end
        end
        local tailReordered = false
        for a = 1, #commonTail do
            for b = a + 1, #commonTail do
                if now[commonTail[a]] > now[commonTail[b]] then tailReordered = true break end
            end
            if tailReordered then break end
        end

        addon:Print("|cffffff00vs last run:|r")
        addon:Print("  pick: " .. (prev.pick == pick and "unchanged"
            or ("changed " .. (prev.pick and nm(prev.pick) or "none")
                .. " -> " .. (pick and nm(pick) or "none"))))
        if #swaps > 0 then addon:Print("  variant swap (same name, form/talent): " .. table.concat(swaps, ", ")) end
        if #added > 0 then addon:Print("  added: " .. table.concat(added, ", ")) end
        if #removed > 0 then addon:Print("  removed: " .. table.concat(removed, ", ")) end
        if sameSeq then
            addon:Print("  order: |cff888888identical to last run|r - change your state between runs to test")
        elseif tailReordered then
            addon:Print("  order: |cff2ecc71TAIL REORDERED|r - positions 2+ re-prioritized: evidence "
                .. "GetRotationSpells is LIVE-ordered, so its tail could feed the queue directly")
        else
            addon:Print("  order: changed, but positions 2+ kept their relative order (looks like the "
                .. "head just advanced / set changed) - no live-tail evidence this round")
        end
    else
        addon:Print("|cff888888baseline captured.|r Change your state (burn a proc, dump resources, "
            .. "add/drop a target) and run |cffffd100/jac inspect rotation|r again to see if positions 2+ move")
    end

    local ids = {}
    for i = 1, #list do ids[i] = list[i] end
    lastRotationSnap = { ids = ids, pick = pick }
end

--------------------------------------------------------------------------------
-- Class resource-point probe: can we read the resource COUNT without a secret?
--------------------------------------------------------------------------------
--- /jac inspect resourcepoints - discrete class resources (combo points, holy power, chi,
--- soul shards, runes, essence, arcane charges) are drawn as one widget PER POINT. Blizzard's
--- own bars branch on the secret UnitPower in privileged code - `point:SetActive(i <= count)`
--- - and leave the answer behind as ORDINARY frame state (an `isActive` field plus shown /
--- alpha visuals). If those read back PLAIN for an addon we get an exact resource count for
--- free, no secret touched - the same idiom as the scratch-Cooldown IsShown() readiness probe.
--- That would let the rotation actually evaluate builder/spender gates instead of delegating.
--- Dumps every point with its state + secrecy, and the derived count to eyeball against your
--- real resource. Read-only, so no taint risk.
-- Mirrors BlizzardAPI.GetClassResourcePoints' per-bar shape table. Enum semantics belong to the
-- BAR, not the field name: Paladin and DK both use `visualState` with DIFFERENT enums.
local RESOURCE_BAR_FRAMES = {
    -- 12.x PRD builds its own class frame as the global `prdClassFrame` (live whenever PRD is on).
    { "PersonalResourceDisplayFrame.classFrame", class="DRUID",   event="UNIT_POWER_FREQUENT" },
    { "PersonalResourceDisplayFrame.classFrame", class="ROGUE",   event="UNIT_POWER_FREQUENT" },
    { "PersonalResourceDisplayFrame.classFrame", class="MONK",    event="UNIT_POWER_FREQUENT" },
    { "PersonalResourceDisplayFrame.classFrame", class="WARLOCK", event="UNIT_POWER_FREQUENT" },
    { "PersonalResourceDisplayFrame.classFrame", class="MAGE",    event="UNIT_POWER_FREQUENT" },
    { "PersonalResourceDisplayFrame.classFrame", class="EVOKER",  event="UNIT_POWER_FREQUENT" },
    { "PersonalResourceDisplayFrame.classFrame", class="PALADIN", event="UNIT_POWER_FREQUENT", indexed="rune",
      state="visualState", min=1, max=3, isFilled=function(v) return v > 1 end },
    { "PersonalResourceDisplayFrame.classFrame", class="DEATHKNIGHT", event="RUNE_POWER_UPDATE", array="Runes",
      state="visualState", min=1, max=4, isFilled=function(v) return v == 4 end },
    { "DruidComboPointBarFrame", class="DRUID", event="UNIT_POWER_FREQUENT" }, { "RogueComboPointBarFrame", class="ROGUE", event="UNIT_POWER_FREQUENT" }, { "MonkHarmonyBarFrame", class="MONK", event="UNIT_POWER_FREQUENT" },
    { "WarlockPowerFrame", class="WARLOCK", event="UNIT_POWER_FREQUENT" }, { "MageArcaneChargesFrame", class="MAGE", event="UNIT_POWER_FREQUENT" }, { "EssencePlayerFrame", class="EVOKER", event="UNIT_POWER_FREQUENT" },
    { "PaladinPowerBarFrame", class="PALADIN", event="UNIT_POWER_FREQUENT", indexed = "rune", state = "visualState", min = 1, max = 3,
      isFilled = function(v) return v > 1 end },
    { "RuneFrame", class="DEATHKNIGHT", event="RUNE_POWER_UPDATE", array = "Runes", state = "visualState", min = 1, max = 4,
      isFilled = function(v) return v == 4 end },
    -- Personal Resource Display equivalents (separate globals, same shapes). These keep updating
    -- when an addon that replaces the player unit frame hides Blizzard's own bars.
    { "ClassNameplateBarFeralDruidFrame", class="DRUID", event="UNIT_POWER_FREQUENT" }, { "ClassNameplateBarRogueFrame", class="ROGUE", event="UNIT_POWER_FREQUENT" },
    { "ClassNameplateBarWindwalkerMonkFrame", class="MONK", event="UNIT_POWER_FREQUENT" }, { "ClassNameplateBarWarlockFrame", class="WARLOCK", event="UNIT_POWER_FREQUENT" },
    { "ClassNameplateBarMageFrame", class="MAGE", event="UNIT_POWER_FREQUENT" }, { "ClassNameplateBarDracthyrFrame", class="EVOKER", event="UNIT_POWER_FREQUENT" },
    { "ClassNameplateBarPaladinFrame", class="PALADIN", event="UNIT_POWER_FREQUENT", indexed = "rune", state = "visualState", min = 1, max = 3,
      isFilled = function(v) return v > 1 end },
    { "DeathKnightResourceOverlayFrame", class="DEATHKNIGHT", event="RUNE_POWER_UPDATE", array = "Runes", state = "visualState", min = 1, max = 4,
      isFilled = function(v) return v == 4 end },
}
function DebugCommands.ResourcePointProbe(addon)
    addon:Print("|cff00ccff== Class resource-point probe ==|r")

    -- Context: the personal resource display re-parents these same bars, so note its state.
    -- GetNamePlateForUnit's 2nd arg is includeForbidden - the personal plate is a FORBIDDEN
    -- frame, so passing false returns nil and the PRD looks "off" while plainly on screen.
    -- The CVar is the authoritative switch; also report the 12.x PRD frames directly.
    local prdOn = GetCVarBool and GetCVarBool("nameplateShowSelf")
    local function frameState(f) return f and (f:IsShown() and "|cff00ff00shown|r" or "hidden") or "|cff888888nil|r" end
    addon:Print(string.format("  personal resource display: %s   PersonalResourceDisplayFrame=%s  prdClassFrame=%s",
        prdOn and "|cff00ff00ON|r" or "|cff888888off|r",
        frameState(_G.PersonalResourceDisplayFrame), frameState(_G.prdClassFrame)))

    local found, framesSeen = 0, {}
    local _, playerClass = UnitClass("player")
    for _, def in ipairs(RESOURCE_BAR_FRAMES) do
        local name = def[1]
        -- Only this character's bars; another class's global exists but is never initialised.
        -- Dotted paths are walked: the PRD class bar has no global of its own (SetupClassBar
        -- creates it with a nil name arg), so it is only reachable as a field.
        local bar = nil
        if def.class == playerClass then
            for part in name:gmatch("[^.]+") do
                bar = (bar == nil) and _G[part] or bar[part]
                if bar == nil then break end
            end
        end
        local points = bar and bar.classResourceButtonTable
        if bar and (not points or #points == 0) and def.array then
            local a = bar[def.array]
            if type(a) == "table" and #a > 0 then points = a end
        end
        if bar and (not points or #points == 0) and def.indexed then
            points = {}
            for i = 1, 10 do
                local p = bar[def.indexed .. i]
                if not p then break end
                points[i] = p
            end
        end
        if bar then framesSeen[#framesSeen + 1] = name end
        if type(points) == "table" and #points > 0 then
            found = found + 1
            local shown = bar:IsShown()
            local reg = def.event and bar.IsEventRegistered and bar:IsEventRegistered(def.event)
            addon:Print(string.format("|cffffff00%s|r  points=%d  barShown=%s  %s=%s%s",
                name, #points, SafeSecret(shown), def.event or "evt", SafeSecret(reg),
                (shown or reg) and "" or "  |cffff6600(hidden+unregistered -> frozen)|r"))
            -- Classes store the filled flag under different names (Druid isActive, Monk active,
            -- Rogue isFull); show whichever reads as a real boolean, and which field it came from.
            local BOOL_FIELDS = { "isActive", "active", "isFull", "isCharged" }
            local FILL_FIELDS = { "fillAmount" }   -- numeric 0..1 (Warlock fractional shards)
            local active, readable, anySecret, usedField = 0, 0, false, nil
            for i = 1, #points do
                -- raw = what the widget actually stores; val = the filled-ness we derive from it.
                -- Showing both matters: a bare "visualState=0" hides whether the enum was 1 or 4.
                local p, val, from, raw = points[i], nil, nil, nil
                for _, f in ipairs(BOOL_FIELDS) do
                    local v = p and p[f]
                    if IsSecret(v) then anySecret = true end
                    if val == nil and type(v) == "boolean" then val, from, raw = (v and 1 or 0), f, v end
                end
                for _, f in ipairs(FILL_FIELDS) do
                    local v = p and p[f]
                    if IsSecret(v) then anySecret = true end
                    if val == nil and type(v) == "number" and v >= 0 and v <= 1 then val, from, raw = v, f, v end
                end
                if val == nil and def.state and def.isFilled then
                    local v = p and p[def.state]
                    if IsSecret(v) then anySecret = true end
                    if type(v) == "number" and v % 1 == 0 and v >= def.min and v <= def.max then
                        val, from, raw = (def.isFilled(v) and 1 or 0), def.state, v
                    end
                end
                if val ~= nil then
                    readable = readable + 1
                    usedField = usedField or from
                    active = active + val
                end
                addon:Print(string.format("   %2d. %s raw=%s -> filled=%s  IsShown=%s  alpha=%s", i,
                    from or "|cffff6600<no readable field>|r", SafeSecret(raw), SafeSecret(val),
                    SafeSecret(p and p:IsShown()), SafeSecret(p and p:GetAlpha())))
            end
            if anySecret then
                addon:Print("   |cffff6600a point field reads SECRET - count not derivable|r")
            elseif readable == #points then
                -- %.10g, not %d: fractional fills (a partly-charged shard) are real and must show.
                addon:Print(string.format("   |cff2ecc71derived count = %.10g|r (field '%s')"
                    .. "  <- compare to your real resource; if it matches, this is readable",
                    active, tostring(usedField)))
            else
                addon:Print(string.format("   |cffff6600only %d/%d points expose a boolean flag|r"
                    .. " - this bar's shape is unmapped, so the reader returns nil (fails open)",
                    readable, #points))
            end
        end
    end
    if found == 0 then
        if #framesSeen > 0 then
            -- The frame is a CLASS-wide global, so its existence says nothing about this SPEC:
            -- it is created for every Monk but only populated for the one with chi. Zero points
            -- usually means "this spec has no such resource", not a mapping gap. Don't blame a
            -- "continuous resource" either; that misdiagnoses e.g. Holy Power, which is discrete
            -- but uses an unmapped widget layout.
            addon:Print("|cffff6600bar frame(s) present but no readable points|r: "
                .. table.concat(framesSeen, ", ")
                .. " - most likely this SPEC has no such resource (the frame is class-wide and"
                .. " stays empty), or the bar is hidden, or its widget layout is unmapped."
                .. " Fails open.")
        else
            addon:Print("|cffff6600no discrete class-resource bar found|r - this spec likely uses a"
                .. " continuous resource (energy/rage/mana), which is bar-fill rather than points.")
        end
    end
end

--------------------------------------------------------------------------------
-- Secrecy census: MEASURE what is readable instead of inferring it from source
--------------------------------------------------------------------------------
--- /jac inspect secrecy - the empirical answer to "can we read X in combat?".
--- Reading source tells us what SHOULD be secret; it has twice been wrong in our favour
--- (the scratch-Cooldown IsShown() readiness probe and the class-resource point read are
--- both unintended engine behaviour that no amount of source reading would have predicted).
--- So: actually call each candidate and measure it.
---
--- Three columns, because they can DISAGREE and the disagreement is the interesting part:
---   secret?     - what issecretvalue() claims. Safe to call on anything.
---   branchable? - whether `if v then end` actually runs. This is the measurement that
---                 matters: it is what a gate in the queue would really do.
---   comparable? - whether `v > 0` runs. Ordering is what a threshold test needs, and it
---                 can fail where plain truthiness succeeds.
--- Every probe is wrapped in pcall, so an unreadable value reports instead of erroring.
--- CONTROL CASES are included on purpose and labelled: entries we are confident are plain
--- and entries we are confident are secret. If a control comes back the wrong way, the
--- probe itself (or our whole model) is wrong - check those lines first.
--- Run it OUT of combat and again IN combat; the difference is the whole point.
-- Built ONCE at file load, deliberately NOT lazily on first probe run. Creating a frame from
-- a slash-command stack means creating it inside JustAC's taint, and if that happens in
-- combat the taint can spread through the frame hierarchy - which surfaced as an unrelated
-- addon being "blocked from an action". Load time is before any of that. Unparented for the
-- same reason: nothing here is ever shown, so it needs no parent and must not touch UIParent.
local secrecyScratchBar
do
    local f = CreateFrame("Frame")
    f:Hide()
    local bar = CreateFrame("StatusBar", nil, f)   -- native StatusBar, NOT SmoothStatusBarMixin
    bar:SetSize(100, 10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    secrecyScratchBar = bar
end

--- First active Cooldown Manager item frame, or nil. Its OnUpdate only runs while the viewer
--- is SHOWN, so a nil here means "not laid out", never "secret".
local function FirstCooldownViewerItem()
    local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer",
                      "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    for i = 1, #VIEWERS do
        local v = _G[VIEWERS[i]]
        local pool = v and v.itemFramePool
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                -- Active is not enough: items are assigned an id by layoutIndex, so a pooled
                -- frame can be active with cooldownID still nil. Require the id.
                local ok, id = pcall(function() return item and item:GetCooldownID() end)
                if ok and id then return item end
            end
        end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CLOSED 2026-07-20: the combat log is NOT available to us in 12.0.
-- Registering COMBAT_LOG_EVENT_UNFILTERED produces "AddOn 'JustAC' has been blocked" -
-- from a slash command AND from addon load, so it is a hard restriction, not taint.
-- That kills the combat log as a data source, and with it the only route to exact aura
-- STACK counts (aura.applications reads SECRET in combat; SPELL_AURA_APPLIED_DOSE would
-- have carried the count plainly). Coherent with the secret-value system: the combat log
-- would otherwise hand back every exact number secrets exist to hide.
-- Do not re-add a CLEU listener anywhere in this addon.
-- ─────────────────────────────────────────────────────────────────────────────

--- How many HELPFUL aura instances are on the player. Counting INSTANCES needs no secret
--- read: the table's presence is plain even in combat, and auraInstanceID is NeverSecret -
--- it is only the contents (spellId, applications, duration) that go secret. This is the
--- test that decides whether a stacking self-buff is countable: an aura that applies as N
--- separate instances can be counted exactly via the same bridge DotTracker already uses,
--- while one instance carrying a stack counter cannot, because the counter is secret.
local function CountPlayerAuraInstances()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local n = 0
    for i = 1, 60 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not data then break end
        n = n + 1
    end
    return n
end

--- Classify one candidate read. Never throws.
function ClassifyRead(fn)   -- forward-declared local, see ProbeReport
    local status, text, v = ProbeRead(fn, 24)
    if status == "err" then return "|cffff6600ERROR|r " .. text end
    if status == "nil" then return "|cff888888nil|r (absent - not evidence either way)" end

    local isSecret = status == "secret"
    -- `if v then` is ALLOWED on a secret NUMBER (its truthiness is always true, so it leaks
    -- nothing) but THROWS on a secret BOOLEAN (there, truthiness IS the secret). That is the
    -- whole rule: the engine permits exactly the operations that leak no information. So this
    -- column is only interesting when the value is a boolean.
    local branchOk = pcall(function() if v then return 1 end return 0 end)
    -- Ordering is only meaningful for numbers - `false > 0` is a TYPE error, not secrecy, and
    -- reporting that as "n" made plain booleans look blocked in the first run of this probe.
    local isNum = (type(v) == "number") or (isSecret and not pcall(function() return v == true end))
    local cmpOk = isNum and pcall(function() return v > 0 end) or false

    local shown = isSecret and "|cffff6600SECRET|r" or ("|cff2ecc71plain|r=" .. text)
    return string.format("%s [%s] branch:%s cmp:%s", shown, type(v),
        branchOk and "|cff2ecc71y|r" or "|cffff6600n THROWS|r",
        isNum and (cmpOk and "|cff2ecc71y|r" or "|cffff6600n|r") or "|cff888888-|r")
end

--- /jac inspect stacks - settle whether a stacking self-buff is N aura INSTANCES or ONE
--- instance carrying a counter. Run it OUT OF COMBAT, where spellId and applications are
--- both plain, so this reads the answer directly instead of inferring it.
--- Multi-instance -> countable in combat via the instance bridge DotTracker already uses
--- (auraInstanceID is NeverSecret). One-instance-with-counter -> dead, the counter is secret.
function DebugCommands.StacksProbe(addon)
    if InCombatLockdown() then
        addon:Print("|cffff6600Run this OUT of combat|r - in combat spellId and applications are")
        addon:Print("secret and the whole point is to read them directly.")
        return
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        addon:Print("|cffff6600C_UnitAuras unavailable|r")
        return
    end

    local bySpell, order = {}, {}
    for i = 1, 60 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not d then break end
        local sid = d.spellId
        if type(sid) == "number" then
            local e = bySpell[sid]
            if not e then
                e = { instances = 0, apps = d.applications, name = d.name, ids = {} }
                bySpell[sid] = e
                order[#order + 1] = sid
            end
            e.instances = e.instances + 1
            e.ids[#e.ids + 1] = d.auraInstanceID
        end
    end

    addon:Print("== aura stack shape (out of combat) ==")
    addon:Print("|cff888888apply a stacking buff a few times, then re-run|r")
    local multi = 0
    for _, sid in ipairs(order) do
        local e = bySpell[sid]
        -- The distinction that decides everything: more than one INSTANCE of the same
        -- spellId means each application is its own aura (countable via the bridge);
        -- one instance with applications > 1 means a secret counter (not countable).
        local shape
        if e.instances > 1 then
            shape = string.format("|cff2ecc71MULTI-INSTANCE x%d|r -> countable in combat", e.instances)
            multi = multi + 1
        elseif (e.apps or 1) > 1 then
            shape = string.format("|cffff6600STACKING counter=%d|r -> NOT countable (secret in combat)", e.apps)
        else
            shape = "single"
        end
        if e.instances > 1 or (e.apps or 1) > 1 then
            addon:Print(string.format("  %7d %-26s %s", sid, tostring(e.name):sub(1, 26), shape))
        end
    end
    addon:Print(string.format("|cff888888%d spell(s) apply as multiple instances.|r", multi))
end

function DebugCommands.SecrecyProbe(addon)
    local pf = _G.PlayerFrame
    local pfHealth = pf and (pf.healthBar or pf.healthbar)
    local ct = _G.CombatText
    local caa = _G.CombatAudioAlertManager

    -- {label, fn, note}. Order groups related hypotheses together.
    local PROBES = {
        { "-- CONTROLS (validate the probe itself) --" },
        { "LowHealthFrame:IsShown()", function() return _G.LowHealthFrame and _G.LowHealthFrame:IsShown() end,
          "expect PLAIN - we already ship this" },
        { "UnitHealth('player')", function() return UnitHealth("player") end,
          "expect SECRET in combat" },
        { "UnitHealthMax('player')", function() return UnitHealthMax("player") end },
        { "UnitPower('player')", function() return UnitPower("player") end,
          "expect SECRET in combat" },
        { "UnitPowerMax('player')", function() return UnitPowerMax("player") end },

        { "-- CURVE FAMILY (we called this closed - verify) --" },
        { "UnitHealthPercent(scaleTo100)", function()
            return UnitHealthPercent and UnitHealthPercent("player", nil,
                _G.CurveConstants and _G.CurveConstants.ScaleTo100) end },
        { "UnitPowerPercent(scaleTo100)", function()
            return UnitPowerPercent and UnitPowerPercent("player", nil,
                _G.CurveConstants and _G.CurveConstants.ScaleTo100) end },

        { "-- STATUSBAR GEOMETRY (we called this closed - verify) --" },
        { "PlayerFrame health:GetValue()", function() return pfHealth and pfHealth:GetValue() end },
        { "PlayerFrame healthTex:GetWidth()", function()
            return pfHealth and pfHealth:GetStatusBarTexture():GetWidth() end },
        { "PlayerFrame healthTex:GetTexCoord()", function()
            local a = { pfHealth:GetStatusBarTexture():GetTexCoord() }; return a[7] end,
          "the line 12.0_COMPATIBILITY says reads secret" },
        { "scratch bar GetValue() after SetValue(secret)", function()
            secrecyScratchBar:SetMinMaxValues(0, 100)
            secrecyScratchBar:SetValue(UnitHealth("player"))
            return secrecyScratchBar:GetValue() end },
        { "scratch bar texture:GetWidth()", function()
            secrecyScratchBar:SetMinMaxValues(0, UnitHealthMax("player"))
            secrecyScratchBar:SetValue(UnitHealth("player"))
            return secrecyScratchBar:GetStatusBarTexture():GetWidth() end,
          "if PLAIN: narrow the band = chooseable threshold = binary search" },
        { "scratch bar texture:IsShown()", function()
            return secrecyScratchBar:GetStatusBarTexture():IsShown() end },

        { "-- AURA TIMING (the pandemic 'close to lapsing' logic rests on this) --" },
        { "aura[1] table itself", function()
            return C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL") ~= nil end },
        { "aura[1].expirationTime", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.expirationTime end,
          "RedundancyFilter caches this OOC to compute pandemic - is that still possible?" },
        { "aura[1].duration", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.duration end },
        { "aura[1].applications (stacks)", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.applications end },
        { "aura[1].spellId", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.spellId end },

        { "-- AURA INSTANCES (does a stacking buff = N instances or 1 with a counter?) --" },
        { "player HELPFUL instance count", function() return CountPlayerAuraInstances() end,
          "cast Ironfur twice: +2 = multi-instance (countable), +1 then +0 = stacking (dead)" },
        { "aura[1].auraInstanceID", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.auraInstanceID end,
          "DotTracker relies on this being NeverSecret - verify it holds in combat" },
        { "IsAuraFilteredOutByInstanceID readable", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
            if not (a and a.auraInstanceID and C_UnitAuras.IsAuraFilteredOutByInstanceID) then return nil end
            return C_UnitAuras.IsAuraFilteredOutByInstanceID("player", a.auraInstanceID, "HELPFUL|PLAYER") end,
          "the bridge that identifies an instance as OURS without reading spellId" },

        { "-- SECRET BOOLEANS (branch:n here is the crash class) --" },
        { "aura[1].canApplyAura (bool field)", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.canApplyAura end,
          "a secret BOOLEAN throws on `if v then` - unlike a secret number" },
        { "aura[1].isHelpful (bool field)", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.isHelpful end },
        { "party1 aura presence (bool)", function()
            return C_UnitAuras.GetPlayerAuraBySpellID and
                (C_UnitAuras.GetAuraDataBySpellName and
                 C_UnitAuras.GetAuraDataBySpellName("party1", "x", "HELPFUL") ~= nil) end,
          "the shape that crashed PrecombatEngine:235" },

        { "-- ABSORB GLOWS (if/else Show/Hide -> expect PLAIN) --" },
        { "which PlayerFrame health bar exists", function()
            local pfh = _G.PlayerFrame and (_G.PlayerFrame.healthBar or _G.PlayerFrame.healthbar)
            if not pfh then return "no healthBar/healthbar" end
            local keys = {}
            for _, k in ipairs({ "overAbsorbGlow", "overHealAbsorbGlow", "healAbsorbBar",
                                "totalAbsorb", "myHealPrediction" }) do
                if pfh[k] ~= nil then keys[#keys + 1] = k end
            end
            return (#keys > 0) and table.concat(keys, ",") or "none of the absorb subwidgets"
            end,
          "tells us whether the nils below are a wrong path or a real absence" },
        { "overAbsorbGlow:IsShown()", function()
            return pfHealth and pfHealth.overAbsorbGlow and pfHealth.overAbsorbGlow:IsShown() end },
        { "overHealAbsorbGlow:IsShown()", function()
            return pfHealth and pfHealth.overHealAbsorbGlow and pfHealth.overHealAbsorbGlow:IsShown() end },
        { "healAbsorbBar.LeftShadow:IsShown()", function()
            return pfHealth and pfHealth.healAbsorbBar and pfHealth.healAbsorbBar.LeftShadow
                and pfHealth.healAbsorbBar.LeftShadow:IsShown() end,
          "SetShown(expr) -> expect SECRET. If plain, our screening rule is WRONG" },

        { "-- COMBAT TEXT (fixed 20%; needs floating combat text ON) --" },
        { "CombatText:IsVisible()", function() return ct and ct:IsVisible() end,
          "if false, lowHealth/lowMana never update - false negative" },
        { "CombatText.lowHealth", function() return ct and ct.lowHealth end },
        { "CombatText.lowMana", function() return ct and ct.lowMana end,
          "first branchable MANA signal, if it holds" },

        { "-- COMBAT AUDIO ALERTS (needs the accessibility setting + a party) --" },
        { "CAA partyHealthInfo.unitCount", function()
            return caa and caa.partyHealthInfo and caa.partyHealthInfo.unitCount end },
        { "CAA unitInfo['player'] present", function()
            return caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
                and (caa.partyHealthInfo.unitInfo["player"] ~= nil) end },
        { "CAA unitInfo['player'].frequency", function()
            return caa.partyHealthInfo.unitInfo["player"].frequency end,
          "Lerp'd from health % -> expect SECRET. If PLAIN this IS the health number" },

        { "-- COOLDOWN VIEWER pandemic window (needs Cooldown Manager shown) --" },
        { "cooldown viewer item found", function()
            local it = FirstCooldownViewerItem(); return it ~= nil end,
          "if false, everything below is nil for layout reasons, not secrecy" },
        { "item.PandemicIcon (aura in pandemic)", function()
            local it = FirstCooldownViewerItem(); return it and (it.PandemicIcon ~= nil) end,
          "if PLAIN this is a remaining-TIME threshold the cd probe cannot give" },
        { "item:GetCooldownID()", function()
            local it = FirstCooldownViewerItem(); return it and it:GetCooldownID() end,
          "the plain join key - layout data" },
        { "item:GetSpellID()", function()
            local it = FirstCooldownViewerItem(); return it and it:GetSpellID() end,
          "expect SECRET while an aura is active - do NOT join on this" },

        { "-- UNIT API SIBLINGS --" },
        { "UnitGetTotalAbsorbs('player')", function() return UnitGetTotalAbsorbs("player") end },
        { "UnitGetTotalHealAbsorbs('player')", function() return UnitGetTotalHealAbsorbs("player") end },
        { "UnitStagger('player')", function() return UnitStagger("player") end },
        { "UnitThreatSituation('player','target')", function()
            return UnitThreatSituation("player", "target") end },
        { "UnitIsDeadOrGhost('target')", function() return UnitIsDeadOrGhost("target") end },
    }

    addon:Print("== secrecy census ==  |cff2ecc71plain|r/|cffff6600SECRET|r, branch = `if v then`, cmp = `v > 0`")
    addon:Print(string.format("  in combat: %s   issecretvalue available: %s",
        InCombatLockdown() and "|cff2ecc71YES|r" or "|cffff6600no - rerun IN combat|r",
        issecretvalue and "yes" or "|cffff6600NO|r"))

    for i = 1, #PROBES do
        local p = PROBES[i]
        if not p[2] then
            addon:Print("|cff66ccff" .. p[1] .. "|r")
        else
            local note = p[3] and ("  |cff888888// " .. p[3] .. "|r") or ""
            addon:Print(string.format("  %-38s %s%s", p[1], ClassifyRead(p[2]), note))
        end
    end
    addon:Print("|cff888888Run once OUT of combat and once IN combat - the delta is the finding.|r")
end

--------------------------------------------------------------------------------
-- Performance Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.PerformanceDiagnostics(addon, subCommand)
    local SpellQueue    = LibStub("JustAC-SpellQueue", true)
    local DefEngine     = LibStub("JustAC-DefensiveEngine", true)
    local now = GetTime()

    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.debugMode then
        addon:Print("|cffffff00Enable debug mode first: /jac debug|r")
        return
    end

    local normalizedSub = nil
    if type(subCommand) == "string" then
        normalizedSub = subCommand:match("^%s*(.-)%s*$")
        if normalizedSub == "" then normalizedSub = nil end
        if normalizedSub then normalizedSub = normalizedSub:lower() end
    end

    if normalizedSub and normalizedSub ~= "reset" then
        addon:Print("|cffffff00Unknown subcommand:|r " .. normalizedSub)
        addon:Print("Usage: /jac inspect perf [reset]")
        return
    end

    if normalizedSub == "reset" then
        if SpellQueue and SpellQueue.ResetBuildStats then SpellQueue.ResetBuildStats() end
        if DefEngine and DefEngine.ResetBuildStats then DefEngine.ResetBuildStats() end
        addon:Print("|cff00ff00Build counters reset.|r")
        return
    end

    addon:Print("=== JustAC Queue Build Statistics ===")

    local sqStats = SpellQueue and SpellQueue.GetBuildStats and SpellQueue.GetBuildStats()
    if sqStats then
        local elapsed = sqStats.resetTime > 0 and (now - sqStats.resetTime) or now
        local rate = elapsed > 0 and (sqStats.buildCount / elapsed) or 0
        addon:Print(string.format("Offensive queue builds: |cffadd8e6%d|r (|cffadd8e6%.1f/s|r over %.0fs)",
            sqStats.buildCount, rate, elapsed))
    else
        addon:Print("  SpellQueue stats: |cffff0000not available|r")
    end

    local defStats = DefEngine and DefEngine.GetBuildStats and DefEngine.GetBuildStats()
    if defStats then
        local elapsed = defStats.resetTime > 0 and (now - defStats.resetTime) or now
        local rate = elapsed > 0 and (defStats.buildCount / elapsed) or 0
        addon:Print(string.format("Defensive queue builds: |cffadd8e6%d|r (|cffadd8e6%.1f/s|r over %.0fs)",
            defStats.buildCount, rate, elapsed))
    else
        addon:Print("  DefensiveEngine stats: |cffff0000not available|r")
    end

    -- Threshold-gate layer cost. A MISS is a curve evaluation plus a FontString
    -- round-trip; a HIT is a table lookup. Misses per second is the number that
    -- matters - it should sit near (distinct thresholds asked) x (memo wipes/s),
    -- not scale with how many spells are in the queue.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.GetThresholdGateStats then
        local hits, misses, wipes, curves = BAPI.GetThresholdGateStats()
        local total = hits + misses
        local elapsed = sqStats and sqStats.resetTime > 0 and (now - sqStats.resetTime) or nil
        addon:Print(string.format("Threshold gates: |cffadd8e6%d|r calls (%d miss / %d hit, %.0f%% cached), %d curves cached",
            total, misses, hits, total > 0 and (hits / total * 100) or 0, curves or 0))
        if elapsed and elapsed > 0 then
            addon:Print(string.format("  |cffadd8e6%.1f|r evaluations/s (%d memo windows over %.0fs)",
                misses / elapsed, wipes, elapsed))
        end
    end

    -- Which health band the defensive cluster is ordering by, and WHICH SOURCE
    -- answered. The source is the line that matters if this ever degrades: "gate"
    -- is the direct read, "percent" the unrestricted-context exact read, and
    -- "vignette" the estimate that cannot see the mitigation band at all.
    local DE = LibStub("JustAC-DefensiveEngine", true)
    if DE and DE.GetHealthBandInfo then
        local band, source, bounds = DE.GetHealthBandInfo()
        local BAND_NAMES = { "PANIC", "MAJOR", "MITIGATE", "HEALTHY" }
        addon:Print(string.format("Health band: |cffadd8e6%s|r (band %d, source=%s, boundaries %s)",
            BAND_NAMES[band] or "?", band or -1, tostring(source),
            bounds and table.concat(bounds, "/") .. "%" or "?"))
        if source == "vignette" then
            addon:Print("  |cffffff00vignette fallback: MITIGATE is unreachable here - expected if the gate layer is blocked|r")
        end
    end

    local inCombat = UnitAffectingCombat("player")
    addon:Print("In combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))

    if profile then
        local updateCVar = GetCVar and GetCVar("assistedCombatIconUpdateRate")
        if updateCVar then
            addon:Print("Update CVar (assistedCombatIconUpdateRate): |cffffff00" .. updateCVar .. "s|r")
        end
        local maxIcons = profile.maxIcons or 4
        addon:Print("Max icons (offensive): " .. maxIcons)
        local defEnabled = profile.defensives and profile.defensives.enabled
        addon:Print("Defensives enabled: " .. (defEnabled and "|cff00ff00YES|r" or "NO"))
    end

    addon:Print("|cff888888Use '/jac inspect perf reset' to reset counters.|r")
    addon:Print("======================================")
end

--------------------------------------------------------------------------------
-- Charge API Diagnostics (SPELL_UPDATE_CHARGES / GetSpellCharges secrecy probe)
--------------------------------------------------------------------------------
-- Settles whether a charge-refund correction is buildable in combat:
--   Q1: does SPELL_UPDATE_CHARGES fire in combat, and is its payload readable?
--   Q2: which C_Spell.GetSpellCharges fields are non-secret in combat?
--   Q3: does any readable field cleanly distinguish "recharging" from "charges
--       full"? (recharge inactive ⟺ full would give a definitive refund fix)
-- Arm, enter combat, spend a charge, let it recharge. Auto-disarms after 60s
-- or 12 logged events.
function DebugCommands.ChargeDiagnostics(addon, spellArg)
    if DebugCommands._chargeDiag then
        addon:Print("|cffffff00chargediag already armed (/reload to cancel).|r")
        return
    end
    if not (C_Spell and C_Spell.GetSpellCharges) then
        addon:Print("|cffff0000C_Spell.GetSpellCharges not available|r")
        return
    end

    -- Print-safe conversion; "<secret>" for secret values (shared helper).
    local safe = SafeSecret

    -- Resolve probe spells: named arg, else every charge spell in the spellbook.
    local probeSpells = {}
    local normalizedArg = type(spellArg) == "string" and spellArg:match("^%s*(.-)%s*$") or nil
    if normalizedArg == "" then normalizedArg = nil end
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local lowerArg = normalizedArg and normalizedArg:lower()
        for i = 1, 1000 do
            local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
            if not info then break end
            if info.spellID and info.name then
                if lowerArg then
                    if info.name:lower() == lowerArg then
                        probeSpells[1] = info.spellID
                        break
                    end
                else
                    local ok, ci = pcall(C_Spell.GetSpellCharges, info.spellID)
                    if ok and ci then
                        -- maxCharges is NeverSecret; arithmetic throws if that changes
                        local okMax, isMulti = pcall(function() return ci.maxCharges > 1 end)
                        if okMax and isMulti and #probeSpells < 4 then
                            probeSpells[#probeSpells + 1] = info.spellID
                        end
                    end
                end
            end
        end
    end
    if #probeSpells == 0 then
        if normalizedArg then
            addon:Print("|cffff0000Spell not found in spellbook:|r " .. normalizedArg)
        else
            addon:Print("|cffff6600No charge spells found in spellbook. Name one: /jac inspect chargediag <spell>|r")
        end
        return
    end

    local function dumpCharges(label, spellID)
        local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local name = (info and info.name) or "?"
        local ok, ci = pcall(C_Spell.GetSpellCharges, spellID)
        if not ok or not ci then
            addon:Print(string.format("  [%s] %s (%d): GetSpellCharges -> nil", label, name, spellID))
            return
        end
        local parts = {}
        for k, v in pairs(ci) do
            parts[#parts + 1] = tostring(k) .. "=" .. safe(v)
        end
        table.sort(parts)
        addon:Print(string.format("  [%s] %s (%d): %s", label, name, spellID, table.concat(parts, "  ")))
    end

    local f = CreateFrame("Frame")
    DebugCommands._chargeDiag = f
    local armT = GetTime()
    local fires = 0
    local MAX_FIRES = 12
    local probeSet = {}
    for _, sid in ipairs(probeSpells) do probeSet[sid] = true end

    local function disarm(msg)
        f:UnregisterAllEvents(); f:SetScript("OnEvent", nil); f:SetScript("OnUpdate", nil)
        DebugCommands._chargeDiag = nil
        addon:Print(msg)
    end

    addon:Print("|cff00ff00=== chargediag ARMED (60s) ===|r monitoring " .. #probeSpells .. " charge spell(s):")
    for _, sid in ipairs(probeSpells) do dumpCharges("baseline", sid) end
    addon:Print("  In combat: spend a charge, then let it recharge. Watching SPELL_UPDATE_CHARGES.")

    f:RegisterEvent("SPELL_UPDATE_CHARGES")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "SPELL_UPDATE_COOLDOWN" then
            -- Fallback trigger question only; this event is spammy, so log it
            -- solely when the payload names a probe spell. pcall: payload may be
            -- secret, and indexing with a secret key throws.
            local ok, isProbe = pcall(function() return probeSet[arg1] == true end)
            if not (ok and isProbe) then return end
        end
        fires = fires + 1
        addon:Print(string.format("|cffadd8e6[%+.2fs]|r %s payload=%s inCombat=%s",
            GetTime() - armT, event, safe(arg1), tostring(UnitAffectingCombat("player"))))
        for _, sid in ipairs(probeSpells) do dumpCharges("now", sid) end
        if fires >= MAX_FIRES then
            disarm("|cffffff00chargediag: max events logged - disarmed. Re-arm to continue.|r")
        end
    end)
    f:SetScript("OnUpdate", function()
        if GetTime() - armT > 60 then
            disarm("|cffffff00chargediag: 60s window ended - disarmed.|r")
        end
    end)
end

--------------------------------------------------------------------------------
-- Cast Interruptibility Diagnostics
--------------------------------------------------------------------------------
-- One-shot cast-interruptibility diagnostic. Settles two assumptions the interrupt
-- tracker is built on: (Q1) do INTERRUPTIBLE/NOT_INTERRUPTIBLE events fire at cast
-- START, or only on a mid-cast transition? (Q2) does an addon-created CastingBar
-- resolve the secret notInterruptible? Arm it, then target a caster - ideally one whose
-- cast is non-interruptible from the start (the hard case).
function DebugCommands.CastDiagnostics(addon)
    if DebugCommands._castDiag then
        addon:Print("|cffffff00castdiag already armed - target a caster (or /reload to cancel).|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._castDiag = f
    local armT = GetTime()
    local log, started, startedT, probed = {}, false, 0, false
    local castSpellID, probeLines = nil, {}

    addon:Print("|cff00ff00=== castdiag ARMED ===|r Target a caster. Reads .notInterruptible MID-cast.")
    -- NOTE: do NOT set HideIconWhenNotInterruptible on a cast bar - if that bar has been
    -- tainted by any third-party addon (skinning the target frame, replacing the nameplate),
    -- the resulting IsInterruptable() call throws on the secret barType. The icon-hidden
    -- signal only works on an UNtainted, Blizzard-driven bar. Verified 2026-06-28.

    local function stamp(label) log[#log + 1] = string.format("%+.3fs %s", GetTime() - armT, label) end

    -- Convert any value to a print-safe string (shared helper): "<secret>" for secret
    -- values, secret-tainted strings, or anything tostring can't handle - never lets a
    -- secret reach AceConsole's concat (which errors on secrets).
    local safe = SafeSecret

    -- Capture .notInterruptible DURING the cast. The field is only valid while casting;
    -- reading it after STOP (as the old report did) always came back false. THIS is the
    -- value CastInterruptTracker line 155 uses to suppress the kick.
    local function captureProbes()
        if probed then return end
        probed = true
        local function probeBar(label, bar)
            if not bar then probeLines[#probeLines + 1] = label .. ": absent"; return end
            local niOk, ni = pcall(function() return bar.notInterruptible and true or false end)
            probeLines[#probeLines + 1] = string.format("%s .notInterruptible (MID-cast): ok=%s value=%s  <- true=can't interrupt",
                label, tostring(niOk), niOk and safe(ni) or "-")
        end
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
        probeBar("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
        probeBar("nameplate.castBar", NameplateCastBar(np))
        -- Read the icon-hidden check on the BLIZZARD bars DIRECTLY, even if a third-party addon
        -- hides them and shows its own. If a hidden Blizzard bar still reports
        -- notInterruptible=true on a shielded cast, it is still Blizzard-DRIVEN and readable.
        -- hasIcon/flag must be present for the check to work.
        local function probeIconHidden(label, bar)
            if not bar then probeLines[#probeLines + 1] = "  " .. label .. ": absent"; return end
            local hasIcon = bar.Icon ~= nil
            local flag = bar.HideIconWhenNotInterruptible
            local sOk, shown = pcall(function() return bar.Icon and bar.Icon:IsShown() and true or false end)
            local cOk, chk = pcall(function() return (bar.Icon and bar.HideIconWhenNotInterruptible and not bar.Icon:IsShown()) and true or false end)
            probeLines[#probeLines + 1] = string.format("  %s icon-hidden: hasIcon=%s flag=%s iconShown=%s => notInterruptible=%s",
                label, tostring(hasIcon), tostring(flag), sOk and safe(shown) or "?", cOk and safe(chk) or "?")
        end
        probeIconHidden("TargetFrame.spellbar (Blizzard)", TargetFrame and TargetFrame.spellbar)
        probeIconHidden("nameplate UnitFrame.castBar (Blizzard,capU)", NameplateCastBar(np))

        -- ZERO-GATE ON THE SHIELD'S ALPHA. The shield route was written off because
        -- BorderShield:IsShown() is a secret BOOLEAN, and a secret boolean cannot be
        -- branched on. But GetAlpha() returns a secret NUMBER - and a secret number
        -- is exactly what IsSecretZero eats. If this reads, the sealed
        -- notInterruptible flag has a back door that needs no untainted frame:
        --     alpha zero   -> shield not drawn -> cast IS interruptible
        --     alpha non-0  -> shield drawn     -> cast is NOT interruptible
        -- Two reasons this stays a PROBE until measured in a fight:
        --   * alpha and shown are different things. A shield hidden with Hide() can
        --     still report alpha 1, which reads as "uninterruptible" on a kickable
        --     cast - and that is the direction that costs an interrupt.
        --   * the existing cascade is fail-open by design; a half-trusted new signal
        --     could turn a safe "no suggestion" into a confidently wrong one.
        -- Cross-check every line against the icon-hidden verdict directly above: on a
        -- Blizzard-driven bar they must agree, and any row where they disagree is the
        -- interesting one.
        local BAPI = LibStub("JustAC-BlizzardAPI", true)
        local function probeShieldAlpha(label, bar)
            if not bar then return end
            for _, key in ipairs({ "BorderShield", "Shield" }) do
                local sh = bar[key]
                if sh and sh.GetAlpha then
                    local aOk, alpha = pcall(sh.GetAlpha, sh)
                    local isSec = aOk and BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(alpha) or false
                    local zero = aOk and BAPI and BAPI.IsSecretZero and BAPI.IsSecretZero(alpha)
                    local shOk, shown = pcall(function() return sh:IsShown() and true or false end)
                    probeLines[#probeLines + 1] = string.format(
                        "  %s .%s: read=%s secret=%s shown=%s  zero-gate => %s",
                        label, key, tostring(aOk), tostring(isSec),
                        shOk and safe(shown) or "?",
                        (zero == true and "|cff2ecc71alpha 0 = INTERRUPTIBLE|r")
                            or (zero == false and "|cffff6600alpha>0 = NOT interruptible|r")
                            or "|cff888888no answer|r")
                end
            end
        end
        probeShieldAlpha("TargetFrame.spellbar (Blizzard)", TargetFrame and TargetFrame.spellbar)
        probeShieldAlpha("nameplate UnitFrame.castBar (Blizzard,capU)", NameplateCastBar(np))
        -- The replaced/reskinned bar the tracker would actually have found. This is the
        -- row that matters for the addon-interaction complaint: if the zero-gate answers
        -- HERE, layer 2 stops degrading when a third-party bar is in play.
        local Tracker = LibStub("JustAC-CastInterruptTracker", true)
        if Tracker and Tracker.DebugFindCastBar and np then
            local found, src = Tracker.DebugFindCastBar(np)
            if found then
                probeShieldAlpha("discovered bar (" .. tostring(src) .. ")", found)
            else
                probeLines[#probeLines + 1] = "  discovered bar: none found on this nameplate"
            end
        end
        -- LIVENESS of the (possibly hidden) Blizzard bar: a replacing addon that merely
        -- Hide()s it leaves its UNTAINTED event handlers running - the icon-hidden read
        -- above then stays trustworthy even invisible. An addon that unregistered its
        -- events leaves the state frozen-stale (must never be trusted: stale iconShown
        -- would read as "interruptible" = wrongly-shown kick). Verdict rules:
        --   eventsRegistered + castingFlag tracking THIS cast = LIVE (signal usable)
        --   eventsRegistered=false = EVENT-DEAD (unusable)
        local function probeLiveness(label, bar)
            if not bar then return end
            local regOk, regged = pcall(function() return bar:IsEventRegistered("UNIT_SPELLCAST_START") and true or false end)
            local cOk, castingF = pcall(function() return (bar.casting or bar.channeling) and true or false end)
            local shOk, shownF  = pcall(function() return bar:IsShown() and true or false end)
            local vOk, visible  = pcall(function() return bar:IsVisible() and true or false end)
            local verdict
            if regOk and regged and cOk and castingF then
                verdict = "|cff00ff00LIVE - hidden-bar icon signal trustworthy|r"
            elseif regOk and not regged then
                verdict = "|cffff6600EVENT-DEAD (events unregistered) - unusable|r"
            elseif cOk and not castingF then
                verdict = "|cffff6600STALE (casting flag not tracking this cast) - unusable|r"
            else
                verdict = "|cffff6600INCONCLUSIVE (reads sealed)|r"
            end
            probeLines[#probeLines + 1] = string.format(
                "  %s liveness: eventsReg=%s castingFlag=%s shown=%s visible=%s",
                label, regOk and safe(regged) or "?", cOk and safe(castingF) or "?",
                shOk and safe(shownF) or "?", vOk and safe(visible) or "?")
            probeLines[#probeLines + 1] = "    => " .. verdict
        end
        probeLiveness("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
        probeLiveness("nameplate UnitFrame.castBar", NameplateCastBar(np))
        -- Focus-frame bar: a second untainted Blizzard bar if the player has focus=target
        if FocusFrame and FocusFrame.spellbar then
            probeIconHidden("FocusFrame.spellbar (Blizzard)", FocusFrame.spellbar)
            probeLiveness("FocusFrame.spellbar", FocusFrame.spellbar)
        end
        -- BYPASS PROBE: does a replacing cast-bar addon expose its OWN interruptibility on its
        -- bar? Such bars commonly live at nameplate.unitFrame.castBar (lowercase). If a field
        -- reads a clean boolean matching the actual cast (and its shield is visually correct),
        -- we could read its answer instead of Blizzard's. Compare to what its bar shows.
        local puf = np and np.unitFrame
        local pcb = puf and ((puf.CastBarsContainer and puf.CastBarsContainer.castBar) or puf.castBar)
        if pcb then
            local function rd(field)
                local ok, v = pcall(function() return pcb[field] end)
                return ok and safe(v) or "ERR"
            end
            probeLines[#probeLines + 1] = string.format("3rd-party castBar fields: canInterrupt=%s notInterruptible=%s IsInterruptible=%s",
                rd("canInterrupt"), rd("notInterruptible"), rd("IsInterruptible"))
            local sOk, sh = pcall(function() return pcb.Icon and pcb.Icon:IsShown() and true or false end)
            probeLines[#probeLines + 1] = "3rd-party castBar: hasIcon=" .. tostring(pcb.Icon ~= nil) ..
                " iconShown=" .. (sOk and safe(sh) or "?") .. " HideIconFlag=" .. tostring(pcb.HideIconWhenNotInterruptible)
        else
            probeLines[#probeLines + 1] = "3rd-party castBar: not found (nameplate.unitFrame.castBar absent)"
        end
        -- The AUTHORITATIVE verdict: what the addon's own IsTargetCastInterruptible returns.
        local CIT = LibStub and LibStub("JustAC-CastInterruptTracker", true)
        if CIT and CIT.DebugInterruptState then
            local okc, isCasting, interruptible, src = pcall(CIT.DebugInterruptState)
            probeLines[#probeLines + 1] = string.format("IsTargetCastInterruptible(): isCasting=%s interruptible=%s  via=%s",
                okc and safe(isCasting) or "ERR", okc and safe(interruptible) or "-", okc and safe(src) or "-")
        end
        local BlizzardAPI = LibStub and LibStub("JustAC-BlizzardAPI", true)
        local worthy = BlizzardAPI and BlizzardAPI.IsTargetInterruptWorthy and BlizzardAPI.IsTargetInterruptWorthy()
        probeLines[#probeLines + 1] = "IsTargetInterruptWorthy(): " .. tostring(worthy)
        local ic = addon.interruptIcon
        local sOk, shown = pcall(function() return ic and ic:IsShown() and true or false end)
        local aOk, alpha = pcall(function() return ic and ic:GetAlpha() end)
        probeLines[#probeLines + 1] = "JustAC Kick icon: shown=" .. (sOk and tostring(shown) or "?") ..
            " alpha=" .. (aOk and safe(alpha) or "?") .. "  (alpha 0 on a non-kickable cast = SetAlphaFromBoolean works)"
        addon:Print(string.format("|cff888888[castdiag captured mid-cast at +%.2fs; full result on cast end]|r", GetTime() - startedT))
    end

    local function report()
        if DebugCommands._castDiag ~= f then return end
        -- Clean up FIRST so any print error cannot re-fire every frame.
        f:UnregisterAllEvents(); f:SetScript("OnEvent", nil); f:SetScript("OnUpdate", nil)
        DebugCommands._castDiag = nil
        local pok, perr = pcall(function()
            addon:Print("|cff00ff00=== castdiag RESULT ===|r")
            for _, line in ipairs(log) do addon:Print("  " .. line) end
            local sawInterEvt = false
            for _, line in ipairs(log) do if line:find("INTERRUPTIBLE") then sawInterEvt = true break end end
            addon:Print("  Q1 interruptible event this cast: " ..
                (sawInterEvt and "|cff00ff00YES - events may suffice|r" or "|cffff6600NO - initial state needs secret resolution|r"))
            if #probeLines > 0 then
                addon:Print("  |cffffd100--- MID-CAST reads (what the addon actually uses) ---|r")
                for _, l in ipairs(probeLines) do addon:Print("  " .. l) end
            else
                addon:Print("  |cffff6600(no mid-cast capture - cast ended in <0.3s)|r")
            end
            -- Q2: the cast's spellID from the event - if readable, a spell-keyed lookup is viable.
            local idStr = safe(castSpellID)
            addon:Print("  Q2 event spellID: " .. idStr ..
                (idStr == "<secret>" and " |cffff6600(secret -> spell-DB approach dead)|r"
                 or " |cff00ff00(readable -> spell-DB approach viable)|r"))
            -- Q3: BorderShield:IsShown() - Blizzard's display derivation. shown=true would
            -- mean non-interruptible if it reads as a concrete (non-secret) boolean.
            addon:Print("  Q3 cast-bar BorderShield IsShown (true expected on a shielded cast):")
            local function probeShield(label, bar)
                if not bar then addon:Print("    " .. label .. ": |cff888888absent|r"); return end
                -- (post-STOP read - kept only for the BorderShield secret check; the meaningful
                -- .notInterruptible value is the MID-CAST capture printed above.)
                local shield = bar.BorderShield or bar.Shield
                if shield and shield.IsShown then
                    local ok, shown = pcall(shield.IsShown, shield)
                    addon:Print(string.format("    %s BorderShield IsShown (post-cast): ok=%s shown=%s", label, tostring(ok), ok and safe(shown) or "-"))
                end
            end
            probeShield("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
            local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
            probeShield("nameplate.UnitFrame.castBar", NameplateCastBar(np))
            -- Q4: cast-bar color. If Blizzard sets it by branching on the secret (a plain
            -- constant result), GetStatusBarColor() is NON-secret -> we can read interruptibility
            -- directly (yellow ~ interruptible, grey ~ not). If it reads <secret>, it's piped.
            -- base StatusBarColor was white; the grey/yellow lives on the fill texture's
            -- ATLAS or vertex color. If either is a readable constant that differs by
            -- interruptibility, that's the full fix.
            addon:Print("  Q4 cast-bar fill appearance (readable + differs by cast = full fix):")
            local function probeColor(label, bar)
                if not bar then addon:Print("    " .. label .. ": |cff888888absent|r"); return end
                local _, r, g, b = pcall(bar.GetStatusBarColor, bar)
                local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
                local atlas, vr, vg, vb = "n/a", nil, nil, nil
                if tex then
                    local aok, a = pcall(tex.GetAtlas, tex); if aok then atlas = a end
                    local vok, x, y, z = pcall(tex.GetVertexColor, tex); if vok then vr, vg, vb = x, y, z end
                end
                addon:Print(string.format("    %s: barColor=%s/%s/%s vertex=%s/%s/%s",
                    label, safe(r), safe(g), safe(b), safe(vr), safe(vg), safe(vb)))
                addon:Print("      atlas=" .. safe(atlas))
            end
            probeColor("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
            probeColor("nameplate.UnitFrame.castBar", NameplateCastBar(np))
            -- Q5: can we PASS the secret shield state into display sinks without reading it?
            -- SetDesaturated greys the icon (non-occluding - keybind stays visible); SetShown
            -- drives a non-covering border/badge. ok = that cue is viable.
            -- Which secret-accepting sinks can drive a cue? ok = that visual is usable.
            -- VertexColor (color tint) is the most obvious; Alpha (fade) next; Desaturated
            -- (grey) is the subtle baseline; Shown is known-rejected. The secret bool is
            -- forwarded to each, never read.
            addon:Print("  Q5 secret-passthrough sinks (ok = that cue is usable):")
            local function probePass(label, bar)
                local shield = bar and (bar.BorderShield or bar.Shield)
                if not (shield and shield.IsShown) then addon:Print("    " .. label .. ": |cff888888no shield|r"); return end
                if not DebugCommands._probeTex then
                    DebugCommands._probeTex = UIParent:CreateTexture(nil, "OVERLAY"); DebugCommands._probeTex:Hide()
                end
                local tex = DebugCommands._probeTex
                local s = shield:IsShown()  -- secret bool; forwarded to sinks, never read
                local function t(fn) return pcall(fn) and "|cff00ff00ok|r" or "|cffff6600REJECT|r" end
                addon:Print(string.format("    %s: VertexColor=%s Alpha=%s Desaturated=%s Shown=%s", label,
                    t(function() tex:SetVertexColor(1, s, s) end),
                    t(function() tex:SetAlpha(s) end),
                    t(function() tex:SetDesaturated(s) end),
                    t(function() tex:SetShown(s) end)))
            end
            probePass("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
        end)
        if not pok then addon:Print("|cffff0000castdiag error (handled):|r " .. safe(perr)) end
    end

    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    -- Interruptible events registered BROADLY (no unit filter): the game may fire them with
    -- a "nameplateN" token instead of "target", which a target-filtered registration misses.
    -- We match back to the current target via SafeUnitIsUnit - UnitIsUnit is NOT non-secret.
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    f:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")

    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Log only if it pertains to the current target, whatever token the game used.
            -- These events are registered WITHOUT a unit filter, so `unit` can be a COMPOUND
            -- token (eg. "boss1target") - and the docs say compound comparisons are ALWAYS
            -- secret, on any map, not just restricted ones. Unreadable defaults to false:
            -- this is a diagnostic, so skipping an entry beats throwing mid-probe.
            if unit and BlizzardAPI and BlizzardAPI.SafeUnitIsUnit
                and BlizzardAPI.SafeUnitIsUnit(unit, "target", false) then
                stamp(event:gsub("UNIT_SPELLCAST_", "") .. " (target via " .. tostring(unit) .. ")")
            end
            return
        end
        stamp((event:gsub("UNIT_SPELLCAST_", "")))
        if (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") and not started then
            started = true
            startedT = GetTime()
            castSpellID = spellID  -- raw; safe() converts at print time (may be secret)
        elseif (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP") and started then
            report()
        end
    end)

    f:SetScript("OnUpdate", function()
        local now = GetTime()
        if not started then
            if now - armT > 30 then
                addon:Print("|cffff6600castdiag timed out (no cast in 30s). Disarmed.|r")
                f:UnregisterAllEvents(); f:SetScript("OnUpdate", nil); f:SetScript("OnEvent", nil)
                DebugCommands._castDiag = nil
            end
            return
        end
        if not probed and (now - startedT) >= 0.3 then captureProbes() end  -- read .notInterruptible MID-cast
        if (now - startedT) > 8 then report() end                          -- long/channel cast with no STOP
    end)
end

--------------------------------------------------------------------------------
-- Assumption Validation Suite
-- /jac inspect validate       - one-shot sweep of every load-bearing API read
-- /jac inspect validate arm   - also re-captures on combat enter/exit and prints
--                               only what changed class (readable/secret/sealed)
-- Every probe is classified: ok:<value> | secret | SEALED (threw) | nil | absent.
-- Nothing is written or branched on a secret; reads are pcall-guarded.
--------------------------------------------------------------------------------

-- C_Secrets function count at last full audit (12.0.7, 2026-07-05). If the live
-- count differs, the secrecy surface changed and every assumption needs re-audit.
-- Re-checked against the 12.1.0 generated docs before that patch shipped: the
-- C_Secrets surface is unchanged, so this guard should stay quiet across it.
local SECRETS_SURFACE_COUNT = 27

--- @return string class the diff key - what a CHANGE between snapshots means
--- @return string display the coloured cell
local function ValidateClassify(fn)
    local status, text, v = ProbeRead(fn, 24)
    local cell = ProbeColour(status) .. (status == "err" and "SEALED" or text) .. "|r"
    if status == "err" then return "SEALED", cell end
    if status == "nil" then return "nil", cell end
    if status == "secret" then return "secret", cell end
    -- Booleans are state, not noise: track the VALUE so a predicate flipping
    -- false->true in combat shows in the diff. Numbers (cooldown clocks etc.)
    -- churn constantly - class-only for those.
    if type(v) == "boolean" then return "ok:" .. text, cell end
    return "ok", cell
end

-- First rotation spell if plainly readable, else the GCD reference spell.
local function ValidateProbeSpell()
    local ok, sid = pcall(function()
        return C_AssistedCombat.GetRotationSpells()[1] + 0
    end)
    if ok and type(sid) == "number" then return sid end
    return 61304
end

-- First occupied action slot with a plainly readable HasAction.
local function ValidateProbeSlot()
    for i = 1, 120 do
        local ok, has = pcall(function() return HasAction(i) == true end)
        if ok and has then return i end
    end
    return 1
end

local function BuildValidateProbes()
    local probes = {}
    local function add(key, fn) probes[#probes + 1] = { key, fn } end
    local sid = ValidateProbeSpell()
    local slot = ValidateProbeSlot()
    local CS = C_Secrets

    -- Secrecy predicates (full documented surface, correct args). Plain booleans
    -- by contract; any class other than ok/absent here is itself a finding.
    if type(CS) == "table" then
        add("secrets.HasSecretRestrictions", function() return CS.HasSecretRestrictions() end)
        add("secrets.ShouldAurasBeSecret", function() return CS.ShouldAurasBeSecret() end)
        add("secrets.ShouldCooldownsBeSecret", function() return CS.ShouldCooldownsBeSecret() end)
        add("secrets.ShouldUnitStatsBeSecret", function() return CS.ShouldUnitStatsBeSecret() end)
        add("secrets.ShouldUnitHealthMaxBeSecret", function() return CS.ShouldUnitHealthMaxBeSecret("player") end)
        add("secrets.ShouldUnitPowerBeSecret", function() return CS.ShouldUnitPowerBeSecret("player") end)
        add("secrets.ShouldUnitIdentityBeSecret", function() return CS.ShouldUnitIdentityBeSecret("target") end)
        add("secrets.ShouldUnitSpellCastingBeSecret", function() return CS.ShouldUnitSpellCastingBeSecret("target") end)
        add("secrets.ShouldUnitComparisonBeSecret", function() return CS.ShouldUnitComparisonBeSecret("player", "target") end)
        add("secrets.ShouldUnitThreatStateBeSecret", function() return CS.ShouldUnitThreatStateBeSecret("player", "target") end)
        add("secrets.ShouldSpellCooldownBeSecret", function() return CS.ShouldSpellCooldownBeSecret(sid) end)
        add("secrets.ShouldSpellAuraBeSecret", function() return CS.ShouldSpellAuraBeSecret(sid) end)
        add("secrets.ShouldActionCooldownBeSecret", function() return CS.ShouldActionCooldownBeSecret(slot) end)
        add("secrets.CanCompareUnitTokens", function() return CS.CanCompareUnitTokens("player", "target") end)
        -- SecrecyLevel: 0=NeverSecret 1=AlwaysSecret 2=ContextuallySecret
        add("secrets.SpellCooldownSecrecy", function() return CS.GetSpellCooldownSecrecy(sid) end)
        add("secrets.SpellAuraSecrecy", function() return CS.GetSpellAuraSecrecy(sid) end)
        add("secrets.SpellCastSecrecy", function() return CS.GetSpellCastSecrecy(sid) end)
        add("secrets.PowerTypeSecrecy", function() return CS.GetPowerTypeSecrecy(0) end)
    else
        add("secrets.C_Secrets", function() return nil end)
    end

    add("health.UnitHealth", function() return UnitHealth("player") end)
    add("health.UnitHealthMax", function() return UnitHealthMax("player") end)
    add("health.UnitHealthMissing", function() return UnitHealthMissing and UnitHealthMissing("player") end)
    add("health.UnitHealthPercent", function() return UnitHealthPercent and UnitHealthPercent("player") end)
    add("health.UnitPower", function() return UnitPower("player") end)
    add("health.UnitPowerMax", function() return UnitPowerMax("player") end)
    add("health.absorbs", function() return UnitGetTotalAbsorbs("player") end)
    add("health.targetHealth", function() return UnitHealth("target") end)

    add("aura.helpfulCount", function()
        local n = 0
        for i = 1, 40 do
            if not C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL") then break end
            n = n + 1
        end
        return n
    end)
    for _, field in ipairs({ "name", "spellId", "duration", "expirationTime", "applications" }) do
        add("aura.player1." .. field, function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
            return a and a[field]
        end)
    end
    add("aura.durationObjSecret", function()
        local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
        if not a then return nil end
        local d = C_UnitAuras.GetAuraDuration("player", a.auraInstanceID)
        return d and d:HasSecretValues()  -- ReturnsNeverSecret by contract
    end)
    -- Per-aura secrecy: docs say per-spell flags override the global rule
    -- (ShouldAurasBeSecret=true while an exempt buff stays readable).
    add("aura.player1.shouldBeSecret", function()
        return CS and CS.ShouldUnitAuraIndexBeSecret("player", 1, "HELPFUL")
    end)
    add("aura.player1.auraSecrecy", function()
        local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
        return a and CS and CS.GetSpellAuraSecrecy(a.spellId)  -- spellId may be secret; accepted per docs
    end)
    add("aura.target1.spellId", function()
        local a = C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL")
        return a and a.spellId
    end)
    -- Live fronts for the static SelfAuras/AuraStacks tables (SpellDB accessors).
    -- maxStacks probes a KNOWN stacking aura (Ironfur): the API throws (SEALED)
    -- for spells without a stacking record - verified 2026-07-05 with Cat Form.
    add("aura.isSelfBuffAPI", function() return C_Spell.IsSelfBuff(sid) end)
    -- Lives in C_Spell, NOT C_UnitAuras. Probing the wrong namespace called a nil field, and
    -- the resulting error was recorded as "the API throws" - a false negative. Verify before
    -- concluding anything about this function's availability.
    add("aura.maxStacksIronfur", function() return C_Spell.GetSpellMaxCumulativeAuraApplications(192081) end)

    add("cd.probeSpell", function() return sid end)
    add("cd.start", function() return C_Spell.GetSpellCooldown(sid).startTime end)
    add("cd.duration", function() return C_Spell.GetSpellCooldown(sid).duration end)
    add("cd.isEnabled", function() return C_Spell.GetSpellCooldown(sid).isEnabled end)
    add("cd.chargesCurrent", function()
        local c = C_Spell.GetSpellCharges(sid)
        return c and c.currentCharges
    end)
    add("cd.chargesMax", function()
        local c = C_Spell.GetSpellCharges(sid)
        return c and c.maxCharges  -- NeverSecret by contract
    end)
    add("cd.castCount", function() return C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(sid) end)
    add("cd.durationObjSecret", function()
        local d = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
        return d and d:HasSecretValues()
    end)
    add("cd.usable", function() return C_Spell.IsSpellUsable(sid) end)
    add("cd.inRange", function() return C_Spell.IsSpellInRange(sid, "target") end)
    add("cd.overrideSpell", function() return C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(sid) end)

    add("ac.next", function() return C_AssistedCombat.GetNextCastSpell() end)
    add("ac.rot1", function() return C_AssistedCombat.GetRotationSpells()[1] end)
    add("ac.rotCount", function() return #C_AssistedCombat.GetRotationSpells() end)
    add("ac.available", function() return (C_AssistedCombat.IsAvailable()) end)
    add("proc.overlayed", function() return C_SpellActivationOverlay.IsSpellOverlayed(sid) end)

    add("action.probeSlot", function() return slot end)
    add("action.cdStart", function() return (GetActionCooldown(slot)) end)
    add("action.usable", function() return (IsUsableAction(slot)) end)
    add("action.inRange", function() return IsActionInRange(slot) end)
    add("action.isInterrupt", function() return C_ActionBar.IsInterruptAction and C_ActionBar.IsInterruptAction(slot) end)
    add("action.durationObjSecret", function()
        local d = C_ActionBar.GetActionCooldownDuration and C_ActionBar.GetActionCooldownDuration(slot)
        return d and d:HasSecretValues()
    end)

    -- Loss of control: the defensive queue skips its castability gate while CC'd
    -- (a stun reports the whole book uncastable). That rests on the active count
    -- being plainly readable - if this ever classes secret, the queue silently
    -- reverts to hiding every defensive for the CC's duration.
    add("loc.activeCount", function()
        return C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount()
    end)
    add("loc.gate", function()
        local B = LibStub("JustAC-BlizzardAPI", true)
        return B and B.IsLossOfControlActive and B.IsLossOfControlActive()
    end)
    -- A bar-swapping debuff reports NO loss-of-control entry, so loc.gate above stays false
    -- while every ability is uncastable. This is the read that catches it, and the lockout
    -- gate is what keeps the queue from being filtered away in that state.
    -- Important-cast channels. C_Spell.IsSpellImportant is the engine's own "lethal if not
    -- interrupted" flag and is AllowedWhenTainted, but an NPC's cast spell id is expected to
    -- be secret in combat, which would make the verdict secret too - display-only. These
    -- three reads decide whether a BRANCH is available (a suggestion) or only a cue:
    --   cast.importantVerdict - the verdict itself, from the target's cast id
    --   castbar.importantAnim - Blizzard's flash animation: SetPlaying(secret) is a DIFFERENT
    --                           laundering channel from SetShown, and the shape that worked
    --                           for the scratch-Cooldown readiness probe. Best hope.
    --   castbar.importantShown - predicted SECRET: Blizzard uses SetShown(expr), which the
    --                           resource sweep established does not launder.
    -- Both castbar reads need the target's own nameplate up AND Blizzard's
    -- highlightImportantCasts setting on; castbar.highlight reports whether it is.
    add("cast.importantVerdict", function()
        local id = select(9, UnitCastingInfo("target"))
        return C_Spell.IsSpellImportant(id)
    end)
    local function TargetCastBar()
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit("target")
        return NameplateCastBar(np)
    end
    add("castbar.spellID", function() return TargetCastBar().spellID end)
    add("castbar.highlight", function() return TargetCastBar().highlightImportantCasts end)
    add("castbar.importantAnim", function()
        return TargetCastBar().ImportantCastFlashAnim:IsPlaying()
    end)
    add("castbar.importantShown", function()
        return TargetCastBar().ImportantCastIndicator:IsShown()
    end)
    add("bar.override", function() return HasOverrideActionBar() end)
    add("bar.vehicle", function() return HasVehicleActionBar() end)
    add("lockout.gate", function()
        local B = LibStub("JustAC-BlizzardAPI", true)
        return B and B.IsPlayerAbilityLockout and B.IsPlayerAbilityLockout()
    end)

    add("cast.playerName", function() return (UnitCastingInfo("player")) end)
    add("cast.targetName", function() return (UnitCastingInfo("target")) end)
    add("cast.targetNotInterruptible", function() return select(8, UnitCastingInfo("target")) end)

    add("viewer.available", function() return (C_CooldownViewer.IsCooldownViewerAvailable()) end)
    add("viewer.essentialCount", function()
        return #C_CooldownViewer.GetCooldownViewerCategorySet(Enum.CooldownViewerCategory.Essential, false)
    end)

    -- What the addon's own gates believe - should agree with the raw reads above.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.GetFeatureAvailability then
        add("gate.health", function() return BAPI.GetFeatureAvailability().healthAccess end)
        add("gate.aura", function() return BAPI.GetFeatureAvailability().auraAccess end)
        add("gate.proc", function() return BAPI.GetFeatureAvailability().procAccess end)
    end

    -- TECHNIQUE SELF-TESTS. Everything above measures what the client will TELL us;
    -- these measure whether the mechanisms the addon is BUILT ON still work. That is
    -- a different failure and a much quieter one: when a threshold curve or the
    -- zero-gate stops answering, nothing errors - every caller fails open, the
    -- addon silently reverts to its estimates, and the only symptom is that cues
    -- feel slightly wrong. Each check below has a KNOWN answer, so "ok" means the
    -- mechanism actually produced the right result, not merely that the API exists.
    add("tech.curveAPI", function()
        return (C_CurveUtil and C_CurveUtil.CreateCurve
            and Enum.LuaCurveType.Linear ~= nil) and true or false
    end)
    add("tech.curveShape", function()
        -- A 50% threshold curve, evaluated with PLAIN inputs either side of it. The
        -- domain is the 0-1 fraction; below the threshold reads high, at/above reads
        -- zero. Backwards or flat here means every threshold gate in the addon is
        -- silently inverted or dead.
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Linear)
        c:AddPoint(0, 100); c:AddPoint(0.499, 100); c:AddPoint(0.501, 0); c:AddPoint(1, 0)
        return (c:Evaluate(0.4) >= 1 and c:Evaluate(0.6) < 1) and "ok" or "BROKEN"
    end)
    add("tech.zeroGate", function()
        -- The zero-gate, end to end on PLAIN numbers: truncate-when-zero collapses 0
        -- to nil and leaves a non-zero alone, and a FontString hands the result back
        -- readable. Both halves must hold - this is what turns a secret into a
        -- branchable boolean everywhere in the addon.
        if not (C_StringUtil and C_StringUtil.TruncateWhenZero) then return "no API" end
        local fs = DebugCommands._validateFS
        if not fs then
            fs = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
            fs:Hide(); DebugCommands._validateFS = fs
        end
        fs:SetText(C_StringUtil.TruncateWhenZero(0) or "")
        local emptyReadsNil = fs:GetText() == nil
        fs:SetText(C_StringUtil.TruncateWhenZero(42) or "")
        local valueReadsBack = fs:GetText() ~= nil
        return (emptyReadsNil and valueReadsBack) and "ok" or "BROKEN"
    end)
    add("tech.zeroGatePlain", function()
        -- The addon's own wrapper on its PLAIN fast path (0 is zero). Only proves the
        -- module loaded and the fast path is sane; the secret-widget path needs a live
        -- secret, which durcurve exercises. Disagreeing with the raw check above
        -- localises a break to our code rather than the client.
        return BAPI and BAPI.IsSecretZero and BAPI.IsSecretZero(0)
    end)
    add("tech.thresholdGate", function()
        return BAPI and BAPI.IsThresholdGateAvailable and BAPI.IsThresholdGateAvailable()
    end)
    add("tech.durationEval", function()
        -- The three Evaluate* entry points the duration thresholds ride on. Method
        -- presence only: a real verdict needs a live aura, which durcurve does.
        local d = C_Spell.GetSpellCooldownDuration(sid)
        if not d then return "no durObj" end
        return (d.EvaluateRemainingPercent and d.EvaluateRemainingDuration
            and d.EvaluateTotalDuration) and "ok" or "MISSING"
    end)
    add("tech.stackCount", function()
        return (C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount) ~= nil
    end)
    add("tech.groupBuffItems", function()
        return (C_CooldownViewer and C_CooldownViewer.GetGroupBuffItems) ~= nil
    end)

    return probes
end

local function PrintValidateEnv(addon)
    -- SafeSecret, not tostring: tostring propagates secrecy silently, so the old body
    -- could print a secret as if it were a plain value.
    local function vs(fn)
        local ok, v = pcall(fn)
        return ok and SafeSecret(v) or "SEALED"
    end
    addon:Print("  where: zone=" .. vs(function() return (GetInstanceInfo()) end)
        .. " type=" .. vs(function() return select(2, GetInstanceInfo()) end)
        .. " diff=" .. vs(function() return select(4, GetInstanceInfo()) end)
        .. " map=" .. vs(function() return C_Map.GetBestMapForUnit("player") end)
        .. " instID=" .. vs(function() return select(8, GetInstanceInfo()) end))
    addon:Print("  state: combat=" .. tostring(UnitAffectingCombat("player"))
        .. " resting=" .. vs(IsResting)
        .. " group=" .. (IsInRaid() and "raid" or IsInGroup() and "party" or "solo")
        .. " spec=" .. vs(function() return select(2, GetSpecializationInfo(GetSpecialization())) end)
        .. " form=" .. vs(GetShapeshiftFormID)
        .. " level=" .. vs(function() return UnitLevel("player") end))
    addon:Print("  pvp: warMode=" .. vs(C_PvP.IsWarModeActive)
        .. " zonePvP=" .. vs(function() return (C_PvP.GetZonePVPInfo()) end)
        .. "  client: " .. vs(function() local v, b = GetBuildInfo(); return v .. "." .. b end))
end

-- Runs all probes; returns snapshot {key -> class} plus ordered key list.
local function RunValidateSnapshot(addon, printAll)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.RefreshFeatureAvailability then pcall(BAPI.RefreshFeatureAvailability) end
    local probes = BuildValidateProbes()
    local snap, order = {}, {}
    local curGroup, parts
    local function flush()
        if curGroup and parts and #parts > 0 then
            addon:Print("  " .. curGroup .. ": " .. table.concat(parts, " "))
        end
        parts = {}
    end
    for _, p in ipairs(probes) do
        local key, fn = p[1], p[2]
        local class, disp = ValidateClassify(fn)
        snap[key] = class
        order[#order + 1] = key
        if printAll then
            local group, rest = key:match("^([^.]+)%.(.+)$")
            if group ~= curGroup then
                flush()
                curGroup = group
            end
            parts[#parts + 1] = rest .. "=" .. disp
            if #parts >= 5 then flush() end
        end
    end
    if printAll then flush() end
    return snap, order
end

local function DiffValidate(addon, base, now, order)
    local changed = 0
    for _, key in ipairs(order) do
        if base[key] ~= now[key] then
            changed = changed + 1
            addon:Print(string.format("  |cffffff00%s|r: %s -> %s", key,
                tostring(base[key]), tostring(now[key])))
        end
    end
    addon:Print(string.format("  %d probe class change(s); %d held.", changed, #order - changed))
end

function DebugCommands.ValidateAssumptions(addon, arg)
    local armed = arg == "arm"
    if armed and DebugCommands._validate then
        addon:Print("|cffffff00validate already armed (/reload to cancel).|r")
        return
    end

    addon:Print("===== assumption validation (" .. (armed and "armed" or "one-shot") .. ") =====")
    PrintValidateEnv(addon)

    -- Secrecy surface drift check: the one signal that all cached verdicts are stale.
    local fnCount = 0
    if type(C_Secrets) == "table" then
        for _, v in pairs(C_Secrets) do
            if type(v) == "function" then fnCount = fnCount + 1 end
        end
    end
    if fnCount ~= SECRETS_SURFACE_COUNT then
        addon:Print(string.format(
            "|cffff0000C_Secrets surface changed: %d functions (audited at %d) - re-audit all secrecy assumptions!|r",
            fnCount, SECRETS_SURFACE_COUNT))
    end

    -- Render-sink availability (existence only; these consume secrets, never return them).
    local sink = DebugCommands._validateSinkProbe
    if not sink then
        sink = { tex = UIParent:CreateTexture(), cd = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate") }
        sink.tex:Hide(); sink.cd:Hide()
        DebugCommands._validateSinkProbe = sink
    end
    local function has(obj, m) return type(obj) == "table" and type(obj[m]) == "function" and "yes" or "|cffff6666NO|r" end
    addon:Print("  sinks: SetAlphaFromBoolean=" .. has(sink.tex, "SetAlphaFromBoolean")
        .. " SetVertexColorFromBoolean=" .. has(sink.tex, "SetVertexColorFromBoolean")
        .. " SetCooldownFromDurationObject=" .. has(sink.cd, "SetCooldownFromDurationObject")
        .. " C_CurveUtil=" .. has(C_CurveUtil, "EvaluateColorFromBoolean"))

    local base, order = RunValidateSnapshot(addon, true)

    if not armed then
        addon:Print("Tip: '/jac inspect validate arm' re-captures on combat enter/exit and prints the diff.")
        addon:Print("=============================================")
        return
    end

    local f = CreateFrame("Frame")
    DebugCommands._validate = f
    local armT = GetTime()
    local combatSnap
    local pendingCaptureAt
    local settleCaptureAt

    local function disarm(msg)
        f:UnregisterAllEvents(); f:SetScript("OnEvent", nil); f:SetScript("OnUpdate", nil)
        DebugCommands._validate = nil
        addon:Print(msg)
    end

    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            pendingCaptureAt = GetTime() + 0.5  -- let secrecy state settle
        elseif combatSnap then
            settleCaptureAt = nil
            addon:Print("|cff00ff00validate: combat ended - post-combat vs in-combat:|r")
            PrintValidateEnv(addon)
            local post = RunValidateSnapshot(addon, false)
            DiffValidate(addon, combatSnap, post, order)
            disarm("validate: done.")
        end
    end)
    f:SetScript("OnUpdate", function()
        local now = GetTime()
        if pendingCaptureAt and now >= pendingCaptureAt then
            pendingCaptureAt = nil
            addon:Print("|cff00ff00validate: in-combat capture (+0.5s) - changes vs baseline:|r")
            PrintValidateEnv(addon)
            combatSnap = RunValidateSnapshot(addon, false)
            DiffValidate(addon, base, combatSnap, order)
            settleCaptureAt = now + 4.5  -- settle check: does anything flip late?
        end
        if settleCaptureAt and now >= settleCaptureAt then
            settleCaptureAt = nil
            local settled = RunValidateSnapshot(addon, false)
            addon:Print("|cff00ff00validate: settle check (~+5s vs +0.5s capture):|r")
            DiffValidate(addon, combatSnap, settled, order)
            combatSnap = settled  -- exit diff compares against the latest state
        end
        if now - armT > 600 then
            disarm("|cffffff00validate: 10min window ended - disarmed.|r")
        end
    end)
    if UnitAffectingCombat("player") then pendingCaptureAt = GetTime() end
    addon:Print("|cff00ff00validate ARMED:|r enter (and leave) combat to capture diffs. 10min window.")
end

-- SecrecyLevel enum, hoisted: 0 = the direct lookup always works for that spell.
local SECRECY_LEVEL = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }

--------------------------------------------------------------------------------
-- Maintenance slot recorder (/jac inspect maintlog)
--------------------------------------------------------------------------------
-- Samples tracker state to JustACGlobal so a whole fight can be read off disk instead of
-- pasted out of chat. Intermittent faults - a tracker stuck "down" for minutes, a bind that
-- never retries - are invisible in a snapshot and obvious in a sequence.
-- SavedVariables flush on /reload or logout ONLY: play, then /reload, then read the file.
local MAINTLOG_MAX = 400          -- ~6.5 min at 1s; bounded so it cannot bloat the file
local maintLogTicker = nil
local lastMaintPayload = nil   -- change-only guard for MaintLogSample

local function MaintLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.maintLog = g.maintLog or {}
    return g.maintLog
end

--- One compact sample. Only plain values - never persist a secret, and never let a probe
--- throw: a recorder that breaks combat is worse than no recorder.
---
--- `dur` is the field that localises a swipe delay. The renderer can only draw a swipe once
--- the duration object resolves, and that needs a bound instance - so:
---   inst=nil                -> the bind is late (bridge/exact-path problem)
---   inst set but dur=nil    -> bound to an instance with no duration object (wrong instance,
---                              or the aura went away)
---   inst set and dur=1      -> the data was ready and any remaining lag is the RENDERER
--- Emitted change-only by the caller, so these lines are transitions with real timestamps.
local function MaintLogSample()
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    if not (MT and MT.GetState) then return end
    local okS, state, _, inst = pcall(MT.GetState)
    if not okS then return end
    local d = (MT.GetBridgeDiag and select(2, pcall(MT.GetBridgeDiag))) or nil
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local hasDur = "?"
    if BAPI and BAPI.GetAuraDurationObject and type(inst) == "number" then
        hasDur = (BAPI.GetAuraDurationObject("player", inst) ~= nil) and "1" or "0"
    elseif type(inst) ~= "number" then
        hasDur = "-"
    end
    -- eff = the effective duration the clock is actually using (2nd return of
    -- GetEstimatedCooldown). Logged because every projected timer is built on it, and a
    -- poisoned learnedDuration silently shortens the sweep and fires the refresh cue early -
    -- measured once at ~4.2s against Ironfur's true 7.0s. nc = projected stack count.
    local eff, nc = "-", "-"
    if MT.GetEstimatedCooldown then
        local okE, _, len = pcall(MT.GetEstimatedCooldown)
        if okE and type(len) == "number" then eff = string.format("%.1f", len) end
    end
    if MT.GetProjectedStacks then
        local okN, n = pcall(MT.GetProjectedStacks)
        if okN and type(n) == "number" then nc = tostring(n) end
    end
    local payload = string.format("%s inst=%s dur=%s eff=%s nc=%s combat=%s b=%s/%s/%s cand=%s",
        tostring(state),
        (type(inst) == "number") and tostring(inst) or "nil",
        hasDur,
        eff,
        nc,
        (UnitAffectingCombat and UnitAffectingCombat("player")) and "1" or "0",
        d and tostring(d.batches or 0) or "?",
        d and tostring(d.bound or 0) or "?",
        d and tostring(d.ambiguous or 0) or "?",
        d and tostring(d.lastCandidates or 0) or "?")
    -- Change-only: at 10/s a clock-sampled log would be all duplicates and would ring out
    -- of the interesting window in 40s. Transitions are what a latency question needs.
    if payload == lastMaintPayload then return end
    lastMaintPayload = payload
    local log = MaintLogStore()
    log[#log + 1] = string.format("%.2f %s", GetTime(), payload)
    -- Ring: drop the oldest half in one pass rather than table.remove per sample (O(n) each).
    if #log > MAINTLOG_MAX then
        local keep, half = {}, math.floor(MAINTLOG_MAX / 2)
        for i = #log - half + 1, #log do keep[#keep + 1] = log[i] end
        _G.JustACGlobal.maintLog = keep
    end
end

--- /jac inspect maintlog [on|off|clear] - record maintenance-slot state once a second.
function DebugCommands.MaintenanceLog(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.maintLog = nil end
        addon:Print("maintlog: |cffffff00cleared|r")
        return
    end
    if arg == "off" or (not arg and maintLogTicker) then
        if maintLogTicker then maintLogTicker:Cancel() end
        maintLogTicker = nil
        local n = (_G.JustACGlobal and _G.JustACGlobal.maintLog and #_G.JustACGlobal.maintLog) or 0
        addon:Print(string.format("maintlog: |cffff6600OFF|r - %d samples held.", n))
        addon:Print("|cff888888/reload to flush them to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua|r")
        return
    end
    if not C_Timer or not C_Timer.NewTicker then
        addon:Print("|cffff6600C_Timer unavailable|r")
        return
    end
    -- 10/s: the reported lag is sub-second, which 1/s sampling cannot resolve at all.
    -- Cheap because the sample is change-only (see MaintLogSample).
    lastMaintPayload = nil
    maintLogTicker = C_Timer.NewTicker(0.1, function() pcall(MaintLogSample) end)
    addon:Print("maintlog: |cff00ff00ON|r - sampling 10/s, transitions only. Press the buff a few")
    addon:Print("times (first application AND refreshes), then |cffffff00/jac inspect maintlog off|r and |cffffff00/reload|r.")
end

--- /jac inspect maintenance - can the tank maintenance slot bind its aura EXACTLY in combat,
--- instead of guessing via the cast->instance bridge? Three questions, one call:
---   Q1 Is this spec's aura secret at all? GetSpellAuraSecrecy == 0 means the direct lookup
---      always works and the bridge is dead code for that spec.
---   Q2 Is the spell in the player's Cooldown Manager tracked set? No entry -> no join.
---   Q3 Does the CDM item frame hand back a PLAIN auraInstanceID? Blizzard's viewer is
---      untainted, so it legally reads the secret spellId and caches the instance id as an
---      ordinary field - we read the materialized number, never the secret.
--- Run it IN COMBAT with the buff up: that is the only state where Q1 and Q3 mean anything.
function DebugCommands.MaintenanceProbe(addon)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    if not entry then
        addon:Print("|cffff6600No maintenance entry for this spec|r - tank specs only (Brewmaster absent by design)")
        return
    end

    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false
    addon:Print("== maintenance slot probe ==")
    addon:Print(string.format("cast=%d aura=%d stacks=%s combat=%s",
        entry.cast, entry.aura, tostring(entry.stacks or false), tostring(inCombat)))
    if not inCombat then
        addon:Print("|cffff6600Out of combat|r - Q1/Q3 only mean something mid-fight. Re-run with the buff up.")
    end

    -- Q0b: engine-drawn displays. An aura container watching this exact buff on the player
    -- replaces the cast-time sweep and the bind-gated stack count wherever it attaches. Its
    -- failure mode is SILENCE - a container that never built, or one that built and draws
    -- nothing - and on screen that is indistinguishable from the buff simply being down. So
    -- the attachment has to be reportable, or the whole path is untestable from in game.
    do
        local ov = addon.maintenanceIcon and addon.maintenanceIcon._maintAura
        if not ov then
            addon:Print("Q0b engine displays: |cff888888not attached|r"
                .. " |cff888888(standard-queue slot only; it has not rendered on the"
                .. " upkeep path yet this session)|r")
        elseif not ov.container then
            addon:Print(string.format("Q0b engine displays: |cffff6600refused|r for aura %s"
                .. " - the slot keeps its own estimate", tostring(ov.aura)))
        else
            addon:Print(string.format("Q0b engine displays: aura=%s sweep=%s count=%s container=%s",
                tostring(ov.aura),
                ov.sweep and "|cff2ecc71ENGINE|r" or "|cffffff00cast estimate|r",
                ov.count and "|cff2ecc71ENGINE|r" or "|cffffff00projection/bind|r",
                ov.container:IsShown() and "shown" or "|cffff6600hidden|r"))
        end
    end

    -- Q0: is the refresh cue on ENGINE TRUTH or on the cast-time estimate? The two
    -- disagree exactly when the estimate is wrong, which is the whole reason the
    -- engine path exists - and a silent fall back to the estimate looks identical
    -- in the queue, so it has to be visible here.
    do
        local BAPI = LibStub("JustAC-BlizzardAPI", true)
        -- Two calls, NOT `local a, _, c = MT and MT.GetState and MT.GetState()`: an
        -- `and` chain yields a single value, so the 3rd return would always be nil
        -- and this probe would report "no live instance" forever. GetState memoizes
        -- per frame, so the second call is a table read.
        local state, inst
        if MT and MT.GetState then
            state = MT.GetState()
            inst = select(3, MT.GetState())
        end
        addon:Print(string.format("Q0 refresh source: state=%s instance=%s",
            tostring(state), tostring(inst)))
        -- Whether PRODUCTION uses the engine answer, which is not the same as
        -- whether one is available: stacking and charge-gated entries are excluded
        -- on purpose (see LiveVerdict). Printing the reading without saying who
        -- acts on it is how a probe starts describing a path nobody takes.
        local eligible = not entry.stacks and not entry.chargeGated
        addon:Print(string.format("   production uses: |cff%s|r  %s",
            eligible and "2ecc71ENGINE" or "ffff00cast-time estimate",
            eligible and "(single-instance refresh buff)"
                or (entry.stacks and "(stacking entry - one instance is a single stack's clock,"
                    .. " not the buff's; projection stays authoritative)"
                    or "(chargeGated - never pre-warns)")))
        if inst and BAPI and BAPI.GetAuraDurationObject then
            local d = BAPI.GetAuraDurationObject("player", inst)
            if d then
                addon:Print(string.format("   engine reads%s  below30%%=%s  below5s=%s  below2s=%s",
                    eligible and ":" or " |cff888888(shown for comparison only)|r:",
                    tostring(BAPI.IsDurationBelowPercent and BAPI.IsDurationBelowPercent(d, 30)),
                    tostring(BAPI.IsDurationBelowSeconds and BAPI.IsDurationBelowSeconds(d, 5)),
                    tostring(BAPI.IsDurationBelowSeconds and BAPI.IsDurationBelowSeconds(d, 2))))
                addon:Print("|cff888888   these should march true as the buff runs down;"
                    .. " below2s must not lead below30%|r")
            else
                addon:Print("   |cffffff00no duration object|r - falling back to the cast-time estimate")
            end
        else
            addon:Print("   |cffffff00no live instance|r - projected/viewer path, estimate is expected here")
        end
    end

    -- Q1: per-spell aura secrecy.
    local CS = C_Secrets
    if CS and CS.GetSpellAuraSecrecy then
        local function Sec(id)
            local ok, lvl = pcall(CS.GetSpellAuraSecrecy, id)
            if not ok then return "err" end
            local label = (type(lvl) == "number" and SECRECY_LEVEL[lvl]) or "?"
            return SafeSecret(lvl) .. " (" .. label .. ")"
        end
        addon:Print("Q1 secrecy: aura -> " .. Sec(entry.aura) .. "   cast -> " .. Sec(entry.cast))
        addon:Print("|cff888888   0 means no bridge is needed for this spec at all|r")
        addon:Print("|cff888888   (static per-SPELL property - same answer whether the buff is up or not)|r")
    else
        addon:Print("Q1 secrecy: |cffff6600C_Secrets.GetSpellAuraSecrecy unavailable|r")
    end

    -- The direct path, for contrast: nil in combat is exactly why the bridge exists.
    local direct
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local okD, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, entry.aura)
        direct = okD and d and d.auraInstanceID or nil
    end
    addon:Print("direct GetPlayerAuraBySpellID -> " .. SafeSecret(direct))

    -- The last untested crack in the tainted-legal aura surface. Of the six C_UnitAuras
    -- functions marked AllowedWhenTainted, every live-state one is blocked by a second flag:
    -- GetAuraBaseDuration / GetRefreshExtendedDuration carry RequiresUnitAuraAccess (the
    -- "cannot be accessed when secret while tainted" denial), and this one carries
    -- RequiresNonSecretAura - yet ALSO SecretWhenUnitAuraRestricted, which says the opposite.
    -- If it returns secret-but-PRESENT data rather than nil, that secret is something the
    -- zero-gate could turn into a branchable up/down and the maintenance slot would no longer
    -- need the Cooldown Manager at all. nil here closes the question for good.
    if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
        local okU, u = pcall(C_UnitAuras.GetUnitAuraBySpellID, "player", entry.aura)
        if not okU then
            addon:Print("GetUnitAuraBySpellID -> |cffff6600THREW|r (access denied while tainted)")
        elseif u == nil then
            addon:Print("GetUnitAuraBySpellID -> |cff888888nil|r (RequiresNonSecretAura wins - route closed)")
        else
            addon:Print(string.format(
                "GetUnitAuraBySpellID -> |cff2ecc71DATA|r inst=%s exp=%s dur=%s"
                .. "  |cffffff00<- gateable if these read secret|r",
                SafeSecret(u.auraInstanceID), SafeSecret(u.expirationTime), SafeSecret(u.duration)))
        end
    end

    -- Q2/Q3. NEVER call item:GetSpellID() - it returns the SECRET auraSpellID first. Only
    -- GetCooldownInfo (static layout data) and GetAuraSpellInstanceID (already materialized
    -- plain by untainted code) are safe to touch here.
    --
    -- Q2 the FRAME-INDEPENDENT way, straight off PRODUCTION's own resolver. This probe
    -- used to re-implement the category scan, and drifted: it kept the 0..3 range from
    -- when there were four categories while production moved to enumerating them, so on
    -- 12.1.0 (nine categories) it reported "not in any category set" for a buff the
    -- addon was binding perfectly. A probe with its own copy of the logic is a probe
    -- that can lie about the thing it exists to check.
    local trackedIDs = (MT and MT.ResolveCooldownIDs and MT.ResolveCooldownIDs(entry)) or {}
    local trackedCooldownID, trackedViewer = nil, nil
    do
        -- Category names by reverse lookup rather than a literal table, for the same
        -- reason production enumerates them: the next patch's categories name themselves.
        local catNames = {}
        if type(Enum) == "table" and type(Enum.CooldownViewerCategory) == "table" then
            for name, v in pairs(Enum.CooldownViewerCategory) do catNames[v] = name end
        end
        local VIEWER_BY_CAT = { [0] = "EssentialCooldownViewer", [1] = "UtilityCooldownViewer",
                                [2] = "BuffIconCooldownViewer", [3] = "BuffBarCooldownViewer" }
        local hitCat
        for id, cat in pairs(trackedIDs) do
            hitCat = (hitCat and (hitCat .. ", ") or "")
                     .. string.format("%s=%s", catNames[cat] or ("cat" .. tostring(cat)), tostring(id))
            trackedCooldownID = trackedCooldownID or id
            trackedViewer = trackedViewer or VIEWER_BY_CAT[cat]
        end
        if hitCat then
            -- "ELIGIBLE", not "tracked": production scans with allowUnlearned=true, so this
            -- is everything the categories COULD contain, not the subset the player put on
            -- their bar. Q3 is what decides whether a frame actually exists. Conflating the
            -- two cost a debugging round.
            addon:Print(string.format("Q2 |cff2ecc71ELIGIBLE|r for %s  |cff888888(Q3 says if it is on the bar)|r", hitCat))
        else
            addon:Print("Q2 |cffff6600NOT in any category set|r")
            addon:Print("|cff888888   spell genuinely absent from the Cooldown Manager data -> join impossible|r")
        end
    end

    -- Why the viewers may be hidden. A hidden viewer never computes auraInstanceID at all:
    -- OnShow registers UNIT_AURA, OnHide unregisters it. So Q3 REQUIRES a shown viewer.
    local okV, cvarOn = pcall(function()
        return C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled")
    end)
    local okAv, avail, why = pcall(function()
        local CV = C_CooldownViewer
        if CV and CV.IsCooldownViewerAvailable then return CV.IsCooldownViewerAvailable() end
    end)
    addon:Print(string.format("CooldownManager: cvar=%s available=%s %s",
        okV and tostring(cvarOn) or "err",
        okAv and tostring(avail) or "err",
        (okAv and why) and tostring(why) or ""))

    local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer",
                      "EssentialCooldownViewer", "UtilityCooldownViewer" }
    local found, scanned = nil, 0
    local seenIDs = {}
    for i = 1, #VIEWERS do
        local name = VIEWERS[i]
        local v = _G[name]
        local shown = (v and v.IsShown and v:IsShown()) and true or false
        local pool = v and v.itemFramePool
        local n = 0
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                n = n + 1
                scanned = scanned + 1
                -- Join on cooldownID (from the category set above), NOT on the frame's spell
                -- ids: GetCooldownID survives a hidden viewer, GetCooldownInfo appears not to.
                local okC, cid = pcall(item.GetCooldownID, item)
                if okC and type(cid) == "number" then
                    seenIDs[#seenIDs + 1] = cid
                end
                local isMatch = okC and type(cid) == "number" and trackedIDs[cid] and true or false
                if not isMatch and not next(trackedIDs) then
                    -- No cooldownID to join on: fall back to the spell-id set.
                    local okI, info = pcall(item.GetCooldownInfo, item)
                    isMatch = okI and MT and MT.MatchesCooldownInfo
                        and MT.MatchesCooldownInfo(entry, info) or false
                end
                if isMatch and not found then
                    local okA, inst = pcall(item.GetAuraSpellInstanceID, item)
                    local okU, unit = pcall(item.GetAuraDataUnit, item)
                    -- type() is NOT a secrecy guard - a SECRET number reports type "number" -
                    -- so this test called a secret plain, stored it, printed "IDENTITY
                    -- AVAILABLE" over a <secret>, and handed it to the cross-check below, which
                    -- compared it and threw. 12.1.0 is what made that reachable: this id used to
                    -- read plain here and now comes back secret IN COMBAT (plain out of it).
                    -- PlainText, not IsSecret: this is a struct field, and those can be secret
                    -- in ways issecretvalue alone misses.
                    local isPlain = okA and type(inst) == "number" and PlainText(inst) ~= nil
                    found = {
                        viewer = name, shown = shown, cid = cid,
                        inst = isPlain and inst or nil,
                        instStr = okA and SafeSecret(inst) or "err",
                        plain = isPlain,
                        unit = okU and tostring(unit) or "err",
                    }
                end
            end
        end
        -- alpha matters as much as shown: a viewer kept SHOWN at alpha 0 stays populated
        -- (pool laid out, auraInstanceID live) while being invisible to the player. Hidden
        -- is what empties the pool, not transparent.
        local okA, av = pcall(function() return v and v.GetAlpha and v:GetAlpha() end)
        addon:Print(string.format("  %-24s shown=%-5s alpha=%-4s items=%d",
            name, tostring(shown), okA and tostring(av) or "?", n))
    end

    if not found then
        local want = {}
        for id in pairs(trackedIDs) do want[#want + 1] = tostring(id) end
        table.sort(want)
        addon:Print(string.format("Q3 |cffff6600no live item frame|r (want any of %s, %d active items walked)",
            (#want > 0) and table.concat(want, "/") or "none", scanned))
        addon:Print("|cff888888   active frame cooldownIDs: " .. table.concat(seenIDs, ",") .. "|r")
        addon:Print("|cff888888   id absent -> the viewer is not feeding ids; id present -> match logic is wrong|r")
        if trackedViewer then
            local v = _G[trackedViewer]
            local vShown = (v and v.IsShown and v:IsShown()) and true or false
            if vShown then
                addon:Print(string.format("|cffffff00   %s IS shown but our id is not on it - add the spell to that bar in Edit Mode|r",
                    trackedViewer))
            else
                -- shown=false has TWO causes and they need different fixes. This message used to
                -- assert "not laid out", which cost a debugging session when the real cause was
                -- the panel's visibility dropdown set to Always Hidden - the panel WAS laid out.
                -- JustAC is never a candidate: its own cosmetic hide only ever sets alpha 0
                -- (MaintenanceTracker.ApplyViewerAlpha), which leaves IsShown() true.
                addon:Print(string.format("|cffffff00   our id belongs to %s, which is HIDDEN. Two causes:|r", trackedViewer))
                addon:Print("|cffffff00     1. the panel's Edit Mode visibility is set to Always Hidden -> set it to Always Show|r")
                addon:Print("|cffffff00     2. the panel is not enabled in this Edit Mode layout -> enable it|r")
                addon:Print("|cff888888     Either way a hidden viewer serves no ids and cannot be revived from addon|r")
                addon:Print("|cff888888     code (Documentation/AURA_IDENTITY_12.0.md). JustAC's own hide is alpha-only|r")
                addon:Print("|cff888888     and keeps it feeding, so hide it there rather than in Edit Mode.|r")
            end
        end
    else
        addon:Print(string.format("Q3 frame |cff2ecc71MATCH|r in %s (cooldownID=%s shown=%s)",
            found.viewer, tostring(found.cid), tostring(found.shown)))
        if not found.shown then
            -- Frames keep their cooldownID after hiding (OnHide clears nothing), so a match on
            -- a hidden viewer is expected - and useless: OnHide also unregisters UNIT_AURA, so
            -- any auraInstanceID it still holds is FROZEN at hide time. The tracker rejects
            -- these; a stale id that looks valid is worse than none.
            addon:Print("|cffff6600   viewer HIDDEN - id retained but aura data is frozen; tracker ignores this|r")
        end
        addon:Print(string.format("Q3 GetAuraSpellInstanceID -> %s  plain=%s  unit=%s",
            found.instStr, tostring(found.plain), found.unit))
        if found.plain and found.unit == "player" then
            addon:Print("|cff2ecc71   IDENTITY AVAILABLE|r - exact bind works, bridge becomes fallback")
        else
            addon:Print("|cffff6600   unusable|r - nil/secret instance, or the frame is scanning another unit")
            -- Deliberately not called "expected" or "normal": measured 2026-08-11, this id came
            -- back SECRET for Ironfur in combat and PLAIN (bound, agreeing) for Bone Shield in
            -- combat, so it is neither a flat combat rule nor a per-client one. Whatever decides
            -- it, the slot does not depend on the answer any more - say where to look instead.
            addon:Print("|cff888888   the exact bind is unavailable right now; Q0b shows what draws instead|r")
        end
    end

    -- Q4: the per-instance secrecy route - no Blizzard frame, no UI dependency at all.
    -- GetUnitAuraInstanceIDs returns a PLAIN table of ids (no secret annotation on its return,
    -- unlike GetUnitAuras which carries ConditionalSecretContents), and
    -- ShouldUnitAuraInstanceBeSecret answers per id with a plain bool. For instances it reports
    -- NON-secret, GetAuraDataByAuraInstanceID's spellId is readable and comparable - which is
    -- exact identity. sortRule is pinned to Unsorted(0): the other rules order by secret data.
    local UA, CSec = C_UnitAuras, C_Secrets
    if UA and UA.GetUnitAuraInstanceIDs and CSec and CSec.ShouldUnitAuraInstanceBeSecret then
        local okIDs, ids = pcall(UA.GetUnitAuraInstanceIDs, "player", "HELPFUL|PLAYER", nil, 0, 0)
        if okIDs and type(ids) == "table" then
            local readable, secretN, hit = 0, 0, nil
            for i = 1, #ids do
                local id = ids[i]
                local okS, isAuraSecret = pcall(CSec.ShouldUnitAuraInstanceBeSecret, "player", id)
                if okS and isAuraSecret == false then
                    readable = readable + 1
                    -- Contractually non-secret, but compare inside pcall anyway: being wrong
                    -- here throws, and this probe must never be the thing that breaks combat.
                    local okD, d = pcall(UA.GetAuraDataByAuraInstanceID, "player", id)
                    if okD and d then
                        local okC, isOurs = pcall(function()
                            return d.spellId == entry.aura or d.spellId == entry.cast
                        end)
                        if okC and isOurs and not hit then hit = id end
                    end
                elseif okS then
                    secretN = secretN + 1
                end
            end
            addon:Print(string.format("Q4 instances: %d total, %d readable, %d secret",
                #ids, readable, secretN))
            if hit then
                addon:Print(string.format("   |cff2ecc71EXACT IDENTITY|r via instance %d - no frame, no CDM needed", hit))
            elseif #ids == 0 then
                addon:Print("   |cffff6600enumerated ZERO|r - auras silently absent, not secret")
            elseif readable > 0 and secretN == 0 then
                -- Nothing is hidden, so "ours is secret" cannot be the explanation: the buff
                -- is simply not applied right now. Saying "secret" here sends you hunting a
                -- secrecy problem when the answer is "re-run with it up".
                addon:Print("   |cffff6600no instance is ours|r - and nothing is secret, so the buff is not applied; re-run with it up")
            elseif readable > 0 then
                addon:Print("   |cffff6600readable instances exist, none is ours|r - ours is among the secret set")
            else
                addon:Print("   |cffff6600every instance secret|r - route closed for this unit/filter")
            end
        else
            addon:Print("Q4 |cffff6600GetUnitAuraInstanceIDs call failed|r")
        end
    else
        addon:Print("Q4 |cffff6600per-instance secrecy API unavailable|r (needs GetUnitAuraInstanceIDs + ShouldUnitAuraInstanceBeSecret)")
    end

    -- Q5: which aura FILTERS does our buff actually match? The bridge currently asks
    -- "HELPFUL|PLAYER", which every trinket proc also satisfies - that breadth IS the mis-bind.
    -- If our aura also carries a narrower flag (BIG_DEFENSIVE is the hope), the bridge can ask
    -- for that instead and stop matching unrelated procs. Run OUT of combat, where we can
    -- resolve the true instance first: testing filters against a guessed instance proves nothing.
    do
        local UAf = C_UnitAuras
        local known = nil
        if UAf and UAf.GetPlayerAuraBySpellID then
            local okD, d = pcall(UAf.GetPlayerAuraBySpellID, entry.aura)
            known = okD and d and d.auraInstanceID or nil
        end
        -- The question is NOT "what does our aura match" - it is "does any narrower filter
        -- SEPARATE our aura from the other player-helpful auras". That is answerable without
        -- knowing which instance is ours: count how many of the whole HELPFUL|PLAYER set match
        -- each narrow token. A token matched by exactly 1 of N is a discriminating filter and
        -- can replace "HELPFUL|PLAYER" in the bridge; a token matched by all N or none is
        -- useless. This works IN COMBAT, where the exact-instance version cannot.
        local TOKENS = { "BIG_DEFENSIVE", "IMPORTANT", "EXTERNAL_DEFENSIVE", "CANCELABLE",
                         "NOT_CANCELABLE", "RAID", "RAID_IN_COMBAT", "CROWD_CONTROL" }
        if UAf and UAf.IsAuraFilteredOutByInstanceID and UAf.GetUnitAuraInstanceIDs then
            local okIDs, ids = pcall(UAf.GetUnitAuraInstanceIDs, "player", "HELPFUL|PLAYER", nil, 0, 0)
            if okIDs and type(ids) == "table" and #ids > 0 then
                local parts = {}
                for t = 1, #TOKENS do
                    local n, ourHit = 0, false
                    for i = 1, #ids do
                        local okF, out = pcall(UAf.IsAuraFilteredOutByInstanceID, "player", ids[i], TOKENS[t])
                        if okF and out == false then
                            n = n + 1
                            if known and ids[i] == known then ourHit = true end
                        end
                    end
                    if n > 0 then
                        parts[#parts + 1] = string.format("%s=%d%s", TOKENS[t], n, ourHit and "*" or "")
                    end
                end
                addon:Print(string.format("Q5 of %d player-helpful auras: %s", #ids,
                    (#parts > 0) and table.concat(parts, " ") or "|cffff6600no narrow token matches any|r"))
                addon:Print("|cff888888   a token matching exactly 1 discriminates -> use it in the bridge"
                    .. (known and "; * = confirmed ours" or "") .. "|r")
            else
                addon:Print("Q5 |cffff6600no player-helpful auras enumerated|r")
            end
        else
            addon:Print("Q5 filters: |cffff6600filter API unavailable|r")
        end
    end

    -- Bridge health. If `ambiguous` dominates `bound`, the single-candidate guard is refusing
    -- every batch and the tracker can never bind in combat - which presents as a false "down".
    if MT and MT.GetBridgeDiag then
        local okG, d = pcall(MT.GetBridgeDiag)
        if okG and type(d) == "table" then
            addon:Print(string.format("bridge: batches=%d bound=%d ambiguous=%d lastCand=%d maxCand=%d",
                d.batches or 0, d.bound or 0, d.ambiguous or 0, d.lastCandidates or 0, d.maxCandidates or 0))
            -- Needs a real sample before crying starvation: measured in game, "1 ambiguous,
            -- 0 bound" simply means the first clean batch has not arrived yet, and it bound
            -- normally seconds later. Only a sustained run of ambiguity is evidence.
            if (d.ambiguous or 0) >= 6 and (d.bound or 0) == 0 then
                addon:Print("   |cffff0000guard may be starving the bind|r - many batches, never bound")
            end
        end
    end

    -- Cross-check. A disagreement here IS the wrong-stacks bug, caught in the act.
    if MT and MT.GetState then
        local okS, state, _, inst = pcall(MT.GetState)
        if okS then
            addon:Print(string.format("tracker: state=%s instance=%s", tostring(state), SafeSecret(inst)))
            if found and found.plain and type(inst) == "number" then
                if inst == found.inst then
                    addon:Print("|cff2ecc71   AGREES with Cooldown Manager|r")
                else
                    addon:Print("|cffff0000   DISAGREES - bridge bound the WRONG aura (this is the stacks bug)|r")
                end
            end
        end
    end

    -- Q6: loss-of-control readout. Answers "why no CC break" directly - what the game reports
    -- while you are held, whether locType reads plain or secret, and what the tracker resolves.
    local LOC = C_LossOfControl
    if LOC and LOC.GetActiveLossOfControlDataCount then
        local okC, n = pcall(LOC.GetActiveLossOfControlDataCount)
        addon:Print(string.format("Q6 loss-of-control: count=%s", okC and SafeSecret(n) or "err"))
        if okC and type(n) == "number" and n > 0 and LOC.GetActiveLossOfControlData then
            for i = 1, n do
                local okD, d = pcall(LOC.GetActiveLossOfControlData, i)
                if okD and d then
                    local lt = d.locType
                    addon:Print(string.format("   [%d] locType=%s%s displayType=%s",
                        i, SafeSecret(lt),
                        BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(lt)
                            and " |cffff6600(SECRET)|r" or "",
                        SafeSecret(d.displayType)))
                end
            end
        end
        local sid, item = nil, nil
        if MT and MT.GetCCBreak then sid, item = MT.GetCCBreak() end
        local macro = MT and MT.GetCCBreakMacro and MT.GetCCBreakMacro(addon.db.profile)
        addon:Print(string.format("   resolved: spell=%s item=%s macro=%s",
            tostring(sid), tostring(item), tostring(macro)))
        -- The selected macro and whether it actually yields a keybind: "" means it is not on a
        -- bound action-bar slot, so the slot correctly shows nothing. This is the other half of
        -- "macro set but nothing appears".
        local chosen = addon.db.profile.ccBreakMacro
        if chosen and chosen ~= "" then
            local ABS = LibStub("JustAC-ActionBarScanner", true)
            local key = ABS and ABS.GetMacroHotkey and ABS.GetMacroHotkey(chosen) or "?"
            addon:Print(string.format("   macro '%s' keybind=%s%s", chosen,
                (key ~= "" and key ~= "?") and key or "|cffff6600(none - not on a bound action bar slot)|r",
                (key == "?") and " (scanner unavailable)" or ""))
        end
        if not sid and not macro then
            addon:Print("|cff888888   nothing resolved. If locType above shows a string I don't map")
            addon:Print("|cff888888   (STUN/ROOT/FEAR are UNVERIFIED guesses), that is the bug - report it.|r")
        end
    else
        addon:Print("Q6 loss-of-control: |cffff6600C_LossOfControl unavailable|r")
    end
end

--- /jac inspect locwatch - ARM a loss-of-control capture. CC is a 2-4s window that a hand-run
--- probe keeps missing, so listen for the event instead and dump the REAL data the instant it
--- lands: the actual locType string (which the source cannot confirm), whether it reads secret,
--- and whether any of our mappings/breakers resolve. This is what settles "macro set, nothing
--- shows" - get CC'd once and it prints the truth.
function DebugCommands.LossOfControlWatch(addon)
    if DebugCommands._locWatch then
        DebugCommands._locWatch:UnregisterAllEvents()
        DebugCommands._locWatch:SetScript("OnEvent", nil)
        DebugCommands._locWatch = nil
        addon:Print("|cffffff00locwatch: disarmed.|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._locWatch = f
    local armT = GetTime()
    local fires = 0
    local LOC = C_LossOfControl
    local MT = LibStub("JustAC-MaintenanceTracker", true)

    -- Scratch Cooldown for laundering a DurationObject into a plain shown-boolean.
    local function scratchShown(durObj)
        if durObj == nil then return "|cff888888nil-dur|r" end
        local sc = DebugCommands._locScratch
        if not sc then
            local holder = CreateFrame("Frame", nil, UIParent)
            holder:Hide()
            sc = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
            DebugCommands._locScratch = sc
        end
        if not sc.SetCooldownFromDurationObject then return "|cff888888no-api|r" end
        sc:SetCooldownFromDurationObject(durObj)
        local shown = sc:IsShown()
        sc:SetCooldown(0, 0)
        return tostring(shown)
    end
    -- First few rotation spells for the per-spell lockout boolean check.
    local lockoutIds = {}
    do
        local BAPI = LibStub("JustAC-BlizzardAPI", true)
        local list = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
        if list then for i = 1, math.min(3, #list) do lockoutIds[i] = list[i] end end
    end

    f:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    f:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    f:RegisterEvent("PLAYER_CONTROL_LOST")
    f:RegisterEvent("PLAYER_CONTROL_GAINED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
            addon:Print(string.format("|cff00ccff%s|r  UIParent.isOutOfControl=%s", event,
                ClassifyRead(function() return UIParent.isOutOfControl end)))
            return
        end
        if not (LOC and LOC.GetActiveLossOfControlDataCount) then return end
        local okC, n = pcall(LOC.GetActiveLossOfControlDataCount)
        if not okC or type(n) ~= "number" or n < 1 then return end
        fires = fires + 1
        addon:Print(string.format("|cff00ff00LOC fired|r (%s) count=%d combat=%s", event, n,
            tostring(UnitAffectingCombat("player"))))
        for i = 1, n do
            local okD, d = pcall(LOC.GetActiveLossOfControlData, i)
            if okD and d then
                addon:Print(string.format("  [%d] locType=%s displayType=%s spellID=%s priority=%s auraInst=%s",
                    i, SafeSecret(d.locType), SafeSecret(d.displayType), SafeSecret(d.spellID),
                    SafeSecret(d.priority), SafeSecret(d.auraInstanceID)))
                addon:Print(string.format("      timeRemaining=%s duration=%s lockoutSchool=%s",
                    ClassifyRead(function() return d.timeRemaining end),
                    ClassifyRead(function() return d.duration end),
                    ClassifyRead(function() return d.lockoutSchool end)))
            end
        end
        -- Duration object route + slows: speed is expected SECRET in combat
        -- (SecretWhenUnitStatsRestricted) - measure, don't assume.
        if LOC.GetActiveLossOfControlDuration then
            local okDur, durObj = pcall(LOC.GetActiveLossOfControlDuration, "player", 1)
            if okDur and durObj then
                addon:Print(string.format("  durObj[1]: HasSecretValues=%s scratchShown=%s",
                    ClassifyRead(function() return durObj:HasSecretValues() end), scratchShown(durObj)))
            end
        end
        addon:Print("  GetUnitSpeed(player)=" .. ClassifyRead(function() return (GetUnitSpeed("player")) end))
        for _, id in ipairs(lockoutIds) do
            local okL, li = pcall(C_Spell.GetSpellLossOfControlCooldownInfo, id)
            addon:Print(string.format("  lockout %s: isActive=%s", tostring(id),
                (okL and li) and ClassifyRead(function() return li.isActive end) or "|cff888888no-info|r"))
        end
        local sid = MT and MT.GetCCBreak and MT.GetCCBreak()
        local macro = MT and MT.GetCCBreakMacro and MT.GetCCBreakMacro(addon.db.profile)
        addon:Print(string.format("  -> resolves: spell=%s macro=%s", tostring(sid), tostring(macro)))
        if fires >= 120 or GetTime() - armT > 1800 then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._locWatch = nil
            addon:Print("|cffffff00locwatch: window ended.|r")
        end
    end)
    addon:Print("|cff00ff00=== locwatch ARMED (30min) ===|r get stunned/rooted/DAZED; it prints the real locType on the spot.")
    addon:Print("|cff888888  ALL entries dump (a snare may hide behind displayType NONE). Run again to disarm early.|r")
end

--------------------------------------------------------------------------------
-- 68887 signal-audit probes (Documentation/PROBE_PLAN_68887.md, Session 1)
--------------------------------------------------------------------------------

--- Rotation ids helper for the audit probes (first n, fail-open to empty).
local function RotationIds(n)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local list = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
    local ids = {}
    if list then for i = 1, math.min(n, #list) do ids[i] = list[i] end end
    return ids
end

--- /jac inspect selfcast - ARM a capture of the player's own cast info. Claim
--- (68887 docs): SecretWhenUnitSpellCastRestricted only fires for non-player
--- units, so UnitCastingInfo/UnitChannelInfo("player") read PLAIN in combat.
--- Cast anything (hardcast + a channel) in AND out of combat; disarm = run again.
function DebugCommands.SelfCastProbe(addon)
    if DebugCommands._selfCast then
        DebugCommands._selfCast:UnregisterAllEvents()
        DebugCommands._selfCast:SetScript("OnEvent", nil)
        DebugCommands._selfCast = nil
        addon:Print("|cffffff00selfcast: disarmed.|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._selfCast = f
    local armT, fires, kicks = GetTime(), 0, 0
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    -- 4th payload arg. MEASURED 2026-07-25 - it is two different things depending on
    -- the event, which is why both are captured and labelled separately:
    --   UNIT_SPELLCAST_STOP        -> a PLAIN small integer (castBarID). Always
    --                                 present, so it says nothing about interrupts.
    --   UNIT_SPELLCAST_INTERRUPTED -> nil, or a SECRET string (the interrupter's
    --                                 GUID). THIS is the real signal: non-nil means
    --                                 the cast was actually interrupted rather than
    --                                 having merely ended. Both cases were observed
    --                                 in one fight, so the distinction is live.
    -- The value stays sealed, but presence-vs-nil is readable without reading it
    -- (issecretvalue(arg) or arg ~= nil) - which is all CastInterruptTracker needs
    -- to replace its 1s debounce guess. Channels fire CHANNEL_STOP, not INTERRUPTED.
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    f:SetScript("OnEvent", function(_, event, _, _, _, interruptedBy)
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if kicks >= 20 then return end
            kicks = kicks + 1
            -- Never branch on the value: only ask whether the slot is occupied.
            local occupied = (issecretvalue and issecretvalue(interruptedBy)) or interruptedBy ~= nil
            local meaning = (event == "UNIT_SPELLCAST_STOP")
                and "castBarID - expect always-present, NOT an interrupt signal"
                or "interrupter GUID - occupied=true means genuinely interrupted"
            addon:Print(string.format("|cff00ccff%s|r combat=%s arg4-occupied=%s (%s) [%s]",
                event, tostring(UnitAffectingCombat("player")), tostring(occupied),
                ClassifyRead(function() return interruptedBy end), meaning))
            return
        end
        fires = fires + 1
        local isChannel = event ~= "UNIT_SPELLCAST_START"
        addon:Print(string.format("|cff00ff00%s|r combat=%s", event, tostring(UnitAffectingCombat("player"))))
        local info = { (isChannel and UnitChannelInfo or UnitCastingInfo)("player") }
        -- UnitCastingInfo: name,text,texture,startTimeMs,endTimeMs,isTradeskill,castID,notInterruptible,spellID
        -- UnitChannelInfo: name,text,texture,startTimeMs,endTimeMs,isTradeskill,notInterruptible,spellID,isEmpowered,numEmpowerStages
        local FIELDS = isChannel
            and { "name", 4, "startTimeMs", 5, "endTimeMs", 7, "notInterruptible", 8, "spellID", 9, "isEmpowered", 10, "numEmpowerStages" }
            or  { "name", 4, "startTimeMs", 5, "endTimeMs", 7, "castID", 8, "notInterruptible", 9, "spellID" }
        addon:Print("  name=" .. ClassifyRead(function() return info[1] end))
        for i = 2, #FIELDS, 2 do
            local idx, fname = FIELDS[i], FIELDS[i + 1]
            addon:Print(string.format("  %s=%s", fname, ClassifyRead(function() return info[idx] end)))
        end
        -- The doc asymmetry: UnitCastingDuration SecretReturns=true, UnitChannelDuration unannotated.
        if UnitCastingDuration then
            addon:Print("  castDur:HasSecretValues=" .. ClassifyRead(function()
                local d = UnitCastingDuration("player"); return d and d:HasSecretValues() end))
        end
        if UnitChannelDuration then
            addon:Print("  chanDur:HasSecretValues=" .. ClassifyRead(function()
                local d = UnitChannelDuration("player"); return d and d:HasSecretValues() end))
        end
        local sid = info[isChannel and 8 or 9]
        if sid and C_Spell.IsCurrentSpell then
            addon:Print("  IsCurrentSpell=" .. ClassifyRead(function() return C_Spell.IsCurrentSpell(sid) end))
        end
        if fires >= 12 or GetTime() - armT > 300 then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._selfCast = nil
            addon:Print("|cffffff00selfcast: window ended.|r")
        end
    end)
    addon:Print("|cff00ff00=== selfcast ARMED (5min/12 casts) ===|r hardcast + channel something, in and out of combat.")
    addon:Print("|cff888888  Also logs target STOP vs INTERRUPTED arg4 - kick a target's cast to see the two differ.|r")
end

--------------------------------------------------------------------------------
-- /jac inspect healprobe [arm|show] - heal-mode Phase 0 probe battery.
-- Everything the planned healer queue would branch on, measured on live party
-- units (follower-dungeon NPC allies included). Three modes:
--   (none) one-shot census - run once OUT of combat, again IN combat with the
--          party taking damage; the delta is the finding.
--   show   toggle an on-screen swatch row proving the party health-curve alpha
--          sink tracks each member (eyes are the only readback - the alpha
--          itself is secret).
--   arm    toggle a 5-minute capture of cast-target secrecy and party
--          UNIT_AURA instance plumbing (cast HoTs on party members while armed).
-- Reads only: never writes a CVar, never assigns a Blizzard frame field.
--------------------------------------------------------------------------------

-- Urgency bands mirroring the planned party cue: bright below 35%, dim up to
-- 90%, invisible above. Module-level constant - the curve caches by identity.
local HEALPROBE_BANDS = { { 0, 1 }, { 0.35, 0.65 }, { 0.9, 0 } }
local HEALPROBE_UNITS = { "player", "party1", "party2", "party3", "party4" }
local HEALPROBE_PARTY = { party1 = true, party2 = true, party3 = true, party4 = true }

--- Compact classifier for per-unit grid lines (ClassifyRead is too wide there).
--- Narrow cells only; the verdict itself comes from the shared primitive, which
--- catches the struct fields IsSecretValue alone misses - this grid reads aura and
--- heal-prediction structs, which is exactly where that gap showed up.
local function HealCR(fn)
    local cell, status = ProbeCell(fn, 14)
    if status == "secret" then return "|cffff6600SECRET|r" end
    if status == "err" then return "|cffff6600ERR|r" end
    return cell
end

--- `show`: one swatch per party slot, alpha handed to the engine per tick.
local function HealProbeSwatches(addon)
    if DebugCommands._healSwatchFrame then
        DebugCommands._healSwatchFrame:Hide()
        DebugCommands._healSwatchFrame:SetParent(nil)
        DebugCommands._healSwatchFrame = nil
        addon:Print("healprobe swatches: OFF")
        return
    end
    local UFF = LibStub("JustAC-UIFrameFactory", true)
    if not (UFF and UFF.SetAlphaFromHealthCurve) then
        addon:Print("healprobe: |cffff6666UIFrameFactory unavailable|r")
        return
    end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(5 * 64 + 8, 76)
    f:SetPoint("CENTER", 0, 200)
    f._swatches = {}
    for i, unit in ipairs(HEALPROBE_UNITS) do
        local box = f:CreateTexture(nil, "ARTWORK")
        box:SetColorTexture(0.15, 0.85, 0.3, 1)  -- solid green; the curve drives alpha
        box:SetSize(56, 40)
        box:SetPoint("TOPLEFT", (i - 1) * 64 + 8, -16)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOP", box, "BOTTOM", 0, -2)
        fs:SetText(unit)
        f._swatches[i] = { tex = box, unit = unit }
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)
    title:SetText("bright<35% dim<90% gone at full - row = party order")
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.1 then return end
        self._t = 0
        for _, s in ipairs(self._swatches) do
            -- The helper sinks the secret alpha engine-side; false = no unit or
            -- technique dead, either way the swatch must not stick visible.
            if not UFF.SetAlphaFromHealthCurve(s.tex, s.unit, HEALPROBE_BANDS, true) then
                pcall(s.tex.SetAlpha, s.tex, 0)
            end
        end
    end)
    DebugCommands._healSwatchFrame = f
    addon:Print("healprobe swatches: ON (top-center). Let party members take damage.")
    addon:Print("|cff888888A swatch tracking ITS member's health = curve sink works on that unit class.|r")
    addon:Print("|cff888888Run /jac inspect healprobe show again to remove.|r")
end

--- `arm`: capture cast-target secrecy + party aura-instance plumbing.
local function HealProbeCapture(addon)
    if DebugCommands._healCapture then
        DebugCommands._healCapture:UnregisterAllEvents()
        DebugCommands._healCapture:SetScript("OnEvent", nil)
        DebugCommands._healCapture = nil
        addon:Print("|cffffff00healprobe: disarmed.|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._healCapture = f
    local armT, sent, added = GetTime(), 0, 0
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
        if GetTime() - armT > 300 then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._healCapture = nil
            addon:Print("|cffffff00healprobe: capture window ended.|r")
            return
        end
        if event == "UNIT_SPELLCAST_SENT" then
            -- Args: unit, targetName, castGUID, spellID. The target NAME is the
            -- HoT-attribution backbone; its secrecy is annotated ConditionalSecret,
            -- so this capture is the only way to learn the 12.0 condition.
            if unit ~= "player" or sent >= 10 then return end
            sent = sent + 1
            local sName = arg4 and C_Spell.GetSpellName and C_Spell.GetSpellName(arg4)
            addon:Print(string.format("|cff00ccffSENT|r %s target=%s combat=%s",
                tostring(sName or arg4), ClassifyRead(function() return arg2 end),
                tostring(UnitAffectingCombat("player"))))
        elseif event == "UNIT_AURA" then
            if not HEALPROBE_PARTY[unit] or added >= 20 then return end
            local info = arg2
            local list = info and info.addedAuras
            if type(list) ~= "table" then return end
            for i = 1, #list do
                added = added + 1
                local a = list[i]
                -- instanceID plain = the cast->instance bridge can bind on party
                -- units; the HELPFUL|PLAYER filter verdict is the ours-detector.
                addon:Print(string.format("|cff00ff00+aura|r %s instID=%s spellId=%s fromMe=%s oursFilter=%s",
                    unit,
                    ClassifyRead(function() return a.auraInstanceID end),
                    HealCR(function() return a.spellId end),
                    HealCR(function() return a.isFromPlayerOrPlayerPet end),
                    HealCR(function()
                        return C_UnitAuras.IsAuraFilteredOutByInstanceID
                            and C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, a.auraInstanceID, "HELPFUL|PLAYER")
                    end)))
            end
        end
    end)
    addon:Print("|cff00ff00=== healprobe ARMED (5min) ===|r Cast HoTs on party members, in and out of combat.")
    addon:Print("|cff888888SENT target plain + party instID plain + oursFilter plain bool = HoT upkeep bridge works.|r")
end

--- `watch`: edge-triggered watcher for the party-low table. The one-shot census
--- can't catch "someone is below the threshold RIGHT NOW" while the user is busy
--- healing; this polls at 0.25s and prints only TRANSITIONS. A read that throws
--- or returns secret is itself the verdict (laundering failed) and is printed
--- loudly rather than swallowed.
local function HealProbeWatch(addon)
    if DebugCommands._healWatch then
        DebugCommands._healWatch:SetScript("OnUpdate", nil)
        DebugCommands._healWatch = nil
        addon:Print("|cffffff00healprobe watch: OFF.|r")
        return
    end
    local caa = _G.CombatAudioAlertManager
    if not caa then
        addon:Print("healprobe watch: |cffff6666alert manager frame not found|r")
        return
    end
    local cvar = tostring(GetCVar and GetCVar("CAAPartyHealthPercent") or "?")
    if cvar == "0" then
        addon:Print("|cffff6600Party health alert CVar is 0 - enable the accessibility setting first.|r")
    end
    local f = CreateFrame("Frame")
    DebugCommands._healWatch = f
    local last, lastCount, armT = {}, nil, GetTime()
    addon:Print(string.format("|cff00ff00=== healprobe watch ON (5min, threshold-CVar=%s) ===|r pull; transitions print as they happen.", cvar))
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.25 then return end
        self._t = 0
        if GetTime() - armT > 300 then
            f:SetScript("OnUpdate", nil)
            DebugCommands._healWatch = nil
            addon:Print("|cffffff00healprobe watch: window ended.|r")
            return
        end
        -- unitCount: a plain int per the source; secret/throw = failed laundering.
        local okC, count = pcall(function()
            return caa.partyHealthInfo and caa.partyHealthInfo.unitCount end)
        local countState = not okC and "ERROR"
            or (issecretvalue and issecretvalue(count)) and "SECRET"
            or tostring(count)
        if countState ~= lastCount then
            local bad = (countState == "ERROR" or countState == "SECRET")
            addon:Print(string.format("%sunitCount -> %s|r  combat=%s",
                bad and "|cffff6600" or "|cff2ecc71", countState,
                tostring(UnitAffectingCombat("player"))))
            lastCount = countState
        end
        for _, u in ipairs(HEALPROBE_UNITS) do
            local okK, present = pcall(function()
                local ui = caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
                return ui and (ui[u] ~= nil) or false end)
            local state = not okK and "ERROR"
                or (issecretvalue and issecretvalue(present)) and "SECRET"
                or tostring(present)
            if state ~= last[u] then
                local bad = (state == "ERROR" or state == "SECRET")
                -- true/false transitions are the PASS signal; ERROR/SECRET is the
                -- laundering-failed verdict the whole emergency tier hangs on.
                addon:Print(string.format("%slow[%s] -> %s|r  combat=%s",
                    bad and "|cffff6600" or "|cff2ecc71", u, state,
                    tostring(UnitAffectingCombat("player"))))
                last[u] = state
            end
        end
    end)
end

--- `cvar [index]`: the auto-setup taint experiment. Writes the party-health
--- threshold CVar from ADDON (tainted) code - the exact thing the sweep memory
--- warns might taint the alert manager's cached compare. If, after this write,
--- keys still flip plain during a fight (`watch`) and `/jac inspect errors`
--- stays clean, a managed-CVar setup toggle (nameplate-overlay save/restore
--- pattern) is safe to ship. Recovery if it breaks: re-set the threshold from
--- Blizzard's accessibility settings, or /reload.
local function HealProbeCVarWrite(addon, arg)
    if InCombatLockdown() then
        addon:Print("|cffff6600Run the cvar write OUT of combat.|r")
        return
    end
    local cur = tostring(GetCVar and GetCVar("CAAPartyHealthPercent") or "?")
    local idx = arg and arg:match("^cvar%s+(%d+)$")
    if not idx then
        addon:Print(string.format("Usage: /jac inspect healprobe cvar <index>  (current=%s; 0 disables)", cur))
        addon:Print("|cff888888Writes the threshold CVar from addon code to test the taint theory.|r")
        return
    end
    local ok, err = pcall(SetCVar, "CAAPartyHealthPercent", idx)
    addon:Print(string.format("SetCVar CAAPartyHealthPercent %s -> %s : %s",
        cur, idx, ok and "|cff2ecc71written|r" or ("|cffff6600FAILED|r " .. tostring(err))))
    if ok then
        addon:Print("Now: `healprobe watch`, pull, let members drop below the threshold, then `/jac inspect errors`.")
        addon:Print("|cff888888Keys flipping plain + zero taint errors = managed auto-setup is shippable.|r")
    end
end

function DebugCommands.HealProbe(addon, arg)
    if arg == "show" then return HealProbeSwatches(addon) end
    if arg == "arm" then return HealProbeCapture(addon) end
    if arg == "watch" then return HealProbeWatch(addon) end
    if arg and arg:match("^cvar") then return HealProbeCVarWrite(addon, arg) end

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local UFF = LibStub("JustAC-UIFrameFactory", true)
    local caa = _G.CombatAudioAlertManager
    local caaApi = _G.C_CombatAudioAlert

    addon:Print("== heal-mode probe ==  run OOC, then IN combat while the party takes damage")
    local role = GetSpecialization() and GetSpecializationRole(GetSpecialization())
    addon:Print(string.format("  combat=%s grouped=%s members=%s role=%s",
        tostring(InCombatLockdown()), tostring(IsInGroup()),
        tostring(GetNumGroupMembers()), tostring(role)))

    -- A. The one branchable ally-low signal: key-existence in the accessibility
    -- alert manager's table, inserted by untainted code. Values stay untouched.
    addon:Print("|cff66ccffA. party-low bridge (audio-alert manager)|r")
    addon:Print(string.format("  manager=%s IsEnabled=%s threshold-CVar=%s (0 = feature off; volume CVar mutes the voice)",
        tostring(caa ~= nil),
        HealCR(function() return caaApi and caaApi.IsEnabled and caaApi.IsEnabled() end),
        HealCR(function() return GetCVar("CAAPartyHealthPercent") end)))
    addon:Print("  unitCount=" .. ClassifyRead(function()
        return caa and caa.partyHealthInfo and caa.partyHealthInfo.unitCount end))
    addon:Print("  keys-iterable=" .. ClassifyRead(function()
        local ui = caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
        if not ui then return nil end
        local n = 0
        for _ in pairs(ui) do n = n + 1 end
        return n end))
    for _, u in ipairs(HEALPROBE_UNITS) do
        addon:Print(string.format("  low[%s]=%s", u, ClassifyRead(function()
            local ui = caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
            if not ui then return nil end
            return ui[u] ~= nil end)))
    end
    -- Same signal through the shipping wrapper: these must agree with the raw
    -- reads above, or the wrapper's guards are wrong.
    if BlizzardAPI and BlizzardAPI.GetPartyLowCount then
        local parts = {}
        for _, u in ipairs(HEALPROBE_UNITS) do
            parts[#parts + 1] = u:gsub("party", "p") .. "=" .. tostring(BlizzardAPI.IsUnitLow(u))
        end
        addon:Print(string.format("  |cff888888via BlizzardAPI:|r available=%s count=%s  %s",
            tostring(BlizzardAPI.IsPartyLowAvailable()),
            tostring(BlizzardAPI.GetPartyLowCount()), table.concat(parts, " ")))
    end

    -- B. Plain per-unit gates the queue would branch on.
    addon:Print("|cff66ccffB. roster gates (per unit: exists/conn/dead/role/name/maxHP/threat/cmp)|r")
    for _, u in ipairs(HEALPROBE_UNITS) do
        addon:Print(string.format("  %-7s %s %s %s %s %s %s %s", u,
            HealCR(function() return UnitExists(u) end),
            HealCR(function() return UnitIsConnected(u) end),
            HealCR(function() return UnitIsDeadOrGhost(u) end),
            HealCR(function() return UnitGroupRolesAssigned(u) end),
            HealCR(function() return UnitName(u) end),
            HealCR(function() return UnitHealthMax(u) end),
            HealCR(function() return UnitThreatSituation(u) end)
            .. "/" .. HealCR(function()
                return C_Secrets and C_Secrets.CanCompareUnitTokens
                    and C_Secrets.CanCompareUnitTokens("player", u) end)))
    end

    -- C. Availability of the display-only curve sink per unit (the alpha itself
    -- is secret - `show` mode is the eyes-on proof; this only asks "did the
    -- helper wire up").
    addon:Print("|cff66ccffC. health-curve alpha sink availability|r")
    if UFF and UFF.SetAlphaFromHealthCurve then
        DebugCommands._healScratch = DebugCommands._healScratch or CreateFrame("Frame")
        local parts = {}
        for _, u in ipairs(HEALPROBE_UNITS) do
            local ok = UFF.SetAlphaFromHealthCurve(DebugCommands._healScratch, u, HEALPROBE_BANDS, true)
            parts[#parts + 1] = u .. "=" .. (ok and "|cff2ecc71ok|r" or "|cffff6600no|r")
        end
        addon:Print("  " .. table.concat(parts, " "))
    else
        addon:Print("  |cffff6666UIFrameFactory unavailable|r")
    end

    -- D. Engine aura filters on party units. CountAuras carries the shipped
    -- token-verdict guard: nil = token not trusted (or unit unreadable). The
    -- verdict needs >1 aura in play, so only in-combat runs are conclusive.
    addon:Print("|cff66ccffD. aura filters (harmful / player-dispellable / my-HoTs)|r")
    if BlizzardAPI and BlizzardAPI.CountAuras then
        for _, u in ipairs(HEALPROBE_UNITS) do
            local harm = BlizzardAPI.CountAuras(u, "HARMFUL")
            local disp = BlizzardAPI.CountAuras(u, "HARMFUL|RAID_PLAYER_DISPELLABLE")
            local mine = BlizzardAPI.CountAuras(u, "HELPFUL|PLAYER")
            local warn = (harm and disp and harm > 1 and disp == harm)
                and "  |cffff6600token may be ignored (narrowed==base)|r" or ""
            addon:Print(string.format("  %-7s harmful=%s dispellable=%s myhots=%s%s",
                u, tostring(harm), tostring(disp), tostring(mine), warn))
        end
        addon:Print("|cff888888  cast a HoT on a member and re-run: their myhots must move 0->1|r")
    else
        addon:Print("  |cffff6666BlizzardAPI unavailable|r")
    end

    -- E. What Assisted Combat feeds this spec (works even while spec-disabled -
    -- these are direct API reads, not the queue).
    addon:Print("|cff66ccffE. Assisted Combat on this spec|r")
    local AC = C_AssistedCombat
    if AC then
        local okA, avail, reason = pcall(AC.IsAvailable)
        addon:Print(string.format("  IsAvailable=%s reason=%s",
            okA and tostring(avail) or "ERR", okA and tostring(reason) or "-"))
        local okN, pick = pcall(AC.GetNextCastSpell, false)
        local pickName = okN and pick and C_Spell.GetSpellName and C_Spell.GetSpellName(pick)
        local pickTag = ""
        if okN and pick and SpellDB and SpellDB.IsHealingSpell then
            pickTag = SpellDB.IsHealingSpell(pick) and " |cff2ecc71[heal]|r" or " [dps]"
        end
        addon:Print(string.format("  next=%s %s%s", tostring(okN and pick or "ERR"),
            tostring(pickName or ""), pickTag))
        local okR, rot = pcall(AC.GetRotationSpells)
        if okR and type(rot) == "table" then
            addon:Print(string.format("  rotation pool: %d spells%s", #rot,
                #rot == 0 and " (some specs return empty OOC)" or ""))
            for i = 1, math.min(#rot, 12) do
                local id = rot[i]
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local tag = (SpellDB and SpellDB.IsHealingSpell and SpellDB.IsHealingSpell(id))
                    and "|cff2ecc71heal|r" or "dps"
                addon:Print(string.format("    %2d. %7d %-24s %s", i, id, tostring(nm), tag))
            end
        else
            addon:Print("  rotation pool: unavailable")
        end
    else
        addon:Print("  |cffff6666C_AssistedCombat unavailable|r")
    end
    addon:Print("|cff888888Also: `healprobe show` = live swatches, `healprobe arm` = cast/aura capture.|r")
end

--- /jac inspect ccdb [clear] - what the addon has learned about CC-immune mob types, and
--- the escape hatch. The table only ever grows on the engine's own "Immune" announcement,
--- so a wrong entry should be rare - but it survives sessions, so it must be inspectable.
function DebugCommands.CCImmunityDB(addon, arg)
    local B = LibStub("JustAC-BlizzardAPI", true)
    if not (B and B.GetCCImmunityDBInfo) then return end
    if arg == "clear" then
        B.ClearCCImmunityDB()
        addon:Print("|cff00ccff== ccdb ==|r cleared.")
        return
    end
    local count, targetNPC, sightings, threshold, byName = B.GetCCImmunityDBInfo()
    addon:Print(string.format("|cff00ccff== ccdb ==|r %d mob type(s) confirmed CC-immune "
        .. "(%d sighting(s) to confirm).", count, threshold))
    if targetNPC then
        addon:Print(string.format("  current target npcID=%d sightings=%s%s",
            targetNPC, tostring(sightings or 0),
            byName and " |cff888888(recovered by name - lookups only, never recorded)|r" or ""))
    else
        addon:Print("  current target npcID unknown (GUID is secret in combat, and no name "
            .. "match yet - target this mob out of combat once to learn it).")
    end
    addon:Print("  signal on this target: "
        .. tostring(B.GetCCImmuneSignal and B.GetCCImmuneSignal()))
end

--- /jac inspect blank - why did the queue last go empty? Three branches can blank it and
--- the result looks identical, so SpellQueue records the branch at the moment of the flip.
--- Run it right after the icons vanish; the bar/form state captured alongside is what tells
--- an ordinary hide apart from an effect that swapped the action bar out from under you.
function DebugCommands.QueueBlankReport(addon)
    local SQ = LibStub("JustAC-SpellQueue", true)
    local info = SQ and SQ.GetQueueBlankInfo and SQ.GetQueueBlankInfo()
    if not info then
        addon:Print("|cff00ccff== blank ==|r the queue has not gone empty since login.")
        return
    end
    addon:Print(string.format("|cff00ccff== blank ==|r %.1fs ago: |cffffff00%s|r",
        GetTime() - info.at, tostring(info.reason)))
    addon:Print(string.format("  combat=%s overrideBar=%s vehicleBar=%s possessBar=%s formID=%s",
        tostring(info.inCombat), tostring(info.override), tostring(info.vehicle),
        tostring(info.possess), tostring(info.formID)))
end

--- /jac inspect auraids - one-shot: is C_UnitAuras.GetUnitAuraInstanceIDs a plain,
--- countable, iterable list in combat? (Claim: yes.) Run OOC for baseline, then in
--- combat, then dungeon. GetUnitAuras - the batch call whose docs say the TABLE is
--- plain and only the fields are secret - is measured by `enginesig` instead.
function DebugCommands.AuraInstanceIdsProbe(addon)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then
        addon:Print("|cffff6600GetUnitAuraInstanceIDs unavailable|r")
        return
    end
    addon:Print(string.format("|cff00ccff== auraids ==|r combat=%s", tostring(UnitAffectingCombat("player"))))
    for _, unit in ipairs({ "player", "target" }) do
        if unit == "player" or UnitExists(unit) then
            for _, filter in ipairs({ "HELPFUL", "HARMFUL", "HARMFUL|CROWD_CONTROL" }) do
                local ok, t = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
                if not ok then
                    addon:Print(string.format("  %s %s: |cffff6600THREW|r", unit, filter))
                elseif t == nil then
                    addon:Print(string.format("  %s %s: nil", unit, filter))
                else
                    local cnt = ClassifyRead(function() return #t end)
                    local first = ClassifyRead(function() return t[1] end)
                    addon:Print(string.format("  %s %s: count=%s first=%s", unit, filter, cnt, first))
                    if t[1] and C_UnitAuras.GetAuraDuration then
                        addon:Print("    dur[1]:HasSecretValues=" .. ClassifyRead(function()
                            local d = C_UnitAuras.GetAuraDuration(unit, t[1]); return d and d:HasSecretValues() end))
                    end
                end
            end
        end
    end
    addon:Print("|cff888888Goal: count/first read plain in combat -> plain aura counts for gates.|r")
end

--- /jac inspect cdfields - one-shot: the NeverSecret fields inside otherwise-secret
--- cooldown structs (maxCharges, charge isActive, isEnabled, isOnGCD) plus
--- IsSpellOverlayed proc boolean and GetSpellCastCount. Run OOC, then in combat.
function DebugCommands.CooldownFieldsProbe(addon)
    local ids = RotationIds(8)
    if #ids == 0 then
        addon:Print("no rotation spells - use a spec with a rotation")
        return
    end
    addon:Print(string.format("|cff00ccff== cdfields ==|r combat=%s", tostring(UnitAffectingCombat("player"))))
    addon:Print("|cff888888isOnGCD is only trustworthy inside SPELL_UPDATE_COOLDOWN - treat as indicative here.|r")
    for _, id in ipairs(ids) do
        local nmS = (C_Spell.GetSpellName and C_Spell.GetSpellName(id) or "?") .. "(" .. id .. ")"
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
        addon:Print("  " .. nmS)
        if ch then
            addon:Print(string.format("    charges: maxCharges=%s isActive=%s",
                ClassifyRead(function() return ch.maxCharges end),
                ClassifyRead(function() return ch.isActive end)))
        end
        if cd then
            addon:Print(string.format("    cooldown: isEnabled=%s isOnGCD=%s",
                ClassifyRead(function() return cd.isEnabled end),
                ClassifyRead(function() return cd.isOnGCD end)))
        end
        if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
            addon:Print("    overlayed=" .. ClassifyRead(function() return C_SpellActivationOverlay.IsSpellOverlayed(id) end))
        end
        if C_Spell.GetSpellCastCount then
            addon:Print("    castCount=" .. ClassifyRead(function() return C_Spell.GetSpellCastCount(id) end))
        end
    end
end

--- /jac inspect secrecymap - one-shot, OOC: per-spell SecrecyLevel from C_Secrets
--- (NeverSecret=0 / AlwaysSecret=1 / ContextuallySecret=2). The predicate docs say
--- individual spells/power types may be flagged NeverSecret, overriding combat
--- restrictions - any hit gets a plain fast path forever. Dumps exceptions only.
function DebugCommands.SecrecyMapProbe(addon)
    if not (C_Secrets and C_Secrets.GetSpellCooldownSecrecy) then
        addon:Print("|cffff6600C_Secrets.GetSpell*Secrecy unavailable|r")
        return
    end
    local counts, exceptions, total = { [0] = 0, [1] = 0, [2] = 0 }, {}, 0
    local seen = {}
    local function probeSpell(id)
        if not id or seen[id] then return end
        seen[id] = true
        total = total + 1
        local levels = {}
        for tag, fn in pairs({ cd = C_Secrets.GetSpellCooldownSecrecy,
                               aura = C_Secrets.GetSpellAuraSecrecy,
                               cast = C_Secrets.GetSpellCastSecrecy }) do
            local ok, lv = pcall(fn, id)
            if ok and type(lv) == "number" then
                counts[lv] = (counts[lv] or 0) + 1
                if lv ~= 2 then levels[#levels + 1] = tag .. "=" .. lv end
            end
        end
        if #levels > 0 then
            exceptions[#exceptions + 1] = string.format("%s(%d): %s",
                C_Spell.GetSpellName and C_Spell.GetSpellName(id) or "?", id, table.concat(levels, " "))
        end
    end
    -- Spellbook sweep (player bank) + rotation list.
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum.SpellBookSpellBank then
        for i = 1, 400 do
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Player)
            if not ok or not info then break end
            probeSpell(info.spellID)
        end
    end
    for _, id in ipairs(RotationIds(20)) do probeSpell(id) end
    addon:Print(string.format("|cff00ccff== secrecymap ==|r %d spells: Never=%d Always=%d Contextual=%d",
        total, counts[0] or 0, counts[1] or 0, counts[2] or 0))
    if #exceptions == 0 then
        addon:Print("  no per-spell exemptions found (everything ContextuallySecret)")
    else
        for i = 1, math.min(#exceptions, 30) do addon:Print("  " .. exceptions[i]) end
        if #exceptions > 30 then addon:Print(string.format("  ...and %d more", #exceptions - 30)) end
    end
    -- Power types 0..29.
    if C_Secrets.GetPowerTypeSecrecy then
        local pt = {}
        for p = 0, 29 do
            local ok, lv = pcall(C_Secrets.GetPowerTypeSecrecy, p)
            if ok and type(lv) == "number" and lv ~= 2 then pt[#pt + 1] = p .. "=" .. lv end
        end
        addon:Print("  power-type exemptions: " .. (#pt > 0 and table.concat(pt, " ") or "none"))
    end
end

--- /jac inspect frames - one-shot triples for the laundered frame-state booleans
--- found at 68887 (control-flow Show/Hide -> plain IsShown). Run while: hurt <35%,
--- resource capped, absorb up, in a party with a hurt member. Spam it as state
--- changes; every read is guarded. MUST be re-run with a unit-frame replacement
--- addon enabled before any feature ships on these (frozen-frame precedent).
function DebugCommands.FrameStateProbe(addon)
    local walk = FramePath
    local report = ProbeReport(addon)
    addon:Print(string.format("|cff00ccff== frames ==|r combat=%s", tostring(UnitAffectingCombat("player"))))

    report("LowHealthFrame:IsShown (<=35% hp)", function() return LowHealthFrame and LowHealthFrame:IsShown() end)
    report("cvar doNotFlashLowHealthWarning", function() return GetCVarBool("doNotFlashLowHealthWarning") end)

    local main = { "PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain" }
    report("AnimatedLoss:IsShown (dmg<0.25s & no absorb)", function()
        local f = walk(main[1], main[2], main[3], "HealthBarsContainer", "PlayerFrameHealthBarAnimatedLoss")
        return f and f:IsShown()
    end)
    report("HealAbsorbBar:IsShown", function()
        local f = walk(main[1], main[2], main[3], "HealthBarsContainer", "HealthBar", "HealAbsorbBar")
        return f and f:IsShown()
    end)
    local function manaChild(...)
        return walk(main[1], main[2], main[3], "ManaBarArea", "ManaBar", ...)
    end
    report("FullPowerFrame.active", function() local f = manaChild("FullPowerFrame") return f and f.active end)
    report("FullPowerFrame pulse (capped)", function()
        local f = manaChild("FullPowerFrame", "PulseFrame", "PulseAnim") return f and f:IsPlaying()
    end)
    report("FullPowerFrame:GetAlpha", function() local f = manaChild("FullPowerFrame") return f and f:GetAlpha() end)
    report("FeedbackFrame gain glow (>10% gain)", function()
        local t = manaChild("FeedbackFrame", "GainGlowTexture") return t and t:IsShown()
    end)
    report("FeedbackFrame loss glow (>10% spend)", function()
        local t = manaChild("FeedbackFrame", "LossGlowTexture") return t and t:IsShown()
    end)
    report("cvar showBuilderFeedback", function() return GetCVarBool("showBuilderFeedback") end)
    report("cvar showSpenderFeedback", function() return GetCVarBool("showSpenderFeedback") end)

    if IsInGroup() then
        for i = 1, 4 do
            local pf = walk("PartyFrame", "MemberFrame" .. i)
            if pf and pf:IsShown() then
                report("Party" .. i .. " portrait rgb (red=(1,0,0) -> <=20%)", function()
                    local r, g, b = pf.Portrait:GetVertexColor()
                    return string.format("%.2f,%.2f,%.2f", r, g, b)
                end)
            end
        end
    else
        addon:Print("  |cff888888party portrait probes skipped (not in a group)|r")
    end

    -- 2026-07-24 secrecymap found power types 4,5,7,9,12,16,19 (combo points, runes,
    -- shards, holy power, chi, arcane charges, essence) flagged NeverSecret. If a
    -- direct UnitPower read on those is truly plain in combat, it supersedes the
    -- whole point-widget frame reader. Only types the class actually has print.
    if UnitPower and UnitHasPowerType then
        for _, pt in ipairs({ 4, 5, 7, 9, 12, 16, 19 }) do
            local okH, has = pcall(UnitHasPowerType, "player", pt)
            if okH and has == true then
                report("UnitPower(player," .. pt .. ") [NeverSecret-flagged discrete]",
                    function() return UnitPower("player", pt) end)
            end
        end
        -- Slows post-mortem (15:22 session: slows provably NOT in LoC data): the only
        -- conceivable in-combat speed signal left is position-delta dead reckoning.
        -- Record UnitPosition's per-context behavior (known nil in instances; secrecy
        -- in combat unmeasured) so that route can be judged before building anything.
        report("UnitPosition(player) [slow-detect dead-reckoning feasibility]", function()
            local y, x = UnitPosition("player")
            if y == nil then return "nil (instanced?)" end
            return string.format("%.1f,%.1f", y, x)
        end)
        -- LoC lockout counterfactual: validated TRUE during a stun (14:5x session);
        -- this samples the not-CC'd baseline so we know it reads false when free.
        report("LoC count / lockout[rot1].isActive (expect 0/false when free)", function()
            local n = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount
                and C_LossOfControl.GetActiveLossOfControlDataCount() or "?"
            local ids = RotationIds(1)
            local li = ids[1] and C_Spell.GetSpellLossOfControlCooldownInfo
                and C_Spell.GetSpellLossOfControlCooldownInfo(ids[1])
            return tostring(n) .. " / " .. tostring(li and li.isActive)
        end)
        -- Cross-check vs the shipped reader (direct fast path where wired, point
        -- widgets otherwise - notably DK, where UnitPower read a constant 6 in
        -- combat 2026-07-24, i.e. total runes not ready runes).
        report("GetClassResourcePoints (shipped reader)", function()
            local BAPI = LibStub("JustAC-BlizzardAPI", true)
            if not (BAPI and BAPI.GetClassResourcePoints) then return nil end
            local c, m, r = BAPI.GetClassResourcePoints()
            if c == nil then return "unknown" end
            return string.format("%s/%s %s", tostring(c), tostring(m), tostring(r))
        end)
    end
end

--- /jac inspect cvitems - one-shot over Cooldown Manager viewer items: the
--- laundered per-spell booleans (CooldownFlash:IsShown = on real non-GCD CD,
--- isActive = tracked buff up, PandemicIcon = engine pandemic window on target
--- debuffs). Requires the Cooldown Manager enabled in Edit Mode.
function DebugCommands.CooldownViewerItemsProbe(addon)
    -- Buff viewers FIRST: their isActive/PandemicIcon are the interesting bits, and
    -- the 2026-07-24 session showed Essential/Utility items exhausting the cap
    -- (their isActive just means "spell known/tracked", always true).
    local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer",
                      "EssentialCooldownViewer", "UtilityCooldownViewer" }
    addon:Print(string.format("|cff00ccff== cvitems ==|r combat=%s", tostring(UnitAffectingCombat("player"))))
    local any, printed = false, 0
    for _, vName in ipairs(VIEWERS) do
        local v = _G[vName]
        local pool = v and v.itemFramePool
        if pool and pool.EnumerateActive then
            local shown = v:IsShown()
            addon:Print(string.format("  %s shown=%s", vName, tostring(shown)))
            for item in pool:EnumerateActive() do
                local ok, cdID = pcall(function() return item:GetCooldownID() end)
                if ok and cdID and printed < 20 then
                    any = true
                    printed = printed + 1
                    local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                        and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    local sid = info and info.spellID
                    local nmS = sid and (C_Spell.GetSpellName(sid) or "?") .. "(" .. sid .. ")" or "cd" .. cdID
                    addon:Print(string.format("    %s flash=%s isActive=%s pandemic=%s", nmS,
                        ClassifyRead(function() return item.CooldownFlash and item.CooldownFlash:IsShown() end),
                        ClassifyRead(function() return item.isActive end),
                        ClassifyRead(function() return item.PandemicIcon and item.PandemicIcon:IsShown() end)))
                end
            end
        end
    end
    if not any then
        addon:Print("  |cffff6600no active viewer items - enable the Cooldown Manager in Edit Mode|r")
    elseif printed >= 20 then
        addon:Print("  |cff888888(truncated at 20 items)|r")
    end
end

--- /jac inspect enginesig - one-shot over four engine-side signals the addon does
--- not use yet. Each is cheap to adopt IF it measures the way the docs read, and
--- each is worthless if it does not, so they get measured before anything is built:
---
---  1. C_UnitAuras.GetUnitAuras(unit, filter) - the BATCH aura call. Docs mark the
---     return ConditionalSecretContents, i.e. the table (and #length) plain with only
---     the FIELDS secret. If so it replaces the 40x GetAuraDataByIndex index loops in
---     RedundancyFilter/PrecombatEngine/StateHelpers, and #auras under a category
---     filter becomes a plain, branchable count ("target has a big defensive up").
---  2. C_Spell.IsSpellImportant / IsSpellCrowdControl / C_UnitAuras.AuraIsBigDefensive
---     - engine spell classifiers, all SecretArguments=AllowedWhenTainted, so they
---     accept a SECRET spellID. IsSpellImportant is Blizzard's own "lethal if not
---     interrupted" flag - exactly what interrupt ranking wants and cannot get from a
---     secret cast id. Probed with both a plain id and a secret one.
---  3. PlayerIsSpellTarget(unit) - "this unit's cast is aimed at the player".
---     SecretReturns=true unconditionally, so display-sink only (SetAlphaFromBoolean),
---     never a gate. Confirm it does not throw and is genuinely secret.
---  4. CreateUnitHealPredictionCalculator - a secret-aware arithmetic object. Its
---     `clamped` second returns are ENGINE-COMPUTED comparisons between two secret
---     numbers (absorb vs missing health, heal-absorb vs current health), which we
---     cannot derive ourselves at any price. Secret booleans, so display-only.
---
--- Run OOC for a baseline, then in combat, ideally targeting something with a
--- defensive up and something crowd-controlled.
function DebugCommands.EngineSignalsProbe(addon)
    local report = ProbeReport(addon)
    addon:Print(string.format("|cff00ccff== enginesig ==|r combat=%s",
        tostring(UnitAffectingCombat("player"))))

    -- 1. Batch aura call. The count is the whole point: a plain # under a narrow
    -- filter is a gate we can branch on with zero secret reads.
    local UA = C_UnitAuras
    if not (UA and UA.GetUnitAuras) then
        addon:Print("  |cffff6600GetUnitAuras unavailable|r")
    else
        local FILTERS = { "HELPFUL", "HARMFUL", "HELPFUL|BIG_DEFENSIVE",
                          "HELPFUL|EXTERNAL_DEFENSIVE", "HARMFUL|CROWD_CONTROL",
        -- Control row. 2026-07-25 run: every category filter returned 0 on both
        -- units in every sample, which is ambiguous - either nothing matched, or
        -- the token is unrecognised and the engine silently returns an empty list.
        -- A deliberately bogus token settles it: if this returns the same count as
        -- plain HELPFUL, extra tokens are being IGNORED and every 0 above is
        -- meaningless; if it returns 0, tokens really are parsed and the 0s are real.
                          "HELPFUL|JAC_NOT_A_REAL_TOKEN" }
        for _, unit in ipairs({ "player", "target" }) do
            if unit == "player" or UnitExists(unit) then
                for _, filter in ipairs(FILTERS) do
                    local ok, t = pcall(UA.GetUnitAuras, unit, filter)
                    if not ok then
                        addon:Print(string.format("  getUnitAuras %s %s: |cffff6600THREW|r", unit, filter))
                    elseif type(t) ~= "table" then
                        addon:Print(string.format("  getUnitAuras %s %s: %s", unit, filter, tostring(t)))
                    else
                        addon:Print(string.format("  getUnitAuras %s %s: count=%s spellId[1]=%s",
                            unit, filter,
                            ClassifyRead(function() return #t end),
                            ClassifyRead(function() return t[1] and t[1].spellId end)))
                    end
                end
            end
        end
    end

    -- 1b. The shipped helpers built on the above. This is the check on the
    -- ignored-token guard in CountAuras: if a category token ever stops being
    -- honoured, CountAuras must return nil (not a full-set count) and
    -- HasBigDefensive must go nil rather than silently reading true forever.
    -- Cross-read against the raw count so a divergence is visible in one line.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.CountAuras then
        addon:Print(string.format("  shipped: GetAuras#=%s CountAuras(BIG_DEFENSIVE)=%s HasBigDefensive=%s",
            ClassifyRead(function()
                local l = BAPI.GetAuras("player", "HELPFUL") return l and #l end),
            ClassifyRead(function() return BAPI.CountAuras("player", "HELPFUL|BIG_DEFENSIVE") end),
            ClassifyRead(function() return BAPI.HasBigDefensive("player") end)))
        addon:Print("  |cff888888(CountAuras nil + HasBigDefensive nil = the ignored-token guard tripped)|r")
    end

    -- 2. Classifiers, each against a KNOWN-YES / KNOWN-NO pair rather than whatever
    -- the rotation happens to hand over. The 2026-07-25 run fed IsSpellCrowdControl
    -- the first rotation id - Cat Form(768) - and got `true`, which is either a
    -- broken classifier or a semantic we have guessed wrong; with one uncalibrated
    -- sample there is no way to tell. A pair answers it: yes+no = the classifier
    -- works and we can trust it; yes+yes (or no+no) = it does not mean what the
    -- name says and nothing may be built on it. Ids are hardcoded on purpose - they
    -- need not be known by the player, only to exist.
    local CLASSIFIERS = {
        { "IsSpellImportant", C_Spell and C_Spell.IsSpellImportant,
          -- No universally-castable "lethal if not interrupted" spell exists to pin
          -- this against; a raid/dungeon boss cast is the real calibration. Pair is
          -- a floor check only: a plain damage spell must NOT read important.
          yes = { 118, "Polymorph" }, no = { 8921, "Moonfire" } },
        { "IsSpellCrowdControl", C_Spell and C_Spell.IsSpellCrowdControl,
          yes = { 118, "Polymorph" }, no = { 8921, "Moonfire" } },
        { "AuraIsBigDefensive", UA and UA.AuraIsBigDefensive,
          yes = { 871, "Shield Wall" }, no = { 8921, "Moonfire" } },
    }
    local secretID = nil
    if UA and UA.GetAuraDataByIndex then
        local okA, d = pcall(UA.GetAuraDataByIndex, "target", 1, "HARMFUL")
        if okA and d then secretID = d.spellId end
    end
    for _, c in ipairs(CLASSIFIERS) do
        local name, fn = c[1], c[2]
        if not fn then
            addon:Print("  |cffff6600" .. name .. " unavailable|r")
        else
            for _, leg in ipairs({ "yes", "no" }) do
                local id, label = c[leg][1], c[leg][2]
                report(string.format("%s(%d %s) [expect %s]", name, id, label, leg:upper()),
                    function() return fn(id) end)
            end
            if secretID ~= nil then
                report(name .. "(target aura id) [secret id]", function() return fn(secretID) end)
            end
        end
    end
    if secretID == nil then
        addon:Print("  |cff888888secret-id leg skipped (no target debuff) - re-run on a debuffed target in combat|r")
    end

    -- 3. Cast-on-me. Only meaningful while the target is mid-cast; nil otherwise is
    -- not evidence, so the label says which read it was.
    if PlayerIsSpellTarget then
        local casting = UnitExists("target")
            and (UnitCastingInfo("target") ~= nil or UnitChannelInfo("target") ~= nil)
        report(string.format("PlayerIsSpellTarget(target) [target casting=%s]", tostring(casting)),
            function() return PlayerIsSpellTarget("target") end)
    else
        addon:Print("  |cffff6600PlayerIsSpellTarget unavailable|r")
    end

    -- 4. Heal-prediction calculator. HasSecretValues is documented ReturnsNeverSecret,
    -- so it is the one plain read here and tells us whether the engine actually
    -- populated the object with secrets - without it, a plain `clamped` would be
    -- ambiguous (genuinely unrestricted, or silently never filled?).
    if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
        addon:Print("  |cffff6600UnitHealPredictionCalculator unavailable|r")
    else
        local calc = DebugCommands._healPredCalc
        if not calc then
            local okC
            okC, calc = pcall(function()
                local c = CreateUnitHealPredictionCalculator()
                -- MissingHealth is the mode that makes `clamped` mean "the absorb
                -- exceeds the health actually missing" - the comparison of two secret
                -- numbers we have no other way to obtain.
                c:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
                return c
            end)
            if not okC then
                addon:Print("  |cffff6600healPred setup failed:|r " .. tostring(calc):sub(1, 60))
                return
            end
            DebugCommands._healPredCalc = calc
        end
        for _, unit in ipairs({ "player", "target" }) do
            if unit == "player" or UnitExists(unit) then
                local okP = pcall(UnitGetDetailedHealPrediction, unit, nil, calc)
                if not okP then
                    addon:Print(string.format("  healPred %s: |cffff6600THREW|r", unit))
                else
                    addon:Print(string.format("  healPred %s: hasSecrets=%s absorbClamped=%s healAbsorbClamped=%s incomingClamped=%s",
                        unit,
                        ClassifyRead(function() return calc:HasSecretValues() end),
                        ClassifyRead(function() local _, c = calc:GetDamageAbsorbs() return c end),
                        ClassifyRead(function() local _, c = calc:GetHealAbsorbs() return c end),
                        ClassifyRead(function() local _, _, _, c = calc:GetIncomingHeals() return c end)))
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- /jac inspect audit [off|clear] - the whole Session-1 battery, hands-free.
-- Arm it once, then just fight: it snapshots every probe OOC (baseline), on
-- every combat enter, 10s into combat, and on combat exit. Output goes to
-- SavedVariables (JustACGlobal.probeLog), color codes stripped, so after
-- '/jac inspect audit off' + /reload the full transcript is readable directly
-- from WTF/.../SavedVariables/JustAC.lua. Also arms locwatch + selfcast with
-- their output redirected into the same log.
--------------------------------------------------------------------------------
local PROBE_LOG_MAX = 8000

local function ProbeLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.probeLog = g.probeLog or {}
    return g.probeLog
end

local function ProbeLogEmit(msg)
    local log = ProbeLogStore()
    log[#log + 1] = tostring(msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if #log > PROBE_LOG_MAX then
        local keep, half = {}, math.floor(PROBE_LOG_MAX / 2)
        for i = #log - half + 1, #log do keep[#keep + 1] = log[i] end
        _G.JustACGlobal.probeLog = keep
    end
end

--- Proxy addon whose Print goes to the log instead of chat; everything else
--- falls through to the real addon (db, methods).
local function LogProxy(addon)
    return setmetatable({ Print = function(_, msg) ProbeLogEmit(msg) end }, { __index = addon })
end

--------------------------------------------------------------------------------
-- /jac inspect enragelog [off|clear] - does the enrage signal actually fire in combat?
--
-- The colour-sink the feature uses is UNVERIFIABLE by construction: we hand a secret
-- alpha straight to SetAlpha and never read it, and GetAlpha is secret-aspect
-- protected, so there is no way to log "did it light up". The swatch in
-- '/jac inspect enrage' is eyes-only, which cannot prove reliability over a fight.
--
-- So this measures a DIFFERENT, readable signal and correlates it with the cue:
--   HELPFUL|RAID_PLAYER_DISPELLABLE = "auras with a dispel type the player can dispel"
--   (AuraUtil.AuraFilters). On a HOSTILE target for a soothe class that should mean
--   enrage specifically, and an aura COUNT is plain even in combat.
-- If that holds, it is a branchable enrage boolean and strictly better than the sink.
--
-- FAIL-OPEN GUARD, mandatory: an unrecognised filter token returns the UNFILTERED set
-- rather than erroring (measured - see the JAC_NOT_A_REAL_TOKEN line in enginesig).
-- A narrowed count that equals its base count is therefore "token ignored", NOT "every
-- aura is dispellable" - without this check the probe would confidently report an
-- enrage on every target that has any buff at all.
--
-- Change-only sampling: a whole fight collapses to a handful of transitions.
--------------------------------------------------------------------------------
--- Call GetUnitAuras RAW so a THROW is distinguishable from an empty result.
--- BlizzardAPI.GetAuras deliberately swallows that difference (it pcalls, then falls back to
--- the by-index loop, which also throws in combat, yielding {}). For production that is the
--- right fail-safe; for this question it is fatal - "the target has no buffs" and "the API
--- refused us" both render as 0, and only one of them means the route is dead.
local function RawAuraCount(filter)
    local fn = C_UnitAuras and C_UnitAuras.GetUnitAuras
    if not fn then return nil, "no API" end
    local ok, list = pcall(fn, "target", filter)
    if not ok then return nil, "THREW" end
    if type(list) ~= "table" then return nil, "not a table" end
    return #list, nil, list
end

local function EnrageSample()
    if not UnitExists("target") then return nil end
    local nb, berr, base = RawAuraCount("HELPFUL")
    local nd, derr = RawAuraCount("HELPFUL|RAID_PLAYER_DISPELLABLE")
    -- Token honoured only if it actually narrowed something at least once. Needs nb > 1:
    -- with a single aura present, a fail-open token is indistinguishable from a real answer.
    local ignored = (nb and nd and nb > 1 and nd == nb)
    return nb, nd, ignored, base, berr, derr
end

--- Per-aura dispel-type decode for the log. Uses the IDENTITY curve (r = type/32), so a
--- readable context yields the raw type number and 9 == Enrage. In combat this reads SECRET,
--- which is itself the answer to "can we ever branch on this" - no.
--- Kept separate from the counts so a decode failure cannot break the sampling line.
local identCurve
local function DecodeDispelTypes(auras)
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local gadtc = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and gadtc and stepType and CreateColor and auras) then return "" end
    if not identCurve then
        identCurve = cu.CreateColorCurve()
        identCurve:SetType(stepType)
        for k = 0, 15 do identCurve:AddPoint(k, CreateColor(k / 32, 0, 0, 1)) end
    end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local out = {}
    for i = 1, #auras do
        local id = auras[i].auraInstanceID
        local part = "?"
        local c
        if pcall(function() c = gadtc("target", id, identCurve) end) and c then
            if BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(c.r) then
                part = "SECRET"
            else
                local t = math.floor((c.r or 0) * 32 + 0.5)
                part = tostring(t) .. (t == 9 and "<ENRAGE>" or "")
            end
        end
        out[#out + 1] = tostring(id) .. ":" .. part
    end
    return " types=[" .. table.concat(out, " ") .. "]"
end

--------------------------------------------------------------------------------
--- \jac inspect auradump - every aura on the target, every field, every filter.
---
--- Written because guessing which filter or field surfaces an enrage was costing runs.
--- Do not infer the shape of the data: enumerate it. The player can confirm the enrage by
--- NAME in game ("Seeing Red" on the test mob), so a dump that shows which fields read plain
--- and which filters include that aura answers in one pull what a targeted probe kept
--- failing to settle - including the case where the aura is present but every field is
--- secret, which is a different answer from "no aura".
---
--- Every read is classified plain / secret / err individually: a secret field is EVIDENCE
--- (the aura exists, we just cannot read that attribute), while a throw means the call
--- itself was refused. Collapsing those two is what made the earlier probe inconclusive.
--------------------------------------------------------------------------------
local AURA_FILTERS = {
    "HELPFUL",
    "HELPFUL|RAID_PLAYER_DISPELLABLE",
    "HELPFUL|DISPELLABLE",
    "HELPFUL|IMPORTANT",
    "HELPFUL|BIG_DEFENSIVE",
    "HELPFUL|CROWD_CONTROL",
    "HELPFUL|CANCELABLE",
    "HELPFUL|!CANCELABLE",
    "HARMFUL",
}

function DebugCommands.AuraDumpProbe(addon)
    local unit = UnitExists("target") and "target" or "player"
    addon:Print(string.format("== aura dump == unit=%s (%s)  combat=%s",
        unit, tostring(UnitName(unit)), tostring(UnitAffectingCombat("player"))))

    -- 1. Filter sweep. A token the engine does not recognise is IGNORED, returning the
    --    unfiltered set - so a count equal to the HELPFUL baseline means "token ignored",
    --    not "everything matched". IsValidFilterString (12.1.0) answers that directly
    --    instead of inferring it from counts.
    local valid = AuraUtil and AuraUtil.IsValidFilterString
    local fn = C_UnitAuras and C_UnitAuras.GetUnitAuras
    if not fn then addon:Print("  |cffff0000GetUnitAuras missing|r"); return end
    local baseline
    for i = 1, #AURA_FILTERS do
        local f = AURA_FILTERS[i]
        local vOK, vWhy = true, nil
        if valid then vOK, vWhy = valid(f) end
        local ok, list = pcall(fn, unit, f)
        local n = (ok and type(list) == "table") and #list or nil
        if f == "HELPFUL" then baseline = n end
        local note = ""
        if not vOK then note = " |cffff6600INVALID TOKEN|r " .. tostring(vWhy)
        elseif not ok then note = " |cffff6600THREW|r"
        elseif n and baseline and f ~= "HELPFUL" and n == baseline and baseline > 0 then
            note = " |cffffff00(== HELPFUL, token may be ignored)|r"
        end
        -- Escape the pipes: the chat frame eats "|R" as a colour reset and "|C" as the start
        -- of a colour code, so RAID_PLAYER_DISPELLABLE / CROWD_CONTROL / CANCELABLE printed
        -- as mangled labels and made the sweep unreadable.
        addon:Print(string.format("  %-34s n=%s%s", (f:gsub("|", "||")), tostring(n), note))
    end

    -- 2. Full field dump per aura. pairs() rather than a known-field list: the point is to
    --    find what we did NOT think to ask for.
    -- The border walk reads Blizzard's OWN frames and does not touch GetUnitAuras, so it must
    -- run even when the enumeration above is refused - that is precisely the case where it is
    -- the only thing left that can answer. It was previously called after the field dump and
    -- got skipped by the early returns, i.e. it never ran when it mattered.
    local ok, list = pcall(fn, unit, "HELPFUL")
    if not ok then
        addon:Print("  |cffff6600HELPFUL enumeration threw|r - GetUnitAuras is refused for a")
        addon:Print("  tainted caller here, so no filter token is usable. Re-run OUT of combat:")
        addon:Print("  if it answers there, the denial is combat-gated and the tokens are still")
        addon:Print("  worth having for the pre-combat systems.")
        DebugCommands.DumpTargetAuraBorders(addon)
        return
    end
    if type(list) ~= "table" or #list == 0 then
        addon:Print("  |cff888888no helpful auras returned|r")
        DebugCommands.DumpTargetAuraBorders(addon)
        return
    end
    for i = 1, #list do
        local a = list[i]
        addon:Print(string.format("  |cff00ccff[%d]|r", i))
        local keys = {}
        local okP = pcall(function() for k in pairs(a) do keys[#keys + 1] = tostring(k) end end)
        if not okP then addon:Print("      |cffff6600pairs() refused|r"); end
        table.sort(keys)
        for j = 1, #keys do
            local k = keys[j]
            local kind, text = ProbeRead(function() return a[k] end, 46)
            local colour = (kind == "plain" and "|cff2ecc71") or (kind == "secret" and "|cffffff00")
                or "|cffff6600"
            addon:Print(string.format("      %-30s %s%s|r", k, colour, text))
        end
    end
    addon:Print("|cff888888green=plain (branchable)  yellow=secret  orange=err/nil|r")
    DebugCommands.DumpTargetAuraBorders(addon)
end

--- The BORDERS Blizzard draws on the target's own buff buttons. Reported because a visible
--- glow means Blizzard's UNTAINTED code already made the judgement, and if it left the answer
--- as plain frame state we can read it - the laundering idiom this addon lives on.
---
--- Prediction on the source: TargetFrameBuffButtonPrivateMixin:ApplyAuraBorder does
--- `StealableBorder:SetShown(auraData.isStealable and ...)`, and SetShown(expr) does NOT
--- launder (unlike an if/else with Show()/Hide()), so IsShown() should read SECRET. Measuring
--- anyway: that prediction has been wrong twice today, and if it reads PLAIN this is a
--- branchable signal and strictly better than the container route.
---
--- Buttons are found by walking TargetFrame's descendants for a StealableBorder field rather
--- than by a hardcoded path - the pooling shape changed in 12.x and a wrong path would read
--- as "no borders" instead of "not found", which is the exact ambiguity that wasted runs today.
function DebugCommands.DumpTargetAuraBorders(addon)
    local tf = _G.TargetFrame
    if not tf then addon:Print("  |cff888888TargetFrame absent|r"); return end

    -- In 12.x the target's auras live in an <AuraContainer parentKey="Auras"> whose BUTTONS
    -- carry Enum.ScriptObjectAccessRestriction.DenyTaintedAccessWhenAurasAreSecret. So the
    -- container frame is reachable but its children may be refused to us in combat - a
    -- THROW here is the answer ("sealed"), not a failure to look. Report it rather than
    -- swallowing it, which is what made the first pass say "not found" and teach nothing.
    local denied = 0
    local found = 0
    local function walk(frame, depth)
        if depth > 8 or found >= 12 then return end
        local okK, kids = pcall(function() return { frame:GetChildren() } end)
        if not okK then
            denied = denied + 1
            if denied <= 3 then
                addon:Print(string.format("  |cffffff00GetChildren refused at depth %d|r: %s",
                    depth, tostring(kids):gsub("^.-:%d+: ", ""):sub(1, 70)))
            end
            return
        end
        for i = 1, #kids do
            local f = kids[i]
            local sb = f and rawget(f, "StealableBorder") or (f and f.StealableBorder)
            local db = f and f.DispelBorder
            if sb or db then
                found = found + 1
                local parts = {}
                if sb then
                    local k, t = ProbeRead(function() return sb:IsShown() end)
                    parts[#parts + 1] = "StealableBorder:IsShown=" ..
                        ((k == "plain") and ("|cff2ecc71" .. t .. "|r")
                          or (k == "secret") and "|cffffff00<secret>|r" or ("|cffff6600" .. t .. "|r"))
                end
                if db then
                    local k, t = ProbeRead(function() return db:IsShown() end)
                    parts[#parts + 1] = "DispelBorder:IsShown=" ..
                        ((k == "plain") and ("|cff2ecc71" .. t .. "|r")
                          or (k == "secret") and "|cffffff00<secret>|r" or ("|cffff6600" .. t .. "|r"))
                end
                local vis = select(2, ProbeRead(function() return f:IsShown() end))
                addon:Print(string.format("  aura button #%d shown=%s  %s",
                    found, vis, table.concat(parts, "  ")))
            end
            walk(f, depth + 1)
        end
    end
    addon:Print("== target aura button borders ==")
    -- Name the aura container explicitly before walking: if this resolves but yields no
    -- buttons, that separates "the container is gone" from "the container is sealed".
    local auras
    for _, path in ipairs({ "TargetFrameContent.TargetFrameContentMain.Auras",
                            "TargetFrameContent.TargetFrameContentContextual.Auras",
                            "Auras" }) do
        local obj = tf
        for part in path:gmatch("[^.]+") do
            obj = obj and rawget(obj, part) or (obj and obj[part])
            if obj == nil then break end
        end
        if obj then
            auras = obj
            addon:Print("  aura container found at TargetFrame." .. path
                .. "  shown=" .. select(2, ProbeRead(function() return obj:IsShown() end)))
            break
        end
    end
    if not auras then addon:Print("  |cffffff00aura container not found by name|r") end

    walk(tf, 1)
    if found == 0 then
        addon:Print("  |cff888888no StealableBorder/DispelBorder reachable|r"
            .. (denied > 0 and (" - " .. denied .. " access refusals (SEALED, not absent)")
                or " - and no access refusals, so they are genuinely not there"))
    end
end

--------------------------------------------------------------------------------
--- \jac inspect auracontainer - can we actually build one, and what is on it?
---
--- 12.1.0's Blizzard_AuraContainer is the ONLY remaining route to an enrage cue: its two XML
--- files are the only places in the entire UI source carrying allowUntaintedCreation="true",
--- which exists so an addon-created frame does NOT run in the addon's taint. That is the
--- exact problem that sank the private-CastingBarFrame attempt.
---
--- This probe exists because AuraContainer is a C-side INTRINSIC: its real method surface is
--- invisible in the Lua source, so the API shape cannot be read off disk (there is no SetUnit
--- in the mixins, yet a container must be pointed at a unit somehow). Rather than guess and
--- write a 300-line rewrite against an imagined API, create ONE and enumerate what it has.
---
--- Every step is reported separately: creation, mixin presence, and the method dump. A
--- failure at any step is the answer - if creation throws under our taint the whole route is
--- dead and the cue cannot come back at all.
--------------------------------------------------------------------------------
function DebugCommands.AuraContainerProbe(addon)
    addon:Print("== aura container probe ==")

    local okC, cont = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not okC or not cont then
        addon:Print("  |cffff0000CreateFrame failed|r: " .. tostring(cont))
        addon:Print("  |cffff6600Route closed - the enrage cue cannot be rebuilt this way.|r")
        return
    end
    addon:Print("  |cff2ecc71created|r AuraContainer from CustomAuraContainerTemplate")

    -- Method surface. Frame methods live on the metatable's __index, not the frame, so pairs()
    -- on the frame alone finds nothing. Both are walked: the template's Lua mixins land
    -- directly on the object, the intrinsic's C methods on the metatable.
    local seen, names = {}, {}
    local function collect(t, label)
        if type(t) ~= "table" then return end
        pcall(function()
            for k, v in pairs(t) do
                if type(v) == "function" and not seen[k] then
                    seen[k] = true
                    names[#names + 1] = tostring(k) .. label
                end
            end
        end)
    end
    collect(cont, "")
    local mt = getmetatable(cont)
    collect(mt and mt.__index, "*")

    table.sort(names)
    addon:Print(string.format("  %d methods (|cff888888* = from metatable|r):", #names))
    -- Chunked: one Print per method floods the frame and the useful ones scroll away.
    local line = "    "
    for i = 1, #names do
        line = line .. names[i] .. "  "
        if #line > 110 or i == #names then addon:Print(line); line = "    " end
    end

    -- The ones the rebuild would depend on. Absence here is the finding, not an error.
    addon:Print("  wanted:")
    for _, m in ipairs({ "AddAuraGroup", "AddAuraSlot", "HasAuraGroup", "SetUnit",
                         "GetAuraGroupFrame", "GetAuraGroupFrameCount",
                         "SetAuraGroupCandidateFilters", "SetAuraGroupLayout" }) do
        local has = seen[m] and "|cff2ecc71yes|r" or "|cffff6600NO|r"
        addon:Print(string.format("    %-30s %s", m, has))
    end

    -- Does a tainted AddAuraGroup call survive the inbound delegate? This is the real question:
    -- creation succeeding proves nothing if configuring it from our side is refused.
    -- END-TO-END: wire the real enrage curve to a real texture and leave it on screen.
    -- This is the only step that proves the CHAIN works rather than its pieces: curve ->
    -- Blizzard's untainted GetAuraDispelTypeColor -> vertex colour on a texture we own.
    -- A green square appears over the centre of the screen ONLY while the target has a
    -- dispel-type-9 aura. Layout is left at the container default deliberately - if the
    -- buttons spread out, that tells us the layout needs configuring, which is cheaper to
    -- learn here than inside a module rewrite.
    if seen.AddAuraGroup and seen.SetUnit then
        local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
        local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
        local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        if not (cu and cu.CreateColorCurve and step and style) then
            addon:Print("  |cffff6600curve/enum API missing - cannot wire the end-to-end test|r")
            return
        end
        local curve = cu.CreateColorCurve()
        curve:SetType(step)
        curve:AddPoint(0,  CreateColor(0, 0, 0, 0))
        curve:AddPoint(9,  CreateColor(0, 1, 0, 1))   -- Enrage: opaque green
        curve:AddPoint(10, CreateColor(0, 0, 0, 0))

        cont:SetSize(64, 64)
        cont:ClearAllPoints()
        cont:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        cont:SetFrameStrata("TOOLTIP")
        pcall(cont.EnableMouse, cont, false)
        local okU, uerr = pcall(cont.SetUnit, cont, "target")
        addon:Print("  SetUnit('target') -> " ..
            (okU and "|cff2ecc71ok|r" or ("|cffff6600" .. tostring(uerr):sub(1, 80) .. "|r")))

        local made = 0
        local okA, err = pcall(function()
            -- Filter the GROUP, not just the texture. Blizzard applies this filter internally,
            -- so the token we are refused when calling GetUnitAuras ourselves works here - and
            -- if it selects enrages, a button EXISTS only for an enrage. That matters
            -- architecturally: Blizzard shows a button for any aura matching the group
            -- (SetShown(secretwrap(auraData ~= nil))) and only AddDispelTypeTexture elements are
            -- dispel-gated, so a plain HELPFUL group can gate the icon but NOT the hotkey text
            -- or cooldown swipe. Group-level filtering gates the whole button, restoring the
            -- full cue instead of an icon-only one.
            cont:AddAuraGroup("jacEnrage", "HELPFUL|RAID_PLAYER_DISPELLABLE", {
                maxFrameCount = 8,
                initializeFrame = function(button)
                    made = made + 1
                    -- The pooled button has NO intrinsic size and the group layout options are
                    -- spacing-only, so a texture anchored with SetAllPoints on it renders at
                    -- zero pixels - invisible, and indistinguishable from "the curve did not
                    -- select". Size the button, and give the texture explicit dimensions too so
                    -- neither depends on the other.
                    pcall(button.SetSize, button, 48, 48)
                    local tex = button:CreateTexture(nil, "OVERLAY")
                    tex:SetSize(48, 48)
                    tex:SetPoint("CENTER", button, "CENTER", 0, 0)
                    tex:SetColorTexture(1, 1, 1, 1)   -- PreserveAsset keeps this white block
                    button:AddDispelTypeTexture(tex, {
                        showAlways = true,            -- enrage is NOT a dispelName; criteria would suppress it
                        style = style.PreserveAsset,
                        customDispelColorCurve = curve,
                    })
                end,
            })
        end)
        addon:Print("  AddAuraGroup + dispel curve -> " ..
            (okA and "|cff2ecc71accepted|r" or ("|cffff6600" .. tostring(err):sub(1, 90) .. "|r")))
        addon:Print(string.format("  initializeFrame ran for %d button(s)", made))
        if okA then
            cont:Show()
            -- Geometry readout: a zero-sized or off-screen button looks exactly like a curve
            -- that never fires. Report it so the next run cannot be ambiguous the same way.
            local okG, gf = pcall(cont.GetAuraGroupFrame, cont, "jacEnrage", 1)
            if okG and gf then
                addon:Print(string.format("  button#1 size=%s x %s  shown=%s  container=%s x %s",
                    select(2, ProbeRead(function() return math.floor(gf:GetWidth() or 0) end)),
                    select(2, ProbeRead(function() return math.floor(gf:GetHeight() or 0) end)),
                    select(2, ProbeRead(function() return gf:IsShown() end)),
                    tostring(math.floor(cont:GetWidth() or 0)),
                    tostring(math.floor(cont:GetHeight() or 0))))
            else
                addon:Print("  |cffffff00GetAuraGroupFrame refused/nil|r - buttons not inspectable")
            end
            addon:Print("  |cff2ecc71WATCH ABOVE YOUR CHARACTER|r: a GREEN block appears at centre-screen")
            addon:Print("  only while the target has an ENRAGE. Target the swine and let it enrage.")
            addon:Print("  |cff888888/reload clears it.|r")
            DebugCommands._auraContainerProbe = cont
            return
        end
    end
    pcall(function() cont:Hide() end)
end

--------------------------------------------------------------------------------
-- /jac inspect channels - the LAUNDERING MATRIX
--------------------------------------------------------------------------------
-- Every capability this addon has for reading combat state is a CHAIN, never a single
-- call: a secret goes into a C-side sink that accepts one, and we read back some other
-- property of the same object that the engine forgot to seal. The shipped readiness probe
-- is exactly that (secret duration -> Cooldown -> IsShown), and so is the enrage cue.
--
-- 12.1.0's generated API documentation says why a chain can exist at all, and it is not
-- luck. Secrecy on a widget is per-(OBJECT, ASPECT): a getter carries
-- `SecretReturnsForAspect = { Enum.SecretAspect.X }` and returns secret ONLY when aspect X
-- is stamped on that object. So a getter whose declared aspects omit the aspect your sink
-- stamped is an open channel, and the gaps are enumerable rather than guessable.
--
-- The clearest example, and the reason this probe exists: on a FontString, `GetText` is
-- guarded by `SecretAspect.Text`, while `GetStringWidth`, `IsTruncated`, `GetNumLines`,
-- `GetWrappedWidth` and `GetUnboundedStringWidth` are guarded by `SecretWhenAnchoringSecret`
-- instead. If that is literally true, a FontString holding SECRET text still answers
-- questions about the SHAPE of that text - which is a numeric readback of a secret, not
-- merely a boolean one, and the formatters that take curves (SecondsFormatter interval
-- bands, AbbreviatedNumberFormatter) turn magnitude into length on the way in.
--
-- READ THIS BEFORE TRUSTING AN ANNOTATION. `SecretWhen<X>` is a NECESSARY condition for
-- secrecy, NOT a complete specification: "secret when X" does not imply "plain when not X".
-- Proof, from our own shipped code: all five DurationObject Evaluate* methods carry ONLY
-- `SecretWhenCurveSecret`, and we always pass our own plain curve - yet the result is still
-- secret, which is exactly why BlizzardAPI.DurationBelow has to run it through the
-- IsSecretZero text gate to get a boolean out. An earlier draft of this probe predicted
-- those cells PLAIN on the strength of the annotation alone and would have shipped a green
-- row that meant nothing. The documentation says where to LOOK; only the client says what is.
--
-- So each cell carries what we currently BELIEVE from shipped code and past measurement -
-- never from an annotation alone - and contested cells are marked unknown and claim nothing.
-- Disagreements are the entire point, in both directions:
--   * believed secret, reads PLAIN -> a capability we are not using
--   * believed plain, reads SECRET or throws -> a latent crash, exactly the shape of the
--     two that bit us on 2026-08-12 (GetActionDisplayCount and GetAuraSpellInstanceID, both
--     believed plain because a hand-written comment said so).
-- The Cooldown row is a CONTROL: it is shipped and proven, so the day it stops reading
-- plain, this probe has caught a closure before the error reports do.
--
-- Scratch widgets are built fresh on every run and never reused. Aspects are permanent once
-- stamped, so a reused widget would report the previous run's contamination as this run's
-- result. The discarded frames are not reclaimed - acceptable for a debug command, and the
-- alternative silently poisons the measurement.
local CHANNEL_PREDICT_PLAIN  = "plain"
local CHANNEL_PREDICT_SECRET = "secret"
-- Genuinely contested: shipped code/measurement says one thing and the documentation says
-- another, and neither has been settled in game. These cells report and colour nothing -
-- guessing a side here is how a probe starts asserting the thing it was built to find out.
local CHANNEL_PREDICT_UNKNOWN = "unknown"

function DebugCommands.ChannelMatrix(addon)
    -- This file has NO file-local BlizzardAPI (see the other two notes saying so). A bare
    -- reference is a nil global, and indexing it throws INSIDE a probe cell - which then
    -- reports as "err" and reads exactly like a finding about the client. It did, on the
    -- first run: the zero-gate cell came back err and the cause was this line missing.
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("=== laundering matrix ===")

    -- A cell only means something if what we fed in was ACTUALLY secret. Establish that
    -- first and refuse to draw conclusions otherwise: out of combat every source reads
    -- plain, every readback reads plain, and the grid would look like a clean sweep of
    -- open channels while proving nothing at all.
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false
    local sources = {
        { label = "UnitHealth('player')", get = function() return UnitHealth("player") end },
        { label = "UnitPower('player')",  get = function() return UnitPower("player") end },
    }
    local secretNum, secretFrom
    for i = 1, #sources do
        local st, txt, val = ProbeRead(sources[i].get)
        addon:Print(string.format("source %-22s -> %s", sources[i].label,
            st == "secret" and "|cff2ecc71<secret>|r (usable)" or (txt or st)))
        if st == "secret" and not secretNum then secretNum, secretFrom = val, sources[i].label end
    end
    if not secretNum then
        addon:Print("|cffff6600No secret source available|r - nothing here would mean anything."
            .. (inCombat and "  Secrecy may be off for this character/context."
                          or "  Run it IN COMBAT."))
        return
    end
    addon:Print("|cff888888feeding: " .. secretFrom .. "|r")

    -- Fresh, never reused - see the note above.
    local host = CreateFrame("Frame", nil, UIParent)
    host:Hide()

    local rows, cells = 0, 0
    --- One matrix row: apply the secret through `sink`, then read every getter back.
    --- @param name string
    --- @param build function -> object (fresh), or nil when the sink itself refused
    --- @param readbacks table array of { label, fn(obj), predict }
    local function Row(name, build, readbacks)
        rows = rows + 1
        local okB, obj = pcall(build)
        if not okB or not obj then
            addon:Print(string.format("%-26s |cffff6600sink refused|r %s", name,
                okB and "" or tostring(obj):gsub("^.-:%d+: ", ""):sub(1, 40)))
            return
        end
        local parts, errs = {}, {}
        for i = 1, #readbacks do
            local rb = readbacks[i]
            local st, txt = ProbeRead(function() return rb.fn(obj) end)
            cells = cells + 1
            -- Carry the message for anything that threw. "err" alone is ambiguous between a
            -- sealed call and a broken probe, and on the first run TWO cells were the latter
            -- - a nil global and an unset bar texture - both indistinguishable from a finding
            -- until the text was in front of us.
            if st == "err" then errs[#errs + 1] = rb.label .. ": " .. tostring(txt) end
            -- A "nil" read is not evidence either way - the getter answered without a
            -- value, which tells us nothing about whether it would have laundered one.
            local colour = "|cff888888"
            if st == "plain" and rb.predict == CHANNEL_PREDICT_SECRET then
                colour = "|cff2ecc71"      -- unexploited capability
            elseif (st == "secret" or st == "err") and rb.predict == CHANNEL_PREDICT_PLAIN then
                colour = "|cffff0000"      -- latent crash / closed since documented
            elseif st == rb.predict then
                colour = "|cffffffff"      -- contract held
            end
            -- Plain cells print their VALUE, not just "plain". On the three-state rows the
            -- value IS the finding: "did we get our own literal back, or the engine's
            -- formatted text" is invisible if the cell only reports its classification.
            parts[#parts + 1] = string.format("%s%s=%s|r", colour, rb.label,
                (st == "plain" and txt and txt ~= "") and ("plain(" .. txt .. ")") or st)
        end
        addon:Print(string.format("%-26s %s", name, table.concat(parts, "  ")))
        for i = 1, #errs do addon:Print("   |cff888888" .. errs[i] .. "|r") end
    end

    -- 1. TEXT SHAPE. The strong lead: only GetText is guarded by the Text aspect.
    Row("FontString:SetText", function()
        local fs = host:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        fs:SetWidth(12)              -- deliberately narrow, so IsTruncated has something to say
        fs:SetText(secretNum)
        return fs
    end, {
        -- GetText is settled: SecretReturnsForAspect{Text}, and the IsSecretZero gate relies
        -- on exactly that. The four shape readbacks are CONTESTED - the documentation guards
        -- them on anchoring rather than Text, while our own note says GetStringWidth goes
        -- secret permanently once a font string has held secret text. One of those is stale
        -- and this is the cell that says which; claiming a side in advance would be the
        -- mistake this whole probe exists to stop making.
        { label = "GetText",       predict = CHANNEL_PREDICT_SECRET,  fn = function(o) return o:GetText() end },
        { label = "width",         predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o:GetStringWidth() end },
        { label = "trunc",         predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o:IsTruncated() end },
        { label = "lines",         predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o:GetNumLines() end },
        { label = "unbounded",     predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o:GetUnboundedStringWidth() end },
    })

    -- A duration object that ACTUALLY carries a secret. Found by asking each candidate
    -- `HasSecretValues()`, which on LuaDurationObject is documented ReturnsNeverSecret -
    -- unconditionally plain - so the search validates itself using the very classifier the
    -- duration row below is here to test. Candidates are whatever the player has that might
    -- be running: an undriven cooldown would make the control row pass while proving nothing.
    local secretDur, durRunning, expiredDur
    do
        local get = C_Spell and C_Spell.GetSpellCooldownDuration
        -- Candidate choice was the reason three runs in a row found only expired durations:
        -- the QUEUE icons hold whatever is ready to press, so sampling them is sampling the
        -- spells least likely to be running. Defensives and the interrupt are usually on
        -- cooldown mid-fight, so they go FIRST, and every list is walked rather than [1].
        local cands = {}
        local function addAll(list, field)
            for i = 1, (list and #list or 0) do
                local e = list[i]
                local id = e and (field and e[field] or e.spellID)
                if id then cands[#cands + 1] = id end
            end
        end
        addAll(addon.defensiveIcons)
        addAll(addon.resolvedInterrupts, "spellID")
        cands[#cands + 1] = addon.interruptIcon and addon.interruptIcon.spellID
        cands[#cands + 1] = addon.maintenanceIcon and addon.maintenanceIcon.spellID
        addAll(addon.spellIcons)
        -- PREFER A RUNNING DURATION. Every earlier run happened to pick an expired one, and
        -- that quietly made the duration rows worthless: a gate answering "zero" against a
        -- zero duration is indistinguishable from a gate that returns a constant. Only a
        -- RUNNING duration shows the channel DISCRIMINATING, which is the property we
        -- actually depend on. Running-ness is itself read through the channel under test -
        -- circular in appearance, not in substance: it only means "the cooldown widget shows".
        -- BOTH excludeGCD values. `true` skips the global, which is what production wants -
        -- but mid-combat the GCD is the one duration that is reliably RUNNING, so `false`
        -- is what actually finds a live one to measure the discriminating branch with.
        local anySecret
        for i = 1, #cands do
            for _, excludeGCD in ipairs({ true, false }) do
                if get and cands[i] and not durRunning then
                    local okD, d = pcall(get, cands[i], excludeGCD)
                    local okH, isSecret = false, false
                    if okD and d and d.HasSecretValues then okH, isSecret = pcall(d.HasSecretValues, d) end
                    if okH and isSecret == true then
                        anySecret = anySecret or d
                        local probe = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
                        local okS = pcall(probe.SetCooldownFromDurationObject, probe, d)
                        local okV, shown = pcall(probe.IsShown, probe)
                        if okS and okV and shown == true then secretDur, durRunning = d, true end
                    end
                end
            end
        end
        -- Keep BOTH when both exist. Every wrong conclusion in this probe's short history came
        -- from observing a gate in one state only, so where a second state is available for
        -- free the probe should take it rather than ask the player to re-run and remember.
        expiredDur = (anySecret ~= secretDur) and anySecret or nil
        secretDur = secretDur or anySecret
        addon:Print("secret DurationObject: " .. (secretDur and "|cff2ecc71found|r" or "|cffff6600none|r")
            .. (secretDur and (durRunning and " |cff2ecc71(RUNNING - rows discriminate)|r"
                or " |cffff6600(expired/zero - rows only show the zero branch; press a cooldown"
                   .. " and re-run to test the other one)|r")
                or " - the duration rows below are inconclusive"))
    end

    -- 2. CONTROL. Shipped and proven; a red cell here is a closure, not a discovery.
    -- Returns nil rather than an undriven widget when no secret duration exists, so the row
    -- reports "sink refused" instead of passing on a cooldown nothing was ever fed into.
    Row("Cooldown:SetCooldownFromDur", function()
        if not secretDur then return nil end
        local cd = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
        cd:SetCooldownFromDurationObject(secretDur)
        return cd
    end, {
        { label = "IsShown",       predict = CHANNEL_PREDICT_PLAIN,  fn = function(o) return o:IsShown() end },
        { label = "GetCooldownTimes", predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o:GetCooldownTimes() end },
    })

    -- 2b. THE CURVE FAMILY. Believed SECRET despite carrying only `SecretWhenCurveSecret`
    -- and being handed a plain curve - because BlizzardAPI.DurationBelow, which ships and
    -- works, has to push the result through the IsSecretZero text gate to get a boolean.
    -- Included anyway, and this is the point of a matrix rather than a hypothesis: it costs
    -- one cell to keep measuring a thing we think we know, and the day Blizzard makes these
    -- plain we get a numeric read of every cooldown and aura for free. `zeroGate` is the
    -- extraction we actually use, carried alongside so the row shows the working chain next
    -- to the raw call it is built on.
    Row("DurationObject (curve)", function()
        if not secretDur then return nil end
        local cu = C_CurveUtil
        if not (cu and cu.CreateCurve) then return nil end
        local c = cu.CreateCurve()
        c:AddPoint(0, 0)
        c:AddPoint(1, 100)
        return { d = secretDur, c = c }
    end, {
        { label = "HasSecretValues", predict = CHANNEL_PREDICT_PLAIN,  fn = function(o) return o.d:HasSecretValues() end },
        { label = "remPct",          predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o.d:EvaluateRemainingPercent(o.c) end },
        { label = "remDur",          predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o.d:EvaluateRemainingDuration(o.c) end },
        { label = "totalDur",        predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o.d:EvaluateTotalDuration(o.c) end },
        -- The working chain, called through the SHIPPED entry point rather than rebuilt
        -- here: secret result -> TruncateWhenZero -> scratch FontString emptiness -> plain
        -- boolean. Testing production's own function is the point - a reconstruction with a
        -- hand-rolled curve would measure my copy of the technique, not the one that ships.
        { label = "zeroGate",        predict = CHANNEL_PREDICT_PLAIN,  fn = function(o)
            return BlizzardAPI.IsDurationBelowPercent(o.d, 30) end },
    })

    -- 3. BAR VALUE vs BAR GEOMETRY. GetValue/GetMinMaxValues are guarded by BarValue, but
    -- GetStatusBarTexture carries no aspect guard at all and the texture's own geometry is
    -- guarded by Hierarchy/Anchoring - a different aspect than the one SetValue stamps.
    Row("StatusBar:SetValue", function()
        local sb = CreateFrame("StatusBar", nil, host)
        sb:SetSize(100, 10)
        -- REQUIRED, and its absence cost a run: a StatusBar with no texture returns nil from
        -- GetStatusBarTexture, so both geometry cells threw and reported "err" - which reads
        -- as "the channel is closed" when nothing had been tested at all.
        sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        sb:SetMinMaxValues(0, 100)
        sb:SetValue(secretNum)
        return sb
    end, {
        { label = "GetValue",      predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o:GetValue() end },
        { label = "texW",          predict = CHANNEL_PREDICT_PLAIN,  fn = function(o) return o:GetStatusBarTexture():GetWidth() end },
        { label = "texCoord",      predict = CHANNEL_PREDICT_PLAIN,  fn = function(o) return select(2, o:GetStatusBarTexture():GetTexCoord()) end },
    })

    -- 4. ALPHA. SetAlpha takes a secret (it is the sink the whole cue system rides on), and
    -- GetAlpha is guarded by the Alpha aspect - so this row should be sealed. It is here as
    -- a NEGATIVE control: if this ever reads plain, the aspect model itself has changed.
    Row("Frame:SetAlpha", function()
        local f = CreateFrame("Frame", nil, host)
        local ok = pcall(f.SetAlpha, f, secretNum)
        if not ok then return nil end
        return f
    end, {
        { label = "GetAlpha",      predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o:GetAlpha() end },
    })

    -- 4b. THE TEXTURE LAUNDERER - the one candidate tools/audit_secret_channels.py turned up
    -- after the noise was filtered out, and the only sink in the entire API with our working
    -- channel's exact shape: it accepts a RAW secret (SecretArguments = AllowedWhenTainted)
    -- and declares NO SecretArgumentsAddAspect, so nothing is sealed on the way in. Its
    -- readbacks GetTexture/GetAtlas declare no aspect guard either, while every OTHER getter
    -- on a Texture does (Desaturation, Rotation, TexCoords, RadialProgress).
    --
    -- If that is literal, SetTexture(secretNumber) -> GetTexture() converts a secret number
    -- into a plain one, which would be a universal launderer and is almost certainly too
    -- good to be true - the measured rule all day has been that taint follows derivation
    -- whatever the annotations claim. Believed SECRET for exactly that reason. It costs one
    -- row to find out, and "too good to be true" is a prediction, not a measurement.
    Row("Texture:SetTexture(secret)", function()
        local t = host:CreateTexture(nil, "ARTWORK")
        if not pcall(t.SetTexture, t, secretNum) then return nil end
        return t
    end, {
        { label = "GetTexture",  predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o:GetTexture() end },
        { label = "GetAtlas",    predict = CHANNEL_PREDICT_SECRET, fn = function(o) return o:GetAtlas() end },
    })

    -- 4c. DURATION TEXT BINDING - the other collapse-to-absence candidate, from the
    -- --absence pass of tools/audit_secret_channels.py.
    --
    -- A binding drives OUR font string from a secret duration and writes one of THREE
    -- things: the formatted remaining time (engine-derived, so secret), or one of two
    -- literals we supplied ourselves - zeroDurationText for an unconfigured/zero span,
    -- expiredText for one that has run out. Those literals never came from the secret, so
    -- if the engine writes one back verbatim the font string may hold PLAIN text.
    --
    -- Two reasons this earns a row despite the zero-gate already answering is-zero:
    --   * REDUNDANCY. It reaches the same predicate by a completely different route, so if
    --     TruncateWhenZero is ever sealed this says whether a fallback exists - and the
    --     readiness probe is load-bearing enough to want a spare.
    --   * A THREE-state discriminator is more than the gate gives. nil / our expired literal
    --     / secret would separate "expired" from "still running" from "no duration at all",
    --     where the gate only says zero or not.
    -- Deliberately marked unknown, not predicted: which state the binding lands in depends on
    -- whether the duration we found happens to be running, and we do not control that.
    -- GetFormattedText is a readback nothing has ever tested - it returns what WOULD be
    -- written, bypassing the font string entirely.
    -- Built once and run for EVERY duration state we managed to find, because a binding
    -- observed only while running proves as little as one observed only while expired: the
    -- channel is the DIFFERENCE between the two, never either reading on its own.
    local function BindingRow(label, dur)
    Row(label, function()
        local secretDur = dur
        if not secretDur then return nil end
        local du = C_DurationUtil
        if not (du and du.CreateDurationTextBinding) then return nil end
        local okB, b = pcall(du.CreateDurationTextBinding)
        if not okB or not b then return nil end
        local fs = host:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        -- SetToDefaults first where it exists: Blizzard's own aura button configures a
        -- binding that way, and guessing a formatter's arguments is how this row would end
        -- up measuring my misconfiguration instead of the client.
        pcall(b.SetToDefaults, b)
        -- A FORMATTER, which SetToDefaults does not appear to install: Blizzard's own aura
        -- button does SetToDefaults() AND THEN SetFormatter(), and skipping the second call
        -- is the remaining explanation for a binding that formats (GetFormattedText returns
        -- secret) yet writes nothing - a secret EMPTY string would look exactly like this.
        -- Safe here where it would not be on a count: duration text goes through the C-side
        -- binding, which handles secrets. See the SetApplicationCount trap in UIMaintenanceAura.
        if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
            local okF, f = pcall(C_StringUtil.CreateSecondsFormatter)
            if okF and f then pcall(b.SetFormatter, b, f) end
        end
        if not pcall(b.SetFontString, b, fs) then return nil end
        pcall(b.SetZeroDurationText, b, "")        -- collapse to absence on zero
        pcall(b.SetExpiredText, b, "EXP")          -- a literal that is ours, never derived
        pcall(b.SetDuration, b, secretDur)
        -- ENABLE, and this was missing: without it the binding never writes to the font
        -- string at all, so fsText came back nil against a RUNNING duration too. That nil
        -- looked exactly like the collapse-to-absence result we were hoping for and briefly
        -- got recorded as one - a false positive that only the discriminating run exposed.
        pcall(b.SetEnabled, b, true)
        pcall(b.UpdateFontString, b)
        return { b = b, fs = fs }
    end, {
        { label = "fsText",     predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o.fs:GetText() end },
        { label = "fmtText",    predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o.b:GetFormattedText() end },
        { label = "hasSecret",  predict = CHANNEL_PREDICT_PLAIN,   fn = function(o) return o.b:HasSecretValues() end },
        -- Measured SECRET, and it was predicted plain. `CanFormatText` is documented as
        -- answering a pure configuration question - "does this binding have enough config to
        -- produce text" - and it still inherits the bound duration's secrecy. Even
        -- CONFIGURATION-STATE booleans are tainted once a secret is attached, which is the
        -- taint-follows-derivation rule reaching further than a value readback.
        { label = "canFormat",  predict = CHANNEL_PREDICT_SECRET,  fn = function(o) return o.b:CanFormatText() end },
        -- The predicate that separates the two failure modes: "can format" and "can update
        -- the font string" are documented as DIFFERENT questions, and only this one answers
        -- why a binding that demonstrably produces text writes none of it.
        { label = "canUpdate",  predict = CHANNEL_PREDICT_UNKNOWN, fn = function(o) return o.b:CanUpdateFontString() end },
    })
    end
    BindingRow(durRunning and "DurTextBind(running)" or "DurTextBind(expired)", secretDur)
    -- The other state, when the search happened to turn one up. `fsText` must differ between
    -- the two rows - secret while running, nil at zero - or the binding is not a gate at all.
    if expiredDur then BindingRow("DurTextBind(expired)", expiredDur) end

    -- 5. The same classifier on a WIDGET - and the answer is a TRAP, measured 2026-08-12.
    -- It reads plain, but it reads plain FALSE on a font string we just fed a secret to,
    -- while GetText on that same object is secret (row 1). So HasSecretValues on a widget
    -- does NOT mean "a secret was written into me", and it is NOT the provenance oracle it
    -- looks like - an earlier note here suggested it could replace our PlainText probe, and
    -- that would have been a silent, confident wrong answer everywhere it was used.
    -- On a DATA object it is trustworthy: row 2b's LuaDurationObject correctly says true.
    -- Kept as a row precisely to keep that distinction measured rather than remembered.
    Row("ScriptObject (secret text)", function()
        local fs = host:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        fs:SetText(secretNum)
        return fs
    end, {
        { label = "HasSecretValues", predict = CHANNEL_PREDICT_PLAIN, fn = function(o) return o:HasSecretValues() end },
    })

    addon:Print(string.format("%d rows / %d cells.  |cff2ecc71green|r = believed secret, read PLAIN"
        .. " (new channel).  |cffff0000red|r = believed plain, read secret/err (closed, or a"
        .. " crash waiting).  |cff888888grey|r = contested, claiming nothing.", rows, cells))
    addon:Print("=========================")
end

--------------------------------------------------------------------------------
-- /jac inspect aurapanels - Blizzard's OWN aura panels, and whether they are live
--------------------------------------------------------------------------------
-- The one aura-identity technique that still works in 12.1.0 does not read an aura at all:
-- it reads what BLIZZARD'S UNTAINTED CODE already computed and left on a frame. That is how
-- MaintenanceTracker gets an instance id off the Cooldown Manager - the viewer does the
-- secret spellId match for us and materializes the answer as a plain field.
--
-- Several other Blizzard panels are built on the SAME 12.1 aura containers and have never
-- been probed. TargetFrame.Auras is the interesting one: it is the real `AuraContainer`
-- intrinsic (not the same-named plain Frame + Lua mixin in the buff-frame templates - that
-- is a name collision), Blizzard creates it, and Blizzard's own code calls
-- `element:GetAuraInstance()` on its buttons. If that call is reachable from tainted code it
-- is a route to ENEMY aura identity, which every direct route lost.
--
-- TWO RULES THIS PROBE EXISTS TO ENFORCE, both learned the hard way:
--   * A PANEL MUST BE LIVE BEFORE ANY READ MEANS ANYTHING. A hidden Cooldown Manager viewer
--     serves a FROZEN instance id forever (OnHide drops its UNIT_AURA registration), so a
--     read off a hidden panel is not "no data", it is WRONG data that looks fine. Every row
--     here reports shown/alpha/populated FIRST and refuses to interpret reads without it.
--   * RESOLVE PANELS AS PATHS, never by name. `nameplate.UnitFrame.castBar` moved into
--     `CastBarsContainer` in 12.x with no alias and silently killed CC substitution; a
--     name-level grep could not see it. Each row below states the path it walked and where
--     it stopped, so a move shows up as a short path rather than as a mystery.
local AURA_PANEL_PATHS = {
    { "TargetFrame.Auras",       "target aura container - the real intrinsic; the prize" },
    { "FocusFrame.Auras",        "same shape on focus" },
    { "BuffFrame.AuraContainer", "player buffs (plain Frame + mixin, NOT the intrinsic)" },
    { "DebuffFrame.AuraContainer", "player debuffs" },
    { "BuffIconCooldownViewer",  "Cooldown Manager - the one we already read" },
}

function DebugCommands.AuraPanelProbe(addon)
    addon:Print("=== Blizzard aura panels ===")
    local hasTarget = UnitExists and UnitExists("target")
    addon:Print("target: " .. tostring(hasTarget)
        .. (hasTarget and "" or "  |cffff6600no target - the target/focus rows cannot populate|r"))

    for i = 1, #AURA_PANEL_PATHS do
        local path, note = AURA_PANEL_PATHS[i][1], AURA_PANEL_PATHS[i][2]
        -- Walk the path a SEGMENT at a time and report where it stopped. A frame that moved
        -- reads as "stopped at X" instead of a bare nil, which is the difference between
        -- "Blizzard renamed something" and "this panel does not exist".
        local obj, walked = nil, {}
        for seg in path:gmatch("[^.]+") do
            obj = (obj == nil) and _G[seg] or (type(obj) == "table" and obj[seg] or nil)
            walked[#walked + 1] = seg
            if obj == nil then break end
        end
        if obj == nil then
            -- "missing" overstates it. Measured 2026-08-12 in combat with a target:
            -- TargetFrame resolves and TargetFrame.Auras does not, and the reason is not a
            -- moved path - Blizzard's aura containers carry `useForbiddenObjectTable="true"`,
            -- so a tainted reader cannot obtain a reference to one at all. Unreachable, not
            -- relocated, and no amount of path-hunting will fix it.
            addon:Print(string.format("%-28s |cffff6600unreachable|r - stops after %s"
                .. " (moved, or a forbidden object)  |cff888888(%s)|r",
                path, table.concat(walked, "."), note))
        else
            local okS, shown = pcall(function() return obj:IsShown() end)
            local okA, alpha = pcall(function() return obj:GetAlpha() end)
            local live = okS and shown == true
            addon:Print(string.format("%-28s %s  alpha=%s  |cff888888(%s)|r",
                path, live and "|cff2ecc71SHOWN|r" or "|cffff6600hidden/unknown|r",
                okA and tostring(alpha) or "err", note))
            if not live then
                addon:Print("   |cff888888not live - anything read here is stale or absent, not evidence|r")
            else
                DebugCommands._ProbeAuraPanelButtons(addon, obj)
            end
        end
    end

    -- DISCOVERY, because guessing paths is what the "frame paths move silently" lesson says
    -- not to do and the list above did anyway (TargetFrame resolves, TargetFrame.Auras does
    -- not). Every intrinsic container answers GetObjectType() == "AuraContainer", so walk the
    -- whole frame list and let the CLIENT say where they are. This finds them wherever
    -- Blizzard moved them, which a hardcoded path can never do.
    if EnumerateFrames then
        addon:Print("-- discovery: every live AuraContainer intrinsic --")
        local f, n, shownN = EnumerateFrames(), 0, 0
        while f and n < 40 do
            local okT, t = pcall(function() return f:GetObjectType() end)
            if okT and t == "AuraContainer" then
                n = n + 1
                local okS, shown = pcall(function() return f:IsShown() end)
                if okS and shown then shownN = shownN + 1 end
                local okN, nm = pcall(function() return f:GetDebugName() end)
                addon:Print(string.format("   %s  shown=%s",
                    (okN and nm and nm ~= "") and nm or "<unnamed>",
                    okS and tostring(shown) or "err"))
            end
            f = EnumerateFrames(f)
        end
        -- ANSWERED, 2026-08-12: this returns ZERO even with a target up and even while our
        -- own soothe cue holds live containers. They are not missing - every container XML
        -- carries `useForbiddenObjectTable="true"`, and a tainted caller's frame enumeration
        -- does not include forbidden objects. So the count being zero IS the finding, and
        -- the row is kept as a tripwire: a non-zero result means the rule changed.
        addon:Print(string.format("   %d AuraContainer intrinsic(s), %d shown%s", n, shownN,
            n == 0 and "  |cff888888- expected: containers are forbidden objects and are"
                   .. " invisible to tainted enumeration, even ours|r" or
                   "  |cffff6600- UNEXPECTED: enumeration used to return none|r"))
    end
    addon:Print("============================")
end

--- Walk a live panel's children and ask each what it will tell a TAINTED caller about its
--- aura. `GetAuraInstance` is the interesting one - it is what Blizzard's own target-frame
--- code calls, and a plain auraInstanceID out of it would be enemy aura identity.
--- Children rather than the frame pool: the pool is provider-private, and enumerating what
--- is actually parented is the honest question anyway.
function DebugCommands._ProbeAuraPanelButtons(addon, panel)
    -- RECURSIVE, and it has to be. Aura buttons are pooled onto an inner container frame, so
    -- they are GRANDchildren - MaintenanceTracker already carries this exact warning about
    -- the Cooldown Manager ("a one-level GetChildren() walk never reaches them, which is why
    -- an earlier attempt silently did nothing") and the first version of this probe walked
    -- one level anyway and reported a confident 0 for every panel.
    -- Depth 4 covers viewer -> itemContainer -> item and container -> button -> region.
    local seen, reported, scanned = 0, 0, 0
    local function walk(frame, depth)
        if depth > 4 or reported >= 2 then return end
        local okK, kids = pcall(function() return { frame:GetChildren() } end)
        if not okK or not kids then return end
        for i = 1, #kids do
            local b = kids[i]
            scanned = scanned + 1
            if b.GetAuraInstance then
                local okV, vis = pcall(function() return b:IsShown() end)
                if okV and vis then
                    seen = seen + 1
                    if reported < 2 then   -- two characterises it; the rest repeat
                        reported = reported + 1
                        local st, txt = ProbeRead(function()
                            local d = select(2, b:GetAuraInstance())
                            return d and d.auraInstanceID
                        end)
                        local st2 = ProbeRead(function()
                            local d = select(2, b:GetAuraInstance())
                            return d and d.spellId
                        end)
                        addon:Print(string.format("   button(d%d) auraInstanceID=%s(%s)  spellId=%s",
                            depth, st, tostring(txt), st2))
                    end
                end
            end
            walk(b, depth + 1)
        end
    end
    walk(panel, 1)
    addon:Print(string.format("   %d descendant(s) scanned, %d shown with GetAuraInstance",
        scanned, seen))
    if scanned == 0 then
        addon:Print("   |cff888888no descendants at all - panel is an empty shell right now|r")
    elseif seen == 0 then
        -- NOT "the target has no auras": on the player panels there is no target involved,
        -- and the buff-frame templates are the plain Frame + mixin, whose buttons never had
        -- GetAuraInstance to begin with. Absence here means the wrong KIND of panel, not
        -- absence of auras.
        addon:Print("   |cff888888descendants exist but none expose GetAuraInstance - not an"
            .. " intrinsic-container panel|r")
    end
end

--------------------------------------------------------------------------------
-- /jac inspect audioalerts - the combat audio alert manager as a SIGNAL SOURCE
--------------------------------------------------------------------------------
-- Blizzard's combat audio alert system announces player/target health, player/target casts,
-- party health and player debuffs. To do that it must COMPUTE those things - and it is
-- ordinary untainted Lua on an ordinary Frame (`CombatAudioAlertManager`, toplevel, plain
-- mixin), NOT one of the forbidden aura containers. It caches what it computed:
--
--   lastUnitHealthPercent[unit]      lastPlayerPowerPercent[...]     partyHealthInfo
--   lastUnitHealthAnnouncePercent    lastPlayerPowerAnnouncePercent  lastInterruptedCast
--   unitCastStartUnitsLookup         unitCastEndUnitsLookup          unitHealthUnitsLookup
--
-- Why this is worth measuring rather than assuming: untainted control flow CAN launder a
-- secret into a plain value, and we already ship a technique that depends on it -
-- `item.isActive` on the Cooldown Manager is "an ordinary boolean assigned by untainted
-- control flow" and reads PLAIN in combat (MaintenanceTracker.ViewerBuffActive). If health
-- and power percents survive the same way, they are branchable numbers - the exact thing
-- every note we have says does not exist.
--
-- Same conditionality as the Cooldown Manager, and the same trap: this only computes while
-- the FEATURE IS ON. A category the player left off caches nothing, and a stale cache from a
-- category switched off mid-session would be worse than nothing - so report the settings
-- FIRST and never interpret a value without them.
function DebugCommands.AudioAlertProbe(addon)
    addon:Print("=== combat audio alerts as a signal source ===")
    local mgr = CombatAudioAlertManager
    if not mgr then
        addon:Print("|cffff6600CombatAudioAlertManager missing|r - addon not loaded this session")
        return
    end
    addon:Print("manager: present  initDone=" .. tostring(rawget(mgr, "initDone")))

    -- WHICH CATEGORIES ARE ON. Everything below is meaningless without this: an off category
    -- never populates its cache, so a nil read means "disabled", not "unreadable".
    local CA = C_CombatAudioAlert
    local cats = Enum and Enum.CombatAudioAlertCategory
    if CA and CA.GetSpecSetting and type(cats) == "table" then
        local parts = {}
        for name, value in pairs(cats) do
            local st, txt = ProbeRead(function() return CA.GetSpecSetting(value) end)
            parts[#parts + 1] = string.format("%s=%s", name, st == "plain" and txt or st)
        end
        table.sort(parts)
        addon:Print("settings: " .. table.concat(parts, "  "))
    else
        addon:Print("|cff888888category settings unavailable - cannot say which caches are live|r")
    end

    -- THE CACHES. Percent-per-unit tables are the prize; the rest are cheap to read while
    -- we are here and each one is a signal in its own right if it comes back plain.
    local function report(label, fn)
        local st, txt = ProbeRead(fn)
        local colour = (st == "plain") and "|cff2ecc71" or "|cff888888"
        addon:Print(string.format("  %-38s %s%s|r%s", label, colour, st,
            (st == "plain" and txt and txt ~= "nil") and (" = " .. txt) or ""))
    end
    report("lastUnitHealthPercent[player]", function() return mgr.lastUnitHealthPercent and mgr.lastUnitHealthPercent["player"] end)
    report("lastUnitHealthPercent[target]", function() return mgr.lastUnitHealthPercent and mgr.lastUnitHealthPercent["target"] end)
    report("lastPlayerPowerPercent (count)", function()
        local t = mgr.lastPlayerPowerPercent
        if type(t) ~= "table" then return nil end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end)
    report("lastPlayerPowerPercent (first value)", function()
        local t = mgr.lastPlayerPowerPercent
        if type(t) ~= "table" then return nil end
        -- next(), not a one-iteration pairs loop: the table is keyed by power token and any
        -- entry characterises it, so say "give me one" rather than writing a loop that lies
        -- about iterating.
        return select(2, next(t))
    end)
    report("partyHealthInfo.unitCount", function()
        return mgr.partyHealthInfo and mgr.partyHealthInfo.unitCount
    end)
    report("lastInterruptedCast", function() return mgr.lastInterruptedCast end)
    report("unitCastStartUnitsLookup[target]", function()
        return mgr.unitCastStartUnitsLookup and mgr.unitCastStartUnitsLookup["target"]
    end)

    addon:Print("|cff888888green = PLAIN, i.e. branchable. A percent reading plain here is a"
        .. " number every other route says cannot exist - re-read the settings line before"
        .. " believing it, and check it TRACKS (take damage, re-run).|r")
    addon:Print("==============================================")
end

--------------------------------------------------------------------------------
-- /jac inspect hotkeys - why a queue icon has no keybind
--------------------------------------------------------------------------------
-- Reported 2026-08-12: while CHANNELING, the next recommendation shows no hotkey, and it
-- comes back the moment the channel ends. Three causes look identical on screen and this
-- probe exists to tell them apart, because guessing between them is how the wrong one gets
-- "fixed":
--
--   1. THE SPELL GENUINELY HAS NO BINDING. Nothing is broken; the recommendation is an
--      ability the player has not placed on a bar. `slot` below is nil every pass.
--   2. CACHE STARVATION. ACTIONBAR_SLOT_CHANGED fires constantly in some situations, and
--      every one of those FULL-WIPES spellSlotCache. The forward-override scan in
--      GetSpellHotkey - the only route that resolves an aura-driven transform - can only
--      work by iterating that table, so a cache wiped faster than it warms resolves
--      nothing. Watch `wipes` climbing and `slotEntries` staying near zero.
--   3. REFRESH THROTTLE. `lastHotkeyRefreshTime` is ONE module-level timestamp shared by
--      every spell, so the first lookup each interval consumes the refresh and every other
--      spell is served its stale value - which for a spell cached as "" is "" again.
--      Watch `sinceRefresh` staying pinned below the interval.
--
-- Run it WHILE the symptom is on screen. Run it again after the channel ends and diff the
-- two: what CHANGES between them is the cause, and any single reading is just a snapshot.
function DebugCommands.HotkeyProbe(addon)
    addon:Print("=== hotkey resolution ===")
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    if not ABS then addon:Print("|cffff6600ActionBarScanner unavailable|r") return end

    local channeling = PlayerCastingBarFrame and PlayerCastingBarFrame.channeling == true
    local casting    = PlayerCastingBarFrame and PlayerCastingBarFrame.casting == true
    addon:Print(string.format("state: channeling=%s casting=%s combat=%s",
        tostring(channeling), tostring(casting),
        tostring(UnitAffectingCombat and UnitAffectingCombat("player") or false)))

    local st = ABS.GetHotkeyCacheStats and ABS.GetHotkeyCacheStats()
    if st then
        -- slotEntries near zero with a climbing wipe count IS cause 2; a healthy cache with
        -- sinceRefresh pinned low is cause 3; a healthy cache and a stable count leaves 1.
        addon:Print(string.format("cache: hotkeys=%d slots=%d valid=%s  wipes=%d"
            .. "  sinceWipe=%.1fs  sinceRefresh=%.2fs",
            st.hotkeyEntries, st.slotEntries, tostring(st.valid), st.wipes,
            st.sinceWipe, st.sinceRefresh))
        if st.slotEntries == 0 then
            addon:Print("   |cffff6600slot cache EMPTY|r - the override scan has nothing to"
                .. " search, so any aura-driven transform resolves to no keybind")
        end
    end

    -- Per icon: what it is showing, what it cached, and what a FRESH lookup says right now.
    -- The cached-vs-fresh split matters: equal-and-empty means the lookup genuinely fails,
    -- while cached-empty but fresh-good means we are serving a stale blank.
    local icons = addon.spellIcons
    for i = 1, math.min(icons and #icons or 0, 4) do
        local icon = icons[i]
        local sid = icon and icon.spellID
        if sid then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local fresh = ABS.GetSpellHotkey and ABS.GetSpellHotkey(sid) or "?"
            local slot  = ABS.GetSlotForSpell and ABS.GetSlotForSpell(sid)
            local shownText = icon.hotkeyText and icon.hotkeyText:GetText() or ""
            addon:Print(string.format("  [%d] %-22s cached=%-8s fresh=%-8s slot=%-5s onScreen=%s",
                i, (info and info.name) or ("id " .. sid),
                (icon.cachedHotkey ~= nil and icon.cachedHotkey ~= "") and icon.cachedHotkey or "<empty>",
                (fresh ~= "") and fresh or "<empty>",
                tostring(slot or "none"),
                (shownText ~= "") and shownText or "<blank>"))
            -- WHICH LINK BROKE. Five of them fail independently and all five look the same
            -- on screen, so the chain is printed whenever the answer came back empty.
            if fresh == "" and ABS.DebugResolveHotkey then
                local r = ABS.DebugResolveHotkey(sid)
                addon:Print(string.format("       chain: name=%s slot=%s macro=%s%s parse=%s"
                    .. " mods=%s baseKey=%s",
                    r.name and "ok" or "|cffff0000NIL|r",
                    r.slot and tostring(r.slot) or "|cffff0000NIL|r",
                    tostring(r.isMacro or false),
                    r.macroName and ("(" .. r.macroName .. ")") or "",
                    r.isMacro and (r.macroFound and "ok" or "|cffff0000NIL|r") or "-",
                    r.modifiers and tostring(r.modifiers) or "-",
                    r.baseKey and tostring(r.baseKey) or "|cffff0000NIL|r"))
            end
        end
    end
    addon:Print("Run again AFTER the channel ends and compare - the field that changes is the cause.")
    addon:Print("=========================")
end

function DebugCommands.EnrageLog(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.probeLog = nil end
        addon:Print("enragelog: |cffffff00log cleared|r")
        return
    end
    if arg == "off" or (not arg and DebugCommands._enrageLog) then
        if DebugCommands._enrageLog then
            DebugCommands._enrageLog:Cancel()
            DebugCommands._enrageLog = nil
        end
        addon:Print(string.format("enragelog: |cffff6600OFF|r - %d log lines held.", #ProbeLogStore()))
        addon:Print("|cff888888/reload to flush (JustACGlobal.probeLog)|r")
        return
    end

    ProbeLogEmit(string.format("===== ENRAGELOG armed @ %.1f =====", GetTime()))
    local last = nil
    DebugCommands._enrageLog = C_Timer.NewTicker(0.2, function()
        local nb, nd, ignored, auras, berr, derr = EnrageSample()
        -- Frame state is plain, so the cue's own verdict IS readable even though the
        -- alpha that drives it is not - this is the correlation that matters.
        local intIcon = addon.interruptIcon
        local cue = intIcon and intIcon.sootheCue
        local cueShown = (cue and cue:IsShown()) and true or false
        local key = string.format("%s|%s|%s|%s|%s|%s", tostring(nb), tostring(nd),
            tostring(ignored), tostring(cueShown), tostring(berr), tostring(derr))
        if key == last then return end
        last = key
        ProbeLogEmit(string.format(
            "ENR %.1f combat=%s target=%s helpful=%s dispellable=%s%s cueShown=%s",
            GetTime(), tostring(UnitAffectingCombat("player")),
            tostring(UnitName("target")),
            berr and ("|cffff6600" .. berr .. "|r") or tostring(nb),
            derr and ("|cffff6600" .. derr .. "|r") or tostring(nd),
            ignored and " |TOKEN-IGNORED|" or "", tostring(cueShown))
            .. DecodeDispelTypes(auras))
    end)
    addon:Print("enragelog: |cff00ff00ON|r - sampling target dispellable-aura count 5/s (changes only).")
    addon:Print("|cff888888Pull the mob that always enrages, then '/jac inspect enragelog off' and /reload.|r")
end

local PROBE_BATTERY = { "DurationProbe", "AuraInstanceIdsProbe", "CooldownFieldsProbe",
                        "FrameStateProbe", "CooldownViewerItemsProbe", "EngineSignalsProbe" }

local function RunProbeBattery(addon, tag, includeStatic)
    ProbeLogEmit(string.format("===== %s @ %.1f combat=%s hp-context: dead=%s =====",
        tag, GetTime(), tostring(UnitAffectingCombat("player")), tostring(UnitIsDeadOrGhost("player"))))
    local proxy = LogProxy(addon)
    if includeStatic then pcall(DebugCommands.SecrecyMapProbe, proxy) end
    for _, m in ipairs(PROBE_BATTERY) do
        pcall(DebugCommands[m], proxy)
    end
    addon:Print(string.format("audit: |cff00ff00%s|r snapshot captured (%d log lines held).",
        tag, #ProbeLogStore()))
end

--------------------------------------------------------------------------------
-- /jac inspect errors [off|clear|show] - capture Lua errors AND taint blocks to
-- SavedVariables (JustACGlobal.errorLog), so a fight's worth of errors can be read
-- off disk after a /reload instead of copied out of a chat frame.
--
-- TWO channels, deliberately: a tainted-execution failure NEVER reaches
-- seterrorhandler - the client fires ADDON_ACTION_BLOCKED/FORBIDDEN as an event
-- carrying (addonName, functionName) instead. Capturing only the Lua handler is
-- how a taint problem looks like "no errors at all" while the screen fills up.
--
-- Entries are DEDUPED by message and counted. One bad call inside a combat-frequency
-- hook produces thousands of identical errors; storing each one buries the single
-- other error that actually matters and bloats the saved file for nothing.
--------------------------------------------------------------------------------
local ERRORLOG_MAX = 250      -- distinct entries, not occurrences

local function ErrorLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.errorLog = g.errorLog or {}
    return g.errorLog
end

--- Record one error/block, collapsing repeats into a count + last-seen time.
local function ErrorLogRecord(kind, msg, stack)
    local log = ErrorLogStore()
    local key = kind .. "|" .. tostring(msg or "?")
    for i = 1, #log do
        if log[i].key == key then
            local e = log[i]
            e.count = e.count + 1
            e.last = GetTime()
            e.lastCombat = UnitAffectingCombat("player") and true or false
            return
        end
    end
    if #log >= ERRORLOG_MAX then return end   -- full: keep the first N, they came first
    log[#log + 1] = {
        key = key, kind = kind, count = 1,
        msg = tostring(msg or "?"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
        stack = stack and tostring(stack):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil,
        first = GetTime(), last = GetTime(),
        firstCombat = UnitAffectingCombat("player") and true or false,
    }
end

function DebugCommands.ErrorCapture(addon, arg)
    arg = arg and arg:lower() or nil

    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.errorLog = nil end
        addon:Print("errors: |cffffff00log cleared|r")
        return
    end

    if arg == "show" then
        local log = ErrorLogStore()
        if #log == 0 then addon:Print("errors: none captured.") return end
        addon:Print(string.format("errors: |cffffff00%d distinct|r", #log))
        for i = 1, math.min(#log, 10) do
            local e = log[i]
            addon:Print(string.format("|cffff6600%d.|r [%s x%d%s] %s",
                i, e.kind, e.count, e.firstCombat and " COMBAT" or "", e.msg))
        end
        if #log > 10 then addon:Print(string.format("|cff888888... %d more; /reload and read the file|r", #log - 10)) end
        return
    end

    if arg == "off" or (not arg and DebugCommands._errorCapture) then
        local f = DebugCommands._errorCapture
        if f then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._errorCapture = nil
        end
        -- The Lua handler stays chained: seterrorhandler has no unregister, and
        -- restoring a stale handler would clobber whatever installed itself after us.
        -- The flag below is what actually gates recording.
        DebugCommands._errorCaptureOn = false
        addon:Print(string.format("errors: |cffff6600OFF|r - %d distinct entries held.", #ErrorLogStore()))
        addon:Print("|cff888888/reload to flush to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua (JustACGlobal.errorLog)|r")
        return
    end

    DebugCommands._errorCaptureOn = true

    -- Chain the Lua error handler once per session; the flag gates recording so
    -- toggling off/on never stacks handlers.
    if not DebugCommands._errorHandlerHooked then
        DebugCommands._errorHandlerHooked = true
        local prev = geterrorhandler and geterrorhandler()
        if seterrorhandler then
            seterrorhandler(function(msg)
                if DebugCommands._errorCaptureOn then
                    -- debugstack(2) skips this closure and the handler frame.
                    ErrorLogRecord("LUA", msg, debugstack and debugstack(2, 12, 12))
                end
                if prev then return prev(msg) end
            end)
        end
    end

    local f = CreateFrame("Frame")
    DebugCommands._errorCapture = f
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addonName, funcName)
        if not DebugCommands._errorCaptureOn then return end
        ErrorLogRecord(event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED",
            string.format("%s tried to call %s", tostring(addonName), tostring(funcName)))
    end)

    addon:Print("errors: |cff00ff00ON|r - capturing Lua errors and taint blocks.")
    addon:Print("|cff888888Fight, then '/jac inspect errors off' and /reload. '/jac inspect errors show' for a quick look.|r")
    addon:Print("|cff888888Repeats are collapsed into a count, so a flood shows as one line xN.|r")
end

function DebugCommands.ProbeSession(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.probeLog = nil end
        addon:Print("audit: |cffffff00log cleared|r")
        return
    end
    if arg == "off" or (not arg and DebugCommands._probeSession) then
        local f = DebugCommands._probeSession
        if f then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._probeSession = nil
        end
        if DebugCommands._probeTicker then
            DebugCommands._probeTicker:Cancel()
            DebugCommands._probeTicker = nil
        end
        -- Disarm the event captures we armed (they toggle).
        if DebugCommands._locWatch then DebugCommands.LossOfControlWatch(LogProxy(addon)) end
        if DebugCommands._selfCast then DebugCommands.SelfCastProbe(LogProxy(addon)) end
        addon:Print(string.format("audit: |cffff6600OFF|r - %d log lines held.", #ProbeLogStore()))
        addon:Print("|cff888888/reload to flush to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua (JustACGlobal.probeLog)|r")
        return
    end

    local f = CreateFrame("Frame")
    DebugCommands._probeSession = f
    local cycles = 0
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD") -- instanced content (delves) loads via this, not ZONE_CHANGED
    f:SetScript("OnEvent", function(_, event)
        if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
            -- Restricted-map baseline: SecretOnRestrictedMaps applies OOC too,
            -- so entering a delve/dungeon deserves its own out-of-combat snapshot.
            if not UnitAffectingCombat("player") then
                RunProbeBattery(addon, "ZONE:" .. (GetZoneText() or "?"))
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            cycles = cycles + 1
            -- No battery at entry: measured 2026-07-24 that secrecy latches
            -- mid-combat, so at-entry reads look plain and prove nothing.
            ProbeLogEmit(string.format("===== COMBAT-ENTER#%d @ %.1f (marker only) =====", cycles, GetTime()))
            -- +4s catches short pulls (a 7.5s pull missed the +10s window entirely);
            -- castCount going SECRET inside the same snapshot marks whether
            -- restrictions had latched, so an early read cannot mislead.
            for _, delay in ipairs({ 4, 10 }) do
                C_Timer.After(delay, function()
                    if DebugCommands._probeSession and UnitAffectingCombat("player") then
                        RunProbeBattery(addon, "COMBAT+" .. delay .. "s#" .. cycles)
                    end
                end)
            end
        else
            RunProbeBattery(addon, "COMBAT-EXIT#" .. cycles)
            if cycles >= 20 then
                addon:Print("audit: 20 combat cycles captured - auto-stopping.")
                DebugCommands.ProbeSession(addon, "off")
            end
        end
    end)

    -- Change-only 1/s watcher for rare-edge booleans: a 110s boss fight gets only
    -- +4s/+10s battery snapshots, so a mid-fight low-health dip or damage edge is
    -- invisible to sampling. This logs TRANSITIONS only (a handful of lines/fight).
    local edgeState = {}
    local function edgeSample()
        local walk2 = FramePath
        local reads = {
            lowHealth = function() return LowHealthFrame and LowHealthFrame:IsShown() end,
            animLoss = function()
                local fr = walk2("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain",
                    "HealthBarsContainer", "PlayerFrameHealthBarAnimatedLoss")
                return fr and fr:IsShown()
            end,
            powerCapped = function()
                local a = walk2("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain",
                    "ManaBarArea", "ManaBar", "FullPowerFrame", "PulseFrame", "PulseAnim")
                return a and a:IsPlaying()
            end,
            -- Polled, not event-driven: settles whether slows appear in the LoC data
            -- at all. Locwatch is armed on LOSS_OF_CONTROL_ADDED - if slows never
            -- fire that event, only a poll can see them. If this stays 0 while the
            -- player is visibly slowed, slows are NOT in LoC data and the fallback
            -- ladder (DB2 aura-type-33 list) is the only route.
            locCount = function()
                return C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount
                    and C_LossOfControl.GetActiveLossOfControlDataCount() or 0
            end,
            -- IsPlayerMoving: unannotated in the 68887 docs = plain always (verify -
            -- annotation gaps have lied before). Pairs with speedBand: moving+slow<5
            -- sustained = slowed; roots don't need this (ROOT is a real LoC type).
            moving = function() return IsPlayerMoving() end,
            -- Dead-reckoning speed band (validated feasible 15:31 session: UnitPosition
            -- plain+live in delve combat). Base run 7 yd/s, cat ~9.8; a slow while
            -- trying to move shows as run->slow band transitions. Heuristic only -
            -- backpedal (~4.5 yd/s) and /walk also land in slow<5, so a feature
            -- trigger must require the band to persist while moving.
            speedBand = function()
                local y, x = UnitPosition("player")
                local t = GetTime()
                local movingNow = IsPlayerMoving() == true
                local prev = edgeState._pos
                edgeState._pos = y and { y = y, x = x, t = t, moving = movingNow } or nil
                if not (y and prev) then return "n/a" end
                -- Only a delta whose WHOLE window was spent moving measures travel
                -- speed. Measured 18:56 session: combat stutter-stepping at 1s
                -- sampling aliases into phantom slow/still readings - a window with
                -- a stationary half-second reads as slow<5 while unimpaired.
                if not (movingNow and prev.moving) then return "idle" end
                local dt = t - prev.t
                if dt <= 0 or dt > 3 then return "idle" end
                local v = math.sqrt((y - prev.y) ^ 2 + (x - prev.x) ^ 2) / dt
                if v < 5 then return "slow<5"
                elseif v < 9 then return "run5-9"
                else return "fast>9" end
            end,
        }
        for key, fn in pairs(reads) do
            local ok, v = pcall(fn)
            if not ok then v = false end
            -- numbers and strings (speedBand) compare as-is; everything else -> boolean
            if type(v) ~= "number" and type(v) ~= "string" then v = (v == true) end
            if edgeState[key] ~= nil and edgeState[key] ~= v then
                ProbeLogEmit(string.format("EDGE %.1f %s: %s -> %s combat=%s",
                    GetTime(), key, tostring(edgeState[key]), tostring(v),
                    tostring(UnitAffectingCombat("player"))))
            end
            edgeState[key] = v
        end
    end
    DebugCommands._probeTicker = C_Timer.NewTicker(1.0, function() pcall(edgeSample) end)

    ProbeLogEmit(string.format("========== AUDIT SESSION ARMED %s (build %s) ==========",
        date("%Y-%m-%d %H:%M:%S"), (GetBuildInfo())))
    RunProbeBattery(addon, "BASELINE", true)
    -- Arm the event captures with output into the log.
    if not DebugCommands._locWatch then DebugCommands.LossOfControlWatch(LogProxy(addon)) end
    if not DebugCommands._selfCast then DebugCommands.SelfCastProbe(LogProxy(addon)) end
    addon:Print("|cff00ff00=== audit ARMED ===|r Baseline captured. Now just fight: enter/exit combat a few times,")
    addon:Print("get CC'd/dazed if you can, cast + channel, get hurt, cap a resource. Snapshots are automatic.")
    addon:Print("|cff888888  For the engine-signal leg: keep a debuffed target, kick something, and take a shield/absorb.|r")
    addon:Print("|cffffff00Then: /jac inspect audit off  ->  /reload|r  (log lands in SavedVariables/JustAC.lua)")
end

--------------------------------------------------------------------------------
-- /jac inspect glows - inventory every VISIBLE frame overlapping the defensive
-- cluster / resource-bar region, with its texture regions. Built for the
-- "orphan glow floating near the queue" class of report: run it WHILE the
-- artifact is on screen and the listing names the frame, its owner chain, its
-- texture atlas (which identifies the glow style at a glance), and whether its
-- alpha aspect is ENGINE-OWNED (HasSecretAspect) - the one mechanism in this
-- addon that can hold a frame visible against a manual SetAlpha(0).
--------------------------------------------------------------------------------
function DebugCommands.GlowInventory(addon)
    local function plainNum(x)
        return type(x) == "number" and not IsSecret(x)
    end

    -- Our anchor frames: rect sources for the search box, and ancestry roots
    -- for the ours/foreign tag.
    local roots, sources = {}, {}
    local function AddRoot(f)
        if f then roots[f] = true; sources[#sources + 1] = f end
    end
    local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
    AddRoot(UIHealthBar and UIHealthBar.GetFrame and UIHealthBar.GetFrame())
    AddRoot(addon.maintenanceIcon)
    AddRoot(addon.defensiveFrame)
    AddRoot(addon.interruptIcon)
    if addon.interruptIcon then AddRoot(addon.interruptIcon.sootheCue) end
    for _, icon in ipairs(addon.defensiveIcons or {}) do AddRoot(icon) end
    for _, icon in ipairs(addon.spellIcons or {}) do AddRoot(icon) end

    local L, B, R, T
    for _, f in ipairs(sources) do
        local ok, l, b, w, h = pcall(f.GetRect, f)
        if ok and plainNum(l) and plainNum(b) and plainNum(w) and plainNum(h) then
            if not L or l < L then L = l end
            if not B or b < B then B = b end
            if not R or l + w > R then R = l + w end
            if not T or b + h > T then T = b + h end
        end
    end
    if not L then
        addon:Print("glows: no placeable anchor frames (displays disabled?) - nothing to search around")
        return
    end
    local PAD = 90
    L, B, R, T = L - PAD, B - PAD, R + PAD, T + PAD
    addon:Print(string.format("|cff00ff00=== glow inventory ===|r box (%.0f,%.0f)-(%.0f,%.0f) - run WHILE the artifact is visible", L, B, R, T))

    local function IsOurs(f)
        local depth = 0
        while f and depth < 12 do
            if roots[f] then return true end
            local ok, p = pcall(f.GetParent, f)
            f = ok and p or nil
            depth = depth + 1
        end
        return false
    end
    local function Label(f)
        local ok, n = pcall(f.GetName, f)
        if ok and n then return n end
        local okT, t = pcall(f.GetObjectType, f)
        return "(anon " .. (okT and t or "?") .. ")"
    end

    local hits, ourSecretRect, printed = 0, 0, 0
    local f = EnumerateFrames()
    while f do
        local okF, forbidden = pcall(f.IsForbidden, f)
        local okV, vis = pcall(f.IsVisible, f)
        if okF and not forbidden and okV and vis == true then
            local ok, l, b, w, h = pcall(f.GetRect, f)
            if not (ok and plainNum(l) and plainNum(b) and plainNum(w) and plainNum(h)) then
                -- Visible but unplaceable: only interesting if it is one of ours.
                if IsOurs(f) then
                    ourSecretRect = ourSecretRect + 1
                    addon:Print("|cffff6600OURS, SECRET rect (cannot place):|r " .. Label(f))
                end
            elseif w < 800 and h < 800 and l < R and l + w > L and b < T and b + h > B then
                hits = hits + 1
                if printed < 25 then
                    printed = printed + 1
                    local okA, a = pcall(f.GetAlpha, f)
                    local aStr = (okA and plainNum(a)) and string.format("%.2f", a) or "SECRET"
                    local owned = ""
                    if f.HasSecretAspect and Enum and Enum.SecretAspect and Enum.SecretAspect.Alpha then
                        local okO, o = pcall(f.HasSecretAspect, f, Enum.SecretAspect.Alpha)
                        if okO and o == true then owned = " |cffff6600[alpha ENGINE-OWNED]|r" end
                    end
                    local pChain, p, okP = {}, f, nil
                    for _ = 1, 3 do
                        okP, p = pcall(p.GetParent, p)
                        if not okP or not p then break end
                        pChain[#pChain + 1] = Label(p)
                    end
                    local okS, strata = pcall(f.GetFrameStrata, f)
                    local okLv, lvl = pcall(f.GetFrameLevel, f)
                    addon:Print(string.format("%d) %s%s %dx%d @(%.0f,%.0f) %s/%s a=%s%s < %s",
                        printed, Label(f), IsOurs(f) and " |cff2ecc71(ours)|r" or " |cffcccccc(foreign)|r",
                        w, h, l, b, okS and strata or "?", okLv and tostring(lvl) or "?", aStr, owned,
                        table.concat(pChain, " < ")))
                    local okN, numRegions = pcall(f.GetNumRegions, f)
                    for i = 1, (okN and numRegions or 0) do
                        local r = select(i, f:GetRegions())
                        local okSh, shown = pcall(r.IsShown, r)
                        if okSh and shown == true then
                            local okOT, ot = pcall(r.GetObjectType, r)
                            if okOT and ot == "Texture" then
                                local _, atlas = pcall(r.GetAtlas, r)
                                local _, tex = pcall(r.GetTexture, r)
                                local _, blend = pcall(r.GetBlendMode, r)
                                local what = (type(atlas) == "string" and atlas)
                                    or (type(tex) == "string" and tex)
                                    or (plainNum(tex) and ("fileID " .. tex))
                                    or "?"
                                -- Color forensics: vertex tint + desaturation state identify a
                                -- tinted-glow frame whose desaturation silently failed (cyan
                                -- over the gold base reads as olive/yellow).
                                local okC, vr, vg, vb = pcall(r.GetVertexColor, r)
                                local col = (okC and plainNum(vr) and plainNum(vg) and plainNum(vb))
                                    and string.format("%.2f,%.2f,%.2f", vr, vg, vb) or "secret"
                                local okD, desat = pcall(r.IsDesaturated, r)
                                addon:Print(string.format("     tex: %s (%s) tint=%s desat=%s", what,
                                    tostring(blend), col, okD and tostring(desat) or "?"))
                            end
                        end
                    end
                end
            end
        end
        f = EnumerateFrames(f)
    end
    addon:Print(string.format("=== %d visible frame(s) in the box, %d printed%s ===",
        hits, printed, ourSecretRect > 0 and (", " .. ourSecretRect .. " ours-with-secret-rect") or ""))
end

--------------------------------------------------------------------------------
-- /jac inspect groupbuff - verbose mirror of the pre-combat "party member is
-- missing my raid buff" detection (PrecombatEngine.PartyMemberMissingBuff),
-- showing every gate's actual answer per member: the readable-boolean probes
-- (nil = SECRET = member skipped), the aura-scan outcome, and where a secret
-- spellId forced the fail-silent bail. Run it when the recast nudge seems
-- wrong (nagging while everyone is buffed / silent while someone is not).
--------------------------------------------------------------------------------
function DebugCommands.GroupBuffProbe(addon)
    -- No file-local BlizzardAPI in this file - resolve it, or every gated
    -- BlizzardAPI.* read below silently short-circuits to nil.
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local function RB(v)  -- ReadableBool: true/false when plain, "SECRET" when not
        if v == nil then return "nil" end
        if IsSecret(v) then return "SECRET" end
        return v and "T" or "F"
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local class = select(2, UnitClass("player"))
    local groups = SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS and SpellDB.CLASS_MAINTAINED_BUFFS[class]

    -- ENGINE REGISTRY vs CURATED TABLE (12.1.0+). The whole reason to adopt
    -- GetGroupBuffItems is that curation cannot keep up with patches, so the useful
    -- output is the DIFFERENCE: an engine entry the curated groups do not claim is
    -- coverage we only get from the engine, and a curated group with no engine
    -- counterpart is either an aura-variant detail the registry omits or curation
    -- that has gone stale.
    local engine = BlizzardAPI and BlizzardAPI.GetGroupBuffItems and BlizzardAPI.GetGroupBuffItems()
    if not engine then
        addon:Print("|cff888888engine registry: C_CooldownViewer.GetGroupBuffItems unavailable"
            .. " (pre-12.1.0) - curated table is the only source|r")
    else
        local covered = {}
        for _, grp in ipairs(groups or {}) do
            for _, id in ipairs(grp.group) do covered[id] = true end
            for _, id in ipairs(grp.auraIDs or {}) do covered[id] = true end
        end
        addon:Print(string.format("|cff00ccffengine registry:|r %d entries", #engine))
        for i = 1, #engine do
            local it = engine[i]
            addon:Print(string.format("   %-28s (%d) known=%s hideByDefault=%s  %s",
                tostring(it.name), it.spellID, tostring(it.isKnown), tostring(it.hideByDefault),
                covered[it.spellID] and "|cff888888curated|r"
                    or (it.isKnown and "|cff2ecc71NEW - engine-only coverage|r" or "not known")))
        end
    end
    addon:Print(string.format("|cff00ff00=== group buff probe ===|r class=%s groups=%s inGroup=%s inRaid=%s combat=%s aurasRestricted=%s",
        tostring(class), groups and #groups or 0, RB(IsInGroup()), RB(IsInRaid()),
        tostring(InCombatLockdown()), tostring(BlizzardAPI and BlizzardAPI.AreAurasSecret and BlizzardAPI.AreAurasSecret())))
    if not groups then return end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for gi, grp in ipairs(groups) do
        local family = grp.auraIDs or grp.group
        local famStr = table.concat(family, "/")
        local active
        for _, spellID in ipairs(grp.group) do
            if IsPlayerSpell(spellID) and get then
                local a = get(spellID)
                if not a and grp.auraIDs then
                    for _, auraID in ipairs(grp.auraIDs) do
                        a = get(auraID); if a then break end
                    end
                end
                if a then active = spellID break end
            end
        end
        addon:Print(string.format("group %d [%s] raidWide=%s: player active=%s",
            gi, famStr, tostring(grp.raidWide or false), tostring(active)))
        if grp.raidWide then
            for i = 1, 4 do
                local unit = "party" .. i
                local okE, ex = pcall(UnitExists, unit)
                if okE and ex == true then
                    local okN, name = pcall(UnitName, unit)
                    local okP, isPlayer = pcall(UnitIsPlayer, unit)
                    local okC, conn = pcall(UnitIsConnected, unit)
                    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
                    local okR, inRange = pcall(UnitInRange, unit)
                    -- Every gate reduced to a plain STRING once; all verdicts below compare
                    -- strings, never the raw returns (a secret boolean burns any == test -
                    -- this very probe learned that in the field).
                    local connS  = okC and RB(conn) or "err"
                    local deadS  = okD and RB(dead) or "err"
                    local urS    = okR and RB(inRange) or "err"
                    local srS    = "n/a"
                    if active and C_Spell and C_Spell.IsSpellInRange then
                        local okS, sr = pcall(C_Spell.IsSpellInRange, active, unit)
                        srS = okS and RB(sr) or "err"
                    end
                    -- Point queries per family id: the real detection's primary probe now.
                    local pq = "n/a"
                    local byId = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
                    if byId then
                        pq = "ABSENT"
                        for _, fid in ipairs(family) do
                            local okQ, data = pcall(byId, unit, fid)
                            if okQ and data ~= nil then pq = "HAS " .. fid; break end
                            if not okQ then pq = "THROW"; break end
                        end
                    end
                    local auras = BlizzardAPI and BlizzardAPI.GetAuras and BlizzardAPI.GetAuras(unit, "HELPFUL")
                    local scan, secretAt, found = "no-auras", nil, nil
                    if auras then
                        scan = "MISSING"
                        for ai = 1, #auras do
                            local sid = auras[ai].spellId
                            if sid == nil or IsSecret(sid) then
                                secretAt = ai; scan = "BAIL(secret id)"; break
                            end
                            for _, fid in ipairs(family) do
                                if sid == fid then found = sid; scan = "HAS"; break end
                            end
                            if found then break end
                        end
                    end
                    local playerS = okP and RB(isPlayer) or "err"
                    addon:Print(string.format("  %s (%s): isPlayer=%s conn=%s dead=%s unitRange=%s spellRange=%s pointQuery=%s bulk=%s(%s)%s%s",
                        unit, (okN and name) or "?", playerS, connS, deadS,
                        urS, srS, pq, scan, auras and #auras or "nil",
                        found and (" " .. found) or "", secretAt and (" @" .. secretAt) or ""))
                    -- The real check's verdict for this member (new gates: NPCs excluded,
                    -- spell-range preferred over unit-range, point query over bulk scan):
                    local rangeOK = (srS == "T") or (srS ~= "F" and urS == "T")
                    local counted = playerS == "T" and connS == "T" and deadS == "F" and rangeOK
                    local missing = (pq == "ABSENT") or (pq ~= "n/a" and pq == "THROW" and scan == "MISSING")
                        or (pq == "n/a" and scan == "MISSING")
                    if counted and missing then
                        addon:Print("     |cffff6600-> this member triggers the recast nudge|r")
                    elseif not counted then
                        addon:Print("     |cff888888-> skipped by gates (not counted either way)|r")
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- /jac inspect textlaunder - test the FontString SetText->GetText laundering
-- claim (seen in a Midnight-native frames addon: "SetText accepts a secret
-- string, GetText() hands back a PLAIN string"). Our continuous-read sweep
-- concluded the opposite (Text aspect goes secret permanently). Three possible
-- verdicts, in descending order of consequence:
--   LAUNDERS   - GetText returns a PLAIN readable string: reopens the whole
--                continuous-read family. (Expect Blizzard to patch it.)
--   ZERO-GATE  - GetText returns a SECRET string, but `not result` is safe
--                (documented non-boolean truthiness rule) and empty text
--                collapses to plain nil: a legal presence/zero detector.
--   SEALED     - readback secret and truthiness throws: sweep verdict stands.
-- Run IN COMBAT with a target (or in a follower dungeon: NPC ally max-health
-- reads secret even out of combat).
--------------------------------------------------------------------------------
function DebugCommands.TextLaunderProbe(addon)
    if not issecretvalue then
        addon:Print("textlaunder: no issecretvalue on this client - nothing to test")
        return
    end

    -- Find a live secret value to feed the widget.
    local candidates = {
        { "UnitHealth(target)",     function() return UnitHealth("target") end },
        { "UnitHealthMax(target)",  function() return UnitHealthMax("target") end },
        { "UnitHealth(player)",     function() return UnitHealth("player") end },
        { "UnitHealthMax(party1)",  function() return UnitHealthMax("party1") end },
        { "UnitPower(player)",      function() return UnitPower("player") end },
    }
    local srcName, secretVal
    for _, c in ipairs(candidates) do
        local ok, v = pcall(c[2])
        if ok and v ~= nil and IsSecret(v) then
            srcName, secretVal = c[1], v
            break
        end
    end
    addon:Print("|cff00ff00=== text launder probe ===|r")
    if not secretVal then
        addon:Print("no SECRET source available here (all candidate reads plain) - get in combat with a target, or stand in a follower dungeon party, and rerun")
        return
    end
    addon:Print("secret source: " .. srcName)

    -- Secret-safe formatter for chat output: tostring() and string.format("%s")
    -- PROPAGATE secrecy silently (field-measured 2026-08-10 - the poisoned string
    -- sailed through both and only blew up in the chat library's table.concat),
    -- so every possibly-secret value must be reduced HERE, before the message.
    local function safe(v)
        if v ~= nil and IsSecret(v) then return "<SECRET " .. type(v) .. ">" end
        return tostring(v)
    end

    -- FRESH FontString every run: the Text aspect is STICKY - one secret SetText
    -- poisons the widget so even a plain "42" reads back secret forever after
    -- (field-measured: a pooled scratch widget failed its own control on re-run).
    -- A leaked FontString per probe run is an acceptable debug cost.
    if not DebugCommands._launderHolder then
        DebugCommands._launderHolder = CreateFrame("Frame")
        DebugCommands._launderHolder:Hide()
    end
    local fs = DebugCommands._launderHolder:CreateFontString(nil, "ARTWORK", "GameFontNormal")

    -- Control on the fresh widget: plain round-trip must be plain.
    fs:SetText("42")
    local ctrl = fs:GetText()
    addon:Print(string.format("control (fresh widget): GetText() = %s (secret=%s)",
        safe(ctrl), tostring(ctrl ~= nil and IsSecret(ctrl) or false)))

    -- Leg 1: secret in, what comes out?
    local okSet = pcall(fs.SetText, fs, secretVal)
    addon:Print("SetText(secret): " .. (okSet and "accepted" or "REJECTED (threw)"))
    if not okSet then
        addon:Print("|cffff6600verdict: SEALED at the door - SetText no longer accepts this secret|r")
        return
    end
    local aspect = "n/a"
    if fs.HasSecretAspect and Enum and Enum.SecretAspect and Enum.SecretAspect.Text then
        local okA, a = pcall(fs.HasSecretAspect, fs, Enum.SecretAspect.Text)
        aspect = okA and tostring(a) or "err"
    end
    local okGet, back = pcall(fs.GetText, fs)
    if not okGet then
        addon:Print("GetText() THREW - aspect=" .. aspect)
        addon:Print("|cffff6600verdict: SEALED (readback itself is blocked)|r")
        return
    end
    local backSecret = back ~= nil and IsSecret(back) or false
    addon:Print(string.format("GetText(): type=%s secret=%s aspect(Text)=%s value=%s",
        type(back), tostring(backSecret), aspect, safe(back)))

    if back ~= nil and not backSecret then
        addon:Print("|cffff0000verdict: LAUNDERS - plain readback of a secret. The continuous-read family just reopened; expect this to be patched, build nothing load-bearing on it.|r")
        return
    end

    -- Leg 2: secret readback - is the documented truthiness rule usable on it?
    local okTruth, truthy = pcall(function() return not back end)
    addon:Print(string.format("truthiness test (`not result`): %s -> %s",
        okTruth and "SAFE" or "THREW", okTruth and safe(truthy) or "-"))

    -- Leg 3: empty-collapse on the POISONED widget - does empty text read back
    -- as plain nil (the zero-detector's load-bearing half)?
    fs:SetText("")
    local emptyBack = fs:GetText()
    addon:Print(string.format("empty-collapse: SetText('') -> GetText() = %s (secret=%s)",
        safe(emptyBack), tostring(emptyBack ~= nil and IsSecret(emptyBack) or false)))

    -- Leg 4: stickiness - plain write to the poisoned widget.
    fs:SetText("42")
    local sticky = fs:GetText()
    addon:Print(string.format("sticky-aspect: plain '42' into poisoned widget -> secret=%s",
        tostring(sticky ~= nil and IsSecret(sticky) or false)))

    if okTruth and emptyBack == nil then
        addon:Print("|cffffff00verdict: ZERO-GATE - readback stays secret but presence/absence is branchable (truthiness + plain-nil empty-collapse). A legal zero-detector, not a laundering hole.|r")
    elseif okTruth then
        addon:Print("|cffffff00verdict: PARTIAL - truthiness is safe on the readback, but empty text does not collapse to plain nil, so the zero-detector needs the truthiness leg alone.|r")
    else
        addon:Print("|cff888888verdict: SEALED - readback secret and truthiness blocked; the sweep's conclusion stands.|r")
    end

    -- Applied check: the top-off feature's live gate. Run this AT FULL HEALTH -
    -- expect true (verifies the engine treats the deficit API's "-0 at full"
    -- quirk as zero); hurt yourself and rerun - expect false.
    -- This file has NO file-local BlizzardAPI - resolve it here (a bare reference
    -- is a nil global and silently skipped this whole block once already).
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    -- The gate's own self-check, as the LIVE gate sees it right now. The legs above test
    -- the mechanism on a throwaway widget; this is whether IsSecretZero currently trusts
    -- its readback enough to answer at all. They can disagree: if this says NO, every
    -- zero-gate answer in the addon is nil and ~29 threshold sites are on their fallbacks
    -- - which is the correct behaviour, but silent without this line.
    if BAPI and BAPI.IsTextReadbackWorking then
        local live = BAPI.IsTextReadbackWorking()
        addon:Print("live gate self-check: GetText readback "
            .. (live and "|cff2ecc71answers|r - zero-gate trusted"
                     or "|cffff0000DEAD|r - zero-gate returns nil, everything is on fallbacks"))
    end
    if not UnitHealthMissing then
        addon:Print("applied: SKIPPED - UnitHealthMissing API not present on this client")
    elseif not (BAPI and BAPI.IsSecretZero) then
        addon:Print("applied: SKIPPED - BlizzardAPI.IsSecretZero unavailable")
    else
        local missing = UnitHealthMissing("player")
        local atFull
        if missing ~= nil then atFull = BAPI.IsSecretZero(missing) end
        addon:Print(string.format("applied: IsSecretZero(UnitHealthMissing(player)) = %s  (at full: expect true)",
            tostring(atFull)))
        -- Every shipped zero-gate consumer, exercised together.
        addon:Print(string.format("  IsUnitFullHealth: player=%s pet=%s",
            tostring(BAPI.IsUnitFullHealth and BAPI.IsUnitFullHealth("player")),
            tostring(BAPI.IsUnitFullHealth and BAPI.IsUnitFullHealth("pet"))))
        addon:Print(string.format("  IsHealingUnneeded (glow + ordering gate) = %s   [partyLow=%s]",
            tostring(BAPI.IsHealingUnneeded and BAPI.IsHealingUnneeded()),
            tostring(BAPI.GetPartyLowCount and BAPI.GetPartyLowCount())))
        -- Curve shape + DOMAIN, proved with plain inputs only (Evaluate takes an
        -- ordinary number). A threshold-80 curve must read 100 below the line and
        -- 0 above it. Whichever of the 0-1 / 0-100 pairs behaves that way is the
        -- domain UnitHealthPercent feeds the curve.
        local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
        if cu and cu.CreateCurve and Enum and Enum.LuaCurveType then
            local okC, c = pcall(cu.CreateCurve)
            if okC and c then
                pcall(c.SetType, c, Enum.LuaCurveType.Linear)
                pcall(c.AddPoint, c, 0, 100)
                pcall(c.AddPoint, c, 0.799, 100)
                pcall(c.AddPoint, c, 0.801, 0)
                pcall(c.AddPoint, c, 1, 0)
                local function ev(x)
                    local ok, y = pcall(c.Evaluate, c, x)
                    return ok and tostring(y) or "err"
                end
                addon:Print(string.format("  curve self-test (t=80): as fraction E(.75)=%s E(.85)=%s | as percent E(75)=%s E(85)=%s",
                    ev(0.75), ev(0.85), ev(75), ev(85)))
            end
        end
        -- Curve-encoded threshold gate: the engine compares, we read zero-ness.
        -- At full health every line should read false; hurt yourself and they
        -- flip to true one band at a time as you drop past each percentage.
        -- nil here = the curve failed its own self-test and callers fell back.
        if BAPI.IsUnitHealthBelow then
            local yourPct = addon.db and addon.db.profile and addon.db.profile.precombatBuffs
                and addon.db.profile.precombatBuffs.topoffThreshold
            addon:Print(string.format("  IsUnitHealthBelow(player): 95=%s 90=%s 50=%s 35=%s | YOUR top-off %s=%s",
                tostring(BAPI.IsUnitHealthBelow("player", 95)),
                tostring(BAPI.IsUnitHealthBelow("player", 90)),
                tostring(BAPI.IsUnitHealthBelow("player", 50)),
                tostring(BAPI.IsUnitHealthBelow("player", 35)),
                tostring(yourPct or "unset"),
                tostring(yourPct and BAPI.IsUnitHealthBelow("player", yourPct))))
            if UnitExists("target") then
                addon:Print(string.format("  IsUnitHealthBelow(target): 90=%s 35=%s 20=%s",
                    tostring(BAPI.IsUnitHealthBelow("target", 90)),
                    tostring(BAPI.IsUnitHealthBelow("target", 35)),
                    tostring(BAPI.IsUnitHealthBelow("target", 20))))
            end
        end
        -- Power gate + bands. Spend some resource before running this: the
        -- power lines should flip as you cross each percentage, and the band
        -- number should climb as you regenerate (1 = below the first boundary).
        if BAPI.IsUnitPowerBelow then
            addon:Print(string.format("  IsUnitPowerBelow(player): 90=%s 50=%s 20=%s | band{20,50,90}=%s",
                tostring(BAPI.IsUnitPowerBelow("player", 90)),
                tostring(BAPI.IsUnitPowerBelow("player", 50)),
                tostring(BAPI.IsUnitPowerBelow("player", 20)),
                tostring(BAPI.GetPowerBand and BAPI.GetPowerBand("player", {20, 50, 90}))))
        end
        if BAPI.GetHealthBand then
            -- The boundaries the DEFENSIVE CLUSTER actually uses, asked for rather
            -- than hardcoded: a demo band would keep printing happily after the
            -- production one moved, and the whole point of this line is to check
            -- the live layer.
            local DE = LibStub("JustAC-DefensiveEngine", true)
            local bounds = DE and DE.GetHealthBandInfo and select(3, DE.GetHealthBandInfo())
                or { 35, 80 }
            addon:Print(string.format("  GetHealthBand{%s}: player=%s target=%s  (1 = below the first boundary; %d = above the last)",
                table.concat(bounds, ","),
                tostring(BAPI.GetHealthBand("player", bounds)),
                UnitExists("target") and tostring(BAPI.GetHealthBand("target", bounds)) or "no target",
                #bounds + 1))
        end
        addon:Print(string.format("  UnitHasAbsorb: target=%s player=%s  (new capability - shield on ANY unit)",
            tostring(BAPI.UnitHasAbsorb and BAPI.UnitHasAbsorb("target")),
            tostring(BAPI.UnitHasAbsorb and BAPI.UnitHasAbsorb("player"))))
        -- Stack gate: first player buff carrying an instance id, asked ">= 2".
        local auras = BAPI.GetAuras and BAPI.GetAuras("player", "HELPFUL")
        local inst = auras and auras[1] and auras[1].auraInstanceID
        if inst and BAPI.AuraStacksAtLeast then
            addon:Print(string.format("  AuraStacksAtLeast(player, first buff, 2) = %s",
                tostring(BAPI.AuraStacksAtLeast("player", inst, 2))))
        end
    end
end

--------------------------------------------------------------------------------
-- /jac inspect timeline - can we see a BIG HIT coming?
--
-- C_EncounterTimeline is Blizzard's own boss-mechanic timeline and JustAC does not
-- touch it. Every defensive decision the addon makes today is REACTIVE - inferred
-- from health that has already dropped. "Something lands in 3 seconds" is a
-- different category of signal, and the access rules are unusually generous:
--
--   PLAIN (no restriction):  IsFeatureEnabled, HasActiveEvents, GetEventList,
--                            GetSortedEventList, GetEventHighlightTime, GetEventTrack
--   NeverSecret FIELDS:      info.id, info.source, info.duration, info.maxQueueDuration
--   SECRET in an encounter:  info.spellID, info.spellName, info.icons, info.severity
--
-- So TIMING is readable and CLASSIFICATION is not. GetSortedEventList takes a
-- maxEventDuration filter, which makes "how many events land within N seconds" a
-- plain count - branchable with no curve at all.
--
-- CLASSIFICATION IS A CLOSED QUESTION - do not spend a raid night on it. This
-- comment used to say GetEventColor was "shaped exactly like GetAuraDispelTypeColor"
-- and that the Enrage selector-curve trick should transfer. It is not and it does
-- not: the real signature is GetEventColor(eventID, overrideTrigger) - there is NO
-- curve parameter to pass - and it carries SecretArguments = "NotAllowed" plus
-- SecretWhenEncounterEvent, so the return is secret on exactly the events we care
-- about and we cannot hand it a selector either. The dispel-type route needed BOTH
-- halves; neither is here.
--
-- So this probe measures the TIMING signal, which is the half that works.
--------------------------------------------------------------------------------
function DebugCommands.EncounterTimelineProbe(addon)
    local ET = C_EncounterTimeline ---@diagnostic disable-line: undefined-global
    addon:Print("|cff00ccff== encounter timeline probe ==|r")
    if not ET then
        addon:Print("|cffff6600C_EncounterTimeline unavailable on this client|r")
        return
    end
    local function call(name, ...)
        local fn = ET[name]
        if not fn then return nil, "absent" end
        local ok, a, b = pcall(fn, ...)
        if not ok then return nil, "THREW" end
        return a, nil, b
    end
    local enabled = call("IsFeatureEnabled")
    local active  = call("HasActiveEvents")
    addon:Print(string.format("feature enabled=%s  active events=%s  highlight lead=%ss",
        tostring(enabled), tostring(active), tostring(call("GetEventHighlightTime"))))
    if enabled ~= true then
        addon:Print("|cff888888Feature off or unavailable - the rest needs it on, in an encounter.|r")
    end

    -- THE BRANCHABLE TIMING SIGNAL. A count of events inside a window, with no
    -- curve and no secret: this alone is enough to raise defensive priority.
    --
    -- Arg 4 is excludeHiddenEvents and it is FALSE on purpose. It defaults to true,
    -- which drops events the user's own display settings hide (long countdowns, say).
    -- That is right for drawing a timeline and wrong for asking "is something about
    -- to hit me" - a mechanic does not stop landing because it was scrolled off a
    -- bar. Passing true here under-reported the danger and the count silently
    -- depended on a display preference.
    -- Arg 3 is excludeTerminalStates, left TRUE: Canceled/Finished events are not
    -- coming, and dropping them is what makes a paused mechanic fall out of the
    -- window on its own with no state for us to hold.
    --
    -- source == Encounter (0) filters to mechanics the INSTANCE scripted. Script (1)
    -- and EditMode (2) are entries any addon can add - counting those would let one
    -- addon's decorative timeline drive our defensive priority. `source` is
    -- NeverSecret, so the compare is safe.
    -- IsEventBlocked drops mechanics whose cast conditions are not met.
    local function DangerCount(window)
        local list = call("GetSortedEventList", nil, window, true, false)
        if type(list) ~= "table" then return nil, nil end
        local real, blocked = 0, 0
        for i = 1, #list do
            local id = list[i]
            local info = call("GetEventInfo", id)
            if info and info.source == 0 then
                if call("IsEventBlocked", id) == true then blocked = blocked + 1
                else real = real + 1 end
            end
        end
        return real, blocked, #list
    end
    for _, window in ipairs({ 3, 5, 10 }) do
        local real, blocked, raw = DangerCount(window)
        addon:Print(string.format("  events within %2ds: %s encounter%s%s%s", window,
            tostring(real),
            (blocked and blocked > 0) and string.format(" (+%d blocked)", blocked) or "",
            (raw and real and raw ~= real) and string.format("  |cff888888[%d total incl. script/editmode]|r", raw) or "",
            (real and real > 0) and "  |cffff8800<- something is coming|r" or ""))
    end

    local list = call("GetSortedEventList", 4, 30, true, false)
    if type(list) ~= "table" or #list == 0 then
        addon:Print("|cff888888No events on the timeline right now - run this during a boss fight.|r")
        return
    end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("|cffffff00-- per-event: which fields survive, and does the timer gate? --|r")
    for i = 1, #list do
        local id = list[i]
        local info = call("GetEventInfo", id)
        local track = call("GetEventTrack", id)
        -- Per-field secrecy: id/source/duration/maxQueueDuration are NeverSecret,
        -- the rest are not. Reduce each to a word rather than printing it - a
        -- tostring on a secret would propagate secrecy into the chat message.
        local function field(v)
            if v == nil then return "nil" end
            if BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v) then return "|cffff6600secret|r" end
            return "|cff2ecc71" .. tostring(v) .. "|r"
        end
        addon:Print(string.format("  #%d track=%s src=%s blocked=%s  dur=%s  severity=%s  icons=%s  spellID=%s",
            i, tostring(track),
            field(info and info.source), tostring(call("IsEventBlocked", id)),
            field(info and info.duration), field(info and info.severity),
            field(info and info.icons), field(info and info.spellID)))
        -- Does the event's own timer threshold-gate like every other duration?
        local timer = call("GetEventTimer", id)
        if timer and BAPI and BAPI.IsDurationBelowSeconds then
            addon:Print(string.format("     timer: <3s=%s  <8s=%s",
                tostring(BAPI.IsDurationBelowSeconds(timer, 3)),
                tostring(BAPI.IsDurationBelowSeconds(timer, 8))))
        end
    end
    addon:Print("|cff00ccffWhat to look for:|r dur/src/blocked print |cff2ecc71green|r - that is the"
        .. " whole usable signal, and the encounter count above is what a defensive would key off."
        .. " severity/icons/spellID printing |cffff6600secret|r is EXPECTED and has no workaround"
        .. " (see the header); it means we can know WHEN, never WHAT.")
    addon:Print("|cff888888Scope: instance bosses only - no trash, no open world, no dummy. A zero"
        .. " count outside an encounter means 'unsupported here', never 'safe'.|r")
end

--------------------------------------------------------------------------------
-- /jac inspect durcurve [spellID] - can a DURATION be threshold-gated?
--
-- The question: LuaDurationObject:EvaluateRemainingPercent(curve, modifier) carries
-- the same annotation pair as UnitHealthPercent - SecretWhenCurveSecret, and
-- SecretArguments AllowedWhenUntainted - which is the exact API the working health
-- threshold gate rides. If the composition transfers, "is this aura/cooldown below
-- N% remaining" becomes branchable, and remaining-duration is the single largest
-- class of SimC conditions still delegated (675 `.remains` atoms across the APLs).
--
-- Prior art, and why this is a RE-test rather than a new one: probed in game
-- 2026-07-06, the evaluated result came back issecretvalue()==true in combat, and
-- the path was filed as display-only. That verdict was correct at the time - there
-- was no way to branch on a secret result. The zero-gate is exactly that way, and
-- it did not exist until 2026-08-10. Same API, new tool.
--
-- Two things are unknown and BOTH are measured here, because guessing either wrong
-- produces a confident wrong answer:
--   1. Is the result secret? The 2026-07-06 run says yes, which is the GOOD case:
--      secret plus a working zero-gate is a branchable answer. The doc annotation
--      hints otherwise (no SecretReturns, unlike UnitHealthPercent) - measurement
--      beats inference, so the probe reports whichever it actually finds.
--   2. What is the curve's DOMAIN? UnitHealthPercent turned out to take the 0-1
--      fraction, not 0-100 (an assumption that already cost one invisible icon).
--      So every threshold is asked TWICE - once as a fraction, once as a percent -
--      and only the one matching ground truth is real.
-- Ground truth comes from the scratch-Cooldown IsShown() boolean we already trust
-- (active / not active) plus, out of combat, whatever plain numbers the client hands
-- over. Nothing here writes to a production path.
--------------------------------------------------------------------------------

-- Ramp from `lo` (below the threshold) to 0 at/above it, over an explicit domain.
-- Output 100 rather than 1 for the same reason the production builder does:
-- TruncateWhenZero formats as an integer ROUNDING DOWN, so an interpolated 0.4
-- would floor to zero and read as "above threshold".
local function DurProbeCurve(threshold, hi)
    local cu = C_CurveUtil
    local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
    if not (cu and cu.CreateCurve and linear) then return nil end
    local ok, c = pcall(cu.CreateCurve)
    if not ok or not c then return nil end
    -- Epsilon off the THRESHOLD, not the domain bound. The first version used
    -- hi*0.001, which for a 3600s domain is a 3.6-SECOND epsilon: a 7.2s-wide ramp
    -- masquerading as a step, so the "threshold" columns returned interpolated
    -- values instead of 100/0. (That accident is what exposed the value leak the
    -- reveal ramp below now measures on purpose.)
    local eps = math.max(threshold * 0.002, 0.001)
    local okAll = pcall(function()
        c:SetType(linear)
        c:AddPoint(0, 100)
        c:AddPoint(math.max(0, threshold - eps), 100)
        c:AddPoint(threshold + eps, 0)
        c:AddPoint(hi, 0)
    end)
    return okAll and c or nil
end

-- A straight 0..hi -> 0..1000 ramp. Where the evaluated result comes back PLAIN,
-- inverting it recovers the INPUT - i.e. the actual remaining seconds or fraction.
-- DIAGNOSTIC ONLY, and it is here precisely to find out whether that is possible:
-- in combat this should go secret, and the scope rule in StateHelpers means no
-- production path may ever reconstruct a value this way even if it stays plain.
local function DurRevealCurve(hi)
    local cu = C_CurveUtil
    local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
    if not (cu and cu.CreateCurve and linear) then return nil end
    local ok, c = pcall(cu.CreateCurve)
    if not ok or not c then return nil end
    local okAll = pcall(function()
        c:SetType(linear)
        c:AddPoint(0, 0)
        c:AddPoint(hi, 1000)
    end)
    return okAll and c or nil
end

--- Invert the reveal ramp: evaluated -> the input the engine fed it.
--- @return string the recovered value, or why it could not be recovered
local function DurReveal(durObj, method, hi, unit, modifier)
    local curve = DurRevealCurve(hi)
    local fn = curve and durObj and durObj[method]
    if not fn then return "|cff888888n/a|r" end
    local ok, result = pcall(fn, durObj, curve, modifier)
    if not ok then return "|cffff6666THREW|r" end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(result) then
        return "|cff00ff00secret|r"          -- the good outcome: no value leaks
    end
    if type(result) ~= "number" then return tostring(result) end
    return string.format("|cffff6600%.2f%s|r", result / 1000 * hi, unit)
end

--- Evaluate one method with one curve and describe what came back.
--- @return string a single human-readable verdict cell
local function DurProbeCell(durObj, method, curve, modifier)
    local fn = durObj and durObj[method]
    if not fn then return "|cff888888no method|r" end
    local ok, result = pcall(fn, durObj, curve, modifier)
    if not ok then return "|cffff6666THREW|r" end
    if result == nil then return "nil" end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local isSecret = BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(result)
    if not isSecret then
        -- PLAIN. Then the number is readable outright - report it verbatim, since
        -- that is a bigger finding than the gate this probe was written to test.
        return string.format("|cff00ff00PLAIN|r %s", tostring(result))
    end
    local zero = BAPI and BAPI.IsSecretZero and BAPI.IsSecretZero(result)
    if zero == nil then return "secret, |cffff6666zero-gate cannot answer|r" end
    -- Curve is 100 BELOW the threshold and 0 at/above it, so non-zero = below.
    return string.format("secret, below=%s", tostring(not zero))
end

function DebugCommands.DurationCurveProbe(addon, arg)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("|cff00ccff== duration curve probe ==|r")
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
        addon:Print("|cffff6600C_CurveUtil.CreateCurve unavailable - nothing to test|r")
        return
    end
    local RealTime = (Enum and Enum.DurationTimeModifier and Enum.DurationTimeModifier.RealTime) or 0

    -- Source: an explicit spell's cooldown if asked for, else the first player buff
    -- carrying a duration. Both are the SAME object type, so either answers the
    -- question; the aura is preferred because a fresh buff has a known ~100%.
    local durObj, source
    local auraNotes = {}        -- why each aura lookup did not supply the object
    local sid = tonumber(arg)
    local sName = sid and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    sName = (sName and sName.name) or (sid and tostring(sid))
    -- A named spell prefers its own AURA while that aura is up, and falls back to
    -- its cooldown otherwise. Both are duration objects, but only this ordering
    -- makes a CONTROLLED test possible: pick a short self-buff and the same command
    -- measures the buff running down, then the cooldown running down.
    -- Order: player aura, then TARGET aura, then cooldown. The target leg is what
    -- reaches SimC's `dot.`/`debuff.` atoms, which are most of the prize and sit
    -- behind the same aura secrecy predicate as the player's - so a DoT on the
    -- target is the single most representative subject this probe can take.
    if sid and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local lookups = {
            { "player", C_UnitAuras.GetPlayerAuraBySpellID, "BUFF %s (%d) on player" },
            { "target", C_UnitAuras.GetUnitAuraBySpellID,   "DOT/DEBUFF %s (%d) on target" },
        }
        for i = 1, #lookups do
            local unit, getter, label = lookups[i][1], lookups[i][2], lookups[i][3]
            if not getter then
                auraNotes[#auraNotes + 1] = unit .. ": no lookup API"
            elseif unit == "target" and not UnitExists("target") then
                auraNotes[#auraNotes + 1] = "target: no target"
            else
                local okA, aura
                if unit == "player" then okA, aura = pcall(getter, sid)
                else okA, aura = pcall(getter, unit, sid) end
                local inst = okA and aura and aura.auraInstanceID
                if inst then
                    local okD, d = pcall(C_UnitAuras.GetAuraDuration, unit, inst)
                    if okD and d then
                        durObj, source = d, string.format(label, sName, sid)
                        break
                    end
                    auraNotes[#auraNotes + 1] = unit .. ": have instance, GetAuraDuration gave nothing"
                elseif not okA then
                    auraNotes[#auraNotes + 1] = unit .. ": lookup THREW"
                else
                    -- The distinction that matters. GetUnitAuraBySpellID is
                    -- RequiresNonSecretAura: under aura secrecy it returns NO VALUES
                    -- for an aura that is genuinely present, so "absent" and "hidden"
                    -- look identical here. AreAurasSecret is the only thing that
                    -- separates them, and if it is true this is a BLOCKED path, not a
                    -- missing aura - which is a finding, not a failed test.
                    local secret = BAPI and BAPI.AreAurasSecret and BAPI.AreAurasSecret()
                    auraNotes[#auraNotes + 1] = unit .. ": no aura returned ("
                        .. (secret and "|cffffff00UNDECIDABLE - absent OR blocked; aura secrecy is"
                                    .. " on, so a present aura also returns nothing. Re-run naming"
                                    .. " an aura you KNOW is on this unit|r"
                                   or "auras readable, so it is genuinely not applied") .. ")"
                end
            end
        end
    end
    if not durObj and sid and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, sid, true)
        if ok and d then
            durObj, source = d, string.format("COOLDOWN of %s (%d)", sName, sid)
        end
    end
    if not durObj and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local auras = BAPI and BAPI.GetAuras and BAPI.GetAuras("player", "HELPFUL")
        for i = 1, (auras and #auras or 0) do
            local inst = auras[i] and auras[i].auraInstanceID
            if inst then
                local ok, d = pcall(C_UnitAuras.GetAuraDuration, "player", inst)
                if ok and d then
                    durObj = d
                    source = string.format("player buff #%d (auraInstanceID %s)", i, tostring(inst))
                    break
                end
            end
        end
    end
    if not durObj then
        addon:Print("|cffff6600No duration object available.|r Get a buff on yourself, or"
            .. " name a spell you have buffed or on cooldown: /jac inspect durcurve 5217")
        return
    end
    addon:Print("source: " .. source)
    -- Printed whenever an aura leg was tried and did not win. A silent fallthrough
    -- to the cooldown looks exactly like a successful aura test in the output, which
    -- is how a run can appear to pass while measuring something else entirely.
    for i = 1, #auraNotes do
        addon:Print("  |cff888888aura lookup ->|r " .. auraNotes[i])
    end
    if not sid then
        addon:Print("|cff888888(arbitrary buff - for a CONTROLLED test name a short one,"
            .. " e.g. /jac inspect durcurve 5217)|r")
    end

    -- What the object offers, and the baseline we already trust.
    local methods = {}
    for _, m in ipairs({ "EvaluateRemainingPercent", "EvaluateRemainingDuration",
                         "EvaluateElapsedPercent", "EvaluateTotalDuration" }) do
        methods[#methods + 1] = m:gsub("Evaluate", "") .. "=" .. (durObj[m] and "y" or "|cffff6666n|r")
    end
    addon:Print("methods: " .. table.concat(methods, " "))
    addon:Print(string.format("baseline (scratch-Cooldown IsShown, today's boolean): active=%s",
        tostring(BAPI and BAPI.IsDurationObjectActive and BAPI.IsDurationObjectActive(durObj))))
    addon:Print(string.format("in combat: %s  |cff888888(secrecy differs OOC - run this both ways)|r",
        tostring(UnitAffectingCombat("player"))))
    -- PRODUCTION IMPACT CHECK. IsBuffWindowActive takes the very same spellID ->
    -- auraInstanceID hop, and the SimC buff-window gates plus the burst cue's
    -- "window is up" signal ride on it. If that hop is blocked in combat, this
    -- reads false for a buff that IS up - a live bug, not a probe curiosity.
    if sid and BAPI and BAPI.IsBuffWindowActive then
        addon:Print(string.format("production IsBuffWindowActive(%d) = %s  "
            .. "|cff888888(same instance-id hop; if you KNOW this buff is up and this says"
            .. " false, the buff gates are dead in combat)|r",
            sid, tostring(BAPI.IsBuffWindowActive(sid))))
    end

    -- PERCENT methods, asked in BOTH candidate domains. Exactly one column should
    -- track reality; if they agree everywhere the curve is not being evaluated at all.
    addon:Print("|cffffff00-- percent methods: 50% threshold, both domains --|r")
    local frac50, pct50 = DurProbeCurve(0.5, 1), DurProbeCurve(50, 100)
    for _, m in ipairs({ "EvaluateRemainingPercent", "EvaluateElapsedPercent" }) do
        addon:Print(string.format("  %-26s fraction-domain: %s", m,
            frac50 and DurProbeCell(durObj, m, frac50, RealTime) or "curve build failed"))
        addon:Print(string.format("  %-26s percent-domain : %s", "",
            pct50 and DurProbeCell(durObj, m, pct50, RealTime) or "curve build failed"))
    end

    -- SECONDS methods. Domain is unambiguous here, so a working result is the
    -- cleanest possible confirmation: "under 5s left" with no percentage involved.
    addon:Print("|cffffff00-- seconds methods: 5s and 30s thresholds --|r")
    local s5, s30 = DurProbeCurve(5, 3600), DurProbeCurve(30, 3600)
    for _, m in ipairs({ "EvaluateRemainingDuration", "EvaluateTotalDuration" }) do
        addon:Print(string.format("  %-26s <5s: %s", m,
            s5 and DurProbeCell(durObj, m, s5, RealTime) or "curve build failed"))
        addon:Print(string.format("  %-26s <30s: %s", "",
            s30 and DurProbeCell(durObj, m, s30, RealTime) or "curve build failed"))
    end

    -- DIRECT GETTERS AND PREDICATES. Not part of the original question, and worth
    -- more than it: LuaDurationObject carries a whole predicate surface the curve
    -- work never touched.
    --   HasSecretValues is annotated ReturnsNeverSecret - a duration object can be
    --     ASKED whether it holds secrets, instead of us inferring it from a trial
    --     read. If that holds, IsSecretZero's plain-vs-secret branch stops guessing.
    --   IsActive / HasExpired / HasStarted / IsZero carry NO SecretReturns. If they
    --     read plain in combat, IsActive() replaces the scratch-Cooldown
    --     SetCooldownFromDurationObject + IsShown() probe this addon ships today
    --     with one call - the same answer, none of the widget round-trip.
    --   GetRemainingDuration / GetTotalDuration are the raw numbers; expect secret
    --     wherever the reveal ramp below is also secret. Disagreement is the finding.
    -- Measured, NOT trusted: tonight already showed these docs under-describe
    -- secrecy for duration objects (EvaluateRemainingPercent carries no
    -- SecretReturns yet came back secret in combat).
    addon:Print("|cffffff00-- direct getters / predicates --|r")
    local function cell(method)
        local fn = durObj[method]
        if not fn then return method .. "=|cff888888absent|r" end
        local okc, v = pcall(fn, durObj)
        if not okc then return method .. "=|cffff6666THREW|r" end
        local sec = BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v)
        return string.format("%s=%s", method, sec and "|cffff6600secret|r"
            or ("|cff2ecc71" .. tostring(v) .. "|r"))
    end
    addon:Print("  " .. table.concat({
        cell("HasSecretValues"), cell("IsZero"), cell("IsActive"),
    }, "  "))
    addon:Print("  " .. table.concat({
        cell("HasStarted"), cell("HasExpired"),
    }, "  "))
    addon:Print("  " .. table.concat({
        cell("GetRemainingDuration"), cell("GetTotalDuration"), cell("GetRemainingPercent"),
    }, "  "))
    addon:Print("|cff888888  green = plain (branchable). If IsActive is green in combat it"
        .. " supersedes the scratch-Cooldown readiness probe.|r")

    -- REVEAL ROW. A straight ramp inverts back to the engine's own input, so where
    -- the result is plain this prints the ACTUAL remaining time. Two jobs: it makes
    -- every run above interpretable (you can see what state each threshold was
    -- judging), and it is the test for whether a value leaks at all. "secret" here
    -- is the outcome that keeps the threshold gates legitimate.
    addon:Print("|cffffff00-- reveal ramp (diagnostic: does the exact value leak?) --|r")
    addon:Print(string.format("  remaining: %s   total: %s   elapsed%%: %s   remaining%%: %s",
        DurReveal(durObj, "EvaluateRemainingDuration", 3600, "s", RealTime),
        DurReveal(durObj, "EvaluateTotalDuration",     3600, "s", RealTime),
        DurReveal(durObj, "EvaluateElapsedPercent",       1, "",  RealTime),
        DurReveal(durObj, "EvaluateRemainingPercent",     1, "",  RealTime)))

    -- NOT probed, deliberately: UnitHealPredictionCalculator is the other curve
    -- surface, but CreateUnitHealPredictionCalculator takes no unit and the object
    -- is populated with SetPredictedValues, which is AllowedWhenUntainted - addon
    -- code cannot hand it a secret. It computes on numbers we already have, so it
    -- can reveal nothing. A probe there would print a confident meaningless result.

    addon:Print("|cff00ccffReading this:|r PLAIN = the number is readable outright."
        .. "  secret+below=<t/f> = the ZERO-GATE works and durations become gateable."
        .. "  THREW / cannot answer = the composition does not transfer.")
    addon:Print("Cross-check against the baseline above, and re-run at a DIFFERENT"
        .. " remaining time - a column that never changes is not measuring anything.")
end

--------------------------------------------------------------------------------
-- /jac inspect simcgates [st|aoe|cleave] - evaluate this spec's SimC gates live.
-- The verification tool for the threshold layer feeding the rotation: every entry
-- carrying an EVALUABLE gate is listed with the gate's inputs and the verdict the
-- queue acts on, so a wrong gate is visible instead of quietly reordering things.
-- "-"/nil anywhere means unevaluable, which always fails OPEN (never blocks).
-- Countable resource gates are listed but not evaluated here - they need the live
-- point count the queue passes in.
--------------------------------------------------------------------------------
function DebugCommands.SimcGateProbe(addon, arg)
    local RI   = LibStub("JustAC-RotationImport", true)
    local SQ   = LibStub("JustAC-SpellQueue", true)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if not (RI and RI.GetRotationGated and SQ and BAPI) then
        addon:Print("simcgates: modules unavailable")
        return
    end
    local ctx = (arg == "aoe" or arg == "cleave") and arg or "st"
    local blocks = SQ._SimcGateBlocks

    addon:Print(string.format("|cff00ff00=== simc gates (%s) ===|r thresholdGate=%s target=%s",
        ctx, tostring(BAPI.IsThresholdGateAvailable and BAPI.IsThresholdGateAvailable()),
        UnitExists("target") and (UnitName("target") or "?") or "none"))

    -- Real inputs, so the verdict shown is the one the queue actually computes.
    local resCount, resMax, resName
    if BAPI.GetClassResourcePoints then
        resCount, resMax, resName = BAPI.GetClassResourcePoints()
    end
    addon:Print(string.format("  countable resource: %s cur=%s max=%s",
        tostring(resName), tostring(resCount), tostring(resMax)))

    local list = RI.GetRotationGated(ctx) or {}
    local shown, blocked = 0, 0
    for i = 1, #list do
        local e = list[i]
        local gates = e and e.gates
        if gates then
            local parts = {}
            for gi = 1, #gates do
                local g = gates[gi]
                if g.t == "power" then
                    -- Ask the RUNTIME for the threshold rather than recomputing it -
                    -- a probe that mirrors the logic drifts from it.
                    -- Guard THEN call: `local a, b = X and X.fn()` truncates to a single
                    -- value, so `pt` came back nil and UnitPowerMax below was asked for the
                    -- player's PRIMARY power rather than this gate's resource.
                    local pctVal, pt
                    if SQ.PowerGateThreshold then pctVal, pt = SQ.PowerGateThreshold(g) end
                    local below = pctVal and BAPI.IsUnitPowerBelow
                        and BAPI.IsUnitPowerBelow("player", pctVal, pt)
                    parts[#parts + 1] = string.format("%s%s%s%d [max=%s -> %s%%] below=%s",
                        g.res, g.deficit and ".deficit" or "", g.op, g.n,
                        tostring(pt and UnitPowerMax("player", pt)),
                        pctVal and string.format("%.1f", pctVal) or "-", tostring(below))
                elseif g.t == "execute" and g.pct then
                    parts[#parts + 1] = string.format("target.hp%s%d below=%s", g.op, g.pct,
                        tostring(BAPI.IsUnitHealthBelow and BAPI.IsUnitHealthBelow("target", g.pct)))
                elseif g.t == "health" and g.pct then
                    parts[#parts + 1] = string.format("my.hp%s%d below=%s", g.op, g.pct,
                        tostring(BAPI.IsUnitHealthBelow and BAPI.IsUnitHealthBelow("player", g.pct)))
                elseif g.t == "stack" and g.id and g.n then
                    -- Ask the runtime's own verdict, then show the raw ">= n" read
                    -- beside it: the two disagree exactly when the operator logic is
                    -- wrong, which is the part worth being able to see.
                    local unit = g.tgt and "target" or "player"
                    local holds = SQ._StackHolds and SQ._StackHolds(unit, g)
                    local atN = BAPI.GetAuraStackAtLeast and BAPI.GetAuraStackAtLeast(unit, g.id, g.n)
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(g.id)
                    parts[#parts + 1] = string.format("%s(%s).stack%s%d [>=%d is %s] holds=%s",
                        (info and info.name) or tostring(g.id), unit,
                        g.op, g.n, g.n, tostring(atN), tostring(holds))
                elseif g.t == "resource" then
                    local value = resCount
                    if g.deficit and type(resMax) == "number" and type(resCount) == "number" then
                        value = resMax - resCount
                    elseif g.deficit then
                        value = nil
                    end
                    parts[#parts + 1] = string.format("%s%s%s%d [is=%s]", g.res,
                        g.deficit and ".deficit" or "", g.op, g.n,
                        (g.res == resName) and tostring(value) or "other resource")
                end
            end
            if #parts > 0 then
                shown = shown + 1
                local isBlocked = blocks and blocks(gates, resCount, resName, resMax) or false
                if isBlocked then blocked = blocked + 1 end
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(e.id)
                addon:Print(string.format("  %s|r %s %s {%s}",
                    isBlocked and "|cffff6600BLOCK" or "|cff2ecc71ok   ",
                    (info and info.name) or tostring(e.id),
                    e.delegated and "|cff888888(delegated)|r" or "",
                    table.concat(parts, ", ")))
            end
        end
    end
    addon:Print(string.format("=== %d gated entr%s, %d blocked right now ===",
        shown, shown == 1 and "y" or "ies", blocked))
    if shown == 0 then
        addon:Print("|cff888888This spec's rotation carries no threshold-evaluable gates - expected for many specs.|r")
    end
end

--------------------------------------------------------------------------------
-- /jac inspect topoff [off] - watch the between-pulls heal reminder decide.
-- Samples every 0.25s and prints only TRANSITIONS, so a flicker shows up as a
-- pair of lines with a timestamp gap instead of a wall of text. Every input the
-- decision uses is listed side by side, so the oscillating one is obvious.
--------------------------------------------------------------------------------
function DebugCommands.TopoffWatch(addon, arg)
    if DebugCommands._topoffWatch then
        DebugCommands._topoffWatch:SetScript("OnUpdate", nil)
        DebugCommands._topoffWatch = nil
        addon:Print("topoff watch: OFF")
        if arg == "off" then return end
    elseif arg == "off" then
        addon:Print("topoff watch: not running")
        return
    end

    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local Engine = LibStub("JustAC-PrecombatEngine", true)
    if not (BAPI and Engine) then addon:Print("topoff watch: modules unavailable") return end

    local f = CreateFrame("Frame")
    DebugCommands._topoffWatch = f
    local last, t = nil, 0
    f:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 0.25 then return end
        t = 0
        local profile = addon.db and addon.db.profile
        local offerTopoff = profile and profile.precombatBuffs and profile.precombatBuffs.topoffHeal == true
        local topoffPct = profile and profile.precombatBuffs and profile.precombatBuffs.topoffThreshold
        -- Ask the engine for the live list, exactly as the defensive queue does.
        local list = Engine.GetMissingClassBuffs and Engine.GetMissingClassBuffs(offerTopoff, topoffPct) or {}
        local offered = Engine.offeredTopoffHeal
        local inList = false
        for i = 1, #list do if list[i] == offered then inList = true break end end

        -- Guard THEN call - an `and` chain yields one value and dropped `estimated`, so this
        -- reported an estimate as though it were a measured percent.
        local pct, estimated
        if BAPI.GetPlayerHealthPercentSafe then pct, estimated = BAPI.GetPlayerHealthPercentSafe() end
        local state = table.concat({
            "offer=" .. tostring(offered),
            "inList=" .. tostring(inList),
            "full=" .. tostring(BAPI.IsUnitFullHealth and BAPI.IsUnitFullHealth("player")),
            "below" .. tostring(topoffPct or "?") .. "=" .. tostring(BAPI.IsUnitHealthBelow
                and topoffPct and BAPI.IsUnitHealthBelow("player", topoffPct)),
            "sustainedRegen=" .. tostring(BAPI.HasSustainedPlayerHealthActivity and BAPI.HasSustainedPlayerHealthActivity()),
            "recentEvent=" .. tostring(BAPI.HasRecentPlayerHealthActivity and BAPI.HasRecentPlayerHealthActivity()),
            "postCombat=" .. tostring(BAPI.IsInPostCombatDowntime and BAPI.IsInPostCombatDowntime()),
            "allyLowKey=" .. tostring(BAPI.IsUnitLow and BAPI.IsUnitLow("player")),
            "pct=" .. tostring(pct) .. (estimated and "(est)" or "(exact)"),
        }, " ")
        if state ~= last then
            last = state
            addon:Print(string.format("|cff888888[%.1f]|r %s", GetTime() % 1000, state))
        end
    end)
    addon:Print("|cff00ff00topoff watch: ON|r - stand damaged out of combat and watch which value flips with the icon. /jac inspect topoff off")
end
