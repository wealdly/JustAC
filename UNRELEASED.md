## [Unreleased]

### Fixed
- **Overlay-only fallback**: When `displayMode` is set to "Overlay Only" and the target's nameplate is not rendered (too far, culled by stacking limits, hidden by nameplate addon), the main panel now shows as a fallback so users never lose their combat queue. Applies to both the offensive queue (UIRenderer) and the defensive queue (DefensiveEngine). As soon as the nameplate reappears, the overlay takes over and the main panel hides again.
