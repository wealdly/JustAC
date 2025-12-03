# JustAC - AI Agent Instructions

WoW addon displaying Blizzard's Assisted Combat spell suggestions with keybinds. Lua + WoW API + Ace3 libraries.

## Critical Workflow

1. **NEVER guess WoW API behavior** - Use `/script` commands in-game to verify API responses first
2. **Propose before implementing** - Describe changes, ask "Should I proceed?", wait for confirmation
3. **WoW Source Reference**: `R:\WOW\00-SOURCE\WowUISource` for Blizzard UI source when needed

## Architecture

10 LibStub modules in `JustAC.toc` load order (dependencies matter):

| Module | Purpose | Key Functions |
|--------|---------|--------------|
| `BlizzardAPI.lua` | `C_AssistedCombat` wrappers, shared profile access | `GetProfile()`, `GetDebugMode()`, `GetSpellInfo()` |
| `FormCache.lua` | Shapeshift form caching, spell→form mapping | `GetActiveForm()`, `GetFormIDBySpellID()` |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` conditionals | `ParseMacroForSpell()`, 30s cache TTL |
| `ActionBarScanner.lua` | Spell→keybind mapping via state hashing | `GetSpellHotkey()`, hash = page+bonus+form |
| `RedundancyFilter.lua` | Hide active buffs/forms/pets | Uses LibPlayerSpells-1.0 |
| `SpellQueue.lua` | Throttled queue (0.03s combat/0.08s OOC) | `GetCurrentSpellQueue()`, blacklist |
| `UIManager.lua` | Icon rendering with LibCustomGlow | `FreezeAllGlows()`, `UnfreezeAllGlows()` |
| `DebugCommands.lua` | `/jac` slash commands | `ModuleDiagnostics()`, `FormDetection()` |
| `Options.lua` | AceConfig-3.0 options UI | `UpdateBlacklistOptions()` |
| `JustAC.lua` | Core (Ace3 init, events, defensives) | `OnInitialize()`, `OnUpdate()` |

## Data Flow (Critical Path)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ OnUpdate (0.03s combat / 0.15s OOC) or Event-driven trigger            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ SpellQueue.GetCurrentSpellQueue()                                        │
│  ├─ BlizzardAPI.GetNextCastSpell() → Primary spell (position 1)         │
│  ├─ BlizzardAPI.GetRotationSpells() → Queue spells (positions 2+)       │
│  ├─ C_Spell.GetOverrideSpell() → Resolve morphed spells                 │
│  ├─ SpellQueue.IsSpellBlacklisted() → Filter user-blocked spells        │
│  ├─ BlizzardAPI.IsSpellAvailable() → Filter passive/unavailable         │
│  └─ RedundancyFilter.IsSpellRedundant() → Filter active buffs/forms     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ UIManager.RenderSpellQueue(spellIDs)                                     │
│  ├─ For each spellID:                                                   │
│  │   ├─ BlizzardAPI.GetSpellInfo() → icon, name                         │
│  │   ├─ ActionBarScanner.GetSpellHotkey() → keybind text                │
│  │   │   ├─ FindSpellInActions() → locate spell on action bars          │
│  │   │   ├─ MacroParser.GetMacroSpellInfo() → parse macro conditionals  │
│  │   │   │   └─ FormCache.GetActiveForm() → [form:X] matching           │
│  │   │   └─ GetBindingKey() → raw keybind lookup                        │
│  │   └─ StartAssistedGlow() → LibCustomGlow visual effects              │
│  └─ Position 1 gets firstIconScale (1.4x default)                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Access Pattern (ALWAYS use)

```lua
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
if not BlizzardAPI then return end

