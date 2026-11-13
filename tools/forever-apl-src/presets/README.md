# Rotation presets

The default rotations (APLs) MythicSim runs for every World of Warcraft: Forever
spec, and the other playstyles Advanced settings offers. Each file is the
`rotation` of a player in a sim request, in the same JSON the engine reads
(`type`, `prepullActions`, `priorityList`).

These files are a generated mirror of the presets in the MythicSim
application (`api/data/forever_rotations.json` at commit `4bf1541700`), refreshed
whenever a preset changes. [`catalog.json`](catalog.json) lists each
spec's choices, its default and the stats its stat weights run weighs.

## What a sim runs

A preset is where a run starts. For a given character the sim then:

- drops any line that casts a spell the character does not have (untrained
  ranks, talents not taken), so one preset serves every talent build;
- applies the class options from Advanced settings, which can add or swap
  lines (a Warlock's Wrack filler, a Rogue's poison swap, a Paladin's seal);
- runs your own rotation instead when you paste one under Customise rotation.

To see the exact rotation a sim ran, open its result, choose Re-sim, then
**Advanced settings > Rotation > Customise rotation** and switch the editor to
**JSON**: it starts from that sim's rotation, line for line.

## Proposing a change

Open a pull request that edits the file here, with what you changed and a sim
(or a log) that shows it doing better. Changes are A/B tested on the reference
builds and adopted when they win every case; an adopted change goes into
MythicSim and comes back here with the next mirror, so do not hand-edit files
that are not part of your change.

## Index

| Spec | Rotation | | File |
|---|---|---|---|
| Affliction Warlock | Affliction | default | [`warlock/dps/affliction.apl.json`](warlock/dps/affliction.apl.json) |
| Affliction Warlock | Demonic Pact |  | [`warlock/dps/demonic_pact.apl.json`](warlock/dps/demonic_pact.apl.json) |
| Affliction Warlock | DS/Ruin |  | [`warlock/dps/ds_ruin.apl.json`](warlock/dps/ds_ruin.apl.json) |
| Affliction Warlock | Shadow and Flame |  | [`warlock/dps/destruction_conflag.apl.json`](warlock/dps/destruction_conflag.apl.json) |
| Arcane Mage | Arcane | default | [`mage/dps/arcane.apl.json`](mage/dps/arcane.apl.json) |
| Arcane Mage | Fire |  | [`mage/dps/fire.apl.json`](mage/dps/fire.apl.json) |
| Arcane Mage | Fire (low rank) |  | [`mage/dps/fire_lowrank.apl.json`](mage/dps/fire_lowrank.apl.json) |
| Arcane Mage | Frost |  | [`mage/dps/frost.apl.json`](mage/dps/frost.apl.json) |
| Arcane Mage | Frostfire hybrid (experimental) |  | [`mage/dps/frostfire.apl.json`](mage/dps/frostfire.apl.json) |
| Assassination Rogue | Mutilate | default | [`rogue/dps/forever_mutilate.apl.json`](rogue/dps/forever_mutilate.apl.json) |
| Assassination Rogue | Hemorrhage |  | [`rogue/dps/forever_hemorrhage.apl.json`](rogue/dps/forever_hemorrhage.apl.json) |
| Assassination Rogue | Sinister Strike |  | [`rogue/dps/combat_sinister_strike.apl.json`](rogue/dps/combat_sinister_strike.apl.json) |
| Assassination Rogue | Backstab |  | [`rogue/dps/combat_backstab.apl.json`](rogue/dps/combat_backstab.apl.json) |
| Assassination Rogue | Venom (Ambiwar) |  | [`rogue/dps/venom.apl.json`](rogue/dps/venom.apl.json) |
| Balance Druid | Launch | default | [`druid/balance/launch.apl.json`](druid/balance/launch.apl.json) |
| Balance Druid | Starfire (no Eclipse) |  | [`druid/balance/default.apl.json`](druid/balance/default.apl.json) |
| Combat Rogue | Sinister Strike | default | [`rogue/dps/combat_sinister_strike.apl.json`](rogue/dps/combat_sinister_strike.apl.json) |
| Combat Rogue | Sinister Strike (Sweaty) |  | [`rogue/dps/combat_sinister_strike_sweaty.apl.json`](rogue/dps/combat_sinister_strike_sweaty.apl.json) |
| Combat Rogue | Improved Expose Armor (SS) |  | [`rogue/dps/combat_sinister_strike_iea.apl.json`](rogue/dps/combat_sinister_strike_iea.apl.json) |
| Combat Rogue | Backstab |  | [`rogue/dps/combat_backstab.apl.json`](rogue/dps/combat_backstab.apl.json) |
| Combat Rogue | Backstab (Sweaty) |  | [`rogue/dps/combat_backstab_sweaty.apl.json`](rogue/dps/combat_backstab_sweaty.apl.json) |
| Combat Rogue | Mutilate |  | [`rogue/dps/forever_mutilate.apl.json`](rogue/dps/forever_mutilate.apl.json) |
| Combat Rogue | Hemorrhage |  | [`rogue/dps/forever_hemorrhage.apl.json`](rogue/dps/forever_hemorrhage.apl.json) |
| Demonology Warlock | Demonic Pact | default | [`warlock/dps/demonic_pact.apl.json`](warlock/dps/demonic_pact.apl.json) |
| Demonology Warlock | Affliction |  | [`warlock/dps/affliction.apl.json`](warlock/dps/affliction.apl.json) |
| Demonology Warlock | DS/Ruin |  | [`warlock/dps/ds_ruin.apl.json`](warlock/dps/ds_ruin.apl.json) |
| Demonology Warlock | Shadow and Flame |  | [`warlock/dps/destruction_conflag.apl.json`](warlock/dps/destruction_conflag.apl.json) |
| Destruction Warlock | Shadow and Flame | default | [`warlock/dps/destruction_conflag.apl.json`](warlock/dps/destruction_conflag.apl.json) |
| Destruction Warlock | DS/Ruin |  | [`warlock/dps/ds_ruin.apl.json`](warlock/dps/ds_ruin.apl.json) |
| Destruction Warlock | Affliction |  | [`warlock/dps/affliction.apl.json`](warlock/dps/affliction.apl.json) |
| Destruction Warlock | Demonic Pact |  | [`warlock/dps/demonic_pact.apl.json`](warlock/dps/demonic_pact.apl.json) |
| Destruction Warlock | Fire (Incinerate) |  | [`warlock/dps/destruction_fire.apl.json`](warlock/dps/destruction_fire.apl.json) |
| Discipline Priest | Penance, Binding Heal and Renew | default | [`priest/healer/default.apl.json`](priest/healer/default.apl.json) |
| DPS Warrior | Automatic (Arms or Fury) | default | [`warrior/dps/dps_reck.apl.json`](warrior/dps/dps_reck.apl.json) |
| DPS Warrior | DPS (No Reck) |  | [`warrior/dps/dps_no_reck.apl.json`](warrior/dps/dps_no_reck.apl.json) |
| DPS Warrior | Arms |  | [`warrior/dps/arms.apl.json`](warrior/dps/arms.apl.json) |
| Elemental Shaman | Default | default | [`shaman/elemental/forever.apl.json`](shaman/elemental/forever.apl.json) |
| Elemental Shaman | Elehance melee weave (Experimental) |  | [`shaman/elemental/elehance.apl.json`](shaman/elemental/elehance.apl.json) |
| Enhancement Shaman | Default | default | [`shaman/enhancement/forever.apl.json`](shaman/enhancement/forever.apl.json) |
| Feral Bear Druid | Bear | default | [`druid/feralbear/default.apl.json`](druid/feralbear/default.apl.json) |
| Feral Druid | Feral | default | [`druid/feralcat/default.apl.json`](druid/feralcat/default.apl.json) |
| Feral Druid | Simple Vaelastrasz |  | [`druid/feralcat/simple_vael.apl.json`](druid/feralcat/simple_vael.apl.json) |
| Fire Mage | Fire | default | [`mage/dps/fire.apl.json`](mage/dps/fire.apl.json) |
| Fire Mage | Fire (low rank) |  | [`mage/dps/fire_lowrank.apl.json`](mage/dps/fire_lowrank.apl.json) |
| Fire Mage | Arcane |  | [`mage/dps/arcane.apl.json`](mage/dps/arcane.apl.json) |
| Fire Mage | Frost |  | [`mage/dps/frost.apl.json`](mage/dps/frost.apl.json) |
| Fire Mage | Frostfire hybrid (experimental) |  | [`mage/dps/frostfire.apl.json`](mage/dps/frostfire.apl.json) |
| Frost Mage | Frost | default | [`mage/dps/frost.apl.json`](mage/dps/frost.apl.json) |
| Frost Mage | Arcane |  | [`mage/dps/arcane.apl.json`](mage/dps/arcane.apl.json) |
| Frost Mage | Fire |  | [`mage/dps/fire.apl.json`](mage/dps/fire.apl.json) |
| Frost Mage | Fire (low rank) |  | [`mage/dps/fire_lowrank.apl.json`](mage/dps/fire_lowrank.apl.json) |
| Frost Mage | Frostfire hybrid (experimental) |  | [`mage/dps/frostfire.apl.json`](mage/dps/frostfire.apl.json) |
| Holy Paladin | Flash of Light | default | [`paladin/holy/flash_of_light.apl.json`](paladin/holy/flash_of_light.apl.json) |
| Holy Paladin | Holy Light |  | [`paladin/holy/holy_light.apl.json`](paladin/holy/holy_light.apl.json) |
| Holy Priest | Penance, Binding Heal and Renew | default | [`priest/healer/default.apl.json`](priest/healer/default.apl.json) |
| Hunter | Beast Mastery | default | [`hunter/dps/bm.apl.json`](hunter/dps/bm.apl.json) |
| Hunter | Marksmanship |  | [`hunter/dps/mm.apl.json`](hunter/dps/mm.apl.json) |
| Hunter | Survival |  | [`hunter/dps/sv.apl.json`](hunter/dps/sv.apl.json) |
| Hunter | Melee weave (Experimental) |  | [`hunter/dps/melee_weave.apl.json`](hunter/dps/melee_weave.apl.json) |
| Hunter | Survival weave, Sanctum (Experimental) |  | [`hunter/dps/survival_weave.apl.json`](hunter/dps/survival_weave.apl.json) |
| Hunter | Survival light weave, Arc (Experimental) |  | [`hunter/dps/survival_light_weave.apl.json`](hunter/dps/survival_light_weave.apl.json) |
| Hunter | Survival (melee) |  | [`hunter/dps/sv_melee.apl.json`](hunter/dps/sv_melee.apl.json) |
| Marksmanship Hunter | Marksmanship | default | [`hunter/dps/mm.apl.json`](hunter/dps/mm.apl.json) |
| Marksmanship Hunter | Beast Mastery |  | [`hunter/dps/bm.apl.json`](hunter/dps/bm.apl.json) |
| Marksmanship Hunter | Survival |  | [`hunter/dps/sv.apl.json`](hunter/dps/sv.apl.json) |
| Marksmanship Hunter | Melee weave (Experimental) |  | [`hunter/dps/melee_weave.apl.json`](hunter/dps/melee_weave.apl.json) |
| Marksmanship Hunter | Survival weave, Sanctum (Experimental) |  | [`hunter/dps/survival_weave.apl.json`](hunter/dps/survival_weave.apl.json) |
| Marksmanship Hunter | Survival light weave, Arc (Experimental) |  | [`hunter/dps/survival_light_weave.apl.json`](hunter/dps/survival_light_weave.apl.json) |
| Marksmanship Hunter | Survival (melee) |  | [`hunter/dps/sv_melee.apl.json`](hunter/dps/sv_melee.apl.json) |
| Protection Paladin | P5 Prot | default | [`paladin/protection/p5.apl.json`](paladin/protection/p5.apl.json) |
| Protection Paladin | Basic Prot |  | [`paladin/protection/default.apl.json`](paladin/protection/default.apl.json) |
| Protection Paladin | Ret-prot hybrid (Experimental) |  | [`paladin/protection/ret_prot.apl.json`](paladin/protection/ret_prot.apl.json) |
| Protection Paladin | Holy-prot hybrid (Experimental) |  | [`paladin/protection/holy_prot.apl.json`](paladin/protection/holy_prot.apl.json) |
| Protection Warrior | Protection | default | [`warrior/protection/protection.apl.json`](warrior/protection/protection.apl.json) |
| Protection Warrior | DPS (No Reck) |  | [`warrior/protection/dps_no_reck.apl.json`](warrior/protection/dps_no_reck.apl.json) |
| Protection Warrior | DPS (With Reck) |  | [`warrior/protection/dps_reck.apl.json`](warrior/protection/dps_reck.apl.json) |
| Protection Warrior | Protection damage (Recklessness) |  | [`warrior/protection/damage.apl.json`](warrior/protection/damage.apl.json) |
| Protection Warrior | Fury-prot shield (Experimental) |  | [`warrior/protection/fury_prot.apl.json`](warrior/protection/fury_prot.apl.json) |
| Restoration Druid | Rejuvenation and Healing Touch | default | [`druid/restoration/default.apl.json`](druid/restoration/default.apl.json) |
| Restoration Shaman | Chain Heal and Riptide | default | [`shaman/restoration/default.apl.json`](shaman/restoration/default.apl.json) |
| Retribution Paladin | Basic Ret | default | [`paladin/retribution/default.apl.json`](paladin/retribution/default.apl.json) |
| Retribution Paladin | Shockadin hybrid (Experimental) |  | [`paladin/retribution/shockadin.apl.json`](paladin/retribution/shockadin.apl.json) |
| Shadow Priest | Shadow | default | [`priest/dps/shadow.apl.json`](priest/dps/shadow.apl.json) |
| Shadow Priest | Smite |  | [`priest/dps/smite.apl.json`](priest/dps/smite.apl.json) |
| Subtlety Rogue | Hemorrhage | default | [`rogue/dps/forever_hemorrhage.apl.json`](rogue/dps/forever_hemorrhage.apl.json) |
| Subtlety Rogue | Backstab |  | [`rogue/dps/combat_backstab.apl.json`](rogue/dps/combat_backstab.apl.json) |
| Subtlety Rogue | Backstab (Sweaty) |  | [`rogue/dps/combat_backstab_sweaty.apl.json`](rogue/dps/combat_backstab_sweaty.apl.json) |
| Subtlety Rogue | Mutilate |  | [`rogue/dps/forever_mutilate.apl.json`](rogue/dps/forever_mutilate.apl.json) |
| Survival Hunter | Survival (melee) | default | [`hunter/dps/sv_melee.apl.json`](hunter/dps/sv_melee.apl.json) |
| Survival Hunter | Melee weave (Experimental) |  | [`hunter/dps/melee_weave.apl.json`](hunter/dps/melee_weave.apl.json) |
| Survival Hunter | Survival weave, Sanctum (Experimental) |  | [`hunter/dps/survival_weave.apl.json`](hunter/dps/survival_weave.apl.json) |
| Survival Hunter | Survival light weave, Arc (Experimental) |  | [`hunter/dps/survival_light_weave.apl.json`](hunter/dps/survival_light_weave.apl.json) |
| Survival Hunter | Melee-first weave (Experimental) |  | [`hunter/dps/sv_melee_weave.apl.json`](hunter/dps/sv_melee_weave.apl.json) |
