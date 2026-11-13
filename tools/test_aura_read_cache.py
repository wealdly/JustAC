# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real queue categorization, buff evidence, target tracking and CDM reads in one runtime.
from pathlib import Path

from test_forever_openers import create_runtime
from test_gate_groups import extract

ROOT = Path(__file__).resolve().parent.parent


def runtime(forever=True):
    lua = create_runtime(real_gates=True)
    lua.globals().forever = forever
    lua.execute("""
        Reset()
        local libs = {
            ["JustAC-BlizzardAPI"]=BlizzardAPI, ["JustAC-SpellDB"]=SpellDB,
            ["JustAC-RotationImport"]=RotationImport,
        }
        LibStub=setmetatable({
            NewLibrary=function(_, name) libs[name]=libs[name] or {};return libs[name] end,
        }, {__call=function(_, name) return libs[name] end})
        now=100;targetGUID="Creature-A"
        function GetTime() return now end
        function UnitGUID() return targetGUID end
        function UnitAffectingCombat() return true end
        function CreateFrame()
            return {RegisterEvent=function() end,RegisterUnitEvent=function() end,
                SetScript=function() end,HookScript=function() end}
        end
        hooksecurefunc=function() end
        BlizzardAPI.Unsecret=function(v) return v end
        BlizzardAPI.ResolveBaseSpellID=function() return nil end
        BlizzardAPI.AreAurasSecret=function() return true end
        SpellDB.IsTargetDot=function(id) return id==772 end
        SpellDB.IsTrackedTargetAura=function(id) return id==14914 or id==91001 end
        SpellDB.GetTargetAuraDuration=function() return 10 end
        SpellDB.GetForeverTotemSlot=function() end
        SpellDB.IsFrontalDot=function(id) return id==14914 end
        Enum={CooldownViewerCategory={Essential=0,Utility=1,TrackedBuff=2,TrackedBar=3}}
        viewerShown=true;itemReads=0;auraReads=0;items={};auraActive=true
        -- Every requested spell has one distinct aura entry.
        local spells={14914,772,91001,91002,91003,20154,20164,20165,20166,20375,21082,1311649}
        local ids, info={},{}
        for i,id in ipairs(spells) do
            ids[i]=1000+i;info[1000+i]={spellID=id}
        end
        C_CooldownViewer={
            GetCooldownViewerCategorySet=function(cat) if cat==2 then return ids end return {} end,
            GetCooldownViewerCooldownInfo=function(cid) return info[cid] end,
        }
        BuffIconCooldownViewer={
            IsShown=function() return viewerShown end,
            itemFramePool={EnumerateActive=function()
                local i=0
                return function() i=i+1;return items[i] end
            end},
        }
        function SetViewer(spell, active, count)
            items={}
            for i=1,count do
                local cid=300000+i
                if i==count then
                    for id,entry in pairs(info) do if entry.spellID==spell then cid=id end end
                end
                items[i]={GetCooldownID=function() itemReads=itemReads+1;return cid end,isActive=active}
            end
        end
        C_UnitAuras={GetPlayerAuraBySpellID=function()
            auraReads=auraReads+1;return nil
        end}
        function NewReads() return {dots={},buffs={},tracked={}} end
        previousB={}
        for k,v in pairs(BlizzardAPI) do previousB[k]=v end
    """)
    # Reset() installs the Forever default; choose the client before loading tracker constants.
    lua.globals().forever = forever
    for file in ("MaintenanceTracker.lua", "BlizzardAPI\\CooldownTracking.lua", "DotTracker.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8"))
    lua.execute("""
        for k,v in pairs(previousB) do
            if k~="IsBuffWindowActive" then BlizzardAPI[k]=v end
        end
        DotTracker=LibStub("JustAC-DotTracker")
        MaintenanceTracker=LibStub("JustAC-MaintenanceTracker")
        dotCtx={strict=false}
    """)
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    for name in ("SimcBuffWindowActive", "SimcNegativeBuffBlocks", "DotGateBlocks"):
        lua.execute(extract(name, source))
    return lua


