# Forever engine design

Status: implementation reference with historical proposal sections, updated 2026-10-13.
Branch `forever`. Inputs: `FOREVER_PROBE_PLAN.md` (measured
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

### Weapon enhancements and range reads

Forever's `C_Item.GetWeaponEnchantInfo(weaponSlot)` returns multiple entries per weapon.
`Enum.ItemEnchantType.Imbue` and `Temporary` are separate channels: Rockbiter can be active
while the first entry, or the legacy `GetWeaponEnchantInfo()` return, reports no enchant.
`BlizzardAPI.GetWeaponEnhancementInfo` selects the requested channel across all entries.
The precombat checklist and redundancy filter share it. Retail continues using the legacy
API, selected by the existing `IsForever()` client check.

The queue polls hostile targets out of combat, but an event-only swing-range cache need
not update during movement. On Forever, `IsTargetInSwingRange` polls
`C_SwingTimer.IsTargetWithinSwingRange` and retains a valid event result when that API
is absent or returns nil (measured in the saved probe). Target changes clear the event
cache, and `checksRange=false` invalidates it. Attack and next-swing spells use
`SpellDB.IsTargetWithin(5)`, combining known
spell-range probes with the live swing read. An unknown range never becomes an
out-of-range verdict. Retail's Attack spell-range path is unchanged.

The Cooldown Manager option uses Blizzard's registered Settings value when available
and verifies the CVar afterward. Its checked state reads the client CVar, not a saved
profile flag. A refused change is reported without recording a successful opt-in.

Regression harnesses: `tools/test_forever_weapon_enchants.py`,
`tools/test_forever_swing.py`, `tools/test_forever_primary.py`,
`tools/test_forever_autoattack.py` and `tools/test_forever_options.py`.
The in-game check remains necessary: `/jac inspect forever` reports both enchant
channels, the legacy read, live swing range, and the Cooldown Manager CVar state.

## 4. Architecture

### Defensive routing audit (Forever DB2 build 1.60.1.70245)

Compared the nine class pools and defensive defaults against the single-build
Forever CSV exports. This is a routing review, not authorization to add every
candidate to a health-triggered list.

| Class | Finding |
|---|---|
| Shaman | Stoneskin is maintained physical protection, not DPS. Windwall is ranged protection. Grounding, Tremor, resistance and cleansing totems need contextual conditions. Healing Stream already belongs to group help; mana totems are resource support. |
| Mage | Fire Ward and Frost Ward are missing defensive candidates, but school-specific absorption must not become unconditional upkeep. |
| Paladin | Templar's Bulwark is a missing personal absorb. Holy Shield is mixed block/damage tank maintenance. Blessing of Sacrifice protects an ally, not the caster; it is not a generic self-defense offer. |
| Priest | Elune's Grace is a missing avoidance candidate. Fear Ward and Shadow Protection are preparation/contextual protection. Fade is threat management. Divine Grace cannot target self; Contingency Plan targets an ally. Dark Sacrifice spends health for mana. |
| Warrior | Shield Block is missing rotational mitigation. Retaliation combines survival context and damage. Berserker Rage belongs to CC/resource handling. Demoralizing Shout and Thunder Clap retain their tank-rotation roles. |
| Druid | Barkskin and Frenzied Regeneration already have defensive defaults but can enter the automatic offensive pool. Forms, Enrage and Demoralizing Roar must retain their combat roles. Innervate is resource support. |
| Rogue | Evasion and Vanish already have defensive defaults but can enter the automatic pool. Sprint belongs to movement; stealth needs opener context. |
| Hunter | Deterrence and Feign Death already have defensive defaults but can enter the automatic pool. Control traps are situational; damage traps remain offensive. Scouting and taming are utility, not health defenses. |
| Warlock | Shadow Ward is already defensive. Drain Life and Death Coil have both damage and defensive value; Siphon Life remains damage/healing. Pet resummoning is not a generic low-health defense. |

The automatic-pool generator admits damage OR short-lived combat buffs/summons.
The latter is not evidence of an offensive role. Conversely, its damage detector
does not prove the absence of damage from summons, scripts, traps or retaliation.
Category-only filtering is therefore insufficient: Drain Life, Death Coil,
Holy Shock, Holy Nova and Holy Shield are important dual-purpose exceptions.
Use explicit role data with a shared routing rule; preserve custom entries,
Always Show overrides and retail behavior.

The generator then removes unlisted pool spells whose job is not damage, even when
they hit (`not_dps` in `tools/gen_forever_rotations.py`): interrupts on a cooldown
over 8s (Earth Shock at 6s stays a damage press), hard crowd control and taunts by
SpellMechanic / taunt effect, non-damaging movement, stealth and mount buffs, and a
short named `NOT_DPS` list for what the data cannot separate from a combat buff.
Slows and roots on damage spells and every ranged weapon attack stay as fillers.
Runtime discovery merges bar spells with the learned player spellbook, including
known flyout spells. It walks each skill line separately to avoid gaps between
tabs, excludes passive/off-spec/future entries and uses the generated class
admission list. Bar-selected ranks win; otherwise the highest known rank is used.
Discovery is cached until availability invalidation on spell/talent/spec changes.
Macros and missing bindings do not prevent admission. An unranked but eligible
Throw leads sunk melee entries, so WAIT is only offered when that filler is also
unavailable. Retail and custom lists retain their existing sources.

List entries are never filtered. Forever's spell and macro-button usability can
report Backstab usable even when a cast fails with "must be behind your target".
Rear-required attacks therefore use a conservative targeting gate: when definitely
not stealthed and `SafeUnitIsUnit("targettarget", "player", nil)` is definitely true,
the attack is cast-barred. This uses the existing unavailable sink and promotion
veto, preserves stealth openers and tank-held targets, and fails open when the
comparison is restricted. Targeting is a heuristic, not a facing measurement:
a stunned or turning enemy can still target the player.

`Data/SpellCategories.lua` holds the verified Forever rear-required families:
Backstab, Garrote, Shred, Ravage, Ambush and Pounce. Existing rank resolution covers
their ranks. Learned Dirty Deeds waives Garrote's gate. The existing buff-state
helper waives Shred's gate when it detects the legacy Feral set bonus (1213171);
that bonus's availability in Forever is unverified, and an undetected bonus
does not waive the heuristic. Retail does not use this classification.

With Unavailable Last and ranked ordering, an all-sunk Forever queue reserves its
first slot for the shared WAIT sentinel after burst-cue processing. Existing
actionable injections prevent WAIT. The unavailable tail keeps its order within
the configured icon limit. Out of combat this requires a live attackable target;
no-target, friendly-target and dead-target previews remain unchanged. Retail's
WAIT continues to follow Blizzard's own demand rather than this rule.

For maintained protection, the selected default policy is to preserve any active
totem in the same elemental slot. Offer Stoneskin only when the Earth slot is
empty, behind urgent healing, and suppress it when active. Never alternate
Stoneskin and Strength of Earth merely because each queue prefers its own.

Live saved probes identify Earth as slot 2. In combat, GetTotemInfo's occupied
boolean and spellID are secret, and branching on occupied throws. The
GetTotemDuration object passed to the existing duration-readiness probe returned
a plain active boolean for slot 2 while a totem was present; unused slots returned
false. Out of combat Stoneskin returned spellID 8071 and duration-active true.
Another out-of-combat snapshot had occupied=true but spellID=0 and
duration-active=false: do not assume the presence flag and duration are always
equivalent. A follow-up saved combat capture returned duration-active false
with an empty Earth slot, then true after Stoneskin was cast, while occupied
and spellID remained secret in both states. This validates the empty-to-active
transition without reading identity. The captured active-to-empty endpoint was
out of combat, so destruction/expiry mid-combat still needs explicit coverage.
API failure must remain unknown, not be interpreted as an empty slot.

Implemented: curated role routing, elemental-slot preservation and maintained
Stoneskin offers from the editable defensive list. Templar's Bulwark and
Elune's Grace join defensive defaults. Only unchanged previous defaults migrate;
customized lists and deliberately removed entries remain untouched.

A later probe explicitly tested duration-object presence: the empty Earth slot
returned no object in and out of combat. A successful nil-duration result is
therefore empty, not an API failure. An active Stoneskin returns an active
duration object. The shared helper catches thrown reads, reports the error and
returns unknown, suppressing offers until it can read the slot again.

Situational wards, cleansing/resistance totems and rotational Shield Block
are classified but still need their appropriate conditional defensive surfaces.
They are not unconditional health-triggered default additions.

### Out-of-combat opener audit (2026-10-12)

Combat priority is not automatically pull priority. Reviewed all nine classes in
`Data/Forever/Rotations.lua` against the local `forever-guides` notes:

| Class | Decision |
|---|---|
| Shaman | Prefer a confirmed usable, ready, in-range Lightning Bolt before combat. The guides explicitly recommend bolt pulls; Enhancement's sole five-stack Maelstrom gate applies to instant bolts during combat, not a hardcast pull. Earth Shock remains in the queue and interrupt reminder. |
| Druid | Retain form, stealth, resource and DoT conditions; Balance guides disagree between Wrath and Starfire pulls. No universal replacement. |
| Rogue | Retain stealth openers and weapon/positional usability, not a generic cast-time preference. |
| Warrior | Retain preparation and rage/reactive conditions; Charge is handled by the gap-closer stage. |
| Hunter | Retain mark, sting, cooldown and swing conditions; pet engagement is not inferred from being out of combat. |
| Mage | Retain tree-specific proc/stack and mana conditions; no blanket hardcast override. |
| Priest | Retain Holy Fire/Smite and Shadow setup priorities. |
| Paladin | Retain seal preparation, Judgement and ability usability. |
| Warlock | Retain curse/DoT setup and mana recovery rather than automatically promoting Shadow Bolt. |

The Shaman exception lives in queue assembly, not generated combat data. It applies
only to the Forever automatic pool with theorycraft ordering, with no target or a
hostile target confirmed in range. With no target, range and hostility are not
requirements for previewing a pull. Friendly targets do not receive the override.
It only promotes a bolt already accepted by the queue filters. It recognizes all
bolt ranks through `RotationImport.RankBase`. Only the exact sole Maelstrom stack
gate is waived; other gates, blacklist, cooldown, resource, range and lockout checks
remain in force. Real proc suggestions retain their higher-priority bucket.
Combat, custom queues, exact/source ordering and retail are unchanged.

Regression: `tools/test_forever_openers.py`. In game, target an enemy out of combat,
check `/jac why Lightning Bolt` and the leading spell, then enter combat and check
that the ordinary Maelstrom condition resumes. Repeat with a custom list to verify
that its order is not replaced.

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
  `Data/Forever/Rotations.lua`: 28 trees across the 9 classes, the full MIT notice embedded
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
- Generated into `Data/Forever/Rotations.lua`, registered through the existing
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
- `power`: power threshold curve; usability for "can afford this".
- `resource`: readable discrete class-resource points. With Unavailable Last enabled
  in ranked ordering, unavailable abilities use three tiers: regeneration/cooldown
  waits, confirmed unmet class-resource prerequisites, then wasted presses.
  Minimum-cost and explicit point-hold shortages share the rule on Forever and
  Retail; Retail's primary game
  pick remains untouched. This keeps builders ahead after a finisher spends combo
  points.
  Casting prerequisites use `C_Spell.GetSpellPowerCost().minCost`, not optional
  full cost or the imported preferred point threshold. Only matching, readable
  discrete-resource rows whose conditional aura applies establish a shortage.
  Unknown minimum costs do not establish a missing prerequisite. Explicit holds
  remain authoritative. Forever evaluates the imported resource and power
  preferences, with the tiered damage-finisher caps below; an explicit Hold Until
  dial replaces imported resource and power preferences for that entry.
  Retail retains its imported gates and primary pick.
  Exact source-order mode is unchanged. Confirmed minimum shortages veto tail
  promotions, while zero-cost procs remain eligible. The early spellbook-proc
  path requires usability too. Point holds reuse the assembly's resource read.
  Without a readable minimum cost or point hold, the queue does not infer which
  ability builds or consumes a resource from spell identity or low energy alone.
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

### Finisher point caps on short-lived targets

The leveling policy treats Forever combo points as target-bound: points left when
the target dies are not worth pooling for. Logs show `GetComboPoints("player", "target")`
falling to zero when the target clears, but carryover between two living targets
has not been established by a controlled A-to-B-to-A test. The
imported lists are max-level boss APLs (Eviscerate at 4-5 points). Pooling to 5 on a mob
that dies in a few hits only costs builder GCDs and energy. Without a game pick, an
"at least N points" resource gate on a TIERED point spender (`PointGateCap` in
`SpellQueue.lua`) is lowered to a per-target cap (`TargetPointCap`). Tiered means the
discrete cost row has an optional part (`cost > minCost`: Eviscerate costs 1 point and
spends up to 4 more), so any point count casts it, just weaker. Fixed-cost consumers
(a 3 Holy Power or 2 Chi spender) have no tiers and keep the source threshold:

| Target | Cap |
|---|---|
| Boss, elite, rare elite, unreadable classification | none (source target) |
| Normal / rare, confirmed below 20% health | the spell's own minimum cost |
| Normal / rare, confirmed below 50% health | 2 |
| Normal / rare, health above 50% or unreadable | 3 |
| Trivial / minus, health above 50% or unreadable | 2 |

The cap only lowers a source target, never raises one. Tiered spenders whose value is
duration keep the source target too: self buffs (Slice and Dice), DoTs (Rupture, Rip) and
crowd control (Kidney Shot). Energy, buff and cooldown gates, explicit Hold Until dials and
Retail are unchanged.

All-unavailable ordering is not a usability claim. At two points, when a wounded
target's cap falls from three to two, an energy-starved Eviscerate joins the
builders in tier 1 and leads by source position. If all attacks are out of range,
tier 3 also supersedes a finisher's missing-point tier. WAIT now leads in both
cases; the tail remains an ordered preview, not an instruction to cast.

The unreadable-health rows are the generic fallback: `UnitClassification` is NeverSecret,
so if the health threshold reads (`IsUnitHealthBelow`) stop working the cap still drops
from 5 to 3 (or 2 on trivial mobs). An unknown health read never lowers the cap further.
A cast-informed health estimate (builder hits landed on this target) would be the next
fallback, under the same rules as the resource contingency below.

### Contingency: cast-informed resource estimates

If direct resource reads, resource widgets and threshold techniques stop working,
a cast/hit-informed estimate is a viable fallback for builder/consumer ordering.
This is a future contingency, not an implemented resource reader.

- Prefer confirmed generation evidence: a successful hit from a known combo-point
  generator can provisionally add its verified base gain. A successful cast alone
  is weaker evidence: it may miss, be dodged or parried, or generate no points.
- If only successful casts remain observable, label the result as an estimate,
  not a confirmed count. Do not assume unavailable hit evidence exists or infer
  secret damage/combat-log values.
- A confirmed consumer cast can update or invalidate the estimate according to
  that ability's verified spending rules. Do not assume all consumers empty the
  resource, or that all generators grant exactly one point. Procs, extra gains,
  refunds, optional costs and passive regeneration can change the result.
- Keep estimated state separate from the existing confirmed resource reader.
  Use it for advisory ordering only, never to satisfy a strict confirmed gate or
  suppress a spell the client's readable usability says can be cast.
- Reconcile immediately when a trusted read returns. Invalidate stale estimates
  on reload, death and relevant state changes; target-bound resources also need
  target-change handling. Preserve explicit player holds and Retail's game pick.
- Implement through shared resource/spell metadata, not a Rogue-only counter.
  Verify gains, spending rules and observable event semantics on each client.

For now, readable minimum costs and usability take precedence. When counts are
unknown, confirmed non-resource unusability trails regeneration waits; when all
evidence is unknown, the configured priority remains the advisory fallback.

## 8. What changes elsewhere

- `FOREVER_DEAD_CODE.md` Tier 1 "SimC stack" splits: keep `RotationImport`, the generator,
  and the gate evaluators; delete `Data/SimcRotations.lua`, `Data/AssistedCombatOrder.lua`,
  pick windows, pick-leads, Safe Lead and the SimC probes tied to them.
- `BlizzardAPI.GetRotationSpells` supplies the shared learned-spellbook/bar pool to
  the options tools and live queue; imported priorities order that pool.
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
3. Generator Forever profile, `Data/Forever/Rotations.lua`, rank chains; warrior `default` +
   `arms` first.
4. `ForeverEngine` behind the `GetCurrentSpellQueue` seam; tree selection. DONE 2026-10-07,
   without a new module: the existing tail pipeline already ranks a pool by imported
   priority, gates it and fills slot 1 when there is no pick, so phase 4 became
   - `RotationImport.RegisterForever` + a single `Rot(specKey)` reader that installs the
     tree with the most talent points (class default with none; Feral -> bear list in bear
     form), re-picked on `InvalidateLookup` (SPELLS_CHANGED) and druid form changes;
   - rank chains: every rank resolves to its entry, insertions use `HighestKnownRank`;
   - pool = bar spells + learned player-spellbook abilities + every known list ability
     (delegated included on Forever),
     deduplicated by rank family (`ForeverPool`, `WithAdditions`);
   - `SpellQueue.LeadMode` = "mylist" when Assisted Combat is unavailable, so what we
     cannot time never leads;
   - `known` gate evaluator; `swing` / `tick` pending phase 5 (`test_gate_groups.py`).
   Tests: `tools/test_forever_engine.py` (mutation-checked), `test_gate_groups.py`.
5. `queued` and `swing` gates; confirm inherited gates with the open-question probes.
6. Remaining classes' lists; regenerate the other `Data/` tables from the Forever CSVs.

Each phase is testable on its own: phases 1-2 in game with the existing queue, phase 3 with
the generator's own report and `tools/test_forever_rotations.py`, phases 4-5 with the probes above.
