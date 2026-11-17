# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Aura removals seen on UNIT_AURA end buff timers: RedundancyFilter records when a mapped aura
was removed (any rank), and counts how the removed-instance list read (plain or secret, in and
out of combat) for the session probe. Loads the real functions from RedundancyFilter.lua.

Run: python tools/test_aura_removals.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "RedundancyFilter.lua").read_text(encoding="utf-8")
    decl_start = source.index("RedundancyFilter._auraRemovedAt = {}")
    decl_end = source.index("\n", source.index("RedundancyFilter._removalReads = "))
    upd_start = source.index("function RedundancyFilter.OnUnitAuraUpdate(updateInfo)")
    upd_end = source.index("    -- Process added auras", upd_start)
    get_start = source.index("function RedundancyFilter.GetAuraRemovedAt(spellID)")
    get_end = source.index("\nend\n", get_start) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        RedundancyFilter, secret, now, combat = {}, {}, 100, true
        function GetTime() return now end
        function UnitAffectingCombat() return combat end
        BlizzardAPI = { Unsecret = function(v) if rawequal(v, secret) then return nil end return v end }
        instanceToSpellMap, instanceToNameMap, instanceToTimingMap = {}, {}, {}
        combatRemovedSpellIDs, inCombatActivations = {}, {}
        local chains = { [6673] = {6673, 5242}, [5242] = {6673, 5242} }
        function LibStub(name)
            if name == "JustAC-RotationImport" then return { RankChain = function(id) return chains[id] end } end
        end
    """ + source[decl_start:decl_end] + "\n" + source[upd_start:upd_end] + "\nend\n" + source[get_start:get_end])
    lua.execute("instanceToSpellMap[7] = 5242; RedundancyFilter.OnUnitAuraUpdate({removedAuraInstanceIDs = {7}})")
    assert lua.eval("RedundancyFilter.GetAuraRemovedAt(6673)") == 100, "a rank-2 removal answers for rank 1"
    assert lua.eval("RedundancyFilter.GetAuraRemovedAt(5242)") == 100
    assert lua.eval("instanceToSpellMap[7]") is None, "the instance leaves the map"
    lua.execute("now = 120; instanceToSpellMap[8] = 6673; RedundancyFilter.OnUnitAuraUpdate({removedAuraInstanceIDs = {8}})")
    assert lua.eval("RedundancyFilter.GetAuraRemovedAt(5242)") == 120, "the latest removal across ranks"
    lua.execute("now = 130; RedundancyFilter.OnUnitAuraUpdate({removedAuraInstanceIDs = {99}})")
    assert lua.eval("RedundancyFilter.GetAuraRemovedAt(6673)") == 120, "an unmapped instance names no spell"
    lua.execute("RedundancyFilter.OnUnitAuraUpdate({removedAuraInstanceIDs = secret})")
    lua.execute("combat = false; RedundancyFilter.OnUnitAuraUpdate({removedAuraInstanceIDs = {}})")
    lua.execute("RedundancyFilter.OnUnitAuraUpdate({})")
    reads = lua.eval("RedundancyFilter._removalReads")
    assert (reads.plain, reads.secret, reads.plainCombat, reads.secretCombat) == (4, 1, 3, 1), \
        ("removed-list reads: plain/secret, in combat", reads.plain, reads.secret, reads.plainCombat, reads.secretCombat)
    assert lua.eval("RedundancyFilter.GetAuraRemovedAt(1)") is None, "never removed: nil"
    print("Aura removals: mapped removals timestamped across ranks; list readability counted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
