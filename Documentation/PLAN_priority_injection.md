# Design Plan: Offensive Priority Injection List

Authored after reading the full queue pipeline. Pick this up in a new session
alongside SpellQueue.lua, GapCloserEngine.lua, Options/GapClosers.lua, and
Options/Defensives.lua as primary references.

---

## What this is

A user-configurable list of spells that JustAC injects into the DPS queue at a
chosen position when a set of conditions is met. The gap-closer injection in
SpellQueue.lua is the exact pattern — this generalises it so users can define
their own rules.

Example rules:
- "Show Execute at position 1 when Sudden Death is procced"
- "Show Shield Wall at position 1 when in combat and off cooldown"
- "Show Healthstone at position 2 when in combat, hide it when on cooldown"

---

## 12.0 API constraints (critical)

In 12.0 Midnight, most spell/unit data is **secret in combat** (issecretvalue()
returns true). This limits what conditions can be used:

| Condition type          | API source                                    | Secret? |
|-------------------------|-----------------------------------------------|---------|
| After casting spell Y   | UNIT_SPELLCAST_SUCCEEDED (spellID NeverSecret)| No      |
| Spell Y is procced      | C_SpellActivationOverlay.IsSpellOverlayed     | No      |
| In combat               | UnitAffectingCombat                           | No      |
| Spell off cooldown      | IsSpellUsable + local CD tracking             | No      |
| Enough resources        | IsSpellUsable (notEnoughResources return val) | No      |
| Buff/debuff active      | UnitAura contents                             | **YES** |
| Resource level (e.g. HP)| UnitPower                                     | **YES** |
| Enemy health %          | UnitHealth("target")                          | **YES** |

Feasible condition types: **afterCast**, **isProcced**, **inCombat**.
Display filters (per-entry toggles): **hideOnCooldown**, **hideIfNoResources**.

Do NOT attempt aura-based or resource-level conditions — they are secret in
combat and will always fail or return garbage.

---

## Proposed DB schema

Stored per spec under `profile.priorityInjections[specKey]` (parallel to
`profile.blacklistedSpells[specKey]` and `profile.gapCloserSpells[specKey]`).

```lua
profile.priorityInjections = {
  ["WARRIOR_3"] = {     -- specKey from SpellDB.GetSpecKey()
    {
      spellID     = 12345,          -- spell to inject
      position    = 1,              -- 1 = front, 2 = after pos1, etc.
      condLogic   = "any",          -- "any" (OR) or "all" (AND)
      conditions  = {
        { type = "isProcced",  spellID = 12345 },
        { type = "afterCast",  spellID = 67890, windowSecs = 8 },
        { type = "inCombat" },
      },
      -- Display filters (evaluated after conditions pass)
      hideOnCooldown   = true,      -- don't show if spell is on CD
      hideIfNoResources = false,    -- don't show if can't afford resources
    },
    -- more rules...
  }
}
```

Rules are evaluated in order; first matching rule for a given spellID wins.
A rule with zero conditions is treated as "always inject when visible".

---

## Components to build

### 1. Recent-cast tracker (small, in CooldownTracking.lua or new file)

The `UNIT_SPELLCAST_SUCCEEDED` event frame already exists in
`BlizzardAPI/CooldownTracking.lua`. Extend it with a ring buffer:

```lua
-- Ring buffer: last N player spell casts with timestamps
local recentCasts = {}        -- { [spellID] = lastCastTime }
local RECENT_CAST_WINDOW = 30 -- seconds; prune older entries lazily

-- In the existing UNIT_SPELLCAST_SUCCEEDED handler:
if unit == "player" and spellID then
    recentCasts[spellID] = GetTime()
    RecordSpellCooldown(spellID)  -- existing call
end

function BlizzardAPI.WasCastWithin(spellID, windowSecs)
    local t = recentCasts[spellID]
    if not t then return false end
    return (GetTime() - t) <= windowSecs
end

function BlizzardAPI.ClearRecentCasts()
    wipe(recentCasts)
end
```

