# Client compatibility: retail and WoW Forever in one addon

Goal: one branch, one release, both clients. The shared engine (queue, renderer, gates,
trackers, options, probes) is most of the addon; what differs is data and a short list of
client behaviours. Separate branches would turn every shared fix into a merge, so they are
not the plan.

## Rules

1. **One client predicate.** `SpellDB.IsForever()` (and `BlizzardAPI.IsForever()`, which
   delegates). `BlizzardAPI.HasGamePick()` is the other gate: false where Assisted Combat is
   absent (Forever). Nothing else tests the client.
2. **Gate where everything routes through.** A guard in the one function every consumer
   reaches (example: `RotationImport.RegisterForever`) beats a guard at each caller, and it
   survives regenerating the data.
3. **Data per client, one gate per file.** `Data/ForeverDefaults.lua` returns unless Forever;
   `Data/ForeverRotations.lua` registers through the gated `RegisterForever`. Shared tables
   are merged into, never replaced, and retail never builds `<CLASS>_F` keys.
4. **Retail behaviour stays exactly as before unless a change is meant for both.** Universal
   changes are listed below as such; anything else is gated.
5. **Every leak is a test.** `tools/test_forever_defaults.py` loads the real SpellDB,
   RotationImport, Forever lists and Forever defaults as retail and asserts nothing Forever
   registers there. `tools/test_forever_dots.py` checks the DoT tracker's retail half.

## Planned next steps

- A capability layer (`BlizzardAPI/Client.lua`) answering the questions the code actually
  asks: HasGamePick, HasRanks, HasSwingEvents, DotRefreshCarryover, TargetGUIDPlainInCombat,
  AurasReadableInCombat. Gates then name the reason, not the client.
- Per-client TOC file lists, if Forever reads a client-specific TOC suffix (needs an
  in-game check): each client would then load only its own data files.
- Merge `main` (5.8.0, 5.8.1) into `forever`, then `forever` back into `main`.

## Review of 2026-10-07 (branch `forever` vs its base 4b0a2f1)

Fixed - retail behaviour that had changed by accident:

| What | Effect on retail | Fix |
|---|---|---|
| Forever rank chains registered on retail | 131 retail spell ids resolved through Forever ranks (displayed rank, static lookups, override resolution, saved-setting matching; Polymorph resolved to Polymorph: Pig) | `RegisterForever` returns unless Forever |
| DoT hit check (UNIT_COMBAT) on retail | Any miss within 0.4s of a DoT cast - our white swings, a party member's parry - wiped the DoT's timer; any IMMUNE flagged it sunk for the fight | Registered on Forever only |
| Per-target DoT records on retail | PvP targets (plain GUIDs) had records restored across swaps | Forever only |
| Remembered buff expiry on retail | A buff consumed early read as up until its old expiry | Forever only |
| Rotation rebuilt on every bar change | Wasted work on retail | No-game-pick only |
| "Wasted presses last" sunk ordering | Retail's sunk tail reordered | No-game-pick only |
| Maintained-buff aura ids in the latch index | Extra latch keys on retail | Forever only |
| `/startattack` counted as a macro command | `/startattack` + `/cast X` scored X as the second command, changing which macro supplied the hotkey | Attack lines no longer move the count |
| Unbound button's slot pre-empted the hotkey search | A bound copy reachable only through a transform was missed | The unbound slot is used only when no bound button is found |

Fixed - Forever-side bugs found on the way: oversized rank chains (every nameless spell of a
class collapsed into one 100+ "rank" chain), the Cooldown Manager lookup sharing state with
maintenance-slot entries, and two `x and x.f()` expressions that read a missing module as
"down".

Intended universal changes (apply on both clients):

- `C_SpecializationInfo.*` instead of the deprecated globals (aliases on retail).
- Queue icons tint by usability out of combat too.
- An unbound button's slot answers usability, range and cooldown.
- `/startattack` in a macro maps to Attack; Attack hides while auto-attacking.
- Saved settings (blacklist, pins, holds, hotkey overrides) match across ranks (a no-op on
  retail).
- Priority-list tie order keeps the incoming order.
