#!/usr/bin/env python3
# tools/gen_forever_rotations.py
#
# WoW Forever priority lists for every class and talent tree -> Data/Forever/Rotations.lua.
#
# Source 1: MythicSim's MIT-licensed Forever preset mirror vendored in
# tools/forever-apl-src/presets/ (engine commit in UPSTREAM_COMMIT; application
# preset source pinned in presets/catalog.json). Source 2: hand pins in
# tools/simc-apl-forever/ for healer damage fillers.
#
# Each entry keeps the gates JustAC can evaluate under secret values, in the same shape
# RotationImport already reads (buff / cd / debuff / execute / health / power / resource /
# stack / stealth / any / all), plus three Forever gates: `known` (IsPlayerSpell), `swing`
# (time to next auto attack, PLAYER_SWING) and `tick` (time to next energy tick). What no
# gate can express marks the entry `delegated`: it keeps its priority place, ungated.
# Ids are emitted as rank 1 of their chain; `rankChains` lets the runtime show the highest
# rank known. Spells no Forever class can learn (racials, items, removed abilities such as
# Tiger's Fury) are dropped and reported.
#
# Usage: python tools/gen_forever_rotations.py [--print|--coverage]
# --coverage emits a report-only JSON inventory without writing generated Lua.
import functools
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "forever-apl-src")
PINS = os.path.join(ROOT, "tools", "simc-apl-forever")
OUT = os.path.join(ROOT, "Data", "Forever", "Rotations.lua")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_forever_apl as cfa  # noqa: E402  (shared learnability + rank chains)
import gen_simc_rotations as gsr  # noqa: E402  (the SimC condition parser, for hand pins)
import gen_forever_defaults as gfd  # noqa: E402  (BURST: offensive cooldowns join the bar pool)

# class -> (default tree for characters with no talent points, {tree: source})
# A source is a vendored preset path stem or "pin:<file stem>" for a hand pin.
TREES = {
    "warrior": ("arms", {"arms": "presets/warrior/dps/arms",
                         "fury": "presets/warrior/dps/dps_reck",
                         "protection": "presets/warrior/protection/protection"}),
    "rogue": ("combat", {"assassination": "presets/rogue/dps/forever_mutilate",
                         "combat": "presets/rogue/dps/combat_sinister_strike",
                         "subtlety": "presets/rogue/dps/forever_hemorrhage"}),
    "paladin": ("retribution", {"holy": "pin:paladin_holy",
                                "protection": "presets/paladin/protection/p5",
                                "retribution": "presets/paladin/retribution/default"}),
    "priest": ("shadow", {"discipline": "presets/priest/dps/smite",
                          "holy": "presets/priest/dps/smite",
                          "shadow": "presets/priest/dps/shadow"}),
    "druid": ("feral", {"balance": "presets/druid/balance/launch",
                        "feral": "presets/druid/feralcat/default",
                        "feral_bear": "presets/druid/feralbear/default",
                        "restoration": "pin:druid_restoration"}),
    "shaman": ("enhancement", {"elemental": "presets/shaman/elemental/forever",
                               "enhancement": "presets/shaman/enhancement/forever",
                               "restoration": "pin:shaman_restoration"}),
    "hunter": ("beast_mastery", {"beast_mastery": "presets/hunter/dps/bm",
                                 "marksmanship": "presets/hunter/dps/mm",
                                 "survival": "presets/hunter/dps/sv_melee"}),
    "mage": ("frost", {"arcane": "presets/mage/dps/arcane",
                       "fire": "presets/mage/dps/fire",
                       "frost": "presets/mage/dps/frost"}),
    "warlock": ("affliction", {"affliction": "presets/warlock/dps/affliction",
                               "demonology": "presets/warlock/dps/demonic_pact",
                               "destruction": "presets/warlock/dps/destruction_conflag"}),
}
# Keeping your own timed buff up leads every list (Battle Shout, a paladin seal): the sims cast
# it before the pull and it outlasts their fight, so their in-combat line sits last, but on
# Forever it lapses mid-fight while levelling and every guide puts it first
# (forever-guides/). An entry qualifies when its only gate is its own buff being down.
# Forms and stances (no duration) keep the sim's place: the sims order those deliberately.
# Lists that lack one the guides call for get it, gated the same way (rank-1 ids).
ADD = {"warrior": [6673]}   # Battle Shout: the tank (Protection) sim list has none
# AoE abilities the sims leave out because their level-60 lists use a later one (Whirlwind),
# while a levelling character's AoE IS this one. Placed at the front of the cleave (2 targets)
# and aoe (3+) tiers, after the own-buff leads, ungated: the cooldown and the stance it needs
# are read live (rank-1 ids). Everything else in the 2-target tier stays the sim's own call on
# whether AoE beats single-target damage there.
AOE_LEAD = {"warrior": [6343]}   # Thunder Clap
# A pack attack leads from three targets: at two, a low-level Thunder Clap deals less than the
# single-target attacks it would displace, for more rage.
AOE_LEAD_TIERS = ["aoe"]

# Abilities the level-60 sims leave out but levelling play needs (tools/forever-guides, and the
# missing-abilities audit of 2026-10-07), by ability name; the build exits on one the class
# cannot learn. trees: which talent trees (None = all). tiers: which target-count lists (None
# = all). at: "front" (after the own-buff leads; listed order kept), "end", "after:<name>" or
# "before:<name>".
# gates: "dot" = keep-it-up on the target (sinks while it runs, never on a dying target),
# "stealth" = only from stealth. Melee abilities need no gate: out of range sinks them.
# move: the ability is already on the sim list - reposition that entry instead of adding a
# second one. Set gates to replace its source conditions when the adaptation calls for it.
# A gate may also be a raw gate dict. drop: remove the ability and all its copies from the tree's list
# and keep it out of the queue there (left out); a copy= row after it brings it back to its tiers.
# copy: add an entry even though the ability is already listed (a tier-specific placement).
# A sim may list an ability twice (an AoE-only or proc copy): move takes every copy, and an
# anchor is the copy tier_lists keeps (its last ungated entry, else its first).
EXTRA = {
    # Reactive melee attacks (usable only after a dodge, parry or kill) lead when lit; until then
    # the game reports them unusable and they trail. The sims omit them or keep them defensive.
    "warrior": [dict(spell="victory_rush", trees=["arms", "fury"], at="front"),
                # Hamstring's damage repays its rage only as Arms' spare-rage press (REGATE). As a
                # rage dump it cost Fury 2 to 6% from level 24 and Protection 16%, and as a
                # finisher on a dying target it changed nothing in any tree (2026-11-18 and
                # 2026-11-20 simulations): those trees leave it to the player.
                dict(spell="hamstring", trees=["fury", "protection"], drop=True),
                dict(spell="rend", trees=["protection"], at="before:heroic_strike", move=True),
                # Protection's Sunder follows its main attacks: ahead of them it delayed Revenge and
                # Shield Slam (2026-11-18 simulation, shield in Defensive Stance: 2 to 4% faster
                # kills on regular targets, 7 to 8% on elites and long fights at five stacks). One
                # application here; the runtime stacks it where stacks pay. Against a pack it spends
                # rage and a global cooldown on one enemy, so it leaves the list.
                dict(spell="sunder_armor", trees=["protection"], drop=True),
                dict(spell="sunder_armor", trees=["protection"], tiers=["st", "cleave"],
                     at="before:heroic_strike", copy=True,
                     gates=[{"t": "stack", "id": 7386, "op": "<", "n": 1, "tgt": True}]),
                # Spare rage against a pack (same simulation: 4% more damage on three, 8% on five).
                dict(spell="cleave", trees=["protection"], tiers=["aoe"], at="before:heroic_strike", w=True,
                     gates=[{"t": "power", "res": "rage", "op": ">=", "n": 30}]),
                # Against a pack Thunder Clap is the strongest attack and leads, as in Arms and Fury.
                dict(spell="thunder_clap", trees=["protection"], tiers=AOE_LEAD_TIERS,
                     at="front", move=True),
                # It deals damage, its slow a side effect, so one and two targets keep it where the
                # sim had it, after Shield Slam and Revenge (leaving it out there cost 6 to 15% at
                # every level, 2026-11-20 simulation).
                dict(spell="thunder_clap", trees=["protection"], tiers=["st", "cleave"],
                     at="after:revenge", copy=True),
                # Arms: Overpower > Mortal Strike > Execute > Slam; Rend only with a second
                # enemy; Sweeping Strikes leads multi-target play.
                dict(spell="mortal_strike", trees=["arms"], at="after:overpower", move=True),
                dict(spell="execute", trees=["arms"], at="after:mortal_strike", move=True),
                dict(spell="rend", trees=["arms"], tiers=["cleave", "aoe"], at="after:slam", move=True),
                # Untalented warriors use this list. Single target puts Rend (while missing) ahead
                # of Heroic Strike, as the levelling guides open (Charge, Rend, then Heroic
                # Strike): a priority list holds a cheaper spender for a higher one, so below it
                # Rend would wait on Heroic Strike's rage.
                dict(spell="rend", trees=["arms"], tiers=["st"], at="before:heroic_strike", gates=["dot"],
                     copy=True),
                dict(spell="sweeping_strikes", trees=["arms"], tiers=["cleave", "aoe"],
                     at="before:battle_stance"),
                # Fury (low attack power, i.e. levelling): Whirlwind > Execute > Bloodthirst >
                # Overpower > Rend.
                dict(spell="whirlwind", trees=["fury"], at="before:execute", move=True),
                dict(spell="bloodthirst", trees=["fury"], at="after:execute", move=True),
                dict(spell="rend", trees=["fury"], at="after:overpower", move=True)],
    # Serpent Sting opens: its DoT lands at once, and it is cast WITH Auto Shot, which is off the
    # GCD and follows it as the hunter's main damage; once running Auto Shot sinks with its timer.
    "hunter": [dict(spell="serpent_sting", at="front", move=True),
               dict(spell="auto_shot", at="front"),
               dict(spell="hunters_mark", at="front", gates=["dot"]),
               dict(spell="raptor_strike", at="front"),
               dict(spell="mongoose_bite", at="front"),
               # The Forever MM guide recommends Sniper Shot on cooldown ahead of Aimed Shot.
               # Its imported fight-duration mana gate is unavailable; spell usability still
               # determines whether Sniper Shot itself can be cast.
               dict(spell="sniper_shot", trees=["marksmanship"], at="before:aimed_shot",
                    move=True, gates=[]),
               # The Survival sim is melee only. Its guides keep the ranged shots for a target
               # out of melee (Arcane Shot, Multi-Shot on packs); last, so melee leads in range.
               dict(spell="counterattack", trees=["survival"], at="after:mongoose_bite"),
               dict(spell="multi_shot", trees=["survival"], tiers=["aoe"], at="end"),
               dict(spell="arcane_shot", trees=["survival"], at="end"),
               # Launch guides (read 2026-11-16). Beast Mastery keeps two hawks up ahead of
               # Aimed Shot; Multi-Shot is a multi-target shot for BM and MM.
               dict(spell="summon_hawk", trees=["beast_mastery"], at="before:aimed_shot", move=True),
               dict(spell="multi_shot", trees=["beast_mastery", "marksmanship"],
                    tiers=["cleave", "aoe"], at="after:aimed_shot", move=True),
               # Survival melee: Immolation Trap and hawks before Raptor Strike; Aimed Shot
               # joins the ranged shots for a target out of melee.
               dict(spell="immolation_trap", trees=["survival"], at="before:raptor_strike", move=True),
               dict(spell="summon_hawk", trees=["survival"], at="before:raptor_strike"),
               dict(spell="aimed_shot", trees=["survival"], at="before:arcane_shot")],
    # Launch Retribution guides: Consecration before Holy Strike; Holy Shock (Shockadin) on
    # cooldown after it. Exorcism on cooldown, and Holy Wrath against a pack: both only hit
    # Demons and Undead, which the queue reads from the target (SpellDB.GetCreatureTypeMask).
    "paladin": [dict(spell="consecration", trees=["retribution"], at="before:holy_strike", move=True),
                dict(spell="holy_shock", trees=["retribution"], at="after:holy_strike"),
                dict(spell="exorcism", trees=["retribution"], at="before:consecration"),
                dict(spell="holy_wrath", trees=["retribution"], tiers=["aoe"], at="after:consecration"),
                # Hammer of the Righteous (40): Protection's weapon strike on the target and up to
                # three more, 6 s cooldown (kami). No sim lists it; it joins Protection's attacks
                # ahead of Holy Strike. Holy and Retribution do not use it in any guide.
                dict(spell="hammer_of_the_righteous", trees=["protection"], at="before:holy_strike")],
    # Backstab is absent from the selected upstream APLs. Prefer it to Sinister Strike when
    # usable from behind, while keeping the tree's main builder (Mutilate, Hemorrhage) first.
    # Spell usability handles the rear requirement; no position signal is inferred here.
    # Launch guides open with Garrote; Cheap Shot stays as the opener when Garrote cannot be used.
    "rogue": [
              # Leveling guides (Method, Warcraft Tavern, read 2026-11-17) open Assassination and
              # Combat with Ambush (level 18) when a dagger is equipped, else Garrote. Spell
              # usability covers the dagger; Subtlety's sim already lists it. First of the
              # front entries, which keep their listed order.
              dict(spell="ambush", trees=["assassination", "combat"], at="front",
                   gates=["stealth"]),
              dict(spell="garrote", at="front", gates=["stealth", "dot"]),
              dict(spell="cheap_shot", at="front", gates=["stealth"]),
              # Assassination and Combat keep Rupture up and Eviscerate only once it runs.
              dict(spell="rupture", trees=["assassination", "combat"], at="before:eviscerate",
                   gates=[{"t": "resource", "res": "combo_points", "op": ">=", "n": 5}, "dot"]),
              dict(spell="riposte", at="front"),
              dict(spell="backstab", trees=["combat"], at="before:sinister_strike"),
              # Shank is the primary energy-gated attack before the Combat finisher.
              dict(spell="shank", trees=["combat"], at="before:eviscerate", move=True),
              dict(spell="sinister_strike", trees=["subtlety"], at="after:hemorrhage"),
              dict(spell="backstab", trees=["subtlety"], at="before:sinister_strike"),
              dict(spell="sinister_strike", trees=["assassination"], at="after:mutilate"),
              dict(spell="backstab", trees=["assassination"], at="before:sinister_strike")],
    "druid": [dict(spell="rake", trees=["feral"], at="front", gates=["dot"]),
              # The bear sim list has no rage starter. Enrage is the bear's Bloodrage and takes the
              # warrior lists' conditions for it: low rage, and health above half because it lowers
              # armor while it runs (2026-11-20 simulation: kills 6 to 16% faster on regular
              # targets at 25, 40 and 60, 4 to 5% on elites).
              dict(spell="enrage", trees=["feral_bear"], at="front", w=True,
                   gates=[{"t": "power", "res": "rage", "op": "<", "n": 10},
                          {"t": "health", "op": ">", "pct": 50.0}]),
              dict(spell="swipe", trees=["feral_bear"], tiers=["cleave", "aoe"], at="front", move=True),
              dict(spell="wrath", trees=["balance"], at="end")],
    "warlock": [dict(spell="conflagrate", trees=["destruction"], at="after:immolate"),
                # Launch fillers (level 40): Wrack (Affliction), Incinerate (Destruction);
                # Shadow Bolt stays behind them for lower levels.
                dict(spell="wrack", trees=["affliction"], at="before:shadow_bolt"),
                dict(spell="incinerate", trees=["destruction"], at="before:shadow_bolt"),
                dict(spell="shoot", at="end")],
    # Caster leveling guides describe wanding as a low-health/finishing fallback; keep Shoot last
    # so listed spells take precedence and spell usability hides it without a usable wand.
    "mage": [dict(spell="cone_of_cold", trees=["frost"], tiers=["cleave", "aoe"], at="front", move=True),
             # Fire's only Scorch line stacks Fire Vulnerability to five once Improved Scorch is
             # taken. Levelling fights end before the stacks pay for five Scorch casts: at level 30
             # leaving it out was 8 to 15% faster on ordinary targets with Improved Scorch 3/3 and
             # equal on elites, and 35 to 40% faster at 1/3, where a stack lands one cast in three
             # and the list cast Scorch about 13 times a fight (2026-11-23 simulation; no change at
             # 20 and 25, before the talent). The tree leaves Scorch to the player.
             dict(spell="scorch", trees=["fire"], drop=True),
             # The Arcane and Fire sims list no AoE spell. Guide AoE (forever-guides/): Fire
             # Flamestrike > Blast Wave > Arcane Explosion, Arcane Explosion at 3+ for Arcane.
             dict(spell="flamestrike", trees=["fire"], tiers=["aoe"], at="before:pyroblast"),
             dict(spell="blast_wave", trees=["fire"], tiers=["aoe"], at="before:pyroblast"),
             dict(spell="arcane_explosion", trees=["fire"], tiers=["aoe"], at="before:pyroblast"),
             dict(spell="arcane_explosion", trees=["arcane"], tiers=["aoe"], at="after:evocation"),
             # Launch guides: Arcane AoE opens with Flamestrike; Fire AoE adds Cone of Cold;
             # the Frostfire Bolt build (level 40 talent) fills with it instead of Fireball.
             dict(spell="flamestrike", trees=["arcane"], tiers=["aoe"], at="before:arcane_explosion"),
             dict(spell="cone_of_cold", trees=["fire"], tiers=["aoe"], at="after:blast_wave"),
             dict(spell="frostfire_bolt", trees=["fire"], at="before:fireball"),
             dict(spell="shoot", at="end"),
             # Arcane Blast is a level 20 talent, and the Arcane sim's other casts all wait on it
             # or on a proc. Until it is learned, Fireball fills, as Smite does for Shadow. After
             # it, Arcane Blast (unconditional, listed above) is always reached first.
             dict(spell="fireball", trees=["arcane"], at="before:shoot")],
    # Wanding is a documented leveling damage fallback across Priest trees; it is only usable
    # when the character has an appropriate wand equipped.
    "priest": [dict(spell="shoot", at="end"),
               # Shadow is also the untalented default; Smite fills before Shadow attacks
               # are learned rather than yielding to the listed wand fallback.
               dict(spell="smite", trees=["shadow"], at="before:shoot"),
               # The Smite sim has no Mind Blast, but every priest learns it at 10 and the
               # leveling guides (Method, read 2026-11-17) cast it on cooldown in every tree.
               # Placed as the Shadow list has it: after the damage over time, before the fillers.
               dict(spell="mind_blast", trees=["discipline", "holy"], at="before:holy_fire"),
               # Starshards (Night Elf, 10): a 6 s channel, 162 damage at rank 1 for 50 mana on a
               # 30 s cooldown (client data), about Mind Blast's damage per second and twice
               # Smite's at 10 to 16. No sim or guide lists it; placed after Mind Blast, as
               # Devouring Plague (another race spell) sits by the damage over time. Chastise
               # (Dwarf) stays with the player: one Smite of damage per 2 min, and its root is
               # crowd control (tools/test_closed_lists.py).
               dict(spell="starshards", trees=["discipline", "holy"], at="after:mind_blast"),
               dict(spell="starshards", trees=["shadow"], at="before:mind_flay"),
               dict(spell="holy_nova", tiers=["cleave", "aoe"], at="front")],
}


