# Changelog

## [3.10] - 2026-01-25

### WoW 12.0 Midnight Compatibility Release

Major update for full WoW 12.0 (Midnight) compatibility with comprehensive secret value handling and modernized spell classification.

### Added

- **SpellDB.lua**: Native spell classification database replacing LibPlayerSpells-1.0
  - ~330 spell IDs across 4 categories: DEFENSIVE, HEALING, CROWD_CONTROL, UTILITY
  - Fail-open design: unknown spells assumed offensive (correct for DPS filtering)
  - Covers all classes including Evoker/Augmentation support
- **Out-of-range indicator**: Hotkey text turns red when queue spells are out of range
- **C_Secrets namespace wrappers**: `ShouldSpellCooldownBeSecret()`, `ShouldSpellAuraBeSecret()`, `ShouldUnitSpellCastBeSecret()` for proactive secrecy testing
- **Enhanced `/jac formcheck`**: Shows spell ID → form ID mappings and redundancy check results

### Changed

- **Module architecture**: Split UIManager.lua (2025 lines) into focused modules:
  - `UIAnimations.lua` (451 lines) - Animation/visual effects
  - `UIFrameFactory.lua` (881 lines) - Frame creation and layout
  - `UIRenderer.lua` (962 lines) - Rendering and update logic
  - `UIManager.lua` (154 lines) - Thin orchestrator
- **Resource coloring**: Now uses Blizzard's standard blue tint (0.5, 0.5, 1.0) when not enough mana/resources
- **Flash layering**: Flash (+6) > Proc Glow (+5) > Marching Ants (+4) for better visibility
- **Priest defensives**: Reorganized - Desperate Prayer moved to cooldowns, Vampiric Embrace added to self-heals

### Fixed

- **Icon artwork bleeding outside frame**: Icons now use 1px inset, SetTexCoord edge crop, and MaskTexture for beveled corners
- **Proc glow not showing**: Fixed combat state bug in UIRenderer (was checking never-updated variable)
- **Dead Priest spell ID**: Replaced Greater Fade (213602, removed in 10.0.0) with Desperate Prayer
- **Secret value crashes**: Hardened all API wrappers to handle 12.0 secret values gracefully
- **Best-effort aura detection**: Now skips individual secret auras instead of abandoning all remaining
- **Form redundancy check**: Now runs before secret bypass, using always-safe stance bar APIs
- **Raid buffs filtered**: Mark of the Wild, Fortitude, Battle Shout, Arcane Intellect, Blessing of the Bronze now hidden when active
- **Usability filtering**: Queue positions 2+ now filter spells on cooldown (>2s) or lacking resources

### Removed

- **LibPlayerSpells-1.0**: Removed entirely (outdated since Shadowlands, missing all modern spells)
- **Duplicate cooldown filtering**: Consolidated to SpellQueue only
- **Unused functions**: `HasBuffByIcon()`, `HasSameNameBuff()`, `IsRaidBuff()`

## [3.03] - 2025-12-15

### Added

- **Keybind abbreviations**: Long keybinds now display with compact abbreviations for better fit
  - Mouse buttons: BUTTON4→M4, BUTTON5→M5, MOUSEWHEELUP→MwU, MOUSEWHEELDOWN→MwD
  - Numpad: NUMPAD1→N1, NUMPAD0→N0
  - Navigation: PAGEUP→PgU, PAGEDOWN→PgD, HOME→Hm, END→End
  - Special: SPACE→Spc, ESCAPE→Esc, BACKSPACE→BkSp, CAPSLOCK→Caps
  - Editing: INSERT→Ins, DELETE→Del
  - Combined examples: CTRL-BUTTON4→CM4, SHIFT-NUMPAD5→SN5

### Changed

