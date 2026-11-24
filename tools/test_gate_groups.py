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

from wow_stubs import LuaRuntime

SRC = Path(__file__).resolve().parent.parent / "SpellQueue.lua"

# Only the two leaves the cases use need stubbing. Lua resolves globals at call time, so a
# branch the cases never reach needs nothing behind it.
PRELUDE = """
SpellQueue = SpellQueue or {}
stealthed = false
function IsStealthed() return stealthed end
ctx = { strict = false }
-- The swing leaf: Forever's swing tracker, stubbed. swingRem[type] = seconds to the next
-- auto attack (nil = unknown: not swinging / retail).
swingRem = {}
-- The buff leaf: buffUp = the window reads up (our own cast inside its duration);
-- hasPick = retail's game pick exists.
buffUp, hasPick = false, false
-- The cast leaf: castMs[id] = the live cast time GetSpellInfo reports (a table = secret).
castMs, castSecret = {}, {}
-- The DoT time-left leaf: timeBelow = DotTracker's answer; asked = the seconds it was asked.
timeBelow, askedSeconds = nil, nil
DotTracker = { IsTimeLeftBelow = function(_, s) askedSeconds = s; return timeBelow end }
BlizzardAPI = { GetSwingRemaining = function(t) return swingRem[t] end,
                IsBuffWindowActive = function() return buffUp end,
                HasGamePick = function() return hasPick end,
                GetDisplaySpellID = function(id) return id == 1 and 2 or id end,
                IsSecretValue = function(v) return rawequal(v, castSecret) end,
                -- The shared cast-time read: plain seconds, nil when unknown or secret.
                GetCastSeconds = function(id)
                    local ms = castMs[id]
                    if type(ms) ~= "number" then return nil end
                    return ms / 1000
                end }
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
DATA = (Path("SimcRotations.lua"), Path("Forever") / "Rotations.lua")


def check_automatic_burst():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellQueue={}
        b={inCombat=true,sinkCooldowns=true,contextOrder='simc',ctxEnemies=1,profile={}}
        boss=false; classification='normal'; selfBuff=true; seconds=180
        pick=false; target=true
        function UnitClassification() return classification end
        function IsLiveAttackableTarget() return target end
        SpellDB={
            IsPureSelfAura=function() return selfBuff end,
            IsDelayedPayoff=function() return delayed end,
            IsTargetDot=function() return targetDot end,
            GainsOverTime=function() return overTime end,
            IsAreaDot=function() return areaDot end,
            GetSpecKey=function() return 'ROGUE_F' end,
            GetThreatRole=function() return threatRole end,
            IsTankTree=function(_, tree) return tree == 'protection' end,
            IsPlayerTank=function() return tree == 'protection' end,
            IsEarlyArmorTree=function(_, tree) return tree == 'arms' end,
        }
        RotationImport={GetForeverTree=function() return tree end}
        BlizzardAPI={
            HasGamePick=function() return pick end,
            IsSecretValue=function(v) return v==secret end,
            IsTargetBoss=function() return boss end,
            GetTargetLevelDelta=function() return levelDelta end,
            PeekBaseCooldownSeconds=function() return seconds end,
            GetDisplaySpellID=function(id) return id end,
            IsGrouped=function() return grouped end,
            IsFightEnding=function(n, pct) return n == 1 and pct == 35 and below35 end,
        }
        DOT_MIN_TARGET_PCT = 35
        levelDelta = nil; grouped = false
        secret={}
    """ + extract("IsWorthwhileFight", SRC.read_text(encoding="utf-8"))
        + "\n" + extract("HoldAutomaticBurst", SRC.read_text(encoding="utf-8")))
    cases = [
        ("", True),
        ("classification='trivial'", True),
        ("classification='minus'", True),
        ("classification='rare'", True),
        ("classification='elite'", False),
        ("classification='rareelite'", False),
        ("classification='worldboss'", False),
        ("boss=true", False), ("boss=nil", True), ("boss=secret", True),
        ("classification=secret", True), ("classification=nil", True),
        ("b.ctxEnemies=2", False), ("b.ctxEnemies=0", True),
        ("b.ctxEnemies=nil", True), ("b.ctxEnemies=secret", True),
        ("pick=true", False), ("target=false", True),
        ("b.inCombat=false", True), ("b.sinkCooldowns=false", False),
        ("b.inCombat=false;classification='elite'", False),
        ("b.inCombat=false;b.ctxEnemies=3", True),
        ("b.contextOrder='off'", False), ("SpellQueue._rotationIsCustom=true", False),
        ("selfBuff=false", False), ("selfBuff=nil", False), ("selfBuff=secret", False),
        ("seconds=119", False), ("seconds=120", True),
        ("seconds=0", False), ("seconds=secret", False),
        ("BlizzardAPI.PeekBaseCooldownSeconds=function() error('denied') end", False),
        ("b.profile.burstTriggers={ROGUE_F={1259799}}", False),
        # A slow payoff on the target alone (Bane of Doom, an armor reduction such as Sunder
        # Armor) waits for a target that lasts, whatever its cooldown or aura shape. A pack of
        # trash does not make that one target live longer.
        ("delayed=true;selfBuff=false;seconds=0", True),
        ("delayed=true;selfBuff=false;classification='elite'", False),
        ("delayed=true;selfBuff=false;levelDelta=-1", True),
        ("delayed=true;selfBuff=false;levelDelta=-2", True),
        ("delayed=true;selfBuff=false;levelDelta=1", False),
        ("delayed=true;selfBuff=false;levelDelta=5", False),
        ("delayed=true;selfBuff=false;levelDelta=0", True),
        ("delayed=true;selfBuff=false;levelDelta=-1;classification='elite'", False),
        ("delayed=true;selfBuff=false;boss=true", False),
        ("delayed=true;selfBuff=false;b.ctxEnemies=2", True),
        ("delayed=true;selfBuff=false;b.ctxEnemies=2;classification='elite'", False),
        ("delayed=false;selfBuff=false;levelDelta=-1", False),
        ("delayed=false;selfBuff=false;levelDelta=1", False),
        ("delayed=true;selfBuff=false;SpellQueue._rotationIsCustom=true", False),
        ("delayed=true;selfBuff=false;b.contextOrder='off'", False),
        # A threat-building armor reduction is not held in a tank tree in a group; alone, or in
        # any other tree, it waits like the rest (Sunder Armor's threat buys a solo tank nothing,
        # and as damage it does not repay its rage on an ordinary target).
        ("delayed=true;selfBuff=false;threatRole='boost';tree='protection';grouped=true", False),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='protection'", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='protection';grouped=nil", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='protection';classification='elite'", False),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='arms'", False),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='fury'", True),
        ("delayed=true;selfBuff=false;threatRole=nil;tree='arms'", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree=nil", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='fury';classification='elite'", False),
        ("delayed=true;selfBuff=false;threatRole='taunt';tree='protection'", True),
        # A normal target fought this long is no quick trash kill.
        ("delayed=true;selfBuff=false;b.now=100;targetFightStartedAt=81", True),
        ("delayed=true;selfBuff=false;levelDelta=-1;b.now=100;targetFightStartedAt=81", True),
        ("delayed=true;selfBuff=false;b.now=100;targetFightStartedAt=80", False),
        ("delayed=true;selfBuff=false;b.now=100;targetFightStartedAt=80;b.inCombat=false", True),
        # Damage a minute away (Bane of Doom): time already spent on the target proves nothing.
        ("delayed=true;targetDot=true;selfBuff=false;b.now=100;targetFightStartedAt=40", True),
        ("delayed=true;targetDot=true;selfBuff=false;b.ctxTargetWorthwhile=true", True),
        ("delayed=true;targetDot=true;selfBuff=false;classification='elite'", False),
        ("delayed=true;targetDot=true;selfBuff=false;levelDelta=1", False),
        ("delayed=true;targetDot=true;selfBuff=false;boss=true", False),
        # Time spent on an ordinary target does not release a long cooldown; a cached verdict
        # that counted that time does not either.
        ("seconds=180;b.now=100;targetFightStartedAt=60", True),
        ("seconds=180;b.now=100;targetFightStartedAt=60;b.ctxWorthwhile=true", True),
        ("seconds=180;b.now=100;targetFightStartedAt=60;classification='elite'", False),
        # A long cooldown is kept for the fights that need it: a regular target three or more
        # levels above releases it, a smaller gap or an unknown level does not.
        ("levelDelta=3", False), ("levelDelta=5", False),
        ("levelDelta=2", True), ("levelDelta=1", True), ("levelDelta=0", True), ("levelDelta=-3", True),
        ("levelDelta=3;SpellQueue._lowValueTarget=true", True),
        ("levelDelta=3;target=false", True),
        # "Prioritize Your Own Targets": a low-value target is never worthwhile.
        ("SpellQueue._lowValueTarget=true;classification='elite'", True),
        ("SpellQueue._lowValueTarget=true;delayed=true;selfBuff=false;boss=true", True),
        ("SpellQueue._lowValueTarget=true;b.profile.burstTriggers={ROGUE_F={1259799}}", False),
        # A resource paid out over time (Bloodrage) waits out a confirmed dying last enemy, even
        # on an elite; any other fight, or an unconfirmed one, offers it as before.
        ("overTime=true;selfBuff=false;b.ctxDying=true;classification='elite'", True),
        ("overTime=true;selfBuff=false;b.ctxDying=false", False),
        ("overTime=true;selfBuff=false;b.ctxDying=nil", False),
        ("overTime=false;selfBuff=false;b.ctxDying=true", False),
        # A slow payoff waits out a confirmed dying last enemy in every tree, grouped tank and
        # early-armor tree included, even on an elite.
        ("delayed=true;selfBuff=false;b.ctxDying=true;classification='elite'", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='protection';grouped=true;b.ctxDying=true", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='arms';b.ctxDying=true", True),
        ("delayed=true;selfBuff=false;threatRole='boost';tree='protection';grouped=true;b.ctxDying=nil", False),
        # Area damage over time (Consecration) waits once the last enemy is below the damage
        # over time line, an elite too; above it, with others around, or unknown, it is offered.
        ("areaDot=true;selfBuff=false;below35=true;classification='elite'", True),
        ("areaDot=true;selfBuff=false;below35=false", False),
        ("areaDot=true;selfBuff=false;below35=true;b.ctxEnemies=2", False),
        ("areaDot=false;selfBuff=false;below35=true", False),
    ]
    for setup, expected in cases:
        lua.execute("""
            b={inCombat=true,sinkCooldowns=true,contextOrder='simc',ctxEnemies=1,profile={}}
            boss=false;classification='normal';selfBuff=true;seconds=180;delayed=false;overTime=false
            levelDelta=nil;threatRole=nil;tree=nil;targetDot=false;grouped=false;areaDot=false;below35=false
            LONG_FIGHT_SECONDS=20;targetFightStartedAt=nil
            pick=false;target=true;SpellQueue._rotationIsCustom=false;SpellQueue._lowValueTarget=nil
            BlizzardAPI.PeekBaseCooldownSeconds=function() return seconds end
        """ + setup)
        assert lua.eval("HoldAutomaticBurst(1259799,b)") == expected, setup
    print("Automatic burst hold: %d cases passed" % len(cases))
    return 0


