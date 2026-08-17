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
cycling_variable retarget retarget_auto_attack auto_attack auto_shot start_moving stop_moving
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
    # Devourer: the trait-tree export joins only same-named PASSIVE shadow records
    # for these casts, so the universe walk can't reach them. CSV name+castability
    # grounded at live 12.0.7.68887 (passives excluded via SPELL_ATTR0_PASSIVE),
    # cross-checked against live rotation-guide spell ids - 2026-08-02.
    "DEMONHUNTER_3": {
        "collapsing_star": 1221150, "eradicate": 1225826, "hungering_slash": 1239123,
        "pierce_the_veil": 1245483, "predators_wake": 1259431, "reapers_toll": 1245470,
    },
    "DRUID_1": {"full_moon": 274283, "half_moon": 274282, "stellar_flare": 202347, "warrior_of_elune": 202425},
    "DRUID_3": {"pulverize": 80313, "thrash_bear": 77758, "swipe_bear": 213771},
    "HUNTER_1": {"bloodshed": 321530, "call_of_the_wild": 359844, "multishot": 2643},
    "HUNTER_3": {"butchery": 212436, "coordinated_assault": 360952, "flanking_strike": 269751,
                 "mongoose_bite": 259387, "raptor_bite": 186270, "spearhead": 360966},
    # Hero-subtree abilities the 69214 trait-tree export can't reach (same export-join
    # gap as DEMONHUNTER_3): CSV name+castability grounded, passives excluded, each id
    # cross-confirmed against Data/SpellArchetypes.lua (independent generator) - 2026-08-16.
    "EVOKER_1": {"azure_sweep": 1265872, "unbound_flame": 1292321},
    "MAGE_1": {"prismatic_bolt": 1295924},
    "MAGE_2": {"phoenix_flames": 257541},
    "MAGE_3": {"glacial_spike": 199786},
    # empty_the_cellar: TWO Monk-family candidates (1262765 / 1263438), one per hero tree.
    # 1262765 is the cross-validated damage cast (SpellArchetypes hit); 1263438 never
    # surfaces there (non-damage aura twin). Same hero-tree ambiguity as SHAMAN_2
    # ascendance; revisit if the Shado-Pan build misbehaves in game.
    "MONK_1": {"empty_the_cellar": 1262765},
    "MONK_2": {"invoke_chiji": 325197},
    # zenith 1249625 (Midnight WW cooldown, 2 charges @ 90s; single-entry node in
    # the parallel Monk tree the universe walk misses) - CSV-grounded 2026-08-02.
    "MONK_3": {"zenith": 1249625},
    # ascendance: the shared-class-tree name walk picks Elemental's 114050 inside
    # the Enhancement universe; the Enh cast is 114051 - CSV-grounded 2026-08-02.
    "SHAMAN_2": {"ascendance": 114051},
    "PALADIN_2": {"holy_armaments": 432459},
    "PALADIN_3": {"divine_hammer": 198034, "final_reckoning": 343721,
                  "justicars_vengeance": 215661, "templar_strike": 407480},
    # devouring_plague 369128 (a valid DP record), void_bolt 205448 confirmed; void_eruption
    # left as residue (228360/228361 byte-identical in every CSV column - no signal to pick;
    # the voidform burst anchor resolves through dark_ascension instead, one is enough).
    # mind_flay_insanity: override target of aura 391401 (EffectAura=332), whose owner sits
    # in an export-gapped hero node so the automatic override hop never fires.
    "PRIEST_3": {"devouring_plague": 369128, "mindbender": 123040, "void_bolt": 205448,
                 "mind_flay_insanity": 391403, "void_blast": 450983,
                 "void_volley": 1242173, "dark_ascension": 391109},
    "ROGUE_2": {"coup_de_grace": 441776},
    "ROGUE_3": {"coup_de_grace": 441776, "rupture": 1943, "shuriken_tornado": 277925, "symbols_of_death": 212283},
    "WARLOCK_1": {"malefic_grasp": 1261153},
    "WARLOCK_2": {"infernal_bolt": 434506, "ruination": 434635},
    "WARLOCK_3": {"infernal_bolt": 434506, "ruination": 434635},
    # champions_leap: core Colossus rotational damage (unconditional APL slot beside
    # champions_spear), NOT the movement gap-closer - that is Charge/Heroic Leap in
    # CLASS_GAPCLOSER_DEFAULTS. Sole SpellName match, family 4, not passive.
    "WARRIOR_3": {"champions_leap": 1271985},
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


