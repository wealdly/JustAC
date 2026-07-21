# Identifying a specific aura in 12.0 combat

**Status: CONDITIONAL.** Exact identity IS obtainable in combat, by two routes - but neither
covers a `ContextuallySecret` aura in the default UI configuration, which is why the tank
maintenance slot shows no stack count. Settled from the client source mirror plus in-game
measurement (`/jac inspect maintenance`).

> An earlier revision of this document declared the problem CLOSED and stated that the
> Cooldown Manager join was unavailable. That was **wrong**: it assumed a viewer the player
> cannot see is unpopulated. A viewer kept *shown at alpha 0* stays fully populated. The
> correction is in "Route 1" below.

## The two routes, and where each stops

**Route 1 - Cooldown Manager join.** Works. Requires the viewer to be laid out.
**Route 2 - per-instance secrecy.** Works. Requires the aura not to be secret.

Neither covers Ironfur/Bone Shield by default, so the maintenance slot renders no count.

## The question

Given spell id 192081 (Ironfur), get *its* `auraInstanceID` in combat, so `.applications`
and `GetAuraDuration` can be read off the correct instance.

## Why it cannot be done

`aura.spellId` is a secret value in combat - it cannot be read, compared, or branched on.
So the buff list cannot be scanned for "the one whose spellId == 192081".

**The by-spell lookups are closed at the schema level, not by taint.**
`GetPlayerAuraBySpellID` (`UnitAuraDocumentation.lua:335`), `GetUnitAuraBySpellID` (`:372`)
and `GetAuraDataBySpellName` (`:208`) all carry `RequiresNonSecretAura = true`. Blizzard's
own untainted code cannot look the spell up by id either. There is no fourth door.

**Different iteration hits the same wall.** `GetAuraDataByIndex`, `GetAuraDataBySlot` and
`GetAuraDataByAuraInstanceID` are all `SecretWhenUnitAuraRestricted`. Aura index and slot are
positional, not identity, and shift as auras come and go - Blizzard guards against slot
desync in its own code (`AuraUtil.lua:93`).

**Display code does not launder identity.** Systems that *show* auras iterate and render;
they never need to answer "is spell X up", so they never compare a secret spellId against a
known id. Every plain aura cache in the client (`BuffFrame.lua:799`, `TargetFrame.lua:510`,
`Blizzard_NamePlateAuras.lua:182`, `PartyMemberFrame.lua:41`) is keyed *by* `auraInstanceID`
with a secret `spellId` as the value - an anonymous bag, backwards from what is needed. Where
a plain-named `spellID` field sits beside an instance id (`Blizzard_NamePlateAuras.lua:39`,
`BuffFrame.lua:797`) it holds a *copied secret*; assignment does not launder.

**Tooltips are closed too, both directions.** `C_TooltipInfo.GetUnitBuff`,
`GetUnitBuffByAuraInstanceID` and `GetUnitDebuffByAuraInstanceID` all carry
`SecretWhenUnitAuraRestricted = true` (`TooltipInfoDocumentation.lua:1240, :1259, :1294`), so
scanning tooltips for the aura's NAME returns secret strings - unreadable, uncomparable.

Nor can a value be drawn into a tooltip and read back. That is the system's core invariant:
anything derived from a secret stays secret. Display sinks (`SetText`,
`SetCooldownFromDurationObject`, `SetVertexColor`) accept secrets precisely because they are
TERMINAL - the value enters the engine and never returns to Lua. Render-then-read would launder
any secret through a hidden FontString and make the whole restriction decorative.
The Cooldown Manager is not a counter-example: it does not launder. Blizzard's UNTAINTED code
compares the secret and stores a PLAIN result, and we read that stored number. Borrowed
privilege, not a leak - which is why it is the only route of its kind.

**The combat log is hard-blocked**, not merely secret - accessors live only in
`C_CombatLogSecure` (`Environment = "SecureOnly"`). That was the only route to exact stack
counts. See the do-not-re-add note in `DebugCommands.lua`.

**`.applications` is display-only, permanently.** A correct instance id would not make the
stack count readable. It is secret; `GetAuraApplicationDisplayCount` returns a secret string.
The only payoff from a correct instance is the `DurationObject` for the swipe.

## Route 2: per-instance secrecy (no frames, no UI dependency)

`C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter, maxCount, sortRule, sortDirection)` returns a
**plain table of instance ids** - its return carries no `SecretWhenUnitAuraRestricted` and no
`ConditionalSecretContents` (contrast `GetUnitAuras`, `UnitAuraDocumentation.lua:407`, which
does). `C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)` then answers per id with
a plain bool. For instances it reports NON-secret, `GetAuraDataByAuraInstanceID(...).spellId` is
readable and directly comparable - **exact identity, no Blizzard frame involved.**

