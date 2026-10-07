# Druid and Shaman - WoW Forever guide references

researched 2026-10-07 (beta is capped at level 30; launch 2026-11-04). All priorities below
are paraphrased summaries, not guide text. "L30" = written for the level-30 beta stage.

## Read this first - official changes that invalidate older guides

Source: Blizzard "WoW Forever Beta Development Notes" thread
(us.forums.blizzard.com/en/wow/t/2360696, updates 2026-09-24 and 2026-10-01).

- **Oct 1: Tiger's Fury is REMOVED** (and the King of the Jungle talent with it). Replaced by the
  Feral talent **Shifting Power**: Cat Form only, 16 s cooldown, spends a chunk of base mana and
  instantly grants 40 Energy. **Improved Shifting Power** cuts the cooldown by 4/8 s (to 8 s).
  Any guide that still lists Tiger's Fury (wowtbc search snippets, Wowhead L30 tank page's cat
  section, Mobalytics/Wowhead overview pages, wow.gg) predates this.
- **Sep 24: Mangle renamed Primal Bite**, its debuff removed; all Mangle-referencing talents now
  say Primal Bite. Oct 1: Primal Bite threat roughly doubled.
- Sep 24: the old Primal Fury talent was renamed back to **Blood Frenzy** (cat crits on combo
  generators can add an extra combo point).
- Oct 1: Bear/Dire Bear gain 75% more Rage from landing crits; Swipe now scales with 3% AP
  (was bugged); all forms immune to Disarm; Faerie Fire no longer resets the swing timer.
- Sep 24: Wrath base damage +~50%; Rejuvenation, Tranquility, Wild Growth can now crit;
  Thorns scales with the caster's spell power.
- Shaman Sep 24: Lightning Bolt ranks 3-4 buffed so every rank is an upgrade; Lava Burst
  ranks 1-2 ~10% above comparable Lightning Bolt; Rage of the Farseer no longer adds cast
  speed (melee haste only); Riptide can crit; Tranquil Air / Windfury / Grace of Air totems do
  not stack even from different shamans; Flametongue Totem has no duration and is replaced
  instantly. Oct 1: Totemic Recall mana refund fixed; Disease Cleansing Totem 5 min duration.
- Developer podcast (summarised by Icy Veins news, ~Sep 24): powershifting removed on purpose;
  **totem twisting removed**; Maelstrom Weapon exists to make Enhancement weave Lightning Bolt.
- System: spells cast at ranks far below your level get reduced spell-power benefit
  (downranking penalty is shown in the character sheet). Several guides say exact downranking
  rules are still unknown.

Cross-class Forever mechanics relevant to a suggestion engine (Mobalytics druid leveling,
Wowhead feral pages): mana and energy regenerate continuously, not in 2 s ticks; **combo points
transfer between targets**; form attacks scale with weapon DPS; consumables usable in forms.

---

## Druid - Balance

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Wowhead | wowhead.com/forever/guide/classes/druid/balance/level-30-dps-overview | L30 rotation + builds | patch 1.60.1, L30 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/druid/balance/overview-pve-dps | endgame overview + expected rotation | undated, beta | OK (browser) |
| Icy Veins | icy-veins.com/wow-forever/balance-druid-ranged-dps-pve-guide | L30 beta guide | 2026-09-18 (written for L20) | OK (browser; 403 to WebFetch) |
| Mobalytics | mobalytics.gg/wow-forever/classes/balance-druid-guide | L30 + expected L60 talents | 2026-09-22 | OK (browser) |
| Mobalytics | mobalytics.gg/wow-forever/guides/druid-class-overview | class change list | 2026-09-18 | OK (browser) |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/balance-druid/ | short priority list | undated, "L30 beta" | OK (WebFetch) |
| Warcraft Tavern | warcrafttavern.com/forever/guides/druid/ | class change summary | "Oct 2026" | OK (WebFetch) |
| Method | method.gg/wow-forever/wow-forever-druid-leveling-guide-and-talents | leveling | 2026-09-29 | OK (WebFetch) |

