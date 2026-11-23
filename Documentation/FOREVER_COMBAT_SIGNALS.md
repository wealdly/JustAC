# Forever combat signals: high-value research

Reviewed 2026-11-10. Research/debug capture only: no new recommendation behavior
or combat validation.

## Evidence and scope

- Forever source: Gethe/wow-ui-source, branch `forever`, build **1.60.1.70862**,
  revision `9dc84f0d3bbae1768ac3405b3716000bd93eda06`.
- Retail comparator: the same upstream, local `live` mirror, build **12.1.5.70783**,
  revision `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`.
- These are inspected local snapshots, not a claim that either mirror, installed
  client or CSV snapshot is the latest published build. No source refresh performed.
- Source links below are pinned references, not adopted or redistributed code.
  Any later code adoption still requires the repository's licensing and
  attribution review.

**Existing** means a JustAC consumer exists, not that every class/context was tested.
**Candidate** means source supports an experiment, not a usable combat signal.
**Display-only** means the engine can render the answer but Lua cannot branch on it.
Earlier measurements remain tied to their recorded client/build.

### Tracked-bar timing and caster pushback investigation (2026-11-14)

Additional source review uses Forever **1.60.1 (70938)**, revision
`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`; the Retail comparator above is unchanged.
These are source contracts and offline probe tests, **not new live measurements**.

The existing health/power threshold curves and zero-gate can answer bounded
questions without recovering exact values. Target below 20% is already available
to the queue. Mana thresholds can supply conservation context. Neither alone
proves that a melee swing will finish a target or that casting is inefficient.

The same duration predicates require a usable duration object. A plain CDM aura
instance does not override `GetAuraDuration`'s `RequiresUnitAuraAccess`.
`LuaDurationObject:SetTimeFromEnd` and numeric `LuaCurveObject:Evaluate` both
declare `SecretArguments = AllowedWhenUntainted`: do not assume addon code can
feed raw secret bar timing into them. An ordinary duration object holding secret
contents is different from passing secret numbers as arguments.

`signal.viewers` now compares independent routes per tracked item:

- Static spell/override identity from `GetCooldownInfo`, never `GetSpellID`.
- Viewer shown/visible/editing and item active/visible/preview states.
- Raw expiration/duration, bar value/max and timer/application text, each classified.
- Aura-instance duration access beside native `Bar:GetTimerDuration()` access.
- Object predicates, raw remaining/total classification, bridged activity, the
  existing scratch activity test, and fixed below-25%-remaining / below-1-second
  questions. These are bounded decisions, not a reconstruction of remaining time.

The reviewed bar mixin uses `SetMinMaxValues` / `SetValue`, not `SetTimerDuration`.
Consequently, a returned native timer object might be empty or unrelated.
Require active-above-threshold, near-expiry, refreshed and expired controls before
trusting either route. A constant true below-1-second answer on an empty timer is
not success. Hidden viewers, Edit Mode previews and absent entries are not live
timing evidence. This capture never refreshes, writes to or rearranges Blizzard
viewers; each buff viewer remains bounded to 12 items.

`signal.player.pushback` records actual player `UNIT_SPELLCAST_DELAYED` and WOUND
events, cast/base cast times, the existing target-below-20% predicate, target melee
range, target-of-target context and an already-running melee swing. Nameplates
targeting the player are explicitly **not confirmed hit sources**; WOUND counts
are damage events, not distinct melee attackers. Damage amounts are not read.
Event evidence is capped at 120 per kind per combat phase. Incoming hits do not
trigger full-session synchronous sampling. These registrations exist only during
a Research-enabled capture and are removed by the normal stop lifecycle.

Ordinary Forever filler is selected during categorization, not promoted by a
second weapon stage. Prefer the best learned, usable, confirmed-in-range automatic
attack until a supported cast offers at least 1.20 times its baseline DPS. This
single fixed margin favors free attacks without mana scoring, running-state
thresholds or sticky timers. Melee must already have confirmed shared melee reach;
equal weapons favor the wand. Meaningful normal priorities, procs, DoTs, channels,
required-stack casts, custom lists and exact ordering remain protected.

The spell baseline comes from the current Forever CSVs, indexed by exact learned
rank: simple single-target direct damage, capped per-level gain and its spell-power
coefficient. Triggered, periodic, resource/AP-scaled and unsupported scaling
formulas are omitted. Plain level, school spell-power and equipped-weapon DPS
are captured out of combat while a live hostile target is selected. Refresh is
limited to once per second across queue builds. Weapon damage ranges come from
`UnitRangedDamage` or `UnitDamage`, including both hands; attack intervals come
from `UnitAttackSpeed` (third return for ranged), following the client's damage-panel
formula but retaining raw rather than rounded display bounds. Do not reapply
damage bonuses, percentages or the offhand penalty. One-/two-handed and unarmed
melee use the main-hand rate; dual wield adds the separately timed offhand rate.
A shield or held offhand with no attack interval adds no damage. Wands, bows,
guns and crossbows use the ranged rate only with a supported repeat attack and
the required equipment, live usability and confirmed range. Manual shots and
thrown attacks are not treated as sustained repeats.
The snapshot is retained in memory through combat as an explicitly
labelled pre-combat baseline, not a reading or reconstruction of hidden current
stats. Combat buffs/debuffs can make actual damage differ. Equipment changes,
world entry, combat exit, form, level and talent changes invalidate the snapshot.
An invalidated or missing snapshot keeps the usual order until another readable
out-of-combat hostile-target pass. Nothing is persisted across reloads.

The divisor is the same spell's observed pushed-back cast duration, or its fresh
`GetSpellInfo` cast time for the normal comparison. Every positive readable cast
duration is eligible, including hasted casts below 1.5 seconds. Ignoring a longer
GCD overestimates spell DPS, so a cast must clear the 20% margin even with that
optimistic estimate; this does not invent a GCD. Zero-time instants remain outside
the comparison. Instant, on-next-swing and unsupported physical/AP/weapon-scaled
abilities can add damage alongside autoattacks and retain their normal priorities,
not a blanket weapon-versus-ability replacement test. These
are baseline estimates, not predictions of crits, talents, target armor/resistance
or final damage. Never recover secret numbers or present the stored baseline as
current combat stats.

The comparison requires a live hostile PvE target and, in combat, one confirmed
enemy. A confirmed running ranged repeat can retain filler selection while the
initial enemy count is still zero; zero is not treated as proof of single-target
combat. Confirmed packs, boss/PvP and AoE/cleave contexts keep normal ordering.
Supported zero-base-cooldown filler stays in a stable filler bucket through
temporary shot-cycle readiness pulses. Real range, resource, gate, hold and
loss-of-control failures still sink it. A usable, confirmed-in-range running
automatic attack is ongoing damage and cannot alone justify WAIT.

The observed-pushback response retains its five-second window and short-cooldown
instant preference, but no longer selects weapons separately. The filler comparison
charges each cast its cast time, plus expected pushback, plus its mana cost divided by
`GetManaRegen` base regeneration (per second) captured with the pre-combat damage baseline
(the live read was nil in combat on 2026-11-16). Expected pushback comes from the rate of
player `UNIT_COMBAT` WOUND hits without the ABSORB flag over the last 3 seconds and the
measured per-cast steps (1.0, 0.8, 0.6, 0.4 s, the first capped by cast progress); see the
measured section below. Pushback resistance is not seen. Measured `delayTimeMs` was rejected
as the input: it arrives after the pushed cast and stops while wanding. A pushed cast moves
start and end together, so `endMS - startMS` never shows the delay.
An unreadable cost or regeneration leaves the mana part out.
`weaponComparison` records its baseline, fixed margin, comparable spell, filler
choice and damage rates. It describes the filler bucket, not an override of a
protected priority ahead of it. `pushbackComparison` records the instant-response
decision and choice. Unknown inputs leave the usual priority intact. Automatic
attack hotkeys accept direct buttons and macros containing only that attack,
including `/use !Shoot` as well as `/cast !Shoot`.
Mixed casts/items, sequences and opaque commands do not qualify; explicit hotkey
overrides remain authoritative. Proven attack-only macros can also supply running
action state without weakening the direct-slot-only cooldown query.
Live controls must include weak/strong wand,
in/out-of-melee reach, pushed/non-pushed casts, equipment swaps, and unreadable
stats before treating these estimates as validated client behavior.

For a focused live control, manually place a currently learned short buff in
Tracked Bars, keep that viewer shown and leave Edit Mode. After `/reload`, run
`/jac inspect start`; capture absent, active, refreshed/consumed and expired states,
including in combat. Also capture caster pulls with observed pushback, single
versus multiple enemies attacking, and low-health targets with melee already
running. Finish with `/jac inspect stop`, then `/reload` to flush SavedVariables.
Record which controls actually occurred. No new finishing policy, automatic
attacks, cast cancellation or recommendation suppression is enabled by this work.

#### Stoneform capture: older loaded probe (2026-11-14 12:02)

Session `20261114-120226-1`, Forever **1.60.1.70938**, recorded 23 samples,
zero combat pulls and zero sampler failures. Stoneform `20594` succeeded at
elapsed approximately 2.3 seconds. Tracked-bar item `200189` changed from
inactive/hidden to active/visible with source `player`; this is consistent with
the reported Stoneform placement, but this probe did not record static spell
identity. The spell cooldown duration object independently changed from inactive
to active, with non-secret contents. That is cooldown evidence, not buff timing.

The capture still used the older loaded Research probe: viewer rows lack static
identity, raw timing, `auraDuration` and `barDuration`, and the new pushback channel
is absent. The installed source/runtime hashes matched when checked afterward,
so no replacement deployment was needed. Reload before the next capture.
This short out-of-combat recording ended before a buff-expiration transition;
it does not establish aura-duration access, native timer liveness, threshold
crossings or combat secrecy. Repeat through buff expiration, ideally with an
in-combat control, using the updated probe before adopting a timing route.

#### Stoneform capture: combat and expiration (2026-11-14 12:05)

Session `20261114-120529-1`, the same Forever build, used the updated probe:
131 samples, one combat pull and zero sampler failures. The viewer was shown,
with no item preview. Static spell/override `20594` identified bar item `200189`.
Stoneform succeeded about 10.3 seconds into the capture; the item was active at
11.28 seconds and inactive by 19.29 seconds, still during combat.

- Item active/visible and source `player` were plain while the buff was up.
- Aura instance, expiration, duration, bar value/max and timer text were secret.
  The aura-duration route reported a secret instance and was not called; this
  capture does not establish whether that API would authorize access.
- `Bar:GetTimerDuration()` returned nil before, during and after the buff.
  The native timer route therefore supplies no usable duration object here.
  Bar value/max remained secret even after the buff became inactive.
- The **spell cooldown** duration object had secret contents in combat, but its
  activity bridge and scratch test changed false to true after casting; its
  below-1-second predicate changed true to false. After combat, total duration
  read 180 seconds while the buff was already gone. These working bounded
  predicates concern the cooldown, not the aura, and cannot time buff renewal.
- Incoming WOUND counts reached nine; delayed-cast counts remained zero.
  The target-below-20%, melee range and already-running Attack context were
  readable before the target swap, but swing remaining was nil. No observed
  pushback or swing-timing control supports a new finishing policy yet.

Conclusion for this measured build/scenario: retain tracked-bar activity as
up/down evidence. Merely moving a buff to Tracked Bars does not supply a usable
buff-duration object for the existing health/mana-style threshold technique.
No recommendation change follows from this capture.

#### Portrait overlay: BetterBlizzFrames and AuraContainer (2026-11-14)

The installed BetterBlizzFrames v2.2.1b Forever module supplies this portrait
overlay through its Big Debuffs feature, not through Cooldown Manager.
Saved settings enable both Big Debuffs and extra buffs; its extra-buff list
includes Stoneform `20594`. Qualifying active auras occupy overlapping portrait
slots, with crowd control and other higher-layer categories able to cover an
ordinary extra buff. Tracking Stoneform in CDM is not what enables this overlay.

Source tracing found a distinct candidate, not another measured timing signal:

- BetterBlizzFrames uses Blizzard's `CustomAuraContainerTemplate`, supplies a
  portrait icon/cooldown and lets Blizzard populate the aura display.
- Blizzard's AuraButton keeps a stable duration object and updates its secret
  timing internally. Its `GetAuraDuration` / `GetAuraInstance` methods belong to
  the private partition, not the public inbound mixin. Do not treat these as
  addon-callable getters merely because their Lua source exists.
- The public `CustomAuraButton:SetDurationBar` API accepts an addon-provided
  StatusBar. Blizzard then calls `SetTimerDuration` with that internal object,
  unlike CDM's measured manual `SetValue` path.
- The experiment configured an owned, single-spell player-buff slot and duration
  bar to test `GetTimerDuration()` and fixed thresholds. No BetterBlizzFrames
  widgets were queried or modified.

Capture `20261114-121506-1` exercised Stoneform in combat through expiration,
but the initial probe wrongly required secure-environment mixin globals. Its
`unavailable:duration-bar API` result reflects that guard, not an API denial:
Blizzard loads those Lua mixins in a secure environment while exporting the XML
template globally. A corrected subsequent capture tested the actual template;
the tracked-bar control again switched active then inactive.

#### Owned Stoneform duration bar: combat denial (2026-11-14 12:19)

Session `20261114-121958-1`, Forever **1.60.1.70938**, ran 93 samples, one
combat pull and zero sampler failures. The owned slot initialized successfully
out of combat; its empty timer reported inactive and below one second. During
combat, the container remained shown, visible and enabled, but addon reads of
the button, bar value and `GetTimerDuration()` failed with forbidden-object
errors. That failure remained the last observed state throughout the Stoneform
cast and expiration. The independently tracked CDM item went active after the
cast and inactive approximately eight seconds later.

On leaving combat, the timer was accessible again, had secret contents, and
reported inactive / below one second; the buff had already expired. Thus this
capture does not validate an active or near-expiration timer verdict, and it
**rules out this addon-owned descendant read route in this combat context**.
No inference about other clients or all possible aura access routes is implied.
Cleanup completed without a reported error. The failed experiment and its
session lifecycle wiring were removed after this capture.

