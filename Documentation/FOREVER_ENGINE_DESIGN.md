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
| GCD | reference spell 1283885's cooldown, plain in combat (`GetGCDReferenceSpell`) | lookahead; replaces the missing 61304 |
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
- Core rules (2026-11-15): after the class adaptations, the generator applies a few general,
  data-driven damage principles to every tree; class and spec quirks stay in the small
  `EXTRA`, `REGATE` and `generalize_entries` tables. A combo-point finisher that applies damage
  over time needs at least four points unless its source gates points. In a ranged tree
  (`RANGED_TREES`), attacks with a melee maximum range trail the ranged attacks. Outside tank
  trees an absorb shield moves behind the damage abilities, ahead of a trailing wand. A
  rage/energy threshold above 100 reads as 90 ("near the cap") instead of never firing.
  A point-blank attack (no range of its own; every enemy effect a caster-centred area or
  cone) gets a `near` gate at its data radius (Holy Nova, Consecration, Frost Nova, Thunder
  Clap, Whirlwind, Cone of Cold), since the game reports no range for it and the
  out-of-range sink never moves it; casters rarely own a probe short enough to prove
  "within", so an unproven distance never blocks. A spell restricted to targets below 20%
  health (`SpellAuraRestrictions.TargetAuraState` 2: Execute, Hammer of Wrath) gets the
  execute gate. These two gate rules run after tier selection, which treats an ungated
  entry as the general fallback. Hellfire's distance stays in `REGATE` (it burns from a self
  aura the data does not mark as an area). Magma Totem's radius belongs to the totem, so it
  has no derived gate. A stack requirement on a buff whose every effect only shortens cast
  time or cost (Maelstrom Weapon) is marked `castOnly`.