**Rotation (single target)** - endgame expectation (Wowhead overview, wowtbc agree)
1. Moonkin Form up (when talented; level not in beta reach).
2. Pre-cast Wrath before combat.
3. Keep Moonfire and Insect Swarm ticking on the target.
4. Starfire as the main nuke, with Wrath interleaved to feed Eclipse.
5. Nature's Grace proc -> spend on a Starfire.
6. While moving: instant Moonfire (down-ranked) or Insect Swarm.

L30 hard-cast cycle (Wowhead L30): open Wrath -> Entangling Roots to keep the mob at range ->
Starfire x2 -> Wrath -> Starfire x2 -> repeat. If roots break, cancel and re-root before the
next Starfire (pushback costs more than the recast).
L30 DoT style (Wowhead L30): Insect Swarm -> Moonfire -> spread both to extra mobs ->
Rejuvenation on self -> let mobs hit you (Thorns cleave), melee between refreshes.
Icy Veins (written for L20): Moonfire on everything, Wrath filler, add Insect Swarm after
Moonfire from 25.

Disagreements: Mobalytics says opener can be Starfire or Wrath and notes that pure Wrath spam
is a valid mana-saving alternative; Wowhead/wowtbc make Starfire primary under Eclipse.
Wowhead says Starfire is weaker than Wrath until Eclipse is talented.

**AoE**
- 2-4 targets: Moonfire + Insect Swarm on two targets, then normal rotation (Wowhead).
- 5+ targets: Hurricane (learned at 40 per Icy Veins; not in beta).
- Leveling alternative "Spellbear" (Wowhead L30, recommended): Moonfire 3-4 mobs, HoT self,
  Bear Form, Demoralizing Roar, Swipe spam, Enrage for rage at pull start.

**Upkeep**: Mark of the Wild, Thorns (now spell-power scaled, a large share of leveling damage),
Moonfire + Insect Swarm, Moonkin Form, Faerie Fire on bosses (baseline for all druids).

**Defensives**: Barkskin (baseline; physical DR, no spell pushback), Entangling Roots to stop
melee pushback, Bear Form for emergencies, Rejuvenation/Regrowth self-heals. No interrupt.

**Forever-specific changes**
- **Eclipse** (talent, 3 ranks, reachable by L30): each Wrath shortens the cast of the next two
  Starfires; stores up to 4 charges, 15 s. Defines a 1 Wrath : 2 Starfire cadence.
- **Omen of Clarity** baseline (learned 20 per Wowhead feral page), procs from spells, stronger
  in Moonkin Form.
- **Insect Swarm** moved into the Balance tree (talent ~25).
- **Nature's Splendor**: Moonfire +3 s, Insect Swarm +2 s, Rejuvenation +3 s, Regrowth +6 s.
- Improved Wrath also halves Wrath mana cost; Moonglow earlier; Nature's Reach adds hit;
  Vengeance covers all Arcane/Nature crits; Genesis (+periodic dmg/heal); Nature's Majesty
  (+crit); Overgrowth (multi-target Entangling Roots, castable indoors).
- Nature's Grace (per Wowhead resto page) is now 10% haste + GCD reduction for 3 s.
- Moonkin aura is a general party crit buff, mutually exclusive with Leader of the Pack.
- Spells learned 21-30 (Wowhead): Remove Curse 24, Abolish Poison 26, Tranquility 30.

**Gaps**: no source has a level-60 tested priority; Eclipse charge cap interaction with
Starfire cast count untested; Moonkin Form level unknown; Hurricane thresholds speculative.

---

