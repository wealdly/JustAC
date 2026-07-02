# Probe: enumerate every eating/drinking aura reachable from food items in the DB2 dumps.
# Foods resolve as item -> on-use spell -> [eating aura ("Food"/"Refreshment", the visible
# player aura during the eat)] -> Well Fed buff. gen_precombat_buffs.py keeps only the two
# ends of that chain; this probe reports the middle hops, which is exactly the set
# SpellDB.EATING_AURAS must cover (a missing id silently disables the eat sweep and
# "wait" hint for that food generation).
#
#   python tools/probe_eating_auras.py
#
# Re-run after refreshing the CSVs in Documentation/wow_spell_csv/ (wago.tools/db2 ->
# SpellName, SpellEffect, Item, ItemEffect, ItemXItemEffect -> "Download as CSV").
import csv, glob, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_DIR = os.path.join(os.path.dirname(HERE), "Documentation", "wow_spell_csv")

# Same stat-aura set the generator treats as "this spell IS the persistent buff".
STAT_AURAS = {"189", "29", "137", "99", "124"}


def find_csv(prefix):
    hits = sorted(glob.glob(os.path.join(CSV_DIR, prefix + ".*.csv")))
    if not hits:
        sys.exit(f"missing {prefix}.*.csv in {CSV_DIR}")
    return hits[-1]


def load():
    cls = {}  # itemID -> subclass (class 0 consumables only)
    with open(find_csv("Item"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["ClassID"] == "0":
                cls[r["ID"]] = r["SubclassID"]
    ie = {}
    with open(find_csv("ItemEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ie[r["ID"]] = (r["SpellID"], r["TriggerType"])
    ix = defaultdict(list)
    with open(find_csv("ItemXItemEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ix[r["ItemID"]].append(r["ItemEffectID"])
    se = defaultdict(list)
    with open(find_csv("SpellEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            se[r["SpellID"]].append((r["Effect"], r["EffectAura"], r["EffectTriggerSpell"]))
    names = {}
    with open(find_csv("SpellName"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            names[r["ID"]] = r["Name_lang"]
    return cls, ie, ix, se, names


def on_use(item_id, ie, ix):
    spells = [ie[e] for e in ix.get(item_id, []) if e in ie]
    use = [sp for sp, tt in spells if tt == "0"]
    return (use or [sp for sp, _ in spells] or [None])[0]


# The eating aura's structural signature: an apply-aura effect (6) with EffectAura 84
# (OBS_MOD_HEALTH, "restores health while eating") or 85 (OBS_MOD_POWER, drink variant).
# Verified against 5004 / 396918 / 452276 - all carry aura 84 at effect index 0.
EAT_AURAS = {"84", "85"}


def closure(sid, se, depth=0, seen=None):
    """All spells reachable from sid via EffectTriggerSpell, sid included (depth <= 4).
    The visible eating aura can hang off a side branch of the Well Fed resolution path
    (use -> "Refreshment" -> effect 64 -> shared "Food"), so walk everything."""
    seen = seen if seen is not None else set()
    if not sid or sid == "0" or sid in seen:
        return seen
    seen.add(sid)
    if depth < 4:
        for _eff, _aura, trig in se.get(sid, []):
            if trig and trig != "0":
                closure(trig, se, depth + 1, seen)
    return seen


def is_eating_aura(sid, se):
    return any(eff == "6" and aura in EAT_AURAS for eff, aura, _t in se.get(sid, []))


def main():
    cls, ie, ix, se, names = load()
    # eating-aura sid -> number of food items whose trigger closure contains it
    hits = defaultdict(int)
    foods = 0
    for iid, sub in cls.items():
        if sub != "5":  # 5 = Food & Drink
            continue
        foods += 1
        for sid in closure(on_use(iid, ie, ix), se):
            if is_eating_aura(sid, se):
                hits[sid] += 1
    print(f"foods: {foods}, distinct eating auras: {len(hits)}", file=sys.stderr)
    print("-- eating auras (spellID  name  #foods), most-used first:")
    for sid, n in sorted(hits.items(), key=lambda kv: (-kv[1], int(kv[0]))):
        print(f"{sid:>8}  {names.get(sid, '?'):<30}  {n}")
    for known in ("5004", "396918", "452276"):
        tag = "OK" if known in hits else "MISSING"
        print(f"sanity {known}: {tag}", file=sys.stderr)


if __name__ == "__main__":
    main()
