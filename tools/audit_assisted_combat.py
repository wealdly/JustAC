# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Audit against Blizzard's own assisted-combat rotation data (DB2 tables AssistedCombat,
# AssistedCombatStep, AssistedCombatRule). Report-only.
#
#   python tools/audit_assisted_combat.py                 what SimC pool insertion adds, per spec
#   python tools/audit_assisted_combat.py --diff OLD NEW  which specs' rotations changed between builds
#   python tools/audit_assisted_combat.py --cooldowns     Blizzard's cooldown/movement class vs burst anchors + NEVER_INSERT
#   python tools/audit_assisted_combat.py --dots          DoTs Blizzard refreshes when missing vs Data/TargetDots.lua
#   python tools/audit_assisted_combat.py --healers       the local healer pins vs Blizzard's order for those specs
#   python tools/audit_assisted_combat.py --procs         ability <- gating aura pairs (reference listing)
#   python tools/audit_assisted_combat.py --decode [FILE] join an in-game pick log with the rules (research)
#
# WHY. With SimC ordering, the queue adds SimC abilities the game's rotation list leaves out
# (BlizzardAPI.GetRotationSpells -> RotationImport.GetInsertable). That changes the pool for
# every spec at once, and the only other way to see what it adds is to log in on each one.
# This computes it offline: insertable SimC ids minus Blizzard's step list.
#
# TWO LIMITS, both measured (Devourer DH, 2026-09-19):
#   * The DB2 step list is a SUPERSET of the live C_AssistedCombat.GetRotationSpells(). Live
#     drops talent-gated steps the character lacks, and every spell whose steps ALL carry
#     ConditionType 70 - which across the specs is exactly the major cooldowns and movement
#     abilities. So those are reported separately: insertion brings them back where SimC can
#     time them. The meaning of type 70 itself is unconfirmed.
#   * Talents are ignored, so the counts are an upper bound, and a temporary form of a button
#     already listed (matched here by NAME) is not counted - at runtime the override resolver
#     and the queue's duplicate check do that job.
#
# --diff is wired into update_data.py, which runs it while both builds are still on disk: a
# changed rotation is the signal to re-check that spec's SimC pin / local healer list.

import argparse
import csv
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CSV_DIR = REPO / "Documentation" / "wow_spell_csv"
CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 6: "DEATHKNIGHT",
           7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 10: "MONK", 11: "DRUID", 12: "DEMONHUNTER", 13: "EVOKER"}
COOLDOWN_CLASS = "70"   # ConditionType: see the header