## Druid - Feral (cat DPS)

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Wowhead | wowhead.com/forever/guide/classes/druid/feral/level-30-dps-overview | L30 rotation | 2026-10-06, patch 1.60.1 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/druid/feral/overview-pve-dps | change list | pre-Oct 1 (still lists Tiger's Fury) | OK (browser) |
| Icy Veins | icy-veins.com/wow-forever/feral-druid-melee-dps-and-tank-pve-guide | L30 cat + bear | 2026-10-04 | OK (browser) |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/feral-dps-druid/ | short priority | undated; page now shows Shifting Power | OK (WebFetch) |
| Mobalytics | mobalytics.gg/wow-forever/classes/feral-druid-guide | talents + bear-centric leveling | 2026-09-26 | OK (browser; cat variant text not separate) |
| Mobalytics | mobalytics.gg/wow-forever/classes/druid-leveling-guide | leveling 1-30 | 2026-09-29 | OK (browser) |
| Method | method.gg/wow-forever/wow-forever-druid-leveling-guide-and-talents | leveling | 2026-09-29 | OK |
| wow.gg | wow.gg/guides/druid-feral-combat-forever-overview | talent descriptions | 2026-09-19 (stale) | OK |
| Warcraft Tavern | warcrafttavern.com/forever/guides/druid/ | change summary | Oct 2026 | OK |

**Rotation (single target)** - Wowhead L30 (newest, post-Oct 1), consistent with Icy Veins
1. Shifting Power on cooldown, only when it will not overcap Energy (Wowhead: below ~50;
   Icy Veins and wowtbc: below 60) and no Clearcasting is active.
2. Rip at 4-5 combo points if target lives >= ~6 s and Rip is not already on it (prefer 5).
3. Rake if target lives >= ~6 s and Rake is not already on it.
4. Faerie Fire if missing and it won't waste Energy (6 s cooldown when cast in form).
5. Shred (from behind) as the main builder; spend Clearcasting on Shred.
6. Claw when you cannot get behind.
7. Faerie Fire as a filler to fish for Clearcasting procs.
Endgame additions (wowtbc): Berserk with on-use effects near the top; Ferocious Bite only if it
won't delay Rip; keep Faerie Fire (Feral) up.

Opener: pool Energy in Cat Form, Prowl, open with Shred from behind (Mobalytics/Method);
Ravage and Pounce exist as stealth openers (Wowhead abilities).

Disagreements: Icy Veins says Rake is low value vs Shred at L30 and Rip only when target lives;
Wowhead dungeon tip says Rake early and rarely Rip on short-lived dungeon mobs. Mobalytics
leveling uses Claw spam + Ferocious Bite, Rip only if target lives >= 10 s.

**AoE**: effectively none at L30 (Wowhead): Rake multiple targets, or Thorns on the tank;
Berserk at endgame. Swap to Bear for Swipe if real AoE is needed.

**Upkeep**: Cat Form, Mark of the Wild, Thorns, Rip, Rake, Faerie Fire debuff, Leader of the
Pack (crit aura, L30 talent, exclusive with Moonkin aura).

**Defensives**: Barkskin (baseline; Wowhead flags castable in forms as unconfirmed), Bear Form
swap, Nature's Grasp (baseline at 10, castable in forms), Entangling Roots, shift to cast heals,
Dash, Cower. Shifting out of form clears Polymorph and movement impairment.

**Forever-specific changes**
- Powershifting removed: **Furor** now restores the Energy you had when last in Cat Form
  (wow.gg adds +10/s while out of form, capped) instead of a flat 40.
- **Tiger's Fury removed Oct 1** -> **Shifting Power** (talent, ~L20-25 row 4; mana for 40
  Energy, 16 s, Improved version down to 8 s).
- **Berserk** (31-pt capstone): 15 s, +100% crit on combo generators in cat, clears/immunes Fear.
- **Blood Frenzy** extra combo point on crit; **Rend and Tear** (+dmg vs bleeding targets),
  **Predatory Instincts** (+crit dmg).
- **Feral Charge (Cat)**: leap behind target and daze; shares cooldown with bear charge.
- Combo points carry across targets; energy regen continuous; Omen of Clarity baseline (20).
- Polearms usable; form damage scales with weapon DPS.
- Form levels (Method/Icy): Bear 10 (quest), Cat 20 (quest), Travel 30 (trainer), Dire Bear 40.

**Gaps**: no tested Berserk sequencing; Ferocious Bite energy-dump threshold unspecified in
Forever; Rip/Rake durations under Forever talents not stated; no source handles Shifting Power
vs mana for heals trade-off at endgame.

---

## Druid - Feral (bear tank)

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Wowhead | wowhead.com/forever/guide/classes/druid/feral/level-30-tank-overview | L30 bear + cat | patch 1.60.1, L30 (cat half pre-Oct 1) | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/druid/feral/tank-abilities | ability list | beta | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/druid/feral/overview-pve-tank | change list | beta | OK (browser) |
| Icy Veins | (same feral page as above) | L30 bear section | 2026-10-04 | OK |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/feral-tank-druid/ | endgame priority list | undated, L30 beta | OK |
| Mobalytics | mobalytics.gg/wow-forever/classes/feral-druid-guide | bear leveling/tanking tips | 2026-09-26 | OK |
| kami-labs | kami-labs.fr/en/wow-forever/build-druide-gardien-wow-forever/ | pre-beta talent analysis | 2026-09-16 | OK (speculative) |

