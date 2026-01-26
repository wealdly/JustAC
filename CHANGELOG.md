# Changelog

## [3.14] - 2026-01-26

### Added
- **Multiple Defensive Icons**: Can now display 1-3 defensive spells simultaneously
  - New `defensives.maxIcons` setting (1-3, default 1) controls how many icons to show
  - Icons layout horizontally for SIDE1/SIDE2 positions (along queue direction)
  - Icons stack perpendicular for LEADING position
  - Each icon has full visual parity: glow, cooldown, hotkey, tooltips
- **Defensive Icon Scale**: New independent scaling option for defensive icons
  - `defensives.iconScale` (1.0-2.0, default 1.2) works like Primary Spell Scale
  - All defensive icons scale uniformly with this setting
  - No longer tied to DPS queue's firstIconScale
- **12.0 Local Cooldown Tracking**: When `C_Spell.GetSpellCooldown()` returns secrets in combat, defensive spell cooldowns are now tracked locally using `UNIT_SPELLCAST_SUCCEEDED` events and `GetSpellBaseCooldown()` (which is NOT secret in 12.0)
  - Duration caching: When spells are cast out of combat, actual modified duration is captured and cached for in-combat use
  - Cached durations cleared on talent/spec changes
  - `BlizzardAPI.RegisterDefensiveSpell()`, `ClearTrackedDefensives()`, `IsSpellOnLocalCooldown()`
  - `JustAC:RegisterDefensivesForTracking()` registers all configured defensive spells
- **In-Combat Activation Tracking**: RedundancyFilter now tracks spell casts during combat via `UNIT_SPELLCAST_SUCCEEDED`
  - Works reliably even with 12.0 combat log restrictions (mirrors proc detection system)
  - Filters out redundant suggestions for spells cast during combat (forms, poisons, long buffs)
  - Toggle detection: Automatically detects when toggleable auras canceled mid-combat via non-secret APIs (forms, stealth, pets, mounts)
  - Cleared on leaving combat
- **Charge Count Display**: Shows current charges for charge-based spells on both defensive and DPS icons
  - Displayed in bottom-right corner at 85% of hotkey font size
  - Only shown for multi-charge spells (Fire Blast, Frenzied Regen, Roll, etc.)
  - Handles 12.0 secret values properly

### Changed
- **BlizzardAPI v25**: Enhanced cooldown detection system
  - `IsSpellOnRealCooldown()` now uses 3-tier fallback: Native API → Local cooldown tracking → Action bar usability check
  - Added charge detection for charge-based spells (filters when depleted)
  - Secret value handling improvements
- **RedundancyFilter v24**: In-combat activation tracking with toggle detection
- **UIRenderer v6**: Simplified cooldown overlay handling
  - Cooldown widget auto-expires naturally (no manual hiding on 0,0 data)
  - Minimal change detection prevents flicker while handling secrets correctly
  - Fixed cooldown overlays not updating reliably during combat
- **UIFrameFactory v8**: Added charge text display to both defensive and DPS icons
- **Defensive Spell Defaults Redesigned for 12.0**: Streamlined spell lists with fewer, better choices
  - Removed cast-time spells and spec-specific deep talents
  - Reordered for priority: instant heals > absorbs > damage reduction
  - Self-heals: ~2-3 spells per class (reduced from 3-4)
  - Cooldowns: ~2-3 big defensives per class
- **SpellDB**: Added Word of Glory (85673) to HEALING_SPELLS for Divine Purpose proc detection

### Fixed
- **Cooldown Overlay Display**: Fixed cooldowns not updating reliably during combat with secret values
  - Cooldown widget now expires naturally instead of being manually hidden
  - Properly handles transitions between secret and non-secret cooldown states
- **Defensive Proc Detection**: Fixed proc'd defensives showing gold glow even after proc ended
  - `IsSpellProcced()` now checks both spell ID and override ID
  - Validates procs are still active via API instead of trusting cached events
  - Automatic cleanup of stale proc entries
- **Multi-Defensive Icon Queue**: Fixed queue disappearing with maxIcons > 1
  - `GetUsableDefensiveSpells` now uses local table instead of modifying caller's table
- **Charge-Based Spell Filtering**: Fixed charge spells staying in queue when depleted
  - `IsSpellOnRealCooldown()` now checks `C_Spell.GetSpellCharges()` for zero charges
- **Secret Value Handling**: Fixed comparison errors with secret charge counts
  - Check for secrets on both `maxCharges` and `currentCharges` before comparing

### Technical Notes
- Verified in-game on WoW 12.0.0 (build 65560):
  - `GetSpellBaseCooldown()` is NOT secret in combat ✅
  - `C_Spell.GetSpellCooldown()` is SECRET in combat ❌
  - `C_Spell.GetSpellCharges()` is SECRET in combat ❌
- Out-of-combat casts capture actual modified duration for later use
- In-combat uses cached duration if available, otherwise base cooldown
- Base cooldown ignores haste/talent modifiers (conservative approach)

## [3.13] - 2026-01-25

### Added
- **Health Bar Display**: Optional compact health bar above main queue
  - Green → Yellow → Red gradient based on health percentage
  - Enable via Defensive Queue settings: "Show Health Bar"
  - Supports edge-to-edge display for single icon mode, 25% inset for multiple icons
  - New module: `UIHealthBar.lua` with StatusBar widget approach
