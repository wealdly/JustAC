# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Sync the validated checkout into the shared local runtime and verify both clients.

Implements the "Validate, deploy, verify" steps of Documentation/DEV_TOOLING.md
(runtime test sync). Run it only after tests and tools/check.ps1 pass.

Required files: JustAC.toc, its active entries and their XML Include/Script closure.
Every other runtime file that also exists in the checkout (Bindings.xml, LICENSE,
README.md, assets) is compared too. Nothing is ever deleted; runtime-only files are
reported. After copying, every compared runtime file is verified against the checkout;
each client AddOns path must be a junction to that runtime. With local Debug/Research sources, the companion is
refreshed through tools/install_research.ps1 and its Lua/LICENSE files verified.

Run: python tools/deploy_runtime.py            # plan only
     python tools/deploy_runtime.py --apply    # copy differing files, then verify
Paths default to the documented local layout; override with --runtime and --client
(repeatable) or the JUSTAC_RUNTIME / JUSTAC_CLIENTS (';'-separated) environment variables.
"""
import argparse
import datetime
import functools
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lua51 import lua51_compile_error  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RUNTIME = r"<sources>\JustAC-runtime\JustAC"
DEFAULT_CLIENTS = [r"C:\Blizzard\World of Warcraft\_retail_\Interface\AddOns",
                   r"C:\Blizzard\World of Warcraft\_forever_\Interface\AddOns"]
SKIP_DIRS = {".git", "__pycache__"}


@functools.lru_cache(maxsize=None)
def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def toc_closure(toc):
    """Relative paths of the TOC and every active file it loads, XML includes resolved."""
    files, pending = {toc.name}, []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            pending.append(line.replace("\\\\", "\\").replace("\\", "/"))
    while pending:
        rel = pending.pop()
        if rel in files:
            continue
        files.add(rel)
        if rel.lower().endswith(".xml") and (ROOT / rel).exists():
            base = os.path.dirname(rel)
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
            text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
            for ref in re.findall(r'<(?:Include|Script)\s+file="([^"]+)"', text):
                pending.append(os.path.normpath(os.path.join(base, ref.replace("\\", "/"))).replace("\\", "/"))
    return files


def runtime_files(runtime):
    out = set()
    for dirpath, dirnames, filenames in os.walk(runtime):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            out.add(os.path.relpath(os.path.join(dirpath, name), runtime).replace("\\", "/"))
    return out


def junction_target(path):
    try:
        target = os.readlink(path)
    except OSError:
        return None
    return os.path.normcase(os.path.normpath(target.removeprefix("\\\\?\\")))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true", help="copy differing files (default: plan only)")
    ap.add_argument("--runtime", default=os.environ.get("JUSTAC_RUNTIME", DEFAULT_RUNTIME))
    ap.add_argument("--client", action="append",
                    help="a client AddOns directory (repeatable)")
    args = ap.parse_args()
    clients = args.client or [c for c in os.environ.get("JUSTAC_CLIENTS", "").split(";") if c] or DEFAULT_CLIENTS
    runtime = Path(args.runtime)
    if not runtime.is_dir():
        sys.exit(f"runtime not found: {runtime}")

    required = toc_closure(ROOT / "JustAC.toc")
    missing_src = sorted(r for r in required if not (ROOT / r).is_file())
    if missing_src:
        sys.exit("TOC entries missing from the checkout: " + ", ".join(missing_src))
    present = runtime_files(runtime)
    compared = required | {r for r in present if (ROOT / r).is_file()}
    copy = sorted(r for r in compared
                  if not (runtime / r).is_file() or digest(ROOT / r) != digest(runtime / r))
    extra = sorted(present - compared)

    print(f"runtime: {runtime}\nchecked {len(compared)} files ({len(required)} from the TOC closure)")
    for r in copy:
        print(f"  {'copy' if args.apply else 'would copy'}  {r}")
    for r in extra:
        print(f"  runtime only (left alone)  {r}")
    if not args.apply:
        print(f"{len(copy)} file(s) differ; rerun with --apply to deploy")
        return 1 if copy else 0
    # A Lua file that Lua 5.1 will not compile (a syntax error, more than 60 upvalues or 200
    # locals in one function) kills the whole file in game. Refuse the deploy instead.
    blocked = []
    for r in copy:
        if r.endswith(".lua"):
            error = lua51_compile_error((ROOT / r).read_text(encoding="utf-8"), r)
            if error:
                blocked.append(f"{r}: {error}")
            elif error is False:
                print("  note: no Lua 5.1 runtime (pip install lupa): compile not checked")
                break
    if blocked:
        for b in blocked:
            print(f"  REFUSED  Lua 5.1 will not compile {b}")
        print(f"nothing copied: {len(blocked)} file(s) would not load in game")
        return 1
    for r in copy:
        (runtime / r).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / r, runtime / r)

    # Fresh reads: the runtime files just changed, so they bypass the digest cache.
    problems = [f"{runtime / r} differs from the checkout after copying" for r in sorted(compared)
                if digest.__wrapped__(runtime / r) != digest(ROOT / r)]
    want = os.path.normcase(os.path.normpath(str(runtime)))
    research = (ROOT / "Debug" / "Research").is_dir()
    if research:
        # Stamp the build this deploy puts in the clients: a capture session writes it into its
        # own rows, so an archived log says which code produced it. Local companion only.
        def git(*args):
            done = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
            return done.stdout.strip() if done.returncode == 0 else ""
        stamp = "deployed=%s commit=%s dirty=%s" % (
            datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), git("rev-parse", "--short", "HEAD") or "unknown",
            "true" if git("status", "--porcelain") else "false")
        (ROOT / "Debug" / "Research" / "BuildStamp.lua").write_text(
            "-- Generated by tools/deploy_runtime.py at every deploy. Do not edit.\n"
            'local DebugCommands = LibStub("JustAC-DebugCommands", true)\n'
            'if DebugCommands then DebugCommands._buildStamp = "%s" end\n' % stamp,
            encoding="utf-8", newline="\n")
        script = ROOT / "tools" / "install_research.ps1"
        done = subprocess.run(["pwsh", "-NoProfile", "-File", str(script), "-AddOnsPath", str(runtime.parent)],
                              cwd=ROOT, capture_output=True, text=True)
        if done.returncode != 0:
            problems.append("install_research.ps1 failed: " + (done.stderr or done.stdout).strip()[-300:])
    research_files = [p for p in (ROOT / "Debug" / "Research").glob("*.lua")] if research else []
    for client in clients:
        addon = Path(client) / "JustAC"
        if junction_target(addon) != want:
            problems.append(f"{addon} is not a junction to {runtime}")
            continue
        if research:
            companion = Path(client) / "JustAC_Research"
            for src in research_files + [ROOT / "LICENSE"]:
                dst = companion / src.name
                if not dst.is_file() or digest(src) != digest.__wrapped__(dst):
                    problems.append(f"{dst} differs from {src.relative_to(ROOT)}")
    for p in problems:
        print("  PROBLEM", p)
    print(f"copied {len(copy)} file(s); {len(clients)} client(s) "
          + ("verified" if not problems else f"with {len(problems)} problem(s)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
