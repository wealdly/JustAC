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


function DebugCommands.DiagnosticReport(addon)
    local s = DebugCommands._diagnosticSession or DebugCommands._lastDiagnosticSession
        or (_G.JustACGlobal and _G.JustACGlobal.diagnosticSummary)
    if not s then
        addon:Print("diagnostics: no session summary captured")
        if _G.JustACGlobal and _G.JustACGlobal.probeLog and #_G.JustACGlobal.probeLog > 0 then
            addon:Print("  Detailed probeLog entries exist; older captures did not persist report summaries.")
        end
        return
    end
    addon:Print(string.format("diagnostics: %d samples, %d changes, %d combat entries, %d probe failures",
        s.samples, s.changes, s.pulls, s.failures))
    addon:Print("  session=" .. s.id .. "; context is recorded at baseline, combat edges and context events.")
    addon:Print("  rolling log entries discarded during session: " .. tostring(s.dropped or 0)
        .. "; initial baseline is stored separately when available.")
    if (s.dropped or 0) > 0 then
        addon:Print("  WARNING: detailed capture is incomplete; older rows were discarded.")
    end
    if s.sampleMs then
        addon:Print(string.format("  sampler ms: total=%.2f mean=%.3f max=%.3f; audit ms: total=%.2f count=%d max=%.3f",
            s.sampleMs, s.sampleMs / math.max(s.samples, 1), s.sampleMaxMs,
            s.batteryMs or 0, s.batteries or 0, s.batteryMaxMs or 0))
    else
        addon:Print("  timing: unavailable")
    end
    for _, key in ipairs({"build", "researchAvailable", "class", "level", "spec", "instanceType", "mapID", "powerType",
        "healthThreshold", "healthBelow", "healthSource", "healUrgencyBelow50",
        "powerBelow50", "recoveryHealthThreshold", "recoveryHealthBelow",
        "recoveryManaThreshold", "recoveryManaBelow", "leadMode",
        "efficiencyMode", "efficiencyManaThreshold", "efficiencyRecoverySeconds",
        "efficiencyReason", "efficiencyID", "efficiencyRecovery", "efficiencyCandidates",
        "efficiencyManaBelow", "efficiencyEnemies", "queueContext", "targetContext", "enemyProvenance"}) do
        addon:Print("  " .. key .. "=" .. (s.last[key] or "untested"))
    end
    addon:Print("  Observations only: passing gates do not prove correct offers. Missing/secret reads are not absence.")
    addon:Print("  powerBelow50 tests current resource; recoveryManaBelow explicitly tests mana. Recovery offers are OOC-only.")
    addon:Print("  Summary and detailed log persist in JustACGlobal; /reload or logout flushes current changes to disk.")
end

function DebugCommands.DiagnosticStatus(addon)
    local s = DebugCommands._diagnosticSession
    addon:Print("diagnostics: " .. (s and "ON" or "OFF"))
    addon:Print("  audit=" .. tostring(DebugCommands._probeSession ~= nil)
        .. " errors=" .. tostring(DebugCommands._errorCapture ~= nil))
    if s then
        addon:Print("  owned audit=" .. tostring(s.ownsAudit) .. " errors=" .. tostring(s.ownsErrors))
    end
    DebugCommands.DiagnosticReport(addon)
end

function DebugCommands.StopDiagnostics(addon)
    local s = DebugCommands._diagnosticSession
    if not s then addon:Print("diagnostics: already OFF"); return end
    DebugCommands._diagnosticSession = nil
    s.frame:UnregisterAllEvents()
    s.frame:SetScript("OnEvent", nil)
    s.ticker:Cancel()
    s.signalReads, s.signalEvent = nil, nil
    if s.ownsAudit and DebugCommands._probeSession == s.audit then DebugCommands.ProbeSession(addon, "off") end
    if s.ownsErrors and DebugCommands._errorCapture == s.errors then DebugCommands.ErrorCapture(addon, "off") end
    ProbeLogEmit(string.format("DIAGNOSTICS STOP session=%s samples=%d changes=%d pulls=%d failures=%d",
        s.id, s.samples, s.changes, s.pulls, s.failures))
    if s.sampleMs then
        ProbeLogEmit(string.format("DIAGNOSTICS TIMING session=%s samplerMs=%.3f samplerMaxMs=%.3f auditMs=%.3f auditCount=%d auditMaxMs=%.3f",
            s.id, s.sampleMs, s.sampleMaxMs, s.batteryMs or 0, s.batteries or 0, s.batteryMaxMs or 0))
    end
    DebugCommands._lastDiagnosticSession = s
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local summary = {last={}}
    for _, key in ipairs({"id", "samples", "changes", "pulls", "failures", "sampleMs",
        "sampleMaxMs", "batteryMs", "batteries", "batteryMaxMs", "dropped"}) do
        summary[key] = s[key]
    end
    for key, value in pairs(s.last) do summary.last[key] = value end
    _G.JustACGlobal.diagnosticSummary = summary
    addon:Print("diagnostics: OFF")
    DebugCommands.DiagnosticReport(addon)
