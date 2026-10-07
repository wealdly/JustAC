# Forever engine design

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

- Primary source (found 2026-10-07): **ElliotWood/Forever**, an MIT-licensed wowsims fork
  with 49 Forever-native rotation files (`ui/specs/<class>/<spec>/apls/*.apl.json`), all nine
  classes, level 60, Forever spell ids at max rank, structured conditions. Its condition
  vocabulary maps onto our gates almost one to one: `auraIsActive` -> `buff`,
  `auraNumStacks` -> `stack` (own auras) or `delegated` (target debuffs), `dotIsActive` ->
  `dot`, `isExecutePhase` -> `execute`, `numberTargets` -> the `st` / `cleave` / `aoe` tier,
  `currentRage` / energy -> `power`, `spellTimeToReady` -> `cd`, `spellCastTime` and fight time
  remaining -> `delegated`. Item and trinket entries are skipped. IMPLEMENTED 2026-10-07:
  `tools/gen_forever_rotations.py` (vendored sources in `tools/forever-apl-src/` with
  `UPSTREAM_COMMIT`; rule tests in `tools/test_forever_rotations.py`) writes
  `Data/ForeverRotations.lua`: 28 trees across the 9 classes, the full MIT notice embedded
  (tools/ is not packaged). Fight-length conditions fold under a "fight goes on" assumption;
  the tree -> source-file mapping (e.g. Arms = `dps_battle`, Fury = `dps_reck`, Holy and
  Discipline priest = `smite`) is the `TREES` table. Not in the TOC yet: it registers through
  `RotationImport.RegisterForever`, which phase 4 adds.
- Fallback: `tools/simc-apl-forever/<class>_<tree>.simc`, SimC syntax, hand-authored from the
  public guides (`Documentation/forever-guides/`), for what the sim lists do not cover: the
  beta's level range and each class's `<class>_default` list for characters with no talent
  points. The sim lists are written for level 60; below that, entries the character does not
  know drop at runtime, which is what makes them usable while leveling at all.
- Checked by `tools/gen_forever_rotations.py`, using the learnability rules in
  `tools/check_forever_apl.py` (every token must be learnable by the class on
  Forever; exit 1 otherwise).
- Generated into `Data/ForeverRotations.lua`, registered through the existing
  `RotationImport.RegisterGated`, keyed `<CLASS>_F` with one list per tree:
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

## 6. Choosing the list (talent trees)

Forever has one spec id per class; the guides' Arms / Fury / Protection are trait GROUPS of
that spec's tree. The engine picks the group with the most points spent:
`C_ClassTalents.GetActiveConfigID()` + `C_ClassTalents.GetTraitTreeForSpec(specID)` +
`C_Traits.GetGroupDisplayInfoByTreeID` / `GetGroupCurrencyInfo` (probe section H, the same
reads Forever's talent frame uses). Re-evaluated on `TRAIT_CONFIG_UPDATED` / level-up, out of
combat. No points spent: the class `default` list. A player's own list always wins, as it
does today. Group ids map to tree names through `displayName` once, recorded in the data.

## 7. Gates

Inherited, evaluated by the existing code:

- `execute` / `health`: target health threshold curve.
- `power` / `resource`: power threshold curve; usability for "can afford this".
- `buff` (own buffs): buff window from own-cast observation with the spell's duration.
- `dot` (own DoTs on the target): `DotTracker`, cast observation. Its
  `IsAuraFilteredOutByInstanceID` bridge needs an instance id, which Forever denies in combat,
  so on Forever the observation half carries it alone (recast / target swap / expiry by
  duration). Accepted ceiling: a dispelled or overwritten DoT reads as still up.
- `cd`, `stack`, `stealth`: as retail. Target debuff stacks (Sunder Armor to 5) are unreadable:
  `delegated`, order only.

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
