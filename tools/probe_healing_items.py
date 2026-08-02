# Probe wago.tools DB2 dumps for health-restoring consumables and diff them against
# Data/HealingItems.lua. Run each major patch to find pots we are missing.
#
#   python tools/probe_healing_items.py
#
# Source CSVs live in Documentation/wow_spell_csv/ (drop fresh ItemSparse.*.csv there
# from https://wago.tools/db2/ItemSparse - "Export as CSV"). Name-based: it finds the
# standard "* Healing Potion" / "Healthstone" naming. Oddly-named restoration items
# (e.g. health+mana pots with no "healing" in the name) won't surface here - those stay
# hand-curated in HealingItems.lua. ponytail: name match, not effect graph; we don't
# have ItemXItemEffect to walk on-use heal effects, and the standard names cover ~all.
import csv, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CSV_DIR = os.path.join(ROOT, "Documentation", "wow_spell_csv")
LIST_LUA = os.path.join(ROOT, "Data", "HealingItems.lua")

# Names that mark a health-restoring consumable.
INCLUDE = re.compile(r"\b(Healing Potion|Health Potion|Healthstone|Healing Tonic|"
                     r"Rejuvenation Potion|Healing Draught)\b", re.I)
# Crafting docs (which only mention the item) and items that can't serve as a real
# emergency heal: test/QA placeholders, Brawler's-Guild-only pots, joke items.
EXCLUDE = re.compile(r"^(Recipe|Pattern|Plan|Formula|Schematic|Design|Manual|Technique"
                     r"|Enchant|Bag of|Craftsman's Writ):"
                     r"|\bQA\b|\[DNT\]|\bDNT\b|Brawler's|Impotent|Experimental Healing"
                     r"|Ultra Healing|Gladiator's", re.I)

EXPANSION = {  # ItemSparse.ExpansionID -> label, newest first in output
    "11": "The War Within", "10": "Dragonflight", "9": "Shadowlands",
    "8": "Battle for Azeroth", "7": "Legion", "6": "Warlords of Draenor",
    "5": "Mists of Pandaria", "4": "Cataclysm", "3": "Wrath", "2": "Burning Crusade",
    "1": "Classic", "0": "Classic",
}


def find_csv(prefix):
    hits = sorted(glob.glob(os.path.join(CSV_DIR, prefix + ".*.csv")))
    if not hits:
        sys.exit(f"missing {prefix}.*.csv in {CSV_DIR}")
    return hits[-1]


def known_ids():
    ids = set()
    with open(LIST_LUA, encoding="utf-8") as fh:
        for line in fh:
            code = line.split("--", 1)[0]  # strip trailing comment
            ids.update(int(n) for n in re.findall(r"\b\d{2,7}\b", code))
    return ids


def main():
    known = known_ids()
    found = {}  # id -> row
    with open(find_csv("ItemSparse"), encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            name = row["Display_lang"]
            if (INCLUDE.search(name) and not EXCLUDE.search(name)
                    and (row["OverallQualityID"] or "0") != "0"):  # drop q0 joke/test pots
                found[int(row["ID"])] = row

    missing = sorted((i for i in found if i not in known),
                     key=lambda i: (-int(found[i]["ExpansionID"] or 0),
                                    -int(found[i]["ItemLevel"] or 0)))
    print(f"{len(found)} health-restoring items matched by name; "
          f"{len(found) - len(missing)} already in HealingItems.lua.\n")
    if not missing:
        print("No new candidates. List is current.")
        return
    print(f"{len(missing)} candidate(s) NOT in the list "
          "(verify on wago.tools, then add - heirlooms are quality 7):\n")
    cur = None
    for i in missing:
        r = found[i]
        exp = EXPANSION.get(r["ExpansionID"], "exp " + r["ExpansionID"])
        if exp != cur:
            print(f"  -- {exp}")
            cur = exp
        print(f"    {i},  -- {r['Display_lang']} "
              f"(q{r['OverallQualityID']}, reqLvl {r['RequiredLevel']}, ilvl {r['ItemLevel']})")


if __name__ == "__main__":
    main()
