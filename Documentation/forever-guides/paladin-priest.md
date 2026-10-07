# Paladin and Priest - WoW Forever guide references

researched 2026-10-07 (beta cap 30, beta patch label "1.60.1" on wowhead; launch 2026-11-04).

All priorities below are paraphrased summaries, not guide text. "L30" = beta level-30 guidance.
Where guides disagree the newest source (wowhead, 2026-10-06, and the official dev notes) wins
unless stated otherwise.

## Cross-cutting facts (both classes)

Official beta dev notes (Blizzard EU forums, builds of 2026-09-24 and 2026-10-01):
- Holy Strike cooldown 12 s -> **10 s**; Improved Holy Strike talent **removed**; Holy Power talent now gives Holy Strike +15% crit.
- Righteous Fury Holy threat bonus 90% -> **60%**.
- Vengeance: procs only from non-periodic crits, max 3 stacks (was 5). Two-Handed Weapon Spec 2/4/6%.
- Sacred Arbiter: Holy Strike +20% (was 10%) and refreshes Judgement debuffs.
- Twist of Light also cuts seal mana cost 20%.
- Champion of the Light: Intellect-to-spell-damage 20/40/60% (was 33/66/100%); wowhead says it no longer adds healing.
- Redoubt 4..20% block; Holy Shield block chance 30% (was 20%).
- Retribution Aura damage now updates live with spell power.
- Priest: Renew can crit; Devouring Plague can crit; Inner Focus crit bonus no longer applies to periodic effects;
  Power Word: Shield can now overwrite an existing shield (Weakened Soul handling changed - wording ambiguous, verify).
- Character-sheet tooltip now explains that low-rank spells cast at high level get reduced benefit from +damage/+healing.

Downranking: a forum thread (2026-09-17) reports an anti-downranking scaling on bonus healing/damage for lower ranks;
the dev-notes tooltip change confirms a rank penalty exists. Downranking still works for mana saving (mobalytics Holy
Paladin advises keeping low-rank Holy Light on bars) but gear scaling on low ranks is reduced. wowtbc.gg and
icy-veins say they do not yet know how downranking behaves and list one rank per spell.

No DoT snapshotting in Forever (icy-veins Shadow): DoTs update with current stats.

Spell ranks: new ranks every 2 levels from level 2 (wowhead); action bars do NOT auto-upgrade ranks for casters
(icy-veins Shadow) - a suggestion addon must resolve the highest known rank itself.

---

## Paladin - Retribution

**Sources**

| site | URL | guide type | stated date / level | fetched |
|---|---|---|---|---|
| wowhead | https://www.wowhead.com/forever/guide/classes/paladin/retribution/level-30-dps-overview | rotation, leveling, talents | 2026-10-06, L30, beta 1.60.1 | OK (browser) |
| wowhead | https://www.wowhead.com/forever/guide/classes/paladin/retribution/dps-abilities | ability reference | beta build | OK (browser) |
| wowhead | https://www.wowhead.com/forever/guide/classes/paladin/retribution/level-20-dps-overview | leveling | L20 | not fetched (superseded by L30) |
| icy-veins | https://www.icy-veins.com/wow-forever/retribution-paladin-melee-dps-pve-guide | rotation, leveling, Shockadin build | 2026-10-04, L30 | OK (browser; WebFetch 403) |
| icy-veins | https://www.icy-veins.com/wow-forever/paladin-class-overview | class changes | 2026-09-20 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/classes/retribution-paladin-guide | leveling rotation | 2026-09-22, L30 | OK (browser; WebFetch 403) |
| mobalytics | https://mobalytics.gg/wow-forever/guides/paladin-class-overview | class changes / talents | 2026-09-18 | OK (browser) |
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/retribution-paladin/ | rotation priority | L30 beta | OK |
| method.gg | https://www.method.gg/wow-forever/wow-forever-paladin-leveling-guide-and-talents | leveling | 2026-09-24 | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-paladin-vindicte-wow-forever/ | build | 2026-09-14 (pre-beta) | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/paladin-wow-forever-sorts-et-talents-modifies/ | spell/talent changes | 2026-09-26 | OK |
| Blizzard EU forums | https://eu.forums.blizzard.com/en/wow/t/631316/1 | official dev notes | 2026-09-24 / 10-01 | OK |

