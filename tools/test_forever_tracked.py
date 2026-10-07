# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# MaintenanceTracker.IsTrackedAuraActive against a stubbed Cooldown Manager: WoW Forever lets a
# spell's cooldown entry sit in Tracked Buffs beside its aura entry (measured: Rend's Essential
# entry 199859 next to its aura entry 199656), and only the AURA entry may answer "is it up".
#
# Run: python tools/test_forever_tracked.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
LibStub:NewLibrary("JustAC-SpellDB")
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.IsSecretValue = function() return false end
B.Unsecret = function(v) return v end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
now = 0
function GetTime() return now end
function UnitAffectingCombat() return true end
function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:RegisterUnitEvent() end
    function f:SetScript() end
    function f:HookScript() end
    return f
end
hooksecurefunc = function() end
Enum = { CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3,
                                    GroupBuff = 4, HiddenActive = -1, HiddenPassive = -2 } }
-- Rend: its cooldown entry 199859 (default Essential) and its aura entry 199656 (default TrackedBuff).
sets = { [0] = { 199859 }, [2] = { 199656 } }
C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(c) return sets[c] or {} end,
    GetCooldownViewerCooldownInfo = function() return { spellID = 772 } end,
}
items = {}
local function item(cid, active) return { GetCooldownID = function() return cid end, isActive = active } end
function SetItems(spellActive, auraActive)
    items = { item(199859, spellActive), item(199656, auraActive) }
end
viewerShown = true
BuffIconCooldownViewer = {
    IsShown = function() return viewerShown end,
    itemFramePool = { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return items[i] end
    end },
}
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "MaintenanceTracker.lua").read_text(encoding="utf-8"))
    MT = lua.eval('LibStub("JustAC-MaintenanceTracker")')
    g = lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    lua.execute("SetItems(true, false)")
    check(MT.IsTrackedAuraActive(772) is False, "spell entry 'active' must not read as the debuff being up")
    lua.execute("SetItems(true, true)")
    check(MT.IsTrackedAuraActive(772) is True, "aura entry active: up")
    lua.execute("SetItems(false, false)")
    check(MT.IsTrackedAuraActive(772) is False, "aura entry inactive: down")
    g.viewerShown = False
    check(MT.IsTrackedAuraActive(772) is None, "hidden viewer: no answer (its data is frozen)")

    for why in bad:
        print("  FAIL", why)
    print("forever tracked: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
