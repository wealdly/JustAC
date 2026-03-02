## [Unreleased]

### Changed
- Reduced update pipeline latency for faster rotation display after casting:
  - `OnCooldownUpdate` debounce: 100ms → 40ms
  - `ScheduleUpdate` debounce: 100ms → 40ms
  - SpellQueue combat throttle: 100ms → 50ms (20 updates/sec)
  - SpellQueue out-of-combat throttle: 150ms → 120ms
  - UIRenderer cooldown overlay: 150ms → 80ms
  - UINameplateOverlay cooldown overlay: 150ms → 80ms
  - OnUpdate out-of-combat dirty rate floor: 150ms → 100ms- Shortened interrupt mode dropdown labels across all locales

### Added
- Defensive queue usability visuals: icons grey out while channeling, blue-tint when lacking resources, desaturate when on cooldown (mirrors offensive queue behavior)
- Defensive queue usability-aware sorting: unusable spells (on cooldown or resource-blocked) are deprioritized to the bottom of the queue so castable abilities appear first

### Changed
- Defensive health thresholds in combat (12.0 secret health adaptation):
  - Self-heal tier now always active in combat (configurable 80% threshold is undetectable when UnitHealth is secret)
  - Cooldown tier triggers at LowHealthFrame "low" signal (~35%) instead of waiting for "critical" (~20%), since the configurable 60% threshold is also undetectable
  - Out-of-combat thresholds unchanged (exact health available)

### Fixed
- Gap-closer glow on nameplate overlay defaulted to ON instead of matching main panel (OFF by default)
- DefensiveEngine `showProcs` override precedence (Lua and/or short-circuit with false values)