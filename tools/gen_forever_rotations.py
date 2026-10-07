#!/usr/bin/env python3
# tools/gen_forever_rotations.py
#
# WoW Forever priority lists for every class and talent tree -> Data/ForeverRotations.lua.
#
# Source 1: the wowsims-format rotation files vendored in tools/forever-apl-src/ (from
# github.com/ElliotWood/Forever, MIT; commit in UPSTREAM_COMMIT). Forever spell ids, level
# 60, structured conditions. Source 2: hand pins in tools/simc-apl-forever/ for trees the sim
# does not model (healer damage fillers).
#
# Each entry keeps the gates JustAC can evaluate under secret values, in the same shape
# RotationImport already reads (buff / cd / dot / execute / health / power / resource /
# stack / stealth / any / all), plus three Forever gates: `known` (IsPlayerSpell), `swing`
# (time to next auto attack, PLAYER_SWING) and `tick` (time to next energy tick). What no
# gate can express marks the entry `delegated`: it keeps its priority place, ungated.
# Ids are emitted as rank 1 of their chain; `rankChains` lets the runtime show the highest
# rank known. Spells no Forever class can learn (racials, items, removed abilities such as
# Tiger's Fury) are dropped and reported.
#
# Usage: python tools/gen_forever_rotations.py [--print]
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "forever-apl-src")
PINS = os.path.join(ROOT, "tools", "simc-apl-forever")
OUT = os.path.join(ROOT, "Data", "ForeverRotations.lua")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_forever_apl as cfa  # noqa: E402  (shared learnability + rank chains)
import gen_simc_rotations as gsr  # noqa: E402  (the SimC condition parser, for hand pins)

# class -> (default tree for characters with no talent points, {tree: source})
# A source is a vendored file stem or "pin:<file stem>" for a hand pin.
TREES = {
    "warrior": ("arms", {"arms": "warrior_dps__dps_battle", "fury": "warrior_dps__dps_reck",
                         "protection": "warrior_protection__protection"}),
    "rogue": ("combat", {"assassination": "rogue_dps__forever_mutilate",
                         "combat": "rogue_dps__combat_sinister_strike",
                         "subtlety": "rogue_dps__forever_hemorrhage"}),
    "paladin": ("retribution", {"holy": "pin:paladin_holy",
                                "protection": "paladin_protection__default",
                                "retribution": "paladin_retribution__default"}),
    "priest": ("shadow", {"discipline": "priest_dps__smite", "holy": "priest_dps__smite",
                          "shadow": "priest_dps__shadow"}),
    "druid": ("feral", {"balance": "druid_balance__default", "feral": "druid_feralcat__default",
                        "feral_bear": "druid_feralbear__default",
                        "restoration": "pin:druid_restoration"}),
    "shaman": ("enhancement", {"elemental": "shaman_elemental__forever",
                               "enhancement": "shaman_enhancement__forever",
                               "restoration": "pin:shaman_restoration"}),
    "hunter": ("beast_mastery", {"beast_mastery": "hunter_dps__bm",
                                 "marksmanship": "hunter_dps__mm", "survival": "hunter_dps__sv"}),
    "mage": ("frost", {"arcane": "mage_dps__arcane", "fire": "mage_dps__fire",
                       "frost": "mage_dps__frost"}),
    "warlock": ("affliction", {"affliction": "warlock_dps__affliction",
                               "demonology": "warlock_dps__demonic_pact",
                               "destruction": "warlock_dps__destruction"}),
}
# Keeping your own timed buff up leads every list (Battle Shout, a paladin seal): the sims cast
# it before the pull and it outlasts their fight, so their in-combat line sits last, but on
# Forever it lapses mid-fight while levelling and every guide puts it first
# (forever-guides/). An entry qualifies when its only gate is its own buff being down.
# Forms and stances (no duration) keep the sim's place: the sims order those deliberately.
# Lists that lack one the guides call for get it, gated the same way (rank-1 ids).
ADD = {"warrior": [6673]}   # Battle Shout: the tank (Protection) sim list has none
# AoE abilities the sims leave out because their level-60 lists use a later one (Whirlwind),
# while a levelling character's AoE IS this one. Placed at the front of the cleave (2 targets)
# and aoe (3+) tiers, after the own-buff leads, ungated: the cooldown and the stance it needs
# are read live (rank-1 ids). Everything else in the 2-target tier stays the sim's own call on
# whether AoE beats single-target damage there.
AOE_LEAD = {"warrior": [6343]}   # Thunder Clap
AOE_LEAD_TIERS = ["cleave", "aoe"]

