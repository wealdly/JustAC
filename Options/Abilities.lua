-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Abilities - one per-ability card over the existing stores.
--
-- Lists answer WHEN (order, on their own tabs); this card answers HOW: visibility
-- (the blacklist), pins, item settings, list membership, and the hotkey override,
-- all for one searched ability. The card is a VIEW - it reads and writes the same
-- nine stores the engines already consume; no storage moved and no migration.
local Abilities = LibStub:NewLibrary("JustAC-OptionsAbilities", 1)
if not Abilities then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Session-only selection; the card is rebuilt around it.
local selectedID = nil

local function GetSpecKey()
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
end

local function NotifyChange()
    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
end

-------------------------------------------------------------------------------
-- Store accessors (create-on-write; nil-safe on read)
-------------------------------------------------------------------------------
local function BlacklistTable(profile, create)
    local specKey = GetSpecKey()
    if not specKey then return nil end
    if not profile.blacklistedSpells then
        if not create then return nil end
        profile.blacklistedSpells = {}
    end
    if not profile.blacklistedSpells[specKey] then
        if not create then return nil end
        profile.blacklistedSpells[specKey] = {}
    end
    return profile.blacklistedSpells[specKey]
end

local function SpellSettings(profile, id, create)
    local d = profile.defensives
    if not d then return nil end
    if not d.spellSettings then
        if not create then return nil end
        d.spellSettings = {}
    end
    if not d.spellSettings[id] then
        if not create then return nil end
        d.spellSettings[id] = {}
    end
    return d.spellSettings[id]
end

local function ItemSettings(profile, itemID, create)
    local d = profile.defensives
    if not d then return nil end
    if not d.itemSettings then
        if not create then return nil end
        d.itemSettings = {}
    end
    if not d.itemSettings[itemID] then
        if not create then return nil end
        d.itemSettings[itemID] = {}
    end
    return d.itemSettings[itemID]
end

-------------------------------------------------------------------------------
-- List descriptors for the membership section. resolve() returns the live list
-- table for the current spec (nil = list unavailable right now); after() runs
-- the same refresh chain that list's own tab uses. fits(id, roleFam) filters the
-- row by ability type - an ability already IN a list always shows its row, so
-- Remove can never be filtered away. roleFam is "offensive"/"defensive"/"both"
-- from SpellSearch.RoleTag ("both" covers Disruption, Utility, and items).
-------------------------------------------------------------------------------
local function FitsOffense(_, roleFam) return roleFam ~= "defensive" end
local function FitsDefense(_, roleFam) return roleFam ~= "offensive" end

-- Gap-closers: only the spec's curated movement spells qualify.
local function FitsGapCloser(id)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = GetSpecKey()
    local defaults = SpellDB and specKey and SpellDB.CLASS_GAPCLOSER_DEFAULTS
        and SpellDB.CLASS_GAPCLOSER_DEFAULTS[specKey]
    if not defaults then return false end
    for _, sid in ipairs(defaults) do
        if sid == id then return true end
    end
    return false
end

-- Burst triggers: offensive-family with a real cooldown - the spec's curated
-- trigger defaults qualify outright; anything else needs a base CD >= 30s.
local function FitsBurstTrigger(id, roleFam)
    if roleFam == "defensive" then return false end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local specKey = GetSpecKey()
    local defaults = SpellDB and specKey and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS
        and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
    if defaults then
        for _, sid in ipairs(defaults) do
            if sid == id then return true end
        end
    end
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local cd = BlizzardAPI and BlizzardAPI.GetBaseCooldownSeconds
        and BlizzardAPI.GetBaseCooldownSeconds(id)
    return (cd or 0) >= 30
end

