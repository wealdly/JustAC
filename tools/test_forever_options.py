# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The Forever grey-out pass (Options/Core.lua ApplyForeverUnused), run outside the game
# against a stand-in options table: listed options are disabled with the note appended
# once (string or function desc), a second pass changes nothing, and with a game pick
# (retail) nothing is touched. Whether each listed PATH still exists in the real table is
# the in-game half: debug mode prints any path that stopped resolving.
#
# Run: python tools/test_forever_options.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "Options" / "Core.lua"
NOTE = "|cffff6600Not used in WoW Forever|r"

def check_preparation_layout():
    source = (SRC.parent / "Defensives.lua").read_text(encoding="utf-8")
    helpers = source[:source.index("--- The current spec's maintenance entry")]
    start = source.index("            precombat = {")
    end = source.index("\n            },\n        },\n    }\n    -- One reset", start)
    block = source[start:end] + "\n            }"
    block = block.replace("precombat = {", "local result = {", 1)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        local libs = {}
        local L = setmetatable({}, {__index=function(_, key) return key end})
        LibStub = setmetatable({
            NewLibrary=function(_, name) libs[name]={}; return libs[name] end
        }, {__call=function(_, name) return libs[name] end})
        libs["AceLocale-3.0"]={GetLocale=function() return L end}
        libs["JustAC-SpellDB"]={IsForever=function() return forever end}
        libs["JustAC-PrecombatEngine"]={
            ClearCache=function() clears=clears+1 end,
            STEALTH_REMINDER={ROGUE={}},
        }
        addon={db={profile={
            defensives={enabled=true},
            precombatBuffs={enabled=true,topoffHeal=true,topoffThreshold=70,
                recoveryManaThreshold=60,categories={food="haste",recovery=false}},
        }}, ForceUpdateAll=function() updates=updates+1 end}
        clears,updates=0,0
        function UnitClass() return "Rogue","ROGUE" end
        C_SpecializationInfo={GetSpecialization=function() return 1 end}
    """)
    engine = (SRC.parent.parent / "PrecombatEngine.lua").read_text(encoding="utf-8")
    recovery = engine[engine.index("function PrecombatEngine.IsRecoveryEnabled("):]
    recovery = recovery[:recovery.index("\nfunction PrecombatEngine.AddRecoveryItems")]
    lua.execute('PrecombatEngine=LibStub("JustAC-PrecombatEngine")\n' + recovery)
    build = lua.execute(helpers + "\nreturn function(forever)\n" + block + "\nreturn result\nend")
    for forever in (True, False):
        lua.globals().forever = forever
        tab = build(forever)
        a = tab.args
        assert tab.name == "Preparation"
        assert a.pbEnabled.order < a.recoveryGroup.order < a.buffsGroup.order < a.readinessGroup.order
        for group in (a.recoveryGroup, a.buffsGroup, a.readinessGroup):
            assert group.type == "group" and group.inline is True
        r, b = a.recoveryGroup.args, a.buffsGroup.args
        assert r.topoffHeal.order < r.topoffThreshold.order < r.healthRecovery.order < r.recoveryManaThreshold.order < r.manaRecovery.order
        for control in (r.topoffHeal, r.topoffThreshold, r.healthRecovery, r.manaRecovery, r.recoveryManaThreshold):
            assert control.width == "full", "recovery controls must have aligned full-width rows"
        for _, control in b.items():
            assert control.width == "double", "buff selectors must use consistent readable widths"
        assert b.food.name == "Food Buff" and r.manaRecovery.name == "Mana Recovery Items"
        assert r.topoffThreshold.get() == 70 and r.recoveryManaThreshold.get() == 60
        assert r.manaRecovery.get() == "off" and r.healthRecovery.get() == "off"
        assert b.food.get() == ("auto" if forever else "haste")
        assert lua.eval("addon.db.profile.precombatBuffs.categories.food") == "haste"
        assert r.manaRecovery.hidden() is (not forever)
        assert r.healthRecovery.hidden() is (not forever)
        assert r.recoveryManaThreshold.hidden() is (not forever)
        assert r.recoveryManaThreshold.disabled() is True
        r.manaRecovery.set(None, "auto")
        assert r.recoveryManaThreshold.disabled() is False
        assert r.healthRecovery.get() == "off", "mana toggle must not change health recovery"
        r.manaRecovery.set(None, "off")
        lua.execute("""
            LibStub("JustAC-PrecombatEngine").GetRecoveryHeals=function() return {635,19750} end
            C_Spell={GetSpellName=function(id) return "Heal "..id end}
        """)
        choices = r.healthRecovery["values"]()
        assert choices[635] == "Heal 635" and choices[19750] == "Heal 19750"
        assert choices.auto == "Auto (Heal 635)" and choices[633] is None
        r.healthRecovery.set(None, 19750)
        assert r.healthRecovery.get() == 19750
        r.healthRecovery.set(None, "items")
        assert r.healthRecovery.get() == "items" and r.manaRecovery.get() == "off"
        r.healthRecovery.set(None, "auto")
        assert r.healthRecovery.get() == "auto"
        r.healthRecovery.set(None, "off")
        assert not a.readinessGroup.hidden()
        lua.execute('LibStub("JustAC-PrecombatEngine").STEALTH_REMINDER.ROGUE=nil')
        assert a.readinessGroup.hidden() is True, "no empty readiness group for unsupported classes"
        lua.execute('LibStub("JustAC-PrecombatEngine").STEALTH_REMINDER.ROGUE={}')
    print("preparation layout: both clients, ordering, labels, saved settings and Recovery Off passed")


def check_cdm_buttons():
    lua = LuaRuntime()
    lua.execute("""