# Hand-reviewed safety gates, by ability name; every entry is flagged w ("offer only when the
# gates hold": when they fail it trails the queue instead of waiting as a sunk "soon").
#   starved: its sim mana line widens to "or the rotation cannot be paid for" (read per build) -
#            a fixed mana line misses a low-level caster whose filler costs a fifth of the bar.
#   health:  only with health above this percent - it costs health (Life Tap, Bloodrage) or
#            burns the caster too (Hellfire).
#   near:    only when close enough for point-blank damage the data cannot show (Hellfire
#            burns from a self aura; core rule 5 derives the rest).
#   execute: only while the target is below this percent (Shadowburn spends a soul shard;
#            the Forever guides keep it for a dying target, which refunds the shard).
#   or_known: ...or whenever this talent is known: with Shadow and Flame the launch
#            Destruction guide uses Shadowburn on cooldown (good enough without timing its
#            buff, whose id is not in the data).
#   or_none_known: its resource condition also holds while none of these spells is learned.
#            Heroic Strike waits for excess rage, but before a warrior learns a main rage
#            spender all rage is excess: otherwise Hamstring (which waits only on those
#            spenders being unavailable) spends every point for little damage (2026-11-17
#            level-8 capture). Once one is learned the original condition returns.
#   needs_known: only once at least one of these spells is learned. Hamstring "with spare
#            rage" has no spare rage before a main spender exists: at 10-14 rage it would
#            otherwise spend what Heroic Strike (15) is building toward.
#   drop_cast: remove the source's cast-time condition; the guide keeps the spell without the
#            talent that shortens its cast (launch Affliction keeps Immolate up, launch Arms
#            keeps Slam; the sims cast them only once a talent shortens the cast). An entry left with no
#            condition stays delegated (Slam); one that keeps a timeable condition does not
#            (Immolate). Neither is flagged w.
#   trees:   limit the entry to these trees (default: every tree).
#   at:      {tree: {resource: n}}: in that tree the entry's "resource >= ..." condition asks for
#            n instead of the source's number. `was` ({tree: {resource: n}}) names the source's
#            number where the value is taken ahead of a source refresh: the build stops when
#            the source no longer says it, so the row is revisited instead of going stale.
#   drop:    {tree: [gate pattern]}: in that tree, conditions matching a pattern leave the
#            entry. A pattern is the gate fields to match; `has` matches a group by a member.
#   add:     {tree: [gate]}: in that tree the entry also needs these conditions.
#   A row with only trees / at / was / drop / add changes conditions and nothing else: the entry is
#   not flagged w and keeps its place among the timed entries.
#   A spell list may instead be a {tree: [names]} dict (a talent style's own spenders); a tree it
#   does not name is skipped.
WARRIOR_SPENDERS = {"arms": ["mortal_strike", "slam", "whirlwind", "bloodthirst"],
                    "fury": ["mortal_strike", "slam", "whirlwind", "bloodthirst"],
                    "protection": ["revenge", "shield_slam"]}
# Hamstring "with spare rage" (Arms only; EXTRA keeps it out of Fury and Protection): Arms keeps
# its sim's own cooldown conditions, so knowing a spender is enough (5 to 7% faster at 20).
ENERGY_FLOOR = {"t": "power", "res": "energy", "op": ">="}
HEATING_UP_BRANCH = {"t": "all", "has": {"t": "known", "id": 400624}}
IN_A_GROUP = {"t": "group"}
CONDITIONS_ONLY = {"trees", "at", "was", "drop", "add"}   # REGATE options that add no safety gate
REGATE = {
    "warlock": {"immolate": dict(drop_cast=True, trees=["affliction"]),
                "life_tap": dict(starved=True, health=50),
                "hellfire": dict(health=50, near=10),
                "shadowburn": dict(execute=20, or_known=426316)},
    # The Arcane sim's whole single-target branch asks for the Heating Up talent (400624).
    # Recovering mana and spending a Missile Barrage proc do not depend on it: without them an
    # Arcane mage who has not taken it casts Arcane Blast until the mana is gone (2026-11-20
    # simulation: kills 62% faster at 60, long fights 20 to 65% faster; no change on short
    # low-level fights). The sim's other Heating Up entries keep the condition.
    "mage": {"evocation": dict(starved=True, drop={"arcane": [HEATING_UP_BRANCH]}),
             "arcane_missiles": dict(drop={"arcane": [HEATING_UP_BRANCH]})},
    "rogue": {
        # Subtlety: the sim saves energy before Hemorrhage (60) and Eviscerate (80). In a
        # priority list the Sinister Strike below them spends first, so the energy never
        # arrives and neither was cast (2026-11-20 simulation without the thresholds: kills 7%
        # faster at 40, 15% at 60, 10 to 18% on elites; no change at 25).
        "hemorrhage": dict(drop={"subtlety": [ENERGY_FLOOR]}),
        # Slice and Dice is kept up first on every list (levelling guides; about 60% of a level 12
        # rogue's damage was auto attacks in game) from 1 combo point: its 9 s covers most of a
        # levelling fight (12 logged at level 12 on 2026-11-23: median 11.7 s). Simulated at those
        # fight lengths, 1 point was 2 to 6% faster than 2; 2 points paid only past about 14 s
        # (1 to 3%), too little for a fight-length rule. One rule for every tree.
        "slice_and_dice": dict(
            drop={tree: [{"t": "resource", "res": "combo_points"}, {"t": "any"}]
                  for tree in ("assassination", "combat", "subtlety")},
            add={tree: [{"t": "resource", "res": "combo_points", "op": ">=", "n": 1},
                        {"t": "buff", "id": 5171, "dur": 6, "neg": True}]
                 for tree in ("assassination", "combat", "subtlety")}),
        # Vanish carried the same unreachable energy threshold. Without it the sim re-opens from
        # stealth far more often (2026-11-20 simulation: kills 31% faster at 40, 16% at 60, 6 to
        # 8% on elites). Fought alone, Vanish drops the fight: the enemy resets, so that is not
        # damage a solo player gets, and it is the rogue's escape. Offered in a group only,
        # where someone else holds the enemy. Not checked in game.
        "vanish": dict(drop={"subtlety": [ENERGY_FLOOR]}, add={"subtlety": [IN_A_GROUP]}),
        # Combat: the source now spends Eviscerate from 2 combo points, not 5 (preset mirror
        # after our pin: engine commit 69fcaca9c1, app #1021). Taken here by hand because the
        # rest of that refresh costs other trees (2026-11-20 simulation of this change: kills 2
        # to 4% faster at 25 and 40, 14 to 17% at 60, 7% on a level 60 elite). `was` stops the
        # build once the pin moves past that commit, when this row can go.
        "eviscerate": dict(drop={"subtlety": [ENERGY_FLOOR]},
                           at={"combat": {"combo_points": 2}}, was={"combat": {"combo_points": 5}}),
    },
    # Maul banks 25 rage for Lacerate and Primal Bite (the sim's level 60 setup). Before either is
    # learned (Lacerate 25, Primal Bite 40) it is the bear's only single-target spender, and the
    # rage it waited on had nothing else to buy: it spends at its cost, as Heroic Strike does.
    "druid": {"innervate": dict(starved=True),
              "maul": dict(or_none_known={"feral_bear": ["lacerate", "primal_bite"]})},
    # Slam keeps the sim's cast-time condition (only once Improved Slam shortens the cast):
    # dropping it, as the launch guide plays, cost 3% at 30 and 10% at 40 once Mortal Strike
    # arrives, for 3% at 20 (2026-11-20 simulation).
    "warrior": {"bloodrage": dict(health=50),
                # Each talent style names its own main spenders: Protection levels on Heroic
                # Strike until Revenge (14) or Shield Slam (talent) arrives (forever-guides).
                # Protection spends earlier: 30 rage killed regular targets 1 to 2% faster than
                # the sim's 45 and cost nothing on long fights (2026-11-18 simulation).
                "heroic_strike": dict(or_none_known=WARRIOR_SPENDERS, at={"protection": {"rage": 30}}),
                "hamstring": dict(needs_known={"arms": WARRIOR_SPENDERS["arms"]})},
}


