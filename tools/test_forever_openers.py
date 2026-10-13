# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real Forever entries and queue assembly, with controlled readiness and range.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

from test_gate_groups import extract

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local RI = {}
function LibStub() return RI end
function RI.RegisterForever(data, chains)
    classes, rankBases = data, {}
    for base, chain in pairs(chains) do
        for _, id in ipairs(chain) do rankBases[id] = base end
    end
end
function RI.RankBase(id) return rankBases[id] or id end
RotationImport = RI
function wipe(t) for k in pairs(t) do t[k] = nil end end
SpellQueue = { IsSpellBlacklisted = function(id) return blacklisted[id] == true end }
SpellDB = { GetSpecKey = function() return specKey end }
BlizzardAPI = {
    IsForever = function() return forever end,
    HasGamePick = function() return not forever end,
    AbilityInRange = function(id) return ranges[RI.RankBase(id)] end,
    IsSpellReady = function(id) return not cooldown[RI.RankBase(id)] end,
    IsSpellUsable = function(id)
        local base = RI.RankBase(id)
        return not unusable[base] and not starved[base], starved[base] == true
    end,
    GetDisplaySpellID = function(id) return id end,
    IsItemSpell = function() return false end,
    RunningAutoSwing = function() end,
    IsSpellLoCLocked = function(id) return locked[RI.RankBase(id)] == true end,
    IsSpellProcced = function(id) return procs[RI.RankBase(id)] == true end,
    GetClassResourcePoints = function() return points, 5, "combo_points" end,
}
function UnitExists() return targetExists end
function UnitCanAttack() return hostile end
function NoteManaStarved() end
function ClaimSpellID(id, added) added[id] = true; return id end
function PassesRotationFilters(id) return not filtered[RotationImport.RankBase(id)] end
function HeldByUserHold() return false end
function HasUserHold(id) return holds[id] == true end
function IsSpenderSpell(id) return specKey == "ROGUE_F" end
function IsConfirmedOutOfRange(id) return BlizzardAPI.AbilityInRange(id) == false end
function SimcBuffWindowActive() return false end
function GateInPickWindows() return false end
function HasPositiveBuffGate() return false end
function ProcPriorityEnabled() return true end
function SimcNegativeBuffBlocks() return false end
function DotGateBlocks() return false end
function SimcGateBlocks(gates)
    for _, g in ipairs(gates or {}) do
        if g.t == "stack" and stacks < g.n then return true end
        if g.t == "cd" then return true end
    end
    return false
end
function RotationImport.GetEntry(id)
    local base = RotationImport.RankBase(id)
    for i, e in ipairs(entries) do
        if e.id == base then return {rank = i, gates = e.gates} end
    end
end
function rankOf(id, rec) return rec and rec.rank or 999 end
function AppendRankedBucket(bucket, ranks, count, queue, size, maxIcons)
    local order = {}
    for i = 1, count do order[i] = i end
    table.sort(order, function(a, b)
        if ranks[a] == ranks[b] then return a < b end
        return ranks[a] < ranks[b]
    end)
    for _, i in ipairs(order) do
        if size == maxIcons then break end
        size = size + 1; queue[size] = bucket[i]
    end
    return size
end
function Reset()
    forever, specKey, stacks = true, "SHAMAN_F", 0
    targetExists, hostile = true, true
    ranges, cooldown, unusable, starved, locked, filtered, blacklisted, procs =
        {[403] = true, [8042] = true}, {}, {}, {}, {}, {}, {}, {}
    SpellQueue._rotationIsCustom = false
    points, holds = nil, {}
    entries = classes.SHAMAN_F.enhancement.st
    proccedSpells, normalSpells, proccedRank, normalRank = {}, {}, {}, {}
    cooldownSpells, sunkSet, wastedSet, formEntryBase, pinnedAlwaysShow = {}, {}, {}, {}, {}
    b = {
        profile = {}, blacklist = {}, addedSpellIDs = {}, recommendedSpells = {},
        spellCount = 0, maxIcons = 4, effectiveBypassProcs = false,
        contextOrder = "simc", sinkCooldowns = true, inCombat = false,
    }
    pool = {8042, 403}
