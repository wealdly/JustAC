# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Probe reporting and recorder lifecycle with controlled client signals.
from pathlib import Path
import re

from lupa import LuaRuntime
from lupa.lua51 import LuaRuntime as Lua51Runtime

ROOT = Path(__file__).resolve().parent.parent
DEBUG_FILES = [
    ROOT.joinpath(*line.strip().split("\\"))
    for line in (ROOT / "JustAC.toc").read_text(encoding="utf-8").splitlines()
    if line.strip() == "DebugCommands.lua" or line.strip().startswith("Debug\\")
]
RESEARCH_ROOT = ROOT / "Debug" / "Research"
RESEARCH_TOC = RESEARCH_ROOT / "JustAC_Research.toc"
RESEARCH_FILES = [
    RESEARCH_ROOT / line.strip()
    for line in RESEARCH_TOC.read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.startswith("#")
] if RESEARCH_TOC.exists() else []
SOURCES = {path: path.read_text(encoding="utf-8") for path in DEBUG_FILES + RESEARCH_FILES}
SOURCE = "\n".join(SOURCES.values())
COMMON_SOURCE = SOURCES[ROOT / "Debug" / "Common.lua"]
CAPTURE_SOURCE = SOURCES[ROOT / "Debug" / "Capture.lua"]


def method(name):
    marker = f"function DebugCommands.{name}("
    source = next(text for text in reversed(SOURCES.values()) if marker in text)
    start = source.index(marker)
    end = source.index("\nend", start) + len("\nend")
    return source[start:end]


def runtime(runtime_type=LuaRuntime):
    lua = runtime_type(unpack_returned_tuples=True)
    lua.execute("""
        DebugCommands = {}
        output, timers, callbacks, frames = {}, {}, {}, {}
        addon = { Print = function(_, msg) output[#output+1] = msg end }
        function issecretvalue() return false end
        function GetTime() return 10 end
        function UnitAffectingCombat() return combat == true end
        function UnitIsDeadOrGhost() return false end
        function InCombatLockdown() return combat == true end
        C_Timer = {
            NewTicker = function(_, fn)
                local t = {fn=fn, Cancel=function(self) self.cancelled=true end}
                timers[#timers+1] = t
                return t
            end,
            After = function(_, fn) callbacks[#callbacks+1] = fn end,
        }
        function CreateFrame()
            local f = {
                scripts = {}, RegisterEvent = function() end, RegisterUnitEvent = function() end,
                UnregisterAllEvents = function(self) self.unregistered=true end,
                SetScript = function(self, key, fn) self.scripts[key]=fn end,
            }
            frames[#frames+1] = f
            return f
        end
        function GetBuildInfo() return 'test' end
        function UnitPowerType() return 3 end
        function LibStub() return nil end
        addon.GetProfile=function() return {precombatBuffs={topoffThreshold=90,topoffHeal=true}} end
        function date() return 'test' end
        function wipe(t) for k in pairs(t) do t[k]=nil end end
    """)
    start = COMMON_SOURCE.index("local function IsSecret(")
    end = COMMON_SOURCE.index("\nDebugCommands._Common =")
    lua.execute(COMMON_SOURCE[start:end].replace("local function ", "function ")
                .replace("local ClassifyRead\n", ""))
    start = CAPTURE_SOURCE.index("local PROBE_LOG_MAX =")
    end = CAPTURE_SOURCE.index("\n--------------------------------------------------------------------------------", start)
    lua.execute(CAPTURE_SOURCE[start:end].replace("local function ", "function "))
    if RESEARCH_FILES:
        lua.execute(method("PriorityGateSample"))
        lua.execute(method("CombatSignalReads"))
        lua.execute(method("AuditSignalSamples"))
    lua.execute("function targetEpoch() return curseTargetEpoch end")
    return lua


def lines(lua):
    return "\n".join(lua.globals().output.values())


def test_chat_output():
    lua = runtime()
    lua.execute(r"""
        chat=DebugCommands.ChatOutput(addon)
        chat:Print('|cff00ff00Short heading|r')
        assert(output[1]=='|cff00ff00Short heading|r')
        output={}
        local text='context combat=true target=true hostile=true viewer=BuffIconCooldownViewer '
            .. 'active=true spell=secret linked=secret auraUnit=target'
        chat:Print('|cffff0000'..text..'|r')
        assert(#output>1)
        local words={}
        for _,line in ipairs(output) do
            assert(#line<=76)
            for word in line:gmatch('%S+') do words[#words+1]=word end
        end
        assert(table.concat(words,' ')==text, 'no field may be lost')
        assert(output[2]:sub(1,2)=='  ', 'continuations are indented')
        output={}
        chat:Print('first\nsecond')
        assert(output[1]=='first' and output[2]=='second')
        output={}
        local link='|Hspell:702|h[Curse of Weakness]|h'
        chat:Print(string.rep('context ',12)..link..' active=true')
        local found=false
        for _,line in ipairs(output) do
            if line:find(link,1,true) then found=true end
        end
        assert(found, 'hyperlinks must not be split')
        chat.testFlag=true
        assert(addon.testFlag==true, 'watcher writes must reach the real addon')
        addon.GetProfile=function(self) return self.testFlag end
        assert(chat:GetProfile()==true)
        output={}
        local function later() chat:Print(text) end
        later()
        assert(#output>1, 'watcher callbacks retain chat formatting')
        LogProxy(chat):Print(text)
        assert(JustACGlobal.probeLog[#JustACGlobal.probeLog]==text,
            'saved rows must stay complete and unsplit')
    """)
    core = (ROOT / "Options" / "Core.lua").read_text(encoding="utf-8")
    assert "local output = DebugCommands.ChatOutput(addon)" in core
    assert "DebugCommands[methodName](output, ...)" in core
    lua.execute("""
        output={}
        DebugCommands.CurseDiagnostics=nil
    """)
    lua.execute(method("CurseDiagnostics"))
    lua.globals().DebugCommands.CurseDiagnostics(lua.globals().chat)
    assert all(len(line) <= 76 for line in lua.globals().output.values())


def test_registry():
    start = SOURCE.index("local INSPECT_TOPICS =")
    end = SOURCE.index("--- topic -> method name", start)
    rows = re.findall(r'\{\s*"([^"]+)",\s*"([^"]+)"', SOURCE[start:end])
    methods = re.findall(r"function DebugCommands\.(\w+)\(", SOURCE)
    assert len(rows) == len({topic for topic, _ in rows})
    lua = loaded_runtime(False, False)
    loaded = lua.globals().DebugCommands.GetInspectTopics()
    assert all(name in methods for name in loaded.values())
    if RESEARCH_FILES:
        assert all(name in methods for _, name in rows)


def loaded_runtime(forever, research=True):
    lua = runtime(Lua51Runtime)
    lua.globals().forever = forever
    lua.execute("""
        local createFrame=CreateFrame
        function CreateFrame(...)
            local f=createFrame(...)
            f.Hide=function() end
            f.SetSize=function() end
            f.SetStatusBarTexture=function() end
            return f
        end
        libraries={}
        libraries['JustAC-BlizzardAPI']={
            IsForever=function() return forever end,
            GetRotationSpells=function() return {123,456} end,
        }
        LibStub=setmetatable({
            NewLibrary=function(_,name)
                assert(libraries[name]==nil)
                libraries[name]={}
                return libraries[name]
            end,
        }, {__call=function(_,name) return libraries[name] end})
        function UnitExists() return false end
        function UnitClass() return 'Rogue','ROGUE',4 end
        function UnitLevel() return 60 end
        function GetInstanceInfo() return 'Test','none',0,nil,nil,nil,nil,1 end
        function UnitIsDeadOrGhost() return false end
        function IsPlayerMoving() return false end
        function GetCVar() return '0' end
        addon.db={profile={}}
    """)
    files = DEBUG_FILES + (RESEARCH_FILES if research else [])
    for path in files:
        lua.execute(SOURCES[path])
    lua.execute("""
        DebugCommands=libraries['JustAC-DebugCommands']
        for name in pairs(DebugCommands._Common) do _G[name]=nil end
        for name in pairs(DebugCommands._Capture) do _G[name]=nil end
        targetEpoch=nil
    """)
    return lua


def test_loaded_modules():
    expected_files = {ROOT / "DebugCommands.lua", *(ROOT / "Debug").glob("*.lua")}
    assert set(DEBUG_FILES) == expected_files, "every diagnostic file must load through the TOC"
    assert len(DEBUG_FILES) == len(set(DEBUG_FILES)), "no duplicate TOC loads"
    for research in ((False, True) if RESEARCH_FILES else (False,)):
        files = DEBUG_FILES + (RESEARCH_FILES if research else [])
        methods = set(re.findall(r"function DebugCommands\.(\w+)\(", "\n".join(SOURCES[p] for p in files)))
        for forever in (False, True):
            for external in (False, True):
                lua = loaded_runtime(forever, research)
                dc = lua.globals().DebugCommands
                missing = [name for name in methods if lua.eval("type")(dc[name]) != "function"]
                assert not missing, missing
                assert len(lua.globals().timers) == 0, "loading research must not start capture"
                for name in ("_diagnosticSession", "_probeSession", "_errorCapture", "_locWatch", "_selfCast"):
                    assert dc[name] is None
                lua.execute("""
                    local ids=DebugCommands._Common.RotationIds(1)
                    assert(#ids==1 and ids[1]==123)
                    DebugCommands._Common.ProbeReport(addon)('control',function() return false end)
                    assert(output[#output]:find('plain',1,true))
                    local proxy=DebugCommands._Capture.LogProxy(addon)
                    proxy:Print('loaded proxy')
                    assert(JustACGlobal.probeLog[#JustACGlobal.probeLog]=='loaded proxy')
                    batteryCalls={}
                    for _,name in ipairs({'SecrecyMapProbe','ValidateAssumptions','DurationProbe',
                        'AuraInstanceIdsProbe','CooldownFieldsProbe','FrameStateProbe',
                        'CooldownViewerItemsProbe','EngineSignalsProbe','ForeverProbe','ForeverAuraProbe'}) do
                        if DebugCommands[name] then
                            DebugCommands[name]=function() batteryCalls[name]=(batteryCalls[name] or 0)+1 end
                        end
                    end
                """)
                if external:
                    dc.ErrorCapture(lua.globals().addon, "on")
                    dc.ProbeSession(lua.globals().addon, "on")
                dc.StartDiagnostics(lua.globals().addon)
                s = dc._diagnosticSession
                assert s is not None, lines(lua)
                assert s.ownsAudit == (not external) and s.ownsErrors == (not external)
                assert s.last.forever == f"plain:{str(forever).lower()}"
                assert s.last.researchAvailable == f"plain:{str(research).lower()}"
                if research:
                    assert s.last["signal.priorityGates"] is not None
                    assert s.last["signal.rogueArchetype"] is not None
                else:
                    assert s.last["signal.priorityGates"] is None
                    assert s.last["signal.rogueArchetype"] is None
                    assert "Research unavailable" in lines(lua)
                    assert dc.GetInspectTopics()["forever"] is None
                    assert "foreverauras" not in dc.GetInspectUsage()
                    assert dc.GetInspectTopics()["modules"] == "ModuleDiagnostics"
                for name in dc.GetInspectTopics().values():
                    assert lua.eval("type")(dc[name]) == "function"
                calls = lua.globals().batteryCalls
                assert calls.ValidateAssumptions == 1
                assert calls.ForeverProbe == (1 if forever and research else None)
                assert calls.ForeverAuraProbe == (1 if forever and research else None)
                timer_count = len(lua.globals().timers)
                dc.StartDiagnostics(lua.globals().addon)
                assert len(lua.globals().timers) == timer_count
                audit, errors = dc._probeSession, dc._errorCapture
                lua.globals().audit = audit
                lua.globals().errors = errors
                audit.scripts.OnEvent(None, "PLAYER_TARGET_CHANGED")
                if research:
                    dc._probeTicker.fn()
                log = list(lua.globals().JustACGlobal.probeLog.values())
                if research:
                    assert any("CURSE snapshot" in line and "epoch=1" in line for line in log)
                assert not any("AUDIT SAMPLE ERROR" in line for line in log), log
                dc.StopDiagnostics(lua.globals().addon)
                assert s.ticker.cancelled is True and s.frame.unregistered is True
                assert lua.globals().JustACGlobal.diagnosticSummary.id == s.id
                if external:
                    lua.execute("assert(DebugCommands._probeSession==audit and DebugCommands._errorCapture==errors)")
                    assert audit.unregistered is None and errors.unregistered is None
                    dc.ProbeSession(lua.globals().addon, "off")
                    dc.ErrorCapture(lua.globals().addon, "off")
                else:
                    assert audit.unregistered is True and errors.unregistered is True
                assert dc._probeSession is None and dc._errorCapture is None
                assert dc._locWatch is None and dc._selfCast is None
                assert all(timer.cancelled for timer in lua.globals().timers.values())
                dc.DiagnosticReport(lua.globals().addon)


