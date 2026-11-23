# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Real Forever entries and queue assembly, with controlled readiness and range.
from pathlib import Path

from wow_stubs import LuaRuntime

from test_gate_groups import extract
from test_buff_refresh_window import buff_window_lua

ROOT = Path(__file__).resolve().parent.parent


def aura_clock_source(root):
    """AuraClock.lua for a harness without a real LibStub: the library becomes global AuraClock."""
    shim = ("do local LibStub = setmetatable({NewLibrary = function() AuraClock = {}; return AuraClock end},"
            " {__call = function() return nil end})\n")
    return shim + (root / "AuraClock.lua").read_text(encoding="utf-8") + "\nend\n"


def forever_stages_body():
    """SpellQueueForever.lua without its header, which captures SpellQueue.lua's file-locals."""
    text = (ROOT / "SpellQueueForever.lua").read_text(encoding="utf-8")
    return text[text.index("local lastPushbackAt"):]

PRELUDE = r"""
local RI = {}
function LibStub(name)
    if name == "JustAC-SpellDB" then return SpellDB end
    return RI
end
function RI.RegisterForever(data, chains, _, damageCooldowns, estimates)
    classes, rankBases, rankChains, pushbackDamage = data, {}, chains, damageCooldowns
    damageEstimates = estimates
    for base, chain in pairs(chains) do
        for _, id in ipairs(chain) do rankBases[id] = base end
    end
end
function RI.RankBase(id) return rankBases[id] or id end
function RI.RankChain(id) return rankChains[RI.RankBase(id)] end
function RI.IsWideOnly(id) return wideOnly ~= nil and wideOnly[RI.RankBase(id)] == true end
function RI.IsLeftOut(id, ctx) return leftOut ~= nil and leftOut[ctx or "st"] ~= nil and leftOut[ctx or "st"][RI.RankBase(id)] == true end
function RI.IsNamed(id) return named == nil or named[RI.RankBase(id)] == true end
function RI.GetPushbackDamageCooldown(id) return pushbackDamage[RI.RankBase(id)] end
function RI.GetDirectDamageEstimate(id) if unpriced[id] then return nil end return damageEstimates[id] end
RotationImport = RI
function wipe(t) for k in pairs(t) do t[k] = nil end end
SpellQueue = { IsSpellBlacklisted = function(id) return blacklisted[id] == true end }
SpellQueue._OneGCD = function() return 1.5 end
SpellQueue.WAIT_SENTINEL = -999999999
AUTO_ATTACK_SPELL = 6603
SpellDB = {
    GetSpecKey = function() return specKey end,
    NEXT_SWING_SPELLS = {[78]=true,[845]=true,[2973]=true,[14260]=true,[6807]=true},
}
FOREVER_REAR_ATTACKS = {}
LEAD_BARRED_PENALTY = 100000
FOREVER_PULLS, FOREVER_RANGED_FILLERS = {}, {}
FOREVER_TARGET_SETUP = {}
function SpellDB.RegisterCategories(t)
    FOREVER_REAR_ATTACKS, FOREVER_PULLS, FOREVER_RANGED_FILLERS =
        t.foreverRear, t.foreverPull, t.foreverRanged
    FOREVER_TARGET_SETUP = t.foreverTargetSetup
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
    CooldownEndsWithin = function(id) return briefWait[RI.RankBase(id)] end,
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
    GetDirectSpellHit = function(id) return hits[id] end,
    GetCachedSpellInfo = function(id) return {castTime = castTimes[RI.RankBase(id)] or 0} end,
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
        if e.id == base then return {rank = i, gates = e.gates, delegated = e.delegated, w = e.w} end
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
    if SpellQueue.ResetNearMeleeHint then SpellQueue.ResetNearMeleeHint() end
    forever, specKey, stacks = true, "SHAMAN_F", 0
    targetExists, hostile = true, true
    targetDead = false
    cachedGapCloserEngine = nil
    wideOnly = {}
    leftOut = nil
    named = nil
    activityAt = nil
    ranges, cooldown, unusable, starved, locked, filtered, blacklisted, procs =
        {[403] = true, [8042] = true}, {}, {}, {}, {}, {}, {}, {}
    SpellQueue._rotationIsCustom = false
    points = nil
    maximum, resourceName, resourceReads = 5, "combo_points", 0
    capped, minimum, costAura, hasCostAura = false, 1, 0, false
    stealthed, targetingMe, talents, buffs = false, false, {}, {}
    hits, unpriced, briefWait = {}, {}, {}
    castTimes = {[403] = 1500, [585] = 1500, [8092] = 1500, [14914] = 3500}
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
    cooldownSpells, sunkSet, unavailableTier, formEntryBase, pinnedAlwaysShow, displacedPrimary = {}, {}, {}, {}, {}, {}
    b = {
        profile = {}, blacklist = {}, addedSpellIDs = {}, recommendedSpells = {},
        spellCount = 0, maxIcons = 4, effectiveBypassProcs = false,
        contextOrder = "simc", sinkCooldowns = true, inCombat = false, ctxPointCap = nil, now = 100,
    }
    finisher = {[2098] = true}
    pool = {8042, 403}
end
"""


