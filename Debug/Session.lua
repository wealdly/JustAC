-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end
local IsSecret = DebugCommands._Common.IsSecret
local SafeSecret = DebugCommands._Common.SafeSecret
local ProbeRead = DebugCommands._Common.ProbeRead
local ProbeLogStore = DebugCommands._Capture.ProbeLogStore
local ProbeLogEmit = DebugCommands._Capture.ProbeLogEmit
local LogProxy = DebugCommands._Capture.LogProxy
local QuietProxy = DebugCommands._Capture.QuietProxy


-- Chat output stays short: the session's own state, warnings and the next step.
-- Recorders a session starts for itself report to the probe log, not chat.
function DebugCommands.DiagnosticReport(addon)
    local REPORT_KEYS = {"build", "researchAvailable", "class", "level", "spec", "instanceType", "mapID", "powerType",
        "healthThreshold", "healthBelow", "healthSource", "healUrgencyBelow50",
        "powerBelow50", "recoveryHealthThreshold", "recoveryHealthBelow",
        "recoveryManaThreshold", "recoveryManaBelow", "leadMode",
        "efficiencyMode", "efficiencyManaThreshold", "efficiencyRecoverySeconds",
        "efficiencyReason", "efficiencyID", "efficiencyRecovery", "efficiencyCandidates",
        "efficiencyManaBelow", "efficiencyEnemies", "pushbackComparison", "weaponComparison", "auraClock",
        "queueContext", "targetContext", "enemyProvenance"}
    local s = DebugCommands._diagnosticSession or DebugCommands._lastDiagnosticSession
        or (_G.JustACGlobal and _G.JustACGlobal.diagnosticSummary)
    if not s then
        addon:Print("diagnostics: no session summary captured")
        if _G.JustACGlobal and _G.JustACGlobal.probeLog and #_G.JustACGlobal.probeLog > 0 then
            addon:Print("  Detailed probeLog entries exist; older captures did not persist report summaries.")
        end
        return
    end
    local question = s.question
    if type(question) == "table" then question = question.id end
    addon:Print(string.format("diagnostics: session %s (%s) - %d samples, %d changes, %d pulls, %d marks, %d read failures",
        s.id, tostring(question or "all"), s.samples, s.changes, s.pulls, s.marks or 0, s.failures))
    if (s.dropped or 0) > 0 then
        addon:Print(string.format("  WARNING: detailed capture is incomplete; %d older log rows were discarded.", s.dropped))
    end
    if s.sampleMs then
        addon:Print(string.format("  sampler ms: total=%.2f mean=%.3f max=%.3f; audit ms: total=%.2f count=%d max=%.3f",
            s.sampleMs, s.sampleMs / math.max(s.samples, 1), s.sampleMaxMs,
            s.batteryMs or 0, s.batteries or 0, s.batteryMaxMs or 0))
    end
    for _, key in ipairs(REPORT_KEYS) do
        if s.last[key] then addon:Print("  " .. key .. "=" .. s.last[key]) end
    end
    addon:Print("  Observations only: missing or secret reads are not absence. /reload saves; analyze with tools\\analyze_probe.py.")
end

function DebugCommands.DiagnosticStatus(addon)
    local s = DebugCommands._diagnosticSession
    if not s then
        addon:Print("diagnostics: OFF")
        local last = DebugCommands._lastDiagnosticSession
            or (_G.JustACGlobal and _G.JustACGlobal.diagnosticSummary)
        if last then addon:Print("  last session " .. last.id .. "; /jac inspect report for details") end
    else
        local elapsed = GetTime() - s.started
        addon:Print(string.format("diagnostics: ON (%s) session %s, %dm%02ds of %dm, %d samples, %d pulls, %d marks",
            s.mode or "general", s.id, math.floor(elapsed / 60), math.floor(elapsed % 60), s.limit / 60,
            s.samples, s.pulls, s.marks or 0))
        if (s.dropped or 0) > 0 then
            addon:Print(string.format("  WARNING: %d older log rows discarded so far.", s.dropped))
        end
        if s.sampleMs then
            addon:Print(string.format("  sampler ms: mean=%.3f max=%.3f", s.sampleMs / math.max(s.samples, 1),
                s.sampleMaxMs))
        end
    end
    -- Recorders started outside a session keep running independently; say so.
    local session = s
    local audit = DebugCommands._probeSession ~= nil and not (session and session.ownsAudit)
    local errors = DebugCommands._errorCapture ~= nil and not (session and session.ownsErrors)
    if audit or errors then
        addon:Print("  also running: audit=" .. tostring(audit) .. " errors=" .. tostring(errors))
    end
end

