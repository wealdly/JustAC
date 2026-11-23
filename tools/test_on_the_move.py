# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""On the Move: while the player keeps moving in combat, pressable attacks castable on the move go
ahead of what needs standing still. A sidestep does not flip the queue, custom lists and Retail's
slot 1 keep their place. Loads the real SpellQueueMovement.lua.

Run: python tools/test_on_the_move.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
FROSTBOLT, FIRE_BLAST, ICE_LANCE, SHOOT, ARCANE_MISSILES = 116, 2136, 30455, 5019, 5143


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        function wipe(t) for k in pairs(t) do t[k] = nil end return t end
        secret, moving, hasPick, rangedSpec = {}, false, false, true
        castable = { [116] = false, [2136] = true, [30455] = true, [5019] = false, [5143] = false }
        unpressable = {}
        local libs = {}
        LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
            { __call = function(_, n) return libs[n] end })
        SQ = LibStub:NewLibrary("JustAC-SpellQueue")
        SQ._sunkSet, SQ._lastCtx = {}, {}
        SQ._PressableNow = function(id) return not unpressable[id] end
        local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
        B.IsSecretValue = function(v) return rawequal(v, secret) end
        B.HasGamePick = function() return hasPick end
        B.GetCachedSpellInfo = function() return {} end
        local DB = LibStub:NewLibrary("JustAC-SpellDB")
        DB.IsMoveCastableNow = function(id) return castable[id] end
        DB.IsRangedOrHealerSpec = function() return rangedSpec end
        function IsPlayerMoving() return moving end
        function Build(now, spells, fields)
            local b = { inCombat = true, now = now, profile = {}, contextOrder = "simc",
                        recommendedSpells = {}, spellCount = #spells }
            for i, id in ipairs(spells) do b.recommendedSpells[i] = id end
            for k, v in pairs(fields or {}) do b[k] = v end
            SQ._StageOnTheMove(b)
            return b.recommendedSpells
        end
    """)
    lua.execute((ROOT / "SpellQueueMovement.lua").read_text(encoding="utf-8"))
    g = lua.globals()
    base = [FROSTBOLT, ARCANE_MISSILES, FIRE_BLAST, ICE_LANCE]

    def build(now, spells=None, fields=None):
        table = lua.table_from(spells or base)
        extra = lua.table_from(fields) if fields else None
        return list(g.Build(now, table, extra).values())

    assert build(0) == base, "standing: the list's order"
    g.moving = True
    assert build(1) == base, "the first moment of movement changes nothing"
    assert build(1.2) == base, "a sidestep under the delay changes nothing"
    moved = [FIRE_BLAST, ICE_LANCE, FROSTBOLT, ARCANE_MISSILES]
    assert build(1.3) == moved, "moving on: instants first, each group in order"
    g.moving = False
    assert build(1.5) == moved, "a brief stop keeps the instants up"
    g.moving = True
    assert build(1.6) == moved, "weaving short moves stays on instants"
    g.moving = False
    assert build(2.0) == moved, "stopped, inside the return delay"
    assert build(2.41) == base, "stood still long enough: the list's order returns"

    g.moving = True
    build(10)
    assert build(11) == moved, "moving again"
    lua.execute("unpressable[2136] = true")
    assert build(11.1) == [ICE_LANCE, FROSTBOLT, ARCANE_MISSILES, FIRE_BLAST], "only what can be pressed now"
    lua.execute("unpressable = {}; SQ._sunkSet[2136] = true")
    assert build(11.2) == [ICE_LANCE, FROSTBOLT, ARCANE_MISSILES, FIRE_BLAST], "a sunk entry stays behind"
    lua.execute("SQ._sunkSet[2136] = nil")
    assert build(11.3, [FROSTBOLT, SHOOT]) == [FROSTBOLT, SHOOT], "nothing castable: the queue is unchanged"
    assert build(11.4, [FIRE_BLAST, FROSTBOLT]) == [FIRE_BLAST, FROSTBOLT], "already first"

    g.hasPick = True
    assert build(11.5) == [FROSTBOLT, FIRE_BLAST, ICE_LANCE, ARCANE_MISSILES], "slot 1 stays the game's pick"
    assert build(11.6, None, {"leadMode": "mylist"}) == moved, "unless the player's list leads"
    g.hasPick = False

    lua.execute("SQ._rotationIsCustom = true")
    assert build(12) == base, "a custom list keeps its order"
    lua.execute("SQ._rotationIsCustom = nil")
    build(20)
    assert build(21) == moved
    assert build(21.1, None, {"contextOrder": "off"}) == base, "reordering turned off"
    build(30)
    assert build(31) == moved
    assert build(31.1, None, {"inCombat": False}) == base, "out of combat nothing changes"

    enabled = lua.eval("SQ.OnTheMoveEnabled")
    assert enabled(lua.table_from({})) is True, "ranged and healers default on"
    g.rangedSpec = False
    assert enabled(lua.table_from({})) is False, "melee defaults off"
    assert enabled(lua.table_from({"promoteOnTheMove": True})) is True, "the player's choice wins"
    g.rangedSpec = True
    assert enabled(lua.table_from({"promoteOnTheMove": False})) is False, "either way"
    assert build(40, None, {"profile": lua.table_from({"promoteOnTheMove": False})}) == base, "turned off"

    lua.execute("moving = secret")
    build(50)
    assert build(51) == base, "an unreadable movement read counts as standing"
    print("On the Move: instants lead while moving, debounced; custom lists and the game's pick keep their place")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
