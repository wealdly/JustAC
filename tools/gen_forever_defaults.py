#!/usr/bin/env python3
# tools/gen_forever_defaults.py
#
# WoW Forever entries for JustAC's curated default lists -> Data/ForeverDefaults.lua.
#
# The lists below are curated BY ABILITY NAME (the slug of the client's spell name) per
# class. Every name must resolve to an ability that class can actually LEARN on Forever
# (tools/check_forever_apl.class_chains: class skill lines, talent grants), or the build
# exits 1 - a typo or a retail-only ability cannot ship. Ids are emitted as rank 1; the
# runtime resolves every rank (BlizzardAPI.GetDisplaySpellID, SpellDB.StaticLookup).
# Spell ranges and channel flags are not curated: they are read from the Forever client
# data (SpellMisc / SpellRange).
#
# The data file applies ONLY on the Forever client and adds "<CLASS>_F" keys (plus the
# class key where a table is read by class), so retail's lists are untouched.
#
# Sources: Documentation/forever-guides/*.md (defensive and healing sections) and the
# retail lists' own rules (SpellDB.lua comments: instants first, cast heals last).
#
# Usage: python tools/gen_forever_defaults.py [--print]
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "ForeverDefaults.lua")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_forever_apl as cfa  # noqa: E402

CLASSES = ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"]

# --- per-class lists (order matters where the table is a priority) ---------------------
# Personal defensives: instants first, cast-time heals last (the retail table's rule).
DEFENSIVE = {
    "warrior": ["last_stand", "shield_wall", "victory_rush"],
    "paladin": ["divine_shield", "divine_protection", "blessing_of_protection", "lay_on_hands",
                "flash_of_light", "holy_light"],
    "hunter":  ["deterrence", "feign_death"],
    "rogue":   ["evasion", "vanish"],
    "priest":  ["power_word_shield", "desperate_prayer", "renew", "flash_heal"],
    "shaman":  ["lesser_healing_wave", "healing_wave"],
    "mage":    ["ice_block", "ice_barrier", "mana_shield"],
    "warlock": ["death_coil", "shadow_ward", "drain_life"],
    "druid":   ["barkskin", "frenzied_regeneration", "rejuvenation", "regrowth", "healing_touch"],
}
PET_HEAL = {"hunter": ["mend_pet"], "warlock": ["health_funnel"]}
PET_REZ = {"hunter": ["revive_pet", "call_pet"],
           "warlock": ["summon_imp", "summon_voidwalker", "summon_succubus", "summon_felhunter"]}
# Party-wide, press-and-done relief for non-healers (retail's "group help" rule).
GROUP_HELP = {"shaman": ["healing_stream_totem"]}
# Group heals and the emergency ladder: opt-in healing features.
GROUP_HEAL = {"priest": ["prayer_of_healing"], "shaman": ["chain_heal"], "druid": ["tranquility"]}
EMERGENCY = {"druid": ["tranquility"]}
# Melee gap closers (the table's presence also marks the class as melee).
GAP_CLOSER = {"warrior": ["charge", "intercept"], "rogue": ["sprint"], "druid": ["feral_charge"]}
# Major offensive cooldowns: the burst-ready cue. (Elemental Mastery, Concussive Blow and a
# learnable Wyvern Sting do not exist on Forever - the resolver rejected them.)
BURST = {
    "warrior": ["recklessness", "death_wish"],
    "rogue":   ["adrenaline_rush", "blade_flurry", "cold_blood"],
    "mage":    ["arcane_power", "combustion", "presence_of_mind"],
    "hunter":  ["rapid_fire", "bestial_wrath"],
    "priest":  ["power_infusion"],
}
# Cheap between-pull heals (read by class).
TOPOFF = {"priest": ["renew", "lesser_heal"], "paladin": ["flash_of_light", "holy_light"],
          "druid": ["rejuvenation", "regrowth"], "shaman": ["lesser_healing_wave", "healing_wave"]}
