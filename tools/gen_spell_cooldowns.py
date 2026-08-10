# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Generates Data/SpellCooldowns.lua from client data CSV exports.
#
# Static base cooldown/charge data for local cooldown tracking: runtime CD APIs
# (GetSpellBaseCooldown, tooltips, C_Spell.GetSpellCharges) are secret in combat,
# so a spell never seen out of combat has no duration and IsSpellReady fails open.
# This table is the in-combat last resort (base values, unmodified by talents).
#
# Inputs (same folder, wago.tools CSV exports):
#   SpellCooldowns.csv     - per-spell RecoveryTime / CategoryRecoveryTime
#   SpellCategories.csv    - per-spell ChargeCategory
#   SpellCategory.csv      - per-category MaxCharges / ChargeRecoveryTime
#   SkillLineAbility.csv   - player-learnable spell filter
#   TraitDefinition.csv    - talent spell filter
#   SpecializationSpells.csv - spec-granted spell filter (Penance, Purify, ...:
#                            granted by spec assignment, absent from both tables above)
#
# Run: python tools/gen_spell_cooldowns.py [csv_dir] [build]
# (csv_dir defaults to Documentation/wow_spell_csv, same as the sibling generators;
#  build defaults to the one in the CSV filenames)

import csv
import re
import sys
from pathlib import Path

MIN_CD_MS = 3000  # matches MIN_TRACKABLE_CD_SECS in CooldownTracking.lua
DEFAULT_CSV_DIR = Path(__file__).resolve().parent.parent / "Documentation" / "wow_spell_csv"


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        yield from csv.DictReader(f)


