# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Compare account-wide Forever immunity observations with a local Classic SQL snapshot.

The report is evidence for review, not a generator: a matching mechanic mask is not proof
of Forever behavior, and a missing mask does not establish that the spell can land.
SavedVariables must have been flushed by reload or logout.
"""
import argparse
from contextlib import closing
import csv
import datetime
import re
import sqlite3
import sys
from pathlib import Path

from analyze_probe import DEFAULT_WOW_ROOT, default_paths

ROOT = Path(__file__).resolve().parent.parent
CSV_DIR = ROOT / "Documentation" / "wow_spell_csv_forever"
OPEN_GLOBAL = re.compile(r"^JustACGlobal\s*=\s*\{\s*$")
OPEN_IMMUNE = re.compile(r'^\s*\["dotImmuneNPCs"\]\s*=\s*\{\s*$')
OPEN_NPC = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{\s*$")
ENTRY = re.compile(r"^\s*\[(\d+)\]\s*=\s*(\d+),?\s*$")
CLOSE = re.compile(r"^\s*\},?\s*$")


def read_observations(path):
    observations = {}
    in_global, state, npc = False, 0, None
    with path.open(encoding="utf-8-sig") as handle:
        for line in handle:
            if not in_global:
                in_global = bool(OPEN_GLOBAL.match(line))
            elif state == 0:
                if OPEN_IMMUNE.match(line):
                    state = 1
            elif state == 1:
                if CLOSE.match(line):
                    return observations
                match = OPEN_NPC.match(line)
                if not match or int(match.group(1)) < 1:
                    raise ValueError(f"{path}: invalid creature entry in immunity cache")
                npc, state = int(match.group(1)), 2
            else:
                if CLOSE.match(line):
                    state = 1
                    continue
                match = ENTRY.match(line)
                if not match or int(match.group(1)) < 1:
                    raise ValueError(f"{path}: invalid spell entry in immunity cache")
                key = npc, int(match.group(1))
                if key in observations:
                    raise ValueError(f"{path}: duplicate immunity entry")
                observations[key] = int(match.group(2))
    if state:
        raise ValueError(f"{path}: incomplete immunity cache")
    if not in_global:
        raise ValueError(f"{path}: JustACGlobal is missing")
    return observations


def load_mechanics(folder, spells):
    files = list(folder.glob("SpellCategories.*.csv"))
    if len(files) != 1:
        raise ValueError(f"{folder}: expected one SpellCategories CSV, found {len(files)}")
    found = {}
    with files[0].open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            spell = int(row["SpellID"])
            if spell in spells and row["DifficultyID"] == "0":
                found.setdefault(spell, set()).add(int(row["Mechanic"]))
    return {spell: next(iter(values)) for spell, values in found.items()
            if len(values) == 1 and 0 not in values}


def compare(db_path, observations, mechanics):
    results = []
    with closing(sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True)) as db:
        for (npc, spell), sightings in sorted(observations.items()):
            row = db.execute(
                "SELECT mechanic_immune_mask FROM creature_template "
                "WHERE entry = ? ORDER BY patch DESC LIMIT 1", (npc,)
            ).fetchone()
            mechanic = mechanics.get(spell)
            if row is None or not mechanic or not 1 <= mechanic <= 32:
                verdict = "unknown"
            elif int(row[0]) & (1 << (mechanic - 1)):
                verdict = "mask-match"
            else:
                verdict = "not-marked"
            results.append((npc, spell, sightings, verdict))
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--classic-db", required=True, type=Path, help="local Classic SQLite snapshot")
    parser.add_argument("--wow-root", default=DEFAULT_WOW_ROOT, help="WoW installation root")
    parser.add_argument("--csv-dir", default=CSV_DIR, type=Path, help="complete Forever CSV folder")
    parser.add_argument("paths", nargs="*", type=Path, help="Forever account SavedVariables files")
    args = parser.parse_args(argv)
    paths = args.paths or [Path(path) for label, path in default_paths(args.wow_root) if label == "_forever_"]
    if not paths:
        parser.error("no Forever SavedVariables found")
    observations = {}
    for path in paths:
        for key, count in read_observations(path).items():
            observations[key] = max(observations.get(key, 0), count)
    mechanics = load_mechanics(args.csv_dir, {spell for _, spell in observations})
    results = compare(args.classic_db, observations, mechanics)
    times = [datetime.datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds") for path in paths]
    print(f"{len(paths)} account file(s); last saved {min(times)} to {max(times)}; reload/logout to flush")
    print("npc spell sightings comparison (mask match is a candidate, not confirmed Forever behavior)")
    for npc, spell, count, verdict in results:
        print(f"{npc} {spell} {count} {verdict}")
    print(f"{len(results)} distinct observations; not-marked and unknown are not evidence of a hit")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, sqlite3.Error) as exc:
        sys.exit(f"immunity audit failed: {exc}")