# Discrete (countable) class resources only - see classify_atom for why continuous ones stay
# delegated. `soul_shards`/`runes` plural forms normalize to the singular token the runtime uses.
# `.deficit` (max - current) is how APLs express pooling - "don't spend while
# regeneration would be wasted". Countable resources get it for free: the runtime
# reads current AND max as plain numbers, so it is plain arithmetic there.
_RESOURCE_ATOM = re.compile(
    r'(combo_points|holy_power|chi|soul_shards?|runes?|essence|arcane_charges)'
    r'(\.deficit)?\s*(>=|<=|>|<|=|!=)\s*(\d+)')

# Continuous (bar-fill) resources. Ordered comparisons only - see classify_atom.
# `.pct` marks a value that is ALREADY a percentage (runtime skips its
# absolute->percent conversion); `.deficit` restates the threshold as max-N and
# flips the comparison, both handled at runtime where the maximum is readable.
_CONT_RESOURCE_ATOM = re.compile(
    r'(energy|rage|mana|astral_power|fury|runic_power|maelstrom|insanity|focus|pain)'
    r'(\.pct|\.deficit)?\s*(>=|<=|>|<)\s*(\d+)')


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
    # Aura STACK counts. The count itself is secret, but the engine renders an
    # application count ONLY at or above a minimum the caller names
    # (C_UnitAuras.GetAuraApplicationDisplayCount), so "is it at least N" is
    # answerable without reading it - and every comparison SimC uses reduces to one
    # or two of those questions. Unlike the power gates, `=` is expressible here
    # (>=n and not >=n+1), so it is NOT delegated.
    # `debuff.` is the TARGET's aura, `buff.` the player's - hence `tgt`.
    m = re.match(r'(buff|debuff)\.(\w+)\.stack\s*(>=|<=|>|<|=)\s*(\d+)$', a)
    if m and not neg:
        sid = resolve(m.group(2))
        if sid:
            return {"t": "stack", "id": sid, "op": m.group(3), "n": int(m.group(4)),
                    "tgt": m.group(1) == "debuff"}, False
        return None, True  # unknown aura -> can't evaluate -> delegate
    if re.match(r'(buff|debuff)\.\w+\.(remains|stack)', a):
        # Remaining DURATION is genuinely secret. A stack atom only lands here when
        # it was negated or its aura token did not resolve.
        return None, True
    # Execute WITH its percentage. SimC's APLs are the only place per-spell execute
    # thresholds exist (DB2 has no health-threshold column), and the runtime can now
    # test a target-health threshold directly - so keep the number instead of
    # collapsing every execute line into one shared "execute phase" flag.
    m = re.match(r'target\.health\.pct\s*(>=|<=|>|<)\s*(\d+)', a)
    if m and not neg:
        return {"t": "execute", "op": m.group(1), "pct": int(m.group(2))}, False
    if re.match(r'(target\.health\.pct|target\.time_to_die)', a):
        return {"t": "execute", "neg": neg}, False
    # Player health, which defensive APL lines lean on.
    m = re.match(r'health\.pct\s*(>=|<=|>|<)\s*(\d+)', a)
    if m and not neg:
        return {"t": "health", "op": m.group(1), "pct": int(m.group(2))}, False
    if re.match(r'(spell_targets|active_enemies|desired_targets)', a):
        return None, False  # target count -> handled by the tier split
    if re.match(r'(talent|hero_tree|runeforge|set_bonus|equipped)\.', a):
        return None, False  # build gate -> IsPlayerSpell handles it, not a runtime gate
    if re.match(r'(refreshable|ticking)$', a):
        return {"t": "dot", "own": True}, False
    # DISCRETE class resources (combo points, holy power, chi, shards, runes, essence, arcane
    # charges) are readable at runtime WITHOUT a secret: Blizzard's own resource bar branches on
    # the secret UnitPower in privileged code and leaves per-point `isActive` frame state behind
    # (BlizzardAPI.GetClassResourcePoints). So these become real gates instead of delegating.
    # CONTINUOUS resources (energy, rage, mana, astral_power...) are bar-fill, not points, so
    # there is nothing plain to COUNT - but a THRESHOLD is testable engine-side, which is all
    # these comparisons need. Emitted as "power", distinct from the countable "resource" gates,
    # because the runtime evaluates them differently: SimC states them in ABSOLUTE units and the
    # gate takes a percentage, so the runtime converts through UnitPowerMax (plain, read live
    # because talents move maximums). Ordered comparisons only - = and != cannot be expressed by
    # a threshold - and a negated form is left to delegation rather than risking an inverted gate.
    m = _RESOURCE_ATOM.fullmatch(a)
    if m and not neg:
        res = {"soul_shards": "soul_shard", "runes": "rune"}.get(m.group(1), m.group(1))
        return {"t": "resource", "res": res, "op": m.group(3), "n": int(m.group(4)),
                "deficit": bool(m.group(2))}, False
    m = _CONT_RESOURCE_ATOM.fullmatch(a)
    if m and not neg:
        suffix = m.group(2) or ""
        return {"t": "power", "res": m.group(1), "op": m.group(3),
                "n": int(m.group(4)), "ispct": suffix == ".pct",
                "deficit": suffix == ".deficit"}, False
    return None, True  # time / prev_gcd / variable / compound -> delegate


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
    e = {"id": sid, "token": token, "gates": uniq, "delegated": delegated}
    # Release tier for an EMPOWERED cast (`consumption,empower_to=1`). Deliberately NOT a
    # gate: it never decides WHETHER to press, only how long to hold before letting go, so
    # nothing in the runtime evaluator should ever test it. Carried as plain data for the
    # icon to show.
    emp = mods.get("empower_to", "")
    if emp.isdigit() and int(emp) > 0:
        e["empower"] = int(emp)
    return e


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
    out, seen = [], {}
    for _d, _s, e in occ:
        kept = seen.get(e["id"])
        if kept is None:
            seen[e["id"]] = e
            out.append(e)
        elif kept.get("empower") != e.get("empower"):
            # Same spell, DIFFERENT release tier. SimC chooses between those lines on
            # conditions this generator could not classify - Eternity Surge picks its tier by
            # target count against TALENT-dependent thresholds (`active_enemies<=2+2*talent.
            # eternitys_span`), which _COUNT_ATOM cannot evaluate, so every tier survives to
            # here and first-wins would ship whichever came first as if it were the answer.
            # Drop the tier instead and show none: a wrong release tier is worse than no
            # advice, and the entry itself is still correct without it.
            kept.pop("empower", None)
    return out


