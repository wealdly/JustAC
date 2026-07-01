# Generate Data/PrecombatBuffs.lua from wago.tools DB2 dumps. Discovers buff consumables
# by item class/subclass (not name), resolves the persistent buff aura each one grants
# (following trigger chains for food), decodes the stat, and emits a source-aware table.
#
#   python tools/gen_precombat_buffs.py            # all expansions
#   python tools/gen_precombat_buffs.py > out.lua  # inspect without writing
#
# Re-run each major patch after refreshing the CSVs in Documentation/wow_spell_csv/.
# The generator owns the bulk (bag consumables, source="item"); toys (source="toy") and
# class self-buffs (source="spell") are hand-added in the data file below the marker.
import csv, glob, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CSV_DIR = os.path.join(ROOT, "Documentation", "wow_spell_csv")
OUT = os.path.join(ROOT, "Data", "PrecombatBuffs.lua")

# item class/subclass -> our category. Subclass 8 (Item Enhancement) holds BOTH augment
# runes and weapon enchants, split by name below.
SUBCLASS = {"3": "flask", "5": "food", "8": "enh"}

# Aura types that mean "this spell grants a stat" (so the spell IS the buff we detect).
STAT_AURAS = {"189", "29", "137", "99", "124"}  # MOD_RATING/STAT/TOTAL_STAT%/AP/RANGED_AP
# Combat-rating bits (EffectMiscValue on a MOD_RATING aura) -> secondary stat. Verified
# against this build's flask buffs: crit 8-10, haste 17-19, mastery 25, versatility 28-30.
RATING_BITS = {"crit": (8, 9, 10), "haste": (17, 18, 19), "mastery": (25,),
               "versatility": (28, 29, 30)}
PRIMARY_STAT = {"0": "strength", "1": "agility", "2": "stamina", "3": "intellect"}

EXPANSION = {11: "Midnight / current", 10: "Dragonflight / TWW", 9: "Shadowlands",
             8: "Battle for Azeroth", 7: "Legion", 6: "Warlords of Draenor",
             5: "Mists of Pandaria", 4: "Cataclysm", 3: "Wrath", 2: "Burning Crusade",
             1: "Classic", 0: "Classic"}


def find_csv(prefix):
    hits = sorted(glob.glob(os.path.join(CSV_DIR, prefix + ".*.csv")))
    if not hits:
        sys.exit(f"missing {prefix}.*.csv in {CSV_DIR}")
    return hits[-1]


