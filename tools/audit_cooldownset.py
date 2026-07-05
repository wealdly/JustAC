# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Audit: diffs the client's own per-spec cooldown-tracker lists (CooldownSet /
# CooldownSetSpell, the data behind the built-in cooldown viewer) against the
# curated Data/SpellCategories.lua buckets. Report-only - human judgment decides
# what enters the curated lists. Re-run per patch.
#
# Categories in CooldownSetSpell: 0=Essential 1=Utility 2=TrackedBuff 3=TrackedBar.
# Only Essential/Utility entries are reported: they are castable cooldowns (the
# analogue of our buckets). TrackedBuff/TrackedBar are aura displays - hundreds
# of talent procs per class, wrong review queue for SpellCategories (pass
# --buffs to include them anyway). Essential mixes offensive and defensive
# cooldowns, so "missing from ours" is a review queue, not automatically a bug.
#
# Run: python tools/audit_cooldownset.py [csv_dir] [--buffs]

import csv
import re
import sys
from pathlib import Path

DEFAULT_CSV_DIR = Path(__file__).resolve().parent.parent / "Documentation" / "wow_spell_csv"

SPEC_CLASS = {
    62: "Mage", 63: "Mage", 64: "Mage",
    65: "Paladin", 66: "Paladin", 70: "Paladin",
    71: "Warrior", 72: "Warrior", 73: "Warrior",
    102: "Druid", 103: "Druid", 104: "Druid", 105: "Druid",
    250: "DeathKnight", 251: "DeathKnight", 252: "DeathKnight",
    253: "Hunter", 254: "Hunter", 255: "Hunter",
    256: "Priest", 257: "Priest", 258: "Priest",
    259: "Rogue", 260: "Rogue", 261: "Rogue",
    262: "Shaman", 263: "Shaman", 264: "Shaman",
    265: "Warlock", 266: "Warlock", 267: "Warlock",
    268: "Monk", 269: "Monk", 270: "Monk",
    577: "DemonHunter", 581: "DemonHunter",
    1467: "Evoker", 1468: "Evoker", 1473: "Evoker",
}
CATEGORY = {0: "Essential", 1: "Utility", 2: "TrackedBuff", 3: "TrackedBar"}


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        yield from csv.DictReader(f)


def main():
    args = [a for a in sys.argv[1:] if a != "--buffs"]
    include_buffs = "--buffs" in sys.argv
    csv_dir = Path(args[0]) if args else DEFAULT_CSV_DIR

    def find(table):
        hits = sorted(csv_dir.glob(f"{table}.*.csv"))
        if not hits:
            sys.exit(f"missing {table} csv in {csv_dir}")
        return hits[-1]

    names = {int(r["ID"]): r["Name_lang"] for r in read_csv(find("SpellName"))}

    set_class = {}
    for r in read_csv(find("CooldownSet")):
        spec = int(r["ChrSpecialization"] or 0)
        set_class[int(r["ID"])] = SPEC_CLASS.get(spec, f"spec{spec}" if spec else "Global")

    # class -> {spellID -> set of Blizzard categories}
    blizz = {}
    for r in read_csv(find("CooldownSetSpell")):
        cls = set_class.get(int(r["CooldownSetID"]))
        if not cls:
            continue
        # 12.1 data has categories beyond the documented 0-3 - show the raw int
        cat_id = int(r["Category"] or 0)
        cat = CATEGORY.get(cat_id, f"cat{cat_id}")
        blizz.setdefault(cls, {}).setdefault(int(r["SpellID"]), set()).add(cat)

    # Curated buckets straight from Data/SpellCategories.lua
    src = (Path(__file__).resolve().parent.parent / "Data" / "SpellCategories.lua").read_text(encoding="utf-8")
    ours = {}  # spellID -> set of bucket names
    for bucket, var in (("defensive", "DEFENSIVE_SPELLS"), ("healing", "HEALING_SPELLS"),
                        ("cc", "CROWD_CONTROL_SPELLS"), ("utility", "UTILITY_SPELLS")):
        block = re.search(var + r" = \{(.*?)\n\}", src, re.S)
        if not block:
            sys.exit(f"could not find {var} in SpellCategories.lua")
        body = re.sub(r"--[^\n]*", "", block.group(1))
        for m in re.findall(r"\[(\d+)\]", body):
            ours.setdefault(int(m), set()).add(bucket)

    total_missing = 0
    for cls in sorted(blizz):
        spells = blizz[cls]
        if not include_buffs:
            spells = {sid: cats for sid, cats in spells.items()
                      if cats & {"Essential", "Utility"}}
        missing = {sid: cats for sid, cats in spells.items() if sid not in ours}
        covered = len(spells) - len(missing)
        print(f"\n== {cls}: {len(spells)} tracked by client, {covered} in curated buckets, "
              f"{len(missing)} not curated")
        for sid in sorted(missing, key=lambda s: (sorted(missing[s])[0], names.get(s, ""))):
            cats = "/".join(sorted(missing[sid]))
            print(f"  {sid:>7}  {names.get(sid, '?'):<32} [{cats}]")
        total_missing += len(missing)

    print(f"\nTotal not-curated across classes: {total_missing}")
    print("Reminder: Essential includes offensive cooldowns we intentionally do not "
          "curate as defensive/healing/cc/utility - review, don't bulk-add.")


if __name__ == "__main__":
    main()
