# Midnight Post-Launch Research (March 2026)

Researched: 2026-03-07. Midnight (12.0) launched: 2026-03-02.

Companion to `12.0_COMPATIBILITY.md` (alpha/beta findings).
This document covers post-launch confirmation, newly available APIs,
and reference addon patterns observed in the wild.

---

## What Actually Happened vs. Beta Predictions

### CLEU: Completely Removed (not secret — gone)

Combat Log Events (`COMBAT_LOG_EVENT_UNFILTERED`) were fully removed, not just restricted.
Source data is gone; no fallback pattern exists.

**JustAC impact: none.** Zero CLEU usage found anywhere in the codebase (grep verified).

### UnitHealth / UnitHealthMax: Secret in combat (confirmed)

Beta finding held. `UnitHealth("player")` and `UnitHealthMax("player")` are SECRET in open
world combat. The `LowHealthFrame` fallback implemented in `BlizzardAPI.GetPlayerHealthPercentSafe()`
is the correct approach.

**New:** `UnitHealthPercent()` and `UnitHealthMissing()` were added in 12.0 but are
**SECRET even out of combat** (verified 2026-03-07). They are unusable. See "New APIs" section.

**Also confirmed:** `C_Secrets.ShouldUnitHealthMaxBeSecret("player")` returns `false` in combat,
meaning `UnitHealthMax("player")` is NeverSecret. Only `UnitHealth("player")` is secret in combat.

### auraInstanceID mapping (RedundancyFilter v38): Holding up in live

The beta assumption that `auraInstanceID` is NeverSecret has held in live play.
The pending activation FIFO queue pattern (UNIT_SPELLCAST_SUCCEEDED → addedAuras) is working.

### Whitelist state at launch

The whitelist was smaller than anticipated at launch. Blizzard deferred many additional
whitelist entries to Patch 12.0.1 (released ~2 weeks after launch). Players needed "creative
solutions" in the interim. Relevant whitelisted spells at 12.0:

- **GCD dummy spell** (already used in `BlizzardAPI.GetGCDInfo()`) — officially whitelisted
- **All combat resurrection spells** — cooldowns and charge counts non-secret
- **Maelstrom Weapon** — full aura data (Enhancement Shaman)
- Devourer DH resource spells, Skyriding spells

Additional per-spell whitelisting ongoing in 12.0.1+.

---

## New APIs Added in 12.0

These were not available during alpha/beta testing but are confirmed in live 12.0.

### Aura Classification

```lua
-- Returns true if Blizzard classifies this aura as a major defensive.
-- Replaces/augments manual defensive aura spell ID lists.
-- Input: auraInstanceID (NeverSecret handle from GetAuraDataByIndex)
C_UnitAuras.AuraIsBigDefensive(auraInstanceID)  --> boolean
```

**Opportunity for DefensiveEngine.lua:** Use this to augment or partially replace the
hardcoded `DEFENSIVE_SPELLS` table's aura tracking. Blizzard maintains the classification;
we benefit automatically when new defensives are added.

### GetUnitAuras (replaces GetAuraDataByIndex iteration)

```lua
-- Returns all auras in one call. New params: sortRule, sortDirection.
-- Preferred over index-loop in 12.0+.
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", {
    sortRule = Enum.AuraSortMethod.Duration,
    sortDirection = Enum.AuraSortDirection.Ascending,
})
-- auras is a table; same field layout as GetAuraDataByIndex result objects
```

`GetAuraDataByIndex` was deprecated in 10.2.5. It is NOT confirmed removed in 12.0,
but Blizzard noted some deprecated `C_UnitAuras` APIs were removed in 12.0.
**JustAC is pcall-protected at all call sites** (RedundancyFilter.lua, SecretValues.lua)
so a removal would degrade gracefully. Migrate to `GetUnitAuras` during a cleanup pass.

### Non-Secret Health/Power Helpers

