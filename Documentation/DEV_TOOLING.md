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
On Forever, it temporarily records per-entry next-swing queue eligibility and
restores the queue probe state on stop. Research-only direct swing-range reads
are skipped during combat; no queue behavior or player settings change.
For a static, report-only inventory use
`python tools\gen_forever_rotations.py --coverage`; no generated Lua is written.

## Lua static analysis

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
Its full player-aura cache cases require one batch per refresh and no indexed
timing re-reads, preserving snapshot-based pruning, partial-instance safeguards,
secret timing and the restricted-combat fallback on both clients.
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
   `Documentation\wow_spell_csv_forever` for Forever. `tools/stage_csv_update.py`
   implements this step and the next: `python tools\stage_csv_update.py forever <wowf-build>`
   (or `retail [build]`) copies the live folder to `<folder>.staging`, downloads there with
   `--skip-gen` and refuses unless every live table is present on exactly one build;
   `--accept` keeps the old folder as `<folder>.previous`, moves staging live and runs that
   client's generators; `--discard` drops staging. Never generate from a failed/mixed
   download or use `--keep-old` in a generator input folder.
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

### Auditing Forever immunity observations

After `/reload` or logout has flushed SavedVariables, compare learned Forever
damage-over-time immunity entries with the local Classic SQL snapshot:

```powershell
python tools/audit_forever_immunity.py --classic-db "<sources>\vmangos-db-validation\extracted\sqlite-dump\mangos.sqlite"
```

By default, the tool reads Forever account SavedVariables below
`C:\Blizzard\World of Warcraft`. Supply one or more `JustAC.lua` paths after the
options to audit specific accounts, or use `--wow-root` for another installation.
The Classic snapshot is local research input, not a shipped addon database. The tool
selects the newest creature-template patch per NPC ID and compares learned spell
mechanics to the Classic mechanic-immunity mask. A mask match is only a Classic
candidate, not confirmation of Forever immunity; a missing mask is not proof that
the spell lands. The source archive used for validation is pinned outside this addon
repository at vMaNGOS `70e38cd`; verify the database dump's redistribution terms
before copying or shipping its contents.

### Auditing the hand-curated tables

`Data/*.lua` regenerates itself, but the curated tables in `SpellDB.lua` do not, so
they rot silently across patches. Run this after every CSV refresh:

```
python tools/audit_defensives.py
```

It checks `CLASS_DEFENSIVE_DEFAULTS` and `DEFENSE_TIER` for the failure mode with no
in-game symptom: an entry the player can never press. `IsSpellAvailable` hides it
forever, so it quietly consumes a queue slot and nothing says why.

