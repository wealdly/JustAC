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
import gen_forever_defaults as gfd  # noqa: E402  (BURST: offensive cooldowns join the bar pool)

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
# move: the ability is already on the sim list - take that entry, with its own conditions, to
# the front instead of adding a second one.
EXTRA = {
    "warrior": [dict(spell="demoralizing_shout", tiers=["cleave", "aoe"], at="front", gates=["dot"])],
    # Serpent Sting opens: its DoT lands at once, and it is cast WITH Auto Shot, which is off the
    # GCD and follows it as the hunter's main damage; once running Auto Shot sinks with its timer.
    "hunter": [dict(spell="serpent_sting", at="front", move=True),
               dict(spell="auto_shot", at="front"),
               dict(spell="hunters_mark", at="front", gates=["dot"]),
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


# Resource-for-a-price presses, by ability name; every one is flagged w ("offer only when the
# gates hold": when they fail it trails the queue instead of waiting as a sunk "soon").
#   starved: its sim mana line widens to "or the rotation cannot be paid for" (read per build) -
#            a fixed mana line misses a low-level caster whose filler costs a fifth of the bar.
#   health:  only with health above this percent - it costs health (Life Tap, Bloodrage) or
#            burns the caster too (Hellfire).
REGATE = {
    "warlock": {"life_tap": dict(starved=True, health=50), "hellfire": dict(health=50)},
    "mage": {"evocation": dict(starved=True)},
    "druid": {"innervate": dict(starved=True)},
    "warrior": {"bloodrage": dict(health=50)},
}


def regate(cls, entries, chains):
    for name, spec in REGATE.get(cls, {}).items():
        chain = chains.get(name)
        sid = chain and rank1(chain)
        for e in entries:
            if e["id"] != sid:
                continue
            gates = list(e["gates"])
            if spec.get("starved"):
                power = [g for g in gates if g["t"] == "power" and g.get("res") == "mana"]
                gates = [g for g in gates if g not in power]
                gates.insert(0, {"t": "any", "g": power + [{"t": "starved"}]} if power else {"t": "starved"})
            if spec.get("health"):
                gates.append({"t": "health", "op": ">", "pct": float(spec["health"])})
            e["gates"], e["w"] = gates, True


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
        if not sid:
            continue
        mine = next((e for e in entries if e["id"] == sid), None)
        if mine and x.get("move") and x.get("at") == "front":
            entries.remove(mine)
            fronts.append(mine)
            continue
        if mine:
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
LOST = {}   # id(entry) -> condition nodes given up, for --audit


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
    right. Value-vs-value ("dot remaining <= its cast time") keeps the left value with no
    constant (n None): a rule that does not need the number can still read it."""
    op = OPS.get(val.get("op"))
    lhs, rhs = val.get("lhs", {}), val.get("rhs", {})
    if "const" in rhs and "const" not in lhs:
        side, n = lhs, num(rhs["const"])
    elif "const" in lhs and "const" not in rhs:
        side, n, op = rhs, num(lhs["const"]), FLIP.get(op)
    elif "const" not in lhs and "const" not in rhs:
        side, n = lhs, None
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
        self.lost = []           # the condition nodes given up (tools audit: why delegated)

    def lose(self, node):
        self.delegated = True
        self.lost.append(json.dumps(node, separators=(",", ":"))[:160])

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
        # "not my own DoT up" (Rend, Flame Shock) is exactly that gate. "Not my OTHER debuff
        # up" (Bane of Agony unless Bane of Doom) holds while that one is unknown: a low-level
        # character casts the line; one who has learned it lets that one own the slot.
        # "Not another class's debuff up" (Sunder unless Expose Armor) holds solo, where
        # nobody else applies it.
        # ponytail: in a group the other class's debuff is invisible here; Sunder still shows.
        if t == "dot":
            if g.get("id") == self.self_id:
                return g
            if g.get("id") in self.by_id:
                return {"t": "known", "id": g["id"], "neg": True}
            return TRUE
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
                    self.lose(x)
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
                    self.lose(x)
                    return TRUE
                if g != FALSE:
                    out.append(g)
            return FALSE if not out else (out[0] if len(out) == 1 else {"t": "any", "g": out})
        if key == "not":
            g = self.negate(self.conv(val.get("val")))
            if g == UNK:
                self.lose(node)
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
            aid = self.rank1(sid_of(val.get("auraId")))
            if not aid:
                self.lose(node)
                return TRUE
            # My own aura (Faerie Fire, Demoralizing Roar): refreshed as it drops, which is the
            # dot / buff gate on Forever (timed from the cast). Someone else's: given up.
            if aid != self.self_id:
                self.lose(node)
            if val.get("sourceUnit", {}).get("type") == "CurrentTarget":
                return {"t": "dot", "id": aid}
            return self.buff(aid, True)
        if key == "frontOfTarget":
            # Solo levelling, the mob faces you: Claw (front) yes, Shred (behind) no.
            # ponytail: a tank-held mob turns its back; a group-aware check needs facing data.
            return TRUE
        return UNK

    def cmp(self, val):
        op, name, n, side = cmp_parts(val)
        if op is None or name is None:
            return UNK
        if name in ("auraRemainingTime", "dotRemainingTime"):
            return self.remaining(op, name, side, val)
        if n is None and "remainingTime" in json.dumps(val):
            # Mana paced against fight length (Lightning Bolt: mana >= time left * 35): the
            # fight length is unknowable, so no pacing - as remainingTime vs a constant above.
            return TRUE
        if name == "math":
            # Resource pooling arithmetic (Ferocious Bite: energy + regen vs its cost + Shred's):
            # the button's own cost decides whether it can be pressed.
            # ponytail: pools nothing; a real pool needs the plain energy-tick timer.
            return TRUE
        if n is None:
            return UNK
        if name == "unitDistance" and op in ("<", "<="):
            # Point-blank AoE (Arcane Explosion, Hellfire, Blast Wave) only with the target close.
            return {"t": "near", "n": n}
        if name == "totemRemainingTime" and op in ("<", "<=") and n <= 1:
            # "This element's totem is down": my own totem, timed from its cast like a buff.
            # ponytail: a totem killed early or replaced by another of its element reads up.
            return self.buff(self.self_id, True) if self.self_id else UNK
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


    def remaining(self, op, name, side, val):
        """auraRemainingTime / dotRemainingTime vs a constant or another value (cast time)."""
        raw = sid_of(side.get("auraId") or side.get("spellId"))
        sid = self.rank1(raw)
        if not sid:
            return UNK
        target = name == "dotRemainingTime" or side.get("sourceUnit", {}).get("type") == "CurrentTarget"
        # "My own DoT about to run out" (Immolate if its time left <= its cast time) IS the dot
        # gate on Forever: an early recast overwrites the ticks left, so it is refreshed as it
        # drops (DotTracker times it from the cast; no secret read, nothing delegated).
        if target and sid == self.self_id and op in ("<", "<="):
            return {"t": "dot", "id": sid}
        # Likewise my own buff about to drop (Slice and Dice, a seal): its window is timed from
        # my cast, so "not up" is the refresh.
        if not target and sid == self.self_id and op in ("<", "<="):
            return self.buff(sid, True)
        # My OTHER buff about to drop (Judgement / Seal of Command as Seal of Righteousness runs
        # out: level-60 seal twisting): the timing detail is dropped, that buff's own line keeps
        # it up. Never "not up": Judgement needs the seal it consumes.
        if not target and sid in self.by_id and op in ("<", "<=") and on_self(raw):
            return TRUE
        self.lose({"cmp": val})              # remaining time itself is secret
        if target:
            return {"t": "dot", "id": sid}
        return self.buff(sid, op in ("<", "<="))


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
                c.lose(cond)
            if extra == "dot":
                gates.append({"t": "dot", "id": rid})
            tiers = [name for name, k in TIERS if c.tier(cond, k) is not False]
            e = {"id": rid, "gates": gates, "delegated": c.delegated, "tiers": tiers}
            if e not in entries:             # a sim list repeats a line per talent variant
                entries.append(e)
                LOST[id(e)] = c.lost
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


# What makes a bar spell a DPS ability for the queue: it deals damage (SpellEffect spell /
# weapon / leech damage or Attack, aura periodic damage / leech, an area trigger aimed at
# enemies: Volley, Hurricane, Blizzard), followed through triggered spells. An enemy effect
# that deals none (crowd control, taunts, curses and weakening debuffs, mana drains) is no DPS
# press: the ones that are (Hunter's Mark, Faerie Fire, Sunder) are on the lists, interrupts and
# CC have their own slot, gap closers their own queue. Or it is a combat-length self buff or summon (under
# gen_forever_defaults.SHORT_BUFF_SECS: Sweeping Strikes, seals, totems), the same cut that
# keeps a buff in the combat queue; or a combat form (stances, Shadowform, Bear / Cat Form -
# not the travel forms); or a trap (placed object). Other self-only spells (tracking, travel,
# pet care, conjuring, hour-long buffs) join only from the class's lists or the burst cooldowns.
DMG_EFFECTS = {2, 9, 17, 31, 58, 78, 121}
DMG_AURAS = {3, 53, 89}
AREA_TRIGGER = 179
ENEMY_TARGETS = {6, 15, 16, 24, 28, 53, 54}   # ImplicitTarget: enemy unit / area / cone
SELF_TARGETS = {1, 20}                        # ImplicitTarget: the caster / caster's party
APPLY_AURA, SUMMON, PLACE_OBJECT = 6, 28, 104
SHAPESHIFT = 36
TRAVEL_FORMS = {3, 4, 16, 27, 29}   # shapeshift form ids: Travel, Aquatic, Ghost Wolf, flight
_effects = None


def effects_of(sid):
    """SpellEffect rows of sid as (effect, aura, trigger spell, implicit targets, misc value)."""
    global _effects
    if _effects is None:
        _effects = {}
        for r in cfa.rows("SpellEffect"):
            _effects.setdefault(r["SpellID"], []).append(
                (int(r["Effect"] or 0), int(r["EffectAura"] or 0), r.get("EffectTriggerSpell") or "0",
                 {int(r["ImplicitTarget_0"] or 0), int(r["ImplicitTarget_1"] or 0)},
                 int(r["EffectMiscValue_0"] or 0)))
    return _effects.get(str(sid), [])


def on_self(sid):
    """Does sid put an aura on the caster (a seal), not on an enemy (Fire Vulnerability)?"""
    return any(eff == APPLY_AURA and targets & SELF_TARGETS for eff, _, _, targets, _ in effects_of(sid))


def deals_damage(sid, depth=0):
    for eff, aura, trig, targets, _ in effects_of(sid):
        if eff in DMG_EFFECTS or aura in DMG_AURAS or (eff == AREA_TRIGGER and targets & ENEMY_TARGETS):
            return True
        if depth < 2 and trig not in ("", "0") and deals_damage(trig, depth + 1):
            return True
    return False


def combat_buff(sid):
    """A self / party aura or a summon lasting under SHORT_BUFF_SECS (DURATION: rank 1), a
    combat form, or a trap."""
    effects = effects_of(sid)
    if any(eff == APPLY_AURA and aura == SHAPESHIFT and form not in TRAVEL_FORMS
           for eff, aura, _, _, form in effects):
        return True
    if any(eff == PLACE_OBJECT for eff, *_ in effects):
        return True
    if not 0 < DURATION.get(sid, 0) < gfd.SHORT_BUFF_SECS:
        return False
    return any((eff == APPLY_AURA and targets & SELF_TARGETS) or eff == SUMMON
               for eff, _, _, targets, _ in effects)


def entry_lua(e, names):
    parts = [f"id={e['id']}", "gates=" + lua(e["gates"])]
    if e["delegated"]:
        parts.append("delegated=true")
    if e.get("w"):
        parts.append("w=true")
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
        # The class's combat abilities (rank 1): what a bar spell must be to join the pool, so
        # tracking, travel, profession or utility spells on the bars never reach the queue.
        # Abilities that deal damage or are combat buffs (deals_damage, combat_buff), the
        # curated burst cooldowns and damage racials (cfa.RACIAL_ROLES); list entries join below.
        # Racials join by that role only: Escape Artist passes as a short self buff, but it is
        # defensive, and an unclassified one (Rapid Regeneration) belongs to no combat queue.
        pool = {rank1(chain) for chain in chains.values()
                if any(deals_damage(i) for i, _ in chain) or combat_buff(rank1(chain))}
        pool -= {i for ids in cfa.racials().values() for i in ids}
        pool |= {rank1(chains[n]) for n in gfd.BURST.get(cls, []) if n in chains}
        pool |= set(cfa.racial_ids("offensive"))
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
            regate(cls, entries, chains)
            for sid in reversed(AOE_LEAD.get(cls, [])):
                if not any(e["id"] == sid for e in entries):
                    entries.insert(0, {"id": sid, "delegated": False, "tiers": list(AOE_LEAD_TIERS), "gates": []})
            entries.sort(key=lambda e: 0 if keeps_own_buff(e) else 1)   # stable: sim order otherwise
            lists = tier_lists(entries)
            pool |= {e["id"] for e in entries}
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
            if "--audit" in sys.argv:   # why each delegated entry is (it can never lead)
                for e in entries:
                    if e["delegated"]:
                        lost = LOST.get(id(e)) or ["(hand pin: see the .simc line)"]
                        report.append(f"    {names.get(str(e['id']), '?')} ({e['id']}): " + " | ".join(lost))
        body.append("  },")
        abilities[cls] = sorted(pool)

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