def gate_matches(g, pattern):
    """Does gate g carry every field of the pattern? `has` asks for a group member that does."""
    for key, want in pattern.items():
        if key == "has":
            if not any(gate_matches(member, want) for member in g.get("g", [])):
                return False
        elif g.get(key) != want:
            return False
    return True


def without_cast(gates):
    """The gates with every cast-time condition removed, nested groups included. Dropping an
    `any` member would make the group stricter, so such a group goes whole (it then holds)."""
    out = []
    for g in gates:
        if g["t"] == "cast":
            continue
        if g["t"] in ("any", "all"):
            members = without_cast(g["g"])
            if not members or (g["t"] == "any" and len(members) < len(g["g"])):
                continue
            g = dict(g, g=members)
        out.append(g)
    return out


def regate(cls, tree, entries, chains):
    for name, spec in REGATE.get(cls, {}).items():
        if spec.get("trees") and tree not in spec["trees"]:
            continue
        by_tree = [k for k in ("or_none_known", "needs_known") if isinstance(spec.get(k), dict)]
        if any(tree not in spec[k] for k in by_tree):
            continue
        spec = dict(spec, **{k: spec[k][tree] for k in by_tree})
        chain = chains.get(name)
        sid = chain and rank1(chain)
        for e in entries:
            if e["id"] != sid:
                continue
            gates = list(e["gates"])
            at, was = (spec.get("at") or {}).get(tree) or {}, (spec.get("was") or {}).get(tree) or {}
            for i, g in enumerate(gates):
                if g["t"] in ("power", "resource") and g.get("res") in at and g.get("op") == ">=":
                    if g["res"] in was and g["n"] != was[g["res"]]:
                        raise SystemExit("REGATE %s %s: the source now says %s >= %s, not %s; revisit the row"
                                         % (cls, name, g["res"], g["n"], was[g["res"]]))
                    gates[i] = dict(g, n=at[g["res"]])
            drop = (spec.get("drop") or {}).get(tree)
            if drop:
                gates = [g for g in gates if not any(gate_matches(g, pattern) for pattern in drop)]
            gates += [dict(g) for g in (spec.get("add") or {}).get(tree) or [] if g not in gates]
            if not set(spec) - CONDITIONS_ONLY:
                e["gates"] = gates
                continue
            if spec.get("drop_cast"):
                e["gates"] = without_cast(gates)
                # With a condition left that the addon can time (Immolate: missing from the
                # target), the entry is an ordinary one and may lead. With none left (Slam) it
                # stays left to the player: nothing says when it is the right press.
                if not e["gates"]:
                    e["delegated"] = True
                    LOST[id(e)] = (LOST.get(id(e)) or []) + ["cast-time condition dropped (REGATE drop_cast)"]
                continue
            if spec.get("starved"):
                power = [g for g in gates if g["t"] == "power" and g.get("res") == "mana"]
                gates = [g for g in gates if g not in power]
                gates.insert(0, {"t": "any", "g": power + [{"t": "starved"}]} if power else {"t": "starved"})
            if spec.get("health"):
                gates.append({"t": "health", "op": ">", "pct": float(spec["health"])})
            if spec.get("execute"):
                execute = {"t": "execute", "op": "<", "pct": spec["execute"]}
                gates = [g for g in gates if g != execute]
                if spec.get("or_known"):
                    gates.append({"t": "any", "g": [execute, {"t": "known", "id": spec["or_known"]}]})
                else:
                    gates.append(execute)
            if spec.get("near"):
                near = {"t": "near", "n": spec["near"]}
                if near not in gates:
                    gates.append(near)
            if spec.get("or_none_known"):
                power = [g for g in gates if g["t"] == "power"]
                unknown = [{"t": "known", "id": rank1(chains[n]), "neg": True}
                           for n in spec["or_none_known"] if chains.get(n)]
                assert power and unknown, (cls, name, "or_none_known needs a power gate and spells")
                gates = [g for g in gates if g not in power]
                cond = power[0] if len(power) == 1 else {"t": "all", "g": power}
                gates.append({"t": "any", "g": [cond, {"t": "all", "g": unknown}]})
            if spec.get("needs_known") is not None:
                known = [{"t": "known", "id": rank1(chains[n])} for n in spec["needs_known"] if chains.get(n)]
                assert known, (cls, name, "needs_known names no learnable spell")
                gates.append(known[0] if len(known) == 1 else {"t": "any", "g": known})
            e["gates"], e["w"] = gates, True


# ---------------------------------------------------------------------------------------------
# CORE RULES. Simple, data-driven damage principles applied to every tree after the class
# adaptations above (EXTRA / REGATE / generalize_entries hold the class and spec quirks).
# Sources: forever-guides/ (finishers at full points, ranged specs stay ranged, spend before the
# cap) and the 2026-11-15 priority audit.
#   1. A combo-point finisher that applies damage over time to the target spends at least
#      FINISHER_MIN_POINTS unless its source already gates on points (Rupture at 1 point is a
#      weak bleed). Direct finishers keep the runtime's per-target point policy; maintenance
#      buffs (Slice and Dice) are self auras and exempt.
#   2. In a ranged tree, attacks that need melee range trail the tree's ranged attacks: they
#      remain as the fallback when an enemy is on top of the player.
#   3. Outside tank trees an absorb shield is a defensive, never a damage lead: it moves to the
#      end of the list with its source gates (the defensive queue owns emergency use).
#   4. (In Conv.cmp) a rage/energy threshold above NOMINAL_POWER_MAX reads as "near the cap".
#   5. A point-blank attack (no range; caster-centred enemy area or cone) is offered only with
#      the target inside its radius. The game reports no range for it, so the out-of-range
#      sink never moves it; an unproven distance still never blocks.
#   6. A spell the game restricts to targets below 20% health (Execute, Hammer of Wrath)
#      carries the execute gate, so it ranks with the other execute-range spells.
#   7. A stack requirement on a buff whose every effect only shortens cast time or cost
#      (Maelstrom Weapon) is marked castOnly: before a pull a cast cannot be pushed back, so
#      the runtime may open with the spell without those stacks.
#   8. A damage over time with no hit of its own and no condition on its own debuff (Bane of Doom,
#      Devouring Plague) gets the keep-it-up condition, so the dying-target rules reach it too.
#   9. Against a pack a stacking debuff stops at one application per target (`once`): the runtime
#      does not raise it to the full stack there, whatever the fight (FOREVER_DPS_PRINCIPLES).
# ---------------------------------------------------------------------------------------------
FINISHER_MIN_POINTS = 4
NOMINAL_POWER_MAX = 100
NEAR_CAP_POWER = 90
MELEE_RANGE_MAX = 5           # yards: SpellRange maximum of a melee attack
COMBO_POINTS_POWER = 4        # SpellPower.PowerType on Forever
POOLED_POWERS = {"1", "3"}    # SpellPower.PowerType: rage, energy
SCHOOL_ABSORB_AURA = 69
WAND_FALLBACK = {5019}        # Shoot (wand)
TARGET_ENEMY_UNIT = 6         # ImplicitTarget: the chosen enemy
CASTER_ORIGINS = {18, 22}     # ImplicitTarget: area centred on the caster
ENEMY_AREAS = {15, 16}        # ImplicitTarget: enemies in that area
ENEMY_CONE = 24               # ImplicitTarget: enemies in a cone in front of the caster
AURA_STATE_HEALTH_BELOW_20 = 2  # SpellAuraRestrictions.TargetAuraState (Execute)
EXECUTE_PCT = 20
SPELL_MODIFIER_AURAS = {107, 108}  # flat / percent spell modifier
MOD_CAST_TIME, MOD_COST = 10, 14
RANGED_TREES = {"hunter": {"beast_mastery", "marksmanship"}}
TANK_TREES = {cls: set(trees) for cls, trees in gfd.TANK_TREES.items()}

@functools.lru_cache(maxsize=None)
def _combo_point_spenders():
    return frozenset(r["SpellID"] for r in cfa.rows("SpellPower")
                     if r["PowerType"] == str(COMBO_POINTS_POWER) and int(r["ManaCost"] or 0) > 0)


@functools.lru_cache(maxsize=None)
def _hostile_max_ranges():
    ranges = {r["ID"]: float(r["RangeMax_0"] or 0) for r in cfa.rows("SpellRange")}
    return {r["SpellID"]: ranges[r["RangeIndex"]] for r in cfa.rows("SpellMisc")
            if r["DifficultyID"] == "0" and r["RangeIndex"] in ranges}


def costs_combo_points(sid):
    return str(sid) in _combo_point_spenders()


@functools.lru_cache(maxsize=None)
def _pooled_costs():
    """SpellID -> the pooled power types (rage, energy) it costs."""
    found = {}
    for r in cfa.rows("SpellPower"):
        if r["PowerType"] in POOLED_POWERS and int(r["ManaCost"] or 0) > 0:
            found.setdefault(r["SpellID"], set()).add(r["PowerType"])
    return found


def pooled_costs(sid):
    return _pooled_costs().get(str(sid), set())


def hits_area(sid):
    """Does sid strike every enemy in an area or cone, not one chosen enemy?"""
    return any(targets & (ENEMY_AREAS | {ENEMY_CONE}) for _, _, _, targets, _ in effects_of(sid))


def hostile_max_range(sid):
    """SpellRange maximum (hostile) of sid in yards, or None when the data has no range."""
    return _hostile_max_ranges().get(str(sid))


def applies_target_dot(sid):
    return any(eff == APPLY_AURA and aura in DMG_AURAS and targets & ENEMY_TARGETS
               for eff, aura, _, targets, _ in effects_of(sid))


def is_absorb_shield(sid):
    return on_self(sid) and not deals_damage(sid) and any(
        eff == APPLY_AURA and aura == SCHOOL_ABSORB_AURA for eff, aura, *_ in effects_of(sid))


def is_melee(sid):
    reach = hostile_max_range(sid)
    return reach is not None and 0 < reach <= MELEE_RANGE_MAX


@functools.lru_cache(maxsize=None)
def _point_blank_radii():
    """SpellID -> largest radius of its caster-centred enemy areas and cones, for spells with
    no effect aimed at a chosen enemy (those use their range, not a radius)."""
    radii = {r["ID"]: float(r["Radius"] or 0) for r in cfa.rows("SpellRadius")}
    found, aimed = {}, set()
    for r in cfa.rows("SpellEffect"):
        if r["DifficultyID"] != "0":
            continue
        first, second = int(r["ImplicitTarget_0"] or 0), int(r["ImplicitTarget_1"] or 0)
        if TARGET_ENEMY_UNIT in (first, second):
            aimed.add(r["SpellID"])
        if (first in CASTER_ORIGINS and second in ENEMY_AREAS) or first == ENEMY_CONE:
            radius = max(radii.get(r["EffectRadiusIndex_0"], 0), radii.get(r["EffectRadiusIndex_1"], 0))
            if radius > 0:
                found[r["SpellID"]] = max(found.get(r["SpellID"], 0), radius)
    return {sid: radius for sid, radius in found.items() if sid not in aimed}


@functools.lru_cache(maxsize=None)
def _execute_only():
    return frozenset(r["SpellID"] for r in cfa.rows("SpellAuraRestrictions")
                     if r["TargetAuraState"] == str(AURA_STATE_HEALTH_BELOW_20))


def point_blank_radius(sid):
    """Radius in yards of a point-blank attack (no range of its own), else None."""
    if hostile_max_range(sid):
        return None
    return _point_blank_radii().get(str(sid))


def gates_on_points(gates):
    return any((g.get("t") == "resource" and g.get("res") == "combo_points")
               or (g.get("t") in ("any", "all") and gates_on_points(g["g"])) for g in gates)


@functools.lru_cache(maxsize=None)
def _channeled():
    return frozenset(r["SpellID"] for r in cfa.rows("SpellMisc")
                     if int(r.get("Attributes_1") or 0) & gfd.CHANNEL_ATTR1)


def is_pure_dot(sid):
    """All of the spell's damage comes over time on the target, and it is not a channel."""
    return (applies_target_dot(sid) and str(sid) not in _channeled()
            and not any(eff in DMG_EFFECTS for eff, *_ in effects_of(sid)))


def names_own_debuff(gates, sid):
    return any((g.get("t") in ("debuff", "dot") and g.get("id") == sid)
               or (g.get("t") in ("any", "all") and names_own_debuff(g["g"], sid)) for g in gates)


def holds_hit_for_side_effect(e, g):
    """A refresh condition on the entry's own debuff, where the spell hits for damage and the
    debuff does none over time (Thunder Clap's slow): the tank sims keep the slow up as
    mitigation. A recast loses no ticks, so in the damage queue it only delays the hit."""
    return (g.get("t") == "debuff" and g.get("refresh") and g.get("id") == e["id"]
            and deals_damage(e["id"]) and not applies_target_dot(e["id"]))