# --- emit --------------------------------------------------------------------
def gate_lua(g):
    parts = ['t="%s"' % g["t"]]
    if g.get("id"):
        parts.append("id=%d" % g["id"])
    if g.get("res"):
        parts.append('res="%s"' % g["res"])
    if g.get("op"):
        parts.append('op="%s"' % g["op"])
    if g.get("n") is not None:
        parts.append("n=%d" % g["n"])
    # Threshold percentage (execute / health gates). Distinct from `ispct`, which
    # only marks that a POWER gate's n is already a percentage - conflating the two
    # silently mis-converted mana.pct thresholds through UnitPowerMax.
    if g.get("pct") is not None:
        parts.append("pct=%d" % g["pct"])
    if g.get("ispct"):
        parts.append("ispct=true")
    if g.get("deficit"):
        parts.append("deficit=true")
    # `own` marks a bare `refreshable`/`ticking` - the entry's OWN dot rather than a
    # named one. It was being dropped, flattening those gates to a bare {t="dot"}
    # with no subject at all; the runtime does not consume it yet, but the data
    # should say what the classifier meant. (Found by the schema guard below.)
    if g.get("own"):
        parts.append("own=true")
    # `tgt` marks a gate that asks about the TARGET rather than the player (a SimC
    # `debuff.` stack). Without it a target debuff would be probed on the player.
    if g.get("tgt"):
        parts.append("tgt=true")
    if g.get("neg"):
        parts.append("neg=true")
    return "{" + ",".join(parts) + "}"


