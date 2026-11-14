# Development tooling

Reference for the local tools this repo expects, and how to install them if
they are missing. None of this ships to players - `.pkgmeta` excludes `tools/`,
`Documentation/`, and `.luacheckrc` from the CurseForge package.

## Temporary combat-signal capture

With the local `JustAC_Research` companion enabled, `/jac inspect start` includes
the source-research `signal.*` channels on Retail and Forever. Without it, the
standard diagnostics still work, but Research channels are absent.
Use `/jac inspect stop`, then `/reload` to flush the capture
to SavedVariables. No queue behavior or player settings change.
See [capture instructions and coverage limits](FOREVER_COMBAT_SIGNALS.md#temporary-capture-routine).
New candidates are observations, not validated gameplay gates.
Capture output uses context markers plus field deltas, separate priority
definitions/context/verdicts, and classified range/meter deduplication. See
[capture volume and retention](FOREVER_COMBAT_SIGNALS.md#capture-volume).
The capture also includes bounded per-entry/nested-condition `PRIORITY` records;
see [coverage and controls](FOREVER_COMBAT_SIGNALS.md#priority-condition-coverage).
For a static, report-only inventory use
`python tools\gen_forever_rotations.py --coverage`; no generated Lua is written.

## Lua static analysis (the pre-commit / pre-reload gate)

Queue optimization regressions in `python tools\test_forever_openers.py` check
empty/full/single-entry sort fast paths, stable rank ties, one hold-setting lookup
per admitted spell, and lazy tri-state DoT memoization reset on every categorization
pass. These establish reduced work and preserved queue behavior, not live CPU savings.
The same suite exercises spellbook proc candidates through the shared categorizer on both
clients, including contextual vetoes, automatic burst holds, settings across Forever ranks,
deduplication and the actual tail stage without a cached rotation.
`python tools\test_forever_general_priorities.py` also checks Shifting Power's below-50
Energy boundary, unknown reads, proc/cap promotions, Mana affordability, maximum-Energy
changes and explicit ordering/hold overrides using the generated Druid entry.
`python tools\test_forever_aura_policy.py` uses the real generated data, tracker and shared
tail stage to cover every Holy Fire rank, Thunder Clap's different tree policies, bounded
cast estimates, miss cancellation, CDM precedence, prerequisites, proc vetoes and totems.
It also requires every emitted self-refresh condition to have an observation route.
`python tools\test_aura_read_cache.py` combines the real categorizer, buff evidence,
target tracker and CDM reader in one runtime. It checks exact read counts, shared
true/false/unknown evidence, independent cast-duration policies, fresh passes,
miss/target changes and live diagnostic reads on both clients where applicable.
`python tools\test_precombat_preparation.py` checks preparation groups
with real Forever seal ranks, active alternatives, denied/secret reads, visible
offer deduplication and disabled surfaces. It also checks generic groups on both
clients, Retail data isolation and combat reapplication after aura loss. Additional
cases cover active-family suppression in the primary/tail, one missing
buff choice per finished queue, stale-queue fallback and deliberate stance changes.
Early consumption and denied reads cannot reuse an old active-family estimate.
The real Cooldown Manager reader also covers shared Seals records and linked
alternatives through primary, tail and stale-queue filtering, including live
active/down transitions, secret/unavailable activity, hidden viewers and
cooldown-only entries on both clients.
Bounded OOC refresh cases verify exact 25%/10-second boundaries across buff durations,
active seal/rank preservation, readiness, cooldown-free eligibility, permanent effects,
forms, unknown/denied timing, application grace and hostile-target emphasis.
The primary, tail, lookahead and stale fallback agree on refresh eligibility and visible
offer handoff; active-only shared viewer evidence never authorizes early refresh.
Recovery tests cover learned heal ranks without Recuperate, Auto/explicit/item-only
choices, unavailable and unknown spells, ongoing healing, independent mana
recovery and heal-first insertion ahead of consumables.
Context cases cover tree/spec selection, mounted/alternate/unknown forms, usability and
readiness, Hunter aspect defaults and Retail rites. The actual primary stage and
pre-combat insertion block verify slot-1 routing, sibling/rank deduplication,
hidden/disabled fallback and preparation ahead of a full consumable checklist.
The insertion test seeds DPS exclusions with the same preparation spell to
prevent a circular handoff where neither surface yields to the destination.
The low-level case knows only Seal of Righteousness 21084, not canonical 20154,
and verifies learned-rank selection, readiness and active-aura detection.
Paladin blessing upkeep cases cover missing Might, learned ranks, active
Might/Wisdom/Kings alternatives, restricted aura reads and no combat offers.
Forever blessings are long-duration maintained buffs, not short combat preparation;
their source policy lives in `tools\gen_forever_defaults.py`.
Critical-preparation context tests cover confirmed missing families with a live
hostile target, learned ranks, alternate buffs, mounted/dead/vehicle states,
unknown/denied reads and weapon-hand selection. `combatCritical` is an explicit
preparation-group policy; weapon imbues/rites use the existing weapon policies.
Routine upkeep is not promoted to urgency. Family reads share a 0.25-second
cache across display surfaces, invalidated on player aura changes and applications;
readability, target context and readiness are still checked live.
`test_debug_probes.py` exercises the actual shared tinted-proc animation and both
renderer paths: glow modes, proc precedence, immediate preparation downgrades,
Proc Only OOC preparation animation on both shared renderers, No Glows suppression,
frame reuse and cleanup. This is offline validation, not proof of live visual
appearance or combat aura access; restricted/unknown aura state never enables the
new tint.
The same tests check reused-frame recoloring, neutralized atlas bases and shared
palette application to preparation/mitigation rings and proc-style glows.
Sustain claimant changes also repaint when the urgent stage is unchanged:
mitigation stays blue, pet/group heals turn green and CC escapes use movement blue.
`UIAnimations.GLOW_COLORS` owns custom glow colors; the player's color legend is
in [README](../README.md#glow-colors). Keep native proc/assisted art untinted and
do not duplicate the custom RGB values in renderers or secret-alpha containers.
Upkeep-family regressions also cover Divine Spirit, Shadow Protection, Thorns,
Prayer/Brilliance/Gift equivalents and every additional Hunter aspect. Detection
does not require learning the active buff's cast; offers still require a learned
member. Missing families fall back to a learned member if their preferred default
is unavailable, without overriding an explicit assisted demand in another group.
Lifecycle cases execute the shared update-loop scheduling block: out-of-combat
defensive rendering precedes DPS invalidation/rendering, throttled handoffs wait
together, periodic updates follow the same order, and combat scheduling stays
unchanged. Player-aura changes invalidate the checklist outside combat even
when the broader aura-cache invalidation is throttled.
`test_support_queue_fixes.py` checks the top-off slider's 50-90% range in 10%
steps, each threshold on exact and engine-gate paths on both clients, legacy
95%, the default 80% when unset, immediate clearing above the line, onset
debounce and unavailable gates. Below-full, regen, party alerts and post-combat
activity must not substitute for the configured threshold; the emergency floor
remains independent. Registry regressions also exclude healing spells and HoTs
from additive precombat buff offers, including Forever ranks, while retaining
real buffs and health-gated recovery on both clients.
`test_forever_consumables.py` covers the configurable 80% mana-recovery default,
all 10% selections, explicit hybrid mana, unknown reads, active consumption,
combined-item deduplication, Recovery Off and threshold changes through the
cached checklist. Diagnostic recovery thresholds follow the saved selection.
`test_forever_options.py` executes the Preparation options on both clients to
check section ordering, food/recovery terminology, client visibility, unchanged
saved values and Recovery Off disabling the mana slider.
Recovery tests also cover independent health/mana overrides, inheritance from
the legacy combined setting, combined food/drink with either recovery type off,
and deduplication against buff-food offers.

WoW loads the addon's Lua at runtime; a stray brace or a typo'd global
(`UnitAffectingCombt`) is a silent failure that only shows up as an addon that
won't load. Catch it before `/reload` with:

```
tools/check.ps1                     # whole addon
tools/check.ps1 SpellQueue.lua ...  # just the files you touched
```

`check.ps1` prefers **luacheck** and falls back to a **luaparser** syntax check.

### luacheck (recommended)

Catches syntax errors, **undefined globals**, unused locals, and accidental
global writes. It is a standalone Windows binary - no Lua/luarocks/compiler
needed. Expected at `tools/luacheck.exe` (git-ignored; not committed).

Install if missing:

```
curl -L -o tools/luacheck.exe https://github.com/mpeterv/luacheck/releases/download/0.23.0/luacheck.exe
```

Config is `.luacheckrc` at the repo root. Its `read_globals` list is **harvested
from the addon's actual API usage**: a new undefined global (a typo, or a `local`
you forgot to declare) will not be in the list and so gets flagged. Don't add a
name there to silence a warning unless you've confirmed the WoW API really exists.

Run the gate on the affected files and confirm no **errors** or **new** warnings
versus their pre-change output. Do not rely on a copied repository-wide warning
total; checker availability and source changes make it stale. The fallback is
syntax-only and cannot establish an undefined-global/unused-local warning baseline.

### luaparser (fallback)

Syntax-only (no undefined-global analysis). Pure Python, useful if the luacheck
binary isn't present. Needs:

```
python -m pip install luaparser
```

`check.ps1` uses it automatically when `luacheck.exe` is absent; or run directly:
`python tools/luasyntax.py <file.lua> ...`

## Data-generation tools (`tools/*.py`, `tools/*.sh`)

Generated spell tables under `Data/` come from wago.tools CSVs and pinned rotation
inputs via `gen_*` scripts. Curated tables are maintained by hand; ownership is
listed below. Check each generator's header for required inputs. Generated Lua
is committed, not the multi-MB source CSVs.

### Updating the CSVs

`python tools\update_data.py [build] [--product wow|wowt] [--dir path]`
downloads into its input folder, diffs row counts, removes the previous build
after downloads succeed, then runs generators unless `--skip-gen` is set.
**It is not an atomic folder replacement:** failed downloads leave mixed builds.
Use the [staged two-client workflow](#two-client-update-check-and-refresh).
The table set is **self-maintaining** - whatever `<Table>.<build>.csv` files sit
in `Documentation/wow_spell_csv/` (gitignored) define what gets pulled. To track a
new table, download it once by hand from
`https://wago.tools/db2/<Table>/csv?build=<build>` and re-run. Keep the folder on
**one build**; generators join across tables. Full flag list: the header of
`tools/update_data.py`.

For Forever pass the discovered `wowf` build explicitly with the appropriate
`--dir` and `--skip-gen`; do not rely on undocumented product auto-detection.
`--dir` does not retarget the generators. Run the Forever generators explicitly
after accepting the staged snapshot. `gen_cc_breakers.py` needs both clients' CSVs.

### Two-client update-check and refresh

Every update-check covers Retail and Forever. Checking alone does not authorize
changes, builds, commits, pushes, tags or releases. Implemented runtime updates
follow the standing [runtime test sync](#runtime-test-sync) workflow.

1. Compare installed builds, published builds, CSV builds, mirror revisions and
   both deployed addon copies. Record checked revisions/context, not "latest"
   based only on a version label. For mirror paths see [source mirrors](#source-and-enum-mirrors).
2. Before adopting external sources, verify license/redistribution compatibility.
   Preserve notices and document authors, URL, license, pinned revision and local
   adaptations in source documentation and relevant project README credits.
   Unresolved licensing blocks adoption.
3. Refresh the four source mirrors with `update-sources.ps1` (fetch + fast-forward
   only): Retail UI `live`, Forever UI `forever`, packet-parser enums `master`,
   Retail SimC `midnight`. Stop on dirty/conflicting mirrors; never reset them.
4. Keep separate CSV folders: `Documentation\wow_spell_csv` for Retail and
   `Documentation\wow_spell_csv_forever` for Forever. Copy the complete old snapshot
   to a separate staging folder, refresh that copy with `--skip-gen`, then verify
   successful downloads and exactly one complete build before replacing live data.
   Keep the previous snapshot until validation succeeds. Never generate from a
   failed/mixed download or use `--keep-old` in a generator input folder.
5. Forever download form: `python tools\update_data.py <wowf-build> --dir <staging-folder> --skip-gen`.
   After accepting it into the Forever CSV folder, run:
   ```
   python tools\gen_forever_rotations.py
   python tools\gen_forever_defaults.py
   python tools\gen_forever_consumables.py
   ```
   Review generator headers for required inputs. Run `gen_cc_breakers.py` only
   with both complete client snapshots. The updater's default generator sweep
   is not a client-specific refresh.
6. Rotation freshness is separate: refresh Retail pins with
   `tools\update_simc_apl.py`; review Forever vendored inputs and local pins via
   [rotation source review](CLIENT_COMPAT.md#forever-rotation-source-review) and the
   [Forever guide-to-archetype workflow](forever-guides/README.md#guide-to-archetype-workflow).
   Forever has no native Assisted Combat priority feed. A recent repository or
   simulation result alone is not evidence of an importable, reliable list.
7. Review generated diffs, run affected audits/tests and the Lua gate. Audits are
   report-only: candidates require judgment, not automatic curated-list changes.
   After validated runtime changes, sync and verify both test copies as described below.
   Do not reconcile old branches as part of an update check.

### Auditing the hand-curated tables

`Data/*.lua` regenerates itself, but the curated tables in `SpellDB.lua` do not, so
they rot silently across patches. Run this after every CSV refresh:

```
python tools/audit_defensives.py
```

It checks `CLASS_DEFENSIVE_DEFAULTS` and `DEFENSE_TIER` for the failure mode with no
in-game symptom: an entry the player can never press. `IsSpellAvailable` hides it
forever, so it quietly consumes a queue slot and nothing says why.

There are two distinct ways to land there and they need different tests; the trap is
that a **passive talent node** looks identical to the castable button it grants. The
rule is `castable = reachable AND NOT SPELL_ATTR0_PASSIVE (0x40)`. Both are explained
with worked examples in the script's own header: `python tools/audit_defensives.py --help`.

Note this check does **not** transfer to `Data/SimcRotations.lua`. Unobtainable ids
are correct there: SimC names the button you actually press, so override forms
(`death_sweep`, `swipe_cat`, `templar_slash`) are what match Assisted Combat's live
pick. Rewriting those to base ids would break the matching.

### Auditing against Blizzard's own rotation data

Blizzard's assisted-combat rotation ships in the client data: `AssistedCombat` (one row per
spec), `AssistedCombatStep` (spell + `OrderIndex` = their priority order) and
`AssistedCombatRule` (the conditions on each step). All three are tracked in the CSV folder,
so `update_data.py` refreshes them with everything else.

```
python tools/audit_assisted_combat.py                  # what SimC pool insertion adds, per spec
python tools/audit_assisted_combat.py --diff OLD NEW   # which specs' rotations changed
python tools/audit_assisted_combat.py --cooldowns      # Blizzard's cooldown/movement class vs burst anchors + NEVER_INSERT
python tools/audit_assisted_combat.py --dots           # DoTs Blizzard refreshes when missing vs Data/TargetDots.lua
python tools/audit_assisted_combat.py --healers        # local healer pins vs Blizzard's order
python tools/audit_assisted_combat.py --procs          # ability <- gating aura pairs (reference)
python tools/audit_assisted_combat.py --decode [FILE]  # join an in-game pick log with the rules
```

**Insertion audit.** With SimC priority ordering, the queue adds SimC abilities the game's
rotation list leaves out (`BlizzardAPI.GetRotationSpells` -> `RotationImport.GetInsertable`).
That moves the pool for every spec at once, and the only other way to see it is to log in on
each one. Run this after any change to `Data/SimcRotations.lua`, `NEVER_INSERT`, the gap-closer
defaults or `SpellCategories`, and read the list: anything that moves the player, or that a
player presses for a reason other than damage, belongs in `NEVER_INSERT` (`RotationImport.lua`).

**Rotation diff.** `update_data.py` runs this automatically while both builds are on disk. A
spec listed there is one whose SimC pin (or local healer list in `tools/simc-apl/`) needs a
second look, and is release-note material.

**Classification audits** (`--cooldowns`, `--dots`, `--healers`, `--procs`) diff Blizzard's data
against hand-curated tables. Report-only, and every line is a candidate to look at, not a defect:
a movement ability under `--cooldowns` belongs in `NEVER_INSERT`; most `--dots` misses are aura ids
or stacking DoTs excluded on purpose.

**Blizzard's order ships as data.** `tools/gen_assisted_combat_order.py` writes
`Data/AssistedCombatOrder.lua` (spec -> spell -> rank), the tiebreaker for the "Match Blizzard's
pick" ordering. A spell's rank is its LAST step, its unconditional position: first-step order put
situational multi-target steps at the very top. `update_data.py` regenerates it with the rest.

**The pick recorder** is a diagnostic, not a feature (the plan demoted reading state from the pick: the addon already detects that state directly). `/jac inspect picklog on` records the game's
pick next to the facts the addon can read (enemy count, resource points, power and target-health
bands); `/reload` flushes it; `--decode` joins it to the rules offline and reports how often a
pick pins down one step, plus which facts held each time a numeric condition fired. No rule data
ships in the addon for this.

Two measured limits, both in the script header: the DB2 step list is a **superset** of the live
`C_AssistedCombat.GetRotationSpells()` (live drops talent-gated steps, and every spell whose
steps all carry `ConditionType 70` - which is exactly the major cooldowns and movement
abilities), and talents are ignored, so counts are an upper bound. Where this data goes next:
`Documentation/ASSISTED_COMBAT_DATA_PLAN.md`.

### CSV source tables (which generator reads what)

Most generators share a resolution **spine**: `SpellName` (id -> name),
`SpellMisc` (school/attributes), `SkillLineAbility` + `TraitDefinition`
(talent/override -> base spell), `SpellDuration` (duration index -> ms). On top of
that spine:

| Generator | Distinctive input tables | Produces |
|-----------|--------------------------|----------|
| `gen_precombat_buffs.py` | `Item`, `ItemSparse`, `ItemEffect`, `ItemXItemEffect`, `SpellEffect`, `SpellEquippedItems` | `PrecombatBuffs.lua` (flask/food/rune/imbue + Well Fed) |
| `gen_healing_items.py` | `Item`, `ItemSparse`, `ItemEffect`, `ItemXItemEffect`, `SpellEffect` | `HealingItems.lua` |
| `gen_spell_cooldowns.py` | `SpellCategory`, `SpellCategories`, `SpellCooldowns` | `SpellCooldowns.lua` |
| `gen_aura_stacks.py` | `SpellAuraOptions` (CumulativeAura) | `AuraStacks.lua` |
| `gen_self_auras.py` | `SpellAuraOptions`, `SpellEffect` | `SelfAuras.lua` |
| `gen_target_dots.py` | `SpellAuraOptions`, `SpellEffect`, `SpecializationSpells` | `TargetDots.lua` |
| `gen_spell_transforms.py` | Override-action-bar spell effects (332/333) | `SpellTransforms.lua` (transformed buttons and their bases) |
| `gen_assisted_combat_order.py` | `AssistedCombat`, `AssistedCombatStep`, `AssistedCombatRule` | `AssistedCombatOrder.lua` (last/unconditional step rank) |
| `gen_cc_breakers.py` | Mechanic-immunity spell effects plus item-use links, both clients | `CCBreakers.lua` |
| `gen_forever_defaults.py` | Forever CSVs and curated ability names | `Forever/Defaults.lua` |
| `gen_forever_rotations.py` | Forever CSVs, vendored priorities and local pins | `Forever/Rotations.lua` |
| `gen_forever_consumables.py` | Forever item/spell CSVs | `Forever/Consumables.lua` |
| `gen_aura_durations.py` | `SpellDuration` | *(retained, not shipped - durations are secret in combat)* |
| `gen_archetypes.sh` | `SpellTargetRestrictions`, `SpellEffect` (role heuristics) | `SpellArchetypes.lua` |
| `gen_simc_rotations.py` | SimC APL text + `Data/` token bridge (not a straight DB2 read) | `SimcRotations.lua` |

Curated-by-hand (no generator, no CSV): `SpellCategories.lua`,
`InterruptAbilities.lua`, `RangeReferences.lua`.

## Source and enum mirrors

Root: `D:\.src\WOW\WOW\00-SOURCE\`, **outside** the addon repo.
These dev-local sparse GitHub mirrors are the ground
truth for "how does this API actually behave" (see AGENTS.md rule: never guess a
WoW API):

- **`wow-ui-source`** (branch `live`) - Blizzard's own UI Lua. The generated API
  surface lives at
  `wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`, e.g.
  `AssistedCombatDocumentation.lua`, `Secret*Documentation.lua` (secret-value
  predicates), `Spell*Documentation.lua`.
- **`wow-ui-source-forever`** (branch `forever`) - the same upstream UI source,
  checked out separately for Forever. Its API documentation is under
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/`. Keep this separate from
  `live` so a retail API change is never mistaken for a Forever change.
- **`WowPacketParser`** (branch `master`) - server enum values at
  `WowPacketParser/WowPacketParser/Enums/*.cs`, e.g. `PowerType.cs`.

**Refresh:** `D:\.src\WOW\WOW\00-SOURCE\update-sources.ps1` fetches and
fast-forwards each mirror, including the retail SimC source. It stops on a failed
fetch or a branch that cannot fast-forward rather than resetting local work.

To seed the Forever mirror in that folder:

```powershell
git clone --depth 1 --filter=blob:none --sparse --branch forever https://github.com/Gethe/wow-ui-source.git wow-ui-source-forever
git -C wow-ui-source-forever sparse-checkout set Interface/AddOns
```

Forever rotation inputs are separate from the UI mirrors. The MIT-licensed
MythicSim engine preset snapshot is pinned in
`tools/forever-apl-src/UPSTREAM_COMMIT`; `presets/catalog.json` carries the
application-data source revision. See
[FOREVER_ENGINE_DESIGN.md](FOREVER_ENGINE_DESIGN.md#lists) for source selection
and local adaptations, and `tools/simc-apl-forever/` for the healer damage-filler
pins. Preserve `LICENSE`, `NOTICE.md` and both source revisions when refreshing;
do not substitute Retail SimC lists.

**Looking something up** (grep the mirror instead of guessing):

```
# an API method or return field
grep -ri "GetSpellCooldown" 00-SOURCE/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated
# secret-value predicates (Should*BeSecret, etc.)
grep -ri "ShouldUnitHealth" 00-SOURCE/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated
# an enum's numeric values
grep -ri "PowerType" 00-SOURCE/WowPacketParser/WowPacketParser/Enums
```

## Reading in-game captures

### Diagnostic maintenance

Before removing a debug method, check `INSPECT_TOPICS`, battery/session callers,
timers, options dispatch and tests. A manually invoked research command is not
unused merely because the normal queue never calls it. Preserve active capture
ownership and cancellation; archive/retire research only with explicit scope.

Diagnostics are split by responsibility:

| File | Ownership |
|---|---|
| `DebugCommands.lua` | Shared library, authoritative topic registry, help and profile commands |
| `Debug\Common.lua` | Secret/plain/error classification, formatting and shared lookup helpers |
| `Debug\Capture.lua` | Bounded SavedVariables log, output proxies and error recorder |
| `Debug\Session.lua` | Start/stop/status/report, scheduling and recorder ownership |
| `Debug\Queue.lua` | Queue explanations, imported gates, ranks, DoTs and pick logging |
| `Debug\Systems.lua` | Durable troubleshooting for shipped features |
| `Debug\Validation.lua` | Repeatable checks of production assumptions and standard audit battery |
| `Debug\Research\` | Optional local experiments, broad sweeps and temporary signal captures |

Subfiles extend the same `JustAC-DebugCommands` library. Helpers load before
consumers in the TOC. Keep mutable state, callbacks and cleanup with the owning
diagnostic; do not introduce separate libraries or duplicate read classifiers.

Research sources are **local-only**: `Debug\Research\` is gitignored, excluded
by `.pkgmeta` and absent from the shipped TOC. `build.ps1` rejects research TOC
entries instead of producing a package that references missing files.
Gitignore does not untrack already committed files; review staged paths.
Do not delete the local research folder expecting Git to restore it.
Resolved findings belong in documentation and small durable validation checks,
not in permanently shipped exploratory sweeps.

To install the local companion into a chosen test client, explicitly run:

```powershell
.\tools\install_research.ps1 -AddOnsPath 'C:\Blizzard\World of Warcraft\_retail_\Interface\AddOns'
```

This copies only the companion to the sibling `JustAC_Research` addon folder;
it does not sync JustAC or touch another client. The standing runtime sync runs
it for both the Retail and Forever AddOns directories. Enable the companion in the
addon list; a newly installed addon may require restarting the client.
Re-run the installer after changing local probes. Do not install/sync it over
an active test session without agreeing on a reload boundary.

Normal installs retain operational diagnostics, error capture and
`/jac inspect start` health/resource/queue sampling plus production-assumption validation.
Without the companion, research-only topics are omitted from help/dispatch,
the session explicitly reports standard-only coverage, and the saved baseline
records `researchAvailable=false`. With it enabled, the original broad capture,
priority-condition evidence and research watchers are available.
Stopping a session never stops recorders it did not start.
The rolling detailed log holds up to 8,000 rows normally or 32,000 with the
research companion loaded. Overflow retains the newest half and counts discarded
rows; the report warns when detail is incomplete. Baseline and summary remain
separate. The ten-minute shared-session limit is unchanged.

Run `python tools\test_debug_probes.py` after changes. Tests load the real Lua
files in TOC order on Lua 5.1, with and without the companion and with both client
variants. A clean clone without local research still runs the durable tests;
research-only cases are explicitly skipped. Each active experiment should state
its question, controls, verification status and retirement criterion.
Use `.\tools\test_build.ps1` and `.\tools\test_install_research.ps1` for disposable
packaging/installation fixtures; they do not build a release or modify deployed addons.

`/jac inspect gates` uses the same per-context reporter as `simcgates`, including
cleave and unknown/delegated entries. The reports describe imported conditions,
not player hold overrides or final ordering. `/jac inspect rotation` excludes
JustAC pool additions and is inapplicable without a Blizzard feed.
`/jac inspect stacks` reports out-of-combat aura shape only; it cannot establish
combat threshold access or rule it out.

### Capture workflow

The current topic registry is `INSPECT_TOPICS` in [DebugCommands.lua](../DebugCommands.lua);
use `/jac help` rather than a copied command inventory. For a regression start
with `validate`, `errors`, `secrecy`, then the relevant subsystem probe.

Prefer structured `JustACGlobal` captures in the client's
`WTF\Account\<ACCOUNT>\SavedVariables\JustAC.lua`; `.bak` is the previous flush.
**Play, stop recording, `/reload` or log out, then read disk.** SavedVariables
are not live. Confirm the flush before interpreting results.

For intermittent faults use bounded, debug-only, change-oriented time series
with client/build, target epoch, API success and plain/secret/unknown/error
classification. Do not persist raw secrets or enable captures for normal players.
Reuse the shared capture lifecycle and its bounds rather than adding parallel
recorders. `/chatlog` is opt-in; `Logs\WoWChatLog.txt` may not exist and is a
truncated/interleaved fallback, not the preferred evidence channel.

## Runtime test sync

Local runtime syncing has standing authorization after every validated runtime
update, including fixes, cleanup and generated-data changes. Do not wait for a
separate sync request or leave one test client on older code.

### Current local layout

| Purpose | Location |
|---|---|
| Git checkout, development tools/docs and ignored Research sources | `D:\.src\WOW\WOW\00-SOURCE\JustAC` |
| Shared core runtime | `D:\.src\WOW\WOW\00-SOURCE\JustAC-runtime\JustAC` |
| Separate local Research companion runtime | `D:\.src\WOW\WOW\00-SOURCE\JustAC-runtime\JustAC_Research` |
| Pre-migration snapshots and hash manifest | `D:\.src\WOW\WOW\00-SOURCE\JustAC-local-backups\20261113-1134` |

Both clients' `Interface\AddOns\JustAC` directories are junctions to the shared
core runtime. Both sibling `JustAC_Research` directories are junctions to the
separate companion runtime. Research is not embedded in the core runtime.
SavedVariables and addon enablement remain client-specific in each client's
`WTF` directory; junctions do not share settings or captures.

### Validate, deploy, verify

- The local development checkout is
  `D:\.src\WOW\WOW\00-SOURCE\JustAC`. Run tests and edit sources there, not through
  a deployed addon path. Open editor/agent workspaces and terminals there too.
- Run affected tests and the changed-Lua gate before copying validated runtime
  files and required assets/dependencies into the shared target. Do not copy source
  research, Git metadata, tools, caches, archives or documentation. Keep all active
  TOC/XML dependencies and required assets/licenses. Do not copy the entire checkout
  into the runtime target.
  Documentation-only updates do not require a runtime sync.
- A shared runtime update reaches both clients immediately. Do not edit a deployed
  junction to isolate a Forever experiment. Validate in the development checkout
  first; use a separate temporary test installation if client-isolated deployment
  is required. Each running client still needs its own reload.
- Preserve SavedVariables, player settings and unrelated files. Investigate
  unexpected deployment differences rather than overwriting unknown work or
  broadly deleting destination files.
- Verify junction type/target and the complete runtime inventory and SHA-256
  contents against the validated checkout, then verify both client paths. Comparing
  the two junctions alone cannot detect a stale shared target. Resolve active TOC
  entries and XML Include/Script dependencies on both, ignoring commented-out
  entries. Version labels alone are insufficient.
- Keep the local research companion current in both clients too. For a completed
  junction deployment with local `Debug\Research\` sources, run
  the following from the development checkout:

  ```powershell
  .\tools\install_research.ps1 -AddOnsPath 'D:\.src\WOW\WOW\00-SOURCE\JustAC-runtime'
  ```

  This refreshes the separate shared companion visible to both clients. Verify
  each sibling `JustAC_Research` folder
  matches the source TOC, Lua files and LICENSE by SHA-256. The companion stays
  local-only: never commit it or add it to a release package.
  For ordinary client directories, run the installer for each client's AddOns
  directory instead.
- Report parity or any blocker. Syncing files does not reload a running client;
  in-game testing needs a reload, or a restart when required for new addon discovery.
- Keep full pre-migration backups outside AddOns under
  `D:\.src\WOW\WOW\00-SOURCE\JustAC-local-backups`. Do not put a backup containing
  an active TOC beside installed addons.

### Changing or restoring the layout

Before replacing directories or junctions, back up the complete installations,
including hidden Git files and ignored local Research sources, and verify hashes.
Close agents/editors/terminals using the old path before renaming a workspace;
changing a shell's directory does not update an agent session's saved workspace.
Switch the session to the development checkout first, or start a new session there
if workspace switching is unavailable. Repair linked Git worktree pointers after
relocating the checkout, and verify their original HEADs and working changes.

Remove only a verified junction itself when reverting a client path, never its
shared target recursively. Restore the selected backup into the now-empty client
path and verify its inventory, hashes and active dependencies. Ordinary client
directories then require their own runtime copies and Research installer runs;
updating the shared target alone no longer updates them.

This authorization does not include builds, commits, version bumps, pushes, tags
or publication.

## Build and release

Only act on explicit authorization. A cleanup, data update or test is not a
release request. Local `build.ps1` creates the ZIP; CI uses
[release.yml](../.github/workflows/release.yml) and [.pkgmeta](../.pkgmeta).
Documentation, contributor instructions and tools are excluded from packages,
not automatically from Git commits. Review the exact staged file list when the
user excludes documentation from a publication.

For an authorized version bump:

1. Move player-facing `UNRELEASED.md` entries to `CHANGELOG.md`, update
   `JustAC.toc`, then clear the released entries. No research/tooling release notes.
2. Update the player README for significant feature/behavior changes, and verify
   new source files appear in the TOC and local build manifest.
3. Run relevant tests/static analysis and confirm `/jac inspect modules` plus
   gameplay on both clients. Commit the intended files without attribution trailers.
4. Build/push only when authorized. A branch push alone does not publish.

For an explicitly requested release/deploy, create `v<version>` and push the
branch and tag by name: `git push origin v<version>`. Do not rely on
`--follow-tags` for lightweight tags. Verify with `git ls-remote --tags origin`;
the tag push triggers CI publication. Do not tag or publish as a side effect.
