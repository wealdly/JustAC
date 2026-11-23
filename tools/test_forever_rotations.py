#!/usr/bin/env python3
# The converter rules most likely to break silently. Run: python tools/test_forever_rotations.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_forever_rotations import Conv, TRUE, FALSE, UNK  # noqa: E402
from gen_forever_rotations import condition_coverage
from gen_forever_rotations import add_extras, generalize_entries, keeps_own_buff, tier_lists
from gen_forever_rotations import rank1
from gen_forever_rotations import DURATION
from gen_forever_rotations import direct_damage_estimates
import check_forever_apl as cfa

damage_estimates = direct_damage_estimates({
    585, 591, 589, 15407, 5019, 75, 133, 3044, 1752, 78, 19434, 2764, 3018, 14914,
})
assert set(damage_estimates) == {585, 591, 3044, 133, 14914, 589}, \
    "Channel, weapon/AP-scaled and repeat/manual weapon attacks stay outside direct cast estimates"
assert damage_estimates[589][11] == 1 and damage_estimates[589][12] == 3, \
    "an instant damage over time (Shadow Word: Pain) is priced for measured damage only, ticking every 3s"
assert damage_estimates[14914][11] == 0 and damage_estimates[14914][12] == 2, \
    "a spell with a hit is not flagged measure-only; its damage over time ticks every 2s"
assert len(damage_estimates[585]) == 6, "Plain direct hits carry no partial flag"
assert damage_estimates[133][6] == 1 and damage_estimates[14914][6] == 1, \
    "A hit followed by its own damage over time is priced but flagged partial"
for actual, expected in zip(damage_estimates[14914][7:], (20, 0, 0.25)):
    assert abs(actual - expected) < 0.000001, "Holy Fire: five 4-damage ticks with a 0.05 share each"
immolate = direct_damage_estimates({348, 172, 589, 980})
assert set(immolate) == {348, 172, 589}, \
    "Immolate is priced despite its script effect; a hitless damage over time too"
assert immolate[172][11] == 0 and immolate[589][11] == 1, \
    "a hitless damage over time with a cast time (Corruption) is an ordinary price; an instant one is measure-only"
for actual, expected in zip(immolate[172], (0, 0, 4, 9, 0, 6, 1, 40, 0, 0.8, 12)):
    assert abs(actual - expected) < 0.000001, "Corruption rank 1: no hit, four 10-damage ticks over 12 seconds"
flame_shock = direct_damage_estimates({8050})
assert 8050 in flame_shock and flame_shock[8050][6] == 1 and flame_shock[8050][10] == 12,     "Flame Shock is priced despite its dummy aura: a hit and a 12 second burn"
for actual, expected in zip(immolate[348], (8, 0.7, 1, 5, 0.2, 3, 1, 15, 0, 0.65, 15)):
    assert abs(actual - expected) < 0.000001, "Immolate rank 1: 8 hit, five 3-damage ticks, Fire school"
assert damage_estimates[591][0] > damage_estimates[585][0], "Exact ranks retain different damage"
for actual, expected in zip(damage_estimates[585], (15, 0.1, 1, 6, 0.429, 2)):
    assert abs(actual - expected) < 0.000001, "Smite rank-1 mean, growth, cap, coefficient and Holy school"

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
      "SHAMAN_F": [8042, 8056],                   # Custom-eligible Earth Shock, Frost Shock
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
        return {RegisterForever = function(data, chains, abilities, damage)
            classes, pushbackDamage = data, damage
        end}
    end
