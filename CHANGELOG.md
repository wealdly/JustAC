
# Changelog

## [Unreleased]

## [4.8.5] - 2026-03-08

### Fixed
- RedundancyFilter: Poisons with <10 min remaining were still being filtered out of combat (FALLBACK 2 by-name check bypassed the expiry threshold)
- RedundancyFilter: Maintenance buffs (poisons, imbues, raid buffs, rites) now always filtered in combat — DPS takes priority

### Performance
- RedundancyFilter: Skip full aura scan in combat using `C_Secrets.ShouldAurasBeSecret()` pre-check (avoids 40 pcall iterations when all fields are known secret)
- SecretValues: Short-circuit `TestAuraAccess()` with `C_Secrets.ShouldAurasBeSecret()` (skip 5-aura probe loop in combat)
- StateHelpers: Skip per-value `IsSecretValue()` calls in `GetPlayerHealthPercent()` when `C_Secrets.HasSecretRestrictions()` is false (out-of-combat fast path)

## [4.8.4] - 2026-03-08

### Fixed
- Charge-based abilities no longer show a stationary yellow cooldown sweep — `SetCooldown` with `duration==0` or an already-expired cooldown (stale `startTime+duration` from the last GCD/recharge) parks the sweep at 12 o'clock; both cases now call `Clear()` instead
- Same expiry check applied to the charge-recharge ring (`chargeCooldown` widget)
- Both fixes guard against 12.0 secret values: opaque `startTime`/`duration` are passed through to `SetCooldown` (which handles them internally) rather than being compared
- Fixed cooldown sweep (yellow) getting stuck at 12 o'clock when spell comes off cooldown out of combat — now uses `dur:IsZero()` to detect finished cooldowns and calls `Clear()` instead of `SetCooldownFromDurationObject` with a zero-duration object (applies to both main and charge cooldown paths)
- Fixed `IsZero()` crash in combat — `IsZero()` is secret in combat; gate with `HasSecretValues()` (NeverSecret) to only call `IsZero()` when duration object has no secrets
- Fixed cooldown sweeps bleeding onto wrong icons during queue re-ordering (e.g. combat exit) — proactively `Clear()` stale cooldown widget when the spell identity on a button changes
- Fixed nameplate overlay showing yellow gap-closer crawl instead of blue assisted crawl when Blizzard recommends a gap-closer spell at position 1 — overlay now matches standard queue behavior (only synthetically injected spells get gap-closer glow)
- Fixed gap-closer priority not iterating to lower-tier spells when a higher-tier gap closer is out of range — all gap-closer candidates now validate range so out-of-range spells fall through (e.g. Shadowstep out of 25yd range → Sprint)
- Fixed gap-closer spells in macros (e.g. Sprint in `/use [mod]Item;Sprint`) never being suggested — simplified TryGapCloserCandidate to known + cooldown + range only; removed action-bar-slot gate and fail-closed usability check that rejected valid spells (especially in combat with secret values)
- Fixed gap-closer injection overriding Blizzard's #1 recommendation when the primary spell is already in range (e.g. AoE abilities with no range check) — now checks IsActionInRange on the primary spell's slot before injecting

## [4.8.3] - 2026-03-08

### Added
- Live-search popup (persistent floating frame) for all spell/item selection panels — replaces the broken AceConfig `input+select` pattern that lost EditBox focus on every keystroke
- Items (trinkets, on-use gear, bag items) now searchable in the Offensive blacklist, consistent with defensive spell lists
- Spellbook cache invalidated automatically on specialization change and `SPELLS_CHANGED`

### Changed
- Spellbook cache pre-computes `nameLower` and `idStr` at build time — eliminates per-keystroke string allocations during search
- Search popup uses `TOOLTIP` frame strata to always render above the WoW Settings panel
- Shared spell-search logic extracted into a private helper — `GetFilteredResults` and `GetFilteredSpellbookSpells` no longer duplicate the scan loop
- Removed dead options code: `filterState` table, unused `previewState` entries, `LookupSpellByName`, `CreateAddSpellInput`, orphaned `AceConfigRegistry` reference in SpellSearch

## [4.8.2] - 2026-03-07

### Added
- Sound Test button next to the Interrupt Alert sound dropdown — preview the selected sound without leaving the options panel

## [4.8.1] - 2026-03-07

### Fixed
- Overlay Reset to Defaults now correctly resets expansion direction to "down" (was incorrectly set to "out")
- Locales: Removed 30 dead/orphaned keys from all 8 non-English locale files
- Locales: Added 7–12 missing translation keys per locale (Grey Out While Casting/Channeling, Queue Visibility, Settings, Reset desc keys)
- Locales: All 9 locale files now have exactly 230 keys with 0 dead and 0 missing

## [4.8.0] - 2026-03-07

### Added
- Nameplate Overlay: First Icon Scale setting (scale the primary icon independently)
- Nameplate Overlay: Queue Icon Desaturation setting (desaturate non-primary icons)
- Nameplate Overlay: Show Pet Health Bar toggle (parity with Standard Queue)
- General tab: Offensive Queue section (Include Macro-Hidden Abilities, Insert Procced Abilities, Allow Item Abilities)
- General tab: Defensive Queue section (Insert Procced Defensives, Allow Items in Spell Lists, Auto-Insert Health Potions)

### Changed
- Nameplate Overlay: Max offensive/defensive icons increased from 5 to 7 (slider instead of dropdown)
- Options: Moved 6 cross-queue content toggles from Offensive/Defensives tabs to General tab
- Options: Removed Queue Content sub-tabs from Offensive and Defensives tabs
- Options: Defensives tab no longer uses sub-tab layout (flattened to single page)
- Options: Unified setting names across Standard Queue and Overlay (Icon Size, Max Icons, Queue Visibility, etc.)
- Options: "Enable Defensive Suggestions" renamed to "Show Defensive Icons" for consistency
- Options: Moved Icon Labels and Hotkey Overrides into General as sub-tabs (Settings, Icon Labels, Hotkeys)
- Options: Top-level tab count reduced from 7 to 5 (General, Standard Queue, Overlay, Offensive, Defensives)
- Locales: Cleaned up 10 orphaned locale keys, added Show Defensive Icons and Defensive Queue translations

### Removed
- Overlay-only fallback: standard queue no longer force-shows when overlay can't find a nameplate (was causing standard queue to persist permanently in overlay-only mode)

## [4.7.5] - 2026-03-07

### Fixed
- Defensive icon proc glow now re-evaluated every frame (was only set on queue rebuild, causing 0.1–0.5s stagnation)
- Defensive icon hotkeys now refresh when bindings change and retry empty results for proc override propagation (was only set once on queue rebuild)
- Defensive icon cooldown swipes now polled at the same 0.08s cadence as offensive icons, so CD resets from talent procs clear promptly
- Removed dead `UpdateDefensiveCooldowns()` comment that claimed it was called externally (it was never called)
- Range check (out-of-range red text) now updates per-frame instead of every 0.08s across all queues (main panel offensive, interrupt, and nameplate overlay)
- Usability/resource tinting (blue desaturated state) now updates per-frame instead of every 0.08s across all queues (main panel offensive, interrupt, and nameplate overlay)
- Position stabilization: offensive queue positions 2+ now hold their spell for 150ms before allowing replacement, preventing rapid icon cycling from proc/CD re-categorization (position 1 always passes through the Blizzard assistant suggestion immediately)
- Glow hysteresis: glow animations on positions 2+ require 100ms of stable desired state before switching, preventing jarring animation restarts from transient proc toggles (main panel, nameplate overlay, and defensive icons)

## [4.7.4] - 2026-03-07

### Added
- **Grey Out While Casting** option (General tab, on by default) — queue icons desaturate during hardcasts. The spell being cast stays full color. Applies to both standard queue and nameplate overlay.
- **Grey Out While Channeling** option (General tab, on by default) — the previously hardcoded channeling grey-out is now toggleable. The channeled spell stays full color with a fill animation.

### Changed
- Early ungrey threshold reduced from 200ms to 100ms — icons regain color closer to the end of a cast/channel for tighter timing.

## [4.7.3] - 2026-03-07

### Fixed
- Interrupt reminder now works correctly when third-party nameplate/target frame addons (Platynator, etc.) hide or replace the Blizzard cast bar. Previously, non-interruptible casts could incorrectly show the interrupt icon because the interruptibility check depended on visually inspecting the Blizzard cast bar's shield widget. The event tracker now reads `notInterruptible` directly from the API at cast start, making it self-sufficient.
- Cast aura icon on interrupt reminder now falls back to UnitCastingInfo/UnitChannelInfo when the Blizzard cast bar is hidden by third-party addons (both standard queue and overlay).
- Overlay interrupt icon in horizontal mode no longer overlaps the nameplate — now pops out above the first DPS icon instead of inline.
- Overlay defensive queue now rebuilds on periodic checks (every 0.5s) instead of only updating cooldown swipes. Icons for "always" and "combatOnly" display modes now appear promptly when cooldowns expire.
- Overlay defensive queue now includes pet rez/summon and pet heal spells (parity with main panel).
- Overlay hotkey caches now invalidate on binding changes (parity with main panel).
- Overlay defensive icons in "always" mode now appear and disappear instantly (no fade animation), matching DPS icon behavior. State-driven modes ("combatOnly", "healthBased") retain the fade-in/out for smooth transitions.
- Overlay health bar no longer re-anchors every tick — only repositions when the visible defensive icon count changes, eliminating visual flicker in vertical orientations.
- Overlay health bar in vertical expansion modes no longer starts at the wrong position (above icons) and jumps to the correct side position — it now always appears at the correct expansion-aware position immediately.
- Overlay health bar now shows immediately with correct health values when a nameplate appears — no longer requires a subsequent update tick to fill in.
- Overlay defensive icons in "always" mode no longer appear ~500ms later than DPS icons when targeting a mob out of combat for the first time.
- Overlay defensive icons no longer lag behind DPS icons by 1+ frames — defensive overlay now refreshes on the same update tick as the offensive overlay.

