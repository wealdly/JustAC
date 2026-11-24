# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real generated data, tracker and shared queue stage with controlled aura evidence.
from pathlib import Path

from wow_stubs import LuaRuntime

from test_forever_defaults import PRELUDE
from test_forever_openers import create_runtime

ROOT = Path(__file__).resolve().parent.parent


def observer():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE + "\nWOW_PROJECT_CAMELOT=18; WOW_PROJECT_ID=18")
    for file in ("SpellDB.lua", "RotationImport.lua", "Data\\SpellCategories.lua",
                 "Data\\Forever\\Rotations.lua", "Data\\Forever\\Defaults.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8"))
    lua.execute("""
        now=0; targetGUID='Creature-A'
        GetTime=function() return now end
        UnitExists=function() return true end
        UnitGUID=function() return targetGUID end
        C_UnitAuras={}
        function CreateFrame()
            return {RegisterEvent=function() end,RegisterUnitEvent=function() end,SetScript=function() end}
        end
        local B=LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.GetDisplaySpellID=function(id) return id end
        B.Unsecret=function(value) return value end
        tracked={}
        LibStub:NewLibrary("JustAC-MaintenanceTracker").IsTrackedAuraActive=function(id)
            return tracked[LibStub("JustAC-RotationImport").RankBase(id)]
        end
    """)
    lua.execute((ROOT / "DotTracker.lua").read_text(encoding="utf-8"))
    return lua, lua.eval('LibStub("JustAC-SpellDB")'), lua.eval('LibStub("JustAC-DotTracker")')


