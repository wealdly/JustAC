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

**Baseline:** a clean tree currently reports **~47 warnings / 0 errors**. Those
are pre-existing unused-locals and two known items worth a look but out of scope
for routine changes:
- `UI/UIRenderer.lua` references `C_Spell_GetSpellCooldown` as a bare global
  (never declared `local` in that file) - that branch is dead. Intentionally left
  un-whitelisted so it stays visible.

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
