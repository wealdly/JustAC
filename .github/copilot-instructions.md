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

1. **NEVER guess WoW API behavior** — Verify with `/script` commands in-game or check `R:\WOW\00-SOURCE\WowUISource`
2. **Propose before implementing** — Describe changes, ask "Should I proceed?"
3. **Test with debug commands** — Use `/jac test`, `/jac modules`, `/jac formcheck` to validate changes
4. **DO NOT auto-increment versions** — Track changes in `UNRELEASED.md`, only bump version on explicit instruction
5. **DO NOT auto-build or push** — Commit changes, let user build/push manually
6. **NO AI attribution** — Never add `Co-Authored-By`, credits, acknowledgments, or any other reference to AI agents/models in commit messages, code comments, README, CHANGELOG, or any project file. All contributions are authored solely by the project owner.

## Versioning

**Semantic Versioning (MAJOR.MINOR.PATCH):**
- Current: 4.12.0
- Hotfixes: 4.5.5, 4.5.6, etc. (bug fixes only)
- Features: 4.6.0, 4.7.0, etc. (new functionality)
- Breaking: 5.0.0, 6.0.0, etc. (major rewrites)

Update in three places: `JustAC.toc`, `CHANGELOG.md`, `UNRELEASED.md`

## Architecture (Load Order Matters)

LibStub modules in `JustAC.toc` — **MUST edit in dependency order**:

```
BlizzardAPI → FormCache → MacroParser → ActionBarScanner → RedundancyFilter
                                    ↓
              SpellQueue → UI/* → DefensiveEngine → GapCloserEngine → DebugCommands → Options/SpellSearch → Options/LiveSearchPopup → Options/* → TargetFrameAnchor → KeyPressDetector → JustAC
```

| Module | Role | Key Exports | Current Version |
|--------|------|-------------|-----------------|
| `Locales/*.lua` | AceLocale-3.0 localization (9 languages) | `L` global | N/A (not LibStub) |
| `SpellDB.lua` | Static spell data (defensive, class defaults) | `GetDefaults()`, `GetSpecKey()` | v8 |
| `BlizzardAPI.lua` | Root: secret value primitives, version detection | `IsSecretValue()`, `Unsecret()`, `GetActionBarUsability()` | v33 |
| `BlizzardAPI/CooldownTracking.lua` | Local CD tracking (12.0+ secret workaround) | `IsSpellReady()`, `RegisterSpellForTracking()`, `IsSpellOnLocalCooldown()` | v6 |
| `BlizzardAPI/SecretValues.lua` | Feature availability gates, aura timing | `IsRedundancyFilterAvailable()`, `IsMidnightOrLater()` | v1 |
| `BlizzardAPI/SpellQuery.lua` | Spell info, usability, rotation API, items | `GetProfile()`, `GetSpellInfo()`, `IsSpellUsable()` | v1 |
| `BlizzardAPI/StateHelpers.lua` | Defensive/item state, health, CC immunity, target analysis | `CheckDefensiveItemState()`, `GetPlayerHealthPercent()`, `IsTargetCCImmune()` | v5 |
| `FormCache.lua` | Shapeshift form state (Druid/Rogue/etc) | `GetActiveForm()`, `GetFormIDBySpellID()` | v11 |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` conditional parsing | `GetMacroSpellInfo()`, quality scoring | v21 |
| `ActionBarScanner.lua` | Spell→keybind lookup, slot caching | `GetSpellHotkey()`, `GetSlotForSpell()` | v35 |
| `RedundancyFilter.lua` | Hide active buffs/forms | `IsSpellRedundant()` | v41 |
| `SpellQueue.lua` | Throttled spell queue, proc detection | `GetCurrentSpellQueue()`, blacklist | v37 |
| **UI/** | **UI rendering subsystem (5 files)** | | |
| `UI/UIHealthBar.lua` | Health bar widget | `Create()`, `Update()` | v7 |
| `UI/UIAnimations.lua` | Animation helpers (glow, flash, channel fill) | `StartAssistedGlow()`, `ShowProcGlow()`, `StartFlash()` | v11 |
| `UI/UIFrameFactory.lua` | Icon frame pool | `AcquireFrame()`, `ReleaseFrame()` | v12 |
| `UI/UIRenderer.lua` | Icon rendering + Masque integration | `RenderSpellQueue()`, frame management | v17 |
| `UI/UINameplateOverlay.lua` | Nameplate overlay rendering | `Create()`, `Destroy()`, `Update()` | v6 |
| `DefensiveEngine.lua` | Defensive spell evaluation | `EvaluateDefensives()` | v1 |
| `GapCloserEngine.lua` | Gap-closer spell suggestions (offensive queue) | `GetGapCloserSpell()`, `IsGapCloserSpell()`, `InvalidateGapCloserCache()` | v3 |
| `DebugCommands.lua` | In-game diagnostics | `/jac test`, `/jac modules` | v15 |
| **Options/** | **Modular options panel (11 files)** | | |
| `Options/SpellSearch.lua` | Shared spell search, filter state, spell list utils | `BuildSpellbookCache()`, `AddSpellToList()` | v1 |
| `Options/LiveSearchPopup.lua` | Persistent modal for spell/item selection | `Open()`, `Close()`, `IsOpen()` | v1 |
| `Options/General.lua` | General tab (display mode, layout, visibility) | `CreateTabArgs()` | v4 |
| `Options/StandardQueue.lua` | Standard Queue tab (icon size, spacing, layout) | `CreateTabArgs()` | v2 |
| `Options/Offensive.lua` | Offensive tab + blacklist management | `CreateTabArgs()`, `UpdateBlacklistOptions()` | v1 |
| `Options/Overlay.lua` | Nameplate Overlay tab | `CreateTabArgs()` | v2 |
| `Options/Defensives.lua` | Defensives tab + spell list management | `CreateTabArgs()`, `UpdateDefensivesOptions()` | v1 |
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

### Critical API Gotcha — MUST filter "assistedcombat" string
```lua
-- GetActionInfo(slot) may return "assistedcombat" as ID — causes crashes if not filtered
-- BlizzardAPI.GetActionInfo() handles this automatically
if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then return nil end
```

## Code Standards

- **4 spaces** indentation, **camelCase** variables, **UPPER_SNAKE** constants
- **Early returns** over nesting (max 3 levels)
- **pcall()** all WoW APIs that can fail
- **All variables local** except `JustAC` global table
- **Increment LibStub version** on breaking changes: `LibStub:NewLibrary("JustAC-Module", VERSION)`

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
/jac test       — API diagnostics
/jac modules    — Module health check  
/jac formcheck  — Form detection debug
/jac find Name  — Locate spell on action bars
```

