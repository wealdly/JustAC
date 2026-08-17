# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Generates Data/TargetDots.lua from client data CSV exports.
#
# Maintained enemy DoT applicators: rotation CAST spells that apply a
# non-stacking periodic-damage debuff to an enemy target. Re-casting one while
# its debuff is already up on the target is (until the refresh window) wasted -
# DotTracker sinks these to the back of the queue while the debuff is live.
#
# Each entry maps the cast spell -> its debuff's estimated duration in seconds
# (0 = unknown). DotTracker un-sinks the spell ~30% before that estimate so the
# player can refresh inside the pandemic window. MaxDuration is used: exact for
# fixed DoTs, and the full-resource value for combo-point DoTs (a 5-CP Rip is
# 24s) - a shorter real duration is caught by the live aura-removal bridge.
#
# A cast qualifies if it EITHER directly applies such an aura (Rip self-applies
# its bleed) OR triggers a spell that does (Rake casts, triggers its bleed
# aura). The DURATION resolves through that link - Rake's 15s comes from its
# triggered bleed, not the cast. Stacking debuffs are EXCLUDED on purpose (same
# rule as self-buffs): a stacking DoT must keep being suggested so the player can
# build stacks. DoTs whose stacks ramp PASSIVELY (Agony ticks add its own stacks;
# recasting is still a wasted refresh) are false positives of that rule - curate
# them back in below. Channeled casts are excluded (a channel is not a maintained
# DoT).
#
# Script-driven applicators (e.g. Primal Wrath applies Rip via a server-side
# script effect with no trigger link in the data) are in CURATED below, mapped to
# the aura spell they apply so the duration still resolves.
#
# Inputs (wago.tools CSV exports): SpellEffect, SpellAuraOptions, SpellMisc,
#   SpellDuration, SkillLineAbility, SpecializationSpells, TraitDefinition,
#   SpellName
# Run: python tools/gen_target_dots.py [csv_dir] [build]

import csv
import re
import sys
from pathlib import Path

DEFAULT_CSV_DIR = Path(__file__).resolve().parent.parent / "Documentation" / "wow_spell_csv"

EFFECT_APPLY_AURA = 6
TARGET_UNIT_CASTER = 1
# Periodic-damage aura sub-types (EffectAura when Effect == APPLY_AURA).
# 3 = periodic damage, 53 = periodic leech (drain DoTs: Phantom Singularity,
# Siphon Life), 89 = periodic damage %.
PERIODIC_DAMAGE_AURAS = {3, 53, 89}
# SpellMisc.Attributes_1 channel flags (SPELL_ATTR1_CHANNELED_1 | _2).
CHANNELED_FLAGS = 0x4 | 0x40
# SpellMisc.Attributes_0 passive flag - a passive record is never the cast button.
SPELL_ATTR0_PASSIVE = 0x40

# Script-driven applicators the effect data can't link: cast spell -> aura spell
# it applies (the aura supplies the duration). Vetted by hand.
#
# Prefer curating the BASE spell (what C_Spell.GetBaseSpell resolves to): the
# runtime lookup resolves every talent/override variant to its base, so one base
# entry covers the whole family. E.g. base Moonfire 8921 (script-applied, so the
# effect data has no periodic-damage link) also covers Lunar Inspiration's 155625
# because GetBaseSpell(155625) == 8921. Curate a variant ID directly only when it
# does NOT resolve to a curated base.
CURATED = {
    285381: 1079,     # Primal Wrath applies Rip to all nearby targets via script
    8921:   164812,   # Moonfire (base) - script-applies its DoT; covers all specs
                      # and talent variants via GetBaseSpell (e.g. 155625 -> 8921)
    93402:  164815,   # Sunfire (Balance) - script-applies its DoT, no trigger link;
                      # mirrors Moonfire. Without this the cast never maps and Sunfire
                      # never sinks while its debuff is live (only the dead aura id 164815
                      # was emitted, which UNIT_SPELLCAST_SUCCEEDED never delivers).
    # Passively-stacking DoTs the CumulativeAura rule wrongly drops: their stacks
    # ramp on their own (ticks / other spells), so recasting while live is still
    # a wasted refresh - exactly what the sink exists for. The APLs refresh all
    # three only when refreshable, same as non-stacking DoTs.
    980:     980,     # Agony (stacks ramp per tick, not per cast)
    1259790: 1259790, # Unstable Affliction
    445468:  445474,  # Wither cast -> its stacking DoT aura
    348:     157736,  # Immolate - script-applies its DoT (no trigger link)
}
CURATED_NAMES = {
    285381: "Primal Wrath (applies Rip via script)",
    8921:   "Moonfire (base; covers talent variants via GetBaseSpell)",
    93402:  "Sunfire (script-applies its DoT)",
    980:    "Agony (stacks ramp passively; recast is still a wasted refresh)",
    1259790: "Unstable Affliction (stacking false positive)",
    445468: "Wither (stacking false positive)",
    348:    "Immolate (script-applies its DoT)",
}

