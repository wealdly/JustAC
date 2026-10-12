# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Forever primary-pick handling: out-of-range Attack yields to the next pick.
#
# Run: python tools/test_forever_primary.py
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "SpellQueue.lua"

PRELUDE = r"""
SpellQueue = {
    LeadMode = function() return "game" end,
    IsCasterSuppressedPick = function() return false end,
    IsSpellBlacklisted = function() return false end,
}
AUTO_ATTACK_SPELL = 6603
BlizzardAPI = {
    IsForever = function() return forever end,
    SpellInRange = function() return meleeInRange end,
    GetDisplaySpellID = function(id) return id end,
    GetHighlightCastSpell = function() return nextPick end,
}
forever, meleeInRange, nextPick = true, false, 403
function ClaimSpellID(id, added)
    if added[id] then return nil end
    added[id] = true
    return id
end
function NotePick() end
"""


def main():
    source = SRC.read_text(encoding="utf-8")
    start = source.index("function SpellQueue._StagePrimary(b)")
    end = source.index("\nfunction SpellQueue.GetCurrentSpellQueue()", start)
    lua = LuaRuntime()
    compiled, error = lua.eval(
        "function(src) local chunk, err = load(src); return chunk ~= nil, err end"
    )(source)
    if not compiled:
        raise SyntaxError(error)
    lua.execute(PRELUDE)
    lua.execute(source[start:end])
    run = lua.eval(
        """function(isForever, inRange, lookahead)
            forever, meleeInRange, nextPick = isForever, inRange, lookahead
            local b = {
                profile = {},
                primarySpellID = 6603,
                blacklist = {},
                addedSpellIDs = {},
                recommendedSpells = {},
                spellCount = 0,
            }
            SpellQueue._StagePrimary(b)
            return b.recommendedSpells[1]
        end"""
    )

    cases = [
        (True, False, 403, 403, "Forever out-of-range Attack yields to Lightning Bolt"),
        (True, True, 403, 6603, "Forever Attack stays in melee"),
        (True, None, 403, 6603, "unknown range preserves Forever Attack"),
        (False, False, 403, 6603, "Retail behavior stays unchanged"),
    ]
    failures = []
    for forever, in_range, lookahead, expected, message in cases:
        actual = run(forever, in_range, lookahead)
        if actual != expected:
            failures.append(f"{message}: got {actual!r}, wanted {expected!r}")

    for failure in failures:
        print("FAIL", failure)
    if failures:
        return 1
    print(f"Forever primary pick: {len(cases)} cases passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
