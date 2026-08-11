# JustAC - Contributor Instructions

WoW addon displaying Blizzard's Assisted Combat suggestions with keybinds. Lua + WoW API + Ace3.

## Version Detection & Compatibility

**WoW 12.0 (Midnight) compatibility layer ready** - Use version conditionals for breaking API changes:

```lua
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Check version
if BlizzardAPI.IsMidnightOrLater() then
    -- 12.0+ code path (new/fixed API)
else
    -- Pre-12.0 code path (original API)
end
```

**When to add version conditionals:**
- 12.0 error reported → Add conditional fix
- API behavior changes between versions → Wrap in version check
- New API replaces old → Keep both paths with version guard

**See:** `Documentation/VERSION_CONDITIONALS.md` for detailed patterns and examples

## Critical Workflow

1. **NEVER guess WoW API behavior** - Verify with `/script` commands in-game or check the local source mirrors in `R:\WOW\00-SOURCE\` (`wow-ui-source\Interface\AddOns` incl. `Blizzard_APIDocumentationGenerated`, and `WowPacketParser\WowPacketParser\Enums`; refresh both with `R:\WOW\00-SOURCE\update-sources.ps1`)
2. **Propose before implementing** - Describe changes, ask "Should I proceed?"
3. **Test with debug commands** - Use `/jac inspect modules`, `/jac find`, `/jac inspect cooldown` to validate changes
4. **DO NOT auto-increment versions** - Track changes in `UNRELEASED.md`, only bump version on explicit instruction
5. **DO NOT auto-build or push** - Commit changes, let user build/push manually
6. **NO AI attribution** - Never add `Co-Authored-By`, credits, acknowledgments, or any other reference to AI agents/models in commit messages, code comments, README, CHANGELOG, or any project file. All contributions are authored solely by the project owner.
7. **Release notes must be player-facing** - `UNRELEASED.md` and `CHANGELOG.md` should focus on user-visible changes, fixes, and configuration impacts. Technical details are allowed, but keep them simple and concise. Never mention AI, agents, models, or tooling attribution in release notes.

## Lua validation (before commit / `/reload`)

WoW loads Lua at runtime, so a brace slip or a typo'd global is a silent load
failure. Run the static-analysis gate on anything you touch:

```
tools/check.ps1 SpellQueue.lua UI/UIRenderer.lua   # specific files
tools/check.ps1                                     # whole addon
```

It prefers **luacheck** (config `.luacheckrc`: undefined globals, unused locals,
syntax) and falls back to a **luaparser** syntax check. Baseline is 54 known
warnings / 0 errors, all of them WoW globals the config does not list plus
multiple-return placeholders in `FormCache.lua`; a clean change adds no errors and
no *new* warnings. If no
checker is installed, `check.ps1` prints the install command. Details:
`Documentation/DEV_TOOLING.md`.

## Versioning

**Semantic Versioning (MAJOR.MINOR.PATCH):** (current version: see `## Version:` in `JustAC.toc`)
- Hotfixes: 4.5.5, 4.5.6, etc. (bug fixes only)
- Features: 4.6.0, 4.7.0, etc. (new functionality)
- Breaking: 5.0.0, 6.0.0, etc. (major rewrites)

Update in three places: `JustAC.toc`, `CHANGELOG.md`, `UNRELEASED.md`

## Architecture (Load Order Matters)

LibStub modules in `JustAC.toc` - **MUST edit in dependency order**:

```
BlizzardAPI → FormCache → MacroParser → ActionBarScanner → RedundancyFilter
                                    ↓
              DotTracker → MaintenanceTracker → SpellQueue → UI/*
                                    ↓
              DefensiveEngine → GapCloserEngine → PrecombatEngine
                                    ↓
              DebugCommands → DebugHUD → Options/* → TargetFrameAnchor → KeyPressDetector → JustAC
```
Note `Options/Core.lua` loads LAST of the `Options/*` files: the panels resolve
`LibStub("JustAC-Options")` per call, not at load time.

