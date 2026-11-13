#!/usr/bin/env python3
# The converter rules most likely to break silently. Run: python tools/test_forever_rotations.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_forever_rotations import Conv, TRUE, FALSE, UNK  # noqa: E402
from gen_forever_rotations import condition_coverage
from gen_forever_rotations import add_extras, generalize_entries, keeps_own_buff, tier_lists
from gen_forever_rotations import rank1
from gen_forever_rotations import DURATION
import check_forever_apl as cfa

paladinChains, _ = cfa.class_chains(cfa.CLASS_MASK["paladin"])

sealIDs = sorted({rank1(chain) for name, chain in paladinChains.items()
                  if name.startswith("seal_of_")})
judgeID = rank1(paladinChains["judgement"])
sealID = rank1(paladinChains["seal_of_righteousness"])
unrelatedGate = {"t": "known", "id": 123}
savedDurations = dict(DURATION)
DURATION.update({sid: 30 for sid in sealIDs})
for tree in ("holy", "protection", "retribution"):
    entries = [{"id": judgeID, "gates": [unrelatedGate, {"t": "buff", "id": sealID}],
                "delegated": False, "tiers": ["st", "aoe"]}]
    if tree != "holy":
        entries += [{"id": sealID, "gates": [], "delegated": True, "tiers": ["st"]}] * 2
    generalize_entries("paladin", tree, entries, paladinChains)
    entries.sort(key=lambda e: 0 if keeps_own_buff(e) else 1)
    assert entries[0]["id"] == sealID
    assert len([e for e in entries if e["id"] == sealID]) == 1
    seal = entries[0]
    judge = next(e for e in entries if e["id"] == judgeID)
    assert {g["id"] for g in seal["gates"]} == set(sealIDs)
    assert all(g["t"] == "buff" and g["neg"] for g in seal["gates"])
    assert not seal["delegated"]
    assert judge["gates"][0] == unrelatedGate
    requirement = judge["gates"][1]
    assert requirement["t"] == "any"
    assert {g["id"] for g in requirement["g"]} == set(sealIDs)
    assert all(g["t"] == "buff" and not g.get("neg") for g in requirement["g"])
    assert len(judge["gates"]) == 2
    lists = tier_lists(entries)
    for context in ("st", "aoe"):
        ids = [e["id"] for e in lists.get(context, lists["st"])]
        assert ids.index(sealID) < ids.index(judgeID)
DURATION.clear()
DURATION.update(savedDurations)

hunterChains, _ = cfa.class_chains(cfa.CLASS_MASK["hunter"])
sniperID = rank1(hunterChains["sniper_shot"])
aimedID = rank1(hunterChains["aimed_shot"])
hunterEntries = [
    {"id": aimedID, "gates": [], "delegated": False, "tiers": ["st", "cleave", "aoe"]},
    {"id": sniperID, "gates": [{"t": "unconfirmed"}], "delegated": False,
     "tiers": ["st", "cleave", "aoe"]},
]
add_extras("hunter", "marksmanship", hunterEntries, hunterChains, [])
sniperEntry = next(e for e in hunterEntries if e["id"] == sniperID)
assert [e["id"] for e in hunterEntries].index(sniperID) < \
    [e["id"] for e in hunterEntries].index(aimedID)
assert sniperEntry["gates"] == [] and not sniperEntry["delegated"]

rogueChains, _ = cfa.class_chains(cfa.CLASS_MASK["rogue"])
shankID = rank1(rogueChains["shank"])
eviscerateID = rank1(rogueChains["eviscerate"])
rogueEntries = [
    {"id": eviscerateID, "gates": [], "delegated": False, "tiers": ["st"]},
    {"id": shankID, "gates": [{"t": "power", "res": "energy", "op": "<", "n": 80}],
     "delegated": False, "tiers": ["st"]},
]
add_extras("rogue", "combat", rogueEntries, rogueChains, [])
assert [e["id"] for e in rogueEntries].index(shankID) < \
    [e["id"] for e in rogueEntries].index(eviscerateID)

coverage = list(condition_coverage([
    {"t": "any", "g": [{"t": "known", "id": 1}, {"t": "dot", "id": 2}]},
    {"t": "unconfirmed"}, {"t": "stack", "id": 3, "n": 5}, {"t": "tick"},
]))
assert [row["path"] for row in coverage] == ["1", "1.1", "1.2", "2", "3", "4"]
assert [row["status"] for row in coverage] == [
    "partial", "fully supported", "partial", "disabled", "partial", "partial",
]