**Rotation (single target)** - L30 consensus
1. Keep a damage seal up: Seal of Righteousness (fast weapon / lots of spell power) or Seal of Command (slow 2H). Seals expire - refresh when the buff drops (wowhead).
2. Optional opener on anything that will live a while (elites, bosses): Seal of the Crusader -> Judgement to apply the Holy-damage-taken debuff -> switch back to the main seal. Skip on trash to save mana (mobalytics, icy, wowhead).
3. Judgement on cooldown (off the GCD per wowhead; Judgement no longer consumes the seal).
4. Holy Strike on cooldown (10 s). With Sacred Arbiter it refreshes the Judgement debuffs, so the Crusader debuff stays up.
5. Exorcism on cooldown vs Undead/Demon.
6. Hammer of Wrath when target < 20% (execute; has a cast time - Instrument of Law shortens it). wowtbc lists it; level-30 guides barely mention it (likely trained past 30 - unverified).
7. Hammer of Justice on dangerous mobs; with Seal of Command, Judging a stunned/incapacitated target doubles the Judgement damage (wowhead ability text), so HoJ/Repentance -> Judgement is a burst combo (icy).
- Mana: all guides stress rationing - Holy Strike is cheap, Consecration expensive; keep mana for self-heals between pulls.
- wowtbc ordering (Aura > Blessing > Crusader debuff > seal twist SoC/SoR > Holy Strike > Judgement > HoW > Exorcism > Consecration) assumes Twist of Light, which wowhead says is out of reach at 30.

Seal twisting (endgame, Twist of Light capstone): swapping away from Command / Righteousness / Fury / Justice
grants an Echo; the next melee swing also applies the replaced seal. Practical loop (wowtbc): swap between
Seal of Command and Seal of Righteousness right after each auto attack. Not available at L30.

**AoE**
- No AoE before level 20. Consecration trained at 20 (baseline now). Use on 3-4+ targets only; costly.
- Consecration does bonus damage to the first 4 targets inside it; extra targets take little (icy, wowhead).
- Holy Wrath vs Undead/Demon packs (wowhead ability list; level not stated).

**Upkeep**
- Aura: Retribution Aura default (scales with spell power), Devotion if the group needs mitigation.
- Blessing: Might or Kings on self; Blessings now last 60 min; Kings is trainer-learned (level 20 per method).
- Seal always active in combat.

**Defensives**
- Divine Shield (12 s full immunity, you deal 50% less damage, Forbearance) - mobalytics recommends a cancel-aura macro.
- Divine Protection (8 s immunity but cannot attack/use abilities; can still cast) - wowhead ability text. Note this
  is inverted vs. the old Classic naming; verify in client.
- Lay on Hands (heal = your max HP, drains all mana). Blessing of Protection on allies who pull aggro.
- Holy Light / Flash of Light self-heal ("mana as a second health bar" for leveling - icy).

**Forever-specific changes**
- Holy Strike baseline at level 6, Holy damage from weapon + spell power, 10 s CD.
- Judgement does not consume the seal.
- Consecration trained at 20; Blessing of Kings trained (20); Blessings 60 min.
- Twist of Light (capstone), Sacred Arbiter, Sanctified Judgement (Judgement refunds part of seal cost),
  Benediction (instant spell cost -2%/pt), Holy Conduit (-20%/pt Consecration/Holy Wrath/Exorcism/HoW cost),
  Vengeance rework, Crusade, Champion of the Light (Int -> spell damage, 20/40/60%), Instrument of Law.
- Spell power gear is competitive with Strength because seals, Judgement, Holy Strike and Consecration scale with it.
  Disagreement: mobalytics says stack Strength/Agility; icy and wowhead say spell power is often better.
- L30 new spells: Seal of Justice, Seal of Light, Concentration Aura, Shadow Resistance Aura, Blessing of Salvation (26),
  Turn Undead, Divine Intervention. Righteous Fury and Retribution Aura at 16 (wowhead Prot).

**Shockadin (hybrid)**
- Holy Shock requires 20 Holy points, trainable at 30 (was 40), 160 mana, 10 s CD, 40 yd range, 42.9% SP coefficient.
- Icy build: Holy Shock on CD as an extra rotational button; Improved Seals boosts SoR; Reverence is the only mana
  sustain; Divine Favor guarantees a Holy Shock crit. Seal of Righteousness + Judgement + Holy Strike + Holy Shock.
