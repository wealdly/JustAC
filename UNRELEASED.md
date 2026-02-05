# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.21.0

**Instructions:**
- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

### Added

### Changed

### Fixed
  - `StartAssistedGlow`: Set `assistedAnimPaused` flag immediately before scheduling timer, not inside callback
  - `StartDefensiveGlow`: Added missing `defensiveAnimPaused` flag tracking (previously scheduled new timer every frame when out of combat)
  - Root cause of hitching even out of combat with JAC enabled

- **Major Performance Fix (SpellQueue v31)**: Reduced in-combat CPU usage from ~34% to near-zero
  - Added early-exit checks in `GetCurrentSpellQueue()` when frame should be hidden (mounted, out of combat with hideQueueOutOfCombat enabled, etc.)
  - Removed expensive `IsSpellOnRealCooldown` check from `IsSpellUsable()` - was doing 8+ API calls per spell, multiplied by 20-30 spells per update = 200+ API calls every 0.1s
  - Added `filterResultCache` to cache `PassesSpellFilters()` results per update cycle - prevents re-checking the same spell multiple times
  - Cooldown visibility now relies solely on the cooldown swipe (visual indicator) instead of pre-filtering

- **GC Pressure Reduction**: Pooled frequently allocated tables to reduce garbage collection stutter
  - `OnHealthChanged`: Added 100ms throttle for defensive queue updates (UNIT_HEALTH fires multiple times per second in combat)
  - `SpellQueue.GetCurrentSpellQueue()`: Pooled `addedSpellIDs` and `recommendedSpells` tables (previously allocated every 30-150ms)
  - `GetDefensiveSpellQueue()`: Pooled `alreadyAdded` and `dpsQueueExclusions` tables

- **Architectural Optimizations**: Reduced redundant work through caching and dirty flags
  - Increased aura cache duration from 0.2s to 0.5s (60% fewer aura API calls, UNIT_AURA events still invalidate)
  - Removed repeated LibStub lookups in hot path defensive functions (use module-level cached refs)
  - Added dirty flag system: OnUpdate uses longer intervals (0.5s) when idle, immediate updates on events
  - Events (proc, target change, spellcast) now mark queues dirty for responsive updates

- **Advanced Optimizations**: Eliminated closure creation and reduced string operations
  - Key press detector: Inlined hotkey matching (was creating closure on every keypress)
  - OnUpdate early exit: Skips all work when UI is completely hidden (saves CPU when mounted)
  - Gamepad check: Quick "PAD" substring pre-check avoids 11 string.find() calls for keyboard binds

- **OnUpdate Loop Optimization**: Reduced per-frame overhead significantly
  - Fast path: Early exit at top of OnUpdate when within throttle interval (most common case)
  - Cached `assistedCombatIconUpdateRate` CVar lookup (was calling GetCVar every frame, now every 5s)
  - Pre-cached function references at frame creation time to avoid table lookups in hot path
  - `StartAssistedGlow`/`StartDefensiveGlow`: Skip redundant setup work when already in correct state
  - `IsSpellProcced`: Added per-update cache to avoid redundant API calls across multiple icons

- **UIRenderer Throttling (v10)**: Major reduction in per-frame API calls while preserving responsiveness
  - Added `COOLDOWN_UPDATE_INTERVAL = 0.15s` throttle for cooldown updates (6-7x/sec instead of 33x/sec)
  - Cooldown swipe animates smoothly once `SetCooldown` is called - no need to update every frame
  - Throttled `C_Spell.IsSpellInRange` checks - range rarely changes faster than 0.15s
  - Cached hotkey normalization - string operations (upper, gsub) only run when hotkey actually changes
  - Proc glows check every frame (cheap cache lookup) for instant feedback when abilities proc
  - Resource/usability checks synced with cooldown throttle (0.15s) for responsive blue tint

- **BlizzardAPI Caching (v27)**: Reduced redundant API calls in SpellQueue and UIRenderer
  - `GetDisplaySpellID`: Now caches `C_Spell.GetOverrideSpell` results per update cycle (was called 10-20+ times per update with no caching)
  - Override cache cleared with proc cache each update cycle

- **Gamepad Keybind Optimization (ActionBarScanner v33)**: Fixed ~100% CPU overhead when gamepad mode enabled
  - `CalculateKeybindHash()` was iterating through all binding strings and hashing each character on EVERY cache validation check
  - With gamepad enabled, binding strings are longer ("SHIFT-PAD1" vs "1"), causing O(n*m) overhead where n=bindings, m=string length
  - Now computes hash ONCE when rebuilding binding cache, stores result in `cachedBindingHash`
  - Reduces per-lookup cost from O(bindings * avg_length) to O(1)
  - `AbbreviateKeybind()` caching already in place - this fixes the validation path
  - Gamepad CPU overhead reduced from ~8% to near-zero

- **Hotkey Lookup Rate-Limiting**: Eliminated expensive action bar scanning on every frame
  - `GetSpellHotkey()` now returns cached values immediately, even when cache marked "invalid"
  - Full lookups (`FindSpellInActions` iterating 100+ slots) rate-limited to max 4x/sec
  - Stale hotkey values are usually correct anyway (keybinds rarely change mid-combat)
  - Reduces per-icon CPU from O(100 slots) to O(1) for 99% of frames

- **UIRenderer Visual State Caching**: Eliminated per-frame UI API calls
  - Cached `SetTextColor` for range indicator - only updates when out-of-range state changes
  - Cached `SetDesaturation`/`SetVertexColor` for icon tinting - only updates when visual state changes (channeling/no-resources/normal)
  - Reduced UI API calls from ~100/frame to ~5/frame during stable combat

### Removed

- **Mobility Feature**: Removed the gap closer feature entirely
  - `C_Spell.IsSpellInRange()` returns secret values in WoW 12.0+ combat, making range detection unreliable
  - Feature's value was primarily in combat where range detection doesn't work
  - Removed: Options tab, profile settings, locale strings, SpellQueue insertion, RedundancyFilter check
  - Removed: `CLASS_MOBILITY_DEFAULTS`, `CLASS_PETMOBILITY_DEFAULTS`, `IsMobilitySpell()`, `IsInMeleeRange()`

### Added

- **Key Press Flash**: Visual feedback when pressing keybinds - icons flash gold when their hotkey is pressed
  - Monitors key presses and matches against visible queue and defensive icons
  - Uses pooled table to avoid GC allocations on every key press
  - Smart logic to avoid flashing spells that just moved positions (e.g., after casting slot 1)
  - Grace period for slot 1: flashes even when spell changes right as you press the key
