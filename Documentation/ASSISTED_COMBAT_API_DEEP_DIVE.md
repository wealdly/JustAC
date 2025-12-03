# Assisted Combat API Deep Dive - JustAC Integration

**Source:** Blizzard UI Source Files  
**Version:** Retail (11.0.7)  
**Last Updated:** 2025-11-18

---

## Executive Summary

The Assisted Combat system is Blizzard's integrated rotation helper that provides:
1. **Primary "action spell"** - Single recommended spell (via `GetNextCastSpell`)
2. **Full rotation queue** - Extended spell list (via `GetRotationSpells`)
3. **Visual highlighting** - Native button glows (via `assistedCombatHighlight` CVar)
4. **Single-button assistant** - Special actionType `"assistedcombat"` that changes dynamically

**JustAC's Role:** Display the rotation queue with hotkeys, avoiding duplication with Blizzard's highlight system.

---

## C_AssistedCombat API (Official Documentation)

### Functions

#### `GetActionSpell()`
```lua
Returns: spellID (number, nilable)
```
- **Purpose:** Returns the "action spell" - highest priority rotation spell
- **JustAC Usage:** Not currently used (we use `GetNextCastSpell` instead)
- **Difference from GetNextCastSpell:** Unclear from docs

#### `GetNextCastSpell(checkForVisibleButton)`
```lua
Arguments: checkForVisibleButton (bool, default=false)
Returns: spellID (number, nilable)
```
- **Purpose:** Primary rotation spell recommendation
- **When checkForVisibleButton=true:** Only returns spell if it has a visible action button
- **JustAC Usage:** Called with `true` (Blizzard default) in `BlizzardAPI.GetNextCastSpell()`
- **Update Frequency:** Controlled by `assistedCombatIconUpdateRate` CVar (0-1 seconds)

#### `GetRotationSpells()`
```lua
Returns: spellIDs (table of numbers, never nil)
```
- **Purpose:** Full rotation queue (typically 5-20 spells)
- **Return Guarantee:** Always returns table (may be empty)
- **JustAC Usage:** Core of `SpellQueue.GetCurrentSpellQueue()`
- **Order:** Blizzard-determined priority

#### `IsAvailable()`
```lua
Returns: 
  - isAvailable (bool)
  - failureReason (string)
```
- **Purpose:** Check if system is enabled and functional
- **Failure Reasons:** Unknown (not documented)
- **JustAC Usage:** `BlizzardAPI.ValidateAssistedCombatSetup()`

### Events

#### `ASSISTED_COMBAT_ACTION_SPELL_CAST`
```lua
Event: "ASSISTED_COMBAT_ACTION_SPELL_CAST"
```
- **Fires:** When action spell is successfully cast
- **JustAC Usage:** Not currently used
- **Blizzard Usage:** Help tip dismissal in `AssistedCombatRotationFrameMixin`

---

## C_ActionBar API (Relevant Functions)

### Assisted Combat Detection

#### `FindAssistedCombatActionButtons()`
```lua
Returns: slots (table of luaIndex) or nothing
Documentation: "Returns the list of action bar slots that contain the Assisted Combat action spell."
```
- **Purpose:** Locate all "single-button assistant" slots
- **Returns:** Array of slot IDs (e.g., `{12, 48}`) or nil
- **JustAC Usage:** Not currently used

#### `HasAssistedCombatActionButtons()`
```lua
Returns: hasButtons (bool)
```
- **Purpose:** Quick check if single-button assistant exists
- **Verified Behavior:** Returns `false` when no assistant placed
- **JustAC Usage:** `BlizzardAPI.ValidateAssistedCombatSetup()`

#### `IsAssistedCombatAction(slotID)`
```lua
Arguments: slotID (luaIndex)
Returns: isAssistedCombatAction (bool)
Documentation: "Returns whether the given action button contains the Assisted Combat action spell."
```
- **Purpose:** Check if specific slot is the single-button assistant
- **JustAC Usage:** Filter in `ActionBarScanner.FindSpellInActions()` and `GetActionButtonSpellForAssistedHighlight()`
- **Critical:** Must be used to avoid showing hotkey for dynamic assistant button

