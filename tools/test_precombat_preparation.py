# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Preparation through real generated groups and shared checklist/filter.
from pathlib import Path

from test_support_queue_fixes import new_runtime, seq
from test_forever_openers import create_runtime

ROOT = Path(__file__).resolve().parent.parent


def test_preparation_refresh_window():
    for forever in (True, False):
        lua, _ = new_runtime(forever, precombat=False)
        pick, alternate, rank = (21082, 20165, 20162) if forever else (90001, 90002, 90003)
        lua.execute(f"""
            playerClass="PALADIN";combat=false;restricted=false;ready=true;usable=true;baseCooldown=0
            pick={pick};alternate={alternate};rank={rank}
            known[pick]=true;known[alternate]=true
            if not {str(forever).lower()} then
                SpellDB.CLASS_MAINTAINED_BUFFS.PALADIN={{
                    {{group={{pick,alternate}},memberAuraIDs={{[pick]={{rank}},[alternate]={{alternate}}}},
                      auraIDs={{rank,alternate}},preparation=true,combatCritical=true}},
                }}
                SpellDB.IndexMaintainedBuffs()
            end
            function InCombatLockdown() return combat end
            function UnitExists() return true end
            function UnitCanAttack() return true end
            function UnitInVehicle() return false end
            function GetSpellBaseCooldown() return baseCooldown end
            local B=LibStub("JustAC-BlizzardAPI")
            B.AreAurasSecret=function() return restricted end
            B.IsSpellReady=function() return ready end
            B.IsSpellUsable=function(_, failOpen) assert(failOpen==false);return usable end
            P=LibStub("JustAC-PrecombatEngine")
            function Query()
                P.ClearCache()
                return P.GetMissingClassBuffs(false,90,false,{{healthRecovery=false}})
            end
            function Aura(duration,remaining)
                auraByID={{[rank]={{duration=duration,expirationTime=now+remaining}}}}
                P.ClearCache()
            end
        """)
        lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
        lua.execute('P=LibStub("JustAC-PrecombatEngine")')
        p = lua.globals().P
        query = lua.globals().Query
        aura = lua.globals().Aura
        for duration, boundary in ((8, 2), (30, 7.5), (60, 10), (120, 10)):
            aura(duration, boundary + 0.01)
            assert seq(query()) == [], "a fresh short buff must not use the long upkeep window"
            aura(duration, boundary)
            assert seq(query()) == [pick], (duration, boundary, "refresh at the bounded threshold")
            assert p.IsPreparationFamilyActive(pick) is True, "refresh does not redefine aura presence"
            assert p.IsPreparationFamilySatisfied(pick) is False, "the active member may refresh OOC"
            assert p.IsPreparationFamilySatisfied(alternate) is True, "refresh never replaces an active alternative"
            assert p.ShouldEmphasizePreparation(pick) is True, "refresh is emphasized with a hostile target"
            assert p.ShouldEmphasizePreparation(alternate) is False
            lua.execute("combat=true;P.ClearCache()")
            assert seq(query()) == []
            assert p.IsPreparationFamilySatisfied(pick) is True, "combat remains missing-only"
            assert p.ShouldEmphasizePreparation(pick) is False
            lua.execute("combat=false")
        aura(30, 2)
        for setup in (
            "auraByID[rank].duration=0;auraByID[rank].expirationTime=0",
            "auraByID[rank].duration=secretAuraID",
            "auraByID[rank].expirationTime=secretAuraID",
            "auraByID[rank].expirationTime=nil",
            "auraByID[rank].expirationTime=0",
            "ready=false",
            "ready=nil",
            "usable=false",
            "usable=nil",
            "baseCooldown=60000",
            "baseCooldown=nil",
            "baseCooldown=secretAuraID",
        ):
            aura(30, 2)
            lua.execute("ready=true;usable=true;baseCooldown=0;" + setup)
            assert seq(query()) == [], (setup, "unreadable/permanent/unavailable/burst preparation stays quiet")
            assert p.IsPreparationFamilySatisfied(pick) is True
            assert p.ShouldEmphasizePreparation(pick) is False
        lua.execute("ready=true;usable=true;baseCooldown=0")
        aura(30, 2)
        lua.execute("auraByID[rank]=setmetatable({}, {__index=function() error('aura timing denied') end})")
        assert seq(query()) == [], "denied timing fields cannot authorize a refresh"
        assert len(lua.globals().messages) == 1, "timing denial is reported explicitly"
        aura(30, 2)
        lua.execute("denySpell=true;P.ClearCache()")
        assert seq(query()) == [], "denied reads cannot authorize a refresh"
        lua.execute("denySpell=false")
        aura(30, 2)
        lua.execute("P.NoteClassBuffApplied(alternate)")
        assert seq(query()) == [], "application grace also blocks early refresh"
        lua.execute("now=now+3.1")
        aura(30, 2)
        assert seq(query()) == [pick], "refresh returns after the application settles"
        lua.execute("SpellDB.PREPARATION_BUFF_MEMBERS[pick].form=true")
        assert seq(query()) == [], "forms never refresh even with a finite aura"


