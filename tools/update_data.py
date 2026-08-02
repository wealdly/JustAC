# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Centralized data refresh: pull updated DB2 CSV exports from wago.tools, diff
# them against the current set, swap the folder to the new build, regenerate
# every Data/*.lua file, and show the resulting repo diff.
#
# The CSV folder must stay on ONE build: generators join across tables, and
# gen_archetypes.sh picks the lexicographically first file per table while the
# Python generators pick the last - a mixed folder silently joins across
# builds. This script downloads the full new build first, diffs, then removes
# the old build atomically before regenerating.
#
# The table list is self-maintaining: whatever <Table>.<build>.csv files exist
# in the folder define what gets pulled. To track a new table, download it once
# by hand (https://wago.tools/db2/<Table>/csv?build=<build>) and re-run.
#
# Run: python tools/update_data.py [build] [--product wow|wowt] [--skip-gen] [--keep-old] [--dir path]
#   build      target build (e.g. 12.1.0.68412); default = latest for --product
#   --product  wago product line for build auto-detection: wow (retail, default) or wowt (PTR)
#   --skip-gen download + diff + swap only; don't run generators
#   --keep-old keep the previous build's CSVs after a successful swap
#   --dir      override the CSV folder (testing)

import argparse
import csv
import json
import re
import subprocess
import shutil
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_CSV_DIR = REPO / "Documentation" / "wow_spell_csv"
FILE_RE = re.compile(r"^([A-Za-z_]+)\.([\d.]+?)(?: \(\d+\))?\.csv$")
UA = {"User-Agent": "JustAC-data-pipeline (github)"}

# Be a good wago.tools citizen: space out requests, back off once on failure.
# Build-versioned files are immutable, so nothing is ever fetched twice (the
# resume check skips files already on disk), and a same-build run exits before
# any request. A full refresh is ~27 requests once per patch cycle.
THROTTLE_SECS = 1.5
RETRY_WAIT_SECS = 10


def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def fetch_throttled(url):
    time.sleep(THROTTLE_SECS)
    try:
        return fetch(url)
    except Exception:  # noqa: BLE001 - one gentle retry, then let it surface
        time.sleep(RETRY_WAIT_SECS)
        return fetch(url)


def latest_build(product):
    builds = json.loads(fetch("https://wago.tools/api/builds"))
    entries = builds.get(product)
    if not entries:
        sys.exit(f"no builds for product '{product}' (have: {', '.join(builds)})")
    return entries[0]["version"]


def inventory(csv_dir):
    """-> (tables: set, builds: {build -> set of tables})"""
    tables, builds = set(), {}
    for p in csv_dir.glob("*.csv"):
        m = FILE_RE.match(p.name)
        if m:
            tables.add(m.group(1))
            builds.setdefault(m.group(2), set()).add(m.group(1))
    return tables, builds


def diff_tables(csv_dir, tables, old_build, new_build):
    print(f"\n== diff {old_build} -> {new_build}")
    print(f"{'table':<26}{'old':>8}{'new':>8}{'added':>7}{'gone':>7}{'chgd':>7}")
    for t in sorted(tables):
        old_p = find_file(csv_dir, t, old_build)
        new_p = find_file(csv_dir, t, new_build)
        if not old_p or not new_p:
            print(f"{t:<26}{'(no old file - new table)' if not old_p else '(missing new!)'}")
            continue
        old_rows = load_rows(old_p)
        new_rows = load_rows(new_p)
        added = sum(1 for k in new_rows if k not in old_rows)
        gone = sum(1 for k in old_rows if k not in new_rows)
        chgd = sum(1 for k, v in new_rows.items() if k in old_rows and old_rows[k] != v)
        flag = "  <-- changed" if (added or gone or chgd) else ""
        print(f"{t:<26}{len(old_rows):>8}{len(new_rows):>8}{added:>7}{gone:>7}{chgd:>7}{flag}")


def load_rows(path):
    rows = {}
    with open(path, encoding="utf-8-sig", newline="") as f:
        for row in csv.reader(f):
            if row:
                rows[row[0]] = row
    return rows


def find_file(csv_dir, table, build):
    hits = sorted(csv_dir.glob(f"{table}.{build}*.csv"))
    return hits[0] if hits else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build", nargs="?", help="target build; default = latest for --product")
    ap.add_argument("--product", default="wow", help="wago product for auto-detect (wow/wowt)")
    ap.add_argument("--skip-gen", action="store_true")
    ap.add_argument("--keep-old", action="store_true")
    ap.add_argument("--dir", type=Path, default=DEFAULT_CSV_DIR)
    args = ap.parse_args()
    csv_dir = args.dir

    tables, builds = inventory(csv_dir)
    if not tables:
        sys.exit(f"no <Table>.<build>.csv files in {csv_dir} - seed the folder first")
    current = max(builds, key=lambda b: len(builds[b]))  # the build most tables are on
    target = args.build or latest_build(args.product)
    print(f"folder: {csv_dir}\ntables: {len(tables)}  current build: {current}  target: {target}")
    if target == current:
        print("already on the target build - nothing to do")
        return

    # 1. Download the complete new build (skip files already present from a resume)
    failed = []
    for t in sorted(tables):
        dest = csv_dir / f"{t}.{target}.csv"
        if dest.exists() and dest.stat().st_size > 0:
            print(f"  have    {dest.name}")
            continue
        try:
            data = fetch_throttled(f"https://wago.tools/db2/{t}/csv?build={target}")
            dest.write_bytes(data)
            print(f"  pulled  {dest.name} ({len(data) // 1024} KB)")
        except Exception as e:  # noqa: BLE001 - report and continue, abort below
            failed.append(t)
            print(f"  FAILED  {t}: {e}")
    if failed:
        sys.exit(f"\n{len(failed)} download(s) failed ({', '.join(failed)}). Old build kept; "
                 "folder is mixed-build - re-run to resume before regenerating.")

    # 2. Diff old vs new while both are present
    diff_tables(csv_dir, tables, current, target)

    # 3. Swap: drop the old build so every generator resolves the same build
    if not args.keep_old:
        for t in tables:
            old_p = find_file(csv_dir, t, current)
            if old_p:
                old_p.unlink()
        print(f"\nremoved {current} files - folder is now {target} only")

    # 4. Regenerate Data/*.lua
    if args.skip_gen:
        print("skipped generators (--skip-gen)")
        return
    print("\n== generators")
    # gen_aura_durations.py is retained for reference but its output is not shipped
    # (durations are secret in combat; the readiness probe superseded it). Running it
    # would drop an untracked Data/AuraDurations.lua that nothing loads.
    skip = {"gen_aura_durations.py"}
    for gen in sorted(REPO.glob("tools/gen_*.py")):
        if gen.name in skip:
            print(f"-- {gen.name} SKIPPED (output not shipped)")
            continue
        print(f"-- {gen.name}")
        subprocess.run([sys.executable, str(gen)], check=True, cwd=REPO)
    bash = shutil.which("bash")
    if bash:
        print("-- gen_archetypes.sh")
        subprocess.run([bash, "tools/gen_archetypes.sh"], check=True, cwd=REPO)
    else:
        print("-- gen_archetypes.sh SKIPPED (no bash on PATH - run it from Git Bash)")

    # 5. Show what actually changed in the shipped data
    print("\n== Data/ impact")
    subprocess.run(["git", "diff", "--stat", "Data/"], cwd=REPO)
    print("\nReview with: git diff Data/   (then run the curated-list audits in tools/)")


if __name__ == "__main__":
    main()
