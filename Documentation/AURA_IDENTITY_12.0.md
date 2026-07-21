# Identifying a specific aura in 12.0 combat

**Status: CLOSED.** There is no way for this addon to obtain the `auraInstanceID` of a
*named* spell's aura on the player during combat. Everything below is settled from the
client source mirror plus in-game measurement. Do not re-derive it.

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

**The combat log is hard-blocked**, not merely secret - accessors live only in
`C_CombatLogSecure` (`Environment = "SecureOnly"`). That was the only route to exact stack
counts. See the do-not-re-add note in `DebugCommands.lua`.

**`.applications` is display-only, permanently.** A correct instance id would not make the
stack count readable. It is secret; `GetAuraApplicationDisplayCount` returns a secret string.
The only payoff from a correct instance is the `DurationObject` for the swipe.

## The one exception, and why it is not usable

`Blizzard_CooldownViewer` *does* perform the match - it is the only system whose job requires
it. Untainted, it reads the secret `spellId`, matches it against a tracked cooldown, and
caches the result as a plain field (`CooldownViewerItemData.lua:243-249`):

```lua
self.auraInstanceID = auraInstanceID;   -- plain
self.auraSpellID    = auraSpellID;      -- SECRET, never touch
```

Reading `item:GetAuraSpellInstanceID()` would be legitimate laundering. **Measured in game, it
is unavailable:** with the viewers hidden, every pooled item frame has `cooldownID == nil`, so
no frame carries an instance id at all. `cooldownViewerEnabled = true` and
`IsCooldownViewerAvailable() = true` are *not* sufficient - the viewer must actually be
displayed. That is a UI configuration the addon cannot require of players.

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