- **Custom Hotkeys**: Right-click defensive icon to set custom keybinds for spells
  - Immediately visible without reload
  - Tooltips show "(custom)" indicator for overridden hotkeys
- **Tooltip Support**: Defensive icon now respects tooltip settings (showTooltips/tooltipsInCombat)

### Changed
- **Animation System**: Unified all glows on marching ants animations with color tinting
  - DPS queue: White marching ants (regular), Gold (proc)
  - Defensive icon: Green marching ants (regular), Gold (proc)
  - Removed 370 lines of old unused animation code
  - No more blue tint on position 1
- **Position System Refactor**: Renamed defensive icon positions for clarity across orientations
  - ABOVE → SIDE1 (health bar side)
  - BELOW → SIDE2 (opposite perpendicular)
  - LEFT → LEADING (opposite grab tab)
  - Health bar always appears on SIDE1 regardless of queue orientation
- **Default Settings**: Updated profile defaults for better user experience
  - Tooltips in combat: enabled by default
  - Defensive position: LEADING (opposite grab tab)
  - Defensive visibility: always visible (not just in combat)
  - First icon scale: standardized to 1.2 across all components

### Fixed
- **Defensive Icon Visibility**: Fixed icon disappearing when changing queue orientation
  - Now preserves state (id, isItem, isShown) across recreations
- **Defensive Icon Spacing**: Fixed spacing when health bar toggled on/off
- **Health Bar Sizing**: Fixed health bar not edge-to-edge in single icon mode
  - Single icon: full width with 0 offset
  - Multiple icons: 25% inset for visual balance
- **Health Bar Gradient**: Fixed color gradient not updating (was stuck on green)

## [3.12] - 2026-01-25

### Added
- `ActionBarScanner.GetSlotForSpell(spellID)` - Returns action bar slot for a spell (v30)
- `/jac defensive` command - Diagnose defensive icon system (DebugCommands v7)

### Changed
- **12.0 Resource Detection**: When `C_Spell.IsSpellUsable()` returns secret values, now falls back to checking `C_ActionBar.IsUsableAction()` on the action bar slot for that spell - this uses the visual icon state (desaturation) which is not secret (BlizzardAPI v21)
- **12.0 Defensive Health Detection**: Defensive system now uses `GetPlayerHealthPercentSafe()` which tries exact health first, then falls back to visual overlay when secrets block the API. When using the visual overlay, "low" = overlay showing (~35%), "critical" = high alpha (~20%)
- **Simplified Defensive Priority System**: Redesigned defensive spell selection: procs at any health; low (~35%) → big heals; critical (~20%) → cooldowns > potions > heals
- **GCD Swipe**: Removed fragile `anyIconOnGCD` detection loop - GCD now always propagates when active (uses dummy spell 61304 for accurate state)
- **Cooldown Caching**: Uses tolerance-based comparison (50ms threshold) to prevent flickering on repeated same-spell casts
- **Debug Logging Throttled**: Reduced log spam in debug mode - form redundancy, non-DPS spell filter, and macro parser messages now throttled

### Fixed
- **Defensive Icon Not Showing**: Fixed critical bug where `addon.defensiveIcon` was never assigned after creation - the defensive icon frame was created but not exposed to UIManager, causing all defensive suggestions to silently fail (UIFrameFactory v2)
- **Defensive Spells Filtered by DPS-Relevance**: In 12.0 when aura API is restricted (instances), the DPS-relevance filter incorrectly filtered out self-heal spells like Regrowth. Added `isDefensiveCheck` parameter to `IsSpellRedundant()` to bypass this filter for defensive spell selection
- Fixed GCD swipe not showing when repeatedly casting the same ability (e.g., spamming Shred)
- Fixed GCD swipe flickering caused by floating-point comparison on every frame
- Fixed cooldown swipe inset gap - cooldowns now fill icon exactly (`SetAllPoints(iconTexture)`) matching Blizzard/WeakAuras/Dominos pattern
- Fixed icon mask not filling button properly - now uses `SetAllPoints(button)` instead of explicit sizing
- Fixed asymmetric frame sizing (was `actualIconSize + 1` width, `actualIconSize` height) - all textures now symmetric and centered
- Fixed flash/highlight textures using TOPLEFT anchor with 0.5px offset compensation - now properly centered
- **Debug Log Now Shows Spell Name**: "Non-DPS spell" filter message now includes spell name and ID for easier debugging

## [3.11] - 2026-01-25

### Fixed

- **Blue marching ants animation**: Fixed assisted combat glow (marching ants) not animating in combat
  - UIRenderer module was never loaded via LibStub in JustAC.lua
  - Added proper module loading and combat state propagation
  - Animation now correctly plays in combat, freezes out of combat
- **Secret value handling improvements**:
  - Fixed GCD cooldown detection with secret values in WoW 12.0+
  - Split GetSpellCooldown into raw (for UI widgets) and sanitized (for logic) versions
  - Fixed cooldown flicker by tracking lastCooldownWasSecret flag
  - Cooldown widgets handle secrets internally, Lua code uses sanitized values
- **Options blacklist persistence**: Fixed blacklistedSpells table not being initialized properly
- **Debug mode usability**: Removed extremely spammy macro parsing traces
  - Removed per-spell, per-command, and per-entry parsing debug messages
  - Kept useful messages: macro match results and specificity scores
  - Debug mode now much more readable while still showing important information

### Changed

- **Flash brightness**: Increased flash animation brightness (1.5, 1.2, 0.3 vertex color for ADD blend)

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