function DebugCommands.StopDiagnostics(addon)
    local s = DebugCommands._diagnosticSession
    if not s then addon:Print("diagnostics: already OFF"); return end
    DebugCommands._diagnosticSession = nil
    s.frame:UnregisterAllEvents()
    s.frame:SetScript("OnEvent", nil)
    s.ticker:Cancel()
    if s.focusTicker then s.focusTicker:Cancel(); s.focusTicker = nil end
    if s.signalCleanup then s.signalCleanup() end
    s.signalReads, s.signalEvent, s.signalCleanup = nil, nil, nil
    local logOnly = LogProxy(addon)
    if s.ownsWatch and DebugCommands._ForeverWatch then DebugCommands._ForeverWatch(false) end
    local quiet = QuietProxy(addon)
    for _, name in ipairs(s.ownedLoggers or {}) do DebugCommands[name](quiet, "off") end
    if s.ownsAudit and DebugCommands._probeSession == s.audit then DebugCommands.ProbeSession(logOnly, "off") end
    if s.ownsErrors and DebugCommands._errorCapture == s.errors then DebugCommands.ErrorCapture(logOnly, "off") end
    ProbeLogEmit(string.format("DIAGNOSTICS STOP session=%s samples=%d changes=%d pulls=%d failures=%d t=%.3f marks=%d",
        s.id, s.samples, s.changes, s.pulls, s.failures, GetTime(), s.marks or 0))
    if s.sampleMs then
        ProbeLogEmit(string.format("DIAGNOSTICS TIMING session=%s samplerMs=%.3f samplerMaxMs=%.3f auditMs=%.3f auditCount=%d auditMaxMs=%.3f",
            s.id, s.sampleMs, s.sampleMaxMs, s.batteryMs or 0, s.batteries or 0, s.batteryMaxMs or 0))
    end
    DebugCommands._lastDiagnosticSession = s
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local summary = {last={}}
    for _, key in ipairs({"id", "samples", "changes", "pulls", "failures", "sampleMs",
        "sampleMaxMs", "batteryMs", "batteries", "batteryMaxMs", "dropped", "marks"}) do
        summary[key] = s[key]
    end
    summary.question = s.question and s.question.id or "all"
    for key, value in pairs(s.last) do summary.last[key] = value end
    _G.JustACGlobal.diagnosticSummary = summary
    local elapsed = GetTime() - s.started
    addon:Print(string.format("diagnostics: OFF - session %s, %dm%02ds, %d pulls, %d marks",
        s.id, math.floor(elapsed / 60), math.floor(elapsed % 60), s.pulls, s.marks or 0))
    if (s.dropped or 0) > 0 then
        addon:Print(string.format("  WARNING: detailed capture is incomplete; %d older log rows were discarded.", s.dropped))
    end
    local errorLog = _G.JustACGlobal.errorLog
    local newErrors = (errorLog and #errorLog or 0) - (s.errorsAtStart or 0)
    if newErrors > 0 then
        addon:Print(string.format("  %d new Lua/taint error(s) captured; /jac inspect errors show", newErrors))
    end
    addon:Print("  Next: /reload to save, then python tools\\analyze_probe.py (/jac inspect report for a summary)")
end

--------------------------------------------------------------------------------
function DebugCommands.StartDiagnostics(addon, arg)
    if DebugCommands._diagnosticSession then addon:Print("diagnostics: already ON"); return end
    -- Three modes. The default general capture records every key and row with the
    -- change-only audit samplers but without the audit battery's aura sweeps, so a
    -- normal play session fits the rolling log and can be compared against a saved
    -- baseline. "full" adds the battery. A question id records only that question.
    local LIGHT_LIMIT_SECONDS, FULL_LIMIT_SECONDS = 1200, 600
    local GENERAL_AUDIT = { "edge", "dot", "auraRoute", "curse" }
    local question
    local full = arg ~= nil and arg:lower() == "full"
    if arg and arg ~= "" and not full then
        if not DebugCommands.FindResearchQuestion then
            addon:Print("diagnostics: focused captures need the optional JustAC_Research companion.")
            addon:Print("Usage: /jac inspect start [full] (general capture; full adds the audit battery)")
            return
        end
        question = DebugCommands.FindResearchQuestion(arg:lower())
        if not question then
            addon:Print("diagnostics: unknown question '" .. arg .. "'. /jac inspect questions lists them.")
            return
        end
        if question.needs then
            addon:Print("diagnostics: '" .. question.id .. "' is not instrumented yet (needs "
                .. question.needs .. ").")
            return
        end
    end
    DebugCommands._diagnosticSerial = (DebugCommands._diagnosticSerial or 0) + 1
    local s = { samples=0, changes=0, pulls=0, failures=0, last={}, started=GetTime(),
        id=date("%Y%m%d-%H%M%S") .. "-" .. DebugCommands._diagnosticSerial,
        question=question, epoch=0, marks=0, mode=(question and "question") or (full and "full") or "general",
        ownsAudit=full and DebugCommands._probeSession == nil,
        ownsErrors=not DebugCommands._errorCapture }
    if question then
        s.rowKinds = {}
        for _, kind in ipairs(question.rows or {}) do s.rowKinds[kind] = true end
    end
    DebugCommands._diagnosticSession = s
        local B = LibStub("JustAC-BlizzardAPI", true)
        local DE = LibStub("JustAC-DefensiveEngine", true)
        local RF = LibStub("JustAC-RedundancyFilter", true)
        local PE = LibStub("JustAC-PrecombatEngine", true)
        local SDB = LibStub("JustAC-SpellDB", true)
        local SQ = LibStub("JustAC-SpellQueue", true)
        local RI = LibStub("JustAC-RotationImport", true)
        local profile, pre
        local ROTATION_ENTRY_LIMIT = 12
        local breakdown = {}
        local function compact(fn)
            local status, text = ProbeRead(fn)
            if status == "plain" or status == "nil" then return text end
            return status .. ":" .. text
        end
        local function pair(fn)
            local ok, first, second, source = pcall(fn)
            if not ok then return "err:" .. SafeSecret(first), "unknown", "query failed" end
            local function text(value)
                if IsSecret(value) then return "secret:<secret>" end
                return SafeSecret(value)
            end
            return text(first), text(second), text(source)
        end
        local function exists(unit)
            local value = UnitExists(unit)
            if IsSecret(value) then return nil end
            return value and true or false
        end
        local function rendered(icon)
            return icon:IsShown() and icon:GetAlpha() > 0
                and icon.iconTexture and icon.iconTexture:IsShown()
        end
        local function listContext(list)
            if not list then return nil end
            local ids = {}
            for i, id in ipairs(list) do ids[i] = SafeSecret(id) end
            return table.concat(ids, ",")
        end
        local reads = {
            combat=function() return UnitAffectingCombat("player") end,
            build=function() local v,b = GetBuildInfo(); return tostring(v) .. "." .. tostring(b) end,
            interface=function() return select(4, GetBuildInfo()) end,
            project=function() return WOW_PROJECT_ID end,
            forever=function() return B and B.IsForever and B.IsForever() end,
            addonVersion=function() return C_AddOns and C_AddOns.GetAddOnMetadata("JustAC", "Version") end,
            class=function() return select(2, UnitClass("player")) end,
            level=function() return UnitLevel("player") end,
            spec=function() return SDB and SDB.GetSpecKey and SDB.GetSpecKey() end,
            form=function() return GetShapeshiftForm() end,
            resting=function() return IsResting() end,
            dead=function() return UnitIsDeadOrGhost("player") end,
            mounted=function() return IsMounted() end,
            vehicle=function() return UnitInVehicle("player") end,
            groupSize=function() return GetNumGroupMembers() end,
            -- Can UNIT_AURA's removed-instance list end a buff timer here? How it has read so
            -- far, out of combat and in combat: none / plain / secret / mixed (RedundancyFilter).
            -- Categories, not counts: a count changes on every aura event.
            auraRemovals=function()
                local reads = RF and RF._removalReads
                if not reads then return nil end
                local function kind(plain, secret)
                    if plain > 0 and secret > 0 then return "mixed" end
                    if plain > 0 then return "plain" end
                    if secret > 0 then return "secret" end
                    return "none"
                end
                return "outOfCombat=" .. kind(reads.plain - reads.plainCombat, reads.secret - reads.secretCombat)
                    .. " inCombat=" .. kind(reads.plainCombat, reads.secretCombat)
            end,
            -- Threat as the game exposes it (research question "threat"): the tank signals,
            -- the target's state, lead and detailed values with their secrecy predicates, and a
            -- tally of the visible plates' states. Each cell is a plain/secret/error probe read.
            threat=function()
                local function on(mob, fn) return compact(function() return fn("player", mob) end) end
                local secrets = C_Secrets or {}
                local parts = {
                    "tankAura=" .. compact(function() return UnitHasEffectivelyTankAura("player") end),
                    "role=" .. compact(function() return UnitGroupRolesAssigned("player") end),
                    "pet=" .. tostring(exists("pet")),
                }
                if exists("target") then
                    parts[#parts + 1] = "stateSecret=" .. on("target", secrets.ShouldUnitThreatStateBeSecret)
                    parts[#parts + 1] = "valuesSecret=" .. on("target", secrets.ShouldUnitThreatValuesBeSecret)
                    parts[#parts + 1] = "state=" .. on("target", UnitThreatSituation)
                    parts[#parts + 1] = "lead=" .. on("target", UnitThreatLeadSituation)
                    for i, name in ipairs({ "tanking", "status", "scaled", "raw", "rawThreat" }) do
                        parts[#parts + 1] = name .. "=" .. compact(function()
                            return (select(i, UnitDetailedThreatSituation("player", "target")))
                        end)
                    end
                    parts[#parts + 1] = "ofLead=" .. on("target", UnitThreatPercentageOfLead)
                end
                local tally = { listed=0, secret=0, failed=0 }
                for i = 1, 40 do
                    local unit = "nameplate" .. i
                    if exists(unit) then
                        local ok, state = pcall(UnitThreatSituation, "player", unit)
                        if not ok then
                            tally.failed = tally.failed + 1
                        elseif IsSecret(state) then
                            tally.secret = tally.secret + 1
                        elseif type(state) == "number" then
                            tally.listed = tally.listed + 1
                            tally[state] = (tally[state] or 0) + 1
                        end
                    end
                end
                parts[#parts + 1] = string.format("plates=%d s0=%d s1=%d s2=%d s3=%d platesSecret=%d platesFailed=%d",
                    tally.listed, tally[0] or 0, tally[1] or 0, tally[2] or 0, tally[3] or 0, tally.secret, tally.failed)
                return table.concat(parts, " ")
            end,
            instanceType=function() return select(2, GetInstanceInfo()) end,
            difficulty=function() return select(3, GetInstanceInfo()) end,
            instanceID=function() return select(8, GetInstanceInfo()) end,
            mapID=function() return C_Map and C_Map.GetBestMapForUnit("player") end,
            targetExists=function() return UnitExists("target") end,
            targetHostile=function() return UnitCanAttack("player", "target") end,
            targetDead=function() return UnitIsDeadOrGhost("target") end,
            targetFriendly=function() return UnitIsFriend("player", "target") end,
            targetContext=function()
                local present = exists("target")
                if present == nil then return "unknown target" end
                if not present then return nil end
                return string.format("type=%s typeID=%s classification=%s level=%s",
                    compact(function() return UnitCreatureType and (UnitCreatureType("target")) end),
                    compact(function() return UnitCreatureType and select(2, UnitCreatureType("target")) end),
                    compact(function() return UnitClassification and UnitClassification("target") end),
                    compact(function() return UnitLevel("target") end))
            end,
            queueContext=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                if not ctx then return nil end
                return string.format("simc=%s enemies=%s outOfMelee=%s dying=%s execute=%s pick=%s lowValue=%s holdsRange=%s rangedSwap=%s onTheMove=%s",
                    SafeSecret(ctx.simcCtx), SafeSecret(ctx.enemies), SafeSecret(ctx.outOfMelee),
                    SafeSecret(ctx.dying), SafeSecret(ctx.execute), SafeSecret(ctx.pickID),
                    SafeSecret(ctx.lowValueTarget), SafeSecret(ctx.holdsRange), SafeSecret(ctx.rangedSwap), SafeSecret(ctx.onTheMove))
            end,
            enemyProvenance=function()
                -- The engaged count and its per-plate reasons come from the queue's own scan.
                if not (B and B.GetEngagedEnemyCount) then return nil end
                local count = B.GetEngagedEnemyCount(breakdown)
                return string.format("plates=%d hostile=%d threat=%d unknown=%d helper=%d widened=%d inCombatOthers=%d",
                    breakdown.plates, breakdown.hostile, breakdown.threat, breakdown.unknown, count,
                    breakdown.widened, breakdown.others)
            end,
            aggroRange=function()
                if not (SDB and SDB.GetAggroRangeState and SDB.IsTargetWithin) then return nil end
                local applies, reason = SDB.GetAggroRangeState()
                return string.format("applies=%s reason=%s within5=%s",
                    tostring(applies), tostring(reason), compact(function() return SDB.IsTargetWithin(5) end))
            end,
            rotationEligibility=function()
                if not (RI and RI.GetRotationGated and B) then return nil end
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                local context = ctx and ctx.simcCtx
                if context ~= "aoe" and context ~= "cleave" then context = "st" end
                local list = RI.GetRotationGated(context)
                if not list then return "context=" .. context .. " entries=0" end
                local shown = {}
                for position, icon in ipairs(addon.spellIcons or {}) do
                    if rendered(icon) then
                        local id = icon.currentSpellID or icon.spellID or icon.currentID
                        if id ~= nil and not IsSecret(id) and shown[id] == nil then shown[id] = position end
                    end
                end
                local resCount, resMax, resName
                if B.GetClassResourcePoints then resCount, resMax, resName = B.GetClassResourcePoints() end
                local count = math.min(#list, ROTATION_ENTRY_LIMIT)
                local rows = {"context=" .. context .. " entries=" .. #list}
                for i = 1, count do
                    local entry = list[i]
                    local id = entry.id
                    local rank = (RI.HighestKnownRank and RI.HighestKnownRank(id)) or id
                    local usable = C_Spell and C_Spell.IsSpellUsable
                    local rawUsable, rawPower = pair(function()
                        if usable then return usable(rank) end
                    end)
                    local helperUsable, helperPower, helperSource = pair(function()
                        return B.IsSpellUsable(rank, true)
                    end)
                    local ready, readySource = pair(function()
                        if B.IsSpellReady then return B.IsSpellReady(rank) end
                    end)
                    local gate = "none"
                    if entry.gates then
                        gate = compact(function()
                            if not SQ or not SQ._SimcGateBlocks then return nil end
                            if SQ._SimcGateBlocks(entry.gates, resCount, resName, resMax) then return "block" end
                            return "ok"
                        end)
                    end
                    rows[#rows+1] = string.format("%d:%s>%s raw=%s/%s helper=%s/%s ready=%s/%s range=%s gate=%s%s q=%s source=%s slot=%s action=%s",
                        i, SafeSecret(id), SafeSecret(rank),
                        rawUsable, rawPower, helperUsable, helperPower, ready, readySource,
                        compact(function() return B.AbilityInRange and B.AbilityInRange(rank) end),
                        gate, entry.delegated and "/delegated" or "",
                        tostring(shown[rank] or shown[id] or "-"), helperSource,
                        compact(function()
                            local scanner = LibStub("JustAC-ActionBarScanner", true)
                            return scanner and scanner.GetDirectSlotForSpell(rank)
                        end),
                        compact(function()
                            if not B.GetActionBarUsability then return nil end
                            local actionUsable, actionPower, actionSource = pair(function()
                                return B.GetActionBarUsability(rank)
                            end)
                            return actionUsable .. "/" .. actionPower .. "/" .. actionSource
                        end))
                end
                if #list > count then rows[#rows+1] = "truncated=" .. (#list - count) end
                return table.concat(rows, "; ")
            end,
            manualMode=function() return profile and profile.isManualMode end,
            leadMode=function() return SQ and SQ.LeadMode and SQ.LeadMode(profile) end,
            efficiencyMode=function() return profile and (profile.efficiencyMode or "off") end,
            pushbackComparison=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                if not ctx then return nil end
                return string.format("reason=%s chosen=%s",
                    SafeSecret(ctx.pushbackReason), SafeSecret(ctx.pushbackID))
            end,
            -- Which timer each held icon drew ("spell:kind:source"): the engine's own (aura
            -- container, aura or totem DurationObject), our estimate, or none. See AuraClock.
            auraClock=function()
                local clock = LibStub("JustAC-AuraClock", true)
                if not clock then return nil end
                return clock.Debug()
            end,
            weaponComparison=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                if not ctx then return nil end
                return string.format("basis=precombat-baseline minSpellGain=1.20x reason=%s spell=%s fillerChoice=%s spellDPS=%s weaponDPS=%s hitRate=%s manaRegen=%s",
                    SafeSecret(ctx.weaponReason), SafeSecret(ctx.weaponLead), SafeSecret(ctx.weaponID),
                    SafeSecret(ctx.weaponSpellDPS), SafeSecret(ctx.weaponDPS),
                    SafeSecret(ctx.weaponHitRate), SafeSecret(ctx.weaponManaRegen))
            end,
            efficiencyManaThreshold=function() return profile and (profile.efficiencyManaThreshold or 40) end,
            efficiencyRecoverySeconds=function() return profile and (profile.efficiencyRecoverySeconds or 10) end,
            efficiencyRecovery=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                if not ctx then return nil end
                return string.format("decision=%s source=%s combatSeconds=%s baseSeconds=%s reach=%s",
                    SafeSecret(ctx.efficiencyResourceDecision), SafeSecret(ctx.efficiencyRecoverySource),
                    SafeSecret(ctx.efficiencyFullSeconds), SafeSecret(ctx.efficiencyBaseFullSeconds),
                    SafeSecret(ctx.efficiencyRange))
            end,
            efficiencyCandidates=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                return ctx and ctx.efficiencyCandidates
            end,
            efficiencyManaBelow=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                if ctx then return ctx.efficiencyManaBelow end
            end,
            efficiencyEnemies=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                return ctx and ctx.enemies
            end,
            efficiencyReason=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                return ctx and ctx.efficiencyReason
            end,
            efficiencyID=function()
                local ctx = SQ and SQ.DebugContextState and SQ.DebugContextState()
                return ctx and ctx.efficiencyID
            end,
            maxIcons=function() return SQ and SQ.GetEffectiveMaxIcons and SQ.GetEffectiveMaxIcons(profile) end,
            defensivesEnabled=function() return profile and profile.defensives and profile.defensives.enabled end,
            defensiveDisplayMode=function() return profile and profile.defensives and profile.defensives.displayMode end,
            defensiveGlowMode=function() return profile and profile.defensives and profile.defensives.glowMode end,
            petRecoveryList=function() return DE and listContext(DE.GetClassSpellList(addon, "petRezSpells")) end,
            defensiveList=function() return DE and listContext(DE.GetClassSpellList(addon, "defensiveSpells")) end,
            customList=function()
                local spec = SDB and SDB.GetSpecKey and SDB.GetSpecKey()
                local cq = spec and profile and profile.customQueue and profile.customQueue[spec]
                if cq then return tostring(cq.enabled) .. ":" .. (listContext(cq.spells) or "absent") end
            end,
            blacklist=function()
                if not profile or not profile.blacklistedSpells then return nil end
                local spec = SDB and SDB.GetSpecKey and SDB.GetSpecKey()
                local blacklist = spec and profile.blacklistedSpells[spec]
                if not blacklist then return nil end
                local entries = {}
                for id, flags in pairs(blacklist) do
                    local value = SafeSecret(flags)
                    if type(flags) == "table" then
                        value = "fixedQueue=" .. SafeSecret(flags.fixedQueue)
                    end
                    entries[#entries+1] = SafeSecret(id) .. ":" .. value
                end
                table.sort(entries)
                return table.concat(entries, ",")
            end,
            aurasSecret=function() return B and B.AreAurasSecret() end,
            cooldownsSecret=function() return B and B.AreCooldownsSecret() end,
            healthThreshold=function() return pre and pre.topoffThreshold end,
            topoffEnabled=function() return pre and pre.topoffHeal end,
            healthBelow=function()
                if B and pre and pre.topoffThreshold then
                    return B.IsUnitHealthBelow("player", pre.topoffThreshold)
                end
            end,
            healthSource=function()
                if B and pre and pre.topoffThreshold then
                    return select(2, B.IsUnitHealthBelow("player", pre.topoffThreshold))
                end
            end,
            powerType=function() return UnitPowerType("player") end,
            powerBelow50=function() return B and B.IsUnitPowerBelow("player", 50) end,
            healUrgencyBelow50=function() return B and B.IsUnitHealthBelow("player", 50) end,
            healUrgencySource=function()
                if B then return select(2, B.IsUnitHealthBelow("player", 50)) end
            end,
            recoveryHealthThreshold=function()
                return PE and PE.GetRecoveryThresholds and PE.GetRecoveryThresholds()
            end,
            recoveryManaThreshold=function()
                if PE and PE.GetRecoveryThresholds then
                    return select(2, PE.GetRecoveryThresholds(pre and pre.recoveryManaThreshold))
                end
            end,
            recoveryHealthBelow=function()
                if B and PE and PE.GetRecoveryThresholds and B.IsForever() then
                    local pct = PE.GetRecoveryThresholds()
                    return B.IsUnitHealthBelow("player", pct)
                end
            end,
            recoveryManaBelow=function()
                if B and PE and PE.GetRecoveryThresholds and B.IsForever() then
                    local mana = Enum.PowerType.Mana
                    local maximum = UnitPowerMax("player", mana)
                    if IsSecret(maximum) then return "unknown mana capacity" end
                    if not maximum or maximum <= 0 then return "not applicable: no mana" end
                    local _, pct = PE.GetRecoveryThresholds(pre and pre.recoveryManaThreshold)
                    return B.IsUnitPowerBelow("player", pct, mana)
                end
            end,
            pet=function() return B and B.GetPetStatus() end,
            topoffOffer=function() return PE and PE.offeredTopoffHeal end,
            healthBand=function() return DE and DE.GetHealthBandInfo and DE.GetHealthBandInfo() end,
            healthBandSource=function()
                if DE and DE.GetHealthBandInfo then return select(2, DE.GetHealthBandInfo()) end
            end,
            petReminder=function()
                if DE and DE.GetPetReminderState then
                    local eligible, reason = DE.GetPetReminderState(addon)
                    return tostring(eligible) .. ":" .. tostring(reason)
                end
            end,
            auraComplete=function() local c = RF and RF.GetAuraCache(); return c and c.complete end,
            displayed=function()
                local ids = {}
                for surface, icons in ipairs({addon.spellIcons or {}, addon.defensiveIcons or {}}) do
                    for position, icon in ipairs(icons) do
                        if rendered(icon) then
                            local label = "main"
                            if surface == 2 then label = "defensive" end
                            local identity = SafeSecret(icon.currentSpellID or icon.spellID or icon.currentID)
                            if icon.isItem then
                                identity = "item:" .. SafeSecret(icon.itemID or icon.currentID)
                            elseif icon.isWaitingSpell or icon.isWaiting then
                                identity = "wait:" .. identity
                            elseif identity == "nil" then
                                identity = "unidentified"
                            end
                            ids[#ids+1] = label .. "[" .. position .. "]="
                                .. identity
                        end
                    end
                end
                -- The Threat button (shares the interrupt slot): which press it offered.
                local threat = addon.threatIcon
                if threat and rendered(threat) then
                    ids[#ids+1] = "threat[1]=" .. SafeSecret(threat.spellID)
                end
                return table.concat(ids, ",")
            end,
            defensiveGlow=function()
                local states = {}
                for position, icon in ipairs(addon.defensiveIcons or {}) do
                    if rendered(icon) then
                        states[#states+1] = string.format("[%d] id=%s mode=%s primary=%s waiting=%s applied=%s reason=%s",
                            position, SafeSecret(icon.currentID), SafeSecret(icon.defGlowMode),
                            SafeSecret(icon.defShowGlow), SafeSecret(icon.isWaiting),
                            SafeSecret(icon.appliedDefGlowState), SafeSecret(icon.defGlowReason))
                    end
                end
                return table.concat(states, ";")
            end,
        }
        if DebugCommands.CombatSignalReads then
            s.signalReads, s.signalEvent, s.signalCleanup =
                DebugCommands.CombatSignalReads(reads.displayed)
        else
            s.signalReads = {}
        end
        reads.researchAvailable = function() return DebugCommands.CombatSignalReads ~= nil end
        for key, read in pairs(s.signalReads) do reads[key] = read end
        local keys = {}
        local missing = {}
        if question then
            local wanted = {}
            for _, key in ipairs(DebugCommands.RESEARCH_CORE_KEYS or {}) do wanted[key] = true end
            for _, key in ipairs(question.keys or {}) do
                wanted[key] = true
                if not reads[key] then missing[#missing+1] = key end
            end
            for key in pairs(wanted) do
                if reads[key] then keys[#keys+1] = key end
            end
        else
            for key in pairs(reads) do keys[#keys+1] = key end
        end
        table.sort(keys)
        table.sort(missing)
    local immutable = {build=true, interface=true, project=true, forever=true, addonVersion=true, class=true}
    local metadata = {}
    local function header(tag)
        local now = GetTime()
        ProbeLogEmit(string.format("DIAG session=%s sample=%d elapsed=%.2f t=%.3f epoch=%d %s pull=%d",
            s.id, s.samples, now - s.started, now, s.epoch, tag, s.pulls))
    end
    local function observe(tag)
        s.samples = s.samples + 1
        profile = addon:GetProfile()
        pre = profile and profile.precombatBuffs
        local emitted = tag ~= "SAMPLE"
        if emitted then header(tag) end
        for _, key in ipairs(keys) do
            local cell = metadata[key]
            local status
            if not cell then
                local text
                status, text = ProbeRead(reads[key])
                cell = status .. ":" .. text
                if immutable[key] and status ~= "err" then metadata[key] = cell end
            end
            local changed = s.last[key] ~= cell
            if changed or tag == "BASELINE" then
                if changed then
                    s.changes = s.changes + 1
                    if status == "err" then s.failures = s.failures + 1 end
                end
                if not emitted then
                    header(tag)
                    emitted = true
                end
                ProbeLogEmit("  " .. key .. "=" .. cell)
                s.last[key] = cell
            end
        end
        if tag == "BASELINE" then
            if not _G.JustACGlobal then _G.JustACGlobal = {} end
            local baseline = {id=s.id, last={}}
            for key, value in pairs(s.last) do baseline.last[key] = value end
            _G.JustACGlobal.diagnosticBaseline = baseline
        end
    end
    local function sample(tag)
        local started = debugprofilestop and debugprofilestop()
        local ok, err = pcall(observe, tag)
        if started then
            local elapsed = debugprofilestop() - started
            s.sampleMs = (s.sampleMs or 0) + elapsed
            s.sampleMaxMs = math.max(s.sampleMaxMs or 0, elapsed)
        end
        if not ok then
            s.failures = s.failures + 1
            ProbeLogEmit("DIAGNOSTICS ERROR: " .. SafeSecret(err))
            addon:Print("diagnostics: sampler failed: " .. SafeSecret(err))
            DebugCommands.StopDiagnostics(addon)
        end
    end
    s.frame = CreateFrame("Frame")
    s.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    s.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    s.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    for _, event in ipairs({"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"}) do
        s.frame:RegisterUnitEvent(event, "target")
    end
    if s.signalEvent then
        s.frame:RegisterUnitEvent("UNIT_COMBAT", "player")
        for _, event in ipairs({"ACTION_RANGE_CHECK_UPDATE", "SPELL_RANGE_CHECK_UPDATE",
            "UI_ERROR_MESSAGE", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
            "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
            "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "CVAR_UPDATE",
            -- A creature's emote (a flee: "attempts to run away in fear"), with its sender's GUID.
            "CHAT_MSG_MONSTER_EMOTE"}) do
            s.frame:RegisterEvent(event)
        end
        if B and B.IsForever and B.IsForever() then
            s.frame:RegisterEvent("PLAYER_SWING")
            if C_SwingTimer then s.frame:RegisterEvent("PLAYER_SWING_RANGE_UPDATE") end
        end
        for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED",
            "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET"}) do
            s.frame:RegisterUnitEvent(event, "player")
        end
        -- Re-registering replaces the unit list: keep the target and add the player's starts.
        s.frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target", "player")
        -- Lockout auras (Weakened Soul, Forbearance) come and go on the player; the look-ahead
        -- probe also times target debuffs, resource updates and the target's combat results.
        s.frame:RegisterUnitEvent("UNIT_AURA", "player", "target")
        s.frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        s.frame:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
    end
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
        "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UNIT_PET", "PLAYER_LEVEL_UP"}) do
        s.frame:RegisterEvent(event)
    end
    s.frame:SetScript("OnEvent", function(_, event, unit, a, b, c, d, ...)
        if DebugCommands._diagnosticSession ~= s then return end
        if event == "UNIT_PET" and unit ~= "player" then return end
        if event == "PLAYER_TARGET_CHANGED" then s.epoch = s.epoch + 1 end
        if s.signalEvent then s.signalEvent(event, unit, a, b, c, d, ...) end
        if event == "SPELL_UPDATE_COOLDOWN" or event == "UNIT_COMBAT" or event:match("^UNIT_SPELLCAST_")
           or event == "ACTION_RANGE_CHECK_UPDATE" or event == "SPELL_RANGE_CHECK_UPDATE"
           or event == "PLAYER_SWING" or event == "PLAYER_SWING_RANGE_UPDATE" or event == "CVAR_UPDATE"
           or event:match("^DAMAGE_METER_") or event == "UI_ERROR_MESSAGE" or event == "UNIT_AURA"
           or event == "UNIT_POWER_FREQUENT" or event == "CHAT_MSG_MONSTER_EMOTE" then
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then s.pulls = s.pulls + 1 end
        sample(event)
        -- One line per combat edge so a running capture is never forgotten.
        if event == "PLAYER_REGEN_DISABLED" then
            addon:Print(string.format("|cffffcc00probe active|r - recording pull %d", s.pulls))
        elseif event == "PLAYER_REGEN_ENABLED" then
            local elapsed = GetTime() - s.started
            addon:Print(string.format("|cffffcc00probe active|r - pull %d recorded (%dm of %dm); /jac inspect stop when done",
                s.pulls, math.floor(elapsed / 60), s.limit / 60))
        end
    end)
    local limit = LIGHT_LIMIT_SECONDS
    if full then limit = FULL_LIMIT_SECONDS end
    s.ticker = C_Timer.NewTicker(0.25, function()
        if DebugCommands._diagnosticSession ~= s then return end
        sample("SAMPLE")
        if GetTime() - s.started >= limit and DebugCommands._diagnosticSession == s then
            addon:Print(string.format("diagnostics: %d-minute sampling limit reached", limit / 60))
            DebugCommands.StopDiagnostics(addon)
        end
    end)
    s.limit = limit
    s.errorsAtStart = _G.JustACGlobal and _G.JustACGlobal.errorLog and #_G.JustACGlobal.errorLog or 0
    local logOnly = LogProxy(addon)
    -- The start row comes first: every row after it belongs to this session, so what the
    -- recorders below write as they start (the audit baseline above all) is kept with it.
    -- Self-describing capture: the analyzer scores against these rows, not the
    -- registry it happens to find on disk later.
    ProbeLogEmit(string.format("DIAGNOSTICS START session=%s t=%.3f question=%s mode=%s limit=%d",
        s.id, GetTime(), question and question.id or "all", s.mode, limit))
    -- Which deployed build this is (written at deploy time into the Research companion), so a
    -- session read weeks later still says what code produced it.
    if DebugCommands._buildStamp then
        ProbeLogEmit("DIAGNOSTICS BUILD session=" .. s.id .. " " .. DebugCommands._buildStamp)
    end
    if s.ownsErrors then DebugCommands.ErrorCapture(logOnly, "on") end
    if s.ownsAudit then DebugCommands.ProbeSession(logOnly, "on") end
    s.audit, s.errors = DebugCommands._probeSession, DebugCommands._errorCapture
    -- The standard capture runs the passive recorders too: what each used to record on its own
    -- switch. The change-only loggers write into the same log; the mob and pet profiles keep
    -- their own tables (the offline simulator reads them) and are simply armed for the session.
    -- One already running by hand is left to its owner. The pick logger needs a game pick, so
    -- it stays off where there is none. A focused session runs only what its question asks for.
    if not question then
        local quiet = QuietProxy(addon)
        s.ownedLoggers = {}
        for _, logger in ipairs({ { "MaintenanceLog", "_maintLog" }, { "TopoffWatch", "_topoffWatch" },
                                  { "EnrageLog", "_enrageLog" }, { "PickLog", "_pickLog", gamePick = true },
                                  { "MobProfileProbe", "_mobProfileOn", start = "arm" },
                                  { "PetProfileProbe", "_petProfileOn", start = "arm" } }) do
            local name, state = logger[1], logger[2]
            if DebugCommands[name] and not DebugCommands[state]
               and (not logger.gamePick or (B and B.HasGamePick and B.HasGamePick())) then
                DebugCommands[name](quiet, logger.start or "on")
                s.ownedLoggers[#s.ownedLoggers + 1] = name
            end
        end
    end
    -- Full mode on Forever also runs the event recorder (Research companion), unless one is
    -- already running on its own.
    if full and DebugCommands._ForeverWatch and not DebugCommands._foreverWatch
       and B and B.IsForever and B.IsForever() then
        s.ownsWatch = true
        DebugCommands._ForeverWatch(true)
    end
    ProbeLogEmit("DIAGNOSTICS KEYS session=" .. s.id .. " keys=" .. table.concat(keys, ","))
    if #missing > 0 then
        ProbeLogEmit("DIAGNOSTICS MISSING session=" .. s.id .. " keys=" .. table.concat(missing, ","))
    end
    if DebugCommands.EmitQuestionDefinitions then
        if question then
            DebugCommands.EmitQuestionDefinitions(s.id, {question})
        else
            DebugCommands.EmitQuestionDefinitions(s.id, DebugCommands.InstrumentedResearchQuestions())
        end
    end
    local auditNames
    if question then auditNames = question.audit elseif not full then auditNames = GENERAL_AUDIT end
    if auditNames and DebugCommands.AuditSignalSamples then
        local samples = DebugCommands.AuditSignalSamples(function() return s.epoch end, auditNames)
        s.focusTicker = C_Timer.NewTicker(1.0, function()
            if DebugCommands._diagnosticSession ~= s then return end
            for _, read in ipairs(samples) do
                local ok, err = pcall(read)
                if not ok then
                    ProbeLogEmit("FOCUS SAMPLE ERROR: " .. SafeSecret(err))
                    s.focusTicker:Cancel()
                    s.focusTicker = nil
                    return
                end
            end
        end)
    end
    sample("BASELINE")
    if DebugCommands._diagnosticSession ~= s then return end
    local minutes = limit / 60
    if question then
        addon:Print(string.format("diagnostics: ON (question '%s', up to %d min): %s", question.id, minutes, question.title))
        DebugCommands.PrintQuestionGuide(addon, question)
        if #missing > 0 then
            addon:Print("  WARNING: keys unavailable on this client: " .. table.concat(missing, ", "))
        end
    elseif full then
        addon:Print(string.format("diagnostics: ON (full capture with audit battery, up to %d min)", minutes))
    else
        addon:Print(string.format("diagnostics: ON (general capture, up to %d min); 'start full' adds the audit battery", minutes))
    end
    if not DebugCommands.CombatSignalReads then
        addon:Print("  Research unavailable: JustAC_Research is not loaded; standard keys only.")
    end
    addon:Print("  Play, then /jac inspect stop and /reload.")
end



--------------------------------------------------------------------------------
-- /jac inspect audit: the standard session in its full mode. There is one capture; this name
-- stays for macros and older test plans. `clear` empties the log; `off` also stops a battery
-- that was started on its own before this routed through the session.
function DebugCommands.AuditSession(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        DebugCommands.ProbeSession(addon, "clear")
    elseif arg == "off" or (not arg and DebugCommands._diagnosticSession) then
        if DebugCommands._diagnosticSession then
            DebugCommands.StopDiagnostics(addon)
        elseif DebugCommands._probeSession then
            DebugCommands.ProbeSession(addon, "off")
        else
            addon:Print("diagnostics: already OFF")
        end
    else
        DebugCommands.StartDiagnostics(addon, "full")
    end
end

-- The audit battery: snapshots at the baseline, in combat and at its end. Run by the standard
-- session's full mode (StartDiagnostics); not a command of its own.
function DebugCommands.ProbeSession(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then
            _G.JustACGlobal.probeLog = nil
            _G.JustACGlobal.probeLogDropped = nil
            -- The lists the maintenance and pick loggers kept before they wrote here.
            _G.JustACGlobal.maintLog, _G.JustACGlobal.pickLog = nil, nil
        end
        addon:Print("audit: log cleared")
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
        if f and f.ownsLoc and DebugCommands._locWatch == f.loc then
            DebugCommands.LossOfControlWatch(LogProxy(addon))
        end
        if f and f.ownsSelfCast and DebugCommands._selfCast == f.selfCast then
            DebugCommands.SelfCastProbe(LogProxy(addon))
        end
        addon:Print(string.format("audit: OFF - %d log lines held; /reload to save (JustACGlobal.probeLog)",
            #ProbeLogStore()))
        return
    end

    if DebugCommands._probeSession then addon:Print("audit: already ON"); return end
    local f = CreateFrame("Frame")
    DebugCommands._probeSession = f
    local cycles = 0
    local curseTargetEpoch = 0
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD") -- instanced content (delves) loads via this, not ZONE_CHANGED
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "PLAYER_TARGET_CHANGED" then
            curseTargetEpoch = curseTargetEpoch + 1
            ProbeLogEmit(string.format("CURSE target-change @ %.1f epoch=%d", GetTime(), curseTargetEpoch))
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" then
                ProbeLogEmit(string.format("CURSE cast @ %.1f epoch=%d spell=%s",
                    GetTime(), curseTargetEpoch, SafeSecret(spellID)))
            end
        elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
            -- Restricted-map baseline: SecretOnRestrictedMaps applies OOC too,
            -- so entering a delve/dungeon deserves its own out-of-combat snapshot.
            if not UnitAffectingCombat("player") then
                DebugCommands.RunProbeBattery(addon, "ZONE:" .. (GetZoneText() or "?"))
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            cycles = cycles + 1
            local cycle = cycles
            -- No battery at entry: measured 2026-07-24 that secrecy latches
            -- mid-combat, so at-entry reads look plain and prove nothing.
            ProbeLogEmit(string.format("===== COMBAT-ENTER#%d @ %.1f (marker only) =====", cycles, GetTime()))
            -- +4s catches short pulls (a 7.5s pull missed the +10s window entirely);
            -- castCount going SECRET inside the same snapshot marks whether
            -- restrictions had latched, so an early read cannot mislead.
            for _, delay in ipairs({ 4, 10 }) do
                C_Timer.After(delay, function()
                    if DebugCommands._probeSession == f and cycles == cycle
                        and UnitAffectingCombat("player") then
                        DebugCommands.RunProbeBattery(addon, "COMBAT+" .. delay .. "s#" .. cycle)
                    end
                end)
            end
        else
            DebugCommands.RunProbeBattery(addon, "COMBAT-EXIT#" .. cycles)
            if cycles >= 20 then
                ProbeLogEmit("audit: 20 combat cycles captured; stopping")
                DebugCommands.ProbeSession(LogProxy(addon), "off")
            end
        end
    end)

    local curseSample
    if DebugCommands.AuditSignalSamples then
        local samples
        samples, curseSample = DebugCommands.AuditSignalSamples(function() return curseTargetEpoch end)
        DebugCommands._probeTicker = C_Timer.NewTicker(1.0, function()
            for _, sample in ipairs(samples) do
                local ok, err = pcall(sample)
                if not ok then
                    ProbeLogEmit("AUDIT SAMPLE ERROR: " .. SafeSecret(err))
                    DebugCommands.ProbeSession(addon, "off")
                    break
                end
            end
        end)
    end

    ProbeLogEmit(string.format("========== AUDIT SESSION ARMED %s (build %s) ==========",
        date("%Y-%m-%d %H:%M:%S"), (GetBuildInfo())))
    DebugCommands.RunProbeBattery(addon, "BASELINE", true)
    if curseSample then curseSample() end
    -- Arm the event captures with output into the log.
    f.ownsLoc = DebugCommands.LossOfControlWatch ~= nil and DebugCommands._locWatch == nil
    f.ownsSelfCast = DebugCommands.SelfCastProbe ~= nil and DebugCommands._selfCast == nil
    if f.ownsLoc then DebugCommands.LossOfControlWatch(LogProxy(addon)) end
    if f.ownsSelfCast then DebugCommands.SelfCastProbe(LogProxy(addon)) end
    f.loc, f.selfCast = DebugCommands._locWatch, DebugCommands._selfCast
    if not DebugCommands.AuditSignalSamples then
        addon:Print("audit: ON - standard validation only (JustAC_Research not loaded)")
        return
    end
    addon:Print("audit: ON - baseline captured; combat snapshots are automatic")
    addon:Print("  /jac inspect stop, then /reload to save")
end

--------------------------------------------------------------------------------
-- /jac inspect mark <label>: timestamp a scenario control the probe cannot observe
-- itself (a heal landing on you, a debuff dispelled, stepping into melee). Bind it
-- to a macro to mark mid-fight. The analyzer scores marks against the session's
-- question definitions; a mark outside a session is logged but never scored.
--------------------------------------------------------------------------------
local MARK_LABEL_MAX = 40

function DebugCommands.MarkScenario(addon, arg)
    local label = arg and arg:lower():gsub("[^%w%-_]+", "-"):gsub("^%-+", ""):gsub("%-+$", "") or ""
    label = label:sub(1, MARK_LABEL_MAX)
    local s = DebugCommands._diagnosticSession
    if label == "" then
        addon:Print("Usage: /jac inspect mark <label>")
        local question = s and s.question
        if question and question.marks then
            addon:Print("  Labels for '" .. question.id .. "': " .. table.concat(question.marks, ", "))
        end
        return
    end
    local epoch = "none"
    if s then
        s.marks = (s.marks or 0) + 1
        epoch = tostring(s.epoch or 0)
    end
    local now = GetTime()
    ProbeLogEmit(string.format("MARK session=%s t=%.3f epoch=%s combat=%s label=%s",
        s and s.id or "none", now, epoch, tostring(UnitAffectingCombat("player") and true or false), label))
    if s then
        addon:Print(string.format("mark: %s @ %.1f", label, now))
    else
        addon:Print("mark: " .. label .. " logged, but no session is running, so it will not be scored")
    end
end
