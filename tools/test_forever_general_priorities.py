# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
from pathlib import Path

from wow_stubs import LuaRuntime

from gen_forever_rotations import (
    Conv, UNK, actions_of, on_enemy, tier_lists,
)
from test_forever_openers import create_runtime


def check_pushback_events():
    root = Path(__file__).resolve().parent.parent
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        BlizzardAPI = {IsSecretValue=function(v) return v == "secret" end}
        IsSecretValue = BlizzardAPI.IsSecretValue
        SpellQueue = {NotePushback=function() noted = noted + 1 end,
            NoteIncomingHit=function() hits = hits + 1; return fresh end}
        JustAC = {MarkQueueDirty=function() dirty = dirty + 1 end}
        function UnitAffectingCombat() return combat end
        function UnitCastingInfo()
            if casting then return "cast", nil, nil, nil, nil, nil, nil, false end
        end
        function UnitChannelInfo() end
        function CreateFrame()
            frame = {
                RegisterUnitEvent=function() end, RegisterEvent=function() end,
                SetScript=function(self, _, handler) self.handler = handler end,
            }
            return frame
        end
    """)
    core = (root / "JustAC.lua").read_text(encoding="utf-8")
    start = core.index("function JustAC:OnPlayerCastDelayed")
    end = core.index("\nend", start) + len("\nend")
    lua.execute(core[start:end])
    start = core.index("function JustAC:OnPlayerCombatHit")
    lua.execute(core[start:core.index("\nend", start) + len("\nend")])
    assert 'uf:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")' in core
    assert 'uf:RegisterUnitEvent("UNIT_COMBAT", "player")' in core
    lua.execute("""
        hits, dirty, fresh = 0, 0, true
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "WOUND", "")
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "WOUND", "CRITICAL")
        assert(hits == 2 and dirty == 2, 'unabsorbed hits count')
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "WOUND", "ABSORB")
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "DODGE", "")
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "target", "WOUND", "")
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "secret", "")
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "WOUND", "secret")
        assert(hits == 2, 'absorbed, avoided, other-unit and unreadable events do not count')
        fresh = false
        JustAC:OnPlayerCombatHit("UNIT_COMBAT", "player", "WOUND", "")
        assert(hits == 3 and dirty == 2, 'a hit inside the window does not rebuild again')
    """)
    lua.execute("""
        noted, dirty, combat = 0, 0, true
        JustAC:OnPlayerCastDelayed("UNIT_SPELLCAST_DELAYED", "player")
        JustAC:OnPlayerCastDelayed("UNIT_SPELLCAST_DELAYED", "target")
        JustAC:OnPlayerCastDelayed("UNIT_SPELLCAST_DELAYED", "secret")
        combat = false
        JustAC:OnPlayerCastDelayed("UNIT_SPELLCAST_DELAYED", "player")
        assert(noted == 1 and dirty == 1)
    """)
    state = (root / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    first = state[state.index("local targetCastInterruptible ="):state.index("local function SuggestedCCEntry")]
    second = state[state.index("local function InitTargetCastTracking()"):
                   state.index("-- Secret-aware display sinks")]
    lua.execute(first + second + """
        InitTargetCastTracking()
        casting = false
        frame.handler(frame, "PLAYER_TARGET_CHANGED")
        assert(not BlizzardAPI.HasTargetCastSinceSelected())
        frame.handler(frame, "UNIT_SPELLCAST_START", "target")
        assert(BlizzardAPI.HasTargetCastSinceSelected())
        frame.handler(frame, "UNIT_SPELLCAST_STOP", "target")
        assert(BlizzardAPI.HasTargetCastSinceSelected())
        frame.handler(frame, "PLAYER_TARGET_CHANGED")
        assert(not BlizzardAPI.HasTargetCastSinceSelected())
        casting = true
        frame.handler(frame, "PLAYER_TARGET_CHANGED")
        assert(BlizzardAPI.HasTargetCastSinceSelected())
    """)


def check_pushback_priority():
    lua = create_runtime(real_gates=True)
    lua.execute("""
        clock = 100
        function GetTime() return clock end
        function geterrorhandler() return function(e) error(e) end end
        function UnitIsPlayer() return targetPlayer end
        function UnitPlayerControlled() return targetControlled end
        BlizzardAPI.IsTargetBoss = function() return targetBoss end
        BlizzardAPI.GetCachedSpellInfo = function(id)
            if times[id] == nil then return nil end
            return {castTime=times[id]}
        end
        BlizzardAPI.IsSpellAvailable = function(id) return not unavailable[id] end
        BlizzardAPI.GetTargetCastInterruptState = function() return targetCasting end
        BlizzardAPI.HasTargetCastSinceSelected = function() return targetHasCast end
        SpellDB.IsChanneled = function(id) return channels[id] == true end
        SpellDB.IsTargetDot = function(id) return dots[id] == true end
        SpellDB.IsInterruptTypeSpell = function(id) return RotationImport.RankBase(id) == 8042 end
        SpellDB.GetForeverAbilityRole = function(id)
            if RotationImport.RankBase(id) == 8042 then return "utility" end
        end
        local originalReady, originalUsable = BlizzardAPI.IsSpellReady, BlizzardAPI.IsSpellUsable
        function SetupPushback()
            Reset()
            BlizzardAPI.IsSpellReady, BlizzardAPI.IsSpellUsable = originalReady, originalUsable
            SpellQueue.ResetPushback()
            clock = 100
            times = {[403]=2500,[8042]=0,[8044]=0,[8056]=0,[2136]=0,[15237]=0,[120]=0}
            unavailable, channels, dots, syntheticProcs = {}, {}, {}, {}
            targetCasting, targetHasCast = false, false
            targetPlayer, targetControlled, targetBoss = false, false, false
            C_Spell.IsSpellHarmful = function() return true end
            entries = {{id=403,gates={}}, {id=8056,gates={}},
                       {id=2136,gates={}}, {id=15237,gates={}}, {id=120,gates={}}}
            pool = {403,8042}
            b.inCombat, b.now, b.contextOrder = true, 100, "simc"
            b.recommendedSpells, b.spellCount = {403}, 1
            ranges = setmetatable({}, {__index=function() return true end})
        end
        function PushbackResult()
            SpellQueue._StagePushback(b, pool)
            return b.recommendedSpells[1]
        end
    """)

    def check(setup, expected, description):
        lua.globals().SetupPushback()
        lua.execute(setup)
        actual = lua.globals().PushbackResult()
        assert actual == expected, (description, actual, expected)

    check("", 403, "no observed pushback")
    check("SpellQueue.NotePushback()", 8042, "short interrupt fills when no caster observed")
    check("SpellQueue.NotePushback(); pool={403,8044}", 8044, "ranked Earth Shock")
    check("SpellQueue.NotePushback(); targetCasting=true", 403, "active target cast")
    check("SpellQueue.NotePushback(); targetHasCast=true", 403, "previous target cast")
    check("SpellQueue.NotePushback(); targetCasting=nil", 403, "unknown cast state")
    check("SpellQueue.NotePushback(); targetPlayer=true", 403, "player target")
    check("SpellQueue.NotePushback(); targetControlled=true", 403, "player-controlled target")
    check("SpellQueue.NotePushback(); targetBoss=true", 403, "boss target")
    check("SpellQueue.NotePushback(); targetBoss=nil", 403, "unknown target type")
    check("SpellQueue.NotePushback(); b.now=105", 8042, "recent boundary")
    check("SpellQueue.NotePushback(); b.now=105.01", 403, "expired")
    check("SpellQueue.NotePushback(); clock=104; SpellQueue.NotePushback(); b.now=108", 8042, "renewed")
    check("SpellQueue.NotePushback(); SpellQueue.ResetPushback()", 403, "combat reset")
    check("SpellQueue.NotePushback(); b.inCombat=false", 403, "out of combat")
    check("SpellQueue.NotePushback(); forever=false", 403, "Retail unchanged")
    check("SpellQueue.NotePushback(); SpellQueue._rotationIsCustom=true", 403, "custom queue")
    check("SpellQueue.NotePushback(); b.contextOrder='off'", 403, "explicit order")
    check("SpellQueue.NotePushback(); targetExists=false", 403, "no target")
    check("SpellQueue.NotePushback(); procs[403]=true", 403, "preserve proc")
    check("SpellQueue.NotePushback(); entries[1].gates={{t='stack',required=true}}", 403, "instant stack lead")
    check("SpellQueue.NotePushback(); times[403]=0", 403, "instant lead")
    check("SpellQueue.NotePushback(); times[403]=nil", 403, "unknown lead cast time")
    check("SpellQueue.NotePushback(); cooldown[8042]=true", 403, "interrupt on cooldown")
    check('SpellQueue.NotePushback(); BlizzardAPI.IsSpellReady=function() return true, "no cooldown API" end',
          403, "missing cooldown API")
    check('SpellQueue.NotePushback(); BlizzardAPI.IsSpellReady=function() return true, "cooldown query failed (fail-open)" end',
          403, "failed cooldown query")
    check("SpellQueue.NotePushback(); BlizzardAPI.IsSpellUsable=function(_, failOpen) return failOpen, nil end",
          403, "unknown usability")
    check("SpellQueue.NotePushback(); starved[8042]=true", 403, "unaffordable")
    check("SpellQueue.NotePushback(); ranges[8042]=false", 403, "out of range")
    check("SpellQueue.NotePushback(); ranges=setmetatable({}, {})", 403, "unknown range")
    check("SpellQueue.NotePushback(); blacklisted[8042]=true", 403, "blacklist")
    check("SpellQueue.NotePushback(); locked[8042]=true", 403, "school lock")
    check("SpellQueue.NotePushback(); holdPoints[8042]=3; points=0", 403, "user hold")
    check("SpellQueue.NotePushback(); C_Spell.IsSpellHarmful=function() return false end",
          403, "non-harmful ability")
    check("SpellQueue.NotePushback(); sunkSet[8042]=true", 403, "sunk candidate")
    check("SpellQueue.NotePushback(); dots[8042]=true", 403, "DoT")
    check("SpellQueue.NotePushback(); channels[8042]=true", 403, "channel")
    for auto in (2480, 7918, 7919):
        check(f"""SpellQueue.NotePushback(); pool={{403,{auto}}}; times[{auto}]=0;
              entries[2]={{id={auto},gates={{}}}}""",
              403, f"ranged filler {auto} is not an instant damage filler")
    check("SpellQueue.NotePushback(); pool={403,120}", 403, "10-second cooldown excluded")
    check("SpellQueue.NotePushback(); pool={403,120}; pushbackDamage[120]=10",
          403, "10-second cooldown rejected at runtime")
    check("SpellQueue.NotePushback(); pool={403,8042,8056}", 8056, "prefer non-interrupt")
    check("SpellQueue.NotePushback(); pool={403,2136,8056}", 8056, "prefer shorter cooldown")
    check("SpellQueue.NotePushback(); pool={403,8056,15237}", 15237, "zero cooldown")
    check("SpellQueue.NotePushback(); pool={403,8056}; entries[2].gates={{t='unconfirmed'}}",
          403, "unknown priority gate")
    check("SpellQueue.NotePushback(); pool={403,8056}; entries[2].delegated=true",
          403, "delegated priority")
    lua.globals().SetupPushback()
    lua.execute("""
        local read = BlizzardAPI.IsSpellUsable
        local calls = 0
        BlizzardAPI.IsSpellUsable = function(id, failOpen)
            calls = calls + 1
            return read(id, failOpen)
        end
        SpellQueue.NotePushback()
        assert(PushbackResult() == 8042 and calls == 1)
    """)
    lua.globals().SetupPushback()
    # The real Enhancement list: Earth Shock shares the shocks' cooldown, so it answers pushback
    # only while Flame Shock is known to have more than that cooldown left.
    for below, expected in (("false", "8042"), ("true", "nil"), ("nil", "nil")):
        lua.globals().SetupPushback()
        lua.execute(f"""
            local saved = DotTracker
            DotTracker = {{ IsTimeLeftBelow = function(id, seconds)
                assert(id == 8050 and seconds == 4)
                return {below}
            end }}
            SpellQueue.NotePushback()
            entries = classes.SHAMAN_F.enhancement.st
            sunkSet[403] = true
            SpellQueue._StagePushback(b, pool)
            DotTracker = saved
            assert(b.recommendedSpells[1] == 403 and b.recommendedSpells[2] == {expected},
                   "Flame Shock below 4s left = {below}")
        """)
    lua.globals().SetupPushback()
    lua.execute("""
        SpellQueue.NotePushback()
        procs[403] = true
        SpellQueue._StagePushback(b, pool)
        assert(b.recommendedSpells[1] == 403 and b.recommendedSpells[2] == 8042)
    """)
    lua.globals().SetupPushback()
    lua.execute("""
        SpellQueue.NotePushback()
        procs[403] = true
        b.maxIcons = 1
        SpellQueue._StagePushback(b, pool)
        assert(b.spellCount == 1 and b.recommendedSpells[1] == 403)
    """)
    lua.globals().SetupPushback()
    lua.execute("""
        SpellQueue.NotePushback()
        entries = classes.SHAMAN_F.enhancement.st
        pool = {6603,8042,403}
        times[6603] = 0
        b.recommendedSpells, b.spellCount, b.leadMode = {}, 0, "mylist"
        function PassesRotationFilters(id)
            return RotationImport.RankBase(id) ~= 8042
        end
        Build()
        assert(b.recommendedSpells[1] == 6603 and sunkSet[403])
        -- Flame Shock running with time to spare: the shared shock cooldown costs nothing.
        local saved = DotTracker
        DotTracker = { IsTimeLeftBelow = function() return false end }
        SpellQueue._StagePushback(b, pool)
        DotTracker = saved
        assert(b.recommendedSpells[1] == 6603 and b.recommendedSpells[2] == 8042)
    """)
    lua.globals().SetupPushback()
    lua.execute("""
        SpellQueue.NotePushback()
        pool={403,8056}
        b.recommendedSpells={403,2136,8056}
        b.spellCount=3
    """)
    assert lua.globals().PushbackResult() == 8056
    assert list(lua.globals().b.recommendedSpells.values()) == [8056, 403, 2136], "move without duplicate"
    lua.globals().SetupPushback()
    lua.execute("""
        pushbackDamage[120] = nil
        SpellQueue.NotePushback()
        entries = classes.SHAMAN_F.elemental.st
        pool = {403,8042}
        b.recommendedSpells, b.spellCount, b.leadMode = {}, 0, "mylist"
        function PassesRotationFilters(id)
            return RotationImport.RankBase(id) ~= 8042
        end
        Build()
        assert(b.recommendedSpells[1] == 403)
        SpellQueue._StagePushback(b, pool)
        assert(b.recommendedSpells[1] == 8042)
    """)
    print("Pushback: event window, priority, cooldown, cast evidence and safety checks passed")


def check_pushback_weapon_dps():
    root = Path(__file__).resolve().parent.parent
    lua = create_runtime(real_gates=True)
    source = (root / "BlizzardAPI" / "CooldownTracking.lua").read_text(encoding="utf-8")
    start = source.index("local damageBaseline,")
    end = source.index("-- PLAYER_SWING_RANGE_UPDATE", start)
    lua.execute("local IsSecretValue=BlizzardAPI.IsSecretValue\n" + source[start:end])
    lua.execute("""
        clock=100
        function GetTime() return clock end
        function InCombatLockdown() return combatLockdown end
        function geterrorhandler() return function() errors=errors+1 end end
        function UnitLevel() return level end
        function GetSpellBonusDamage() return bonus end
        function UnitRangedDamage() return wandSpeed,wandLow,wandHigh end
        function UnitAttackSpeed() return meleeSpeed,offSpeed,rangedSpeed end
        function UnitDamage() return meleeLow,meleeHigh,offLow,offHigh end
        function UnitIsPlayer() return targetPlayer end
        function UnitPlayerControlled() return targetControlled end
        BlizzardAPI.GetCachedSpellInfo=function() return {castTime=1500} end
        BlizzardAPI.GetSpellInfo=function() return {castTime=normalCastTime} end
        BlizzardAPI.IsTargetBoss=function() return boss end
        BlizzardAPI.IsSpellAvailable=function(id) return equipment[id]==true end
        BlizzardAPI.IsTargetInSwingRange=function() return meleeReach end
        local abilityRange = BlizzardAPI.AbilityInRange
        BlizzardAPI.AbilityInRange=function(id)
            if id == 6603 and ranges[id] ~= false then return meleeReach end
            return abilityRange(id)
        end
        BlizzardAPI.RunningAutoSwing=function(id) return running[id] end
        SpellDB.GetArch=function() return leadArch end
        SpellDB.IsTargetDot=function() return leadDot end
        SpellDB.IsChanneled=function() return leadChannel end
        SpellDB.IsInterruptTypeSpell=function() return false end
        function SetupWeapons()
            Reset();SpellQueue.ResetPushback();SpellQueue._ResetWeaponPhase()
            specKey='PRIEST_F';entries=classes.PRIEST_F.shadow.st
            pool={585,5019,6603};b.inCombat=true;b.now=100;b.ctxEnemies=1
            b.recommendedSpells={585,5019,6603};b.spellCount=3
            level,bonus,errors=1,0,0
            combatLockdown,baselinePrimed=false,false
            BlizzardAPI.InvalidateDamageBaseline()
            normalCastTime=1500
            leadArch,leadDot,leadChannel="st",false,false
            targetPlayer,targetControlled,boss=false,false,false
            syntheticProcs={}
            running={}
            hits=2
            manaRegen,manaCost=nil,0
            Enum = Enum or {}; Enum.PowerType = Enum.PowerType or { Mana = 0 }
            BlizzardAPI.GetBaseManaRegen=function() return manaRegen end
            C_Spell.GetSpellPowerCost=function(id)
                if id == 585 then return {{type=0,cost=manaCost}} end
                return {}
            end
            wandSpeed,wandLow,wandHigh=2,10,14
            rangedSpeed=2
            meleeSpeed,meleeLow,meleeHigh=2,14,18
            offSpeed,offLow,offHigh=nil,0,0
            equipment={[5019]=true,[6603]=true}
            ranges={[585]=true,[5019]=true,[6603]=true}
            meleeReach=false
            C_Spell.IsSpellHarmful=function() return true end
        end
        function PrimeWeaponBaseline()
            if not baselinePrimed then
                combatLockdown=false
                BlizzardAPI.RefreshDamageBaseline()
                baselinePrimed=true
            end
            combatLockdown=b.inCombat
        end
        function WeaponResult()
            PrimeWeaponBaseline()
            SpellQueue.NotePushback()
            for _ = 1, hits do SpellQueue.NoteIncomingHit() end
            return BuildWeaponFillers()
        end
        function BuildWeaponFillers()
            b.leadMode='mylist';b.recommendedSpells={};b.addedSpellIDs={};b.spellCount=0
            BuildStage()
            SpellQueue._StagePushback(b,pool)
            SpellQueue._StageForeverWait(b)
            return b.recommendedSpells[1]
        end
        function NormalWeaponResult()
            PrimeWeaponBaseline()
            return BuildWeaponFillers()
        end
    """)
    for setup, expected, why in (
        ("", 5019, "wand beats Smite while being hit"),
        ("hits=0", 585, "Smite wins when nothing is hitting"),
        ("hits=1", 585, "one hit in the window expects less pushback"),
        ("wandLow=10;wandHigh=10", 5019, "spell advantage under 20% while hit favors free weapon"),
        ("wandLow=9.8;wandHigh=9.8", 585, "20% spell advantage while hit restores casting"),
        ("b.now=103", 5019, "hit window boundary"),
        ("b.now=103.01", 585, "hit window expired"),
        ("hits=0;rangedSpeed=1", 5019, "current ranged speed includes haste"),
        ("wandSpeed=1;rangedSpeed=4", 585, "legacy ranged speed cannot overstate DPS"),
        ("rangedSpeed=secret", 585, "secret current ranged speed"),
        ("rangedSpeed=nil", 585, "missing current ranged speed"),
        ("meleeReach=true", 6603, "stronger melee when already in reach"),
        ("equipment[5019]=false;meleeReach=true;normalCastTime=0", 585,
         "an instant adds to the melee swing, so melee never takes its place"),
        ("meleeReach=true;meleeLow=10;meleeHigh=14", 5019, "wand wins equal weapon DPS"),
        ("meleeReach=nil", 5019, "unknown melee reach never promotes melee"),
        ("equipment[5019]=false;meleeReach=true", 6603, "no wand: melee remains available"),
        ("equipment[5019]=false;meleeReach=true;meleeLow=12;meleeHigh=12", 6603,
         "melee within 20% of the cast also saves casting cost"),
        ("equipment[5019]=false", 585, "no usable in-range weapon"),
        ("ranges[5019]=false", 585, "wand out of range"),
        ("ranges[5019]=nil", 585, "wand range unknown"),
        ("wandLow=secret", 585, "secret ranged damage"),
        ("bonus=secret", 585, "secret spell bonus"),
        ("level=secret", 585, "secret level"),
        ("procs[585]=true", 585, "protected proc"),
        ("SpellQueue._rotationIsCustom=true", 585, "custom queue"),
        ("b.contextOrder='off'", 585, "explicit order"),
        ("forever=false", 585, "Retail unchanged"),
        ("b.ctxEnemies=2", 585, "packs unchanged"),
        ("b.ctxArch='aoe'", 585, "AoE context unchanged"),
        ("blacklisted[5019]=true", 585, "blacklist honored"),
        ("holdPoints[5019]=3;points=0", 585, "hold honored"),
        ("locked[5019]=true", 585, "lockout honored"),
        ("cooldown[5019]=true", 585, "unready wand"),
        ("unusable[5019]=true", 585, "unusable wand"),
    ):
        lua.globals().SetupWeapons()
        lua.execute(setup)
        actual = lua.globals().WeaponResult()
        assert actual == expected, (why, actual, expected)
    lua.globals().SetupWeapons()
    lua.execute("""
        SpellQueue._StagePushback(b,pool)
        assert(b.recommendedSpells[1]==585, 'no pushback means no weapon promotion')
        assert(WeaponResult()==5019)
        SpellQueue.ResetPushback()
        assert(BuildWeaponFillers()==585, 'leaving or entering combat clears being hit')
        SpellQueue.NoteIncomingHit()
        assert(SpellQueue.NoteIncomingHit()==false, 'a hit inside the window is not a new spell')
        clock=103.01
        assert(SpellQueue.NoteIncomingHit()==true, 'a hit after the window starts a new spell')
        clock=100
        SpellQueue.ResetPushback()
        local E=SpellQueue._ExpectedPushback
        assert(E(1.739,0)==0, 'no hits, no pushback')
        assert(math.abs(E(1.739,1/3)-0.5111)<0.001, 'one slow attacker: about the measured 0.67s')
        assert(math.abs(E(1.739,4/3)-2.5125)<0.001, 'two attackers: the four measured pushes')
        assert(E(1.739,10)==E(1.739,4/3), 'no fifth push is assumed')
        assert(E(0.5,1) <= 0.5, 'a short cast cannot be pushed past its own progress on the first hit')
    """)
    lua.globals().SetupWeapons()
    lua.execute("""
        assert(WeaponResult()==5019)
        wandLow=secret
        assert(BuildWeaponFillers()==5019, 'explicit precombat baseline survives combat secrecy')
    """)
    lua.globals().SetupWeapons()
    lua.execute("""
        local ranged=UnitRangedDamage
        UnitRangedDamage=function() error("denied") end
        assert(WeaponResult()==585 and errors==1)
        UnitRangedDamage=ranged
        level=6
        bonus=20
        assert(math.abs(BlizzardAPI.GetDirectSpellDPS(585,3)-(15.5+20*0.429)/3)<0.000001,
            'rank-1 mean, capped level growth and school bonus')
        assert(math.abs(BlizzardAPI.GetDirectSpellDPS(591,3)-(27+20*0.571)/3)<0.000001,
            'rank-2 damage is not rank 1')
        level=20
        assert(math.abs(BlizzardAPI.GetDirectSpellDPS(585,3)-(15.5+20*0.429)/3)<0.000001,
            'level growth stops at the rank cap')
        assert(BlizzardAPI.GetDirectSpellDPS(591,3) ~= BlizzardAPI.GetDirectSpellDPS(585,3))
        assert(BlizzardAPI.GetDirectSpellDPS(999999,3)==nil, 'no rank-1 substitution')
        assert(math.abs(BlizzardAPI.GetDirectSpellHit(585)-(15.5+20*0.429))<0.000001,
            'one cast hit shares the DPS damage model')
        assert(math.abs(BlizzardAPI.GetDirectSpellHit(14914)-(54+20*0.75))<0.000001,
            'Holy Fire hit is priced without its damage over time')
        assert(math.abs(BlizzardAPI.GetDirectSpellDPS(14914,3)-(54+20*0.75+(20+20*0.25)*3/10)/3)<0.000001,
            'a hit with a burn counts the part of the burn that runs during one cycle')
        assert(math.abs(BlizzardAPI.GetDirectSpellDPS(14914,20)-(54+20*0.75+20+20*0.25)/20)<0.000001,
            'a cycle longer than the burn counts all of it, never more')
        assert(math.abs(BlizzardAPI.GetDirectSpellHit(14914,nil,true)-(54+20*0.75+20+20*0.25))<0.000001,
            'whole Holy Fire adds every damage-over-time tick')
        assert(math.abs(BlizzardAPI.GetDirectSpellHit(585,nil,true)-(15.5+20*0.429))<0.000001,
            'a plain hit is already the whole spell')
        assert(BlizzardAPI.GetDirectSpellHit(999999)==nil, 'unknown hit stays unknown')
        assert(math.abs(BlizzardAPI.GetDirectSpellHit(172,nil,true)-(40+20*0.8))<0.000001,
            'a damage over time with no hit is priced by its total')
        assert(BlizzardAPI.GetDirectSpellHit(172)==nil and BlizzardAPI.GetDirectSpellDPS(172,2)==nil,
            'and has no hit and no filler rate of its own')
        offSpeed,offLow,offHigh=2,2,6
        assert(BlizzardAPI.GetAutoAttackDPS(6603)==10, 'both hands counted')
        offLow=secret
        assert(BlizzardAPI.GetAutoAttackDPS(6603)==nil, 'no partial dual-wield estimate')
        rangedSpeed=0
        assert(BlizzardAPI.GetAutoAttackDPS(5019)==nil)
        rangedSpeed=2;wandLow=0/0
        assert(BlizzardAPI.GetAutoAttackDPS(5019)==nil)
        wandLow=math.huge
        assert(BlizzardAPI.GetAutoAttackDPS(5019)==nil)
    """)
    print("Pushback DPS: learned ranks, observed cast cycle, weapon reach, wand ties and unknown guards passed")
    lua.globals().SetupWeapons()
    lua.execute("""
        local damage,ranged=UnitDamage,UnitRangedDamage
        UnitDamage=function() return meleeLow,meleeHigh,offLow,offHigh,30,-10,1.5 end
        for _, case in ipairs({
            {2,18,26,nil,0,0,11}, -- one hand with shield/held offhand
            {4,28,52,nil,0,0,10}, -- two hands
            {2,2,4,nil,0,0,1.5}, -- unarmed
            {2,10,14,1,4,8,12}, -- unequal dual-wield intervals; offhand already penalized
            {1.7,1.1,2.3,nil,0,0,1}, -- raw precision, not rounded display bounds
        }) do
            meleeSpeed,meleeLow,meleeHigh=case[1],case[2],case[3]
            offSpeed,offLow,offHigh=case[4],case[5],case[6]
            assert(math.abs(BlizzardAPI.GetAutoAttackDPS(6603)-case[7])<0.000001,
                'raw hand rates include bonuses without a second offhand penalty')
        end
        UnitRangedDamage=function() return 99,10,14,30,-10,1.5 end
        rangedSpeed=1
        assert(BlizzardAPI.GetAutoAttackDPS(5019)==12)
        assert(BlizzardAPI.GetAutoAttackDPS(75)==12, 'all supported ranged repeats use current ranged interval')
        for _, id in ipairs({2480,7918,7919,2764,3018}) do
            assert(BlizzardAPI.GetAutoAttackDPS(id)==nil, 'manual/thrown shots are not sustained repeats')
        end
        UnitDamage,UnitRangedDamage=damage,ranged
        meleeLow,meleeHigh=12,10
        assert(BlizzardAPI.GetAutoAttackDPS(6603)==nil, 'reversed melee range')
        wandLow,wandHigh=-1,2
        assert(BlizzardAPI.GetAutoAttackDPS(5019)==nil, 'negative ranged damage')
        wandLow,wandHigh=12,10
        assert(BlizzardAPI.GetAutoAttackDPS(5019)==nil, 'reversed ranged range')
        level,bonus,normalCastTime=5,1,1304
        wandLow,wandHigh,rangedSpeed=17,17,1.304
        assert(math.abs(BlizzardAPI.GetAutoAttackDPS(5019)-13.036809615728)<0.000001)
        assert(math.abs(BlizzardAPI.GetDirectSpellDPS(585)-12.138803680982)<0.000001,
            'rank growth and short cast reproduce the captured DPS pair')
    """)
    # Once the wand is chosen against this target it stays chosen while its readiness wavers
    # between shots (a brief wait); a fresh target or leaving combat starts over.
    for setup, expected, why in (
        ("cooldown[5019]=true; briefWait[5019]=true", 5019, "the chosen wand stays between shots"),
        ("cooldown[5019]=true; briefWait[5019]=true; ranges[5019]=false", 585, "out of range ends the phase"),
        ("cooldown[5019]=true; briefWait[5019]=true; blacklisted[5019]=true", 585, "a blacklist ends the phase"),
        ("cooldown[5019]=true; briefWait[5019]=true; SpellQueue._ResetWeaponPhase()", 585,
         "a new target (choice cleared) starts over"),
        # Just after a shot Shoot reads a real cooldown: a stronger melee attack in reach that
        # moment must not take the wand's place (2026-11-20 capture: one-frame melee blips).
        ("cooldown[5019]=true; briefWait[5019]=true; meleeReach=true", 5019,
         "a ready melee attack does not replace a wavering wand"),
        ("ranges[5019]=false; meleeReach=true", 6603, "out of range, melee in reach takes over"),
        ("meleeReach=true", 6603, "a stronger melee attack still wins when both read ready"),
    ):
        lua.globals().SetupWeapons()
        assert lua.eval("WeaponResult()") == 5019, why
        lua.execute(setup)
        actual = lua.eval("WeaponResult()")
        assert actual == expected, (why, actual, expected)
    # A weaker melee attack (priced before the fight) in reach while the wand's range reads
    # unknown for a moment: the wand stays; out of range is what drops it.
    lua.globals().SetupWeapons()
    lua.execute("meleeLow,meleeHigh=6,6")
    assert lua.eval("WeaponResult()") == 5019
    lua.execute("ranges[5019]=nil; meleeReach=true")
    assert lua.eval("WeaponResult()") == 5019, "a range read unknown for a moment keeps the wand"
    # Right after a shot the wand's button can read out of range for a frame (2026-11-20 capture):
    # a shot just fired was fired at a target in range, so the wand stays.
    lua.execute("ranges[5019]=false; BlizzardAPI.GetSwingWindow=function(t) if t==2 then return shotAt end end")
    lua.execute("shotAt=b.now-0.03")
    lua.eval("WeaponResult()")
    assert lua.eval("b.weaponFillerID") == 5019, "out of range for a frame right after a shot keeps the wand"
    lua.execute("shotAt=b.now-2")
    lua.eval("WeaponResult()")
    assert lua.eval("b.weaponFillerID") == 6603, "out of range, the melee attack in reach becomes the weapon"
    lua.execute("BlizzardAPI.GetSwingWindow=nil")
    for setup, expected, why in (
        ("", 5019, "strong wand leads without pushback or mana conservation"),
        ("b.inCombat=false;b.ctxEnemies=0", 585, "a ready pull nuke opens before the wand"),
        ("b.inCombat=false;b.ctxEnemies=0;pool={589,585,5019,6603}", 585, "the pull nuke opens ahead of Shadow Word: Pain"),
        ("wandLow=19.8;wandHigh=19.8", 5019, "near-equal spell DPS favors free weapon"),
        ("wandLow=16;wandHigh=16", 585, "clear spell advantage restores Smite"),
        ("wandLow=20;wandHigh=20", 5019, "wand wins a tie with an ordinary cast"),
        ("meleeReach=true;meleeLow=26;meleeHigh=26", 6603, "stronger melee already in reach"),
        ("meleeReach=true;meleeLow=24;meleeHigh=24", 5019, "equal weapons prefer versatile wand"),
        ("equipment[5019]=false;meleeReach=true;meleeLow=26;meleeHigh=26", 6603, "melee without wand"),
        ("equipment[5019]=false;meleeReach=true;meleeLow=20;meleeHigh=20", 6603, "equal melee DPS avoids casting"),
        ("equipment[5019]=false", 585, "no request to move into melee"),
        ("equipment[5019]=false;meleeReach=nil", 585, "unknown melee reach"),
        ("equipment[5019]=false;meleeReach=true;meleeLow=26;meleeHigh=26;"
         "BlizzardAPI.IsTargetInSwingRange=function() return nil end", 6603,
         "confirmed shared melee evidence needs no second raw swing verdict"),
        ("ranges[5019]=false", 585, "wand out of range"),
        ("ranges[5019]=nil", 585, "wand range unknown"),
        ("normalCastTime=secret", 585, "secret cast time"),
        ("normalCastTime=nil", 585, "missing cast time"),
        ("normalCastTime=0/0", 585, "nonfinite cast time"),
        ("normalCastTime=0", 585, "instant GCD is not guessed"),
        ("normalCastTime=1000", 585, "short cast upper-bound DPS still exceeds wand"),
        ("normalCastTime=1304", 5019, "live-sized hasted Smite is comparable"),
        ("normalCastTime=1000;wandLow=40;wandHigh=40", 5019,
         "wand beating the cast-time-only upper bound is safe without GCD timing"),
        ("level=6;bonus=30", 585, "spell power can make Smite clearly stronger"),
        ("wandLow=secret", 585, "secret weapon damage"),
        ("bonus=secret", 585, "secret spell power"),
        ("procs[585]=true", 585, "proc priority"),
        ("syntheticProcs[585]=true", 585, "synthetic proc priority"),
        ("entries={{id=585,gates={{t='stack',id=123,required=true,op='>=',n=5}}}};"
         "BlizzardAPI.GetAuraStackAtLeast=function() return true end", 585, "required-stack lead"),
        ("b.contextOrder='ac';entries={{id=585,gates={{t='stack',id=123,required=true,op='>=',n=5}}}};"
         "BlizzardAPI.GetAuraStackAtLeast=function() return true end", 585, "required-stack context ordering"),
        ("leadDot=true", 585, "DoT priority"),
        ("leadChannel=true", 585, "channel priority"),
        ("leadArch='aoe'", 585, "AoE spell priority"),
        ("b.ctxEnemies=2", 585, "multi-target context"),
        ("b.ctxEnemies=nil", 585, "unknown combat enemy count"),
        ("boss=true", 585, "boss priority"),
        ("targetPlayer=true", 585, "PvP target"),
        ("targetControlled=true", 585, "player-controlled target"),
        ("targetExists=false", 585, "no target"),
        ("hostile=false", 585, "friendly target"),
        ("targetDead=true", 585, "dead target"),
        ("SpellQueue._rotationIsCustom=true", 585, "custom ordering"),
        ("b.contextOrder='off'", 585, "exact ordering"),
        ("forever=false", 585, "Retail unchanged"),
        ("blacklisted[5019]=true", 585, "weapon blacklist"),
        ("filtered[5019]=true", 585, "weapon display filters"),
        ("holdPoints[5019]=3;points=0", 585, "weapon hold"),
        ("locked[5019]=true", 585, "weapon lockout"),
        ("cooldown[5019]=true", 585, "unready weapon"),
        ("unusable[5019]=true", 585, "unusable weapon"),
    ):
        lua.globals().SetupWeapons()
        lua.execute("wandLow,wandHigh=24,24\n" + setup)
        actual = lua.globals().NormalWeaponResult()
        assert actual == expected, (why, actual, expected)
    for setup, expected, why in (
        ("", 585, "a clearly stronger cast leads without mana data"),
        ("manaRegen=10;manaCost=0", 585, "a free cast keeps its advantage"),
        ("manaRegen=10;manaCost=10", 5019, "recovering the mana makes the free wand stronger"),
        ("manaRegen=10;manaCost=10;PrimeWeaponBaseline();manaRegen=nil", 5019,
         "the pre-combat regeneration still charges mana when the live read goes unreadable"),
        ("manaRegen=1000;manaCost=10", 585, "fast regeneration makes the mana cheap"),
        ("manaRegen=nil;manaCost=10", 585, "unknown regeneration leaves mana out"),
        ("manaRegen=10;manaCost=secret", 585, "secret cost leaves mana out"),
        ("manaRegen=10;C_Spell.GetSpellPowerCost=function() error('denied') end", 585,
         "denied cost leaves mana out"),
        ("manaRegen=10;manaCost=10;b.inCombat=false;b.ctxEnemies=0", 585,
         "the pull nuke is not a filler comparison"),
    ):
        lua.globals().SetupWeapons()
        lua.execute("wandLow,wandHigh=16,16\n" + setup)
        actual = lua.globals().NormalWeaponResult()
        assert actual == expected, (why, actual, expected)
    # Mana confirmed at or above the conserve threshold: a cast is priced on damage alone.
    for setup, expected, why in (
        ("wandLow,wandHigh=16,16;manaBelow=false", 585, "mana to spare: the cast's mana is not charged"),
        ("wandLow,wandHigh=16,16;manaBelow=true", 5019, "low mana: recovering the mana still favors the wand"),
        ("wandLow,wandHigh=16,16;manaBelow=nil", 5019, "unreadable mana keeps the conserving rule"),
        ("wandLow,wandHigh=16,16;b.profile.efficiencyManaThreshold=60;manaAt=50", 5019,
         "the profile's threshold decides what low means"),
        ("wandLow,wandHigh=16,16;b.profile.efficiencyManaThreshold=30;manaAt=50", 585,
         "a lower threshold leaves this mana level spendable"),
        ("wandLow,wandHigh=18,18;manaRegen=nil;manaBelow=false", 585,
         "mana to spare: a cast that is simply ahead leads, no 20% margin"),
        ("wandLow,wandHigh=18,18;manaRegen=nil;manaBelow=true", 5019, "low mana keeps the 20% margin"),
        ("wandLow,wandHigh=30,30;manaRegen=nil;manaBelow=false", 5019,
         "mana to spare never promotes a weaker cast"),
        # Measured damage over paper damage scales each side (talents, crits, misses).
        ("wandLow,wandHigh=16,16;manaBelow=false;"
         "BlizzardAPI.GetMeasuredDamageRatio=function(id) if id==5019 then return 1.5 end end", 5019,
         "a wand measured above its sheet damage overtakes the cast"),
        ("wandLow,wandHigh=16,16;manaBelow=false;"
         "BlizzardAPI.GetMeasuredDamageRatio=function(id) if id==585 then return 0.5 end end", 5019,
         "a cast measured below its paper damage loses to the wand"),
        ("wandLow,wandHigh=30,30;manaRegen=nil;manaBelow=false;"
         "BlizzardAPI.GetMeasuredDamageRatio=function(id) if id==5019 then return 0.5 end end", 585,
         "a wand that misses a lot loses to the cast"),
    ):
        lua.globals().SetupWeapons()
        lua.execute("""
            manaBelow, manaAt = nil, nil
            BlizzardAPI.GetMeasuredDamageRatio = nil
            SpellQueue._ResetWeaponPhase()
            b.profile.efficiencyManaThreshold = nil
            manaRegen, manaCost = 10, 10
            BlizzardAPI.IsUnitPowerBelow = function(_, pct)
                if manaAt then return manaAt < pct end
                return manaBelow
            end
        """ + setup)
        actual = lua.globals().NormalWeaponResult()
        assert actual == expected, (why, actual, expected)
    lua.globals().SetupWeapons()
    lua.execute("""
        BlizzardAPI.GetMeasuredDamageRatio = nil
        wandLow,wandHigh=16,16
        manaRegen, manaCost = 10, 10
        SpellQueue._ResetWeaponPhase()
        manaBelow = true
        assert(NormalWeaponResult()==5019, 'low mana conserves')
        manaBelow = false
        assert(BuildWeaponFillers()==5019, 'once low in a fight, the conserving rule stays for that fight')
        b.inCombat = false; b.ctxEnemies = 0
        BuildWeaponFillers()
        b.inCombat = true; b.ctxEnemies = 1
        assert(BuildWeaponFillers()==585, 'leaving combat clears it')
        BlizzardAPI.IsUnitPowerBelow = nil
        b.profile.efficiencyManaThreshold = nil
        SpellQueue._ResetWeaponPhase()
    """)
    lua.globals().SetupWeapons()
    lua.execute("""
        wandLow,wandHigh=24,24
        assert(NormalWeaponResult()==5019)
        assert(b.spellCount==3 and b.recommendedSpells[2]==585 and b.recommendedSpells[3]==6603)
        assert(pushbackDebug.weaponID==5019 and pushbackDebug.weaponSpellDPS==10
            and pushbackDebug.weaponDPS==12)
        assert(NormalWeaponResult()==5019 and b.spellCount==3, 'repeat builds do not duplicate wand')
        b.recommendedSpells={6603,585,5019};b.spellCount=3
        assert(NormalWeaponResult()==5019, 'stronger wand can replace a leading melee attack')
        b.recommendedSpells={585};b.spellCount=1;b.maxIcons=1
        assert(NormalWeaponResult()==5019 and b.spellCount==1 and b.recommendedSpells[2]==nil)
    """)
    for cast_time, expected in ((1250.1, 5019), (1250, 585), (1249.9, 585)):
        lua.globals().SetupWeapons()
        lua.execute(f"wandLow,wandHigh=20,20;normalCastTime={cast_time}")
        assert lua.globals().NormalWeaponResult() == expected, ("exact 20% boundary", cast_time)
    lua.globals().SetupWeapons()
    lua.execute("""
        level,bonus,normalCastTime=5,1,1304
        wandLow,wandHigh,rangedSpeed=17,17,1.304
        running[5019]=2
        local W=SpellQueue.WAIT_SENTINEL
        assert(NormalWeaponResult()==W, 'a running wand leaves the queue: WAIT keeps it going')
        for i=1,20 do
            cooldown[585],cooldown[5019],cooldown[6603]=i%2==0,i%2==0,i%3==0
            BuildWeaponFillers()
            assert(b.spellCount==3 and b.recommendedSpells[1]==W
                and b.recommendedSpells[2]==585 and b.recommendedSpells[3]==6603,
                'shot lockouts do not shuffle fillers or show the running wand')
        end
        b.ctxEnemies=0
        assert(BuildWeaponFillers()==W, 'confirmed running repeat survives initial threat-count delay')
        b.ctxEnemies=1;meleeReach=true;locked[585]=true
        BuildWeaponFillers()
        assert(b.recommendedSpells[2]==6603, 'real school/LoC lockout still sinks filler')
        locked[585]=nil;starved[585]=true
        BuildWeaponFillers()
        assert(b.recommendedSpells[2]==6603, 'unaffordable filler still sinks')
        starved[585]=nil;cooldown[585]=nil;procs[585]=true
        assert(BuildWeaponFillers()==585, 'new proc interrupts weapon-first filler')
        procs[585]=nil;ranges[5019]=false
        assert(BuildWeaponFillers()==585, 'range changes immediately restore the usable spell')
    """)
    for additive in (3044, 1752, 78, 19434):
        lua.globals().SetupWeapons()
        lua.execute(f"""
            level=20;wandLow,wandHigh=30,30
            ranges[{additive}]=true
            pool={{{additive},585,5019,6603}}
            entries={{{{id={additive}}},{{id=585}},{{id=5019}},{{id=6603}}}}
            local info=BlizzardAPI.GetSpellInfo
            BlizzardAPI.GetSpellInfo=function(id)
                if id=={additive} then return {{castTime={3000 if additive == 19434 else 0}}} end
                return info(id)
            end
            assert(NormalWeaponResult()=={additive},
                'instant, on-swing and unsupported weapon-scaled abilities keep their priority')
            BlizzardAPI.GetSpellInfo=info
        """)
    lua.globals().SetupWeapons()
    lua.execute("""
        wandLow,wandHigh=24,24
        equipment[5019],equipment[75]=false,true
        ranges[75]=true
        pool={585,75,6603};entries={{id=585},{id=75},{id=6603}}
        assert(NormalWeaponResult()==75, 'supported ranged weapons can offer sustained Auto Shot')
        running[75]=2;cooldown[585],cooldown[75]=true,true
        assert(BuildWeaponFillers()==SpellQueue.WAIT_SENTINEL and b.recommendedSpells[2]==585,
            'a running Auto Shot cycle leaves the queue to WAIT, stably')
        running[75]=nil;unusable[75]=true;cooldown[585]=nil
        assert(BuildWeaponFillers()==585, 'missing ammo or another usability failure rejects ranged repeat')
    """)
    for auto in (5019, 6603):
        lua.globals().SetupWeapons()
        lua.execute(f"""
            pool={{{auto}}};entries={{{{id={auto}}}}}
            running[{auto}]={2 if auto == 5019 else 0}
            meleeReach=true
            assert(NormalWeaponResult()==SpellQueue.WAIT_SENTINEL,
                'an attack already running takes no slot: WAIT while it continues')
            ranges[{auto}]=false
            assert(BuildWeaponFillers()==SpellQueue.WAIT_SENTINEL, 'out-of-range checked attacks cannot prevent WAIT')
        """)
    lua.globals().SetupWeapons()
    lua.execute("""
        wandLow,wandHigh=30,30
        normalCastTime=1304
        PrimeWeaponBaseline()
        level,bonus,wandLow,rangedSpeed,meleeLow=secret,secret,secret,secret,secret
        assert(NormalWeaponResult()==5019, 'both sides use plain precombat stats, not hidden combat values')
        BlizzardAPI.RefreshDamageBaseline()
        assert(BlizzardAPI.GetAutoAttackDPS(5019,true)==15, 'combat refresh leaves the baseline intact')
        BlizzardAPI.InvalidateDamageBaseline()
        b.recommendedSpells={585,5019,6603};b.spellCount=3
        assert(NormalWeaponResult()==585, 'no stale estimate after invalidation in combat')
        assert(BlizzardAPI.GetAutoAttackDPS(5019,true)==nil)
    """)
    lua.globals().SetupWeapons()
    lua.execute("""
        local ranged=UnitRangedDamage
        local reads=0
        UnitRangedDamage=function() reads=reads+1;return ranged() end
        b.inCombat=false;wandLow,wandHigh=30,30
        hostile=false
        BuildWeaponFillers()
        assert(reads==0, 'friendly target does not trigger a baseline refresh')
        hostile=true;targetExists=false
        BuildWeaponFillers()
        assert(reads==0, 'no target does not trigger a baseline refresh')
        targetExists=true
        for i=1,100 do BuildWeaponFillers() end
        assert(reads==1, 'hostile-target refresh is throttled, not repeated each queue build')
        clock=101.01
        BuildWeaponFillers()
        assert(reads==2, 'baseline refreshes again after one second')
        combatLockdown=true
        for i=1,100 do BlizzardAPI.RefreshDamageBaseline() end
        assert(reads==2, 'no weapon-stat calls while combat locks them')
        combatLockdown=false;clock=103;wandLow=secret
        BlizzardAPI.RefreshDamageBaseline()
        assert(BlizzardAPI.GetAutoAttackDPS(5019,true)==nil, 'unreadable refresh does not retain old weapon stats')
        UnitRangedDamage=ranged
    """)
    lua.globals().SetupWeapons()
    lua.execute("""
        wandLow,wandHigh=12,12
        assert(NormalWeaponResult()==585)
        normalCastTime=3000
        assert(NormalWeaponResult()==5019, 'fresh cast time, not cached 1500 ms')
        b.recommendedSpells={585,5019,6603};b.spellCount=3
        normalCastTime=1500
        assert(NormalWeaponResult()==585, 'fresh speed changes restore spell priority')
        local read=BlizzardAPI.GetSpellInfo
        BlizzardAPI.GetSpellInfo=function() error("denied") end
        assert(NormalWeaponResult()==585 and errors==1, 'denied cast-time read is reported')
        BlizzardAPI.GetSpellInfo=read
    """)
    for tree in ("shadow", "discipline", "holy"):
        lua.globals().SetupWeapons()
        lua.execute(f"""
            level=5;normalCastTime=1304;wandLow,wandHigh=30,30
            entries=classes.PRIEST_F.{tree}.st
            PrimeWeaponBaseline()
            b.leadMode='mylist';b.recommendedSpells={{}};b.spellCount=0
            BuildStage()
            assert(b.recommendedSpells[1]==5019, 'weapon preference is integrated into categorization')
            SpellQueue._StagePushback(b,pool)
            assert(NormalWeaponResult()==5019, 'strong wand leads the assembled Priest queue')
            SpellQueue._StageForeverWait(b)
            assert(b.recommendedSpells[1]==5019, 'actionable wand is not replaced by WAIT')
        """)
    print("Normal weapon DPS: hasted casts, baseline secrecy/refresh/invalidation, wand/melee ties and protected contexts passed")


def check_burst_queue_placement():
    root = Path(__file__).resolve().parent.parent
    source = (root / "SpellQueue.lua").read_text(encoding="utf-8")
    helper_start = source.index("local function PlaceQueueSpell(")
    helper_end = source.index("\nend", helper_start) + len("\nend")
    stage_start = source.index("function SpellQueue._StageBurstCue(")
    stage_end = source.index("\nend", stage_start) + len("\nend")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        SpellQueue = {IsSpellBlacklisted=function() return false end}
        BlizzardAPI = {
            GetDisplaySpellID=function(id) if id == 400 then return 401 end return id end,
            IsSpellAvailable=function() return true end,
            IsSpellOnCooldown=function() return false end,
        }
        RotationImport = {GetEntry=function() return nil end}
        sunkSet, burstCueSpells, cachedBurstSource = {}, {}, "custom"
        function ResolveBurstTriggers() return {[400]=true, [401]=true}, {400} end
        function IsBurstTrigger(triggers, id) return triggers[id] == true end
        function IsUnusableNonResource() return false end
    """ + source[helper_start:helper_end] + "\n" + source[stage_start:stage_end] + """
        function check(queue, count, maxIcons, expected, cue, added)
            burstCueSpells = {}
            local b = {inCombat=true, profile={burstCueGlow=true}, blacklist={},
                recommendedSpells=queue, addedSpellIDs={}, spellCount=count, maxIcons=maxIcons}
            SpellQueue._StageBurstCue(b)
            assert(b.spellCount == #expected)
            for i, id in ipairs(expected) do assert(queue[i] == id) end
            assert(burstCueSpells[cue] == true)
            assert((b.addedSpellIDs[400] == true) == added)
            assert((b.addedSpellIDs[401] == true) == added)
        end
        check({111,222,400}, 3, 3, {111,400,222}, 400, false)
        check({111,401,222}, 3, 3, {111,401,222}, 401, false)
        check({111,222,333}, 3, 3, {111,401,222}, 401, true)
        check({111}, 1, 3, {111,401}, 401, true)
        check({111}, 1, 1, {111}, 401, true)
        check({}, 0, 3, {401}, 401, true)
    """)
    print("Burst cue placement preserves existing ids, insertion and queue bounds")


