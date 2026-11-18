# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Immunity learned per kind of creature (DotTracker.lua, WoW Forever).

An IMMUNE result matched to our own DoT cast is remembered by npc id and spell: held for the
session after one sighting, kept on disk once two different mobs showed it, and forgotten when
the DoT is seen on a mob of that kind. Never generalised beyond the npc id it was seen on.

Run: python tools/test_dot_immunity_learning.py
"""
import sys
from pathlib import Path

from lupa import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_forever_dots import PRELUDE, ROOT  # noqa: E402
from test_forever_protection import section  # noqa: E402

REND = 772
GOLEM_A = "Creature-0-6806-0-6-480-000000000A"
GOLEM_B = "Creature-0-6806-0-6-480-000000000B"
GOLEM_C = "Creature-0-6806-0-6-480-000000000C"
WOLF = "Creature-0-6806-0-6-299-000000000D"
PLAYER = "Player-1234-0000000E"

# The real GUID parser and bounded cache from StateHelpers.lua, which the tracker shares.
HELPERS = """
    function strsplit(sep, text)
        local parts = {}
        for part in string.gmatch(text, "[^" .. sep .. "]+") do parts[#parts + 1] = part end
        return (table.unpack or unpack)(parts)
    end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI")
    grouped, petOut = false, false
    BlizzardAPI.IsGrouped = function() return grouped end
    function UnitExists(unit) if unit == "pet" then return petOut end return true end
""" + section("BlizzardAPI/StateHelpers.lua", "local function BoundedGlobalCache", "\n-- Localized creature-type name") \
    + section("BlizzardAPI/StateHelpers.lua", "local function ExtractNPCID", "\n-- CC-failure learning")


def tracker(saved=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().forever = True
    lua.execute(PRELUDE + HELPERS)
    if saved is not None:
        lua.execute("JustACGlobal = " + saved)
    lua.execute((ROOT / "DotTracker.lua").read_text(encoding="utf-8"))
    return lua, lua.eval('LibStub("JustAC-DotTracker")')


def main():
    count = 0

    def check(condition, why):
        nonlocal count
        assert condition, why
        count += 1

    lua, dots = tracker()
    g = lua.globals()

    def target(guid):
        g.targetGUID = guid
        dots.OnTargetChanged()

    def cast_then(kind, at):
        g.now = at
        dots.OnCastSucceeded(REND)
        g.now = at + 0.05
        lua.eval("handlers.UNIT_COMBAT")(None, "UNIT_COMBAT", "target", kind)

    def verdict():
        return tuple(dots.GetDotEvidence(REND))

    def saved(npc):
        return lua.eval(f"JustACGlobal and JustACGlobal.dotImmuneNPCs and JustACGlobal.dotImmuneNPCs[{npc}] "
                        f"and JustACGlobal.dotImmuneNPCs[{npc}][{REND}]")

    target(GOLEM_A)
    check(verdict() == (False, "none", "untracked"), "nothing known before the first cast")
    cast_then("IMMUNE", 10)
    check(verdict() == (True, "policy", "immune-policy"), "the mob itself is held, as before")
    check(saved(480) == 1, "one sighting on disk")

    # A recast on the same mob is not a second sighting.
    cast_then("IMMUNE", 12)
    check(saved(480) == 1, "the same mob counts once")

    target(GOLEM_B)
    check(verdict() == (True, "policy", "immune-known"), "another mob of that kind is held without a cast")
    check(dots.IsDotActiveOnCurrentTarget(REND) is True, "so the queue sinks the spell")
    target(WOLF)
    check(verdict() == (False, "none", "untracked"), "a different creature id is untouched")
    target(PLAYER)
    check(verdict() == (False, "none", "untracked"), "a player has no creature id")
    g.targetGUID = None
    dots.OnTargetChanged()
    check(verdict() == (False, "none", "untracked"), "no readable target: nothing is assumed")

    # A second mob showing it is what reaches disk as knowledge.
    target(GOLEM_B)
    cast_then("IMMUNE", 20)
    check(saved(480) == 2, "two different mobs: confirmed on disk")
    total, threshold, npc, entries = dots.GetImmunityInfo()
    check((total, threshold, npc) == (1, 2, 480) and entries[1].base == REND and entries[1].saved == 2
          and entries[1].session is True, "the inspect data shows the entry")

    # A miss is not immunity.
    target(WOLF)
    cast_then("DODGE", 30)
    check(saved(299) is None and verdict() == (False, "none", "untracked"), "a dodge teaches nothing")

    # The icon showing the DoT on a mob of that kind overrules and forgets what was learned.
    target(GOLEM_C)
    check(verdict()[2] == "immune-known", "held on a third mob")
    g.tracked = False
    check(verdict()[2] == "immune-known", "an icon saying 'not there' does not release it")
    g.tracked = True
    check(verdict() == (True, "confirmed", "cooldown-manager"), "the icon shows it ticking: that wins")
    check(saved(480) is None and lua.eval("JustACGlobal.dotImmuneNPCsN") == 0, "and the entry is forgotten")
    g.tracked = None
    check(verdict() == (False, "none", "untracked"), "afterwards the spell is offered again")

    # With a pet out or in a group the result may be someone else's: one sighting holds only
    # the mob itself, and a second mob showing it is what holds the kind.
    for who, npc in (("petOut", 500), ("grouped", 502)):
        lua.execute(f"grouped, petOut = false, false; {who} = true")
        target(f"Creature-0-6806-0-6-{npc}-00000000A1")
        cast_then("IMMUNE", 40)
        check(verdict()[2] == "immune-policy" and saved(npc) == 1, f"{who}: the mob is held and counted")
        target(f"Creature-0-6806-0-6-{npc}-00000000A2")
        check(verdict() == (False, "none", "untracked"), f"{who}: one sighting does not hold the kind")
        cast_then("IMMUNE", 44)
        target(f"Creature-0-6806-0-6-{npc}-00000000A3")
        check(saved(npc) == 2 and verdict()[2] == "immune-known", f"{who}: a second mob does")
    lua.execute("grouped, petOut = nil, false")
    target("Creature-0-6806-0-6-501-00000000B1")
    cast_then("IMMUNE", 50)
    target("Creature-0-6806-0-6-501-00000000B2")
    check(verdict() == (False, "none", "untracked"), "group state unreadable: treated as not alone")
    lua.execute("grouped = false")

    # Loaded from disk: one sighting is not knowledge, two are.
    lua, dots = tracker("{ dotImmuneNPCs = { [480] = { [772] = 1 }, [481] = { [772] = 2 } }, dotImmuneNPCsN = 2 }")
    g = lua.globals()
    target(GOLEM_A)
    check(verdict() == (False, "none", "untracked"), "a single saved sighting does not hold the spell")
    target("Creature-0-6806-0-6-481-000000000F")
    check(verdict()[2] == "immune-known", "two saved sightings do")

    dots.ClearLearnedImmunity()
    check(verdict() == (False, "none", "untracked") and lua.eval("JustACGlobal.dotImmuneNPCs") is None,
          "clearing throws all of it away")

    # A full saved cache evicts one old creature, not the entire learned database.
    saved_full = ("{dotImmuneNPCs=(function() local t={} "
                  "for i=1,500 do t[i]={[772]=2} end return t end)(),dotImmuneNPCsN=500}")
    lua, dots = tracker(saved_full)
    g = lua.globals()
    target("Creature-0-6806-0-6-1001-000000000A")
    cast_then("IMMUNE", 60)
    check(lua.eval("JustACGlobal.dotImmuneNPCsN") == 500 and saved(1001) == 1,
          "one new creature replaces one old entry at capacity")
    check(lua.eval("(function() local n=0 for i=1,500 do "
                   "if JustACGlobal.dotImmuneNPCs[i] then n=n+1 end end return n end)()") == 499,
          "all but the evicted creature survive")
    target("Creature-0-6806-0-6-1001-000000000C")
    g.tracked = True
    verdict()
    check(saved(1001) is None and lua.eval("JustACGlobal.dotImmuneNPCsN") == 499,
          "positive aura evidence removes a creature from the index")
    g.tracked = None
    target("Creature-0-6806-0-6-1002-000000000B")
    cast_then("IMMUNE", 70)
    check(saved(1002) == 1 and lua.eval("JustACGlobal.dotImmuneNPCsN") == 500,
          "a freed slot accepts a new observation without evicting another")

    # Retail: the GUID is not read there, so nothing is learned or held.
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().forever = False
    lua.execute(PRELUDE + HELPERS)
    lua.execute("JustACGlobal = { dotImmuneNPCs = { [480] = { [772] = 5 } }, dotImmuneNPCsN = 1 }")
    lua.execute((ROOT / "DotTracker.lua").read_text(encoding="utf-8"))
    dots = lua.eval('LibStub("JustAC-DotTracker")')
    lua.globals().targetGUID = GOLEM_A
    dots.OnTargetChanged()
    check(tuple(dots.GetDotEvidence(REND))[2] != "immune-known", "retail never uses the table")
    print(f"ok ({count} checks)")


if __name__ == "__main__":
    main()
