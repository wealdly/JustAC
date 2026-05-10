## [Unreleased]

### Fixed
- Raise Dead no longer shows for Blood and Frost Death Knights. It is now scoped to Unholy (spec 3) only, since Blood/Frost ghouls are Guardians rather than persistent pets.

### Changed
- Debug command surface consolidated to a single `inspect` namespace. All diagnostic sub-commands now live under `/jac inspect <topic>` and `/jac find [spell]`.

**Removed commands and their replacements:**

| Old command | New command |
|---|---|
| `/jac modules` | `/jac inspect modules` |
| `/jac testcd [spell]` | `/jac inspect cooldown [spell]` |
| `/jac defensive`, `/jac def` | `/jac inspect defensives` |
| `/jac interrupts`, `/jac int` | `/jac inspect interrupts` |
| `/jac burst` | `/jac inspect burst` |
| `/jac poisons`, `/jac poison` | `/jac inspect auras` |
| `/jac perf`, `/jac stats` | `/jac inspect perf [reset]` |
| `/jac diag` (alias) | `/jac inspect <topic>` |
| `/jac config`, `/jac options` | `/jac` (blank) |

**Removed with no replacement** (dead/broken commands): `test`, `formcheck`, `raw`, `testmacro`, `macrostats`.