def check_shaman_priorities():
    lua = create_runtime(real_gates=True)
    lua.execute("""
        function Shaman(tree, context)
            Reset()
            local t = classes.SHAMAN_F[tree]
            entries = t[context] or (context == "cleave" and t.aoe) or t.st
            b.inCombat, b.leadMode, b.ctxEnemies = true, "mylist", 3
            stackCount, fireOccupied, earthOccupied = nil, true, true
            BlizzardAPI.GetAuraStackAtLeast = function(_, _, n)
                if stackCount == nil then return nil end
                return stackCount >= n
            end
            BlizzardAPI.IsTotemSlotOccupied = function(slot)
                if slot == 1 then return fireOccupied end
                return earthOccupied
            end
            BlizzardAPI.GetEngagedEnemyCount = function() return b.ctxEnemies end
            function IsSpenderSpell() return true end
            ranges = setmetatable({}, {__index=function() return true end})
        end
    """)
    # Maelstrom Weapon is a rune: a confirmed zero before any stack was seen this session means
    # the shaman cannot gain it, so Bolt is a normal cast; once seen, five stacks are required.
    lua.execute("castOnlyBuffSeen = {}")
    for stacks, expected in ((None, 408341), (0, 403), (4, 408341), (5, 403), (0, 408341)):
        for procced in (False, True):
            lua.globals().Shaman("enhancement", "st")
            lua.execute("pool={403,408341}")
            lua.globals().stackCount = stacks
            lua.globals().procs[403] = procced
            queue = list(lua.globals().Build().values())
            assert queue[0] == expected, ("Maelstrom prerequisite", stacks, procced, queue)
    lua.globals().Shaman("enhancement", "st")
    lua.execute("pool={403,408341}; BlizzardAPI.GetAuraStackAtLeast=nil")
    assert list(lua.globals().Build().values())[0] == 408341
    lua.globals().Shaman("enhancement", "st")
    lua.execute("pool={403,408341}; b.inCombat=false")
    assert list(lua.globals().Build().values())[0] == 403, "The ranged pull still permits a hardcast"
    lua.globals().Shaman("enhancement", "st")
    lua.execute("pool={403,8042}; SpellQueue._rotationIsCustom=true; b.contextOrder='off'")
    assert list(lua.globals().Build().values()) == [403, 8042]
    assert lua.eval("SpellQueue._GateVerdict({t='stack',id=408505,op='>=',n=5},{})") is None

    for context, expected in (("st", 17364), ("aoe", 408341)):
        lua.globals().Shaman("enhancement", context)
        lua.execute("pool={17364,408341,403}")
        assert list(lua.globals().Build().values())[0] == expected, \
            (context, "Nova needs no Clearcasting talent or buff")
    for occupied in (False, None):
        lua.globals().Shaman("enhancement", "aoe")
        lua.execute("pool={408341,17364}")
        lua.globals().fireOccupied = occupied
        assert list(lua.globals().Build().values())[0] == 17364
    lua.globals().Shaman("enhancement", "aoe")
    lua.execute("pool={408341,17364}; fireOccupied=false; procs[408341]=true")
    assert list(lua.globals().Build().values())[0] == 17364, "A proc cannot override an empty fire slot"
    lua.globals().Shaman("enhancement", "st")
    lua.execute("pool={8190,3599,17364}; fireOccupied=false")
    assert list(lua.globals().Build().values())[0] == 8190
    lua.globals().Shaman("enhancement", "st")
    lua.execute("pool={8190,3599,17364}; fireOccupied=false; starved[8190]=true")
    assert list(lua.globals().Build().values())[0] == 3599, "Affordable Searing backs up Magma"

    for context in ("st", "cleave"):
        lua.globals().Shaman("elemental", context)
        lua.execute("pool={3599,8190,403}; fireOccupied=false; b.ctxEnemies=2")
        assert list(lua.globals().Build().values())[0] == 3599, "Two targets retain Searing"
    lua.globals().Shaman("elemental", "aoe")
    lua.execute("pool={421,408341,403}")
    assert list(lua.globals().Build().values())[0] == 421, "Chain Lightning needs no Clearcasting"
    lua.globals().Shaman("elemental", "aoe")
    lua.execute("pool={421,408341,403}; cooldown[421]=true")
    assert list(lua.globals().Build().values())[0] == 408341
    for context, expected in (("st", 403), ("aoe", 421)):
        lua.globals().Shaman("elemental", context)
        lua.execute("pool={421,403}; buffs[16166]=true")
        assert list(lua.globals().Build().values())[0] == expected, \
            "Lightning Mastery favors Bolt on one target, Chain Lightning on packs"
    lua.globals().Shaman("elemental", "aoe")
    lua.execute("pool={408341,403}; b.ctxEnemies=2")
    assert list(lua.globals().Build().values())[0] == 403, "Nova's AoE threshold is three targets"
    for tree, burst in (("elemental", 16166), ("enhancement", 425336)):
        lua.globals().Shaman(tree, "st")
        lua.execute(f"pool={{{burst},403}}")
        lua.globals().stackCount = 5
        assert list(lua.globals().Build().values())[0] == burst, "Rank the tree's burst before filler"


