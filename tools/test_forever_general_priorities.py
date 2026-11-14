# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
from gen_forever_rotations import (
    Conv, UNK, actions_of, on_enemy, tier_lists,
)
from test_forever_openers import create_runtime


def check_shifting_power():
    lua = create_runtime(real_gates=True)
    lua.execute("""
        Enum = {PowerType={Mana=0,Energy=3}}
        function UnitPowerMax(_, pt)
            if pt == 3 then return energyMax end
            return 100
        end
        BlizzardAPI.IsUnitPowerBelow = function(_, pct, pt)
            if pt ~= 3 then return false end
            energyReadType, energyReadThreshold = pt, pct
            if unknownEnergy then return nil end
            return energy * 100 / energyMax < pct
        end
        function IsSpenderSpell() return true end
        function Cat()
            Reset()
            specKey = "DRUID_F"
            entries = classes.DRUID_F.feral.st
            pool = {1322605,1082}
            ranges = {[1322605]=true,[1082]=true}
            energyMax, energy, unknownEnergy = 100, 0, false
            energyReadType, energyReadThreshold = nil, nil
        end
    """)
    for energy, should_lead in ((0, True), (49, True), (50, False),
                                (51, False), (100, False)):
        for procced in (False, True):
            lua.globals().Cat()
            lua.globals().energy = energy
            lua.globals().procs[1322605] = procced
            lua.globals().capped = energy == 100
            queue = list(lua.globals().Build().values())
            expected = 1322605 if should_lead else 1082
            assert queue[0] == expected, ("Shifting Power Energy guard", energy, procced, queue)
            assert lua.globals().energyReadType == 3
            assert lua.globals().energyReadThreshold == 50

    for procced in (False, True):
        lua.globals().Cat()
        lua.globals().unknownEnergy = True
        lua.globals().procs[1322605] = procced
        assert list(lua.globals().Build().values())[0] == 1082, \
            "Unknown Energy must not authorize Shifting Power"

    lua.globals().Cat()
    lua.execute("energyMax=120; energy=55")
    assert list(lua.globals().Build().values())[0] == 1082, \
        "The guard uses Energy units, not a percentage of maximum Energy"
    lua.globals().Cat()
    lua.execute("starved[1322605]=true")
    assert list(lua.globals().Build().values())[0] == 1082, \
        "Low Energy must not override insufficient Mana"
    lua.globals().Cat()
    lua.execute("cooldown[1322605]=true")
    assert list(lua.globals().Build().values())[0] == 1082

    for procced in (False, True):
        lua.globals().Cat()
        lua.execute("energy=100; holdPctVal[1322605]=10; holdPctType[1322605]=0")
        lua.globals().procs[1322605] = procced
        assert list(lua.globals().Build().values())[0] == 1322605, \
            "An explicit Hold Until dial replaces the imported Energy preference"
    lua.globals().Cat()
    lua.execute("energy=100; SpellQueue._rotationIsCustom=true; b.contextOrder='off'")
    assert list(lua.globals().Build().values()) == [1322605, 1082], \
        "Custom fixed ordering remains unchanged"

    lua.globals().Cat()
    lua.globals().unknownEnergy = True
    assert lua.eval("""
        SpellQueue._GateVerdict({t='power',res='energy',op='<',n=50},{})
    """) is None, "Existing power gates retain their unknown-state behavior"


