# Full UI-replacement compatibility plan

Scope: a player running a single addon suite that replaces the action bars, player/target
unit frames, nameplates and cast bars all at once. Goal is **compatibility** (nothing silently
dead, nothing wrong), not visual integration.

Audited 2026-09-19 against production code (every Blizzard-frame dependency inventoried) and
the replacement suite's current source. Nothing here has been exercised in game yet - Phase 0
is that pass.

## What already survives (no work)

| Area | Why |
|---|---|
| Queue / rotation | `C_AssistedCombat` + slot APIs only; no action-button frame is ever read |
| Kick hidden on shielded casts | secret `notInterruptible` -> `SetAlphaFromBoolean` sink, no cast-bar dependency |
| Nameplate cast-bar discovery | replacement plate is a CHILD of the base nameplate and exposes `.Castbar` -> the `childCastbar` branch finds it. The `lowercaseUF` branch does not (it looks for `.castBar`), harmless |
| Oddly-shaped replacement bar | the icon-hidden check requires `HideIconWhenNotInterruptible`, absent on a unit-frame-library bar, so a user-disabled cast icon can NOT read as "uninterruptible" |
| Target-frame dock | `IsStandardTargetFrame` sees stripped events, greys the option, restores saved position |
| Class resources (all but DK) | `DirectPowerRead` = NeverSecret-gated `UnitPower`, no frame involved |
| Soothe / enrage cue on our own icon | an AuraContainer parented to OUR icon, independent of the nameplate |
| Primary keybinds | the suite's bars 1, 3-6, 13-15 reuse the Blizzard binding names |
| `AssistedCombatManager` callbacks | the suite uses the manager itself, does not suppress it |

## Defects found

| # | Severity | Where | What happens under a full replacement |
|---|---|---|---|
| D1 | high | `ActionBarScanner.lua:193-293` | Extra paged bars (suite bar 2 = action page 2, bars 7-10 = pages 7-10) carry their OWN binding commands. Those slots are neither mapped nor scanned -> spells there show no hotkey |
| D2 | medium | `UI/UIRenderer.lua:777-793` | Grey-out-while-casting reads `PlayerCastingBarFrame.casting/.channeling`. A replaced player cast bar is `SetUnit(nil)`'d, which nils both fields and unregisters its events -> feature silently dead |
| D3 | medium | `UI/UINameplateOverlay.lua:753` | Overlay anchors to Blizzard's `UnitFrame.HealthBarsContainer`. That frame is hidden + event-stripped but NOT reparented, so the anchor resolves - to an invisible bar, not the one on screen. Icons drift from the visible health bar |
| D4 | low | `UI/UINameplateOverlay.lua:669`, `:484` | CC-list displacement and the nameplate enrage indicator keep mutating the hidden Blizzard children. Invisible, wasted work |
| D5 | low | `StateHelpers.lua:1981-2005` | DK runes: widget reader only. Player-frame bar is dead, and the suite's nameplate module sets `nameplateShowSelf=0` by default, which is the Personal Resource Display's enable CVar -> no live rune source |

## Hard limits (document, do not chase)

- `IsPrimaryPowerCapped` / `IsActivelyTakingDamage` read engine-driven widgets inside the
  Blizzard player frame. Hidden frame -> permanent `false` (fail-open by design). No other source.
- CC-for-kick substitution needs an UNTAINTED Blizzard cast bar. Replaced plate -> no suggestion
  instead of a CC (never a wrong kick). Possibly recoverable, see P2-1.
- Nameplate enrage indicator = a repositioned Blizzard buff list. Gone on a replaced plate.

## Phase 0 - in-game baseline (no code)

All suite modules ON. Record results in this file.

1. `/jac inspect castdiag` on one kickable and one shielded cast. Note: discovered-bar source
   (expect `childCastbar`), hidden-Blizzard-bar liveness (expect dead), and the shield-alpha
   zero-gate row for the discovered bar. That last row decides P2-1.
