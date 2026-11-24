#!/usr/bin/env python3
"""WoW Forever lists are closed: the automatic queue offers only what the installed tree names
(SpellQueue._IsLeftOut). A class ability that deals damage and that no tree of its class names is
therefore never offered. This check lists those per class and fails when the set changes, so a
data refresh that brings a new damaging ability (or a list edit that drops one) is a decision,
not a silent loss: add it to a tree's list in tools/gen_forever_rotations.py, or record it below
as deliberately left to the player.

Run: python tools/test_closed_lists.py  (needs the Forever client CSVs, as the generator does)
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_forever_rotations as gen  # noqa: E402

# Damaging class abilities no tree names, per class, each left to the player for the reason
# given (2026-11-22 decisions, also in the class guides). A new one is a decision: add it to a
# list, or record it here with its reason.
KNOWN_UNNAMED = {
    # Pet abilities, cast by the pet, not a player press: Bite, Claw, Lightning Breath, Scorpid
    # Poison, Lacerate, Demoralizing Screech, Thunderstomp, Lava Breath and the newer families.
    # Explosive Trap (34): placed at the hunter's feet, so where the fight happens is the
    # player's. Black Arrow (50): beyond the guides' levels; revisit when one covers it.
    "HUNTER": {2975, 3674, 13812, 17254, 24118, 24424, 24584, 24845, 26094, 444680,
               1264727, 1264745, 1264937, 1265043, 1265059, 1265831, 1265887},
    # Felfire (60): no guide or sim names it and its source is unclear; revisit with one.
    # Frostfire Bolt (40): the client gives it about half Fireball's damage, and Fireball fills
    # faster at 40 to 60 (2026-11-24); its use against a fire-resistant enemy is the player's.
    "MAGE": {24530, 401502},
    # Seal of Command (Retribution, 20): Command or Righteousness follows weapon speed (guides);
    # the seal entries already wait while any seal is up, so a chosen Command is kept.
    "PALADIN": {20375},
    # Chastise (Dwarf, 20): one Smite of damage per 2 min, humanoids only; the root is crowd control.
    "PRIEST": {1277331},
    # Frost Shock (20): shares the shock cooldown with Earth Shock, which the lists use; it costs
    # more mana and its slow is for kiting.
    "SHAMAN": {8056},
    # Drain Life: guides cast it for health. Drain Soul: for soul shards. Soul Fire (48): guides
    # use it only as Decimation's execute, which no list models yet.
    "WARLOCK": {689, 1120, 6353},
    # Intercept: the gap closer feature's (its Forever class list).
    "WARRIOR": {20252},
}

WEAPON_ATTACKS = {6603}   # Attack; the ranged weapon attacks come from SpellCategories below


def table(source, pattern):
    m = re.search(pattern, source, re.S)
    assert m, pattern
    return m.group(1)


def main():
    rot = open(os.path.join(ROOT, "Data", "Forever", "Rotations.lua"), encoding="utf-8").read()
    defaults = open(os.path.join(ROOT, "Data", "Forever", "Defaults.lua"), encoding="utf-8").read()
    categories = open(os.path.join(ROOT, "Data", "SpellCategories.lua"), encoding="utf-8").read()

    pools = {}
    block = table(rot, r'\n\}, \{\n((?:  \["\w+_F"\] = \{[\d,]*\},\n)+)\}, \{')
    for cls, ids in re.findall(r'  \["(\w+)_F"\] = \{([\d,]*)\}', block):
        pools[cls] = [int(x) for x in ids.split(",") if x]

    named = {}
    body = rot[rot.index("RotationImport.RegisterForever({"):]
    body = body[:body.index("\n}, {")]
    cls = None
    for line in body.splitlines():
        m = re.match(r'  \["(\w+)_F"\] = \{', line)
        if m:
            cls = m.group(1)
            named.setdefault(cls, set())
            continue
        if cls:
            named[cls].update(int(x) for x in re.findall(r"\{id=(\d+),", line))

    roles = {int(k): v for k, v in re.findall(r'\[(\d+)\] = "(\w+)"',
                                              table(defaults, r"local ABILITY_ROLES = \{(.*?)\n\}"))}
    ranged = {int(x) for x in re.findall(r"\[(\d+)\] = true",
                                         table(categories, r"foreverRanged = \{(.*?)\}"))}

    unnamed = {}
    for cls, pool in sorted(pools.items()):
        for sid in pool:
            if sid in named.get(cls, ()) or sid in WEAPON_ATTACKS or sid in ranged:
                continue
            if roles.get(sid, "mixed") != "mixed":
                continue   # reserved for its own queue (defensive, utility...): never a damage entry
            if gen.deals_damage(str(sid)):
                unnamed.setdefault(cls, set()).add(sid)

    bad = []
    for cls in sorted(set(unnamed) | set(KNOWN_UNNAMED)):
        new = unnamed.get(cls, set()) - KNOWN_UNNAMED.get(cls, set())
        gone = KNOWN_UNNAMED.get(cls, set()) - unnamed.get(cls, set())
        if new:
            bad.append("%s: damaging abilities no tree names (never offered): %s" % (cls, sorted(new)))
        if gone:
            bad.append("%s: now named or gone, drop from KNOWN_UNNAMED: %s" % (cls, sorted(gone)))
    for why in bad:
        print("  FAIL", why)
    print("closed lists: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