def main():
    lua = runtime()
    lua.execute("""
        specKey="PRIEST_F";b.inCombat=true;b.maxIcons=1
        entries=classes.PRIEST_F.holy.st;pool={14914,585}
        ranges[14914],ranges[585]=true,true
        SetViewer(14914,true,40)
    """)
    build = lua.eval("""function()
        b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0
        return BuildStage()
    end""")
    assert list(build().values()) == [585]
    assert lua.globals().itemReads == 40, "three Holy Fire policies must share one CDM scan"
    lua.execute("SetViewer(14914,false,40);itemReads=0")
    assert list(build().values()) == [14914]
    assert lua.globals().itemReads == 40, "false is cached; next pass sees the new verdict"
    lua.execute("SetViewer(14914,secret,40);itemReads=0")
    assert list(build().values()) == [14914]
    assert lua.globals().itemReads == 40, "unknown is cached, never converted to absence"
    lua.execute("viewerShown=false")
    assert list(build().values()) == [14914], "viewer visibility is fresh on the next pass"

    lua.execute("""
        viewerShown=true;SetViewer(91001,nil,40);cache=NewReads()
        DotTracker.OnCastSucceeded(91001)
    """)
    dot = lua.globals().DotTracker
    cache = lua.globals().cache
    assert dot.GetTargetAuraState(91001, True, cache) is True
    assert dot.GetTargetAuraState(91001, False, cache) is None, "estimate never becomes evidence"
    lua.execute("now=100.1")
    dot.OnTargetCombat("MISS")
    assert dot.GetTargetAuraState(91001, True, cache) is None, "miss invalidates the live estimate"
    dot.OnCastSucceeded(91001)
    lua.execute("targetGUID='Creature-B'")
    dot.OnTargetChanged()
    assert dot.GetTargetAuraState(91001, True, lua.globals().NewReads()) is None

    mt = lua.globals().MaintenanceTracker
    lua.execute("SetViewer(91002,false,40);cache=NewReads();itemReads=0")
    cache = lua.globals().cache
    assert mt.IsTrackedAuraActive(91002, None, cache) is False
    assert mt.IsTrackedAuraActive(91002, None, cache) is False
    assert lua.globals().itemReads == 40
    lua.execute("SetViewer(91002,true,40)")
    diagnostic = lua.table()
    assert mt.IsTrackedAuraActive(91002, diagnostic, cache) is True, "diagnostics bypass snapshots"
    assert diagnostic.reason == "aura-active"
    assert mt.IsTrackedAuraActive(91002) is True, "uncached callers always read live"

    lua.execute("SetViewer(772,true,40);cache=NewReads();itemReads=0")
    cache = lua.globals().cache
    assert dot.IsDotActiveOnCurrentTarget(772, cache) is True
    assert dot.GetTargetAuraState(772, False, cache) is True
    assert lua.globals().BlizzardAPI.IsBuffWindowActive(772, None, cache) is True
    assert lua.globals().itemReads == 40, "all consumers share the same raw CDM read"

    lua.execute("""
        SetViewer(91003,false,40);cache=NewReads();itemReads=0
        BlizzardAPI.NoteOwnCast(91003)
    """)
    cache = lua.globals().cache
    bapi = lua.globals().BlizzardAPI
    assert bapi.IsBuffWindowActive(91003, 30, cache) is False
    assert bapi.IsBuffWindowActive(91003, 60, cache) is False
    assert lua.globals().itemReads == 40, "confirmed absence overrides both cast windows"
    lua.execute("SetViewer(91003,true,40)")
    assert bapi.IsBuffWindowActive(91003, 30, lua.globals().NewReads()) is True

    for forever in (True, False):
        lua = runtime(forever)
        bapi = lua.globals().BlizzardAPI
        lua.execute("""
            viewerShown=false;cache=NewReads()
            BlizzardAPI.NoteOwnCast(91003)
            now=106
        """)
        cache = lua.globals().cache
        assert bapi.IsBuffWindowActive(91003, 5, cache) is False
        assert bapi.IsBuffWindowActive(91003, 10, cache) is True, "duration is evaluated per gate"
        assert bapi.IsBuffWindowActive(91003, None, cache) is False
        assert lua.globals().auraReads == 1, "one raw aura lookup across different fallback windows"
        lua.execute("now=111;cache=NewReads()")
        assert bapi.IsBuffWindowActive(91003, 10, lua.globals().cache) is False
        assert lua.globals().auraReads == 2, "expiry is fresh with a new pass"

    lua = runtime()
    lua.execute("""
        specKey="PALADIN_F";b.inCombat=true
        entries=classes.PALADIN_F.retribution.st;pool={20154};ranges[20154]=true
        viewerShown=false
    """)
    lua.globals().BuildStage()
    assert lua.globals().auraReads == 35, "seven seals' 35 ranks are read once, not twice"
    print("Aura read cache: CDM item reads 120 -> 40; seal rank lookups 70 -> 35; "
          "tri-state, estimates, duration policies, fresh passes and diagnostics passed")


if __name__ == "__main__":
    main()