For Forever's aura reads, also run `python tools/audit_forever_auras.py` (`--all` lists every
side). It maps each class ability to the aura it applies, directly or through a triggered spell,
and flags list conditions on an aura id that never appears and generated aura tables keyed by
a cast whose aura has another id (Bloodrage's rage aura is 29131). The queue's own-aura clock
reads by the cast's window, so those keys are safe there; a new reader keyed by aura id is not.

To check the queue's Forever damage estimates against real fights, run a diagnostic session,
`/reload`, then `python tools/meter_compare.py [path to JustAC.lua] [--min-casts N]`. It is
read-only: each spell's post-combat meter damage per cast beside the generated estimate, plus
fight length, damage share and measured auto-attack DPS. Listed damage assumes no spell power,
talents, crits or misses and every tick landing. Compare several classes and levels before
changing how the queue prices a spell.

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
| `gen_forever_defaults.py` | Forever CSVs, curated ability names and the generated `Forever/Rotations.lua` (run it after the rotations) | `Forever/Defaults.lua` |
| `gen_forever_rotations.py` | Forever CSVs, vendored priorities and local pins | `Forever/Rotations.lua` |
| `gen_forever_consumables.py` | Forever item/spell CSVs | `Forever/Consumables.lua` |
| `gen_aura_durations.py` | `SpellDuration` | *(retained, not shipped - durations are secret in combat)* |
| `gen_archetypes.sh` | `SpellTargetRestrictions`, `SpellEffect` (role heuristics) | `SpellArchetypes.lua` |
| `gen_simc_rotations.py` | SimC APL text + `Data/` token bridge (not a straight DB2 read) | `SimcRotations.lua` |

Curated-by-hand (no generator, no CSV): `SpellCategories.lua`,
`InterruptAbilities.lua`, `RangeReferences.lua`.

### Changing a Forever priority list

The lists are closed: the automatic queue offers nothing a tree does not name. After a list
change or a data refresh, `python tools/test_closed_lists.py` names any damaging class ability
that no tree of its class lists; add it to a list or record it in that test's `KNOWN_UNNAMED`.

Use this for guide-driven order changes, new list entries, safety gates and the Forever
interrupt/CC tables. Read [the launch guide summary](forever-guides/README.md) for the tree
first.

1. **Check that it is damage.** The queue recommends damage only, in every tree. A utility
   press a guide lists (slow, root, mitigation or threat debuff, healing, crowd control) does
   not get an entry; it goes in `NOT_DPS` or `TANK_ONLY` instead. See
   [the damage-only queue](FOREVER_ENGINE_DESIGN.md#damage-only-queue).
2. **Check for a recorded decision.** Search the tree's guide file for "default queue"
   and the existing assertions in `tools/test_forever_rotations.py`. A failing assertion may
   encode a deliberate choice (Earth Shock is reserved for interrupts; Serpent Sting opens
   with Auto Shot), not stale data. Change it only with the user's agreement.
3. **Resolve ids from the Forever data.** Names map to rank 1 through
   `check_forever_apl.class_chains(cfa.CLASS_MASK[cls])`; Forever ids differ from Retail
   (Slam 1240193, Shadow Word: Death 1309595). Check every new spell is learnable there.
4. **Edit the right layer** in `tools/gen_forever_rotations.py`:

   | Layer | Use it for |
   |---|---|
   | `EXTRA` | add, move (`move`, `all` for duplicate copies), place (`at`: front, end, `before:`/`after:` a spell, `last` for its final copy), tier-limit (`tiers`), gate (`dot`, `stealth` or a raw gate dict) or `drop` an entry |
   | `REGATE` | an existing entry's conditions: safety gates (`starved`, `health`, `near`, `execute`; `or_known` adds a talent alternative), a per-tree threshold (`at`, with `was` when the value is taken ahead of a source refresh), per-tree removals (`drop`) and per-tree additions (`add`). Prefer a row here to a new `if cls == ...` block |
   | `CORE RULES` | data-derived rules for every tree; prefer a rule here to repeated class exceptions |
   | `generalize_entries` | hand-ordered Shaman Elemental/Enhancement lists and Paladin seals; these replace `EXTRA` changes for those entries |

   A sim may list a spell twice (an AoE-only copy, a proc copy): `tier_lists` keeps one per
   context, so move every copy (`all`) or anchor on the plain one (`last`).
5. **Regenerate and check** with `python tools/forever_regen.py`. It runs
   `gen_forever_rotations.py` then `gen_forever_defaults.py` (defaults read the generated
   debuff gates to build the tracked target auras; without it a new debuff gate fails
   `test_forever_aura_policy.py` with "refresh condition without an observation route"),
   prints only the list contexts and Defaults lines that changed, runs the Forever tests and
   `tools/check.ps1` on the generated Lua. Only intended rows should change. Add an assertion
   per change to `test_forever_rotations.py`; use `--all` for every `tools/test_*.py`.
6. **Review a tree** with `python tools/forever_queue_dump.py CLASS [tree]`.
7. **Deploy** with `python tools/deploy_runtime.py --apply` and add a player note.

Interrupt and enrage-dispel tables: `Data/InterruptAbilities.lua` is shared and keyed by
Retail ids. Forever additions live in `INTERRUPTS` in `tools/gen_forever_defaults.py`;
a Retail id that is another spell on Forever goes in `INTERRUPT_REMOVE` or
`SOOTHE_REMOVE` (the rotation test derives these collisions from the data). A non-`mixed`
`ABILITY_ROLES` entry keeps an interrupt out of automatic damage queues while custom lists
can still name it.

### Comparing a Forever list offline at levelling levels

`python tools/forever_sim_bench.py --sim <simulator checkout>` (the simulator's command-line
tool is built into that checkout as `wowsimcli.exe`; `--cli` names another) converts a
generated list to the WoW Forever simulator's priority-list format, reports every gate as
exact, approximated or not expressible, and compares kill time against the simulator's own
preset and the vendored source preset on health-sized fights. It writes nothing in the
addon. The header of the file lists the build steps for the simulator, the gear setups
(`--gear behind|average|lucky|bare|file:<path>`), the assumptions and the limits. Every class
and tree with a generated list has an entry (`--class`, `--tree`). Results rank two orderings
under the same assumptions; they are not absolute damage numbers.

Per-class limits the report states and the header lists: the simulator defines rogue attacks,
feral Shred, Maul and Swipe and hunter melee attacks only at levels 25, 40, 50 and 60, so those
trees are refused at other levels; a healer tree (restoration, holy, discipline) runs its damage
list on the class's damage spec with the healer build; a hunter shoots from 30 yards with no
pet by default (`--pet <family>` adds the simulator's pet, which has level 60 stats at every
level; `--engagement melee` is the pessimistic end); a run that never finishes is stopped after
`--run-timeout` seconds, reported as failed and skipped for the rest of that level. A "known"
gate on a talent follows the build the level has; spell ranks are chosen per level and never
include the level 60 book ranks the simulator leaves out; each report lists what the simulator
defines only at its level brackets when a run is at another level. The simulator uses half the machine's
processor threads (`--threads N`) at the lowest scheduling priority, so a game in use keeps the
processor (`--normal-priority` turns that off); run one bench at a time.

Each tree runs in the stance and weapons it is played with (Protection: Defensive Stance,
one-hand weapon and shield); `--stance`, `--loadout 2h|shield|dw` and `--talents` override the
setup (`dw` wears two one-hand weapons from level 20, an assumption since the client data has
no level for Dual Wield; `--dual-wield-level` changes it). Every report has a "Can each entry be used in this setup?" section, built from the
client's `SpellShapeshift` and `SpellEquippedItems` tables, naming each entry the setup's
stance or equipment can never use. In game the queue hides an unusable entry live and the
simulator skips it too, so the section checks the setup, not the list: a core attack named
there (Revenge in Battle Stance) means the run does not describe how the tree is played. `--mobs N --pull-seconds S` fights N targets for a fixed pull and compares damage
per second; damage taken per fight is reported for every run. `--gaps=-3,-2,-1,0,1,2` replaces the
target set with one regular target per level gap. The queue's rules outside the
lists are applied per scenario: the full Sunder-style stack on an elite or higher-level
target, the slow-payoff hold, the major-cooldown hold and the dying-target and fast-fight rules
for new damage over time (`--no-runtime-rules` runs the lists alone). The class's major
cooldowns that a list does not name are cued by the queue, never shown in the first slot, so
they run as a second arm, `justac+cooldowns` (a player who presses the cue; `--no-cooldown-arm`
leaves it out). The rest of the spellbook pool is not modelled.
`--new-source DIR` runs a tree's source preset from a newer upstream `presets` folder (not yet
vendored) as the arm `source-new`, to see what a refresh would bring before doing it.
`--other-lists TREES` runs the tree's own character on other trees' lists (`list-<tree>`): what
a hybrid or early build gets when the tree with the most points is not how it plays.
`--draft FILE` runs a proposed list beside the current one: FILE is a copy of
`Data/Forever/Rotations.lua` with the change made by hand, kept outside the project data.
A setup may use every weapon type the class can learn (the client's weapon skill data) that
fits its shape, and each picked weapon names the skill it needs, since the data does not say
which skills a character starts with; `--listed-weapons` keeps to the setup's own types.
`--cooldown-gap N` tries another level gap than the runtime's three for releasing the major
cooldowns. The bench fights alone, so a list condition "in a group" (`{t="group"}`: Vanish)
reads false; `--grouped` answers it true, for what an entry kept for group play is worth there.
Nothing else about the fight changes, so this is that entry's value only, not a group fight.

`--group` is the group fight (it implies `--grouped`). Per level: a grouped regular target, a
dungeon elite one level above, a dungeon boss two above and, at 60, a raid boss three above. The
party's damage is modelled as health: each target has the player's share of it (a quarter, from
three damage dealers, a tank and a healer), so its health falls at the party's rate. A dungeon
boss has 12 times and a raid boss 5 times a regular target's health (the raid boss's already the
player's share). These numbers are ASSUMED, not measured. The tank holds the target, so it never
hits the player and melee stand behind it; a tank tree is hit as usual. A boss has no
dying-target floor, and a grouped target that is not a long fight (no elite, boss, pack or higher
level) gets the runtime's 20 second hold on damage over time. With `--mobs N`, the pull is a
grouped pack. In every scenario a cooldown of ten minutes or more (Recklessness) is pressed only
against a boss: no arm, presets included, has it for every trash fight. The simulator's autocast
of its own major cooldowns is not reached by that.

**Group pass, 2026-11-24** (client 1.60.1, `average` gear, 3 batches of 300, levels 20 to 60,
every tree):
- A grouped elite is still a long fight. Treating it as a short one (no DoT for 20 seconds, no
  stacking, no cooldowns) made elite kills up to 54% slower: priests, Combat rogue, Affliction
  and both hunters lost most. The runtime keeps the elite rule in a group.
- The 20 second DoT hold on a grouped regular target pays. Without it Shadow, Subtlety and
  Destruction killed 2 to 3 times slower; only the healer priests' damage lists gained (12 to
  24% at 40 to 60), and their mana is for healing.
- Stacking Sunder Armor as Arms or Fury on a dungeon elite is mixed (up to 20% faster or 8%
  slower without it), and it pays on every boss: no change.
- Fire: with Fireball in place of Frostfire Bolt, kills were never slower and up to 18% faster
  at 40 to 60, solo and grouped. The client's own data gives Frostfire Bolt about half
  Fireball's base damage, and its tooltip reads the same value. Applied: Fireball fills
  (forever-guides/hunter-mage-warlock.md).
- Faults found and fixed: Heating Up (400625) read as never active, because the simulator
  registers it as 44445, so Pyroblast never fired in the Fire list (the bench now maps an aura by
  the simulator's label for it); a target killed before its first swing had no kill time; and
  `--justac-only` also dropped `--without` arms.
- Packs (`--group --mobs 4`, elites one level above, a 20 second pull), each tree's AoE list
  against its single-target list: the AoE list deals 25 to 250% more from 40 in most trees, and
  never less. Equal (no AoE spell the level uses, or none listed): Affliction, Enhancement,
  Protection warrior, Survival, the priests; rogues, Feral cat and Protection paladin have no
  AoE list. Retribution's AoE list showed 7% less only because the bench pressed Holy Wrath on
  its humanoid targets, which the runtime offers only against Demons and Undead: the bench now
  leaves out every spell whose creature types (the generated CREATURE_TYPES) exclude humanoids.
- Protection paladin at 40 to 60, with Hammer of the Righteous added to the simulator (see
  forever-sim-patches): 3 to 14% faster kills than before it existed; it spends mana Seal and
  Judgement would have used, but is a net gain at every level. The preset's lead at 60 (12 to
  16%) is Holy Shield's damage, which the lists leave to the player as a tank press.
- Arcane: Arcane Blast only above a mana floor (30, 50 or 70%, Fireball below) was slower in
  every scenario but the raid boss (up to 43% on solo elites, 3 to 10% on dungeon bosses; 8%
  faster at 70% on the two and a half minute raid boss). Arcane Blast freely stays. The preset's
  lead on bosses comes from a mana gem and a Frostbolt filler timed to the fight's remaining
  length, which the queue cannot know.
- Tanks and threat (2026-11-24): the report now gives each arm's threat per second (the
  simulator's own threat), and a Protection paladin fights with Righteous Fury up (left out, its
  threat was its damage alone). The bench stacks Sunder Armor in a group as the runtime does, and
  a next-swing attack waits while another is queued. Results are in FOREVER_DPS_PRINCIPLES
  (the tank's threat), the warrior and paladin guides (Shield Block, Holy Shield).
- Sanity check of the day's lists against 6.6.0 (same runtime, `average` gear, 3 to 8 batches,
  solo and grouped at 20, 40 and 60; Feral, bear, Shadow, Retribution, both Protections,
  Marksmanship, Fire, Enhancement): equal or faster everywhere but two rows. Marksmanship on a
  grouped level 40 elite is 11% slower: the old list opened with Sniper Shot, the new one waits for
  Rapid Killing, which a fresh bench fight never has (a chain of pulls often carries it). Solo
  Enhancement on a level 60 elite is 4% slower: Flame Shock pays on that long fight, Earth Shock on
  the short ones. Both stand. The coverage sweep at 10 to 60 failed nothing and found nothing
  pressed without damage. Regenerating also refreshed Defaults.lua, which had missed Holy Shield's
  shield in Protection paladin's tree gear.
