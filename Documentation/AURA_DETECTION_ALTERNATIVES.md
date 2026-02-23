# Alternative Aura Detection Methods for WoW 12.0

When `C_UnitAuras.GetAuraDataByIndex()` returns secret values, these alternatives may bypass restrictions.

## IMPLEMENTED SOLUTION: auraInstanceID Mapping (RedundancyFilter v38)

**Status:** ✅ Implemented and tested — handles multi-cycle removal/reapply in combat.

`auraInstanceID` is a **NeverSecret** stable numeric handle. The same ID maps to the same aura across combat entry. New auras get new IDs. This field is always readable, even when `spellId` and `name` are secret.

### Architecture

```
Out of combat:
  RefreshAuraCache() → GetAuraDataByIndex() → populate instance maps
    instanceToSpellMap[auraInstanceID] = spellId
    instanceToNameMap[auraInstanceID] = name
    instanceToIconMap[auraInstanceID] = icon
    instanceToTimingMap[auraInstanceID] = {duration, expirationTime}

In combat (spellId/name are secret):
  RefreshAuraCache() → GetAuraDataByIndex() → resolve via instance maps
    if IsSecretValue(data.spellId) then
        data.spellId = instanceToSpellMap[data.auraInstanceID]
    end

UNIT_AURA(unit, updateInfo) keeps maps current:
  removedAuraInstanceIDs → clean map entries, record in combatRemovedSpellIDs
  addedAuras → map new instances (non-secret spellId or pending activation match)

UNIT_SPELLCAST_SUCCEEDED → queue pending activations (FIFO, 2s window)
  Bridges the gap: cast event fires BEFORE UNIT_AURA addedAuras
  Only queues UNIQUE_AURA_SPELLS and RAID_BUFF_SPELLS
  Harmful auras (isHarmful=true or isHelpful=false) filtered from matching

PLAYER_REGEN_ENABLED → clear combat tracking state
  Wipes inCombatActivations, combatRemovedSpellIDs, pendingActivations
```

### Key Design Decisions

1. **Instance maps persist across combat** — populated out of combat, used in combat
2. **Pending activation FIFO** — handles recast after removal when new instance has secret spellId
3. **combatRemovedSpellIDs** — prevents trusted cache merge from re-hiding removed buffs
4. **spellStateKnown bypass** — if a spell is resolved (in cache) or explicitly removed, skip the non-DPS blanket filter
5. **IsInPandemicWindow** — returns false for fresh inCombatActivations (no timing = just cast = full duration)
6. **Harmful aura filtering** — debuffs can't consume pending activation entries meant for buffs

### Limitations

- Auras applied for the first time during combat (never seen out of combat, no UNIT_SPELLCAST_SUCCEEDED) remain as unresolved secrets
- If `isHelpful`/`isHarmful` are also secret, debuffs could theoretically consume pending matches (fail-open)
- Instance maps grow unbounded within a combat session (cleaned on combat exit)

---

## API Reference: Secret Value Restrictions

Based on Blizzard API Documentation (`SecretPredicateAPIDocumentation.lua`):

### C_Secrets Namespace - Proactive Secrecy Testing

| Function | Purpose |
|----------|---------|
| `C_Secrets.HasSecretRestrictions()` | Returns true if secrets are enabled on this build |
| `C_Secrets.ShouldAurasBeSecret()` | Returns true if aura queries will generally return secrets |
| `C_Secrets.ShouldCooldownsBeSecret()` | Returns true if cooldown queries will generally return secrets |
| `C_Secrets.ShouldSpellCooldownBeSecret(spellID)` | Check specific spell's cooldown secrecy |
| `C_Secrets.ShouldSpellAuraBeSecret(spellID)` | Check if a specific aura would be secret |
| `C_Secrets.ShouldUnitAuraIndexBeSecret(unit, index, filter)` | Check specific aura index |
| `C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)` | Check specific aura instance |
| `C_Secrets.ShouldUnitHealthMaxBeSecret(unit)` | Check if unit's max health is secret |
| `C_Secrets.ShouldUnitPowerBeSecret(unit, powerType)` | Check if unit's power is secret |
| `C_Secrets.ShouldUnitIdentityBeSecret(unit)` | Check if unit's name/GUID is secret |
| `C_Secrets.GetSpellAuraSecrecy(spellID)` | Returns SecrecyLevel enum |
| `C_Secrets.GetSpellCooldownSecrecy(spellID)` | Returns SecrecyLevel enum |
| `C_Secrets.GetSpellCastSecrecy(spellID)` | Returns SecrecyLevel enum |

