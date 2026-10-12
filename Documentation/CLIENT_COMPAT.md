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
   changes are listed below as such; anything else is gated.
5. **Every leak is a test.** `tools/test_forever_defaults.py` loads the real SpellDB,
   RotationImport, Forever lists and Forever defaults as retail and asserts nothing Forever
   registers there. `tools/test_forever_dots.py` checks the DoT tracker's retail half.

## File organization

Forever-only generated runtime data lives in `Data/Forever/`: `Rotations.lua`,
`Defaults.lua`, and `Consumables.lua`. Each retains its original client guard or
gated registration, and the TOC retains the original dependency order.

The `gen_forever_*.py` generators own these output paths and create the destination
directory when needed. Vendored APLs remain in `tools/forever-apl-src/`, hand pins
in `tools/simc-apl-forever/`, and generator/test scripts in `tools/`.

The queue, API helpers and UI remain shared. Extract client policy only when it
removes substantial client-specific logic, not just to relocate every small branch.
`build.ps1` derives its source list from the TOC and preserves nested directories;
`.pkgmeta` includes the data directory without an explicit per-file manifest.

## Source snapshot (2026-10-12)

The vendored Forever simulator APLs now pin commit
`96719dc69ff3e93de4a8b0eff4653e7df269a604` in
`tools/forever-apl-src/UPSTREAM_COMMIT`. Compared with the previous pin,
21 vendored APLs changed; regeneration uses the existing curated extras,
role routing and out-of-combat opener policy.

Spell/rank resolution still uses the complete single-build Forever DB2 export
`1.60.1.70245`. Upstream's simulator database reports `1.60.1.70338` with
October 12 hotfixes, but requests to Wago's build index and the newer SpellName
CSV endpoint timed out. No partial CSV refresh or mixed-build join was performed.
Simulator spell-database updates are not proof that our complete CSV export is
available or current.

The generator retains three ordering contexts, but target-count conditions
now survive as runtime `targets` gates. The AoE context includes conditions
that can hold from three through forty observed enemies, so four-target
Blizzard and Beast Mastery Volley remain present and require four engaged
enemies. No count (zero/unknown) does not confirm such a gate. Nameplate
coverage and threat visibility limit this observed count; it is not a census.

Imported missing-totem conditions use `totem` gates backed by the shared
live duration-presence reader, not a cast-observed buff window. Unknown reads
do not authorize replacement.

Mana paced against remaining fight duration becomes an explicit `unconfirmed`
branch that does not authorize a cast. Fire Nova retains its confirmed
three-target alternative without acquiring unconditional single-target
priority. An unconfirmed pacing-only line cannot mask an unconditional filler
for the same spell later in that context. Fight-duration prediction is not
implemented. Constant fight-length conditions retain the existing steady-state
policy.

Stack gates still return unknown when aura lookup is denied. No hidden stack
count is inferred, and the existing fail-open sinking behavior is unchanged.

## Forever ability routing

`tools/gen_forever_defaults.py` owns `FOREVER_ABILITY_ROLES`, elemental totem
slots and maintained-protection membership in `Data/Forever/Defaults.lua`.
The automatic queue excludes pure protection, healing, mitigation, resource
support and utility roles, but preserves mixed damage/defense abilities.
The broad bar-eligibility pool in `Data/Forever/Rotations.lua` remains intact,
so custom entries and Always Show can bypass automatic routing.

Mapped totems use one shared duration-presence read. A successful nil duration
means an empty slot (measured in and out of combat); a thrown call is reported
once per distinct error and returns unknown, which does not authorize replacing
a totem. Automatic offensive and defensive recommendations preserve occupied
elemental slots, avoiding Stoneskin/Strength of Earth replacement loops.

Maintained protection is selected from the player's editable defensive list.
It is offered while missing even in Low Health Only mode, behind urgent personal
and group healing. Combat Only still hides it out of combat. Removing it from
the list disables the offer. Templar's Bulwark and Elune's Grace use the normal
defensive list; school-specific wards and situational protection are classified
but do not gain unconditional automatic defensive offers.

Only an exact unchanged prior default list migrates to the new defaults, once.
Reordering, adding or removing entries preserves the player's list. Customized
lists can adopt additions using Restore Class Defaults. Retail has no Forever
role, slot, migration or maintained-protection data.

Regression coverage: `tools/test_forever_protection.py` runs the real routing
filter, totem-duration probe, defensive queue and default migration, including
API failure, nil duration, active/empty transitions, rank resolution and retail
isolation.

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
