# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 4.2.1

**Instructions:**

- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

### Fixed

- **Long buffs (poisons, Mark of the Wild) shown as active when about to expire at combat start:** Stop filtering a long-duration buff (≥10 min) when less than 5 minutes remain. The aura `expirationTime` is a plain Lua number captured out of combat and via `auraInstanceID`→timing map, so `expirationTime - GetTime()` is valid arithmetic even in combat. Three-layer fix: (1) `IsInPandemicWindow` applies a 5-minute absolute floor for long buffs alongside the 30% pandemic threshold; (2) the trusted-cache combat merge skips re-adding expiring long buffs; (3) `CountActivePoisonBuffs` skips counting a poison whose cached expiration is within 5 minutes.
