# Warrior and Rogue - WoW Forever guide references

Researched 2026-10-07. Covers WoW Forever (camelot) beta only, level cap 30. All priorities below are paraphrased; source wording is not reproduced.

Ground rules for reading this file:
- **Official > guide.** The Blizzard class deep dive (Warrior only) and the beta development notes (Sep 24 + Oct 1) override any guide written earlier. Several guides (Sep 14-22) predate those patches and are stale on specific numbers. Each stale point is flagged.
- Every guide is a level 1-30 beta guide. No source has a real level 60 rotation; "Level 60" tabs on mobalytics are placeholder pages that say the content is still to come.
- wow.gg (Fouren) pages look machine-translated and mislabel spells: "Bloodthirst" where they mean **Bloodthrill**, "Piercing Howl" where they mean **Spearing Strike**, "Envenom" where they mean **Venom**, "Defensive Mastery" where they mean **Master of Defense**. Their numbers come from the pre-patch beta.

---

## Warrior - class-wide sources (used by all three trees)

| ID | site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|---|
| W-BLZ | Blizzard (official deep dive) | https://worldofwarcraft.com/en-us/news/24301514 (forum mirror us.forums.blizzard.com/en/wow/t/2367485) | class changes, all trees | ~Sep 30 2026 | OK (browser) |
| W-DEV | Blizzard beta dev notes | https://us.forums.blizzard.com/en/wow/t/2360696 | patch notes Sep 24 + Oct 1 | Sep 24, Oct 1 2026 | OK (browser) |
| W-IVO | Icy Veins class overview | https://www.icy-veins.com/wow-forever/warrior-class-overview | spell/talent changes | updated Sep 27 (changelog Oct 2) | OK (browser; WebFetch 403) |
| W-MOO | Mobalytics class overview | https://mobalytics.gg/wow-forever/guides/warrior-class-overview | talent changes | Sep 18 (pre-Oct 1, partly stale) | OK (browser) |
| W-KLC | kami-labs changed spells | https://kami-labs.fr/en/wow-forever/guerrier-wow-forever-sorts-et-talents-modifies/ | spell/talent changes | Sep 30 | OK |
| W-MTH | Method leveling | https://www.method.gg/wow-forever/wow-forever-warrior-leveling-guide-and-talents | leveling (Arms 2H + Prot builds) | Oct 4 | OK |
| W-WT | Warcraft Tavern class guide | https://www.warcrafttavern.com/forever/guides/warrior/ | overview, brief per-spec notes | Sep 2026 | OK (thin) |
| W-PUG | powerupgaming talent changes | https://powerupgaming.co.uk/2026/09/14/new-wow-forever-talents-changes-vs-classic-guide/ | talent change list | Sep 14 (pre-beta) | OK (thin) |
| W-FB | Blizzard forum "DPS Warrior Feedback" | https://us.forums.blizzard.com/en/wow/t/dps-warrior-feedback/2356172 | player feedback | Sep 20 | OK (context only) |

### Warrior baseline changes that affect every tree (official unless noted)
- **Rage from dealing damage is normalized** to weapon speed (not damage dealt). Crit bonus: launch beta had none; deep dive re-added +75%; **Oct 1 raised it to +100%**. Rage from damage taken ignores armor and absorbs. [W-BLZ, W-DEV]
- **Tactical Mastery baseline at 14**, keeps 10 rage on stance change. Arms talent Improved Tactical Mastery raises it (+3/point, up to 25 total). [W-BLZ; W-IVO/W-KLC say "+15 on top of 10", same result]
- **Victory Rush baseline at 20**: instant, no rage cost, damage scales with AP, heals 10% max HP, usable for 20 s after killing a non-trivial enemy, 30 s cooldown. [W-BLZ; Icy Arms/Fury agree on 20; Icy Prot says 30 in one paragraph - treat as an error]
- **Cooldowns unlinked**: Recklessness, Retaliation and Shield Wall no longer share a cooldown. Retaliation and Shield Wall drop to 15 min. **Recklessness keeps its 30 min cooldown** (the deep dive lists no reduction, and the forum feedback complains about it). zockify says all three are 15 min, which disagrees with the official text.
- **Thunder Clap**: usable in Defensive Stance, scales with AP, 6 s cooldown, hits up to 4 targets, slows attack speed by 20%. [W-BLZ, W-IVO, W-KLC]
- **Rend** now scales heavily with AP. Rend and Sunder Armor instantly tag the mob (Oct 1). [W-BLZ, W-DEV]
- **Sunder Armor** can be applied even when a stronger Expose Armor is up. Its threat now scales with AP, with a threat fix on Sep 24. [W-BLZ, W-DEV]
- **Bloodrage** no longer puts you in combat, so you can use it before Charge or while eating. [W-IVO]
- **Battle Shout** gives less AP, but Improved Battle Shout is now baseline. Improved Demoralizing Shout is baseline too. [W-BLZ]
- Queueing Heroic Strike no longer raises off-hand hit (Oct 1). [W-DEV]
- **Whirlwind hits with both weapons baseline** (Oct 1; it used to need Raging Blows). Learned at 36 [W-MTH], so it is out of reach at the beta cap.
- Berserker Stance comes from a level 30 class quest. Berserker Rage is now level 30 (was 32, Oct 1). [W-IVO guides, W-DEV]
- Known bug [mobalytics warrior leveling, Sep 29]: Demoralizing Shout generates no threat, so tanks should not open a pull with it.
- Hit and crit are now universal stats. Weapon skill still exists, but items give less of it. [W-IVO]

---

## Warrior - Arms