- wowhead skips it at 30 (mana problems); Light's Vigil (40) is the intended Shockadin enabler later.

**Gaps**
- No level-60 priority from any source; Hammer of Wrath and Holy Wrath training levels not confirmed.
- Divine Shield vs Divine Protection behavior only from wowhead tooltip summaries.
- Seal durations not stated anywhere.

---

## Paladin - Protection

**Sources**

| site | URL | guide type | stated date / level | fetched |
|---|---|---|---|---|
| wowhead | https://www.wowhead.com/forever/guide/classes/paladin/protection/level-30-tank-overview | tank priority, leveling | 2026-10-06, L30 | OK (browser) |
| icy-veins | https://www.icy-veins.com/wow-forever/protection-paladin-tank-pve-guide | tank rotation, seals, utility | 2026-10-01, L30 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/classes/protection-paladin-guide | tank gameplay | 2026-09-24, L30 | OK (browser) |
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/protection-paladin/ | tank priority | L30 beta | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-paladin-protection-wow-forever/ | build | pre-beta | not fetched (search hit only) |

**Tanking priority (single target)**
1. Precombat: Righteous Fury on (level 16), Retribution Aura (default, scales with SP) or Devotion Aura; Blessing of Might/Kings.
2. Seal of Fury before the pull, keep it up the whole fight (wowhead, icy). Off-tank / not tanking: Seal of Righteousness (wowtbc) or Seal of Light for solo sustain (wowhead).
3. Judgement on cooldown - with Seal of Fury it deals damage AND taunts for 4 s. icy: hold a Judgement in reserve for lost targets once you are comfortable; wowhead: just use it.
4. Exorcism vs Undead/Demon. (Optional: Seal of the Crusader for the first Judgement vs Undead/Demons - wowhead.)
5. Holy Strike on cooldown (Iron Creed adds threat and 2%/rank damage reduction while Righteous Fury is up - keep it rolling).
6. Consecration if mana allows.
- wowtbc adds: maintain Holy Shield; Swift Judgement -> Judgement for an emergency double taunt; Templar's Bulwark as the emergency button.

**AoE / multi-target**
1. Seal of Fury up.
2. Consecration first (main AoE threat; spell-power bonus only on the first 4 targets).
3. Judgement on the main target, Holy Strike, then tab and Judge other mobs to spread threat (mobalytics).
4. Swift Judgement resets Judgement (next one free) - re-Judge the same target or a second mob.
5. Exorcism on Undead/Demon. Skip new Consecrations when only 1-2 mobs remain (mobalytics).
- Disagreement: mobalytics says reapply your seal after Judgement; all other sources and the change itself say Judgement no longer consumes the seal (mobalytics text likely stale).

**Upkeep**
- Righteous Fury always (threat bonus now 60%). Seal of Fury. Aura (Ret default). Blessing of Might on party; Salvation (26) only on high-threat DPS when buffs are plentiful.

**Defensives**
- Templar's Bulwark: absorb = 100% max HP for 8 s, applies Forbearance (1 min), cannot be used under Forbearance; available at 30 (wowhead calls it a spell learned at 30, mobalytics/icy list it as a talent - unclear).
- Sacred Duty: -60 s/rank on Divine Shield, Divine Protection and Templar's Bulwark cooldowns.
- Divine Shield: drops threat on the party - use briefly and cancel (mobalytics macro). Shares Forbearance with Bulwark and BoP.
- Lay on Hands as last resort. BoP on a healer being hit. Dwarf Stoneform now also reduces physical damage.

**Mana**
- Shield Specialization: blocks restore mana (6% max mana, max once per 3 s per kami/icy). Redoubt raises block.
- Improved Seal of Fury: mana when the Seal of Fury absorb is fully consumed (scales with attacker level).
- Holy Conduit (Ret) cheapens Consecration. Play conservatively with Consecration until comfortable (icy).

**Forever-specific changes**
- Seal of Fury (new): small Holy damage per swing; with a shield equipped you gain an absorb worth 50% of the Holy damage; Judgement of it taunts 4 s.
- First real taunt for Paladins; Righteous Fury, Retribution Aura at 16; Consecration at 20; Templar's Bulwark at 30.
- Hammer of the Righteous at 40+ (target + 3 nearby, 6 s CD - kami).
- Stats: spell power valued for threat (icy: SP first); mobalytics: Stamina first then Str/Agi. Disagreement.

