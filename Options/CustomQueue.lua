-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/CustomQueue - Custom Queue tab for user-defined rotation ordering
local CustomQueue = LibStub:NewLibrary("JustAC-OptionsCustomQueue", 1)
if not CustomQueue then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local ipairs = ipairs
local table_concat = table.concat
local wipe = wipe
local pcall = pcall

--- Resolve a spell ID to its base ID (handles talent overrides).
local function ResolveSpellID(id)
    return BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(id) or id
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

--- Snapshot the current Blizzard rotation into the profile (baseline + spells).
--- Returns true if snapshot was taken, false if no rotation available.
local function SnapshotRotation(addon, specKey)
    if not BlizzardAPI or not BlizzardAPI.GetRotationSpells then return false end

    local rotationSpells = BlizzardAPI.GetRotationSpells()
    if not rotationSpells or #rotationSpells == 0 then return false end

    local profile = addon and addon.db and addon.db.profile
    if not profile then return false end
    if not profile.customQueue then profile.customQueue = {} end
    if not profile.customQueue[specKey] then profile.customQueue[specKey] = {} end

    local cq = profile.customQueue[specKey]
    cq.spells = {}
    cq.baseline = {}
    for i, spellID in ipairs(rotationSpells) do
        cq.spells[i] = spellID
        cq.baseline[i] = spellID
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

    -- Build sets for comparison (use resolved IDs to avoid false positives from talent swaps)
    local baselineSet = {}
    for _, sid in ipairs(cq.baseline) do
        if sid and sid > 0 then
            baselineSet[ResolveSpellID(sid)] = true
        end
    end
    local currentSet = {}
    for _, sid in ipairs(rotationSpells) do
        if sid and sid > 0 then
            currentSet[ResolveSpellID(sid)] = true
        end
    end

    local added = {}
    local removed = {}
    for sid in pairs(currentSet) do
        if not baselineSet[sid] then
            added[#added + 1] = sid
        end
    end
    for sid in pairs(baselineSet) do
        if not currentSet[sid] then
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
            info = {
                type = "description",
                name = L["Custom Queue Info"],
                order = 1,
                fontSize = "medium",
            },
            blacklistNote = {
                type = "description",
                name = "|cFF999999" .. L["Custom Queue Blacklist Note"] .. "|r",
                order = 1.5,
                fontSize = "small",
            },
            enableCustomQueue = {
                type = "toggle",
                name = L["Enable Custom Queue"],
                desc = L["Enable Custom Queue desc"],
                order = 2,
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
                            removedSet[ResolveSpellID(sid)] = true
                        end
                        if cq.spells then
                            local newSpells = {}
                            for _, sid in ipairs(cq.spells) do
                                if sid and sid > 0 and not removedSet[ResolveSpellID(sid)] then
                                    newSpells[#newSpells + 1] = sid
                                end
                            end
                            cq.spells = newSpells
                        end
                    end

                    -- Update baseline to current rotation
                    if BlizzardAPI and BlizzardAPI.GetRotationSpells then
                        local rotationSpells = BlizzardAPI.GetRotationSpells()
                        if rotationSpells then
                            cq.baseline = {}
                            for i, sid in ipairs(rotationSpells) do
                                cq.baseline[i] = sid
                            end
                        end
                    end

                    InvalidateRotationCache()
                    CustomQueue.UpdateCustomQueueOptions(addon)
                    addon:ForceUpdateAll()
                end,
            },
            -- SPELL LIST GROUP (10+)
            spellListGroup = {
                type = "group",
                inline = true,
                name = function()
                    local className, playerClass = UnitClass("player")
                    local colorCode = (playerClass and SpellSearch and SpellSearch.CLASS_COLORS
                        and SpellSearch.CLASS_COLORS[playerClass]) or "FFFFFFFF"
                    local specIndex = GetSpecialization and GetSpecialization()
                    local specName
                    if specIndex then
                        local _, name = GetSpecializationInfo(specIndex)
                        specName = name
                    end
                    return "|c" .. colorCode .. (className or "Unknown") .. "|r " .. L["Custom Queue Spells"] .. " (" .. (specName or "?") .. ")"
                end,
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
    local keysToClear = {}
    for key, _ in pairs(spellListArgs) do
        if not staticKeys[key] then
            keysToClear[#keysToClear + 1] = key
        end
    end
    for _, key in ipairs(keysToClear) do
        spellListArgs[key] = nil
    end

    local specKey = GetSpecKey()
    if not specKey then return end

    local profile = addon:GetProfile()
    if not profile then return end
    if not profile.customQueue then profile.customQueue = {} end
    if not profile.customQueue[specKey] then profile.customQueue[specKey] = {} end
    local cq = profile.customQueue[specKey]
    if not cq.spells then cq.spells = {} end
    local spellList = cq.spells

    if #spellList == 0 then
        spellListArgs.emptyNote = {
            type = "description",
            name = L["Custom Queue Empty"],
            order = 12,
            fontSize = "medium",
        }
    end

    if not SpellSearch then
        SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
    end
    if SpellSearch then
        local updateFunc = function()
            InvalidateRotationCache()
            CustomQueue.UpdateCustomQueueOptions(addon)
            addon:ForceUpdate()
        end
        SpellSearch.CreateSpellListEntries(addon, spellListArgs, spellList, "customqueue", 12, updateFunc)
        SpellSearch.CreateAddSpellButton(addon, spellListArgs, spellList, "customqueue", 30, L["Custom Queue Spells"], updateFunc, false)
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

--- Ensure the custom queue is initialized for the current spec.
--- Auto-enables and snapshots from Blizzard's rotation if not yet configured.
--- Called on spec change alongside gap-closer/burst injection init.
function CustomQueue.EnsureInitialized(addon)
    local specKey = GetSpecKey()
    if not specKey then return end

    local profile = addon and addon.db and addon.db.profile
    if not profile then return end
    if not profile.customQueue then profile.customQueue = {} end

    local cq = profile.customQueue[specKey]
    -- Already initialized — has spells
    if cq and cq.spells and #cq.spells > 0 then return end

    -- Auto-enable and snapshot from Blizzard rotation
    if not cq then
        profile.customQueue[specKey] = {}
        cq = profile.customQueue[specKey]
    end
    cq.enabled = true
    SnapshotRotation(addon, specKey)

    InvalidateRotationCache()
end

--- Remove a spell from the custom queue for the current spec.
--- Returns true if the spell was found and removed.
function CustomQueue.RemoveSpell(addon, spellID)
    if not spellID or spellID == 0 then return false end
    local specKey = GetSpecKey()
    if not specKey then return false end

    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.customQueue then return false end
    local cq = profile.customQueue[specKey]
    if not cq or not cq.spells then return false end

    -- Items (negative IDs): direct match only. Spells: check both raw and resolved ID.
    local isItem = spellID < 0
    local resolvedTarget = not isItem and ResolveSpellID(spellID) or nil

    local found = false
    local newSpells = {}
    for _, sid in ipairs(cq.spells) do
        if sid == spellID or (not isItem and ResolveSpellID(sid) == resolvedTarget) then
            found = true
        else
            newSpells[#newSpells + 1] = sid
        end
    end

    if not found then return false end
    cq.spells = newSpells

    InvalidateRotationCache()

    CustomQueue.UpdateCustomQueueOptions(addon)
    return true
end
