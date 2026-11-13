# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Proc overlay API failures degrade safely and remain diagnosable.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


PRELUDE = r"""
local libs = {}
LibStub = setmetatable({NewLibrary=function(_, name)
    libs[name] = libs[name] or {}; return libs[name]
end}, {__call=function(_, name) return libs[name] end})
B = LibStub:NewLibrary("JustAC-BlizzardAPI")
secret = {}
B.IsSecretValue = function(value) return value == secret end
overlays, overlayErrors, overrides = {}, {}, {}
now, reports = 0, {}
function GetTime() return now end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function geterrorhandler()
    return function(message) reports[#reports + 1] = message end
end
C_SpellActivationOverlay = {
    IsSpellOverlayed=function(id)
        if overlayErrors[id] then error(overlayErrors[id]) end
        return overlays[id]
    end,
}
C_Spell = {
    GetOverrideSpell=function(id) return overrides[id] or id end,
    IsSpellPassive=function() return false end,
}
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "BlizzardAPI" / "SpellQuery.lua").read_text(encoding="utf-8"))
    lua.execute("""
        overlays[10] = true
        assert(B.IsSpellProcced(10), "a confirmed overlay remains a proc")
        overlayErrors[11] = "overlay denied"
        B.ClearProcCache()
        assert(not B.IsSpellProcced(11), "overlay errors fail closed")
        assert(#reports == 1 and string.find(reports[1], "overlay denied"))
        assert(not B.IsSpellProcced(11) and #reports == 1, "errors are reported once per spell")
        overlays[12], overrides[12], overlays[13] = false, 13, true
        B.ClearProcCache()
        assert(B.IsSpellProcced(12), "the resolved override overlay is checked")
        overrides[14], overlayErrors[15] = 15, "override denied"
        B.ClearProcCache()
        assert(not B.IsSpellProcced(14), "override query errors fail closed")
        assert(#reports == 2 and string.find(reports[2], "override denied"))
        overlays[16] = secret
        B.ClearProcCache()
        assert(not B.IsSpellProcced(16), "secret overlay results remain unknown")
    """)

    secret_values = (ROOT / "BlizzardAPI" / "SecretValues.lua").read_text(encoding="utf-8")
    start = secret_values.index("local function TestProcAccess()")
    end = secret_values.index("\nend", start) + len("\nend")
    probe = secret_values[start:end].replace("local function TestProcAccess()", "function TestProcAccess()", 1)
    lua.execute("""
        local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay.IsSpellOverlayed
        local IsSecretValue = B.IsSecretValue
        local pcall, tostring, geterrorhandler = pcall, tostring, geterrorhandler
        local C_AssistedCombat = {GetRotationSpells=function() return {20} end}
        local procProbeErrorReported = false
    """ + probe + """
        overlayErrors[20] = "probe denied"
        assert(not TestProcAccess(), "probe errors report unavailable")
        assert(#reports == 3 and string.find(reports[3], "probe denied"))
        assert(not TestProcAccess() and #reports == 3, "probe failures are reported once")
        overlayErrors[20] = nil
        overlays[20] = secret
        assert(not TestProcAccess(), "secret probe results report unavailable")
    """)
    print("Proc overlays: base/override signals, secret values, fail-closed errors and diagnostics passed")


if __name__ == "__main__":
    main()
