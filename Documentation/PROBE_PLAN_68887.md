# In-game probe plan - build 12.0.7 (68887) signal audit

Source audit date: 2026-07-24, against `r:\WOW\00-SOURCE` mirrors at 68887.
Goal: validate every candidate in-combat signal found in the source audit with
measured in-game probes before any feature consumes it.

## Ground rules (apply to every probe)

1. **Measure, never infer.** The annotation-gap precedent stands: docs claiming
   plain has been wrong before (texcoord secrecy propagation). A missing
   `Secret*` annotation is a *hypothesis*, not a fact.
2. Every read goes through the standard harness: `issecretvalue(v)` first, then
   `type(v)`, then compare. Print all three. Never bare-compare a candidate.
3. **Secret booleans throw on truthiness test** (`if b then`); secret numbers
   don't. Wrap every candidate boolean read in pcall inside the probe.
4. The screening rule for frame-state candidates: control-flow `Show()/Hide()`
   launders → plain; `SetShown(secretExpr)` does not. Each frame probe must
   report `issecretvalue(frame:IsShown())`, not just the value.
5. Hidden-bar freeze precedent: a hidden frame's state may be FROZEN, not live
   (Paladin holy-power bug). Every frame-state probe also reports
   `IsEventRegistered` liveness where applicable, and must be re-run with a
   unit-frame replacement addon loaded before a feature ships on it.
6. Contexts are not interchangeable. The predicate taxonomy distinguishes:
   - `SecretWhenInCombat` - combat only, anywhere
   - `SecretOnRestrictedMaps` - dungeon/raid, even out of combat
   - `SecretWhenUnitAuraRestricted` / `SecretWhenCooldownsRestricted` -
     combat OR encounter OR challenge mode OR PvP match
   - `SecretWhenUnitSpellCastRestricted` - unit-based (non-player/pet), not context-based
   - `SecretInActivePvPMatch` - PvP only
   A probe passing at an open-world dummy proves nothing about a dungeon.

## Context matrix

Run each probe batch in every context its predicates implicate; record results
per context (extend the `/jac inspect validate arm` diff pattern):

| ID | Context | How to get there |
|----|---------|------------------|
| C0 | Out of combat, open world | baseline |
| C1 | Solo combat, open world | training dummy or world mob |
| C2 | Dungeon, out of combat | walk into any normal dungeon |
| C3 | Dungeon, in combat | trash pull |
| C4 | Raid encounter / M+ (challenge mode) | LFR boss or M+ key |
| C5 | PvP match | random BG (skirmish for arena frames) |

Special states (orthogonal, induced inside C1 first, re-checked in C3):

| ID | State | How to induce |
|----|-------|---------------|
| S1 | Player CC'd (stun/fear/root) | mob with stun; or duel |
| S2 | School lockout / silence | get kicked mid-cast by an interrupting mob |
| S3 | Absorb shield up | PW:Shield from party priest, or self-shield class |
| S4 | Player < 35% and < 20% HP | stand in mob damage |
| S5 | Primary resource capped | pool energy/fury to max in combat |
| S6 | Own DoT on target, in pandemic window | any DoT spec, wait to <30% remaining |
| S7 | Empowered cast | Evoker alt |
| S8 | Target casting interruptible / uninterruptible | caster mob / boss cast |

## Implementation status (2026-07-24)

Session-1 probes are DEPLOYED: `locwatch` (extended: full field triples,
PLAYER_CONTROL_LOST/GAINED, GetUnitSpeed slows check, per-spell lockout
booleans, LoC duration object), `selfcast`, `auraids`, `cdfields`,
`secrecymap`, `frames`, `cvitems`, and the `durprobe` method sweep.

**One-command flow: `/jac inspect audit`** - arms everything, snapshots the
whole battery at baseline / combat enter / +10s / combat exit (up to 10
cycles), redirects locwatch+selfcast output into the same log, and stores
everything color-stripped in `JustACGlobal.probeLog`. Finish with
`/jac inspect audit off` + `/reload`; the transcript lands in
`WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua` for direct file reading.