end

--------------------------------------------------------------------------------
function DebugCommands.StartDiagnostics(addon, arg)
    if arg and arg ~= "" then
        addon:Print("Usage: /jac inspect start (shared health, power, pet, queue, audit and error capture)")
        return
    end
    if DebugCommands._diagnosticSession then addon:Print("diagnostics: already ON"); return end
    DebugCommands._diagnosticSerial = (DebugCommands._diagnosticSerial or 0) + 1
    local s = { samples=0, changes=0, pulls=0, failures=0, last={}, started=GetTime(),
        id=date("%Y%m%d-%H%M%S") .. "-" .. DebugCommands._diagnosticSerial,
        ownsAudit=DebugCommands._probeSession == nil, ownsErrors=not DebugCommands._errorCapture }
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
        local nameplateUnits = {}
        for i = 1, 40 do nameplateUnits[i] = "nameplate" .. i end
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
                return string.format("simc=%s enemies=%s outOfMelee=%s dying=%s execute=%s pick=%s",
                    SafeSecret(ctx.simcCtx), SafeSecret(ctx.enemies), SafeSecret(ctx.outOfMelee),
                    SafeSecret(ctx.dying), SafeSecret(ctx.execute), SafeSecret(ctx.pickID))
            end,
            enemyProvenance=function()
                local threatRead = _G.UnitThreatSituation
                local plates, hostile, threat, noThreat, unknown = 0, 0, 0, 0, 0
                for i = 1, #nameplateUnits do
                    local unit = nameplateUnits[i]
                    local present = exists(unit)
                    if present == nil then
                        unknown = unknown + 1
                    elseif present then
                        plates = plates + 1
                        local attackable = UnitCanAttack("player", unit)
                        if IsSecret(attackable) then
                            unknown = unknown + 1
                        elseif attackable then
                            hostile = hostile + 1
                            if not threatRead then
                                unknown = unknown + 1
                            else
                                local ok, situation = pcall(threatRead, "player", unit)
                                if not ok or IsSecret(situation) then
                                    unknown = unknown + 1
                                elseif situation == nil then
                                    noThreat = noThreat + 1
                                else
                                    threat = threat + 1
                                end
                            end
                        end
                    end
                end
                return string.format("plates=%d hostile=%d threat=%d noThreat=%d unknown=%d threatApi=%s helper=%s",
                    plates, hostile, threat, noThreat, unknown, tostring(threatRead ~= nil),
                    compact(function() return B and B.GetEngagedEnemyCount and B.GetEngagedEnemyCount() end))
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
            s.signalReads, s.signalEvent = DebugCommands.CombatSignalReads()
        else
            s.signalReads = {}
        end
        reads.researchAvailable = function() return DebugCommands.CombatSignalReads ~= nil end
        for key, read in pairs(s.signalReads) do reads[key] = read end
        local keys = {}
        for key in pairs(reads) do keys[#keys+1] = key end
        table.sort(keys)
    local immutable = {build=true, interface=true, project=true, forever=true, addonVersion=true, class=true}
    local metadata = {}
    local function observe(tag)
        s.samples = s.samples + 1
        profile = addon:GetProfile()
        pre = profile and profile.precombatBuffs
        local emitted = tag ~= "SAMPLE"
        if emitted then
            ProbeLogEmit(string.format("DIAG session=%s sample=%d elapsed=%.2f %s pull=%d",
                s.id, s.samples, GetTime() - s.started, tag, s.pulls))
        end
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
                    ProbeLogEmit(string.format("DIAG session=%s sample=%d elapsed=%.2f %s pull=%d",
                        s.id, s.samples, GetTime() - s.started, tag, s.pulls))
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
        for _, event in ipairs({"ACTION_RANGE_CHECK_UPDATE", "SPELL_RANGE_CHECK_UPDATE",
            "UI_ERROR_MESSAGE", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
            "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET"}) do
            s.frame:RegisterEvent(event)
        end
        for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
            "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET"}) do
            s.frame:RegisterUnitEvent(event, "player")
        end
    end
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
        "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UNIT_PET", "PLAYER_LEVEL_UP"}) do
        s.frame:RegisterEvent(event)
    end
    s.frame:SetScript("OnEvent", function(_, event, unit, a, b, c, d)
        if DebugCommands._diagnosticSession ~= s then return end
        if event == "UNIT_PET" and unit ~= "player" then return end
        if s.signalEvent then s.signalEvent(event, unit, a, b, c, d) end
        if event == "SPELL_UPDATE_COOLDOWN" or event:match("^UNIT_SPELLCAST_")
           or event == "ACTION_RANGE_CHECK_UPDATE" or event == "SPELL_RANGE_CHECK_UPDATE"
           or event:match("^DAMAGE_METER_") or event == "UI_ERROR_MESSAGE" then return end
        if event == "PLAYER_REGEN_DISABLED" then s.pulls = s.pulls + 1 end
        sample(event)
    end)
    s.ticker = C_Timer.NewTicker(0.25, function()
        if DebugCommands._diagnosticSession ~= s then return end
        sample("SAMPLE")
        if GetTime() - s.started >= 600 and DebugCommands._diagnosticSession == s then
            addon:Print("diagnostics: ten-minute sampling limit reached")
            DebugCommands.StopDiagnostics(addon)
        end
    end)
    if s.ownsErrors then DebugCommands.ErrorCapture(addon, "on") end
    if s.ownsAudit then DebugCommands.ProbeSession(addon, "on") end
    s.audit, s.errors = DebugCommands._probeSession, DebugCommands._errorCapture
    sample("BASELINE")
    if DebugCommands._diagnosticSession == s then
        addon:Print("diagnostics: ON - play normally; /jac inspect stop, then /reload to save")
        addon:Print("  Power check: current resource below 50%; untested until you spend/recover across it.")
        if DebugCommands.CombatSignalReads then
            addon:Print("  Temporary signal research ON: 1s reads; up to 120 GCD changes per phase.")
            addon:Print("  Research log capacity: 32000 rows; ten-minute session limit.")
        else
            addon:Print("  Research unavailable: optional JustAC_Research companion is not loaded; standard diagnostics only.")
        end
    end
