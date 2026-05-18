## [Unreleased]

### Changed
- `build.ps1`: `$coreFiles` now derived from `JustAC.toc` at build time instead of a hardcoded list — new `.lua` files added to the TOC are automatically included in the distribution ZIP
- `UI/UIRenderer.lua`: Extracted `MatchesSpellOrOverride()` helper from duplicated `C_Spell.GetOverrideSpell` check blocks in `MatchActiveCast` and the defensive-icon active-cast detection; no behaviour change
- `BurstInjectionEngine.lua`: Removed the local `GetSpecKey()` wrapper and replaced it with a direct cached `SpellDB.GetSpecKey` function reference at all call sites (nil-safe), reducing indirection without changing behaviour
- `UI/UIFrameFactory.lua` + `UI/UINameplateOverlay.lua`: Added `ApplyTextOverlaySettingsToIcons()` and switched nameplate Masque skin callback to use it, removing duplicated icon-loop text-overlay application logic