def apply_core_rules(cls, tree, entries):
    # The queue is a damage queue in every tree: no hit waits on its own side effect.
    for e in entries:
        if any(holds_hit_for_side_effect(e, g) for g in e["gates"]):
            e["gates"] = [g for g in e["gates"] if not holds_hit_for_side_effect(e, g)]
    # Against three or more, a one-target damage over time paid from a pooled resource (rage,
    # energy) spends what the tree's own area attack on that resource needs, and takes a global
    # cooldown per target to spread. It stays in the one- and two-target lists.
    area_pools = set()
    for e in entries:
        if "aoe" in e["tiers"] and hits_area(e["id"]) and deals_damage(e["id"]):
            area_pools |= pooled_costs(e["id"])
    for e in list(entries):
        if ("aoe" in e["tiers"] and applies_target_dot(e["id"]) and not hits_area(e["id"])
                and pooled_costs(e["id"]) & area_pools):
            e["tiers"] = [t for t in e["tiers"] if t != "aoe"]
            if not e["tiers"]:
                entries.remove(e)
    for e in entries:
        if costs_combo_points(e["id"]) and applies_target_dot(e["id"]) and not gates_on_points(e["gates"]):
            e["gates"] = list(e["gates"]) + [
                {"t": "resource", "res": "combo_points", "op": ">=", "n": FINISHER_MIN_POINTS}]
    if tree in RANGED_TREES.get(cls, ()):
        melee = [e for e in entries if is_melee(e["id"])]
        kept = [e for e in entries if not is_melee(e["id"])]
        last = max((i for i, e in enumerate(kept) if deals_damage(e["id"])), default=None)
        if melee and last is not None:
            entries[:] = kept[:last + 1] + melee + kept[last + 1:]
    if tree not in TANK_TREES.get(cls, ()):
        shields = [e for e in entries if is_absorb_shield(e["id"])]
        rest = [e for e in entries if not is_absorb_shield(e["id"])]
        # The wand stays the final fallback (a caster convention every list keeps).
        tail = len(rest)
        while tail > 0 and rest[tail - 1]["id"] in WAND_FALLBACK:
            tail -= 1
        entries[:] = rest[:tail] + shields + rest[tail:]


@functools.lru_cache(maxsize=None)
def is_cast_only_aura(aid):
    effects = effects_of(aid)
    return bool(effects) and all(
        eff == APPLY_AURA and aura in SPELL_MODIFIER_AURAS and misc in (MOD_CAST_TIME, MOD_COST)
        for eff, aura, _, _, misc in effects) and any(e[4] == MOD_CAST_TIME for e in effects)


def is_cast_only_gate(g):
    return g.get("t") == "stack" and is_cast_only_aura(g.get("id"))


def apply_core_gates(lists):
    """Rules 5 to 8. They run after tier_lists, which tells a general fallback (no gates)
    from a special branch, so a derived gate never changes which entry a tier keeps."""
    for e in {id(e): e for lines in lists.values() for e in lines}.values():
        radius = point_blank_radius(e["id"])
        near = radius and {"t": "near", "n": int(radius)}
        if near and near not in e["gates"]:
            e["gates"], e["w"] = list(e["gates"]) + [near], True
        execute = {"t": "execute", "op": "<", "pct": EXECUTE_PCT}
        if str(e["id"]) in _execute_only() and execute not in e["gates"]:
            e["gates"] = list(e["gates"]) + [execute]
        if any(is_cast_only_gate(g) for g in e["gates"]):
            e["gates"] = [dict(g, castOnly=True) if is_cast_only_gate(g) else g for g in e["gates"]]
        if is_pure_dot(e["id"]) and not names_own_debuff(e["gates"], e["id"]):
            e["gates"] = list(e["gates"]) + [{"t": "debuff", "id": e["id"], "neg": True, "refresh": True}]

def is_one_stack_gate(e, g):
    return (g.get("t") == "stack" and g.get("tgt") and g.get("id") == e["id"]
            and g.get("op") == "<" and g.get("n") == 1)


def one_stack_on_packs(lists):
    """Rule 9. The pack list gets its own copy: the entry may be shared with the other tiers."""
    pack = lists.get("aoe") or []
    for i, e in enumerate(pack):
        if any(is_one_stack_gate(e, g) for g in e["gates"]):
            pack[i] = dict(e, gates=[dict(g, once=True) if is_one_stack_gate(e, g) else g for g in e["gates"]])


def maintained_auras(entries):
    """Auras an entry keeps up: it is cast while the aura is missing, short of stacks or running
    out on the target (a gate on the aura that holds when there is too little of it)."""
    out = set()

    def visit(g):
        for m in g.get("g", []):
            visit(m)
        if g.get("t") == "stack" and g.get("op") in ("<", "<="):
            out.add(g.get("id"))
        elif g.get("t") in ("debuff", "dot") and (g.get("neg") or g.get("op") in ("<", "<=")):
            out.add(g.get("id"))
    for e in entries:
        for g in e.get("gates", []):
            visit(g)
    return out


def release_waits(gates, gone):
    """The gates with every wait for an aura in `gone` (stacks reached, or present on the target)
    read as already met: nothing in the list keeps that aura up any more, so waiting for it would
    hold the entry for good. A met member makes an `any` group met; it leaves an `all` group."""
    def waits(g):
        if g.get("id") not in gone:
            return False
        if g.get("t") == "stack":
            return g.get("op") in ("=", ">=", ">")
        return g.get("t") == "debuff" and not g.get("neg") and g.get("op") not in ("<", "<=")

    def met(g):
        """True when g now always holds; else the simplified gate."""
        if waits(g):
            return True
        if g.get("t") in ("any", "all"):
            kept = []
            for m in g.get("g", []):
                r = met(m)
                if r is True:
                    if g["t"] == "any":
                        return True
                    continue
                kept.append(r)
            if not kept:
                return True
            return dict(g, g=kept)
        return g

    out = []
    for g in gates:
        r = met(g)
        if r is not True:
            out.append(r)
    return out


def add_extras(cls, tree, entries, chains, unresolved):
    """Place the class's EXTRA abilities into one tree's entries (in place). Returns the ids a
    drop row took out: unlisted, a class ability still reached the queue as an unranked filler,
    so the runtime keeps these out wherever the tree's list does not name them."""
    dropped = set()
    def r1_of(name):
        chain = chains.get(name)
        if not chain:
            unresolved.append(f"{cls}: EXTRA {name} is not learnable")
            return None
        return rank1(chain)
    fronts = []
    before_maintained = maintained_auras(entries)

    def place(x, items, default):
        at = x.get("at", default)
        if at == "front":
            fronts.extend(items)
            return
        if at.startswith(("after:", "before:")):
            where, name = at.split(":", 1)
            anchor = r1_of(name)
            hits = [n for n, y in enumerate(entries) if y["id"] == anchor]
            if hits:
                plain = [n for n in hits if not entries[n]["gates"]]
                i = plain[-1] if plain else hits[0]
                if where == "after":
                    i += 1
                entries[i:i] = items
                return
            # The anchor is not on this tree's list (or is itself a "front" extra, placed last):
            # the entry falls to the end. Reported, since that is rarely what the line meant.
            ANCHOR_MISSES.append(f"{cls} {tree}: {x['spell']} {at} (anchor not listed; placed at the end)")
        entries.extend(items)

    for x in EXTRA.get(cls, []):
        if x.get("trees") and tree not in x["trees"]:
            continue
        sid = r1_of(x["spell"])
        if not sid:
            continue
        mine = next((e for e in entries if e["id"] == sid), None)
        if x.get("drop"):
            entries[:] = [e for e in entries if e["id"] != sid]
            dropped.add(sid)
            continue
        if mine and x.get("move"):
            if x.get("tiers"):
                mine["tiers"] = list(x["tiers"])
                count = min(k for name, k in TIERS if name in x["tiers"])
                mine["gates"] = [g for g in mine["gates"] if g["t"] != "targets"]
                mine["gates"].append({"t": "targets", "op": ">=", "n": count})
            if "gates" in x:
                mine["gates"] = list(x["gates"])
                mine["delegated"] = False
            # A tier-limited move retiers one entry; otherwise every copy moves.
            moving = [mine] if x.get("tiers") else [e for e in entries if e["id"] == sid]
            for e in moving:
                entries.remove(e)
            place(x, moving, "front")
            continue
        if mine and not x.get("copy"):
            continue
        gates = []
        for g in x.get("gates", []):
            if isinstance(g, dict):
                gates.append(dict(g))
            elif g == "dot":
                gates.append({"t": "debuff", "id": sid, "neg": True, "refresh": True})
            else:
                gates.append({"t": "stealth"})
        e = {"id": sid, "delegated": False, "tiers": list(x.get("tiers") or [t for t, _ in TIERS]),
             "gates": gates}
        if x.get("w"):
            e["w"] = True
        place(x, [e], "end")
    entries[0:0] = fronts
    # An entry dropped here may have been the only one keeping an aura up (Fire's Scorch stacked
    # Fire Vulnerability, and Combustion waited for five stacks): the waits on it are released.
    if dropped:
        gone = before_maintained - maintained_auras(entries)
        if gone:
            for e in entries:
                e["gates"] = release_waits(e["gates"], gone)
    return dropped


def keeps_own_buff(e):
    """Does the entry only keep its own buff up: cast while the buff is missing, at most with a
    minimum of the resource it spends (Slice and Dice at two combo points)?"""
    g = e["gates"]
    own = [x for x in g if x.get("t") == "buff" and x.get("neg") and x.get("dur")]
    spend = [x for x in g if x.get("t") == "resource" and x.get("op") == ">="]
    return (bool(own) and len(own) + len(spend) == len(g)
            and any(x.get("id") == e["id"] for x in own))
TIERS = [("st", 1), ("cleave", 2), ("aoe", 3)]
OPS = {"OpLt": "<", "OpLe": "<=", "OpGt": ">", "OpGe": ">=", "OpEq": "=", "OpNe": "!="}
FLIP = {"<": ">", "<=": ">=", ">": "<", ">=": "<=", "=": "=", "!=": "!="}
NOT_OP = {"<": ">=", "<=": ">", ">": "<=", ">=": "<", "=": "!=", "!=": "="}
POWER = {"currentRage": "rage", "currentEnergy": "energy", "currentMana": "mana"}
TRUE, FALSE, UNK = "TRUE", "FALSE", "UNK"
# spellID -> base aura seconds (SpellMisc.DurationIndex -> SpellDuration), filled by main().
# A buff gate needs it for the runtime's cast-observed window (IsBuffWindowActive).
DURATION = {}
LOST = {}   # id(entry) -> condition nodes given up, for --audit
ANCHOR_MISSES = []   # EXTRA placements whose after:/before: anchor was not on the list


def num(const):
    """'6' / '0ms' / '2s' / '20%' -> float (seconds for times)."""
    v = str(const.get("val", "0")).strip()
    m = re.fullmatch(r"(-?[\d.]+)\s*(ms|s|%)?", v)
    if not m:
        return None
    n = float(m.group(1))
    return n / 1000 if m.group(2) == "ms" else n


def sid_of(ref):
    """{"spellId": n, "rank": r} -> n, None for item / other ids."""
    return ref.get("spellId") if isinstance(ref, dict) else None


def compare(k, op, n):
    return {"<": k < n, "<=": k <= n, ">": k > n, ">=": k >= n, "=": k == n, "!=": k != n}[op]


def rank1(chain):
    """Rank 1 (the first-learned id) of a class_chains chain."""
    return int(chain[0][0])


# Preset ids that are not in the 1.60.1 client, by the id the client does have (checked
# against SpellName / Spell descriptions). A gate on a missing id can never hold.
#   44404 -> 400589: Missile Barrage's proc aura ("your next Arcane Missiles ..."), talent 400588.
SOURCE_ID_FIXES = {44404: 400589}


@functools.lru_cache(maxsize=None)
def _known_index():
    """(spell names, talent spell ids, ids any class can learn) for known_spell_id."""
    names = {int(r["ID"]): r["Name_lang"] for r in cfa.rows("SpellName")}
    by_name = {}
    for sid, name in names.items():
        by_name.setdefault(name, []).append(sid)
    talents = set()
    for r in cfa.rows("TraitDefinition"):
        for col in ("SpellID", "OverridesSpellID", "VisibleSpellID"):
            value = r.get(col) or ""
            if value.isdigit() and int(value):
                talents.add(int(value))
    learnable = set()
    for cls in TREES:
        chains, _ = cfa.class_chains(cfa.CLASS_MASK[cls])
        learnable.update(int(sid) for chain in chains.values() for sid, _ in chain)
    return names, by_name, talents, learnable


@functools.lru_cache(maxsize=None)
def _granting_talents():
    """Aura id -> the talents with an effect that triggers it (Arcane Concentration -> Clearcasting)."""
    _, _, talents, _ = _known_index()
    found = {}
    for r in cfa.rows("SpellEffect"):
        trigger, source = r.get("EffectTriggerSpell") or "0", r["SpellID"]
        if trigger.isdigit() and int(trigger) and source.isdigit() and int(source) in talents:
            found.setdefault(int(trigger), set()).add(int(source))
    return found