def create_runtime(real_gates=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(buff_window_lua("BlizzardAPI"))
    lua.execute((ROOT / "Data" / "Forever" / "Rotations.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "Data" / "SpellCategories.lua").read_text(encoding="utf-8"))
    db_source = (ROOT / "SpellDB.lua").read_text(encoding="utf-8")
    for name in ("GetForeverRearRequirement", "IsForeverRangedFiller",
                 "GetForeverTargetSetupPolicy"):
        start_db = db_source.index(f"function SpellDB.{name}(")
        end_db = db_source.index("\nend", start_db) + len("\nend")
        lua.execute(db_source[start_db:end_db])
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("function SpellQueue._IsTargetSetupOpener(")
    end = source.index("\n--- Largest icon count", start)
    tail_start = source.index("function SpellQueue._StageTail(")
    tail_end = source.index("\nend", tail_start) + len("\nend")
    wait_start = source.index("function SpellQueue._StageForeverWait(")
    wait_end = source.index("\nfunction SpellQueue._StageFinalize(", wait_start)
    helpers = "\n".join(extract(name, source) for name in (
        "ProcPriorityEnabled", "ClaimSpellID", "HeldByUserHold", "HasUserHold", "CompareOp", "ResourceGateHolds", "MissingMinimumResource",
        "IsBarGreyedOut", "IsRearAttackBlocked", "IsLiveAttackableTarget", "IsStackPayoffContext",
        "GateVerdict", "GatesConfirmed", "ProcGateBlocks", "SimcGateBlocks", "TieredSpenderType", "PointGateCap",
        "IsUnusableNonResource", "SimcPowerType", "ThresholdGateBlocks", "StackAtLeast", "StackHolds",
        "PlaceQueueSpell"
    ))
    helpers = """
        local gateCtx, tieredSpenderCache = {}, {}
        rankState = {}
        castOnlyBuffSeen = {}
        local lastCtx = {}
        pushbackDebug = lastCtx
        local EFFICIENCY_ATTACKS = {5019, 75, AUTO_ATTACK_SPELL}
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
        LONG_FIGHT_SECONDS = LONG_FIGHT_SECONDS or 20
        Upkeep = { DRAINING_POWER = {[1]=true, [6]=true} }
    """ + aura_clock_source(ROOT) + source[source.index("local spellbookProcState ="):source.index("\n--- Profile-distance rank")] \
        + source[start:end] \
        + source[source.index("local function PushbackRead("):source.index("--- Stage G - burst-ready cue")] \
        + forever_stages_body() + """
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
    """ + source[wait_start:wait_end])
    power_start = source.index("function SpellQueue.PowerGateThreshold(")
    power_end = source.index("\nend", power_start) + len("\nend")
    lua.execute(source[power_start:power_end])
    return lua


def check_target_setup_openers():
    lua = create_runtime(real_gates=True)
    lua.execute("""
        now=100;combat=false;restricted=false;visible=true;targetGUID="Creature-A"
        auraList={};batchReads=0;indexReads=0;messages={};denyList=false
        function GetTime() return now end
        function UnitAffectingCombat() return combat end
        function UnitIsVisible() return visible end
        function UnitGUID() return targetGUID end
        function issecretvalue(value) return value==secret end
        function issecrettable(value) return value==secretList end
        function geterrorhandler()
            return function(message) messages[#messages+1]=message end
        end
        BlizzardAPI.AreAurasSecret=function() return restricted end
        C_UnitAuras={
            GetUnitAuras=function(unit,filter)
                assert(unit=="target" and filter=="HARMFUL")
                batchReads=batchReads+1
                if denyList then error("target aura access denied") end
                return auraList
            end,
            GetAuraDataByIndex=function()
                indexReads=indexReads+1
                error("must not fall back after a denied batch")
            end,
        }
        local oldLibStub=LibStub
        local libs={}
        LibStub=setmetatable({
            NewLibrary=function(_,name) libs[name]=libs[name] or {};return libs[name] end,
        }, {__call=function(_,name,...)
            if libs[name] then return libs[name] end
            if name=="JustAC-BlizzardAPI" then return BlizzardAPI end
            return oldLibStub(name,...)
        end})
    """)
    lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
    lua.execute("""
        P=LibStub("JustAC-PrecombatEngine")
        baseReady=BlizzardAPI.IsSpellReady
        function SetupOpener()
            Reset();P.ClearCache()
            now=100;combat=false;restricted=false;visible=true;targetGUID="Creature-A"
            auraList={};batchReads=0;indexReads=0;denyList=false;secretList=nil;messages={}
            BlizzardAPI.IsSpellReady=baseReady
            specKey="HUNTER_F"
            pool={1978,75,1130,2973,3044}
            entries={{id=1978},{id=75},{id=1130},{id=2973},{id=3044}}
            ranges[1978],ranges[75],ranges[1130],ranges[3044]=true,true,true,true
        end
        function BuildOpener(primary)
            b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0
            if primary then
                b.spellCount=1;b.recommendedSpells[1]=primary;b.addedSpellIDs[primary]=true
            end
            Build()
            b.spellCount=#b.recommendedSpells
            return b.recommendedSpells
        end
    """)
    setup, build = lua.globals().SetupOpener, lua.globals().BuildOpener
    setup()
    ranks = list(lua.globals().RotationImport.RankChain(1130).values())
    for rank in ranks:
        for size in (1, 4):
            setup()
            lua.execute(f"pool[3]={rank};b.maxIcons={size}")
            queue = list(build().values())
            assert queue[0] == rank and len(queue) == size, (rank, size, queue)
            assert lua.globals().b.targetSetupID == rank
            assert len(queue) == len(set(queue)), "promoted setup is not duplicated"
        for aura_rank in ranks:
            setup()
            lua.execute(f"pool[3]={rank};auraList={{{{spellId={aura_rank},sourceUnit='party1'}}}}")
            assert build()[1] != rank, "any caster's existing Mark satisfies the whole family"
            assert lua.globals().b.targetSetupID is None

    controls = (
        "b.inCombat=true;combat=true", "b.contextOrder='off'", "b.sinkCooldowns=false",
        "SpellQueue._rotationIsCustom=true", "forever=false",
        "targetExists=false", "hostile=false", "targetDead=true",
        "cooldown[1130]=true", "unusable[1130]=true", "starved[1130]=true",
        "locked[1130]=true", "blacklisted[1130]=true", "filtered[1130]=true",
        "holdPoints[1130]=5;points=0", "ranges[1130]=false", "ranges[1130]=nil",
        "BlizzardAPI.IsSpellReady=function(id) if id~=1130 then return baseReady(id) end end",
        "entries[3].gates={{t='known',id=999999}}",
        "visible=false", "restricted=true", "visible=secret", "restricted=secret",
        "auraList=secret", "auraList={{spellId=secret}}", "auraList={secret}",
        "auraList={{spellId=1130},{spellId=secret}}", "auraList={{}}",
        "auraList=nil", "denyList=true",
        "secretList=setmetatable({}, {__len=function() error('secret list length') end});auraList=secretList",
    )
    for control in controls:
        setup()
        lua.execute(control)
        build()
        assert lua.globals().b.targetSetupID is None, control
        if control == "denyList=true":
            assert len(lua.globals().messages) == 1 and lua.globals().indexReads == 0

    for size in (1, 4):
        setup()
        lua.execute(f"b.maxIcons={size}")
        queue = list(build(999).values())
        assert queue[0] == 1130 and len(queue) == size, "setup precedes a pre-filled lead slot"
        if size > 1:
            assert queue[1] == 999, "the previous lead shifts rather than disappearing"
    setup()
    lua.execute("b.contextOrder='ac';b.profile.orderProcsFirst=false")
    assert build()[1] == 1130, "target setup is not a proc promotion"
    setup()
    queue = list(build(1130).values())
    assert queue[0] == 1130 and queue.count(1130) == 1, "an existing setup lead stays deduplicated"

    setup()
    lua.execute("""
        FOREVER_TARGET_SETUP[900001]={auraIDs={900101,900102}}
        rankBases[900002]=900001
        specKey="WARLOCK_F";pool={1978,900002,3044}
        entries={{id=1978},{id=900001},{id=3044}}
        ranges[900001]=true;b.maxIcons=1
    """)
    assert build()[1] == 900002, "target setup is not coupled to Hunter, Mark or matching cast/aura IDs"
    lua.execute("auraList={{spellId=900102}};P.InvalidateTargetDebuffs()")
    assert build()[1] == 1978, "another registered aura family also suppresses its setup promotion"
    lua.execute("auraList={};P.InvalidateTargetDebuffs();b.inCombat=true;combat=true")
    assert build()[1] == 1978, "the generalized target-setup policy remains precombat-only"
    lua.execute("FOREVER_TARGET_SETUP[900001]=nil;rankBases[900002]=nil")

    for forever in (True, False):
        setup()
        lua.globals().forever = forever
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is False
        build()
        reads = lua.globals().batchReads
        assert reads == 1, "a build reuses the bounded complete snapshot"
        lua.execute("auraList={{spellId=1130}}")
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is False
        lua.execute("P.InvalidateTargetDebuffs()")
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is True
        lua.execute("auraList={};targetGUID='Creature-B'")
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is False
        lua.execute("auraList={{spellId=1130}};now=now+0.21")
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is True
        lua.execute("combat=true")
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is None
        lua.execute("combat=false;auraList={}")
        assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is False

    source = (ROOT / "JustAC.lua").read_text(encoding="utf-8")
    start = source.index("function JustAC:OnUnitAura(")
    end = source.index("\nend", start) + len("\nend")
    lua.execute("JustAC={MarkQueueDirty=function() dirty=true end}")
    lua.execute('function GetPrecombatEngine() return LibStub("JustAC-PrecombatEngine", true) end; AURA_CACHE_FLAGS={auras=true}')
    lua.execute(source[start:end])
    setup()
    assert build()[1] == 1130
    lua.execute("auraList={{spellId=1130}};JustAC:OnUnitAura('UNIT_AURA','target',{})")
    assert lua.globals().dirty and build()[1] != 1130, "application invalidates the opener immediately"
    lua.execute("auraList={};JustAC:OnUnitAura('UNIT_AURA','target',{})")
    assert build()[1] == 1130, "confirmed removal restores target setup"
    lua.execute("""
        P.InvalidateTargetDebuffs()
        C_UnitAuras.GetUnitAuras=nil
        C_UnitAuras.GetAuraDataByIndex=function(_,index)
            indexReads=indexReads+1
            if index<=40 then return {spellId=999} end
        end
    """)
    assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is None, \
        "a capped index scan cannot establish absence"
    lua.execute("P.InvalidateTargetDebuffs();C_UnitAuras.GetAuraDataByIndex=function() end")
    assert lua.globals().P.GetTargetDebuffState(lua.table_from(ranks)) is False
    print("Target setup: independent class/cast/aura policy, all Mark ranks, aura safety, full queues and both clients passed")


def check_wide_only_sinks():
    lua = create_runtime()
    for setup, sunk, why in (
        ("", False, "without wide-only data the unlisted ability still fills the lead"),
        ("wideOnly[6343]=true", True, "a cleave/AoE-only ability sinks at single target"),
        ("wideOnly[6343]=true;b.simcCtx='cleave'", False, "in cleave context it is ranked normally"),
        ("wideOnly[6343]=true;b.contextOrder='off'", False, "exact ordering is preserved"),
        ("wideOnly[6343]=true;SpellQueue._rotationIsCustom=true", False, "custom lists are preserved"),
        ("wideOnly[6343]=true;pinnedAlwaysShow[6343]=true", False, "an Always Show pin is preserved"),
    ):
        lua.execute("""
            Reset()
            b.inCombat=true;b.leadMode='mylist';b.simcCtx='st'
            entries={{id=78}}
            pool={6343,78}
            cooldown[78]=true
        """ + setup)
        queue = lua.globals().Build()
        assert bool(lua.globals().sunkSet[6343]) == sunk, why
        if not sunk:
            assert queue[1] == 6343, (why, queue[1])
    print("Wide-only abilities: single-target sink, cleave, exact, custom and pinned passed")


def check_left_out():
    lua = create_runtime()
    for setup, shown, why in (
        ("", True, "without left-out data an unlisted ability still fills the queue"),
        ("leftOut={st={[1715]=true}}", False, "a left-out ability is not offered at all"),
        ("leftOut={aoe={[1715]=true}}", True, "left out only in another context: offered here"),
        ("leftOut={st={[1715]=true}};b.contextOrder='off'", True, "exact ordering is preserved"),
        ("leftOut={st={[1715]=true}};SpellQueue._rotationIsCustom=true", True, "custom lists are preserved"),
        ("leftOut={st={[1715]=true}};pinnedAlwaysShow[1715]=true", True, "an Always Show pin is preserved"),
    ):
        lua.execute("""
            Reset()
            b.inCombat=true;b.leadMode='mylist';b.simcCtx='st'
            entries={{id=78}}
            pool={1715,78}
            cooldown[78]=true
        """ + setup)
        queue = lua.globals().Build()
        ids = [queue[i] for i in range(1, 10) if queue[i] is not None]
        assert (1715 in ids) == shown, (why, ids)
    print("Left-out abilities: kept out, other context, exact, custom and pinned passed")


def check_closed_list():
    """A Forever list is closed: a ready class ability the tree names nowhere never fills in while
    the listed rotation waits. Weapon attacks stay; custom, exact order and pins keep it."""
    lua = create_runtime()
    for setup, shown, why in (
        ("", True, "without list data (retail) an unlisted ability still fills the queue"),
        ("named={[78]=true}", False, "an ability the tree names nowhere is not offered"),
        ("named={[78]=true,[1715]=true}", True, "named in some list: offered"),
        ("named={[78]=true};b.contextOrder='off'", True, "exact ordering is preserved"),
        ("named={[78]=true};SpellQueue._rotationIsCustom=true", True, "custom lists are preserved"),
        ("named={[78]=true};pinnedAlwaysShow[1715]=true", True, "an Always Show pin is preserved"),
    ):
        lua.execute("""
            Reset()
            b.inCombat=true;b.leadMode='mylist';b.simcCtx='st'
            entries={{id=78}}
            pool={1715,78}
            cooldown[78]=true
        """ + setup)
        queue = lua.globals().Build()
        ids = [queue[i] for i in range(1, 10) if queue[i] is not None]
        assert (1715 in ids) == shown, (why, ids)
    lua.execute("Reset(); named={}")
    g = lua.globals()
    check = g.SpellQueue._IsLeftOut
    b = g.b
    assert check(2764, 2764, b) is False, "Throw (a weapon attack) stays unlisted"
    assert check(6603, 6603, b) is False, "Attack stays unlisted"
    assert check(100, 100, b) is True, "Charge is the gap closer feature's, not the damage list's"
    lua.execute("named={[1715]=true}")
    assert check(7372, 1715, b) is False, "the pool entry's own rank keeps a named spell"
    print("Closed list: unnamed abilities kept out; weapons, exact, custom and pinned kept")


def check_trash_burst_wait():
    lua = create_runtime()
    for setup, should_wait in (
        ("", True),
        ("procs[1259799]=true", True),
        ("b.ctxEnemies=0", True),
        # Before the pull only a next-swing lead waits: the cooling-down opener leads itself.
        ("b.inCombat=false;b.ctxEnemies=0", "lead"),
        ("b.inCombat=false;targetExists=false;b.ctxEnemies=0", "lead"),
        ("b.inCombat=false;targetDead=true;b.ctxEnemies=0", "lead"),
        ("b.inCombat=false;b.ctxEnemies=3", "lead"),
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
        if should_wait == "lead":
            assert queue[1] == 403 and queue[2] == 1259799, setup
        elif should_wait:
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


def check_charge_before_ranged_pull():
    lua = create_runtime()
    setup = """
        specKey='WARRIOR_F'
        pool={772,7918,100}
        entries={{id=772},{id=7918},{id=100}}
        ranges[772],ranges[7918],ranges[100]=false,true,true
        castTimes[7918]=1000
        damageEstimates[7918]=40
        SpellDB.IsPureSelfAura=function() return false end
        SpellDB.LandsAtTarget=function(id) return id==100 end
        C_Spell.IsSpellHarmful=function() return true end
    """
    cases = [
        ("", [100, 7918, 772], "Charge leads a ranged pull that would leave it unusable"),
        ("pool={772,7918}; entries={{id=772},{id=7918}}", [7918, 772], "without Charge the shot still opens"),
        ("ranges[100]=false", [7918, 772, 100], "out of range Charge does not lead the pull"),
        ("ranges[100]=nil", [100, 7918, 772], "unknown range keeps Charge first"),
        ("unusable[100]=true", [7918, 772, 100], "unusable Charge (in combat) never leads"),
        ("cooldown[100]=true", [7918, 772, 100], "Charge on cooldown never leads"),
        ("b.inCombat=true; ranges[772]=true", [772, 7918, 100], "in combat the list order is kept"),
        ("named={[772]=true,[7918]=true}", [7918, 772],
         "a closed list leaves Charge to the gap closer feature"),
    ]
    for extra, expected, label in cases:
        lua.execute("Reset(); " + setup + extra)
        actual = list(lua.globals().Build().values())
        assert actual == expected, (label, actual, expected)
    print(f"Charge before ranged pull: {len(cases)} cases passed")


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
    start = source.index("function SpellQueue._IsForeverOpener(")
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


def check_priest_wand_fallback():
    lua = create_runtime(real_gates=True)
    for tree in ("shadow", "discipline", "holy"):
        for setup, expected, description in (
            ("", 585, "ready Smite precedes Shoot while Pain is active"),
            ("cooldown[585]=true", 5019, "Shoot remains a fallback when Smite is unavailable"),
            ("pool={5019,585,589};b.contextOrder='off'", 5019, "explicit order is preserved"),
        ):
            lua.execute(f"""
                Reset();specKey='PRIEST_F';entries=classes.PRIEST_F.{tree}.st
                pool={{589,585,5019}};b.inCombat=true;b.leadMode='mylist'
                DotTracker={{IsDotActiveOnCurrentTarget=function(id) return id==589 end}}
                {setup}
                Build()
            """)
            actual = lua.globals().b.recommendedSpells[1]
            assert actual == expected, (tree, description, actual, expected)
    lua.execute("""
        Reset();specKey='PRIEST_F';entries=classes.PRIEST_F.shadow.st
        pool={5019,585,8092};b.inCombat=true;b.leadMode='mylist'
        Build()
        assert(b.recommendedSpells[1]==8092, 'Shadow abilities retain priority over leveling Smite')
    """)
    print("Priest wand fallback: ready Smite, unavailable fallback, Shadow priority and explicit order passed")


def check_next_swing_priority():
    lua = create_runtime()
    cooldown = (ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    start = cooldown.index("local function IsAttackChecked(")
    end = cooldown.index("\nlocal damageBaseline,", start)
    lua.execute("local IsSecretValue=BlizzardAPI.IsSecretValue\n" + cooldown[start:end])
    lua.execute("""
        errors=0
        function geterrorhandler() return function() errors=errors+1 end end
        function SetupHunter()
            Reset();specKey='HUNTER_F';b.inCombat=true;b.leadMode='mylist'
            entries=classes.HUNTER_F.beast_mastery.st
            pool={1978,75,1130,2973,3044}
            ranges={[1978]=true,[75]=true,[1130]=true,[3044]=true}
            queued, running = {}, {[75]=2}
            C_Spell.IsCurrentSpell=function(id) return queued[id] end
            swingFar=false
            SpellQueue._SwingFarOff=function() return swingFar end
            meleeReach={}
            SpellQueue._IsMeleeReach=function(id) return meleeReach[id] == true end
            C_Spell.IsAutoRepeatSpell=function(id) return running[id]==2 end
            DotTracker={IsDotActiveOnCurrentTarget=function(id) return id==1978 or id==1130 end}
        end
        function HunterLead()
            b.recommendedSpells, b.addedSpellIDs, b.spellCount = {}, {}, 0
            b.foreverWaiting = nil
            wipe(sunkSet);wipe(unavailableTier)
            Build()
            b.spellCount=#b.recommendedSpells
            SpellQueue._StageForeverWait(b)
            return b.recommendedSpells[1]
        end
    """)
    for setup, expected, why in (
        ("", 3044, "ready Arcane Shot leads while next-swing reach is unknown"),
        ("ranges[2973]=false", 3044, "ready Arcane Shot leads outside melee"),
        ("procs[2973]=true", 3044, "a proc does not bypass unknown melee reach"),
        # In melee the shots sit inside their minimum range and read out of range.
        ("ranges[2973]=true;ranges[3044]=false", 2973, "confirmed melee admits Raptor Strike"),
        ("ranges[2973]=true", 3044, "a ranged tree keeps a castable shot ahead of melee"),
        ("ranges[2973]=true;queued[2973]=true", 3044, "queued Raptor Strike yields to an actionable shot"),
        ("ranges[2973]=true;queued[2973]=true;procs[2973]=true", 3044,
         "a proc cannot re-promote an already queued next-swing ability"),
        ("ranges[2973]=true;queued[2973]=true;pool={2973,1495};ranges[1495]=true", 1495,
         "queued Raptor Strike yields to usable melee abilities too"),
        ("pool={2973};ranges[2973]=true;queued[2973]=true", 2973,
         "a queued next-swing attack alone holds slot 1 with its swing timer, not WAIT"),
        ("pool={2973};ranges[2973]=true;queued[2973]=false", 2973,
         "the native queue clearing immediately restores the next-swing suggestion"),
        ("pool={2973,1495};ranges[2973]=true;ranges[1495]=true", 2973,
         "a ready next-swing attack keeps its rank"),
        ("pool={2973};ranges[2973]=false;b.landingMelee=true;meleeReach[2973]=true", 2973,
         "a charge in flight: the melee attack ranks for arrival instead of waiting"),
        ("pool={1495};ranges[1495]=false;unusable[1495]=true;b.landingMelee=true;meleeReach[1495]=true", 1495,
         "a charge in flight: a not-yet-usable melee lead keeps slot 1 with its tint, not WAIT"),
        ("pool={1495};ranges[1495]=true;unusable[1495]=true;b.landingMelee=false", -999999999,
         "landed, nothing usable: WAIT as before"),
        ("pool={2973};ranges[2973]=false;unusable[2973]=true;b.landingMelee=true;meleeReach[2973]=true", 2973,
         "a charge in flight: even a next-swing lead keeps slot 1 (the swing starts on arrival)"),
        ("pool={2973};ranges[2973]=false;b.landingMelee=false;meleeReach[2973]=true", -999999999,
         "no charge in flight: out of reach still waits"),
        ("pool={3044,2973};ranges[3044]=false;ranges[2973]=false;b.landingMelee=true;meleeReach[2973]=true",
         2973, "a ranged spell keeps its own out-of-range reading during the charge"),
        ("pool={2973,1495};ranges[2973]=true;ranges[1495]=true;b.ctxDying=true;swingFar=true", 1495,
         "dying target, swing more than a GCD away: the instant finishes first"),
        ("pool={2973,1495};ranges[2973]=true;ranges[1495]=true;b.ctxDying=true;swingFar=false", 2973,
         "dying target, swing close: the next-swing attack keeps its rank"),
        ("pool={2973,1495};ranges[2973]=true;ranges[1495]=true;b.ctxDying=false;swingFar=true", 2973,
         "a healthy target keeps the next-swing attack"),
        ("pool={2973};ranges[2973]=false", -999999999, "in combat an out-of-reach melee lead waits"),
        ("b.inCombat=false;pool={2973};ranges[2973]=false", -999999999,
         "before the pull an out-of-reach next-swing lead waits"),
        ("b.inCombat=false;pool={2973};ranges[2973]=nil", -999999999,
         "before the pull a next-swing lead of unknown reach waits"),
        ("b.inCombat=false;pool={3044};ranges[3044]=false", 3044,
         "before the pull an out-of-reach opener leads with its range tint, not WAIT"),
        ("pool={3044};ranges[3044]=false;b.ctxOutOfMelee=true;cachedGapCloserEngine={InFlight=function() return true end}",
         3044, "a gap closer in flight shows the next ability, not WAIT"),
        ("pool={2973};ranges[2973]=false;b.ctxOutOfMelee=true;cachedGapCloserEngine={InFlight=function() return true end}",
         -999999999, "a next-swing lead still waits while the gap closer is in flight"),
        ("pool={3044};ranges[3044]=false;b.ctxOutOfMelee=false;cachedGapCloserEngine={InFlight=function() return true end}",
         -999999999, "once in melee the flight window no longer lifts WAIT"),
        ("pool={3044};ranges[3044]=false;b.ctxOutOfMelee=true;cachedGapCloserEngine={InFlight=function() return false end}",
         -999999999, "out of melee without a gap closer in flight still waits"),
        ("b.inCombat=false;pool={3044};ranges[3044]=nil", 3044,
         "before the pull an opener of unknown reach leads, not WAIT"),
        ("pool={2973,3044};entries={{id=2973},{id=3044}};SpellQueue._rotationIsCustom=true", 2973,
         "custom ordering is preserved"),
        ("pool={2973,3044};entries={{id=2973},{id=3044}};b.contextOrder='off'", 2973,
         "exact ordering is preserved"),
        ("pool={2973,3044};entries={{id=2973},{id=3044}};b.sinkCooldowns=false", 2973,
         "unavailable-last opt-out is preserved"),
        ("pool={2973,3044};entries={{id=2973},{id=3044}};forever=false", 2973,
         "Retail gains no next-swing policy"),
    ):
        lua.execute("SetupHunter(); " + setup)
        actual = lua.globals().HunterLead()
        assert actual == expected, (why, actual, expected)
    for spell in (78, 845, 6807, 14260):
        lua.execute(f"SetupHunter();pool={{{spell},3044}};entries={{{{id={spell}}},{{id=3044}}}}")
        assert lua.globals().HunterLead() == 3044, ("shared next-swing melee admission", spell)
    # A queued next-swing attack is never displaced by another one (Cleave queued, Heroic Strike
    # ready): pressing the second would only swap it for the first.
    lua.execute("SetupHunter();pool={845,78};entries={{id=845},{id=78}};"
                "ranges[845],ranges[78]=true,true;queued[845]=true")
    assert lua.globals().HunterLead() == 845, "the queued Cleave keeps its swing"
    assert 78 not in list(lua.eval("b.recommendedSpells").values())[:1], "Heroic Strike does not lead over it"
    lua.execute("SetupHunter();pool={845,78};entries={{id=845},{id=78}};ranges[845],ranges[78]=true,true")
    assert lua.globals().HunterLead() == 845, "with nothing queued the list's order stands"
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    for name in ("_ClearSituationMemory", "NoteLeadEvent", "OnTargetChanged"):
        if name == "NoteLeadEvent":
            lua.execute("SpellQueue._leadHold = {}; GetTime = GetTime or function() return 0 end")
        start = source.index(f"function SpellQueue.{name}(")
        lua.execute(source[start:source.index("\nend", start) + len("\nend")])
    lua.execute("""
        BlizzardAPI.IsSpellAvailable=function(id) return id==75 end
        BlizzardAPI.GetCachedSpellInfo=function() return shotInfo end
        BlizzardAPI.GetMeleeActivityTime=function() return activityAt end
        SpellDB.IsTargetWithin=function(yards)
            if yards==5 then return meleeRead end
            return outerRead
        end
        function SetupHint()
            SetupHunter()
            shotInfo={minRange=8,maxRange=35}
            meleeRead,outerRead=nil,nil
        end
        function LoseShootingRange()
            ranges[75],ranges[1978],ranges[3044]=false,false,false
            b.now=b.now+0.1
        end
    """)
    for setup, hint, expected, why in (
        ("", True, 2973, "a shooting-range loss cues the ready next swing"),
        ("queued[2973]=true", True, 2973, "a pending swing holds slot 1 with its swing timer"),
        ("cooldown[2973]=true", True, -999999999, "a positioning hint does not bypass cooldown"),
        ("starved[2973]=true", True, -999999999, "a positioning hint does not bypass resources"),
        ("unusable[2973]=true", True, -999999999, "a positioning hint does not bypass cast conditions"),
        ("ranges[2973]=false", True, -999999999, "the ability's confirmed rejection wins"),
        ("meleeRead=false", False, -999999999, "confirmed non-melee reach clears the hint"),
        ("outerRead=false", False, -999999999, "confirmed beyond-maximum range clears the hint"),
        ("ranges[75]=nil", False, -999999999, "unknown shooting range clears the hint"),
        ("ranges[75]=secret", False, -999999999, "secret shooting range clears the hint"),
        ("shotInfo.minRange=0", False, -999999999, "a zero-minimum weapon cannot imply approach"),
        ("shotInfo.minRange=secret", False, -999999999, "secret endpoints cannot support the hint"),
        ("shotInfo.maxRange=nil", False, -999999999, "unknown maximum cannot support the hint"),
        ("SpellQueue.OnTargetChanged()", False, -999999999, "a new target needs a new transition"),
        ("SpellQueue._ClearSituationMemory()", False, -999999999, "combat reset clears history"),
        ("b.now=103.01", False, -999999999, "a stale positive does not create a transition"),
        ("SpellQueue._rotationIsCustom=true", False, None, "custom ordering does not use the hint"),
        ("b.contextOrder='off'", False, None, "exact ordering does not use the hint"),
        ("b.sinkCooldowns=false", False, None, "unavailable-last opt-out does not use the hint"),
        ("forever=false", False, None, "Retail does not use the hint"),
        ("targetDead=true", False, None, "dead targets clear history"),
        ("hostile=false", False, None, "friendly targets clear history"),
        ("targetExists=false", False, None, "target loss clears history"),
        ("b.inCombat=false", False, None, "out-of-combat builds clear history"),
    ):
        lua.execute("SetupHint();HunterLead();LoseShootingRange();" + setup)
        actual = lua.globals().HunterLead()
        assert lua.globals().b.nearMeleeHint == hint, (why, "hint")
        if expected is not None:
            assert actual == expected, (why, actual, expected)
    lua.execute("""
        SetupHint();HunterLead();LoseShootingRange()
        assert(HunterLead()==2973)
        for cycle=1,3 do
            queued[2973]=true
            assert(HunterLead()==2973)
            queued[2973]=false;cooldown[2973]=true
            for seconds=1,6 do
                b.now=b.now+1
                assert(HunterLead()==SpellQueue.WAIT_SENTINEL)
            end
            cooldown[2973]=false
            assert(HunterLead()==2973,
                'continuous close-range hints must survive cooldown and restore the next swing')
        end
    """)
    lua.execute("""
        SetupHint();LoseShootingRange();HunterLead()
        assert(not b.nearMeleeHint, 'starting out of shooting range is not a transition')
        outerRead=true;HunterLead()
        assert(b.nearMeleeHint, 'a compatible current range bracket supports a near cue')
        SetupHint();HunterLead();LoseShootingRange()
        assert(HunterLead()==2973)
        b.now=103.1;assert(HunterLead()==2973, 'observations include their three-second boundary')
        b.now=103.11;assert(HunterLead()==2973, 'fresh consistent readings renew the hint')
        b.now=106.12;HunterLead()
        assert(not b.nearMeleeHint, 'a stale observation gap expires the hint')
        b.now=106.13;HunterLead()
        assert(not b.nearMeleeHint, 'negative readings alone cannot restart an expired episode')
        SetupHint();HunterLead();LoseShootingRange();HunterLead()
        ranges[75]=nil;HunterLead();ranges[75]=false;HunterLead()
        assert(not b.nearMeleeHint, 'unknown range interrupts continuity instead of rearming')
        SetupHint();HunterLead();LoseShootingRange();HunterLead()
        ranges[75],ranges[3044]=true,true
        assert(HunterLead()==3044 and not b.nearMeleeHint, 'restored shooting range clears the hint')
        assert(ranges[2973]==nil, 'the hint does not fabricate an ability-range verdict')
    """)
    for setup, hint, expected, why in (
        ("", True, 2973, "fresh melee activity arms a melee-start pull without a shooting transition"),
        ("queued[2973]=true", True, 2973, "a pending next swing holds slot 1 with its swing timer"),
        ("cooldown[2973]=true", True, -999999999, "activity cannot bypass cooldown"),
        ("starved[2973]=true", True, -999999999, "activity cannot bypass resources"),
        ("unusable[2973]=true", True, -999999999, "activity cannot bypass usability"),
        ("activityAt=b.now-3", True, 2973, "activity includes the freshness boundary"),
        ("activityAt=b.now-3.01", False, -999999999, "stale activity cannot arm the cue"),
        ("activityAt=b.now+0.01", False, -999999999, "future activity cannot arm the cue"),
        ("activityAt=secret", False, -999999999, "secret activity remains unknown"),
        ("meleeRead=false", False, -999999999, "confirmed non-melee beats recent activity"),
        ("outerRead=false", False, -999999999, "confirmed beyond-maximum beats recent activity"),
        ("ranges[75]=true", False, None, "restored shooting range beats recent activity"),
        ("ranges[75]=nil", True, 2973, "activity does not require readable shooting range"),
        ("BlizzardAPI.IsSpellAvailable=function() return false end", True, 2973,
         "melee classes without a ranged weapon can use activity"),
        ("SpellQueue._rotationIsCustom=true", False, None, "custom ordering does not use activity"),
        ("b.contextOrder='off'", False, None, "exact ordering does not use activity"),
        ("b.sinkCooldowns=false", False, None, "unavailable-last opt-out does not use activity"),
        ("forever=false", False, None, "Retail does not use activity"),
        ("targetDead=true", False, None, "dead targets do not use activity"),
        ("hostile=false", False, None, "friendly targets do not use activity"),
        ("targetExists=false", False, None, "target loss does not use activity"),
        ("b.inCombat=false", False, None, "out-of-combat ordering does not use activity"),
    ):
        lua.execute("BlizzardAPI.IsSpellAvailable=function(id) return id==75 end;"
                    "SetupHint();LoseShootingRange();activityAt=b.now;" + setup)
        actual = lua.globals().HunterLead()
        assert lua.globals().b.nearMeleeHint == hint, (why, "activity hint")
        if expected is not None:
            assert actual == expected, (why, actual, expected)
    lua.execute("""
        BlizzardAPI.IsSpellAvailable=function(id) return id==75 end
        SetupHint();LoseShootingRange();activityAt=b.now
        queueProbeEnabled=true;queueProbeEntries={}
        assert(HunterLead()==2973 and SpellQueue._nearMeleeState.source=='melee-activity')
        local probe=queueProbeEntries[2973]
        assert(probe and probe:find('bucket=normal',1,true)
            and probe:find('usable=true',1,true) and probe:find('notEnough=false',1,true)
            and probe:find('meleeUnconfirmed=false',1,true)
            and probe:find('nearMeleeHint=true',1,true),
            'ready melee activity must be visible in the queue decision reason')
        queueProbeEnabled=false
        assert(SpellQueue._nearMeleeState.hintAt==nil, 'activity must not seed a persistent range-loss episode')
        b.now=b.now+3.01
        assert(HunterLead()==SpellQueue.WAIT_SENTINEL and not b.nearMeleeHint)
        b.now=b.now+0.01
        assert(HunterLead()==SpellQueue.WAIT_SENTINEL, 'negative range alone cannot renew expired activity')
        activityAt=b.now
        assert(HunterLead()==2973)
        for cycle=1,3 do
            queued[2973]=true
            assert(HunterLead()==2973)
            queued[2973]=false;cooldown[2973]=true
            for seconds=1,6 do
                b.now=b.now+1;activityAt=b.now
                assert(HunterLead()==SpellQueue.WAIT_SENTINEL)
            end
            cooldown[2973]=false
            assert(HunterLead()==2973, 'fresh melee swings restore a ready next swing after each cooldown')
        end
        assert(ranges[2973]==nil, 'activity never fabricates actual range')
    """)
    for spell in (78, 845, 6807, 14260):
        lua.execute(f"SetupHint();LoseShootingRange();activityAt=b.now;pool={{{spell},3044}};"
                    f"entries={{{{id={spell}}},{{id=3044}}}}")
        assert lua.globals().HunterLead() == spell, ("shared melee activity ordering", spell)
    lua.execute("""
        local oldStub=LibStub
        LibStub=setmetatable({NewLibrary=function() return {} end},
            {__call=function(_,name)
                if name=='JustAC-BlizzardAPI' then return BlizzardAPI end
                return oldStub(name)
            end})
        activityFrames={}
        function CreateFrame()
            local f={events={},RegisterEvent=function(self,event) self.events[event]=true end,
                RegisterUnitEvent=function(self,event) self.events[event]=true end,
                SetScript=function(self,_,fn) self.callback=fn end}
            activityFrames[#activityFrames+1]=f
            return f
        end
        function FireActivityEvent(event,...)
            for _,f in ipairs(activityFrames) do if f.events[event] then f.callback(f,event,...) end end
        end
        function GetTime() return b.now end
        function UnitGUID() return 'melee-target' end
        savedReady=BlizzardAPI.IsSpellReady
    """)
    lua.execute((ROOT / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8"))
    lua.execute("""
        BlizzardAPI.IsSpellReady=savedReady
        SetupHint();LoseShootingRange();queued[6603]=true
        assert(HunterLead()==SpellQueue.WAIT_SENTINEL, 'melee-start repro has no shooting transition')
        b.inCombat=false;FireActivityEvent('PLAYER_SWING',2,0)
        b.inCombat=true;SpellQueue.ResetNearMeleeHint()
        assert(HunterLead()==2973, 'real tracker retains an opening swing across combat entry')
        for cycle=1,3 do
            queued[2973]=true;assert(HunterLead()==2973)
            queued[2973]=false;cooldown[2973]=true
            for seconds=1,6 do
                b.now=b.now+1
                if seconds%2==0 then FireActivityEvent('PLAYER_SWING',2,0) end
                assert(HunterLead()==SpellQueue.WAIT_SENTINEL)
            end
            cooldown[2973]=false
            assert(HunterLead()==2973, 'real swing events recover the melee-start queue after cooldown')
        end
        FireActivityEvent('PLAYER_TARGET_CHANGED');SpellQueue.OnTargetChanged()
        assert(HunterLead()==SpellQueue.WAIT_SENTINEL, 'a target swap cannot inherit real melee activity')
        assert(ranges[2973]==nil, 'real activity never changes effective ability range')
    """)
    print("Near-melee hints: cooldown cycles, continuous observations, gaps, brackets, queued state and range/reset controls passed")
    print("Next-swing priority: real queued-state reader, Hunter shots, melee admission and explicit settings passed")


def check_resource_wait_lead():
    """A priority list holds on a shared resource: a lower-priority spender does not take the rage
    a higher-priority one waits on, so the next press on rage is its highest-priority wait. A wait
    blocked by its own condition holds nothing and trails the waits that clear on their own."""
    lua = create_runtime(real_gates=True)
    lua.execute("""
        function GetTime() return 100 end
        rageCost = {[12294]=30, [78]=15, [772]=10, [6343]=20}
        function Setup()
            Reset();specKey='WARRIOR_F';b.inCombat=true;b.leadMode='mylist'
            entries={{id=12294,gates={}},{id=78,gates={}}}
            pool={12294,78}; ranges={[12294]=true,[78]=true}; talents={}
            starved[12294], starved[78] = true, true
            C_Spell.GetSpellPowerCost=function(id) return {{type=1, cost=rageCost[id] or 0}} end
            wipe(SpellQueue._continuousCost)
            IsSpenderSpell = function() return true end
        end
        function Lead()
            b.recommendedSpells, b.addedSpellIDs, b.spellCount = {}, {}, 0
            wipe(sunkSet);wipe(unavailableTier)
            Build()
            return b.recommendedSpells[1]
        end
    """)
    for setup, expected, why in (
        ("", 12294, "both wait on rage: Mortal Strike ranks higher, so it is the next press"),
        ("entries[2].gates={{t='known',id=999}}", 12294,
         "a Heroic Strike blocked by its own condition does not jump the wait"),
        ("starved[78]=nil", 12294, "Heroic Strike holds its rage for Mortal Strike, which ranks above it"),
        ("starved[78]=nil; cooldown[12294]=true", 78, "a higher spender on cooldown holds nothing"),
        ("starved[78]=nil; starved[12294]=nil", 12294, "both affordable: priority as ever"),
        # Three targets: Thunder Clap above Heroic Strike gets its rage first.
        ("entries={{id=6343,gates={}},{id=78,gates={}}};pool={6343,78};ranges[6343]=true;"
         "starved[6343]=true;starved[78]=nil", 6343, "Thunder Clap waits on rage: Heroic Strike holds"),
        # Thunder Clap held at one target (its own condition) never heads the waits, even when
        # listed first: waiting does not make it the next press.
        ("entries={{id=6343,gates={{t='known',id=999}}},{id=12294,gates={}},{id=78,gates={}}};"
         "pool={6343,12294,78};ranges[6343]=true;starved[6343]=true", 12294,
         "a condition-blocked wait trails the waits that clear on their own"),
        # Offered only when its conditions hold (w): holding them and short of rage, Heroic
        # Strike is a cost wait like any other and heads the waits over a blocked Thunder Clap.
        ("entries={{id=6343,gates={{t='known',id=999}}},{id=78,w=true,gates={}}};"
         "pool={6343,78};ranges[6343]=true;starved[6343]=true", 78,
         "a w entry whose conditions hold waits on its cost"),
        ("entries={{id=6343,gates={{t='known',id=999}}},{id=78,w=true,gates={{t='known',id=998}}}};"
         "pool={6343,78};ranges[6343]=true;starved[6343]=true", 6343,
         "a w entry whose conditions fail trails even a condition wait"),
        # Range unknown while unaffordable: the target's melee distance answers for a melee attack.
        ("entries={{id=6343,gates={{t='known',id=999}}},{id=78,gates={}}};"
         "pool={6343,78};ranges[6343]=true;ranges[78]=nil;starved[6343]=true;"
         "SpellDB.IsTargetWithin=function() return true end;"
         "SpellQueue._IsMeleeReach=function(id) return id==78 end;"
         "SpellDB.NEXT_SWING_SPELLS={[78]=true};BlizzardAPI.IsForever=function() return true end", 78,
         "unknown range in melee distance: Heroic Strike's reach is confirmed"),
    ):
        lua.execute("Setup(); " + setup)
        actual = lua.eval("Lead()")
        assert actual == expected, (why, actual, expected)
    print("Resource wait lead: lower spenders hold for a higher rage wait; condition waits trail")


def check_instant_when_hit():
    """Frost's Fire Blast ("a cast would not finish as planned"): leads over Frostbolt while you
    are being hit or the target is confirmed nearly dead; otherwise Frostbolt leads."""
    lua = create_runtime(real_gates=True)
    lua.execute("""
        function GetTime() return 100 end
        function Setup()
            Reset();specKey='MAGE_F';b.inCombat=true;b.leadMode='mylist'
            entries=classes.MAGE_F.frost.st
            pool={2136,116}; ranges={[2136]=true,[116]=true}; talents={}
            beingHit, health = false, nil
            SpellQueue._BeingHit = function() return beingHit end
            BlizzardAPI.IsUnitHealthBelow = function() return health end
        end
        function Lead()
            b.recommendedSpells, b.addedSpellIDs, b.spellCount = {}, {}, 0
            wipe(sunkSet);wipe(unavailableTier)
            Build()
            return b.recommendedSpells[1]
        end
    """)
    for setup, expected, why in (
        ("", 116, "at range, not hit: Frostbolt"),
        ("beingHit=true", 2136, "being hit: the instant avoids pushback"),
        ("health=true", 2136, "target nearly dead: the instant finishes it"),
        ("health=nil; beingHit=false", 116, "unreadable health is not dying"),
        ("beingHit=true; cooldown[2136]=true", 116, "Fire Blast on cooldown: Frostbolt"),
    ):
        lua.execute("Setup(); " + setup)
        actual = lua.eval("Lead()")
        assert actual == expected, (why, actual, expected)
    print("Instant when hit: Fire Blast leads while being hit or on a dying target; Frostbolt otherwise")


def check_confirmed_offer():
    """Hamstring's "main spender learned OR target dying" holds only when confirmed: its execute
    alternative is required, so an unreadable target health is not dying."""
    lua = create_runtime(real_gates=True)
    lua.execute("""
        function GetTime() return 100 end
        function Setup()
            Reset();specKey='WARRIOR_F';b.inCombat=true;b.leadMode='mylist'
            entries={{id=1715,w=true,gates={{t="any",g={{t="known",id=12294},
                                                       {t="execute",op="<",pct=20,required=true}}}}},
                     {id=772,gates={}}}
            pool={1715,772}; ranges={[1715]=true,[772]=true}; talents={}
            health=nil
            BlizzardAPI.IsUnitHealthBelow=function() return health end
        end
        function Lead()
            b.recommendedSpells, b.addedSpellIDs, b.spellCount = {}, {}, 0
            wipe(sunkSet);wipe(unavailableTier)
            Build()
            return b.recommendedSpells[1]
        end
    """)
    for setup, expected, why in (
        ("", 772, "health unknown: the condition is not confirmed, so Hamstring waits"),
        ("health=false", 772, "a healthy target and no main spender: Hamstring waits"),
        ("health=true", 1715, "a dying target confirms it: Hamstring finishes"),
        ("talents[12294]=true", 1715, "a main spender learned confirms it"),
        ("entries[1].gates[1].g[2].required=nil", 1715, "without required an unknown health leaks open"),
    ):
        lua.execute("Setup(); " + setup)
        actual = lua.eval("Lead()")
        assert actual == expected, (why, actual, expected)
    print("Confirmed offers: an unreadable dying check keeps Hamstring held; confirmed conditions release it")


def check_buff_upkeep():
    lua = create_runtime(real_gates=True)
    lua.execute("""
        function GetTime() return 100 end
        function SetupShout()
            Reset();specKey='WARRIOR_F';b.inCombat=true;b.leadMode='mylist'
            entries={{id=6673,gates={{t="buff",id=6673,dur=180,neg=true}}},{id=772,gates={}}}
            pool={6673,772}
            ranges={[6673]=true,[772]=true}
            buffs, remaining, castAge = {[6673]=true}, {[6673]=100}, {}
            BlizzardAPI.GetBuffWindowRemaining=function(id) return remaining[id] end
            BlizzardAPI.GetOwnCastAge=function(id) return castAge[id] end
            BlizzardAPI.IsSpellAvailable=function() return true end
            C_Spell.GetSpellPowerCost=function(id) return {{type=costType[id] or 1, cost=10}} end
            costType={}
            combatStartedAt=90
            b.now=100;b.ctxDying=true;b.ctxEnemies=1
        end
        function Queue()
            b.recommendedSpells, b.addedSpellIDs, b.spellCount = {}, {}, 0
            wipe(sunkSet);wipe(unavailableTier)
            AuraClock.BeginQueueHolds()
            Build()
            AuraClock.EndQueueHolds()
            b.spellCount=#b.recommendedSpells
            return table.concat(b.recommendedSpells, ",")
        end
        function FightEnd()
            Queue()
            SpellQueue._StageFightEndRefresh(b, pool)
            return table.concat(b.recommendedSpells, ",")
        end
    """)
    for setup, expected, why in (
        ("", "772", "a shout with more than the fight horizon left leaves the queue"),
        ("remaining[6673]=10", "772,6673", "inside the horizon it stays sunk"),
        ("remaining[6673]=nil", "772,6673", "unknown time left stays sunk: never hidden on a guess"),
        ("buffs[6673]=false", "6673,772", "a missing shout leads at its rank"),
        ("SpellQueue._rotationIsCustom=false;b.sinkCooldowns=false", "6673,772",
         "unavailable-last opt-out keeps the exact order"),
    ):
        lua.execute("SetupShout(); " + setup)
        assert lua.eval("Queue()") == expected, (why, lua.eval("Queue()"), expected)
    # The sunk shout carries its aura to the icon: the aura id for the engine pass-through and
    # its full duration, so the icon reads the plain window when it draws.
    lua.execute("SetupShout(); remaining[6673]=10; Queue()")
    kind, aura, dur = lua.eval("AuraClock.Resolve(6673, true)")
    assert kind == "buff" and aura == 6673 and dur == 180
    lua.execute("SetupShout(); remaining[6673]=nil; Queue()")
    kind, aura, dur = lua.eval("AuraClock.Resolve(6673, true)")
    assert kind == "buff" and aura == 6673, "unknown time left: still held, drawn by the engine or not at all"
    assert lua.eval("AuraClock.Resolve(6673, false)") is None, "queue holds are for queue icons only"
    assert lua.eval("AuraClock.Resolve(772, true)") is None, "an entry no aura holds draws its own cooldown"
    for setup, lead, why in (
        ("", 772, "dying last target, shout up with 100s left: not needed, no refresh"),
        ("remaining[6673]=10", 6673, "dying last target, shout nearly out: leftover rage refreshes it"),
        ("remaining[6673]=nil", 6673, "unknown time left: refresh, as before"),
        ("buffs[6673]=false;remaining[6673]=nil", 6673, "shout missing: refresh"),
        ("castAge[6673]=30;remaining[6673]=10", 6673, "cast before this fight, nearly out: refresh"),
        ("castAge[6673]=30", 772, "cast before this fight, plenty left: no refresh"),
        ("castAge[6673]=5", 772, "already cast this fight: no GCD spent"),
        ("b.ctxDying=false", 772, "a healthy target keeps the rotation"),
        ("b.ctxEnemies=2", 772, "more enemies: the fight is not ending"),
        ("b.ctxEnemies=nil", 772, "unknown enemy count"),
        ("starved[6673]=true", 772, "not affordable now"),
        ("costType[6673]=0", 772, "mana does not drain out of combat: the pull checklist covers it"),
        ("cooldown[6673]=true", 772, "not ready"),
        ("blacklisted[6673]=true", 772, "blacklist honored"),
        ("entries[1].gates[1].dur=10", 772, "a short rotation buff is not upkeep"),
        ("b.inCombat=false", 772, "out of combat"),
        ("combatStartedAt=nil", 772, "unknown fight start"),
        ("SpellQueue._rotationIsCustom=true", 772, "custom order"),
    ):
        lua.execute("SetupShout(); " + setup)
        actual = lua.eval("FightEnd()")
        assert int(actual.split(",")[0]) == lead, (why, actual, lead)
    print("Buff upkeep: hidden while up beyond the fight horizon, aura clock carried, end-of-fight refresh passed")


def main():
    check_next_swing_priority()
    check_confirmed_offer()
    check_instant_when_hit()
    check_resource_wait_lead()
    check_buff_upkeep()
    check_priest_wand_fallback()
    check_queue_fast_paths()
    check_spellbook_proc_pipeline()
    check_shared_proc_stage()
    check_wide_only_sinks()
    check_left_out()
    check_closed_list()
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
        # A wait that ends within one global cooldown keeps the entry's place (Forever).
        ("b.inCombat = true; stacks = 5; cooldown[403] = true", [8042, 403], "a real cooldown sinks"),
        ("b.inCombat = true; stacks = 5; cooldown[403] = true; briefWait[403] = true", [403, 8042],
         "a brief wait keeps its place"),
        ("b.inCombat = true; stacks = 5; cooldown[403] = true; briefWait[403] = false", [8042, 403],
         "a longer wait still sinks"),
        ("b.inCombat = true; stacks = 5; cooldown[403] = true; briefWait[403] = nil", [8042, 403],
         "an unanswerable wait still sinks"),
        ("forever = false; b.inCombat = true; stacks = 5; cooldown[403] = true; briefWait[403] = true",
         [8042, 403], "retail ordering unchanged"),
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
        cases.append((f"specKey = '{cls}_F'", [403, 8042], f"{cls} opener follows its list, not its class"))
    cases.extend([
        ("castTimes[403] = 0", [8042, 403], "an instant gains nothing from the pre-pull window"),
        ("castTimes[403] = nil", [8042, 403], "unknown cast time is not a hardcast"),
        ("unpriced[403] = true", [8042, 403], "an unpriced spell is not an opener"),
        ("entries = {{id=8042, gates={}}, {id=403, gates={{t='stack',id=408505,op='>=',n=5}}}}",
         [8042, 403], "a stack requirement not marked castOnly is never waived"),
        ("entries = {{id=8042, gates={}}, {id=403, gates={{t='stack',id=408505,op='>=',n=5,castOnly=true}}}}",
         [403, 8042], "a castOnly requirement is waived before the pull"),
    ])
    priest = "specKey = 'PRIEST_F'; pool = {589, 585}; entries = {{id=589}, {id=585}}; "
    cases.extend([
        (priest, [585, 589], "Priest opens with Smite"),
        (priest + "pool = {591, 589}", [591, 589], "higher Smite ranks share the opener"),
        (priest + "b.inCombat = true", [589, 585], "Shadow Word: Pain leads once in combat"),
        (priest + "cooldown[585] = true", [589, 585], "unready Smite never leads"),
        (priest + "forever = false", [589, 585], "retail has no Smite opener"),
    ])
    nukes = (priest + "pool = {589, 585, 14914, 8092}; "
             "entries = {{id=589}, {id=585}, {id=14914}, {id=8092}}; "
             "hits = {[585]=40, [14914]=90, [8092]=70}; ")
    # One cast opens the pull; the other candidates keep their list rank, so slot 2 names what
    # follows the opener once the fight starts (Shadow Word: Pain, first on the list).
    cases.extend([
        (nukes, [14914, 589, 585, 8092], "biggest estimated hit opens; the list follows"),
        (nukes + "hits[14914] = 60", [8092, 589, 585, 14914], "a bigger faster hit beats a slower cast"),
        (nukes + "hits[14914] = nil", [585, 589, 14914, 8092],
         "one unknown estimate: the best-ranked candidate opens"),
        (nukes + "cooldown[8092] = true", [14914, 589, 585, 8092], "an unready nuke never opens"),
        (nukes + "b.inCombat = true", [589, 585, 14914, 8092], "combat order returns after the pull"),
    ])
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
         [1752, 2098], "another blocking gate stays blocking: a condition wait trails the builder"),
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
         [1752, 2098], "an imported upper bound is no points shortfall, but still a condition wait"),
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
        (rogue + "points=0; b.inCombat=false", [1752, 2098], "live OOC target: the opener leads, not WAIT"),
        (rogue + "points=0; b.inCombat=false; targetExists=false", [1752, 2098], "no-target OOC preview unchanged"),
        (rogue + "points=0; b.inCombat=false; hostile=false", [1752, 2098], "friendly OOC target unchanged"),
        (rogue + "points=0; b.inCombat=false; targetDead=true", [1752, 2098], "dead OOC target unchanged"),
        (rogue + "points=0; b.inCombat=false; targetDead=secret", [1752, 2098], "unknown alive status does not show OOC WAIT"),
        (rogue + "points=0; forever=false", [1752, 2098], "retail does not gain synthetic WAIT"),
        (rogue + "points=0; b.contextOrder='off'", [2098, 1752], "exact source order unchanged"),
        (rogue + "points=0; b.sinkCooldowns=false", [2098, 1752], "unavailable-last opt-out unchanged"),
        (rogue + "points=0; starved[1752]=nil", [1752, 2098], "usable builder removes WAIT"),
        ("""specKey='HUNTER_F'; pool={1978,3044,2973};
            entries={{id=1978},{id=3044},{id=2973}};
            ranges[1978]=false; ranges[3044]=false; ranges[2973]=nil; b.inCombat=true""",
         [wait, 1978, 3044, 2973], "unknown next-swing reach cannot replace WAIT when ranged attacks are too close"),
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
        other = 2973 if filler == 75 else 589 if filler == 5019 else 78
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
    check_target_setup_openers()
    check_positioning_openers()
    check_charge_before_ranged_pull()
    main()
