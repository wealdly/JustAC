# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Three-valued and/or over nested gate groups, checked outside the game.
#
# GateVerdict is the one place a gate's true / false / cannot-tell answer is decided, and
# the group half of it is pure logic: no combat state, just how an unknown member moves
# through an `any` or an `all`. That half is worth failing a commit over, so it runs here
# rather than only via /jac inspect. The leaves stay out of scope - they read the live game
# and cannot be faked honestly - so the cases below use the two leaves that need nothing:
# a stealth gate (one stubbed global) and a `cd` gate, which has no evaluator and is the
# canonical unknown.
#
# Run: python tools/test_gate_groups.py

import re
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "SpellQueue.lua"

PRELUDE = """
stealthed = false
function IsStealthed() return stealthed end
function UnitExists() return false end
function UnitCanAttack() return false end
BlizzardAPI = {}
SpellQueue = {}
function ResourceGateHolds() return nil end
function ThresholdGateBlocks() return false end
function StackHolds() return nil end
ctx = { strict = false }
"""


def extract(name, text):
    """The named local function, up to the `end` in its own column."""
    start = text.index("local function %s(" % name)
    indent = len(text[:start].split("\n")[-1])
    m = re.compile(r"^%send$" % (" " * indent), re.M).search(text, start)
    assert m, name
    return text[start:m.end()].replace("local function", "function", 1)


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(extract("GateVerdict", SRC.read_text(encoding="utf-8")))
    run = lua.eval("function(src) return assert(load(src))() end")

    ON = '{t="stealth"}'            # holds only while stealthed
    OFF = '{t="stealth",neg=true}'  # holds only while NOT stealthed
    UNK = '{t="cd"}'                # no evaluator: the canonical unknown
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
    print("gate groups: %d case(s), %d failure(s)" % (len(cases) + 1, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