The same pull recorded one real player `UNIT_SPELLCAST_DELAYED` for Lightning
Bolt, with six incoming WOUND events and one nameplate targeting the player.
The sampled cast start/end each moved one second later across the delay; melee
range was unknown. This demonstrates that the delay event can be observed in
this case, not that targeting counts identify attackers or that a finisher
threshold is justified.

The Forever queue now uses this event for a five-second, refreshable preference for
confirmed ready, in-range direct-damage instants with base cooldown and charge
recovery under ten seconds, over an unprotected hardcast or unavailable lead.
Otherwise the instant can appear behind the existing lead, including when a
stack-gated hardcast or auto attack leads the queue. Existing priority conditions,
custom queues, exact order, DoTs and user holds remain respected. Short-cooldown
damage interrupts are fallback-only, excluded for bosses and player-controlled
targets, and reserved when the target is casting or has been observed casting
since selection. Absence of such evidence
does not prove a target cannot cast, and other attackers may cast. This is a
heuristic, not a measured DPS or kill-time calculation; Retail is unchanged.

### Temporary capture routine

The shared `/jac inspect start` session now includes the `signal.*` research
channels below on **both clients**. It does not change recommendation behavior,
CVars, tracked spells or saved player settings.

1. `/reload` to load the updated probe, then `/jac inspect start`.
2. Play several pulls. Spend/recover health and power; cast and cancel heals on
   yourself/pet or target an ally while another player heals them. Use a heal-absorb
   encounter if available. Control a target and let the effect expire or break.
3. Keep the relevant buffs/DoTs tracked in your existing Cooldown Manager layout.
   Exercise refresh/removal, toggles, pet happiness and a grouped tank/non-tank
   threat situation where available. Do not change settings merely to force a
   positive capture. A missing scenario remains untested.
   Include interruptible and shielded casts, channels, target swaps during a
   cast, a cast aimed at you versus someone else, and player stun/fear/root/slow
   transitions where possible. Record which controls actually occurred.
4. `/jac inspect stop`, then `/reload`. Read
   `JustACGlobal.probeLog` and `diagnosticSummary` from the client's SavedVariables.

