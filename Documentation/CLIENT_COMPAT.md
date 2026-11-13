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
3. **Data per client, one gate per file.** `Data/Forever/Defaults.lua` returns unless Forever;
   `Data/Forever/Rotations.lua` registers through the gated `RegisterForever`. Shared tables
   are merged into, never replaced, and retail never builds `<CLASS>_F` keys.
4. **Retail behaviour stays exactly as before unless a change is meant for both.** Universal
   changes must be intentional; client-specific changes are gated.
5. **Every leak is a test.** `tools/test_forever_defaults.py` loads the real SpellDB,
   RotationImport, Forever lists and Forever defaults as retail and asserts nothing Forever
   registers there. `tools/test_forever_dots.py` checks the DoT tracker's retail half.

## Current workflow

- Combat-signal research: [Forever combat signals](FOREVER_COMBAT_SIGNALS.md)
  records existing high-value bridges and unverified next experiments. Source
  annotations alone are not combat validation.

- Prefer existing capability helpers; this document does not prescribe a new
  capability module or client-specific TOC split.
- Use the [two-client refresh workflow](DEV_TOOLING.md#two-client-update-check-and-refresh)
  for source/data checks and authorized deployment verification.
- One shared `main` branch supports both clients. The branch review below is
  historical, not a pending merge or a description of every current code path.

## Forever rotation source review

The current vendored source and local adaptations are described under
[Lists](FOREVER_ENGINE_DESIGN.md#lists); pinned revision and license live with
`tools/forever-apl-src/`. Local healer pins live in `tools/simc-apl-forever/`.
Check those inputs and the current generator before interpreting the old design.

When evaluating alternatives, verify client/level/talent coverage, priority-list
semantics, maintenance, reproducibility, license and redistribution terms.
Compare actual imported decisions against supported live signals and general
play scenarios. Do not adopt Retail IDs/assumptions, infer unknown combat state,
or claim optimal execution from a simulator result. Document attribution,
revision and adaptations before adoption.

Future rank handling must account for intentional downranking for utility
effects, not only maximum damage. See
[intentional downranking](FOREVER_ENGINE_DESIGN.md#intentional-downranking-future-requirement)
before changing rank normalization or explicit player spell selection.

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