# Maintained buffs (read by class): (group names, default name, raidWide).
# ponytail: rogue poisons left out until a rogue probe shows whether they apply an aura or a
# weapon enchant on Forever (the wrong path nags forever).
# Only long buffs belong here: one shorter than SHORT_BUFF_SECS (Battle Shout, 3 min) is a
# combat buff the rotation list keeps up, and the build refuses it (see SHORT_BUFFS below).
MAINTAINED = {
    "priest":  [(["power_word_fortitude"], "power_word_fortitude", True),
                (["inner_fire"], "inner_fire", False)],
    "mage":    [(["arcane_intellect"], "arcane_intellect", True),
                (["frost_armor", "ice_armor", "mage_armor"], "frost_armor", False)],
    "druid":   [(["mark_of_the_wild"], "mark_of_the_wild", True)],
    "warlock": [(["demon_skin", "demon_armor"], "demon_skin", False)],
    "shaman":  [(["lightning_shield", "water_shield"], "lightning_shield", False)],
    "paladin": [(["devotion_aura", "retribution_aura", "concentration_aura"], "devotion_aura", False)],
    "hunter":  [(["aspect_of_the_hawk", "aspect_of_the_monkey"], "aspect_of_the_hawk", False)],
}
# Shaman weapon imbues: first KNOWN wins as the default (the table's rule).
IMBUES = ["windfury_weapon", "flametongue_weapon", "rockbiter_weapon"]
IMBUE_ALL = IMBUES + ["frostbrand_weapon"]

# --- spellID-keyed registries (only abilities the retail data lacks need listing; the
# classic ids it already has - Kick, Pummel, Counterspell, Polymorph's peers - resolve by rank).
INTERRUPTS = {  # name: meta (SpellMechanic ids: 2 disoriented, 5 fleeing, 12 stunned,
                #                               17 polymorphed, 24 horrified)
    ("warrior", "shield_bash"):     {"kind": "interrupt", "reach": "ranged", "pri": 1},
    ("shaman", "earth_shock"):      {"kind": "interrupt", "reach": "ranged", "pri": 1},
    ("druid", "feral_charge"):      {"kind": "interrupt", "reach": "ranged", "pri": 2},
    ("druid", "bash"):              {"kind": "cc", "mech": 12, "reach": "ranged", "pri": 3},
    ("hunter", "scatter_shot"):     {"kind": "cc", "mech": 2, "reach": "ranged", "pri": 3},
    ("hunter", "intimidation"):     {"kind": "cc", "mech": 12, "reach": "ranged", "pri": 3},
    ("mage", "polymorph"):          {"kind": "cc", "mech": 17, "reach": "ranged", "pri": 4},
    ("warlock", "fear"):            {"kind": "cc", "mech": 5, "reach": "ranged", "pri": 5},
    ("warlock", "death_coil"):      {"kind": "cc", "mech": 24, "reach": "ranged", "pri": 4},
}
# 2908 is Soothe Animal on Forever (beast crowd control), not an enrage dispel.
SOOTHE_REMOVE = [2908]
# Range-check references per class: yards come from the client data. Never an on-next-swing
# ability: its range check answers "in" at any distance (measured: Heroic Strike in at 15 yd
# while Rend read out), which reads as permanent melee range and kills the gap closer.
RANGE = {
    "warrior": ["rend", "hamstring", "sunder_armor", "charge"], "rogue": ["sinister_strike", "kick"],
    "hunter": ["arcane_shot", "wing_clip"], "mage": ["frostbolt", "fire_blast"],
    "warlock": ["shadow_bolt", "corruption"], "priest": ["smite", "shadow_word_pain"],
    "druid": ["wrath", "moonfire", "claw"], "shaman": ["lightning_bolt", "earth_shock"],
    "paladin": ["judgement", "holy_strike"],
}
# Emergency tiers (SpellDB DEFENSE_TIER): 1 immunity, 2 big instant heal, 4 pre-emptive wall.
TIERS = {
    ("paladin", "divine_shield"): 1, ("paladin", "divine_protection"): 1,
    ("paladin", "blessing_of_protection"): 1, ("mage", "ice_block"): 1,
    ("paladin", "lay_on_hands"): 2, ("priest", "desperate_prayer"): 2, ("warrior", "victory_rush"): 2,
    ("warrior", "shield_wall"): 4, ("warrior", "last_stand"): 4, ("rogue", "evasion"): 4,
    ("hunter", "deterrence"): 4,
}
HEALS = {"victory_rush", "lay_on_hands", "flash_of_light", "holy_light", "desperate_prayer", "renew",
         "flash_heal", "lesser_healing_wave", "healing_wave", "drain_life", "rejuvenation", "regrowth",
         "healing_touch", "lesser_heal", "frenzied_regeneration", "mend_pet", "health_funnel",
         "prayer_of_healing", "chain_heal", "tranquility", "healing_stream_totem"}
