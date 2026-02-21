# Assisted Combat API Deep Dive - JustAC Integration

**Source:** Blizzard UI Source Files  
**Version:** Retail (12.0.x)  
**Last Updated:** 2026-02-21

> **⚠ 12.0 MAJOR UPDATE:** `AssistedCombatManager.lua`, `AssistedCombatDocumentation.lua`,
> `Blizzard_SpellSearchAssistedCombatFilter.lua`, and all `AssistedCombatRotationFrameMixin`
> code in `ActionButton.lua` are **entirely new in 12.0** (confirmed via diff — new file mode).
> The core `C_AssistedCombat` namespace existed pre-12.0 but the entire Blizzard UI controller
> layer was added/rewritten in 12.0.

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
1. **`subType` check (Blizzard's actual method):** `type == "spell" and subType ~= "assistedcombat"` — Blizzard checks `subType`, NOT `id`!
2. API check: `C_ActionBar.IsAssistedCombatAction(slot)` — authoritative
3. Fallback: `type(id) == "string" and id == "assistedcombat"` — may or may not be reliable (unverified)

> **⚠ DOCUMENTATION ERROR (pre-12.0):** Earlier notes stated `id == "assistedcombat"`. Source confirms
> Blizzard filters via `subType ~= "assistedcombat"`. JustAC's `BlizzardAPI.GetActionInfo()` should
> be verified/updated to match. Use `IsAssistedCombatAction(slot)` as the belt-and-suspenders check.

**Why It Matters:**
- Dynamic button changes spell without slot update
- Cannot use for hotkey detection
- Must filter from action bar scans

### GetActionInfo Filtering (BlizzardAPI.lua)

> **⚠ IMPORTANT:** Blizzard's source (12.0) checks `subType ~= "assistedcombat"`, not the `id` field.
> JustAC currently filters on `id == "assistedcombat"`. Both checks should stay until verified in-game.

```lua
function BlizzardAPI.GetActionInfo(slot)
    local actionType, id, subType, spell_id_from_macro = GetActionInfo(slot)
    
    -- Blizzard (12.0) checks subType, not id:
    --   elseif type == "spell" and subType ~= "assistedcombat" then
    -- JustAC currently filters id. Keep both until verified:
    if actionType == "spell" and (
        (type(id) == "string" and id == "assistedcombat") or
        (subType == "assistedcombat")
    ) then
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
- **JustAC:** Does NOT modify - respects user's setting

### `assistedCombatHighlight`
- **Type:** Boolean
- **Purpose:** Enable Blizzard's native button glow
- **Effect:** Activates `AssistedCombatManager` update loop
- **JustAC:** Does NOT modify - respects user's setting

### `assistedCombatIconUpdateRate`
- **Type:** Number (0-1)
- **Default:** Unknown (likely 0.05 based on code comments)
- **Purpose:** Throttle update frequency in seconds
- **Clamped:** `Clamp(value, 0, 1)` in `ProcessCVars()`
- **JustAC:** Should respect but can have own throttle

### `assistedCombatHighlightRPE` *(New in 12.0)*
- **Type:** Boolean
- **Purpose:** Tutorial/RPE-specific highlight variant (set by `Blizzard_Tutorials_RPE`)
- **Effect:** Enables highlight mode during new player experience quests only
- **JustAC:** Ignore — tutorial system only, disabled after RPE completes

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

## AssistedCombatManager Public API *(New in 12.0)*

Blizzard now exposes a global singleton `AssistedCombatManager` with a rich public API.
These can be called directly from JustAC — no need to re-implement equivalent logic.

```lua
-- Check if action spell exists
AssistedCombatManager:HasActionSpell()           -- → bool

-- Get current action spell ID (same as C_AssistedCombat.GetActionSpell())
AssistedCombatManager:GetActionSpellID()          -- → spellID or nil

-- Get spell description string (loaded async on action spell change)
AssistedCombatManager:GetActionSpellDescription() -- → string or nil

-- Fast set-lookup: is spellID part of the rotation?
AssistedCombatManager:IsRotationSpell(spellID)    -- → bool (O(1), backed by hash)

-- Is the assistedCombatHighlight CVar enabled?
AssistedCombatManager:IsAssistedHighlightActive() -- → bool

-- Current update rate in seconds (from assistedCombatIconUpdateRate CVar)
AssistedCombatManager:GetUpdateRate()             -- → number (0-1)

-- Is this button currently highlighted as recommended?
AssistedCombatManager:IsRecommendedAssistedHighlightButton(actionButton) -- → bool

-- Spellbook integration
AssistedCombatManager:ShouldHighlightSpellbookSpell(spellID)  -- → bool
AssistedCombatManager:IsHighlightableSpellbookSpell(spellID)  -- → bool
```

**JustAC Opportunity:** `AssistedCombatManager:IsRotationSpell(spellID)` is a fast O(1) lookup
with Blizzard-managed cache. Could replace/supplement JustAC's own rotation set tracking.

---

## EventRegistry Events *(New in 12.0)*

Blizzard fires these `EventRegistry` events from `AssistedCombatManager`. These are **not**
standard WoW frame events — they use `EventRegistry:RegisterCallback()` not `self:RegisterEvent()`.

| Event | When Fired | JustAC Use |
|-------|-----------|------------|
| `AssistedCombatManager.RotationSpellsUpdated` | After `SPELLS_CHANGED` finishes updating the rotation set | **Best hook for cache invalidation** |
| `AssistedCombatManager.OnSetActionSpell` | When primary action spell ID changes | Track recommend-spell changes |
| `AssistedCombatManager.OnAssistedHighlightSpellChange` | When `GetNextCastSpell()` result changes (highlight mode only) | Could drive UI updates |
| `AssistedCombatManager.OnSetUseAssistedHighlight` | When `assistedCombatHighlight` CVar changes | Adjust JustAC behavior to coexist |
| `AssistedCombatManager.OnSetCanHighlightSpellbookSpells` | Spellbook highlight setting changed | Low priority |
| `ActionButton.OnAssistedCombatRotationFrameChanged` | Rotation frame show/hide on a button | Low priority |

**Recommended usage:**
```lua
-- Cache invalidation: listen to RotationSpellsUpdated instead of SPELLS_CHANGED
EventRegistry:RegisterCallback("AssistedCombatManager.RotationSpellsUpdated", function()
    rotationSpellsValid = false  -- invalidate JustAC cache
end, JustAC)

-- Track when primary spell changes
EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function(spellID)
    -- spellID is passed as argument
end, JustAC)
```

> **Note:** `RotationSpellsUpdated` fires AFTER `SPELLS_CHANGED` has finished processing
> the full rotation set — Blizzard explicitly comments this is intentional so listeners
> get accurate `IsRotationSpell()` results.

---

## SpellSearch Integration *(New in 12.0)*

`Blizzard_SpellSearchAssistedCombatFilter.lua` adds a spell book search filter.

- **Filter mixin:** `SpellSearchAssistedCombatFilterMixin`
- **Match type:** `SpellSearchUtil.MatchType.AssistedCombat`
- **Logic:** Calls `AssistedCombatManager:IsRotationSpell(spellID)` on each spell book item
- **Filters out:** Passive spells, off-spec spells, future spells

This means users can search/filter their spellbook to show only rotation spells. Not
directly actionable for JustAC but confirms `IsRotationSpell()` is the authoritative check.

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

### Known Bugs (Source-Validated)

> All items below were validated against Blizzard source (`AssistedCombatManager.lua`,
> `AssistedCombatDocumentation.lua`, `ActionButton.lua`) on 2025-07-11.

#### BUG-1: `TestCooldownAccess()` / `TestProcAccess()` — Dead Code *(Critical)*

**File:** `BlizzardAPI.lua` lines 200, 225  
**Issue:** Both functions access `spells[1].spellId`, but `C_AssistedCombat.GetRotationSpells()`
returns a **flat array of numbers** (`{ Type = "table", InnerType = "number" }`), NOT objects.  
`spells[1].spellId` is always `nil`, so the secret-value detection for cooldowns and procs
**never executes**. Feature availability flags default to `true` (fail-open), masking the bug.

```lua
-- CURRENT (broken):
local spells = C_AssistedCombat.GetRotationSpells()
if spells and spells[1] and spells[1].spellId then  -- always nil

