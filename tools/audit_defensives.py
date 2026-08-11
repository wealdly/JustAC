#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Audit SpellDB.CLASS_DEFENSIVE_DEFAULTS and DEFENSE_TIER against the DB2 exports.

Run after every client-data refresh:

    python tools/audit_defensives.py            # report
    python tools/audit_defensives.py --strict   # exit 1 on any finding (CI / pre-release)

WHY THIS EXISTS
---------------
A defensive list entry that cannot be learned is worse than a missing one. The
runtime known-spell gate hides it forever, so it silently occupies one of the four
slots the queue shows by default, and nothing in game says why. "The id is in DB2"
does not catch it - a spell can have a live SpellName row and no acquisition route
at all. The 12.1 audit found ten such entries, including every Monk spec carrying a
dead Fortifying Brew.

Checks
  1. OBTAINABLE   - every id has a SkillLineAbility, TraitDefinition or
                    SpecializationSpells row; reports live same-name alternatives.
  2. ORDERING     - cast-time heals must be last in their list (the table's own rule).
  3. TIER ORPHANS - DEFENSE_TIER must not tag an id no list carries.
  4. TIER GAPS    - untagged entries whose DB2 effects look like a survival button.

Check 4 is ADVISORY. The tier table is hand-curated for good reasons documented
beside it (school-limited walls, HoTs and group utility are deliberately untiered),
so a hit here means "confirm this is still deliberate", not "fix it".
"""
import argparse
import collections
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_DIR = os.path.join(ROOT, "Documentation", "wow_spell_csv")
csv.field_size_limit(10_000_000)


def _build():
    """Newest client-data build present in the export directory."""
    builds = {m.group(1) for f in os.listdir(CSV_DIR)
              for m in [re.search(r"\.(\d+\.\d+\.\d+\.\d+)\.csv$", f)] if m}
    if not builds:
        sys.exit(f"no DB2 exports found in {CSV_DIR}")
    return sorted(builds, key=lambda b: [int(x) for x in b.split(".")])[-1]


BUILD = _build()


def rows(name):
    path = os.path.join(CSV_DIR, f"{name}.{BUILD}.csv")
    with open(path, encoding="utf-8", errors="replace", newline="") as fh:
        yield from csv.DictReader(fh)


def ints(table, col):
    return {int(r[col]) for r in rows(table) if r.get(col, "").isdigit()}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if any non-advisory check fails")
    args = ap.parse_args()

    print(f"client data: {BUILD}\n")

    names = {int(r["ID"]): r["Name_lang"] for r in rows("SpellName")}
    by_name = collections.defaultdict(list)
    for sid, nm in names.items():
        by_name[nm.lower()].append(sid)

    obtainable = ints("SkillLineAbility", "Spell")
    obtainable |= ints("SpecializationSpells", "SpellID")
    obtainable |= ints("TraitDefinition", "SpellID")

    cast_index = {int(r["SpellID"]): int(r["CastingTimeIndex"]) for r in rows("SpellMisc")
                  if r.get("SpellID", "").isdigit() and r.get("CastingTimeIndex", "").isdigit()}
    cast_base = {int(r["ID"]): int(r["Base"]) for r in rows("SpellCastTimes")}

    effects = collections.defaultdict(set)
    for r in rows("SpellEffect"):
        sid = r.get("SpellID", "")
        if not sid.isdigit():
            continue
        try:
            e, a = int(r["Effect"]), int(r["EffectAura"])
        except (ValueError, KeyError):
            continue
        if e in (10, 136):
            effects[int(sid)].add("heal")
        if a == 8:
            effects[int(sid)].add("hot")
        if a == 69:
            effects[int(sid)].add("absorb")
        if a in (39, 40):
            effects[int(sid)].add("immune")
        if a in (22, 118, 143):
            effects[int(sid)].add("dr")

    src = open(os.path.join(ROOT, "SpellDB.lua"), encoding="utf-8").read()

    def section(pattern):
        m = re.search(pattern + r"\s*=\s*\{(.*?)\n\}", src, re.S)
        if not m:
            sys.exit(f"could not locate {pattern} in SpellDB.lua")
        return m.group(1)

    lists = {m.group(1): [int(x) for x in re.findall(r"\d+", m.group(2))]
             for m in re.finditer(r"^\s*([A-Z]+(?:_\d)?)\s*=\s*\{([^}]*)\}",
                                  section(r"SpellDB\.CLASS_DEFENSIVE_DEFAULTS"), re.M)}
    tiers = {int(a): int(b) for a, b in
             re.findall(r"\[(\d+)\]\s*=\s*(\d)", section(r"local DEFENSE_TIER"))}

    listed = {sid for v in lists.values() for sid in v}
    print(f"{len(lists)} lists, {sum(len(v) for v in lists.values())} entries, "
          f"{len(listed)} distinct spells, {len(tiers)} tier tags\n")

    failures = 0

    def report(title, items, advisory=False):
        nonlocal failures
        tag = "  (advisory)" if advisory else ""
        if not items:
            print(f"PASS  {title}{tag}")
            return
        print(f"FAIL  {title}: {len(items)}{tag}")
        for line in items:
            print(f"        {line}")
        if not advisory:
            failures += len(items)

    # 1. obtainable
    bad = []
    for key, ids in sorted(lists.items()):
        for i, sid in enumerate(ids, 1):
            if sid in obtainable:
                continue
            nm = names.get(sid, "?")
            alts = [a for a in by_name.get(nm.lower(), []) if a in obtainable and a != sid]
            hint = f"-> live same-name id {alts}" if alts else "(no live same-name id)"
            bad.append(f"{key}[{i}] {sid} {nm!r} {hint}")
    report("every entry is obtainable", bad)

    # 2. cast-time heals last
    bad = []
    for key, ids in sorted(lists.items()):
        for i, sid in enumerate(ids, 1):
            base = cast_base.get(cast_index.get(sid, 0), 0)
            if base > 0 and i != len(ids):
                bad.append(f"{key}[{i}/{len(ids)}] {sid} {names.get(sid,'?')!r} "
                           f"{base}ms - cast-time heals must be last")
    report("cast-time heals sit last in their list", bad)

    # 3. tier orphans
    report("no tier tag on an unlisted spell",
           [f"{sid} {names.get(sid,'?')!r} tier {t}"
            for sid, t in sorted(tiers.items()) if sid not in listed])

    # 4. tier gaps (advisory)
    gaps = []
    for sid in sorted(listed):
        if tiers.get(sid, 3) != 3:
            continue
        sig = effects.get(sid, set())
        why = ("immunity effect" if "immune" in sig else
               "direct heal" if ("heal" in sig and "hot" not in sig) else
               "damage reduction" if "dr" in sig else None)
        if why:
            where = [k for k, v in lists.items() if sid in v]
            gaps.append(f"{sid} {names.get(sid,'?')!r} - {why}, untagged, in {where}")
    report("untagged entries that look like survival buttons", gaps, advisory=True)

    print()
    if failures and args.strict:
        print(f"{failures} finding(s); --strict set")
        return 1
    print("no blocking findings" if not failures else f"{failures} finding(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