local libs = {}
LibStub = setmetatable({
    NewLibrary = function(_, name) libs[name] = {}; return libs[name] end
}, { __call = function(_, name) return libs[name] end })
local L = setmetatable({}, { __index = function(_, key) return key end })
libs["AceLocale-3.0"] = { GetLocale = function() return L end }
libs["JustAC-OptionsWidgets"] = {
    toggle = function(_, _, opts) return opts end,
    select = function(_, _, opts) return opts end,
    spellDesc = function(key) return key end,
    soundControl = function() end,
    resetButton = function() return {}, {} end,
    NotifyChange = function() end,
}
libs["JustAC-OptionsSpellSearch"] = { SpecHeader = function(text) return text end }
function SetAdvisor(state, candidates, added)
    if state == nil then libs["JustAC-CdmAdvisor"] = nil; return end
    libs["JustAC-CdmAdvisor"] = {
        Status = function()
            local can = {}
            for i = 1, candidates do can[i] = { id = i, name = "Aura" } end
            return state, can, {}, added
        end,
    }
end
""")
    tracker = (SRC.parent.parent / "MaintenanceTracker.lua").read_text(encoding="utf-8")
    start = tracker.index("function MaintenanceTracker.SetCooldownManagerEnabled(on)")
    end = tracker.index("\nend", start) + len("\nend")
    lua.execute("""
MaintenanceTracker = {}
combat, cvar, acceptWrite, settingsWrites, rawWrites = false, false, true, 0, 0
function InCombatLockdown() return combat end
function GetCVarBool() return cvar end
C_CVar = {
    GetCVarBool = GetCVarBool,
    SetCVar = function(_, value)
        rawWrites = rawWrites + 1
        if acceptWrite then cvar = value == "1"; return true end
        return false
    end,
}
Settings = {
    GetSetting = function() return {} end,
    SetValue = function(_, value)
        settingsWrites = settingsWrites + 1
        if acceptWrite then cvar = value end
    end,
}
MaintenanceTracker.ApplyViewerVisibility = function() end
LibStub:NewLibrary("JustAC-MaintenanceTracker")
""")
    lua.execute(tracker[start:end])
    lua.execute("""