def test_contextual_preparation():
    cases = (
        (True, "PALADIN", "protection", 1, 25780, False),
        (True, "PRIEST", "shadow", 1, 15473, True),
        (True, "DRUID", "balance", 1, 24858, True),
        (True, "WARRIOR", "arms", 1, 6673, False),
        (False, "PRIEST", None, 3, 232698, True),
        (False, "DRUID", None, 1, 24858, True),
        (False, "DRUID", None, 2, 768, True),
        (False, "DRUID", None, 3, 5487, True),
    )
    for forever, cls, tree, spec, spell, form in cases:
        lua, _ = new_runtime(forever)
        lua.globals().playerClass = cls
        lua.globals().currentTree = tree
        lua.globals().currentSpec = spec
        lua.execute(f"known[{spell}]=true")
        lua.execute("""
            form=0;mounted=false;canUse=true;ready=true
            function IsMounted() return mounted end
            LibStub:NewLibrary("JustAC-FormCache").GetActiveForm=function() return form end
            local RI=LibStub:NewLibrary("JustAC-RotationImport")
            RI.GetForeverTree=function() return currentTree end
            C_SpecializationInfo.GetSpecialization=function() return currentSpec end
            local B=LibStub("JustAC-BlizzardAPI")
            B.IsSpellUsable=function(_, failOpen)
                assert(failOpen==false)
                return canUse
            end
            B.IsSpellReady=function() return ready end
            P=LibStub("JustAC-PrecombatEngine")
            function Query()
                P.ClearCache()
                return P.GetMissingClassBuffs(false,90,false)
            end
        """)
        query = lua.globals().Query
        assert seq(query()) == [spell], (forever, cls, tree, spec, "missing preparation")
        lua.execute("canUse=false")
        assert seq(query()) == [], "insufficient resources or unusable preparation stays quiet"
        lua.execute("canUse=nil")
        assert seq(query()) == [], "unknown usability cannot authorize a preparation offer"
        lua.execute("canUse=true;ready=false")
        assert seq(query()) == [], "preparation waits for readiness"
        lua.execute(f"ready=true;auraByID[{spell}]={{duration=180,expirationTime=now+0.1}}")
        assert seq(query()) == ([] if form else [spell]), "only timed non-form preparation refreshes OOC"
        lua.execute("auraByID={}")
        if form:
            lua.execute("form=4")
            assert seq(query()) == [], "an intentional alternate form is preserved"
            lua.execute("form=nil")
            assert seq(query()) == [], "unknown form state is not caster form"
            lua.execute("form=0;mounted=true")
            assert seq(query()) == [], "form preparation does not ask a mounted player to shift"
            lua.execute("mounted=false")
        if tree in ("protection", "shadow", "balance"):
            lua.execute("currentTree='other'")
            assert seq(query()) == [], "preparation respects the installed Forever tree"
        elif not forever:
            lua.globals().currentSpec = 4
            assert seq(query()) == [], "preparation respects the Retail specialization"

    lua, _ = new_runtime()
    lua.execute("""
        playerClass="HUNTER";known={[13165]=true,[13163]=true,[13161]=true}
        currentTree="survival"
        LibStub("JustAC-RotationImport").GetForeverTree=function() return currentTree end
        P=LibStub("JustAC-PrecombatEngine")
        function Query() P.ClearCache();return P.GetMissingClassBuffs(false,90,false) end
    """)
    assert seq(lua.globals().Query()) == [13161], "Survival defaults to Aspect of the Beast"
    lua.execute("currentTree='marksmanship'")
    assert seq(lua.globals().Query()) == [13165], "ranged Hunters retain Aspect of the Hawk"
    lua.execute("auraByID[13163]={duration=0,expirationTime=0}")
    assert seq(lua.globals().Query()) == [], "any active aspect preserves the player's choice"

    lua, _ = new_runtime()
    lua.execute("""
        playerClass="WARRIOR";known={[2457]=true,[2458]=true,[71]=true}
        currentTree="fury";form=0
        LibStub("JustAC-RotationImport").GetForeverTree=function() return currentTree end
        LibStub:NewLibrary("JustAC-FormCache").GetActiveForm=function() return form end
        P=LibStub("JustAC-PrecombatEngine")
        function Query() P.ClearCache();return P.GetMissingClassBuffs(false,90,false) end
    """)
    assert seq(lua.globals().Query()) == [2458], "Fury's fallback stance is Berserker"
    lua.execute("currentTree='protection'")
    assert seq(lua.globals().Query()) == [71], "Protection's fallback stance is Defensive"
    lua.execute("currentTree='arms'")
    assert seq(lua.globals().Query()) == [2457], "Arms' fallback stance is Battle"
    lua.execute("form=2")
    assert seq(lua.globals().Query()) == [], "no reminder replaces an intentional active stance"


def test_rites_and_preparation_priority():
    lua, _ = new_runtime(False)
    lua.execute("""
        playerClass="PALADIN";known={[433568]=true,[433583]=true}
        enchanted=false;remaining=3600000
        LibStub("JustAC-BlizzardAPI").GetWeaponEnhancementInfo=function(slot)
            assert(slot==0);return enchanted,remaining
        end
        P=LibStub("JustAC-PrecombatEngine")
        function Query() P.ClearCache();return P.GetMissingClassBuffs(false,90,false) end
    """)
    assert seq(lua.globals().Query()) == [433568], "known rites use the existing weapon path"
    lua.execute("enchanted=true")
    assert seq(lua.globals().Query()) == [], "an existing weapon preparation is not overwritten"
    lua.execute("enchanted=nil")
    assert seq(lua.globals().Query()) == [], "unknown enchant presence cannot prove a missing rite"
    lua.execute("""
        enchanted=false
        LibStub("JustAC-BlizzardAPI").IsSpellUsable=function() return false end
    """)
    assert seq(lua.globals().Query()) == [], "weapon preparation needs confirmed usability"
    lua.execute('LibStub("JustAC-BlizzardAPI").IsSpellUsable=function() return true end')
    lua.execute("enchanted=false;P.NoteClassBuffApplied(433568)")
    assert seq(lua.globals().Query()) == [], "rites retain application settle suppression"

    source = (ROOT / "DefensiveEngine.lua").read_text(encoding="utf-8")
    start = source.index("    if not inCombat and not overrides\n")
    end = source.index("\n    -- Out-of-combat recovery is handled", start)
    lua.execute("""
        PrecombatEngine=P
        local group={};SpellDB.PREPARATION_BUFF_MEMBERS[20154]=group
        P.GetMissingClassBuffs=function() return {465,20154} end
        P.GetMissingBuffItems=function() return {1001,1002,1003} end
        function AppendPrecombatPetRez() end
        function PushEntry(results,id,_,_,_,_,precombat,topoff)
            assert(precombat==true)
            if id==639 then assert(topoff==true) end
            results[#results+1]=id
        end
        function BuildPrecombat(limit, excluded)
            local results,alreadyAdded={},excluded or {}
            local maxIcons=limit
            local profile={defensives={enabled=true},precombatBuffs={enabled=true}}
            local inCombat,overrides=false,nil
    """ + source[start:end] + """
            return results
        end
    """)
    assert seq(lua.globals().BuildPrecombat(1)) == [20154], "preparation survives a full consumable checklist"
    assert seq(lua.globals().BuildPrecombat(5)) == [20154, 1001, 1002, 1003, 465], \
        "preparation is offered once, then existing checklist order is preserved"
    assert seq(lua.globals().BuildPrecombat(1, lua.eval("{[20154]=true}"))) == [20154], \
        "the old DPS seal cannot exclude its own pre-combat destination"
    assert seq(lua.globals().BuildPrecombat(5, lua.eval("{[20154]=true,[465]=true}"))) == \
        [20154, 1001, 1002, 1003, 465], "all class preparation still wins DPS exclusions"
    lua.execute("""
        P.GetMissingClassBuffs=function() return {465,20154,639} end
        P.offeredTopoffHeal=639
    """)
    assert seq(lua.globals().BuildPrecombat(2)) == [20154, 639], "a cast heal fits ahead of consumables"
    assert seq(lua.globals().BuildPrecombat(6)) == [20154, 639, 1001, 1002, 1003, 465], \
        "heals are not duplicated and preserve preparation/other buff ordering"


