# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""The WoW Forever options section, outside the game: shown only on Forever, and its Play Style
rows read and write what RotationImport reports, including which tree is followed and why.

Run: python tools/test_forever_section.py
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        libs = {}
        local L = setmetatable({}, {__index = function(_, k) return k end})
        L["Play Style Following"] = "Following: %s, %s."
        L["Play Style Automatic"] = "Automatic (%s)"
        L["Play Style Reason Gear"] = "%s needs gear"
        L["Play Style Bear Form"] = "%s in Bear Form"
        LibStub = setmetatable({NewLibrary = function(_, name)
            libs[name] = {}; return libs[name]
        end}, {__call = function(_, name) return libs[name] end})
        libs['AceLocale-3.0'] = {GetLocale = function() return L end}
        libs['JustAC-Options'] = {IsFullyDisabled = function() return false end}
        forever, refreshed, updated = true, 0, 0
        libs['JustAC-SpellDB'] = {IsForever = function() return forever end}
        libs['JustAC-SpellQueue'] = {OnSpellsChanged = function() refreshed = refreshed + 1 end}
        status = nil
        libs['JustAC-RotationImport'] = {PlayStyleChoices = function() return status end}
        addon = {db = {profile = {}}, ForceUpdateAll = function() updated = updated + 1 end}
    """)
    for name in ("Widgets.lua", "Forever.lua"):
        lua.execute((ROOT / "Options" / name).read_text(encoding="utf-8"))
    tab = lua.eval("libs['JustAC-OptionsForever'].CreateTabArgs(addon)")
    g = lua.globals()

    assert tab.hidden() is False, "shown on Forever"
    g.forever = False
    assert tab.hidden() is True, "hidden on Retail"
    g.forever = True

    rows = tab.args.playStyleGroup.args
    style, following = rows.playStyle, rows.following
    # Off Forever data (nil): nothing to show, nothing written.
    assert following.name() == "" and style.get() == "auto"
    style.set(None, "fury")
    assert lua.eval("addon.db.profile.playStyle == nil and refreshed == 0")

    lua.execute("""status = {choices = {{key='arms', name='Arms'}, {key='fury', name='Fury'}}, specKey='WARRIOR_F',
        chosen=nil, automatic='Arms', following='Arms', reason='points'}""")
    values = style["values"]()   # by key: `.values` is lupa's own table method
    assert values.auto == "Automatic (Arms)" and values.fury == "Fury", dict(values)
    assert list(style.sorting().values()) == ["auto", "arms", "fury"]
    assert following.name() == "Following: Arms, Play Style Reason Points.", following.name()
    style.set(None, "fury")
    assert lua.eval("addon.db.profile.playStyle.WARRIOR_F == 'fury' and refreshed == 1 and updated == 1")
    style.set(None, "auto")
    assert lua.eval("addon.db.profile.playStyle.WARRIOR_F == nil")

    for reason, ruled_out, bear, want in (
            ("chosen", "nil", "false", "Following: Arms, Play Style Reason Chosen."),
            ("gear", "'Protection'", "false", "Following: Arms, Protection needs gear."),
            ("default", "nil", "false", "Following: Arms, Play Style Reason Default."),
            ("points", "nil", "true", "Following: Arms in Bear Form, Play Style Reason Points.")):
        lua.execute("status.reason, status.ruledOut, status.bearForm = '%s', %s, %s" % (reason, ruled_out, bear))
        assert following.name() == want, (reason, following.name())

    cdm = tab.args.cdmTrackGroup.args
    assert cdm.cdmTrackAdd and cdm.cdmTrackRemove and cdm.cdmTrackStatus, "aura tracking lives here now"
    general = (ROOT / "Options" / "General.lua").read_text(encoding="utf-8")
    offensive = (ROOT / "Options" / "Offensive.lua").read_text(encoding="utf-8")
    assert "cdmTrackAdd" not in general and "playStyle" not in offensive, "and nowhere else"
    print("forever section: shown on Forever only, Play Style reads and writes, following and why, aura tracking moved")


if __name__ == "__main__":
    main()