- Pull opener (2026-11-15): before a pull nothing can push a cast back and its cast time
  costs no fight time, so any ready list entry with a cast time and a direct-hit estimate is
  an opener, with its `castOnly` requirements waived. The biggest estimated whole damage
  leads (the hit plus every tick of a damage over time it applies, from spell data), with
  no cast-time penalty; one unknown estimate keeps list order. The in-combat weapon
  comparison still prices only plain hits, by cast time alone: Forever global cooldown
  timing under haste is unmeasured. Instants keep their list
  rank: they cost the same GCD in or out of combat. An opener skips the weapon comparison,
  which resumes in combat. This replaced a hand-listed per-class pull table.
  The converter also reads `auraIsInactive`. The one bespoke tweak from the same audit gates
  Shadowburn to targets below 20%. `tools/test_forever_rotations.py` checks each rule on the
  generated data. Target-count tiers still depend on the engaged-enemy count, which is the
  main open gap: see [FOREVER_COMBAT_SIGNALS.md](FOREVER_COMBAT_SIGNALS.md#enemy-context-membership-is-not-tanking-or-proximity).
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

The queue is a damage queue whatever role the player plays, so a class has several lists only
for its talent STYLES: each tree's list is that style's damage order. Tank lists drop threat
and mitigation presses (`TANK_ONLY` in the generator); healer pins are the guides' levelling
damage. Tank and healer play belongs to the defensive queue and preparation, which read the
same installed tree (Righteous Fury, a Protection seal). No group role or size is read.

### Damage-only queue

Every entry in a Forever list, and every spell that joins the pool as a filler, must be there
for its damage. Guides and sims mix in utility, and each addition looks reasonable on its own,
so this is the rule to hold the line on:

| Kind | Examples | In the damage queue? |
|---|---|---|
| Damage, including a damaging spell with a slow or root as a side effect | Thunder Clap, Cone of Cold, Hamstring | Yes |
| A debuff that raises the damage the target takes | Sunder Armor, Faerie Fire, Curse of the Elements, Hunter's Mark | Yes (counts as damage) |
| A slow, root or snare whose job is control | Frost Nova | No: the player's |
| Mitigation or threat on the enemy | Demoralizing Shout, Demoralizing Roar, taunts | No: defensive queue for tanks |
| Healing, including healing debuffs | Vampiric Embrace | No: defensive queue |
| Crowd control | Polymorph, Sap, Fear | No: the player's |

Two consequences:

- A damaging spell never waits on its own side effect. A refresh condition on a debuff that
  deals no damage over time (Thunder Clap's slow) only delays the hit; the generator drops it
  (`holds_hit_for_side_effect`). Refresh conditions stay for damage over time, where an early
  recast loses ticks.
- A guide or sim listing a utility press is not a reason to keep it. Remove it from the lists
  and the pool (`NOT_DPS`, `TANK_ONLY`) and note it in the tree's guide file.

The one narrow exception is the ranged opener on a melee target: a ranged class pulling a
mob that will close to melee may open with a damaging slow (a mage's Frostbolt while the mob
closes). That belongs to opener and pull handling, decided from readable range and combat
state, never to a list entry added for the slow. Explicit non-pulling target setup
(`foreverTargetSetup`, Hunter's Mark) is separate and must also raise damage.
`tools/test_forever_rotations.py` asserts the removed utility presses stay
out; extend that check when another is removed.

The reverse case is a target that holds its range (a caster or an archer). There the slow
is worth nothing, so a slowing filler (generated `SLOWING_ATTACKS`: Frostbolt) gives its place
to the strongest pool attack that does not slow and that the list does not name (Fireball for
an untalented mage), when it is ready, castable and in range (`_StageRangedFiller`). Evidence
only, per target, in combat: the target casting while out of melee reach, or a lone target
still hitting the player from out of reach after a few seconds. A target that reaches melee
returns to the list's order. Session captures show `holdsRange=` and `rangedSwap=` in
`queueContext`.

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
    miss/resist/dodge/parry events inside the cast's result window cancel it. The window comes
    from the generated `AURA_DELIVERY` data (`SpellCategories.DefenseType`, `SpellMisc.Speed`).
    A cast with no missile reports in the same instant (0.1 seconds, either event order). A
    missile reports on arrival: from the cast to its maximum range at its speed plus 0.25
    seconds. A cast the data does not describe, or an unreadable range, keeps 0.4 seconds.
    These events lack source/spell attribution: matching is best-effort, and an unrelated miss
    can cancel an estimate. An immune result is also remembered by the target's creature id
    (from its GUID) and the spell's rank base: fighting alone with no pet, one sighting holds the spell on
    that creature id for the session (with a pet or a group the result may be theirs, so it is
    only counted); sightings on two different mobs persist in `JustACGlobal.dotImmuneNPCs` and hold it,
    and the DoT seen on such a mob (Cooldown Manager or aura instance) forgets the entry
    (`/jac inspect immunedb [clear]`). It is never generalised to a creature type.
    To compare the account's learned entries with the local Classic database snapshot, run
    `python tools/audit_forever_immunity.py --classic-db <path-to-mangos.sqlite>`.
    This is a read-only research comparison, not a database update or proof of Forever
    behavior. A matching Classic mask is a candidate; an absent mask does not establish
    that the effect lands. See [the audit procedure](DEV_TOOLING.md#auditing-forever-immunity-observations).
    Two cases are excluded: a result the cast's defense type
    rules out (a spell is never parried or dodged, a ranged attack never parried), and a result arriving
    where one of our own white melee swings is due to report: 0.3 to 0.52 seconds after its
    `PLAYER_SWING` (measured 0.34 to 0.47 over 19 swings), unless it shares the timestamp of a
    cast with no missile. Each swing takes one result. Ranged shots are not candidates: their
    result arrives after the flight. Both leave the cast open for a later result. Immunity retains the existing per-target suppression policy.
    Readable CDM state takes precedence; early removal without readable evidence can outlive
    the real aura until the estimate expires. Unknown duration uses a 12-second fallback,
    favoring overlap over a long uptime gap; known durations are not capped by that fallback.
  - Active/absent-aura prerequisites require aura evidence, not an unobserved cast or an
    estimated expiry. Other-aura remaining-time comparisons retain their operator/constant
    but remain unknown: presence cannot prove seconds or stacks. Own refreshes have no
    carry-over on Forever, so a DoT or HoT returns its refresh lead before expiry
    (`BlizzardAPI.GetPeriodicRefreshLead`): its cast time, so the recast lands as the last tick
    goes, plus one global cooldown for a stacking aura (generated `STACKING_AURAS`), whose drop
    loses every stack. Instant non-stacking effects still return at expiry. The lead reads the
    engine timer when an instance is held, else the cast estimate, including while a
    Cooldown Manager icon reports the DoT active. Forever self HoTs (generated
    `PERIODIC_HEALS`) use the same lead in the redundancy filter.
  - Relative target level qualifies only slow target-only payoffs, such as a very late
    periodic tick or an armor reduction. A normal/trivial target at least one level below
    the player is not considered worthwhile for that payoff unless other positive fight
    evidence applies; one or more levels above qualifies it. Equal, unknown and skull-level
    reads do not force either result. This is deliberately not a blanket duration-based
    DoT veto: ordinary damage-over-time priorities such as Rend, Corruption and Shadow
    Word: Pain are not classified as slow payoffs, so a lower-level target cannot suppress
    a class's core periodic damage through this rule. Damaging spells are not delayed just
    because their own damage-over-time rider has a long duration.
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
  JustAC's own landed-stack count can still pace the applicator. In a solo ordinary fight,
  Protection Sunder is suggested for one application; grouped, instance, elite or +1-level
  contexts can allow further applications up to the spell's generated stack maximum.
  This affects only the applicator's own generated stack gate, not imported/custom lists.

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
- `cast`: the spell's current cast time (`GetSpellInfo`, highest known rank, read each
  build) against N seconds: the sims' `spellCastTime` comparisons (a proc or talent that
  makes the cast fast). Unknown or secret is no opinion. Whether a proc such as Nightfall
  shows in `castTime` still needs an in-game check (`/jac inspect simcgates`, `cast time ... [castTime=]`).
  Where the launch guide keeps a spell without the shortening talent (Affliction Immolate,
  Arms Slam), `REGATE drop_cast` removes the condition and the entry stays delegated.
- Priority on a shared power (`SpellQueue._HoldForPriority`, lists without a game pick for the
  reserve): a lower-ranked spender on the same continuous power waits while a higher-ranked one
  is ready and short only of its cost, and also while a higher-ranked one comes off cooldown
  within `_RESERVE_GCDS` (2) GCDs, unless both can be paid (`_AffordableWithin` with the other
  cost spent first; only income known to be due counts, so none for rage). An unreadable
  threshold never holds. This is the guides' "pool rage as Mortal Strike comes off cooldown",
  and Thunder Clap's rage in a pack.
- Own-DoT time left: a `debuff` gate with `op` and `n` (or `ncast`, a spell's live cast time)
  on a DoT this class casts compares its time left (`DotTracker.IsTimeLeftBelow`): the
  engine's timer when an instance is held, else the cast estimate for a known duration; a DoT
  known gone has none left; never cast on this target, immune or no timer is unknown.
  Recovers Ferocious Bite (Rip 3+ seconds), Shred's Rip branches, Ghostly Strike (Garrote)
  and Amplify Curse (Curse of Agony). Other auras' time left stays unknown.
- Own target stacks: a target `stack` gate whose stacks do not read falls back to
  `DotTracker.GetOwnStacks`, my landed applications of a generated stacking aura (Sunder
  Armor; stack-gated target auras are observed, not DoTs), capped at its maximum, renewed while
  the last runs and reset after it lapses. A miss reported for a cast takes back only that
  stack. Other players' stacks and chance-based stacks (Improved Scorch, Winter's Chill: a
  different aura id from the cast) are never counted; unknown stays unknown.
- Creature-type limits: generated `CREATURE_TYPES` (SpellTargetRestrictions, enemy-aimed
  spells only) drop a spell in the redundancy filter when the target's type is known and
  outside it (`BlizzardAPI.IsSpellTypeValidForTarget`, shared with the CC check). Retribution
  lists Exorcism, and Holy Wrath for packs, on that basis. Unknown type keeps the spell.

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
- The GCD source moved from 61304 to reference spell 1283885 (bug 7, done 2026-11-17).

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