| Module | Role | Key Exports | Current Version |
|--------|------|-------------|-----------------|
| `Locales/*.lua` | AceLocale-3.0 localization (9 languages) | `L` global | N/A (not LibStub) |
| `SpellDB.lua` | Static spell data (defensive, class defaults) | `GetDefaults()`, `GetSpecKey()` | v20 |
| `RotationImport.lua` | Alternate rotation source (gated import lookup + burst anchors) | `GetRotation()`, `HasRotation()`, `RegisterGated()`, `GetBurstTriggers()` | v1 |
| `BlizzardAPI.lua` | Root: secret value primitives, live secrecy gates, version detection | `IsSecretValue()`, `Unsecret()`, `AreCooldownsSecret()`, `AreAurasSecret()`, `GetActionBarUsability()` | v36 |
| `BlizzardAPI/CooldownTracking.lua` | Local CD tracking (12.0+ secret workaround) | `IsSpellReady()`, `RegisterSpellForTracking()`, `IsSpellOnLocalCooldown()` | v13 |
| `BlizzardAPI/SecretValues.lua` | Feature availability gates, aura timing | `IsRedundancyFilterAvailable()`, `GetFeatureAvailability()` | v2 |
| `BlizzardAPI/SpellQuery.lua` | Spell info, usability, rotation API, items | `GetProfile()`, `GetSpellInfo()`, `IsSpellUsable()` | v2 |
| `BlizzardAPI/StateHelpers.lua` | Defensive/item state, health, CC immunity, target analysis | `CheckDefensiveItemState()`, `GetPlayerHealthPercent()`, `IsTargetCCImmune()` | v14 |
| `FormCache.lua` | Shapeshift form state (Druid/Rogue/etc) | `GetActiveForm()`, `GetFormIDBySpellID()` | v11 |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` conditional parsing | `GetMacroSpellInfo()`, quality scoring | v25 |
| `ActionBarScanner.lua` | Spell→keybind lookup, slot caching | `GetSpellHotkey()`, `GetSlotForSpell()` | v38 |
| `RedundancyFilter.lua` | Hide active buffs/forms | `IsSpellRedundant()` | v45 |
| `DotTracker.lua` | Sink maintained enemy DoTs while their debuff is live on the target (cast-observation + `IsAuraFilteredOutByInstanceID` bridge; secret-safe) | `OnCastSucceeded()`, `OnTargetAuraUpdate()`, `IsDotActiveOnCurrentTarget()` | v1 |
| `MaintenanceTracker.lua` | Sustain/maintenance slot: tracked buff+bar viewer bridge, cosmetic CDM hides | `ApplyViewerVisibility()`, `Reset()`, `GetBridgeDiag()` | v8 |
| `SpellQueue.lua` | Throttled spell queue, proc detection | `GetCurrentSpellQueue()`, blacklist | v43 |
| **UI/** | **UI rendering subsystem (8 files)** | | |
| `UI/UIHealthBar.lua` | Health bar widget | `Create()`, `Update()` | v9 |
| `UI/UIAnimations.lua` | Animation helpers (glow, flash, channel fill) | `StartAssistedGlow()`, `ShowProcGlow()`, `StartFlash()` | v18 |
| `UI/CastInterruptTracker.lua` | Interrupt debounce, cast bar discovery, LSM sound registration | `EvaluateInterrupt()`, `PlayInterruptAlertSound()`, `NotifyCCApplied()` | v2 |
| `UI/UIFrameFactory.lua` | Icon/grab-tab frame construction | `CreateSpellIcons()`, `CreateInterruptIcon()` | v25 |
| `UI/UIRenderer.lua` | Icon rendering + Masque integration (shared per-icon render for both surfaces) | `RenderSpellQueue()`, `RenderQueueIcon()`, `RenderInterruptSlot()` | v44 |
| `UI/UINameplateOverlay.lua` | Nameplate overlay rendering | `Create()`, `Destroy()`, `Update()` | v14 |
| `UI/UISootheCue.lua` | Soothe (enrage-cleanse) cue; rides the interrupt slot | `Create()`, `SetSpell()`, `Show()`, `Available()` | v8 |
| `UI/UIPrecombatOverlay.lua` | OOC click overlay for the defensive queue (pooled click layers) | `Init()`, `Refresh()`, `OverlayClickLayers()` | v3 |
| `DefensiveEngine.lua` | Defensive spell evaluation | `EvaluateDefensives()` | v4 |
| `GapCloserEngine.lua` | Gap-closer spell suggestions (offensive queue) | `GetGapCloserSpell()`, `IsGapCloserSpell()`, `InvalidateGapCloserCache()` | v6 |
| `PrecombatEngine.lua` | Out-of-combat buff checklist (flask/food/rune/imbue) | `IsCategorySatisfied()`, maintained-buff offers | v8 |
| `DebugCommands.lua` | In-game diagnostics | `/jac inspect <topic>`, `/jac find` | v37 |
| `DebugHUD.lua` | Movable live overlay of the signals feeding the queue | `Toggle()` | v1 |
| **Options/** | **Modular options panel (14 files)** | | |
| `Options/Widgets.lua` | Shared AceConfig entry builders (`JustAC-OptionsWidgets`) | `W.toggle()`, `W.select()`, `W.range()`, `W.resetButton()` | v1 |
| `Options/SpellSearch.lua` | Shared spell search, filter state, spell list utils | `BuildSpellbookCache()`, `AddSpellToList()`, `RebuildListSection()` | v3 |
| `Options/LiveSearchPopup.lua` | Persistent modal for spell/item selection | `Open()`, `Close()`, `IsOpen()` | v1 |
| `Options/General.lua` | General tab (display mode, layout, visibility) | `CreateTabArgs()` | v8 |
| `Options/StandardQueue.lua` | Standard Queue tab (icon size, spacing, layout) | `CreateTabArgs()` | v4 |
| `Options/Offensive.lua` | Offensive tab + blacklist + burst-trigger overrides | `CreateTabArgs()`, `UpdateBlacklistOptions()`, `UpdateBurstTriggerOptions()` | v3 |
| `Options/CustomQueue.lua` | Custom Queue tab (manual spell list override) | `CreateTabArgs()` | v1 |
| `Options/Overlay.lua` | Nameplate Overlay tab | `CreateTabArgs()` | v3 |
| `Options/Defensives.lua` | Defensives tab + spell list management | `CreateTabArgs()`, `UpdateDefensivesOptions()` | v4 |
| `Options/GapClosers.lua` | Gap Closers tab (sub-tab of Offensive) | `CreateTabArgs()`, `UpdateGapCloserOptions()` | v1 |
| `Options/Labels.lua` | Icon Labels tab (text overlays) | `CreateTabArgs()` | v4 |
| `Options/Hotkeys.lua` | Hotkey Overrides tab | `CreateTabArgs()`, `UpdateHotkeyOverrideOptions()` | v1 |
| `Options/Profiles.lua` | Per-spec profile switching (injected into profiles) | `AddSpecProfileOptions()` | v1 |
| `Options/Core.lua` | Options assembly, slash commands, initialization | `Initialize()`, `UpdateX()` forwards | v32 |
| `TargetFrameAnchor.lua` | Anchor main frame to Blizzard TargetFrame | `UpdateTargetFrameAnchor()`, `ClampFrameToScreen()` | v1 |
| `KeyPressDetector.lua` | Flash feedback on matching key press | `Create()` | v2 |
| `JustAC.lua` | Core addon, events, defensive cooldowns | `OnInitialize()`, `OnUpdate()` | N/A (main addon) |

## Required Patterns

### Module Access (ALWAYS use this pattern)
```lua
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
if not BlizzardAPI then return end

