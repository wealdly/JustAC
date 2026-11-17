# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Buff time left from plain evidence, in order of reliability (BlizzardAPI.GetBuffWindowRemaining).

The expiry the spell's aura showed while it read plain, then the last complete out-of-combat
aura scan (RedundancyFilter), then our own cast plus the data's duration. A reading taken
before our latest cast yields to the cast. Loads the real functions from the source.

Run: python tools/test_buff_window.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    decl_start = source.index("local ownCastAt = {}")
    decl_end = source.index("\n", source.index("local maintenanceTracker"))
    fn_start = source.index("--- Seconds left on a self-buff window")
    fn_end = source.index("\nend\n", source.index("function BlizzardAPI.GetBuffWindowRemaining(")) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        now = 100
        function GetTime() return now end
        BlizzardAPI = {}
        snapshot, takenAt = {}, 50
        removedAt = nil
        local RF = { GetTrustedAuraExpiry = function(id)
            if snapshot[id] then return snapshot[id], takenAt end
        end, GetAuraRemovedAt = function(id) return removedAt end }
        local RI = { RankChain = function(id) if id == 6673 then return {6673, 5242} end end }
        function LibStub(name)
            if name == "JustAC-RedundancyFilter" then return RF end
            if name == "JustAC-RotationImport" then return RI end
        end
    """ + source[decl_start:decl_end] + "\n" + source[fn_start:fn_end] + """
        function Seed(untilAt, readAt, castAt)
            auraUntil[6673], auraUntilReadAt[6673], ownCastAt[6673] = untilAt, readAt, castAt
        end
        function Left() return BlizzardAPI.GetBuffWindowRemaining(6673, 120) end
    """)
    for setup, expected, why in (
        ("Seed(nil, nil, nil)", None, "nothing known"),
        ("Seed(nil, nil, 90)", 110, "cast estimate only: 120s book duration from a cast 10s ago"),
        ("Seed(nil, nil, 40); snapshot[5242]=250", 150,
         "the snapshot (any rank) beats an estimate from a cast before it"),
        ("Seed(nil, nil, 60); snapshot[6673]=170", 80, "recast after the snapshot: the cast wins"),
        ("Seed(260, 70, 60); snapshot[6673]=170", 160, "the plain aura reading beats the snapshot"),
        ("Seed(260, 70, 80)", 100, "recast after the aura reading: the cast wins"),
        ("Seed(90, 70, nil); snapshot[6673]=170", 70, "a reading already past falls to the snapshot"),
        ("Seed(nil, nil, -50)", None, "an expired cast estimate is nothing"),
        # The real length a plain read showed (a talent, a higher rank) times the next cast.
        ("Seed(nil, nil, 90); learned[6673]=180", 170, "learned 180s, cast 10s ago"),
        ("Seed(nil, nil, -50); learned[6673]=180", 30, "still running on the learned length"),
        ("Seed(nil, nil, 90); learned[5242]=180", 110, "another spell's length is not borrowed"),
        # A removal seen after the source (cancelled, dispelled, expired early) ends it.
        ("Seed(nil, nil, 90); removedAt = 95", None, "removed after the cast: no window"),
        ("Seed(nil, nil, 90); removedAt = 90.3", 110, "a removal right after the cast is the refresh"),
        ("Seed(nil, nil, 90); removedAt = 80", 110, "removed before the cast: the new cast stands"),
        ("Seed(260, 70, nil); removedAt = 75", None, "removed after the reading: the reading is void"),
        ("Seed(nil, nil, 40); snapshot[5242]=250; removedAt = 60", None,
         "removed after the snapshot and the cast: nothing left"),
    ):
        lua.execute("snapshot={}; removedAt=nil; learned = BlizzardAPI._learnedBuffDuration; for k in pairs(learned) do learned[k] = nil end; " + setup)
        actual = lua.eval("Left()")
        assert actual == expected, (why, actual, expected)
    print("Buff window: aura reading, then out-of-combat snapshot, then cast estimate on the learned or book length")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
