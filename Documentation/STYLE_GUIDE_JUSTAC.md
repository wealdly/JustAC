# JustAC Style Guide - AI Reference

**Version:** 2.5  
**Format:** AI-optimized for quick parsing and rule extraction  
**Addon:** WoW Assisted Combat Enhancement (JustAC)  
**Last Updated:** 2025-11-18

---

## Priority Levels

- **MUST** - Critical rules, violations break functionality or cause conflicts
- **SHOULD** - Important conventions, follow unless there's good reason
- **MAY** - Optional guidelines, use for consistency

---

## Quick Rules Summary

### Critical (MUST)
```
✓ All variables MUST be local unless explicitly global
✓ MUST use LibStub module registration pattern
✓ MUST use 4 spaces for indentation (no tabs)
✓ MUST wrap WoW API calls that can fail in pcall()
✓ MUST check module availability with LibStub("Module", true)
✓ MUST validate nil on all module retrievals and API calls
✓ MUST use early returns over deep nesting (max 3 levels)
✓ MUST filter "assistedcombat" string actionType from action bars
```

### Important (SHOULD)
```
✓ Functions SHOULD be lowercase-started to avoid WoW API conflicts
✓ Constants SHOULD use UPPER_SNAKE_CASE
✓ Variables SHOULD use camelCase (JustAC standard)
✓ Module names SHOULD use PascalCase
✓ SHOULD return early to reduce nesting
✓ SHOULD use trailing commas in multi-line tables
✓ SHOULD cache repeated table lookups in locals
✓ SHOULD use ipairs() for arrays, pairs() for dictionaries
✓ SHOULD cache expensive WoW API results (forms, bindings, macros)
✓ SHOULD invalidate caches on relevant events only
```

### Optional (MAY)
```
✓ MAY prefix private functions with local
✓ MAY use boolean prefixes (is/has/should/can)
✓ MAY use ternary-style and/or expressions for simple cases
```

---

## Module System (LibStub)

### Module Registration Pattern
```lua
-- MUST: Use at top of every module file
local ModuleName = LibStub:NewLibrary("JustAC-ModuleName", VERSION_NUMBER)
if not ModuleName then return end

-- Example from SpellQueue.lua
local SpellQueue = LibStub:NewLibrary("JustAC-SpellQueue", 12)
if not SpellQueue then return end
```

**Version Numbers:**
- Increment on breaking changes
- Used by LibStub to prevent loading old versions
- Current versions: BlizzardAPI=5, SpellQueue=12, ActionBarScanner=9, MacroParser=11, FormCache=5, UIManager=12

### Module Dependencies
```lua
-- MUST: Always check for nil with true parameter
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local FormCache = LibStub("JustAC-FormCache", true)

-- MUST: Validate before use
if not BlizzardAPI then return end
if not FormCache or not FormCache.GetActiveForm then return end

-- GOOD: Full safety pattern
local function getActiveForm()
    local FormCache = LibStub("JustAC-FormCache", true)
    if not FormCache or not FormCache.GetActiveForm then
        return 0
    end
    return FormCache.GetActiveForm()
end
```

### Module Structure
```lua
-- Standard module file structure:

-- 1. LibStub registration
local ModuleName = LibStub:NewLibrary("JustAC-ModuleName", VERSION)
if not ModuleName then return end

-- 2. Module dependencies
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

-- 3. File-local variables and caches
local cache = {}
local lastUpdate = 0

-- 4. Private helper functions
local function privateHelper()
end

-- 5. Public API functions
function ModuleName.PublicFunction()
end

-- 6. Optional: return module
return ModuleName
```

---

## Naming Conventions

### Variables
```lua
-- SHOULD: camelCase (JustAC standard)
local spellQueue = {}
local lastUpdate = 0
local cachedFormData = {}
local bindingKeyCache = {}

-- MUST: Constants in UPPER_SNAKE_CASE
local MAX_ACTION_SLOTS = 200
local NUM_ACTIONBAR_BUTTONS = 12
local CACHE_FLUSH_INTERVAL = 30

-- MAY: Prefix booleans
local isEnabled = true
local hasOverride = false
local canProcess = true
local bindingCacheValid = false
```