## Defensive Spell System

Two-tier health thresholds in `JustAC.lua`:
- `CLASS_SELFHEAL_DEFAULTS` — 80% threshold, quick heals
- `CLASS_COOLDOWN_DEFAULTS` — 60% threshold, major defensives

## 12.0 Compatibility & Secret Values

**Safe APIs:** `C_AssistedCombat.*`, `GetBindingKey()`, `C_Spell.GetSpellInfo()`, `C_Spell.IsSpellInRange()`, `C_Spell.IsExternalDefensive()`

**NeverSecret Fields (critical for combat-safe logic):**
- `isOnGCD` — Three-state NeverSecret (verified 2026-02-25): `true`=GCD only (spell ready), `false`=real cooldown running (only for Blizzard-flagged spells like Judgment, Blade of Justice, Wake of Ashes), `nil`/absent=ambiguous (off CD OR unflagged spell on CD — indistinguishable). Major CDs (Divine Toll, Shadow Blades) never show `false`. Use `isOnGCD == false` for definitive CD detection; fall back to local cooldown tracking + action bar usability when `nil`. Flagged spells go `nil→false` immediately at cast (no transient `true` state). State machine: `nil`→`false` (cast) → `false`→`nil` (CD expires). Unflagged: `nil`→`true` (GCD) → `true`→`nil` (GCD ends).
- `timeUntilEndOfStartRecovery` — SECRET in combat. Counts down GCD remaining (unflagged spells) or total CD remaining (flagged spells). Display-only via UI pipeline. Note: despite the name suggesting "GCD recovery", it tracks total CD remaining for flagged spells (e.g. 28.2s of 30s Wake CD).
- `auraInstanceID` — Stable numeric handle, same ID maps to same aura across combat. Use for tracking aura identity when `spellId`/`name` are secret.
- `isHelpful` / `isHarmful` — Aura disposition (may be secret in some contexts, fail-open)