CHANNEL_ATTR1 = 0x4 | 0x40   # SPELL_ATTR1_IS_CHANNELLED / IS_SELF_CHANNELLED
NEXT_SWING_ATTR0 = 0x4       # SPELL_ATTR0_ON_NEXT_SWING (Heroic Strike, Cleave, Raptor Strike, Maul)
# A DoT: APPLY_AURA (6) of PERIODIC_DAMAGE (3) on the enemy target (6).
DOT_EFFECT, DOT_AURA, ENEMY_TARGET = "6", "3", "6"
SUMMON_EFFECTS = {"28", "87", "88", "89", "90"}   # SUMMON, SUMMON_OBJECT_SLOT1-4 (totems)
SCHOOL_DAMAGE = "2"
# The cast's own hit as a share of hit + the DoT's total (client data, per rank). At or above
# NUKE_SHARE the spell is a nuke with a DoT rider (Fireball 89%, Holy Fire 73%): never tracked
# as a DoT, or it sank after every cast while its 2-damage burn ran. At or above FRONTAL_SHARE
# the hit still lands on a dying target (Moonfire, Flame Shock, Rake, Immolate), so the
# dying-target block skips it; it still sinks while ticking, since an early recast on Forever
# overwrites the ticks left.
NUKE_SHARE, FRONTAL_SHARE = 0.5, 0.25
# A buff shorter than this lapses mid-fight on Forever: it is kept up in combat by the
# rotation list, never offered as between-pull upkeep, never treated as an hour-long party
# buff. Longer than the 5 min upkeep window with room to spare.
SHORT_BUFF_SECS = 600
BUFF_TARGETS = {"1", "20"}   # the caster; the caster's party (Battle Shout)


class Resolver:
    def __init__(self):
        self.by_class = {c: cfa.class_chains(cfa.CLASS_MASK[c]) for c in CLASSES}
        self.missing = []

    def chain(self, cls, name):
        ch = self.by_class[cls][0].get(name)
        if not ch:
            self.missing.append(f"{cls}: {name}")
        return ch

    def r1(self, cls, name):
        ch = self.chain(cls, name)
        return int(ch[0][0]) if ch else None

    def ranks(self, cls, name):
        ch = self.chain(cls, name)
        return [int(i) for i, _ in ch] if ch else []


def ids(res, cls, names):
    return [i for i in (res.r1(cls, n) for n in names) if i]


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(int(v)) if float(v).is_integer() else repr(v)
    if isinstance(v, str):
        return '"' + v + '"'
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    return "{ " + ", ".join(f"{k} = {lua(x)}" for k, x in v.items()) + " }"


def class_block(var, table):
    return [f"local {var} = {{"] + [f"    {c.upper()} = {lua(v)}," for c, v in table.items() if v] + ["}"]


