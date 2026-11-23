# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
"""Shared WoW API stubs for the offline tests.

LuaRuntime is lupa's runtime with C_SpellBook answered from the plain functions a test defines for
what the character knows: IsPlayerSpell(id), IsSpellKnown(id, isPet) and
IsSpellKnownOrOverridesKnown(id, isPet). Those are read at call time, so a test may define or
replace them at any point. What a test sets on C_SpellBook itself is kept.
"""
from lupa import LuaRuntime as _LuaRuntime  # type: ignore[import-not-found]

_BOOK = """
do
    local function read(id, isPet, ...)
        for i = 1, select("#", ...) do
            local fn = rawget(_G, (select(i, ...)))
            if type(fn) == "function" then return fn(id, isPet) end
        end
        return false
    end
    local book = rawget(_G, "C_SpellBook")
    if type(book) ~= "table" or getmetatable(book) then book = {} end
    book.IsSpellKnown = book.IsSpellKnown or function(id)
        return read(id, nil, "IsPlayerSpell", "IsSpellKnown")
    end
    book.IsSpellInSpellBook = book.IsSpellInSpellBook or function(id, bank, includeOverrides)
        local isPet = bank == 1
        if includeOverrides then
            return read(id, isPet, "IsSpellKnownOrOverridesKnown", "IsSpellKnown", "IsPlayerSpell")
        end
        return read(id, isPet, "IsSpellKnown", "IsPlayerSpell")
    end
    book.FindBaseSpellByID = book.FindBaseSpellByID or function(id) return id end
    rawset(_G, "C_SpellBook", book)
end
"""

_ENUM = """
do
    local enum = rawget(_G, "Enum")
    if type(enum) ~= "table" or getmetatable(enum) then enum = {} end
    enum.SpellBookSpellBank = enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
    rawset(_G, "Enum", enum)
end
"""


def with_spellbook(runtime_class):
    """A runtime class that keeps the C_SpellBook stubs in place around every execute."""

    class Runtime:
        def __init__(self, *args, **kwargs):
            self._lua = runtime_class(*args, **kwargs)

        def execute(self, code, *args):
            self._lua.execute(_BOOK + _ENUM)
            result = self._lua.execute(code, *args)
            self._lua.execute(_BOOK + _ENUM)
            return result

        def __getattr__(self, name):
            return getattr(self._lua, name)

    return Runtime


LuaRuntime = with_spellbook(_LuaRuntime)