local LISTS = {
    {
        key = "custom", nameKey = "Custom Queue Spells",
        spellsOnly = false, fits = FitsOffense,
        resolve = function(profile)
            local specKey = GetSpecKey()
            local cq = specKey and profile.customQueue and profile.customQueue[specKey]
            if not (cq and cq.enabled) then return nil, L["Custom Priority Disabled"] end
            return cq.spells
        end,
        after = function(addon)
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
            local CQ = LibStub("JustAC-OptionsCustomQueue", true)
            if CQ and CQ.UpdateCustomQueueOptions then CQ.UpdateCustomQueueOptions(addon) end
            addon:ForceUpdateAll()
        end,
    },
    {
        key = "defensive", nameKey = "Defensive Priority List",
        spellsOnly = false, listField = "defensiveSpells", fits = FitsDefense,
    },
    {
        key = "gap", nameKey = "Gap-Closers",
        spellsOnly = true, fits = FitsGapCloser,
        resolve = function(profile)
            local specKey = GetSpecKey()
            local gc = specKey and profile.gapClosers and profile.gapClosers.classSpells
            return gc and gc[specKey]
        end,
        after = function(addon)
            local GCE = LibStub("JustAC-GapCloserEngine", true)
            if GCE and GCE.InvalidateGapCloserCache then GCE.InvalidateGapCloserCache() end
            local GC = LibStub("JustAC-OptionsGapClosers", true)
            if GC and GC.UpdateGapCloserOptions then GC.UpdateGapCloserOptions(addon) end
            addon:ForceUpdate()
        end,
    },
    {
        key = "burst", nameKey = "Burst Triggers",
        spellsOnly = true, fits = FitsBurstTrigger,
        resolve = function(profile)
            local specKey = GetSpecKey()
            if not specKey then return nil end
            profile.burstTriggers = profile.burstTriggers or {}
            profile.burstTriggers[specKey] = profile.burstTriggers[specKey] or {}
            return profile.burstTriggers[specKey]
        end,
        after = function(addon)
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.InvalidateBurstTriggers then SQ.InvalidateBurstTriggers() end
            local Off = LibStub("JustAC-OptionsOffensive", true)
            if Off and Off.UpdateBurstTriggerOptions then Off.UpdateBurstTriggerOptions(addon) end
            addon:ForceUpdate()
        end,
    },
    {
        key = "petrez", nameKey = "Pet Rez/Summon Priority List",
        spellsOnly = true, listField = "petRezSpells", petOnly = true, fits = FitsDefense,
    },
    {
        key = "petheal", nameKey = "Pet Heal Priority List",
        spellsOnly = false, listField = "petHealSpells", petOnly = true, fits = FitsDefense,
    },
}

-- Shared resolve/after for the three defensive-family lists (listField set above).
local function ResolveClassList(profile, listField)
    local specKey = GetSpecKey()
    local cs = specKey and profile.defensives and profile.defensives.classSpells
        and profile.defensives.classSpells[specKey]
    return cs and cs[listField]
end

local function AfterDefensiveList(addon)
    local Def = LibStub("JustAC-OptionsDefensives", true)
    if Def and Def.UpdateDefensivesOptions then Def.UpdateDefensivesOptions(addon) end
    local DE = LibStub("JustAC-DefensiveEngine", true)
    if DE and DE.RegisterDefensivesForTracking then DE.RegisterDefensivesForTracking(addon) end
    addon:ForceUpdateAll()
end

local function IsPetClass()
    local _, pc = UnitClass("player")
    local SpellDB = LibStub("JustAC-SpellDB", true)
    return SpellDB and SpellDB.ClassHasPetDefaults and SpellDB.ClassHasPetDefaults(pc)
end

local function ListIndexOf(list, id)
    if not list then return nil end
    for i, v in ipairs(list) do
        if v == id then return i end
    end
    return nil
end