---

## AssistedCombatManager (Blizzard's Controller)

### Core Responsibilities

1. **Rotation Spell Tracking**
   ```lua
   rotationSpells = {}  -- table: [spellID] = true
   ```
   - Updated on `SPELLS_CHANGED` event
   - Used by `IsRotationSpell(spellID)` checks throughout UI

2. **Action Spell Management**
   ```lua
   actionSpellID = nil  -- Current primary spell
   spellDescription = nil  -- Cached description
   ```
   - Updated via `SetActionSpell(actionSpellID)`
   - Loads spell data asynchronously

3. **Highlight System Control**
   ```lua
   useAssistedHighlight = false  -- From assistedCombatHighlight CVar
   updateRate = 0  -- From assistedCombatIconUpdateRate CVar (0-1)
   ```

### Update Loop (Highlight Mode Only)

```lua
function AssistedCombatManager:OnUpdate(elapsed)
    self.updateTimeLeft = self.updateTimeLeft - elapsed
    if self.updateTimeLeft <= 0 then
        self.updateTimeLeft = self:GetUpdateRate()
        
        local checkForVisibleButton = true
        local spellID = C_AssistedCombat.GetNextCastSpell(checkForVisibleButton)
        
        if spellID ~= self.lastNextCastSpellID then
            self.lastNextCastSpellID = spellID
            self:UpdateAllAssistedHighlightFramesForSpell(spellID)
        end
    end
end
```

**Key Insights:**
- Only runs when `assistedCombatHighlight` CVar is enabled
- Respects `assistedCombatIconUpdateRate` CVar (clamped 0-1 seconds)
- Calls `GetNextCastSpell(true)` - requires visible button
- Updates ALL buttons with matching spell simultaneously

### Highlight Frame Management

```lua
function AssistedCombatManager:SetAssistedHighlightFrameShown(actionButton, shown)
    -- Creates AssistedCombatHighlightFrame on demand
    -- Frame structure:
    --   - Flipbook animation (play in combat, stop out of combat)
    --   - Positioned at CENTER
    --   - Frame level below MainMenuBar end caps
    --   - Size 48x48 for stance buttons, default otherwise
end
```

**Conflict Avoidance:**
- Blizzard highlights action buttons
- JustAC displays queue separately
- Both can coexist without interference

---

## Action Button Integration

### The "assistedcombat" ActionType

**Problem:** Single-button assistant returns special type:
```lua
local actionType, actionID = GetActionInfo(slot)
-- For assistant: actionType = "spell", actionID = "assistedcombat" (string!)
```

**Detection Methods:**
1. Type check: `type(actionID) == "string" and actionID == "assistedcombat"`
2. API check: `C_ActionBar.IsAssistedCombatAction(slot)`
3. String comparison in BlizzardAPI wrapper

**Why It Matters:**
- Dynamic button changes spell without slot update
- Cannot use for hotkey detection
- Must filter from action bar scans

### GetActionInfo Filtering (BlizzardAPI.lua)

```lua
function BlizzardAPI.GetActionInfo(slot)
    local actionType, id, subType, spell_id_from_macro = GetActionInfo(slot)
    
    -- Filter out assistedcombat string IDs
    if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then
        return nil, nil, nil, nil
    end
    
    return actionType, id, subType, spell_id_from_macro
end
```

### Rotation Frame on Action Buttons

**Source:** `ActionBarButtonAssistedCombatRotationFrameMixin`

```lua
function UpdateAssistedCombatRotationFrame()
    local show = C_ActionBar.IsAssistedCombatAction(self.action)
    -- Creates AssistedCombatRotationFrame overlay
    -- Updates glow based on combat state
    -- Runs update loop respecting assistedCombatIconUpdateRate
end
```

**Frame Details:**
- Size: 1.4x action button size
- Position: CENTER with offset (-2, 1)
- Textures: InactiveTexture (out of combat), ActiveFrame with GlowAnim (in combat)
- Update loop: Calls `C_ActionBar.ForceUpdateAction(slot)` at CVar rate

