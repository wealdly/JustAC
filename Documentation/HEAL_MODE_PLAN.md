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
helper — its budget is spent in both dimensions. Before any heal-queue code,
decompose it into stages (pos-1 assembly / gap-closer injection / source
resolution / tail assembly / burst cue) passing ONE per-build context table;
each stage gets a fresh 60-slot budget and the arg explosion collapses. Done
as its own change against a known-good baseline, never mixed with features.

The defensive-cluster builder gains a heal surface in Heal mode. Self-defensives
remain (self-low signals are the richest we have); ally-low promotes heals; both plain.

- New per-spec list `groupHealSpells` in `defensives.classSpells[specKey]`
  (shape/fallback/options identical to petHealSpells), seeded from
  `CLASS_GROUPHEAL_DEFAULTS` (Phase 5 tables).
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

## Phase 3 — Triage cue row (hover-to-aim)

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

## Phase 4 — Slot 0 claimant stack (the emergency slot)

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

New tables: `CLASS_GROUPHEAL_DEFAULTS`, `HEAL_EMERGENCY_LADDER`, `HEAL_EXTERNAL_LADDER`,
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
