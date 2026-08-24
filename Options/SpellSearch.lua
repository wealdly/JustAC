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
-- Used by panels that accept both spells and items (defensive lists, blacklist).
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
        local itemName = GetItemInfo(itemID)
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
-- (gap-closers, hotkeys, melee range override).
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

    if id < 0 then
        -- Item entry: validate item exists
        local itemID = -id
        local itemName = GetItemInfo(itemID)
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
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
        if not itemTexture and C_Item and C_Item.GetItemIconByID then
            itemTexture = C_Item.GetItemIconByID(itemID)
        end
        return itemName, itemTexture
    end
    local info = (BlizzardAPI and BlizzardAPI.GetCachedSpellInfo(id))
        or (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id))
    if info then return info.name, info.iconID end
end

-------------------------------------------------------------------------------
-- Helper to create spell list entries for a given list (defensives/etc.)
-------------------------------------------------------------------------------
-- Lists whose engines actually read defensives.spellSettings[id].procPriority
-- (DefensiveEngine for the defensive/pet lists, SpellQueue for the custom queue).
-- Other lists must neither show the toggle nor wipe the setting on removal.
local PROC_PRIORITY_LISTS = { defensive = true, petheal = true, petrez = true, customqueue = true }

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

--- The full AceConfig select for one spell's Hold Until dial. `extraDisabled`
--- (optional) ORs onto the shared "Unavailable last is off" greying.
function SpellSearch.HoldModeControl(addon, spellID, order, width, extraDisabled)
    return {
        type = "select",
        order = order,
        width = width or 1.0,
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
        end,
    }
end

-- Every row button below closes over the index it was BUILT with. If the list changed
-- since - another row acted, defaults were restored, the spec swapped - that index now
-- points at a different entry, or past the end. Re-checking that the captured entry is
-- still sitting at the captured index makes acting on a stale row a no-op instead of a
-- silent edit to the wrong one. Shared by every list this builds (defensives, pet lists,
-- gap-closers, custom queue), so the guard lands once for all of them.
local function StillAt(list, i, entry)
    return list and i and list[i] == entry
end

