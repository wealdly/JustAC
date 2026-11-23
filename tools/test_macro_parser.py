# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The macro parser reads a macro as the client does (Blizzard_ChatFrameBase: the command is the
line's first word; /castsequence, /castrandom and /userandom hold comma lists in ;-branches) and
answers which key a spell is on, not what would fire this moment. Loads the real MacroParser.lua.

Run: python tools/test_macro_parser.py
"""
from pathlib import Path

from wow_stubs import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = """
local stub; stub = setmetatable({}, { __index = function() return stub end, __call = function() return nil end })
setmetatable(_G, { __index = function() return stub end })
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local libs = {}
LibStub = setmetatable({ libs = libs, NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
inCombat, stealthed, form, learned, ranks = false, false, 0, {}, {}
names = { rend = 772, ["improved rend"] = 12286, other = 999 }
local B = LibStub:NewLibrary("JustAC-BlizzardAPI")
B.GetDebugMode = function() return false end
B.GetSpellInfo = function() return nil end
B.IsSpellAvailable = function() error("[known] asks what is learned, not what can be pressed") end
LibStub:NewLibrary("JustAC-FormCache").GetActiveForm = function() return form end
LibStub:NewLibrary("JustAC-RotationImport").HighestKnownRank = function(id) return ranks[id] end
C_Spell = { GetOverrideSpell = function() return nil end,
            GetSpellInfo = function(n) if names[n] then return { spellID = names[n] } end end }
C_SpecializationInfo = { GetSpecialization = function() return 0 end }
C_SpellBook = { FindBaseSpellByID = function(id) return id end }
GetTime = function() return 100 end
function UnitAffectingCombat() return inCombat end
function IsStealthed() return stealthed end
function IsPlayerSpell(id) return learned[id] == true end
function IsSpellKnown(id) return false end
body = ""
function GetActionText() return "M" end
function GetActionInfo() return "macro", 1, "" end
function GetMacroInfo(i) if i == 1 then return "M", 0, body end end
function GetNumMacros() return 1, 0 end
"""

BANE = """#showtooltip
/petattack [nocombat,harm]
/castsequence [@mouseover,harm,nodead][] reset=target/combat Bane of Agony, !Shoot, null"""


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute((ROOT / "MacroParser.lua").read_text(encoding="utf-8"))
    parser = lua.eval('LibStub.libs["JustAC-MacroParser"]')
    g = lua.globals()

    def read(body, spell="X"):
        """None when the macro does not hold the spell, else its modifiers."""
        parser.InvalidateMacroCache()
        ok, modifiers = parser.ParseMacroForSpell(body, 100, spell)
        return dict(modifiers.items()) if ok else None

    def found(body, spell="X"):
        return read(body, spell) is not None

    # /castsequence: the reset clause, and branches with their own conditions.
    for body, spell, expected, why in (
        (BANE, "Bane of Agony", True, "the spell right after reset= is in the sequence"),
        (BANE, "Shoot", True, "a later entry, with its repeat marker"),
        (BANE, "Corruption", False, "a spell the macro does not name"),
        ("/castsequence reset=3 Maul, Swipe", "Maul", True, "reset by seconds"),
        ("/castsequence reset=3 Maul, Swipe", "Swipe", True, "the second entry"),
        ("/castsequence reset=3, Maul, Swipe", "Maul", True, "a comma after the reset clause"),
        ("/castsequence reset=target/combat/5 Maul", "Maul", True, "several reset conditions"),
        ("/castsequence Maul, Swipe", "Maul", True, "no reset clause"),
        ("/castsequence [nomod] reset=5 Maul, Swipe", "Maul", True, "conditions before the reset clause"),
        ("/castsequence [mod:shift] reset=5 Maul, Swipe; [nomod] Claw, Rake", "Swipe", True, "an earlier branch"),
        ("/castsequence [mod:shift] reset=5 Maul, Swipe; [nomod] reset=3 Claw, Rake", "Claw", True, "a later branch"),
    ):
        assert found(body, spell) is expected, (why, body, spell)
    branches = "/castsequence [mod:shift] Maul, Swipe; [nomod] Claw, Rake"
    assert read(branches, "Maul") == {"mod": "shift"}, "a branch keeps its own conditions"
    assert read(branches, "Rake") == {"nomod": True}, "and the next branch keeps its own"

    # /castrandom and /userandom hold comma lists too.
    assert found("/castrandom Maul, X") and found("/userandom [nomod] X, Maul"), "random lists are read"

    # The command is the line's first word.
    for body in ("/say /use X", "/run print(1) -- /cast X", "#show /cast X", "/cast[nomod] X"):
        assert not found(body), (body, "only mentions a command")
    assert found("  /cast X") and found("/CAST X") and found("/use [mod][]X"), "real commands are read"

    # A group needing no modifier decides.
    assert read("/use [mod][]X") == {}, "a plain press also casts it"
    assert read("/cast [mod:shift][nomod] X") == {"nomod": True}, "the plain group decides"
    assert read("/cast [][mod:shift] X") == {}, "in either order"
    assert read("/cast [mod:shift][mod:alt] X") == {"mod": "shift"}, "only modified: the first one shows"

    # Combat and stealth change what fires now, not the key.
    for body in ("/cast [combat] X; Y", "/cast [nocombat] X; Y", "/cast [stealth] X; Y", "/cast [nostealth] X; Y"):
        for combat, stealth in ((False, False), (True, False), (False, True)):
            g.inCombat, g.stealthed = combat, stealth
            assert found(body), (body, combat, stealth)
    g.inCombat, g.stealthed = False, False
    g.body = "/cast [combat] X; Y"
    parser.InvalidateMacroCache()
    assert parser.GetMacroSpellInfo(1, 100, "X") is not None, "found out of combat"
    g.inCombat = True
    assert parser.GetMacroSpellInfo(1, 100, "X") is not None, "and still found in combat"
    g.inCombat = False
    g.form = 1
    assert found("/cast [form:1] X") and not found("/cast [form:2] X"), "a form still decides the bar"
    g.form = 0

    # [known] and [noknown]: learned at any rank, lists, and names that cannot be resolved.
    lua.execute("learned = {[772] = true}")
    for condition, expected, why in (
        ("known:rend", True, "learned"),
        ("noknown:rend", False, "learned, so noknown fails"),
        ("known:772", True, "by spell id"),
        ("known:other/rend", True, "a list holds when any entry does"),
        ("noknown:other/rend", False, "and noknown fails when any entry does"),
        ("known:other", False, "not learned"),
        ("noknown:other", True, "not learned, so noknown holds"),
        ("known:no such spell", True, "an unresolved name proves nothing"),
        ("noknown:no such spell", True, "either way"),
    ):
        assert found(f"/cast [{condition}] X") is expected, (condition, why)
    lua.execute("learned, ranks = {}, {[772] = 6546}")
    assert found("/cast [known:772] X"), "a higher rank learned counts for rank 1"
    lua.execute("ranks = {}; learned = {[12286] = true}")
    assert found("/cast [known:improved rend] X"), "a passive talent counts"
    # [equipped] and [worn]: the key follows the gear. Macros take any case; the query (exact
    # here on purpose) gets the client's own spelling of the type.
    lua.execute("""worn = {Shields = true}
Enum = {ItemClass = {Weapon = 2, Armor = 4}, ItemWeaponSubclass = {Dagger = 15}, ItemArmorSubclass = {Shield = 6},
        SpellBookSpellBank = {Player = 0, Pet = 1}}
C_Item = {IsEquippedItemType = function(t) return worn[t] == true end,
          GetItemSubClassInfo = function(c, s)
              if c == 4 and s == 6 then return "Shields" end
              if c == 2 and s == 15 then return "Daggers" end
          end}""")
    for condition, expected, why in (
        ("equipped:Shields", True, "a shield is on"),
        ("worn:Shields", True, "worn is the same conditional"),
        ("noequipped:Shields", False, "so its negation fails"),
        ("noworn:Shields", False, "under either name"),
        ("equipped:Daggers", False, "nothing of that type is on"),
        ("noequipped:Daggers", True, "so its negation holds"),
        ("equipped:Daggers/Shields", True, "a list holds when any entry does"),
        ("noequipped:Daggers/Shields", False, "and its negation fails when any entry does"),
        ("equipped: Shields ", True, "spaces around the type"),
        ("equipped:shields", True, "lowercase works, as it does in a macro"),
        ("noequipped:shields", False, "for the negation too"),
        ("equipped:SHIELDS", True, "any case"),
        ("equipped:no such type", True, "an unrecognized type proves nothing"),
        ("noequipped:no such type", True, "either way"),
    ):
        assert found(f"/cast [{condition}] X") is expected, (condition, why)
    assert found("/cast [equipped:Shields] X; Y") and not found("/cast [equipped:Shields] Y; [noequipped:Shields] X"), \
        "only the branch the worn gear selects holds the key"
    assert found("/CAST [Equipped:Shields] x"), "the command, the condition's name and the spell are case-free"
    assert found("/castsequence RESET=target X, Y", "Y") and found("/castsequence Reset=5 X, Y"), "so is reset="
    lua.execute('C_Item.IsEquippedItemType = function() error("unreadable") end')
    assert found("/cast [equipped:Shields] X") and found("/cast [noequipped:Shields] X"), "an unreadable answer blocks nothing"
    print("Macro parser: commands, branches, modifier fallback, combat, stealth, known and equipped read as the client does")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