def test_log_capacity():
    for research in ((False, True) if RESEARCH_FILES else (False,)):
        lua = loaded_runtime(True, research)
        limit = 32000 if research else 8000
        lua.globals().limit = limit
        lua.execute("""
            JustACGlobal={
                diagnosticBaseline={id='baseline'},
                diagnosticSummary={id='summary'},
            }
            DebugCommands._diagnosticSession={dropped=0}
            local emit=DebugCommands._Capture.ProbeLogEmit
            for i=1,limit do emit('row '..i) end
            assert(#JustACGlobal.probeLog==limit)
            assert(JustACGlobal.probeLogDropped==nil)
            emit('overflow')
            local kept=math.floor(limit/2)
            assert(#JustACGlobal.probeLog==kept)
            assert(JustACGlobal.probeLog[kept]=='overflow')
            assert(JustACGlobal.probeLog[1]=='row '..(limit-kept+2))
            assert(JustACGlobal.probeLogDropped==limit+1-kept)
            assert(DebugCommands._diagnosticSession.dropped==limit+1-kept)
            assert(JustACGlobal.diagnosticBaseline.id=='baseline')
            assert(JustACGlobal.diagnosticSummary.id=='summary')
        """)


def test_loaded_recovery_mana():
    for research in ((False, True) if RESEARCH_FILES else (False,)):
        for forever in (False, True):
            for capacity, expected in (
                ("0", "plain:not applicable: no mana"),
                ("100", "plain:false"),
                ("secretCapacity", "plain:unknown mana capacity"),
            ):
                lua = loaded_runtime(forever, research)
                lua.execute("""
                    secretCapacity={}
                    function issecretvalue(value) return value==secretCapacity end
                    Enum={PowerType={Mana=0}}
                    libraries['JustAC-PrecombatEngine']={
                        GetRecoveryThresholds=function(pct)
                            assert(pct==nil or pct==60)
                            return 80,pct or 40
                        end,
                    }
                    local B=libraries['JustAC-BlizzardAPI']
                    B.IsUnitHealthBelow=function() return false end
                    B.IsUnitPowerBelow=function(unit,pct,powerType)
                        if powerType~=nil then
                            assert(unit=='player' and pct==60 and powerType==0)
                            manaCalls=(manaCalls or 0)+1
                        end
                        return false
                    end
                    DebugCommands.RunProbeBattery=function() end
                    addon.GetProfile=function()
                        return {precombatBuffs={recoveryManaThreshold=60}}
                    end
                """)
                lua.execute("function UnitPowerMax() return " + capacity + " end")
                dc = lua.globals().DebugCommands
                dc.StartDiagnostics(lua.globals().addon)
                session = dc._diagnosticSession
                assert session is not None, lines(lua)
                result = session.last.recoveryManaBelow
                assert result == (expected if forever else "nil:nil"), result
                assert lua.globals().manaCalls == (1 if forever and capacity == "100" else None)
                dc.StopDiagnostics(lua.globals().addon)


def test_rotation_target_enemy_context():
    lua = loaded_runtime(True, False)
    lua.execute("""
        secretThreat={}
        function issecretvalue(value) return value==secretThreat end
        units={target=true,nameplate1=true,nameplate2=true,nameplate3=true,nameplate4=true}
        function UnitExists(unit) return units[unit] or false end
        function UnitCanAttack(_,unit) return unit~='nameplate4' end
        function UnitCreatureType(unit) assert(unit=='target'); return 'Undead',6 end
        function UnitClassification() return 'elite' end
        function UnitLevel(unit) if unit=='target' then return 7 end return 6 end
        threats={nameplate1=0,nameplate3=secretThreat}
        function UnitThreatSituation(_,unit) return threats[unit] end
        C_Spell={IsSpellUsable=function(id)
            if id==678 then return false,true end
            return true,false
        end}
        local B=libraries['JustAC-BlizzardAPI']
        B.GetEngagedEnemyCount=function() return 1 end
        B.IsSpellUsable=function(id,failOpen)
            assert(failOpen==true)
            if id==678 then return false,true end
            return true,false
        end
        B.IsSpellReady=function(id) return id~=20271,'test source' end
        B.AbilityInRange=function(id) if id==20271 then return false end return true end
        B.GetClassResourcePoints=function() return nil end
        libraries['JustAC-SpellQueue']={
            DebugContextState=function()
                return {simcCtx='aoe',enemies=1,outOfMelee=false,dying=true,execute=false,pickID=679}
            end,
            _SimcGateBlocks=function(gates) return gates.blocked==true end,
        }
        libraries['JustAC-RotationImport']={
            GetRotationGated=function(context)
                requestedContext=context
                return {
                    {id=679,gates={}},
                    {id=20271,gates={blocked=true},delegated=true},
                }
            end,
            HighestKnownRank=function(id) if id==679 then return 678 end end,
        }
        addon.spellIcons={{currentSpellID=678,IsShown=function() return true end,
            GetAlpha=function() return 1 end,iconTexture={IsShown=function() return true end}}}
        DebugCommands.RunProbeBattery=function() end
    """)
    dc = lua.globals().DebugCommands
    dc.StartDiagnostics(lua.globals().addon)
    s = dc._diagnosticSession
    assert s is not None, lines(lua)
    assert lua.globals().requestedContext == "aoe"
    rotation = s.last.rotationEligibility
    assert "context=aoe entries=2" in rotation
    assert "1:679>678 raw=false/true helper=false/true ready=true/test source range=true gate=ok q=1" in rotation
    assert "2:20271>20271" in rotation and "ready=false/test source range=false gate=block/delegated q=-" in rotation
    assert s.last.targetContext == "plain:type=Undead typeID=6 classification=elite level=7"
    assert s.last.queueContext == "plain:simc=aoe enemies=1 outOfMelee=false dying=true execute=false pick=679"
    assert s.last.enemyProvenance == (
        "plain:plates=4 hostile=3 threat=1 noThreat=1 unknown=1 threatApi=true helper=1"
    )
    dc.StopDiagnostics(lua.globals().addon)
    assert "enemyProvenance=plain:plates=4" in lines(lua)


def test_eligibility_evidence_capture():
    for forever in (False, True):
        lua = loaded_runtime(forever, True)
        lua.execute("""
            DebugCommands.RunProbeBattery=function() end
            clock=10
            function GetTime() return clock end
            secretPayload=setmetatable({}, {__index=function() error('secret payload accessed') end})
            function issecretvalue(value) return rawequal(value,secretPayload) end
            local B=libraries['JustAC-BlizzardAPI']
            B.GetBarSpells=function() return {{id=679,slot=1}} end
            B.GetActionInfo=function() return 'spell',679 end
            B.AbilityInRange=function() return false end
            nativeRangeCalls=0
            C_ActionBar={IsActionInRange=function() nativeRangeCalls=nativeRangeCalls+1; return false end,
                EnableActionRangeCheck=function() error('must not alter range subscriptions') end}
            C_Spell={IsSpellInRange=function() return false end}
            C_CombatLog={IsCombatLogRestricted=function() return true end}
            C_CVar={GetCVarBool=function(name) assert(name=='damageMeterEnabled'); return true end}
            function SetCVar() error('must not alter settings') end
            function GetGameMessageInfo(index)
                assert(index==23)
                if denyMapping then error('mapping denied') end
                return 'SPELL_FAILED_OUT_OF_RANGE'
            end
            Enum={DamageMeterSessionType={Overall=0,Current=1,Expired=2},DamageMeterType={DamageDone=0}}
            function UnitGUID(unit) assert(unit=='player'); return 'player-guid' end
            aggregateCalls=0
            meterSource={totalAmount=25,combatSpells={{spellID=679,totalAmount=25,amountPerSecond=5}}}
            C_DamageMeter={
                IsDamageMeterAvailable=function() return true,'available' end,
                GetSessionDurationSeconds=function(kind) return kind+10 end,
                GetCombatSessionSourceFromID=function(id,kind,guid)
                    assert(combat~=true, 'aggregates must never be read in combat')
                    assert(id==42 and kind==0 and guid=='player-guid')
                    aggregateCalls=aggregateCalls+1
                    return meterSource
                end,
            }
        """)
        dc = lua.globals().DebugCommands
        dc.StartDiagnostics(lua.globals().addon)
        s = dc._diagnosticSession
        assert s is not None, lines(lua)
        event = s.frame.scripts.OnEvent
        event(s.frame, "ACTION_RANGE_CHECK_UPDATE", 1, False, False)
        s.ticker.fn()
        text = s.last["signal.range.event"]
        assert "raw=plain:false" in text and "verdict=plain:unknown:no check" in text
        event(s.frame, "SPELL_RANGE_CHECK_UPDATE", 679, False, True)
        s.ticker.fn()
        assert "verdict=plain:false" in s.last["signal.range.event"]
        assert "helper=plain:false" in s.last["signal.range.event"]
        size = len(lua.globals().JustACGlobal.probeLog)
        event(s.frame, "SPELL_RANGE_CHECK_UPDATE", 679, False, True)
        assert len(lua.globals().JustACGlobal.probeLog) == size, "identical range evidence is suppressed"
        s.ticker.fn()
        assert s.last["signal.evidence.suppressed"] == "plain:1"
        size = len(lua.globals().JustACGlobal.probeLog)
        event(s.frame, "SPELL_RANGE_CHECK_UPDATE", 679, False, False)
        assert len(lua.globals().JustACGlobal.probeLog) == size + 1, "validity transitions survive"
        event(s.frame, "UNIT_SPELLCAST_SENT", "player", "target", "cast-1", 679)
        event(s.frame, "UI_ERROR_MESSAGE", 23, "localized error")
        s.ticker.fn()
        text = s.last["signal.failure.event"]
        assert "name=plain:SPELL_FAILED_OUT_OF_RANGE" in text
        assert "recentCast=plain:679" in text and "association=unconfirmed" in text
        assert "localized error" not in text
        event(s.frame, "PLAYER_TARGET_CHANGED")
        event(s.frame, "UI_ERROR_MESSAGE", 23, "localized error")
        s.ticker.fn()
        assert "recentCast=none" in s.last["signal.failure.event"], "target swaps break correlation"
        lua.execute("denyMapping=true")
        event(s.frame, "UI_ERROR_MESSAGE", 23, "localized error")
        s.ticker.fn()
        assert "err:" in s.last["signal.failure.event"] and "mapping denied" in s.last["signal.failure.event"]
        event(s.frame, "UNIT_SPELLCAST_FAILED", "player", "cast-1", 679)
        s.ticker.fn()
        assert "UNIT_SPELLCAST_FAILED spell=plain:679" in s.last["signal.failure.event"]
        lua.execute("combat=true")
        event(s.frame, "PLAYER_REGEN_DISABLED")
        event(s.frame, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 42)
        event(s.frame, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 1, 42)
        meter_rows = len(lua.globals().JustACGlobal.probeLog)
        event(s.frame, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 42)
        assert len(lua.globals().JustACGlobal.probeLog) == meter_rows, "interleaved meter types deduplicate"
        s.ticker.fn()
        assert lua.globals().aggregateCalls == 0
        assert "unavailable:in combat" in s.last["signal.meter.postCombat"]
        before_range_calls = lua.globals().nativeRangeCalls
        for index in range(125):
            event(s.frame, "ACTION_RANGE_CHECK_UPDATE", 1, bool(index % 2), True)
        s.ticker.fn()
        assert s.last["signal.evidence.dropped"] == "plain:5"
        assert lua.globals().nativeRangeCalls - before_range_calls == 120
        lua.execute("combat=false")
        event(s.frame, "PLAYER_REGEN_ENABLED")
        assert "session=42" in s.last["signal.meter.postCombat"]
        assert "679:damage=plain:25" in s.last["signal.meter.postCombat"]
        assert "Current=plain:11" in s.last["signal.meter.duration"]
        lua.execute("meterSource={combatSpells=secretPayload};clock=clock+2")
        s.ticker.fn()
        assert "secret:<secret>" in s.last["signal.meter.postCombat"]
        assert "secret payload accessed" not in s.last["signal.meter.postCombat"]
        lua.execute("meterSource=secretPayload;clock=clock+2")
        s.ticker.fn()
        assert "secret:<secret>" in s.last["signal.meter.postCombat"]
        event(s.frame, "DAMAGE_METER_RESET")
        s.ticker.fn()
        assert "untested:no notified session" in s.last["signal.meter.postCombat"]
        log = list(lua.globals().JustACGlobal.probeLog.values())
        assert any("EVIDENCE failure session=" + s.id in row for row in log)
        dc.StopDiagnostics(lua.globals().addon)
        size = len(lua.globals().JustACGlobal.probeLog)
        event(s.frame, "UI_ERROR_MESSAGE", 23, "localized error")
        assert len(lua.globals().JustACGlobal.probeLog) == size