-------------------------------------------------------------------------------
-- The customizations index: every ability with non-default state.
-- Bare list membership is deliberately NOT a customization (the defensive lists
-- are auto-seeded; indexing them would flood this with defaults).
-------------------------------------------------------------------------------
local function CollectCustomizations(profile)
    local seen = {}
    local function badge(id, text)
        if not seen[id] then seen[id] = {} end
        seen[id][#seen[id] + 1] = text
    end

    local bl = BlacklistTable(profile, false)
    if bl then
        for id, v in pairs(bl) do
            if type(id) == "number" and id ~= 0 then
                badge(id, v == true and L["Visibility Everywhere Badge"] or L["Visibility Queue Badge"])
            end
        end
    end
    local ss = profile.defensives and profile.defensives.spellSettings
    if ss then
        for id, s in pairs(ss) do
            if type(id) == "number" and type(s) == "table"
               and (s.procPriority == false or s.alwaysShow == true or s.holdUntilCharged == true) then
                badge(id, L["Pinned Badge"])
            end
        end
    end
    local is = profile.defensives and profile.defensives.itemSettings
    if is then
        for itemID, s in pairs(is) do
            if type(itemID) == "number" and type(s) == "table"
               and (s.linkedAura or s.combatHide) then
                badge(-itemID, L["Item Settings Badge"])
            end
        end
    end
    if profile.hotkeyOverrides then
        for id, v in pairs(profile.hotkeyOverrides) do
            if type(id) == "number" and id ~= 0 and type(v) == "string" then
                badge(id, string.format(L["Hotkey Badge"], v))
            end
        end
    end

    local out = {}
    for id, badges in pairs(seen) do
        local name = SpellSearch.DisplayInfo(id)
        out[#out + 1] = {
            id = id,
            name = name or ((id < 0 and "Item #" or "Spell #") .. math.abs(id)),
            badges = table.concat(badges, " · "),
        }
    end
    table.sort(out, function(a, b)
        return SpellSearch.StripColor(a.name) < SpellSearch.StripColor(b.name)
    end)
    return out
end

-------------------------------------------------------------------------------
-- Card builder: writes the dynamic args for the selected ability.
-------------------------------------------------------------------------------
local function BuildCard(addon, args, profile)
    local id = selectedID
    local name, icon = SpellSearch.DisplayInfo(id)
    local isItem = id < 0
    local displayName = name or ((isItem and "Item #" or "Spell #") .. math.abs(id))
    if isItem and name then displayName = displayName .. " |cff00ccff[Item]|r" end
    local specKey = GetSpecKey()

    local roleTag, roleFam = SpellSearch.RoleTag(id)
    roleFam = roleFam or "both"  -- items: role is context-specific, fits everywhere

    args.cardHeader = {
        type = "description",
        name = "|T" .. (icon or 134400) .. ":24:24:0:0|t  |cffFFD100" .. displayName .. "|r  |cff888888("
            .. (isItem and ("item:" .. -id) or ("ID: " .. id)) .. ")|r"
            .. (roleTag and ("  " .. roleTag) or ""),
        order = 10,
        fontSize = "large",
    }

    -- ── Visibility (per-spec; the blacklist behind its real name) ───────────
    args.visibility = {
        type = "select",
        name = L["Ability Visibility"],
        desc = L["Ability Visibility desc"],
        order = 11,
        width = "double",
        values = function()
            local v = {
                normal     = L["Visibility Normal"],
                everywhere = L["Visibility Everywhere"],
            }
            -- Items never appear in the AC slot, so the middle state is spells-only.
            if not isItem then v.queueOnly = L["Visibility Queue Only"] end
            return v
        end,
        sorting = function()
            return isItem and { "normal", "everywhere" }
                or { "normal", "queueOnly", "everywhere" }
        end,
        get = function()
            local bl = BlacklistTable(profile, false)
            local v = bl and bl[id]
            if v == true then return "everywhere" end
            if type(v) == "table" then return "queueOnly" end
            return "normal"
        end,
        set = function(_, val)
            local bl = BlacklistTable(profile, true)
            if not bl then return end
            if val == "normal" then bl[id] = nil
            elseif val == "queueOnly" then bl[id] = { fixedQueue = true }
            else bl[id] = true end
            addon:ForceUpdate()
            Abilities.UpdateAbilitiesOptions(addon)
        end,
        disabled = function() return not specKey end,
    }

    -- ── Pins (global across specs; effective while the ability is in a list) ─
    local function pinToggle(field, nameL, descL, order, defaultOn)
        return {
            type = "toggle",
            name = L[nameL],
            desc = L[descL],
            order = order,
            width = "normal",
            get = function()
                local s = SpellSettings(profile, id, false)
                if defaultOn then return not s or s[field] ~= false end
                return s and s[field] == true or false
            end,
            set = function(_, val)
                local s = SpellSettings(profile, id, true)
                if not s then return end
                if defaultOn then
                    s[field] = (not val) and false or nil
                else
                    s[field] = val or nil
                end
                if not next(s) then profile.defensives.spellSettings[id] = nil end
                addon:ForceUpdateAll()
                Abilities.UpdateAbilitiesOptions(addon)
            end,
        }
    end
    args.pinProc   = pinToggle("procPriority", "Proc Priority", "Proc Priority desc", 12, true)
    args.pinAlways = pinToggle("alwaysShow", "Always Show", "Always Show desc", 13, false)
    args.pinHold   = pinToggle("holdUntilCharged", "Hold Until Charged", "Hold Until Charged desc", 14, false)
    -- SpellQueue honours holdUntilCharged only while the custom queue is the rotation
    -- source AND "Unavailable last" sinking is on - grey the pin out exactly like the
    -- custom-queue row twin, plus the custom-queue half the rows get for free by hiding.
    args.pinHold.disabled = function()
        local p = addon.db.profile
        if p.orderSinkCooldowns == false then return true end
        local sk = GetSpecKey()
        local cq = sk and p.customQueue and p.customQueue[sk]
        return not (cq and cq.enabled)
    end
    args.pinNote = {
        type = "description",
        name = "|cff888888" .. L["Ability Pins Note"] .. "|r",
        order = 15,
        fontSize = "small",
    }

    -- ── Item settings (mirror the defensive-row controls) ───────────────────
    if isItem then
        local itemID = -id
        args.linkAura = {
            type = "execute",
            name = function()
                local s = ItemSettings(profile, itemID, false)
                if s and s.linkedAura then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s.linkedAura)
                    return (info and info.name) or tostring(s.linkedAura)
                end
                return L["Link Aura..."]
            end,
            desc = L["Link Aura desc"],
            order = 16,
            width = "double",
            func = function()
                local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
                if not LiveSearchPopup then return end
                LiveSearchPopup.Open({
                    title      = L["Link Aura..."],
                    searchFunc = SpellSearch.GetFilteredPlayerAuras,
                    onSelect   = function(auraSpellID)
                        local s = ItemSettings(profile, itemID, true)
                        if not s then return end
                        s.linkedAura = auraSpellID
                        if s.combatHide == nil then s.combatHide = true end
                        addon:ForceUpdateAll()
                        Abilities.UpdateAbilitiesOptions(addon)
                    end,
                })
            end,
        }
        args.clearAura = {
            type = "execute",
            name = L["Clear Link"],
            desc = L["Clear Link desc"],
            order = 17,
            width = "half",
            hidden = function()
                local s = ItemSettings(profile, itemID, false)
                return not (s and s.linkedAura)
            end,
            func = function()
                local s = ItemSettings(profile, itemID, false)
                if s then s.linkedAura = nil end
                addon:ForceUpdateAll()
                Abilities.UpdateAbilitiesOptions(addon)
            end,
        }
        args.combatHide = {
            type = "toggle",
            name = L["Hide in Combat"],
            desc = L["Hide in Combat desc"],
            order = 18,
            width = "normal",
            get = function()
                local s = ItemSettings(profile, itemID, false)
                return s and s.combatHide or false
            end,
            set = function(_, val)
                local s = ItemSettings(profile, itemID, true)
                if s then s.combatHide = val or nil end
                addon:ForceUpdateAll()
            end,
        }
    end

    -- ── List membership ─────────────────────────────────────────────────────
    args.listsHeader = {
        type = "header",
        name = SpellSearch.SpecHeader(L["Ability Lists"]),
        order = 20,
    }
    local order = 21
    for _, desc in ipairs(LISTS) do
        local list, naText
        if desc.listField then
            list = ResolveClassList(profile, desc.listField)
        else
            list, naText = desc.resolve(profile)
        end
        local pos = ListIndexOf(list, id)

        -- Type-filtered: a row appears when the ability is already in that list
        -- (Remove must always be reachable) or genuinely fits it.
        if (not desc.petOnly or IsPetClass())
           and not (desc.spellsOnly and isItem)
           and (pos or desc.fits(id, roleFam)) then
            local after = desc.listField and AfterDefensiveList or desc.after

            args["list_" .. desc.key] = {
                type = "description",
                name = L[desc.nameKey] .. ": " .. (pos and ("|cff2ecc71#" .. pos .. "|r")
                    or (list and "|cff888888—|r" or ("|cff888888" .. (naText or "—") .. "|r"))),
                order = order,
                width = "double",
            }
            -- Resolved at PRESS time, not captured from the card build: a rotation
            -- re-snapshot replaces the underlying table (SnapshotRotation builds a
            -- fresh one), and mutating the stale capture was a silent no-op.
            local function LiveList()
                if desc.listField then return ResolveClassList(profile, desc.listField) end
                return (desc.resolve(profile))
            end
            args["listbtn_" .. desc.key] = {
                type = "execute",
                name = pos and L["Remove"] or L["Add"],
                order = order + 0.1,
                width = "half",
                disabled = function() return not LiveList() end,
                func = function()
                    local live = LiveList()
                    if not live then return end
                    local at = ListIndexOf(live, id)
                    if at then
                        table.remove(live, at)
                    else
                        if not SpellSearch.AddSpellToList(addon, live, id) then return end
                    end
                    after(addon)
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            }
            order = order + 1
        end
    end

    -- ── Hotkey override (global) ────────────────────────────────────────────
    args.hotkeyHeader = { type = "header", name = L["Custom Hotkey"], order = 40 }
    args.hotkey = {
        type = "input",
        name = L["Custom Hotkey"],
        desc = L["Enter the hotkey text to display (e.g. 1, F1, S-2)"],
        order = 41,
        width = "normal",
        get = function()
            return (profile.hotkeyOverrides and profile.hotkeyOverrides[id]) or ""
        end,
        set = function(_, val)
            if not profile.hotkeyOverrides then profile.hotkeyOverrides = {} end
            local trimmed = val and val:trim() or ""
            profile.hotkeyOverrides[id] = trimmed ~= "" and trimmed or nil
            addon:ForceUpdate()
            Abilities.UpdateAbilitiesOptions(addon)
        end,
    }

    -- ── Clear everything for this ability ───────────────────────────────────
    args.clearAbility = {
        type = "execute",
        name = L["Clear Ability"],
        desc = L["Clear Ability desc"],
        order = 50,
        width = "normal",
        confirm = true,
        func = function()
            local bl = BlacklistTable(profile, false)
            if bl then bl[id] = nil end
            if profile.defensives then
                if profile.defensives.spellSettings then profile.defensives.spellSettings[id] = nil end
                if isItem and profile.defensives.itemSettings then profile.defensives.itemSettings[-id] = nil end
            end
            if profile.hotkeyOverrides then profile.hotkeyOverrides[id] = nil end
            for _, desc in ipairs(LISTS) do
                local list = desc.listField and ResolveClassList(profile, desc.listField)
                    or desc.resolve(profile)
                local at = ListIndexOf(list, id)
                if at then
                    table.remove(list, at)
                    local after = desc.listField and AfterDefensiveList or desc.after
                    after(addon)
                end
            end
            addon:ForceUpdateAll()
            local Opt = LibStub("JustAC-Options", true)
            if Opt and Opt.RefreshAllDynamic then Opt.RefreshAllDynamic(addon) end
        end,
    }