c = lambda v: {"const": {"val": v}}
cmp = lambda op, lhs, n: {"cmp": {"op": op, "lhs": lhs, "rhs": c(n)}}
dot = lambda sid: {"dotIsActive": {"spellId": {"spellId": sid}}}
targets = {"numberTargets": {}}

conv = Conv({}, self_id=772)
# const on the left flips the comparison
assert conv.conv({"cmp": {"op": "OpLt", "lhs": c("40"), "rhs": {"currentRage": {}}}}) == \
    {"t": "power", "res": "rage", "op": ">", "n": 40.0}
# Refresh policy and another aura's presence retain distinct meanings.
assert conv.conv({"not": {"val": dot(772)}}) == {"t": "debuff", "id": 772, "neg": True, "refresh": True}
other = Conv({}, self_id=772)
assert other.conv({"not": {"val": dot(11198)}}) == {"t": "debuff", "id": 11198, "neg": True}
assert not other.delegated
# an `or` with an inexpressible member is dropped whole, never made stricter
o = Conv({})
assert o.conv({"or": {"vals": [cmp("OpGe", {"currentRage": {}}, "80"), {"bossSpellIsCasting": {}}]}}) == TRUE
assert o.delegated
# fight length assumed long: "plenty left" holds, "fight ending" never does
assert Conv({}).conv(cmp("OpGe", {"remainingTime": {}}, "6s")) == TRUE
assert Conv({}).conv(cmp("OpLt", {"remainingTime": {}}, "6s")) == FALSE
# target count decides tiers, not gates
t = Conv({})
aoe_only = cmp("OpGe", targets, "3")
assert [t.tier(aoe_only, k) for k in (1, 2, 3)] == [False, False, True]
assert t.conv(aoe_only) == {"t": "targets", "op": ">=", "n": 3.0}
# negation flips thresholds and buffs, De Morgan for groups
n = Conv({})
assert n.conv({"not": {"val": {"and": {"vals": [cmp("OpLt", {"currentEnergy": {}}, "50"),
                                               {"auraIsActive": {"auraId": {"spellId": 6774}}}]}}}}) == \
    {"t": "any", "g": [{"t": "power", "res": "energy", "op": ">=", "n": 50.0},
                       {"t": "buff", "id": 6774, "neg": True}]}
# units: ms and s become seconds
assert Conv({}).conv(cmp("OpLt", {"autoTimeToNext": {}}, "500ms")) == {"t": "swing", "op": "<", "n": 0.5}
# Conditions Forever can time itself are gates, not delegations (a delegated entry never leads).
rem = lambda name, sid: {name: {"spellId": {"spellId": sid}, "auraId": {"spellId": sid}}}
d = Conv({}, self_id=348)   # Immolate: refresh as its time left <= its cast time
assert d.conv({"cmp": {"op": "OpLe", "lhs": rem("dotRemainingTime", 348),
                       "rhs": {"spellCastTime": {"spellId": {"spellId": 348}}}}}) == \
    {"t": "debuff", "id": 348, "neg": True, "refresh": True}
assert not d.delegated
b = Conv({}, self_id=5171)  # Slice and Dice about to drop = my own buff down
assert b.conv(cmp("OpLt", rem("auraRemainingTime", 5171), "3"))["neg"] is True and not b.delegated
assert Conv({}).conv({"frontOfTarget": {}}) == UNK
facing = Conv({})
assert facing.conv({"not": {"val": {"frontOfTarget": {}}}}) == TRUE and facing.delegated
k = Conv({603: [("603", "")]}, self_id=980)  # Bane of Agony unless Bane of Doom (a class spell)
assert k.conv({"not": {"val": dot(603)}}) == {"t": "debuff", "id": 603, "neg": True}
assert not k.delegated
assert Conv({}, self_id=7386).conv({"not": {"val": dot(11198)}}) == {"t": "debuff", "id": 11198, "neg": True}
timed = Conv({}, self_id=1328618)
assert timed.conv(cmp("OpGt", rem("dotRemainingTime", 1079), "3s")) == \
    {"t": "debuff", "id": 1079, "op": ">", "n": 3.0}
assert timed.delegated
assert Conv({}).conv(cmp("OpLe", {"unitDistance": {}}, "10")) == {"t": "near", "n": 10.0}
assert Conv({}, self_id=8075).conv(cmp("OpLe", {"totemRemainingTime": {"totemType": "Earth"}}, "0s")) == \
    {"t": "totem", "slot": 2, "neg": True}
