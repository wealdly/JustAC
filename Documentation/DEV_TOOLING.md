# Development tooling

Reference for the local tools this repo expects, and how to install them if
they are missing. None of this ships to players - `.pkgmeta` excludes `tools/`,
`Documentation/`, and `.luacheckrc` from the CurseForge package.

## Lua static analysis (the pre-commit / pre-reload gate)

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

**Baseline:** see AGENTS.md - it carries the current warning count so there is one
number to keep correct.

"Did my change break something" = run the gate on your files and confirm no
**errors** and no **new** warnings versus that baseline.

### luaparser (fallback)

Syntax-only (no undefined-global analysis). Pure Python, useful if the luacheck
binary isn't present. Needs:

```
python -m pip install luaparser
```

`check.ps1` uses it automatically when `luacheck.exe` is absent; or run directly:
`python tools/luasyntax.py <file.lua> ...`

## Data-generation tools (`tools/*.py`, `tools/*.sh`)

The curated spell data under `Data/` is generated from wago.tools CSV exports by
the `gen_*.py` / `update_data.py` scripts here. They require Python and a local
CSV export; see the top of each script. Only the generated `Data/*.lua` output is
committed, not the multi-MB source CSVs.

### Updating the CSVs

`python tools/update_data.py [build] [--product wow|wowt]` does the whole cycle:
pull the latest DB2 build for every table already present, diff row counts, swap
the folder atomically, rerun every generator, and print `git diff --stat Data/`.
The table set is **self-maintaining** - whatever `<Table>.<build>.csv` files sit
in `Documentation/wow_spell_csv/` (gitignored) define what gets pulled. To track a
new table, download it once by hand from
`https://wago.tools/db2/<Table>/csv?build=<build>` and re-run. Keep the folder on
**one build**; generators join across tables. Full flag list: the header of
`tools/update_data.py`.

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
with worked examples in the script's own header — `python tools/audit_defensives.py --help`.

Note this check does **not** transfer to `Data/SimcRotations.lua`. Unobtainable ids
are correct there: SimC names the button you actually press, so override forms
(`death_sweep`, `swipe_cat`, `templar_slash`) are what match Assisted Combat's live
pick. Rewriting those to base ids would break the matching.

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
| `gen_aura_durations.py` | `SpellDuration` | *(retained, not shipped - durations are secret in combat)* |
| `gen_archetypes.sh` | `SpellTargetRestrictions`, `SpellEffect` (role heuristics) | `SpellArchetypes.lua` |
| `gen_simc_rotations.py` | SimC APL text + `Data/` token bridge (not a straight DB2 read) | `SimcRotations.lua` |

Curated-by-hand (no generator, no CSV): `SpellCategories.lua`,
`InterruptAbilities.lua`, `RangeReferences.lua`.

## Source & enum mirrors (`R:\WOW\00-SOURCE\`)

Dev-local, **outside** the addon repo. Two sparse GitHub mirrors are the ground
truth for "how does this API actually behave" (see AGENTS.md rule: never guess a
WoW API):

- **`wow-ui-source`** (branch `live`) - Blizzard's own UI Lua. The generated API
  surface lives at
  `wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`, e.g.
  `AssistedCombatDocumentation.lua`, `Secret*Documentation.lua` (secret-value
  predicates), `Spell*Documentation.lua`.
- **`WowPacketParser`** (branch `master`) - server enum values at
  `WowPacketParser/WowPacketParser/Enums/*.cs`, e.g. `PowerType.cs`.

**Refresh both:** `.\00-SOURCE\update-sources.ps1` (depth-1 fetch + hard reset per
mirror). Build-immutable, so it is cheap to run once per patch.

**Looking something up** (grep the mirror instead of guessing):

```
# an API method or return field
grep -ri "GetSpellCooldown" 00-SOURCE/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated
# secret-value predicates (Should*BeSecret, etc.)
grep -ri "ShouldUnitHealth" 00-SOURCE/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated
# an enum's numeric values
grep -ri "PowerType" 00-SOURCE/WowPacketParser/WowPacketParser/Enums
```