Call `ClearRecentCasts()` on `PLAYER_ENTERING_WORLD`/`PLAYER_DEAD` (already
handled in the same event frame).

### 2. Condition evaluator (new function in SpellQueue.lua or new module)

```lua
-- Returns true if a single condition passes
local function EvalCondition(cond)
    if cond.type == "inCombat" then
        return UnitAffectingCombat("player")
    elseif cond.type == "isProcced" then
        return BlizzardAPI.IsSpellProcced(cond.spellID or rule.spellID)
    elseif cond.type == "afterCast" then
        return BlizzardAPI.WasCastWithin(cond.spellID, cond.windowSecs or 10)
    end
    return true  -- unknown condition type: fail-open
end

-- Returns true if the rule's condition set passes
local function RuleConditionsMet(rule)
    if not rule.conditions or #rule.conditions == 0 then return true end
    if rule.condLogic == "all" then
        for _, cond in ipairs(rule.conditions) do
            if not EvalCondition(cond) then return false end
        end
        return true
    else  -- "any" (default)
        for _, cond in ipairs(rule.conditions) do
            if EvalCondition(cond) then return true end
        end
        return false
    end
end

-- Returns true if the spell should be shown given display filters
local function RuleDisplayAllowed(rule)
    local spellID = rule.spellID
    if rule.hideOnCooldown then
        local isOnLocalCD = BlizzardAPI.IsSpellOnLocalCooldown(spellID)
        if isOnLocalCD then return false end
        local usable, _ = BlizzardAPI.IsSpellUsable(spellID, false)  -- failOpen=false
        if usable == false then return false end  -- nil = unknown, don't hide
    end
    if rule.hideIfNoResources then
        local _, noResources = BlizzardAPI.IsSpellUsable(spellID, true)
        if noResources then return false end
    end
    return true
end
```

### 3. Injection step in SpellQueue.GetCurrentSpellQueue()

Insert after the gap-closer block, before the rotation-list pass (around line
378 in SpellQueue.lua). Follow the gap-closer pattern exactly:

```lua
-- Priority injection rules (user-configured)
local injectionList = GetPriorityInjections()   -- reads profile[specKey]
if injectionList then
    for _, rule in ipairs(injectionList) do
        if spellCount >= maxIcons then break end
        local spellID = rule.spellID
        if spellID and not addedSpellIDs[spellID] then
            if BlizzardAPI.IsSpellAvailable(spellID)
               and RuleConditionsMet(rule)
               and RuleDisplayAllowed(rule) then
                local pos = math.min(rule.position or 1, spellCount + 1)
                -- Shift existing spells right to make room
                for i = spellCount, pos, -1 do
                    recommendedSpells[i + 1] = recommendedSpells[i]
                end
                recommendedSpells[pos] = spellID
                spellCount = spellCount + 1
                addedSpellIDs[spellID] = true
                -- Mark as synthetic proc so it gets the green glow
                syntheticProcs[spellID] = true
            end
        end
    end
end
```

### 4. Options UI (Options/PriorityInjections.lua — new file)

Mirror Options/GapClosers.lua structure. The main rebuild function is
`UpdatePriorityInjectionOptions(addon)`.

Each rule renders as an inline group containing:
- Spell icon + name (read-only label, from GetCachedSpellInfo)
- Position selector: range 1–maxIcons
- Condition logic: dropdown "Any condition" / "All conditions"
- Condition list: per-condition inline group with:
  - Type dropdown: "In Combat" / "Spell Procced" / "After Casting..."
  - Spell picker (for isProcced, afterCast types): inline LiveSearchPopup button
  - Window seconds slider (afterCast only): 1–30s
  - Remove condition button
- "Add Condition" button
- Display filter toggles: "Hide when on cooldown" / "Hide if not enough resources"
- Move Up / Move Down / Remove rule buttons
- "Add Rule..." button at bottom (opens LiveSearchPopup for spell selection)

