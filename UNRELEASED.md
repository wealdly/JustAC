## [Unreleased]

### Added
- **Instance-level CC immunity cache**: Mobs identified as CC-immune (bosses, certain elites) are now remembered by NPC ID for the duration of the instance. Repeat pulls of the same mob no longer re-learn CC immunity from scratch. The cache resets on zone change (`PLAYER_ENTERING_WORLD`). NPC IDs are extracted from `UnitGUID` out of combat and backfilled at combat end.

### Changed
- **Options restructured**: Split the "General" tab into two tabs:
  - **General** (new) — Shared settings that affect both surfaces: Display Mode, Interrupt Mode, Key Press Flash, Gamepad Icon Style, Interrupt Alert Sound.
  - **Standard Queue** (renamed from General) — Settings specific to the standard queue panel: layout, visibility, appearance, system.
- Interrupt Mode and Key Press Flash moved from the Offensives tab to General (they apply to both surfaces).

### Fixed
- **Overlay-only fallback**: When `displayMode` is set to "Overlay Only" and the target's nameplate is not rendered (too far, culled by stacking limits, hidden by nameplate addon), the main panel now shows as a fallback so users never lose their combat queue. Applies to both the offensive queue (UIRenderer) and the defensive queue (DefensiveEngine). As soon as the nameplate reappears, the overlay takes over and the main panel hides again.
- **Disabled-function corrections** (7 settings):
  - `includeHiddenAbilities`, `showSpellbookProcs`, `hideItemAbilities` — No longer grayed out in overlay-only mode (SpellQueue feeds both surfaces).
  - `glowMode` (offensive) — Now correctly grayed out in overlay-only mode (only UIRenderer uses it).
  - `defensives.showProcs`, `defensives.allowItems`, `defensives.autoInsertPotions` — Now available when either surface's defensives are enabled (standard panel or overlay), not just the standard panel.
