# Changelog

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
