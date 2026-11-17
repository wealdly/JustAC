# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
""""Prioritize Your Own Targets": which targets are low value (burst and DoTs wait).

A target not attacking you that is either untagged (nobody fighting it) or tagged by someone else
(UnitIsTapDenied). Every unknown read answers "not low value", and a charge in flight makes the
target yours. Loads the real SpellQueue._IsLowValueTarget from SpellQueue.lua.

Run: python tools/test_own_targets.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("function SpellQueue._IsLowValueTarget(")
    end = source.index("\nend\n", start) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellQueue, secret = {}, {}
        live, onMe, tapped, fighting = true, false, false, false
        function IsLiveAttackableTarget() return live end
        BlizzardAPI = {
            IsSecretValue = function(v) return rawequal(v, secret) end,
            SafeUnitIsUnit = function(a, b) assert(a == "targettarget" and b == "player"); return onMe end,
        }
        function UnitIsTapDenied(u) assert(u == "target"); return tapped end
        function UnitAffectingCombat(u) assert(u == "target"); return fighting end
    """ + source[start:end])
    for setup, expected, why in (
        ("", "untagged", "untagged and not attacking you: burst waits, openers stay free"),
        ("tapped=true; fighting=true", "others", "another player's mob, not on you: burst and DoTs wait"),
        ("fighting=true", False, "tagged by you or your group: yours"),
        ("onMe=true", False, "attacking you: always yours"),
        ("onMe=true; tapped=true", False, "another player's mob attacking you: yours to fight"),
        ("onMe=nil", False, "unknown target of target: nothing held"),
        ("tapped=secret", False, "unreadable tap: nothing held"),
        ("fighting=secret", False, "unreadable combat: nothing held"),
        ("UnitIsTapDenied=function() error('denied') end", False, "denied tap read: nothing held"),
        ("b.landingMelee=true", False, "a charge in flight: the target is about to be yours"),
        ("live=false", False, "no live hostile target"),
    ):
        lua.execute("""
            live, onMe, tapped, fighting = true, false, false, false
            function UnitIsTapDenied(u) return tapped end
            b = {}
        """ + setup)
        got = lua.eval("SpellQueue._IsLowValueTarget(b)")
        assert got == expected, (why, got, expected)
    print("Own targets: untagged or others' mobs not on you are low value; unknowns and charges are not")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
