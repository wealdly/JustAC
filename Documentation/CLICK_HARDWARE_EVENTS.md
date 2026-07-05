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

## Wiring two actions onto one click (secure buttons)

`RegisterForClicks` decides which transitions fire the button:

```lua
button:RegisterForClicks("AnyDown", "AnyUp")   -- BOTH transitions fire, separately
```

With both registered, the secure template resolves a separate attribute set per
phase (added alongside Blizzard's press-and-hold support):

| Phase | Type attribute | Fires on |
|-------|----------------|----------|
| press | `type1` | mouse-down |
| release | `typerelease1` | mouse-up |

Example - cancel a stale aura on the press, re-cast the spell on the release,
from one physical click:

```lua
button:RegisterForClicks("AnyDown", "AnyUp")
button:SetAttribute("type1", "cancelaura")      -- down: clear the stale aura
button:SetAttribute("unit", "player")
button:SetAttribute("spell", spellName)
button:SetAttribute("typerelease1", "spell")    -- up: re-cast
```

All attributes must be set out of combat (secure frame rules apply as usual).

## When to reach for this

The first choice for chaining two actions is a secure macro
(`type1="macro"` + `macrotext` with two slash lines) - one hardware event may
run a multi-line macro. Use the down/up split when:

- macro chaining misbehaves on a given button (this codebase has previously
  seen left-click-only macros fail to activate reliably on overlay click
  layers - see the header comment in `UI/UIPrecombatOverlay.lua`), or
- the two actions must not share one macro body (e.g. the second action needs
  its own targeting resolution), or
- press/release semantics are genuinely wanted (hold-to-preview patterns).

## Current usage in JustAC

`UI/UIPrecombatOverlay.lua` (`ConfigureLayer`): the Recuperate click layer
chains `/cancelaura` + `/cast` via macrotext, because a damage tick can
interrupt Recuperate's heal-over-time while its 30s active aura (and
animation) keeps running - the stale aura must be cancelled before a re-cast
lands. If that macro path regresses, the down/up split above is the documented
fallback.
