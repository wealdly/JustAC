# Probe wago.tools DB2 dumps for pre-combat buff consumables (flasks/phials, augment
# runes, weapon enchants) and resolve the buff each one grants. Raw material for
# Data/PrecombatBuffs.lua. Run each major patch.
#
#   python tools/probe_buffs.py            # current expansion only
#   python tools/probe_buffs.py --all      # every expansion
#
# Chain:  ItemSparse (name/expansion) -> ItemXItemEffect (item->effect)
#         -> ItemEffect (effect->on-use spell) -> SpellName (buff name)
#         -> SpellEffect (buff -> which stat, best effort)
# The on-use spell IS (or applies) the buff aura, so its id is what the addon checks
# with C_UnitAuras.GetPlayerAuraBySpellID. Food is name-opaque (dish names, not "Food")
# so it is NOT discovered here - it is detected at runtime via the Well Fed aura.
import csv, glob, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_DIR = os.path.join(os.path.dirname(HERE), "Documentation", "wow_spell_csv")

# category -> (must-match substrings, exclude substrings). Matched against item name.
CATEGORIES = {
    "flask":         (("Flask", "Phial"), ("Cauldron", "Recycle", "Prepare", "Recipe")),
    "augment_rune":  (("Augment Rune",), ()),
    "weapon_enchant":(("Oil", "Whetstone", "Weightstone", "Sharpening Stone",
                       "Balanced Weightstone", "Wax", "Weapon Rune", "Howling Rune",
                       "Buzzing Rune", "Primal Weightstone"), ("Recipe", "Pattern")),
}
CRAFTING_DOC = ("Recipe:", "Pattern:", "Plan:", "Formula:", "Technique:", "Design:")

# Combat-rating bits (EffectMiscValue bitmask on a MOD_RATING aura) -> secondary stat.
RATING_BITS = {"crit": (9, 10, 11), "haste": (17, 18, 19), "mastery": (26,),
               "versatility": (29,)}
PRIMARY_STAT = {0: "strength", 1: "agility", 2: "stamina", 3: "intellect"}
AURA_MOD_STAT, AURA_MOD_RATING = "29", "189"


def find_csv(prefix):
    hits = sorted(glob.glob(os.path.join(CSV_DIR, prefix + ".*.csv")))
    if not hits:
        sys.exit(f"missing {prefix}.*.csv in {CSV_DIR}")
    return hits[-1]


def load():
    ie = {}  # effect id -> (spellID, triggerType)
    with open(find_csv("ItemEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ie[r["ID"]] = (r["SpellID"], r["TriggerType"])
    ix = defaultdict(list)  # itemID -> [effect id]
    with open(find_csv("ItemXItemEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ix[r["ItemID"]].append(r["ItemEffectID"])
    sn = {}  # spellID -> name
    with open(find_csv("SpellName"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            sn[r["ID"]] = r["Name_lang"]
    return ie, ix, sn


def stat_of(spellids):
    # Best-effort: scan SpellEffect once for the given buff spells, decode the stat.
    want = set(spellids)
    out = {}
    with open(find_csv("SpellEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            sid = r["SpellID"]
            if sid not in want:
                continue
            aura, misc = r["EffectAura"], r["EffectMiscValue_0"]
            if aura == AURA_MOD_STAT:
                out.setdefault(sid, set()).add(PRIMARY_STAT.get(int(misc or 0), "stat"))
            elif aura == AURA_MOD_RATING:
                try:
                    mask = int(misc or 0)
                except ValueError:
                    continue
                for stat, bits in RATING_BITS.items():
                    if any(mask & (1 << b) for b in bits):
                        out.setdefault(sid, set()).add(stat)
    return out


def on_use_spell(item_id, ie, ix):
    spells = [ie[e] for e in ix.get(item_id, []) if e in ie]
    use = [sp for sp, tt in spells if tt == "0"]  # trigger 0 = on use
    return (use or [sp for sp, _ in spells] or [None])[0]


def main():
    all_exp = "--all" in sys.argv
    ie, ix, sn = load()

    rows = []  # (cat, exp, itemID, name, quality, ilvl, buffSpell, buffName)
    max_exp = 0
    with open(find_csv("ItemSparse"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            name = r["Display_lang"]
            if any(name.startswith(p) for p in CRAFTING_DOC):
                continue
            cat = None
            for c, (inc, exc) in CATEGORIES.items():
                if any(s in name for s in inc) and not any(s in name for s in exc):
                    cat = c
                    break
            if not cat:
                continue
            buff = on_use_spell(r["ID"], ie, ix)
            if not buff:
                continue
            exp = int(r["ExpansionID"] or 0)
            max_exp = max(max_exp, exp)
            rows.append((cat, exp, r["ID"], name, r["OverallQualityID"],
                         r["ItemLevel"], buff, sn.get(buff, "?")))

    if not all_exp:
        rows = [x for x in rows if x[1] == max_exp]

    stats = stat_of([x[6] for x in rows])
    by_cat = defaultdict(list)
    for x in rows:
        by_cat[x[0]].append(x)

    scope = "all expansions" if all_exp else f"current expansion (ExpansionID {max_exp})"
    print(f"Pre-combat buff consumables, {scope}:\n")
    for cat in CATEGORIES:
        items = sorted(by_cat.get(cat, []), key=lambda x: (-int(x[5] or 0), x[3]))
        if not items:
            continue
        buffset = sorted({x[6] for x in items}, key=int)
        print(f"== {cat}  ({len(items)} items, {len(buffset)} distinct buffs) ==")
        for _, _, iid, nm, q, ilvl, buff, bname in items:
            st = ",".join(sorted(stats.get(buff, []))) or "?"
            print(f"  item {iid:>7}  buff {buff:>8}  [{st:<22}] {nm}  (q{q}, ilvl{ilvl})")
        print(f"  buff spellIDs: {{ {', '.join(buffset)} }}\n")


if __name__ == "__main__":
    main()