def known_spell_id(sid, by_id, aura=False):
    """The id a "known" gate should ask IsPlayerSpell about. A sim asks whether an aura is
    available; the game only knows learned spells and talents. So: rank 1 of the class's own
    chain (any rank known counts, not the level-60 rank the preset names); a talent as it is;
    else the one talent or learnable spell of the same name (Heating Up the proc aura ->
    Heating Up the talent). Anything else stays as it is: an item or set proc the player
    does not have reads "not known", which is right for nearly every character."""
    sid = SOURCE_ID_FIXES.get(sid, sid)
    if aura:
        # "Is this aura available to me": the one talent that grants it, when the data names
        # exactly one (Clearcasting <- Arcane Concentration, Fire Vulnerability <- Improved Scorch).
        granting = _granting_talents().get(sid, ())
        if len(granting) == 1:
            return next(iter(granting))
    if sid in by_id:
        return rank1(by_id[sid])
    names, by_name, talents, learnable = _known_index()
    if sid in talents:
        return sid
    same = [i for i in by_name.get(names.get(sid), []) if i != sid and (i in talents or i in learnable)]
    return same[0] if len(same) == 1 else sid


def cmp_parts(val):
    """A wowsims comparison as (op, value name, constant, value args), constant on the
    right. Value-vs-value ("dot remaining <= its cast time") keeps the left value with no
    constant (n None): a rule that does not need the number can still read it."""
    op = OPS.get(val.get("op"))
    lhs, rhs = val.get("lhs", {}), val.get("rhs", {})
    if "const" in rhs and "const" not in lhs:
        side, n = lhs, num(rhs["const"])
    elif "const" in lhs and "const" not in rhs:
        side, n, op = rhs, num(lhs["const"]), FLIP.get(op)
    elif "const" not in lhs and "const" not in rhs:
        side, n = lhs, None
    else:
        return op, None, None, {}
    name = next(iter(side), None)
    return op, name, n, (side.get(name, {}) if name else {})


class Conv:
    """Condition tree -> gate, for one class. `self.delegated` records lost conditions."""

    def __init__(self, by_id, self_id=None):
        self.by_id = by_id
        self.self_id = self_id   # the entry's own spell (rank 1), for DoT-refresh negation
        self.delegated = False
        self.lost = []           # the condition nodes given up (tools audit: why delegated)

    def lose(self, node):
        self.delegated = True
        self.lost.append(json.dumps(node, separators=(",", ":"))[:160])

    def buff(self, aid, neg=False):
        g = {"t": "buff", "id": aid}
        if DURATION.get(aid):
            g["dur"] = DURATION[aid]
        if neg:
            g["neg"] = True
        return g

    def rank1(self, sid):
        sid = SOURCE_ID_FIXES.get(sid, sid)
        chain = self.by_id.get(sid)
        return rank1(chain) if chain else sid

    # --- target-count tier: True / False / None for k engaged enemies ---
    def tier(self, node, k):
        if not isinstance(node, dict) or not node:
            return None
        key, val = next(iter(node.items()))
        if key == "and":
            vs = [self.tier(x, k) for x in val.get("vals", [])]
            return False if False in vs else (True if all(v is True for v in vs) else None)
        if key == "or":
            vs = [self.tier(x, k) for x in val.get("vals", [])]
            return True if True in vs else (False if vs and all(v is False for v in vs) else None)
        if key == "not":
            v = self.tier(val.get("val"), k)
            return None if v is None else not v
        if key == "cmp":
            op, name, n, _ = cmp_parts(val)
            if name == "numberTargets" and n is not None and op in FLIP:
                return compare(k, op, n)
        return None

    # --- gates ---
    def negate(self, g):
        if g in (TRUE, FALSE):
            return FALSE if g == TRUE else TRUE
        if g == UNK:
            return UNK
        t = g["t"]
        if t in ("buff", "cd", "known", "stealth", "group", "totem", "debuff"):
            if t == "debuff" and g.get("op"):
                return dict(g, op=NOT_OP[g["op"]])
            if t == "debuff":
                gate = dict(g, neg=not g.get("neg", False))
                gate.pop("refresh", None)
                if gate["neg"] and gate["id"] == self.self_id:
                    gate["refresh"] = True
                return gate
            return dict(g, neg=not g.get("neg", False))
        if t in ("power", "resource", "execute", "health", "stack", "swing", "tick", "targets", "cast") and g.get("op") in NOT_OP:
            return dict(g, op=NOT_OP[g["op"]])
        if t in ("any", "all"):
            members = [self.negate(m) for m in g["g"]]
            if UNK in members:
                return UNK
            return {"t": "all" if t == "any" else "any", "g": members}
        # Another spell being learned is not evidence its debuff is active.
        if t == "dot":
            if g.get("id") == self.self_id:
                return g
            return UNK
        return UNK

    def conv(self, node):
        if not isinstance(node, dict) or not node:
            return TRUE
        key, val = next(iter(node.items()))
        if key == "const":
            return TRUE
        if key == "and":
            out = []
            for x in val.get("vals", []):
                g = self.conv(x)
                if g == FALSE:
                    return FALSE
                if g == UNK:
                    self.lose(x)
                elif g != TRUE and g not in out:
                    out.append(g)
            return TRUE if not out else (out[0] if len(out) == 1 else {"t": "all", "g": out})
        if key == "or":
            out = []
            for x in val.get("vals", []):
                g = self.conv(x)
                if g == TRUE:
                    return TRUE
                if g == UNK:
                    # Dropping an `or` member makes it STRICTER, which is wrong: give the
                    # whole alternative up instead.
                    self.lose(x)
                    return TRUE
                if g != FALSE and g not in out:
                    out.append(g)
            return FALSE if not out else (out[0] if len(out) == 1 else {"t": "any", "g": out})
        if key == "not":
            g = self.negate(self.conv(val.get("val")))
            if g == UNK:
                self.lose(node)
                return TRUE
            return g
        if key == "cmp":
            return self.cmp(val)
        if key in ("auraIsActive", "auraIsInactive"):
            aid = self.rank1(sid_of(val.get("auraId")))
            if not aid:
                return UNK
            gate = {"t": "debuff", "id": aid} if aura_on_target(val, aid) else self.buff(aid)
            return self.negate(gate) if key == "auraIsInactive" else gate
        if key == "dotIsActive":
            sid = sid_of(val.get("spellId"))
            return {"t": "debuff", "id": self.rank1(sid)} if sid else UNK
        if key == "isExecutePhase":
            m = re.search(r"\d+", str(val.get("threshold", "E20")))
            return {"t": "execute", "op": "<", "pct": int(m.group()) if m else 20}
        if key in ("spellIsKnown", "auraIsKnown"):
            sid = sid_of(val.get("spellId") or val.get("auraId"))
            return {"t": "known", "id": known_spell_id(sid, self.by_id, key == "auraIsKnown")} if sid else UNK
        if key == "spellIsReady":
            sid = sid_of(val.get("spellId"))
            return {"t": "cd", "id": self.rank1(sid)} if sid else UNK
        if key in ("gcdIsReady", "spellCanCast"):
            return TRUE
        if key == "auraShouldRefresh":
            aid = self.rank1(sid_of(val.get("auraId")))
            if not aid:
                self.lose(node)
                return TRUE
            # My own aura (Faerie Fire, Demoralizing Roar): refreshed as it drops, which is the
            # dot / buff gate on Forever (timed from the cast). Someone else's: given up.
            if aid != self.self_id:
                self.lose(node)
            if aura_on_target(val, aid):
                gate = {"t": "debuff", "id": aid, "neg": True}
                if aid == self.self_id:
                    gate["refresh"] = True
                return gate
            return self.buff(aid, True)
        if key == "frontOfTarget":
            return UNK
        return UNK

    def cmp(self, val):
        op, name, n, side = cmp_parts(val)
        if op is None or name is None:
            return UNK
        if name in ("auraRemainingTime", "dotRemainingTime"):
            return self.remaining(op, name, side, val)
        if n is None and name == "remainingTime" and op in ("<", "<="):
            # "A cast would not finish as planned" (frost Fire Blast: fight time left under
            # Frostbolt's cast), so the instant goes: on a dying target (confirmed below the
            # execute line; unreadable health is not dying), or while being hit, when every
            # cast expects pushback (the player's own hits, UNIT_COMBAT).
            return {"t": "any", "g": [{"t": "execute", "op": "<", "pct": EXECUTE_PCT, "required": True},
                                      {"t": "hit"}]}
        if n is None and "remainingTime" in json.dumps(val):
            # No fight-duration signal: keep this branch unconfirmed, rather than
            # erasing it and turning a conditional mana spender into a filler.
            return {"t": "unconfirmed"}
        if name == "math":
            # Resource pooling arithmetic (Ferocious Bite: energy + regen vs its cost + Shred's):
            # the button's own cost decides whether it can be pressed.
            # ponytail: pools nothing; a real pool needs the plain energy-tick timer.
            return TRUE
        if n is None:
            return UNK
        if name == "unitDistance" and op in ("<", "<="):
            # Point-blank AoE (Arcane Explosion, Hellfire, Blast Wave) only with the target close.
            return {"t": "near", "n": n}
        if name == "totemRemainingTime" and op in ("<", "<=") and n <= 1:
            slot = {"Fire": 1, "Earth": 2, "Water": 3, "Air": 4}.get(side.get("totemType"))
            return {"t": "totem", "slot": slot, "neg": True} if slot else UNK
        if name == "numberTargets":
            return {"t": "targets", "op": op, "n": n}
        if name == "remainingTime":
            # Fight length is unknowable; assume the fight goes on (steady state).
            # ponytail: end-of-fight dumps never fire; a real time-to-die needs secret health.
            return TRUE if op in (">", ">=") else (FALSE if op in ("<", "<=") else UNK)
        if name in POWER:
            # Core rule: a rage/energy spender gated above the bar's nominal maximum would
            # never fire, so the resource could sit capped. Read it as "near the cap".
            if POWER[name] in ("rage", "energy") and op in (">", ">=") and n > NOMINAL_POWER_MAX:
                n = NEAR_CAP_POWER
            return {"t": "power", "res": POWER[name], "op": op, "n": n}
        if name == "currentManaPercent":
            return {"t": "power", "res": "mana", "op": op, "n": n, "ispct": True}
        if name == "currentComboPoints":
            return {"t": "resource", "res": "combo_points", "op": op, "n": n}
        if name == "currentHealthPercent":
            on_target = side.get("sourceUnit", {}).get("type") == "CurrentTarget"
            return {"t": "execute" if on_target else "health", "op": op, "pct": n}
        if name == "spellTimeToReady":
            sid = self.rank1(sid_of(side.get("spellId")))
            if not sid:
                return UNK
            if op in ("<", "<=") and n <= 1.5:
                return {"t": "cd", "id": sid}
            if op in (">", ">=") and n >= 0:
                return {"t": "cd", "id": sid, "neg": True}
            return UNK
        if name == "auraNumStacks":
            aid = self.rank1(sid_of(side.get("auraId")))
            if not aid:
                return UNK
            g = {"t": "stack", "id": aid, "op": op, "n": n}
            if aura_on_target(side, aid):
                g["tgt"] = True
            return g
        if name == "autoTimeToNext":
            g = {"t": "swing", "op": op, "n": n}
            if side.get("autoType") == "RangedAuto":
                g["ranged"] = True
            return g
        if name == "timeToNextEnergyTick":
            return UNK
        if name == "spellCastTime":
            # The spell's current cast time (GetSpellInfo, highest known rank): a proc that makes
            # it instant (Nightfall's Shadow Bolt, Presence of Mind) or a talent that shortens
            # it (Improved Slam) moves it under a GCD.
            sid = self.rank1(sid_of(side.get("spellId")))
            return {"t": "cast", "id": sid, "op": op, "n": n} if sid else UNK
        return UNK


    def remaining(self, op, name, side, val):
        """auraRemainingTime / dotRemainingTime vs a constant or another value (cast time)."""
        raw = sid_of(side.get("auraId") or side.get("spellId"))
        sid = self.rank1(raw)
        if not sid:
            return UNK
        target = name == "dotRemainingTime" or aura_on_target(side, raw)
        # Own refreshes conservatively wait for expiry. Presence does not establish an
        # early-refresh threshold; never use this policy for another spell's prerequisite.
        if target and sid == self.self_id and op in ("<", "<="):
            return {"t": "debuff", "id": sid, "neg": True, "refresh": True}
        # Likewise my own buff about to drop (Slice and Dice, a seal): its window is timed from
        # my cast, so "not up" is the refresh.
        if not target and sid == self.self_id and op in ("<", "<="):
            return self.buff(sid, True)
        # My OTHER buff about to drop (Judgement / Seal of Command as Seal of Righteousness runs
        # out: level-60 seal twisting): the timing detail is dropped, that buff's own line keeps
        # it up. Never "not up": Judgement needs an active seal, but does not consume it.
        if not target and sid in self.by_id and op in ("<", "<=") and on_self(raw):
            return TRUE
        # Time left on MY OWN DoT on the target (one this class casts): DotTracker reads it from
        # the engine's timer or from my cast (Ferocious Bite while Rip has 3+ seconds, Ghostly
        # Strike as Rupture runs out). Against a constant, or against a spell's cast time.
        if name == "dotRemainingTime" and raw in self.by_id:
            _, _, n, _ = cmp_parts(val)
            gate = {"t": "debuff", "id": sid, "op": op}
            if n is not None:
                gate["n"] = n
                return gate
            rhs = val.get("rhs", {})
            cast = sid_of(rhs["spellCastTime"].get("spellId")) if "spellCastTime" in rhs else None
            if cast:
                gate["ncast"] = self.rank1(cast)
                return gate
        self.lose({"cmp": val})              # remaining time itself is secret
        if target:
            _, _, n, _ = cmp_parts(val)
            gate = {"t": "debuff", "id": sid, "op": op}
            if n is not None:
                gate["n"] = n
            return gate
        return self.buff(sid, op in ("<", "<="))


