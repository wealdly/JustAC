# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Rank-aware stack lookups against the real StateHelpers module.
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
PRELUDE = """
local libs = {}
LibStub = setmetatable({NewLibrary = function(_, n)
    libs[n] = libs[n] or {}; return libs[n]
end}, {__call = function(_, n) return libs[n] end})
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.IsSecretValue = function(v) return v == secret end
B.AreAurasSecret = function() return restricted end
local RI = LibStub:NewLibrary("JustAC-RotationImport")
RI.RankChain = function(id)
    if id == 1328617 or id == 1235827 then return {1328617, 1235827} end
end
C_Item, C_Spell = {}, {}
function GetTime() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function CreateFrame() return {
    RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function() end
} end
secret = {}
restricted, denied, stacks = false, false, 5
auras = { [1235827] = {auraInstanceID = 77} }
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        if denied then error("aura access denied") end
        if not restricted then return auras[id] end
    end,
    GetUnitAuraBySpellID = function(_, id)
        if denied then error("aura access denied") end
        if not restricted then return auras[id] end
    end,
    GetAuraApplicationDisplayCount = function(_, _, threshold)
        if denied then error("aura access denied") end
        if stacks >= threshold then return tostring(stacks) end
        return ""
    end,
}
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8"))
    B, g = lua.eval('LibStub("JustAC-BlizzardAPI")'), lua.globals()
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    check(B.GetAuraStackAtLeast("target", 1328617, 5) is True, "base ID finds higher-rank stacks")
    check(B.GetAuraStackAtLeast("player", 1328617, 5) is True, "player lookup resolves ranks too")
    g.stacks = 4
    check(B.GetAuraStackAtLeast("target", 1235827, 5) is False, "empty count string is below threshold")
    lua.execute("C_UnitAuras.GetUnitAuraBySpellID = function(_, id) return auras[id] end")
    g.restricted = True
    check(B.GetAuraStackAtLeast("target", 1328617, 5) is False,
          "a readable exempt aura can answer false despite global restrictions")
    lua.execute("""
        C_UnitAuras.GetUnitAuraBySpellID = function(_, id)
            if denied then error("aura access denied") end
            if not restricted then return auras[id] end
        end
    """)
    g.restricted = False
    g.auras = lua.eval("{}")
    check(B.GetAuraStackAtLeast("target", 1328617, 5) is False, "readable absence means zero")
    g.restricted = True
    check(B.GetAuraStackAtLeast("target", 1328617, 5) is None, "hidden aura is unknown, not zero")
    g.denied = True
    check(B.GetAuraStackAtLeast("target", 1328617, 5) is None, "denied lookup is unknown")
    check(B.AuraStacksAtLeast("target", 77, 5) is None, "denied count read is unknown")
    g.denied = False
    g.restricted = False
    g.auras = lua.eval("{[1235827] = {auraInstanceID = secret}}")
    check(B.GetAuraStackAtLeast("target", 1328617, 5) is None, "secret instance is not branched on")
    check(B.GetAuraStackAtLeast("target", 1328617, 0) is True, "zero threshold always holds")
    for why in bad:
        print("  FAIL", why)
    print("forever stacks: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
