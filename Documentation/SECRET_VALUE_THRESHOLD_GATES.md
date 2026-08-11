# Secret-Value Threshold Gates (WoW 12.0 / 12.1)

**Status:** in use as of 2026-08-10, validated in combat on Feral / Guardian Druid.
**Re-verified against shipping 12.1.0 (build 69214) on 2026-08-11 - unchanged.**
**Underpins:** defensive health bands, execute detection, the wasted-cooldown guard,
pet-heal and top-off cues, DoT pandemic windows, tank mitigation refresh, and the
SimC power / execute / health / stack gates.

> This composes engine behaviour that is almost certainly *not* an intended public
> contract. Assume Blizzard may close it in any patch. This doc exists so a future
> maintainer can recognise the closure, prove it with one command, and fall back
> cleanly.

Companion to [SECRET_VALUE_READINESS_PROBE.md](SECRET_VALUE_READINESS_PROBE.md),
which recovers a **boolean** ("is it active?"). This one recovers a **threshold**
("is it below N?"). That doc's "Do NOT get: the remaining *time*" limitation is
lifted here - see [Superseded claims](#superseded-claims).

---

## The problem

12.0 makes unit health, power, aura duration, aura stacks and cooldown remaining
*secret*: `issecretvalue(v)` is true, and the value cannot be read, compared, or
used in arithmetic. Every question a combat helper actually wants to ask - "am I
below 35%?", "is the target in execute range?", "is this DoT about to fall off?" -
is a **comparison**, which is exactly what secrecy forbids.

## The two primitives

### 1. The zero-gate - "is this secret number zero?"

`C_StringUtil.TruncateWhenZero(v)` accepts a secret and returns **nil for zero**, a
(secret) string otherwise. The engine makes the only decision. Write that into a
scratch `FontString` and read it back: empty text returns **plain nil**, and
truthiness on a secret *string* is legal (the non-boolean rule).

```lua
-- BlizzardAPI/SecretValues.lua : IsSecretZero
if zeroCanClear then zeroScratch:ClearText() end          -- 12.1: drops the Text aspect
zeroScratch:SetText(C_StringUtil.TruncateWhenZero(v) or "")
return not zeroScratch:GetText()                          -- true = the value was zero
```

Returns `true` / `false` / **`nil`** where nil means *no answer* - callers must keep
their fallback and never treat it as a verdict.

> **Gotcha that cost a shipped feature:** `TruncateWhenZero` formats as an integer
> **rounding down**, so any value under 1.0 floors to zero and reads as "zero". Curve
> outputs must therefore be large (100, not 1).

> **Gotcha:** `tostring()` and `string.format("%s", ...)` propagate secrecy
> *silently*; only `table.concat` throws. Reduce anything possibly-secret to a plain
> word before it reaches a chat message.

### 2. The threshold curve - "is this secret value below N?"

The engine will evaluate a curve against a secret and hand back a (secret) result.
Build a curve that maps **below the threshold -> 100** and **at or above -> 0**, then
ask the zero-gate whether the result is zero. No secret is ever compared in Lua - the
engine does the comparing.

```lua
-- BlizzardAPI/StateHelpers.lua : BuildThresholdCurve  (Linear, never Step)
c:AddPoint(0, 100)  c:AddPoint(t - 0.001, 100)
c:AddPoint(t + 0.001, 0)  c:AddPoint(1, 0)
-- then: UnitHealthPercent(unit, false, curve) -> IsSecretZero(result) -> not zero = below
```

**Linear, never Step:** step-curve band semantics cannot be verified from Lua (they
once cost an invisible top-off icon), so the threshold is a steep ramp between two
flat segments - unambiguous under interpolation, and 0.2% wide.

**The curve self-tests before it is trusted.** `curve:Evaluate(x)` takes a *plain* x,
so each curve proves its own shape at build time. A failed self-test disables that one
threshold, so this can be wrong-or-absent but never silently backwards.

## Domains - measured, not assumed

| API | domain | note |
|---|---|---|
| `UnitHealthPercent(unit, usePredicted, curve)` | **0-1 fraction** | not 0-100 |
| `UnitPowerPercent(unit, powerType, unmodified, curve)` | **0-1 fraction** | |
| `LuaDurationObject:EvaluateRemainingPercent(curve, mod)` | **0-1 fraction** | |
| `LuaDurationObject:EvaluateRemainingDuration(curve, mod)` | **seconds** | best fit for SimC `.remains` |
| `LuaDurationObject:EvaluateTotalDuration(curve, mod)` | **seconds** | total, not remaining |

Field proof for the fraction domain: with a cooldown inactive,
`EvaluateRemainingPercent` = `curve(0)` = 100 while `EvaluateElapsedPercent` =
`curve(1)` = 0. A 0-100 curve asked the same questions returns a constant - it carries
no information, which is the tell.

**Epsilon comes from the THRESHOLD, never the domain bound.** A domain-scaled epsilon
on a 3600s range is a 3.6-*second* ramp: it interpolates instead of stepping, and the
returned value can be inverted to recover the exact input. That is a value read, not a
threshold, and it is the one thing this technique must not do.

## Secrecy is per-subject, and it does not matter

| subject | in combat | how it is handled |
|---|---|---|
| cooldown duration | **secret** | zero-gate |
| non-secret player aura (e.g. a raid buff) | **plain** | `IsSecretZero`'s plain fast path |
| secret player aura (e.g. a tank mitigation buff) | **secret** | zero-gate |
| unit health / power | **secret** | zero-gate |

One call covers all of it: `IsSecretZero` short-circuits on plain numbers, so callers
never branch on which mode they are in. **Production must keep using the threshold
form even where the value happens to be plain** - plainness is a property of one
particular aura, not of the API, and the scope rule below applies regardless.

### Getting an aura instance id

Threshold-gating an aura needs its `auraInstanceID`, and the route depends on secrecy:

- `GetPlayerAuraBySpellID(id)` works in combat **only for non-secret auras**. It is
  `RequiresNonSecretAura`, so for a secret aura it returns *nothing* - indistinguishable
  from "not applied" at the call site.
- **Secret auras: go through the Cooldown Manager.** Its viewer runs untainted, may
  legally read the secret aura, and exposes a **plain** `GetAuraSpellInstanceID`. See
  `MaintenanceTracker.FindInstanceViaCooldownManager`, including its staleness rules
  (a hidden viewer serves a stale id forever; never `GetSpellID()`, which is secret).
- **CC auras are free:** `GetUnitAuraInstanceIDs(unit, "HARMFUL|CROWD_CONTROL")` hands
  back plain instance ids directly, skipping the spellID hop entirely.
- Target DoTs: bound at application time from the `UNIT_AURA` batch (`DotTracker`).

## THE SCOPE RULE

These answer **questions**, never **values**.

Asking one threshold to make one decision is what the engine's curve mechanism is
for. Chaining many to binary-search the hidden number back out is precisely what the
secret-value system exists to prevent, would break every legitimate use here when it
got patched, and is not something this addon does. **There is no "what percent is it"
function, and there should not be one.**

Practically: boundaries must come from *what a feature does differently*, never from
wanting resolution. Three health bands exist because the defensive cluster orders
itself three ways - not to locate health within 25%.

The one deliberate exception is diagnostic: `/jac inspect durcurve` has a reveal ramp
whose whole purpose is to test **whether** a value leaks. It reads `secret` in combat,
which is the outcome that keeps the rest of this legitimate.

## Cost

Every distinct `(unit, threshold)` pair is one curve evaluation plus one widget
round-trip, memoised for 0.1s - so roughly 10 evaluations/second each. Hits are table
lookups. `/jac inspect perf` reports hit/miss/evals-per-second.

**Invariant: misses track distinct thresholds x memo windows, NOT queue length.** A
miss count that scales with the number of spells means something is asking per-entry
instead of per-question.

## Verifying it (and detecting closure)

```
/jac inspect textlaunder          -- the zero-gate itself, plus every consumer
/jac inspect durcurve [spellID]   -- durations: both domains, secret-vs-plain, leak test
/jac inspect simcgates [st|aoe]   -- the generated gates, live, with their inputs
/jac inspect perf                 -- gate cost + which health-band source answered
```

Run these after every patch. Closure looks like:

- **zero-gate**: `textlaunder` reports the empty readback as secret, or `GetText()`
  stops returning plain nil for empty -> `IsSecretZero` returns nil everywhere ->
  every consumer falls back. Graceful but total.
- **threshold curves**: `durcurve` columns stop changing as the subject changes (a
  column that never moves is not measuring), or the self-test fails and curves stop
  building.
- **domain change**: the fraction and percent columns swap which one carries
  information. This is the failure that would otherwise be silent.
- **leak**: the reveal ramp prints a number in combat instead of `secret`. That is
  Blizzard's bug, not our licence - do not build on it.

## If Blizzard closes it - fallbacks (in order)

Every consumer already fails to these; nothing needs rewriting to degrade.

1. **The exact percent where the client still offers one** -
   `GetPlayerHealthPercentSafe` in unrestricted contexts.
2. **The LowHealthFrame vignette** - an estimate, and it knows only two levels
   (~35% shown, ~20% critical). `DefensiveEngine` maps those to MAJOR and PANIC and
   deliberately never claims to see the MITIGATE band, because it cannot measure it.
3. **The party health alert keys** - `CombatAudioAlertManager.partyHealthInfo`
   launders one ally-health threshold through plain table keys. One threshold only.
4. **Cast-time projection** - the approach this replaced: time the window from
   `UNIT_SPELLCAST_SUCCEEDED` and use a static or learned duration. Drifts, cannot see
   pandemic rollover or external refreshes, needs a duration DB.
5. **Delegate to AC** - fail open. The queue degrades to Blizzard's order, which still
   reads the real state engine-side.

## Superseded claims

- `SECRET_VALUE_READINESS_PROBE.md` says the remaining **time** is out of reach and
  that `dot.remains < N` "cannot be done this way". True for the scratch-Cooldown
  boolean; **not true** with the threshold curve above. `EvaluateRemainingDuration`
  takes seconds directly. Confirmed in combat 2026-08-10.
- A 2026-07-06 probe filed the durationObject+curve path as **display-only** because
  the result came back secret in combat. That was correct at the time - a secret result
  could not be branched on. The zero-gate is exactly the missing tool, and did not
  exist until 2026-08-10. Same API, new capability.

## Unadopted: the LuaDurationObject predicate surface

Found 2026-08-11. All of this work used only the object's `Evaluate*` methods; it also
carries predicates that may be **simpler than any of the above**:

| method | annotation | if it holds |
|---|---|---|
| `HasSecretValues()` | **`ReturnsNeverSecret = true`** | ask an object whether it holds secrets instead of inferring from a trial read. This one is a stated contract, not a guess. |
| `IsActive()` | no `SecretReturns` | would **supersede the scratch-Cooldown readiness probe entirely** - same answer, one call, no widget round-trip |
| `HasExpired()` / `HasStarted()` / `IsZero()` | no `SecretReturns` | same class |
| `GetRemainingDuration()` / `GetTotalDuration()` | no `SecretReturns` | raw numbers; expect secret wherever the reveal ramp is |

**Deliberately not adopted on the annotation alone.** These docs already under-describe
duration secrecy once - `EvaluateRemainingPercent` carries no `SecretReturns` and
returns secret in combat regardless. Adopting `IsActive()` on the strength of the
annotation risks a *wrong readiness answer*, which is worse than the working probe it
would replace.

All of them print in `/jac inspect durcurve` (direct getters / predicates row), green
for plain and orange for secret. **One in-combat run decides it.** If `IsActive` reads
green there, retiring `DurationObjectActive` is a real simplification of shipped code.

Also unused: **`CurveConstants`** (global, `Blizzard_SharedXMLBase/CurveConstants.lua`)
supplies prebuilt `ZeroToOne`, `ScaleTo100`, `Reverse`, `ReverseTo100` curve objects,
and the percent APIs accept `true` as "use the default curve". Threshold curves still
have to be built, so this only saves construction for identity/scaling ramps.

## Where it is used

| consumer | question |
|---|---|
| `DefensiveEngine` health bands | player below 25 / 50 / 80% - picks the defensive ordering |
| `SpellQueue._StageContext` | target below 20% - execute, and the wasted-cooldown guard |
| `PrecombatEngine` | player below the Top-Off Threshold, out of combat |
| `UIRenderer` pet heal | pet below the Pet Heal Threshold |
| `DotTracker` | DoT inside its pandemic window - **fixes rollover drift the projection could not express** |
| `MaintenanceTracker` | tank mitigation buff inside its refresh window |
| `SpellQueue` SimC gates | power / execute / health / aura-stack conditions from the APLs |
| `BlizzardAPI.ShouldInterruptNow` | cast total length + remaining - kick late in a long cast |
| `BlizzardAPI.IsCrowdControlExpiring` | is the CC about to break |
