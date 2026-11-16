# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Staged, per-client DB2 CSV refresh (steps 4-5 of the two-client update in DEV_TOOLING.md).

stage:   copy the live CSV folder to <folder>.staging, download the target build there with
         update_data.py --skip-gen, and verify that every live table is present on exactly that
         one build. The live folder is untouched.
accept:  verify staging again, keep the live folder as <folder>.previous (replacing an older
         one), move staging live, run that client's generators and show the Data/ impact.
discard: delete the staging folder.

Run: python tools/stage_csv_update.py forever <wowf-build>
     python tools/stage_csv_update.py retail [build] [--product wow|wowt]
     python tools/stage_csv_update.py <client> --accept
     python tools/stage_csv_update.py <client> --discard
Forever has no build auto-detection: pass the discovered wowf build. Generators need both
clients' snapshots for gen_cc_breakers.py. Never accept a staging folder that failed checks.
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from update_data import FILE_RE  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LIVE = {"retail": ROOT / "Documentation" / "wow_spell_csv",
        "forever": ROOT / "Documentation" / "wow_spell_csv_forever"}
FOREVER_GENS = ["gen_forever_rotations.py", "gen_forever_defaults.py", "gen_forever_consumables.py",
                "gen_cc_breakers.py"]
NOT_SHIPPED = {"gen_aura_durations.py"}


def inventory(folder):
    """{table: {builds}} of the CSVs in folder; empty files count as missing."""
    tables = {}
    for path in folder.glob("*.csv"):
        m = FILE_RE.match(path.name)
        if m and path.stat().st_size > 0:
            tables.setdefault(m.group(1), set()).add(m.group(2))
    return tables


def verify(live, staging):
    """The staged build, or exit with the reason staging is not usable."""
    want, got = inventory(live), inventory(staging)
    builds = set().union(*got.values()) if got else set()
    if len(builds) != 1:
        sys.exit(f"staging holds builds {sorted(builds)}; it must hold exactly one")
    missing = sorted(set(want) - set(got))
    if missing:
        sys.exit(f"staging lacks {len(missing)} live table(s): {', '.join(missing)}")
    return builds.pop()


def run(cmd):
    print("-- " + " ".join(str(c) for c in cmd[1:]))
    subprocess.run(cmd, check=True, cwd=ROOT)


def generators(client):
    if client == "forever":
        return FOREVER_GENS
    return [p.name for p in sorted((ROOT / "tools").glob("gen_*.py"))
            if not p.name.startswith("gen_forever_") and p.name not in NOT_SHIPPED]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("client", choices=sorted(LIVE))
    ap.add_argument("build", nargs="?")
    ap.add_argument("--product", default="wow", help="retail auto-detect product (wow/wowt)")
    ap.add_argument("--accept", action="store_true")
    ap.add_argument("--discard", action="store_true")
    args = ap.parse_args()
    live = LIVE[args.client]
    staging = live.with_name(live.name + ".staging")
    previous = live.with_name(live.name + ".previous")

    if args.discard:
        shutil.rmtree(staging, ignore_errors=True)
        print(f"removed {staging}")
        return
    if args.accept:
        build = verify(live, staging)
        if previous.exists():
            shutil.rmtree(previous)
        live.rename(previous)
        staging.rename(live)
        print(f"{live.name} is now build {build}; the old snapshot is in {previous.name}")
        for gen in generators(args.client):
            run([sys.executable, str(ROOT / "tools" / gen)])
        if args.client == "retail":
            bash = shutil.which("bash")
            if bash:
                run([bash, "tools/gen_archetypes.sh"])
            else:
                print("-- gen_archetypes.sh SKIPPED (no bash on PATH)")
        subprocess.run(["git", "diff", "--stat", "--", "Data/"], cwd=ROOT)
        print("Next: review git diff Data/, run the tests, then python tools/deploy_runtime.py --apply."
              f" Restore with: move {previous.name} back if validation fails.")
        return

    if args.client == "forever" and not args.build:
        sys.exit("pass the discovered wowf build: Forever has no build auto-detection")
    if not live.is_dir():
        sys.exit(f"no live CSV folder at {live}")
    shutil.rmtree(staging, ignore_errors=True)
    shutil.copytree(live, staging)
    cmd = [sys.executable, str(ROOT / "tools" / "update_data.py")]
    cmd += [args.build] if args.build else ["--product", args.product]
    run(cmd + ["--dir", str(staging), "--skip-gen"])
    build = verify(live, staging)
    print(f"staging is complete on build {build}. Accept with: "
          f"python tools/stage_csv_update.py {args.client} --accept")


if __name__ == "__main__":
    main()
