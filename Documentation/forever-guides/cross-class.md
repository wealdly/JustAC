# Cross-class WoW Forever references

Researched 2026-10-07. Scope: material shared by every class (official notes, combat
mechanics, healing, defensives/consumables, sims, beta-cap builds). Per-class rotation
guides are in the sibling files. Everything below is paraphrased; numbers are as reported
by the cited source on the date given and the beta is moving weekly.

Confidence key: **High** = Blizzard post/article; **Med** = several community sources agree
or datamined from the beta client; **Low** = single community source, unverified, or
contradicted elsewhere.

Beta client build referenced by datamining sites: 1.60.1.69913 (Sept 18) and
1.60.1.70245 (Oct 1).

## Official sources

| Title | URL | Date | What it covers |
|---|---|---|---|
| Carve a New Path with World of Warcraft: Forever (announcement, via Wowhead blue tracker mirror) | https://www.wowhead.com/forever/blue-tracker/news/eu/24302093 | 2026-09-12/13 (BlizzCon) | Launch 2026-11-04, beta 2026-09-17, positioning; no mechanics |
| WoW Forever Beta Development Notes (updated Sept 24 and Oct 1), Kaivax | https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-october-1/2360696 (Oct 1 post: /2360696/4; EU mirror https://eu.forums.blizzard.com/en/wow/t/631316/4) | 2026-09-24, 2026-10-01 | All class tuning, level cap 30, Cooldown Manager rollout, downrank tooltip, crit-able HoTs/DoTs, known issues |
| WoW Forever Beta Known Issues (started Sept 18, updated Oct 1) | https://eu.forums.blizzard.com/en/wow/t/629369 | 2026-09-18 → 10-01 | Parry/block from behind, glancing calc wrong for casters, CDM gaps, "on-next-attack disables spell queue window" |
| Class Deep Dives — Priest and Warrior | https://news.blizzard.com/en-us/article/24301514/world-of-warcraft-forever-class-deep-dives-priest-and-warrior | 2026-09-30 | Full baseline + talent lists, rage rework, racial priest spells |
| Class Deep Dives — Hunter and Druid | https://news.blizzard.com/en-us/article/24301515/world-of-warcraft-forever-class-deep-dives-hunter-and-druid | 2026-09-30 | Full baseline + talent lists, hawks, shapeshift rework |
| Forum thread for the Hunter/Druid deep dive (Nethaera reply) | https://us.forums.blizzard.com/en/wow/t/world-of-warcraft-forever-class-deep-dives-%E2%80%94-hunter-and-druid/2367361/66 | 2026-09-30 | Blue says the remaining classes will get deep dives later; details may change during beta |
| Warrior Updates in Today's Beta Build, Kaivax | https://us.forums.blizzard.com/en/wow/t/warrior-updates-in-todays-beta-build/2369360/1 | 2026-10-02 | Crit rage 100%, Fury/Prot tree rework, dev reasoning |
| BlizzCon 2026 "Forever – Deep Dive" panel (Kris Zierhut, Principal Game Designer) | recaps: https://outputlag.com/news/everything-new-world-of-warcraft-forever-deep-dive/ , https://outputlag.com/news/world-of-warcraft-forever-unifies-hit-and-crit-stats-and-gives-healing-gear-bonus-damage/ | 2026-09-13 | Hit/crit merge, 16-pt gold talent, buff talents baseline, Paladin rework walkthrough |
| Paladin changelist (BlizzCon; only class with a full list before the deep dives) | no first-party URL found; recaps: https://www.warcrafttavern.com/forever/news/all-changes-to-paladins-in-wow-forever/ , https://lfcarry.com/guides/wow-forever-paladin | 2026-09-13 | Holy Strike L6, Seal of Fury taunt, seals not consumed, Consecration baseline |
| Sept 17 beta-launch Q&A stream (Nora Mills, Lead Software Engineer; Tim Jones, Lead Classic Designer) | recaps: https://wowsod.pro/articles/wow-forever-qa-recap-september-17 , https://mein-mmo.de/en/wow-forever-beta-start-and-qa-from-september-17-in-live-ticker-when-does-it-start,1588368/ | 2026-09-17 | Modern (Midnight) addon API + combat restrictions, built-in damage meter and Cooldown Manager, swing timer "perhaps soon", single difficulty, 10/20-player raids |
| Blue-post aggregator | https://theforeverera.com/en/blue/ | rolling | Index of all Forever blue posts |
| Community bug tracker (player-run, issues labeled Fixed/Seen) | https://github.com/ClassicWoWCommunity/forever-bugs/issues | rolling | Useful for "is this proc/talent actually working" checks |

Classes with a full official write-up as of 2026-10-07: Paladin (BlizzCon), Priest,
Warrior, Hunter, Druid (deep dives). **Mage, Rogue, Shaman, Warlock: no official deep dive
yet**; their data below is datamined/community (Med/Low).

## Combat mechanic changes

### Addon / UI environment (most important for JustAC)
- **Modern Midnight addon API with Midnight in-combat restrictions (secret values).** Lead
  Software Engineer Nora Mills said Forever uses the modern API and its combat limits,
  arguing simpler encounters make the limits hurt less. All classes. Source: Sept 17 Q&A
  recaps (wowsod.pro, wowguide.net). **High** (stated live by dev; multiple recaps).
- Beta testers report `UnitHealth` returning a secret in combat, `C_Spell`/`C_Item`/`C_Traits`
  namespaces, and a missing `loadstring_untainted` breaking secure snippets (believed a bug).
  Same article claims `WOW_PROJECT_ID` reports 1; **this conflicts with our own in-client
  measurement (project 18, Interface 16001) — trust the local probe**. Source:
  https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni
  (build 1.60.1.69913, 2026-09-18). **Med/Low**.
- **Built-in damage meter and Cooldown Manager** ship; a built-in swing timer was described
  as "perhaps coming soon" (Mills, Sept 17). Some community pages say it ships; not seen
  in dev notes. **High** for meter/CDM, **Low** for swing timer.
- **Cooldown Manager rollout**: Sept 24 enabled (off by default, Options → Gameplay
  Enhancement) for Druid, Mage, Priest, Warrior, Warlock; Oct 1 added Rogue and racials and
  removed per-rank duplicate entries. Still **no spell-rank support**; known gaps: Healthstone
  cooldown, pet cooldowns, Arcane Blast, weapon imbues/poisons, mana gem (needs one cast),
  Banes/Curses after retargeting. Hunter, Paladin, Shaman not listed as supported. Source:
  dev notes + known issues. **High**.
- Assisted Combat is off in Forever (our probe; no Blizzard source mentions it). Personal
  Resource Display exists (combo points missing from it on Sept 24 build). **High** (dev notes).
- **New spell ranks do not replace old ranks on action bars**; the spellbook shows the
  highest rank with a dropdown for lower ones; pet bars do auto-update. Source:
  https://wowforeverbuilds.com/news/new-spell-ranks-dont-jump-onto-your-bars-in-wow-forever-and-casters-are-arguing
  and forum thread 2352785. **Med** — affects any spell-id matching against bar slots.
- Known issue: queueing an on-next-attack ability (Heroic Strike, Maul, Raptor Strike)
  disables the spell queue window. Implies a retail-style spell queue window exists. Known
  issues list. **High** (that it's listed), behavior may change.
- Known issue: chained casts don't play the next cast's precast effects until the first
  finishes (cosmetic). **High**.

### Stats, ranks and regen
- **One hit stat and one crit stat** for melee, ranged and spells. All classes; biggest
  winners named as Ret Paladin, Enh Shaman, taunting Warriors, Rogue poisons, Hunter traps.
  Source: BlizzCon Deep Dive (Zierhut) via outputlag. **High**.
- Weapon skill kept but spread thinner across items; a new (unnamed) stat reduces target
  dodge/parry; racial weapon passives now give spell+ability crit with that weapon type
  (e.g. Human swords). Source: wofwforever.com weapon-skill guide citing panel. **Med**.
- Bonus healing also grants one-third as spell damage; caster weapons from level 10.
  Panel. **High**.
- **Periodic effects can crit.** Dev notes explicitly enable crits on Rejuvenation,
  Tranquility, Wild Growth (Druid), Renew, Devouring Plague (Priest), Riptide (Shaman),
  Lacerating Strikes (Hunter), Hellfire (Warlock); community reports DoTs in general can
  crit (Mage, Priest, Rogue, Shaman, Warlock, Warrior). Disc Inner Focus no longer adds crit
  to periodics. Sources: dev notes Sept 24/Oct 1; wowtbc.gg "What we know". **High** for
  named spells, **Med** for "all DoTs".
- **Downranking is penalised harder than vanilla.** The Oct 1 build added a character-sheet
  tooltip saying spells far below your level get less spell damage/healing benefit **and a
  reduced chance to trigger class procs**. Exact formula unpublished. Healers/casters. Source:
  dev notes Oct 1 (UI section). **High** that the penalty exists, **Low** on any formula.
- **Five-second rule still exists, but regen is continuous** (retail engine), not 2-second
  ticks — no tick-timing of casts. Spirit formula unconfirmed; Paladins and Shamans now use
  Spirit; many healer trees add in-combat regen (Meditation-style). Source: forum thread
  https://us.forums.blizzard.com/en/wow/t/forever-mana-regen/2361435 (players, no blue).
  **Med**.
- Wands no longer scale with spell damage (Sept 24). **High**.
- Glancing blow calc is wrong for casters and vs higher-level targets (known issue). **High**.
- Enemies can parry/block from behind at very close range (known issue, Oct 1). **High**.

### Talents and baseline kits (all classes)
- Trees keep 3 × 7 rows and 51 points at 60, with a **new one-point gold talent at 16
  points** (alongside 11/21/31). First point at level 10, so **21 points at the level-30
  beta cap**. Buff-improvement filler talents removed and made baseline. Panel + lfcarry.
  **High**.
- Respec cost 1 silver during beta (resets after an hour). Sept 24 notes recap. **Med**.

### Resource and rhythm changes
- **Warrior rage rework**: rage from damage taken ignores armor and absorbs; weapon rage
  fully normalised by weapon speed; crits give extra rage — 75% (deep dive) raised to
  **100%** on Oct 1–2. Tactical Mastery baseline at 14 (keep 10 rage on stance swap).
  Warrior. Deep dive + Kaivax Oct 2. **High**.
- **Bear rage**: Bear/Dire Bear Form +75% rage on crit (Oct 1). Druid. **High**.
- **Slam no longer interrupts/resets the swing timer**, has a base cast of 1.5s and a
  cooldown (15s → 18s on Sept 24); Improved Slam (Arms row 6, 2 pts) trims cooldown by
  1.5/3s and cuts cast/GCD. Warrior. Official: cooldown numbers (dev notes) + "reduces
  cooldown and cast time" (deep dive). Swing-timer preservation: kami-labs, powerupgaming,
  wowtbc — **Med** (not stated in a Blizzard text I could find).
- Faerie Fire no longer resets the swing timer (Druid, Sept 24). **High**.
- **Combo points no longer drop when you change targets** (only when you build on a new
  target). Rogue/Druid. mobalytics Rogue overview. **Med**.
- **GCD reductions exist as talents**: Druid Nature's Grace (haste + lower GCD, 3s);
  Gift of the Earthmother (instant heals' GCD −0.5s); Improved Slam (Slam GCD). Shaman
  Lightning Bolt/Chain Lightning base cast −0.5s, Ghost Wolf 2s. Deep dive (Druid) **High**;
  Shaman **Med**.
- Arcane Missiles checks line of sight only at channel start (Sept 24). **High**.
- Mage "comprehension scrolls" cannot be cast while moving (Oct 1). **High**.
- Drain Soul is interrupted by starting another cast (Oct 1). **High**.
- Rend and Sunder Armor instantly tap enemies (Oct 1). **High**.

### Threat
- Righteous Fury holy threat bonus set to 60% (was 90%) (Sept 24). Paladin. **High**.
- Fade, Disengage, Cower threat reduction doubled; Primal Bite threat roughly doubled (Oct 1).
  **High**.
- Seal of Fury makes Judgement a 10-yard taunt (Paladin); Sunder threat scales with AP;
  Thunder Clap usable in Defensive Stance; Growl cooldown matches Taunt. **High**.
- Lightning Overload echoes generate no threat; Natural Grace now reduces threat of all
  Shaman spells; Spirit Weapons +30% threat with Rockbiter, −30% without. **Med** (datamined).
- Known issue: several debuffs (Faerie Fire, Demoralizing Shout) generate no threat. **High**.

### Proc / stacking / buff rules
- Shaman totem buffs: Flametongue Totem no longer stacks with itself, Flametongue Weapon, or
  Windfury Totem; Tranquil Air, Windfury and Grace of Air totems no longer stack even across
  Shamans. **High**.
- Paladin: Judgement no longer consumes the Seal; most judgement debuffs last 40s; 5-min
  blessings last 1 hour. **High** (seal) / **Med** (durations).
- Campsite features are mutually exclusive with matching class buffs (e.g. Fish Bowl vs
  Kings, First Aid Kit vs Fortitude, Camp Chair vs Moonkin aura). mobalytics professions.
  **Med**.
- Gnome Eureka: no longer affects periodic effects (channels excluded too) (Oct 1). **High**.

## Class change overviews

Levels are when the ability is learned/trained where a source states it. "N-pt" = talent
gated at N points in that tree. Detailed rotations are in the per-class files.

### Warrior (official: deep dive 2026-09-30; Kaivax 2026-10-02)
- New/changed baseline: Tactical Mastery (L14), **Victory Rush (L20, heals 10% max HP, usable
  shortly after a kill that grants XP/honor)**, Recklessness/Retaliation/Shield Wall no
  longer share a cooldown (Retaliation, Shield Wall 15 min), Rend gains AP scaling,
  Thunder Clap AP scaling + Defensive Stance, Battle Shout lowered, Sunder usable with
  Expose Armor and AP-scaled threat, Berserker Rage at L30 (was 32).
- Arms: **Spearing Strike** (16-pt gold, 15 rage, ~20s cd per kami-labs; bonus vs giants,
  dragonkin and mounted, dismounts; Oct 1: no 2H needed, needs Battle Stance); Bloodthrill
  (Rend targets proc Overpower, main-hand only, 4–20%); Weaponmaster (replaces weapon specs);
  Improved Slam (see mechanics).
- Fury: Raging Blows (16-pt; Whirlwind now always hits with both weapons, talent now cuts
  Cleave/WW cost by 3); Enrage triggers from any damage taken; Death Wish increases damage
  taken instead of armor loss and now gates Flurry; Bloodthirst no longer heals, gives 10%
  run speed, AP ratio 45%; Gore Drinker (row 6, next 3 swings heal 0.5/1%); Lingering
  Rage, Furious Precision new; Improved Cleave and Boundless Rage removed (Oct 1).
- Protection: Shield Specialization block = 5 rage; Master of Defense (5 rage on
  dodge/parry with shield); **Vanguard (16-pt: Charge in Defensive Stance)**; Improved Shield
  Wall big cooldown cut; Bastion, Focused Rage; Toughness removed; tree reordered for
  non-shield dips (Oct 1).
- Sources: deep dive, Kaivax Oct 2, https://kami-labs.fr/en/wow-forever/guerrier-wow-forever-sorts-et-talents-modifies/

### Paladin (official: BlizzCon changelist 2026-09-13 + dev notes)
- Baseline: **Holy Strike (L6, instant Holy weapon strike; cd 12s → 10s on Sept 24; rank
  scaling reworked)**, Consecration (L20, full damage to first 4 targets only), Blessing of
  Kings baseline (L20), Seal of Fury (tank seal: holy damage per swing + absorb shield,
  Judgement taunts at 10 yd), Judgement no longer consumes the seal, Lay on Hands 20 min,
  Divine Shield halves your damage dealt (Wrath-style), Holy Wrath stuns undead/demons.
- Holy: Holy Shock (21-pt), Light's Vigil (place on ally/enemy, Holy Shock then group-heals
  or damages + refunds mana), Divine Favor (16-pt per lfcarry), Holy Power now +15% Holy
  Strike crit; Improved Holy Strike removed.
- Protection: Improved Seal of Fury (11-pt), Swift Judgment (16-pt, recover a missed taunt),
  Templar's Bulwark (21-pt absorb); Holy Shield block 30%, Redoubt reduced (Oct 1).
- Retribution: Vengeance from non-periodic crits, max 3 stacks; Sacred Arbiter +20% Holy
  Strike and refreshes judgements; Twist of Light (seal twisting, −20% seal cost); Champion
  of the Light (Int → spell damage 20/40/60%).
- Sources: warcrafttavern, lfcarry, outputlag, dev notes.

### Priest (official: deep dive 2026-09-30)
- Baseline for all races: Fear Ward (L20), Devouring Plague (L20), **Divine Spirit (L30)**,
  **Shadow Word: Death (L32)**; Prayer of Healing heals the target's party (+pets); Fade
  threat drop doubled; Renew from multiple priests stacks; PW:S can overwrite a shield on a
  target without Weakened Soul.
- Racial spells: Gnome Confounding Flash (L10), Contingency Plan (L20, absorb ward);
  Dwarf Desperate Prayer (L10), Chastise (L20); Human Divine Grace (L10, heal <50% and
  clear Weakened Soul), Feedback; Night Elf Starshards (L10, 30s cd), Elune's Grace (L20,
  −50% hit vs you, 15s); Troll Hex of Weakness, Shadowguard; Undead Touch of Weakness,
  Dark Sacrifice (L20, health → mana).
- Discipline: Twin Disciplines, Power in Light, Soul Warding (16-pt), **Penance (21-pt, 2s
  channel, 12s cd)**, Renewed Hope, Divine Aegis; Holy Precision removes hit need for healers.
- Holy: Binding Heal (16-pt, no cd), Litany of Light (mana refund for alternating spells),
  Inspiration from any non-periodic crit heal, Searing Light free Holy Nova procs,
  **Prayer of Mending (31-pt)**; Lightwell removed.
- Shadow: Improved Mind Flay, Vampiric Embrace (16-pt, 30s, 1 min cd), Devouring Contagion,
  Early Demise (SW:D crit below 20%), Shadowform (allows non-heal spells, −50% shadow cost).

### Hunter (official: deep dive 2026-09-30)
- Baseline: **Aimed Shot at L20**, Multi-Shot now shares Aimed Shot's cooldown, Arcane Shot
  does not; Disengage threat drop doubled; Aspect of the Beast grants melee AP; **traps
  usable in combat (30s cd; Frost/Fire separate)**; Scorpid Sting reduces hit; all pets learn
  Bite or Claw; Aggressive pet mode restored (Oct 1).
- Beast Mastery: Focused Fire; **Summon Hawk (16-pt: instant damage + hawk attacks target for
  18s)**; Intimidation gives pet 100% crit; Unleashed Fury/Ferocity affect hawks.
- Marksmanship: Careful Aim (Int → AP), Lone Wolf (11-pt, +20% damage with no pet), Rapid
  Killing, Trueshot Aura (21-pt), **Sniper Shot (31-pt, 4s cast, 15s cd, 45 yd)**.
- Survival: Predator's Edge, Expose Prey (Mongoose Bite on marked targets), Counterattack
  (16-pt), **Strider Kick (21-pt, +30% run speed 3s)**, Lacerating Strikes (31-pt bleed, can
  crit); Deflection parry lowered (Oct 1).

### Druid (official: deep dive 2026-09-30)
- Baseline: Nature's Grasp (L10, usable shifted/indoors), Revive (L12, OOC rez), **Omen of
  Clarity (L20)**, Lacerate (L42, bleed, high threat); Barkskin usable shifted; Hurricane no
  cd; Faerie Fire usable in forms (6s cd, free); Thorns scales with spell power; Wrath much
  cheaper and weaker (then +~50% base on Sept 24).
- **Shapeshift rules: potions, weapon enchants/procs, doors, and racials work in form
  without cancelling it**; form auto-attack DPS equals the equipped weapon; forms immune
  to Disarm (Oct 1). Tiger's Fury removed (Oct 1).
- Balance: Genesis, Nature's Majesty, Nature's Splendor (11-pt), **Insect Swarm (16-pt)**,
  Eclipse (Wrath shortens next Starfires), Overgrowth; Moonkin allows non-heal spells.
- Feral: **Primal Bite (16-pt, Mangle renamed; 20 rage, very high threat)**, **Shifting Power
  (Oct 1 moved to row 4: Cat only, 16s cd, mana → 40 energy)**, Improved Shifting Power,
  Natural Reaction, Rend and Tear, Berserk (31-pt).
- Restoration: Gift of the Earthmother (11-pt, instant heal GCD −0.5s), **Swiftmend (16-pt,
  no longer consumes the HoT)**, Living Spirit, **Wild Growth (31-pt, 6s cd)**.

### Mage (no official deep dive; datamined/community)
- Arcane Blast (stacking: +damage to other spells, rising cost, 4 stacks) and Missile
  Barrage proc; Arcane Intellect 60 min; Teleport: Dalaran (L50).
- Fire: Frostfire Bolt (trained; hits weaker of fire/frost resist); Hot Streak stacks cut
  Pyroblast cast 25% each (renamed **Heating Up** Oct 1, buff 20s); Wake of Fire (Fire Blast
  cd/crit); Combustion charges 3 (was 4 in beta, returned to 3 Oct 1); Ignite no longer
  double-dips.
- Frost: Ice Lance (frozen bonus), Fingers of Frost; Ice Block 5 min cd; Winter's Chill
  never resisted (Oct 1).
- Sources: https://kami-labs.fr/en/wow-forever/mage-wow-forever-sorts-et-talents-modifies/
  (2026-09-26), icy-veins all-class page, dev notes. **Med**.

### Rogue (no official deep dive)
- No new baseline abilities found; combo points persist across target swaps; one-handed
  axes usable.
- Assassination: **Mutilate** (2 CP), **Venom** finisher (poison damage/apply chance); Vigor
  moved down, Improved Gouge moved in.
- Combat: Hack and Slash (replaces weapon specs; axes/swords extra attack, daggers/fists
  crit, maces armor pen), Flawless Execution, Puncturing Wounds.
- Subtlety: Dirty Tricks, Improved Distract, Quietus, Cutthroat (Ambush without stealth
  proc), Thousand Cuts (capstone); Premeditation moved earlier.
- Sources: https://mobalytics.gg/wow-forever/guides/rogue-class-overview (2026-09-18),
  https://foreverchanges.pro/class/rogue (build 70245). **Med**.

### Shaman (no official deep dive)
- Baseline: Totemic Projection, Totemic Recall (25% mana refund), Call of the Elements
  (+ two variants), Fire Nova now instant, detonates from an active fire totem; Lightning
  Bolt/Chain Lightning casts −0.5s; Lightning Bolt ranks 3–4 buffed (Sept 24).
- Elemental: Lightning Overload, Earthbound, **Lava Burst** (+20% with Flame Shock; ranks 1–2
  buffed Oct 1), Call of Flame/Eye of the Storm reworked.
- Enhancement: Mental Dexterity/Quickness (Int → AP/SP), Maelstrom Weapon (stacks to 5, Bolt
  cast/cost), Stormstrike moved to row 4 (+20% nature taken 12s), Improved Stormstrike,
  Rage of the Farseer (30% haste 25s; no longer spell haste Sept 24), Spirit Weapons
  (Rockbiter tanking).
- Restoration: Mindfulness, **Water Shield**, **Riptide** (capstone, can crit, +25% Chain Heal
  on target), Natural Grace, Tidal Focus +hit, Healing Way flat +Healing Wave.
- Sources: https://mobalytics.gg/wow-forever/guides/shaman-class-overview (2026-09-18),
  https://foreverchanges.pro/class/shaman. **Med**.

### Warlock (no official deep dive)
- Curse of Agony/Doom renamed **Bane of Agony/Doom** (separate category from curses);
  Incubus separate from Succubus; Portal of Summoning; periodic damage can crit.
- Affliction: Wrack, Malediction, Malevolence, Pandemic (DoT/drain crit damage), Improved
  Drains, Soul Siphon, Soul Harvest (mana regen while casting after Drain Soul kill).
- Demonology: Decimation (Soul Fire procs), Demonic Aegis, Demonic Brand, Demonic Energies,
  Demonic Knowledge, Demonic Pact (sacrifice persists across another summon), Fel Vitality,
  Improved Felhunter.
- Destruction: Agonizing Flames, **Bane of Havoc**, Fire and Brimstone, Shadow and Flame,
  Molten Skin, **Incinerate (31-pt capstone)**; Hellfire can crit (Oct 1).
- Sources: https://mobalytics.gg/wow-forever/guides/warlock-class-overview (2026-09-18),
  https://foreverchanges.pro/class/warlock. **Med**.

### Racials that act like cooldowns (all classes)
Gnome **Eureka!** (next 3 spells cheaper + 10% stronger; not periodics), Orc Blood Fury
(10% AP and spell power, 15s, 2 min, no healing debuff) and **Shatter Curse** (curse/bane
immunity + magic DR, 8s), Troll Berserking (flat 10% haste 10s) and **Rapid Regeneration**
(50% HP over time), Night Elf Elune's Light (+10% crit 15s), Undead Touch of the Grave,
Will of the Forsaken (no lingering immunity), Human Will to Survive (stun break), Dwarf
Stoneform, Skyborne Walk on Air / Read Ley Line (Alliance, regen) / Skysight (Horde, speed).
Source: mobalytics Rogue/Warlock/Shaman overviews. **Med**.

## Healing references

- No class-neutral Blizzard healing primer exists. Healing-relevant system facts:
  HoTs crit (Rejuv, Renew, Riptide, Wild Growth, Tranquility — Sept 24 notes); PW:S overwrite
  rule; Prayer of Healing heals the target's party; Renew stacks across priests; downranking
  penalty on both spell power and proc chance; continuous mana regen; Paladin/Shaman use Spirit.
- Design summary across the five healers ("anchor" spell + follow-up), 2026-09: Holy Paladin
  (Light's Vigil + Holy Shock, weakest mana), Disc (PW:S, Penance), Holy Priest (Prayer of
  Mending + Litany of Light), Resto Druid (Rejuv, Swiftmend, Wild Growth, GCD talent), Resto
  Shaman (Riptide → Chain Heal, Water Shield). Source:
  https://www.mmoexp.com/News/wow-forever-healer-guide-all-five-specs-compared.html — **Low**
  (third-party summary; some numbers unverified; Wild Growth/PoM are 31-pt, not reachable at 30).
- Per-spec healer guides (beta, level 30 focus): Icy Veins Resto Druid
  https://www.icy-veins.com/wow-forever/restoration-druid-healer-pve-guide , Holy Priest
  https://www.icy-veins.com/wow-forever/holy-priest-healer-pve-guide , Disc Priest
  https://www.icy-veins.com/wow-forever/discipline-priest-healer-pve-guide ; Mobalytics Holy
  Priest https://mobalytics.gg/wow-forever/classes/holy-priest-guide , Resto Druid and Resto
  Shaman guides under https://mobalytics.gg/wow-forever/classes/ ; wow.gg overviews
  (https://wow.gg/guides/paladin-holy-forever-overview and siblings). Common level-30 advice:
  keep a HoT on the tank, use Prayer of Healing (L30) when the party is hurt, Flash of
  Light for steady damage / Holy Light for big gaps / Holy Shock as emergency, use lower
  ranks to stretch mana.
- Healer tier lists (beta, no logs): S = Resto Shaman, Holy Priest; A = Disc, Resto Druid;
  B = Holy Paladin (https://epiccarry.com/blogs/?p=41553 ,
  https://www.mmoexp.com/News/wow-forever-best-healer-tier-list-2026-top-healing-classes-for-raids-dungeons-pve.html).
  Other lists put Disc/Holy Paladin on top. **Low**.
- Healing-adjacent bug notes: Mana Tide Totem not restoring mana (fixed), Rejuvenation not
  stacking (fixed), weaker PW:S still triggering Weakened Soul (fixed), combat-log healing
  numbers differ between healer and target in dungeons (open). Source: ClassicWoWCommunity/forever-bugs.

## Defensives and consumables

### Consumables
- **Healing Potions are crafted by First Aid**, not Alchemy (Minor at FA 55 … Major at 275;
  Greater/Superior/Major from manuals; reagents now include cooking spices). Expect every
  class to carry potions while levelling. https://www.icy-veins.com/wow-forever/news/healing-potions-now-crafted-by-first-aid-in-wow-forever/ — **Med** (datamined, BlizzCon demo).
- Bandages heal more; First Aid campsite "Toxin Study"/"Plague Doctor's Laboratory" dispense
  healing potions and anti-venom. mobalytics professions (2026-09-18). **Med**.
- **Alchemy (29 new recipes, BlizzCon demo)**: 30-second combat potions — Frenzy, Mender's,
  Spellblasting (+ Major versions), Potion of Elemental Siphoning (elementals only);
  DoT potions (Dragonfire, Venomous Blood); thrown AoE potions (Caustic Smog, Disorienting
  Smog); 30-minute elixirs (Greater Fortitude, Phalanx, Wicked Regeneration, Mageblood,
  Cleric's, Arcane, Nature Power, stat elixirs). Reported: **combat potions share a 2-minute
  cooldown; Healthstone does not share it**. Mixology: elixirs/flasks +100% duration, +25%
  effect; Philosopher's Stone upgradeable trinket. Sources:
  https://www.warcrafttavern.com/forever/news/new-alchemy-recipes-for-world-of-warcraft-forever/ (2026-09-15),
  https://wow.gg/guides/wow-forever-new-recipes-alchemy . Cooldown claims **Low/Med**.
- Druids can drink potions in form without leaving it (deep dive). **High**.
- Healthstone cooldown is not trackable in the Cooldown Manager yet (known issue). **High**.
- Legacy perk: food buff duration +33%; campsite features replace some class buffs.
  Mixology and campsite buff exclusivity means "missing buff" checks should treat campsite
  equivalents as satisfying the buff. **Med**.
- Wizard oils restored (Minor 8, Lesser 16, normal 24 spell power; Sept 24). **High**.

### Defensive kit changes worth an addon "suggest defensive" rule
- Warrior: Shield Wall and Retaliation 15 min each, independent of Recklessness; Victory Rush
  10% heal after a kill; Gore Drinker self-heal procs; Death Wish now raises damage taken
  (don't treat it as a defensive); Last Stand bug (kept HP% instead of full bonus) fixed.
- Paladin: Lay on Hands 20 min; Divine Shield halves damage dealt; Seal of Fury absorb shield
  on hit (bug: PW:S overrode it, fixed); Templar's Bulwark absorb.
- Priest: Contingency Plan (Gnome ward), Elune's Grace (NE), Desperate Prayer (Dwarf), Divine
  Grace (Human), Dark Sacrifice (Undead), Fade threat doubled; Disc Divine Aegis.
- Druid: Barkskin and Frenzied Regeneration (now 100% max HP over its duration) usable in form;
  Natural Reaction dodge.
- Hunter: Disengage threat doubled, traps in combat, Deterrence cd talent, Aspect of the Monkey
  doubled dodge; Feign Death hit talent.
- Mage: Ice Block 5 min with Cold Snap reset; Mana Shield/Mage Armor talents.
- Warlock: Molten Skin (−10% damage taken), Demonic Aegis, Voidwalker Sacrifice scales with
  healing.
- Shaman: Improved Ghost Wolf instant/indoors; Earthbound root; Spirit Weapons parry.
- Rogue: no new defensive buttons found; Human/Gnome/Dwarf racials matter.

## Simulators and theorycraft

| Resource | What | Publishes rotations? | Format | License |
|---|---|---|---|---|
| ElliotWood/Forever — https://github.com/ElliotWood/Forever | Fork of `wowsims/classic` retargeted to Forever (pushed 2026-10-07) | **Yes**: 49 APL files under `ui/specs/<class>/<spec>/apls/*.apl.json`, incl. Forever-specific ones (`forever_mutilate`, `forever_hemorrhage`, shaman `forever*.apl.json`, `fire_lowrank`, `smite_lowrank`, `default_lowrank` Balance, Warrior `dps_battle`/`dps_dance`/`dps_reck`, Prot Paladin, Prot Warrior, Feral cat/bear) | wowsims APL JSON (`priorityList` of `{action, condition}` with `spellId` + `rank` ids, `auraIsActive`, `auraNumStacks`, `cmp`) — machine-readable | MIT |
| MythicSim engine (Go) — https://github.com/sage3648/mythicsim-forever-engine-go | Maintained fork of ElliotWood/Forever powering mythicsim.com | Inherits the same APLs | same | MIT |
| MythicSim engine (Rust, experimental) — https://github.com/sage3648/mythicsim-forever-engine | Rewrite validated against the Go engine; rotations live in prepared fixture files | Yes, inside `fixtures/` prepared inputs | "prepared v2" fixture files | MIT (upstream notices kept) |
| MythicSim site — https://mythicsim.com/wow-forever | Quick Sim (paste from the "MythicSim – Forever Sim Exporter" addon on CurseForge), DPS tier list, trinkets, races, per-class change pages, audit log | Not shown on the site; fixed rotations per spec | web | n/a |
| bottlefedchaney808/wow4_sims — https://github.com/bottlefedchaney808/wow4_sims | Another wowsims fork (DPS/HPS), 33 APL files, last push 2026-09-28 | Yes | wowsims APL JSON | none declared (treat as all rights reserved) |
| ForeverDB — https://foreverdb.net/ | Client-datamined DB (≈31.7k spells, 22.1k items), talents, `/datamine` diff vs Classic, own sim | Not as data | web | site terms; "not affiliated" |
| ForeverChanges — https://foreverchanges.pro/ | Per-class diff vs Classic Era from client builds 1.60.1.70245 vs 1.15.9.69722; downrank calculator | No | web | site terms |
| woweternity.com/forever/spells | Spell DB + downrank calculator | No | web | site terms |
| SimulationCraft | No Forever support (never supported Classic clients, per MythicSim) | — | — | — |

Caveats: MythicSim sims level 60 vs a level-63 boss with BlizzCon-demo-era data; talents and
racials partly unverified; its displayed talent splits (e.g. 18/31/28) don't sum to 51 —
treat as provisional. Many APLs in the forks are inherited Classic/SoD lists (e.g. Sunder
Armor rank 5 id 11597, "sweaty"/"ghostly" variants) and are level-60 oriented; only the
`forever_*`/`lowrank` ones were clearly authored for Forever. None target the level-30 cap.

## Builds that exist at the beta cap

Beta cap was 20 until 2026-10-01, now **30 through beta end (≈2026-10-21)**; dungeons up to
Excavation Site: Wetlands (26–31), Razorfen Downs (25+), Uldaman (30+). **21 talent points**
at 30 → 11-, 16- and 21-point gold talents are reachable, **31-point capstones are not**.

Reachable at 30 (per tree): Arms Spearing Strike; Fury Raging Blows; Prot Vanguard; Holy
Paladin Divine Favor + Holy Shock; Prot Paladin Improved Seal of Fury/Swift Judgment/
Templar's Bulwark; Disc Soul Warding + Penance; Holy Priest Binding Heal; Shadow Vampiric
Embrace; BM Summon Hawk; MM Lone Wolf + Trueshot Aura; SV Counterattack + Strider Kick;
Balance Insect Swarm; Feral Primal Bite + Shifting Power; Resto Druid Gift of the Earthmother
+ Swiftmend. **Not reachable** at 30: Sniper Shot, Lacerating Strikes, Wild Growth, Prayer
of Mending, Berserk, Incinerate, Thousand Cuts/Venom-tier capstones, Riptide (capstone).
Baseline gates: Divine Spirit L30, Berserker Rage L30, Shadow Word: Death L32, Lacerate L42,
Teleport: Dalaran L50 — the last three are not in beta.

Builds named by guides at level 30 (all 21/0/0-style single-tree):
- Mobalytics levelling picks: Feral, BM, Frost Mage, Ret, Shadow, Combat, Enhancement
  (0/11/0 at time of writing), Affliction, Arms; levelling tier S = Paladin, Hunter;
  A = Warlock, Mage, Shaman; B = Rogue, Priest; C = Warrior, Druid (1–20 basis).
  https://mobalytics.gg/wow-forever/tier-list
- Guides updated Oct 1–6: Affliction 21/0/0, Destruction 0/0/21, BM 21/0/0, Ret 0/0/21,
  Elemental 21/0/0, Fury 0/21/0, Prot Warrior 0/0/20; Disc 21/0/0 dungeon build (Twin
  Disciplines, Imp PW:S, Soul Warding, Penance) per leprestore; Holy Paladin 21/0/0 with
  Holy Shock.
- Tank options seen in guides: Prot Warrior, Prot Paladin, Feral bear; Enhancement
  "Rockbiter" tank is niche.

## Sources not usable

| Source | Reason |
|---|---|
| wowhead.com/forever (guides, DB, talent calc) | WebFetch 403; browser got a CloudFront "request could not be satisfied" error. Only reachable via the blue-tracker mirror URL above |
| icy-veins.com/wow-forever | WebFetch 403; readable in the browser (used for the class page, potions news) |
| mobalytics.gg/wow-forever | WebFetch 403; readable in the browser (used for Rogue/Shaman/Warlock/professions/tier list) |
| method.gg/wow-forever | Only levelling guides + talent calc listed; no class-change or healing content found; hit-chance page 404 |
| news.blizzard.com feed page | Feed is JS-rendered; article list not extractable. Individual articles fetch fine |
| Paladin first-party article | No first-party URL located; only community recaps of the BlizzCon changelist |
| world-of-warcraft-forever.wiki | Fan wiki with thin, partly wrong content (says eight classes); not relied on |
| kami-labs.fr Rogue/Shaman/Warlock pages | Guessed URLs 404; Mage/Warrior pages used |
| Forum threads on downranking/regen (2352785, 2361435) | Player-only, no blue replies; used for player-observed behavior only, marked Med/Low |
| wowsod.pro / wowguide.net / wofwforever.com / lfcarry.com / mmoexp.com etc. | Usable as recaps only; some carry factual slips (e.g. stale Combustion charges, Holy Strike cd); cross-checked against dev notes where possible |
| warcraft.wiki.gg | BlizzCon 2026 page lists Forever panels but no mechanics detail |
| SimulationCraft | No Forever (or any Classic) support |