Pin `sortRule = Unsorted (0)`; the Expiration and Name rules order by data we cannot read.

Measured in combat on a Guardian Druid: `14 instances total, 2 readable, 12 secret`. So the
enumeration works and the partition is real - but Ironfur is `ContextuallySecret`
(`GetSpellAuraSecrecy = 2`) and therefore always lands in the secret group. **Route 2 gives
exact identity only for auras that are not secret** - in practice the long-duration ones
(flask, food, weapon imbue, raid buffs). That subset is genuinely useful elsewhere in this
addon; it just cannot serve the maintenance slot.

Note this contradicts a claim seen elsewhere that combat aura enumeration returns nothing:
that applies to `GetAuraDataByIndex`, not to `GetUnitAuraInstanceIDs`.

## Route 1: the Cooldown Manager join, and its real condition

`Blizzard_CooldownViewer` *does* perform the match - it is the only system whose job requires
it. Untainted, it reads the secret `spellId`, matches it against a tracked cooldown, and
caches the result as a plain field (`CooldownViewerItemData.lua:243-249`):

```lua
self.auraInstanceID = auraInstanceID;   -- plain
self.auraSpellID    = auraSpellID;      -- SECRET, never touch
```

Reading `item:GetAuraSpellInstanceID()` is legitimate laundering, and it works. The condition is
that the viewer must be **shown**: measured in game, with the viewers hidden every pooled item
frame has `cooldownID == nil`, so no frame carries an instance id. `cooldownViewerEnabled = true`
and `IsCooldownViewerAvailable() = true` are *not* sufficient - the frame must be laid out in
Edit Mode.

**Shown does not mean visible.** A viewer held at `SetAlpha(0)` with mouse motion disabled stays
fully populated - pool laid out, `RefreshLayout` running, `auraInstanceID` current - while being
invisible and non-interactive to the player. Only `Hide()` empties the pool. So requiring the
viewer is an onboarding question, not an impossibility: the player must place it once, after
which it can be made to disappear. Defend the alpha with `hooksecurefunc` on the viewer's
`SetAlpha` (guarded against re-entrancy) and rebuild the spell->frame map on `RefreshLayout`,
since pooled frames are reshuffled by `layoutIndex`.

Identity comes from `child.cooldownInfo` - `spellID` / `overrideSpellID` /
`overrideTooltipSpellID` / `linkedSpellIDs` are plain numbers compared with ordinary `==` - then
`child.auraInstanceID` and `child.auraDataUnit` are read as plain fields. Never call
`item:GetSpellID()`: it returns the secret `auraSpellID`.

Not implemented here: JustAC would have to require the player to configure a Blizzard UI it
otherwise has nothing to do with. Revisit if the maintenance slot's stack count is wanted back.

Measured on a Guardian Druid, in combat, Ironfur active:

```
Q1 secrecy: aura -> 2 (ContextuallySecret)   cast -> 2
direct GetPlayerAuraBySpellID -> nil
Q2 TRACKED in Utility (cooldownID=177838)  (73 ids across categories)
CooldownManager: cvar=true available=true
  UtilityCooldownViewer  shown=false items=11
Q3 no live item frame (want cooldownID=177838, 26 active items walked)
   active frame cooldownIDs:            <- empty: GetCooldownID nil on all 26
```

Reproduce with `/jac inspect maintenance` (run in combat with the buff up).

## What we do instead

The cast->instance bridge in `MaintenanceTracker.lua`: after our own cast succeeds, the next
player-cast helpful aura in the `UNIT_AURA` batch is assumed to be ours.
`IsAuraFilteredOutByInstanceID(unit, id, "HELPFUL|PLAYER")` is a readable boolean, and
`auraInstanceID` is plain - identity without ever reading `spellId`.

Its ceiling: that filter means "a player-cast helpful buff", not "this spell". `AuraFilters`
is 13 category tokens with no spell dimension (`AuraUtil.lua:158-173`), so `"HELPFUL|PLAYER"`
is the tightest predicate expressible - the heuristic is at the API ceiling, not misusing it.

A trinket or talent proc landing in the same window can therefore be bound instead. Mitigation:
**bind only when the batch offers exactly one candidate**, and stay UNKNOWN when it is
ambiguous. Failing to nil is correct; failing to a wrong aura is not.

## Consequence: no stack count on the maintenance slot

Rendering the count was *safe* (pass-through: the engine drew a number we never read) but not
*correct* - on a mis-bind it drew another aura's count as your mitigation stacks, which for a
tank is actionable misinformation. It was removed. The swipe and glow still carry "up /
refresh it". Do not re-add without an identity-exact bind.
