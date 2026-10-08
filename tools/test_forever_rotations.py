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
assert t.conv(aoe_only) == TRUE
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
assert Conv({}, self_id=8075).conv(cmp("OpLe", {"totemRemainingTime": {"totemType": "Earth"}}, "0s"))["neg"] is True
pace = Conv({})   # mana paced against fight length: unknowable, so no pacing
assert pace.conv({"cmp": {"op": "OpGe", "lhs": {"currentMana": {}}, "rhs": {"math": {
    "op": "OpMul", "lhs": {"remainingTime": {}}, "rhs": {"const": {"val": "35"}}}}}}) == TRUE and not pace.delegated
# The shipped bar pool (Data/ForeverRotations.lua, last table): combat abilities in, utility out.
import re  # noqa: E402
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = open(os.path.join(root, "Data", "ForeverRotations.lua"), encoding="utf-8").read()
pool = {k: {int(i) for i in v.split(",")} for k, v in re.findall(r'\["(\w+_F)"\] = \{([\d,]+)\}', data)}
IN = {"HUNTER_F": [75, 6603, 1510, 13795],        # Auto Shot, Attack, Volley, Immolation Trap
      "WARRIOR_F": [12292, 2457],                 # Sweeping Strikes, Battle Stance
      "DRUID_F": [768, 5487, 16914],              # Cat Form, Bear Form, Hurricane
      "PRIEST_F": [15473, 20554]}                 # Shadowform, Berserking (offensive racial)
OUT = {"HUNTER_F": [1494, 5118, 6991, 5116],      # Track Beasts, Aspect of the Cheetah, Feed Pet, Concussive Shot
       "WARLOCK_F": [702, 5782],                  # Curse of Weakness, Fear: no damage, no DPS press
       "DRUID_F": [783, 1066],                    # Travel Form, Aquatic Form
       "MAGE_F": [587],                           # Conjure Food
       "SHAMAN_F": [2645],                        # Ghost Wolf
       # racials by role only: Escape Artist (defensive), Rapid Regeneration (no combat role)
       "WARRIOR_F": [20589, 1260270]}
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
print("ok")
