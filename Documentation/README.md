# Documentation index

Use this as a router, not a reading list. Read the relevant section of one
reference first; inspect code/source when implementation facts are needed.
Current version, interfaces and load order live in [JustAC.toc](../JustAC.toc);
module versions, constants, exports and cache invalidation live in code.

## Working references

| Question | Read |
|---|---|
| Contributor rules | [AGENTS.md](../AGENTS.md) |
| Player features, configuration and source credits | [Project README](../README.md) |
| CurseForge description copy | [CurseForge_JustAC.md](CurseForge_JustAC.md) |
| Shared Retail/Forever rules | [CLIENT_COMPAT.md](CLIENT_COMPAT.md) |
| Tests, mirrors, data generation, captures and release | [DEV_TOOLING.md](DEV_TOOLING.md) |
| Lua, modules, options and compile limits | [STYLE_GUIDE_JUSTAC.md](STYLE_GUIDE_JUSTAC.md) |
| Verified combat signals and secrecy | [12.0_COMPATIBILITY.md](12.0_COMPATIBILITY.md), Combat-Safe Signal Reference |
| Aura call denial and engine-driven display | [AURA_CONTAINER_12.1.md](AURA_CONTAINER_12.1.md) |
| Specific aura identity and measured dead ends | [AURA_IDENTITY_12.0.md](AURA_IDENTITY_12.0.md) |
| Duration readiness | [SECRET_VALUE_READINESS_PROBE.md](SECRET_VALUE_READINESS_PROBE.md) |
| Health/power/duration/stack thresholds | [SECRET_VALUE_THRESHOLD_GATES.md](SECRET_VALUE_THRESHOLD_GATES.md), especially The Scope Rule |
| Assisted Combat API | [ASSISTED_COMBAT_API_DEEP_DIVE.md](ASSISTED_COMBAT_API_DEEP_DIVE.md) |
| Macros and binds | [MACRO_PARSING_DEEP_DIVE.md](MACRO_PARSING_DEEP_DIVE.md) |
| Click protection | [CLICK_HARDWARE_EVENTS.md](CLICK_HARDWARE_EVENTS.md) |

These are references, not promises that every old statement applies to the
installed client. Use dated/contextual evidence and matching-client source;
update the owning reference when a measurement changes a conclusion.

## Active research, not verified behavior

[FOREVER_COMBAT_SIGNALS.md](FOREVER_COMBAT_SIGNALS.md) is the entry point for the
temporary shared capture and current interrupt/CC review. It separates existing
consumers from candidates. The numeric-selector boolean bridge and other new
candidates still require in-game controls on each client.

Do not promote a candidate because a mock passes, an API is callable, or a single
false/empty sample is plain. Require repeated positive/negative transitions,
liveness, correct subject and explicit unknown/error handling.

## Historical plans and research

Open these only for a named question, prior decision or contradictory evidence.
They are not task queues or current implementation inventories.

| Document | Scope / caution |
|---|---|
| [FOREVER_PROBE_PLAN.md](FOREVER_PROBE_PLAN.md) | Early port probes and dated captures; old branch/status assumptions |
| [PROBE_PLAN_68887.md](PROBE_PLAN_68887.md) | Build-68887 hypotheses; current interrupt/CC corrections are in active research |
| [MIDNIGHT_POST_LAUNCH_RESEARCH.md](MIDNIGHT_POST_LAUNCH_RESEARCH.md) | Launch-era API research, with some later corrections |
| [AURA_DETECTION_ALTERNATIVES.md](AURA_DETECTION_ALTERNATIVES.md) | Earlier aura techniques; later denial/identity references take precedence |
| [FOREVER_ENGINE_DESIGN.md](FOREVER_ENGINE_DESIGN.md) | Design rationale and rotation provenance, not current port status |
| [FOREVER_DEAD_CODE.md](FOREVER_DEAD_CODE.md) | Historical inventory, not permission to delete shared Retail paths |
| [HEAL_MODE_PLAN.md](HEAL_MODE_PLAN.md) | Design proposal, not proof that listed features are absent or implemented |
| [SAFE_LEAD_PLAN.md](SAFE_LEAD_PLAN.md) | Ordering rationale; verify actual queue behavior in code |
| [ASSISTED_COMBAT_DATA_PLAN.md](ASSISTED_COMBAT_DATA_PLAN.md) | Data-audit history; read tools for current output and flags |

## Maintenance

- Keep durable rules in the root instructions, operational detail in its owning
  reference, and dated evidence in research. Link instead of duplicating tables.
- Do not maintain copied module versions, warning totals, file counts, API
  exports or current build labels. Verify the source of truth when needed.
- Preserve historical measurements with their client/build/context; mark stale
  conclusions rather than silently treating them as current.
- Documentation and contributor instructions are excluded from addon packages
  by [.pkgmeta](../.pkgmeta). Package exclusion does not mean Git exclusion.
