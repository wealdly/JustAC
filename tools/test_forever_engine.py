# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The Forever half of RotationImport, run outside the game against the real file: which
# talent tree gets installed, that every rank of a chain finds the entry, and that the
# pool additions offer the rank the player would press. The talent and spell reads are
# stubbed - they are the game's answers, and the point is what the module does with them.
#
# Run: python tools/test_forever_engine.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "RotationImport.lua"

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end },
    { __call = function(_, name) return libs[name] end })
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
libs["JustAC-SpellDB"] = { GetSpecKey = function() return specKey, "WARRIOR" end, CLASS_GAPCLOSER_DEFAULTS = {},
    IsForever = function() return true end }
libs["JustAC-BlizzardAPI"] = { ResolveSpellID = function(id) return id end }
known = {}
function IsPlayerSpell(id) return known[id] == true end
form = 0
function GetShapeshiftFormID() return form end
spent = {}          -- groupID -> points
groups = {}         -- { {groupID=, displayName=} }
C_SpecializationInfo = { GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1491 end }
C_ClassTalents = { GetActiveConfigID = function() return 7 end,
    GetTraitTreeForSpec = function() return 99 end }
C_Traits = { GetGroupDisplayInfoByTreeID = function() return groups end,
    GetGroupCurrencyInfo = function(_, ids)
        local out = {}
        for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = { { spent = spent[id] or 0 } } } end
        return out
    end }
specKey = "WARRIOR_F"
"""

DATA = r"""
local RI = LibStub("JustAC-RotationImport")
RI.RegisterForever({
  WARRIOR_F = {
    default = "arms",
    arms = { st = { {id=78,gates={}}, {id=772,gates={},delegated=true} } },
    fury = { st = { {id=23881,gates={}} } },
  },
  DRUID_F = {
    default = "feral",
    feral = { st = { {id=5221,gates={}} } },
    feral_bear = { st = { {id=6807,gates={}} } },
  },
}, { [78] = {78, 284, 285} }, {
  WARRIOR_F = { 78, 772, 23881, 20554 },   -- class abilities (rank 1) + a damage racial
})
return RI
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(SRC.read_text(encoding="utf-8"))
    RI = lua.execute(DATA)
    g = lua.globals()
    bad = []

    def check(cond, why):
        if not cond:
            bad.append(why)

    # No points spent: the class default.
    check(RI.GetForeverTree() == "arms", "no talents -> default tree")
    # Any rank finds the entry; the rank-1 entry is the one returned.
    check(RI.GetEntry(285, "st") is not None, "rank 3 id finds the rank-1 entry")
    rec = RI.GetEntry(284, "st")
    check(rec is not None and rec.rank == 1, "rank 2 shares rank-1's priority")
    check(RI.RankBase(285) == 78 and RI.RankBase(999) == 999, "RankBase maps ranks, passes others")
    # Highest KNOWN rank, not highest existing.
    g.known = lua.eval("{[78]=true,[284]=true}")
    check(RI.HighestKnownRank(78) == 284, "highest known rank")
    check(RI.HighestKnownRank(285) == 284, "from any rank of the chain")
    g.known = lua.eval("{}")
    check(RI.HighestKnownRank(78) is None, "nothing known -> nil")
    # The bar pool admits class abilities (any rank) and damage racials, nothing else.
    check(RI.IsClassAbility(285) is True, "a rank-3 class ability is a class ability")
    check(RI.IsClassAbility(20554) is True, "a damage racial joins the pool")
    check(RI.IsClassAbility(2580) is False, "a tracking spell on the bar (Find Minerals) does not")
    # Insertable: every entry incl. delegated (Forever), offered at the known rank.
    g.known = lua.eval("{[78]=true,[284]=true,[772]=true}")
    RI.InvalidateLookup()
    ins = list(RI.GetInsertable().values())
    check(ins == [284, 772], "insertable = known ranks, delegated included: %s" % ins)
    # Points decide the tree, re-read on invalidation.
    g.groups = lua.eval("{ {groupID=1, displayName='Arms'}, {groupID=2, displayName='Fury'} }")
    g.spent = lua.eval("{[1]=3, [2]=5}")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "fury", "most points spent wins")
    check(RI.GetEntry(23881, "st") is not None and RI.GetEntry(78, "st") is None,
          "only the installed tree's entries resolve")
    # A tree name the data lacks falls back to its first word, then the default.
    g.specKey = "DRUID_F"
    g.groups = lua.eval("{ {groupID=3, displayName='Feral Combat'} }")
    g.spent = lua.eval("{[3]=4}")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral", "'Feral Combat' -> feral")
    g.form = 5
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "feral in bear form -> feral_bear")
    # Form changes re-pick only when the cat / bear choice flips.
    check(RI.OnFormChanged() is False, "still in bear form -> no re-pick")
    g.form = 1
    check(RI.OnFormChanged() is True and RI.GetForeverTree() == "feral", "leaving bear form -> feral")
    # Unregistered key: retail behaviour untouched.
    g.specKey = "MONK_1"
    check(RI.HasRotation() is False, "no data -> no rotation")

    for why in bad:
        print("  FAIL", why)
    print("forever engine: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