**Rotation (single target)** - wowtbc endgame list
1. Dire Bear Form.
2. Frenzied Regeneration as the emergency defensive.
3. Berserk with on-use effects.
4. Build and hold 5 stacks of Lacerate.
5. Faerie Fire debuff up.
6. Demoralizing Roar up.
7. Maul with excess Rage (off-GCD next-swing).
8. Primal Bite on cooldown.
9. Lacerate if under 5 stacks.
10. Swipe as filler.

L30 (Wowhead): pre-pull Faerie Fire to pull; keep Demoralizing Roar on tanked mobs; Primal Bite
whenever ready; Swipe vs multiple; Maul as the single-target rage spender.
Icy Veins L30: Primal Bite is the main spender, Swipe vs packs, Maul only to burn excess Rage
(it costs more than listed because it replaces a swing); spend Omen of Clarity on Primal Bite,
else Swipe (AoE) or Maul (ST). Enrage = 30 Rage over 10 s, 1 min cd, lowers armor.
Mobalytics: Enrage at pull start, then Swipe for threat; Growl to taunt.

**AoE**: Enrage -> Demoralizing Roar -> Swipe spam (3 targets); Berserk lets Primal Bite hit 3
targets with no cooldown for 15 s; Challenging Roar as an AoE taunt.

**Upkeep**: Dire/Bear Form, Lacerate x5 (endgame), Demoralizing Roar, Faerie Fire, Thorns on
self, Mark of the Wild.

**Defensives / tanking**: Frenzied Regeneration (rage -> health over 10 s; now described as a
real cooldown), Barkskin (20% physical DR, 15 s), Natural Reaction (dodge + rage on dodge),
Demoralizing Roar, Bash (Brutal Impact also cuts its cooldown), Growl, Challenging Roar,
Feral Charge. Leave form only to heal; Nature's Grasp/Roots to escape.

**Forever-specific changes**
- **Primal Bite** (ex-Mangle, talent ~25 per Wowhead), threat doubled Oct 1.
- **Lacerate**: stacking bleed, 5 stacks, high threat; Wowhead says it is far beyond L30.
- **Berserk** bear mode: Primal Bite no cooldown + 3 targets, Fear immunity.
- Bear crits give +75% Rage (Oct 1); Swipe scales with AP (Oct 1); forms Disarm-immune.
- Faerie Fire baseline, merged with the feral version, 6 s cd in form, no swing reset.
- Defense skill now adds base armor per level (wow.gg); Thick Hide reworked (kami-labs).
- Furor still gives rage on bear shift.

**Gaps**: Lacerate and Dire Bear levels for the live game not confirmed; no threat numbers;
Frenzied Regeneration rage cost/conversion not stated; Maul vs Primal Bite rage priority at
endgame untested.

---

## Druid - Restoration

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Wowhead | wowhead.com/forever/guide/classes/druid/restoration/level-30-healer-overview | L30 healing rotation | patch 1.60.1, L30 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/druid/restoration/overview-pve-healer | change list (detailed) | beta | OK (browser) |
| Icy Veins | icy-veins.com/wow-forever/restoration-druid-healer-pve-guide | L20/30 healer | 2026-09-18 | OK (browser; FAQ collapsed, not read) |
| Mobalytics | mobalytics.gg/wow-forever/classes/restoration-druid-guide | L30 talents + healing | 2026-09-22 | OK (browser) |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/restoration-druid/ | endgame priority list | undated | OK |
| Warcraft Tavern | warcrafttavern.com/forever/guides/druid/ | change summary | Oct 2026 | OK |

**Healing priorities** - wowtbc endgame list
1. Nature's Swiftness + Healing Touch for an instant emergency heal.
2. Tranquility for party-wide emergencies.
3. Wild Growth for party AoE healing.
4. Swiftmend for instant single-target.
5. Rejuvenation on many targets during heavy raid damage.
6. Rejuvenation + Regrowth kept on tanks.
7. Regrowth or Healing Touch for routine single-target.

