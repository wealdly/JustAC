#!/usr/bin/env python3
# The converter rules most likely to break silently. Run: python tools/test_forever_rotations.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_forever_rotations import Conv, TRUE, FALSE  # noqa: E402

c = lambda v: {"const": {"val": v}}
cmp = lambda op, lhs, n: {"cmp": {"op": op, "lhs": lhs, "rhs": c(n)}}
dot = lambda sid: {"dotIsActive": {"spellId": {"spellId": sid}}}
targets = {"numberTargets": {}}

conv = Conv({}, self_id=772)
# const on the left flips the comparison
assert conv.conv({"cmp": {"op": "OpLt", "lhs": c("40"), "rhs": {"currentRage": {}}}}) == \
    {"t": "power", "res": "rage", "op": ">", "n": 40.0}
# "not my own DoT" is the refresh gate; "not another class's debuff" holds solo
assert conv.conv({"not": {"val": dot(772)}}) == {"t": "dot", "id": 772}
other = Conv({}, self_id=772)
assert other.conv({"not": {"val": dot(11198)}}) == TRUE and not other.delegated
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
                       "rhs": {"spellCastTime": {"spellId": {"spellId": 348}}}}}) == {"t": "dot", "id": 348}
assert not d.delegated
b = Conv({}, self_id=5171)  # Slice and Dice about to drop = my own buff down
assert b.conv(cmp("OpLt", rem("auraRemainingTime", 5171), "3"))["neg"] is True and not b.delegated
assert Conv({}).conv({"frontOfTarget": {}}) == TRUE                       # solo: the mob faces you
assert Conv({}).conv({"not": {"val": {"frontOfTarget": {}}}}) == FALSE    # so never Shred from the list
k = Conv({603: [("603", "")]}, self_id=980)  # Bane of Agony unless Bane of Doom (a class spell)
assert k.conv({"not": {"val": dot(603)}}) == {"t": "known", "id": 603, "neg": True} and not k.delegated
assert Conv({}, self_id=7386).conv({"not": {"val": dot(11198)}}) == TRUE  # another class's debuff: solo
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
                  (1949, ('t="near"', 'pct=50', "w=true")),          # Hellfire
                  (2687, ('t="health"', "w=true"))]:                 # Bloodrage
    assert all(n in line(sid) for n in need), (sid, line(sid))
# Hunters open with Serpent Sting (its own conditions kept), cast with Auto Shot right behind it.
hunter = data[data.index('["HUNTER_F"] = {'):data.index('["MAGE_F"] = {')]
for tree in ("beast_mastery", "marksmanship", "survival"):
    block = hunter[hunter.index(tree + " = {"):]
    ids = [int(i) for i in re.findall(r"\{id=(\d+),", block)[:2]]
    assert ids == [1978, 75], (tree, ids)
# Backstab leads the front-facing builder; the game greys it out unless you are behind.
rogue = data[data.index('["ROGUE_F"] = {'):data.index('["SHAMAN_F"] = {')]
for tree, order in (("combat", [53, 1752]), ("subtlety", [53, 16511, 1752]),
                    ("assassination", [1310707, 53, 1752])):
    block = rogue[rogue.index(tree + " = {"):]
    block = block[:block.index("\n    },")]
    ids = [int(i) for i in re.findall(r"\{id=(\d+),", block)]
    assert ids[-len(order):] == order and "{id=53,gates={}}" in block, (tree, ids)
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
assert 120 not in ids_of(frost.cleave), "Cone of Cold is no longer a two-target lead"
assert any(e["id"] == 120 and any(g["t"] == "near" and g["n"] == 10 for g in e["gates"].values())
           for e in frost.aoe.values()), "Frost point-blank AoE keeps its distance condition"
prot = classes.WARRIOR_F.protection
assert 78 in ids_of(prot.st) and 845 not in ids_of(prot.st), "Heroic Strike on one target"
assert 845 in ids_of(prot.aoe) and 78 not in ids_of(prot.aoe), "Cleave on multiple targets"
for tree in ("marksmanship", "survival"):
    hunter_tree = classes.HUNTER_F[tree]
    assert 1510 not in ids_of(hunter_tree.st) and 1510 in ids_of(hunter_tree.aoe), tree
assert 1510 not in ids_of(classes.HUNTER_F.beast_mastery.st)
assert 1510 in ids_of(classes.HUNTER_F.beast_mastery.aoe)
assert 10 in ids_of(frost.aoe)
for tree, sid in ((classes.HUNTER_F.beast_mastery, 1510), (frost, 10)):
    entry = next(e for e in tree.aoe.values() if e["id"] == sid)
    assert any(g["t"] == "targets" and g["n"] == 4 for g in entry["gates"].values())
assert 407632 not in ids_of(classes.PALADIN_F.protection.st)
assert 407632 in ids_of(classes.PALADIN_F.protection.aoe), "Hammer remains AoE-only"
enh = classes.SHAMAN_F.enhancement.st
assert ids_of(enh).index(408341) < ids_of(enh).index(403), "Fire Nova precedes combat Lightning Bolt"
assert any(e["id"] == 403 and e["gates"][1]["t"] == "stack" and e["gates"][1]["n"] == 5
           for e in enh.values()), "Combat Maelstrom requirement remains intact"
fire_nova = next(e for e in enh.values() if e["id"] == 408341)
assert fire_nova["gates"][1]["t"] == "any"
assert fire_nova["gates"][1]["g"][1]["t"] == "targets"
assert fire_nova["gates"][1]["g"][2]["t"] == "unconfirmed"
elemental_bolt = next(e for e in classes.SHAMAN_F.elemental.st.values() if e["id"] == 403)
assert len(elemental_bolt["gates"]) == 0, "Unconfirmed pacing must not mask the unconditional bolt filler"
print("ok")
