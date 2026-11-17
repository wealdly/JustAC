# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""A dead target is no target in SpellQueue: the module's UnitExists reads a plainly dead target
as absent (the pull preview, not attacks on a corpse), leaves every other unit alone, and keeps
the target when its death cannot be read. Loads the real wrapper from SpellQueue.lua.

Run: python tools/test_dead_target.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("local RawUnitExists = UnitExists")
    end = source.index("local UnitCanAttack = UnitCanAttack")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        secret, exists, dead = {}, {target = true, pet = true}, {}
        function UnitExists(unit) return exists[unit] == true end
        function UnitIsDeadOrGhost(unit)
            if dead[unit] == 'error' then error('denied') end
            return dead[unit]
        end
        BlizzardAPI = { IsSecretValue = function(v) return rawequal(v, secret) end }
    """ + source[start:end] + "\nfunction Exists(unit) return UnitExists(unit) end")
    for setup, unit, expected, why in (
        ("", "target", True, "a live target is a target"),
        ("dead.target = true", "target", False, "a dead target is no target"),
        ("dead.target = secret", "target", True, "an unreadable death keeps the target"),
        ("dead.target = 'error'", "target", True, "a failed death read keeps the target"),
        ("exists.target = false", "target", False, "no target is no target"),
        ("dead.pet = true", "pet", True, "other units are read as they are"),
    ):
        lua.execute("exists, dead = {target = true, pet = true}, {}; " + setup)
        assert lua.eval(f"Exists('{unit}')") == expected, (why, lua.eval(f"Exists('{unit}')"))
    print("Dead target: read as no target in the queue; other units and unknowns unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