### Functions
```lua
-- SHOULD: Lowercase start for private functions
local function updateFormCache()
local function validateSpell(spellID)
local function getQueueThrottleInterval()

-- SHOULD: Module public API - PascalCase
function SpellQueue.GetCurrentSpellQueue()
function ActionBarScanner.GetSpellHotkey(spellID)
function BlizzardAPI.GetNextCastSpell()

-- SHOULD: Verb-based descriptive names
✓ getCachedSpellInfo()
✓ invalidateCache()
✓ isSpellBlacklisted()
✓ updateCachedState()

❌ spell()
❌ cache()
❌ blacklist()
❌ state()
```

### Modules
```lua
-- MUST: PascalCase with "JustAC-" prefix for LibStub
"JustAC-SpellQueue"
"JustAC-ActionBarScanner"
"JustAC-BlizzardAPI"
"JustAC-FormCache"
"JustAC-MacroParser"
"JustAC-UIManager"
"JustAC-RedundancyFilter"
```

---

## Formatting Rules

### Indentation
```lua
-- MUST: 4 spaces per level, no tabs
function myFunction()
    if condition then
        doSomething()
    end
end
```

### Spacing
```lua
-- MUST: Space after operators
local x = y + 5
local result = (a * b) / c

-- MUST: Space after commas
local t = {1, 2, 3}
myFunction(arg1, arg2, arg3)

-- MUST: Space around table braces (single line)
local config = { enabled = true }
local empty = {}

-- MUST NOT: Space between function name and parens
✓ myFunction(arg)
❌ myFunction (arg)

-- SHOULD: Space after -- in comments
-- Good comment
--Bad comment
```

### Line Length
```
SHOULD: Soft limit 100 characters
MUST: Hard limit 120 characters
```

---

## Caching Patterns (Critical for JustAC)

### Cache Invalidation Strategy
```lua
-- MUST: Every cache needs invalidation logic
local cache = {}
local cacheValid = false

function InvalidateCache()
    cacheValid = false
    wipe(cache)
end

function GetCachedData()
    if not cacheValid then
        RebuildCache()
    end
    return cache
end
```

### Time-Based Cache Flushing
```lua
-- SHOULD: Use for long-lived caches
local cache = {}
local lastCacheFlush = 0
local CACHE_FLUSH_INTERVAL = 30

function GetData()
    local now = GetTime()
    if now - lastCacheFlush > CACHE_FLUSH_INTERVAL then
        wipe(cache)
        lastCacheFlush = now
    end
    
    if not cache[key] then
        cache[key] = ExpensiveOperation()
    end
    return cache[key]
end
```

### Throttling Pattern
```lua
-- MUST: Use for high-frequency operations
local lastUpdate = 0

function Update()
    local now = GetTime()
    local throttleInterval = 0.03  -- 30fps max
    
    if now - lastUpdate < throttleInterval then
        return  -- Skip update
    end
    lastUpdate = now
    
    -- Do expensive work
end
```

### Cache Key Composition
```lua
-- SHOULD: Include all state dependencies
local cacheKey = slot .. "_" .. spellID .. "_" .. currentForm .. "_" .. currentSpec

-- BAD: Missing state dependency
❌ local cacheKey = slot .. "_" .. spellID  -- Breaks on form/spec change
```

---

## WoW API Safety Patterns

### pcall Wrapper Pattern
```lua
-- MUST: Wrap APIs that can fail
function BlizzardAPI.GetNextCastSpell()
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
        return nil
    end
    
    local success, result = pcall(C_AssistedCombat.GetNextCastSpell, true)
    if success and result and type(result) == "number" and result > 0 then
        return result
    end
    return nil
end
```

### Assisted Combat Special Case
```lua
-- MUST: Filter "assistedcombat" string actionType
local actionType, id = GetActionInfo(slot)

-- Check multiple ways
local isAssistantButton = (actionType == "spell" and type(id) == "string" and id == "assistedcombat")
local isAssistedCombatAction = C_ActionBar and C_ActionBar.IsAssistedCombatAction and C_ActionBar.IsAssistedCombatAction(slot)

if isAssistantButton or isAssistedCombatAction then
    return nil  -- Skip this slot
end
```

