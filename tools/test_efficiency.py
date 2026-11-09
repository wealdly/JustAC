# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent


def check_options():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        libs={}
        local L=setmetatable({}, {__index=function(_,k) return k end})
        LibStub=setmetatable({NewLibrary=function(_,name)
            libs[name]={}; return libs[name]
        end}, {__call=function(_,name) return libs[name] end})
        libs['AceLocale-3.0']={GetLocale=function() return L end}
        libs['JustAC-Options']={IsFullyDisabled=function() return disabled end}
        libs['JustAC-OptionsSpellLists']={Args=function() end}
        libs['JustAC-OptionsCustomQueue']={CreateTabArgs=function() return {args={}} end}
        addon={db={profile={}},ForceUpdate=function() updates=updates+1 end}
        updates,disabled=0,false
        Enum={PowerType={Mana=0}}
        manaCapacity=100
        secret={}
        libs['JustAC-BlizzardAPI']={IsSecretValue=function(v) return v==secret end}
        function UnitPowerMax(unit,pt)
            assert(unit=='player' and pt==0)
            return manaCapacity
        end
    """)
    for file in ("Widgets.lua", "Offensive.lua"):
        lua.execute((ROOT / "Options" / file).read_text(encoding="utf-8"))
    lua.execute("""
        function Controls()
            return libs['JustAC-OptionsOffensive'].CreateTabArgs(addon)
                .args.customQueue.args.queueContentGroup.args
        end
        local c=Controls()
        assert(c.efficiencyMode.get()=='off')
        assert(c.efficiencyManaThreshold==nil and c.efficiencyRecoverySeconds==nil)
        assert(addon.db.profile.efficiencyManaThreshold==nil)
        assert(addon.db.profile.efficiencyRecoverySeconds==nil)
        c.efficiencyMode.set(nil,'solo')
        assert(addon.db.profile.efficiencyMode=='solo')
        assert(not c.efficiencyMode.disabled())
        assert(updates==1)
        addon.db.profile.efficiencyManaThreshold=55
        addon.db.profile.efficiencyRecoverySeconds=15
        c=Controls()
        assert(c.efficiencyMode.get()=='solo')
        assert(c.efficiencyManaThreshold==nil and c.efficiencyRecoverySeconds==nil)
        assert(addon.db.profile.efficiencyManaThreshold==55)
        assert(addon.db.profile.efficiencyRecoverySeconds==15)
        c.efficiencyMode.set(nil,'off')
        assert(c.efficiencyMode.get()=='off')
        assert(updates==2)
        c.efficiencyMode.set(nil,'always')
        assert(c.efficiencyMode.get()=='always' and updates==3)
        c.efficiencyMode.set(nil,'solo')
        manaCapacity=0
        assert(c.efficiencyMode.disabled())
        assert(c.efficiencyMode.get()=='solo', 'availability never rewrites saved intent')
        manaCapacity=100
        assert(not c.efficiencyMode.disabled())
        manaCapacity=secret
        assert(not c.efficiencyMode.disabled(), 'unknown is not no mana')
        UnitPowerMax=function() error('denied') end
        assert(not c.efficiencyMode.disabled())
        disabled=true
        assert(c.efficiencyMode.disabled())
        assert(addon.db.profile.efficiencyManaThreshold==55)
        assert(addon.db.profile.efficiencyRecoverySeconds==15)
    """)


def check_attack_equipment():
    source = (ROOT / "BlizzardAPI" / "SpellQuery.lua").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("assert(loadstring(...))", source)
    lua.execute("""
        BlizzardAPI={}
        secret={}
        function IsSecretValue(v) return rawequal(v,secret) end
        function IsPassiveID() return false end
        function IsSpellKnown() return true end
        Enum={ItemClass={Weapon=2}, ItemWeaponSubclass={
            Bows=2,Guns=3,Thrown=16,Crossbow=18,Wand=19}}
        equipped={}
        C_Item={
            GetItemSubClassInfo=function(class,subclass)
                assert(class==2)
                for key,value in pairs(Enum.ItemWeaponSubclass) do
                    if value==subclass then return 'localized '..key end
                end
            end,
            IsEquippedItemType=function(name) return equipped[name]==true end,
        }
        C_Spell_IsSpellUsable=function() return true,false end
    """)
    lua.execute(source[source.index("local attackWeaponTypes"):])
    start = source.index("function BlizzardAPI.IsSpellUsable(")
    end = source.index("\n--------------------------------------------------------------------------------", start)
    lua.execute(source[start:end])
    for client in ("retail", "forever"):
        lua.execute("""
            equipped={}
            assert(BlizzardAPI.HasRequiredAttackWeapon(6603)==true)
            assert(BlizzardAPI.IsSpellAvailable(686)==true)
            for id,kind in pairs({[5019]='Wand',[2480]='Bows',[7918]='Guns',
                                 [2764]='Thrown',[7919]='Crossbow'}) do
                assert(BlizzardAPI.HasRequiredAttackWeapon(id)==false)
                assert(BlizzardAPI.IsSpellAvailable(id)==false)
                assert(BlizzardAPI.IsSpellUsable(id,true)==false)
                equipped['localized '..kind]=true
                assert(BlizzardAPI.HasRequiredAttackWeapon(id)==true)
                assert(BlizzardAPI.IsSpellAvailable(id)==true)
                assert(BlizzardAPI.IsSpellUsable(id,false)==true)
                equipped={}
                assert(BlizzardAPI.IsSpellAvailable(id)==false, 'must bypass cached learned state')
                equipped['localized '..kind]=true
                assert(BlizzardAPI.IsSpellAvailable(id)==true, 're-equipping needs no spellbook event')
                equipped={}
            end
            for _,kind in ipairs({'Bows','Guns','Crossbow'}) do
                equipped={['localized '..kind]=true}
                assert(BlizzardAPI.IsSpellAvailable(75)==true)
                assert(BlizzardAPI.IsSpellAvailable(5019)==false)
            end
            equipped={['localized Wand']=true}
            assert(BlizzardAPI.IsSpellAvailable(75)==false)
        """)
    lua.execute("""
        local query=C_Item.IsEquippedItemType
        for _,value in ipairs({secret, 'malformed'}) do
            C_Item.IsEquippedItemType=function() return value end
            assert(BlizzardAPI.HasRequiredAttackWeapon(5019)==nil)
            assert(BlizzardAPI.IsSpellAvailable(5019)==false)
            assert(BlizzardAPI.IsSpellUsable(5019,true)==false)
        end
        C_Item.IsEquippedItemType=function() error('denied') end
        assert(BlizzardAPI.HasRequiredAttackWeapon(5019)==nil)
        C_Item.IsEquippedItemType=nil
        assert(BlizzardAPI.HasRequiredAttackWeapon(5019)==nil)
        C_Item.IsEquippedItemType=query
        C_Item.GetItemSubClassInfo=function() return secret end
        assert(BlizzardAPI.HasRequiredAttackWeapon(5019)==nil)
        assert(BlizzardAPI.IsSpellAvailable(5019)==false)
        C_Item=nil
        assert(BlizzardAPI.HasRequiredAttackWeapon(5019)==nil)
        assert(BlizzardAPI.IsSpellAvailable(6603)==true)
    """)
    core = (ROOT / "JustAC.lua").read_text(encoding="utf-8")
    lua.execute("assert(loadstring(...))", core)
    start = core.index("function JustAC:OnEquipmentChanged(")
    end = core.index("\nend", start) + len("\nend")
    lua.execute("""
        JustAC={}
        refreshed={}
        BlizzardAPI.RefreshItemSpellCache=function() refreshed.items=true end
        BlizzardAPI.ClearAvailabilityCache=function() refreshed.availability=true end
        SpellQueue={InvalidateRotationCache=function() refreshed.rotation=true end}
        SpellSearch={InvalidateSpellbookCache=function() refreshed.search=true end}
        function JustAC:ForceUpdateAll() refreshed.queues=true end
    """)
    lua.execute(core[start:end])
    lua.execute("""
        JustAC:OnEquipmentChanged('PLAYER_EQUIPMENT_CHANGED',18,false)
        assert(refreshed.items and refreshed.availability and refreshed.rotation
            and refreshed.search and refreshed.queues)
    """)
    print("efficiency: shared equipment checks reject unequipped ranged attacks, including cached availability and weapon swaps")


def check_recovery():
    source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    start = source.index("local function PlainRecoveryNumber(")
    end = source.index("\n--- Which band", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        BlizzardAPI={}
        Enum={PowerType={Mana=0}}
        function ResetRecovery()
            secret=setmetatable({},{
                __eq=function() error('secret compared') end,
                __lt=function() error('secret compared') end,
                __le=function() error('secret compared') end,
                __sub=function() error('secret arithmetic') end,
                __div=function() error('secret arithmetic') end,
            })
            BlizzardAPI.IsSecretValue=function(v) return rawequal(v,secret) end
            maximum,current,base,casting=1000,500,50,10
            function UnitPower(unit,pt)
                assert(unit=='player' and pt==0); return current
            end
            function UnitPowerMax(unit,pt)
                assert(unit=='player' and pt==0); return maximum
            end
            function GetManaRegen() return base,casting end
        end
    """)
    lua.execute(source[start:end])
    run = lua.eval("""
        function(setup)
            ResetRecovery()
            assert(loadstring(setup))()
            return BlizzardAPI.GetManaRecoveryEstimate()
        end
    """)
    cases = [
        ("", (50, "readable", 10)),
        ("current=1000", (0, "readable", 0)),
        ("casting=0", (None, "no combat regeneration", 10)),
        ("base=0", (50, "readable", None)),
        ("base=0; casting=0", (None, "no combat regeneration", None)),
        ("base=secret", (50, "readable", None)),
        ("casting=secret", (None, "regeneration unreadable")),
        ("current=secret", (None, "current unreadable")),
        ("maximum=secret", (None, "maximum unreadable")),
        ("casting=0/0", (None, "regeneration unreadable")),
        ("casting=math.huge", (None, "regeneration unreadable")),
        ("casting=-1", (None, "regeneration unreadable")),
        ("casting=nil", (None, "regeneration unreadable")),
        ("casting='10'", (None, "regeneration unreadable")),
        ("current=-1", (None, "current unreadable")),
        ("current=1001", (None, "current unreadable")),
        ("maximum=0", (None, "no mana")),
        ("maximum=nil", (None, "maximum unreadable")),
        ("maximum=math.huge", (None, "maximum unreadable")),
        ("GetManaRegen=nil", (None, "unavailable")),
        ("UnitPower=nil", (None, "unavailable")),
        ("GetManaRegen=function() error('denied') end", (None, "regeneration denied")),
        ("UnitPower=function() error('denied') end", (None, "current denied")),
        ("UnitPowerMax=function() error('denied') end", (None, "maximum denied")),
    ]
    for setup, expected in cases:
        actual = run(setup)
        assert actual == expected, (setup, actual, expected)
    print(f"efficiency: {len(cases)} actual mana recovery cases (combat/base units, zero, secret, denial and invalid reads)")


