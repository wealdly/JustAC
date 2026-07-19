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
# Interrupts are handled by JustAC's dedicated interrupt system (Data/InterruptAbilities.lua),
# NOT the rotation queue, so the pure interrupt tokens are skipped here - EXCEPT avengers_shield,
# which is also Protection Paladin's core rotational builder and must keep ranking.
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
counterspell kick pummel mind_freeze wind_shear skull_bash rebuke disrupt muzzle quell
silence solar_beam spear_hand_strike counter_shot spell_lock
""".split())

# Defensives, tank active-mitigation, gap-closers/movement, and pure utility - all owned
# by JustAC's own systems (DefensiveEngine / GapCloserEngine), so they must not clutter the
# damage rotation. Grounded against SpellDB.CLASS_DEFENSIVE_DEFAULTS / CLASS_GAPCLOSER_DEFAULTS.
# ONLY unambiguously non-offensive abilities are here: anything with a real DPS role is kept,
# even if defensive-flavored (death_strike, soul_cleave, fiery_brand, eye_of_tyr, shadowstrike,
# fel_rush, felblade, harpoon, infernal_strike, flying_serpent_kick, touch_of_karma). NOTE the
# token `metamorphosis` is deliberately NOT here - it is Havoc's DPS burst as well as Vengeance's
# survival CD, and SKIP is by token (global), so cutting it would break Havoc.
SKIP |= set("""
ardent_defender barkskin celestial_brew charge chi_torpedo demon_spikes desperate_prayer
earth_elemental heroic_leap ignore_pain ironfur last_stand purifying_brew regrowth roll
rune_tap shield_block shield_wall sprint tombstone vampiric_blood verdant_embrace word_of_glory
stealth bloodlust heroism spiritwalkers_grace lightning_shield natures_swiftness
hover black_ox_brew
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
    # Cast ids not name-reachable in the spec universe (export-gapped trait node, form
    # variant, rework, or an old same-name spell shadows it). Ground-truthed against JustAC's
    # own generated Data tables. NOTE: actionbar-override abilities (Annihilation, Death Sweep,
    # Thunder Blast, Tempest, Crushing Blow, Comet Storm, Hammer of Light, Templar's Slash,
    # Primordial Storm, ...) are NOT listed here - SimcBridge now resolves them automatically
    # from the DB2 override effects (SpellEffect EffectAura=332, followed through the cast's
    # trigger chain), so they need no curation and auto-refresh each patch.
    "DEATHKNIGHT_1": {"blooddrinker": 206931, "bonestorm": 194844, "rune_tap": 194679, "tombstone": 219809},
    "DEATHKNIGHT_3": {"raise_abomination": 288853, "summon_gargoyle": 49206, "unholy_assault": 207289},
    "DEMONHUNTER_1": {"fel_barrage": 258925, "glaive_tempest": 342817, "reavers_glaive": 442294},
    "DEMONHUNTER_2": {"bulk_extraction": 320341, "reavers_glaive": 442294, "shear": 203782},
    "DRUID_1": {"full_moon": 274283, "half_moon": 274282, "stellar_flare": 202347, "warrior_of_elune": 202425},
    "DRUID_3": {"pulverize": 80313, "thrash_bear": 77758, "swipe_bear": 213771},
    "HUNTER_1": {"bloodshed": 321530, "call_of_the_wild": 359844, "multishot": 2643},
    "HUNTER_3": {"butchery": 212436, "coordinated_assault": 360952, "flanking_strike": 269751,
                 "mongoose_bite": 259387, "raptor_bite": 186270, "spearhead": 360966},
    "MAGE_2": {"phoenix_flames": 257541},
    "MAGE_3": {"glacial_spike": 199786},
    "MONK_2": {"invoke_chiji": 325197},
    "PALADIN_2": {"holy_armaments": 432459},
    "PALADIN_3": {"divine_hammer": 198034, "final_reckoning": 343721,
                  "justicars_vengeance": 215661, "templar_strike": 407480},
    # devouring_plague 369128 (a valid DP record), void_bolt 205448 confirmed; void_eruption
    # left as residue (228260 resolves to the Voidform buff, not the cast - unconfirmed).
    "PRIEST_3": {"devouring_plague": 369128, "mindbender": 123040, "void_bolt": 205448},
    "ROGUE_2": {"coup_de_grace": 441776},
    "ROGUE_3": {"coup_de_grace": 441776, "rupture": 1943, "shuriken_tornado": 277925, "symbols_of_death": 212283},
    "WARLOCK_2": {"infernal_bolt": 434506, "ruination": 434635},
    "WARLOCK_3": {"infernal_bolt": 434506, "ruination": 434635},
    # crusade left as residue: the only confident candidate (231895) is the Avenging Wrath
    # record, not a distinct Crusade cast - avoid emitting a wrong id.
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
_COUNT_ATOM = re.compile(r'(?:active_enemies|spell_targets(?:\.\w+)?|desired_targets)'
                         r'\s*(>=|>|=|<=|<|!=)\s*(\d+)')


