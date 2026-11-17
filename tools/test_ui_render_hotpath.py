# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Same-queue defensive overlay refresh reuses static icon metadata but keeps live visuals current.
#
# Run: python tools/test_ui_render_hotpath.py

from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "UI" / "UIRenderer.lua"


PRELUDE = """
UIRenderer = {}
calls = { spellInfo = 0, itemIcon = 0, itemInfo = 0, visual = 0, proc = 0, dirty = 0 }
COOLDOWN_UPDATE_INTERVAL = 5
isInCombat = false
function GetTime() return 100 end
function MoveCastDotEnabled() return false end
function ApplyCueDot() end
function UpdateButtonCooldowns() end
function ShowHotkeys() return false end
function SetIconHotkey() end
function GetItemSpell() return nil end
function ComputeDefensiveGlowState() return "none" end
function ApplyDefensiveGlow() end
function SetDefensiveIconVisible() end
function UpdateVisual(icon) calls.visual = calls.visual + 1 end
function MarkDirty() calls.dirty = calls.dirty + 1 end
BlizzardAPI = {
    GetCachedSpellInfo = function(id)
        calls.spellInfo = calls.spellInfo + 1
        return { iconID = "spell:" .. id, castTime = 0 }
    end,
    IsSpellProcced = function()
        calls.proc = calls.proc + 1
        return false
    end,
}
C_Item = {
    GetItemIconByID = function(id)
        calls.itemIcon = calls.itemIcon + 1
        return "item:" .. id
    end,
    GetItemInfo = function(id)
        calls.itemInfo = calls.itemInfo + 1
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, "item:" .. id
    end,
}
"""


def extract_show_defensive_icon(source: str) -> str:
    start = source.index("function UIRenderer.ShowDefensiveIcon(")
    end = source.index("\n-- keepSlot:", start)
    return source[start:end]


def test_range_hotkey() -> None:
    source = SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n")
    indicator_start = source.index("local RANGE_INDICATOR =")
    indicator_end = source.index("\n", indicator_start)
    start = source.index("local function UpdateRangeHotkeyColor(")
    end = source.index("\nend", start) + len("\nend")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(source[indicator_start:indicator_end] + "\n" + source[start:end] +
                "\nTestUpdateRangeHotkeyColor = UpdateRangeHotkeyColor")
    lua.execute("""
        local text = {
            value = "",
            GetText = function(self) return self.value end,
            SetText = function(self, value) self.value = value end,
            SetTextColor = function(self, r, g, b, a) self.color = {r, g, b, a} end,
        }
        local icon = {hotkeyText = text, hotkeyShown = true, cachedHotkey = ""}
        local color = {r=0.2, g=0.3, b=0.4, a=0.5}
        TestUpdateRangeHotkeyColor(icon, true, color)
        assert(text.value == ".", "unbound range indicator must use a font-safe dot")
        assert(text.color[1] == 1 and text.color[2] == 0, "indicator should be red")
        TestUpdateRangeHotkeyColor(icon, false, color)
        assert(text.value == "" and text.color[1] == 0.2 and text.color[4] == 0.5,
            "returning to range should clear the indicator and restore color")

        icon.cachedHotkey, text.value = ".", "."
        TestUpdateRangeHotkeyColor(icon, true, color)
        TestUpdateRangeHotkeyColor(icon, false, color)
        assert(text.value == ".", "a period keybind must not be mistaken for the indicator")
        icon.cachedHotkey, text.value = "1", "1"
        TestUpdateRangeHotkeyColor(icon, true, color)
        assert(text.value == "1" and text.color[1] == 1 and text.color[2] == 0,
            "bound key must remain visible and turn red")
        TestUpdateRangeHotkeyColor(icon, false, color)
        assert(text.value == "1" and text.color[2] == 0.3,
            "bound key must retain its text and restore its configured color")
    """)