end



--------------------------------------------------------------------------------
function DebugCommands.ProbeSession(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then
            _G.JustACGlobal.probeLog = nil
            _G.JustACGlobal.probeLogDropped = nil
        end
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
        if f and f.ownsLoc and DebugCommands._locWatch == f.loc then
            DebugCommands.LossOfControlWatch(LogProxy(addon))
        end
        if f and f.ownsSelfCast and DebugCommands._selfCast == f.selfCast then
            DebugCommands.SelfCastProbe(LogProxy(addon))
        end
        addon:Print(string.format("audit: |cffff6600OFF|r - %d log lines held.", #ProbeLogStore()))
        addon:Print("|cff888888/reload to flush to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua (JustACGlobal.probeLog)|r")
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
                addon:Print("audit: 20 combat cycles captured - auto-stopping.")
                DebugCommands.ProbeSession(addon, "off")
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
        addon:Print("audit: standard validation only; optional JustAC_Research companion is not loaded.")
        return
    end
    addon:Print("|cff00ff00=== audit ARMED ===|r Baseline captured. Now just fight: enter/exit combat a few times,")
    addon:Print("get CC'd/dazed if you can, cast + channel, get hurt, cap a resource. Snapshots are automatic.")
    addon:Print("|cff888888  For the engine-signal leg: keep a debuffed target, kick something, and take a shield/absorb.|r")
    addon:Print("|cff888888  For the DoT leg: keep several bleeds rolling on one target, refresh them early,|r")
    addon:Print("|cff888888  and swap targets at least once so the tracker has to start over.|r")
    addon:Print("|cff888888  Apply a bleed OUT of combat too - the out-of-combat line is the control.|r")
    addon:Print("|cff888888  For curses: track their AURA entries in Cooldown Manager Tracked Buffs; cast, replace,|r")
    addon:Print("|cff888888  let expire, and swap targets. CURSE snapshots record true/false/unknown plus viewer/category evidence.|r")
    addon:Print("|cffffff00Then: /jac inspect audit off  ->  /reload|r  (log lands in SavedVariables/JustAC.lua)")
end
