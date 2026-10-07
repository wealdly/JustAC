# Forever dead-code pass (2026-10-04)

> **Superseded direction (2026-10-07): the branch must stay backward compatible with
> retail** (one codebase, `## Interface: 120100, 16001`). Nothing below is to be DELETED;
> "dead on Forever" now means "gate on `SpellDB.IsForever()` / `BlizzardAPI.HasGamePick()`"
> or "add a `<CLASS>_F` entry". The inventory stays useful as the list of retail-only paths.

Branch `forever`. Three things make code dead on Forever, and every finding below traces to
one of them:

- **No pick.** `GetNextCastSpell` is always nil, so `primarySpellID`, the WAIT sentinel, and
  everything that reads "the game's pick" never run. (The rotation POOL still exists: it is
  the action bars now.)
- **`<CLASS>_F` spec key.** Every table keyed `CLASS_N` or by retail spec ID misses. Tables
  read through `SpellDB.ResolveDefaults` fall back to the class key; tables read directly
  have no fallback and are never read.
- **Vanilla game.** Nine classes (no DK, DH, Monk, Evoker), mana/rage/energy/combo points
  only, and the class-resource frames are excluded from camelot (`[ExcludeLoadGameType camelot]`
  in `Blizzard_UnitFrame.toc`). EncounterTimeline does not load.

Line counts are approximate.

## Tier 1: dead whatever the probes say (~7,500 lines)

| Area | Where | ~Lines | Removal touches |
|---|---|---|---|
| SimC stack - **REVISED by `FOREVER_ENGINE_DESIGN.md`: keep `RotationImport`, the generator and the gate evaluators (they become the engine); only the retail data and pick-relative parts are dead** | `Data/SimcRotations.lua`, `RotationImport.lua`, SpellQueue gate layer 819-873 + 941-1211 + SimC parts of CategorizeAndAssemble / `_StageTail`, `WithAdditions` (SpellQuery 177-237), PriorityList simc tab + gate phrasing 355-536, CustomQueue 86-170, UIRenderer `EmpowerNumeral` | 3,300 | TOC, DebugHUD, locale keys `Priority Tab Simc`, `Burst Source simc` |
| Blizzard order data | `Data/AssistedCombatOrder.lua`, `GetBlizzardRank` and its readers (SpellQueue `rankOf` "ac", PriorityList 122-132) | 560 | "Match Blizzard's pick" ordering degrades to context fit only |
| Pick consumers | Safe Lead (`_ApplySafeLead`, `SafeLeadCandidate`, `CostsPrimary`, `GatesConfirmed`, `IsSafeLead`), `_StagePrimary` pick/WAIT/dot-spread/highlight lookahead, WAIT sentinel + `RenderWaitSlot`, `displacedPrimary`, gap-closer pick shifting, `_StageContext` pick tags, `pickWindows`, `NotePick` | 450 | `_StageFinalize`, Options "safe" lead value + locale keys, UIRenderer readers |
| FightWindow | whole file | 160 | TOC, SpellQueue context, JustAC 2024, DebugCommands |
| AC plumbing | SpellQuery next-cast trio, `IsWaitPlaceholder`, AC branch of `GetRotationSpells`, `ValidateAssistedCombatSetup`; ActionBarScanner `GetAssistedCombatSlot`/`InvalidateAssistedSlot`; BlizzardAPI.lua AC-slot usability fallback; UIRenderer raw `GetNextCastSpell(true)` per icon refresh; JustAC `AssistedCombatManager.*` callbacks, `ASSISTED_COMBAT_ACTION_SPELL_CAST`, AC CVar handling + update-rate CVar read | 280 | |
| AC options | General `disableBlizzardHighlight`, Offensive `includeHiddenAbilities`, PriorityList "Blizzard's pick" pin label | 40 | locale keys |
| Absent classes | DK/DH/Monk/Evoker keys across SpellDB (defensive, group help, maintained buffs, top-off, pet summon, raid buffs) and Data files; spec-only keys of absent specs | 250 | |
| Retail class resources | StateHelpers `RESOURCE_BAR_DEFS` widget path 2026-2213 (all frames missing on camelot), `DIRECT_POWER` non-vanilla rows, UIHealthBar `POWER_COLOR` / `SECONDARY` non-vanilla rows, SpellQueue `DISCRETE_POWER` except combo points | 300 | keep `DirectPowerRead` |
| Healer machinery | `CLASS_GROUPHEAL_DEFAULTS`, `HEAL_EMERGENCY_LADDER`, DefensiveEngine group-heal pass + emergency ladder + reseed, `DEFENSE_TIER_SPEC`, `DEFAULT_WAIT_SPEC`, stagger `floatAuras` | 250 | Options/Defensives rows |
| Spec-only defaults | `CLASS_GAPCLOSER_DEFAULTS`, `GAP_CLOSER_REQUIRES_STEALTH`, `CLASS_BURST_TRIGGER_DEFAULTS`, `RANGED_DPS_SPECS` | 180 | gap-closer/burst engines stay, fed by user lists |
| Debug probes | `MaintenanceProbe`+`MaintenanceLog`, `EncounterTimelineProbe`, `ResourcePointProbe`, `SimcGateProbe`, `PickLog`, `RotationOrderProbe`, `GateDiagnostics`, `FightWindowDump`, AC rows in Module/Heal/Precombat/Aoe/Validate/Why/ContextRank probes, DebugHUD AC rows | 1,700 | `INSPECT_TOPICS` rows |