Not yet implemented: `dr` (Batch 9, PvP-only), Batch 8 threat-pair additions,
Batch 10 display-sink spikes (DurationTextBinding, SetSpriteSheetCell).

## Probe batches

Batches are grouped by required context so one session covers many probes.
Priority order = feature value × novelty. Each probe reports
`issecretvalue / type / value` triples for every field.

### Batch 1 - extend `/jac inspect locwatch` - contexts C1+S1, C1+S2, then C3, C5

`locwatch` already exists (armed capture on LOSS_OF_CONTROL_ADDED/UPDATE,
dumps all entries' locType/displayType/spellID with secrecy checks). Extend it
rather than adding a new command.

The headline finding: player loss-of-control data is documented plain in combat.

Armed capture (locwatch pattern - CC windows are too short to hand-type):
on `LOSS_OF_CONTROL_ADDED` / `LOSS_OF_CONTROL_UPDATE` / `PLAYER_CONTROL_LOST` /
`PLAYER_CONTROL_GAINED`, dump:

- `C_LossOfControl.GetActiveLossOfControlDataCount()` - claim: plain integer
- `GetActiveLossOfControlData(1)` - per-field triples: `locType`, `spellID`,
  `displayText`, `startTime`, `timeRemaining`, `duration`, `lockoutSchool`,
  plus the NeverSecret trio `priority` / `displayType` / `auraInstanceID`
- `GetActiveLossOfControlDuration("player", 1)` - DurationObject; report
  `HasSecretValues()`, `IsZero()`, and scratch-Cooldown `IsShown()` probe
- `UIParent.isOutOfControl` - plain field claim
- For each of ~3 school-representative spells:
  `C_Spell.GetSpellLossOfControlCooldownInfo(id).isActive` and
  `.shouldReplaceNormalCooldown` - claim: NeverSecret booleans ("this spell is
  locked out right now")
- `C_Spell.GetSpellLossOfControlCooldownDuration(id)` - claim: no predicate

Unlocks: lockout-aware queue (suppress/deprioritize spells of a locked school),
"you are CC'd" state for the queue display, CC-remaining swipe.

**Slows/snares sub-probe (same session, get dazed by a mob or slowed in a duel):**
- Dump EVERY active LoC entry, not just index 1, and record each `locType`
  string verbatim. Question to settle: do snare/daze effects appear in
  `GetActiveLossOfControlData` with their own locType (e.g. "SNARE") even
  though the LoC frame gives them DISPLAY_TYPE_NONE? `locType` is an open
  cstring in the docs - the value set is undocumented; measure it.
- `GetUnitSpeed("player")` triple while slowed - expected SECRET in combat
  (`SecretWhenUnitStatsRestricted`); confirm, and also check OOC-while-dazed
  (open-world daze may occur outside combat restrictions).
- If both fail: fallback ladder is (a) OUTGOING slows via own-cast tracking
  (DotTracker pattern - covers "is my slow on the kite target"), (b) INCOMING
  slows via the enrichment pipeline (DB2 aura type 33 MOD_DECREASE_SPEED /
  mechanic 11) as an OOC-cached spell list, degrading like all combat-applied
  auras. No engine SNARE aura-filter flag exists - confirmed absent at 68887.

### Batch 2 - `/jac inspect selfcast` (NEW) - C1, then C3, C4

Claim: `UnitCastingInfo("player")` / `UnitChannelInfo("player")` are entirely
plain in combat (`SecretWhenUnitSpellCastRestricted` fires only for non-player
units). Armed on `UNIT_SPELLCAST_START`/`CHANNEL_START` for player: dump every
return with triples, notably `startTimeMs`, `endTimeMs`, `spellID`,
`notInterruptible`, `castID`.

Also in the same probe:
- `UnitChannelDuration("player")` vs `UnitCastingDuration("player")` - the docs
  mark casting `SecretReturns=true` but channel unannotated; settle the asymmetry.
- `C_Spell.IsCurrentSpell(id)` - claim: plain, covers queued casts.
- On an Evoker (S7): `UnitEmpoweredStagePercentages("player")` - claim: plain
  number table; `numEmpowerStages` / `isEmpowered` NeverSecret on any unit.

Unlocks: exact own-cast progress (queue timing, next-suggestion prefetch
without the AC event race), empower-stage gating.

### Batch 3 - `/jac inspect auraids` (NEW) - C1, C3, C4, C5

Claim: `C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter, max, sortRule, dir)`
returns a plain, iterable, countable table in combat - while `GetUnitAuras`
has ConditionalSecretContents (Blizzard's own comment: iteration indices go
secret). Probe on "player" and "target" with HELPFUL / HARMFUL / CROWD_CONTROL
filters: report `issecretvalue(#t)`, iterate with pcall, and cross-check count
against known aura state.

Also: `C_UnitAuras.GetAuraDuration` on a returned instanceID (already trusted
via DotTracker - re-confirm at 68887), and the per-aura classification pair
`IsAuraFilteredOutByInstanceID(unit, id, "CROWD_CONTROL")` +
`C_Spell.IsSpellCrowdControl(spellId)`.

Unlocks: plain aura *counts* (buff-count gates SimC uses), engine-classified
enemy-CC detection (don't suggest CC on an already-CC'd target).

### Batch 4 - `/jac inspect cdfields` (NEW or fold into `validate`) - C1, C3

NeverSecret fields inside otherwise-secret cooldown structs:
- `C_Spell.GetSpellCharges(id)`: `maxCharges`, `isActive` - claim NeverSecret.
  `isActive == false` ⇒ at max charges (capped-charge gate).
- `C_Spell.GetSpellCooldown(id)`: `isEnabled`, `isOnGCD` - probe `isOnGCD`
  only inside a `SPELL_UPDATE_COOLDOWN` handler (documented trust caveat).
- `C_Spell.GetSpellCooldownDuration(id, ignoreGCD)` both flag values -
  re-confirm the scratch-Cooldown probe distinguishes real-CD from GCD-locked.
- `C_SpellActivationOverlay.IsSpellOverlayed(id)` - claim: plain proc boolean.
  Probe on a proc-heavy spec during S5 session.
- `C_Spell.GetSpellCastCount(id)` (SecretWhenCooldownsRestricted - expect
  secret in C3; confirm).

Unlocks: charge-cap overcap warning, proc-driven priority boosts without aura
scans, cleaner GCD handling.

### Batch 5 - `/jac inspect secrecymap` (NEW) - C0 once per spec

Dump `C_Secrets.GetSpellCooldownSecrecy / GetSpellAuraSecrecy /
GetSpellCastSecrecy` for every spellbook spell and
`GetPowerTypeSecrecy` for every power type the class has. The predicate docs
say individual spells/power types may be flagged NeverSecret, overriding
restrictions. Any spell reporting `SecrecyLevel.NeverSecret` gets the cheap
plain-arithmetic path forever.

Output: table to SavedVariables; diff across specs. Zero combat needed.

Unlocks: per-spell fast paths; also tells us which probes above are pointless
for which spells.

### Batch 6 - `/jac inspect frames` (NEW) - C1 + S3/S4/S5, then C3

The laundered frame-state booleans. Sample 1/s (maintlog pattern), each row =
triples for:

- `LowHealthFrame:IsShown()` - player ≤35% HP claim. Gate check: CVar
  `doNotFlashLowHealthWarning` off. Note edge-latch behavior (fade lag).
- `PlayerFrame...HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss:IsShown()`
  - "damaged in last ~0.25s AND zero absorb". With S3 active, damage should
  NOT show it (absorb inference).
- `...ManaBar.FullPowerFrame.PulseFrame.PulseAnim:IsPlaying()` +
  `FullPowerFrame:GetAlpha()` + `.active` - resource capped (S5). Only armed
  for power types with `fullPowerAnim` (energy/fury...).
- `...ManaBar.FeedbackFrame.GainGlowTexture:IsShown()` /
  `.LossGlowTexture:IsShown()` / `.updatingGain` / `.updatingLoss` - >10%
  power delta edges. CVars `showBuilderFeedback`/`showSpenderFeedback`.
- `PlayerFrame...HealthBar.HealAbsorbBar:IsShown()` - heal-absorb presence.
- Party (needs a group): `PartyFrame.MemberFrameN.Portrait:GetVertexColor()`
  == (1,0,0) ⇒ member ≤20% HP; CompactUnitFrame `TotalAbsorbLeftShadow:IsShown()`
  per raid frame ⇒ member has an absorb.
- Target portrait ≤20% is PvP-player-only - skip unless C5.

MANDATORY follow-up before any feature ships: re-run the whole batch with the
user's unit-frame replacement addon enabled - the frozen-hidden-frame
precedent says these may freeze when Blizzard frames are hidden.

Unlocks: defensive-suggestion gates (≤35% self, ≤20% party member), absorb
awareness, overcap warning, spender-fired edge detection.

### Batch 7 - `/jac inspect cvitems` (NEW) - C1 + S6, then C3

Cooldown Manager viewer internals (globals `EssentialCooldownViewer`,
`UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`;
iterate `itemFramePool:EnumerateActive()`):

- `item.CooldownFlash:IsShown()` - on a *real* (non-GCD) cooldown, laundered
  at CooldownViewer.lua:1052. Cross-check against the scratch-Cooldown probe -
  if this holds, it's a free replacement for per-spell scratch probes on
  tracked spells.
- `item.isActive` - tracked buff/DoT currently up (plain literal assignment).
- `item.PandemicIcon ~= nil` / `:IsShown()` - engine-computed pandemic window
  (target debuffs only, uses GetRefreshExtendedDuration internally). Compare
  its timing against RedundancyFilter's cached-OOC pandemic math during S6.
- `C_CooldownViewer.GetCooldownViewerCategorySet/GetCooldownViewerCooldownInfo`
  - plain taxonomy claim (spellID, hasAura, selfAura, charges, linkedSpellIDs).

Gate: user must have Cooldown Manager enabled in Edit Mode; probe must report
viewer shown-ness and degrade gracefully. Same frozen-frame caveat as Batch 6.

Unlocks: pandemic refresh gating from engine truth (supersedes the OOC-cache
degradation for combat-applied DoTs), per-tracked-spell readiness without
scratch widgets, aura-linkage data (GetCooldownAuraBySpellID cross-check).

### Batch 8 - `/jac inspect kick` (extend existing castdiag) - C1 + S8, C3

- `UNIT_SPELLCAST_INTERRUPTIBLE` / `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` event
  identity as a state machine on target/nameplates - the only plain
  interruptibility signal (shield icon + `notInterruptible` are closed:
  secretwrap'd barType, SetShown'd BorderShield - do NOT probe those, already
  refuted by source).
- `castBarID` NeverSecret correlation key across all UNIT_SPELLCAST_* events.
- `C_Spell.IsSpellImportant(spellID)` on the target's cast (plain claim) -
  "lethal if not interrupted" for interrupt priority.
- Threat pair on a boss (C4): `UnitThreatLeadSituation("player","boss1")`
  (State predicate - permits boss) vs `UnitDetailedThreatSituation` (Values
  predicate - expects secret on boss). Confirms the tank-gap signal.

Unlocks: layered interrupt priority (important > interruptible > skip),
tank-swap awareness.

### Batch 9 - `/jac inspect dr` (NEW) - C5 (and C1 to confirm unsupported)

`C_SpellDiminish.IsSystemSupported()`, category enumeration, and an armed
capture of `UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED` (payload:
category/startTime/duration/isImmune - event marked SecretPayloads; measure
what actually reads plain, expect startTime/duration secret and the
category/isImmune shape TBD).

Unlocks (PvP feature, low priority): DR-aware CC suggestions, immune veto.

### Batch 10 - display-sink spikes (no secrecy question, behavior check) - C0/C1

Not signal probes; verify behavior before adopting in display code:
- `C_DurationUtil.CreateDurationTextBinding()` - bind a FontString to
  `GetSpellCooldownDuration`; confirm countdown text renders and
  `HasSecretValues()` is branchable. Candidate replacement for any OnUpdate
  cooldown text.
- `Texture:SetSpriteSheetCell(secretIndex, ...)` - N-way branchless selector;
  feed a step-curve-evaluated secret and confirm cell selection renders.
- `Cooldown:SetCountdownFormatter` + `C_StringUtil.CreateSecondsFormatter` -
  engine countdown text on the suggestion icon swipe.
- `SetCooldownFromDurationObject(dur, clearIfZero=true)` - confirm auto-clear
  on ready (drop any manual clear logic).
- `DurationObject:IsActive(modifier)` / `IsZero()` / `HasSecretValues()` -
  docs claim plain/ReturnsNeverSecret; if `IsActive()` truly returns a plain
  boolean this SUPERSEDES the scratch-Cooldown IsShown() probe entirely.
  **IMPLEMENTED: folded into `/jac inspect durprobe` (method sweep section) -
  run in combat with a cooldown down; compare against the scratch column.**
- `UnitStagger("player")` re-check on Brewmaster - docs say ConditionalSecret,
  our 2026-07-20 sweep measured plain. Trust the new measurement.

## Execution order

1. **Session 1 (solo, dummy + world mobs):** Batch 5 (OOC dump), Batch 10's
   `DurationObject:IsActive` check, Batches 2/3/4, Batch 6 states S4/S5,
   Batch 1 states S1/S2 on world mobs.
2. **Session 2 (dungeon):** re-run 1-4 + 6 + 7 in C2/C3 - this is where
   `SecretOnRestrictedMaps` vs `SecretWhenInCombat` separates.
3. **Session 3 (group/LFR):** Batch 6 party rows, Batch 8 threat pair on boss,
   Batch 7 pandemic timing on a boss target.
4. **Session 4 (BG):** Batch 9, nameplate LoC on enemy players, target
   portrait check.
5. **Regression:** re-run Batch 6/7 with unit-frame addon enabled; add
   surviving reads to `/jac inspect validate` so drift is caught by the
   existing arm-diff harness.

## Decision table (what each validated signal unlocks)

| Signal (if validated) | Feature |
|---|---|
| LoC data plain for player | Lockout-aware queue; CC state display; suppress suggestions while stunned |
| `GetSpellLossOfControlCooldownInfo().isActive` | Per-spell school-lockout veto in queue ranking |
| Player cast info plain | Exact cast-progress timing; queue prefetch |
| `GetUnitAuraInstanceIDs` plain count | Buff-count SimC gates; enemy-CC-present veto |
| `DurationObject:IsActive()` plain | Replace scratch-Cooldown probe (simpler, sanctioned) |
| `LowHealthFrame` / party portrait | Defensive auto-suggestion tiers (35% self / 20% party) |
| `FullPowerFrame` pulse | Overcap warning / spender priority boost |
| CooldownViewer `PandemicIcon` | Engine-truth pandemic refresh for combat-applied DoTs |
| `IsSpellOverlayed` | Proc-driven priority boost |
| `isActive`/`maxCharges` NeverSecret | Charge-cap gates |
| Threat lead on boss | Tank-swap / aggro-loss context |
| `secrecymap` NeverSecret spells | Per-spell plain fast paths |
| Player-slowed signal (LoC locType or fallback ladder) | Shift-to-break-slow suggestion (Druid: a quick form shift removes movement-impairing effects) - needs a *branchable* "slowed now" boolean, so this feature's viability hangs entirely on the Batch 1 slows sub-probe |

## Known dead ends - do not probe (refuted at source level)

- Cast-bar shield / `barType` / `IsInterruptable()` - secretwrap'd by design.
- Arena frame LoC `IsShown()` - SetShown + Blizzard TODO to move secure.
- `GetUnitAuras` table iteration/length - secret indices (Blizzard's own comment).
- Nameplate health: no execute/low-health branch exists at 68887.
- Stagger/usability/range laundering - the APIs are already plain; call direct.
- CLEU - hard-blocked; unchanged.