### Added
- Nameplate Overlay **Offensive Display** tab now includes a **Queue Visibility** dropdown ("Always", "In Combat Only", "Require Hostile Target") and a **Hide When Mounted** toggle. These settings are independent from the Standard Queue visibility options.

### Changed
- Unified update cycle architecture: all rendering now flows through a single OnUpdate loop. `ForceUpdate()`/`ForceUpdateAll()` set dirty flags instead of rendering synchronously, eliminating redundant mid-event renders.
- Removed redundant dual-path rendering in `OnProcGlowChange`, `OnTargetChanged`, `OnSpellcastSucceeded`, and `OnCooldownUpdate` — each now uses a single `ForceUpdateAll()` call.
- SpellQueue internal throttle aligned with main loop minimums (combat: 0.03s, OOC: 0.05s) so it never bottlenecks CVar-driven update rates.
- CVar `assistedCombatIconUpdateRate` changes now take effect immediately (invalidate cached rate on CVAR_UPDATE).

## [4.7.2] - 2026-03-06

### Fixed
- **Defensive queue hidden on first load after update** — Defensive icons were invisible until the user toggled the setting off/on. Two causes: (1) `SPELLS_CHANGED` didn't mark the defensive queue dirty, so even after spell APIs became available the defensive queue was never rebuilt; (2) the delayed 1-second `ForceUpdateAll` on `PLAYER_ENTERING_WORLD` reused stale spell availability cache entries (spells cached as unavailable during initial load when APIs weren't ready yet). Now `OnSpellsChanged` marks the defensive queue dirty, and the delayed timer clears the availability cache before rebuilding.

## [4.7.1] - 2026-03-05

### Fixed
- **Channeling detection fixed for 12.0** — `PlayerChannelBarFrame` was removed in the Dragonflight UI rework; replaced with `PlayerCastingBarFrame.channeling` (plain Lua boolean on CastingBarMixin). Icons now properly grey out during channeling.
- **Defensive icon visual parity with offensive queue** — Extracted `UIRenderer.UpdateDefensiveVisualState()` — a shared function handling channeling + usability states (channeling/no-resources/on-cooldown/normal). Called per-frame from both `RenderSpellQueue` and `UINameplateOverlay.Render`, giving defensives the same instant responsiveness as offensive queue icons. Previously defensives updated on a 0.5s timer, causing visible lag.
- **Overlay queue icons show no-resource blue tint** — Nameplate overlay queue icons now show the blue tint for insufficient resources (matching the standard queue), in addition to channeling grey-out.
- **Interrupt icon stays fully colored during channeling** — Interrupts are urgent actions the player may want to cancel a channel to use. Removed channeling desaturation from interrupt icons on both standard queue and overlay.
- **Early ungrey 200ms before channel ends** — Icons ungrey ~200ms before a channel finishes, letting the player see their next ability before the GCD unlocks. Uses `PlayerCastingBarFrame.value` (NeverSecret countdown timer) with secret-value safety guard.
- **Channeling fill animation on active spell** — When the player is channeling, the queue icon matching the channeled spell shows Blizzard's channel-fill animation (sliding atlas texture, same as action bar buttons) instead of desaturation. Identified via `UnitChannelInfo` spellID + `C_Spell.GetOverrideSpell` matching (resolves base→override spellID chain, e.g. Drain Life 689→234153). Works on both offensive and defensive queue icons. Other icons still grey out.

## [4.7.0] - 2026-03-05

### Fixed
- **Defensive defaults restore fixed** — "Restore Class Defaults" in the defensives panel did nothing and defensive spell lists were empty after profile reset. Root cause: Lua's `and` operator truncates multiple return values, so `return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()` dropped the second return value (`playerClass`), making it always `nil`. Every function that needed `playerClass` (RestoreDefensiveDefaults, InitializeDefensiveSpells, MigrateDefensiveSpellsToClassSpells, GetClassSpellList) bailed out early. Fixed `DefensiveEngine.GetDefensiveSpecKey()` and `GapCloserEngine.ResolveMeleeReference()` to use `if/then/return` pattern that preserves both return values.

### Changed
- **Gap-closer glow now on by default** — New profiles and "Reset Gap-Closer Settings" now enable the glow overlay on gap-closer icons, so users can immediately see when the addon recommends a movement ability.

### Code Cleanup & Consolidation

#### Dead Code Removal
- **Remove 7 dead `CLASS_*_DEFAULTS` assignments** — `CLASS_SELFHEAL_DEFAULTS` and `CLASS_COOLDOWN_DEFAULTS` tables were populated but never read after SpellDB took over spell list management. Removed assignments and stale header comment from `JustAC.lua`.
- **Remove 3 unused BlizzardAPI functions** — `GetCharData()`, `GetSpellCooldownValues()`, and `IsSpellOnGCD()` in `SpellQuery.lua` had zero callers. Removed ~63 lines.
- **Remove 2 dead addon wrappers** — `JustAC:IsSpellBlacklisted()` and `JustAC:GetBlacklistedSpells()` forwarded to SpellQueue but were never called. Removed from `JustAC.lua`.
- **Remove `verboseDebugMode` dead flag** — `MacroParser.lua` and `ActionBarScanner.lua` each had a `local verboseDebugMode = false` that was never set to `true`. Removed the variables and all guarded debug-print blocks (~20 lines in ActionBarScanner).
- **Remove unused `_interfaceVersion` local** — `SecretValues.lua` cached `BlizzardAPI._interfaceVersion` but never used it. Removed.
- **Remove `PERSONAL_AURA_SPELLS` table** — `RedundancyFilter.lua` maintained a 12-entry spell ID table that was only consumed by the third return value of `IsAuraSpell()`. No caller used the third value. Removed the table and simplified `IsAuraSpell()` to return 2 values `(isAura, isUniqueAura)`.
- **Remove unused `GetDebugMode` wrapper** — `FormCache.lua` defined a `GetDebugMode()` function that was never called. Removed.
- **Remove redundant `defensiveIcon` (singular) checks** — `self.defensiveIcon` was a backward-compat alias for `self.defensiveIcons[1]` (set/cleared together in UIFrameFactory). Three uses in `JustAC.lua` were redundant with the plural array loop or already covered by `defHidden` logic. Removed.

#### Wrapper Consolidation
- **Consolidate spec key computation** — `GapCloserEngine.GetGapCloserSpecKey()` and `DefensiveEngine.GetDefensiveSpecKey()` each reimplemented `UnitClass + GetSpecialization + concat`. Both now delegate to `SpellDB.GetSpecKey()`. Inline computations in `ResolveMeleeReference()` and `ResolveGapCloserSpells()` also replaced.
- **Consolidate `GetCachedSpellInfo` access** — `SpellQueue.GetCachedSpellInfo()` and `RedundancyFilter.GetCachedSpellInfo()` were thin wrappers around `BlizzardAPI.GetCachedSpellInfo()`. Removed both; all callers (SpellQueue, UIRenderer, UINameplateOverlay) now reference `BlizzardAPI.GetCachedSpellInfo` directly.
- **Fix `GetDebugMode` in MacroParser** — Was returning a dead `false` local instead of delegating to `BlizzardAPI.GetDebugMode()`. Now correctly returns the live debug mode state.
- **Extract shared `GetActionBarUsability` helper** — `SpellQuery.IsSpellUsable()` and `SecretValues.IsSpellReady()` both had identical 6-line inline patterns for action bar usability fallback. Extracted to `BlizzardAPI.GetActionBarUsability(spellID)` in `BlizzardAPI.lua`; both callers now delegate.
- **Consolidate tooltipMode migration** — Three `OnEnter` handlers in `UIFrameFactory.lua` each had an 8-line inline migration block converting legacy `showTooltips`/`tooltipsInCombat` to `tooltipMode`. Migration now runs once in `NormalizeSavedData()`; handlers read `profile.tooltipMode` directly.

