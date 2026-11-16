# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Regenerate the Forever lists and defaults after a priority tweak, and check the result.

Runs gen_forever_rotations.py then gen_forever_defaults.py (defaults read the generated
debuff gates, so the order matters), prints the list contexts whose order or gates changed
and the changed Defaults lines, then runs the Forever tests and tools/check.ps1 on the
generated Lua. See "Changing a Forever priority list" in Documentation/DEV_TOOLING.md.

Run: python tools/forever_regen.py            # regenerate, diff, Forever tests, Lua check
     python tools/forever_regen.py --all      # every tools/test_*.py instead
     python tools/forever_regen.py --no-tests # regenerate and diff only
Exit status 1 when a generator, test or check fails. Deploy afterwards with
tools/deploy_runtime.py --apply.
"""
import argparse
import difflib
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from forever_queue_dump import dump  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ROTATIONS = ROOT / "Data" / "Forever" / "Rotations.lua"
DEFAULTS = ROOT / "Data" / "Forever" / "Defaults.lua"
FOREVER_TESTS = ["test_forever_rotations.py", "test_forever_defaults.py", "test_forever_aura_policy.py",
                 "test_forever_openers.py", "test_forever_general_priorities.py", "test_forever_engine.py",
                 "test_forever_dots.py", "test_gate_groups.py", "test_lua_limits.py"]


def by_context(text):
    rows = {}
    for line in dump(text=text):
        key, _, body = line.partition(": ")
        rows[key] = body
    return rows


def changed_lines(before, after):
    return [line for line in difflib.unified_diff(before.splitlines(), after.splitlines(), n=0, lineterm="")
            if line[:1] in "+-" and not line.startswith(("+++", "---"))]


def run(cmd):
    done = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return done.returncode, (done.stdout + done.stderr).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--all", action="store_true", help="run every tools/test_*.py")
    ap.add_argument("--no-tests", action="store_true", help="skip tests and the Lua check")
    args = ap.parse_args()

    before_rot, before_def = ROTATIONS.read_text(encoding="utf-8"), DEFAULTS.read_text(encoding="utf-8")
    for gen in ("gen_forever_rotations.py", "gen_forever_defaults.py"):
        code, out = run([sys.executable, str(ROOT / "tools" / gen)])
        if code:
            print(out[-2000:])
            sys.exit(f"{gen} failed")
        unresolved = [line for line in out.splitlines() if "not learnable" in line]
        for line in unresolved:
            print("  UNRESOLVED", line.strip())

    after_rot, after_def = ROTATIONS.read_text(encoding="utf-8"), DEFAULTS.read_text(encoding="utf-8")
    old, new = by_context(before_rot), by_context(after_rot)
    changed = [k for k in sorted(set(old) | set(new)) if old.get(k) != new.get(k)]
    print(f"== list contexts changed: {len(changed)}")
    for key in changed:
        print(f"{key}\n  - {old.get(key, '(absent)')}\n  + {new.get(key, '(absent)')}")
    other = [line for line in changed_lines(before_rot, after_rot) if not line[1:].startswith("      ")]
    if other:
        print(f"== other Rotations.lua lines changed: {len(other)} (rank chains, pools, estimates)")
        for line in other[:40]:
            print("  " + line[:160])
    defaults = changed_lines(before_def, after_def)
    print(f"== Defaults.lua lines changed: {len(defaults)}")
    for line in defaults[:60]:
        print("  " + line[:160])
    if args.no_tests:
        return 0

    tests = sorted(p.name for p in (ROOT / "tools").glob("test_*.py")) if args.all else FOREVER_TESTS
    failed = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = pool.map(lambda name: (name, *run([sys.executable, str(ROOT / "tools" / name)])), tests)
        for name, code, out in results:
            if code:
                failed.append(name)
                print(f"  FAIL {name}\n" + "\n".join("    " + l for l in out.splitlines()[-6:]))
    code, out = run(["pwsh", "-NoProfile", "-File", str(ROOT / "tools" / "check.ps1"),
                     str(ROTATIONS), str(DEFAULTS)])
    if code:
        failed.append("check.ps1")
        print(out[-1500:])
    print(f"== {len(tests)} test file(s), Lua check: " + ("all passed" if not failed else "FAILED: " + ", ".join(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