def actions_of(action):
    """Independent suggestions only; strict sequences need state we do not model."""
    if "strictSequence" in action:
        return []
    for key in ("castSpell", "channelSpell"):
        if key in action:
            sid = sid_of(action[key].get("spellId"))
            return [(sid, None)] if sid else []
    if "multidot" in action:
        sid = sid_of(action["multidot"].get("spellId"))
        return [(sid, "dot")] if sid else []
    return []   # autocastOtherCooldowns, cancelAura, move, wait: not suggestions


def convert_sim(stem, by_id, dropped):
    # ponytail: prepullActions are not read - nothing consumes a precombat list yet.
    data = json.load(open(os.path.join(SRC, stem + ".apl.json"), encoding="utf-8"))
    entries = []
    for e in data.get("priorityList", []):
        if e.get("hide"):
            continue
        action = e.get("action", {})
        cond = action.get("condition")
        for sid, extra in actions_of(action):
            if sid not in by_id:
                dropped.add(sid)
                continue
            rid = rank1(by_id[sid])
            c = Conv(by_id, rid)
            g = c.conv(cond)
            if g == FALSE:
                continue                     # can never fire in a long fight
            gates = [] if g in (TRUE, UNK) else (g["g"] if g["t"] == "all" else [g])
            if g == UNK:
                c.lose(cond)
            if extra == "dot":
                gates.append({"t": "debuff", "id": rid, "neg": True, "refresh": True})
            tiers = [name for name, k in TIERS
                     if (any(c.tier(cond, count) is not False for count in range(3, 41))
                         if name == "aoe" else c.tier(cond, k) is not False)]
            e = {"id": rid, "gates": gates, "delegated": c.delegated, "tiers": tiers}
            if e not in entries:             # a sim list repeats a line per talent variant
                entries.append(e)
                LOST[id(e)] = c.lost
    return entries


def convert_pin(stem, chains, unresolved):
    """Hand pins: SimC syntax, classified by the retail generator's own condition parser
    (classify_if / count_fails) with tokens resolved against the Forever class chains."""
    resolve = lambda tok: rank1(chains[tok]) if tok in chains else None  # noqa: E731
    entries = []
    for line in open(os.path.join(PINS, stem + ".simc"), encoding="utf-8"):
        m = re.match(r"actions\+?=/?([a-z0-9_]+)(?:,if=(.*))?$", line.strip())
        if not m or m.group(1) in cfa.SKIP:
            continue
        rid = resolve(m.group(1))
        if not rid:
            unresolved.append(f"{stem}: {m.group(1)}")
            continue
        cond = m.group(2) or ""
        gates, delegated = gsr.classify_if(cond, resolve) if cond else ([], False)
        tiers = [n for n, k in TIERS if not (cond and gsr.count_fails(cond, k))]
        entries.append({"id": rid, "gates": gates, "delegated": delegated, "tiers": tiers})
    return entries


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(int(v)) if float(v).is_integer() else repr(v)
    if isinstance(v, str):
        return '"' + v + '"'
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    return "{" + ",".join(f"{k}={lua(x)}" for k, x in v.items()) + "}"


EARTH_SHOCK_LATE_SECONDS = 2


def generalize_entries(cls, tree, entries, chains):
    """Adapt specialized execution into stable defaults before selecting each context."""
    if cls == "warrior" and tree == "fury":
        # On one target Sunder follows Fury's attacks, just ahead of the Heroic Strike that spends
        # what is left (2026-11-18 simulation: 1 to 2% faster kills). The pack lists keep their order.
        sunder, heroic = rank1(chains["sunder_armor"]), rank1(chains["heroic_strike"])
        for e in [e for e in entries if e["id"] == sunder and "st" in e["tiers"]]:
            e["tiers"] = [t for t in e["tiers"] if t != "st"]
            at = next(i for i, x in enumerate(entries) if x["id"] == heroic and "st" in x["tiers"])
            entries.insert(at, dict(e, tiers=["st"]))
    if cls == "warlock":
        # A target carries one Bane from a warlock, so a cast replaces the other. Bane of Doom
        # leads wherever it is allowed and Bane of Agony waits while it runs, in every tier.
        doom, agony = rank1(chains["bane_of_doom"]), rank1(chains["bane_of_agony"])
        yields = {"t": "debuff", "id": doom, "neg": True}
        for e in entries:
            if e["id"] == agony and yields not in e["gates"]:
                e["gates"] = [yields] + list(e["gates"])
        # A sim may keep a separate copy per target count, so each copy is placed on its own.
        for copy in [e for e in entries if e["id"] == doom]:
            at = next(i for i, e in enumerate(entries) if e is copy)
            first = next((i for i, e in enumerate(entries)
                          if e["id"] == agony and set(e["tiers"]) & set(copy["tiers"])), None)
            if first is not None and first < at:
                del entries[at]
                entries.insert(first, copy)
    if cls == "shaman" and tree in ("elemental", "enhancement"):
        # Current guide adaptations and deliberate limits: forever-guides/druid-shaman.md.
        if tree == "enhancement":
            orders = {
                # Earth Shock is the filler shock once Flame Shock is ticking (the shocks share a
                # cooldown) and the only instant before Flame Shock is learned. It is an
                # interrupt: the runtime offers it as damage only against a quiet open-world
                # target (SpellQueue._InterruptFreeForDamage) and reserves it otherwise. After
                # Lightning Bolt, as the launch guide has it: an instant Bolt at five Maelstrom
                # Weapon stacks comes first.
                "st": ["strength_of_earth_totem", "magma_totem", "searing_totem", "flame_shock",
                       "rage_of_the_farseer", "stormstrike", "lightning_bolt", "earth_shock", "fire_nova"],
                "aoe": ["strength_of_earth_totem", "magma_totem", "searing_totem", "fire_nova",
                        "flame_shock", "rage_of_the_farseer", "stormstrike", "lightning_bolt", "earth_shock"],
            }
        else:
            orders = {
                "st": ["searing_totem", "flame_shock", "lightning_mastery", "chain_lightning", "lightning_bolt"],
                "aoe": ["magma_totem", "searing_totem", "lightning_mastery", "chain_lightning",
                        "fire_nova", "flame_shock", "lightning_bolt"],
            }
        out = []
        for context, order in orders.items():
            for name in order:
                sid = rank1(chains[name])
                gates = []
                if name in ("magma_totem", "searing_totem", "strength_of_earth_totem"):
                    gates = [{"t": "totem", "slot": 2 if name == "strength_of_earth_totem" else 1, "neg": True}]
                elif name == "fire_nova":
                    gates = [{"t": "totem", "slot": 1}]
                elif name == "flame_shock":
                    gates = [{"t": "debuff", "id": sid, "neg": True, "refresh": True}]
                elif name == "earth_shock":
                    # The shocks share one cooldown (SpellCooldowns category, 6s in 1.60.1.70938),
                    # so a filler Earth Shock locks Flame Shock out for that long. Asking for more
                    # than the whole cooldown left never held before the talent that shortens it:
                    # Flame Shock has exactly that much left when the cooldown ends. A refresh up
                    # to EARTH_SHOCK_LATE_SECONDS late costs less than an idle shock cooldown
                    # (2026-11-20 simulation: kills 9 to 13% faster at 14 and 30, no change at 60).
                    gates = [{"t": "debuff", "id": rank1(chains["flame_shock"]), "op": ">",
                              "n": spell_meta(sid)[1] - EARTH_SHOCK_LATE_SECONDS}]
                elif name == "lightning_bolt" and tree == "enhancement":
                    gates = [{"t": "stack", "id": 408505, "op": ">=", "n": 5, "required": True}]
                elif name == "chain_lightning" and context == "st":
                    gates = [Conv({}).buff(rank1(chains["lightning_mastery"]), True)]
                if tree == "elemental" and name in ("magma_totem", "fire_nova"):
                    gates.append({"t": "targets", "op": ">=", "n": 3})
                entry = {"id": sid, "gates": gates, "delegated": False,
                         "tiers": ["st", "cleave"] if context == "st" else ["aoe"]}
                if name == "fire_nova" or (name == "lightning_bolt" and tree == "enhancement"):
                    entry["w"] = True
                out.append(entry)
        entries[:] = out
    if cls == "paladin":
        seals = sorted({rank1(chain) for name, chain in chains.items()
                        if name.startswith("seal_of_")})
        judgement = rank1(chains["judgement"])
        righteousness = rank1(chains["seal_of_righteousness"])
        converter = Conv({})
        seen = set()
        out = []
        # Preserve the existing Righteousness-first Retribution fallback instead of
        # promoting the preset's conditional tank seal when its gates are normalized.
        ordered = entries
        if tree == "retribution":
            ordered = sorted(entries, key=lambda e: 0 if e["id"] == righteousness else 1)
        for e in ordered:
            if e["id"] in seals:
                if e["id"] in seen:
                    continue
                seen.add(e["id"])
                e = dict(e, gates=[converter.buff(sid, True) for sid in seals],
                         delegated=False, tiers=[t for t, _ in TIERS])
            elif e["id"] == judgement:
                # Imported presets may require their particular damage seal. Any active
                # seal enables Judgement; keep unrelated conditions from the source.
                gates = [g for g in e["gates"]
                         if not (g.get("t") == "buff" and g.get("id") in seals)]
                gates.append({"t": "any", "g": [converter.buff(sid) for sid in seals]})
                e = dict(e, gates=gates)
            out.append(e)
        if not seen:
            out.insert(0, {"id": righteousness, "gates": [converter.buff(sid, True) for sid in seals],
                           "delegated": False, "tiers": [t for t, _ in TIERS]})
        entries[:] = out
    if cls == "druid" and tree == "feral":
        bite = rank1(chains["ferocious_bite"])
        shifting_power = rank1(chains["shifting_power"])
        claw = rank1(chains["claw"])
        for e in entries:
            if e["id"] == claw and not e["gates"]:
                # Its only source condition is "in front of the target": the sim's stand-in for
                # "Shred cannot be used". Claw itself has no positional requirement, so nothing
                # about it is untimed. It is the levelling cat's builder (forever-guides) and
                # the list's one unconditional attack: it must be able to lead.
                e["delegated"] = False
            if e["id"] == bite:
                e["gates"] = [dict(g, op=">=") if g["t"] == "resource" and g.get("res") == "combo_points"
                              and g.get("op") == "=" and g.get("n") == 5
                              else g for g in e["gates"]]
            elif e["id"] == shifting_power:
                # Replace unsupported maximum-Energy arithmetic with a conservative guide threshold.
                e["gates"] = [{"t": "power", "res": "energy", "op": "<", "n": 50, "required": True}]
                e["delegated"], e["w"] = False, True


def tier_lists(entries):
    lists = {t: [] for t, _ in TIERS}
    for e in entries:
        for t in e["tiers"]:
            lists[t].append(e)
    for t, lines in lists.items():
        selected = {}
        for e in lines:
            previous = selected.get(e["id"])
            if previous is None or not e["gates"]:
                selected[e["id"]] = e
            elif len(previous["gates"]) == len(e["gates"]) == 1:
                old, new = previous["gates"][0], e["gates"][0]
                if old["t"] == new["t"] == "targets" and old.get("op") == new.get("op") == ">=" \
                        and new["n"] < old["n"]:
                    selected[e["id"]] = e
        # A general fallback keeps its own position, never the special branch's earlier rank.
        lists[t] = [e for e in lines if selected[e["id"]] is e]
    out = {"st": lists["st"]}
    if lists["aoe"] != lists["st"]:
        out["aoe"] = lists["aoe"]
    if lists["cleave"] != out.get("aoe", lists["st"]):
        out["cleave"] = lists["cleave"]
    return out


# What makes a bar spell a DPS ability for the queue: it deals damage (SpellEffect spell /
# weapon / leech damage or Attack, aura periodic damage / leech, an area trigger aimed at
# enemies: Volley, Hurricane, Blizzard), followed through triggered spells. An enemy effect
# that deals none (crowd control, taunts, curses and weakening debuffs, mana drains) is no DPS
# press: the ones that are (Hunter's Mark, Faerie Fire, Sunder) are on the lists, interrupts and
# CC have their own slot, gap closers their own queue. Or it is a combat-length self buff or summon (under
# gen_forever_defaults.SHORT_BUFF_SECS: Sweeping Strikes, seals, totems), the same cut that
# keeps a buff in the combat queue; or a combat form (stances, Shadowform, Bear / Cat Form -
# not the travel forms); or a trap (placed object). Other self-only spells (tracking, travel,
# pet care, conjuring, hour-long buffs) join only from the class's lists or the burst cooldowns.
DMG_EFFECTS = {2, 9, 17, 31, 58, 78, 121}
DMG_AURAS = {3, 53, 89}
AREA_TRIGGER = 179
ENEMY_TARGETS = {6, 15, 16, 24, 28, 53, 54}   # ImplicitTarget: enemy unit / area / cone
SELF_TARGETS = {1, 20}                        # ImplicitTarget: the caster / caster's party
APPLY_AURA, SUMMON, PLACE_OBJECT, SCRIPT_EFFECT = 6, 28, 104, 77
DUMMY_AURA = 4
SHAPESHIFT = 36
TRAVEL_FORMS = {3, 4, 16, 27, 29}   # shapeshift form ids: Travel, Aquatic, Ghost Wolf, flight
_effects = None


