# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The list registry's read / edit contract, checked outside the game.
#
# Two of the lists read through to shipped defaults while the player has none of their
# own. Editing what `resolve` returned would edit those defaults in place - for every
# character, until a reload - and it would look fine in game, because the edit is exactly
# what the player asked for. Everything that writes must go through `ensure`, which copies
# first. These cases pin that down, plus the Add path that must NOT copy on a cancel.
#
# Run: python tools/test_spell_lists.py

import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "Options" / "SpellLists.lua"

PRELUDE = """
local libs = {}
LibStub = setmetatable({
    NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end,
    GetLibrary = function(_, name, silent)
        if not libs[name] and not silent then error("missing library " .. tostring(name)) end
        return libs[name]
    end,
}, { __call = function(self, name, silent) return self:GetLibrary(name, silent) end })

POTION = -9000000
GAP_DEFAULTS = { 100, 101 }
DEF_DEFAULTS = { 200, 201 }
EFFECTIVE_BURST = { 300, 301 }
potionRemoved, popup = false, nil

libs["AceLocale-3.0"] = { GetLocale = function()
    return setmetatable({}, { __index = function(_, k) return k end })
end }
libs["JustAC-ListWidget"] = {}
libs["JustAC-OptionsWidgets"] = { spellDesc = function(key) return function() return key end end }
libs["JustAC-SpellDB"] = {
    EMERGENCY_POTION = POTION,
    GetSpecKey = function() return "SPEC", "CLASS" end,
    CLASS_GAPCLOSER_DEFAULTS = { SPEC = GAP_DEFAULTS },
    CLASS_DEFENSIVE_DEFAULTS = { SPEC = DEF_DEFAULTS },
    ResolveDefaults = function(t, spec) return t[spec] end,
}
libs["JustAC-DefensiveEngine"] = {
    GetClassSpellList = function(a, field)
        local cs = a:GetProfile().defensives.classSpells
        return cs and cs.SPEC and cs.SPEC[field]
    end,
    DefaultsKeyForList = function() return "CLASS_DEFENSIVE_DEFAULTS" end,
    MarkEmergencyPotionRemoved = function() potionRemoved = true end,
    RegisterDefensivesForTracking = function() end,
}
libs["JustAC-SpellQueue"] = {
    GetBurstTriggerInfo = function() return EFFECTIVE_BURST, "simc" end,
    InvalidateBurstTriggers = function() end,
}
libs["JustAC-LiveSearchPopup"] = { Open = function(opts) popup = opts end }
libs["JustAC-OptionsSpellSearch"] = {
    BuildSpellbookCache = function() end,
    AddSpellToList = function(_, list, id)
        for _, v in ipairs(list) do if v == id then return false end end
        list[#list + 1] = id
        return true
    end,
}
function UnitClass() return "Class", "CLASS" end

profile = { defensives = {} }
addon = {
    GetProfile = function() return profile end,
    ForceUpdate = function() end,
    ForceUpdateAll = function() end,
}
function csv(t)
    local out = {}
    for i, v in ipairs(t or {}) do out[i] = tostring(v) end
    return table.concat(out, ",")
end
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(SRC.read_text(encoding="utf-8").replace("\r\n", "\n"))
    lua.execute('SL = LibStub("JustAC-OptionsSpellLists")')
    run = lua.eval("function(src) return assert(load(src))() end")
    bad = []

    def check(want, got, why):
        if want != got:
            bad.append("  FAIL %-52s got %r, want %r" % (why, got, want))

    # Gap-closers: nothing stored, so the defaults are what is shown.
    check("100,101", run('return csv(SL.Get("gap").resolve(addon))'), "gap: an empty list reads the defaults")
    check(True, run('return SL.Remove(addon, SL.Get("gap"), 100)'), "gap: removing a default entry works")
    check("100,101", run("return csv(GAP_DEFAULTS)"), "gap: ...without touching the defaults")
    check("101", run('return csv(profile.gapClosers.classSpells.SPEC)'), "gap: ...by editing a copy")
    check(False, run('return SL.Remove(addon, SL.Get("gap"), 999)'), "gap: removing an absent entry is a no-op")

    # Burst: Add opened and cancelled must leave the automatic list in charge.
    run('SL.AddButton(addon, "burst", 1).func()')
    check(None, run("return profile.burstTriggers"), "burst: a cancelled Add copies nothing")
    run("popup.onSelect(302)")
    check("300,301,302", run('return csv(profile.burstTriggers.SPEC)'), "burst: a pick refines the list shown")
    check("300,301", run("return csv(EFFECTIVE_BURST)"), "burst: ...without touching the queue's copy")
    run('SL.Get("burst").restore.func(addon)')
    check(None, run("return profile.burstTriggers.SPEC"), "burst: Use Defaults drops your own list")

    # Defensive: a spec with no list yet is seeded on the first edit, and the potion
    # entry's removal is recorded as deliberate.
    check(None, run('return SL.Get("defensive").resolve(addon)'), "defensive: no list before the first edit")
    run('popup = nil; SL.AddButton(addon, "defensive", 1).func(); popup.onSelect(POTION)')
    check("200,201,%d" % -9000000, run('return csv(SL.Get("defensive").resolve(addon))'),
          "defensive: the first edit seeds from defaults")
    check("200,201", run("return csv(DEF_DEFAULTS)"), "defensive: ...without touching the defaults")
    run('SL.Remove(addon, SL.Get("defensive"), POTION)')
    check(True, run("return potionRemoved"), "defensive: removing the potion is remembered")

    # Your own offensive list: kept while unused, and the Abilities tab told why.
    run('profile.customQueue = { SPEC = { enabled = false, spells = { 7 } } }')
    check("7", run('return csv(SL.Get("custom").resolve(addon))'), "custom: an unused list still reads")
    check("Custom Priority Disabled", run('return SL.Get("custom").inactive(addon)'),
          "custom: ...and says it is not in use")
    run("profile.customQueue.SPEC.enabled = true")
    check(None, run('return SL.Get("custom").inactive(addon)'), "custom: in use says nothing")

    for line in bad:
        print(line)
    total = 17
    print("spell lists: %d case(s), %d failure(s)" % (total, len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
