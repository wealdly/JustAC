#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Audit the locale tables against what the code actually asks for.

    python tools/audit_locales.py            # report
    python tools/audit_locales.py --strict   # exit 1 on any finding (CI / pre-release)

WHY THIS EXISTS
---------------
AceLocale's fallback hides a missing key badly. The default locale (enUS, registered
first) fills only unset keys, so a key missing from deDE renders as ENGLISH - visibly
fine, easy to miss, harmless. But a key missing from enUS TOO has no fallback left:
AceLocale raises "Missing entry for '<key>'" at the point the option is drawn.

The trap is that comparing the locale files against EACH OTHER cannot see it. They
agree perfectly - all eleven are equally missing the key. That is exactly how
'Show Soothe Cue desc' shipped: a parity sweep reported "357 keys everywhere" and
called it complete. Parity is not completeness. The only ground truth is the source:
every key the code looks up must EXIST, and every key defined should be looked up.

Checks
  1. MISSING  - referenced by the code, absent from enUS (this one throws in game).
  2. UNUSED   - defined in enUS, referenced nowhere (dead weight, drifts stale).
  3. PARITY   - a translation missing a key enUS has (renders English, not fatal).

Reference forms understood: L["key"], and the W.spellDesc/W.itemDesc helpers, whose
FIRST argument is a bare locale key rather than an L[...] lookup - that indirection
is what hid all three of the original findings from a naive grep.

WHAT THIS CANNOT SEE
--------------------
A key built at runtime - L["Burst Source " .. source] - is invisible to any static
scan, because the key does not exist in the source text. That is not a hypothetical:
the first version of this tool reported "0 missing" while three such keys were absent
from every locale, and one of them threw in game minutes later. A tool that quietly
skips what it cannot check is worse than no tool, because the PASS is read as proof.

So check 4 finds those lookups and reports them as UNVERIFIABLE with file:line. It
does not fail the build - it cannot know whether they resolve - but it refuses to let
a clean run imply coverage it does not have. Each one needs a human to confirm every
value the expression can take has a key.
"""
import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES = os.path.join(ROOT, "Locales")
KEY = r'L\["((?:[^"\\]|\\.)*)"\]'
# Helpers taking a bare locale key as their first argument.
BARE = r'\bW\.(?:spellDesc|itemDesc)\(\s*"((?:[^"\\]|\\.)*)"'
# A lookup whose key is an EXPRESSION, not a literal - unverifiable, see docstring.
# Lookbehind rejects CTRL[ and the like; `L[#` is the array-append idiom, not a lookup.
DYN = r'(?<![\w.])L\[(?!["#])'


def defined_in(locale):
    path = os.path.join(LOCALES, locale + ".lua")
    with open(path, encoding="utf-8") as fh:
        return set(re.findall(KEY + r"\s*=", fh.read()))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if any check fails")
    args = ap.parse_args()

    os.chdir(ROOT)
    enus = defined_in("enUS")

    refs, dynamic = {}, []
    for path in glob.glob("**/*.lua", recursive=True):
        parts = path.split(os.sep)
        if parts[0] in ("Locales", "Libs", "dist") or "Libs" in parts:
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for pattern in (KEY, BARE):
            for m in re.finditer(pattern, src):
                line = src[:m.start()].count("\n") + 1
                refs.setdefault(m.group(1), []).append("%s:%d" % (path, line))
        for m in re.finditer(DYN, src):
            line = src[:m.start()].count("\n") + 1
            snippet = src[m.start():src.find("\n", m.start())].strip()
            dynamic.append("%s:%d  %s" % (path, line, snippet[:76]))

    others = sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(LOCALES, "*.lua"))
                    if not p.endswith("enUS.lua"))
    print("enUS defines %d keys; code references %d; %d translations\n"
          % (len(enus), len(refs), len(others)))

    failures = 0

    def report(title, items, fatal=True):
        nonlocal failures
        tag = "" if fatal else "  (advisory)"
        if not items:
            print("PASS  %s%s" % (title, tag))
            return
        print("%s  %s: %d%s" % ("FAIL" if fatal else "WARN", title, len(items), tag))
        for line in items:
            print("        %s" % line)
        if fatal:
            failures += len(items)

    report("every referenced key exists in enUS",
           ["%r  %s" % (k, refs[k][0]) for k in sorted(refs) if k not in enus])
    # UNUSED is only sound when every lookup is a literal. One runtime-built key makes it
    # unfalsifiable - 'Burst Source simc' is reached solely as L["Burst Source " .. source],
    # so a literal scan calls it dead while it is the very key that threw in game. Advisory
    # while any dynamic lookup exists, rather than a failure that trains you to ignore it.
    report("every enUS key is referenced",
           ["%r" % k for k in sorted(enus) if k not in refs],
           fatal=not dynamic)
    if dynamic:
        print("      (advisory: %d runtime-built lookup(s) below can reach keys a literal "
              "scan cannot see)" % len(dynamic))

    gaps = []
    for loc in others:
        missing = enus - defined_in(loc)
        if missing:
            gaps.append("%s missing %d: %s" % (loc, len(missing),
                                               ", ".join(repr(k) for k in sorted(missing)[:4])))
    report("every translation covers enUS", gaps)

    # 4. Runtime-built keys. Reported, never silently skipped - see the module docstring.
    if dynamic:
        print("\nUNVERIFIABLE  %d runtime-built lookup(s) - confirm every value has a key:"
              % len(dynamic))
        for line in dynamic:
            print("        %s" % line)

    print()
    if failures and args.strict:
        print("%d finding(s); --strict set" % failures)
        return 1
    print("no blocking findings" if not failures else "%d finding(s)" % failures)
    return 0


if __name__ == "__main__":
    sys.exit(main())
