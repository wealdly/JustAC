# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Forever DoT/HoT refresh lead: a recast restarts the effect and loses the ticks left, so it
comes back its cast time before it ends, a global cooldown earlier still when it stacks.
Loads the real BlizzardAPI.GetPeriodicRefreshLead and checks the generated Forever data that
marks stacking auras and heals over time.

Run: python tools/test_periodic_refresh.py
"""
import re
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    plain_start = source.index("local function PlainDamageNumber(value)")
    plain_end = source.index("\nend\n", plain_start) + len("\nend\n")
    start = source.index("function BlizzardAPI.GetCastSeconds(")
    lead_at = source.index("function BlizzardAPI.GetPeriodicRefreshLead(")
    end = source.index("\nend\n", lead_at) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        secret = {}
        spells = { [348] = {castTime = 2000}, [139] = {castTime = 0}, [9] = secret, [8] = {castTime = secret} }
        gcds = {}
        BlizzardAPI = {
            GetSpellInfo = function(id) if id == 7 then error('denied') end return spells[id] end,
            GetSpellGCD = function(id) return gcds[id] end,
        }
        IsSecretValue = function(v) return rawequal(v, secret) end
        function geterrorhandler() return function() end end
    """ + source[plain_start:plain_end] + source[start:end])
    lead = lua.eval("BlizzardAPI.GetPeriodicRefreshLead")
    assert lead(348, False) == 2, "cast-time DoT: its cast time"
    assert lead(139, False) == 0, "instant HoT: back as it runs out"
    assert lead(139, True) == 1.5, "instant stacking: one unhasted GCD"
    lua.execute("gcds[348] = 1.2")
    assert abs(lead(348, True) - 3.2) < 1e-9, "stacking cast: cast time plus the measured GCD"
    for sid in (9, 8, 7, 404):
        assert lead(sid, False) == 0, (sid, "unreadable cast time counts as instant")

    defaults = (ROOT / "Data" / "Forever" / "Defaults.lua").read_text(encoding="utf-8")

    def table(name):
        m = re.search(r"^local " + name + r" = \{\n(.*?)^\}", defaults, re.M | re.S)
        assert m, name
        return {int(x) for x in re.findall(r"\[(\d+)\]", m.group(1))}
    stacking, heals = table("STACKING_AURAS"), table("PERIODIC_HEALS")
    assert 414644 in stacking and 7386 in stacking, "Lacerate and Sunder Armor stack"
    # Fire Vulnerability left the table with the Scorch line that stacked it (Fire leaves Scorch out).
    assert 22959 not in stacking, "no list stacks Fire Vulnerability"
    assert 348 not in stacking and 772 not in stacking, "Immolate and Rend do not"
    assert {139, 774, 8936} <= heals and 2061 not in heals, "Renew, Rejuvenation, Regrowth; not Flash Heal"
    assert "SpellDB.RegisterPeriodicRefresh(STACKING_AURAS, PERIODIC_HEALS)" in defaults
    print("Periodic refresh: cast-time lead, GCD more when stacking; Forever stacking and HoT data")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