local mt = LibStub("JustAC-MaintenanceTracker")
mt.SetCooldownManagerEnabled = MaintenanceTracker.SetCooldownManagerEnabled
mt.ApplyViewerVisibility = MaintenanceTracker.ApplyViewerVisibility
addon = { db = { profile = {}, char = {} }, Print = function(_, text) message = text end }
""")
    lua.execute((SRC.parent / "General.lua").read_text(encoding="utf-8"))
    options = lua.eval(
        'LibStub("JustAC-OptionsGeneral").CreateTabArgs(addon).args'
    )
    cases = [
        ("ok", 1, 1, False, False),
        ("ok", 0, 0, True, True),
        ("nolayout", 1, 0, False, True),
        ("disabled", 0, 0, True, True),
        ("unavailable", 0, 0, True, True),
        ("unreadable", 0, 0, True, True),
        (None, 0, 0, True, True),
    ]
    bad = []
    for state, candidates, added, add_disabled, remove_disabled in cases:
        lua.globals().SetAdvisor(state, candidates, added)
        if options.cdmTrackAdd.disabled() != add_disabled:
            bad.append(f"CDM add availability: {state}, candidates={candidates}")
        if options.cdmTrackRemove.disabled() != remove_disabled:
            bad.append(f"CDM remove availability: {state}, added={added}")
    toggle = options.cooldownManagerEnable
    toggle.set(None, True)
    assert toggle.get() is True and lua.eval("addon.db.profile.cooldownManagerEnable") is True
    assert lua.globals().settingsWrites == 1 and lua.globals().rawWrites == 0
    lua.execute("cvar = false; acceptWrite = false")
    toggle.set(None, True)
    assert toggle.get() is False, "failed write must not leave a checked toggle"
    assert lua.globals().message == "Cooldown Manager enable failed", "refusal is reported"
    lua.execute("combat = true; acceptWrite = true; message = nil")
    toggle.set(None, True)
    assert lua.globals().message == "Cooldown Manager combat warning"
    assert lua.globals().settingsWrites == 2, "combat never attempts a write"
    lua.execute("combat = false; Settings = nil")
    toggle.set(None, True)
    assert toggle.get() is True and lua.globals().rawWrites == 1
    toggle.set(None, False)
    assert toggle.get() is False and lua.eval("addon.db.profile.cooldownManagerEnable") is False
    lua.execute("acceptWrite = false; message = nil")
    toggle.set(None, True)
    assert toggle.get() is False and lua.eval("addon.db.profile.cooldownManagerEnable") is False
    assert lua.globals().message is not None, "raw SetCVar false return is not success"
    return bad


def main():
    check_preparation_layout()
    src = SRC.read_text(encoding="utf-8")
    block = src[src.index("local FOREVER_UNUSED"):src.index("-- Refresh all dynamic options lists")]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
L = setmetatable({}, {__index = function(_, k) return k end})
Options = {}
hasPick = false
local B = { HasGamePick = function() return hasPick end }
LibStub = function(name) if name == "JustAC-BlizzardAPI" then return B end end
""")
    lua.execute(block + "\n_G.Apply = ApplyForeverUnused")
    lua.execute("""
addon = { db = { profile = {} }, optionsTable = { args = {
  general = { args = { disableBlizzardHighlight = { type = "toggle", desc = "d" } } },
  offensive = { args = {
    customQueue = { args = {
      spellListGroup = { args = { leadMode = { type = "select", desc = function() return "lm" end } } },
      queueContentGroup = { args = { includeHiddenAbilities = { type = "toggle" } } } } },
    gapClosers = { args = { spellListGroup = { args = { gapRestore = { type = "execute", desc = "r" } } } } } } },
  profiles = { args = { specSwitching = { type = "group", args = {} } } } } } }
Apply(addon)
Apply(addon)
hasPick = true
retail = { db = { profile = {} }, optionsTable = { args = {
  general = { args = { disableBlizzardHighlight = { type = "toggle", desc = "d" } } } } } }
Apply(retail)
""")
    o = lua.eval("addon.optionsTable.args")
    cq = o.offensive.args.customQueue.args
    checks = [
        (o.general.args.disableBlizzardHighlight.disabled is True, "toggle greyed"),
        (o.general.args.disableBlizzardHighlight.desc == "d\n\n" + NOTE, "string desc noted once"),
        (cq.spellListGroup.args.leadMode.desc() == "lm\n\n" + NOTE, "function desc wrapped once"),
        (cq.queueContentGroup.args.includeHiddenAbilities.desc == NOTE, "no desc -> the note alone"),
        (o.offensive.args.gapClosers.args.spellListGroup.args.gapRestore.disabled is True, "button greyed"),
        (o.profiles.args.specSwitching.disabled is True, "whole group greyed"),
        (lua.eval("#Options.foreverUnresolved") == 0, "every listed path resolved and recorded"),
        (lua.eval("retail.optionsTable.args.general.args.disableBlizzardHighlight.disabled") is None,
         "retail (game pick present): untouched"),
    ]
    bad = [why for ok, why in checks if not ok]
    bad.extend(check_cdm_buttons())
    for why in bad:
        print("  FAIL", why)
    print("forever options: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