# Abilities the level-60 sims leave out but levelling play needs (tools/forever-guides, and the
# missing-abilities audit of 2026-10-07), by ability name; the build exits on one the class
# cannot learn. trees: which talent trees (None = all). tiers: which target-count lists (None
# = all). at: "front" (after the own-buff leads; listed order kept), "end", or "after:<name>".
# gates: "dot" = keep-it-up on the target (sinks while it runs, never on a dying target),
# "stealth" = only from stealth. Melee abilities need no gate: out of range sinks them.
EXTRA = {
    "warrior": [dict(spell="demoralizing_shout", tiers=["cleave", "aoe"], at="front", gates=["dot"])],
    "hunter": [dict(spell="hunters_mark", at="front", gates=["dot"]),
               dict(spell="raptor_strike", at="front"),
               dict(spell="mongoose_bite", at="front")],
    "rogue": [dict(spell="cheap_shot", at="front", gates=["stealth"]),
              dict(spell="garrote", at="front", gates=["stealth", "dot"])],
    "druid": [dict(spell="rake", trees=["feral"], at="front", gates=["dot"]),
              dict(spell="swipe", trees=["feral_bear"], tiers=["cleave", "aoe"], at="front")],
    "warlock": [dict(spell="conflagrate", trees=["destruction"], at="after:immolate")],
    "mage": [dict(spell="cone_of_cold", trees=["frost"], tiers=["cleave", "aoe"], at="front"),
             dict(spell="frost_nova", trees=["frost"], tiers=["aoe"], at="end")],
    "priest": [dict(spell="holy_nova", tiers=["cleave", "aoe"], at="front")],
}


def add_extras(cls, tree, entries, chains, unresolved):
    """Place the class's EXTRA abilities into one tree's entries (in place)."""
    def r1_of(name):
        chain = chains.get(name)
        if not chain:
            unresolved.append(f"{cls}: EXTRA {name} is not learnable")
            return None
        return rank1(chain)
    fronts = []
    for x in EXTRA.get(cls, []):
        if x.get("trees") and tree not in x["trees"]:
            continue
        sid = r1_of(x["spell"])
        if not sid or any(e["id"] == sid for e in entries):
            continue
        gates = []
        for g in x.get("gates", []):
            gates.append({"t": "dot", "id": sid} if g == "dot" else {"t": "stealth"})
        e = {"id": sid, "delegated": False, "tiers": list(x.get("tiers") or [t for t, _ in TIERS]),
             "gates": gates}
        at = x.get("at", "end")
        if at == "front":
            fronts.append(e)
        elif at.startswith("after:"):
            anchor = r1_of(at[6:])
            i = next((n for n, y in enumerate(entries) if y["id"] == anchor), None)
            entries.insert(len(entries) if i is None else i + 1, e)
        else:
            entries.append(e)
    entries[0:0] = fronts


def keeps_own_buff(e):
    g = e["gates"]
    return (len(g) == 1 and g[0].get("t") == "buff" and g[0].get("id") == e["id"]
            and g[0].get("neg") and g[0].get("dur"))
TIERS = [("st", 1), ("cleave", 2), ("aoe", 3)]
OPS = {"OpLt": "<", "OpLe": "<=", "OpGt": ">", "OpGe": ">=", "OpEq": "=", "OpNe": "!="}
FLIP = {"<": ">", "<=": ">=", ">": "<", ">=": "<=", "=": "=", "!=": "!="}
NOT_OP = {"<": ">=", "<=": ">", ">": "<=", ">=": "<", "=": "!=", "!=": "="}
POWER = {"currentRage": "rage", "currentEnergy": "energy", "currentMana": "mana"}
TRUE, FALSE, UNK = "TRUE", "FALSE", "UNK"
# spellID -> base aura seconds (SpellMisc.DurationIndex -> SpellDuration), filled by main().
# A buff gate needs it for the runtime's cast-observed window (IsBuffWindowActive).
DURATION = {}


def num(const):
    """'6' / '0ms' / '2s' / '20%' -> float (seconds for times)."""
    v = str(const.get("val", "0")).strip()
    m = re.fullmatch(r"(-?[\d.]+)\s*(ms|s|%)?", v)
    if not m:
        return None
    n = float(m.group(1))
    return n / 1000 if m.group(2) == "ms" else n


