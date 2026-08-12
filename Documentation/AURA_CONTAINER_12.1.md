# Aura Display via AuraContainer (WoW 12.1.0)

**Status:** in use as of 2026-08-11 (build 69214), validated in game on the enrage
cleanse cue. Shipped in `UI/UISootheCue.lua` (enemy, curve-selected) and
`UI/UIMaintenanceAura.lua` (player, spell-id-selected).
**Answers:** "12.1.0 refuses to let me read auras at all - can I still show the player
something that depends on one?"

> Read [AURA_IDENTITY_12.0.md](AURA_IDENTITY_12.0.md) first for the *read* routes.
> This doc is about the case where every read route is closed and only a **display**
> remains. Nothing here ever becomes a branchable boolean - see "The hard limit".

## The problem

12.0 made aura FIELDS secret. 12.1.0 went further and made the aura CALLS refuse:

- `C_UnitAuras.GetAuraDataByIndex` throws `Auras cannot be accessed when secret while
  tainted by 'JustAC'` - it does not hand back a secret, it denies the call.
- `GetUnitAuras` throws in combat for **every** filter, including plain `"HELPFUL"`.
  The 12.1.0 filter tokens (`RAID_PLAYER_DISPELLABLE`, `DISPELLABLE`, `BIG_DEFENSIVE`,
  `CROWD_CONTROL`) are therefore unusable to us however attractive they look.
- `GetAuraDispelTypeColor`, `GetAuraDuration`, `GetAuraBaseDuration` and
  `GetRefreshExtendedDuration` all carry the `RequiresUnitAuraAccess` precondition
  (`FailureMode = Error`), which is the flag that produces that denial.

Grep the generated docs for `Requires*`, **not** `SecretArguments`, when asking "can we
call this": `SecretArguments = "AllowedWhenUntainted"` governs whether secret values may
be passed *as arguments*, not whether a tainted addon may call the function at all.

Net: there is no tainted-legal route to live aura state on a hostile unit. The enrage
cue, validated secret-safe on 12.0.7, died outright on 12.1.0.

## Why the container works when nothing else does

`Blizzard_AuraContainer`'s two XML files are the only places in the entire UI source
carrying `allowUntaintedCreation="true"`. A frame we create from those templates does
**not** run in our taint, so Blizzard makes the denied calls on our behalf. The
templates also carry `secureDelegates="true"`, and `initializeFrame` is deliberately
`securecallfunction`'d with Blizzard's own comment calling it "potentially tainted".
This is built for addons.

We supply a **colour curve**; the container evaluates it against the aura's numeric
dispel type and writes the resulting (secret) colour into a texture we own. Enrage is
dispel type **9** - a distinct engine value that `auraData.dispelName` never exposes
(that string only ever says Magic/Curse/Disease/Poison/Bleed/None).

## The recipe

```lua
local curve = C_CurveUtil.CreateColorCurve()
curve:SetType(Enum.LuaCurveType.Step)
curve:AddPoint(0,  CreateColor(0, 0, 0, 0))   -- transparent
curve:AddPoint(9,  CreateColor(0, 1, 0, 1))   -- 9 = Enrage
curve:AddPoint(10, CreateColor(0, 0, 0, 0))   -- transparent again

local cont = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
cont:SetUnit("target")
cont:AddAuraGroup("myGroup", "HELPFUL|RAID_PLAYER_DISPELLABLE", {
    maxFrameCount = 5,
    initializeFrame = function(button)
        button:SetSize(48, 48)                          -- REQUIRED, see trap 3
        local t = button:CreateTexture(nil, "OVERLAY")
        t:SetSize(48, 48); t:SetPoint("CENTER")
        button:AddDispelTypeTexture(t, {
            showAlways = true,                          -- REQUIRED, see trap 1
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            customDispelColorCurve = curve,
        })
    end,
})
```

`SetUnit` is a C-side intrinsic method invisible in the Lua source - enumerate a live
object rather than trying to confirm the API surface from the mirror alone.

### Three traps, each of which costs a run

1. **`showAlways = true` is mandatory.** Enrage is not a `dispelName`, and
   `showWhenHelpful` defaults false, so the default criteria suppress it entirely.
   (`ShouldShowDispelTypeForAura`, Blizzard_CustomAuraButton.lua)
2. **On an ENEMY, you cannot name the spell.** `CanApplyIdentityCandidateFilters`
   returns false for helpful auras on a unit you cannot assist - i.e. exactly enrage -
   so `candidateFilters.includeSpellIDs` is silently ignored there. Use a group over the
   whole filter string and let the curve do the selecting; every non-match is
   transparent. On the **player** the same test passes (`UnitCanAssist("player",
   "player")`), so a player-buff display may and should name its spell id outright - see
   "Slots, groups, and naming the spell".
3. **Pooled buttons have NO intrinsic size**, and the group's layout options are
   spacing-only. Without `button:SetSize`, everything anchored to it renders at zero
   pixels - invisible, with every other gate reporting healthy.