- Open: Survival's preset weaves ranged and melee (positioning, the player's); the healer
  trees' damage lists spend their mana slower than the presets by design and are not judged
  here (the bench has no healing to make room for).

Fight length is calibrated from the game: `--calibrate <path to JustAC.lua>` reads the solo
kills JustAC recorded (`/jac inspect mobprofile arm`, then play and `/reload`), simulates each
with the bench's class, tree and gear, and scales each target's health by the measured over
simulated kill time ratio at the 75% point of the kills at its level gap (interpolated between
measured gaps, the nearest measured gap outside them) (`--calibrate-quantile`; `--health-scale` sets the
factor by hand). It leans long on purpose: a fight that ends sooner than planned is the
pleasant surprise, one that runs longer is not. The records do not say
which character made a kill, so calibrate with the setup that matches the player.
`python tools/test_forever_sim_bench.py` covers these checks without the simulator.

#### What the simulator cannot be trusted for (2026-11-23 audit)

The bench needs the simulator's local changes in
[tools/forever-sim-patches](../tools/forever-sim-patches/README.md): the fight's real length, the
wand for priests and mages, every class's ranks at every level and per-level crit rates.
`python tools/forever_sim_sweep.py --sim <checkout>` is the coverage check: per class, tree and
level (5 to 30 by default) it says which learned list entries the simulator pressed, never
pressed, or does not have. Run it after any simulator or list change; a comparison of two lists
means nothing at a level where the entries they differ in are missing. It also lists any spell
whose simulated damage per cast is far from the client's spell data. 2026-11-23: 46 of 168
tree-levels failed before the rank changes, 1 of 164 after (the enhancement shaman at level 5),
with nothing flagged by the damage check. 2026-11-24 at levels 10 to 40: 1 of 111 fails (Protection paladin at 40: the simulator has no Hammer of the Righteous); the damage check flagged Chain Lightning (a stale simulator table, fixed) and level 40 warlock spells whose crits double (Ruin, Pandemic), which are not faults. The sweep also lists any action pressed over and over for no damage, which found Faerie Fire recast every global cooldown (a bench aura-id fault, fixed). At 50 and 60: 2 of 56 fail (the same Hammer of the Righteous gap, since added: Protection passes at 40 to 60, and the damage check's flag on it is its weapon-based damage, whose client value is a placeholder 1); the damage check's high flags there come from gear spell power and crit talents (the check leaves spell power out), not from wrong tables. Pet stats by level come from the Classic server table
the simulator's own rows were taken from; no WoW Forever pet damage has been measured in game. Every report says which kill time clock it used; a report on the
target-swing clock is from an unpatched build and runs slow under Thunder Clap. Results before
2026-11-23 used that clock, and priest and mage results before that date had no wand at all.

Read the model's code, not run it, for these limits. Each is a reason a result may not carry
over to the game:

| Limit | What it biases |
|---|---|
| Every fight starts rested: full mana and health, every cooldown ready, no sequence of fights, no drinking | Mana-heavy lists pay nothing for downtime; a 3 to 10 minute cooldown is worth a full use every fight. Do not judge mana conservation or long cooldowns from it |
| The player cannot die | A slower list that survives and a faster one that would die look alike; read damage taken per fight |
| The last hit's overkill is counted as damage | Damage per second flatters large hits; compare kill times |
| Pulls: with the pull model (on by default) a fight starts when the first attack lands, the target then runs to a caster and a pet runs to the target, all at an assumed 7 yards a second. No kiting, fleeing or mob casting. `--no-pull-model` gives the simulator's own start, the target swinging from time zero | Matched six logged level 15 hunter fights (kill time and the hunter and pet damage split). A caster's time before it is hit depends on the assumed speed and on standing 20 yards away |
| The weapon stage (the queue's wand-or-cast rule) is applied from paper damage: a single-target cast-time spell without damage over time is pressed over the wand only while its client damage per second, its cast pushed back by the expected hits, beats the wand's; before the target arrives it is weighed unhindered. Wand Specialization (13% a rank) counts, and priest and mage levelling builds take it first, as the guides do. Spell power, crit and the mana margin are not in the comparison; `--no-weapon-rule` runs the list as written | A level 13 priest went from 20.9 s to 15.8 s; about 10 s is logged in game with a better wand and talents than the generated setup, so prefer a character file (`--gear file:`) |
| Targets are immune to stuns, roots and slows (most classes do not even apply them) | Charge, Intercept and stuns are worth nothing; damage taken is overstated for them |
| Elites: health x3 matches the simulator's planner; damage x1.5 has no source | Warrior and bear rage from damage taken, so their elite kill times |
| Packs: every target attacks for the whole pull and none dies; area damage counts in full on each | Area attacks and late-pull damage taken are overstated |
| Calibration scales target health to match recorded kill times. A recorded kill also holds multi-mob pulls (area damage split between targets) and chases after fleeing mobs | Dead time in the game (the run to the target, travel time, a chase) becomes extra health: more casts, more mana, more value for damage over time. 2026-11-23, 88 solo warrior kills at 14 to 16: recorded kills ran 17% longer than simulated (median), 1.6 to 1.8 times for mobs two or three levels below |
| One stance for the whole fight (the tree's own, or `--stance`); no stance swaps | Protection is simulated in Defensive Stance, so Revenge is always available; logged level 15 to 16 Protection play spent 26 to 56% of samples there and pressed Revenge about half as often. Battle Stance (no Revenge) simulated 5% slower |
| Upstream, rogue attacks, feral Maul, Shred, Swipe and Claw, hunter melee and pet abilities and warlock demons exist at 25, 40, 50 and 60 only, and crit per agility and intellect is the level 60 rate. The local changes fix these from client data; rogue poisons, Mutilate and shaman imbues are still bracket-only, and the simulator has no Shank, Cheap Shot, Victory Rush, Bash, Pounce or Ravage | A run on an unpatched simulator; the listed abilities |
| Priest Spirit Tap never triggers; warlock Life Tap costs no health; caster staff swings are missing; weapon skill is always full for the level | Priest and warlock mana, and weapon versus spell comparisons |
| Hunter pet and warlock demon stats by level are Classic server data (the table the simulator's own rows come from), not measured on WoW Forever | Any run with a pet |
| Warrior: flat rage per swing, glancing damage and the swing reset after a cast are provisional | Heroic Strike against white swings |

How the bench covers the [core principles](FOREVER_DPS_PRINCIPLES.md#core-principles):

| Principle | Covered | Not covered |
|---|---|---|
| Damage only | Lists run as generated | |
| Confirmed signals and inference | Every gate reported exact, approximated or not expressible; the stacking, slow-payoff hold and DoT health rules applied per scenario | The weapon filler and pushback stages, On the Move, the multi-minute self-buff hold, group rules; the fast-fight rule cannot tell a renewal from a first application |
| Damage now, in this context | Range by engagement; usability by stance and equipment | Movement and kiting (no movement model) |
| Player owns strategy | Talents and gear from `--gear file:` or `--talents` | |
| Reliable before peak | Targets below, even, above, elite and health multiples; gear points; levels; health calibrated from recorded kills | Elite factors are assumed; calibration rests on the kills recorded so far |
| Easy to follow, stable output | | The simulator presses instantly and never thrashes; flip rate needs the in-game capture |
| Simplicity margins | Ablation arms (`--without`) | Margins are applied by hand from the report |
| Class and build fit | Stance, weapons (two-hand, shield or dual wield) and talents per tree | Only warrior and warlock; Victory Rush, Reckless Swings and racials are not in the simulator; its Shield Block is not castable from a list |

`/jac inspect character` (out of combat) shows the current character as JSON in a copy box:
class, race, level, highest known ranks, talents as trait node, entry and rank, and
equipped items with the raw item string. Save it as a `.json` file and pass it with
`--gear file:<path>` to run the comparison on that character. The item string split and
the talent read follow the Forever client's own source and API documentation and have not
yet been confirmed against a live character; check the first export by eye.
`python tools/test_character_export.py` covers the export with stubbed client values.

## Source and enum mirrors

Root: `<sources>\`, **outside** the addon repo.
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

**Refresh:** `<sources>\update-sources.ps1` fetches and
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
it does not sync JustAC. With the shared junction layout, the standing runtime
sync instead runs it once against the shared runtime root as described below.
Enable the companion in the addon list; a newly installed addon may require
restarting the client.
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

### Behavior baseline and the analyzer

The routine loop for catching behavior changes early, on either client:

1. `/jac inspect start`, play normally, `/jac inspect stop`, `/reload`.
2. `python tools\analyze_probe.py`

The default session records every diagnostic key and event row plus the
change-only audit samplers (edges, DoTs, aura routes, curses), without the audit
battery's aura sweeps, for up to 20 minutes. `/jac inspect start full` adds the
battery for 10 minutes; it fills the rolling log quickly.

The analyzer reads the latest session of every client under
`C:\Blizzard\World of Warcraft` (override with `--wow-root`, `JUSTAC_WOW_ROOT`, or
explicit SavedVariables paths) and builds a qualitative fingerprint: for each key,
in and out of combat, which read classes occurred (plain, secret, err, nil, and the
inner status of research cells), the status of each named field, which event row
kinds appeared, question control counts, contradictions and tallies. It compares
that with the client's saved baseline in `.probe-baselines\` (git-ignored) and
lists differences first:

- **CHANGED**: a secret or error read, contradiction, sampler failure, probe error
  row or tally category that the baseline never had.
- **LOST**: plain reads, keys or fields the baseline had and this session lacks.
  Key presence is only compared when both sessions kept their BASELINE sample.
- **NOT SEEN**: a control or row kind seen in the baseline did not occur. This may
  just mean the situation was not played.
- Informational differences (build and version changes, unknown/unavailable shifts)
  are counted; `--info` lists them. Combat behavior is compared only after at least
  30 seconds of combat.

Review a capture, then make it the baseline with `--accept`. A session without a
STOP row, or whose BASELINE sample was evicted, is refused. The replaced baseline
is kept as `<client>.prev.json`. Other options: `--details` (every control and
check), `--all`, `--session <id>`, `--question <id>` and `--json`.

Research questions in `Debug\Research\Questions.lua` give the fingerprint its
consistency checks. Each lists the keys it needs, the in-combat controls that must
occur, and checks that can contradict a signal without reconstructing a hidden
value. A check can cite captured evidence: for example, an execute latch released
right after a completed target cast is reported as explained, not contradicted.
**CONTROLS MET** means the required transitions occurred with no contradiction: a
candidate for adoption review, not proof. Optional extras:

- `/jac inspect questions` lists the questions and their controls.
- `/jac inspect start <id>` records one question's keys and rows only.
- `/jac inspect mark <label>` timestamps a control the probe cannot observe,
  such as crowd control landing. Bind it to a macro. Mark checks with
  `scope="combat"` look across the whole fight containing the mark, or the next
  fight starting within 15 seconds, so a mark typed just before a pull still counts.
- Question patterns of the form `name=value` match that whole field (`count=0`
  never matches `count=05`); other patterns are plain substrings. List values are
  separated by `,` in the log (`|` collides with WoW colour codes, which the log strips).

### One probe, added to and taken from

There is one capture: `/jac inspect start`, the standard session. A targeted check is not a
new probe or a new command. It is a read or an evidence row added to the Research companion
(`Debug/Research/`), which the standard session then records with everything else; when the
question is answered the addition comes out again, unless `/jac inspect validate` does not
yet cover the technique it relies on. A question in `Questions.lua` names which rows and
checks answer it, for scoring; it is not needed to record them. `start <question>` only
narrows a capture to that question's rows. `start full` adds the audit snapshots at the
baseline and combat edges and, on Forever, the event recorder. `/jac inspect audit` and
`/jac inspect forever arm|off|toggle` are that same session under older names, kept for macros
and earlier test plans; they start no recorder of their own.

### Keeping captures

The capture log is one rolling log, and it favours detail: up to 120,000 rows with the Research
companion (30,000 without), and when the limit is reached only the oldest tenth goes. Rows of
one evidence kind are capped per combat phase at 2,000 (6,000 for first-slot changes) as a
runaway guard. The standard session also runs the change-only loggers into the same log:
maintenance transitions (`MAINT` rows), the between-pulls heal reminder (`TOPOFF`), enrage
detections (`ENR`) and, where the game supplies a pick, that pick with the facts beside it
(`PICK`). It also arms the mob and pet profiles, which keep their own tables for the offline
simulator. Their commands still switch one by hand. In full mode the audit snapshots bring the
loss-of-control and own-cast captures with them. What stays a command of its own needs an
argument or draws on screen: `windowsig <spell>`, `chargediag [spell]`, `castdiag` (waits for a
caster), `healprobe`, `healthgate`, `enrage`, `identity`.

`python tools\archive_probe.py` copies every session out of the rolling log into
`.probe-archive/<client>/<session id>.lua`, one file per session, for review later. Each file
opens with the context needed to read it cold: client, mode and question, the JustAC version,
the game build, the character, when its source was written, and the build stamp. The stamp is
written at every `deploy_runtime.py --apply` into the Research companion (deploy time, commit
and whether the checkout had uncommitted changes) and each session logs it as a
`DIAGNOSTICS BUILD` row. An archived file has the shape of the saved file, so
`python tools\analyze_probe.py <file>` reads it as it reads the live one; `--list` shows what is
kept. Archiving again skips sessions already kept unless the live copy has grown. The archive
is per machine and not committed. Tests: `python tools\test_archive_probe.py`.

### Queue stability capture

The `stability` question measures the
[stable output principle](FOREVER_DPS_PRINCIPLES.md#stable-followable-output): how often
the main queue's first slot changes, against the player's own presses.

1. `/jac inspect start` (or `start stability` to record only this), then fight several normal mobs and one pack with your
   usual buttons, including some moving in combat and a cast-time spell if you have one.
2. `/jac inspect stop`, `/reload`.
3. `python tools\analyze_probe.py --question stability --details`

It records an `EVIDENCE flip` row for every slot-1 change, observed about every 0.03 seconds
in the standard session and in this focused one (up to 600 rows per combat phase): from, to, the gap since
the previous change, `back=true` when it returned to the value before the previous change
within 1.5 seconds, cast state, global cooldown left, moving, seconds since the last own cast
send and the queue stages active at the time (`stage`, `ctx`). It also carries the list
tier and enemy count, the context values that changed within 0.15 seconds before it
(`changed`: the tier, enemy count, melee range, dying target, execute, On the Move, fast or
short fight, low-value target) and from those its `cause`: `context` when one did, `press`
when it follows your own cast send within 0.4 seconds, otherwise `queue` (a cost met or lost,
a cooldown ending, a proc). `pair` is the change itself, for ranking, and `enemyStep` is how far
the enemy count moved in one step when it did (`-1` is an enemy dying; `-4` at once is more
likely nameplates leaving the screen). Each own cast send adds an
`event=press` row with whether the player pressed the shown first slot (`match`). The checks
report flips per press (the `ratio` check kind), the gap distribution, the straight-back share
and tallies by cast state, stage, movement, cause, changed context value and tier, with the
causes and pairs of the straight-back flips and the pairs the queue flipped on its own. The aim is about one change per press.

**First-slot hold (trial).** `SpellQueue._StageLeadHold` keeps the shown first slot until a
challenger has led for a set time, released at once by the player's own cast, a new target, a
proc on the challenger or the shown entry leaving the queue. It is off unless
`profile.leadHoldSeconds` is a positive number, so the same character can be captured with and
without it; a held build shows as `leadHeld` in the flip rows' `ctx`. Switch it for a trial with
`/run LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat").db.profile.leadHoldSeconds = 0.2`
(`= nil` turns it off). It becomes a default, or is removed, on the capture's evidence.
Tests: `python tools\test_lead_hold.py`.

Every session writes its definitions, key list, mode and start/stop rows into the
log, and `DIAG` headers carry game time and the target epoch, so a capture is scored
against the registry that produced it. Captures from before this harness are scored
against the current registry, with epochs and the game clock inferred, and labeled
as such. Tests: `python tools\test_analyze_probe.py`.

## Runtime test sync

Local runtime syncing has standing authorization after every validated runtime
update, including fixes, cleanup and generated-data changes. Do not wait for a
separate sync request or leave one test client on older code.

### Current local layout

| Purpose | Location |
|---|---|
| Git checkout, development tools/docs and ignored Research sources | `<sources>\JustAC` |
| Shared core runtime | `<sources>\JustAC-runtime\JustAC` |
| Separate local Research companion runtime | `<sources>\JustAC-runtime\JustAC_Research` |
| Pre-migration snapshots and hash manifest | `<sources>\JustAC-local-backups\20261113-1134` |

Both clients' `Interface\AddOns\JustAC` directories are junctions to the shared
core runtime. Both sibling `JustAC_Research` directories are junctions to the
separate companion runtime. Research is not embedded in the core runtime.
SavedVariables and addon enablement remain client-specific in each client's
`WTF` directory; junctions do not share settings or captures.

### Validate, deploy, verify

- The local development checkout is
  `<sources>\JustAC`. Run tests and edit sources there, not through
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
- `python tools/deploy_runtime.py` plans and `--apply` performs the steps below: it copies
  differing TOC/XML-closure files and other files the runtime shares with the checkout,
  never deletes, reports runtime-only files, verifies every compared runtime file against the
  checkout by SHA-256, checks that each client path is a junction to that runtime, and
  refreshes and verifies the Research companion in both clients. Investigate any reported problem rather than forcing it.
- Verify junction type/target and the complete runtime inventory and SHA-256
  contents against the validated checkout, then verify both client paths. Comparing
  the two junctions alone cannot detect a stale shared target. Resolve active TOC
  entries and XML Include/Script dependencies on both, ignoring commented-out
  entries. Version labels alone are insufficient. On Windows, inspect `LinkType`
  and `Target` with `Get-Item -Force -LiteralPath`; `Resolve-Path` can return the
  junction path itself rather than its target.
- Keep the local research companion current in both clients too. For a completed
  junction deployment with local `Debug\Research\` sources, run
  the following from the development checkout:

  ```powershell
  .\tools\install_research.ps1 -AddOnsPath '<sources>\JustAC-runtime'
  ```

  This refreshes the separate shared companion visible to both clients. Verify
  each sibling `JustAC_Research` junction and compare the Lua files and LICENSE
  to their sources by SHA-256. The installer writes the companion TOC using the
  core TOC's Interface field, so verify its resulting contents against the source
  TOC with that substitution rather than assuming byte-identical TOCs. The
  companion stays local-only: never commit it or add it to a release package.
  For ordinary client directories, run the installer for each client's AddOns
  directory instead.
- Report parity or any blocker. Syncing files does not reload a running client;
  in-game testing needs a reload, or a restart when required for new addon discovery.
- Keep full pre-migration backups outside AddOns under
  `<sources>\JustAC-local-backups`. Do not put a backup containing
  an active TOC beside installed addons.

### Changing or restoring the layout

Before replacing directories or junctions, back up the complete installations,
including hidden Git files and ignored local Research sources, and verify hashes.
Keep displaced originals outside `AddOns` as well; do not assume a renamed folder
there is a safe long-term backup or delete it without verifying its contents.
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
