# WoW Forever guide references

Researched 2026-10-07 during the level-30 beta. These paraphrased guide summaries are
historical evidence, not confirmation of launch behavior. Recheck current client data and
sources before using them to change a priority; never copy guide text into the addon.

| File | Covers |
|---|---|
| [warrior-rogue.md](warrior-rogue.md) | Arms, Fury, Protection; Assassination, Combat, Subtlety (no rogue tank exists) |
| [paladin-priest.md](paladin-priest.md) | Holy, Protection, Retribution; Discipline, Holy, Shadow |
| [druid-shaman.md](druid-shaman.md) | Balance, Feral cat, Feral bear, Restoration; Elemental, Enhancement, Restoration |
| [hunter-mage-warlock.md](hunter-mage-warlock.md) | Beast Mastery, Marksmanship, Survival; Arcane, Fire, Frost; Affliction, Demonology, Destruction |
| [cross-class.md](cross-class.md) | Blizzard notes, combat-mechanic changes, healing, consumables, simulators, builds at the cap |

## Priority-list sources

The current generated baseline comes from the MIT-licensed MythicSim Forever preset mirror,
pinned and documented in [FOREVER_ENGINE_DESIGN.md](../FOREVER_ENGINE_DESIGN.md). The
presets provide a useful level-60 starting point, but are not a complete guide to leveling,
hybrid builds, or every target-count context. Guide-derived adjustments remain human-reviewed;
CSV refreshes validate spell data and learnability, not priority quality.

## Guide-to-archetype workflow

Use this process when adding or revising a guide-based priority or deciding which mixed-build
archetypes JustAC should recognize. Keep conclusions in the class guide files as original,
concise paraphrases with source links. Do not copy guide prose, scrape it into addon data, or
treat a spell-data CSV as evidence for rotation order.

1. **Record evidence and scope.** For each source, record its URL, author/publisher, publication
   or update date, client/build or game phase, and what it actually supports. Prefer first-party
   Forever notes for mechanic changes. Use reputable class guides to fill in rotation/build
   detail, cross-check material disagreements, and label unresolved claims with confidence.
2. **Describe a build as an archetype, not a tree name.** Record the intended role and content,
   talent-point split, signature talents and any talent-dependent spells or priority changes.
   Include leveling variants when they materially change what is known or practical. A tree's
   name or largest point total alone is not a sufficiently precise build fingerprint.
3. **Extract behavior by context.** Separate opener/setup from the repeating priority. For each
   single-target, cleave, and AoE list, record ordered abilities and their trigger in plain
   language: upkeep, resource threshold, proc/talent requirement, target count/range, or
   cooldown alignment. Note any source disagreement and whether a condition depends on gear,
   encounter, or a mechanic the addon cannot observe.
4. **Validate against the client.** Check spell identity, rank chain, learnability, talent
   association, and relevant mechanics against the current Forever client/source and CSV
   snapshot. A guide's spell name does not prove a particular rank or spell ID. Verify live API
   signals with in-game probes before using them to detect a build or gate a recommendation.
5. **Choose a small canonical set.** Keep one reviewed priority per useful archetype and target
   context; don't create a profile for every point allocation. For a hybrid, prefer selecting
   one coherent archetype over merging lists. A future similarity score may weight signature
   talent matches above incidental point differences, but its inputs, confidence threshold,
   tie-break, and fallback must be defined and tested before it replaces dominant-tree selection.
6. **Encode and review deliberately.** Put hand-reviewed adjustments in the existing Forever
   source/generator path with a short rationale and source reference. For a curated list on an
   existing tree key, add a SimC-syntax pin in `tools/simc-apl-forever/` and map it as
   `pin:<file stem>` in `tools/gen_forever_rotations.py`; see `paladin_holy.simc` for the
   pattern. The current generator selects one source per tree and does not implement multiple
   archetypes or similarity matching. Keep unsupported conditions explicit rather than
   inventing a signal. Regenerate `Data/Forever/Rotations.lua`, review the generated diff, run
   `tools/test_forever_rotations.py` and the affected Forever regression tests, then run
   `tools/check.ps1 Data\Forever\Rotations.lua`. Do not bump versions, build, sync deployed
   copies, or release as part of this review.

### Per-archetype note template

Use this outline in the relevant class guide when documenting a candidate:

```
Archetype and role:
Source(s), date, client/build:
Talent split:
Signature talents / talent-dependent abilities:
Leveling variants:
Single-target priority and triggers:
Cleave/AoE priority and triggers:
Source disagreements / confidence:
Client signals and spell IDs verified:
JustAC adaptation and unsupported conditions:
```

Do not fill an unknown with an inferred value. Mark it unresolved and keep it out of automatic
profile matching until it can be verified.

### Condition coverage report

Run `python tools\gen_forever_rotations.py --coverage` for report-only JSON;
it does not write generated priority data. The report identifies class, tree,
target context, entry/spell, condition path, source pin, status and reason:

- **fully supported**: a runtime evaluator exists; live unknowns remain possible.
- **partial**: condition semantics or evidence are limited, including DoT health
  policy versus presence, buff-window ranking, spell-bound stack reads and groups.
- **delegated**: an unsupported source condition was omitted; retained gates are
  listed separately, with available lost-condition notes.
- **disabled**: an emitted `unconfirmed` condition always returns false.

This inventories post-adaptation condition occurrences in emitted target-tier
lists, not every original source node or a percentage of optimal APL fidelity.
No-gate, non-delegated fallbacks have no condition row; omitted identical tiers
inherit the emitted list. Group rows do not imply their children are supported.
Source rewrites and dropped entries still need source/generator review.

For in-game evidence use the shared
[priority-condition capture](../FOREVER_COMBAT_SIGNALS.md#priority-condition-coverage).
Do not equate imported verdicts with final ordering or promote unknowns to truth.

## What the guides change for the engine

1. **Guides go stale fast.** Tiger's Fury removed and Mangle renamed Primal Bite (Oct 1), Fury
   rework (Oct 1), Slam cooldown raised (Sep 24), Bloodthrill odds doubled (Sep 24). Every
   list must build cleanly with `tools/gen_forever_rotations.py`, which checks every
   ability against the current Forever data (exit 1 on one no class can learn).
2. **Ranks.** New ranks do not replace old ones on action bars, low ranks get less spell power
   and fewer proc chances. Show the highest known rank, find the hotkey for whatever rank is
   on the bar (probe H14).
3. **Swing timer is a real gate.** Baseline Slam resets the swing (18s cooldown; the Arms
   talent Improved Slam removes the reset); hunter abilities no longer clip Auto Shot.
4. **Carry-over state.** Combo points stay on a target when you switch (rogue, feral).
5. **Reactive triggers.** Overpower via dodge or Bloodthrill (main-hand hits on your Rend
   target), Victory Rush on Victorious, Fingers of Frost / Frostbite for Ice Lance,
   Maelstrom Weapon at 5 stacks.
6. **Upkeep changes.** Warlock Curse of Agony / Doom are now Banes and stack with a curse;
   Judgement no longer consumes the seal.
7. **Mechanics.** DoTs and HoTs can crit; crits give +100% rage; mana regen is continuous
   (no 2s ticks) with the five-second rule kept; hit and crit are single stats.
8. **Level-cap changes.** During the level-30 beta, Mortal Strike, Whirlwind, Shadowform,
   Shadow Word: Death, Light's Vigil and most capstones were learned past the cap. Recheck
   each spell against the current client before carrying that conclusion into a launch list.
9. **Addon rules.** Midnight API with secret values (as measured); built-in damage meter and
   Cooldown Manager, the latter without spell-rank support yet.
