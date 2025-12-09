# Version Conditional Code Patterns

Guide for adding version-specific code paths for WoW 12.0 (Midnight) compatibility.

## Quick Reference

```lua
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- Get current version number
local version = BlizzardAPI.GetInterfaceVersion()  -- Returns: 110207, 120000, etc.

-- Check if 12.0 or later
if BlizzardAPI.IsMidnightOrLater() then
    -- 12.0+ code path
else
    -- Pre-12.0 code path
end
```

## Pattern 1: Simple Conditional Branch

When API behavior changes between versions:

```lua
local function GetSpellData(spellID)
    if BlizzardAPI.IsMidnightOrLater() then
        -- 12.0: New API with different return signature
        local info = C_Spell.GetSpellInfo(spellID)
        return info.name, info.iconID
    else
        -- Pre-12.0: Old API
        local name, _, iconID = GetSpellInfo(spellID)
        return name, iconID
    end
end
```

## Pattern 2: Version-Aware Function Wrapper

Using `VersionCall()` helper for cleaner code:

```lua
-- Define version-specific implementations
local function GetAura_Pre12(unit, index)
    return UnitAura(unit, index, "HELPFUL")
end

local function GetAura_Post12(unit, index)
    return C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
end

-- Call the appropriate version
local function SafeGetAura(unit, index)
    return BlizzardAPI.VersionCall(GetAura_Pre12, GetAura_Post12, unit, index)
end
```

## Pattern 3: Hot Path Optimization

Cache version check result to avoid repeated lookups:

```lua
-- At module load time (top of file)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local IS_MIDNIGHT = BlizzardAPI and BlizzardAPI.IsMidnightOrLater() or false

-- In hot path function
local function ProcessSpells(spells)
    for i = 1, #spells do
        if IS_MIDNIGHT then
            -- 12.0 fast path
            ProcessSpell_v12(spells[i])
        else
            -- Pre-12.0 fast path
            ProcessSpell_v11(spells[i])
        end
    end
end
```

## Pattern 4: API Availability Check + Version

When API might not exist in older versions:

```lua
local function GetCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        -- Modern API (11.0+)
        if BlizzardAPI.IsMidnightOrLater() then
            -- 12.0: Handle secrets in cooldown data
            local info = C_Spell.GetSpellCooldown(spellID)
            if info and not issecretvalue(info.startTime) then
                return info.startTime, info.duration
            end
            return nil, nil  -- Secret value detected
        else
            -- 11.x: No secrets yet
            local info = C_Spell.GetSpellCooldown(spellID)
            return info.startTime, info.duration
        end
    else
        -- Fallback for ancient clients
        return GetSpellCooldown(spellID)
    end
end
```

## Pattern 5: Conditional Constants

When constants change between versions:

```lua
local SPELL_FLAGS = {}
if BlizzardAPI.IsMidnightOrLater() then
    SPELL_FLAGS.HARMFUL = 0x00008000  -- 12.0 value
    SPELL_FLAGS.HELPFUL = 0x00004000
else
    SPELL_FLAGS.HARMFUL = 0x00010000  -- Pre-12.0 value
    SPELL_FLAGS.HELPFUL = 0x00008000
end
```

## Pattern 6: Gradual Migration

When fixing a specific error:

```lua
local function ParseMacro(macroText)
    -- BEFORE: This crashes in 12.0
    -- local tokens = string.split(macroText, ";")
    
    -- AFTER: Version-aware fix
    if BlizzardAPI.IsMidnightOrLater() then
        -- 12.0: string.split removed, use gmatch
        local tokens = {}
        for token in string.gmatch(macroText, "[^;]+") do
            table.insert(tokens, token)
        end
        return tokens
    else
        -- Pre-12.0: Original code works fine
        return {string.split(macroText, ";")}
    end
end
```

## Where to Add Version Conditionals

### RedundancyFilter.lua
- Aura detection changes (if C_UnitAuras behavior changes)
- Buff/debuff filtering (if categories change)

### ActionBarScanner.lua
- Action slot mapping (if bar layout changes)
- Keybind detection (if binding API changes)

### MacroParser.lua
- Conditional parsing (if macro syntax changes)
- String manipulation (if Lua string lib changes)

### SpellQueue.lua
- Spell categorization (if flags change)
- Proc detection (if overlay API changes)

### UIManager.lua
- Frame creation (if frame API changes)
- Animation (if animation API changes)

## Testing Your Changes

After adding version conditionals:

1. **Test in 11.2.7** (current retail):
   ```
   /jac test
   /jac modules
   ```

2. **Test in 12.0** (beta):
   ```
   /jac test
   /jac modules
   ```

3. **Verify version detection**:
   ```lua
   /dump BlizzardAPI.GetInterfaceVersion()  -- Should show 110207 or 120000
   /dump BlizzardAPI.IsMidnightOrLater()    -- Should show false or true
   ```

## Commit Message Template

When adding version conditionals for a specific error:

```
v3.xx: Fix [error description] in WoW 12.0

- Add version conditional for [specific API/function]
- 12.0 path: [what the new code does]
- Pre-12.0 path: [original behavior preserved]
- Fixes error: [paste error message]
```

## Important Notes

1. **Always preserve pre-12.0 behavior** - Don't break current retail
2. **Test both paths** - Even if you don't have 12.0, verify 11.x still works
3. **Document assumptions** - Add comments explaining why version check is needed
4. **Keep it simple** - Only add conditionals when APIs actually differ
5. **Cache version checks** - Don't call `IsMidnightOrLater()` in hot paths

## Example: Real World Fix

```lua
-- ERROR in 12.0: "attempt to call field 'GetOverrideSpell' (a nil value)"
-- CAUSE: C_Spell.GetOverrideSpell removed in 12.0

local function GetDisplaySpell(baseSpellID)
    if BlizzardAPI.IsMidnightOrLater() then
        -- 12.0: Use new SpecializationInfo API
        if C_ClassTalents and C_ClassTalents.GetActiveSpecOverride then
            return C_ClassTalents.GetActiveSpecOverride(baseSpellID) or baseSpellID
        end
        return baseSpellID  -- No override available
    else
        -- Pre-12.0: Original API
        if C_Spell and C_Spell.GetOverrideSpell then
            return C_Spell.GetOverrideSpell(baseSpellID) or baseSpellID
        end
        return baseSpellID
    end
end
```

## Next Steps

When you encounter a 12.0 error:

1. **Identify the failing API** - Read the error message carefully
2. **Check if it's version-specific** - Does it work in 11.2.7?
3. **Add version conditional** - Use one of the patterns above
4. **Test both paths** - Verify fix works, doesn't break 11.x
5. **Document the change** - Update CHANGELOG and commit message
