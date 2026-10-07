#!/usr/bin/env python3
# tools/gen_forever_consumables.py
#
# WoW Forever consumables -> Data/ForeverConsumables.lua, from the Forever client data
# (Documentation/wow_spell_csv_forever). Retail's consumable lists (Data/PrecombatBuffs.lua,
# Data/HealingItems.lua) are retail items, ids and durations; on Forever they are skipped and
# this file is loaded instead. Same discovery rules as the retail generators - by item class
# and by what the item's spell does, never by name - with the Classic item layout and stats:
#
#   buff categories (the pre-pull reminder, same pipeline as retail):
#     flask    Classic flasks AND elixirs (subclass 3 + 2): the long stat buff
#     scroll   scrolls (subclass 4): they stack with elixirs on Forever, so their own slot
#     food     Well Fed foods (subclass 5 whose eating ends in a stat buff)
#     weaponEnchant  sharpening stones, weightstones, oils (effect 54)
#   recovery (Forever only: out of combat with low health / mana):
#     food / drink   plain eat / drink items, ranked by what one restores
#     bandage        First Aid bandages (subclass 7), ranked the same way
#   healing potions (the in-combat defensive pick): heal-on-use potions and healthstones
#
# Shares buff resolution, eating-aura detection and on-use lookup with gen_precombat_buffs.py
# (imported, pointed at the Forever CSVs).
#
# Usage: python tools/gen_forever_consumables.py
import csv, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gen_precombat_buffs as gpb  # noqa: E402

gpb.CSV_DIR = os.path.join(ROOT, "Documentation", "wow_spell_csv_forever")
OUT = os.path.join(ROOT, "Data", "ForeverConsumables.lua")

# Classic item class 0 subclasses.
POTION, ELIXIR, FLASK, SCROLL, FOOD, BANDAGE, OTHER = "1", "2", "3", "4", "5", "7", "8"
BUFF_CATEGORY = {FLASK: "flask", ELIXIR: "flask", SCROLL: "scroll", FOOD: "food"}
# Classic stat auras: 29 MOD_STAT (misc 0 str, 1 agi, 2 sta, 3 int, 4 spi), 99 / 124 attack
# power / ranged AP, 22 MOD_RESISTANCE (misc 1 = armor), 13 MOD_DAMAGE_DONE (spell power),
# 135 MOD_HEALING_DONE, 34 MOD_INCREASE_HEALTH.
CLASSIC_STAT = {"0": "strength", "1": "agility", "2": "stamina", "3": "intellect", "4": "spirit"}
gpb.STAT_AURAS = {"29", "99", "124", "22", "13", "135", "34"}


def classic_stat_of(aura, misc):
    if aura == "29":
        return CLASSIC_STAT.get(misc, "stat")
    return {"99": "attackpower", "124": "rangedattackpower", "13": "spellpower",
            "135": "healing", "34": "stamina"}.get(aura) or ("armor" if aura == "22" else None)


gpb.stat_of = classic_stat_of
# Classic buffs are shorter than retail's: Well Fed runs 15 minutes, scrolls 30, elixirs 60.
FLOOR_MS = 10 * 60 * 1000
HEALTH_REGEN, MANA_REGEN, PERIODIC_HEAL = "84", "85", "8"
HEAL_EFFECTS = {"10", "136"}   # direct heal, heal % of max health (healthstones)
NOISE = ("Deprecated", "[", "(TEST)", "QA ", "Recipe:", "Pattern:", "Plan:", "Formula:")


def num(x):
    try:
        return abs(float(x))
    except (TypeError, ValueError):
        return 0.0


