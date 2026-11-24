# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Run JustAC's WoW Forever priority lists through the Forever simulator at levelling levels.

Offline analysis only. It reads Data/Forever/Rotations.lua and writes nothing inside the
addon; it never changes a list, a generator or runtime Lua.

What it does
  1. Converts one generated list (class, tree, context) into the simulator's priority-list
     JSON (proto/apl.proto), gate by gate, and prints which gates converted exactly, which
     were approximated and which could not be expressed. Nothing is dropped silently.
  2. Builds a levelling character (level, talents, weapon) and a set of targets sized by
     health, so short fights are represented.
  3. Runs every list ("arm") on every scenario with the same seeds and prints kill time
     and damage per second with 95% confidence intervals, plus casts per fight per ability.

What it needs (none of it is vendored here)
  - A checkout of the WoW Forever simulator (MIT, https://github.com/gunba/wow-forever-sim)
    with its protocol code generated, and its command-line tool built:
        protoc "--proto_path=proto" "--go_out=sim/core" proto/*.proto
        go build -tags=with_db -o wowsimcli.exe ./cmd/wowsimcli
    Built into the checkout's own folder (its .gitignore expects it there), the bench finds it
    without --cli. Keep it out of temporary folders: a cleanup there removes the only copy.
  - Python 3.9+, standard library only.

Run
    python tools/forever_sim_bench.py --sim <simulator checkout>
    python tools/forever_sim_bench.py --sim ... --class warrior --tree arms \
        --levels 20,40 --gear behind,average,lucky --batches 10 --iterations 1000 --out <result.md> --keep <dir for requests/results>
    python tools/forever_sim_bench.py --sim ... --convert-only      (print the conversion)

Arms compared
  justac    the generated list for --tree / --context, converted
  sim       the simulator's own preset for the tree (ui/<class>/apls/<file>)
  source    the vendored MythicSim preset the generated list was adapted from
            (tools/forever-apl-src/presets/...), when the simulator can parse it
  justac+cooldowns   the list plus the class's major cooldowns it does not name, pressed when
            the queue cues them (--no-cooldown-arm leaves it out)
  source-new         optional (--new-source DIR): the tree's source preset from a newer upstream folder
  list-<tree>        optional (--other-lists): this tree's character following another tree's list
  draft              optional (--draft FILE): the same tree read from a proposed copy of the lists
  justac-without-<ids>   optional (--without): the generated list minus some entries
All arms run without their own pre-pull actions: a levelling pull has no countdown. Every arm
instead gets the class's levelling pre-pull casts (PREPULL): a rogue's Stealth, a priest's Power
Word: Shield (a local simulator addition; absorbed hits push no cast back).

Pull model (on by default, --no-pull-model turns it off; needs the simulator's local change): a
fight starts when the player's first attack lands. Until then the target does not attack, so a
caster's opening cast is free, as in a real pull; the target then needs distance / 7 yards a
second to reach a caster before its first swing, and a pet sent from range needs the same to
reach the target. Kill time runs from that first landing, as a kill timed in game does. Checked
against kills logged in game (2026-11-23): six level 15 hunter fights with a boar ran 11 to 15 s
with 251 hunter and 105 pet damage; the model gives 12.0 s, 264 and 93 (before it: 10.9 s, 237
and 126).

Assumptions (each is a modelling choice, not a measured fact; see ASSUMPTIONS below and the
printed report)
  - Character: the simulator's base stats and trained ranks for the level. Talents are the
    simulator's own preset build for the tree, cut down to the points the level has, in row
    order, taking the tree's last talent as soon as its row opens (--talents names a build).
  - Stance and weapons follow how the tree is played (Protection: Defensive Stance, one-hand
    weapon and shield); --stance and --loadout override them. The report lists every entry
    the setup's stance or equipment can never use, from the client's own spell data.
  - Packs: --mobs N fights N identical targets for --pull-seconds and reports damage per
    second over that pull instead of a kill time. Damage taken is reported per fight.
  - Runtime rules: the queue's rules outside the lists are applied per scenario (RuntimeRules);
    --no-runtime-rules runs the lists alone.
  - Fight length: --calibrate <SavedVariables> reads the kills JustAC recorded in game
    (`/jac inspect mobprofile`), simulates each one and scales target health so simulated kill
    times match the measured ones (--health-scale sets the factor by hand).
  - Gear: a named setup chosen with --gear (bare, behind, average, lucky, or file:<path>
    for an explicit character). Generated setups pick real client items by required level,
    quality and slot, taking the MEDIAN candidate by a simple stat score, never the best.
    The rules and the gaps are written next to GEAR_SETUPS and ItemPool below, and every
    report lists the items a setup resolved to.
  - Targets: health, armour and melee damage of the client's expected creature for the
    target level (ExpectedStat, as shipped in the simulator). "Elite" multiplies health and
    damage by stated factors that are NOT measured.
  - The simulator's combat tables are Classic's and its Forever rules are partly
    provisional. Use the output to compare two orderings under the same assumptions, never
    as absolute damage numbers.
  - Local simulator changes the bench relies on (tools/forever-sim-patches): the fight's
    real length, and the wand for priests and mages. What the model still cannot be trusted
    for is listed in Documentation/DEV_TOOLING.md ("What the simulator cannot be trusted for").

Classes (every class and tree in Data/Forever/Rotations.lua has an entry in CLASSES)
  - Each tree runs on the simulator spec that plays it, with its own weapons, armour and
    engagement. A tree the simulator has no spec for (restoration druid and shaman, holy
    paladin, discipline and holy priest) runs its damage list on the class's damage spec
    with the healer build; its "sim" arm is that damage spec's preset.
  - Level brackets: upstream, the simulator defines every rogue attack, the feral druid's
    Shred, Maul and Swipe, the hunter's melee attacks and pet abilities and the warlock's
    demons only at levels 25, 40, 50 and 60. The local changes (tools/forever-sim-patches) give
    them the rank the level has, from the client spell tables, so every tree runs at every
    level. What is still bracket-only (rogue poisons, Mutilate, shaman imbues) is listed in
    each report; tools/forever_sim_sweep.py shows what a level is missing.
  - Pets: a hunter fights beside a cat (2.0 s swing) from level 10 and a warlock beside an imp
    unless --pet says otherwise (assumed defaults). With the local changes the hunter pet's and
    the demons' attributes follow the Classic server table by level (the simulator's own level
    rows are rows of it), and the hunter pet's base hit is linear in level as in Classic. Whether
    WoW Forever changed those curves is not measured, and the pet is about half of a hunter's
    damage. The hunter shoots from 30 yards and is never hit; vendor ammunition by level.
  - Spec options the lists do not cast are the same for every arm and printed in the report:
    no mage or priest armour spell, no rogue poisons, the enhancement weapon imbue by level.
  - A simulator run that never finishes (a preset that loops on a free instant action at a
    level it was not written for) is stopped after --run-timeout seconds, reported failed, and
    that arm is skipped for the rest of the level.
  - Ranks: the simulator's classes register spell ranks in different ways. Most give every rank
    its own id with a required level (rank_by_chain: the rank is chosen per level, from the
    simulator's own tables or the client's SpellLevels); the warrior keeps one id per spell at
    every level and must not be rewritten. The level 60 book ranks (BOOK_RANKS) are left out of
    the simulator and are never chosen.
  - Talents: a "known" gate that names a talent is answered from the build being run at that
    level, since the simulator's spell book does not hold talents.
  - Every report lists what the simulator defines only at levels 25, 40, 50 and 60 for the
    class when a run is at another level, and per-tree caveats where a result cannot be judged.
  - The simulator uses half the machine's processor threads at the lowest priority (--threads,
    --normal-priority). Run one bench at a time.
"""
import argparse
import csv
import functools
import glob
import json
import math
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROTATIONS = os.path.join(ROOT, "Data", "Forever", "Rotations.lua")
PRESETS = os.path.join(ROOT, "tools", "forever-apl-src", "presets")
SPELL_QUEUE = os.path.join(ROOT, "SpellQueue.lua")

# ---------------------------------------------------------------------------------------
# Per-class knowledge. Everything class-specific lives here; the rest is generic.
#   spec        the Player oneof field and its options
#   race        a race whose Forever racials are passive in the simulator, so a preset's
#               "use other cooldowns" line cannot give one arm a racial the list lacks
#   trees       tree -> simulator preset (relative to the simulator checkout), the vendored
#               source preset (relative to tools/forever-apl-src/presets), the simulator's
#               talent string for the tree, and which tree index the build fills first
#   class_id    ChrClasses id, for the client's AllowableClass mask
#   weapon, armor, stat_weights   what the gear setups may pick (see ItemPool)
#   engagement  how the class meets a solo target. melee: in front, hit from the start.
#               Ranged and kiting classes need other profiles (see ENGAGEMENTS).
#   actions     overrides for list ids the automatic match cannot settle:
#               JustAC rank-1 id -> {"id": simulator action id, "tag": n, "dot": bool}
#               or None with a reason in `unmodelled`.
#   unmodelled  JustAC rank-1 id -> why the simulator cannot cast it
# ---------------------------------------------------------------------------------------
CLASSES = {
    "warrior": {
        "proto_class": "ClassWarrior",
        "spec": ("warrior", {"options": {"stance": "WarriorStanceBattle"}}),
        "race": "RaceHuman",   # Forever human: passive racials only in the simulator
        "engagement": "melee",
        "class_id": 1,
        # Client item class 2 (weapon): inventory type 17 two-hand; subclasses axe, mace, polearm, sword.
        "weapon": {"inv": (17,), "subclasses": (1, 5, 6, 8)},
        # Armour subclasses worn while levelling: leather and mail, plate from level 40.
        "armor": lambda level: (2, 3, 4) if level >= 40 else (2, 3),
        # Only used to order candidates so the MEDIAN one can be taken (strength, agility,
        # stamina, attack power by simulator stat index). Not a best-in-slot search.
        "stat_weights": {0: 1.0, 1: 0.6, 2: 0.2, 17: 0.5},
        # The random suffix ASSUMED on an uncommon armour piece that has no stats of its own
        # (simulator stat indexes: strength and stamina). Which suffixes an item can really
        # roll is in client tables this project does not have.
        "suffix": {"name": "of the Bear", "stats": (0, 2)},
        "trees": {
            "arms": {"sim_preset": "ui/warrior/apls/forever_arms.apl.json",
                     "source_preset": "warrior/dps/arms.apl.json",
                     "talents": "20305213132515201-3505-2", "main_tree": 0,
                     "stance": "Battle", "loadout": "2h"},
            # Fury's list carries its own stance swaps; it starts in Battle Stance.
            "fury": {"sim_preset": "ui/warrior/apls/forever_fury_2h.apl.json",
                     "source_preset": "warrior/dps/dps_reck.apl.json",
                     "talents": "20305203032-45050020152010501", "main_tree": 1,
                     "stance": "Battle", "loadout": "2h"},
            # Protection is played in Defensive Stance with a shield: Revenge, Shield Slam and
            # Shield Block need them (2026-11-18: Battle Stance with a two-hander hid Revenge).
            "protection": {"sim_preset": "ui/tank_warrior/apls/forever_protection.apl.json",
                           "source_preset": "warrior/protection/protection.apl.json",
                           "talents": "35-0501-251333120230021351", "main_tree": 2,
                           "stance": "Defensive", "loadout": "shield"},
        },
        "actions": {
            78: {"id": 11567, "tag": 1},     # Heroic Strike: the queue action, not the swing
            845: {"id": 20569, "tag": 1},    # Cleave: likewise
            772: {"id": 11574, "dot": True},  # Rend
            6572: {"id": 11601},             # Revenge (rank 6 is a raid book rank)
            23922: {"id": 23925},            # Shield Slam (the simulator names its top rank)
            6673: {"id": 11551},             # Battle Shout (rank 7 is a raid book rank)
            6343: {"id": 11581},             # Thunder Clap (the simulator names its top rank)
            # Demoralizing Shout: one action at the top rank's id, its trained rank inside; its
            # debuff keeps that id too (sim/warrior/demoralizing_shout.go).
            1160: {"id": 11556},
        },
        "unmodelled": {
            402927: "Victory Rush is not implemented in the simulator",
            1329555: "Reckless Swings is not implemented in the simulator",
            1259813: "Eureka! (racial) is not implemented in the simulator",
            20572: "Blood Fury is a racial of a race this character is not",
        },
    },
    "warlock": {
        "proto_class": "ClassWarlock",
        # No demon by default: the simulator only has demon stats for owner levels 25, 40, 50
        # and 60, and at any other level the demon has none and never acts. --pet names one for
        # those levels. No armour spell and no weapon stone: the same for every arm.
        "spec": ("warlock", {"options": {"summon": "NoSummon"}}),
        "race": "RaceHuman",
        "engagement": "caster",
        "class_id": 9,
        # Client item class 2: two-hand staff (subclass 10).
        "weapon": {"inv": (17,), "subclasses": (10,)},
        # A wand in the ranged slot. Needs a simulator build with the local wand attack
        # (sim/core/wand.go, not upstream); without it the wand is only a stat stick.
        "wand": True,
        "armor": lambda level: (1,),
        # Intellect, stamina, spirit, spell power (simulator stat indexes), for the median pick.
        "stat_weights": {3: 1.0, 2: 0.6, 4: 0.4, 5: 1.0, 11: 1.0, 7: 0.5},
        "suffix": {"name": "of the Eagle", "stats": (2, 3)},
        "trees": {
            "affliction": {"sim_preset": "ui/warlock/apls/forever_affliction.apl.json",
                           "source_preset": "warlock/dps/affliction.apl.json",
                           "talents": "2550002003520015--0550305003", "main_tree": 0},
            "demonology": {"sim_preset": "ui/warlock/apls/forever_pact.apl.json",
                           "source_preset": "warlock/dps/demonic_pact.apl.json",
                           "talents": "011-0005003231220301351-0550005003", "main_tree": 1,
                           "caveats": ["This build plays around its demon, and the default here is no demon (the "
                                       "simulator's demons only act at owner levels 25, 40, 50 and 60). Without one "
                                       "the pet's brand never lands, so Searing Pain is cast over and over: run it "
                                       "with --pet at one of those levels."]},
            "destruction": {"sim_preset": "ui/warlock/apls/forever_shadow_and_flame.apl.json",
                            "source_preset": "warlock/dps/destruction_conflag.apl.json",
                            "talents": "25500000035--055030510310035", "main_tree": 2},
        },
        "actions": {},
        "unmodelled": {
            5019: "Shoot is not a cast here: with a wand equipped the local wand attack fires by itself whenever "
                  "the character is neither casting nor in a global cooldown",
            1259813: "Eureka! (racial) is not implemented in the simulator",
            1259821: "Eureka! (racial) is not implemented in the simulator",
            20572: "Blood Fury is a racial of a race this character is not",
        },
    },
}

# Shared pieces of the class table below (simulator stat indexes: 0 strength, 1 agility,
# 2 stamina, 3 intellect, 4 spirit, 5 spell power, 6-11 school power, 17 attack power,
# 27 ranged attack power). Weights only order candidates so the MEDIAN one can be taken.
CASTER_WEIGHTS = {3: 1.0, 2: 0.6, 4: 0.4, 5: 1.0, 6: 0.5, 7: 0.5, 8: 0.5, 9: 0.5, 10: 0.5, 11: 0.5}
MELEE_WEIGHTS = {0: 1.0, 1: 0.6, 2: 0.2, 17: 0.5}
AGILITY_WEIGHTS = {1: 1.0, 0: 0.5, 2: 0.2, 17: 0.5, 27: 0.5}
EAGLE = {"name": "of the Eagle", "stats": (2, 3)}
BEAR = {"name": "of the Bear", "stats": (0, 2)}
MONKEY = {"name": "of the Monkey", "stats": (1, 2)}
STAFF = {"inv": (17,), "subclasses": (10,)}
RACIALS = {
    1259813: "Eureka! (racial) is not implemented in the simulator",
    1259821: "Eureka! (racial) is not implemented in the simulator",
    20572: "Blood Fury is a racial of a race this character is not",
}
# The simulator defines some classes' core attacks only at these levels (a map indexed by the
# character's level: every rogue builder and finisher, the feral druid's Shred, Maul and Swipe,
# the hunter's melee attacks). At any other level they do not exist and a run would be auto
# attacks alone, so such a tree is refused outside them.
BRACKET_LEVELS = (25, 40, 50, 60)
WAND_SHOOT = ("Shoot is not a cast here: with a wand equipped the local wand attack fires by itself whenever "
              "the character is neither casting nor in a global cooldown")


def hunter_spec(level):
    """Vendor ammunition for the level, from the simulator's own list (client ItemSparse: Razor
    Arrow requires 25, Jagged Arrow 40; the client's level 1 and 10 arrows are not in the
    simulator's list, so below 25 there is none)."""
    ammo = "JaggedArrow" if level >= 40 else "RazorArrow" if level >= 25 else "AmmoNone"
    return {"ammo": ammo}


def enhancement_spec(level):
    """The weapon imbue a levelling shaman has (Rockbiter from 1 and Windfury from 30 per the
    simulator's rank tables; Flametongue from 10 ASSUMED as in Classic). JustAC keeps it up
    outside the damage list. The simulator ranks imbues only at levels 25, 40, 50 and 60."""
    imbue = "WindfuryImbue" if level >= 30 else "FlametongueImbue" if level >= 10 else "RockbiterImbue"
    return {"mainHandImbue": imbue}


CLASSES.update({
    "druid": {
        "proto_class": "ClassDruid",
        "spec": ("balanceDruid", {"options": {}}),
        "race": "RaceNightElf",
        "engagement": "caster",
        "class_id": 11,
        "ui": ["balance_druid", "feral_druid", "feral_tank_druid"],
        "rank_by_chain": True,
        "weapon": {"inv": (17,), "subclasses": (5, 10)},   # two-hand mace or staff
        "armor": lambda level: (1, 2),
        "stat_weights": CASTER_WEIGHTS,
        "suffix": EAGLE,
        # SpellShapeshift form bits. The simulator's feral specs take their form themselves.
        "forms": {"Cat": 1, "Bear": 5, "Dire Bear": 8, "Moonkin": 31},
        "form_spells": {768: "Cat", 5487: "Bear", 9634: "Dire Bear", 24858: "Moonkin"},
        "form_word": "Form",
        "trees": {
            "balance": {"sim_preset": "ui/balance_druid/apls/launch.apl.json",
                        "source_preset": "druid/balance/launch.apl.json",
                        "talents": "533222011550135--505003", "main_tree": 0},
            "feral": {"sim_preset": "ui/feral_druid/apls/feral.apl.json",
                      "source_preset": "druid/feralcat/default.apl.json",
                      "talents": "05002-55000032021032212051-055", "main_tree": 1, "form": "Cat",
                      "caveats": ["The simulator's Claw is the level 60 rank at every level (a flat 115 bonus "
                                  "damage, sim/druid/claw.go), so Claw is overstated below level 58. From the "
                                  "front, where Shred cannot be used, the list leans on Claw: its lead over the "
                                  "presets here is not evidence."],
                      "spec": ("feralDruid", {"options": {}}), "engagement": "melee",
                      "stat_weights": AGILITY_WEIGHTS, "suffix": {"name": "of the Tiger", "stats": (0, 1)}},
            "feral_bear": {"sim_preset": "ui/feral_tank_druid/apls/forever_bear.apl.json",
                           "source_preset": "druid/feralbear/default.apl.json",
                           "talents": "01-50022332120132012551-055", "main_tree": 1, "form": "Bear",
                           "spec": ("feralTankDruid", {"options": {}}), "engagement": "melee",
                           "stat_weights": MELEE_WEIGHTS, "suffix": BEAR},
            # The simulator has no restoration spec: the tree's damage list runs on the balance
            # spec with the restoration build, against the balance preset.
            "restoration": {"sim_preset": "ui/balance_druid/apls/launch.apl.json",
                            "talents": "05302--5053035153113051", "main_tree": 2},
        },
        "actions": {
            6807: {"id": 9881, "tag": 1},   # Maul: the queue action, not the swing
        },
        "unmodelled": dict(RACIALS),
    },
    "hunter": {
        "proto_class": "ClassHunter",
        # No pet by default: the simulator's hunter pet has one fixed set of stats (a level 60
        # pet) at every owner level. --pet names a family for a level 60 run.
        # petAttackSpeed: a 2.0 s swing, the ordinary Classic pet (ASSUMED for the default cat). Left
        # out, the simulator's option reads as its first value, a 1.0 s swing (Broken Tooth).
        "spec": ("hunter", {"options": {"petType": "PetNone", "petUptime": 1, "petAttackSpeed": "Two"}}),
        "spec_for_level": hunter_spec,
        "pets": {"option": "petType", "none": "PetNone",
                 "names": ["Cat", "WindSerpent", "Wolf", "Bat", "Bear", "Owl", "Boar", "CarrionBird", "Crab",
                           "Crocolisk", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle"],
                 "note": "the pet's body scales linearly with level from the simulator's level 60 values (local change, "
                         "an assumption)"},
        "race": "RaceNightElf",
        "engagement": "ranged",
        "class_id": 3,
        "rank_by_chain": True,
        # The simulator tags a Hunter's Mark aura with its caster (player index + 1,
        # sim/core/debuffs.go): without the tag the mark reads as never on the target.
        "aura_tags": {1130: 1},
        "ui": ["hunter"],
        # A two-hand axe, polearm, sword or staff as the melee weapon, and a bow, gun or crossbow.
        "weapon": {"inv": (17,), "subclasses": (1, 6, 8, 10)},
        "ranged": {"subclasses": (2, 3, 18), "note": "bow, gun or crossbow"},
        "armor": lambda level: (2, 3) if level >= 40 else (2,),
        "stat_weights": AGILITY_WEIGHTS,
        "suffix": MONKEY,
        "trees": {
            "beast_mastery": {"sim_preset": "ui/hunter/apls/beast_mastery.apl.json",
                              "source_preset": "hunter/dps/bm.apl.json",
                              "talents": "5320001505101251-00532500005", "main_tree": 0},
            "marksmanship": {"sim_preset": "ui/hunter/apls/p1.apl.json",
                             "source_preset": "hunter/dps/mm.apl.json",
                             "talents": "502-0053552001523051-50002", "main_tree": 1},
            # The survival list comes from the melee preset: it fights in melee range.
            "survival": {"sim_preset": "ui/hunter/apls/survival.apl.json",
                         "source_preset": "hunter/dps/sv_melee.apl.json",
                         "talents": "502-005205-500230230050122151", "main_tree": 2, "engagement": "melee",
                         "caveats": ["The list comes from the melee preset and runs in melee range, where no shot "
                                     "can be fired; the simulator's own preset steps out and shoots, so the 'sim' "
                                     "arm is a different way to play, not a like-for-like list. Compare with "
                                     "'source'."]},
        },
        "actions": {
            2973: {"id": 14266, "tag": 3},   # Raptor Strike: the queue action, not the swing
        },
        "unmodelled": dict(RACIALS),
    },
    "mage": {
        "proto_class": "ClassMage",
        "spec": ("mage", {"options": {"armor": "NoArmor"}}),
        "race": "RaceHuman",
        "engagement": "caster",
        "class_id": 8,
        "rank_by_chain": True,
        # Fire Vulnerability (the Improved Scorch debuff): the simulator keeps its stacks in an
        # aura on the mage, id 12873 (sim/mage/talents.go), not on the target.
        "aura_alias": {22959: 12873},
        "self_auras": (12873,),
        "ui": ["mage"],
        "weapon": STAFF,
        "wand": True,
        "armor": lambda level: (1,),
        "stat_weights": CASTER_WEIGHTS,
        "suffix": EAGLE,
        "trees": {
            "arcane": {"sim_preset": "ui/mage/apls/forever_arcane.apl.json",
                       "source_preset": "mage/dps/arcane.apl.json",
                       "talents": "0502205003100311531-03-05350003", "main_tree": 0},
            "fire": {"sim_preset": "ui/mage/apls/forever_fire.apl.json",
                     "source_preset": "mage/dps/fire.apl.json",
                     "talents": "-03552020130135131-05350003", "main_tree": 1},
            "frost": {"sim_preset": "ui/mage/apls/forever_frost.apl.json",
                      "source_preset": "mage/dps/frost.apl.json",
                      "talents": "0500205-03-253520330100301251", "main_tree": 2},
        },
        "actions": {},
        "unmodelled": dict(list(RACIALS.items()) + [(5019, WAND_SHOOT)]),
    },
    "paladin": {
        "proto_class": "ClassPaladin",
        "spec": ("retributionPaladin", {"options": {}}),
        "race": "RaceHuman",
        "engagement": "melee",
        "class_id": 2,
        "rank_by_chain": True,
        "ui": ["retribution_paladin", "protection_paladin"],
        # Seal of Fury's ranks and levels (sim/paladin/sof.go, a struct table the rank reader skips).
        "rank_tables": [([1311649, 1311656, 20163, 20419, 20421, 20422, 20423], [10, 18, 25, 34, 42, 50, 58])],
        "weapon": {"inv": (17,), "subclasses": (1, 5, 6, 8)},
        "armor": lambda level: (2, 3, 4) if level >= 40 else (2, 3),
        "stat_weights": dict(list(MELEE_WEIGHTS.items()) + [(3, 0.3)]),
        "suffix": BEAR,
        "trees": {
            # The simulator has no holy spec: the tree's damage list runs on the retribution spec
            # with the holy build, against the spell-damage (shockadin) preset.
            "holy": {"sim_preset": "ui/retribution_paladin/apls/shockadin.apl.json",
                     "talents": "05323213225121051-55021", "main_tree": 0, "loadout": "shield"},
            "protection": {"sim_preset": "ui/protection_paladin/apls/forever_protection.apl.json",
                           "source_preset": "paladin/protection/p5.apl.json",
                           "talents": "-5520513321301551-15102", "main_tree": 1, "loadout": "shield",
                           # Righteous Fury up, as every Protection guide keeps it (its threat; left
                           # out, the bench's threat was the damage's alone).
                           "spec": ("protectionPaladin", {"options": {"righteousFury": True}})},
            "retribution": {"sim_preset": "ui/retribution_paladin/apls/basic_ret.apl.json",
                            "source_preset": "paladin/retribution/default.apl.json",
                            "talents": "55003003-2-05225331001330311", "main_tree": 2, "loadout": "2h"},
        },
        "actions": {},
        "unmodelled": dict(RACIALS),
    },
    "priest": {
        "proto_class": "ClassPriest",
        "spec": ("smitePriest", {"options": {"armor": "NoArmor"}}),
        "race": "RaceHuman",
        "engagement": "caster",
        "class_id": 5,
        "rank_by_chain": True,
        "ui": ["smite_priest", "shadow_priest"],
        "weapon": STAFF,
        "wand": True,
        "armor": lambda level: (1,),
        "stat_weights": CASTER_WEIGHTS,
        "suffix": EAGLE,
        "trees": {
            # Discipline and holy lists are the smite list: they run on the smite spec with the
            # simulator's healer builds, the talents a healer brings to solo play.
            "discipline": {"sim_preset": "ui/smite_priest/apls/launch.apl.json",
                           "source_preset": "priest/dps/smite.apl.json",
                           "talents": "005205031332011531-03505003", "main_tree": 0},
            "holy": {"sim_preset": "ui/smite_priest/apls/launch.apl.json",
                     "source_preset": "priest/dps/smite.apl.json",
                     "talents": "00520302133-2350510323000053", "main_tree": 1},
            "shadow": {"sim_preset": "ui/shadow_priest/apls/p1.apl.json",
                       "source_preset": "priest/dps/shadow.apl.json",
                       "talents": "02530003101--55052201201302251", "main_tree": 2,
                       "spec": ("shadowPriest", {"options": {"armor": "NoArmor"}})},
        },
        "actions": {},
        "unmodelled": dict(list(RACIALS.items()) + [(5019, WAND_SHOOT)]),
    },
    "rogue": {
        "proto_class": "ClassRogue",
        # No poisons: the same for every arm.
        "spec": ("rogue", {"options": {}}),
        "race": "RaceHuman",
        "engagement": "melee",
        "class_id": 4,
        "rank_by_chain": True,
        "ui": ["rogue"],
        "weapon": {"inv": (13, 21), "subclasses": (4, 7, 13, 15)},
        "armor": lambda level: (2,),
        "stat_weights": AGILITY_WEIGHTS,
        "suffix": MONKEY,
        "forms": {"Stealth": 30},
        "form_spells": {1784: "Stealth"},
        # A levelling rogue opens nearly every fight from Stealth: every arm casts it a second before
        # the pull (the simulator's own Stealth spell and aura), so the lists' openers can fire.
        "stealth": {"spell": 1784, "aura": 1787},   # 1787: FIXED_IDS (filled from here below)
        "form_word": "",
        "trees": {
            "assassination": {"sim_preset": "ui/rogue/apls/forever_mutilate.apl.json",
                              "source_preset": "rogue/dps/forever_mutilate.apl.json",
                              "talents": "02532010531201051-225303000005", "main_tree": 0, "loadout": "daggers"},
            "combat": {"sim_preset": "ui/rogue/apls/combat_sinister_strike.apl.json",
                       "source_preset": "rogue/dps/combat_sinister_strike.apl.json",
                       "talents": "1053231-22530300001515231-012", "main_tree": 1, "loadout": "dw"},
            "subtlety": {"sim_preset": "ui/rogue/apls/forever_hemorrhage.apl.json",
                         "source_preset": "rogue/dps/forever_hemorrhage.apl.json",
                         "talents": "005303103005--3320203310013211501", "main_tree": 2, "loadout": "daggers"},
        },
        "actions": {},
        "unmodelled": dict(RACIALS),
    },
    "shaman": {
        "proto_class": "ClassShaman",
        "spec": ("elementalShaman", {"options": {}}),
        "race": "RaceTauren",
        "engagement": "caster",
        "class_id": 7,
        "rank_by_chain": True,
        "ui": ["elemental_shaman", "enhancement_shaman"],
        "weapon": STAFF,
        "armor": lambda level: (1, 2, 3) if level >= 40 else (1, 2),
        "stat_weights": CASTER_WEIGHTS,
        "suffix": EAGLE,
        "trees": {
            "elemental": {"sim_preset": "ui/elemental_shaman/apls/default.apl.json",
                          "source_preset": "shaman/elemental/forever.apl.json",
                          "talents": "5503331000011351-055000001-05301", "main_tree": 0},
            "enhancement": {"sim_preset": "ui/enhancement_shaman/apls/default.apl.json",
                            "source_preset": "shaman/enhancement/forever.apl.json",
                            "talents": "053503102-055030011005102251-01", "main_tree": 1, "loadout": "2h",
                            "spec": ("enhancementShaman", {"options": {}}), "spec_for_level": enhancement_spec,
                            "engagement": "melee", "armor": lambda level: (2, 3) if level >= 40 else (2,),
                            "stat_weights": MELEE_WEIGHTS, "suffix": BEAR},
            # The simulator has no restoration spec: the tree's damage list runs on the elemental
            # spec with the restoration build, against the elemental preset.
            "restoration": {"sim_preset": "ui/elemental_shaman/apls/default.apl.json",
                            "talents": "-003-5532503315513151", "main_tree": 2},
        },
        "actions": {},
        "unmodelled": dict(RACIALS),
    },
})
# What a tree may set in place of its class's value.
TREE_OVERRIDES = ("spec", "spec_for_level", "engagement", "weapon", "armor", "stat_weights", "suffix", "wand", "ranged")

# How a class meets a solo target. The simulator has no movement or kiting model for
# targets, so a profile is only: how far the character stands, and whether the target's
# hits land on the character (which pushes casts back) from the first second.
#   distance   yards from the target (None: melee range). A "near" gate is tested against it.
#   target_attacks_player   False: the target's swing does no damage and is only the clock
#                           kill time is measured with.
ENGAGEMENTS = {
    "melee": {"in_front": True, "target_attacks_player": True, "distance": None,
              "note": "stands in front of the target and is hit from the first second"},
    "caster": {"in_front": True, "target_attacks_player": True, "distance": 20,
               "note": "casts from 20 yards; the target is on the character from the first second (no approach "
                       "time, the pessimistic end) and every hit that lands can push a cast back"},
    "caster_free": {"in_front": True, "target_attacks_player": False, "distance": 20,
                    "note": "casts from 20 yards and is never hit (a pet holds the target, or it is feared): "
                            "no pushback, the optimistic end"},
    "ranged": {"in_front": True, "target_attacks_player": False, "distance": 30,
               "note": "shoots from 30 yards and is never hit (a pet holds the target, or it is kited): the "
                       "optimistic end; --engagement melee is the pessimistic one"},
}

# Weapon setups a tree can be played with (client item classes): the main hand, and a shield.
LOADOUTS = {
    "warrior": {
        "2h": {"weapon": {"inv": (17,), "subclasses": (1, 5, 6, 8)}, "shield": False,
               "note": "two-hand axe, mace, polearm or sword"},
        "shield": {"weapon": {"inv": (13, 21), "subclasses": (0, 4, 7)}, "shield": True,
                   "note": "one-hand axe, mace or sword and a shield"},
        # Two one-hand weapons once Dual Wield is learned; before that, the main hand alone.
        "dw": {"weapon": {"inv": (13, 21), "subclasses": (0, 4, 7, 13, 15)}, "shield": False, "dual": True,
               "note": "two one-hand weapons (axe, mace, sword, fist or dagger)"},
    },
    "paladin": {
        "2h": {"weapon": {"inv": (17,), "subclasses": (1, 5, 6, 8)}, "shield": False,
               "note": "two-hand axe, mace, polearm or sword"},
        "shield": {"weapon": {"inv": (13, 21), "subclasses": (0, 4, 7)}, "shield": True,
                   "note": "one-hand axe, mace or sword and a shield"},
    },
    # Rogues learn Dual Wield at level 10 (ASSUMED, as in Classic; --dual-wield-level changes it).
    "rogue": {
        "dw": {"weapon": {"inv": (13, 21), "subclasses": (4, 7, 13, 15)}, "shield": False, "dual": True,
               "dual_level": 10, "note": "two one-hand weapons (mace, sword, fist or dagger)"},
        "daggers": {"weapon": {"inv": (13, 21), "subclasses": (15,), "fixed": True}, "shield": False, "dual": True,
                    "dual_level": 10, "note": "two daggers"},
    },
    # The client's SkillLineAbility lists two-hand axes and maces as shaman trainer skills (class
    # masks 71 and 1091), no talent needed. It also lists Dual Wield for the shaman (another
    # acquire method), but the simulator's enhancement spec swings one weapon only.
    "shaman": {
        "2h": {"weapon": {"inv": (17,), "subclasses": (1, 5, 10)}, "shield": False,
               "note": "two-hand axe, mace or staff"},
        "shield": {"weapon": {"inv": (13, 21), "subclasses": (0, 4)}, "shield": True,
                   "note": "one-hand axe or mace and a shield"},
    },
}
# The client data does not say when Dual Wield (spell 674) is learned: it is a trainer skill
# (SkillLineAbility, acquire method 2) with no level of its own. ASSUMED: level 20, as in
# Classic; --dual-wield-level changes it.
ASSUMED_DUAL_WIELD_LEVEL = 20
DUAL_WIELD = {"level": ASSUMED_DUAL_WIELD_LEVEL}


def dual_wield_level():
    return DUAL_WIELD["level"]
# SpellShapeshift form bits for the warrior stances, and the list entries that take one.
STANCE_FORMS = {"Battle": 17, "Defensive": 18, "Berserker": 19}
STANCE_SPELLS = {2457: "Battle", 71: "Defensive", 2458: "Berserker"}
CLIENT_CSV = os.path.join(ROOT, "Documentation", "wow_spell_csv_forever")
ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR, SUBCLASS_SHIELD, SUBCLASS_WAND = 2, 4, 6, 19
# The pet a levelling character fights beside when --pet names none (ASSUMED: the first demon, and
# a cat). Before 2026-11-23 the default was no pet, which is not how either class levels: a
# Demonology list then cast Searing Pain without end, its brand needing the demon's attacks.
# A hunter has no pet before level 10 (HUNTER_PET_LEVEL, as in Classic).
DEFAULT_PET = {"warlock": "imp", "hunter": "cat"}
HUNTER_PET_LEVEL = 10
# A fight against several targets: their count and the fixed length of the pull (seconds).
PULL = {"mobs": 1, "seconds": 20.0}
# The bench fights alone. --grouped answers the lists' "in a group" condition as true, for what
# an entry kept for group play (Vanish) is worth there; nothing else about the fight changes.
GROUPED = {"on": False}
# --group: the fights a party member meets in a dungeon or raid (group_scenarios). The party's
# damage is modelled as health: the target loses health at the party's rate, so its health
# fraction over time is that of a target with the player's share of the health fought alone.
# The tank holds the target, so it does not hit the player and melee stand behind it, unless the
# tree is a tank tree ("tank").
GROUP = {"on": False, "tank": False}
# The client's level cap: a raid boss joins the --group fights there.
TOP_LEVEL = 60
# Every target's health is multiplied by a fight-length factor: one for every scenario, or one
# per level gap (target level minus player level) when calibration measured gaps.
HEALTH = {"scale": 1.0, "by_gap": {}}


def health_factor(gap):
    """The health factor for a level gap. Between two measured gaps it is interpolated (on a log
    scale, since kill time multiplies); outside them the nearest measured gap holds."""
    known = HEALTH["by_gap"]
    if not known:
        return HEALTH["scale"]
    if gap in known:
        return known[gap]
    gaps = sorted(known)
    if gap < gaps[0]:
        return known[gaps[0]]
    if gap > gaps[-1]:
        return known[gaps[-1]]
    lo = max(g for g in gaps if g < gap)
    hi = min(g for g in gaps if g > gap)
    t = (gap - lo) / float(hi - lo)
    return math.exp(math.log(known[lo]) * (1 - t) + math.log(known[hi]) * t)
SOLO_KINDS = {"normal": False, "rare": False, "elite": True, "rareelite": True}


def calibration_factor(ratios, quantile):
    """The measured/simulated kill-time ratio at a quantile (nearest rank). Above the median it leans
    toward fights that run a little long in the simulator, the safer side to be wrong on."""
    ordered = sorted(ratios)
    rank = max(1, min(len(ordered), int(math.ceil(quantile * len(ordered)))))
    return ordered[rank - 1]


def recorded_kills(path):
    """Solo kills JustAC recorded in game (JustACGlobal.mobProfile): one dict per kill with the
    creature's name, level range and kind, the player's level and the seconds it took."""
    text = open(path, encoding="utf-8", errors="replace").read()
    at = text.find('["mobProfile"] = {')
    if at < 0:
        return []
    reader = LuaReader(text)
    reader.pos = text.index("{", at)
    profile = reader.value()
    npcs = profile.get("npcs") if isinstance(profile, dict) else None
    out = []
    for npc in (npcs.values() if isinstance(npcs, dict) else []):
        kind = npc.get("class")
        if not isinstance(npc, dict) or kind not in SOLO_KINDS or not npc.get("lvMin"):
            continue
        for kill in npc.get("kills") or []:
            if isinstance(kill, dict) and kill.get("group") is False and kill.get("d") and kill.get("plvl"):
                out.append({"name": npc.get("name", "?"), "levels": list(range(int(npc["lvMin"]), int(npc.get("lvMax") or npc["lvMin"]) + 1)),
                            "elite": SOLO_KINDS[kind], "plvl": int(kill["plvl"]), "seconds": float(kill["d"])})
    return out


@functools.lru_cache(maxsize=None)
def client_rows(table):
    files = sorted(glob.glob(os.path.join(CLIENT_CSV, table + ".*.csv")))
    if not files:
        return []
    with open(files[-1], encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


# Client weapon skill line -> item weapon subclass.
SKILL_SUBCLASS = {44: 0, 172: 1, 45: 2, 46: 3, 54: 4, 160: 5, 229: 6, 43: 7, 55: 8, 136: 10, 473: 13, 173: 15,
                  176: 16, 226: 18, 228: 19}
RANGED_SUBCLASSES = (2, 3, 16, 18, 19)
_TRAINABLE = None


def trainable_weapons(class_id):
    """Weapon subclass -> skill name for every weapon skill the class can learn (the client's
    SkillLineAbility class masks). The data does not say which of them a character starts
    with, so a pick names its skill and the reader checks it is trained."""
    global _TRAINABLE
    if _TRAINABLE is None:
        _TRAINABLE = {}
        lines = {}
        for r in client_rows("SkillLine"):
            lines[int(r["ID"])] = r.get("DisplayName_lang") or r.get("\ufeffDisplayName_lang") or "skill %s" % r["ID"]
        for r in client_rows("SkillLineAbility"):
            sub = SKILL_SUBCLASS.get(int(r["SkillLine"]))
            if sub is None:
                continue
            mask = int(r["ClassMask"] or 0)
            for cid in range(1, 12):
                if not mask or mask >> (cid - 1) & 1:
                    _TRAINABLE.setdefault(cid, {})[sub] = lines.get(int(r["SkillLine"]), "skill")
    return _TRAINABLE.get(class_id, {})


def open_weapons(cfg):
    """Let a setup use every weapon type the class can learn. The setup keeps its shape (two-hand,
    one-hand, ranged: the inventory types) and a setup marked fixed keeps its types (daggers)."""
    skills = trainable_weapons(cfg["class_id"])
    if not skills:
        return
    if not cfg["weapon"].get("fixed"):
        cfg["weapon"] = dict(cfg["weapon"], subclasses=tuple(sorted(s for s in skills if s not in RANGED_SUBCLASSES)))
    if cfg.get("ranged"):
        learned = tuple(s for s in cfg["ranged"]["subclasses"] if s in skills)
        cfg["ranged"] = dict(cfg["ranged"], subclasses=learned or cfg["ranged"]["subclasses"])


def usability_problems(entries, names, stance, weapon_subclasses, shield, wand, forms=None, form_spells=None,
                       word="Stance"):
    """(entry label, why) for each list entry this setup can never use, from the client's spell
    data: a stance or form the setup never takes (its own, or one the list swaps to), and
    equipment it does not wear. Stance is not checked for a class without stances (stance None).
    forms / form_spells: the class's SpellShapeshift bits and the entries that take a form
    (default: the warrior stances)."""
    forms = STANCE_FORMS if forms is None else forms
    form_spells = STANCE_SPELLS if form_spells is None else form_spells
    word = (" " + word) if word else ""
    masks = dict((int(r["SpellID"]), int(r["ShapeshiftMask_0"] or 0)) for r in client_rows("SpellShapeshift")
                 if r["SpellID"].isdigit())
    needs = {}
    for r in client_rows("SpellEquippedItems"):
        if r["SpellID"].isdigit():
            needs.setdefault(int(r["SpellID"]), []).append((int(r["EquippedItemClass"] or 0),
                                                            int(r["EquippedItemSubclass"] or 0)))
    reachable = set([stance]) if stance else set()
    reachable |= set(form_spells[e["id"]] for e in entries if e["id"] in form_spells)
    worn = set(weapon_subclasses) | (set([SUBCLASS_WAND]) if wand else set())
    out, seen = [], set()
    for e in entries:
        sid = e["id"]
        if sid in seen:
            continue
        seen.add(sid)
        label = "%s (%d)" % (names.get(sid, "?"), sid)
        mask = masks.get(sid, 0)
        allowed = [n for n, bit in sorted(forms.items()) if mask >> (bit - 1) & 1]
        if stance and allowed and not set(allowed) & reachable:
            out.append((label, "needs %s%s; this setup stays in %s%s" % (" or ".join(allowed), word, stance, word)))
        elif stance and allowed and stance not in allowed:
            out.append((label, "usable only after the list swaps to %s%s" % (" or ".join(allowed), word)))
        for item_class, subclasses in needs.get(sid, []):
            if item_class == ITEM_CLASS_ARMOR and subclasses >> SUBCLASS_SHIELD & 1 and not shield:
                out.append((label, "needs a shield; this setup wears none"))
            elif item_class == ITEM_CLASS_WEAPON and subclasses and not any(subclasses >> s & 1 for s in worn):
                out.append((label, "needs a weapon type this setup does not wield"))
    return out


ASSUMPTIONS = {
    # Not measured. Classic dungeon elites are commonly described as about three times the
    # health of a normal creature of the level; damage factor chosen for illustration.
    "elite_health_mult": 3.0,
    "elite_damage_mult": 1.5,
    # Conversion from expected auto-attack damage per second to the simulator's target
    # swing, copied from the simulator's own planner benchmark (sim/planner/bench.go).
    "target_swing_speed": 2.0,
    "target_damage_spread": 0.3333,
    # --group (not measured): the player's share of a five-player party's damage (three damage
    # dealers, a tank and a healer adding a little), and boss health as multiples of a regular
    # creature of the boss's level, before that share. A raid boss is fought by a raid, so its
    # multiple is already the player's share: about two to three minutes at level 60.
    "party_share": 0.25,
    "dungeon_boss_health_mult": 12.0,
    "raid_boss_health_mult": 5.0,
}

OPS = {"<": "OpLt", "<=": "OpLe", ">": "OpGt", ">=": "OpGe", "=": "OpEq", "!=": "OpNe"}


# ---------------------------------------------------------------------------------------
# Reading the generated Lua (a small literal-table reader; the file is machine-written)
# ---------------------------------------------------------------------------------------
class LuaReader:
    TOKEN = re.compile(r"""\s*(?:--[^\n]*\n\s*)*(\{|\}|\[|\]|=|,|"(?:[^"\\]|\\.)*"|-?\d+\.?\d*(?:e-?\d+)?|[A-Za-z_]\w*)""")

    def __init__(self, text):
        self.text, self.pos = text, 0

    def peek(self):
        m = self.TOKEN.match(self.text, self.pos)
        return m.group(1) if m else None

    def take(self, want=None):
        m = self.TOKEN.match(self.text, self.pos)
        if not m or (want and m.group(1) != want):
            raise ValueError("Lua parse error near offset %d: wanted %r" % (self.pos, want))
        self.pos = m.end()
        return m.group(1)

    def value(self):
        tok = self.take()
        if tok == "{":
            return self.table()
        if tok.startswith('"'):
            return json.loads(tok)
        if tok in ("true", "false"):
            return tok == "true"
        if re.fullmatch(r"-?\d+", tok):
            return int(tok)
        return float(tok)

    def table(self):
        arr, obj = [], {}
        while True:
            tok = self.peek()
            if tok == "}":
                self.take()
                break
            if tok == "[":
                self.take()
                key = self.value()
                self.take("]")
                self.take("=")
                obj[key] = self.value()
            elif re.fullmatch(r"[A-Za-z_]\w*", tok) and tok not in ("true", "false"):
                save = self.pos
                self.take()
                if self.peek() == "=":
                    self.take()
                    obj[tok] = self.value()
                else:
                    self.pos = save
                    arr.append(self.value())
            else:
                arr.append(self.value())
            if self.peek() == ",":
                self.take()
        if obj and arr:
            obj["_list"] = arr
            return obj
        return obj if obj else arr


def load_rotations(path=None):
    text = open(path or ROTATIONS, encoding="utf-8").read()
    start = text.index("RotationImport.RegisterForever(") + len("RotationImport.RegisterForever(")
    reader = LuaReader(text)
    reader.pos = start
    classes = reader.value()
    reader.take(",")
    chains = reader.value()
    names = dict((int(i), n) for i, n in re.findall(r"\{id=(\d+),.*?\},?\s*-- ([^\n]+)", text))
    return classes, chains, names


def dot_floor_pct():
    """The runtime's rule: no new damage over time on a non-boss target below this health."""
    m = re.search(r"local DOT_MIN_TARGET_PCT = (\d+)", open(SPELL_QUEUE, encoding="utf-8").read())
    return int(m.group(1)) if m else None


DEFAULTS_LUA = os.path.join(ROOT, "Data", "Forever", "Defaults.lua")


def _lua_table(text, name):
    """[id] = value pairs of one generated `local NAME = { ... }` table, values as raw text."""
    m = re.search(r"local %s = \{(.*?)\n\}" % name, text, re.S)
    return dict((int(k), v.strip()) for k, v in re.findall(r"\[(\d+)\]\s*=\s*([^,]+),", m.group(1))) if m else {}


def _tree_spenders(text, name):
    """class -> tree -> spender ids of one generated `SpellDB.NAME = { CLS_F = { tree = {ids} } }`."""
    m = re.search(r"SpellDB\.%s = \{(.*)\}" % name, text)
    out = {}
    for cls, body in re.findall(r"(\w+)_F = \{((?:\s*\w+ = \{[^}]*\},?)*)\s*\}", m.group(1) if m else ""):
        out[cls.lower()] = dict((tree, [int(x) for x in re.findall(r"\d+", ids)])
                                for tree, ids in re.findall(r"(\w+) = \{([^}]*)\}", body))
    return out


def _tree_sets(text, name):
    m = re.search(r"SpellDB\.%s = \{(.*)\}" % name, text)
    out = {}
    for cls, body in re.findall(r"(\w+)_F = \{([^}]*)\}", m.group(1) if m else ""):
        out[cls.lower()] = set(re.findall(r"(\w+) = true", body))
    return out


def _class_lists(text, name):
    """class -> ids of one generated `local NAME = { CLASS = {ids}, ... }` table."""
    m = re.search(r"local %s = \{(.*?)\n\}" % name, text, re.S)
    return dict((cls.lower(), [int(x) for x in re.findall(r"\d+", body)])
                for cls, body in re.findall(r"(\w+) = \{([^}]*)\}", m.group(1) if m else ""))


def runtime_data():
    """What the runtime rules read: generated Forever data and SpellQueue.lua's constants."""
    text = open(DEFAULTS_LUA, encoding="utf-8").read()
    queue = open(SPELL_QUEUE, encoding="utf-8").read()

    def constant(name, default):
        m = re.search(r"local %s = (\d+)" % name, queue)
        return int(m.group(1)) if m else default
    return {
        "delayed": set(_lua_table(text, "DELAYED_PAYOFF")),
        "area_dots": set(_lua_table(text, "AREA_DOTS")),
        "creature_types": dict((k, int(v)) for k, v in _lua_table(text, "CREATURE_TYPES").items()),
        "frontal": dict((k, float(v)) for k, v in _lua_table(text, "FRONTAL_DOTS").items() if v != "true"),
        "dots": dict((k, float(v)) for k, v in _lua_table(text, "DOTS").items()),
        "stacks": dict((k, int(v)) for k, v in _lua_table(text, "STACKING_AURAS").items()),
        "threat": dict((k, v.strip('"')) for k, v in _lua_table(text, "THREAT_ROLES").items()),
        "burst": _class_lists(text, "BURST"),
        "tank_trees": _tree_sets(text, "FOREVER_TANK_TREES"),
        "early_armor_trees": _tree_spenders(text, "FOREVER_EARLY_ARMOR_TREES"),
        "dot_floor": constant("DOT_MIN_TARGET_PCT", 35),
        "fast_floor": constant("FAST_DOT_MIN_TARGET_PCT", 70),
        "long_fight": constant("LONG_FIGHT_SECONDS", 20),
        "higher_level": constant("HIGHER_LEVEL_FIGHT", 3),
    }


class RuntimeRules:
    """The queue's rules that live outside the lists (SpellQueue.lua), for one scenario: a solo
    fight against one target of a known level and kind. Each is the runtime's rule, read
    through what the simulator can express; the approximations are said where they are made."""

    def __init__(self, data, cls, tree, level_delta, elite, pack, cooldown_gap=None, level=None, boss=False):
        self.d, self.cls, self.tree = data, cls, tree
        self.boss = boss
        # SpellDB.IsEarlyArmorTree: the tree repays an armor reduction at once only when one of
        # its main spenders is learned at this level (None: the full build, every one learned).
        spenders = data["early_armor_trees"].get(cls, {}).get(tree)
        self.early_armor = bool(spenders) and (level is None or any(
            (client_spell_levels().get(s) or 999) <= level for s in spenders))
        self.pack = pack
        # IsWorthwhileFight(b, true) without its age clause: a boss, an elite, a higher level.
        self.lasting = boss or elite or level_delta >= 1
        # IsWorthwhileFight(b) for a multi-minute self-buff: several enemies, a boss, an elite or
        # a regular target HIGHER_LEVEL_FIGHT levels above (--cooldown-gap tries another gap).
        # Time already spent on the target does not count.
        if cooldown_gap is None:
            cooldown_gap = data["higher_level"]
        self.worthwhile = boss or elite or pack or level_delta >= cooldown_gap
        # fastSoloFight: one regular enemy at or below the player's level, alone.
        self.fast = not elite and level_delta <= 0 and not pack and not GROUPED["on"]
        # shortGroupFight: grouped, and the fight is not worthwhile (IsWorthwhileFight, whose age
        # clause ends it after LONG_FIGHT_SECONDS).
        self.short_group = GROUPED["on"] and not self.worthwhile

    def stack(self, e, g):
        """IsStackPayoffContext: one stack becomes the full stack where stacks pay."""
        if (g.get("t") == "stack" and g.get("tgt") and g.get("id") == e["id"] and g.get("op") == "<"
                and g.get("n") == 1 and not g.get("once") and e["id"] in self.d["delayed"]
                and self.d["stacks"].get(e["id"], 0) > 1 and (self.lasting or GROUPED["on"])):
            return dict(g, n=self.d["stacks"][e["id"]]), "stacked to %d on this target (runtime: grouped, elite or higher level)" % self.d["stacks"][e["id"]]
        return g, None

    def hold(self, e):
        """HoldAutomaticBurst for a slow payoff: (condition or None, note)."""
        sid = e["id"]
        if sid in self.d.get("burst", {}).get(self.cls, ()):
            # The class's major cooldowns stand in for the runtime's own test (a pure self-buff
            # with a base cooldown of two minutes or more), which needs the live client.
            if self.worthwhile:
                return None, "major cooldown allowed: an elite, several enemies or a much higher level"
            return Converter.const("false"), "major cooldown held: needs an elite, several enemies or a much higher level"
        if sid in self.d["area_dots"]:
            # Area damage over time waits on a dying last enemy: the damage over time line.
            if self.pack:
                return None, "area damage over time: dying-target hold not modelled in a fixed pull"
            floor = self.d["dot_floor"]
            return (Converter.health_fraction(">=", floor),
                    "area damage over time held below %d%% health on the last enemy" % floor)
        if sid not in self.d["delayed"]:
            return None, None
        # SpellDB.IsPlayerTank grouped (the tank tree, no role in the simulator), or an early-armor
        # tree: a threat-building armor reduction is not held. A tank alone holds it like the rest.
        grouped_tank = GROUPED["on"] and self.tree in self.d["tank_trees"].get(self.cls, set())
        if self.d["threat"].get(sid) == "boost" and (grouped_tank or self.early_armor):
            return None, "slow payoff, not held in this tree"
        if sid in self.d["dots"]:
            if self.lasting:
                return None, "delayed damage allowed: an elite or higher-level target"
            return Converter.const("false"), "delayed damage held: needs a boss, an elite or a higher-level target"
        if self.lasting:
            return None, "slow payoff allowed: an elite or higher-level target"
        seconds = self.d["long_fight"]
        return ({"cmp": {"op": OPS[">="], "lhs": {"currentTime": {}}, "rhs": {"const": {"val": "%gs" % seconds}}}},
                "slow payoff held until the fight has lasted %d s" % seconds)

    def dot(self, conv, g, value):
        """The dying-target and fast-fight rules for a new damage over time: (condition, note)."""
        if self.pack:
            return value, "dying-target rules not modelled in a fixed pull (targets do not die)"
        share = self.d["frontal"].get(g.get("id"))
        floor, fast = self.d["dot_floor"], self.d["fast_floor"]
        parts, said = [value], []
        if self.short_group and g.get("id") not in self.d["frontal"]:
            seconds = self.d["long_fight"]
            parts.append({"cmp": {"op": OPS[">="], "lhs": {"currentTime": {}},
                                  "rhs": {"const": {"val": "%gs" % seconds}}}})
            said.append("short group fight: not for the first %d s" % seconds)
        if self.boss:
            said.append("a boss: no dying-target floor")
        elif share is None:
            parts.append(conv.health_fraction(">=", floor))
            said.append("not below %d%% health" % floor)
        elif share < 0.5:
            instant = {"cmp": {"op": OPS["<="], "lhs": {"spellCastTime": {"spellId": conv.spell_ref(g["id"], "dot rule")}},
                               "rhs": {"const": {"val": "0s"}}}}
            parts.append({"or": {"vals": [conv.health_fraction(">=", floor), instant]}})
            said.append("below %d%% only when instant (a real hit up front)" % floor)
        if self.fast and not (share is not None and share >= 0.5):
            # The runtime renews a DoT that already ran on the target; the simulator cannot count
            # applications, so the higher floor holds until the DoT's own duration (or the fight
            # age that ends a fast fight) has passed: about when a first application would end.
            until = min(self.d["long_fight"], self.d["dots"].get(g.get("id"), self.d["long_fight"]))
            late = {"cmp": {"op": OPS[">="], "lhs": {"currentTime": {}}, "rhs": {"const": {"val": "%gs" % until}}}}
            parts.append({"or": {"vals": [conv.health_fraction(">=", fast), late]}})
            said.append("fast fight: not below %d%% for the first %g s (approximates first application only)" % (fast, until))
        if len(parts) == 1:
            return value, "mostly its hit: no health rule"
        return {"and": {"vals": parts}}, "; ".join(said)


# ---------------------------------------------------------------------------------------
# Matching JustAC ids to simulator action ids
# ---------------------------------------------------------------------------------------
def walk(node, fn):
    if isinstance(node, dict):
        fn(node)
        for v in node.values():
            walk(v, fn)
    elif isinstance(node, list):
        for v in node:
            walk(v, fn)


def harvest_sim_ids(sim, cls):
    """Action ids the simulator's own presets for the class use: id -> {"tag", "dot"}."""
    found = {}
    files = []
    for page in CLASSES.get(cls, {}).get("ui", [cls]):
        folder = os.path.join(sim, "ui", page, "apls")
        files += [os.path.join(folder, name) for name in sorted(os.listdir(folder)) if name.endswith(".apl.json")] \
            if os.path.isdir(folder) else []
    for path in files:
        data = json.load(open(path, encoding="utf-8"))

        def visit(node):
            for key, val in node.items():
                if not isinstance(val, dict):
                    continue
                ref = val.get("spellId") or val.get("auraId")
                if isinstance(ref, dict) and "spellId" in ref:
                    rec = found.setdefault(ref["spellId"], {"tag": 0, "dot": False})
                    if key in ("castSpell", "channelSpell"):
                        rec["cast"] = True
                    if key in ("castSpell", "channelSpell") and ref.get("tag"):
                        rec["tag"] = ref["tag"]
                    if key in ("dotIsActive", "dotRemainingTime", "multidot"):
                        rec["dot"] = True
        walk(data, visit)
    return found


# Classes whose simulator code registers its spells from the generated rank tables
# (sim/<class>/level_ranks_generated.go, tools/forever-sim-patches): there the table's ids are the
# simulator's action ids. Every other class has the table too (for checks against client data)
# but registers its own ids, so the table must not be read as the simulator's: with it the mage's
# Arcane Blast was sent as the client rank id and never cast (2026-11-23).
RANKED_BY_TABLE = ("rogue", "druid", "hunter", "warlock")


def scanned(cls, name):
    """Is this simulator source file one the id scans read?"""
    if not name.endswith(".go") or name.endswith("_test.go"):
        return False
    return name != "level_ranks_generated.go" or cls in RANKED_BY_TABLE


def source_literals(sim, cls):
    """Every integer literal in the simulator's Go source for the class and its core."""
    out = set()
    for folder in (os.path.join(sim, "sim", cls), os.path.join(sim, "sim", "core")):
        for base, _, files in os.walk(folder):
            for name in files:
                if scanned(cls, name):
                    text = open(os.path.join(base, name), encoding="utf-8", errors="replace").read()
                    out.update(int(n) for n in re.findall(r"\b\d{2,7}\b", text))
    return out


def rank_tables(sim, cls, client_levels=False):
    """Rank families the simulator registers one spell per rank for: [(ids, required levels)].

    Some classes (warlock) give every rank its own action id and register only the ranks the
    level has, so a list that names the top rank casts nothing on a low character. The
    families are read from the class's Go source, where each is a pair of literal arrays
    indexed by rank (spellId := [...]int32{0, ...}[rank] and level := [...]int{0, ...}[rank]).

    client_levels: also take an id array with no level array beside it, with the client's own
    required level per rank. Only for a class whose simulator code registers every rank under
    its own id; the warrior code keeps one id per spell at every level and must not get this."""
    out = []
    client = {}
    for r in client_rows("SpellLevels"):
        if r["SpellID"].isdigit() and r.get("DifficultyID", "0") == "0":
            client[int(r["SpellID"])] = int(r["BaseLevel"] or 0)
    files = []
    for base, _, names in os.walk(os.path.join(sim, "sim", cls)):
        if os.path.basename(base).startswith("_"):
            continue
        files += [os.path.join(base, n) for n in sorted(names) if scanned(cls, n)]
    config = os.path.join(sim, "sim", "core", "config.go")
    include_aq = bool(re.search(r"IncludeAQ\s*=\s*true", open(config, encoding="utf-8").read())) if os.path.exists(config) else True
    # A class that registers every rank under its own id names its level arrays freely
    # (WrathLevel); elsewhere only a bare `level` beside the ids is a rank table: the warrior
    # code has RevengeSpellId and RevengeLevel but casts one id at every level.
    pattern = (r"(?i)\b(\w*spellid|%s)\s*:?=\s*\[[^\]]*\]int(?:32)?\{([^}]*)\}"
               % (r"\w*level" if client_levels else "level"))
    for path in sorted(files):
        body = open(path, encoding="utf-8", errors="replace").read()
        # maxRank := core.TernaryInt(core.IncludeAQ, 12, 11): without the level 60 book ranks the
        # simulator registers only the lower count, so a family of the higher count is cut to it.
        book = re.search(r"TernaryInt\(core\.IncludeAQ,\s*(\d+),\s*(\d+)\)", body)
        cut = (int(book.group(1)), int(book.group(2))) if book and not include_aq else None
        found = [(m.group(1).lower().endswith("level"), [int(n) for n in re.findall(r"\d+", m.group(2))])
                 for m in re.finditer(pattern, body)]
        for k, (is_level, ids) in enumerate(found):
            if is_level or len(ids) < 2:
                continue
            nxt = found[k + 1] if k + 1 < len(found) else None
            if nxt and nxt[0] and len(nxt[1]) == len(ids):
                levels = nxt[1]
            elif not client_levels:
                continue
            else:
                # No level array beside it: the client's own required level for each rank.
                levels = [client.get(i, 0) for i in ids]
                if any(lv <= 0 for i, lv in zip(ids, levels) if i):
                    continue
            if ids[0] == 0:
                ids, levels = ids[1:], levels[1:]
            if cut and len(ids) == cut[0]:
                ids, levels = ids[:cut[1]], levels[:cut[1]]
            if len(ids) > 1:
                out.append((ids, levels))
        # A spell defined per level bracket: spellID := map[int32]int32{25: a, 40: b, ...}[x.Level].
        for m in re.finditer(r"(?i)\bspellid\s*:?=\s*map\[int32\]int32\{([^}]*)\}\[\w+(?:\.\w+)*\.Level\]", body):
            inner = re.sub(r"core\.TernaryInt(?:32)?\(core\.IncludeAQ,\s*(\d+),\s*(\d+)\)",
                           lambda t: t.group(1) if include_aq else t.group(2), m.group(1))
            pairs = sorted((int(a), int(b)) for a, b in re.findall(r"(\d+)\s*:\s*(\d+)", inner))
            if len(pairs) > 1:
                out.append(([b for _, b in pairs], [a for a, _ in pairs]))
    return out


def bracket_only(sim, cls):
    """Names of the class's simulator source files that define something by a map indexed with the
    character's level (x := map[...]...{25: .., 40: .., 50: .., 60: ..}[c.Level]): at any other
    level the value is zero, so whatever the file models is missing or at rank 0."""
    out = []
    for base, _, names in os.walk(os.path.join(sim, "sim", cls)):
        if os.path.basename(base).startswith("_"):
            continue
        for n in sorted(names):
            if scanned(cls, n):
                text = open(os.path.join(base, n), encoding="utf-8", errors="replace").read()
                if re.search(r"\}\[\w+(?:\.\w+)*\.Level\]", text):
                    out.append(n[:-3])
    return sorted(set(out))


def struct_spell_ids(sim, cls):
    """Ids the class's source names as a spell in a field (spellID: n): ranks kept in a table of
    structs, which rank_tables cannot read."""
    out = set()
    for base, _, names in os.walk(os.path.join(sim, "sim", cls)):
        for n in names:
            if scanned(cls, n):
                text = open(os.path.join(base, n), encoding="utf-8", errors="replace").read()
                out.update(int(x) for x in re.findall(r"(?i)\bspellid:\s*(\d+)", text))
    return out


def client_spell_levels():
    return dict((int(r["SpellID"]), int(r["BaseLevel"] or 0)) for r in client_rows("SpellLevels")
                if r["SpellID"].isdigit() and r.get("DifficultyID", "0") == "0")


# The level 60 ranks taught by Ahn'Qiraj books. The simulator leaves them out (IncludeAQ is false
# in sim/core/config.go), so a family never picks one: the rank below is the highest it has.
BOOK_RANKS = (25286, 25361)


# Aura ids the simulator uses at every level though they sit in a rank family: an aura a class
# entry names as the one the simulator always applies (the rogue's Stealth aura is 1787 whatever
# rank of Stealth was cast), and the shared debuffs its core registers under one id for every rank
# (Faerie Fire 9907, Sunder Armor 11597). An aura check keeps that id at every level; a cast of the
# same id still takes the level's rank. Before 2026-11-24 the check was moved to the level's rank,
# which the simulator never applies, so it read "never up" and the debuff was recast every global
# cooldown (a level 24 cat cast Faerie Fire 15 times in a 26 s fight).
FIXED_IDS = set()


def core_fixed_auras(sim):
    """Aura ids the simulator's shared core registers literally (sim/core, not its tests)."""
    found = set()
    core = os.path.join(sim, "sim", "core")
    for name in os.listdir(core):
        if name.endswith(".go") and not name.endswith("_test.go"):
            text = open(os.path.join(core, name), encoding="utf-8").read()
            found.update(int(i) for i in re.findall(r"ActionID:\s*ActionID\{SpellID:\s*(\d+)\}", text))
    return found


def labelled_auras(sim, cls):
    """Aura label (lower case) -> ids the simulator registers under it, in the class's code and the
    shared core. The simulator keeps some auras under the id of a later game version (Heating Up
    as 44445); the label carries the client's name."""
    out = {}
    folders = [os.path.join(sim, "sim", "core"), os.path.join(sim, "sim", cls)]
    pattern = re.compile(r'Label:\s*"([^"]+)",\s*ActionID:\s*(?:core\.)?ActionID\{SpellID:\s*(\d+)\}')
    for folder in folders:
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            if name.endswith(".go") and not name.endswith("_test.go"):
                text = open(os.path.join(folder, name), encoding="utf-8").read()
                for label, sid in pattern.findall(text):
                    out.setdefault(label.lower(), set()).add(int(sid))
    return out


def ranks_for_level(rotation, tables, level):
    """A copy of the rotation in which every id of a rank family is the highest rank the
    level has (rank 1 when it has none: the spell is then not registered and never cast)."""
    best = {}
    for ids, levels in tables:
        have = [i for i, need in zip(ids, levels) if need <= level and not BOOK_RANKS[0] <= i <= BOOK_RANKS[1]]
        for i in ids:
            best[i] = have[-1] if have else ids[0]
    if not best:
        return rotation
    rotation = json.loads(json.dumps(rotation))

    def visit(node, key=None):
        if isinstance(node, dict):
            sid = node.get("spellId")
            if isinstance(sid, int) and sid in best and not (key == "auraId" and sid in FIXED_IDS):
                node["spellId"] = best[sid]
            for k, v in node.items():
                visit(v, k)
        elif isinstance(node, list):
            for v in node:
                visit(v, key)
    visit(rotation)
    return rotation


class IdMap:
    def __init__(self, sim, cls, chains):
        self.cfg = CLASSES[cls]
        self.chains = chains
        self.harvest = harvest_sim_ids(sim, cls)
        self.literals = source_literals(sim, cls)
        self.tables = (rank_tables(sim, cls, bool(self.cfg.get("rank_by_chain") or self.cfg.get("rank_by_client")))
                       + [tuple(t) for t in self.cfg.get("rank_tables", [])])
        # Ranks the simulator keeps in struct tables: a list chain with two or more of its ids
        # named there is a rank family too, with the client's own level for each rank.
        covered = set(i for ids, _ in self.tables for i in ids)
        named, levels = struct_spell_ids(sim, cls), None
        if self.cfg.get("rank_by_chain"):
            # A class whose simulator code registers every rank under its own id, each with its
            # required level, in whatever form it is written: any chain with two or more ids in
            # the class's source is a rank family.
            named = self.literals
        for chain in chains.values():
            ids = [i for i in chain if i in named]
            if len(ids) > 1 and not set(chain) & covered:
                levels = levels or client_spell_levels()
                self.tables.append((ids, [max(levels.get(i, 1), 1) for i in ids]))
                covered.update(ids)
        self.notes = {}   # justac id -> how it was matched
        self.fixed_auras = core_fixed_auras(sim)
        self.labels = labelled_auras(sim, cls)
        self.labelled = set(i for ids in self.labels.values() for i in ids)
        # Spell names, for a spell the simulator knows under another id (it keeps some ids of
        # later game versions where the Forever client has its own): the simulator's database
        # first, the client's SpellName table for ids the database lacks.
        self.sim_names = {}
        for s in json.load(open(os.path.join(sim, "assets", "database", "db.json"), encoding="utf-8")).get("spellIcons", []):
            self.sim_names[s["id"]] = s["name"]
        self._client_names = None

    def name_of(self, sid):
        if sid in self.sim_names:
            return self.sim_names[sid]
        if self._client_names is None:
            self._client_names = dict((int(r["ID"]), r["Name_lang"]) for r in client_rows("SpellName") if r["ID"].isdigit())
        return self._client_names.get(sid)

    def same_name(self, jid):
        """Simulator ids that carry the spell's name: those its presets use, else those in its source."""
        name = self.name_of(jid)
        if not name:
            return []
        same = [i for i, n in self.sim_names.items() if n == name and i != jid]
        return [i for i in same if i in self.harvest] or [i for i in same if i in self.literals]

    def action(self, jid):
        """Simulator action for a JustAC rank-1 id: dict(id, tag, dot) or None."""
        if jid in self.cfg["unmodelled"]:
            self.notes[jid] = "unmodelled: " + self.cfg["unmodelled"][jid]
            return None
        if jid in self.cfg["actions"]:
            rec = dict({"tag": 0, "dot": False}, **self.cfg["actions"][jid])
            ok = rec["id"] in self.literals
            self.notes[jid] = "class table -> %d%s" % (rec["id"], "" if ok else " (NOT FOUND in simulator source)")
            return rec
        chain = self.chains.get(jid) or [jid]
        for ids, _ in self.tables:
            if set(ids) & set(chain):
                self.notes[jid] = "simulator rank family %d..%d: the rank is chosen per level" % (ids[0], ids[-1])
                return {"id": ids[-1], "tag": 0, "dot": any(self.harvest.get(i, {}).get("dot") for i in ids)}
        hits = [c for c in chain if c in self.harvest]
        if len(hits) == 1:
            self.notes[jid] = "simulator preset id %d (same rank chain)" % hits[0]
            return dict(self.harvest[hits[0]], id=hits[0])
        if not hits:
            # A spell the simulator's presets cast under another id beats a bare number in its
            # source: the source also names ids that are auras or other versions, not the cast.
            preset = [i for i in self.same_name(jid) if self.harvest.get(i, {}).get("cast")]
            if len(preset) == 1:
                self.notes[jid] = "simulator preset id %d: the same spell name (%s), another id" % (preset[0], self.name_of(jid))
                return dict(self.harvest[preset[0]], id=preset[0])
            hits = [c for c in chain if c in self.literals]
            if len(hits) == 1:
                self.notes[jid] = "simulator source literal %d (same rank chain)" % hits[0]
                return {"id": hits[0], "tag": 0, "dot": False}
        named = self.same_name(jid)
        if len(named) == 1:
            self.notes[jid] = "simulator id %d: the same spell name (%s), another id" % (named[0], self.name_of(jid))
            return dict(self.harvest.get(named[0], {"tag": 0, "dot": False}), id=named[0])
        self.notes[jid] = "no unique match in the rank chain (%s)%s" % (
            hits or "none", "; by name: %s" % named if named else "")
        return None

    def aura(self, jid):
        """Aura id for a buff / debuff gate. Falls back to the id itself, and says so."""
        if jid in self.cfg.get("aura_alias", {}):
            return self.cfg["aura_alias"][jid], False, None
        rec = self.action(jid) if (jid in self.chains or jid in self.cfg["actions"]) else None
        if rec:
            family = next((ids for ids, _ in self.tables if rec["id"] in ids), ())
            # A DoT keeps its own per-rank timer (Insect Swarm's 24977 is only its miss rider).
            fixed = [i for i in family if i in self.fixed_auras]
            if len(fixed) == 1 and not rec.get("dot"):
                FIXED_IDS.add(fixed[0])
                return fixed[0], False, None
            return rec["id"], rec.get("dot", False), None
        if jid not in self.labelled:
            # Registered under the client's name with another id (a literal of jid in a comment
            # is not a registration).
            labelled = self.labels.get((self.name_of(jid) or "").lower(), set())
            if len(labelled) == 1:
                return next(iter(labelled)), False, None
        if jid in self.literals or jid in self.harvest:
            return jid, False, None
        named = self.same_name(jid)
        if len(named) == 1:
            return named[0], self.harvest.get(named[0], {}).get("dot", False), None
        return jid, False, "aura %d is not referenced anywhere in the simulator: reads as never active" % jid


# ---------------------------------------------------------------------------------------
# Gate -> simulator condition
# ---------------------------------------------------------------------------------------
EXACT, APPROX, LOST = "exact", "approximated", "not expressible"
# The game's totem slots -> the simulator's totem types.
TOTEM_SLOTS = {1: "Fire", 2: "Earth", 3: "Water", 4: "Air"}


class Converter:
    def __init__(self, idmap, names, engagement, dot_floor, rules=None, talents=None):
        self.ids, self.names = idmap, names
        self.talents = talents   # talent name -> points in the build being run, or None
        self.engagement, self.engagement_name = ENGAGEMENTS[engagement], engagement
        self.dot_floor = dot_floor
        self.rules = rules   # RuntimeRules for one scenario, or None for the list alone
        self.report = []   # (line label, status, text)
        self.line = ""

    def note(self, status, text):
        self.report.append((self.line, status, text))

    @staticmethod
    def const(value):
        return {"const": {"val": value}}

    @staticmethod
    def cmp(lhs, op, n):
        return {"cmp": {"op": OPS[op], "lhs": lhs, "rhs": {"const": {"val": ("%g" % n)}}}}

    @staticmethod
    def neg(value, negate):
        return {"not": {"val": value}} if negate else value

    def spell_ref(self, jid, what):
        rec = self.ids.action(jid)
        if rec is None:
            self.note(APPROX, "%s names spell %d, which the simulator does not have: read as unknown / never ready (%s)"
                      % (what, jid, self.ids.notes.get(jid, "")))
            return {"spellId": jid}
        ref = {"spellId": rec["id"]}
        if rec.get("tag"):
            ref["tag"] = rec["tag"]
        return ref

    @staticmethod
    def health_fraction(op, pct):
        # Fight sized by health, one target: remaining fraction of the fight IS the health fraction.
        return {"cmp": {"op": OPS[op], "lhs": {"remainingTimePercent": {}}, "rhs": {"const": {"val": "%g" % (pct / 100.0)}}}}

    def gate(self, g):
        t = g.get("t")
        if t in ("any", "all"):
            vals = [self.gate(m) for m in g.get("g", [])]
            return {"or" if t == "any" else "and": {"vals": vals}}
        if t == "buff":
            aid, _, warn = self.ids.aura(g["id"])
            if warn:
                self.note(APPROX, "buff gate: " + warn)
            else:
                self.note(EXACT, "buff %d -> aura %d active on the player%s" % (g["id"], aid, " (negated)" if g.get("neg") else ""))
            return self.neg({"auraIsActive": {"auraId": {"spellId": aid}}}, g.get("neg"))
        if t in ("debuff", "dot"):
            aid, is_dot, warn = self.ids.aura(g["id"])
            if warn:
                self.note(APPROX, "debuff gate: " + warn)
                if g.get("neg") or t == "dot":
                    # "Cast while X is not on the target", and the simulator has no X: the entry
                    # would be pressed without end (2026-11-23: Demonology at 30 cast Searing Pain 27
                    # times a fight and nothing else). The line is left out instead.
                    self.unkept = g["id"]
            if g.get("op"):
                if g.get("ncast"):
                    rhs = {"spellCastTime": {"spellId": self.spell_ref(g["ncast"], "debuff gate cast time")}}
                else:
                    rhs = {"const": {"val": "%gs" % g.get("n", 0)}}
                self.note(EXACT, "time left on %d %s %s" % (aid, g["op"], g.get("ncast") and "its cast time" or g.get("n")))
                if aid in self.ids.cfg.get("self_auras", ()):
                    return {"cmp": {"op": OPS[g["op"]], "lhs": {"auraRemainingTime": {"auraId": {"spellId": aid}}}, "rhs": rhs}}
                left = {"cmp": {"op": OPS[g["op"]], "lhs": {"dotRemainingTime": {"spellId": {"spellId": aid}}}, "rhs": rhs}}
                if g["op"] in (">", ">=") and self.rules:
                    # GateVerdict: waiting for time on a DoT the runtime will not start is met.
                    starts, said = self.rules.dot(self, g, {"const": {"val": "true"}})
                    if starts != {"const": {"val": "true"}}:
                        self.note(EXACT, "runtime: the wait is met where the DoT would not start (%s)" % said)
                        return {"or": {"vals": [left, {"not": {"val": starts}}]}}
                return left
            if is_dot:
                active = {"dotIsActive": {"spellId": {"spellId": aid}}}
            else:
                ref = {"spellId": aid}
                if g["id"] in self.ids.cfg.get("aura_tags", {}):
                    ref["tag"] = self.ids.cfg["aura_tags"][g["id"]]
                active = {"auraIsActive": {"auraId": ref, "sourceUnit": {"type": "CurrentTarget"}}}
            want_absent = bool(g.get("neg")) or t == "dot"
            value = self.neg(active, want_absent)
            if (t == "dot" or g.get("refresh")) and self.rules:
                value, said = self.rules.dot(self, g, value)
                self.note(APPROX if "approximates" in said or "not modelled" in said else EXACT,
                          "apply %d when it is not on the target (runtime: %s)" % (aid, said))
            elif t == "dot" or g.get("refresh"):
                if self.dot_floor:
                    self.note(EXACT, "apply %d when it is not on the target, and (runtime rule, non-boss target) only at or above %d%% health"
                              % (aid, self.dot_floor))
                    value = {"and": {"vals": [value, self.health_fraction(">=", self.dot_floor)]}}
                else:
                    self.note(EXACT, "apply %d when it is not on the target" % aid)
            else:
                self.note(EXACT, "debuff %d %s on the target" % (aid, "absent" if want_absent else "present"))
            return value
        if t == "stack":
            aid, _, warn = self.ids.aura(g["id"])
            if warn:
                self.note(APPROX, "stack gate: " + warn)
            val = {"auraNumStacks": {"auraId": {"spellId": aid}}}
            if g.get("tgt") and aid not in self.ids.cfg.get("self_auras", ()):
                val["auraNumStacks"]["sourceUnit"] = {"type": "CurrentTarget"}
            self.note(EXACT, "stacks of %d %s %s on the %s" % (aid, g["op"], g["n"], "target" if g.get("tgt") else "player"))
            return self.cmp(val, g["op"], g["n"])
        if t == "bench_unhindered":
            early = {"cmp": {"op": OPS["<"], "lhs": {"currentTime": {}}, "rhs": {"const": {"val": "%gs" % g["n"]}}}}
            if not g.get("shield"):
                self.note(EXACT, "weapon stage: only in the first %g s of the fight, before the target arrives" % g["n"])
                return early
            self.note(EXACT, "weapon stage: only before the target arrives (%g s) or while the shield %d holds"
                      % (g["n"], g["shield"]))
            return {"or": {"vals": [early, {"auraIsActive": {"auraId": {"spellId": g["shield"]}}}]}}
        if t == "execute":
            if g["op"] == "<" and g["pct"] in (20, 25, 35):
                self.note(EXACT, "target below %d%% health" % g["pct"])
                return {"isExecutePhase": {"threshold": "E%d" % g["pct"]}}
            self.note(EXACT, "target health %s %s%%" % (g["op"], g["pct"]))
            return self.health_fraction(g["op"], g["pct"])
        if t == "health":
            self.note(APPROX, "player health %s %s%%: the simulated player takes the target's hits and is never healed"
                      % (g["op"], g["pct"]))
            return self.cmp({"currentHealthPercent": {"sourceUnit": {"type": "Self"}}}, g["op"], g["pct"] / 100.0)
        if t == "power":
            res = g.get("res")
            if res == "mana" and g.get("ispct"):
                self.note(EXACT, "mana %s %s%%" % (g["op"], g["n"]))
                return self.cmp({"currentManaPercent": {}}, g["op"], g["n"] / 100.0)
            name = {"rage": "currentRage", "energy": "currentEnergy", "mana": "currentMana"}.get(res)
            if name:
                self.note(EXACT, "%s %s %s" % (res, g["op"], g["n"]))
                return self.cmp({name: {}}, g["op"], g["n"])
        if t == "resource" and g.get("res") == "combo_points":
            self.note(EXACT, "combo points %s %s" % (g["op"], g["n"]))
            return self.cmp({"currentComboPoints": {}}, g["op"], g["n"])
        if t == "cd":
            self.note(EXACT, "spell %d %s" % (g["id"], "on cooldown or not learned" if g.get("neg") else "ready"))
            return self.neg({"spellIsReady": {"spellId": self.spell_ref(g["id"], "cooldown gate")}}, g.get("neg"))
        if t == "known" and self.talents is not None and self.ids.name_of(g["id"]) in self.talents:
            # A talent (or the aura it grants, which carries its name): the build decides.
            name = self.ids.name_of(g["id"])
            have = self.talents[name] > 0
            self.note(EXACT, "talent %s %s in this build" % (name, "taken" if have else "not taken"))
            return self.neg(self.const("true" if have else "false"), g.get("neg"))
        if t == "group":
            self.note(APPROX, "in a group: %s (the bench fights alone; --grouped answers yes)"
                      % ("yes" if GROUPED["on"] else "no"))
            return self.neg(self.const("true" if GROUPED["on"] else "false"), g.get("neg"))
        if t == "known":
            self.note(EXACT, "spell %d %s" % (g["id"], "not known" if g.get("neg") else "known"))
            return self.neg({"spellIsKnown": {"spellId": self.spell_ref(g["id"], "known gate")}}, g.get("neg"))
        if t == "targets":
            self.note(EXACT, "engaged enemies %s %s" % (g["op"], g["n"]))
            return self.cmp({"numberTargets": {}}, g["op"], g["n"])
        if t == "cast":
            self.note(EXACT, "cast time of %d %s %s s" % (g["id"], g["op"], g["n"]))
            return {"cmp": {"op": OPS[g["op"]], "lhs": {"spellCastTime": {"spellId": self.spell_ref(g["id"], "cast gate")}},
                            "rhs": {"const": {"val": "%gs" % g["n"]}}}}
        if t == "swing":
            self.note(EXACT, "next %s swing %s %s s" % ("ranged" if g.get("ranged") else "melee", g["op"], g["n"]))
            return {"cmp": {"op": OPS[g["op"]], "lhs": {"autoTimeToNext": {"autoType": "Ranged" if g.get("ranged") else "MainHand"}},
                            "rhs": {"const": {"val": "%gs" % g["n"]}}}}
        if t == "near":
            distance = self.engagement.get("distance")
            near = distance is None or distance <= (g.get("n") or 0)
            self.note(APPROX, "target within %s yards: constant %s (the character stands %s)"
                      % (g.get("n"), str(near).lower(), "in melee range" if distance is None else "%g yards away" % distance))
            return self.const("true" if near else "false")
        if t == "hit":
            hit = self.engagement["target_attacks_player"]
            self.note(APPROX, "being hit: constant %s for the %s engagement" % (str(hit).lower(), self.engagement_name))
            return self.const("true" if hit else "false")
        if t == "totem" and g.get("slot") in TOTEM_SLOTS:
            kind = TOTEM_SLOTS[g["slot"]]
            self.note(EXACT, "%s totem %s" % (kind, "not down" if g.get("neg") else "down"))
            return {"cmp": {"op": OPS["<=" if g.get("neg") else ">"], "lhs": {"totemRemainingTime": {"totemType": kind}},
                            "rhs": {"const": {"val": "0s"}}}}
        if t == "unconfirmed":
            self.note(EXACT, "unconfirmed gate: false, as at runtime")
            return self.const("false")
        if t == "starved":
            self.note(APPROX, "mana-starved gate: read as false (the runtime derives it from what is affordable; no simulator value matches)")
            return self.const("false")
        if t == "stealth" and self.ids.cfg.get("stealth"):
            self.note(EXACT, "stealthed: the fight opens from Stealth (cast before the pull in every arm)")
            return {"auraIsActive": {"auraId": {"spellId": self.ids.cfg["stealth"]["aura"]}}}
        # stealth (a class with no opener from it here), totem, prev, tick and anything new
        self.note(LOST, "gate %s cannot be expressed: read as holding, the way the runtime treats an unreadable gate"
                  % json.dumps(g, separators=(",", ":")))
        return self.const("true")

    def convert(self, entries):
        """List entries -> simulator priorityList. Every entry and gate is reported."""
        out = []
        # Next-swing attacks (a tagged queue action: Heroic Strike, Cleave, Maul). The queue never
        # displaces one already queued by another (SpellQueue: a queued next-swing attack is never
        # displaced); the simulator replaces it, so each waits while another is queued (its queue
        # aura: the action's id with the same tag).
        queued = []
        for e in entries:
            rec = self.ids.action(e["id"])
            if rec is not None and rec.get("tag"):
                queued.append((e["id"], {"spellId": rec["id"], "tag": rec["tag"]}))
        for i, e in enumerate(entries, 1):
            jid = e["id"]
            self.line = "%2d %s (%d)" % (i, self.names.get(jid, "?"), jid)
            rec = self.ids.action(jid)
            if rec is None:
                self.note(LOST, "LINE OMITTED: " + self.ids.notes.get(jid, "no simulator action"))
                continue
            ref = {"spellId": rec["id"]}
            if rec.get("tag"):
                ref["tag"] = rec["tag"]
            self.note(EXACT, "cast -> simulator action %d%s [%s]" % (rec["id"], " tag %d" % rec["tag"] if rec.get("tag") else "",
                                                                     self.ids.notes.get(jid, "")))
            if e.get("delegated"):
                self.note(APPROX, "delegated entry: its source condition was given up at generation, so it is cast whenever "
                                  "ready at this position")
            gates = list(e.get("gates") or [])
            hold = None
            if self.rules:
                for k, g in enumerate(gates):
                    gates[k], said = self.rules.stack(e, g)
                    if said:
                        self.note(EXACT, "runtime: " + said)
                hold, said = self.rules.hold(e)
                if said:
                    self.note(EXACT, "runtime: " + said)
            action = {"castSpell": {"spellId": ref}}
            self.unkept = None
            conds = [self.gate(g) for g in gates]
            if self.unkept:
                self.note(LOST, "LINE OMITTED: cast to keep %d on the target, an aura the simulator does not have "
                                "(as written it would be pressed without end)" % self.unkept)
                continue
            if hold is not None:
                conds.append(hold)
            others = [ref_ for jid_, ref_ in queued if jid_ != jid] if rec.get("tag") else []
            for other in others:
                conds.append({"not": {"val": {"auraIsActive": {"auraId": dict(other)}}}})
            if others:
                self.note(EXACT, "runtime: waits while another next-swing attack is queued")
            if len(conds) == 1:
                action["condition"] = conds[0]
            elif conds:
                action["condition"] = {"and": {"vals": conds}}
            out.append({"action": action})
        return {"type": "TypeAPL", "priorityList": out}


# ---------------------------------------------------------------------------------------
# Character, target and request
# ---------------------------------------------------------------------------------------
def talent_layout(sim, cls):
    data = json.load(open(os.path.join(sim, "ui", "core", "talents", "trees", cls + ".json"), encoding="utf-8"))
    return [[(t["location"]["rowIdx"], t["maxPoints"]) for t in tree["talents"]] for tree in data]


def talent_points(sim, cls, build):
    """Talent name -> points for a talent string (every talent of the class is a key)."""
    data = json.load(open(os.path.join(sim, "ui", "core", "talents", "trees", cls + ".json"), encoding="utf-8"))
    trees = (build.split("-") + ["", ""])[:3]
    out = {}
    for tree, digits in zip(data, trees):
        for idx, talent in enumerate(tree["talents"]):
            out[talent["name"]] = int(digits[idx]) if idx < len(digits) else 0
    return out


# Talents a levelling build takes before anything else, per class: (tree, index in the talent string,
# ranks). Wand Specialization is the priest's and mage's first two points in the levelling guides
# (Documentation/forever-guides: "Wand Specialization 2/2 first"), while the simulator's presets
# are level 60 builds that reach it last or never: a level 13 priest had none.
LEVELLING_FIRST = ["Wand Specialization"]
# Wand Specialization: 13% wand damage per rank, 2 ranks (client talent spell 6057 is 13; the
# guides say 13% a rank for the priest too, whose spell 14524 reads 25).
WAND_SPEC_PER_RANK = 0.13


def talent_position(sim, cls, name):
    """(tree, index, max points) of the class's talent with this name, or None."""
    data = json.load(open(os.path.join(sim, "ui", "core", "talents", "trees", cls + ".json"), encoding="utf-8"))
    for tree, block in enumerate(data):
        for idx, talent in enumerate(block["talents"]):
            if talent.get("name") == name:
                return tree, idx, talent["maxPoints"]
    return None


def wand_spec_bonus(sim, cls, talents):
    """Fraction Wand Specialization adds to wand damage under this talent string (any class that
    has the talent)."""
    if not talents:
        return 0.0
    return WAND_SPEC_PER_RANK * talent_points(sim, cls, talents).get("Wand Specialization", 0)


def talents_for_level(sim, cls, tree_cfg, level):
    """The simulator's preset build for the tree, cut to the level's points (level - 9), after the
    class's levelling-first talents (LEVELLING_FIRST).

    Points go into the build's main tree in row order (the order of the talent string),
    then into the other trees in order. Once the level has the 31 points the last talent
    needs, one point is held back for it. Row gates (5 points per row) hold because the
    full build is valid and rows fill in order."""
    points = max(level - 9, 0)
    layout = talent_layout(sim, cls)
    full = [[int(c) for c in part] for part in (tree_cfg["talents"].split("-") + ["", ""])[:3]]
    for i in range(3):
        full[i] += [0] * (len(layout[i]) - len(full[i]))
    got = [[0] * len(layout[i]) for i in range(3)]
    order = [tree_cfg["main_tree"]] + [i for i in range(3) if i != tree_cfg["main_tree"]]
    main = order[0]
    last = len(layout[main]) - 1
    for name in LEVELLING_FIRST:
        where = talent_position(sim, cls, name)
        if not where:
            continue
        tree, idx, ranks = where
        take = min(ranks, points)
        got[tree][idx] = take
        full[tree][idx] = max(full[tree][idx], take)
        points -= take
    capstone = full[main][last] > 0 and points >= layout[main][last][0] * 5 + 1
    if capstone:
        points -= 1
    for tree in order:
        for idx, want in enumerate(full[tree]):
            if tree == main and idx == last and capstone:
                continue
            take = min(want - got[tree][idx], points)
            got[tree][idx] += take
            points -= take
    if capstone:
        spent_above = sum(got[main][:last])
        if spent_above >= layout[main][last][0] * 5:
            got[main][last] = 1
        else:
            points += 1
    return "-".join("".join(str(n) for n in tree).rstrip("0") for tree in got)


# --- Gear ------------------------------------------------------------------------------
# Item data comes from two real sources and nothing is invented:
#   - sim/planner/items.json.gz in the simulator: every client item with its stats already in
#     the simulator's stat indexes, weapon damage and speed, class, subclass, inventory type.
#   - Documentation/wow_spell_csv_forever/ItemSparse.*.csv here: name, required level, quality
#     and allowed classes from the Forever client. It does not hold every item; see info().
#   - assets/database/db.json in the simulator: where an item comes from (drop, quest,
#     crafted, vendor), for the items the simulator's authors curated.
# Known gaps, stated in every report: random-suffix world drops carry their stats in the
# suffix, and which suffixes an item can roll is in client tables this project does not
# have. An uncommon armour piece with no stats of its own is therefore given ONE assumed,
# class-suited suffix (CLASSES[...]["suffix"]) and marked as such; item "use" and proc
# effects exist only for items the simulator's own database knows; trinkets are not picked.
INV_SLOTS = {1: (0,), 2: (1,), 3: (2,), 16: (3,), 5: (4,), 20: (4,), 9: (5,), 10: (6,), 6: (7,), 7: (8,), 8: (9,),
             11: (10, 11), 12: (12, 13)}
SLOT_NAMES = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger 1",
              "finger 2", "trinket 1", "trinket 2", "main hand", "off hand", "ranged"]
GAME_SLOT = {"1": 0, "2": 1, "3": 2, "5": 4, "6": 7, "7": 8, "8": 9, "9": 5, "10": 6, "11": 10, "12": 11, "13": 12,
             "14": 13, "15": 3, "16": 14, "17": 15, "18": 16}   # WoW equipment slot -> simulator slot
INV_TYPE = {1: 1, 2: 2, 3: 3, 5: 5, 20: 5, 6: 8, 7: 9, 8: 10, 9: 6, 10: 7, 11: 11, 12: 12, 16: 4,
            13: 13, 14: 13, 17: 13, 21: 13, 22: 13, 23: 13, 15: 14, 25: 14, 26: 14, 28: 14}
WEAPON_TYPE = {0: 1, 1: 1, 4: 4, 5: 4, 6: 6, 7: 9, 8: 9, 10: 8, 13: 3, 15: 2}
HAND_TYPE = {13: 2, 21: 1, 22: 3, 14: 3, 23: 3, 17: 4}
# How far behind the character level each armour slot sits in the "average" setup: players
# do not replace everything at once. A fixed pattern, so runs are reproducible.
SLOT_LAG = {4: 0, 8: 1, 9: 2, 0: 2, 6: 3, 3: 3, 2: 4, 7: 5, 5: 6}
STAT_NAMES = {0: "strength", 1: "agility", 2: "stamina", 3: "intellect", 4: "spirit"}
GEAR_SETUPS = {
    "bare": "weapon only: the best uncommon weapon the level can equip, every other slot empty",
    "behind": "all uncommon, worn from 5 to 10 levels below the character, no jewellery",
    "average": "uncommon pieces up to 7 levels behind on a fixed per-slot lag, plus two lucky rare drops "
               "(the weapon and the chest) and uncommon jewellery where the client has any",
    "lucky": "rare in every slot that has one within 5 levels, the average pick elsewhere",
}


RETIRED_ITEM = re.compile(r"^(Deprecated|DEPRECATED|Monster - |TEST|Test |OLD |\[PH\])|\((old|OLD|test|TEST|DEPRECATED)\)")


class ItemPool:
    def __init__(self, sim, cls):
        import csv
        import glob
        import gzip
        self.cfg = CLASSES[cls]
        with gzip.open(os.path.join(sim, "sim", "planner", "items.json.gz"), "rt", encoding="utf-8") as handle:
            tables = json.load(handle)
        self.stats, self.bonus, self.rand_prop = tables["items"], tables["bonus"], tables["randProp"]
        files = sorted(glob.glob(os.path.join(ROOT, "Documentation", "wow_spell_csv_forever", "ItemSparse.*.csv")))
        if not files:
            raise SystemExit("ItemSparse CSV not found under Documentation/wow_spell_csv_forever")
        self.client_file = os.path.basename(files[-1])
        self.meta = {}
        with open(files[-1], encoding="utf-8", newline="") as handle:
            reader = csv.reader(handle)
            head = next(reader)
            col = dict((name, head.index(name)) for name in
                       ("ID", "Display_lang", "AllowableClass", "RequiredLevel", "OverallQualityID"))
            for row in reader:
                self.meta[row[col["ID"]]] = (row[col["Display_lang"]], int(row[col["AllowableClass"]]),
                                             int(row[col["RequiredLevel"]]), int(row[col["OverallQualityID"]]))
        known = json.load(open(os.path.join(sim, "assets", "database", "db.json"), encoding="utf-8"))["items"]
        self.sim_db = dict((it["id"], it) for it in known)
        self.class_bit = 1 << (self.cfg["class_id"] - 1)
        self.wand_choice = None   # --wand: an item id, "none", or None for the rule in wand()

    def wand(self, level):
        """(item id or None, note). The rule: the highest-level uncommon wand an enchanter
        crafts that the level can equip, the wand a levelling caster is most often handed.
        Only wands in the simulator's own database carry damage and speed, so only those
        can be picked. --wand names one explicitly, or none."""
        if self.wand_choice == "none":
            return None, "no wand (--wand none)"
        wands = dict((iid, it) for iid, it in self.sim_db.items()
                     if it.get("rangedWeaponType") == 8 and it.get("weaponSpeed"))
        if self.wand_choice:
            iid = int(self.wand_choice)
            if iid not in wands:
                raise SystemExit("--wand %d: not a wand with damage in the simulator's database" % iid)
            return iid, " [named with --wand]"
        best = None
        for iid, it in wands.items():
            meta = self.meta.get(str(iid))
            crafted = any("crafted" in s for s in it.get("sources", []))
            if meta and crafted and meta[3] == 2 and 0 < meta[2] <= level and (best is None or meta[2] > best[0]):
                best = (meta[2], iid)
        if best is None:
            return None, "no crafted uncommon wand can be equipped at this level"
        return best[1], " [crafted wand, the same in every setup]"

    def info(self, iid):
        """(name, class mask, level the item is worn from, quality, estimated?) or None.

        The client table does not hold every item (old dungeon drops are missing from it)
        and some rows have no required level (quest rewards). For those the level is
        ESTIMATED as item level - 5, the usual gap for Classic items, and the report says so.
        Quality then comes from the simulator's own database."""
        rec = self.stats.get(str(iid))
        if rec is None:
            return None
        meta = self.meta.get(str(iid))
        known = self.sim_db.get(int(iid))
        if meta:
            name, mask, req, quality = meta
        elif known and known.get("quality"):
            name, mask, req, quality = known["name"], -1, 0, known["quality"]
        else:
            return None
        if req > 0:
            return name, mask, req, quality, False
        return name, mask, max(rec.get("il", 0) - 5, 1), quality, True

    def sources(self, iid):
        return sorted(set(k for s in self.sim_db.get(int(iid), {}).get("sources", []) for k in s))

    def prefer_sourced(self, cands):
        """Items with a recorded drop, quest or crafting source first, together with
        random-suffix world drops; other client-only items (no way to tell an event or
        promotional item from a drop) only when there are none."""
        sourced = [c for c in cands if self.sources(c[-1]) or self.suffix_base(c[-1])]
        return sourced or cands

    def assumed_bonus(self):
        """The suffix definition used for stat-less greens: among the definitions that give
        exactly the class's two suffix stats in equal shares, the median share. The client
        has several per suffix (different shares); which one an item uses is not known."""
        if not hasattr(self, "_assumed"):
            want = sorted(self.cfg.get("suffix", {}).get("stats", ()))
            found = []
            for bid, allocs in self.bonus.items():
                if sorted(int(a[0]) for a in allocs) == want and len(set(a[1] for a in allocs)) == 1:
                    found.append((allocs[0][1], int(bid)))
            found.sort()
            self._assumed = found[len(found) // 2][1] if found and want else None
        return self._assumed

    def suffix_base(self, iid):
        """An uncommon armour piece with no stats of its own besides armour and block: on this
        client its stats come from a random suffix attached when it drops. Only items with a
        real required level count: a stat-less item without one is usually a costume piece."""
        rec = self.stats.get(str(iid))
        meta = self.info(iid)
        if not rec or not meta or meta[3] != 2 or meta[4] or rec["c"] != 4 or rec["inv"] in (2, 11, 12):
            return False
        if any(k != "drop" for k in self.sources(iid)):
            return False   # crafted, quest and vendor items never roll a suffix
        return not any(v for k, v in rec.get("st", {}).items() if int(k) not in (26, 29, 30))

    def score(self, rec, iid=None):
        weights = self.cfg["stat_weights"]
        total = sum(weights.get(int(k), 0.0) * v for k, v in rec.get("st", {}).items())
        if iid is not None and self.assumed_bonus() and self.suffix_base(iid):
            total += sum(weights.get(k, 0.0) * v for k, v in self.suffix_stats(iid, [self.assumed_bonus()]).items())
        return total

    def candidates(self, level, quality, lo, hi, want):
        """(score, id) for items of the quality the class can use with required level in lo..hi."""
        out = []
        armor_ok = self.cfg["armor"](level)
        for iid, rec in self.stats.items():
            meta = self.info(iid)
            if not meta or meta[3] != quality or not (max(lo, 1) <= meta[2] <= hi):
                continue
            if RETIRED_ITEM.search(meta[0] or ""):
                continue   # a name the client marks as retired or internal: nobody wears it
            if meta[1] != -1 and not (meta[1] & self.class_bit):
                continue
            if not (0 <= rec.get("il", 0) - meta[2] <= 8):
                continue   # item level far from its level: event, promotional or scaled items
            src = self.sources(iid)
            if src and all(k == "soldBy" for k in src):
                continue   # vendor rewards (reputation, honour): not levelling gear
            if not want(rec):
                continue
            if rec["c"] == 4 and rec["inv"] != 16 and rec["s"] in (1, 2, 3, 4) and rec["s"] not in armor_ok:
                continue
            out.append((self.score(rec, iid), int(iid)))
        return sorted(out)

    def weapon_dps(self, rec):
        w = rec.get("w") or rec.get("r") or [0, 0, 1]
        return (w[0] + w[1]) / 2.0 / max(w[2], 0.1)

    def median(self, cands):
        return cands[len(cands) // 2][1] if cands else None

    def describe(self, iid, note=""):
        meta = self.info(iid) or (self.sim_db.get(iid, {}).get("name", "item %d" % iid), -1, 0, 0, True)
        name, _, req, quality, estimated = meta
        rec = self.stats.get(str(iid), {})
        src = self.sources(iid)
        return "%s (item %d, %s, level %d%s, item level %s, %s)%s" % (
            name, iid, {2: "uncommon", 3: "rare", 4: "epic"}.get(quality, "quality %d" % quality), req,
            " ESTIMATED" if estimated else " required", rec.get("il", "?"),
            "source: " + "/".join(src) if src else "no recorded source", note)

    def suffix_stats(self, iid, bonus):
        rec = self.stats[str(iid)]
        quality = (self.info(iid) or ("", -1, 0, 2, True))[3]
        name = {2: "Good", 3: "Superior", 4: "Epic", 5: "Epic"}.get(quality, "Good")
        index = 0 if rec["inv"] in (1, 5, 7, 17, 20) else 1 if rec["inv"] in (3, 6, 8, 10, 12) else \
            3 if rec["inv"] in (13, 21) else 4 if rec["inv"] in (15, 25, 26) else 2
        budget = (self.rand_prop.get(str(rec.get("il", 0))) or {}).get(name, [0] * 5)[index]
        out = {}
        for b in bonus:
            for stat, alloc in self.bonus.get(str(b), []):
                out[int(stat)] = out.get(int(stat), 0) + math.floor(alloc / 10000.0 * budget + 0.5)
        return out

    def sim_item(self, iid, slot, bonus=None):
        """(ItemSpec, custom SimItem or None). The simulator's own item is used when it has one."""
        if iid in self.sim_db and not bonus:
            return {"id": iid}, None
        rec = self.stats[str(iid)]
        stats = [0.0] * 44
        for k, v in rec.get("st", {}).items():
            if int(k) < len(stats):
                stats[int(k)] += v
        for k, v in (self.suffix_stats(iid, bonus) if bonus else {}).items():
            if k < len(stats):
                stats[k] += v
        item = {"id": iid, "name": (self.info(iid) or ("item %d" % iid,))[0], "type": INV_TYPE.get(rec["inv"], 0),
                "stats": stats, "ilvl": rec.get("il", 0)}
        if rec["c"] == 4 and rec["s"] in (1, 2, 3, 4):
            item["armorType"] = rec["s"]
        if rec["c"] == 2 or (rec["c"] == 4 and rec["s"] == 6):
            item["type"] = 13
            item["weaponType"] = 7 if rec["c"] == 4 else WEAPON_TYPE.get(rec["s"], 0)
            item["handType"] = HAND_TYPE.get(rec["inv"], 0)
            if slot == 16:
                # Client weapon subclass -> simulator ranged type (bow, gun, thrown, crossbow, wand).
                item["type"], item["rangedWeaponType"] = 14, {2: 1, 3: 3, 16: 6, 18: 2, 19: 8}.get(rec["s"], 1)
        w = rec.get("w") or rec.get("r")
        if w and len(w) == 3:
            item["weaponDamageMin"], item["weaponDamageMax"], item["weaponSpeed"] = w
        if iid in self.sim_db:
            item["id"] = 1700000000 + iid   # keep the simulator's own item; this copy adds the suffix stats
        return {"id": item["id"]}, item

    def build(self, setup, level):
        """A gear setup for the level -> (17 item specs, custom items, description lines)."""
        specs, custom, lines = [{} for _ in range(17)], [], []
        wcfg = self.cfg["weapon"]

        def put(slot, iid, note=""):
            bonus = None
            rec = self.stats.get(str(iid)) or {}
            skill = trainable_weapons(self.cfg["class_id"]).get(rec.get("s")) if rec.get("c") == ITEM_CLASS_WEAPON else None
            if skill:
                note += " [needs the %s skill]" % skill
            if self.assumed_bonus() and self.suffix_base(iid):
                bonus = [self.assumed_bonus()]
                gained = self.suffix_stats(iid, bonus)
                note += " [random-suffix drop; ASSUMED %s: %s]" % (
                    self.cfg["suffix"]["name"], ", ".join("+%d %s" % (v, STAT_NAMES.get(k, "stat %d" % k)) for k, v in sorted(gained.items())))
            spec, item = self.sim_item(iid, slot, bonus)
            specs[slot] = spec
            if item:
                custom.append(item)
            lines.append("%s: %s" % (SLOT_NAMES[slot], self.describe(iid, note)))

        def is_weapon(rec):
            return rec["c"] == 2 and rec["inv"] in wcfg["inv"] and rec["s"] in wcfg["subclasses"] and rec.get("w")

        def weapon(quality, lo, hi, best):
            cands = sorted((self.weapon_dps(self.stats[str(i)]), i)
                           for _, i in self.prefer_sourced(self.candidates(level, quality, lo, hi, is_weapon)))
            if not cands:
                return None
            return cands[-1][1] if best else self.median(cands)

        def armour(slot, quality, lo, hi, target=None):
            invs = [inv for inv, slots in INV_SLOTS.items() if slot in slots]
            cands = self.prefer_sourced([c for c in self.candidates(level, quality, lo, hi,
                                                                    lambda r: r["inv"] in invs and r["c"] == 4) if c[0] > 0])
            if target is not None and cands:
                near = min(abs(self.info(i)[2] - target) for _, i in cands)
                cands = [c for c in cands if abs(self.info(c[1])[2] - target) == near]
            return self.median(cands)

        armour_slots = [0, 2, 3, 4, 5, 6, 7, 8, 9]
        if setup == "bare":
            pick = weapon(2, 1, level, True)
            if pick:
                put(14, pick)
        elif setup == "behind":
            pick = weapon(2, level - 10, level - 5, False) or weapon(2, 1, level - 5, True)
            if pick:
                put(14, pick)
            for slot in armour_slots:
                pick = armour(slot, 2, level - 10, level - 5)
                if pick:
                    put(slot, pick)
        elif setup in ("average", "lucky"):
            rare = weapon(3, level - 5, level, False)
            pick = rare or weapon(2, level - 5, level, False) or weapon(2, 1, level, True)
            if pick:
                put(14, pick, " [lucky drop]" if rare else " [no rare weapon in range: uncommon]")
            for slot in armour_slots:
                base = armour(slot, 2, level - 7, level, level - SLOT_LAG[slot])
                want_rare = setup == "lucky" or slot == 4
                better = armour(slot, 3, level - 5, level) if want_rare else None
                if better:
                    put(slot, better, " [lucky drop]" if setup == "average" else "")
                elif base:
                    put(slot, base, " [no rare in range: uncommon]" if want_rare else "")
            for slot in (1, 10, 11):
                invs = [inv for inv, slots in INV_SLOTS.items() if slot in slots]
                quality = 3 if setup == "lucky" else 2
                cands = [c for c in self.candidates(level, quality, level - 7, level, lambda r: r["inv"] in invs)
                         if c[0] > 0 and {"id": c[1]} not in specs]
                if not cands and setup == "lucky":
                    cands = [c for c in self.candidates(level, 2, level - 7, level, lambda r: r["inv"] in invs)
                             if c[0] > 0 and {"id": c[1]} not in specs]
                if cands:
                    put(slot, self.median(self.prefer_sourced(cands)))
        else:
            raise SystemExit("unknown gear setup %r (use %s or file:<path>)" % (setup, ", ".join(GEAR_SETUPS)))
        if self.cfg.get("wand"):
            pick, note = self.wand(level)
            if pick:
                it = self.sim_db[pick]
                put(16, pick, "%s, %g-%g damage every %gs" % (note, it["weaponDamageMin"], it["weaponDamageMax"], it["weaponSpeed"]))
            else:
                lines.append("ranged: " + note)
        if self.cfg.get("ranged") and setup in GEAR_SETUPS:
            rcfg = self.cfg["ranged"]
            wanted = lambda r: (r["c"] == 2 and r["inv"] in (15, 26) and r["s"] in rcfg["subclasses"]
                                and (r.get("r") or r.get("w")))
            lo, hi = {"bare": (1, level), "behind": (level - 10, level - 5)}.get(setup, (level - 5, level))
            ranked = lambda cands: sorted((self.weapon_dps(self.stats[str(i)]), i) for _, i in self.prefer_sourced(cands))
            cands = ranked(self.candidates(level, 2, lo, hi, wanted))
            pick = (cands[-1][1] if setup == "bare" else self.median(cands)) if cands else None
            if not pick:
                cands = ranked(self.candidates(level, 2, 1, level, wanted))
                pick = cands[-1][1] if cands else None
            if pick:
                w = self.stats[str(pick)].get("r") or self.stats[str(pick)].get("w")
                put(16, pick, " [%s, %g-%g damage every %gs]" % (rcfg["note"], w[0], w[1], w[2]))
            else:
                lines.append("ranged: no %s passes the rule" % rcfg["note"])
        if self.cfg.get("dual") and setup in GEAR_SETUPS:
            learned = dual_wield_level()
            if learned and level < learned:
                lines.append("off hand: empty, Dual Wield is not learned before level %d (ASSUMED)" % learned)
            else:
                wcfg_dual = self.cfg["weapon"]
                wanted = lambda r: (r["c"] == 2 and r["inv"] in (13, 22) and r["s"] in wcfg_dual["subclasses"]
                                    and r.get("w"))
                lo, hi = (level - 10, level - 5) if setup == "behind" else (level - 7, level)
                pick = (self.median(self.prefer_sourced(self.candidates(level, 2, lo, hi, wanted)))
                        or self.median(self.prefer_sourced(self.candidates(level, 2, 1, level, wanted))))
                if pick:
                    put(15, pick)
                else:
                    lines.append("off hand: no one-hand weapon passes the rule")
        if self.cfg.get("shield") and setup in GEAR_SETUPS:
            wanted = lambda r: r["c"] == 4 and r["s"] == SUBCLASS_SHIELD and r["inv"] == 14
            lo, hi = (level - 10, level - 5) if setup == "behind" else (level - 7, level)
            pick = (self.median(self.prefer_sourced(self.candidates(level, 2, lo, hi, wanted)))
                    or self.median(self.prefer_sourced(self.candidates(level, 2, 1, level, wanted))))
            if pick:
                put(15, pick)
            else:
                lines.append("off hand: no shield passes the rule")
        empty = [SLOT_NAMES[i] for i in armour_slots + [1, 10, 11] if not specs[i]]
        if empty and setup != "bare":
            lines.append("empty (no item passes the rule): " + ", ".join(empty))
        return specs, custom, lines

    def from_file(self, path):
        """An explicit character: {"gear": {"<WoW slot 1-18>": {"item": id, "bonus": [ids], "enchant": id}}}.
        The same gear shape as the simulator planner's character message."""
        data = json.load(open(path, encoding="utf-8"))
        specs, custom, lines = [{} for _ in range(17)], [], []
        for key in sorted(data.get("gear", {}), key=int):
            piece = data["gear"][key]
            slot, iid = GAME_SLOT.get(str(key)), int(piece.get("item") or 0)
            if slot is None or not iid:
                continue
            if str(iid) not in self.stats and iid not in self.sim_db:
                lines.append("%s: item %d is in neither item table: SLOT LEFT EMPTY" % (SLOT_NAMES[slot], iid))
                continue
            spec, item = self.sim_item(iid, slot, piece.get("bonus")) if str(iid) in self.stats else ({"id": iid}, None)
            specs[slot] = spec
            if item:
                custom.append(item)
            note = ""
            if piece.get("enchant"):
                note += " [enchant %s not applied]" % piece["enchant"]
            if item and slot in (12, 13):
                note += " [stats only: its use or proc effect is not modelled]"
            lines.append("%s: %s" % (SLOT_NAMES[slot], self.describe(iid, note)))
        return specs, custom, lines, data


def expected_creatures(sim):
    """level -> (health, auto-attack damage per second, armour) from the simulator's copy of
    the client ExpectedStat table (sim/planner/expected_generated.go)."""
    text = open(os.path.join(sim, "sim", "planner", "expected_generated.go"), encoding="utf-8").read()
    build = re.search(r"build ([\d.]+)", text)
    rows = {}
    for m in re.finditer(r"\{([\d.]+), ([\d.]+), ([\d.]+), [\d.]+\},\s*// (\d+)", text):
        rows[int(m.group(4))] = (float(m.group(1)), float(m.group(2)), float(m.group(3)))
    return rows, (build.group(1) if build else "?")


GAP_NAMES = {-1: "one below", 0: "even", 1: "one above"}


def gap_scenarios(level, gaps):
    """One regular target per level gap (target level minus player level), for --gaps."""
    out = []
    for gap in gaps:
        if level + gap < 1:
            continue
        name = GAP_NAMES.get(gap, "%d %s" % (abs(gap), "below" if gap < 0 else "above"))
        out.append({"name": "L%d vs %d (%s)" % (level, level + gap, name), "target_level": level + gap, "elite": False})
    return out


def scenarios_for(level, health_mults=None):
    """The target set for a level. With health_mults, an even-level target at each multiple of
    its expected health instead: the same fight made shorter or longer, to find where an
    ability stops paying for itself."""
    if health_mults:
        return [{"name": "L%d vs %d (even), health x%g" % (level, level, mult), "target_level": level,
                 "elite": False, "hp_mult": mult} for mult in health_mults]
    return ([] if level < 2 else [
        {"name": "L%d vs %d (one below)" % (level, level - 1), "target_level": level - 1, "elite": False}]) + [
        {"name": "L%d vs %d (even)" % (level, level), "target_level": level, "elite": False},
        {"name": "L%d vs %d (one above)" % (level, level + 1), "target_level": level + 1, "elite": False},
        {"name": "L%d vs %d elite" % (level, level + 1), "target_level": level + 1, "elite": True},
    ]


def group_scenarios(level, top_level):
    """--group: the fights of a dungeon or raid party member at this level. Health is the player's
    share (ASSUMPTIONS party_share), so kill time is the party's. A grouped regular target is the
    short group fight; a dungeon pull is elite; a dungeon boss is two levels above; at the top
    level a raid boss is three above."""
    share = ASSUMPTIONS["party_share"]
    out = [
        {"name": "L%d grouped regular" % level, "target_level": level, "elite": False, "hp_mult": share},
        {"name": "L%d dungeon elite" % level, "target_level": level + 1, "elite": True, "hp_mult": share},
        {"name": "L%d dungeon boss" % level, "target_level": level + 2, "elite": True, "boss": True,
         "hp_mult": share * ASSUMPTIONS["dungeon_boss_health_mult"] / ASSUMPTIONS["elite_health_mult"]},
    ]
    if level >= top_level:
        out.append({"name": "L%d raid boss" % level, "target_level": level + 3, "elite": True, "boss": True,
                    "hp_mult": ASSUMPTIONS["raid_boss_health_mult"] / ASSUMPTIONS["elite_health_mult"]})
    return out


def scenario_health(scenario, creatures, level):
    """A scenario target's health: its level's expected health, elite and scenario multiples."""
    health = creatures[scenario["target_level"]][0]
    if scenario["elite"]:
        health *= ASSUMPTIONS["elite_health_mult"]
    return health * scenario.get("hp_mult", 1) * health_factor(scenario["target_level"] - level)


# The client's creature type of every bench target (CreatureType 7, Humanoid).
HUMANOID_TYPE = 7


def build_request(cls, level, talents, gear, scenario, creatures, rotation, iterations, seed):
    cfg = CLASSES[cls]
    eng = ENGAGEMENTS[cfg["engagement"]]
    if GROUP["on"] and not GROUP["tank"]:
        # The tank holds the target: it never hits the player, and melee stand behind it.
        eng = dict(eng, in_front=False, target_attacks_player=False)
    _, dps, armor = creatures[scenario["target_level"]]
    if scenario["elite"]:
        dps *= ASSUMPTIONS["elite_damage_mult"]
    health = scenario_health(scenario, creatures, level)
    stats = [0.0] * 44
    # Stat indexes are read from proto/common.proto by stat_index(); filled in by the caller.
    stats[scenario["_armor_idx"]] = armor
    stats[scenario["_health_idx"]] = health
    spec_field, spec_value = cfg["spec"]
    if cfg.get("spec_for_level"):
        spec_value = {"options": dict(spec_value.get("options", {}), **cfg["spec_for_level"](level))}
    if cfg.get("pets") and level < HUNTER_PET_LEVEL:
        spec_value = {"options": dict(spec_value.get("options", {}), **{cfg["pets"]["option"]: cfg["pets"]["none"]})}
    player = {
        "name": "bench", "race": gear[2].get("race") or cfg["race"], "class": cfg["proto_class"], "level": level,
        "knownSpells": gear[2].get("spells") or [],
        "equipment": {"items": gear[0]}, "database": {"items": gear[1]},
        "talentsString": talents, "consumes": {}, "buffs": {},
        "inFrontOfTarget": eng["in_front"], "rotation": rotation, spec_field: spec_value,
    }
    target = {"name": scenario["name"], "level": scenario["target_level"], "mobType": "MobTypeHumanoid", "stats": stats}
    raid = {"parties": [{"players": [player]}]}
    if eng.get("distance") is not None:
        player["distanceFromTarget"] = eng["distance"]
    # The target always swings at the character: its swing count is the clock kill time is
    # read from. When the engagement says it never hits, the swing does no damage, and a
    # hit for no damage causes no pushback in the simulator (sim/core/cast.go).
    hits = eng["target_attacks_player"]
    target.update({"minBaseDamage": dps * ASSUMPTIONS["target_swing_speed"] / 1.17 if hits else 0,
                   "damageSpread": ASSUMPTIONS["target_damage_spread"] if hits else 0,
                   "swingSpeed": ASSUMPTIONS["target_swing_speed"], "tankIndex": 0})
    raid["tanks"] = [{"type": "Player", "index": 0}]
    encounter = {"useHealth": True, "duration": 180, "targets": [target]}
    if PULL["mobs"] > 1:
        encounter = {"useHealth": False, "duration": PULL["seconds"], "durationVariation": 0,
                     "targets": [dict(target, name="%s %d" % (target["name"], i)) for i in range(PULL["mobs"])]}
    return {"raid": raid, "encounter": encounter,
            "simOptions": {"iterations": iterations, "randomSeed": seed, "ruleset": "RulesetForever"}}


RACES = {"human": "RaceHuman", "dwarf": "RaceDwarf", "nightelf": "RaceNightElf", "gnome": "RaceGnome", "orc": "RaceOrc",
         "tauren": "RaceTauren", "troll": "RaceTroll", "undead": "RaceUndead", "scourge": "RaceUndead"}


def character_overrides(sim, cls, data, say):
    """What an exported character file adds beyond gear: race, learned ranks, talents.

    Talents arrive as trait node / entry / rank and are placed in the simulator's talent
    string with the planner's table (sim/planner/traits_generated.go), which exists for
    the classes the planner supports. Anything that cannot be used is said, not guessed."""
    out = {}
    if data.get("class") and data["class"].lower() != cls:
        say("  - character file is a %s, the run is for %s: only its gear is used" % (data["class"], cls))
        return out
    race = RACES.get(str(data.get("race", "")).lower().replace(" ", ""))
    if race:
        out["race"] = race
    elif data.get("race"):
        say("  - race %r has no simulator name here: the class default race is used" % data["race"])
    if data.get("spells"):
        out["spells"] = [int(x) for x in data["spells"]]
        say("  - %d learned spell ids sent as known spells: ability ranks follow them, not the level" % len(out["spells"]))
    picks = data.get("talents") or []
    if picks:
        text = open(os.path.join(sim, "sim", "planner", "traits_generated.go"), encoding="utf-8").read()
        block = re.search(r'"%s": \{(.*?)\n\t\},' % cls.upper(), text, re.S)
        if not block:
            say("  - talents: the simulator has no trait table for %s, so the level-derived build is used" % cls)
            return out
        slots = dict((int(m.group(1)), (int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))))
                     for m in re.finditer(r"(\d+): \{Tree: (\d+), Index: (\d+), MaxRank: (\d+), Node: (\d+)", block.group(1)))
        by_node = dict((v[3], v) for v in slots.values())
        trees, unknown = [[0] * 20 for _ in range(3)], 0
        for pick in picks:
            slot = slots.get(int(pick.get("entry", 0))) or by_node.get(int(pick.get("node", 0)))
            if not slot:
                unknown += 1
                continue
            trees[slot[0]][slot[1]] = min(int(pick.get("rank", 0)), slot[2])
        out["talents"] = "-".join("".join(str(n) for n in tree).rstrip("0") for tree in trees)
        say("  - talents from the file: `%s`%s" % (out["talents"], " (%d picks not in the trait table, left out)" % unknown if unknown else ""))
    return out