**Sources** (plus W-BLZ, W-DEV, W-IVO, W-MOO, W-KLC, W-MTH, W-WT, W-PUG, W-FB above)

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/arms-warrior/ | rotation (priority list) | "Level 30 (Beta)", undated | OK |
| Icy Veins (Abide) | https://www.icy-veins.com/wow-forever/arms-warrior-melee-dps-pve-guide | rotation + leveling, lvl 30 | Sep 27 | OK (browser) |
| Mobalytics | https://mobalytics.gg/wow-forever/classes/arms-warrior-guide | leveling, 1-30 + lvl 60 talents | Sep 22 (lvl 60 gameplay empty) | OK (browser) |
| wow.gg (Fouren) | https://wow.gg/guides/warrior-arms-forever-overview | spec overview | Sep 18 (pre-patch numbers) | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-guerrier-armes-wow-forever/ | build | Sep 14 | OK (thin) |
| kami-labs PvP | https://kami-labs.fr/wow-forever/build-guerrier-armes-pvp-wow-forever/ | PvP build (French) | Sep 2026 | not fetched (PvP, out of scope) |

**Rotation (single target)** - consensus first, then the endgame-style list
1. Out of combat: Battle Shout up. Bloodrage between pulls (it no longer starts combat).
2. Open with Charge (Battle Stance).
3. Rend early, but only on a target that will live through most of the bleed. Never refresh it on a dying mob. With Bloodthrill talented, Rend also matters as the proc enabler (see below).
4. Overpower whenever it is lit: after the target dodges, or on a Bloodthrill proc (6 s window). Battle Stance only.
5. Mortal Strike on cooldown once you have it (tree capstone, not reachable at 30).
6. Slam: see the disagreement below. Arms has Slam from 30 [Icy]. In Forever it has an **18 s cooldown**, so it is a periodic button, not a filler you spam.
7. Spearing Strike: on cooldown against Giants, Dragonkin or mounted targets. Otherwise only as a rage dump near cap, or to finish a runner. [Icy, wowtbc, kami]
8. Sunder Armor: one or two early on while leveling. Stop once the target is under 50% HP [Icy]. wowtbc keeps 5 stacks (endgame framing).
9. Victory Rush whenever the Victorious buff is up.
10. Heroic Strike only with excess rage. Every guide warns that while leveling it is rage-inefficient, because a yellow swing generates no rage.

wowtbc's endgame-style list (Berserker Stance base, dancing to Battle for Rend, Overpower and Spearing Strike): Battle Shout > Recklessness with on-use effects (save for execute) > Bloodrage > Sunder to 5 / refresh > Execute under 20% > keep Rend up > Heroic Strike on excess rage > Spearing Strike on Dragonkin/Giants > Overpower on Bloodthrill or dodge > Mortal Strike > Whirlwind > Slam.

Disagreements:
- **Slam and the swing timer.** Official (deep dive): the redesigned 2-point **Improved Slam** (Arms row 6) cuts Slam's cooldown, GCD and cast time, *and* stops Slam delaying or interrupting the auto-attack. W-IVO, wow.gg and powerupgaming say the same. **Icy's Arms guide (Sep 27, level 30)** says Slam still resets the swing, so press it right after a white hit. That is true **without** Improved Slam, and Improved Slam is out of reach at level 30. kami-labs claims baseline Slam no longer interrupts melee; that does not match the official text. Net: before Improved Slam, weave Slam right after a swing. With Improved Slam, cast it freely.
- **Execute.** Icy (both DPS guides) says do not use it while leveling, because it dumps all your rage. wowtbc puts it high (under 20%). Mobalytics says use it only when you need a fast kill. All three agree it is an endgame button.
- **Stance.** Icy says sit in Battle Stance at 30. wowtbc assumes Berserker Stance with dancing to Battle. wow.gg treats stance swapping as part of the rotation (baseline Tactical Mastery makes it cheap).

**AoE / cleave**
- Sweeping Strikes (talent, level 30; Battle Stance, 30 rage, next 5 swings hit a second target). Use it when two mobs will stay together, not just because it is off cooldown, and never on a crowd-controlled mob. [Icy, wow.gg, mobalytics]
- Cleave to spend rage on 2 targets. In dungeons, wait for the tank to establish threat first [Icy]. Thunder Clap and Demoralizing Shout reduce damage taken in multi-mob fights. Whirlwind from 36. Spearing Strike is not AoE.

**Execute / opener**
- Opener: Battle Shout, then Bloodrage pre-pull, then Charge (macro with /startattack and Battle Stance), then Rend, then Demoralizing Shout on melee mobs [Icy].
- Execute: learned at 24 [mobalytics, Icy]. Spends all of your rage. Recklessness is saved for the execute phase [wowtbc].

**Defensives**
- Retaliation (20, 15 min, separate cooldown): counters melee from the front. For bad multi-mob pulls [Icy, W-MTH says it is the first major cooldown].
- Shield Wall (28, 60% damage reduction for 12 s, 15 min, needs a shield and Defensive Stance): carry a shield for emergencies [Icy].
- Intimidating Shout (22) to make space. Hamstring for runners. Shield Bash (shield equipped) is the only interrupt before Pummel.
- Victory Rush is the only self-heal (10%).