### SecrecyLevel Enum

| Value | Meaning |
|-------|---------|
| `0` (NeverSecret) | Will never yield secret values when queried |
| `1` (AlwaysSecret) | Will always yield secret values when queried |
| `2` (ContextuallySecret) | May yield secrets depending on addon restriction states, unit disposition |

### APIs Marked as Safe (No SecretWhen* Conditions)

| Category | API | Notes |
|----------|-----|-------|
| **Forms/Stances** | `GetShapeshiftFormInfo(index)` | Returns icon, active, castable, spellID - ALWAYS SAFE |
| **Forms/Stances** | `GetNumShapeshiftForms()` | Count of available forms - ALWAYS SAFE |
| **Forms/Stances** | `GetShapeshiftFormID()` | Current form constant ID - ALWAYS SAFE |
| **Unit Existence** | `UnitExists(unit)` | No SecretWhen - ALWAYS SAFE |
| **Dead/Alive** | `UnitIsDead(unit)` | No SecretWhen - ALWAYS SAFE |
| **Dead/Alive** | `UnitIsDeadOrGhost(unit)` | No SecretWhen - ALWAYS SAFE |
| **Spec** | `GetSpecialization()` | Current spec index - ALWAYS SAFE |
| **Spec** | `GetNumSpecializations()` | Number of specs - ALWAYS SAFE |
| **Spell Info** | `C_Spell.GetSpellInfo(spellID)` | Name, icon, etc - ALWAYS SAFE |
| **Spell Info** | `C_Spell.GetSpellName(spellID)` | Spell name only - ALWAYS SAFE |
| **Spell Info** | `C_Spell.GetOverrideSpell(spellID)` | Override lookup - ALWAYS SAFE |
| **Spell Overlay** | `C_SpellActivationOverlay.IsSpellOverlayed(spellID)` | Proc glow detection |
| **Weapon Enchants** | `GetWeaponEnchantInfo()` | Weapon imbues - ALWAYS SAFE |

### APIs With Conditional Secrecy

| Category | API | Condition |
|----------|-----|-----------|
| **Auras** | `C_UnitAuras.GetAuraDataByIndex()` | SecretWhenUnitAuraRestricted |
| **Auras** | `C_UnitAuras.GetPlayerAuraBySpellID()` | SecretWhenUnitAuraRestricted + RequiresNonSecretAura |
| **Auras** | `C_UnitAuras.GetAuraDataBySpellName()` | SecretWhenUnitAuraRestricted + RequiresNonSecretAura |
| **Auras** | `C_UnitAuras.GetUnitAuras()` | ConditionalSecretContents - vector safe, contents may be secret |
| **Cooldowns** | `C_Spell.GetSpellCooldown()` | SecretWhenSpellCooldownRestricted |
| **Cooldowns** | `C_Spell.GetSpellCharges()` | SecretWhenSpellCooldownRestricted |
| **Health** | `UnitHealth(unit)` | SecretReturns (always potentially secret) |
| **Health** | `UnitHealthMax(unit)` | SecretWhenUnitHealthMaxRestricted |
| **Health** | `UnitHealthPercent(unit)` | SecretReturns + SecretWhenCurveSecret |
| **Power** | `GetComboPoints(unit, target)` | SecretWhenUnitPowerRestricted |
| **Casting** | `GetUnitEmpowerStageDuration()` | SecretWhenUnitSpellCastRestricted |

---

