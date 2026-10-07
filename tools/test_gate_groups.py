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
-- The swing leaf: Forever's swing tracker, stubbed. swingRem[type] = seconds to the next
-- auto attack (nil = unknown: not swinging / retail).
swingRem = {}
-- The buff leaf: buffUp = the window reads up (our own cast inside its duration);
-- hasPick = retail's game pick exists.
buffUp, hasPick = false, false
BlizzardAPI = { GetSwingRemaining = function(t) return swingRem[t] end,
                IsBuffWindowActive = function() return buffUp end,
                HasGamePick = function() return hasPick end }
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
# Forever gate types whose evaluator is still to come: `tick` needs an energy-tick model the
# probes have not yet shown is measurable. Until then it answers "no opinion" and never
# blocks, the documented fail-open direction - listed so it is a decision, not drift.
PENDING = {"tick"}
DATA = ("SimcRotations.lua", "ForeverRotations.lua")


def check_coverage():
    emitted = set()
    for name in DATA:
        path = SRC.parent / "Data" / name
        if path.exists():
            emitted |= set(re.findall(r't="([a-z]+)"', path.read_text(encoding="utf-8")))
    handled = set(re.findall(r't == "([a-z]+)"', SRC.read_text(encoding="utf-8")))
    missing = sorted(emitted - handled - UNEVALUATED - PENDING)
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
    # The swing leaf (Forever): main hand by default, `ranged` picks the ranged timer.
    swing = [
        ("{[0]=0.3}", '{t="swing",op="<",n=0.4}', True, "seal just before the main-hand swing"),
        ("{[0]=0.9}", '{t="swing",op="<",n=0.4}', False, "too early for it"),
        ("{[2]=1.5}", '{t="swing",op=">",n=1,ranged=true}', True, "Aimed Shot with time to spare"),
        ("{[0]=1.5}", '{t="swing",op=">",n=1,ranged=true}', None, "ranged timer unknown"),
        ("{}", '{t="swing",op="<",n=0.4}', None, "not swinging: no opinion"),
    ]
    for rem, gate, want, why in swing:
        lua.execute("swingRem = %s" % rem)
        got = run("return GateVerdict(%s, ctx)" % gate)
        if got != want:
            bad += 1
            print("  FAIL swing %s rem=%s got %s, want %s  (%s)" % (gate, rem, got, want, why))
    # A "buff down" gate in the sinking (non-strict) reading: only a provably-up buff on a
    # client with no game pick blocks (Battle Shout must sink while the shout is up).
    buff = [
        ("true", "false", False, "Forever, shout up: blocks"),
        ("false", "false", None, "Forever, shout down: no opinion"),
        ("true", "true", None, "retail: unchanged, no opinion"),
    ]
    for up, pick, want, why in buff:
        lua.execute("buffUp, hasPick = %s, %s" % (up, pick))
        got = run('return GateVerdict({t="buff",id=6673,dur=180,neg=true}, ctx)')
        if got != want:
            bad += 1
            print("  FAIL buff up=%s pick=%s got %s, want %s  (%s)" % (up, pick, got, want, why))
    # A DoT gate on a dying target (Forever): a confirmed low, non-boss target blocks.
    lua.execute("""
DOT_MIN_TARGET_PCT = 35
function UnitExists() return true end
BlizzardAPI.IsUnitHealthBelow = function(_, pct) return targetBelow[pct] end
BlizzardAPI.IsTargetBoss = function() return isBoss end
""")
    dot = [
        ("{[35]=true}", "false", "false", False, "Forever, target under 35%: no new DoT"),
        ("{[35]=false}", "false", "false", None, "healthy target: no opinion"),
        ("{}", "false", "false", None, "health unreadable: no opinion"),
        ("{[35]=true}", "true", "false", None, "a boss low on health: keep DoTs going"),
        ("{[35]=true}", "false", "true", None, "retail (game pick): unchanged"),
    ]
    # A DoT that also hits hard up front (Moonfire) is never blocked on a dying target.
    lua.execute("SpellDB = { IsFrontalDot = function(id) return id == 8921 end }")
    lua.execute("targetBelow, isBoss, hasPick = {[35]=true}, false, false")
    got = run('return GateVerdict({t="dot",id=8921}, ctx)')
    if got is not None:
        bad += 1
        print("  FAIL dot: Moonfire on a dying target got %s, want None (its hit still lands)" % got)
    lua.execute("SpellDB = nil")
    for below, boss, pick, want, why in dot:
        lua.execute("targetBelow, isBoss, hasPick = %s, %s, %s" % (below, boss, pick))
        got = run('return GateVerdict({t="dot",id=772}, ctx)')
        if got != want:
            bad += 1
            print("  FAIL dot below=%s boss=%s pick=%s got %s, want %s  (%s)" % (below, boss, pick, got, want, why))
    lua.execute("BlizzardAPI.IsUnitHealthBelow = nil")
    # Life Tap's "starved" leaf (Forever): among the build's known mana spells none usable and
    # one short of mana. NoteManaStarved is the real function, the game's answers are stubbed.
    src = SRC.read_text(encoding="utf-8")
    lua.execute("""
manaCostCache = {}
cost = {}         -- spellID -> mana cost
usableOf = {}     -- spellID -> { usable, notEnough }
known = {}
function IsPlayerSpell(id) return known[id] == true end
C_Spell = { GetSpellPowerCost = function(id) return cost[id] and { { type = 0, cost = cost[id] } } or {} end }
BlizzardAPI.IsSecretValue = function() return false end
BlizzardAPI.IsSpellUsable = function(id) local u = usableOf[id] or {true, false}; return u[1], u[2] end
""" + extract("CostsMana", src) + "\n" + extract("NoteManaStarved", src))
    starved = [
        # pick, known/cost/usable setup, expected verdict
        ("false", "known={[686]=true,[348]=true,[1454]=true}; cost={[686]=25,[348]=25}; "
                  "usableOf={[686]={false,true},[348]={false,true}}", True,
         "Shadow Bolt and Immolate short of mana: starved (Life Tap's own cost is health)"),
        ("false", "known={[686]=true,[348]=true}; cost={[686]=25,[348]=25}; "
                  "usableOf={[686]={false,true},[348]={true,false}}", False, "one mana spell affordable"),
        ("false", "known={[686]=true}; cost={[686]=25}; usableOf={[686]={false,false}}", None,
         "unusable for another reason (moving, no target): no opinion"),
        ("false", "known={}; cost={}; usableOf={}", None, "nothing that costs mana: no opinion"),
        ("true", "known={[686]=true}; cost={[686]=25}; usableOf={[686]={false,true}}", None,
         "retail (game pick): never asked"),
    ]
    for pick, setup, want, why in starved:
        lua.execute("hasPick = %s; manaCostCache = {}; %s" % (pick, setup))
        lua.execute("NoteManaStarved({686, 348, 1454})")
        got = run('return GateVerdict({t="starved"}, ctx)')
        if got != want:
            bad += 1
            print("  FAIL starved got %s, want %s  (%s)" % (got, want, why))
    bad += check_coverage()
    print("gate groups: %d case(s), %d failure(s)" % (len(cases) + 2 + len(swing) + len(buff) + len(dot) + len(starved), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
