# Nameplate Addon Analysis

Analysis of three nameplate addons in the workspace. Use this as context for a deep-dive session.

## Quick Reference: Ownership Models

| Addon | Strategy | Blizzard Frame | Custom Frames |
|-------|----------|----------------|---------------|
| **Platynator** | Full Replacement | Hidden (`SetAlpha(0)`), elements reparented | 8 frame pools (friend/enemy × combat/pvp variants) |
| **Plater** | Hybrid Overlay | Partially visible | DetailsFramework unit frame overlaid inside Blizzard frame |
| **BlizzPlatesFix** | In-Place Modification | Fully intact | None (modifies Blizzard frames directly via `BPF_*` properties) |

---

## 1. Platynator

**Path:** `r:\WOW\Interface\AddOns\Platynator\`

### Architecture
- **Core/** — Config, Constants, Initialize, Utilities
- **Display/** — 9 files: health bar, cast bar, power, text, auras, markers, highlights
- **CustomiseDialog/** — Visual profile designer with import/export
- **API/** — Public text override API
- **Libs/** — LibStub + LibSharedMedia-3.0

### Hooking
```lua
hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, nameplate)
    -- Hides Blizzard UnitFrame (SetAlpha(0))
    -- Reparents: HealthBarsContainer, castBar, RaidTargetFrame, name,
    --   aggroHighlight, DebuffListFrame, BuffListFrame, CrowdControlListFrame
    -- Attaches Platynator frame from pool at CENTER of nameplate
end)
hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, nameplate)
    -- Restores Blizzard frames, returns custom frame to pool
end)
```

### Key Elements
- Custom health bar (replaces Blizzard entirely)
- Custom cast bar
- Three aura displays: Debuffs, Buffs, CC (each with pandemic animation, dispel highlighting)
- Text overlays: creature name, guild, health, cast, level
- Markers: Elite, Rare, Raid Target, PvP, Class, Quest
- Highlights: target/soft-target/mouseover (animated)
- Nameplate stacking per category

### 12.0 Compatibility
- `IsMidnight = select(4, GetBuildInfo()) >= 120001` in Constants.lua
- Aura frames handle opaque duration objects: `SetCooldownFromDurationObject(aura.durationSecret)`
- No direct `UnitHealth()` usage (good — avoids secret health problem)

### Performance
- **8 frame pools** via `CreateFramePool()` (reuse on add/remove)
- `C_Timer.NewTicker(0.1)` for attackable status transitions
- `CallbackRegistry` for settings propagation (no polling)
- Aura manager caches by `auraInstanceID`

### Config
- `PLATYNATOR_CONFIG` (SavedVariables) + `PLATYNATOR_CURRENT_PROFILE` (per-char)
- JSON-serialized design profiles, assigned per nameplate type

---

## 2. Plater

**Path:** `r:\WOW\Interface\AddOns\Plater\`

### Architecture
- ~40 root `.lua` files (monolithic, not modular libraries)
- `Plater.lua` — main entry + cache definitions
- `Definitions.lua` — extensive `@class`/`@alias` type annotations
- `Plater_API.lua` — minimal public API
- **Requires DetailsFramework-1.0** — unit frame classes, GUI builders, DB abstraction
- Also uses: LibRangeCheck-3.0, LibCustomGlow-1.0, LibSharedMedia-3.0

### Hooking
```lua
-- DetailsFramework creates parallel widget tree inside Blizzard nameplate
-- Blizzard UnitFrame remains partially visible underneath
-- No reparenting or hiding of Blizzard frames
-- Hook via DF framework on NAME_PLATE_UNIT_ADDED
-- Custom unitFrame stored as plateFrame.unitFrame
```

### Key Elements
- `df_healthbar` — custom health bar with absorb/heal prediction, execute range
- `df_castbar` — cast bar with target name, throttled updates
- `df_powerbar` — energy/mana display
- `BuffFrame` / `BuffFrame2` — separate aura containers
- Custom indicators: threat, focus, raid markers
- Target highlight (neon glow)
- ExtraIconFrame for additional status

### 12.0 Compatibility
- `IS_WOW_PROJECT_MIDNIGHT = DF.IsAddonApocalypseWow()`
- Secret value handling delegated to DetailsFramework:
  ```lua
  if IS_WOW_PROJECT_MIDNIGHT and issecretvalue(isInRange) then
      unitFrame:SetAlphaFromBoolean(isInRange, ...)
  ```
- DF abstracts `issecretvalue()` checks behind utility methods

### Performance
- Script hook system: `HOOK_NAMEPLATE_ADDED/CREATED/UPDATED` with indexed lookup + `ScriptAmount` counter
- `DB_*` local variables cache profile values (avoids deep table lookups per frame)
- DF-provided frame pooling
- Throttled range check updates

### Config
- `PlaterDB` (global) + `PlaterDBChr` (per-char) + `PlaterLanguage`
- AceConfig-like options panel
- Per-spec settings, JSON import/export
- Masque skinning support

---

## 3. BlizzPlatesFix

**Path:** `r:\WOW\Interface\AddOns\BlizzPlatesFix\`

### Architecture
- **Core/** (14 files) — Engine, Events, Dispatch, Hooks, HooksDispatch, ModuleManager, Config
- **Modules/** (17 files) — Each module = `{Init, Update, Reset}` pattern
- **UI/** — Options panel + widgets
- Libs: LibStub, LibRangeCheck-3.0, LibDataBroker, LibDBIcon, LibSharedMedia-3.0

### Hooking
```lua
-- In-place hooks on Blizzard's CompactUnitFrame functions:
hooksecurefunc("CompactUnitFrame_UpdateName", HookHandler)
hooksecurefunc("CompactUnitFrame_UpdateHealth", HookHandler)
hooksecurefunc("CompactUnitFrame_UpdateAuras", HookHandler)
-- All route to NS.RequestUpdate(unit, reason, immediate)
-- Queued updates dispatched via Engine.FlushPending()