pace = Conv({})
assert pace.conv({"cmp": {"op": "OpGe", "lhs": {"currentMana": {}}, "rhs": {"math": {
    "op": "OpMul", "lhs": {"remainingTime": {}}, "rhs": {"const": {"val": "35"}}}}}}) == {"t": "unconfirmed"}
# The shipped bar pool (Data/Forever/Rotations.lua, last table): combat abilities in, utility out.
import re  # noqa: E402
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = open(os.path.join(root, "Data", "Forever", "Rotations.lua"), encoding="utf-8").read()
assert "https://github.com/sage3648/mythicsim-forever-engine" in data
assert "MIT License" in data
pool = {k: {int(i) for i in v.split(",")} for k, v in re.findall(r'\["(\w+_F)"\] = \{([\d,]+)\}', data)}
IN = {"HUNTER_F": [75, 6603, 1510, 13795],        # Auto Shot, Attack, Volley, Immolation Trap
      "WARRIOR_F": [12292, 2457, 2764],           # Sweeping Strikes, Battle Stance, Throw
      "DRUID_F": [768, 5487, 16914],              # Cat Form, Bear Form, Hurricane
      "PRIEST_F": [15473, 20554, 1277331],        # Shadowform, Berserking, Chastise (root side effect)
      "ROGUE_F": [53, 2480, 14251],               # Backstab, Shoot Bow, Riposte
      "SHAMAN_F": [8042, 8056],                   # Earth Shock (6s interrupt), Frost Shock
      "MAGE_F": [5019, 401502],                   # Shoot (wand), Frostfire Bolt (slow side effect)
      "PALADIN_F": [2812, 21082]}                 # Holy Wrath, Seal of the Crusader
OUT = {"HUNTER_F": [1494, 5118, 6991, 5116,       # Track Beasts, Aspect of the Cheetah, Feed Pet, Concussive Shot
                    19503, 1499, 1543],           # Scatter Shot (CC), Freezing Trap, Flare
       "WARLOCK_F": [702, 5782, 755, 6789],       # Curse of Weakness, Fear, Health Funnel, Death Coil (horror)
       "DRUID_F": [783, 1066, 1850, 9005, 339],   # Travel / Aquatic Form, Dash, Pounce (stun), Entangling Roots
       "MAGE_F": [587],                           # Conjure Food
       "SHAMAN_F": [2645],                        # Ghost Wolf
       "ROGUE_F": [1766, 1776, 1784, 2983],       # Kick (10s interrupt), Gouge, Stealth, Sprint
       "PRIEST_F": [605],                         # Mind Control
       "PALADIN_F": [20164, 461607],              # Seal of Justice, Divine Steed
       # racials by role only: Escape Artist (defensive), Rapid Regeneration (no combat role);
       # Pummel, Shield Bash (interrupts), Mocking Blow (taunt)
       "WARRIOR_F": [20589, 1260270, 6552, 72, 694]}
for k, ids in IN.items():
    assert all(i in pool[k] for i in ids), (k, [i for i in ids if i not in pool[k]])
for k, ids in OUT.items():
    assert not any(i in pool[k] for i in ids), (k, [i for i in ids if i in pool[k]])
# Resource-for-a-price lines (REGATE): offered only when needed (w), starved / health floors.
line = lambda sid: re.search(r"\{id=%d,gates=(.*?)\},  --" % sid, data).group(1)
for sid, need in [(1454, ('t="starved"', 'pct=50', "w=true")),      # Life Tap
                  (12051, ('t="starved"', "w=true")),                # Evocation
                  (29166, ('t="starved"', "w=true")),                # Innervate
                  (2687, ('t="health"', "w=true"))]:                 # Bloodrage
    assert all(n in line(sid) for n in need), (sid, line(sid))
hellfire_lines = [entry for entry in data.splitlines() if "{id=1949," in entry]
assert hellfire_lines and all(
    't="near"' in entry and 'pct=50' in entry and "w=true" in entry
    for entry in hellfire_lines
), hellfire_lines
# Hunters open with Serpent Sting (its own conditions kept), cast with Auto Shot right behind it.
hunter = data[data.index('["HUNTER_F"] = {'):data.index('["MAGE_F"] = {')]
for tree in ("beast_mastery", "marksmanship", "survival"):
    block = hunter[hunter.index(tree + " = {"):]
    ids = [int(i) for i in re.findall(r"\{id=(\d+),", block)[:2]]
    assert ids == [1978, 75], (tree, ids)
