-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/CustomQueue - Custom Queue tab for user-defined rotation ordering
local CustomQueue = LibStub:NewLibrary("JustAC-OptionsCustomQueue", 1)
if not CustomQueue then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local W = LibStub("JustAC-OptionsWidgets")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local ipairs = ipairs
local table_concat = table.concat

--- Resolve a spell ID to its base ID (handles talent overrides).
local function ResolveSpellID(id)
    return BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(id) or id
end

--- Identity of a rotation entry for diffing. The rotation list hands back
--- form-dependent variants of the same ability (Moonfire 8921 in caster form,
--- 155625 in cat), and override resolution does not collapse them - so keying on
--- the ID alone reads a shapeshift as one spell added plus one removed, forever.
--- Key on the name when we have it; fall back to the resolved ID.
local function RotationKey(id)
    local resolved = ResolveSpellID(id)
    return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(resolved)) or resolved
end

--- Invalidate SpellQueue's rotation cache so changes take effect immediately.
local function InvalidateRotationCache()
    local SpellQueueLib = LibStub("JustAC-SpellQueue", true)
    if SpellQueueLib and SpellQueueLib.InvalidateRotationCache then
        SpellQueueLib.InvalidateRotationCache()
    end
end

--- Return the spec key for the current player.
local function GetSpecKey()
    if SpellDB and SpellDB.GetSpecKey then
        return SpellDB.GetSpecKey()
    end
    return nil
end

--- Shared hidden check: true when custom queue is NOT enabled for current spec.
local function IsCustomQueueHidden(addon)
    local profile = addon:GetProfile()
    local specKey = GetSpecKey()
    return not (profile and profile.customQueue
        and specKey and profile.customQueue[specKey]
        and profile.customQueue[specKey].enabled)
end

--- Ordering presets over the three profile keys (orderProcsFirst / contextOrder /
--- orderSinkCooldowns). The preset is DERIVED, never stored - any other mix of
--- the three reads as "custom". No migration needed and DebugHUD/SpellQueue keep
--- reading the raw keys.
local ORDERING_PRESETS = {
    smart = { procs = true,  context = "simc", sink = true  },
    ac    = { procs = true,  context = "ac",   sink = true  },
    fixed = { procs = false, context = "off",  sink = false },
}

local function CurrentOrderingPreset(addon)
    local profile = addon:GetProfile()
    if not profile then return "smart" end
    local procs   = profile.orderProcsFirst ~= false
    local context = profile.contextOrder or "simc"
    local sink    = profile.orderSinkCooldowns ~= false
    for key, p in pairs(ORDERING_PRESETS) do
        if p.procs == procs and p.context == context and p.sink == sink then
            return key
        end
    end
    return "custom"
end

-- Write one preset's three keys (shared by the preset select and the Customize
-- snap-back). Returns true when applied.
local function ApplyOrderingPreset(addon, key)
    local p = ORDERING_PRESETS[key]
    if not p then return false end
    local profile = addon:GetProfile()
    if not profile then return false end
    profile.orderProcsFirst    = p.procs
    profile.contextOrder       = p.context
    profile.orderSinkCooldowns = p.sink
    addon:ForceUpdateAll()
    return true
end

-- Session-only: the player opened the individual ordering controls. A profile
-- already in a mixed state shows them regardless.
local orderingAdvanced = false

local function OrderingAdvancedShown(addon)
    return orderingAdvanced or CurrentOrderingPreset(addon) == "custom"
end

local function MakeOrderingPresetSelect(addon, order)
    return {
        type = "select",
        name = L["Ordering Preset"],
        desc = L["Ordering Preset desc"],
        order = order,
        width = "double",
        values = function()
            local v = {
                smart = L["Ordering Smart"],
                ac    = L["Ordering Match"],
                fixed = L["Ordering Fixed"],
            }
            -- "Custom" is a state reached through the individual controls below,
            -- not a preset to pick - listed only while it is the current state.
            if CurrentOrderingPreset(addon) == "custom" then
                v.custom = L["Ordering Custom"]
            end
            return v
        end,
        sorting = function()
            if CurrentOrderingPreset(addon) == "custom" then
                return { "smart", "ac", "fixed", "custom" }
            end
            return { "smart", "ac", "fixed" }
        end,
        get = function() return CurrentOrderingPreset(addon) end,
        set = function(_, val)
            if ApplyOrderingPreset(addon, val) then
                -- Refresh so the per-ability pin toggles re-evaluate their greyed state.
                if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
            end
        end,
    }