**Gaps**
- Holy Shield placement/level not confirmed at 30; Avenger's Shield not mentioned anywhere.
- No level-60 priority.

---

## Paladin - Holy

**Sources**

| site | URL | guide type | stated date / level | fetched |
|---|---|---|---|---|
| wowhead | https://www.wowhead.com/forever/guide/classes/paladin/holy/level-30-healer-overview | healing + damage priority | 2026-10-06, L30 | OK (browser) |
| wowhead | https://www.wowhead.com/forever/guide/classes/paladin/holy/healer-abilities | ability reference | beta | not fetched |
| icy-veins | https://www.icy-veins.com/wow-forever/holy-paladin-healer-pve-guide | healing spells, seals | 2026-10-01, L30 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/classes/holy-paladin-guide | healing, ranks | 2026-09-22, L30 | OK (browser) |
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/holy-paladin/ | healing priority (endgame-ish) | L30 beta | OK |
| kami-labs | https://kami-labs.fr/en/wow-forever/build-paladin-sacre-wow-forever/ | build | pre-beta | not fetched |

**Healing priorities** (L30 kit: Flash of Light, Holy Light, Holy Shock, Seal of Light, Lay on Hands)
1. Emergency, target about to die: Holy Shock (instant). Last resort: Lay on Hands (heal = your max HP, costs all mana) - or when already out of mana.
2. Divine Favor + Holy Shock or Holy Light for a guaranteed crit (wowtbc, icy).
3. Infusion of Light proc (from Holy Shock/Flash of Light crit): next Holy Light is 0.5 s faster - spend it on Holy Light (wowtbc).
4. Default filler: Flash of Light (cheap, fast; icy calls it the primary heal).
5. Holy Light only for big deficits / when mana allows (icy, wowhead); mobalytics instead suggests low-rank Holy Light as the efficient workhorse and max-rank Holy Light to top the tank (subject to the downrank penalty).
6. Group "AoE": Judgement of Light (Seal of Light judged on an enemy) - attacks on it heal attackers (wowhead).
7. Light's Vigil (level 40, not in L30 beta): mark an ally, next Holy Shock on them has no cooldown and heals their whole party (or damages + refunds 75% mana on an enemy); one active per Paladin per party. wowtbc endgame: Light's Vigil then chain Holy Shock for group damage.
- Triage: tank first, but don't let the rest of the party sit low (mobalytics).
- Only one Judgement debuff of yours per target: judging Seal of Light then switching seals keeps JoL; a new Judgement replaces it (wowhead).

**Mana rules**
- Reverence: 10%/rank of regen continues while casting (Spirit matters now). Illumination: crits refund mana - crit is a key stat (mobalytics).
- Intellect does not add healing (wowhead); look for +healing. MP5 always ticks.
- Seal of Wisdom on bosses for caster-heavy groups, Seal of Light for melee-heavy (mobalytics).

**Upkeep**
- Aura: Devotion (survivability) or Retribution (damage). Blessings Might/Wisdom/Kings, 60 min.
- Seal of Light judged on the enemy; Seal of Righteousness when dealing damage.

**Damage when idle (wowhead)**
Seal of Righteousness -> Judgement -> Holy Strike -> Exorcism (Undead/Demon) -> Holy Shock -> Consecration.

**Defensives**
- Divine Shield self; Blessing of Protection / Hammer of Justice to save an ally (BoP on a tank drops their threat).
- Voice of Truth (talent): 6 s immunity to silence/interrupt.

**Forever-specific changes**
- Holy Shock: 20-point talent (trainable at 30), 10 s CD, 40 yd, 160 mana. Light's Vigil replaced Holy Shock as the capstone (icy) - wowhead says it is learned at 40.
- New: Infusion of Light, Reverence, Voice of Truth, Divine Precision, Consecrated Ground, Purifying Power, Light's Vigil.
- Paladins benefit from Spirit for regen now.

**Gaps**
- No raid healing / level-60 priorities. Divine Illumination, Blessing of Light usage not covered. Holy Power (talent) value unclear.

---

## Priest - Discipline

**Sources**