### Form Detection Pattern
```lua
-- SHOULD: Cache form data, validate on interval
local function UpdateFormCache()
    local now = GetTime()
    if cachedFormData.valid and (now - cachedFormData.lastUpdate) < 0.1 then
        return  -- Cache still valid
    end
    
    local formID = 0
    local numForms = GetNumShapeshiftForms()
    
    for i = 1, numForms do
        local icon, active = GetShapeshiftFormInfo(i)
        if active then
            formID = i
            break
        end
    end
    
    cachedFormData.currentFormID = formID
    cachedFormData.lastUpdate = now
    cachedFormData.valid = true
end
```

---

## Early Returns (Critical Rule)

```lua
-- MUST: Use early returns, max 3 nesting levels

-- GOOD: Early returns
function processSpell(spellID)
    if not spellID then return nil end
    if spellID == 0 then return nil end
    
    local spellInfo = GetSpellInfo(spellID)
    if not spellInfo then return nil end
    
    return processValidSpell(spellInfo)
end

-- BAD: Deep nesting
❌ function processSpell(spellID)
    if spellID then
        if spellID ~= 0 then
            local spellInfo = GetSpellInfo(spellID)
            if spellInfo then
                return processValidSpell(spellInfo)
            end
        end
    end
    return nil
end
```

---

## Common Patterns

### Module Function Call Pattern
```lua
-- SHOULD: Safe module function call
local function callModuleFunction(module, funcName, ...)
    local mod = LibStub(module, true)
    if not mod or not mod[funcName] then
        return nil
    end
    
    local success, result = pcall(mod[funcName], ...)
    if success then
        return result
    end
    return nil
end
```

### Addon Reference Pattern
```lua
-- SHOULD: Get addon reference safely
local function getAddonReference()
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if not addon then return nil end
    return addon
end

local function getProfile()
    local addon = getAddonReference()
    if not addon or not addon.db then return nil end
    return addon.db.profile
end
```

### Table Comparison Pattern
```lua
-- SHOULD: Compare spell arrays efficiently
function CompareSpellArrays(arr1, arr2)
    if arr1 == arr2 then return true end
    if not arr1 or not arr2 then return false end
    
    local len1, len2 = #arr1, #arr2
    if len1 ~= len2 then return false end
    if len1 == 0 then return true end
    
    for i = 1, len1 do
        if arr1[i] ~= arr2[i] then return false end
    end
    
    return true
end
```

---

## Comments

### Style
```lua
-- MUST: Space after --
-- Good comment
--Bad comment (no space)
```

### Purpose
```
SHOULD: Comment WHY, not WHAT
SHOULD: Comment complex logic
MUST: Comment WoW API workarounds
MUST NOT: Comment obvious code
MUST NOT: Comment Lua syntax
```

### Examples
```lua
-- GOOD: Explains WHY
-- Cache to avoid repeated API calls during combat
local playerName = UnitName("player")

-- GOOD: Documents workaround
-- GetShapeshiftFormID() returns nil in caster form, treat as 0
local formID = GetShapeshiftFormID() or 0

-- GOOD: Complex state tracking
-- Hash includes page, bonusOffset, form, and special bar flags
-- This invalidates when ANY of these change
local hash = page + (bonusOffset * 100) + (formID * 10000)

-- BAD: Obvious
❌ local playerName = UnitName("player")  -- Get player name
```

### Function Documentation
```lua
-- SHOULD: Document public API
-- Gets the current spell queue with filters applied
-- @param ignoreBlacklist bool - Skip blacklist filtering
-- @return table - Array of spell IDs
function SpellQueue.GetCurrentSpellQueue(ignoreBlacklist)
```

---

## Performance Rules

### Cache Expensive Operations
```lua
-- MUST: Cache GetMacroInfo, GetBindingKey, GetShapeshiftFormInfo
-- These are expensive and called frequently

-- GOOD
local bindingCache = {}
function getCachedBinding(key)
    if not bindingCache[key] then
        bindingCache[key] = GetBindingKey(key) or ""
    end
    return bindingCache[key]
end

-- BAD
❌ function getBinding(key)
    return GetBindingKey(key)  -- Called every frame!
end
```

