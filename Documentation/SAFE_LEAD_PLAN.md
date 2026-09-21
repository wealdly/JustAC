# Safe Lead: a stable alternative to My List Leads

Status: PLAN. No code yet. Written 2026-09-21, after the 2026-09-20 inference audit.
Revised the same day: assumptions checked against the code, and the fight window added as
the shared foundation (phase 0).

## Why

**My List Leads** inverts the addon's trust model: the user's list owns slot 1 and the game's
pick is only an adviser. That needs the addon to know *when* each ability should be pressed,
and in combat it mostly cannot:

- Player buffs are secret in combat (measured); 234 of 435 shipped single-target SimC entries
  are `delegated` - only the game can time them. Subtlety is nearly all delegated, Protection
  Paladin 100%.
- So delegated entries had to be barred from leading unless they ARE the game's pick, plus a
  fallback to the pick when nothing timeable is in front. After those fixes the lead differed
  from the pick on 1/49 and 12/96 combat ticks - almost all of it the gap closer, which the
  default mode does too. The option reproduces the default through a much longer path.
- Every gap in what the addon can see becomes a **wrong slot 1 for a whole fight, silently**
  (a list without Eviscerate led with Backstab at 7 combo points for 20 seconds). One session
  produced six mode-only bugs.

**Safe Lead** keeps the default trust model and adds one narrow exception:

> Slot 1 is the game's pick - unless that pick is cheap to displace AND the addon holds
> game-issued evidence for something better.

The risk is asymmetric by construction. Worst case: a good ability was pressed instead of a
filler. It never leads on static order, never on an unreadable condition, and an incomplete
list cannot break it, because the pick is the default rather than the fallback.

## The rule

Replace slot 1 only when **both** sides hold.

### A. The pick is cheap to displace

| Pick | How it is known | Notes |
|---|---|---|
| **Wait** | the game returns no pick in combat (`WAIT_SENTINEL`, already detected) | On energy/focus classes a wait is POOLING - see the evidence limits below |
| **Filler** | measured live from the fight window (W2); see "Identifying the filler" | never a cooldown, never a spender, never anything with a gate that is currently satisfied |

### B. The replacement has game-issued evidence

Always required: known, ready (`IsSpellReady`), usable (not `IsUnusableNonResource`), affordable,
in range (`AbilityInRange`), not blacklisted, not held by a user dial, on the GCD.

| # | Evidence | Source (all plain in combat) | Allowed over Filler | Allowed over Wait |
|---|---|---|---|---|
| 1 | **The game never recommends it** - the cooldown class its live list drops, and SimC-inserted abilities (`RotationImport.GetInsertable`, burst triggers) | offline step data + live pool | yes | yes |
| 2 | **Charges capped** | `IsSpellChargeCapped` | yes | yes |
| 3 | **Primary resource capped + the replacement is a spender** | `IsPrimaryPowerCapped`, role data | yes | no |
| 4 | **Confirmed buff window** - open by our own cast or a form read, every other gate readable and passing, and the entry outranks the filler in SimC order | `IsBuffWindowActive(id, dur)`, `SimcGateBlocks` | yes | no |

Deliberately **not** evidence:

- a `delegated` entry, ever (the My List Leads lesson);
- a proc glow alone - the game sees its own procs and still chose the filler;
- a positive window revealed only by the game's pick - vacuous here rather than circular: pick
  windows come from the PICK's own gates, and a wait or a filler has none;
- static list or SimC position.

Off-GCD abilities need no replacement: they do not displace the pick. The slot-2 off-GCD marker
stays the right treatment.

### Why the game's flow keeps moving

The game's rotation is a rule list re-evaluated against current state after every cast, so an
unexpected press just yields a new pick. The one way to stall its plan is to spend something it
was saving. Evidence 3 only exists while the resource is capped (nothing is being saved), 1 and 2
cost nothing the game was counting on, and spenders/builders are barred during a Wait.

## Checked against the code (2026-09-21)

Every assumption above was traced to the function that would have to answer it. What held, and
what the plan had wrong:

| Assumption | Reality | Consequence |
|---|---|---|
| "every other gate readable and passing" = `not SimcGateBlocks(...)` | **Every gate evaluator FAILS OPEN**: unknown resource count, hidden class bar, unanswerable threshold, no target -> "does not block". Right for sinking, wrong for leading. | Needs a tri-state `GatesConfirmed(gates)` - true only when each gate positively HOLDS. New code, small: the evaluators already compute the tri-state internally (`StackHolds`, `ThresholdGateBlocks`), they just collapse it. |
| all gate types are evaluated | `{t="cd"}` (25 in the data) and `{t="dot"}` (57) have **no runtime evaluator at all**; `{t="stack"}` reads an aura, so it is nil for secret player buffs in combat. | An entry carrying any of these is never "confirmed". (`dot` on the entry's OWN dot could later be answered by DotTracker.) |
| evidence 4 has real coverage | 385 non-delegated entries: 320 unconditional, 24 dot-only, **23 buff-gated - 18 positive windows, 10 with a base duration, ~7 distinct abilities** (Putrefy, Secret Technique, Storm Bolt, Rising Sun Kick; Convoke/Mangle via the form read). | Class 4 is narrow. Worth having, not the headline. |
| own-cast windows cover the poster child | Voidblade's window is Metamorphosis (191427): **no base duration** on the cast id (the aura is a separate triggered spell), so it is never confirmable in combat. | Generator gap: `load_aura_secs` should follow the cast's triggered aura when the cast id has no duration. Until then Voidblade only qualifies under class 1 if its window gate is dropped - it must NOT be. |
| class 1 can be tested at runtime | "Never recommended" = absent from the RAW live pool. `WithAdditions` builds exactly that set (`have`) and throws it away. | Keep the added-id set and expose it. Inserted entries still carry gates, so class 1 also needs `GatesConfirmed` (most are unconditional, so this costs little). |
| class 3: "capped + spender" | `IsSpenderSpell` = costs ANY power, so Backstab (energy) is a "spender" - **the filler itself usually qualifies**. The cap signal is the PRIMARY power only, and only while the stock player frame is visible (a replaced unit frame reads permanently false). | Class 3 only means something when the filler does NOT cost the capped power (rage / runic power / maelstrom / insanity builders). Rule: replacement costs the capped power AND the filler does not. On energy classes class 3 never fires - correct, any press fixes an energy cap. |
| class 2: capped charges | Engine read, solid (`GetSpellCharges().isActive == false`, max >= 2). | Pool membership already excludes mobility and defensives; gap closers are suppressed from the tail. No change. |
| filler candidate B: `role == "builder"` | Role data only covers SECONDARY-resource builders/spenders (452/190). Frostbolt, Slam, Bloodthirst, Lightning Bolt have no role; Shuriken Storm is not tagged builder. | Candidate B is weak. Lean on A (Blizzard's last steps) checked against measured C. |
| a Wait is always "nothing to press" | Set only while the assist is available and returns no pick in combat. What it MEANS differs: pooling (energy), mid-cast (casters), everything on cooldown. | The dry run must log "player casting" and "GCD running" beside each wait so the three can be told apart before any replacement ships. |
| discrete resource gates are readable | Validated on 6 classes, and only while the class bar is shown; hidden -> nil. | nil = unconfirmed = no replacement. Already the right direction once `GatesConfirmed` exists. |
| ready / affordable / range / off-GCD | `IsSpellReady` and charges are engine reads; `notEnoughResources` is never secret; `AbilityInRange` nil means "no range requirement" (accept `~= false`); off-GCD is static data. | Hold as written. |

Net: the two strong classes (1 and 2) stand on solid reads. Class 3 needs the "filler does not
cost the capped power" clause. Class 4 needs `GatesConfirmed` and is small. Nothing here needs a
new inference engine - one new function (`GatesConfirmed`), one retained set (added ids), one
generator follow-up (triggered-aura durations).

## Foundation: the fight window

One small ring buffer shared by everything below: the last ~12 abilities the game **served**
(distinct consecutive picks) and the player **used** (own casts - plain in combat), timestamped.
Wiped on leaving combat; a target change writes a marker entry rather than wiping, so consumers
can choose whether history across the swap still counts.

It is the game's own view, a fraction of a second late, so it is **never evidence for leading
over the pick**. It supplies context, measurement and safeguards - and it turns three of this
plan's offline guesses into runtime observations.

Measured on the existing pick logs (Subtlety, 19 fights, 482 served picks):

- Context from the current pick alone flipped single/multi **49** times; from "at least 2
  AoE-only picks among the last 6" it flipped **16** times.
- On 38 served picks the engaged-enemy count read under 2 while the window said AoE (packs on a
  companion, name-only mobs the count cannot see). On 43 the count read 2+ while the game was
  serving single-target picks (two targets, single-target finishers) - the count over-promotes.
- Median 2 served picks between finishers; Shadow Dance served on a steady ~8 s cadence in burst.

| # | Inference from the window | Feeds | Status |
|---|---|---|---|
| W1 | **Target-count context** - majority over recent typed picks; replaces the fixed 8 s sticky memory and may overrule the count in BOTH directions | queue ranking (independent of Safe Lead) | measured, above |
| W2 | **The filler, live** - the ability served most while nothing else is ready, per character and talents | Safe Lead side A | replaces the offline candidates |
| W3 | **Never served** - ready across several fights, never picked | Safe Lead evidence class 1 | observed beats inferred from the raw-pool diff; keep the diff as the cold-start answer |
| W4 | **Flow check** - after the player pressed something other than the pick, did the next pick move on? | Safe Lead agreement metric, live | replaces the offline-only measure |
| W5 | **Stuck pick** - the same pick served for many seconds while the player casts other things or nothing: they cannot press it (off the bars, missing from the list, out of range) | safeguard in every mode | would have flagged the 20 s Eviscerate failure on its own |
| W6 | **Windows with memory** - a window the game revealed two picks ago is still open for its base duration; covers windows the player did not open (procs, talent buffs) | evidence class 4, slot-2 promotion | extends `pickWindows`, which today lasts one tick |
| W7 | **Hidden resets** - served again sooner than its cooldown allows; a DoT served for refresh | DotTracker correction, diagnostics | unmeasured |
| W8 | **Resource rhythm** - spacing of spender picks as the only affordability signal for unreadable continuous resources | later; needs a rage/mana spec to measure | unmeasured |

Limits: six picks is 5-8 seconds, so openers and downtime skew it; history across a target swap
or phase change is wrong until it refills; none of it may seat an ability in slot 1 by itself.

## Identifying the filler

Settled by **W2**: measure it live instead of shipping a guess. The offline candidates remain
only as the cold-start answer for the first pulls of a session:

- Candidate A: the last step(s) of Blizzard's own order (`Data/AssistedCombatOrder.lua`,
  rank = a spell's last step). Reads well for Frost Mage (Frostbolt) but the tail is noisy:
  Subtlety ends Shadowstrike / Shuriken Toss / Sinister Strike, Fury ends Slam / Whirlwind.
- Candidate B: `role == "builder"` - weak, the role data only covers secondary-resource builders
  (see "Checked against the code").

Until the window has seen enough served picks to name a filler with confidence, Safe Lead
replaces a Wait only.

## Phases

0. **Fight window + its two standalone wins** (ships without Safe Lead; no option).
   **BUILT 2026-09-21** on branch `safe-lead` - `FightWindow.lua`, `/jac inspect window
   [selftest]`, pick log field `ctx=` (`*` = carried by the window). Two deliberate gaps:
   the count is still promote-only (W1's "overrule downward" waits for a measurement on a
   spec whose two-target priority really differs), and the stuck-pick hint is `/jac why` only
   (a chat line needs locale keys - fold into the next locale pass).
   - the ring buffer, fed from the existing pick stage and the existing own-cast hook
     (`BlizzardAPI.NoteOwnCast` already sees every cast);
   - **W1** context: the sticky timer becomes window evidence. Verify with the pick log that
     flips drop as measured and that the 38 missed-pack ticks now rank as AoE;
   - **W5** stuck-pick safeguard: a one-line chat hint outside combat, and `/jac why` names it;
   - `/jac inspect window` prints the buffer.
1. **Dry run (no behaviour change).** In `/jac inspect picklog`, per tick: is the pick
   displaceable (Wait, or the **W2** filler), which evidence class would fire - judged by the
   strict `GatesConfirmed`, never the fail-open gate check - and what would lead. Beside each
   Wait: player casting / GCD running, so pooling, mid-cast and all-on-cooldown can be told
   apart. Live metrics from the window, mirrored offline
   (`tools/audit_assisted_combat.py --safelead LOG`):
   - fire rate per fight;
   - **agreement (W4)**: how often the game's NEXT pick is the ability we would have shown
     (high = we only gain a GCD; low = we add something the game would not have asked for -
     inspect those by hand);
   - W2 filler vs offline candidate A, per spec;
   - W3 never-served set vs the raw-pool diff.
   Exit: fire rate worth having on at least two specs, and no evidence class with a bad
   hand-inspected sample.
2. **Prerequisites the code check found:** `GatesConfirmed` (tri-state, strict); keep and expose
   the added-id set from `WithAdditions`; `load_aura_secs` follows a cast's triggered aura when
   the cast id has no duration (Metamorphosis); class 3 requires that the filler does NOT cost
   the capped power.
3. **Opt-in option**, SimC ordering only (the evidence classes come from that data). One toggle
   in the Priority panel. Slot 1 gets a distinct cue when it is a replacement, so a mismatch
   with the game's own highlight reads as intent, not a bug. `/jac why` and the pick log name
   the evidence class. **W6** widens class 4 here.
4. **Retire My List Leads** once Safe Lead has a release of field use: migrate the setting
   (on -> Safe Lead on), delete `leadBarred`, `LEAD_BARRED_PENALTY`, the pick fallback and the
   option. Everything generic it produced stays: GCD lookahead, usability gating, the range
   read, transform handling. W5 takes over the pick fallback's job in the modes that remain.

Later, separately measured: W7 (reset / DoT correction) and W8 (resource rhythm).

## Implementation sketch (phase 3)

One stage after the queue is assembled, default mode only:

```
if slot 1 is WAIT or window.filler == slot1 then
    for each entry in the promoted bucket, in rank order:
        cls = EvidenceClass(entry)          -- 1..4 above, nil otherwise; GatesConfirmed inside
        if cls and Allowed(cls, slot1IsWait) then
            swap entry into slot 1, the pick moves to slot 2; break
```

The promoted bucket already exists (charge cap, power cap, confirmed window), so the evidence
checks are reuse, not new inference. New code: the fight window, `GatesConfirmed`, the class-1
test (never-served set, raw-pool diff at cold start), the swap, the cue.

## Limits to state in the option's tooltip

- Blizzard's one-button assist key always casts the game's pick; a replacement can only be
  pressed from its own keybind.
- Everything it promotes already shows in slot 2 with a glow. The gain is for players who
  watch slot 1 - which is most of them, but it is one GCD, not a different rotation.
