# Changelog

## [3.08] - 2025-12-09

### Fixed

- **WoW 12.0 compatibility**: Fix Settings.OpenToCategory error when opening options panel
- 12.0 path: Use AceConfigDialog:Open() directly (Settings API changed signature)
- Pre-12.0 path: Keep Settings.OpenToCategory() with string parameter
- Fixes error: "bad argument #1 to 'OpenSettingsPanel' (outside of expected range)"

## [3.07] - 2025-12-09

### Added

- **Version detection infrastructure**: Prepare for WoW 12.0 compatibility fixes
- Added `BlizzardAPI.GetInterfaceVersion()` - Returns current WoW version (110207, 120000, etc.)
- Added `BlizzardAPI.IsMidnightOrLater()` - Check if running 12.0+
- Added `BlizzardAPI.VersionCall()` - Helper for version-aware function calls
- Created `Documentation/VERSION_CONDITIONALS.md` - Patterns for adding version-specific code
- Ready to accept 12.0 error reports and add conditional fixes

## [3.06] - 2025-12-09

### Changed

- **Code simplification pass**: Removed duplicate logic in RedundancyFilter module
- Removed duplicate cooldown check (was checked twice in same function)
- Consolidated duplicate secret detection checks into single unified block
- Improved code maintainability without affecting functionality

## [3.05] - 2025-12-09

### Changed

- **Cooldown-aware filtering enabled always**: Hide abilities on cooldown >2s, show when coming off CD
- Abilities appear 2 seconds before ready, giving visual preparation time
- Applies to both main DPS queue and defensive queue
- Reduces queue clutter from abilities on long cooldowns
- Keeps queue focused on immediately available or soon-ready abilities

## [3.04] - 2025-12-09

### Changed

- **Whitelist approach for WoW 12.0**: When aura detection is blocked, only show DPS-relevant spells in queue
- Automatically filters out forms, pets, raid buffs, and utility abilities when can't verify their state
- Uses LibPlayerSpells flags (HARMFUL, BURST, COOLDOWN, IMPORTANT) to identify rotation-critical abilities
- Keeps queue focused on offensive rotation when addon can't access buff information

## [3.03] - 2025-12-09

### Changed

- Automatically hide raid buffs (Battle Shout, Arcane Intellect, etc.) from queue when WoW 12.0 blocks aura detection
- Uses LibPlayerSpells RAIDBUFF flag to identify long-duration maintenance buffs
- Reduces queue clutter when addon can't verify if buffs are already active
- Forms, pets, and rotation abilities still show normally (don't require aura API)

## [3.02] - 2025-12-09

### Changed

- Updated Interface version to 120000 for WoW 12.0 (Midnight) beta compatibility

## [3.01] - 2025-12-08

### Fixed

- Fixed nil reference crash in defensive proc glow animation when switching between proc and non-proc states
- Removed references to deleted ProcStartFlipbook and ProcStartAnim frame elements (cleaned up after earlier animation refactor)
- Added defensive null checks for Flipbook.Anim frame transitions

## [3.0] - 2025-12-08

### Added

- Feature Availability system to detect 12.0+ "secret" values (health/aura/cooldown/proc APIs) and gracefully degrade features when blocked
- Manual blacklist and hotkey override inputs in the Options panel for easier configuration

### Changed

- UI visual improvements: brighter marching ants glow, enhanced keypress flash (stacked ADD layers and slightly larger), and hotkeys always render on top
- GCD swipe removes gold edge (now only used for full ability cooldowns)

### Fixed

- Fix: activation flash appearing on the wrong slot when spells move in the queue

## [2.98] - 2025-12-07

### Added

- Important procs now display before regular procs in the queue
- `/jac lps <spellID>` debug command to view spell classification info

### Changed

- Activation flash is now brighter and lasts longer for better visibility
- Improved hotkey detection when spells change rapidly
- Removed stabilization window setting (no longer needed)

### Fixed

- Slot 1 now stays stable when holding modifier keys (requires Single-Button Assistant placed on any action bar)

## [2.97] - 2025-12-07

### Added

- Brazilian Portuguese (ptBR) translation - 127 strings
- Total coverage increased to ~40-42% of non-English player base

## [2.96] - 2025-12-07

### Added

- Full localization support via AceLocale-3.0
- German (deDE) translation - 127 strings
- French (frFR) translation - 127 strings
- Russian (ruRU) translation - 127 strings
- Spanish-Spain (esES) translation - 127 strings
- Spanish-Mexico (esMX) translation - 127 strings
- Total coverage: ~32% of non-English Western WoW retail player base

### Changed

- All UI strings in Options panel now use localization keys
- Improved terminology consistency (e.g., German now uses "Cooldown" consistently)
- Spell examples use localized names (e.g., "Fel Blade" → "Teufelsklinge" in German)

## [2.95] - 2025-12-07

### License Update

- License updated from MIT to GPL-3.0-or-later for LibPlayerSpells-1.0 compatibility
- Added SPDX license identifiers to all source files
- Updated README.md with GPL v3 license information
