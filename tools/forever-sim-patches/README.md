# Local changes to the WoW Forever simulator

`local.patch` holds the changes `tools/forever_sim_bench.py` and `tools/forever_sim_sweep.py`
rely on that are not upstream. They live only in a working copy of the simulator, so this
folder is the copy that survives a fresh checkout.

- Simulator: https://github.com/gunba/wow-forever-sim (MIT License, Copyright (c) 2024 wowsims
  team). The patch is a derived work of that code and stays under its MIT License.
- Base revision: `8a956cdd4edb51560c02c3a330f93e4b9b2459f7`.

Apply and build (from the simulator checkout; the rank tables are generated, not in the patch):

    git apply <JustAC>/tools/forever-sim-patches/local.patch
    python <JustAC>/tools/forever-sim-patches/gen_class_ranks.py --sim .
    python <JustAC>/tools/forever-sim-patches/gen_pet_levelstats.py --sim . --db <vmangos world database as SQLite>
    go build -tags=with_db -o wowsimcli.exe ./cmd/wowsimcli

Then `python tools/forever_sim_sweep.py --sim <checkout>` shows, per class, tree and level, whether
the simulator presses what the generated list names, flags damage far from the client's, and lists
any action pressed over and over for no damage (an aura check that never matches what the simulator
applies).

## What it changes

| Change | Why | Status |
|---|---|---|
| `sim/core/sim.go` Cleanup keeps the kill time as the iteration's duration in a fight sized by health | The simulator overwrote it with the nominal 600 s, so fight length, damage per second and aura uptimes were unusable. The bench timed fights by counting target swings: 2 s steps, and slow whenever the target's attacks were slowed (Thunder Clap, 20%) | Verified against the swing clock on a run with no slow (within 0.2 s). The first version of this change cut every fight to the first iteration's length; every bench report now prints the largest difference between the two clocks so that cannot hide |
| `sim/core/pull_model_local.go` (with hooks in `unit.go`, `pet.go`, `spell.go`, `sim.go`): a pull model, on only when the environment variable `WOWSIM_PULL_MODEL` is `1` (the bench sets it) | A simulated fight started at time zero with the target already swinging and a pet already on the target. In game a fight starts when the first attack lands: a caster's opening cast is free, the target has to run to a caster, a pet has to run to the target | Checked against six level 15 hunter fights logged in game (a boar, target one level below): 11 to 15 s, hunter 251 and pet 105 damage a fight; the model gives 12.0 s, 264 and 93 (without it 10.9 s, 237 and 126). The 7 yards a second approach speed is ASSUMED |
| `sim/priest/power_word_shield.go`: Power Word: Shield from the client rank data (absorb by level, mana, 30 s, Weakened Soul 15 s), registered for every priest | Upstream it was commented out, so every simulated priest was pushed back by every hit. The simulator already skips pushback for a hit whose damage is fully absorbed | The bench casts it before each pull (PREPULL). Improved Power Word: Shield's 5% a point is ASSUMED unchanged |
| Mage Arcane Blast uses the rank the level has | It used the level 60 rank's 218-254 at every level: about seven times too hard at 30 | Client ranks at 20/30/40/50/60 |
| `sim/core/wand.go`, `attack.go`: a wand auto attack for casters, on for warlock, priest (shadow, smite) and mage; a channel stops it like a cast; Wand Specialization adds 13% / 25% | The engine had no wand. Until 2026-11-23 only the warlock had it, so every earlier priest and mage run compared casts with no wand | Model ASSUMED, not measured (the file's header lists each assumption) |
| `sim/core/spell_rank.go` and `sim/<class>/level_ranks_generated.go` (rogue, druid, hunter, warlock; from `gen_class_ranks.py`): every rank of every learnable ability from the client spell tables | Rogue attacks, feral Maul, Shred, Swipe and Claw, hunter melee attacks and pet abilities and warlock demons, curses and armors existed only at levels 25, 40, 50 and 60: a character of another level pressed nothing | Level 60 results unchanged (compared old and new binaries); values at 25, 40 and 50 agree with the old tables except where listed below |
| Hunter pet body and warlock demon stats by level, from `sim/core/pet_levelstats_generated.go` (`gen_pet_levelstats.py`, the vmangos `pet_levelstats` table) | The pet had level 60 stats at every owner level; demons had stats at four levels | The simulator's own level 60 pet and its demon rows at 25, 40, 50 and 60 are rows of that Classic table, so its other levels are the same data. The hunter pet's base hit is linear in level, as Classic's formula is. Demon weapon damage, which the table lacks, is interpolated. Whether WoW Forever changed these curves is not measured |
| Druid: forms not registered before they are learned; Bear Form below 40; Classic-ruleset paw damage by level | A level 5 druid fought in Cat Form with level 60 numbers | Linear paw scaling is the Classic rule; the level 60 anchor is the simulator's |
| `sim/core/crit_levels_local.go`; every class reads crit per agility and spell crit per intellect for its level | Only the warrior did. The level 60 rate understated low-level crit several times over (a level 10 priest: 0.1273% per intellect against 0.0168%) | From the client's PlayerExpectedStat, already in the simulator |
| `sim/core/gcd.go`, `character.go`, `cast.go`: a cast whose time is up completes before another cast starts (`completeDueHardcast`) | A cast ending at the same instant as its global cooldown completes inside the global cooldown action; a wand shot at that instant let the rotation start the next cast first, which overwrote the finished one, so it never landed (2026-11-24: a level 10 priest's Mind Blast landed in 9% of fights, kills 14.4 s, 11.2 s once fixed) | Checked in the combat log of a level 10 fight. `TestStunCastLifecycleCallbacks` and the upstream class tests fail with and without the change |
| `sim/shaman/level_ranks.go`, `lightning_bolt.go`, `chain_lightning.go`: Lightning Bolt and Chain Lightning damage and spell power coefficient from the generated client ranks | The hand tables came from earlier clients: by client 71037 Chain Lightning rank 1 was 215 at 0.714 (here 85 to 97 at 0.571) and Lightning Bolt ranks 3 to 5 had risen (52, 73, 109). Mana cost and cast time stay the simulator's, which records deliberate changes to them | The sweep's damage check flagged Chain Lightning at 40 (133 a cast against the client's 348); nothing flagged after |
| `sim/paladin/hammer_of_the_righteous.go` (registered in `paladin.go`): Hammer of the Righteous from level 40 | The simulator had no action for it, so every Protection run at 40 and above failed | Client 71037 spell 407632: Holy damage of three times the main hand's damage per second on the target and up to three more, 6% of base mana, a 6 s cooldown. ASSUMED: weapon damage per second includes attack power as the white swing does; threat is the damage's; its own cooldown (the Crusader Strike it names does not exist in Forever) |
| `sim/warrior/shield_block.go`, `warrior.go`, `tank_warrior/tank_warrior.go`: Shield Block registered for every warrior and pressable by a rotation | It was registered only for the tank spec (the bench runs Protection as the general warrior spec) and only as a major cooldown that never fires, so no list could press it | Unchanged spell: 10 rage, 5 s cooldown, 7 s or two blocks in Forever. With it, Protection's blocks refund rage (Shield Specialization) and open Revenge |
| `sim/warrior/warrior.go`, `heroic_strike_cleave.go`: one pending next-swing slot for Heroic Strike and Cleave | Each queued attack waits out a reaction delay; during it the other could queue as well and replace it when its own delay ended, so a list with Cleave above Heroic Strike never landed a Cleave on a pack | The queue never displaces a queued next-swing attack; pressing both remains possible in game |

## Bench-side choices that go with these changes (tools/forever_sim_bench.py)

- The queue's wand-or-cast rule: a caster's single-target cast-time spell is pressed over the
  wand only while its paper damage per second, pushed back by the expected hits once the target
  is on the caster, beats the wand's (`--no-weapon-rule` turns it off). Wand Specialization (13%
  a rank) counts, and a priest's or mage's derived talent build takes its two ranks first, as
  the levelling guides do; the simulator's presets are level 60 builds that reach it last.

- A warlock fights beside an imp and a hunter beside a cat from level 10 unless `--pet` says
  otherwise. Without a demon, a Demonology list cast Searing Pain without end.
- The hunter pet swings every 2.0 s (`petAttackSpeed: Two`). Left out, the simulator's option
  reads as its first value, a 1.0 s swing, and in Forever a faster pet keeps its full hit: that
  doubled the pet's white damage in every pet run before 2026-11-23 (53% of a level 60 hunter's
  damage; 40% with the 2.0 s swing). With the Classic table and this swing the pet is 40 to 48%
  of the damage at 10 to 60 and a hunter still kills about twice as fast as other classes at 10
  to 30. That matches two damage sources, but no Forever pet damage has been measured in game.
- A rogue casts Stealth a second before every pull, in every arm, so Ambush can open. Garrote
  still needs the rogue behind the target, which a fight from the front never gives.
- An entry cast to keep up an aura the simulator does not have is left out, not cast forever.
- The rank tables exist for every class but the bench reads them as simulator ids only for
  rogue, druid, hunter and warlock, whose code registers spells from them.

`tools/forever_sim_sweep.py` also compares each spell's simulated damage per cast with the
client's spell data (the rank the level has, five combo points for a finisher whose duration grows
with them; physical attacks are left out, their attack power scaling being server-side) and lists
any that is far off (the check that would have caught Arcane Blast
and the druid's Claw). 2026-11-23: nothing flagged; 1 of 164 tree-levels fails (the enhancement
shaman at level 5).