def main():
    csv_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV_DIR
    build = sys.argv[2] if len(sys.argv) > 2 else None

    def find(table):
        hits = sorted(csv_dir.glob(f"{table}.*.csv"))
        if not hits:
            sys.exit(f"missing {table} csv in {csv_dir}")
        return hits[-1]

    # Stamp the header with the build the data actually came from: a hardcoded
    # default here once shipped a build string ahead of the real CSVs.
    if not build:
        m = re.search(r"\.([\d.]+)\.csv$", find("SpellCooldowns").name)
        build = m.group(1) if m else "unknown"

    # Player-relevant spell universe: class/profession skill lines + talents
    # + spec grants (SpecializationSpells: baseline spells granted by spec
    # assignment - Penance, Purify, Naturalize - reachable via neither
    # SkillLineAbility nor TraitDefinition).
    universe = set()
    for row in read_csv(find("SkillLineAbility")):
        universe.add(int(row["Spell"]))
    for row in read_csv(find("TraitDefinition")):
        for col in ("SpellID", "VisibleSpellID", "OverridesSpellID"):
            v = int(row[col] or 0)
            if v > 0:
                universe.add(v)
    for row in read_csv(find("SpecializationSpells")):
        for col in ("SpellID", "OverridesSpellID"):
            v = int(row[col] or 0)
            if v > 0:
                universe.add(v)

    # Charge categories: ID -> (MaxCharges, ChargeRecoveryTime)
    categories = {}
    for row in read_csv(find("SpellCategory")):
        max_charges = int(row["MaxCharges"] or 0)
        recharge = int(row["ChargeRecoveryTime"] or 0)
        if max_charges >= 1 and recharge > 0:
            categories[int(row["ID"])] = (max_charges, recharge)

    # Per-spell charge assignment (base difficulty only)
    charges = {}
    start_cat = {}
    for row in read_csv(find("SpellCategories")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        sid = int(row["SpellID"])
        cat = categories.get(int(row["ChargeCategory"] or 0))
        if cat:
            charges[sid] = cat
        start_cat[sid] = int(row["StartRecoveryCategory"] or 0)

    # Flat cooldowns (base difficulty only)
    flat = {}
    start_time = {}
    for row in read_csv(find("SpellCooldowns")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        sid = int(row["SpellID"])
        eff = max(int(row["RecoveryTime"] or 0), int(row["CategoryRecoveryTime"] or 0))
        if eff > 0:
            flat[sid] = eff
        start_time[sid] = int(row["StartRecoveryTime"] or 0)

    # Off-GCD: triggers no global cooldown, so the next ability can be pressed immediately.
    #   StartRecoveryTime == 0     - REQUIRED, and the row must exist. This is the positive
    #                                evidence: the spell explicitly starts no global recovery.
    #   StartRecoveryCategory == 0 - required only IF the row exists. A MISSING categories row
    #                                means no recovery category is assigned, which is exactly
    #                                what off-GCD looks like - so absent is treated as 0.
    # The asymmetry is deliberate and was got wrong once. Requiring a SpellCooldowns row is the
    # safety catch: ~1900 learnable spells carry StartRecoveryCategory=0 with NO cooldown row -
    # legacy duplicate ids, mounts, tracking and profession casts - and category alone would
    # flag every one of them. But ALSO demanding a categories row wrongly rejected real
    # abilities that simply have no category assigned (Tiger's Fury 5217 is the proof case:
    # StartRecoveryTime=0, no SpellCategories row at all), leaving the marker dark on them.
    # A false positive is worse than a miss - it tells a player to move on while a real GCD
    # is running - so the cooldown row stays mandatory while the category row does not.
    # Widened universe, for the off-GCD set only - the cooldown table above keeps its own.
    # The grant tables are not enough: some live abilities (Symbols of Death) appear in
    # NONE of SkillLineAbility / TraitDefinition / SpecializationSpells / CooldownSetSpell,
    # so they are reachable only via the class spell family. Dropping the universe entirely
    # is not an option either - that is 13.5k spells, nearly all of them NPC.
    gcd_universe = set(universe)
    for row in read_csv(find("SpecializationSpells")):
        for col in ("SpellID", "OverridesSpellID"):
            v = int(row[col] or 0)
            if v > 0:
                gcd_universe.add(v)
    for row in read_csv(find("SpellClassOptions")):
        if int(row["SpellClassSet"] or 0) > 0 and int(row["SpellID"] or 0) > 0:
            gcd_universe.add(int(row["SpellID"]))

    off_gcd = {sid for sid in gcd_universe
               if start_time.get(sid) == 0 and start_cat.get(sid, 0) == 0}

    # Guards the rule in BOTH directions. The FLAGGED ids are known off-GCD abilities - 5217
    # Tiger's Fury specifically has NO SpellCategories row, so it fails the moment anyone
    # makes that row mandatory again. The UNFLAGGED ones are the opposite trap: each has
    # StartRecoveryCategory=0 but NO SpellCooldowns row, so dropping the `start_time` half
    # of the test silently marks all of them as off-GCD.
    for sid in (5217, 1719, 108853, 53600, 190319, 1766, 212283):  # Tiger's Fury .. Symbols of Death
        assert sid in off_gcd, f"expected {sid} to be off-GCD"
    for sid in (5374, 75, 468, 1329, 8921):   # legacy Mutilate, Auto Shot, a mount, Mutilate, Moonfire
        assert sid not in off_gcd, f"{sid} must NOT be flagged off-GCD"

    # Merge: charge spells (max > 1) emit {max, rechargeMs}; single-charge spells
    # are flat cooldowns implemented as charges - fold into the flat value.
    out = {}
    for sid in universe:
        cd = flat.get(sid, 0)
        ch = charges.get(sid)
        if ch and ch[0] > 1:
            if ch[1] >= MIN_CD_MS:
                out[sid] = ch
            continue
        if ch:  # single charge: recharge acts as the cooldown
            cd = max(cd, ch[1])
        if cd >= MIN_CD_MS:
            out[sid] = cd

    names = {int(r["ID"]): r["Name_lang"] for r in read_csv(find("SpellName"))}

    def nm(sid):
        return (names.get(sid) or "?").replace("\r", "").replace("\n", " ")

    lines = [
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2024-2026 wealdly",
        "-- JustAC: Static base cooldown/charge data (in-combat last resort for local",
        "-- cooldown tracking; runtime CD APIs are secret in combat).",
        f"-- GENERATED by tools/gen_spell_cooldowns.py from client data build {build}.",
        "-- Do not hand-edit. Flat entry: [spellID] = cooldownMs.",
        "-- Charge entry: [spellID] = {maxCharges, rechargeMs}.",
        "-- OFF_GCD: spells that start no global cooldown (press and continue immediately).",
        'local lib = LibStub:NewLibrary("JustAC-CooldownData", 2)',
        "if not lib then return end",
        "",
        "local D = {",
    ]
    for sid in sorted(out):
        v = out[sid]
        if isinstance(v, tuple):
            lines.append(f"[{sid}]={{{v[0]},{v[1]}}},  -- {nm(sid)}")
        else:
            lines.append(f"[{sid}]={v},  -- {nm(sid)}")
    lines += ["}", "", "local OFF_GCD = {"]
    for sid in sorted(off_gcd):
        lines.append(f"[{sid}]=true,  -- {nm(sid)}")
    lines += [
        "}",
        "",
        "--- True when casting this spell starts no global cooldown, so the next ability",
        "--- can be pressed immediately. Absent id = unknown -> false (never a wrong claim).",
        "--- @return boolean",
        "function lib.IsOffGCD(spellID)",
        "    return spellID ~= nil and OFF_GCD[spellID] == true",
        "end",
        "",
        "--- @return number|nil cooldownMs, number|nil maxCharges, number|nil rechargeMs",
        "function lib.Get(spellID)",
        "    local v = D[spellID]",
        "    if not v then return nil end",
        '    if type(v) == "table" then return nil, v[1], v[2] end',
        "    return v",
        "end",
        "",
    ]

    out_path = Path(__file__).parent.parent / "Data" / "SpellCooldowns.lua"
    out_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    n_charge = sum(1 for v in out.values() if isinstance(v, tuple))
    print(f"{out_path}: {len(out)} spells ({n_charge} charge-based), "
          f"universe {len(universe)}, build {build}")


if __name__ == "__main__":
    main()