def sid_of(ref):
    """{"spellId": n, "rank": r} -> n, None for item / other ids."""
    return ref.get("spellId") if isinstance(ref, dict) else None


def compare(k, op, n):
    return {"<": k < n, "<=": k <= n, ">": k > n, ">=": k >= n, "=": k == n, "!=": k != n}[op]


def rank1(chain):
    """Rank 1 (the first-learned id) of a class_chains chain."""
    return int(chain[0][0])


def cmp_parts(val):
    """A wowsims comparison as (op, value name, constant, value args), constant on the
    right; (op, None, None, {}) when it is not value-vs-constant."""
    op = OPS.get(val.get("op"))
    lhs, rhs = val.get("lhs", {}), val.get("rhs", {})
    if "const" in rhs and "const" not in lhs:
        side, n = lhs, num(rhs["const"])
    elif "const" in lhs and "const" not in rhs:
        side, n, op = rhs, num(lhs["const"]), FLIP.get(op)
    else:
        return op, None, None, {}
    name = next(iter(side), None)
    return op, name, n, (side.get(name, {}) if name else {})


class Conv:
    """Condition tree -> gate, for one class. `self.delegated` records lost conditions."""

    def __init__(self, by_id, self_id=None):
        self.by_id = by_id
        self.self_id = self_id   # the entry's own spell (rank 1), for DoT-refresh negation
        self.delegated = False

    def buff(self, aid, neg=False):
        g = {"t": "buff", "id": aid}
        if DURATION.get(aid):
            g["dur"] = DURATION[aid]
        if neg:
            g["neg"] = True
        return g

    def rank1(self, sid):
        chain = self.by_id.get(sid)
        return rank1(chain) if chain else sid

    # --- target-count tier: True / False / None for k engaged enemies ---
    def tier(self, node, k):
        if not isinstance(node, dict) or not node:
            return None
        key, val = next(iter(node.items()))
        if key == "and":
            vs = [self.tier(x, k) for x in val.get("vals", [])]
            return False if False in vs else (True if all(v is True for v in vs) else None)
        if key == "or":
            vs = [self.tier(x, k) for x in val.get("vals", [])]
            return True if True in vs else (False if vs and all(v is False for v in vs) else None)
        if key == "not":
            v = self.tier(val.get("val"), k)
            return None if v is None else not v
        if key == "cmp":
            op, name, n, _ = cmp_parts(val)
            if name == "numberTargets" and n is not None and op in FLIP:
                return compare(k, op, n)
        return None

    # --- gates ---
    def negate(self, g):
        if g in (TRUE, FALSE):
            return FALSE if g == TRUE else TRUE
        if g == UNK:
            return UNK
        t = g["t"]
        if t in ("buff", "cd", "known", "stealth"):
            return dict(g, neg=not g.get("neg", False))
        if t in ("power", "resource", "execute", "health", "stack", "swing", "tick") and g.get("op") in NOT_OP:
            return dict(g, op=NOT_OP[g["op"]])
        if t in ("any", "all"):
            members = [self.negate(m) for m in g["g"]]
            if UNK in members:
                return UNK
            return {"t": "all" if t == "any" else "any", "g": members}
        # A dot gate has no sense to flip: it means "this DoT is being maintained". So
        # "not my own DoT up" (Rend, Flame Shock) is exactly that gate; "not SOMEONE ELSE's
        # debuff up" (Sunder unless Expose Armor) cannot be said and is given up.
        if t == "dot" and g.get("id") == self.self_id:
            return g
        return UNK

    def conv(self, node):
        if not isinstance(node, dict) or not node:
            return TRUE
        key, val = next(iter(node.items()))
        if key == "const":
            return TRUE
        if key == "and":
            out = []
            for x in val.get("vals", []):
                g = self.conv(x)
                if g == FALSE:
                    return FALSE
                if g == UNK:
                    self.delegated = True
                elif g != TRUE:
                    out.append(g)
            return TRUE if not out else (out[0] if len(out) == 1 else {"t": "all", "g": out})
        if key == "or":
            out = []
            for x in val.get("vals", []):
                g = self.conv(x)
                if g == TRUE:
                    return TRUE
                if g == UNK:
                    # Dropping an `or` member makes it STRICTER, which is wrong: give the
                    # whole alternative up instead.
                    self.delegated = True
                    return TRUE
                if g != FALSE:
                    out.append(g)
            return FALSE if not out else (out[0] if len(out) == 1 else {"t": "any", "g": out})
        if key == "not":
            g = self.negate(self.conv(val.get("val")))
            if g == UNK:
                self.delegated = True
                return TRUE
            return g
        if key == "cmp":
            return self.cmp(val)
        if key == "auraIsActive":
            aid = self.rank1(sid_of(val.get("auraId")))
            if not aid:
                return UNK
            if val.get("sourceUnit", {}).get("type") == "CurrentTarget":
                return {"t": "dot", "id": aid}
            return self.buff(aid)
        if key == "dotIsActive":
            sid = sid_of(val.get("spellId"))
            return {"t": "dot", "id": self.rank1(sid)} if sid else UNK
        if key == "isExecutePhase":
            m = re.search(r"\d+", str(val.get("threshold", "E20")))
            return {"t": "execute", "op": "<", "pct": int(m.group()) if m else 20}
        if key in ("spellIsKnown", "auraIsKnown"):
            sid = sid_of(val.get("spellId") or val.get("auraId"))
            return {"t": "known", "id": sid} if sid else UNK
        if key == "spellIsReady":
            sid = sid_of(val.get("spellId"))
            return {"t": "cd", "id": self.rank1(sid)} if sid else UNK
        if key in ("gcdIsReady", "spellCanCast"):
            return TRUE
        if key == "auraShouldRefresh":
            self.delegated = True
            aid = self.rank1(sid_of(val.get("auraId")))
            if not aid:
                return TRUE
            if val.get("sourceUnit", {}).get("type") == "CurrentTarget":
                return {"t": "dot", "id": aid}
            return self.buff(aid, True)
        return UNK

    def cmp(self, val):
        op, name, n, side = cmp_parts(val)
        if op is None or name is None or n is None:
            return UNK
        if name == "numberTargets":
            return TRUE                     # decided by the tier split
        if name == "remainingTime":
            # Fight length is unknowable; assume the fight goes on (steady state).
            # ponytail: end-of-fight dumps never fire; a real time-to-die needs secret health.
            return TRUE if op in (">", ">=") else (FALSE if op in ("<", "<=") else UNK)
        if name in POWER:
            return {"t": "power", "res": POWER[name], "op": op, "n": n}
        if name == "currentManaPercent":
            return {"t": "power", "res": "mana", "op": op, "n": n, "ispct": True}
        if name == "currentComboPoints":
            return {"t": "resource", "res": "combo_points", "op": op, "n": n}
        if name == "currentHealthPercent":
            on_target = side.get("sourceUnit", {}).get("type") == "CurrentTarget"
            return {"t": "execute" if on_target else "health", "op": op, "pct": n}
        if name == "spellTimeToReady":
            sid = self.rank1(sid_of(side.get("spellId")))
            if not sid:
                return UNK
            if op in ("<", "<=") and n <= 1.5:
                return {"t": "cd", "id": sid}
            if op in (">", ">=") and n >= 0:
                return {"t": "cd", "id": sid, "neg": True}
            return UNK
        if name in ("auraRemainingTime", "dotRemainingTime"):
            sid = self.rank1(sid_of(side.get("auraId") or side.get("spellId")))
            if not sid:
                return UNK
            self.delegated = True            # remaining time itself is secret
            target = name == "dotRemainingTime" or side.get("sourceUnit", {}).get("type") == "CurrentTarget"
            if target:
                return {"t": "dot", "id": sid}
            return self.buff(sid, op in ("<", "<="))
        if name == "auraNumStacks":
            aid = self.rank1(sid_of(side.get("auraId")))
            if not aid:
                return UNK
            g = {"t": "stack", "id": aid, "op": op, "n": n}
            if side.get("sourceUnit", {}).get("type") == "CurrentTarget":
                g["tgt"] = True
            return g
        if name == "autoTimeToNext":
            g = {"t": "swing", "op": op, "n": n}
            if side.get("autoType") == "RangedAuto":
                g["ranged"] = True
            return g
        if name == "timeToNextEnergyTick":
            return {"t": "tick", "op": op, "n": n}
        return UNK


