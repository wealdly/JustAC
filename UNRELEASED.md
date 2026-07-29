## [Unreleased]

### Fixed

- **No more error when you target an enemy.** With nameplate icons on, picking an
  enemy target could throw a "failed because Can't measure restricted regions"
  error. The overlay now skips that measurement and retries on the next pass.

### Changed

- **Out-of-combat buff reminders now come back before the buff runs out.** Flasks,
  food, augment runes, weapon oils, poisons, imbues and raid buffs used to be
  re-offered only once they had lapsed entirely (or, for the class buffs, from the
  halfway mark - half an hour of nagging on a 60-minute buff). Everything now
  surfaces on the same schedule: in the last 3 minutes solo, or the last 5 minutes
  in a group, where one recast covers everyone and wants to land before the pull.
- **Korean translation updated.** Every option and tooltip is now translated, and
  a number of earlier mistranslations have been corrected. Thanks to Crazyyoungs
  for the contribution.