def test_paladin_blessing_upkeep():
    lua, _ = new_runtime(precombat=False)
    lua.execute("""
        playerClass="PALADIN";known={[19740]=true}
        combat=false;restricted=false
        function InCombatLockdown() return combat end
        local B=LibStub("JustAC-BlizzardAPI")
        B.AreAurasSecret=function() return restricted end
    """)
    lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
    lua.execute("""
        P=LibStub("JustAC-PrecombatEngine")
        function Query() P.ClearCache();return P.GetMissingClassBuffs(false,80,false) end
    """)
    query = lua.globals().Query
    assert seq(query()) == [19740], "missing Blessing of Might must be offered before combat"
    for alternate in (19740, 19742, 20217, 25894):
        lua.execute(f"known[{alternate}]=true;auraByID={{[{alternate}]={{duration=300,expirationTime=now+200}}}}")
        assert seq(query()) == [], "an active blessing preserves the player's choice"
    lua.execute("auraByID={};combat=true")
    assert seq(query()) == [], "long-duration blessings do not become combat preparation"
    lua.execute("combat=false;restricted=true")
    assert seq(query()) == [], "hidden auras cannot establish a missing blessing"
    lua.execute("""
        restricted=false;known={[19834]=true}
        local RI=LibStub("JustAC-RotationImport")
        RI.RankBase=function(id) if id==19834 then return 19740 end return id end
        RI.HighestKnownRank=function(id)
            if id==19740 or id==19834 then return 19834 end
        end
    """)
    assert seq(query()) == [19834], "upkeep resolves the learned blessing rank"
    lua.execute("auraByID[19834]={duration=300,expirationTime=now+200}")
    assert seq(query()) == [], "the active learned rank satisfies blessing upkeep"

def test_upkeep_family_gaps():
    for cls, spell in (("PRIEST", 14752), ("PRIEST", 976), ("DRUID", 467),
                       ("PRIEST", 21562), ("MAGE", 23028), ("DRUID", 21849)):
        lua, _ = new_runtime()
        lua.execute(f"""
            playerClass="{cls}";known={{[{spell}]=true}}
            P=LibStub("JustAC-PrecombatEngine")
            function Query() P.ClearCache();return P.GetMissingClassBuffs(false,80,false) end
        """)
        assert seq(lua.globals().Query()) == [spell], "missing upkeep resolves a learned family member"

    for cls, base, alternate in (("PALADIN", 19740, 25782), ("PRIEST", 1243, 21562),
                                  ("PRIEST", 14752, 27681), ("PRIEST", 976, 27683),
                                  ("MAGE", 1459, 23028), ("DRUID", 1126, 21849)):
        lua, _ = new_runtime()
        lua.execute(f"""
            playerClass="{cls}";known={{[{base}]=true}}
            auraByID[{alternate}]={{duration=3600,expirationTime=now+3000}}
            P=LibStub("JustAC-PrecombatEngine")
            function Query() P.ClearCache();return P.GetMissingClassBuffs(false,80,false) end
        """)
        assert seq(lua.globals().Query()) == [], "received equivalent buffs do not require knowing their casts"
        lua.execute("auraByID={}")
        assert seq(lua.globals().Query()) == [base], "reminder returns after the equivalent buff expires"

    for alternate in (5118, 13159, 20043, 415423, 469145):
        lua, _ = new_runtime()
        lua.execute(f"""
            playerClass="HUNTER";known={{[13165]=true}}
            auraByID[{alternate}]={{duration=0,expirationTime=0}}
            P=LibStub("JustAC-PrecombatEngine")
            function Query() P.ClearCache();return P.GetMissingClassBuffs(false,80,false) end
        """)
        assert seq(lua.globals().Query()) == [], "active Hunter alternatives are never replaced with Hawk"
        lua.execute("auraByID={}")
        assert seq(lua.globals().Query()) == [13165]


def test_learned_rank_preparation():
    lua, _ = new_runtime(precombat=False)
    lua.execute("""
        playerClass="PALADIN";known={[21084]=true}
        local RI=LibStub("JustAC-RotationImport")
        RI.RankBase=function(id) if id==21084 then return 20154 end return id end
        RI.HighestKnownRank=function(id)
            if id==20154 or id==21084 then return 21084 end
            if known[id] then return id end
        end
        nextPick=21084
        local B=LibStub("JustAC-BlizzardAPI")
        B.GetAnyNextCastSpell=function() return nextPick end
        B.IsSpellUsable=function(id) return known[id]==true end
        B.IsSpellReady=function(id) return known[id]==true end
        function UnitExists() return true end
        function UnitCanAttack() return true end
        function UnitInVehicle() return false end
    """)
    lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
    lua.execute("""
        P=LibStub("JustAC-PrecombatEngine")
        function Query() P.ClearCache();return P.GetMissingClassBuffs(false,90,false) end
    """)
    assert seq(lua.globals().Query()) == [21084], \
        "level-6 learned seal is offered even when its generated canonical ID is not known"
    lua.execute("nextPick=nil")
    assert seq(lua.globals().Query()) == [21084], "default resolves to the actual learned rank"
    assert lua.globals().P.ShouldEmphasizePreparation(21084) is True, "the visible learned rank can be urgent"
    lua.execute("auraByID[21084]={duration=30,expirationTime=now+1}")
    assert seq(lua.globals().Query()) == [21084], "a near-expiry learned seal rank refreshes itself"
    assert lua.globals().P.ShouldEmphasizePreparation(21084) is True