| site | URL | guide type | stated date / level | fetched |
|---|---|---|---|---|
| wowhead | https://www.wowhead.com/forever/guide/classes/priest/discipline/level-30-healer-overview | healing + questing | 2026-10-06, L30 | OK (browser) |
| wowhead | https://www.wowhead.com/forever/guide/classes/priest/discipline/overview-pve-healer | spec overview | beta | not fetched |
| icy-veins | https://www.icy-veins.com/wow-forever/discipline-priest-healer-pve-guide | healing + damage | 2026-09-17, L30 | OK (browser) |
| icy-veins | https://www.icy-veins.com/wow-forever/priest-class-overview | full talent change list | 2026-09-20 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/classes/discipline-priest-guide | leveling DPS (Holy Fire/Smite/wand) | 2026-09-24, L30 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/guides/priest-class-overview | talents, racials | 2026-09-19 | OK (browser) |
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/discipline-priest/ | healing priority (endgame-ish) | L30 beta | OK |
| method.gg | https://www.method.gg/wow-forever/wow-forever-priest-leveling-guide-and-talents | leveling by bracket | 2026-10-04 | OK |
| Blizzard | https://worldofwarcraft.blizzard.com/news/24301514 | official class deep dive (Priest & Warrior) | 2026-09-30 | OK |

**Healing priorities**
1. Big incoming raid/party damage: Power Word: Shield on as many targets as possible beforehand (wowtbc).
2. Tank: shield before the pull and keep it shielded - EXCEPT rage tanks (Warrior/Druid): absorbs starve their rage; skip unless needed (wowhead, mobalytics; may change in beta).
3. Inner Focus + Prayer of Healing (or + Heal) for a free, crit-boosted cast.
4. Power Infusion on a caster DPS (wowtbc); in Forever it requires Penance and boosts spell damage/healing.
5. Renew on the tank / anyone taking chip damage.
6. Penance (20 Disc points, at 30; 2 s channel, 12 s CD) as the main single-target heal.
7. Heal as the efficient filler; Flash Heal (or Binding Heal if Holy-dipped) only for emergencies - costly.
8. Prayer of Healing (learned 30) only when most of the party is low (3 s cast, expensive). In Forever it heals the TARGET's party (+pets).
9. Dispel Magic (18) / Cure Disease when worth the mana.
- Renewed Hope: heals on targets with Weakened Soul get extra crit and shorten Weakened Soul -> shield then direct-heal the same target. Divine Aegis: crit heals leave a 12 s absorb.

**Mana rules**
- 5-second rule; Meditation (Disc, ~level 20+) allows regen while casting. Wand when nothing to heal (wanding does not reset the timer).
- Spirit Tap (killing blows) while leveling. Downranking still useful but bonus healing is penalized on low ranks.

**Damage (solo / idle)** - L30 (wowhead, icy, method)
1. Buffs: Power Word: Fortitude, Inner Fire. Pre-pull Power Word: Shield (prevents pushback).
2. Opener: Holy Fire (20+; on the priority target with Power in Light - boosts Smite and Penance on Holy Fire targets), else Smite.
3. Mind Blast, Shadow Word: Pain.
4. Penance on CD (method: from 30 Penance > wand is the core damage loop).
5. Wand to finish; recast Mind Blast if it comes back on a healthy mob. Renew self if taking hits.

**Upkeep**
- Power Word: Fortitude (2), Inner Fire (12), Divine Spirit (30, now baseline), Fear Ward (20, now baseline for all).

**Defensives**
- Power Word: Shield self; Fade (threat drop doubled in Forever, ~10 s); Psychic Scream.
- Desperate Prayer is listed as a Dwarf priest racial (mobalytics), not baseline. Human: Divine Grace (ally < 40% heal, clears Weakened Soul). Gnome: Contingency Plan (cheat-death-like ward). Undead: Dark Sacrifice (HP -> mana).

**Forever-specific changes**
- New: Penance, Divine Aegis, Renewed Hope, Soul Warding (cheaper/faster PW:S, 16-pt), Twin Disciplines (+instant spell power), Power in Light, Holy Precision.
- Power Infusion requires Penance; Wand Specialization now 2 ranks (13%/rank); Divine Spirit baseline.

**Gaps**
- No raid-healing or level-60 Disc priority from any site. Pain Suppression not mentioned. PW:S overwrite/Weakened Soul change wording ambiguous.

---

## Priest - Holy

**Sources**