**Forever-specific changes affecting Arms**
- **Bloodthrill** (new row-5 talent, 5 ranks): main-hand melee attacks on a target with *your* Rend can light Overpower for 6 s. **Sep 24: 4/8/12/16/20% (was 2/4/6/8/10%), main hand only, and Heroic Strike and Cleave count.** wow.gg's "up to 10%" is pre-patch. Icy says auto-attacks at 20%. The proc checks your melee hits, not the bleed ticks [wow.gg], and a bleed crit does not count.
- **Spearing Strike** (new 16-point milestone talent): instant, 15 rage, 20 s cooldown, dismounts the target. Deals bonus damage to mounted targets, Dragons and Giants: doubled per Blizzard, "40% + 80% weapon damage" per W-MOO and W-IVO, "triple" per the Icy guide. **Oct 1: no longer needs a 2H weapon, now needs Battle Stance.**
- **Improved Slam** moved from Fury to Arms row 6 (2 points). **Slam cooldown is 18 s (Sep 24, was 15).** Improved Slam takes 1.5/3 s off it [W-DEV]. Slam cast is 1.5 s [W-IVO, kami].
- **Weaponmaster** (row 5) replaces the 4 weapon specializations: axes and polearms get crit, maces and staves get armor ignore, swords get extra-attack chance. Numbers vary by source (wow.gg 1%/3%/5% per point; W-KLC up to 5%/15%).
- Improved Overpower moved up to row 2 (+50% Overpower crit at 2 points). Anger Management is unchanged (+1 rage per 3 s in combat; tooltip clarified only). Bleeds can now crit [wow.gg].
- Tactical Mastery is baseline (see class-wide).

**Gaps**
- No level 60 rotation from any source: Mortal Strike/Slam/Overpower weaving, Heroic Strike thresholds, and Whirlwind usage under normalized rage are all unknown.
- No source ranks Spearing Strike against Overpower or Mortal Strike on a target type it counts as bonus (Giant/Dragonkin).
- No source covers Arms execute-phase specifics (Execute rage thresholds, MS during execute).
- No numbers on how much Bloodthrill uptime you can expect.

---

## Warrior - Fury

**Sources** (plus W-BLZ, W-DEV, W-IVO, W-MOO, W-KLC, W-WT, W-PUG, W-FB)

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/fury-warrior/ | rotation | "Level 30 (Beta)" | OK |
| Icy Veins (Abide) | https://www.icy-veins.com/wow-forever/fury-warrior-melee-dps-pve-guide | rotation + leveling, lvl 30 | Sep 27 (talents pre-Oct 1) | OK (browser) |
| Mobalytics | https://mobalytics.gg/wow-forever/classes/fury-warrior-guide | leveling 1-30 (2H Fury) | Oct 6 (talents redone Oct 5) | OK (browser) |
| wow.gg (Fouren) | https://wow.gg/guides/warrior-fury-forever-overview | spec overview | Sep 18 (stale: pre-Oct 1 rework) | OK |

**Rotation (single target)**
Leveling, level 1-30 (Icy and Mobalytics broadly agree):
1. Battle Shout. Bloodrage between pulls.
2. Charge.
3. Demoralizing Shout on non-caster mobs (Icy only; it saves health across pulls).
4. Victory Rush when lit.
5. Rend early on mobs that will live through it.
6. Overpower after a dodge.
7. Sunder Armor once or twice. Skip it under 50% HP.
8. Execute: Icy says skip it while leveling. Mobalytics says use it only for a fast kill.
9. Heroic Strike or Cleave only with excess rage.
10. Death Wish (talent, level 30) as often as possible, ideally with rage pooled so you can chain Cleaves on multi-mob pulls [Icy].

wowtbc's endgame list: Berserker Stance > Battle Shout > Recklessness + Death Wish + on-use effects (save for execute) > Bloodrage > Sunder to 5 > Execute under 20% > Heroic Strike *and Hamstring* to spend excess rage > Bloodthirst > Whirlwind. Hamstring as a rage dump is wowtbc only.

Disagreement: wowtbc puts Execute above Bloodthirst (endgame framing). Icy says never use it while leveling. Mobalytics plays 2H Fury to 30 while Icy builds toward dual-wield. Since Oct 1, Unbridled Wrath no longer gives double rage on a 2H, which weakens the 2H Fury case.

**AoE / cleave**
- Cleave is the main rage spender on 2 targets. Raging Blows (talent) cuts Cleave and Whirlwind cost by 3 [W-DEV]. Whirlwind hits with both weapons baseline from 36. Never cleave onto a crowd-controlled mob. Thunder Clap and Demoralizing Shout for damage reduction. Piercing Howl (talent) as an AoE slow for utility [Icy, wow.gg].

**Execute / opener**
- Opener: as for Arms (Battle Shout, Bloodrage, Charge, then debuffs). Execute learned at 24. Cooldowns (Recklessness, Death Wish) are saved for execute [wowtbc]. Recklessness is a 30 min cooldown (see class-wide), so in practice it is a once-per-session button.

**Defensives**
- Same baseline tools as Arms (Retaliation 15 min, Shield Wall needs a shield, Intimidating Shout, Victory Rush). Death Wish makes you take +5% damage, so avoid it during dangerous incoming-damage windows [wow.gg]. Berserker Rage (30) breaks fear.

