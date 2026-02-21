# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 4.0.0

**Instructions:**

- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

### Added
- **DefensiveEngine module**: Extracted ~855 lines of defensive spell logic from JustAC.lua into `DefensiveEngine.lua` (LibStub `JustAC-DefensiveEngine` v1) — health-based queue, proc detection, potion subsystem, cooldown polling. JustAC.lua retains thin wrapper methods that delegate to the new module.
- **CC Non-Important Casts option**: New toggle under Interrupt Reminder (both standard queue and nameplate overlay). When enabled, uses crowd-control abilities (stuns, incapacitates) to interrupt non-important casts on CC-able (non-boss) mobs, while saving true interrupt lockout for important/lethal casts. Ideal for open-world combat efficiency.

### Changed
- **Frame rebuild consistency**: All frame-affecting settings now route through a single `UpdateFrameSize()` path
  - `UpdateFrameSize()` now calls `ForceUpdateAll()` instead of `ForceUpdate()`, ensuring `OnHealthChanged` fires and `ResizeToCount` runs immediately after any frame rebuild — fixes health bar width not shrinking until next `UNIT_HEALTH` event
  - Removed redundant trailing `ForceUpdate()` from `RefreshConfig` (already handled by `UpdateFrameSize`)
  - Simplified 4 defensive Options setters (enabled, maxIcons, iconScale, position) from inline `CreateSpellIcons + UpdateSize + UpdatePetSize + ForceUpdateAll` to single `UpdateFrameSize()` call
  - Simplified defensive health bar toggle setters (showHealthBar, showPetHealthBar) from inline destroy/create to `UpdateFrameSize()`
  - Simplified General "Reset to Defaults" button: removed redundant `UpdateTargetFrameAnchor()` and `ForceUpdate()` calls
- **Defensive "Reset to Defaults" button**: Synced hardcoded defaults with JustAC.lua profile defaults
  - `showHealthBar`: `false` → `true`
  - `showPetHealthBar`: `false` → `true`
  - `glowMode`: `"procOnly"` → `"all"`
  - `maxIcons`: `3` → `4`
  - `allowItems`: `false` → `true`
  - `displayMode`: `"combatOnly"` → `"always"`
  - Now uses `UpdateFrameSize()` instead of manual destroy/create/ForceUpdateAll

### Fixed
- **Health bars not scaling after reset**: `UpdateFrameSize` now triggers `OnHealthChanged` → `ResizeToCount`, so health bar width matches actual visible defensive icon count immediately after any configuration change or profile reset
- **Dynamic transform hotkeys missing** (e.g. Templar Strike → Templar Slash): ActionBarScanner v35
  - Pass `onlyKnown=false` to `C_Spell.GetOverrideSpell()` — default `true` filtered out aura-driven combat transforms that aren't in the spellbook
  - Added `FindSpellOverrideByID` fallback in `SearchSlots` for talent/aura overrides that `C_Spell.GetOverrideSpell` may miss (separate native lookup path)
  - Empty hotkey cache results (`""`) no longer use the fast-path, falling through to 0.25s stale-refresh so transforms self-correct within frames
  - Added forward override scan in `GetSpellHotkey` — checks if any previously-cached slot's spell currently overrides to the target, catching dynamic transforms where `FindBaseSpellByID` returns nil

### Removed
