# Heal Mode — Implementation Plan

Status: PLANNED (no code yet). Test spec: Restoration Druid, solo follower dungeons.
Scope: 5-man party content (dungeon/raid; raid degrades gracefully — see limits).

Two deliverables:
1. **DPS mode for healer specs** — un-gate the existing pipeline (it is already healer-clean).
2. **Heal queue** — the defensive-cluster surface rebuilt for healers: ranked heal
   suggestions, per-party triage cues with hover-to-aim, and an emergency slot 0.

Cardinal rule (inherited from the pet-heal cue): **a ranked list can never hold a
secret**. Ordering keys off plain booleans/ints only; per-unit health urgency is
expressed exclusively as engine-side display (alpha/color curves), never as sort position.

---

## Signal foundation (what combat-time logic may read)

**Plain / branchable** (verified against API-doc secrecy annotations + shipped code):
- `partyHealthInfo` key-existence per unit + `unitCount` int from the Blizzard combat
  audio-alert manager — the ONLY branchable "ally is low" signal (party1-4, CVar-gated).
  Read keys only, never values; never write the CVar from addon code. PROBE-GATED.
- `UnitExists / UnitIsConnected / UnitIsDeadOrGhost / UnitGroupRolesAssigned` on party
  units (via the ReadableBool guard pattern — secrecy is per-context, not per-combat).
- Party `UNIT_HEALTH` edge events (payload = who changed, never read amounts).
- Plain aura counting: `#C_UnitAuras.GetUnitAuraInstanceIDs(unit, engineFilter)` —
  validated for CROWD_CONTROL/BIG_DEFENSIVE; `HARMFUL|RAID_PLAYER_DISPELLABLE` and
  `HELPFUL|PLAYER` are PROBE-GATED (engine silently ignores unknown tokens; the
  filterVerdict self-test must be ported to the instance-ID path first).
- Own casts (`UNIT_SPELLCAST_SUCCEEDED` player), local cooldown tracking, the
  scratch-Cooldown readiness probe, `C_Spell.IsSpellUsable` + `insufficientPower`.
- `CombatText.lowMana` (player, fixed ~20%) — the one branchable mana signal.
- Discrete resource reads (validated): Holy Power exact counts for Holy Paladin.
  Evoker Essence NOT validated — probe.

**Secret / impossible — do not attempt:** any health/mana number or comparison, sorted
"lowest first" triage, ally-in-range (`UnitInRange` + its event are secret), ally casts,
incoming-heal numbers, combat log (hard-blocked in 12.0), raid-member-low signals.
`UnitThreatSituation` on allies is conditionally secret — gate on its predicate.

**Display-only sinks for ally state:** `SetAlphaFromHealthCurve/Below(frame, "partyN",
...)` (unit-parameterized, shipped), StatusBar secret passthrough, color curves.

---

## Phase 0 — Probe session (gates everything; no UI work before this)

Extend `/jac inspect` with a party-probe suite; run in a follower dungeon on Resto:

| # | Probe | Gates | Status (2026-08-09, Resto, follower dungeon) |
|---|-------|-------|--------|
| 1 | partyHealthInfo key-existence plainness (`healprobe watch`) | emergency tier, AoE promotion, DPS dimming | **PASS** — per-unit keys flip plain true/false in combat, both directions; unitCount plain and consistent with keys (0..4 observed); works at alert volume 0 (volume gates TTS only) |
| 2 | `SetAlphaFromHealthCurve` on party/follower-NPC tokens | triage cue row | **PASS (wired)** — helper accepts all party tokens incl. NPCs; swatch visual confirmation informal |
| 3 | `RAID_PLAYER_DISPELLABLE` filterVerdict on party units (port guard to instance-ID path) | dispel claimant | pending — needs a debuffing pack |
| 4 | `UNIT_SPELLCAST_SENT` target-name secrecy (ConditionalSecret in docs) | HoT-to-unit attribution | **PASS** — target name plain in combat for all members incl. NPCs. Bonus: player-sourced aura spellId reads PLAIN on party units in combat; `isFromPlayerOrPlayerPet` is a plain branchable bool; `IsAuraFilteredOutByInstanceID(HELPFUL|PLAYER)` agrees (inverted: filteredOut=false means mine) |
| 5 | AC `GetNextCastSpell` content on an enabled healer spec | pos-1 expectations | **PASS** — Resto gets Wrath + a 12-spell pure-damage pool (matches SimC catweave) + Mark of the Wild |
| 6 | `UnitThreatSituation("partyN")` secrecy | aggro badge (optional) | pending — nil OOC; needs in-combat census |
| 7 | Evoker Essence point-widget read | Essence gating (Phase 5) | pending — needs an Evoker login |
| 8 | In-game cooldown checks: Flourish (no CD resolves from DB2 — bug or design?), Tranquility channel length | Phase 5 data | pending |

Field notes from the session: party token↔identity SHUFFLES on mid-dungeon
composition changes — bind HoTs by cast-target name + firing unit, refresh cue
labels on GROUP_ROSTER_UPDATE; the player's LFG-assigned role can be stale after
a spec switch (see tank identification, Phase 4); Symbiotic Blooms-class talent
procs land player HoTs on non-targeted members (bind-on-exactly-one handles it);
SENT target-name secrecy is exactly target-friendliness — plain for allies/self,
SECRET for hostiles — so `issecretvalue(targetName)` doubles as a safe
ally-vs-enemy cast discriminator; Germination's second Rejuv lands as its own
plain fromMe instance (155777), so double-Rejuv upkeep is directly trackable;
other-sourced party aura spellIds are plain OOC but SECRET in combat, while
player-sourced spellIds stay plain in both states — with PER-SPELL EXEMPTIONS
observed live (Temporal Displacement 80354 read plain in combat from another
source; the sated-debuff class is engine-exempted, usable later for lust-window
cues). Alert-system gating: the master enable and the threshold CVar are
SEPARATE switches (CVar observed non-zero while the feature was off, during
which no keys ever appear — correct fail-open); gate the emergency tier on
IsEnabled() AND CVar > 0, and resolve the CVar's step index to a display percent
via Blizzard's own mapping util, never arithmetic.

Every gated feature fails open (feature dark, queue degrades to cadence/display-only).

## Phase 1 — DPS mode, all 7 specs (+ filler style)

Ship first; it works today. Healers are off via one mechanism: firstRun writes
`specProfiles[i]="DISABLED"`.

1. **Per-spec mode tri-state** `Disabled / DPS / Heal` replacing the bare sentinel,
   surfaced on the Profiles per-spec dropdown; routes through the existing
   Enter/ExitDisabledMode warm-start. Healer firstRun default stays Disabled.