def check_dying_long_casts():
    """WoW Forever, target below 20%: a cast longer than the global cooldown sinks."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    source = SRC.read_text(encoding="utf-8")
    lua.execute("""
        RANK_SINK, ARCH_UNK, ARCH_MISS, GEOM_PEN, ROLE_PEN, UNHASTED_GCD_SECONDS = 9, 3, 4, 1, 1, 1.5
        castTimes, pick, secret, gcd = {}, false, {}, nil
        BlizzardAPI = {
            HasGamePick = function() return pick end,
            IsSecretValue = function(v) return v == secret end,
            GetCachedSpellInfo = function(id) return {castTime = castTimes[id]} end,
            GetSpellGCD = function() return gcd end,
        }
        SpellDB = {}
        function ResolveBurstTriggers() return nil end
        function pattern() return nil end
    """ + extract("IsLongCast", source) + "\n" + extract("ContextRank", source))
    cases = [
        ("castTimes[1]=2000", True, 9, "long cast on a dying target sinks"),
        ("castTimes[1]=2000", False, 3, "long cast on a healthy target keeps its rank"),
        ("castTimes[1]=1500", True, 3, "a cast no longer than the GCD keeps its rank"),
        ("castTimes[1]=0", True, 3, "an instant keeps its rank"),
        ("castTimes[1]=secret", True, 3, "a hidden cast time is not a long cast"),
        ("castTimes[1]=nil", True, 3, "an unknown cast time is not a long cast"),
        ("castTimes[1]=2000; pick=true", True, 3, "retail (game pick): unchanged"),
        ("castTimes[1]=1400; gcd=1.304", True, 9, "longer than a hasted 1.304s GCD: sinks"),
        ("castTimes[1]=1600; gcd=2", True, 3, "within the spell's own measured GCD: keeps its rank"),
    ]
    bad = 0
    for setup, dying, want, why in cases:
        lua.execute("castTimes, pick, gcd = {}, false, nil; " + setup)
        got = lua.eval("ContextRank(1, nil, nil, nil, false, false, %s)" % ("true" if dying else "false"))
        if got != want:
            bad += 1
            print("  FAIL dying long cast: got %s, want %s  (%s)" % (got, want, why))
    print("Dying long casts: %d cases, %d failure(s)" % (len(cases), bad))
    return bad


def check_forever_lockout_readiness():
    """WoW Forever: isActive with isOnGCD unset after a wand shot is a lockout, not a cooldown."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    text = (SRC.parent / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    start = text.index("function BlizzardAPI.IsSpellReady(")
    end = text.index("\nend\n", start) + len("\nend\n")
    lua.execute("""
        BlizzardAPI = {}
        forever, ownCooldown, cdInfo = true, false, nil
        C_Spell = { GetSpellCooldownDuration = function() end }
        function C_Spell_GetSpellCooldown() return cdInfo end
        function Unsecret() return nil end
        function ReadyByGCDEnd() return false end
        shotLockout = false
        function ShotLockoutOnly() return shotLockout end
        function GetTime() return 0 end
        BlizzardAPI.IsForever = function() return forever end
        BlizzardAPI.IsSpellOnCooldown = function() return ownCooldown end
    """ + text[start:end])
    cases = [
        ("", True, "Forever lockout without an own cooldown: ready"),
        ("ownCooldown = true", False, "Forever own cooldown under the lockout: not ready"),
        ("ownCooldown = true; shotLockout = true", True, "a cooldown that is the shot's lockout: ready"),
        ("forever = false", False, "retail: isActive still means a real cooldown"),
        ("C_Spell.GetSpellCooldownDuration = nil", False, "no ignore-GCD read: unchanged"),
        ("cdInfo = {isActive = false}", True, "nothing active: ready"),
    ]
    bad = 0
    for setup, want, why in cases:
        lua.execute("""forever, ownCooldown = true, false
            C_Spell.GetSpellCooldownDuration = function() end
            cdInfo = {isActive = true}
            shotLockout = false
        """ + setup)
        got = lua.eval("(BlizzardAPI.IsSpellReady(585))")
        if got != want:
            bad += 1
            print("  FAIL lockout readiness: got %s, want %s  (%s)" % (got, want, why))
    print("Forever lockout readiness: %d cases, %d failure(s)" % (len(cases), bad))
    # One threshold question on the duration object: "does it end within N seconds?"
    start = text.index("function BlizzardAPI.CooldownEndsWithin(")
    end = text.index("\nend\n", start) + len("\nend\n")
    lua.execute("""
        active, below = false, nil
        function DurationObjectActive() return active end
        BlizzardAPI.IsDurationBelowSeconds = function() return below end
        C_Spell.GetSpellCooldownDuration = function() return {} end
    """ + text[start:end])
    within = [
        ("active = false", True, "no cooldown of its own"),
        ("active, below = true, true", True, "ends within the window"),
        ("active, below = true, false", False, "a longer cooldown"),
        ("active, below = true, nil", None, "unanswerable stays unknown"),
        ("C_Spell.GetSpellCooldownDuration = nil", None, "no duration read"),
    ]
    for setup, want, why in within:
        lua.execute("""active, below = false, nil
            C_Spell.GetSpellCooldownDuration = function() return {} end
        """ + setup)
        got = lua.eval("BlizzardAPI.CooldownEndsWithin(585, 1.5)")
        if got != want:
            bad += 1
            print("  FAIL cooldown ends within: got %s, want %s  (%s)" % (got, want, why))
    return bad


def check_tank_lift():
    """A threat entry (tank=) ranks just ahead of the list's filler with a strong tank signal only."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    text = SRC.read_text(encoding="utf-8")
    lua.execute("""
        SIMC_UNRANKED, CONTEXT_STRIDE = 1000, 10000
        function ContextRank() return 1 end
        rankState = {simcMode = true}
    """ + extract("rankOf", text))
    cases = [
        ("rankState.tankLift = false", "rankOf(7386, {rank = 10, tank = 9}) > rankOf(772, {rank = 9})",
         "no signal: the list's order"),
        ("rankState.tankLift = true", "rankOf(7386, {rank = 10, tank = 9}) < rankOf(772, {rank = 9})",
         "a strong tank signal: just ahead of the filler"),
        ("rankState.tankLift = true", "rankOf(7386, {rank = 10, tank = 9}) > rankOf(23922, {rank = 6})",
         "still behind an attack on a cooldown"),
        ("rankState.tankLift = true", "rankOf(772, {rank = 9}) == 10000 + 9", "an entry without tank= keeps its rank"),
    ]
    bad = 0
    for setup, expression, why in cases:
        lua.execute(setup)
        if lua.eval(expression) is not True:
            bad += 1
            print("  FAIL tank lift: %s  (%s)" % (expression, why))
    print("Tank lift: %d cases, %d failure(s)" % (len(cases), bad))
    return bad


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
    lua.execute(extract("CompareOp", SRC.read_text(encoding="utf-8")))
    lua.execute(extract("ResourceGateHolds", SRC.read_text(encoding="utf-8")))
    lua.execute(extract("IsStackPayoffContext", SRC.read_text(encoding="utf-8")))
    lua.execute(extract("DotWontStart", SRC.read_text(encoding="utf-8")))
    lua.execute(extract("GateVerdict", SRC.read_text(encoding="utf-8")))
    lua.execute("castOnlyBuffSeen = {}")
    run = lua.eval("function(src) return assert(load(src))() end")
    lua.execute("""
        enemies, occupied = 0, nil
        BlizzardAPI.IsSecretValue = function() return false end
        BlizzardAPI.GetEngagedEnemyCount = function() return enemies end
        BlizzardAPI.IsTotemSlotOccupied = function() return occupied end
    """)
    signal_cases = 0
    for count in (0, 1, 2, 3, 4, 5):
        lua.globals().enemies = count
        assert run('return GateVerdict({t="targets",op=">=",n=4}, ctx)') == (count >= 4)
        # No visible engaged enemy (zero) reads as one: single-target comparisons hold.
        assert run('return GateVerdict({t="targets",op="<",n=3}, ctx)') == (max(count, 1) < 3)
        assert run('return GateVerdict({t="targets",op="<=",n=1}, ctx)') == (max(count, 1) <= 1)
        assert run('return GateVerdict({t="targets",op="=",n=1}, ctx)') == (max(count, 1) == 1)
        assert run('return GateVerdict({t="targets",op=">=",n=2}, ctx)') == (count >= 2)
        assert run('return GateVerdict({t="any",g={{t="targets",op=">=",n=3},{t="unconfirmed"}}}, ctx)') == (count >= 3)
        signal_cases += 2
    for occupied, expected in ((None, False), (True, False), (False, True)):
        lua.globals().occupied = occupied
        assert run('return GateVerdict({t="totem",slot=2,neg=true}, ctx)') == expected
        signal_cases += 1
    for strict in (True, False):
        lua.globals().ctx.strict = strict
        assert run('return GateVerdict({t="unconfirmed"}, ctx)') is False
        signal_cases += 1
    lua.globals().ctx.strict = False
    # In a group: a confirmed read only. Unknown is not a group (Vanish must never be a guess).
    for grouped, expected in ((True, True), (False, False), (None, False)):
        lua.globals().grouped = grouped
        lua.execute("BlizzardAPI.IsGrouped = function() return grouped end")
        assert run('return GateVerdict({t="group"}, ctx)') is expected, grouped
        assert run('return GateVerdict({t="group",neg=true}, ctx)') is (not expected), grouped
        signal_cases += 2
    # Being hit (Fire Blast's "a cast would not finish as planned"): our own hits, never unknown.
    lua.execute("beingHit = nil; SpellQueue._BeingHit = function() return beingHit end")
    for hit, expected in ((True, True), (False, False), (None, False)):
        lua.globals().beingHit = hit
        assert run('return GateVerdict({t="hit"}, ctx)') is expected, ("hit", hit)
        signal_cases += 1
    lua.execute("SpellQueue._BeingHit = nil")
    assert run('return GateVerdict({t="hit"}, ctx)') is False, "no hit signal: not being hit"
    signal_cases += 1
    print(f"Forever signal gates: {signal_cases} cases passed")
    lua.execute("gateCtx={}; BlizzardAPI.IsForever=function() return not hasPick end")
    source = SRC.read_text(encoding="utf-8")
    start = source.index("local PROC_CONTEXT_GATES =")
    end = source.index("\n--- Every evaluable SimC gate", start)
    lua.execute(source[start:end] + "\n"
                + extract("SimcGateBlocks", source))
    preference = '{{t="resource",res="combo_points",op=">=",n=5}}'
    both = "function(...) local a, b = SimcGateBlocks(...); return {a, b} end"
    blocks = lua.eval(both)
    gates = lua.eval(f"function() return {preference} end")()
    upper = lua.eval('function() return {{t="resource",res="combo_points",op="<=",n=1}} end')()
    for pick in (False, True):
        lua.globals().hasPick = pick
        # The imported preference holds in both clients and names points as the shortfall.
        assert list(blocks(gates, 2, "combo_points", 5, False).values()) == [True, True]
        assert list(blocks(gates, 5, "combo_points", 5, False).values()) == [False, False]
        # An explicit hold replaces it; an unknown count never blocks.
        assert list(blocks(gates, 2, "combo_points", 5, True).values()) == [False, False]
        assert list(blocks(gates, None, "combo_points", 5, False).values()) == [False, False]
        # A point cap lowers "at least N": 0 leaves the minimum cost the queue checks
        # separately, a positive cap becomes the new target.
        assert list(blocks(gates, 2, "combo_points", 5, False, 0).values()) == [False, False]
        assert list(blocks(gates, 2, "combo_points", 5, False, 3).values()) == [True, True]
        assert list(blocks(gates, 3, "combo_points", 5, False, 3).values()) == [False, False]
        # An upper bound is not a pooling preference: blocks, but is not a points shortfall.
        assert list(blocks(upper, 3, "combo_points", 5, False, 0).values()) == [True, False]
    lua.execute("hasPick=false; enemies=2")
    assert run('return (SimcGateBlocks({{t="targets",op=">=",n=3}},nil,nil,nil,false))') is True
    lua.execute("enemies=3")
    assert run('return (SimcGateBlocks({{t="targets",op=">=",n=3}},nil,nil,nil,false))') is False
    print("Resource pooling policy: 18 checks passed")

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
    # The cast leaf (Forever): the live cast time of the highest known rank (id 1 shows as 2).
    cast = [
        ("{[2]=0}", '{t="cast",id=1,op="<=",n=1.5}', True, "a proc made it instant (read at its rank)"),
        ("{[2]=3000}", '{t="cast",id=1,op="<=",n=1.5}', False, "full cast"),
        ("{[2]=1500}", '{t="cast",id=1,op="<",n=1.5}', False, "Slam at 1.5s: not shortened"),
        ("{[2]=1000}", '{t="cast",id=1,op="<",n=1.5}', True, "Improved Slam"),
        ("{[1]=0}", '{t="cast",id=1,op="<=",n=1.5}', None, "the rank shown is unreadable: no opinion"),
        ("{[2]=castSecret}", '{t="cast",id=1,op="<=",n=1.5}', None, "secret: no opinion"),
    ]
    for ms, gate, want, why in cast:
        lua.execute("castMs = %s" % ms)
        got = run("return GateVerdict(%s, ctx)" % gate)
        if got != want:
            bad += 1
            print("  FAIL cast %s ms=%s got %s, want %s  (%s)" % (gate, ms, got, want, why))
    # The DoT time-left leaf (Forever): my DoT's time left against N, or a spell's cast time.
    dot = [
        ("true", "{}", '{t="debuff",id=1079,op=">",n=3}', False, 3, "Rip under 3s: no Bite"),
        ("false", "{}", '{t="debuff",id=1079,op=">",n=3}', True, 3, "Rip with time: Bite"),
        ("true", "{}", '{t="debuff",id=703,op="<",n=1}', True, 1, "Garrote running out"),
        ("nil", "{}", '{t="debuff",id=1079,op=">",n=3}', None, 3, "unknown: no opinion"),
        ("true", "{[2]=2000}", '{t="debuff",id=980,op="<=",ncast=1}', True, 2, "against the cast time"),
        ("true", "{}", '{t="debuff",id=980,op="<=",ncast=1}', None, None, "cast time unknown"),
    ]
    for below, ms, gate, want, asked, why in dot:
        lua.execute("timeBelow, askedSeconds, castMs = %s, nil, %s" % (below, ms))
        got = run("return GateVerdict(%s, ctx)" % gate)
        got_asked = lua.eval("askedSeconds")
        if got != want or got_asked != asked:
            bad += 1
            print("  FAIL dot %s got %s/%s, want %s/%s  (%s)" % (gate, got, got_asked, want, asked, why))
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
    # A short group fight (grouped, normal target, no pack): no over-time DoT on a healthy
    # target, while one with a big upfront hit still goes out.
    lua.execute("""SpellDB = { IsFrontalDot = function(id) return id == 8921 end }
targetBelow, isBoss, hasPick = {[35]=false}, false, false""")
    group = [
        ("true", 772, False, "short group fight: Rend skipped"),
        ("true", 8921, None, "short group fight: Moonfire's hit still lands"),
        ("false", 772, None, "solo or worthwhile fight: no opinion"),
    ]
    for short, sid, want, why in group:
        lua.execute("shortGroupFight = %s" % short)
        got = run('return GateVerdict({t="dot",id=%d}, ctx)' % sid)
        if got != want:
            bad += 1
            print("  FAIL group dot %s: got %s, want %s  (%s)" % (sid, got, want, why))
    lua.execute("shortGroupFight, SpellDB = false, nil")
    # A fast solo fight (one regular enemy at or below my level): a new DoT starts only early,
    # and only a spell that is mostly its hit skips the higher floor.
    lua.execute("""FAST_DOT_MIN_TARGET_PCT = 70
SpellDB = { IsFrontalDot = function(id) return id == 8921 or id == 348 end,
            IsMostlyUpfrontDot = function(id) return id == 8921 end }
isBoss, hasPick = false, false""")
    fast = [
        ("true", "{[70]=true,[35]=false}", 772, False, "fast fight, target under 70%: no new Rend"),
        ("true", "{[70]=false,[35]=false}", 772, None, "fast fight, target still healthy: no opinion"),
        ("true", "{}", 772, None, "fast fight, health unreadable: no opinion"),
        ("true", "{[70]=true,[35]=false}", 348, False, "fast fight: a one-third hit (Immolate) is not exempt"),
        ("true", "{[70]=true,[35]=true}", 8921, None, "fast fight: a spell that is mostly its hit still goes out"),
        ("false", "{[70]=true,[35]=false}", 772, None, "not a fast fight: only the 35% rule applies"),
        ("false", "{[70]=true,[35]=true}", 348, None, "not a fast fight: a frontal spell keeps its exemption"),
    ]
    for fastFight, below, sid, want, why in fast:
        lua.execute("fastSoloFight, targetBelow = %s, %s" % (fastFight, below))
        got = run('return GateVerdict({t="dot",id=%d}, ctx)' % sid)
        if got != want:
            bad += 1
            print("  FAIL fast dot %s: got %s, want %s  (%s)" % (sid, got, want, why))
    # A DoT that already ran on this target may be renewed; the ordinary floor still applies.
    lua.execute("ranOnTarget = true; DotTracker.HasRunOnTarget = function() return ranOnTarget end")
    renew = [
        ("true", "{[70]=true,[35]=false}", None, "fast fight: a DoT that ran out is renewed"),
        ("true", "{[70]=true,[35]=true}", False, "renewal still stops on a dying target"),
        ("false", "{[70]=true,[35]=false}", False, "first application in a fast fight stays blocked"),
    ]
    for ran, below, want, why in renew:
        lua.execute("fastSoloFight, ranOnTarget, targetBelow = true, %s, %s" % (ran, below))
        got = run('return GateVerdict({t="dot",id=772}, ctx)')
        if got != want:
            bad += 1
            print("  FAIL renew ran=%s: got %s, want %s  (%s)" % (ran, got, want, why))
    # On a dying target a frontal DoT keeps its exemption only if instant or mostly its hit.
    lua.execute("fastSoloFight, ranOnTarget, targetBelow = false, false, {[70]=true,[35]=true}")
    dying = [
        ("{[348]=2000}", 348, False, "hard-cast Immolate: most of it would be lost"),
        ("{[348]=0}", 348, None, "made instant: the hit is free to take"),
        ("{}", 348, None, "cast time unknown: keeps the exemption"),
        ("{[8921]=2000}", 8921, None, "a cast that is mostly its hit still pays"),
    ]
    for ms, sid, want, why in dying:
        lua.execute("castMs = %s" % ms)
        got = run('return GateVerdict({t="dot",id=%d}, ctx)' % sid)
        if got != want:
            bad += 1
            print("  FAIL dying frontal %s ms=%s: got %s, want %s  (%s)" % (sid, ms, got, want, why))
    lua.execute("castMs, targetBelow, shortGroupFight = {[348]=2000}, {[35]=false}, true")
    if run('return GateVerdict({t="dot",id=348}, ctx)') is not None:
        bad += 1
        print("  FAIL short group fight: a hard-cast frontal DoT on a healthy target still goes out")
    lua.execute("castMs, shortGroupFight = {}, false; DotTracker.HasRunOnTarget = nil")
    lua.execute("hasPick = true; fastSoloFight, targetBelow = true, {[70]=true}")
    if run('return GateVerdict({t="dot",id=772}, ctx)') is not None:
        bad += 1
        print("  FAIL fast dot: retail (game pick) must be unchanged")
    lua.execute("fastSoloFight, hasPick, SpellDB = false, false, nil")
    # Waiting for time on a DoT the queue will not start is met (Ferocious Bite waits on Rip):
    # on a dying target or in a short group fight; never on a healthy target, a boss, or
    # in the strict (leading) reading, where the time left decides as before.
    wait = [
        ("{[35]=true}", "false", "false", "nil", True, "dying target, no Rip: Bite spends"),
        ("{[35]=false}", "false", "false", "nil", False, "healthy target: Bite waits on Rip"),
        ("{[35]=true}", "true", "false", "nil", False, "a boss: Rip still goes out, Bite waits"),
        ("{[35]=false}", "false", "true", "nil", True, "short group fight: Rip never starts"),
        ("{[35]=true}", "false", "false", "true", False, "strict reading: unchanged"),
    ]
    for below, boss, short, strict, want, why in wait:
        lua.execute("timeBelow, targetBelow, isBoss, shortGroupFight = true, %s, %s, %s" % (below, boss, short))
        got = run('return GateVerdict({t="debuff",id=1079,op=">",n=3}, {strict=%s})' % strict)
        if got != want:
            bad += 1
            print("  FAIL dot wait: got %s, want %s  (%s)" % (got, want, why))
    lua.execute("targetBelow, isBoss, shortGroupFight = {}, false, false")
    # A cast-only stack requirement (Maelstrom Weapon) applies once the buff has been seen this
    # session; a player who cannot gain it (no rune) keeps a normal full-length cast.
    lua.execute("""
castOnlyBuffSeen, playerStacks = {}, 0
function StackAtLeast(unit, id, k)
    if unit == "player" and playerStacks ~= nil then return playerStacks >= k end
    return nil
end
function StackHolds(unit, g) return StackAtLeast(unit, g.id, g.n) end
BlizzardAPI.GetAuraStackAtLeast = function() return true end
""")
    maelstrom = '{t="stack",id=408505,op=">=",n=5,required=true,castOnly=true}'
    cast_only = [
        ("playerStacks = 0", maelstrom, True, "never seen: no rune, a normal cast"),
        ("playerStacks = 2", maelstrom, False, "seen: the five-stack requirement applies"),
        ("playerStacks = 0", maelstrom, False, "seen earlier this session: still required"),
        ("playerStacks = 5", maelstrom, True, "five stacks: instant cast"),
        ("castOnlyBuffSeen, playerStacks = {}, 0",
         '{t="stack",id=408505,op=">=",n=5,required=true}', False, "not cast-only: never waived"),
        ("castOnlyBuffSeen, playerStacks = {}, nil",
         maelstrom, False, "unreadable stacks: the requirement stays"),
        ("castOnlyBuffSeen, playerStacks = {}, 0",
         '{t="stack",id=408505,op=">=",n=5,required=true,castOnly=true,tgt=true}', False,
         "a target stack is never waived"),
    ]
    for setup, gate, want, why in cast_only:
        lua.execute(setup)
        got = run("return GateVerdict(%s, ctx)" % gate)
        if got != want:
            bad += 1
            print("  FAIL cast-only %s: got %s, want %s  (%s)" % (setup, got, want, why))
    # Target stacks unreadable: my own counted applications answer (Sunder Armor).
    lua.execute("ownStacks = nil; DotTracker.GetOwnStacks = function() return ownStacks end")
    sunder = '{t="stack",id=7386,op="<",n=1,tgt=true}'
    own = [
        ("nil", sunder, None, "never sundered here: no opinion"),
        ("0", sunder, True, "known gone: apply it"),
        ("2", sunder, False, "two of mine up: not below one"),
        ("5", '{t="stack",id=7386,op=">=",n=5,tgt=true}', True, "five counted"),
    ]
    for stacks, gate, want, why in own:
        lua.execute("ownStacks = %s" % stacks)
        got = run("return GateVerdict(%s, ctx)" % gate)
        if got != want:
            bad += 1
            print("  FAIL own stacks %s: got %s, want %s  (%s)" % (stacks, got, want, why))
    lua.execute("DotTracker.GetOwnStacks = nil")
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
    # The cd leaf on Forever: a spell not learned yet reads as unavailable (on cooldown), so
    # "Serpent Sting while Aimed Shot is on cooldown" holds for a hunter without Aimed Shot.
    lua.execute("onCd = {}; BlizzardAPI.IsSpellOnCooldown = function(id) return onCd[id] == true end")
    cd = [
        # pick, known, on cd, gate, expected
        ("false", "{}", "{}", '{t="cd",id=19434,neg=true}', True, "Forever, Aimed Shot not learned: counts as on cooldown"),
        ("false", "{[19434]=true}", "{}", '{t="cd",id=19434,neg=true}', False, "learned and ready: not on cooldown"),
        ("false", "{[19434]=true}", "{[19434]=true}", '{t="cd",id=19434,neg=true}', True, "learned and on cooldown"),
        ("false", "{}", "{}", '{t="cd",id=19434}', False, "not learned: never 'ready'"),
        ("true", "{}", "{}", '{t="cd",id=19434,neg=true}', False, "retail (game pick): unchanged"),
    ]
    for pick, known, oncd, gate, want, why in cd:
        lua.execute("hasPick = %s; known = %s; onCd = %s" % (pick, known, oncd))
        got = run("return GateVerdict(%s, ctx)" % gate)
        if got != want:
            bad += 1
            print("  FAIL cd %s got %s, want %s  (%s)" % (gate, got, want, why))
    bad += check_coverage()
    bad += check_automatic_burst()
    bad += check_dying_long_casts()
    bad += check_forever_lockout_readiness()
    bad += check_tank_lift()
    print("gate groups: %d case(s), %d failure(s)" % (len(cases) + 2 + len(swing) + len(buff) + len(dot) + len(starved) + len(cd), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