def effects_of(sid):
    """SpellEffect rows of sid as (effect, aura, trigger spell, implicit targets, misc value)."""
    global _effects
    if _effects is None:
        _effects = {}
        for r in cfa.rows("SpellEffect"):
            _effects.setdefault(r["SpellID"], []).append(
                (int(r["Effect"] or 0), int(r["EffectAura"] or 0), r.get("EffectTriggerSpell") or "0",
                 {int(r["ImplicitTarget_0"] or 0), int(r["ImplicitTarget_1"] or 0)},
                 int(r["EffectMiscValue_0"] or 0)))
    return _effects.get(str(sid), [])


def on_self(sid):
    """Does sid put an aura on the caster (a seal), not on an enemy (Fire Vulnerability)?"""
    return any(eff == APPLY_AURA and targets & SELF_TARGETS for eff, _, _, targets, _ in effects_of(sid))


def on_enemy(sid):
    """Infer omitted source-unit annotations only for exclusively enemy-applied auras."""
    return not on_self(sid) and any(eff == APPLY_AURA and targets & ENEMY_TARGETS
                                   for eff, _, _, targets, _ in effects_of(sid))


def aura_on_target(node, sid):
    source = node.get("sourceUnit", {}).get("type")
    return source == "CurrentTarget" or (not source and on_enemy(sid))


def deals_damage(sid, depth=0):
    for eff, aura, trig, targets, _ in effects_of(sid):
        if eff in DMG_EFFECTS or aura in DMG_AURAS or (eff == AREA_TRIGGER and targets & ENEMY_TARGETS):
            return True
        if depth < 2 and trig not in ("", "0") and deals_damage(trig, depth + 1):
            return True
    return False


def combat_buff(sid):
    """A self / party aura or a summon lasting under SHORT_BUFF_SECS (DURATION: rank 1), a
    combat form, or a trap."""
    effects = effects_of(sid)
    if any(eff == APPLY_AURA and aura == SHAPESHIFT and form not in TRAVEL_FORMS
           for eff, aura, _, _, form in effects):
        return True
    if any(eff == PLACE_OBJECT for eff, *_ in effects):
        return True
    if not 0 < DURATION.get(sid, 0) < gfd.SHORT_BUFF_SECS:
        return False
    return any((eff == APPLY_AURA and targets & SELF_TARGETS) or eff == SUMMON
               for eff, _, _, targets, _ in effects)


# The DPS queue holds damage presses only. A bar spell no list names still joins as a filler
# (Backstab, Holy Wrath, a wand or bow shot, a damage spell whose slow or root is a side effect),
# but not when its job is something other than damage, even if it hits too:
#   an interrupt on a cooldown longer than INTERRUPT_DPS_CD (Kick, Pummel, Shield Bash are kept
#   for the interrupt slot; Earth Shock at 6s stays eligible for custom queues but its
#   Forever utility role reserves it from the automatic queue);
#   crowd control or a taunt (Gouge, Scatter Shot, Pounce, Mind Control, Death Coil, Mocking Blow);
#   a movement, stealth or mount buff that deals no damage (Sprint, Dash, Stealth, Divine Steed);
#   NOT_DPS: what the data cannot tell from a combat buff or a damage spell, and utility the
#   player manages: a debuff whose job is a slow, root or mitigation (Demoralizing Shout,
#   Frost Nova) or healing (Vampiric Embrace), even where a guide lists it. Debuffs that raise
#   damage taken (Sunder Armor, Faerie Fire, Curse of the Elements, Hunter's Mark) stay.
# List entries are never filtered: a list that names one meant it.
INTERRUPT, TAUNT_EFFECT = 68, 114
TAUNT_AURA, STEALTH_AURA, SPEED_AURA, MOUNT_AURA = 11, 16, 31, 78
INTERRUPT_DPS_CD = 8
PUSHBACK_MAX_CD = 10
# SpellMechanic: charm, disoriented, fleeing, asleep, stunned, incapacitated, polymorphed,
# banished, shackled, turned, horrified, sapped
HARD_CC = {1, 2, 5, 10, 12, 14, 17, 18, 20, 23, 24, 30}
MOUNT_MECHANIC = 21
NOT_DPS = {
    "paladin": ["seal_of_justice", "seal_of_light", "seal_of_wisdom"],
    "rogue":   ["redirect"],
    "hunter":  ["flare", "enchanted_flare", "freezing_trap", "frost_trap"],
    "mage":    ["frost_nova"],
    "druid":   ["entangling_roots", "natures_grasp"],
    "warlock": ["health_funnel", "fel_domination"],
    "warrior": ["berserker_rage", "demoralizing_shout"],
    "priest":  ["focused_casting", "dark_sacrifice", "vampiric_embrace"],
}
NOT_DPS_ALL = ["grovel"]
# The queue is a damage queue in every tree, a tank tree included: its list is that talent
# style's damage order. Presses whose value is threat or mitigation leave the tank lists and the
# pool (the tank sims lead with them); tank play belongs to the defensive queue.
TANK_ONLY = {
    "warrior": ["shield_block", "defensive_stance", "demoralizing_shout"],
    "paladin": ["holy_shield"],
    "druid":   ["demoralizing_roar"],
}
_mechanic = _cooldown = None


def spell_meta(sid):
    """(SpellCategories mechanic, cooldown seconds) of sid."""
    global _mechanic, _cooldown
    if _mechanic is None:
        _mechanic = {r["SpellID"]: int(r["Mechanic"] or 0) for r in cfa.rows("SpellCategories")}
        _cooldown = {}
        for r in cfa.rows("SpellCooldowns"):
            ms = max(int(r["RecoveryTime"] or 0), int(r["CategoryRecoveryTime"] or 0))
            _cooldown[r["SpellID"]] = max(_cooldown.get(r["SpellID"], 0), ms / 1000)
    return _mechanic.get(str(sid), 0), _cooldown.get(str(sid), 0)


_effect_mechanics = None


def not_dps(sid, damage):
    """Why sid is no DPS press (see above), or None."""
    global _effect_mechanics
    if _effect_mechanics is None:
        _effect_mechanics = {}
        for r in cfa.rows("SpellEffect"):
            m = int(r["EffectMechanic"] or 0)
            if m:
                _effect_mechanics.setdefault(r["SpellID"], set()).add(m)
    effects = effects_of(sid)
    mech, cd = spell_meta(sid)
    mechanics = {mech} | _effect_mechanics.get(str(sid), set())
    if any(eff == INTERRUPT for eff, *_ in effects) and cd > INTERRUPT_DPS_CD:
        return "interrupt"
    if mechanics & HARD_CC:
        return "cc"
    if any(eff == TAUNT_EFFECT or (eff == APPLY_AURA and aura == TAUNT_AURA) for eff, aura, *_ in effects):
        return "taunt"
    if not damage and (MOUNT_MECHANIC in mechanics or any(
            eff == APPLY_AURA and aura in (STEALTH_AURA, SPEED_AURA, MOUNT_AURA) for eff, aura, *_ in effects)):
        return "movement"
    return None


