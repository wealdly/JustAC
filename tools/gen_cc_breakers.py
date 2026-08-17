# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Generates Data/CCBreakers.lua from client data CSV exports.
#
# What can I press to get out of THIS crowd control? The game tags the answer:
# an effect with EffectAura 77 (mechanic immunity) names the mechanic it protects
# against in EffectMiscValue_0. Blessing of Freedom carries 7 (rooted) and 11 (snared);
# Berserker Rage carries 5 (fleeing), 14 (incapacitated), 23 (turned), 30 (sapped).
# So the whole table is discoverable rather than curated - no hand-maintained list to rot
# when Blizzard retunes an ability.
#
# Loss-of-control DATA is readable in combat (C_LossOfControl.GetActiveLossOfControlData
# carries no SecretWhen* flag; only the ByUnit variant is restricted), so the runtime side
# needs no secret-value handling at all - unlike the aura work this sits beside.
#
# Items are included: a PvP medallion is often the only stun break a spec owns. Items reach
# their spells through ItemXItemEffect -> ItemEffect -> SpellID.
#
# Inputs (same folder, wago.tools CSV exports):
#   SpellEffect.csv        - EffectAura 77 rows carry the mechanic in EffectMiscValue_0
#   SpellMechanic.csv      - mechanic id -> name, for readable comments
#   SpellName.csv          - names, for comments
#   SkillLineAbility.csv   - player-learnable spell filter
#   TraitDefinition.csv    - talent spell filter
#   ItemEffect.csv         - item effect -> spell
#   ItemXItemEffect.csv    - item -> item effect
#
# Run: python tools/gen_cc_breakers.py [csv_dir] [build]

import csv
import re
import sys
from pathlib import Path

DEFAULT_CSV_DIR = Path(__file__).resolve().parent.parent / "Documentation" / "wow_spell_csv"
OUT = Path(__file__).resolve().parent.parent / "Data" / "CCBreakers.lua"

# SPELL_AURA_MECHANIC_IMMUNITY. The one signal that means "this protects you from <mechanic>".
AURA_MECHANIC_IMMUNITY = 77

# Mechanics worth surfacing as a "break this" cue. Deliberately NOT every mechanic: immunity
# to bleeding/infected/mounted is real but is not loss of control, and offering it while the
# player is stunned would be noise. Keyed to what C_LossOfControl actually reports.
CC_MECHANICS = {
    1: "charmed", 2: "disoriented", 3: "disarmed", 5: "fleeing", 7: "rooted",
    8: "slowed", 9: "silenced", 10: "asleep", 11: "snared", 12: "stunned",
    13: "frozen", 14: "incapacitated", 17: "polymorphed", 18: "banished",
    20: "shackled", 23: "turned", 24: "horrified", 27: "dazed", 30: "sapped",
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

    # Player-relevant spell universe: class/profession skill lines + talents. Without this the
    # scan returns thousands of NPC and encounter spells that no player can press.
    universe = set()
    for row in read_csv(find("SkillLineAbility")):
        universe.add(int(row["Spell"]))
    for row in read_csv(find("TraitDefinition")):
        for col in ("SpellID", "VisibleSpellID", "OverridesSpellID"):
            v = int(row[col] or 0)
            if v > 0:
                universe.add(v)

    # Item -> spell, so an item-granted break is attributed to the ITEM the player clicks.
    effect_to_spell = {}
    for row in read_csv(find("ItemEffect")):
        sid = int(row.get("SpellID") or 0)
        if sid > 0:
            effect_to_spell[int(row["ID"])] = sid
    item_spells = {}          # spellID -> itemID
    for row in read_csv(find("ItemXItemEffect")):
        sid = effect_to_spell.get(int(row.get("ItemEffectID") or 0))
        if sid:
            item_spells.setdefault(sid, int(row.get("ItemID") or 0))

    names = {}
    for row in read_csv(find("SpellName")):
        names[int(row["ID"])] = (row.get("Name_lang") or "").strip()

    # The scan: every mechanic-immunity effect, bucketed by mechanic.
    by_mechanic = {m: {} for m in CC_MECHANICS}   # mechanic -> {spellID: itemID or 0}
    for row in read_csv(find("SpellEffect")):
        if int(row.get("EffectAura") or 0) != AURA_MECHANIC_IMMUNITY:
            continue
        mech = int(row.get("EffectMiscValue_0") or 0)
        if mech not in CC_MECHANICS:
            continue
        sid = int(row.get("SpellID") or 0)
        item = item_spells.get(sid, 0)
        # Keep a spell if the player can learn it OR an item grants it.
        if sid in universe or item:
            by_mechanic[mech][sid] = item

    lines = [
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2024-2026 wealdly",
        "-- GENERATED by tools/gen_cc_breakers.py - do not edit by hand.",
        f"-- Client data build {build}.",
        "--",
        "-- MECHANIC_BREAKERS[mechanicID] = { [spellID] = itemID or 0 }",
        "-- Sourced from EffectAura 77 (mechanic immunity), whose EffectMiscValue_0 names the",
        "-- mechanic. itemID is non-zero when an item grants the spell (press the item, not it).",
        "-- Filtered to spells a player can learn, plus anything an item grants.",
        "",
        'local lib = LibStub:NewLibrary("JustAC-CCBreakers", 1)',
        "if not lib then return end",
        "",
        "local MECHANIC_BREAKERS = {",
    ]
    total = 0
    for mech in sorted(by_mechanic):
        entries = by_mechanic[mech]
        if not entries:
            continue
        lines.append(f"    [{mech}] = {{  -- {CC_MECHANICS[mech]}")
        for sid in sorted(entries):
            item = entries[sid]
            nm = names.get(sid, "?")
            lines.append(f"        [{sid}]={item},  -- {nm}" + (f" (item {item})" if item else ""))
            total += 1
        lines.append("    },")
    lines += [
        "}",
        "",
        "--- Spells/items that free the player from `mechanic`, or nil when nothing does.",
        "--- @param mechanic number SpellMechanic id (see CC_MECHANICS in the generator)",
        "--- @return table|nil map of [spellID] = itemID (0 when the spell is cast directly)",
        "function lib.GetBreakers(mechanic)",
        "    return mechanic and MECHANIC_BREAKERS[mechanic] or nil",
        "end",
        "",
        "lib.MECHANIC_BREAKERS = MECHANIC_BREAKERS",
        "",
    ]
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT} - {total} breaker entries across "
          f"{sum(1 for m in by_mechanic if by_mechanic[m])} mechanics")


if __name__ == "__main__":
    main()