local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
if not addon or not addon.db then return end
```

### Hot Path Optimization (top of each file)
```lua
local GetTime = GetTime
local pcall = pcall
local wipe = wipe
```

### Critical API Gotcha - MUST filter "assistedcombat" string
```lua
-- GetActionInfo(slot) may return "assistedcombat" as ID - causes crashes if not filtered
-- BlizzardAPI.GetActionInfo() handles this automatically
if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then return nil end
```

## Code Standards

- **4 spaces** indentation, **camelCase** variables, **UPPER_SNAKE** constants
- **Early returns** over nesting (max 3 levels)
- **pcall()** all WoW APIs that can fail
- **All variables local** except `JustAC` global table
- **Increment LibStub version** on breaking changes: `LibStub:NewLibrary("JustAC-Module", VERSION)`
- **Never use em dashes (`—`) anywhere**: not in code, comments, locale strings, README, CHANGELOG, `UNRELEASED.md`, or any project file. Use a hyphen, colon, comma, or separate sentence instead.

## Cache Patterns

| Pattern | Usage | Example |
|---------|-------|---------|
| Throttled | `if now - lastUpdate < interval then return cached` | SpellQueue (0.1s combat) |
| State hash | `hash = page + bonusOffset*100 + form*10000` | ActionBarScanner |
| Event-driven | Clear on `ACTIONBAR_SLOT_CHANGED` | ActionBarScanner |
| Time-based | `if now - lastFlush > 30 then wipe(cache)` | MacroParser |

## Event→Cache Invalidation Map

| Event | Invalidates |
|-------|-------------|
| `UPDATE_SHAPESHIFT_FORM` | MacroParser, ActionBarScanner, FormCache |
| `ACTIONBAR_SLOT_CHANGED` | ActionBarScanner slot cache |
| `UPDATE_BINDINGS` | Binding cache (0.2s debounce) |
| `SPELL_ACTIVATION_OVERLAY_GLOW_*` | Immediate UI refresh |
| `UNIT_AURA(unit, updateInfo)` | RedundancyFilter instance maps (addedAuras/removedAuraInstanceIDs) |
| `UNIT_SPELLCAST_SUCCEEDED` | RedundancyFilter pending activation queue |
| `PLAYER_REGEN_ENABLED` | RedundancyFilter combat state (inCombatActivations, combatRemovedSpellIDs, pendingActivations) |

## Debug Commands

```
/jac help                     - EVERY inspect topic with its one-liner
/jac find [spell]             - Locate spell on action bars (defaults to AC suggestion)
/jac why <spell>              - Per-stage verdict on why a spell is/isn't in the queue
```

The topic list is **not duplicated here**. `INSPECT_TOPICS` at the top of
`DebugCommands.lua` is the single source for the slash dispatch, the usage line and
the `/jac help` listing; a copy in this file would be a fourth list to keep in sync,
and every previous copy had already drifted. Add a probe by adding one row there.

**When a feature stops working, start with these three**, in order - they separate
"the client changed" from "the addon broke":

| Command | Answers |
|---|---|
| `/jac inspect validate` | Did a secrecy predicate flip, or did one of the techniques the addon rides on (threshold curves, the zero-gate, duration evaluation, stack counts) stop producing its known-correct answer? `arm` diffs across a combat enter/exit. |
| `/jac inspect errors` | Did we start getting taint or secret-value errors? Run it after a fight. |
| `/jac inspect secrecy` | Which values actually read plain vs secret right now, in and out of combat. |

Then reach for the probe covering the specific subsystem (`/jac help` lists them).

## Reading in-game results from disk

Probe output does NOT have to be copied out of the chat frame. Two channels exist; prefer them,
they remove a whole round trip per question.

**SavedVariables (structured, preferred).** `## SavedVariables: JustACDB JustACGlobal`, written to:

