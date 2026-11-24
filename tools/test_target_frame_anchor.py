# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# TargetFrameAnchor: docks the queue to Blizzard's TargetFrame, or, when a unit-frame addon has
# replaced it, to that addon's target frame (Shadowed Unit Frames: SUFUnittarget). Falls back to
# the saved position when there is nothing visible to dock to, and never moves in combat.
from pathlib import Path

from lupa import LuaRuntime  # type: ignore[import-not-found]

ROOT = Path(__file__).resolve().parent.parent


def load():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "Libs" / "LibStub" / "LibStub.lua").read_text(encoding="utf-8"))
    lua.execute("""
        combat = false
        function InCombatLockdown() return combat end
        targetExists = true
        function UnitExists(unit) return targetExists end
        function GetScreenWidth() return 1920 end
        function GetScreenHeight() return 1080 end
        UIParent = {name = "UIParent", GetEffectiveScale = function() return 1 end}

        function NewFrame(name, opts)
            opts = opts or {}
            local f = {name = name, shown = opts.shown ~= false, visible = opts.visible ~= false,
                       events = opts.events or {}, point = opts.point ~= false,
                       forbidden = opts.forbidden == true, buffsOnTop = opts.buffsOnTop}
            function f:IsShown() return self.shown end
            function f:IsVisible() return self.shown and self.visible end
            function f:GetPoint() if self.point then return "CENTER" end end
            function f:IsForbidden() return self.forbidden end
            function f:IsEventRegistered(e) return self.events[e] == true end
            return f
        end

        mainFrame = {points = {}}
        function mainFrame:ClearAllPoints() self.points = {} end
        function mainFrame:SetPoint(point, rel, relPoint, x, y)
            self.points[#self.points + 1] = {point = point, rel = rel, relPoint = relPoint, x = x, y = y}
        end
        profile = {targetFrameAnchor = "TOP", queueOrientation = "LEFT",
                   framePosition = {point = "CENTER", relativePoint = "CENTER", x = 10, y = 20}}
        addon = {mainFrame = mainFrame, targetframe_anchored = false}
        function addon:GetProfile() return profile end
        function addon:DebugPrint() end
    """)
    lua.execute((ROOT / "TargetFrameAnchor.lua").read_text(encoding="utf-8"))
    lua.execute("TFA = LibStub('JustAC-TargetFrameAnchor')")
    return lua


def docked_to(lua):
    return lua.eval("mainFrame.points[1] and mainFrame.points[1].rel and mainFrame.points[1].rel.name")


def update(lua):
    lua.execute("TFA.InvalidateCache(); TFA.UpdateTargetFrameAnchor(addon)")


def test_standard_frame():
    lua = load()
    lua.execute("TargetFrame = NewFrame('TargetFrame', {events = {UNIT_NAME_UPDATE = true}})")
    lua.execute("SUFUnittarget = NewFrame('SUFUnittarget')")
    update(lua)
    assert docked_to(lua) == "TargetFrame", "Blizzard's frame wins while it is active"
    assert lua.eval("addon.targetframe_anchored") is True
    # Buffs on top: docking on top would cover them, so the saved position is kept.
    lua.execute("TargetFrame.buffsOnTop = true")
    update(lua)
    assert docked_to(lua) == "UIParent"
    assert lua.eval("addon.targetframe_anchored") is False


def test_shadowed_unit_frames_replacement():
    lua = load()
    # SUF strips the stock frame's events and parks it under a hidden parent.
    lua.execute("TargetFrame = NewFrame('TargetFrame', {visible = false, events = {UNIT_AURA = true}})")
    lua.execute("SUFUnittarget = NewFrame('SUFUnittarget')")
    update(lua)
    assert docked_to(lua) == "SUFUnittarget"
    assert lua.eval("mainFrame.points[1].point") == "BOTTOM" and lua.eval("mainFrame.points[1].relPoint") == "TOP"
    assert lua.eval("TFA.GetAnchorFrame(addon) == SUFUnittarget") is True
    assert lua.eval("select(2, TFA.GetAnchorFrame(addon))") is False
    # The stock frame's Edit Mode setting says nothing about where SUF puts its auras.
    lua.execute("TargetFrame.buffsOnTop = true")
    update(lua)
    assert docked_to(lua) == "SUFUnittarget"
    # Every side docks to the replacement.
    for side, point, rel_point in (("BOTTOM", "TOP", "BOTTOM"), ("LEFT", "RIGHT", "LEFT"), ("RIGHT", "LEFT", "RIGHT")):
        lua.execute("profile.targetFrameAnchor = '%s'" % side)
        update(lua)
        assert docked_to(lua) == "SUFUnittarget", side
        assert lua.eval("mainFrame.points[1].point") == point and lua.eval("mainFrame.points[1].relPoint") == rel_point


def test_replacement_visibility():
    lua = load()
    lua.execute("TargetFrame = NewFrame('TargetFrame', {visible = false})")
    # No target: SUF's unit watch hides its frame; the dock is kept so the queue stays put.
    lua.execute("SUFUnittarget = NewFrame('SUFUnittarget', {shown = false}); targetExists = false")
    update(lua)
    assert docked_to(lua) == "SUFUnittarget"
    # A target is up but the frame stays hidden (its target unit switched off): saved position.
    lua.execute("targetExists = true")
    update(lua)
    assert docked_to(lua) == "UIParent"
    assert lua.eval("mainFrame.points[1].x") == 10 and lua.eval("mainFrame.points[1].y") == 20


def test_nothing_to_dock_to():
    lua = load()
    lua.execute("TargetFrame = NewFrame('TargetFrame', {visible = false})")
    update(lua)
    assert lua.eval("(TFA.GetAnchorFrame(addon))") is None
    assert lua.eval("#mainFrame.points") == 0, "never docked: nothing to restore"
    # Unpositioned or forbidden replacements are not docked to.
    for opts in ("{point = false}", "{forbidden = true}"):
        lua.execute("SUFUnittarget = NewFrame('SUFUnittarget', %s); addon.targetframe_anchored = true" % opts)
        update(lua)
        assert docked_to(lua) == "UIParent", opts
        assert lua.eval("addon.targetframe_anchored") is False


def test_never_moves_in_combat():
    lua = load()
    lua.execute("TargetFrame = NewFrame('TargetFrame', {visible = false})")
    lua.execute("SUFUnittarget = NewFrame('SUFUnittarget'); combat = true")
    update(lua)
    assert lua.eval("#mainFrame.points") == 0


def main():
    for test in (test_standard_frame, test_shadowed_unit_frames_replacement, test_replacement_visibility,
                 test_nothing_to_dock_to, test_never_moves_in_combat):
        test()
    print("target frame anchor: Blizzard's frame first, Shadowed Unit Frames' replacement, "
          "visibility, fallbacks and combat passed")


if __name__ == "__main__":
    main()
