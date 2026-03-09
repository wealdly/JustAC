# Plan: Detached Defensive Frame (v3)

**Feature:** Independent positioning of the defensive queue panel
**Status:** Ready to implement (reviewed 2026-03-08)
**Supersedes:** v1 plan (2026-03-07)

---

## Goal

Add a `defensives.detached` toggle that gives the defensive icon cluster its own independent, draggable frame separate from `mainFrame`. When enabled, defensives render regardless of `displayMode` — enabling mix/match like "offensives on overlay, floating defensives." Health bars follow the defensive frame. Overlay defensives remain independent. The toggle lives in the General tab alongside `displayMode`.

---

## Steps

### Phase 1: Schema & Profile Defaults
1. Add `defensives.detached` (bool, default false) and `defensives.detachedPosition` ({point, x, y}) to defaults in JustAC.lua (~line 97)
2. Add `defensives.detachedOrientation` (string, default "LEFT") to defaults — controls icon growth direction of the detached frame

### Phase 2: UIFrameFactory — Detached Frame Infrastructure
3. Increment UIFrameFactory LibStub version 12 → 13
4. Add `CreateDetachedDefensiveFrame(addon)` — creates `addon.defensiveFrame` as a `UIParent` child with movable/clamped behavior, fade animations (mirror `CreateMainFrame` pattern)
5. Add `CreateDefensiveGrabTab(addon)` — creates `addon.defensiveGrabTab`, a drag handle for `defensiveFrame`. Position based on `detachedOrientation` (same logic as main grab tab: right edge for LEFT, left for RIGHT, bottom for UP, top for DOWN). Full pattern at UIFrameFactory.lua lines 679-850.
6. Add `UIFrameFactory.SaveDefensivePosition(addon)` — reads `defensiveFrame:GetPoint()`, writes to `profile.defensives.detachedPosition`
7. Add `UIFrameFactory.UpdateDefensiveFrameSize(addon)` — sets `defensiveFrame:SetSize()` based on icon count, orientation, and grab tab space
8. Modify `CreateSingleDefensiveButton` — when `profile.defensives.detached`, parent icons to `addon.defensiveFrame` and lay out based on `detachedOrientation` instead of SIDE1/SIDE2 relative to `mainFrame`
9. **CRITICAL — Decouple `CreateDefensiveIcons` from `CreateSpellIcons`:**
   - Currently `CreateDefensiveIcons` is called at the END of `CreateSpellIcons` (UIFrameFactory.lua line 1107), which guards on `addon.mainFrame`. This couples defensive creation to offensive creation.
   - Fix: Remove the `CreateDefensiveIcons(addon, profile)` call from `CreateSpellIcons`.
   - Instead, call `CreateDefensiveIcons` from `UIFrameFactory.UpdateFrameSize` AFTER `CreateSpellIcons` returns. This way both calls happen in the same place but defensives are no longer gated by `CreateSpellIcons`'s `mainFrame` guard.
   - When detached, `CreateDefensiveIcons` calls `CreateDetachedDefensiveFrame` before icon creation, then `UpdateDefensiveFrameSize` after. When attached, it parents to `mainFrame` as before.
   - Unconditionally destroy `addon.defensiveFrame` at cleanup in `CreateDefensiveIcons` (a new frame is created if needed). (*depends on 4, 5, 7, 8*)