def _count_ok(op, n, k):
    return {">=": k >= n, ">": k > n, "=": k == n,
            "<=": k <= n, "<": k < n, "!=": k != n}[op]


def call_applies(cond, k):
    """Does a call's target-count gate hold at k enemies? Non-target-count clauses
    (hero tree / talent / variable) are ignored so those branches collapse in."""
    for m in _COUNT_ATOM.finditer(cond):
        if not _count_ok(m.group(1), int(m.group(2)), k):
            return False
    return True


def tier_excludes(expr, k):
    """True when a TOP-LEVEL (&-joined, non-OR) atom of an entry's own if= is a bare
    target-count comparison that fails at k enemies - so the entry does not apply at
    this tier and must be dropped (an AoE-only spender must not leak into the ST list).
    A count inside an OR (`active_enemies>3|buff.x.up`) is left in place: it is not a
    necessary condition, so classify handles it as a normal/delegated gate."""
    for atom in split_and(expr):
        a = atom.strip().lstrip("!")
        if "|" in a or "(" in a:
            continue
        m = _COUNT_ATOM.fullmatch(a)
        if m and not _count_ok(m.group(1), int(m.group(2)), k):
            return True
    return False


# --- flatten -----------------------------------------------------------------
def make_entry(token, mods, resolve, unresolved, k):
    if token in SKIP or token.startswith("variable"):
        return None
    if tier_excludes(mods.get("if", ""), k):
        return None  # entry-level target-count gate excludes it at this tier
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


def build_varmap(lists):
    """name -> value expression, for `actions=variable,name=X,value=...` definitions
    (used to see through a call guarded by `variable.X` to what X actually tests)."""
    vm = {}
    for lst in lists.values():
        for token, mods in lst:
            if token == "variable" and mods.get("name") and "value" in mods:
                vm.setdefault(mods["name"], mods["value"])
    return vm


_PHASE_LEAF = re.compile(r'^(time|fight_remains|gcd|prev_gcd|prev)\b')


def phase_gate(cond):
    """True when a condition only holds in a narrow fight-PHASE window (opener/ender):
    every leaf across its & and | is a time/fight_remains/gcd/prev term, with no combat
    state. Such a line (`arcane_barrage,if=fight_remains<2`) must not define a spell's
    steady-state priority rank - it is deferred below the normal-condition entries."""
    atoms = split_and(cond)
    if not atoms:
        return False
    for a in atoms:
        for leaf in a.lstrip("!").split("|"):
            leaf = leaf.strip().strip("()").lstrip("!")
            if leaf and not _PHASE_LEAF.match(leaf):
                return False
    return True


def branch_defer(cond, varmap):
    """True when a call POSITIVELY requires a tier SET BONUS (directly, or via a variable
    that expands to one). Set bonuses are transient tier gear, so a set-bonus-specific list
    must not out-rank the base rotation - defer it so the base list defines ranks and the
    set-bonus-only extras append after. A NEGATED set-bonus (`!variable.X` / `!set_bonus`)
    is the default no-set branch and must keep ranking, so only positive references defer."""
    for m in re.finditer(r'(!?)(?:variable\.(\w+)|set_bonus\.\w+)', cond):
        neg, var = m.group(1) == "!", m.group(2)
        has_set = ("set_bonus" in varmap.get(var, "")) if var else True
        if has_set and not neg:
            return True
    return False