def main():
    res = Resolver()
    names = {r["ID"]: r["Name_lang"] for r in cfa.rows("SpellName")}
    misc = {r["SpellID"]: r for r in cfa.rows("SpellMisc")}
    rng = {r["ID"]: r for r in cfa.rows("SpellRange")}

    lines = []
    for var, src in [("DEFENSIVE", DEFENSIVE), ("PET_HEAL", PET_HEAL), ("PET_REZ", PET_REZ),
                     ("GROUP_HELP", GROUP_HELP), ("GROUP_HEAL", GROUP_HEAL), ("EMERGENCY", EMERGENCY),
                     ("GAP_CLOSER", GAP_CLOSER), ("BURST", BURST), ("TOPOFF", TOPOFF)]:
        lines += class_block(var, {c: ids(res, c, n) for c, n in src.items()})

    secs = {r["ID"]: int(r["Duration"] or 0) / 1000 for r in cfa.rows("SpellDuration")}

    def duration(sid):
        m = misc.get(str(sid))
        return secs.get(m["DurationIndex"], 0) if m else 0

    lines.append("local MAINTAINED = {")
    for cls, groups in MAINTAINED.items():
        out = []
        for group, default, raid in groups:
            g = ids(res, cls, group)
            auras = [i for n in group for i in res.ranks(cls, n)]
            d = res.r1(cls, default)
            if not g or not d:
                continue
            if 0 < duration(d) < SHORT_BUFF_SECS:
                res.missing.append(f"{cls}: {default} lasts {duration(d):g}s - a combat buff, not upkeep")
                continue
            e = {"group": g, "default": d}
            if raid:
                e["raidWide"] = True
            e["auraIDs"] = auras          # every rank's aura: a rank-3 cast applies the rank-3 buff
            out.append(e)
        if out:
            lines.append(f"    {cls.upper()} = {{ " + ", ".join(lua(e) for e in out) + " },")
    lines.append("}")
    lines.append("local IMBUES = " + lua(ids(res, "shaman", IMBUES)))
    lines.append("local IMBUE_CASTS = " + lua([i for n in IMBUE_ALL for i in res.ranks("shaman", n)]))

    lines.append("local INTERRUPTS = {")
    for (cls, name), meta in INTERRUPTS.items():
        sid = res.r1(cls, name)
        if sid:
            lines.append(f"    [{sid}] = {lua(meta)},  -- {names.get(str(sid), '?')}")
    lines.append("}")
    lines.append("local SOOTHE_REMOVE = " + lua(SOOTHE_REMOVE))

    lines.append("local RANGE = {")
    for cls, nlist in RANGE.items():
        for n in nlist:
            sid = res.r1(cls, n)
            if not sid:
                continue
            if int((misc.get(str(sid)) or {}).get("Attributes_0") or 0) & NEXT_SWING_ATTR0:
                res.missing.append(f"{cls}: {n} is on-next-swing, unusable as a range reference")
                continue
            r = rng.get((misc.get(str(sid)) or {}).get("RangeIndex", ""), {})
            yards = r.get("RangeMax_0") or "0"
            lines.append(f"    [{sid}] = {lua(round(float(yards)))},  -- {names.get(str(sid), '?')} ({cls})")
    lines.append("}")

    lines.append("local TIERS = {")
    for (cls, name), tier in TIERS.items():
        sid = res.r1(cls, name)
        if sid:
            lines.append(f"    [{sid}] = {tier},  -- {names.get(str(sid), '?')}")
    lines.append("}")

    # Categories: everything the defensive-side lists name, split heal / defensive, plus CC.
    defensive, healing = set(), set()
    for src in (DEFENSIVE, PET_HEAL, GROUP_HELP, GROUP_HEAL):
        for cls, nlist in src.items():
            for n in nlist:
                sid = res.r1(cls, n)
                if sid:
                    (healing if n in HEALS else defensive).add(sid)
    cc = {res.r1(c, n) for (c, n), m in INTERRUPTS.items() if m["kind"] == "cc"} - {None}
    # Racials by role (cfa.RACIAL_ROLES): defensive and CC ones route like the class's own.
    defensive |= set(cfa.racial_ids("defensive"))
    cc |= set(cfa.racial_ids("cc"))
    lines.append("local CATEGORIES = { defensive = " + lua({f"[{i}]": True for i in sorted(defensive)})
                 .replace('"', "") + ", healing = " + lua({f"[{i}]": True for i in sorted(healing)})
                 .replace('"', "") + ", cc = " + lua({f"[{i}]": True for i in sorted(cc)}).replace('"', "") + " }")

    # Channeled spells: every learnable class ability whose SpellMisc flags it channeled.
    channeled = set()
    for cls in CLASSES:
        for sid in res.by_class[cls][1]:
            m = misc.get(str(sid))
            if m and int(m.get("Attributes_1") or 0) & CHANNEL_ATTR1:
                channeled.add(sid)
    lines.append("local CHANNELED = {")
    for sid in sorted(channeled):
        lines.append(f"    [{sid}] = true,  -- {names.get(str(sid), '?')}")
    lines.append("}")

    # Target DoTs, every rank with its own duration: the queue times them from the cast
    # (target debuffs are unreadable in combat) and sinks them while they run.
    dot_ids = {int(r["SpellID"]) for r in cfa.rows("SpellEffect") if r["SpellID"].isdigit()
               and r["Effect"] == DOT_EFFECT and r["EffectAura"] == DOT_AURA
               and r["ImplicitTarget_0"] == ENEMY_TARGET}
    # Plus every debuff the rotation lists keep up on the target (a "dot" gate: Faerie Fire,
    # Demoralizing Shout, Hunter's Mark, curses) - tracked the same way, or they were suggested
    # again and again. Every rank of each. Not summons (totems are not on the target).
    # Reads Data/ForeverRotations.lua: run gen_forever_rotations.py first.
    rot = open(os.path.join(ROOT, "Data", "ForeverRotations.lua"), encoding="utf-8").read()
    summons = {r["SpellID"] for r in cfa.rows("SpellEffect") if r["Effect"] in SUMMON_EFFECTS}
    for gid in {int(x) for x in re.findall(r't="dot",id=(\d+)', rot)}:
        for cls in CLASSES:
            chain = res.by_class[cls][1].get(gid)
            if chain and str(gid) not in summons:
                dot_ids |= {int(i) for i, _ in chain}
    # Upfront share per id (see NUKE_SHARE): nukes leave the DoT list, frontal DoTs are marked.
    effects = {}
    for r in cfa.rows("SpellEffect"):
        effects.setdefault(r["SpellID"], []).append(r)

    def num(x):
        try:
            return abs(float(x))
        except (TypeError, ValueError):
            return 0.0

    def upfront_share(sid):
        es = effects.get(str(sid), [])
        hit = sum(num(e["EffectBasePointsF"]) for e in es if e["Effect"] == SCHOOL_DAMAGE)
        dur = duration(sid)
        ticks = sum(num(e["EffectBasePointsF"]) * dur / (num(e["EffectAuraPeriod"]) / 1000)
                    for e in es if e["Effect"] == DOT_EFFECT and e["EffectAura"] == DOT_AURA
                    and num(e["EffectAuraPeriod"]) > 0)
        return hit / (hit + ticks) if hit + ticks > 0 else 0.0
    class_ids = set().union(*(res.by_class[cls][1] for cls in CLASSES))
    dot_ids &= class_ids
    shares = {sid: upfront_share(sid) for sid in dot_ids}
    dot_ids = {sid for sid in dot_ids if shares[sid] < NUKE_SHARE}
    # Frontal: every class DoT whose hit is FRONTAL_SHARE or more - the nukes included, since a
    # list may still carry a "dot" gate on one (Holy Fire) and its hit lands on a dying target.
    lines.append("local FRONTAL_DOTS = {")
    for sid in sorted(s for s in shares if shares[s] >= FRONTAL_SHARE):
        lines.append(f"    [{sid}] = true,  -- {names.get(str(sid), '?')} ({shares[sid]:.0%} upfront)")
    lines.append("}")
    # On-next-swing abilities, every rank: the queue shows one as in progress while queued.
    lines.append("local NEXT_SWING = {")
    for cls in CLASSES:
        for sid in sorted(res.by_class[cls][1]):
            m = misc.get(str(sid))
            if m and int(m.get("Attributes_0") or 0) & NEXT_SWING_ATTR0:
                lines.append(f"    [{sid}] = true,  -- {names.get(str(sid), '?')} ({cls})")
    lines.append("}")

    # Short buffs (rank 1): kept up in combat, so off retail's party-buff and unique-aura
    # lists, which hide their members in combat when buffs cannot be read.
    buff_ids = {r["SpellID"] for r in cfa.rows("SpellEffect")
                if r["Effect"] == DOT_EFFECT and r["ImplicitTarget_0"] in BUFF_TARGETS}
    short = {int(ch[0][0]) for cls in CLASSES for ch in res.by_class[cls][0].values()
             if ch[0][0] in buff_ids and 0 < duration(ch[0][0]) < SHORT_BUFF_SECS}
    lines.append("local SHORT_BUFFS = {")
    for sid in sorted(short):
        lines.append(f"    {sid},  -- {names.get(str(sid), '?')} ({duration(sid):g}s)")
    lines.append("}")

    lines.append("local DOTS = {")
    for cls in CLASSES:
        for sid in sorted(dot_ids & set(res.by_class[cls][1])):
            m = misc.get(str(sid))
            dur = secs.get(m["DurationIndex"], 0) if m else 0
            if dur > 0:
                lines.append(f"    [{sid}] = {dur:g},  -- {names.get(str(sid), '?')}")
    lines.append("}")

    if res.missing:
        print("UNRESOLVED - not learnable on Forever:\n  " + "\n  ".join(sorted(set(res.missing))))
        sys.exit(1)

    text = "\n".join([
        "-- SPDX-License-Identifier: GPL-3.0-or-later",
        "-- Copyright (C) 2024-2026 wealdly",
        "--",
        "-- JustAC: WoW Forever entries for the curated default lists. GENERATED by",
        "-- tools/gen_forever_defaults.py (curated by ability name there) - do not edit by hand.",
        "-- Applies only on the Forever client: \"<CLASS>_F\" keys are added (plus the class key for",
        "-- tables read by class), so retail's lists are untouched. Ids are rank 1; every rank",
        "-- resolves at runtime (BlizzardAPI.GetDisplaySpellID, SpellDB.StaticLookup).",
        "",
        "local SpellDB = LibStub(\"JustAC-SpellDB\", true)",
        "if not (SpellDB and SpellDB.IsForever and SpellDB.IsForever()) then return end",
        "",
        *lines,
        "",
        "--- Forever entries under <CLASS>_F (the spec key there); byClass also replaces the",
        "--- class key, for tables some readers index by class.",
        "local function Put(tbl, lists, byClass)",
        "    if not tbl then return end",
        "    for class, list in pairs(lists) do",
        "        tbl[class .. \"_F\"] = list",
        "        if byClass then tbl[class] = list end",
        "    end",
        "end",
        "Put(SpellDB.CLASS_DEFENSIVE_DEFAULTS, DEFENSIVE)",
        "Put(SpellDB.CLASS_PETHEAL_DEFAULTS, PET_HEAL, true)",
        "Put(SpellDB.CLASS_PET_REZ_DEFAULTS, PET_REZ, true)",
        "Put(SpellDB.CLASS_GROUP_HELP_DEFAULTS, GROUP_HELP)",
        "Put(SpellDB.CLASS_GROUPHEAL_DEFAULTS, GROUP_HEAL)",
        "Put(SpellDB.HEAL_EMERGENCY_LADDER, EMERGENCY)",
        "Put(SpellDB.CLASS_GAPCLOSER_DEFAULTS, GAP_CLOSER)",
        "Put(SpellDB.CLASS_BURST_TRIGGER_DEFAULTS, BURST)",
        "Put(SpellDB.CLASS_TOPOFF_HEALS, TOPOFF, true)",
        "-- Replaced whole: retail's groups (rogue poisons, Battle Shout) name retail ids or",
        "-- retail behaviour.",
        "wipe(SpellDB.CLASS_MAINTAINED_BUFFS)",
        "for class, groups in pairs(MAINTAINED) do SpellDB.CLASS_MAINTAINED_BUFFS[class] = groups end",
        "for _, id in ipairs(SHORT_BUFFS) do",
        "    SpellDB.RAID_BUFF_SPELLS[id], SpellDB.UNIQUE_AURA_SPELLS[id] = nil, nil",
        "end",
        "if SpellDB.IndexMaintainedBuffs then SpellDB.IndexMaintainedBuffs() end",
        "-- In place: RedundancyFilter holds a reference to the enchant set.",
        "for _, id in ipairs(IMBUE_CASTS) do SpellDB.WEAPON_ENCHANT_SPELLS[id] = true end",
        "SpellDB.WEAPON_IMBUE_SPELLS = IMBUES",
        "SpellDB.RegisterInterruptAbilities(INTERRUPTS)",
        "if SpellDB.RegisterSootheAbilities then",
        "    local remove = {}",
        "    for _, id in ipairs(SOOTHE_REMOVE) do remove[id] = false end",
        "    SpellDB.RegisterSootheAbilities(remove)",
        "end",
        "SpellDB.RegisterRangeReferences(RANGE)",
        "if SpellDB.RegisterDefenseTiers then SpellDB.RegisterDefenseTiers(TIERS) end",
        "SpellDB.RegisterCategories(CATEGORIES)",
        "SpellDB.RegisterChanneledSpells(CHANNELED)",
        "-- Replaces retail's DoT list: its ids and durations are retail's.",
        "SpellDB.RegisterTargetDots(DOTS)",
        "for id in pairs(FRONTAL_DOTS) do SpellDB.FRONTAL_DOTS[id] = true end",
        "for id in pairs(NEXT_SWING) do SpellDB.NEXT_SWING_SPELLS[id] = true end",
        "",
    ])
    if "--print" in sys.argv:
        print(text)
    else:
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote", OUT, f"({len(channeled)} channeled, {len(defensive)} defensive, {len(healing)} heal ids)")


if __name__ == "__main__":
    main()