function SpellSearch.CreateSpellListEntries(_addon, defensivesArgs, spellList, listType, baseOrder, updateFunc)
    if not spellList then return end

    for i, entry in ipairs(spellList) do
        local isEmergency = listType == "defensive" and SpellDB and SpellDB.EMERGENCY_POTION
            and entry == SpellDB.EMERGENCY_POTION
        local isItemEntry = (not isEmergency) and (entry < 0)
        local displayName, displayIcon, cooldownInfo

        if isEmergency then
            local p = _addon:GetProfile()
            local choice = (p and p.defensives and p.defensives.emergencyPotionChoice) or 0
            local label
            if choice == -1 then
                label = "|cff888888" .. (L["Emergency Potion Off"] or "Off") .. "|r"
            elseif choice > 0 then
                label = (GetItemInfo(choice)) or ("Item " .. choice)
            else
                local bestID = SpellDB.GetBestHealingItem and SpellDB.GetBestHealingItem()
                local bestName = bestID and (GetItemInfo(bestID))
                if bestName then
                    label = (L["Auto"] or "Auto") .. ": " .. bestName
                else
                    label = (L["Auto best owned"] or "Auto (best owned)")
                end
            end
            displayName = (L["Emergency Potion"] or "Emergency Potion") .. " |cff00ccff(" .. label .. ")|r"
            displayIcon = 134832
            cooldownInfo = ""
        elseif isItemEntry then
            -- Negative entry = item ID
            local itemName, itemIcon = SpellSearch.DisplayInfo(entry)
            displayName = itemName and (itemName .. " |cff00ccff[Item]|r") or ("Item " .. -entry)
            displayIcon = itemIcon or 134400
            cooldownInfo = ""
        else
            -- Positive entry = spell ID
            local spellName, spellIcon = SpellSearch.DisplayInfo(entry)
            displayName = spellName or ("Spell " .. entry)
            displayIcon = spellIcon or 134400
            cooldownInfo = ""
            if spellName and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(entry)
                local duration = cdInfo and cdInfo.duration
                local isSecret = BlizzardAPI.IsSecretValue(duration)
                if duration and not isSecret and duration > 1.5 then
                    cooldownInfo = " |cff888888(" .. math.floor(duration) .. "s)|r"
                end
            end
        end
        
        defensivesArgs[listType .. "_" .. i] = {
            type = "group",
            name = i .. ". |T" .. displayIcon .. ":16:16:0:0|t " .. displayName .. cooldownInfo,
            inline = true,
            order = baseOrder + (i * 0.1),
            args = {
                moveUp = {
                    type = "execute",
                    name = L["Up"],
                    desc = L["Move up desc"],
                    order = 1,
                    width = 0.3,
                    disabled = function() return i == 1 end,
                    func = function()
                        if not StillAt(spellList, i, entry) or i <= 1 then return end
                        spellList[i - 1], spellList[i] = spellList[i], spellList[i - 1]
                        updateFunc()
                    end
                },
                moveDown = {
                    type = "execute",
                    name = L["Dn"],
                    desc = L["Move down desc"],
                    order = 2,
                    width = 0.3,
                    disabled = function() return i == #spellList end,
                    func = function()
                        -- The bounds test is the real guard, not `disabled`: that closure
                        -- compares a build-time index against a live length, so a tree the
                        -- dialog has not refreshed yet can enable this on the LAST row. The
                        -- swap would then read a nil neighbour and write nil back into
                        -- spellList[i] - a HOLE, which truncates every later entry at save
                        -- time. The Emergency Potion tile is appended last, so it is always
                        -- the first thing such a hole eats.
                        if not StillAt(spellList, i, entry) or i >= #spellList then return end
                        spellList[i + 1], spellList[i] = spellList[i], spellList[i + 1]
                        updateFunc()
                    end
                },
                remove = {
                    type = "execute",
                    name = L["Remove"],
                    -- Far right, after the per-ability settings: the destructive
                    -- control sits away from the reorder pair it used to neighbor.
                    order = 9,
                    width = 0.5,
                    func = function()
                        if not StillAt(spellList, i, entry) then return end
                        if isEmergency then
                            -- Record the intent, so the tile stays gone. Everything else
                            -- that can drop it is treated as accidental and re-seeded.
                            local DE = LibStub("JustAC-DefensiveEngine", true)
                            if DE and DE.MarkEmergencyPotionRemoved then
                                DE.MarkEmergencyPotionRemoved(_addon)
                            end
                        end
                        -- Deliberately NOT wiping the entry's spell/item settings: both
                        -- stores are shared across lists AND specs, so no removal event
                        -- can soundly decide ownership - clearing here discarded a Hold
                        -- Until dial or pin another list/spec still used. Settings are
                        -- ability-level properties, effective while the ability is in a
                        -- list; orphans are inert (the queue and defensive engine only
                        -- consult them for listed entries) and stay visible on the
                        -- Abilities tab, which owns editing and resetting them.
                        table.remove(spellList, i)
                        updateFunc()
                    end
                }
            }
        }

        -- Emergency Potion tile: a dropdown to pick which pot it fires (or turn it off).
        if isEmergency then
            local entryArgs = defensivesArgs[listType .. "_" .. i].args
            entryArgs.potion = {
                type = "select",
                name = L["Emergency Potion Use"] or "Use",
                desc = function()
                    local rule = L["Emergency Potion Auto Desc"]
                        or ("Auto fires the health item that restores the most at your "
                            .. "current maximum health, so a percentage potion is weighed "
                            .. "fairly against a fixed-amount one. Pick a specific potion "
                            .. "to override.")
                    local info = SpellDB and SpellDB.GetBestHealingItemInfo
                        and SpellDB.GetBestHealingItemInfo()
                    if not info then return rule end
                    local restores
                    if info.isPct then
                        restores = info.value .. "%"
                        if info.heal and info.heal > 0 then
                            restores = restores .. " (~" .. BreakUpLargeNumbers(math.floor(info.heal)) .. ")"
                        end
                    elseif info.value and info.value > 0 then
                        restores = "~" .. BreakUpLargeNumbers(info.value)
                    end
                    local best = "|cff00ff00" .. info.name .. "|r"
                    if restores then
                        best = best .. " - " .. restores .. " " .. (L["health"] or "health")
                    end
                    if info.owned > 1 then
                        best = best .. " (" .. (L["best of"] or "best of") .. " " .. info.owned .. ")"
                    end
                    return rule .. "\n\n" .. (L["Best in bags"] or "Best in bags") .. ": " .. best
                end,
                order = 0.5,
                width = "double",
                values = function()
                    local vals = {
                        [-1] = (L["Emergency Potion Off"] or "Off"),
                        [0]  = (L["Auto best owned"] or "Auto (best owned)"),
                    }
                    if SpellDB and SpellDB.GetOwnedHealingItems then
                        for _, it in ipairs(SpellDB.GetOwnedHealingItems()) do vals[it.id] = it.name end
                    end
                    return vals
                end,
                get = function()
                    local p = _addon:GetProfile()
                    return (p and p.defensives and p.defensives.emergencyPotionChoice) or 0
                end,
                set = function(_, v)
                    local p = _addon:GetProfile()
                    if p and p.defensives then p.defensives.emergencyPotionChoice = v end
                    updateFunc()
                end,
            }
        end

        -- Per-item controls: Link Aura + Hide in Combat
        if isItemEntry then
            local itemID = -entry
            local entryArgs = defensivesArgs[listType .. "_" .. i].args

            entryArgs.linkAura = {
                type = "execute",
                order = 4,
                width = 0.7,
                name = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
                    if settings and settings.linkedAura then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(settings.linkedAura)
                        local auraName = info and info.name or tostring(settings.linkedAura)
                        return L["Linked: %s"]:format(auraName)
                    end
                    return L["Link Aura..."]
                end,
                desc = L["Link Aura desc"],
                func = function()
                    local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
                    if not LiveSearchPopup then return end

                    LiveSearchPopup.Open({
                        title = L["Link Aura..."],
                        searchFunc = SpellSearch.GetFilteredPlayerAuras,
                        onSelect = function(auraSpellID, _)
                            local profile = _addon:GetProfile()
                            if not profile or not profile.defensives then return end
                            if not profile.defensives.itemSettings then profile.defensives.itemSettings = {} end
                            if not profile.defensives.itemSettings[itemID] then profile.defensives.itemSettings[itemID] = {} end
                            profile.defensives.itemSettings[itemID].linkedAura = auraSpellID
                            -- Default to hiding in combat when linking an aura
                            -- (item auras are almost certainly secret in combat)
                            if profile.defensives.itemSettings[itemID].combatHide == nil then
                                profile.defensives.itemSettings[itemID].combatHide = true
                            end
                            updateFunc()
                        end,
                    })
                end,
            }

            entryArgs.clearLink = {
                type = "execute",
                order = 5,
                width = 0.3,
                name = L["Clear Link"],
                desc = L["Clear Link desc"],
                hidden = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
                    return not (settings and settings.linkedAura)
                end,
                func = function()
                    local profile = _addon:GetProfile()
                    if profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID] then
                        profile.defensives.itemSettings[itemID].linkedAura = nil
                    end
                    updateFunc()
                end,
            }

            entryArgs.combatHide = {
                type = "toggle",
                order = 6,
                width = 0.7,
                name = L["Hide in Combat"],
                desc = L["Hide in Combat desc"],
                get = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.itemSettings and profile.defensives.itemSettings[itemID]
                    return settings and settings.combatHide or false
                end,
                set = function(_, val)
                    local profile = _addon:GetProfile()
                    if not profile or not profile.defensives then return end
                    if not profile.defensives.itemSettings then profile.defensives.itemSettings = {} end
                    if not profile.defensives.itemSettings[itemID] then profile.defensives.itemSettings[itemID] = {} end
                    profile.defensives.itemSettings[itemID].combatHide = val
                end,
            }
        end

        -- Per-spell controls: Proc Priority toggle (spells only, not items,
        -- and only on lists whose engine reads the setting)
        if not isItemEntry and PROC_PRIORITY_LISTS[listType] then
            local spellID = entry
            local entryArgs = defensivesArgs[listType .. "_" .. i].args

            entryArgs.procPriority = {
                type = "toggle",
                -- Custom-queue rows read position -> hold -> pin -> proc exception;
                -- the rarest decision goes last. Other lists keep the old slot.
                order = listType == "customqueue" and 6 or 4,
                width = 0.7,
                name = L["Proc Priority"],
                desc = L["Proc Priority desc"],
                -- In the Rotation (custom queue) list this only matters while the master
                -- "Procs first" toggle is on; grey it out otherwise. The defensives lists
                -- use a separate path (the defensive engine), so they're never gated here.
                disabled = listType == "customqueue" and function()
                    local profile = _addon:GetProfile()
                    return profile and profile.orderProcsFirst == false or false
                end or nil,
                get = function()
                    local profile = _addon:GetProfile()
                    local settings = profile and profile.defensives and profile.defensives.spellSettings and profile.defensives.spellSettings[spellID]
                    -- Default to true (procced spells jump to front by default)
                    return not settings or settings.procPriority ~= false
                end,
                set = function(_, val)
                    local profile = _addon:GetProfile()
                    if not profile or not profile.defensives then return end
                    if not profile.defensives.spellSettings then profile.defensives.spellSettings = {} end
                    if not profile.defensives.spellSettings[spellID] then profile.defensives.spellSettings[spellID] = {} end
                    profile.defensives.spellSettings[spellID].procPriority = val
                end,
            }

            -- Custom Queue only: pin the entry so filtering never hides it (active
            -- buff / running DoT). SpellQueue.AlwaysShowEnabled reads this key.
            if listType == "customqueue" then
                entryArgs.alwaysShow = {
                    type = "toggle",
                    order = 5,
                    width = 0.7,
                    name = L["Always Show"],
                    desc = L["Always Show desc"],
                    -- Same rule as the dial: inert while a visibility override
                    -- hides this spell from the queue, so grey it.
                    disabled = function()
                        local SQ = LibStub("JustAC-SpellQueue", true)
                        return (SQ and SQ.IsSpellBlacklisted and SQ.IsSpellBlacklisted(spellID)) or false
                    end,
                    get = function()
                        local profile = _addon:GetProfile()
                        local settings = profile and profile.defensives and profile.defensives.spellSettings
                            and profile.defensives.spellSettings[spellID]
                        return settings and settings.alwaysShow == true
                    end,
                    set = function(_, val)
                        local profile = _addon:GetProfile()
                        if not profile or not profile.defensives then return end
                        if not profile.defensives.spellSettings then profile.defensives.spellSettings = {} end
                        if not profile.defensives.spellSettings[spellID] then profile.defensives.spellSettings[spellID] = {} end
                        -- Store true or nil (default off) to keep the settings table sparse.
                        profile.defensives.spellSettings[spellID].alwaysShow = val or nil
                        -- The queue resolves pins into a cached set at list-rebuild time;
                        -- invalidate so the toggle applies on the next build.
                        local SQ = LibStub("JustAC-SpellQueue", true)
                        if SQ and SQ.InvalidateRotationCache then SQ.InvalidateRotationCache() end
                        _addon:ForceUpdate()
                    end,
                }

                entryArgs.holdMode = SpellSearch.HoldModeControl(_addon, spellID, 4)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Helper to create a single "Add..." button that opens the live-search popup.
