-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Options/Profiles - Per-spec profile switching (injected into AceDBOptions tab)
local Profiles = LibStub:NewLibrary("JustAC-OptionsProfiles", 1)
if not Profiles then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-------------------------------------------------------------------------------
-- Add per-spec profile switching options to the profiles section
-------------------------------------------------------------------------------
function Profiles.AddSpecProfileOptions(addon)
    local profilesArgs = addon.optionsTable.args.profiles.args
    if not profilesArgs then return end

    -- Helper to get list of profiles plus special values
    local function GetProfileValues()
        local values = {
            [""] = L["(No change)"],
        }
        -- Add all existing profiles
        local profiles = addon.db:GetProfiles()
        if profiles then
            for _, name in ipairs(profiles) do
                values[name] = name
            end
        end
        -- Add disabled option at the end
        values["DISABLED"] = L["(Disabled)"]
        return values
    end

    -- Sorting function to ensure (No change) first, profiles alphabetically, (Disabled) last
    local function GetProfileSorting()
        local order = { "" }  -- (No change) first
        local profiles = addon.db:GetProfiles()
        if profiles then
            table.sort(profiles)  -- Alphabetical order
            for _, name in ipairs(profiles) do
                table.insert(order, name)
            end
        end
        table.insert(order, "DISABLED")  -- (Disabled) always last
        return order
    end

    -- Helper to get spec name with icon (called dynamically when panel renders)
    local function GetSpecName(specIndex)
        local _, specName, _, specIcon = GetSpecializationInfo(specIndex)
        if specName then
            local iconString = specIcon and ("|T" .. specIcon .. ":16:16:0:0|t ") or ""
            return iconString .. specName
        end
        return "Spec " .. specIndex
    end

    -- Helper to check if spec exists (called dynamically)
    local function SpecExists(specIndex)
        local numSpecs = GetNumSpecializations()
        return specIndex <= numSpecs
    end

    -- Add inline group for spec-based switching
    profilesArgs.specSwitching = {
        type = "group",
        name = L["Spec-Based Switching"],
        inline = true,
        order = 100,
        args = {
            enabled = {
                type = "toggle",
                name = L["Auto-switch profile by spec"],
                order = 1,
                width = "full",
                get = function() return addon.db.char.specProfilesEnabled end,
                set = function(_, val)
                    addon.db.char.specProfilesEnabled = val
                    -- Refresh options panel to show/hide spec dropdowns
                    if AceConfigRegistry then
                        AceConfigRegistry:NotifyChange("JustAssistedCombat")
                    end
                    -- If enabling and current spec has a mapping, apply it
                    if val then
                        local currentSpec = GetSpecialization()
                        if currentSpec and addon.db.char.specProfiles[currentSpec] then
                            addon:OnSpecChange()
                        end
                    elseif addon.isDisabledMode then
                        -- If disabling feature while in disabled mode, exit it
                        addon:ExitDisabledMode()
                    end
                end,
            },
        },
    }

    -- Add spec dropdowns for all possible specs (max 4)
    -- Use dynamic hidden/name to handle specs that don't exist yet at init time
    for i = 1, 4 do
        local specIndex = i  -- Capture for closure
        profilesArgs.specSwitching.args["spec" .. i] = {
            type = "select",
            name = function() return GetSpecName(specIndex) end,
            order = 10 + i,
            width = 1.2,
            values = GetProfileValues,
            sorting = GetProfileSorting,
            hidden = function()
                return not addon.db.char.specProfilesEnabled or not SpecExists(specIndex)
            end,
            get = function()
                return addon.db.char.specProfiles[specIndex] or ""
            end,
            set = function(_, val)
                if val == "" then
                    addon.db.char.specProfiles[specIndex] = nil
                else
                    addon.db.char.specProfiles[specIndex] = val
                end
                -- If this is the current spec, apply the change
                local currentSpec = GetSpecialization()
                if currentSpec == specIndex then
                    addon:OnSpecChange()
                end
            end,
        }
    end
end
