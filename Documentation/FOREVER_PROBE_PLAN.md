# Forever probe plan

Forever is game type `camelot` (`WOW_PROJECT_ID` 18, Interface 16001) on the modern engine.
Measured on the beta (1.60.1.70205): `C_AssistedCombat.IsAvailable()` = false,
`GetRotationSpells()` = `{}`; the client's own `InterfaceOverrides.HasAssistedCombat()` returns
false. There is no Blizzard pick, so everything keyed off the pick has no input. These probes
find out what we can use instead.

Source facts (wow-ui-source `forever` branch, wago.tools build 1.60.1.70205):

- One spec per class (`ChrSpecialization` 1482-1491), spell ranks present ("show all ranks").
- API docs are a superset of live 12.1.0. The secrecy annotations are identical, so whether the
  restrictions are actually ENFORCED can only be measured in game.
- Loads on camelot: CooldownViewer, DamageMeter, AuraContainer, CombatAudioAlerts, a new
  SwingTimer UI. Does not load: PersonalResourceDisplay, EncounterTimeline, AssistedCombatManager.

## Port status (branch `forever`)

What runs unchanged: defensives / heals / potions / pet cluster (own frame), health and
power bars, maintenance slot (Cooldown Manager loads on camelot), spellbook proc glows,
interrupt slot on the nameplate overlay, key-press flash, all list editing via spellbook search.

What changed:

- `JustAC.toc`: Interface 16001.
- `SpellDB.GetSpecKey`: `<CLASS>_F`. `WARRIOR_1` would have matched retail Arms data, and
  the old key was nil whenever `GetSpecialization()` is.