**JustAC Implication:** Don't create UI for the assistant button itself - it has native frame.

---

## CVars (Critical Configuration)

### `assistedMode`
- **Type:** Boolean
- **Purpose:** Master enable/disable for entire system
- **Effect:** Controls `C_AssistedCombat.IsAvailable()`
- **JustAC:** Auto-enables in `SetupAssistedCombatCVars()` if `autoEnableAssistedMode` setting true

### `assistedCombatHighlight`
- **Type:** Boolean
- **Purpose:** Enable Blizzard's native button glow
- **Effect:** Activates `AssistedCombatManager` update loop
- **JustAC:** Independent - works with or without
- **User Choice:** Optional complement to JustAC display

### `assistedCombatIconUpdateRate`
- **Type:** Number (0-1)
- **Default:** Unknown (likely 0.05 based on code comments)
- **Purpose:** Throttle update frequency in seconds
- **Clamped:** `Clamp(value, 0, 1)` in `ProcessCVars()`
- **JustAC:** Should respect but can have own throttle

---

## Integration Points for JustAC

### 1. Spell Queue Fetching

**Current Implementation (SpellQueue.lua):**
```lua
function GetCurrentSpellQueue()
    -- Get primary spell
    local primarySpellID = BlizzardAPI.GetNextCastSpell()
    if primarySpellID and not IsBlacklisted and not IsRedundant then
        table.insert(recommendedSpells, primarySpellID)
    end
    
    -- Get rotation queue
    local rotationList = BlizzardAPI.GetRotationSpells()
    for i = 1, #rotationList do
        -- Add if not already in queue
    end
end
```

**Blizzard Equivalent (AssistedCombatManager.lua):**
```lua
function OnSpellsChanged()
    wipe(self.rotationSpells)
    local rotationSpells = C_AssistedCombat.GetRotationSpells()
    for i, spellID in ipairs(rotationSpells) do
        self.rotationSpells[spellID] = true
    end
    
    local actionSpellID = C_AssistedCombat.GetActionSpell()
    self:SetActionSpell(actionSpellID)
end
```

**Key Difference:**
- Blizzard stores as set (fast lookup)
- JustAC stores as array (preserves order)
- Blizzard uses `GetActionSpell()` not `GetNextCastSpell()`

### 2. Action Bar Scanning

**Critical Filter (ActionBarScanner.lua line ~250):**
```lua
local actionType, id = BlizzardAPI.GetActionInfo(slot)

-- Skip assistant button
local isAssistantButton = (actionType == "spell" and type(id) == "string" and id == "assistedcombat")
local isAssistedCombatAction = C_ActionBar.IsAssistedCombatAction(slot)

if not isAssistantButton and not isAssistedCombatAction then
    -- Process normally
end
```

**Blizzard Equivalent (AssistedCombatManager.lua):**
```lua
function GetActionButtonSpellForAssistedHighlight(actionButton)
    local type, id, subType = GetActionInfo(actionButton.action)
    if type == "spell" and subType ~= "assistedcombat" then
        if self:IsRotationSpell(id) then
            return id
        end
    end
end
```

**Why Dual Check:**
- `type(id) == "string"` catches string "assistedcombat"
- `IsAssistedCombatAction()` is authoritative API
- Belt-and-suspenders approach ensures no false positives

### 3. Spell Alert Downgrading

**Blizzard Logic (AssistedCombatManager.lua):**
```lua
function ShouldDowngradeSpellAlertForButton(actionButton)
    local usingAssistedCombat = self:IsAssistedHighlightActive() or 
                                C_ActionBar.HasAssistedCombatActionButtons()
    if not usingAssistedCombat then return false end
    
    -- Only rotation spells get downgraded alerts
    local type, id = GetActionInfo(actionButton.action)
    if type == "spell" or (type == "macro" and subType == "spell") then
        return self:IsRotationSpell(id)
    end
end
```

**Purpose:** Proc glow (purple swirly) is less prominent for rotation spells.

**JustAC Consideration:** Not applicable - we don't use spell alerts.