def actions_of(action):
    """(spellID, extra gate) for every cast an action makes; sequences expand in order."""
    if "strictSequence" in action:
        out = []
        for a in action["strictSequence"].get("actions", []):
            out += actions_of(a)
        return out
    for key in ("castSpell", "channelSpell"):
        if key in action:
            sid = sid_of(action[key].get("spellId"))
            return [(sid, None)] if sid else []
    if "multidot" in action:
        sid = sid_of(action["multidot"].get("spellId"))
        return [(sid, "dot")] if sid else []
    return []   # autocastOtherCooldowns, cancelAura, move, wait: not suggestions


def convert_sim(stem, by_id, dropped):
    # ponytail: prepullActions are not read - nothing consumes a precombat list yet.
    data = json.load(open(os.path.join(SRC, stem + ".apl.json"), encoding="utf-8"))
    entries = []
    for e in data.get("priorityList", []):
        if e.get("hide"):
            continue
        action = e.get("action", {})
        cond = action.get("condition")
        for sid, extra in actions_of(action):
            if sid not in by_id:
                dropped.add(sid)
                continue
            rid = rank1(by_id[sid])
            c = Conv(by_id, rid)
            g = c.conv(cond)
            if g == FALSE:
                continue                     # can never fire in a long fight
            gates = [] if g in (TRUE, UNK) else (g["g"] if g["t"] == "all" else [g])
            if g == UNK:
                c.delegated = True
            if extra == "dot":
                gates.append({"t": "dot", "id": rid})
            tiers = [name for name, k in TIERS if c.tier(cond, k) is not False]
            e = {"id": rid, "gates": gates, "delegated": c.delegated, "tiers": tiers}
            if e not in entries:             # a sim list repeats a line per talent variant
                entries.append(e)
    return entries


