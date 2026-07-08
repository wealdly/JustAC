#!/usr/bin/env python3
# tools/gen_simc_rotations.py
#
# Generate per-spec SimC PRIORITY LISTS (ordered, with secret-safe gates) for every
# spec, to REFINE Blizzard's Assisted Combat fixed queue - reorder positions 2+ by
# SimC priority rank and gate each entry by the conditions we can actually evaluate.
# This is NOT a replacement queue: the ORDER and the secret-safe gates are the
# product; resource/duration conditions delegate to AC (which reads the real state).
#
# Per spec we emit up to three context lists matching JustAC's engaged-enemy tiers:
#   st (1 target) / cleave (2) / aoe (3+).
# A context list is omitted when identical to another (the runtime falls back
# aoe->st, cleave->aoe->st), so specs that don't distinguish cleave stay lean.
#
# Pipeline per ActionPriorityLists/default/<class>_<spec>.simc:
#   parse -> flatten the call graph per target tier (target-count gates decide which
#   calls apply at k enemies; hero-tree/talent branches collapse in, IsPlayerSpell
#   sorts them at runtime) -> resolve tokens to spell ids via tools/simc_bridge
#   (client-data universe + curated residue) -> classify each if= into secret-safe
#   gates -> emit Data/SimcRotations.lua.
#
# Unresolved tokens are REPORTED, never fatal: an ability we can't resolve simply
# isn't ranked and keeps AC's order (fail-safe). Curate core-spell misses in CURATED.
#
# Usage: python tools/gen_simc_rotations.py [--print] [--spec druid_feral]
import re, os, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APL_DIR = os.path.join(ROOT, "tools", "simc-apl")
CSV_DIR = os.path.join(ROOT, "Documentation", "wow_spell_csv")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from simc_bridge import SimcBridge, slug, CLASS_ID  # noqa: E402

TIERS = [("st", 1), ("cleave", 2), ("aoe", 3)]

# Non-rotational actions to skip (flow control, racials, trinkets, forms, setup).
SKIP = set("""
variable snapshot_stats sequence strict_sequence wait wait_until_ready pool_resource
cycling_variable retarget_auto_attack auto_attack auto_shot start_moving stop_moving
move_to_max_range pick_up_fragment use_item use_items potion healthstone health_potion
cancel_buff cancel_action invoke_external_buff do_treacherous_transmitter_task
any_dnd any_blink call_action_list run_action_list
berserking blood_fury arcane_torrent ancestral_call fireblood bag_of_tricks
lights_judgment gift_of_the_naaru stoneform will_of_the_forsaken haymaker
rocket_barrage arcane_pulse bag trinket1 trinket2 counterstrike_totem
cat_form bear_form moonkin_form travel_form prowl shadowmeld summon_pet apply_poison
""".split())

# Per-spec curated token->id residue: form variants (_cat/_bear), talent override
# chains whose SimC cast id is downstream of the trait definition, cross-spec name
# collisions, and SimC short aliases. The client-data universe auto-resolves the
# rest and refreshes between patches. Grow this from the coverage report's residue.
CURATED = {
    "DRUID_2": {  # Feral
        "swipe_cat": 106785, "thrash_cat": 106830, "moonfire_cat": 155625,
        "berserk": 106951, "brutal_slash": 202028, "adaptive_swarm": 391888,
        "incarnation": 102543, "bs_inc": 106951,
    },
}


# --- parse -------------------------------------------------------------------
def parse_apl(text):
    """list_name -> [ (token, mods_dict) ] in file order."""
    lists = {}
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r'^actions(?:\.(\w+))?\+?=/?(.+)$', line)
        if not m:
            continue
        lname = m.group(1) or "main"
        parts = m.group(2).split(",")
        mods = {}
        for p in parts[1:]:
            if "=" in p:
                k, v = p.split("=", 1)
                mods[k.strip()] = v.strip()
        lists.setdefault(lname, []).append((parts[0].strip(), mods))
    return lists


# --- gate classification -----------------------------------------------------
def split_and(expr):
    atoms, depth, cur = [], 0, ""
    for ch in expr:
        if ch == "(":
            depth += 1; cur += ch
        elif ch == ")":
            depth -= 1; cur += ch
        elif ch == "&" and depth == 0:
            atoms.append(cur); cur = ""
        else:
            cur += ch
    if cur:
        atoms.append(cur)
    return [a.strip() for a in atoms if a.strip()]


