# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Run JustAC's WoW Forever priority lists through the Forever simulator at levelling levels.

Offline analysis only. It reads Data/Forever/Rotations.lua and writes nothing inside the
addon; it never changes a list, a generator or runtime Lua.

What it does
  1. Converts one generated list (class, tree, context) into the simulator's priority-list
     JSON (proto/apl.proto), gate by gate, and prints which gates converted exactly, which
     were approximated and which could not be expressed. Nothing is dropped silently.
  2. Builds a levelling character (level, talents, weapon) and a set of targets sized by
     health, so short fights are represented.
  3. Runs every list ("arm") on every scenario with the same seeds and prints kill time
     and damage per second with 95% confidence intervals, plus casts per fight per ability.

What it needs (none of it is vendored here)
  - A checkout of the WoW Forever simulator (MIT, https://github.com/gunba/wow-forever-sim)
    with its protocol code generated, and its command-line tool built:
        protoc "--proto_path=proto" "--go_out=sim/core" proto/*.proto
        go build -tags=with_db -o <dir>/wowsimcli.exe ./cmd/wowsimcli
  - Python 3.9+, standard library only.

Run
    python tools/forever_sim_bench.py --sim <simulator checkout> --cli <wowsimcli.exe>
    python tools/forever_sim_bench.py --sim ... --cli ... --class warrior --tree arms \
        --levels 20,40 --gear behind,average,lucky --batches 10 --iterations 1000 --out <result.md> --keep <dir for requests/results>
    python tools/forever_sim_bench.py --sim ... --convert-only      (print the conversion)

Arms compared
  justac    the generated list for --tree / --context, converted
  sim       the simulator's own preset for the tree (ui/<class>/apls/<file>)
  source    the vendored MythicSim preset the generated list was adapted from
            (tools/forever-apl-src/presets/...), when the simulator can parse it
  justac-without-<ids>   optional (--without): the generated list minus some entries
All arms run without pre-pull actions: a levelling pull has no countdown.

Assumptions (each is a modelling choice, not a measured fact; see ASSUMPTIONS below and the
printed report)
  - Character: the simulator's base stats and trained ranks for the level. Talents are the
    simulator's own preset build for the tree, cut down to the points the level has, in row
    order, taking the tree's last talent as soon as its row opens.
  - Gear: a named setup chosen with --gear (bare, behind, average, lucky, or file:<path>
    for an explicit character). Generated setups pick real client items by required level,
    quality and slot, taking the MEDIAN candidate by a simple stat score, never the best.
    The rules and the gaps are written next to GEAR_SETUPS and ItemPool below, and every
    report lists the items a setup resolved to.
  - Targets: health, armour and melee damage of the client's expected creature for the
    target level (ExpectedStat, as shipped in the simulator). "Elite" multiplies health and
    damage by stated factors that are NOT measured.
  - The simulator's combat tables are Classic's and its Forever rules are partly
    provisional. Use the output to compare two orderings under the same assumptions, never
    as absolute damage numbers.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROTATIONS = os.path.join(ROOT, "Data", "Forever", "Rotations.lua")
PRESETS = os.path.join(ROOT, "tools", "forever-apl-src", "presets")
SPELL_QUEUE = os.path.join(ROOT, "SpellQueue.lua")

# ---------------------------------------------------------------------------------------
# Per-class knowledge. Everything class-specific lives here; the rest is generic.
#   spec        the Player oneof field and its options
#   race        a race whose Forever racials are passive in the simulator, so a preset's
#               "use other cooldowns" line cannot give one arm a racial the list lacks
#   trees       tree -> simulator preset (relative to the simulator checkout), the vendored
#               source preset (relative to tools/forever-apl-src/presets), the simulator's
#               talent string for the tree, and which tree index the build fills first
#   class_id    ChrClasses id, for the client's AllowableClass mask
#   weapon, armor, stat_weights   what the gear setups may pick (see ItemPool)
#   engagement  how the class meets a solo target. melee: in front, hit from the start.
#               Ranged and kiting classes need other profiles (see ENGAGEMENTS).
#   actions     overrides for list ids the automatic match cannot settle:
#               JustAC rank-1 id -> {"id": simulator action id, "tag": n, "dot": bool}
#               or None with a reason in `unmodelled`.
#   unmodelled  JustAC rank-1 id -> why the simulator cannot cast it
# ---------------------------------------------------------------------------------------
CLASSES = {
    "warrior": {
        "proto_class": "ClassWarrior",
        "spec": ("warrior", {"options": {"stance": "WarriorStanceBattle"}}),
        "race": "RaceHuman",   # Forever human: passive racials only in the simulator
        "engagement": "melee",
        "class_id": 1,
        # Client item class 2 (weapon): inventory type 17 two-hand; subclasses axe, mace, polearm, sword.
        "weapon": {"inv": (17,), "subclasses": (1, 5, 6, 8)},
        # Armour subclasses worn while levelling: leather and mail, plate from level 40.
        "armor": lambda level: (2, 3, 4) if level >= 40 else (2, 3),
        # Only used to order candidates so the MEDIAN one can be taken (strength, agility,
        # stamina, attack power by simulator stat index). Not a best-in-slot search.
        "stat_weights": {0: 1.0, 1: 0.6, 2: 0.2, 17: 0.5},
        # The random suffix ASSUMED on an uncommon armour piece that has no stats of its own
        # (simulator stat indexes: strength and stamina). Which suffixes an item can really
        # roll is in client tables this project does not have.
        "suffix": {"name": "of the Bear", "stats": (0, 2)},
        "trees": {
            "arms": {"sim_preset": "ui/warrior/apls/forever_arms.apl.json",
                     "source_preset": "warrior/dps/arms.apl.json",
                     "talents": "20305213132515201-3505-2", "main_tree": 0},
            "fury": {"sim_preset": "ui/warrior/apls/forever_fury_2h.apl.json",
                     "source_preset": "warrior/dps/dps_reck.apl.json",
                     "talents": "20305203032-45050020152010501", "main_tree": 1},
            # The damage order of a Protection-talented warrior. Run in Battle Stance like the
            # others: the generated list never changes stance, and an export does not say
            # which stance the player keeps.
            "protection": {"sim_preset": "ui/tank_warrior/apls/forever_protection.apl.json",
                           "source_preset": "warrior/protection/protection.apl.json",
                           "talents": "35-0501-251333120230021351", "main_tree": 2},
        },
        "actions": {
            78: {"id": 11567, "tag": 1},     # Heroic Strike: the queue action, not the swing
            845: {"id": 20569, "tag": 1},    # Cleave: likewise
            772: {"id": 11574, "dot": True},  # Rend
            6572: {"id": 11601},             # Revenge (rank 6 is a raid book rank)
            23922: {"id": 23925},            # Shield Slam (the simulator names its top rank)
            6673: {"id": 11551},             # Battle Shout (rank 7 is a raid book rank)
        },
        "unmodelled": {
            402927: "Victory Rush is not implemented in the simulator",
            1329555: "Reckless Swings is not implemented in the simulator",
            1259813: "Eureka! (racial) is not implemented in the simulator",
            20572: "Blood Fury is a racial of a race this character is not",
        },
    },
    "warlock": {
        "proto_class": "ClassWarlock",
        # No demon by default: the simulator only has demon stats for owner levels 25, 40, 50
        # and 60, and at any other level the demon has none and never acts. --pet names one for
        # those levels. No armour spell and no weapon stone: the same for every arm.
        "spec": ("warlock", {"options": {"summon": "NoSummon"}}),
        "race": "RaceHuman",
        "engagement": "caster",
        "class_id": 9,
        # Client item class 2: two-hand staff (subclass 10).
        "weapon": {"inv": (17,), "subclasses": (10,)},
        # A wand in the ranged slot. Needs a simulator build with the local wand attack
        # (sim/core/wand.go, not upstream); without it the wand is only a stat stick.
        "wand": True,
        "armor": lambda level: (1,),
        # Intellect, stamina, spirit, spell power (simulator stat indexes), for the median pick.
        "stat_weights": {3: 1.0, 2: 0.6, 4: 0.4, 5: 1.0, 11: 1.0, 7: 0.5},
        "suffix": {"name": "of the Eagle", "stats": (2, 3)},
        "trees": {
            "affliction": {"sim_preset": "ui/warlock/apls/forever_affliction.apl.json",
                           "source_preset": "warlock/dps/affliction.apl.json",
                           "talents": "2550002003520015--0550305003", "main_tree": 0},
            "demonology": {"sim_preset": "ui/warlock/apls/forever_pact.apl.json",
                           "source_preset": "warlock/dps/demonic_pact.apl.json",
                           "talents": "011-0005003231220301351-0550005003", "main_tree": 1},
            "destruction": {"sim_preset": "ui/warlock/apls/forever_shadow_and_flame.apl.json",
                            "source_preset": "warlock/dps/destruction_conflag.apl.json",
                            "talents": "25500000035--055030510310035", "main_tree": 2},
        },
        "actions": {},
        "unmodelled": {
            5019: "Shoot is not a cast here: with a wand equipped the local wand attack fires by itself whenever "
                  "the character is neither casting nor in a global cooldown",
            1259813: "Eureka! (racial) is not implemented in the simulator",
            1259821: "Eureka! (racial) is not implemented in the simulator",
            20572: "Blood Fury is a racial of a race this character is not",
        },
    },
}

# How a class meets a solo target. The simulator has no movement or kiting model for
# targets, so a profile is only: how far the character stands, and whether the target's
# hits land on the character (which pushes casts back) from the first second.
#   distance   yards from the target (None: melee range). A "near" gate is tested against it.
#   target_attacks_player   False: the target's swing does no damage and is only the clock
#                           kill time is measured with.
ENGAGEMENTS = {
    "melee": {"in_front": True, "target_attacks_player": True, "distance": None,
              "note": "stands in front of the target and is hit from the first second"},
    "caster": {"in_front": True, "target_attacks_player": True, "distance": 20,
               "note": "casts from 20 yards; the target is on the character from the first second (no approach "
                       "time, the pessimistic end) and every hit that lands can push a cast back"},
    "caster_free": {"in_front": True, "target_attacks_player": False, "distance": 20,
                    "note": "casts from 20 yards and is never hit (a pet holds the target, or it is feared): "
                            "no pushback, the optimistic end"},
}

ASSUMPTIONS = {
    # Not measured. Classic dungeon elites are commonly described as about three times the
    # health of a normal creature of the level; damage factor chosen for illustration.
    "elite_health_mult": 3.0,
    "elite_damage_mult": 1.5,
    # Conversion from expected auto-attack damage per second to the simulator's target
    # swing, copied from the simulator's own planner benchmark (sim/planner/bench.go).
    "target_swing_speed": 2.0,
    "target_damage_spread": 0.3333,
}

OPS = {"<": "OpLt", "<=": "OpLe", ">": "OpGt", ">=": "OpGe", "=": "OpEq", "!=": "OpNe"}


# ---------------------------------------------------------------------------------------
# Reading the generated Lua (a small literal-table reader; the file is machine-written)
# ---------------------------------------------------------------------------------------
class LuaReader:
    TOKEN = re.compile(r"""\s*(?:--[^\n]*\n\s*)*(\{|\}|\[|\]|=|,|"(?:[^"\\]|\\.)*"|-?\d+\.?\d*(?:e-?\d+)?|[A-Za-z_]\w*)""")

    def __init__(self, text):
        self.text, self.pos = text, 0

    def peek(self):
        m = self.TOKEN.match(self.text, self.pos)
        return m.group(1) if m else None

    def take(self, want=None):
        m = self.TOKEN.match(self.text, self.pos)
        if not m or (want and m.group(1) != want):
            raise ValueError("Lua parse error near offset %d: wanted %r" % (self.pos, want))
        self.pos = m.end()
        return m.group(1)

    def value(self):
        tok = self.take()
        if tok == "{":
            return self.table()
        if tok.startswith('"'):
            return json.loads(tok)
        if tok in ("true", "false"):
            return tok == "true"
        if re.fullmatch(r"-?\d+", tok):
            return int(tok)
        return float(tok)

    def table(self):
        arr, obj = [], {}
        while True:
            tok = self.peek()
            if tok == "}":
                self.take()
                break
            if tok == "[":
                self.take()
                key = self.value()
                self.take("]")
                self.take("=")
                obj[key] = self.value()
            elif re.fullmatch(r"[A-Za-z_]\w*", tok) and tok not in ("true", "false"):
                save = self.pos
                self.take()
                if self.peek() == "=":
                    self.take()
                    obj[tok] = self.value()
                else:
                    self.pos = save
                    arr.append(self.value())
            else:
                arr.append(self.value())
            if self.peek() == ",":
                self.take()
        if obj and arr:
            obj["_list"] = arr
            return obj
        return obj if obj else arr


def load_rotations():
    text = open(ROTATIONS, encoding="utf-8").read()
    start = text.index("RotationImport.RegisterForever(") + len("RotationImport.RegisterForever(")
    reader = LuaReader(text)
    reader.pos = start
    classes = reader.value()
    reader.take(",")
    chains = reader.value()
    names = dict((int(i), n) for i, n in re.findall(r"\{id=(\d+),.*?\},?\s*-- ([^\n]+)", text))
    return classes, chains, names


def dot_floor_pct():
    """The runtime's rule: no new damage over time on a non-boss target below this health."""
    m = re.search(r"local DOT_MIN_TARGET_PCT = (\d+)", open(SPELL_QUEUE, encoding="utf-8").read())
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------------------------------
# Matching JustAC ids to simulator action ids
# ---------------------------------------------------------------------------------------
def walk(node, fn):
    if isinstance(node, dict):
        fn(node)
        for v in node.values():
            walk(v, fn)
    elif isinstance(node, list):
        for v in node:
            walk(v, fn)


def harvest_sim_ids(sim, cls):
    """Action ids the simulator's own presets for the class use: id -> {"tag", "dot"}."""
    found = {}
    folder = os.path.join(sim, "ui", cls, "apls")
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if not name.endswith(".apl.json"):
            continue
        data = json.load(open(os.path.join(folder, name), encoding="utf-8"))

        def visit(node):
            for key, val in node.items():
                if not isinstance(val, dict):
                    continue
                ref = val.get("spellId") or val.get("auraId")
                if isinstance(ref, dict) and "spellId" in ref:
                    rec = found.setdefault(ref["spellId"], {"tag": 0, "dot": False})
                    if key in ("castSpell", "channelSpell") and ref.get("tag"):
                        rec["tag"] = ref["tag"]
                    if key in ("dotIsActive", "dotRemainingTime", "multidot"):
                        rec["dot"] = True
        walk(data, visit)
    return found


def source_literals(sim, cls):
    """Every integer literal in the simulator's Go source for the class and its core."""
    out = set()
    for folder in (os.path.join(sim, "sim", cls), os.path.join(sim, "sim", "core")):
        for base, _, files in os.walk(folder):
            for name in files:
                if name.endswith(".go") and not name.endswith("_test.go"):
                    text = open(os.path.join(base, name), encoding="utf-8", errors="replace").read()
                    out.update(int(n) for n in re.findall(r"\b\d{2,7}\b", text))
    return out


def rank_tables(sim, cls):
    """Rank families the simulator registers one spell per rank for: [(ids, required levels)].

    Some classes (warlock) give every rank its own action id and register only the ranks the
    level has, so a list that names the top rank casts nothing on a low character. The
    families are read from the class's Go source, where each is a pair of literal arrays
    indexed by rank (spellId := [...]int32{0, ...}[rank] and level := [...]int{0, ...}[rank])."""
    out = []
    folder = os.path.join(sim, "sim", cls)
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if not name.endswith(".go") or name.endswith("_test.go"):
            continue
        body = open(os.path.join(folder, name), encoding="utf-8", errors="replace").read()
        found = [(m.start(), m.group(1).lower() == "level", [int(n) for n in re.findall(r"\d+", m.group(2))])
                 for m in re.finditer(r"(?i)\b(\w*spellid|level)\s*:?=\s*\[[^\]]*\]int(?:32)?\{([^}]*)\}", body)]
        for (_, is_level, ids), (_, next_is_level, levels) in zip(found, found[1:]):
            if not is_level and next_is_level and len(ids) == len(levels) and len(ids) > 1:
                out.append((ids[1:], levels[1:]))
    return out


def ranks_for_level(rotation, tables, level):
    """A copy of the rotation in which every id of a rank family is the highest rank the
    level has (rank 1 when it has none: the spell is then not registered and never cast)."""
    best = {}
    for ids, levels in tables:
        have = [i for i, need in zip(ids, levels) if need <= level]
        for i in ids:
            best[i] = have[-1] if have else ids[0]
    if not best:
        return rotation
    rotation = json.loads(json.dumps(rotation))

    def visit(node):
        if isinstance(node.get("spellId"), int) and node["spellId"] in best:
            node["spellId"] = best[node["spellId"]]
    walk(rotation, visit)
    return rotation


class IdMap:
    def __init__(self, sim, cls, chains):
        self.cfg = CLASSES[cls]
        self.chains = chains
        self.harvest = harvest_sim_ids(sim, cls)
        self.literals = source_literals(sim, cls)
        self.tables = rank_tables(sim, cls)
        self.notes = {}   # justac id -> how it was matched

    def action(self, jid):
        """Simulator action for a JustAC rank-1 id: dict(id, tag, dot) or None."""
        if jid in self.cfg["unmodelled"]:
            self.notes[jid] = "unmodelled: " + self.cfg["unmodelled"][jid]
            return None
        if jid in self.cfg["actions"]:
            rec = dict({"tag": 0, "dot": False}, **self.cfg["actions"][jid])
            ok = rec["id"] in self.literals
            self.notes[jid] = "class table -> %d%s" % (rec["id"], "" if ok else " (NOT FOUND in simulator source)")
            return rec
        chain = self.chains.get(jid) or [jid]
        for ids, _ in self.tables:
            if set(ids) & set(chain):
                self.notes[jid] = "simulator rank family %d..%d: the rank is chosen per level" % (ids[0], ids[-1])
                return {"id": ids[-1], "tag": 0, "dot": any(self.harvest.get(i, {}).get("dot") for i in ids)}
        hits = [c for c in chain if c in self.harvest]
        if len(hits) == 1:
            self.notes[jid] = "simulator preset id %d (same rank chain)" % hits[0]
            return dict(self.harvest[hits[0]], id=hits[0])
        if not hits:
            hits = [c for c in chain if c in self.literals]
            if len(hits) == 1:
                self.notes[jid] = "simulator source literal %d (same rank chain)" % hits[0]
                return {"id": hits[0], "tag": 0, "dot": False}
        self.notes[jid] = "no unique match in the rank chain (%s)" % (hits or "none")
        return None

    def aura(self, jid):
        """Aura id for a buff / debuff gate. Falls back to the id itself, and says so."""
        rec = self.action(jid) if (jid in self.chains or jid in self.cfg["actions"]) else None
        if rec:
            return rec["id"], rec.get("dot", False), None
        if jid in self.literals or jid in self.harvest:
            return jid, False, None
        return jid, False, "aura %d is not referenced anywhere in the simulator: reads as never active" % jid


# ---------------------------------------------------------------------------------------
# Gate -> simulator condition
# ---------------------------------------------------------------------------------------
EXACT, APPROX, LOST = "exact", "approximated", "not expressible"


class Converter:
    def __init__(self, idmap, names, engagement, dot_floor):
        self.ids, self.names = idmap, names
        self.engagement, self.engagement_name = ENGAGEMENTS[engagement], engagement
        self.dot_floor = dot_floor
        self.report = []   # (line label, status, text)
        self.line = ""

    def note(self, status, text):
        self.report.append((self.line, status, text))

    @staticmethod
    def const(value):
        return {"const": {"val": value}}

    @staticmethod
    def cmp(lhs, op, n):
        return {"cmp": {"op": OPS[op], "lhs": lhs, "rhs": {"const": {"val": ("%g" % n)}}}}

    @staticmethod
    def neg(value, negate):
        return {"not": {"val": value}} if negate else value

    def spell_ref(self, jid, what):
        rec = self.ids.action(jid)
        if rec is None:
            self.note(APPROX, "%s names spell %d, which the simulator does not have: read as unknown / never ready (%s)"
                      % (what, jid, self.ids.notes.get(jid, "")))
            return {"spellId": jid}
        ref = {"spellId": rec["id"]}
        if rec.get("tag"):
            ref["tag"] = rec["tag"]
        return ref

    def health_fraction(self, op, pct):
        # Fight sized by health, one target: remaining fraction of the fight IS the health fraction.
        return {"cmp": {"op": OPS[op], "lhs": {"remainingTimePercent": {}}, "rhs": {"const": {"val": "%g" % (pct / 100.0)}}}}

    def gate(self, g):
        t = g.get("t")
        if t in ("any", "all"):
            vals = [self.gate(m) for m in g.get("g", [])]
            return {"or" if t == "any" else "and": {"vals": vals}}
        if t == "buff":
            aid, _, warn = self.ids.aura(g["id"])
            if warn:
                self.note(APPROX, "buff gate: " + warn)
            else:
                self.note(EXACT, "buff %d -> aura %d active on the player%s" % (g["id"], aid, " (negated)" if g.get("neg") else ""))
            return self.neg({"auraIsActive": {"auraId": {"spellId": aid}}}, g.get("neg"))
        if t in ("debuff", "dot"):
            aid, is_dot, warn = self.ids.aura(g["id"])
            if warn:
                self.note(APPROX, "debuff gate: " + warn)
            if g.get("op"):
                if g.get("ncast"):
                    rhs = {"spellCastTime": {"spellId": self.spell_ref(g["ncast"], "debuff gate cast time")}}
                else:
                    rhs = {"const": {"val": "%gs" % g.get("n", 0)}}
                self.note(EXACT, "time left on %d %s %s" % (aid, g["op"], g.get("ncast") and "its cast time" or g.get("n")))
                return {"cmp": {"op": OPS[g["op"]], "lhs": {"dotRemainingTime": {"spellId": {"spellId": aid}}}, "rhs": rhs}}
            if is_dot:
                active = {"dotIsActive": {"spellId": {"spellId": aid}}}
            else:
                active = {"auraIsActive": {"auraId": {"spellId": aid}, "sourceUnit": {"type": "CurrentTarget"}}}
            want_absent = bool(g.get("neg")) or t == "dot"
            value = self.neg(active, want_absent)
            if t == "dot" or g.get("refresh"):
                if self.dot_floor:
                    self.note(EXACT, "apply %d when it is not on the target, and (runtime rule, non-boss target) only at or above %d%% health"
                              % (aid, self.dot_floor))
                    value = {"and": {"vals": [value, self.health_fraction(">=", self.dot_floor)]}}
                else:
                    self.note(EXACT, "apply %d when it is not on the target" % aid)
            else:
                self.note(EXACT, "debuff %d %s on the target" % (aid, "absent" if want_absent else "present"))
            return value
        if t == "stack":
            aid, _, warn = self.ids.aura(g["id"])
            if warn:
                self.note(APPROX, "stack gate: " + warn)
            val = {"auraNumStacks": {"auraId": {"spellId": aid}}}
            if g.get("tgt"):
                val["auraNumStacks"]["sourceUnit"] = {"type": "CurrentTarget"}
            self.note(EXACT, "stacks of %d %s %s on the %s" % (aid, g["op"], g["n"], "target" if g.get("tgt") else "player"))
            return self.cmp(val, g["op"], g["n"])
        if t == "execute":
            if g["op"] == "<" and g["pct"] in (20, 25, 35):
                self.note(EXACT, "target below %d%% health" % g["pct"])
                return {"isExecutePhase": {"threshold": "E%d" % g["pct"]}}
            self.note(EXACT, "target health %s %s%%" % (g["op"], g["pct"]))
            return self.health_fraction(g["op"], g["pct"])
        if t == "health":
            self.note(APPROX, "player health %s %s%%: the simulated player takes the target's hits and is never healed"
                      % (g["op"], g["pct"]))
            return self.cmp({"currentHealthPercent": {"sourceUnit": {"type": "Self"}}}, g["op"], g["pct"] / 100.0)
        if t == "power":
            res = g.get("res")
            if res == "mana" and g.get("ispct"):
                self.note(EXACT, "mana %s %s%%" % (g["op"], g["n"]))
                return self.cmp({"currentManaPercent": {}}, g["op"], g["n"] / 100.0)
            name = {"rage": "currentRage", "energy": "currentEnergy", "mana": "currentMana"}.get(res)
            if name:
                self.note(EXACT, "%s %s %s" % (res, g["op"], g["n"]))
                return self.cmp({name: {}}, g["op"], g["n"])
        if t == "resource" and g.get("res") == "combo_points":
            self.note(EXACT, "combo points %s %s" % (g["op"], g["n"]))
            return self.cmp({"currentComboPoints": {}}, g["op"], g["n"])
        if t == "cd":
            self.note(EXACT, "spell %d %s" % (g["id"], "on cooldown or not learned" if g.get("neg") else "ready"))
            return self.neg({"spellIsReady": {"spellId": self.spell_ref(g["id"], "cooldown gate")}}, g.get("neg"))
        if t == "known":
            self.note(EXACT, "spell %d %s" % (g["id"], "not known" if g.get("neg") else "known"))
            return self.neg({"spellIsKnown": {"spellId": self.spell_ref(g["id"], "known gate")}}, g.get("neg"))
        if t == "targets":
            self.note(EXACT, "engaged enemies %s %s" % (g["op"], g["n"]))
            return self.cmp({"numberTargets": {}}, g["op"], g["n"])
        if t == "cast":
            self.note(EXACT, "cast time of %d %s %s s" % (g["id"], g["op"], g["n"]))
            return {"cmp": {"op": OPS[g["op"]], "lhs": {"spellCastTime": {"spellId": self.spell_ref(g["id"], "cast gate")}},
                            "rhs": {"const": {"val": "%gs" % g["n"]}}}}
        if t == "swing":
            self.note(EXACT, "next %s swing %s %s s" % ("ranged" if g.get("ranged") else "melee", g["op"], g["n"]))
            return {"cmp": {"op": OPS[g["op"]], "lhs": {"autoTimeToNext": {"autoType": "Ranged" if g.get("ranged") else "MainHand"}},
                            "rhs": {"const": {"val": "%gs" % g["n"]}}}}
        if t == "near":
            distance = self.engagement.get("distance")
            near = distance is None or distance <= (g.get("n") or 0)
            self.note(APPROX, "target within %s yards: constant %s (the character stands %s)"
                      % (g.get("n"), str(near).lower(), "in melee range" if distance is None else "%g yards away" % distance))
            return self.const("true" if near else "false")
        if t == "hit":
            hit = self.engagement["target_attacks_player"]
            self.note(APPROX, "being hit: constant %s for the %s engagement" % (str(hit).lower(), self.engagement_name))
            return self.const("true" if hit else "false")
        if t == "unconfirmed":
            self.note(EXACT, "unconfirmed gate: false, as at runtime")
            return self.const("false")
        if t == "starved":
            self.note(APPROX, "mana-starved gate: read as false (the runtime derives it from what is affordable; no simulator value matches)")
            return self.const("false")
        # stealth, totem, prev, tick and anything new
        self.note(LOST, "gate %s cannot be expressed: read as holding, the way the runtime treats an unreadable gate"
                  % json.dumps(g, separators=(",", ":")))
        return self.const("true")

    def convert(self, entries):
        """List entries -> simulator priorityList. Every entry and gate is reported."""
        out = []
        for i, e in enumerate(entries, 1):
            jid = e["id"]
            self.line = "%2d %s (%d)" % (i, self.names.get(jid, "?"), jid)
            rec = self.ids.action(jid)
            if rec is None:
                self.note(LOST, "LINE OMITTED: " + self.ids.notes.get(jid, "no simulator action"))
                continue
            ref = {"spellId": rec["id"]}
            if rec.get("tag"):
                ref["tag"] = rec["tag"]
            self.note(EXACT, "cast -> simulator action %d%s [%s]" % (rec["id"], " tag %d" % rec["tag"] if rec.get("tag") else "",
                                                                     self.ids.notes.get(jid, "")))
            if e.get("delegated"):
                self.note(APPROX, "delegated entry: its source condition was given up at generation, so it is cast whenever "
                                  "ready at this position")
            gates = e.get("gates") or []
            action = {"castSpell": {"spellId": ref}}
            conds = [self.gate(g) for g in gates]
            if len(conds) == 1:
                action["condition"] = conds[0]
            elif conds:
                action["condition"] = {"and": {"vals": conds}}
            out.append({"action": action})
        return {"type": "TypeAPL", "priorityList": out}


# ---------------------------------------------------------------------------------------
# Character, target and request
# ---------------------------------------------------------------------------------------
def talent_layout(sim, cls):
    data = json.load(open(os.path.join(sim, "ui", "core", "talents", "trees", cls + ".json"), encoding="utf-8"))
    return [[(t["location"]["rowIdx"], t["maxPoints"]) for t in tree["talents"]] for tree in data]


def talents_for_level(sim, cls, tree_cfg, level):
    """The simulator's preset build for the tree, cut to the level's points (level - 9).

    Points go into the build's main tree in row order (the order of the talent string),
    then into the other trees in order. Once the level has the 31 points the last talent
    needs, one point is held back for it. Row gates (5 points per row) hold because the
    full build is valid and rows fill in order."""
    points = max(level - 9, 0)
    layout = talent_layout(sim, cls)
    full = [[int(c) for c in part] for part in (tree_cfg["talents"].split("-") + ["", ""])[:3]]
    for i in range(3):
        full[i] += [0] * (len(layout[i]) - len(full[i]))
    got = [[0] * len(layout[i]) for i in range(3)]
    order = [tree_cfg["main_tree"]] + [i for i in range(3) if i != tree_cfg["main_tree"]]
    main = order[0]
    last = len(layout[main]) - 1
    capstone = full[main][last] > 0 and points >= layout[main][last][0] * 5 + 1
    if capstone:
        points -= 1
    for tree in order:
        for idx, want in enumerate(full[tree]):
            if tree == main and idx == last and capstone:
                continue
            take = min(want, points)
            got[tree][idx] = take
            points -= take
    if capstone:
        spent_above = sum(got[main][:last])
        if spent_above >= layout[main][last][0] * 5:
            got[main][last] = 1
        else:
            points += 1
    return "-".join("".join(str(n) for n in tree).rstrip("0") for tree in got)


# --- Gear ------------------------------------------------------------------------------
# Item data comes from two real sources and nothing is invented:
#   - sim/planner/items.json.gz in the simulator: every client item with its stats already in
#     the simulator's stat indexes, weapon damage and speed, class, subclass, inventory type.
#   - Documentation/wow_spell_csv_forever/ItemSparse.*.csv here: name, required level, quality
#     and allowed classes from the Forever client. It does not hold every item; see info().
#   - assets/database/db.json in the simulator: where an item comes from (drop, quest,
#     crafted, vendor), for the items the simulator's authors curated.
# Known gaps, stated in every report: random-suffix world drops carry their stats in the
# suffix, and which suffixes an item can roll is in client tables this project does not
# have. An uncommon armour piece with no stats of its own is therefore given ONE assumed,
# class-suited suffix (CLASSES[...]["suffix"]) and marked as such; item "use" and proc
# effects exist only for items the simulator's own database knows; trinkets are not picked.
INV_SLOTS = {1: (0,), 2: (1,), 3: (2,), 16: (3,), 5: (4,), 20: (4,), 9: (5,), 10: (6,), 6: (7,), 7: (8,), 8: (9,),
             11: (10, 11), 12: (12, 13)}
SLOT_NAMES = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger 1",
              "finger 2", "trinket 1", "trinket 2", "main hand", "off hand", "ranged"]
GAME_SLOT = {"1": 0, "2": 1, "3": 2, "5": 4, "6": 7, "7": 8, "8": 9, "9": 5, "10": 6, "11": 10, "12": 11, "13": 12,
             "14": 13, "15": 3, "16": 14, "17": 15, "18": 16}   # WoW equipment slot -> simulator slot
INV_TYPE = {1: 1, 2: 2, 3: 3, 5: 5, 20: 5, 6: 8, 7: 9, 8: 10, 9: 6, 10: 7, 11: 11, 12: 12, 16: 4,
            13: 13, 14: 13, 17: 13, 21: 13, 22: 13, 23: 13, 15: 14, 25: 14, 26: 14, 28: 14}
WEAPON_TYPE = {0: 1, 1: 1, 4: 4, 5: 4, 6: 6, 7: 9, 8: 9, 10: 8, 13: 3, 15: 2}
HAND_TYPE = {13: 2, 21: 1, 22: 3, 14: 3, 23: 3, 17: 4}
# How far behind the character level each armour slot sits in the "average" setup: players
# do not replace everything at once. A fixed pattern, so runs are reproducible.
SLOT_LAG = {4: 0, 8: 1, 9: 2, 0: 2, 6: 3, 3: 3, 2: 4, 7: 5, 5: 6}
STAT_NAMES = {0: "strength", 1: "agility", 2: "stamina", 3: "intellect", 4: "spirit"}
GEAR_SETUPS = {
    "bare": "weapon only: the best uncommon weapon the level can equip, every other slot empty",
    "behind": "all uncommon, worn from 5 to 10 levels below the character, no jewellery",
    "average": "uncommon pieces up to 7 levels behind on a fixed per-slot lag, plus two lucky rare drops "
               "(the weapon and the chest) and uncommon jewellery where the client has any",
    "lucky": "rare in every slot that has one within 5 levels, the average pick elsewhere",
}


class ItemPool:
    def __init__(self, sim, cls):
        import csv
        import glob
        import gzip
        self.cfg = CLASSES[cls]
        with gzip.open(os.path.join(sim, "sim", "planner", "items.json.gz"), "rt", encoding="utf-8") as handle:
            tables = json.load(handle)
        self.stats, self.bonus, self.rand_prop = tables["items"], tables["bonus"], tables["randProp"]
        files = sorted(glob.glob(os.path.join(ROOT, "Documentation", "wow_spell_csv_forever", "ItemSparse.*.csv")))
        if not files:
            raise SystemExit("ItemSparse CSV not found under Documentation/wow_spell_csv_forever")
        self.client_file = os.path.basename(files[-1])
        self.meta = {}
        with open(files[-1], encoding="utf-8", newline="") as handle:
            reader = csv.reader(handle)
            head = next(reader)
            col = dict((name, head.index(name)) for name in
                       ("ID", "Display_lang", "AllowableClass", "RequiredLevel", "OverallQualityID"))
            for row in reader:
                self.meta[row[col["ID"]]] = (row[col["Display_lang"]], int(row[col["AllowableClass"]]),
                                             int(row[col["RequiredLevel"]]), int(row[col["OverallQualityID"]]))
        known = json.load(open(os.path.join(sim, "assets", "database", "db.json"), encoding="utf-8"))["items"]
        self.sim_db = dict((it["id"], it) for it in known)
        self.class_bit = 1 << (self.cfg["class_id"] - 1)
        self.wand_choice = None   # --wand: an item id, "none", or None for the rule in wand()

    def wand(self, level):
        """(item id or None, note). The rule: the highest-level uncommon wand an enchanter
        crafts that the level can equip, the wand a levelling caster is most often handed.
        Only wands in the simulator's own database carry damage and speed, so only those
        can be picked. --wand names one explicitly, or none."""
        if self.wand_choice == "none":
            return None, "no wand (--wand none)"
        wands = dict((iid, it) for iid, it in self.sim_db.items()
                     if it.get("rangedWeaponType") == 8 and it.get("weaponSpeed"))
        if self.wand_choice:
            iid = int(self.wand_choice)
            if iid not in wands:
                raise SystemExit("--wand %d: not a wand with damage in the simulator's database" % iid)
            return iid, " [named with --wand]"
        best = None
        for iid, it in wands.items():
            meta = self.meta.get(str(iid))
            crafted = any("crafted" in s for s in it.get("sources", []))
            if meta and crafted and meta[3] == 2 and 0 < meta[2] <= level and (best is None or meta[2] > best[0]):
                best = (meta[2], iid)
        if best is None:
            return None, "no crafted uncommon wand can be equipped at this level"
        return best[1], " [crafted wand, the same in every setup]"

    def info(self, iid):
        """(name, class mask, level the item is worn from, quality, estimated?) or None.

        The client table does not hold every item (old dungeon drops are missing from it)
        and some rows have no required level (quest rewards). For those the level is
        ESTIMATED as item level - 5, the usual gap for Classic items, and the report says so.
        Quality then comes from the simulator's own database."""
        rec = self.stats.get(str(iid))
        if rec is None:
            return None
        meta = self.meta.get(str(iid))
        known = self.sim_db.get(int(iid))
        if meta:
            name, mask, req, quality = meta
        elif known and known.get("quality"):
            name, mask, req, quality = known["name"], -1, 0, known["quality"]
        else:
            return None
        if req > 0:
            return name, mask, req, quality, False
        return name, mask, max(rec.get("il", 0) - 5, 1), quality, True

    def sources(self, iid):
        return sorted(set(k for s in self.sim_db.get(int(iid), {}).get("sources", []) for k in s))

    def prefer_sourced(self, cands):
        """Items with a recorded drop, quest or crafting source first, together with
        random-suffix world drops; other client-only items (no way to tell an event or
        promotional item from a drop) only when there are none."""
        sourced = [c for c in cands if self.sources(c[-1]) or self.suffix_base(c[-1])]
        return sourced or cands

    def assumed_bonus(self):
        """The suffix definition used for stat-less greens: among the definitions that give
        exactly the class's two suffix stats in equal shares, the median share. The client
        has several per suffix (different shares); which one an item uses is not known."""
        if not hasattr(self, "_assumed"):
            want = sorted(self.cfg.get("suffix", {}).get("stats", ()))
            found = []
            for bid, allocs in self.bonus.items():
                if sorted(int(a[0]) for a in allocs) == want and len(set(a[1] for a in allocs)) == 1:
                    found.append((allocs[0][1], int(bid)))
            found.sort()
            self._assumed = found[len(found) // 2][1] if found and want else None
        return self._assumed

    def suffix_base(self, iid):
        """An uncommon armour piece with no stats of its own besides armour and block: on this
        client its stats come from a random suffix attached when it drops. Only items with a
        real required level count: a stat-less item without one is usually a costume piece."""
        rec = self.stats.get(str(iid))
        meta = self.info(iid)
        if not rec or not meta or meta[3] != 2 or meta[4] or rec["c"] != 4 or rec["inv"] in (2, 11, 12):
            return False
        if any(k != "drop" for k in self.sources(iid)):
            return False   # crafted, quest and vendor items never roll a suffix
        return not any(v for k, v in rec.get("st", {}).items() if int(k) not in (26, 29, 30))

    def score(self, rec, iid=None):
        weights = self.cfg["stat_weights"]
        total = sum(weights.get(int(k), 0.0) * v for k, v in rec.get("st", {}).items())
        if iid is not None and self.assumed_bonus() and self.suffix_base(iid):
            total += sum(weights.get(k, 0.0) * v for k, v in self.suffix_stats(iid, [self.assumed_bonus()]).items())
        return total

    def candidates(self, level, quality, lo, hi, want):
        """(score, id) for items of the quality the class can use with required level in lo..hi."""
        out = []
        armor_ok = self.cfg["armor"](level)
        for iid, rec in self.stats.items():
            meta = self.info(iid)
            if not meta or meta[3] != quality or not (max(lo, 1) <= meta[2] <= hi):
                continue
            if meta[1] != -1 and not (meta[1] & self.class_bit):
                continue
            if not (0 <= rec.get("il", 0) - meta[2] <= 8):
                continue   # item level far from its level: event, promotional or scaled items
            src = self.sources(iid)
            if src and all(k == "soldBy" for k in src):
                continue   # vendor rewards (reputation, honour): not levelling gear
            if not want(rec):
                continue
            if rec["c"] == 4 and rec["inv"] != 16 and rec["s"] in (1, 2, 3, 4) and rec["s"] not in armor_ok:
                continue
            out.append((self.score(rec, iid), int(iid)))
        return sorted(out)

    def weapon_dps(self, rec):
        w = rec.get("w") or [0, 0, 1]
        return (w[0] + w[1]) / 2.0 / max(w[2], 0.1)

    def median(self, cands):
        return cands[len(cands) // 2][1] if cands else None

    def describe(self, iid, note=""):
        meta = self.info(iid) or (self.sim_db.get(iid, {}).get("name", "item %d" % iid), -1, 0, 0, True)
        name, _, req, quality, estimated = meta
        rec = self.stats.get(str(iid), {})
        src = self.sources(iid)
        return "%s (item %d, %s, level %d%s, item level %s, %s)%s" % (
            name, iid, {2: "uncommon", 3: "rare", 4: "epic"}.get(quality, "quality %d" % quality), req,
            " ESTIMATED" if estimated else " required", rec.get("il", "?"),
            "source: " + "/".join(src) if src else "no recorded source", note)

    def suffix_stats(self, iid, bonus):
        rec = self.stats[str(iid)]
        quality = (self.info(iid) or ("", -1, 0, 2, True))[3]
        name = {2: "Good", 3: "Superior", 4: "Epic", 5: "Epic"}.get(quality, "Good")
        index = 0 if rec["inv"] in (1, 5, 7, 17, 20) else 1 if rec["inv"] in (3, 6, 8, 10, 12) else \
            3 if rec["inv"] in (13, 21) else 4 if rec["inv"] in (15, 25, 26) else 2
        budget = (self.rand_prop.get(str(rec.get("il", 0))) or {}).get(name, [0] * 5)[index]
        out = {}
        for b in bonus:
            for stat, alloc in self.bonus.get(str(b), []):
                out[int(stat)] = out.get(int(stat), 0) + math.floor(alloc / 10000.0 * budget + 0.5)
        return out

    def sim_item(self, iid, slot, bonus=None):
        """(ItemSpec, custom SimItem or None). The simulator's own item is used when it has one."""
        if iid in self.sim_db and not bonus:
            return {"id": iid}, None
        rec = self.stats[str(iid)]
        stats = [0.0] * 44
        for k, v in rec.get("st", {}).items():
            if int(k) < len(stats):
                stats[int(k)] += v
        for k, v in (self.suffix_stats(iid, bonus) if bonus else {}).items():
            if k < len(stats):
                stats[k] += v
        item = {"id": iid, "name": (self.info(iid) or ("item %d" % iid,))[0], "type": INV_TYPE.get(rec["inv"], 0),
                "stats": stats, "ilvl": rec.get("il", 0)}
        if rec["c"] == 4 and rec["s"] in (1, 2, 3, 4):
            item["armorType"] = rec["s"]
        if rec["c"] == 2 or (rec["c"] == 4 and rec["s"] == 6):
            item["type"] = 13
            item["weaponType"] = 7 if rec["c"] == 4 else WEAPON_TYPE.get(rec["s"], 0)
            item["handType"] = HAND_TYPE.get(rec["inv"], 0)
            if slot == 16:
                # Client weapon subclass -> simulator ranged type (bow, gun, thrown, crossbow, wand).
                item["type"], item["rangedWeaponType"] = 14, {2: 1, 3: 3, 16: 6, 18: 2, 19: 8}.get(rec["s"], 1)
        w = rec.get("w") or rec.get("r")
        if w and len(w) == 3:
            item["weaponDamageMin"], item["weaponDamageMax"], item["weaponSpeed"] = w
        if iid in self.sim_db:
            item["id"] = 1700000000 + iid   # keep the simulator's own item; this copy adds the suffix stats
        return {"id": item["id"]}, item

    def build(self, setup, level):
        """A gear setup for the level -> (17 item specs, custom items, description lines)."""
        specs, custom, lines = [{} for _ in range(17)], [], []
        wcfg = self.cfg["weapon"]

        def put(slot, iid, note=""):
            bonus = None
            if self.assumed_bonus() and self.suffix_base(iid):
                bonus = [self.assumed_bonus()]
                gained = self.suffix_stats(iid, bonus)
                note += " [random-suffix drop; ASSUMED %s: %s]" % (
                    self.cfg["suffix"]["name"], ", ".join("+%d %s" % (v, STAT_NAMES.get(k, "stat %d" % k)) for k, v in sorted(gained.items())))
            spec, item = self.sim_item(iid, slot, bonus)
            specs[slot] = spec
            if item:
                custom.append(item)
            lines.append("%s: %s" % (SLOT_NAMES[slot], self.describe(iid, note)))

        def is_weapon(rec):
            return rec["c"] == 2 and rec["inv"] in wcfg["inv"] and rec["s"] in wcfg["subclasses"] and rec.get("w")

        def weapon(quality, lo, hi, best):
            cands = sorted((self.weapon_dps(self.stats[str(i)]), i)
                           for _, i in self.prefer_sourced(self.candidates(level, quality, lo, hi, is_weapon)))
            if not cands:
                return None
            return cands[-1][1] if best else self.median(cands)

        def armour(slot, quality, lo, hi, target=None):
            invs = [inv for inv, slots in INV_SLOTS.items() if slot in slots]
            cands = self.prefer_sourced([c for c in self.candidates(level, quality, lo, hi,
                                                                    lambda r: r["inv"] in invs and r["c"] == 4) if c[0] > 0])
            if target is not None and cands:
                near = min(abs(self.info(i)[2] - target) for _, i in cands)
                cands = [c for c in cands if abs(self.info(c[1])[2] - target) == near]
            return self.median(cands)

        armour_slots = [0, 2, 3, 4, 5, 6, 7, 8, 9]
        if setup == "bare":
            pick = weapon(2, 1, level, True)
            if pick:
                put(14, pick)
        elif setup == "behind":
            pick = weapon(2, level - 10, level - 5, False) or weapon(2, 1, level - 5, True)
            if pick:
                put(14, pick)
            for slot in armour_slots:
                pick = armour(slot, 2, level - 10, level - 5)
                if pick:
                    put(slot, pick)
        elif setup in ("average", "lucky"):
            rare = weapon(3, level - 5, level, False)
            pick = rare or weapon(2, level - 5, level, False) or weapon(2, 1, level, True)
            if pick:
                put(14, pick, " [lucky drop]" if rare else " [no rare weapon in range: uncommon]")
            for slot in armour_slots:
                base = armour(slot, 2, level - 7, level, level - SLOT_LAG[slot])
                want_rare = setup == "lucky" or slot == 4
                better = armour(slot, 3, level - 5, level) if want_rare else None
                if better:
                    put(slot, better, " [lucky drop]" if setup == "average" else "")
                elif base:
                    put(slot, base, " [no rare in range: uncommon]" if want_rare else "")
            for slot in (1, 10, 11):
                invs = [inv for inv, slots in INV_SLOTS.items() if slot in slots]
                quality = 3 if setup == "lucky" else 2
                cands = [c for c in self.candidates(level, quality, level - 7, level, lambda r: r["inv"] in invs)
                         if c[0] > 0 and {"id": c[1]} not in specs]
                if not cands and setup == "lucky":
                    cands = [c for c in self.candidates(level, 2, level - 7, level, lambda r: r["inv"] in invs)
                             if c[0] > 0 and {"id": c[1]} not in specs]
                if cands:
                    put(slot, self.median(self.prefer_sourced(cands)))
        else:
            raise SystemExit("unknown gear setup %r (use %s or file:<path>)" % (setup, ", ".join(GEAR_SETUPS)))
        if self.cfg.get("wand"):
            pick, note = self.wand(level)
            if pick:
                it = self.sim_db[pick]
                put(16, pick, "%s, %g-%g damage every %gs" % (note, it["weaponDamageMin"], it["weaponDamageMax"], it["weaponSpeed"]))
            else:
                lines.append("ranged: " + note)
        empty = [SLOT_NAMES[i] for i in armour_slots + [1, 10, 11] if not specs[i]]
        if empty and setup != "bare":
            lines.append("empty (no item passes the rule): " + ", ".join(empty))
        return specs, custom, lines

    def from_file(self, path):
        """An explicit character: {"gear": {"<WoW slot 1-18>": {"item": id, "bonus": [ids], "enchant": id}}}.
        The same gear shape as the simulator planner's character message."""
        data = json.load(open(path, encoding="utf-8"))
        specs, custom, lines = [{} for _ in range(17)], [], []
        for key in sorted(data.get("gear", {}), key=int):
            piece = data["gear"][key]
            slot, iid = GAME_SLOT.get(str(key)), int(piece.get("item") or 0)
            if slot is None or not iid:
                continue
            if str(iid) not in self.stats and iid not in self.sim_db:
                lines.append("%s: item %d is in neither item table: SLOT LEFT EMPTY" % (SLOT_NAMES[slot], iid))
                continue
            spec, item = self.sim_item(iid, slot, piece.get("bonus")) if str(iid) in self.stats else ({"id": iid}, None)
            specs[slot] = spec
            if item:
                custom.append(item)
            note = ""
            if piece.get("enchant"):
                note += " [enchant %s not applied]" % piece["enchant"]
            if item and slot in (12, 13):
                note += " [stats only: its use or proc effect is not modelled]"
            lines.append("%s: %s" % (SLOT_NAMES[slot], self.describe(iid, note)))
        return specs, custom, lines, data


def expected_creatures(sim):
    """level -> (health, auto-attack damage per second, armour) from the simulator's copy of
    the client ExpectedStat table (sim/planner/expected_generated.go)."""
    text = open(os.path.join(sim, "sim", "planner", "expected_generated.go"), encoding="utf-8").read()
    build = re.search(r"build ([\d.]+)", text)
    rows = {}
    for m in re.finditer(r"\{([\d.]+), ([\d.]+), ([\d.]+), [\d.]+\},\s*// (\d+)", text):
        rows[int(m.group(4))] = (float(m.group(1)), float(m.group(2)), float(m.group(3)))
    return rows, (build.group(1) if build else "?")


def scenarios_for(level, health_mults=None):
    """The target set for a level. With health_mults, an even-level target at each multiple of
    its expected health instead: the same fight made shorter or longer, to find where an
    ability stops paying for itself."""
    if health_mults:
        return [{"name": "L%d vs %d (even), health x%g" % (level, level, mult), "target_level": level,
                 "elite": False, "hp_mult": mult} for mult in health_mults]
    return ([] if level < 2 else [
        {"name": "L%d vs %d (one below)" % (level, level - 1), "target_level": level - 1, "elite": False}]) + [
        {"name": "L%d vs %d (even)" % (level, level), "target_level": level, "elite": False},
        {"name": "L%d vs %d (one above)" % (level, level + 1), "target_level": level + 1, "elite": False},
        {"name": "L%d vs %d elite" % (level, level + 1), "target_level": level + 1, "elite": True},
    ]


def build_request(cls, level, talents, gear, scenario, creatures, rotation, iterations, seed):
    cfg = CLASSES[cls]
    eng = ENGAGEMENTS[cfg["engagement"]]
    health, dps, armor = creatures[scenario["target_level"]]
    if scenario["elite"]:
        health *= ASSUMPTIONS["elite_health_mult"]
        dps *= ASSUMPTIONS["elite_damage_mult"]
    health *= scenario.get("hp_mult", 1)
    stats = [0.0] * 44
    # Stat indexes are read from proto/common.proto by stat_index(); filled in by the caller.
    stats[scenario["_armor_idx"]] = armor
    stats[scenario["_health_idx"]] = health
    spec_field, spec_value = cfg["spec"]
    player = {
        "name": "bench", "race": gear[2].get("race") or cfg["race"], "class": cfg["proto_class"], "level": level,
        "knownSpells": gear[2].get("spells") or [],
        "equipment": {"items": gear[0]}, "database": {"items": gear[1]},
        "talentsString": talents, "consumes": {}, "buffs": {},
        "inFrontOfTarget": eng["in_front"], "rotation": rotation, spec_field: spec_value,
    }
    target = {"name": scenario["name"], "level": scenario["target_level"], "mobType": "MobTypeHumanoid", "stats": stats}
    raid = {"parties": [{"players": [player]}]}
    if eng.get("distance") is not None:
        player["distanceFromTarget"] = eng["distance"]
    # The target always swings at the character: its swing count is the clock kill time is
    # read from. When the engagement says it never hits, the swing does no damage, and a
    # hit for no damage causes no pushback in the simulator (sim/core/cast.go).
    hits = eng["target_attacks_player"]
    target.update({"minBaseDamage": dps * ASSUMPTIONS["target_swing_speed"] / 1.17 if hits else 0,
                   "damageSpread": ASSUMPTIONS["target_damage_spread"] if hits else 0,
                   "swingSpeed": ASSUMPTIONS["target_swing_speed"], "tankIndex": 0})
    raid["tanks"] = [{"type": "Player", "index": 0}]
    return {"raid": raid,
            "encounter": {"useHealth": True, "duration": 180, "targets": [target]},
            "simOptions": {"iterations": iterations, "randomSeed": seed, "ruleset": "RulesetForever"}}


RACES = {"human": "RaceHuman", "dwarf": "RaceDwarf", "nightelf": "RaceNightElf", "gnome": "RaceGnome", "orc": "RaceOrc",
         "tauren": "RaceTauren", "troll": "RaceTroll", "undead": "RaceUndead", "scourge": "RaceUndead"}


def character_overrides(sim, cls, data, say):
    """What an exported character file adds beyond gear: race, learned ranks, talents.

    Talents arrive as trait node / entry / rank and are placed in the simulator's talent
    string with the planner's table (sim/planner/traits_generated.go), which exists for
    the classes the planner supports. Anything that cannot be used is said, not guessed."""
    out = {}
    if data.get("class") and data["class"].lower() != cls:
        say("  - character file is a %s, the run is for %s: only its gear is used" % (data["class"], cls))
        return out
    race = RACES.get(str(data.get("race", "")).lower().replace(" ", ""))
    if race:
        out["race"] = race
    elif data.get("race"):
        say("  - race %r has no simulator name here: the class default race is used" % data["race"])
    if data.get("spells"):
        out["spells"] = [int(x) for x in data["spells"]]
        say("  - %d learned spell ids sent as known spells: ability ranks follow them, not the level" % len(out["spells"]))
    picks = data.get("talents") or []
    if picks:
        text = open(os.path.join(sim, "sim", "planner", "traits_generated.go"), encoding="utf-8").read()
        block = re.search(r'"%s": \{(.*?)\n\t\},' % cls.upper(), text, re.S)
        if not block:
            say("  - talents: the simulator has no trait table for %s, so the level-derived build is used" % cls)
            return out
        slots = dict((int(m.group(1)), (int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))))
                     for m in re.finditer(r"(\d+): \{Tree: (\d+), Index: (\d+), MaxRank: (\d+), Node: (\d+)", block.group(1)))
        by_node = dict((v[3], v) for v in slots.values())
        trees, unknown = [[0] * 20 for _ in range(3)], 0
        for pick in picks:
            slot = slots.get(int(pick.get("entry", 0))) or by_node.get(int(pick.get("node", 0)))
            if not slot:
                unknown += 1
                continue
            trees[slot[0]][slot[1]] = min(int(pick.get("rank", 0)), slot[2])
        out["talents"] = "-".join("".join(str(n) for n in tree).rstrip("0") for tree in trees)
        say("  - talents from the file: `%s`%s" % (out["talents"], " (%d picks not in the trait table, left out)" % unknown if unknown else ""))
    return out


