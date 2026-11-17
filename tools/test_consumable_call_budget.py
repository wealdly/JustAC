# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Call budget for the consumable ownership scan and the per-icon GCD query.
#
# Run: python tools/test_consumable_call_budget.py

from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def block(path: Path, start: str, end: str) -> str:
    source = path.read_text(encoding="utf-8")
    i = source.index(start)
    return source[i:source.index(end, i)]


OWNERSHIP = block(ROOT / "SpellDB.lua", "local OWNED_ITEM_MAX_AGE", "\n-- Caster specs")
GCD_GATE = block(ROOT / "BlizzardAPI" / "CooldownTracking.lua",
                 "local gcdRunningAt, gcdRunning", "\nend\n") + "\nend\n"
GCD_REFERENCE = block(ROOT / "BlizzardAPI" / "CooldownTracking.lua",
                      "local GCD_REFERENCE_CANDIDATES", "\nend\n") + "\nend\n"


def test_ownership_memo():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        now = 100
        function GetTime() return now end
        function wipe(t) for k in pairs(t) do t[k] = nil end return t end
        counts = { [1] = 2, [2] = 0 }
        calls = { count = 0, usable = 0 }
        C_Item = {
            GetItemCount = function(id) calls.count = calls.count + 1; return counts[id] or 0 end,
            IsUsableItem = function(id) calls.usable = calls.usable + 1; return true end,
        }
        SpellDB = {}
        PlayerHasToy, IsPlayerSpell = nil, nil
    """)
    lua.execute(OWNERSHIP + "\nOwns = OwnsBuffEntry")
    owns = lua.globals().Owns
    e1, e2 = lua.table_from({"id": 1}), lua.table_from({"id": 2})
    for _ in range(10):
        assert owns(e1) is True
        assert owns(e2) is False
    calls = lua.globals().calls
    assert calls.count == 2, calls.count          # one count read per item, then memo
    assert calls.usable == 10, calls.usable       # usability stays live, owned items only
    lua.execute("counts[2] = 1")
    assert owns(e2) is False                      # still memoized until the bags change
    lua.execute("SpellDB.MarkConsumableBagsDirty()")
    assert owns(e2) is True                       # BAG_UPDATE_DELAYED invalidates
    lua.execute("counts[1] = 0; now = now + 31")
    assert owns(e1) is False                      # age backstop for a missed event


def gcd_runtime(reference, present, durations):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        now = 100
        function GetTime() return now end
        calls = { duration = 0, ids = {} }
        BlizzardAPI = {}
        local function DurationObjectActive(d) return d ~= nil and d.active == true end
        _G.DurationObjectActive = DurationObjectActive
    """)
    lua.globals().reference = reference
    lua.globals().present = lua.table_from(present)
    lua.globals().durs = lua.table_from(durations)
    lua.execute("""
        function BlizzardAPI.GetGCDReferenceSpell() return reference end
        C_Spell = {
            DoesSpellExist = function(id) return present[id] == true end,
            GetSpellCooldownDuration = function(id)
                calls.duration = calls.duration + 1
                calls.ids[#calls.ids + 1] = id
                return durs[calls.duration]
            end,
        }
    """)
    lua.execute(GCD_GATE)
    return lua


def test_gcd_reference_by_client():
    # The first candidate the spell data has wins: retail keeps 61304 although it also has
    # 1283885; Forever has only 1283885; neither means unknown. Resolved once.
    for present, expected in (({61304: True, 1283885: True}, 61304), ({1283885: True}, 1283885),
                              ({}, None)):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().present = lua.table_from(present)
        lua.execute("""
            BlizzardAPI = {}
            existsCalls = 0
            C_Spell = {DoesSpellExist = function(id) existsCalls = existsCalls + 1; return present[id] == true end}
        """)
        lua.execute(GCD_REFERENCE)
        ref = lua.globals().BlizzardAPI.GetGCDReferenceSpell
        assert ref() == expected and ref() == expected, (present, ref())
        calls = lua.globals().existsCalls
        lua.execute("BlizzardAPI.GetGCDReferenceSpell()")
        assert lua.globals().existsCalls == calls        # static data: never asked again


def test_gcd_gate_retail():
    lua = gcd_runtime(61304, {61304: True}, [None, {"active": True}])
    gate = lua.globals().BlizzardAPI.IsGlobalCooldownRunning
    assert gate() is False                        # reference present, no duration -> idle
    assert gate() is False                        # same frame: memoized
    assert lua.globals().calls.duration == 1
    lua.execute("now = now + 0.016")
    assert gate() is True
    assert lua.globals().calls.ids[1] == 61304


def test_gcd_gate_forever_reference():
    # Forever has no 61304; its reference 1283885 answers instead of unknown.
    lua = gcd_runtime(1283885, {1283885: True}, [{"active": True}, None])
    gate = lua.globals().BlizzardAPI.IsGlobalCooldownRunning
    assert gate() is True
    lua.execute("now = now + 0.016")
    assert gate() is False
    assert lua.globals().calls.ids[1] == 1283885 and lua.globals().calls.ids[2] == 1283885


def test_gcd_gate_unknown_without_reference():
    lua = gcd_runtime(None, {}, [])
    gate = lua.globals().BlizzardAPI.IsGlobalCooldownRunning
    assert gate() is None                         # no reference: unknown, callers ask the spell
    assert lua.globals().calls.duration == 0


if __name__ == "__main__":
    test_ownership_memo()
    test_gcd_reference_by_client()
    test_gcd_gate_retail()
    test_gcd_gate_forever_reference()
    test_gcd_gate_unknown_without_reference()
    print("consumable call budget: ok")