-- Aura suppression:
-- Detects BuffFrame/DebuffFrame/AurasFrame containers
-- Sets container:SetAlpha(0), :Hide()
-- Hooks OnShow to re-hide
```

### Module System (17 modules)
| Module | Purpose |
|--------|---------|
| HpBar | Health bar coloring (threat/class/neutral) |
| CastBar | Cast bar rendering + styling |
| Auras | Buff/debuff display |
| NameText | Unit name styling |
| HpText | Health/shield text overlays |
| Level | Unit level display |
| Border | Border styling |
| TargetIndicator | Current target visuals |
| Glow | Threat/selection glow |
| Icon (×6) | Elite, Faction, Quest, RaidTarget icons |
| Transparency | Range-based alpha |
| CastTimer | Visual cast timer |

### Reason Mask System
```lua
NS.REASON_PLATE  = 1    -- geometry change
NS.REASON_AURA   = 2    -- buff/debuff update
NS.REASON_CAST   = 4    -- cast bar update
NS.REASON_HEALTH = 8    -- health change
NS.REASON_THREAT = 16   -- threat update
NS.REASON_CONFIG = 128  -- config applied
-- Modules only execute if their required reason bits are set
```

### 12.0 Compatibility
- **NOT IMPLEMENTED** — No `issecretvalue()`, no `C_Secrets`, no version checks
- Direct `UnitHealth()`/`UnitHealthMax()` calls in health bar module → **will break in 12.0 combat**
- Relies on Blizzard's `CompactUnitFrame_*` to handle secrets internally

### Performance
- **Throttled FIFO queue**: per-unit min 0.05s between updates, max 25 units/frame
- Reason masks aggregate triggers → single update pass
- `NS.ActiveNamePlates` table for unit→frame mapping
- Forbidden frame guards throughout: `if frame:IsForbidden() then return end`
- FastTasks registry for periodic background work (OnUpdate-driven)

### Config
- `BlizzPlatesFixDB` (SavedVariables)
- Per-unit-type profiles: FriendlyPlayer, FriendlyNPC, EnemyPlayer, EnemyNPC
- Settings apply immediately (queues REASON_CONFIG update)

---

## Comparative Matrix

| Aspect | Platynator | Plater | BlizzPlatesFix |
|--------|-----------|--------|----------------|
| Frame ownership | Full replacement | Hybrid overlay | In-place modify |
| Dependencies | LibStub + LSM | **DetailsFramework** (required) | LibStub + LibRangeCheck |
| 12.0 ready | ⚠️ Partial (opaque durations) | ✅ Good (DF abstraction) | ❌ Broken (direct health API) |
| Complexity | High | Very High (~40 files) | Medium (modular plugins) |
| Aura handling | Custom pools + instanceID cache | DF-provided BuffFrame | Suppress Blizzard + custom |
| Perf strategy | Frame pools + callbacks | Script cache + DB locals | FIFO queue + reason masks |
| Config | JSON design profiles | AceDB + JSON import | Per-unit-type profiles |

## Key APIs (Nameplate Lifecycle)

```
NAME_PLATE_UNIT_ADDED        → nameplate appears (creation/reuse)
NAME_PLATE_UNIT_REMOVED      → nameplate disappears (recycle)
C_NamePlate.GetNamePlateForUnit(unit, issecure())  → frame lookup
C_NamePlate.GetNamePlates()   → all active plates
CompactUnitFrame_Update*      → Blizzard's internal update hooks
NamePlateDriverFrame          → Blizzard's management frame (scale, distance, stacking)
```

## 12.0 Secret Value Concerns for Nameplates

| API | Secret in Combat? | Workaround |
|-----|-------------------|------------|
| `UnitHealth(unit)` | YES | Use opaque health pipelines or local tracking |
| `UnitHealthMax(unit)` | NO (`C_Secrets.ShouldUnitHealthMaxBeSecret` → false) | Safe to call |
| `UnitPower(unit)` | YES (primary resource) | Discrete secondary resources are NeverSecret |
| Aura `spellId`/`name` | YES | Track by `auraInstanceID` (NeverSecret) |
| Aura `duration` | YES | Use `SetCooldownFromDurationObject()` with opaque object |
| `UnitThreatSituation()` | NO | Safe to call |
| `UnitClassification()` | NO | Safe to call |
| `UnitIsPlayer()` | NO | Safe to call |