def check_shifting_power():
    lua = create_runtime(real_gates=True)
    lua.execute("""
        Enum = {PowerType={Mana=0,Energy=3}}
        function UnitPowerMax(_, pt)
            if pt == 3 then return energyMax end
            return 100
        end
        BlizzardAPI.IsUnitPowerBelow = function(_, pct, pt)
            if pt ~= 3 then return false end
            energyReadType, energyReadThreshold = pt, pct
            if unknownEnergy then return nil end
            return energy * 100 / energyMax < pct
        end
        function IsSpenderSpell() return true end
        function Cat()
            Reset()
            specKey = "DRUID_F"
            entries = classes.DRUID_F.feral.st
            pool = {1322605,1082}
            ranges = {[1322605]=true,[1082]=true}
            energyMax, energy, unknownEnergy = 100, 0, false
            energyReadType, energyReadThreshold = nil, nil
        end
    """)
    for energy, should_lead in ((0, True), (49, True), (50, False),
                                (51, False), (100, False)):
        for procced in (False, True):
            lua.globals().Cat()
            lua.globals().energy = energy
            lua.globals().procs[1322605] = procced
            lua.globals().capped = energy == 100
            queue = list(lua.globals().Build().values())
            expected = 1322605 if should_lead else 1082
            assert queue[0] == expected, ("Shifting Power Energy guard", energy, procced, queue)
            assert lua.globals().energyReadType == 3
            assert lua.globals().energyReadThreshold == 50

    for procced in (False, True):
        lua.globals().Cat()
        lua.globals().unknownEnergy = True
        lua.globals().procs[1322605] = procced
        assert list(lua.globals().Build().values())[0] == 1082, \
            "Unknown Energy must not authorize Shifting Power"

    lua.globals().Cat()
    lua.execute("energyMax=120; energy=55")
    assert list(lua.globals().Build().values())[0] == 1082, \
        "The guard uses Energy units, not a percentage of maximum Energy"
    lua.globals().Cat()
    lua.execute("starved[1322605]=true")
    assert list(lua.globals().Build().values())[0] == 1082, \
        "Low Energy must not override insufficient Mana"
    lua.globals().Cat()
    lua.execute("cooldown[1322605]=true")
    assert list(lua.globals().Build().values())[0] == 1082

    for procced in (False, True):
        lua.globals().Cat()
        lua.execute("energy=100; holdPctVal[1322605]=10; holdPctType[1322605]=0")
        lua.globals().procs[1322605] = procced
        assert list(lua.globals().Build().values())[0] == 1322605, \
            "An explicit Hold Until dial replaces the imported Energy preference"
    lua.globals().Cat()
    lua.execute("energy=100; SpellQueue._rotationIsCustom=true; b.contextOrder='off'")
    assert list(lua.globals().Build().values()) == [1322605, 1082], \
        "Custom fixed ordering remains unchanged"

    lua.globals().Cat()
    lua.globals().unknownEnergy = True
    assert lua.eval("""
        SpellQueue._GateVerdict({t='power',res='energy',op='<',n=50},{})
    """) is None, "Existing power gates retain their unknown-state behavior"