end
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("local function IsForeverPullSpell(")
    end = source.index("\n--- Largest icon count", start)
    helpers = "\n".join(extract(name, source) for name in (
        "ResourceGateHolds", "GateVerdict", "SimcResourceGateBlocks"
    ))
    lua.execute("resourceGateCtx = { resourceOnly = true }\n" + helpers + """
        local originalBlocks = SimcGateBlocks
        function SimcGateBlocks(gates, count, name, maximum, skipResource)
            return (not skipResource and SimcResourceGateBlocks(gates, count, name, maximum))
                or originalBlocks(gates)
        end
    """ + source[start:end] + """
        function Build()
            CategorizeAndAssembleRotation(pool, b)
            return b.recommendedSpells
        end
    """)
    cases = [
        ("", [403, 8042], "OOC bolt leads without Maelstrom stacks"),
        ("pool = {10414, 15208}", [15208, 10414], "highest-rank entries use the same opener"),
        ("b.inCombat = true", [8042, 403], "combat retains the five-stack gate"),
        ("b.inCombat = true; stacks = 5", [403, 8042], "combat instant bolt keeps imported rank"),
        ("forever = false", [8042, 403], "retail has no opener exception"),
        ("SpellQueue._rotationIsCustom = true", [8042, 403], "custom list retains combat gates"),
        ("b.contextOrder = 'off'", [8042, 403], "exact source order unchanged"),
        ("b.contextOrder = 'ac'", [8042, 403], "non-theorycraft ordering unchanged"),
        ("ranges[403] = false", [8042, 403], "out-of-range bolt never promoted"),
        ("ranges[403] = nil", [8042, 403], "unknown range never promotes a pull"),
        ("cooldown[403] = true", [8042, 403], "cooldown prevents promotion"),
        ("unusable[403] = true", [8042, 403], "unusable bolt never leads"),
        ("starved[403] = true", [8042, 403], "unaffordable bolt never leads"),
        ("locked[403] = true", [8042, 403], "school lockout prevents promotion"),
        ("filtered[403] = true", [8042], "queue filters still apply"),
        ("blacklisted[403] = true", [8042], "blacklist still applies"),
        ("hostile = false", [8042, 403], "friendly targets have no pull override"),
        ("targetExists = false; ranges[403] = nil", [403, 8042], "no target still previews the pull"),
        ("targetExists = false; hostile = false; ranges[403] = nil", [403, 8042], "absent target needs no hostility verdict"),
        ("targetExists = false; ranges[403] = nil; cooldown[403] = true", [8042, 403], "no-target preview still requires readiness"),
        ("targetExists = false; ranges[403] = nil; starved[403] = true", [8042, 403], "no-target preview still requires affordability"),
        ("targetExists = false; ranges[403] = nil; b.inCombat = true", [8042, 403], "target loss in combat does not waive stacks"),
        ("targetExists = false; ranges[403] = nil; SpellQueue._rotationIsCustom = true", [8042, 403], "no-target custom list unchanged"),
        ("targetExists = false; ranges[403] = nil; forever = false", [8042, 403], "no-target retail unchanged"),
        ("pool = {8042}", [8042], "never injects an omitted or unknown bolt"),
        ("procs[8042] = true", [8042, 403], "real proc priority retained"),
        ("b.maxIcons = 1", [403], "opener works with one visible icon"),
        ("b.sinkCooldowns = false", [403, 8042], "opener preference independent of sinking"),
        ("""entries = {
            {id=8042, gates={}},
            {id=403, gates={{t='stack',id=408505,op='>=',n=5},{t='cd',id=17364}}}
        }""", [8042, 403], "additional requirements are not waived"),
    ]
    for cls in ("DRUID", "ROGUE", "WARRIOR", "HUNTER", "MAGE", "PRIEST", "PALADIN", "WARLOCK"):
        cases.append((f"specKey = '{cls}_F'", [8042, 403], f"{cls} receives no blanket override"))
    rogue = """
        specKey = "ROGUE_F"; b.inCombat = true; pool = {2098,1752}
        entries = {{id=2098,gates={{t="resource",res="combo_points",op=">=",n=5}}},{id=1752}}
        starved[2098], starved[1752] = true, true
    """
    cases.extend([
        (rogue + "points=0", [1752, 2098], "builder leads at zero points even while energy-starved"),
        (rogue + "points=2", [1752, 2098], "unmet finisher threshold trails an energy-starved builder"),
        (rogue + "points=5", [2098, 1752], "met finisher requirement preserves source order"),
        (rogue + "points=nil", [2098, 1752], "unknown points never infer a missing prerequisite"),
        (rogue + "points=0; forever=false", [2098, 1752], "retail sunk ordering unchanged"),
        (rogue + "points=0; b.sinkCooldowns=false", [2098, 1752], "unavailable-last opt-out unchanged"),
        (rogue + "points=0; holds[2098]=true", [2098, 1752], "explicit hold replaces imported threshold"),
        (rogue + """points=0; entries[1].gates={{t="any",g={
            {t="resource",res="combo_points",op=">=",n=5},{t="buff",id=5171}}}}""",
         [2098, 1752], "unknown OR alternative prevents prerequisite demotion"),
        (rogue + """points=0; entries[1].gates={{t="all",g={
            {t="resource",res="combo_points",op=">=",n=5},{t="buff",id=5171}}}}""",
         [1752, 2098], "confirmed missing AND prerequisite demotes the finisher"),
        (rogue + "points=0; starved[1752]=nil", [1752, 2098], "affordable builder still leads"),
    ])
    for setup, expected, description in cases:
        lua.execute("Reset(); " + setup)
        actual = list(lua.globals().Build().values())
        assert actual == expected, f"{description}: got {actual}, expected {expected}"
    lua.execute("Reset(); " + rogue + "points=5")
    assert list(lua.globals().Build().values()) == [2098, 1752]
    lua.execute("points=0; b.addedSpellIDs={}; b.recommendedSpells={}")
    assert list(lua.globals().Build().values()) == [1752, 2098], "spending points must immediately surface the builder"
    lua.execute("Reset()")
    bolt = next(e for e in lua.globals().entries.values() if e.id == 403)
    assert len(bolt.gates) == 1 and bolt.gates[1].t == "stack", "imported stack gates were not mutated"
    print(f"Forever openers and prerequisites: {len(cases)} cases plus spend transition passed")


if __name__ == "__main__":
    main()