#### Simplification
- **Simplify `CheckDefensiveSpellState` return values** — Was returning 5 values `(isUsable, isKnown, isRedundant, onCooldown, isProcced)` where `isKnown` was only used to gate `isUsable` (already encoded) and `onCooldown` was always `false`. Now returns 3 values `(isUsable, isRedundant, isProcced)`. Both callers in `DefensiveEngine.lua` updated.
- **Cache LibStub module references** — `JustAC.lua` had 11 inline `LibStub("JustAC-*")` re-fetches for modules already cached as upvalues in `LoadModules()`. Added `SpellDB` to upvalue list and `LoadModules()`; replaced all re-fetches with upvalue references. Also removed 2 unnecessary `LibStub and LibStub(...)` guards (LibStub is always available).
- **Remove duplicate `FormCache.OnPlayerLogin()` call** — `PLAYER_ENTERING_WORLD` called `FormCache.OnPlayerLogin()` immediately after `InitializeCaches()`, which already calls it. Removed the duplicate.

#### Module Separation & Consistency
- **Move `IsSpellReady()` from SecretValues → CooldownTracking** — Core cooldown readiness evaluator (46 lines) was in the wrong submodule. Now lives alongside the local cooldown tracking state it depends on (`IsLocalCooldownActive`, `cachedMaxCharges`), eliminating a backward dependency. Uses local references instead of `BlizzardAPI.*` for same-module state.
- **Move health/pet functions from SpellQuery → StateHelpers** — `GetPlayerHealthPercent()`, `GetPetHealthPercent()`, and `GetPetStatus()` moved to consolidate all health-related queries with `GetPlayerHealthPercentSafe()` and `GetLowHealthState()`.
- **Fix duplicate `GetAddon` in SecretValues** — `RefreshFeatureAvailability()` was calling `LibStub("AceAddon-3.0"):GetAddon(...)` directly instead of the cached `BlizzardAPI.GetAddon()`.
- **Standardize LibStub declaration style** — Convert 4 files using `MAJOR/MINOR` variable pattern to inline style (`LibStub:NewLibrary("name", N)`), matching the 22 other files: DefensiveEngine, GapCloserEngine, Options/Overlay, Options/Labels.
- **Standardize hot path cache labels** — All modules now use `-- Hot path cache` consistently. Changed from `-- Cached globals` (UIFrameFactory, DefensiveEngine, TargetFrameAnchor), `-- Hot path cached globals` (KeyPressDetector), and unlabeled (UINameplateOverlay).
- **Fix UIFrameFactory mixed profile access** — 5 occurrences of `addon.db.profile` converted to `addon:GetProfile()`, matching the file's other 13 uses. Eliminates mixed access pattern within the same file.
- **Consolidate `ForceUpdate`/`ForceUpdateAll`** — `ForceUpdate(includeDefensives)` is now the single implementation; `ForceUpdateAll()` delegates to `ForceUpdate(true)`. Eliminates 3 duplicate lines.
- **Clarify UINameplateOverlay bar constants** — Comment `BAR_HEIGHT` and `BAR_SPACING` to document they intentionally differ from `UIHealthBar` equivalents (5 vs 6, 2 vs 3).

## [4.6.1] - 2026-03-05

### Changed
- **Quest indicator replacement is now always active** when the nameplate overlay is enabled. Previously it was a separate toggle, but disabling it caused visual overlap between Blizzard's engine-rendered quest circles and the icon queue. The option has been removed; the replacement activates automatically with the overlay and restores the original CVar on disable.

## [4.6.0] - 2026-03-05

### Changed
- **Blacklist is now per-profile, per-spec.** Previously stored per-character (`db.char`), so switching profiles/specs kept the same blacklist. Now stored in `db.profile.blacklistedSpells["CLASS_N"]`, matching how defensive spell lists, gap-closers, and hotkey overrides work. Existing character blacklists are automatically migrated into the current spec's profile on first load.
- **Defensive spell lists are now per-spec.** Previously keyed per-class (`classSpells["WARRIOR"]`), so all specs shared one defensive list. Now keyed per-spec (`classSpells["WARRIOR_3"]`), allowing tank specs to have different defensive priorities than DPS specs. Existing per-class lists are automatically copied to all specs of that class on migration.
- **Spec-specific defensive defaults** for tanks and notable spec outliers: Blood DK, Vengeance DH, Guardian Druid, Feral Druid, Brewmaster Monk, Windwalker Monk, Protection Paladin, Shadow Priest, Protection Warrior. All other specs continue to use class-level fallback defaults.
- Blacklist tab and defensive spell list headers now show the active spec name for clarity.
- All spell lists (blacklist, defensives, gap-closers, hotkey overrides) now consistently live in `db.profile` and travel with profile switches/copies/resets.

## [4.5.8] - 2026-03-04

### Added
- **Input Preference setting** — New "Input Preference" dropdown (Auto-Detect / Keyboard / Gamepad) in General options. When both keyboard and controller bindings exist for the same action, the addon now selects the appropriate one based on this setting. "Auto-Detect" (default) uses controller glyphs when a gamepad is connected and keyboard text when disconnected. Handles `GAME_PAD_CONNECTED` / `GAME_PAD_DISCONNECTED` events for live hot-plug switching.

### Fixed
- Fixed keybind display always showing keyboard bindings even when a controller was connected, because `GetBindingKey()` returns multiple values but only the first was captured.

## [4.5.7] - 2026-03-03

### Removed
- **Single-Button Assistant warning**: Removed the startup warning requiring the Single-Button Assistant to be placed on an action bar. `C_AssistedCombat.GetRotationSpells()` and `GetNextCastSpell()` work regardless of button placement; the warning was unnecessary.

## [4.5.6] - 2026-03-03

### Changed
- **Overlay interrupt positioning**: Interrupt icon now anchors inline at "position 0" (between icon 1 and the nameplate edge) instead of perpendicular (above icon 1). Mirrors the standard queue's `CreateInterruptIcon` pattern. Queue icons 1+ never shift when the interrupt appears/hides. Cast aura direction adapts to expansion mode ("up" → below interrupt, otherwise above).

### Added
- **Replace Quest Indicator** (Overlay): Suppresses the engine-rendered quest exclamation mark (`!`) on nameplates and renders our own version above the nameplate center, preventing overlap with the icon queue. Uses `UnitIsQuestBoss()` for detection and `SetCVar("ShowQuestUnitCircles", "0")` for suppression. Original CVar restored on disable/unload. Enabled by default; toggle in Overlay → Layout.

### Fixed
- **RedundancyFilter v40**: NeverSecret aura timing data (duration, expirationTime) was always zero in combat. `GetAuraTiming` used `Unsecret()` which trusts `issecretvalue()` — returns `true` even for NeverSecret fields (generic marking). Switched to pcall arithmetic bypass (`auraData.duration + 0`) matching the pattern already used for spellId. Fixes long-duration buff expiration reminders (raid buffs, rogue poisons) not appearing when buffs near expiry.

## [4.5.5] - 2026-03-03

### Added
- **Instance-level CC immunity cache**: Mobs identified as CC-immune (bosses, certain elites) are now remembered by NPC ID for the duration of the instance. Repeat pulls of the same mob no longer re-learn CC immunity from scratch. The cache resets on zone change (`PLAYER_ENTERING_WORLD`). NPC IDs are extracted from `UnitGUID` out of combat and backfilled at combat end.

### Changed
- **Options panel reorganized**: Centralized per-surface display settings for better coherence.
  - **Standard Queue** now has 4 sub-tabs: Layout, Offensive Display, Defensive Display, Appearance.
    - **Offensive Display** sub-tab absorbs `maxIcons`, `firstIconScale`, `glowMode` from the Offensive tab.
    - **Defensive Display** sub-tab absorbs `enabled`, `displayMode`, `maxIcons`, `iconScale`, `glowMode`, `showHealthBar`, `showPetHealthBar` from the Defensives tab.
  - **Offensive** tab renamed its settings sub-tab to "Queue Content" (only content settings remain: `includeHiddenAbilities`, `showSpellbookProcs`, `hideItemAbilities`).
  - **Defensives** tab renamed its settings sub-tab to "Queue Content" (only content settings remain: `showProcs`, `allowItems`, `autoInsertPotions`).
  - Tab order updated: General(1) → Standard Queue(2) → Overlay(3) → Offensive(4) → Defensives(5) → Labels(6) → Hotkeys(7) → Profiles(8).
- **Overlay defensive display mode**: Added "When Health Low" (`healthBased`) option for feature parity with the standard queue panel.
- **Overlay restructured into sub-tabs**: Layout, Offensive Display, Defensive Display — matching the Standard Queue's organization. Each sub-tab has its own scoped reset button.
- **Overlay glow modes split**: Offensive and defensive overlay icons now have independent Highlight Mode settings (`npo.glowMode` for offensive, `npo.defensiveGlowMode` for defensive), matching Standard Queue parity. Existing users' offensive glow setting is preserved; defensive defaults to "All Glows".