```lua
-- Added in 12.0. Simpler than UnitHealth/UnitHealthMax division.
UnitHealthPercent(unit)   --> number (0–100)
UnitHealthMissing(unit)   --> number (raw HP missing)
UnitPowerPercent(unit[, powerType])  --> number (0–100)
UnitPowerMissing(unit[, powerType])  --> number (raw resource missing)
```

**CONFIRMED SECRET (2026-03-07):** ALL four helpers return secret values even **out of combat**:
- `UnitHealthPercent("player")` — SECRET
- `UnitHealthMissing("player")` — SECRET
- `UnitPowerPercent("player")` — SECRET
- `UnitPowerMissing("player")` — SECRET

These are unusable for any logic — worse than `UnitHealth/UnitHealthMax` which are at least
readable out of combat. The current `GetPlayerHealthPercentSafe()` fallback chain
(UnitHealth/UnitHealthMax → LowHealthFrame) remains the correct approach.

**CONFIRMED WORKING (2026-03-07):**
- `C_UnitAuras.AuraIsBigDefensive()` — API exists (see action item #3)
- `C_UnitAuras.GetUnitAuras()` — Works, returns aura table directly (see action item #4)

### Cast Sequence ID

New return value delivered with all `UNIT_SPELLCAST_*` events. Never secret. Increments
monotonically on each new cast. Useful for deduplicating cast events more reliably than
timestamp comparisons. No current use case in JustAC but worth knowing.

### Party Kill Event

```lua
-- Fires when a party member kills a unit.
-- Payload: attackerGUID, targetGUID
PARTY_KILL
```

The post-CLEU replacement for party kill detection in scenarios where group-kill information
matters. JustAC has no current use case but relevant if group-context logic is added.

### Heal Prediction / Absorb API

```lua
-- New for unit frame addons (12.0).
CreateUnitHealPredictionCalculator()
UnitGetDetailedHealPrediction(unit)
```

JustAC has no current use case, but relevant if health-bar overlays are revisited.

### Castbar Utilities

```lua
-- Optional direction param added to StatusBar:SetTimerDuration().
-- Allows fill-from-remaining-duration for channels.
StatusBar:SetTimerDuration(duration, direction)

-- C_CurveUtil: convert secret boolean to color for visual-only display.
C_CurveUtil.EvaluateColorFromBoolean(curve, secretBool)       --> r, g, b, a
C_CurveUtil.EvaluateColorValueFromBoolean(curve, secretBool)  --> number (0–1)
```

### String / Display Utilities

```lua
-- Display a number that may be secret. Handles secret → display-safe conversion.
SecondsFormatter  -- Lua object. Use for CD countdowns when value may be secret.

-- Restored to restricted environment (were blocked during beta):
strsplit, strjoin, strconcat
```

---

## C_Secrets: Pre-Flight Guards (Confirmed 2026-03-07)

The `C_Secrets` namespace provides fast, non-secret boolean guards
that avoid per-value `issecretvalue()` overhead. The actual live API is significantly
richer than wiki documentation suggested.

**Confirmed functions (pairs() dump 2026-03-07):**

### Master Switch
```lua
C_Secrets.HasSecretRestrictions()              --> bool: any restriction active?
-- IN COMBAT: true | OUT OF COMBAT: false
```

### Unit Data Secrecy (require unit arg)
```lua
C_Secrets.ShouldUnitHealthMaxBeSecret(unit)    --> bool: UnitHealthMax secret?
-- IN COMBAT: false (NeverSecret!) | Confirms UnitHealthMax is always readable
C_Secrets.ShouldUnitPowerBeSecret(unit[, powerType]) --> bool: power secret?
-- IN COMBAT (no powerType arg): true (conservative/blanket answer)
-- IN COMBAT (with powerType): per-type granular answer:
--   ShouldUnitPowerBeSecret("player", 0) = false (Mana, Ret Paladin)
--   ShouldUnitPowerBeSecret("player", 9) = false (Holy Power)
--   Confirmed: per-type query agrees with actual issecretvalue() on UnitPower()
-- Use per-type queries for accurate secrecy checks; no-arg is overly conservative
C_Secrets.ShouldUnitPowerMaxBeSecret()         --> bool: power max secret? (untested)
C_Secrets.ShouldUnitComparisonBeSecret()       --> bool: unit comparison secret? (untested)
C_Secrets.ShouldUnitIdentityBeSecret()         --> bool: unit identity secret? (untested)
C_Secrets.ShouldUnitThreatValuesBeSecret()     --> bool: threat values secret? (untested)
C_Secrets.ShouldUnitThreatStateBeSecret(unit)  --> bool: threat state secret?
-- IN COMBAT: false (NeverSecret!) | Confirms UnitThreatSituation is always readable
```

### Aura Secrecy (no args required for blanket check)
```lua
C_Secrets.ShouldAurasBeSecret()                --> bool: aura contents secret?
-- IN COMBAT: true | Use as fast early-exit before aura scan loops
C_Secrets.ShouldUnitAuraIndexBeSecret()        --> bool: aura-by-index secret? (untested)
C_Secrets.ShouldUnitAuraSlotBeSecret()         --> bool: aura-by-slot secret? (untested)
C_Secrets.ShouldUnitAuraInstanceBeSecret()     --> bool: aura-by-instance secret? (untested)
C_Secrets.ShouldSpellAuraBeSecret()            --> bool: spell aura secret? (untested)
```

### Cooldown Secrecy
```lua
C_Secrets.ShouldCooldownsBeSecret()            --> bool: general cooldowns secret?
-- IN COMBAT: true | Blanket check, no args needed
C_Secrets.ShouldSpellCooldownBeSecret(spellID) --> bool: per-spell cooldown secret? (requires spellID)
C_Secrets.ShouldActionCooldownBeSecret()       --> bool: action bar cooldowns secret? (untested)
C_Secrets.ShouldSpellBookItemCooldownBeSecret() --> bool: spellbook item CDs secret? (untested)
```

### Spellcast Secrecy
```lua
C_Secrets.ShouldUnitSpellCastingBeSecret()     --> bool: spellcasting info secret?
C_Secrets.ShouldUnitSpellCastBeSecret()        --> bool: spellcast info secret?
C_Secrets.ShouldTotemSpellBeSecret()           --> bool: totem spell secret?
C_Secrets.ShouldTotemSlotBeSecret()            --> bool: totem slot secret?
```

### Getter Functions (return richer secrecy metadata)
```lua
C_Secrets.GetSpellCastSecrecy()                --> secrecy info for spell casts
C_Secrets.GetSpellAuraSecrecy()                --> secrecy info for spell auras
C_Secrets.GetSpellCooldownSecrecy()            --> secrecy info for spell cooldowns
C_Secrets.GetPowerTypeSecrecy()                --> secrecy info per power type
```

### C_RestrictedActions (confirmed 2026-03-07)
```lua
C_RestrictedActions.IsAddOnRestrictionActive()  --> bool: addon restrictions active?
C_RestrictedActions.GetAddOnRestrictionState()  --> state enum/value
C_RestrictedActions.CheckAllowProtectedFunctions() --> bool: protected functions allowed?
```

**Opportunity:** Add `C_Secrets.ShouldAurasBeSecret()` as a fast early-exit in the aura
scan loops in `RedundancyFilter.lua` and `BlizzardAPI/SecretValues.lua`. This skips the
entire `GetAuraDataByIndex` loop when results would all be secret anyway, saving CPU on
every aura scan triggered during combat.

---

## Reference Addon Patterns (Post-Launch)

### MidnightSimpleAuras
Source: https://github.com/Mapkov2/Midnight-Simple-Auras

Key patterns observed:
- `issecretvalue` guard on every timing read before displaying duration
- "Secure cooldown passthrough": obtain a `LuaDurationObject` via `GetSpellCooldownDuration`,
  pass directly to `SetCooldownFromDurationObject` — no intermediate secret value touched
- `MSA_BuffBridge.lua`: out-of-combat aura cache bridged into combat via instanceID maps
  (same pattern as JustAC RedundancyFilter v38)
- Whitelisted aura handling: separate code path for spells where full data is available

### OmniCD
Cooldown/interrupt tracker for group content. Post-CLEU approach:
- Uses only legal, non-secret combat data
- Party defensive and interrupt tracking via action timeline, not event listening
- Shows Ironbark, Pain Suppression, etc. using the `C_Spell.IsExternalDefensive()` API
  (already documented in JustAC's `12.0_COMPATIBILITY.md`)

### BetterBlizzFrames / MidnightSimpleUnitFrames
Working unit frame addons (ElvUI and SUF broke at launch):
- Build on Blizzard's frame templates rather than replacing them
- Aura display uses `C_UnitAuras.GetUnitAuras()` (not the deprecated index loop)
- Health display uses new `UnitHealthPercent()` helper
  - **Note:** `UnitHealthPercent()` is SECRET even out of combat (verified 2026-03-07).
    These addons may be using Blizzard's secure display pipeline to render it visually
    without branching on the value.

### Blizzard Cooldown Manager + TweaksUI: Cooldowns
Native Blizzard Cooldown Manager covers major abilities, procs, and healer externals
(Ironbark, Pain Suppression visible via whitelisted data). TweaksUI adds addon
customization hooks on top. Useful reference for the whitelist scope.

---

## Action Items for JustAC

Priority ordered. None are regressions — these are improvements.

| Priority | Item | Location | Notes |
|----------|------|----------|-------|
| 1 | Add `C_Secrets.ShouldAurasBeSecret()` fast pre-check | RedundancyFilter.lua, SecretValues.lua | Short-circuit full aura scan when everything would be secret anyway |
| ~~2~~ | ~~Validate `UnitHealthPercent("player")` non-secret status in-game~~ | ~~BlizzardAPI/StateHelpers.lua~~ | **REJECTED (2026-03-07):** Secret even out of combat. Current fallback chain is correct. |
| 3 | Evaluate `C_UnitAuras.AuraIsBigDefensive()` for defensive tracking | DefensiveEngine.lua | Could replace/augment manual aura ID lists |
| 4 | Migrate from `GetAuraDataByIndex` to `GetUnitAuras()` | RedundancyFilter.lua, SecretValues.lua, DebugCommands.lua | Cleanup pass — pcall fallback already in place |
| 5 | Consider `SecondsFormatter` for CD countdown display | UI/UIRenderer.lua | Only if current `SetCooldownFromDurationObject` path proves insufficient |

---

## Addons That Broke at Launch (For Context)

| Addon | Status | Reason |
|-------|--------|--------|
| ElvUI | No updates until 12.0.5+ | Massive rewrite required for new container model |
| WeakAuras (rotation profiles) | Effectively dead for decision logic | Cannot access protected combat data |
| WeakAuras (visual display) | Functional (limited) | Still works as visual display layer |
| Shadowed Unit Frames | Broken | Replaced raw frame access patterns |
| Z-Perl | Broken | Same root cause as SUF |
| Hekili | Dead | Direct rotation calculation explicitly blocked |

JustAC is unaffected by all of the above because it consumes `C_AssistedCombat` output
(Blizzard's own feature) rather than calculating rotation logic.

---

## Sources

- https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
- https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes
- https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes
- https://www.wowhead.com/news/majority-of-addon-changes-finalized-for-midnight-pre-patch-whitelisted-spells-379738
- https://www.icy-veins.com/wow/news/blizzard-relaxing-more-addon-limitations-in-midnight/
- https://www.warcrafttavern.com/wow/news/elvui-joins-weakauras-in-development-limbo-for-midnight/
- https://www.wowhead.com/news/unit-frame-addons-in-midnight-massive-changes-project-reworked-for-midnight-379941
- https://us.forums.blizzard.com/en/wow/t/with-new-api-changes-addons-are-once-again-stronger-than-base-ui-on-beta/2215895
- https://kaylriene.com/2025/10/03/wow-midnights-addon-combat-and-design-changes-part-1-api-anarchy-and-the-dark-black-box/
