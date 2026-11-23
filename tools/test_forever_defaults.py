# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# The real SpellDB.lua + Data/Forever/Defaults.lua, loaded outside the game, on BOTH clients:
# Forever gets its "<CLASS>_F" lists (and the class key where readers index by class), the
# rank-aware static lookup finds any rank, and retail - no WOW_PROJECT_CAMELOT - is left
# exactly as it was. Whether each id is LEARNABLE is checked when the data is generated
# (tools/gen_forever_defaults.py exits 1); this checks how the data is applied.
#
# Run: python tools/test_forever_defaults.py
import sys
from pathlib import Path

from wow_stubs import LuaRuntime

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
    files = ["SpellDB.lua", "Data/InterruptAbilities.lua", "Data/ChanneledSpells.lua",
             "Data/Forever/Defaults.lua", "Data/CCBreakers.lua"]
    if not forever:
        # Retail also loads the real RotationImport and the Forever lists (the TOC lists them
        # for both clients): nothing in them may register there.
        files[1:1] = ["RotationImport.lua", "Data/Forever/Rotations.lua"]
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
    check(sdb.IsDefensiveSpell(8071) is True and sdb.IsOffensiveSpell(8071) is False,
          "Stoneskin is defensive, not an offensive short-lived summon")
    check(8071 in list(sdb.CLASS_DEFENSIVE_DEFAULTS.SHAMAN_F.values()),
          "Stoneskin is in editable Shaman defensive defaults")
    check(1311015 in list(sdb.CLASS_DEFENSIVE_DEFAULTS.PALADIN_F.values()),
          "Templar's Bulwark is in Paladin defensive defaults")
    check(2651 in list(sdb.CLASS_DEFENSIVE_DEFAULTS.PRIEST_F.values()),
          "Elune's Grace is in Priest defensive defaults")
    check(sdb.GetForeverAbilityRole(402927) == "mixed",
          "Victory Rush keeps its offensive and defensive roles")
    check(list(sdb.CLASS_BURST_TRIGGER_DEFAULTS.SHAMAN_F.values()) == [16166, 425336],
          "Shaman burst cues include Lightning Mastery and Rage of the Farseer")
    check(sdb.IsForever() is True, "Forever client detected")
    check(sdb.GetSpecKey()[0] == "WARRIOR_F", "spec key on Forever is CLASS_F")
    gap = sdb.ResolveDefaults(sdb.CLASS_GAPCLOSER_DEFAULTS)
    check(gap is not None and list(gap.values()) == [100, 20252], "warrior gap closers = Charge, Intercept")
    check(list(sdb.CLASS_GAPCLOSER_DEFAULTS.DRUID_F.values()) == [1238122, 1850],
          "druid gap closers = Feral Charge (Bear Form), Dash (Cat Form)")
    check(list(sdb.CLASS_GAPCLOSER_DEFAULTS.ROGUE_F.values()) == [2983], "rogue gap closer = Sprint")
    check(sdb.CLASS_GAPCLOSER_DEFAULTS.PALADIN_F is None and sdb.CLASS_GAPCLOSER_DEFAULTS.SHAMAN_F is None
          and sdb.CLASS_GAPCLOSER_DEFAULTS.HUNTER_F is None,
          "no gap closer data for paladins, shamans or hunters")
    check(list(sdb.ResolveDefaults(sdb.CLASS_DEFENSIVE_DEFAULTS).values())[0] == 12975, "defensives start with Last Stand")
    check(sdb.CLASS_TOPOFF_HEALS.PRIEST[1] == 139, "class-keyed table replaced for readers that index by class")
    check(sdb.CLASS_MAINTAINED_BUFFS.ROGUE is None, "retail rogue poison groups dropped on Forever")
    check(sdb.ROGUE_POISON_CAST_IDS[315584] is None, "derived poison index rebuilt")
    check(sdb.MAINTAINED_BUFF_MEMBERS[7128] is True, "a rank-2 Inner Fire counts as a member")
    check(sdb.PREPARATION_BUFF_MEMBERS[6673] is not None,
          "Battle Shout is missing-only preparation on Forever, not long-buff upkeep")
    check(sdb.RAID_BUFF_SPELLS[6673] is None and sdb.UNIQUE_AURA_SPELLS[6673] is None,
          "Battle Shout off the raid-buff lists that hide it in combat")
    check(sdb.WEAPON_ENCHANT_SPELLS[8235] is True and sdb.WEAPON_ENCHANT_SPELLS[33757] is True,
          "imbue ranks added in place, retail ids kept")
    check(sdb.GetDefenseTier(11958) == 1, "Ice Block tier 1")
    check(sdb.IsTargetDot(772) is True and sdb.GetTargetDotDuration(11574) == 21, "Rend tracked, each rank its own duration")
    check(sdb.IsTargetDot(133) is False, "Fireball is a nuke with a burn rider: never sunk as a DoT")
    check(sdb.IsTrackedTargetAura(770) is True and sdb.IsTrackedTargetAura(1130) is True,
          "kept-up debuffs (Faerie Fire, Hunter's Mark) observed separately from damage")
    check(sdb.IsTargetDot(770) is True and sdb.IsTargetDot(1130) is True,
          "existing maintained-debuff suppression remains available for custom queues")
    for sid in (14914, 15261):
        check(sdb.IsTrackedTargetAura(sid) is True and sdb.IsTargetDot(sid) is False,
              "explicit maintenance does not turn a nuke into an unconditional DoT sink")
    check(sdb.IsTrackedTargetAura(6343) is False and sdb.IsTargetDot(6343) is False,
          "Thunder Clap's slow is no list's upkeep any more: not observed")
    check(sdb.IsSlowingAttack(116) is True and sdb.IsSlowingAttack(133) is False,
          "Frostbolt slows, Fireball does not")
    check(sdb.IsTargetDot(3599) is False, "a totem is not on the target")
    check(sdb.IsFrontalDot(8921) is True and sdb.IsFrontalDot(14914) is True and sdb.IsFrontalDot(772) is False,
          "Moonfire / Holy Fire hit up front; Rend does not")
    check(sdb.IsChanneled(314791) is True, "retail-only channel kept (merge, not replace)")
    check(sdb.StaticLookup(fe.eval("{[679] = 'x'}"), 678) == "x", "any rank finds the rank-1 key")
    defs = list(sdb.ResolveDefaults(sdb.CLASS_DEFENSIVE_DEFAULTS).values())
    check(defs[-2:] == [20594, 1299026], "defensive racials (Stoneform, Shatter Curse) close the list")
    ccb = fe.eval('LibStub("JustAC-CCBreakers")')
    check(ccb.GetBreakers(12)[1259718] == 0 and ccb.GetBreakers(5)[7744] == 0 and ccb.GetBreakers(7)[20589] == 0,
          "Forever CC breaks: Will to Survive (stun), Will of the Forsaken (fear), Escape Artist (root)")

    rt = load(False)
    r = rt.eval('LibStub("JustAC-SpellDB")')
    check(r.IsDefensiveSpell(8071) is False, "Forever Stoneskin category does not leak to retail")
    check(r.IsForever() is False, "retail client detected")
    check(r.IsTrackedTargetAura(14914) is False and r.IsTrackedTargetAura(6343) is False,
          "Forever target-aura observation policy does not register on retail")
    check(r.GetSpecKey()[0] == "WARRIOR_1", "retail spec key unchanged")
    check(r.CLASS_GAPCLOSER_DEFAULTS.WARRIOR_F is None, "no Forever keys on retail")
    check(r.CLASS_BURST_TRIGGER_DEFAULTS.SHAMAN_F is None, "Forever Shaman burst defaults do not leak to retail")
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
    check(rt.eval('LibStub("JustAC-CCBreakers")').GetBreakers(12)[1259718] is None,
          "retail: the retail CC-break table, not Forever's")

    # Interrupt/CC table: Forever retracts a retail id that is another spell there, and adds
    # its own interrupts and crowd control; retail keeps the shared table unchanged.
    check(sdb.GetInterruptAbility(99) is None, "Forever: 99 is Demoralizing Roar, not a crowd control")
    check(sdb.GetInterruptAbility(12809).kind == "cc" and sdb.GetInterruptAbility(72).kind == "interrupt"
          and sdb.IsInterruptTypeSpell(8042) is True, "Forever: Concussion Blow, Shield Bash, Earth Shock")
    check(sdb.IsCrowdControlSpell(12809) is True, "Forever: Concussion Blow is crowd control, not damage")
    for sid, name in ((72, "Shield Bash"), (1238122, "Feral Charge"), (8042, "Earth Shock")):
        check(sdb.GetForeverAbilityRole(sid) == "utility",
              f"Forever: {name} is reserved from automatic damage queues")
    check(sdb.IsDelayedPayoff(603) is True and sdb.IsDelayedPayoff(980) is False,
          "Forever: Bane of Doom pays off only in long fights; Bane of Agony ticks at once")
    for sid, name in ((172, "Corruption"), (589, "Shadow Word: Pain"),
                      (980, "Bane of Agony"), (772, "Rend")):
        check(sdb.IsTargetDot(sid) is True and sdb.IsDelayedPayoff(sid) is False,
              f"Forever: {name} remains an ordinary damage-over-time priority, not a slow-payoff hold")
    check(r.IsDelayedPayoff(603) is False, "retail: no Forever delayed-payoff data")
    # Arms repays one Sunder Armor at once only with a main weapon spender learned (Slam at 20).
    arms = sdb.FOREVER_EARLY_ARMOR_TREES.WARRIOR_F.arms
    check(arms is not None and 1240193 in list(arms.values()), "Arms names its main spenders, Slam among them")
    fe.execute("known = {}; IsPlayerSpell = function(id) return known[id] == true end")
    check(sdb.IsEarlyArmorTree("WARRIOR_F", "arms") is False, "Arms with no main spender: Sunder waits")
    fe.execute("known[1240193] = true")
    check(sdb.IsEarlyArmorTree("WARRIOR_F", "arms") is True, "Arms with Slam: Sunder at once")
    check(sdb.IsEarlyArmorTree("WARRIOR_F", "fury") is False, "Fury is not an early-armor tree")
    fe.execute("IsPlayerSpell = function() error('denied') end")
    check(sdb.IsEarlyArmorTree("WARRIOR_F", "arms") is False, "an unanswerable read holds Sunder")
    # Gear a tree's own attacks need: Shield Slam's shield (item class 4, subclass bit 6).
    gear = sdb.FOREVER_TREE_GEAR
    need = gear is not None and gear.WARRIOR_F is not None and gear.WARRIOR_F.protection
    check(bool(need) and need[1][1] == 4 and need[1][2] == 64, "Forever: the Protection warrior list needs a shield")
    check(gear is not None and gear.WARRIOR_F.arms is None and gear.ROGUE_F is None,
          "Forever: gear every tree of a class shares rules no tree out")
    check(r.FOREVER_TREE_GEAR is None, "retail: no Forever tree gear data")
    for sid, held, why in ((7386, True, "Sunder Armor remains classified as a target armor payoff"),
                           (11597, True, "every Sunder Armor rank"), (770, True, "Faerie Fire"),
                           (704, True, "Curse of Recklessness"), (8647, True, "Expose Armor"),
                           (772, False, "Rend deals its own damage"),
                           (6343, False, "Thunder Clap deals damage"), (6673, False, "Battle Shout buffs you")):
        check(sdb.IsDelayedPayoff(sid) is held, f"Forever slow payoff: {why}")
    check(sdb.LandsAtTarget(100) is True and sdb.LandsAtTarget(20252) is True and sdb.LandsAtTarget(2983) is False,
          "Forever: Charge and Intercept carry the player to the target; Sprint does not")
    check(tuple(sdb.GetEnergize(100)) == (1, 9) and tuple(sdb.GetEnergize(6178)) == (1, 12),
          "Forever: Charge gives 9 rage at rank 1, 12 at rank 2 (data in tenths)")
    check(tuple(sdb.GetEnergize(1752)) == (4, 1) and tuple(sdb.GetEnergize(1833)) == (4, 2),
          "Forever: Sinister Strike builds one combo point, Cheap Shot two")
    check(sdb.GetEnergize(633) is None and sdb.GetEnergize(772) is None,
          "Forever: Lay on Hands' mana goes to its target; Rend gives nothing")
    check(r.LandsAtTarget(100) is False and r.GetEnergize(100) is None, "retail: no Forever look-ahead data")
    for sid, role, why in ((71, "tank", "Defensive Stance carries the effectively-tank aura"),
                           (5487, "tank", "Bear Form"), (25780, "tank", "Righteous Fury"),
                           (355, "taunt", "Taunt"), (6795, "taunt", "Growl"), (694, "taunt", "Mocking Blow"),
                           (1161, "taunt", "Challenging Shout"),
                           (586, "drop", "Fade"), (9578, "drop", "Fade rank 2"), (1966, "drop", "Feint"),
                           (8998, "drop", "Cower"), (5384, "drop", "Feign Death"),
                           (7386, "boost", "Sunder Armor adds threat"),
                           (78, None, "Heroic Strike has no threat effect in the data"),
                           (2565, None, "Shield Block is mitigation, not threat")):
        check(sdb.GetThreatRole(sid) == role, f"Forever threat role: {why} ({sdb.GetThreatRole(sid)})")
    check(r.GetThreatRole(355) is None, "retail: no Forever threat data")
    check(sdb.GainsOverTime(2687) is True and sdb.GainsOverTime(5229) is True,
          "Forever: Bloodrage and Enrage keep paying rage after the cast")
    check(sdb.GainsOverTime(100) is False and sdb.GainsOverTime(18499) is False,
          "Forever: Charge pays at once; Berserker Rage is no gain over time")
    check(r.GainsOverTime(2687) is False, "retail: no Forever gain-over-time data")
    check(sdb.GetSelfAuraSeconds(2687) == 10 and sdb.GetSelfAuraSeconds(1719) == 15,
          "Forever: Bloodrage's triggered rage aura lasts 10s; Recklessness 15s")
    check(sdb.GetSelfAuraSeconds(78) is None and sdb.GetSelfAuraSeconds(71) is None,
          "Forever: Heroic Strike puts no aura on you; a stance has no duration")
    check(r.GetSelfAuraSeconds(2687) is None, "retail: no Forever self-aura data")
    check(r.GetInterruptAbility(99).kind == "cc" and r.GetInterruptAbility(12809) is None,
          "retail: Incapacitating Roar kept, no Forever-only entries")

    for why in bad:
        print("  FAIL", why)
    print("forever defaults: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