def test_low_health_heal_glow():
    source = (ROOT / "UI" / "UIRenderer.lua").read_text(encoding="utf-8")
    start = source.index("local function IsUrgentPreparation(")
    end = source.index("\n-- Per-frame defensive visual state", start)
    for forever in (False, True):
        lua = runtime()
        lua.execute("""
            SpellDB={IsHealingSpell=function(id) return id==635 end}
            below, ready, usable, unneeded = true,true,true,false
            personal={635}
            B={
                IsUnitHealthBelow=function(unit,pct)
                    assert(unit=='player' and pct==50)
                    if below==nil and vignette then return true,'vignette' end
                    return below,'gate'
                end,
                GetLowHealthState=function() return vignette end,
                IsSpellReady=function() return ready end,
                IsSpellUsable=function(_,failOpen) assert(failOpen==false); return usable end,
                GetAddon=function() return addon end,
                GetDisplaySpellID=function(id) if id==639 then return 635 end; return id end,
                IsHealingUnneeded=function() return unneeded end,
            }
            BlizzardAPI=B
            LibStub=function() return {GetClassSpellList=function() return personal end} end
            function WakeWhenReady() end
            function fresh()
                icon={currentID=635,spellID=635,defGlowMode='all',defShowGlow=true}
                below,ready,usable,unneeded=true,true,true,false
                vignette=false
                personal={635}
            end
            fresh()
        """)
        lua.globals().forever = forever
        lua.execute(source[start:end].replace("local function ", "function "))
        fn = lua.globals().ComputeDefensiveGlowState
        assert fn(lua.globals().icon, False) == "proc"
        assert lua.globals().icon.defGlowReason == "low-health"
        for setup, expected in (
            ("below=false", "marching"), ("below=nil", "marching"),
            ("below=nil; vignette=true", "proc"),
            ("below=false; vignette=true", "marching"),
            ("ready=false", "marching"), ("usable=false", "marching"),
            ("usable=nil", "marching"), ("personal={}", "marching"),
            ("personal={639}", "proc"), ("icon.currentID=136; icon.spellID=136", "marching"),
            ("icon.defShowGlow=false", "none"), ("icon.isWaiting=true", "none"),
            ("icon.isItem=true", "marching"), ("icon.isPrecombatBuff=true", "precombat"),
            ("icon.defGlowMode='none'", "none"), ("icon.defGlowMode='procOnly'", "none"),
            ("icon.defGlowMode='primaryOnly'", "proc"),
        ):
            lua.execute("fresh(); " + setup)
            assert fn(lua.globals().icon, False) == expected, (forever, setup)
        lua.execute("fresh(); icon.defGlowMode='procOnly'; below=false")
        assert fn(lua.globals().icon, True) == "proc"
        assert lua.globals().icon.defGlowReason == "proc"
        lua.execute("fresh(); unneeded=true; below=false")
        assert fn(lua.globals().icon, True) == "marching"
        lua.execute("fresh(); below=nil; vignette=true")
        assert fn(lua.globals().icon, False) == "proc"
        assert lua.globals().icon.defGlowReason == "low-health-fallback"


def test_critical_preparation_glow():
    source = (ROOT / "UI" / "UIRenderer.lua").read_text(encoding="utf-8")
    lua = runtime(Lua51Runtime)
    lua.execute("""
        UIAnimations={};missing=true;procActive=false
        LibStub=setmetatable({NewLibrary=function() return UIAnimations end}, {
            __call=function(_,name)
                if name=='JustAC-PrecombatEngine' then
                    return {ShouldEmphasizePreparation=function() return missing end}
                end
            end,
        })
        function object()
            local o={scripts={},shown=false,playing=false,paused=false}
            setmetatable(o,{__index=function() return function() end end})
            function o:Show() self.shown=true end
            function o:Hide()
                self.shown=false
                if self.scripts.OnHide then self.scripts.OnHide() end
            end
            function o:IsShown() return self.shown end
            function o:Play() self.playing=true;self.paused=false end
            function o:Stop() self.playing=false;self.paused=false end
            function o:Pause() self.playing=false;self.paused=true end
            function o:IsPlaying() return self.playing end
            function o:IsPaused() return self.paused end
            function o:SetScript(key,fn) self.scripts[key]=fn end
            function o:SetVertexColor(r,g,b) self.tint={r,g,b} end
            function o:SetDesaturated(value) self.desaturated=value end
            function o:CreateTexture() return object() end
            function o:CreateAnimationGroup() return object() end
            function o:CreateAnimation() return object() end
            return o
        end
        function CreateFrame() return object() end
        SpellDB={IsHealingSpell=function() return false end}
        BlizzardAPI={
            IsSpellReady=function() return true end,
            IsSpellProcced=function() return procActive end,
        }
        SpellQueue={}
        icon={currentID=20154,spellID=20154,isPrecombatBuff=true,defGlowMode='all',
            defShowGlow=true,cachedIconSize=45,GetFrameLevel=function() return 0 end}
    """)
    lua.execute((ROOT / "UI" / "UIAnimations.lua").read_text(encoding="utf-8"))
    lua.execute("""
        UIAnimations.ShowColoredProcGlow(icon,'retintGlow',0.6,1,0.6)
        local frame=icon.retintGlow
        UIAnimations.ShowColoredProcGlow(icon,'retintGlow',1,0.6,0.25)
        assert(icon.retintGlow==frame and frame.ProcLoopFlipbook.tint[1]==1,
            'a reused named frame must honor the newly requested tint')
        UIAnimations.HideColoredProcGlow(icon,'retintGlow')
        UIAnimations.StartDefensiveGlow(icon,true)
        assert(icon.DefensiveHighlightFrame.Flipbook.desaturated==true,
            'a green defensive cue must not retain the native blue atlas')
        UIAnimations.StopAllGlows(icon)
        UIAnimations.StartPrecombatGlow(icon,false)
        assert(icon.PrecombatHighlightFrame.Flipbook.desaturated==true,
            'preparation must use a neutral base before tinting')
        UIAnimations.StopAllGlows(icon)
    """)
    start = source.index("-- Blue: \"this mitigation")
    end = source.index("-- Pet-heal cue threshold", start)
    lua.execute(source[start:end].replace("local MAINTENANCE_GLOW", "MAINTENANCE_GLOW"))
    lua.execute("""
        local colors=UIAnimations.GLOW_COLORS
        local function matches(texture,color)
            assert(texture.tint[1]==color.r and texture.tint[2]==color.g and texture.tint[3]==color.b)
        end
        UIAnimations.StartGapCloserGlow(icon)
        matches(icon.GapCloserHighlightFrame.Flipbook,colors.MOVEMENT)
        assert(icon.GapCloserHighlightFrame.Flipbook.desaturated==true)
        UIAnimations.StopAllGlows(icon)
        UIAnimations.StartBurstGlow(icon)
        matches(icon.BurstHighlightFrame.Flipbook,colors.BURST)
        assert(colors.BURST.r>colors.BURST.b, 'offensive burst must not read as violet preparation')
        UIAnimations.StopAllGlows(icon)
        UIAnimations.StartMaintenanceGlow(icon)
        UIAnimations.ShowColoredProcGlow(icon,'maintenanceGlow',MAINTENANCE_GLOW.r,MAINTENANCE_GLOW.g,MAINTENANCE_GLOW.b)
        matches(icon.MaintenanceHighlightFrame.Flipbook,colors.MAINTENANCE)
        matches(icon.maintenanceGlow.ProcLoopFlipbook,colors.MAINTENANCE)
        UIAnimations.StopAllGlows(icon)
        UIAnimations.HideColoredProcGlow(icon,'maintenanceGlow')
        UIAnimations.StartPrecombatGlow(icon,false)
        UIAnimations.ShowPreparationGlow(icon)
        matches(icon.PrecombatHighlightFrame.Flipbook,colors.PREPARATION)
        matches(icon.PreparationProcGlowFrame.ProcLoopFlipbook,colors.PREPARATION)
        UIAnimations.StopAllGlows(icon)
        UIAnimations.ShowProcGlow(icon,true)
        assert(rawget(icon.ProcGlowFrame.ProcLoopFlipbook,'tint')==nil,
            'native proc art must keep its authored gold')
        UIAnimations.StopAllGlows(icon)
    """)
    start = source.index("local function ApplyMaintenanceGlow(")
    end = source.index("\n-- Single teardown", start)
    lua.execute(source[start:end].replace("local function ", "function "))
    lua.execute("""
        local colors=UIAnimations.GLOW_COLORS
        ApplyMaintenanceGlow(icon,'burst',colors.MAINTENANCE)
        local frame=icon.maintenanceGlow
        ApplyMaintenanceGlow(icon,'burst',colors.DEFENSIVE)
        assert(icon._maintGlowColor==colors.DEFENSIVE and icon.maintenanceGlow==frame)
        assert(frame.ProcLoopFlipbook.tint[2]==colors.DEFENSIVE.g,
            'a heal taking over the same loud stage must replace the blue mitigation tint')
        ApplyMaintenanceGlow(icon,'burst',colors.MOVEMENT)
        assert(frame.ProcLoopFlipbook.tint[1]==colors.MOVEMENT.r,
            'spell/macro escape must share the movement color, not keep a heal tint')
        ApplyMaintenanceGlow(icon,'ants',colors.MAINTENANCE)
        assert(not frame:IsShown() and icon.hasMaintenanceGlow)
        ApplyMaintenanceGlow(icon,nil,colors.MAINTENANCE)
        assert(icon._maintGlow==nil and icon._maintGlowColor==nil and not icon.hasMaintenanceGlow)
    """)
    start = source.index("    local glowColor = MAINTENANCE_GLOW")
    end = source.index("\nend", start)
    lua.execute("function renderClaim(ccSpellID,petSpellID,emergencyHealID) local wantGlow='burst'\n"
                + source[start:end] + "\nend")
    lua.execute("""
        local colors=UIAnimations.GLOW_COLORS
        renderClaim(nil,nil,nil)
        assert(icon._maintGlowColor==colors.MAINTENANCE)
        renderClaim(nil,136,nil)
        assert(icon._maintGlowColor==colors.DEFENSIVE)
        renderClaim(nil,nil,740)
        assert(icon._maintGlowColor==colors.DEFENSIVE)
        renderClaim(42292,nil,nil)
        assert(icon._maintGlowColor==colors.MOVEMENT)
        ApplyMaintenanceGlow(icon,nil,colors.MAINTENANCE)
    """)
    start = source.index("local GLOW_SETTLE_TIME =")
    end = source.index("\n-- Per-frame defensive visual state", start)
    lua.execute(source[start:end].replace("local function ", "function "))
    lua.execute("""
        assert(ComputeDefensiveGlowState(icon,false)=='preparation')
        assert(icon.defGlowReason=='critical-preparation')
        ApplyDefensiveGlow(icon,'preparation',false,false)
        local frame=icon.PreparationProcGlowFrame
        assert(icon.hasPreparationGlow and frame:IsShown() and frame.ProcLoop:IsPlaying())
        assert(not icon.hasProcGlow and not icon.hasPrecombatGlow)
        assert(frame.ProcLoopFlipbook.tint[1]<1 and frame.ProcLoopFlipbook.tint[3]==1)
        missing=false
        assert(ComputeDefensiveGlowState(icon,false)=='precombat')
        ApplyDefensiveGlow(icon,'precombat',false,false)
        assert(not icon.hasPreparationGlow and not frame:IsShown() and not frame.ProcLoop:IsPlaying())
        assert(icon.hasPrecombatGlow, 'normal preparation highlighting must survive a downgrade')
        missing=true
        ApplyDefensiveGlow(icon,'preparation',false,false)
        assert(icon.PreparationProcGlowFrame==frame, 'pooled icons reuse the tinted frame')
        assert(not icon.hasPrecombatGlow)
        assert(ComputeDefensiveGlowState(icon,true)=='proc', 'real proc outranks preparation')
        ApplyDefensiveGlow(icon,'proc',false,false)
        assert(icon.hasProcGlow and not icon.hasPreparationGlow and not frame:IsShown())
        UIAnimations.StopAllGlows(icon)
        assert(not icon.hasPreparationGlow and not icon.hasProcGlow and icon.appliedDefGlowState==nil)
        icon.defGlowMode='procOnly'
        assert(ComputeDefensiveGlowState(icon,false)=='preparation', 'Proc Only includes urgent preparation')
        ApplyDefensiveGlow(icon,ComputeDefensiveGlowState(icon,false),false,true)
        assert(icon.PreparationProcGlowFrame.ProcLoop:IsPlaying(), 'Proc Only preparation animates out of combat')
        assert(ComputeDefensiveGlowState(icon,true)=='proc', 'real procs retain precedence in Proc Only')
        missing=false
        assert(ComputeDefensiveGlowState(icon,false)=='precombat', 'cleared urgency removes the proc-style cue')
        missing=true;icon.defGlowMode='none'
        assert(ComputeDefensiveGlowState(icon,false)=='precombat', 'No Glows preserves baseline precombat policy')
        icon.defGlowMode='primaryOnly'
        assert(ComputeDefensiveGlowState(icon,false)=='preparation')
        icon.isWaiting=true
        assert(ComputeDefensiveGlowState(icon,false)=='none')
        icon.isWaiting=false
    """)
    start = source.index("local GLOW_NONE ")
    end = source.index("\nlocal itemIconInfoCache", start)
    resolver = source[start:end].replace("local function ", "function ")
    start = source.index("        if glowState == GLOW_PREPARATION then")
    end = source.index("\n        -- Re-query only", start)
    lua.execute(resolver + "\nfunction draw(glowState) local ctx={inCombat=true}\n"
                + source[start:end] + "\nend")
    lua.execute("""
        assert(ResolveGlowState(1,20154,true,true,true)==5)
        assert(ResolveGlowState(2,20154,true,false,false)==5)
        assert(ResolveGlowState(1,20154,false,true,true)==5, 'Proc Only includes preparation in shared DPS/nameplate rendering')
        assert(ResolveGlowState(2,20154,false,true,false)==5)
        assert(ResolveGlowState(1,20154,false,false,false)==0, 'No Glows suppresses preparation emphasis')
        procActive=true
        assert(ResolveGlowState(1,20154,true,true,true)==2)
        procActive=false;missing=false
        assert(ResolveGlowState(1,20154,false,true,false)==0, 'Proc Only does not light ordinary recommendations')
        assert(ResolveGlowState(1,20154,true,true,true)==1)
        assert(ResolveGlowState(2,20154,true,true,true)==0)
    """)
    lua.execute("""
        draw(5)
        assert(icon.hasPreparationGlow and not icon.hasProcGlow)
        draw(2)
        assert(icon.hasProcGlow and not icon.hasPreparationGlow)
        draw(5);draw(0)
        assert(not icon.hasPreparationGlow and not icon.hasProcGlow)
        draw(5);UIAnimations.StopAllGlows(icon)
        assert(not icon.PreparationProcGlowFrame:IsShown())
        draw(5)
        local addon={spellIcons={icon}}
        UIAnimations.PauseAllGlows(addon)
        assert(icon.PreparationProcGlowFrame.ProcLoop:IsPlaying(), 'preparation also animates OOC')
        icon.PreparationProcGlowFrame:Hide()
        assert(not icon.PreparationProcGlowFrame.ProcLoop:IsPlaying())
        UIAnimations.ResumeAllGlows(addon)
        assert(icon.PreparationProcGlowFrame:IsShown() and icon.PreparationProcGlowFrame.ProcLoop:IsPlaying())
        UIAnimations.StopAllGlows(icon);UIAnimations.ResumeAllGlows(addon)
        assert(not icon.PreparationProcGlowFrame:IsShown(), 'resume must not resurrect a cleared preparation cue')
        draw(5);UIAnimations.PauseAllGlows({defensiveIcons={icon}})
        assert(not icon.hasPreparationGlow and icon.appliedDefGlowState==nil)
        ApplyDefensiveGlow(icon,'preparation',false,false)
        assert(icon.hasPreparationGlow, 'defensive transition rebuild restores the correct cue')
    """)


