# WoW Forever damage principles

The one place to start before refining a Forever priority list. It states what the lists
are for, the rules a change must respect, how strong each kind of evidence is, and where
the detail lives. It is a router with rules, not a class guide: per-tree decisions stay in
[forever-guides](forever-guides/README.md), mechanics in
[FOREVER_ENGINE_DESIGN.md](FOREVER_ENGINE_DESIGN.md), procedure in
[DEV_TOOLING.md](DEV_TOOLING.md#changing-a-forever-priority-list). When this file and one
of those disagree, fix the disagreement; do not pick one silently.

Statements here are marked **rule** (project policy, from [AGENTS.md](../AGENTS.md)),
**model** (seen in the offline comparison only) or **open** (not settled). Dated findings
are for the build and character they name.

## 1. Who the lists are for

- **Rule.** Good-enough damage in most situations, for an ordinary player, not perfect
  output in every scenario. Prefer one simple general rule to a special case.
- **Rule.** Situational strategy is the player's: kiting, slows, positioning, crowd-control
  timing, encounter-specific play. No list entry, gate or probe advises it.
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

- **Rule.** Unknown stays unknown. A condition uses only signals confirmed readable for
  the context it runs in; nothing infers a hidden resource, aura or mechanic state from an
  unrelated signal, and no hidden number is reconstructed. Start from the
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
  regular enemy at or below the player's level, fought solo, is a fast fight: there a new
  damage over time starts only early in the target's health, and only a spell that is mostly
  its hit is exempt. The opener and the first applications are untouched. Skipping a DoT
  outright on such a target is **not** supported: in the simulator it gained at some levels
  and lost at others (Bane of Agony dropped: 9% slower at level 10, 13% at level 18), because
  the same level and kind covers a 9 second kill at level 4 and a 20 second kill at level 18.
  An elite, a boss, a higher-level enemy, a pack, a group or any unknown read keeps the
  ordinary dying-target rule.
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
2. Check the entry is damage (section 2) and its condition is readable (section 3).
3. Compare before and after in the model across the target set and at least two gear
   points; note anything the converter approximated or could not express.
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
