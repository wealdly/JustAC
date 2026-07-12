# JustAC - AI Agent Instructions

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

1. **NEVER guess WoW API behavior** - Verify with `/script` commands in-game or check the local source mirrors in `<sources>\` (`wow-ui-source\Interface\AddOns` incl. `Blizzard_APIDocumentationGenerated`, and `WowPacketParser\WowPacketParser\Enums`; refresh both with `<sources>\update-sources.ps1`)
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
syntax) and falls back to a **luaparser** syntax check. Baseline is ~47 known
warnings / 0 errors - a clean change adds no errors and no *new* warnings. If no
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
              SpellQueue → UI/* → DefensiveEngine → GapCloserEngine → BurstInjectionEngine → DebugCommands → Options/* → TargetFrameAnchor → KeyPressDetector → JustAC
```

| Module | Role | Key Exports | Current Version |
|--------|------|-------------|-----------------|
| `Locales/*.lua` | AceLocale-3.0 localization (9 languages) | `L` global | N/A (not LibStub) |
| `SpellDB.lua` | Static spell data (defensive, class defaults) | `GetDefaults()`, `GetSpecKey()` | v13 |
| `BlizzardAPI.lua` | Root: secret value primitives, live secrecy gates, version detection | `IsSecretValue()`, `Unsecret()`, `AreCooldownsSecret()`, `AreAurasSecret()`, `GetActionBarUsability()` | v36 |
| `BlizzardAPI/CooldownTracking.lua` | Local CD tracking (12.0+ secret workaround) | `IsSpellReady()`, `RegisterSpellForTracking()`, `IsSpellOnLocalCooldown()` | v13 |
| `BlizzardAPI/SecretValues.lua` | Feature availability gates, aura timing | `IsRedundancyFilterAvailable()`, `GetFeatureAvailability()` | v2 |
| `BlizzardAPI/SpellQuery.lua` | Spell info, usability, rotation API, items | `GetProfile()`, `GetSpellInfo()`, `IsSpellUsable()` | v2 |
| `BlizzardAPI/StateHelpers.lua` | Defensive/item state, health, CC immunity, target analysis | `CheckDefensiveItemState()`, `GetPlayerHealthPercent()`, `IsTargetCCImmune()` | v10 |
| `FormCache.lua` | Shapeshift form state (Druid/Rogue/etc) | `GetActiveForm()`, `GetFormIDBySpellID()` | v11 |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` conditional parsing | `GetMacroSpellInfo()`, quality scoring | v25 |
| `ActionBarScanner.lua` | Spell→keybind lookup, slot caching | `GetSpellHotkey()`, `GetSlotForSpell()` | v38 |
| `RedundancyFilter.lua` | Hide active buffs/forms | `IsSpellRedundant()` | v43 |
| `DotTracker.lua` | Sink maintained enemy DoTs while their debuff is live on the target (cast-observation + `IsAuraFilteredOutByInstanceID` bridge; secret-safe) | `OnCastSucceeded()`, `OnTargetAuraUpdate()`, `IsDotActiveOnCurrentTarget()` | v1 |
| `SpellQueue.lua` | Throttled spell queue, proc detection | `GetCurrentSpellQueue()`, blacklist | v43 |
| **UI/** | **UI rendering subsystem (6 files)** | | |
| `UI/UIHealthBar.lua` | Health bar widget | `Create()`, `Update()` | v9 |
| `UI/UIAnimations.lua` | Animation helpers (glow, flash, channel fill) | `StartAssistedGlow()`, `ShowProcGlow()`, `StartFlash()` | v15 |
| `UI/CastInterruptTracker.lua` | Interrupt debounce, cast bar discovery, LSM sound registration | `EvaluateInterrupt()`, `PlayInterruptAlertSound()`, `NotifyCCApplied()` | v1 |
| `UI/UIFrameFactory.lua` | Icon/grab-tab frame construction | `CreateSpellIcons()`, `CreateInterruptIcon()` | v16 |
| `UI/UIRenderer.lua` | Icon rendering + Masque integration (shared per-icon render for both surfaces) | `RenderSpellQueue()`, `RenderQueueIcon()`, `RenderInterruptSlot()` | v25 |
| `UI/UINameplateOverlay.lua` | Nameplate overlay rendering | `Create()`, `Destroy()`, `Update()` | v11 |
| `DefensiveEngine.lua` | Defensive spell evaluation | `EvaluateDefensives()` | v2 |
| `GapCloserEngine.lua` | Gap-closer spell suggestions (offensive queue) | `GetGapCloserSpell()`, `IsGapCloserSpell()`, `InvalidateGapCloserCache()` | v6 |
| `BurstInjectionEngine.lua` | Two-phase burst injection (trigger → inject priority spells) | `TryActivateBurst()`, `GetBurstStatus()`, `PreCacheRotationCooldowns()` | v5 |
| `PrecombatEngine.lua` | Out-of-combat buff checklist (flask/food/rune/imbue) | `IsCategorySatisfied()`, maintained-buff offers | v3 |
| `DebugCommands.lua` | In-game diagnostics | `/jac inspect <topic>`, `/jac find` | v21 |
| **Options/** | **Modular options panel (13 files)** | | |
| `Options/SpellSearch.lua` | Shared spell search, filter state, spell list utils | `BuildSpellbookCache()`, `AddSpellToList()`, `RebuildListSection()` | v3 |
| `Options/LiveSearchPopup.lua` | Persistent modal for spell/item selection | `Open()`, `Close()`, `IsOpen()` | v1 |
| `Options/General.lua` | General tab (display mode, layout, visibility) | `CreateTabArgs()` | v4 |
| `Options/StandardQueue.lua` | Standard Queue tab (icon size, spacing, layout) | `CreateTabArgs()` | v4 |
| `Options/Offensive.lua` | Offensive tab + blacklist management | `CreateTabArgs()`, `UpdateBlacklistOptions()` | v1 |
| `Options/CustomQueue.lua` | Custom Queue tab (manual spell list override) | `CreateTabArgs()` | v1 |
| `Options/Overlay.lua` | Nameplate Overlay tab | `CreateTabArgs()` | v3 |
| `Options/Defensives.lua` | Defensives tab + spell list management | `CreateTabArgs()`, `UpdateDefensivesOptions()` | v1 |
| `Options/GapClosers.lua` | Gap Closers tab (sub-tab of Offensive) | `CreateTabArgs()`, `UpdateGapCloserOptions()` | v1 |
| `Options/BurstInjection.lua` | Burst Injection tab (trigger + spell list) | `CreateTabArgs()` | v1 |
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
/jac inspect modules          - Module health check
/jac inspect cooldown [spell] - Cooldown API diagnostics (defaults to AC suggestion)
/jac inspect defensives       - Defensive system state
/jac inspect interrupts       - Interrupt/CC queue state
/jac inspect burst            - Burst injection state
/jac inspect auras            - Aura cache state
/jac inspect buffs            - Pre-combat buff checklist state
/jac inspect rank             - Queue context inference / per-spell ordering
/jac inspect dots             - Maintained-DoT tracking state for the current target
/jac inspect perf [reset]     - Queue build rate statistics (requires debug mode)
/jac inspect chargediag [sp]  - Armed 60s charge-event/secrecy probe
/jac inspect castdiag         - Armed one-shot cast-interruptibility probe
/jac inspect healthprobe      - OOC health-detection channel sweep (run while hurt)
/jac inspect validate [arm]   - Validate every secrecy/API assumption; arm = diff on combat enter/exit
/jac find [spell]             - Locate spell on action bars (defaults to AC suggestion)
/jac why <spell>              - Per-stage verdict on why a spell is/isn't in the queue
```

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