def test_attack_hotkey() -> None:
    source = SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n")
    start = source.index("--- Bar lookup for a spell or an item")
    end = source.index("\n-----", source.index("local function AttackHotkey("))
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        keys = {[6603]="A", [78]="2", [772]="3"}
        ActionBarScanner = { GetSpellHotkey=function(id) return keys[id] or "" end }
        SpellQueue = { GetAttackKeySpell=function() return carrier end }
    """ + source[start:end] + "\nTestAttackHotkey = AttackHotkey")
    lua.execute("""
        assert(TestAttackHotkey() == "A", "no carrier: Attack's own key")
        carrier = 772
        assert(TestAttackHotkey() == "3", "the queue's chosen carrier supplies the key")
        keys[772] = nil
        assert(TestAttackHotkey() == "A", "a carrier that lost its key falls back")
        SpellQueue = nil
        assert(TestAttackHotkey() == "A", "no queue module: Attack's own key")
    """)
    print("Attack hotkey: the queue's /startattack carrier, else Attack's own key")


def test_aura_clock_diagnostics() -> None:
    from test_forever_openers import aura_clock_source
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("GetTime = function() return 0 end\n" + aura_clock_source(ROOT))
    lua.execute("""
        local function icon(id, kind, src, shown)
            local b = {spellID=id, _auraClockKind=kind, _auraClockSource=src,
                       IsShown=function() return shown end}
            AuraClock._buttons[b] = true
            return b
        end
        assert(AuraClock.Debug() == "none", "nothing held")
        icon(6673, "buff", "engine-container", true)
        icon(589, "debuff", "estimate", true)
        icon(772, "debuff", nil, true)
        icon(78, "buff", "none", false)
        assert(AuraClock.Debug() == "589:debuff:estimate,6673:buff:engine-container", AuraClock.Debug())
    """)
    # /jac inspect's auraClock row reads the module directly.
    session = (ROOT / "Debug" / "Session.lua").read_text(encoding="utf-8")
    assert "return clock.Debug()" in session
    print("Aura clock diagnostics: shown held icons listed by spell, kind and source")


def test_hold_never_duplicates() -> None:
    source = SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n")
    start = source.index("local function ShownElsewhere(")
    end = source.index("\nend\n", start) + len("\nend\n")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(source[start:end] + "\nTestShownElsewhere = ShownElsewhere")
    lua.execute("""
        local q = {78, 772, 6603, 1715}
        assert(TestShownElsewhere(q, 4, 3, 2, 78), "moved to slot 1: holding it at 2 would duplicate")
        assert(not TestShownElsewhere(q, 4, 3, 1, 78), "its own slot does not count")
        assert(not TestShownElsewhere(q, 4, 3, 2, 1715), "queued past the visible icons: hold may keep it")
        assert(not TestShownElsewhere(q, 4, 3, 2, 999), "not queued at all")
        assert(TestShownElsewhere(q, 4, nil, 2, 1715), "unknown visible count reads the whole queue")
    """)
    print("Position hold: never keeps a spell the queue already shows in another visible slot")


def main() -> None:
    test_range_hotkey()
    test_hold_never_duplicates()
    test_aura_clock_diagnostics()
    test_attack_hotkey()
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    lua.execute(
        extract_show_defensive_icon(SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n"))
    )
    lua.execute("""
        UIRenderer.UpdateDefensiveVisualState = UpdateVisual
        UIRenderer.ResolveGlowMode = function() return "none" end
        local texture = {
            SetTexture = function(self, value) self.value = value end,
            Show = function() end,
            SetDesaturation = function() end,
            SetVertexColor = function() end,
        }
        addon = {
            db = { profile = {
                showFlash = false,
                showOffGcdDot = false,
                textOverlays = { hotkey = { show = false } },
                defensives = { glowMode = "none" },
            } },
            MarkDefensiveDirty = MarkDirty,
        }
        spellIcon = { iconTexture = texture }
        UIRenderer.ShowDefensiveIcon(addon, 101, false, spellIcon, false, nil, false, false)
        assert(calls.spellInfo == 1 and calls.visual == 1 and calls.proc == 1)
        UIRenderer.ShowDefensiveIcon(addon, 101, false, spellIcon, false, nil, false, false, true)
        assert(calls.spellInfo == 1, "same-id refresh repeated spell metadata lookup")
        assert(calls.visual == 2 and calls.proc == 2, "same-id refresh skipped live visual state")
        UIRenderer.ShowDefensiveIcon(addon, 102, false, spellIcon, false, nil, false, false, true)
        assert(calls.spellInfo == 2 and spellIcon.currentID == 102,
            "changed spell id did not resolve fresh metadata")
        incompleteIcon = { currentID = 101, isItem = false, iconTexture = texture }
        UIRenderer.ShowDefensiveIcon(addon, 101, false, incompleteIcon, false, nil, false, false, true)
        assert(calls.spellInfo == 3 and texture.value == "spell:101",
            "missing cached metadata did not refresh the icon texture")

        itemIcon = { iconTexture = texture }
        UIRenderer.ShowDefensiveIcon(addon, 501, true, itemIcon, false, nil, false, false)
        assert(calls.itemIcon == 1 and calls.itemInfo == 1)
        UIRenderer.ShowDefensiveIcon(addon, 501, true, itemIcon, false, nil, false, false, true)
        assert(calls.itemIcon == 1 and calls.itemInfo == 1,
            "same-id item refresh repeated static icon lookups")
        assert(calls.visual == 6 and calls.proc == 6,
            "item refresh skipped live visual state")
        assert(calls.dirty == 0, "metadata resolution unexpectedly failed")
    """)
    print("Defensive overlay refresh: static spell/item metadata is reused; live visual checks continue")


if __name__ == "__main__":
    main()