def stat_index(sim, name):
    text = open(os.path.join(sim, "proto", "common.proto"), encoding="utf-8").read()
    block = text[text.index("enum Stat {"):]
    return int(re.search(r"\b%s = (\d+);" % name, block).group(1))


def strip_prepull(rotation):
    rotation = dict(rotation)
    rotation.pop("prepullActions", None)
    rotation["type"] = "TypeAPL"
    return rotation


def run_cli(cli, request, keep, label):
    folder = keep or tempfile.mkdtemp(prefix="jac_simbench_")
    os.makedirs(folder, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9]+", "_", label)
    infile, outfile = os.path.join(folder, safe + ".request.json"), os.path.join(folder, safe + ".result.json")
    json.dump(request, open(infile, "w", encoding="utf-8"), indent=1)
    proc = subprocess.run([cli, "sim", "--infile", infile, "--outfile", outfile], capture_output=True, text=True)
    if proc.returncode != 0 or not os.path.exists(outfile):
        return None, (proc.stderr or proc.stdout).strip()[-400:]
    result = json.load(open(outfile, encoding="utf-8"))
    if result.get("error"):
        return None, json.dumps(result["error"])[:400]
    return result, None


def summarize(result, swing_speed):
    """One run -> damage per fight, kill time, casts per fight.

    With a fight sized by health the simulator stops the iteration at the kill but then
    reports a nominal 600 s duration, so its own damage per second and fight length are
    unusable. Damage per fight is still right, and the target's melee swings are a clock:
    it swings at t = 0 and every swing_speed seconds until the kill, so the mean kill time
    is swing_speed x (mean swings - 0.5). That holds while nothing slows or stuns the
    target (Thunder Clap would bias it)."""
    player = result["raidMetrics"]["parties"][0]["players"][0]
    n = result.get("iterationsDone") or player["dps"]["aggregatorData"]["n"]
    casts, damage = {}, 0.0
    for action in player.get("actions", []):
        ident = action.get("id", {})
        key = "%s%s" % (ident.get("spellId") or ident.get("otherId") or ident.get("itemId") or "?",
                         ":%d" % ident["tag"] if ident.get("tag") else "")
        tot = sum(t.get("casts", 0) for t in action.get("targets", []))
        dmg = sum(t.get("damage", 0.0) for t in action.get("targets", []))
        damage += dmg
        casts[key] = (tot / n, dmg / n)
    mana = -sum(r.get("gain", 0.0) for r in player.get("resources", [])
                if r.get("type") == "ResourceTypeMana" and r.get("gain", 0.0) < 0) / n
    swings = 0
    for target in result["encounterMetrics"]["targets"]:
        for action in target.get("actions", []):
            if action.get("id", {}).get("otherId") == "OtherActionAttack":
                swings += sum(t.get("casts", 0) for t in action.get("targets", []))
    if not swings:
        return {"n": n, "damage": damage / n, "kill": float("nan"), "dps": float("nan"), "casts": casts, "mana": mana}
    kill = swing_speed * (swings / n - 0.5)
    return {"n": n, "damage": damage / n, "kill": kill, "dps": damage / n / kill, "casts": casts, "mana": mana}


