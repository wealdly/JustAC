# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Resource waits: a priority list holds on a shared resource, and names the next press.

A lower-priority spender does not take the resource a higher-priority one is waiting on
(SpellQueue._HoldForPriority): Thunder Clap (20 rage) above Heroic Strike (15) on three
targets never got its rage while the cheaper press became affordable first. With lower ones
held, the next press on a power is its highest-priority wait (SpellQueue._OrderResourceWaits).
Also the affordable-within-one-GCD threshold. Loads the real functions from SpellQueue.lua.

Run: python tools/test_resource_waits.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("SpellQueue._continuousCost = {}")
    end = source.index("\nend\n", source.index("function SpellQueue._OrderResourceWaits(")) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellQueue, secret = {}, {}
        DISCRETE_POWER = { [4] = true }   -- combo points
        BlizzardAPI = { IsSecretValue = function(v) return rawequal(v, secret) end,
                        HasGamePick = function() return gamePick end,
                        CooldownEndsWithin = function(id, s) window = s; return cdSoon[id] end }
        gamePick, cdSoon = false, {}
        SpellQueue._OneGCD = function() return 1.5 end
        costs = {}
        C_Spell = { GetSpellPowerCost = function(id)
            if costs[id] == 'error' then error('denied') end
            return costs[id]
        end }
    """ + source[start:end])

    def order(ids, tiers, sunk, cost_table, ranks="{}"):
        lua.execute("wipe = function(t) for k in pairs(t) do t[k] = nil end end; "
                    "wipe(SpellQueue._continuousCost); wipe(SpellQueue._waitRank); costs = " + cost_table +
                    "; for id, r in pairs(" + ranks + ") do SpellQueue._waitRank[id] = r end")
        spells = lua.table(*ids)
        lua.globals().SpellQueue._OrderResourceWaits(spells, len(ids), lua.eval(tiers), lua.eval(sunk))
        return [spells[i + 1] for i in range(len(ids))]

    rage = "{[6343]={{type=1,cost=20}}, [78]={{type=1,cost=15}}, [772]={{type=1,cost=10}}, "            "[2565]={{type=1,cost=10}}, [133]={{type=0,cost=30}}, [2098]={{type=3,cost=35},{type=4,cost=1}}, "            "[999]={{type=1,cost=secret}}, [998]='error', [6603]={}}"
    res = "'resource'"
    for ids, tiers, sunk, ranks, expected, why in (
        ([78, 6343], "{}", f"{{[6343]={res},[78]={res}}}", "{[6343]=1,[78]=2}", [6343, 78],
         "Thunder Clap ranks above Heroic Strike: it is the next press on rage"),
        ([6343, 78], "{}", f"{{[6343]={res},[78]={res}}}", "{[6343]=2,[78]=1}", [78, 6343],
         "the other way round when Heroic Strike ranks higher"),
        ([78, 100, 6343], "{}", f"{{[6343]={res},[100]=true,[78]={res}}}", "{[6343]=1,[78]=2}",
         [6343, 100, 78], "a cooldown wait keeps its place between them"),
        ([772, 78, 6343], "{}", f"{{[6343]={res},[78]={res},[772]={res}}}", "{[6343]=1,[78]=2,[772]=3}",
         [6343, 78, 772], "three waits: by priority"),
        ([772, 2565], "{}", f"{{[772]={res},[2565]={res}}}", "{[772]=1,[2565]=1}", [772, 2565],
         "equal ranks keep list order"),
        ([133, 6343], "{}", f"{{[6343]={res},[133]={res}}}", "{[6343]=1,[133]=2}", [133, 6343],
         "different powers keep list order"),
        ([78, 6343], "{[6343]=2}", f"{{[6343]={res},[78]={res}}}", "{[6343]=1,[78]=2}", [78, 6343],
         "a wait in another tier is not reordered here"),
        ([78, 6343], "{}", f"{{[6343]={res},[78]=true}}", "{[6343]=1,[78]=2}", [78, 6343],
         "a held or barred wait is not a resource wait"),
        ([999, 6343], "{}", f"{{[6343]={res},[999]={res}}}", "{[6343]=1,[999]=2}", [999, 6343],
         "a secret cost stays in place"),
        ([998, 6343], "{}", f"{{[6343]={res},[998]={res}}}", "{[6343]=1,[998]=2}", [998, 6343],
         "a failed cost read stays in place"),
    ):
        got = order(ids, tiers, sunk, rage, ranks)
        assert got == expected, (why, got, expected)

    # The hold: a normal entry yields to a higher-ranked wait on the same power.
    def hold(normal, ranks, waits, sunk, wait_ranks, tiers="{}"):
        lua.execute("wipe(SpellQueue._continuousCost); wipe(SpellQueue._waitRank); costs = " + rage +
                    "; for id, r in pairs(" + wait_ranks + ") do SpellQueue._waitRank[id] = r end")
        n, w = lua.table(*normal), lua.table(*waits)
        r, sk, t = lua.table(*ranks), lua.eval(sunk), lua.eval(tiers)
        kept, count = lua.globals().SpellQueue._HoldForPriority(n, r, len(normal), w, len(waits), sk, t)
        return [n[i + 1] for i in range(kept)], [w[i + 1] for i in range(count)], sk
    for normal, ranks, waits, sunk, wait_ranks, tiers, kept, waited, why in (
        ([78], [2], [6343], f"{{[6343]={res}}}", "{[6343]=1}", "{}", [], [6343, 78],
         "Heroic Strike waits while Thunder Clap, above it, waits on rage"),
        ([78], [2], [6343], f"{{[6343]={res}}}", "{[6343]=3}", "{}", [78], [6343],
         "a lower-ranked wait holds nothing"),
        ([6603, 78], [0, 2], [6343], f"{{[6343]={res}}}", "{[6343]=1}", "{}", [6603], [6343, 78],
         "Attack has no cost: never held"),
        ([133], [5], [6343], f"{{[6343]={res}}}", "{[6343]=1}", "{}", [133], [6343],
         "a mana spell is not held by a rage wait"),
        ([78], [2], [6343], "{[6343]=true}", "{[6343]=1}", "{}", [78], [6343],
         "a cooldown or condition wait holds nothing"),
        ([78], [2], [6343], f"{{[6343]={res}}}", "{[6343]=1}", "{[6343]=2}", [78], [6343],
         "a wait outside the first tier holds nothing"),
        ([78], [2], [999], f"{{[999]={res}}}", "{[999]=1}", "{}", [78], [999],
         "an unreadable cost holds nothing"),
    ):
        got_kept, got_waits, sk = hold(normal, ranks, waits, sunk, wait_ranks, tiers)
        assert got_kept == kept and got_waits == waited, (why, got_kept, got_waits)
        for id in waited:
            if id not in waits:
                assert sk[id] == "resource", (why, "a held spender is a resource wait")
    # The reserve: a higher-ranked spender coming off cooldown within two GCDs holds a lower one
    # on the same power only when both cannot be paid (rage income unknowable: none counted).
    lua.execute("""
        power, maxPower = 0, 100
        function UnitPowerMax() return maxPower end
        function GetTime() return 100 end
        function SpellQueue._PendingGain() return nil end
        BlizzardAPI.IsUnitPowerBelow = function(_, pct) if power == nil then return nil end return power < pct end
    """)

    def reserve(setup, normal=(78,), ranks=(2,)):
        lua.execute("wipe(SpellQueue._continuousCost); wipe(SpellQueue._waitRank); wipe(SpellQueue._cooldownRank);"
                    "wipe(SpellQueue._incomeRate); costs = " + rage + "; gamePick, cdSoon, window = false, {[6343]=true}, nil;"
                    "SpellQueue._cooldownRank[6343] = 1; power = 20;" + setup)
        n, w = lua.table(*normal), lua.table(6343)
        kept, _ = lua.globals().SpellQueue._HoldForPriority(n, lua.table(*ranks), len(normal), w, 1,
                                                          lua.eval("{[6343]=true}"), lua.eval("{}"))
        return [n[i + 1] for i in range(kept)]
    assert reserve("") == [], "20 rage: Heroic Strike would leave Thunder Clap short, held"
    assert lua.globals().window == 3.0, "two GCDs of reserve"
    assert reserve("power = 35") == [78], "35 rage pays both: nothing held"
    assert reserve("cdSoon = {}") == [78], "Thunder Clap further off: nothing held"
    assert reserve("power = nil") == [78], "an unreadable threshold never holds"
    assert reserve("gamePick = true") == [78], "with a game pick the game times its own pooling"
    assert reserve("", ranks=(0,)) == [78], "a higher-priority spender is never held for a lower one"
    assert reserve("", normal=(133,)) == [133], "another power is untouched"

    # Affordable within one GCD: one threshold at cost minus the income due, rounded up to 5%.
    lua.execute("""
        wipe(SpellQueue._continuousCost); wipe(SpellQueue._incomeRate)
        costs = {[1752]={{type=3,cost=40}}, [8676]={{type=3,cost=62}}, [78]={{type=1,cost=15}},
                 [133]={{type=0,cost=30}}}
        regen, maxPower, power, asked = 10, 100, 0, nil
        function GetPowerRegenForPowerType(pt) assert(pt == 3); return regen end
        function UnitPowerMax(unit, pt) return maxPower end
        pending = {}
        function GetTime() return 100 end
        function SpellQueue._PendingGain(pt, now) assert(now == 100); return pending[pt] end
        BlizzardAPI.IsUnitPowerBelow = function(unit, pct, pt)
            assert(unit == 'player'); asked = pct
            if power == nil then return nil end
            return power < pct
        end
    """)
    within = lua.globals().SpellQueue._AffordableWithin
    for setup, sid, seconds, expected, threshold, why in (
        ("power=30", 1752, 1.0, True, 30, "40 energy, 10 per second: 30 now is enough within a second"),
        ("power=25", 1752, 1.0, False, 30, "25 is not"),
        ("power=50", 8676, 1.5, True, 50, "47 needed rounds up to the 50 step, never claims early"),
        ("power=45", 8676, 1.5, False, 50, "45 is under the rounded-up step"),
        ("power=nil", 1752, 1.0, None, 30, "an unreadable threshold is unknown"),
        ("power=0", 1752, 5.0, True, None, "income alone covers it: no threshold asked"),
        ("power=0", 78, 1.0, None, None, "rage income is unknowable: no estimate"),
        ("power=5; pending={[1]=12}", 78, 1.0, True, 5, "Charge's 12 rage on landing: 3 more is enough"),
        ("power=0; pending={[1]=9}", 78, 1.0, False, 10, "9 rage on landing leaves 6 short"),
        ("power=0; pending={[1]=20}", 78, 1.0, True, None, "a landing gain that covers the cost alone"),
        ("power=0; pending={[3]=50}", 78, 1.0, None, None, "a gain of another power does not count"),
        ("power=0", 133, 1.0, None, None, "mana is out of scope"),
        ("power=0; maxPower=secret", 1752, 1.0, None, None, "a secret maximum is unknown"),
    ):
        lua.execute("power, maxPower, asked, pending = 0, 100, nil, {};" + setup)
        got = within(sid, seconds)
        assert got == expected and lua.globals().asked == threshold, (why, got, lua.globals().asked)
    lua.execute("regen = secret; power, maxPower = 30, 100; wipe(SpellQueue._incomeRate)")
    assert within(1752, 1.0) is None, "no plain rate seen yet: unknown"
    lua.execute("regen = 10"); within(1752, 1.0)
    lua.execute("regen = secret")
    assert within(1752, 1.0) is True, "a secret rate falls back to the last plain reading"
    print("Resource waits: lower spenders hold for a higher wait on their power; waits order by priority")
    print("Affordable within: one rounded-up threshold for energy and a landing's known rage; unknowns give none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