end

-------------------------------------------------------------------------------
-- Tab skeleton + dynamic rebuild
-------------------------------------------------------------------------------
function Abilities.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Abilities"],
        order = 5.5,  -- exceptions come after the queues they override, above Profiles
        args = {
            info = {
                type = "description",
                name = L["Abilities Info"],
                order = 1,
                fontSize = "medium",
            },
            -- Dynamic content added by UpdateAbilitiesOptions
        },
    }
end

function Abilities.UpdateAbilitiesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not optionsTable.args.abilities then return end
    local args = optionsTable.args.abilities.args
    local profile = addon:GetProfile()
    if not profile then return end

    SpellSearch.ClearDynamicArgs(args, { info = true })

    args.selectAbility = {
        type = "execute",
        name = L["Select Spell..."],
        order = 2,
        width = "normal",
        func = function()
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end
            SpellSearch.BuildSpellbookCache()
            LiveSearchPopup.Open({
                title      = L["Abilities"],
                searchFunc = SpellSearch.GetFilteredResults,
                onSelect   = function(id)
                    if not id or id == 0 then return end
                    selectedID = id
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            })
        end,
    }

    if selectedID then
        BuildCard(addon, args, profile)
    end

    -- ── Customizations index ────────────────────────────────────────────────
    args.customHeader = {
        type = "header",
        name = L["Your Customizations"],
        order = 60,
    }
    local rows = CollectCustomizations(profile)
    if #rows == 0 then
        args.noCustomizations = {
            type = "description",
            name = "|cff888888" .. L["No Customizations"] .. "|r",
            order = 61,
        }
    else
        for i, row in ipairs(rows) do
            local _, icon = SpellSearch.DisplayInfo(row.id)
            args["cust_" .. tostring(row.id)] = {
                type = "execute",
                name = "|T" .. (icon or 134400) .. ":16:16:0:0|t " .. row.name
                    .. "  |cff888888" .. row.badges .. "|r",
                order = 60 + i,
                width = "full",
                func = function()
                    selectedID = row.id
                    Abilities.UpdateAbilitiesOptions(addon)
                end,
            }
        end
    end

    NotifyChange()
end