def main():
    cls, ie, ix, se, mi, du, eq = gpb.load()
    full = defaultdict(list)   # spellID -> SpellEffect rows (amounts, periods)
    with open(gpb.find_csv("SpellEffect"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            full[r["SpellID"]].append(r)

    def restores(sid, aura):
        """Total health / mana one use restores through `aura` anywhere in its trigger chain."""
        best = 0.0
        for s in gpb.trigger_closure(sid, se):
            dur = (du.get(mi.get(s)) or 0) / 1000
            for e in full.get(s, []):
                if e["Effect"] == "6" and e["EffectAura"] == aura:
                    period = num(e["EffectAuraPeriod"]) / 1000 or 1
                    best = max(best, num(e["EffectBasePointsF"]) * (dur / period if dur else 1))
        return best

    buffs = defaultdict(list)       # category -> [(ilvl, id, name, buff, stat, wmask)]
    recovery = defaultdict(list)    # kind -> [(amount, id, name, level, wellfed)]
    potions = []
    with open(gpb.find_csv("ItemSparse"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            iid, name = r["ID"], r["Display_lang"]
            sub = cls.get(iid)
            if sub is None or any(n in name for n in NOISE):
                continue
            use = gpb.on_use(iid, ie, ix)
            if not use:
                continue
            ilvl, lvl = int(r["ItemLevel"] or 0), int(r["RequiredLevel"] or 0)
            buff, stat = gpb.resolve_buff(use, se) or (None, None)
            ms = buff and du.get(mi.get(buff))
            long_enough = buff and not (ms and 0 < ms < FLOOR_MS)
            if sub in BUFF_CATEGORY and long_enough and not (sub == FOOD and stat is None):
                buffs[BUFF_CATEGORY[sub]].append((ilvl, iid, name, buff, stat, None))
            if sub == OTHER and any(e == "54" for e, _a, _t, _m in se.get(use, [])):
                kind = "caster" if ("Oil" in name or "Wax" in name) else "physical"
                buffs["weaponEnchant"].append((ilvl, iid, name, use, kind, eq.get(use)))
            if sub == FOOD:
                hp, mp = restores(use, HEALTH_REGEN), restores(use, MANA_REGEN)
                wellfed = bool(long_enough and stat)
                if hp:
                    recovery["food"].append((hp, iid, name, lvl, wellfed))
                if mp:
                    recovery["drink"].append((mp, iid, name, lvl, wellfed))
            if sub == BANDAGE:
                amount = restores(use, PERIODIC_HEAL)
                if amount:
                    recovery["bandage"].append((amount, iid, name, lvl, False))
            if sub in (POTION, ELIXIR, OTHER) and r["InventoryType"] == "0" and any(
                    e["Effect"] in HEAL_EFFECTS for e in full.get(use, [])):
                potions.append((ilvl, iid, name))

    eat_ids = set()
    for iid, sub in cls.items():
        if sub == FOOD:
            for sid in gpb.trigger_closure(gpb.on_use(iid, ie, ix), se):
                if gpb.is_eating_aura(sid, se):
                    eat_ids.add(int(sid))

    L = [HEADER, "SpellDB.RegisterPrecombatBuffs({"]
    for cat in ("flask", "scroll", "food", "weaponEnchant"):
        L.append(f"    {cat} = {{")
        for ilvl, iid, name, buff, stat, wmask in sorted(buffs[cat], key=lambda x: (-x[0], x[2])):
            st = f', stat = "{stat}"' if stat else ""
            wm = f", wmask = {wmask}" if wmask else ""
            L.append(f"        {{ id = {iid}, buff = {buff}{st}{wm} }},  -- {name}")
        L.append("    },")
    L.append("})")
    L.append("SpellDB.RegisterEatingAuras({")
    ids = sorted(eat_ids)
    for i in range(0, len(ids), 12):
        L.append("    " + ", ".join(str(x) for x in ids[i:i + 12]) + ",")
    L.append("})")
    L.append("-- Recovery: amount = health / mana one use restores; best owned and usable wins.")
    L.append("SpellDB.RegisterRecoveryItems({")
    for kind in ("food", "drink", "bandage"):
        L.append(f"    {kind} = {{")
        for amount, iid, name, lvl, wf in sorted(recovery[kind], key=lambda x: (-x[0], x[2])):
            w = ", wellfed = true" if wf else ""
            L.append(f"        {{ id = {iid}, amount = {amount:g}, level = {lvl}{w} }},  -- {name}")
        L.append("    },")
    L.append("})")
    L.append("SpellDB.RegisterHealingItems({")
    for ilvl, iid, name in sorted(potions, key=lambda x: (-x[0], x[2])):
        L.append(f"    {iid},  -- {name}")
    L.append("})")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    counts = {c: len(v) for c, v in buffs.items()}
    counts.update({"recovery " + k: len(v) for k, v in recovery.items()})
    print(f"wrote {OUT}: {counts}, eating auras {len(ids)}, healing potions {len(potions)}")


HEADER = """\
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: WoW Forever consumables - pre-pull buffs (flasks + elixirs, scrolls, Well Fed food,
-- weapon stones / oils), eating auras, out-of-combat recovery (food, drink, bandages) and
-- healing potions.
--
-- GENERATED by tools/gen_forever_consumables.py from the Forever client data - do not
-- hand-edit. Retail's Data/PrecombatBuffs.lua and Data/HealingItems.lua skip on Forever;
-- this file skips on retail.
local SpellDB = LibStub("JustAC-SpellDB", true)
if not (SpellDB and SpellDB.IsForever and SpellDB.IsForever()) then return end
"""

if __name__ == "__main__":
    main()
