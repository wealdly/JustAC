-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- PrecombatEngine.lua - Out-of-combat buff checklist. Detects pre-combat buffs (flask,
-- food, augment rune, weapon enchant) the player is missing AND owns something to fix.
-- Detection is aura-based and runs only out of combat, so it never touches the 12.0
-- secret-value wall (auras and item counts are plain values out of combat).

local PrecombatEngine = LibStub:NewLibrary("JustAC-PrecombatEngine", 1)
if not PrecombatEngine then return end

local SpellDB = LibStub("JustAC-SpellDB", true)

local InCombatLockdown = InCombatLockdown
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local C_UnitAuras = C_UnitAuras
local ipairs = ipairs
local GetTime = GetTime
local type = type
local UnitClass = UnitClass
local IsPlayerSpell = IsPlayerSpell or IsSpellKnown

-- True if the player currently has any aura whose spellId is in the set. Iterates the
-- player's helpful auras (usually < 40), so cost is independent of how big the set is -
-- which matters because the food set can hold a few hundred Well Fed buff ids.
local function HasAnyAura(buffSet)
    if not buffSet or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return false
    end
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then return false end
        if aura.spellId and buffSet[aura.spellId] then return true end
        i = i + 1
    end
end

-- The weapon imbue the player knows (in preference order), or nil. Shaman only - IsPlayerSpell
-- gates and separates specs (Enhancement -> Windfury, Resto -> Earthliving). Imbues are weapon
-- ENCHANTS, so they're detected/suggested off the weapon (GetWeaponEnchantInfo), not auras.
local function KnownWeaponImbue()
    local list = SpellDB and SpellDB.WEAPON_IMBUE_SPELLS
    if not list then return nil end
    for i = 1, #list do
        if IsPlayerSpell(list[i]) then return list[i] end
    end
    return nil
end

--- Is the buff category already satisfied? Weapon enchant is read off the weapon (temp
--- enchant); every other category from the player's auras. Out of combat only.
function PrecombatEngine.IsCategorySatisfied(category)
    if category == "weaponEnchant" then
        local hasMainHand = GetWeaponEnchantInfo and GetWeaponEnchantInfo()
        return hasMainHand and true or false
    end
    local set = SpellDB and SpellDB.GetPrecombatBuffSet and SpellDB.GetPrecombatBuffSet(category)
    return HasAnyAura(set)
end

