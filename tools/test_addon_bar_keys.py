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
FindBaseSpellByID = function(id) return id end
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


def main():
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