---

## Event Flow

### System Initialization

```
PLAYER_LOGIN
  ↓
CVarCallbackRegistry loads CVars
  ↓
AssistedCombatManager:Init()
  ↓
Register CVar callbacks (assistedCombatHighlight, assistedCombatIconUpdateRate)
  ↓
SPELLS_CHANGED
  ↓
AssistedCombatManager:OnSpellsChanged()
  ↓
C_AssistedCombat.GetRotationSpells() → rotationSpells table
C_AssistedCombat.GetActionSpell() → actionSpellID
```

### Runtime Updates

```
Combat State Change (PLAYER_REGEN_DISABLED/ENABLED)
  ↓
AssistedCombatManager:OnPlayerRegenChanged()
  ↓
ForceUpdateAtEndOfFrame()
  ↓
AssistedCombatManager:OnUpdate()
  ↓
C_AssistedCombat.GetNextCastSpell(true)
  ↓
UpdateAllAssistedHighlightFramesForSpell(spellID)
  ↓
SetAssistedHighlightFrameShown(button, show)
  ↓
Flipbook animation plays/stops
```

### Macro/Form Changes

```
UPDATE_SHAPESHIFT_FORM or Action Button Changed
  ↓
AssistedCombatManager:OnActionButtonActionChanged(actionButton)
  ↓
GetActionButtonSpellForAssistedHighlight(actionButton)
  ↓
Update candidate button list
  ↓
ForceUpdateAtEndOfFrame() [if hasShapeshiftForms]
```

---

## Performance Characteristics

### Update Rate Control

**Blizzard Implementation:**
```lua
function ProcessCVars()
    local updateRate = tonumber(GetCVar("assistedCombatIconUpdateRate"))
    self.updateRate = Clamp(updateRate, 0, 1)  -- Min 0s, Max 1s
end

function OnUpdate(elapsed)
    self.updateTimeLeft = self.updateTimeLeft - elapsed
    if self.updateTimeLeft <= 0 then
        self.updateTimeLeft = self:GetUpdateRate()  -- Reset throttle
        -- Do work
    end
end
```

**JustAC Implementation (SpellQueue.lua):**
```lua
local function GetQueueThrottleInterval()
    local inCombat = UnitAffectingCombat("player")
    return inCombat and 0.03 or 0.08
end

function GetCurrentSpellQueue()
    local now = GetTime()
    if now - lastQueueUpdate < GetQueueThrottleInterval() then
        return lastSpellIDs  -- Cached
    end
    lastQueueUpdate = now
    -- Fetch fresh data
end
```

**Comparison:**
| System | Combat Interval | OOC Interval | CVar Respect |
|--------|----------------|--------------|--------------|
| Blizzard | CVar (0-1s) | CVar (0-1s) | Yes (required) |
| JustAC | 0.03s (30fps) | 0.08s (12.5fps) | Parallel system |

**Recommendation:** Add option to sync with Blizzard's update rate for consistency.

### API Call Frequency

**GetRotationSpells() Calls:**
- Blizzard: Only on `SPELLS_CHANGED` (spec/talent/equipment changes)
- JustAC: Every throttle interval (30-100 calls/second in combat!)

**Optimization Opportunity:**
```lua
-- Cache rotation spells like Blizzard does
local cachedRotationSpells = {}
local rotationSpellsValid = false

function OnSpellsChanged()
    rotationSpellsValid = false
end

function GetCurrentSpellQueue()
    if not rotationSpellsValid then
        cachedRotationSpells = C_AssistedCombat.GetRotationSpells()
        rotationSpellsValid = true
    end
    -- Use cachedRotationSpells
end
```

---

## Tooltip Integration

