-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Offensive - Offensive queue settings tab + blacklist management
local Offensive = LibStub:NewLibrary("JustAC-OptionsOffensive", 3)
if not Offensive then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- displayMode == "disabled" turns off every surface; content toggles gate on it.
-- Resolved per call, not at load: Options/Core.lua loads after this file.
local function fullyDisabled(addon)
    return LibStub("JustAC-Options", true).IsFullyDisabled(addon)
end

-- Offensive queue CONTENT (what abilities the rotation surfaces). Cross-surface (affects the
-- standard queue and the nameplate overlay alike), so it lives with the other offensive
-- content tools here rather than a per-surface display panel. Moved out of the General tab.
-- Rendered as an inline group at the TOP of the Offensive "General" sub-tab, above the
-- custom-priority (Custom Queue) controls it now shares that tab with.
local function queueContentGroup(addon)
    return {
        type = "group",
        inline = true,
        name = L["Queue Content"],
        order = 0.1,
        args = {
            includeHiddenAbilities = W.toggle(addon, "includeHiddenAbilities", {
                name = L["Include All Available Abilities"], desc = L["Include All Available Abilities desc"],
                order = 1, width = "normal", default = true,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
            showSpellbookProcs = W.toggle(addon, "showSpellbookProcs", {
                name = L["Insert Procced Abilities"], desc = L["Insert Procced Abilities desc"],
                order = 2, width = "normal", default = true,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
            hideItemAbilities = {
                type = "toggle",
                name = L["Allow Item Abilities"],
                desc = L["Allow Item Abilities desc"],
                order = 3,
                width = "normal",
                -- Inverted (toggle shows "Allow", stores "hide") - stays raw.
                get = function() return not addon.db.profile.hideItemAbilities end,
                set = function(_, val)
                    addon.db.profile.hideItemAbilities = not val
                    addon:ForceUpdate()
                end,
                disabled = function() return fullyDisabled(addon) end,
            },
            showDotSpreadArrow = W.toggle(addon, "showDotSpreadArrow", {
                name = "Switch-Target Arrow",
                desc = "Show an arrow on the first icon when Assisted Combat keeps recommending a damage-over-time ability that is already active on your target - a cue to apply it to another enemy.",
                order = 4, width = "normal", default = false,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
            burstCueGlow = W.toggle(addon, "burstCueGlow", {
                name = L["Burst Ready Cue"], desc = L["Burst Ready Cue desc"],
                order = 5, width = "normal", default = false,
                onSet = function() addon:ForceUpdate() end,
                disabled = fullyDisabled,
            }),
        },
    }
end

-- Burst-ready cue triggers. Cross-surface queue content, so it lives with the
-- other content tools on the General sub-tab. The effective list resolves at
-- runtime: user override -> SimC sync anchors (generated) -> curated class
-- defaults; this panel shows the effective list and edits the override tier.
local function burstTriggerGroup(addon)
    return {
        type = "group",
        inline = true,
        name = L["Burst Triggers"],
        order = 0.2,
        args = {
            info = {
                type = "description",
                name = L["Burst Triggers desc"],
                order = 1,
                fontSize = "small",
            },
            active = {
                type = "description",
                name = function()
                    local SpellQueueLib = LibStub("JustAC-SpellQueue", true)
                    local list, source
                    if SpellQueueLib and SpellQueueLib.GetBurstTriggerInfo then
                        list, source = SpellQueueLib.GetBurstTriggerInfo()
                    end
                    local srcLabel = L["Burst Source " .. (source or "curated")]
                    if not list or #list == 0 then
                        return string.format(L["Burst Triggers Active"], srcLabel) .. " -"
                    end
                    local names = {}
                    for _, id in ipairs(list) do
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                        names[#names + 1] = info and info.name or ("#" .. id)
                    end
                    return string.format(L["Burst Triggers Active"], srcLabel)
                        .. " " .. table.concat(names, ", ")
                end,
                order = 2,
                fontSize = "medium",
            },
            clearTriggers = {
                type = "execute",
                name = L["Clear Burst Triggers"],
                desc = L["Clear Burst Triggers desc"],
                order = 40,
                width = "normal",
                disabled = function()
                    local profile = addon:GetProfile()
                    local SpellDB = LibStub("JustAC-SpellDB", true)
                    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
                    local t = profile and specKey and profile.burstTriggers
                        and profile.burstTriggers[specKey]
                    return not (t and #t > 0)
                end,
                func = function()
                    local profile = addon:GetProfile()
                    local SpellDB = LibStub("JustAC-SpellDB", true)
                    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
                    if profile and specKey and profile.burstTriggers then
                        profile.burstTriggers[specKey] = nil
                    end
                    local SpellQueueLib = LibStub("JustAC-SpellQueue", true)
                    if SpellQueueLib and SpellQueueLib.InvalidateBurstTriggers then
                        SpellQueueLib.InvalidateBurstTriggers()
                    end
                    Offensive.UpdateBurstTriggerOptions(addon)
                    addon:ForceUpdate()
                end,
            },
            -- Dynamic override entries added by UpdateBurstTriggerOptions
        },
    }
end

function Offensive.CreateTabArgs(addon)
    local CustomQueue = LibStub("JustAC-OptionsCustomQueue", true)
    local GapClosers = LibStub("JustAC-OptionsGapClosers", true)

    -- "General" sub-tab = the queue-content toggles + the custom-priority (Custom Queue)
    -- controls, merged into one panel (matching the General sub-tab every other top tab
    -- leads with). We reuse the Custom Queue tab as the base and inject the content group
    -- at the top; the arg KEY stays "customQueue" so UpdateCustomQueueOptions still resolves it.
    local generalTab = (CustomQueue and CustomQueue.CreateTabArgs) and CustomQueue.CreateTabArgs(addon)
    if generalTab then
        generalTab.name = L["General"]
        generalTab.order = 1
        generalTab.args.queueContentGroup = queueContentGroup(addon)
        generalTab.args.burstTriggerGroup = burstTriggerGroup(addon)
    else
        -- Fallback if the Custom Queue module is unavailable: still surface the toggles.
        generalTab = { type = "group", name = L["General"], order = 1,
                       args = { queueContentGroup = queueContentGroup(addon) } }
    end

    local tab = {
        type = "group",
        name = L["Offensive"],
        order = 4,
        childGroups = "tab",
        args = {
            -- Sub-tab 1: General (queue content + custom priority)
            customQueue = generalTab,
            -- Sub-tab 1: Gap-Closers
            gapClosers = (GapClosers and GapClosers.CreateTabArgs) and GapClosers.CreateTabArgs(addon) or nil,
            -- Sub-tab 2: Blacklist
            blacklist = {
                type = "group",
                name = L["Blacklist"],
                order = 2,
                args = {
                    info = {
                        type = "description",
                        name = L["Blacklist Info"],
                        order = 1,
                        fontSize = "medium"
                    },
                    warning = {
                        type = "description",
                        name = L["Blacklist Warning"],
                        order = 1.2,
                        fontSize = "small",
                    },
                    -- Dynamic blacklist entries added by UpdateBlacklistOptions
                },
            },
        },
    }
    return tab
end

-------------------------------------------------------------------------------
-- Dynamic burst-trigger override rebuild (mirrors the blacklist pattern)
-------------------------------------------------------------------------------
function Offensive.UpdateBurstTriggerOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end
    -- The General sub-tab keeps the arg key "customQueue" (see CreateTabArgs).
    local generalTab = optionsTable.args.offensive and optionsTable.args.offensive.args.customQueue
    local group = generalTab and generalTab.args.burstTriggerGroup
    if not group then return end
    local args = group.args

    local staticKeys = { info = true, active = true, clearTriggers = true }
    SpellSearch.ClearDynamicArgs(args, staticKeys)

    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return end
    local profile = addon:GetProfile()
    if not profile then return end
    if not profile.burstTriggers then profile.burstTriggers = {} end
    if not profile.burstTriggers[specKey] then profile.burstTriggers[specKey] = {} end
    local list = profile.burstTriggers[specKey]

    local updateFunc = function()
        local SpellQueueLib = LibStub("JustAC-SpellQueue", true)
        if SpellQueueLib and SpellQueueLib.InvalidateBurstTriggers then
            SpellQueueLib.InvalidateBurstTriggers()
        end
        Offensive.UpdateBurstTriggerOptions(addon)
        addon:ForceUpdate()
    end
    SpellSearch.RebuildListSection(addon, args, {
        spellList = list, listType = "bursttrigger",
        baseOrder = 10, addOrder = 30,
        listName = L["Burst Triggers"], updateFunc = updateFunc,
        spellsOnly = true, emptyText = L["Burst Triggers Empty"],
    })

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end

-------------------------------------------------------------------------------
-- Dynamic blacklist rebuild
-------------------------------------------------------------------------------
function Offensive.UpdateBlacklistOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local blacklistTab = optionsTable.args.offensive.args.blacklist
    if not blacklistTab then return end
    local blacklistArgs = blacklistTab.args

    -- Static keys to preserve (defined in CreateTabArgs)
    local staticKeys = {
        info = true,
        warning = true,
    }
    SpellSearch.ClearDynamicArgs(blacklistArgs, staticKeys)

    if not addon.db.profile.blacklistedSpells then
        addon.db.profile.blacklistedSpells = {}
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    if not specKey then return end
    if not addon.db.profile.blacklistedSpells[specKey] then
        addon.db.profile.blacklistedSpells[specKey] = {}
    end
    local blacklistedSpells = addon.db.profile.blacklistedSpells[specKey]

    SpellSearch.BuildSpellbookCache()

    blacklistArgs.addHeader = {
        type = "header",
        name = L["Add Spell to Blacklist"],
        order = 22,
    }
    blacklistArgs.addSpellButton = {
        type  = "execute",
        name  = L["Add"] .. " " .. L["Blacklist"] .. "...",
        desc  = L["Search spell desc"],
        order = 22.1,
        width = "normal",
        func  = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end

            -- Snapshot current blacklist as exclusion set
            local excludeList = {}
            for spellID, _ in pairs(blacklistedSpells) do
                excludeList[#excludeList + 1] = spellID
            end

            LiveSearchPopup.Open({
                title      = L["Add Spell to Blacklist"],
                searchFunc = SpellSearch.GetFilteredResults,
                excludeList = excludeList,
                onSelect   = function(id, _)
                    if not id or id == 0 then return end
                    if blacklistedSpells[id] then return end
                    local displayName
                    if id > 0 then
                        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                        if not spellInfo or not spellInfo.name then return end
                        displayName = spellInfo.name
                    else
                        local itemName = GetItemInfo(-id)
                        if not itemName then return end
                        displayName = itemName .. " |cff00ccff[Item]|r"
                    end
                    blacklistedSpells[id] = true
                    addon:Print("Blacklisted: " .. displayName)
                    addon:ForceUpdate()
                    Offensive.UpdateBlacklistOptions(addon)
                end,
            })
        end,
    }
    blacklistArgs.listHeader = {
        type = "header",
        name = SpellSearch.SpecHeader(L["Blacklist"]),
        order = 22.5,
    }

    -- Collect all blacklisted entries (spells: positive IDs, items: negative IDs)
    local entryList = {}
    for id, _ in pairs(blacklistedSpells) do
        if type(id) == "number" and id ~= 0 then
            local displayName, displayIcon
            if id > 0 then
                local info = BlizzardAPI and BlizzardAPI.GetSpellInfo(id) or (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id))
                displayName = info and info.name or ("Spell #" .. id)
                displayIcon = info and info.iconID or 134400
            else
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(-id)
                displayName = (itemName or ("Item #" .. (-id))) .. " |cff00ccff[Item]|r"
                displayIcon = itemTexture or 134400
            end
            entryList[#entryList + 1] = { id = id, name = displayName, icon = displayIcon }
        end
    end

    table.sort(entryList, function(a, b)
        return SpellSearch.StripColor(a.name) < SpellSearch.StripColor(b.name)
    end)

    if #entryList == 0 then
        blacklistArgs.noSpells = {
            type = "description",
            name = L["No spells currently blacklisted"],
            order = 23,
        }
    else
        blacklistArgs.clearAll = {
            type = "execute",
            name = L["Clear All"],
            desc = L["Clear All Blacklist desc"],
            order = 22.6,
            width = "half",
            confirm = true,
            func = function()
                wipe(blacklistedSpells)
                addon:ForceUpdate()
                Offensive.UpdateBlacklistOptions(addon)
            end,
        }
        for i, entry in ipairs(entryList) do
            local idKey = "bl_" .. tostring(entry.id)
            local idStr = entry.id > 0
                and ("|cff888888ID: " .. entry.id .. "|r")
                or  ("|cff888888item:" .. (-entry.id) .. "|r")

            local groupArgs = {
                entryInfo = {
                    type = "description",
                    name = idStr,
                    order = 1,
                    width = "double",
                },
                remove = {
                    type = "execute",
                    name = L["Remove"],
                    order = 3,
                    func = function()
                        blacklistedSpells[entry.id] = nil
                        addon:ForceUpdate()
                        Offensive.UpdateBlacklistOptions(addon)
                    end
                }
            }

            -- AC-slot scope toggle (spells only - items never appear in the AC slot).
            -- On (value == true): hidden everywhere. Off ({fixedQueue=true}): hidden from
            -- the queue only, so Blizzard's AC-slot recommendation can't stall.
            if entry.id > 0 then
                groupArgs.pos1 = {
                    type = "toggle",
                    name = L["Blacklist Position 1"],
                    desc = L["Blacklist Position 1 desc"],
                    order = 2,
                    get = function() return blacklistedSpells[entry.id] == true end,
                    set = function(_, val)
                        blacklistedSpells[entry.id] = val and true or { fixedQueue = true }
                        addon:ForceUpdate()
                    end,
                }
            end

            blacklistArgs[idKey] = {
                type = "group",
                name = "|T" .. entry.icon .. ":16:16:0:0|t " .. entry.name,
                inline = true,
                order = i + 23,
                args = groupArgs,
            }
        end
    end

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
