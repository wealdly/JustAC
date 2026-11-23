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

from wow_stubs import LuaRuntime

SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "RotationImport.lua"

PRELUDE = r"""
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end },
    { __call = function(_, name) return libs[name] end })
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
libs["JustAC-SpellDB"] = { GetSpecKey = function() return specKey, "WARRIOR" end, CLASS_GAPCLOSER_DEFAULTS = {},
    IsForever = function() return true end,
    FOREVER_TREE_GEAR = { WARRIOR_F = { protection = { {4, 64} } } } }
shield = nil        -- true / false / nil (unreadable)
profile = {}
libs["JustAC-BlizzardAPI"] = { ResolveSpellID = function(id) return id end,
    GetProfile = function() return profile end,
    HasEquippedItemClass = function(classID, mask)
        assert(classID == 4 and mask == 64)
        return shield
    end }
fighting = false
function UnitAffectingCombat() return fighting end
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
    protection = { st = { {id=23922,gates={}} } },
  },
  DRUID_F = {
    default = "feral",
    feral = { st = { {id=5221,gates={}} } },
    feral_bear = { st = { {id=6807,gates={}} } },
  },
}, { [78] = {78, 284, 285} }, {
  WARRIOR_F = { 78, 772, 23881, 20554 },   -- class abilities (rank 1) + a damage racial
}, { [78] = 6, [772] = 0 })
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
    check(RI.GetPushbackDamageCooldown(285) == 6 and RI.GetPushbackDamageCooldown(772) == 0
          and RI.GetPushbackDamageCooldown(999) is None, "pushback cooldown resolves ranks and unknowns")
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
    # A tree whose own attacks need gear the player is not wearing is skipped: points say what
    # the player is building, gear says how they fight. Unreadable gear rules nothing out.
    g.groups = lua.eval("{ {groupID=1, displayName='Arms'}, {groupID=2, displayName='Fury'}, "
                        "{groupID=3, displayName='Protection'} }")
    for shield, spent, want, why in (
            ("true", "{[3]=5}", "protection", "shield worn: the shield tree"),
            ("nil", "{[3]=5}", "protection", "unreadable gear rules nothing out"),
            ("false", "{[3]=5}", "arms", "no shield, only shield-tree points: the class default"),
            ("false", "{[2]=2, [3]=5}", "fury", "no shield: most points among the trees gear allows"),
            ("false", "{[1]=6, [3]=5}", "arms", "another tree leads anyway"),
            ("true", "{[2]=2, [3]=5}", "protection", "shield worn: most points wins")):
        g.shield = lua.eval(shield)
        g.spent = lua.eval(spent)
        RI.OnGearChanged()
        RI.InvalidateLookup()
        check(RI.GetForeverTree() == want, "%s (got %s)" % (why, RI.GetForeverTree()))
    # Gear changes re-pick, but never during a fight: the gear read then is the one from before
    # it, whichever path re-picks the tree meanwhile, and the change applies when the fight ends.
    g.shield = lua.eval("true")
    g.spent = lua.eval("{[3]=5}")
    RI.OnGearChanged()
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "protection" and RI.OnGearChanged() is False, "same gear: no re-pick")
    g.shield = lua.eval("false")
    g.fighting = True
    check(RI.OnGearChanged() is False and RI.GetForeverTree() == "protection", "a swap in combat keeps the list")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "protection", "and so does a talent or spell change during that fight")
    g.fighting = False
    check(RI.OnGearChanged() is True and RI.GetForeverTree() == "arms", "the swap applies when the fight ends")
    check(RI.OnGearChanged() is False, "nothing left to apply: no re-pick")
    g.shield = lua.eval("true")
    check(RI.OnGearChanged() is True and RI.GetForeverTree() == "protection", "out of combat it applies at once")
    # The player's own choice (the Play Style option) comes before points and gear; a value the
    # data does not have is ignored. Automatic is still reported for the option's label.
    g.shield = lua.eval("false")
    g.spent = lua.eval("{[1]=6, [3]=5}")
    RI.OnGearChanged()
    for style, want, why in (("{WARRIOR_F='fury'}", "fury", "a chosen tree beats points"),
                             ("{WARRIOR_F='protection'}", "protection", "a chosen tree beats gear"),
                             ("{WARRIOR_F='default'}", "arms", "'default' is not a tree"),
                             ("{WARRIOR_F='holy'}", "arms", "a tree the class lacks is ignored"),
                             ("{DRUID_F='feral'}", "arms", "another class's choice does not apply"),
                             ("nil", "arms", "no choice: automatic")):
        g.profile = lua.eval("{playStyle=%s}" % style)
        RI.InvalidateLookup()
        check(RI.GetForeverTree() == want, "%s (got %s)" % (why, RI.GetForeverTree()))
    g.profile = lua.eval("{playStyle={WARRIOR_F='fury'}}")
    RI.InvalidateLookup()
    s = RI.PlayStyleChoices()
    check([c.key for c in s.choices.values()] == ["arms", "fury", "protection"] and s.choices[1].name == "Arms",
          "choices are the game's trees, in its order, with its names")
    check(s.automatic == "Arms" and s.specKey == "WARRIOR_F" and s.chosen == "fury",
          "automatic is named beside the choice in effect")
    check(s.following == "Fury" and s.reason == "chosen" and s.ruledOut is None, "following: your choice")
    # Why the automatic pick is what it is: the most points, the gear, or no points yet.
    g.profile = lua.eval("{}")
    for shield, spent, following, reason, ruled_out in (
            ("true", "{[3]=5}", "Protection", "points", None),
            ("false", "{[3]=5}", "Arms", "gear", "Protection"),
            ("false", "{[2]=2, [3]=5}", "Fury", "gear", "Protection"),
            ("false", "{}", "Arms", "default", None)):
        g.shield, g.spent = lua.eval(shield), lua.eval(spent)
        RI.OnGearChanged()
        RI.InvalidateLookup()
        s = RI.PlayStyleChoices()
        check((s.following, s.reason, s.ruledOut) == (following, reason, ruled_out),
              "%s / %s: got %s" % (shield, spent, (s.following, s.reason, s.ruledOut)))
        check(RI.GetForeverTree() == following.lower(), "the read-out names the installed tree")
    g.profile = lua.eval("{playStyle={WARRIOR_F='fury'}}")
    g.shield, g.spent = lua.eval("false"), lua.eval("{[1]=6, [3]=5}")
    RI.OnGearChanged()
    RI.InvalidateLookup()
    check(RI.HasPlayStyles() is True, "the class has trees to choose between")
    check(RI.OnGearChanged() is False, "a chosen tree does not follow gear")
    g.profile = lua.eval("{}")
    g.shield = lua.eval("nil")
    g.spent = lua.eval("{}")
    # A tree name the data lacks falls back to its first word, then the default.
    g.specKey = "DRUID_F"
    g.groups = lua.eval("{ {groupID=3, displayName='Feral Combat'} }")
    g.spent = lua.eval("{[3]=4}")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral", "'Feral Combat' -> feral")
    g.form = 5
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "feral in bear form -> feral_bear")
    g.profile = lua.eval("{playStyle={DRUID_F='feral'}}")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "a chosen Feral still follows Bear Form")
    s = RI.PlayStyleChoices()
    check(s.automatic == "Feral Combat" and s.chosen == "feral" and s.following == "Feral Combat" and s.bearForm is True,
          "the bear list is named as the Feral tree, in Bear Form")
    g.profile = lua.eval("{}")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "automatic again: still the bear list in Bear Form")
    # Form changes re-pick only when the cat / bear choice flips.
    check(RI.OnFormChanged() is False, "still in bear form -> no re-pick")
    g.form = 1
    check(RI.OnFormChanged() is True and RI.GetForeverTree() == "feral", "leaving bear form -> feral")
    check(RI.OnFormChanged() is False, "still in cat form -> no re-pick")
    g.form = 8
    check(RI.OnFormChanged() is True and RI.GetForeverTree() == "feral_bear",
          "entering Dire Bear form -> feral_bear")
    g.form = 5
    check(RI.OnFormChanged() is False, "Bear and Dire Bear share the installed list")
    # A tree that leads with a form the character has not learned (Cat Form at 20) is skipped by
    # the automatic pick: a levelling Feral druid in caster form follows the class default, its
    # bear list in Bear Form, and Feral once Cat Form is learned.
    lua.execute("""
        LibStub("JustAC-RotationImport").RegisterForever({ DRUID_L = {
            default = "balance",
            balance = { st = { {id=8921,gates={}}, {id=5176,gates={}} } },
            feral = { st = { {id=768,gates={{t="buff",id=768,neg=true}},form=true}, {id=1082,gates={}} } },
            feral_bear = { st = { {id=6807,gates={}} } },
        } }, {}, {}, {})
    """)
    g.specKey = "DRUID_L"
    g.groups = lua.eval("{ {groupID=1, displayName='Balance'}, {groupID=3, displayName='Feral Combat'} }")
    g.spent = lua.eval("{[3]=6}")
    g.form = 0
    g.profile = lua.eval("{}")
    lua.execute("known[768] = nil")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "balance", "Feral points, Cat Form not learned, caster form -> the caster list")
    s = RI.PlayStyleChoices()
    check(s.reason == "form" and s.ruledOut == "Feral Combat", ("the read-out names the unlearned form", s.reason, s.ruledOut))
    g.form = 5
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "Bear Form needs no Cat Form: the bear list")
    g.form = 0
    lua.execute("known[768] = true")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral", "Cat Form learned -> the Feral list")
    g.profile = lua.eval("{playStyle={DRUID_L='feral'}}")
    lua.execute("known[768] = nil")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral", "a chosen Feral is the player's: kept")
    g.profile = lua.eval("{}")
    lua.execute("known[768] = nil")
    # No points yet and the class default (Feral) needs Cat Form: the first playable tree.
    lua.execute("""
        LibStub("JustAC-RotationImport").RegisterForever({ DRUID_N = {
            default = "feral",
            balance = { st = { {id=8921,gates={}}, {id=5176,gates={}} } },
            feral = { st = { {id=768,gates={{t="buff",id=768,neg=true}},form=true}, {id=1082,gates={}} } },
            feral_bear = { st = { {id=6807,gates={}} } },
        } }, {}, {}, {})
    """)
    g.specKey = "DRUID_N"
    g.spent = lua.eval("{}")
    g.form = 0
    lua.execute("known[768] = nil")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "balance", "no points, the Feral default unplayable -> the first playable tree")
    s = RI.PlayStyleChoices()
    check(s.reason == "form", ("the read-out says why the default is not followed", s.reason))
    lua.execute("known[768] = true")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral", "Cat Form learned: the class default again")
    lua.execute("known[768] = nil")
    # Form masks: in a form a spell's mask leaves out, an unlisted spell is left out (Moonfire in
    # Bear Form leaves the form); listed spells, other forms and caster form are untouched.
    lua.execute("""
        bit = bit or { band = function(a, b) return math.floor(a) & math.floor(b) end }
        LibStub("JustAC-RotationImport").RegisterForever({ DRUID_M = {
            default = "balance",
            balance = { st = { {id=8921,gates={}}, {id=5176,gates={}} } },
            feral_bear = { st = { {id=6807,gates={}} } },
        } }, {}, {}, {}, {}, {}, { [8921] = 1073741824, [6807] = 144 })
    """)
    g.specKey = "DRUID_M"
    g.groups = lua.eval("{ {groupID=1, displayName='Balance'} }")
    g.spent = lua.eval("{[1]=5}")
    g.form = 5
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "Bear Form takes the bear list whatever the tree (Balance points)")
    check(RI.IsLeftOut(8921, "st") is True, "unlisted Moonfire in Bear Form: left out (it leaves the form)")
    check(RI.IsLeftOut(6807, "st") is False, "listed Maul in Bear Form: offered")
    g.form = 0
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "balance", "caster form: the Balance list again")
    check(RI.IsLeftOut(8921, "st") is False, "caster form: Moonfire is not left out")
    g.form = 31
    RI.InvalidateLookup()
    check(RI.IsLeftOut(8921, "st") is False, "Moonkin Form casts Moonfire")
    # Back to the Feral druid in Bear Form for the cases below.
    g.specKey = "DRUID_F"
    g.groups = lua.eval("{ {groupID=3, displayName='Feral Combat'} }")
    g.spent = lua.eval("{[3]=4}")
    g.form = 5
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "feral_bear", "restored: Feral druid in Bear Form")
    g.form = None
    check(RI.OnFormChanged() is True and RI.GetForeverTree() == "feral",
          "no shapeshift form -> feral")
    lua.execute("GetShapeshiftFormID = nil")
    check(RI.OnFormChanged() is False, "missing form API leaves the non-bear list installed")
    # Unregistered key: retail behaviour untouched.
    g.specKey = "MONK_1"
    check(RI.HasRotation() is False, "no data -> no rotation")

    generated = SRC.parent / "Data" / "Forever" / "Rotations.lua"
    lua.execute(generated.read_text(encoding="utf-8"))
    check(RI.GetPushbackDamageCooldown(8042) == 6 and RI.GetPushbackDamageCooldown(8044) == 6,
          "generated Earth Shock cooldown resolves both ranks")
    check(RI.GetPushbackDamageCooldown(120) is None, "ten-second cooldown remains excluded")
    # Wide-only: listed for cleave/AoE but absent from the single-target list.
    g.specKey = "WARRIOR_F"
    g.groups = lua.eval("{ {groupID=1, displayName='Arms'} }")
    g.spent = lua.eval("{[1]=5}")
    RI.InvalidateLookup()
    check(RI.IsWideOnly(6343) is True, "generated Arms data: Thunder Clap is wide-only")
    check(RI.IsWideOnly(772) is False and RI.IsWideOnly(78) is False,
          "generated Arms data: Rend and Heroic Strike are single-target entries")
    check(RI.IsWideOnly(999999) is False, "an unlisted spell is not wide-only")
    # Left out: a class ability the tree's list deliberately drops is kept out, not a filler.
    check(RI.IsLeftOut(1715, "st") is False, "generated Arms data: Arms keeps its Hamstring")
    hamstring_ranks = list(RI.RankChain(1715).values())
    g.groups = lua.eval("{ {groupID=1, displayName='Fury'} }")
    RI.InvalidateLookup()
    check(RI.GetForeverTree() == "fury", "Fury installed")
    check(all(RI.IsLeftOut(r, ctx) is True for r in hamstring_ranks for ctx in ("st", "cleave", "aoe")),
          "generated Fury data: every Hamstring rank is left out in every context")
    check(RI.IsLeftOut(23881, "st") is False and RI.IsLeftOut(999999, "st") is False,
          "a listed or unknown spell is not left out")
    # Closed list: named means listed by the installed tree in some context, any rank.
    check(RI.IsNamed(23881) is True, "generated Fury data: Bloodthirst is named")
    check(RI.IsNamed(20230) is False, "generated Fury data: Retaliation is named nowhere")
    check(RI.IsNamed(12294) is False, "generated Fury data: Arms' Mortal Strike is not Fury's")
    g.specKey = "MONK_1"
    RI.InvalidateLookup()
    check(RI.IsWideOnly(6343) is False, "no data -> not wide-only")
    check(RI.IsLeftOut(1715, "st") is False, "no data -> not left out")
    check(RI.IsNamed(20230) is True, "no data (retail) -> every spell counts as named")

    for why in bad:
        print("  FAIL", why)
    print("forever engine: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