local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
if not addon or not addon.db then return end
```

## Key API Behaviors

```lua
C_AssistedCombat.GetNextCastSpell(true)  -- returns spellID > 0 or nil
C_AssistedCombat.GetRotationSpells()     -- returns {spellID, ...} or nil
GetActionInfo(slot)                       -- CRITICAL: may return "assistedcombat" string - MUST filter
GetShapeshiftFormID()                     -- returns nil for caster form, 1-N for forms
```

**assistedcombat filter** (handled automatically by `BlizzardAPI.GetActionInfo`):
```lua
if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then return nil end
```

## Event-Driven Updates (JustAC.lua)

| Event | Handler | Invalidates |
|-------|---------|-------------|
| `ACTIONBAR_SLOT_CHANGED` | `OnActionBarChanged` | ActionBarScanner slot cache |
| `UPDATE_BINDINGS` | `OnBindingsUpdated` | Binding cache (0.2s debounce) |
| `UPDATE_SHAPESHIFT_FORM` | `OnShapeshiftFormChanged` | MacroParser, ActionBarScanner |
| `UNIT_PET` (player) | `OnPetChanged` | RedundancyFilter cache |
| `UNIT_AURA` (player) | `OnUnitAura` | ActionBarScanner (0.5s throttle) |
| `SPELL_ACTIVATION_OVERLAY_GLOW_*` | `OnProcGlowChange` | Immediate refresh |
| `PLAYER_TARGET_CHANGED` | `OnTargetChanged` | MacroParser cache |
| `UNIT_SPELLCAST_SUCCEEDED` | `OnSpellcastSucceeded` | 0.02s delayed refresh |
| `UNIT_HEALTH` (player) | `OnHealthChanged` | Defensive icon |

## Code Standards

- **Early returns** over deep nesting (max 3 levels)
- **pcall()** all WoW APIs that can fail
- **All variables local** except `JustAC` table
- **4 spaces** indentation, **camelCase** variables
- LibStub versions: increment on breaking changes

## Cache Invalidation Patterns

| Pattern | Example | Used In |
|---------|---------|---------|
| Throttled | `if now - lastUpdate < interval then return cached end` | SpellQueue |
| State hash | `hash = page + (bonusOffset * 100) + (form * 10000)` | ActionBarScanner |
| Event-driven | `ACTIONBAR_SLOT_CHANGED` → rebuild | ActionBarScanner |
| Time-based | `if now - lastFlush > 30 then wipe(cache) end` | MacroParser |

## Debug Commands

```
/jac test        -- API diagnostics
/jac modules     -- Module health check
/jac formcheck   -- Form detection debug
/jac find <name> -- Locate spell on action bars
/jac lps <id>    -- LibPlayerSpells info
```

## Macro Conditional Parsing (MacroParser.lua)

**Purpose**: Find spells in macros and determine if conditionals match current state.

### Key Functions

| Function | Purpose | Returns |
|----------|---------|---------|
| `GetMacroSpellInfo(slot, spellID, spellName)` | Main entry point for ActionBarScanner | `{found, modifiers, forms, qualityScore}` |
| `ParseMacroForSpell(body, spellID, spellName)` | Parse macro body for spell match | `found, modifiers` |
| `EvaluateConditions(conditionString, spec, form)` | Check if `[mod]`, `[form]`, etc. match | `allMet, modifiers, formMatched` |

### Supported Conditionals

| Conditional | Example | Behavior |
|-------------|---------|----------|
| `[mod]` / `[mod:shift]` | `[mod:shift] Spell` | Tracks modifier key requirement |
| `[form:X]` / `[form:X/Y]` | `[form:1/2] Bear Spell` | Uses `FormCache.GetActiveForm()` (1-N index) |
| `[spec:X]` | `[spec:2] Spell` | Uses `GetSpecialization()` |
| `[mounted]` / `[unmounted]` | `[unmounted] Ground Mount` | Uses `IsMounted()` API |
| `[outdoors]` / `[indoors]` | `[outdoors] Flying Mount` | Uses `IsOutdoors()` API |

### Quality Scoring System

Macros are ranked by specificity to prefer direct bindings over multi-conditional macros:

```lua
-- Base score: 500
-- Bonuses:
--   +200: Macro name matches spell name exactly
--   +150: Macro name starts with spell name
--   +50 per conditional: [form:1], [mod:shift], etc.

-- Penalties:
--   -150 per execution order position (spell on line 2+)
--   -75 per clause position (spell after semicolon)
--   -25 per extra spell in same clause
--   -100: Spell not first in multi-spell line
```

### Cache Key Structure

```lua
-- Includes form + spec for proper conditional invalidation
cacheKey = slot .. "_" .. targetSpellID .. "_" .. currentForm .. "_" .. currentSpec
```

### Spell Override Handling

```lua
-- GetSpellAndOverride() returns both base and morphed spell IDs
-- Example: Pyroblast (11366) → Hot Streak Pyroblast (48108)
-- Macro containing either ID will match
```

### Integration with ActionBarScanner

```lua
-- ActionBarScanner.SearchSlots() calls:
local parsedEntry = MacroParser.GetMacroSpellInfo(slot, spellID, spellName)
if parsedEntry and parsedEntry.found then
    -- Check if current form matches macro's [form:X] conditionals
    local formMatch = true
    if parsedEntry.forms then
        local currentFormID = FormCache.GetActiveForm()
        formMatch = tContains(parsedEntry.forms, currentFormID)
    end
    -- Use parsedEntry.qualityScore for candidate ranking
end
```

## 12.0 (Midnight) Compatibility

JustAC is **safe for 12.0** - displays Blizzard's Combat Assistant output, not a custom rotation.

- **Safe APIs**: `C_AssistedCombat.*`, `GetBindingKey()`, `C_Spell.GetSpellInfo()`
- **Secret Values**: `BlizzardAPI.IsSecretValue()`, `BlizzardAPI.IsMidnightOrLater()`
- **Graceful degradation**: RedundancyFilter shows extra spells if aura APIs return secrets (fail-open)

## Defensive Spell System

Two-tier health-based suggestions in `JustAC.lua`:
- **Self-heals** (`selfHealThreshold: 70%`) - Quick heals in rotation
- **Major cooldowns** (`cooldownThreshold: 50%`) - Emergency defensives
- Class defaults in `CLASS_SELFHEAL_DEFAULTS` / `CLASS_COOLDOWN_DEFAULTS` tables

## Reference Docs

- `Documentation/STYLE_GUIDE_JUSTAC.md` - Full coding conventions (MUST/SHOULD/MAY)
- `Documentation/ASSISTED_COMBAT_API_DEEP_DIVE.md` - C_AssistedCombat API reference
- `Documentation/MACRO_PARSING_DEEP_DIVE.md` - Macro conditional parsing
- `Documentation/12.0_COMPATIBILITY.md` - WoW 12.0 API migration