def test_critical_preparation_context():
    cases = ((True, "PALADIN", 20154, "retribution", 1),
             (True, "HUNTER", 13165, "marksmanship", 1),
             (True, "WARRIOR", 2457, "arms", 1),
             (True, "PRIEST", 15473, "shadow", 1),
             (True, "SHAMAN", 8017, "enhancement", 1),
             (False, "DRUID", 24858, None, 1),
             (False, "PRIEST", 232698, None, 3),
             (False, "SHAMAN", 318038, None, 2),
             (False, "PALADIN", 433568, None, 1))
    for forever, cls, spell, tree, spec in cases:
        lua, _ = new_runtime(forever, precombat=False)
        lua.globals().currentTree = tree
        lua.globals().currentSpec = spec
        lua.execute(f"""
            playerClass="{cls}";known={{[{spell}]=true}}
            targetExists=true;hostile=true;dead=false;mounted=false;vehicle=false
            restricted=false;ready=true;usable=true;form=0;weaponPresent=true;enchanted=false
            function UnitExists() return targetExists end
            function UnitCanAttack() return hostile end
            function UnitIsDeadOrGhost() return dead end
            function IsMounted() return mounted end
            function UnitInVehicle() return vehicle end
            function GetInventoryItemID() if weaponPresent then return 100 end end
            LibStub:NewLibrary("JustAC-FormCache").GetActiveForm=function() return form end
            local RI=LibStub:NewLibrary("JustAC-RotationImport")
            RI.RankBase=function(id) return id end
            RI.GetForeverTree=function() return currentTree end
            C_SpecializationInfo.GetSpecialization=function() return currentSpec end
            local B=LibStub("JustAC-BlizzardAPI")
            B.AreAurasSecret=function() return restricted end
            B.IsSpellUsable=function() return usable end
            B.IsSpellReady=function() return ready end
            B.GetWeaponEnhancementInfo=function() return enchanted,1000 end
        """)
        lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
        p = lua.eval('LibStub("JustAC-PrecombatEngine")')
        assert p.ShouldEmphasizePreparation(spell) is True, (forever, cls, "confirmed missing")
        for flag in ("targetExists", "hostile", "ready", "usable"):
            lua.execute(f"{flag}=false")
            assert p.ShouldEmphasizePreparation(spell) is False, flag
            lua.execute(f"{flag}=nil")
            assert p.ShouldEmphasizePreparation(spell) is False, "unknown " + flag
            lua.execute(f"{flag}=true")
            lua.execute(f"{flag}=secretAuraID")
            assert p.ShouldEmphasizePreparation(spell) is False, "secret " + flag
            lua.execute(f"{flag}=true")
        for flag in ("dead", "mounted", "vehicle"):
            lua.execute(f"{flag}=true")
            assert p.ShouldEmphasizePreparation(spell) is False, flag
            lua.execute(f"{flag}=false")
        if cls == "SHAMAN" or spell == 433568:
            if spell == 318038:
                lua.execute("""
                    known[33757]=true
                    LibStub("JustAC-BlizzardAPI").GetWeaponEnhancementInfo=function(slot)
                        assert(slot==1, 'dual-imbue Flametongue must inspect the off-hand')
                        return enchanted,1000
                    end
                """)
                assert p.ShouldEmphasizePreparation(spell) is True
            lua.execute("enchanted=true")
            assert p.ShouldEmphasizePreparation(spell) is False, "any active enchant satisfies preparation"
            lua.execute("enchanted=nil")
            assert p.ShouldEmphasizePreparation(spell) is False, "unknown enchant is not missing"
            lua.execute("enchanted=false;weaponPresent=false")
            assert p.ShouldEmphasizePreparation(spell) is False, "no weapon cannot authorize an imbue cue"
            if spell == 318038:
                lua.execute("""
                    weaponPresent=true
                    C_Item.GetItemInfoInstant=function() return nil,nil,nil,nil,nil,4 end
                """)
                assert p.ShouldEmphasizePreparation(spell) is False, "a shield must not redirect the cue to main-hand"
        else:
            calls = lua.globals().spellQueries
            for _ in range(100):
                assert p.ShouldEmphasizePreparation(spell) is True
            assert lua.globals().spellQueries == calls, "unchanged renders must not re-query the rank family"
            lua.execute(f"auraByID[{spell}]={{duration=30,expirationTime=now+0.1}}")
            p.ClearCache()
            group = lua.eval(f'SpellDB.PREPARATION_BUFF_MEMBERS[{spell}]')
            assert p.ShouldEmphasizePreparation(spell) is (not bool(group.form)), "timed non-form refresh gets the same context tint"
            lua.execute(f"auraByID[{spell}]=nil;restricted=true")
            assert p.ShouldEmphasizePreparation(spell) is False, "restricted aura absence is unknown"
            lua.execute("restricted=false;denySpell=true")
            p.ClearCache()
            assert p.ShouldEmphasizePreparation(spell) is False, "denied reads cannot authorize urgency"
            lua.execute(f"denySpell=false;auraByID[{spell}]=secretAuraID")
            p.ClearCache()
            assert p.ShouldEmphasizePreparation(spell) is False, "a secret aura is not absent"
            lua.execute(f"auraByID[{spell}]=nil;now=now+0.251")
            assert p.ShouldEmphasizePreparation(spell) is True, "expired cached unknown evidence is re-read"
            if cls in ("PALADIN", "HUNTER"):
                alternative = 20165 if cls == "PALADIN" else 5118
                lua.execute(f"auraByID[{alternative}]={{duration=0,expirationTime=0}}")
                p.ClearCache()
                assert p.ShouldEmphasizePreparation(spell) is False, "unlearned active alternatives satisfy the family"
                lua.execute(f"auraByID[{alternative}]=nil;known[{alternative}]=true")
                p.NoteClassBuffApplied(alternative)
                assert p.ShouldEmphasizePreparation(spell) is False, "a recently applied alternative retains its settle latch"
        assert p.ShouldEmphasizePreparation(19740) is False, "routine blessing upkeep is not urgent preparation"


