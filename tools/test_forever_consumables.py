# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# WoW Forever consumables (Data/ForeverConsumables.lua, tools/gen_forever_consumables.py)
# through the real SpellDB.lua, on BOTH clients: Forever's recovery picks (best drink / food /
# bandage the player owns and can use, plain food before Well Fed food), the class-aware Auto
# pick for buffs, and that each client loads only its own consumable lists.
#
# Run: python tools/test_forever_consumables.py
import sys
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent

PRELUDE = """
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
owned, usable = {}, {}
C_Item = {
    GetItemCount = function(id) return owned[id] or 0 end,
    IsUsableItem = function(id) return usable[id] ~= false end,
    GetItemInfo = function() return nil end,
}
C_Spell = {}
C_SpecializationInfo = { GetSpecialization = function() return 1 end }
playerClass = "WARRIOR"
function UnitClass() return playerClass, playerClass end
GetTime = function() return 0 end
"""


ENGINE_STUBS = """
local libs = {}
LibStub = setmetatable({ NewLibrary = function(_, n) libs[n] = libs[n] or {}; return libs[n] end },
    { __call = function(_, n) return libs[n] end })
local S, B = LibStub:NewLibrary("JustAC-SpellDB"), LibStub:NewLibrary("JustAC-BlizzardAPI")
S.IsForever = function() return true end
recov = { food = 117, drink = 159, bandage = 1251 }
S.GetBestRecoveryItem = function(k) return recov[k] end
eating = nil
S.GetActiveEatingAura = function() return eating end
hpLow, mpLow = false, false
B.IsUnitHealthBelow = function() return hpLow end
B.IsUnitPowerBelow = function() return mpLow end
Enum = { PowerType = { Mana = 0 } }
cls = "MAGE"
function UnitClass() return cls, cls end
combat = false
function InCombatLockdown() return combat end
function IsMounted() return false end
function UnitIsDeadOrGhost() return false end
bandaged = nil
C_UnitAuras = { GetPlayerAuraBySpellID = function() return bandaged end }
function GetTime() return 0 end
function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:RegisterUnitEvent() end
    function f:SetScript() end
    return f
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
"""


def load(forever):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    if forever:
        lua.execute("WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = 18")
    for f in ("SpellDB.lua", "Data/HealingItems.lua", "Data/PrecombatBuffs.lua", "Data/ForeverConsumables.lua"):
        lua.execute((ROOT / f).read_text(encoding="utf-8"))
    return lua, lua.eval('LibStub("JustAC-SpellDB")')


def main():
    bad = []

    def check(ok, why):
        if not ok:
            bad.append(why)

    lua, sdb = load(True)
    own = lambda ids: lua.execute("owned = {" + ",".join(f"[{i}]=1" for i in ids) + "}")

    own([159, 5350])          # Refreshing Spring Water (756), Conjured Water (756)
    check(sdb.GetBestRecoveryItem("drink") in (159, 5350), "a drink the player carries")
    own([159, 231778])        # + Mountain Spring Water (25,500, level 55)
    lua.execute("usable = { [231778] = false }")
    check(sdb.GetBestRecoveryItem("drink") == 159, "too high level to use: the best usable one instead")
    lua.execute("usable = {}")
    check(sdb.GetBestRecoveryItem("drink") == 231778, "the most restored per drink wins")
    own([117, 13935])         # Tough Jerky (plain) + Baked Salmon (Well Fed, restores far more)
    check(sdb.GetBestRecoveryItem("food") == 117, "plain food before Well Fed food (keep that for the buff)")
    own([13935])
    check(sdb.GetBestRecoveryItem("food") == 13935, "Well Fed food when it is all there is")
    own([1251])               # Linen Bandage
    check(sdb.GetBestRecoveryItem("bandage") == 1251 and sdb.GetBestRecoveryItem("food") is None,
          "bandages ranked separately; no food carried")

    own([3383, 2454])         # Elixir of Wisdom (intellect) + Elixir of Minor Strength
    best = sdb.GetBestOwnedBuff("flask")
    check(best is not None and best.id == 2454, "warrior Auto: strength, never Elixir of Wisdom")
    lua.execute('playerClass = "MAGE"')
    best = sdb.GetBestOwnedBuff("flask")
    check(best is not None and best.id == 3383, "mage Auto: intellect")
    check(sdb.GetPrecombatBuffItems("augmentRune") is None, "Forever: retail's lists are not loaded")
    check(sdb.GetPrecombatBuffItems("scroll") is not None, "Forever: scrolls registered")

    rlua, r = load(False)
    check(r.GetBestRecoveryItem("food") is None, "retail: no recovery items")
    check(r.GetPrecombatBuffItems("scroll") is None, "retail: no Forever scroll category")
    check(r.GetPrecombatBuffItems("flask") is not None and r.GetPrecombatBuffItems("augmentRune") is not None,
          "retail: its own consumable lists are loaded")

    # The recovery offer itself (PrecombatEngine.AddRecoveryItems), against a stubbed client.
    pe = LuaRuntime(unpack_returned_tuples=True)
    pe.execute(ENGINE_STUBS)
    pe.execute((ROOT / "PrecombatEngine.lua").read_text(encoding="utf-8"))
    offer = lambda: list(pe.eval("(function() local o = {} LibStub('JustAC-PrecombatEngine').AddRecoveryItems(o) return o end)()").values())
    pe.execute("hpLow, mpLow = true, true")
    check(offer() == [159, 117], "mage low on both: drink and food together")
    pe.execute('cls = "WARRIOR"')
    check(offer() == [117], "warrior: no mana bar, never a drink")
    pe.execute("recov.food = nil")
    check(offer() == [1251], "no food carried: a bandage")
    pe.execute("bandaged = { spellId = 11196 }")
    check(offer() == [], "Recently Bandaged: nothing")
    pe.execute("bandaged = nil; recov.food = 117; eating = { spellId = 433 }")
    check(offer() == [], "already eating: nothing")
    pe.execute("eating = nil; combat = true")
    check(offer() == [], "in combat: nothing")
    pe.execute("combat = false; hpLow, mpLow = false, false")
    check(offer() == [], "healthy: nothing")

    for why in bad:
        print("  FAIL", why)
    print("forever consumables: %d failure(s)" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