-- FIX:
if spells and spells[1] then
    local cooldownInfo = C_Spell_GetSpellCooldown(spells[1])
```

#### BUG-2: `GetActionInfo()` Filters on `id` Instead of `subType` *(Medium)*

**File:** `BlizzardAPI.lua` line 606  
**Issue:** JustAC checks `type(id) == "string" and id == "assistedcombat"`, but Blizzard's
canonical filter (AssistedCombatManager.lua line 207) is `subType ~= "assistedcombat"`.

```lua
-- CURRENT:
if actionType == "spell" and type(id) == "string" and id == "assistedcombat" then

-- Blizzard's canonical check:
-- elseif type == "spell" and subType ~= "assistedcombat" then
```

**Mitigated** by `C_ActionBar.IsAssistedCombatAction(slot)` safety net in ActionBarScanner,
so no user-visible bugs currently. The `subType` check should be added alongside the existing
`id` check for correctness.

### Performance Improvements (Source-Validated)

#### PERF-1: Cache `GetRotationSpells()` Result *(High Priority)*

**File:** `SpellQueue.lua` line 386  
**Issue:** `GetRotationSpells()` is called every throttle tick (~10/sec in combat). Blizzard's
`AssistedCombatManager` only calls it on `SPELLS_CHANGED` — the list is static during combat.

**Status:** JustAC already wires `RotationSpellsUpdated` EventRegistry event (JustAC.lua line 273).  
**Fix:** Cache the result list and only refresh on the `RotationSpellsUpdated` callback.
Reduces API calls by ~99%.

#### PERF-2: Reuse `GetBypassFlags()` Table *(Medium Priority)*

**File:** `BlizzardAPI.lua` lines 298–312  
**Issue:** Creates a new Lua table literal every call. Called every SpellQueue update tick.  
**Fix:** Allocate a module-level table once and update its fields in-place:

```lua
local bypassCache = {}
function BlizzardAPI.GetBypassFlags()
    RefreshFeatureAvailability()
    bypassCache.bypassRedundancy = not BlizzardAPI.IsRedundancyFilterAvailable()
    -- ...etc
    return bypassCache