- `BlizzardAPI.GetRotationSpells`: with no Assisted Combat pool, the pool is the non-passive
  spells on the action bars in slot order. Every list tool (start from, merge, baseline, "new
  abilities" notice) works off it unchanged. The rotation cache refreshes on OOC bar changes.
- `PriorityList.SortByPriority`: ties keep their incoming order, so an unranked pool stays in
  bar order instead of spell-id order.

The queue is therefore "your list" (Custom Queue), seeded from your bars. Without a list it
shows the bar pool, filtered for readiness, in bar order. Not ported yet: curated retail spell
data (ranks make exact-id lists miss; wago.tools carries the Forever build as `wow_cn_beta`
1.60.1.70205 for a regenerated set), SimC ordering (no Forever APLs), gap closers (spec-keyed).

## Hypotheses

| # | Question | Probe line | If YES, it unlocks |
|---|---|---|---|
| H1 | Are combat restrictions enforced at all? | `forever` B: `HasSecretRestrictions`, `Should*BeSecret`, raw `UnitHealth`/`UnitPower` in combat | NO = a local priority engine can read cooldowns, auras and power directly, so a real rotation queue is possible. YES = we reuse the retail secret-safe toolkit |
| H2 | Is `PLAYER_SWING.swingDuration` plain in combat, and does the measured `gap` match it? | `forever arm`, probe log `forever swing` rows | A complete swing timer from one event: Slam windows, Heroic Strike/Cleave queue cue, Auto Shot clip warning |
| H3 | Is `IsCurrentSpell` plain for a queued on-next-swing ability and for Attack/Auto Shot? | `forever` C and D `cur=` | Hide a queued Heroic Strike instead of re-suggesting it; "auto attack is off" reminder |
| H4 | Is `IsUsableAction` plain for reactive abilities (Overpower, Revenge, Execute, Riposte)? | `forever` D `use=` while the ability is lit | Reactive abilities become proc signals, so we promote them the way retail promotes glowing spells |
| H5 | Do action bars hold low ranks, and does a by-name lookup return the top rank? | `forever` D `LOW-RANK` flag, `byName=` | Decides how hotkey lookup must match ranks (by id, by name, or by rank family) |
| H6 | Is weapon-enchant state plain (`hasEnchant`, `timeLeft`)? | `forever` E | Poison / sharpening stone / wizard oil / shaman imbue reminder in the precombat checklist |
| H7 | `AmmoNeeded` / `UnitUsesAmmo` | `forever` E | Hunter ammo reminder |
| H8 | `GetPetHappiness` / `GetPetLoyalty` plain? | `forever` E (with a pet out) | Feed-pet reminder in the sustain slot |
| H9 | Is `GetRefreshCarryOverDuration` plain on our own DoT on the target in combat? | `forever` F, target row | A plain refresh-window signal for maintained DoTs, which retail closed |
| H10 | Does the Cooldown Manager have entries for a Forever class? | `forever` G | MaintenanceTracker's buff bridge works unchanged |
| H11 | Are combo points (`GetComboPoints`) plain in combat? | `forever` B | Finisher gating for rogue and feral |
| H12 | Does `GetManaRegen` casting regen move with the five-second rule? | `forever` E, before/after a cast | Spirit-tap / five-second-rule cue for healers and casters |
| H13 | The retail GCD dummy (61304) is not in Forever's spell data. Does it still answer, and does a bar spell's `isOnGCD` track the GCD? | `forever` B "GCD dummy", D `onGCD=` right after a cast | Which spell CooldownTracking's GCD lookahead and `GetGCDInfo` should read on Forever (today they get nothing and silently disable) |
| H14 | Does hotkey lookup find the button for a low rank AND for the top rank? | `forever` D `key=` / `keyTop=` | Whether curated lists can name any rank, or must match the rank on the bar |
| H15 | Do `[AllowLoadGameType mainline]` files load on camelot? | `forever` A: AssistedCombatManager, PersonalResourceDisplayFrame, `.classFrame`, combo bar frame | Which Blizzard frames the shell can still lean on; expected: manager + resource display yes, class frame + combo bars no |

Known limits: aura instance ids come only through access-gated calls (`GetAuraDataByIndex`,
`GetUnitAuraInstanceIDs`), so H9 can only answer in combat if H1 shows aura access is open.

## Results (2026-10-04, level-1 warrior, 3 runs + 8-pull audit)

| # | Verdict |
|---|---|
| H1 | ENFORCED, stricter than retail: player power and target health secret even out of combat; auras + cooldowns secret in combat; every aura call throws in combat |
| H2 | YES: `PLAYER_SWING` swingDuration/swingType plain in combat; measured gaps 1.82-2.00s on a 1.9s weapon. Range half dead (`checksRange` always false, `IsTargetWithinSwingRange` nil) |
| H3 | YES: `IsCurrentSpell` plain in combat (queued Heroic Strike, Attack) |
| H4 | YES for resource-gated usability (`IsUsableAction` false -> true with rage); reactive abilities untested (level 1) |
| H5/H14 | untested (rank 1 only); hotkeys resolve for rank 1 |
| H6/H7 | YES: weapon enchant + ammo plain in combat |
| H8 | untested (no pet) |
| H9 | CLOSED: aura calls denied in combat |
| H10 | YES: Cooldown Manager populated (viewers must be enabled in Edit Mode) |
| H11 | plain (0 on warrior); rogue pass pending |
| H12 | CLOSED: mana regen secret in combat |
| H13 | YES: a GCD-bound bar spell's `isOnGCD` is plain and true during the GCD |
| H15 | mainline-tagged files load (AssistedCombatManager, PRD without class frame); combo bars absent |

Also measured: own casts plain, target casts secret; `UnitAttackSpeed` plain OOC / secret
in combat; the scratch-Cooldown readiness probe, cooldown `isActive`, LowHealthFrame,
FullPowerFrame and builder/spender feedback frames all read plain in combat, as on retail.

## Round 2: combat context (what a rotation needs to know, and where it might come from)

Round 1 answered "which reads survive". Round 2 asks the engine's question: for each
decision a Forever rotation makes, is there a signal that answers it in combat? Two tools:

- `/jac inspect forever` section I: one-shot slow-changing context.
- `/jac inspect forever arm`: the COMBAT RECORDER. 37 events with every payload argument
  classified (plain value / SECRET / nil), the gap since the previous event of the same kind,
  and a 5/s change-only sampler of every bar button (usable / no-power / in range / queued /
  on GCD), the player (form, stealth, speed, combo points, threat, auto attack) and the
  nameplates (count, in combat, within 10 yd). Lines: `fw` = event, `fs` = sampler change.
  Caps reset per combat phase; overflow is counted (`fw: over cap last phase`).

### Decision -> candidate signal

| Decision (classes) | Candidate signal | Recorder line | If plain, it unlocks |
|---|---|---|---|
| Target dodged / I parried / blocked: Overpower, Revenge, Riposte, Counterattack (WAR, ROG, HUN) | `UNIT_COMBAT` event string (DODGE, PARRY, BLOCK) - retail already branches on its IMMUNE string | `fw UNIT_COMBAT` | The reactive trigger itself, before the button even lights |
| Reactive ability lit: Overpower, Revenge, Execute, Victory Rush, Riposte, Hammer of Wrath, Exorcism vs undead | `IsUsableAction` flip (usability encodes target health < 20%, creature type, a dodge, a kill) | `fs [slot]` use= | One gate covers every "only usable when" ability; Execute doubles as an execute-phase signal |
| Can I afford it vs is it unusable | `IsUsableAction` 2nd return (no-power) | `fs [slot]` noPower= | Resource gating per ability without reading rage / energy / mana |
| Next swing: Heroic Strike / Cleave queue, Slam, Auto Shot clip, Maul (WAR, HUN, DRU) | `PLAYER_SWING` (done: plain) | `fw PLAYER_SWING` gap | Swing timer (confirmed) |
| Already queued on next swing | `IsCurrentSpell` (done: plain) | `fs [slot]` queued= | `queued` gate (confirmed) |
| Auto attack / Auto Shot on or off | `PLAYER_ENTER_COMBAT` / `LEAVE_COMBAT`, `START`/`STOP_AUTOREPEAT_SPELL`, `IsCurrentSpell(6603)` | `fw`, `fs player` attack= | "Start attacking" / "Auto Shot stopped" cue |
| Energy / mana tick timing: energy pooling, five-second rule (ROG, DRU, casters) | `UNIT_POWER_UPDATE` / `FREQUENT` timing (value secret, event may still fire on each tick) | `fw UNIT_POWER_*` gap | Energy tick prediction (2s cadence in vanilla); mana regen resume |
| Procs: Clearcasting, Fingers of Frost, Nightfall, Bloodthrill (MAG, DRU, WLK, WAR) | `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` spellID | `fw SPELL_ACTIVATION_OVERLAY_GLOW_*` | Proc promotions, as retail's glow path |
| Proc / reactive popups | `COMBAT_TEXT_UPDATE` type (SPELL_ACTIVE...) + `C_CombatText.GetCurrentEventInfo` (SecretReturns) | `fw COMBAT_TEXT_UPDATE` | A second proc channel if the type string carries it |
| Crit happened: Flurry, Enrage, Clearcasting inference | `UNIT_COMBAT` flagText (CRITICAL) on target | `fw UNIT_COMBAT` | Proc-window inference by observation |
| Damage taken rate: defensive timing, healer triage | `UNIT_COMBAT` player WOUND amount | `fw UNIT_COMBAT` | A plain incoming-damage number, which retail never had |
| Stance / form / stealth (WAR, ROG, DRU) | `GetShapeshiftForm`, `IsStealthed`, `UPDATE_SHAPESHIFT_FORM` | `fw`, `fs player` | Stance-dance gates (Overpower needs Battle Stance) |
| Combo points (ROG, DRU) | `GetComboPoints` (done: plain 0) | `fs player` cp= | Finisher gating, once a rogue confirms > 0 |
| In range / melee distance / dead zone (all; HUN dead zone) | `IsActionInRange(slot)`, `C_Spell.IsSpellInRange`, `CheckInteractDistance(unit, 3)` | `fs [slot]` range=, I | Range gating, gap-closer trigger, hunter melee fallback |
| How many enemies, how many engaged, how many close (AoE: Whirlwind, Cleave, Thunder Clap, Blizzard) | nameplates + `UnitAffectingCombat` + `CheckInteractDistance` per plate | `fs plates` | Target-count tiers with "in combat" and "in melee" filters |
| Am I tanking (WAR, DRU, PAL tanks) | `UnitThreatSituation`, `UNIT_THREAT_SITUATION_UPDATE` | `fs player` threat=, `fw` | Tank mode: Taunt / Revenge priority |
| Target type: Spearing Strike (dragonkin, giants), Exorcism / Holy Wrath (undead, demons) | `UnitCreatureType` (SecretWhenUnitIdentityRestricted) | I, `fw PLAYER_TARGET_CHANGED` | Per-target list gates |
| Target worth cooldowns (elite / boss) | `UnitClassification`, `UnitLevel` | I | Burst on elites only |
| Kill happened (Victory Rush) | `PARTY_KILL` (SecretWhenUnitIdentityRestricted) | `fw PARTY_KILL` | Victory Rush window (usability also covers it) |
| Moving: cast-time spells, Slam | `GetUnitSpeed` (SecretWhenUnitStatsRestricted) | `fs player` speed= | Movement gate for cast times |
| My buffs / DoTs up (Battle Shout, Rend, Corruption, Seal) | `UNIT_AURA` payload shape; own-cast observation (`UNIT_SPELLCAST_SUCCEEDED` player) | `fw UNIT_AURA`, `fw UNIT_SPELLCAST_SUCCEEDED` | Whether Forever's aura payload is as closed as 12.1; else buff windows by observation |
| Enemy casting (kicks) | **Measured (round 3, build 70245).** `UNIT_SPELLCAST_START` target fires as a plain event; cast GUID, spell, and every `UnitCastingInfo` field (name, start, end, notInterruptible) are secret, in combat and out. A finished cast: target `SUCCEEDED` then `STOP`, no `INTERRUPTED`. A stopped cast: `INTERRUPTED` then `STOP`; `INTERRUPTED`'s 4th arg is secret when someone interrupted it and nil otherwise (castBarID moves to the 5th) - presence is the "kick landed" signal, as on retail | `fw UNIT_SPELLCAST_START` notInterruptible=, `fw UNIT_SPELLCAST_INTERRUPTED` d=, `fw UNIT_SPELLCAST_STOP` | Interrupt cue works on the plain START event (production reads a secret notInterruptible as unknown and offers the kick); "can't be kicked" can only be shown, never branched on |
| Target dying soon | `UNIT_HEALTH` target event cadence (value secret) | `fw UNIT_HEALTH` gap | Only if cadence tracks damage; otherwise execute via usability |
| Failed press feedback: behind target, out of range, facing | `UI_ERROR_MESSAGE` (type + message) | `fw UI_ERROR_MESSAGE` | Backstab "must be behind" and facing errors as plain feedback |
| Totems up (SHA) | `PLAYER_TOTEM_UPDATE`, `GetTotemInfo` (SecretWhenTotemSlotSecret) | `fw PLAYER_TOTEM_UPDATE`, I | Totem upkeep |
| Pet state (HUN, WLK) | **Measured (warlock imp, build 70245):** pet exists / dead / in combat / pet target is my target plain in and out of combat; raw `UnitHealth("pet")` SECRET even out of combat; `IsUnitHealthBelow("pet", pct)` plain in combat and tracks damage (below 50 / 35 seen). Pet mana the same way: raw `UnitPower("pet", 0)` SECRET, `UnitPowerType("pet")` plain, `IsUnitPowerBelow("pet", pct, 0)` plain in combat and tracks the imp's casting (below 50 / 25 seen). Dark Pact is not learnable on Forever. `PET_ATTACK_START` fires plain. `GetPetHappiness` absent; `UNIT_HAPPINESS` fires for every unit (noise). Open: the summon button's `IsCurrentSpell` with no pet out | `fs pet=`, section I pet lines | Pet heal (Sustain slot) works in combat: it gates on `IsUnitHealthBelow("pet")`. Pet rez / summon on exists / dead |
| Soul shards, ammo (WLK, HUN, WAR) | `C_Item.GetItemCount`, `AmmoNeeded` (done: plain) | I | Shard and ammo reminders |
| Loss of control | `LOSS_OF_CONTROL_ADDED` / `_UPDATE` + `C_LossOfControl` data (retail: plain). **Not yet seen on Forever**: no round-2 session was CC'd | `fw LOSS_OF_CONTROL_*` count= [type= spell= dur=], `fw PLAYER_CONTROL_LOST` | CC-break cue: Forever's breaker table (Will of the Forsaken, Will to Survive, Escape Artist, Berserker Rage, Blessing of Freedom) is shipped but unmeasured |

### Swing bars: what they give us

Forever ships `Blizzard_SwingTimer` (camelot only): `SwingTimerMainHandFrame`,
`SwingTimerOffHandFrame`, `SwingTimerRangedFrame`, driven by the same `PLAYER_SWING` we
measured plain, keeping plain fields `swingDuration`, `swingEndTime` (GetTime-based) and
`isOutOfRange`. They only run while the `showSwingTimer` CVar is on and the bar is not hidden
in Edit Mode, so JustAC keeps its own `PLAYER_SWING` tracker and treats the bars as a
cross-check. Reads only - writing fields on them would taint.

How the swing data can be used:

| Use | Signal | Status |
|---|---|---|
| `swing` gate: Slam right after a swing (baseline Slam resets it), Heroic Strike / Cleave / Maul / Raptor Strike queued just before the main-hand swing with spare rage | last `PLAYER_SWING` per type + `swingDuration` | plain, measured; evaluator is phase 5 |
| Countdown on queued on-next-swing icons (a cooldown swipe from last swing to next, plain numbers) | same + `IsCurrentSpell` | both plain; display work |
| Live attack speed in combat (`UnitAttackSpeed` is secret there) | `swingDuration` per swing | plain, measured |
| Haste-buff inference without aura reads: Slice and Dice, Flurry, Blade Flurry show as a shorter `swingDuration`; buff start / end as a `UNIT_ATTACK_SPEED` event | ratio vs the out-of-combat base speed; event timing | **probe**: recorder `fw UNIT_ATTACK_SPEED` vs `fw PLAYER_SWING` dur |
| Wand / Auto Shot timing (ranged swing type) for casters wanding and hunters | ranged `PLAYER_SWING` | plain; hunter abilities no longer clip Auto Shot on Forever |
| In melee range of the target | Blizzard bars' `isOutOfRange` / `PLAYER_SWING_RANGE_UPDATE` | our own check read nil; **probe** whether the bars' check engages with the CVar on (`fs SwingTimer*Frame` lines) |

### Round 2 session

1. `/reload`, then `/jac inspect forever arm` and `/jac inspect errors`.
2. Fight several pulls. To trigger the reactive and edge lines on purpose:
   - fight a mob that dodges and parries (any level-appropriate humanoid); let it hit you;
   - target a dragonkin or giant if one is nearby (Spearing Strike, creature type);
   - pull two or three at once (plates, threat, AoE);
   - press an ability out of range and one while facing away (`UI_ERROR_MESSAGE`);
   - run while in combat (speed); finish a kill and wait (Victory Rush, `PARTY_KILL`).
3. Out of combat, with a target: `/jac inspect forever` (section I).
4. `/jac inspect forever off`, `/jac inspect errors off`, `/reload`.

A rogue session (energy ticks, combo points, Riposte, stealth, poisons) and a hunter
session (Auto Shot, dead zone, pet) cover the rows a warrior cannot.

### Round 3: crowd control and kicks

Same arm / off as round 2. On purpose:
- get feared, stunned, rooted and slowed (a caster mob, a warrior mob's Hamstring, a
  Murloc net); press a break if you have one (Will of the Forsaken, Escape Artist,
  Berserker Rage);
- kick (or Shield Bash / Pummel / Earth Shock) a target's cast, and let another finish;
- target a mob whose cast cannot be interrupted, if one is known.

Read: `fw LOSS_OF_CONTROL_*` (is the data there and plain, does `type=` name the CC),
`fw UNIT_SPELLCAST_START` `notInterruptible=`, and `fw UNIT_SPELLCAST_INTERRUPTED` `d=`
against `fw UNIT_SPELLCAST_STOP` for the same cast.

## Run order (one session)

1. `/jac inspect errors` first, then `/reload`. A load error invalidates everything after it.
2. Target a training dummy out of combat: `/jac inspect forever`.
3. `/jac inspect forever arm` and `/jac inspect audit`. Fight for about 30s: auto attack, press
   every bar ability, let a reactive ability light up. Repeat once out of combat if the class
   can swing at a dummy without entering combat.
4. `/jac inspect forever off`, `/jac inspect audit off`, `/reload`. Results are read from
   `_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua` (`probeLog`, `errorLog`).

Class passes that cover all hypotheses: Warrior (H2-H4), Rogue (H6, H11), Hunter (H2 ranged, H7,
H8, H9 with Serpent Sting), a caster (H5 ranks, H9 DoT, H12).

## Aura sweep (`/jac inspect foreverauras`, also in every audit snapshot)

Nothing about auras is carried over from retail: build 70245 already differs (the aura LIST
calls throw in combat instead of returning a secret). The sweep asks every route, on player,
target and pet, and classifies each answer as plain, secret, nil or an error:

- classic-era `UnitAura` / `UnitBuff` / `UnitDebuff`
- `GetAuraDataByIndex`, `GetBuffDataByIndex` / `GetDebuffDataByIndex`, `GetAuraSlots` + `GetAuraDataBySlot`
- `GetUnitAuras`, `GetUnitAuraInstanceIDs`
- per field of every aura table (spell id, name, stacks, duration, expiry, source, instance id)
- for auras REMEMBERED from an out-of-combat read: by spell id, by name, by instance id,
  `IsAuraFilteredOutByInstanceID`, the duration object, the stack display count
- Blizzard's own frames: player buff buttons, target frame aura frames, the Cooldown
  Manager's tracked-buff icons (shown = the buff is up)

How to run: arm the session out of combat with a buff up (so it is remembered), then fight.
The +4s and +10s snapshots answer "the buff is known to be up; which routes still see it?".

Measured build 70245 (warrior, 2026-10-07, 10 fights, player and target):

| Route | OOC | In combat |
|---|---|---|
| `UnitAura` / `UnitBuff` / `UnitDebuff` | do not exist | do not exist |
| `GetAuraDataByIndex`, `GetBuff/DebuffDataByIndex`, `GetAuraSlots`, `GetAuraDataBySlot` | plain | throw "Auras cannot be accessed when secret" |
| `GetUnitAuras`, `GetUnitAuraInstanceIDs` | plain | throw |
| `GetPlayerAuraBySpellID`, `GetUnitAuraBySpellID`, `GetAuraDataBySpellName` | plain | nil, even for a buff known to be up |
| `GetAuraDataByAuraInstanceID`, `IsAuraFilteredOutByInstanceID`, `GetAuraDuration`, `GetAuraApplicationDisplayCount` | plain | throw |
| Player buff frame: number of shown buttons | plain | plain |
| Player buff frame: button icon | secret | secret |
| Target frame aura frames | no `auraPools` | no `auraPools` |

| Cooldown Manager tracked-buff icon (`isActive`, shown) | plain | **plain** (Battle Shout, Rend on the target, Thunder Clap) |
| Player buff frame: duration text under each icon | plain | plain ("3 m", "55 m") |
| `PLAYER_SWING_RANGE_UPDATE (swingType, inRange, hasTarget)` | plain | plain |

Conclusion: in combat no aura is readable through the aura API. Buffs and DoTs are timed from our
own casts, and a buff's expiry is remembered from an out-of-combat read - except for spells the
player tracks in the Cooldown Manager, whose icon state is exact and is now read first
(MaintenanceTracker.IsTrackedAuraActive). Blizzard's aura container exists on Forever.
