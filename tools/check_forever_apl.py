#!/usr/bin/env python3
# tools/check_forever_apl.py
#
# What a Forever class can actually LEARN, as rank chains, read from the Forever client
# data (Documentation/wow_spell_csv_forever). An id in a priority list must be one of these,
# not merely a name present in SpellName: tools/gen_forever_rotations.py builds every list
# against this and exits 1 on a hand-pin ability no class can learn.
import csv, glob, os, sys
from functools import lru_cache

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_DIR = os.path.join(ROOT, "Documentation", "wow_spell_csv_forever")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from simc_bridge import slug, CLASS_ID  # noqa: E402

# SkillLineAbility.ClassMask bit = 1 << (ChrClasses id - 1).
CLASS_MASK = {k.lower(): 1 << (v - 1) for k, v in CLASS_ID.items()}
SKIP = {"auto_attack", "auto_shot", "use_items", "potion", "call_action_list", "run_action_list"}
# AcquireMethod 3 rows are either a talent grant (the spell is a TraitDefinition's SpellID,
# e.g. Shifting Power) or something no player casts (Execute's damage component 20647, the
# removed Tiger's Fury). Only the talent-granted ones are learnable.
ACQUIRE_GRANTED = "3"
# Racials by what they do in a fight, by slug. Sorted by hand from the Forever spell
# descriptions: the data cannot tell a damage cooldown from a travel or tracking one.
# Racials not listed (Find Treasure, Perception, Shadowmeld, Cultivation, Cannibalize,
# Rapid Regeneration, the Skyborne travel racials) never reach a combat list.
RACIAL_ROLES = {
    "offensive": ["berserking", "blood_fury", "elunes_light", "eureka"],
    "defensive": ["stoneform", "shatter_curse", "will_of_the_forsaken", "will_to_survive",
                  "escape_artist"],
    "cc": ["war_stomp"],
}


@lru_cache(maxsize=None)
def rows(table):
    path = glob.glob(os.path.join(CSV_DIR, table + ".*.csv"))
    if not path:
        sys.exit(f"missing {table} in {CSV_DIR} - pull the Forever CSVs first")
    with open(path[0], encoding="utf-8") as f:
        return tuple(csv.DictReader(f))


@lru_cache(maxsize=None)
def racials():
    """slug -> sorted spell ids for every racial ability (skill lines named "... Racial";
    Eureka! has one id per class). Which race has which is the game's business at runtime."""
    lines = {r["ID"] for r in rows("SkillLine") if "Racial" in (r["DisplayName_lang"] or "")}
    name = {r["ID"]: r["Name_lang"] for r in rows("SpellName")}
    out = {}
    for r in rows("SkillLineAbility"):
        if r["SkillLine"] in lines and r["Spell"].isdigit():
            out.setdefault(slug(name.get(r["Spell"], "")), set()).add(int(r["Spell"]))
    return {k: sorted(v) for k, v in out.items()}


def racial_ids(role):
    """Every id of the racials RACIAL_ROLES gives this role; exits on a slug the data lacks."""
    known = racials()
    missing = [s for s in RACIAL_ROLES[role] if s not in known]
    if missing:
        sys.exit("RACIAL_ROLES names racials the data lacks: " + ", ".join(missing))
    return sorted(i for s in RACIAL_ROLES[role] for i in known[s])


def _level(levels, sid):
    v = levels.get(sid, "")
    return int(v) if v.isdigit() else 999


def class_chains(mask):
    """Every learnable ability of one class as rank chains.
    Returns (by_slug, by_id): slug -> [(spellID, level)] in learn order (rank 1 first),
    and spellID -> its chain, for every rank. A row counts when it sits in one of the
    class's skill lines (talent rows carry ClassMask 0 inside them) and, for
    AcquireMethod 3, only when a talent grants it."""
    name = {r["ID"]: r["Name_lang"] for r in rows("SpellName")}
    level = {r["SpellID"]: r["BaseLevel"] for r in rows("SpellLevels")}
    talent = {r["SpellID"] for r in rows("TraitDefinition")}
    sla = [r for r in rows("SkillLineAbility") if r["Spell"].isdigit()]
    lines = {r["SkillLine"] for r in sla if int(r["ClassMask"] or 0) & mask}
    by_slug = {}
    for r in sla:
        cm = int(r["ClassMask"] or 0)
        if (cm & mask or (cm == 0 and r["SkillLine"] in lines)) \
           and (r["AcquireMethod"] != ACQUIRE_GRANTED or r["Spell"] in talent):
            # A spell with no name is no ability anyone presses - and grouped by name, every
            # nameless one of a class collapsed into one bogus 100+ "rank" chain.
            s = slug(name.get(r["Spell"], ""))
            if s:
                by_slug.setdefault(s, set()).add(r["Spell"])
    chains, by_id = {}, {}
    for s, ids in by_slug.items():
        # Ranks ordered by learn level: rank 1 is the one learned first. A talent's own
        # head (Holy Shock 1311606 at 30) sits with the trainer ranks of the same name.
        chain = [(sid, level.get(sid, "?")) for sid in sorted(ids, key=lambda i: (_level(level, i), int(i)))]
        chains[s] = chain
        for sid, _ in chain:
            by_id[int(sid)] = chain
    return chains, by_id