### Phase 3: UIHealthBar — Reparent When Detached
10. Increment UIHealthBar LibStub version 7 → 8
11. Modify `CreateHealthBar` — when `detached`, parent to `addon.defensiveFrame` instead of `addon.mainFrame`. Anchor above `defensiveFrame` using `detachedOrientation` for positioning. Keep `addon.mainFrame` guard as fallback for attached mode.
12. Modify `CreatePetHealthBar` — same pattern as step 11. Currently guards on `addon.mainFrame` at line 458 and parents at line 476.
13. Modify `ResizeToCount` — when `detached`:
    - For `visibleCount > 0`: size and anchor based on `defensiveFrame` width and `detachedOrientation`
    - For `visibleCount == 0`: **hide the health bar** (no fallback to offensive dims — on the detached frame there's no offensive context to fall back to). This is simpler than the current attached behavior where it falls back to offensive queue dims at UIHealthBar.lua lines 340-370.

### Phase 4: UIRenderer — Independent Defensive Rendering
14. **CRITICAL — Decouple defensive per-frame updates from offensive guards:**
    - Currently `RenderSpellQueue` (UIRenderer.lua) has this flow:
      ```
      line 992: if not spellIconsRef then return end  ← early exit
      line 1027-1052: compute isChanneling/isCasting/channelSpellID (module-level vars)
      line 1056: compute shouldUpdateCooldowns
      line 1064-1113: defensive icon loop (visual state, hotkeys, cooldowns)
      line 1255+: if shouldShowFrame then ... offensive icon rendering
      ```
    - The defensive icon loop at line 1064 reads module-level `isChanneling`/`channelSpellID` (set at line 1027) for grey-out during channels. It also reads `shouldUpdateCooldowns` (set at line 1056).
    - Fix: Restructure `RenderSpellQueue` so that the channeling state computation AND the defensive icon loop run BEFORE the `spellIconsRef` guard. New flow:
      ```
      1. profile + time setup (no dependency on spellIcons)
      2. Compute isChanneling/isCasting/channelSpellID
      3. Compute shouldUpdateCooldowns
      4. Run defensive icon loop (uses addon.defensiveIcons, no spellIcons dependency)
      5. if not spellIconsRef then return end  ← offensive-only guard moves here
      6. Offensive icon rendering (unchanged)
      ```
    - This ensures defensive visual updates run even if `spellIcons` were ever nil.
15. Modify `ShowDefensiveIcons` — when `addon.defensiveFrame` exists, show/hide the frame container with fade animations (show when any icon visible, hide when all hidden)
16. Modify `HideDefensiveIcons` — also hide `addon.defensiveFrame` with fade-out. This covers vehicle mode (UpdateDefensiveCooldowns calls HideDefensiveIcons at JustAC.lua line 756) so the empty container doesn't linger.
17. Fix pre-existing opacity bug: apply `frameOpacity` to `addon.defensiveFrame` (when detached) or to ALL `defensiveIcons` (not just `defensiveIcon[1]`). Current code at UIRenderer.lua line 1676 only applies to `addon.defensiveIcon` (legacy single-icon reference).
18. Add click-through / locked state propagation for `addon.defensiveFrame` and `addon.defensiveGrabTab` in the panel interaction block (~line 1620)

### Phase 5: JustAC.lua — Lifecycle Integration
19. Modify `UpdateFrameSize` — after existing calls, also call `UIFrameFactory.UpdateDefensiveFrameSize(self)` if `self.defensiveFrame` exists
20. Modify the early-exit guard in `OnUpdate` (~line 1388) — `defHidden` should also consider `self.defensiveFrame:IsShown()` so the update loop doesn't idle when only the detached frame is visible:
    ```lua
    local defHidden = (not defIcons or #defIcons == 0)
        and (not self.defensiveFrame or not self.defensiveFrame:IsShown())
    ```
21. Ensure `OnEnable` flow works: `UpdateFrameSize` → `CreateSpellIcons` + `CreateDefensiveIcons` (now separate calls) → `CreateDetachedDefensiveFrame` (if detached) — no explicit call needed
22. Add comment to `UpdateSpellQueue`'s `mainFrame` guard (line 873) clarifying it doesn't gate defensives because mainFrame always exists (created unconditionally in `OnEnable`)
23. **Modify `EnterDisabledMode` (line 604):** Also hide `self.defensiveFrame` if it exists (currently only hides `mainFrame` and iterates `defensiveIcons`). Without this, the detached frame container stays visible when entering healer-spec auto-disable.
24. **Modify `ExitDisabledMode` (line 635):** Also restore `self.defensiveFrame` visibility. Currently only shows `mainFrame` and restores health bars. The detached frame would remain hidden after re-enabling without this.
25. **Modify `RefreshConfig` (line 662):** After restoring `mainFrame` position from `profile.framePosition`, also restore `defensiveFrame` position from `profile.defensives.detachedPosition`. Current code (line 672-675) only handles mainFrame. On profile change/copy, the detached frame would keep the old profile's position without this fix.

### Phase 6: Options — General Tab + Standard Queue Adjustments
26. In `Options/General.lua` Settings subtab, add `defensives.detached` toggle (order 25, in the available gap) with description: "Give defensive icons their own independent draggable frame"
27. In `Options/General.lua`, add `defensives.detachedOrientation` dropdown (order 26, hidden when `detached = false`) with values LEFT/RIGHT/UP/DOWN
28. In `Options/General.lua`, add "Reset Defensive Position" execute button (order 27, hidden when `detached = false`)
29. Fix `panelDisabled()` in `Options/StandardQueue.lua` — the Defensive Display subtab should NOT be disabled when `detached = true`, even if `displayMode = "overlay"` or `"disabled"`. Add a new `defensiveDisabled()` helper:
    ```lua
    local function defensiveDisabled(addon)
        local profile = addon.db.profile
        if profile.defensives and profile.defensives.detached then
            return false  -- detached defensives are always configurable
        end
        return panelDisabled(addon)
    end
    ```
30. In `Options/StandardQueue.lua` Layout subtab, hide the defensive-side portion of the combined orientation dropdown when `detached = true`
31. In `Options/StandardQueue.lua` Layout reset button, skip `defensives.position` reset when detached
32. Increment Options/StandardQueue LibStub version 2 → 3

### Phase 7: Localization
33. Add new strings to locale files: "Independent Positioning", description text, "Reset Defensive Frame Position", "Detached Orientation" (and desc), orientation values if different from existing

---

## Relevant Files

- `JustAC.lua` — Schema defaults (line ~97 defensives block), `UpdateSpellQueue` (line 873, mainFrame guard), `UpdateFrameSize` (line 1449), OnUpdate early-exit guard (line 1388), `EnterDisabledMode` (line 604), `ExitDisabledMode` (line 635), `RefreshConfig` (line 662)
- `UI/UIFrameFactory.lua` — `CreateSingleDefensiveButton` (line 403), `CreateDefensiveIcons` (line 546), `CreateSpellIcons` (line 1058, calls CreateDefensiveIcons at line 1107), `CreateMainFrame` (line 610) as template, `CreateGrabTab` (lines 679-850) as template, `UpdateFrameSize` (line 1226, needs to call CreateDefensiveIcons separately)
- `UI/UIHealthBar.lua` — `CreateHealthBar` (line 37, guards mainFrame at line 47, parents at line 63), `CreatePetHealthBar` (guards at line 458, parents at line 476), `ResizeToCount` (line 315, zero-count fallback at lines 340-370)
- `UI/UIRenderer.lua` — `RenderSpellQueue` (line 989, spellIconsRef guard at 992, channeling state at 1027, defensive loop at 1064, shouldShowFrame block at 1255), `ShowDefensiveIcons` (line 932), `HideDefensiveIcons` (line 944), opacity block (line 1676, only applies to defensiveIcon not defensiveIcons[]), panel interaction block (line 1620)
- `Options/General.lua` — Settings subtab, order 25 available for detached toggle
- `Options/StandardQueue.lua` — `panelDisabled()` (line 13), combined orientation dropdown (line 96), Defensive Display subtab (line 475)
- `KeyPressDetector.lua` — References `addon.defensiveIcons` (line 135) and `addon.defensiveIcon` (line 145), no mainFrame dependency. SAFE.
- Locale files (enUS.lua and others)

---

## Verification

1. `/jac modules` — All modules load with incremented versions (UIFrameFactory v13, UIHealthBar v8, StandardQueue v3)
2. Toggle detached ON → defensive icons appear in a separate draggable frame with grab tab
3. Toggle detached OFF → defensives reattach to mainFrame at SIDE1/SIDE2 position as before
4. Set `displayMode = "overlay"` + `detached = true` → offensive queue hidden on standard panel, defensive frame visible and draggable, overlay shows offensives
5. Set `displayMode = "overlay"` + `detached = true` → General tab detached toggle is accessible and NOT greyed out
6. Set `displayMode = "overlay"` + `detached = true` → Standard Queue → Defensive Display settings (icon count, scale, glow) are accessible and NOT greyed out
7. Set `displayMode = "disabled"` + `detached = true` → defensive frame still visible (detached defensives are independent of displayMode)
8. Drag the detached frame → `/reload` → frame restores saved position
9. Switch profiles → detached frame moves to new profile's saved position
10. Verify health bar parents to detached frame and resizes correctly
11. Health bar hides when visibleCount == 0 on detached frame (no fallback to offensive dims)
12. Panel interaction modes (locked, click-through) apply to detached frame and grab tab
13. `frameOpacity` slider affects detached frame and ALL defensive icons (not just first)
14. Detached orientation dropdown: test all 4 directions, verify grab tab repositions correctly
15. Overlay defensives work independently — `nameplateOverlay.showDefensives` unaffected by detached toggle
16. Defensive visual states update during channeling (grey-out) when `displayMode = "overlay"` + `detached = true`
17. Defensive cooldown swipes animate correctly when offensives are hidden
18. Enter healer spec (disabled mode) → detached frame hides along with everything else
19. Switch back to DPS spec (exit disabled mode) → detached frame reappears
20. Vehicle/possess mode → detached frame hides (HideDefensiveIcons hides container)
21. Key press flash works on detached defensive icons (KeyPressDetector scans addon.defensiveIcons)

---

## Decisions

- **Option C for options placement:** Detached toggle + orientation + reset in General tab (order 25-27); defensive appearance settings stay in Standard Queue → Defensive Display
- Detached frame gets its own orientation dropdown (not hardcoded horizontal)
- Health bars move to detached frame (not duplicated on both surfaces)
- Health bar hides when visibleCount == 0 on detached frame (no offensive-queue fallback)
- Overlay defensives remain completely independent — `detached` only affects the main-panel defensive cluster
- Pre-existing opacity bug (only applied to first defensive icon) fixed as part of this work
- `panelDisabled()` gets a carve-out via `defensiveDisabled()` so Defensive Display subtab is reachable when detached + any displayMode
- `CreateDefensiveIcons` decoupled from `CreateSpellIcons` — called separately from `UpdateFrameSize`
- Defensive per-frame loop in `RenderSpellQueue` moved before `spellIconsRef` guard
- **`displayMode = "disabled"` + `detached = true` → defensives still render.** Detached defensives are fully independent of displayMode. Only `EnterDisabledMode` (healer spec auto-disable) hides everything.

---

## Dependency Analysis: "Defensives Shown, Offensives Hidden"

| Path | Status | Detail |
|------|--------|--------|
| `UpdateSpellQueue` mainFrame guard (line 873) | SAFE | mainFrame always exists (created in OnEnable). Comment added (step 22). |
| `RenderSpellQueue` spellIconsRef guard (line 992) | FIXED | Defensive loop moved before guard (step 14) |
| `CreateDefensiveIcons` in `CreateSpellIcons` (line 1107) | FIXED | Extracted to separate call (step 9) |
| `isChanneling`/`channelSpellID` module-level vars | FIXED | Computed before defensive loop (step 14) |
| `DefensiveEngine.OnHealthChanged` | SAFE | No mainFrame dependency |
| `ApplyMainPanelQueue` / `HideDefensiveIconFrames` | SAFE | No mainFrame dependency |
| `ForceUpdate` / `ForceUpdateAll` | SAFE | No guards, just sets dirty flags |
| OnUpdate early-exit guard | FIXED | Includes defensiveFrame visibility (step 20) |
| `EnterDisabledMode` | FIXED | Now hides defensiveFrame (step 23) |
| `ExitDisabledMode` | FIXED | Now shows defensiveFrame (step 24) |
| `RefreshConfig` profile restore | FIXED | Now restores defensiveFrame position (step 25) |
| `UpdateDefensiveCooldowns` vehicle check | FIXED | HideDefensiveIcons hides container (step 16) |
| `ResizeToCount` zero-count fallback | FIXED | Hides bar instead of offensive fallback (step 13) |
| `KeyPressDetector` | SAFE | Scans addon.defensiveIcons array, no mainFrame ref |
| `TargetFrameAnchor` | SAFE | Geometry-based, no defensive dependency |
| Masque integration | SAFE | Frame-agnostic (RemoveButton/AddButton) |

---

## What is NOT Changing

- `DefensiveEngine.lua` — zero changes (engine is independent)
- `SpellQueue.lua` — zero changes
- `UINameplateOverlay.lua` — zero changes (overlay has its own defensive pipeline)
- `UIAnimations.lua` — zero changes
- `Options/Overlay.lua` — zero changes (overlay defensive settings are independent)
- `Options/Defensives.lua` — zero changes (spell list management unaffected)
- `KeyPressDetector.lua` — zero changes (already scans defensiveIcons array, no mainFrame ref)
- `TargetFrameAnchor.lua` — zero changes (geometry-based, no defensive dependency)

---

## Further Considerations

1. **Target frame anchor + detached:** Independent. Offensives can anchor to target frame while defensives float.
2. **Profile switching:** Detached position is per-profile. Switching profiles restores position (step 25).
3. **Future:** Per-surface queue type selection already supported via existing toggles. Detached fills the last gap.