## Method 1: Direct Spell ID Lookup (BEST)

**API:** `C_UnitAuras.GetPlayerAuraBySpellID(spellID)`

```lua
-- Check if player has specific buff by spell ID
local function HasBuffBySpellID_Direct(spellID)
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then
        return false
    end
    
    local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if not auraData then return false end
    
    -- Check if result is a secret
    if issecretvalue and issecretvalue(auraData.spellId) then
        return nil  -- Can't determine
    end
    
    return true  -- Has the buff
end
```

**Advantages:**
- Direct lookup, no iteration
- Only queries specific spell we care about
- May be exempt from secret restrictions (targeted query vs bulk query)

**Disadvantages:**
- Still might return secrets (needs testing)
- Only works for known spell IDs

## Method 2: Slot-Based Access

**API:** `C_UnitAuras.GetAuraSlots()` + `C_UnitAuras.GetAuraDataBySlot()`

```lua
-- Use slot system instead of index iteration
local function RefreshAuraCache_Slots()
    local cachedAuras = {}
    cachedAuras.byID = {}
    
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots then
        return cachedAuras
    end
    
    -- Get all aura slots for helpful buffs
    local continuationToken, slots = C_UnitAuras.GetAuraSlots("player", "HELPFUL")
    
    if not slots then
        return cachedAuras
    end
    
    -- Iterate through slots
    for i = 1, #slots do
        local slot = slots[i]
        local auraData = C_UnitAuras.GetAuraDataBySlot("player", slot)
        
        if auraData and auraData.spellId then
            -- Check for secrets
            if issecretvalue and issecretvalue(auraData.spellId) then
                cachedAuras.hasSecrets = true
                break
            end
            
            cachedAuras.byID[auraData.spellId] = true
        end
    end
    
    return cachedAuras
end
```

**Advantages:**
- Different code path than GetAuraDataByIndex
- Might have different secret restrictions

**Disadvantages:**
- Still likely returns secrets
- More complex API

## Method 3: Spell Name Lookup

**API:** `C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)`

```lua
-- Check by spell name instead of ID
local function HasBuffByName_Direct(spellName)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataBySpellName then
        return false
    end
    
    local auraData = C_UnitAuras.GetAuraDataBySpellName("player", spellName, "HELPFUL")
    if not auraData then return false end
    
    -- Check for secrets
    if issecretvalue and (issecretvalue(auraData.name) or issecretvalue(auraData.spellId)) then
        return nil  -- Can't determine
    end
    
    return true
end
```

**Advantages:**
- Bypasses spell ID lookup entirely
- Works with localized names

**Disadvantages:**
- Names are localized (not portable across regions)
- Still might return secrets

## Method 4: Weapon Buff Detection

**API:** `GetWeaponEnchantInfo()` (for imbues/enchants)

```lua
-- Already implemented for Shaman weapon imbues
-- This API appears to NOT return secrets
local function HasActiveWeaponEnchant()
    if not GetWeaponEnchantInfo then return false end
    
    local hasMainHand, mainHandExpiration = GetWeaponEnchantInfo()
    
    return hasMainHand and (not mainHandExpiration or mainHandExpiration > 10000)
end
```

**Advantages:**
- Confirmed NOT secret in 12.0
- Reliable for weapon enchants

**Disadvantages:**
- Only works for weapon enchants
- Limited use case

## Method 5: Spell Overlay Detection (Proc Detection)

**API:** `C_SpellActivationOverlay.IsSpellOverlayed(spellID)`

```lua
-- Check if spell has proc glow (implies buff is active)
local function IsSpellProccedOrActive(spellID)
    if not C_SpellActivationOverlay or not C_SpellActivationOverlay.IsSpellOverlayed then
        return false
    end
    
    local hasProc = C_SpellActivationOverlay.IsSpellOverlayed(spellID)
    
    -- Check for secrets
    if issecretvalue and issecretvalue(hasProc) then
        return nil
    end
    
    return hasProc
end
```

