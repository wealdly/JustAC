# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.26.0

**Instructions:**

- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

### Added

- **Nameplate Overlay** — Independent queue cluster that attaches directly to the target's nameplate. Fully separate from the main panel; either or both can be active at once. Includes DPS queue icons, defensive queue icons (opposite side), and a compact player health bar. Configurable anchor side, expansion direction (horizontal or vertical), icon count, icon size, glow mode, hotkey display, and per-section visibility. Overlay defensives operate independently of the main Defensive Suggestions setting.
- **Items in defensive queue** — Spell lists now accept equipped items (`-itemID` or `item:ID` syntax). Items display with an `[Item]` tag and correct icon/name in the editor. Auto-deduplication against hardcoded health potions.
- **Reset to Defaults buttons** — Each major options tab (General, Offensives, Overlay, Defensives) now has a section-scoped reset button. Spell lists and the blacklist are never affected.

### Changed

- Defensive suggestions enabled by default on new profiles
- BlizzardAPI library version bumped to v29

### Fixed

- DPS icons invisible after icon refactor (alpha not reset on slot reuse)
- Defensive spells on cooldown permanently hidden in combat — cooldown swipe is now the visual indicator; visibility is no longer gated on cooldown state
- Rotation list positions 2+ permanently hiding spells on cooldown
- Cooldown swipe not re-shown when an icon slot is reused
- Icon background corner-clipping (rounded mask now applied to background as well as texture)
- Disabled spec profile not applied on login/reload until the user manually switched specs

### Removed

(nothing yet)
