# Forever engine design

**Historical design, not current implementation status.** One shared `main`
release now supports both clients. Use [client compatibility](CLIENT_COMPAT.md)
and current code for behavior; retain this document for rationale and provenance.

Status: proposal, 2026-10-07. Branch `forever`. Inputs: `FOREVER_PROBE_PLAN.md` (measured
signals), `FOREVER_DEAD_CODE.md` (what is dead), `tools/simc-apl-forever/` (first list).

## 1. Problem

On retail, JustAC's queue is Blizzard's pick in position 1 plus a re-ranked tail. Every
context signal (target count, range, role) is read off that pick, because the combat state
itself is secret. Forever has no pick: Assisted Combat is off (`IsAvailable` = false,
reason `WRONG_WORLD_STATE_EXPRES...`, and the AssistedCombat DB2 tables are absent from the
build). So the engine has to produce the whole recommendation itself, under the same secret
rules: Forever is restricted, and more strictly than retail (player power and target health
are secret even out of combat; every aura call throws in combat).

## 2. What we already have

The retail SimC layer is a priority-list engine in disguise:

- `RotationImport` stores per-spec, per-context (`st` / `cleave` / `aoe`) ordered entries,
  each with secret-safe gates: `buff`, `cd`, `dot`, `execute`, `health`, `power`,
  `resource`, `stack`, `stealth`, plus `any` / `all` groups and a `delegated` flag for
  conditions nothing can read.
- `tools/gen_simc_rotations.py` parses SimC APLs, flattens the call graph per target tier,
  resolves tokens to spell ids and classifies each `if=` into those gates.
- `SpellQueue`'s gate layer evaluates them in combat with the secret-safe techniques
  (readiness probe, threshold curves, usability, buff windows from own-cast observation).

On retail this layer only re-ranks positions 2+ around the pick. On Forever it becomes the
whole engine. So the dead-code pass's "SimC stack: dead" verdict is revised: the DATA MODEL,
the parser/classifier and the gate EVALUATORS are kept; only the pick-relative parts
(pick windows, pick-leads, Safe Lead, retail APL data) are dead.

## 3. Signals the engine may use (all measured in combat on Forever)

| Signal | Source | Use |
|---|---|---|
| Spell known / rank | spellbook, `IsPlayerSpell`, rank chains (section 5) | which entries exist, which id to show |
| Ready | scratch-Cooldown readiness probe, cooldown `isActive` | skip abilities on cooldown |
| Usable (resource / reactive) | `C_ActionBar.IsUsableAction`, plain | "enough rage/energy", Overpower/Revenge/Execute lit |
| GCD | a known GCD-bound spell's `isOnGCD` + its cooldown duration | lookahead; replaces the missing 61304 |
| Swing timer | `PLAYER_SWING` (`swingDuration`, `swingType`) plain; gap measured 1.82-2.00s on a 1.9s weapon | NEW: Slam / Heroic Strike / Auto Shot timing |
| Queued on-next-swing | `C_Spell.IsCurrentSpell`, plain | NEW: drop a Heroic Strike / Cleave already queued; "auto attack off" cue |
| Own casts | `UNIT_SPELLCAST_SUCCEEDED` (player) plain, `ShouldUnitSpellCastBeSecret(player)` = false | buff windows and DoT tracking by observation |
| Health / power thresholds | `UnitHealthPercent` / `UnitPowerPercent` + threshold curves (retail technique) | execute < 20%, rage >= N. VERIFY on Forever (section 9) |
| Frame booleans | LowHealthFrame, FullPowerFrame pulse, builder/spender feedback | low health, power capped |
| Combo points | `GetComboPoints` / `UnitPower(player, 4)` plain | finisher gating (rogue / feral) |
| Weapon enchant, ammo | `C_Item.GetWeaponEnchantInfo`, `C_PaperDollInfo.AmmoNeeded` plain | precombat reminders |
| Enemy count | nameplate count (retail AoE path) | `st` / `cleave` / `aoe` context |

Not available: aura state by any direct call (throws), target casts (secret), mana regen,
defense skill, `IsActiveSpell`, swing range (`checksRange` always false).

## 4. Architecture

```
            shell (unchanged)                         core (new on Forever)
  ActionBarScanner / MacroParser / FormCache   ForeverEngine.Build(b)
  UIRenderer / UIFrameFactory / overlays    <-   1 source   : list for (class, tree, ctx)
  DefensiveEngine / interrupt slot                2 resolve  : rank -> known id, drop unknown
  PrecombatEngine / RedundancyFilter              3 filter   : ready, usable, not queued,
  Options lists + spell search                                 not redundant, not blacklisted
  BlizzardAPI secret primitives                   4 gates    : RotationImport gate evaluators
                                                  5 assemble : survivors in order -> queue
```