2. **Tail heal filter**: when spec role is HEALER, drop `IsHealingSpell` entries from
   positions 2+ (pos 1 = AC's pick, never filtered). Fail open if the filter would
   empty the tail.
3. **Category top-up** (fail-open `IsOffensiveSpell` leaks — audit-verified): see
   "Data work" below.
4. **Filler style** per spec — IMPLEMENTED 2026-08-09 as a two-state toggle
   (`profile.casterFiller[specKey]`, DPS Queue tab, healer specs only): off =
   auto (today's distance-based melee sink); on = caster (melee-tagged and
   form-shift suggestions suppressed from the tail via archetype range tags +
   FormCache, and a melee/form pos-1 pick takes the blacklist-lookahead
   replacement). The planned third "weave" state folded into auto — the
   distance sink already serves committed weavers. Caster residue for Resto
   Druid (Sunfire/Moonfire/Wrath/Starfire/Starsurge) is a legitimate list; for
   Mistweaver caster mode honestly means "thin filler" — no fabricated rotation.
   Note: the toggle is shown for all healer specs rather than hidden for
   always-caster ones (harmless no-op there; one less spec table to maintain).

SimC coverage: DRUID_4 (catweave) and MONK_2 (fistweave) exist; the other five healer
specs fall back to "ac" ordering silently — ship as-is.

## Phase 2 — Heal queue engine (spec-agnostic)

**Phase 2 opens with a capacity refactor** (lesson of the 2026-08 upvalue
incident): GetCurrentSpellQueue is at ~56/60 upvalues with an 18-argument
helper — its budget is spent in both dimensions. Executed incrementally, each
step leaving the file loadable and verified (luasyntax + upvalue estimate +
in-game reload). Baseline commit: ad34a91.

Stage map (line anchors at ad34a91): gate/throttle+setup 956-1028 stays in the
coordinator; A pos-1 assembly 1030-1094; B gap-closer injection 1096-1147;
C spellbook procs 1149-1151 (already a function); D rotation-source resolution
1153-1271; E context inference 1272-1333; F tail ordering+assembly 1336-1380;
G burst cue 1382-~1480; H final copy/dedup ~1483-1513.

Mechanics: ONE pooled per-build context table `SpellQueue._b` (wiped each
build) carrying profile/blacklist/inCombat/now/maxIcons/hideItems/spellCount/
primarySpellID/ctx*/ordering fields. Stages become `SpellQueue._StageX(b)`
module-table functions — each captures only its own module-locals from a fresh
60-slot budget, and the coordinator's references collapse toward just
SpellQueue + b.

**STATUS: COMPLETE 2026-08-09.** All eight stages extracted verbatim
(_StagePrimary/_StageGapCloser/AddSpellbookProcs(b)/_StageResolveSource/
_StageContext/_StageTail/_StageBurstCue/_StageFinalize + _ClearSituationMemory);
the coordinator is a ~50-line pipeline. Measured upvalues: coordinator ~21/60
(was >60 at the crisis), every stage 6-13/60. Lazy engine-ref resolution moved
into _StageGapCloser (first per-build user). Stages A-D verified in-game;
E-H pending one reload+pull. Heal-queue feature work may now begin.

The defensive-cluster builder gains a heal surface in Heal mode. Self-defensives
remain (self-low signals are the richest we have); ally-low promotes heals; both plain.

- New per-spec list `groupHealSpells` in `defensives.classSpells[specKey]`
  (shape/fallback/options identical to petHealSpells), seeded from
  `CLASS_GROUPHEAL_DEFAULTS`. **LANDED 2026-08-09 (inert until consumed):**
  `SpellDB.CLASS_GROUPHEAL_DEFAULTS` / `HEAL_EMERGENCY_LADDER` /
  `HEAL_EXTERNAL_LADDER` for all 7 healer specs + `SpellDB.SpecHasGroupHeals`
  (`HEAL_EXTERNAL_LADDER` deleted 2026-08-10 with the targeted-heal descope;
  the other two trimmed to multi-target-only per the DECIDED block),
  and the signal wrapper `BlizzardAPI.GetPartyLowCount` / `IsUnitLow` /
  `IsPartyLowAvailable` (StateHelpers, read-keys-only discipline documented at
  the call site; `healprobe` census cross-checks wrapper vs raw reads).
  **ENGINE v0 LANDED 2026-08-09:** SPELL_LIST_CONFIG row (healer specs only —
  ResolveDefaults returns nil elsewhere), the heal pass in
  GetDefensiveSpellQueue (in-combat AND lowCount>0, above the self-defensive
  pass), `profile.healing.enabled` (default off), the Defensive Queue toggle +
  live alert-status line, and party1-4 UNIT_HEALTH dirty triggers (payload
  never read, gated on healing.enabled and isDisabledMode). NOT yet done: tier
  permutation by unitCount (needs per-heal target-type metadata), sticky
  smoothing, who-chips, emergency slot 0, cue row.
- **Two hard rules from the 2026-08-09 dungeon trace** (a full follower-dungeon
  run at threshold index 2): (1) the low-keys PERSIST OUT OF COMBAT — the trace
  ends `unitCount -> 3  combat=false` while the group walks around at partial
  health, so every heal-tier and emergency trigger MUST be ANDed with inCombat
  or it fires permanently while nothing is happening; (2) transitions flap hard
  near the threshold (units flipping true/false within the same second), which
  is why the AoE tier needs the sticky hold — an unsmoothed `unitCount >= N`
  would thrash the queue mid-triage.
- **One queue, tier-permuted** by plain state (never two parallel queues):
  - 0 low → maintenance order (upkeep, cadence HoTs, filler bright)
  - 1 low → ST tier floats + who-chip; AoE sinks
  - 2+ low (sticky ~8s, reusing the sticky-context pattern) → AoE tier floats
    (target-type `smart/ground/raid` from Phase 5 data)
- **Burst classification is free**: the existing hold-worthy rule (base CD >= 60s,
  OOC-precached) parks raid CDs desaturated + WAIT until a trigger fires.
- Party `UNIT_HEALTH` dirty-triggers (respect the isDisabledMode guard — this exact
  re-show bug is in the changelog), 10Hz rebuild throttle unchanged.
- **Mana behavior**: `insufficientPower` sink (exists) degrades the queue toward
  affordable casts; `CombatText.lowMana` flips an efficiency state — cheap-cost tier
  floats (mana costs pre-cached OOC like base cooldowns), mana actives (Innervate-class)
  cue, DPS filler dims. No efficiency modeling beyond these two signals — they are all
  that exists.
- Dual-purpose target-dependent spells (Living Flame, Adaptive Swarm) are gated on
  current-target friendliness, not spell identity.
- **Ally-low signal setup UX** (so users need no manual accessibility spelunking):
  two tiers. Tier 1 (unconditional): the heal options page shows live signal
  status (enabled/threshold/volume via plain reads) with a button opening
  Blizzard's Settings at the right category, plus an "inactive" notice mirroring
  how defensives surface state. Tier 2 (probe-gated): a managed toggle on the
  nameplate-overlay CVar precedent — save the user's enable/threshold/volume,
  write our own (volume 0 default), restore on disable/logout; never touch
  settings the user already configured; writes OOC only. Gate: the
  `healprobe cvar` taint experiment — an addon-originated threshold write
  followed by a clean watch run + `/jac inspect errors` proves the manager's
  cached compare survives tainted CVar writes. If it fails, Tier 1 only.
  STATUS 2026-08-09: **FULL PASS — Tier 2 managed toggle is shippable.** After a
  tainted SetCVar the keys kept flipping plain through multiple fights, and an
  armed error-capture pull recorded zero taint blocks and zero alert-manager
  errors (the single captured entry was a pre-existing fault inside an unrelated
  third-party addon's bundled database library). The July taint theory is
  falsified: C-side CVar storage launders addon writes. Threshold mapping
  corroborated as percent = 110-10*V (index 5 ↔ 60%; index 2 ≈ 90% produced
  rapid boundary flapping — the field case for the emergency tier's sticky-hold
  smoothing; managed default should sit mid-band, index 6-7 ≈ 50/40%).

## Product scoping + healer display model (settled 2026-08-09, owner-driven)

> **SUPERSEDED 2026-08-10** — the display-model priority list below (beacons /
> cursor companion / sound / cue row) is retired: targeted heal advice left
> the scope entirely. See the DECIDED block under the ecosystem survey for
> the final shape. Kept for the reasoning record.

**The product is a DPS-first copilot with a heal interrupt**, not a healing
rotation bot: the healer catweaves off the DPS queue; when party members drop,
the addon interrupts — heal suggestions replace the filler, and the player is
routed to the right target fast. (The shipped v0 already behaves this way:
heals appear only in combat while someone is low.) The always-watched heal
rotation is explicitly out of scope.

Display model (the mockup-session conclusion): the suggestion COMES TO THE
EYES — never a panel the eyes must visit. Priority order:
1. **On-frame beacons**: the hurt member's party frame grows the suggested
   heal's icon + its hotkey label + an urgency rim. Who/what/key at the point
   of action. KEY FACT: per-member low flags are PLAIN booleans, so beacons are
   ordinary alpha/animation code — zero secret machinery. Constraint: overlays
   anchor to frames OUT of combat only (target-frame taint lesson); frames are
   static in combat, so pre-anchored overlays only change alpha/content
   mid-fight; mid-combat roster change hides beacons until regen. Structural
   frame detection with a stand-down fallback when frames are replaced.
2. **Cursor companion**: the current suggestion (+ emergency tint) rides the
   cursor — covers travel between frames and replaced-frame setups. Own
   unprotected frame following GetCursorPosition; alpha-driven content.
   **LANDED 2026-08-09** (UI/UICursorCompanion.lua) on the shared payload
   `DefensiveEngine.GetHealSuggestion` (0.1s memo; rotational pick from the
   heal list, emergency/external ladders on `unitCount >= emergencyCount` (3)
   or tank-low with the measured 8s sticky hold; exactly-one-other-TANK rule;
   hotkey via ActionBarScanner). Toggle: Defensive Queue tab, healing.cursorCompanion.
3. **Emergency sound** (LSM, like the interrupt alert): the OH SHIT moment
   needs zero eyes.
4. **Cue row** (secure unit buttons, click-to-target/hover-to-aim) DEMOTED to
   an optional fallback for players without usable frames/mouseover habits.
   Native party-target keybinds (read via GetBindingKey, shown on beacons or
   chips) answer "fast targeting" for keyboard players.

Fast-targeting answer (addons cannot target programmatically): click a cue box
(secure *type1=target), hover beacon/frame + mouseover bind, or the native
party-targeting keys surfaced next to the suggestion.

## Midnight ecosystem survey (2026-08-09) — field evidence from updated addons

Surveyed: the four Midnight-updated (Interface 120000+) addons in the local
AddOns directory — a click-heal addon (updated two days before this survey), a
unit-frame addon, an avoidable-damage audio alerter, a group-frame sorter —
plus the public status/changelogs of the major raid-frame, heal, dispel, and
click-casting addons.

### Convergent verdicts

1. **Triage is dead ecosystem-wide.** No surviving addon ranks allies by
   health. Both "emergency / lowest-health highlight" features found in
   surveyed heal addons are inert in combat (gated on reading a now-secret
   value). Deficit sorting, overheal text, and AoE-heal advisory modules were
   removed, not re-engineered. **No addon anywhere references the
   party-health audio-alert manager keys** — the plain per-unit ally-low
   signal this plan is built on is uncontested territory. Blizzard's blue
   post names the audio alert system ("health, buffs, and combat events") as
   a sanctioned signal channel, which is the channel we consume.
2. **Directing a heal survived untouched: the human is the comparator.** All
   surviving click-heal flow is secure unit buttons + hover/mouseover
   routing; the spell attribute never knows the target, the *button* does.
   Unit attributes are written out of combat and frozen for the fight (writes
   deferred to a regen-drained queue — same discipline as Phase 3's static
   attributes). One friction: 12.0 reworked default frame clicks, so
   click-casting setups must explicitly bind target/menu.
3. **Rendering is pure engine passthrough.** Secret health flows into
   StatusBar SetValue; coloring via UnitHealthPercent + curve objects;
   incoming heals via the heal-prediction calculator object. Addons that
   moved rendering/detection into the engine survived; addons that needed to
   *read* died (the damage alerter shipped "with much of its functionality
   gone" — its detection is now engine-side private-aura sound registration).

### Techniques adopted into this plan

- **Ally range, per spell:** `C_Spell.IsSpellInRange` stays PLAIN for allies
  in combat (both local survivors use it as their real range source; generic
  `UnitInRange` is secret). New invalidation events `UNIT_IN_RANGE_UPDATE` /
  `UNIT_DISTANCE_CHECK_UPDATE` fire per unit. → Beacons/cue row can honestly
  dim an unreachable heal. Verify in game once, then rely on it.
- **Dispellable triage without reading anything:** the `RAID_PLAYER_DISPELLABLE`
  / `HARMFUL|RAID` filters are server-side predicates — "this debuff is
  dispellable *by you*". Combined with our validated plain `#GetUnitAuras`
  count (non-boolean secret truthiness is documented branchable on the wiki),
  that yields "party N has a debuff I can dispel" as a branchable per-ally
  fact, plus the cache-plain-boolean-per-spellID pattern seen in the field.
  This CLOSES the Phase 0 dispel-filter probe without a debuffing pack.
- **Heal prediction:** `CreateUnitHealPredictionCalculator` +
  `UnitGetDetailedHealPrediction`, with **`calc:HasSecretValues()` as a
  branchable boolean** gating any arithmetic. Display-only otherwise.
- **Non-secret healer-aura whitelist:** a Blizzard data hotfix makes ~100
  healer spell IDs return readable AuraData in combat (list liftable from a
  unit-frame addon's source; Blizzard accepts whitelist requests). My-HoT
  tracking on party units may be plainly readable for whitelisted IDs —
  cross-checks our own "player-sourced aura spellIds plain" finding.
- **Gradient without branches:** a 3-point ColorCurve through
  `UnitHealthPercent` replaces threshold if/else ladders wholesale.
- **Misc portable idioms:** `issecretvalue(x) or x ~= cached` as universal
  change-detection (secret ⇒ assume changed); identical-signature shim pairs
  (classic vs Midnight implementations selected once by feature-detect);
  `Frame:HasSecretAspect(Enum.SecretAspect.Alpha)` to detect
  secret-contaminated alpha; `UnitHealthMissing` / `AbbreviateNumbers` for
  engine-side deficit/formatting; `C_ClassColor.GetClassColor` accepts a
  secret class token; `UnitIsDeadOrGhost` stays plain (liveness boolean).

### Cautions surfaced

- **Aura instanceIDs re-randomize** on entering an encounter / M+ / PvP match
  (12.0.5). Any tracker holding an instanceID across that boundary silently
  wedges. Audit queued for RedundancyFilter / MaintenanceTracker / DotTracker.
- **`SetStatusBarColor` secret acceptance is disputed in the field** — one
  surveyed addon routes around it (tints the fill texture instead), another
  feeds it curve-derived RGB; the wiki lists it as a sink. Probe before
  relying on it; texture `SetVertexColor` is the undisputed path.
- **Per-call-site guards leak.** The click-heal addon hand-guarded ~98 sites
  and missed one (unguarded arithmetic on a secret max-health in a sort
  branch → in-combat error in a niche config). Centralized fail-open helpers
  (our BlizzardAPI layer) are the pattern its mistakes argue for. Its master
  gate also disables ~40 features even OUT of combat where values are
  readable — gate on combat, not on client version.
- **Aura tracking by spell NAME died in 12.0.1** — spellID-only (we comply).
- A third-party rewrite claims a widget-readback (`SetValue`→`GetValue`)
  works for health text; this contradicts our closed continuous-resource
  sweep and the laundering rules — treat as stale/patched. Its
  `CheckInteractDistance` non-secret range fallback claim is plausible but
  redundant given per-spell range above.

### Implication for the open display fork

**DECIDED (owner, 2026-08-10): targeted heal advice is OUT OF SCOPE
entirely.** Directing a heal at a person is group/raid-frame addon territory —
the survey shows those addons own that input point and do it well. JustAC's
heal surface is exactly three things:
1. Personal self-heals in the defensive queue, as always.
2. **Multi-target group heals** injected into the defensive queue while the
   group-low signal is live. The criterion is "heals several allies per
   cast", NOT targeting: a targeted AoE (Wild Growth, Chain Heal) cast with
   no friendly target defaults to the player and the splash still covers the
   group. Strictly single-target heals never appear — the queue cannot say
   *who*, so it never suggests anything that needs a *who*.
3. **The OH SHIT claimant**: when several allies are low at once
   (`healing.emergencyCount`, default 3, with the measured 8s sticky hold),
   the first READY spell of `HEAL_EMERGENCY_LADDER` claims the Sustain slot
   (defensive slot 0) — arbitrated in `RenderMaintenanceSlot` between CC
   escape (above, plain) and pet heal (below, secret alpha). LANDED
   2026-08-10 (`DefensiveEngine.GetEmergencyHealID`).

Consequences: the cursor companion is REMOVED (landed 2026-08-09, deleted
2026-08-10 — it competed with the frames instead of joining them); on-frame
beacons and the secure cue row are CANCELLED; `HEAL_EXTERNAL_LADDER`
(tank-save externals) deleted — externals are targeted. The ladder and the
injected list are kept DISJOINT by curation so a spell never renders twice.

## Phase 3 — Triage cue row (hover-to-aim) — CANCELLED (out of scope, see above)

Up to four party cue icons + pet, the pet-heal pattern generalized:
- Created as **SecureUnitButtonTemplate** buttons with STATIC unit attributes
  (icon N = partyN forever; attributes set OOC only, deferred on in-combat roster
  change). Hovering a cue makes `mouseover` resolve to that ally — the player's own
  `[@mouseover]` binds aim correctly. `*type1=target` click-to-target at creation.
- Always Shown; visibility = engine alpha via `SetAlphaFromHealthCurve(icon,"partyN",
  bands, predicted)` — multi-band urgency (faint/solid/glow), incoming-heal aware.
- Icon texture = first usable groupHealSpells entry; plain role label; dead ally swaps
  to combat-rez at full alpha (druid only — see Phase 5 brez notes).
- Mouse interactivity is **opt-in** (an alpha-0 mouse-enabled frame still eats the
  mouse; we cannot toggle EnableMouse from health — that would be a branch).
- The addon never casts. No dynamic secure attributes anywhere.

## Phase 4 — Slot 0 claimant stack (the emergency slot) — LANDED 2026-08-10 (see decided scope above)

Claimant priority (all plain → ordinary ifs; CC-break stays on top deliberately —
if the crisis hits while stunned, the correct button IS the CC-break):

1. **CC-break** (existing claimant, unchanged)
2. **Emergency**: `unitCount >= N` (default 3) → group-crisis ladder, first-ready-wins;
   tank's low-key present (+ plain role) → external ladder with → TANK chip;
   distinct red pulse + optional `emergencyAlertSound` (LSM, sibling of the interrupt
   alert). The WAIT-parked raid CD un-parks here.
3. **Dispel cue** (probe-gated): any party unit with a player-dispellable debuff
4. **HoT upkeep**: MaintenanceTracker entries extended to (unit, HoT) pairs —
   cast→instance bridge per party unit, bind-on-exactly-one, fail-to-UNKNOWN.
   Scope: single-instance maintained buffs only (Lifebloom, Earth Shield, Beacon);
   blanket HoTs are not promised.

Tank identification (field-verified caveat): `UnitGroupRolesAssigned` is the
LFG-assigned role and can be stale — switching spec after entering a follower
dungeon leaves the player's assigned role unchanged. The player's own role always
comes from `GetSpecializationRole`. For allies, resolve the tank as: exactly one
OTHER member assigned TANK → use them; else the acting tank via ally threat
situation (probe-gated); a set focus overrides both as the designated upkeep target.

## Phase 5 — Per-spec data (audit-grounded, build 12.0.7.68887)

New tables: `CLASS_GROUPHEAL_DEFAULTS`, `HEAL_EMERGENCY_LADDER` (both later trimmed
to multi-target-only; `HEAL_EXTERNAL_LADDER` deleted with the targeted-heal descope),
heal metadata (target type / cast class / HoT duration), friendly-dispel table, upkeep
entries. All user-overridable via the existing priority-list UI. Alpha-build caveat:
audited at 12.0.7.68887, re-audited at 12.0.7.68974 (incl. the full trait-condition
spec-gating chain — see Data work #5); re-verify flagged IDs on the launch build.

### DRUID_4 — Restoration Druid
- Group defaults: Rejuvenation 774, Lifebloom 33763, Efflorescence 145205,
  Swiftmend 18562, Wild Growth 48438, Regrowth 8936, Cenarion Ward 102351
- Emergency: Tranquility 740 → Flourish 197721 → Wild Growth → Swiftmend
- External: Ironbark 102342 (off-GCD — can be offered alongside a GCD heal)
- Dispel: Nature's Cure 88423 (Magic/Curse/Poison, 8s charge CD hidden behind
  ChargeCategory); Upkeep: Lifebloom → tank
- Notes: Flourish CD unresolvable from DB2 (probe #8); Adaptive Swarm 391888 has a
  real 25s CD missing from Data/SpellCooldowns.lua (regen); Germination 155777 and
  Spring Blossoms 207385 are not pressable — never queue-suggest; brez = Rebirth.

### PALADIN_1 — Holy Paladin
- Group defaults: Holy Shock 20473, Word of Glory 85673, Light of Dawn 85222,
  Beacon of Virtue 200025, Divine Toll 375576, Holy Prism 114165, Holy Light 82326,
  Flash of Light 19750
- Emergency: Aura Mastery 31821 → Avenging Crusader 216331 → Divine Toll → Lay on Hands 633
- External: Blessing of Protection 1022 → Blessing of Sacrifice 6940
- Dispel: Cleanse 4987 (Magic/Disease/Poison); Upkeep: Beacon of Light 53563
  (+ Beacon of Faith 156910 when talented; Beacon of Virtue overrides)
- Notes: **Holy Power spenders (WoG/LoD) gate on the validated exact Holy Power read
  (suggest at 3+)** — the only healer with true resource gating. Light's Hammer /
  Bestow Faith / Barrier of Faith have no live learn path in this build — excluded
  pending re-check.

### PRIEST_1 — Discipline Priest (the special case)
- Group defaults (= Atonement applicators first): Plea 200829, Power Word: Shield 17,
  Penance 47540, Renew 139, Prayer of Healing 596, Power Word: Radiance 194509,
  Flash Heal 2061, Heal 2060
- Emergency: Power Word: Barrier 62618 → Ultimate Penitence 421453 → Rapture 47536
- External: Pain Suppression 33206 → Void Shift 108968 (Guardian Spirit is
  Holy-exclusive — never list it for Disc)
- Dispel: Purify 527 (Magic/Disease); Upkeep: none single-instance (Atonement is
  multi-target)
- **Design inversion**: damage IS healing under Atonement. Disc's heal queue = keep
  applicators rolling; the DPS filler is NOT dimmed under heal pressure (dimming
  inverts for this spec); PW:S availability is per-target (Weakened Soul 7.5s lock,
  not a spell CD). No Priest battle rez exists. Penance is a SpecializationSpells
  baseline grant (not a talent). 68974 flag: Rapture 47536 is absent from EVERY
  grant table (trait/skill-line/spec/learn) — keep listed but re-verify at launch.

### PRIEST_2 — Holy Priest
- Group defaults: Prayer of Mending 33076, Renew 139, Circle of Healing 204883,
  Holy Word: Sanctify 34861, Flash Heal 2061, Prayer of Healing 596, Heal 2060
- Emergency: Divine Hymn 64843 → Halo 120517 → Holy Word: Sanctify 34861
  (Holy Word: Salvation 265202 dropped: its TraitDefinition attaches to ZERO nodes
  at 68974 — orphaned, unreachable by any spec; restore if the launch build wires it)
- External: Guardian Spirit 47788 (off-GCD) → Holy Word: Serenity 2050 → PW:S 17
- Dispel: Purify 527 (Magic/Disease); Upkeep: Renew cadence (soft)
- Notes: Holy Word flat CDs are ceilings — Serendipity shortens them; local-CD
  fallback will read pessimistic (readiness probe stays authoritative). Divine Hymn
  and Guardian Spirit are confirmed Holy-only via real SpecSet gates (68974).
  Circle of Healing / Divine Star / Symbol of Hope are absent from every grant
  table incl. SpellLearnSpell at 68974 — keep listed but re-verify at launch.

### SHAMAN_3 — Restoration Shaman
- Group defaults: Riptide 61295, Unleash Life 73685, Healing Stream Totem 5394,
  Healing Wave 77472, Healing Surge 8004, Chain Heal 1064, Healing Rain 73920,
  Wellspring 197995
- Emergency: Healing Tide Totem 108280 → Ancestral Protection Totem 207399 →
  Spirit Link Totem 98008 → Ancestral Guidance 108281
- External: Ancestral Protection Totem (no true ST external)
- Dispel: Purify Spirit 77130 (Magic; +Curse via class talent 383016);
  Upkeep: Earth Shield 974 → tank
- Notes: totem placement classes differ (self-anchored: Healing Stream/Tide vs
  reticle: Spirit Link/APT/Healing Rain) — metadata must distinguish; Chain Heal is
  ally-targeted but weighs like smart at 2+ low; no in-combat rez.

### MONK_2 — Mistweaver
- Group defaults: Renewing Mist 119611, Soothing Mist 115175, Thunder Focus Tea 116680,
  Essence Font 231633, Enveloping Mist 124682, Vivify 116670, Life Cocoon 116849,
  Restoral 388615
- Emergency: Restoral → Invoke Yu'lon 322118 / Chi-Ji 325197 (choice node) → Essence Font
- External: Life Cocoon; Dispel: Detox 115450 (Magic/Disease/Poison — spec variant;
  218164 is the non-healer variant, keep distinct); Upkeep: Renewing Mist (soft — it
  self-propagates; cadence, not single-instance)
- Notes: fistweave-dominant SimC list already carries heal-CD cast IDs; caster filler
  style = honestly thin; brez = Reawaken 212051 (currently uncategorized — see gaps).

### EVOKER_2 — Preservation
- Group defaults: Echo 364343, Reversion 366155, Emerald Blossom 355913,
  Verdant Embrace 360995, Living Flame 361469, Temporal Anomaly 373861,
  Spiritbloom 367226→382731, Dream Breath 382614
- Emergency: Rewind 363534 → Dream Breath → Zephyr 374227 → Spiritbloom
- External: Time Dilation 357170; Dispel: Naturalize 360823 (Magic/Poison);
  Upkeep: none (Reversion is charge-based, not single-instance)
- Notes: **empower casts** need a cast-class of their own (hold-to-release). 68974
  ID check: of 7 spells named Dream Breath only base 355936 is in the grant chain,
  Pres-gated (SpecSet 172 → spec 1468, verified directly); the 4-stage upgrade IDs
  382614/382731 have no grant rows anywhere — the stage-upgrade swap happens outside
  the trait tables, so confirm the bar-facing ID in game before hardcoding; the
  metadata table should carry both base and upgrade IDs; Emerald Blossom is
  effectively CD-free for this spec (auto-learned 365262 removes the 30s CD);
  Essence gating pends probe #7; Stasis 370537 is proactive banking — offer before
  expected damage, not reactively; Living Flame heals-or-damages by target.

## Data work (audit findings — actionable regardless of heal mode)

1. **Generator universe bug** (`gen_spell_cooldowns.py`) — **FIXED + REGENERATED
   2026-08-09** (build 68974): SpecializationSpells added to the universe; build
   string now derived from CSV filenames (stale hardcoded default removed).
   38 entries rescued, zero dropped — all healer dispels (Purify/Cleanse/Purify
   Spirit/Nature's Cure/Detox/Naturalize + class-wide variants), Penance, Prayer
   of Mending, plus non-healer strays (both Divine Protections, Vampiric
   Embrace, Silence, Judgment, much of the DH kit). Still absent because no
   grant row exists in this alpha build (auto-resolves on launch-build regen):
   Rapture 47536, Circle of Healing 204883, Divine Star 110744, Symbol of Hope
   64901, Dream Breath 382614 / Spiritbloom 382731, Adaptive Swarm 391888.
2. **HEALING_SPELLS top-up** (fail-open leaks into the DPS queue): Druid — Nourish
   50464, Grove Guardians 102693, Incarnation: Tree of Life 33891, Convoke the
   Spirits 391528 (heals for Resto); Paladin — Beacon of Faith 156910, Divine Toll
   375576 (class-wide leak); Priest — Penance 47540, Plea 200829, Evangelism 472433,
   Holy Word: Salvation 265202, Symbol of Hope 64901 (Guardian Spirit 47788 →
   defensive family); Shaman — Chain Heal 1064, Earth Shield 974, Unleash Life 73685,
   Primordial Wave heal variant 428332; Monk — Reawaken 212051, Chi Burst 123986,
   Sheilun's Gift 399491, Celestial Conduit 443028; Evoker — Echo 364343, Temporal
   Anomaly 373861, Zephyr 374227.
3. **Data bug**: SpellCategories entry `[382024]` labeled "Primordial Wave (heal
   component)" is actually Earthliving Weapon; the Resto heal variant is 428332.
4. Charge-category cooldowns (Swiftmend, Nature's Cure, Holy Shock, Cleanse) read 0
   from plain SpellCooldowns — generator/readers must resolve ChargeCategory.
5. **Per-spec spell universe is now derivable offline** (validated end-to-end at
   68974): `TraitDefinition(SpellID/VisibleSpellID/OverridesSpellID) →
   TraitNodeEntry.TraitDefinitionID → TraitNodeXTraitNodeEntry → TraitNode →
   conds = TraitNodeXTraitCond ∪ (TraitNodeGroupXTraitNode →
   TraitNodeGroupXTraitCond) → TraitCond.SpecSetID → SpecSetMember.SpecSet →
   ChrSpecializationID`. An entry with zero TraitNodeXTraitNodeEntry rows is
   orphaned/unreachable. CondType=1 is the practical spec-gate; every used SpecSet
   maps to exactly one spec at 68974. The CSV folder now tracks the whole chain
   (TraitCond, SpecSetMember, TraitNodeGroup + 3 join tables) plus SpellLearnSpell —
   `update_data.py` refreshes them automatically. Feeds the universe fix in #1 and a
   future per-spec gen script; nothing in tools/ reads these tables yet.
6. Tooling bug found while validating: `update_data.py`'s diff summary keys rows on
   the first CSV column, which is a localized-text column for SkillLineAbility /
   SpecializationSpells — it reported 25 and 2 "rows" for full 17,756- and 632-row
   exports. Pull integrity is unaffected (verified by direct row counts); only the
   diff report is wrong.

## Options integration & defaults

Tri-state needs NO new storage: Disabled = the existing char-level sentinel;
DPS = sentinel cleared + profile `healing.enabled=false`; Heal = cleared + true.
The mode radio writes both.

New top-level **Healing** tab (order 4 — sidebar reads offensive/healing/defensive):
mode radio w/ disabled-healer banner (the discoverable enable path), ally-low
group (managed toggle, percent slider via Blizzard's index mapping, mute-voice,
live status line), emergency group (crisis count, tank-external, LSM sound),
cue row group (enable, hover opt-in + click-block warning, scale), per-spec heal
priority list (Defensives' Priority Lists widget factory), filler-dimming toggle.
Non-healer specs collapse the tab to a note (dynamic-refresh pattern). Filler
style (auto/caster/weave) lives on the OFFENSIVE tab; `groupHealSpells` storage
stays a fourth SPELL_LIST_CONFIG row under defensives.classSpells — the Healing
tab is a view (Abilities-card precedent).

Defaults: healer specs are ENABLED by default as of Phase 1 (owner decision
2026-08-09 — DPS mode is verified healer-clean, so default-off lost its
rationale; characters with stored DISABLED state keep it, hint + /jac enable
cover them; the firstRun auto-disable seeding is deleted). Heal
mode enable turns on a COMPLETE setup — managed ally-low (index 6 ≈ 50%, voice
muted, user values saved/restored, never touch user-configured alerts),
emergency slot (count 3, tank-external on, sound None like interruptAlertSound),
cue row on with hover OFF (invisible mouse-block must be opt-in), filler +
dimming on with dimming AUTO-INVERTED for Discipline (spec behavior, not a
knob), filler style auto, dispel/upkeep on-but-dark behind their self-tests.

## Phase 6 — Polish

Who-chips (class-colored name/role) on ranked ST suggestions; switch-arrow reuse when
suggested unit ≠ current target (SafeUnitIsUnit preflight, fail-open); DPS-filler
dimming (inverted for Disc); options copy for the CVar threshold guidance; locales;
Masque group for cue row; `/jac inspect healmode` diagnostics.

## Limits (documented, not worked around)

No lowest-first sorting; no ally range/LoS gating; raid = display-only cues + cadence
(no raid-low signal exists); severity-blind triggers (count of members below ONE
threshold); mana = affordability + the 20% line, nothing finer. Every probe-gated
feature ships dark and fails open. Re-run all probes after every patch.