def entry_lua(e):
    g = "{" + ",".join(gate_lua(x) for x in e["gates"]) + "}"
    d = ",delegated=true" if e["delegated"] else ""
    emp = ",empower=%d" % e["empower"] if e.get("empower") else ""
    return "      {id=%d,gates=%s%s%s},  -- %s" % (e["id"], g, d, emp, e["token"])


def entry_sig(e):
    # Signature taken off the CANONICAL serialization rather than a hand-listed key
    # tuple. The old list named six keys, so every key added since (pct, ispct,
    # deficit, own, tgt) was invisible to dedup and two entries differing only in
    # one of them collapsed into a single entry - a dropped rotation line, silently.
    # `empower` is an ENTRY key, not a gate key, so it has to be named here explicitly -
    # gate_lua never sees it, and without it a context list differing only by release tier
    # would compare equal to another and be dropped as a duplicate.
    return (e["id"], tuple(sorted(gate_lua(x) for x in e["gates"])), e["delegated"],
            e.get("empower"))


def list_sig(lst):
    return tuple(entry_sig(e) for e in lst)


# --- burst anchors -----------------------------------------------------------
# SimC marks each spec's burst window EXPLICITLY: potions, on-use trinkets and
# external-buff requests (Power Infusion) are gated on the window buff
# (`potion,if=buff.X.up`, trinket-sync variables). Those anchor tokens, resolved
# to cast ids and filtered to real cooldowns, become the per-spec burst-cue
# trigger list (runtime priority: profile override -> this list -> SpellDB
# curated fallback).
SYNC_RE = re.compile(r"\+=/(?:potion|use_items?|invoke_external_buff)\b"
                     r"|variable,name=[a-z_0-9]*(?:trinket|sync)")
ANCHOR_TOKEN_RE = re.compile(r"(?:buff|cooldown)\.([a-z_]+)\.(?:up|remains|react|ready)")
# Raid externals/utility that gate items but are not the spec's own burst CD,
# plus stealth openers (long CDs that gate opener lines, not burst windows).
ANCHOR_SKIP = set("""bloodlust heroism time_warp fury_of_the_aspects power_infusion potion
shadowmeld prowl stealth vanish""".split())
# Anchor buff token -> castable action token(s), where they differ (composite
# talent-choice tokens, buff granted by a differently-named cast).
BUFF2CAST = {
    "ca_inc":          ["celestial_alignment", "incarnation_chosen_of_elune"],
    "bs_inc":          ["berserk", "incarnation_avatar_of_ashamane"],
    "voidform":        ["void_eruption", "dark_ascension"],
    "ebon_might_self": ["ebon_might"],
}
MIN_ANCHOR_CD_MS = 45_000  # ponytail: fixed floor keeps 30s mini-CDs (Tiger's Fury) out
MAX_ANCHORS = 4


def burst_anchors(text, resolve, cds, unresolved):
    counts = {}
    for line in text.splitlines():
        if not SYNC_RE.search(line):
            continue
        for t in ANCHOR_TOKEN_RE.findall(line):
            if t not in ANCHOR_SKIP:
                counts[t] = counts.get(t, 0) + 1
    out, seen = [], set()
    for t, _ in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        hit = False
        for cast in BUFF2CAST.get(t, [t]):
            sid = resolve(cast)
            if sid and sid not in seen and cds.get(sid, 0) >= MIN_ANCHOR_CD_MS:
                seen.add(sid)
                out.append((sid, cast))
                hit = True
        # Report anchors that resolve to nothing at all - a proc/pseudo buff
        # token is expected noise, but a top anchor going dark is worth eyes.
        if not hit and t in BUFF2CAST:
            unresolved.add(t + "(burst)")
        if len(out) >= MAX_ANCHORS:
            break
    return out[:MAX_ANCHORS]


