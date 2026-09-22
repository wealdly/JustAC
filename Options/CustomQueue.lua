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

--- True when custom queue is NOT enabled for current spec.
local function IsCustomQueueOff(addon)
    local profile = addon:GetProfile()
    local specKey = GetSpecKey()
    return not (profile and profile.customQueue
        and specKey and profile.customQueue[specKey]
        and profile.customQueue[specKey].enabled)
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

CustomQueue.SnapshotBaseline = snapshotBaseline   -- shared with the priority list widget

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
    local PL = LibStub("JustAC-PriorityList", true)
    for _, spellID in ipairs(rotationSpells) do
        -- Upkeep is excluded HERE rather than pruned later: copying it in and deleting it
        -- one call afterwards told the player we had removed entries they never added.
        if not (PL and PL.IsUpkeep and PL.IsUpkeep(spellID)) then
            cq.spells[#cq.spells + 1] = spellID
        end
    end
    -- The game hands its pool over in spell-id order, which reads as nonsense in a list the
    -- user is about to reorder (Eviscerate at step 8, poisons at 2-4) and IS the order with
    -- Context Ordering off. Seed it as a priority instead: theorycraft rank, then the game's
    -- own step order, then id. Unranked entries (utility) fall to the bottom.
    if PL and PL.SortByPriority then PL.SortByPriority(cq.spells, "simc") end

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
        parts[#parts + 1] = #added .. " " .. L["spells added"]
    end
    if removed and #removed > 0 then
        parts[#parts + 1] = #removed .. " " .. L["spells removed"]
    end
    if #parts == 0 then return nil end
    return "|cFFFFAA00" .. L["Custom Queue Stale Warning"] .. ": " .. table_concat(parts, ", ") .. ".|r"
end

function CustomQueue.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Custom Queue"],
        order = 1,
        args = {
            ordering = {
                type = "group",
                inline = true,
                name = L["Custom Queue Ordering"],
                order = 20,
                -- "Which list" moved to the widget's tab strip; what stays here is how the
                -- chosen list is treated, which is the same question for all three.
                args = {
                    procsFirst    = MakeOrderingToggle(addon, "orderProcsFirst", L["Custom Queue Procs First"], L["Custom Queue Procs First desc"], 1),
                    sinkCooldowns = MakeOrderingToggle(addon, "orderSinkCooldowns", L["Custom Queue Sink Cooldowns"],
                        W.spellDesc("Custom Queue Sink Cooldowns desc", 163201), 2),  -- Execute
                    -- Last, and with its warning in the panel rather than in a tooltip: it
                    -- switches OFF the situational reordering the other two build on, so
                    -- the consequence should be readable without hovering anything.
                    orderExact = {
                        type = "toggle",
                        name = W.risky(L["Order Exact"]),
                        desc = L["Order Exact desc"],
                        order = 10,
                        width = "full",
                        get = function()
                            local profile = addon:GetProfile()
                            return (profile and profile.orderExact) == true
                        end,
                        set = function(_, val)
                            local profile = addon:GetProfile()
                            if not profile then return end
                            -- Its OWN field: stored in contextOrder it fought the tab strip,
                            -- which reads that field to say which source is live.
                            profile.orderExact = val or nil
                            InvalidateRotationCache()
                            addon:ForceUpdateAll()
                            if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
                        end,
                    },
                    orderExactNote = {
                        type = "description",
                        name = function()
                            local profile = addon:GetProfile()
                            return (profile and profile.orderExact)
                                and ("|cffffcc00" .. L["Order Exact note on"] .. "|r")
                                or L["Order Exact note off"]
                        end,
                        order = 11,
                        fontSize = "small",
                        width = "full",
                    },
                },
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
                        local PL = LibStub("JustAC-PriorityList", true)
                        for _, sid in ipairs(added) do
                            if not (PL and PL.IsUpkeep and PL.IsUpkeep(sid)) then
                                cq.spells[#cq.spells + 1] = sid
                            end
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
                order = 1,
                args = {
                    leadMode = {
                        type = "select",
                        name = W.risky(L["Lead Mode"]),
                        desc = L["Lead Mode desc"],
                        -- Sunk below the list on purpose: it is a rarely-useful expert
                        -- setting, and sitting above the list it read as a headline feature.
                        order = 40,
                        width = "full",
                        values = function()
                            local v = { off = L["Lead Off"], safe = L["Lead Safe"] }
                            -- Leading with a list needs a list, so that answer only
                            -- appears once there is one to lead with.
                            local profile = addon:GetProfile()
                            local specKey = GetSpecKey()
                            local cq = profile and specKey and profile.customQueue
                                and profile.customQueue[specKey]
                            if cq and cq.spells and #cq.spells > 0 then
                                v.mylist = L["Lead My List"]
                            end
                            return v
                        end,
                        sorting = function()
                            local profile = addon:GetProfile()
                            local specKey = GetSpecKey()
                            local cq = profile and specKey and profile.customQueue
                                and profile.customQueue[specKey]
                            if cq and cq.spells and #cq.spells > 0 then
                                return { "off", "safe", "mylist" }
                            end
                            return { "off", "safe" }
                        end,
                        get = function()
                            local SQ = LibStub("JustAC-SpellQueue", true)
                            -- The queue owns the reading, including what a pre-dropdown
                            -- save meant, so the panel cannot drift from the behaviour.
                            return (SQ and SQ.LeadMode and SQ.LeadMode(addon:GetProfile())) or "off"
                        end,
                        set = function(_, val)
                            local profile = addon:GetProfile()
                            local specKey = GetSpecKey()
                            if not (profile and specKey) then return end
                            profile.customQueue = profile.customQueue or {}
                            profile.customQueue[specKey] = profile.customQueue[specKey]
                                or { enabled = false, spells = {} }
                            local cq = profile.customQueue[specKey]
                            cq.leadMode = (val ~= "off") and val or nil
                            cq.myListLeads = nil   -- migrated: the dropdown is the setting now
                            -- Through Changed, not ForceUpdateAll: this decides what the
                            -- position-1 row says, and only a rebuild repaints the widget.
                            local PL = LibStub("JustAC-PriorityList", true)
                            if PL and PL.Changed then PL.Changed(addon) else addon:ForceUpdateAll() end
                        end,
                    },
                    priorityList = {
                        type = "description",
                        name = "",
                        order = 11.8,
                        width = "full",
                        -- The list draws itself (Options/PriorityList.lua): one 26px row per
                        -- ability, the position-1 row the game owns, and a lock on every
                        -- entry only the game can time. Falls back to nothing rather than
                        -- killing the panel if the widget did not register.
                        dialogControl = (function()
                            local AceGUI = LibStub("AceGUI-3.0", true)
                            if AceGUI and AceGUI.GetWidgetVersion and AceGUI:GetWidgetVersion("JustACPriorityList") then
                                return "JustACPriorityList"
                            end
                            return nil
                        end)(),
                    },
                    -- Settings for the one row the player opened, added by UpdateCustomQueueOptions
                },
            },
            -- RESET (990+)
            resetHeader = {
                type = "header",
                name = "",
                order = 990,
            },
            refreshFromRotation = {
                type = "execute",
                name = L["Refresh from Rotation"],
                desc = L["Refresh from Rotation desc"],
                order = 991,
                width = "normal",
                disabled = function() return IsCustomQueueOff(addon) end,
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
    local staticKeys = { leadMode = true, priorityList = true }
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
    local PriorityList = LibStub("JustAC-PriorityList", true)
    -- A list made before upkeep abilities were excluded still carries them, and they stall
    -- the queue. Repair it here, once, and tell the player why their list got shorter.
    if PriorityList and PriorityList.PruneUpkeep and cq.enabled then
        local dropped = PriorityList.PruneUpkeep(addon)
        if dropped > 0 and addon.Print then
            addon:Print(string.format(L["Upkeep Pruned"], dropped))
        end
    end
    SpellSearch.RebuildListSection(addon, spellListArgs, {
        spellList = spellList, listType = "customqueue",
        baseOrder = 12, addOrder = 30,
        listName = L["Custom Queue Spells"], updateFunc = updateFunc,
        spellsOnly = false, emptyText = L["Custom Queue Empty"],
        -- Rows, reordering and per-ability settings all live in the widget now, so Ace
        -- renders NO entry group. Its Up/Down/Remove duplicated the row's own controls
        -- and opened below the whole table rather than under the ability. 0 is "no entry
        -- matches"; nil would mean "no filter" and redraw the entire legacy list.
        onlyEntry = PriorityList and 0 or nil,
    })

    -- The add button belongs to YOUR list: on the read-only previews there is nothing to
    -- add to. Its generated name ("Add <list name>...") also overran the row.
    local addButton = spellListArgs["add_popup_customqueue"]
    if addButton then
        addButton.name = L["Priority Add"]
        addButton.hidden = function()
            return not PriorityList or PriorityList.CurrentSource(addon:GetProfile()) ~= "custom"
        end
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
--- Called on spec change alongside the gap-closer init.
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

