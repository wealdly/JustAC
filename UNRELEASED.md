## [Unreleased]

### Fixed
- Several potential mid-combat errors from protected (secret) combat values: the enrage-cleanse cue on the nameplate overlay, the overlay health and pet health bars, the execute-context target latch, an assisted-combat usability fallback, and `/jac inspect auras` / `/jac inspect castdiag` output.
- Changing the Input Preference (keyboard/gamepad) option now updates displayed hotkeys immediately instead of after the next binding update.
- The Proc Priority toggle no longer appears on lists whose engines ignore it (gap-closers, burst, pet rez), and removing a spell from one of those lists no longer discards the proc-priority setting the same spell has in the defensive or rotation lists.
- A stuck highlight glow on nameplate overlay icons when leaving combat.
- The enrage-cleanse cue now hides together with the nameplate overlay (mounted, visibility rules, or overlay teardown).
- Two damage-over-time spells landing in the same update are now attributed to the right casts.
- The overlay's Defensive Display reset now also resets the resource bar option.
- Burst injection could keep serving the previous spec's spell list in rare spec-switch sequences; talent changes now refresh imported rotation rankings without a reload.
- Empty queue slots no longer keep a stale charge cooldown ring; pet-summon talent variants are now recognized by the redundancy filter; a disabled cooldown-swipe fallback for off-bar spells works again.

- Pre-combat buff suggestions are now strictly tied to the defensive bar: with defensives disabled they never appear, and their options section grays out to make the dependency clear.

### Changed
- Large internal cleanup: duplicated rendering, options, health-bar, and engine logic consolidated and dead code removed (roughly 770 fewer lines). No visual or behavioral changes intended beyond the fixes above.
- `/jac` spell name lookup no longer freezes the game briefly when a name isn't found.