def emit_spec(speckey, contexts):
    L = ['  ["%s"] = {' % speckey]
    b = contexts.get("burst")
    if b:
        L.append("    burst = {%s},  -- %s" % (
            ", ".join(str(sid) for sid, _ in b), " ".join(tok for _, tok in b)))
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
    # Discrete resources become countable gates; negations still delegate.
    g, d = classify_atom("combo_points>=5", lambda t: None)
    assert g == {"t": "resource", "res": "combo_points", "op": ">=", "n": 5, "deficit": False} and not d
    g, d = classify_atom("soul_shards<3", lambda t: None)
    assert g == {"t": "resource", "res": "soul_shard", "op": "<", "n": 3, "deficit": False} and not d
    # .deficit - pooling conditions. Countable: plain arithmetic at runtime.
    g, d = classify_atom("combo_points.deficit>=2", lambda t: None)
    assert g == {"t": "resource", "res": "combo_points", "op": ">=", "n": 2, "deficit": True} and not d
    # Continuous: the runtime restates it as max-N and flips the comparison.
    g, d = classify_atom("runic_power.deficit<20", lambda t: None)
    assert g == {"t": "power", "res": "runic_power", "op": "<", "n": 20,
                 "ispct": False, "deficit": True} and not d
    assert gate_lua({"t": "resource", "res": "chi", "op": ">=", "n": 2, "deficit": True}) \
        == '{t="resource",res="chi",op=">=",n=2,deficit=true}'
    # Aura stacks. `=` is kept (unlike the power gates) because the runtime can ask
    # ">=n and not >=n+1"; an unresolved aura token still delegates, as does a
    # negation, and `remains` stays delegated because a duration really is secret.
    g, d = classify_atom("buff.maelstrom_weapon.stack>=5", lambda t: 344179)
    assert g == {"t": "stack", "id": 344179, "op": ">=", "n": 5, "tgt": False} and not d
    g, d = classify_atom("debuff.x.stack<2", lambda t: 7)
    assert g == {"t": "stack", "id": 7, "op": "<", "n": 2, "tgt": True} and not d
    assert classify_atom("buff.x.stack=3", lambda t: 7)[0]["op"] == "="
    assert classify_atom("buff.x.stack>=5", lambda t: None) == (None, True)   # unresolved
    assert classify_atom("!buff.x.stack>=5", lambda t: 7) == (None, True)     # negated
    assert classify_atom("buff.x.remains>5", lambda t: 7) == (None, True)     # duration is secret
    assert gate_lua({"t": "stack", "id": 7, "op": "<", "n": 2, "tgt": True}) \
        == '{t="stack",id=7,op="<",n=2,tgt=true}'
    # entry_sig must separate entries that differ ONLY in a key the old hand-listed
    # tuple ignored - the dropped-rotation-line bug that motivated the rewrite.
    mk = lambda gs: {"id": 1, "gates": gs, "delegated": False, "token": "x"}
    assert entry_sig(mk([{"t": "stack", "id": 7, "op": ">=", "n": 2}])) \
        != entry_sig(mk([{"t": "stack", "id": 7, "op": ">=", "n": 2, "tgt": True}]))
    # SCHEMA GUARD. Every key classify_atom can put on a gate must survive
    # gate_lua - a key the classifier emits and the serializer ignores is
    # invisible until it silently changes runtime behaviour, which is exactly how
    # `pct` once shipped inert (every execute gate evaluated as if it had no
    # threshold). The runtime reads these by name, so this is the seam where
    # Python and Lua agree; nothing else checks it.
    SAMPLES = ("cooldown.x.ready", "dot.y.ticking", "buff.z.up", "refreshable",
               "target.health.pct<20", "target.time_to_die<10", "health.pct<35",
               "combo_points>=5", "combo_points.deficit>=2",
               "energy>=50", "mana.pct<30", "runic_power.deficit<20",
               "buff.maelstrom_weapon.stack>=5", "debuff.x.stack<2")
    keys = set()
    for atom in SAMPLES:
        gate, _ = classify_atom(atom, lambda t: 123)
        if gate:
            keys.update(gate.keys())
    for k in sorted(keys - {"t"}):
        probe = {"t": "probe", k: 1 if k in ("id", "n", "pct") else
                 ("x" if k in ("res", "op") else True)}
        assert k + "=" in gate_lua(probe), "gate_lua drops gate key %r" % k
    assert classify_atom("!combo_points>=5", lambda t: None) == (None, True)    # negated -> delegate
    # Continuous resources become THRESHOLD gates (were delegated before threshold
    # gates existed). Absolute values stay absolute here - the runtime converts to a
    # percentage with UnitPowerMax, which only it can read.
    g, d = classify_atom("energy>=50", lambda t: None)
    assert g == {"t": "power", "res": "energy", "op": ">=", "n": 50,
                 "ispct": False, "deficit": False} and not d
    g, d = classify_atom("astral_power>=90", lambda t: None)
    assert g == {"t": "power", "res": "astral_power", "op": ">=", "n": 90,
                 "ispct": False, "deficit": False} and not d
    g, d = classify_atom("mana.pct<30", lambda t: None)
    assert g == {"t": "power", "res": "mana", "op": "<", "n": 30,
                 "ispct": True, "deficit": False} and not d
    # Serialization must carry the threshold through - a dropped pct silently
    # disabled every execute gate the first time this shipped.
    assert gate_lua({"t": "execute", "op": "<", "pct": 20}) == '{t="execute",op="<",pct=20}'
    assert gate_lua({"t": "power", "res": "mana", "op": "<", "n": 30, "ispct": True}) \
        == '{t="power",res="mana",op="<",n=30,ispct=true}'
    assert classify_atom("energy=50", lambda t: None) == (None, True)     # = not expressible
    assert classify_atom("!energy>=50", lambda t: None) == (None, True)   # negated -> delegate
    # Execute keeps its per-spell percentage; time_to_die stays the generic flag.
    g, d = classify_atom("target.health.pct<20", lambda t: None)
    assert g == {"t": "execute", "op": "<", "pct": 20} and not d
    g, d = classify_atom("target.health.pct<35", lambda t: None)
    assert g == {"t": "execute", "op": "<", "pct": 35} and not d
    g, d = classify_atom("target.time_to_die<10", lambda t: None)
    assert g == {"t": "execute", "neg": False} and not d
    g, d = classify_atom("health.pct<35", lambda t: None)
    assert g == {"t": "health", "op": "<", "pct": 35} and not d

    # Empower tier: parsed off the mod, serialized, and part of the dedup signature. The
    # last two are what a dropped key looks like - the data still generates, just without
    # the tier, exactly like the gate keys that went missing before the schema guard.
    e = make_entry("consumption", {"empower_to": "1"}, lambda t: 42, set(), 1)
    assert e.get("empower") == 1
    assert "empower=1" in entry_lua(e)
    assert entry_sig(e) != entry_sig(make_entry("consumption", {}, lambda t: 42, set(), 1))
    assert make_entry("x", {"empower_to": "0"}, lambda t: 42, set(), 1).get("empower") is None