| site | URL | guide type | stated date / level | fetched |
|---|---|---|---|---|
| wowhead | https://www.wowhead.com/forever/guide/classes/priest/holy/level-30-healer-overview | healing + questing | 2026-10-06, L30 | OK (browser) |
| wowhead | https://www.wowhead.com/forever/guide/classes/priest/holy/overview-pve-healer | spec overview | beta | not fetched |
| icy-veins | https://www.icy-veins.com/wow-forever/holy-priest-healer-pve-guide | healing + damage, mana | 2026-09-17, L30 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/classes/holy-priest-guide | healing | 2026-09-24, L30 | OK (browser) |
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/holy-priest/ | healing priority (endgame-ish) | L30 beta | OK |
| Blizzard | https://worldofwarcraft.blizzard.com/news/24301514 | official deep dive | 2026-09-30 | OK |

**Healing priorities**
1. Litany of Light (talent): alternate different heal spells - repeating the same one forfeits the mana refund (wowtbc, wowhead).
2. Inner Focus with Greater Heal or Prayer of Healing.
3. Renew on the tank and anyone taking steady damage (multiple priests' Renews now stack on one target).
4. Power Word: Shield to buy cast time (not on rage tanks).
5. Prayer of Mending (31-point capstone - NOT reachable at 30) on cooldown when available.
6. Prayer of Healing when most of the party is low (learned 30; range 40 yd from target).
7. Binding Heal (15 Holy points) when you and the target are both hurt; low threat.
8. Flash Heal for someone about to die (expensive).
9. Greater Heal for large single-target deficits (not trained by 30); Heal as the everyday efficient heal; Lesser Heal ranks for small top-ups (mobalytics).
10. Holy Nova when Searing Light makes it free (Holy Fire DoT ticks can proc a free Holy Nova) and nobody is in danger (icy).
- Dispel Magic / Cure Disease selectively. Wand when the group is healthy.

**Mana rules**
- 5-second rule; avoid overhealing; wand filler; downranking still useful but low ranks scale worse with +healing.
- Spirit of Redemption (20 Holy points): 15 s on death, healing spells free.

**Damage (solo)**: buffs -> pre-shield -> Holy Fire (20+) or Smite -> Mind Blast -> Shadow Word: Pain -> wand; Holy Nova for AoE tagging when solo.

**Upkeep**: Fortitude, Inner Fire, Divine Spirit (30), Fear Ward (20).

**Defensives**: Fade (keybind it in dungeons), PW:S self, Psychic Scream; race-specific ones as in Discipline.

**Forever-specific changes**
- New: Binding Heal (16-pt tier per Blizzard / 15 points per wowhead), Prayer of Mending (31-pt), Litany of Light, Twilight Focus (pushback protection on all spells).
- Removed: Lightwell, Improved Prayer of Healing. Searing Light reworked (Holy damage + free Holy Nova proc). Inspiration = armor on crit heals.
- Improved Healing now also cheapens Penance and Prayer of Mending.

**Gaps**: no raid or 60 priority; Circle of Healing not mentioned anywhere.

---

## Priest - Shadow

**Sources**

| site | URL | guide type | stated date / level | fetched |
|---|---|---|---|---|
| wowhead | https://www.wowhead.com/forever/guide/classes/priest/shadow/level-30-dps-overview | rotation, leveling | 2026-10-06, L30 | OK (browser) |
| wowhead | https://www.wowhead.com/forever/guide/classes/priest/shadow/dps-abilities | ability reference | beta | not fetched |
| icy-veins | https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-guide | rotation, mana | 2026-09-17, L30 | OK (browser) |
| mobalytics | https://mobalytics.gg/wow-forever/classes/shadow-priest-guide | leveling rotation, multi-DoT | 2026-09-24, L30 | OK (browser) |
| wowtbc.gg | https://wowtbc.gg/warcraftforever/class-guides/shadow-priest/ | rotation priority (endgame-ish) | L30 beta | OK |
| method.gg | https://www.method.gg/wow-forever/wow-forever-priest-leveling-guide-and-talents | rotation by level bracket | 2026-10-04 | OK |
| Blizzard | https://worldofwarcraft.blizzard.com/news/24301514 | official deep dive | 2026-09-30 | OK |

**Rotation (single target)** - L30 (wowhead, icy)
1. Buffs: Power Word: Fortitude, Inner Fire (Undead: Touch of Weakness). Optional pre-pull Power Word: Shield.
2. Open with Mind Blast.
3. Shadow Word: Pain.
4. Devouring Plague (20, baseline) - mana-hungry; skip on fast-dying mobs unless Devouring Contagion is talented.
5. Mind Flay (talent from 20) only if mana allows - at L30 it barely beats a wand and resets the 5-second rule.
6. Wand to finish. Before Mind Flay: Smite filler.

Endgame-ish priority (wowtbc, method 40-60):
1. Shadowform up (level 40 talent).
2. Vampiric Embrace when the party takes damage (wowtbc) - mobalytics uses it as a target debuff placed on the longest-living mob.
3. Inner Focus + Mind Blast.
4. Keep Shadow Word: Pain up; Devouring Plague.
5. Shadow Word: Death on targets <= 20% (Early Demise adds crit there). method says SW:D on cooldown in general - disagreement; it costs 10% of your max HP if the target survives, so execute-only is the safer default.
6. Mind Blast on cooldown, Mind Flay filler, SW:D as the moving instant.

**AoE**
- Multi-DoT Shadow Word: Pain on every mob (dungeons: SW:P everything first - mobalytics, wowhead), Devouring Plague on several, then Mind Flay/wand them down. Devouring Contagion spreads DP when a target dies.
- Psychic Scream to peel 2 mobs when overwhelmed (mobalytics).

**Upkeep**: Shadowform (40), Fortitude, Inner Fire, Divine Spirit (30), Fear Ward (20); VE is a cooldown, not permanent.

**Defensives**: PW:S, Fade (threat drop doubled), Psychic Scream; Shadowform also -15% physical damage taken (icy). Silence is now a real interrupt (1 talent point, no Improved Psychic Scream prerequisite).

**Mana**: wand-heavy leveling (40-50% of damage), group casts together then wand to start regen sooner; Spirit Tap (now also allows regen while casting when active); VE kills also trigger Spirit Tap; Meditation dip option.

**Forever-specific changes**
- Devouring Plague (20) and Fear Ward (20) baseline for all races; Shadow Word: Death baseline at **32** (beyond beta cap) - 15 s CD, self-damage 10% max HP on non-kill.
- Shadowform: +10% Shadow damage, -50% Shadow spell mana cost, +100% crit damage bonus on Shadow spells, -15% physical damage taken; blocks only HEALING spells now (shields/utility allowed).
- New talents: Improved Mind Flay (more damage/range, weaker slow), Devouring Contagion, Early Demise; Shadow Weaving now a self-buff stacking to 5; Vampiric Embrace moved to 16-pt tier.
- No snapshotting of DoTs.

**Gaps**: Vampiric Touch not present in any source (likely not in Forever). Exact Shadowform level/tier: wowhead says 40; Blizzard says row 6.

---

## Sources not usable

| source | URL | reason |
|---|---|---|
| wow.gg Retribution overview | https://wow.gg/guides/paladin-retribution-forever-overview | Uses ability/talent names that do not exist in Forever (Crusader Strike, Holy Arbiter, Glimmer of Light, Protector of the Light, Hand of the Law); appears speculative/generated. Ignore. |
| wow.gg Holy overview | https://wow.gg/guides/paladin-holy-forever-overview | Same site; not trusted, not fetched. |
| zockify Paladin / Priest | https://www.zockify.com/forever/paladin/ , https://www.zockify.com/forever/priest/ | Change summaries only, "builds coming soon"; no priorities. Also wrongly lists Divine Spirit as removed (it became baseline). |
| Blizzard forum "Are Shockadins a thing?" | https://us.forums.blizzard.com/en/wow/t/are-shockadins-a-thing/632264 | Classic (2020) thread, not Forever. |
| mmoexp articles | https://www.mmoexp.com/News/wow-forever-paladin-guide-best-ret-build-holy-strike-tanking-and-seal-twisting.html | Gold-seller content; not fetched. |
| warcrafttavern / seemeta / lfcarry / hostedgg | various | Only generic class/race overviews in search results; no rotation content found. |
| mythicsim, warcraft.wiki.gg, world-of-warcraft-forever.wiki | - | No Paladin/Priest Forever guide pages surfaced in searches. |
| reddit | - | No usable Forever Paladin/Priest rotation threads surfaced. |
| Blizzard Paladin deep dive | - | No official Paladin class deep dive article found (only Priest/Warrior 24301514 and Hunter/Druid 24301515). |
| wowhead L20 guides, ability pages for Holy Pal/Priest specs | see tables | Found but not fetched; superseded by L30 pages. |
