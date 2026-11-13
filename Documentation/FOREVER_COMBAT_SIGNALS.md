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
hidden number. Follow the [threshold scope rule](SECRET_VALUE_THRESHOLD_GATES.md#the-scope-rule):
no threshold sweeps, binary searches, timer inversion or arbitrary hidden-value
reconstruction. Unknown stays unknown. A readable result must also be live,
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
enemy is attacking the player. `GetEngagedEnemyCount` counts that membership,
not all enemies near the player or all members of a group pull.

Candidate group evidence is confirmed threat membership for a party member
against the same nameplate token, deduplicated by that token. It needs live
verification before widening any count. `UnitAffectingCombat` alone cannot
associate an enemy with our group. `UnitThreatLeadSituation` is a tank warning,
not a membership replacement. Keep observed player/group membership separate
from ability-specific range; never infer Consecration coverage from either
count alone. Compare solo/group-tanked pulls, before/after player damage,
unrelated nearby fights, missing nameplates and unreadable threat.

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

Use an addon-owned calculator, refresh it with
`UnitGetDetailedHealPrediction(unit, healerUnit, calculator)`, and explicitly set
the calculation modes relevant to the question. Nil healer means healer-specific
values are zero, not "all healers". `HasSecretValues()` is NeverSecret but only
reports secrecy, not successful/live population.

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

## Other high-value API findings

| Item | Opportunity | Required verification |
|---|---|---|
| `UnitHasEffectivelyTankAura("player")` | Better tank context alongside assigned role | [Blizzard's role helper][tank] uses it first. Identity secrecy applies; measure form/stance/aura transitions. Never override player configuration. |
| `C_Spell.IsActiveSpell(id, unit)` | Direct active-toggle state, possibly replacing a heuristic | [Contract][toggle] explicitly covers toggles and carries aura/identity secrecy. Not a general buff-presence API or bypass. |
| Pet happiness and food compatibility | Out-of-combat hunter feeding reminder | [Pet UI][pet] uses `GetPetHappiness` on `UNIT_HAPPINESS`/`UNIT_PET`; test hunter vs non-hunter pets, unavailable data, diet and inventory. Separate from pet healing/revival. |
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
