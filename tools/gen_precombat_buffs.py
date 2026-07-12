# Generate Data/PrecombatBuffs.lua from wago.tools DB2 dumps. Discovers buff consumables
# by item class/subclass (not name), resolves the persistent buff aura each one grants
# (following trigger chains for food), decodes the stat, and emits a source-aware table.
#
#   python tools/gen_precombat_buffs.py            # all expansions
#   python tools/gen_precombat_buffs.py > out.lua  # inspect without writing
#
# Re-run each major patch after refreshing the CSVs in Documentation/wow_spell_csv/
# (includes SpellEquippedItems - the weapon-subclass restriction masks).
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
STAT_AURAS = {"189", "29", "137", "99", "124", "511"}  # MOD_RATING/STAT/TOTAL_STAT%/AP/RANGED_AP; 511 = new Midnight alchemy-phial stat aura
# Combat-rating bits (EffectMiscValue on a MOD_RATING aura) -> secondary stat. Verified
# against this build's buffs: crit 8-10, haste 17-19, mastery 25, versatility 28-30,
# speed 13 (the Speed secondary stat - a rating that stacks, unlike a flat run-speed %).
RATING_BITS = {"crit": (8, 9, 10), "haste": (17, 18, 19), "mastery": (25,),
               "versatility": (28, 29, 30), "speed": (13,)}