**NeverSecret Spell APIs (verified 2026-02-25):**
- `C_Spell.IsSpellUsable(id)` — Real `bool, bool` in combat (usable + noMana). Verified NeverSecret on Ret Paladin.
- `C_Spell.GetSpellPowerCost(id)` — ALL fields NeverSecret: `type`, `cost`, `minCost`, `costPercentOfMax`. Cacheable at registration. Use with IsUsableAction to distinguish CD vs resource issues.
- `C_Spell.IsCurrentSpell(id)` — Real `bool` in combat. Active cast/channel detection at spell level.
- `C_Spell.GetSpellInfo(id)` — `name`, `iconID` NeverSecret in combat. Display pipeline safe.
- `C_Spell.GetSpellCharges(id)` — **ALL fields SECRET** (including maxCharges). Cache maxCharges out of combat.

**NeverSecret Power APIs (verified 2026-02-25):**
- `UnitPowerType("player")` — NeverSecret. Returns primary power type enum (0=Mana, 1=Rage, 3=Energy, etc.).
- `UnitPowerMax("player"[, type])` — NeverSecret for ALL power types. Cacheable at combat exit.
- `UnitPower("player", type)` — **Per-type secrecy:** Continuous resources (Mana=0, Rage=1, Energy=3, Focus=2, Runic Power=6) are SECRET. Discrete secondary resources (Combo Points=4, Holy Power=9, Soul Shards=7, Chi=12, Arcane Charges=16) are **NeverSecret**.
- `GetComboPoints("player","target")` — **NeverSecret** (verified on Rogue). Equivalent to `UnitPower("player", 4)`.

**Secret in combat (verified 2026-02-25):**
- `UnitHealth("player")` — SECRET even in open world combat
- `UnitPower("player")` — SECRET (default=primary resource: energy, mana, rage, focus)
- Target health/power — `UnitHealth/UnitHealthMax/UnitPower/UnitPowerMax("target")` — ALL SECRET

**Always secret (verified 2026-03-07):**
- `UnitHealthPercent(unit)` — SECRET even OUT OF COMBAT. Unusable for any logic. Do NOT use.
- `UnitHealthMissing(unit)` — SECRET (verified 2026-03-07). Same as UnitHealthPercent.
- `UnitPowerPercent(unit)` — SECRET (verified 2026-03-07). Do NOT use.
- `UnitPowerMissing(unit)` — SECRET (verified 2026-03-07). Do NOT use.

**NeverSecret Target APIs (verified 2026-02-24):**
- `UnitClassification("target")` — `"normal"`, `"elite"`, `"worldboss"`, `"rare"`, `"rareelite"`, `"minus"`
- `UnitIsUnit("target", "boss1-5")` — Boss slot detection
- `UnitIsPlayer("target")` — Player vs NPC (confirmed `issecretvalue()=false`)
- `UnitIsMinion("target")` — Pets, totems, treants (combat-safe creature-type replacement)
- `UnitThreatSituation("player", "target")` — 0-3 threat state
- `UnitIsCrowdControlled("target")` — Target already CC'd
- `nameplate.UnitFrame.isPlayer` / `.isFriend` — Cached table fields, bypass secret system

**NeverSecret Action Bar APIs (verified 2026-02-25):**
- `C_ActionBar.IsActionInRange(slot, "target")` — Real `bool` in combat. Range check per action slot.
- `C_ActionBar.IsInterruptAction(slot)` — Real `bool` in combat. Identifies interrupt spell slots.
- `C_ActionBar.IsUsableAction(slot)` — Real `bool, bool` in combat. Usable + noMana.
- `C_ActionBar.IsAttackAction(slot)` — Real `bool` in combat. Auto-attack slot detection.
- `C_ActionBar.IsCurrentAction(slot)` — Real `bool` in combat. Active cast/channel/toggle only (NOT melee swing).
- `ACTION_RANGE_CHECK_UPDATE` event — Push-based per-slot range (`isInRange`, `checksRange`). Requires `EnableActionRangeCheck(slot, true)`.
- `ACTION_USABLE_CHANGED` event — Batched `ActionUsableState[]` with per-slot `usable`/`noMana` bools.
- `C_Spell.IsExternalDefensive(spellID)` — Real `bool`. Static classification, always works.
- `C_DamageMeter.GetSessionDurationSeconds(type)` — Real combat timer (seconds). No SecretWhen.