L30 (Wowhead): Thorns on tank -> Rejuvenation on tank and anyone about to take damage -> idle
to regen or DPS -> needs direct heal: Regrowth first (gets HoT up), then low-rank Healing Touch
-> life in danger: Swiftmend (Rejuvenation then Swiftmend is a ~1 s save even with no HoT up)
-> Swiftmend on cd: Nature's Swiftness + max-rank Healing Touch -> party-wide disaster:
Tranquility. Spend Omen of Clarity on max-rank Regrowth or Healing Touch.
Mobalytics: Regrowth + Rejuvenation on tank; NS + Healing Touch then Swiftmend as a burst
combo; keep a low-rank Healing Touch bound.

**Downranking / mana**: all three guides say downrank Healing Touch (and HoTs) to fit damage;
Reflection now lets 50% of regen continue while casting; Living Spirit adds Spirit; Innervate.
Note the official penalty for very-low ranks (see top).

**Upkeep**: Rejuvenation on tank (+ Regrowth), Thorns on tank, Mark of the Wild; at endgame
Rejuvenation blankets enabled by Gift of the Earthmother.

**Defensives**: Barkskin (also stops pushback, pair with Tranquility channel), Bear Form,
Nature's Grasp, Entangling Roots; Rebirth (combat res) and new Revive (out of combat).

**Forever-specific changes**
- **Wild Growth** (talent, capstone tier): instant, 6 s cd, HoT on the target's party only.
- **Swiftmend** moved early (reachable at L30); heals for the full value of the strongest HoT
  and **no longer consumes it**.
- **Gift of the Earthmother** (L20 talent): Rejuvenation / Swiftmend / Wild Growth on 1.0 s GCD.
- HoTs (Rejuvenation, Regrowth, Tranquility, Wild Growth) can crit; Regrowth much cheaper.
- Nature's Splendor extends HoTs (Rejuv +3 s, Regrowth +6 s) - synergy with Swiftmend.
- Improved Tranquility reduces its cooldown (to 2 min) and threat; Tranquility trained at 30.
- Nature's Grace = 3 s haste/GCD window; Moonglow now damage-spells only.
- Missing vs later games: Lifebloom, Nourish, Efflorescence, Tree of Life.

**Gaps**: Wild Growth level and healing curve untested; HoT haste scaling unknown (Icy FAQ not
read); exact downrank penalty curve unknown.

---

## Shaman - Elemental

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Wowhead | wowhead.com/forever/guide/classes/shaman/elemental/level-30-dps-overview | L30 rotation + spell levels | patch 1.60.1, L30 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/shaman/elemental/overview-pve-dps | change list | beta | OK (browser) |
| Icy Veins | icy-veins.com/wow-forever/elemental-shaman-ranged-dps-pve-guide | L30 guide | 2026-10-04 | OK (browser) |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/elemental-shaman/ | endgame priority | undated | OK |
| Mobalytics | mobalytics.gg/wow-forever/classes/elemental-shaman-guide | L30 talents/leveling | 2026-10-06 | OK (browser) |
| Mobalytics | mobalytics.gg/wow-forever/guides/shaman-class-overview | change list | 2026-09-18 | OK (browser) |
| Warcraft Tavern | warcrafttavern.com/forever/guides/shaman/ | class summary + stats | Sep 2026 | OK |

**Rotation (single target)** - wowtbc endgame
1. Totems down via Call of the Elements (Searing, Mana Spring, assigned Earth/Air).
2. Flame Shock kept on target.
3. Lava Burst when Flame Shock is on the target.
4. Chain Lightning (wowtbc doubts single-target mana for it).
5. Lightning Bolt filler.
6. Flame Shock while moving.
Warcraft Tavern opener: start Lightning Bolt and queue Flame Shock so it lands before the bolt.

L30 (Icy Veins): pre-place totems (Searing last, short duration) -> Lightning Bolt pull ->
Fire Nova on cooldown vs 3+ -> Flame Shock right after, refresh on expiry for long fights ->
Lightning Bolt until dead.
L30 (Wowhead): Strength of Earth for group -> Lightning Bolt at range -> Searing (ST) or Magma
(multi) totem -> spend Clearcasting on Fire Nova -> Fire Nova vs packs -> alternate Flame Shock
and Earth Shock -> melee to pool mana. Wowhead says at current tuning melee + shocks + Fire
Nova often beats bolt casting while leveling.

