# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Context rank: archetype distance applies only where a game pick supplies the context.

Loads ContextRank from SpellQueue.lua. With a game pick (Retail) an ability that matches the
pick's pattern ranks ahead of one that does not. Without one (WoW Forever) the multi-target
context is only the enemy count, so every ability ranks the same and the list tier's own
order decides; the confirmed out-of-melee sink still applies on both.

Run: python tools/test_context_rank.py
"""
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
THUNDER_CLAP, MORTAL_STRIKE, FROSTBOLT, UNTAGGED = 6343, 12294, 116, 5019


def main():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("local ARCH_MISS = 4")
    body = source[start:source.index("\n--- Structurally unusable", start)]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        hasPick = true
        SpellQueue = {}
        LibStub = function() return nil end
        Enum = { PowerType = { Rage = 1, RunicPower = 6 } }
        BlizzardAPI = {
            FIGHT_ENDING_TARGET_PCT = 20,
            HasGamePick = function() return hasPick end,
            IsSecretValue = function() return false end,
        }
        local arch = { [6343] = "aoe", [12294] = "st", [116] = "st" }
        local range = { [6343] = "melee", [12294] = "melee", [116] = "ranged" }
        SpellDB = {
            GetArch = function(id) return arch[id] end,
            GetRange = function(id) return range[id] end,
            GetRole = function() return nil end,
            GetGate = function() return nil end,
        }
        function ResolveBurstTriggers() return nil end
        function IsBurstTrigger() return false end
    """ + body + """
        function Rank(id, ctxArch, outOfMelee)
            return ContextRank(id, ctxArch, nil, nil, false, outOfMelee, false)
        end
    """)
    rank = lua.globals().Rank
    count = 0

    def check(condition, why):
        nonlocal count
        assert condition, why
        count += 1

    lua.execute("hasPick = true")
    check(rank(THUNDER_CLAP, "aoe", False) < rank(MORTAL_STRIKE, "aoe", False),
          "Retail: a pack attack ranks ahead of a single-target attack in an AoE context")
    check(rank(UNTAGGED, "aoe", False) < rank(FROSTBOLT, "aoe", False),
          "Retail: an untagged ability ranks ahead of a mismatched one")

    lua.execute("hasPick = false")
    for context in ("cleave", "aoe"):
        ranks = {rank(sid, context, False) for sid in (THUNDER_CLAP, MORTAL_STRIKE, FROSTBOLT, UNTAGGED)}
        check(len(ranks) == 1, f"Forever {context}: every ability ranks the same, list order decides")
    check(rank(MORTAL_STRIKE, "aoe", True) > rank(FROSTBOLT, "aoe", True),
          "Forever: a melee attack still sinks on a confirmed out-of-melee read")
    check(rank(MORTAL_STRIKE, None, False) == rank(MORTAL_STRIKE, "aoe", False),
          "Forever: multi-target ranks as single target does")
    print(f"ok ({count} checks)")


if __name__ == "__main__":
    main()