def convert_pin(stem, chains, unresolved):
    """Hand pins: SimC syntax, classified by the retail generator's own condition parser
    (classify_if / count_fails) with tokens resolved against the Forever class chains."""
    resolve = lambda tok: rank1(chains[tok]) if tok in chains else None  # noqa: E731
    entries = []
    for line in open(os.path.join(PINS, stem + ".simc"), encoding="utf-8"):
        m = re.match(r"actions\+?=/?([a-z0-9_]+)(?:,if=(.*))?$", line.strip())
        if not m or m.group(1) in cfa.SKIP:
            continue
        rid = resolve(m.group(1))
        if not rid:
            unresolved.append(f"{stem}: {m.group(1)}")
            continue
        cond = m.group(2) or ""
        gates, delegated = gsr.classify_if(cond, resolve) if cond else ([], False)
        tiers = [n for n, k in TIERS if not (cond and gsr.count_fails(cond, k))]
        entries.append({"id": rid, "gates": gates, "delegated": delegated, "tiers": tiers})
    return entries


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(int(v)) if float(v).is_integer() else repr(v)
    if isinstance(v, str):
        return '"' + v + '"'
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    return "{" + ",".join(f"{k}={lua(x)}" for k, x in v.items()) + "}"


def tier_lists(entries):
    lists = {t: [] for t, _ in TIERS}
    for e in entries:
        for t in e["tiers"]:
            lists[t].append(e)
    out = {"st": lists["st"]}
    if lists["aoe"] != lists["st"]:
        out["aoe"] = lists["aoe"]
    if lists["cleave"] != out.get("aoe", lists["st"]):
        out["cleave"] = lists["cleave"]
    return out


def entry_lua(e, names):
    parts = [f"id={e['id']}", "gates=" + lua(e["gates"])]
    if e["delegated"]:
        parts.append("delegated=true")
    return "      {" + ",".join(parts) + "},  -- " + names.get(str(e["id"]), "?")


