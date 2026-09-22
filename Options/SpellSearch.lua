-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/SpellSearch - Shared spellbook cache, search/filter, spell list management
local SpellSearch = LibStub:NewLibrary("JustAC-OptionsSpellSearch", 3)
if not SpellSearch then return end

local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
local SpellDB = LibStub("JustAC-SpellDB", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

-- Hot path locals
local wipe = wipe
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local GetInventoryItemID = GetInventoryItemID
local C_Container = C_Container

-------------------------------------------------------------------------------
-- Spellbook cache for autocomplete (populated on first options open)
-------------------------------------------------------------------------------
local spellbookCache = {}  -- {spellID = {name = "Spell Name", icon = iconID}, ...}
local spellbookCacheBuilt = false

-------------------------------------------------------------------------------
-- Build spellbook cache (called once when options panel opens)
-------------------------------------------------------------------------------
function SpellSearch.BuildSpellbookCache()
    if spellbookCacheBuilt then return end

    if not C_SpellBook or not C_SpellBook.GetSpellBookItemInfo then
        return
    end

    local function CacheSlot(slotIndex, bank)
        local spellInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, bank)
        if not spellInfo then return end
        if spellInfo.itemType == Enum.SpellBookItemType.Spell and spellInfo.spellID then
            local isPassive = C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellInfo.spellID)
            if not isPassive then
                local fullInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellInfo.spellID)
                if fullInfo and fullInfo.name then
                    -- Pre-compute search strings to avoid per-keystroke allocations
                    spellbookCache[spellInfo.spellID] = {
                        name      = fullInfo.name,
                        nameLower = fullInfo.name:lower(),
                        idStr     = tostring(spellInfo.spellID),
                        icon      = fullInfo.iconID,
                    }
                    -- The forms this button can take are not in the spellbook, so they
                    -- ride in on their button: searchable by their own name, labelled
                    -- with what they are a form of.
                    local forms = SpellDB and SpellDB.GetTransformForms and SpellDB.GetTransformForms(spellInfo.spellID)
                    for _, formID in ipairs(forms or {}) do
                        local formInfo = C_Spell.GetSpellInfo(formID)
                        if formInfo and formInfo.name and not spellbookCache[formID] then
                            local label = string.format("%s  |cff888888(%s)|r", formInfo.name,
                                string.format(L["Transform Of"], fullInfo.name))
                            spellbookCache[formID] = {
                                name      = label,
                                nameLower = formInfo.name:lower(),
                                idStr     = tostring(formID),
                                icon      = formInfo.iconID,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Enumerate by skill line (11.0+ spellbook), matching Blizzard's own code:
    -- the flat 1..N Player scan BREAKS at the first gap between skill lines, so it
    -- silently drops later tabs - the General line (Recuperate) and class-tree
    -- spells (e.g. Frenzied Regeneration on Druid). Each line has its own
    -- itemIndexOffset + numSpellBookItems range that must be walked separately.
    local playerBank = Enum.SpellBookSpellBank.Player
    if C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if lineInfo and lineInfo.numSpellBookItems then
                for i = 1, lineInfo.numSpellBookItems do
                    CacheSlot(lineInfo.itemIndexOffset + i, playerBank)
                end
            end
        end
    else
        -- Fallback for clients without the skill-line API (contiguous flat scan)
        for i = 1, 500 do
            if not C_SpellBook.GetSpellBookItemInfo(i, playerBank) then break end
            CacheSlot(i, playerBank)
        end
    end

    -- Pet bank has no skill lines - contiguous flat scan
    if Enum.SpellBookSpellBank.Pet then
        for i = 1, 200 do
            if not C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet) then break end
            CacheSlot(i, Enum.SpellBookSpellBank.Pet)
        end
    end

    spellbookCacheBuilt = true
end

-- Invalidate the spellbook cache (call on spec change or SPELLS_CHANGED)
function SpellSearch.InvalidateSpellbookCache()
    wipe(spellbookCache)
    spellbookCacheBuilt = false
end