def main():
    check_pushback_events()
    check_pushback_priority()
    check_pushback_weapon_dps()
    check_burst_queue_placement()
    check_shaman_priorities()
    check_shifting_power()
    early = {"id": 1, "gates": [{"t": "resource", "op": ">=", "n": 5}],
             "tiers": ["st"]}
    middle = {"id": 2, "gates": [], "tiers": ["st"]}
    fallback = {"id": 1, "gates": [], "tiers": ["st"]}
    assert tier_lists([early, middle, fallback])["st"] == [middle, fallback]
    assert actions_of({"strictSequence": {"actions": [
        {"castSpell": {"spellId": {"spellId": 14751}}},
        {"castSpell": {"spellId": {"spellId": 585}}},
    ]}}) == []
    assert actions_of({"channelSpell": {"spellId": {"spellId": 1510}}}) == [(1510, None)]
    assert Conv({}).conv({"cmp": {"op": "OpLt", "lhs": {"timeToNextEnergyTick": {}},
                                 "rhs": {"const": {"val": "1s"}}}}) == UNK
    assert on_enemy(22959) and not on_enemy(400625)
    explicit_player = Conv({}).conv({"cmp": {
        "op": "OpGe", "lhs": {"auraNumStacks": {
            "auraId": {"spellId": 22959}, "sourceUnit": {"type": "Self"}}},
        "rhs": {"const": {"val": "5"}},
    }})
    assert not explicit_player.get("tgt"), "Explicit source annotations take precedence over inference"

    lua = create_runtime(real_gates=True)
    lua.execute("""
        Enum = {PowerType={Mana=0,Rage=1,Energy=3}}
        function UnitPowerMax() return 100 end
        RotationImport.HighestKnownRank = function(id) return id end
        BlizzardAPI.GetEngagedEnemyCount = function() return enemyCount end
        BlizzardAPI.IsUnitPowerBelow = function(_, pct) return manaPct < pct end
        BlizzardAPI.IsUnitHealthBelow = function() return false end
        BlizzardAPI.GetAuraStackAtLeast = function(unit, id, n)
            lastStackUnit = unit
            if unknownStacks then return nil end
            return (stackCounts[unit][id] or 0) >= n
        end
        BlizzardAPI.IsSpellOnCooldown = function(id) return cooldown[id] == true end
        BlizzardAPI.IsTotemSlotOccupied = function() return false end
        BlizzardAPI.GetSwingRemaining = function() return nil end
        function Defaults(cls, tree, context)
            Reset()
            specKey = cls
            local t = classes[cls][tree]
            entries = t[context] or (context == "cleave" and t.aoe) or t.st
            manaPct, enemyCount = 100, 4
            stackCounts, unknownStacks = {player={},target={}}, true
            talents = setmetatable({}, {__index=function() return true end})
            pool = {}
            for _, e in ipairs(entries) do
                pool[#pool+1] = e.id
                ranges[e.id] = true
            end
        end
        function Gate(id, gateIndex)
            return SpellQueue._GateVerdict(RotationImport.GetEntry(id).gates[gateIndex],
                {strict=false,resCount=points,resMax=5,resName="combo_points"})
        end
    """)
    classes = lua.globals().classes
    contexts = 0
    builds = 0
    for cls, trees in classes.items():
        for tree in trees.keys():
            if tree == "default":
                continue
            for context in ("st", "cleave", "aoe"):
                lua.globals().Defaults(cls, tree, context)
                entries = list(lua.globals().entries.values())
                ids = [e.id for e in entries]
                assert len(ids) == len(set(ids)), (cls, tree, context, ids)
                for e in entries:
                    assert not any(g.t == "tick" for g in e.gates.values())
                contexts += 1
                for state in ("ready", "cooldown", "starved", "blacklisted", "custom"):
                    lua.globals().Defaults(cls, tree, context)
                    if state in ("cooldown", "starved", "blacklisted"):
                        lua.execute(f"for _, id in ipairs(pool) do {state}[id]=true end")
                    elif state == "custom":
                        lua.execute("SpellQueue._rotationIsCustom=true")
                    queue = list(lua.globals().Build().values())
                    assert len(queue) <= 4 and len(queue) == len(set(queue)), (cls, tree, state)
                    assert set(queue).issubset(set(ids)), (cls, tree, state)
                    if state == "blacklisted":
                        assert queue == []
                    builds += 1
    assert contexts == 84 and builds == 420

    for cls, tree, sid in (
        ("DRUID_F", "balance", 16914),
        ("WARLOCK_F", "affliction", 1949),
        ("WARLOCK_F", "demonology", 5740),
        ("WARLOCK_F", "destruction", 5740),
    ):
        lua.globals().Defaults(cls, tree, "aoe")
        lua.globals().enemyCount = 3
        assert lua.globals().Gate(sid, 1) is True
        lua.globals().enemyCount = 2
        assert lua.globals().Gate(sid, 1) is False
    lua.globals().Defaults("MAGE_F", "fire", "st")
    lua.execute("unknownStacks=false; stackCounts.target[22959]=5")
    assert lua.globals().Gate(11129, 1) is True
    assert lua.globals().lastStackUnit == "target"
    lua.globals().unknownStacks = True
    assert lua.globals().Gate(11129, 1) is None

    lua.globals().Defaults("PRIEST_F", "discipline", "st")
    penance = lua.globals().RotationImport.RankBase(1316995)
    lua.execute("pool={14914,589,585}; cooldown[14914]=true; b.inCombat=true")
    queue = list(lua.globals().Build().values())
    assert lua.globals().RotationImport.GetEntry(penance) is None
    assert queue.index(589) < queue.index(585)
    assert queue.index(585) < queue.index(14914)
    assert 14751 not in [e.id for e in lua.globals().entries.values()]
    for cls, tree, sid in (("DRUID_F", "feral_bear", 779), ("MAGE_F", "frost", 120)):
        lua.globals().Defaults(cls, tree, "cleave")
        assert sid in [e.id for e in lua.globals().entries.values()]
    lua.globals().Defaults("DRUID_F", "balance", "st")
    lua.execute("filtered[2912]=true")
    assert 5176 in list(lua.globals().Build().values()), "Wrath remains when Starfire is unavailable"
    lua.globals().Defaults("MAGE_F", "arcane", "st")
    assert len(lua.globals().RotationImport.GetEntry(400574).gates) == 0
    assert len(lua.globals().RotationImport.GetEntry(116).gates) > 0
    lua.globals().Defaults("WARRIOR_F", "arms", "aoe")
    lua.globals().enemyCount = 3
    assert lua.globals().Gate(1680, 1) is True
    lua.globals().enemyCount = 2
    assert lua.globals().Gate(1680, 1) is False
    lua.globals().Defaults("WARRIOR_F", "fury", "st")
    lua.execute("cooldown[23881]=true")
    assert [g.t for g in lua.globals().RotationImport.GetEntry(1680).gates.values()] == ["near"],         "Fury Whirlwind needs no enemy count, only the target inside its radius"
    lua.globals().Defaults("WARRIOR_F", "fury", "aoe")
    lua.globals().enemyCount = 2
    assert [g.t for g in lua.globals().RotationImport.GetEntry(1680).gates.values()] == ["near"],         "Fury Whirlwind needs no enemy count, only the target inside its radius"
    lua.globals().Defaults("PALADIN_F", "retribution", "st")
    lua.execute("buffs[20154]=true")
    assert lua.globals().Gate(20154, 1) is False, "An active seal is not reapplied"
    assert lua.eval("SpellQueue._GateVerdict(RotationImport.GetEntry(20271).gates[2],{strict=true})") is True
    lua.execute("buffs={}")
    assert 20154 in list(lua.globals().Build().values()), "Righteousness remains available without a seal"
    lua.globals().Defaults("DRUID_F", "feral", "st")
    bite = lua.globals().RotationImport.GetEntry(1328618).gates
    assert bite[1].op == ">="
    lua.execute("""
        pool={1328618,1082}; points=3; b.ctxPointCap=3
        C_Spell.GetSpellPowerCost=function(id)
            if id == 1328618 then return {{type=4,minCost=1,cost=5}} end
            return {}
        end
        finisher[1328618]=true
    """)
    assert list(lua.globals().Build().values())[0] == 1328618
    lua.globals().Defaults("PRIEST_F", "holy", "st")
    lua.execute("pool={14914,585}; cooldown[14914]=true; b.maxIcons=1")
    assert list(lua.globals().Build().values()) == [585]
    # No adaptation is applied to custom source ordering by this data generator.
    lua.globals().Defaults("DRUID_F", "feral", "st")
    lua.execute("SpellQueue._rotationIsCustom=true; b.contextOrder='off'; pool={1082,1328618}")
    assert list(lua.globals().Build().values()) == [1082, 1328618]
    print(f"Forever general priorities: {contexts} contexts, {builds} queue builds and targeted regressions passed")


if __name__ == "__main__":
    main()
