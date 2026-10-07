# Hunter, Mage and Warlock - WoW Forever guide references

researched 2026-10-07

Scope: WoW Forever (camelot) beta, level cap 30. Every guide found is a
**level 30 beta** guide; no source has a tested level 60 rotation yet (several
show a "Level 60" tab that is a placeholder or a projected talent tree only).
All rotation lists below are paraphrased summaries, not guide text.

Site key used in the tables:
- IV = icy-veins.com/wow-forever (WebFetch 403; read via built-in browser)
- MOB = mobalytics.gg/wow-forever (WebFetch 403; read via built-in browser)
- TBC = wowtbc.gg/warcraftforever (WebFetch OK; short priority lists only)
- MGG = method.gg/wow-forever (WebFetch OK; leveling guides per class)
- WT = warcrafttavern.com/forever (WebFetch OK; class overview pages)
- WGG = wow.gg/guides/*-forever-overview (WebFetch OK; dated 2026-09-19, uses
  some talent names that differ from the current beta - see Gaps)

Cross-class facts that matter for a suggestion engine:
- Pets (hunter and warlock) now scale with the player's stats (IV, MOB, WT).
- DoTs can crit (warlock; also Ignite/Frostfire DoT for mage) (IV, MOB).
- Haste does not speed up warlock DoTs or drains, only casts (IV warlock overview).
- Blizzard blue post 2026-09-23: Auto Shot and wands are meant to have a 0.5 s
  cast before each shot; a bug made it shorter, fix promised for a following
  beta build (us.forums.blizzard.com/en/wow/t/2359185).
- "Legacy" account perk (Talented rank 5) can grant up to 5 extra talent points
  at 30; every guide gives a separate recommendation for those points.

---

## Hunter - Beast Mastery

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/beast-mastery-hunter-ranged-dps-pve-guide | spec guide (leveling + rotation) | updated 2026-10-05, level 30 | OK (browser) |
| IV | https://www.icy-veins.com/wow-forever/hunter-class-overview | class changes overview | added 2026-09-12 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/beast-mastery-hunter-guide | spec guide | 2026-10-01, level 30 (60 tab = placeholder) | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/hunter-leveling-guide | leveling guide (BM) | 2026-10-01, 1-30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/guides/hunter-class-overview | class changes overview | 2026-09-18 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/beast-mastery-hunter/ | priority list | "Level 30 (Beta)" | OK |
| MGG | https://www.method.gg/wow-forever/wow-forever-hunter-leveling-guide-and-talents | leveling guide | 2026-10-04 | OK |
| WT | https://www.warcrafttavern.com/forever/guides/hunter/ | class overview | level 20/30 beta | OK |
| WGG | https://wow.gg/guides/hunter-beast-mastery-forever-overview | spec overview | 2026-09-19 | OK |

**Rotation (single target)**

IV (leveling/solo framing, level 30):
1. Hunter's Mark on the target before the pull.
2. Send pet in first (abilities on autocast); let it build threat.
3. Serpent Sting once the pet has hit the target.
4. Summon Hawk on cooldown, aiming to keep 2 hawks out.
5. Aimed Shot on cooldown.
6. Auto Shot continuously.
7. Disengage if you pull threat off the pet.
8. Arcane Shot only when mana is capped AND both hawks will still be up for more than ~6 s.
9. Keep Auto Shotting to the kill; Mend Pet as needed.

TBC (short priority, raid-flavoured):
1. Aspect of the Hawk up. 2. Trueshot Aura. 3. Hunter's Mark kept up.
4. Rapid Fire + Bestial Wrath + on-use trinkets together. 5. Intimidation.
6. Serpent Sting kept up. 7. Summon Hawk if fewer than 2 active.
8. Aimed Shot. 9. Auto Shot.

MOB: Hunter's Mark, pet in, then Summon Hawk immediately and again 6 s later so
2 are up; Auto Shot then Serpent Sting / Aimed Shot / Multi-Shot between shots.
Intimidation (level 30) early in the fight for pet threat. Arcane Shot only in
the window where both hawks are up and the first has not expired.

MOB leveling guide disagrees on order: it says the second hawk is only worth
casting if the target will live a while, and that the Arcane Shot/hawk shared
cooldown is why Arcane Shot is mostly dropped.

WGG: hawks on durable targets, Arcane Shot instead on low-health targets
(burst finish); Bestial Wrath when the pet can attack for the full buff.

Disagreements: TBC has Bestial Wrath/Trueshot Aura which a level 30 BM cannot
have (BW needs 31 points); its list is a projection. IV and MOB agree on the
"2 hawks, Arcane Shot only in spare windows" rule.

**AoE**: IV/MOB/MGG: Multi-Shot replaces Aimed Shot (they share a cooldown -
see Forever changes). Explosive Trap and Frost Trap in combat (MOB group
section). Bear pet Swipe for pet AoE threat (IV).

**Opener**: Hunter's Mark pre-pull -> pet attack -> wait for pet threat -> Serpent Sting / Summon Hawk (IV, MOB).

**Upkeep**
- Aspect of the Hawk in combat (Deadly Aspects talent procs a 30% haste buff
  for 12 s off Hawk - IV); Aspect of the Cheetah out of combat/travel (no
  mounts before 40); never fight in Cheetah.
- Hunter's Mark on main target; Serpent Sting on targets that live.
- Pet: tame at 10. Happiness and loyalty still exist - feed the pet (IV, MOB).
  Pets are Ferocity/Cunning/Tenacity, no type damage modifier, each family has
  a unique ability; abilities still learned by taming (IV). Suggested pets:
  Bear (Swipe cleave, 5 s cd) (IV); Boar (Charge, easy diet) then Tallstrider
  (Dust Cloud armor pen) (MOB). Mend Pet / Revive Pet (Improved Revive Pet
  talent for in-combat revive).
- Trueshot Aura only if specced (MM tree).

**Defensives**: Feign Death (threat reset; pet still gets attacked) - MGG lists
it at level 30. Disengage (threat drop). Concussive Shot / Wing Clip to kite;
Freezing Trap on one of two attackers; Frost Trap slow. Intimidation (pet stun,
level 30 talent). Health potions/bandages.

**Forever-specific changes**
- **Summon Hawk** (BM talent, level 25 per IV and MGG): summons a hawk for
  18 s, max 2 at once, **shares its cooldown with Arcane Shot** (MOB: 6 s cd).
  Unleashed Fury / Ferocity also buff hawks.
- **Abilities no longer clip Auto Shot**; you still must stand still to shoot
  (IV overview). Intended 0.5 s pre-shot cast (blue post, see top).
- **Aimed Shot is baseline** (learned level 20 per MGG/IV) and **shares its
  cooldown with Multi-Shot** (IV overview; WGG gives 6 s shared cd).
- Traps usable in combat.
- Aspect of the Beast now grants melee attack power.
- New/changed BM talents: Deadly Aspects (Hawk-aspect haste proc), Focused Fire
  (+dmg while pet is out), Pathfinding, Improved Revive Pet, Bestial Swiftness.
- Trainer milestones (MOB): 10 Tame Beast, 18 Multi-Shot, 26 Rapid Fire.

**Gaps**: no tested level 60 BM rotation; no dead-zone handling detail beyond
"Raptor Strike / Mongoose Bite if they reach you"; Bestial Wrath timing only
from TBC projection; Summon Hawk exact cooldown only from MOB/WGG (IV does not
state it).

---

## Hunter - Marksmanship

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/marksmanship-hunter-ranged-dps-pve-guide | spec guide | updated 2026-10-05, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/marksmanship-hunter-guide | spec guide | 2026-10-01, level 30 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/marksmanship-hunter/ | priority list | "Level 30 (Beta)" | OK |
| WGG | https://wow.gg/guides/hunter-marksmanship-forever-overview | spec overview | 2026-09-19 | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-chasseur-precision-wow-forever/ | talent build | 2026-09-14 (pre-beta) | OK |
| (shared) | IV / MOB hunter class overviews, WT, MGG (see BM table) | | | OK |

**Rotation (single target)**

IV (level 30): Hunter's Mark pre-pull -> pet in -> Serpent Sting once pet has
aggro -> Aimed Shot on cooldown -> Auto Shot -> Disengage on threat -> Arcane
Shot only when mana capped -> Auto Shot to kill. Mend Pet and Serpent Sting are
the efficient mana uses.

TBC: 1. Aspect of the Hawk. 2. Trueshot Aura. 3. Hunter's Mark. 4. Rapid Fire
with on-use items. 5. Serpent Sting kept up. 6. Sniper Shot. 7. Aimed Shot.
8. Auto Shot.

MOB: pet in, Hunter's Mark, max range; Auto Shot then Serpent Sting / Aimed
Shot / Arcane Shot, Multi-Shot from 18. Keeping Serpent Sting up matters with
Rapid Killing because a kill under your sting grants the next-shot buff for the
following mob.

WGG: Serpent Sting on durable targets (Rapid Recuperation mana); alternate
Aimed Shot and Multi-Shot on their shared cd; Sniper Shot only when you have
time and space for the long cast.

**AoE**: Multi-Shot (shares cd with Aimed). IV's level 30 MM build (21 MM
points with Lone Wolf + Trueshot Aura) is explicitly a dungeon-AoE build; it
says the BM build is better for general play at 30. Explosive/Frost Trap.

**Opener**: same as BM. Rapid Fire on harder targets but it pulls threat off
the pet (MOB).

**Upkeep**: Aspect of the Hawk; Hunter's Mark; Serpent Sting (also feeds
Rapid Killing / Rapid Recuperation); Trueshot Aura; pet OR no pet with Lone
Wolf (+20% damage while no pet is active; does not combine with Focused Fire -
WGG). Pet on Defensive stance (MOB).

**Defensives**: as BM - Feign Death, Disengage, Scatter Shot (WGG lists a 4 s
disorient), Concussive Shot, Wing Clip, Freezing/Frost Trap.

**Forever-specific changes**
- **Sniper Shot** - MM capstone. Conflicts: IV MM guide says a 4 s
  **cooldown**; IV overview and WGG say a **4 s cast time**, WGG adds a 15 s
  cooldown and 8-35 yd range; kami-labs (pre-beta) describes +160 ranged damage
  and +10 yd range on the next 3 shots. Not usable at 30 without Legacy points
  per IV (needs deep MM).
- **Lone Wolf** (early MM talent): +20% damage with no pet.
- **Rapid Killing**: Rapid Fire cd -1 min; a kill under your Serpent Sting
  grants +10% damage on the next shot within 20 s (MOB overview).
- **Rapid Recuperation**: Serpent Sting hits and consuming Rapid Killing grant
  temporary in-cast mana regen (MOB overview).
- **Careful Aim**: AP from Intellect.
- Lethal Shots reworked into Lethal Attacks (applies beyond ranged).
- Removed: Improved Hunter's Mark, Improved Scorpid Sting, others (MOB, kami).
- Shared hunter changes (Aimed Shot baseline + Multi-Shot shared cd, no Auto
  Shot clipping, in-combat traps) as in BM.

**Gaps**: Sniper Shot numbers disagree between sources; no source covers the
level 60 Aimed/Multi/Arcane/Sniper interaction with a tested sequence;
Rapid Killing proc window handling not in any priority list.

---

## Hunter - Survival

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-guide | spec guide | updated 2026-10-05, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/survival-hunter-guide | spec guide | 2026-10-01, level 30 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/survival-hunter/ | priority list | "Level 30 (Beta)" | OK |
| WGG | https://wow.gg/guides/hunter-survival-forever-overview | spec overview | 2026-09-19 (older talent names) | OK |
| (shared) | IV / MOB hunter class overviews | | | OK |

**Rotation (single target)**

IV melee (level 30, fully Survival-specced; ranged is still better before that):
1. Hunter's Mark pre-pull. 2. Pet in. 3. Serpent Sting after pet aggro.
4. Run in; Raptor Strike on cooldown. 5. Mongoose Bite whenever usable.
6. Strider Kick on cooldown. 7. Disengage on threat.
IV ranged fallback for SV: same as MM list (Aimed Shot, Auto Shot, Arcane Shot if spare mana).

TBC: 1. Aspect of the Beast. 2. Hunter's Mark. 3. Rapid Fire with on-use
items. 4. Mongoose Bite when Expose Prey has activated it. 5. Immolation Trap
kept up. 6. Strider Kick. 7. Raptor Strike.

MOB: open at range (Aimed Shot, Auto Shot, Serpent Sting/Arcane Shot,
Multi-Shot), deliberately pull the mob to you, then Raptor Strike + Strider
Kick, Mongoose Bite and Counterattack when they light up; Deterrence to boost
parries/Counterattack (5 min cd, save for multi-pulls). Says a two-hander
probably beats dual wield at 30 despite Predator's Edge.

WGG (older build naming): Hunter's Mark, "Runner's Strike" on cd, Mongoose Bite
via marked-target procs, Raptor Strike, Counterattack after parry.

Disagreement: IV uses Aspect of the Hawk in its text; TBC uses Aspect of the
Beast for melee (Beast is the new melee-AP aspect). IV says melee only beats
ranged at 30 when fully specced; MOB recommends the melee build anyway.

**AoE**: no SV-specific AoE; traps (Explosive/Frost) in combat, Multi-Shot at range.

**Opener**: Hunter's Mark -> pet -> ranged shots -> close to melee.

**Upkeep**: Hunter's Mark (required for Expose Prey procs); Serpent Sting;
Immolation Trap (TBC); Aspect of the Beast in melee; tracking active with
Improved Tracking (MOB build).

**Defensives**: Deterrence (5 min cd, MOB); Feign Death; Disengage;
Survival Tactics (+hit on traps and Feign Death); Survivalist's Discipline
(-20% trap and Deterrence cd).

**Forever-specific changes**
- Survival is now a **melee spec**; Classic-style melee weaving removed
  (IV: you specialise into ranged or melee).
- **Strider Kick** (level 30 talent per IV): 100% weapon damage melee kick.
- **Expose Prey**: attacks on a Hunter's Marked target have a chance to make
  Mongoose Bite usable for 5 s (no dodge needed).
- **Lacerating Strikes**: Mongoose Bite applies a 21 s bleed (40% of the hit).
- **Predator's Edge** (melee crit damage + off-hand damage), **Savage Strikes**,
  **Resourcefulness** (cheaper traps/melee, crit-proc mana regen).
- **Aspect of the Beast** now baseline melee AP aspect.
- Mongoose Bite trained at 16 (MOB).

**Gaps**: no defensive/kiting guidance specific to melee SV; no confirmed
cooldown for Strider Kick; WGG names (Runner's Strike, Expose Weakness, Rending
Strikes) appear to be an older build of the same talents.

---

## Mage - Arcane

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/arcane-mage-ranged-dps-pve-guide | spec guide | updated 2026-09-24, level 30 | OK (browser) |
| IV | https://www.icy-veins.com/wow-forever/mage-class-overview | class changes overview | updated 2026-09-28 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/arcane-mage-guide | spec guide | 2026-09-24, level 25-30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/guides/mage-class-overview | class changes overview | 2026-09-18 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/arcane-mage/ | priority list | "Level 30 (Beta)" | OK |
| MGG | https://www.method.gg/wow-forever/wow-forever-mage-leveling-guide-and-talents | leveling guide (Frost) | 2026-09-29 | OK |
| WT | https://www.warcrafttavern.com/forever/guides/mage/ | class overview | level 20/30 beta | OK |
| WGG | https://wow.gg/guides/mage-arcane-forever-overview | spec overview | 2026-09-19 | OK |

**Rotation (single target)**

IV (level 30, mana-efficiency framing):
1. Solo: pull with Frostbolt (snare).
2. Arcane Blast (first cast in a group).
3. After 2-3 Arcane Blasts, spend the stacks with Fire Blast.
4. Repeat; wand low-health targets.
5. Arcane Missiles whenever Missile Barrage procs (overrides the above).

MOB (25+): spam Arcane Blast until Missile Barrage, then Arcane Missiles; repeat.
Presence of Mind (30) for an instant Arcane Blast finish. Improved Channeling
lets you stand and cast through melee. Optional rank 1 Frostbolt opener.

TBC (projected): 1. Mage Armor or Molten Armor. 2. Arcane Power with on-use
items. 3. Arcane Missiles on Missile Barrage. 4. Frostbolt at 4 Arcane Blast
stacks (keep blasting instead on short fights with spare mana). 5. Arcane
Blast. 6. Fire Blast / Arcane Explosion while moving.

WGG: build to 4 stacks (fewer if the fight ends or you must move), finish with
Arcane Missiles or an off-school spell, take free Missile Barrage casts when
mana is tight, never let the 8 s stack buff fall off unspent.

Disagreement: stack-dump spell and stack count differ - Fire Blast after 2-3
(IV), Frostbolt at 4 (TBC), Arcane Missiles or any spell at up to 4 (WGG), or
just keep blasting (MOB).

**AoE**: Arcane Explosion when 3+ (IV); tanked mobs: spam Arcane Explosion.
Solo AoE: gather -> Frost Nova -> Flamestrike -> Cone of Cold -> kite with
Arcane Explosion. Arcane Blast stacks buff the next AoE spell (Blizzard /
Arcane Explosion).

**Opener**: Frostbolt (solo) or Arcane Blast; Arcane Power + on-use (TBC).

**Upkeep**: Arcane Intellect; Mage Armor (regen) or Frost Armor (melee
threat); mana gems conjured in downtime; Evocation (IV frost guide: 8 min cd,
use regularly in dungeons). Do not keep Mana Shield up by default (IV).

**Defensives**: Mana Shield only when needed; Frost Nova + Blink; Fire/Frost
Ward vs casters; Improved Channeling (pushback protection); Polymorph; Counterspell.

**Forever-specific changes**
- **Arcane Blast** (talent, level 20 per IV): each cast adds a stack (max 4,
  8 s, removed by casting another damage spell) that buffs other spells by 10%
  and raises Arcane Blast's cost by 175%.
- **Missile Barrage** (talent, level 25): 40% chance from Arcane Blast, 20%
  from Fireball/Frostbolt/Frostfire Bolt, to make the next Arcane Missiles free,
  half duration, missile every 0.5 s.
- Arcane Meditation 50% in-cast regen; Arcane Mind adds 100% crit damage to
  Arcane; Arcane Impact = +crit to all Arcane; Arcane Focus = +5% hit; Arcane
  Geometry +6 yd range; Arcane Shielding (Mana Shield efficiency, Mage Armor resist).
- Spec is non-functional before 25 (MOB: level as Frost and respec).

**Gaps**: no source gives a tested mana-threshold rule for when to stop
blasting; Evocation/gem timing only in general terms; Arcane Power at 30 not
covered by IV/MOB.

---

## Mage - Fire

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/fire-mage-ranged-dps-pve-guide | spec guide | updated 2026-09-24, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/fire-mage-guide | spec guide | 2026-09-24, level 30 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/fire-mage/ | priority list | "Level 30 (Beta)" | OK |
| WGG | https://wow.gg/guides/mage-fire-forever-overview | spec overview | 2026-09-19 (older talent names) | OK |
| (shared) | IV / MOB mage class overviews, MGG, WT (see Arcane table) | | | OK |

**Rotation (single target)**

IV (level 30):
1. Open with Pyroblast (Fireball before 20).
2. Fireball as filler.
3. Fire Blast to finish non-trivial mobs and to spend the Wake of Fire buff.
4. Wand to finish at low level.

MOB (level 30, Improved Scorch + Hot Streak): open Fireball, then spam Scorch
(fast crits, builds the 5-stack debuff), Pyroblast once Hot Streak is at 3
stacks. Early levels: Frostbolt (rank 1) opener to chill, then Fireball.

TBC (projected 60): 1. Molten Armor. 2. Keep 5 Improved Scorch stacks.
3. Pyroblast at 3 stacks of "Heating Up" (TBC's name for the Hot Streak stack).
4. Frostfire Bolt. 5. Fire Blast while moving.

WGG (older naming "Firestarter"): build stacks via Fireball/Scorch/Fire Blast
crits, Pyroblast when the cast window allows, Scorch stacks on long targets,
Fire Blast while moving.

Disagreement: IV ignores Scorch at 30 (Scorch only at 22, Improved Scorch is
"60 talent"); MOB makes Scorch the filler. All agree Pyroblast is the Hot
Streak spender. MOB wrongly calls the Hot Streak effect a cooldown reduction;
IV overview: it cuts Pyroblast cast time 25% per stack (to 4.5/3/1.5 s).

**AoE**: tanked mobs: Flamestrike > Blast Wave > Arcane Explosion (IV). Solo:
gather -> Frost Nova -> Flamestrike -> Cone of Cold -> kite with Arcane
Explosion -> Blast Wave for extra slow. Blizzard also usable (MOB).

**Opener**: Pyroblast (IV); Frostbolt or Fireball (MOB, solo leveling).

**Upkeep**: Arcane Intellect; Frost Armor (melee) or Mage Armor; Improved
Scorch debuff (personal, 5 stacks, 30 s per WGG); Hot Streak stacks; Molten
Armor (TBC only - not confirmed by IV/MOB at 30).

**Defensives**: Mana Shield, Fire/Frost Ward, Frost Nova, Blink, Ice Armor
(30, MGG), Counterspell, Polymorph. Burning Soul / Flame Throwing reduce
pushback and add range (IV).

**Forever-specific changes**
- **Hot Streak** (1-pt talent, available by 30): non-periodic crits from
  Fireball, Frostfire Bolt, Fire Blast, Scorch give a stack (15 s, max 3); each
  stack -25% Pyroblast cast time; consumed by Pyroblast.
- **Wake of Fire** (first-row talent, from 10): Fire Blast cd -2 s; killing a
  non-trivial mob gives the next Fire Blast +50% crit (IV) / +25% (MOB) - feeds
  Hot Streak.
- **Frostfire Bolt** (baseline, **level 40** per IV Fire guide): damage + slow +
  short DoT, uses whichever school the target resists less; benefits from
  Fire and Frost talents; expected to replace Fireball.
- **Incineration**: +crit for Fire Blast, Ice Lance, Arcane Blast, Scorch.
- DoTs crit, so Ignite matters more.

**Gaps**: Wake of Fire crit value disagrees (50% vs 25%); no tested
Fireball-vs-Scorch filler data; Combustion at 60 only from WGG (older build).

---

## Mage - Frost

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-guide | spec guide (ST + AoE) | updated 2026-10-01, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/frost-mage-guide | spec guide, ST + AoE-farm variants | 2026-09-24, level 30 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/frost-mage/ | priority list | "Level 30 (Beta)" | OK |
| MGG | https://www.method.gg/wow-forever/wow-forever-mage-leveling-guide-and-talents | leveling guide (Frost recommended) | 2026-09-29 | OK |
| WGG | https://wow.gg/guides/mage-frost-forever-overview | spec overview | 2026-09-19 | OK |
| (shared) | IV / MOB mage class overviews, WT | | | OK |

**Rotation (single target)**

IV (level 30), re-evaluated every cast:
1. Frostbolt as the constant cast.
2. Fingers of Frost proc (gained on cast, so you see it immediately): cancel the
   current cast and Ice Lance.
3. Frostbite freeze from a Frostbolt hit: do NOT cancel; queue Ice Lance right
   after the Frostbolt in flight finishes (Ice Lance snapshots frozen state
   when not in melee).
4. Keep Ice Lancing while the target stays frozen.
5. Frost Nova for extra Shatter damage and space; Fire Blast as finisher on a
   non-frozen low target.

MOB: spam Frostbolt; Ice Lance on Frostbite freezes; Frost Nova at melee range
then Ice Lance; Fire Blast or moving Ice Lance to finish.

TBC (projected): 1. Molten Armor. 2. Ice Lance on Fingers of Frost.
3. Arcane Missiles on Missile Barrage (Frostbolt can proc it). 4. Frostbolt.
5. Ice Lance while moving.

WGG/MGG: Frostbolt -> freeze (Frostbite / Frost Nova / FoF) -> Ice Lance,
Shatter for crit; Counterspell (24).

One quote: IV says to start the next Frostbolt "before you know if the enemy will be frozen" (Icy Veins).

**AoE** (IV):
- 3+ targets: Cone of Cold (fishes FoF/Frostbite) -> Ice Lance un-frozen
  targets with FoF -> Ice Lance frozen targets -> Frost Nova for more freezes.
- 5+ targets: Cone of Cold on cd, Blizzard between, Arcane Explosion if you
  have aggro and cannot channel.
MOB AoE-farm build (Improved Blizzard, Permafrost, Ice Block, Arctic Reach):
gather with wand/Ice Lance -> Frost Nova -> Blink away -> Blizzard on the
front edge of the pack -> recast at the front -> Ice Block when gathered, then
Frost Nova + Blink -> finish with Frost Nova / Cone of Cold / Arcane Explosion
/ Flamestrike. Avoid caster packs.

**Opener**: Frostbolt from range (all sources); keep a rank 1 Frostbolt bound
for cheap slows/finishes (IV).

**Upkeep**: Arcane Intellect; Frost Armor / Ice Armor (melee, chill can proc
Frostbite) or Mage Armor (regen); Evocation (8 min cd, use in dungeons);
conjured water/food/gems in downtime.

**Defensives**: Ice Block, Ice Barrier (absorb + pushback protection), Cold
Snap (WGG), Frost Nova + Blink (Blink breaks stuns/roots), Mana Shield (pre-pull
for AoE), Fire/Frost Ward, Polymorph (one target per mage), Counterspell.
Ice Block is reachable by 30 in MOB builds.

**Forever-specific changes**
- **Ice Lance** (talent, reachable at level 20 per MGG): instant, no cd, +300%
  damage to frozen targets (or with FoF).
- **Fingers of Frost** (talent at 21 points, i.e. level 30): chill effects have
  a chance to make the next spell(s) treat the target as frozen; works on
  freeze-immune targets (bosses), feeds Shatter. Conflict: IV overview = 30%
  chance, 2 spells, 15 s; MOB = 15/30% by rank, 1 spell; WGG = rank 1 one cast;
  IV spec guide = consumed by any spell cast.
- **Frostbite**: chance to freeze from chill (Frostbolt hit); Ice Lance window.
- **Shatter**: +50% crit vs frozen at 3 points, no longer needs Improved Frost Nova.
- **Winter's Chill**: now only buffs Frostbolt and Ice Lance.
- **Improved Blizzard** slow reduced (45-40%, 1.5 s); overall Frost slows nerfed.
- **Elemental Precision**: +5% hit (Fire/Frost), 5 ranks.
- **Frostfire Bolt** baseline at 40 (see Fire).

**Gaps**: Fingers of Frost charge count and chance conflict; nothing tested at
60 on bosses where freezes break immediately (IV warns freeze is unreliable
in groups).

---

## Warlock - Affliction

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-guide | spec guide | updated 2026-10-02, level 30 | OK (browser) |
| IV | https://www.icy-veins.com/wow-forever/warlock-class-overview | class changes overview | updated 2026-10-02 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/affliction-warlock-guide | spec guide | 2026-10-06, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/guides/warlock-class-overview | class changes overview | 2026-09-18 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/affliction-warlock/ | priority list | "Level 30 (Beta)" | OK |
| MGG | https://www.method.gg/wow-forever/wow-forever-warlock-leveling-guide-and-talents | leveling guide (all specs) | 2026-09-30 | OK |
| WT | https://www.warcrafttavern.com/forever/guides/warlock/ | class overview | level 20/30 beta | OK |
| WGG | https://wow.gg/guides/warlock-affliction-forever-overview | spec overview | 2026-09-19 (older names) | OK |

**Rotation (single target)**

IV (level 30):
1. Demon in first.
2. Curse of the Elements or Curse of Recklessness on bosses/elites (group-dependent).
3. Pre-cast Immolate if not tag-racing (otherwise after Corruption).
4. Bane of Agony if the target lives long enough (ramps up; lowest threat).
5. Siphon Life if the target lives 20+ s.
6. Corruption (instant with 5/5 Improved Corruption).
7. Drain Life when you need health.
8. Shadow Bolt only on Nightfall (Shadow Trance) procs.
9. Wand when DoTs will finish it; Drain Soul to finish when shards needed.
10. Life Tap when health allows. Do not clip DoTs.

MOB (level 30): demon in (Succubus from 20, Voidwalker for safety); curse;
Amplify Curse + Bane of Agony together (macro, every 3 min) on long targets;
Bane of Agony; Corruption and Immolate on elites/high-HP; Shadow Bolt or wand
filler; Nightfall procs; Drain Life for health; Drain Soul for shards.

TBC (projected 60): 1. Spellstone. 2. Demonic Sacrifice the Imp. 3. Assigned
curse (default Curse of Shadow). 4. Amplify Curse + Bane of Agony + on-use.
5. Shadow Bolt on Nightfall. 6. Bane of Agony up. 7. Corruption up. 8. Siphon
Life up. 9. Wrack as filler. 10. Life Tap (ideally while moving).

MGG: Immolate -> Corruption -> Bane of Agony -> wand or Drain Life to finish.

WGG (older names): prime with DoTs, then channel drains (empowered per effect
on target), Nightfall Shadow Bolts while moving.

Disagreements: Siphon Life at 30 - IV spec guide and MGG say yes (level 30);
IV class overview says not available to a normal level 30. Immolate order
varies (first in IV/MGG, after Corruption in MOB). Filler at 60: Wrack (TBC) vs
drains (WGG).

**AoE**: spread Corruption + Bane of Agony; Rain of Fire when mobs die fast;
Hellfire at 30 (self-damage, huge threat) (IV).

**Opener**: pet in -> curse -> Immolate pre-cast -> Bane of Agony -> Corruption.

**Upkeep**: Demon Skin -> Demon Armor (20); curse (CoE / CoR; Curse of
Tongues from 26 vs casters); Bane of Agony; Corruption; Immolate; Siphon Life;
soul shards (Drain Soul from 10); Healthstone; pet health (Health Funnel).
Pet: Succubus = most damage, Voidwalker = tank, Felhunter (30) = interrupt and
dispel, Imp = least (runs out of mana). Pets unlocked by class quests at 2/10/20/30.

**Defensives**: Healthstone, Soulstone (pre-applied; MOB: on healer in groups),
Fear (+ fear juggling with curses, MOB), Howl of Terror, Death Coil (WT, WGG),
Voidwalker Sacrifice (MGG), Drain Life, Shadow Ward, Banish (28).

**Forever-specific changes**
- **Curse of Agony -> Bane of Agony; Curse of Doom -> Bane of Doom**: banes are
  not curses, so Bane of Agony + Curse of the Elements/Recklessness coexist on
  one target (IV, MOB, WGG).
- **DoTs can crit**; **Pandemic** = +100% DoT/drain crit damage (not duration).
- **Nightfall** (level 25-26 per MOB): Corruption, Drain Life, Drain Soul can
  proc Shadow Trance (instant Shadow Bolt).
- Improved Corruption also +10% Corruption damage; Malediction, Malevolence,
  Improved Bane of Agony, Suppression (hit + threat), Amplify Curse buffs Bane.
- **Wrack** (deep talent): 6 s shadow DoT that buffs your other shadow DoTs 10%.
- Improved Drains / Soul Siphon / Soul Harvesting (drain-centric playstyle).
- Life Tap now scales with Spirit.
- Felhunter at 30; demons have a Move To command (100 yd).
- Spellstone reworked into a weapon oil (trained 36); Firestone oil (28).

**Gaps**: no tested 60 priority; Wrack vs drain filler unresolved; Death Coil
level not stated by any spec guide.

---

## Warlock - Demonology

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-guide | spec guide | updated 2026-10-02, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/demonology-warlock-guide | spec guide | 2026-10-06, level 30 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/demonology-warlock/ | priority list | "Level 30 (Beta)" | OK |
| WGG | https://wow.gg/guides/warlock-demonology-forever-overview | spec overview | 2026-09-19 (older names) | OK |
| (shared) | IV / MOB warlock overviews, MGG, WT | | | OK |

**Rotation (single target)**

IV (level 30):
1. Demon out and Soul Link active (pre-pull).
2. Demon in first.
3. Curse (CoE / CoR) on bosses/elites.
4. Immolate pre-cast if not tag-racing.
5. Bane of Agony if the target lives.
6. Corruption (even hard-cast without Improved Corruption).
7. Drain Life / Healthstone for health (Drain Life also heals pet via Demonic Energies).
8. Wand when DoTs/pet will finish; Drain Soul for shards.
9. Life Tap (pet gets equal mana via Demonic Energies).

MOB (level 30, Demonic Brand build): Soul Link + Demon Armor pre-pull; curse;
**Searing Pain on the main target every 10 s to keep Demonic Brand up**, with
the Succubus attacking that target; Bane of Agony; Corruption; Immolate;
Shadow Bolt or wand filler; Drain Life; Drain Soul.

TBC (projected 60): 1. Spellstone. 2. Demonic Sacrifice the Imp. 3. Summon
Succubus. 4. Soul Link. 5. Curse (default Curse of Shadow). 6. Bane of Doom if
the target lives 1+ min. 7. Soul Fire under 35% with Decimation active.
8. Shadow Bolt. 9. Life Tap (while moving).

MGG: Immolate + Bane of Agony, Shadow Bolt and wand; Searing Pain when
available; Soul Fire finishes once Decimation is talented.

Disagreement: Demonic Brand upkeep (MOB) is not in IV's list although IV's
build takes the talent.

**AoE**: spread Corruption + Bane of Agony; Rain of Fire; Hellfire at 30
(threat, self-damage).

**Opener**: Soul Link + pet -> curse -> Immolate -> Bane of Agony -> Corruption
(IV); Searing Pain for Brand first (MOB).

**Upkeep**: Soul Link (drops if pet dies); Demonic Brand (10 s); Demon Armor;
curse; Bane of Agony / Corruption / Immolate; pet alive (Health Funnel,
Demonic Energies heal); Demonic Sacrifice + Demonic Pact buff at 60.
Pet: Succubus/Incubus main (Improved Sayaad); Voidwalker tank.

**Defensives**: Soul Link (30% damage to pet), Fel Domination + Master
Summoner (fast resummon), Healthstone, Soulstone, Fear, Death Coil, Voidwalker
Sacrifice, Demonic Aegis.

**Forever-specific changes**
- **Soul Link** reachable at 30 (21 Demo points).
- **Demonic Energies**: your spell damage heals the pet (15% at 2 pts); Life
  Tap mana also goes to the pet.
- **Demonic Brand**: Searing Pain makes less threat and brands the target; pet
  attacks on it deal extra damage/threat.
- **Demonic Sacrifice** reworked: Imp = +15% Shadow, Succubus = +15% Fire
  (IV); WGG says duration now 2 h. **Demonic Pact**: the sacrifice buff stays
  when you summon a different demon.
- **Decimation**: big Soul Fire cd reduction; Shadow Bolt/Searing Pain on a
  target under 35% gives a fast, shard-free Soul Fire.
- **Demonic Knowledge**: spell damage scaled from your level while a demon is out.
- Incubus is a separate summon from Succubus (same kit).
- Pets scale with warlock stats.

**Gaps**: no tested Soul Fire/Decimation execute rotation; Sacrifice-vs-Soul
Link choice at 60 unresolved.

---

## Warlock - Destruction

**Sources**

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| IV | https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-guide | spec guide | updated 2026-10-02, level 30 | OK (browser) |
| MOB | https://mobalytics.gg/wow-forever/classes/destruction-warlock-guide | spec guide | 2026-10-06, level 30 | OK (browser) |
| TBC | https://wowtbc.gg/warcraftforever/class-guides/destruction-warlock/ | priority list | "Level 30 (Beta)" | OK |
| WGG | https://wow.gg/guides/warlock-destruction-forever-overview | spec overview | 2026-09-19 (older names) | OK |
| (shared) | IV / MOB warlock overviews, MGG, WT | | | OK |

**Rotation (single target)**

IV (level 30):
1. Demon in first.
2. Curse (CoE / CoR) on bosses/elites.
3. Pre-cast Shadow Bolt, then Immolate so both land together.
4. Immolate (only DoT to manage).
5. Shadow Bolt (or wand) filler.
6. Searing Pain when a faster cast is needed (high threat).
7. Conflagrate near the end of Immolate or when the target must die now
   (it still consumes Immolate at 30).
8. Shadowburn on a dying target (shard refunded if it dies within 8 s); on
   cooldown if shards are capped.
9. Drain Soul instead of Shadowburn when shards are needed.
10. Stop casting when pet + DoT will finish; Life Tap when health allows.

MOB: Demon Armor, Healthstone, Soulstone on healer; curse; Bane of Agony on
long targets; Immolate; Corruption only with 5/5 Improved Corruption; Drain
Life for health; wand filler; Drain Soul for shards.

TBC (projected 60): 1. Firestone. 2. Demonic Sacrifice the Succubus.
3. Curse (default CoE). 4. Keep Shadow and Flame buff up via Shadowburn.
5. Searing Pain under 35% to trigger Decimation. 6. Soul Fire under 35% with
Decimation. 7. Immolate up. 8. Bane of Doom if target lives 1+ min.
9. Conflagrate. 10. Incinerate. 11. Life Tap.

MGG: Immolate, Shadow Bolt/wand; Shadowburn from 24 before death; Conflagrate
from 29.

WGG: keep Immolate up; Conflagrate while Immolate persists (Shadow and Flame
rank 5) or before it expires at lower ranks; Shadowburn on dying targets or
while moving; Imp is the standard pet.

Disagreements: Conflagrate level 25 (IV) vs 29 (MGG); MOB rotation omits
Shadow Bolt and Conflagrate; pet choice Succubus (IV/MOB) vs Imp (WGG) vs
"sim pending" (TBC).

**AoE**: **Bane of Havoc** on a second tough target (15% of damage dealt to
others is copied to it; one target per warlock; cannot coexist with Bane of
Agony on the same target); put Havoc on a high-HP mob every pack; Rain of
Fire; Hellfire at 30 (Havoc also copies Hellfire damage).

**Opener**: Shadow Bolt pre-cast -> Immolate (IV).

**Upkeep**: Immolate; curse; Bane of Havoc on second target; Demon Armor;
Firestone weapon oil (28); soul shards for Shadowburn.

**Defensives**: Molten Skin talent (up to -10% damage taken), Healthstone,
Soulstone, Fear, Death Coil, Voidwalker, Shadow Ward.

**Forever-specific changes**
- **Bane of Havoc** (talent, level 28-30): 5 min bane, 15% damage transfer.
- **Conflagrate** (talent, 25-29) still consumes Immolate at 30; **Shadow and
  Flame** (deeper) gives a chance to keep Immolate and to refund Shadowburn's
  shard, and makes Conflagrate buff Shadow / Shadowburn buff Fire damage.
- **Incinerate**: new 31-pt capstone, +25% vs Immolated targets.
- **Bane** talent also cuts Incinerate cast; **Ruin** +100% crit damage;
  **Agonizing Flames** (+10% Destruction damage, Searing Pain crit);
  **Fire and Brimstone** (Conflagrate crit); **Cataclysm** (mana);
  **Destructive Reach** (+20% range); Aftermath dazes on Conflagrate.
- Improved Shadow Bolt now a personal vulnerability (WGG).

**Gaps**: no tested Incinerate/Conflagrate/Shadow and Flame priority at 60;
Soul Fire use for Destruction only from TBC.

---

## Sources not usable

| source | reason |
|---|---|
| icy-veins.com, mobalytics.gg via WebFetch | HTTP 403; content read through the built-in browser instead |
| wowhead.com/forever guides | no Forever class guides found by search; wowhead hosts a Forever spell DB (wow.gg links wowhead.com/forever/spell=75) which may help ID lookups, not a guide |
| mythicsim.com/wow-forever | no Forever hunter/mage/warlock pages found by search |
| warcraft.wiki.gg, world-of-warcraft-forever.wiki | only retail/Wrath pages (e.g. Fingers of Frost) surfaced; no Forever-specific spell pages found |
| reddit | no relevant Forever rotation threads surfaced in search |
| eu.forums.blizzard.com/.../what-happened-to-auto-shot-for-hunters/612553 | not about Forever (retail action bar issue) |
| us.forums.blizzard.com/en/wow/t/2359185 | usable only as a fact (Auto Shot 0.5 s cast bug, 2026-09-23); not a guide |
| zockify.com/forever/hunter (and mage/warlock) | placeholder: "builds coming soon", change list only (confirms dead zone kept, Aimed Shot baseline, in-combat traps) |
| kami-labs.fr MM build | pre-beta (2026-09-14) talent summary, no rotation; Sniper Shot text likely outdated |
| wow.gg *-forever-overview pages | used, but dated 2026-09-19 and use talent names that differ from current beta guides (Runner's Strike, Expose Weakness, Rending Strikes, Firestarter, Drain Hope, Devastation, Fel Energies) - treat as an older build; the fetch model may also have misread |
| wowtbc.gg rotations | used, but labelled "Level 30 (Beta)" while listing spells not available at 30 (Molten Armor, Incinerate, Bane of Doom, Wrack, Spellstone, Bestial Wrath) - projected 60 lists, not tested |
