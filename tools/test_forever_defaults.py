# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The real SpellDB.lua + Data/ForeverDefaults.lua, loaded outside the game, on BOTH clients:
# Forever gets its "<CLASS>_F" lists (and the class key where readers index by class), the
# rank-aware static lookup finds any rank, and retail - no WOW_PROJECT_CAMELOT - is left
# exactly as it was. Whether each id is LEARNABLE is checked when the data is generated
# (tools/gen_forever_defaults.py exits 1); this checks how the data is applied.
#
# Run: python tools/test_forever_defaults.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = """
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Spell = {}
C_SpecializationInfo = { GetSpecialization = function() return 1 end }
function UnitClass() return "Warrior", "WARRIOR" end
GetTime = function() return 0 end
"""


def load(forever):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    if forever:
        lua.execute("WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = 18")
        # Rank chains as RotationImport would hold them (Holy Strike 679 -> 678 rank 2).
        lua.execute("""LibStub:NewLibrary("JustAC-RotationImport").RankBase =
            function(id) if id == 678 then return 679 end return id end""")
    files = ["SpellDB.lua", "Data/ChanneledSpells.lua", "Data/ForeverDefaults.lua"]
    if not forever:
        # Retail also loads the real RotationImport and the Forever lists (the TOC lists them
        # for both clients): nothing in them may register there.
        files[1:1] = ["RotationImport.lua", "Data/ForeverRotations.lua"]
    for f in files:
        lua.execute((ROOT / f).read_text(encoding="utf-8"))
    return lua


def main():
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    fe = load(True)
    sdb = fe.eval('LibStub("JustAC-SpellDB")')
    check(sdb.IsForever() is True, "Forever client detected")
    check(sdb.GetSpecKey()[0] == "WARRIOR_F", "spec key on Forever is CLASS_F")
    gap = sdb.ResolveDefaults(sdb.CLASS_GAPCLOSER_DEFAULTS)
    check(gap is not None and list(gap.values()) == [100, 20252], "warrior gap closers = Charge, Intercept")
    check(list(sdb.ResolveDefaults(sdb.CLASS_DEFENSIVE_DEFAULTS).values())[0] == 12975, "defensives start with Last Stand")
    check(sdb.CLASS_TOPOFF_HEALS.PRIEST[1] == 139, "class-keyed table replaced for readers that index by class")
    check(sdb.CLASS_MAINTAINED_BUFFS.ROGUE is None, "retail rogue poison groups dropped on Forever")
    check(sdb.ROGUE_POISON_CAST_IDS[315584] is None, "derived poison index rebuilt")
    check(sdb.MAINTAINED_BUFF_MEMBERS[7128] is True, "a rank-2 Inner Fire counts as a member")
    check(sdb.CLASS_MAINTAINED_BUFFS.WARRIOR is None and sdb.MAINTAINED_BUFF_MEMBERS[6673] is None,
          "Battle Shout is no between-pull upkeep buff on Forever")
    check(sdb.RAID_BUFF_SPELLS[6673] is None and sdb.UNIQUE_AURA_SPELLS[6673] is None,
          "Battle Shout off the raid-buff lists that hide it in combat")
    check(sdb.WEAPON_ENCHANT_SPELLS[8235] is True and sdb.WEAPON_ENCHANT_SPELLS[33757] is True,
          "imbue ranks added in place, retail ids kept")
    check(sdb.GetDefenseTier(11958) == 1, "Ice Block tier 1")
    check(sdb.IsTargetDot(772) is True and sdb.GetTargetDotDuration(11574) == 21, "Rend tracked, each rank its own duration")
    check(sdb.IsTargetDot(133) is False, "Fireball is a nuke with a burn rider: never sunk as a DoT")
    check(sdb.IsTargetDot(770) is True and sdb.IsTargetDot(1130) is True,
          "kept-up debuffs (Faerie Fire, Hunter's Mark) tracked like DoTs")
    check(sdb.IsTargetDot(3599) is False, "a totem is not on the target")
    check(sdb.IsFrontalDot(8921) is True and sdb.IsFrontalDot(14914) is True and sdb.IsFrontalDot(772) is False,
          "Moonfire / Holy Fire hit up front; Rend does not")
    check(sdb.IsChanneled(314791) is True, "retail-only channel kept (merge, not replace)")
    check(sdb.StaticLookup(fe.eval("{[679] = 'x'}"), 678) == "x", "any rank finds the rank-1 key")

    rt = load(False)
    r = rt.eval('LibStub("JustAC-SpellDB")')
    check(r.IsForever() is False, "retail client detected")
    check(r.GetSpecKey()[0] == "WARRIOR_1", "retail spec key unchanged")
    check(r.CLASS_GAPCLOSER_DEFAULTS.WARRIOR_F is None, "no Forever keys on retail")
    check(r.CLASS_TOPOFF_HEALS.PRIEST[1] == 2061, "retail class lists untouched")
    check(r.ROGUE_POISON_CAST_IDS[315584] is True, "retail poison index intact")
    check(r.RAID_BUFF_SPELLS[6673] is True and r.CLASS_MAINTAINED_BUFFS.WARRIOR is not None,
          "retail Battle Shout still an upkeep raid buff")
    # Nothing Forever leaks into retail.
    ri = rt.eval('LibStub("JustAC-RotationImport")')
    check(ri.RankChain(772) is None and ri.RankBase(6546) == 6546 and ri.RankBase(28272) == 28272,
          "retail: no Forever rank chains (Rend, Polymorph: Pig resolve as themselves)")
    check(r.IsTargetDot(133) is False and r.IsFrontalDot(8921) is False and next(iter(r.NEXT_SWING_SPELLS), None) is None,
          "retail: no Forever DoT / frontal / next-swing data")
    check(r.StaticLookup(rt.eval("{[772] = 'x'}"), 6546) is None, "retail: a Forever rank id finds nothing")

    for why in bad:
        print("  FAIL", why)
    print("forever defaults: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
