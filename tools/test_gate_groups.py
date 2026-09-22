# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Three-valued and/or over nested gate groups, checked outside the game.
#
# GateVerdict is the one place a gate's true / false / cannot-tell answer is decided, and
# the group half of it is pure logic: no combat state, just how an unknown member moves
# through an `any` or an `all`. That half is worth failing a commit over, so it runs here
# rather than only via /jac inspect. The leaves stay out of scope - they read the live game
# and cannot be faked honestly - so the cases below use the two leaves that need nothing:
# a stealth gate (one stubbed global) and a dot gate, the one type the queue deliberately
# cannot answer.
#
# Run: python tools/test_gate_groups.py

import re
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "SpellQueue.lua"

# Only the two leaves the cases use need stubbing. Lua resolves globals at call time, so a
# branch the cases never reach needs nothing behind it.
PRELUDE = """
stealthed = false
function IsStealthed() return stealthed end
ctx = { strict = false }
"""


def extract(name, text):
    """The named local function, up to the `end` in its own column."""
    start = text.index("local function %s(" % name)
    indent = len(text[:start].split("\n")[-1])
    m = re.compile(r"^%send$" % (" " * indent), re.M).search(text, start)
    assert m, name
    return text[start:m.end()].replace("local function", "function", 1)


# Gate types the queue deliberately has no evaluator for. Anything else appearing in the
# generated data without a branch in GateVerdict is a gate that silently does nothing -
# which is how a cooldown condition sat inert for as long as it did.
#
# `dot` is here for a measured reason, not an unfinished one. Answering it needs a live
# aura instance on the target, and 12.1.0 closed every route to one in combat. Measured
# in game 2026-09-22, Feral, bleeds up on the target the whole time:
#
#   instance list      works out of combat (an id, and the duration object answers
#                      "below 30% left" outright) - DENIED in combat
#   lookup by spell    nil in combat with four bleeds tracked on that target; the call
#                      requires a non-secret aura and in combat there is no such thing
#   aura container     renders only: every region, font string and cooldown handed to it
#                      is marked with secret aspects, so nothing reads back
#
# The duration object itself is NOT restricted - only every handle to one is. Zero
# confirmed instances in 38 samples. Do not re-litigate without an API change.
UNEVALUATED = {"dot"}


def check_coverage():
    data = (SRC.parent / "Data" / "SimcRotations.lua").read_text(encoding="utf-8")
    emitted = set(re.findall(r't="([a-z]+)"', data))
    handled = set(re.findall(r't == "([a-z]+)"', SRC.read_text(encoding="utf-8")))
    missing = sorted(emitted - handled - UNEVALUATED)
    if missing:
        print("  FAIL gate types in the data with no evaluator: %s" % ", ".join(missing))
    return 1 if missing else 0


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(extract("GateVerdict", SRC.read_text(encoding="utf-8")))
    run = lua.eval("function(src) return assert(load(src))() end")

    ON = '{t="stealth"}'            # holds only while stealthed
    OFF = '{t="stealth",neg=true}'  # holds only while NOT stealthed
    UNK = '{t="dot",id=1}'          # no evaluator at all: the canonical unknown
    cases = [
        # stealthed, gate, expected
        (True,  'any', [ON, UNK],   True,  "one member holding settles an `any`"),
        (True,  'any', [OFF, UNK],  None,  "an unknown member keeps `any` undecided"),
        (True,  'any', [OFF, OFF],  False, "`any` fails only when every member fails"),
        (True,  'all', [ON, ON],    True,  "`all` holds when every member holds"),
        (True,  'all', [ON, UNK],   None,  "an unknown member keeps `all` undecided"),
        (True,  'all', [OFF, UNK],  False, "one member failing settles an `all`"),
        (False, 'any', [ON, OFF],   True,  "the stub really does flip the leaves"),
        (True,  'any', [],          None,  "an empty group decides nothing"),
    ]
    bad = 0
    for stealthed, kind, members, want, why in cases:
        lua.execute("stealthed = %s" % str(stealthed).lower())
        gate = '{t="%s",g={%s}}' % (kind, ",".join(members))
        got = run("return GateVerdict(%s, ctx)" % gate)
        if got != want:
            bad += 1
            print("  FAIL %-5s %-28s got %s, want %s  (%s)"
                  % (kind, "".join(members) or "{}", got, want, why))
    # nesting: a group inside a group is answered the same way
    lua.execute("stealthed = true")
    nested = '{t="any",g={{t="all",g={%s,%s}},%s}}' % (OFF, ON, ON)
    got = run("return GateVerdict(%s, ctx)" % nested)
    if got is not True:
        bad += 1
        print("  FAIL nested: got %s, want True  (%s)" % (got, nested))
    bad += check_coverage()
    print("gate groups: %d case(s), %d failure(s)" % (len(cases) + 2, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