## 12.0 Compatibility & Secret Values

**Safe APIs:** `C_AssistedCombat.*`, `GetBindingKey()`, `C_Spell.GetSpellInfo()`, `C_Spell.IsSpellInRange()`, `C_Spell.IsExternalDefensive()`

**`isOnGCD`** (the most-used signal) is a three-state NeverSecret bool on `C_Spell.GetSpellCooldown()`: `true`=on GCD only (spell ready), `false`=real CD running (only Blizzard-flagged spells like Judgment/BoJ/Wake), `nil`=ambiguous in combat (off-CD OR unflagged-on-CD - indistinguishable; fall back to local CD tracking + action-bar usability). See `BlizzardAPI.IsSpellReady()` for the full fallback chain.

**Full combat-safe signal matrix** - every verified NeverSecret/SECRET API (units, spells, auras, action bars, cooldown events, classification APIs, C_Secrets pre-flight guards, LossOfControl, LuaDurationObject) with verification dates lives in `Documentation/12.0_COMPATIBILITY.md` → "Combat-Safe Signal Reference". Consult it before assuming any combat API is readable. Do not duplicate the matrix here - update the doc instead. (C_Secrets function list: `Documentation/MIDNIGHT_POST_LAUNCH_RESEARCH.md`.) Re-verify the whole matrix in-game anytime with `/jac inspect validate arm`.