def dot_fields(effects, duration):
    """Full damage over time of these aura effects (every tick of the duration): base, per-level
    gain, coefficient, seconds; and the tick period in seconds when every effect shares one."""
    periods = [int(o["EffectAuraPeriod"]) for o in effects]
    ticks = [duration // period for period in periods]
    fields = [
        sum(float(o["EffectBasePointsF"]) * n for o, n in zip(effects, ticks)),
        sum(float(o["EffectRealPointsPerLevel"]) * n for o, n in zip(effects, ticks)),
        sum(float(o["EffectBonusCoefficient"]) * n for o, n in zip(effects, ticks)),
        duration / 1000,   # seconds the damage over time runs
    ]
    return fields, (periods[0] / 1000 if len(set(periods)) == 1 else None)


def direct_damage_estimates(spell_ids):
    """Simple single-target, non-scaling rank damage; omit formulas we cannot model."""
    effects, levels, schools, durations = {}, {}, {}, {}
    duration_ms = {r["ID"]: int(r["Duration"]) for r in cfa.rows("SpellDuration")}
    for row in cfa.rows("SpellEffect"):
        if row["SpellID"].isdigit() and int(row["SpellID"]) in spell_ids:
            effects.setdefault(int(row["SpellID"]), []).append(row)
    for row in cfa.rows("SpellLevels"):
        if row["DifficultyID"] == "0":
            levels[int(row["SpellID"])] = row
    cast_ms = {r["ID"]: int(r["Base"]) for r in cfa.rows("SpellCastTimes")}
    casts = {}
    for row in cfa.rows("SpellMisc"):
        if row["DifficultyID"] == "0":
            schools[int(row["SpellID"])] = int(row["SchoolMask"])
            durations[int(row["SpellID"])] = duration_ms.get(row["DurationIndex"], 0)
            casts[int(row["SpellID"])] = cast_ms.get(row["CastingTimeIndex"], 0)
    result = {}
    for sid, rows in effects.items():
        damage = [r for r in rows if r["Effect"] == "2"]
        if any(r["DifficultyID"] != "0" for r in rows):
            continue
        if not damage:
            # A damage over time with a cast time and no hit (Corruption) is priced by its
            # total alone, so it can be weighed as the cast that opens a pull. An instant one
            # (Shadow Word: Pain) gains nothing before a pull: its row carries a 12th field, 1,
            # and is priced for measured damage only, never to choose an opener or a filler.
            level, school, duration = levels.get(sid), schools.get(sid, 0), durations.get(sid, 0)
            if not level or school not in (2, 4, 8, 16, 32, 64) or duration <= 0:
                continue
            if not all(
                    o["Effect"] == str(APPLY_AURA) and o["EffectAura"] == "3" and o["EffectTriggerSpell"] == "0"
                    and o["ImplicitTarget_0"] == "6" and o["ImplicitTarget_1"] == "0"
                    and int(o["EffectAuraPeriod"]) > 0 and float(o["EffectBasePointsF"]) > 0
                    and all(float(o[k]) == 0 for k in (
                        "ScalingClass", "Coefficient", "ResourceCoefficient", "EffectPointsPerResource",
                        "BonusCoefficientFromAP")) for o in rows):
                continue
            fields, period = dot_fields(rows, duration)
            result[sid] = [0, 0, int(level["SpellLevel"]), int(level["MaxLevel"]), 0, school.bit_length(), 1,
                           *fields, 1 if casts.get(sid, 0) <= 0 else 0]
            # Ticks land every period: the measurement prices a cut-short run by whole ticks.
            if period:
                result[sid].append(period)
            continue
        if len(damage) != 1:
            continue
        r = damage[0]
        if r["ImplicitTarget_0"] != "6" or r["ImplicitTarget_1"] != "0":
            continue
        if any(float(r[k]) != 0 for k in (
                "ScalingClass", "Coefficient", "ResourceCoefficient", "EffectPointsPerResource",
                "BonusCoefficientFromAP", "EffectTriggerSpell")):
            continue
        # A trailing damage-over-time on the same target (Holy Fire, Fireball) keeps the hit
        # priceable, flagged partial: the hit alone is not the spell's whole damage.
        # A script effect that triggers no spell (Immolate carries one) or a dummy aura that
        # triggers none (Flame Shock) deals no damage of its own and does not make the spell
        # unpriceable.
        others = [o for o in rows if o is not r and not (o["EffectTriggerSpell"] == "0" and (
            o["Effect"] == str(SCRIPT_EFFECT)
            or (o["Effect"] == str(APPLY_AURA) and o["EffectAura"] == str(DUMMY_AURA))))]
        partial = bool(others) and all(
            o["Effect"] == str(APPLY_AURA) and o["EffectAura"] == "3" and o["EffectTriggerSpell"] == "0"
            and o["ImplicitTarget_0"] == "6" for o in others)
        if not partial and any(
                o["EffectTriggerSpell"] != "0" or int(o["EffectAura"]) in DMG_AURAS for o in rows):
            continue
        level, school = levels.get(sid), schools.get(sid, 0)
        if not level or school not in (2, 4, 8, 16, 32, 64):
            continue
        base = float(r["EffectBasePointsF"])
        if base <= 0:
            continue
        result[sid] = [
            base, float(r["EffectRealPointsPerLevel"]), int(level["SpellLevel"]),
            int(level["MaxLevel"]), float(r["EffectBonusCoefficient"]), school.bit_length(),
        ]
        if partial:
            result[sid].append(1)
            # Full damage over time: every tick of the aura's duration. Unknown when the
            # duration or a period is missing, then the spell's total stays unknown.
            duration = durations.get(sid, 0)
            if duration > 0 and all(int(o["EffectAuraPeriod"]) > 0 for o in others):
                fields, period = dot_fields(others, duration)
                result[sid] += fields
                if period:
                    result[sid] += [0, period]   # not measure-only; tick interval
    return result


def keeps_combat_form(sid):
    """Does sid shapeshift into a combat form (not a travel form)? Marked form=true in the data: the
    runtime does not follow a tree that leads with a form the character has not learned."""
    return any(eff == APPLY_AURA and aura == SHAPESHIFT and form not in TRAVEL_FORMS
               for eff, aura, _, _, form in effects_of(sid))


def entry_lua(e, names):
    parts = [f"id={e['id']}", "gates=" + lua(e["gates"])]
    if keeps_combat_form(e["id"]):
        parts.append("form=true")
    if e["delegated"]:
        parts.append("delegated=true")
    if e.get("w"):
        parts.append("w=true")
    return "      {" + ",".join(parts) + "},  -- " + names.get(str(e["id"]), "?")


def condition_coverage(gates, path=""):
    """Evaluator coverage, not a claim that the current client can answer a read."""
    for index, gate in enumerate(gates, 1):
        key = f"{path}.{index}" if path else str(index)
        kind = gate["t"]
        if kind == "unconfirmed":
            status, reason = "disabled", "runtime always returns false"
        elif kind in ("dot", "debuff", "buff", "stack"):
            status = "partial"
            reason = {
                "dot": "target-health policy only; tracked own-DoT suppression is separate",
                "debuff": "presence requires exact aura evidence; own refresh may use cast estimates; remaining-time comparisons stay unknown",
                "buff": "window helper; ordinary ranking does not fully evaluate presence",
                "stack": "requires a usable spell-bound aura instance and threshold read",
            }[kind]
        elif kind in ("any", "all"):
            status, reason = "partial", "three-valued group; inspect child coverage and live verdicts"
        elif kind in ("power", "execute", "health") and gate.get("op") not in ("<", "<=", ">", ">="):
            status, reason = "partial", "runtime supports threshold operators only"
        elif kind in ("known", "stealth", "group", "targets", "totem", "near", "swing", "hit",
                      "resource", "power", "execute", "health", "cd", "prev", "starved", "cast"):
            status, reason = "fully supported", "runtime evaluator exists; live unknowns remain possible"
        else:
            status, reason = "partial", "no confirmed runtime evaluator"
        yield {"path": key, "condition": gate, "status": status, "reason": reason}
        yield from condition_coverage(gate.get("g", []), key)


def main():
    left_out = {}   # class -> tree -> ids an EXTRA drop took out
    form_masks = {}  # rank-1 class ability -> forms it can be cast in (bit form-1)
    shapeshift_masks = {r["SpellID"]: int(r["ShapeshiftMask_0"] or 0) for r in cfa.rows("SpellShapeshift")}
    names = {r["ID"]: r["Name_lang"] for r in cfa.rows("SpellName")}
    secs = {r["ID"]: int(r["Duration"] or 0) / 1000 for r in cfa.rows("SpellDuration")}
    charge_recovery = {r["ID"]: int(r["ChargeRecoveryTime"] or 0) / 1000
                       for r in cfa.rows("SpellCategory")}
    charge_categories = {}
    for r in cfa.rows("SpellCategories"):
        if int(r["ChargeCategory"] or 0):
            charge_categories.setdefault(r["SpellID"], set()).add(r["ChargeCategory"])
    for r in cfa.rows("SpellMisc"):
        d = secs.get(r["DurationIndex"], 0)
        if d > 0 and r["SpellID"].isdigit():
            DURATION[int(r["SpellID"])] = round(d, 1)
    commit = open(os.path.join(SRC, "UPSTREAM_COMMIT"), encoding="utf-8").read().strip()
    catalog = json.load(open(os.path.join(SRC, "presets", "catalog.json"), encoding="utf-8"))
    catalog_source = catalog["source"]
    catalog_commit = catalog_source["commit"]
    body, chains_out, report, unresolved, abilities, pushback_damage = [], {}, [], [], {}, {}
    learned_ids = set()
    coverage = []
    for cls in sorted(TREES):
        default, trees = TREES[cls]
        chains, by_id = cfa.class_chains(cfa.CLASS_MASK[cls])
        learned_ids.update(int(sid) for chain in chains.values() for sid, _ in chain)
        # EVERY learnable chain of the class, not just the list entries: the runtime
        # resolves any curated id (defensives, gap closers, interrupts...) to the rank the
        # player presses through these.
        for chain in chains.values():
            if len(chain) > 1:
                chains_out[rank1(chain)] = [int(i) for i, _ in chain]
        # Broad bar eligibility (rank 1), not final offensive admission. The curated
        # ABILITY_ROLES in Forever defaults route protection/utility out at runtime,
        # retaining eligibility for custom entries and Always Show overrides.
        # Abilities that deal damage or are combat buffs (deals_damage, combat_buff), the
        # curated burst cooldowns and damage racials (cfa.RACIAL_ROLES); list entries join below.
        # Racials join by that role only: Escape Artist passes as a short self buff, but it is
        # defensive, and an unclassified one (Rapid Regeneration) belongs to no combat queue.
        pool = set()
        for chain in chains.values():
            sid = rank1(chain)
            damage = any(deals_damage(i) for i, _ in chain)
            if (damage or combat_buff(sid)) and not_dps(sid, damage) is None:
                pool.add(sid)
            # Direct-damage candidates only. Runtime additionally checks instant cast,
            # range, usability, DoTs, interrupt state and the player's settings.
            if (any(eff in DMG_EFFECTS for eff, *_ in effects_of(sid))
                    and not any(aura in DMG_AURAS for i, _ in chain
                                for _, aura, *_ in effects_of(i))):
                cooldown = max(spell_meta(i)[1] for i, _ in chain)
                charges = {category for i, _ in chain for category in charge_categories.get(str(i), ())}
                if all(charge_recovery.get(category, 0) > 0 for category in charges):
                    cooldown = max([cooldown] + [charge_recovery[category] for category in charges])
                else:
                    cooldown = PUSHBACK_MAX_CD
                if cooldown < PUSHBACK_MAX_CD:
                    pushback_damage[sid] = cooldown
        for name in TANK_ONLY.get(cls, []):
            if name in chains:
                pool.discard(rank1(chains[name]))
            else:
                unresolved.append(f"{cls}: TANK_ONLY {name} is not learnable")
        for name in NOT_DPS.get(cls, []) + NOT_DPS_ALL:
            if name in chains:
                pool.discard(rank1(chains[name]))
            else:
                unresolved.append(f"{cls}: NOT_DPS {name} is not learnable")
        pool -= {i for ids in cfa.racials().values() for i in ids}
        pool |= {rank1(chains[n]) for n in gfd.BURST.get(cls, []) if n in chains}
        pool |= set(cfa.racial_ids("offensive"))
        body.append(f'  ["{cls.upper()}_F"] = {{')
        body.append(f'    default = "{default}",')
        for tree in sorted(trees):
            src, dropped = trees[tree], set()
            if src.startswith("pin:"):
                entries = convert_pin(src[4:], chains, unresolved)
            else:
                entries = convert_sim(src, by_id, dropped)
            for sid in ADD.get(cls, []):
                if not any(e["id"] == sid for e in entries):
                    entries.append({"id": sid, "delegated": False, "tiers": [t for t, _ in TIERS],
                                    "gates": [{"t": "buff", "id": sid, "dur": DURATION.get(sid), "neg": True}]})
            dropped_ids = add_extras(cls, tree, entries, chains, unresolved)
            if dropped_ids:
                left_out.setdefault(cls, {})[tree] = sorted(dropped_ids)
            regate(cls, tree, entries, chains)
            generalize_entries(cls, tree, entries, chains)
            if tree in TANK_TREES.get(cls, ()):
                tank_only = {rank1(chains[n]) for n in TANK_ONLY.get(cls, []) if n in chains}
                entries[:] = [e for e in entries if e["id"] not in tank_only]
            for sid in reversed(AOE_LEAD.get(cls, [])):
                if not any(e["id"] == sid for e in entries):
                    entries.insert(0, {"id": sid, "delegated": False, "tiers": list(AOE_LEAD_TIERS), "gates": []})
            apply_core_rules(cls, tree, entries)
            entries.sort(key=lambda e: 0 if keeps_own_buff(e) else 1)   # stable: sim order otherwise
            lists = tier_lists(entries)
            apply_core_gates(lists)
            one_stack_on_packs(lists)
            pool |= {e["id"] for e in entries}
            body.append(f"    {tree} = {{  -- {src}")
            for t, _ in TIERS:
                if t in lists:
                    for index, entry in enumerate(lists[t] if "--coverage" in sys.argv else [], 1):
                        identity = {"class": cls, "tree": tree, "context": t,
                                    "entry": index, "spell": entry["id"], "source": src}
                        coverage.extend(dict(identity, **row)
                                        for row in condition_coverage(entry["gates"]))
                        if entry["delegated"]:
                            coverage.append(dict(
                                identity, path="delegated", status="delegated",
                                reason="unsupported source condition omitted",
                                lost=LOST.get(id(entry)) or ["hand pin: inspect source condition"],
                            ))
                    body.append(f"      {t} = {{")
                    body += ["  " + entry_lua(e, names) for e in lists[t]]
                    body.append("      },")
            body.append("    },")
            gated = sum(1 for e in entries if e["gates"])
            deleg = sum(1 for e in entries if e["delegated"])
            drop = ", ".join(f"{names.get(str(s), '?')} ({s})" for s in sorted(dropped))
            report.append(f"{cls:8s} {tree:14s} {len(entries):3d} entries {gated:3d} gated "
                          f"{deleg:3d} delegated  dropped: {drop or '-'}")
            if "--audit" in sys.argv:   # why each delegated entry is (it can never lead)
                for e in entries:
                    if e["delegated"]:
                        lost = LOST.get(id(e)) or ["(hand pin: see the .simc line)"]
                        report.append(f"    {names.get(str(e['id']), '?')} ({e['id']}): " + " | ".join(lost))
        body.append("  },")
        abilities[cls] = sorted(pool)
        # Forms each class ability can be cast in (SpellShapeshift.ShapeshiftMask_0: bit form-1);
        # only abilities with a mask. In a form the mask leaves out, casting would leave the form.
        for sid in pool:
            mask = shapeshift_masks.get(str(sid))
            if mask:
                form_masks[sid] = mask

    if "--coverage" in sys.argv:
        if unresolved:
            sys.exit("UNRESOLVED hand-pin tokens:\n  " + "\n  ".join(unresolved))
        counts = {status: sum(row["status"] == status for row in coverage)
                  for status in ("fully supported", "partial", "delegated", "disabled")}
        print(json.dumps({
            "engine_revision": commit, "preset_revision": catalog_commit,
            "scope": "post-adaptation target-tier condition occurrences; not live validation",
            "counts": counts, "conditions": coverage,
        }, indent=2))
        return

    rank_lines = [f"  [{k}] = {lua(v)}," for k, v in sorted(chains_out.items())]
    # tools/ is not packaged (.pkgmeta), so the MIT notice must travel inside this file.
    mit = ["--   " + l.rstrip() if l.strip() else "--" for l in
           open(os.path.join(SRC, "LICENSE"), encoding="utf-8").read().strip().splitlines()]
    text = "\n".join([
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2024-2026 wealdly",
        "--",
        "-- JustAC: WoW Forever priority lists, per class and talent tree, with secret-safe",
        "-- gates. GENERATED by tools/gen_forever_rotations.py - do not edit by hand.",
        "--",
        "-- Orderings and conditions adapt the MIT-licensed MythicSim Forever presets",
        "-- (https://github.com/sage3648/mythicsim-forever-engine,",
        f"-- commit {commit}); the mirrored catalog cites",
        f"-- {catalog_source['repository']}/{catalog_source['path']} at commit {catalog_commit}.",
        "--",
        *mit,
        "--",
        "-- Trees marked pin: are JustAC hand pins (tools/simc-apl-forever/).",
        "-- Keys: <CLASS>_F -> tree -> st / cleave / aoe (omitted = same as the next wider tier).",
        "-- Ids are rank 1; rankChains lists every rank so the runtime can show the highest known.",
        "",
        "local RotationImport = LibStub(\"JustAC-RotationImport\", true)",
        "if not RotationImport or not RotationImport.RegisterForever then return end",
        "",
        "RotationImport.RegisterForever({",
        *body,
        "}, {",
        *rank_lines,
        "}, {",
        *[f'  ["{c.upper()}_F"] = {lua(v)},' for c, v in sorted(abilities.items())],
        "}, {",
        *[f"  [{sid}] = {seconds:g},  -- {names.get(str(sid), '?')}"
          for sid, seconds in sorted(pushback_damage.items())],
        "}, {",
        "  -- Exact rank -> average base damage, per-level gain, spell/max level, SP coefficient, school,",
        "  -- then 1 when a damage over time follows the hit, and that",
        "  -- damage over time's full-duration base, per-level gain and SP coefficient when known.",
        *[f"  [{sid}] = {{{','.join(f'{v:g}' for v in values)}}},"
          for sid, values in sorted(direct_damage_estimates(learned_ids).items())],
        "}, {",
        "  -- Left out: class abilities a tree's list deliberately drops; the queue keeps them out",
        "  -- wherever that tree's list does not name them, rather than offering an unranked filler.",
        *[f'  ["{c.upper()}_F"] = {lua(dict(sorted(trees_out.items())))},'
          for c, trees_out in sorted(left_out.items())],
        "}, {",
        "  -- Forms a class ability can be cast in (bit form-1, ShapeshiftMask): in a form it leaves",
        "  -- out, an unlisted ability is not offered (casting it would leave the form).",
        *[f"  [{sid}] = {mask},  -- {names.get(str(sid), '?')}" for sid, mask in sorted(form_masks.items())],
        "})",
        "",
    ])
    if "--print" in sys.argv:
        print(text)
    else:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote", OUT)
    print("\n".join(report))
    if ANCHOR_MISSES:
        print("EXTRA anchors not found:\n  " + "\n  ".join(ANCHOR_MISSES))
    if unresolved:
        print("UNRESOLVED hand-pin tokens:\n  " + "\n  ".join(unresolved))
        sys.exit(1)


if __name__ == "__main__":
    main()