**Blizzard Implementation (AssistedCombatManager.lua):**
```lua
function AddSpellTooltipLine(tooltip, spellID, overriddenSpellID)
    local usingRotation = C_ActionBar.HasAssistedCombatActionButtons()
    local usingHighlight = self:IsAssistedHighlightActive()
    
    if not usingRotation and not usingHighlight then return end
    
    if self:IsRotationSpell(spellID) then
        local text = ASSISTED_COMBAT_SPELL_INCLUDED
        if not usingRotation then
            text = ASSISTED_COMBAT_HIGHLIGHT_SPELL_INCLUDED
        elseif not usingHighlight then
            text = ASSISTED_COMBAT_ROTATION_SPELL_INCLUDED
        end
        GameTooltip_AddColoredLine(tooltip, text, LIGHTBLUE_FONT_COLOR)
    end
end
```

**String Constants (likely in Localization.lua):**
- `ASSISTED_COMBAT_SPELL_INCLUDED` - "Part of your assisted combat rotation"
- `ASSISTED_COMBAT_HIGHLIGHT_SPELL_INCLUDED` - (highlight only)
- `ASSISTED_COMBAT_ROTATION_SPELL_INCLUDED` - (rotation button only)

**JustAC Integration:** Not currently used. Could add similar line to action button tooltips.

---

## Spell Override Handling

**Blizzard Approach:** None visible in source.

**Expected Behavior:**
- `GetRotationSpells()` returns BASE spell IDs
- Action buttons handle `C_Spell.GetOverrideSpell()` internally
- UI displays current override texture

**JustAC Approach (SpellQueue.lua):**
```lua
if spellID and spellInfo then
    -- Check for override
    local override = C_Spell.GetOverrideSpell(spellID)
    local actualSpellID = (override ~= 0) and override or spellID
    table.insert(recommendedSpells, actualSpellID)
end
```

**Verification Needed:** Does `GetRotationSpells()` return base or override IDs?

**Test Command:**
```lua
-- In cat form with Rake/Pounce relationship:
/script local spells = C_AssistedCombat.GetRotationSpells(); for i, id in ipairs(spells) do print(i, id, C_Spell.GetSpellInfo(id).name) end
```

---

## Edge Cases & Gotchas

### 1. Dynamic Single-Button Assistant

**Issue:** Button changes spell without `ACTIONBAR_SLOT_CHANGED` event.

**Blizzard Solution:**
```lua
function OnUpdate(elapsed)
    -- Poll GetNextCastSpell() every updateRate
    -- Update highlight if spell changed
end
```

**JustAC Solution:** Don't track assistant button - it's self-updating.

### 2. Macro Spell Icons

**Issue:** Macros with `#showtooltip` show conditional spell icon.

**Blizzard Detection:**
```lua
if type == "macro" and subType == "spell" then
    return id  -- Spell ID shown on macro icon
end
```

**JustAC Usage:** `MacroParser.GetMacroSpellInfo()` for hotkey detection.

### 3. Form-Specific Spells

**Issue:** Rotation includes spells for other forms.

**Blizzard Handling:** Unknown (no filtering visible in source).

**JustAC Solution:** `RedundancyFilter.IsSpellRedundant()` checks form mismatches.

### 4. Empty Rotation Out of Combat

**Verified:** `GetRotationSpells()` returns empty table when not in combat for some specs.

**JustAC Handling:**
```lua
local rotationList = BlizzardAPI.GetRotationSpells()
if rotationList and #rotationList > 0 then
    -- Process spells
end
```

### 5. Stance Bar Priority

**Blizzard Code (AssistedCombatManager.lua):**
```lua
function UpdateAllAssistedHighlightFramesForSpell(spellID)
    local hasHighlightedActionButton = false
    for actionButton, actionSpellID in pairs(candidateButtons) do
        local show = actionSpellID == spellID
        hasHighlightedActionButton = hasHighlightedActionButton or show
        SetAssistedHighlightFrameShown(actionButton, show)
    end
    
    -- Don't highlight stance bar if normal button already highlighted
    for i = 1, StanceBar.numForms do
        local actionButton = StanceBar.actionButtons[i]
        local show = not hasHighlightedActionButton and spellID and actionButton.spellID == spellID
        SetAssistedHighlightFrameShown(actionButton, show)
    end
end
```

**Key Insight:** Stance buttons are deprioritized vs normal action bars.

**JustAC Behavior:** Matches via `useBlizzardPriority` setting in ActionBarScanner.