end

--- Build a master ordering toggle. `field` is a profile-level key; the toggle
--- applies universally - to positions 2+ of both the custom list and Blizzard's
--- default rotation. All three default to enabled (nil → true: smart order);
--- turning all three off renders positions 2+ in their exact source order.
local function MakeOrderingToggle(addon, field, name, desc, order)
    return {
        type = "toggle",
        name = name,
        desc = desc,
        order = order,
        width = "normal",
        get = function()
            local profile = addon:GetProfile()
            return not profile or profile[field] ~= false
        end,
        set = function(_, val)
            local profile = addon:GetProfile()
            if not profile then return end
            profile[field] = val
            addon:ForceUpdateAll()
            -- Refresh the panel so the per-ability Proc Priority toggles re-evaluate
            -- their greyed state against the new "Procs first" value.
            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
        end,
    }
end

--- The "Context ordering" select for positions 2+: Off / Match Blizzard's pick (the
--- context-aware heuristic) / SimC priority (imported theorycraft order). The SimC
--- tier only appears where we have data for the current spec.
local function MakeContextOrderSelect(addon, order)
    local function hasSimc()
        local RI = LibStub("JustAC-RotationImport", true)
        return RI and RI.HasRotation and RI.HasRotation()
    end
    return {
        type = "select",
        name = "Context ordering",
        desc = "How the abilities after the first are ordered.\n\n"
            .. "|cffffd100Off|r - source order.\n"
            .. "|cffffd100Match Blizzard's pick|r - reorder to match what Assisted "
            .. "Combat is recommending now (target pattern + builder/spender role).\n"
            .. "|cffffd100SimC priority|r - order by SimulationCraft's theorycraft "
            .. "priority for your spec and target count. The default where data "
            .. "exists for your spec.\n\n"
            .. "SimC priority is tuned for end-game; below max level use Match Blizzard's "
            .. "pick. (Orderings from SimulationCraft, GPL-3.0.)",
        order = order,
        width = "normal",
        values = function()
            local v = { off = "Off", ac = "Match Blizzard's pick" }
            if hasSimc() then v.simc = "SimC priority" end
            return v
        end,
        sorting = function()
            return hasSimc() and { "off", "ac", "simc" } or { "off", "ac" }
        end,
        get = function()
            local profile = addon:GetProfile()
            if not profile then return "ac" end
            local v = profile.contextOrder or "simc"
            -- No SimC data for this spec: the runtime falls back to the AC
            -- heuristic, and the dropdown has no "simc" entry - reflect that.
            if v == "simc" and not hasSimc() then v = "ac" end
            return v
        end,
        set = function(_, val)
            local profile = addon:GetProfile()
            if not profile then return end
            profile.contextOrder = val
            addon:ForceUpdateAll()
            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
        end,
    }
end

--- Copy the current Blizzard rotation into cq.baseline. Returns the rotation
--- list (never empty), or nil when unavailable.
local function snapshotBaseline(cq)
    if not BlizzardAPI or not BlizzardAPI.GetRotationSpells then return nil end
    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells then return nil end
    cq.baseline = {}
    for i, spellID in ipairs(rotationSpells) do
        cq.baseline[i] = spellID
    end
    return rotationSpells
end

--- Snapshot the current Blizzard rotation into the profile (baseline + spells).
--- Returns true if snapshot was taken, false if no rotation available.
local function SnapshotRotation(addon, specKey)
    local profile = addon and addon.db and addon.db.profile
    if not profile then return false end
    if not profile.customQueue then profile.customQueue = {} end
    if not profile.customQueue[specKey] then profile.customQueue[specKey] = {} end

    local cq = profile.customQueue[specKey]
    local rotationSpells = snapshotBaseline(cq)
    if not rotationSpells then return false end
    cq.spells = {}
    for i, spellID in ipairs(rotationSpells) do
        cq.spells[i] = spellID
    end

    return true
end