### Fixed
- **Overlay respects shared `showProcs` setting**: The nameplate overlay defensive queue previously hardcoded `showProcs=true`, ignoring the user's "Insert Procced Defensives" setting. Now correctly reads `profile.defensives.showProcs`.
- **Overlay-only fallback**: When `displayMode` is set to "Overlay Only" and the target's nameplate is not rendered (too far, culled by stacking limits, hidden by nameplate addon), the main panel now shows as a fallback so users never lose their combat queue. Applies to both the offensive queue (UIRenderer) and the defensive queue (DefensiveEngine). As soon as the nameplate reappears, the overlay takes over and the main panel hides again.
- **Disabled-function corrections** (7 settings):
  - `includeHiddenAbilities`, `showSpellbookProcs`, `hideItemAbilities` — No longer grayed out in overlay-only mode (SpellQueue feeds both surfaces).
  - `glowMode` (offensive) — Now correctly grayed out in overlay-only mode (only UIRenderer uses it).
  - `defensives.showProcs`, `defensives.allowItems`, `defensives.autoInsertPotions` — Now available when either surface's defensives are enabled (standard panel or overlay), not just the standard panel.

## [4.5.4] - 2026-03-03

### Changed
- **UIRenderer v17**: Cooldown display now uses `SetCooldownFromDurationObject` (12.0+ opaque pipeline) when available. Bypasses secret value handling entirely for cooldown sweep animations. Falls back to legacy `SetCooldown` on pre-12.0 clients. Charge cooldowns also use `GetActionChargeDuration` → `SetCooldownFromDurationObject` when an action bar slot is resolved.
- **RedundancyFilter v39**: Added NeverSecret aura whitelist (Meorawr/Blizzard hotfix data, ~50 spells). Auras gained during combat that are on the whitelist can be resolved directly via pcall without instance-map lookup — covers raid buffs, rogue poisons, shaman imbues, exhaustion debuffs, and more.
- **RedundancyFilter v39**: Wrapped `GetAuraDataByIndex` loop in pcall for crash resilience. If the API throws (compound token issues, hotfix changes), the loop breaks gracefully and falls back to the trusted out-of-combat cache.
- **GapCloserEngine v2**: Uses `C_ActionBar.EnableActionRangeCheck(slot, true)` to opt the melee reference slot into push-based `ACTION_RANGE_CHECK_UPDATE` events. Properly disables range check on old slots when the reference changes or the cache is invalidated.

## [4.5.3] - 2026-03-02

### Fixed
- "When Health Low" defensive display mode now works correctly in combat — was showing defensives at all health levels because secret-health fallback bypassed the threshold check. LowHealthFrame (~35%) is NeverSecret and properly gates the queue.

## [4.5.2] - 2026-03-02

### Changed
- **Merged defensive spell lists:** Self-heals and major cooldowns are now a single "Defensive Priority List" instead of two separate lists. Self-heals appear first by default (natural priority). Existing per-class customizations are automatically migrated (old keys preserved for safe downgrade).
- Auto-insert potions now triggers at the unified low-health threshold instead of requiring a separate "critical" health level.
- Removed `cooldownThreshold` setting and "Ignore Health Priority" toggle (unified list makes both obsolete).

### Fixed
- Defensive spells on cooldown (e.g. Crimson Vial) now deprioritized to end of queue instead of showing at full priority.
- Charge-based spells (e.g. Crimson Vial with 2 charges) excluded from local cooldown tracking — `IsSpellUsable` handles charge depletion correctly.
- `UpdateButtonCooldowns` wrapped in pcall; charge display no longer flickers off when `GetSpellCharges` returns nil in combat.

## [4.5.1] - 2026-03-02

### Fixed
- Keybind not showing on primary icon when a spell procs (e.g. Infernal Bolt, Ruination for Demo Lock) — empty hotkey cache was never retried due to Lua truthiness of empty string
- Gap-closer glow on nameplate overlay defaulted to ON instead of matching main panel (OFF by default)
- DefensiveEngine `showProcs` override precedence (Lua and/or short-circuit with false values)

### Changed
- **Centralized shared settings across Standard Queue and Nameplate Overlay:**
  - **Interrupt Mode** — now a single setting in the Offensive tab, applied to both surfaces
  - **Key Press Flash** — now a single toggle in the Offensive tab, applied to both surfaces
  - **Highlight Mode** — offensive and defensive queues now share one `glowMode` (overlay keeps its own)
  - **Icon Labels** — show toggle is shared; font scale, color, and anchor are independently configurable per surface via mirrored sub-groups within each label type
  - **Health Bars** — removed confusing fallback toggles from the General tab; the Defensives tab is now the sole owner
- Reduced update pipeline latency for faster rotation display after casting (debounce timers halved across SpellQueue, UIRenderer, UINameplateOverlay, and OnUpdate)
- Shortened interrupt mode dropdown labels across all locales
- Defensive health thresholds in combat (12.0 secret health adaptation):
  - Self-heal tier now always active in combat (configurable threshold undetectable when UnitHealth is secret)
  - Cooldown tier triggers at LowHealthFrame "low" signal (~35%) instead of waiting for "critical" (~20%)
  - Out-of-combat thresholds unchanged

### Added
- Defensive queue usability visuals: icons grey out while channeling, blue-tint when lacking resources, desaturate when on cooldown (mirrors offensive queue behavior)
- Defensive queue usability-aware sorting: unusable spells deprioritized to the bottom so castable abilities appear first

### Improved
- DefensiveEngine single-pass iteration and pooled table sorting (reduces GC pressure)

## [4.5.0] - 2026-03-02

### Added
- **Third-party nameplate cast bar discovery chain (UIRenderer v16):** Interrupt detection now cascades through Blizzard → Plater → ElvUI cast bars via `FindVisibleCastBar()`. Previously only worked with Blizzard's default nameplate cast bar; Plater and ElvUI users got no interrupt suggestions. Source-verified paths: `nameplate.UnitFrame.castBar` (Blizzard, capital U), `nameplate.unitFrame.castBar` (Plater, lowercase u), child `.Castbar` (ElvUI/oUF, capital C).
- **API fallback for interrupt detection when nameplates disabled:** `IsTargetCastInterruptible()` falls back to `UnitCastingInfo`/`UnitChannelInfo` with `issecretvalue()` guard and fail-open design when no cast bar frame is available (nameplates off + addon target frame).
- **Event-driven interrupt interruptibility tracking (StateHelpers v2):** `UNIT_SPELLCAST_INTERRUPTIBLE` / `NOT_INTERRUPTIBLE` events on `"target"` now provide a definitive real boolean for interruptibility (never secret). Used as the preferred signal before frame field inspection or API fallback. Pattern learned from oUF (ElvUI) and DetailsFramework (Plater) source.
- **`ResetTargetCastState()` on target change (JustAC.lua):** Clears stale event-driven interruptibility state when target changes, preventing carry-over from previous target's cast.

### Changed
- **Unified `IsTargetCastInterruptible()` replaces three functions:** `IsCastBarInterruptible()`, `IsTargetCastingFallback()`, and redundant `GetTargetCastInterruptState()` calls merged into a single `IsTargetCastInterruptible(nameplate)` → `(isCasting, isInterruptible, castBar)`. Event tracker queried once instead of independently in two functions.
- **Single-pass spell selection in `EvaluateInterrupt()`:** Two separate loops (CC-prefer pass + fallback pass) merged into one loop with inline `fallbackID` tracking. Fewer iterations when `preferCC` is false (immediate break on first usable).
- **Dead `importantOnly` interrupt mode removed:** `ImportantCastIndicator` pcall chain and `importantOnly` mode guard were entirely unreachable (all signals SECRET in 12.0, mode retired). ~12 lines removed from `EvaluateInterrupt()`.
- **Comment cleanup — "why not how":** ~180 lines of "how" comments removed or shortened across UIRenderer.lua. Retained all gotcha/safety comments (secret values, case sensitivity, race conditions, ordering constraints). Deduplicated repeated "widget handles secret values" explanations (was 6×, now once at function header).