**Forever-specific changes affecting Fury** (Oct 1 rework supersedes earlier guides)
- **Oct 1:** Improved Cleave and Boundless Rage are removed. New talents: Lingering Rage (row 2, delays out-of-combat rage decay by 2-10 s), Furious Precision (row 3, +4/7/10% off-hand hit), Gore Drinker (row 6, needs Enrage: Enrage, Berserker Rage, Bloodrage, Death Wish and Bloodthirst make your next 3 melee hits heal 0.5/1% max HP).
- **Oct 1:** Dual Wield Specialization lost its off-hand rage bonus (and a bug that gave hit to both hands). Unbridled Wrath no longer doubles rage on a 2H, and a too-low proc chance was fixed. Flurry now requires Death Wish instead of Enrage. Booming Voice: shouts get +10-50% radius and -5-25% rage cost. Improved Berserker Rage moved to row 5.
- **Bloodthirst**: no longer heals, gives +10% move speed for 10 s, base damage + AP ratio. **Oct 1: AP ratio back to 45% (was 35%).** Blood Craze no longer procs from Bloodthirst (Oct 1). wow.gg says it does, which is stale.
- **Enrage**: can now trigger from taking any damage (official). wow.gg says it triggers from dealing a damaging attack, which is likely a translation error.
- **Death Wish**: +20% physical damage, fear immunity, and +5% damage taken (instead of the old armor and resist penalty). 3 min cooldown, 30 s [Icy, wow.gg].
- Flurry's attack-speed bonus is 5% lower. Precision is a new hit talent. Booming Voice no longer changes shout duration (that is baseline now).
- Stale claims to ignore: W-MOO's "Boundless Rage" and "Raging Blows makes Whirlwind use the off-hand" (both changed on Oct 1). W-IVO's "Raging Blows" -3 cost is current. wow.gg's "Unbridled Wrath raises max rage" is a garble.

**Gaps**
- No source has a post-Oct-1 Fury priority. Every rotation list predates the rework or ignores it.
- Nobody covers Bloodthirst vs Whirlwind priority or Heroic Strike rage thresholds under normalized rage at 60.
- Nobody covers how Execute and Bloodthirst interact in the execute phase.
- Whether dual-wield or 2H is better after Oct 1: untested.

---

## Warrior - Protection

**Sources** (plus W-BLZ, W-DEV, W-IVO, W-MOO, W-KLC, W-MTH, W-WT)

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/protection-warrior/ | tank rotation | "Level 30 (Beta)" | OK |
| Icy Veins (Abide) | https://www.icy-veins.com/wow-forever/protection-warrior-tank-pve-guide | tank + leveling, lvl 30 | Sep 27 | OK (browser) |
| Mobalytics (KallTorak) | https://mobalytics.gg/wow-forever/classes/protection-warrior-guide-kalltorak | tank + leveling 1-30 (30-60 and endgame tabs WIP) | Oct 6 | OK (browser) |
| Mobalytics (Oli) | https://mobalytics.gg/wow-forever/classes/warrior-leveling-guide | Prot leveling 1-30 + dungeon tips | Sep 29 | OK (browser) |
| wow.gg (Fouren) | https://wow.gg/guides/warrior-protection-forever-overview | spec overview | Sep 18 | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-guerrier-protection-wow-forever/ | build | Sep 14 | OK (thin) |
| Method | (W-MTH) | Prot solo leveling build | Oct 4 | OK |

**Rotation (single-target threat)**
Leveling, 1-16 [KallTorak, Oli]: Charge then Rend, then mostly Heroic Strike (an auto-attack simulator). From 10, Defensive Stance: Charge from Battle, then swap to Defensive to use Revenge. From 14, Revenge.
From 16 (Shield Block) onward, consensus across Icy, KallTorak, Oli and wowtbc:
1. Battle Shout. Bloodrage between pulls (it no longer starts combat).
2. Charge. With Vanguard you can Charge from Defensive Stance and keep the rage you banked (still only out of combat).
3. **Shield Block on cooldown.** Press it right before hits land [Oli]. Two blocks with Shield Specialization refund its rage and give two Revenge procs [Icy]. KallTorak opens Charge > Shield Block for a guaranteed early Revenge, then one Sunder.
4. **Revenge whenever it is lit.** Icy calls it the hardest hitter at 5 rage.
5. Thunder Clap and Demoralizing Shout up. Icy and Oli say on hard mobs or multi-mob pulls only; wowtbc and KallTorak say keep both up.
6. Rend on targets that will live.
7. Sunder Armor: Icy and Oli say stop under 50% HP while leveling, but stack 5 on elites and bosses. wowtbc keeps 5 stacks.
8. Victory Rush when lit (Oli: skip it above 90% HP).
9. Shield Slam (when talented, deep tree) as burst threat [wowtbc, wow.gg].
10. Heroic Strike (or Cleave) only with excess rage. Oli: only below 50% HP, and Sunder first because of Improved Sunder.
11. Shield Bash for interrupts. Disarm a dangerous melee mob [KallTorak].

wowtbc order: Defensive Stance + Battle Shout > Bloodrage > 5 Sunders > Thunder Clap > Demoralizing Shout > Shield Block vs physical > Heroic Strike on excess > Shield Slam > Revenge > Sunder.

Disagreement: wow.gg says save Shield Block for heavy pulls and bank rage for it. Every other source says use it on cooldown, because with Shield Specialization it pays for itself.

Note: KallTorak says Overpower shares a cooldown with Revenge, so weaving to Battle Stance for Overpower is not worth it.

**AoE threat**
- Charge, then Thunder Clap. Shield Block and Revenge on the main target. Tab-Sunder the others. Thunder Clap and Shield Block on cooldown. Cleave with spare rage. Retaliation for threat on big pulls. Taunt or Mocking Blow when a mob slips [KallTorak].
- Icy: tab between mobs every few seconds and spend 1-2 abilities on each to spread threat. Improved Thunder Clap makes Thunder Clap spammable.
- Do not open with Demoralizing Shout until the threat bug is fixed [Oli].
- Challenging Shout (26) grants no threat of its own. Follow it up within its 6 s [Icy].