-------------------------------------------------------------------------------
-- Private: fill `results` with matching spellbook entries.
-- Returns true if an exact numeric ID was matched (caller should return early).
-------------------------------------------------------------------------------
local function SearchSpells(filter, filterLower, excluded, results)
    local filterAsID = tonumber(filter)
    if filterAsID and filterAsID > 0 and not excluded[filterAsID] then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(filterAsID)
        if spellInfo and spellInfo.name then
            results[filterAsID] = spellInfo.name .. " (ID: " .. filterAsID .. ")"
            return true
        end
    end
    local count = 0
    for spellID, info in pairs(spellbookCache) do
        if not excluded[spellID] then
            if info.nameLower:find(filterLower, 1, true) or info.idStr:find(filter, 1, true) then
                results[spellID] = info.name .. " (" .. info.idStr .. ")"
                count = count + 1
                if count >= 15 then break end
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Get filtered results: spells from spellbook + items from equipped slots,
-- action bars, and bags. Returns combined table:
--   positive key = spellID, negative key = -itemID
-- Used by panels that accept both spells and items (defensive lists).
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredResults(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()

    if filter == "" or #filter < 2 then return results end

    local excluded = {}
    if excludeList then
        for _, entry in ipairs(excludeList) do excluded[entry] = true end
    end

    if SearchSpells(filter, filterLower, excluded, results) then return results end

    -- ── Items ─────────────────────────────────────────────────────────────────

    local itemPrefixID = filter:match("^[iI]tem:(%d+)$")
    local seen = {}
    local itemCount = 0
    local MAX_ITEMS = 10

    local function TryAddItem(itemID)
        if itemCount >= MAX_ITEMS or seen[itemID] or excluded[-itemID] then return end
        local itemName = C_Item.GetItemInfo(itemID)
        if not itemName then return end
        local matched
        if itemPrefixID then
            matched = tostring(itemID) == itemPrefixID
        else
            matched = itemName:lower():find(filterLower, 1, true) or tostring(itemID):find(filter, 1, true)
        end
        if matched then
            seen[itemID] = true
            results[-itemID] = "|cff00ccff" .. itemName .. "|r (item:" .. itemID .. ")"
            itemCount = itemCount + 1
        end
    end

    -- Source 1: Equipped gear slots (trinkets, on-use items, etc.)
    for slot = 1, 19 do
        if itemCount >= MAX_ITEMS then break end
        local itemID = GetInventoryItemID("player", slot)
        if itemID then TryAddItem(itemID) end
    end

    -- Source 2: Action bar slots
    for slot = 1, 180 do
        if itemCount >= MAX_ITEMS then break end
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then TryAddItem(id) end
    end

    -- Source 3: Bags (backpack + 4 bags)
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            if itemCount >= MAX_ITEMS then break end
            local numSlots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                if itemCount >= MAX_ITEMS then break end
                local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                if containerInfo and containerInfo.itemID then TryAddItem(containerInfo.itemID) end
            end
        end
    end

    return results
end

-------------------------------------------------------------------------------
-- Spells-only search - for panels where items are not applicable
-- (gap-closers, burst triggers).
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredSpellbookSpells(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()

    if filter == "" or #filter < 2 then return results end

    local excluded = {}
    if excludeList then
        for _, spellID in ipairs(excludeList) do excluded[spellID] = true end
    end

    SearchSpells(filter, filterLower, excluded, results)
    return results
end

-------------------------------------------------------------------------------
-- Aura search - returns active player buffs for linking to items.
-- Empty/short text → all active buffs. Text input → filter by name or spell ID.
-- Returns {[spellID] = "Aura Name (ID: 12345)"} - positive keys (auras are spells).
-------------------------------------------------------------------------------
function SpellSearch.GetFilteredPlayerAuras(filterText, excludeList)
    local results = {}
    local filter = (filterText or ""):trim()
    local filterLower = filter:lower()
    local filterAsNumber = tonumber(filter)

    local excluded = {}
    if excludeList then
        for _, id in ipairs(excludeList) do excluded[id] = true end
    end

    -- Scan active player buffs
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not data then break end
            local spellId = data.spellId
            local name = data.name
            if spellId and name and not excluded[spellId] then
                local isSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and (BlizzardAPI.IsSecretValue(spellId) or BlizzardAPI.IsSecretValue(name))
                if not isSecret then
                    local match = false
                    if filter == "" or #filter < 2 then
                        match = true  -- show all active buffs on empty search
                    elseif name:lower():find(filterLower, 1, true) then
                        match = true
                    elseif filterAsNumber and spellId == filterAsNumber then
                        match = true
                    end
                    if match then
                        results[spellId] = name .. " |cff888888(ID: " .. spellId .. ")|r"
                    end
                end
            end
        end
    end

    -- Allow direct spellID entry even if not currently active
    if filterAsNumber and filterAsNumber > 0 and not results[filterAsNumber] and not excluded[filterAsNumber] then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(filterAsNumber)
        if info and info.name then
            results[filterAsNumber] = info.name .. " |cffff8800(not active)|r |cff888888(ID: " .. filterAsNumber .. ")|r"
        end
    end

    return results
end

-------------------------------------------------------------------------------
-- Helper to clear dynamic (non-static) keys from an AceConfig args table.
-- staticKeys: {key = true, ...} set of keys to preserve.
-- Avoids allocating a per-call table by using a two-pass collect-then-nil pattern.
-------------------------------------------------------------------------------
function SpellSearch.ClearDynamicArgs(argsTable, staticKeys)
    local keysToClear = {}
    for key, _ in pairs(argsTable) do
        if not staticKeys[key] then
            keysToClear[#keysToClear + 1] = key
        end
    end
    for _, key in ipairs(keysToClear) do
        argsTable[key] = nil
    end
end

-------------------------------------------------------------------------------
-- Strip UI color escapes (|cAARRGGBB ... |r) so display names sort by their
-- visible text. Returns a single value (the gsub match count is discarded).
-------------------------------------------------------------------------------
function SpellSearch.StripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-------------------------------------------------------------------------------
-- Returns a name-function for a class-colored, spec-suffixed inline header.
-- label: already-localized middle text, e.g. L["Defensive Priority List"].
-------------------------------------------------------------------------------
function SpellSearch.SpecHeader(label)
    return function()
        local className, playerClass = UnitClass("player")
        local classColor = playerClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[playerClass]
        local colorCode = (classColor and classColor.colorStr) or "FFFFFFFF"
        local specIndex = GetSpecialization and GetSpecialization()
        local specName
        if specIndex then
            local _, name = GetSpecializationInfo(specIndex)
            specName = name
        end
        return "|c" .. colorCode .. (className or L["Unknown"]) .. "|r " .. label .. " (" .. (specName or "?") .. ")"
    end
end

-------------------------------------------------------------------------------
-- Helper to add a spell or item to a list (used by both dropdown and manual input)
-- Positive ID = spell, negative ID = item (stored as -itemID in the list)
-------------------------------------------------------------------------------
function SpellSearch.AddSpellToList(addon, spellList, id)
    if not spellList then return false end
    if not id or id == 0 then return false end

    -- Upkeep abilities (poisons, weapon imbues, long raid buffs) must never enter a
    -- priority list. Out of combat the game reveals its buff demands ONE at a time and
    -- holds every other pick until each is applied, so a list that owns the order sits on
    -- the first one and the queue stops moving. The pre-combat reminder offers them
    -- instead, which does not block anything.
    local RF = LibStub("JustAC-RedundancyFilter", true)
    if id > 0 and RF and RF.IsUpkeepSpell and RF.IsUpkeepSpell(id) then
        local info = BlizzardAPI.GetCachedSpellInfo(id)
        addon:Print(string.format(L["Upkeep Not Listable"], (info and info.name) or tostring(id)))
        return false
    end

    if id < 0 then
        -- Item entry: validate item exists
        local itemID = -id
        local itemName = C_Item.GetItemInfo(itemID)
        if not itemName then
            addon:Print("Invalid item ID: " .. itemID .. " (item not found or not cached)")
            return false
        end

        -- Check if already in list
        for _, existingID in ipairs(spellList) do
            if existingID == id then
                addon:Print("Item already in list: " .. itemName)
                return false
            end
        end

        table.insert(spellList, id)
        addon:Print("Added item: " .. itemName)
        return true
    end

    -- Positive ID: spell entry (original behavior)
    -- Validate spell exists
    local spellInfo = BlizzardAPI.GetCachedSpellInfo(id)
    if not spellInfo or not spellInfo.name then
        addon:Print("Invalid spell ID: " .. id .. " (spell not found)")
        return false
    end

    -- Check if already in list
    for _, existingID in ipairs(spellList) do
        if existingID == id then
            addon:Print("Spell already in list: " .. spellInfo.name)
            return false
        end
    end

    table.insert(spellList, id)
    addon:Print("Added: " .. spellInfo.name)
    return true
end

-------------------------------------------------------------------------------
-- Curated role for a spell, as a colored short tag plus a family bucket:
-- "defensive" (defensive/heal tables), "offensive" (SpellDB's fail-open default),
-- or "both" for the ambiguous middle - Disruption (CC/interrupt) and Utility keep
-- their own tag but belong to BOTH families, so nothing warns or reorders against
-- them. Items return nil - their role is context-specific. Display guidance only;
-- nothing gates on it.
-------------------------------------------------------------------------------
function SpellSearch.RoleTag(id)
    if not id or id < 0 or not SpellDB then return nil end
    if (SpellDB.IsDefensiveSpell and SpellDB.IsDefensiveSpell(id))
       or (SpellDB.IsHealingSpell and SpellDB.IsHealingSpell(id)) then
        return "|cff2ecc71" .. L["Role Defensive"] .. "|r", "defensive"
    end
    if (SpellDB.IsCrowdControlSpell and SpellDB.IsCrowdControlSpell(id))
       or (SpellDB.IsInterruptTypeSpell and SpellDB.IsInterruptTypeSpell(id)) then
        return "|cff4fc3f7" .. L["Disruption"] .. "|r", "both"
    end
    if SpellDB.IsOffensiveSpell and not SpellDB.IsOffensiveSpell(id) then
        return "|cff9e9e9e" .. L["Role Utility"] .. "|r", "both"
    end
    return "|cffff9966" .. L["Role Offensive"] .. "|r", "offensive"
end

-------------------------------------------------------------------------------
-- Resolve a signed list entry to its display name and icon: positive = spell,
-- negative = item. Either return may be nil when the record is not cached;
-- callers supply their own fallback text and icon.
-------------------------------------------------------------------------------
function SpellSearch.DisplayInfo(id)
    if id < 0 then
        local itemID = -id
        local itemName, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
        if not itemTexture and C_Item and C_Item.GetItemIconByID then
            itemTexture = C_Item.GetItemIconByID(itemID)
        end
        return itemName, itemTexture
    end
    local info = (BlizzardAPI and BlizzardAPI.GetCachedSpellInfo(id))
        or (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id))
    if not info then return end
    -- A form listed by itself is inactive most of the time; say so, or the row reads as broken.
    local base = SpellDB and SpellDB.GetTransformBase and SpellDB.GetTransformBase(id)
    local baseInfo = base and BlizzardAPI and BlizzardAPI.GetCachedSpellInfo(base)
    if baseInfo and baseInfo.name then
        return string.format("%s  |cff888888(%s)|r", info.name,
            string.format(L["Transform While"], baseInfo.name)), info.iconID
    end
    return info.name, info.iconID
end

-- ── "Hold Until" dial (shared by the Custom Queue rows and the ability card) ──
-- One dropdown, values shaped by what the spell actually has: "Fully charged"
-- always (a chargeless spell holds until off cooldown), point steps for a
-- discrete cost row, percent steps for a continuous one. Stored sparse as
-- spellSettings[id].holdMode = "charged" | "pts:N" | "pct:N"; the legacy
-- holdUntilCharged boolean reads as "charged" until the dial is next touched.
local HOLD_PCT_STEPS = { 20, 40, 60, 80 }
-- Static per-type point caps for the dropdown; the queue clamps a stored value
-- to the LIVE max at evaluation time, so over-offering here can never strand a
-- hold on a lower-max build.
local HOLD_PTS_CAP = {}
do
    local PT = Enum and Enum.PowerType
    if PT then
        local caps = { ComboPoints = 7, Runes = 6, SoulShards = 5, HolyPower = 5,
                       Chi = 6, ArcaneCharges = 4, Essence = 6 }
        for k, cap in pairs(caps) do
            if PT[k] then HOLD_PTS_CAP[PT[k]] = cap end
        end
    end
end

local function HoldModeOptions(spellID)
    local values = { off = L["Hold Off Label"], charged = L["Hold Charged Label"] }
    local sorting = { "off", "charged" }
    local SQ = LibStub("JustAC-SpellQueue", true)
    local kind, ptype, resName
    if SQ and SQ.GetHoldResource then kind, ptype, resName = SQ.GetHoldResource(spellID) end
    if kind == "pts" then
        for n = 2, HOLD_PTS_CAP[ptype] or 5 do
            local key = "pts:" .. n
            values[key] = n .. "+ " .. (resName or "")
            sorting[#sorting + 1] = key
        end
    elseif kind == "pct" then
        for i = 1, #HOLD_PCT_STEPS do
            local n = HOLD_PCT_STEPS[i]
            local key = "pct:" .. n
            values[key] = n .. "% " .. (resName or "")
            sorting[#sorting + 1] = key
        end
    end
    return values, sorting
end

--- One spell's Hold Until dial, as a settings-strip control. `extraDisabled` (optional)
--- ORs onto the shared "Unavailable last is off" greying; `onChange` (optional) runs after a
--- pick, for a surface that has to redraw itself.
function SpellSearch.HoldModeControl(addon, spellID, extraDisabled, onChange)
    return {
        type = "select",
        name = L["Hold Until"],
        desc = L["Hold Until desc"],
        disabled = function()
            local profile = addon:GetProfile()
            if profile and profile.orderSinkCooldowns == false then return true end
            -- A hidden ability never reaches positions 2+, so its dial is inert:
            -- grey it while this spec's visibility override (or an inactive
            -- situational set) hides the spell from the queue.
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.IsSpellBlacklisted and SQ.IsSpellBlacklisted(spellID) then return true end
            return extraDisabled and extraDisabled() or false
        end,
        values = function()
            local v = HoldModeOptions(spellID)
            -- A stored value the spell no longer offers (a respec changed its
            -- cost shape) must still render on the closed dropdown, not a blank.
            local profile = addon:GetProfile()
            local ss = profile and profile.defensives and profile.defensives.spellSettings
                and profile.defensives.spellSettings[spellID]
            local cur = ss and ss.holdMode
            if cur and not v[cur] then v[cur] = cur end
            return v
        end,
        sorting = function() local _, s = HoldModeOptions(spellID); return s end,
        get = function()
            local profile = addon:GetProfile()
            local s = profile and profile.defensives and profile.defensives.spellSettings
                and profile.defensives.spellSettings[spellID]
            local m = s and s.holdMode
            if m == nil and s and s.holdUntilCharged == true then m = "charged" end
            return m or "off"
        end,
        set = function(_, val)
            local profile = addon:GetProfile()
            if not profile or not profile.defensives then return end
            if not profile.defensives.spellSettings then profile.defensives.spellSettings = {} end
            local store = profile.defensives.spellSettings
            if not store[spellID] then store[spellID] = {} end
            local s = store[spellID]
            s.holdMode = (val ~= "off") and val or nil
            s.holdUntilCharged = nil   -- superseded by holdMode
            if not next(s) then store[spellID] = nil end
            -- Dials are read into the rotation SETUP cache, which only rebuilds
            -- on a list change - invalidate so the pick applies on the next build.
            local SQ = LibStub("JustAC-SpellQueue", true)
            if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
            addon:ForceUpdate()
            if onChange then onChange() end
        end,
    }
end
