## [Unreleased]

### Added
- **Replace Quest Indicator** (Overlay): Suppresses the engine-rendered quest exclamation mark (`!`) on nameplates and renders our own version above the nameplate center, preventing overlap with the icon queue. Uses `UnitIsQuestBoss()` for detection and `SetCVar("ShowQuestUnitCircles", "0")` for suppression. Original CVar restored on disable/unload. Enabled by default; toggle in Overlay → Layout.

### Fixed
- **RedundancyFilter v40**: NeverSecret aura timing data (duration, expirationTime) was always zero in combat. `GetAuraTiming` used `Unsecret()` which trusts `issecretvalue()` — returns `true` even for NeverSecret fields (generic marking). Switched to pcall arithmetic bypass (`auraData.duration + 0`) matching the pattern already used for spellId. Fixes long-duration buff expiration reminders (raid buffs, rogue poisons) not appearing when buffs near expiry.