def classify_atom(atom, resolve):
    """(gate|None, delegated_bool). Target-count atoms are handled by the tier split,
    so they neither gate nor delegate here."""
    neg = atom.startswith("!")
    a = atom.lstrip("!")
    if "|" in a or "(" in a:
        return None, True  # compound / OR -> conservatively delegate
    if re.match(r'cooldown\.\w+\.(ready|up|remains)', a):
        return {"t": "cd"}, False
    m = re.match(r'dot\.(\w+)\.(refreshable|ticking|remains)', a)
    if m:
        return {"t": "dot", "id": resolve(m.group(1))}, False
    m = re.match(r'buff\.(\w+)\.(up|react|down)', a)
    if m:
        buff, suf = m.group(1), m.group(2)
        bid = resolve(buff)
        if bid:
            return {"t": "buff", "id": bid, "neg": neg or suf == "down"}, False
        return None, True  # unknown buff -> can't evaluate -> delegate
    if re.match(r'buff\.\w+\.(remains|stack)', a):
        return None, True  # aura duration / stacks are secret
    if re.match(r'(target\.health\.pct|target\.time_to_die)', a):
        return {"t": "execute", "neg": neg}, False
    if re.match(r'(spell_targets|active_enemies|desired_targets)', a):
        return None, False  # target count -> handled by the tier split
    if re.match(r'(talent|hero_tree|runeforge|set_bonus|equipped)\.', a):
        return None, False  # build gate -> IsPlayerSpell handles it, not a runtime gate
    if re.match(r'(refreshable|ticking)$', a):
        return {"t": "dot", "own": True}, False
    return None, True  # resources / time / prev_gcd / variable -> delegate


def classify_if(expr, resolve):
    gates, delegated = [], False
    for atom in split_and(expr):
        g, d = classify_atom(atom, resolve)
        if g:
            gates.append(g)
        delegated = delegated or d
    return gates, delegated


# --- tier / context ----------------------------------------------------------
def call_applies(cond, k):
    """Does a call's target-count gate hold at k enemies? Non-target-count clauses
    (hero tree / talent / variable) are ignored so those branches collapse in."""
    for m in re.finditer(r'(?:active_enemies|spell_targets(?:\.\w+)?|desired_targets)'
                         r'\s*(>=|>|=|<=|<|!=)\s*(\d+)', cond):
        op, n = m.group(1), int(m.group(2))
        ok = {">=": k >= n, ">": k > n, "=": k == n,
              "<=": k <= n, "<": k < n, "!=": k != n}[op]
        if not ok:
            return False
    return True


# --- flatten -----------------------------------------------------------------
def make_entry(token, mods, resolve, unresolved):
    if token in SKIP or token.startswith("variable"):
        return None
    sid = resolve(token)
    if not sid:
        unresolved.add(token)
        return None
    gates, delegated = classify_if(mods.get("if", ""), resolve)
    tif = mods.get("target_if", "")
    if re.search(r'(?:^|[:&|(])\s*!?(refreshable|ticking)\b', tif) or ("dot.%s." % token) in tif:
        gates.append({"t": "dot", "own": True})
    if "max_energy" in mods:
        delegated = True
    uniq = []
    for g in gates:
        if g.get("own"):
            g = {"t": "dot", "id": sid}
        if g not in uniq:
            uniq.append(g)
    return {"id": sid, "token": token, "gates": uniq, "delegated": delegated}


def flatten(lists, k, resolve, unresolved):
    """Priority list for k enemies: walk the call graph from `main`, dedup by id
    (first/highest-priority reach wins)."""
    out, seen, visited = [], set(), set()

    def walk(name):
        if name in visited:
            return
        visited.add(name)
        for token, mods in lists.get(name, []):
            if token in ("call_action_list", "run_action_list"):
                target = mods.get("name")
                if target and call_applies(mods.get("if", ""), k):
                    walk(target)
            else:
                e = make_entry(token, mods, resolve, unresolved)
                if e and e["id"] not in seen:
                    seen.add(e["id"])
                    out.append(e)

    walk("main")
    return out


# --- emit --------------------------------------------------------------------
def gate_lua(g):
    parts = ['t="%s"' % g["t"]]
    if g.get("id"):
        parts.append("id=%d" % g["id"])
    if g.get("neg"):
        parts.append("neg=true")
    return "{" + ",".join(parts) + "}"


def entry_lua(e):
    g = "{" + ",".join(gate_lua(x) for x in e["gates"]) + "}"
    d = ",delegated=true" if e["delegated"] else ""
    return "      {id=%d,gates=%s%s},  -- %s" % (e["id"], g, d, e["token"])


def entry_sig(e):
    return (e["id"], tuple(sorted((x["t"], x.get("id", 0), x.get("neg", False))
                                  for x in e["gates"])), e["delegated"])


def list_sig(lst):
    return tuple(entry_sig(e) for e in lst)


def emit_spec(speckey, contexts):
    L = ['  ["%s"] = {' % speckey]
    for ctx in ("st", "cleave", "aoe"):
        lst = contexts.get(ctx)
        if not lst:
            continue
        L.append("    %s = {" % ctx)
        for e in lst:
            L.append(entry_lua(e))
        L.append("    },")
    L.append("  },")
    return "\n".join(L)


