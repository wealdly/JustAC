# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The meter comparison tool reads capture lines into fights and prices the generated estimates.

Run: python tools/test_meter_compare.py
"""
import meter_compare as mc

CAPTURE = '''
"DIAGNOSTICS START session=A t=1",
"  level=plain:5",
"EVIDENCE cast session=A t=2 epoch=1 UNIT_SPELLCAST_SUCCEEDED spell=plain:172 cast=plain:x base=172",
"EVIDENCE cast session=A t=3 epoch=1 UNIT_SPELLCAST_SUCCEEDED spell=plain:686 cast=plain:y base=686",
"EVIDENCE cast session=A t=5 epoch=1 UNIT_SPELLCAST_SUCCEEDED spell=plain:686 cast=plain:z base=686",
"EVIDENCE rangedSwing session=A t=6 swing=plain:2 duration=plain:1.5 observedTarget{}",
"EVIDENCE rangedSwing session=A t=8 swing=plain:2 duration=plain:1.5 observedTarget{}",
"  signal.meter.postCombat=plain:plain:session=7 playerDamage=plain:50 plain:686:damage=plain:30:dps=plain:3 plain:75:damage=plain:20:dps=plain:2",
"  signal.meter.postCombat=plain:plain:session=7 playerDamage=plain:70 plain:686:damage=plain:30:dps=plain:3 plain:75:damage=plain:20:dps=plain:2 plain:172:damage=plain:20:dps=plain:2",
"  signal.meter.postCombat=plain:plain:unavailable:in combat",
"EVIDENCE cast session=A t=20 epoch=2 UNIT_SPELLCAST_SUCCEEDED spell=plain:686 cast=plain:w base=686",
"  signal.meter.postCombat=plain:plain:session=8 playerDamage=plain:0",
"  signal.meter.postCombat=plain:plain:session=9 playerDamage=plain:14 plain:686:damage=plain:14:dps=plain:2",
"DIAGNOSTICS START session=B t=30",
"  signal.meter.postCombat=plain:plain:session=9 playerDamage=plain:5 plain:686:damage=plain:5:dps=plain:1",
"  level=plain:6",
'''.splitlines()

ESTIMATES = {
    172: [0, 0, 4, 9, 0, 6, 1, 40, 0, 0.8, 12],   # Corruption: no hit, 40 over time
    686: [13, 0.2, 1, 5, 0.486, 6],               # Shadow Bolt: hit only, capped at level 5
    348: [8, 0.7, 1, 5, 0.2, 3, 1, 15, 0, 0.65, 15],
}
NAMES = {172: "Corruption", 686: "Shadow Bolt"}


def main():
    fights = mc.parse_capture(CAPTURE)
    assert len(fights) == 3, "reports of one fight merge; a zero-damage report is no fight"
    first, second, third = fights
    assert first["spells"] == {686: 30, 75: 20, 172: 20}, "the latest report of a fight wins"
    assert first["casts"] == {172: 1, 686: 2} and first["seconds"] == 10, (first["casts"], first["seconds"])
    assert second["casts"] == {686: 1}, "casts start again after each fight"
    assert third["capture"] == "B" and third["level"] == 6, "a level read later fills that capture's fights"

    assert mc.listed_damage(ESTIMATES[172], 5) == (0, 40), "damage over time only"
    hit, over_time = mc.listed_damage(ESTIMATES[686], 9)
    assert abs(hit - 13.8) < 1e-9 and over_time == 0, "per-level gain stops at the spell's maximum level"
    hit, over_time = mc.listed_damage(ESTIMATES[348], 1)
    assert (hit, over_time) == (8, 15), "hit plus damage over time"

    rows = {row[0]: row for row in mc.compare(fights, ESTIMATES, NAMES)}
    name, casts, count, measured, listed = rows["Shadow Bolt"]
    assert (casts, count) == (3, 2) and measured == (30 + 14) / 3, "a fight with no casts seen is left out"
    assert rows["Corruption"][3:] == (20, 40), "measured and listed per cast"
    attacks = mc.auto_attacks(fights)
    assert attacks["rangedSwing"] == (2, 10, 1.5, 10 / 1.5), attacks

    truncated = [dict(first, truncated=True)]
    assert mc.compare(truncated, ESTIMATES, NAMES) == [], "a report cut short is not compared"
    print("Meter compare: fights, casts, listed damage and auto attacks read correctly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
