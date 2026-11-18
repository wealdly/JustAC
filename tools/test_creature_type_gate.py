# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Creature-type limits from spell data: a spell the data restricts to some creature types
(Forever Exorcism and Holy Wrath: Demons and Undead) is dropped from the queue when the
target's type is known and outside the mask; unknown type or an unrestricted spell keeps it.
Loads the real BlizzardAPI.IsSpellTypeValidForTarget and checks the generated Forever data.

Run: python tools/test_creature_type_gate.py
"""
import re
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
DEMON, UNDEAD, BEAST, HUMANOID = 3, 6, 1, 7


def main():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("local CC_TYPE_MASK = {")
    end = source.index("--- Called when the player successfully casts a real CC")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        bit = { band = function(a, b) return a & b end, lshift = function(a, n) return a << n end }
        targetType = nil
        BlizzardAPI = { GetTargetCreatureTypeID = function() return targetType end }
        local masks = { [879] = 36, [5614] = 36 }
        local db = { GetCreatureTypeMask = function(id) return masks[id] end }
        function LibStub(name) if name == "JustAC-SpellDB" then return db end end
    """ + source[start:end])
    valid = lua.eval("BlizzardAPI.IsSpellTypeValidForTarget")
    for target, spell, want, why in (
        (UNDEAD, 879, True, "Exorcism on Undead"),
        (DEMON, 5614, True, "a higher rank on a Demon"),
        (BEAST, 879, False, "Exorcism on a Beast: dropped"),
        (HUMANOID, 879, False, "Exorcism on a Humanoid: dropped"),
        (None, 879, True, "unknown type keeps it"),
        (BEAST, 35395, True, "an unrestricted spell is never dropped"),
        (BEAST, 20066, False, "the curated CC mask still applies (Repentance)"),
        (HUMANOID, 20066, True, "Repentance on a Humanoid"),
    ):
        lua.globals().targetType = target
        assert valid(spell) is want, (why, valid(spell))

    defaults = (ROOT / "Data" / "Forever" / "Defaults.lua").read_text(encoding="utf-8")
    block = re.search(r"^local CREATURE_TYPES = \{\n(.*?)^\}", defaults, re.M | re.S).group(1)
    masks = {int(a): int(b) for a, b in re.findall(r"\[(\d+)\] = (\d+)", block)}
    assert masks.get(879) == 36 and masks.get(10314) == 36, "Exorcism, every rank: Demons and Undead"
    assert masks.get(2812) == 36, "Holy Wrath"
    for pet_spell in (19574, 19577, 19028, 2641):
        assert pet_spell not in masks, (pet_spell, "a pet-targeted spell's mask describes the pet")
    assert "SpellDB.RegisterCreatureTypes(CREATURE_TYPES)" in defaults
    rotations = (ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8")
    ret = rotations[rotations.index("retribution"):]
    assert "-- Exorcism" in ret[:ret.index("\n    },")], "Retribution lists Exorcism"
    print("Creature-type gate: data masks drop wrong-type spells; unknown and unrestricted keep them")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
