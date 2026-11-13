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
    classes, rankBases, rankChains = data, {}, chains
    for base, chain in pairs(chains) do
        for _, id in ipairs(chain) do rankBases[id] = base end
    end
end
function RI.RankBase(id) return rankBases[id] or id end
function RI.RankChain(id) return rankChains[RI.RankBase(id)] end
RotationImport = RI
function wipe(t) for k in pairs(t) do t[k] = nil end end
SpellQueue = { IsSpellBlacklisted = function(id) return blacklisted[id] == true end }
SpellQueue.WAIT_SENTINEL = -999999999
SpellDB = { GetSpecKey = function() return specKey end }
FOREVER_REAR_ATTACKS = {}
LEAD_BARRED_PENALTY = 100000
FOREVER_PULLS, FOREVER_RANGED_FILLERS = {}, {}
function SpellDB.RegisterCategories(t)
    FOREVER_REAR_ATTACKS, FOREVER_PULLS, FOREVER_RANGED_FILLERS =
        t.foreverRear, t.foreverPull, t.foreverRanged
end
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
function PassesSpellFilters(id) return not filtered[RotationImport.RankBase(id)] end
function IsSpenderSpell(id) return specKey == "ROGUE_F" end
function IsConfirmedOutOfRange(id) return BlizzardAPI.AbilityInRange(id) == false end
function SimcBuffWindowActive() return false end
function GateInPickWindows() return false end
function HasPositiveBuffGate() return false end
function SimcNegativeBuffBlocks() return false end
function DotGateBlocks() return false end
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