def test_shared_health_fallback():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("function BlizzardAPI.IsUnitHealthBelow(")
    end = source.index("\n---", start)
    lua = runtime()
    lua.execute("""
        BlizzardAPI={GetLowHealthState=function() return warning end}
        function CachedBelow() return gate end
        function UnitIsDeadOrGhost() return dead==true end
        warning=true
    """)
    lua.execute(source[start:end])
    fn = lua.globals().BlizzardAPI.IsUnitHealthBelow
    for unit, pct, expected in (
        ("player", 35, True), ("player", 50, True), ("player", 90, True),
        ("player", 20, None), ("pet", 50, None), ("target", 90, None),
        ("player", 101, None),
    ):
        assert fn(unit, pct)[0] == expected, (unit, pct)
    lua.execute("gate=false")
    assert fn("player", 90) == (False, "gate")
    lua.execute("gate=true; warning=false")
    assert fn("player", 20) == (True, "gate")
    lua.execute("gate=nil")
    assert fn("player", 90) == (None, "unknown")
    lua.execute("warning=true; dead=true")
    assert fn("player", 90) == (None, "unknown")


def test_shared_session():
    for existing in (False, True):
        lua = runtime()
        lua.execute("""
            DebugCommands.ProbeSession=function(_,arg)
                if arg=='off' then DebugCommands._probeSession=nil
                else DebugCommands._probeSession={} end
            end
            DebugCommands.ErrorCapture=function(_,arg)
                if arg=='off' then DebugCommands._errorCapture=nil
                else DebugCommands._errorCapture={} end
            end
            B={
                AreAurasSecret=function() return combat==true end,
                AreCooldownsSecret=function() return combat==true end,
                IsUnitHealthBelow=function() return hurt end,
                IsUnitPowerBelow=function() return lowPower end,
                GetPetStatus=function() return 'missing' end,
                IsForever=function() return true end,
            }
            LibStub=function(name) if name=='JustAC-BlizzardAPI' then return B end end
            hurt=false; lowPower=nil
            mapID=1429; form=0
            function UnitClass() return 'Rogue','ROGUE' end
            function UnitLevel() return 1 end
            function GetShapeshiftForm() return form end
            function GetInstanceInfo() return '', 'none', 0, '', 0, 0, false, 0 end
            C_Map={GetBestMapForUnit=function() return mapID end}
            C_AddOns={GetAddOnMetadata=function() return '6.0.0' end}
            function IsResting() return false end
            function IsMounted() return false end
            function UnitInVehicle() return false end
            function GetNumGroupMembers() return 0 end
            function UnitExists() return false end
            function UnitCanAttack() return false end
            function UnitIsFriend() return false end
            Enum={PowerType={Mana=0}}
            manaMax=100
            function UnitPowerMax(_,powerType) assert(powerType==0); return manaMax end
            B.IsUnitPowerBelow=function(_,pct,powerType)
                assert(pct==50)
                if powerType==0 then return lowMana end
                assert(powerType==nil)
                return lowPower
            end
            local getProfile=addon.GetProfile
            profile=getProfile()
            profile.blacklistedSpells={ROGUE={[883]=true,[982]={fixedQueue=true}}}
            addon.GetProfile=function() return profile end
            LibStub=function(name)
                if name=='JustAC-BlizzardAPI' then return B end
                if name=='JustAC-SpellDB' then return {GetSpecKey=function() return 'ROGUE' end} end
                if name=='JustAC-PrecombatEngine' then
                    return {GetRecoveryThresholds=function() return 70,50 end}
                end
                if name=='JustAC-SpellQueue' then
                    return {DebugContextState=function()
                        return {efficiencyReason='conserve mana',efficiencyID=6603,
                            efficiencyRecoverySource='readable',efficiencyResourceDecision='recovery estimate',
                            efficiencyFullSeconds=20,efficiencyBaseFullSeconds=5,
                            efficiencyManaBelow=false,enemies=1,
                            efficiencyCandidates='6603=eligible: unknown',efficiencyRange='unknown'}
                    end}
                end
            end
            addon.spellIcons={{spellID=123,IsShown=function() return true end,GetAlpha=function() return 1 end}}
            addon.defensiveIcons={{
                currentID=635,defGlowMode='all',defShowGlow=true,appliedDefGlowState='marching',
                IsShown=function() return true end,GetAlpha=function() return 1 end,
            }}
            metadataReads=0
            C_AddOns.GetAddOnMetadata=function()
                metadataReads=metadataReads+1; return '6.0.0'
            end
            clock=0
            function debugprofilestop() clock=clock+0.1; return clock end
            for _,icons in ipairs({addon.spellIcons,addon.defensiveIcons}) do
                for _,icon in ipairs(icons) do icon.iconTexture={IsShown=function() return true end} end
            end
        """)
        if existing:
            lua.execute("DebugCommands._probeSession={}; DebugCommands._errorCapture={}")
        for name in ("DiagnosticReport", "DiagnosticStatus", "StopDiagnostics", "StartDiagnostics"):
            lua.execute(method(name))
        dc = lua.globals().DebugCommands
        dc.StartDiagnostics(lua.globals().addon)
        s = dc._diagnosticSession
        assert s.ownsAudit == (not existing)
        assert s.ownsErrors == (not existing)
        dc.StartDiagnostics(lua.globals().addon)
        assert len(lua.globals().timers) == 1
        assert "nil:" in s.last.powerBelow50
        assert "123" in s.last.displayed
        assert s.last["class"] == "plain:ROGUE"
        assert s.last.mapID == "plain:1429"
        assert s.last.addonVersion == "plain:6.0.0"
        assert s.last.instanceType == "plain:none"
        assert s.last.efficiencyMode == "plain:off"
        assert s.last.efficiencyManaThreshold == "plain:40"
        assert s.last.efficiencyReason == "plain:conserve mana"
        assert s.last.efficiencyID == "plain:6603"
        assert s.last.efficiencyRecoverySeconds == "plain:10"
        assert "combatSeconds=20 baseSeconds=5" in s.last.efficiencyRecovery
        assert s.last.efficiencyCandidates == "plain:6603=eligible: unknown"
        assert s.last.efficiencyManaBelow == "plain:false", "false must not become nil"
        assert s.last.efficiencyEnemies == "plain:1"
        assert "883:true" in s.last.blacklist and "982:fixedQueue=true" in s.last.blacklist
        assert "main[1]=123" in s.last.displayed
        session_id = s.id
        baseline = lua.globals().JustACGlobal.diagnosticBaseline
        assert baseline.id == session_id and baseline.last.mapID == "plain:1429"
        assert "applied=marching" in s.last.defensiveGlow
        lua.execute("""
            addon.spellIcons[2]={isWaitingSpell=true,IsShown=function() return true end,GetAlpha=function() return 1 end}
            addon.spellIcons[3]={IsShown=function() return true end,GetAlpha=function() return 1 end}
            addon.spellIcons[4]={isItem=true,itemID=118,IsShown=function() return true end,GetAlpha=function() return 1 end}
            for _,icon in ipairs(addon.spellIcons) do icon.iconTexture={IsShown=function() return true end} end
        """)
        s.ticker.fn()
        assert "main[2]=wait:nil" in s.last.displayed
        assert "main[3]=unidentified" in s.last.displayed
        assert "main[4]=item:118" in s.last.displayed
        lua.execute("""
            addon.spellIcons[3].iconTexture.IsShown=function() return false end
            lowPower=false; lowMana=true
        """)
        s.ticker.fn()
        assert "main[3]" not in s.last.displayed, "empty pooled slot is not a displayed entry"
        assert s.last.powerBelow50 == "plain:false"
        assert s.last.recoveryManaBelow == "plain:true", "mana must be read explicitly, not current resource"
        assert s.last.recoveryHealthThreshold == "plain:70"
        assert s.last.recoveryManaThreshold == "plain:50"
        lua.execute("manaMax=0")
        s.ticker.fn()
        assert "not applicable" in s.last.recoveryManaBelow
        initial = s.changes
        s.ticker.fn()
        assert s.changes == initial, "unchanged samples must not emit"
        assert lua.globals().metadataReads == 1, "metadata must be read once"
        assert s.sampleMs > 0 and s.sampleMaxMs > 0
        lua.execute("profile.precombatBuffs.topoffHeal=false")
        s.ticker.fn()
        assert s.last.topoffEnabled == "plain:false", "in-place configuration changes remain live"
        lua.execute("profile.precombatBuffs.topoffHeal=true")
        lua.execute("combat=true; hurt=true; lowPower=true")
        s.frame.scripts.OnEvent(s.frame, "PLAYER_REGEN_DISABLED")
        assert s.pulls == 1 and "true" in s.last.healthBelow
        lua.execute("mapID=2339; form=1")
        s.frame.scripts.OnEvent(s.frame, "ZONE_CHANGED_NEW_AREA")
        assert s.last.mapID == "plain:2339" and s.last.form == "plain:1"
        assert baseline.last.mapID == "plain:1429", "baseline must not alias live context"
        assert s.id == session_id
        changes = s.changes
        before_event = len(lua.globals().JustACGlobal.probeLog)
        s.frame.scripts.OnEvent(s.frame, "GROUP_ROSTER_UPDATE")
        assert s.changes == changes, "event snapshots must not inflate change counts"
        assert len(lua.globals().JustACGlobal.probeLog) == before_event + 1, "unchanged context emits only its marker"
        burst_start = len(lua.globals().JustACGlobal.probeLog)
        for _ in range(100):
            s.frame.scripts.OnEvent(s.frame, "GROUP_ROSTER_UPDATE")
        assert len(lua.globals().JustACGlobal.probeLog) - burst_start == 100
        assert s.changes == changes
        log = list(lua.globals().JustACGlobal.probeLog.values())
        assert any(f"session={session_id}" in row and "sample=" in row and "elapsed=" in row for row in log)
        dc.DiagnosticStatus(lua.globals().addon)
        assert "errors=true" in lines(lua)
        assert "sampler ms:" in lines(lua)
        lua.execute("for i=1,32100 do ProbeLogEmit('fill '..i) end")
        assert s.dropped > 0 and lua.globals().JustACGlobal.probeLogDropped > 0
        assert lua.globals().JustACGlobal.diagnosticBaseline.last.mapID == "plain:1429"
        old_event = s.frame.scripts.OnEvent
        dc.StopDiagnostics(lua.globals().addon)
        assert "WARNING: detailed capture is incomplete" in lines(lua)
        assert s.ticker.cancelled and s.frame.unregistered
        assert s.signalReads is None and s.signalEvent is None
        assert dc._diagnosticSession is None
        assert (dc._probeSession is not None) == existing
        assert (dc._errorCapture is not None) == existing
        summary = lua.globals().JustACGlobal.diagnosticSummary
        assert summary.id == session_id and summary.samples == s.samples
        assert summary.last.mapID == s.last.mapID and summary.sampleMs == s.sampleMs
        assert summary.dropped == s.dropped
        assert summary.frame is None and summary.ticker is None and summary.audit is None
        # A fresh Lua runtime models reload: only SavedVariables cross the boundary.
        reloaded = runtime()
        def copy_saved(value):
            if hasattr(value, "items"):
                return reloaded.table_from({key: copy_saved(item) for key, item in value.items()})
            return value
        reloaded.globals().JustACGlobal = copy_saved(lua.globals().JustACGlobal)
        reloaded.execute(method("DiagnosticReport"))
        reloaded.globals().DebugCommands.DiagnosticReport(reloaded.globals().addon)
        assert session_id in lines(reloaded) and "mapID=plain:2339" in lines(reloaded)
        assert "no session" not in lines(reloaded)
        assert reloaded.globals().JustACGlobal.diagnosticBaseline.id == session_id
        reloaded.execute("output={}; JustACGlobal.diagnosticSummary=nil")
        reloaded.globals().DebugCommands.DiagnosticReport(reloaded.globals().addon)
        assert "Detailed probeLog entries exist" in lines(reloaded)
        samples = s.samples
        s.ticker.fn()
        old_event(s.frame, "PLAYER_REGEN_DISABLED")
        assert s.samples == samples, "stale ticker callback must not record"
        dc.StopDiagnostics(lua.globals().addon)
        assert "already OFF" in lines(lua)
        dc.StartDiagnostics(lua.globals().addon)
        s = dc._diagnosticSession
        assert s.id != session_id
        s.started = -590
        s.ticker.fn()
        assert dc._diagnosticSession is None
        assert "sampling limit" in lines(lua)
        dc.StartDiagnostics(lua.globals().addon)
        s = dc._diagnosticSession
        lua.execute("addon.GetProfile=function() error('profile failed') end")
        s.ticker.fn()
        assert dc._diagnosticSession is None and s.failures > 0
        assert "sampler failed" in lines(lua)


