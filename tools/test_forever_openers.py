# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real Forever entries and queue assembly, with controlled readiness and range.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

from test_gate_groups import extract

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = r"""
local RI = {}
function LibStub(name)
    if name == "JustAC-SpellDB" then return SpellDB end
    return RI
end
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
SpellQueue.WAIT_SENTINEL = -999999999
SpellDB = { GetSpecKey = function() return specKey end }
FOREVER_REAR_ATTACKS = {}
function SpellDB.RegisterCategories(t) FOREVER_REAR_ATTACKS = t.foreverRear end
function SpellDB.IsForever() return forever end
function StaticLookup(t, id) return t[RI.RankBase(id)] end
function IsStealthed() return stealthed end
function IsPlayerSpell(id) return talents[id] == true end
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
    GetClassResourcePoints = function()
        resourceReads = resourceReads + 1
        return points, maximum, resourceName
    end,
    IsSecretValue = function(value) return value == secret end,
    IsPrimaryPowerCapped = function() return capped end,
    SafeUnitIsUnit = function() return targetingMe end,
    GetActionBarUsability = function() return true, false end,
    IsBuffWindowActive = function(id) return buffs[id] == true end,
}
function UnitExists() return targetExists end
function UnitCanAttack() return hostile end
function UnitIsDeadOrGhost() return targetDead end
function NoteManaStarved() end
function ClaimSpellID(id, added) added[id] = true; return id end
function PassesRotationFilters(id) return not filtered[RotationImport.RankBase(id)] end
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
    targetDead = false
    ranges, cooldown, unusable, starved, locked, filtered, blacklisted, procs =
        {[403] = true, [8042] = true}, {}, {}, {}, {}, {}, {}, {}
    SpellQueue._rotationIsCustom = false
    points = nil
    maximum, resourceName, resourceReads = 5, "combo_points", 0
    capped, minimum, costAura, hasCostAura = false, 1, 0, false
    stealthed, targetingMe, talents, buffs = false, false, {}, {}
    secret = {}
    resourcePowerTypes = {combo_points=4, holy_power=9, chi=12, soul_shard=7,
        runes=5, essence=19, arcane_charges=16}
    C_Spell = {GetSpellPowerCost=function(id)
        if id == 2098 then return {{type=resourcePowerTypes[resourceName], minCost=minimum,
            cost=5, requiredAuraID=costAura, hasRequiredAura=hasCostAura}} end
        return {}
    end}
    maxChargeGated, holdPoints, holdPctVal, holdPctType = {}, {}, {}, {}
    entries = classes.SHAMAN_F.enhancement.st
    proccedSpells, normalSpells, proccedRank, normalRank = {}, {}, {}, {}
    cooldownSpells, sunkSet, unavailableTier, formEntryBase, pinnedAlwaysShow = {}, {}, {}, {}, {}
    b = {
        profile = {}, blacklist = {}, addedSpellIDs = {}, recommendedSpells = {},
        spellCount = 0, maxIcons = 4, effectiveBypassProcs = false,
        contextOrder = "simc", sinkCooldowns = true, inCombat = false, ctxPointCap = nil,
    }
    finisher = {[2098] = true}
    pool = {8042, 403}
end
"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Data" / "SpellCategories.lua").read_text(encoding="utf-8"))
    db_source = (ROOT / "SpellDB.lua").read_text(encoding="utf-8")
    start_db = db_source.index("function SpellDB.GetForeverRearRequirement(")
    end_db = db_source.index("\nend", start_db) + len("\nend")
    lua.execute(db_source[start_db:end_db])
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("local function IsForeverPullSpell(")
    end = source.index("\n--- Largest icon count", start)
    helpers = "\n".join(extract(name, source) for name in (
        "HeldByUserHold", "HasUserHold", "ResourceGateHolds", "MissingMinimumResource",
        "IsBarGreyedOut", "IsRearAttackBlocked"
    ))
    lua.execute(helpers + """
        local originalBlocks = SimcGateBlocks
        function SimcGateBlocks(gates, count, name, maximum, skipResource, pointCap)
            local blocked, short = false, false
            if not skipResource and count ~= nil then
                for _, g in ipairs(gates or {}) do
                    local atLeast = not g.deficit and (g.op == ">=" or g.op == ">")
                    if g.t == "resource" and g.res == name then
                        local holds
                        local need = g.op == ">" and g.n + 1 or g.n
                        if atLeast and pointCap and pointCap < need then
                            if pointCap > 0 then holds = count >= pointCap end
                        else
                            holds = ResourceGateHolds(g, count, maximum)
                        end
                        if holds == false then blocked, short = true, short or atLeast end
                    end
                end
            end
            return blocked or originalBlocks(gates), short
        end
        function PointGateCap(id, resource, cap)
            if cap and resource ~= nil and not BlizzardAPI.HasGamePick()
                and finisher[RotationImport.RankBase(id)] == true then return cap end
            return nil
        end
    """ + source[start:end] + """
        function Build()
            CategorizeAndAssembleRotation(pool, b)
            return b.recommendedSpells
        end
    """)
    wait_start = source.index("function SpellQueue._StageForeverWait(")
    wait_end = source.index("\nfunction SpellQueue._StageFinalize(", wait_start)
    lua.execute(source[wait_start:wait_end])
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
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true""",
         [1752, 53], "detected rear attack sinks behind the usable builder"),
        ("""pool={11281,1752}; entries={{id=53},{id=1752}}; targetingMe=true""",
         [1752, 11281], "higher Backstab ranks share the rear requirement"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; stealthed=true""",
         [53, 1752], "stealth opener keeps priority"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=false""",
         [53, 1752], "tank-held target keeps rear attack priority"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=nil""",
         [53, 1752], "unknown target-of-target fails open"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; stealthed=nil""",
         [53, 1752], "unknown stealth state fails open"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; stealthed=secret""",
         [53, 1752], "secret stealth state fails open"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; forever=false""",
         [53, 1752], "retail rear attacks unchanged"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; capped=true""",
         [1752, 53], "full-energy promotion cannot bypass rear gate"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; procs[53]=true""",
         [1752, 53], "proc promotion cannot bypass rear gate"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; starved[1752]=true""",
         [1752, 53], "blocked rear attack trails an energy-starved builder"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true; b.sinkCooldowns=false""",
         [53, 1752], "unavailable-last opt-out retains source order"),
        ("""pool={9830,1082}; entries={{id=5221},{id=1082}}; targetingMe=true""",
         [1082, 9830], "Shred ranks sink behind Claw"),
        ("""pool={5221,1082}; entries={{id=5221},{id=1082}}; targetingMe=true; buffs[1213171]=true""",
         [5221, 1082], "detected Shred set bonus waives the rear gate"),
        ("""pool={703,1752}; entries={{id=703},{id=1752}}; targetingMe=true; talents[14082]=true""",
         [703, 1752], "Dirty Deeds waives Garrote rear gate"),
        (rogue + "points=0", [1752, 2098], "builder leads at zero points even while energy-starved"),
        (rogue + "points=2", [1752, 2098], "imported five-point preference waits for the builder"),
        (rogue + "points=2; b.ctxPointCap=0", [2098, 1752], "dying target lowers the preference to the minimum"),
        (rogue + "points=0; b.ctxPointCap=0", [1752, 2098], "dying target still requires the actual minimum"),
        (rogue + "points=2; b.ctxPointCap=3", [1752, 2098], "normal mob waits for three points"),
        (rogue + "points=3; b.ctxPointCap=3", [2098, 1752], "normal mob finisher at three points"),
        (rogue + "points=2; b.ctxPointCap=2", [2098, 1752], "wounded normal mob finisher at two points"),
        (rogue + "points=4; b.ctxPointCap=3; entries[1].gates[1].op='>'; entries[1].gates[1].n=4",
         [2098, 1752], "strict gate above the cap uses the cap"),
        (rogue + "points=2; b.ctxPointCap=3; entries[1].gates[1].n=2", [2098, 1752], "cap never raises a lower source target"),
        (rogue + "points=2; b.ctxPointCap=0; forever=false", [1752, 2098], "retail keeps its preference on a dying target"),
        (rogue + "points=2; b.ctxPointCap=0; finisher[2098]=nil", [1752, 2098], "non-damage finishers keep their preference"),
        (rogue + "points=2; b.ctxPointCap=0; entries[1].gates[2]={t='stack',id=1,op='>=',n=1}",
         [2098, 1752], "other blocking gates stay blocking without a points shortfall"),
        (rogue + "points=5", [2098, 1752], "met finisher requirement preserves source order"),
        (rogue + "points=nil", [2098, 1752], "unknown points never infer a missing prerequisite"),
        (rogue + "points=0; forever=false", [1752, 2098], "retail tail shares prerequisite ordering"),
        (rogue + "points=0; b.sinkCooldowns=false", [2098, 1752], "unavailable-last opt-out unchanged"),
        (rogue + "points=2; holdPoints[2098]=2", [2098, 1752], "satisfied explicit hold replaces imported threshold"),
        (rogue + "points=0; holdPoints[2098]=2", [1752, 2098], "unmet explicit points hold is a prerequisite"),
        (rogue + "points=0; holdPoints[2098]=2; b.contextOrder='ac'", [1752, 2098], "points hold works without theorycraft ordering"),
        (rogue + "points=0; holdPoints[2098]=2; b.contextOrder='off'", [2098, 1752], "points hold retains exact source order"),
        (rogue + "points=0; holdPoints[2098]=2; entries[1].gates=nil; SpellQueue._rotationIsCustom=true",
         [1752, 2098], "custom list without imported gates honors point prerequisites"),
        (rogue + "points=0; b.spellCount=1; b.recommendedSpells={999}", [999, 1752, 2098],
         "existing primary slot stays ahead of reordered unavailable tail"),
        (rogue + """points=0; entries[1].gates={{t="any",g={
            {t="resource",res="combo_points",op=">=",n=5},{t="buff",id=5171}}}}""",
         [1752, 2098], "actual cost applies independently of imported OR preferences"),
        (rogue + """points=0; entries[1].gates={{t="all",g={
            {t="resource",res="combo_points",op=">=",n=5},{t="buff",id=5171}}}}""",
         [1752, 2098], "confirmed missing AND prerequisite demotes the finisher"),
        (rogue + "points=0; starved[1752]=nil", [1752, 2098], "affordable builder still leads"),
        (rogue + "points=0; entries[1].gates={{t='resource',res='combo_points',op='<=',n=1}}",
         [1752, 2098], "actual minimum still applies despite imported upper bound"),
        (rogue + "points=5; entries[1].gates={{t='resource',res='combo_points',op='<=',n=1}}",
         [2098, 1752], "imported upper bound is not a casting prerequisite"),
        (rogue + "points=0; entries[1].gates={{t='resource',res='combo_points',op='<=',n=1,deficit=true}}",
         [1752, 2098], "deficit prerequisite uses current maximum"),
        (rogue + "points=0; maximum=nil; entries[1].gates={{t='resource',res='combo_points',op='<=',n=1,deficit=true}}",
         [1752, 2098], "known minimum does not require a maximum read"),
        (rogue + "points=0; entries[1].gates[1].res='chi'",
         [1752, 2098], "actual cost uses the player's resource rather than imported token"),
        (rogue + "points=0; ranges[1752]=false",
         [2098, 1752], "out-of-range builder trails a missing-resource finisher"),
        (rogue + "points=0; starved[2098]=nil; procs[2098]=true",
         [1752, 2098], "proc cannot bypass a confirmed actual minimum"),
        (rogue + "points=0; starved[2098]=nil; minimum=0; procs[2098]=true",
         [2098, 1752], "free proc with zero minimum remains usable"),
        (rogue + "points=0; minimum=nil; entries[1].gates=nil", [2098, 1752], "missing minimum remains unknown"),
        (rogue + "points=0; minimum=nil", [1752, 2098], "imported points gate still applies without a minimum"),
        (rogue + "points=0; costAura=123; hasCostAura=false; entries[1].gates=nil",
         [2098, 1752], "inactive conditional cost is ignored"),
        (rogue + "points=0; costAura=123; hasCostAura=true",
         [1752, 2098], "active conditional cost applies"),
        (rogue + "points=0; b.inCombat=false; capped=true; starved[2098]=nil; starved[1752]=nil; unusable[2098]=true",
         [1752, 2098], "precombat capped energy cannot promote a zero-point finisher"),
        (rogue + "points=2; starved[2098]=nil; starved[1752]=true",
         [1752, 2098], "imported preference keeps a short finisher behind the energy-starved builder"),
        (rogue + "points=2; starved[2098]=nil; starved[1752]=true; b.ctxPointCap=0",
         [2098, 1752], "affordable two-point finisher leads on a dying target"),
        (rogue + "points=2; b.contextOrder='ac'",
         [2098, 1752], "actual minimum applies outside theorycraft ordering"),
        (rogue + "points=nil; unusable[2098]=true; starved[2098]=nil",
         [1752, 2098], "unknown count uses confirmed structural unusability before energy wait"),
        (rogue + "points=nil; unusable[2098]=true; starved[2098]=nil; forever=false",
         [1752, 2098], "retail unavailable tail shares usability fallback"),
        (rogue + "points=nil; starved[2098]=nil",
         [2098, 1752], "usable consumer leads without an exact count"),
        (rogue + "points=nil; C_Spell=nil",
         [2098, 1752], "unknown counts and minimums retain priority order"),
        (rogue + "points=2; forever=false; starved[2098]=nil; starved[1752]=nil",
         [1752, 2098], "retail retains its imported five-point preference"),
    ])
    for rear, builder in ((703, 1752), (6785, 1082), (8676, 1752), (9005, 1082)):
        cases.append(("pool={%d,%d}; entries={{id=%d},{id=%d}}; targetingMe=true" % (rear, builder, rear, builder),
                      [builder, rear], f"rear-required spell {rear} shares the gate"))
    for resource in ("combo_points", "holy_power", "chi", "soul_shard", "runes", "essence", "arcane_charges"):
        for retail in (False, True):
            cases.append((rogue + f"""points=0; resourceName='{resource}';
                entries[1].gates[1].res=resourceName; forever={str(not retail).lower()}""",
                [1752, 2098], f"{resource} prerequisite shares logic, retail={retail}"))
    cases.append((rogue + """points=0.5; resourceName='soul_shard';
        entries[1].gates[1].res=resourceName; entries[1].gates[1].n=1""",
        [1752, 2098], "fractional shards retain exact prerequisite comparisons"))
    for setup, expected, description in cases:
        lua.execute("Reset(); " + setup)
        actual = list(lua.globals().Build().values())
        assert actual == expected, f"{description}: got {actual}, expected {expected}"
        assert lua.globals().resourceReads <= 1, f"{description}: duplicate class-resource read"
    wait = lua.globals().SpellQueue.WAIT_SENTINEL
    wait_cases = [
        (rogue + "points=0", [wait, 1752, 2098], "all-starved queue shows WAIT before missing-point finisher"),
        (rogue + "points=2; b.ctxPointCap=2", [wait, 2098, 1752], "eligible finisher still waits for energy"),
        (rogue + "points=0; ranges[1752]=false; ranges[2098]=false", [wait, 2098, 1752], "all-out-of-range queue shows WAIT"),
        (rogue + "points=0; b.inCombat=false", [wait, 1752, 2098], "live OOC target shows WAIT"),
        (rogue + "points=0; b.inCombat=false; targetExists=false", [1752, 2098], "no-target OOC preview unchanged"),
        (rogue + "points=0; b.inCombat=false; hostile=false", [1752, 2098], "friendly OOC target unchanged"),
        (rogue + "points=0; b.inCombat=false; targetDead=true", [1752, 2098], "dead OOC target unchanged"),
        (rogue + "points=0; b.inCombat=false; targetDead=secret", [1752, 2098], "unknown alive status does not show OOC WAIT"),
        (rogue + "points=0; forever=false", [1752, 2098], "retail does not gain synthetic WAIT"),
        (rogue + "points=0; b.contextOrder='off'", [2098, 1752], "exact source order unchanged"),
        (rogue + "points=0; b.sinkCooldowns=false", [2098, 1752], "unavailable-last opt-out unchanged"),
        (rogue + "points=0; starved[1752]=nil", [1752, 2098], "usable builder removes WAIT"),
        (rogue + """points=0; pool[3]=2764; ranges[1752]=false;
            ranges[2098]=false; ranges[2764]=true""",
         [2764, 2098, 1752], "unranked Throw at range leads sunk melee instead of WAIT"),
        (rogue + """points=0; pool[3]=2764; starved={}; capped=true;
            ranges[1752]=false; ranges[2098]=false; ranges[2764]=true; b.inCombat=true""",
         [2764, 2098, 1752], "full-energy melee promotion cannot displace in-range Throw"),
        (rogue + """points=0; pool[3]=2764; starved={}; procs[1752]=true;
            ranges[1752]=false; ranges[2098]=false; ranges[2764]=true; b.inCombat=true""",
         [2764, 2098, 1752], "real proc glow cannot promote out-of-range melee over Throw"),
        (rogue + """points=0; pool[3]=2764; starved={}; capped=true;
            ranges[1752]=false; ranges[2098]=false; ranges[2764]=true;
            cooldown[2764]=true; b.inCombat=true""",
         [wait, 2764, 2098, 1752], "WAIT during Throw cooldown rather than out-of-range full-energy melee"),
        (rogue + """points=0; pool[3]=2764; starved={}; capped=true;
            ranges[1752]=true; ranges[2098]=true; ranges[2764]=false; b.inCombat=true""",
         [1752, 2098, 2764], "melee promotion returns when target enters range"),
        (rogue + """points=0; pool[3]=2764; starved={}; capped=true;
            ranges[1752]=false; ranges[2098]=false; ranges[2764]=true;
            b.sinkCooldowns=false; b.inCombat=true""",
         [1752, 2764, 2098], "unavailable-last opt-out retains full-energy promotion"),
        (rogue + """points=0; pool[3]=2764; ranges[1752]=false;
            ranges[2098]=false; ranges[2764]=true; b.maxIcons=1; b.inCombat=false""",
         [2764], "single-icon OOC queue recommends eligible Throw, not WAIT"),
        (rogue + """points=0; pool[3]=2764; ranges[1752]=false;
            ranges[2098]=false; ranges[2764]=true; cooldown[2764]=true""",
         [wait, 2764, 2098, 1752], "Throw on cooldown waits ahead of wasted melee presses"),
        (rogue + """points=0; pool[3]=2764; starved[1752]=nil;
            ranges[2764]=false""",
         [1752, 2098, 2764], "usable melee leads Throw inside its minimum range"),
        (rogue + """points=0; pool[3]=2764; ranges[1752]=false;
            ranges[2098]=false; ranges[2764]=false""",
         [wait, 2098, 1752, 2764], "Throw outside its range does not prevent WAIT"),
        (rogue + "points=2; b.ctxPointCap=2; starved[2098]=nil", [2098, 1752], "affordable consumer removes WAIT"),
        (rogue + "points=0; b.maxIcons=1", [wait], "one-icon queue shows WAIT"),
        (rogue + "points=0; b.maxIcons=2", [wait, 1752], "WAIT respects icon limit"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}};
            cooldown[53]=true; cooldown[1752]=true; b.inCombat=true""",
         [wait, 53, 1752], "cooldown-only queue shows WAIT"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}};
            points=0; holdPoints[53]=2; holdPoints[1752]=2; b.inCombat=true""",
         [wait, 53, 1752], "all-held queue shows WAIT"),
        (rogue + "points=0; b.spellCount=1; b.recommendedSpells={999}", [999, 1752, 2098], "early injected suggestion prevents WAIT"),
        ("pool={}; entries={}", [], "empty pool never synthesizes WAIT"),
        ("""pool={53,1752}; entries={{id=53},{id=1752}}; targetingMe=true;
            specKey='ROGUE_F'; starved[1752]=true; b.inCombat=true""", [wait, 1752, 53], "rear-blocked attack does not count as actionable"),
    ]
    for setup, expected, description in wait_cases:
        lua.execute("Reset(); " + setup)
        queue = lua.globals().Build()
        lua.globals().b.spellCount = len(queue)
        lua.globals().SpellQueue._StageForeverWait(lua.globals().b)
        actual = [queue[i] for i in range(1, lua.globals().b.spellCount + 1)]
        assert actual == expected, f"{description}: got {actual}, expected {expected}"
    lua.execute("Reset(); " + rogue + "points=0")
    queue = lua.globals().Build()
    lua.globals().b.spellCount = len(queue) + 1
    queue[len(queue) + 1] = 999
    lua.globals().SpellQueue._StageForeverWait(lua.globals().b)
    assert queue[1] != wait, "later actionable burst injection prevents WAIT"
    print(f"Forever WAIT: {len(wait_cases)} cases and late-injection check passed")
    lua.execute(extract("AddSpellbookProcs", source) + """
        function PassesSpellFilters() return true end
        SpellDB.IsOffensiveSpell = function() return true end
        ActionBarScanner = {
            GetSpellbookProccedSpells = function() return {2098} end,
            GetSpellHotkey = function() return "1" end,
        }
        Reset(); unusable[2098]=true
    """)
    assert lua.globals().AddSpellbookProcs(lua.globals().b) == 0, "early spellbook proc must not inject unusable finisher"
    lua.execute("Reset(); starved[2098]=true")
    assert lua.globals().AddSpellbookProcs(lua.globals().b) == 0, "early spellbook proc must not inject unaffordable finisher"
    lua.execute("Reset(); ranges[2098]=false")
    assert lua.globals().AddSpellbookProcs(lua.globals().b) == 0, "early spellbook proc must not inject out-of-range spell"
    assert not lua.globals().b.addedSpellIDs[2098], "range rejection must release the spell for tail sinking"
    lua.execute("Reset(); ranges[2098]=nil")
    assert lua.globals().AddSpellbookProcs(lua.globals().b) == 1, "unknown range does not reject early spellbook proc"
    lua.execute("Reset()")
    assert lua.globals().AddSpellbookProcs(lua.globals().b) == 1, "usable spellbook proc remains available"
    lua.execute("Reset(); " + rogue + "points=5")
    assert list(lua.globals().Build().values()) == [2098, 1752]
    lua.execute("points=0; b.addedSpellIDs={}; b.recommendedSpells={}; unavailableTier={}")
    assert list(lua.globals().Build().values()) == [1752, 2098], "spending points must immediately surface the builder"
    lua.execute("Reset()")
    bolt = next(e for e in lua.globals().entries.values() if e.id == 403)
    assert len(bolt.gates) == 1 and bolt.gates[1].t == "stack", "imported stack gates were not mutated"
    print(f"Forever openers and prerequisites: {len(cases)} cases, spend transition and 5 early-proc checks passed")


if __name__ == "__main__":
    main()