def main():
    _selftest()
    only = None
    if "--spec" in sys.argv:
        only = sys.argv[sys.argv.index("--spec") + 1]

    bridge = SimcBridge(CSV_DIR)
    # Base cooldowns (ms) for the burst-anchor floor: procs/pseudo buffs have no
    # cooldown row and mini-CDs fall under MIN_ANCHOR_CD_MS. Charge-based majors
    # (Zenith: 2 charges @ 90s) carry their real weight in ChargeRecoveryTime,
    # not RecoveryTime - fold that in via the charge-category join.
    cds = {}
    for r in bridge._rows("SpellCooldowns"):
        sid = int(r["SpellID"] or 0)
        eff = max(int(r["RecoveryTime"] or 0), int(r["CategoryRecoveryTime"] or 0))
        if sid and eff > cds.get(sid, 0):
            cds[sid] = eff
    charge_cat = {int(r["ID"]): int(r["ChargeRecoveryTime"] or 0)
                  for r in bridge._rows("SpellCategory")}
    for r in bridge._rows("SpellCategories"):
        if int(r.get("DifficultyID") or 0) != 0:
            continue
        sid = int(r["SpellID"] or 0)
        recharge = charge_cat.get(int(r["ChargeCategory"] or 0), 0)
        if sid and recharge > cds.get(sid, 0):
            cds[sid] = recharge
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
        text = open(f, encoding="utf-8").read()
        lists = parse_apl(text)
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

        anchors = burst_anchors(text, resolve, cds, unresolved)
        if anchors:
            contexts["burst"] = anchors

        all_specs[speckey] = contexts
        counts = {c: len(v) for c, v in contexts.items() if c != "burst"}
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
