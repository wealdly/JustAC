# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Spell-to-aura audit for WoW Forever: which aura each class ability applies, and where the
addon's aura reads would miss it.

For every learnable class ability (rank 1), from the Forever CSVs:
  * the auras it applies: its own APPLY_AURA / area-aura effects, or those of a spell it
    triggers (Bloodrage applies 29131 through TRIGGER_SPELL), with target side and duration;
  * whether that aura carries the cast's own id ("same") or another ("other");
  * whether the Cooldown Manager lists the cast or the aura (CooldownSetSpell);
  * whether raid frames show it (SpellAuraVisibility).

Then the cross-checks that matter for the queue:
  1. list gates (Data/Forever/Rotations.lua) on a buff/debuff id whose cast applies its aura
     under another id: the gate reads an aura that never appears;
  2. abilities whose aura id differs from the cast id at all (the Bloodrage shape), with
     whether the Cooldown Manager can see the aura id.

Read-only. Run: python tools/audit_forever_auras.py [--all]
"""
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_forever_apl as cfa  # noqa: E402

APPLY_AURA, TRIGGER_SPELL = "6", "64"
AREA_AURAS = {"35": "party", "65": "raid", "119": "pet", "128": "friend", "129": "enemy", "143": "owner"}
CASTER, ENEMY = "1", "6"
PASSIVE_ATTR0 = 0x40   # SPELL_ATTR0_PASSIVE


def main():
    names = {r["ID"]: r["Name_lang"] for r in cfa.rows("SpellName")}
    effects = defaultdict(list)
    for r in cfa.rows("SpellEffect"):
        effects[r["SpellID"]].append(r)
    misc = {r["SpellID"]: r for r in cfa.rows("SpellMisc")}
    secs = {r["ID"]: int(r["Duration"] or 0) / 1000 for r in cfa.rows("SpellDuration")}
    cdm = {r["SpellID"] for r in cfa.rows("CooldownSetSpell")}
    try:
        raid_shown = {r["SpellID"] for r in cfa.rows("SpellAuraVisibility")}
    except SystemExit:
        raid_shown = set()

    def duration(sid):
        m = misc.get(sid)
        return secs.get(m["DurationIndex"], 0) if m else 0

    def passive(sid):
        m = misc.get(sid)
        return bool(m and int(m.get("Attributes_0") or 0) & PASSIVE_ATTR0)

    def auras(sid, depth=0, via=None):
        """[(aura id, side, seconds, via)] the spell applies, following triggers one level."""
        out = []
        for e in effects.get(sid, []):
            eff, tgt = e["Effect"], e.get("ImplicitTarget_0")
            if eff == APPLY_AURA:
                side = "self" if tgt == CASTER else ("enemy" if tgt == ENEMY else f"target{tgt}")
                out.append((sid, side, duration(sid), via))
            elif eff in AREA_AURAS:
                out.append((sid, AREA_AURAS[eff], duration(sid), via))
            trig = e.get("EffectTriggerSpell") or "0"
            if depth < 1 and eff == TRIGGER_SPELL and trig != "0":
                out.extend(auras(trig, depth + 1, via=sid))
        seen, unique = set(), []
        for a in out:
            if (a[0], a[1]) not in seen:
                seen.add((a[0], a[1]))
                unique.append(a)
        return unique

    abilities = {}   # rank-1 id -> (class, slug)
    for cls in cfa.CLASS_MASK:
        chains, _ = cfa.class_chains(cfa.CLASS_MASK[cls])
        for slug, chain in chains.items():
            abilities[chain[0][0]] = (cls, slug)

    other = []
    for sid, (cls, slug) in sorted(abilities.items(), key=lambda kv: (kv[1][0], kv[1][1])):
        if passive(sid):
            continue
        for aura, side, seconds, via in auras(sid):
            if aura != sid and seconds > 0:
                other.append((cls, slug, sid, aura, side, seconds, aura in cdm, sid in cdm))

    # 1. List gates on an aura id that the cast never shows under that id.
    from lupa import LuaRuntime  # type: ignore[import-not-found]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("CAP=nil; LibStub=function() return {RegisterForever=function(c) CAP=c end} end")
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    gated = defaultdict(set)   # gate id -> {(class, tree)}

    def walk(g, cls, tree):
        t = g["t"]
        if t in ("any", "all"):
            for x in g["g"].values():
                walk(x, cls, tree)
        elif t in ("buff", "debuff", "dot", "stack") and g["id"]:
            gated[str(int(g["id"]))].add((cls, tree))
    cap = lua.globals().CAP
    for cls in cap.keys():
        for tree in cap[cls].keys():
            if tree == "default":
                continue
            for ctx in cap[cls][tree].values():
                for e in ctx.values():
                    for g in (e["gates"] or {}).values():
                        walk(g, cls, tree)
    mismatched = []
    for gid, where in sorted(gated.items(), key=lambda kv: int(kv[0])):
        own = [a for a in auras(gid) if a[0] == gid and a[2] > 0]
        moved = [a for a in auras(gid) if a[0] != gid and a[2] > 0]
        if not own and moved:
            mismatched.append((gid, names.get(gid, "?"), moved, sorted(where)))

    print("== 1. List gates whose aura id never appears (the cast applies another id)")
    for gid, name, moved, where in mismatched:
        target = ", ".join(f"{a} {names.get(a, '?')} ({side}, {s:g}s)" for a, side, s, _ in moved)
        trees = ", ".join(f"{c}/{t}" for c, t in where)
        print(f"   gate {gid} {name}: aura {target}  [{trees}]")
    if not mismatched:
        print("   none")

    print("\n== 2. Abilities whose aura has another id than the cast (the Bloodrage shape)")
    shown = [o for o in other if "--all" in sys.argv or o[4] in ("self", "enemy", "party", "raid")]
    for cls, slug, sid, aura, side, seconds, aura_cdm, cast_cdm in shown:
        cdm_note = "CDM aura" if aura_cdm else ("CDM cast only" if cast_cdm else "no CDM")
        print(f"   {cls:8} {names.get(sid, slug)[:26]:26} {sid:>8} -> {aura:>8} {names.get(aura, '?')[:24]:24} "
              f"{side:6} {seconds:>6g}s  {cdm_note}{'  raid-frame' if aura in raid_shown else ''}")
    # 3. Generated aura tables keyed by a cast id (Data/Forever/Defaults.lua): every rank whose
    # cast applies its aura under another id, so a read by the cast id would miss it.
    import re
    defaults = (ROOT / "Data" / "Forever" / "Defaults.lua").read_text(encoding="utf-8")
    print("\n== 3. Generated aura tables keyed by a cast whose aura has another id (every rank)")
    found = 0
    for table in ("TARGET_AURAS", "SELF_AURA_SECONDS", "DELAYED_PAYOFF", "GAINS_OVER_TIME"):
        m = re.search(r"^local " + table + r" = \{\n(.*?)^\}", defaults, re.M | re.S)
        if not m:
            continue
        for sid in re.findall(r"\[(\d+)\]", m.group(1)):
            own = [a for a in auras(sid) if a[0] == sid and a[2] > 0]
            moved = [a for a in auras(sid) if a[0] != sid and a[2] > 0]
            if moved and not own:
                found += 1
                target = ", ".join(f"{a} {names.get(a, '?')} ({side}, {s:g}s)" for a, side, s, _ in moved)
                print(f"   {table:18} {sid:>8} {names.get(sid, '?')[:24]:24} -> {target}")
    if not found:
        print("   none")
    print(f"\n{len(abilities)} abilities; {len(other)} other-id auras; {len(mismatched)} mismatched gates; "
          f"{found} table keys on another id")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
