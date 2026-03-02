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

### Fixed
- Gap-closer glow on nameplate overlay defaulted to ON instead of matching main panel (OFF by default)
- DefensiveEngine `showProcs` override precedence (Lua and/or short-circuit with false values)