# Backstab precedes Sinister Strike when usable, but follows each tree's main builder.
rogue = data[data.index('["ROGUE_F"] = {'):data.index('["SHAMAN_F"] = {')]
import check_forever_apl as cfa  # noqa: E402
from gen_forever_rotations import rank1  # noqa: E402

rogueChains, _ = cfa.class_chains(cfa.CLASS_MASK["rogue"])
for tree, main_builder in (("combat", None), ("subtlety", 16511),
                           ("assassination", rank1(rogueChains["mutilate"]))):
    block = rogue[rogue.index(tree + " = {"):]
    block = block[:block.index("\n    },")]
    ids = [int(i) for i in re.findall(r"\{id=(\d+),", block)]
    builder_ids = [sid for sid in ids if sid != 14185]  # Preparation is a cooldown utility.
    assert builder_ids.index(53) < builder_ids.index(1752), (tree, builder_ids)
    if main_builder:
        assert builder_ids.index(main_builder) < builder_ids.index(53), (tree, builder_ids)
    assert "{id=53,gates={}}" in block, (tree, ids)
# Refreshed upstream conditions: three-tier conversion and known steady-state policy.
from lupa import LuaRuntime  # type: ignore[import-not-found]  # noqa: E402

runtime = LuaRuntime(unpack_returned_tuples=True)
runtime.execute("""
    function LibStub()
        return {RegisterForever = function(data, chains) classes = data end}
    end
""")
runtime.execute(data)
classes = runtime.globals().classes
ids_of = lambda entries: [entry["id"] for entry in entries.values()]
frost = classes.MAGE_F.frost
assert 120 in ids_of(frost.cleave), "Cone of Cold retains reviewed two-target coverage"
assert any(e["id"] == 120 and any(g["t"] == "near" and g["n"] == 10 for g in e["gates"].values())
           for e in frost.aoe.values()), "Frost point-blank AoE keeps its distance condition"
arms = classes.WARRIOR_F.arms
assert 78 in ids_of(arms.st) and 845 not in ids_of(arms.st), "Heroic Strike on one target"
assert 845 in ids_of(arms.aoe) and 78 not in ids_of(arms.aoe), "Cleave on multiple targets"
for tree, min_targets in ((classes.HUNTER_F.beast_mastery, 4),
                          (classes.HUNTER_F.marksmanship, 3)):
    assert 1510 not in ids_of(tree.st) and 1510 in ids_of(tree.aoe)
    volley = next(e for e in tree.aoe.values() if e["id"] == 1510)
    assert any(g["t"] == "targets" and g["n"] == min_targets
               for g in volley["gates"].values())
assert 10 in ids_of(frost.aoe)
blizzard = next(e for e in frost.aoe.values() if e["id"] == 10)
assert any(g["t"] == "targets" and g["n"] == 4 for g in blizzard["gates"].values())
enh = classes.SHAMAN_F.enhancement.st
assert ids_of(enh).index(408341) < ids_of(enh).index(403), "Fire Nova precedes combat Lightning Bolt"
assert any(e["id"] == 403 and e["gates"][1]["t"] == "stack" and e["gates"][1]["n"] == 5
           for e in enh.values()), "Combat Maelstrom requirement remains intact"
fire_nova = next(e for e in enh.values() if e["id"] == 408341)
assert any(g["t"] == "known" and g["id"] == 16246 for g in fire_nova["gates"].values())
assert any(g["t"] == "buff" and g["id"] == 16246 for g in fire_nova["gates"].values())
elemental_bolt = next(e for e in classes.SHAMAN_F.elemental.st.values() if e["id"] == 403)
assert len(elemental_bolt["gates"]) == 0, "Unconfirmed pacing must not mask the unconditional bolt filler"
for tree_name in ("discipline", "holy", "shadow"):
    tree = classes.PRIEST_F[tree_name]
    for context in ("st", "cleave", "aoe"):
        entries = tree[context]
        if entries is not None:
            ids = ids_of(entries)
            assert ids[-1] == 5019, (tree_name, context, ids)
for class_table, tree_names in (
        (classes.MAGE_F, ("arcane", "fire", "frost")),
        (classes.WARLOCK_F, ("affliction", "demonology", "destruction"))):
    for tree_name in tree_names:
        tree = class_table[tree_name]
        for context in ("st", "cleave", "aoe"):
            entries = tree[context]
            if entries is not None:
                ids = ids_of(entries)
                assert ids[-1] == 5019, (tree_name, context, ids)
print("ok")