### Avoid Function Creation in Loops
```lua
-- BAD
❌ for i = 1, 100 do
    C_Timer.After(i, function() print(i) end)  -- Creates 100 closures
end

-- GOOD
local function printNumber(n)
    print(n)
end

for i = 1, 100 do
    C_Timer.After(i, function() printNumber(i) end)
end
```

### Use table.concat for Large Strings
```lua
-- BAD: Repeated concatenation
❌ local result = ""
   for i = 1, 1000 do
       result = result .. tostring(i) .. ", "
   end

-- GOOD: table.concat
✓ local parts = {}
  for i = 1, 1000 do
      parts[i] = tostring(i)
  end
  local result = table.concat(parts, ", ")
```

---

## Anti-Patterns (JustAC-Specific)

### DON'T: Call GetRotationSpells Every Frame
```lua
-- BAD: Called 30 times per second in combat!
❌ function OnUpdate()
    local spells = C_AssistedCombat.GetRotationSpells()
    DisplaySpells(spells)
end

-- GOOD: Cache and invalidate on SPELLS_CHANGED
✓ local cachedRotation = {}
  local rotationValid = false
  
  function OnSpellsChanged()
      rotationValid = false
  end
  
  function GetRotation()
      if not rotationValid then
          cachedRotation = C_AssistedCombat.GetRotationSpells()
          rotationValid = true
      end
      return cachedRotation
  end
```

### DON'T: Process Assistant Button
```lua
-- BAD: Tries to get hotkey for dynamic button
❌ local actionType, id = GetActionInfo(slot)
   if actionType == "spell" then
       return GetHotkeyForSpell(id)
   end

-- GOOD: Filter assistant button first
✓ local actionType, id = GetActionInfo(slot)
  if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
      return nil  -- Skip
  end
  if C_ActionBar.IsAssistedCombatAction(slot) then
      return nil  -- Double-check
  end
```

### DON'T: Deep Nesting
```lua
-- BAD: 4+ levels of nesting
❌ function process(data)
    if data then
        if data.spellID then
            if data.spellID > 0 then
                if IsSpellKnown(data.spellID) then
                    return true
                end
            end
        end
    end
    return false
end

-- GOOD: Early returns
✓ function process(data)
    if not data then return false end
    if not data.spellID then return false end
    if data.spellID <= 0 then return false end
    if not IsSpellKnown(data.spellID) then return false end
    return true
end
```

### DON'T: Unbounded Cache Growth
```lua
-- BAD: Cache grows forever
❌ local spellCache = {}
   function cacheSpell(id)
       if not spellCache[id] then
           spellCache[id] = GetSpellInfo(id)
       end
   end

-- GOOD: Limit cache size
✓ local spellCache = {}
  local cacheSize = 0
  local MAX_CACHE_SIZE = 100
  
  function cacheSpell(id)
      if not spellCache[id] then
          if cacheSize >= MAX_CACHE_SIZE then
              wipe(spellCache)
              cacheSize = 0
          end
          spellCache[id] = GetSpellInfo(id)
          cacheSize = cacheSize + 1
      end
  end
```

---

## Event Handling Patterns

### Standard Event Registration
```lua
-- Core addon uses AceEvent
self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser:InvalidateMacroCache()
    end
    self:ForceUpdate()
end)
```

### Module Event Pattern
```lua
-- Modules export functions called by core
function FormCache.OnPlayerLogin()
    UpdateFormCache()
    ScanSpellbookForFormSpells()
end

function ActionBarScanner.OnUIChanged()
    InvalidateStateCache()
    InvalidateKeybindCache()
end
```

---

## Testing Patterns

