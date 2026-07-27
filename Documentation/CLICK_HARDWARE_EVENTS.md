# Click hardware events: down and up are two distinct events

## The model

WoW's protected-action system meters casts by **hardware events**, not by
"clicks". Every physical input transition is its own hardware event:

- mouse button **down** = one hardware event
- mouse button **up** = a second hardware event

Each hardware event is allowed to trigger one secure action. A single physical
click therefore carries **two** sanctioned action opportunities. This is fully
within the rules - each action is backed by its own genuine input transition,
so it is not automation; it is the same mechanism Blizzard's own press-and-hold
casting uses.

## What a MOUSE click actually resolves

The two-hardware-events model above is real, but it does **not** give a mouse
click two secure actions. Traced through `Blizzard_FrameXML/SecureTemplates.lua`
(`SecureActionButton_OnClick`), a genuine mouse press on a secure button arrives
with `isKeyPress = false, isSecureAction = true`, so:

```lua
isSecureMousePress = not isKeyPress and isSecureAction   -- true
useOnKeyDown       = not isSecureMousePress and (...)    -- forced FALSE
clickAction        = (down and useOnKeyDown) or (not down and not useOnKeyDown)
                   -- reduces to: not down
```

So for mouse input the action fires **once, on the release, reading `type1`**.
The press does nothing. `typerelease1` is *not* consulted here: the type
attribute is chosen by `(pressType == PRESS_TYPE_HOLD_RELEASE) and "typerelease"
or "type"`, and `PRESS_TYPE_HOLD_RELEASE` is only reached via
`OnActionButtonPressAndHoldRelease`, which needs the `pressAndHoldAction`
attribute or the `ActionButtonUseKeyHeldSpell` CVar.

Consequences for this codebase:

- `RegisterForClicks("AnyDown", "AnyUp")` on the overlay layers is still correct.
  It guarantees the button receives whichever phase resolves, and costs nothing:
  the press is a no-op for the secure action, and it does **not** double-fire.
- A press/release split is **not** available as a mouse-click fallback. Chaining
  two actions onto one mouse click means a secure macro, full stop.

All attributes must be set out of combat (secure frame rules apply as usual).

## Chaining two actions

Use a secure macro: `type1="macro"` + `macrotext` with two slash lines. One
hardware event may run a multi-line macro, and per the section above this is the
only option for mouse-driven buttons. Keybound buttons can additionally use the
`useOnKeyDown` / press-and-hold paths, which is what the split above was written
for - it applies to key presses, not clicks.

## Current usage in JustAC

`UI/UIPrecombatOverlay.lua` (`ConfigureLayer`) chains two actions in two places,
both via macrotext:

- **Recuperate**: `/cancelaura` + `/cast`. A damage tick can interrupt
  Recuperate's heal-over-time while its 30s active aura (and animation) keeps
  running - the stale aura must be cancelled before a re-cast lands.
- **Weapon enhancements** (oil / whetstone / weightstone): `/use item:<id>` +
  `/use 16`. Using the item only arms an "apply to which item?" cursor; the
  enchant lands when a weapon slot is used while it's held. `/use 16` is
  `INVSLOT_MAINHAND` - `SecureCmdItemParse` matches a bare number as a slot, so
  `SecureCmdUseItem` routes it to `UseInventoryItem(16)`, consuming the cursor.

Both must stay macros: these layers are mouse-driven, and per "What a MOUSE
click actually resolves" a press/release split would simply never fire its
release half. If a macro path regresses, debug the macro - do not reach for
`typerelease1`.