The seam is `SpellQueue.GetCurrentSpellQueue()`: the renderer, overlays, keybind lookup and
diagnostics read its output and nothing else, so they stay untouched. On Forever its
pick-driven stages (`_StagePrimary`, Safe Lead, pick windows, `FightWindow` context) are
replaced by `ForeverEngine.Build`. The stages that are not about the pick stay as they are:
custom list override, blacklist, redundancy filter, spellbook procs, gap closer, burst cue.

Position 1 is the first surviving entry. Positions 2+ are the next survivors: "after this,
press these". With the GCD lookahead, an ability that becomes ready inside the current GCD
counts as ready, as retail already does.

The engine interface is deliberately the one retail's queue already exposes, so a later
single-repo build can put retail's pick engine and this engine behind the same seam.

## 5. Data

### Lists

- Pinned source (reviewed 2026-11-10): **MythicSim's Forever engine** and its MIT-licensed
  `presets/` mirror, pinned to engine revision
  `0bae6e2148cdc81fcc8a1151753667d990504b1a`. The mirror contains 55 `.apl.json` presets
  covering every class, with alternatives catalogued in `presets/catalog.json`. That catalog
  records its MythicSim application source at
  `sage3648/mythicsim/api/data/forever_rotations.json`, commit
  `4bf15417001a5e86ebc99cae159a09f91ff0be4b`. The engine repository is MIT-licensed; its
  `LICENSE` and `NOTICE.md` are vendored with the presets.
  The generator selects damage lists by tree; Holy Paladin and Restoration Druid/Shaman retain
  local healer damage-filler pins. The retired ElliotWood source snapshot has been replaced.
  Source APLs use level-60 spell ids and structured conditions. Their condition vocabulary
  maps onto our gates almost one to one: `auraIsActive` -> `buff`,
  `auraNumStacks` -> `stack` (own auras) or `delegated` (target debuffs), `dotIsActive` ->
  `dot`, `isExecutePhase` -> `execute`, `numberTargets` -> the `st` / `cleave` / `aoe` tier,
  `currentRage` / energy -> `power`, `spellTimeToReady` -> `cd`, `spellCastTime` and fight time
  remaining -> `delegated`. Unsupported conditions remain delegated; unlearnable and
  non-spell actions are skipped. `tools/gen_forever_rotations.py` adapts the selected presets
  through the existing secret-safe gates and local leveling additions:
  `tools/forever-apl-src/` contains the exact mirror and notices, with the engine pin in
  `UPSTREAM_COMMIT`; `tools/test_forever_rotations.py` covers converter rules. The generator writes
  `Data/Forever/Rotations.lua`: 28 trees across all 9 classes. The full MIT notice is embedded
  because `tools/` is not packaged. Fight-length conditions fold under a "fight goes on"
  assumption; `TREES` records each selected preset and the retained local pins. The
  independently published `wowsims/forever` APL tree was reviewed but not used: it did not
  provide complete class coverage in the available JSON format.