--- Pre-combat buffs the player is missing AND can fix right now:
--- { {category=, entry=}, ... } - the best owned entry per enabled, unsatisfied category.
--- Out of combat only (returns empty in combat; buffs can't be applied there anyway). A
--- category only appears if the player actually OWNS something that satisfies it.
--- `settings` (optional), keyed by category:
---   settings[category] = false             -> category disabled
---   settings[category] = "haste"/"crit"/…  -> stat preference for the best-owned pick
function PrecombatEngine.GetMissingBuffs(settings)
    local out = {}
    if InCombatLockdown() then return out end
    if not SpellDB or not SpellDB.GetPrecombatBuffCategories then return out end
    for _, category in ipairs(SpellDB.GetPrecombatBuffCategories()) do
        -- An imbue-using class (Enhancement shaman) fills the main-hand enchant slot with its
        -- weapon imbue, so never suggest a weapon oil for it - the imbue is offered instead by
        -- GetMissingClassBuffs (and an oil would just overwrite the imbue anyway).
        local skip = category == "weaponEnchant" and KnownWeaponImbue() ~= nil
        local pref = settings and settings[category]
        if not skip and pref ~= false and not PrecombatEngine.IsCategorySatisfied(category) then
            local entry = SpellDB.GetBestOwnedBuff(category,
                type(pref) == "string" and pref or nil)
            if entry then
                out[#out + 1] = { category = category, entry = entry }
            end
        end
    end
    return out
end

--- Just the bag-item IDs to insert at the front of the defensive queue, in category order
--- (bag items only; toys/spells are handled elsewhere). Out of combat only.
---
--- Cached for a short window: the defensive queue rebuilds up to ~10x/s, but this scans
--- every buff item (GetItemCount) + aura state, which only changes on bag/aura/gear events.
--- A 0.5s expiry caps the full scan at ~2x/s and still reflects changes within half a
--- second. (In combat the queue insertion is skipped entirely, so the cache is OOC-only.)
local cachedItems, cachedItemsAt = nil, -1
local cachedClassBuffs, cachedClassBuffsAt = nil, -1
function PrecombatEngine.GetMissingBuffItems(settings)
    local now = GetTime()
    if cachedItems and (now - cachedItemsAt) < 0.5 then
        return cachedItems
    end
    local out = {}
    for _, m in ipairs(PrecombatEngine.GetMissingBuffs(settings)) do
        if (m.entry.source or "item") == "item" then
            out[#out + 1] = m.entry.id
        end
    end
    cachedItems, cachedItemsAt = out, now
    return out
end

--- Drop the cache so the next query recomputes immediately (call on options changes).
function PrecombatEngine.ClearCache()
    cachedItemsAt = -1
    cachedClassBuffsAt = -1
end

-- Class maintained buffs (poisons, imbues) that need (re)applying, as spell IDs. For each
-- group we find the option that's currently ACTIVE and re-suggest it once it drops past the
-- halfway point of its duration (refresh with plenty of margin, and useful for short buffs
-- too); if none is up we fall back to the group's default. Only spells the player knows
-- (IsPlayerSpell) surface, so it self-gates by class. Out of combat only; cached.
local CLASS_BUFF_REFRESH_FRACTION = 0.5  -- prompt to refresh once remaining < this * duration

-- Highest-priority member of `group` that the current rotation/fixed queue wants, or nil.
-- Used as the preferred pick when a maintained buff is missing entirely: offer the poison
-- the SBA/fixed queue is actually trying to apply instead of a blind default. Best-effort
-- only - position 1 of the queue is Blizzard's 12.0 secret suggestion, which can't be
-- compared (a raw `==` throws), so secret entries are skipped. Returns the known group
-- constant (never a queue value) and only one the player knows, so it can NEVER suppress
-- the reliable default fallback at the call site.
local issecretvalue = issecretvalue
local function HighestQueuedInGroup(group)
    local SQ = LibStub("JustAC-SpellQueue", true)
    local queue = SQ and SQ.GetCurrentSpellQueue and SQ.GetCurrentSpellQueue()
    if type(queue) ~= "table" then return nil end
    for i = 1, #queue do
        local q = queue[i]
        if not (issecretvalue and issecretvalue(q)) then
            for j = 1, #group do
                if q == group[j] and IsPlayerSpell(group[j]) then return group[j] end
            end
        end
    end
    return nil
end

function PrecombatEngine.GetMissingClassBuffs()
    local now = GetTime()
    if cachedClassBuffs and (now - cachedClassBuffsAt) < 0.5 then
        return cachedClassBuffs
    end
    local out = {}
    local groups = (not InCombatLockdown()) and SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS
    local class = groups and select(2, UnitClass("player"))
    groups = class and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if groups and get then
        for _, grp in ipairs(groups) do
            local active, aura
            for _, spellID in ipairs(grp.group) do
                if IsPlayerSpell(spellID) then
                    local a = get(spellID)
                    if a then active, aura = spellID, a; break end
                end
            end
            if active then
                local dur = aura.duration or 0
                local rem = (aura.expirationTime or 0) - now
                if dur > 0 and rem <= dur * CLASS_BUFF_REFRESH_FRACTION then out[#out + 1] = active end
            else
                -- Missing entirely (lapsed/cancelled): offer what the fixed queue ranks
                -- highest in this group, else the group's own default. Each group resolves
                -- independently, so a rogue with neither lethal nor non-lethal up gets both.
                local pick = HighestQueuedInGroup(grp.group) or grp.default
                if pick and IsPlayerSpell(pick) then out[#out + 1] = pick end
            end
        end
    end
    -- Weapon imbue (Enhancement shaman): a temp weapon ENCHANT, not a player aura, so it can't
    -- ride the group loop above. Suggest the known imbue while the main hand is bare. Mirrors
    -- IsCategorySatisfied's weapon read; GetWeaponEnchantInfo's first return is a plain OOC value.
    if not InCombatLockdown() then
        local imbue = KnownWeaponImbue()
        if imbue then
            local hasMainHand = GetWeaponEnchantInfo and GetWeaponEnchantInfo()
            if not hasMainHand then out[#out + 1] = imbue end
        end
    end
    cachedClassBuffs, cachedClassBuffsAt = out, now
    return out
end