**AoE**: Fire Nova (baseline spell, explodes around your active Fire Totem) is the strongest
tool; Magma Totem; Chain Lightning at 32 (Mobalytics; not in beta).

**Upkeep**: Flame Shock, Searing/Magma Totem, Mana Spring, Strength of Earth or Stoneskin,
Lightning Shield (leveling), Water Shield if Restoration-dipped; weapon imbue for melee finish
(Rockbiter/Flametongue/Windfury).

**Defensives**: Frost Shock kiting, Earthbind Totem (Earthbound talent turns it into a 5 s
root), Stoneclaw Totem taunt, Earth Shock interrupt, Healing Wave / Lesser Healing Wave,
Grounding Totem (30), Ghost Wolf escape.

**Forever-specific changes**
- **Lava Burst** (31-pt capstone): +20% damage if your Flame Shock is on target; no guaranteed
  crit.
- **Lightning Overload** (3 ranks): small chance of a free half-damage, threatless repeat.
- Lightning Bolt / Chain Lightning base cast -0.5 s; Elemental Alacrity cuts more (bolt 2 s).
- Lower base spell damage, more spell power on gear; no wands for shamans.
- **Fire Nova** is a spell tied to the active Fire Totem, 10 yd radius; Improved Fire Nova
  lowers its cooldown. Elemental Focus Clearcasting best spent on it.
- Eye of the Storm = flat pushback reduction; Call of Flame now buffs Flame Shock / Fire Nova /
  Lava Burst; Elemental Fury now 5 ranks.
- Mindfulness (Resto talent) and Mana Tide Totem (row 3) are reachable for mana.
- Spell levels 21-30 (Wowhead): Totemic Projection 22, Mana Spring 26, Magma 26, Flametongue
  Totem 26, Windfury Weapon 30, Grounding 30, Call of the Ancestors 30.

**Gaps**: no tested endgame priority; Chain Lightning single-target value disputed; Lava
Burst cooldown not stated by any source.

---

## Shaman - Enhancement

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Icy Veins | icy-veins.com/wow-forever/enhancement-shaman-melee-dps-pve-guide | L30 rotation (most detailed) | 2026-10-05 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/shaman/enhancement/level-30-dps-overview | L30 | patch 1.60.1 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/shaman/enhancement/overview-pve-dps | change list | beta | OK (browser) |
| Mobalytics | mobalytics.gg/wow-forever/classes/shaman-leveling-guide | leveling 1-30 (community author) | 2026-10-01 | OK (browser) |
| Mobalytics | mobalytics.gg/wow-forever/classes/enhancement-shaman-guide | L30 talents/tips | 2026-09-28 | OK (browser) |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/enhancement-shaman/ | endgame priority | undated | OK |
| Method | method.gg/wow-forever/wow-forever-shaman-leveling-guide-and-talents | leveling | 2026-09-30 | OK |
| wow.gg | wow.gg/guides/shaman-enhancement-forever-overview | talent descriptions | 2026-09-19 | OK |
| kami-labs | kami-labs.fr/en/wow-forever/build-chaman-amelioration-wow-forever/ | pre-beta analysis | 2026-09-14 | OK (speculative; says dual wield - contradicted) |

**Rotation (single target)** - wowtbc endgame
1. Windfury Weapon on.
2. Call of the Elements: Strength of Earth, Mana Spring, Searing, Windfury or Grace of Air.
3. Rage of the Farseer with on-use effects.
4. Lightning Bolt at 5 Maelstrom Weapon stacks (do not overcap - Wowhead).
5. Stormstrike.
6. Flame Shock if missing, otherwise Earth Shock.
7. Fire Nova.

