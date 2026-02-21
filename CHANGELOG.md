# Changelog

## [3.26.2] - 2026-02-20

### Added

- **Nameplate Overlay** — Independent queue cluster that attaches directly to the target's nameplate. Fully separate from the main panel; either or both can be active at once. Includes DPS queue icons, defensive queue icons (opposite side), and a compact player health bar. Configurable anchor side, expansion direction (horizontal or vertical), icon count, icon size, glow mode, hotkey display, and per-section visibility. Overlay defensives operate independently of the main Defensive Suggestions setting.
- **Items in defensive queue** — Spell lists now accept equipped items (`-itemID` or `item:ID` syntax). Items display with an `[Item]` tag and correct icon/name in the editor. Auto-deduplication against hardcoded health potions.
- **Reset to Defaults buttons** — Each major options tab (General, Offensives, Overlay, Defensives) now has a section-scoped reset button. Spell lists and the blacklist are never affected.

### Changed

- Defensive suggestions enabled by default on new profiles
- BlizzardAPI library version bumped to v29

### Fixed

- Defensive icons remaining visible when "Enable Defensive Suggestions" is turned off (early-exit paths in OnHealthChanged bypassed the hide logic)
- Charge-based ability cooldown sweep bleeding outside icon border (SetDrawSwipe disabled on chargeCooldown; edge ring now matches Blizzard's own rendering)
- Target frame anchor not re-applied after loading screens or combat lockdown (UpdateTargetFrameAnchor now called on PLAYER_ENTERING_WORLD and PLAYER_REGEN_ENABLED)
- DPS icons invisible after icon refactor (alpha not reset on slot reuse)
- Defensive spells on cooldown permanently hidden in combat — cooldown swipe is now the visual indicator; visibility is no longer gated on cooldown state
- Rotation list positions 2+ permanently hiding spells on cooldown
- Cooldown swipe not re-shown when an icon slot is reused
- Icon background corner-clipping (rounded mask now applied to background as well as texture)
- Disabled spec profile not applied on login/reload until the user manually switched specs
- Defensive queue item deduplication: same item in multiple spell lists (selfheal + cooldown) could appear twice — cross-call check used negative key but callers marked positive key
- Defensive queue showing same ability twice when a talent replaces a base spell (e.g. Impending Victory replacing Victory Rush) — both the base ID and the talent ID passed availability checks and both appeared; fixed by resolving talent overrides via FindSpellOverrideByID in GetUsableDefensiveSpells and the ActionBarScanner proc injection path, so both share the same tracking key and only the active (talent) version is shown
- Options: Profiles tab had same `order = 4` as Defensives tab (undefined tab ordering)
- Options: Nameplate Overlay health bar was incorrectly gated on "Show Defensives" — users could not enable it independently
- Options: Standard queue settings (icon size, spacing, orientation, anchor, tooltips, opacity, fade, panel interaction) had no disabled state when Display Mode was Overlay-only or Disabled
- Options: Offensive settings had no disabled state when Display Mode was Overlay-only or Disabled

## [3.26.0] - 2026-02-20

### Added

- **Nameplate overlay: expansion direction setting** — New "Expansion Direction" dropdown: Horizontal (Out) chains icons away from the nameplate (original behaviour), Vertical Up stacks slot 2 above slot 1, Vertical Down stacks them downward. Anchor dropdown is now LEFT/RIGHT only (TOP/BOTTOM were mis-implemented as above/below the nameplate and have been removed).
- **Nameplate overlay: vertical health bar** — For Vertical Up/Down expansion the health bar renders as a thin vertical strip beside the icon column, spanning the full cluster height (26 px × 1 icon, 54 px × 2 icons, 82 px × 3 icons). Orientation is VERTICAL so fill direction matches the icon stack.
- **Nameplate overlay defensive display mode** — New "Defensive Visibility" dropdown in the Nameplate Overlay options: "In Combat Only" (default) or "Always". Previously the overlay defensives inherited the main defensive panel's `displayMode`. The overlay now has its own independent setting and calls `GetDefensiveSpellQueue` with an `overrideDisplayMode`.
- **Items in defensive queue** — Negative numbers in spell lists represent items (-itemID).
  - `BlizzardAPI.CheckDefensiveItemState(itemID, profile)` — validates item count and cooldown.
  - Options UI accepts `-itemID` or `item:ID` syntax in the manual input field.
  - Items display with `[Item]` tag and correct icon/name in the spell list editor.
  - `GetUsableDefensiveSpells` handles mixed spell/item lists, deduplicates with hardcoded potions.
  - `GetBestDefensiveSpell` returns `itemID, true` for item entries.
  - Backward compatible: existing positive-only spell lists work unchanged.

### Changed

- BlizzardAPI library bumped to v29.
- **Health bar color** — Overlay health bar now uses pure bright green `(0, 1, 0)` instead of the previous murky `(0.1, 0.8, 0.1)`, matching Blizzard's nameplate health bar saturation.
- **Health bar inset formula** — Replaced asymmetric `iconSize * 1.8 + (n-2)*spacing` with symmetric `clusterWidth - 2*inset` so both outer edges have equal inset.
- **healthBarPosition option** — Disabled when expansion is "out" (horizontal) instead of when anchor is LEFT/RIGHT. Only meaningful for vertical expansion.

### Fixed

- **Defensive overlay invisible after option change** — `UINameplateOverlay.Create` now calls `ForceUpdateAll()` after anchoring so icons render immediately without requiring a re-target.
- **DPS queue invisible after CreateBaseIcon refactor** — `CreateBaseIcon` was setting `button:SetAlpha(0)` at init; the DPS renderer only calls `icon:Show()` (not `fadeIn:Play()`), so icons were permanently invisible. Removed the alpha reset from `CreateBaseIcon`; defensive icons set alpha=0 themselves before playing fadeIn.
- **Defensive queue permanently hides spells on cooldown** — `CheckDefensiveSpellState` was calling `IsSpellOnRealCooldown` and returning `isUsable=false` for spells on CD. In combat cooldown duration is secret so we can never reliably detect expiry. Removed the gate; all known non-redundant defensives now appear with the cooldown swipe as the visual indicator.
- **Rotation list (positions 2+) permanently hides spells on cooldown** — Added `PassesRotationFilters` in SpellQueue.lua that checks availability and redundancy but skips `IsSpellUsable`/cooldown filtering. The rotation list now uses this function.
- **Cooldown swipe not re-shown when icon slot is reused** — `HideDefensiveIcon` and the DPS slot-clear path were calling `cooldown:Hide()` without resetting `_cooldownShown` / `_chargeCooldownShown` / `_cachedMaxCharges`. All three flags now reset in both clear paths.
- **Icon background corner-clipping** — `iconMask` was only applied to `iconTexture`, not `slotBackground`. Added `slotBackground:AddMaskTexture(iconMask)` so the background is also clipped.
- **Disabled spec profile not applied on login/reload** — `PLAYER_ENTERING_WORLD` now calls `OnSpecChange()` to apply the spec profile (including disabled state) on world entry.
- **Defensive icons/health bar could re-appear while spec-disabled** — `OnHealthChanged` now guards on `isDisabledMode` so live health changes can't undo the hide performed by `EnterDisabledMode`.

## [3.25.1] - 2026-02-17

### Fixed

- Critical: Crash on addon load caused by variable scoping error in defensive spell initialization (`defensiveAlreadyAdded` declared after use)
- Critical: Combat crash when spell procs are active (restored `IsImportantSpell` stub accidentally removed during cleanup)
- Suppressed single-button assistant warning when current spec is set to DISABLED in options

### Changed

- Internal: Unified spell info caching in BlizzardAPI (eliminated duplicate caches in SpellQueue and RedundancyFilter, ~35 lines consolidated)
- Internal: Removed ~90 lines of dead code and redundant abstractions (self-assignment exports, unused texture allocations, legacy stubs)
- Internal: Simplified proc sorting logic (removed unused "important proc" categorization, ~20 lines)
- Internal: Optimized defensive spell registration with table-driven iteration (4 loops → 1 loop)

## [3.25.0] - 2026-02-14

### Added

- Per-class defensive spell lists: profiles now store spell lists under `classSpells[playerClass]` so one profile works across all classes
- Class-colored header in Defensives options panel showing which class's spells are being edited
- Migration: existing flat spell lists (`selfHealSpells`/`cooldownSpells`/`petHealSpells`) automatically migrated to new structure on first load
- `GetClassSpellList(listKey)` helper for clean per-class spell access
- `/jac defensive` now shows current class name and pet heal count
- **Pet rez/summon system**: High-priority defensive icon when pet is dead (`UnitIsDead`) or missing (`!UnitExists`) — reliable in combat (not secret)
- `CLASS_PET_REZ_DEFAULTS` in SpellDB: Hunter (Revive Pet, Heart of the Phoenix, Call Pet 1), Warlock (all summon demons), Death Knight (Raise Dead)
- `BlizzardAPI.GetPetStatus()`: returns "dead", "missing", or "alive" using combat-safe APIs
- **Pet health bar**: Teal-colored StatusBar mirroring player health bar style, independently toggleable via `showPetHealthBar`
  - Auto-hides when no pet is active, shows red dead overlay when pet is dead
  - StatusBar accepts secret values — renders pet health visually even when exact % is hidden
  - Stacks above player health bar when both enabled, defensive icons offset correctly for both bars
- Pet Rez/Summon and Pet Heal priority list sections in Options panel (hidden for non-pet classes)
- `/jac defensive` now shows pet status, pet health %, pet rez spell count
- `AddSpellToList` nil guard for safety

### Changed

- Defensive spell lists are no longer stored at `profile.defensives.selfHealSpells` — they live under `profile.defensives.classSpells[CLASS].selfHealSpells`
- Profile copy/share now transfers visual settings (thresholds, icon count, display mode) while each class auto-populates its own defensive spells on first login
- Pet heal suggestions now require pet to be alive (dead/missing triggers rez spells instead)
- Pet heal threshold is best-effort: pet health is secret in combat, heals only suggested when health is readable
- Added inline code comments throughout explaining 12.0 secret limitations: thresholds are out-of-combat only, pet heals are out-of-combat only, pet rez/summon works in combat via UnitIsDead/UnitExists
- UIFrameFactory defensive icon offset accounts for both player and pet health bars when stacked

### Fixed

- Fixed duplicate spells in defensive queue: pet rez/heal now shares `defensiveAlreadyAdded` with player defensives (prevents e.g. Exhilaration appearing twice for Hunters)
- Fixed `petHealThreshold` fallback using wrong default (70 instead of profile default 50)
- Added `issecretvalue` guard in UIHealthBar `UpdatePet()` for consistency with `GetPetStatus()`

## [3.24.1] - 2026-02-12

### Changed

- RedundancyFilter: `GetCachedSpellInfo` now routes through SpellQueue's cache (avoids ~12 uncached `C_Spell.GetSpellInfo` calls per redundancy check)
- ActionBarScanner: Reuse `BlizzardAPI.GetAddon()` instead of duplicate `cachedAddon` local
- Updated "Show Hotkeys" tooltip descriptions in all 9 locales (removed stale "skips hotkey detection" claim)

### Removed

- Deleted deprecated root `Locale.lua` (only `Locales/*.lua` files are loaded)

## [3.24.0] - 2026-02-12

### Added

- Separate "Key Press Flash" toggles for offensive and defensive queues

### Changed

- ActionBarScanner: Extract `CacheHotkey` helper in `GetSpellHotkey` (reduces code duplication)
- ActionBarScanner: `ClearAllCaches` now also clears `abbreviatedKeyCache` (fixes stale gamepad icons on style change)
- ActionBarScanner: Minor code cleanup (cached addon lookup, remove unused upvalues, remove shadowed locals, remove redundant debug function)

### Fixed

- Gamepad modifier keys showing "S" prefix instead of trigger icons when used with shoulder buttons

## [3.23.0] - 2026-02-12

### Added

- Simplified Chinese (zhCN) and Traditional Chinese (zhTW) locale support
- 56+ missing translation keys added to all existing locales (deDE, frFR, ruRU, esES, esMX, ptBR) covering gamepad icons, spell search UI, panel interaction, defensive display modes, visibility toggles, and profile switching

### Changed

- Split single Locale.lua into per-language files under Locales/ folder for easier maintenance and community contributions

### Fixed

- Removed dead/outdated locale keys (Cooldown Threshold, Debug Mode, About, Slash Commands) from older translations
- Removed duplicate key definitions within locale sections
- Added missing `UI Scale` translation to esMX and ptBR
- Added missing `Clear All` translation to zhCN

## [3.22.0] - 2026-02-11

### Added

- **Target Frame Anchor:** New option to attach the spell queue to the default target frame (Top/Bottom/Left/Right). Anchor persists even when target frame is hidden. Dragging detaches, re-enable in General → Icon Layout. Localized in all 7 languages.

## [3.21.7] - 2026-02-11

### Fixed

- **Fix crash opening hotkey override dialog**: `OpenHotkeyOverrideDialog` was calling `addon:GetCachedSpellInfo()` (doesn't exist) instead of `SpellQueue.GetCachedSpellInfo()` — right-clicking a spell icon to set a custom hotkey caused an error
- **Fix glow animations not pausing/resuming on combat state change**: `PauseAllGlows` and `ResumeAllGlows` were called without the required `addon` argument at 4 call sites, so they silently did nothing

## [3.21.6] - 2026-02-11

### Changed

- **Removed section summaries from Offensives/Defensives tabs**: Info descriptions at top of each tab removed — settings are self-explanatory
- **Compact About panel**: Replaced verbose feature list with concise one-liner; removed console command instructions (assisted combat is on by default in 12.0)
- **About version now reads from TOC**: Uses `C_AddOns.GetAddOnMetadata` instead of stale `db.global.version` default

### Removed

- Console command references from About panel and debug output (`assistedMode`, `assistedCombatHighlight` CVars are on by default in 12.0)
- Stale `db.global.version = "2.6"` default (was never updated, About panel now reads TOC version)
- CVar validation from `BlizzardAPI.ValidateSetup()` and "Quick Fix Commands" from `/jac test` output

## [3.21.5] - 2026-02-11

### Changed

- **Defensive queue and health bar disabled by default**: New profiles start with defensives off and health bar hidden — enable in Defensives tab if desired
- **Clear All buttons for blacklist and hotkey overrides**: Both panels now show a "Clear All" button (with confirmation) when entries exist
- **Removed health bar color gradient**: Bar stays green with red background showing missing health (gradient didn't work with secret health values)

### Fixed

- **Fix `IsShown` crash in `HideDefensiveIcon`**: Was passing addon object (`self`) instead of defensive icon frame — caused 57+ errors per second during health updates
- **Fix `ShowDefensiveIcon` silently failing**: Two call sites were missing the required `defensiveIcon` frame parameter, so defensive icons never displayed when health dropped or hotkey overrides changed
- **Fix health bar toggle in options**: Was calling nonexistent `UIHealthBar.DestroyHealthBar()` instead of `UIHealthBar.Destroy()` — toggling health bar off in settings had no effect
- **Fix default mismatches in Options panel**: `maxIcons` fallback was 5 (should be 4), `iconSpacing` fallback was 2 (should be 1), causing options sliders to show wrong values on fresh profiles
- **Fix profile migration on profile switch**: `RefreshConfig` now calls `NormalizeSavedData()` so switching to an older profile properly migrates string-keyed spell IDs, profile-level blacklists, and `panelLocked` boolean
- **Fix profile reset wiping character data**: `OnProfileReset` no longer clears blacklist and hotkey overrides, which are character-specific and should persist across profile operations

### Removed

- Dead variable `defensivePosition` in `UIHealthBar.CreateHealthBar` (assigned but never read)
- `BlizzardAPI` import from `UIHealthBar` (only used by removed gradient code)
- **Threshold sliders from Defensives options**: Self-heal, cooldown, and pet heal threshold settings hidden from UI (health values are secret in 12.0+, making user-configured thresholds non-functional); defaults still used internally

## [3.21.4] - 2026-02-11

### Added

- **Highlight Mode Dropdown**: Replaced `Highlight Primary Spell` toggle with a dropdown offering granular glow control
  - Both Offensive and Defensive tabs now have independent `Highlight Mode` dropdowns
  - Options: All Glows (default), Primary Only, Proc Only, No Glows
  - "Insert Procced Abilities/Defensives" toggles remain separate (control queue content, not visuals)
  - Backwards compatible: existing `focusEmphasis = false` migrates to "Proc Only" mode

### Changed

- **Code Cleanup**: Removed orphaned locale strings and deduplicated spell data
  - Deduplicated `RAID_BUFF_SPELLS` from `UNIQUE_AURA_SPELLS` in RedundancyFilter (programmatic merge instead of manual copy)
  - Fixed locale bug: "Restore Defaults" button for cooldowns was showing self-heal description (duplicate key overwrite)
  - Removed 9 orphaned locale keys across all 7 languages (Display Behavior, Visual Effects, Stabilization Window, etc.)

- **Options Reorganization**: Moved `Max Icons` from General tab to Offensives Display section (it only affects the offensive queue)

- **SpellDB Reclassification**: Removed 5 DPS abilities from `DEFENSIVE_SPELLS` so they appear in the offensive queue
  - Blooddrinker (Blood DK damage channel), Fel Devastation (Vengeance DH core rotational AoE)
  - Seraphim (Prot Paladin DPS cooldown), Odyn's Fury and Thunderous Roar (Warrior damage CDs)
  - None of these were in `CLASS_SELFHEAL_DEFAULTS` or `CLASS_COOLDOWN_DEFAULTS`, so defensive sidebar is unaffected

### Fixed

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

## [3.21.2] - 2026-02-05

### Fixed

- **Flash animation scaling bug**: Fixed OnUpdate handler stacking that caused spell flash to grow uncontrollably on rapid key presses (sentinel value pattern prevents re-wrapping)
- **Spec change cache invalidation**: Profile switch via spec change now properly invalidates spell, macro, and hotkey caches (early return was skipping cache clears)
- **Health bar in disabled mode**: Health bar now hides when entering disabled mode and restores when exiting

### Changed

- **Options panel reorganization**: Offensive and Defensive tabs now mirror each other with parallel section structure (Queue Content → Display → unique sections)
- **Gamepad Icon Style**: Moved from Icon Layout to Appearance section in General tab (visual setting, not spatial layout)

## [3.21.1] - 2026-02-04

### Fixed
- **Aura filtering consistency (RedundancyFilter v36)**: Fixed aura recast suggestions appearing during long combat
  - Adaptive cache expiration: Recent validation (<5 min) uses actual expiration time; older validation uses conservative 80% threshold
  - Prevents hour-long buffs (poisons, imbues) from reappearing mid-combat during persistent boss fights
  - All duration calculations done out of combat to avoid arithmetic on WoW 12.0 secret values

## [3.21.0] - 2026-02-04

### Added
- **Key press flash**: Icons flash gold when their hotkey is pressed for visual feedback
- **Separate hotkey toggles**: Individual "Show Hotkeys" options for Offensive and Defensives sections
  - Performance benefit: disabling skips hotkey detection for that section only
- **Insert Procced Defensives option**: Toggle to control procced defensives (Victory Rush, free heals) at any health

### Changed
- **Options reorganization**: Moved "Primary Spell Scale" from General to Offensive section (offensive-only setting)
- **Threshold note shortened**: More concise threshold fallback description
- **Options preservation**: Fixed threshold settings and new toggles being removed during dynamic updates

### Fixed
- **Profile switching**: Fixed queue appearing when switching to healer spec marked as "DISABLED"
- **Flash animation growth**: Fixed key press flash growing larger over time due to cumulative scale bug
- **Critical timer allocation fix**: Fixed `C_Timer.After` being called every frame in glow animations, causing massive GC pressure
- **Major performance fix**: Reduced in-combat CPU usage from ~34% to near-zero
  - Early-exit checks when frame hidden (mounted, out of combat, etc.)
  - Removed expensive `IsSpellOnRealCooldown` check (200+ API calls per update)
  - Added `filterResultCache` to prevent re-checking same spell multiple times
  - Pooled frequently allocated tables to reduce GC stutter
- **Gamepad keybind optimization**: Fixed ~100% CPU overhead when gamepad mode enabled
  - `CalculateKeybindHash()` now computed once instead of every validation check
- **Hotkey lookup rate-limiting**: Eliminated expensive action bar scanning (100+ slots) on every frame
  - Full lookups rate-limited to max 4x/sec, cached values returned immediately
- **UIRenderer throttling**: Major reduction in per-frame API calls
  - Added 0.15s throttle for cooldown updates (cooldown swipe animates smoothly once set)
  - Throttled range checks, cached hotkey normalization
  - Visual state caching (tinting, desaturation) - only updates when state changes

### Removed
- **Mobility feature**: Gap closer feature removed entirely
  - `C_Spell.IsSpellInRange()` returns secret values in WoW 12.0+ combat, making it unreliable
  - Removed Options tab, profile settings, locale strings, SpellQueue integration

## [3.2] - 2026-01-31

### Added
- **Gamepad keybind support**: Full gamepad/controller button display using native WoW atlas textures
  - D-pad, face buttons (PAD1-6), shoulders/triggers, stick clicks + directions, paddles, system buttons
  - **New option "Gamepad Icon Style"** in General settings: Generic (1/2/3/4), Xbox (A/B/X/Y), PlayStation (Cross/Circle/Square/Triangle)
  - Uses `_64` atlas with proper button outline matching WoW's default keybind display
  - Pixel-perfect positioning with 1px right/down offset

- **Extended keyboard keybind abbreviations**:
  - Numpad special keys: NUMPADDIVIDE→N/, NUMPADMULTIPLY→N*, NUMPADMINUS→N-, NUMPADPLUS→N+, etc.
  - Arrow keys, navigation keys, punctuation (TAB, ENTER, PAUSE, brackets, etc.)

### Changed
- **ActionBarScanner v32**: Extended keybind abbreviation with full keyboard and gamepad support
- **UIRenderer v10**: Enhanced hotkey normalization for flash animation matching on all key types
- **Delayed keybind refresh**: Added 0.3s follow-up invalidation to catch late-committed gamepad binding changes

## [3.199] - 2026-01-31

### Added
- **Options:** "Require Hostile Target" checkbox is now disabled when "Hide Out of Combat" is enabled
  - These options are redundant together since hideQueueOutOfCombat hides the frame before the hostile target check runs
  - Description updated to explain the relationship

### Changed
- **UIRenderer v10**: Optimized rendering loop when auto-hide features are active
  - Skips expensive rendering operations (hotkey lookups, icon updates, glow animations) when frame is hidden
  - Still processes queue building and cache updates to ensure instant response when frame becomes visible
  - Maintains warm caches for redundancy filter, aura tracking, and spell info
  - Applies to: hideQueueOutOfCombat, hideQueueForHealers, hideQueueWhenMounted, requireHostileTarget

### Fixed
- **UIRenderer v10**: Fixed large highlight frame bug appearing over backup abilities when auto-hide features are enabled
  - Now properly stops all glow animations (assisted, proc, defensive) when frame should be hidden
  - Prevents highlight frames from scaling incorrectly during auto-hide transitions
  - Skips icon updates entirely when `shouldShowFrame = false` to avoid frame state inconsistencies

## [3.198] - 2026-01-30

### Changed
- **UIRenderer v34**: CPU optimization improvements for high icon counts
  - Eliminated redundant IsSpellProcced calls to ActionBarScanner
  - Replaced pcall closures with direct issecretvalue checks (cooldown, charge display)
  - Cached "Waiting for" pattern on spellChanged instead of every frame
  - Throttled IsSpellUsable per-icon to 0.25s interval (reduced from 60fps)
  - Track panelLocked state to skip RegisterForClicks when unchanged
  - Removed duplicate defensive icon cooldown updates
  - Added explicit secret value handling for range detection (C_Spell.IsSpellInRange)

- **RedundancyFilter v36**: Edge-case safety for in-combat logins
  - Add fail-open behavior when trusted cache unavailable (no pre-combat snapshot)
  - Only filter non-DPS spells if cache exists; allow through if no trusted data
  - Prevents false negatives during combat login scenarios

- **SpellDB v18**: Spell classification accuracy sweep
  - Remove damage/hybrid spells from HEALING_SPELLS: Cone of Cold, Purge the Wicked, Death Strike, Drain Life, Grimoire of Sacrifice, Penance, Soul Cleave, Immolation Aura, Reaver, Fracture, Expel Harm
  - Remove pet maintenance from HEALING_SPELLS: Mend Pet, Revive Pet (now offensive, DPS-critical)
  - Remove DPS gap closer from UTILITY_SPELLS: Shadowstep (now offensive)
  - Remove damage-dealing spells from CROWD_CONTROL_SPELLS: Rake (bleed DoT), Holy Word: Chastise variants
  - Remove speed-boosting ability from UTILITY_SPELLS: Chi Torpedo

## [3.197] - 2026-01-29

### Added
- **Per-Spec Profile Selection**: Automatic profile switching based on specialization
  - Enable/disable via "Auto-switch profile by spec" toggle in Profiles section
  - Assign different profiles to each spec, or set to "(Disabled)" to hide addon for that spec
  - Healer specs are automatically set to "disabled" by default on first run
  - Profile switching occurs when changing specs or logging in

### Changed
- **Options.lua**: Removed verbose instructions from Profiles section to save vertical space
  - Clear description fields for desc, descreset, choosedesc, copydesc, deldesc, resetdesc
  - Maintains functionality while reducing UI clutter

## [3.195] - 2026-01-29

### Changed
- **RedundancyFilter v35**: Add alternate aura IDs from 12.0 Midnight Exclusion Whitelist
  - Add alternate IDs for group buffs: Mark of the Wild (264778), Power Word: Fortitude (264764), Battle Shout (264761)
  - Fix mislabeled 264761 (Battle Shout alternate, not Blessing of the Bronze)
  - Add Frostbrand Weapon (196834) and Earthliving Weapon (382021) to shaman imbues
  - Clean up poison buff IDs to match whitelist exactly

## [3.194] - 2026-01-29

### Changed
- **RedundancyFilter v34**: Poison detection - cast-based inference for 12.0 compatibility
  - Use UNIT_SPELLCAST_SUCCEEDED for primary detection (not aura API)
  - Poisons are hour-long buffs (Category A) - safe for cast-based inference
  - Include both cast IDs and possible buff IDs for fallback detection
  - Preserve trusted aura cache in combat (don't wipe on UNIT_AURA)
  - Three-tier detection: cast tracking > aura cache by ID > aura cache by name

### Changed
- **DebugCommands.lua**: Updated poison detection debugging commands
  - Enhanced `/jac poison` command for testing cast-based inference

## [3.15] - 2026-01-27

### Added
- **BlizzardAPI v26**: API-specific secret helpers for incremental 12.0 compatibility
  - `GetCooldownForDisplay(spellID)` - Returns start, duration (nil if secret)
  - `IsSpellReady(spellID)` - Boolean usability check, fail-open if secret  
  - `GetAuraTiming(unit, index, filter)` - Returns duration, expiration (field-level checks)
  - `GetSpellCharges(spellID)` - Returns current, max charges (field-level checks)
  - Purpose-specific helpers check only needed fields as Blizzard releases API access incrementally

- **MacroParser v21**: [stealth] and [combat] conditional evaluation
  - Implemented `[stealth]`, `[nostealth]`, `[combat]`, `[nocombat]` conditional checks
  - Fixes Rogue/Druid keybind detection for macros like `/cast [stealth] Cheap Shot; Sinister Strike`

### Changed
- **UIRenderer v9**: Migrated to centralized secret handling and Blizzard's cooldown logic
  - All secret checks now use `BlizzardAPI.IsSecretValue()`
  - Using API-specific helpers for field-level granularity (30+ call sites simplified)
  - Refactored to use Blizzard's ActionButtonTemplate cooldown logic (mimics ActionButton_UpdateCooldown)
  - Removed manual GCD/cooldown management, now using C_Spell APIs directly like Blizzard

- **RedundancyFilter v25**: Migrated to centralized secret handling  
  - All secret checks now use `BlizzardAPI.IsSecretValue()`
  - Using `GetAuraTiming()` for field-level aura access
  - Allows partial aura data when some fields are secret (best-effort processing)

- **Options.lua**: Migrated to centralized secret handling and added configurable health thresholds
  - Cooldown display now uses `BlizzardAPI.IsSecretValue()`
  - All spell info lookups use `BlizzardAPI.GetSpellInfo()` for consistent secret handling
  - Removed redundant LibStub lookups inside functions
  - Added configurable health thresholds: selfHealThreshold, cooldownThreshold, petHealThreshold

- **DebugCommands.lua**: Migrated to centralized secret handling
  - Health API status now uses `BlizzardAPI.IsSecretValue()`

- **UIFrameFactory v10**: Refactored cooldown frames to match Blizzard's ActionButtonTemplate
  - Separate cooldown and chargeCooldown frames (matching Blizzard's structure)
  - Smaller, more transparent countdown numbers to avoid overlapping hotkey text

- **JustAC.lua**: Added configurable health thresholds for defensive spells
  - Self-heal threshold (default 80%), cooldown threshold (default 60%), pet heal threshold (default 50%)
  - Uses exact health when available, falls back to LowHealthFrame overlay when secret

### Removed
- **Code consolidation**: Removed duplicate `SafeGetSpellInfo` implementations (-18 lines)
  - Deleted from MacroParser.lua - now uses `BlizzardAPI.GetSpellInfo()`
  - Deleted from FormCache.lua - now uses `BlizzardAPI.GetSpellInfo()`
  - All spell info access consolidated through BlizzardAPI for consistent secret handling

- **RedundancyFilter**: Removed unused debug variables (-3 lines)
  - Deleted unused `lastDebugPrintTime` table
  - Deleted unused `DEBUG_THROTTLE_INTERVAL` constant

### Fixed
- **MacroParser v21**: Removed dead code (-12 lines)
  - Deleted `SafeIsMounted()` - defined but never called
  - Deleted `SafeIsOutdoors()` - defined but never called

### Performance
- **Comment cleanup**: Condensed verbose comments across 4 core modules (-80 lines)
  - Removed multi-line explanations that restated obvious code
  - Kept all operational guidance and critical API compatibility notes
  - MacroParser, BlizzardAPI, UIRenderer, RedundancyFilter now more concise

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