--- Compare current rotation against stored baseline.
--- Returns: added (array), removed (array), or nil,nil if no diff.
local function DiffRotation(addon, specKey)
    if not BlizzardAPI or not BlizzardAPI.GetRotationSpells then return nil, nil end

    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.customQueue or not profile.customQueue[specKey] then return nil, nil end
    local cq = profile.customQueue[specKey]
    if not cq.baseline then return nil, nil end

    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells then return nil, nil end

    -- Build sets for comparison, keyed so talent overrides and form variants of the
    -- same ability don't register as a change. Values stay spell IDs for the merge.
    local baselineSet = {}
    for _, sid in ipairs(cq.baseline) do
        if sid and sid > 0 then
            baselineSet[RotationKey(sid)] = sid
        end
    end
    local currentSet = {}
    for _, sid in ipairs(rotationSpells) do
        if sid and sid > 0 then
            currentSet[RotationKey(sid)] = sid
        end
    end

    local added = {}
    local removed = {}
    for key, sid in pairs(currentSet) do
        if not baselineSet[key] then
            added[#added + 1] = sid
        end
    end
    for key, sid in pairs(baselineSet) do
        if not currentSet[key] then
            removed[#removed + 1] = sid
        end
    end

    if #added == 0 and #removed == 0 then return nil, nil end
    return added, removed
end

--- Build a human-readable string for the stale warning banner.
local function BuildStaleWarning(added, removed)
    local parts = {}
    if added and #added > 0 then
        parts[#parts + 1] = #added .. " " .. (L["spells added"] or "spell(s) added")
    end
    if removed and #removed > 0 then
        parts[#parts + 1] = #removed .. " " .. (L["spells removed"] or "spell(s) removed")
    end
    if #parts == 0 then return nil end
    return "|cFFFFAA00" .. (L["Custom Queue Stale Warning"] or "Blizzard's rotation has changed") .. ": " .. table_concat(parts, ", ") .. ".|r"
end

function CustomQueue.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Custom Queue"],
        order = 1,
        args = {
            positionNote = {
                type = "description",
                name = L["Custom Queue Position Note"],
                order = 0.25,
                fontSize = "medium",
            },
            enableCustomQueue = {
                type = "toggle",
                name = L["Enable Custom Queue"],
                desc = L["Enable Custom Queue desc"],
                -- The tab's master switch reads first, right under the position
                -- note; the ordering group below applies to both queue sources,
                -- so it keeps working with the switch off.
                order = 0.4,
                width = "full",
                get = function()
                    local profile = addon:GetProfile()
                    local specKey = GetSpecKey()
                    return profile and profile.customQueue
                        and specKey and profile.customQueue[specKey]
                        and profile.customQueue[specKey].enabled == true
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    if not profile then return end
                    local specKey = GetSpecKey()
                    if not specKey then return end
                    if not profile.customQueue then profile.customQueue = {} end
                    if not profile.customQueue[specKey] then
                        profile.customQueue[specKey] = {}
                    end
                    profile.customQueue[specKey].enabled = val
                    -- Snapshot rotation on first enable if no spells yet
                    if val and (not profile.customQueue[specKey].spells
                                or #profile.customQueue[specKey].spells == 0) then
                        SnapshotRotation(addon, specKey)
                    end
                    -- Invalidate rotation cache so SpellQueue picks up the change
                    InvalidateRotationCache()
                    CustomQueue.UpdateCustomQueueOptions(addon)
                    addon:ForceUpdateAll()
                end,
            },
            myListLeads = {
                type = "toggle",
                name = L["My List Leads"] .. " |cffff7f00(" .. L["Experimental"] .. ")|r",
                desc = L["My List Leads desc"],
                order = 0.45,
                width = "full",
                disabled = function()
                    local profile = addon:GetProfile()
                    local specKey = GetSpecKey()
                    local cq = profile and specKey and profile.customQueue and profile.customQueue[specKey]
                    return not (cq and cq.enabled)
                end,
                get = function()
                    local profile = addon:GetProfile()
                    local specKey = GetSpecKey()
                    local cq = profile and specKey and profile.customQueue and profile.customQueue[specKey]
                    return (cq and cq.myListLeads == true) or false
                end,
                set = function(_, val)
                    local profile = addon:GetProfile()
                    local specKey = GetSpecKey()
                    if not profile or not specKey then return end
                    local cq = profile.customQueue and profile.customQueue[specKey]
                    if not cq then return end
                    cq.myListLeads = val or nil
                    addon:ForceUpdateAll()
                end,
            },
            ordering = {
                type = "group",
                inline = true,
                name = L["Custom Queue Ordering"],
                order = 0.5,
                args = (function()
                    local function advancedHidden()
                        return not OrderingAdvancedShown(addon)
                    end
                    local procsFirst    = MakeOrderingToggle(addon, "orderProcsFirst", L["Custom Queue Procs First"], L["Custom Queue Procs First desc"], 2)
                    local contextOrder  = MakeContextOrderSelect(addon, 3)
                    local sinkCooldowns = MakeOrderingToggle(addon, "orderSinkCooldowns", L["Custom Queue Sink Cooldowns"],
                        W.spellDesc("Custom Queue Sink Cooldowns desc", 163201), 4)  -- Execute
                    procsFirst.hidden, contextOrder.hidden, sinkCooldowns.hidden =
                        advancedHidden, advancedHidden, advancedHidden
                    return {
                        note = {
                            type = "description",
                            name = "|cFF999999" .. L["Custom Queue Ordering Note"] .. "|r",
                            order = 1,
                            fontSize = "small",
                        },
                        preset = MakeOrderingPresetSelect(addon, 1.2),
                        customize = {
                            type = "toggle",
                            name = L["Ordering Customize"],
                            desc = L["Ordering Customize desc"],
                            order = 1.4,
                            width = "normal",
                            get = function() return OrderingAdvancedShown(addon) end,
                            set = function(_, v)
                                orderingAdvanced = v
                                -- Collapsing out of a mixed state snaps back to Smart,
                                -- so the toggle never reads off while controls show.
                                if not v and CurrentOrderingPreset(addon) == "custom" then
                                    ApplyOrderingPreset(addon, "smart")
                                end
                                if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                            end,
                        },
                        procsFirst    = procsFirst,
                        contextOrder  = contextOrder,
                        sinkCooldowns = sinkCooldowns,
                    }
                end)(),
            },
            staleWarning = {
                type = "description",
                name = function()
                    local specKey = GetSpecKey()
                    if not specKey then return "" end
                    local added, removed = DiffRotation(addon, specKey)
                    if not added and not removed then return "" end
                    return BuildStaleWarning(added, removed) or ""
                end,
                order = 2.5,
                fontSize = "medium",
                hidden = function()
                    local profile = addon:GetProfile()
                    local specKey = GetSpecKey()
                    if not profile or not specKey then return true end
                    local cq = profile.customQueue and profile.customQueue[specKey]
                    if not cq or not cq.enabled or not cq.baseline then return true end
                    local added, removed = DiffRotation(addon, specKey)
                    return not added and not removed
                end,
            },
            mergeNewSpells = {
                type = "execute",
                name = L["Merge New Spells"],
                desc = L["Merge New Spells desc"],
                order = 2.7,
                width = "normal",
                hidden = function()
                    local profile = addon:GetProfile()
                    local specKey = GetSpecKey()
                    if not profile or not specKey then return true end
                    local cq = profile.customQueue and profile.customQueue[specKey]
                    if not cq or not cq.enabled or not cq.baseline then return true end
                    local added, removed = DiffRotation(addon, specKey)
                    return not added and not removed
                end,
                func = function()
                    local specKey = GetSpecKey()
                    if not specKey then return end
                    local profile = addon:GetProfile()
                    if not profile or not profile.customQueue or not profile.customQueue[specKey] then return end
                    local cq = profile.customQueue[specKey]
                    local added, removed = DiffRotation(addon, specKey)

                    -- Append added spells
                    if added then
                        if not cq.spells then cq.spells = {} end
                        for _, sid in ipairs(added) do
                            cq.spells[#cq.spells + 1] = sid
                        end
                    end

                    -- Remove spells that no longer exist in the rotation
                    if removed then
                        local removedSet = {}
                        for _, sid in ipairs(removed) do
                            removedSet[RotationKey(sid)] = true
                        end
                        if cq.spells then
                            local newSpells = {}
                            for _, sid in ipairs(cq.spells) do
                                if sid and sid > 0 and not removedSet[RotationKey(sid)] then
                                    newSpells[#newSpells + 1] = sid
                                end
                            end
                            cq.spells = newSpells
                        end
                    end

                    -- Update baseline to current rotation
                    snapshotBaseline(cq)

                    InvalidateRotationCache()
                    CustomQueue.UpdateCustomQueueOptions(addon)
                    addon:ForceUpdateAll()
                end,
            },
            -- SPELL LIST GROUP (10+)
            spellListGroup = {
                type = "group",
                inline = true,
                name = SpellSearch.SpecHeader(L["Custom Queue Spells"]),
                order = 10,
                hidden = function() return IsCustomQueueHidden(addon) end,
                args = {
                    spellListInfo = {
                        type = "description",
                        name = L["Custom Queue Spells desc"],
                        order = 11,
                        fontSize = "small",
                    },
                    -- Dynamic spell entries added by UpdateCustomQueueOptions
                },
            },
            -- RESET (990+)
            resetHeader = {
                type = "header",
                name = "",
                order = 990,
                hidden = function() return IsCustomQueueHidden(addon) end,
            },
            refreshFromRotation = {
                type = "execute",
                name = L["Refresh from Rotation"],
                desc = L["Refresh from Rotation desc"],
                order = 991,
                width = "normal",
                hidden = function() return IsCustomQueueHidden(addon) end,
                confirm = true,
                confirmText = L["Refresh from Rotation confirm"],
                func = function()
                    local specKey = GetSpecKey()
                    if not specKey then return end
                    SnapshotRotation(addon, specKey)
                    InvalidateRotationCache()
                    CustomQueue.UpdateCustomQueueOptions(addon)
                    addon:ForceUpdateAll()
                end,
            },
        },
    }
end

function CustomQueue.UpdateCustomQueueOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable then return end

    local offTab = optionsTable.args.offensive
    if not offTab then return end
    local cqTab = offTab.args.customQueue
    if not cqTab then return end

    -- Update spell list entries
    local spellListGroup = cqTab.args.spellListGroup
    if not spellListGroup then return end

    local spellListArgs = spellListGroup.args
    local staticKeys = { spellListInfo = true }
    SpellSearch.ClearDynamicArgs(spellListArgs, staticKeys)

    local specKey = GetSpecKey()
    if not specKey then return end

    local profile = addon:GetProfile()
    if not profile then return end
    if not profile.customQueue then profile.customQueue = {} end
    if not profile.customQueue[specKey] then profile.customQueue[specKey] = {} end
    local cq = profile.customQueue[specKey]
    if not cq.spells then cq.spells = {} end
    local spellList = cq.spells

    local updateFunc = function()
        InvalidateRotationCache()
        CustomQueue.UpdateCustomQueueOptions(addon)
        addon:ForceUpdate()
    end
    SpellSearch.RebuildListSection(addon, spellListArgs, {
        spellList = spellList, listType = "customqueue",
        baseOrder = 12, addOrder = 30,
        listName = L["Custom Queue Spells"], updateFunc = updateFunc,
        spellsOnly = false, emptyText = L["Custom Queue Empty"],
    })

    -- Cap transparency: entries that sink (cooldown, out of range, active DoT)
    -- trail the ready ones, so a list longer than Max Icons silently pushes them
    -- off the end - the most common "my ability is missing" confusion.
    local maxIcons = profile.maxIcons or 4
    if #spellList > maxIcons then
        spellListArgs.capNote = {
            type = "description",
            name = "|cffffcc00" .. string.format(L["Custom Queue Cap Note"], #spellList, maxIcons) .. "|r",
            order = 31,
            fontSize = "medium",
        }
    end

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end

--- Check if rotation has changed and print a one-time chat notification.
--- Called on spec load / combat exit. Only notifies once per session per spec.
local notifiedSpecs = {}
function CustomQueue.CheckStaleNotification(addon)
    local specKey = GetSpecKey()
    if not specKey or notifiedSpecs[specKey] then return end

    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.customQueue then return end
    local cq = profile.customQueue[specKey]
    if not cq or not cq.enabled or not cq.baseline then return end

    local added, removed = DiffRotation(addon, specKey)
    if not added and not removed then return end

    notifiedSpecs[specKey] = true
    local msg = BuildStaleWarning(added, removed)
    if msg and addon.Print then
        addon:Print(L["Custom Queue Stale Chat"] .. " " .. msg)
    end
end

--- Ensure custom queue data exists for the current spec.
--- Default state is disabled; snapshot only when explicitly enabled.
--- Called on spec change alongside gap-closer/burst injection init.
function CustomQueue.EnsureInitialized(addon)
    local specKey = GetSpecKey()
    if not specKey then return end

    local profile = addon and addon.db and addon.db.profile
    if not profile then return end
    if not profile.customQueue then profile.customQueue = {} end

    local cq = profile.customQueue[specKey]
    if not cq then
        profile.customQueue[specKey] = {
            enabled = false,
            spells = {},
        }
        cq = profile.customQueue[specKey]
    end

    -- Default off for existing profiles that don't have this flag yet.
    if cq.enabled == nil then
        cq.enabled = false
    end

    -- Backfill spell list if user previously enabled custom queue but has no snapshot.
    if cq.enabled and (not cq.spells or #cq.spells == 0) then
        SnapshotRotation(addon, specKey)
        InvalidateRotationCache()
    end
end

