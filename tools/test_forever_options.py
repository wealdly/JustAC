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


def main():
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
    for why in bad:
        print("  FAIL", why)
    print("forever options: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