def main():
    names = {r["ID"]: r["Name_lang"] for r in cfa.rows("SpellName")}
    secs = {r["ID"]: int(r["Duration"] or 0) / 1000 for r in cfa.rows("SpellDuration")}
    for r in cfa.rows("SpellMisc"):
        d = secs.get(r["DurationIndex"], 0)
        if d > 0 and r["SpellID"].isdigit():
            DURATION[int(r["SpellID"])] = round(d, 1)
    commit = open(os.path.join(SRC, "UPSTREAM_COMMIT")).read().strip()
    body, chains_out, report, unresolved, abilities = [], {}, [], [], {}
    for cls in sorted(TREES):
        default, trees = TREES[cls]
        chains, by_id = cfa.class_chains(cfa.CLASS_MASK[cls])
        # EVERY learnable chain of the class, not just the list entries: the runtime
        # resolves any curated id (defensives, gap closers, interrupts...) to the rank the
        # player presses through these.
        for chain in chains.values():
            if len(chain) > 1:
                chains_out[rank1(chain)] = [int(i) for i, _ in chain]
        # Every class ability (rank 1): what a bar spell must be to join the pool, so a
        # profession, tracking or racial spell on the bars never reaches the queue.
        # Damage racials join too (cfa.RACIAL_ROLES); the rest stay out.
        abilities[cls] = sorted({rank1(chain) for chain in chains.values()}
                                | set(cfa.racial_ids("offensive")))
        body.append(f'  ["{cls.upper()}_F"] = {{')
        body.append(f'    default = "{default}",')
        for tree in sorted(trees):
            src, dropped = trees[tree], set()
            if src.startswith("pin:"):
                entries = convert_pin(src[4:], chains, unresolved)
            else:
                entries = convert_sim(src, by_id, dropped)
            for sid in ADD.get(cls, []):
                if not any(e["id"] == sid for e in entries):
                    entries.append({"id": sid, "delegated": False, "tiers": [t for t, _ in TIERS],
                                    "gates": [{"t": "buff", "id": sid, "dur": DURATION.get(sid), "neg": True}]})
            add_extras(cls, tree, entries, chains, unresolved)
            for sid in reversed(AOE_LEAD.get(cls, [])):
                if not any(e["id"] == sid for e in entries):
                    entries.insert(0, {"id": sid, "delegated": False, "tiers": list(AOE_LEAD_TIERS), "gates": []})
            entries.sort(key=lambda e: 0 if keeps_own_buff(e) else 1)   # stable: sim order otherwise
            lists = tier_lists(entries)
            body.append(f"    {tree} = {{  -- {src}")
            for t, _ in TIERS:
                if t in lists:
                    body.append(f"      {t} = {{")
                    body += ["  " + entry_lua(e, names) for e in lists[t]]
                    body.append("      },")
            body.append("    },")
            gated = sum(1 for e in entries if e["gates"])
            deleg = sum(1 for e in entries if e["delegated"])
            drop = ", ".join(f"{names.get(str(s), '?')} ({s})" for s in sorted(dropped))
            report.append(f"{cls:8s} {tree:14s} {len(entries):3d} entries {gated:3d} gated "
                          f"{deleg:3d} delegated  dropped: {drop or '-'}")
        body.append("  },")

    rank_lines = [f"  [{k}] = {lua(v)}," for k, v in sorted(chains_out.items())]
    # tools/ is not packaged (.pkgmeta), so the MIT notice must travel inside this file.
    mit = ["--   " + l.rstrip() if l.strip() else "--" for l in
           open(os.path.join(SRC, "LICENSE"), encoding="utf-8").read().strip().splitlines()]
    text = "\n".join([
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2024-2026 wealdly",
        "--",
        "-- JustAC: WoW Forever priority lists, per class and talent tree, with secret-safe",
        "-- gates. GENERATED by tools/gen_forever_rotations.py - do not edit by hand.",
        "--",
        "-- Orderings and conditions derive from the wowsims rotation files of",
        f"-- github.com/ElliotWood/Forever (commit {commit}), vendored in tools/forever-apl-src/,",
        "-- used under its license:",
        "--",
        *mit,
        "--",
        "-- Trees marked pin: are JustAC hand pins (tools/simc-apl-forever/).",
        "-- Keys: <CLASS>_F -> tree -> st / cleave / aoe (omitted = same as the next wider tier).",
        "-- Ids are rank 1; rankChains lists every rank so the runtime can show the highest known.",
        "",
        "local RotationImport = LibStub(\"JustAC-RotationImport\", true)",
        "if not RotationImport or not RotationImport.RegisterForever then return end",
        "",
        "RotationImport.RegisterForever({",
        *body,
        "}, {",
        *rank_lines,
        "}, {",
        *[f'  ["{c.upper()}_F"] = {lua(v)},' for c, v in sorted(abilities.items())],
        "})",
        "",
    ])
    if "--print" in sys.argv:
        print(text)
    else:
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote", OUT)
    print("\n".join(report))
    if unresolved:
        print("UNRESOLVED hand-pin tokens:\n  " + "\n  ".join(unresolved))
        sys.exit(1)


if __name__ == "__main__":
    main()