L30 (Icy Veins): rank-1 Lightning Bolt to pull -> Stormstrike on cooldown, react to Improved
Stormstrike resets -> Earth Shock on cooldown, consuming the Stormstrike debuff -> alternate
Flame Shock and Earth Shock in groups -> Frost Shock instead of Earth Shock if threat is a
problem -> Fire Nova with a Fire Totem down if mana allows -> autoattack. Rotation is built
around Stormstrike's 8 s timer; be stingy with everything except Stormstrike.
L24-30 solo (Mobalytics leveling): Lightning Shield pre-pull -> Flame Shock pull (save shock for
an interrupt on casters) -> Searing Totem -> Stormstrike -> Fire Nova vs 3+ -> Earth Shock on cd
to kick or finish. Front-load casts, then melee so the 5-second rule restores mana.
Wowhead L30: mostly autoattack; occasional Stormstrike to fish Improved Stormstrike regen;
shocks/bolt to pull.

**AoE**: Searing (or Magma) Totem + Fire Nova on cooldown; Totemic Projection to move the fire
totem onto the pack.

**Upkeep / imbues / totems**
- Imbue: Windfury Weapon from 30 everywhere (Icy, Method). Before 30: Rockbiter solo,
  Flametongue in groups (threat). Disagreement: Wowhead says avoid Windfury Weapon in dungeons
  at L30 (threat) and use Flametongue with 1H+shield.
- Totems (Icy L30): Earth = Strength of Earth (Stoneskin if taking damage); Fire = Flametongue
  Totem in groups or Magma for AoE; Water = Mana Spring; Air = Grounding situationally.
  Windfury Totem at 32. Searing for solo.
- Lightning Shield: refresh pre-pull; mid-fight only after a shock and with spare mana.

**Defensives / tanking**: Healing Wave between pulls, Lesser Healing Wave mid-fight, Stoneskin,
Stoneclaw (taunt), Earthbind + Frost Shock + Ghost Wolf to kite, Earth Shock interrupt.

**Shaman tanking (no dedicated tank spec)**: 1H + shield, Rockbiter Weapon, **Spirit Weapons**
(+30% threat with Rockbiter, -30% without; adds parry), Earth Shock, Searing + Fire Nova for
AoE threat. Guides agree it works for leveling dungeons only; Anticipation and Toughness
(now Stamina) are the only mitigation talents. No priority list exists.

**Forever-specific changes**
- **No dual wield** - Enhancement is a two-hander spec (Wowhead overview); slow 2H preferred.
- **Stormstrike**: talent row 4 (L25), 8 s cd, +20% Nature damage taken for 12 s (Mobalytics
  overview, wow.gg) - Icy Veins frames it as a debuff Earth Shock consumes; treat as the shock
  window.
- **Improved Stormstrike** (L30): Stormstrike gives 50/100% in-combat mana regen for 15 s and
  dodge/parry can reset Stormstrike.
- **Maelstrom Weapon** (5 ranks, Lightning Bolt only): 5 stacks = instant, free bolt. Guides say
  useless until 5/5.
- **Rage of the Farseer** (capstone, L40 per Method): +30% melee speed 25 s, 3 min; cast speed
  removed Sep 24.
- **Shamanistic Focus** (L20): shocks and Lightning Shield -45% mana. Mental Dexterity (Int ->
  AP), Mental Quickness (Int -> spell power).
- **Windfury Totem** is a static aura that stacks with weapon imbues; Flametongue Totem buff
  stacks with Windfury Weapon; totem twisting removed.
- Totem quests: Earth 4, Fire 10, Water 20, Air 30.

**Gaps**: Maelstrom Weapon stack generation rate unknown; no endgame mana model; Stormstrike
debuff-consumption mechanic unclear between sources; no shaman tank priority from any source.

---

## Shaman - Restoration

**Sources**

| site | URL | guide type | date / level | fetched |
|---|---|---|---|---|
| Icy Veins | icy-veins.com/wow-forever/restoration-shaman-healer-pve-guide | L30 guide | 2026-10-04 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/shaman/restoration/level-30-healer-overview | L30 | patch 1.60.1 | OK (browser) |
| Wowhead | wowhead.com/forever/guide/classes/shaman/restoration/overview-pve-healer | change list | beta | OK (browser) |
| wowtbc.gg | wowtbc.gg/warcraftforever/class-guides/restoration-shaman/ | endgame priority | undated | OK |
| Mobalytics | mobalytics.gg/wow-forever/classes/restoration-shaman-guide | L30 talents/tips | 2026-09-22 | OK (browser) |
| Mobalytics | mobalytics.gg/wow-forever/guides/shaman-class-overview | change list | 2026-09-18 | OK |

