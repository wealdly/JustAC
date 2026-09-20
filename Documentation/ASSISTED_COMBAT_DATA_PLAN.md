# Assisted-combat rotation data: plan

Blizzard's per-spec rotation is in the client data (`AssistedCombat`, `AssistedCombatStep`,
`AssistedCombatRule`; 693 steps and 3,116 conditions across 40 specs at 12.1.0.69382). Steps are
in priority order; each carries conditions. Found 2026-09-19.

## Done

1. **Insertion audit** - `tools/audit_assisted_combat.py`: what SimC pool insertion adds per spec.
2. **Rotation diff** - same script, `--diff`, run by `tools/update_data.py` on every data refresh.
3. **Classification audits** - `--cooldowns`, `--dots`, `--healers`, `--procs`. First findings:
   Deep Breath and Champion's Leap move the player and went into `NEVER_INSERT`; the healer pins
   broadly agree with Blizzard's order (Discipline differs only in Penance vs Mind Blast).
4. **Blizzard's order as the "Match Blizzard's pick" tiebreaker** - `Data/AssistedCombatOrder.lua`,
   `RotationImport.GetBlizzardRank`. The open question is settled: rank by a spell's LAST step.
   First-step order put Thunder Clap and Whirlwind ahead of Rampage for Fury; last-step order reads
   cooldowns > spenders > builders > filler on all four specs checked.
5. **Pick recorder + offline join, kept as a DIAGNOSTIC.** `/jac inspect picklog` records;
   `--decode` joins the log to the rules. Built as the first half of step 5 below, which has since
   been demoted - see that section for why.

## What is established, and what is not

- The DB2 step list is a **superset** of live `C_AssistedCombat.GetRotationSpells()`. Measured on a
  Devourer Demon Hunter: data lists 7 spells, live returned 5. Live dropped one step gated on a
  talent the character lacked, and both spells whose every step carries **ConditionType 70**.
- Across all specs the type-70-only spells are exactly the major cooldowns and movement abilities
  (40 of them). What type 70 literally tests is **unconfirmed**.
- Condition types with a spell id in value 1 are readable as they stand: 9 and 16 (aura / talent
  present), 10 and 15 (DoT or debuff state on the target), 54 and 55 (aura with a stack count),
  17 and 18 (aura with a millisecond value - a remaining-time test). The purely numeric types
  (3, 4, 8, 11, 12, 27, 28, 56 ...) are **not decoded**.

Every step below must fail safe to today's behaviour: Blizzard can restructure these tables in any
patch, and nothing here is documented.

## 3. Classification audits (cheap, data only, report-only)

Each is a new mode of the audit script, or a small sibling, that diffs Blizzard's data against a
hand-curated table. None ships data; they find mistakes.

- **Cooldown and movement class.** Type-70-only spells per spec vs the burst anchor lists in
  `Data/SimcRotations.lua` and vs `NEVER_INSERT`. Expect it to confirm most entries and surface
  a few missing ones.
- **DoT upkeep.** Types 10/15 name the DoTs Blizzard refreshes when missing. Diff against
  `Data/TargetDots.lua`, where the July priority audit found systemic problems.
- **Proc links.** Types 9/16 pair an aura with the ability it gates. Diff against the proc
  handling the queue already does, looking for pairs it does not know.
- **Healer damage lists.** The six local pins in `tools/simc-apl/` were written from judgment.
  Compare their order with Blizzard's step order for those specs.

Order: cooldown class first (it directly guards insertion), then DoTs, then healers, then procs.

## 4. Blizzard's order as the ranking for "Match Blizzard's pick"

That mode currently infers an order heuristically. The step `OrderIndex` is the real one.

- Generate `Data/AssistedCombatOrder.lua` (spec -> spell id -> first step index) from the tables.
- In "Match Blizzard's pick" mode, rank the tail by it; keep the heuristic as the fallback when a
  spell has no step.
- Works for every spec, including below max level where the SimC order is a poor fit, and for any
  spec that ever lacks SimC data.
- Open question to settle first: a spell usually has several steps at different priorities
  depending on conditions. First-step index is the simple choice; check on three or four specs
  that it produces a sane static order before building.

## 5. Reading hidden state from the pick - DEMOTED to diagnostic only (2026-09-20)

The idea: steps are evaluated in order, so when the game picks an ability, that step's conditions
passed and every earlier step failed. Reap has a step gated on "Soul Fragments at least 4"; a pick
through it reveals a stack count the addon cannot read.

**Why it is not a roadmap item.** Checked against what the addon already does, two of its three
claimed benefits duplicate existing work, one of them with a worse method:

- **Enemy count** - already read directly (`GetEngagedEnemyCount`, promote-only), with the pick's
  own archetype as the fallback inference (`ContextRank`). Blizzard's rule would be a third opinion
  on the same fact. The only gain is when the direct count is wrong (nameplates hidden, enemies
  stacked), and how often that bites is unknown.
- **Resource thresholds** - already answered by `IsUnitPowerBelow` for any percentage,
  continuously. A pick only answers at the moment of a decision. Strictly worse.
- **Hidden stacks and buffs** - genuinely new, but one-off per spec, and no feature is waiting on
  those facts.

It also runs against the standing design principle (2026-08-10): DETECT state directly, infer from
the pick only as a fallback. Buff windows are already inferred from the pick via the SimC
conditions (`GateInPickWindows`), so even the inference half of this exists.

**What stays, because it is built and costs nothing:**

- The recorder and `--decode` as a debugging tool. For a report like "the queue thought it was
  single target in a pack", a pick log joined to the rules shows what Blizzard's rotation believed
  at that moment next to what the addon counted.
- Decoded condition types, on paper only - they make the rule table readable for the audits in
  step 3. Likely-but-unconfirmed from their values: types 11 and 12 (about 80 uses, almost always
  "3,10" or "2,10") are "at least N enemies within 10 yards"; types 56 and 3 carry values like 25
  and 30 and look like resource thresholds. A recording would confirm them.

**Revisit only if** a feature ever needs a hidden stack count that has no direct read. Measured
offline for that day: 62% of abilities have exactly one step, so most picks are unambiguous, but
it ranges from about 90% (Guardian, Restoration Shaman) down to 22% (Retribution). Build on
positive inference only - "an earlier step did not fire, so its condition was false" needs every
condition on that step decoded.
