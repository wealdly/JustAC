# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Compare real damage with the queue's Forever damage estimates. Read-only.

Reads the diagnostic captures in a Forever JustAC SavedVariables file. For each fight the built-in
damage meter reported after combat, it divides each spell's damage by the casts seen since the
previous fight, and compares that with the generated estimate (hit plus full damage over time).

What the numbers mean:
  * Listed damage assumes no spell power, talents, crits or misses, and every tick landing.
  * Measured damage includes misses, resists, crits and ticks lost when the target died.
  * Casts are grouped between meter reports, so a fight the meter did not report adds its casts to
    the next one and lowers that fight's measured figure. Prefer several fights per spell.
  * Captures hold only the latest sessions: flush them with /reload before reading.

Run: python tools/meter_compare.py [path to JustAC.lua] [--min-casts N]
"""
import argparse
import collections
import glob
import os
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

RANGED_ATTACKS = {75, 5019}   # Auto Shot, and a wand's Shoot
MELEE_ATTACK = 6603

START = re.compile(r"DIAGNOSTICS START session=(\S+)")
LEVEL = re.compile(r"level=plain:(\d+)")
CAST = re.compile(r"EVIDENCE cast .*UNIT_SPELLCAST_SUCCEEDED spell=plain:(\d+)")
SWING = re.compile(r"EVIDENCE (rangedSwing|mainHandSwing) .*?duration=plain:([\d.]+)")
METER = re.compile(r"signal\.meter\.postCombat=plain:plain:session=(\d+) playerDamage=plain:(\d+)(.*)")
METER_SPELL = re.compile(r"plain:(\d+):damage=plain:(\d+):dps=plain:([\d.]+)")


def parse_capture(lines):
    """The fights in capture lines: level, casts, swings, spell damage and length in seconds."""
    fights, by_key = [], {}
    capture, level = None, None
    casts, swings = collections.Counter(), collections.defaultdict(list)
    for raw in lines:
        line = raw.strip().rstrip(",").strip('"').strip()
        match = START.match(line)
        if match:
            capture, level = match.group(1), None
            casts, swings = collections.Counter(), collections.defaultdict(list)
            continue
        match = LEVEL.match(line)
        if match:
            level = int(match.group(1))
            for fight in fights:
                if fight["capture"] == capture and fight["level"] is None:
                    fight["level"] = level
            continue
        match = CAST.search(line)
        if match:
            casts[int(match.group(1))] += 1
            continue
        match = SWING.search(line)
        if match:
            swings[match.group(1)].append(float(match.group(2)))
            continue
        match = METER.match(line)
        if not match or capture is None or int(match.group(2)) <= 0:
            continue
        rows = METER_SPELL.findall(match.group(3))
        spells = {int(spell): int(damage) for spell, damage, _ in rows}
        lengths = [int(damage) / float(dps) for _, damage, dps in rows if float(dps) > 0]
        seconds = statistics.median(lengths) if lengths else None
        key = (capture, match.group(1))
        if key in by_key:   # a later report of the same fight: ticks may have landed since
            by_key[key].update(spells=spells, seconds=seconds, truncated="truncated=" in line)
            continue
        fight = {"capture": capture, "level": level, "casts": dict(casts), "swings": dict(swings),
                 "spells": spells, "seconds": seconds, "truncated": "truncated=" in line}
        by_key[key] = fight
        fights.append(fight)
        casts, swings = collections.Counter(), collections.defaultdict(list)
    return fights


def listed_damage(row, level):
    """Hit and full damage over time of one estimate row at a level, with no spell power."""
    def scaled(base, per_level):
        at = max(row[2], level)
        if row[3] > 0:
            at = min(at, row[3])
        return base + (at - row[2]) * per_level
    hit = scaled(row[0], row[1]) if row[0] else 0
    over_time = 0
    if len(row) > 7 and row[6] and row[7] is not None:
        over_time = scaled(row[7], row[8] or 0)
    return hit, over_time


def compare(fights, estimates, names):
    """Measured against listed damage per spell name: [(name, casts, fights, measured, listed)]."""
    totals = collections.defaultdict(lambda: [0, 0, 0.0, set()])
    for index, fight in enumerate(fights):
        if fight["level"] is None or fight["truncated"]:
            continue
        for spell, damage in fight["spells"].items():
            casts = fight["casts"].get(spell, 0)
            if not casts or spell not in estimates:
                continue
            hit, over_time = listed_damage(estimates[spell], fight["level"])
            row = totals[names.get(spell, str(spell))]
            row[0] += casts
            row[1] += damage
            row[2] += (hit + over_time) * casts
            row[3].add(index)
    return sorted(((name, r[0], len(r[3]), r[1] / r[0], r[2] / r[0]) for name, r in totals.items()),
                  key=lambda r: r[0])


def auto_attacks(fights):
    """Measured DPS of ranged and melee auto attacks: {kind: (shots, per shot, speed, dps)}."""
    out = {}
    for kind, ids in (("rangedSwing", RANGED_ATTACKS), ("mainHandSwing", {MELEE_ATTACK})):
        damage, speeds = 0, []
        for fight in fights:
            seen = fight["swings"].get(kind, [])
            done = sum(fight["spells"].get(spell, 0) for spell in ids)
            if seen and done:
                damage += done
                speeds.extend(seen)
        if speeds:
            speed = statistics.median(speeds)
            out[kind] = (len(speeds), damage / len(speeds), speed, damage / len(speeds) / speed)
    return out


def load_estimates():
    """The generated damage estimate rows from Data/Forever/Rotations.lua, by spell id."""
    from lupa import LuaRuntime  # type: ignore[import-not-found]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        local module = { RegisterForever = function(_, _, _, _, estimates) ESTIMATES = estimates end }
        function LibStub() return module end
    """)
    with open(os.path.join(ROOT, "Data", "Forever", "Rotations.lua"), encoding="utf-8") as source:
        lua.execute(source.read())
    return {int(spell): list(row.values()) for spell, row in lua.globals().ESTIMATES.items()}


