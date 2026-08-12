#!/usr/bin/env python3
"""Enumerate candidate secret-laundering channels from the client's own API docs.

WoW 12.x seals secrets with a MATCHED PAIR of annotations, and once you see both halves
the search stops being a hunt and becomes arithmetic:

    a sink   declares  SecretArgumentsAddAspect = { A, ... }   -- what it stamps
    a getter declares  SecretReturnsForAspect   = { B, ... }   -- what taints it

A channel can therefore only exist where those two sets DO NOT INTERSECT on the same
object. That is computable offline, exhaustively, from the shipped documentation - so
this script prints the candidates and `/jac inspect channels` measures them. Neither
half is trustworthy alone: the documentation says where to look, the client says what is.

Confirmed by the one channel we already ship: Cooldown:SetCooldownFromDurationObject
declares NO SecretArgumentsAddAspect at all (stamps nothing), while IsShown guards on
Shown - an empty intersection, which is exactly why reading IsShown() works.

WHAT THIS CANNOT FIND is the second survival mechanism, because it is semantic rather
than declared: COLLAPSE TO ABSENCE. C_StringUtil.TruncateWhenZero returns an empty
string for zero; SetText of an empty string leaves the FontString with no text at all;
GetText then returns plain nil even though it guards on Text. Nothing can carry secrecy,
so an aspect guard has nothing to seal. Those are found by reading Documentation strings
for "returns an empty string" style behaviour - the --absence pass below does that.

MEASURED VERDICT (in-game sweep, 19 cells, 2026-08-12): every candidate GAP was sealed -
text shape, bar geometry, texture readback, alpha. Taint follows DERIVATION whatever the
annotations claim. The two channels that work are therefore not oversights but doors left
open on purpose, so `--doors` (the AllowedWhenTainted list) is the output that actually
earns its keep: snapshot it, diff it after each patch, read the additions.

Usage:
    python tools/audit_secret_channels.py [--docs DIR] [--absence] [--doors]
"""
import argparse
import os
import re
import sys

DEFAULT_DOCS = os.path.join("R:", os.sep, "WOW", "00-SOURCE", "wow-ui-source", "Interface",
                            "AddOns", "Blizzard_APIDocumentationGenerated")

# One entry per `{ Name = "X", Type = "Function", ... }` block. The docs are generated and
# uniformly formatted, so a block scanner beats a Lua parser here - and a malformed block
# simply fails to match rather than corrupting the run.
FUNC_RE = re.compile(
    r'\{\s*\n\s*Name = "([A-Za-z_][A-Za-z0-9_]*)",\s*\n\s*Type = "Function",(.*?)\n\t\t\},',
    re.S)
ASPECT_RE = re.compile(r'Enum\.SecretAspect\.([A-Za-z]+)')


def aspects(body, key):
    """The aspect set a function declares for `key`, or None when it declares none."""
    m = re.search(key + r'\s*=\s*\{([^}]*)\}', body)
    if not m:
        return None
    return set(ASPECT_RE.findall(m.group(1)))


