-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Forever - the WoW Forever section: what exists only there, in one place.
-- Settings shared with Retail stay with their peers on the other tabs (Mana Conservation,
-- recovery, threat cues); Retail-only settings stay where they are, greyed on Forever
-- (Options/Core.lua FOREVER_UNUSED).
local Forever = LibStub:NewLibrary("JustAC-OptionsForever", 1)
if not Forever then return end

local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

local fullyDisabled = W.fullyDisabled

local function NotForever()
    local SDB = LibStub("JustAC-SpellDB", true)
    return not (SDB and SDB.IsForever and SDB.IsForever())
end

--- What the Play Style rows show (RotationImport owns the rules); nil off Forever.
local function playStyles()
    local RI = LibStub("JustAC-RotationImport", true)
    if not (RI and RI.PlayStyleChoices) then return nil end
    return RI.PlayStyleChoices()
end

local function Format(key, ...)
    local ok, text = pcall(string.format, L[key], ...)
    if ok then return text end
    return L[key]
end

local REASONS = {
    chosen = "Play Style Reason Chosen",
    points = "Play Style Reason Points",
    default = "Play Style Reason Default",
}

--- Which tree's priority the queue follows now, and why.
local function Following()
    local s = playStyles()
    if not (s and s.following) then return "" end
    local name = s.following
    if s.bearForm then name = Format("Play Style Bear Form", name) end
    local reason
    if s.reason == "gear" and s.ruledOut then
        reason = Format("Play Style Reason Gear", s.ruledOut)
    elseif s.reason == "form" and s.ruledOut then
        reason = Format("Play Style Reason Form", s.ruledOut)
    else
        reason = L[REASONS[s.reason] or REASONS.points]
    end
    return Format("Play Style Following", name, reason)
end

--- WoW Forever: what the Cooldown Manager advisor would add, what the player hid, what it added.
local function CdmTrackStatus()
    local CA = LibStub("JustAC-CdmAdvisor", true)
    if not CA then return "" end
    local state, can, hidden, added = CA.Status()
    if state ~= "ok" and state ~= "nolayout" then return CA.StateText(state) end
    local names, lines = {}, {}
    for _, c in ipairs(can) do names[#names + 1] = c.name end
    lines[1] = #names > 0 and L["CDM can add"]:format(table.concat(names, ", ")) or L["CDM all tracked"]
    if #hidden > 0 then
        local h = {}
        for _, c in ipairs(hidden) do h[#h + 1] = c.name end
        lines[#lines + 1] = L["CDM player hid"]:format(table.concat(h, ", "))
    end
    if added > 0 then lines[#lines + 1] = L["CDM added count"]:format(added) end
    if state == "nolayout" and #names > 0 then lines[#lines + 1] = CA.StateText(state) end
    return table.concat(lines, "\n")
end

function Forever.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["WoW Forever"],
        desc = L["WoW Forever desc"],
        order = 1.5,
        hidden = NotForever,
        args = {
            info = {
                type = "description", order = 1, fontSize = "medium",
                name = L["WoW Forever desc"],
            },
            playStyleGroup = {
                type = "group", inline = true, order = 2,
                name = L["Play Style"],
                args = {
                    -- Which talent tree's priority to follow. Automatic reads talent points and
                    -- worn gear (RotationImport.PickTree); this is for what those cannot show.
                    -- Stored per class key, so one profile serves several characters.
                    playStyle = {
                        type = "select",
                        name = L["Play Style"], desc = L["Play Style desc"],
                        order = 1, width = "normal",
                        values = function()
                            local s = playStyles()
                            local values = { auto = L["Play Style Automatic Plain"] }
                            for _, c in ipairs(s and s.choices or {}) do values[c.key] = c.name end
                            if s and s.automatic then values.auto = Format("Play Style Automatic", s.automatic) end
                            return values
                        end,
                        sorting = function()
                            local s = playStyles()
                            local order = { "auto" }
                            for _, c in ipairs(s and s.choices or {}) do order[#order + 1] = c.key end
                            return order
                        end,
                        get = function()
                            local s = playStyles()
                            return s and s.chosen or "auto"
                        end,
                        set = function(_, val)
                            local s = playStyles()
                            if not (s and s.specKey) then return end
                            local profile = addon.db.profile
                            profile.playStyle = profile.playStyle or {}
                            if val == "auto" then
                                profile.playStyle[s.specKey] = nil
                            else
                                profile.playStyle[s.specKey] = val
                            end
                            -- The same refresh a talent change gets: another list, other costs and cues.
                            local SQ = LibStub("JustAC-SpellQueue", true)
                            if SQ and SQ.OnSpellsChanged then SQ.OnSpellsChanged() end
                            addon:ForceUpdateAll()
                        end,
                        disabled = function() return fullyDisabled(addon) end,
                    },
                    following = {
                        type = "description", order = 2, fontSize = "medium",
                        name = Following,
                    },
                },
            },
            -- Add the rotation's buffs and DoTs to the player's Cooldown Manager, as a guest in
            -- their layout (CdmAdvisor has the rules). Raw entries: their callbacks close over
            -- `addon`.
            cdmTrackGroup = {
                type = "group", inline = true, order = 3,
                name = L["Track Rotation Auras"],
                args = {
                    cdmTrackDesc = {
                        type = "description", order = 1, fontSize = "small",
                        name = L["Track Rotation Auras desc"],
                    },
                    cdmTrackStatus = {
                        type = "description", order = 2,
                        name = CdmTrackStatus,
                    },
                    cdmTrackAdd = {
                        type = "execute", order = 3, width = "normal",
                        name = L["CDM track"],
                        func = function()
                            local CA = LibStub("JustAC-CdmAdvisor", true)
                            local n, why = CA.Add()
                            if n > 0 then CA.OfferReload(L["CDM reload text"]:format(n))
                            elseif why then addon:Print(why) end
                            W.NotifyChange()
                        end,
                        disabled = function()
                            local CA = LibStub("JustAC-CdmAdvisor", true)
                            if not CA then return true end
                            local state, can = CA.Status()
                            return (state ~= "ok" and state ~= "nolayout") or #can == 0
                        end,
                    },
                    cdmTrackRemove = {
                        type = "execute", order = 4, width = "normal",
                        name = L["CDM remove"], desc = L["CDM remove desc"],
                        func = function()
                            local CA = LibStub("JustAC-CdmAdvisor", true)
                            local n, why = CA.RemoveAdded()
                            if n > 0 then CA.OfferReload(L["CDM removed"]:format(n))
                            elseif why then addon:Print(why) end
                            W.NotifyChange()
                        end,
                        disabled = function()
                            local CA = LibStub("JustAC-CdmAdvisor", true)
                            if not CA then return true end
                            local state, _, _, added = CA.Status()
                            return state ~= "ok" or added == 0
                        end,
                    },
                },
            },
        },
    }
end
