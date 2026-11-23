# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Keybinds for spells on an action-bar addon's own bars, checked outside the game.
#
# Loads the real ActionBarScanner.lua with the WoW API stubbed and a fake shared
# action-button library registered in LibStub, then asks it for hotkeys. The rules under
# test: an addon bar fills slots the Blizzard map misses or leaves unkeyed, only when its
# own command is keyed, never through a Blizzard command, and never displaces a keyed
# Blizzard binding.
#
# Run: python tools/test_addon_bar_keys.py

import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(__file__).resolve().parent.parent / "ActionBarScanner.lua"

PRELUDE = r"""
-- Any WoW global the scanner touches but this test does not care about: callable, nil.
local stub; stub = setmetatable({}, { __index = function() return stub end, __call = function() return nil end })
setmetatable(_G, { __index = function() return stub end })
local now = 100
function GetTime() now = now + 1; return now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Spell = { GetSpellInfo = function(id) return SPELLS[id] and { name = SPELLS[id] } or nil end }
C_Item = { GetItemSpell = function() return nil end }
C_ActionBar = { FindSpellActionButtons = function(id)
    local out = {}
    for slot, sid in pairs(BAR) do if sid == id then out[#out + 1] = slot end end
    table.sort(out)
    return out
end }
C_SpellBook = { FindBaseSpellByID = function(id) return id end }
HasAction = function(slot) return BAR[slot] ~= nil end
GetBindingKey = function(cmd) return BINDS[cmd] end
local libs = {}
LibStub = setmetatable({
    libs = libs,
    NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end,
    IterateLibraries = function(self) return pairs(self.libs) end,
}, { __call = function(_, name) return libs[name] end })
libs["JustAC-BlizzardAPI"] = {
    GetAddon = function() return { db = { profile = {} } } end,
    GetActionInfo = function(slot) if BAR[slot] then return "spell", BAR[slot] end end,
    GetBarSpells = function()
        local entries={}
        for slot in pairs(BAR) do entries[#entries+1]={slot=slot} end
        return entries
    end,
    IsSecretValue = function() return false end,
}
function AddButtonLib(major, list)
    local reg = {}
    for _, b in ipairs(list) do
        local slot, cmd = b[1], b[2]
        reg[{ GetAction = function() return "action", slot end,
              GetBindingAction = function() return cmd end }] = true
    end
    libs[major] = { GetAllButtons = function() local c = {}; for k in pairs(reg) do c[k] = true end; return c end }
end
"""

LIB = "LibActionButton-1.0"
CASES = [
    # name, bar {slot: spellID}, bindings {command: key}, libraries {major: [(slot, command)]}, spell, expected
    ("no addon bar: page-2 spell has no key", {14: 111}, {}, {}, 111, ""),
    ("addon bar on page 2, own command keyed", {14: 111}, {"XBAR2BUTTON2": "F"},
     {LIB + "-Fork": [(14, "XBAR2BUTTON2")]}, 111, "F"),
    ("unkeyed addon bar claims nothing", {14: 111}, {}, {LIB: [(14, "XBAR2BUTTON2")]}, 111, ""),
    ("addon button on a Blizzard command is left to the Blizzard map", {73: 222},
     {"ACTIONBUTTON1": "1"}, {LIB: [(73, "ACTIONBUTTON1")]}, 222, ""),
    ("Blizzard slot unkeyed, addon CLICK command keyed", {25: 333},
     {"CLICK XBar3Button1:LeftButton": "G"}, {LIB: [(25, "CLICK XBar3Button1:LeftButton")]}, 333, "G"),
    ("Blizzard slot keyed wins over the addon command", {25: 333},
     {"MULTIACTIONBAR3BUTTON1": "Q", "CLICK XBar3Button1:LeftButton": "G"},
     {LIB: [(25, "CLICK XBar3Button1:LeftButton")]}, 333, "Q"),
    ("other library families are ignored", {14: 111}, {"XBAR2BUTTON2": "F"},
     {"SomeOtherLib-1.0": [(14, "XBAR2BUTTON2")]}, 111, ""),
    ("main bar unchanged", {3: 444}, {"ACTIONBUTTON3": "3"}, {LIB: [(14, "XBAR2BUTTON2")]}, 444, "3"),
]


