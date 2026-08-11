## [Unreleased]

### Fixed
- Some entries in the default defensive lists could never appear, quietly holding a slot open for a button you can't press. Two causes: an ability the game no longer grants under that name, and an ability that is now a passive rather than something you press. Blood Death Knights, Protection Paladins, Warlocks, Vengeance Demon Hunters, Hunters and Evokers each had one or two. All now point at the live ability, or are gone where there no longer is one
- Unholy Death Knights: the burst reminder never lit up for Dark Transformation, because it was watching a version of the ability that no longer exists
- Restoration Druids and Mistweaver Monks: an emergency group heal that is no longer a castable ability has been removed from the emergency list, so the cue reaches for one you can actually press
- Divine Protection (Paladin) and Death Pact (Death Knight) are now treated as what they are - a major damage-reduction cooldown and a big instant heal - so they rise when you're in trouble instead of sitting among the routine fillers. Sacrificial Pact joins them
- Feral Druids: Regrowth no longer sits above Renewal in the defensive list. Renewal is instant and Regrowth is a cast, and the faster button should come first

### Changed
- Translations are complete again in every supported language. The options rework had left around fifty labels showing English text to everyone else; German, French, Italian, Russian, Spanish, Portuguese, Korean and both Chinese locales are all caught up