def main():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.eval("function(src) assert(loadstring(src)) end")(source)
    lua.execute("""
        AUTO_ATTACK_SPELL=6603
        lastCtx={}
        SpellQueue={}
        SpellQueue.WAIT_SENTINEL=-999999999
        SpellQueue.IsSpellBlacklisted=function(id) return blacklisted[id]==true end
        SpellQueue.IsCasterSuppressedPick=function(id) return suppressed[id]==true end
        SpellQueue.IsHeldByHold=function(id) return held[id]==true end
        SpellDB={
            GetArch=function() return arch end,
            IsOffensiveSpell=function() return offensive end,
        }
        Enum={PowerType={Mana=0}}
        function UnitIsPVP() return pvp end
        function UnitIsPVPFreeForAll() return ffa end
        function UnitIsPlayer() return targetPlayer end
        function UnitPlayerControlled() return controlled end
        function UnitIsDeadOrGhost(unit)
            if unit=='player' then return dead end
            return targetDead
        end
        function IsInGroup() return grouped end
        function IsInInstance() return instance end
        function UnitClassification() return classification end
        function IsPlayerSpell(id) return known[id]==true end
        function UnitExists() return true end
        function UnitCanAttack() return true end
        function TargetPointCap() end
        function wipe(t) for k in pairs(t) do t[k]=nil end end
        DYING_TARGET_PCT=20
        BlizzardAPI={
            IsSecretValue=function(v) return v==secret end,
            IsForever=function() return forever end,
            HasGamePick=function() return nativePick end,
            IsTargetBoss=function() return boss end,
            GetEngagedEnemyCount=function() return enemies end,
            IsUnitHealthBelow=function(unit,pct)
                if unit=='target' then
                    assert(pct==20 or pct==35)
                    if targetUnknown then return nil end
                    return targetHealth < pct
                end
                assert(unit=='player' and pct==80)
                if healthUnknown then return nil end
                return health < pct
            end,
            IsUnitPowerBelow=function(unit,pct,pt)
                assert(unit=='player' and pt==0, 'must test mana explicitly')
                if manaUnknown then return nil end
                lastManaThreshold=pct
                return mana < pct
            end,
            IsSpellReady=function(id) return ready[id] end,
            HasRequiredAttackWeapon=function(id)
                if weaponUnknown then return nil end
                return missingWeapon~=id
            end,
            IsSpellUsable=function(id,failOpen) assert(failOpen==false); return usable[id] end,
            SpellInRange=function(id) return ranges[id] end,
            IsSpellProcced=function() return proc end,
        }
        function Reset()
            C_Spell={
                GetSpellPowerCost=function(id) return costs[id] end,
                IsCurrentSpell=function(id) assert(id==6603); return running[id] end,
                IsAutoRepeatSpell=function(id) assert(id~=6603); return running[id] end,
            }
            running={}
            missingWeapon,weaponUnknown=nil,false
            forever, grouped, instance, pvp, ffa = true, false, false, false, false
            nativePick, executeLatch=false,false
            targetHealth,targetUnknown,enemies=19,false,1
            targetPlayer, controlled, dead, targetDead, boss = false, false, false, false, false
            classification, arch, offensive, proc = 'normal', 'st', true, false
            health, mana, healthUnknown, manaUnknown = 100, 30, false, false
            BlizzardAPI.GetManaRecoveryEstimate=function() return nil,'current unreadable' end
            secret={}
            known={[6603]=true}
            ready={[6603]=true,[5019]=true,[75]=true}
            usable={[6603]=true,[5019]=true,[75]=true}
            ranges={[6603]=true,[5019]=true,[75]=true}
            costs={[6603]={},[5019]={},[75]={},[686]={{type=0,cost=25}}}
            held, suppressed, blacklisted, manaCostCache, syntheticProcs, displacedPrimary = {}, {}, {}, {}, {}, {}
            cachedRotationList={686,5019,75,6603}
            SpellQueue._rotationIsCustom=false
            b={
                profile={efficiencyMode='solo',efficiencyManaThreshold=40},
                contextOrder='simc',inCombat=true,ctxDying=true,ctxArch='st',ctxEnemies=1,
                recommendedSpells={686,172,6603},spellCount=3,maxIcons=3,
                blacklist={},addedSpellIDs={},
            }
        end
    """)
    costs_start = source.index("local function CostsMana(")
    costs_end = source.index('\n--- "Too low on mana', costs_start)
    stage_start = source.index("local EFFICIENCY_ATTACKS")
    stage_end = source.index("\n--- Stage G", stage_start)
    lua.execute(source[costs_start:costs_end] + "\n" + source[stage_start:stage_end])
    run = lua.eval("""
        function(setup)
            Reset()
            assert(loadstring(setup))()
            local before=table.concat(b.recommendedSpells,',')
            SpellQueue._StageEfficiency(b)
            return b.recommendedSpells[1],lastCtx.efficiencyReason,
                before,table.concat(b.recommendedSpells,',')
        end
    """)
    blocked = {
        "equipment unreadable": "weaponUnknown=true",
        "default off": "b.profile.efficiencyMode=nil",
        "explicit off": "b.profile.efficiencyMode='off'",
        "group": "grouped=true",
        "unknown group": "grouped=nil",
        "instance": "instance=true",
        "unknown instance": "instance=nil",
        "PvP": "pvp=true",
        "free for all": "ffa=true",
        "unknown PvP": "pvp=nil",
        "secret PvP": "pvp=secret",
        "player target": "targetPlayer=true",
        "player pet target": "controlled=true",
        "unknown ownership": "controlled=nil",
        "dead player": "dead=true",
        "dead target": "targetDead=true",
        "custom list": "SpellQueue._rotationIsCustom=true",
        "exact order": "b.contextOrder='off'",
        "out of combat": "b.inCombat=false",
        "unknown enemy count": "b.ctxEnemies=nil",
        "zero detected enemies": "b.ctxEnemies=0",
        "two enemies": "b.ctxEnemies=2",
        "three enemies": "b.ctxEnemies=3",
        "multi context": "b.ctxArch='cleave'",
        "boss": "boss=true",
        "unknown boss": "boss=nil",
        "elite": "classification='elite'",
        "low health": "health=79",
        "unknown health": "healthUnknown=true",
        "mana boundary": "mana=40",
        "high mana": "mana=80",
        "unknown mana": "manaUnknown=true",
        "secret mana verdict": "BlizzardAPI.IsUnitPowerBelow=function() return secret end",
        "wrong mode": "b.profile.efficiencyMode='bad'",
        "invalid threshold": "b.profile.efficiencyManaThreshold='40'",
        "NaN threshold": "b.profile.efficiencyManaThreshold=0/0",
        "out of bounds threshold": "b.profile.efficiencyManaThreshold=101",
        "unclassified lead": "arch=nil",
        "AoE lead": "arch='aoe'",
        "utility lead": "offensive=false",
        "proc lead": "proc=true",
        "injected gap closer or proc": "syntheticProcs[686]=true",
        "unknown proc": "proc=nil",
        "wait lead": "b.recommendedSpells[1]=-999999999",
        "free lead": "costs[686]={}",
        "energy lead": "costs[686]={{type=3,cost=35}}",
        "rage lead": "costs[686]={{type=1,cost=20}}",
        "focus lead": "costs[686]={{type=2,cost=30}}",
        "runic power lead": "costs[686]={{type=6,cost=30}}",
        "combo point lead": "costs[686]={{type=4,cost=5}}",
        "health conversion lead": "costs[686]={{type=-2,cost=20}}",
        "unknown leading cost": "costs[686]=nil",
        "unlearned attack": "known[6603]=false",
        "blacklisted": "blacklisted[6603]=true",
        "held attack": "held[6603]=true",
        "caster filler": "suppressed[6603]=true",
        "unusable": "usable[6603]=false",
        "unknown usability": "usable[6603]=nil",
        "not ready": "ready[6603]=false",
        "unknown readiness": "ready[6603]=nil",
        "invalid attack costs": "costs[6603]='unknown'",
        "secret attack costs": "costs[6603]=secret",
        "denied attack costs": "C_Spell.GetSpellPowerCost=function(id) if id==6603 then error('denied') end; return costs[id] end",
        "missing attack cost API": "C_Spell.GetSpellPowerCost=nil",
        "secret cost": "costs[6603]={{cost=secret}}",
        "costs power": "costs[6603]={{cost=1}}",
        "fast regeneration": "BlizzardAPI.GetManaRecoveryEstimate=function() return 9,'readable',20 end",
        "full mana": "BlizzardAPI.GetManaRecoveryEstimate=function() return 0,'readable',0 end",
        "no mana resource": "BlizzardAPI.GetManaRecoveryEstimate=function() return nil,'no mana' end",
        "invalid recovery threshold": "b.profile.efficiencyRecoverySeconds=0",
        "invalid recovery type": "b.profile.efficiencyRecoverySeconds='10'",
        "invalid recovery NaN": "b.profile.efficiencyRecoverySeconds=0/0",
    }
    original_power = lua.globals().BlizzardAPI.IsUnitPowerBelow
    for client in ("forever=true; nativePick=false\n", "forever=false; nativePick=true\n"):
        for label, setup in blocked.items():
            lua.globals().BlizzardAPI.IsUnitPowerBelow = original_power
            lead, reason, before, after = run(client + setup)
            assert before == after, (client, label, lead, reason, before, after)
            assert reason != "conserve mana", (client, label, reason)
    lua.globals().BlizzardAPI.IsUnitPowerBelow = original_power
    allowed = [
        ("", "6603,686,172"),
        ("b.ctxDying=false; targetHealth=90", "6603,686,172"),
        ("costs[686]={{type=3,cost=0},{type=0,cost=25}}", "6603,686,172"),
        ("health=80; mana=39", "6603,686,172"),
        ("b.profile.efficiencyManaThreshold=nil", "6603,686,172"),
        ("mana=49; b.profile.efficiencyManaThreshold=50", "6603,686,172"),
        ("b.profile.efficiencyMode='always'; grouped=true; instance=true", "6603,686,172"),
        ("known[5019]=true", "5019,686,172"),
        ("known[5019]=true; missingWeapon=5019", "6603,686,172"),
        ("known[75]=true; missingWeapon=75", "6603,686,172"),
        ("known[5019]=true; ranges[6603]=false", "5019,686,172"),
        ("known[5019]=true; ranges[5019]=nil", "6603,686,172"),
        ("known[75]=true", "75,686,172"),
        ("b.recommendedSpells={686}; b.spellCount=1; b.maxIcons=1", "6603"),
        ("b.recommendedSpells={686}; b.spellCount=1", "6603,686"),
        ("cachedRotationList={686}", "6603,686,172"),
        ("cachedRotationList=nil", "6603,686,172"),
        ("ranges[6603]=nil", "6603,686,172"),
        ("ranges[6603]=false", "6603,686,172"),
        ("costs[6603]=nil; ranges[6603]=nil", "6603,686,172"),
        ("known[5019]=true; costs[5019]=nil", "5019,686,172"),
        ("known[75]=true; costs[75]=nil", "75,686,172"),
        ("mana=90; BlizzardAPI.GetManaRecoveryEstimate=function() return 10,'readable',20 end", "6603,686,172"),
        ("mana=90; BlizzardAPI.GetManaRecoveryEstimate=function() return 30,'readable',nil end", "6603,686,172"),
        ("mana=90; BlizzardAPI.GetManaRecoveryEstimate=function() return nil,'no combat regeneration',5 end", "6603,686,172"),
        ("known[5019]=true; ranges[5019]=false", "6603,686,172"),
        ("known[5019]=true; ranges[5019]=nil; ranges[6603]=false", "5019,686,172"),
        ("known[5019]=true; ranges[5019]=false; ranges[6603]=false", "5019,686,172"),
    ]
    for client in ("forever=true; nativePick=false\n", "forever=false; nativePick=true\n"):
        for setup, expected in allowed:
            _, reason, _, after = run(client + setup)
            assert after == expected and reason == "conserve mana", (client, setup, reason, after)
            assert len(after.split(",")) == len(set(after.split(","))), after
    for client in ("forever=true\n", "forever=false; nativePick=true\n"):
        for setup, expected, reason in [
            ("running[6603]=true", "-999999999,686,172", "wait for auto attack"),
            ("running[6603]=true; ranges[6603]=nil", "6603,686,172", "conserve mana"),
            ("running[6603]=true; ranges[6603]=false", "6603,686,172", "conserve mana"),
            ("running[6603]=secret", "6603,686,172", "conserve mana"),
            ("C_Spell.IsCurrentSpell=function() error('denied') end", "6603,686,172", "conserve mana"),
            ("known[5019]=true; running[5019]=true; known[6603]=false", "-999999999,686,172", "wait for auto attack"),
            ("known[75]=true; running[75]=true; known[6603]=false", "-999999999,686,172", "wait for auto attack"),
            ("known[5019]=true; running[6603]=true", "5019,686,172", "conserve mana"),
            ("known[5019]=true; running[5019]=true", "6603,686,172", "conserve mana"),
            ("running[6603]=true; b.maxIcons=1; b.spellCount=1; b.recommendedSpells={686}",
             "-999999999", "wait for auto attack"),
        ]:
            _, actual_reason, _, after = run(client + setup)
            assert (after, actual_reason) == (expected, reason), (client, setup, after, actual_reason)
            assert lua.globals().b.efficiencyWaiting == (reason == "wait for auto attack")
    safe_start = source.index("function SpellQueue._ApplySafeLead(")
    safe_end = source.index("\n--- Did the safe-lead", safe_start)
    lua.execute(source[safe_start:safe_end])
    lua.execute("""
        Reset()
        b.efficiencyWaiting=true; b.leadMode='safe'
        SpellQueue.SafeLeadCandidate=function() error('efficiency WAIT must not be overridden') end
        lastSpellIDs={SpellQueue.WAIT_SENTINEL,686}
        SpellQueue._ApplySafeLead(b)
        assert(lastSpellIDs[1]==SpellQueue.WAIT_SENTINEL)
    """)
    lead, reason, _, _ = run("forever=false; nativePick=true; b.primarySpellID=686; cachedRotationList={686}")
    assert lead == 6603 and reason == "conserve mana"
    assert lua.globals().displacedPrimary[686] is True, "native pick retains its displaced recommendation marker"
    run("ranges[6603]=nil; usable[5019]=false")
    ctx = lua.globals().lastCtx
    assert ctx.efficiencyManaBelow is True
    assert ctx.efficiencyRange == "unknown"
    assert "6603=eligible: unknown" in ctx.efficiencyCandidates
    assert "5019=not learned or unknown" in ctx.efficiencyCandidates
    assert ctx.efficiencyResourceDecision == "mana threshold fallback"
    run("known[5019]=true")
    assert "5019=eligible: in range" in ctx.efficiencyCandidates
    run("")
    assert "5019=not learned or unknown" in ctx.efficiencyCandidates
    assert "5019=eligible" not in ctx.efficiencyCandidates, "pooled diagnostics must not retain old candidates"
    run("BlizzardAPI.GetManaRecoveryEstimate=function() return 12,'readable',24 end")
    assert ctx.efficiencyFullSeconds == 12 and ctx.efficiencyBaseFullSeconds == 24
    run("b.profile.efficiencyMode='off'")
    assert ctx.efficiencyFullSeconds is None and ctx.efficiencyCandidates is None, "no stale evidence"
    assert ctx.efficiencyManaBelow is None
    for setup, verdict, reason in [
        ("mana=40", False, "mana at or above threshold"),
        ("manaUnknown=true", None, "mana threshold unreadable"),
    ]:
        _, actual_reason, _, _ = run(setup)
        assert actual_reason == reason
        assert ctx.efficiencyManaBelow == verdict
    # An exception must remain diagnosable and leave the queue untouched.
    _, reason, before, after = run("UnitIsPVP=function() error('denied') end")
    assert before == after and reason == "unsafe or unreadable units"
    lua.execute("function UnitIsPVP() return pvp end")
    context_start = source.index("function SpellQueue._StageContext(")
    context_end = source.index("\n--- Stage F", context_start)
    lua.execute(source[context_start:context_end])
    for setup, expected in [
        ("", 6603),
        ("targetHealth=20", 6603),
        ("targetHealth=21", 6603),
        ("targetHealth=90", 6603),
        ("targetUnknown=true", 6603),
        ("enemies=0", 686),
        ("enemies=2", 686),
        ("enemies=3", 686),
        ("boss=true", 686),
    ]:
        lead, reason, _, _ = run(setup + "\nSpellQueue._StageContext(b)")
        assert lead == expected, (setup, lead, expected, reason)
    lua.execute("""
        for _,retail in ipairs({false,true}) do
            Reset()
            forever=not retail; nativePick=retail
            targetHealth=90; running[6603]=true
            local function build()
                b.recommendedSpells={686,172,6603}; b.spellCount=3
                SpellQueue._StageContext(b)
                SpellQueue._StageEfficiency(b)
            end
            build()
            assert(b.recommendedSpells[1]==SpellQueue.WAIT_SENTINEL)
            enemies=2
            build()
            assert(b.recommendedSpells[1]==686 and not b.efficiencyWaiting)
            assert(lastCtx.efficiencyReason=='enemy count not exactly one')
            enemies=1; b.primarySpellID=686; SpellDB.GetArch=function() return 'cleave' end
            build()
            assert(b.recommendedSpells[1]==686)
            assert(lastCtx.efficiencyReason=='multi-target context')
            SpellDB.GetArch=function() return arch end
            health=79
            build()
            assert(b.recommendedSpells[1]==686)
            assert(lastCtx.efficiencyReason=='health unsafe or unknown')
            health=100; mana=40
            build()
            assert(b.recommendedSpells[1]==686)
            assert(lastCtx.efficiencyReason=='mana at or above threshold')
        end
    """)
    recovery_source = (ROOT / "BlizzardAPI" / "StateHelpers.lua").read_text(encoding="utf-8")
    recovery_start = recovery_source.index("local function PlainRecoveryNumber(")
    recovery_end = recovery_source.index("\n--- Which band", recovery_start)
    lua.execute(recovery_source[recovery_start:recovery_end] + """
        actualRecovery=BlizzardAPI.GetManaRecoveryEstimate
        function UnitPower(unit,pt) assert(unit=='player' and pt==0); return current end
        function UnitPowerMax(unit,pt) assert(unit=='player' and pt==0); return maximum end
        function GetManaRegen() return base,casting end
    """)
    for setup, expected in [
        ("current=500; maximum=1000; base=100; casting=10; mana=90", 6603),
        ("current=500; maximum=1000; base=1; casting=100; mana=10", 686),
        ("current=500; maximum=1000; base=100; casting=0; mana=90", 6603),
        ("current=secret; maximum=1000; base=100; casting=10; mana=30", 6603),
        ("current=secret; maximum=1000; base=100; casting=10; mana=80", 686),
        ("current=0; maximum=0; base=0; casting=0", 686),
    ]:
        lead, reason, _, _ = run(setup + "\nBlizzardAPI.GetManaRecoveryEstimate=actualRecovery")
        assert lead == expected, (setup, lead, reason)
    assert source.index("SpellQueue._StageEfficiency(b)", source.index("function SpellQueue.GetCurrentSpellQueue")) < source.index(
        "SpellQueue._StageFinalize(b)", source.index("function SpellQueue.GetCurrentSpellQueue")
    )
    check_options()
    check_attack_equipment()
    check_recovery()
    print(f"efficiency: {len(blocked)} fail-closed cases and {len(allowed)} promotions per client, denied API and Lua 5.1 compile passed")
    print("efficiency: real options builders preserve defaults, stored overrides, off and ForceUpdate")
    print("efficiency: actual context stage conserves before execute health, rejects packs and bosses")
    print("efficiency: integrated real recovery helper favors combat rate over base and falls back on secret mana")


if __name__ == "__main__":
    main()