def test_threshold_verdicts():
    for in_combat in (False, True):
        lua = runtime()
        lua.execute("""
            profile={precombatBuffs={topoffHeal=true,topoffThreshold=90}}
            addon.GetProfile=function() return profile end
            verdict=true
            B={
                IsUnitHealthBelow=function(unit,pct)
                    assert(unit=='player' and pct==90)
                    if fail then error('gate failed') end
                    return verdict
                end,
                IsUnitPowerBelow=function(unit,pct,powerType)
                    assert(unit=='player' and pct==50 and powerType==nil)
                    return verdict
                end,
            }
            LibStub=function() return B end
        """)
        lua.globals().combat = in_combat
        lua.execute(method("ThresholdDiagnostics"))
        fn = lua.globals().DebugCommands.ThresholdDiagnostics
        for value, expected in ((True, "true"), (False, "false"), (None, "unknown")):
            lua.globals().verdict = value
            lua.execute("output={}")
            fn(lua.globals().addon, None)
            assert f"health below 90%: {expected}" in lines(lua)
            assert f"combat={str(in_combat).lower()}" in lines(lua)
            assert "topoff enabled: true" in lines(lua)
            fn(lua.globals().addon, "power 50")
            assert f"power below 50%: {expected}" in lines(lua)
        for arg in ("power", "health 0", "power 101", "health nope", "health 90 extra"):
            lua.execute("output={}")
            fn(lua.globals().addon, arg)
            assert "Usage:" in lines(lua), arg
        lua.execute("output={}; fail=true")
        fn(lua.globals().addon, "health 90")
        assert "read failed:" in lines(lua) and "gate failed" in lines(lua)
        lua.execute("output={}; fail=false; profile.precombatBuffs.topoffHeal=false")
        fn(lua.globals().addon, None)
        assert "topoff enabled: false" in lines(lua)
        lua.execute("output={}; B.IsUnitPowerBelow=nil")
        fn(lua.globals().addon, "power 50")
        assert "helper unavailable" in lines(lua)
    assert SOURCE.count("DebugCommands.ThresholdDiagnostics(addon)") == 2


def test_aura_denial():
    lua = runtime()
    lua.execute("""
        LibStub = function()
            return {GetAuraCache=function()
                return {byID={},byName={},hasSecrets=true,complete=false}
            end}
        end
        C_UnitAuras = {GetAuraDataByIndex=function() error('aura denied') end}
    """)
    lua.execute(method("AuraDiagnostics"))
    lua.globals().DebugCommands.AuraDiagnostics(lua.globals().addon)
    assert "complete: false" in lines(lua)
    assert "Enumeration err" in lines(lua)
    assert "count incomplete" in lines(lua)


def test_census_count():
    lua = runtime()
    lua.execute("""
        mode, reads = 'empty', 0
        secretValue = {}
        issecretvalue = function(v) return v == secretValue end
        local originalTostring = tostring
        tostring = function(v)
            if v == secretValue then error('secret text') end
            return originalTostring(v)
        end
        C_UnitAuras = {GetAuraDataByIndex=function(_, i)
            reads = reads + 1
            if mode == 'denied' or (mode == 'partial' and i == 2) then
                error('aura denied')
            end
            if mode == 'secret' then return secretValue end
            if mode == 'capped' then return {} end
            if mode == 'eight' and i <= 8 then return {} end
        end}
    """)
    start = SOURCE.index("local function CountPlayerAuraInstances(")
    end = SOURCE.index("\nend", start) + len("\nend")
    lua.execute(SOURCE[start:end].replace("local function ", "function ", 1))
    for mode, status, count in (
        ("empty", "plain", 0), ("eight", "plain", 8),
        ("denied", "err", None), ("partial", "err", None),
        ("secret", "secret", None), ("capped", "nil", None),
    ):
        lua.globals().mode = mode
        # Make the partial scan fail after one successful read.
        if mode == "partial":
            lua.execute("""
                C_UnitAuras.GetAuraDataByIndex = function(_, i)
                    if i == 2 then error('aura denied') end
                    return {}
                end
            """)
        got_status, _, value = lua.globals().ProbeRead(lua.globals().CountPlayerAuraInstances)
        assert got_status == status, mode
        if count is not None:
            assert value == count
        if mode == "partial":
            lua.execute("""
                C_UnitAuras.GetAuraDataByIndex = function()
                    if mode == 'secret' then return secretValue end
                    return {}
                end
            """)


def test_buff_unknown_and_preferences():
    lua = runtime()
    lua.execute("""
        profile = {precombatBuffs={categories={flask='haste',food=false}}}
        addon.GetProfile = function() return profile end
        S = {
            GetPrecombatBuffCategories=function() return {'flask','food'} end,
            GetPrecombatBuffItems=function() return {} end,
            GetBestOwnedBuff=function(cat, pref)
                if cat=='flask' then assert(pref=='haste') end
            end,
        }
        E = {
            IsCategorySatisfied=function() return true, false end,
            IsOfferingNow=function() return true end,
            GetMissingBuffs=function(settings)
                assert(settings==profile.precombatBuffs.categories)
                return {}
            end,
        }
        B = {AreAurasSecret=function() return true end}
        LibStub=function(name)
            if name=='JustAC-SpellDB' then return S end
            if name=='JustAC-PrecombatEngine' then return E end
            if name=='JustAC-BlizzardAPI' then return B end
        end
        UnitClass=function() return '', 'WARRIOR' end
        C_Item = {}
    """)
    lua.execute(method("PrecombatBuffDiagnostics"))
    lua.globals().DebugCommands.PrecombatBuffDiagnostics(lua.globals().addon)
    assert "unknown (offer suppressed)" in lines(lua)
    assert "disabled" in lines(lua)
    assert "|cff00ff00active" not in lines(lua)


def test_ticker_lifecycle():
    for name, ticker, sampler in (
        ("MaintenanceLog", "maintLogTicker", "MaintLogSample"),
        ("PickLog", "pickLogTicker", "PickLogSample"),
    ):
        lua = runtime()
        lua.execute(f"""
            local {ticker}
            local lastMaintPayload, lastPickPayload
            local function {sampler}() if fail then error('sample failed') end end
        """ + method(name))
        fn = lua.globals().DebugCommands[name]
        fn(lua.globals().addon, "on")
        fn(lua.globals().addon, "on")
        assert len(lua.globals().timers) == 1, name
        fn(lua.globals().addon, "off")
        assert lua.globals().timers[1].cancelled is True
        fn(lua.globals().addon, "on")
        lua.globals().fail = True
        lua.globals().timers[2].fn()
        assert lua.globals().timers[2].cancelled is True
        assert "sample error" in lines(lua)


def test_battery_failures():
    lua = runtime()
    start = SOURCE.index("local PROBE_BATTERY =")
    end = SOURCE.index("\nfunction DebugCommands.RunProbeBattery(", start)
    battery = SOURCE[start:end]
    lua.execute(battery + method("RunProbeBattery"))
    for forever, expected in ((False, 7), (True, 9)):
        lua.execute("output={}; JustACGlobal={}")
        lua.globals().forever = forever
        lua.execute("LibStub=function() return {IsForever=function() return forever end} end")
        lua.globals().DebugCommands.RunProbeBattery(lua.globals().addon, "TEST", False)
        assert f"{expected} failures" in lines(lua)
        log = lua.globals().JustACGlobal.probeLog
        assert sum("PROBE ERROR" in msg for msg in log.values()) == expected
    lua.execute("""
        clock=0
        function debugprofilestop() clock=clock+1; return clock end
        DebugCommands._diagnosticSession={id='timing-test',pulls=1,failures=0}
    """)
    lua.globals().DebugCommands.RunProbeBattery(lua.globals().addon, "TIMED", False)
    session = lua.globals().DebugCommands._diagnosticSession
    assert session.batteries == 1 and session.batteryMs == 1 and session.batteryMaxMs == 1


def test_delayed_snapshots():
    lua = runtime()
    lua.execute("""
        cycles=0
        curseTargetEpoch=0
        f=CreateFrame()
        DebugCommands._probeSession=f
        captures={}
        function DebugCommands.RunProbeBattery(_, tag) captures[#captures+1]=tag end
    """)
    start = SOURCE.index('    f:SetScript("OnEvent", function(_, event, unit, _, spellID)', SOURCE.index("function DebugCommands.ProbeSession("))
    end = SOURCE.index("\n\n    local curseSample", start)
    lua.execute(SOURCE[start:end])
    event = lua.globals().f.scripts.OnEvent
    event(None, "PLAYER_TARGET_CHANGED")
    assert lua.globals().curseTargetEpoch == 1
    event(None, "UNIT_SPELLCAST_SUCCEEDED", "player", None, 702)
    assert any("epoch=1 spell=702" in line for line in lua.globals().JustACGlobal.probeLog.values())
    lua.globals().combat = True
    event(None, "PLAYER_REGEN_DISABLED")
    event(None, "PLAYER_REGEN_DISABLED")
    lua.globals().callbacks[1]()
    assert len(lua.globals().captures) == 0, "old pull callback must be ignored"
    lua.globals().callbacks[3]()
    assert lua.globals().captures[1] == "COMBAT+4s#2"
    lua.execute("DebugCommands._probeSession = CreateFrame()")
    lua.globals().callbacks[4]()
    assert len(lua.globals().captures) == 1, "old session callback must be ignored"


def test_topoff_log():
    lua = runtime()
    lua.execute("""
        addon.db={profile={precombatBuffs={topoffHeal=true,topoffThreshold=80}}}
        E={GetMissingClassBuffs=function() return {} end}
        B={GetPlayerHealthPercentSafe=function() return 90,false end}
        LibStub=function(name)
            if name=='JustAC-BlizzardAPI' then return B end
            if name=='JustAC-PrecombatEngine' then return E end
        end
    """)
    lua.execute(method("TopoffWatch"))
    fn = lua.globals().DebugCommands.TopoffWatch
    fn(lua.globals().addon, None)
    update = lua.globals().DebugCommands._topoffWatch.scripts.OnUpdate
    update(None, 0.25)
    update(None, 0.25)
    log = lua.globals().JustACGlobal.probeLog
    assert len(log) == 1 and "TOPOFF" in log[1], "save transitions, not repeated samples"
    fn(lua.globals().addon, "off")
    assert lua.globals().frames[1].scripts.OnUpdate is None
    assert "/reload" in lines(lua)
    fn(lua.globals().addon, None)
    lua.execute("E.GetMissingClassBuffs = function() error('topoff denied') end")
    update = lua.globals().DebugCommands._topoffWatch.scripts.OnUpdate
    update(None, 0.25)
    assert lua.globals().DebugCommands._topoffWatch is None
    assert "TOPOFF ERROR" in lua.globals().JustACGlobal.probeLog[2]
    limit = 32000 if RESEARCH_FILES else 8000
    for _ in range(limit + 100):
        lua.globals().ProbeLogEmit("bounded")
    assert len(lua.globals().JustACGlobal.probeLog) <= limit


