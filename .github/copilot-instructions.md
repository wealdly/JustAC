# JustAC - AI Agent Instructions

WoW addon displaying Blizzard's Assisted Combat suggestions with keybinds. Lua + WoW API + Ace3.

## Version Detection & Compatibility

**WoW 12.0 (Midnight) compatibility layer ready** - Use version conditionals for breaking API changes:

```lua
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Check version
if BlizzardAPI.IsMidnightOrLater() then
    -- 12.0+ code path (new/fixed API)
else
    -- Pre-12.0 code path (original API)
end
```

**When to add version conditionals:**
- 12.0 error reported → Add conditional fix
- API behavior changes between versions → Wrap in version check
- New API replaces old → Keep both paths with version guard

**See:** `Documentation/VERSION_CONDITIONALS.md` for detailed patterns and examples

## Critical Workflow

1. **NEVER guess WoW API behavior** — Verify with `/script` commands in-game or check `R:\WOW\00-SOURCE\WowUISource`
2. **Propose before implementing** — Describe changes, ask "Should I proceed?"
3. **Test with debug commands** — Use `/jac test`, `/jac modules`, `/jac formcheck` to validate changes
4. **DO NOT auto-increment versions** — Track changes in `UNRELEASED.md`, only bump version on explicit instruction
5. **DO NOT auto-build or push** — Commit changes, let user build/push manually

## Architecture (Load Order Matters)

10 LibStub modules in `JustAC.toc` — **MUST edit in dependency order**:

```
BlizzardAPI → FormCache → MacroParser → ActionBarScanner → RedundancyFilter
                                    ↓
                              SpellQueue → UIManager → DebugCommands → Options → JustAC
```

| Module | Role | Key Exports | Current Version |
|--------|------|-------------|-----------------|
| `Locale.lua` | AceLocale-3.0 localization (6 languages) | `L` global | N/A (not LibStub) |
| `BlizzardAPI.lua` | `C_AssistedCombat` wrappers, profile access | `GetProfile()`, `GetSpellInfo()` | v14 |
| `FormCache.lua` | Shapeshift form state (Druid/Rogue/etc) | `GetActiveForm()`, `GetFormIDBySpellID()` | v5 |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` conditional parsing | `GetMacroSpellInfo()`, quality scoring | v19 |
| `ActionBarScanner.lua` | Spell→keybind lookup, slot caching | `GetSpellHotkey()`, `FindSpellInSlots()` | v29 |
| `RedundancyFilter.lua` | Hide active buffs/forms | `IsSpellRedundant()` | N/A |
| `SpellQueue.lua` | Throttled spell queue, proc detection | `GetCurrentSpellQueue()`, blacklist | v24 |
| `UIManager.lua` | Icon rendering + glows, Masque integration | `RenderSpellQueue()`, frame management | v12 |
| `DebugCommands.lua` | In-game diagnostics | `/jac test`, `/jac modules` | v1 |
| `Options.lua` | AceConfig UI panel | Settings registration | N/A |
| `JustAC.lua` | Core addon, events, defensive cooldowns | `OnInitialize()`, `OnUpdate()` | N/A (main addon) |

## Required Patterns

### Module Access (ALWAYS use this pattern)
```lua
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
if not BlizzardAPI then return end

local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
if not addon or not addon.db then return end
```

### Hot Path Optimization (top of each file)
```lua
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
```

### Critical API Gotcha — MUST filter "assistedcombat" string
```lua
-- GetActionInfo(slot) may return "assistedcombat" as ID — causes crashes if not filtered
-- BlizzardAPI.GetActionInfo() handles this automatically
if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then return nil end
```

## Code Standards

- **4 spaces** indentation, **camelCase** variables, **UPPER_SNAKE** constants
- **Early returns** over nesting (max 3 levels)
- **pcall()** all WoW APIs that can fail
- **All variables local** except `JustAC` global table
- **Increment LibStub version** on breaking changes: `LibStub:NewLibrary("JustAC-Module", VERSION)`

## Cache Patterns

| Pattern | Usage | Example |
|---------|-------|---------|
| Throttled | `if now - lastUpdate < interval then return cached` | SpellQueue (0.1s combat) |
| State hash | `hash = page + bonusOffset*100 + form*10000` | ActionBarScanner |
| Event-driven | Clear on `ACTIONBAR_SLOT_CHANGED` | ActionBarScanner |
| Time-based | `if now - lastFlush > 30 then wipe(cache)` | MacroParser |

## Event→Cache Invalidation Map

| Event | Invalidates |
|-------|-------------|
| `UPDATE_SHAPESHIFT_FORM` | MacroParser, ActionBarScanner, FormCache |
| `ACTIONBAR_SLOT_CHANGED` | ActionBarScanner slot cache |
| `UPDATE_BINDINGS` | Binding cache (0.2s debounce) |
| `SPELL_ACTIVATION_OVERLAY_GLOW_*` | Immediate UI refresh |

## Debug Commands

```
/jac test       — API diagnostics
/jac modules    — Module health check  
/jac formcheck  — Form detection debug
/jac find Name  — Locate spell on action bars
```

## Defensive Spell System

Two-tier health thresholds in `JustAC.lua`:
- `CLASS_SELFHEAL_DEFAULTS` — 80% threshold, quick heals
- `CLASS_COOLDOWN_DEFAULTS` — 60% threshold, major defensives

## 12.0 Compatibility

Safe APIs: `C_AssistedCombat.*`, `GetBindingKey()`, `C_Spell.GetSpellInfo()`
Secret handling: `BlizzardAPI.IsSecretValue()` — fail-open design (shows extra, never hides valid)

## Reference Docs

- `Documentation/STYLE_GUIDE_JUSTAC.md` — Full coding conventions (843 lines)
- `Documentation/ASSISTED_COMBAT_API_DEEP_DIVE.md` — C_AssistedCombat reference (717 lines)
- `Documentation/MACRO_PARSING_DEEP_DIVE.md` — Macro conditional parsing (904 lines)
- `Documentation/12.0_COMPATIBILITY.md` — API compatibility notes
- `README.md` — User-facing docs, installation, credits
- `CHANGELOG.md` — Release history (GPL-3.0-or-later since v2.95)

## Build & Release

PowerShell script `build.ps1` creates distributable package:
- Extracts version from `JustAC.toc` (currently 3.10)
- Packages core `.lua` files + `Libs/` folder
- Removes duplicate nested lib folders (common packaging error)
- Creates `dist/JustAC-<version>.zip` ready for CurseForge/GitHub

**Workflow:**
1. Make changes and commit them
2. Update `UNRELEASED.md` with change notes
3. When user requests version bump:
   - Move UNRELEASED changes to CHANGELOG.md
   - Increment version in JustAC.toc
   - Update library versions if breaking changes
   - Clear UNRELEASED.md
   - Commit version bump
4. User runs `.\build.ps1` when ready to test
5. User runs `git push` when ready to deploy

**Before release:** Test with `/jac modules` + in-game rotation to verify all modules loaded.
