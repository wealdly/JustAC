# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The engaged-enemy count keeps a pack's count briefly when its nameplates vanish.

Loads the real count section of BlizzardAPI/StateHelpers.lua with stubbed unit reads: a
count that falls by two or more in one scan while the player is still in combat is held for
four seconds; fresh counts are reacquired on the next quarter-second scan. A rise, a fall
of one, leaving combat, an expired hold and the diagnostic breakdown are all taken as
scanned. Runs on both clients.

Run: python tools/test_enemy_count_hold.py
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
START = SOURCE.index("local UnitThreatSituation = _G.UnitThreatSituation")
END = SOURCE.index("-- Important casts nearby")
BLOCK = SOURCE[START:SOURCE.rindex("\n----", START, END)]
LEFT_COMBAT = SOURCE[SOURCE.index("local combatEndedAt ="):
                     SOURCE.index("function BlizzardAPI.IsInPostCombatDowntime")]

STUBS = """
    secret = {}
    now, plates, inCombat = 0, 0, true
    BlizzardAPI = { IsForever = function() return forever end, GetAddon = function() return nil end }
    function IsSecretValue(v) return rawequal(v, secret) end
    function GetTime() return now end
    function UnitExists(u)
        local i = tonumber(u:match("^nameplate(%d+)$"))
        return i ~= nil and i <= plates
    end
    function UnitCanAttack() return true end
    function UnitThreatSituation(_, u) return 3 end
    function UnitAffectingCombat(u) if u == "player" then return inCombat end return true end
    function UnitIsUnit() return false end
    function UnitIsTapDenied() return false end
"""


def check_client(forever):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS + "local IsSecretValue, UnitExists, UnitCanAttack, UnitIsUnit, UnitIsTapDenied, GetTime = "
                        "IsSecretValue, UnitExists, UnitCanAttack, UnitIsUnit, UnitIsTapDenied, GetTime\n"
                + BLOCK + LEFT_COMBAT)
    g = lua.globals()
    g.forever = forever
    count = lua.eval("function() return BlizzardAPI.GetEngagedEnemyCount() end")
    raw = lua.eval("function() local t = {} BlizzardAPI.GetEngagedEnemyCount(t) return t.threat end")

    def at(time, visible, combat=True):
        g.now, g.plates, g.inCombat = time, visible, combat
        return count()

    assert at(1, 4) == 4, "a pack is counted"
    assert at(2, 0) == 4, "plates gone, still in combat: the pack is kept"
    assert raw() == 0, "the diagnostic breakdown reports the scan, not the hold"
    assert at(5, 0) == 4, "kept through four seconds from the last pack reading"
    assert at(5.25, 0) == 0, "the hold ends on the next scan after four seconds"
    assert at(6, 4) == 4 and at(7, 0) == 4, "another missing pack starts a hold"
    assert at(7.125, 3) == 4, "the normal quarter-second scan cache still applies"
    assert at(7.25, 3) == 3, "a reacquired pack replaces the hold within a quarter second"
    assert at(11.25, 0) == 3, "reacquisition renews the hold from the fresh pack reading"
    assert at(11.5, 0) == 0, "cached held counts never renew the hold"
    assert at(12, 3) == 3 and at(13, 2) == 2 and at(13.5, 1) == 1, "enemies dying one at a time are real readings"
    assert at(14, 0) == 0, "and so is the last of them"
    assert at(14.5, 2) == 2 and at(14.75, 5) == 5, "a rise is taken at once, however large"
    assert at(15.5, 1) == 5, "five to one in a single scan is suspect: the pack is kept"
    assert at(15.75, 4) == 4, "a fall of one from the kept count is real"
    assert at(16.5, 2) == 4 and at(19.75, 2) == 4, "a fall of two is kept for four seconds"
    assert at(20.0, 2) == 2, "and accepted once the lower count has lasted"
    at(20.5, 0, combat=False)
    assert at(25, 3) == 3 and at(26, 0, combat=False) == 0, "leaving combat ends the hold"
    assert at(27, 0) == 0, "and it does not come back"
    assert at(28, 2) == 2 and at(29, 0, combat=g.secret) == 0, "an unreadable combat state holds nothing"
    assert at(30, 4) == 4 and at(31, 0) == 4, "a pack is held before combat ends"
    g.now, g.inCombat = 31.125, False
    g.BlizzardAPI.NotePlayerLeftCombat()
    assert at(31.125, 0) == 0, "combat-end notification clears the cache even on rapid reengagement"
    assert at(31.5, 0) == 0, "the previous fight's held pack cannot return"


def main():
    for forever in (False, True):
        check_client(forever)
    print("enemy count hold: both clients passed four-second expiry, quarter-second "
          "reacquisition, renewal, steps of one, sudden drops, rises, combat end, unknown and diagnostics")


if __name__ == "__main__":
    main()