The rule list is stored as an ordered array (not a hash map) so the UI's
Up/Down buttons work identically to the defensive list.

This is the largest component. Budget ~300 lines of AceConfig options table
construction.

### 5. Options/Core.lua integration

In the options table setup, add the new tab:

```lua
local PriorityInjections = LibStub("JustAC-OptionsPriorityInjections", true)
-- In args:
priorityInjections = PriorityInjections and PriorityInjections.CreateTabArgs(addon) or nil,
```

And expose `UpdatePriorityInjectionOptions` via the Options facade so
SpellQueue can call it after blacklist-style toggles if needed.

---

## Files to create / modify

| File | Action |
|------|--------|
| `BlizzardAPI/CooldownTracking.lua` | Add `recentCasts` ring buffer + `WasCastWithin()` |
| `SpellQueue.lua` | Add injection step + `GetPriorityInjections()` helper |
| `Options/PriorityInjections.lua` | New file — full options UI |
| `Options/Core.lua` | Wire in new tab + expose update function |
| `JustAC.toc` | Add PriorityInjections.lua |
| `Options/Labels.lua` | Add locale strings |

No changes needed to DefensiveEngine, GapCloserEngine, UIRenderer, or
BlizzardAPI/StateHelpers.

---

## Display filter details

`hideOnCooldown`:
- Check `BlizzardAPI.IsSpellOnLocalCooldown(spellID)` first (fast, no API call)
- Fall back to `BlizzardAPI.IsSpellUsable(spellID, false)` (failOpen=false so
  it hides rather than shows when uncertain)
- Note: in 12.0 combat, CD duration is secret; local tracking covers spells
  the user has cast this session, action bar usability covers the rest

`hideIfNoResources`:
- Use the second return value of `BlizzardAPI.IsSpellUsable(spellID, true)`:
  `local _, notEnoughResources = BlizzardAPI.IsSpellUsable(spellID, true)`
- `notEnoughResources` is NeverSecret (verified in existing usage)
- Only hide if explicitly `true`; nil (unknown) means fail-open / keep showing

Both filters are evaluated AFTER conditions pass, so a spell that's procced
but on cooldown can still be hidden via `hideOnCooldown = true`.

---

## Edge cases and decisions

**Position clamping**: `rule.position` is clamped to `spellCount + 1` so a
rule targeting position 3 on an empty queue still inserts at position 1.

**Multiple rules for the same spell**: Only the first matching rule fires.
`addedSpellIDs` prevents duplicates within the same queue build.

**Rule ordering**: The rule array is user-ordered (same as defensive list).
Higher-priority rules should appear first; the UI provides Up/Down buttons.

**Interaction with gap-closers**: Gap-closer injection runs before priority
injection. If the gap-closer fires, it takes position 1 and shifts everything
right. A priority injection targeting position 1 will land at position 2 in
that frame — acceptable, not worth special-casing.

**Interaction with blacklist**: `addedSpellIDs` does not pre-populate from the
blacklist for injected spells. An injected spell that is also blacklisted will
still inject — this is intentional (user explicitly added it to the injection
list). If desired, add a `SpellQueue.IsSpellBlacklisted(spellID)` check.

**No `ForceUpdate` after rule eval**: The injection runs inside
`GetCurrentSpellQueue()` which is already driven by the update loop. No
additional dirty-flagging needed. The `updateFunc` in the Options UI should
call `addon:ForceUpdate()` (same as GapClosers).

---

## What to implement first (suggested order)

1. `WasCastWithin()` in CooldownTracking — small, self-contained, testable
2. `GetPriorityInjections()` + injection step in SpellQueue — engine core
3. Options UI (PriorityInjections.lua) — longest but straightforward given
   the GapClosers and Defensives panels as templates
4. Core.lua wiring + TOC + locale strings
