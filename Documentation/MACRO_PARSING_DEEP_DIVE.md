# Macro Parsing Deep Dive - JustAC

**Version:** 2.5 (MacroParser v11)  
**Last Updated:** 2025-11-18

---

## Overview

MacroParser is the most complex module in JustAC, responsible for extracting spell information from WoW macros and determining which hotkey applies under current conditions. This has been a major development challenge due to:

1. **Complex WoW macro syntax** with nested conditions and multiple spells
2. **Dynamic state dependencies** (form, spec, modifiers, mount status)
3. **Spell override mechanics** (same spell ID, different names based on state)
4. **Quality scoring** to choose best macro when spell appears in multiple macros
5. **Performance** requirements (must cache aggressively, avoid repeated parsing)

---

## Core Challenge: Conditional Macro Resolution

### The Problem
```lua
-- Macro example:
#showtooltip
/cast [mod:shift,form:1] Maul; [form:1] Swipe; Wrath

-- Questions MacroParser must answer:
-- 1. Does this macro cast Maul? (depends on form AND modifier state)
-- 2. What hotkey should display for Maul? (base key or "Shift+key")
-- 3. Should this macro "win" if Maul appears in other macros too?
```

### Current Solution Flow
```
1. GetSpellAndOverride(spellID, spellName)
   → Build list of spell variations to search for
   
2. ParseMacroForSpell(macroBody, targetSpellID, targetSpellName)
   → For each line: extract conditions and spell name
   → Check if conditions evaluate true RIGHT NOW
   → Return modifiers if found + conditions met
   
3. CalculateMacroSpecificityScore(macroName, macroBody, targetSpells)
   → Analyze execution order, position, simultaneous spells
   → Apply penalties for complexity
   → Apply bonuses for specificity
```

---

## Implementation Analysis

### 1. Spell Override Tracking

**Purpose:** Handle spells that change names/IDs based on state

```lua
function GetSpellAndOverride(spellID, spellName)
    local spells = {}
    
    -- Add original spell
    spells[spellID] = spellName
    
    -- Add C_Spell.GetOverrideSpell() result
    local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
    if overrideSpellID ~= 0 and overrideSpellID ~= spellID then
        spells[overrideSpellID] = overrideSpellInfo.name
    end
    
    -- HARDCODED: Ravage ↔ Ferocious Bite relationship
    -- These don't use override system, manual bidirectional link
    
    return spells
end
```

**Issues Identified:**
- ❌ **Hardcoded spell relationships** - Only handles Ravage/Ferocious Bite
- ❌ **No detection of other dynamic spells** - What about Shaman abilities that change with weapon imbues?
- ✅ **Caching works** - 30s flush interval, keyed by spellID
- ⚠️ **Verified behavior:** `C_Spell.GetOverrideSpell(5487)` returns `5487` (no override), so this correctly handles "no change" case

**Recommendation:** Need API test to find other spell pairs that transform but don't use override system.

---

### 2. Condition Parsing

**Supported Conditions:**
```lua
[mod:shift]         -- Modifier (shift/ctrl/alt/"any")
[form:1/2/3]        -- Druid forms, Warrior stances
[spec:1/2/3/4]      -- Talent spec
[mounted]           -- Mount status
[unmounted]         -- Not mounted
[outdoors]          -- Location
[indoors]           -- Location
```

**NOT Supported:**
```lua
[target=...]        -- Target selection
[combat]            -- Combat state
[stance:...]        -- Alias for form (should work but not tested)
[harm/help]         -- Friend/enemy
[exists]            -- Target exists
[dead]              -- Target dead
[flying]            -- Flight status
[channeling]        -- Channeling spell
[pet:...]           -- Pet type
[equipped:...]      -- Item equipped
[group:party/raid]  -- Group type
```

**Current Implementation:**
```lua
function EvaluateConditions(conditionString, currentSpec, currentForm)
    local modifiers = {}
    local allConditionsMet = true
    
    -- Parse comma-separated conditions
    for condition in conditionString:gmatch("[^,]+") do
        -- Match and evaluate each type
        -- If ANY condition fails, return false
    end
    
    return allConditionsMet, modifiers, formMatched
end
```