- Mixed builds: Forever has one class spec key, not separate specializations for each tree.
  `RotationImport.PickTree` currently installs only the list for the tree with the most points;
  hybrid allocations therefore use their dominant-tree list. A better extension may be a small
  catalog of curated archetype builds, with each user's allocation matched to the closest
  archetype by a similarity score over selected talents and points spent. That is a profile
  selection policy, not a reason to blend several lists: selecting one coherent profile avoids
  duplicate or contradictory entries. Weight signature-defining talents more than incidental
  point differences, and use only talent signals verified in-game. Tree labels and point values
  still need live confirmation with `/jac inspect forever`; do not implement matching until the
  signal is confirmed and the archetype references and tie-break behavior are defined. The
  guide evidence and extraction workflow is in [forever-guides/README.md](forever-guides/README.md#guide-to-archetype-workflow).
- Fallback: `tools/simc-apl-forever/<class>_<tree>.simc`, SimC syntax, hand-authored from the
  public guides (`Documentation/forever-guides/`), for what the sim lists do not cover: the
  beta's level range and each class's `<class>_default` list for characters with no talent
  points. The sim lists are written for level 60; below that, entries the character does not
  know drop at runtime, which is what makes them usable while leveling at all.
- Checked by `tools/gen_forever_rotations.py`, using the learnability rules in
  `tools/check_forever_apl.py` (every token must be learnable by the class on
  Forever; exit 1 otherwise).
- Generated into `Data/Forever/Rotations.lua`, registered through
  `RotationImport.RegisterForever`, keyed `<CLASS>_F` with one list per tree:
  `["WARRIOR_F"] = { default = {st=...}, arms = {st=..., aoe=...}, fury = ..., protection = ... }`.

### Generator

Extend `gen_simc_rotations.py` with a Forever profile rather than writing a second parser:
the parser, call-graph flattening and gate classifier are the valuable, already-debugged
part. The profile swaps:

| | retail | Forever |
|---|---|---|
| CSV folder | `Documentation/wow_spell_csv` | `Documentation/wow_spell_csv_forever` |
| APL folder | `tools/simc-apl` | `tools/simc-apl-forever` |
| token universe | spec spells via `SpecializationSpells` (absent on Forever) | class-learnable `SkillLineAbility` rows, AcquireMethod 3 excluded (the rule `check_forever_apl.py` already implements) |
| emitted id | the spell | rank 1 of the chain |
| key | `CLASS_N` | `CLASS_F` + tree |

### Ranks

The generator also emits `rankChains[rank1] = { rank1, rank2, ... }` from `SupercedesSpell`.
At runtime the engine shows the highest rank the player knows (`IsPlayerSpell`), and a
curated id anywhere in a chain maps to its family. This is the only place ranks are handled;
everything downstream sees one id per ability. Hotkey lookup already matches by name (probe
H14 confirms across ranks once a character has two).

#### Intentional downranking (future requirement)

Forever players may deliberately use a lower learned rank for a secondary or
tertiary effect, such as a slow, rather than for maximum damage or healing.
Treat this as a legitimate player choice, not an outdated spell to upgrade.
This is a future design requirement, not a claim that explicit rank selection
is currently preserved through every queue, macro and display path.

Future rank-selection work must distinguish ability-family identity (shared
classification and aura matching) from the exact rank the player intends to
cast. An automatic damage default and an explicitly chosen utility rank need
not resolve to the same spell ID. Review custom lists, action-bar and macro
bindings, display/click targets, resource checks and saved overrides together
before adding support, so a lower-rank choice is not silently rewritten or
paired with a different rank's hotkey.

Do not automatically choose a lower rank merely because an effect is named
"slow" or appears in the same family. Verify the matching Forever rank's
effect, cost, duration and applicable level/target restrictions first; shared
names do not establish equivalent utility. Preserve Retail behavior and test
explicit rank choices alongside ordinary automatic damage priorities.

## 6. Choosing the list (talent trees)

Forever has one spec id per class; the guides' Arms / Fury / Protection are trait GROUPS of
that spec's tree. The engine picks the group with the most points spent:
`C_ClassTalents.GetActiveConfigID()` + `C_ClassTalents.GetTraitTreeForSpec(specID)` +
`C_Traits.GetGroupDisplayInfoByTreeID` / `GetGroupCurrencyInfo` (probe section H, the same
reads Forever's talent frame uses). Re-evaluated on `TRAIT_CONFIG_UPDATED` / level-up, out of
combat. No points spent: the class `default` list. A player's own list always wins, as it
does today. Group ids map to tree names through `displayName` once, recorded in the data.

Build selection and combat-condition evaluation are separate. The current selector uses the
dominant tree, not archetype similarity matching. A future curated archetype selector would
use verified talent allocation and signature talents to choose one coherent list, not blend
several lists. Combat signals such as CDM aura activity then evaluate supported conditions
within that list; they do not identify the character's build. See the
[guide-to-archetype workflow](forever-guides/README.md#guide-to-archetype-workflow).

## 7. Gates

Short-duration self-buffs needed before a pull may opt into the shared maintained
group `preparation` policy. Forever seals and other combat preparation use this missing-only reminder: any
readable active member satisfies it, regardless of expiry or a different suggested
member. Missing groups reuse existing queue preference/default selection and the
normal pre-combat visibility controls. They do not use the long-buff refresh
window. Their cast settle latch applies only outside combat, so a buff consumed
just after the pull can be reapplied immediately through the unchanged combat
rotation. Preparation membership does not classify the spell as combat-suppressed
upkeep or remove it from custom priorities.

Groups can declare a `tree` (Forever) or `spec` (Retail), and `form` groups require
confirmed caster form and an unmounted player. This never switches away from an
intentional form. `defaultByTree` supplies a context-specific fallback only when
no alternative is active or explicitly requested. New preparation requires
confirmed usability and readiness; Battle Shout therefore does not request
unavailable rage or invent a Bloodrage sequence.

The preparation member index stores each owning group for all applicable ranks,
so a visible alternative routes the whole group to pre-combat. Both the primary
and tail DPS paths respect that visible offer; combat and hidden/disabled
pre-combat surfaces retain their existing DPS fallback. The defensive builder
places preparation before consumables to avoid crowding it out. Paladin rites
reuse the existing weapon-enchant path, where any existing enchant is preserved.
Warrior stance defaults follow the installed tree but never replace an active
stance. Shield enchants, ally-target preparation, blessings and ambiguous
Forever Cat/Bear role choices remain outside these defaults.

Inherited, evaluated by the existing code:

- `execute` / `health`: target health threshold curve.
- `power` / `resource`: power threshold curve; usability for "can afford this".
- `buff` (own buffs): buff window from own-cast observation with the spell's duration.
- Target debuffs require separating observation from entry policy:
  - Queue suppression uses `DotTracker.IsDotActiveOnCurrentTarget`. On Forever, a readable
    Cooldown Manager aura verdict takes precedence over cast timing, except for the existing
    immunity policy. Relevant aura entries must be tracked in enabled, updating buff/bar
    viewers. Moving a cooldown-only entry there does not make it aura-presence evidence.
    When CDM cannot answer, instance/engine evidence and cast-time estimates remain fallbacks;
    an estimate can outlive an early removal and is not confirmed aura presence.
  - Forever imports emit `debuff` conditions. `neg` preserves absence versus presence;
    `refresh` identifies the entry's own maintenance policy. A separate generated target-aura
    observation table includes explicitly maintained nukes/debuffs without making them
    unconditional DoT sinks. A fire totem's refresh condition uses its existing slot signal.
    Target-aura references share rank expansion in the defaults generator, excluding summons.
    The tracker shares eligibility checks while keeping observation-only spells out of
    unconditional DoT suppression.
    Queue categorization and subsequent burst cues share a pooled aura-read context
    cleared on each categorization pass. Buff and target-aura policies reuse raw CDM
    evidence, including unknown results, without caching policy-specific cast estimates.
    Self-buff evidence is also shared independently of each gate's fallback duration.
    Diagnostics and callers without a context continue to read live; no viewer frame
    references or timed gameplay caches are retained.
  - Own refreshes may use the bounded cast estimate when CDM/instance evidence cannot answer.
    A successful cast starts the spell rank's projected duration. Forever target `UNIT_COMBAT`
    miss/resist/dodge/parry events within 0.4 seconds cancel it, in either event order.
    These events lack source/spell attribution: matching is best-effort, and an unrelated miss
    can cancel an estimate. Immunity retains the existing per-target suppression policy.
    Readable CDM state takes precedence; early removal without readable evidence can outlive
    the real aura until the estimate expires. Unknown duration uses a 12-second fallback,
    favoring overlap over a long uptime gap; known durations are not capped by that fallback.
  - Active/absent-aura prerequisites require aura evidence, not an unobserved cast or an
    estimated expiry. Other-aura remaining-time comparisons retain their operator/constant
    but remain unknown: presence cannot prove seconds or stacks. Own refreshes conservatively
    wait for expiry rather than attempting an unverified early-refresh window.
  - The legacy `dot` gate retains its target-health policy. The same policy applies to
    `debuff` refreshes, never positive prerequisites: pure applications yield below 35% target
    health, while upfront damage remains useful. Proc vetoes require confirmed aura evidence
    rather than a cast estimate. Always Show pins bypass refresh suppression.
  - Measured on Forever build 1.60.1.70888 on 2026-11-10: Corruption and Immolate supplied
    readable CDM active/inactive states in combat, including target-switch observations.
    Session `20261110-095700-1` captured Corruption becoming inactive on the same target before
    combat ended, matching the tester's visible expiry. Immolate remained active until target
    loss, so that session did not validate its natural expiry. Aura-instance binding remained
    unavailable. These results do not establish duration/stack reads, every DoT, or Retail
    behavior. See [capture semantics and controls](FOREVER_COMBAT_SIGNALS.md#priority-condition-coverage).
- `cd`, `stack`, `stealth`: as retail. Target debuff stacks (Sunder Armor to 5) are unreadable:
  `delegated`, order only.

Spellbook proc events feed candidates into the shared tail categorizer, not directly into
display slots. Both event and overlay promotions respect confirmed contextual vetoes,
minimum casting resources, readiness, lockouts, explicit holds and automatic burst holds.
A proc may still override soft imported resource/stack preferences. The master proc-order
switch and per-spell opt-outs apply to both paths; Forever opt-outs match the whole rank
family. Candidates added only by a proc are omitted when ineligible rather than becoming
new ordinary rotation entries.

**Holy Fire correction (offline regression, Forever data 1.60.1.70888):** both Holy and
Discipline now observe Holy Fire's aura independently of its upfront damage share. Its
own refresh condition yields to Smite while a cast estimate or readable aura evidence says
it is active; it returns after expiry. No cooldown is invented: the matching CSV has zero
recovery/category recovery. The same entry-scoped rule handles Protection Thunder Clap
without suppressing its unconditional damage entries in other trees. Scorch's stack/remaining
time condition remains unknown rather than being reduced to aura presence. Regression tests
cover all Holy Fire ranks and distinguish a one-icon repeated lead from genuinely missing
alternatives in a wider queue. These offline controls do not establish live Priest API
readability; no live Priest capture/settings have been verified.

New on Forever:

- `queued`: the entry is an on-next-swing ability (`IsCurrentSpell` true): drop it, it is
  already pressed.
- `swing`: time to the next main-hand swing below / above N seconds, from the last
  `PLAYER_SWING` timestamp + `swingDuration`. Needed from the start: baseline Slam still
  resets the swing timer (18s cooldown; the Arms talent Improved Slam removes the reset), so
  the Arms list casts it right after a swing unless the talent is known.

Unreadable conditions stay in the source and classify as `delegated`: the entry keeps its
priority position with no gate, which is how the retail pipeline already fails safe.

## 8. What changes elsewhere

- `FOREVER_DEAD_CODE.md` Tier 1 "SimC stack" splits: keep `RotationImport`, the generator,
  and the gate evaluators; delete `Data/SimcRotations.lua`, `Data/AssistedCombatOrder.lua`,
  pick windows, pick-leads, Safe Lead and the SimC probes tied to them.
- `BlizzardAPI.GetRotationSpells`' action-bar fallback stays as the pool for the options
  tools; the live queue comes from the engine.
- Healer handling keys off the group role (`UnitGroupRolesAssigned`) or a setting, because
  every Forever spec reports DAMAGER.
- The GCD source moves from 61304 to a known GCD-bound spell (bug 7).

## 9. Open questions (each has a probe)

1. Talent groups: do names / points read as expected? `/jac inspect forever` section H, on a
   character with talent points.
2. Threshold curves on Forever: do the health and power gates still produce known-correct
   answers? `/jac inspect validate arm`, in and out of combat.
3. Ranks: does hotkey lookup find a low rank and the top rank? Section D `key=` / `keyTop=`,
   on a character with two ranks.
4. Enemy count: does the nameplate count work on Forever's camelot nameplates? `/jac inspect
   enemies` with a pack.
5. Reactive abilities: does `IsUsableAction` flip for Overpower after a dodge? Section D, on a
   level-12+ warrior.

## 10. Phases

1. Fix the behaviour bugs from the dead-code pass, including the GCD source.
2. Delete the revised dead list.
3. Generator Forever profile, `Data/ForeverRotations.lua`, rank chains; warrior `default` +
   `arms` first.
4. `ForeverEngine` behind the `GetCurrentSpellQueue` seam; tree selection. DONE 2026-10-07,
   without a new module: the existing tail pipeline already ranks a pool by imported
   priority, gates it and fills slot 1 when there is no pick, so phase 4 became
   - `RotationImport.RegisterForever` + a single `Rot(specKey)` reader that installs the
     tree with the most talent points (class default with none; Feral -> bear list in bear
     form), re-picked on `InvalidateLookup` (SPELLS_CHANGED) and druid form changes;
   - rank chains: every rank resolves to its entry, insertions use `HighestKnownRank`;
   - pool = bar spells + every known list ability (delegated included on Forever),
     deduplicated by rank family (`ForeverPool`, `WithAdditions`);
   - `SpellQueue.LeadMode` = "mylist" when Assisted Combat is unavailable, so what we
     cannot time never leads;
   - `known` gate evaluator; `swing` / `tick` pending phase 5 (`test_gate_groups.py`).
   Tests: `tools/test_forever_engine.py` (mutation-checked), `test_gate_groups.py`.
5. `queued` and `swing` gates; confirm inherited gates with the open-question probes.
6. Remaining classes' lists; regenerate the other `Data/` tables from the Forever CSVs.

Each phase is testable on its own: phases 1-2 in game with the existing queue, phase 3 with
the generator's own report and `tools/test_forever_rotations.py`, phases 4-5 with the probes above.