## Where the client data disagreed with the simulator's old bracket values

The client value was taken unless noted:

- Shred at 25: bonus 24 became 22 (the level 30 rank was skipped before).
- Demoralizing Roar: ranks are learned at 10/20/32/42/52, not 10/20/30/40/50.
- Wing Clip at 50: rank 2, not rank 3. Lightning Breath at 40: rank 4, not rank 3.
- Curse of the Elements at 40: 60 resistance and 8%, not 75 and 10%.
- Incinerate at 40 and 50: the old values were those nine levels after learning the rank.
- NOT changed, still the simulator's values: Mutilate (client: three ranks at 40/50/60 with 44/63/88 flat at 90% weapon damage; simulator: 23/33/48/67 at 75%), Rake, Rip and Ferocious Bite (client about 1.25 times the simulator), Primal Bite (client ranks at 40/50/60), imp Firebolt ranks 1 to 4 (client 6/11/15/18 with per-level growth; simulator 4/7/12/17).

## Still not at every level

- Rogue poisons use the highest bracket row at or below the level and nothing below 20; Mutilate likewise.
- Shaman weapon imbues are ranked at 25, 40, 50 and 60.
- `core.FaerieFireAura` and `core.DemoralizingRoarAura` are the top rank at every level.
- The simulator has no Shank, Cheap Shot, Bash, Pounce or Ravage.

## Regenerate the patch after changing the working copy

    git diff > local.patch
    for f in $(git ls-files --others --exclude-standard | grep '\.go$' | grep -v '_generated\.go$'); do
        git diff --no-index /dev/null "$f" >> local.patch
    done