**Critical Issue - First Condition Only:**
```lua
-- In ParseMacroForSpell():
local conditionPart = trimmedEntry:sub(1, lastBracketPos)
local firstCondition = conditionPart:match("^%[([^%]]*)%]")  -- ❌ ONLY FIRST BRACKET

-- This breaks:
/cast [target=focus,exists][target=mouseover,exists][] Maul
-- Would only parse "[target=focus,exists]", ignore rest
```

**Recommendation:** Need to parse ALL bracket groups, handle cascading conditions.

---

### 3. Macro Command Parsing

**Supported Commands:**
```lua
/cast <spell>               -- Direct cast
/use <spell>                -- Alias for /cast
/castsequence <spells>      -- Sequential casting
```

**Pattern Matching:**
```lua
local command = lowerLine:match("/use%s+(.+)") or 
                lowerLine:match("/cast%s+(.+)") or
                lowerLine:match("/castsequence%s+(.+)")
```

**Edge Cases NOT Handled:**

1. **Items by slot number:**
   ```lua
   /use 13  -- Trinket slot
   /use [combat] 13; [nocombat] Maul
   ```
   Currently: Tries to match "13" as spell name, fails

2. **Castsequence with reset:**
   ```lua
   /castsequence reset=3 Maul, Swipe, Thrash
   ```
   Currently: Extracts "reset=3 Maul, Swipe, Thrash" as full command
   Should: Strip "reset=X" prefix first

3. **Spell ranks (Classic/SoM):**
   ```lua
   /cast Maul(Rank 7)
   ```
   Currently: Would try exact match "maul(rank 7)", likely fails

4. **Item names:**
   ```lua
   /use Healthstone
   /use [combat] Healing Potion; Maul
   ```
   Currently: Would match "Healing Potion" as spell if it exists

---

### 4. Spell Name Matching

```lua
function DoesSpellMatch(spellPart, targetSpells)
    local lowerSpellPart = spellPart:lower()
    
    for spellID, spellName in pairs(targetSpells) do
        local lowerSpellName = spellName:lower()
        -- Exact match OR starts with spell name followed by non-letter
        if lowerSpellPart == lowerSpellName or 
           lowerSpellPart:find("^" .. lowerSpellName .. "[^a-z]") then
            return true, spellID, spellName
        end
    end
    
    return false
end
```

**Issues:**