def main():
    check_shifting_power()
    early = {"id": 1, "gates": [{"t": "resource", "op": ">=", "n": 5}],
             "tiers": ["st"]}
    middle = {"id": 2, "gates": [], "tiers": ["st"]}
    fallback = {"id": 1, "gates": [], "tiers": ["st"]}
    assert tier_lists([early, middle, fallback])["st"] == [middle, fallback]
    assert actions_of({"strictSequence": {"actions": [
        {"castSpell": {"spellId": {"spellId": 14751}}},
        {"castSpell": {"spellId": {"spellId": 585}}},
    ]}}) == []
    assert actions_of({"channelSpell": {"spellId": {"spellId": 1510}}}) == [(1510, None)]
    assert Conv({}).conv({"cmp": {"op": "OpLt", "lhs": {"timeToNextEnergyTick": {}},
                                 "rhs": {"const": {"val": "1s"}}}}) == UNK
    assert on_enemy(22959) and not on_enemy(400625)
    explicit_player = Conv({}).conv({"cmp": {
        "op": "OpGe", "lhs": {"auraNumStacks": {
            "auraId": {"spellId": 22959}, "sourceUnit": {"type": "Self"}}},
        "rhs": {"const": {"val": "5"}},
    }})
    assert not explicit_player.get("tgt"), "Explicit source annotations take precedence over inference"

    lua = create_runtime(real_gates=True)
    lua.execute("""
        Enum = {PowerType={Mana=0,Rage=1,Energy=3}}
        function UnitPowerMax() return 100 end
        RotationImport.HighestKnownRank = function(id) return id end
        BlizzardAPI.GetEngagedEnemyCount = function() return enemyCount end
        BlizzardAPI.IsUnitPowerBelow = function(_, pct) return manaPct < pct end
        BlizzardAPI.IsUnitHealthBelow = function() return false end
        BlizzardAPI.GetAuraStackAtLeast = function(unit, id, n)
            lastStackUnit = unit
            if unknownStacks then return nil end
            return (stackCounts[unit][id] or 0) >= n
        end
        BlizzardAPI.IsSpellOnCooldown = function(id) return cooldown[id] == true end
        BlizzardAPI.IsTotemSlotOccupied = function() return false end
        BlizzardAPI.GetSwingRemaining = function() return nil end
        function Defaults(cls, tree, context)
            Reset()
            specKey = cls
            local t = classes[cls][tree]
            entries = t[context] or (context == "cleave" and t.aoe) or t.st
            manaPct, enemyCount = 100, 4
            stackCounts, unknownStacks = {player={},target={}}, true
            talents = setmetatable({}, {__index=function() return true end})
            pool = {}
            for _, e in ipairs(entries) do
                pool[#pool+1] = e.id
                ranges[e.id] = true
            end
        end
        function Gate(id, gateIndex)
            return SpellQueue._GateVerdict(RotationImport.GetEntry(id).gates[gateIndex],
                {strict=false,resCount=points,resMax=5,resName="combo_points"})
        end
    """)
    classes = lua.globals().classes
    contexts = 0
    builds = 0
    for cls, trees in classes.items():
        for tree in trees.keys():
            if tree == "default":
                continue
            for context in ("st", "cleave", "aoe"):
                lua.globals().Defaults(cls, tree, context)
                entries = list(lua.globals().entries.values())
                ids = [e.id for e in entries]
                assert len(ids) == len(set(ids)), (cls, tree, context, ids)
                for e in entries:
                    assert not any(g.t == "tick" for g in e.gates.values())
                contexts += 1
                for state in ("ready", "cooldown", "starved", "blacklisted", "custom"):
                    lua.globals().Defaults(cls, tree, context)
                    if state in ("cooldown", "starved", "blacklisted"):
                        lua.execute(f"for _, id in ipairs(pool) do {state}[id]=true end")
                    elif state == "custom":
                        lua.execute("SpellQueue._rotationIsCustom=true")
                    queue = list(lua.globals().Build().values())
                    assert len(queue) <= 4 and len(queue) == len(set(queue)), (cls, tree, state)
                    assert set(queue).issubset(set(ids)), (cls, tree, state)
                    if state == "blacklisted":
                        assert queue == []
                    builds += 1
    assert contexts == 84 and builds == 420

    for cls, tree, sid in (
        ("DRUID_F", "balance", 16914),
        ("WARLOCK_F", "affliction", 1949),
        ("WARLOCK_F", "demonology", 5740),
        ("WARLOCK_F", "destruction", 5740),
    ):
        lua.globals().Defaults(cls, tree, "aoe")
        lua.globals().enemyCount = 3
        assert lua.globals().Gate(sid, 1) is True
        lua.globals().enemyCount = 2
        assert lua.globals().Gate(sid, 1) is False
    lua.globals().Defaults("MAGE_F", "fire", "st")
    lua.execute("unknownStacks=false; stackCounts.target[22959]=5")
    assert lua.globals().Gate(11129, 1) is True
    assert lua.globals().lastStackUnit == "target"
    lua.globals().unknownStacks = True
    assert lua.globals().Gate(11129, 1) is None

    lua.globals().Defaults("PRIEST_F", "discipline", "st")
    penance = lua.globals().RotationImport.RankBase(1316995)
    lua.execute("pool={14914,589,585}; cooldown[14914]=true")
    queue = list(lua.globals().Build().values())
    assert lua.globals().RotationImport.GetEntry(penance) is None
    assert queue.index(589) < queue.index(585)
    assert queue.index(585) < queue.index(14914)
    assert 14751 not in [e.id for e in lua.globals().entries.values()]
    for cls, tree, sid in (("DRUID_F", "feral_bear", 779), ("MAGE_F", "frost", 120)):
        lua.globals().Defaults(cls, tree, "cleave")
        assert sid in [e.id for e in lua.globals().entries.values()]
    lua.globals().Defaults("DRUID_F", "balance", "st")
    lua.execute("filtered[2912]=true")
    assert 5176 in list(lua.globals().Build().values()), "Wrath remains when Starfire is unavailable"
    lua.globals().Defaults("MAGE_F", "arcane", "st")
    assert len(lua.globals().RotationImport.GetEntry(400574).gates) == 0
    assert len(lua.globals().RotationImport.GetEntry(116).gates) > 0
    lua.globals().Defaults("WARRIOR_F", "arms", "aoe")
    lua.globals().enemyCount = 3
    assert lua.globals().Gate(1680, 1) is True
    lua.globals().enemyCount = 2
    assert lua.globals().Gate(1680, 1) is False
    lua.globals().Defaults("WARRIOR_F", "fury", "st")
    lua.execute("cooldown[23881]=true")
    assert len(lua.globals().RotationImport.GetEntry(1680).gates) == 0
    lua.globals().Defaults("WARRIOR_F", "fury", "aoe")
    lua.globals().enemyCount = 2
    assert len(lua.globals().RotationImport.GetEntry(1680).gates) == 0
    lua.globals().Defaults("PALADIN_F", "retribution", "st")
    lua.execute("buffs[20154]=true")
    assert lua.globals().Gate(20154, 1) is False, "An active seal is not reapplied"
    assert lua.eval("SpellQueue._GateVerdict(RotationImport.GetEntry(20271).gates[2],{strict=true})") is True
    lua.execute("buffs={}")
    assert 20154 in list(lua.globals().Build().values()), "Righteousness remains available without a seal"
    lua.globals().Defaults("DRUID_F", "feral", "st")
    bite = lua.globals().RotationImport.GetEntry(1328618).gates
    assert bite[1].op == ">="
    lua.execute("""
        pool={1328618,1082}; points=3; b.ctxPointCap=3
        C_Spell.GetSpellPowerCost=function(id)
            if id == 1328618 then return {{type=4,minCost=1,cost=5}} end
            return {}
        end
        finisher[1328618]=true
    """)
    assert list(lua.globals().Build().values())[0] == 1328618
    lua.globals().Defaults("PRIEST_F", "holy", "st")
    lua.execute("pool={14914,585}; cooldown[14914]=true; b.maxIcons=1")
    assert list(lua.globals().Build().values()) == [585]
    # No adaptation is applied to custom source ordering by this data generator.
    lua.globals().Defaults("DRUID_F", "feral", "st")
    lua.execute("SpellQueue._rotationIsCustom=true; b.contextOrder='off'; pool={1082,1328618}")
    assert list(lua.globals().Build().values()) == [1082, 1328618]
    print(f"Forever general priorities: {contexts} contexts, {builds} queue builds and targeted regressions passed")


if __name__ == "__main__":
    main()