def hotkey(bar, binds, button_libs, spell):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    lua.execute("SPELLS = { [111] = 'Alpha', [222] = 'Beta', [333] = 'Gamma', [444] = 'Delta' }")
    g.BAR, g.BINDS = lua.table_from(bar), lua.table_from(binds)
    lua.execute(PRELUDE)
    for major, buttons in button_libs.items():
        g.AddButtonLib(major, lua.table_from([lua.table_from(b) for b in buttons]))
    lua.execute(SRC.read_text(encoding="utf-8"))
    scanner = lua.eval('LibStub.libs["JustAC-ActionBarScanner"]')
    scanner.RebuildKeybindCache()
    return scanner.GetSpellHotkey(spell)


def check_autoattack_macros():
    cases = (
        (5019, "#showtooltip\n/use !Shoot", "/cast Smite", "1"),
        (5019, "/use [mod:alt] !Shoot; !Shoot", "/cast Smite", "1"),
        (5019, "/use !Shoot\n/use 13", "/use !Shoot", "2"),
        (5019, "/use [mod:alt] Smite; !Shoot", "/use !Shoot", "2"),
        (6603, "/use Attack", "/cast Smite", "1"),
        (75, "/use !Auto Shot", "/cast Smite", "1"),
        (6603, "/startattack\n/cast Smite", "/startattack", "2"),
        (5019, "/cast Smite\n/cast !Shoot", "#showtooltip Shoot\n/cast !Shoot", "2"),
        (5019, "/cast !Shoot\n/use 13", "/cast !Shoot", "2"),
        (5019, "/cast [mod:alt] Smite; !Shoot", "/cast !Shoot", "2"),
        (5019, "/castsequence !Shoot, Smite", "/cast !Shoot", "2"),
        (5019, "/cast !Shoot\n/run print('x')", "/cast !Shoot", "2"),
        (5019, "/cast !Shoot\n/click OtherButton", "/cast !Shoot", "2"),
        (5019, "/cast !Shoot\n/stopcasting", "/cast !Shoot", "2"),
        (5019, "/cast !Shoot\n/startattack", "/cast Smite", ""),
        (6603, "/startattack", "/cast Smite", "1"),
        (5019, "/cast !Shoot", "/cast Smite", "1"),
    )
    for spell, first, second, expected in cases:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
            SPELLS={[6603]='Attack',[5019]='Shoot',[75]='Auto Shot',[585]='Smite'}
            BAR={[1]=5019,[2]=5019}
            BINDS={ACTIONBUTTON1='1',ACTIONBUTTON2='2'}
        """)
        lua.execute(PRELUDE)
        lua.globals().bodies = lua.table_from({1: first, 2: second})
        lua.execute("""
            C_SpecializationInfo={GetSpecialization=function() return 0 end}
            MAX_ACCOUNT_MACROS=120
            C_Spell.GetOverrideSpell=function() end
            function GetActionInfo(slot) return "macro",slot end
            function GetActionText(slot) return "M"..slot end
            function GetMacroInfo(index)
                if type(index)=="number" and bodies[index] then return "M"..index,nil,bodies[index] end
            end
            function GetNumMacros() return 2,0 end
            LibStub.libs["JustAC-BlizzardAPI"].GetDebugMode=function() return false end
            LibStub.libs["JustAC-BlizzardAPI"].GetActionInfo=function(slot)
                if BAR[slot] then return "macro",slot,"spell",BAR[slot] end
            end
        """)
        lua.execute((SRC.parent / "MacroParser.lua").read_text(encoding="utf-8"))
        lua.execute(SRC.read_text(encoding="utf-8"))
        scanner = lua.eval('LibStub.libs["JustAC-ActionBarScanner"]')
        scanner.RebuildKeybindCache()
        actual = scanner.GetSpellHotkey(spell)
        assert actual == expected, (spell, first, second, actual, expected)
        expected_slot = int(expected) if expected else None
        assert scanner.GetAutoAttackSlotForSpell(spell) == expected_slot, (spell, first, second)
        assert scanner.GetDirectSlotForSpell(spell) is None, "macros never become direct cooldown slots"
    lua.execute("""
        function GetActionInfo() return "macro",5019,"spell" end
        function GetActionText() return "Shared" end
        function GetMacroInfo(index)
            if type(index)=="number" and bodies[index] then return "Shared",nil,bodies[index] end
        end
        LibStub.libs["JustAC-MacroParser"].InvalidateMacroCache()
        LibStub.libs["JustAC-ActionBarScanner"].InvalidateHotkeyCache()
    """)
    assert scanner.GetSpellHotkey(5019) == "", "ambiguous same-name macros cannot prove attack-only"
    assert scanner.GetAutoAttackSlotForSpell(5019) is None, "ambiguous checked macro is not a running Shoot"
    print("Autoattack hotkeys: pure start/cast/use macros preferred; mixed actions excluded")


def check_spell_press_starts_attack():
    cases = (
        ("/startattack\n/cast Smite", True, "a /startattack line starts melee with the cast"),
        ("/startattack [harm,nodead]\n/cast Smite", True, "conditions still start melee"),
        ("/cast Smite\n/startattack", True, "line order does not matter"),
        ("/cast Smite", False, "a plain cast macro does not start melee"),
        ("#/startattack\n/cast Smite", False, "a commented line is ignored"),
        (None, False, "a plain spell button is not a macro"),
    )
    for body, expected, why in cases:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
            SPELLS={[6603]='Attack',[585]='Smite'}
            BAR={[1]=585}
            BINDS={ACTIONBUTTON1='1'}
        """)
        lua.execute(PRELUDE)
        lua.globals().body = body if body is not None else False  # nil would read the stub
        lua.execute("""
            C_SpecializationInfo={GetSpecialization=function() return 0 end}
            MAX_ACCOUNT_MACROS=120
            C_Spell.GetOverrideSpell=function() end
            function GetActionInfo(slot) if body then return "macro",slot end return "spell",585 end
            function GetActionText(slot) return "M"..slot end
            function GetMacroInfo(index)
                if body and (index==1 or index=="M1") then return "M1",nil,body end
            end
            function GetNumMacros() return 1,0 end
            LibStub.libs["JustAC-BlizzardAPI"].GetDebugMode=function() return false end
            LibStub.libs["JustAC-BlizzardAPI"].GetActionInfo=function(slot)
                if BAR[slot] and body then return "macro",slot,"spell",BAR[slot] end
                if BAR[slot] then return "spell",BAR[slot] end
            end
        """)
        lua.execute((SRC.parent / "MacroParser.lua").read_text(encoding="utf-8"))
        lua.execute(SRC.read_text(encoding="utf-8"))
        scanner = lua.eval('LibStub.libs["JustAC-ActionBarScanner"]')
        scanner.RebuildKeybindCache()
        assert scanner.GetSpellHotkey(585) == "1", (why, "the cast keeps its key")
        assert scanner.SpellPressStartsAttack(585) == expected, why
    print("Spell press starts attack: /startattack macros detected; plain casts, comments and buttons not")


def main():
    check_autoattack_macros()
    check_spell_press_starts_attack()
    bad = []
    for name, bar, binds, button_libs, spell, want in CASES:
        got = hotkey(bar, binds, button_libs, spell)
        if got != want:
            bad.append("FAIL  %s: got %r, want %r" % (name, got, want))
    for line in bad:
        print(line)
    print("addon bar keys: %d case(s), %d failure(s)" % (len(CASES), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
