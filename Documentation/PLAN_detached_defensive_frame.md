# Implementation Plan: Detached Defensive Frame
**Feature:** Independent positioning of the defensive queue panel
**Status:** Ready to implement
**Verified against codebase:** 2026-03-07

---

## Goal

Add a `profile.defensives.detached` toggle that, when enabled, gives the defensive icon cluster its own independent draggable frame (`addon.defensiveFrame`), separate from `addon.mainFrame`. When disabled, the existing SIDE1/SIDE2 attached behavior is fully preserved.

---

## Verified Architecture Facts

### Current attachment model
- `addon.mainFrame` — the offensive queue's draggable `UIParent` child. Created in `UIFrameFactory.CreateMainFrame()`. Position saved via `profile.framePosition = {point, x, y}`.
- `addon.grabTab` — a `Button` parented to `addon.mainFrame`. Its `OnDragStart`/`OnDragStop` scripts call `addon.mainFrame:StartMoving(true)` and `UIFrameFactory.SavePosition(addon)`.
- **Defensive icons are children of `addon.mainFrame`** — confirmed at UIFrameFactory.lua:395: `CreateBaseIcon(addon.mainFrame, ...)`. This means they move with mainFrame and must be reparented to detach them.
- Defensive icons are then positioned with `SetPoint(..., addon.mainFrame, ...)` based on SIDE1/SIDE2 and queueOrientation (UIFrameFactory.lua:417–448).
- `healthBarFrame` is parented to `addon.mainFrame` (UIHealthBar.lua:59) and anchored to its edges.
- `petHealthBarFrame` — same pattern.

### Key functions
| Function | File | What it does |
|---|---|---|
| `CreateDefensiveIcons(addon, profile)` | UIFrameFactory.lua:528 | Tears down and rebuilds all defensive icon buttons |
| `CreateSingleDefensiveButton(addon, profile, index, actualIconSize, defPosition, queueOrientation, spacing)` | UIFrameFactory.lua:393 | Creates one defensive button, parents to `addon.mainFrame`, positions relative to it |
| `UIFrameFactory.CreateGrabTab(addon)` | UIFrameFactory.lua:679 | Creates the grab tab, drag callbacks, `SavePosition` call |
| `UIFrameFactory.SavePosition(addon)` | UIFrameFactory.lua:1278 | Reads `mainFrame:GetPoint()`, writes to `profile.framePosition` |
| `UIFrameFactory.UpdateFrameSize(addon)` | UIFrameFactory.lua:1226 | Sets `mainFrame:SetSize()` based on icon count; calls `CreateDefensiveIcons` at end |
| `UIHealthBar.CreateHealthBar(addon)` | UIHealthBar.lua:37 | Creates health bar, parents to `addon.mainFrame`, anchors to its edges using SIDE1/SIDE2 |
| `JustAC:UpdateFrameSize()` | JustAC.lua:1440 | Delegates to `UIFrameFactory.UpdateFrameSize`, then `UIHealthBar.UpdateSize`, then re-applies target frame anchor |

### Module versions (must increment on breaking changes per style guide)
- `UIFrameFactory` current version: **12** → increment to **13**
- `UIHealthBar` current version: **5** → increment to **6**
- `Options` current version: **30** → increment to **31**

---

## Profile Schema Changes

In `JustAC.lua` defaults (the `defensives = { ... }` table, around line 97):

```lua
defensives = {
    enabled = true,
    showProcs = true,
    showHotkeys = true,
    position = "SIDE1",        -- Only used when detached = false
    detached = false,          -- NEW: true = independent frame, false = attached to mainFrame
    detachedPosition = {       -- NEW: saved position for the independent defensive frame
        point = "CENTER",
        x = 100,
        y = -150,
    },
    showHealthBar = true,
    showPetHealthBar = true,
    iconScale = 1.0,
    maxIcons = 4,
    allowItems = true,
    autoInsertPotions = true,
    classSpells = {},
    displayMode = "always",
    glowMode = "all",
},
```

---

## Implementation: UIFrameFactory.lua

Increment version to **13**.

### 1. New `CreateDefensiveGrabTab(addon)` function

