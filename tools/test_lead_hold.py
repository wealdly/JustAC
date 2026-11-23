# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The first-slot hold (SpellQueue._StageLeadHold), checked outside the game: a challenger must
# last before it replaces the shown first slot, and the events that matter release it at once.
#
# Run: python tools/test_lead_hold.py

import sys
from pathlib import Path

from wow_stubs import LuaRuntime

SRC = Path(__file__).resolve().parent.parent / "SpellQueue.lua"

PRELUDE = """
SpellQueue = {}
lastSpellIDs, lastCtx = {}, {}
clock, gamePick, procced = 0, false, {}
function GetTime() return clock end
BlizzardAPI = {
    HasGamePick = function() return gamePick end,
    IsSpellProcced = function(id) return procced[id] == true end,
}
profile = { leadHoldSeconds = 0.2 }
function Build(at, ...)
    clock = at
    for i = #lastSpellIDs, 1, -1 do lastSpellIDs[i] = nil end
    for i, id in ipairs({...}) do lastSpellIDs[i] = id end
    SpellQueue._StageLeadHold({ profile = profile, inCombat = inCombat, now = at })
    return table.concat(lastSpellIDs, ",")
end
inCombat = true
"""


def main():
    text = SRC.read_text(encoding="utf-8")
    start = text.index("SpellQueue._leadHold = {}")
    end = text.index("--- Stage H - finalize", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(text[start:end])
    build = lua.globals().Build
    bad = []

    def check(got, want, why):
        if got != want:
            bad.append("%s: got %s, want %s" % (why, got, want))

    def reset(**settings):
        lua.execute("SpellQueue._leadHold = {}; procced = {}; gamePick = false; inCombat = true; "
                    "profile = { leadHoldSeconds = 0.2 }")
        for key, value in settings.items():
            lua.execute("%s = %s" % (key, value))

    # A flicker changes nothing: the shown entry keeps the first slot and the challenger follows.
    reset()
    check(build(1.00, 100, 200, 300), "100,200,300", "the first build sets the shown lead")
    check(build(1.03, 200, 100, 300), "100,200,300", "a challenger is held")
    check(lua.eval("lastCtx.leadHeld"), True, "a held build is marked")
    check(build(1.06, 100, 200, 300), "100,200,300", "the incumbent returning ends the hold")
    check(lua.eval("lastCtx.leadHeld"), None, "an unheld build is not marked")
    # A challenger that keeps winning takes the slot after the hold time, whoever it is by then.
    check(build(2.00, 200, 100, 300), "100,200,300", "held at first")
    check(build(2.10, 300, 100, 200), "100,300,200", "still held, another challenger")
    check(build(2.20, 300, 100, 200), "300,100,200", "released once the incumbent has lost for the hold time")
    check(build(2.23, 100, 300, 200), "300,100,200", "the new lead is the incumbent now")
    # What matters releases at once: the player's own cast, a proc, the shown entry leaving.
    reset()
    build(1.00, 100, 200)
    lua.execute("clock = 1.02; SpellQueue.NoteLeadEvent()")
    check(build(1.03, 200, 100), "200,100", "the player's own cast releases the change")
    check(build(1.60, 100, 200), "200,100", "an old event releases nothing")
    reset()
    build(1.00, 100, 200)
    lua.execute("procced[200] = true")
    check(build(1.03, 200, 100), "200,100", "a proc on the challenger releases")
    reset()
    build(1.00, 100, 200)
    check(build(1.03, 200, 300), "200,300", "the shown entry left the queue: nothing to hold")
    # Off: no setting, out of combat, or the first slot is the game's pick.
    for why, setting in (("no setting", {"profile": "{}"}), ("out of combat", {"inCombat": "false"}),
                         ("a game pick", {"gamePick": "true"}), ("zero seconds", {"profile": "{leadHoldSeconds=0}"})):
        reset(**setting)
        build(1.00, 100, 200)
        check(build(1.03, 200, 100), "200,100", "%s: no hold" % why)
    # A wait marker in the first slot is held like any other value.
    reset()
    build(1.00, 100, 200)
    check(build(1.03, -999999999, 100, 200), "100,-999999999,200", "a flicker to waiting is held")

    for line in bad:
        print("  FAIL", line)
    print("lead hold: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