**Defensives / tanking cooldowns**
- **Shield Block**: rotational, not emergency (2 blocks within 7 s, 5 s cooldown, +75% block). [W-IVO, W-KLC]
- **Last Stand** (talent): emergency panic button. Now a **3 min** cooldown [KallTorak, wow.gg]. Gives 30% max HP for 20 s [kami]. Icy skips it at 30. KallTorak: do not die with it unused.
- **Shield Wall** (28): 60% damage reduction for 12 s, 15 min baseline. Improved Shield Wall (2 points) takes off up to 11 min, so about 4 min [W-IVO, W-KLC]. Use it on over-pulls or dangerous bosses.
- Retaliation (20, 15 min): big melee pulls. Disarm against hard-hitting melee. Concussion Blow (talent) as a utility stun. Intimidating Shout (22) when a pull breaks.
- Racials worth timing [KallTorak]: Elune's Light or Blood Fury or Berserking on the pull for threat; Stoneform against physical burst.

**Forever-specific changes affecting Protection**
- Thunder Clap usable in Defensive Stance (6 s cooldown, AP scaling, threat reduced to compensate). **Improved Thunder Clap moved to Prot** (-6 rage at 3/3).
- **Vanguard** (16-point milestone): Charge usable in Defensive Stance (still out of combat only).
- **Shield Specialization**: 5 rage per block (was 1). **Master of Defense** (row 3): 50/100% chance for 5 rage on dodge or parry with a shield.
- **Improved Revenge**: now +60% Revenge damage (stun removed). Revenge itself was buffed and is learned at 14 [Oli, Icy].
- **Bastion** (+2%/rank damage with a shield, up to 10%) and **Focused Rage** (-1 to -3 rage on offensive abilities). Swapped Sep 24: Focused Rage is now row 5, Bastion row 6.
- Defiance and Unyielding now require a shield. Shield Slam scales more with Block Value and does more threat.
- Improved Shield Block and Improved Taunt are now baseline. Taunt has an 8 s cooldown. One-Handed Weapon Specialization was removed.
- **Oct 1 reshuffle**: Toughness removed. Iron Will (row 1), Improved Bloodrage (row 1), Anticipation (row 2), Improved Revenge (row 2), Improved Disarm (row 3), Improved Shield Bash (row 4). The goal is to let non-shield builds reach Last Stand.
- Key levels: Defensive Stance at 10 (quest), Taunt 10, Revenge 14, Tactical Mastery 14, **Shield Block 16**, Retaliation 20, Victory Rush 20, Intimidating Shout 22, Challenging Shout 26, Shield Wall 28, Berserker Stance and Intercept 30.