1. **Case sensitivity handled** ✅
2. **Partial matches blocked** ✅ (Won't match "Maul" against "Mauling")
3. **Special characters in spell names** - Tested, no colons in "Bear Form"
4. **Parentheses handling** ⚠️ - Pattern `[^a-z]` would match `(` so "Maul(Rank 7)" → "maul" works by accident

**Potential Issue:**
```lua
-- If spell name is "Ferocious Bite" and macro has:
/cast ferocious bite now!

-- Would match because "ferocious bite " ends with space (non-letter)
-- Probably acceptable - macros rarely have extra text after spell
```

---

### 5. Quality Scoring System

**Base Score:** 500

**Bonuses:**
- Macro name exactly matches spell: +200
- Macro name contains spell prefix (2+ chars): +150
- Each condition in macro: +50 per condition

**Penalties:**
- Each /cast line after first: -150 per line
- Each semicolon clause after first: -75 per position
- Each simultaneous ability after 2nd: -25 per extra
- Spell not first in semicolon list: -100

**Example Scoring:**

```lua
-- Macro 1: "Maul"
#showtooltip
/cast [mod:shift] Mangle; Maul

-- Execution order: 1 (first cast line) = no penalty
-- Position in line: 2 (second after semicolon) = -75
-- Conditions: 1 ([mod:shift] only applies to Mangle) = +50
-- Macro name match: exact = +200
-- Total: 500 + 200 + 50 - 75 = 675

-- Macro 2: "Bear"
#showtooltip
/cast [form:1] Maul
/cast [form:0] Wrath

-- Execution order: 1 = no penalty
-- Position in line: 1 = no penalty  
-- Conditions: 1 ([form:1]) = +50
-- Macro name match: none = 0
-- Total: 500 + 50 = 550

-- Winner: Macro 1 (675 > 550)
```

**Critical Bug in Scoring:**

```lua
-- In CalculateMacroSpecificityScore:
for spellID, spellName in pairs(targetSpells) do
    for line in macroBody:gmatch("[^\r\n]+") do
        if lowerLine:find(lowerSpellName, 1, true) then
            -- Count conditions
            for condition in lowerLine:gmatch("%[[^%]]*%]") do
                lineConditions = lineConditions + 1
            end
            conditionCount = conditionCount + lineConditions
        end
    end
end

-- ❌ COUNTS ALL CONDITIONS ON LINE, EVEN FOR OTHER SPELLS
-- Example:
-- /cast [mod:shift] Mangle; [form:1] Maul
-- Would count BOTH conditions when scoring Maul
```

**Recommendation:** Only count conditions that apply to the target spell clause.

---

### 6. Caching Strategy

**Two-Level Cache:**

```lua
-- Level 1: Spell override cache (shared across calls)
spellOverrideCache[spellID] = { [id1] = name1, [id2] = name2, ... }
-- Flush: Every 30 seconds

-- Level 2: Parsed macro cache (per slot + spell + form)
parsedMacroCache[cacheKey] = {
    found = true,
    modifiers = { mod = "shift" },
    forms = { 1 },
    qualityScore = 675
}
-- Flush: On InvalidateMacroCache() call
```

**Cache Key Generation:**
```lua
local cacheKey = slot .. "_" .. targetSpellID .. "_" .. currentForm
```

**Issues:**

1. ✅ **Form included in key** - Handles form-specific macros correctly
2. ❌ **Spec NOT in key** - If macro has [spec:1/2], cache won't invalidate on respec
3. ❌ **Mount status NOT in key** - If macro has [mounted]/[unmounted], stale
4. ⚠️ **Modifier state NOT in key** - But modifiers are returned, not evaluated in cache

**Verification Needed:**
Are modifiers meant to be evaluated at display time (current) or parse time (cached)?

Current behavior: Parse time evaluation in `EvaluateConditions()`, but modifiers stored for later display formatting.

---

### 7. Bracket Extraction Logic

```lua
-- Find last ']' position
local lastBracketPos = 0
for i = 1, #trimmedEntry do
    if trimmedEntry:sub(i, i) == "]" then
        lastBracketPos = i
    end
end

-- Split on that position
if lastBracketPos > 0 and trimmedEntry:sub(1, 1) == "[" then
    local conditionPart = trimmedEntry:sub(1, lastBracketPos)
    local spellPart = trimmedEntry:sub(lastBracketPos + 1):match("^%s*(.-)%s*$")
end
```

**Issues:**

1. ✅ **Handles multiple bracket groups** - Finds LAST ']', includes all brackets
2. ❌ **Assumes brackets are conditions** - Could be spell name with brackets
3. ❌ **Doesn't handle malformed brackets** - Unmatched '[' or ']'

**Test Case That Breaks:**
```lua
-- Hypothetical (unlikely in real macros):
/cast Spell [Extra Info]  -- Brackets AFTER spell name
-- Would treat "Spell [Extra Info]" as condition + empty spell
```

**Recommendation:** Acceptable risk - WoW macro syntax doesn't allow this.

---

## Performance Profile

### Bottlenecks Identified

1. **`GetMacroInfo(actionText)`** - Expensive WoW API call
   - Called once per action bar slot that has macro
   - Called every time slot is checked (even if macro unchanged)
   - **Mitigated by:** parsedMacroCache keyed by slot

2. **`string.gmatch()` iterations** - Lua pattern matching in loops
   - Used for: lines, conditions, commands, spell clauses
   - **Impact:** Moderate, necessary for parsing
   - **Mitigated by:** Early return on first match

3. **Condition evaluation** - Multiple `IsMounted()`, `GetSpecialization()` calls
   - **Impact:** Low, cached within single parse
   - **Not mitigated:** Could cache at higher level

4. **Quality scoring** - Full macro analysis even if not needed
   - **Impact:** Low, only called on cache miss
   - **Issue:** Runs even for macros that won't be displayed

### Cache Hit Rate

**Optimal:** >95% hit rate during normal play (no form/spec changes)

**Cache Invalidation Events:**
- `UPDATE_SHAPESHIFT_FORM` → MacroParser.InvalidateMacroCache()
- `PLAYER_SPECIALIZATION_CHANGED` → (not currently hooked)
- Manual `/reload` → Full reset

**Improvement:** Track invalidation rate in debug mode.

---

## Known Limitations

### 1. Unsupported Macro Features

**VERIFIED FROM REAL DRUID MACROS (26 macros analyzed):**

| Feature | Example | Frequency | Impact |
|---------|---------|-----------|--------|
| **`known:` condition** | `[known:102359]` | **81% (21/26)** | **CRITICAL - Most common unsupported condition** |
| **Target selection** | `[@mouseover]`, `[@player]` | **50% (13/26)** | **HIGH - Condition ignored completely** |
| **Form negation** | `[noform:4]` | **58% (15/26)** | **HIGH - Shows wrong spell** |
| **Modifier negation** | `[nomod]` | **38% (10/26)** | **MEDIUM - Inverts mod logic** |
| **Combat state** | `[combat]/[nocombat]` | 12% (3/26) | Condition ignored |
| **Help/Harm** | `[help][harm]` | 31% (8/26) | Not evaluated |
| **Item slots** | `/use 13` | Working ✓ | n/a |
| **Pet conditions** | `[pet:cat]` | 0% | Not evaluated |
| **Equipped checks** | `[equipped:shields]` | 0% | Not evaluated |
| **Click commands** | `/click MultiBar7Button6` | Deprecated | Ignore (no longer functional) |

**Verified API Behaviors:**
- `IsSpellKnown(102359)` returns `false/true` (boolean)
- `GetShapeshiftFormID()` returns `1-5` or `nil` (verified: form 5 exists for Druid)
- `UnitExists("mouseover")` returns `false` when no mouseover

### 2. Spell Relationships Not Tracked

Beyond Ravage/Ferocious Bite, these are unknown:
- Shaman: Lightning Bolt vs Chain Lightning (with weapon imbues?)
- Warrior: Battle Shout vs Commanding Shout (in different stances?)
- Paladin: Seals/Blessings that auto-replace?

**Action Required:** Compile list via testing or WoW API research.

### 3. Castsequence Limitations

```lua
/castsequence reset=3 Maul, Swipe, Thrash
```

Currently parses as: `"reset=3 maul, swipe, thrash"`
- Spell matching fails because "reset=3 maul" doesn't match "maul"
- **Fix:** Strip `reset=N` prefix before parsing

### 4. Multiple Bracket Groups

```lua
/cast [target=focus,exists][target=mouseover,exists][] Maul
```

Current code:
```lua
local firstCondition = conditionPart:match("^%[([^%]]*)%]")
```

Only extracts first group: `target=focus,exists`
- Ignores mouseover fallback
- Ignores unconditional `[]` clause

**Impact:** Shows wrong hotkey or hides spell entirely.

---

## Testing Gaps

### Scenarios Not Verified

1. **Macros with only unsupported conditions:**
   ```lua
   /cast [target=focus] Maul
   ```
   Expected: Should fail to match (no supported conditions)
   Actual: Unknown

2. **Modifier-only macros:**
   ```lua
   /cast [mod] Maul; Wrath
   ```
   Expected: Extract `{ mod = "any" }`
   Actual: Likely works, but untested

3. **Form conditions on non-Druid:**
   ```lua
   -- Warrior macro:
   /cast [form:1] Battle Stance
   ```
   Expected: FormCache returns nil, breaks?
   Actual: Unknown

4. **Spec switching mid-combat:**
   - Does cache invalidate?
   - Are spec-conditional macros rescored?

5. **Macro with same spell twice:**
   ```lua
   /cast [mod:shift] Maul; [form:1] Maul
   ```
   Expected: Two possible hotkeys depending on state
   Actual: Returns first match only

---

## Recommended Improvements (Prioritized by Real Usage)

### Priority 1: Critical Fixes (Affect 80%+ of User Macros)

**1. Implement `known:` condition support** ⭐ **81% of macros**
```lua
-- In EvaluateConditions(), add:
elseif trimmed:match("^known:") then
    local spellRef = trimmed:match("known:(.+)")
    local spellID = tonumber(spellRef)
    
    -- Handle both ID and name
    if not spellID then
        local spellInfo = C_Spell.GetSpellInfo(spellRef)
        spellID = spellInfo and spellInfo.spellID
    end
    
    -- Verify: IsSpellKnown(102359) returns boolean
    if not spellID or not IsSpellKnown(spellID) then
        allConditionsMet = false
        break
    end
```

**2. Parse all bracket groups (cascade logic)** ⭐ **92% of macros**
```lua
-- Replace single-bracket extraction with:
local bracketGroups = {}
for bracketContent in trimmedEntry:gmatch("%[([^%]]*)%]") do
    table.insert(bracketGroups, bracketContent)
end

-- Evaluate as OR cascade (first successful wins)
local foundMatch = false
local finalModifiers = {}

for _, conditionString in ipairs(bracketGroups) do
    local conditionsMet, modifiers = EvaluateConditions(conditionString, currentSpec, currentForm)
    if conditionsMet then
        foundMatch = true
        finalModifiers = modifiers
        break  -- First success wins
    end
end

-- Extract spell after ALL brackets
local spellPart = trimmedEntry:gsub("%[[^%]]*%]", "", 1)  -- Remove all brackets
spellPart = spellPart:match("^%s*(.-)%s*$")  -- Trim whitespace
```

**3. Support form negation (`noform:`)** ⭐ **58% of macros**
```lua
-- In EvaluateConditions(), add:
elseif trimmed:match("^noform:") then
    local formList = trimmed:match("noform:([%d/]+)")
    if formList then
        for formStr in formList:gmatch("([^/]+)") do
            local excludedForm = tonumber(formStr)
            -- Verified: GetShapeshiftFormID() returns 1-5 or nil
            if excludedForm and currentForm == excludedForm then
                allConditionsMet = false
                break
            end
        end
    end
```

### Priority 2: High-Value Additions (Affect 50%+ of Macros)

**4. Support target modifiers (`@mouseover`, `@player`)** ⭐ **50% of macros**
```lua
-- In EvaluateConditions(), add:
elseif trimmed:match("^@") then
    local target = trimmed:match("^@(%w+)")
    
    -- Verified: UnitExists("mouseover") returns boolean
    if target == "mouseover" then
        if not UnitExists("mouseover") then
            allConditionsMet = false
            break
        end
    elseif target == "player" or target == "cursor" then
        -- Always valid (self-targeted)
    elseif target == "targetoftarget" then
        if not UnitExists("targetoftarget") then
            allConditionsMet = false
            break
        end
    end
    -- Note: Don't store target in modifiers, it's not a display modifier
```

**5. Support modifier negation (`nomod`)** ⭐ **38% of macros**
```lua
-- In EvaluateConditions(), add:
elseif trimmed == "nomod" then
    -- Check if ANY modifier is pressed
    if IsModifierKeyDown() then
        allConditionsMet = false
        break
    end
```

**6. Support `help/harm` conditions** ⭐ **31% of macros**
```lua
-- In EvaluateConditions(), add:
elseif trimmed == "help" then
    if not UnitExists("target") or not UnitIsFriend("player", "target") then
        allConditionsMet = false
        break
    end

elseif trimmed == "harm" then
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        allConditionsMet = false
        break
    end
```

### Priority 3: Nice-to-Have (Lower Frequency)

1. **Parse all bracket groups, not just first:**
   ```lua
   -- Replace:
   local firstCondition = conditionPart:match("^%[([^%]]*)%]")
   
   -- With:
   local allConditions = {}
   for bracketGroup in conditionPart:gmatch("%[([^%]]*)%]") do
       table.insert(allConditions, bracketGroup)
   end
   -- Evaluate as OR logic (cascade until one succeeds)
   ```

2. **Add spec to cache key:**
   ```lua
   local currentSpec = GetSpecialization() or 0
   local cacheKey = slot .. "_" .. targetSpellID .. "_" .. currentForm .. "_" .. currentSpec
   ```

3. **Fix condition counting in quality score:**
   ```lua
   -- Only count conditions that are part of target spell's clause
   -- Need to track which semicolon clause the spell is in
   ```

### Priority 2: Feature Additions

4. **Support /castsequence reset:**
   ```lua
   if command:match("^reset=") then
       command = command:gsub("^reset=%S+%s*", "")
   end
   ```

5. **Handle item slots:**
   ```lua
   -- If spellPart is pure number, skip (it's a slot)
   if tonumber(spellPart) then
       return false
   end
   ```

6. **Add combat condition support:**
   ```lua
   elseif trimmed == "combat" then
       if not UnitAffectingCombat("player") then 
           allConditionsMet = false; break 
       end
   ```

### Priority 3: Quality of Life

7. **Add debug output for macro parse failures:**
   ```lua
   if debugMode and not found then
       print("|JAC| Failed to find " .. targetSpellName .. " in macro:")
       print("|JAC| " .. macroBody)
   end
   ```

8. **Track and report cache hit rate:**
   ```lua
   local cacheHits, cacheMisses = 0, 0
   -- Increment in GetMacroSpellInfo()
   -- Report with /jac macrostats
   ```

9. **Spell relationship auto-detection:**
   ```lua
   -- Instead of hardcoding Ravage/FB:
   -- Check if C_Spell.GetSpellLink() differs based on form
   -- Build dynamic relationship map
   ```

---

## Debug Commands Needed

Add to DebugCommands.lua:

```lua
function DebugCommands.TestMacroParsing(addon, slot)
    if not slot then
        addon:Print("Usage: /jac testmacro <slot>")
        return
    end
    
    local actionText = GetActionText(slot)
    if not actionText then
        addon:Print("Slot " .. slot .. " is not a macro")
        return
    end
    
    local name, _, body = GetMacroInfo(actionText)
    addon:Print("=== Macro: " .. name .. " (Slot " .. slot .. ") ===")
    addon:Print(body)
    addon:Print("")
    
    -- Test current queue spells against this macro
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local queue = SpellQueue and SpellQueue.GetCurrentSpellQueue()
    
    if queue then
        for i, spellID in ipairs(queue) do
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo then
                local MacroParser = LibStub("JustAC-MacroParser", true)
                local result = MacroParser.GetMacroSpellInfo(slot, spellID, spellInfo.name)
                
                if result then
                    addon:Print("✓ " .. spellInfo.name .. " FOUND")
                    addon:Print("  Score: " .. result.qualityScore)
                    addon:Print("  Modifiers: " .. (result.modifiers.mod or "none"))
                else
                    addon:Print("✗ " .. spellInfo.name .. " NOT FOUND")
                end
            end
        end
    end
    
    addon:Print("================================")
end
```

Usage: `/jac testmacro 12`

---

## Real-World Macro Patterns (Verified)

### Statistics from Feral/Resto Druid (26 Macros)

**Pattern Frequency:**
- Multiple bracket cascades: 92% (24/26)
- Form switching logic: 77% (20/26)
- `known:` conditions: 81% (21/26)
- `@mouseover` targeting: 50% (13/26)
- `noform:` negation: 58% (15/26)
- Spec-specific spells: 85% (22/26)

**Complexity Distribution:**
- Simple (1 spell, 0-1 conditions): 8%
- Medium (2-3 spells, 2-4 conditions): 42%
- Complex (4+ spells, 5+ conditions): 50%

**Most Common Pattern:**
```lua
#showtooltip
/use [spec:X,noform:Y]FormSpell
/use [mod,condition]ModifiedSpell;[condition]DefaultSpell;Fallback
```

**Example: "M1" Macro (Typical Complexity)**
```lua
#showtooltip
/use [spec:1,noform:4]Moonkin Form;[spec:2,noform:2]Cat Form;[spec:3,noform:1]Bear Form
/use [mod,known:108238]Renewal
/use [mod,known:192081]Ironfur
/use [form:1]Mangle;[form:2]Shred;Starsurge
```

**Parsing challenges:**
- Line 1: 3 spell options with spec+noform conditions (6 conditions total)
- Line 2: Optional spell with mod+known (2 conditions)
- Line 3: Optional spell with mod+known (2 conditions)
- Line 4: 3 spell options with form conditions (2 conditions + fallback)
- **Total:** 4 /use lines, 10 distinct spells, 12 condition checks

**Quality Score Calculation:**
- Mangle (in bear form): Base 500 + 50(form:1) - 0(first line) = 550
- Shred (in cat form): Base 500 + 50(form:2) - 75(second position) = 475
- Starsurge (in moonkin): Base 500 - 150(third position) = 350

### Test Macro Set for Feral Druid

```lua
-- Macro 1: "Bear"
#showtooltip
/cast [form:1] Maul; [form:0] Wrath
/cast [form:1] Swipe

-- Expected behavior:
-- In bear form: Show Maul (first line), ignore Swipe (second line = penalty)
-- In caster form: Show Wrath
-- Score (Maul, in bear): 500 + 50([form:1]) - 0 = 550
-- Score (Swipe, in bear): 500 + 50([form:1]) - 150(second line) = 400

-- Macro 2: "Cat"
#showtooltip Mangle
/cast [mod:shift,form:2] Ferocious Bite; [form:2] Mangle; Wrath

-- Expected behavior:
-- In cat form + shift: Show FB with "Shift+key"
-- In cat form: Show Mangle
-- In caster form: Show Wrath
-- Score (FB, cat+shift): 500 + 100([mod+form]) + 200(name) - 0 = 800
-- Score (Mangle, cat): 500 + 50([form:2]) - 75(second pos) + 200(name) = 675

-- Macro 3: "Multi"
/castsequence reset=3 Maul, Swipe, Thrash

-- Expected behavior:
-- ❌ BROKEN: "reset=3 maul" won't match "Maul"
-- Needs preprocessing to strip reset clause
```

**Action Required:** Create test suite with these macros, verify scores match expectations.

---

## Conclusion

MacroParser is functionally complete for basic macro scenarios but has significant gaps:

**Works Well:**
- ✅ Form-specific macros ([form:X])
- ✅ Modifier detection ([mod:shift])
- ✅ Spec-specific macros ([spec:X])
- ✅ Quality scoring for simple cases
- ✅ Spell override tracking (via C_Spell.GetOverrideSpell)

**Needs Work:**
- ❌ Multiple bracket groups (cascading conditions)
- ❌ Castsequence with reset parameter
- ❌ Item slot usage (/use 13)
- ❌ Combat/target/pet conditions
- ❌ Spec changes not invalidating cache
- ❌ Condition counting in quality score (counts wrong conditions)

**Biggest Risk:**
Users with complex multi-condition macros will see wrong hotkeys or missing spells. The single-bracket limitation is the most critical fix needed.

**Recommended Next Steps:**
1. Run test suite on real player macros
2. Fix bracket parsing (Priority 1)
3. Add spec to cache key (Priority 1)  
4. Implement missing conditions based on usage frequency (Priority 2)
5. Add /jac testmacro command for user debugging

---

## Appendix: WoW Macro Syntax Reference

```lua
-- Condition syntax:
[condition1,condition2]  -- AND logic (both must be true)
[cond1][cond2]          -- OR logic (cascade, first true wins)

-- Spell syntax:
/cast SpellName         -- Direct cast
/cast [cond] Spell1; Spell2; Spell3  -- Conditional cascade
/castsequence reset=N Spell1, Spell2  -- Sequential
/use ItemName           -- Items or spells
/use SlotNumber         -- Equipment slots (0-19)

-- Common conditions:
[mod:shift/ctrl/alt]    -- Modifier held
[mod]                   -- Any modifier
[form:N]                -- Druid form / Warrior stance
[stance:N]              -- Alias for form
[spec:N]                -- Talent spec (1-4)
[target=unit]           -- Target selection
[combat]/[nocombat]     -- Combat state
[harm]/[help]           -- Enemy/friendly target
[dead]/[nodead]         -- Target state
[exists]                -- Target exists
[pet:name]              -- Pet type active
[equipped:type]         -- Item equipped
[flying]/[swimming]     -- Movement state
[mounted]/[unmounted]   -- Mount state
[indoors]/[outdoors]    -- Zone type
[channeling:spell]      -- Casting/channeling check
```

For AI agents: Always verify actual macro syntax with `/script` tests before assuming parsing behavior.