Mirror of `CreateGrabTab(addon)` but for `addon.defensiveFrame`. Key differences:
- Parented to `addon.defensiveFrame`
- Drag callbacks call `addon.defensiveFrame:StartMoving(true)` and `UIFrameFactory.SaveDefensivePosition(addon)`
- No target-frame-anchor logic (defensive frame is never target-frame-anchored)
- Tab is always positioned at the right or bottom edge of `addon.defensiveFrame` depending on the defensive icon layout direction (icons always expand right or down from the frame's origin — see layout notes below)
- Store as `addon.defensiveGrabTab`

```lua
local function CreateDefensiveGrabTab(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    local maxIcons = profile and profile.defensives and profile.defensives.maxIcons or 4
    local iconScale = profile and profile.defensives and profile.defensives.iconScale or 1.0
    local iconSize = (profile and profile.iconSize or 42) * iconScale
    local spacing = profile and profile.iconSpacing or 1

    -- Defensive frame is always horizontal (icons expand right), so tab goes on the right.
    local GRAB_TAB_WIDTH = 12
    local GRAB_TAB_HEIGHT = 20

    local tab = CreateFrame("Button", nil, addon.defensiveFrame, "BackdropTemplate")
    if not tab then return end
    tab:SetSize(GRAB_TAB_WIDTH, GRAB_TAB_HEIGHT)
    tab:SetHitRectInsets(-6, -6, -6, -6)
    tab:SetPoint("RIGHT", addon.defensiveFrame, "RIGHT", 0, 0)

    -- Backdrop, dots: copy exactly from CreateGrabTab (vertical dot arrangement)
    tab:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    tab:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
    tab:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

    local dot1 = tab:CreateTexture(nil, "OVERLAY")
    dot1:SetSize(2, 2) ; dot1:SetColorTexture(0.8, 0.8, 0.8, 1)
    dot1:SetPoint("CENTER", tab, "CENTER", 0, 4)
    local dot2 = tab:CreateTexture(nil, "OVERLAY")
    dot2:SetSize(2, 2) ; dot2:SetColorTexture(0.8, 0.8, 0.8, 1)
    dot2:SetPoint("CENTER", tab, "CENTER", 0, 0)
    local dot3 = tab:CreateTexture(nil, "OVERLAY")
    dot3:SetSize(2, 2) ; dot3:SetColorTexture(0.8, 0.8, 0.8, 1)
    dot3:SetPoint("CENTER", tab, "CENTER", 0, -4)

    -- Fade in/out on hover (copy the logic from CreateGrabTab)
    -- ... (identical fade animation setup)

    tab:EnableMouse(true)
    tab:RegisterForDrag("LeftButton")
    tab:RegisterForClicks("RightButtonUp")

    tab:SetScript("OnDragStart", function(self)
        local p = addon:GetProfile()
        if not p then return end
        if p.panelInteraction == "locked" or p.panelInteraction == "clickthrough" then return end
        self.isDragging = true
        addon.isDragging = true
        tab:SetAlpha(1)
        addon.defensiveFrame:StartMoving(true)
    end)

    tab:SetScript("OnDragStop", function(self)
        addon.defensiveFrame:StopMovingOrSizing()
        UIFrameFactory.SaveDefensivePosition(addon)
        self.isDragging = false
        addon.isDragging = false
        -- Trigger icons dirty so they refresh at new position
        if addon.spellsDirty ~= nil then addon.spellsDirty = true end
    end)

    -- Right-click → open options (same as mainFrame right-click)
    tab:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" and Options and Options.OpenOptions then
            Options.OpenOptions()
        end
    end)

    addon.defensiveGrabTab = tab
end
```

### 2. New `UIFrameFactory.SaveDefensivePosition(addon)` function

```lua
function UIFrameFactory.SaveDefensivePosition(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local point, _, _, x, y = addon.defensiveFrame:GetPoint()
    if not point then return end
    profile.defensives.detachedPosition = {
        point = point,
        x = x or 0,
        y = y or -150,
    }
end
```

### 3. New `CreateDetachedDefensiveFrame(addon)` function

```lua
local function CreateDetachedDefensiveFrame(addon)
    local profile = addon:GetProfile()
    if not profile then return end

    -- Destroy previous detached frame if it exists
    if addon.defensiveFrame then
        addon.defensiveFrame:Hide()
        addon.defensiveFrame:SetParent(nil)
        addon.defensiveFrame = nil
        addon.defensiveGrabTab = nil
    end

    local frame = CreateFrame("Frame", "JustACDefensiveFrame", UIParent)
    if not frame then return end
    addon.defensiveFrame = frame

    -- Size will be set by UpdateDefensiveFrameSize after icons are created
    frame:SetSize(42, 42)  -- Placeholder
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    local pos = profile.defensives.detachedPosition
        or { point = "CENTER", x = 100, y = -150 }
    frame:SetPoint(pos.point, pos.x, pos.y)

    -- Right-click for options (consistent with mainFrame behavior)
    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" and Options and Options.OpenOptions then
            Options.OpenOptions()
        end
    end)

    -- Fade animations (copy mainFrame pattern exactly)
    frame:SetAlpha(0)
    frame:Hide()
    local fadeIn = frame:CreateAnimationGroup()
    local fadeInAlpha = fadeIn:CreateAnimation("Alpha")
    fadeInAlpha:SetFromAlpha(0)
    fadeInAlpha:SetToAlpha(1)
    fadeInAlpha:SetDuration(0.15)
    fadeInAlpha:SetSmoothing("IN")
    fadeIn:SetScript("OnFinished", function()
        local p = addon:GetProfile()
        local opacity = p and p.frameOpacity or 1.0
        frame:SetAlpha(opacity)
    end)
    frame.fadeIn = fadeIn

    local fadeOut = frame:CreateAnimationGroup()
    local fadeOutAlpha = fadeOut:CreateAnimation("Alpha")
    fadeOutAlpha:SetFromAlpha(1)
    fadeOutAlpha:SetToAlpha(0)
    fadeOutAlpha:SetDuration(0.15)
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(0)
    end)
    frame.fadeOut = fadeOut

    CreateDefensiveGrabTab(addon)
end
```

### 4. Modify `CreateSingleDefensiveButton` to support detached mode

Currently at line 393. The function signature stays the same; add a parameter or read from profile.

**Key change:** when `profile.defensives.detached` is true, parent icons to `addon.defensiveFrame` and lay them out horizontally from the frame's LEFT edge (index 0 = leftmost, index 1 = second from left, etc.), like how offensive icons are positioned within `mainFrame`.

```lua
local function CreateSingleDefensiveButton(addon, profile, index, actualIconSize, defPosition, queueOrientation, spacing)
    local isDetached = profile.defensives and profile.defensives.detached
    local parentFrame = isDetached and addon.defensiveFrame or addon.mainFrame
    if not parentFrame then return nil end

    local button = CreateBaseIcon(parentFrame, actualIconSize, true, true, profile)
    if not button then return nil end

    button.iconIndex = index

    if isDetached then
        -- Horizontal layout within defensiveFrame: icons expand rightward.
        -- index 0 = first icon (leftmost), index 1 = second, etc.
        -- The frame's LEFT edge is the origin. Grab tab is at the RIGHT edge.
        local iconOffset = index * (actualIconSize + spacing)
        button:SetPoint("LEFT", parentFrame, "LEFT", iconOffset, 0)
    else
        -- Existing SIDE1/SIDE2/LEADING positioning relative to mainFrame
        -- ... (existing code unchanged, lines 402–448)
    end

    return button
end
```

### 5. New `UIFrameFactory.UpdateDefensiveFrameSize(addon)` function

Sets `addon.defensiveFrame:SetSize()` based on icon count, similar to how `UpdateFrameSize` sizes `mainFrame`.

```lua
function UIFrameFactory.UpdateDefensiveFrameSize(addon)
    if not addon.defensiveFrame then return end
    local profile = addon:GetProfile()
    if not profile or not profile.defensives then return end

    local iconScale = profile.defensives.iconScale or 1.0
    local iconSize = profile.iconSize * iconScale
    local maxIcons = profile.defensives.maxIcons or 4
    local spacing = profile.iconSpacing or 1
    local GRAB_TAB_LENGTH = 12
    local GRAB_TAB_SPACING = spacing

    -- Width: icons + spacings + grab tab
    local totalWidth = maxIcons * iconSize + (maxIcons - 1) * spacing + GRAB_TAB_SPACING + GRAB_TAB_LENGTH
    local totalHeight = iconSize

    addon.defensiveFrame:SetSize(totalWidth, totalHeight)
end
```

### 6. Modify `CreateDefensiveIcons(addon, profile)` to call new setup

At the start of `CreateDefensiveIcons`, before creating new icons:

```lua
local function CreateDefensiveIcons(addon, profile)
    -- ... (existing cleanup of old defensiveIcons — unchanged)

    if not profile.defensives or not profile.defensives.enabled then return end

    local isDetached = profile.defensives.detached

    -- If detached mode: ensure defensiveFrame exists
    if isDetached then
        if not addon.defensiveFrame then
            CreateDetachedDefensiveFrame(addon)
        end
        if not addon.defensiveFrame then return end
    end

    -- ... (rest of icon creation loop — unchanged except CreateSingleDefensiveButton now handles routing)

    addon.defensiveIcons = newIcons  -- existing line
    addon.defensiveIcon = newIcons[1] -- existing line

    -- If detached, size the frame to fit the icons
    if isDetached then
        UIFrameFactory.UpdateDefensiveFrameSize(addon)
    end
end
```

### 7. Teardown: when switching from detached → attached, destroy `defensiveFrame`

In the existing cleanup block at the top of `CreateDefensiveIcons`, add:

```lua
-- Destroy detached frame if switching to attached mode (or rebuilding)
if addon.defensiveFrame then
    addon.defensiveFrame:Hide()
    addon.defensiveFrame:SetParent(nil)
    addon.defensiveFrame = nil
    addon.defensiveGrabTab = nil
end
```

This runs unconditionally each time `CreateDefensiveIcons` is called. A new frame will be recreated if `isDetached` is true.

---

## Implementation: UIHealthBar.lua

Increment version to **6**.

In `UIHealthBar.CreateHealthBar(addon)` and `UIHealthBar.CreatePetHealthBar(addon)`:

When `profile.defensives.detached` is true, the health bar should:
- Be parented to `addon.defensiveFrame` instead of `addon.mainFrame`
- Be anchored above `addon.defensiveFrame` (positioned at the frame's TOP edge)
- Use `addon.defensiveFrame`'s width (which already accounts for icon count)

```lua
function UIHealthBar.CreateHealthBar(addon)
    -- ... (existing nil/cleanup logic unchanged)

    local profile = addon:GetProfile()
    local isDetached = profile.defensives and profile.defensives.detached

    if isDetached then
        if not addon.defensiveFrame then return nil end
        local frame = CreateFrame("Frame", nil, addon.defensiveFrame)
        -- ... width/height based on defensiveFrame width
        frame:SetPoint("BOTTOMLEFT", addon.defensiveFrame, "TOPLEFT", 0, BAR_SPACING)
        -- ... rest of health bar setup
        healthBarFrame = frame
        return frame
    else
        -- existing logic anchored to addon.mainFrame (unchanged)
    end
end
```

Apply the same pattern to `CreatePetHealthBar`.

---

## Implementation: UIRenderer.lua

### Show/hide `defensiveFrame` in `RenderSpellQueue`

The existing code shows/hides `addon.defensiveIcons[i]` individually. The `defensiveFrame` itself needs to be shown/hidden when the defensive cluster as a whole appears/disappears.

In `UIRenderer.ShowDefensiveIcons(addon, queue)` — after the icon loop, if `addon.defensiveFrame` exists:

```lua
function UIRenderer.ShowDefensiveIcons(addon, queue)
    if not addon or not addon.defensiveIcons then return end
    local icons = addon.defensiveIcons
    local anyShown = false
    for i, icon in ipairs(icons) do
        local entry = queue[i]
        if entry and entry.spellID then
            local showGlow = (i == 1)
            UIRenderer.ShowDefensiveIcon(addon, entry.spellID, entry.isItem, icon, showGlow)
            anyShown = true
        else
            UIRenderer.HideDefensiveIcon(icon)
        end
    end
    -- Show/hide the detached frame container
    if addon.defensiveFrame then
        if anyShown then
            if not addon.defensiveFrame:IsShown() then
                -- Fade in (mirror mainFrame fade-in pattern)
                if addon.defensiveFrame.fadeIn then
                    addon.defensiveFrame:Show()
                    addon.defensiveFrame:SetAlpha(0)
                    addon.defensiveFrame.fadeIn:Play()
                else
                    addon.defensiveFrame:Show()
                end
            end
        else
            if addon.defensiveFrame:IsShown() then
                if addon.defensiveFrame.fadeOut then
                    addon.defensiveFrame.fadeOut:Play()
                else
                    addon.defensiveFrame:Hide()
                end
            end
        end
    end
end
```

Apply the reverse for `UIRenderer.HideDefensiveIcons(addon)` — also hide `addon.defensiveFrame`.

### Opacity

In the existing `RenderSpellQueue` section that applies `frameOpacity` to `addon.defensiveIcon` (UIRenderer.lua:1591), also apply to `addon.defensiveFrame`:

```lua
if addon.defensiveFrame then
    local isFading = (addon.defensiveFrame.fadeIn and addon.defensiveFrame.fadeIn:IsPlaying())
        or (addon.defensiveFrame.fadeOut and addon.defensiveFrame.fadeOut:IsPlaying())
    if not isFading then
        addon.defensiveFrame:SetAlpha(frameOpacity)
    end
end
```

### Click-through / locked state

In `UIRenderer.RenderSpellQueue`'s panel interaction block (around line 1564 where `defensiveIcons` are iterated for `EnableMouse`), also apply to `addon.defensiveFrame` and `addon.defensiveGrabTab`:

```lua
if addon.defensiveFrame then
    addon.defensiveFrame:EnableMouse(not isClickThrough)
end
if addon.defensiveGrabTab then
    addon.defensiveGrabTab:EnableMouse(not isClickThrough)
    if isLocked then
        addon.defensiveGrabTab:RegisterForClicks()
    else
        addon.defensiveGrabTab:RegisterForClicks("RightButtonUp")
    end
end
```

---

## Implementation: Options/StandardQueue.lua

Increment version to **31**.

### In the Defensive Display sub-tab (tab 3)

**Replace** the combined SIDE1/SIDE2 orientation dropdown (which is currently embedded in the Layout tab as a combined offensive+defensive orientation widget) with two controls:

1. **Detached toggle** (new, order 0):
```lua
detached = {
    type = "toggle",
    name = L["Independent Positioning"],
    desc = L["Move defensive icons independently from the offensive queue. Drag the defensive panel's handle to reposition it."],
    order = 0,
    width = "full",
    get = function() return addon.db.profile.defensives.detached end,
    set = function(_, val)
        addon.db.profile.defensives.detached = val
        addon:UpdateFrameSize()
    end,
    disabled = function() return panelDisabled(addon) or not addon.db.profile.defensives.enabled end,
},
```

2. **Defensive position** (existing SIDE1/SIDE2 dropdown) — wrap in `hidden` so it only shows when not detached:
```lua
hidden = function()
    return addon.db.profile.defensives.detached
end,
```

3. **Reset position button** (new, only visible when detached):
```lua
resetDefPosition = {
    type = "execute",
    name = L["Reset Defensive Frame Position"],
    order = 2,
    width = "normal",
    func = function()
        local def = addon.db.profile.defensives
        def.detachedPosition = { point = "CENTER", x = 100, y = -150 }
        if addon.defensiveFrame then
            addon.defensiveFrame:ClearAllPoints()
            addon.defensiveFrame:SetPoint("CENTER", 100, -150)
        end
    end,
    hidden = function()
        return not addon.db.profile.defensives.detached
    end,
    disabled = function() return panelDisabled(addon) or not addon.db.profile.defensives.enabled end,
},
```

---

## Implementation: JustAC.lua

### On `OnEnable` — position restore

After `UIFrameFactory.CreateMainFrame(self)`, if detached is already enabled from a saved profile, the `defensiveFrame` is created inside `CreateDefensiveIcons` (called from `UpdateFrameSize`). No explicit call needed here — the flow is:

`OnEnable` → `UpdateFrameSize` → `UIFrameFactory.UpdateFrameSize` → `CreateDefensiveIcons` → `CreateDetachedDefensiveFrame` (if detached)

### On `UpdateFrameSize` — defensive frame resizing

`JustAC:UpdateFrameSize()` (line 1440) already delegates to `UIFrameFactory.UpdateFrameSize`. That function calls `CreateDefensiveIcons` at its end. After that call completes, also call:

```lua
function JustAC:UpdateFrameSize()
    if UIFrameFactory and UIFrameFactory.UpdateFrameSize then UIFrameFactory.UpdateFrameSize(self) end
    if UIHealthBar and UIHealthBar.UpdateSize then UIHealthBar.UpdateSize(self) end
    if UIHealthBar and UIHealthBar.UpdatePetSize then UIHealthBar.UpdatePetSize(self) end
    -- NEW: resize the detached defensive frame if it exists
    if UIFrameFactory and UIFrameFactory.UpdateDefensiveFrameSize and self.defensiveFrame then
        UIFrameFactory.UpdateDefensiveFrameSize(self)
    end
    -- ... (existing target frame anchor re-apply)
end
```

### Early-exit guard in `UpdateSpellQueue`

The early-exit check at JustAC.lua:1380 currently tests `defHidden` by checking `#defIcons == 0`. When detached, `defensiveFrame` also needs to be considered:

```lua
local defHidden = (not defIcons or #defIcons == 0)
    and (not self.defensiveFrame or not self.defensiveFrame:IsShown())
```

---

## Localization (Locale files)

Add two new strings:

```lua
L["Independent Positioning"] = "Independent Positioning"
L["Move defensive icons independently from the offensive queue. Drag the defensive panel's handle to reposition it."] = "..."
L["Reset Defensive Frame Position"] = "Reset Defensive Frame Position"
```

---

## What is NOT changing

- `DefensiveEngine.lua` — zero changes (engine is already independent)
- `SpellQueue.lua` — zero changes
- `UINameplateOverlay.lua` — zero changes (overlay has its own separate cluster)
- `UIAnimations.lua` — zero changes
- All defensive icon rendering logic inside `UIRenderer.ShowDefensiveIcon` / `UpdateDefensiveVisualState` — zero changes (they operate on the icon button objects, not on their parent frame)

---

## Behavioral contract

| Setting | Behavior |
|---|---|
| `detached = false` (default) | Exactly current behavior. SIDE1/SIDE2 controls which edge of mainFrame defensives attach to. No `defensiveFrame` exists. |
| `detached = true` | `addon.defensiveFrame` is an independent `UIParent` child. Defensives parent and anchor to it. Health bars anchor to it. `defensiveGrabTab` is the drag handle. Position saved in `profile.defensives.detachedPosition`. The SIDE1/SIDE2 option is hidden in the options panel. |

---

## Implementation order (to minimize breakage)

1. `JustAC.lua` — add `detached` and `detachedPosition` to schema defaults
2. `UIFrameFactory.lua` — add `CreateDetachedDefensiveFrame`, `CreateDefensiveGrabTab`, `SaveDefensivePosition`, `UpdateDefensiveFrameSize`; modify `CreateSingleDefensiveButton` and `CreateDefensiveIcons`
3. `UIHealthBar.lua` — branch on `detached` in `CreateHealthBar` and `CreatePetHealthBar`
4. `UIRenderer.lua` — update `ShowDefensiveIcons` / `HideDefensiveIcons` to manage `defensiveFrame` visibility; add opacity and interaction propagation
5. `JustAC.lua` — update `UpdateFrameSize` to call `UpdateDefensiveFrameSize`; update early-exit guard
6. `Options/StandardQueue.lua` — add detached toggle, hide SIDE1/SIDE2 when detached, add reset button
7. Locale files — add new strings

---

## Style guide compliance notes

- All new variables: `camelCase` (e.g., `isDetached`, `defPos`)
- All new constants: `UPPER_SNAKE_CASE` (e.g., `GRAB_TAB_LENGTH`)
- All new public functions: `UIFrameFactory.FunctionName()`
- All new private functions: `local function functionName()`
- Increment module LibStub version numbers: UIFrameFactory → 13, UIHealthBar → 6, Options → 31
- Max 3 nesting levels; use early returns
- All WoW API calls that can fail: wrap in `pcall`
- All module retrievals: check with `true` parameter and validate before use

---

## File manifest

| File | Change type |
|---|---|
| `JustAC.lua` | Schema defaults + UpdateFrameSize + early-exit guard |
| `UI/UIFrameFactory.lua` | Core frame/tab/position functions + icon routing |
| `UI/UIHealthBar.lua` | Branch on detached for health bar anchoring |
| `UI/UIRenderer.lua` | DefensiveFrame show/hide + opacity + interaction |
| `Options/StandardQueue.lua` | New toggle + reset button + hide SIDE1/SIDE2 when detached |
| Locale `enUS.lua` (or equivalent) | 3 new strings |
