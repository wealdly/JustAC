# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Sync the pinned SimC APLs (tools/simc-apl/) from the sparse simc mirror and
# regenerate Data/SimcRotations.lua. Standard pre-release step, plus after any
# class-tuning patch or new season/tier (wait ~1-2 weeks post-tier for the
# theorycraft to settle).
#
# Mirror: 00-SOURCE/simc (sparse checkout of ActionPriorityLists, branch
# `midnight`), refreshed by 00-SOURCE/update-sources.ps1. Upstream files in
# ActionPriorityLists/default/ overwrite the pinned copies byte-for-byte;
# local-only files are KEPT unless --prune, because deleting a spec's APL
# silently drops it back to AC ordering - make that a choice, not a side
# effect of upstream housekeeping.
#
# Run: python tools/update_simc_apl.py [--mirror path] [--prune] [--skip-gen]

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APL_DIR = REPO / "tools" / "simc-apl"
# JustAC lives at <root>/Interface/AddOns/JustAC; the mirrors at <root>/00-SOURCE.
DEFAULT_MIRROR = REPO.parents[2] / "00-SOURCE" / "simc"


def main():
    ap = argparse.ArgumentParser(description="Sync pinned SimC APLs from the sparse mirror and regenerate")
    ap.add_argument("--mirror", type=Path, default=DEFAULT_MIRROR, help="simc mirror checkout (default: 00-SOURCE/simc)")
    ap.add_argument("--prune", action="store_true", help="delete pinned APLs upstream no longer ships")
    ap.add_argument("--skip-gen", action="store_true", help="sync only; don't run gen_simc_rotations.py")
    args = ap.parse_args()

    src = args.mirror / "ActionPriorityLists" / "default"
    if not src.is_dir():
        sys.exit(f"mirror APL dir not found: {src}\n(run 00-SOURCE/update-sources.ps1 first)")

    head = subprocess.run(
        ["git", "-C", str(args.mirror), "log", "-1", "--format=%h %cs"],
        capture_output=True, text=True).stdout.strip()
    print(f"mirror: {src}  (upstream {head})")

    upstream = sorted(p.name for p in src.glob("*.simc"))
    pinned = sorted(p.name for p in APL_DIR.glob("*.simc"))

    changed, added = [], []
    for name in upstream:
        s, d = src / name, APL_DIR / name
        if not d.exists():
            added.append(name)
        elif s.read_bytes() == d.read_bytes():
            continue
        else:
            changed.append(name)
        shutil.copyfile(s, d)

    local_only = [n for n in pinned if n not in upstream]
    for name in local_only:
        if args.prune:
            (APL_DIR / name).unlink()

    print(f"changed: {len(changed)}  new: {len(added)}  unchanged: {len(upstream) - len(changed) - len(added)}")
    for n in added:
        print(f"  NEW: {n}")
    for n in local_only:
        print(f"  {'PRUNED' if args.prune else 'LOCAL-ONLY (kept; --prune to drop)'}: {n}")

    if args.skip_gen:
        return
    if not (changed or added or (args.prune and local_only)):
        print("no APL changes; skipping regeneration")
        return
    print("regenerating Data/SimcRotations.lua ...")
    subprocess.run([sys.executable, str(REPO / "tools" / "gen_simc_rotations.py")], check=True)


if __name__ == "__main__":
    main()