def scan(path):
    """-> (sinks, getters, absence, doors) for one documentation file."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    sinks, getters, absence, doors = [], [], [], []
    for name, body in FUNC_RE.findall(text):
        tainted = 'SecretArguments = "AllowedWhenTainted"' in body
        adds = aspects(body, "SecretArgumentsAddAspect")
        rets = aspects(body, "SecretReturnsForAspect")
        # Every door, not just the Set*/Add* ones. The canonical door is TruncateWhenZero,
        # which is neither - collecting only writers hid the single most important entry.
        if tainted:
            doors.append(name)

        # A SINK is a WRITER, not merely a function that accepts a secret. Keying on
        # `AllowedWhenTainted` was wrong and dropped the one channel we actually ship:
        # SetCooldownFromDurationObject is AllowedWhenUntainted, because a DurationObject
        # is an object CONTAINING secrets rather than a secret value, so we may pass it.
        # The `tainted` flag is kept and printed - it says whether a RAW secret fits
        # through - but it does not decide what counts as a sink.
        if re.match(r'^(Set|Add)', name):
            sinks.append((name, adds if adds is not None else set(), tainted))
            doc = re.search(r'Documentation = \{([^}]*)\}', body)
            if doc and re.search(r"empty string|zero|else,", doc.group(1), re.I):
                absence.append((name, " ".join(doc.group(1).split())[:150]))
        elif tainted:
            doc = re.search(r'Documentation = \{([^}]*)\}', body)
            if doc and re.search(r"empty string|zero|else,", doc.group(1), re.I):
                absence.append((name, " ".join(doc.group(1).split())[:150]))

        # A GETTER only counts when it declares an aspect guard. One that guards NOTHING
        # was never part of the secret system on this object, so pairing it is noise - that
        # mistake alone produced 4046 "candidates", most of them voice-chat getters.
        if rets:
            getters.append((name, rets))
    return sinks, getters, absence, doors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs", default=DEFAULT_DOCS)
    ap.add_argument("--absence", action="store_true",
                    help="also list conditional-empty returns (the other mechanism)")
    ap.add_argument("--doors", action="store_true",
                    help="print the sorted AllowedWhenTainted list - the thing to DIFF per patch")
    args = ap.parse_args()

    if not os.path.isdir(args.docs):
        print("docs dir not found: %s" % args.docs, file=sys.stderr)
        return 2

    total_pairs, total_files, all_absence, all_doors = 0, 0, [], []
    for fname in sorted(os.listdir(args.docs)):
        if not fname.endswith(".lua"):
            continue
        sinks, getters, absence, doors = scan(os.path.join(args.docs, fname))
        all_absence.extend((fname, n, d) for n, d in absence)
        all_doors.extend("%s.%s" % (fname.replace("Documentation.lua", ""), n) for n in doors)
        if not sinks or not getters:
            continue
        # Same file == same object/system. Cross-file pairs are meaningless: an aspect is
        # stamped on an OBJECT, so only getters on that same object can be sealed by it.
        # The cross product is worthless and two rounds of filtering proved it: a sink that
        # stamps nothing "opens" every guarded getter on the object, including ones the
        # secret never touches (SetTexture -> GetRotation). Relatedness is semantic and no
        # annotation carries it.
        #
        # So report the SINKS, not pairs. The interesting shape is exactly the one our own
        # working channel has: a raw secret may be passed (*), and the call stamps NO aspect
        # - a secret went in and nothing was sealed on the way. Whatever property that sink
        # drives is then worth reading back, and there are few enough to check by hand.
        open_sinks = [(n, t) for (n, a, t) in sinks if t and not a]
        if not open_sinks:
            continue
        total_files += 1
        guarded = sorted(set(g for g, _ in getters))
        print("\n=== %s ===" % fname.replace("Documentation.lua", ""))
        for sname, _t in open_sinks:
            total_pairs += 1
            print("  %s" % sname)
        if guarded:
            print("    guarded getters here: %s" % ", ".join(guarded[:12]))

    print("\n%d candidate channels across %d systems." % (total_pairs, total_files))
    print("Candidates only. An empty intersection means the docs do not CLAIM a seal - it")
    print("does not mean there is none: measured 2026-08-12, secret text taints")
    print("GetStringWidth/IsTruncated/GetNumLines even though none of them guard on Text.")
    print("Confirm every row with /jac inspect channels before believing it.")

    if args.doors:
        # THE thing to diff across patches, and after a full in-game sweep the reason is
        # settled: measured 2026-08-12, every candidate GAP was sealed - text shape, bar
        # geometry, texture readback, alpha, all secret. The two channels that work are not
        # holes we found, they are doors Blizzard left open deliberately (TruncateWhenZero is
        # literally documented "if the integer is zero, returns an empty string" AND marked
        # AllowedWhenTainted - that is an offered zero test, not an oversight).
        # So new capability arrives as a NEW SANCTIONED PRIMITIVE, not as a gap someone
        # forgot. Snapshot this list, diff it after each patch, and read the additions.
        print("\n=== AllowedWhenTainted doors (%d) - snapshot and diff per patch ===" % len(all_doors))
        for d in sorted(all_doors):
            print("  " + d)

    if args.absence:
        print("\n=== collapse-to-absence candidates (the mechanism aspects cannot describe) ===")
        for fname, name, doc in all_absence:
            print("  %-28s %s\n      %s" % (name, fname.replace("Documentation.lua", ""), doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
