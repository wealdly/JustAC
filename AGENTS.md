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
  just matching client paths or version labels. `python tools/deploy_runtime.py --apply`
  does the copy and every check. Preserve SavedVariables and unrelated
  files. See [runtime test sync](Documentation/DEV_TOOLING.md#runtime-test-sync).
- Keep release notes player-facing in [UNRELEASED.md](UNRELEASED.md).
  Research, probes and tooling do not belong in player release notes.
- Public text (README, CHANGELOG, UNRELEASED, release notes) never mentions how secret
  health, power or durations are read: no threshold curves or gates, percentage bands, slider
  steps or "below N%" detection. Describe only what the player sees the queue do.
- No AI attribution, acknowledgments or co-author trailers in project files or
  commits. Preserve required upstream source/license credits.
- No em dashes in project files.

## Rotation and queue principles

Apply these to every list, queue stage and proposal. Full text, margins and the ordered change
check: [core principles](Documentation/FOREVER_DPS_PRINCIPLES.md#core-principles).

**Goal:** high, reliable damage that an ordinary player can follow without effort, for each class
and build as it is actually played. Good enough in most fights beats perfect in a few.

- **Simplicity leads every decision**, in design and in the player's choices. Start from the
  simplest option. Complexity compounds: judge each step against the build's simplest play, not
  the last accepted version. Extra buttons, setup presses, stance or form swaps, new rules,
  stages and settings must together clear the
  [simplicity margins](Documentation/FOREVER_DPS_PRINCIPLES.md#simplicity-margins); removing
  complexity needs none. Of two designs that do the same job, take the one with fewer parts.
- **Hard limits**, never traded for damage or simplicity:
  1. **Damage only**, in every talent tree, tank and healer trees included. Utility stays with
     the player even when a guide or sim lists it: slows, roots, mitigation or threat debuffs,
     healing, crowd control. Debuffs that raise the damage a target takes count as damage. A
     damaging spell never waits on its own non-damaging side effect. The one exception is a
     ranged opener on a melee target. Tank and healer help belongs in the defensive queue
     ([utility scope](Documentation/FOREVER_ENGINE_DESIGN.md#damage-only-queue)).
  2. **Confirmed signals and sound inference.** Unknown stays unknown unless soundly inferred:
     confirmed inputs linked by a game rule or in-game measurement, unknown when any input is,
     expiring when stale, cheap when wrong, labelled as an inference
     ([inference rule](Documentation/FOREVER_DPS_PRINCIPLES.md#3-what-a-condition-may-use)).
     Never infer from an unrelated signal. Estimate a secret value only when a decision needs it.
  3. **Damage now, in this context.** A spell that cannot deal damage in the confirmed context
     (a cast while moving, out of range, locked out, an immune target, a target that dies first)
     is never the press for now.
  4. **The player owns strategy and settings.** Kiting, positioning, crowd-control timing and
     encounter tactics are theirs; no entry, gate or probe advises them. Custom lists, explicit
     settings and overrides are never changed to make a rule work.
- **Weighed together**, with simplicity breaking ties: reliable before peak (never clearly worse
  on any reference target); easy to follow (the first slot is the press for now, the order is
  stable, the same situation gives the same answer, never ask to switch targets); one general,
  data-derived rule over class, spell or build exceptions; state the evidence grade and wait for
  approval before a behavior change.
- **Stable, followable output.** A queue that changes faster than the player can press is a
  burden. Aim for one change of the first slot per press (global cooldown or cast): decide for
  the moment the player can next act, count a sent press as done until the game catches up,
  hold the plan through a cast or channel, change only on events that matter, and let the shown
  order win ties. Flip rate is measured, not assumed
  ([stable output](Documentation/FOREVER_DPS_PRINCIPLES.md#stable-followable-output)).
- **Net damage.** Value a press by what it adds over what it displaces. Instant specials add
  to the auto attack and are never weighed against it; next-swing attacks replace a white swing
  and its rage, and casts can stop a wand or delay an auto shot; a queued next-swing attack is
  never displaced by another
  ([net damage](Documentation/FOREVER_DPS_PRINCIPLES.md#net-damage-adding-to-or-displacing-the-auto-attack)).
- **Direct the order, respond to the situation.** Choose the next press decisively among what
  works where the player is. Asking them to stand still, swap stance or close distance is a
  complication; asking them to switch targets never happens. Respond to changes that last, not
  to every twitch; when directing and responding collide, respond.
- **Fit the class and build.** The baseline is the build's own simplest play (Affliction spreads
  damage over time; a solo Frost mage fights around crowd control). Hard limits still hold: the
  queue responds to the player's tab or kite rather than directing it. A build-specific rule is
  keyed on data, never a class exception in shared code. Play the limits cannot serve is left to
  the player and noted in the class guide.

## Cross-client correctness

- Preserve both clients' queue ordering, resources, UI, options, profiles, generated
  data and packaging. Test affected shared behavior on both, including custom
  lists and explicit settings. Do not change player overrides to make a fix work.
- Prefer existing shared helpers and capability checks. Use `SpellDB.IsForever()`
  or `BlizzardAPI.IsForever()` only for verified client differences; no scattered
  build checks or spell/class exceptions in generic logic.
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
  new thresholds read the threshold scope rule. Estimate a hidden number only when a decision
  needs it, under that rule.
  See the task-specific links in the [documentation index](Documentation/README.md).

## Validation and diagnosis

- Put multi-line edit or analysis scripts in a temporary file rather than an inline
  shell heredoc; quotes and backslashes in Lua/Markdown text break heredocs on Windows.
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

Use the [documentation index](Documentation/README.md) when a task needs project
policy, client behavior, tooling, data or research context. For a localized code
or test change, start with the relevant source and tests; consult only directly
relevant docs when the task requires them. Read the relevant heading/range, not
the whole file or research archive. Do not load old plans by default. Treat dated
findings as build/client/context-specific; distinguish measured results,
source-backed candidates and untested ideas. Do not rerun settled dead ends
without a concrete new API, composition or contradictory measurement.

| Task | Primary reference |
|---|---|
| Client behavior and compatibility | [CLIENT_COMPAT.md](Documentation/CLIENT_COMPAT.md#rules) |
| Code patterns and options | [STYLE_GUIDE_JUSTAC.md](Documentation/STYLE_GUIDE_JUSTAC.md#module-system-libstub); read the specific pattern section needed |
| Secrecy and combat signals | Relevant topic in the [documentation index](Documentation/README.md#working-references); [12.0 signal notes](Documentation/12.0_COMPATIBILITY.md#combat-safe-signal-reference) are historical and must be reverified |
| Lua checks | [DEV_TOOLING.md](Documentation/DEV_TOOLING.md#lua-static-analysis) |
| Runtime test sync | [DEV_TOOLING.md](Documentation/DEV_TOOLING.md#runtime-test-sync) |
| Data refresh | [DEV_TOOLING.md](Documentation/DEV_TOOLING.md#two-client-update-check-and-refresh) |
| Rotation principles; refining a Forever list (start here) | [FOREVER_DPS_PRINCIPLES.md](Documentation/FOREVER_DPS_PRINCIPLES.md) |
| Forever priority lists and interrupt tables | [DEV_TOOLING.md](Documentation/DEV_TOOLING.md#changing-a-forever-priority-list) |
| Captures and release | Relevant section in [DEV_TOOLING.md](Documentation/DEV_TOOLING.md) |
| Player behavior, configuration, source credits | [README.md](README.md) |

Data updates must cover both clients, use one complete build per CSV folder and
stage downloads before generation. Never hand-edit generated output or regenerate
from failed/mixed downloads. Source freshness and rotation freshness are separate.
Before adopting external sources verify license compatibility, preserve notices,
and record authors, URL, license, pinned revision and adaptations. See
[the refresh workflow](Documentation/DEV_TOOLING.md#two-client-update-check-and-refresh).