end
```

### Opportunities (Source-Validated)

#### OPP-1: Use `AssistedCombatManager:IsRotationSpell(spellID)` *(Low Priority)*

**Source:** `AssistedCombatManager.lua` line 3 — declared as global.  
**Benefit:** O(1) hash-set lookup vs. iterating the rotation list. Already maintained by
Blizzard's event handlers. Requires 12.0+ guard since the global doesn't exist pre-12.0.

```lua
if AssistedCombatManager and AssistedCombatManager.IsRotationSpell then
    local isRotation = AssistedCombatManager:IsRotationSpell(spellID)
end
```

### Other Recommendations

1. **Consider using `GetActionSpell()` instead of `GetNextCastSpell()`**
   - Blizzard uses `GetActionSpell()` internally for highlight checks
   - May have different behavior (untested)
   - Verify difference with `/script` tests

2. **Add CVar sync option**
   - Let users match Blizzard's update rate via `assistedCombatIconUpdateRate`
   - Current hardcoded 0.03/0.08 may feel different from native

3. **EventRegistry integration** *(Already Implemented)*
   - ✅ JustAC.lua lines 269–277 already registers 3 EventRegistry callbacks:
     `OnAssistedHighlightSpellChange`, `RotationSpellsUpdated`, `OnSetActionSpell`
   - No further action needed

4. **Verify spell override handling**
   - Test if `GetRotationSpells()` returns base or override IDs
   - May explain some "wrong spell" bugs

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

| File | Purpose | Version Added |
|------|---------|---------------|
| `AssistedCombatDocumentation.lua` | C_AssistedCombat API spec | **New in 12.0** |
| `ActionBarFrameDocumentation.lua` | C_ActionBar API spec incl. `HasAssistedCombatActionButtons` | Pre-12.0 |
| `AssistedCombatManager.lua` | Blizzard's controller singleton | **New in 12.0** |
| `ActionButton.lua` | Action button integration + `AssistedCombatRotationFrameMixin` | **New in 12.0** |
| `Blizzard_SpellSearchAssistedCombatFilter.lua` | Spell book rotation filter | **New in 12.0** |

**Key Functions by Module:**
- **AssistedCombatManager:** `OnSpellsChanged`, `IsRotationSpell`, `UpdateAllAssistedHighlightFramesForSpell`, `GetActionSpellDescription`, `AddSpellTooltipLine`
- **ActionButton:** `UpdateAssistedCombatRotationFrame`, `IsAssistedCombatAction` checks
- **CVarCallbackRegistry:** Auto-reload on CVar changes

---

## Version Notes

- **12.0 (Midnight):** `AssistedCombatManager.lua`, `AssistedCombatDocumentation.lua`,
  `Blizzard_SpellSearchAssistedCombatFilter.lua`, and all `AssistedCombatRotationFrameMixin`
  code in `ActionButton.lua` confirmed as **new files** via 11.x→12.0 diff (all lines are additions).
- **Pre-12.0 (TWW/11.x):** Core `C_AssistedCombat` namespace already existed. `GetNextCastSpell`,
  `GetRotationSpells`, `GetActionSpell`, `IsAvailable` were available. No formal documentation
  file and no `AssistedCombatManager` singleton.
- **`GetNextCastSpell` flag:** Has `SecretArguments = "AllowedWhenUntainted"` in docs —
  confirms call must come from untainted addon code (JustAC is untainted, so no issue).
