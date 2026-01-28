# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.15

### Changes Since 3.15

#### Added
- **BlizzardAPI v26**: API-specific secret helpers for incremental 12.0 compatibility
  - `GetCooldownForDisplay(spellID)` - Returns start, duration (nil if secret)
  - `IsSpellReady(spellID)` - Boolean usability check, fail-open if secret  
  - `GetAuraTiming(unit, index, filter)` - Returns duration, expiration (field-level checks)
  - `GetSpellCharges(spellID)` - Returns current, max charges (field-level checks)
  - Purpose-specific helpers check only needed fields as Blizzard releases API access incrementally

- **MacroParser v21**: [stealth] and [combat] conditional evaluation
  - Implemented `[stealth]`, `[nostealth]`, `[combat]`, `[nocombat]` conditional checks
  - Fixes Rogue/Druid keybind detection for macros like `/cast [stealth] Cheap Shot; Sinister Strike`

#### Changed
- **UIRenderer v8**: Migrated to centralized secret handling
  - All secret checks now use `BlizzardAPI.IsSecretValue()`
  - Using API-specific helpers for field-level granularity (30+ call sites simplified)

- **RedundancyFilter v25**: Migrated to centralized secret handling  
  - All secret checks now use `BlizzardAPI.IsSecretValue()`
  - Using `GetAuraTiming()` for field-level aura access
  - Allows partial aura data when some fields are secret (best-effort processing)

- **Options.lua**: Migrated to centralized secret handling
  - Cooldown display now uses `BlizzardAPI.IsSecretValue()`
  - All spell info lookups use `BlizzardAPI.GetSpellInfo()` for consistent secret handling
  - Removed redundant LibStub lookups inside functions

- **DebugCommands.lua**: Migrated to centralized secret handling
  - Health API status now uses `BlizzardAPI.IsSecretValue()`

#### Removed
- **Code consolidation**: Removed duplicate `SafeGetSpellInfo` implementations (-18 lines)
  - Deleted from MacroParser.lua - now uses `BlizzardAPI.GetSpellInfo()`
  - Deleted from FormCache.lua - now uses `BlizzardAPI.GetSpellInfo()`
  - All spell info access consolidated through BlizzardAPI for consistent secret handling

- **RedundancyFilter**: Removed unused debug variables (-3 lines)
  - Deleted unused `lastDebugPrintTime` table
  - Deleted unused `DEBUG_THROTTLE_INTERVAL` constant

#### Fixed
- **MacroParser v21**: Removed dead code (-12 lines)
  - Deleted `SafeIsMounted()` - defined but never called
  - Deleted `SafeIsOutdoors()` - defined but never called

#### Performance
- **Comment cleanup**: Condensed verbose comments across 4 core modules (-80 lines)
  - Removed multi-line explanations that restated obvious code
  - Kept all operational guidance and critical API compatibility notes
  - MacroParser, BlizzardAPI, UIRenderer, RedundancyFilter now more concise

---

**Instructions:**
- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction
