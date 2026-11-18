# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The debug character export (/jac inspect character) with controlled client values.

Loads the export section of Debug/Systems.lua in Lua 5.1 with stubbed client calls and
checks the JSON it shows: plain fields, highest known ranks, trait picks, item link
parsing, removal of a crafter's player id, and that a secret or failing read is left out instead of written.

Run: python tools/test_character_export.py
"""
import json
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "Debug" / "Systems.lua").read_text(encoding="utf-8")
BLOCK = SOURCE[SOURCE.index("local EXPORT_SLOTS"):]

STUBS = r"""
SECRET = {}
local function IsSecret(v) return v == SECRET end
DebugCommands = {}
shown, printed = nil, {}
addon = { Print = function(_, text) printed[#printed + 1] = text end }
local widgets = {}
local function widget()
    local w = {}
    for _, name in ipairs({"SetTitle", "SetStatusText", "SetLayout", "SetWidth", "SetHeight", "SetCallback",
                           "SetLabel", "DisableButton", "AddChild", "SetFocus", "HighlightText"}) do
        w[name] = function() end
    end
    w.SetText = function(_, text) shown = text end
    return w
end
local libs = {
    ["AceGUI-3.0"] = { Create = function() return widget() end, Release = function() end },
    ["JustAC-RotationImport"] = {
        ClassAbilityIds = function() return { [78] = true, [772] = true, [12294] = true } end,
        HighestKnownRank = function(id) return ({ [78] = 284, [772] = 772 })[id] end,
    },
}
function LibStub(name) return libs[name] end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Human", RACE end
function UnitLevel() return 27 end
function GetBuildInfo() return "1.60.1", "70938", "Nov 1 2026", 16001 end
function GetInventoryItemID(_, slot) return ITEMS[slot] end
function GetInventoryItemLink(_, slot)
    if slot == 7 then error("denied") end
    return LINKS[slot]
end
C_ClassTalents = { GetActiveConfigID = function() return 5 end }
C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 900 } } end,
    GetTreeNodes = function() return { 101, 102, 103 } end,
    GetNodeInfo = function(_, node)
        if node == 101 then return { activeEntry = { entryID = 2001, rank = 3 } } end
        if node == 102 then return { activeEntry = { entryID = 2002, rank = 0 } } end
        return { activeEntry = { entryID = 2003, rank = SECRET } }
    end,
}
"""


def run(race="Human"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS.replace("local function IsSecret", "function IsSecret"))
    g = lua.globals()
    g.RACE = race if race is not None else g.SECRET
    lua.execute("""
        ITEMS = { [5] = 2317, [7] = 7282, [16] = 872 }
        LINKS = {
            [5] = "|cff1eff00|Hitem:2317:15::::::::27:1491::::::::Player-1234-0ABCDEF0:|h[Dark Leather Tunic]|h|r",
            [16] = "|cff0070dd|Hitem:872:0:0:0:0:0:0:0:27:0:0:0:2:12688:12689|h[Rockslicer]|h|r",
        }
    """)
    lua.execute(BLOCK + "\nDebugCommands.ExportCharacter(addon)")
    return g.shown, [g.printed[i] for i in range(1, len(g.printed) + 1)]


def main():
    shown, printed = run()
    data = json.loads(shown)
    assert data["class"] == "WARRIOR" and data["race"] == "Human" and data["level"] == 27, data
    assert data["interface"] == 16001
    assert data["spells"] == [284, 772], data["spells"]              # highest known rank; unknown left out
    assert data["talents"] == [{"node": 101, "entry": 2001, "rank": 3}], data["talents"]   # rank 0 and secret left out
    gear = data["gear"]
    assert set(gear) == {"5", "7", "16"}, gear
    assert gear["5"]["item"] == 2317 and gear["5"]["enchant"] == 15 and gear["5"]["bonus"] == []
    assert "Player-" not in shown and gear["5"]["link"] == "2317:15::::::::27:1491:::::::::", gear["5"]   # maker removed
    assert gear["16"]["bonus"] == [12688, 12689] and gear["16"]["link"].startswith("872:0:")
    assert gear["7"] == {"item": 7282, "enchant": 0, "suffix": 0, "bonus": []}, gear["7"]   # link call failed
    assert any("slot 7" in line for line in printed), printed

    shown, printed = run(race=None)                                  # a secret race: nothing is written
    assert shown is None and any("not readable" in line for line in printed), printed
    print("character export: fields, ranks, traits, link parsing, maker removal, failed and secret reads passed")


if __name__ == "__main__":
    main()
