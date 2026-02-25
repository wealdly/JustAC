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

## Versioning

**Semantic Versioning (MAJOR.MINOR.PATCH):**
- Current: 4.2.2
- Hotfixes: 4.1.2, 4.1.3, etc. (bug fixes only)
- Features: 4.2.0, 4.3.0, etc. (new functionality)
- Breaking: 5.0.0, 6.0.0, etc. (major rewrites)

Update in three places: `JustAC.toc`, `CHANGELOG.md`, `UNRELEASED.md`

## Architecture (Load Order Matters)

LibStub modules in `JustAC.toc` — **MUST edit in dependency order**:

```
BlizzardAPI → FormCache → MacroParser → ActionBarScanner → RedundancyFilter
                                    ↓
              SpellQueue → UI/* → DefensiveEngine → DebugCommands → Options/* → TargetFrameAnchor → KeyPressDetector → JustAC
```

| Module | Role | Key Exports | Current Version |
|--------|------|-------------|-----------------|
| `Locale.lua` | AceLocale-3.0 localization (6 languages) | `L` global | N/A (not LibStub) |
| `BlizzardAPI.lua` | `C_AssistedCombat` wrappers, profile access | `GetProfile()`, `GetSpellInfo()` | v21 |
| `FormCache.lua` | Shapeshift form state (Druid/Rogue/etc) | `GetActiveForm()`, `GetFormIDBySpellID()` | v5 |
| `MacroParser.lua` | `[mod]`, `[form]`, `[spec]` conditional parsing | `GetMacroSpellInfo()`, quality scoring | v19 |
| `ActionBarScanner.lua` | Spell→keybind lookup, slot caching | `GetSpellHotkey()`, `GetSlotForSpell()` | v32 |
| `RedundancyFilter.lua` | Hide active buffs/forms | `IsSpellRedundant()` | N/A |
| `SpellQueue.lua` | Throttled spell queue, proc detection | `GetCurrentSpellQueue()`, blacklist | v24 |
| `SpellDB.lua` | Static spell data (defensive, class defaults) | `GetDefaults()` | N/A |
| **UI/** | **UI rendering subsystem (5 files)** | | |
| `UI/UIHealthBar.lua` | Health bar widget | `Create()`, `Update()` | v5 |
| `UI/UIAnimations.lua` | Animation helpers (glow, flash) | `ApplyGlow()`, `ApplyFlash()` | v4 |
| `UI/UIFrameFactory.lua` | Icon frame pool | `AcquireFrame()`, `ReleaseFrame()` | v12 |
| `UI/UIRenderer.lua` | Icon rendering + Masque integration | `RenderSpellQueue()`, frame management | v14 |
| `UI/UINameplateOverlay.lua` | Nameplate overlay rendering | `Create()`, `Destroy()`, `Update()` | v1 |
| `DefensiveEngine.lua` | Defensive spell evaluation | `EvaluateDefensives()` | v1 |
| `DebugCommands.lua` | In-game diagnostics | `/jac test`, `/jac modules` | v1 |
| **Options/** | **Modular options panel (9 files)** | | |
| `Options/SpellSearch.lua` | Shared spell search, filter state, spell list utils | `BuildSpellbookCache()`, `AddSpellToList()` | v1 |
| `Options/General.lua` | General tab (display mode, layout, visibility) | `CreateTabArgs()` | v1 |
| `Options/Offensive.lua` | Offensive tab + blacklist management | `CreateTabArgs()`, `UpdateBlacklistOptions()` | v1 |
| `Options/Overlay.lua` | Nameplate Overlay tab | `CreateTabArgs()` | v1 |
| `Options/Defensives.lua` | Defensives tab + spell list management | `CreateTabArgs()`, `UpdateDefensivesOptions()` | v1 |
| `Options/Labels.lua` | Icon Labels tab (text overlays) | `CreateTabArgs()` | v1 |
| `Options/Hotkeys.lua` | Hotkey Overrides tab | `CreateTabArgs()`, `UpdateHotkeyOverrideOptions()` | v1 |
| `Options/Profiles.lua` | Per-spec profile switching (injected into profiles) | `AddSpecProfileOptions()` | v1 |
| `Options/Core.lua` | Options assembly, slash commands, initialization | `Initialize()`, `UpdateX()` forwards | v31 |
| `TargetFrameAnchor.lua` | Anchor main frame to Blizzard TargetFrame | `UpdateTargetFrameAnchor()`, `ClampFrameToScreen()` | v1 |
| `KeyPressDetector.lua` | Flash feedback on matching key press | `Create()` | v1 |
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

**Safe APIs:** `C_AssistedCombat.*`, `GetBindingKey()`, `C_Spell.GetSpellInfo()`

**NeverSecret Fields (critical for combat-safe logic):**
- `isOnGCD` — Three-state: `true`=GCD only (spell ready), `false`=real cooldown, `nil`=no cooldown (spell ready). Use `~= false` for readiness checks.
- `auraInstanceID` — Stable numeric handle, same ID maps to same aura across combat. Use for tracking aura identity when `spellId`/`name` are secret.
- `isHelpful` / `isHarmful` — Aura disposition (may be secret in some contexts, fail-open)

**NeverSecret Target APIs (verified 2026-02-24):**
- `UnitClassification("target")` — `"normal"`, `"elite"`, `"worldboss"`, `"rare"`, `"rareelite"`, `"minus"`
- `UnitIsUnit("target", "boss1-5")` — Boss slot detection
- `UnitIsPlayer("target")` — Player vs NPC (confirmed `issecretvalue()=false`)
- `UnitIsMinion("target")` — Pets, totems, treants (combat-safe creature-type replacement)
- `UnitThreatSituation("player", "target")` — 0-3 threat state
- `UnitIsCrowdControlled("target")` — Target already CC'd
- `nameplate.UnitFrame.isPlayer` / `.isFriend` — Cached table fields, bypass secret system

**See:** `Documentation/12.0_COMPATIBILITY.md` → "Combat-Safe Signal Reference" for full matrix

**Secret Values (WoW 12.0+):**
- Blizzard hides certain combat data to prevent automation
- **Detection:** `BlizzardAPI.IsSecretValue(value)` returns `true` for secret data
- **Critical limitations:**
  - ❌ Cannot compare: `if charges > 2` crashes if `charges` is secret
  - ❌ Cannot do arithmetic: `charges + 1` returns secret value (unusable)
  - ❌ Cannot use in conditionals: `if duration > 5` fails if `duration` is secret
  - ✅ Can pass to UI: `FontString:SetText(secretValue)` works (Blizzard handles internally)
  - ✅ Can pass to cooldown: `Cooldown:SetCooldown(start, secretDuration)` works
- **Common secret values in combat:**
  - `C_Spell.GetSpellCooldown()` → `duration`/`startTime` (blanket-secreted even when zero)
  - `C_UnitAuras` → `spellId`, `name` (aura identity hidden in combat)
  - `currentCharges` (charge count)
  - `UnitHealth()` (potentially in some instanced content)
- **Fail-open design:** `IsSecretValue()` shows extra content rather than hiding valid data
- **Fallback pattern:** Cache non-secret structure data (e.g., `maxCharges`) for comparison

**Cooldown readiness pattern (use isOnGCD):**
```lua
local info = C_Spell.GetSpellCooldown(spellID)
if info then
    -- isOnGCD is NeverSecret: true=GCD only, false=real CD, nil=no CD
    if info.isOnGCD ~= false then
        -- Spell is ready (GCD or no cooldown)
    else
        -- Real cooldown active
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

PowerShell script `build.ps1` creates distributable package:
- Extracts version from `JustAC.toc` (currently 4.1.1)
- Packages core `.lua` files + `Libs/` folder
- Removes duplicate nested lib folders (common packaging error)
- Creates `dist/JustAC-<version>.zip` ready for CurseForge/GitHub

**Workflow:**
1. Make changes and commit them
2. Update `UNRELEASED.md` with change notes
3. When user requests version bump:
   - Move UNRELEASED changes to CHANGELOG.md
   - Increment version in JustAC.toc (use semantic versioning: 3.21.0 → 3.21.1 or 3.22.0)
   - Update library versions if breaking changes
   - Clear UNRELEASED.md
   - Commit version bump
4. User runs `.\build.ps1` when ready to test
5. User runs `git push` when ready to deploy

**Before release:** Test with `/jac modules` + in-game rotation to verify all modules loaded.