def stat_index(sim, name):
    text = open(os.path.join(sim, "proto", "common.proto"), encoding="utf-8").read()
    block = text[text.index("enum Stat {"):]
    return int(re.search(r"\b%s = (\d+);" % name, block).group(1))


def with_prepull(rotation, cfg):
    """The rotation with the class's own pre-pull casts (PREPULL), each on the character itself."""
    casts = PREPULL.get(cfg["class_id"], [])
    if not casts:
        return rotation
    actions = [{"action": {"castSpell": {"spellId": {"spellId": sid}, "target": {"type": "Self"}}},
                "doAtValue": {"const": {"val": "%gs" % at}}} for sid, at in casts]
    return dict(rotation, prepullActions=actions)


# Pre-pull casts that absorb hits (Power Word: Shield, rank 1): while one holds, a cast is not
# pushed back, and the queue in game prices it unhindered (SpellQueue.NoteAbsorbedHit).
SELF_SHIELDS = {17}
# What a levelling character casts on itself before every pull, in every arm, by class id: the
# rank-1 id (the level's rank is chosen like every other id) and when, in seconds before the pull.
# A rogue opens from Stealth; a priest shields first, as the levelling guides say ("shield and
# Renew before the pull"): absorbed hits push no cast back.
PREPULL = {4: [(1784, -1.0)], 5: [(17, -1.5)]}