# Two-sided 95% Student t quantiles by degrees of freedom (batch means).
T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
       11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 19: 2.093, 24: 2.064, 29: 2.045}


def mean_ci(values):
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return mean, float("nan"), float("nan")
    sd = math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1))
    t = 1.96 if n > 30 else T95[max(k for k in T95 if k <= n - 1)]
    half = t * sd / math.sqrt(n)
    return mean, mean - half, mean + half


def merge_casts(batches):
    keys = set(k for b in batches for k in b["casts"])
    return dict((k, (sum(b["casts"].get(k, (0, 0))[0] for b in batches) / len(batches),
                     sum(b["casts"].get(k, (0, 0))[1] for b in batches) / len(batches))) for k in keys)


# ---------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--sim", required=True, help="WoW Forever simulator checkout")
    ap.add_argument("--cli", help="built wowsimcli executable")
    ap.add_argument("--class", dest="cls", default="warrior", choices=sorted(CLASSES))
    ap.add_argument("--tree", default="arms")
    ap.add_argument("--context", default="st", choices=("st", "cleave", "aoe"))
    ap.add_argument("--levels", default="20,40")
    ap.add_argument("--gear", default="average",
                    help="comma-separated gear setups: %s, or file:<character json>. Every result row names its setup"
                         % ", ".join(GEAR_SETUPS))
    ap.add_argument("--iterations", type=int, default=1000, help="iterations per batch")
    ap.add_argument("--batches", type=int, default=10,
                    help="independent seeds per arm; intervals come from the spread of the batch means")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--no-dot-floor", action="store_true", help="leave out the runtime's no-new-DoT-on-a-dying-target rule")
    ap.add_argument("--without", help="comma-separated JustAC rank-1 ids: adds an arm that is the generated list "
                                      "minus these entries (an ablation; nothing is written back). Separate several "
                                      "groups with ';' for one arm each")
    ap.add_argument("--mana-floor", help="id=percent[,id=percent]: adds an arm in which each named entry is only cast "
                                         "at or above that mana percentage (the runtime's spend-while-mana-is-high rule "
                                         "for a filler; nothing is written back). Separate several arms with ';'")
    ap.add_argument("--health-mults", help="comma-separated multiples of the expected health of an even-level "
                                           "target: replaces the usual target set with one scenario per multiple")
    ap.add_argument("--engagement", choices=sorted(ENGAGEMENTS), help="how the character meets the target "
                    "(default: the class's own)")
    ap.add_argument("--pet", help="warlock demon: none, imp, voidwalker, succubus or felhunter (default none; the "
                                  "simulator's demons only act at owner levels 25, 40, 50 and 60)")
    ap.add_argument("--wand", help="wand item id from the simulator's database, or 'none' (default: the crafted "
                                   "uncommon wand the level can equip)")
    ap.add_argument("--convert-only", action="store_true")
    ap.add_argument("--keep", help="folder for the request and result JSON of every run")
    ap.add_argument("--out", help="write the report (Markdown) here as well as to stdout")
    args = ap.parse_args()

    cls, cfg = args.cls, CLASSES[args.cls]
    if args.engagement:
        cfg["engagement"] = args.engagement
    if args.pet:
        if "summon" not in cfg["spec"][1].get("options", {}):
            raise SystemExit("--pet applies to a class with a demon")
        demon = {"none": "NoSummon", "imp": "Imp", "voidwalker": "Voidwalker", "succubus": "Succubus",
                 "felhunter": "Felhunter"}.get(args.pet.lower())
        if not demon:
            raise SystemExit("--pet %r: use none, imp, voidwalker, succubus or felhunter" % args.pet)
        cfg["spec"][1]["options"]["summon"] = demon
    tree_cfg = cfg["trees"][args.tree]
    classes, chains, names = load_rotations()
    entries = classes[cls.upper() + "_F"][args.tree][args.context]
    floor = None if args.no_dot_floor else dot_floor_pct()
    conv = Converter(IdMap(args.sim, cls, chains), names, cfg["engagement"], floor)
    justac = conv.convert(entries)

    lines = []
    say = lines.append
    say("# JustAC list vs simulator presets: %s %s (%s)" % (cls, args.tree, args.context))
    say("")
    say("## Conversion of the generated list")
    say("")
    counts = {EXACT: 0, APPROX: 0, LOST: 0}
    last = None
    for line, status, text in conv.report:
        counts[status] += 1
        if line != last:
            say("- `%s`" % line.strip())
            last = line
        say("  - %s: %s" % (status, text))
    say("")
    say("Totals: %d exact, %d approximated, %d not expressible." % (counts[EXACT], counts[APPROX], counts[LOST]))
    say("")
    if args.convert_only:
        say("```json")
        say(json.dumps(justac, indent=1))
        say("```")
        print("\n".join(lines))
        return
    if not args.cli:
        raise SystemExit("--cli is required to run (or use --convert-only)")

    arms = [("justac", justac)]
    for group in (args.without or "").split(";"):
        if not group.strip():
            continue
        drop = set(int(x) for x in group.split(","))
        quiet = Converter(conv.ids, names, cfg["engagement"], floor)
        arms.append(("justac-without-" + "-".join(str(d) for d in sorted(drop)),
                     quiet.convert([e for e in entries if e["id"] not in drop])))
    for group in (args.mana_floor or "").split(";"):
        if not group.strip():
            continue
        floors = dict((int(k), float(v)) for k, v in (pair.split("=") for pair in group.split(",")))
        quiet = Converter(conv.ids, names, cfg["engagement"], floor)
        gated = [dict(e, gates=list(e.get("gates") or []) + [{"t": "power", "res": "mana", "op": ">=", "n": floors[e["id"]],
                                                             "ispct": True}]) if e["id"] in floors else e for e in entries]
        arms.append(("justac-" + "-".join("%d-above-%g" % kv for kv in sorted(floors.items())), quiet.convert(gated)))
    arms.append(("sim", strip_prepull(json.load(open(os.path.join(args.sim, tree_cfg["sim_preset"]), encoding="utf-8")))))
    src = os.path.join(PRESETS, tree_cfg["source_preset"])
    if os.path.exists(src):
        arms.append(("source", strip_prepull(json.load(open(src, encoding="utf-8")))))

    creatures, build = expected_creatures(args.sim)
    armor_idx, health_idx = stat_index(args.sim, "StatArmor"), stat_index(args.sim, "StatHealth")
    say("## Setup")
    say("")
    say("- Simulator: `%s`, ruleset Forever, %d batches of %d iterations per arm and scenario, the same seeds for every arm "
        "(base seed %d). Intervals are 95%% Student t intervals over the batch means; the comparison column pairs batches by seed."
        % (args.sim, args.batches, args.iterations, args.seed))
    say("- Kill time is measured from the target's own swing count (see summarize in the tool); damage per second is damage "
        "per fight divided by it. A negative last column means the arm kills faster than the simulator's preset.")
    say("- Arms: justac = `Data/Forever/Rotations.lua` %s/%s/%s; sim = `%s`; source = `tools/forever-apl-src/presets/%s`. "
        "Pre-pull actions removed from every arm." % (cls, args.tree, args.context, tree_cfg["sim_preset"], tree_cfg["source_preset"]))
    if conv.ids.tables:
        say("- Ranks: the simulator gives each rank of %d spell families its own action id and registers only the ranks "
            "the level has, so every arm is rewritten per level to the highest rank the level has. A spell the level does "
            "not have is never cast." % len(conv.ids.tables))
    say("- Engagement: %s (%s). Race %s, no consumables or buffs, starting resource 0."
        % (cfg["engagement"], ENGAGEMENTS[cfg["engagement"]]["note"], cfg["race"]))
    say("- Targets: client ExpectedStat build %s (health, armour, melee damage per second); elite = health x%g, damage x%g (assumed)."
        % (build, ASSUMPTIONS["elite_health_mult"], ASSUMPTIONS["elite_damage_mult"]))
    say("")

    pool = ItemPool(args.sim, cls)
    pool.wand_choice = args.wand
    if cfg.get("wand"):
        say("- Wand: needs a simulator build with the local wand attack (`sim/core/wand.go`, not upstream). Its model is "
            "assumed, not measured: the wand's own damage roll, ranged hit table, Arcane school, shooting stops for casts "
            "and global cooldowns and resumes 0.5s after. Spec options: %s."
            % json.dumps(cfg["spec"][1].get("options", {}), separators=(",", ":")))
    setups = [g.strip() for g in args.gear.split(",") if g.strip()]
    say("- Item data: stats from the simulator's `sim/planner/items.json.gz`; name, required level, quality and class from "
        "`Documentation/wow_spell_csv_forever/%s`. A stat-less uncommon armour piece is a random-suffix drop: it is given the ASSUMED suffix "
        "'%s' (which suffixes an item can really roll is not in the data) and marked; "
        "item use and proc effects exist only for items in the simulator's own database, trinkets are not picked." % (pool.client_file, cfg.get("suffix", {}).get("name", "none")))
    say("")
    jobs = []
    for setup in setups:
        file_level = None
        if setup.startswith("file:"):
            file_level = json.load(open(setup[5:], encoding="utf-8")).get("level")
        for level in ([int(file_level)] if file_level else [int(x) for x in args.levels.split(",")]):
            jobs.append((level, setup))
    jobs.sort(key=lambda job: job[0])
    for level, setup in jobs:
        talents = talents_for_level(args.sim, cls, tree_cfg, level)
        label = "file:" + os.path.basename(setup[5:]) if setup.startswith("file:") else setup
        say("## Level %d, gear: %s" % (level, label))
        say("")
        say("- Gear setup `%s`: %s." % (setup, GEAR_SETUPS.get(setup, "explicit character file")))
        extra = {}
        if setup.startswith("file:"):
            specs, custom, gear_lines, data = pool.from_file(setup[5:])
            extra = character_overrides(args.sim, cls, data, say)
        else:
            specs, custom, gear_lines = pool.build(setup, level)
        if extra.get("talents") is not None:
            talents = extra["talents"]
        else:
            say("- Talents `%s` (%d points, derived from the level)." % (talents, max(level - 9, 0)))
        gear = (specs, custom, extra)
        for line in gear_lines:
            say("  - %s" % line)
        say("")
        say("| Gear | Scenario | Target health | Arm | Kill time s (95% CI) | DPS (95% CI) | Kill time vs sim preset, % (95% CI) |")
        say("|---|---|---|---|---|---|---|")
        cast_tables = []
        speed = ASSUMPTIONS["target_swing_speed"]
        health_mults = [float(x) for x in args.health_mults.split(",")] if args.health_mults else None
        for sc in scenarios_for(level, health_mults):
            sc["_armor_idx"], sc["_health_idx"] = armor_idx, health_idx
            health = (creatures[sc["target_level"]][0] * (ASSUMPTIONS["elite_health_mult"] if sc["elite"] else 1)
                      * sc.get("hp_mult", 1))
            got = {}
            for name, rotation in arms:
                runs = []
                for batch in range(args.batches):
                    seed = args.seed + batch * 1000003   # the same seeds for every arm
                    request = build_request(cls, level, talents, gear, sc, creatures,
                                            ranks_for_level(rotation, conv.ids.tables, level), args.iterations, seed)
                    result, err = run_cli(args.cli, request, args.keep,
                                          "%s_%s_%s_b%d" % (os.path.basename(setup), sc["name"], name, batch))
                    if result is None:
                        say("| %s | %s | %d | %s | failed: %s | | |"
                            % (label, sc["name"], health, name, err.replace("|", "/").replace("\n", " ")))
                        runs = []
                        break
                    runs.append(summarize(result, speed))
                if runs:
                    got[name] = runs
            for name, _ in arms:
                if name not in got:
                    continue
                kill = mean_ci([r["kill"] for r in got[name]])
                dps = mean_ci([r["dps"] for r in got[name]])
                rel = ""
                if name != "sim" and "sim" in got:
                    pairs = [100 * (a["kill"] - b["kill"]) / b["kill"] for a, b in zip(got[name], got["sim"])]
                    rel = "%+.1f [%+.1f, %+.1f]" % mean_ci(pairs)
                say("| %s | %s | %d | %s | %.1f [%.1f, %.1f] | %.1f [%.1f, %.1f] | %s |"
                    % ((label, sc["name"], health, name) + kill + dps + (rel,)))
            cast_tables.append((sc["name"], dict((k, {"casts": merge_casts(v), "mana": sum(r["mana"] for r in v) / len(v)})
                                                 for k, v in got.items())))
        say("")
        say("Casts per fight (damage per fight in brackets), by simulator action id:")
        say("")
        for name, got in cast_tables:
            say("- %s" % name)
            for arm in got:
                parts = ["%s x%.2f (%.0f)" % (k, c, d) for k, (c, d) in sorted(got[arm]["casts"].items(), key=lambda kv: -kv[1][1]) if c > 0.005]
                spent = "; mana spent per fight %.0f" % got[arm]["mana"] if got[arm]["mana"] else ""
                say("  - %s: %s%s" % (arm, ", ".join(parts), spent))
        say("")

    text = "\n".join(lines)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")


if __name__ == "__main__":
    main()
