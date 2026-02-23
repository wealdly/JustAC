# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 4.2.0

**Instructions:**

- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

### Added

- **Post-interrupt debounce:** After the player uses their interrupt or CC, suppress the interrupt reminder for 1 second to prevent flicker from the lingering cast bar.

### Changed

- **Simplified interrupt options:** Replaced the 5-option interrupt mode dropdown with a simple on/off toggle + "Prefer CC on Regular Mobs" checkbox. Behavior: On + CC off = kick every interruptible cast. On + CC on = prefer CC on non-boss mobs (fall back to kick if no CC ready), always kick on bosses. Off = disabled.
- **Boss detection for CC immunity:** Replaced `UnitIsBossMob()` (only flags a narrow gold-winged portrait category) with `UnitClassification("worldboss")` + `boss1`–`boss5` frame check. Dungeon bosses like Lord Godfrey now correctly detected as CC-immune.

### Fixed

- **Interrupt icon shown for non-interruptible casts (e.g., Brutal Jab):** Use `castBar.Icon:IsShown()` as primary interruptibility check — Blizzard's secure `ShouldIconBeShown()` resolves barType taint internally and returns plain `true`/`false` literals. `BorderShield` kept as fallback for pre-12.0.

### Removed

- **Duration filter for interrupt casts:** Removed `MIN_INTERRUPT_CAST_DURATION` heuristic — `Icon:IsShown()` reliably detects interruptible casts so the duration guard is unnecessary.
- **Important cast detection:** Removed all `C_Spell.IsSpellImportant()` / `ImportantCastIndicator` code — broken by 12.0 secret values in combat, and no longer needed with simplified on/off interrupt model.
- **`/jac casttest` debug command:** Removed (was temporary diagnostic for interrupt taint investigation).