PRIMARY_STAT = {"0": "strength", "1": "agility", "2": "stamina", "3": "intellect"}
# A maintained pre-buff must last a while to be a useful out-of-combat reminder: drop any
# aura buff shorter than this (e.g. a 15s movement-speed "snack" food that carries a stat).
FLOOR_MS = 20 * 60 * 1000  # 20 minutes

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
    mi = {}  # spellID -> DurationIndex (SpellMisc)
    with open(find_csv("SpellMisc"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            sid = r.get("SpellID") or r.get("ID")
            if sid:
                mi[sid] = r["DurationIndex"]
    du = {}  # DurationIndex -> duration ms (SpellDuration)
    with open(find_csv("SpellDuration"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            du[r["ID"]] = int(r["Duration"] or 0)
    eq = {}  # spellID -> allowed weapon-subclass bitmask (EquippedItemClass 2 = weapon)
    with open(find_csv("SpellEquippedItems"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["EquippedItemClass"] == "2":
                mask = int(r["EquippedItemSubclass"] or 0)
                if mask > 0:
                    eq[r["SpellID"]] = mask
    return cls, ie, ix, se, mi, du, eq


def buff_ms(buff, mi, du):
    """Duration (ms) of a buff spell, or None when unknown (missing = keep, don't drop)."""
    return du.get(mi.get(str(buff)))


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
    if aura == "511":
        # New Midnight alchemy-phial stat aura. Its misc encodes the secondary (dual-stat
        # phials), but the mapping isn't the old RATING_BITS bit layout and isn't documented
        # here - so tag it generic ("primary" = surfaces under the Auto preference). Decode
        # the misc->stat map later if per-stat phial preference is wanted.
        return "primary"
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
    # A flat run-speed % (aura 31) is deliberately NOT tracked: it doesn't stack with other
    # movement effects (highest wins), so it's often dead weight, and the addon can't tell
    # OOC whether it'll clash. The Speed *secondary stat* (rating bit 13, matched above) is
    # the real "speed" option - it's a rating, so it always stacks.
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


# Eating-aura signature: apply-aura effect (6) with OBS_MOD_HEALTH (84) / OBS_MOD_POWER
# (85) - "restores health/mana while eating". Verified against 5004/396918/452276.
# Type 20 is the Midnight eating-regen variant: the new "Food" aura (1269920, on the Warped
# feast line) uses 20 instead of 84 for the same "restore health while eating" tick - without
# it those foods have no detectable eating aura, so the 10s eat channel bar never shows.
EAT_AURAS = {"84", "85", "20"}


def trigger_closure(sid, se, depth=0, seen=None):
    """All spells reachable from sid via EffectTriggerSpell, sid included (depth <= 4).
    The visible eating aura can hang off a side branch of the Well Fed resolution path
    (use -> "Refreshment" -> trigger -> shared "Food"), so walk everything."""
    seen = seen if seen is not None else set()
    if not sid or sid == "0" or sid in seen:
        return seen
    seen.add(sid)
    if depth < 4:
        for _eff, _aura, trig, _misc in se.get(sid, []):
            if trig and trig != "0":
                trigger_closure(trig, se, depth + 1, seen)
    return seen


def is_eating_aura(sid, se):
    return any(eff == "6" and aura in EAT_AURAS for eff, aura, _t, _m in se.get(sid, []))


def categorize(name, sub):
    cat = SUBCLASS.get(sub)
    if cat == "enh":
        if "Augment Rune" in name:
            return "augmentRune"
        # Coarse name pre-filter (case-insensitive; catches compound names like "Razorstone").
        # The real gate is the effect-54 (ENCHANT_ITEM_TEMPORARY) check at the call site, which
        # drops any non-enchant that slips through (lures, illusions, lockpicks, etc.).
        low = name.lower()
        if any(k in low for k in ("oil", "stone", "wax", "razor", "sharpen", "whet", "weight")):
            return "weaponEnchant"
        return None
    return cat  # flask / food


def main():
    cls, ie, ix, se, mi, du, eq = load()
    CRAFTING = ("Recipe:", "Pattern:", "Plan:", "Formula:", "Technique:", "Design:", "[")
    buckets = defaultdict(list)  # cat -> [(exp, ilvl, id, name, buff, stat, wmask)]
    dropped_short = 0

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
            # Midnight feast-line foods (Warped Wise Wings, etc.) apply their stat via a server
            # script routed through the shared "Become Well Fed" (1219179) DUMMY aura, so the
            # secondary isn't in DBC and resolve_buff finds nothing. Don't drop them - a food is
            # still worth an out-of-combat Well Fed reminder. Emit with that shared marker buff +
            # a generic stat (surfaces under the Auto preference). New alchemy phials are handled
            # up in resolve_buff via aura 511; other one-off script consumables (e.g. some PvP
            # flasks using a bare dummy aura) are intentionally not force-included here.
            if cat == "food" and not buff and use and "1219179" in trigger_closure(use, se):
                # Adaptive feast food: the server script lands one of the per-secondary "Well
                # Fed" buffs (the data says by the player's best secondary), so the DISH has no
                # fixed stat. Tag all four secondaries so it satisfies ANY stat preference in the
                # dropdown (GetBestOwnedBuff does a substring match); detection of "fed" is
                # handled by the RegisterFoodWellFedBuffs family, not this per-item marker buff.
                buff, stat = "1219179", "crit+haste+mastery+versatility"
            # flask/food/rune must grant a detectable stat aura; weapon enchants are
            # detected via GetWeaponEnchantInfo so they keep their apply-spell instead -
            # but skip any with no resolvable spell at all (avoids buff = nil entries).
            wmask = None
            if cat == "weaponEnchant":
                # A real temp weapon enchant carries effect 54 (ENCHANT_ITEM_TEMPORARY) on
                # its use spell; name-matched stragglers (contracts, portal stones,
                # ensembles) don't - drop them.
                if not any(e == "54" for e, _a, _t, _m in se.get(use or "", [])):
                    continue
                buff = buff or use
                # No secondary-stat matrix for consumable enhancements; tag the archetype so
                # the addon can auto-pick the class-appropriate one (casters want oils,
                # physical specs want stones/whetstones).
                stat = "caster" if ("Oil" in name or "Wax" in name) else "physical"
                # Allowed weapon-subclass bitmask (whetstone = bladed, weightstone = blunt);
                # the addon tests the equipped main hand against it at suggest time.
                wmask = eq.get(use)
            elif not buff:
                continue
            # Duration floor: a maintained pre-buff has to last a while to be worth an OOC
            # reminder. Drop aura buffs under 20 min (e.g. a short "snack" food that carries
            # a stat). weaponEnchant is exempt - it's read off the weapon, not an aura, so
            # its apply-spell has no meaningful duration. Unknown duration = keep.
            if cat != "weaponEnchant":
                ms = buff_ms(buff, mi, du)
                if ms is not None and 0 < ms < FLOOR_MS:
                    dropped_short += 1
                    continue
            buckets[cat].append((int(r["ExpansionID"] or 0), int(r["ItemLevel"] or 0),
                                 iid, name, buff, stat, wmask))
    # Weapon enchants are kept across all expansions: the addon filters them at suggest
    # time by the equipped weapon's expansion (an older oil/stone won't apply to a newer
    # weapon), which also keeps leveling-content coverage that a hard floor would drop.

    lines = [HEADER]
    for cat in ("flask", "food", "augmentRune", "weaponEnchant"):
        items = sorted(buckets.get(cat, []), key=lambda x: (-x[0], -x[1], x[3]))
        lines.append(f"    {cat} = {{")
        cur = None
        for exp, ilvl, iid, name, buff, stat, wmask in items:
            if exp != cur:
                lines.append(f"        -- {EXPANSION.get(exp, 'exp ' + str(exp))}")
                cur = exp
            st = f', stat = "{stat}"' if stat else ""
            wm = f", wmask = {wmask}" if wmask else ""
            lines.append(f"        {{ id = {iid}, buff = {buff}{st}{wm} }},"
                         f"  -- {name}")
        lines.append("    },")
        print(f"  {cat}: {len(items)} items", file=sys.stderr)
    lines.append(FOOTER)

    # Eating auras: every eat/drink regen aura reachable from ANY food item's use-spell
    # trigger chain (not just foods that made the buff cut - extra ids are harmless, the
    # runtime test is set membership against the player's visible buffs).
    eat_ids = set()
    for iid, sub in cls.items():
        if sub == "5":
            for sid in trigger_closure(on_use(iid, ie, ix), se):
                if is_eating_aura(sid, se):
                    eat_ids.add(int(sid))
    lines.append(EAT_HEADER)
    ids = sorted(eat_ids)
    for i in range(0, len(ids), 12):
        lines.append("        " + ", ".join(str(x) for x in ids[i:i + 12]) + ",")
    lines.append("    })\nend\n")
    print(f"  eatingAuras: {len(ids)} ids", file=sys.stderr)

    # "Well Fed" family: the adaptive Midnight feast foods (buff-marker 1219179) land one of
    # the per-secondary "Well Fed" buffs via server script - not reachable from the item's spell
    # chain, so collect them by NAME + a stat-rating aura (189) instead. Registered into the food
    # buffSet so the food category detects "fed" no matter which dish/stat the player ate.
    name_by_id = {}
    with open(find_csv("SpellName"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            name_by_id[r["ID"]] = r["Name_lang"]
    wellfed = sorted(int(sid) for sid, effs in se.items()
                     if name_by_id.get(sid) == "Well Fed"
                     and any(e == "6" and a == "189" for e, a, _t, _m in effs))
    lines.append("if SpellDB.RegisterFoodWellFedBuffs then\n    SpellDB.RegisterFoodWellFedBuffs({\n        "
                 + ", ".join(str(x) for x in wellfed) + ",\n    })\nend\n")
    print(f"  wellFed food buffs: {len(wellfed)} ids", file=sys.stderr)

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"wrote {OUT} (dropped {dropped_short} sub-20m buffs)", file=sys.stderr)


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
-- Curated extras the per-class generator above doesn't cover: aura-discovered utility
-- categories (xp foods, duration-filtered to 20m+) plus toys and class self-buffs. All flow
-- through the same detect+overlay pipeline via `source`. This block is part of the generator
-- template, so a re-run preserves it verbatim - edit it here.
if SpellDB.RegisterPrecombatBuffsExtra then
    SpellDB.RegisterPrecombatBuffsExtra({
        -- (Speed foods/flasks - the Speed *secondary stat*, rating bit 13 - are generated
        --  above tagged stat = "speed". Flat run-speed % foods, aura 31, are intentionally
        --  not tracked: they don't stack and can't be validated OOC.)

        -- XP (leveling): long XP buffs only (>= 20m). Off by default. Tome of Combat Training
        -- (10m) intentionally excluded by the duration floor.
        { category = "xp", id = 166750, buff = 289982 },      -- Draught of Ten Lands (60m)
        { category = "xp", id = 166751, buff = 289982 },      -- Draught of Ten Lands (60m)
        { category = "xp", id = 239142, buff = 1221184 },     -- Bottle of Mysterious Wisdom (120m)
        { category = "xp", id = 254693, buff = 1258529 },     -- Distilled Knowledge of Timeways (120m)
        { category = "xp", id = 209997, buff = 423860 },      -- Distilled Knowledge of Timeways (120m)

        -- XP / leveling toys (source = "toy": owned via PlayerHasToy, used via /usetoy)
        -- { category = "xp", id = <toyItemID>, buff = <auraSpellID>, source = "toy" },

        -- Class self-buffs (source = "spell": known via IsSpellKnown, cast via type=spell)
        -- { category = "classBuff", id = <spellID>, buff = <auraSpellID>, source = "spell" },
    })
end
"""

EAT_HEADER = """\

-- ──────────────────────────── EATING AURAS (generated) ────────────────────────────
-- Every eat/drink regen aura ("Food"/"Refreshment" variants) reachable from a food
-- item's use-spell trigger chain. This is the aura visible on the player while eating;
-- SpellDB.GetActiveEatingAura tests set membership for the eat sweep and "wait" hint.
if SpellDB.RegisterEatingAuras then
    SpellDB.RegisterEatingAuras({"""

if __name__ == "__main__":
    main()