**NeverSecret Cooldown Events (verified 2026-02-25):**
- `SPELL_UPDATE_COOLDOWN` event — **spellID payload is NeverSecret in combat.** Returns `spellID`, `baseSpellID`, `category`, `startRecoveryCategory`. `startRecoveryCategory=133` = GCD. Fires per-spell on CD state change (~10× per cast due to GCD cascade). `spellID=nil` = batch "refresh all". Duplicate events per spell (base + override).
- `ACTIONBAR_UPDATE_COOLDOWN` event — **Fires every frame (~15-18Hz).** No payload. Useless as discrete signal. Do NOT use for event-driven logic.
- `SPELL_UPDATE_USABLE` event — No payload. Fires on usability transitions (CD expire, resource change).

**NeverSecret Spell Classification APIs (verified 2026-02-25):**
- `C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)` — Returns cooldownIDs per category (0=Essential, 1=Utility, 2=TrackedBuff, 3=TrackedBar). Non-secret in combat.
- `C_CooldownViewer.GetCooldownViewerCooldownInfo(id)` — Returns static metadata (spellID, isKnown, category, flags). `hasAura` is static config flag, NOT live state.

**NeverSecret LossOfControl fields (from source, untested in-game):**
- `locType` — CC type string ("STUN", "SILENCE", "ROOT", "FEAR", etc.)
- `priority` — CC priority ranking
- `displayType` — Visual type enum
- `auraInstanceID` — Links to aura instance map

**See:** `Documentation/12.0_COMPATIBILITY.md` → "Combat-Safe Signal Reference" for full matrix

**C_Secrets Pre-Flight Guards (verified 2026-03-07):**
Fast boolean checks — avoid per-value `issecretvalue()` overhead:
- `C_Secrets.HasSecretRestrictions()` — `true` in combat, `false` out of combat
- `C_Secrets.ShouldAurasBeSecret()` — `true` in combat. Fast early-exit for aura scans.
- `C_Secrets.ShouldCooldownsBeSecret()` — `true` in combat. Blanket, no args.
- `C_Secrets.ShouldSpellCooldownBeSecret(spellID)` — per-spell, requires spellID arg
- `C_Secrets.ShouldUnitHealthMaxBeSecret(unit)` — `false` in combat (UnitHealthMax is NeverSecret)
- `C_Secrets.ShouldUnitPowerBeSecret(unit[, powerType])` — no-arg=`true` (conservative); per-type is granular (Holy Power=`false`)
- `C_Secrets.ShouldUnitThreatStateBeSecret(unit)` — `false` in combat (NeverSecret)
- `C_RestrictedActions.IsAddOnRestrictionActive()` — addon restriction state
- See `Documentation/MIDNIGHT_POST_LAUNCH_RESEARCH.md` for full function list (25+ functions)

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

- `Documentation/STYLE_GUIDE_JUSTAC.md` — Full coding conventions (843 lines)
- `Documentation/ASSISTED_COMBAT_API_DEEP_DIVE.md` — C_AssistedCombat reference (717 lines)
- `Documentation/MACRO_PARSING_DEEP_DIVE.md` — Macro conditional parsing (904 lines)
- `Documentation/12.0_COMPATIBILITY.md` — API compatibility, secret values, implementation status
- `Documentation/AURA_DETECTION_ALTERNATIVES.md` — Alternative aura detection methods for 12.0
- `Documentation/VERSION_CONDITIONALS.md` — Version-conditional patterns for 12.0 compatibility
- `README.md` — User-facing docs, installation, credits
- `CHANGELOG.md` — Release history (GPL-3.0-or-later since v2.95)

## Build & Release

**Local build** — `build.ps1` creates `dist/JustAC-<version>.zip` for local testing.

**CI/CD** — GitHub Actions (`.github/workflows/release.yml`) auto-deploys to CurseForge via BigWigs Packager.
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

**DO NOT auto-tag or auto-deploy to CurseForge** — Only tag and push tags when the user explicitly requests a release/deploy.

**Before release:** Test with `/jac modules` + in-game rotation to verify all modules loaded.
