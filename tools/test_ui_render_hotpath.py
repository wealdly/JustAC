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


def main() -> None:
    test_range_hotkey()
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