# Spells the periodic-damage filter catches but that are owned by another
# subsystem (so they must not double-classify as maintained DoTs here).
EXCLUDE = {
    2818,   # Deadly Poison (on-hit proc; poison imbue handled by RedundancyFilter)
    2823,   # Deadly Poison (weapon imbue self-buff, hour-long)
    335467, # Shadow Word: Madness - resource spender, recast while its DoT is
            # live by design (must keep being suggested, never sink)
    431044, # Frostfire Bolt - spammable filler whose DoT is a small rider
            # (~92% of its damage is the direct hit); sinking a filler is wrong.
            # Rule of thumb: a no-cooldown spell whose direct hit outweighs its
            # DoT must never sink (CD-gated ones are parked by the CD sink anyway).
}


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        yield from csv.DictReader(f)


def main():
    csv_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV_DIR
    build = sys.argv[2] if len(sys.argv) > 2 else max(
        (m.group(1) for p in csv_dir.glob("*.csv") for m in [re.search(r"\.(\d+\.\d+\.\d+\.\d+)\.csv$", p.name)] if m),
        key=lambda b: [int(x) for x in b.split(".")], default="unknown")  # header stamp follows the folder

    def find(table):
        hits = sorted(csv_dir.glob(f"{table}.*.csv"))
        if not hits:
            sys.exit(f"missing {table} csv in {csv_dir}")
        return hits[-1]

    # Player-learnable spell universe (spells the player can actually cast).
    universe = set()
    for row in read_csv(find("SkillLineAbility")):
        universe.add(int(row["Spell"]))
    for row in read_csv(find("TraitDefinition")):
        for col in ("SpellID", "VisibleSpellID", "OverridesSpellID"):
            v = int(row[col] or 0)
            if v > 0:
                universe.add(v)
    # Spec-granted spells live here, not in SkillLineAbility (Immolate,
    # Vampiric Touch, ...).
    for row in read_csv(find("SpecializationSpells")):
        for col in ("SpellID", "OverridesSpellID"):
            v = int(row[col] or 0)
            if v > 0:
                universe.add(v)

    # durationIndex per spell (base difficulty) -> MaxDuration seconds.
    dur_index = {}
    for row in read_csv(find("SpellMisc")):
        if int(row["DifficultyID"] or 0) == 0:
            dur_index[int(row["SpellID"])] = int(row["DurationIndex"] or 0)
    dur_secs = {0: 0}
    for row in read_csv(find("SpellDuration")):
        ms = int(row["MaxDuration"] or 0)
        dur_secs[int(row["ID"])] = round(ms / 1000) if ms > 0 else 0

    def aura_duration(aura_id):
        return dur_secs.get(dur_index.get(aura_id, 0), 0)

    # dot_auras: spells whose APPLY_AURA effect deals periodic damage to a
    # non-caster target. Keyed by the aura spell ID (may differ from the cast).
    dot_auras = set()
    for row in read_csv(find("SpellEffect")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        if (int(row["Effect"] or 0) == EFFECT_APPLY_AURA
                and int(row["EffectAura"] or 0) in PERIODIC_DAMAGE_AURAS
                and int(row["ImplicitTarget_0"] or 0) != TARGET_UNIT_CASTER):
            dot_auras.add(int(row["SpellID"]))

    # Exclude stacking auras: a stacking DoT must keep being suggested.
    for row in read_csv(find("SpellAuraOptions")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        sid = int(row["SpellID"])
        if sid in dot_auras and int(row["CumulativeAura"] or 0) > 1:
            dot_auras.discard(sid)

    # Channeled cast spells (a channel isn't a maintained DoT), and passive records.
    channeled = set()
    passive = set()
    for row in read_csv(find("SpellMisc")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        if int(row["Attributes_1"] or 0) & CHANNELED_FLAGS:
            channeled.add(int(row["SpellID"]))
        if int(row["Attributes_0"] or 0) & SPELL_ATTR0_PASSIVE:
            passive.add(int(row["SpellID"]))

    # cast_aura: cast spell -> the dot aura it applies (for duration lookup).
    # Direct (cast IS a dot aura) takes precedence over triggered.
    cast_aura = {}
    for aura in dot_auras:
        if aura in universe:
            cast_aura[aura] = aura
    for row in read_csv(find("SpellEffect")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        sid = int(row["SpellID"])
        trig = int(row["EffectTriggerSpell"] or 0)
        if sid in universe and sid not in cast_aura and trig in dot_auras:
            cast_aura[sid] = trig

    for cast, aura in CURATED.items():
        cast_aura[cast] = aura
    for sid in channeled:
        cast_aura.pop(sid, None)
    for sid in EXCLUDE:
        cast_aura.pop(sid, None)

    names = {int(r["ID"]): r["Name_lang"] for r in read_csv(find("SpellName"))}

    def nm(sid):
        if sid in CURATED_NAMES:
            return CURATED_NAMES[sid]
        return (names.get(sid) or "?").replace("\r", "").replace("\n", " ")

    lines = [
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2024-2026 wealdly",
        "-- JustAC: Maintained enemy DoT applicator cast spells -> debuff duration (s).",
        "-- While the debuff is live on the current target, DotTracker sinks these to the",
        "-- back of the queue, un-sinking ~30% before the duration estimate (pandemic",
        "-- refresh window) or earlier if the live aura-removal bridge sees it drop.",
        "-- 0 = unknown duration (no pandemic lead; rely on the removal bridge). Stacking",
        "-- DoTs and channels are excluded (they must keep being suggested).",
        f"-- GENERATED by tools/gen_target_dots.py from client data build {build}.",
        "-- Do not hand-edit (script-driven applicators go in the generator's CURATED list).",
        'local SpellDB = LibStub("JustAC-SpellDB", true)',
        "if not SpellDB or not SpellDB.RegisterTargetDots then return end",
        "",
        "SpellDB.RegisterTargetDots({",
    ]
    for sid in sorted(cast_aura):
        lines.append(f"[{sid}]={aura_duration(cast_aura[sid])},  -- {nm(sid)}")
    lines += ["})", ""]

    out_path = Path(__file__).parent.parent / "Data" / "TargetDots.lua"
    out_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{out_path}: {len(cast_aura)} DoT applicators, "
          f"{len(dot_auras)} dot auras, universe {len(universe)}, build {build}")

    # Systematic check for the class of miss that hid Sunfire: a dot aura in the
    # universe whose CAST is a distinct same-named spell not mapped here. Reported,
    # never auto-added - some hits are design-excluded (cooldown-parked bursts like
    # Odyn's Fury, poison imbues). Curate the genuine maintained DoTs in CURATED.
    import re as _re
    byslug = {}
    for s in universe:
        n = names.get(s)
        if n:
            byslug.setdefault(_re.sub(r"[^a-z0-9]+", "_", n.lower().replace("'", "")).strip("_"), set()).add(s)
    hints = []
    for a in sorted(dot_auras & universe):
        sl = _re.sub(r"[^a-z0-9]+", "_", (names.get(a, "")).lower().replace("'", "")).strip("_")
        sibs = sorted(c for c in byslug.get(sl, ())
                      if c != a and c not in dot_auras and c not in channeled
                      and c not in passive and c not in cast_aura)
        if sibs:
            hints.append(f"  aura {a} '{names.get(a, '')}' <- unmapped cast {sibs}")
    if hints:
        print("possible unmapped script-applied DoT casts (curate the maintained ones):")
        print("\n".join(hints))


if __name__ == "__main__":
    main()
