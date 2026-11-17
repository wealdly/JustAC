# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Swing bars on queue icons, and slot 1 for a next-swing attack.

Loads the real swing block of RenderQueueIcon from UI/UIRenderer.lua: only a queued next-swing
attack (Heroic Strike pressed, waiting on the swing) shows the swing bar; leading but not
queued, it shows none. Then the real swing-press stage from SpellQueueForever.lua.

Run: python tools/test_lead_swing_bar.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "UI" / "UIRenderer.lua").read_text(encoding="utf-8")
    start = source.index("        local queuedSwing, swingStart, swingEnd, offStart, offEnd = false, nil, nil, nil, nil")
    end = source.index("        local visualState = ResolveVisualState(", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellDB = { NEXT_SWING_SPELLS = { [78] = true } }
        queued, window = nil, nil
        BlizzardAPI = {
            RunningAutoSwing = function(id) return queued end,
            GetSwingWindow = function(kind) if window then return window[1], window[2] end end,
        }
        function Swing(i, spellID, isItemEntry, currentTime)
            local isCastedSpell = false
    """ + source[start:end] + """
            return queuedSwing, isCastedSpell, swingStart, swingEnd
        end
    """)
    for setup, args, expected, why in (
        ("window={10,12}", (1, 78), (False, False, None, None), "leading, not queued: no bar"),
        ("window={10,12}", (2, 78), (False, False, None, None), "not leading: no bar"),
        ("window=nil", (1, 78), (False, False, None, None), "no swing running: no bar"),
        ("window={10,12}", (1, 772), (False, False, None, None), "not a next-swing attack: no bar"),
        ("window={10,12}; queued=0", (2, 78), (True, True, 10, 12), "queued anywhere: in progress, as before"),
    ):
        lua.execute("queued, window = nil, nil;" + setup)
        got = lua.eval("function(i, id) return {Swing(i, id, false, 11)} end")(*args)
        got = tuple(got[k] if k in got else None for k in range(1, 5))
        assert got == expected, (why, got, expected)
    print("Swing bar: only a queued next-swing attack shows its swing")
    check_swing_press()
    return 0


def check_swing_press():
    """A next-swing attack you can press now is not displaced from slot 1 by a lead still waiting
    (a cooldown or a cost due within one GCD). Loads the real stage from SpellQueueForever.lua."""
    source = (ROOT / "SpellQueueForever.lua").read_text(encoding="utf-8")
    start = source.index("--- Can this be pressed right now")
    end = source.index("-- Look-ahead: a spell that carries the player to the target", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellQueue, sunkSet = {}, {}
        SpellDB = { NEXT_SWING_SPELLS = { [78] = true, [845] = true } }
        ready, usable, short, range, queued, forever = {}, {}, {}, {}, {}, true
        BlizzardAPI = {
            IsForever = function() return forever end,
            IsSpellReady = function(id) return ready[id] ~= false end,
            IsSpellUsable = function(id) return usable[id] ~= false, short[id] == true end,
            AbilityInRange = function(id) return range[id] end,
            RunningAutoSwing = function(id) return queued[id] end,
        }
    """ + source[start:end])
    for setup, expected, why in (
        ("ready[12294]=false", [78, 12294, 772], "Mortal Strike's cooldown ends soon: Heroic Strike now"),
        ("short[12294]=true", [78, 12294, 772], "Mortal Strike affordable soon: Heroic Strike now"),
        ("", [12294, 78, 772], "a lead you can press keeps slot 1"),
        ("ready[12294]=false;short[78]=true", [12294, 78, 772], "Heroic Strike unaffordable: no move"),
        ("ready[12294]=false;range[78]=false", [12294, 78, 772], "Heroic Strike out of range: no move"),
        ("ready[12294]=false;queued[78]=0;sunkSet[78]=true", [78, 12294, 772],
         "already queued: in progress, it heads slot 1 over a lead still waiting"),
        ("queued[78]=0;sunkSet[78]=true", [12294, 78, 772], "a lead you can press keeps slot 1 over a queued one"),
        ("ready[12294]=false;sunkSet[78]=true", [12294, 78, 772], "a held Heroic Strike stays held"),
        ("ready[12294]=false;sunkSet[12294]=true", [78, 12294, 772], "a lead waiting in the sink yields too"),
        ("ready[12294]=false;sunkSet[12294]=true;sunkSet[78]=true;short[78]=true", [12294, 78, 772],
         "an unaffordable, unqueued Heroic Strike does not move"),
        ("ready[12294]=false;b.inCombat=false", [12294, 78, 772], "out of combat: the pull keeps its order"),
        ("ready[12294]=false;forever=false", [12294, 78, 772], "retail: no change"),
    ):
        lua.execute("""
            ready, usable, short, range, queued, forever, sunkSet = {}, {}, {}, {}, {}, true, {}
            b = { inCombat = true, recommendedSpells = {12294, 78, 772}, spellCount = 3 }
        """ + setup)
        lua.execute("SpellQueue._StageSwingPress(b)")
        got = [lua.eval("b.recommendedSpells")[k] for k in (1, 2, 3)]
        assert got == expected, (why, got, expected)
    print("Swing press: a pressable or queued next-swing attack leads over a lead still waiting")


if __name__ == "__main__":
    raise SystemExit(main())