### Debug Mode Check
```lua
-- SHOULD: Use consistent debug mode check
local function getDebugMode()
    local addon = LibStub("AceAddon-3.0"):GetAddon("JustAssistedCombat", true)
    if not addon or not addon.db or not addon.db.profile then
        return false
    end
    return addon.db.profile.debugMode or false
end

-- Usage
local debugMode = getDebugMode()
if debugMode then
    print("|cJAC| Cache invalidated:", cacheName)
end
```

### Verification Commands
```lua
-- SHOULD: Add debug commands for complex systems
-- /jac test        -- Full API diagnostics
-- /jac modules     -- Module health check
-- /jac formcheck   -- Form detection debug
-- /jac raw         -- Show raw spell queue
-- /jac find <name> -- Locate spell on bars
```

---

## Constants Reference

### Timing Constants
```lua
0.03  -- Combat queue throttle (30fps)
0.08  -- Out-of-combat queue throttle (12.5fps)
0.1   -- Form cache validation interval
0.2   -- Keybind change debounce
30    -- Macro/spell override cache flush
```

### Slot Constants
```lua
MAX_ACTION_SLOTS = 200
NUM_ACTIONBAR_BUTTONS = 12
```

### User Limits
```lua
maxIcons: 1-7      -- Spell icons displayed
iconSize: 20-64    -- Icon size in pixels
```

---

## Module Checklist

When creating or editing a module, verify:

```
□ LibStub registration with version number
□ Early return if module already loaded
□ Module dependencies checked with true parameter
□ All variables declared local
□ Public functions use ModuleName.FunctionName
□ Private functions use local function
□ Constants in UPPER_SNAKE_CASE
□ Variables in camelCase
□ Early returns used (max 3 nesting levels)
□ WoW API calls wrapped in pcall when needed
□ Caches have invalidation strategy
□ Expensive operations cached
□ Comments explain WHY not WHAT
□ Debug mode printing available
```

---

## Code Review Checklist

```
□ Module registered with LibStub
□ Dependencies checked for nil
□ All variables declared local
□ 4-space indentation (no tabs)
□ Descriptive function names
□ Constants in UPPER_SNAKE_CASE
□ Trailing commas in multi-line tables
□ Spaces around operators
□ Space after commas
□ Space after -- in comments
□ Comments explain WHY not WHAT
□ Public functions documented
□ WoW API calls wrapped in pcall
□ Early returns used
□ No function creation in loops
□ Table lookups cached
□ ipairs for arrays, pairs for dicts
□ Caches have limits/invalidation
□ Assisted combat action filtered
□ Debug mode checks present
```

---

## Quick Don't/Do Reference

```lua
-- Module registration
❌ local MyModule = {}
✓ local MyModule = LibStub:NewLibrary("JustAC-MyModule", 1)
  if not MyModule then return end

-- Module dependencies
❌ local Other = LibStub("JustAC-Other")  -- Errors if missing
✓ local Other = LibStub("JustAC-Other", true)  -- Returns nil if missing

-- Nil checking
❌ if BlizzardAPI.GetSpell() then
✓ if BlizzardAPI and BlizzardAPI.GetSpell and BlizzardAPI.GetSpell() then

-- Nesting
❌ if a then
       if b then
           if c then
✓ if not a then return end
  if not b then return end
  if not c then return end

-- API safety
❌ local spell = C_AssistedCombat.GetNextCastSpell(true)
✓ local success, spell = pcall(C_AssistedCombat.GetNextCastSpell, true)
  if not success or not spell then return nil end

-- Caching
❌ function update()
       local spells = C_AssistedCombat.GetRotationSpells()  -- Every frame!
✓ local cachedSpells = {}
  local spellsValid = false
  function update()
      if not spellsValid then
          cachedSpells = C_AssistedCombat.GetRotationSpells()
          spellsValid = true
      end

-- Assistant button
❌ local type, id = GetActionInfo(slot)  -- id might be "assistedcombat" string!
✓ local type, id = GetActionInfo(slot)
  if type == "spell" and type(id) == "string" and id == "assistedcombat" then
      return nil
  end
```

---

## Version History

- **2.5** (2025-11-18): Initial JustAC-specific style guide

---

**Usage Note:** This guide is optimized for AI agent development working on JustAC. Always verify WoW API behavior with `/script` commands before implementation.
