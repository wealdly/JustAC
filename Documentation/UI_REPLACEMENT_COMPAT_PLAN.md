# Full UI-replacement compatibility plan

Scope: a player running a single addon suite that replaces the action bars, player/target
unit frames, nameplates and cast bars all at once. Goal is **compatibility** (nothing silently
dead, nothing wrong), not visual integration.

Audited 2026-09-19 against production code (every Blizzard-frame dependency inventoried) and
the replacement suite's current source. **Re-evaluated 2026-09-23** against 5.7.2: every defect
anchor still holds, nothing since 5.5.0 touched them; the keybind fix was re-planned (see P1-2)
and one stock-UI bug surfaced under D2. Nothing exercised in game yet - Phase 0 is that pass
(the suite is not installed in this AddOns folder).

**Phase 1 implemented 2026-09-23** (unreleased), against a local sparse mirror of the suite's
source kept beside the other source mirrors (refreshed by the same script). Offline check:
`python tools/test_addon_bar_keys.py` (fails on the pre-change scanner in exactly the two
cases P1-2 fixes). P1-1 and P1-3 can only be verified in game - Phase 0 item 4.

**Re-evaluated 2026-10-04** (still uncommitted, still on 5.7.2): no other work touched the six
files this change lives in, and nothing else uncommitted adds a Blizzard-frame dependency.
Both mirrors refreshed - the Blizzard UI side has no change to the cast bar, nameplates,
Personal Resource Display or action bars; the suite reworked its button library, unit frames
and nameplates, but every fact relied on above still holds (library major and methods, bind
target on the button config, plate as a `.unitFrame` child carrying `.Health`, Blizzard
nameplate frame and player cast bar hidden the same way). Lint and all offline tests pass.

**In game 2026-09-23, stock UI: no issues** (the suite is not installed here). That covers
the no-regression half of item 4 and the stock-UI fixes (hardcast grey-out timing, empowered
spell in full color). Still unexercised: the replacement-UI branches themselves - addon-bar
keys (offline test only), the overlay on a replaced plate, grey-out with a replaced cast bar,
and Phase 0 items 1-3.

## What already survives (no work)

| Area | Why |
|---|---|
| Queue / rotation | `C_AssistedCombat` + slot APIs only; no action-button frame is ever read. The rotation list comes from the C API, so a suite that edits the game's own manager's cached list (its "hide from the assist highlight" option) does not change what JustAC sees |
| Kick hidden on shielded casts | secret `notInterruptible` -> `SetAlphaFromBoolean` sink, no cast-bar dependency |
| Nameplate cast-bar discovery | replacement plate is a CHILD of the base nameplate and exposes `.Castbar` -> the `childCastbar` branch finds it. The `lowercaseUF` branch does not (it looks for `.castBar`), harmless |
| Oddly-shaped replacement bar | the icon-hidden check requires `HideIconWhenNotInterruptible`, absent on a unit-frame-library bar, so a user-disabled cast icon can NOT read as "uninterruptible" |
| Target-frame dock | `IsStandardTargetFrame` sees stripped events, greys the option, restores saved position |
| Class resources (all but DK) | `DirectPowerRead` = NeverSecret-gated `UnitPower`, no frame involved |
| Soothe / enrage cue on our own icon | an AuraContainer parented to OUR icon, independent of the nameplate |
| Primary keybinds | the suite's bars 1, 3-6, 13-15 reuse the Blizzard binding names |
| Bar editing (hide-from-assist) | `FindSpellSlots` / `ClearSlots` / `PlaceSpells` are slot-API only |
| `AssistedCombatManager` callbacks | the suite uses the manager itself, does not suppress it |

## Defects found

| # | Severity | Where | What happens under a full replacement |
|---|---|---|---|
| D1 | high | `ActionBarScanner.lua:192-292` | Extra paged bars (suite bar 2 = action page 2, bars 7-10 = pages 7-10) carry their OWN binding commands. Those slots are neither mapped nor scanned -> spells there show no hotkey |
| D2 | medium | `UI/UIRenderer.lua:764-780` | Grey-out-while-casting reads `PlayerCastingBarFrame.casting/.channeling`. A replaced player cast bar has all its events unregistered and is hidden under a hidden parent, so both fields freeze at whatever they held -> feature silently dead (or stuck grey, if it was stripped mid-cast). **Also a stock-UI bug**: `.value` is time REMAINING for a channel but time ELAPSED for a cast (`CastingBarFrame.lua:161/185`), so the "ungrey 100ms before the end" check fires during the FIRST 100ms of every hardcast - a flicker at cast start, never the intended early release |
| D3 | medium | `UI/UINameplateOverlay.lua:754` | Overlay anchors to Blizzard's `UnitFrame.HealthBarsContainer`. That frame is hidden + event-stripped but NOT reparented, so the anchor resolves - to an invisible bar, not the one on screen. Icons drift from the visible health bar |
| D4 | low | `UI/UINameplateOverlay.lua:665`, `:484` | CC-list displacement and the nameplate enrage indicator keep mutating the hidden Blizzard children. Invisible, wasted work |
| D5 | low | `StateHelpers.lua:2166` | DK runes: widget reader only. Player-frame bar is dead, and the suite's nameplate module sets `nameplateShowSelf=0` by default, which is the Personal Resource Display's enable CVar -> no live rune source |

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
3. `/jac inspect errors` after one fight. Two things can show up: a taint storm from the suite's
   cooldown-manager skin (degrades exact aura binding to the cast bridge), and one from the suite
   writing into the game's assisted-combat manager (its rotation-list edit is a Lua-field write
   on a Blizzard object - if the manager then errors, our three manager callbacks stop firing
   and the queue falls back to its idle timer). Both are theirs to fix, ours to document.