```
WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua
```

(`.bak` alongside it is the previous session.) Anything parked on `JustACGlobal` is readable
directly off disk. **It only flushes on `/reload` or logout** - so the loop is
*play → `/reload` → read the file*, never live tailing. Ask for the `/reload`; without it the
file still holds the previous session and you will analyse stale data and not notice.

**Chat log (raw, opt-in).** `/chatlog` writes `Logs/WoWChatLog.txt` under the WoW root. Absent
unless the user enabled it - check before assuming, and prefer SavedVariables anyway since chat
output is truncated, interleaved with game spam, and unstructured.

**Why this matters for hard bugs.** A pasted snapshot shows one moment. Intermittent faults -
a tracker stuck in a wrong state for minutes, a bind that never retries, a state that a
`/reload` silently clears - are only diagnosable from a time series. For those, have the probe
append to a debug-only ring buffer on `JustACGlobal` (bounded, e.g. 300 entries, gated behind
`/jac debug` so it never runs for normal players or bloats the file), then read the sequence.
Prefer that over asking the user to catch the moment by hand.

Debug commands and this tooling are dev-facing: they never appear in `UNRELEASED.md` /
`CHANGELOG.md` (see Versioning).

## Defensive Spell System

Spell lists managed by `DefensiveEngine.lua` using `SpellDB.CLASS_DEFENSIVE_DEFAULTS` (via `SPELL_LIST_CONFIG`).
Also manages `CLASS_PETHEAL_DEFAULTS` and `CLASS_PET_REZ_DEFAULTS`.

## Data Pipeline (tools/)

Static `Data/*.lua` tables are generated from wago.tools DB2 CSV exports in `Documentation/wow_spell_csv/` (gitignored). Rules:

- **One build per folder.** Generators join across tables and resolve files by glob; a mixed-build folder silently joins across builds.
- **Refresh flow:** `python tools/update_data.py [--product wow|wowt]` pulls the latest build for every tracked table, prints a per-table row diff, swaps the folder atomically, reruns all generators, and shows `git diff --stat Data/`. It is rate-limited - be gentle with wago.tools; never script tight request loops against it.
- **One generator per Data file** (`tools/gen_*.py`, plus `gen_archetypes.sh`). Arg-free default reads `Documentation/wow_spell_csv`.
- **Audits are report-only** (`tools/audit_*.py|sh`): candidate diffs vs curated lists (`audit_topoff_heals.py`, `audit_cooldownset.py` for the client's own per-spec cooldown lists). Human judgment decides what enters curated files.
- Curated files (`SpellCategories`, `InterruptAbilities`, `RangeReferences`) have no generator - edit by hand, re-run audits per patch.

**Data file → source map** (which generator owns which table - skip the grep):

| `Data/*.lua` | Source | Holds |
|--------------|--------|-------|
| `SpellCategories.lua` | curated (hand) | Category tags (defensive/interrupt/etc.) per spell |
| `InterruptAbilities.lua` | curated (hand) | Interrupt/CC spell reference |
| `RangeReferences.lua` | curated (hand) | Per-class range-check spell IDs |
| `SpellArchetypes.lua` | `gen_archetypes.sh` | Role/archetype classification |
| `AuraStacks.lua` | `gen_aura_stacks.py` | Max-stack counts (secret-charge fallback) |
| `SelfAuras.lua` | `gen_self_auras.py` | Player buff/form IDs for RedundancyFilter |
| `TargetDots.lua` | `gen_target_dots.py` | Maintained enemy DoT IDs for DotTracker |
| `HealingItems.lua` | `gen_healing_items.py` | Usable heal/potion items |
| `PrecombatBuffs.lua` | `gen_precombat_buffs.py` | Flask/food/rune/imbue + Well Fed families |
| `SpellCooldowns.lua` | `gen_spell_cooldowns.py` | Per-spec cooldown-set reference |
| `SimcRotations.lua` | `gen_simc_rotations.py` | SimC-derived priority tails (35 specs) + per-spec `burst` anchor lists (mined from potion/trinket/PI sync conditions; feed the burst-ready cue). Pinned source APLs in `tools/simc-apl/`; refresh via `tools/update_simc_apl.py` (syncs from the `00-SOURCE/simc` sparse mirror, branch `midnight`, then regenerates) - standard pre-release step |
| *(not shipped)* | `gen_aura_durations.py` | Retained only - durations are secret in combat, superseded by the readiness probe |

## 12.0 Compatibility & Secret Values

**Safe APIs:** `C_AssistedCombat.*`, `GetBindingKey()`, `C_Spell.GetSpellInfo()`, `C_Spell.IsSpellInRange()`, `C_Spell.IsExternalDefensive()`

**`isOnGCD`** (the most-used signal) is a three-state NeverSecret bool on `C_Spell.GetSpellCooldown()`: `true`=on GCD only (spell ready), `false`=real CD running (only Blizzard-flagged spells like Judgment/BoJ/Wake), `nil`=ambiguous in combat (off-CD OR unflagged-on-CD - indistinguishable; fall back to local CD tracking + action-bar usability). See `BlizzardAPI.IsSpellReady()` for the full fallback chain.

**Full combat-safe signal matrix** - every verified NeverSecret/SECRET API (units, spells, auras, action bars, cooldown events, classification APIs, C_Secrets pre-flight guards, LossOfControl, LuaDurationObject) with verification dates lives in `Documentation/12.0_COMPATIBILITY.md` → "Combat-Safe Signal Reference". Consult it before assuming any combat API is readable. Do not duplicate the matrix here - update the doc instead. (C_Secrets function list: `Documentation/MIDNIGHT_POST_LAUNCH_RESEARCH.md`.) Re-verify the whole matrix in-game anytime with `/jac inspect validate arm`.

**Live secrecy gates (validated 2026-07-05, all contexts):** the `C_Secrets.Should*BeSecret` predicates flip exactly at combat edges, both directions. Use `BlizzardAPI.AreCooldownsSecret()` / `BlizzardAPI.AreAurasSecret()` as the "is this data readable" signal - never `InCombatLockdown()` as a secrecy proxy. Per-spell secrecy overrides the globals: `C_Secrets.GetSpellAuraSecrecy(id) == 0` means that aura stays readable even mid-combat (RedundancyFilter's `IsNeverSecretAura` caches this; forced evaluation via its `ForceReadNumber`/`ForceReadString` reads exempt fields past the generic secret mark).

**Secret Values (WoW 12.0+):** Blizzard hides certain combat data to prevent automation.
A secret value cannot be compared, used in arithmetic, or branched on - it can only be
handed back to the engine (`FontString:SetText`, `Cooldown:SetCooldownFromDurationObject`,
`SetAlphaFromBoolean`, `SetVertexColorFromBoolean`). Detect with `BlizzardAPI.IsSecretValue(value)`.

Per the rule above, the limitation list, the per-API secrecy table, and the worked patterns
(cooldown readiness via `isOnGCD` + local tracking, aura identity via `auraInstanceID`) are
NOT repeated here - they live in `Documentation/12.0_COMPATIBILITY.md`. Update that doc.

## Reference Docs

- `Documentation/STYLE_GUIDE_JUSTAC.md` - Full coding conventions
- `Documentation/ASSISTED_COMBAT_API_DEEP_DIVE.md` - C_AssistedCombat reference
- `Documentation/MACRO_PARSING_DEEP_DIVE.md` - Macro conditional parsing
- `Documentation/12.0_COMPATIBILITY.md` - API compatibility, secret values, implementation status
- `Documentation/AURA_DETECTION_ALTERNATIVES.md` - Alternative aura detection methods for 12.0
- `Documentation/AURA_IDENTITY_12.0.md` - Identifying a SPECIFIC spell's aura in combat: the two
  routes that work, their conditions, and the measured dead ends. Read before proposing any
  "just look up the aura by spell id" solution
- `Documentation/SECRET_VALUE_READINESS_PROBE.md` - recovering a BOOLEAN from a secret duration
  (is it on cooldown / is the buff up) via the scratch-Cooldown shown-state probe
- `Documentation/SECRET_VALUE_THRESHOLD_GATES.md` - recovering a THRESHOLD from a secret value
  (is it below N% / under N seconds) via the zero-gate + threshold curves. Covers health, power,
  aura and cooldown durations, and aura stacks. **Read before adding any new threshold, and read
  its SCOPE RULE before proposing anything that reconstructs a hidden number**
- `Documentation/VERSION_CONDITIONALS.md` - Version-conditional patterns for 12.0 compatibility
- `README.md` - User-facing docs, installation, credits
- `CHANGELOG.md` - Release history (GPL-3.0-or-later since v2.95)

## Build & Release

**Local build** - `build.ps1` creates `dist/JustAC-<version>.zip` for local testing.

**CI/CD** - GitHub Actions (`.github/workflows/release.yml`) auto-deploys to CurseForge via BigWigs Packager.
- Triggered by git tag push (`v*` pattern)
- Packages per `.pkgmeta`, creates GitHub Release, uploads to CurseForge (project ID: 1289544)
- Requires `CF_API_KEY` secret in GitHub repo settings

**Workflow:**
1. Make changes and commit them
2. Update `UNRELEASED.md` with change notes
3. `git push` to keep remote in sync (does NOT trigger CurseForge deploy)
4. When user requests version bump:
   - Move UNRELEASED changes to CHANGELOG.md
   - Increment version in JustAC.toc
   - Update library versions if breaking changes
   - Update README.md if new features, removed features, or significant behavior changes
   - Verify `build.ps1` lists all current source files (new files must be added)
   - Clear UNRELEASED.md
   - Commit version bump
5. User runs `.\build.ps1` when ready to test locally
6. When user explicitly requests deploy/release to CurseForge:
   - `git tag v<version>`, then `git push` and `git push origin v<version>`
   - Push the tag by name. `--follow-tags` pushes annotated tags only and silently
     skips these (they're lightweight), so the branch push succeeds while the tag
     stays local and CI never fires. Verify the tag landed: `git ls-remote --tags origin`
   - This triggers CI → CurseForge upload

**DO NOT auto-tag or auto-deploy to CurseForge** - Only tag and push tags when the user explicitly requests a release/deploy.

**Before release:** Test with `/jac inspect modules` + in-game rotation to verify all modules loaded.
