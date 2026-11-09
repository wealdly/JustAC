# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
from gen_forever_rotations import (
    Conv, UNK, actions_of, on_enemy, tier_lists,
)
from test_forever_openers import create_runtime


def main():
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
        ("WARLOCK_F", "affliction", 5740),
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
    lua.execute(f"pool={{14914,{penance},589,585}}; cooldown[14914]=true")
    queue = list(lua.globals().Build().values())
    assert queue.index(penance) < queue.index(585)
    assert queue.index(589) < queue.index(585)
    assert 14751 not in [e.id for e in lua.globals().entries.values()]
    for cls, tree, sid in (("DRUID_F", "feral_bear", 779), ("MAGE_F", "frost", 120)):
        lua.globals().Defaults(cls, tree, "cleave")
        assert sid in [e.id for e in lua.globals().entries.values()]
    lua.globals().Defaults("DRUID_F", "balance", "st")
    lua.execute("filtered[2912]=true")
    assert 5176 in list(lua.globals().Build().values()), "Wrath remains when Starfire is unavailable"
    lua.globals().Defaults("MAGE_F", "arcane", "st")
    assert len(lua.globals().RotationImport.GetEntry(116).gates) == 0
    assert lua.globals().RotationImport.GetEntry(116).rank > lua.globals().RotationImport.GetEntry(1239700).rank
    lua.globals().Defaults("WARRIOR_F", "arms", "st")
    lua.execute("talents[23881]=false")
    assert lua.globals().Gate(1680, 1) is True, "Whirlwind's single-target fallback survives an unlearned Bloodthirst"
    lua.globals().Defaults("WARRIOR_F", "fury", "st")
    lua.execute("cooldown[23881]=true")
    assert lua.globals().Gate(1680, 1) is True
    lua.globals().Defaults("WARRIOR_F", "fury", "aoe")
    lua.globals().enemyCount = 2
    assert lua.globals().Gate(1680, 1) is True
    lua.globals().Defaults("PALADIN_F", "retribution", "st")
    lua.execute("buffs[20154]=true")
    assert lua.globals().Gate(20375, 2) is False, "Active Righteousness is not displaced for Command"
    lua.execute("buffs={}; talents[20375]=false; filtered[20375]=true")
    assert 20154 in list(lua.globals().Build().values()), "Righteousness backs up an unlearned Command"
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
    lua.execute(f"pool={{{penance},585}}; b.maxIcons=1")
    assert list(lua.globals().Build().values()) == [penance]
    # No adaptation is applied to custom source ordering by this data generator.
    lua.globals().Defaults("DRUID_F", "feral", "st")
    lua.execute("SpellQueue._rotationIsCustom=true; b.contextOrder='off'; pool={1082,1328618}")
    assert list(lua.globals().Build().values()) == [1082, 1328618]
    print(f"Forever general priorities: {contexts} contexts, {builds} queue builds and targeted regressions passed")


if __name__ == "__main__":
    main()