**Healing priorities** - wowtbc endgame
1. Totems via Call of the Elements.
2. Water Shield up.
3. Ancestral Healing (armor buff from heal crits) kept on the tank if assigned.
4. Mana Tide Totem when the group benefits.
5. Nature's Swiftness + Healing Wave or Chain Heal as the instant emergency heal.
6. Riptide on the tank and anyone taking steady damage.
7. Chain Heal for group damage, started on a Riptide target (+25%).
8. Healing Wave / Lesser Healing Wave for single-target.

L30 (Icy Veins / Wowhead): pre-place totems (Call of the Elements at 20), Searing last ->
Healing Wave (downranked to the damage) on injured targets, tank first -> spare time: Fire Nova
on packs or Lightning Bolt -> melee to pool mana. Mobalytics: pre-cast a low-rank Healing Wave
timed to incoming damage; Lesser Healing Wave only when speed matters (costlier per heal);
rank-1 Earth Shock as a cheap interrupt; keep Healing Wave rank 2 bound.
Chain Heal is not available at L30 in beta.

**Upkeep / totems**: Water Shield, Strength of Earth (melee groups) or Stoneskin, Mana Spring or
Healing Stream (swap to what the party needs), Searing/Flametongue for damage, Tremor vs fear,
Poison/Disease Cleansing as needed; Riptide on tank at endgame. Totemic Recall to refund mana.

**Defensives**: Nature's Swiftness, Stoneclaw (emergency taunt if tank dies), Earthbind,
Grounding, Reincarnation (Improved Reincarnation also +4% max health), Ghost Wolf.

**Forever-specific changes**
- **Riptide** (31-pt capstone): instant heal + 15 s HoT, +25% Chain Heal on that target; can crit.
- **Water Shield** (Resto talent, early): 3 orbs, 2% max mana per orb on being hit or on a heal
  crit, 10 min.
- **Mindfulness** (3 ranks): 50% regen while casting. Mana Tide Totem moved up to row 3.
- **Healing Way** now a flat +8/16/24% Healing Wave; Tidal Focus adds hit; Natural Grace lowers
  threat of all spells; Healing Focus pushback protection.
- Call of the Elements / Ancestors / Spirits at 20 / 30 / 40 (three totem presets, 3 s cast);
  Totemic Projection (22, 1 min cd, 30 yd); Totemic Recall (25% refund).
- Ghost Wolf base 2 s; instant + indoors with Improved Ghost Wolf.

**Gaps**: Earth Shield not mentioned by any source (likely absent); Chain Heal level and
downrank penalty unknown; no tested raid priority.

---

## Sources not usable

| source | reason |
|---|---|
| mythicsim.com/wow-forever | no Druid/Shaman Forever pages found by search |
| world-of-warcraft-forever.wiki, warcraft.wiki.gg | no Forever druid/shaman ability or rotation pages found |
| Blizzard class forums (druid/shaman) | only the dev-notes thread is relevant; search found no Forever class-feedback thread with priorities |
| reddit | no Forever druid/shaman threads surfaced in search |
| mobalytics.gg/.../profile/facefoot-.../elemental-shaman-guide... | user-profile guide, not opened (official Mobalytics elemental guide used instead) |
| kami-labs.fr (guardian, enhancement) | pre-beta (Sep 14-16) talent speculation; enhancement page assumes dual wield, contradicted by Wowhead |
| wow.gg overviews | Sep 19, ability descriptions only; still lists Tiger's Fury/Mangle |
| zockify.com/forever/shaman | Sep 15 overview; rotations marked "coming soon" |
| exitlag.com blog, mmoexp.com, powerupgaming, seemeta, gamesfuze | aggregator/SEO pages; exitlag claims dual-wield burst (contradicted) |
| warcrafttavern.com/wow-classic/... feral powershifting | Classic Era, not Forever |
| Icy Veins resto druid FAQ | collapsed accordion content, not extracted |
| Mobalytics feral "Cat Focus" variant | variant switch did not change gameplay text; L60 variant says "to be updated" |