**Gaps**
- No endgame threat priority (KallTorak's 30-60 and endgame tabs are WIP). Nobody ranks Shield Slam against Revenge against Sunder at 60.
- No raid cooldown plan (Shield Wall at about 4 min, Last Stand at 3 min).
- No dual-wield or "fury-prot" tank coverage (mythicsim lists a fury-prot trinket page, nothing more).

---

## Rogue - class-wide sources

| ID | site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|---|
| R-DEV | Blizzard beta dev notes | https://us.forums.blizzard.com/en/wow/t/2360696 | patch notes | Sep 24, Oct 1 | OK (browser) |
| R-IVO | Icy Veins class overview | https://www.icy-veins.com/wow-forever/rogue-class-overview | talent changes | Sep 20 (BlizzCon-era info) | OK (browser) |
| R-MOO | Mobalytics class overview | https://mobalytics.gg/wow-forever/guides/rogue-class-overview | talent changes | Sep 18 | OK (browser) |
| R-MTH | Method leveling | https://www.method.gg/wow-forever/wow-forever-rogue-leveling-guide-and-talents | leveling (Combat + Assassination builds) | Sep 30 | OK |
| R-WT | Warcraft Tavern class guide | https://www.warcrafttavern.com/forever/guides/rogue/ | brief per-spec priorities | Sep 2026 | OK (thin) |
| R-PUG | powerupgaming | (W-PUG) | talent change list | Sep 14 | OK (thin) |
| R-ZK | zockify | https://www.zockify.com/forever/rogue/ | overview ("specs coming soon") | Sep 15 | OK (thin) |

No official Blizzard Rogue deep dive exists yet. The series has covered Hunter, Druid, Priest, Warrior and Paladin so far (lfcarry says the same).

### Rogue baseline changes that affect every tree
- **Combo points no longer reset when you change target.** They stay on the old target until you start building on a new one. You cannot move them to a new target. [R-MOO, R-IVO guides, mobalytics leveling]
- **Oct 1:** a missed Expose Armor no longer wipes your combo points. [R-DEV]
- Energy regen is slow in Forever [Icy Subtlety]. Pooling matters, and so does not sitting at full energy [Icy Combat/Assassination].
- Poisons come at 20 via a quest. Leveling advice: Instant on both weapons. Long fights: Instant main hand + Deadly off hand [mobalytics leveling, Icy, wowtbc]. Poisons last 1 h, have charges, and can drop on zoning [Icy Sub].
- **Windfury disagreement:** mobalytics leveling says do not put poison on the main hand alongside Windfury Totem (they do not stack). R-WT says poisons now stack with sharpening stones and Windfury.
- Rogues can use 1H axes [R-MOO, R-WT, R-ZK]. New poison types exist [R-WT]. R-ZK claims Sap no longer breaks Stealth (single source, unverified).
- Key levels: Slice and Dice 10, Expose Armor 14, **Ambush 18**, poisons 20, Hemorrhage 30 (Subtlety talent) [R-MTH, Icy Sub].
- **No rogue tank** exists: no source publishes one, and lfcarry and mythicsim state there are only three DPS specs.

---

## Rogue - Assassination

**Sources** (plus R-DEV, R-IVO, R-MOO, R-MTH, R-WT, R-PUG, R-ZK)

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/assassination-rogue/ | rotation | "Level 30 (Beta)", sims pending | OK |
| Icy Veins (Sellin) | https://www.icy-veins.com/wow-forever/assassination-rogue-melee-dps-pve-guide | rotation + leveling, lvl 30 | Sep 17 | OK (browser) |
| Mobalytics | https://mobalytics.gg/wow-forever/classes/assassination-rogue-guide | leveling 1-30 | Sep 22 | OK (browser) |
| wow.gg (Fouren) | https://wow.gg/guides/rogue-assassination-forever-overview | spec overview | Sep 18 | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-voleur-assassinat-wow-forever/ | build | Sep 14 | OK |

**Rotation (single target)**
wowtbc (endgame framing):
1. Poisons applied (Instant MH, Deadly OH).
2. Slice and Dice up.
3. Venom up.
4. Cold Blood paired with Mutilate when below 3 CP. This step appeared in the search-index excerpt of the wowtbc page but not in the fetched summary, so verify it.
5. Eviscerate only if it will not delay Venom or Slice and Dice.
6. Mutilate as the builder.

Icy (level 30): Instant Poison on both weapons. Stealth then Ambush. Mutilate as the builder (Backstab from behind, or Sinister Strike, before 30). At 5 CP: Slice and Dice if the target will outlive it, otherwise Eviscerate. Cold Blood on cooldown (do not hoard it).
Mobalytics: Cheap Shot opener (2 CP + stun), Sinister Strike/Mutilate to 5 CP, Slice and Dice, then build to Eviscerate. Use the control chain on elites.
R-WT: Mutilate builds, Venom spends. Use Sinister Strike when you need to save energy.

Disagreements:
- Opener: Ambush (Icy) vs Cheap Shot (mobalytics). Both are valid; it depends on solo safety.
- **Poison choice affects Mutilate.** wow.gg says Instant Poison leaves no lasting effect on the target, so it does *not* enable Mutilate's +20% vs poisoned. Icy's "Instant on both" leveling advice ignores this. For a Mutilate build, keep a lasting poison (Deadly) on one weapon.
- Slice and Dice: wowtbc says always up. Icy says only on targets that live long enough. Icy also skips Improved Slice and Dice at 30 because mobs die too fast.

**AoE**: none specific. Assassination has no cleave; packs are handled with Sap, Blind and Evasion [mobalytics].

**Execute / opener**: no execute. Openers: Ambush, Garrote (bleed) or Cheap Shot (stun) [wow.gg, Icy, mobalytics]. Thistle Tea restores energy (5 min cooldown) [mobalytics].

**Defensives**
- Evasion when fighting 2 mobs, or as a last resort on an elite. Vanish to reset or escape. Vanish fails if a DoT or bleed is ticking on you; use Evasion or Sprint instead [mobalytics].
- Elite control chain: Cheap Shot > 5 CP Kidney Shot > Gouge at the end of the stun to pool energy > Blind to bandage > Evasion [mobalytics].
- Kick for interrupts. Gouge and Blind to take a mob out. Sap pre-pull.

**Forever-specific changes**
- **Mutilate** (talent, the level 30 point in the beta build): needs two daggers, 60 energy, hits with both hands for 75% weapon damage plus a flat amount (13 per R-MOO and wow.gg, 17 per kami), +20% vs poisoned targets, awards 2 CP. Lethality and Cold Blood now include Mutilate.
- **Venom** (new capstone finisher, level 30 talent per wowtbc): +30% poison damage, +10% poison application chance, lasts 9/12/15/18/21 s by CP (25 energy per wow.gg). It is an upkeep buff, not a damage finisher. wow.gg calls it "Envenom" and mythicsim calls it a poison; Venom is the right name.
- **Cold Blood** moved higher in the tree. **Vigor** moved down to 2 ranks (+5/10 max energy). **Improved Expose Armor** lowers the cost and refunds a CP at 5 CP. **Improved Kidney Shot** now makes the stunned target take more damage from you. **Improved Gouge** moved here from Combat. Improved Eviscerate moved to Combat.
- Seal Fate gives CP on generator crits, so do not press an expensive generator at near-full CP [wow.gg]. Relentless Strikes keeps its 20% per CP chance to refund 25 energy.

**Gaps**
- No sim-backed priority (wowtbc says sims are pending).
- Nobody defines when to refresh Venom vs Slice and Dice (clipping rules), or how many CP to spend on Venom.
- No AoE plan.
- No source confirms whether Deadly Poison is required for Mutilate's bonus at endgame.

---

## Rogue - Combat

**Sources** (plus R-DEV, R-IVO, R-MOO, R-MTH, R-WT, R-PUG, R-ZK)

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/combat-rogue/ | rotation | "Level 30 (Beta)" | OK |
| Icy Veins (Sellin) | https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-guide | rotation + leveling, lvl 30 | Sep 17 | OK (browser; WebFetch 403) |
| Mobalytics (FF) | https://mobalytics.gg/wow-forever/classes/combat-rogue-guide | leveling 1-30 | Sep 22 | OK (browser) |
| Mobalytics (Oli) | https://mobalytics.gg/wow-forever/classes/rogue-leveling-guide | Combat leveling 1-30 | Sep 22 | OK (browser) |
| wow.gg (Fouren) | https://wow.gg/guides/rogue-combat-forever-overview | spec overview | Sep 18 | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-voleur-combat-wow-forever/ | build | Sep 14 | OK |

**Rotation (single target)**
wowtbc (endgame framing): poisons (Instant MH, Deadly OH) > Slice and Dice up > Blade Flurry, Adrenaline Rush and on-use effects > Eviscerate if it will not delay Slice and Dice > Sinister Strike. wowtbc notes it is unclear whether the Sinister Strike or the Backstab variant will win.
Icy (level 30):
1. Instant Poison on both weapons.
2. From stealth: Ambush with a dagger, otherwise Garrote.
3. Blade Flurry early and often (the haste is worth it even on a single target).
4. Riposte whenever it is lit (after a parry).
5. Backstab if you have a dagger and are behind the target, otherwise Sinister Strike.
6. At 5 CP: Slice and Dice if the target will outlive it, otherwise Eviscerate.
Mobalytics (Oli): out-of-stealth Sinister Strike pulls are often faster. Eviscerate at 3+ CP or when the mob is nearly dead. Slice and Dice only for back-to-back or multi-mob fights. Keep SnD up on bosses and stay behind the target.
Mobalytics (FF): Cheap Shot opener, Sinister Strike to 5, Slice and Dice, then build to Eviscerate.
R-MTH: Backstab or Sinister Strike > keep Slice and Dice up > Expose Armor only if the target lives long enough.

Disagreement on Slice and Dice while leveling: Icy and wowtbc say keep it up. Oli says it has little value 1v1. Combo-point threshold: Icy uses 5 CP, Oli uses 3+.

**Restless Blades rule (wow.gg, endgame):** keep the sustain effects first (Slice and Dice, the assigned Expose Armor), then put the extra CP into *damage* finishers (Eviscerate, Rupture). Only damage finishers reduce Adrenaline Rush, Blade Flurry, Evasion, Sprint and Vanish cooldowns (2 s per CP). Slice and Dice, Expose Armor and Kidney Shot do not. A damage finisher on a dying mob still returns cooldown time.

**AoE / cleave**: Blade Flurry (talent, level 30; +20% attack speed and hits a second target for 15 s). Turn it on when a second target is safe to hit. Combine it with Adrenaline Rush for a burst window, or spread them across pulls. Do not hit crowd-controlled mobs.

**Opener**: Ambush (dagger) / Garrote / Cheap Shot from stealth, or a plain Sinister Strike pull while leveling. Adrenaline Rush (doubles energy regen for 15 s): use it with room to spend the energy, never at full energy before disengaging [wow.gg].

**Defensives**
- Evasion: 2-mob fights, or to tank aggro. Riposte comes off parries. Endurance shortens Sprint and Evasion cooldowns. Improved Sprint (full rank) removes snares.
- Vanish for escape or threat reset (not while DoTed). Gouge and bandage, Blind, Kidney Shot for elites. Restless Blades brings Sprint, Evasion and Vanish back sooner, so plan around their real remaining cooldown.

**Forever-specific changes**
- **Restless Blades** (new): see the rule above.
- **Hack and Slash** replaces the four weapon specializations: axes and swords get an extra-attack chance (1%), daggers and fists +1% crit, maces ignore 3% armor. Axes are new for Rogues.
- **Flawless Execution** (new): Eviscerate costs 10 less energy.
- **Surprise Attacks** now lowers the target's dodge and parry instead of giving weapon skill.
- **Puncturing Wounds** replaces Improved Backstab (Backstab crit and extra CP; also adds Mutilate crit).
- Precision and Deflection need fewer points. Riposte: 150% weapon damage + 6 s disarm [kami].
- Weapon advice: slow main hand + fast off hand for Sinister Strike; daggers only if you can stay behind the target [wow.gg, Oli].

**Gaps**
- No endgame priority or sim (Sinister Strike vs Backstab is unresolved).
- No CP-spend rule that balances Restless Blades against Slice and Dice uptime with numbers.
- No Blade Flurry/Adrenaline Rush timing guidance for raids.

---

## Rogue - Subtlety

**Sources** (plus R-DEV, R-IVO, R-MOO, R-WT, R-PUG, R-ZK)

| site | URL | guide type | stated date / level | fetch |
|---|---|---|---|---|
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/subtlety-rogue/ | rotation | "Level 30 (Beta)" | OK |
| Icy Veins (Seliathan) | https://www.icy-veins.com/wow-forever/subtlety-rogue-melee-dps-pve-guide | rotation + leveling, lvl 30 | Oct 1 (newest rogue guide) | OK (browser) |
| Mobalytics (FF) | https://mobalytics.gg/wow-forever/classes/subtlety-rogue-guide | leveling 1-30 + lvl 60 PvE talents (gameplay empty) | Sep 22 | OK (browser) |
| wow.gg (Fouren) | https://wow.gg/guides/rogue-subtlety-forever-overview | spec overview | Sep 18 | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-voleur-finesse-wow-forever/ | build | Sep 14 | OK |

**Rotation (single target)**
wowtbc (the most detailed endgame-style list):
1. Poisons applied.
2. Slice and Dice up.
3. Rupture up.
4. Hemorrhage debuff up.
5. Premeditation when below 4 CP.
6. Vanish into Ambush when out of stealth (Preparation resets Vanish).
7. Eviscerate only if it will not delay Slice and Dice or Rupture.
8. Ambush on a Cutthroat proc, or while stealthed.
9. Backstab as the builder.

Icy (level 30): Ambush opener from stealth. Backstab (behind) or Sinister Strike before 30. **From 30, Hemorrhage is the builder at all times** (no positional requirement). At 30, Rupture beats Slice and Dice on targets that live its full duration. Wait for the tank before bursting; Evasion (with Setup) or Vanish if you pull aggro.
Mobalytics: Stealth > Cheap Shot or Ambush > Ghostly Strike first (dodge buff) > Sinister Strike/Hemorrhage to 5 > Slice and Dice > then Rupture if the target lives 10+ s, otherwise Eviscerate.
R-WT: two variants. Bleed: Hemorrhage > Rupture, Ghostly Strike on cooldown, Slice and Dice in long fights. Stealth-opener: Ambush with a weapon swap > Sinister Strike.

Disagreement, the core one: is the builder Backstab (wowtbc; it fishes Cutthroat procs) or Hemorrhage (Icy, mobalytics, R-WT)? wow.gg: if you cannot stay behind the target, go Hemorrhage; Cutthroat only lifts the stealth requirement from Ambush, not the dagger or positional requirement. Thousand Cuts discounts both builders, so either works with Rupture up.

**AoE**: none. Icy says the spec has no AoE at all.

**Opener**: Ambush (dagger in main hand; Icy suggests swapping to a slow main hand afterwards via macro, but a swap costs a GCD and resets the swing). Premeditation (2 CP, must be used within 20 s) + Initiative let you leave stealth with a finisher ready. Dirty Deeds makes Cheap Shot and Garrote cheaper and removes Garrote's positional requirement [wow.gg]. Choose per fight: burst (Ambush), bleed (Garrote) or control (Cheap Shot).

**Defensives**
- Evasion: tank aggro and gain CP via Setup. Vanish: threat reset or escape. Do not Vanish in melee range or it breaks; Gouge or Kidney Shot first [Icy]. Preparation (Talented point) gives a second Evasion/Vanish. Sap and Blind for control. Dirty Tricks makes Sap and Blind cheaper.

**Execute**: Quietus (new) is the closest thing: +2-10% Sinister Strike, Ghostly Strike and Hemorrhage damage vs targets below 35%. It is not a true execute.

**Forever-specific changes**
- **Cutthroat** (new, 5 ranks): Backstab has a 3-15% chance to make your next Ambush within 10 s usable outside stealth. Still needs a main-hand dagger and to be behind the target. (One search snippet said Sinister Strike triggers it; every fetched source says Backstab.)
- **Hemorrhage** (talent, 30) reworked: weapon damage (higher with a dagger, 145% vs 100% per kami). Makes the target take +15% damage from *your* Rupture for 15 s. No longer a group debuff.
- **Thousand Cuts** (new, takes Premeditation's old capstone slot): each Rupture tick takes 3 energy off the next Hemorrhage or Backstab within 10 s, stacking to 5. It is a discount only, so do not cap energy waiting for stacks.
- **Premeditation** moved much earlier. **Setup** now only adds CP to your current target, and only if that target was the one you dodged or resisted (Sep 24/Oct 1).
- Serrated Blades: armor penetration plus a separate Rupture damage bonus. New talents: Dirty Tricks, Improved Distract. Removed: Improved Sap, Sleight of Hand, Deadliness.

**Gaps**
- No endgame rotation (mobalytics' level 60 PvE gameplay tab is empty). Nobody ranks Backstab against Hemorrhage, or gives a Rupture refresh window or Cutthroat proc handling with numbers.
- No raid Vanish/Preparation usage plan.

---

## Rogue - tank / other Forever builds
- **None found.** No guide publishes a rogue tank, and lfcarry and mythicsim (Oct 7) explicitly state that Rogue has only the three DPS specs. Evasion-tanking is mentioned only as a way to survive pulling aggro [Icy Sub].

---

## Sources not usable
- **mythicsim.com/wow-forever/warrior, /rogue** (Oct 7): sim class pages with no rotation or priority text, only spell/talent names. Too thin. It does list trinket boards for a "fury-protection" warrior.
- **zockify.com/forever/warrior/** (Sep 14): says spec guides are coming soon. Its one concrete claim (Recklessness cut to 15 min) contradicts the official deep dive.
- **lfcarry.com/guides/wow-forever-rogue**: no rogue kit content (it predates the rogue info); used only to confirm there is no rogue tank.
- **wowhead.com/forever**: WebFetch returned 403 and searches surfaced no Forever warrior or rogue guide. None found.
- **world-of-warcraft-forever.wiki / warcraft.wiki.gg**: searches returned no Forever-specific warrior or rogue pages (warcraft.wiki.gg only has a Classic Recklessness page, wrong game).
- **mobalytics.gg/wow-forever/classes/protection-warrior-guide**: HTTP 410, archived (replaced by the KallTorak guide).
- **mobalytics.gg/wow-forever/warrior-guides, /rogue-guides**: hub pages with no content.
- **kami-labs.fr/en/wow-forever/build-guerrier-furie-wow-forever/**: 404 (guessed URL). The kami-labs builds hub lists 4 warrior and 3 rogue builds but did not render a list.
- **kami-labs PvP Arms build** (French): PvP, out of scope.
- **highgroundgaming.com/?p=88495**: WotLK Classic warrior leveling guide, wrong game.
- **warcrafttavern.com SoD Protection Warrior, legacy-wow.com WotLK Prot**: wrong game (Season of Discovery / WotLK).
- **icy-veins.com/wow/...** (retail warrior and rogue guides) and **wowhead classic hardcore tips**: wrong game.
- **us.forums.blizzard.com "Feedback: Rogues" (2175619) and the EU equivalent**: not Forever-specific in search excerpts; not used.
- **seemeta.com, exitlag, gamesfuze, hostedgg, mein-mmo**: tier lists and race pages, no rotation content.