def default_capture():
    """The most recently saved Forever capture, or None."""
    pattern = "C:/Blizzard/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/JustAC.lua"
    found = glob.glob(pattern)
    return max(found, key=os.path.getmtime) if found else None


def main():
    parser = argparse.ArgumentParser(description="Compare meter damage with Forever damage estimates.")
    parser.add_argument("capture", nargs="?", default=default_capture(), help="path to a Forever JustAC.lua")
    parser.add_argument("--min-casts", type=int, default=5, help="hide spells with fewer casts (default 5)")
    args = parser.parse_args()
    if not args.capture or not os.path.exists(args.capture):
        sys.exit("no capture found: pass the path to a Forever SavedVariables/JustAC.lua")

    with open(args.capture, encoding="utf-8", errors="replace") as capture:
        fights = parse_capture(capture)
    if not fights:
        sys.exit("no meter reports in this capture: run a diagnostic session, then /reload")
    import check_forever_apl as cfa
    names = {int(row["ID"]): row["Name_lang"] for row in cfa.rows("SpellName")}

    levels = sorted({fight["level"] for fight in fights if fight["level"] is not None})
    lengths = [fight["seconds"] for fight in fights if fight["seconds"]]
    print(f"{len(fights)} fights, levels {levels[0]}-{levels[-1]}" if levels else f"{len(fights)} fights")
    if lengths:
        print(f"fight length: median {statistics.median(lengths):.1f}s, "
              f"range {min(lengths):.1f}-{max(lengths):.1f}s")
    damage = collections.Counter()
    for fight in fights:
        damage.update(fight["spells"])
    total = sum(damage.values())
    print("damage share: " + ", ".join(f"{names.get(spell, spell)} {100 * amount / total:.0f}%"
                                       for spell, amount in damage.most_common(8)))

    print(f"\n{'spell':24} {'casts':>5} {'fights':>6} {'measured':>9} {'listed':>8} {'ratio':>6}")
    for name, casts, count, measured, listed in compare(fights, load_estimates(), names):
        if casts >= args.min_casts:
            ratio = measured / listed if listed else 0
            print(f"{name[:24]:24} {casts:5d} {count:6d} {measured:9.1f} {listed:8.1f} {ratio:6.2f}")
    for kind, (shots, per_shot, speed, dps) in auto_attacks(fights).items():
        label = "ranged auto attack" if kind == "rangedSwing" else "melee auto attack"
        print(f"\n{label}: {shots} swings, {per_shot:.1f} per swing, {speed:.2f}s speed, {dps:.1f} DPS measured")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