## What you may and may not do inside a container button

Blizzard applies `Enum.ScriptObjectAccessRestriction.DenyTaintedAccessWhenAurasAreSecret`
to each button - **after** `initializeFrame` returns
(`AuraContainerCustomFrameProviderMixin:CreateFrame`, with an explicit comment saying
"Access restrictions should be applied after (potentially tainted) post-creation
callbacks"). Two consequences that are easy to get wrong:

- **Construction-time success proves nothing about combat.** A write that worked while
  building the slot may throw once auras are secret. Measure in combat, not on a dummy
  out of combat.
- The subtree may receive **content**, never **behaviour**.

| inside a button | verdict |
|---|---|
| icon texture, hotkey/label text, border + mask chrome | works |
| creating child frames, textures, Cooldowns, AnimationGroups | works |
| `SetScript` of any kind | **blocked** (`cannot replace a forbidden script handler` on the container; `blocked by secret aspects` on a descendant) |
| `SetCooldownFromDurationObject` on your own Cooldown | **blocked** (`Attempt to access forbidden object`) - but see below: the container will make that exact call for you |
| driving anything per tick | **blocked**, and it throws once per tick per slot |

**A proc glow is NOT blocked** - an earlier note here said it was, wrongly. What is
blocked is the `SetScript("OnHide")` the glow builder attaches, and that handler exists
only to *stop* the loop. An AnimationGroup is engine-side and needs no handler, so a
glow that is started once and never stopped builds fine. See
`UIAnimations.CreateUndrivenProcGlow`.

### Handing textures to the container

`AddDispelTypeTexture` runs `AuraContainerUtil.ValidateInboundScriptObject`, which
requires `RegionUtil.IsDescendantOf(texture, button)`. **The curve-driven texture must
live inside the button.** You cannot hand it a texture on your own external frame, so
"build our own full-featured icon somewhere else and alpha-sink it from the enrage" has
no way in.

The container then owns that texture: it stamps `SecretAspect.Alpha`, `VertexColor`,
`TexCoords` and `Shown` on it, plus `ForbiddenAspect.RemoveSecretAspects` and
`ChangeParent`. Practical rules that follow:

- **Never `SetVertexColor` a registered texture** - the curve overwrites it. Supply the
  colour through the curve instead. (Setting it anyway is what once produced a raw
  yellow box where the cue should have been.)
- **Desaturation still works** and is the way to re-tint gold art: `SetDesaturated(true)`
  leaves grey for the curve to multiply.
- Stamp the icon/text **before** handing the texture over; afterwards it is untouchable,
  and there is no `RemoveAuraGroup`, so a *changed* spell means rebuilding the container.

### Registering displays the container drives

`AddDispelTypeTexture` is one of a family. Every one of these takes a widget that must be
a **descendant of the button**, stamps secret aspects on it, and thereafter drives it from
the real aura - including the calls we are forbidden to make ourselves:

| register | what the container then does | stamps |
|---|---|---|
| `SetIcon(texture)` | the aura's own icon art | - |
| `SetDurationCooldown(cooldown)` | `SetCooldownFromDurationObject(auraDuration, false)` | Cooldown, Shown |
| `SetDurationText(fs, opts)` | a formatted countdown; `opts.textColor.curve` tints it | Text, Alpha, VertexColor |
| `SetDurationBar(bar, opts)` | `SetTimerDuration` on a StatusBar | BarValue |
| `SetApplicationCount(fs, opts)` | the stack count, blank below 2 unless you pass a formatter | Text, Shown |
| `SetApplicationBar(bar, opts)` | stacks as a filled bar, `opts.maxApplications` | BarValue |
| `SetSpellName(fs)` | the aura's name | Text, Shown |
| `AddPandemicRegion(region)` | `SetShown` while inside the refresh-carryover window | Shown |

So **the swipe is not off-limits** - only *our* call to it is. Register the widget and the
container makes the call. The same correction applies to anything else in the table above
that looks blocked because a direct attempt threw.

### Slots, groups, and naming the spell

`AddAuraSlot(key, filterString, opts)` is the right primitive for "one aura in a fixed
place", which is what a single indicator button is. It differs from a group in three ways
that all matter:

- its frame is created **eagerly** and returned, so `initializeFrame` has already run by
  the time the call returns - a group creates a lazy batch of ten on first sighting of a
  matching aura, so nothing can be read back at registration time;
- slots take **no part in the flow layout** (`GetFlowLayoutGroupDescriptions` enumerates
  groups and item enchantments only), so you anchor the frame yourself;
- `sortMethod` picks *which* candidate the slot holds. `ExpirationOnly` is the useful one
  for a buff whose applications land as separate aura instances - it holds the one about
  to fall off.

A container holding only slots lays out empty, and `OnLayoutComplete` sizes it to zero.
Anchor it by a **single point**, and give the slot frame its own size, or the zero-size
layout fights a four-corner anchor.

## The hard limit: display only, permanently

There is no read path back out, by design:

- `CustomAuraButtonPrivateMixin:ApplyVisibility` is literally
  `self:SetShown(secretwrap(auraData ~= nil))`, and `Shown` is a stamped secret aspect.
- `GetAuraGroupFrameCount` counts the **pool**, not live auras, and the pool is
  pre-batched at `FrameCreationBatchSize = 10` with Blizzard's comment saying it exists
  "to make it harder to observe the transition between zero/non-zero auras".
- `IsFrameActive` is provider-private and not exposed on the container.

So the enrage can drive pixels and can never drive a queue decision. Do not
re-investigate this.

## Composing plain state with the secret

Everything *else* a cue depends on - your own cooldown, whether the target is
attackable, a profile toggle - is plain and branchable. Do **not** try to express it
inside a slot; you cannot draw "not yet" there. Apply it one level up by showing or
hiding the **container**, which is ours and unrestricted:

```lua
-- UI/UISootheCue.lua : Show
if onCooldown or not (UnitExists("target") and UnitCanAttack("player", "target")) then
    return UISootheCue.Hide(cue)   -- plain half of the AND
end
cue:Show()                          -- secret half is the container's job
```

This is safe and self-healing: `AuraContainerPrivateMixin:OnShow_Intrinsic` /
`OnHide_Intrinsic` both call `UpdateEventRegistrations()` + `UpdateAllAuras()`, and
dynamic `UNIT_AURA` registration is gated on `IsVisible() and IsEnabled()`. A hidden
container drops its registration and re-reads every aura on the way back up.

**Pick the granularity deliberately.** A state that flips slowly (a 10s cooldown) suits
a visibility gate. A state that flips constantly (the GCD) does not - the cue would
strobe for the whole fight. That is why the enrage cue gates on the real cooldown and
simply says nothing about the GCD: the swipe that used to carry it cannot be drawn on
these slots.

## Verifying it (and detecting closure)

`/jac inspect enrage` arms a live on-screen row - one slot per target buff, lit when
that buff is dispel type 9 - and then walks the feature's own gates in order, naming the
first that is false (library loaded, `Available()`, interrupt mode, resolved soothe
spell, cleanse off cooldown, anchor icon, cue created, cue shown, target attackable).

`/jac inspect auracontainer` proves the container half end to end.

Signs of closure after a patch:

- The container refuses creation, or `Enum.CustomAuraButtonDispelTypeTextureStyle`
  disappears -> `UISootheCue.Available()` returns false and the cue self-disables.
- Buttons build but nothing ever lights -> check trap 1 and trap 3 before assuming the
  dispel-type number line moved.
- Errors once per tick per slot -> something in the subtree is being written after
  `initializeFrame`; find it and move it to construction.

## If Blizzard closes it - fallbacks (in order)

1. **Re-check the dispel-type number line.** Calibrate with a known Magic buff: it
   should decode to type 1, matching its `dispelName`. `/jac inspect enrage` prints the
   decoded type per aura where readable (out of combat).
2. **Engine-rendered enemy buffs.** The nameplate `AurasFrame.BuffListFrame` renders
   important/stealable enemy buffs, enrage among them. We can reposition that frame
   without reading it - but it is not enrage-specific, so it fires for any important
   buff. Note the scale-space gotcha: nameplate aura frames inherit the plate's scale,
   so multiply by `UIParent:GetEffectiveScale() / AurasFrame:GetEffectiveScale()`.
3. **Drop the cue.** It is a reminder, not a gate; nothing else depends on it.

**Never** ship a curated `Data/EnrageSpells.lua`. Verified 2026-07-07: the client's own
category data has no dispel-type-9 row for at least one spell the live game treats as an
enrage, so an offline list would miss real enrages. The runtime path reads live truth.

## Source references

In the mirror (`R:\WOW\00-SOURCE\wow-ui-source\Interface\AddOns\Blizzard_AuraContainer`):

| file | what to look for |
|---|---|
| `Blizzard_CustomAuraButton.lua` | `AddDispelTypeTexture`, `ShouldShowDispelTypeForAura`, `ApplyVisibility` |
| `Blizzard_CustomAuraContainer.lua` | `AddAuraGroup` options, candidate filters |
| `Blizzard_AuraContainerUtil.lua` | `ValidateInboundScriptObject`, `CanApplyIdentityCandidateFilters` |
| `Blizzard_AuraContainerFrameProviders.lua` | when access restrictions are applied |
| `Blizzard_AuraContainer.lua` | `OnShow_Intrinsic` / `UpdateEventRegistrations` |
| `Blizzard_AuraContainerShared.lua` | `CustomAuraContainerConstants` |

Ours: `UI/UISootheCue.lua` (the cue), `UIAnimations.CreateUndrivenProcGlow` (the glow),
`DebugCommands.EnrageProbe` (`/jac inspect enrage`).