def load(table, build=None, csv_dir=CSV_DIR):
    hits = sorted(csv_dir.glob(f"{table}.{build}*.csv" if build else f"{table}.*.csv"))
    if not hits:
        sys.exit(f"missing {table} csv{' for ' + build if build else ''} in {csv_dir}")
    with open(hits[-1], encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def spec_keys(build=None):
    return {int(r["ID"]): f"{CLASSES[int(r['ClassID'])]}_{int(r['OrderIndex']) + 1}"
            for r in load("ChrSpecialization", build) if int(r["ClassID"] or 0) in CLASSES}


def rotations(build=None):
    """specKey -> [(order, spellID, isCooldownClass)] in Blizzard's priority order."""
    keys = spec_keys(build)
    ac = {r["ID"]: keys.get(int(r["ChrSpecializationID"])) for r in load("AssistedCombat", build)}
    flagged = {r["AssistedCombatStepID"] for r in load("AssistedCombatRule", build)
               if r["ConditionType"] == COOLDOWN_CLASS}
    out = {}
    for s in load("AssistedCombatStep", build):
        key = ac.get(s["AssistedCombatID"])
        if key:
            out.setdefault(key, []).append((int(s["OrderIndex"]), int(s["SpellID"]), s["ID"] in flagged))
    for steps in out.values():
        steps.sort()
    return out


def lua_id_set(text):
    return {int(x) for x in re.findall(r"\[(\d+)\]\s*=\s*true", text)}


def insertable_by_spec():
    """Mirror of RotationImport.GetInsertable + the pool filter in BlizzardAPI/SpellQuery.lua."""
    non_offensive = lua_id_set((REPO / "Data" / "SpellCategories.lua").read_text(encoding="utf-8"))
    never = never_insert()
    sd = (REPO / "SpellDB.lua").read_text(encoding="utf-8")
    gap_block = sd[sd.index("SpellDB.CLASS_GAPCLOSER_DEFAULTS = {"):]
    gap_block = gap_block[:gap_block.index("\n}")]
    gap = {m.group(1): {int(x) for x in re.findall(r"\d+", m.group(2))}
           for m in re.finditer(r"(\w+_\d) = \{([^}]*)\}", gap_block)}

    parts = re.split(r'\n  \["([A-Z_0-9]+)"\] = \{', (REPO / "Data" / "SimcRotations.lua").read_text(encoding="utf-8"))
    out = {}
    for k in range(1, len(parts), 2):
        key, body, ok = parts[k], parts[k + 1], {}
        # Anchored on the trailing "-- name" comment: gates nest braces, and without the
        # anchor the lazy match stops inside them and never sees ",delegated=true".
        for m in re.finditer(r"\{id=(\d+),gates=\{.*?\}(,delegated=true)?(?:,empower=\d+)?\},\s*--", body):
            sid = int(m.group(1))
            ok[sid] = ok.get(sid, True) and not m.group(2)   # every line, every context
        out[key] = [i for i, good in ok.items()
                    if good and i not in non_offensive and i not in never and i not in gap.get(key, set())]
    return out


def audit_insertion():
    names = spell_names()
    rot, simc = rotations(), insertable_by_spec()
    label = lambda ids: ", ".join(f"{names.get(i, '?')} ({i})" for i in ids) or "-"
    total = back = 0
    for key in sorted(simc):
        steps = rot.get(key)
        if steps is None:
            print(f"{key:15} NO BLIZZARD DATA")
            continue
        listed = {sid for _, sid, _ in steps}
        listed_names = {names.get(i) for i in listed}
        cooldown_only = {sid for _, sid, _ in steps} - {sid for _, sid, flag in steps if not flag}
        adds = [i for i in simc[key] if i not in listed and names.get(i) not in listed_names]
        returns = [i for i in simc[key] if i in cooldown_only]
        total, back = total + len(adds), back + len(returns)
        if adds or returns:
            print(f"{key:15} adds: {label(adds)}")
            if returns:
                print(f"{'':15} brings back (cooldown class, dropped from the live list): {label(returns)}")
    print(f"\n{total} additions + {back} cooldown-class returns across {len(simc)} specs (upper bound: talents ignored)")


def audit_diff(old, new):
    names = {int(r["ID"]): r["Name_lang"] for r in load("SpellName", new)}
    a, b = rotations(old), rotations(new)
    changed = 0
    for key in sorted(set(a) | set(b)):
        before, after = [s for _, s, _ in a.get(key, [])], [s for _, s, _ in b.get(key, [])]
        if before == after:
            continue
        changed += 1
        added = [names.get(i, str(i)) for i in dict.fromkeys(after) if i not in before]
        removed = [names.get(i, str(i)) for i in dict.fromkeys(before) if i not in after]
        note = "; ".join(p for p in (added and "added " + ", ".join(added),
                                     removed and "removed " + ", ".join(removed)) if p)
        print(f"  {key:15} {note or 'same spells, order or conditions-per-step changed'}")
    print(f"  {changed} spec rotation(s) changed {old} -> {new}"
          + (" - re-check those specs' SimC pins and local healer lists" if changed else ""))


def steps_with_rules(build=None):
    """specKey -> [(order, spellID, [(type, v1, v2, v3)])]."""
    keys = spec_keys(build)
    ac = {r["ID"]: keys.get(int(r["ChrSpecializationID"])) for r in load("AssistedCombat", build)}
    rules = {}
    for r in load("AssistedCombatRule", build):
        rules.setdefault(r["AssistedCombatStepID"], []).append(
            (r["ConditionType"], int(r["ConditionValue1"] or 0), int(r["ConditionValue2"] or 0), int(r["ConditionValue3"] or 0)))
    out = {}
    for s in load("AssistedCombatStep", build):
        key = ac.get(s["AssistedCombatID"])
        if key:
            out.setdefault(key, []).append((int(s["OrderIndex"]), int(s["SpellID"]), rules.get(s["ID"], [])))
    for v in out.values():
        v.sort(key=lambda t: t[0])
    return out


def spell_names():
    return {int(r["ID"]): r["Name_lang"] for r in load("SpellName")}


def never_insert():
    ri = (REPO / "RotationImport.lua").read_text(encoding="utf-8")
    block = ri[ri.index("NEVER_INSERT = {"):]
    return lua_id_set(block[:block.index("\n}")])


def audit_cooldowns():
    """Blizzard's cooldown/movement class (type 70 on every step) vs what we curate by hand."""
    names = spell_names()
    src = (REPO / "Data" / "SimcRotations.lua").read_text(encoding="utf-8")
    burst = {m.group(1): {int(x) for x in re.findall(r"\d+", m.group(2))}
             for m in re.finditer(r'"([A-Z_0-9]+)"\] = \{\s*burst = \{([^}]*)\}', src)}
    never = never_insert()
    for key, steps in sorted(rotations().items()):
        cls = {sid for _, sid, _ in steps} - {sid for _, sid, flag in steps if not flag}
        cls_names = {names.get(i) for i in cls}
        anchors = burst.get(key, set())
        anchor_names = {names.get(i) for i in anchors}
        unknown = [i for i in cls if i not in anchors and names.get(i) not in anchor_names and i not in never]
        ours_only = [i for i in anchors if i not in cls and names.get(i) not in cls_names]
        if unknown or ours_only:
            print(f"{key:15} Blizzard-only: {', '.join(names.get(i, str(i)) for i in unknown) or '-'}")
            print(f"{'':15} burst-anchor-only: {', '.join(names.get(i, str(i)) for i in ours_only) or '-'}")
    print("\nBlizzard-only = cooldown/movement class we neither anchor nor exclude. Movement belongs in"
          "\nNEVER_INSERT; a cooldown there is only a gap if the burst cue should call it."
          "\nburst-anchor-only is expected where SimC syncs on a cooldown Blizzard rates as rotation.")


def audit_dots():
    """Spells Blizzard gates on 'my DoT is missing on the target' (types 10/15) vs TargetDots."""
    names = spell_names()
    text = (REPO / "Data" / "TargetDots.lua").read_text(encoding="utf-8")
    ours = {int(x) for x in re.findall(r"^\[(\d+)\]=", text, re.M)}
    our_names = {names.get(i) for i in ours}
    seen = {}
    for key, steps in steps_with_rules().items():
        for _, _sid, rules in steps:
            for t, v1, _, _ in rules:
                if t in ("10", "15") and v1:
                    seen.setdefault(v1, set()).add(key)
    missing = {i: k for i, k in seen.items() if i not in ours and names.get(i) not in our_names}
    for i in sorted(missing, key=lambda i: names.get(i, "")):
        print(f"  {names.get(i, '?'):28} ({i})  {', '.join(sorted(missing[i]))}")
    print(f"\n{len(missing)} of {len(seen)} DoT/debuff ids Blizzard tracks are not in Data/TargetDots.lua."
          "\nMany are legitimately excluded (stacking DoTs, debuffs that are not upkeep, an aura id"
          "\nrather than the cast id) - each is a candidate to look at, not a defect.")


def audit_healers():
    """Local healer pins (written from judgment) vs Blizzard's order for the same spec."""
    names = spell_names()
    pins = {"priest_discipline": "PRIEST_1", "priest_holy": "PRIEST_2", "paladin_holy": "PALADIN_1",
            "shaman_restoration": "SHAMAN_3", "evoker_preservation": "EVOKER_2", "monk_mistweaver": "MONK_2"}
    rot = rotations()
    from simc_bridge import slug
    for apl, key in sorted(pins.items()):
        path = REPO / "tools" / "simc-apl" / f"{apl}.simc"
        if not path.exists():
            continue
        ours = list(dict.fromkeys(re.findall(r"^actions(?:\.\w+)?\+?=/?(\w+)", path.read_text(encoding="utf-8"), re.M)))
        theirs = list(dict.fromkeys(slug(names.get(sid, str(sid))) for _, sid, _ in rot.get(key, [])))
        print(f"{apl} ({key})")
        print(f"    ours:     {' > '.join(ours)}")
        print(f"    Blizzard: {' > '.join(theirs)}")
        print(f"    only ours: {', '.join(o for o in ours if o not in theirs) or '-'}"
              f"   only Blizzard: {', '.join(t for t in theirs if t not in ours) or '-'}")


def audit_procs():
    """Reference listing: ability <- the aura that gates one of its steps (type 9)."""
    names = spell_names()
    for key, steps in sorted(steps_with_rules().items()):
        pairs = sorted({(names.get(sid, str(sid)), names.get(v1, str(v1)))
                        for _, sid, rules in steps for t, v1, _, _ in rules
                        if t == "9" and v1 and names.get(v1) != names.get(sid)})
        if pairs:
            print(f"{key:15} " + "; ".join(f"{a} <- {b}" for a, b in pairs))


def audit_decode(path=None):
    """Join an in-game pick log (/jac inspect picklog) with the rule table.

    Two questions, in the order the plan asks them:
      1. AMBIGUITY - how often does a pick identify exactly one step? A spell with several
         steps does not say which fired. If single-step picks are rare, reading state from
         the pick is a weak idea and stops here.
      2. DECODING - for each undecoded numeric condition type on a single-step pick, which
         readable facts were true every time it fired? A value that never varies alongside
         a condition (type 12 value 3 <-> enemies always >= 3) is a candidate meaning.
    """
    import collections
    wtf = REPO.parents[2] / "WTF" / "Account"
    hits = [Path(path)] if path else sorted(wtf.glob("*/SavedVariables/JustAC.lua"), key=lambda p: p.stat().st_mtime)
    if not hits or not hits[-1].exists():
        sys.exit("no SavedVariables/JustAC.lua found - record with /jac inspect picklog, /reload, then re-run")
    text = hits[-1].read_text(encoding="utf-8", errors="replace")
    rows = re.findall(r'"[\d.]+ (\w+_\d) pick=(\d+) combat=(\S) enemies=(\S+) pts=(\S+)/(\S+) pow=(\S+) thp=(\S+?)(?: lead=[^"]*)?"', text)
    if not rows:
        sys.exit(f"no pickLog samples in {hits[-1]} (record, then /reload to flush)")
    names, steps = spell_names(), steps_with_rules()
    single = multi = unknown = 0
    seen = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for key, pick, combat, enemies, pts, _maxpts, power, thp in rows:
        if combat != "1":
            continue
        pick = int(pick)
        cands = [r for _, sid, r in steps.get(key, []) if sid == pick or names.get(sid) == names.get(pick)]
        if not cands:
            unknown += 1
        elif len(cands) > 1:
            multi += 1
        else:
            single += 1
            for t, v1, v2, v3 in cands[0]:
                if v1 < 1000:                       # numeric condition, not a spell/aura id
                    cond = f"type {t} ({v1},{v2},{v3})"
                    for fact, val in (("enemies", enemies), ("pts", pts), ("pow", power), ("thp", thp)):
                        seen[cond][fact][val] += 1
    total = single + multi + unknown
    print(f"{hits[-1]}\n{total} in-combat samples: {single} pin one step ({100 * single // max(total, 1)}%), "
          f"{multi} ambiguous, {unknown} picks with no step (overrides / unlisted)\n")
    for cond in sorted(seen, key=lambda c: -sum(seen[c]["enemies"].values())):
        n = sum(seen[cond]["enemies"].values())
        facts = "  ".join(f"{f}={dict(sorted(c.items()))}" for f, c in seen[cond].items())
        print(f"{cond:22} x{n:<4} {facts}")
    print("\nRead it as: a fact whose values stay inside one range every time a condition fired is a"
          "\ncandidate meaning for that condition. pow/thp are band indexes (1 = lowest band).")


def self_check():
    # The one measured fact this rests on: live Devourer returned these five, and the DB2
    # list must contain them (superset) plus Voidblade, which live dropped.
    devourer = {sid for _, sid, _ in rotations().get("DEMONHUNTER_3", [])}
    live = {473662, 473728, 1217605, 1226019}
    assert live <= devourer and 1245412 in devourer, "spec-key mapping or step join is broken"
    # Hungering Slash is delegated in the data; reading it as insertable means the entry
    # parser lost the flag (it did once - nested gate braces).
    assert 1239123 not in insertable_by_spec()["DEMONHUNTER_3"], "delegated flag is not being parsed"


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--diff", nargs=2, metavar=("OLD", "NEW"), help="compare rotations between two builds")
    for flag in ("cooldowns", "dots", "healers", "procs"):
        ap.add_argument(f"--{flag}", action="store_true")
    ap.add_argument("--decode", nargs="?", const="", metavar="SAVEDVARS",
                    help="join a /jac inspect picklog recording with the rule table")
    args = ap.parse_args()
    if args.diff:
        audit_diff(*args.diff)
    elif args.cooldowns:
        audit_cooldowns()
    elif args.dots:
        audit_dots()
    elif args.healers:
        audit_healers()
    elif args.procs:
        audit_procs()
    elif args.decode is not None:
        audit_decode(args.decode or None)
    else:
        self_check()
        audit_insertion()
