# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Probe reporting and recorder lifecycle with controlled client signals.
from pathlib import Path
import re

from lupa import LuaRuntime
from lupa.lua51 import LuaRuntime as Lua51Runtime

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "DebugCommands.lua").read_text(encoding="utf-8")


def method(name):
    start = SOURCE.index(f"function DebugCommands.{name}(")
    end = SOURCE.find("\n--------------------------------------------------------------------------------", start)
    return SOURCE[start:] if end < 0 else SOURCE[start:end]


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
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
    """)
    start = SOURCE.index("local function IsSecret(")
    end = SOURCE.index("\n--------------------------------------------------------------------------------\n-- THE topic registry", start)
    lua.execute(SOURCE[start:end].replace("local function ", "function "))
    start = SOURCE.index("local PROBE_LOG_MAX =")
    end = SOURCE.index("\n--------------------------------------------------------------------------------", start)
    lua.execute(SOURCE[start:end].replace("local function ", "function "))
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
    assert all(name in methods for _, name in rows)


def test_low_health_heal_glow():
    source = (ROOT / "UI" / "UIRenderer.lua").read_text(encoding="utf-8")
    start = source.index("local function IsUrgentPlayerHeal(")
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
        s.frame.scripts.OnEvent(s.frame, "GROUP_ROSTER_UPDATE")
        assert s.changes == changes, "event snapshots must not inflate change counts"
        log = list(lua.globals().JustACGlobal.probeLog.values())
        assert any(f"session={session_id}" in row and "sample=" in row and "elapsed=" in row for row in log)
        dc.DiagnosticStatus(lua.globals().addon)
        assert "errors=true" in lines(lua)
        assert "sampler ms:" in lines(lua)
        lua.execute("for i=1,8100 do ProbeLogEmit('fill '..i) end")
        assert s.dropped > 0 and lua.globals().JustACGlobal.probeLogDropped > 0
        assert lua.globals().JustACGlobal.diagnosticBaseline.last.mapID == "plain:1429"
        old_event = s.frame.scripts.OnEvent
        dc.StopDiagnostics(lua.globals().addon)
        assert s.ticker.cancelled and s.frame.unregistered
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
    end = SOURCE.index("\n--------------------------------------------------------------------------------", start)
    lua.execute(SOURCE[start:end].replace("local function RunProbeBattery(", "function RunProbeBattery(", 1))
    for forever, expected in ((False, 7), (True, 9)):
        lua.execute("output={}; JustACGlobal={}")
        lua.globals().forever = forever
        lua.execute("LibStub=function() return {IsForever=function() return forever end} end")
        lua.globals().RunProbeBattery(lua.globals().addon, "TEST", False)
        assert f"{expected} failures" in lines(lua)
        log = lua.globals().JustACGlobal.probeLog
        assert sum("PROBE ERROR" in msg for msg in log.values()) == expected
    lua.execute("""
        clock=0
        function debugprofilestop() clock=clock+1; return clock end
        DebugCommands._diagnosticSession={id='timing-test',pulls=1,failures=0}
    """)
    lua.globals().RunProbeBattery(lua.globals().addon, "TIMED", False)
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
        function RunProbeBattery(_, tag) captures[#captures+1]=tag end
    """)
    start = SOURCE.index('    f:SetScript("OnEvent", function(_, event, unit, _, spellID)', SOURCE.index("function DebugCommands.ProbeSession("))
    end = SOURCE.index("\n\n    -- Change-only", start)
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
    for _ in range(8100):
        lua.globals().ProbeLogEmit("bounded")
    assert len(lua.globals().JustACGlobal.probeLog) <= 8000


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
        ("local function HasAnyAura(", "\n-- The weapon imbue"),
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
    start = SOURCE.index("local ERRORLOG_MAX =")
    end = SOURCE.index("\nfunction DebugCommands.ProbeSession", start)
    lua.execute(SOURCE[start:end])
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
        function RunProbeBattery() end
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
    lua.execute("assert(loadstring(...))", SOURCE)


def main():
    for test in (
        test_registry, test_shared_health_fallback, test_low_health_heal_glow, test_shared_session, test_threshold_verdicts, test_aura_denial, test_census_count, test_buff_unknown_and_preferences,
        test_ticker_lifecycle, test_battery_failures, test_delayed_snapshots,
        test_topoff_log, test_category_knowledge, test_error_capture_lifecycle,
        test_audit_lifecycle, test_curse_signals, test_chat_output,
    ):
        test()
    print("debug probes: registry, denial/unknown, preferences, lifecycle, failures, delayed snapshots and saved transitions passed")


if __name__ == "__main__":
    main()