**Live secrecy gates (validated 2026-07-05, all contexts):** the `C_Secrets.Should*BeSecret` predicates flip exactly at combat edges, both directions. Use `BlizzardAPI.AreCooldownsSecret()` / `BlizzardAPI.AreAurasSecret()` as the "is this data readable" signal - never `InCombatLockdown()` as a secrecy proxy. Per-spell secrecy overrides the globals: `C_Secrets.GetSpellAuraSecrecy(id) == 0` means that aura stays readable even mid-combat (RedundancyFilter's `IsNeverSecretAura` caches this; forced evaluation via its `ForceReadNumber`/`ForceReadString` reads exempt fields past the generic secret mark).

**Secret Values (WoW 12.0+):**
- Blizzard hides certain combat data to prevent automation
- **Detection:** `BlizzardAPI.IsSecretValue(value)` returns `true` for secret data
- **Critical limitations:**
  - ❌ Cannot compare: `if charges > 2` crashes if `charges` is secret
  - ❌ Cannot do arithmetic: `charges + 1` returns secret value (unusable)
  - ❌ Cannot use in conditionals: `if duration > 5` fails if `duration` is secret
  - ✅ Can pass to UI: `FontString:SetText(secretValue)` works (Blizzard handles internally)
  - ✅ Can pass to cooldown: `Cooldown:SetCooldown(start, secretDuration)` works
  - ✅ Can pass LuaDurationObject: `Cooldown:SetCooldownFromDurationObject(dur)` works (12.0 opaque pipeline)
- **Common secret values in combat:**
  - `C_Spell.GetSpellCooldown()` → `duration`/`startTime` (blanket-secreted even when zero)
  - `C_UnitAuras` → `spellId`, `name` (aura identity hidden in combat)
  - `currentCharges` (charge count)
  - `UnitHealth()` (potentially in some instanced content)
- **Fail-open design:** `IsSecretValue()` shows extra content rather than hiding valid data
- **Fallback pattern:** Cache non-secret structure data (e.g., `maxCharges`) for comparison

**Cooldown readiness pattern (isOnGCD + local tracking fallback):**
```lua
local info = C_Spell.GetSpellCooldown(spellID)
if info then
    -- isOnGCD == true → on GCD only, spell is ready
    if info.isOnGCD == true then
        -- Spell is ready (just on GCD)
    elseif info.isOnGCD == false then
        -- Real cooldown running (only for flagged spells: Judgment, BoJ, Wake, etc.)
    elseif issecretvalue(info.duration) then
        -- In combat: isOnGCD is nil for BOTH "off CD" and "unflagged spell on CD"
        -- Must use local cooldown tracking or action bar fallback
        -- See BlizzardAPI.IsSpellReady() for full fallback chain
    else
        -- Out of combat: can compare duration directly
        if info.duration == 0 then -- ready end
    end
end
```

**Aura tracking pattern (use auraInstanceID):**
```lua
-- Build instance map out of combat (spellId is readable)
for i = 1, 40 do
    local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    if data then instanceToSpellMap[data.auraInstanceID] = data.spellId end
end
-- In combat: resolve via map when spellId is secret
if BlizzardAPI.IsSecretValue(data.spellId) then
    local resolved = instanceToSpellMap[data.auraInstanceID]
end
```

## Reference Docs

- `Documentation/STYLE_GUIDE_JUSTAC.md` - Full coding conventions (843 lines)
- `Documentation/ASSISTED_COMBAT_API_DEEP_DIVE.md` - C_AssistedCombat reference (717 lines)
- `Documentation/MACRO_PARSING_DEEP_DIVE.md` - Macro conditional parsing (904 lines)
- `Documentation/12.0_COMPATIBILITY.md` - API compatibility, secret values, implementation status
- `Documentation/AURA_DETECTION_ALTERNATIVES.md` - Alternative aura detection methods for 12.0
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
   - `git tag v<version>` + `git push --tags`
   - This triggers CI → CurseForge upload

**DO NOT auto-tag or auto-deploy to CurseForge** - Only tag and push tags when the user explicitly requests a release/deploy.

**Before release:** Test with `/jac inspect modules` + in-game rotation to verify all modules loaded.