Plain `/jac inspect start` omits the audit battery; `start full` restores it. After
the flush, `python tools\analyze_probe.py` scores the questions and compares the
session with the client's saved baseline, so changed behavior surfaces first. See
[behavior baseline and the analyzer](DEV_TOOLING.md#behavior-baseline-and-the-analyzer).

Heavy candidates run once per second with independently classified results,
change-only logging and cache invalidation on context events. The existing
ten-minute session limit and bounded rolling log still apply. GCD reads are also
captured synchronously on `SPELL_UPDATE_COOLDOWN`, limited to 120 changed event
snapshots per combat phase; `signal.gcd.dropped` reports events skipped after
the cap. `signal.gcd.sample` is the separately sampled comparison. A target
epoch separates target swaps.

Target cast events also capture a synchronous cast/channel sample, timestamp,
target epoch and classified event arguments 4/5. These are limited to 120 events
per combat phase, with one cap notice and `signal.cast.dropped` thereafter.
`signal.booleanCalibration` compares plain and `secretwrap` true/false controls;
`signal.target.cast` compares raw and numeric-bridge interruptibility, importance
and cast-on-player verdicts. `signal.player.locDetails`, `signal.player.control`
and per-unit charm samples cover player control-state candidates. Unavailable
APIs fail independently; no candidate changes the active interrupt/CC cascade.
`player.groupHealers` and `target.groupHealers` compare raw incoming-heal zero
state with a separate prediction calculator for each present party healer, or
the first eight raid unit tokens. The calculator's `netDebtZero` is scoped to
that one healer, not an aggregate; raid truncation is explicit.

#### Priority-condition coverage

`PRIORITY` records now run at most once per second while shared diagnostics are
active, with change-only output. Keys identify target context (`st`, `cleave`,
`aoe`), entry position/spell and recursive condition path. Each includes the
target epoch, selected tree, point-resource context, condition parameters and
the actual queue evaluator's ordinary `rank` and `strict` verdicts. Nil is
explicitly `unknown:nil`, not a pass. Group and child verdicts are both recorded.

These are **imported-condition reads**, not a replay of the final queue:
`importedOnly=true` means per-player Hold Until overrides, finisher point caps,
readiness/range admission and subsequent sorting are not applied here. Compare
with displayed queue records and `/jac why <spell>` for a final ordering decision.
The evaluator may deliberately map an unavailable input to false; the capture
does not redefine its semantics.

#### Rotation eligibility and enemy context

The standard shared session also records three change-only keys, without the
Research companion:

- `rotationEligibility`: up to 12 imported entries for the queue's current
  target context. Each lists listed/resolved rank, raw and helper usability with
  insufficient-power state, readiness and source, range, imported-condition gate
  verdict, delegated status and rendered main-queue position.
- `targetContext` and `queueContext`: raw target creature type, type ID,
  classification and level, beside the queue's own enemy, melee, dying-target,
  execute and pick context.
- `enemyProvenance`: nameplate, hostile, readable threat, no-threat and unknown
  counts beside `GetEngagedEnemyCount()`.

Like `PRIORITY`, gate verdicts are imported-condition reads, not the final sort.
Secret, error and nil reads stay classified. Readiness can change every global
cooldown, so keep captures to focused leveling pulls and watch the dropped-row
warning in the stop report.

Evidence beside the verdict:

- `dot`: referenced spell's active/confirmed/engine-pandemic tracker state.
  `source` identifies the branch that decided the tracker verdict. `cdm` and
  `cdmReason` distinguish readable aura activity from missing entries, hidden
  viewers, cooldown-only items, unavailable activity and denied cooldown-ID reads.
  An instance `confirmed=false` does not invalidate a Cooldown Manager verdict.
  `enginePandemic=nil` means that route did not decide or had no answer.
  Change-only `DOT` records include the same provenance and target epoch.
  Up to 12 rotation-referenced DoTs are sampled even before a cast; candidate
  overflow is marked `truncated=true`. Cast timing remains an estimate, and
  an untracked false is not confirmed aura absence.
  The ordinary dot gate is labeled target-health policy, **not** a DoT-presence
  evaluator. Separate tracker evidence must not be read as proof it changed ranking.
- `stack`: requested `>= n` helper result and independent spell-to-instance
  binding status, for player or target. The operator-aware evaluator verdict is
  separate; for example `< n` is not the same question as `>= n`.
- `swing`: main-hand/ranged tracker remaining time next to the condition verdict.
- `buff`: the buff-window helper's activity next to ranking/strict verdicts.
  This helper may combine evidence routes; the label is not proof of CDM origin.

Bounds: at most 240 entry/condition records per sample, eight nesting levels,
with `signal.priorityGates` reporting `truncated=true` if exceeded. Removal
records expose list changes. The existing rolling log can evict older records;
check dropped counts and stop after controlled scenarios rather than recording
unrelated play for ten minutes. One-second samples can miss short swing windows
or stack transitions; lack of a captured positive does not refute the signal.

The audit's `AURAINST` watcher deduplicates up to four references from tracked
DoTs and all three lists, including nested groups. It records `ref` and target
epoch separately per spell. Only that spell's lookup instance feeds the duration
probe; an arbitrary instance from the general harmful-aura list is no longer
treated as a binding. The general list remains context only.

Controls: apply/expire/refresh a referenced DoT, swap away/back, cross relevant
player/target stack thresholds, and start/stop main-hand or ranged auto attacks
around a swing-gated suggestion. Include absent/untracked states and the relevant
known talent/tree. Missing scenarios remain untested. Repeat on each affected
client; a source/CSV build label alone does not establish installed behavior.

Static support classification belongs in
`python tools\gen_forever_rotations.py --coverage`, not every live record.
That report is post-adaptation evaluator coverage and does not validate engine
readability. See [the guide workflow](forever-guides/README.md#condition-coverage-report).

Bounds are explicit: first six bar-spell entries for toggles/GCD, first bar spell
for cooldown duration predicates, first three target LoC entries, twelve viewer
items per buff viewer, eight pet food types, and twelve distinct bag item IDs
for food compatibility (bags 0-4, at most 36 slots each). These are samples, not
complete spellbook/inventory coverage. Put an ability of interest early on the
bars if needed. No automatic bar or viewer edits are made.

Numeric `*Zero` channels report **true = zero**, false = nonzero, or unknown/error.
`health50` instead reports **true = below 50%**, separately for actual and
predicted health. The calculator explicitly nets incoming healing against debt,
clamps debt to maximum health, and clamps incoming healing to missing health
without overflow. Nil inputs never enter the zero-gate.

Each nested field is classified independently. Hidden viewer visibility, edit
state, aura source, plate binding/preview and missing markers are recorded,
not silently interpreted as a gameplay verdict. Bucket counts use Blizzard's
read-only priority-table `Size()` method, not `#` on the wrapper. No secret
spell identity or raw payload is persisted. Error text is retained by the shared
probe classifier. Remove this temporary capture after the useful questions are
settled; accepted findings belong in the permanent capability documentation.

The useful pattern is **let the engine answer a feature's question**, not recover a
hidden number. Where a decision does need an estimate, follow the
[threshold scope rule](SECRET_VALUE_THRESHOLD_GATES.md#the-scope-rule): bounded cost, an estimate
with its uncertainty, and a fallback. Unknown stays unknown otherwise. A readable result must also be live,
associated with the right subject, and semantically sufficient for the decision.

## Source audit: 2026-11-13

Scope: Forever UI source `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`,
build 1.60.1.70938, contrasted with the current local JustAC helpers. This is
source evidence and controlled offline execution, not a measurement of live
Forever taint, secrecy or availability.

### Implemented follow-up

- Action usability now requires an identity-confirmed direct spell/item slot,
  including current spell overrides. A macro hotkey cannot mask another direct
  placement. Spell ranks are matched explicitly rather than by name.
- Spell and action usability preserve each readable boolean independently.
  Confirmed insufficient power remains true even if castability is secret.
  Unknown power remains nil and cannot establish a structural non-resource
  block. The third usability return records evidence or a `policy:` fallback;
  API failures are reported once per spell/slot instead of silently disappearing.
- `rotationEligibility` records helper source, confirmed direct slot and action
  evidence. Paired usability/readiness results come from one call per snapshot.
- The local Research companion records `signal.range.event`,
  `signal.failure.event`, `signal.meter.event` and `signal.evidence.dropped`.
  Detailed `EVIDENCE` rows include session ID, time and target epoch, capped at
  120 rows per kind per combat phase. Existing range subscriptions are only
  observed, never enabled/disabled by these probes.
- Range capture compares event validity/verdict, the live native query and the
  helper. A false `checksRange` explicitly makes the event verdict unknown.
  Player failed/successful casts and mapped UI errors are captured without
  translated error text or target names. A cast within 1.5 seconds and the same
  target epoch is labeled recent context, never a confirmed error association.
- `signal.combatLog.restricted` only observes the capability flag.
  `signal.meter.available`, `signal.meter.enabled` and `signal.meter.duration`
  report availability, the existing CVar and separate session timers.
  `signal.meter.postCombat` samples up to 12 player damage-spell aggregates from
  the last notified session ID, only outside combat and only through readable
  containers. The session need not correspond to the latest pull; its ID is
  retained explicitly. Reset clears that identity. Hidden payloads remain
  classified; neither totals nor meter state feed queue decisions.

The findings below describe the pre-follow-up audit baseline and remaining live
verification requirements. These changes do not establish new Forever API
access, optimal rotations, group enemy counts or seal-toggle semantics.

### Capture volume

Context events retain a `DIAG` marker but now emit only changed fields; the initial
baseline and final state remain separately persisted. `PRIORITY CONTEXT` records
epoch/tree/resource context once per change. `PRIORITY DEF` records condition
definitions on first observation or definition change; ordinary `PRIORITY` rows
contain live verdicts and evidence. Interpret them with the latest matching
definition and context, not as standalone copies of a condition.

Range evidence suppresses identical consecutive classified results for each
event/subject in the same target epoch; validity, native/helper verdict and
unknown/error transitions remain significant. Meter notification evidence
deduplicates event/type/session combinations within each combat phase, including
interleaved types, without skipping session tracking or cache invalidation.
`signal.evidence.suppressed` counts these duplicates separately from capped
records in `signal.evidence.dropped`; both counters reset at combat phase edges.
The Research rolling log remains bounded at 32,000 rows. Definitions and early
events can still roll off; a separately saved baseline does not restore missing
event history. Prefer shorter controlled captures over unlimited output.

### Ranked opportunities

1. **Keep spell eligibility attached to the actual action.** Blizzard's
   [action-button watcher][audit-action] forwards slot-specific usability and
   insufficient-power values. JustAC already caches these events, but
   `GetActionBarUsability` uses `GetSlotForSpell`, which can return a macro slot
   naming this spell even while a different modifier branch is active.
   `AbilityInRange` instead requires `GetDirectSlotForSpell`. Executing the real
   usability and queue predicates against a controlled non-direct slot confirms
   that a usable spell can be structurally sunk by another branch's grey state.
   Candidate correction: require confirmed effective-spell binding, or use a
   direct slot only when that binding cannot be established. Test modifier
   press/release, explicit low ranks, duplicate direct/macro placements, unbound
   spells, paging and vehicle changes before changing shared admission.

2. **Preserve eligibility provenance and independent return values.**
   `IsSpellUsable` treats either secret return as grounds to replace both via
   the action bar. With no bar evidence, a controlled secret usability value
   plus plain `insufficientPower=true` becomes helper `true,false`; a denied
   call has the same fail-open result. These are verified helper behaviors, not
   proof those combinations occur on Forever. Capture raw values, action-slot
   binding and helper source separately. A policy fallback must not be described
   as confirmed affordability. Keep the default/custom queue and explicit hold
   settings unchanged while testing low mana, no bar slot and call failures.

3. **Use engine range events as an explicitly valid sample.**
   [Action][audit-action-range] and [spell][audit-spell-range] events supply
   `checksRange`; false means the accompanying range boolean cannot be used.
   This is a candidate event-time comparison with existing range helpers, not
   permission to interpret absent events as in range. Start with already
   watched direct slots. Blizzard enables/disables range watching as frames
   register/unregister, so do not change another watcher's engine subscription.
   Test no target, target swaps, minimum/extended range, movement, macros,
   next-swing attacks and stock/replaced/hidden bars. Event results still need
   secrecy classification and invalidation when slot/target identity changes.

4. **Classify failed attempts through the client's own error mapping.**
   [GetGameMessageInfo][audit-game-error] maps a `UI_ERROR_MESSAGE` index to an
   error name; [UIErrorsFrame][audit-error-ui] uses this mapping itself.
   Capture that name alongside recent player cast/target context rather than
   importing packet spell-failure numbers or parsing translated text.
   An error does not identify the responsible spell/target by itself.
   `UNIT_SPELLCAST_FAILED` carries cast/spell identity but no failure-reason
   field; `UNIT_COMBAT` supplies coarse feedback with a secret amount and no
   responsible spell/source identity. Neither is a replacement combat log.
   Existing research watchers already include UI errors and unit combat;
   reuse them for wrong target, range, mana and unrelated-error controls.

### Enemy context: membership is not tanking or proximity

[CompactUnitFrame][audit-threat] explicitly distinguishes being on the player's
threat list from the role-dependent aggro warning. A readable non-nil threat
state can include a DPS player below the tank on threat; it does not mean the
enemy is attacking the player. `GetEngagedEnemyCount` counts membership plus
in-combat plates engaged with the pet or party (see below), not all enemies near
the player or all members of a group pull.

The count comes from visible nameplates, so it also falls when plates leave the screen
(2026-11-20, maintainer's call). Enemies die and join one at a time: a rise, or a fall of one,
is taken at once. A fall of two or more in a single quarter-second scan is suspect and the
last count is kept, in combat, until the lower one has lasted four seconds. Several enemies
really dying at once keeps the pack order that long. Plates leaving one at a time over several
scans are not caught. The stability capture's `enemyStep` shows how often each case occurs;
the rule is not yet checked in game.

Candidate group evidence is confirmed threat membership for a party member
against the same nameplate token, deduplicated by that token. It needs live
verification before widening any count. `UnitAffectingCombat` alone cannot
associate an enemy with our group. `UnitThreatLeadSituation` is a tank warning,
not a membership replacement. Keep observed player/group membership separate
from ability-specific range; never infer Consecration coverage from either
count alone. Compare solo/group-tanked pulls, before/after player damage,
unrelated nearby fights, missing nameplates and unreadable threat.

Captures through 2026-11-15 (Forever 1.60.1.70938, solo hunter): every player
threat read was plain, and the player was never on more than one plate's list.
Extra hostile plates in combat (up to seven) were not shown to be engaged, so
these captures neither confirm nor rule out an undercount. `enemyProvenance`
now also records, per hostile plate counted once, threat membership for the pet,
party members and their pets: `group`, `petOnly`, `partyOnly`, `groupUnknown`
(unreadable member reads) and `members` (present). The `partythreat` research
question scores it.

Measured 2026-11-15 15:06 (hunter 11, pet out, two marked pet-held adds): all
member reads were plain, but the pet was absent from a 27-second pet-tanked
target's threat list for the whole fight and joined the other only about nine
seconds after the mark. Threat membership therefore misses pet-held enemies and
does not qualify for widening the count; the player-only count read zero for 92%
of combat time while hostile plates were present.

The next candidate asks two different questions per hostile plate: is it in
combat (`UnitAffectingCombat` on the plate) and is its target one of us
(`UnitIsUnit` of the plate's target against the player, pet and party, which on
Forever is contracted `RequiresComparableUnitTokens` and
`SecretWhenUnitComparisonRestricted`, so denied and secret comparisons stay
unknown). `enemyProvenance` adds `inCombat`, `inCombatUnknown`, `onUs`,
`onUsUnknown`, `engaged` (in combat and on our threat lists or attacking us) and
`inCombatOthers` (plainly in combat with neither: another fight). The
`enemycount` question scores it. Adoption criteria for `GetEngagedEnemyCount`:
plate reads plain in combat, `engaged` follows marked pet-held adds and packs
within seconds, and a marked nearby fight shows up as `inCombatOthers`, not
`engaged`. A plate that switches targets between members still counts once; a
mob fleeing or attacking a non-group player is not ours.

Measured 2026-11-15 15:15 (hunter 12, 113 seconds of combat, six marks): plate
combat and target reads were never unknown; `engaged` picked up every pull,
including three pet-held adds, within one to four seconds and read 2 for both
2-mob packs; plates in other players' fights stayed `inCombatOthers`, including
one already engaged by someone else until the player hit it. The player-only
count missed engaged enemies for 49% of combat time. A mob that stops targeting
the group (fleeing at low health) drops out a few seconds early: an undercount,
never an overcount. On Forever `GetEngagedEnemyCount` now uses this definition:
the player on the plate's threat list, or the plate plainly in combat with a
pet/party member on its threat list or targeting the player, pet or party.
Unreadable or denied reads never add to the count. Retail, where none of this
was measured, keeps the player-only count. With fight-wide mark windows the
`enemycount` question scores this capture CONTROLS MET.

Current state (after consolidation): `enemyProvenance` formats the breakdown from
the queue helper's own scan (`GetEngagedEnemyCount(breakdown)`): `plates`,
`hostile`, `threat`, `unknown`, `helper` (the count), `widened` (counted through
pet/party threat or targeting) and `inCombatOthers`. The research-only fields
above were retired, and `partythreat` and `enemycount` merged into the `enemies`
question, so the probe can no longer measure a different rule from the one that ships.

### Combat log and built-in damage meter

The current [combat-log contract][audit-combat-log] marks filtered/unfiltered
events restricted. [Secure access][audit-combat-secure] has its own restricted
environment; the UI-facing message is preformatted and protected by a `|K`
wrapper. An internal namespace or missing annotation is not permission to
reopen the measured blocked combat-log route. Do not add a CLEU listener,
parse protected messages or borrow privileged processor state.
`C_CombatLog.IsCombatLogRestricted()` is an appropriate capability observation,
not authorization to read events or change the player's filters.

The [damage-meter contract][audit-meter] exposes availability/failure reason,
session metadata, update notifications and a separate duration accessor.
Blizzard [updates its timer][audit-meter-timer] with the duration accessor.
These are candidates for capture alignment and session-boundary diagnostics,
not target lifetime, damage identity, enemy count or a future fight-duration
prediction. Verify current/overall/expired behavior, reset, consecutive pulls,
availability and actual recording with existing settings preserved.

Aggregated sessions and source spell breakdowns are `SecretWhenInCombat`.
Never enumerate secret lists, even to find an `isLocalPlayer` field annotated
NeverSecret. Do not read meter bar widths/text as hidden totals. After combat,
independently confirmed readable session/source data could support debug-only
damage-contribution analysis for seals, Holy Strike, Judgement and later
Exorcism/Consecration. Pin a session ID and wait for updates; aggregates have no
per-cast timeline and cannot distinguish an unused spell from every other
reason it contributed no damage. Availability and post-combat readability
still require separate client measurements.

**Measured damage (2026-11-20).** Measured damage is read from the meter after combat only
(`BlizzardAPI.GetMeasuredDamageRatio`, `BlizzardAPI/CooldownTracking.lua`). Every damage read
(`GetDirectSpellHit`, `GetDirectSpellDPS`, `GetAutoAttackDPS`) answers with paper times the
attack's ratio, so the weapon comparison, the pull order and the ranged filler swap agree; the
measurement prices its own casts and swings on paper (`PaperSpellHit`, the sheet), so the ratio
never feeds back into itself. The session a
fight's damage went to is the `DAMAGE_METER_COMBAT_SESSION_UPDATED` (DamageDone) id notified
while the fight ran; a fight with none is dropped. Every update also comes as session 0, the
current-fight placeholder, right after the real id (2026-11-20 priest capture: 11 to 17 at each
pull, then 0); 0 is ignored. The meter records with its display off (`damageMeterEnabled` false
in that capture). Damage per attack comes from
`GetCombatSessionSourceFromID(session, DamageDone, playerGUID).combatSpells`, every field
checked plain before use. Counted: the player's direct-hit casts (no damage over time) from
`UNIT_SPELLCAST_SUCCEEDED`, priced at the pre-combat estimate; ranged shots from
`PLAYER_SWING` (ranged), priced at the pre-combat sheet DPS times ranged speed; and white melee
swings from `PLAYER_SWING` (main and off hand), priced at each hand's sheet average
(`UnitDamage`). The meter reports a wand's damage as spell 75, never 5019 (2026-11-18 warlock
captures: 75 in every session that shot), and white melee as 6603 (2026-11-20 warrior
capture). A next-swing attack's success (Heroic Strike, Cleave, Maul, Raptor Strike) takes one
main-hand swing out of the white count: its `PLAYER_SWING` fires at the same moment (same
capture, t=5933.032). A cast with damage over time is priced when its run ends: its hit plus
the damage over time for the part of its duration it could tick, until it expires, is recast
(a refresh drops the ticks left) or the fight ends (`PLAYER_REGEN_ENABLED`). The fight's end
stands for the target's death only with one enemy, so damage over time is measured only when
every such cast went on one target GUID and `GetEngagedEnemyCount` read 1 at every in-combat
sample (wand shots, swings and casts while one runs); no sample counts as unknown. An instant
damage over time with no hit (Shadow Word: Pain, Serpent Sting, Curse of Doom) has an estimate
row flagged measure-only (12th field 1, `BlizzardAPI.IsMeasureOnlyEstimate`): it is measured
but never chooses an opener (openers need a cast time) or the ranged filler swap. A channel
(Starshards) is not measured this way, since its run ends when the channel stops. An inference
from confirmed inputs: combat ending a little after the death prices a little more ticking time
than there was. Only solo fights are measured: every press must read `IsGrouped()` false (unknown is not solo).
With a partner a shot in flight or a last hit's overkill lands nothing on the meter, so a
grouped fight measures who else hit the mob (wand 0.85 and 0.92 in the two grouped fights of
the 2026-11-20 priest capture against 1.06 solo, its skill 2 to 3 under the cap); the capture
reports `groupedSkipped`. The meter files a pet's damage under its owner (a warlock's imp
Firebolt, 3110, in the 2026-11-18 captures); whether a pet's white swings share the owner's 6603
row is not known, so melee is not measured while a pet is out. The `meter.postCombat` probe
records each entry's `creatureName` to settle it. Only targets from four levels below to two
above are measured (`levelSkipped` in the capture): misses and resists climb steeply three or
more above, a grey mob dies to overkill, and an unreadable level (a skull) is skipped. A weapon
swapped in combat clears the pre-fight prices, so every later press goes unpriced and the fight
is not measured. Points spent differently (a signature of points per tree, read on talent and
spell events) clear every measurement. A damage over time ticks every period after the cast
(its row's 13th field, the 12th being the measure-only flag or 0), so a cut-short run is priced
by its whole ticks. The ratio the queue uses is damped toward paper, as if the minimum count (3
casts, 8 shots or swings) more had landed at paper, so a few crits or misses move it gradually.
Measurements are saved per character (`JustACDB` char: `measuredDamage`, `measuredTalents`) and
restored at `PLAYER_ENTERING_WORLD` unless the talent signature changed, since learning takes
several fights and the player reloads often to save a capture. Measured over paper is kept per attack, older fights weighted 0.7 per new
one; used from 3 casts or 8 shots or swings and only between 0.25 and 4. A session read again
credits only its gain (one session can span pulls); a spell the meter does not list yet waits.
Weapon skill (`C_SkillInfo.GetSkillLineInfoByID`, out of combat) is the skill line of the
weapon in the attack's slot, mapped by `Enum.ItemWeaponSubclass` name as the character sheet
does, the feral skill for a druid in a form; 5 points above the last measurement drops the
earlier figure. The capture row `signal.meter.measured` lists each ratio with its count, skill
and target level gap. Untested in game: the session timing above, and hit and crit by skill
against higher-level targets (recorded, not yet used).

### Active spell state: existing probe, not proven seal identity

`C_Spell.IsActiveSpell` is explicitly about an active toggled spell, with aura
and identity secrecy. The [gamepad flyout caller][audit-toggle] uses it to mark
an entry checked and decide whether clicking should cancel the spell.
That establishes toggle UI semantics, not that every timed seal participates.
The existing `signal.spells.toggles` probe already samples current bar spells;
no duplicate probe is needed. Compare a genuine toggle, an ordinary attack
and each learned seal through cast, replacement, expiration and cancellation,
including target changes. Keep normal aura evidence until those transitions
prove applicability on the client.

### Enum mirror: taxonomy, not an extra live signal

The inspected [WowPacketParser mirror][audit-wpp] is revision
`e46644410866709c82ed8c19353587c5b0507f08`, dated 2026-11-04.
Its build inventory includes Forever beta builds
through 70235, not the installed 70938. Creature-type IDs, spell mechanics and
flags are useful source-checking aids, but the matching client's generated
documentation and readable runtime values remain authoritative.

Packet `UnitFlags` are not a Lua unit-state accessor. Spell-cast-failure numbers
also differ across versioned tables: `NotBehind` is 57 in the base table and 76
in the 6.1.0 table. Neither is a verified `UI_ERROR_MESSAGE` index.
Use the runtime creature-type ID (the current `UnitCreatureType` contract
returns name and ID), client enum/catalog helpers and `GetGameMessageInfo`
where applicable; do not copy unverified constants into queue logic.
No external enum implementation was adopted.

## High-value foundations already used

| Mechanism | Question answered | Existing consumer / important limit |
|---|---|---|
| Curve evaluation plus `BlizzardAPI.IsSecretZero` | Below a configured health/resource threshold? | Health bands, execute and power gates. Boundaries come from behavior, not desired numeric resolution. |
| Scratch Cooldown shown state | Is this duration active? | Cooldown/totem/buff-window readers. A duration handle does not bypass aura-access restrictions. |
| Live Blizzard class-resource point state | How many discrete points are active? | `GetClassResourcePoints`. Only matching, updating resource bars count; hidden bars can freeze. Availability differs by client and class. |
| Full-power animation / low-health vignette | Resource capped / coarse low-health warning? | Existing fallback helpers. Absence of an animation is not general proof of an uncapped or healthy state. |
| Combat Audio Alerts party membership | Is a supported party unit below the configured alert threshold? | Existing party-health bridge. One configured threshold, roster/liveness checks, no reading or inverting stored health/frequency. |
| Cooldown Manager tracked-aura state | Is the tracked buff/DoT active? | `MaintenanceTracker` bridge. Viewer must stay populated; a family entry need not identify its member spell. |
| `PLAYER_SWING` | Swing phase and observed swing duration? | Own swing tracker. Haste change alone does not identify which buff caused it. |
| Swing/spell/action range checks | Is this attack in reach? | Range gates. Nil or `checksRange=false` means unknown. Swing range says nothing about facing. |
| Usability plus insufficient-power flag | Unaffordable, or unusable for another reason? | Queue filtering. Does not uniquely identify a proc, stance, missing buff or rear-position failure. |
| Cooldown `isActive`, charge metadata, overlay glow | Engine readiness / spell activation cue? | Existing readiness/proc helpers. GCD and charge-recharge state must not be conflated. |
| LoC count and spell LoC cooldown | Player control lost / this spell locked out? | Existing defensive lockout helpers. Do not remove the whole queue during CC. |

Implementation: [StateHelpers](../BlizzardAPI/StateHelpers.lua),
[CooldownTracking](../BlizzardAPI/CooldownTracking.lua),
[SecretValues](../BlizzardAPI/SecretValues.lua),
[MaintenanceTracker](../MaintenanceTracker.lua).
Contracts: [swing API][swing], [cooldown fields][spellshared],
[action usability events][action], [overlay events][overlay].

Range consumers use `BlizzardAPI.AbilityInRange`: a verified direct action slot,
then the same ability's spell-range fallback. Item slots use `ActionInRange`.
Forever Attack and next-swing abilities retain their measured exception: raw
spell/action positives cannot replace confirmed melee evidence. Unknown remains
unknown; targeted interrupts may fail open, while player-centered AoE still needs
distance proof. `SpellDB.IsTargetWithin` is a separate distance-bracket reader,
using vetted on-target references with readable min/max metadata for the known
rank. All radii share one frame snapshot, invalidated on target and spell changes.
On Forever the snapshot also adds, from the 2026-11-16 measurements below:
curated 5-yard references whose live maximum is 0 or missing (zero minimum, not
next-swing) as melee probes; the `RegisterRangeItems` tiers (5 and 10 yards, two
items each, used once cached, both must agree); and `CheckInteractDistance`
index 3 (true proves within 8, false proves beyond melee). Item and interaction
reads require a live attackable target. Swing range folds into the same bounds,
and any within/beyond contradiction makes every radius unknown for that snapshot.
`/jac inspect range` prints the sources and any contradiction.
`/jac inspect range` shows raw and effective reads plus resolved probe endpoints.
Automatic ranked priorities normally require confirmed melee reach for next-swing
abilities. When that reach is unknown, losing a known ranged weapon's range within
three seconds of a positive reading can cue a ready next-swing ability. Fresh,
continuous out-of-shooting-range observations maintain that cue through queued
swings and cooldowns, so the ability can lead again when ready. A gap longer than
three seconds expires it; negative readings alone cannot restart an expired cue.
A compatible current range bracket within that weapon's maximum can also support
and renew the cue. This is an ordering hint, not proof of movement direction,
melee reach or castability: the target could instead have retreated past maximum
range. It never changes range colouring or `AbilityInRange`, and a confirmed melee
or beyond-maximum verdict takes precedence. Unknown weapon range, restored shooting
range, invalid targets, target/combat/spell/spec changes and explicit ordering
settings clear the hint. Queue diagnostics label it `nearMeleeHint`.
Fresh main-hand or off-hand `PLAYER_SWING` activity can independently supply an
ordering cue for melee-start pulls. The shared tracker binds activity to the
current target-change epoch, requires a live hostile target and an enabled melee
autoattack when queried, and clears on target/world/equipment changes, attack stop
or combat exit. It preserves an opening swing delivered just before combat entry.
This observes the selected target, not an attributed victim.
The activity cue expires three seconds after the last event; unchanged negative
shooting reads cannot latch or renew it. Fresh events can renew it through queued
and cooldown cycles. Confirmed non-melee/beyond-maximum range or restored shooting
range takes precedence. Without a ranged weapon, or with unknown shooting range,
fresh activity alone can support this ordering cue. Diagnostics record
`source=melee-activity` and `activityAge` separately from the shooting-range cue.
`RunningAutoSwing` also recognizes their native `IsCurrentSpell` queued state, so
queue sorting and the swing-bar display agree. A queued next-swing ability trails
actionable attacks and does not by itself suppress WAIT when nothing can be pressed.
The positioning hint adds no estimated next-swing queue window and does not rewrite
custom lists or settings.

### Pre-pull target setup

Automatic ranked Forever queues promote curated non-pulling target debuffs before
damaging openers. Hunter's Mark is the initial policy; all of its ranks share one
debuff family. The queue is not class- or spell-specific: additional verified
policies register their cast ID and equivalent aura IDs through the
`foreverTargetSetup` input to `SpellDB.RegisterCategories`, with rank-aware lookup.
Non-damage alone does not establish that a debuff is safe before a pull.
The ability must pass the normal filters, gates, holds, lockout,
readiness and resource checks and have confirmed range to a live hostile target.
The promotion reserves slot 1 before queue truncation, including one-icon displays
and a pre-filled opener slot. Custom lists, exact ordering and disabling
Unavailable last retain their existing ordering. Combat priorities are unchanged.

`PrecombatEngine.GetTargetDebuffState` requires an out-of-combat, visible target,
readable GUID, unrestricted auras and a complete readable `HARMFUL` enumeration.
Any caster's matching rank satisfies the policy. Denied calls, hidden identities,
secret tables, partial indexed scans and unavailable APIs return unknown, never
missing. It does not interpret an untracked cast or a by-spell nil as absence.
The 0.2-second snapshot is invalidated on target aura updates, target changes,
combat edges and checklist cache resets. This is target setup in the DPS queue,
not a self-buff in Preparation.

### Forever melee-range source audit (2026-11-15)

Scope: Forever **1.60.1 (70938)**, revision
`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`, plus the pinned Forever
**1.60.1.70888** spell CSVs. No source refresh or new live measurement.
The observation-bounded queue hint above is implemented. The candidates below
are now observable in the local Research companion, not used as new production
range predicates.

**Highest-value new lead: swing-range subscription ownership.**
[Blizzard's swing UI][melee-swing-ui] calls
`C_SwingTimer.EnableRangeCheck(swingType, shouldCheckRange)` when its registration
state changes. `ShouldCheckRange` depends on `showSwingTimer`, Edit Mode visibility
and equipment. JustAC enables its checks at world entry. A later UI disable call
is therefore worth correlating with native nil/invalid range transitions.
The Lua call sites do not prove how native ownership works or that this caused the
latest Hunter capture. The probe now passively records future enable/disable
calls, caller, target epoch and valid range updates alongside the frame state.
Do not repeatedly re-enable checks, change player settings or treat a mock as proof
that a native subscription was disabled.

**The swing frame is not an independent range oracle.** Executing the exact
source methods offline reproduced these distinctions:

- `UpdateRangeState` stores `isOutOfRange=false` when the native result is nil,
  or when the frame's range check is disabled.
- An event with `checksRange=false` also becomes `isOutOfRange=false`.
- `IsOutOfRange()` suppresses the warning during an active swing or Edit Mode,
  even when the underlying out-of-range field is true.
- Registration changes can issue `EnableRangeCheck(..., false)`.

Consequently, a bright/green bar, full alpha, `IsOutOfRange()==false` or a false
`isOutOfRange` field cannot prove melee reach. A frame's negative presentation also
does not add information beyond its underlying native check. The
[native swing contract][melee-swing-api] still requires a valid check.

| Avenue | Source-backed finding | Follow-up / limit |
|---|---|---|
| Native item range | [C_Item.IsItemInRange][melee-item-api] takes an item and target and returns a nullable boolean. Potentially class-independent. | Find a real hostile-target short-range item, verify its spell/radius and ownership requirements, then control target eligibility, combat denial and actual crossings. No specific universal 5-yard item was established. A quest-item rejection is not distance proof. |
| Direct interaction predicate | [UnitIsInInteractRange][melee-interact-api] is separate from `CheckInteractDistance`. [Gamepad interaction icons][melee-gamepad-ui] branch on it. | New candidate, not established combat availability or melee semantics. The attack action branch does not use this predicate. Test live hostile targets separately from friendly NPCs and corpses; false may mean non-interactable. |
| Native geometric distance | [UnitDistanceSquared][melee-distance-api] returns distance plus `checkedDistance`; the generated contract has no explicit secret-return annotation. | Candidate only if a hostile target produces a valid, readable live result. Guard both returns and availability. Center distance is not combat reach; never turn a failed check into zero, compare secret numbers or reconstruct distance from UI geometry. |
| Spellbook-index query | [IsSpellBookItemInRange][melee-spellbook-api] supplies an alternate spellbook-identity path with explicit invalid/nil semantics. | Cross-check a learned genuine melee spell against spell/action paths. It is not evidence that Attack or next-swing modifiers acquire real range, nor a substitute for an unlearned Wing Clip. |
| Action-button colour / state | The action range event already supplies `checksRange`; the renderer consumes that same event. | Existing signal, not independent evidence. Attack and next-swing positives retain their measured exception. |
| Nameplate range / fade | [Enemy nameplate defaults][melee-plate-options] set `fadeOutOfRange=false`. [Compact-frame distance][melee-compact-ui] uses a 250-yard threshold; its range fade comes from `UnitInRange`, whose return is explicitly secret in this client. | Plate existence, alpha, selection, threat or `inDistance` cannot identify melee. No 5-yard nameplate predicate was found in the reviewed callers. |
| Soft-target / gamepad attack icon | The gamepad attack icon selects Attack versus Auto Shot from repeat-attack state. Soft-enemy selection supplies a subject, not a measured melee verdict. | No independent range result was found. Do not change targeting CVars or infer distance from the icon or selected unit alone. |
| Swing / combat / failed-cast events | `PLAYER_SWING` has duration/type but no target or hit result. `UNIT_COMBAT` identifies the affected unit, not the attacker. Existing failure capture can record an out-of-range error. | Useful timing/context or retrospective failure evidence, not continuous current-target reach. A queued Raptor Strike success is not a completed melee hit. Do not reopen the denied combat-log path. |

**Auras and area effects:** the nine-class early-ability sweep checked normal
difficulty, acquisition/rank chains and both `EffectRadiusIndex` columns against
`SpellRadius`. Examples were Thunder Clap (8 yards), Confounding Flash (8),
Frost Nova (10) and Demoralizing Roar (10). These apply effects at cast time and
do not establish a continuously enforced 5-yard relationship. Their debuffs can
remain after either unit moves. Friendly Paladin auras and totem buffs have the
wrong subject for a generic hostile-target melee test; a ground effect also need
not remain centered on the moving player.

A future aura candidate needs a verified continuously updated radius, the correct
emitter/recipient relationship to the player and current target, and allowed,
readable identity/presence in the tested context. No generic early 5-yard emitter
was established. There is no range predicate in the reviewed aura API contract.
Keep aura call permission separate from result secrecy; do not scan secret lists
or try to read identity/presence back from an AuraContainer display.

Priority: observe native swing-check lifecycle first; then investigate a vetted
item and the direct interaction/distance candidates with explicit validity
controls. Record far, shooting, dead-zone and melee positions, target swaps,
death, equipment and existing UI settings. Only a new positive/negative result
should promote any candidate into shared range detection.

### Range capture follow-up

With the local Research companion enabled, `/jac inspect start` includes:

- `signal.range.hint`: the queue's last near-melee decision, source, weapon, last
  shooting verdict and hint/observation/activity ages on each 0.25-second sample.
- `signal.range.target`: native interaction and squared-distance candidates.
  Raw distance and `checkedDistance` are recorded separately; an unchecked,
  secret, denied or invalid distance never becomes a valid measurement.
  `interactDist{1..5}` records raw `CheckInteractDistance("target", index)` per
  index without assuming yardage. `position{...}` records whether player and
  target `UnitPosition` reads are plain, secret or nil, and a center-to-center
  ground distance only when both are plain and on one map.
- `signal.range.references`: every known `RangeReferences` probe as
  `SpellDB.DebugRangeProbes` resolved it (live min/max and the raw read the
  snapshot used). Compare 5-yard probes with `interactDist` index 3.
- `signal.range.refItems`: LibRangeCheck-3.0's Era/Forever 5- and 10-yard
  hostile reference items, with cache state and raw `C_Item.IsItemInRange`.
  Uncached item data is requested once per item. Only `true` counts as evidence;
  LibRangeCheck itself treats a false item read as unknown.
- `signal.range.swing`: all three native swing checks, helper results, swing
  frame registration/presentation fields and the existing `showSwingTimer` value.
- `signal.range.activity.mainHand`, `.offHand`, `.ranged` and `.unknown`:
  latest `PLAYER_SWING` evidence, separated by hand/type and reset on target,
  world and combat changes. Each event records its timestamp, target epoch,
  raw duration/type, observed target identity/liveness, interaction/native swing
  range, autoattack-running state, displayed queue and up to six candidates'
  raw spell range, readiness and queued state. These small reads run immediately,
  without the one-second candidate cache or a full synchronous diagnostic sample.
  The observed target is not an attributed victim. Swing timing, enabled attacks
  and queued abilities never become a confirmed hit or current melee verdict.
- `signal.range.spells`: up to six distinct resolved spells, prioritizing the
  current rotation context, then the learned class spell pool, then direct bar
  spells. Uses the shared display/rank resolver, without changing selected ranks
  or player settings. Each row records its source, requested/resolved identity,
  matching direct slot if present, min/max metadata, raw spell and action range,
  effective range, readiness, queued state and spellbook slot/bank/identity/range
  cross-checks. Rotation and learned candidates do not require direct spell
  buttons; macro-only bindings do not exclude them. Other signal topics keep
  their existing bar-based sampling.
- `signal.range.items`: up to six distinct direct item actions on the first
  180 action slots, ownership count and native/action range. Put an item candidate
  on a bar to sample it. Macros and bag-only items are not enumerated; no item's
  yardage or target eligibility is assumed from its boolean result.
- `signal.range.subscription`, `signal.range.swingEvent` and bounded `EVIDENCE`
  rows: future subscription calls with caller stacks and swing events with raw
  result, validity and target epoch. Identical swing verdicts are suppressed;
  validity and target changes remain distinct. Equipment and relevant CVar
  changes provide context.

Candidate polls are cached for one second. Subscription and swing-event evidence
are capped at 120 rows per kind per combat phase; activity has a separate cap for
each hand/type, checked before collecting context. The single passive post-hook
does nothing outside an active diagnostic capture and is reused across restarts;
it never invokes `EnableRangeCheck`, changes CVars or enables action range checks.
Calls before capture/hook installation remain unobserved, not assumed enabled.
On Retail these Forever candidate polls report unavailable.
Action-range cross-checks require a currently matching direct spell/item slot;
a changed identity is unknown rather than another ability's range.

Run far, shooting, dead-zone and melee controls, then `/jac inspect stop` and
`/reload` before disk analysis. A successful next-swing queue is still not a hit,
and consistent near-melee hints still do not turn unknown range into proof.

For activity controls, compare normal melee, facing away, moving backward out of
reach with autoattack still enabled, stopping attacks and swapping targets.
Include observed misses/parries, ranged-only attacks and another attacker while
the player stops. Do not equate timer events, target health loss or unattributed
`UNIT_COMBAT` feedback with the player's successful hit. These controls must be
performed in game; mock coverage cannot establish live event semantics.

### External range-source review (2026-11-16)

Scope: Forever API docs at `bebcb6bf`, the pinned 1.60.1.70938 spell CSVs and
the public source of Forever range addons. External claims are addon-author
measurements, not JustAC measurements. Sources: [forever-addon-kit][ext-kit]
(build 1.60.1.69913 and later beta), [ForeverDeadZone][ext-fdz] (69913),
[SuperSwingTimer][ext-sst], [Range Lens][ext-lens] and
[LibRangeCheck-3.0][ext-lrc].

| Candidate | Evidence | Status |
|---|---|---|
| Combat Range melee probes | Raptor Strike, Wing Clip, Kick, Pummel, Kidney Shot, Sinister Strike, Backstab, Mortal Strike, Slam, Shred and Stormstrike all use `SpellRange` index 2 ("Combat Range", 0-5, melee flag). Raptor Strike read true at 8+ yards here; two external authors report melee abilities in general read in range at any distance. | Rejected 2026-11-16 (see measurements below): Wing Clip reads correctly; only next-swing attacks read true at any distance. Combat Range spells report no live `maxRange`, so they are dropped as probes rather than misleading. |
| `CheckInteractDistance` | Plain `bool`, no secrecy annotation. Two external reports: plain on hostile targets in open-world combat; index 3 flips at Auto Shot's 8-yard edge, index 4 is about 28 yards. Yardage is race-dependent in LibRangeCheck (Tauren 6, Undead 7 on index 3). | Strongest new class-independent bracket. Cannot separate 5 from 8 yards. Captured in `interactDist`. |
| Swing range for addons | Both external beta reports: `IsTargetWithinSwingRange` nil and `checksRange=false` for addons; JustAC measured plain reads on 70245. The kit notes the enable flag is shared with Blizzard's swing bars. | Consistent with the subscription-ownership lead above. Only ever enable. |
| 5-yard reference items | LibRangeCheck lists Era/Forever 5-yard hostile items (8149 and others). The kit saw only 20/30/35-yard items answer, without preloading item data. | Captured in `signal.range.refItems` with preloading. True-only evidence. |
| `UnitPosition("target")` | No secrecy annotation; `#noinstance`. Blizzard's tutorial subtracts player and target positions on a hostile quest creature. No external confirmation for hostile open-world targets. | Captured in `position{}`. Center distance, not combat reach. |
| `ClosestUnitPosition(UnitCreatureID("target"))` | `SecretReturns`; `Curve:Evaluate` accepts secret input only when untainted; `TruncateWhenZero` only separates under 1 yard. Measures the nearest creature with that ID, not the target. | Dead end for decisions. Reading a status bar fill back would reconstruct a hidden number. |
| `UnitDistanceSquared` on a hostile target | SuperSwingTimer users measured `0, false`. | Dead end; matches the unchecked-distance rule above. |

**Measured 2026-11-16 (Forever 1.60.1.70938, Priest 9, open world, session
`20261116-083358-1`, 204 samples, 39 s in combat, beast and humanoid targets
level 5-6):**

- Reference items with preloaded data answered plain `true`/`false` for live
  hostile targets in and out of combat. All six 5-yard items always agreed with
  each other, as did the four 10-yard items. Every 5-yard `true` came with
  10-yard `true` and all `interactDist` indices `true`. 5-yard `false` occurred
  with index 3 `true` (7 samples) and with 10-yard `true` but index 3 `false`
  (8 samples), so the brackets nested without contradiction: 5-yard item, then
  index 3, then 10-yard item, then index 4. Before data loaded, items read nil.
- Dead target: interaction indices all `true`; only 8149 among the 5-yard items
  and three of four 10-yard items answered, the rest nil.
- No target: `CheckInteractDistance` returns `false` for every index, not nil.
  A consumer must require a live target before reading it.
- `UnitPosition("target")` returned nil on every sample: dead end for hostile
  targets in the open world.
- `UnitIsInInteractRange` was `true` only when the 5-yard items were also `true`
  (90 of 100 such samples), never outside them.
- Earlier Hunter 12 capture `20261115-151324-1`: Raptor Strike rank 2 (14260)
  reported live `minRange=0 maxRange=0` through `GetCachedSpellInfo` on all 16
  samples. If other Combat Range spells match, `RefreshRangeSnapshot` already
  drops them as probes (`maxRange > 0` is required), and 5-yard verdicts rest on
  swing range alone. `signal.range.references` on a melee class confirms this.
- The Combat Range probe hypothesis is otherwise untested: a Priest knows no such probe.

**Measured 2026-11-16 (Hunter 12, session `20261116-084241-1`, 255 samples,
41.5 s in combat, 13 main-hand swings), live hostile targets only (159 samples):**

| Auto Shot (8-35) | 5-yard items | `interactDist` 3 | Wing Clip raw | Samples |
|---|---|---|---|---|
| true | false | false | false | 69 |
| false | true | true | true | 68 |
| false | false | true | false | 20 (dead zone) |
| false | true | true | false | 2 (transition) |

- `CheckInteractDistance` index 3 agreed with Auto Shot's 8-yard minimum on all
  159 samples: true exactly when Auto Shot was out of range below its minimum.
  Index 4 went false only while Auto Shot was still true (beyond about 28 yards).
- 5-yard items: every main-hand swing on a live target (11 of 13; two coincided
  with the target dying) had the items `true` in the sample after the swing, and
  in the sample before for 10 of 11. The exception was a walk-in transition read
  through the one-second probe cache. No swing landed with the items `false` on
  both sides. They never read `true` while Auto Shot was in range.
- Wing Clip (2974, Combat Range, not a next-swing attack) read raw spell range
  `true` in melee and `false` at shooting range, matching the 5-yard items on
  157 of 159 samples. The external "melee abilities read in range at any
  distance" claim does not hold for it. Its live `maxRange` is nil, so
  `RefreshRangeSnapshot` discards it as a probe. Raptor Strike (14260,
  next-swing) still read raw `true` on every sample with a target, including at
  shooting range, so the next-swing exception remains correct.
- The swing-range read is not sampled in combat by this capture, so these rows do
  not show how often production 5-yard verdicts were unknown.

**In-combat call restriction (2026-11-16):** the error capture recorded 90
`ADDON_ACTION_BLOCKED` events for `CheckInteractDistance` from the Research probe,
all in combat, when it read the target without a hostility check. That matches
LibRangeCheck's rule: in combat the interaction and item range calls are refused
for any unit the player cannot attack. The generated docs carry no protection
marker for either call. Production reads both only for a live attackable target
and recorded no block; the probe now applies the same rule. In the same live test
the production swing-range read stayed nil throughout combat while the new sources
kept `IsTargetWithin(5)` known in melee, the dead zone and shooting range.
  No melee swing occurred (wand shots only), so the 5-yard item edge is not yet
  compared with real melee reach. Next control: a melee class, auto attack on,
  walking in and out, comparing `refItems` 5-yard with main-hand
  `PLAYER_SWING` activity and `signal.range.references`.

[ext-kit]: https://github.com/Thunderz96/forever-addon-kit
[ext-fdz]: https://github.com/Thunderz96/ForeverDeadZone
[ext-sst]: https://github.com/ssdeanx/SuperSwingTimer-WoW
[ext-lens]: https://github.com/jonlipin/range-lens
[ext-lrc]: https://github.com/WeakAuras/LibRangeCheck-3.0

### Pre-combat minimum-range inference (2026-11-15)

`SpellDB.IsTargetWithin` treats a failed minimum-range probe as "beyond its maximum"
out of combat when the target is an aggressive (hated or hostile), attackable,
non-player, non-trivial NPC that is not in combat or tapped by others, and the player
is alive, unstealthed and not feigning. Any unreadable condition keeps the reading
unknown.

Measured on Forever 1.60.1.70938 (hunter 11 against humanoids level 6 and 7): both
applications in one session were the first sample after selecting a target already in
melee range. The pull followed about 0.25 seconds later, and a melee swing followed
within 1.3 seconds in one case. Raw Raptor Strike range read true in every sample,
including 17 where Arcane Shot confirmed at least 8 yards, so next-swing raw range is
not melee evidence. `UnitIsInInteractRange` read plain out of combat but false at both
failures.

The inference therefore also requires the failed reading to hold for 1.5 seconds,
observed continuously (gaps over 0.5 seconds restart it) on one target out of combat.
The 1.5 seconds is an estimate of aggro reaction time, not a measurement. The `prepull`
research question tests it with an independent check: a melee swing within 2 seconds
of a "beyond" verdict is a contradiction.

### Swing interactions: open questions (2026-11-15)

Forever changes how several abilities meet the auto-attack, and two of them decide queue
rules that are not yet written:

- **Slam and the swing timer.** The official deep dive says Improved Slam stops Slam
  delaying the swing, which implies baseline Slam still resets it; one medium-confidence
  source says the reset is gone. Arms lists Slam ungated. If the reset is real, Slam belongs
  right after a white hit unless Improved Slam is known.
- **Reckless Swings and next-swing attacks.** Reckless Swings adds rage to the next melee
  attacks; a Heroic Strike or Cleave swing generates no rage. Whether such a swing spends a
  charge decides whether Heroic Strike should wait while the buff runs. Source-backed
  candidate: the aura has 4 proc charges with proc mask 0x4 (done melee auto attack) and
  triggers 1329554, so a next-swing ability, a melee spell, should neither proc nor spend one.

The `swing` research question measures both. Main-hand `EVIDENCE` swing rows carry the gap
since the previous swing, its ratio to the swing duration, and the rank-1 id and age of
the player cast that preceded it. A reset shows as a ratio above 1 with the cast about one
weapon speed before the swing; no reset keeps a ratio near 1.

Rage is not measured. Its threshold verdicts work like mana's, but the scope rule allows
questions, not amounts, so per-swing rage gain is out of reach by design. Instead, each
Reckless Swings cast opens a window that closes, as one `EVIDENCE procWindow` row, at the
first main-hand swing that no longer finds the buff. Presence is the single threshold
question (`GetAuraStackAtLeast(player, id, 1)`); the charge count is never read. The row
counts the swings the buff survived, the next-swing casts and the trigger casts in between.
If next-swing swings spend no charge, windows that contain one outlast plain windows. The
analyzer's `stats` check reports min, median and max per case. Nothing in the queue reads
these rows; they settle the two rules before either is written.

### Ability lockouts: open question (2026-11-16)

Forever's data shows two lockout shapes. Mechanic immunity: Power Word: Shield is a
`shielded` spell and Weakened Soul (6788, 15s) grants immunity to that mechanic; Divine
Shield, Divine Protection and Blessing of Protection are `invulnerable` and Forbearance
(25771, 60s) blocks them. Explicit restrictions (`SpellAuraRestrictions`): Forbearance
for those spells and Templar's Bulwark, Tangled Causality for Ice Block, Shadowform for
Penance. Which cast applies Weakened Soul or most Forbearance is server-scripted, not in
the data. Unknown: whether `IsSpellUsable` already refuses a locked spell, whether the
lockout aura reads in combat, and whether a cast's target reads. `/jac inspect start
lockout` records one `EVIDENCE lockout` row per change of each known pair (raw aura
lookup, stack helper, addon and game usability, readiness, combat) and, per cast of a
watched spell, how its target relates to the player (never the name).

Measured 2026-11-16 (Forever priest, sessions 20261116-200437-1 and -200553-1, 159 rows):

- Weakened Soul still blocks a self-recast: the attempts return "immune". It lasted 15s
  (applied t=55813.7, removed t=55828.7).
- Neither the game (`C_Spell.IsSpellUsable`) nor the addon refuses Power Word: Shield
  while Weakened Soul is up: every row with `auraRead=aura` has `usable=true
  gameUsable=true`.
- Weakened Soul does not read in combat: every combat row is `auraRead=nil auraUp=nil`,
  including the row right after a combat start that began with it present.
- The cast's `targetIsSelf` read `false` on all 38 casts, including one that put Weakened
  Soul on the player, so the `UNIT_SPELLCAST_SENT` name comparison was wrong, not the
  target. The cast row now adds `nameIs` (self, selfFull, empty, target, other) and
  `targetUnit` (none, self, hostile, friendly); a rerun decides whether a self-cast can be
  identified.
- Rerun (session 20261116-205838-1, 11 casts, all in combat, mostly `@mouseover` on the
  player frame): every cast still read `nameIs=other`, including one with the player
  targeted. `targetUnit` says nothing about a mouseover cast. An unreadable player name
  would also produce `other`, so the cast row now adds `mouseover`, the read shapes of the
  player's and target's names (`meName`, `targetName`), `nameHyphen`, and
  `nameIsUnit` (`UnitIsUnit(name, "player")`); an unreadable player name reads
  `nameIs=meUnreadable`.
- Third run (session 20261116-210123-1, 15 casts, 1 out of combat): the player's name and
  the target's name read plain in and out of combat, the SENT name has no realm hyphen,
  yet it never equals `UnitName("player")` as text. `UnitIsUnit(name, "player")` read
  `true` on all 15, in combat included. The out-of-combat cast (mouseover on the player
  frame) put Weakened Soul on the player, so `true` was right there. Two casts read
  `mouseover=hostile` with `nameIsUnit=true`, consistent with a `[@mouseover,help]`
  fallback to self. Still missing: a cast on another player, to confirm `nameIsUnit`
  reads `false` for them. The probe now also logs Renew (139) casts for target identity
  only, so a Renew or shield on any friendly player outside a group supplies that control.
- Fourth run (sessions 20261117-060327-1 and 060346-1, 19 casts of Renew and the shield on
  other players and self, in and out of combat): `nameIsUnit=false` on every cast with
  `mouseover=friendly` (6) and `true` on every cast with `mouseover=self`, so `UnitIsUnit`
  does tell another player from the player. The out-of-combat self shield again read
  Weakened Soul up. Four casts with `mouseover=none` and a friendly target split two
  `false`, two `true`; the probe does not record which unit the macro chose, so those
  stay unattributed (a `[@mouseover,help][@player]` fallback would explain the `true` ones).
  A false self only costs a 15s park behind ready defensives.

Adopted (2026-11-16): `SpellDB.SELF_LOCKOUTS` (`PRIEST_F`: Power Word: Shield, Weakened
Soul, 15s). `DefensiveEngine` arms a hold on `UNIT_SPELLCAST_SENT` when
`UnitIsUnit(target, "player")` is plain `true`, starts it on the `UNIT_SPELLCAST_SUCCEEDED`
with the same castGUID (an "immune" attempt never succeeds), and parks the spell with the
on-cooldown entries until it ends. Secret, missing or non-true identity holds nothing.
Adopted (2026-11-17), from build 1.60.1.70938 data without a capture: `PALADIN_F`
Forbearance (25771, 60s). The hold is keyed by the lockout aura, so a cast of Divine
Shield, Divine Protection (both `selfOnly`, no identity check), Blessing of Protection on
the player (identity checked) or Avenging Wrath 407788 (`applyOnly`: gives Forbearance,
not blocked by it) holds all three blockable spells. Divine Shield and Divine Protection
already share a cooldown; the gap closed is Blessing of Protection against those two. The
lockout probe records 642, 498 and 1022 casts; a paladin run would confirm that each
applies Forbearance on Forever.

### Time-left clocks (2026-11-17)

`AuraClock.lua` is the one passthrough that draws a held icon's time left on every surface
(queue, defensive, nameplate overlay). Producers record the hold (`SpellQueue` for sunk
entries: self-buff, totem slot, target debuff; `DefensiveEngine` for self-lockouts); the
module draws the engine's DurationObject or aura container first, then a plain window (a
reading taken while plain, or our cast plus a known duration), else nothing. Redraws follow a
version bumped by target change, `UNIT_AURA` (player, target), `PLAYER_TOTEM_UPDATE`, combat
edges, hold changes and lockout start/end.
Not yet measured on Forever: whether `GetTotemDuration` draws in combat (it already backs
`IsTotemSlotOccupied`) and whether `GetTotemInfo` reads secret in combat. The totem fallback
(`BlizzardAPI.GetTotemWindow`) learns each totem's duration from a plain `GetTotemInfo`
reading and times the slot's latest own cast (`NoteOwnCast`); a totem never read plain has no
estimate. Buff windows are read at draw time from `BlizzardAPI.GetBuffWindowRemaining`.

Fallback ladders (2026-11-17), most reliable first. Self buff: form; the Cooldown Manager's own
icon (exact in combat); swing-speed evidence for haste buffs; a plain aura read (its expiry
and, since 2026-11-17, its real duration, any rank); that remembered expiry while auras are
secret; the out-of-combat aura snapshot; our own cast plus the learned duration, else the
data's base duration. A reading older than our latest cast yields to the cast. A cast whose
aura has another id (Bloodrage, 29131) is timed by its cast window, never by an aura of the
cast's id (`tools/audit_forever_auras.py`). Target debuff (`DotTracker`): the cast plus the
rank's data duration, dropped on a miss, dodge or parry in the hit window, held on IMMUNE, reset
on target change and kill, confirmed by a plain instance or the Cooldown Manager.

Early removal: the Cooldown Manager icon sees it exactly for tracked auras. Otherwise a mapped
instance in `UNIT_AURA`'s removed list (RedundancyFilter, `GetAuraRemovedAt`, any rank) ends
every source older than the removal; one within 0.5s after our cast is the refresh replacing
the old aura. Measured on Forever (session `20261117-122140-1`, priest level 9): the list reads
plain out of combat and secret in combat (session key `auraRemovals`), as on Retail 12.1. So
the removal route ends a buff's estimate only out of combat; in combat, the Cooldown Manager
icon is the only removal signal, and an untracked buff keeps its estimate to the end.

### GCD reference spell: measured (2026-11-17, build 1.60.1.70959)

Forever's data has no retail GCD dummy 61304, so `IsGlobalCooldownRunning`, the GCD
lookahead and `GetGCDInfo` answered nil there. `/jac inspect start gcdref` read three
candidates at each player GCD cast and again 2s later: 61304, 29515 ("TEST Scorch", Mage
class set, start-recovery category 133) and 1283885 ("[DNT] Cooldown Never Secret Test
Spell", category 133, no class, in both clients' data, with 61304's `Attributes_15` high bit).

Captures: Mage 7, Priest 9 and Hunter 14 (no mana), every control met across the three.

- 61304: missing on every row.
- 1283885: `GetSpellCooldownSecrecy` NeverSecret on all 42 reads; `isActive`, the plain
  duration and the duration-object verdict agree on every row. Active at GCD casts, inactive
  2s later and at off-GCD casts (wand Shoot, the first Auto Shot), in and out of combat.
  The few idle reads that stayed active had a GCD started inside the 2s: the next cast 11-12ms
  later, or instant Hunter shots the probe does not log (cast-time index 18 reports a
  non-zero cast time).
- 29515: the same active/inactive answers, but ContextuallySecret, and its duration reads
  secret in combat.
- The duration follows the GCD actually triggered: 1.304s after Priest and Hunter spells,
  1.500s after Hunter ranged shots. These rows carry no `GetHaste()`, so they support but do
  not settle the haste question below.

Adopted: `BlizzardAPI.GetGCDReferenceSpell()` returns the first of 61304 and 1283885 the
client's spell data has (61304 on retail, 1283885 on Forever), or nil for unknown; every
production GCD reader goes through it.

Per spell (2026-11-17): `BlizzardAPI.NoteCastGCD` reads the reference at our own cast start
(cast-time spells) and success (instants) and keeps the duration when that GCD began within
0.5s, per spell and rank chain. `GetSpellGCD` returns it, else the last GCD seen
(`GetGCDLength`), else nil. `GetSpellCycleSeconds` floors a spell's DPS cycle at it, so an
instant has a DPS and a short cast no longer reads faster than its GCD; with no GCD measured a
cast-time spell keeps its cast time and an instant stays unknown.

### Wand lead alternation: open question (2026-11-16)

A priest capture (2026-11-16 07:27) showed the lead trading places around casts and wand
shots. One cause is fixed: on Forever, spells read `isActive` with `isOnGCD` unset right
after a wand shot, so `IsSpellReady` now asks the ignore-GCD duration object there. The
rest is the wand itself: it read `ready=false` (`isOnGCD` false, its auto-repeat timer)
and a running auto-repeat is deliberately never asked for again, so the lead still trades
between the wand and a spell. `/jac inspect start wand` records one `EVIDENCE wandState`
row per change of the wand's reads (`RunningAutoSwing`, `IsAutoRepeatSpell`, readiness
with its reason, usability, cooldown flags) beside the cast in progress, the displayed
lead and the weapon comparison, so the queue can treat a running auto-repeat as one
steady state.

### Which hits push a cast back: measured (2026-11-16 08:32, priest level 8, Smite 1.739s)

Capture `20261116-083206-1`, 17 pushbacks on 9 Smite casts, one then two attackers:

- Every unabsorbed WOUND school seen pushes: physical (1) and nature (8). Five absorbed
  hits (`flags=ABSORB`) landed mid-cast with `castDelayMS=0`: absorbed hits do not push.
- Pushback per cast diminishes: 1.0, 0.8, 0.6, 0.4 s for hits 1 to 4 (three casts reached
  1.8 to 2.8 s). A fifth hit was not observed.
- Each push is capped by the cast's progress so far: first pushes of 0.28 to 0.95 s each
  equal the time since the cast (or the previous push) started. One attacker averaged
  0.67 s per Smite (about 39%); two attackers reached 1.9 to 2.8 s (110 to 160%).
- A physical WOUND arrives 0.29 to 0.80 s after its `UNIT_SPELLCAST_DELAYED`; a nature
  WOUND arrived in the same frame.
- `weaponComparison` read `manaRegen=nil` in combat and 14.75 out of combat: base mana
  regeneration was unreadable in combat in this capture (secret or zero not yet separated).

### Which hits push a cast back: probe (2026-11-16)

`/jac inspect start pushback` records every player combat result (`action`, `flags`,
`school`) with the cast or channel in progress, that cast's `castDelayMS` and `sinceDelay`
since the last pushback, beside each pushback's total `delayMS`. Still unobserved: a fifth
push on one cast, damage over time ticks, partial absorbs and pushback resistance. The
combat log is `HasRestrictions` in Forever's docs and was removed on Retail 12.0; it is not
registered, since a blocked registration could raise a forbidden-action warning.

### Look-ahead: warrior measured (2026-11-17 09:09, level 9-12)

Session `20261117-090926-1`, one pull: Charge, Rend x3, Heroic Strike x5, Thunder Clap x2,
Hamstring x2, Battle Shout, one parry.

- Rage read `secret` at every send, out of combat too: the amount is never readable, so rage
  gains cannot be added to it. Usability (`C_Spell.IsSpellUsable`) stays plain.
- Instants (Charge, Rend, Thunder Clap, Hamstring, Battle Shout): sent and succeeded in the same
  frame, and in that frame the spell's cooldown went active, combat began (Charge), usability
  turned false and the Cooldown Manager aura turned on (Rend, Thunder Clap, Hamstring, Battle
  Shout). The game itself catches up instantly; a ledger adds nothing for them.
- A parry on Rend arrived in the send frame and its Cooldown Manager aura never turned on.
- Charge: combat starts at the cast, melee reach read true 0.40s later, the first swing landed
  at 0.88s. While in flight every melee ability is unusable, so the queue now keeps the
  arrival lead in slot 1 instead of WAIT (`b.landingMelee` in the WAIT stage).
- Heroic Strike (next swing) succeeds only with the swing, 0.81-1.48s after the send; the queue
  already treats it as queued from the press.
- `GetPlayerAuraBySpellID` never reported Battle Shout in combat; the Cooldown Manager did.

Still open: combo points (rogue) and cast-time spells (caster).

### Look-ahead: open question (2026-11-17)

The queue can treat an outcome of the player's own confirmed cast as already happened, from
spell data, until the game's own reading catches up: a charge-effect closer (effect 96,
`SpellDB.LandsAtTarget`) already orders melee for arrival (`SpellQueue._LandingInFlight`, until
the 5-yard reading, a target change or 3s). Resource gains (energize effect 30, combo points
effect 80; Charge rank 1 grants 90 tenths of rage), cooldown starts, applied auras and combat
start are candidates for one pending-outcome ledger. Unmeasured: when each appears after the
send, and whether rage and energy read plain in combat. `/jac inspect start lookahead` records,
per own cast, a baseline at the send and every change of power (with plain/secret kind), combo
points, the spell's cooldown, its player aura, its Cooldown Manager aura, melee reach, combat
and usability, with the cast's milestones and the target's combat result, for 3 seconds.

### Threat: measured in a group, opt-in cues built (2026-11-17)

Candidate signals for opt-in threat cues (a tank losing a target, damage about to pull), not
yet used by any decision. Docs (Forever build 1.60.1): `UnitThreatSituation`,
`UnitThreatLeadSituation`, `UnitDetailedThreatSituation` and `UnitThreatPercentageOfLead` are
secret only when the game restricts threat state or values, with predicates
`C_Secrets.ShouldUnitThreatStateBeSecret` / `ShouldUnitThreatValuesBeSecret`. Blizzard's own
frames give damage `UnitThreatSituation` and tanks `UnitThreatLeadSituation`, and decide "tank"
from `UnitHasEffectivelyTankAura` or the Tank role.

Measured: solo captures read the player's threat state plain in combat. Grouped (session
`20261117-110741-1`: party of two, open world, Tank role, Battle Stance): both predicates false
in all 74 target samples, every nameplate read plain, and the reads matched the documented
meaning (state 3 / lead 0 tanking securely, state 2 / lead 1 slipping, state 0 / lead 3 not
tanking; scaled above 100 only while not tanking; raw 255 when alone on the list). The tank aura
read false in Battle Stance. Not measured: instances, Defensive Stance, aggro marks.

Built (opt-in `defensives.threatCues`, DefensiveEngine): on the target only, in a group or with
a pet, a threat drop for damage or healer at state 1 or above, a taunt for a tank not tanking,
a threat boost for a tank whose lead reads 1-2. Any secret or unknown read offers nothing. External reports disagree: a Forever beta
forum thread (October) found the detailed values secret for nameplate and party units, while a
2026-11 Forever addon spec (ollidiemaus/qol issue 145) found both predicates false in combat in the
open world and a dungeon. Threat events do not fire on every change of the numbers.

Spell data (generated `THREAT_ROLES`, `SpellDB.GetThreatRole`): aura 668 is the
effectively-tank aura (Defensive Stance, Bear and Dire Bear Form, Righteous Fury); ATTACK_ME or
MOD_TAUNT taunts; a negative THREAT effect, negative MOD_TOTAL_THREAT or FEIGN_DEATH drops
threat; a positive THREAT effect adds it (Sunder Armor). Pet spells (Growl ranks, Intimidation)
and Tame Beast also carry THREAT effects and must be filtered by the cue. The research question
`threat` (session key `threat`) records every read with its secrecy predicate.

### Global cooldown under haste: open question (2026-11-15)

Unknown: whether haste shortens the global cooldown on Forever. A capture showed Smite
hasted to a 1.304s cast; spell data gives Smite a 1.5s global cooldown. The weapon
comparison divides a hit by cast time alone, an upper bound for any cast shorter than its
global cooldown, and a global cooldown floor stays out until this is measured.

Source-backed candidate, not measured: Icy Veins' Forever Balance Druid stat page (Voulk,
updated 2026-11-04 for launch, https://www.icy-veins.com/wow-forever/balance-druid-ranged-dps-pve-stat-priority)
states that haste reduces the global cooldown to a minimum of 1 second and does not affect
spell cooldowns. RankedBoost's combat rules page (updated 2026-11-11) still lists the rule as
not announced. If the guide is right, a hasted cast and its global cooldown shrink together,
so a spell whose data cast time is at least its global cooldown never falls below it: cast
time alone is then exact for every current filler, and a floor matters only for a data cast
shorter than its global cooldown or a hasted cast under 1 second.

Method (`/jac inspect start gcd`): `EVIDENCE gcd` rows record, at the start of each player
cast (instants: at success), the GCD reference spell's duration (61304 on retail, 1283885 on
Forever; see "GCD reference spell" above), the spell's live cast time and `GetHaste()`, with
hidden or missing reads printed as `secret` or `unknown`. Rows also carry the cast spell's own
cooldown (`spellCd`, with `onGcd`); for a spell without a cooldown of its own that should be the
global cooldown, which the `unhastedSpellGcd` and `hastedSpellGcd` checks summarize. If the
hasted out-of-combat rows show a GCD below the spell data value, the scale against
`haste` answers the question; equal values mean the GCD is fixed. Combat rows show whether
the reads are hidden there.

## Best additional experiments

Priority is expected utility versus uncertainty, not implementation approval.

### 1. Incoming healing and healing debt: highest-value new composition

**Candidate: extend the existing numeric zero-gate to healing signals.**

[Unit APIs][unitheals] expose `UnitGetIncomingHeals(unit, healerUnit)` and
`UnitGetTotalHealAbsorbs(unit)`. Both explicitly return secret numbers. They do
not have the aura-read access precondition. JustAC already asks the analogous
shield-presence question with `UnitGetTotalAbsorbs` plus `IsSecretZero`.

Useful experiments:

- Is any healing currently predicted for this unit, including from the player?
- Does this unit have a heal-absorb debt?
- After accounting for predicted healing, is any heal-absorb debt left?

The third question is particularly valuable: the engine can subtract secret
amounts without Lua doing arithmetic. The [heal-prediction calculator][healcalc]
has `GetHealAbsorbs()` and `GetIncomingHeals()`. Its
`ReducedByIncomingHeals` mode reduces heal absorbs and incoming heals against
each other and clamps to zero, explicitly documented in the [mode definitions][healmodes].
Passing the resulting **numeric amount** through the existing zero-gate is a new,
unverified composition. It is not a claim that the calculator's `clamped`
**boolean** is plain or can use that numeric gate.

Use addon-owned calculators, refresh each with
`UnitGetDetailedHealPrediction(unit, healerUnit, calculator)`, and explicitly set
the calculation modes relevant to the question. The existing prediction row uses
the player as healer; the new group-healer rows test each present source separately.
Nil healer means healer-specific values are zero, not "all healers".
`HasSecretValues()` is NeverSecret but only reports secrecy, not successful/live
population.

Controls: no incoming heal, another player's heal, own heal, cancellation,
heal landing, debt without incoming heals, debt smaller/larger than predicted
healing, full health, unit death and target swap. A clamped zero can also mean
no displayable missing health; it does not always mean no raw incoming healing.
Probe raw presence and reduced/clamped results separately. The secret zero-gate's
integer formatting floors values below one; do not describe it as an exact
fractional comparison. A failed call, nil incoming-heal result, or unpopulated
calculator is unknown: reject it before the zero-gate, which otherwise treats
nil as zero.

Potential use: explain heal urgency or reduce redundant non-emergency heal
reminders. **Incoming heals are predictions, not guaranteed survival.** They can
cancel or land late; do not suppress panic defensives or change heal ordering
without separate behavior approval and validation.

Existing `/jac inspect enginesig` reports calculator secrecy and clamp booleans;
it does **not** test this new numeric-result composition.

### 2. Target control state without aura enumeration

**Candidate: engine LoC count and duration for the target.**

The [LoC API][loc] offers `GetActiveLossOfControlDataCountByUnit(unit)` and
`GetActiveLossOfControlDuration(unit, index)` separately from the restricted
detail records. The count has no conditional secrecy annotation; that is an
experiment opportunity, not a NeverSecret guarantee. JustAC already uses the
player count and player duration paths, but not the by-unit count as a general
target control signal.

First test whether relevant Forever NPC effects are represented at all.
Positive/negative controls must include stun, fear, root, slow, break, expiry
and an unaffected target. Root is not incapacity, and a count does not identify
the control type or prove the target cannot attack. Only if duration retrieval
works can the existing duration-threshold helper ask a specific expiry question.

Potential use: avoid overlapping an otherwise unnecessary control suggestion.
Never gate an interrupt solely on an unclassified LoC count.

### 3. Cooldown Manager pandemic markers

**Candidate: read the engine's existing refresh-window decision.**

The [viewer implementation][pandemic] creates `item.PandemicIcon`, shows it inside
the pandemic window, then releases it and clears the reference outside the
window. This is the same family of engine-produced frame state as our resource
and tracked-aura bridges, and can avoid a denied `GetAuraDuration` call.

Existing `/jac inspect cvitems` already reports this surface. Validate against
a known matching tracked entry, with pandemic enabled, and actual enter/exit/
refresh/remove transitions. Reject edit previews, pooled/reassigned items,
hidden/stale viewers and wrong target epochs. Missing `PandemicIcon` alone is
not proof that an aura is absent or not refreshable.

Forever's no-carryover behavior is a major limitation: an aura with no pandemic
window may never create the marker. It cannot replace arbitrary remaining-time
thresholds, and should not change Forever refresh policy to Retail's policy.

### 4. Blizzard's classified nameplate aura buckets

**Candidate: category membership, not spell identity.**

[NamePlateAurasMixin:AddAura][plateauras] sorts live auras into separate
`buffList`, `debuffList` and `crowdControlList` structures in Blizzard execution.
This resembles the existing party-alert membership bridge: the useful answer
could be that a category contains something, even while its fields stay secret.

However, these are priority-table wrappers, not plain arrays. Do not use
`#list`, `next(list)` or wrapper metadata as aura counts. Their read-only `Size()`
method returns the underlying sorted-array length in the inspected
`Blizzard_SharedXMLBase/TableUtil.lua:742`. First determine whether that
supported read on a live structure exposes plain membership at all,
without calling Blizzard mutation/refresh methods or entering protected data.
If not, stop that route. A parent `CrowdControlListFrame:IsShown()` is a display
preference, not evidence that a CC aura exists.

Semantics are deliberately broader than the names suggest:

- The CC bucket includes `nameplateShowAll` auras as well as classified CC.
- Enemy buffs are filtered for stealable or important auras, not enrage alone.
- Source filters, display caps, nameplate styles and replacement addons affect
  what is present or rendered.
- `item.spellID = aura.spellId` copies secrecy; it does not reveal identity.

Potential use: coarse category cues where the direct LoC route is insufficient.
Lower priority than direct APIs and the tracked-aura bridge. No exact curse,
dispel type, ownership or control-mechanic claim follows from bucket membership.

### 5. Aggro-highlight state as a coarse fallback

**Candidate: Blizzard has computed a threat warning, not "I am tanking".**

[CompactUnitFrame threat logic][threat] branches on threat, then drives
`aggroHighlight:SetShown`. [Nameplate code][plateframe] mirrors that into
highlight frames/animations, another possible plain frame-state bridge.

Crucially, the helper reports nothing outside a party. For an enemy plate it
uses `UnitThreatSituation` for non-tanks but `UnitThreatLeadSituation` for
effective tanks. A lit highlight therefore has role-dependent meaning.
Edit previews can supply an explicit fake threat state.

Try direct readable threat first. A frame fallback needs party/role/options,
preview exclusion, current-unit binding and live transitions. Test losing and
regaining threat as both tank and non-tank. Do not infer threat percentage,
enemy count or confirmed incoming damage from the highlight.

### 6. Target profile and kill time: probe (2026-11-18)

**Measured sample: GUID readable in combat; maximum health secret even out of combat.**

`/jac inspect mobprofile arm` (research companion) reads every hostile NPC seen
as target, mouseover or nameplate. It
tallies each field plain, secret, nil or error separately for in and out of
combat. Plain reads build a
per-NPC profile: creature type, family, classification, level range, max health
per level and power.

Capture flushed 2026-11-18 at 10:03:16: two normal Mechanical NPC types, Harvest
Golem (36, level 11) and Harvest Watcher (114, levels 14-15), with three solo kill
records at player level 14. The field tallies pool target, mouseover and nameplate
reads; repeated observations are not independent NPC samples.

| Field | Out of combat (16 reads) | In combat (24 reads) |
|---|---|---|
| GUID, name, level, effective level, classification, creature type ID | All plain | All plain |
| Power type, tap denied, trivial, boss | All plain | All plain |
| Maximum health, maximum power | All secret | All secret |
| Creature family | All nil | All nil |

No field calls errored in this sample. The original OOC-only GUID hypothesis is
not supported here: a readable live GUID can identify the NPC in combat, without
a name-based inference. This does not establish readability on other clients,
maps or unit contexts. The probe does not retain per-read unit tokens, build or
instance metadata, so this capture cannot certify dungeon/group behavior.
Keep `pcall` and secrecy checks on every live read; call failure, nil and secret
remain distinct unknown outcomes. `InCombatLockdown() == false` labels the OOC
bucket; it is not proof of unrestricted data access. Maximum health supplied no
plain values to the profiles in this capture.

Kill time uses only plain identity and our own clock: the pre-pull target GUID
(or a plain in-combat swap) is stamped at player combat entry or target selection and closed by
`PARTY_KILL`, whose victim GUID is plain. It is a per-player time-to-kill from
that timestamp, not proof of our first hit or the mob's lifetime. Kills outside
the group are not seen. Never derive it from health bands. Recorded intervals:
Harvest Golem 8.2 seconds; Harvest Watcher 34.6 and 33.7 seconds. These are too few
samples for a queue policy.

Adoption needs: max health and GUID behavior confirmed per context (open world,
dungeon, solo, grouped), kill times stable enough per NPC to separate short and
long fights, and an explicit fallback to the existing level rule for unseen mobs.
A profile from an earlier character level or gear set is context, not a verdict.

### 7. Classic creature-type immunity rates: reference audit (2026-11-18)

Source: local vMaNGOS `db-sqlite-70e38cd.zip`, `mangos.sqlite`,
`creature_template`, revision `70e38cd10ce430f7ce41668c85fb40d2779bc646`.
Select the greatest `patch` per `entry`: 10,381 distinct NPC templates, each
counted once. These are template-weighted rates, not encounter-weighted rates;
the denominator includes friendly, unused and special-purpose templates.

Bleed means `mechanic_immune_mask & (1 << (15 - 1))`. Poison means the explicit
`immunity_flags & 0x20` flag, not Nature-school resistance or immunity.
Meanings were checked against vMaNGOS at the same revision:
[creature flags](https://github.com/vmangos/core/blob/70e38cd10ce430f7ce41668c85fb40d2779bc646/src/game/Objects/CreatureDefines.h)
and [their application](https://github.com/vmangos/core/blob/70e38cd10ce430f7ce41668c85fb40d2779bc646/src/game/Objects/Creature.cpp).

| Creature type | NPCs | Bleed mask set | Bleed mask absent | Poison flag set | Poison flag absent |
|---|---:|---:|---:|---:|---:|
| Unspecified (0) | 22 | 0 (0.00%) | 22 (100.00%) | 0 (0.00%) | 22 (100.00%) |
| Beast | 1,234 | 12 (0.97%) | 1,222 (99.03%) | 1 (0.08%) | 1,233 (99.92%) |
| Dragonkin | 229 | 3 (1.31%) | 226 (98.69%) | 4 (1.75%) | 225 (98.25%) |
| Demon | 266 | 4 (1.50%) | 262 (98.50%) | 5 (1.88%) | 261 (98.12%) |
| Elemental | 324 | 236 (72.84%) | 88 (27.16%) | 73 (22.53%) | 251 (77.47%) |
| Giant | 61 | 4 (6.56%) | 57 (93.44%) | 0 (0.00%) | 61 (100.00%) |
| Undead | 702 | 234 (33.33%) | 468 (66.67%) | 7 (1.00%) | 695 (99.00%) |
| Humanoid | 6,628 | 10 (0.15%) | 6,618 (99.85%) | 1 (0.02%) | 6,627 (99.98%) |
| Critter | 99 | 0 (0.00%) | 99 (100.00%) | 0 (0.00%) | 99 (100.00%) |
| Mechanical | 106 | 98 (92.45%) | 8 (7.55%) | 18 (16.98%) | 88 (83.02%) |
| Not specified (10) | 616 | 19 (3.08%) | 597 (96.92%) | 2 (0.32%) | 614 (99.68%) |
| Totem | 94 | 5 (5.32%) | 89 (94.68%) | 0 (0.00%) | 94 (100.00%) |

"Absent" is an exception to a proposed blanket type rule, not evidence that the
spell can land. This audit does not resolve aura-, script- or spell-specific
immunity, and Classic masks are not confirmed Forever behavior. For example,
Harvest Golem (36) has no explicit poison flag in this snapshot, while Forever's
learned observations associate it with Serpent Sting `IMMUNE` results. Those
events lack source/spell attribution, so neither the snapshot nor that association
alone proves a general poison rule.

The eight Mechanical bleed-mask-absent candidates are 2109 Steam Tank,
4955 Theramore Archery Target 1, 4957 Theramore Combat Dummy 4,
4975 Theramore Archery Target 2, 5187 Southsea Cannon, 5625 Theramore Transport,
8447 Clunk and 8880 Mechastrider. Several names suggest special-purpose templates;
they were not silently removed from the denominator.

**Design candidate, not an adopted queue rule:** type defaults plus explicit
NPC overrides must be per immunity category, with verified per-NPC outcomes
taking precedence. Mechanical bleed is the strongest candidate for a small
exception list; Elemental bleed has 88 candidate exceptions and Undead is mixed.
Within this snapshot, defaulting Mechanical and Elemental to bleed-immune and
other types to unmarked needs 387 NPC overrides (96 unmarked, 291 marked),
versus listing all 625 marked templates. That is compression of this snapshot,
not authority to classify previously unseen Forever NPCs. Explicit vulnerable,
immune and unknown outcomes must remain distinct.

Attribution: vMaNGOS contributors and the upstream MaNGOS, MaNGOSZero, Nostalrius
and Elysium projects. Inspected source headers permit GPL-2.0-or-later; separate
DB-dump redistribution terms still need verification before adopting data.
This is a read-only aggregate audit, not a vendored immunity database.

## Other high-value API findings

| Item | Opportunity | Required verification |
|---|---|---|
| `UnitHasEffectivelyTankAura("player")` | Better tank context alongside assigned role | [Blizzard's role helper][tank] uses it first. Identity secrecy applies; measure form/stance/aura transitions. Never override player configuration. |
| `C_Spell.IsActiveSpell(id, unit)` | Direct active-toggle state, possibly replacing a heuristic | [Contract][toggle] explicitly covers toggles and carries aura/identity secrecy. Not a general buff-presence API or bypass. |
| Pet happiness and food compatibility | Out-of-combat hunter feeding reminder | Implemented 2026-11-16 (`DefensiveEngine` `AppendPrecombatPetFeed`): saved hunter captures read `C_PetInfo.GetPetHappiness` plain (level 3 at 125% damage, 1 at 75%), and nil without a hunter pet. Feed Pet is offered out of combat below happy, not while the pet eats (effect 1539). Still open: diet and inventory (no check that suitable food is in the bags). |
| `UnitHealthPercent(..., usePredicted=true, curve)` | Compare a behavior-specific predicted-health threshold with the existing actual-health gate | Source exposes the switch but does not define the prediction horizon/composition here. Current JustAC deliberately passes false. Do not call this incoming-heal coverage or replace current health bands without measurement. |
| Duration predicates | Potentially simplify the scratch-Cooldown reader | `HasSecretValues` is contracted NeverSecret; `IsActive`/`HasExpired` are not. Existing Retail evidence records secret `IsZero`. Re-test only a concrete client/build difference, not absence of annotations. |
| Event-timed `isOnGCD` | More reliable readiness evidence | [Field documentation][spellshared] says not to trust it except when responding to `SPELL_UPDATE_COOLDOWN`. Compare event-time and ticker-time transitions before changing shared readiness. |

## Closed routes and false positives

- **AuraContainer is display-only.** Its Shown state is explicitly secret and its
  preallocated pool masks aura count. Do not try to read count/visibility back
  into a queue gate. See the [hard limit](AURA_CONTAINER_12.1.md#the-hard-limit-display-only-permanently).
- **Direct secret-boolean reads remain closed unless independently measured plain.**
  `SetAlphaFromBoolean` renders one; it does not promise a readable alpha or
  shown-state result. Never pass a boolean directly to the numeric zero-gate.
  The engine numeric-selector composition below is a separate, unverified test.
- **Secret-argument annotations are not call-access permission.**
  Inspect `Requires*`, `HasRestrictions`, result secrecy and actual taint behavior
  separately. A callable function can still return a secret or no result.
- **`UNIT_COMBAT` lacks attacker/spell attribution** and its amount is explicitly
  secret. Feedback alone cannot prove our DoT landed or identify a reactive proc.
- **Combat Audio Alerts cast speech has no persistent interruptibility verdict**
  in the inspected `ProcessCastState` path. Do not hook its secret-processing
  methods or invert speech timing into hidden cast information.
- **Shared curse-family activity does not distinguish its members.** The previous
  Forever capture found secret instance identity. Do not resurrect tooltip/aura
  identity reads just because the family entry's active state is plain.
- **A plain value can still be stale.** Hidden UI, pooled items, disabled CVars,
  unit replacement, delayed updates and edit previews need explicit checks.
  Never write fields or replace handlers on Blizzard's secret-processing frames.

Older sections of [FOREVER_PROBE_PLAN.md](FOREVER_PROBE_PLAN.md),
[AURA_IDENTITY_12.0.md](AURA_IDENTITY_12.0.md) and
[SECRET_VALUE_THRESHOLD_GATES.md](SECRET_VALUE_THRESHOLD_GATES.md) contain
historical hypotheses or earlier-build access results. In particular, a remembered
plain aura instance does not authorize a new denied aura call. The recorded
secret `IsZero` result in the [signal matrix](12.0_COMPATIBILITY.md) is evidence;
an unannotated method in generated docs is not contrary evidence.

## Interrupt and CC dead-end review

### Highest-value new angle: an engine-selected numeric boolean

Both inspected clients contract
`C_CurveUtil.EvaluateColorValueFromBoolean(boolean, valueIfTrue, valueIfFalse)`
with secret arguments allowed when tainted. It returns a `SingleColorValue`,
not a boolean and not a curve evaluation. The [Forever contract][boolcurve]
matches the [Retail contract][retailboolcurve].

The temporary diagnostic composes:

1. Select numeric **1 for true, 0 for false** inside the engine.
2. Ask the existing numeric zero-gate whether the result is zero.
3. Negate only a confirmed plain boolean from that gate.

Exactly 1 matters: fractional components below 1 would floor to zero in the
existing formatter. This uses endpoint components, not out-of-range values such
as 100, a sweep, a timer inversion or arbitrary secret-number reconstruction.
`SingleColorValue` bounds are not defined by the generated signature alone;
actual endpoint acceptance and secret propagation still require client controls.

**Candidate only.** The contract does not promise that this composition yields
a branchable result. Plain controls and `secretwrap(true/false)` must both give
opposite, correct answers; real combat transitions must then agree with observed
events. A denied/missing selector, non-boolean input, nil number or secret result
is unknown/error, not false. Mock tests verify handling, not engine behavior.

The immediate feature questions are:

- Is the current cast noninterruptible? Cast and channel tuple positions differ.
- Is this cast important? `IsSpellImportant` accepts a secret spell identifier,
  but its result is not guaranteed plain.
- Is this cast aimed at the player? `PlayerIsSpellTarget` explicitly returns a
  secret boolean, so this is a particularly useful positive secrecy control.
- Does the player have full control, and is this unit charmed? Full-control
  does not name a mechanic; charm is not a general stun/fear/root detector.

Do not treat these as permission to recover spell IDs, cast times, aura identity,
health totals or hidden control mechanics. Nothing is wired into queue decisions.

### Cast-bar state: keep the distinction the older plan missed

The [current cast bar][castbar] secretwraps `GetEffectiveType()` and
`IsInterruptable()`. Its shield consumes a secret expression directly; rereading
the shield/bar type is still not a new route.

However, `ShouldIconBeShown()` has ordinary style/visibility early exits and a
conditional `HideIconWhenNotInterruptible` branch that returns literal booleans.
JustAC's existing [interrupt tracker](../UI/CastInterruptTracker.lua) already
uses this narrower icon-hidden route with a live visible bar, UNITFRAME-compatible
look, icons enabled and the hide-when-uninterruptible flag. The historical
"all cast-bar routes closed" conclusion was too broad.

This is not a reason to trust every hidden icon. Hidden/replaced bars, style
changes, suppressed icons and a target swap can invalidate it. Test positive and
negative transitions with stock and replacement UI. Important-cast indicators
and animations are directly driven by classifier output, with no demonstrated
plain-state loophole of their own.

### Event identity: a reliable key, not an interruptibility verdict

The [unit contract][castevents] marks engine `castBarID` NeverSecret in cast/
channel tuples and applicable start/stop/update events. It can correlate a cast
instance across updates and help reject stale stop/CC observations. It is not
the potentially secret GUID or spell ID.

Payload layouts differ: ordinary cast/channel start/update use argument 4;
interrupted/channel-stop use argument 5 after `interruptedBy`; empower-stop
uses argument 6 after `complete` and `interruptedBy`. The temporary event sample
records arguments 4/5 for its registered cast/channel events, not empower events.
Interruptibility-only events carry **only the unit**, so no cast key can be
invented for them. Events report transitions, not guaranteed initial state.

The current tracker uses local cast serials. Engine-key correlation is a future
reliability improvement, not an implemented behavior change in this pass.
Continuing the same cast after observed CC is contextual evidence, not proof of
permanent NPC immunity or proof that our CC landed.

### Player/target LoC: split presence from mechanic identity

The [secrecy predicate][locsecrecy] says restricted LoC details are **always**
secret except for an active PvP spectator/commentator, not merely during combat.
An ordinary player's out-of-combat detail sample is not a trustworthy plain
baseline. `priority` and `displayType` have NeverSecret exemptions, but do not
identify fear, root, slow, stun or a removable mechanic.

Count and duration remain separate candidates. Positive NPC controls are needed:
an empty target list may mean the effect is not represented, not that the NPC
is uncontrolled. Root/slow need not prevent action. Existing player LoC count,
duration and per-spell lockout helpers are stronger than a generic queue-wide
"cannot act" veto. Do not remove control-break recommendations during CC.

### DR and aura identity: no supported new generic immunity gate

The [DR API][diminish] offers a capability check, but category reads require the
system, may return nothing, and tracking verdicts/event payloads are secret.
There is no NeverSecret exemption for the nested `isImmune` field or category.
Do not infer a general PvE immunity table from supported PvP presentation.

AuraContainer readback, denied hostile aura calls, unattributed `UNIT_COMBAT`,
cast-audio timing inversion and tooltips remain closed for the old reasons.
Nameplate bucket membership is broader than CC and does not repair that identity
gap. The useful new experiment is the explicit boolean composition, not another
attempt to enumerate hidden auras.

## Probe and adoption plan

1. Start with `/jac inspect validate`, `/jac inspect errors` and
   `/jac inspect secrecy` to establish the client's baseline.
2. Prioritize healing presence/debt, target LoC, then tracked pandemic state.
   Reuse `/jac inspect enginesig`, `/jac inspect cvitems`,
   `/jac inspect frames` and `/jac inspect forever arm` where they already cover
   a leg. Those commands do not implement every experiment above.
3. Before any new probe implementation, approve its questions and controls.
   Keep output compact and change-only; persist a bounded, debug-gated series
   with unit/target epoch, source liveness, API success and plain/secret/unknown
   classification. Do not save raw secret payloads.
4. Require repeated positive and negative transitions **inside combat**, including
   consumption/cancellation and a target swap. A single plain false or empty
   sample proves neither access nor correctness.
5. Test Retail and Forever independently. Include player, pet and supported ally
   contexts as applicable, stock and replaced/hidden Blizzard UI, and both default
   and custom queues with explicit settings preserved. Failure is unknown, not
   healthy, ready, aura-absent or resource-sufficient.
6. Only after measurement, select the smallest shared capability/helper and test
   its fallback and ordering behavior. Do not add a per-class exception to generic
   readers or change thresholds/settings to manufacture an answer.
7. End recording, `/reload` or log out, then read SavedVariables. Disk data before
   that flush belongs to an earlier session. Record build, class, context and
   controls with each accepted finding.

No player-facing release note, version bump, build or publication is needed for
this research. Documentation remains excluded from the release package.

[audit-action]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua#L416
[audit-action-range]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua#L1036
[audit-spell-range]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua#L1129
[audit-game-error]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/GameErrorDocumentation.lua#L10
[audit-error-ui]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua#L146
[audit-threat]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua#L564
[audit-combat-log]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogDocumentation.lua#L123
[audit-combat-secure]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogSecureDocumentation.lua#L6
[audit-meter]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua#L21
[audit-meter-timer]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_DamageMeter/DamageMeterSessionWindow.lua#L292
[audit-toggle]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_GamepadActionBars/FlyoutRadial.lua#L171
[audit-wpp]: https://github.com/TrinityCore/WowPacketParser/tree/e46644410866709c82ed8c19353587c5b0507f08
[melee-swing-ui]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua#L397
[melee-swing-api]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua#L10
[melee-item-api]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L1550
[melee-interact-api]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L2072
[melee-distance-api]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L1108
[melee-spellbook-api]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua#L616
[melee-gamepad-ui]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_GamepadActionBars/MainActionBarFrame.lua#L208
[melee-compact-ui]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua#L1043
[melee-plate-options]: https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateFrameOptions.lua#L83
[swing]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua#L10
[spellshared]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua#L19
[action]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua#L1035
[overlay]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellActivationOverlayDocumentation.lua#L28
[unitheals]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L1257
[healcalc]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitHealPredictionCalculatorAPIDocumentation.lua#L142
[healmodes]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitHealPredictionCalculatorSharedDocumentation.lua#L34
[loc]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/LossOfControlDocumentation.lua#L44
[pandemic]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua#L526
[plateauras]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateAuras.lua#L145
[threat]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua#L599
[plateframe]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua#L454
[tank]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_SharedXML/UnitUtil.lua#L109
[toggle]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua#L659
[pet]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_FrameXML/PetHappiness.lua#L28
[boolcurve]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua#L50
[retailboolcurve]: https://github.com/Gethe/wow-ui-source/blob/297d7aaaa736f346b3e036f38ee088eaf7f8c07f/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua#L49
[castbar]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua#L886
[castevents]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L4615
[locsecrecy]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua#L100
[diminish]: https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDiminishUIDocumentation.lua#L9
