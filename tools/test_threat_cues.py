# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Threat button (opt-in): which threat role the target calls for, and which spell answers it.

Loads the real threat block of DefensiveEngine.lua. Damage or healer about to pull (state 1)
or holding aggro: a threat drop. A tank (aura or Tank role) on the list but not tanking: a
taunt; tanking with a slipping lead: a boost. Only with a group or a pet; every unknown or
secret read offers nothing; the spell must be known, ready, usable and in range.

Run: python tools/test_threat_cues.py
"""
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def main():
    source = (ROOT / "DefensiveEngine.lua").read_text(encoding="utf-8")
    start = source.index("-- Threat button (opt-in: profile.defensives.threatCues)")
    start = source.rindex("\n----", 0, start)
    end = source.index("\nend\n", source.index("function DefensiveEngine.GetThreatCue(")) + len("\nend\n")
    spelldb = (ROOT / "SpellDB.lua").read_text(encoding="utf-8")
    t_start = spelldb.index("function SpellDB.IsPlayerTank(")
    t_end = spelldb.index("\nend\n", t_start) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        DefensiveEngine, secret = {}, {}
        function PushEntry(results, id) local e = {spellID = id}; results[#results + 1] = e; return e end
        SpellDB = { FOREVER_THREAT_ROLES = {
            [355] = "taunt", [694] = "taunt", [7400] = "taunt",   -- Taunt; Mocking Blow r1, r2
            [586] = "drop", [9578] = "drop", [1966] = "drop",     -- Fade r1, r2; Feint
            [7386] = "boost", [71] = "tank", [1161] = "groupTaunt",   -- Challenging Shout
        },
            GetSpecKey = function() return "WARRIOR_F" end,
            IsTankTree = function(spec, t) return spec == "WARRIOR_F" and t == "protection" end,
        }
        ranks = { [7400] = 694, [9578] = 586 }
        known, cooldown, unusable, short, outOfRange = {}, {}, {}, {}, {}
        rank = function(id) return ranks[id] or id end
        libs = { ["JustAC-RotationImport"] = {
            RankBase = rank,
            GetForeverTree = function() return tree end,
            HighestKnownRank = function(base)
                local best
                for id in pairs(SpellDB.FOREVER_THREAT_ROLES) do
                    if rank(id) == base and known[id] and (not best or id > best) then best = id end
                end
                return best
            end,
        } }
        LibStub = function(name) return libs[name] end
        BlizzardAPI = {
            IsSecretValue = function(v) return rawequal(v, secret) end,
            IsGrouped = function() return grouped end,
            IsSpellReady = function(id) return not cooldown[id] end,
            IsSpellUsable = function(id) return not unusable[id], short[id] == true end,
            AbilityInRange = function(id) if outOfRange[id] then return false end return nil end,
        }
        function UnitExists(u) if u == "pet" then return pet end return target end
        function UnitCanAttack() return attackable end
        function UnitHasEffectivelyTankAura() return tankAura end
        function UnitGroupRolesAssigned() return role end
        function UnitThreatSituation() return state end
        function UnitDetailedThreatSituation() return tanking end
        function UnitThreatLeadSituation() return lead end
        C_Secrets = { ShouldUnitThreatStateBeSecret = function() return stateSecret end }
        function IsSecret(v) return rawequal(v, secret) end
    """ + spelldb[t_start:t_end] + source[start:end])
    cue = lua.eval("DefensiveEngine.GetThreatCue")
    on = lua.eval("{defensives={threatCues=true}}")
    base = ("target, grouped, pet, tankAura, role = true, true, false, false, 'NONE';"
            "state, tanking, lead, stateSecret, tree, attackable = nil, nil, nil, false, 'arms', true;"
            "known, cooldown, unusable, short, outOfRange = {[355]=true,[694]=true,[7400]=true,"
            "[586]=true,[9578]=true,[1966]=true,[7386]=true,[1161]=true}, {}, {}, {}, {}")
    for setup, role, spell, why in (
        ("state=0", None, None, "below the tank: nothing"),
        ("state=1", "drop", 9578, "about to pull: a threat drop, at its highest known rank"),
        ("state=1; known[9578]=nil; known[586]=nil", "drop", 1966, "no Fade known: Feint"),
        ("state=3", "drop", 9578, "already holding aggro as damage: drop it"),
        ("state=1; grouped=false", None, None, "solo, no pet: threat means nothing"),
        ("state=1; grouped=false; pet=true", "drop", 9578, "solo with a pet holding aggro"),
        ("state=1; grouped=nil", None, None, "group unknown and no pet: nothing"),
        ("state=secret", None, None, "a secret state offers nothing"),
        ("state=1; stateSecret=true", None, None, "the game says threat is secret here"),
        ("state=1; stateSecret=nil", None, None, "unknown secrecy offers nothing"),
        ("state=nil", None, None, "not on its threat list"),
        ("target=false; state=1", None, None, "no target"),
        ("target=secret; state=1", None, None, "a secret target read (an instance) hides the button"),
        ("attackable=secret; state=1", None, None, "a secret attackable read hides the button"),
        ("attackable=false; state=1", None, None, "a friendly target: nothing"),
        ("role='TANK'; state=0; tanking=false", "taunt", 355, "a tank not tanking its target: taunt"),
        ("tankAura=true; state=0; tanking=false", "taunt", 355, "a tank stance counts as a tank"),
        ("role='TANK'; state=0; tanking=false; cooldown[355]=true", "taunt", 7400,
         "Taunt on cooldown: Mocking Blow, highest known rank"),
        ("role='TANK'; state=0; tanking=false; outOfRange[355]=true; outOfRange[7400]=true", "taunt", None,
         "every taunt out of range: nothing to press"),
        ("role='TANK'; state=3; tanking=true; lead=0", None, None, "a secure lead: nothing"),
        ("role='TANK'; state=2; tanking=true; lead=1", "boost", 7386, "a slipping lead: a threat boost"),
        ("role='TANK'; state=2; tanking=true; lead=1; short[7386]=true", "boost", None, "the boost unaffordable"),
        ("role='TANK'; state=2; tanking=true; lead=secret", None, None, "an unreadable lead: nothing"),
        ("role='TANK'; state=0; tanking=secret", None, None, "an unreadable tanking flag: nothing"),
        ("role=secret; state=1", "drop", 9578, "an unreadable role is not a tank"),
        # An assigned Damage or Healer role wins over the stance and the tree.
        ("role='DAMAGER'; tankAura=true; state=1", "drop", 9578, "Damage role in a tank stance: damage"),
        ("role='DAMAGER'; tree='protection'; state=0; tanking=false", None, None,
         "Protection playing damage beside the tank: no taunt"),
        ("role='HEALER'; tree='protection'; state=1", "drop", 9578, "Healer role: not the tank"),
        ("role='NONE'; tankAura=true; state=0; tanking=false", "taunt", 355, "no role: the stance decides"),
        ("role='NONE'; tree='protection'; state=0; tanking=false", "taunt", 355, "no role: the tree decides"),
        # A group taunt is never offered for one lost target.
        ("role='TANK'; state=0; tanking=false; cooldown[355]=true; cooldown[7400]=true", "taunt", None,
         "Taunt and Mocking Blow on cooldown: not Challenging Shout"),
        # A tank tree, or the Tank role, holds through a stance swap (no tank aura for a moment).
        ("tree='protection'; state=0; tanking=false", "taunt", 355, "Protection out of stance: still the tank"),
        ("tree='protection'; state=2; tanking=true; lead=1", "boost", 7386, "Protection out of stance: lead slipping"),
        ("tree='protection'; state=3; tanking=true; lead=0", None, None, "Protection holding aggro: nothing to drop"),
        ("role='TANK'; tree='arms'; state=3; tanking=true; lead=0", None, None, "the Tank role in Battle Stance"),
        ("tree='arms'; state=1", "drop", 9578, "Arms out of a tank stance, no Tank role: damage"),
    ):
        lua.execute(base + ";" + setup)
        got_role = lua.eval("DefensiveEngine.WantedThreatRole()")
        got_spell = cue(on, True)
        assert got_role == role, (why, "role", got_role, role)
        assert got_spell == spell, (why, "spell", got_spell, spell)
    lua.execute(base + "; state=1")
    assert cue(lua.eval("{defensives={threatCues=false}}"), True) is None, "off by default: hidden"
    assert cue(on, False) is None, "out of combat: hidden"
    assert cue(on, True) == 9578, "on and in combat: the threat drop"
    print("Threat button: drop, taunt and boost from the target's plain reads; unknowns, solo, off and "
          "out of combat stay hidden")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