# A cooldown this long is not ready for every fight. The bench gives it only to a boss: on any
# other target an arm (a preset, the list, the cooldown arm) fights without it. The simulator's
# own autocast of its major cooldowns is not reached by this.
ONCE_PER_RUN_MS = 600000


def once_per_run_ids():
    """Client spell ids (every rank) whose cooldown is ONCE_PER_RUN_MS or longer."""
    out = set()
    for r in client_rows("SpellCooldowns"):
        try:
            ms = max(int(r.get("RecoveryTime") or 0), int(r.get("CategoryRecoveryTime") or 0))
        except ValueError:
            continue
        if ms >= ONCE_PER_RUN_MS and r["SpellID"].isdigit() and r.get("DifficultyID", "0") == "0":
            out.add(int(r["SpellID"]))
    return out


def without_spells(rotation, drop):
    """A fixed simulator rotation without the priority entries that cast one of these spells."""
    def casts(node):
        found = []
        walk(node, lambda n: found.append(n["castSpell"].get("spellId", {}).get("spellId"))
             if isinstance(n.get("castSpell"), dict) else None)
        return any(sid in drop for sid in found)
    rotation = dict(rotation)
    rotation["priorityList"] = [item for item in rotation.get("priorityList", []) if not casts(item.get("action", {}))]
    return rotation


