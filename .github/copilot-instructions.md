# JustAC - AI Agent Instructions

WoW addon displaying Blizzard's Assisted Combat suggestions with keybinds. Lua + WoW API + Ace3.

## Critical Workflow

1. **NEVER guess WoW API behavior** — Verify with `/script` commands in-game first
2. **Propose before implementing** — Describe changes, ask "Should I proceed?"
3. **Blizzard source reference**: `R:\WOW\00-SOURCE\WowUISource` when needed

## Architecture (Load Order Matters)

10 LibStub modules in `JustAC.toc` — edit in dependency order:

```
BlizzardAPI → FormCache → MacroParser → ActionBarScanner → RedundancyFilter
                                    ↓
                              SpellQueue → UIManager → DebugCommands → Options → JustAC
```

| Module | Role | Key Exports |
|--------|------|-------------|
| `BlizzardAPI.lua` | `C_AssistedCombat` wrappers, profile access | `GetProfile()`, `GetSpellInfo()` |
| `FormCache.lua` | Shapeshift form state | `GetActiveForm()`, `GetFormIDBySpellID()` |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` parsing | `GetMacroSpellInfo()` |
| `ActionBarScanner.lua` | Spell→keybind lookup | `GetSpellHotkey()` |
| `RedundancyFilter.lua` | Hide active buffs/forms | `IsSpellRedundant()` |
| `SpellQueue.lua` | Throttled spell queue | `GetCurrentSpellQueue()` |
| `UIManager.lua` | Icon rendering + glows | `RenderSpellQueue()` |
| `JustAC.lua` | Core addon, events, defensives | `OnInitialize()`, `OnUpdate()` |

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

- `Documentation/STYLE_GUIDE_JUSTAC.md` — Full coding conventions
- `Documentation/ASSISTED_COMBAT_API_DEEP_DIVE.md` — C_AssistedCombat reference
- `Documentation/MACRO_PARSING_DEEP_DIVE.md` — Macro conditional parsing