def test_category_knowledge():
    lua = runtime()
    lua.execute("""
        now, restricted, listKnown, unknownFields = 10, false, true, false
        GetTime=function() return now end
        enchantAppliedAt, ENCHANT_APPLY_GRACE = 0, 1
        hasEnchant, expiry = true, 600000
        BlizzardAPI = {
            AreAurasSecret=function() return restricted end,
            GetWeaponEnhancementInfo=function() return hasEnchant, expiry end,
        }
        SpellDB = {GetPrecombatBuffSet=function() return {[123]=true} end}
        PrecombatEngine = {}
        activeAuras={}
        function SafeAuraList() return activeAuras, listKnown end
        function IsSecret(v) return v == secretValue end
        secretValue={}
        function IsLapsing() return false end
        function RefreshWindow() return 30 end
        function ReportAuraReadError() end
    """)
    source = (ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8")
    for first, last in (
        ("local function WeaponEnchantHolds(", "\n-- The off-hand"),
        ("local function HasAnyAura(", "\nlocal function KnownWeaponImbue("),
        ("function PrecombatEngine.IsCategorySatisfied(", "\n--- Pre-combat buffs"),
    ):
        start = source.index(first)
        end = source.index(last, start)
        lua.execute(source[start:end].replace("local function ", "function "))
    fn = lua.globals().PrecombatEngine.IsCategorySatisfied
    assert fn("flask") == (False, True)
    lua.execute("activeAuras={{spellId=123}}")
    assert fn("flask") == (True, True)
    lua.execute("activeAuras={{spellId=secretValue}}")
    assert fn("flask") == (True, False)
    lua.execute("activeAuras={}; listKnown=false")
    assert fn("flask") == (True, False)
    lua.execute("listKnown=true; restricted=true")
    assert fn("flask") == (True, False)
    lua.execute("restricted=false")
    assert fn("weaponEnchant") == (True, True)
    lua.execute("hasEnchant=nil")
    assert fn("weaponEnchant") == (True, False)
    lua.execute("hasEnchant=true; expiry=secretValue")
    assert fn("weaponEnchant") == (True, False)
    lua.execute("hasEnchant=false")
    assert fn("weaponEnchant") == (False, True)


def test_error_capture_lifecycle():
    lua = runtime()
    start = CAPTURE_SOURCE.index("local ERRORLOG_MAX =")
    end = CAPTURE_SOURCE.index("\nDebugCommands._Capture =")
    lua.execute(CAPTURE_SOURCE[start:end])
    fn = lua.globals().DebugCommands.ErrorCapture
    fn(lua.globals().addon, "on")
    fn(lua.globals().addon, "on")
    assert len(lua.globals().frames) == 1
    fn(lua.globals().addon, "off")
    assert lua.globals().frames[1].unregistered is True
    assert lua.globals().frames[1].scripts.OnEvent is None


def test_audit_lifecycle():
    lua = runtime()
    lua.execute("""
        function DebugCommands.RunProbeBattery() end
        DebugCommands._locWatch={external=true}
        DebugCommands._selfCast={external=true}
        DebugCommands.LossOfControlWatch=function() error('external CC watcher stopped') end
        DebugCommands.SelfCastProbe=function() error('external cast watcher stopped') end
    """)
    lua.execute(method("CurseDiagnostics"))
    lua.execute(method("ProbeSession"))
    fn = lua.globals().DebugCommands.ProbeSession
    fn(lua.globals().addon, "on")
    fn(lua.globals().addon, "on")
    assert len(lua.globals().timers) == 1
    assert len(lua.globals().frames) == 1
    fn(lua.globals().addon, "off")
    assert lua.globals().timers[1].cancelled is True
    assert lua.globals().frames[1].scripts.OnEvent is None
    assert lua.globals().DebugCommands._probeSession is None
    assert lua.globals().DebugCommands._locWatch.external is True
    assert lua.globals().DebugCommands._selfCast.external is True


def test_curse_signals():
    for forever in (False, True):
        lua = runtime()
        lua.globals().forever = forever
        lua.execute("""
            secret=setmetatable({}, {__tostring=function() error('secret formatted') end})
            function issecretvalue(v) return rawequal(v,secret) end
            function UnitExists() return true end
            function UnitCanAttack() return true end
            active=nil
            MT={
                IsTrackedAuraActive=function(id) if id==702 then return active end end,
                ResolveCooldownIDs=function(e)
                    assert(e.cast==e.aura)
                    if e.cast==702 then return {[90]=2,[91]=0} end
                    return {}
                end,
            }
            function LibStub(name)
                if name=='JustAC-MaintenanceTracker' then return MT end
            end
            BuffIconCooldownViewer={IsShown=function() return true end}
            BuffBarCooldownViewer={IsShown=function() return false end}
        """)
        lua.execute(method("CurseDiagnostics"))
        probe = lua.globals().DebugCommands.CurseDiagnostics
        for value, expected in ((None, "unknown"), (False, "false"), (True, "true")):
            lua.globals().active = value
            lua.execute("output={}")
            probe(lua.globals().addon)
            text = lines(lua)
            assert f"spell=702 tracked={expected} mappings=90:2,91:0" in text
            assert "BuffIconCooldownViewer shown=true" in text
            assert "BuffBarCooldownViewer shown=false" in text
        lua.execute("active=secret; output={}")
        probe(lua.globals().addon)
        assert "spell=702 tracked=secret" in lines(lua)
        lua.execute("""
            item={
                GetCooldownID=function() return 90 end,
                IsShown=function() return false end,
                isActive=false,
                GetSpellID=function() return 1714 end,
                GetLinkedSpell=function() return 1714 end,
                GetAuraDataUnit=function() return 'target' end,
                isActiveSpell=1714,
            }
            BuffIconCooldownViewer.itemFramePool={}
            BuffIconCooldownViewer.itemFramePool.EnumerateActive=function()
                local done=false
                return function() if not done then done=true; return item end end
            end
            output={}
        """)
        probe(lua.globals().addon)
        assert "cid=90 shown=false active=false spell=1714 linked=1714 auraUnit=target activeSpell=1714" in lines(lua)
        assert "CURSE unmatched=91" in lines(lua)
        lua.execute("""
            C_CooldownViewer={GetCooldownViewerCooldownInfo=function()
                return {spellID=1319652,category=2,hasAura=true,selfAura=false,
                    linkedSpellIDs={702,1714,704}}
            end}
            item.GetAuraSpellInstanceID=function() error('exploratory instance read removed') end
            C_UnitAuras={GetAuraDataByAuraInstanceID=function() error('must not query aura') end}
            C_TooltipInfo={GetUnitDebuffByAuraInstanceID=function() error('must not query tooltip') end}
            output={}
        """)
        probe(lua.globals().addon)
        text = lines(lua)
        assert "linkedSpellIDs=702,1714,704" in text
        assert "selfAura=false hasAura=true" in text
        assert "CURSE instance" not in text
        assert "BuffIconCooldownViewer matches=1" in text
        lua.execute("""
            C_CooldownViewer.GetCooldownViewerCooldownInfo=function() return secret end
            output={}
        """)
        probe(lua.globals().addon)
        assert "CURSE catalog cid=90 secret" in lines(lua)
        lua.execute("""
            item.isActive=secret
            item.GetSpellID=function() return secret end
            item.GetLinkedSpell=function() error('denied') end
            item.GetAuraDataUnit=nil
            output={}
        """)
        probe(lua.globals().addon)
        assert "active=secret spell=secret linked=denied:" in lines(lua)
        assert "auraUnit=unavailable" in lines(lua)
        lua.execute("item.GetCooldownID=function() return secret end; output={}")
        probe(lua.globals().addon)
        assert "CURSE unmatched=90,91" in lines(lua)
        lua.execute("""
            BuffIconCooldownViewer.itemFramePool.EnumerateActive=function() error('pool denied') end
            output={}
        """)
        probe(lua.globals().addon)
        assert "CURSE items viewer=BuffIconCooldownViewer denied:" in lines(lua)
        lua.execute("MT.IsTrackedAuraActive=function() error('denied') end; output={}")
        probe(lua.globals().addon)
        assert "tracked=denied:" in lines(lua)
        lua.execute("MT=nil; output={}")
        probe(lua.globals().addon)
        assert "tracked=unavailable mappings=unavailable" in lines(lua)
        lua.execute("""
            MT={IsTrackedAuraActive=function() return active end}
            active=false; curseTargetEpoch=0
            output={}
        """)
        start = SOURCE.index("    local curseLast, curseEpoch =")
        end = SOURCE.index("\n    local samples =", start)
        lua.execute(SOURCE[start:end] + "\nSampleCurses=curseSample")
        lua.globals().SampleCurses()
        count = len(lua.globals().JustACGlobal.probeLog)
        lua.globals().SampleCurses()
        assert len(lua.globals().JustACGlobal.probeLog) == count
        lua.execute("active=true")
        lua.globals().SampleCurses()
        assert len(lua.globals().JustACGlobal.probeLog) > count
        delta = list(lua.globals().JustACGlobal.probeLog.values())[count:]
        assert any("tracked=true" in line for line in delta)
        assert any("CURSE removed: CURSE spell=" in line for line in delta)
        assert not any("CURSE viewer=" in line for line in delta), "unchanged rows must not repeat"

        count = len(lua.globals().JustACGlobal.probeLog)
        lua.execute("curseTargetEpoch=1")
        lua.globals().SampleCurses()
        assert len(lua.globals().JustACGlobal.probeLog) == count + 1, "target epoch needs only a marker"
        count = len(lua.globals().JustACGlobal.probeLog)
        lua.execute("BuffIconCooldownViewer=nil")
        lua.globals().SampleCurses()
        delta = list(lua.globals().JustACGlobal.probeLog.values())[count:]
        assert any("CURSE removed: CURSE viewer=BuffIconCooldownViewer shown=true" in line for line in delta)
        assert any("BuffIconCooldownViewer shown=unavailable" in line for line in delta)

    lua = Lua51Runtime(unpack_returned_tuples=True)
    for source in SOURCES.values():
        lua.execute("assert(loadstring(...))", source)


def test_combat_signal_reads():
    for forever in (False, True):
        lua = runtime()
        lua.globals().forever = forever
        lua.execute("""
            now=0; incoming=nil; debt=0; predicted=false
            secret={}; secretFalse={}
            function issecretvalue(v) return v==secret or v==secretFalse end
            function secretwrap(v) if v then return secret else return secretFalse end end
            function GetTime() return now end
            function UnitExists(u) return u~='pet' end
            function UnitIsDeadOrGhost() return false end
            function UnitGetIncomingHeals() return incoming end
            function UnitGetTotalHealAbsorbs() return debt end
            zeroCalls=0
            B={
                IsForever=function() return forever end,
                IsSecretZero=function(v)
                    assert(v~=nil, 'nil must never enter zero gate')
                    zeroCalls=zeroCalls+1
                    if v==secret then return false end
                    if v==secretFalse then return true end
                    return v==0
                end,
                GetBarSpells=function() return {{id=123,slot=1},{id=456,slot=2}} end,
                IsDurationObjectActive=function() return true end,
                IsDurationBelowSeconds=function(_,seconds) assert(seconds==1); return false end,
            }
            LibStub=function(name) if name=='JustAC-BlizzardAPI' then return B end end
            Enum={
                LuaCurveType={Linear=0},
                UnitHealAbsorbMode={ReducedByIncomingHeals=0},
                UnitHealAbsorbClampMode={MaximumHealth=1},
                UnitIncomingHealClampMode={MissingHealth=0},
            }
            calc={}
            function calc:SetHealAbsorbMode(v) assert(v==0) end
            function calc:SetHealAbsorbClampMode(v) assert(v==1) end
            function calc:SetIncomingHealClampMode(v) assert(v==0) end
            function calc:SetIncomingHealOverflowPercent(v) assert(v==1) end
            function calc:ResetPredictedValues() self.populated=false end
            function calc:HasSecretValues() assert(self.populated); return true end
            function calc:GetHealAbsorbs() assert(self.populated); return debt,secret end
            function calc:GetIncomingHeals() assert(self.populated); return incoming,0,0,secret end
            function CreateUnitHealPredictionCalculator() return calc end
            denied=false
            function UnitGetDetailedHealPrediction(_,healer,c)
                assert(healer=='player')
                if denied then error('prediction denied') end
                c.populated=true
            end
            C_CurveUtil={CreateCurve=function()
                return {
                    SetType=function() end, AddPoint=function() end,
                    Evaluate=function(_,v) if v<0.5 then return 100 else return 0 end end,
                }
            end}
            C_CurveUtil.EvaluateColorValueFromBoolean=function(v,yes,no)
                assert(yes==1 and no==0)
                if issecretvalue(v) then return v end
                if v then return yes else return no end
            end
            function UnitHealthPercent(_,prediction)
                if prediction and predicted then return 100 end
                return 0
            end
            castActive=false
            function UnitCastingInfo()
                if castActive then return secret,nil,nil,nil,nil,false,secret,secretFalse,secret,42 end
            end
            function UnitChannelInfo() return nil end
            function PlayerIsSpellTarget() return secret end
            function UnitIsCharmed() return secretFalse end
            function HasFullControl() return true end
            function IsPlayerMoving() return false end
            dur={
                HasSecretValues=function() return true end,
                IsActive=function() return secret end,
                HasExpired=function() return false end,
                HasStarted=function() return true end,
                IsZero=function() return secret end,
            }
            C_LossOfControl={
                GetActiveLossOfControlDataCount=function() return 1 end,
                GetActiveLossOfControlData=function()
                    return {locType=secret,priority=2,displayType=1,lockoutSchool=secret}
                end,
                GetActiveLossOfControlDataCountByUnit=function() return 1 end,
                GetActiveLossOfControlDuration=function() return dur end,
            }
            function UnitHasEffectivelyTankAura() return secret end
            function UnitGroupRolesAssigned() return 'NONE' end
            function HasPetUI() return true,false end
            gcdValue=false
            C_Spell={
                GetSpellCooldown=function() return {isOnGCD=gcdValue} end,
                GetSpellCooldownDuration=function() return dur end,
                IsActiveSpell=function(id) if id==123 then return false else return secret end end,
                IsSpellImportant=function() return secretFalse end,
            }
            bucket={Size=function() return 2 end}
            frame={
                unit='nameplate1',IsVisible=function() return true end,
                aggroHighlight={IsShown=function() return false end},
                AurasFrame={buffList=bucket,debuffList=bucket,crowdControlList=bucket},
            }
            C_NamePlate={GetNamePlateForUnit=function() return {UnitFrame=frame} end}
            item={
                cooldownID=789,IsActive=function() return false end,
                GetAuraDataUnit=function() return 'target' end,IsVisible=function() return true end,
            }
            BuffIconCooldownViewer={
                IsVisible=function() return false end,isEditing=false,
                itemFramePool={EnumerateActive=function()
                    local done=false
                    return function() if not done then done=true; return item end end
                end},
            }
            reads,event=DebugCommands.CombatSignalReads()
        """)
        reads = lua.globals().reads
        assert reads["signal.player.incomingZero"]() == "plain:unknown:nil input"
        assert lua.globals().zeroCalls == 0
        assert reads["signal.player.healDebtZero"]() == "plain:true"
        assert reads["signal.player.tankAura"]() == "secret:<secret>"
        calibration = reads["signal.booleanCalibration"]()
        assert "true=plain:true false=plain:false" in calibration
        assert "secretTrue=plain:true secretFalse=plain:false" in calibration
        assert reads["signal.target.cast"]() == "plain:unavailable:no cast"
        assert reads["signal.player.charmed"]() == "plain:raw=secret:<secret> bridge=plain:false"
        assert "fullControl{plain:raw=plain:true bridge=plain:true}" in reads["signal.player.control"]()
        loc = reads["signal.player.locDetails"]()
        assert "type=secret:<secret>" in loc and "priority=plain:2 display=plain:1" in loc
        assert "123=plain:false" in reads["signal.spells.toggles"]()
        assert "456=secret:<secret>" in reads["signal.spells.toggles"]()
        assert "IsActive=secret:<secret>" in reads["signal.spells.duration"]()
        assert "below1s=plain:false" in reads["signal.target.loc"]()
        assert "crowdControlList=plain:2" in reads["signal.target.nameplate"]()
        assert "visible=plain:false" in reads["signal.viewers"]()
        assert "pandemic=plain:unknown:no marker" in reads["signal.viewers"]()
        assert reads["signal.pet.prediction"]() == "plain:unavailable:no unit"
        lua.execute("incoming=secret; debt=secret; predicted=true; now=1")
        lua.execute("castActive=true")
        cast = reads["signal.target.cast"]()
        assert "barID=plain:42" in cast
        assert "notInterruptible{raw=secret:<secret> bridge=plain:false}" in cast
        assert "important{plain:raw=secret:<secret> bridge=plain:false}" in cast
        assert "onPlayer{plain:raw=secret:<secret> bridge=plain:true}" in cast
        lua.globals().event("UNIT_SPELLCAST_START", "target", "secret-guid", "secret-id", 42)
        assert "arg4=plain:42" in list(lua.globals().JustACGlobal.probeLog.values())[-1]
        assert reads["signal.player.incomingZero"]() == "plain:false"
        prediction = reads["signal.player.prediction"]()
        assert "debtZero=plain:false" in prediction
        assert "debtClamped=secret:<secret>" in prediction
        assert "incomingClamped=secret:<secret>" in prediction
        assert "actual=plain:false predicted=plain:true" in reads["signal.player.health50"]()
        lua.execute("incoming=0")
        assert reads["signal.player.incomingZero"]() == "plain:false", "heavy reads memoized for one second"
        lua.globals().event("UNIT_SPELLCAST_START", "target", "secret-guid", "secret-id", 42)
        assert reads["signal.player.incomingZero"]() == "plain:false", "cast events must not invalidate heavy sibling reads"
        lua.globals().event("PLAYER_TARGET_CHANGED")
        assert reads["signal.targetEpoch"]() == 1
        assert reads["signal.player.incomingZero"]() == "plain:true"
        lua.execute("denied=true; now=2")
        assert "prediction denied" in reads["signal.player.prediction"]()
        assert reads["signal.player.healDebtZero"]() == "plain:false", "one denial must not kill sibling reads"
        lua.globals().event("SPELL_UPDATE_COOLDOWN")
        assert "123=plain:false" in reads["signal.gcd.event"]()
        lua.execute("gcdValue=true; now=3")
        assert "123=plain:true" in reads["signal.gcd.sample"]()
        assert "123=plain:false" in reads["signal.gcd.event"](), "event snapshot must not be overwritten by polling"
        for i in range(125):
            lua.globals().gcdValue = i % 2 == 0
            lua.globals().event("SPELL_UPDATE_COOLDOWN")
        assert reads["signal.gcd.dropped"]() == 6
        lua.globals().event("PLAYER_REGEN_DISABLED")
        assert reads["signal.gcd.dropped"]() == 0
        assert reads["signal.gcd.event"]() == "untested"
        for _ in range(125):
            lua.globals().event("UNIT_SPELLCAST_STOP", "target", "secret-guid", "secret-id", 42)
        assert reads["signal.cast.dropped"]() == 5
        rows = list(lua.globals().JustACGlobal.probeLog.values())
        assert sum("cast events capped" in row for row in rows) == 1
        lua.execute(
            """
            castActive=false
            function UnitChannelInfo()
                return secret,nil,nil,nil,nil,false,secret,secret,false,0,43
            end
            """
        )
        lua.globals().event("PLAYER_TARGET_CHANGED")
        channel = reads["signal.target.cast"]()
        assert "channel barID=plain:43" in channel
        assert "notInterruptible{raw=secret:<secret> bridge=plain:true}" in channel
        lua.globals().event("PLAYER_REGEN_ENABLED")
        lua.globals().event("UNIT_SPELLCAST_CHANNEL_STOP", "target", lua.globals().secret,
                            lua.globals().secret, lua.globals().secret, 43)
        row = list(lua.globals().JustACGlobal.probeLog.values())[-1]
        assert "arg4=secret:<secret> arg5=plain:43" in row
        assert all("secret-guid" not in row and "secret-id" not in row
                   for row in lua.globals().JustACGlobal.probeLog.values())
        lua.execute(
            """
            originalSelector=C_CurveUtil.EvaluateColorValueFromBoolean
            C_CurveUtil.EvaluateColorValueFromBoolean=function() return nil end
            """
        )
        lua.globals().event("PLAYER_TARGET_CHANGED")
        assert "bridge=plain:unknown:nil input" in reads["signal.target.cast"]()
        lua.execute("C_CurveUtil.EvaluateColorValueFromBoolean=function() error('selector denied') end")
        lua.globals().event("PLAYER_TARGET_CHANGED")
        assert "selector denied" in reads["signal.target.cast"]()
        assert "raw=secret:<secret>" in reads["signal.target.cast"]()
        lua.execute("C_CurveUtil.EvaluateColorValueFromBoolean=originalSelector")
        lua.execute("originalZero=B.IsSecretZero; B.IsSecretZero=function() return secret end")
        lua.globals().event("PLAYER_TARGET_CHANGED")
        assert "bridge=secret:<secret>" in reads["signal.target.cast"]()
        lua.execute("B.IsSecretZero=originalZero")
        lua.globals().event("SPELL_UPDATE_COOLDOWN")
        before = len(lua.globals().JustACGlobal.probeLog)
        lua.globals().event("SPELL_UPDATE_COOLDOWN")
        assert len(lua.globals().JustACGlobal.probeLog) == before, "identical GCD event snapshots must not emit"
        lua.execute("""
            now=4
            function UnitExists() return true end
            C_PetInfo={
                GetPetHappiness=function() return 2,100,-1 end,
                GetPetFoodTypes=function() return {'Meat','Fish'} end,
                CanPetEatItem=function(id) return id==5 end,
            }
            C_Container={
                GetContainerNumSlots=function() return 36 end,
                GetContainerItemID=function(_,slot) return slot end,
            }
        """)
        assert "level=plain:2" in reads["signal.pet.happiness"]()
        assert "plain:Meat" in reads["signal.pet.foodTypes"]()
        foods = reads["signal.pet.foodCandidates"]()
        assert "5=plain:true" in foods and "truncated:12" in foods
        assert "13=" not in foods, "inventory classification must stay bounded"
        # All saved values must be classified text or plain counters, never raw payloads.
        lua.execute("""
            for key,fn in pairs(reads) do
                local value=fn()
                assert(type(value)=='string' or type(value)=='number',key)
            end
        """)


def test_spell_bound_aura_capture():
    lua = runtime()
    start = SOURCE.index("    local auraRouteCandidates, auraRouteLast =")
    end = SOURCE.index("\n    local curseLast, curseEpoch", start)
    lua.execute("""
        curseTargetEpoch=1
        function UnitExists() return true end
        secret={}
        function issecretvalue(v) return v==secret end
        DT={DebugState=function() return {entries={{spellID=1}}} end}
        RI={GetRotationGated=function(ctx)
            if ctx=='cleave' then
                return {{id=10,gates={{t='any',g={{t='dot',id=2},{t='dot',id=2}}}}}}
            end
            return {}
        end}
        B={
            GetAuraDurationObject=function(_,id) assert(id==102); return {} end,
            IsDurationBelowPercent=function(_,pct) assert(pct==30); return false end,
        }
        C_UnitAuras={
            GetUnitAuraInstanceIDs=function() return {901} end,
            GetUnitAuraBySpellID=function(_,sid)
                if sid==2 then return {auraInstanceID=102} end
            end,
        }
        function LibStub(name)
            if name=='JustAC-DotTracker' then return DT end
            if name=='JustAC-RotationImport' then return RI end
            if name=='JustAC-BlizzardAPI' then return B end
        end
    """)
    lua.execute(SOURCE[start:end] + "\nauraSample=auraRouteSample")
    lua.globals().auraSample()
    rows = list(lua.globals().JustACGlobal.probeLog.values())
    assert len(rows) == 2, "tracked and nested cleave references must be deduplicated"
    assert "ref=1" in rows[0] and "duration=no-id" in rows[0]
    assert "ref=2" in rows[1] and "below30=plain:false" in rows[1]
    lua.globals().auraSample()
    assert len(lua.globals().JustACGlobal.probeLog) == 2
    lua.execute("curseTargetEpoch=2; C_UnitAuras.GetUnitAuraBySpellID=function() return secret end")
    lua.globals().auraSample()
    assert all("bySpell=secret duration=no-id" in row
               for row in list(lua.globals().JustACGlobal.probeLog.values())[-2:])
    lua.execute("""
        curseTargetEpoch=3
        C_UnitAuras.GetUnitAuraBySpellID=function(_,sid)
            if sid==1 then error('lookup denied') end
            return {auraInstanceID=102}
        end
        B.GetAuraDurationObject=function() error('duration denied') end
    """)
    lua.globals().auraSample()
    rows = list(lua.globals().JustACGlobal.probeLog.values())[-2:]
    assert "ref=1" in rows[0] and "bySpell=denied" in rows[0]
    assert "ref=2" in rows[1] and "duration denied" in rows[1]


def test_priority_gate_capture():
    for forever in (False, True):
        lua = runtime()
        lua.globals().forever = forever
        lua.execute("""
            now=0
            function GetTime() return now end
            secret={}
            function issecretvalue(v) return v==secret end
            B={
                GetClassResourcePoints=function() return 3,5,'combo_points' end,
                GetAuraStackAtLeast=function() return nil end,
                GetSwingRemaining=function() return 0.4 end,
                IsBuffWindowActive=function() return false end,
            }
            SQ={_GateVerdict=function(g,ctx)
                assert(ctx.resCount==3 and ctx.resMax==5 and ctx.resName=='combo_points')
                if g.t=='known' then return true end
                if g.t=='swing' then return false end
                if g.t=='unconfirmed' then return false end
                if ctx.strict then return false end
            end}
            list={
                {id=10,delegated=true,gates={{t='any',g={
                    {t='dot',id=20},{t='stack',id=30,n=5,op='>=',tgt=true}
                }}}},
                {id=11,gates={{t='swing',ranged=true,n=0.5,op='<'}}},
                {id=12,gates={{t='known',id=99}}},
            }
            RI={
                GetForeverTree=function() if forever then return 'marksmanship' end end,
                GetRotationGated=function(ctx) if ctx=='cleave' then return list end return {} end,
            }
            DT={
                IsDotActiveOnCurrentTarget=function(id) assert(id==20); return true end,
                DebugState=function() return {entries={{spellID=20,confirmed=true,enginePandemic=false}}} end,
            }
            C_UnitAuras={GetUnitAuraBySpellID=function() return {auraInstanceID=secret} end}
            function LibStub(name)
                if name=='JustAC-BlizzardAPI' then return B end
                if name=='JustAC-SpellQueue' then return SQ end
                if name=='JustAC-RotationImport' then return RI end
                if name=='JustAC-DotTracker' then return DT end
            end
            sample=DebugCommands.PriorityGateSample()
        """)
        sample = lua.globals().sample
        assert sample(1) == "records=8 truncated=false"
        rows = list(lua.globals().JustACGlobal.probeLog.values())
        assert any("cleave/1/10/1.1" in row and "tracked=plain:true" in row
                   and "rank=unknown:nil" in row and "confirmed=true" in row for row in rows)
        assert any("cleave/1/10/1.2" in row and "binding=plain:secret instance" in row
                   and "threshold=unknown:nil" in row for row in rows)
        assert any("source=swing-tracker remaining=plain:0.4" in row for row in rows)
        before = len(rows)
        assert sample(1) == "records=8 truncated=false"
        lua.execute("now=1")
        sample(1)
        assert len(lua.globals().JustACGlobal.probeLog) == before
        lua.execute("now=2")
        sample(2)
        assert len(lua.globals().JustACGlobal.probeLog) == before + 1, "epoch-only changes emit one context row"
        assert any("PRIORITY DEF" in row and "type=dot" in row for row in rows)
        lua.execute("""
            now=3
            B.GetAuraStackAtLeast=function() error('stack denied') end
            C_UnitAuras.GetUnitAuraBySpellID=function() error('binding denied') end
        """)
        sample(2)
        rows = list(lua.globals().JustACGlobal.probeLog.values())
        assert any("stack denied" in row and "binding denied" in row for row in rows)
        lua.execute("now=3.5; B.GetSwingRemaining=function() return secret end")
        # A forced target change does not bypass the one-second work limit.
        sample(3)
        assert not any("epoch=3" in row for row in lua.globals().JustACGlobal.probeLog.values())
        lua.execute("now=4")
        sample(3)
        assert any("remaining=secret:<secret>" in row
                   for row in lua.globals().JustACGlobal.probeLog.values())
        lua.execute("now=5; list={}")
        sample(2)
        assert any("removed epoch=2" in row for row in lua.globals().JustACGlobal.probeLog.values())
        lua.execute("""
            now=6; list={}
            for i=1,300 do list[i]={id=i,gates={{t='known',id=1}}} end
        """)
        assert sample(2) == "records=240 truncated=true"


def test_consolidated_gate_reports():
    for forever in (False, True):
        lua = runtime()
        lua.globals().forever = forever
        lua.execute("""
            calls={}
            B={
                GetClassResourcePoints=function() return 3,5,'combo_points' end,
                GetAuraStackAtLeast=function() return false end,
                IsThresholdGateAvailable=function() return true end,
                IsForever=function() return forever end,
            }
            SQ={
                _GateVerdict=function(g)
                    if g.t=='stack' then return false end
                    if g.t=='known' then return true end
                end,
                _StackHolds=function() return false end,
                _SimcGateBlocks=function(gates)
                    return #gates>0 and gates[1].t=='stack'
                end,
            }
            RI={
                HasRotation=function() return true end,
                GetRotationGated=function(ctx)
                    calls[#calls+1]=ctx
                    return {
                        {id=1,gates={{t='stack',id=2,n=5,op='>='}}},
                        {id=3,gates={{t='dot',id=4}}},
                        {id=5,gates={{t='any',g={{t='known',id=6},{t='buff',id=7}}}}},
                        {id=8,delegated=true,gates={}},
                    }
                end,
            }
            C_Spell={GetSpellInfo=function(id) return {name='spell'..id} end}
            function UnitExists() return false end
            function LibStub(name)
                if name=='JustAC-BlizzardAPI' then return B end
                if name=='JustAC-SpellQueue' then return SQ end
                if name=='JustAC-RotationImport' then return RI end
            end
        """)
        lua.execute(method("SimcGateProbe"))
        lua.execute(method("GateDiagnostics"))
        lua.globals().DebugCommands.GateDiagnostics(lua.globals().addon)
        assert list(lua.globals().calls.values()) == ["st", "cleave", "aoe"]
        report = lines(lua)
        assert "holds=false" in report and "[>=5 is false]" in report
        assert "dot[4] verdict=nil:nil" in report, "unknown top-level gates must not vanish"
        assert "known[6]" in report and "buff[7]" in report
        assert "no gates" in report and "(delegated)" in report
        assert "4 imported entries, 1 blocked" in report
        lua.execute("output={}; SQ._GateVerdict=nil")
        lua.globals().DebugCommands.SimcGateProbe(lua.globals().addon, "st")
        assert "modules unavailable" in lines(lua)
        lua.execute("B=nil; output={}")
        lua.globals().DebugCommands.GateDiagnostics(lua.globals().addon)
        assert "No SimC gate data" in lines(lua)


def test_rotation_probe_source():
    lua = runtime()
    lua.execute("""
        gamePick=true
        B={
            HasGamePick=function() return gamePick end,
            GetRotationSpells=function(gameOnly)
                assert(gameOnly==true, 'must exclude imported pool additions')
                return {1,2,3}
            end,
            GetNextCastSpell=function() return 1 end,
        }
        C_Spell={GetSpellName=function(id) return 'spell'..id end}
        function LibStub() return B end
    """)
    lua.execute("local lastRotationSnap\n" + method("RotationOrderProbe"))
    lua.globals().DebugCommands.RotationOrderProbe(lua.globals().addon)
    assert "ascending by spell ID" in lines(lua)
    lua.execute("gamePick=false; output={}; B.GetRotationSpells=function() error('no Blizzard feed') end")
    lua.globals().DebugCommands.RotationOrderProbe(lua.globals().addon)
    assert "no Blizzard priority feed" in lines(lua)


def test_stack_shape_scope():
    lua = runtime()
    lua.execute("""
        C_UnitAuras={GetAuraDataByIndex=function(_,i)
            if i==1 then return {spellId=1,applications=5,name='stack'} end
            if i==2 or i==3 then return {spellId=2,applications=1,name='multi'} end
        end}
    """)
    lua.execute(method("StacksProbe"))
    lua.globals().DebugCommands.StacksProbe(lua.globals().addon)
    report = lines(lua)
    assert "STACKING counter=5 (combat threshold access untested)" in report
    assert "MULTI-INSTANCE x2 (OOC shape only)" in report
    assert "NOT countable" not in report and "-> countable in combat" not in report


def test_dot_provenance_capture():
    lua = runtime()
    start = SOURCE.index("    local dotState, lastTarget =")
    end = SOURCE.index("\n    -- Can we hold an aura INSTANCE", start)
    lua.execute("""
        log={}; epoch=1; guid='Creature-A'; now=1; active=false
        function GetTime() return now end
        function UnitGUID() return guid end
        function UnitAffectingCombat() return true end
        function targetEpoch() return epoch end
        function IsSecret() return false end
        function ProbeLogEmit(text) log[#log+1]=text end
        RI={GetRotationGated=function()
            local entries={}
            for i=1,14 do entries[i]={gates={{t='any',g={{t='dot',id=i}}}}} end
            return entries
        end}
        DT={DebugState=function(ids)
            assert(#ids==12, 'candidate bound')
            local entries={}
            for _,id in ipairs(ids) do
                entries[#entries+1]={spellID=id,active=active,confirmed=false,
                    source='cooldown-manager',cooldownManager=active,cooldownManagerReason='aura-inactive'}
            end
            return {entries=entries}
        end}
        function LibStub(name)
            if name=='JustAC-DotTracker' then return DT end
            if name=='JustAC-RotationImport' then return RI end
        end
    """)
    lua.execute(SOURCE[start:end] + "\nSampleDots=dotSample")
    lua.globals().SampleDots()
    text = "\n".join(lua.globals().log.values())
    assert "source=cooldown-manager cdm=false cdmReason=aura-inactive epoch=1 truncated=true" in text
    before = len(lua.globals().log)
    lua.globals().SampleDots()
    assert len(lua.globals().log) == before, "identical state is change-only"
    lua.execute("guid='Creature-B';epoch=2")
    lua.globals().SampleDots()
    assert len(lua.globals().log) == before + 13, "target change re-emits every candidate"
    before = len(lua.globals().log)
    lua.execute("epoch=3")
    lua.globals().SampleDots()
    assert len(lua.globals().log) == before + 13, "epoch change works without a readable GUID change"
    lua.execute("active=true")
    lua.globals().SampleDots()
    assert "cdm=true" in lua.globals().log[len(lua.globals().log)]


def test_rogue_archetype_candidate():
    for runtime_type in (LuaRuntime, Lua51Runtime):
        lua = runtime(runtime_type)
        lua.execute("""
            secret={}
            function IsSecret(v) return v==secret end
            forever=true; spec='ROGUE_F'; learned={}; ranks={}; reads=0
            B={IsForever=function() return forever end}
            SDB={GetSpecKey=function() return spec end}
            RI={
                GetForeverTree=function() return 'combat' end,
                HighestKnownRank=function(id) return ranks[id] end,
                SpentByTree=function()
                    return {{groupID=1},{groupID=2},{groupID=3}}, {[1]=0,[2]=10,[3]=0}
                end,
            }
            function IsPlayerSpell(id)
                reads=reads+1
                if learned[id]==nil then return false end
                return learned[id]
            end
            function LibStub(name)
                if name=='JustAC-BlizzardAPI' then return B end
                if name=='JustAC-SpellDB' then return SDB end
                if name=='JustAC-RotationImport' then return RI end
            end
        """)
        lua.execute(method("RogueArchetypeSample"))
        sample = lua.globals().DebugCommands.RogueArchetypeSample
        for setup, status, candidates in (
            ("learned={}", "insufficient-signature", ""),
            ("learned={[399956]=true}", "candidate-only", "mutilate"),
            ("learned={[16511]=true}", "candidate-only", "hemorrhage"),
            ("learned={[13877]=true,[13750]=true}", "candidate-only", "combat-family"),
            ("learned={[399956]=true,[16511]=true}", "ambiguous-overlap", "mutilate,hemorrhage"),
            ("learned={[16511]=true,[13877]=true}", "ambiguous-overlap", "hemorrhage,combat-family"),
            ("learned={[399956]=secret}", "unknown-signature", ""),
            ("ranks={[399956]=1241584};learned={[1241584]=true}", "candidate-only", "mutilate"),
            ("ranks={[399956]=secret};learned={}", "unknown-signature", ""),
            ("ranks={};RI.HighestKnownRank=function() error('denied') end",
             "unknown-signature", ""),
        ):
            lua.execute(setup)
            report = sample()
            assert f"status={status}" in report, (setup, report)
            assert f"candidates={candidates} status=" in report, (setup, report)
            assert "selection=unchanged" in report and "liveVerified=false" in report
        lua.execute("forever=false;reads=0")
        assert sample() == "not-applicable:client" and lua.globals().reads == 0
        lua.execute("forever=true;spec='WARLOCK_F'")
        assert sample() == "not-applicable:class" and lua.globals().reads == 0


def main():
    tests = (
        test_rotation_target_enemy_context, test_eligibility_evidence_capture,
        test_registry, test_loaded_modules, test_log_capacity, test_loaded_recovery_mana, test_shared_health_fallback, test_low_health_heal_glow, test_critical_preparation_glow, test_shared_session, test_threshold_verdicts, test_aura_denial, test_census_count, test_buff_unknown_and_preferences,
        test_ticker_lifecycle, test_battery_failures, test_delayed_snapshots,
        test_topoff_log, test_category_knowledge, test_error_capture_lifecycle,
        test_audit_lifecycle, test_curse_signals, test_chat_output, test_combat_signal_reads,
        test_priority_gate_capture,
        test_spell_bound_aura_capture, test_dot_provenance_capture, test_rogue_archetype_candidate,
        test_consolidated_gate_reports, test_rotation_probe_source, test_stack_shape_scope,
    )
    research_tests = {
        test_eligibility_evidence_capture,
        test_shared_session, test_census_count, test_battery_failures,
        test_delayed_snapshots, test_audit_lifecycle, test_curse_signals,
        test_combat_signal_reads, test_priority_gate_capture,
        test_spell_bound_aura_capture, test_dot_provenance_capture, test_rogue_archetype_candidate,
        test_rotation_probe_source, test_stack_shape_scope,
    }
    for test in tests:
        if not RESEARCH_FILES and test in research_tests:
            continue
        test()
    if not RESEARCH_FILES:
        print("research companion absent: research-only regressions skipped")
    print("debug probes: TOC-ordered Lua 5.1 loading, both clients, registry, denial/unknown, preferences, lifecycle, failures, delayed snapshots and saved transitions passed")


if __name__ == "__main__":
    main()
