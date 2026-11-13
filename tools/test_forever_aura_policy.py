# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real generated data, tracker and shared queue stage with controlled aura evidence.
from pathlib import Path

from lupa import LuaRuntime

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
    })
    queue.globals().SpellDB.IsFrontalDot = lambda sid: db.IsFrontalDot(sid)
    queue.globals().SpellDB.GetForeverTotemSlot = lambda sid: db.GetForeverTotemSlot(sid)

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

    # An uncorrelated target miss can only undo an estimate, never prove presence.
    for miss in ("MISS", "RESIST", "DODGE", "PARRY"):
        obs.execute("now=20; tracked={}")
        tracker.Reset()
        tracker.OnCastSucceeded(14914)
        obs.globals().now = 20.1
        tracker.OnTargetCombat(miss)
        assert tracker.GetTargetAuraState(14914, True) is None, miss
        assert build() == [sid]

    # CDM overrides the estimate; target changes do not transfer the timer.
    tracker.Reset()
    tracker.OnCastSucceeded(14914)
    obs.execute("tracked[14914]=false")
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
    queue.execute("entries=classes.WARRIOR_F.protection.aoe")
    assert build("pinnedAlwaysShow[6343]=true") == [6343]
    assert build("b.contextOrder='off'") == [6343]
    assert db.IsTargetDot(6343) is False
    assert db.IsTrackedTargetAura(133) is False, "ordinary Fireball remains a repeatable nuke"

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
