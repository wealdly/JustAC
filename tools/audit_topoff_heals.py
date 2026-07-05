# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Audit: derives candidate out-of-combat top-off heals from client data and diffs
# them against the curated SpellDB.CLASS_TOPOFF_HEALS list. Report-only - human
# judgment decides what enters the curated list. Re-run per patch.
#
# Candidate signal: a class spell with a direct-heal effect on a friendly/self
# target, no/short cooldown (<= 30s from SpellCooldowns data), and a cost in a
# resource that regenerates out of combat (mana/energy/focus or free). Excludes
# hostile-target heals (Death Strike style) and long-cooldown combat heals.
#
# Run: python tools/audit_topoff_heals.py [csv_dir]

import csv
import re
import sys
from pathlib import Path

DEFAULT_CSV_DIR = Path(__file__).resolve().parent.parent / "Documentation" / "wow_spell_csv"
MAX_CD_MS = 30000
EFFECT_HEAL = 10
FRIENDLY_TARGETS = {1, 21}          # caster, friendly target
REGEN_POWER_TYPES = {0, 2, 3}       # mana, focus, energy (regen out of combat)


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        yield from csv.DictReader(f)


def main():
    csv_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV_DIR

    def find(table):
        hits = sorted(csv_dir.glob(f"{table}.*.csv"))
        if not hits:
            sys.exit(f"missing {table} csv in {csv_dir}")
        return hits[-1]

    # Class membership via the skill-line hierarchy (CategoryID 7 = class lines;
    # spec lines carry ParentSkillLineID to their class line). Baseline class
    # spells have ClassMask=0 in SkillLineAbility, so the mask alone under-recalls.
    line_name, line_parent, class_lines = {}, {}, {}
    for row in read_csv(find("SkillLine")):
        lid = int(row["ID"])
        line_name[lid] = (row.get("DisplayName_lang") or "").upper().replace(" ", "")
        line_parent[lid] = int(row["ParentSkillLineID"] or 0)
        if int(row["CategoryID"] or 0) == 7:
            class_lines[lid] = True
    CLASS_NAMES = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
                   "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"}
    def line_class(lid):
        for _ in range(3):  # walk to the root class line
            if lid == 0 or lid not in line_name:
                return None
            if line_name[lid] in CLASS_NAMES:
                return line_name[lid]
            lid = line_parent.get(lid, 0)
        return None
    spell_class = {}
    for row in read_csv(find("SkillLineAbility")):
        cls = class_lines.get(int(row["SkillLine"] or 0)) and line_class(int(row["SkillLine"]))
        if cls:
            spell_class[int(row["Spell"])] = cls

    # Direct-heal effects on friendly/self targets; disqualify hostile-target rows
    heals, hostile = set(), set()
    for row in read_csv(find("SpellEffect")):
        if int(row["DifficultyID"] or 0) != 0:
            continue
        sid = int(row["SpellID"])
        if sid not in spell_class:
            continue
        tgt = int(row["ImplicitTarget_0"] or 0)
        eff = int(row["Effect"] or 0)
        aura = int(row["EffectAura"] or 0)
        is_heal = eff == EFFECT_HEAL or (eff == 6 and aura == 8)  # direct or periodic heal
        if is_heal:
            if tgt in FRIENDLY_TARGETS:
                heals.add(sid)
            else:
                hostile.add(sid)
        elif tgt == 6:  # TARGET_UNIT_TARGET_ENEMY on any effect = combat-coupled
            hostile.add(sid)
    heals -= hostile

    # Cooldown gate from the same data the runtime uses
    long_cd = set()
    for row in read_csv(find("SpellCooldowns")):
        if int(row["DifficultyID"] or 0) == 0:
            eff = max(int(row["RecoveryTime"] or 0), int(row["CategoryRecoveryTime"] or 0))
            if eff > MAX_CD_MS:
                long_cd.add(int(row["SpellID"]))
    heals -= long_cd

    # Resource gate: only free casts or OOC-regenerating resources
    cost_power = {}
    for row in read_csv(find("SpellPower")):
        sid = int(row["SpellID"])
        if sid in heals:
            cost_power.setdefault(sid, set()).add(int(row["PowerType"] or 0))
    heals = {s for s in heals
             if not cost_power.get(s) or cost_power[s] <= REGEN_POWER_TYPES}

    names = {}
    for row in read_csv(find("SpellName")):
        try:
            sid = int(row["ID"])
        except (KeyError, ValueError):
            continue
        if sid in heals:
            names[sid] = row.get("Name_lang", "?")

    # Curated list straight from SpellDB.lua
    curated = set()
    spelldb = (Path(__file__).resolve().parent.parent / "SpellDB.lua").read_text(encoding="utf-8")
    block = re.search(r"CLASS_TOPOFF_HEALS = \{(.*?)\n\}", spelldb, re.S)
    if block:
        # strip line comments so IDs in prose ("30s recharge") aren't captured
        body = re.sub(r"--[^\n]*", "", block.group(1))
        curated = {int(m) for m in re.findall(r"(\d+)", body)}

    by_class = {}
    for sid in heals:
        by_class.setdefault(spell_class[sid], []).append(sid)
    print(f"Candidates: {len(heals)}  (curated: {len(curated)})")
    for cls in sorted(by_class):
        print(f"\n{cls}:")
        for sid in sorted(by_class[cls]):
            tag = "CURATED" if sid in curated else "candidate"
            print(f"  [{tag}] {sid} {names.get(sid, '?')}")
    missing_from_data = curated - heals
    if missing_from_data:
        print(f"\nCurated but NOT matching the data signal (verify still correct): {sorted(missing_from_data)}")


if __name__ == "__main__":
    main()