def load():
    cls = {}  # itemID -> subclass (class 0 only)
    with open(find_csv("Item"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["ClassID"] == "0":
                cls[r["ID"]] = r["SubclassID"]
    ie = {}  # effect id -> (spellID, triggerType)
    with open(find_csv("ItemEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ie[r["ID"]] = (r["SpellID"], r["TriggerType"])
    ix = defaultdict(list)  # itemID -> [effect id]
    with open(find_csv("ItemXItemEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ix[r["ItemID"]].append(r["ItemEffectID"])
    se = defaultdict(list)  # spellID -> [(effect, aura, trigger, misc0)]
    with open(find_csv("SpellEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            se[r["SpellID"]].append((r["Effect"], r["EffectAura"],
                                     r["EffectTriggerSpell"], r["EffectMiscValue_0"]))
    return cls, ie, ix, se


def stat_of(aura, misc):
    if aura == "29":
        return PRIMARY_STAT.get(misc, "primary" if misc in ("-1", "-2") else "stat")
    if aura == "189":
        try:
            mask = int(misc or 0)
        except ValueError:
            return None
        hits = [s for s, bits in RATING_BITS.items() if any(mask & (1 << b) for b in bits)]
        return "+".join(sorted(hits)) if hits else None
    return None


def resolve_buff(sid, se, depth=0, seen=None):
    """Return (buffSpellID, stat) for the persistent aura a use-spell grants, or None.
    Direct stat aura -> that spell is the buff; otherwise follow one trigger level."""
    seen = seen or set()
    if sid in seen or sid == "0":
        return None
    seen.add(sid)
    effects = se.get(sid, [])
    for eff, aura, _trig, misc in effects:
        if eff == "6" and aura in STAT_AURAS:
            return sid, stat_of(aura, misc)
    if depth < 2:
        for _eff, _aura, trig, _misc in effects:
            if trig and trig != "0":
                res = resolve_buff(trig, se, depth + 1, seen)
                if res:
                    return res
    return None


def on_use(item_id, ie, ix):
    spells = [ie[e] for e in ix.get(item_id, []) if e in ie]
    use = [sp for sp, tt in spells if tt == "0"]
    return (use or [sp for sp, _ in spells] or [None])[0]


def categorize(name, sub):
    cat = SUBCLASS.get(sub)
    if cat == "enh":
        if "Augment Rune" in name:
            return "augmentRune"
        if any(k in name for k in ("Oil", "Stone", "Whetstone", "Weightstone", "Wax")):
            return "weaponEnchant"
        return None
    return cat  # flask / food


def main():
    cls, ie, ix, se = load()
    CRAFTING = ("Recipe:", "Pattern:", "Plan:", "Formula:", "Technique:", "Design:", "[")
    buckets = defaultdict(list)  # cat -> [(exp, ilvl, id, name, buff, stat)]

    with open(find_csv("ItemSparse"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            iid, name = r["ID"], r["Display_lang"]
            sub = cls.get(iid)
            if not sub or any(name.startswith(p) for p in CRAFTING):
                continue  # "[" drops [PH]/[DNT] placeholder items
            cat = categorize(name, sub)
            if not cat:
                continue
            use = on_use(iid, ie, ix)
            buff, stat = (resolve_buff(use, se) or (None, None))
            # flask/food/rune must grant a detectable stat aura; weapon enchants are
            # detected via GetWeaponEnchantInfo so they keep their apply-spell instead -
            # but skip any with no resolvable spell at all (avoids buff = nil entries).
            if cat == "weaponEnchant":
                buff = buff or use
                if not buff:
                    continue
            elif not buff:
                continue
            buckets[cat].append((int(r["ExpansionID"] or 0), int(r["ItemLevel"] or 0),
                                 iid, name, buff, stat))
    # Weapon enchants are kept across all expansions: the addon filters them at suggest
    # time by the equipped weapon's expansion (an older oil/stone won't apply to a newer
    # weapon), which also keeps leveling-content coverage that a hard floor would drop.

    lines = [HEADER]
    for cat in ("flask", "food", "augmentRune", "weaponEnchant"):
        items = sorted(buckets.get(cat, []), key=lambda x: (-x[0], -x[1], x[3]))
        lines.append(f"    {cat} = {{")
        cur = None
        for exp, ilvl, iid, name, buff, stat in items:
            if exp != cur:
                lines.append(f"        -- {EXPANSION.get(exp, 'exp ' + str(exp))}")
                cur = exp
            st = f', stat = "{stat}"' if stat else ""
            lines.append(f"        {{ id = {iid}, buff = {buff}{st} }},"
                         f"  -- {name}")
        lines.append("    },")
        print(f"  {cat}: {len(items)} items", file=sys.stderr)
    lines.append(FOOTER)

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"wrote {OUT}", file=sys.stderr)


HEADER = """\
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Pre-combat buff consumables (flasks, food, augment runes, weapon enchants).
--
-- GENERATED by tools/gen_precombat_buffs.py from wago.tools DB2 dumps - do not hand-edit
-- the generated categories. Re-run each major patch (see the script header). Items are
-- discovered by item class/subclass and their persistent buff aura is resolved from the
-- effect chain; `buff` is the aura spellID the addon checks for, `stat` is what it grants.
--
-- Source-aware: generated entries are bag items (source defaults to "item"). Toys
-- (source = "toy") and class self-buffs (source = "spell") are hand-added below the
-- HAND-CURATED marker and are preserved across regeneration only if you keep them there.
local SpellDB = LibStub("JustAC-SpellDB", true)
if not SpellDB or not SpellDB.RegisterPrecombatBuffs then return end

SpellDB.RegisterPrecombatBuffs({"""

FOOTER = """\
})

-- ──────────────────────────── HAND-CURATED (not generated) ────────────────────────────
-- Toys and class self-buffs flow through the same detect+overlay pipeline via `source`.
-- Add them with SpellDB.RegisterPrecombatBuffsExtra so a regen never clobbers them.
if SpellDB.RegisterPrecombatBuffsExtra then
    SpellDB.RegisterPrecombatBuffsExtra({
        -- XP / leveling toys (source = "toy": owned via PlayerHasToy, used via /usetoy)
        -- { category = "xp", id = <toyItemID>, buff = <auraSpellID>, source = "toy" },

        -- Class self-buffs (source = "spell": known via IsSpellKnown, cast via type=spell)
        -- { category = "classBuff", id = <spellID>, buff = <auraSpellID>, source = "spell" },
    })
end
"""

if __name__ == "__main__":
    main()