### Refactor
- Split `BlizzardAPI.lua` (1 719 lines) into four cohesive submodules under `BlizzardAPI\`:
  - `CooldownTracking.lua` — local CD event frame, tooltip probe, charge cache
  - `SecretValues.lua` — feature availability, secret value utilities, secrecy API wrappers, C_Secrets namespace
  - `SpellQuery.lua` — addon access, spell info/usability/proc cache, rotation API, item detection, availability, health helpers
  - `StateHelpers.lua` — defensive/item state helpers, LowHealthFrame detection, target CC immunity, shapeshift form wrappers
- Root `BlizzardAPI.lua` reduced to 14 lines (LibStub registration + version constants); public API surface unchanged for all 17 consumers
- Each submodule uses its own LibStub identity (`JustAC-BlizzardAPI-*`) for reload safety
- Extracted `ResolveSpellID` from `DefensiveEngine` and `GapCloserEngine` into `BlizzardAPI.ResolveSpellID` (single canonical implementation)
- Renamed `lib` → `DefensiveEngine` / `GapCloserEngine` in respective module exports for clarity
- Moved shapeshift Safe* wrappers (`SafeGetNumShapeshiftForms`, `SafeGetShapeshiftFormInfo`) from `FormCache` into `BlizzardAPI.GetNumShapeshiftForms` / `BlizzardAPI.GetShapeshiftFormInfo`
- Reduced `GetDefensiveSpellQueue` from 8 parameters to 6 by consolidating override flags into an `overrides` table
- Added `ApplyMainPanelQueue` / `ApplyOverlayQueue` helpers in `DefensiveEngine` to decouple UI dispatch from queue resolution logic

## [4.4.7] - 2026-02-27

### Fixed
- **Custom hotkey overrides with full-word modifiers were silently corrupted:** `NormalizeHotkey` matched the single-letter abbreviated patterns (e.g. `^S%-?`) against full words like `"SHIFT-2"`, capturing `"HIFT-2"` and producing `"SHIFT-HIFT-2"`. Flash/press detection never matched so the icon never flashed. Full-word patterns (`SHIFT`, `CTRL`, `ALT` and two-word combos) now run first and are fully consumed before the abbreviated patterns are checked.
- **`+` separator not accepted in custom hotkey overrides:** User-typed `"Shift+2"` was stored as-is and normalized to `"SHIFT+2"`, which never matched `"SHIFT-2"` from the keybind scan. Full-word patterns now accept both `-` and `+` as separator, so `"Shift+2"`, `"Shift-2"`, and `"S-2"` all resolve to `"SHIFT-2"` and match correctly.

## [4.4.6] - 2026-02-27

### Fixed
- **Proc glow lingering on empty offensive slot:** When a procced spell left a slot, the slot-clear path set `hasProcGlow = false` and wiped state but forgot to call `UIAnimations.HideProcGlow()` — the animation frame stayed visible until another spell filled the slot. Now calls `HideProcGlow` alongside `StopAssistedGlow` and `StopGapCloserGlow` in the empty-slot branch.
- **`HideDefensiveIcon` left `normalizedHotkey` populated:** After a defensive slot was hidden, `normalizedHotkey` and `previousNormalizedHotkey` retained the previous spell's hotkey. Harmless (gated by `IsShown()`), but inconsistent with the offensive-slot clear path which always nils both fields. Now cleared in `HideDefensiveIcon`.
- **`isWaitingSpell` could be `nil` instead of `false`:** `spellInfo.name and name:find(…) or false` returns `nil` when `spellInfo.name` is `nil` (Lua `and`/`or` semantics). Changed to explicit `~= nil` comparisons so the flag is always a proper boolean.
- **`GetCurrentSpellQueue` returned pooled table on full build (SpellQueue v37):** The full-build code path `return recommendedSpells` returned the pooled table that is `wipe()`d at the start of every queue build — any caller holding the reference across frames would see an empty table. Early-exit paths correctly returned the stable `lastSpellIDs` copy; the full-build path now matches them. Callers can safely hold the returned reference.
- **Duplicate interrupt debounce state between UIRenderer and UINameplateOverlay:** Both renderers maintained separate `lastInterruptUsedTime` / `lastInterruptShownID` / `lastCCAppliedTime` debounce locals. When the player used an interrupt, only the evaluating renderer debounced; the other could fire a redundant suggestion on the same frame. Interrupt evaluation is now consolidated in `UIRenderer.EvaluateInterrupt()`, cached per 0.015 s and keyed on `interruptMode`, called by both renderers — one player, one debounce timer. `UINameplateOverlay.NotifyCCApplied()` now delegates to `UIRenderer.NotifyCCApplied()` and `JustAC.lua` no longer needs a second call.

### Changed
- **`rotationFilterCache` split from `filterResultCache` (SpellQueue):** `PassesRotationFilters()` was keying its cache with `"r_" .. spellID` — a string concatenation on every rotation-spell evaluation in the hot path. Now uses a dedicated `rotationFilterCache` table keyed by the plain integer `spellID`. Both tables are wiped together at the start of each queue build. No behaviour change; eliminates ~N string allocations per update cycle where N = rotation list length.
- **Dead `cachedNormalizedHotkey` field removed (UIRenderer):** The field was assigned in three places (hotkey normalized, hotkey cleared, slot emptied) but never read anywhere — `normalizedHotkey` (the live field read by `KeyPressDetector`) was always set alongside it. All three assignments removed.
- **Visibility predicate unified via `SpellQueue.ShouldShowQueue()` (SpellQueue v37, UIRenderer v15):** UIRenderer previously re-evaluated all four visibility conditions (out-of-combat, healer spec, mounted, hostile target) every render frame, duplicating the logic already in `SpellQueue.GetCurrentSpellQueue()`. `GetCurrentSpellQueue()` now caches the final verdict in `lastShouldShowQueue` and exposes it via `SpellQueue.ShouldShowQueue()`. UIRenderer reads the cached result — one evaluation per queue build instead of one per render frame.
- **Glow state resolved via `ResolveGlowState()` enum (UIRenderer v15):** Six cascading boolean locals (`isSyntheticProc`, `isGapCloser`, `isRealProc`, `wantProcGlow`, `wantGapCloserGlow`, `shouldShowAssisted`) per icon per frame replaced with a single `ResolveGlowState(position, spellID, …)` call returning a `GLOW_NONE / GLOW_ASSISTED / GLOW_PROC / GLOW_GAP_CLOSER` integer. Application uses a clear 4-branch structure — easier to extend with new glow types.
- **`UnitAffectingCombat` call count reduced in hot path:** `GetQueueThrottleInterval()` function removed; `inCombat` is now computed once at the top of `GetCurrentSpellQueue()` and reused for both the throttle interval and all four visibility checks. `ShowDefensiveIcon` no longer calls `UnitAffectingCombat` per icon per update — uses the module-level `isInCombat` maintained by `SetCombatState()` on PLAYER_REGEN events. Net reduction: ~2 + N redundant calls per update cycle (N = visible defensive icons).

## [4.4.5] - 2026-02-27

### Fixed
- **Key-press flash broken when a proc moves to position 1:** `normalizedHotkey` was not cleared when a slot went empty, so when a proc refilled it the stale value was written to `previousNormalizedHotkey`, corrupting the grace-period flash logic (regression since 4.4.0 three-tier sort).
- **Gamepad glyphs reverting to keyboard text after a few minutes:** `UPDATE_BINDINGS` immediately wiped `spellHotkeyCache`, causing the next render frame to cache keyboard text before WoW's gamepad bindings had fully committed. Full cache invalidation now deferred to the existing 0.3s settle timer; only the raw binding-key cache is cleared immediately.

## [4.4.4] - 2026-02-25

### Changed
- **Interrupt Reminder dropdown** — The old `Show Interrupt Reminder` toggle + `Prefer CC on Regular Mobs` toggle have been consolidated into a single `Interrupt Reminder` dropdown with three modes:
  - **Disabled** — No interrupt reminders
  - **Interrupt Only** — Shows on all interruptible casts, always suggests your interrupt
  - **Prefer CC on Trash** — Shows on all interruptible casts, prefers crowd control on non-boss mobs (previous default behavior)
- **Important Casts Only mode reserved** — `importantOnly` option removed from UI. All important-cast detection signals (`isHighlightedImportantCast`, `C_Spell.IsSpellImportant()`, `ImportantCastIndicator:IsShown()`, `IsPlaying()`) return secret booleans in 12.0 — unusable for branching logic. Detection code kept in place for future re-enablement. Stale saved data gracefully falls back to `kickOnly`.
- **Interruptibility detection hardened** — Uses `castBar.Icon:IsShown()` (NeverSecret, verified 2026-02-25) on nameplate castbars with `HideIconWhenNotInterruptible=true`. Falls back to `BorderShield:IsShown()` on castbars without icon hiding.
- **Settings migration** — `showInterrupt=true` + `ccRegularMobs=true` → `"ccPrefer"`, `showInterrupt=true` + `ccRegularMobs=false` → `"kickOnly"`, `showInterrupt=false` → `"disabled"`. Legacy keys cleaned from saved data after migration.

## [4.4.3] - 2026-02-25

### Changed
- **Extracted GapCloserEngine from DefensiveEngine** — Gap-closer system moved to its own `GapCloserEngine.lua` module. Gap closers inject into the offensive queue and had no coupling with defensive spell evaluation. DefensiveEngine reduced to its actual scope: health-based defensive queue, proc detection, potions.

## [4.4.2] - 2026-02-25

### Fixed
- **Gap-closer glow missing after leaving combat:** `PauseAllGlows` (fired on `PLAYER_REGEN_ENABLED`) hid the gap-closer crawl frame and stopped its animation, but did not reset the renderer's `hasGapCloserGlow` tracking flag. Removed gap-closer glow from `PauseAllGlows`; added stale-flag guard in UIRenderer as defensive fallback.
- **Shadowstrike gap-closer not suggesting in stealth:** Shadowstrike (185438) was not in Sub Rogue gap-closer defaults, and the melee range reference (Backstab) transforms to Shadowstrike on the action bar in stealth, changing range from 5yd to 25yd. Added Shadowstrike as first entry; stealth-only gap closers now evaluate before the melee range gate using their own slot range.
- **Melee range reference stability audit (Rogue):** Fixed unstable backup references — `ROGUE_2` changed from Between the Eyes (20yd ranged) to Kidney Shot (5yd melee); `ROGUE_3` changed from Shadowstrike (25yd) to Kidney Shot. All other class/spec references verified stable.
- **Druid gap-closer disabled after form change:** `OnShapeshiftFormChanged` did not invalidate the melee range reference cache. Now invalidates gap closer cache + range state on `UPDATE_SHAPESHIFT_FORM`.
- **IsSpellReady() cooldown detection in 12.0 combat:** Now uses full `isOnGCD` three-state: `true`=GCD only (ready), `false`=real CD (flagged spells), `nil`=ambiguous (falls back to local CD tracking + charge checks + action bar usability). Fixes DefensiveEngine suggesting spells on cooldown.
- **GetSpellCooldownValues() `isOnRealCooldown`:** Now checks `isOnGCD == false` (definitive for flagged spells), then local CD tracking for unflagged spells. Returns `nil` (unknown) instead of `false` when ambiguous.
- **Nameplate overlay invisible without enemy nameplates:** Now auto-enables `nameplateShowEnemies` CVar when display mode is "Overlay" or "Both", restores original setting on disable/unload.
- **Mouse hotkey flash detection:** Added `OnUpdate` polling via `IsMouseButtonDown` for mouse button down-transitions (M3/M4/M5, with or without modifiers).
- **Mouse hotkey normalization mismatch:** Added reverse mouse abbreviations (`M%d` → `BUTTON%d`, `MWU` → `MOUSEWHEELUP`, `MWD` → `MOUSEWHEELDOWN`) so normalized hotkeys match WoW binding format.

### Changed
- Updated all `isOnGCD` documentation to reflect verified three-state behavior
- Updated `UnitHealth("player")` documentation: confirmed SECRET in open world combat
- Updated `UnitPower("player")` documentation: per-type secrecy — continuous resources SECRET, discrete resources NeverSecret
- Corrected `GetComboPoints()` from SECRET to NeverSecret
- Added `isEnabled`, `modRate`, `activeCategory` fields to cooldown signal reference (all SECRET)
- Documented `LuaDurationObject` API, `C_Secrets.ShouldSpellCooldownBeSecret()`, `SecrecyLevel` enum
- **CheckCooldownCompletions() now uses SPELL_UPDATE_COOLDOWN spellID payload** — O(1) lookup when event fires with non-nil spellID; falls back to full scan on nil
- **PassesRotationFilters() comment corrected** — accurately documents isOnGCD three-state behavior
- **Central maxCharges cache in BlizzardAPI** — `GetCachedMaxCharges(spellID)` replaces per-button state; proactive scan on combat exit
- **UIRenderer per-button `_cachedMaxCharges` removed** — replaced with central `BlizzardAPI.GetCachedMaxCharges()` lookups

### Added
- **New combat-safe signals discovered and verified:** `C_ActionBar.IsActionInRange()`, `IsInterruptAction()`, `C_Spell.IsExternalDefensive()`, `C_CooldownViewer` category/info APIs, `C_UnitAuras.GetCooldownAuraBySpellID()`, `ACTION_RANGE_CHECK_UPDATE`, `ACTION_USABLE_CHANGED`, `IsAttackAction()`, `IsCurrentAction()`, `GetSessionDurationSeconds()`
- **SPELL_UPDATE_COOLDOWN spellID is NeverSecret** — per-spell CD state change events with `startRecoveryCategory` (133=GCD, 0=own CD)
- **UnitPower secrecy mapped per-type** — continuous primary resources SECRET, discrete secondary resources NeverSecret, `UnitPowerMax`/`UnitPowerType` always NeverSecret
- **C_Spell.IsSpellUsable, GetSpellPowerCost, IsCurrentSpell verified NeverSecret** in combat
- **C_Spell.GetSpellCharges ALL SECRET** (including maxCharges) — must cache out of combat
- **C_Spell.IsSpellInRange verified NeverSecret** — existing range check code confirmed correct
- **LossOfControl API documented from source** — `locType`, `priority`, `displayType`, `auraInstanceID` NeverSecret
- **DB2 tables catalogued** — `CooldownSet`/`CooldownSetSpell`, `SpellActivationOverlay`, `AssistedCombat`/`AssistedCombatRule`/`AssistedCombatStep`, `LossOfControlType`
- **Event-driven CD tracking potential identified** — `SPELL_UPDATE_COOLDOWN` spellID + `isOnGCD` state machine could replace timer-based local CD tracking

### Documentation
- Updated `Documentation/12.0_COMPATIBILITY.md` combat-safe signal reference with all Session 2/2b/2c/2d findings
- Updated `copilot-instructions.md` NeverSecret sections with verified API behaviors

## [4.4.1] - 2026-02-24

### Performance
- Gap-closer engine: early exit when no melee range reference spell resolves (skips target/range/spell checks for ranged specs and melee specs without a reference spell on the action bar)
- Inlined range check in `GetGapCloserSpell` to reuse the already-resolved slot from `ResolveMeleeReference`

### UI
- Removed dead "Bar Position" (healthBarPosition) dropdown from Overlay tab — setting was stored and read but never applied to health bar anchoring
- Gap-Closers options tab: show soft notice for non-melee specs ("No default gap-closers for this specialization") instead of hiding controls
- **Show Pet Health Bar** — New standalone toggle in General tab, mirrors "Show Health Bar". Lets users show a pet health bar (offensive queue width) even when the Defensive Queue is disabled. When defensives are enabled, the existing defensive-section toggle takes over. UIHealthBar v7.
- **Overlay pet health bar** — "Show Health Bars" toggle in Overlay tab now creates both player and pet health bars above the defensive cluster. Pet bar uses warm yellow color, auto-hides when no pet exists. Both bars gated by "Show Defensive Icons". UINameplateOverlay v2.
- **Cross-section naming consistency** — Aligned option labels across all tabs: Overlay "Offensive Slots"/"Defensive Slots" → "Max Icons" (matches Standard Queue), Defensives "Display Mode" → "Defensive Visibility" (matches Overlay, avoids collision with General "Display Mode"), "Key Press Flash" → "Show Key Press Flash" (matches all other "Show X" toggles). Added 6 missing `desc` tooltips to Overlay controls. Removed dead `L["Nameplate Show Health Bar"]` singular keys from all 9 locale files. Updated all 8 translations.

### Investigated
- **Rotation queue cooldown filtering** — `isOnGCD` returns `nil` (not `false`) for real cooldowns outside `SPELL_UPDATE_COOLDOWN` events; `GetActionCooldown` start/duration fully secreted in 12.0 combat; `C_ActionBar.GetActionCharges` also secreted; `IsUsableAction` returns true even on cooldown; `cooldown:IsShown()` includes GCD (can't distinguish)

### Changed
- **Rotation queue cooldown de-prioritization** — Spells with base CD > 3s are tracked locally via `UNIT_SPELLCAST_SUCCEEDED` + `GetSpellBaseCooldown()` (not secret). On-cooldown spells are moved to the end of the queue (below procced and normal spells) rather than filtered out. Fail-open: untracked spells show normally.
- **Tooltip cooldown parsing** — `RegisterRotationSpell()` now scans the spell tooltip for talent-modified cooldown values (e.g., "30 sec cooldown" for Bestial Wrath with Beast Within). Falls back to `GetSpellBaseCooldown` only if tooltip parsing fails. Tooltip is re-scanned on talent/spec changes via natural re-registration flow.
- **Blacklist position 1 option** — New toggle in Offensive > Blacklist: "Apply to Position 1". Off by default. When enabled, blacklisted spells are also hidden from position 1 (Blizzard's primary suggestion). Warning in tooltip about rotation stalling.
- **BlizzardAPI v32**: Added `ParseTooltipCooldown()` for traited cooldown detection; `GetBestCooldownDuration()` now uses 3-tier fallback (observed cast → tooltip → base API); `RegisterRotationSpell()` pre-caches traited duration
- **SpellQueue v36**: Three-tier rotation sort (procced → normal → on-cooldown), auto-registers rotation spells on list fetch, clears registrations on cache invalidation

## [4.4.0] - 2026-02-24

### Fixed
- **SpellDB audit** — full classification review of all spell IDs (SpellDB v7→v8)
  - **CRITICAL:** Removed Storm Elemental (192249) from defensives — DPS cooldown for Elemental Shaman
  - **CRITICAL:** Removed Deathbolt (264106) from defensives — offensive damage ability
  - **CRITICAL:** Removed Mirror Image (55342) from defensives — DPS cooldown for Fire/Frost
  - **CRITICAL:** Moved Holy Word: Chastise (88625) from healing → crowd control (damage + incapacitate)
  - Moved Wind Rush Totem (192077), Mana Tide Totem (16191), Ice Floes (108839) from defensives → utility
  - Moved Wild Charge (102401) from healing → utility (movement ability)
  - Moved Cleanse Toxins (213644) from healing → utility (dispel, consistent with other class dispels)
  - Moved Blistering Scales (360827) from healing → defensive (shield + thorns, not a heal)
  - Removed stale entries: Hand of the Protector (213652, merged into WoG), Greater Heal (289666, not learnable), Soul Harvester (386997, hero talent tree name not a spell), Earthwarden (203974, passive talent), Feral Charge (16979, removed from game)
- **Gap-closer audit** — fixed spell lists and added usability check
  - Removed Vengeful Retreat from DH Havoc (jumps backward, not a gap closer)
  - Added Shadowstrike (185438) as priority 1 for Sub Rogue (teleport gap closer in stealth)
  - Added Grappling Hook (195457) for Outlaw Rogue between Shadowstep and Sprint
  - Added `IsSpellUsable` check to gap-closer evaluation so stealth-only spells only show when actually usable
  - Added action bar slot check to gap-closer evaluation: spells not on any bar (e.g. Shadowstrike out of stealth) are skipped, falling through to the next candidate (e.g. Shadowstep)
- **Melee range detection overhaul** — replaced broad per-slot `slotRangeState` tracking with a fixed per-spec melee reference spell
  - Old system tracked all 120 action bar slots; any out-of-range event (including ranged abilities) could trigger false-positive gap-closer insertion
  - New system uses a priority chain: user override → SpellDB default[1] → SpellDB default[2]; first spell found on the action bar wins
  - Two hardcoded candidates per spec (e.g. Backstab + Shadowstrike for Sub Rogue); primary shown in options, backup is hidden
  - New **Melee Range Reference** group in Gap-Closers options: shows current default, allows user override via spell ID input
  - `OnActionRangeUpdate` now only triggers queue rebuilds when the melee reference slot changes range (not every slot)
  - `SeedRangeState()` loop over 120 slots eliminated — replaced by direct `IsActionInRange(slot)` check on the single reference slot
- **Gap-closer OOC visibility** — fixed gap closer not always appearing out of combat
  - `IsPrimarySpellOutOfRange` replaced by `IsMeleeTargetOutOfRange` (uses fixed reference spell instead of queue position 1)
  - `OnActionRangeUpdate` now calls `SpellQueue.ForceUpdate()` on melee reference slot range transitions so the queue rebuilds immediately
- **Gap-closer position-1 dedup** — when Blizzard's Assisted Combat suggests a gap closer (e.g. Charge) as the primary spell at position 1, JustAC no longer injects a second gap closer at position 2
  - New `DefensiveEngine.IsGapCloserSpell()` checks both base IDs and talent overrides
- **SpellQueue dead code cleanup** (v34→v35) — removed dead stabilization code, fixed `lastSpellIDs` aliasing bug, removed unused functions/variables

### Added
- **Gap-Closer System** — suggests gap-closing abilities (Charge, Shadowstep, Fel Rush, etc.) when the target is out of melee range
  - Appears at position 2, before spellbook procs (highest priority after Blizzard's primary suggestion)
  - Uses `ACTION_RANGE_CHECK_UPDATE` (NeverSecret) for range detection via a fixed per-spec melee reference spell — fully combat-safe under 12.0 secret value system
  - Uses `isOnGCD` (NeverSecret) for cooldown readiness checks
  - 150ms debounce on hide path to prevent flicker during kiting; show path is instant
  - Spec-aware defaults for all melee specs (Warrior, Rogue, DK, DH, Feral/Guardian Druid, Survival Hunter, WW/BM Monk, Ret/Prot Paladin, Enhancement Shaman)
  - Per-spec spell list stored in profile (`gapClosers.classSpells[CLASS_SPECINDEX]`)
  - New **Gap-Closers** options tab with priority list management, restore defaults, and spell search
  - Red emphasis glow (same tint as interrupts) on gap-closer icons, with independent toggle (`showGlow`) separate from the proc glow dropdown
  - Gap-closer and interrupt icons now use red-tinted marching ants crawl instead of red proc glow — proc glow is reserved for actual spell procs
  - Gap-closer crawl animates even out of combat (unlike other crawls which pause OOC)
- `BlizzardAPI.IsTargetInterruptWorthy()` — combat-safe check to suppress interrupt/CC suggestions on trivial targets
  - `"minus"` classification mobs (swarm adds, Explosive orbs) — not worth a kick CD
  - `UnitIsMinion()` targets (pets, totems, treants, guardians) — combat-safe replacement for secreted `UnitCreatureType()` Mechanical/Totem check
- Interrupt guard in both UIRenderer and UINameplateOverlay — skips cast bar processing entirely for unworthy targets

### Documentation
- New "Combat-Safe Signal Reference" section in `Documentation/12.0_COMPATIBILITY.md` — authoritative matrix of all APIs tested in 12.0 combat with verification dates
- Updated `copilot-instructions.md` NeverSecret section with newly verified target APIs

## [4.3.1] - 2026-02-24

### Fixed
- **Standard queue cast aura ("to interrupt" icon) not showing:** `castBar` variable was scoped inside the debounce block, making it nil when the cast aura rendering code ran — hoisted to outer scope in both UIRenderer and UINameplateOverlay
- **Nameplate overlay interrupt icon shifted entire DPS queue:** Interrupt icon now positions perpendicular to icon 1 (above for horizontal queues, outside for vertical) instead of displacing it inline — dpsIcons[1] stays fixed
- **Standard queue cast aura overlapped icon 1 in UP orientation:** Aura now anchors below the interrupt icon when queue grows upward (away from queue) instead of always above

### Changed
- Nameplate overlay interrupt icon now includes cast aura (enemy spell icon), consistent with standard queue — always positioned above the interrupt icon
- Removed redundant dpsIcons[1] re-anchor dance in nameplate overlay Render() — no longer needed since interrupt is perpendicular to queue

## [4.3.0] - 2026-02-24

### Refactored
- Split monolithic `Options.lua` (3316 lines) into 9 modular files in `Options/` subfolder: SpellSearch, General, Offensive, Overlay, Defensives, Labels, Hotkeys, Profiles, Core
- Moved 5 UI modules to `UI/` subfolder: UIHealthBar, UIAnimations, UIFrameFactory, UIRenderer, UINameplateOverlay
- Extracted `TargetFrameAnchor.lua` and `KeyPressDetector.lua` from `JustAC.lua` into standalone modules

### Fixed
- **Hotkey text hidden after update:** Legacy migration (`defensives.showHotkeys = false`) was incorrectly hiding all hotkeys including offensive queue; now only migrates `showOffensiveHotkeys`
- **Nameplate overlay defensive hotkeys ignoring Labels tab toggle:** Was reading legacy `npo.showHotkey` instead of `npo.textOverlays.hotkey.show`
- **General tab "Reset to Defaults" set Target Frame Anchor to TOP instead of DISABLED** and did not reset sidebar position

## [4.2.2] - 2026-02-24

### Fixed
- **Long buffs (poisons, Mark of the Wild) shown as active when about to expire at combat start:** Stop filtering a long-duration buff (≥10 min) when less than 5 minutes remain. Three-layer fix: IsInPandemicWindow applies a 5-minute absolute floor for long buffs, trusted-cache combat merge skips re-adding expiring long buffs, CountActivePoisonBuffs skips counting expiring poisons.

## [4.2.1] - 2026-02-23

### Added
- Text overlays (hotkey, cooldown timer, charge count) are now individually configurable — toggle each on/off, adjust font scale, color, and anchor position. Settings apply across all icon types: main queue, nameplate overlay, defensives, and interrupt icon
- Long-duration buffs (poisons, Mark of the Wild, weapon imbues) now show a recast suggestion when less than 5 minutes remain — previously they were suppressed as "active" right up until expiry, leaving queue slot 1 stuck at the start of combat
- 4-second hold after a CC lands before suggesting another, giving the game time to register the target's crowd-controlled state
- Spell queue and defensive icons now hidden when controlling a vehicle or possessing an NPC (Mind Control, siege engines, questline vehicles) — your normal action bars are replaced in these states

### Changed
- Mechanical and Totem mob types now recognized as CC-immune (in addition to worldbosses and dungeon bosses)

### Fixed
- Fixed a second CC spell briefly flashing immediately after the first one was cast

## [4.2.0] - 2026-02-22

### Added
- Cast aura indicator above interrupt icon: shows the enemy's casting spell icon so you can see what you're interrupting (standard queue + nameplate overlay)
- Nameplate overlay: channeling grey-out — interrupt and DPS icons now desaturate when the player is mid-channel, matching the main panel behavior
- Nameplate overlay: out-of-range detection — interrupt and DPS hotkey text turns red when the target is beyond spell range, matching the main panel behavior

### Changed
- **Interrupt options consolidated into single dropdown** — replaced separate "Interrupt Mode" dropdown + "CC Non-Important Casts" checkbox with one 5-option dropdown: Off, Important Only, Important + CC, All + Smart CC, All Casts. Existing saved settings are preserved automatically.
- Interrupt/CC reminders now only trigger on casts with 0.8s+ duration (important/dangerous casts bypass the filter and trigger immediately); when cast duration is a secret value (12.0 combat), falls back to elapsed-time measurement
- **"All + Smart CC" mode falls back to kick** — non-important casts prefer CC but fall back to your interrupt if no CC is available; "Important + CC" intentionally does NOT fall back (saves interrupt lockout for dangerous casts)

### Fixed
- Interrupt icon for RIGHT/UP orientations now anchors adjacent to icon 1 instead of beyond the grab tab (was causing ~17px gap vs expected ~3px)
- Standalone health bar for UP/DOWN orientations now goes to the side of the queue (perpendicular) instead of above it, matching how horizontal bars are perpendicular to horizontal queues
- **CC/interrupt spells now correctly detected as off-cooldown in combat** — WoW 12.0 blanket-secrets `duration`/`startTime` from `C_Spell.GetSpellCooldown()` even when zero; now uses `isOnGCD` (NeverSecret) three-state field: `true`=GCD only (ready), `false`=real cooldown, `nil`=no cooldown (ready)
- **Aura detection now works in combat via auraInstanceID mapping** — WoW 12.0 secrets `spellId`/`name` in combat but `auraInstanceID` is NeverSecret and stable; builds instanceID→spellID map out of combat, resolves auras in combat using the map; UNIT_AURA addedAuras/removedAuraInstanceIDs keep the map current; trustedOutOfCombatCache used as fallback only for truly unmapped auras (RedundancyFilter v37→v38)
- **Buff removal now detected in combat** — removing a buff (e.g., right-clicking MOW off) now immediately shows the spell in queue; tracks removed spellIDs via `combatRemovedSpellIDs` to prevent trusted cache merge from re-adding them; non-DPS filter gate now uses `hasSecrets` (instance-map-aware) instead of raw `auraAPIBlocked`
- **Buff recast in combat now correctly filtered** — recasting a buff (e.g., MOW) after removal in combat is now hidden from the queue again; IsInPandemicWindow returns false when inCombatActivations shows a fresh cast with no timing data
- **Multi-cycle remove/reapply tracking in combat** — pending activation queue bridges UNIT_SPELLCAST_SUCCEEDED → UNIT_AURA addedAuras (2s FIFO window) to map new aura instance IDs when spellId is secret; supports unlimited remove/recast cycles within a single combat; filters harmful auras (debuffs) from consuming pending activation entries
- **Interrupt list now refreshes on spec/talent changes** — `resolvedInterrupts` was only built during frame creation; now re-resolved in `OnSpellsChanged` and `OnSpecChange` so talent-gated CC/interrupt spells appear immediately; deferred to out-of-combat to prevent `IsSpellAvailable()` secret restrictions from wiping the list
- **Channeling check now secret-safe** — replaced `UnitChannelInfo("player") ~= nil` with `PlayerChannelBarFrame:IsShown()` (NeverSecret visual frame) to avoid potential taint from secret return values
- **Elapsed-time fallback now secret-safe** — the short-cast duration filter's `castBar.spellID` comparison is now pcall-wrapped; in PvP contexts where spellID is secret, prevents taint crash from secret boolean in control flow

## [4.1.1] - 2026-02-22

### Changed
- Default `targetFrameAnchor` changed from `"TOP"` to `"DISABLED"` — new/reset profiles no longer snap to the target frame by default
- Dragging the panel now auto-disables the target frame anchor so the frame stays where you put it
- Frame is now only draggable via the grab tab — prevents accidental repositioning when interacting with icons

### Fixed
- Fixed frame snapping to right side of screen after update or profile reset (target frame anchor was re-applied on every drag stop)
- Fixed inability to reposition the panel when target frame anchor was enabled — dragging would immediately snap the frame back
- Added detection for unavailable/replaced TargetFrame (ElvUI, SUF, etc.) — anchoring gracefully falls back to saved position
- Added off-screen safety check on load — if saved position is outside screen bounds (resolution/scale change), frame resets to center
- Fixed update-freeze-during-drag not working (`isDragging` was set on grab tab but checked on addon object)
- Fixed SavePosition saving garbage coordinates when frame was anchored to TargetFrame (now skips save when anchored)
- Removed unnecessary ForceUpdate from SavePosition (saving coords shouldn't rebuild spell queue)

## [4.1.0] - 2026-02-21

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
- **Interrupt icon missing tooltip & click handlers**: `CreateInterruptIcon` was passing `isClickable=false` to `CreateBaseIcon`, disabling mouse input entirely. Now passes `true` and adds full interactive behavior matching DPS/defensive icons:
  - Tooltip (`OnEnter`/`OnLeave`): spell info, hotkey display, custom hotkey hint — respects `tooltipMode` setting
  - Right-click: opens hotkey override dialog
  - Drag to move: repositions the frame (delegates to mainFrame, same as DPS icons)
  - Masque skinning: registered with MasqueGroup so interrupt icon matches custom button skins
  - Out-of-range red hotkey: hotkey text turns red when target is beyond interrupt range (throttled, secret-safe)
  - Channeling grey-out: icon desaturates when player is channeling (can't interrupt during own channel)
  - `HideInterruptIcon` now resets `cachedOutOfRange`, `lastOutOfRange`, `lastVisualState`, and clears desaturation

## [4.0.0] - 2026-02-21

### Added

- **Interrupt Reminder System** — Detects interruptible casts on your target via nameplate cast bar state and shows your best available interrupt as a "position 0" icon before the DPS queue. Works in both Standard Queue and Nameplate Overlay modes.
  - **Interrupt Mode** dropdown: Important Only (shows for lethal/must-interrupt casts via `C_Spell.IsSpellImportant`), All Casts (any interruptible cast), or Off
  - **CC Non-Important Casts** toggle (on by default): Uses stuns/incapacitates to interrupt non-important casts on CC-able (non-boss) mobs, saving your true interrupt lockout for dangerous casts
  - Per-class interrupt + CC spell lists in SpellDB with automatic override resolution
  - Boss-aware filtering: CC abilities automatically skipped against CC-immune targets
  - De-duplication: interrupt icon hidden when it matches DPS queue position 1
  - Secret-safe: all cast bar visibility checks wrapped in pcall for 12.0 combat taint
  - Red interrupt glow distinguishes from normal DPS/proc glows
- **Nameplate Overlay: Icon Spacing** — New "Spacing" slider (0–10 px, default 2) controls the gap between successive icons in the cluster for both DPS and defensive rows. Applies to horizontal and vertical expansion modes. Replaces the hardcoded 2 px constant.
- **Nameplate Overlay: Opacity** — New "Frame Opacity" slider (0.1–1.0) for the overlay cluster. Applies to DPS icons, defensive icons (respects fade-in animation), and the health bar independently of the main panel opacity.
- **Nameplate Overlay: Show Key Press Flash** — New toggle to enable/disable key-press flash feedback on overlay DPS icons, independently of the main panel flash setting.
- **Nameplate Overlay: Options reorganized** — Overlay tab now structured in three logical sections: shared settings at top (anchor, expansion, health bar position, icon size, spacing, opacity, highlight mode, hotkeys, flash), then an "Offensive Queue" section (offensive slots), then a "Defensive Suggestions" section (enable, visibility, defensive slots, health bar).
- **DefensiveEngine module** — Extracted ~855 lines of defensive spell logic from JustAC.lua into `DefensiveEngine.lua` (LibStub `JustAC-DefensiveEngine` v1) for maintainability. Core addon retains thin wrapper methods.

### Changed

- **BlizzardAPI v30**: Removed dead code — `GetBypassFlags()`, `IsCooldownFeatureAvailable()`, `IsDefensivesFeatureAvailable()`, `TestCooldownAccess()` all had no external consumers. Feature availability struct simplified from 5 fields to 3.
- **SpellQueue v34**: `GetRotationSpells()` result is now cached and only refreshed on `RotationSpellsUpdated` event (was called ~10/sec in combat). Replaced `GetBypassFlags()` table allocation with direct `IsProcFeatureAvailable()` call.
- Default icon size changed from 36 to 42 for new profiles
- Default defensive icon scale changed from 1.2 to 1.0 for new profiles

### Fixed

- **Dynamic transform hotkeys missing** (e.g. Templar Strike → Templar Slash): ActionBarScanner v35 — pass `onlyKnown=false` to `C_Spell.GetOverrideSpell()`, added `FindSpellOverrideByID` fallback and forward override scan for aura-driven combat transforms
- **Frame rebuild consistency**: All frame-affecting Options setters unified through single `UpdateFrameSize()` path; health bar width now updates immediately on config changes
- **Defensive "Reset to Defaults"**: Synced hardcoded reset values with actual profile defaults (health bar, glow mode, icon count, items, display mode were all mismatched)
- **BlizzardAPI**: `TestProcAccess()` accessed `spells[1].spellId` but `GetRotationSpells()` returns a flat array of numbers — secret-value detection for procs was dead code (fail-open masked the bug). Now correctly uses `spells[1]`.
- **BlizzardAPI**: `GetActionInfo()` filtered Assisted Combat placeholder slots by checking `id == "assistedcombat"` but Blizzard's canonical filter is `subType == "assistedcombat"`. Now checks both `subType` and `id` for robustness.
- Nameplate Overlay: "Show Hotkeys" and "Show Flash" settings now apply to defensive overlay icons as well as DPS icons (both now pass their own override to ShowDefensiveIcon instead of reading the main panel's defensives profile)
- Nameplate Overlay: key-press flash for defensive overlay icons was gated on the main panel's `defensives.showFlash` setting instead of the overlay's own `showFlash`

### Removed

- Nameplate Overlay: "Show Procced Defensives" toggle removed — procced spells always appear in the overlay defensive queue; the Highlight Mode dropdown controls whether they receive special highlighting

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
