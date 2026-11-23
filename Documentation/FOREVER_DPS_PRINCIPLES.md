# WoW Forever damage principles

The one place to start before refining a Forever priority list. It states what the lists
are for, the rules a change must respect, how strong each kind of evidence is, and where
the detail lives. It is a router with rules, not a class guide: per-tree decisions stay in
[forever-guides](forever-guides/README.md), mechanics in
[FOREVER_ENGINE_DESIGN.md](FOREVER_ENGINE_DESIGN.md), procedure in
[DEV_TOOLING.md](DEV_TOOLING.md#changing-a-forever-priority-list). When this file and one
of those disagree, fix the disagreement; do not pick one silently.

The [core principles](#core-principles) come first; the sections after them hold the detail.
Statements here are marked **rule** (project policy, from [AGENTS.md](../AGENTS.md)),
**model** (seen in the offline comparison only) or **open** (not settled). Dated findings
are for the build and character they name.

## Core principles

**Goal.** High, reliable damage that an ordinary player can follow without effort.

These apply to every queue in both clients wherever JustAC decides the order. On Retail the
first slot stays the game's recommendation; the principles govern the rest.

### Simplicity leads

- **At every decision point the simplest option is the default.** That holds for what the
  player presses, what a list contains, how a rule or condition is built, what a setting
  offers and what the code does: simple in design and simple in choice.
- **Complexity compounds.** Each extra button, stance swap, condition, special case, setting
  or queue stage adds to every one before it, for the player and for the code. So a step is
  judged against the simplest option, not against the last accepted version, and the margins
  below apply to the total, not one step at a time.
- **Removing complexity needs no margin** as long as damage stays within it. Adding complexity
  must clear one. A simplification pass asks whether each existing complication still earns
  its place.
- **Fewer parts wins.** Of two designs that do the same job, take the one with fewer parts.

### Hard limits

These hold whatever the damage or simplicity case. When two of them meet, the lower number wins.

1. **Damage only.** The offensive queue recommends damage, in every talent tree. Utility stays
   with the player. Detail: [section 2](#2-what-may-be-in-a-list).
2. **Confirmed signals and sound inference.** A decision rests on what the client confirms
   readable in that context, or on a sound inference from several such signals. An unreadable
   read neither blocks nor promotes an entry; when an inference cannot be made, the state stays
   unknown. Detail: [section 3](#3-what-a-condition-may-use).
3. **Damage now, in this context.** An entry counts as damage only where it can deal damage in
   the context the client confirms right now. While the player is moving, a spell with a cast
   time deals none; out of range, under a loss of control, against an immune target or on a
   target that dies before the cast lands, the same holds. Such an entry is never the press
   for now: something that can deal damage in that context goes first, and when nothing can,
   the queue shows what comes next without presenting it as the press. A context the client
   does not confirm changes nothing.
4. **The player decides strategy and keeps their settings.** Situational play (kiting, slows,
   positioning, crowd-control timing, encounter tactics) is theirs; no entry, gate or probe
   advises it. Custom lists, explicit settings and overrides are never changed to make a rule
   work.

### Weighed together

Within the hard limits, simplicity leads: the simpler option wins unless the more complicated
one clears its margin and stays reliable.

5. **Reliable before peak.** Judge a change on every reference target (one level below, even,
   one above, an elite, a short and a long fight), at more than one level and gear point. A rule
   that is never clearly worse beats one that is best in some fights and clearly worse in others.
   A change that improves the average but is clearly slower on any reference target needs a
   condition that tells those fights apart, or it is not made.
6. **Easy to follow.** The player should always know what to press next.
   - The first slot is the press for now; waits and blocked entries trail behind it.
   - The order is stable. It moves only on a confirmed change that lasts, not on a momentary
     read: a wait that ends within one global cooldown keeps its place, and movement is
     debounced before the queue reorders for it.
   - The same situation gives the same answer.
   - The queue never asks the player to switch targets.
7. **General rules over special cases.** Prefer one data-derived rule for every tree to a
   per-class, per-spell or per-build exception. Rules are made in the generator, never in the
   generated data, and must hold in both clients.
8. **Evidence first.** Every change says which [evidence grade](#5-evidence-strongest-first)
   supports it, and behavior changes wait for approval.

### Directing and responding

The queue does two different things, and they pull against each other.

- **Directing** tells the player what to do: the next press, a buff before the pull, a stance
  to take for one attack.
- **Responding** follows what the player or the fight has already done: moving, kiting, the
  target they picked, the stance or form they hold, being out of reach, being hit.

The balance:

- **Direct the order, respond to the situation.** Choosing the next damage press among what
  works where the player stands right now is the queue's job, and it should be decisive: one
  clear press, not a hedge. Where the player stands, what they target and how they move are
  theirs; the queue adapts to them and never fights them.
- **Directing a change of situation is a complication.** Asking the player to stand still,
  change stance or form, close the distance or switch targets costs them a decision. It must
  clear its [simplicity margin](#simplicity-margins); switching targets never does. Before a
  pull, when the player has not committed yet, directing costs least: openers and pre-pull
  buffs belong there.
- **Respond to what lasts, not to every twitch.** The queue answers a confirmed change that
  holds (debounced movement, a stance actually taken, a target actually chosen), so it does not
  chase the player and flicker. A response that would reverse within a global cooldown is no
  response.
- **When the two collide, respond.** If the best press needs a situation the player is not in
  (a cast while they move, melee while they are out of reach), the queue offers the best press
  for the situation they are in, not an instruction to change it. That is principle 3 at work.

### Stable, followable output

A queue that changes faster than the player can press is a burden, not a help. The output is
a signal the player follows at the pace they act.

- **One answer per press.** The first slot should change about once per press opportunity (a
  global cooldown or a cast), and only for a reason. Faster change is noise.
- **Look ahead to the next press.** Decide for the moment the player can next act, the end of
  the current global cooldown or cast, not for this instant. What becomes ready, affordable or
  in reach by then counts as ready; a press already sent counts as done (its cooldown, cost and
  debuff) until the game's own reading catches up.
- **Slot 2 names the next press.** With no game pick (WoW Forever), the second slot forecasts
  what will lead once slot 1 is pressed: after the current global cooldown and the longer of
  slot 1's cast and a global cooldown. A spell ready by then that ranks above slot 2's choice
  shows there. Measured 2026-11-20: slot 2 named the next press on 40 of 55 presses of slot 1,
  and 9 of the 15 misses were a cooldown ending during slot 1's cast. Before a pull only the
  chosen opener ranks first; the other cast-time candidates keep their list rank, so slot 2 shows
  what follows the opener once the fight starts (2026-11-22: Shadow Word: Pain had jumped from
  slot 3 to slot 1 as each pull began). Closing on the target (its execute range) with another
  enemy engaged, slot 2 names the opener on a fresh target (the list's own debuff entry, Shadow
  Word: Pain) since that is what leads after the kill; it never asks for a target switch. Each
  first-slot change in the capture records its stage (`phase=` prepull, fight, closing) and, just
  after a target change, whether it followed a kill or a live swap (`after=`).
- **Hold through a press.** While a cast or channel runs, the plan after it stays put unless a
  confirmed event demands a change.
- **Change on events that matter.** A proc, the target changing or dying, a confirmed context
  change that lasts (movement, range). A read that flickers for one update changes nothing.
- **Incumbent advantage.** A challenger replaces the shown order only when it clearly wins and
  keeps winning; a tie keeps the current order. This holds for the later slots too.
- **Stability is measured.** How often the first slot changes per press is a tested property.
  A change that makes it flip more without a clear damage gain fails principle 6.

In place today: the global cooldown look-ahead, waits and costs due within one global cooldown
keeping their place, a held execute and pack context, the channel hold, the debounced On the
Move stage, the charge arrival look-ahead, the pending-cast bridge for damage over time and the slot 2
forecast of cooldowns ending before the next press.

### Net damage: adding to or displacing the auto attack

Every press is valued by what it adds over what it takes away. Auto attacks run on their own,
and a press relates to them in one of two ways.

- **Additive.** An instant special attack (Mortal Strike, Revenge, a judgement, an instant
  shot) lands on top of the auto attack, which keeps swinging. It is worth its full damage and
  is never weighed against the auto attack as if one replaced the other.
- **Displacing.** A next-swing attack (Heroic Strike, Cleave, Maul, Raptor Strike) replaces the
  next white swing, and that swing's rage. A cast that stops a wand, or delays an auto shot or
  melee swing, takes away what those would have dealt meanwhile. Such a press is worth only its
  damage over what it displaces.
- **A next-swing attack never displaces another one already queued.** Offering a second one
  while the first waits for the swing only trades one for the other.
- What displaces what is a client rule per weapon type and must be confirmed for Forever before
  a decision depends on it (principle 2).

### Class and build fit

Every principle is applied to a class and build as it is actually played, not to a generic
template. The question for each choice is also: does this make sense for this class and build?

- **The baseline is the build's own simplest play.** An Affliction warlock deals its damage
  over time across several targets; a Frost mage alone fights at range around crowd control; a
  Protection warrior holds one target in front of them. Simplicity is measured against that
  baseline, so what makes up the build's own damage is not a complication for it.
- **Hard limits stay the same for every class.** Where a build's natural play meets one, the
  queue responds instead of directing:
  - Spreading damage over time: the queue never asks for a target switch, but when the player
    switches, it offers what the new target is missing, and each target keeps its own timers.
  - Crowd control and kiting: these are the player's. While the player controls or kites, the
    queue offers what deals damage from where they are (principle 3).
- **A build-specific rule is allowed when the build's damage depends on it**, and it is still
  built as a general rule keyed on data (talent tree, learned spells, how the build deals its
  damage), never as a class exception in shared code (principle 7).
- **Level is part of the build.** The same class plays differently before and after its core
  spells are learned.
- **When a build's natural play cannot be served within the hard limits**, its guide notes say
  so and that part is left to the player. A hard limit is not bent for one class.

### Simplicity margins

What a complication must earn over the simplest option for the build, on the reference targets and without
being clearly worse on any of them. Margins add up: a rotation with two complications has to
clear both together. A complication that misses its margin goes, even when it gives the most
damage.

| Complication | Examples | Margin |
|---|---|---|
| An extra button the player must press | A low-value attack with its own cooldown | 1% |
| A setup press with no damage of its own | Extra stacks of an armor debuff | 3% |
| Swapping stance or form during a fight | Leaving a stance for one attack | 5% |
| Switching targets | Spreading a debuff across a pack | Never recommended |
| A new rule, condition type or queue stage | A special case for one kind of fight | 2% across the trees it touches, or a fix for a confirmed wrong recommendation |
| A new player setting | A toggle for one behavior | Only when no single default serves most players |

On a pack, a stacking debuff stops at one application per target.

### Checking a change

Answer in order; stop at the first "no".

1. Does it make sense for this class and build, as they are actually played?
2. Is there no simpler way, for this build, to get close to the same result?
3. Is it damage?
4. Can every condition it needs be read in the contexts it runs in?
5. Does it deal damage in every context where it is offered as the press for now?
6. Does it respond to the player's situation, directing a change only where that clears its margin?
7. Does it keep the output stable, about one change of the first slot per press?
8. Does it leave player settings and custom lists alone?
9. Is it at least as good on every reference target, and better on average?
10. Do the gains clear the margins of every complication it adds, together?
11. Is it one general rule rather than a special case?

## 1. Who the lists are for

- The reference player is levelling (roughly 10 to 60), mostly alone, in gear that lags the
  level: uncommon pieces a few levels behind, some crafted, one or two lucky rares. Not
  best-in-slot, not a twink, not a level 60 raid character. Most source presets are level
  60 raid lists, so every borrowed line has to be re-read for this player.
- The reference fight is short: one target within a level of the player dies in about 15
  to 30 seconds in the model, an elite in 60 to 90. Judge a change on targets one level
  below, even, one above and an elite, never on one of them alone.

## 2. What may be in a list

- **Rule.** Damage only, in every talent tree, tank and healer trees included. A debuff
  that raises the damage a target takes counts as damage. Slows, roots, mitigation and
  threat debuffs, healing and crowd control do not get entries even when a guide or sim
  lists them. See [the damage-only queue](FOREVER_ENGINE_DESIGN.md#damage-only-queue).
- **Rule.** A damaging spell never waits on its own non-damaging side effect.
- **Rule.** The one exception is the ranged opener on a melee target, and it belongs to
  pull handling, not to a list entry.
- **Rule.** Tank and healer help belongs in the defensive queue.

## 3. What a condition may use

- **Rule.** A condition uses signals confirmed readable for the context it runs in, alone or
  combined into a sound inference. An inference is sound when:
  1. every input is a confirmed readable signal in that context;
  2. the link between the inputs and the inferred state is a game rule or was measured in game,
     not a coincidence seen once;
  3. it falls back to unknown when any input is unknown, and expires when its inputs go stale;
  4. being wrong is cheap: the queue falls back to its general behavior, and no damage press is
     held back for long on the inference alone;
  5. code and diagnostics name it as an inference, not a reading.

  Examples in use: a damage over time counted as running from our own landed cast and its
  duration; a target that holds its range, from it casting or hitting us while out of reach;
  a fast fight, from the target's level, kind and the player being solo. An estimate of a value
  the client keeps secret is allowed under the same criteria when a decision needs it, by the
  [threshold scope rule](SECRET_VALUE_THRESHOLD_GATES.md#the-scope-rule). Still not allowed: an
  inference from a signal unrelated to the state. Start from the
  [documentation index](README.md#working-references) for what is readable.
- **Rule.** No scattered class, spell or build exceptions in generic logic. A data-derived
  rule in the generator beats a repeated per-class patch.
- A list has to work at every level. A line may name a spell the character does not have
  yet; the runtime treats an unlearned spell as unavailable, so write conditions that still
  make sense when the named spell is missing (levelling Arms before Mortal Strike).
- A condition the addon cannot read leaves the entry "delegated": it keeps its position
  and is offered whenever ready. Dropping a source condition is therefore not neutral. It
  turns a conditional press into an unconditional one, and that needs its own evidence.

## 4. How levelling fights differ from the source presets

These are the recurring reasons a level 60 raid line is wrong for the reference player.
All are **model** findings unless marked; each is a question to ask of a line, not a law.

- **Setup has to pay back inside the fight.** Damage over time, stacking debuffs and long
  ramps lose value as fights shorten. The runtime already refuses a new damage over time on
  a dying non-boss target. One application of an armour debuff can pay where five do not;
  the reverse holds on an elite.
- Relative target level is a narrow signal for slow target-only payoffs: a regular target at
  least one level below is not assumed to live long enough; one or more levels above is.
  This does not suppress ordinary damaging DoTs or a spell because of its own long-lived
  damage rider. Those are damage sources, including the primary output of DoT-focused
  builds, not setup debuffs. Unknown, equal-level and skull-level reads do not invent a
  fight-length verdict.
- Level and kind also time ordinary DoTs, without removing them (decided 2026-11-18). One
  regular enemy at or below the player's level, fought solo, is a fast fight: there the first
  application of a damage over time starts only early in the target's health, and only a spell
  that is mostly its hit is exempt. A DoT that has already run on the target may be renewed,
  since the target has outlived it once. Skipping a DoT
  outright on such a target is **not** supported: in the simulator it gained at some levels
  and lost at others (Bane of Agony dropped: 9% slower at level 10, 13% at level 18), because
  the same level and kind covers a 9 second kill at level 4 and a 20 second kill at level 18.
  An elite, a boss, a higher-level enemy, a pack or any unknown read keeps the ordinary
  dying-target rule. A group is stricter on one regular target: for the first 20 seconds only a
  DoT with a real hit up front goes out, because that target dies too fast for the rest.
- **Long cooldowns are a safety margin as well as damage** (decided 2026-11-20). A cooldown
  spent to shorten an ordinary kill is missing on the pull that needs it, and that can cost the
  player the fight. A self-buff with a cooldown of two minutes or more is offered only in a fight
  projected to be long or dangerous: a boss, an elite, several enemies, or a regular target three
  or more levels above. **Model** (client 1.60.1, `behind` gear, 4 batches of 300, six trees):
  a target three levels above takes melee 40 to 70% longer than an even one and ranged 15 to 20%
  longer, against 10 to 25% at two above; releasing the cooldowns at the pull there is 2 to 9%
  faster. Time already spent on an ordinary target does not release them: used late in that kill
  they are missing on the next pull. The price in the same runs is 10 to 18% on even-level kills
  for a Combat rogue and 0 to 5% for the other five trees. Not measured in game.
- On a dying target a DoT with a real hit up front still goes out when it is instant. A cast-time
  one must be mostly its hit (Immolate is not). Damage that lands after a long delay (Bane of
  Doom) waits for a boss, an elite or a higher-level enemy: time already spent on a target does
  not show that it will outlast the delay.
- **Model.** Long DoTs stay in fast fights (2026-11-18, client 1.60.1, `behind` gear, no pet,
  8 batches of 500, simulator build with the local wand attack, whose behavior is assumed and
  not measured). Wands were the best tradable one each level can equip: Lesser Magic at 6 and
  10, Greater Magic at 14 to 24, Lesser Mystic at 30 (Greater Mystic is missing from the
  simulator's database). Targets were regular mobs at or below the player's level, and
  even-level mobs at 40 to 80 percent health to stand in for faster kills. A warlock
  (Affliction and Destruction, levels 6 to 30) that skipped every DoT longer than 12 seconds
  killed slower in 55 of 60 comparisons when hit from the first second (33 percent on average,
  69 percent at worst) and in 44 of 60 when never hit (17 percent on average, 53 percent at
  worst). With the wand as the only filler (Affliction), it killed slower in 24 of 30 and 26 of
  30. From 12 seconds up, removing Immolate or Corruption alone, or Arms Rend at levels 24 and
  30, cost time on average at every fight length. Skipping every long DoT won only in some
  fights of 13 seconds or less, by at most 14 percent, and Bane of Agony alone stayed near even at
  12 to 16 seconds (4 percent faster to 8 percent slower) against a loss of 6 to 31 percent
  past 20 seconds. Level and kind cannot tell those fights apart, so no entry is dropped.
  Captures showing a DoT delivering 34 to 59 percent of its listed damage do not change this:
  a partial DoT still beats the direct damage or wand shots that would replace it. The bench
  does not run the queue's own wand comparison or pushback response, so the Shadow Bolt and
  wand-only fillers bracket real play. Priest and hunter are untested: the bench supports
  warrior and warlock only.
- **Model.** Level gaps (2026-11-19). The target's level and kind read plain in combat
  (`BlizzardAPI.GetTargetLevelDelta`), so the gap is a usable signal. Its expected effect comes
  from the client's creature table and the simulator's Forever combat rules: creature health
  grows about 12% a level around level 14 and 5% around level 30, melee miss rises 0.5% a level
  to 8% at three above (Forever applies the full penalty, per the simulator's tester data), and
  spell miss is 4, 5, 6 and 17% at even to three above. Against an even target, a level 14
  player's kill time is about x0.63, x0.74, x0.86 at three, two, one below and x1.15, x1.32,
  x1.71 at one, two, three above, and damage taken moves about twice as far (x0.43 to x2.25);
  at level 30 the steps are about half as large. The only measured pair so far is steeper:
  a level 14 Protection warrior killed a level 11 mob in 8 seconds and a level 14 to 15 one in
  34. Calibrate per level gap from recorded kills before relying on these factors. In the
  uncalibrated model (no pet, runtime rules on), leaving out an Affliction DoT or Arms Rend was
  slower at every gap from three below to two above, and their value grew with the gap (all long
  DoTs, never hit: 28% slower without them at three below, 44% at two above; Rend 6% at three
  below, 14% at even). The model's low-level fights run 17 to 21 seconds where the one measured
  three-below kill took 8, so the low-gap case stays open until warlock kills and pets calibrate it.
- **Do not starve the main strike.** A filler that spends the resource or the swing the
  main attack needs costs more than it deals. A cast-time attack that resets the swing
  timer is the usual case.
- **The same entry can be right at one level and wrong at another.** A filler that helps
  before the tree's main strike is learned can hurt after it. Prefer a "known" condition on
  the main strike to removing the filler.
- **Gear moves the size of an effect, sometimes its sign.** Check a finding at a behind, an
  average and a lucky gear point before trusting it.
- **Each class meets a target differently**: in front and being hit from the first second,
  at range with the target arriving late, kiting, or behind a pet. Rage from damage taken,
  pushback and time on target all follow from that. The comparison tool models only the
  melee case today.

## 5. Evidence, strongest first

| Grade | What it is | Good for |
|---|---|---|
| Measured in game | A bounded capture on the Forever client with the control that proves it, reviewed after a confirmed flush ([capture workflow](DEV_TOOLING.md#capture-workflow)) | Any claim about how the client behaves; the only grade that can justify a new condition signal |
| Model comparison | `tools/forever_sim_bench.py` on the same seeds, with a stated interval ([how to run](DEV_TOOLING.md#comparing-a-forever-list-offline-at-levelling-levels)) | Ranking two orderings, or one entry in or out, when the gap is several percent and holds across targets and gear points |
| Source preset or guide | The vendored simulator presets and the launch guides | Where an ordering came from; a starting point, mostly level 60 |
| Idea | Reasoning without a run | Deciding what to test next |

- The model cannot give absolute damage, settle differences near one percent, or speak for
  immune creatures, movement, unmodelled abilities, or a class whose table is not filled in.
  Its combat tables are Classic's and several Forever rules in it are provisional.
- A model result is a candidate for a change, never the change. Say which grade a claim
  has, and do not present a model number as a game fact.
- A real character beats an assumed one: `/jac inspect character` exports level, ranks,
  talents and gear for `--gear file:<path>`.

## 6. Changing a list

1. Read the tree's guide file and search it and `tools/test_forever_rotations.py` for a
   recorded decision. A failing assertion may be a deliberate choice.
2. Run the [change check](#checking-a-change): damage, readable conditions, player settings.
3. Compare before and after in the model across the target set and at least two gear
   points; note anything the converter approximated or could not express. The gain has to
   clear its [simplicity margin](#simplicity-margins) without being clearly worse anywhere.
4. Propose the change with its evidence grade and wait for approval. Behaviour changes are
   never made on the model's word alone.
5. Follow [the list procedure](DEV_TOOLING.md#changing-a-forever-priority-list): edit the
   generator, never the generated file; regenerate; add an assertion; deploy; write the
   player note without describing how hidden values are read.
6. Record the decision and its evidence in the tree's guide file, and what would still
   have to be measured in game.

## 7. Open candidates

Unapproved leads from the first model runs (2026-11-18, client 1.60.1, warrior only). Each
needs approval and an in-game check before it becomes a change.

| Candidate | Evidence | Grade |
|---|---|---|
| Arms: Slam only while Mortal Strike is not known, or with Improved Slam | At level 40 the list kills 10 to 17 percent faster without the Slam entry at three gear points; at level 20 the entry helps by 1 to 5 percent | Model |
| Protection: one Sunder Armor application, as Arms has | On a real level 12 character the Protection list is 6 percent slower than the simulator's preset on an elite and slower than the Arms list in every scenario; it never applies Sunder | Model |
| Arms level 40: a further gap of about 4 percent to the source preset with average or better gear | Remains after removing Slam; cause not investigated | Open |

Things the model assumes and nobody has measured on Forever: Slam's swing reset and cast
time while levelling, rage per hit dealt and taken, miss, dodge, parry and glancing rates
against even and higher targets, real creature health against the client's expected values
(elites especially), and damage per rank of damage-over-time abilities.