def test_precombat_handoff_order():
    from lupa import LuaRuntime

    source = (ROOT / "JustAC.lua").read_text(encoding="utf-8")
    start = source.index("    local queueSurfaceShown = not mainHidden or not npHidden")
    end = source.index("\nend\n\nfunction JustAC:MarkQueueDirty()", start)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        JustAC={};SpellQueue={};events={}
        function JustAC:OnHealthChanged()
            events[#events+1]="precombat"
            if throttled then return false end
        end
        function SpellQueue.ForceUpdate() events[#events+1]="invalidate-dps" end
        function JustAC:UpdateSpellQueue() events[#events+1]="render-dps" end
        function Tick(combat,dirty,blocked,periodic)
            events={};throttled=blocked
            local inCombat,defensiveQueueDirty=combat,dirty
            local spellQueueDirty=false
            local hostileTarget=false
            local mainHidden,npHidden=false,true
            local channeling=false
            local now=10
            local lastFullUpdate=10
            if periodic then lastFullUpdate=0 end
            local COMBAT_DEFENSIVE_INTERVAL,OOC_DEFENSIVE_IDLE_INTERVAL=0.1,1
    """ + source[start:end] + """
            return events
        end
    """)
    tick = lua.globals().Tick
    assert seq(tick(False, True, False, False)) == \
        ["precombat", "invalidate-dps", "render-dps"], "aura loss hands off before DPS renders"
    assert seq(tick(False, False, False, True)) == \
        ["precombat", "invalidate-dps", "render-dps"], "periodic refresh uses the same ownership order"
    tick(False, True, True, False)
    assert seq(lua.globals().events) == ["precombat"], "throttled destination cannot flash a DPS offer"
    assert seq(tick(True, True, False, False)) == \
        ["render-dps", "precombat"], "combat DPS cadence stays unchanged"
    assert seq(tick(False, False, False, False)) == ["render-dps"], "clean ticks do not rebuild precombat"

    start = source.index("function JustAC:OnUnitAura(")
    end = source.index("\n-- A macro edit", start)
    lua.execute("""
        now=10;clears=0;combat=false
        function GetTime() return now end
        function UnitAffectingCombat() return combat end
        function LibStub() return {ClearCache=function() clears=clears+1 end} end
        function JustAC:MarkQueueDirty() end
        function JustAC:InvalidateCaches() end
    """ + source[start:end])
    lua.execute('JustAC:OnUnitAura("UNIT_AURA","player",{});JustAC:OnUnitAura("UNIT_AURA","player",{})')
    assert lua.globals().clears == 2, "each OOC aura change invalidates checklist despite aura throttle"
    lua.execute('combat=true;JustAC:OnUnitAura("UNIT_AURA","player",{})')
    assert lua.globals().clears == 3, "combat aura changes invalidate the shared preparation cue"


def test_preparation_queue_exclusivity():
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    primary_start = source.index("function SpellQueue.ResolvePetRecoveryPick(")
    primary_end = source.index("\nfunction SpellQueue.GetCurrentSpellQueue()", primary_start)
    final_start = source.index("function SpellQueue._StageFinalize(")
    final_end = source.index("\n--- Stage D", final_start)
    for forever in (True, False):
        lua, _ = new_runtime(forever, precombat=False)
        pick, alternate, aura_rank = (21082, 20293, 20162) if forever else (90001, 90002, 90003)
        if not forever:
            lua.execute("""
                SpellDB.CLASS_MAINTAINED_BUFFS.MAGE={
                    {group={90001,90002},auraIDs={90001,90002,90003},preparation=true,
                     memberAuraIDs={[90001]={90001,90003},[90002]={90002}}},
                }
                SpellDB.IndexMaintainedBuffs()
            """)
        lua.execute(f"""
            primaryPick={pick};alternate={alternate};auraRank={aura_rank}
            known[primaryPick]=true;known[alternate]=true
            combat=true;restricted=false
            function UnitAffectingCombat() return combat end
            function InCombatLockdown() return combat end
            local B=LibStub("JustAC-BlizzardAPI")
            B.AreAurasSecret=function() return restricted end
            B.GetDebugMode=function() return false end
            B.GetAuras=function() return {{}},true end
            B.IsForever=function() return {str(forever).lower()} end
            B.GetDisplaySpellID=function(id) return id end
            preparationVisible=false
            B.GetAddon=function()
                return {{defensiveIcons={{{{spellID=primaryPick,isPrecombatBuff=true,
                    IsVisible=function() return preparationVisible end}}}}}}
            end
            highlight=403
            B.GetHighlightCastSpell=function() return highlight end
            auraByID[auraRank]={{duration=30,expirationTime=now+0.1,auraInstanceID=71}}
        """)
        lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
        lua.execute((ROOT / "RedundancyFilter.lua").read_text(encoding="utf-8"))
        rf = lua.eval('LibStub("JustAC-RedundancyFilter")')
        profile = lua.eval("{}")
        verdict = rf.IsSpellRedundant(pick, profile)
        assert isinstance(verdict, tuple) and verdict[0] is True, "an active preparation rank suppresses its cast"
        verdict = rf.IsSpellRedundant(alternate, profile)
        assert isinstance(verdict, tuple) and verdict[0] is True, "active alternatives satisfy the family"
        lua.execute("""
            RedundancyFilter=LibStub("JustAC-RedundancyFilter")
            BlizzardAPI=LibStub("JustAC-BlizzardAPI")
            SpellQueue=LibStub:NewLibrary("JustAC-SpellQueue")
            SpellQueue.LeadMode=function() return "game" end
            SpellQueue.IsCasterSuppressedPick=function() return false end
            SpellQueue.IsSpellBlacklisted=function() return false end
            SpellQueue._ApplySafeLead=function() end
            SpellQueue.NoteQueueBlank=function() end
            AUTO_ATTACK_SPELL=6603
            function NotePick() end
            function ClaimSpellID(id,added)
                if added[id] then return nil end
                added[id]=true;return id
            end
            function Primary()
                local b={profile={defensives={enabled=true},precombatBuffs={enabled=true}},
                    primarySpellID=primaryPick,blacklist={},addedSpellIDs={},
                    recommendedSpells={},spellCount=0,inCombat=combat}
                SpellQueue._StagePrimary(b)
                return b.recommendedSpells
            end
        """)
        lua.execute(source[primary_start:primary_end])
        lua.execute(
            "local lastSpellIDs={};local blankActive=false\n"
            + source[final_start:final_end]
            + """
            function Finalize(ids)
                local b={recommendedSpells=ids,spellCount=#ids,blacklist={},inCombat=combat,
                    profile={defensives={enabled=true},precombatBuffs={enabled=true}}}
                SpellQueue._StageFinalize(b)
                return lastSpellIDs
            end
            """
        )
        assert seq(lua.globals().Primary()) == [403], "slot 1 yields even near seal expiry"
        lua.globals().highlight = alternate
        assert seq(lua.globals().Primary()) == [], "lookahead cannot replace one active-family cast with another"
        lua.execute('combat=false;highlight=403;LibStub("JustAC-PrecombatEngine").ClearCache()')
        assert seq(lua.globals().Primary()) == [pick], "a near-expiry OOC native pick can refresh the active member"
        assert rf.IsSpellRedundant(pick, profile) is False, "the tail agrees with the bounded refresh policy"
        assert rf.IsSpellRedundant(alternate, profile)[0] is True, "the tail preserves the active choice"
        lua.execute("preparationVisible=true")
        assert seq(lua.globals().Primary()) == [403], "visible refresh offers stay off the DPS primary"
        lua.globals().highlight = alternate
        assert seq(lua.globals().Primary()) == [], "lookahead cannot swap seals during refresh handoff"
        lua.globals().Finalize(lua.table_from([pick]))
        assert seq(lua.globals().Finalize(lua.table())) == [], "stale fallback cannot duplicate a visible refresh"
        lua.execute('preparationVisible=false;combat=true;LibStub("JustAC-PrecombatEngine").ClearCache()')
        lua.execute("""
            local family=SpellDB.PREPARATION_BUFF_MEMBERS[primaryPick]
            family.form=true
            LibStub("JustAC-PrecombatEngine").ClearCache()
        """)
        assert seq(lua.globals().Primary()) == [pick], "deliberate combat form/stance changes are preserved"
        lua.execute("""
            SpellDB.PREPARATION_BUFF_MEMBERS[primaryPick].form=nil
            auraByID[auraRank].expirationTime=now+30;highlight=403
            LibStub("JustAC-PrecombatEngine").ClearCache()
        """)
        assert seq(lua.globals().Primary()) == [403]
        lua.execute("""
            auraByID={};now=now+0.01
            LibStub("JustAC-PrecombatEngine").ClearCache()
        """)
        assert rf.IsSpellRedundant(pick, profile) is False, "consumption releases combat reapplication immediately"
        assert seq(lua.globals().Primary()) == [pick], "a missing preparation can still lead combat"
        finalized = lua.globals().Finalize(lua.table_from([pick, alternate, pick, 403]))
        assert seq(finalized) == [pick, 403], "one preparation choice survives, preserving the first and unrelated spells"
        lua.globals().Finalize(lua.table_from([pick]))
        lua.execute("""
            auraByID[auraRank]={duration=30,expirationTime=now+30,auraInstanceID=72}
            LibStub("JustAC-PrecombatEngine").ClearCache()
        """)
        assert seq(lua.globals().Primary()) == [403]
        assert seq(lua.globals().Finalize(lua.table())) == [], "an active seal cannot return via stale-queue fallback"
        lua.execute("""
            denySpell=true;restricted=true
            LibStub("JustAC-PrecombatEngine").ClearCache()
        """)
        assert seq(lua.globals().Primary()) == [pick], "denied reads do not suppress the native pick"
        # The current client exposes a shared Seals record, not a separate icon for each cast.
        lua.execute("""
            local B=LibStub("JustAC-BlizzardAPI")
            B.IsSecretValue=issecretvalue
            B.Unsecret=function(v) return v end
            hooksecurefunc=function() end
            Enum={CooldownViewerCategory={Essential=0,Utility=1,TrackedBuff=2,TrackedBar=3,GroupBuff=4}}
            local family=SpellDB.PREPARATION_BUFF_MEMBERS[primaryPick]
            C_CooldownViewer={
                GetCooldownViewerCategorySet=function(cat)
                    if cat==0 then return {200288} end
                    if cat==2 then return {200340} end
                    return {}
                end,
                GetCooldownViewerCooldownInfo=function()
                    return {spellID=1323522,linkedSpellIDs=family.group}
                end,
            }
            cooldownItem={GetCooldownID=function() return 200288 end,isActive=true}
            auraItem={GetCooldownID=function() return 200340 end,isActive=true}
            items={cooldownItem,auraItem};viewerShown=true
            BuffIconCooldownViewer={
                IsShown=function() return viewerShown end,
                itemFramePool={EnumerateActive=function()
                    local i=0
                    return function() i=i+1;return items[i] end
                end},
            }
        """)
        lua.execute((ROOT / "MaintenanceTracker.lua").read_text(encoding="utf-8"))
        lua.execute('LibStub("JustAC-PrecombatEngine").ClearCache()')
        calls = lua.globals().spellQueries
        assert seq(lua.globals().Primary()) == [403], "the live shared aura suppresses slot 1 despite denied spell-ID reads"
        assert lua.globals().spellQueries == calls, "positive combat viewer evidence does not attempt direct aura calls"
        lua.execute('combat=false;LibStub("JustAC-PrecombatEngine").ClearCache()')
        assert seq(lua.globals().Primary()) == [403], "an active-only shared signal cannot authorize OOC refresh"
        lua.execute("combat=true")
        verdict = rf.IsSpellRedundant(alternate, profile)
        assert isinstance(verdict, tuple) and verdict[0] is True, "the shared aura also suppresses ranked alternatives in the tail"
        lua.globals().highlight = alternate
        assert seq(lua.globals().Primary()) == [], "shared-aura lookahead cannot reinsert another seal"
        lua.globals().Finalize(lua.table_from([pick]))
        assert seq(lua.globals().Finalize(lua.table())) == [], "shared-aura suppression covers stale queue fallback"
        lua.globals().highlight = 403
        for setup in (
            "auraItem.isActive=false",
            "auraItem.isActive=secretAuraID",
            "auraItem.isActive=nil",
            "auraItem.isActive=true;viewerShown=false",
            "viewerShown=true;items={cooldownItem}",
        ):
            lua.execute(setup)
            assert seq(lua.globals().Primary()) == [pick], (setup, "down/unknown aura releases the pick; cooldown activity is not aura activity")


def test_ooc_item_click_stack():
    for forever in (True, False):
        lua, _ = new_runtime(forever, precombat=False)
        lua.execute(r"""
            combat=false;busy=false;slotReads=0;denyBag=false
            frames={};used={};timers={}
            NUM_TOTAL_EQUIPPED_BAG_SLOTS=4
            STANDARD_TEXT_FONT="font";UIParent={}
            function InCombatLockdown() return combat end
            function RegisterStateDriver() end
            LibStub("JustAC-BlizzardAPI").IsSecretValue=issecretvalue
            local methods={}
            for _, name in ipairs({"SetHighlightTexture","SetFont","SetTextColor","SetPoint",
                "ClearAllPoints","SetSize","SetFrameStrata","SetFrameLevel"}) do
                methods[name]=function() end
            end
            function methods:SetAttribute(key,value)
                assert(not combat,"protected attributes cannot change in combat")
                self.attributes[key]=value
            end
            function methods:SetScript(key,value) self.scripts[key]=value end
            function methods:GetScript(key) return self.scripts[key] end
            function methods:RegisterEvent(event) self.events[event]=true end
            function methods:RegisterForClicks() end
            function methods:GetEffectiveScale() return 1 end
            function methods:GetFrameLevel() return 1 end
            function methods:GetFrameStrata() return "MEDIUM" end
            function methods:GetRect() return 10,20,32,32 end
            function methods:Show() self.shown=true end
            function methods:Hide() self.shown=false end
            function methods:IsShown() return self.shown end
            function methods:IsVisible() return self.shown end
            function methods:SetText(text) self.text=text end
            function methods:CreateFontString() return CreateFrame("FontString") end
            function CreateFrame(kind,name)
                local frame=setmetatable({name=name,attributes={},scripts={},events={},shown=true},
                    {__index=methods})
                frames[#frames+1]=frame
                if name then frames[name]=frame end
                return frame
            end
            C_Timer={After=function(_,callback) timers[#timers+1]=callback end}
            function Fire(event)
                for _,frame in ipairs(frames) do
                    if frame.events[event] then frame.scripts.OnEvent(frame,event) end
                end
            end
            function RunTimers()
                local callbacks=timers;timers={}
                for _,callback in ipairs(callbacks) do callback() end
            end
            bagSlots={[0]={
                [1]={itemID=117,stackCount=5,isLocked=true},
                [2]={itemID=117,stackCount=5,isLocked=false},
            }}
            C_Container={
                GetContainerNumSlots=function() return 4 end,
                GetContainerItemInfo=function(bag,slot)
                    slotReads=slotReads+1
                    if denyBag then error("bag lookup denied") end
                    return bagSlots[bag] and bagSlots[bag][slot]
                end,
                UseContainerItem=function(bag,slot)
                    local info=bagSlots[bag] and bagSlots[bag][slot]
                    assert(info and not info.isLocked,"must not use a locked/moved stack")
                    used[#used+1]={bag,slot,info.itemID}
                end,
            }
            local S=LibStub("JustAC-SpellDB")
            S.GetPrecombatBuffCategory=function(id) if id==900 then return "weaponEnchant" end end
            LibStub:NewLibrary("JustAC-PrecombatEngine").IsBusyApplying=function() return busy end
            icon=CreateFrame("Button");icon.isItem=true;icon.itemID=117;icon.isPrecombatBuff=true
            addon={defensiveIcons={icon},GetProfile=function() return {} end}
            -- Same bag/slot routing as the native secure item action. An ID-only action
            -- must not choose a different or currently locked stack implicitly.
            function Click(down,useOnKeyDown)
                local layer=frames.JustACClickLayer1
                if layer.scripts.PreClick then layer.scripts.PreClick(layer,"LeftButton",down) end
                if down~=useOnKeyDown or not layer.attributes.type1 then return end
                local action=layer.attributes.item
                if layer.attributes.type1=="macro" then
                    action=layer.attributes.macrotext:match("^/use ([^\n]+)")
                end
                local bag,slot=action:match("^(%d+)%s+(%d+)$")
                assert(bag,"item click must resolve an unlocked bag stack, not use by ID")
                C_Container.UseContainerItem(tonumber(bag),tonumber(slot))
            end
        """)
        lua.execute((ROOT / "UI" / "UIPrecombatOverlay.lua").read_text(encoding="utf-8"))
        lua.execute(r"""
            O=LibStub("JustAC-PrecombatOverlay");O.Init(addon)
            local reads=slotReads
            for i=1,20 do O.Refresh() end
            assert(slotReads==reads,"unchanged render ticks must not rescan bags")
            Click(true,false);Click(false,false)
            assert(#used==1 and used[1][2]==2 and used[1][3]==117,
                "food must use the unlocked stack: "..table.concat(messages,"; "))

            -- A sort moves the stack without changing the recommendation's item ID.
            -- The click must recheck even before the deferred bag update arrives.
            bagSlots[0][2]={itemID=222,stackCount=1,isLocked=false}
            bagSlots[0][3]={itemID=117,stackCount=5,isLocked=false}
            Click(true,true);Click(false,true)
            assert(#used==2 and used[2][2]==3 and used[2][3]==117)
            bagSlots[0][3].isLocked=true
            Click(false,false)
            assert(#used==2 and frames.JustACClickLayer1.disarmed)
            assert(frames.JustACClickLayer1.clickHint.text=="wait")
            reads=slotReads
            for i=1,20 do O.Refresh() end
            assert(slotReads==reads,"locked stacks must not cause per-frame bag rescans")
            bagSlots[0][3].isLocked=false
            Fire("ITEM_LOCK_CHANGED");RunTimers()
            assert(not frames.JustACClickLayer1.disarmed)
            Click(false,false)
            assert(#used==3)
            busy=true;Click(false,false);assert(#used==3)
            busy=false
            function CursorHasItem() return true end
            Click(false,false);assert(#used==3,"a held item must not collide with consumption")
            function CursorHasItem() return false end
            MerchantFrame={IsShown=function() return true end}
            Fire("MERCHANT_SHOW");RunTimers()
            assert(frames.JustACClickLayer1.disarmed)
            Click(false,false);assert(#used==3,"item clicks must not sell food at a merchant")
            MerchantFrame=nil
            Fire("MERCHANT_CLOSED");RunTimers()
            assert(not frames.JustACClickLayer1.disarmed,"closing the merchant restores consumption")
            BankFrame={IsShown=function() return true end}
            Click(false,false);assert(#used==3,"item clicks must not deposit food into a bank")
            BankFrame=nil
            Enum={PlayerInteractionType={Banker=1}}
            C_PlayerInteractionManager={IsInteractingWithNpcOfType=function() return true end}
            Click(false,false);assert(#used==3,"hidden bank UI still blocks item transfers")
            C_PlayerInteractionManager=nil

            bagSlots[0][3].itemID=secretAuraID
            Click(false,false);assert(#used==3)
            bagSlots[0][3].itemID=117
            bagSlots[0][3].isLocked=secretAuraID
            Click(false,false);assert(#used==3)
            bagSlots[0][3].isLocked=false
            denyBag=true;Click(false,false)
            assert(#used==3 and #messages==1,"denied lookups disarm and report the error")
            denyBag=false
            bagSlots[0][1]=nil;bagSlots[0][3]=nil
            Click(false,false);assert(#used==3,"a missing item must not use the old slot")

            icon.itemID=900
            bagSlots[0][4]={itemID=900,stackCount=1,isLocked=false}
            O.OverlayClickLayers(addon)
            assert(frames.JustACClickLayer1.attributes.macrotext=="/use 0 4\n/use 16",
                "weapon enhancements retain both use steps")
            combat=true;Fire("BAG_UPDATE_DELAYED");O.Refresh()
            assert(#timers==0,"bag events must not schedule combat overlay work")
            combat=false;Fire("PLAYER_REGEN_ENABLED");RunTimers()
        """)


def main():
    test_ooc_item_click_stack()
    test_preparation_refresh_window()
    test_precombat_handoff_order()
    test_contextual_preparation()
    test_rites_and_preparation_priority()
    test_learned_rank_preparation()
    test_paladin_blessing_upkeep()
    test_upkeep_family_gaps()
    test_critical_preparation_context()
    test_preparation_queue_exclusivity()
    lua, db = new_runtime(precombat=False)
    lua.execute("""
        combat=false;restricted=false;nextPick=nil;rotation={};queue={}
        playerClass="PALADIN";icons={}
        function InCombatLockdown() return combat end
        function UnitAffectingCombat() return combat end
        local B=LibStub("JustAC-BlizzardAPI")
        B.AreAurasSecret=function() return restricted end
        B.GetAnyNextCastSpell=function() return nextPick end
        B.GetRotationSpells=function() return rotation end
        B.GetDebugMode=function() return false end
        B.GetAuras=function() return {},true end
        B.GetAddon=function() return {defensiveIcons=icons} end
        LibStub:NewLibrary("JustAC-SpellQueue").GetCurrentSpellQueue=function() return queue end
        local bases={}
        local RI=LibStub("JustAC-RotationImport")
        RI.RankBase=function(id) return bases[id] or id end
        local groups=SpellDB.CLASS_MAINTAINED_BUFFS.PALADIN
        for _,grp in ipairs(groups) do
            for id,auras in pairs(grp.memberAuraIDs) do
                known[id]=true
                for _,rank in ipairs(auras) do bases[rank]=id end
            end
        end
        -- Unrelated aura and blessing upkeep are already satisfied.
        auraByID[465]={duration=0,expirationTime=0}
        auraByID[19740]={duration=300,expirationTime=now+200}
    """)
    lua.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
    lua.execute("""
        P=LibStub("JustAC-PrecombatEngine")
        function Query()
            P.ClearCache()
            return P.GetMissingClassBuffs(false,90,false)
        end
    """)
    p = lua.globals().P
    query = lua.globals().Query
    group = next(g for g in db.CLASS_MAINTAINED_BUFFS.PALADIN.values() if g.preparation)
    assert len(group.group) == 7
    assert seq(query()) == [20154], "missing seals use the existing default"

    lua.execute("queue={20165};nextPick=20154")
    for member in group.group.values():
        for rank in group.memberAuraIDs[member].values():
            lua.execute(f"auraByID[{rank}]={{duration=30,expirationTime=now+0.1}}")
            assert seq(query()) == [member], ("refresh preserves the active seal instead of the demand/default", rank)
            assert db.PREPARATION_BUFF_MEMBERS[rank] is not None
            lua.execute(f"auraByID[{rank}]=nil")
    lua.execute("nextPick=nil")
    assert seq(query()) == [20165], "missing group respects the queue's chosen alternative"
    lua.execute("queue={};rotation={20375}")
    assert seq(query()) == [20375], "an unambiguous rotation member takes precedence"
    lua.execute("rotation={};nextPick=20164")
    assert seq(query()) == [20164], "an explicit current demand chooses the missing seal"

    lua.execute("nextPick=nil;denySpell=true")
    assert seq(query()) == [], "denied reads cannot prove absence"
    assert len(lua.globals().messages) == 1, "read failures are reported"
    lua.execute("denySpell=false;restricted=true")
    assert seq(query()) == [], "secret aura contexts do not produce missing-buff cues"
    lua.execute("restricted=false;auraByID[20154]=secretAuraID")
    assert seq(query()) == [], "secret aura payloads remain unknown"
    lua.execute("auraByID[20154]=nil")

    p.NoteClassBuffApplied(20293)  # Higher rank of Seal of Righteousness.
    assert p.IsClassBuffFresh(20154) is True
    assert seq(query()) == [], "cast settle grace prevents duplicate pre-pull applications"
    lua.execute("combat=true")
    assert p.IsClassBuffFresh(20154) is False, "the pull releases the preparation latch"
    assert seq(query()) == [], "no preparation offers in combat"
    lua.execute((ROOT / "RedundancyFilter.lua").read_text(encoding="utf-8"))
    rf = lua.eval('LibStub("JustAC-RedundancyFilter")')
    profile = lua.eval("{defensives={enabled=true},precombatBuffs={enabled=true}}")
    assert rf.IsUpkeepSpell(20154) is False, "seals remain valid combat priority entries"
    assert rf.IsSpellRedundant(20154, profile) is False, "OOC grace cannot suppress combat recovery"

    lua.execute("combat=false;now=now+4")
    lua.execute("""
        icons[1]={spellID=20154,isPrecombatBuff=true,IsVisible=function() return true end}
    """)
    assert p.IsOfferedNow(20293, profile) is True, "visible preparation deduplicates across ranks"
    assert rf.IsSpellRedundant(20293, profile)[0] is True
    for expression in (
        "{defensives={enabled=false},precombatBuffs={enabled=true}}",
        "{defensives={enabled=true},precombatBuffs={enabled=false}}",
    ):
        assert p.IsOfferedNow(20154, lua.eval(expression)) is False, "disabled surfaces do not steal the offer"
    lua.execute("icons[1].IsVisible=function() return false end")
    assert p.IsOfferedNow(20154, profile) is False
    # Slot 1 is inserted separately from the filtered tail. It must route the
    # displayed preparation offer too, without suppressing a real combat pick.
    source = (ROOT / "SpellQueue.lua").read_text(encoding="utf-8")
    start = source.index("function SpellQueue.ResolvePetRecoveryPick(")
    end = source.index("\nfunction SpellQueue.GetCurrentSpellQueue()", start)
    lua.execute("""
        SpellQueue=LibStub("JustAC-SpellQueue")
        SpellQueue.LeadMode=function() return "game" end
        SpellQueue.IsCasterSuppressedPick=function() return false end
        SpellQueue.IsSpellBlacklisted=function() return false end
        AUTO_ATTACK_SPELL=6603
        function NotePick() end
        function ClaimSpellID(id,added)
            if added[id] then return nil end
            added[id]=true
            return id
        end
        BlizzardAPI=LibStub("JustAC-BlizzardAPI")
        BlizzardAPI.GetDisplaySpellID=function(id) return id end
        BlizzardAPI.IsForever=function() return true end
        highlight=679;preEnabled=true;defEnabled=true
        BlizzardAPI.GetHighlightCastSpell=function() return highlight end
        function Primary()
            local b={profile={defensives={enabled=defEnabled},precombatBuffs={enabled=preEnabled}},
                primarySpellID=20293,blacklist={},addedSpellIDs={},
                recommendedSpells={},spellCount=0,inCombat=combat}
            SpellQueue._StagePrimary(b)
            return b.recommendedSpells
        end
        icons[1].IsVisible=function() return true end
    """)
    lua.execute(source[start:end])
    assert seq(lua.globals().Primary()) == [679], "preparation cannot take DPS slot 1 before combat"
    lua.execute("icons[1].spellID=20165")
    assert seq(lua.globals().Primary()) == [679], "a visible preparation alternative routes the whole group"
    assert rf.IsSpellRedundant(20293, profile)[0] is True, "the tail routes preparation siblings too"
    lua.execute("highlight=20165")
    assert seq(lua.globals().Primary()) == [], "highlight lookahead cannot reinsert preparation"
    lua.execute("highlight=679")
    lua.execute("icons[1].spellID=20154")
    lua.execute("combat=true")
    assert seq(lua.globals().Primary()) == [20293], "combat retains the game's seal recommendation"
    lua.execute("combat=false;icons[1].IsVisible=function() return false end")
    assert seq(lua.globals().Primary()) == [20293], "hidden preparation preserves the DPS fallback"
    lua.execute("icons[1].IsVisible=function() return true end;preEnabled=false")
    assert seq(lua.globals().Primary()) == [20293], "disabled preparation preserves the primary DPS fallback"
    lua.execute("preEnabled=true;defEnabled=false")
    assert seq(lua.globals().Primary()) == [20293], "disabled defensive bar preserves the primary DPS fallback"
    lua.execute("defEnabled=true")
    lua.execute("combat=true;P.NoteClassBuffApplied(20293)")
    assert p.IsClassBuffFresh(20293) is False, "combat casts cannot arm an effective preparation hold"

    # A non-Paladin synthetic group proves the policy is not a class/spell exception.
    for forever in (True, False):
        generic, generic_db = new_runtime(forever)
        generic.execute("""
            playerClass="MAGE";known={[90001]=true,[90002]=true}
            SpellDB.CLASS_MAINTAINED_BUFFS.MAGE={
                {group={90001,90002},default=90001,preparation=true},
            }
            SpellDB.IndexMaintainedBuffs()
            local B=LibStub("JustAC-BlizzardAPI")
            B.GetAnyNextCastSpell=function() return 90001 end
            auraByID[90002]={duration=10,expirationTime=now+1}
        """)
        engine = generic.eval('LibStub("JustAC-PrecombatEngine")')
        assert seq(engine.GetMissingClassBuffs(False, 90, False)) == [90002], "generic refresh preserves the active alternative"
        generic.execute("auraByID={}")
        engine.ClearCache()
        assert seq(engine.GetMissingClassBuffs(False, 90, False)) == [90001]
        assert generic_db.PREPARATION_BUFF_MEMBERS[90001] is not None
        generic_db.IndexMaintainedBuffs()
    retail, retail_db = new_runtime(False)
    assert retail_db.PREPARATION_BUFF_MEMBERS[20154] is None, "Forever seals do not leak into Retail"

    # Existing shared combat tail still establishes a seal and prioritizes Judgement once active.
    queue = create_runtime(real_gates=True)
    queue.execute("""
        Reset();specKey="PALADIN_F";b.inCombat=true;b.maxIcons=1
        entries=classes.PALADIN_F.retribution.st;pool={20154,20271}
        ranges[20154],ranges[20271]=true,true
        auraUp=false
        BlizzardAPI.IsBuffWindowActive=function(id) return auraUp and id==20154 end
    """)
    assert seq(queue.globals().BuildStage()) == [20154]
    queue.execute("auraUp=true;b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0")
    assert seq(queue.globals().BuildStage()) == [20271]
    queue.execute("auraUp=false;b.addedSpellIDs={};b.recommendedSpells={};b.spellCount=0")
    assert seq(queue.globals().BuildStage()) == [20154], "a missing seal returns to combat priority"
    print("Precombat preparation: tree/spec context, forms/stances, resources, rites, "
          "all seal ranks, unknown reads, primary/tail family suppression, queue exclusivity, checklist priority, "
          "hidden/disabled fallback, Retail isolation and combat reapplication passed")


if __name__ == "__main__":
    main()
