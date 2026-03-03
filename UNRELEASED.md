## [Unreleased]

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

### Fixed
- **Overlay respects shared `showProcs` setting**: The nameplate overlay defensive queue previously hardcoded `showProcs=true`, ignoring the user's "Insert Procced Defensives" setting. Now correctly reads `profile.defensives.showProcs`.

### Fixed
- **Overlay-only fallback**: When `displayMode` is set to "Overlay Only" and the target's nameplate is not rendered (too far, culled by stacking limits, hidden by nameplate addon), the main panel now shows as a fallback so users never lose their combat queue. Applies to both the offensive queue (UIRenderer) and the defensive queue (DefensiveEngine). As soon as the nameplate reappears, the overlay takes over and the main panel hides again.
- **Disabled-function corrections** (7 settings):
  - `includeHiddenAbilities`, `showSpellbookProcs`, `hideItemAbilities` — No longer grayed out in overlay-only mode (SpellQueue feeds both surfaces).
  - `glowMode` (offensive) — Now correctly grayed out in overlay-only mode (only UIRenderer uses it).
  - `defensives.showProcs`, `defensives.allowItems`, `defensives.autoInsertPotions` — Now available when either surface's defensives are enabled (standard panel or overlay), not just the standard panel.