""")
runtime.execute(data)
classes = runtime.globals().classes
damage = runtime.globals().pushbackDamage
assert damage[8042] == 6 and damage[8056] == 6 and damage[2136] == 8
assert damage[120] is None and damage[8050] is None and damage[8921] is None, \
    "Ten-second cooldowns and DoTs are not pushback fillers"
ids_of = lambda entries: [entry["id"] for entry in entries.values()]


def gate_list(entry):
    gates = entry["gates"]
    return [gates[i] for i in range(1, len(gates) + 1)] if gates else []


def entry_of(entries, sid):
    return next(e for e in entries.values() if e["id"] == sid)


# Core rules (gen_forever_rotations.py CORE RULES), checked on the generated data.
rupture = entry_of(classes.ROGUE_F.subtlety.st, 1943)
assert any(g["t"] == "resource" and g["res"] == "combo_points" and g["op"] == ">=" and g["n"] == 4
           for g in gate_list(rupture)), "a damage-over-time finisher spends at least four points"
rip = entry_of(classes.DRUID_F.feral.st, 1079)
assert sum(1 for g in gate_list(rip) if g["t"] == "resource") == 1, "a source point gate is kept, not doubled"
for hunter_tree in ("beast_mastery", "marksmanship"):
    for context in ("st", "cleave", "aoe"):
        ids = ids_of(classes.HUNTER_F[hunter_tree][context])
        assert max(ids.index(s) for s in (75, 3044)) < min(ids.index(s) for s in (2973, 1495)), \
            (hunter_tree, context, "melee attacks trail ranged attacks in a ranged tree")
survival = ids_of(classes.HUNTER_F.survival.st)
assert survival.index(13795) < survival.index(2973) < survival.index(3044), \
    "Survival is a melee tree: launch order Immolation Trap, Raptor Strike, then the ranged shots"
for context in ("st", "cleave", "aoe"):
    ids = ids_of(classes.MAGE_F.frost[context])
    assert ids[0] != 11426 and ids[-2:] == [11426, 5019], (context, "absorb shield trails damage, wand last")
# Every tree is a damage list in its talent style: tank lists drop threat and mitigation.
for cls, tree, gone in (("WARRIOR_F", "protection", {2565, 71, 1160}),          # Shield Block, Defensive
                        ("PALADIN_F", "protection", {20925}),                   # Holy Shield;
                        ("DRUID_F", "feral_bear", {99})):                       # Holy Shield; Demo Roar
    for context in ("st", "cleave", "aoe"):
        ids = ids_of(classes[cls][tree][context]) if classes[cls][tree][context] else []
        assert not gone & set(ids), (cls, tree, context, "threat and mitigation leave tank lists")
prot = ids_of(classes.WARRIOR_F.protection.st)
assert 7386 in prot, "Protection keeps Sunder Armor on a single target"
prot_sunder = entry_of(classes.WARRIOR_F.protection.st, 7386)
assert any(g["t"] == "stack" and g["id"] == 7386 and g["tgt"] and g["op"] == "<" and g["n"] == 1
           for g in gate_list(prot_sunder)), "Protection applies Sunder once per target"
assert prot.index(7386) < prot.index(78), "Protection uses Sunder before its excess-rage spender"
assert prot.index(23922) < prot.index(7386) and prot.index(6572) < prot.index(7386), \
    "Sunder waits behind Shield Slam and Revenge"
def _rage_gate(entry):
    found = []
    def walk(gates):
        for g in gates:
            if g["t"] in ("any", "all"):
                walk(list(g["g"].values()))
            elif g["t"] == "power" and g["res"] == "rage" and g["op"] == ">=":
                found.append(g)
    walk(gate_list(entry))
    return found
assert [g["n"] for g in _rage_gate(entry_of(classes.WARRIOR_F.protection.st, 78))] == [30], \
    "Protection's Heroic Strike spends from 30 rage"
prot_pack = ids_of(classes.WARRIOR_F.protection.aoe)
assert 7386 not in prot_pack, "Sunder on one enemy of a pack costs more than it returns"
assert prot_pack.index(6343) < prot_pack.index(6572), "Thunder Clap leads against a pack"
assert prot_pack.index(845) < prot_pack.index(78), "Cleave spends spare rage against a pack"
assert [g["n"] for g in _rage_gate(entry_of(classes.WARRIOR_F.protection.aoe, 845))] == [30], \
    "Protection's Cleave spends from 30 rage"
for _context in ("st", "cleave"):
    _ids = ids_of(classes.WARRIOR_F.protection[_context])
    assert _ids.index(6572) < _ids.index(6343) < _ids.index(7386), \
        (_context, "Protection keeps the sim's Thunder Clap after Revenge (it deals damage)")
assert 6343 in ids_of(classes.WARRIOR_F.protection.aoe), "Thunder Clap stays a pack attack"
clap = entry_of(classes.WARRIOR_F.protection.aoe, 6343)
assert any(g["t"] == "targets" and g["op"] == ">=" and g["n"] == 3 for g in gate_list(clap)),     "a pack attack leads from three targets"
for tree in ("arms", "fury"):
    assert 6343 not in ids_of(classes.WARRIOR_F[tree].cleave), (tree, "two targets: no Thunder Clap lead")
    assert ids_of(classes.WARRIOR_F[tree].aoe)[1] == 6343, (tree, "three or more: Thunder Clap leads behind the shout")
assert 7386 in ids_of(classes.WARRIOR_F.arms.st), "damage trees keep the sims' Sunder Armor"
heroic = entry_of(classes.WARRIOR_F.protection.st, 78)
spenders = {g["id"] for g in gate_list(heroic) if g["t"] == "any"
            for sub in [dict(x) for x in g["g"].values()] if sub["t"] == "all"
            for g in [dict(y) for y in sub["g"].values()]}
assert heroic["w"] and spenders == {6572, 23922}, "Protection: Heroic Strike first until Revenge or Shield Slam"
# Hamstring repays its rage only as Arms' spare-rage press: Fury and Protection leave it out, and
# no tree keeps the dying-target finisher (2026-11-20 simulation).
for _tree in ("fury", "protection"):
    for _context in ("st", "cleave", "aoe"):
        assert 1715 not in ids_of(classes.WARRIOR_F[_tree][_context]), (_tree, _context, "no Hamstring")
members = [dict(g) for gate in gate_list(entry_of(classes.WARRIOR_F.arms.st, 1715))
           if gate["t"] == "any" for g in gate["g"].values()]
assert members and all(g["t"] == "known" for g in members), "Arms keeps only the spare-rage Hamstring rule"
fury_st = ids_of(classes.WARRIOR_F.fury.st)
assert fury_st.index(23881) < fury_st.index(7386) < fury_st.index(78), "Fury's Sunder follows its attacks on one target"
for _tree in ("arms", "fury"):
    _sunder = [g for g in gate_list(entry_of(classes.WARRIOR_F[_tree].aoe, 7386)) if g["t"] == "stack"]
    assert _sunder and all(g["once"] for g in _sunder), (_tree, "one Sunder per target on a pack")
    assert not any(g["once"] for g in gate_list(entry_of(classes.WARRIOR_F[_tree].st, 7386))), \
        (_tree, "a single target may still take the full stack")
fury_pack = ids_of(classes.WARRIOR_F.fury.aoe)
assert fury_pack.index(7386) < fury_pack.index(1680), "Fury's pack list keeps its Sunder placement"
# Arcane before Arcane Blast (a level 20 talent): Fireball fills, ahead of the wand.
arcane_ids = ids_of(classes.MAGE_F.arcane.st)
assert arcane_ids.index(400574) < arcane_ids.index(133) < arcane_ids.index(5019), \
    "Arcane: Arcane Blast, then Fireball, then the wand"
assert not gate_list(entry_of(classes.MAGE_F.arcane.st, 133)), "Arcane's Fireball fallback is unconditional"
assert 133 not in ids_of(classes.MAGE_F.frost.st), "the Fireball fallback is Arcane's only"
for context in ("st", "cleave", "aoe"):
    burn = entry_of(classes.WARLOCK_F.destruction[context], 17877)
    either = [g for g in gate_list(burn) if g["t"] == "any"]
    assert burn["w"] and len(either) == 1 and [dict(g) for g in either[0]["g"].values()] == [
        {"t": "execute", "op": "<", "pct": 20}, {"t": "known", "id": 426316}], \
        (context, "Shadowburn waits for a dying target unless Shadow and Flame is talented")

# Launch-guide adaptations (forever-guides/ "Launch rotation", read 2026-11-16).
arms = ids_of(classes.WARRIOR_F.arms.st)
assert arms.index(7384) < arms.index(12294) < arms.index(5308) < arms.index(1240193), \
    "Arms: Overpower > Mortal Strike > Execute > Slam"
for _context in ("st", "cleave", "aoe"):
    assert any(g["t"] == "cast" and g["id"] == 1240193 and g["op"] == "<" and g["n"] == 1.5
               for g in gate_list(entry_of(classes.WARRIOR_F.arms[_context], 1240193))), \
        (_context, "Arms keeps the sim's Slam cast-time condition (Improved Slam)")
assert arms.index(772) == arms.index(78) - 1, "Arms single target: Rend (while missing) just ahead of Heroic Strike"
prot = ids_of(classes.WARRIOR_F.protection.st)
assert prot.index(772) < prot.index(78), "Protection: Charge, Rend, then Heroic Strike (forever-guides)"
pack = ids_of(classes.WARRIOR_F.protection.aoe)
assert pack.index(6343) < pack.index(78), "Protection pack: Thunder Clap, then Heroic Strike"
ids = ids_of(classes.WARRIOR_F.arms.cleave)
assert 12292 in ids and ids.index(1240193) < ids.index(772), "Arms cleave: Sweeping Strikes; Rend after Slam"
assert 12292 in ids_of(classes.WARRIOR_F.arms.aoe), "Arms pack: Sweeping Strikes"
for context in ("st", "cleave"):
    ids = ids_of(classes.WARRIOR_F.fury[context])
    assert ids.index(1680) < ids.index(5308) < ids.index(23881) < ids.index(7384) < ids.index(772), \
        (context, "Fury: Whirlwind > Execute > Bloodthirst > Overpower > Rend")
for tree in ("arms", "fury", "protection"):
    assert 772 not in ids_of(classes.WARRIOR_F[tree].aoe), (tree, "three or more: Rend's rage stays for Thunder Clap")
# Utility debuffs (slows, roots, mitigation, healing) are the player's to manage.
for cls, tree, sid, why in (("WARRIOR_F", "arms", 1160, "Demoralizing Shout"),
                            ("WARRIOR_F", "fury", 1160, "Demoralizing Shout"),
                            ("WARRIOR_F", "protection", 1160, "Demoralizing Shout"),
                            ("MAGE_F", "frost", 122, "Frost Nova"),
                            ("PRIEST_F", "shadow", 15286, "Vampiric Embrace")):
    for context in ("st", "cleave", "aoe"):
        lines = classes[cls][tree][context]
        assert lines is None or sid not in ids_of(lines), (tree, context, why, "is utility")
for tree in ("assassination", "combat"):
    ids = ids_of(classes.ROGUE_F[tree].st)
    assert ids.index(703) < ids.index(1833), (tree, "Garrote opens ahead of Cheap Shot")
    ambush = entry_of(classes.ROGUE_F[tree].st, 8676)
    assert ids.index(8676) < ids.index(703) and [dict(g) for g in gate_list(ambush)] == [{"t": "stealth"}], \
        (tree, "Ambush opens from stealth ahead of Garrote")
    rupture = entry_of(classes.ROGUE_F[tree].st, 1943)
    assert ids.index(1943) < ids.index(2098) and {"t": "resource", "res": "combo_points", "op": ">=", "n": 5} \
        in [dict(g) for g in gate_list(rupture)], (tree, "Rupture at 5 points before Eviscerate")
shadow = ids_of(classes.PRIEST_F.shadow.st)
assert shadow.index(1309595) < shadow.index(15407), "Shadow Word: Death before Mind Flay"
for tree in ("discipline", "holy"):
    ids = ids_of(classes.PRIEST_F[tree].st)
    assert ids.index(589) < ids.index(8092) < ids.index(585), (tree, "Mind Blast after Shadow Word: Pain, before Smite")
assert ids_of(classes.WARLOCK_F.affliction.st)[-3:] == [1316697, 686, 5019], "Wrack fills before Shadow Bolt"
assert ids_of(classes.WARLOCK_F.destruction.st)[-3:] == [412758, 686, 5019], "Incinerate fills before Shadow Bolt"
fire = ids_of(classes.MAGE_F.fire.st)
assert fire.index(401502) + 1 == fire.index(133), "Frostfire Bolt fills before Fireball"
assert 120 in ids_of(classes.MAGE_F.fire.aoe), "Fire AoE uses Cone of Cold"
arcane_aoe = ids_of(classes.MAGE_F.arcane.aoe)
assert arcane_aoe.index(2120) < arcane_aoe.index(1449), "Arcane AoE opens with Flamestrike"
for cls, tree, context, sid, radius in (("PRIEST_F", "shadow", "aoe", 15237, 10),
                                        ("PALADIN_F", "retribution", "aoe", 26573, 8),
                                        ("WARRIOR_F", "arms", "aoe", 6343, 8),
                                        ("WARRIOR_F", "fury", "st", 1680, 8)):
    pbaoe = entry_of(classes[cls][tree][context], sid)
    assert pbaoe["w"] and {"t": "near", "n": radius} in [dict(g) for g in gate_list(pbaoe)], \
        (cls, tree, sid, "a point-blank attack waits for the target inside its radius")
assert not any(g["t"] == "near" for g in gate_list(entry_of(classes.MAGE_F.frost.st, 116))), \
    "a ranged spell keeps its range, not a radius"
assert not any(g["t"] == "near" for g in gate_list(entry_of(classes.WARLOCK_F.destruction.aoe, 5740))), \
    "a ground-targeted area (Rain of Fire) is not point-blank"
for tree in ("protection", "retribution"):
    wrath = entry_of(classes.PALADIN_F[tree].st, 24275)
    assert {"t": "execute", "op": "<", "pct": 20} in [dict(g) for g in gate_list(wrath)], \
        (tree, "Hammer of Wrath carries the game's below-20% restriction")
fury_aoe = ids_of(classes.WARRIOR_F.fury.aoe)
assert fury_aoe.count(1680) == 1 and fury_aoe.index(1680) < fury_aoe.index(7384), \
    "a derived gate does not change which Whirlwind branch the AoE tier keeps"
fire_aoe = ids_of(classes.MAGE_F.fire.aoe)
assert fire_aoe.index(2120) < fire_aoe.index(11113) < fire_aoe.index(1449) < fire_aoe.index(133), \
    "Fire AoE follows the guides: Flamestrike, Blast Wave, Arcane Explosion, then the filler"
assert 1449 in ids_of(classes.MAGE_F.arcane.aoe) and 1449 not in ids_of(classes.MAGE_F.arcane.st), \
    "Arcane Explosion joins only the Arcane AoE tier"
for context in ("st", "aoe"):
    ids = ids_of(classes.HUNTER_F.survival[context])
    assert ids[-1] == 3044 and max(ids.index(s) for s in (2973, 1495)) < ids.index(3044), \
        (context, "Survival keeps a ranged shot behind its melee attacks")
assert 2643 in ids_of(classes.HUNTER_F.survival.aoe) and 2643 not in ids_of(classes.HUNTER_F.survival.st)
for cls, tree, sid in (("WARRIOR_F", "arms", 402927), ("WARRIOR_F", "fury", 402927),
                       ("ROGUE_F", "combat", 14251), ("HUNTER_F", "survival", 19306)):
    reactive = entry_of(classes[cls][tree].st, sid)
    assert not gate_list(reactive), (cls, tree, sid, "a reactive attack is gated by the game's own usability")
assert ids_of(classes.WARRIOR_F.arms.st).index(402927) < ids_of(classes.WARRIOR_F.arms.st).index(12294), \
    "Victory Rush leads while it is lit"
assert 402927 not in ids_of(classes.WARRIOR_F.protection.st), "tank lists keep Victory Rush defensive"
def flat_gates(gates):
    for g in gates:
        yield g
        if g["t"] in ("any", "all"):
            yield from flat_gates([g["g"][i] for i in range(1, len(g["g"]) + 1)])


heroic = entry_of(classes.WARRIOR_F.arms.st, 78)
assert any(g["t"] == "power" and g["res"] == "rage" and g["n"] == 90 for g in flat_gates(gate_list(heroic))), \
    "an unreachable rage threshold reads as near the cap"
# Before a main rage spender is learned all rage is excess: Heroic Strike's rage condition
# also holds while none of Mortal Strike, Slam, Whirlwind, Bloodthirst is known (Arms, Fury).
SPENDERS = {12294, 1240193, 1680, 23881}
for tree in ("arms", "fury"):
    hs = entry_of(classes.WARRIOR_F[tree].st, 78)
    alt = [g for g in gate_list(hs) if g["t"] == "any"]
    assert len(alt) == 1, (tree, "one rage-or-unlearned group")
    members = [alt[0]["g"][i] for i in range(1, len(alt[0]["g"]) + 1)]
    assert members[0]["t"] == "power" and members[1]["t"] == "all", (tree, members)
    inner = [members[1]["g"][i] for i in range(1, len(members[1]["g"]) + 1)]
    assert {g["id"] for g in inner if g["t"] == "known" and g["neg"]} == SPENDERS, (tree, inner)
# ...and Arms' Hamstring waits until one of those spenders is learned (no spare rage before).
for tree in ("arms",):
    for ham in (e for e in classes.WARRIOR_F[tree].st.values() if e["id"] == 1715):
        need = [g for g in gate_list(ham) if g["t"] == "any"
                and any(g["g"][i]["t"] == "known" for i in range(1, len(g["g"]) + 1))]
        members = [need[0]["g"][i] for i in range(1, len(need[0]["g"]) + 1)] if need else []
        assert {g["id"] for g in members if g["t"] == "known"} == SPENDERS, (tree, gate_list(ham))
_arms = ids_of(classes.WARRIOR_F.arms.st)
assert _arms.index(78) < _arms.index(1715), "Arms: Heroic Strike ranks above Hamstring"
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
# The adjustment table's per-tree options, on synthetic entries: `at` retunes a threshold, `was`
# stops the build when the source no longer says what the row was written against, `drop`
# removes matching conditions (a group by a member), and none of them flags the entry.
import gen_forever_rotations as _gfr  # noqa: E402
_chains = {"probe": [(900001, 1)]}
_saved = _gfr.REGATE.get("testclass")
_gfr.REGATE["testclass"] = {"probe": dict(at={"a": {"combo_points": 2}}, was={"a": {"combo_points": 5}},
                                         drop={"b": [{"t": "power", "res": "energy", "op": ">="},
                                                     {"t": "all", "has": {"t": "known", "id": 7}}]})}
_points = {"t": "resource", "res": "combo_points", "op": ">=", "n": 5}
_floor = {"t": "power", "res": "energy", "op": ">=", "n": 60}
_branch = {"t": "all", "g": [{"t": "known", "id": 7}, {"t": "targets", "op": "<", "n": 3}]}
_other = {"t": "all", "g": [{"t": "known", "id": 8}]}
_entry = {"id": 900001, "gates": [dict(_points), dict(_floor), _branch, _other]}
_gfr.regate("testclass", "a", [_entry], _chains)
assert _entry["gates"][0]["n"] == 2 and len(_entry["gates"]) == 4 and "w" not in _entry, _entry
_entry = {"id": 900001, "gates": [dict(_points), dict(_floor), _branch, _other]}
_gfr.regate("testclass", "b", [_entry], _chains)
assert _entry["gates"] == [_points, _other] and "w" not in _entry, _entry
try:
    _gfr.regate("testclass", "a", [{"id": 900001, "gates": [dict(_points, n=3)]}], _chains)
    raise AssertionError("a source that moved must stop the build")
except SystemExit as moved:
    assert "revisit the row" in str(moved), moved
if _saved is None:
    del _gfr.REGATE["testclass"]
# Subtlety: Vanish is for groups only (alone it drops the fight), and carries no energy threshold.
_vanish = [dict(g) for g in gate_list(entry_of(classes.ROGUE_F.subtlety.st, 1856))]
assert {"t": "group"} in _vanish, "Vanish only in a group"
assert not any(g["t"] == "power" for g in _vanish), "Vanish saves no energy"
# Subtlety: no energy threshold on Hemorrhage or Eviscerate. Sinister Strike below them spends
# first, so a threshold above its cost is never reached and the entry is never offered.
for sid, why in ((16511, "Hemorrhage"), (2098, "Eviscerate")):
    gates = flat_gates(gate_list(entry_of(classes.ROGUE_F.subtlety.st, sid)))
    assert not any(g["t"] == "power" and g["res"] == "energy" for g in gates), (why, "saves no energy")
# Combat: Eviscerate from two combo points, as the source has it after our pin.
assert {"t": "resource", "res": "combo_points", "op": ">=", "n": 2} in \
    [dict(g) for g in gate_list(entry_of(classes.ROGUE_F.combat.st, 2098))], "Combat Eviscerate from 2 points"
# Arcane: recovering mana and spending Missile Barrage do not depend on a talent.
for sid, why in ((12051, "Evocation"), (5143, "Arcane Missiles")):
    gates = flat_gates(gate_list(entry_of(classes.MAGE_F.arcane.st, sid)))
    assert gates and not any(g["t"] == "known" for g in gates), (why, "needs no talent")
# Restoration shaman: Flame Shock is kept up ahead of Lightning Bolt.
resto = ids_of(classes.SHAMAN_F.restoration.st)
assert resto.index(8050) < resto.index(403), "Flame Shock before Lightning Bolt"
# Bear: Enrage starts the rage, only at low rage and above half health (it lowers armor).
enrage = entry_of(classes.DRUID_F.feral_bear.st, 5229)
assert enrage["w"] and {"t": "health", "op": ">", "pct": 50} in [dict(g) for g in gate_list(enrage)], "Enrage is gated on health"
assert any(g["t"] == "power" and g["res"] == "rage" and g["op"] == "<" for g in gate_list(enrage)), "Enrage only at low rage"
enh = classes.SHAMAN_F.enhancement.st
assert ids_of(enh).index(403) < ids_of(enh).index(408341), \
    "Single-target instant Bolt precedes Nova"
# Earth Shock stays an interrupt (utility role): Elemental and Restoration never list it, and
# Enhancement lists it as the filler shock that the runtime offers only against a quiet
# open-world target (tools/test_interrupt_filler.py).
for tree in ("elemental", "restoration"):
    for context in ("st", "cleave", "aoe"):
        entries = classes.SHAMAN_F[tree][context]
        if entries is not None:
            assert 8042 not in ids_of(entries), (tree, context)
for context in ("st", "cleave", "aoe"):
    ids = ids_of(classes.SHAMAN_F.enhancement[context])
    assert ids.index(8050) < ids.index(17364) < ids.index(403) < ids.index(8042), \
        (context, "Earth Shock fills after Flame Shock, Stormstrike and Lightning Bolt")
    # The shocks share a 6s cooldown. Earth Shock fills while Flame Shock has more than 4s
    # left: asking for the whole cooldown never held before the talent that shortens it.
    shock = gate_list(entry_of(classes.SHAMAN_F.enhancement[context], 8042))
    assert len(shock) == 1 and (shock[0]["t"], shock[0]["id"], shock[0]["op"], shock[0]["n"]) == \
        ("debuff", 8050, ">", 4), (context, "Earth Shock waits on Flame Shock's time left", shock)
assert ids_of(classes.SHAMAN_F.enhancement.aoe).index(408341) < \
    ids_of(classes.SHAMAN_F.enhancement.aoe).index(17364), "AoE Nova precedes Stormstrike"
assert any(e["id"] == 403 and e["gates"][1]["t"] == "stack" and e["gates"][1]["n"] == 5
           and e["gates"][1]["required"] for e in enh.values()), "Combat Maelstrom requires confirmed stacks"
for tree in ("frost",):
    blast = next(e for e in classes.MAGE_F[tree].st.values() if e["id"] == 2136)
    either = blast["gates"][1]
    assert either["t"] == "any" and [dict(g) for g in either["g"].values()] == [
        {"t": "execute", "op": "<", "pct": 20, "required": True}, {"t": "hit"}],         (tree, "Fire Blast: a dying target, or casts pushed back while being hit")
fire_nova = next(e for e in enh.values() if e["id"] == 408341)
assert list(g["t"] for g in fire_nova["gates"].values()) == ["totem"], \
    "Nova requires a fire totem, not the Clearcasting talent or buff"
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

# The shared (retail-keyed) interrupt and soothe tables never apply an id that is a different
# spell on Forever: each must be a real interrupt / cast-stopping CC (or enrage dispel) in the
# Forever data, or be retracted by the Forever defaults.
import re as _re
import gen_forever_defaults as _gfd
import gen_forever_rotations as _gen
_names = {r["ID"]: r["Name_lang"] for r in cfa.rows("SpellName")}
with open(os.path.join(root, "Data", "InterruptAbilities.lua"), encoding="utf-8") as _f:
    _shared = _f.read()
_split = _shared.index("RegisterSootheAbilities")
for _sid in {int(x) for x in _re.findall(r"\[(\d+)\]\s*=\s*\{\s*kind=", _shared[:_split])}:
    if str(_sid) not in _names:
        continue
    _real = any(e[0] == _gen.INTERRUPT for e in _gen.effects_of(_sid)) \
        or _gen.not_dps(_sid, True) == "cc" or _gen.spell_meta(_sid)[0] == 9  # silenced
    assert _real or _sid in _gfd.INTERRUPT_REMOVE, \
        (_sid, _names[str(_sid)], "a shared interrupt/CC id that is another spell on Forever must be removed")
for _sid in {int(x) for x in _re.findall(r"\[(\d+)\]\s*=\s*\{\s*reach=", _shared[_split:])}:
    if str(_sid) not in _names:
        continue
    _dispels = any(e[0] == 38 and e[4] == 9 for e in _gen.effects_of(_sid))  # dispel: enrage
    assert _dispels or _sid in _gfd.SOOTHE_REMOVE, (_sid, _names[str(_sid)], "not an enrage dispel on Forever")

# Gates can only be answered about ids the client has and, for "known", ids a character can
# learn (2026-11-18 generator audit).
from gen_forever_rotations import known_spell_id, SOURCE_ID_FIXES  # noqa: E402
_mage_chains, _mage_by_id = cfa.class_chains(cfa.CLASS_MASK["mage"])
_paladin_chains, _paladin_by_id = cfa.class_chains(cfa.CLASS_MASK["paladin"])
assert all(str(real) in _names and str(wrong) not in _names for wrong, real in SOURCE_ID_FIXES.items()), \
    "a source id fix maps an id the client lacks to one it has"
assert known_spell_id(400625, _mage_by_id) == 400624, "Heating Up: the proc aura asks about the talent"
assert known_spell_id(44404, _mage_by_id) == 400588, "Missile Barrage: the preset's id asks about the talent"
assert known_spell_id(1239700, _mage_by_id) == 400574, "Arcane Blast: any rank known, not one high rank"
assert known_spell_id(20423, _paladin_by_id) == rank1(_paladin_chains["seal_of_fury"]), "Seal of Fury: rank 1"
assert known_spell_id(16551, {}) == 16551, "an item proc with no talent of its name stays as it is"
assert known_spell_id(12536, _mage_by_id, True) == 11213, "Clearcasting available = Arcane Concentration known"
assert known_spell_id(22959, _mage_by_id, True) == 11095, "Fire Vulnerability available = Improved Scorch known"
assert known_spell_id(12536, _mage_by_id) == 12536, "a spell-known check is not rewritten to a talent"


def _all_gates(gates):
    for _g in gates or []:
        yield _g
        if _g["g"] is not None:
            yield from _all_gates(list(_g["g"].values()))


for _cls_key in classes.keys():
    for _tree in classes[_cls_key].keys():
        if _tree == "default":
            continue
        for _context in ("st", "cleave", "aoe"):
            _entries = classes[_cls_key][_tree][_context]
            if _entries is None:
                continue
            for _entry in _entries.values():
                for _g in _all_gates(gate_list(_entry)):
                    if _g["id"] and _g["t"] in ("buff", "debuff", "stack", "known", "cd"):
                        assert str(_g["id"]) in _names, (_cls_key, _tree, _context, _entry["id"], _g,
                                                         "a gate names an id the client does not have")
                    if _g["t"] in ("any", "all"):
                        _members = [repr(sorted(m.items(), key=str)) for m in _g["g"].values()]
                        assert len(set(_members)) == len(_members), (_cls_key, _tree, _entry["id"],
                                                                     "identical members in one group")
_missiles = [e for e in classes.MAGE_F.arcane.st.values() if e["id"] == 5143]
assert _missiles and all(any(g["t"] == "buff" and g["id"] == 400589 for g in gate_list(e)) for e in _missiles), \
    "Arcane Missiles waits on the client's Missile Barrage aura"
_claw = entry_of(classes.DRUID_F.feral.st, 1082)
assert not gate_list(_claw) and not _claw["delegated"], "Claw is the cat list's unconditional attack and may lead"

# A target carries one Bane from a warlock: Doom leads and Agony waits while it runs, in every tier.
for _tree in ("affliction", "demonology", "destruction"):
    for _context in ("st", "cleave", "aoe"):
        _entries = classes.WARLOCK_F[_tree][_context]
        if _entries is None:
            continue
        _order = [e["id"] for e in _entries.values()]
        assert _order.index(603) < _order.index(980), (_tree, _context, "Bane of Doom before Bane of Agony")
        assert any(g["t"] == "debuff" and g["id"] == 603 and g["neg"] for g in gate_list(entry_of(_entries, 980))), \
            (_tree, _context, "Bane of Agony must not replace a running Bane of Doom")
# A damage over time with no hit of its own always carries its keep-it-up condition.
for _entries, _sid in ((classes.WARLOCK_F.affliction.st, 603), (classes.HUNTER_F.survival.st, 1978),
                       (classes.PRIEST_F.shadow.st, 2944)):
    assert any(g["t"] == "debuff" and g["id"] == _sid and g["refresh"] for g in gate_list(entry_of(_entries, _sid))), \
        (_sid, "a pure damage over time needs its own refresh condition")

# Bear Maul spends at its cost until Lacerate or Primal Bite is learned, then banks 25 rage.
for _context in ("st", "aoe"):
    _maul = entry_of(classes.DRUID_F.feral_bear[_context], 6807)
    _alt = [g for g in gate_list(_maul) if g["t"] == "any"]
    assert _maul["w"] and len(_alt) == 1, (_context, "Maul: one rage-or-unlearned group")
    _members = [dict(_alt[0]["g"][i]) for i in range(1, len(_alt[0]["g"]) + 1)]
    assert _members[0]["t"] == "power" and _members[0]["n"] == 25, (_context, _members)
    _unknown = {dict(x)["id"] for x in dict(_members[1])["g"].values()}
    assert _unknown == {1328617, 407995}, (_context, "until Lacerate or Primal Bite is known", _unknown)
