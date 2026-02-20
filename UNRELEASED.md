# Unreleased Changes

Changes accumulated since last version release. Will be moved to CHANGELOG.md on next version bump.

## Current Version: 3.25.2

**Instructions:**

- Add changes here as they're made
- When version is bumped, move these to CHANGELOG.md and clear this section
- Don't increment version numbers without explicit instruction

### Added

- **Items in defensive queue** — Negative numbers in spell lists represent items (-itemID)
  - `BlizzardAPI.CheckDefensiveItemState(itemID, profile)` — validates item count and cooldown
  - Options UI: Add items via `-itemID` or `item:ID` syntax in the manual input field
  - Items display with `[Item]` tag and correct icon/name in the spell list editor
  - `GetUsableDefensiveSpells` handles mixed spell/item lists, deduplicates with hardcoded potions
  - `GetBestDefensiveSpell` returns `itemID, true` for item entries
  - Backward compatible: existing positive-only spell lists work unchanged

### Changed

- BlizzardAPI library version bumped to v29

### Fixed

- **Disabled spec profile not applied on login/reload** — JAC would display even for specs set to "DISABLED" until the user switched profiles. `PLAYER_ENTERING_WORLD` now calls `OnSpecChange()` to apply the spec profile (including disabled state) on world entry, not only when `PLAYER_SPECIALIZATION_CHANGED` fires.
- **Defensive icons/health bar could re-appear while spec-disabled** — `UNIT_HEALTH` events fire regardless of disabled mode; `OnHealthChanged` now guards on `isDisabledMode` so live health changes can't undo the hide performed by `EnterDisabledMode`.

### Removed

(No unreleased removals yet)