def flatten(lists, k, resolve, unresolved, varmap):
    """Priority list for k enemies: walk the call graph from `main`. Each entry is tagged
    with a defer level - 0 for normal steady-state priority, 1 for phase-gated (opener/
    ender) lines and set-bonus branch lists - then ordered defer-0 first (stable by walk
    order), deduped first-wins. A list reached at a lower defer than before is re-walked so
    a shared sub-list (cooldowns / pre_cd) keeps its real rank even if a deferred branch
    reached it first."""
    occ, visited, seq = [], {}, [0]

    def walk(name, defer):
        if visited.get(name, 99) <= defer:
            return
        visited[name] = defer
        for token, mods in lists.get(name, []):
            cond = mods.get("if", "")
            if token in ("call_action_list", "run_action_list"):
                target = mods.get("name")
                if target and call_applies(cond, k):
                    child = 1 if (defer or phase_gate(cond) or branch_defer(cond, varmap)) else 0
                    walk(target, child)
            else:
                e = make_entry(token, mods, resolve, unresolved, k)
                if e:
                    d = 1 if (defer or phase_gate(cond)) else 0
                    occ.append((d, seq[0], e))
                    seq[0] += 1

    walk("main", 0)
    occ.sort(key=lambda x: (x[0], x[1]))   # defer-0 first, stable within a defer class
    out, seen = [], set()
    for _d, _s, e in occ:
        if e["id"] not in seen:
            seen.add(e["id"])
            out.append(e)
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


def _selftest():
    # tier_excludes: bare top-level count atom drops the entry off the wrong tier;
    # an OR-embedded count is not a hard gate and must be kept.
    assert tier_excludes("active_enemies>=3", 1) and not tier_excludes("active_enemies>=3", 3)
    assert tier_excludes("spell_targets<=2", 3) and not tier_excludes("spell_targets<=2", 1)
    assert not tier_excludes("active_enemies>=3|buff.x.up", 1)     # OR -> not a hard gate, keep
    assert tier_excludes("buff.x.up&active_enemies>=3", 1)         # AND count fails at k=1 -> drop
    assert not tier_excludes("", 1) and not tier_excludes("buff.x.up", 1)
    # phase_gate: opener/ender-only lines defer; anything with combat state does not.
    assert phase_gate("fight_remains<2") and phase_gate("time<4")
    assert phase_gate("fight_remains<8|gcd.max") and not phase_gate("buff.x.up&fight_remains<2")
    assert not phase_gate("") and not phase_gate("cooldown.x.ready")
    # branch_defer: a set-bonus gate (direct or via a variable) defers the branch.
    assert branch_defer("set_bonus.tww3_4pc&spell_targets=1", {})
    assert branch_defer("variable.t&spell_targets=1", {"t": "hero_tree.x&set_bonus.tww3_4pc"})
    assert not branch_defer("variable.t", {"t": "buff.x.up"}) and not branch_defer("buff.x.up", {})


def main():
    _selftest()
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
        varmap = build_varmap(lists)

        tier_lists = {ctx: flatten(lists, k, resolve, unresolved, varmap) for ctx, k in TIERS}
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
    # A single-spec (--spec) run only builds ONE spec; writing that over the shipped
    # file would wipe every other spec. Refuse to overwrite the full data file in that
    # case unless SIMC_OUT is set explicitly (--print still shows the result).
    out_path = os.environ.get("SIMC_OUT")
    if not out_path and only:
        out_path = None
        print("NOTE: --spec is a single-spec preview; not overwriting Data/SimcRotations.lua.")
        print("      Set SIMC_OUT=<path> to write, or run without --spec to regenerate all.")
    elif not out_path:
        out_path = os.path.join(ROOT, "Data", "SimcRotations.lua")
    if out_path:
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
    print("%s  (%d specs, %d total unresolved tokens across all specs)"
          % ("wrote " + out_path if out_path else "(no file written)", len(all_specs), tot_res))

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