-- spellsOnly = true  → spellbook only (gap-closers, hotkeys, melee range override)
-- spellsOnly = false → spellbook + inventory items (defensives, blacklist)
-------------------------------------------------------------------------------
function SpellSearch.CreateAddSpellButton(addon, argsTable, spellList, listType, order, listName, updateFunc, spellsOnly)
    SpellSearch.BuildSpellbookCache()

    argsTable["add_popup_" .. listType] = {
        type  = "execute",
        name  = L["Add"] .. " " .. listName .. "...",
        desc  = L["Search spell desc"],
        order = order,
        width = "normal",
        func  = function()
            if not spellList then return end
            local LiveSearchPopup = LibStub("JustAC-LiveSearchPopup", true)
            if not LiveSearchPopup then return end

            -- Snapshot the current list as exclusion set for the popup session
            local excludeList = {}
            for _, entry in ipairs(spellList) do
                excludeList[#excludeList + 1] = entry
            end

            local searchFunc = spellsOnly and SpellSearch.GetFilteredSpellbookSpells
                                          or  SpellSearch.GetFilteredResults

            LiveSearchPopup.Open({
                title       = L["Add"] .. " " .. listName,
                searchFunc  = searchFunc,
                excludeList = excludeList,
                onSelect    = function(id, _)
                    if SpellSearch.AddSpellToList(addon, spellList, id) then
                        updateFunc()
                    end
                end,
            })
        end,
    }
end

-------------------------------------------------------------------------------
-- Rebuild one dynamic spell-list section: optional empty-state note, then
-- list entries, then the "Add..." button. Caller clears dynamic args and
-- ensures the spec-keyed list table exists first; caller also does the final
-- AceConfigRegistry:NotifyChange.
-- opts: { spellList, listType, baseOrder, addOrder, listName, updateFunc,
--         spellsOnly, emptyText (optional) }
-------------------------------------------------------------------------------
function SpellSearch.RebuildListSection(addon, argsTable, opts)
    local spellList = opts.spellList
    if opts.emptyText and spellList and #spellList == 0 then
        argsTable.emptyNote = {
            type = "description",
            name = opts.emptyText,
            order = opts.baseOrder,
            fontSize = "medium",
        }
    end
    SpellSearch.CreateSpellListEntries(addon, argsTable, spellList, opts.listType, opts.baseOrder, opts.updateFunc)
    SpellSearch.CreateAddSpellButton(addon, argsTable, spellList, opts.listType, opts.addOrder, opts.listName, opts.updateFunc, opts.spellsOnly)
end