2. `/jac inspect frames` on a DK in combat - raw `UnitPower` rune read vs actual ready runes. Decides P2-2.
3. `/jac inspect errors` after one fight with the suite's cooldown-manager skin on. Any taint
   storm there degrades exact aura binding to the cast bridge (theirs to fix, ours to document).
4. Eyeball: hotkey on a spell placed on suite bar 2 / 7 (D1), overlay alignment (D3), grey-out
   during a hardcast (D2).

## Phase 1 - universal fixes (name-free, help ANY replacement UI)

**P1-1 (D2) Player cast state from the API, not the frame.** Replace the two field reads in
`ResolvePlayerCastState` with `UnitCastingInfo("player")` / `UnitChannelInfo("player")`;
early-ungrey from `endTimeMS/1000 - GetTime()`. Own-unit cast info is plain in combat
(`IsPlayerChanneling` already relies on it). Deletes a frame dependency outright.
Check: grey-out + 100ms early-ungrey identical on the stock UI; works with a replaced bar.

**P1-2 (D1) Extra paged-bar bindings, discovered structurally.** In `RebuildBindingCache`, one
`GetNumBindings()` pass collecting commands shaped `<PREFIX>BAR<n>BUTTON<m>` that are not
Blizzard's (`MULTIACTIONBAR*` excluded - its n is not a page) and have a key bound; bar n ->
action page n. In `GetCachedSlotMapping`, lay those in FIRST so main-bar / form-page / multibar
mappings overwrite them (a druid's page 7 is the cat bar and must stay `ACTIONBUTTON*`).
Bars with zero bound keys are skipped, so the stock UI scans nothing extra.
No addon name appears in code. Ceiling: assumes bar number == action page (the suite's
default; a user-rewritten paging string can break it -> wrong key, only on those extra bars).
Fallback if the enumeration proves unreliable: a literal list of the five command prefixes,
which needs an owner ruling on the no-names rule.
Check: `assert`-style self-test of the command-pattern parser in `/jac inspect validate`.

**P1-3 (D3, D4) One plate-anchor resolver.** `ResolvePlateAnchor(nameplate)` ->
Blizzard `HealthBarsContainer` when `UnitFrame` is shown; else a shown
`nameplate.unitFrame.Health`; else the nameplate root (today's fallback). Returns a second
value "isBlizzard"; CC displacement and the enrage indicator early-return when it is false.
`IsShown` pcall'd, failure = Blizzard (status quo).
Check: stock plates pixel-identical; replaced plates hug the visible bar; right-side gap
constants (`NAMEPLATE_GAP_*`) are tuned to Blizzard art and may need a zero variant.

## Phase 2 - conditional on Phase 0

- **P2-1** If the shield-alpha zero-gate answered on the discovered bar AND agreed with the
  icon-hidden verdict on stock bars: add it to the cascade for non-Blizzard bars only. Otherwise
  the hard limit stands.
- **P2-2** If `UnitPower` rune semantics match ready runes: add `DEATHKNIGHT` to `DIRECT_POWER`
  (the code already flags this as pending a DK session). Fixes D5 for every UI.
- **P2-3** `nameplateShowEnemies`: we force it on for the overlay; the suite can toggle it on
  combat enter/leave. Act only if a fight is observed.

## Phase 3 - player-facing

- README compatibility note: what degrades under a full UI replacement and the user-side
  remedy (keep the Blizzard player frame or the Personal Resource Display enabled to retain
  resource-cap and damage-intake awareness).
- `UNRELEASED.md`: "Keybinds now show for spells on additional action bars added by
  action-bar addons", "Casting grey-out works with a replaced player cast bar", "Nameplate
  overlay lines up with replacement nameplates".

## Not doing

- Visual integration (suite movers, skins, fonts). Requires naming the suite in code, i.e.
  promoting it to an official integration - an owner decision, separate project.
- `CLICK <button>:<btn>` binding resolution for OTHER bar addons. Different problem (needs
  per-addon button names); revisit on a user report.
- Re-checking the target-frame verdict mid-session. A suite loads at login; the
  `PLAYER_ENTERING_WORLD` invalidation already covers it.