def strip_prepull(rotation):
    rotation = dict(rotation)
    rotation.pop("prepullActions", None)
    rotation["type"] = "TypeAPL"
    return rotation


# One simulator run is stopped after this long: a list that casts a free, instant, cooldown-less
# action forever never advances the simulator's clock.
RUN_TIMEOUT = {"seconds": 180}
TIMED_OUT = set()   # (arm, level) that never finished: not run again at that level
# Processor threads one simulator run may use (GOMAXPROCS). Half the machine by default:
# the simulator otherwise takes every core. It also runs at the lowest scheduling priority, so
# a game or anything else in use gets the processor first (--normal-priority turns that off).
SIM_THREADS = {"n": max(1, (os.cpu_count() or 2) // 2), "low_priority": True}


def low_priority_args():
    """subprocess arguments that start a child at the lowest scheduling priority."""
    if not SIM_THREADS["low_priority"]:
        return {}
    if os.name == "nt":
        return {"creationflags": getattr(subprocess, "IDLE_PRIORITY_CLASS", 0x40)}
    return {"preexec_fn": lambda: os.nice(19)}


def run_cli(cli, request, keep, label):
    folder = keep or tempfile.mkdtemp(prefix="jac_simbench_")
    os.makedirs(folder, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9]+", "_", label)
    infile, outfile = os.path.join(folder, safe + ".request.json"), os.path.join(folder, safe + ".result.json")
    json.dump(request, open(infile, "w", encoding="utf-8"), indent=1)
    try:
        proc = subprocess.run([cli, "sim", "--infile", infile, "--outfile", outfile], capture_output=True, text=True,
                              timeout=RUN_TIMEOUT["seconds"],
                              env=dict(os.environ, GOMAXPROCS=str(SIM_THREADS["n"]),
                                       WOWSIM_PULL_MODEL="1" if PULL_MODEL["on"] else "0"), **low_priority_args())
    except subprocess.TimeoutExpired:
        return None, "the simulator did not finish within %d s (a rotation that never advances time)" % RUN_TIMEOUT["seconds"]
    if proc.returncode != 0 or not os.path.exists(outfile):
        return None, (proc.stderr or proc.stdout).strip()[-400:]
    result = json.load(open(outfile, encoding="utf-8"))
    if result.get("error"):
        return None, json.dumps(result["error"])[:400]
    return result, None


# The pull model (the simulator's local sim/core/pull_model_local.go, on unless --no-pull-model):
# the target does not attack until the player's first attack lands and then has to reach a player
# at range; a pet sent from range has to reach the target; the fight is timed from that first
# landing. APPROACH_YARDS_PER_SECOND must equal the simulator's PullApproachYardsPerSecond.
PULL_MODEL = {"on": True}
FIXED_IDS.update(cfg["stealth"]["aura"] for cfg in CLASSES.values() if cfg.get("stealth"))
APPROACH_YARDS_PER_SECOND = 7.0
MELEE_YARDS = 5.0


# The queue's weapon stage (SpellQueue._SpellBeatsWeapon and _PrepareWeaponFillers in
# SpellQueueForever.lua): a single-target cast-time spell with no damage over time is pressed over
# the wand only while it deals more per second, its cast lengthened by the hits expected to push
# it back. The simulator presses a list as written, so without this a caster spent the fight
# casting Smite under pushback where the game switches to the wand (a level 13 priest: 20.9 s
# against about 10 s in game).
PUSHBACK_FIRST, PUSHBACK_STEP, PUSHBACK_FLOOR = 1.0, 0.2, 0.2   # sim/core/cast.go
GCD_SECONDS = 1.5


def pushed_cast_seconds(cast, swing):
    """A cast's expected length while the target swings every `swing` seconds and every hit lands:
    each hit adds 1.0 s, then 0.2 s less per hit, never under 0.2 s."""
    elapsed, hits = cast, 0
    while swing > 0 and hits < 20 and (hits + 1) * swing <= elapsed:
        elapsed += max(PUSHBACK_FLOOR, PUSHBACK_FIRST - PUSHBACK_STEP * hits)
        hits += 1
    return elapsed


@functools.lru_cache(maxsize=None)
def weapon_rule_spells(cls):
    """rank-1 id -> [(learn level, growth cap, cast seconds, mean hit, per level)] for each rank of
    a class ability the weapon stage weighs: a cast time, a direct hit, no damage over time. From
    the client spell tables, the same the generator reads."""
    import check_forever_apl as cfa
    levels = {}
    for r in cfa.rows("SpellLevels"):
        if r["DifficultyID"] == "0":
            levels[r["SpellID"]] = (int(float(r["SpellLevel"] or 0) or float(r["BaseLevel"] or 0)),
                                    int(float(r["MaxLevel"] or 0)))
    casts = dict((r["ID"], float(r["Base"] or 0) / 1000.0) for r in cfa.rows("SpellCastTimes"))
    cast_of = dict((r["SpellID"], casts.get(r["CastingTimeIndex"], 0.0)) for r in cfa.rows("SpellMisc")
                   if r["DifficultyID"] == "0")
    hit, periodic = {}, set()
    for r in cfa.rows("SpellEffect"):
        if r["DifficultyID"] != "0":
            continue
        if r["Effect"] == "2" and float(r["EffectBasePointsF"] or 0) > 0:
            hit[r["SpellID"]] = (float(r["EffectBasePointsF"]), float(r["EffectRealPointsPerLevel"] or 0))
        if r["Effect"] == "6" and r["EffectAura"] == "3":
            periodic.add(r["SpellID"])
    chains, _ = cfa.class_chains(cfa.CLASS_MASK[cls])
    out = {}
    for chain in chains.values():
        ranks = []
        for sid, _ in chain:
            if cast_of.get(sid, 0) > 0 and sid in hit and sid not in periodic:
                learn, cap = levels.get(sid, (0, 0))
                ranks.append((learn, cap, cast_of[sid], hit[sid][0], hit[sid][1]))
        if ranks:
            out[int(chain[0][0])] = sorted(ranks)
    return out


def spell_hit_at(ranks, level):
    """(cast seconds, mean hit) of the rank a level has, or None before the first rank."""
    have = [r for r in ranks if r[0] <= level]
    if not have:
        return None
    learn, cap, cast, points, per_level = have[-1]
    grown = max(0, (min(level, cap) if cap else level) - learn)
    return cast, points + per_level * grown


def wand_dps(gear, pool, bonus=0.0):
    """Damage per second of the wand a setup wears (with `bonus`, Wand Specialization), or None."""
    specs, custom = gear[0], gear[1]
    items = dict((it.get("id"), it) for it in custom if isinstance(it, dict))
    for spec in specs:
        iid = spec.get("id") if isinstance(spec, dict) else None
        it = items.get(iid) or pool.sim_db.get(iid)
        if it and it.get("rangedWeaponType") == 8 and it.get("weaponSpeed"):
            return (it["weaponDamageMin"] + it["weaponDamageMax"]) / 2.0 / it["weaponSpeed"] * (1 + bonus)
    return None


def weapon_rule_entries(entries, cls, cls_cfg, level, wand, approach):
    """The list as the queue presses it beside a wand: each weighed cast that loses to the wand
    once the target is on the character is pressed only before then. Returns (entries, notes)."""
    if not wand:
        return entries, []
    eng = ENGAGEMENTS[cls_cfg["engagement"]]
    spells = weapon_rule_spells(cls)
    out, notes = [], []
    for e in entries:
        info = spells.get(e["id"]) and spell_hit_at(spells[e["id"]], level)
        if not info:
            out.append(e)
            continue
        cast, mean = info
        free = mean / max(cast, GCD_SECONDS)
        hit = mean / max(pushed_cast_seconds(cast, ASSUMPTIONS["target_swing_speed"]), GCD_SECONDS)
        under_attack = hit if eng["target_attacks_player"] else free
        if under_attack > wand:
            out.append(e)
            continue
        shield = next((sid for sid, _ in PREPULL.get(cls_cfg["class_id"], []) if sid in SELF_SHIELDS), None)
        if free > wand and eng["target_attacks_player"] and (approach > 0 or shield):
            out.append(dict(e, gates=list(e.get("gates") or []) + [{"t": "bench_unhindered", "n": approach,
                                                                    "shield": shield}]))
            notes.append("%d: %.1f a second unhindered, %.1f pushed back, wand %.1f: cast only before the target "
                         "arrives (%.1f s)%s" % (e["id"], free, hit, wand, approach,
                                                  " or while the shield absorbs its hits" if shield else ""))
        else:
            notes.append("%d: %.1f a second at best, wand %.1f: left to the wand" % (e["id"], free, wand))
    return out, notes


def approach_seconds(cls_cfg):
    """How long the target needs to reach the character under the pull model."""
    distance = ENGAGEMENTS[cls_cfg["engagement"]].get("distance")
    if not PULL_MODEL["on"] or not distance or distance <= MELEE_YARDS:
        return 0.0
    return distance / APPROACH_YARDS_PER_SECOND


def summarize(result, swing_speed, approach=0.0):
    """One run -> damage per fight, kill time, casts per fight.

    Kill time is the simulator's mean iteration duration, which is the time of the killing
    event in a build with the local fight-length change (sim/core/sim.go Cleanup, 2026-11-23).
    An unchanged simulator reports its nominal duration there instead (600 s, or the
    encounter's own): then the target's melee swings are the clock, as before. It swings at
    t = 0 and every swing_speed seconds until the kill, so the mean kill time is
    swing_speed x (mean swings - 0.5). That clock moves in swing_speed steps and runs slow
    whenever the target's attacks are slowed (Thunder Clap: 20%), which made every list using
    such a slow look faster than it was; out["clock"] says which one a run used.

    Damage per fight includes the overkill of the last hit, so damage per second flatters
    large hits; compare kill times."""
    player = result["raidMetrics"]["parties"][0]["players"][0]
    n = result.get("iterationsDone") or player["dps"]["aggregatorData"]["n"]
    casts, damage, threat = {}, 0.0, 0.0
    for action in player.get("actions", []):
        ident = action.get("id", {})
        key = "%s%s" % (ident.get("spellId") or ident.get("otherId") or ident.get("itemId") or "?",
                         ":%d" % ident["tag"] if ident.get("tag") else "")
        tot = sum(t.get("casts", 0) for t in action.get("targets", []))
        dmg = sum(t.get("damage", 0.0) for t in action.get("targets", []))
        damage += dmg
        threat += sum(t.get("threat", 0.0) for t in action.get("targets", []))
        casts[key] = (tot / n, dmg / n)
    mana = -sum(r.get("gain", 0.0) for r in player.get("resources", [])
                if r.get("type") == "ResourceTypeMana" and r.get("gain", 0.0) < 0) / n
    # Damage taken comes from the targets' own actions: the player's damage-taken rate is divided
    # by the nominal duration and is unusable for a fight sized by health.
    swings, taken = 0, 0.0
    for target in result["encounterMetrics"]["targets"]:
        for action in target.get("actions", []):
            taken += sum(t.get("damage", 0.0) for t in action.get("targets", []))
            if action.get("id", {}).get("otherId") == "OtherActionAttack":
                swings += sum(t.get("casts", 0) for t in action.get("targets", []))
    out = {"n": n, "damage": damage / n, "taken": taken / n, "casts": casts, "mana": mana}
    if PULL["mobs"] > 1:
        out.update(kill=float("nan"), dps=damage / n / PULL["seconds"], tps=threat / n / PULL["seconds"])
        return out
    # Under the pull model the target's first swing comes `approach` seconds after the pull.
    swing_kill = swing_speed * (swings / n - 0.5) + approach if swings else float("nan")
    kill, clock = swing_kill, "target swings"
    exact = result.get("avgIterationDuration")
    if exact and 0 < exact < EXACT_CLOCK_BELOW:
        kill, clock = exact, "simulator"   # also a target killed before its first swing
    if kill != kill:
        out.update(kill=float("nan"), dps=float("nan"))
        return out
    out.update(kill=kill, dps=damage / n / kill, clock=clock, swing_kill=swing_kill, tps=threat / n / kill)
    return out


# A mean iteration duration below this (seconds) is a real kill time: an unchanged simulator
# reports its nominal duration (600 s, or the bench's own 180 s cap) for every health-sized fight.
EXACT_CLOCK_BELOW = 179.0


# Two-sided 95% Student t quantiles by degrees of freedom (batch means).
T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
       11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 19: 2.093, 24: 2.064, 29: 2.045}


def mean_ci(values):
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return mean, float("nan"), float("nan")
    sd = math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1))
    t = 1.96 if n > 30 else T95[max(k for k in T95 if k <= n - 1)]
    half = t * sd / math.sqrt(n)
    return mean, mean - half, mean + half