4. Verify Phase 1: hotkey on a spell placed on suite bar 2 / 7 (D1; `/jac inspect hotkeys`
   walks the chain), overlay icons hugging the suite's health bar with no gap oddity (D3),
   grey-out during a hardcast, a channel and an empower, lifting at the END (D2), and the
   same three on the stock UI unchanged.

## Phase 1 - universal fixes (name-free, help ANY replacement UI)

**P1-1 (D2) Player cast state from the API, not the frame. DONE.** Empowers come back from
`UnitChannelInfo` but grey as a cast with `GetUnitEmpowerHoldAtMaxTime` added, matching the
cast bar. The same read supplies the spell ID, so the event-driven cast/channel ID cache
(and its setters) was deleted; the empowered spell now stays full color, which it never did
(empower start was never cached). The hotkey probe reads the same API. Replace the two field reads in
`ResolvePlayerCastState` with `UnitCastingInfo("player")` / `UnitChannelInfo("player")`;
remaining = `endTimeMS/1000 - GetTime()` for BOTH, which also fixes the elapsed-vs-remaining
bug for hardcasts on the stock UI. Own-unit cast info is plain in combat
(`IsPlayerChanneling` and `PrecombatEngine` already rely on it). Deletes a frame dependency.
Check: grey-out identical on the stock UI; hardcast early-ungrey now happens at the END;
works with a replaced bar.

**P1-2 (D1) Keys from the shared action-button library, not from binding names. DONE**
(`AddLibraryButtonSlots`; the slot map is now also rebuilt on every keybind-cache
invalidation, because it depends on bindings and its first build can predate the addon's
buttons). A button bound through a Blizzard command is skipped - the Blizzard map covers that
family with paging, and a paging bar read mid-shift reports the last form's slot. Every
major bar-replacement addon builds its buttons on the same LibStub library family; each fork
registers under a major name beginning `LibActionButton-1.0` and exposes `lib:GetAllButtons()`,
`button:GetAction()` -> `("action", slot)` and the binding target the button was keyed to
(`button.config.keyBoundTarget`, else `CLICK <name>:<button>`). So, structurally and with no
addon name in code: `LibStub:IterateLibraries()` (bundled LibStub already has it), take every
library whose major starts with that prefix and has `GetAllButtons`, and for each button whose
action is a numeric slot NOT already in the Blizzard slot map, add the slot and resolve its key
with the same `SelectBinding` + `AbbreviateKeybind` path the Blizzard commands use. ~30 lines
in `ActionBarScanner.lua`, all `pcall`'d, looked up lazily on cache rebuild (the bar addon may
load after us). Fill-only: where both agree (bar 1, bars 3-6, 13-15) nothing changes, and the
stock UI finds no library and does nothing.
Why this over scanning binding commands (the 09-19 plan): the slot comes from the button, so a
user-rewritten paging string cannot desync it; it also covers bar addons that bind through
`CLICK <button>` commands, which no binding-name scan can; and the suite's binding file declares
extra commands for bars 13-15 that its buttons do not use, which a name scan would have shown
as live keys. Ceiling: a bar addon that does not use this library still gets nothing - revisit
on a report. Fallback if `IterateLibraries` proves unreliable: the binding-command scan
(`<PREFIX>BAR<n>BUTTON<m>`, bar n = page n, pages without a Blizzard family only).
Check: `/jac inspect validate` line counting library buttons found -> slots mapped -> keyed.

**P1-3 (D3, D4) One plate-anchor resolver. DONE** as `ReplacementHealthBar(nameplate)`:
`nameplate.unitFrame` (lowercase, not Blizzard's `UnitFrame`) carrying `.Health` or
`.healthBar` -> anchor there; else `HealthBarsContainer`; else the plate root. CC displacement
and the enrage indicator return early when it answers. EXISTENCE, not visibility, changed
from the 09-19 plan: the suite shows its plate from the same plate-added event we attach on,
so a visibility read can lose the race, and an anchor resolves on a hidden frame anyway. No
Blizzard nameplate frame is read (its state can be secret). Anchoring to the suite's bar is
not a new protection risk: its plate is built from a plain (non-secure) ping template and is
created in combat, which a protected frame cannot be.
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

- README already says the overlay works with nameplate addons that keep a compatible cast bar.
  Add one line on what degrades under a full UI replacement and the user-side remedy (keep the
  Blizzard player frame or the Personal Resource Display enabled to retain resource-cap and
  damage-intake awareness).
- `UNRELEASED.md`: done with Phase 1 (three Fixed lines). README line still owed at release.

## Not doing

- Visual integration (suite movers, skins, fonts). Requires naming the suite in code, i.e.
  promoting it to an official integration - an owner decision, separate project.
- Bar addons that neither use the shared button library nor Blizzard binding names. Revisit
  on a user report.
- Re-checking the target-frame verdict mid-session. A suite loads at login; the
  `PLAYER_ENTERING_WORLD` invalidation already covers it.