**Advantages:**
- Different system entirely (visual effects, not auras)
- May bypass aura restrictions

**Disadvantages:**
- Only works for procced abilities
- Doesn't tell us about normal buffs

## Method 6: Combat Log Parsing

**Event:** `COMBAT_LOG_EVENT_UNFILTERED`

⚠️ **NOT AVAILABLE IN 12.0** - Combat log access is also restricted by secrets

## Recommended Strategy — SUPERSEDED

> **Note:** The auraInstanceID mapping approach (documented at the top of this file) is the implemented solution.
> The layered approach below was the original pre-implementation plan. It is preserved for reference
> but is NOT the current code path.

**Original layered approach** - try methods in order until one works:

```lua
local function HasBuffBySpellID_Smart(spellID, spellName)
    -- Try 1: Direct lookup by spell ID (best if not secret)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if auraData then
            if not (issecretvalue and issecretvalue(auraData.spellId)) then
                return true  -- Has buff, not secret
            end
            -- Fall through if secret
        else
            return false  -- Definitely doesn't have it
        end
    end
    
    -- Try 2: Lookup by spell name (if provided and different API path)
    if spellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local auraData = C_UnitAuras.GetAuraDataBySpellName("player", spellName, "HELPFUL")
        if auraData then
            if not (issecretvalue and (issecretvalue(auraData.spellId) or issecretvalue(auraData.name))) then
                return true  -- Has buff, not secret
            end
        else
            return false  -- Doesn't have it
        end
    end
    
    -- Try 3: Fallback to index iteration (current method)
    -- This will set hasSecrets flag if blocked
    return HasBuffBySpellID_Index(spellID)
end
```

## Testing Priority — RESOLVED\n\nThe auraInstanceID mapping approach was implemented and tested successfully.\nThe methods below were candidates evaluated before implementation:\n\n1. **auraInstanceID mapping** - ✅ IMPLEMENTED (RedundancyFilter v38) — NeverSecret handles, maps built OOC, resolved in combat\n2. **GetPlayerAuraBySpellID** - Not used (still returns secrets for spellId field)\n3. **GetAuraDataBySpellName** - Not used (still returns secrets)\n4. **Slot-based access** - Not used (same underlying data, same secrets)\n5. **Hardcoded filtering** - Superseded by instance map approach", "oldString": "## Testing Priority\n\n1. **GetPlayerAuraBySpellID** - Most promising, direct lookup by spell ID\n2. **GetAuraDataBySpellName** - Alternative using spell names\n3. **Slot-based access** - Different iteration method\n4. **Hardcoded filtering** - Current fallback (hide common buffs when secrets detected)

## Implementation Notes

- auraInstanceID mapping proved to be the winning approach (NeverSecret, stable handles)
- GetPlayerAuraBySpellID still returns secrets for spellId field in combat
- Slot-based access uses the same underlying data (same secrets)
- Combat log is NOT available (also restricted by secrets)
- Hardcoded whitelist filtering superseded by instance map approach

---

## Blizzard's AuraUtil Pattern (from BuffFrame.lua)

Blizzard uses `AuraUtil.ForEachAura()` with slot-based iteration internally:

```lua
-- From Blizzard_FrameXMLUtil/AuraUtil.lua
function AuraUtil.ForEachAura(unit, filter, batchSize, func, usePackedAura)
    local continuationToken
    repeat
        continuationToken = ForEachAuraHelper(unit, filter, func, usePackedAura, 
            C_UnitAuras.GetAuraSlots(unit, filter, batchSize, continuationToken))
    until continuationToken == nil
end
```

This uses `GetAuraSlots()` → `GetAuraDataBySlot()` internally, which may have different secret behavior than `GetAuraDataByIndex()`.

---

## Form/Stance Detection (ALWAYS SAFE)

Forms and stances use stance bar APIs which are **client-side UI state** and never restricted:

```lua
-- SAFE: Stance bar APIs don't use secrets
local function GetActiveFormInfo()
    local numForms = GetNumShapeshiftForms()
    for i = 1, numForms do
        local icon, active, castable, spellID = GetShapeshiftFormInfo(i)
        if active then
            return i, spellID, C_Spell.GetSpellName(spellID)
        end
    end
    return 0, nil, "Normal"
end

-- Check if a spell would shift to current form
local function IsAlreadyInForm(formSpellID)
    local activeFormIndex = GetActiveFormInfo()
    if activeFormIndex == 0 then return false end
    
    local _, _, _, activeSpellID = GetShapeshiftFormInfo(activeFormIndex)
    
    -- Direct match
    if activeSpellID == formSpellID then return true end
    
    -- Name-based match (handles spell ID variants)
    local targetName = C_Spell.GetSpellName(formSpellID)
    local activeName = C_Spell.GetSpellName(activeSpellID)
    return targetName and activeName and targetName == activeName
end
```

---

## Specialization Detection (ALWAYS SAFE)

```lua
-- SAFE: Spec APIs don't use secrets
local function GetCurrentSpec()
    local specIndex = GetSpecialization()
    if not specIndex then return nil, nil end
    
    local specID, specName = GetSpecializationInfo(specIndex)
    return specIndex, specName
end
```

---

## Pet Detection Strategy

Pet existence and dead state are safe, but health may be secret:

```lua
-- SAFE: These APIs don't have SecretWhen conditions
local function HasActivePet()
    return UnitExists("pet")
end

local function IsPetDead()
    if not UnitExists("pet") then return nil end
    return UnitIsDead("pet") or UnitIsDeadOrGhost("pet")
end

-- POTENTIALLY SECRET: Pet health
local function GetPetHealthSafe()
    if not UnitExists("pet") then return nil end
    
    local health = UnitHealth("pet")
    if issecretvalue and issecretvalue(health) then
        -- Fallback: use dead check as proxy
        return UnitIsDead("pet") and 0 or nil
    end
    return health
end
```

---

## Proc Glow Detection (ALWAYS SAFE)

The spell activation overlay system is separate from auras:

```lua
-- SAFE: Overlay system is client-side visual effects
local function IsSpellProccedOrGlowing(spellID)
    if not spellID then return false end
    
    -- Check for spell activation overlay (the glow effect)
    if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
        local isOverlayed = C_SpellActivationOverlay.IsSpellOverlayed(spellID)
        if isOverlayed then return true end
    end
    
    -- Also check action bar glow
    if IsSpellOverlayed and IsSpellOverlayed(spellID) then
        return true
    end
    
    return false
end
```

---

## Summary: Safe vs Potentially Secret APIs

### ✅ ALWAYS SAFE (use freely)
- `GetShapeshiftFormInfo()` / `GetNumShapeshiftForms()` / `GetShapeshiftFormID()`
- `GetSpecialization()` / `GetSpecializationInfo()`
- `UnitExists()` / `UnitIsDead()` / `UnitIsDeadOrGhost()`
- `C_Spell.GetSpellInfo()` / `C_Spell.GetSpellName()` / `C_Spell.GetOverrideSpell()`
- `C_SpellActivationOverlay.IsSpellOverlayed()`
- `GetWeaponEnchantInfo()`
- `GetActionInfo()` (action type/ID - but "assistedcombat" string needs filtering)

### ⚠️ CONDITIONALLY SAFE (check with C_Secrets first)
- `C_UnitAuras.GetPlayerAuraBySpellID()` - use `C_Secrets.ShouldSpellAuraBeSecret()`
- `C_UnitAuras.GetAuraDataBySpellName()` - same check
- `C_Spell.GetSpellCooldown()` - use `C_Secrets.ShouldSpellCooldownBeSecret()`
- `C_Spell.GetSpellCharges()` - same check

### ❌ OFTEN SECRET (use with caution)
- `C_UnitAuras.GetAuraDataByIndex()` - bulk iteration most restricted
- `UnitHealth("pet")` / `UnitHealthMax("pet")` - non-player health
- `GetComboPoints()` when querying hostile targets