def merge_casts(batches):
    keys = set(k for b in batches for k in b["casts"])
    return dict((k, (sum(b["casts"].get(k, (0, 0))[0] for b in batches) / len(batches),
                     sum(b["casts"].get(k, (0, 0))[1] for b in batches) / len(batches))) for k in keys)


# ---------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--sim", required=True, help="WoW Forever simulator checkout")
    ap.add_argument("--cli", help="built wowsimcli executable (default: wowsimcli.exe or wowsimcli in the simulator "
                                  "checkout, where its own .gitignore expects the build)")
    ap.add_argument("--class", dest="cls", default="warrior", choices=sorted(CLASSES))
    ap.add_argument("--tree", default="arms")
    ap.add_argument("--context", default="st", choices=("st", "cleave", "aoe"))
    ap.add_argument("--levels", help="comma-separated character levels (default 20,40; 25,40,60 for a tree the "
                                     "simulator only has at levels %s)" % ", ".join(str(x) for x in BRACKET_LEVELS))
    ap.add_argument("--gear", default="average",
                    help="comma-separated gear setups: %s, or file:<character json>. Every result row names its setup"
                         % ", ".join(GEAR_SETUPS))
    ap.add_argument("--iterations", type=int, default=1000, help="iterations per batch")
    ap.add_argument("--batches", type=int, default=10,
                    help="independent seeds per arm; intervals come from the spread of the batch means")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--no-dot-floor", action="store_true", help="leave out the runtime's no-new-DoT-on-a-dying-target rule")
    ap.add_argument("--without", help="comma-separated JustAC rank-1 ids: adds an arm that is the generated list "
                                      "minus these entries (an ablation; nothing is written back). Separate several "
                                      "groups with ';' for one arm each")
    ap.add_argument("--mana-floor", help="id=percent[,id=percent]: adds an arm in which each named entry is only cast "
                                         "at or above that mana percentage (the runtime's spend-while-mana-is-high rule "
                                         "for a filler; nothing is written back). Separate several arms with ';'")
    ap.add_argument("--health-mults", help="comma-separated multiples of the expected health of an even-level "
                                           "target: replaces the usual target set with one scenario per multiple")
    ap.add_argument("--engagement", choices=sorted(ENGAGEMENTS), help="how the character meets the target "
                    "(default: the class's own)")
    ap.add_argument("--pet", help="default: imp for a warlock, cat for a hunter from level 10 (an assumption). "
                                  "Warlock demon (none, imp, voidwalker, succubus, felhunter) or hunter pet family "
                                  "(cat, wolf, boar, ...). Pet and demon stats between the simulator's level brackets "
                                  "are interpolated (local change, an assumption)")
    ap.add_argument("--wand", help="wand item id from the simulator's database, or 'none' (default: the crafted "
                                   "uncommon wand the level can equip)")
    ap.add_argument("--stance", choices=sorted(STANCE_FORMS), help="warrior stance at the pull (default: the tree's own)")
    ap.add_argument("--loadout", help="weapon setup: 2h, shield or dw (dual wield) for a warrior (default: the tree's own)")
    ap.add_argument("--draft", help="a copy of Data/Forever/Rotations.lua holding a proposed list: adds the arm "
                                    "`draft`, the same tree and context read from that file")
    ap.add_argument("--new-source", help="a newer upstream presets folder: adds the arm `source-new`, the tree's "
                                         "source preset as it is there")
    ap.add_argument("--other-lists", help="comma-separated trees: adds an arm per tree, this tree's character "
                                          "following that tree's list (`list-<tree>`), for hybrid and early builds")
    ap.add_argument("--group", action="store_true",
                    help="dungeon and raid fights as a party member (implies --grouped): a grouped regular "
                         "target, a dungeon elite, a dungeon boss and, at level 60, a raid boss, each with the "
                         "player's share of the health; the tank holds the target unless the tree is a tank "
                         "tree (party share and boss health are ASSUMED). With --mobs, a grouped pack")
    ap.add_argument("--grouped", action="store_true",
                    help="answer the lists' 'in a group' condition as true (the bench still fights alone)")
    ap.add_argument("--listed-weapons", action="store_true",
                    help="keep to the weapon types the setup lists instead of every type the class can learn")
    ap.add_argument("--talents", help="talent string to use at every level instead of the derived build")
    ap.add_argument("--dual-wield-level", type=int, default=ASSUMED_DUAL_WIELD_LEVEL,
                    help="level a dual-wield setup gains its off-hand weapon (ASSUMED %d; not in the client data)"
                         % ASSUMED_DUAL_WIELD_LEVEL)
    ap.add_argument("--mobs", type=int, default=1, help="identical targets in the fight; above 1 the fight is a fixed "
                                                       "pull (--pull-seconds) and damage per second over it is reported")
    ap.add_argument("--pull-seconds", type=float, default=20.0, help="length of a multi-target pull")
    ap.add_argument("--no-runtime-rules", action="store_true",
                    help="run the lists alone, without the queue's rules outside them (stacking, slow-payoff hold, "
                         "dying-target and fast-fight DoT rules)")
    ap.add_argument("--no-weapon-rule", action="store_true",
                    help="press a caster's list as written, instead of leaving a cast-time spell to the wand where "
                         "the queue would (its weapon stage)")
    ap.add_argument("--no-pull-model", action="store_true",
                    help="start every fight at time zero with the target already swinging (the simulator's own "
                         "start), instead of at the player's first landed attack with the target and a pet having to "
                         "close the distance")
    ap.add_argument("--any-level", action="store_true",
                    help="run a tree at a level the simulator lacks its core attacks for (the coverage sweep, "
                         "tools/forever_sim_sweep.py, does this to show what is missing)")
    ap.add_argument("--justac-only", action="store_true",
                    help="run the generated list (and --draft) alone: no simulator preset, source preset or cooldown arm")
    ap.add_argument("--gaps", help="comma-separated level gaps (target level minus player level, e.g. --gaps=-3,-2,-1,0,1,2): "
                                   "replaces the usual target set with one regular target per gap")
    ap.add_argument("--health-scale", type=float, help="multiply every target's health by this factor")
    ap.add_argument("--calibrate", help="a JustAC SavedVariables file: scale target health so simulated kill times "
                                        "match the solo kills it recorded (the class, tree and gear here must be the "
                                        "ones that made those kills)")
    ap.add_argument("--calibrate-batches", type=int, default=3, help="batches per recorded kill when calibrating")
    ap.add_argument("--calibrate-quantile", type=float, default=0.75,
                    help="which measured/simulated ratio sets the health factor (default 0.75: lean toward fights "
                         "that run a little long, so real fights come in at or under the simulated ones)")
    ap.add_argument("--cooldown-gap", type=int,
                    help="try another level gap than the runtime's: a target this many levels above the player "
                         "releases the major cooldowns")
    ap.add_argument("--no-cooldown-arm", action="store_true",
                    help="leave out the justac+cooldowns arm (the list plus the class's major cooldowns it does not "
                         "name, pressed when cued)")
    ap.add_argument("--run-timeout", type=int, default=RUN_TIMEOUT["seconds"],
                    help="seconds before one simulator run is stopped and reported as failed")
    ap.add_argument("--threads", type=int, default=SIM_THREADS["n"],
                    help="processor threads the simulator may use (default: half the machine's)")
    ap.add_argument("--normal-priority", action="store_true",
                    help="run the simulator at normal priority instead of the lowest")
    ap.add_argument("--convert-only", action="store_true")
    ap.add_argument("--keep", help="folder for the request and result JSON of every run")
    ap.add_argument("--out", help="write the report (Markdown) here as well as to stdout")
    args = ap.parse_args()

    cls, cfg = args.cls, CLASSES[args.cls]
    if args.tree not in cfg["trees"]:
        raise SystemExit("--tree %r: %s has %s" % (args.tree, cls, ", ".join(sorted(cfg["trees"]))))
    tree_cfg = cfg["trees"][args.tree]
    for key in TREE_OVERRIDES:
        if key in tree_cfg:
            cfg[key] = tree_cfg[key]
    if args.engagement:
        cfg["engagement"] = args.engagement
    PULL_MODEL["on"] = not args.no_pull_model
    if not args.pet and cls in DEFAULT_PET:
        args.pet = DEFAULT_PET[cls]
    if args.pet:
        options = cfg["spec"][1].setdefault("options", {})
        if "summon" in options:
            demon = {"none": "NoSummon", "imp": "Imp", "voidwalker": "Voidwalker", "succubus": "Succubus",
                     "felhunter": "Felhunter"}.get(args.pet.lower())
            if not demon:
                raise SystemExit("--pet %r: use none, imp, voidwalker, succubus or felhunter" % args.pet)
            options["summon"] = demon
        elif cfg.get("pets"):
            families = dict((n.lower(), n) for n in cfg["pets"]["names"])
            families["none"] = cfg["pets"]["none"]
            if args.pet.lower() not in families:
                raise SystemExit("--pet %r: use none or one of %s" % (args.pet, ", ".join(sorted(families))))
            options[cfg["pets"]["option"]] = families[args.pet.lower()]
        else:
            raise SystemExit("--pet applies to a class with a pet")
    stance = args.stance or tree_cfg.get("stance")
    if stance:
        cfg["spec"] = (cfg["spec"][0], {"options": dict(cfg["spec"][1].get("options", {}), stance="WarriorStance" + stance)})
    form = stance or tree_cfg.get("form")
    allowed_levels = tree_cfg.get("levels") or cfg.get("levels")
    if not args.levels:
        args.levels = "25,40,60" if allowed_levels else "20,40"
    refused = [x for x in args.levels.split(",") if allowed_levels and int(x) not in allowed_levels]
    if refused and not args.convert_only and not args.any_level:
        raise SystemExit("--levels %s: the simulator has %s %s's core attacks only at levels %s"
                         % (",".join(refused), cls, args.tree, ", ".join(str(x) for x in allowed_levels)))
    loadout_name = args.loadout or tree_cfg.get("loadout")
    loadout = None
    if loadout_name:
        loadout = LOADOUTS.get(cls, {}).get(loadout_name)
        if not loadout:
            raise SystemExit("--loadout %r: use one of %s" % (loadout_name, ", ".join(sorted(LOADOUTS.get(cls, {})))))
        cfg["weapon"], cfg["shield"] = loadout["weapon"], loadout["shield"]
        cfg["dual"] = loadout.get("dual", False)
    if not args.listed_weapons:
        open_weapons(cfg)
    PULL["mobs"], PULL["seconds"] = max(1, args.mobs), args.pull_seconds
    GROUPED["on"] = args.grouped or args.group
    GROUP["on"] = args.group
    RUN_TIMEOUT["seconds"] = args.run_timeout
    SIM_THREADS["n"] = max(1, args.threads)
    SIM_THREADS["low_priority"] = not args.normal_priority
    DUAL_WIELD["level"] = args.dual_wield_level
    if args.dual_wield_level == ASSUMED_DUAL_WIELD_LEVEL and loadout and loadout.get("dual_level"):
        DUAL_WIELD["level"] = loadout["dual_level"]
    classes, chains, names = load_rotations()
    lists = classes[cls.upper() + "_F"]
    entries = lists[args.tree][args.context]
    # The same character (this tree's build, gear and setup) following another tree's list: what
    # a player gets when the addon picks a tree their points do not really describe.
    other_arms = []
    for other in (args.other_lists.split(",") if args.other_lists else []):
        if other not in lists:
            raise SystemExit("--other-lists %r: no such tree for %s" % (other, cls))
        other_arms.append(("list-" + other, lists[other][args.context], None))
    floor = None if args.no_dot_floor else dot_floor_pct()
    data = None if args.no_runtime_rules or args.no_dot_floor else runtime_data()
    GROUP["tank"] = args.group and args.tree in _tree_sets(open(DEFAULTS_LUA, encoding="utf-8").read(),
                                                            "FOREVER_TANK_TREES").get(cls, set())

    def rules_for(level_delta, elite, level=None, boss=False):
        if data is None:
            return None
        return RuntimeRules(data, cls, args.tree, level_delta, elite, PULL["mobs"] > 1, args.cooldown_gap, level,
                            boss)

    ids = IdMap(args.sim, cls, chains)
    # The printed conversion is for an ordinary even-level target and the tree's full build; each
    # scenario is converted with its own level, kind and the talents the level has when it runs.
    conv = Converter(ids, names, cfg["engagement"], floor, rules_for(0, False),
                     talent_points(args.sim, cls, args.talents or tree_cfg["talents"]))
    justac = conv.convert(entries)

    lines = []
    say = lines.append
    say("# JustAC list vs simulator presets: %s %s (%s)" % (cls, args.tree, args.context))
    say("")
    say("## Conversion of the generated list")
    say("")
    counts = {EXACT: 0, APPROX: 0, LOST: 0}
    last = None
    for line, status, text in conv.report:
        counts[status] += 1
        if line != last:
            say("- `%s`" % line.strip())
            last = line
        say("  - %s: %s" % (status, text))
    say("")
    say("Totals: %d exact, %d approximated, %d not expressible." % (counts[EXACT], counts[APPROX], counts[LOST]))
    say("")
    say("## Can each entry be used in this setup?")
    say("")
    worn = tuple(cfg["weapon"]["subclasses"]) + tuple(cfg.get("ranged", {}).get("subclasses", ()))
    problems = usability_problems(entries, names, form, worn, cfg.get("shield", False), cfg.get("wand", False),
                                  cfg.get("forms"), cfg.get("form_spells"), cfg.get("form_word", "Stance"))
    if problems:
        say("In game the queue hides an entry the client reports unusable, and the simulator skips it too, so these "
            "are not list faults by themselves. They are what this setup rules out: when a core attack is here, the "
            "setup is not how the tree is played and the results do not describe it.")
        say("")
        for label, why in problems:
            say("- %s: %s" % (label, why))
    else:
        say("Every entry can be used in this setup's stance and equipment.")
    say("")
    if args.convert_only:
        say("```json")
        say(json.dumps(justac, indent=1))
        say("```")
        print("\n".join(lines))
        return
    if not args.cli:
        built = [os.path.join(args.sim, name) for name in ("wowsimcli.exe", "wowsimcli")]
        args.cli = next((path for path in built if os.path.isfile(path)), None)
    if not args.cli:
        raise SystemExit("no wowsimcli in %s: build it there (see the top of this file), pass --cli, "
                         "or use --convert-only" % args.sim)

    once_per_run = once_per_run_ids()
    # Every bench target is a humanoid (build_request). The runtime offers a spell limited to other
    # creature types (Exorcism, Holy Wrath: Demons and Undead) only against them, so no arm has it.
    humanoid_bit = 1 << (HUMANOID_TYPE - 1)
    wrong_type = set(sid for sid, mask in (data or runtime_data())["creature_types"].items() if not mask & humanoid_bit)
    # (name, list entries converted per scenario, or a fixed simulator rotation)
    arms = [("justac", entries, None)]
    for group in (args.without or "").split(";"):
        if not group.strip():
            continue
        drop = set(int(x) for x in group.split(","))
        arms.append(("justac-without-" + "-".join(str(d) for d in sorted(drop)),
                     [e for e in entries if e["id"] not in drop], None))
    for group in (args.mana_floor or "").split(";"):
        if not group.strip():
            continue
        floors = dict((int(k), float(v)) for k, v in (pair.split("=") for pair in group.split(",")))
        gated = [dict(e, gates=list(e.get("gates") or []) + [{"t": "power", "res": "mana", "op": ">=", "n": floors[e["id"]],
                                                             "ispct": True}]) if e["id"] in floors else e for e in entries]
        arms.append(("justac-" + "-".join("%d-above-%g" % kv for kv in sorted(floors.items())), gated, None))
    if args.draft:
        # A proposed list, in the generated file's own format, run beside the current one.
        draft_classes, _, draft_names = load_rotations(args.draft)
        for sid, name in draft_names.items():
            names.setdefault(sid, name)
        arms.append(("draft", draft_classes[cls.upper() + "_F"][args.tree][args.context], None))
    arms += other_arms
    # The queue cues the class's major cooldowns (a glow) without putting them in the first
    # slot. This arm is a player who presses each one the list does not name when it is cued.
    listed = set(e["id"] for e in entries)
    cued = []
    if not args.no_cooldown_arm:
        cued = [i for i in ((data or runtime_data()).get("burst", {}).get(cls, [])) if i not in listed]
    if cued:
        arms.append(("justac+cooldowns", [{"id": i, "gates": []} for i in cued] + list(entries), None))
    if args.justac_only:
        arms = [arm for arm in arms if arm[0] != "justac+cooldowns"]   # ablations and drafts stay
    else:
        arms.append(("sim", None, strip_prepull(json.load(open(os.path.join(args.sim, tree_cfg["sim_preset"]), encoding="utf-8")))))
    src = os.path.join(PRESETS, tree_cfg.get("source_preset") or "none")
    if os.path.isfile(src) and not args.justac_only:
        arms.append(("source", None, strip_prepull(json.load(open(src, encoding="utf-8")))))
    if args.new_source:
        # A newer upstream presets folder, not yet vendored: the same preset as it is there.
        newer = os.path.join(args.new_source, tree_cfg.get("source_preset") or "none")
        if os.path.isfile(newer):
            arms.append(("source-new", None, strip_prepull(json.load(open(newer, encoding="utf-8")))))

    creatures, build = expected_creatures(args.sim)
    armor_idx, health_idx = stat_index(args.sim, "StatArmor"), stat_index(args.sim, "StatHealth")
    say("## Setup")
    say("")
    say("- Simulator: `%s`, ruleset Forever, %d batches of %d iterations per arm and scenario, the same seeds for every arm "
        "(base seed %d). Intervals are 95%% Student t intervals over the batch means; the comparison column pairs batches by seed."
        % (args.sim, args.batches, args.iterations, args.seed))
    say("- Kill time is the simulator's time of the killing event, or the target's swing count in a build without the "
        "local fight-length change (each level says which; see summarize in the tool). Damage per second is damage "
        "per fight divided by it. A negative last column means the arm kills faster than the simulator's preset.")
    say("- Arms: justac = `Data/Forever/Rotations.lua` %s/%s/%s; sim = `%s`; source = `tools/forever-apl-src/presets/%s`. "
        "Pre-pull actions removed from every arm." % (cls, args.tree, args.context, tree_cfg["sim_preset"],
                                                      tree_cfg.get("source_preset") or "(none: a hand-pinned list)"))
    say("- Spec: `%s`, options %s%s." % (cfg["spec"][0], json.dumps(cfg["spec"][1].get("options", {}), separators=(",", ":")),
                                       "; per level: " + (cfg["spec_for_level"].__doc__ or "").split("\n")[0]
                                       if cfg.get("spec_for_level") else ""))
    for caveat in tree_cfg.get("caveats", []):
        say("- CAVEAT: " + caveat)
    off_bracket = [x for x in args.levels.split(",") if int(x) not in BRACKET_LEVELS]
    by_level = bracket_only(args.sim, cls)
    if off_bracket and by_level:
        say("- CAVEAT: at level %s the simulator has nothing, or rank 0, for what these source files model (they "
            "are defined only at levels %s): %s. The same for every arm."
            % (", ".join(off_bracket), ", ".join(str(x) for x in BRACKET_LEVELS), ", ".join(by_level)))
    if cfg.get("pets"):
        say("- Pet: %s (%s)." % (cfg["spec"][1]["options"].get(cfg["pets"]["option"]), cfg["pets"]["note"]))
    if conv.ids.tables:
        say("- Ranks: the simulator gives each rank of %d spell families its own action id and registers only the ranks "
            "the level has, so every arm is rewritten per level to the highest rank the level has. A spell the level does "
            "not have is never cast." % len(conv.ids.tables))
    say("- Engagement: %s (%s). Race %s, no consumables or buffs; rage starts at 0, energy starts full (the simulator's own start)."
        % (cfg["engagement"], ENGAGEMENTS[cfg["engagement"]]["note"], cfg["race"]))
    if form or loadout:
        say("- Stance or form %s; weapons: %s." % (form or "none", loadout["note"] if loadout else "the class default"))
    skills = trainable_weapons(cfg["class_id"])
    if skills and not args.listed_weapons:
        say("- Weapon types: any the class can learn that fit the setup (%s). The client data does not say which "
            "skills a character starts with, so every weapon below names the skill it needs: it may have to be "
            "learned from a weapon master first. `--listed-weapons` keeps to the setup's own types."
            % ", ".join(sorted(set(skills.values()))))
    if data is None:
        say("- Runtime rules: off; the lists run alone.")
    else:
        say("- Runtime rules (SpellQueue.lua) applied per scenario: stacking to the full stack on an elite or higher-level "
            "target, the slow-payoff hold, the major-cooldown hold (the class's burst cooldowns wait for an elite, "
            "several enemies or a target three or more levels above, however long the fight lasts; slow payoffs wait "
            "%d s) and the dying-target and fast-fight rules for new damage "
            "over time. Not modelled: the weapon filler comparison, the pushback response, On the Move, the rest of the "
            "spellbook pool (learned abilities no list names) and every group rule (the bench fights alone)."
            % data["long_fight"])
    say("- Every fight starts with every cooldown ready, in every arm. The presets press theirs at once on any target; "
        "a levelling player has a multi-minute cooldown for one fight in several, so on ordinary targets the presets' "
        "lead from cooldowns is not one a player keeps.")
    if cued:
        say("- Arm justac+cooldowns: the list plus the class's major cooldowns it does not name (%s), cast when ready "
            "under the same hold. The queue cues these with a glow and never puts them in the first slot, so this arm is "
            "a player who presses the cue; `justac` is one who follows the first slot only."
            % ", ".join("%s %d" % (names.get(i) or ids.name_of(i) or "spell", i) for i in cued))
    if PULL["mobs"] > 1:
        say("- Pack: %d identical targets for a fixed %g s pull; the kill time column is empty and the comparison column "
            "compares damage per second (positive is more damage)." % (PULL["mobs"], PULL["seconds"]))
    say("- A cooldown of %d minutes or more is pressed only against a boss: every arm fights other targets without it "
        "(the simulator's autocast of its own major cooldowns is not reached)." % (ONCE_PER_RUN_MS // 60000))
    if GROUP["on"]:
        say("- Group fights (ASSUMED): the player deals %d%% of the party's damage, so a target has that share of its "
            "health; a dungeon boss has %gx and a raid boss %gx (already the player's share) a regular target's health; "
            "%s." % (100 * ASSUMPTIONS["party_share"], ASSUMPTIONS["dungeon_boss_health_mult"],
                     ASSUMPTIONS["raid_boss_health_mult"],
                     "a tank tree is hit as usual" if GROUP["tank"] else "the tank holds the target: no hits, melee behind it"))
    say("- Targets: client ExpectedStat build %s (health, armour, melee damage per second); elite = health x%g, damage x%g (assumed)."
        % (build, ASSUMPTIONS["elite_health_mult"], ASSUMPTIONS["elite_damage_mult"]))
    say("")

    pool = ItemPool(args.sim, cls)
    pool.wand_choice = args.wand
    if cfg.get("wand"):
        say("- Wand: needs a simulator build with the local wand attack (`sim/core/wand.go`, not upstream). Its model is "
            "assumed, not measured: the wand's own damage roll, ranged hit table, Arcane school, shooting stops for casts "
            "and global cooldowns and resumes 0.5s after. Spec options: %s."
            % json.dumps(cfg["spec"][1].get("options", {}), separators=(",", ":")))
    setups = [g.strip() for g in args.gear.split(",") if g.strip()]
    say("- Item data: stats from the simulator's `sim/planner/items.json.gz`; name, required level, quality and class from "
        "`Documentation/wow_spell_csv_forever/%s`. A stat-less uncommon armour piece is a random-suffix drop: it is given the ASSUMED suffix "
        "'%s' (which suffixes an item can really roll is not in the data) and marked; "
        "item use and proc effects exist only for items in the simulator's own database, trinkets are not picked." % (pool.client_file, cfg.get("suffix", {}).get("name", "none")))
    say("")
    if args.health_scale:
        HEALTH["scale"] = args.health_scale
    if args.calibrate:
        kills = recorded_kills(args.calibrate)
        say("## Fight length calibration")
        say("")
        if not kills:
            say("No solo kills recorded in `%s`; health is not scaled." % args.calibrate)
        else:
            setup = setups[0]
            say("Each recorded solo kill simulated with this class, tree and gear setup (`%s`), %d batches of %d. "
                "The records do not say which class or gear made a kill: a kill made by another character does not "
                "calibrate this one." % (setup, args.calibrate_batches, args.iterations))
            say("")
            say("| Creature | Level | Kind | Player level | Measured s | Simulated s | Measured / simulated |")
            say("|---|---|---|---|---|---|---|")
            ratios, by_gap = [], {}
            saved_scale, saved_gaps = HEALTH["scale"], HEALTH["by_gap"]
            HEALTH["scale"], HEALTH["by_gap"] = 1.0, {}
            for kill in kills:
                level = kill["plvl"]
                talents = args.talents or talents_for_level(args.sim, cls, tree_cfg, level)
                if setup.startswith("file:"):
                    specs, custom, _, data = pool.from_file(setup[5:])
                    gear = (specs, custom, character_overrides(args.sim, cls, data, lambda _line: None))
                else:
                    specs, custom, _ = pool.build(setup, level)
                    gear = (specs, custom, {})
                simulated = []
                for target_level in kill["levels"]:
                    sc = {"name": "calibration", "target_level": target_level, "elite": kill["elite"],
                          "_armor_idx": armor_idx, "_health_idx": health_idx}
                    rotation = Converter(ids, names, cfg["engagement"], floor,
                                         rules_for(target_level - level, kill["elite"], level),
                                         talent_points(args.sim, cls, talents)).convert(entries)
                    for batch in range(args.calibrate_batches):
                        request = build_request(cls, level, talents, gear, sc, creatures,
                                                ranks_for_level(rotation, conv.ids.tables, level), args.iterations,
                                                args.seed + batch * 1000003)
                        result, err = run_cli(args.cli, request, args.keep, "calibration_%s_%d_b%d"
                                              % (kill["name"], target_level, batch))
                        if result is not None:
                            simulated.append(summarize(result, ASSUMPTIONS["target_swing_speed"], approach_seconds(cfg))["kill"])
                if not simulated:
                    continue
                sim_kill = sum(simulated) / len(simulated)
                ratios.append(kill["seconds"] / sim_kill)
                gap = int(math.floor(sum(kill["levels"]) / float(len(kill["levels"])) - level + 0.5))
                by_gap.setdefault(gap, []).append(ratios[-1])
                say("| %s | %s | %s | %d | %.1f | %.1f | %.2f |" % (
                    kill["name"], "-".join(str(x) for x in (kill["levels"][0], kill["levels"][-1])) if len(kill["levels"]) > 1
                    else kill["levels"][0], "elite" if kill["elite"] else "normal", level, kill["seconds"], sim_kill,
                    ratios[-1]))
            HEALTH["scale"], HEALTH["by_gap"] = saved_scale, saved_gaps
            if ratios and not args.health_scale:
                HEALTH["scale"] = calibration_factor(ratios, args.calibrate_quantile)
                HEALTH["by_gap"] = dict((gap, calibration_factor(values, args.calibrate_quantile))
                                        for gap, values in by_gap.items())
            say("")
            say("Kill time follows health closely, so target health is scaled per level gap by the ratio at the %d%% "
                "point of that gap's kills. Leaning long on purpose: real fights should come in at or under the "
                "simulated ones%s." % (round(100 * args.calibrate_quantile),
                                       "; few kills, treat these as rough corrections" if len(ratios) < 5 else ""))
            if HEALTH["by_gap"]:
                say("")
                say("| Level gap | Kills | Health factor | Source |")
                say("|---|---|---|---|")
                measured = sorted(HEALTH["by_gap"])
                for gap in range(min(measured + [-3]), max(measured + [3]) + 1):
                    source = "measured" if gap in HEALTH["by_gap"] else (
                        "interpolated" if measured[0] < gap < measured[-1] else "nearest measured gap")
                    say("| %+d | %d | x%.2f | %s |" % (gap, len(by_gap.get(gap, [])), health_factor(gap), source))
        say("")
    if HEALTH["by_gap"]:
        say("- Target health scaled per level gap (table above).")
        say("")
    elif HEALTH["scale"] != 1.0:
        say("- Target health scaled by x%.2f for every scenario." % HEALTH["scale"])
        say("")
    jobs = []
    for setup in setups:
        file_level = None
        if setup.startswith("file:"):
            file_level = json.load(open(setup[5:], encoding="utf-8")).get("level")
        for level in ([int(file_level)] if file_level else [int(x) for x in args.levels.split(",")]):
            jobs.append((level, setup))
    jobs.sort(key=lambda job: job[0])
    for level, setup in jobs:
        talents = args.talents or talents_for_level(args.sim, cls, tree_cfg, level)
        label = "file:" + os.path.basename(setup[5:]) if setup.startswith("file:") else setup
        say("## Level %d, gear: %s" % (level, label))
        say("")
        say("- Gear setup `%s`: %s." % (setup, GEAR_SETUPS.get(setup, "explicit character file")))
        extra = {}
        if setup.startswith("file:"):
            specs, custom, gear_lines, data = pool.from_file(setup[5:])
            extra = character_overrides(args.sim, cls, data, say)
        else:
            specs, custom, gear_lines = pool.build(setup, level)
        if extra.get("talents") is not None:
            talents = extra["talents"]
        else:
            say("- Talents `%s` (%d points, derived from the level)." % (talents, max(level - 9, 0)))
        gear = (specs, custom, extra)
        for line in gear_lines:
            say("  - %s" % line)
        wand = None if args.no_weapon_rule else wand_dps(gear, pool, wand_spec_bonus(args.sim, cls, talents))
        if wand:
            _, rule_notes = weapon_rule_entries(entries, cls, cfg, level, wand, approach_seconds(cfg))
            say("- Weapon stage (the queue's wand-or-cast rule; --no-weapon-rule runs the list as written): %s."
                % ("; ".join(rule_notes) or "every weighed cast beats the wand"))
        say("")
        say("| Gear | Scenario | Target health | Arm | Kill time s (95% CI) | DPS (95% CI) | Damage taken per fight | "
            "vs sim preset, % (95% CI) | Threat per second |")
        say("|---|---|---|---|---|---|---|---|---|")
        cast_tables, clocks, drift = [], set(), []
        speed = ASSUMPTIONS["target_swing_speed"]
        health_mults = [float(x) for x in args.health_mults.split(",")] if args.health_mults else None
        gaps = [int(x) for x in args.gaps.split(",")] if args.gaps else None
        if args.group and PULL["mobs"] == 1:
            level_set = group_scenarios(level, TOP_LEVEL)
        elif args.group:
            # A dungeon pack: elites one level above, for the fixed pull.
            level_set = [{"name": "L%d dungeon pack of %d" % (level, PULL["mobs"]), "target_level": level + 1,
                          "elite": True}]
        elif gaps:
            level_set = gap_scenarios(level, gaps)
        else:
            level_set = scenarios_for(level, health_mults)
        for sc in level_set:
            sc["_armor_idx"], sc["_health_idx"] = armor_idx, health_idx
            health = scenario_health(sc, creatures, level)
            got = {}
            for name, arm_entries, fixed in arms:
                if (name, level) in TIMED_OUT:
                    continue   # this arm never finished at this level: said once, not retried
                rotation = fixed
                if rotation is not None and not sc.get("boss"):
                    rotation = without_spells(rotation, once_per_run)
                if arm_entries is not None:
                    pressed = arm_entries
                    if not sc.get("boss"):
                        pressed = [e for e in pressed if e["id"] not in once_per_run]
                    pressed = [e for e in pressed if e["id"] not in wrong_type]
                    if wand:
                        pressed, _ = weapon_rule_entries(arm_entries, cls, cfg, level, wand, approach_seconds(cfg))
                    rotation = Converter(ids, names, cfg["engagement"], floor,
                                         rules_for(sc["target_level"] - level, sc["elite"], level, sc.get("boss", False)),
                                         talent_points(args.sim, cls, talents)).convert(pressed)
                runs = []
                for batch in range(args.batches):
                    seed = args.seed + batch * 1000003   # the same seeds for every arm
                    request = build_request(cls, level, talents, gear, sc, creatures,
                                            ranks_for_level(with_prepull(rotation, cfg), conv.ids.tables, level),
                                            args.iterations, seed)
                    result, err = run_cli(args.cli, request, args.keep,
                                          "%s_%s_%s_b%d" % (os.path.basename(setup), sc["name"], name, batch))
                    if result is None:
                        if "did not finish" in err:
                            TIMED_OUT.add((name, level))
                            err += "; arm skipped for the rest of level %d" % level
                        say("| %s | %s | %d | %s | failed: %s | | |"
                            % (label, sc["name"], health, name, err.replace("|", "/").replace("\n", " ")))
                        runs = []
                        break
                    runs.append(summarize(result, speed, approach_seconds(cfg)))
                if runs:
                    got[name] = runs
                    clocks.update(r.get("clock") for r in runs if r.get("clock"))
                    drift.extend(abs(r["kill"] - r["swing_kill"]) for r in runs if r.get("clock") == "simulator" and r["swing_kill"] == r["swing_kill"])
            for name, _, _ in arms:
                if name not in got:
                    continue
                pack = PULL["mobs"] > 1
                kill = "-" if pack else "%.1f [%.1f, %.1f]" % mean_ci([r["kill"] for r in got[name]])
                dps = mean_ci([r["dps"] for r in got[name]])
                taken = sum(r["taken"] for r in got[name]) / len(got[name])
                rel = ""
                if name != "sim" and "sim" in got:
                    measure = "dps" if pack else "kill"
                    pairs = [100 * (a[measure] - b[measure]) / b[measure] for a, b in zip(got[name], got["sim"])]
                    rel = "%+.1f [%+.1f, %+.1f]" % mean_ci(pairs)
                tps = sum(r.get("tps", float("nan")) for r in got[name]) / len(got[name])
                say("| %s | %s | %d | %s | %s | %.1f [%.1f, %.1f] | %.0f | %s | %.1f |"
                    % ((label, sc["name"], health, name, kill) + dps + (taken, rel, tps)))
            cast_tables.append((sc["name"], dict((k, {"casts": merge_casts(v), "mana": sum(r["mana"] for r in v) / len(v)})
                                                 for k, v in got.items())))
        say("")
        if "target swings" in clocks:
            say("Kill time clock: the target's swing count (%g s steps). This simulator build does not report "
                "the fight's real length; the count runs slow while the target's attacks are slowed (Thunder "
                "Clap), so a list using such a slow looks faster than it is." % speed)
        elif clocks:
            # The two clocks must agree unless the target's attacks were slowed (Thunder Clap) or it
            # stopped swinging. 2026-11-23: a fault in the first fight-length change cut every fight
            # to the first iteration's length, and only this comparison showed it.
            say("Kill time clock: the simulator's own time of the killing event. Largest difference from the "
                "target-swing clock at this level: %.1f s (more than about %g s without a slow on the target is a fault)."
                % (max(drift) if drift else 0.0, speed / 2))
        clocks.clear()
        del drift[:]
        say("")
        say("Casts per fight (damage per fight in brackets), by simulator action id:")
        say("")
        for name, got in cast_tables:
            say("- %s" % name)
            for arm in got:
                parts = ["%s x%.2f (%.0f)" % (k, c, d) for k, (c, d) in sorted(got[arm]["casts"].items(), key=lambda kv: -kv[1][1])
                         # The simulator counts no casts for some spells (Execute) though they land: damage shows them.
                         if c > 0.005 or d > 0.5]
                spent = "; mana spent per fight %.0f" % got[arm]["mana"] if got[arm]["mana"] else ""
                say("  - %s: %s%s" % (arm, ", ".join(parts), spent))
        say("")

    text = "\n".join(lines)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")


if __name__ == "__main__":
    main()
