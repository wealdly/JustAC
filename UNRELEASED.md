## [Unreleased]

### Changed
- `build.ps1`: `$coreFiles` now derived from `JustAC.toc` at build time instead of a hardcoded list — new `.lua` files added to the TOC are automatically included in the distribution ZIP
- `UI/UIRenderer.lua`: Extracted `MatchesSpellOrOverride()` helper from duplicated `C_Spell.GetOverrideSpell` check blocks in `MatchActiveCast` and the defensive-icon active-cast detection; no behaviour change