## Tier 1b: tank maintenance slot (~1,550 lines) - decide, don't just delete

`SpellDB.MAINTENANCE_DEFENSIVE` has only spec keys (`WARRIOR_3`, `PALADIN_2`, `DRUID_3`, plus
DK/DH), so MaintenanceTracker's bridge (~1,130 lines) and `UI/UIMaintenanceAura.lua` never
engage. Forever warriors and druids still tank, and the Cooldown Manager loads on camelot, so
this can be RETARGETED (class keys + Forever spell IDs) instead of deleted. CC-break / loss of
control (~150 lines of the same file) is live either way.

## Tier 2: KEEP - Forever is secret-restricted (measured 2026-10-04)

The first OOC probe run settled H1: `HasSecretRestrictions` is true OUT of combat, and player
power and target health already read SECRET out of combat (stricter than retail). The
secret-value toolkit (threshold gates, readiness probe, laundering sinks) and its probes are
the foundation of the Forever engine, not dead weight.

## Tier 3: regenerate, don't delete

spellID-keyed retail data, 6-40% of whose IDs even exist on Forever (measured against
Forever's SpellName): SpellArchetypes, SpellCooldowns, SelfAuras, PrecombatBuffs,
SpellCategories, SpellTransforms, HealingItems, InterruptAbilities, CCBreakers,
RangeReferences, TargetDots, ChanneledSpells, AuraStacks, plus SpellDB's class-keyed defensive
and maintained-buff lists. Source: `Documentation/wow_spell_csv_forever/` (build 1.60.1.70205).
Hand-curated files (InterruptAbilities, RangeReferences, ChanneledSpells, SpellCategories)
need a manual Forever pass. `tools/gen_aura_durations.py` targets a file that no longer exists.

## Behaviour bugs found (fix, not delete)

1. **PrecombatEngine group demand** treats our own queue head as "the game's demand" and the
   bar pool as "the rotation", so a lone group member on the bars is forced over an active
   one (can nag Deadly Poison while Instant Poison is up). `ACPickInGroup` 290-312,
   `pendingDemand` 581-610.
2. **RedundancyFilter**: `NoteSpellRecommended` was the only expiry for in-combat
   activations of cooldown-less self-buffs. Without it, a buff cast mid-fight stays hidden
   until combat ends, even after it falls off.
3. **ContextRank**: `ctxRange` only came from the pick, so multi-target context always reads
   as melee and every ranged AoE takes `GEOM_PEN`.
4. **Bar changes** invalidate the pool but skip `ClearAvailabilityCache` /
   `PreCacheRotationCooldowns`, which the retail `RotationSpellsUpdated` handler ran.
5. **Options/GapClosers** always shows the "ranged spec" warning (`IsMeleeSpec` is spec-keyed).
6. **PrecombatEngine `STEALTH_REMINDER.DRUID`** has `spec = 2`, so the Prowl reminder never fires.
7. **GCD dummy 61304 does not exist on Forever** (absent from SpellName 1.60.1.70205). It is
   read by `CooldownTracking` `GCD_DUMMY_SPELL` (GCD lookahead) and `SpellQuery`
   `GetGCDInfo`; both fail closed, so the lookahead silently turns off and `GetGCDInfo`
   reports no GCD. Replacement source decided by probe H13.
8. **Every Forever spec is role DAMAGER with primary stat 0** (ChrSpecialization 1482-1491).
   So healer-spec logic (`IsHealerSpecActive`, `FilterHealerTail`, the healer first-run
   disable) never triggers for a healing priest/druid/shaman/paladin, and SpellDB
   `PlayerPrefersOil` (primary stat == Int) is always false, so casters are offered
   sharpening stones instead of wizard oil. Healer detection needs the group role or a setting.
9. `UI/UIRenderer` reads `PlayerCastingBarFrame.casting/.channeling`; Forever's cast bar skips
   updates while the gamepad UI is on, so those go stale for gamepad players.

## Corrections to earlier assumptions

MEASURED: `[AllowLoadGameType mainline]` includes camelot. AssistedCombatManager loads,
the Personal Resource Display loads without a class frame, and the combo-point bar frames do
not exist. `classic, standard`-tagged addons do NOT load (the specialization shims are absent
even with `loadDeprecationFallbacks` = 1). Assisted Combat is off with reason
`WRONG_WORLD_STATE_EXPRES...`: a server world-state gate, but the AssistedCombat DB2 tables are
absent from the build, so turning it on would still need a client patch.