---

## Recommendations for JustAC

### High Priority

1. **Cache GetRotationSpells() result**
   - Currently called every throttle interval (wasteful)
   - Blizzard only updates on `SPELLS_CHANGED`
   - Reduces API calls by 99%

2. **Consider using GetActionSpell() instead of GetNextCastSpell()**
   - Blizzard uses `GetActionSpell()` internally
   - May have different behavior (untested)
   - Verify difference with `/script` tests

3. **Add CVar sync option**
   - Let users match Blizzard's update rate
   - Current hardcoded 0.03/0.08 may feel different

### Medium Priority

4. **Add rotation spell tooltip line**
   - Matches Blizzard UI convention
   - Helps users understand which spells are assisted

5. **Verify spell override handling**
   - Test if `GetRotationSpells()` returns base or override IDs
   - May explain some "wrong spell" bugs

6. **EventRegistry integration**
   - Blizzard uses `EventRegistry:TriggerEvent("AssistedCombatManager.RotationSpellsUpdated")`
   - Could listen instead of `SPELLS_CHANGED`

### Low Priority

7. **Stance bar deprioritization**
   - Already implemented via scoring system
   - Consider matching Blizzard's exact logic

8. **Spell alert downgrade compatibility**
   - Not critical (we don't use spell alerts)
   - Could add option to respect if users want it

---

## Testing Commands

### Verify API Behavior
```lua
-- Check system availability
/script local avail, reason = C_AssistedCombat.IsAvailable(); print("Available:", avail, "Reason:", reason)

-- Check CVars
/script print("Mode:", GetCVarBool("assistedMode"), "Highlight:", GetCVarBool("assistedCombatHighlight"), "Rate:", GetCVar("assistedCombatIconUpdateRate"))

-- Get current spells
/script local next = C_AssistedCombat.GetNextCastSpell(true); print("Next:", next, C_Spell.GetSpellInfo(next).name)
/script local act = C_AssistedCombat.GetActionSpell(); print("Action:", act, act and C_Spell.GetSpellInfo(act).name)
/script local rot = C_AssistedCombat.GetRotationSpells(); print("Rotation:", #rot, "spells")

-- Check for assistant button
/script print("Has buttons:", C_ActionBar.HasAssistedCombatActionButtons())
/script local slots = C_ActionBar.FindAssistedCombatActionButtons(); if slots then for i, s in ipairs(slots) do print("Slot", s) end end

-- Test specific slot
/script print("Slot 12 is assistant:", C_ActionBar.IsAssistedCombatAction(12))
```

### Verify Update Rate
```lua
-- Monitor GetNextCastSpell changes
/script local last = nil; local f = CreateFrame("Frame"); f:SetScript("OnUpdate", function() local now = C_AssistedCombat.GetNextCastSpell(true); if now ~= last then last = now; print(GetTime(), "Changed to:", now and C_Spell.GetSpellInfo(now).name) end end)

-- Stop monitoring
/script for i, v in pairs(UIParent:GetChildren()) do if v:GetScript("OnUpdate") then v:SetScript("OnUpdate", nil) end end
```

---

## Appendix: Source File Map

| File | Purpose |
|------|---------|
| `AssistedCombatDocumentation.lua` | C_AssistedCombat API spec |
| `ActionBarFrameDocumentation.lua` | C_ActionBar API spec |
| `AssistedCombatManager.lua` | Blizzard's controller singleton |
| `ActionButton.lua` | Action button integration |

**Key Functions by Module:**
- **AssistedCombatManager:** `OnSpellsChanged`, `IsRotationSpell`, `UpdateAllAssistedHighlightFramesForSpell`
- **ActionButton:** `UpdateAssistedCombatRotationFrame`, `IsAssistedCombatAction` checks
- **CVarCallbackRegistry:** Auto-reload on CVar changes

---

## Version Notes

- **11.0.7+:** Current implementation analyzed
- **Earlier versions:** `GetNextCastSpell` parameter behavior unknown
- **TWW (11.0):** Assisted Combat introduced (verify actual expansion)
