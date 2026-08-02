# Secret-Value Readiness Probe (WoW 12.0)

**Status:** in use as of 2026-07-07, validated in combat on Feral Druid.
**Underpins:** the SimC gate layer (cooldown / buff-window / dot conditions) that
refines Blizzard's Assisted Combat fixed queue.

> This technique relies on engine behaviour that is almost certainly *not* an
> intended public contract. Assume Blizzard may close it in any patch. This doc
> exists so a future maintainer can recognise the closure, prove it with one
> command, and fall back cleanly.

## The problem

In 12.0, combat turns resources, aura durations, aura stacks, and **cooldown
remaining** into *secret values*: `issecretvalue(v)` is true and the value cannot be
read, compared, or branched on. A rotation helper that wants to gate an ability on
"is this on cooldown?" or "is my buff up?" has no readable number to test.

## The technique

A `DurationObject` (from `C_Spell.GetSpellCooldownDuration`,
`C_UnitAuras.GetAuraDuration`, etc.) carries a *secret* remaining time. But when it is
fed to a native **Cooldown** widget via `SetCooldownFromDurationObject`, the engine
drives that widget's **shown state** from the duration, and `Cooldown:IsShown()` is a
plain widget boolean - *not* a secret value. So we recover a branchable
"active / not active" without ever touching the secret number.

```lua
-- BlizzardAPI/CooldownTracking.lua : DurationObjectActive
scratchCooldown:SetCooldownFromDurationObject(durObj)   -- engine drives shown state
local active = scratchCooldown:IsShown()                -- plain boolean
scratchCooldown:SetCooldown(0, 0)                        -- reset for reuse
```

The scratch frame lives under a **hidden** holder so it never renders. Each probe
sets -> reads -> resets, so the read always reflects the duration object just fed in.

### What we get / don't get

- **Get:** the boolean "on cooldown?" / "aura active?" - enough to evaluate a gate.
- **Do NOT get:** the remaining *time* (still secret). Anything that needs a number
  (a "% remaining" bar, `dot.remains < N`) is out of reach this way.

### Where it's used

- **cd gate** - `BlizzardAPI.IsSpellOnCooldown(id)` via
  `GetSpellCooldownDuration(id, true)` (the `true` excludes the GCD, so "on a real
  cooldown" is distinguished from "just the GCD").
- **buff-window gate** - `BlizzardAPI.IsBuffWindowActive(id)` via
  `GetPlayerAuraBySpellID(id).auraInstanceID` -> `GetAuraDuration("player", instId)`.
  This replaced a shipped duration DB + local cast-time bookkeeping.
- **dot gate** - same pattern against the target aura instance.

## Verifying it (and detecting closure)

`/jac inspect durprobe [spell]` dumps the probe next to the numeric API. In combat the
numeric `startTime` reads **SECRET** while the probe still reads correctly:

```
Cooldown (ignore-GCD duration object -> IsShown):
  Tiger's Fury (5217)   probe=ON-CD   startTime SECRET   isActive=true   secrecy=2
  Rip (1079)            probe=ready   startTime SECRET   isActive=false
Self-buffs present (aura duration object -> IsShown):
  Tiger's Fury (5217)   probe=ACTIVE
```

**Run this after every patch.** If the technique has been closed you will see one of:

- `probe=nil` everywhere -> the API surface changed (`SetCooldownFromDurationObject`
  gone/renamed, or `GetSpellCooldownDuration` no longer returns a duration object).
- probe **disagrees** with reality (ON-CD when ready, or never ACTIVE) -> the engine
  stopped driving the widget's shown state from the duration, or `IsShown()` itself
  became secret-tainted.

## If Blizzard closes it - fallbacks (in order)

1. **`C_Spell.GetSpellCooldown(id).isActive`** - a separate boolean that is
   **NeverSecret** (readable in combat, validated 2026-07-07). Cheapest cd-ready
   signal, but it does not distinguish a real cooldown from the GCD, so it is coarser
   than the ignore-GCD probe. Good first fallback for the cd gate.
2. **`C_Secrets.GetSpellCooldownSecrecy(id)` / power-secrecy predicates** - ask the
   engine up front which inputs are secret this combat and take the readable path
   where one exists (not every spell/spec is secret).
3. **Local cast-time + duration DB** - the approach this replaced. Time each window
   from `UNIT_SPELLCAST_SUCCEEDED` and look the length up in a generated
   `Data/AuraDurations.lua`. The generator is retained at `tools/gen_aura_durations.py`;
   the runtime tracker is recoverable from git history (removed 2026-07-07 in the commit
   that introduced this probe). Approximate - drifts, can't see external refreshes - but
   needs no probe.
4. **Pandemic-pool hook** - for `dot.refreshable` specifically, hook OnShow/OnHide of
   Blizzard's CooldownViewer pandemic-icon pool frames, which the engine shows exactly
   on real pandemic enter/exit. Turns a secret threshold into an event edge.
5. **Delegate to AC** - fail open. Drop the gate and let the ability surface in priority
   order; Blizzard's Assisted Combat pick (position 1) still reads the real state
   engine-side, so the queue degrades to "AC order" rather than breaking.

## Related engine techniques (secret-safe toolbox)

Surveyed from native-frame trackers; useful if new secret-value problems appear:

- **`StatusBar:SetTimerDuration(durObj, ...)`** - engine-driven bar fill/drain from a
  duration object; motion is computed engine-side, never resampled in Lua.
- **`C_DurationUtil.CreateDurationTextBinding()`** - binds a FontString countdown to a
  duration object, so the number ticks without the addon reading the remaining time.
- **StatusBar threshold fill** - `SetMinMaxValues(n-1, n)` + `SetValue(secretValue)`:
  below N fills 0% (bar hidden), at N fills 100% (bar shown). A native "resource >= N" /
  "at max stacks" *display* detector - but visual only; you cannot branch on it, so a
  resource gate still delegates to AC.
- **`AssistedCombatManager.lastNextCastSpellID`** - Blizzard's already-computed pick as a
  plain table field; read it instead of calling `GetNextCastSpell` on a ticker to avoid
  taint/throttle.
