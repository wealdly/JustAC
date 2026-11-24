# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The offline list bench's setup checks, without the simulator: what a setup can never use
(stance and equipment, from the client's own spell data), the pack request, and the
damage-taken and fixed-pull readings of a result.

Run: python tools/test_forever_sim_bench.py
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forever_sim_bench as bench  # noqa: E402

NAMES = {6572: "Revenge", 23922: "Shield Slam", 772: "Rend", 1680: "Whirlwind", 2458: "Berserker Stance",
         5019: "Shoot"}
ONE_HAND = bench.LOADOUTS["warrior"]["shield"]["weapon"]["subclasses"]
TWO_HAND = bench.LOADOUTS["warrior"]["2h"]["weapon"]["subclasses"]


def why(entries, stance, subclasses, shield, wand=False):
    return dict(bench.usability_problems([{"id": i} for i in entries], NAMES, stance, subclasses, shield, wand))


def pack_rules(data):
    return bench.RuntimeRules(data, "warrior", "fury", 0, False, True)


def main():
    prot = [6572, 23922, 772]
    # Protection as it is played: nothing in its core is out of reach.
    assert why(prot, "Defensive", ONE_HAND, True) == {}, why(prot, "Defensive", ONE_HAND, True)
    # The setup that hid Revenge and Shield Slam (Battle Stance, two-hander) is now named.
    wrong = why(prot, "Battle", TWO_HAND, False)
    assert "Defensive" in wrong["Revenge (6572)"], wrong
    assert "shield" in wrong["Shield Slam (23922)"], wrong
    assert "Rend (772)" not in wrong, "Rend works in Battle Stance"
    # A stance the list swaps to is reachable, and said to be.
    fury = why([1680, 2458], "Battle", TWO_HAND, False)
    assert "after the list swaps" in fury["Whirlwind (1680)"], fury
    assert why([1680], "Battle", TWO_HAND, False)["Whirlwind (1680)"].startswith("needs Berserker"), "no swap entry"
    # A class without stances is not stance-checked; a wand covers Shoot.
    assert why([5019], None, (10,), False, wand=True) == {}, "the wand serves Shoot"

    # A pack: several identical targets for a fixed pull, damage per second over it.
    bench.PULL.update(mobs=3, seconds=20.0)
    scenario = {"name": "L30 vs 30", "target_level": 30, "elite": False, "_armor_idx": 0, "_health_idx": 1}
    request = bench.build_request("warrior", 30, "", ([{}] * 17, [], {}), scenario, {30: (1000.0, 10.0, 500.0)},
                                  {}, 10, 1)
    encounter = request["encounter"]
    assert len(encounter["targets"]) == 3 and encounter["useHealth"] is False and encounter["duration"] == 20.0
    result = {"iterationsDone": 10,
              "raidMetrics": {"parties": [{"players": [{"actions": [
                  {"id": {"spellId": 11581}, "targets": [{"casts": 30, "damage": 6000.0}]}], "resources": []}]}]},
              "encounterMetrics": {"targets": [{"actions": [
                  {"id": {"otherId": "OtherActionAttack"}, "targets": [{"casts": 100, "damage": 4000.0}]}]}]}}
    got = bench.summarize(result, 2.0)
    assert abs(got["dps"] - 30.0) < 1e-9 and got["taken"] == 400.0 and got["kill"] != got["kill"], got
    # One target: the kill time clock, and damage taken per fight from the target's own actions.
    bench.PULL.update(mobs=1)
    got = bench.summarize(result, 2.0)
    assert abs(got["kill"] - 19.0) < 1e-9 and got["taken"] == 400.0, got
    assert got["clock"] == "target swings", "no real fight length in the result: the swing clock"
    # A simulator that reports the real fight length: that is the kill time, whatever the swings say
    # (a slowed target swings less often). A nominal duration is not a kill time.
    got = bench.summarize(dict(result, avgIterationDuration=23.4), 2.0)
    assert abs(got["kill"] - 23.4) < 1e-9 and got["clock"] == "simulator", got
    assert abs(got["swing_kill"] - 19.0) < 1e-9, "the swing clock is kept beside it, to check one against the other"
    assert abs(got["dps"] - 600.0 / 23.4) < 1e-9, got
    for nominal in (600.0, 180.0):
        got = bench.summarize(dict(result, avgIterationDuration=nominal), 2.0)
        assert abs(got["kill"] - 19.0) < 1e-9 and got["clock"] == "target swings", (nominal, got)

    # Levelling builds take Wand Specialization first; it adds 13% wand damage a rank.
    shadow = bench.CLASSES["priest"]["trees"]["shadow"]
    sim = os.path.join(os.path.dirname(bench.ROOT), "wow-forever-sim")
    if os.path.isdir(sim):
        assert bench.talents_for_level(sim, "priest", shadow, 11) == "02--", "the first two points go to Wand Specialization"
        assert bench.talents_for_level(sim, "priest", shadow, 13) == "02--2", "then the build's main tree"
    if os.path.isdir(sim):
        assert abs(bench.wand_spec_bonus(sim, "priest", "02--2") - 0.26) < 1e-9
        assert bench.wand_spec_bonus(sim, "priest", "--5") == 0
        assert abs(bench.wand_spec_bonus(sim, "mage", "1-02-") - 0.13) < 1e-9
        assert bench.wand_spec_bonus(sim, "warlock", "52") == 0, "a class without the talent"
        assert bench.talents_for_level(sim, "mage", bench.CLASSES["mage"]["trees"]["fire"], 11) == "2--"
    assert 1787 in bench.FIXED_IDS, "the rogue's Stealth aura, from its class entry"

    # The weapon stage: pushback lengthens a cast (1.0 s, then 0.2 s less per hit, never under 0.2 s).
    assert bench.pushed_cast_seconds(1.5, 2.0) == 1.5, "no swing lands inside a short cast"
    assert abs(bench.pushed_cast_seconds(2.0, 2.0) - 3.0) < 1e-9, "one hit at 2 s pushes it 1 s"
    assert abs(bench.pushed_cast_seconds(2.5, 1.0) - (2.5 + 1.0 + 0.8 + 0.6 + 0.4 + 0.2)) < 1e-9, "five hits land before the cast ends at 5.5 s"
    cfg = dict(bench.CLASSES["priest"], engagement="caster")
    smite = [(1, 0, 1.5, 12.0, 0.0), (6, 0, 2.0, 30.0, 0.0)]
    real = bench.weapon_rule_spells
    try:
        bench.weapon_rule_spells = lambda cls: {585: smite}
        entries = [{"id": 585, "gates": []}, {"id": 589, "gates": []}]
        kept, notes = bench.weapon_rule_entries(entries, "priest", cfg, 10, 11.0, 2.9)
        assert kept[0]["gates"] == [{"t": "bench_unhindered", "n": 2.9, "shield": 17}] and kept[1] == entries[1],             "a priest's Smite: before the target arrives or while the pre-pull shield holds"
        kept, _ = bench.weapon_rule_entries(entries, "priest", cfg, 10, 5.0, 2.9)
        assert kept == entries, "a cast that beats the wand under pushback is pressed as written"
        kept, notes = bench.weapon_rule_entries(entries, "priest", cfg, 10, 25.0, 2.9)
        assert [e["id"] for e in kept] == [589] and "left to the wand" in notes[0], (kept, notes)
        assert bench.weapon_rule_entries(entries, "priest", cfg, 10, None, 2.9)[0] == entries, "no wand: as written"
    finally:
        bench.weapon_rule_spells = real

    # Recorded kills: solo ones only, with the creature's level range and kind.
    import tempfile
    sample = ('JustACGlobal = {\n["mobProfile"] = {\n["npcs"] = {\n[114] = {\n["class"] = "normal",\n'
              '["lvMin"] = 14,\n["lvMax"] = 15,\n["name"] = "Harvest Watcher",\n["kills"] = {\n'
              '{\n["group"] = false,\n["d"] = 34.6,\n["plvl"] = 14,\n},\n{\n["group"] = true,\n["d"] = 9,\n'
              '["plvl"] = 14,\n},\n},\n},\n[7] = {\n["class"] = "worldboss",\n["lvMin"] = 20,\n["kills"] = {\n'
              '{\n["group"] = false,\n["d"] = 90,\n["plvl"] = 14,\n},\n},\n},\n},\n},\n}\n')
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as handle:
        handle.write(sample)
    kills = bench.recorded_kills(handle.name)
    assert kills == [{"name": "Harvest Watcher", "levels": [14, 15], "elite": False, "plvl": 14, "seconds": 34.6}], kills
    assert bench.calibration_factor([1.2, 1.4, 1.0, 1.3], 0.75) == 1.3, "the 75% point, nearest rank"
    assert bench.calibration_factor([1.2], 0.75) == 1.2 and bench.calibration_factor([1.0, 2.0], 0.5) == 1.0
    bench.HEALTH["by_gap"] = {-3: 0.5, 1: 2.0}
    assert bench.health_factor(-3) == 0.5 and bench.health_factor(1) == 2.0, "measured gaps"
    assert abs(bench.health_factor(-1) - 1.0) < 1e-9, "halfway on a log scale between 0.5 and 2"
    assert bench.health_factor(-5) == 0.5 and bench.health_factor(3) == 2.0, "the nearest measured gap outside"
    bench.HEALTH["by_gap"] = {}
    bench.HEALTH["scale"] = 1.5
    scaled = bench.build_request("warrior", 30, "", ([{}] * 17, [], {}), scenario, {30: (1000.0, 10.0, 500.0)}, {}, 10, 1)
    assert scaled["encounter"]["targets"][0]["stats"][1] == 1500.0, "health scale applies to the target"
    bench.HEALTH["scale"] = 1.0

    # Level gaps as scenarios.
    names = [s["name"] for s in bench.gap_scenarios(10, [-3, -1, 0, 2])]
    assert names == ["L10 vs 7 (3 below)", "L10 vs 9 (one below)", "L10 vs 10 (even)", "L10 vs 12 (2 above)"], names
    assert [s["target_level"] for s in bench.gap_scenarios(2, [-3, 0])] == [2], "no target below level 1"

    # Every class and tree with a generated list has a bench entry, and each entry is complete.
    classes, _, _ = bench.load_rotations()
    for key, trees in sorted(classes.items()):
        cls = key[:-2].lower()
        assert cls in bench.CLASSES, "no bench entry for " + cls
        cfg = bench.CLASSES[cls]
        for field in ("proto_class", "spec", "race", "engagement", "class_id", "weapon", "armor", "stat_weights",
                      "trees", "actions", "unmodelled"):
            assert field in cfg, (cls, field)
        for tree in trees:
            if not isinstance(trees[tree], dict):
                continue   # the class's default tree name
            assert tree in cfg["trees"], "no bench entry for %s %s" % (cls, tree)
            tcfg = cfg["trees"][tree]
            assert tcfg["sim_preset"].endswith(".apl.json") and tcfg["talents"] and "main_tree" in tcfg, (cls, tree)
            assert tcfg.get("engagement", cfg["engagement"]) in bench.ENGAGEMENTS, (cls, tree)
            if tcfg.get("loadout"):
                assert tcfg["loadout"] in bench.LOADOUTS[cls], (cls, tree)
            source = tcfg.get("source_preset")
            assert not source or (Path(bench.PRESETS) / source).is_file(), (cls, tree, source)
    # Trees the simulator only has at its level brackets say so.
    # No tree is limited to the simulator's bracket levels any more: the local simulator changes
    # give every class the rank its level has (tools/forever-sim-patches).
    assert not any("levels" in cfg or any("levels" in tree for tree in cfg["trees"].values())
                   for cfg in bench.CLASSES.values())

    # Spec options that follow the level reach the request.
    hunter = bench.build_request("hunter", 40, "", ([{}] * 17, [], {}), dict(scenario), {30: (1000.0, 10.0, 500.0)}, {}, 10, 1)
    player = hunter["raid"]["parties"][0]["players"][0]
    assert player["hunter"]["options"]["ammo"] == "JaggedArrow" and player["hunter"]["options"]["petType"] == "PetNone"
    assert player["distanceFromTarget"] == 30 and hunter["encounter"]["targets"][0]["minBaseDamage"] == 0, "shoots, never hit"
    assert bench.hunter_spec(14)["ammo"] == "AmmoNone" and bench.enhancement_spec(30)["mainHandImbue"] == "WindfuryImbue"

    # Druid forms use the same check as warrior stances; a totem gate reads the totem's time left.
    forms, spells = bench.CLASSES["druid"]["forms"], bench.CLASSES["druid"]["form_spells"]
    cat = dict(bench.usability_problems([{"id": 5221}, {"id": 6807}], {5221: "Shred", 6807: "Maul"}, "Cat", (10,), False,
                                        False, forms, spells, "Form"))
    assert "Shred (5221)" not in cat and "Bear" in cat.get("Maul (6807)", ""), cat
    conv = bench.Converter(None, {}, "melee", None)
    down = conv.gate({"t": "totem", "slot": 1, "neg": True})
    assert down["cmp"]["lhs"] == {"totemRemainingTime": {"totemType": "Fire"}} and down["cmp"]["op"] == "OpLe", down
    assert conv.report[-1][1] == bench.EXACT

    # The simulator is throttled by default: a share of the cores, lowest priority.
    assert 1 <= bench.SIM_THREADS["n"] <= max(1, (bench.os.cpu_count() or 2) // 2)
    assert bench.low_priority_args(), "low priority by default"

    # Ranks: the highest the level has, never a level 60 book rank the simulator leaves out.
    family = [([133, 143, 10151, 25306], [1, 6, 60, 60])]
    cast = {"castSpell": {"spellId": {"spellId": 25306}}}
    assert bench.ranks_for_level(cast, family, 60)["castSpell"]["spellId"]["spellId"] == 10151, "no book rank"
    assert bench.ranks_for_level(cast, family, 14)["castSpell"]["spellId"]["spellId"] == 143
    assert bench.ranks_for_level(cast, family, 14) is not cast and cast["castSpell"]["spellId"]["spellId"] == 25306

    # A "known" gate on a talent follows the build being run, not the simulator's spell book.
    class Names:
        cfg = {}
        name_of = staticmethod(lambda sid: {11095: "Improved Scorch"}.get(sid))
    taken = bench.Converter(Names, {}, "caster", None, None, {"Improved Scorch": 3})
    assert taken.gate({"t": "known", "id": 11095}) == {"const": {"val": "true"}}
    assert taken.gate({"t": "known", "id": 11095, "neg": True}) == {"not": {"val": {"const": {"val": "true"}}}}
    untaken = bench.Converter(Names, {}, "caster", None, None, {"Improved Scorch": 0})
    assert untaken.gate({"t": "known", "id": 11095}) == {"const": {"val": "false"}}

    # An aura the simulator keeps on the caster is read there, whatever the list says.
    mage = bench.CLASSES["mage"]
    assert mage["aura_alias"][22959] in mage["self_auras"]

    # Weapons: every type the class can learn, in the setup's own shape; a fixed setup stays.
    rogue = bench.trainable_weapons(bench.CLASSES["rogue"]["class_id"])
    assert rogue.get(0) == "Axes" and 15 in rogue and 5 not in rogue and 19 not in rogue, rogue
    assert 6 in bench.trainable_weapons(bench.CLASSES["druid"]["class_id"])
    opened = dict(bench.CLASSES["rogue"], weapon=bench.LOADOUTS["rogue"]["dw"]["weapon"])
    bench.open_weapons(opened)
    assert 0 in opened["weapon"]["subclasses"] and 2 not in opened["weapon"]["subclasses"], opened["weapon"]
    assert opened["weapon"]["inv"] == (13, 21)
    fixed = dict(bench.CLASSES["rogue"], weapon=bench.LOADOUTS["rogue"]["daggers"]["weapon"])
    bench.open_weapons(fixed)
    assert fixed["weapon"]["subclasses"] == (15,), fixed["weapon"]
    hunter = dict(bench.CLASSES["hunter"])
    bench.open_weapons(hunter)
    assert set(hunter["ranged"]["subclasses"]) == set((2, 3, 18)) and 4 not in hunter["weapon"]["subclasses"]

    # Retired and internal items never enter a gear setup.
    for name in ("Deprecated Glorious Shield", "Monster - Sword", "TEST Staff", "Old Belt (old)"):
        assert bench.RETIRED_ITEM.search(name), name
    assert not bench.RETIRED_ITEM.search("Glorious Shield") and not bench.RETIRED_ITEM.search("Tester's Cloak")

    # Dual wield: two one-hand weapons from an assumed level (the client data has none).
    assert bench.dual_wield_level() == bench.ASSUMED_DUAL_WIELD_LEVEL
    assert bench.LOADOUTS["warrior"]["dw"]["dual"] and not bench.LOADOUTS["warrior"]["dw"]["shield"]

    # The queue's rules outside the lists, from the generated data, per scenario.
    data = bench.runtime_data()
    sunder = {"id": 7386, "gates": [{"t": "stack", "id": 7386, "op": "<", "n": 1, "tgt": True}]}
    elite = bench.RuntimeRules(data, "warrior", "fury", 1, True, False)
    even = bench.RuntimeRules(data, "warrior", "fury", 0, False, False)
    assert elite.stack(sunder, sunder["gates"][0])[0]["n"] == 5, "five stacks on an elite"
    assert even.stack(sunder, sunder["gates"][0])[0]["n"] == 1, "one on an ordinary target"
    once = dict(sunder["gates"][0], once=True)
    assert elite.stack(sunder, once)[0]["n"] == 1, "a pack list stops at one"
    held, _ = even.hold(sunder)
    assert held and "currentTime" in held["cmp"]["lhs"], "Fury holds Sunder until the fight has lasted"
    assert elite.hold(sunder)[0] is None, "an elite releases it"
    assert bench.RuntimeRules(data, "warrior", "arms", 0, False, False).hold(sunder)[0] is None, "Arms applies it at once"
    held, _ = bench.RuntimeRules(data, "warrior", "protection", 0, False, False).hold(sunder)
    assert held is not None, "a tank alone holds it like the rest"
    bench.GROUPED["on"] = True
    try:
        assert bench.RuntimeRules(data, "warrior", "protection", 0, False, False).hold(sunder)[0] is None,             "a grouped tank applies it at once"
    finally:
        bench.GROUPED["on"] = False
    # A major cooldown waits for a fight worth it: an elite or a pack at once, else a lasting fight.
    assert 1719 in data["burst"]["warrior"] and 3045 in data["burst"]["hunter"], data["burst"]
    reck = {"id": 1719, "gates": []}
    held, said = even.hold(reck)
    assert held == {"const": {"val": "false"}} and "major cooldown held" in said, said
    assert elite.hold(reck)[0] is None and pack_rules(data).hold(reck)[0] is None
    higher = bench.RuntimeRules(data, "warrior", "fury", 1, False, False)
    assert higher.hold(reck)[0] is not None, "a higher level alone does not release a self-buff"
    assert data["higher_level"] == 3, data["higher_level"]
    assert bench.RuntimeRules(data, "warrior", "fury", 3, False, False).hold(reck)[0] is None
    assert bench.RuntimeRules(data, "warrior", "fury", 2, False, False).hold(reck)[0] is not None
    assert bench.RuntimeRules(data, "warrior", "fury", 2, False, False, 2).hold(reck)[0] is None
    doom = {"id": 603, "gates": []}
    assert bench.RuntimeRules(data, "warlock", "affliction", 0, False, False).hold(doom)[0] == {"const": {"val": "false"}}
    assert bench.RuntimeRules(data, "warlock", "affliction", 1, False, False).hold(doom)[0] is None

    class Conv:
        health_fraction = staticmethod(lambda op, pct: ("health", op, pct))
        spell_ref = staticmethod(lambda sid, what: {"spellId": sid})
    rend = {"t": "debuff", "id": 772, "neg": True, "refresh": True}
    fast, said = even.dot(Conv, rend, "absent")
    assert str(("health", ">=", 70)) in str(fast) and "70" in said, said
    slow, said = elite.dot(Conv, rend, "absent")
    assert "70" not in said and "35" in said, said
    fireball = {"t": "debuff", "id": 133, "neg": True, "refresh": True}
    assert even.dot(Conv, fireball, "absent")[0] == "absent", "a spell that is mostly its hit has no health rule"
    pack = bench.RuntimeRules(data, "warrior", "fury", 0, False, True)
    assert pack.dot(Conv, rend, "absent")[0] == "absent", "no health rules in a fixed pull"
    print("forever sim bench: setup usability, pack requests, damage taken and runtime rules read as intended")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
