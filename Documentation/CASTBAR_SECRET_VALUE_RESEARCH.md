# Cast Bar Secret Value Handling — Addon Research (WoW 12.0 Midnight)

Research into how three major addons handle `notInterruptible` and other secret values in cast bar code under WoW 12.0's secret value system.

**Addons analyzed:**
- **Plater Nameplates** (Tercioo/Plater-Nameplates) + **DetailsFramework** (Tercioo/Details-Framework)
- **ElvUI** (tukui-org/ElvUI) via **oUF** (ElvUI_Libraries)
- **SUF NoSelph fork** (NoSelph/ShadowedUnitFrames, alpha branch)

**Date:** 2025-06-16

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Key APIs and Concepts](#2-key-apis-and-concepts)
3. [Plater / DetailsFramework](#3-plater--detailsframework)
4. [ElvUI / oUF](#4-elvui--ouf)
5. [SUF (NoSelph Fork)](#5-suf-noselph-fork)
6. [Comparison Matrix](#6-comparison-matrix)
7. [Notable Patterns for JustAC](#7-notable-patterns-for-justac)

---

## 1. Executive Summary

All three addons converge on the same core strategy: **never read secret values directly — pipe them through Blizzard's secret-safe UI methods instead.** The differences are in elegance and edge-case handling.

| Problem | Blizzard's Solution | How Addons Use It |
|---------|-------------------|-------------------|
| `notInterruptible` is a secret boolean | `Widget:SetAlphaFromBoolean(secretBool, alphaTrue, alphaFalse)` | Show/hide shield overlay |
| `startTime`/`endTime`/`duration` are secret numbers | `UnitCastingDuration()` → `StatusBar:SetTimerDuration(durationObj, interp, dir)` | Drive cast bar fill |
| Cast bar color depends on secret boolean | `C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, val1, val2)` | Tint bar per-channel |
| `castID` is secret | Use `barID` (10th return of `UnitCastingInfo`) as `castBarID` | Match cast identity |
| `spellID`/`name` may be secret | `issecretvalue()` guard before any read | Gate spell-specific logic |
| Remaining time display | `DurationObject:GetRemainingDuration()` | Cast time text |

---

## 2. Key APIs and Concepts

### Secret-Safe Widget Methods
```lua
-- Boolean → visibility (alpha)
widget:SetAlphaFromBoolean(secretBool, alphaIfTrue, alphaIfFalse)

-- Boolean → color channel  (returns secret number suitable for SetVertexColor)
C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, valueIfTrue, valueIfFalse)

-- Duration pipeline (replaces manual SetValue/SetMinMaxValues)
local durationObj = UnitCastingDuration(unit)
statusBar:SetTimerDuration(durationObj, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)

-- Remaining time (for text display)
local remaining = durationObj:GetRemainingDuration()
fontString:SetText(format("%.1f", remaining))

-- Elapsed time
local elapsed = durationObj:GetElapsedDuration()

-- Total duration
local total = durationObj:GetTotalDuration()
```

### UnitCastingInfo Return Values (12.0)
```lua
local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID, barID = UnitCastingInfo(unit)
-- name, text         — may be secret in combat
-- startTime, endTime — secret in combat
-- castID             — SECRET (use barID instead)
-- notInterruptible   — SECRET boolean
-- spellID            — may be secret in combat
-- barID              — NOT SECRET (10th return, new for 12.0)
```

---

## 3. Plater / DetailsFramework

**Files:** `Plater.lua`, `Details-Framework/unitframe_midnight.lua`

Plater delegates core castbar creation to `DF:CreateCastBar()` in the DetailsFramework. The framework handles all secret value logic at the mixin level, while Plater adds hooks for customization (colors, scripts, etc.).

### 3.1 Interrupt State (BorderShield)

The DetailsFramework's `UpdateInterruptState`:

```lua
UpdateInterruptState = function(self)
    if (self.Settings.ShowShield) then
        self.BorderShield:Show()
    else
        self.BorderShield:Hide()
    end
    if self.notInterruptible ~= nil then
        self.BorderShield:SetAlphaFromBoolean(self.notInterruptible, 1, 0)
    else
        self.BorderShield:SetAlpha(0)
    end
end,
```

**Key insight:** `notInterruptible` can be:
- A secret boolean (from `UnitCastingInfo` in combat) → `SetAlphaFromBoolean` handles it
- A real `true`/`false` (from `UNIT_SPELLCAST_INTERRUPTIBLE`/`NOT_INTERRUPTIBLE` events) → also works
- `nil` (no cast) → explicit `SetAlpha(0)` fallback

### 3.2 Interruptible/Not-Interruptible Events

```lua
UNIT_SPELLCAST_INTERRUPTIBLE = function(self, unit, ...)
    self.canInterrupt = true
    self.notInterruptible = false        -- real boolean (not secret)
    self:UpdateCastColor()
    self:UpdateInterruptState()
end,

UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(self, unit, ...)
    self.canInterrupt = false
    self.notInterruptible = true         -- real boolean (not secret)
    self:UpdateCastColor()
    self:UpdateInterruptState()
end,
```

**Pattern:** These events fire with real booleans, replacing the secret value stored from `UnitCastingInfo`. The same `UpdateInterruptState` function works for both secret and non-secret values because `SetAlphaFromBoolean` accepts both.

### 3.3 Cast Bar Color with Secret notInterruptible

The DetailsFramework uses `C_CurveUtil.EvaluateColorValueFromBoolean` to blend colors based on secret booleans:

```lua
SplitEvaluateColor = function(state, r1, g1, b1, a1, r2, g2, b2, a2)
    return
        C_CurveUtil.EvaluateColorValueFromBoolean(state, r1, r2),
        C_CurveUtil.EvaluateColorValueFromBoolean(state, g1, g2),
        C_CurveUtil.EvaluateColorValueFromBoolean(state, b1, b2),
        C_CurveUtil.EvaluateColorValueFromBoolean(state, a1 or 1, a2 or 1)
end,
```

Used in `GetCastColor()`:
```lua
if (self.notInterruptible ~= nil) then
    local c = self.Colors.NonInterruptible
    if c then
        r, g, b, a = self.SplitEvaluateColor(self.notInterruptible, c.r, c.g, c.b, c.a, r, g, b, a)
    end
end
```

Then applied:
```lua
UpdateCastColor = function(self)
    local castColor = self:GetCastColor()
    self:GetStatusBarTexture():SetVertexColor(castColor.r, castColor.g, castColor.b, castColor.a)
end,
```

**This is the most elegant pattern found.** Multiple boolean states (casting, channeling, interrupted, notInterruptible) are all layered via `SplitEvaluateColor`, and the entire chain works with secret booleans.

### 3.4 DurationObject Usage

```lua
-- In UpdateCastingInfo:
local durationObject = UnitCastingDuration(unit)
self.durationObject = durationObject
self:SetTimerDuration(durationObject,
    Enum.StatusBarInterpolation.Immediate,
    Enum.StatusBarTimerDirection.ElapsedTime)

-- In UpdateChannelInfo:
local durationObject = isEmpowered
    and UnitEmpoweredChannelDuration(unit, self.Settings.ShowEmpoweredDuration)
    or UnitChannelDuration(unit)
self:SetTimerDuration(durationObject,
    Enum.StatusBarInterpolation.Immediate,
    self.empowered and Enum.StatusBarTimerDirection.ElapsedTime
        or Enum.StatusBarTimerDirection.RemainingTime)

-- Lazy tick (cast time text):
self.percentText:SetText(format("%.1f", self.durationObject:GetRemainingDuration()))
```

### 3.5 Cast Identity

Uses `castBarID` (10th return of `UnitCastingInfo`, `barID`) for cast matching, NOT `castID`:

```lua
UNIT_SPELLCAST_STOP = function(self, unit, ...)
    local unitTarget, castGUID, spellID, castBarID = ...
    if (castBarID == self.castBarID) then
        -- handle stop
    end
end,
```

### 3.6 isTradeSkill Guard

```lua
IsValid = function(self, unit, castName, isTradeSkill, ignoreVisibility)
    if (not self.Settings.ShowTradeSkills) then
        if (not issecretvalue(isTradeSkill) and isTradeSkill) then
            return false
        end
    end
    -- ...
end,
```

### 3.7 Plater-Level Guards

Plater adds additional guards in its hooks:

```lua
-- Version detection
IS_WOW_PROJECT_MIDNIGHT = DF.IsAddonApocalypseWow()

-- Spell name checks
if IS_WOW_PROJECT_MIDNIGHT and not issecretvalue(self.SpellName) then
    -- spell-name-based color/script logic
end

-- CanInterrupt is nil'd on Midnight (relies on framework's UpdateInterruptState instead)
if IS_WOW_PROJECT_MIDNIGHT then
    self.CanInterrupt = nil
else
    self.CanInterrupt = not self.notInterruptible
end

-- Script environment variables
_Duration = not IS_WOW_PROJECT_MIDNIGHT and (endTime - startTime) or nil
_RemainingTime = not IS_WOW_PROJECT_MIDNIGHT and remainingTime or nil

-- Error auto-recovery for user scripts that hit secret values
if errorMessage:find("secret value") then
    errorContext.globalScriptObject.tmpDisabled = true
end
```

---

## 4. ElvUI / oUF

**Files:** `ElvUI_Libraries/.../oUF/elements/castbar.lua`, `ElvUI/.../UnitFrames/Elements/CastBar.lua`

ElvUI's cast bar is built on oUF (object unit frames), which handles the core cast logic. ElvUI layers UnitFrames configuration and callbacks on top.

### 4.1 Interrupt State (Shield)

In oUF `castbar.lua`:

```lua
-- During UNIT_SPELLCAST_START / CHANNEL_START:
if element.Shield then
    if Retail then
        element.Shield:SetAlphaFromBoolean(notInterruptible, element.Shield.alphaValue or 1, 0)
    else
        element.Shield:SetShown(notInterruptible)
    end
end
```

**Version branching:** Uses `SetAlphaFromBoolean` on Retail (12.0+), falls back to `SetShown` on Classic.

### 4.2 Interruptible/Not-Interruptible Events

oUF uses a single handler for both events, deriving the boolean from the **event name** rather than from API return values:

```lua
local function CastInterruptible(self, event, unit)
    local element = self.Castbar
    -- ...
    local notInterruptible = event == 'UNIT_SPELLCAST_NOT_INTERRUPTIBLE'
    element.notInterruptible = notInterruptible

    if element.Shield then
        if Retail then
            element.Shield:SetAlphaFromBoolean(notInterruptible, element.Shield.alphaValue or 1, 0)
        else
            element.Shield:SetShown(notInterruptible)
        end
    end
end
```

**Key insight:** By deriving `notInterruptible` from the event name (a plain string), oUF avoids needing to read any secret values at all. This is simpler than the DetailsFramework approach but less flexible.

### 4.3 Cast Identity

oUF uses `barID` (10th return) as `castID` on Retail:

```lua
-- Retail uses barID (10th return of UnitCastingInfo) as castID
-- because the traditional castID (8th return) is secret
if Retail then
    element.castID = select(10, UnitCastingInfo(unit))  -- barID
else
    element.castID = castID
end
```

### 4.4 Time Handling

```lua
-- Safe time extraction
if oUF:NotSecretValue(startTime) then
    startTime = startTime / 1000
    endTime = endTime / 1000
    element.duration = GetTime() - startTime
    element.max = endTime - startTime
else
    -- secret: set to nil, rely on DurationObject
    element.duration = nil
    element.max = nil
end

-- DurationObject pipeline
local duration = UnitCastingDuration(unit)
if duration then
    element:SetTimerDuration(duration,
        Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
    element.durationObject = duration
end

-- OnUpdate for cast time display
local d = self:GetTimerDuration()
if d then
    local remaining = d:GetRemainingDuration()
    -- format and display
end
```

### 4.5 Target Name Guard

```lua
-- In oUF:
local function UpdateCurrentTarget(element, target)
    if oUF:NotSecretValue(target) then
        element.curTarget = target
    end
end
```

### 4.6 ElvUI UF Layer

ElvUI's `CastBar.lua` adds:

```lua
-- Safe interrupt color selection
function UF:GetInterruptColor(self)
    if E:NotSecretValue(self.notInterruptible) and self.notInterruptible then
        return customColor.colorNoInterrupt or UF.db.colors.castNoInterrupt
    end
    return nil  -- use default color
end

-- Guard spell-specific logic
function UF:PostCastStart(unit)
    if E:IsSecretValue(self.spellID) then
        -- skip spell-specific overrides
        return
    end
    -- normal spell lookup
end

-- Guard target name display
function UF:SetCastText(unit)
    if E:NotSecretValue(targetName) then
        self.Text:SetText(targetName)
    end
end
```

### 4.7 Utility Functions

```lua
-- oUF level
function oUF:NotSecretValue(value)
    return not issecretvalue(value)  -- inverse for readability
end

-- ElvUI level
function E:NotSecretValue(value) return not issecretvalue(value) end
function E:IsSecretValue(value)  return issecretvalue(value) end
```

---

## 5. SUF (NoSelph Fork)

**File:** `modules/cast.lua` (NoSelph/ShadowedUnitFrames, alpha branch)

SUF takes the most complex approach with multiple fallback layers.

### 5.1 Cast Identity with Secret Values

```lua
local function safeCastID(id)
    if issecretvalue(id) then
        return "secret_cast"
    end
    return id
end
```

And for matching:
```lua
local function DoCastsMatch(storedID, ...)
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        if issecretvalue(v) then
            if storedID == "secret_cast" then return true end
        elseif v == storedID then
            return true
        end
    end
    return false
end
```

**Key insight:** When `castID` is secret, SUF stores a sentinel string `"secret_cast"` and matches any future secret castID to it. This is a pessimistic approach — it assumes any secret cast matches the stored one.

### 5.2 Interrupt State (Uninterruptible Overlay)

SUF uses a **separate StatusBar overlay** rather than a single texture with alpha:

```lua
-- During cast start, after setting up main bar:
if hasSecretTimes then
    local durationObj = UnitCastingDuration(unit)
    overlay:SetTimerDuration(durationObj,
        Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
end

-- Control visibility via SetAlphaFromBoolean
overlay:SetAlphaFromBoolean(notInterruptible, 1, 0)
```

The overlay is a full StatusBar that animates in sync with the main cast bar, colored differently to indicate non-interruptibility. `SetAlphaFromBoolean` controls whether it's visible.

### 5.3 Interruptible/Not-Interruptible Events

```lua
function EventInterruptible(self, event, unit, ...)
    castBar.notInterruptible = false
    -- update overlay alpha
    overlay:SetAlphaFromBoolean(false, 1, 0)  -- hide overlay
    -- update colors
end

function EventUninterruptible(self, event, unit, ...)
    castBar.notInterruptible = true
    -- update overlay alpha
    overlay:SetAlphaFromBoolean(true, 1, 0)   -- show overlay
    -- update colors
end
```

### 5.4 Time Handling (Dual Path)

SUF explicitly checks whether times are secret and branches:

```lua
local hasSecretTimes = issecretvalue(startTime) or issecretvalue(endTime)

if hasSecretTimes then
    -- DurationObject path
    local durationObj = UnitCastingDuration(unit)
    castBar:SetTimerDuration(durationObj,
        Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
    -- Also drive the uninterruptible overlay
    overlay:SetTimerDuration(durationObj,
        Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
else
    -- Numeric path (out of combat / Classic)
    startTime = startTime / 1000
    endTime = endTime / 1000
    castBar:SetMinMaxValues(0, endTime - startTime)
    castBar:SetValue(GetTime() - startTime)
end
```

### 5.5 Fake Unit Monitoring

SUF polls for "fake" units (units without real event support, like `targettarget`) using a ticker:

```lua
-- monitorFakeCast uses C_Timer.NewTicker(0.10) to poll
-- Uses DurationObject comparison for determining if cast changed
```

---

## 6. Comparison Matrix

| Feature | Plater/DF | ElvUI/oUF | SUF NoSelph |
|---------|-----------|-----------|-------------|
| **Shield visibility** | `SetAlphaFromBoolean` on BorderShield texture | `SetAlphaFromBoolean` on Shield texture | `SetAlphaFromBoolean` on overlay StatusBar |
| **Shield widget type** | Single `Texture` | Single `Texture` | Full `StatusBar` (animated overlay) |
| **Cast color w/ secret** | `C_CurveUtil.EvaluateColorValueFromBoolean` per RGBA channel | Guard with `E:NotSecretValue()`, skip if secret | Direct boolean check after event replaces value |
| **Interrupt event handler** | Sets `notInterruptible = true/false` (non-secret), calls `UpdateInterruptState` | Derives boolean from event name string | Sets to literal `true/false`, updates overlay |
| **Cast identity** | `castBarID` (10th return) | `barID` (10th return) on Retail | `safeCastID()` sentinel `"secret_cast"` |
| **Time handling** | Always DurationObject (no numeric fallback) | DurationObject + optional numeric when not secret | Dual path: `hasSecretTimes` branching |
| **Cast time text** | `durationObj:GetRemainingDuration()` | `statusBar:GetTimerDuration()` → `:GetRemainingDuration()` | `durationObj:GetRemainingDuration()` |
| **isTradeSkill guard** | `not issecretvalue(isTradeSkill) and isTradeSkill` | Not explicitly guarded (oUF skips trade check) | Guarded |
| **spellID guard** | `issecretvalue(self.SpellName)` / `issecretvalue(self.spellID)` | `E:IsSecretValue(self.spellID)` | `issecretvalue()` |
| **Version detection** | `DF.IsAddonApocalypseWow()` → `IS_WOW_PROJECT_MIDNIGHT` | `Retail` flag (`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`) | Runtime `issecretvalue()` checks |
| **Error recovery** | Auto-disables scripts that cause "secret value" errors | N/A | N/A |
| **API: Important spell** | `C_Spell.IsSpellImportant(spellID)` | Not used | Not used |
| **Empowered channel** | `UnitEmpoweredChannelDuration()` | `UnitEmpoweredChannelDuration()` | `UnitEmpoweredChannelDuration()` |

---

## 7. Notable Patterns for JustAC

### 7.1 `SetAlphaFromBoolean` — Universal Pattern

All three addons use `SetAlphaFromBoolean` for any UI element whose visibility depends on a secret boolean. This is the primary tool for handling `notInterruptible`.

```lua
-- Pattern: show/hide based on secret boolean
widget:SetAlphaFromBoolean(secretBool, alphaWhenTrue, alphaWhenFalse)

-- Examples:
shield:SetAlphaFromBoolean(notInterruptible, 1, 0)        -- show when not interruptible
overlay:SetAlphaFromBoolean(notInterruptible, 0.6, 0)     -- semi-transparent overlay
icon:SetAlphaFromBoolean(isInRange, 1, 0.4)               -- dim when out of range
```

### 7.2 `C_CurveUtil.EvaluateColorValueFromBoolean` — Color from Secret Boolean

Only the DetailsFramework uses this, but it's the most powerful pattern for coloring based on secret state:

```lua
-- Select color per-channel based on secret boolean
local r = C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, rIfTrue, rIfFalse)
local g = C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, gIfTrue, gIfFalse)
local b = C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, bIfTrue, bIfFalse)
texture:SetVertexColor(r, g, b)
```

### 7.3 DurationObject Pipeline — Replace All Manual Time Math

```lua
-- OLD (broken with secret values):
local elapsed = GetTime() - startTime
castBar:SetMinMaxValues(0, endTime - startTime)
castBar:SetValue(elapsed)

-- NEW (secret-safe):
local durationObj = UnitCastingDuration(unit)  -- or UnitChannelDuration(unit)
castBar:SetTimerDuration(durationObj,
    Enum.StatusBarInterpolation.Immediate,
    Enum.StatusBarTimerDirection.ElapsedTime)  -- or .RemainingTime for channels
```

### 7.4 Cast Identity — Use barID, Not castID

```lua
-- castID (8th return) is now secret
-- barID (10th return of UnitCastingInfo, 11th return of UnitChannelInfo) is NOT secret
local _, _, _, _, _, _, _, _, _, barID = UnitCastingInfo(unit)
self.castBarID = barID  -- use for matching in STOP/INTERRUPTED events
```

### 7.5 Guard-Then-Read Pattern

```lua
-- Always check before reading secret values
if not issecretvalue(spellID) then
    -- safe to read, compare, do arithmetic
    local name = C_Spell.GetSpellInfo(spellID).name
else
    -- skip spell-specific logic, use generic fallback
end
```

### 7.6 Event-Derived Booleans Over API Booleans

oUF's pattern of deriving `notInterruptible` from the **event name** rather than from API returns is notable:

```lua
-- The event name itself tells you the state — no secret value involved
local notInterruptible = (event == 'UNIT_SPELLCAST_NOT_INTERRUPTIBLE')
```

This works because `UNIT_SPELLCAST_INTERRUPTIBLE` / `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` events fire as discrete state changes. However, for the initial cast start, `notInterruptible` from `UnitCastingInfo` is still secret and needs `SetAlphaFromBoolean`.

### 7.7 Plater's Defensive `type()` Check

Plater sometimes uses `type()` instead of `issecretvalue()`:

```lua
-- type(secretValue) returns "userdata", type(nil) returns "nil"
if IS_WOW_PROJECT_MIDNIGHT then
    if type(self.spellStartTime) ~= "nil" then
        -- has a value (could be secret or real)
    end
end
```

This is less precise than `issecretvalue()` but useful when you just need to know if anything was returned vs nil.

### 7.8 Synthetic DurationObject (for test/preview modes)

Plater creates synthetic DurationObjects for test mode:

```lua
local durationObject = C_DurationUtil.CreateDuration()
durationObject:SetTimeFromEnd(desiredDuration)
castBar:SetTimerDuration(durationObject,
    Enum.StatusBarInterpolation.Immediate,
    Enum.StatusBarTimerDirection.ElapsedTime)
```

---

## Appendix: New 12.0 APIs Discovered

| API | Returns | Secret? | Notes |
|-----|---------|---------|-------|
| `C_Spell.IsSpellImportant(spellID)` | `boolean` | No | DF uses for orange "important" cast color |
| `C_CurveUtil.EvaluateColorValueFromBoolean(bool, v1, v2)` | secret number | Accepts secret | Per-channel color selection |
| `C_DurationUtil.CreateDuration()` | DurationObject | No | Synthetic duration for test/preview |
| `DurationObject:SetTimeFromEnd(seconds)` | — | — | Set duration countdown |
| `DurationObject:GetRemainingDuration()` | number | Maybe | Remaining time |
| `DurationObject:GetElapsedDuration()` | number | Maybe | Elapsed time |
| `DurationObject:GetTotalDuration()` | number | Maybe | Total duration |
| `StatusBar:SetTimerDuration(durObj, interp, dir)` | — | Accepts secret | Drive bar from DurationObject |
| `StatusBar:GetTimerDuration()` | DurationObject | — | Retrieve stored DurationObject |
| `Widget:SetAlphaFromBoolean(bool, alphaT, alphaF)` | — | Accepts secret | Boolean → alpha pipe |
| `UnitCastingDuration(unit)` | DurationObject | No | Cast duration opaque object |
| `UnitChannelDuration(unit)` | DurationObject | No | Channel duration opaque object |
| `UnitEmpoweredChannelDuration(unit, showHold)` | DurationObject | No | Empowered channel duration |