- **Keypress flash improvements**: Enhanced visual feedback for button presses
  - Flash now uses strobe/toggle behavior (like Blizzard's action buttons) for high visibility
  - Added short scale pulse (1.12x → 1.0 over 120ms) for emphasis
  - Flash centered on button and sized to match icon exactly
  - Flash positioned below marching ants/proc glow layers (proper z-ordering)
  - Single flash texture instead of doubled layers (cleaner visuals)
- **Empty slots visibility**: Empty slots now visible when abilities are filtered
  - Shows action bar background and border for unused positions up to maxIcons
- **Grab tab fade**: Now fades in/out on mouse hover for cleaner appearance
- **Grab tab persistence**: Stays visible during drag (won't disappear on fast cursor movement)
- **Drag improvements**: Drag from anywhere on icons or main frame when unlocked
- **Frame positioning**: Frame follows cursor precisely during drag with no offset
- **Context menu**: Right-click on icons/empty areas for options menu access

### Fixed

- **Critical**: Flash timing bug causing flash to run 2x faster than intended (double elapsed subtraction)
- **Critical**: Flash overlay staying visible after keypress (OnUpdate handler conflict)
- **Performance**: Optimized keypress detector hot-path (eliminated redundant string concatenations)
- **Visual**: Removed accidental duplicate flash texture on defensive icon
- **Code quality**: Centralized bypass flag logic to eliminate duplication across modules
- **Maintainability**: Added GetBypassFlags() helper in BlizzardAPI for consistent feature detection

## [3.02] - 2025-12-09

### Added

- **Version detection infrastructure**: Prepare for WoW 12.0 compatibility fixes
- Added `BlizzardAPI.GetInterfaceVersion()` - Returns current WoW version (110207, 120000, etc.)
- Added `BlizzardAPI.IsMidnightOrLater()` - Check if running 12.0+
- Added `BlizzardAPI.VersionCall()` - Helper for version-aware function calls
- Created `Documentation/VERSION_CONDITIONALS.md` - Patterns for adding version-specific code
- Ready to accept 12.0 error reports and add conditional fixes

### Changed

- **UI**: Empty slots now visible when abilities are filtered (on cooldown, blacklisted, etc.) - shows action bar background and border for unused icon positions up to maxIcons setting
- **Cooldown filter prep window**: Increased from 2s to 5s before abilities appear
- Abilities now show when ≤5s remaining on cooldown (was 2s)
- Provides more preparation time for abilities coming off cooldown
- Reduces queue flickering from short cooldowns
- **Cooldown-aware filtering enabled always**: Hide abilities on cooldown >5s, show when coming off CD
- Applies to both main DPS queue and defensive queue
- Reduces queue clutter from abilities on long cooldowns
- Keeps queue focused on immediately available or soon-ready abilities
- **Whitelist approach for WoW 12.0**: When aura detection is blocked, only show DPS-relevant spells in queue
- Automatically filters out forms, pets, raid buffs, and utility abilities when can't verify their state
- Uses LibPlayerSpells flags (HARMFUL, BURST, COOLDOWN, IMPORTANT) to identify rotation-critical abilities
- Keeps queue focused on offensive rotation when addon can't access buff information
- Automatically hide raid buffs (Battle Shout, Arcane Intellect, etc.) from queue when WoW 12.0 blocks aura detection
- Uses LibPlayerSpells RAIDBUFF flag to identify long-duration maintenance buffs
- Reduces queue clutter when addon can't verify if buffs are already active
- Forms, pets, and rotation abilities still show normally (don't require aura API)
- Updated Interface version to 120000 for WoW 12.0 (Midnight) beta compatibility
- **Code simplification pass**: Removed duplicate logic in RedundancyFilter module
- Removed duplicate cooldown check (was checked twice in same function)
- Consolidated duplicate secret detection checks into single unified block
- Improved code maintainability without affecting functionality

### Fixed

- **WoW 12.0 raid buff filtering**: Hide Mark of the Wild and other raid buffs when aura API blocked
- Added hardcoded list of common raid buffs (Mark of the Wild, Power Word: Fortitude, Battle Shout, Arcane Intellect)
- These buffs now properly filtered when secrets prevent checking if already active
- Prevents queue clutter from suggesting buffs that may already be active
- **WoW 12.0 compatibility**: Fix Settings.OpenToCategory error when opening options panel
- 12.0 path: Use AceConfigDialog:Open() directly (Settings API changed signature)
- Pre-12.0 path: Keep Settings.OpenToCategory() with string parameter
- Fixes error: "bad argument #1 to 'OpenSettingsPanel' (outside of expected range)"
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