def create_runtime(real_gates=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Data" / "SpellCategories.lua").read_text(encoding="utf-8"))
    db_source = (ROOT / "SpellDB.lua").read_text(encoding="utf-8")
    for name in ("GetForeverRearRequirement", "GetForeverPullPolicy", "IsForeverRangedFiller"):
        start_db = db_source.index(f"function SpellDB.{name}(")
        end_db = db_source.index("\nend", start_db) + len("\nend")
        lua.execute(db_source[start_db:end_db])
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("local function IsForeverPullSpell(")
    end = source.index("\n--- Largest icon count", start)
    tail_start = source.index("function SpellQueue._StageTail(")
    tail_end = source.index("\nend", tail_start) + len("\nend")
    helpers = "\n".join(extract(name, source) for name in (
        "ProcPriorityEnabled", "ClaimSpellID", "HeldByUserHold", "HasUserHold", "ResourceGateHolds", "MissingMinimumResource",
        "IsBarGreyedOut", "IsRearAttackBlocked", "IsLiveAttackableTarget",
        "GateVerdict", "ProcGateBlocks", "SimcGateBlocks", "TieredSpenderType", "PointGateCap",
        "IsUnusableNonResource", "SimcPowerType", "ThresholdGateBlocks", "StackAtLeast", "StackHolds"
    ))
    helpers = """
        local gateCtx, tieredSpenderCache = {}, {}
        local DISCRETE_POWER = {[4]=true,[9]=true,[12]=true,[7]=true,
            [5]=true,[19]=true,[16]=true}
        PROC_CONTEXT_GATES = {dot=true,known=true,near=true,prev=true,stealth=true,
            targets=true,totem=true,unconfirmed=true}
    """ + helpers
    lua.execute(helpers + """
        SpellQueue.IsUnusableNonResource = IsUnusableNonResource
        SpellQueue._GateVerdict = GateVerdict
        SpellQueue._SimcGateBlocks = SimcGateBlocks
    """ + ("" if real_gates else """
        local realVerdict = GateVerdict
        GateVerdict = function(g, ctx)
            if g.t == "stack" then return stacks >= g.n end
            if g.t == "cd" then return false end
            return realVerdict(g, ctx)
        end
    """) + """
        SpellDB.IsPureSelfAura = function(id)
            return finisher[RotationImport.RankBase(id)] ~= true
        end
        SpellDB.IsTargetDot = function() return false end
        SpellDB.IsOffensiveSpell = function() return true end
        local reset = Reset
        Reset = function()
            reset()
            wipe(tieredSpenderCache)
        end
    """ + source[source.index("local spellbookProcState ="):source.index("\n--- Profile-distance rank")] + source[start:end] + """
        function Build()
            CategorizeAndAssembleRotation(AddSpellbookProcs(pool, b), b)
            return b.recommendedSpells
        end
        local cachedRotationList
        local lastCtx, pickWindowsBuf = {}, {}
        BlizzardAPI.GetEffectiveOrdering = function() return b.contextOrder end
        RotationImport.HasRotation = function() return true end
        SpellQueue.FilterHealerTail = function(list) return list end
    """ + source[tail_start:tail_end] + """
        function BuildStage()
            cachedRotationList = pool
            SpellQueue._StageTail(b)
            return b.recommendedSpells
        end
    """)
    wait_start = source.index("function SpellQueue._StageForeverWait(")
    wait_end = source.index("\nfunction SpellQueue._StageFinalize(", wait_start)
    lua.execute(extract("IsLiveAttackableTarget", source).replace("local function", "function", 1)
                + "\n" + source[wait_start:wait_end])
    power_start = source.index("function SpellQueue.PowerGateThreshold(")
    power_end = source.index("\nend", power_start) + len("\nend")
    lua.execute(source[power_start:power_end])
    return lua


def check_trash_burst_wait():
    lua = create_runtime()
    for setup, should_wait in (
        ("", True),
        ("procs[1259799]=true", True),
        ("b.ctxEnemies=0", True),
        ("b.inCombat=false;b.ctxEnemies=0", True),
        ("b.inCombat=false;targetExists=false;b.ctxEnemies=0", True),
        ("b.inCombat=false;targetDead=true;b.ctxEnemies=0", True),
        ("b.inCombat=false;b.ctxEnemies=3", True),
        ("classification='elite'", False),
        ("b.inCombat=false;classification='elite'", False),
        ("b.ctxEnemies=3", False),
        ("SpellQueue._rotationIsCustom=true", False),
        ("pinnedAlwaysShow[1259799]=true", False),
        ("holdPoints[1259799]=0", False),
        ("b.profile.burstTriggers={SHAMAN_F={1259799}}", False),
    ):
        lua.execute("""
            Reset()
            classification='normal'
            function UnitClassification() return classification end
            BlizzardAPI.IsTargetBoss=function() return false end
            BlizzardAPI.PeekBaseCooldownSeconds=function(id)
                if id==1259799 then return 180 end
                return 0
            end
            b.inCombat=true;b.ctxEnemies=1;b.leadMode='mylist'
            entries={{id=403}}
            pool={403,1259799}
            cooldown[403]=true
        """ + setup)
        queue = lua.globals().Build()
        lua.globals().b.spellCount = len(queue)
        lua.globals().SpellQueue._StageForeverWait(lua.globals().b)
        if should_wait:
            assert queue[1] == lua.globals().SpellQueue.WAIT_SENTINEL, setup
            assert queue[2] == 403 and queue[3] == 1259799, setup
        else:
            assert queue[1] == 1259799, setup
    print("Trash burst fallback: wait, proc veto, elites, packs and explicit overrides passed")


def check_positioning_openers():
    lua = create_runtime()
    setup = """
        specKey='WARLOCK_F'
        pool={1459,686,172}
        entries={{id=1459},{id=686},{id=172}}
        ranges[686],ranges[172]=false,false
        SpellDB.IsPureSelfAura=function(id) return id==1459 end
        C_Spell.IsSpellHarmful=function(id) return id==686 or id==172 end
    """
    cases = [
        ("", [686, 172, 1459]),
        ("b.maxIcons=1", [686]),
        ("ranges[686]=nil", [686, 172, 1459]),
        ("ranges[172]=true", [686, 172, 1459]),
        ("b.contextOrder='ac'", [686, 172, 1459]),
        ("cooldown[686]=true", [172, 1459, 686]),
        ("unusable[686]=true", [172, 1459, 686]),
        ("starved[686]=true", [172, 1459, 686]),
        ("locked[686]=true", [172, 1459, 686]),
        ("filtered[686]=true", [172, 1459]),
        ("blacklisted[686]=true", [172, 1459]),
        ("b.inCombat=true", [1459, 686, 172]),
        ("forever=false", [1459, 686, 172]),
        ("SpellQueue._rotationIsCustom=true", [1459, 686, 172]),
        ("b.contextOrder='off'", [1459, 686, 172]),
        ("targetExists=false", [1459, 686, 172]),
        ("hostile=false", [1459, 686, 172]),
        ("targetDead=true", [1459, 686, 172]),
        ("C_Spell.IsSpellHarmful=nil", [1459, 686, 172]),
        ("C_Spell.IsSpellHarmful=function() error('denied') end", [1459, 686, 172]),
        ("C_Spell.IsSpellHarmful=function() return secret end", [1459, 686, 172]),
        ("b.spellCount=1; b.recommendedSpells={999}", [999, 686, 172, 1459]),
        ("procs[1459]=true", [1459, 686, 172]),
    ]
    for extra, expected in cases:
        lua.execute("Reset(); " + setup + extra)
        queue = lua.globals().Build()
        actual = list(queue.values())
        assert actual == expected, (extra, actual, expected)
    print(f"Pre-pull positioning: {len(cases)} cases preserve attacks over self buffs, safety gates and explicit ordering")


def check_queue_fast_paths():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        rankSortIdx={}
        function wipe(t) for k in pairs(t) do t[k]=nil end end
        sortCalls=0
        local sort=table.sort
        table.sort=function(...) sortCalls=sortCalls+1;return sort(...) end
    """)
    start = source.index("local sortRanks\n")
    end = source.index("\n--- Categorize rotation spells", start)
    lua.execute(source[start:end] + """
        local q={99}
        assert(AppendRankedBucket({1,2},{2,1},2,q,1,1)==1 and q[1]==99)
        assert(AppendRankedBucket({},{},0,q,1,4)==1)
        assert(AppendRankedBucket({42},{9},1,q,1,4)==2 and q[2]==42)
        assert(sortCalls==0, 'full, empty and singleton buckets must not sort')
        q={}
        assert(AppendRankedBucket({10,11,12},{2,1,1},3,q,0,2)==2)
        assert(q[1]==11 and q[2]==12 and sortCalls==1, 'stable ties and cap')
    """)
    for client in (True, False):
        for value in (True, False, None):
            lua = create_runtime()
            lua.globals().testClient = client
            lua.globals().dotValue = value
            lua.execute("""
                Reset()
                forever=testClient
                b.inCombat=true
                entries={{id=403},{id=8042}}
                dotReads=0
                DotTracker={IsDotActiveOnCurrentTarget=function()
                    dotReads=dotReads+1;return dotValue
                end}
                Build()
                assert(dotReads==2, 'at most one lazy DoT read per spell')
                b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0
                dotValue=false
                Build()
                assert(dotReads==4, 'memo must be cleared between categorization passes')
                b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0
                procs={[403]=true,[8042]=true}
                Build()
                assert(dotReads==4, 'proc promotion must not introduce DoT reads')
            """)
    lua = create_runtime()
    start = source.index("local function IsForeverPullSpell(")
    end = source.index("\n--- Largest icon count", start)
    lua.execute("""
        Reset();holdReads=0
        function HasUserHold() holdReads=holdReads+1;return false end
        function HeldByUserHold() return false end
    """ + source[start:end] + """
        CategorizeAndAssembleRotation(pool,b)
        assert(holdReads==2, 'one hold-setting lookup per admitted spell')
    """)
    print("Queue fast paths: skipped sorts, stable ties and fresh tri-state DoT reads passed")


def check_spellbook_proc_pipeline():
    cases = [
        ("", [2098, 1752]),
        ("b.profile.showSpellbookProcs=false", [1752, 2098]),
        ("b.profile.orderProcsFirst=false", [1752, 2098]),
        ("b.bypassProcs=true", [1752, 2098]),
        ("b.profile.defensives={spellSettings={[2098]={procPriority=false}}}", [1752, 2098]),
        ("b.profile.defensives={spellSettings={[11299]={procPriority=false}}}", [1752, 2098]),
        ("entries[2].gates={{t='targets',op='>=',n=3}}", [1752, 2098]),
        ("entries[2].gates={{t='stack',id=1,op='>=',n=5}}", [2098, 1752]),
        ("entries[2].gates={{t='buff',id=5171,neg=true,dur=5}};buffs[5171]=true;forever=true",
         [1752, 2098]),
        ("holdPoints[2098]=6; points=2", [1752, 2098]),
        ("locked[2098]=true", [1752, 2098]),
        ("points=0", [1752, 2098]),
        ("cooldown[2098]=true", [1752, 2098]),
        ("pool={1752}", [2098, 1752]),
        ("pool={1752};cooldown[2098]=true", [1752]),
        ("pool={1752};starved[2098]=true", [1752]),
        ("pool={1752};unusable[2098]=true", [1752]),
        ("pool={1752};ranges[2098]=false;b.sinkCooldowns=false", [1752]),
        ("pool={1752};entries[2].gates={{t='targets',op='>=',n=3}}", [1752]),
        ("SpellQueue._rotationIsCustom=true;b.contextOrder='off';b.profile.orderProcsFirst=false",
         [1752, 2098]),
    ]
    for client in (True, False):
        for extra, expected in cases:
            lua = create_runtime()
            lua.globals().client = client
            lua.execute("""
                Reset();forever=client;specKey='ROGUE_F';b.inCombat=true;points=5
                b.profile.showSpellbookProcs=true
                b.effectiveBypassProcs=false
                entries={{id=1752},{id=2098}}
                pool={1752,2098}
                BlizzardAPI.GetEngagedEnemyCount=function() return 1 end
                ActionBarScanner={
                    GetSpellbookProccedSpells=function() return {2098} end,
                    GetSpellHotkey=function() return '1' end,
                }
            """ + extra)
            # StageTail computes this from the master/profile switches.
            lua.execute("b.effectiveBypassProcs=b.bypassProcs or b.profile.orderProcsFirst==false")
            actual = list(lua.globals().Build().values())
            assert actual == expected, (client, extra, actual, expected)

    lua = create_runtime()
    lua.execute("""
        Reset();b.inCombat=true;b.ctxEnemies=1;b.profile.showSpellbookProcs=true
        classification='normal'
        function UnitClassification() return classification end
        BlizzardAPI.IsTargetBoss=function() return false end
        BlizzardAPI.PeekBaseCooldownSeconds=function(id) return 180 end
        pool={403,1259799};entries={{id=403},{id=1259799}}
        ActionBarScanner={
            GetSpellbookProccedSpells=function() return {1259799} end,
            GetSpellHotkey=function() return '1' end,
        }
    """)
    assert list(lua.globals().Build().values()) == [403, 1259799]
    assert lua.globals().b.automaticBurstHeld
    print(f"Spellbook proc pipeline: {len(cases) * 2} cross-client cases and automatic burst hold passed")


def check_shared_proc_stage():
    cases = [
        ("", [11299, 1752]),
        ("b.profile.orderProcsFirst=false", [1752, 11299]),
        ("b.bypassProcs=true", [1752, 11299]),
        ("b.profile.defensives={spellSettings={[2098]={procPriority=false}}}", [1752, 11299]),
        ("b.profile.defensives={spellSettings={[11299]={procPriority=false}}}", [1752, 11299]),
        ("entries[2].gates={{t='targets',op='>=',n=3}}", [1752, 11299]),
        ("pool=nil", [11299]),
        ("pool=nil;cooldown[2098]=true", []),
        ("pool=nil;b.profile.showSpellbookProcs=false", []),
        ("pool={1752};b.hideItems=true;BlizzardAPI.IsItemSpell=function(id) return id==11299 end",
         [1752]),
    ]
    for client in (True, False):
        for extra, expected in cases:
            lua = create_runtime()
            lua.globals().client = client
            lua.execute("""
                Reset();forever=client;specKey='ROGUE_F';b.inCombat=true;points=5
                b.profile.showSpellbookProcs=true
                entries={{id=1752},{id=2098}}
                pool={1752,2098}
                BlizzardAPI.GetDisplaySpellID=function(id)
                    if RotationImport.RankBase(id)==2098 then return 11299 end
                    return id
                end
                BlizzardAPI.GetEngagedEnemyCount=function() return 1 end
                ActionBarScanner={
                    GetSpellbookProccedSpells=function() return {2098,11299} end,
                    GetSpellHotkey=function() return '1' end,
                }
            """ + extra)
            actual = list(lua.globals().BuildStage().values())
            assert actual == expected, (client, extra, actual, expected)
            assert lua.globals().b.spellCount == len(actual)
    print(f"Shared tail stage: {len(cases) * 2} cross-client rank, settings and absent-rotation cases passed")


def main():
    check_queue_fast_paths()
    check_spellbook_proc_pipeline()
    check_shared_proc_stage()
    check_trash_burst_wait()
    lua = create_runtime()
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    cases = [
        ("", [403, 8042], "OOC bolt leads without Maelstrom stacks"),
        ("pool = {10414, 15208}", [15208, 10414], "highest-rank entries use the same opener"),
        ("b.inCombat = true", [8042, 403], "combat retains the five-stack gate"),
        ("b.inCombat = true; stacks = 5", [403, 8042], "combat instant bolt keeps imported rank"),
        ("forever = false", [8042, 403], "retail has no opener exception"),
        ("SpellQueue._rotationIsCustom = true", [8042, 403], "custom list retains combat gates"),
        ("b.contextOrder = 'off'", [8042, 403], "exact source order unchanged"),
        ("b.contextOrder = 'ac'", [8042, 403], "non-theorycraft ordering unchanged"),
        ("ranges[403] = false", [403, 8042], "out-of-range bolt remains the pull cue"),
        ("ranges[403] = nil", [403, 8042], "unknown range retains the pull cue"),
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
        (rogue + "points=2; starved[2098]=nil; procs[2098]=true",
         [2098, 1752], "proc may override an unmet imported resource preference"),
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
        ("""pool={2098,1752}; entries={{id=2098,gates={{t='targets',op='>=',n=2}}},{id=1752}};
            procs[2098]=true; points=5;
            BlizzardAPI.GetEngagedEnemyCount=function() return 1 end""",
         [1752, 2098], "proc cannot bypass an unmet target-count gate"),
        ("""pool={2098,1752}; entries={{id=2098,gates={{t='targets',op='>=',n=2}}},{id=1752}};
            procs[2098]=true; points=5; BlizzardAPI.GetEngagedEnemyCount=nil""",
         [2098, 1752], "unknown target count does not veto a confirmed proc"),
        ("""pool={2098,1752}; entries={{id=2098,gates={{t='stack',id=1,op='>=',n=5}}},{id=1752}};
            procs[2098]=true; points=5; stacks=0""",
         [2098, 1752], "proc glow may override a stack priority preference"),
        ("""pool={2098,1752}; entries={{id=2098,gates={{t='buff',id=5171,neg=true,dur=5}}},{id=1752}};
            procs[2098]=true; points=5; buffs[5171]=true""",
         [1752, 2098], "proc cannot bypass a confirmed active exclusion buff"),
        ("""pool={2098,1752}; entries={{id=2098,gates={{t='dot',id=1}}},{id=1752}};
            procs[2098]=true; points=5;
            BlizzardAPI.IsUnitHealthBelow=function() return true end""",
         [1752, 2098], "proc cannot bypass a confirmed short-lived target gate"),
        ("""pool={2098,1752}; entries={{id=2098,gates={{t='totem',slot=1}}},{id=1752}};
            procs[2098]=true; points=5;
            BlizzardAPI.IsTotemSlotOccupied=function() return false end""",
         [1752, 2098], "proc cannot bypass a confirmed totem-state gate"),
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
        (rogue + """points=0; pool[3]=2764; ranges[1752]=false;
            ranges[2098]=false; ranges[2764]=true; cooldown[2764]=true;
            b.ctxOutOfMelee=true""",
         [2764, 2098, 1752], "cooling Throw keeps repeat-shot plan when melee is confirmed out"),
        (rogue + """points=0; pool[3]=2764; ranges[1752]=false;
            ranges[2098]=false; ranges[2764]=true; cooldown[2764]=true;
            b.ctxOutOfMelee=true; b.maxIcons=1""",
         [2764], "single icon retains cooling Throw"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; starved[1752]=nil""",
         [1752, 2764, 2098], "ready alternative takes precedence over cooling Throw"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=false;
            cooldown[2764]=true; b.ctxOutOfMelee=true""",
         [wait, 1752, 2098, 2764], "blocked-range Throw cannot replace WAIT"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=nil;
            cooldown[2764]=true; b.ctxOutOfMelee=true""",
         [wait, 1752, 2764, 2098], "unknown-range Throw cannot replace WAIT"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; unusable[2764]=true""",
         [wait, 1752, 2098, 2764], "uncastable Throw cannot replace WAIT"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; targetDead=true; b.inCombat=true""",
         [wait, 1752, 2764, 2098], "dead target cannot retain cooling Throw"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; forever=false""",
         [1752, 2764, 2098], "Retail never retains cooling ranged fillers"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; locked[2764]=true""",
         [wait, 1752, 2764, 2098], "locked Throw cannot replace WAIT"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; holdPoints[2764]=2""",
         [wait, 1752, 2098, 2764], "explicit point hold blocks cooling Throw continuity"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; starved[2764]=true""",
         [wait, 1752, 2764, 2098], "resource shortage blocks ranged continuity"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=true;
            cooldown[2764]=true; b.ctxOutOfMelee=true; b.contextOrder='off'""",
         [2098, 1752, 2764], "exact source order ignores ranged continuity"),
        (rogue + """points=0; pool[3]=2764; starved[1752]=nil;
            ranges[2764]=false""",
         [1752, 2098, 2764], "usable melee leads Throw inside its minimum range"),
        (rogue + """points=0; pool[3]=2764; ranges[2764]=false""",
         [wait, 1752, 2098, 2764], "blocked Throw cannot fill an energy-starved melee gap"),
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
    for filler in (75, 2480, 5019, 7918, 7919):
        spec = "HUNTER_F" if filler == 75 else "PRIEST_F" if filler == 5019 else "WARRIOR_F"
        other = 2973 if filler == 75 else 585 if filler == 5019 else 78
        wait_cases.append((f"""specKey='{spec}'; pool={{{filler},{other}}};
            entries={{{{id={other}}}}}; ranges[{other}]=false;
            ranges[{filler}]=true; cooldown[{filler}]=true; b.ctxOutOfMelee=true""",
            [filler, other], f"{spec} ranged weapon filler {filler} retains its cooldown plan"))
    for setup, expected, description in wait_cases:
        lua.execute("Reset(); " + setup)
        queue = lua.globals().Build()
        lua.globals().b.spellCount = len(queue)
        lua.globals().SpellQueue._StageForeverWait(lua.globals().b)
        actual = [queue[i] for i in range(1, lua.globals().b.spellCount + 1)]
        assert actual == expected, f"{description}: got {actual}, expected {expected}"
    lua.execute("Reset(); " + rogue + """points=0; pool[3]=2764; ranges[2764]=true;
        cooldown[2764]=true; b.ctxOutOfMelee=true;
        queueProbeEnabled=true; queueProbeEntries={}""")
    assert lua.globals().Build()[1] == 2764
    assert lua.globals().queueProbeEntries[2764].startswith("bucket=rangedWait ")
    assert lua.globals().sunkSet[2764], "cooling filler must remain barred from burst injection"
    lua.execute("queueProbeEnabled=false")
    lua.execute("Reset(); " + rogue + "points=0")
    queue = lua.globals().Build()
    lua.globals().b.spellCount = len(queue) + 1
    queue[len(queue) + 1] = 999
    lua.globals().SpellQueue._StageForeverWait(lua.globals().b)
    assert queue[1] != wait, "later actionable burst injection prevents WAIT"
    print(f"Forever WAIT: {len(wait_cases)} cases and late-injection check passed")
    lua.execute("""
        function SpellbookProcCount(b)
            b.profile.showSpellbookProcs = true
            pool = {}
            return #Build()
        end
        SpellDB.IsOffensiveSpell = function() return true end
        ActionBarScanner = {
            GetSpellbookProccedSpells = function() return {2098} end,
            GetSpellHotkey = function() return "1" end,
        }
        Reset(); unusable[2098]=true
    """)
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 0, "spellbook proc must not inject unusable finisher"
    lua.execute("Reset(); starved[2098]=true")
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 0, "spellbook proc must not inject unaffordable finisher"
    lua.execute("Reset(); ranges[2098]=false")
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 0, "spellbook proc must not inject out-of-range spell"
    assert not lua.globals().b.addedSpellIDs[2098], "range rejection must release the spell for tail sinking"
    lua.execute("Reset(); ranges[2098]=nil")
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 1, "unknown range does not reject spellbook proc"
    lua.execute("Reset()")
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 1, "usable spellbook proc remains available"
    for spec, spell in (("ROGUE_F", 53), ("DRUID_F", 5221)):
        lua.execute(f"""Reset(); specKey='{spec}'; targetingMe=true;
            ActionBarScanner.GetSpellbookProccedSpells=function() return {{{spell}}} end""")
        assert lua.globals().SpellbookProcCount(lua.globals().b) == 0, f"{spec} rear gate vetoes spellbook proc"
        assert not lua.globals().b.addedSpellIDs[spell]
        lua.execute("stealthed=true")
        assert lua.globals().SpellbookProcCount(lua.globals().b) == 1, f"{spec} stealth preserves spellbook proc"
    lua.execute("""Reset(); specKey='WARRIOR_F';
        ActionBarScanner.GetSpellbookProccedSpells=function() return {7384} end;
        BlizzardAPI.GetActionBarUsability=function() return false,false end""")
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 0, "greyed reactive attack vetoes spellbook proc"
    lua.execute("BlizzardAPI.GetActionBarUsability=function() return nil,nil end")
    assert lua.globals().SpellbookProcCount(lua.globals().b) == 1, "unknown bar state preserves spellbook proc"
    lua.execute("Reset(); " + rogue + "points=5")
    assert list(lua.globals().Build().values()) == [2098, 1752]
    lua.execute("points=0; b.addedSpellIDs={}; b.recommendedSpells={}; unavailableTier={}")
    assert list(lua.globals().Build().values()) == [1752, 2098], "spending points must immediately surface the builder"
    lua.execute("Reset()")
    bolt = next(e for e in lua.globals().entries.values() if e.id == 403)
    assert len(bolt.gates) == 1 and bolt.gates[1].t == "stack", "imported stack gates were not mutated"
    for points, expected in ((0, [5221, 22568]), (2, [5221, 22568]), (3, [22568, 5221])):
        lua.execute(f"""Reset(); specKey='DRUID_F'; points={points}; b.ctxPointCap=3;
            pool={{22568,5221}}; finisher={{[RotationImport.RankBase(22568)]=true}}; stealthed=true;
            entries={{{{id=RotationImport.RankBase(22568),gates={{{{t='resource',res='combo_points',op='>=',n=5}}}}}},
                {{id=5221}}}};
            C_Spell.GetSpellPowerCost=function(id)
                if id==22568 then return {{{{type=4,minCost=1,cost=5,
                    requiredAuraID=0,hasRequiredAura=false}}}} end
                return {{}}
            end""")
        actual = list(lua.globals().Build().values())
        assert actual == expected, ("Feral finisher shares point-cap/minimum-cost policy", points, actual, expected)
    print("Cross-class: Rogue/Feral early rear procs, Warrior reactive usability, ranged fillers and Feral finishers passed")
    print(f"Forever openers and prerequisites: {len(cases)} cases, spend transition and 5 early-proc checks passed")


if __name__ == "__main__":
    check_positioning_openers()
    main()
