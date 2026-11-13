# JustAC contributor instructions

Lua + WoW API + Ace3 addon for Retail and WoW Forever. Maintain one shared
`main` branch and release. Read [JustAC.toc](JustAC.toc) for supported interfaces,
version, dependencies and load order; do not duplicate changing inventories here.

## Workflow

- Propose changes before implementing; obtain approval for behavior/scope changes.
- Preserve unrelated work. Do not build, commit, push, tag or publish
  without authorization. Never bump the addon version unless explicitly requested.
- Edit and test in the development checkout, not through a client addon junction.
  After every validated runtime update, deploy to the shared runtime target used
  by Retail and Forever. This local deployment has standing authorization; verify
  contents against source, junction targets and active TOC/XML dependencies, not
  just matching client paths or version labels. Preserve SavedVariables and unrelated
  files. See [runtime test sync](Documentation/DEV_TOOLING.md#runtime-test-sync).
- Keep release notes player-facing in [UNRELEASED.md](UNRELEASED.md).
  Research, probes and tooling do not belong in player release notes.
- No AI attribution, acknowledgments or co-author trailers in project files or
  commits. Preserve required upstream source/license credits.
- No em dashes in project files.

## Cross-client correctness

- Preserve both clients' queue ordering, resources, UI, options, profiles, generated
  data and packaging. Test affected shared behavior on both, including custom
  lists and explicit settings. Do not change player overrides to make a fix work.
- Prefer existing shared helpers and capability checks. Use `SpellDB.IsForever()`
  or `BlizzardAPI.IsForever()` only for verified client differences; no scattered
  build checks or spell/class exceptions in generic logic.
- Unknown remains unknown. Do not infer hidden resources, aura identity or
  mechanic state from an unrelated signal. General priorities need not simulate
  optimal play, but must use confirmed signals for every supported context.
- Never guess WoW API behavior. Check the matching client's generated API docs,
  caller implementation and saved in-game evidence. Source annotations describe
  contracts, not proof of live taint/secrecy behavior.

## Lua safety

- Four spaces, camelCase locals, UPPER_SNAKE constants, early returns.
  Keep implementation variables local; do not introduce accidental globals.
  Follow existing module/public API names; localize repeated hot-path lookups.
- Use `LibStub("JustAC-Module", true)` and check availability before use.
  Preserve TOC dependency order; options panels resolve `JustAC-Options` per call
  because `Options\Core.lua` loads last. Bump LibStub versions on breaking changes.
- Wrap fallible WoW calls in `pcall`; preserve explicit error/unknown outcomes.
  Use `BlizzardAPI.GetActionInfo()` to filter the `"assistedcombat"` pseudo-ID.
- Never use `a and b or c` when `b` can be nil/false; write an explicit branch.
- Use `BlizzardAPI.IsSecretValue()` before comparing, branching on or performing
  arithmetic with potentially secret values. Never iterate secret payload lists.
- Use `AreAurasSecret()` / `AreCooldownsSecret()`, not combat lockdown as a
  secrecy proxy. Call denial is separate from result secrecy: inspect `Requires*`
  as well as `Secret*`. A remembered plain aura never authorizes a denied call.
- Before buff/aura work read the relevant identity/container reference; before
  new thresholds read the threshold scope rule. No hidden-number reconstruction.
  See the task-specific links in the [documentation index](Documentation/README.md).

## Validation and diagnosis

- For changed Lua run `.\tools\check.ps1 <changed files>` before commit/reload.
  It prefers luacheck and falls back to syntax-only luaparser; add no errors or
  new warnings. Run the smallest relevant existing regression tests.
- For in-game regressions start with `/jac inspect validate`, then
  `/jac inspect errors` and `/jac inspect secrecy`; use `/jac inspect modules`
  for loading and `/jac why <spell>` for queue decisions.
- `INSPECT_TOPICS` in [DebugCommands.lua](DebugCommands.lua) is the authoritative
  probe registry; `/jac help` lists current commands. Do not copy the full list.
- Prefer bounded, debug-only time-series captures to pasted snapshots.
  SavedVariables flush only on `/reload` or logout: confirm a flush before
  reading disk results. Never mistake the previous session for live evidence.

## Read only what the task needs

Start with the [documentation index](Documentation/README.md), then read relevant
headings/ranges, not the whole research archive. Do not load old plans by default.
Treat dated findings as build/client/context-specific; distinguish measured
results, source-backed candidates and untested ideas. Do not rerun settled
dead ends without a concrete new API, composition or contradictory measurement.

| Task | Primary reference |
|---|---|
| Client behavior and compatibility | [CLIENT_COMPAT.md](Documentation/CLIENT_COMPAT.md) |
| Code patterns and options | [STYLE_GUIDE_JUSTAC.md](Documentation/STYLE_GUIDE_JUSTAC.md) |
| Secrecy and combat signals | [12.0_COMPATIBILITY.md](Documentation/12.0_COMPATIBILITY.md), relevant signal reference from the index |
| Tests, source/CSV refresh, generators, captures, release | [DEV_TOOLING.md](Documentation/DEV_TOOLING.md) |
| Player behavior, configuration, source credits | [README.md](README.md) |

Data updates must cover both clients, use one complete build per CSV folder and
stage downloads before generation. Never hand-edit generated output or regenerate
from failed/mixed downloads. Source freshness and rotation freshness are separate.
Before adopting external sources verify license compatibility, preserve notices,
and record authors, URL, license, pinned revision and adaptations. See
[the refresh workflow](Documentation/DEV_TOOLING.md#two-client-update-check-and-refresh).