def main():
    obs, db, tracker = observer()
    queue = create_runtime(real_gates=True)
    queue.globals().DotTracker = queue.table_from({
        "GetTargetAuraState": lambda sid, estimate, cache=None: tracker.GetTargetAuraState(sid, estimate),
        "IsDotActiveOnCurrentTarget": lambda sid, cache=None: tracker.IsDotActiveOnCurrentTarget(sid),
        "GetOwnStacks": lambda sid: tracker.GetOwnStacks(sid),
    })
    queue.globals().SpellDB.IsFrontalDot = lambda sid: db.IsFrontalDot(sid)
    queue.globals().SpellDB.GetForeverTotemSlot = lambda sid: db.GetForeverTotemSlot(sid)
    queue.globals().SpellDB.IsDelayedPayoff = lambda sid: db.IsDelayedPayoff(sid)
    queue.globals().SpellDB.GetStackingMax = lambda sid: db.GetStackingMax(sid)
    queue.globals().SpellDB.GetThreatRole = lambda sid: db.GetThreatRole(sid)
    queue.globals().SpellDB.IsTankTree = lambda spec, tree: db.IsTankTree(spec, tree)
    queue.execute("RotationImport = RotationImport or {}; RotationImport.GetForeverTree = function() return foreverTree end")
    # The shared tank answer (SpellDB.IsPlayerTank) with no role or stance: the tank tree.
    queue.execute("SpellDB.IsPlayerTank = function() return SpellDB.IsTankTree('WARRIOR_F', foreverTree) end")

    def validate(gates, spell):
        for gate in gates.values():
            if gate.t == "debuff" and gate.refresh:
                assert gate.id == spell, "only an applicator may use its own cast estimate"
                assert db.IsTrackedTargetAura(gate.id) or db.GetForeverTotemSlot(gate.id), \
                    ("refresh condition without an observation route", spell)
            if gate.g:
                validate(gate.g, spell)

    for trees in queue.globals().classes.values():
        for tree, contexts in trees.items():
            if tree == "default":
                continue
            for entries in contexts.values():
                for entry in entries.values():
                    validate(entry.gates, entry.id)

    def build(setup=""):
        queue.execute("b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0;" + setup)
        return list(queue.globals().BuildStage().values())

    # Every Holy Fire rank: source maintenance works without a spell cooldown or CDM.
    chains = obs.eval('LibStub("JustAC-RotationImport").RankChain(14914)')
    for sid in chains.values():
        for tree in ("holy", "discipline"):
            obs.execute("now=0; tracked={}")
            tracker.Reset()
            queue.execute(f"""
                Reset();specKey='PRIEST_F';b.inCombat=true;b.maxIcons=1
                entries=classes.PRIEST_F.{tree}.st;pool={{{sid},585}}
                ranges[14914],ranges[585]=true,true
            """)
            assert build() == [sid]
            tracker.OnCastSucceeded(sid)
            obs.globals().now = 4
            assert tracker.GetTargetAuraState(sid, True) is True
            assert tracker.GetTargetAuraState(sid, False) is None
            assert build() == [585], (tree, sid)
            assert build("b.maxIcons=4") == [585, sid]
            obs.globals().now = 10.1
            assert build("b.maxIcons=1") == [sid]

    # An uncorrelated target miss can only undo an estimate, never prove presence. Holy Fire
    # is a spell with no missile: its result comes in the same instant.
    for miss in ("MISS", "RESIST"):
        obs.execute("now=20; tracked={}")
        tracker.Reset()
        tracker.OnCastSucceeded(14914)
        obs.globals().now = 20.05
        tracker.OnTargetCombat(miss)
        assert tracker.GetTargetAuraState(14914, True) is None, miss
        assert build() == [sid]
    # A spell is never dodged or parried, so those results belong to another attack, and a
    # miss well after the cast is not this cast's either: the estimate stands.
    for miss, at in (("DODGE", 20.05), ("PARRY", 20.05), ("MISS", 20.3)):
        obs.execute("now=20; tracked={}")
        tracker.Reset()
        tracker.OnCastSucceeded(14914)
        obs.globals().now = at
        tracker.OnTargetCombat(miss)
        assert tracker.GetTargetAuraState(14914, True) is True, (miss, at)

    # CDM overrides the estimate once the cast-to-icon bridge window has passed; target
    # changes do not transfer the timer.
    tracker.Reset()
    tracker.OnCastSucceeded(14914)
    obs.execute("tracked[14914]=false")
    assert tracker.GetTargetAuraState(14914, True) is True, "icon trails the cast"
    assert tracker.GetTargetAuraState(14914, False) is None, "pending is not presence evidence"
    obs.globals().now = obs.globals().now + 2.1
    assert tracker.GetTargetAuraState(14914, True) is False
    obs.execute("tracked[14914]=true")
    assert tracker.GetTargetAuraState(14914, False) is True
    obs.execute("tracked={};targetGUID='Creature-B'")
    tracker.OnTargetChanged()
    assert tracker.GetTargetAuraState(14914, True) is None

    # Entry policy, not observation, decides whether Thunder Clap should be repeated.
    for tree, expected in (("protection", 78), ("arms", 6343)):
        obs.execute("now=30;tracked={};targetGUID='Creature-A'")
        tracker.Reset()
        tracker.OnCastSucceeded(6343)
        queue.execute(f"""
            Reset();specKey='WARRIOR_F';b.inCombat=true;b.maxIcons=1
            entries=classes.WARRIOR_F.{tree}.aoe;pool={{6343,78}}
            ranges[6343],ranges[78]=true,true
        """)
        assert build() == [expected], tree
    # Protection's Thunder Clap is a pack attack (two or more engaged enemies).
    queue.execute("entries=classes.WARRIOR_F.protection.aoe;"
                  "BlizzardAPI.GetEngagedEnemyCount=function() return 3 end")
    assert build("pinnedAlwaysShow[6343]=true") == [6343]
    queue.execute("BlizzardAPI.GetEngagedEnemyCount=nil")
    assert build("b.contextOrder='off'") == [6343]
    assert db.IsTargetDot(6343) is False
    assert db.IsTrackedTargetAura(133) is False, "ordinary Fireball remains a repeatable nuke"

    # Protection alone on an ordinary target: Sunder's threat buys nothing, so it waits for a
    # worthwhile fight like any slow payoff (the hold's cases are in test_gate_groups.py).
    obs.execute("now=60;tracked={};targetGUID='Creature-Sunder'")
    tracker.Reset()
    queue.execute("""
        Reset();specKey='WARRIOR_F';foreverTree='protection';b.inCombat=true;b.now=60;b.maxIcons=1
        entries=classes.WARRIOR_F.protection.st;pool={7386,78}
        ranges[7386],ranges[78]=true,true
    """)
    assert build() == [78], "solo Protection does not open an ordinary fight with Sunder"

    # Grouped, the tank applies Sunder at once and its own landed stack count paces it,
    # stopping at the generated maximum.
    obs.execute("now=70;tracked={};targetGUID='Creature-Group'")
    tracker.Reset()
    queue.execute("""
        Reset();specKey='WARRIOR_F';b.inCombat=true;b.now=70;b.maxIcons=1
        entries=classes.WARRIOR_F.protection.st;pool={7386,78}
        ranges[7386],ranges[78]=true,true
        BlizzardAPI.IsGrouped=function() return true end
    """)
    for stacks in range(5):
        assert build() == [7386], ("group Sunder", stacks)
        tracker.OnCastSucceeded(7386)
        obs.globals().now += 1
    assert build() == [78], "the generated stack maximum stops further applications"
    obs.execute("now=80;tracked={};targetGUID='Creature-StackContext'")
    tracker.Reset()
    tracker.OnCastSucceeded(7386)
    for setup, expected in (
        ("", False),
        ("grouped=true", True),
        ("content='dungeon'", True),
        ("classification='elite'", True),
        ("delta=1", True),
        ("delta=-1", False),
        ("grouped=nil", False),
        ("grouped=true;SpellQueue._rotationIsCustom=true", False),
        ("grouped=true;forever=false", False),
        ("grouped=true;ctx.stackApplicator=78", False),
    ):
        queue.execute("""
            grouped=false;content='world';classification='normal';delta=nil
            forever=true;SpellQueue._rotationIsCustom=false
            BlizzardAPI.IsGrouped=function() return grouped end
            BlizzardAPI.GetContentType=function() return content end
            BlizzardAPI.GetTargetLevelDelta=function() return delta end
            UnitClassification=function() return classification end
            ctx={strict=false,stackApplicator=7386}
        """ + setup)
        assert queue.eval('SpellQueue._GateVerdict({t="stack",id=7386,op="<",n=1,tgt=true},ctx)') \
            is expected, setup
    queue.execute("grouped=true;ctx={strict=false,stackApplicator=7386}")
    assert queue.eval('SpellQueue._GateVerdict({t="stack",id=7386,op="<",n=1,tgt=true,once=true},ctx)') is False, \
        "a pack list stops at one application, even in a group"
    queue.execute("BlizzardAPI.IsGrouped=nil;BlizzardAPI.GetContentType=nil;"
                  "BlizzardAPI.GetTargetLevelDelta=nil;SpellQueue._rotationIsCustom=false;forever=true")

    # Another aura's presence can be tested, but not inferred from a cast or a timer.
    queue.execute("""
        Reset()
        function Verdict(g) return SpellQueue._GateVerdict(g,{strict=false}) end
    """)
    verdict = queue.globals().Verdict
    immolate = queue.table_from({"t": "debuff", "id": 348})
    for state in (True, False, None):
        obs.execute("tracked={}")
        if state is not None:
            obs.globals().tracked[348] = state
        assert verdict(immolate) is state
        timed = queue.table_from({"t": "debuff", "id": 1079, "op": ">", "n": 3})
        assert verdict(timed) is None, "presence cannot establish Rip's remaining seconds"
    obs.execute("now=40;tracked={}")
    tracker.Reset()
    tracker.OnCastSucceeded(348)
    assert verdict(immolate) is None, "cast estimate is not confirmed prerequisite presence"

    # A confirmed maintenance veto survives proc promotion; an estimate does not.
    queue.execute("""
        Reset();specKey='PRIEST_F';b.inCombat=true;b.maxIcons=1
        entries=classes.PRIEST_F.holy.st;pool={14914,585};procs[14914]=true
    """)
    obs.execute("tracked[14914]=true")
    assert build() == [585]
    obs.execute("tracked={};now=50")
    tracker.Reset()
    tracker.OnCastSucceeded(14914)
    assert build() == [14914], "a real proc may override an unconfirmed cast estimate"

    # A fire totem is maintained by its slot, never a target-aura cast estimate.
    queue.execute("""
        Reset();occupied=true
        BlizzardAPI.IsTotemSlotOccupied=function() return occupied end
    """)
    totem = queue.table_from({"t": "debuff", "id": 3599, "neg": True, "refresh": True})
    assert verdict(totem) is False
    queue.globals().occupied = False
    assert verdict(totem) is True
    queue.globals().occupied = None
    assert verdict(totem) is None
    print("Forever aura policy: Holy Fire ranks, Thunder Clap contexts, estimates, misses, CDM, prerequisites, procs and totems passed")


if __name__ == "__main__":
    main()