HEADER = [
    "-- SPDX-License-Identifier: GPL-3.0-or-later",
    "-- Copyright (C) 2024-2026 wealdly",
    "--",
    "-- JustAC: imported action-priority lists (per spec, per context) with per-entry",
    "-- gates. GENERATED by tools/gen_simc_rotations.py - do not edit by hand.",
    "--",
    "-- Orderings and conditions derive from SimulationCraft (GPL-3.0,",
    "-- https://github.com/simulationcraft/simc); the pinned source APLs live in",
    "-- tools/simc-apl/ as the corresponding source. Each entry keeps the SECRET-SAFE",
    "-- gates JustAC can evaluate in 12.0 combat (cd / dot / proc-or-buff-window /",
    "-- execute). `delegated` marks a step whose SimC condition also needs a value we",
    "-- cannot read (resources, aura duration/stacks), so it falls back to priority",
    "-- order and Blizzard's live pick. Used to REFINE the AC fixed queue, not replace it.",
    "",
    'local RotationImport = LibStub("JustAC-RotationImport", true)',
    "if not RotationImport or not RotationImport.RegisterGated then return end",
    "",
    "RotationImport.RegisterGated({",
]


# --- spec resolution ---------------------------------------------------------
def spec_from_filename(name, bridge):
    """druid_feral -> ('DRUID', 'Feral', 'DRUID_2'). None if unmatched."""
    cls = None
    rest = None
    for c in CLASS_ID:
        pfx = c.lower()
        if name.startswith(pfx + "_"):
            cls, rest = c, name[len(pfx) + 1:]
            break
    if not cls:
        return None
    cid = str(CLASS_ID[cls])
    for sid, (c, nm) in bridge.SPEC.items():
        if c == cid and slug(nm) == rest:
            return cls, nm, "%s_%d" % (cls, bridge.SPEC_ORDER.get(sid, 0) + 1)
    return None


def main():
    only = None
    if "--spec" in sys.argv:
        only = sys.argv[sys.argv.index("--spec") + 1]

    bridge = SimcBridge(CSV_DIR)
    files = sorted(glob.glob(os.path.join(APL_DIR, "*.simc")))
    all_specs = {}          # speckey -> {ctx: list}
    report = []             # (name, speckey, counts, residue)
    for f in files:
        name = os.path.basename(f)[:-5]
        if only and name != only:
            continue
        info = spec_from_filename(name, bridge)
        if not info:
            report.append((name, "?", {}, ["<spec name unmatched>"]))
            continue
        cls, specname, speckey = info
        resolve = bridge.resolver(cls, specname, CURATED.get(speckey, {}))
        unresolved = set()
        lists = parse_apl(open(f, encoding="utf-8").read())

        tier_lists = {ctx: flatten(lists, k, resolve, unresolved) for ctx, k in TIERS}
        # dedup: keep st; keep aoe if != st; keep cleave only if distinct from both
        contexts = {}
        st = tier_lists["st"]
        contexts["st"] = st
        if list_sig(tier_lists["aoe"]) != list_sig(st):
            contexts["aoe"] = tier_lists["aoe"]
        cl = tier_lists["cleave"]
        if list_sig(cl) != list_sig(st) and list_sig(cl) != list_sig(contexts.get("aoe", [])):
            contexts["cleave"] = cl

        all_specs[speckey] = contexts
        counts = {c: len(v) for c, v in contexts.items()}
        # residue minus anything SKIP would have caught (dot-name refs etc. already excluded)
        report.append((name, speckey, counts, sorted(unresolved)))

    # --- write -----------------------------------------------------------------
    out_path = os.environ.get("SIMC_OUT") or os.path.join(ROOT, "Data", "SimcRotations.lua")
    body = HEADER[:]
    for speckey in sorted(all_specs):
        body.append(emit_spec(speckey, all_specs[speckey]))
    body += ["})", ""]
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(body))

    # --- report ----------------------------------------------------------------
    print("%-26s %-12s %-22s residue (unresolved castable tokens)" % ("apl", "speckey", "entries st/cl/aoe"))
    print("-" * 100)
    tot_res = 0
    for name, speckey, counts, residue in report:
        cnt = "%s/%s/%s" % (counts.get("st", 0), counts.get("cleave", "-"), counts.get("aoe", "-"))
        tot_res += len(residue)
        print("%-26s %-12s %-22s %s" % (name, speckey, cnt, " ".join(residue) if residue else "-- clean --"))
    print("-" * 100)
    print("wrote %s  (%d specs, %d total unresolved tokens across all specs)"
          % (out_path, len(all_specs), tot_res))

    if only or "--print" in sys.argv:
        for speckey, contexts in all_specs.items():
            for ctx, lst in contexts.items():
                print("\n=== %s / %s ===" % (speckey, ctx.upper()))
                for e in lst:
                    gs = " ".join(g["t"] + (":%d" % g["id"] if g.get("id") else "")
                                  + ("!" if g.get("neg") else "") for g in e["gates"]) or "-"
                    print("  %-22s [%s]%s" % (e["token"], gs, "  DELEG" if e["delegated"] else ""))


if __name__ == "__main__":
    main()
