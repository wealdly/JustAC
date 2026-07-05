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
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local IsPlayerSpell = IsPlayerSpell or IsSpellKnown

-- Offer Recuperate while player health is below this (exact read, OOC only)
local RECUPERATE_HEALTH_PCT = 90

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
        -- 12.0.7: some aura spellIds are secret even out of combat; a secret table
        -- key throws, so skip those auras (their identity is unknowable here).
        if aura.spellId and not (issecretvalue and issecretvalue(aura.spellId))
           and buffSet[aura.spellId] then return true end
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
    -- 12.0.7: in aura-restricted contexts (PvP instances - restriction is per-context,
    -- not per-combat) every aura reads as secret, so nothing can be verified. Report
    -- satisfied so we never nag someone to re-consume a buff they may already have.
    -- NeverSecret predicate; false in normal content keeps this a no-op.
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return true
    end
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
    -- 12.0.7: in aura-restricted contexts the by-ID probe returns nil for secret-flagged
    -- auras (RequiresNonSecretAura), so every class buff would look lapsed - offer nothing.
    local restricted = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
    if groups and get and not restricted then
        for _, grp in ipairs(groups) do
            local active, aura
            for _, spellID in ipairs(grp.group) do
                if IsPlayerSpell(spellID) then
                    local a = get(spellID)
                    if a then active, aura = spellID, a; break end
                end
            end
            if active then
                -- 12.0.7: aura timing can be secret even out of combat (arithmetic on a
                -- secret throws). Secret timing = buff is up but the refresh window is
                -- unknowable - suggest nothing rather than a premature refresh.
                local dur, exp = aura.duration, aura.expirationTime
                if not (issecretvalue and (issecretvalue(dur) or issecretvalue(exp))) then
                    dur = dur or 0
                    local rem = (exp or 0) - now
                    if dur > 0 and rem <= dur * CLASS_BUFF_REFRESH_FRACTION then out[#out + 1] = active end
                end
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
    -- Recuperate (cross-class OOC self-heal): a maintained buff whose "missing"
    -- condition is health-based instead of aura-expiry - offer it while the player
    -- is below the comfortable threshold and its heal-over-time isn't running.
    -- (1231411 also applies its own 30s active aura, hence the second probe.)
    -- A procced heal (free instant Regrowth and the like) is the better way to
    -- top up after combat and already surfaces with its proc glow - step aside.
    local function HasProccedHeal()
        local ABS = LibStub("JustAC-ActionBarScanner", true)
        local procs = ABS and ABS.GetDefensiveProccedSpells and ABS.GetDefensiveProccedSpells()
        if not procs or not SpellDB.IsHealingSpell then return false end
        for i = 1, #procs do
            if SpellDB.IsHealingSpell(procs[i]) then return true end
        end
        return false
    end
    -- Known-check: general "All Classes" skill-line spells can fail IsPlayerSpell
    -- even when learned, so fall back to IsSpellKnown/IsSpellKnownOrOverridesKnown.
    local recupKnown = SpellDB and SpellDB.RECUPERATE and (
        IsPlayerSpell(SpellDB.RECUPERATE)
        or (IsSpellKnown and IsSpellKnown(SpellDB.RECUPERATE))
        or (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(SpellDB.RECUPERATE)))
    -- Gate on the HoT (1231418) ONLY - deliberately not the 30s active aura
    -- (1231411): a damage tick interrupts the heal but leaves the active aura
    -- (and its animation) running, and that is exactly when a re-cast must be
    -- offered. The click layer cancels the stale aura before re-casting.
    if not InCombatLockdown() and not restricted and get and recupKnown
        and not get(SpellDB.RECUPERATE_AURA) then
        -- Hurt detection, layered by what 12.0.7 lets us read:
        --   1. exact health percent when readable -> offer below the threshold
        --   2. low-health vignette (never secret)  -> definitely hurt
        --   3. player UNIT_HEALTH event activity   -> OOC regen is ticking, so
        --      health is below full even when the value itself is secret
        local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
        local hurt = false
        if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
            local pct, estimated = BlizzardAPI.GetPlayerHealthPercentSafe()
            if pct and pct < RECUPERATE_HEALTH_PCT then
                hurt = true
            elseif estimated and BlizzardAPI.HasSustainedPlayerHealthActivity
                and BlizzardAPI.HasSustainedPlayerHealthActivity() then
                -- Sustained (not just recent) activity: a couple of scratch-repair
                -- ticks at near-full must not summon a 30s heal suggestion.
                hurt = true
            end
        end
        if hurt and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
            and not HasProccedHeal() then
            -- Prefer the class's own cheap heal (spammable; resource regens OOC).
            -- Ready-check via the local cooldown tracker (never secret); usability
            -- fails OPEN because resource state can be secret even out of combat -
            -- worst case an out-of-mana click errors and mana is back in seconds.
            local heal = SpellDB.GetKnownTopoffHeal and SpellDB.GetKnownTopoffHeal()
            local BAPI = LibStub("JustAC-BlizzardAPI", true)
            if heal and get(heal) then
                -- The chosen heal's own HoT is still ticking: the player IS being
                -- healed - suggest nothing (mirrors the Recuperate aura gate, and
                -- prevents the HoT's own no-change snapshots at full health from
                -- keeping the suggestion alive).
            elseif heal and BAPI
                and (not BAPI.IsSpellUsable or BAPI.IsSpellUsable(heal, true))
                and (not BAPI.IsSpellReady or BAPI.IsSpellReady(heal)) then
                out[#out + 1] = heal
            else
                out[#out + 1] = SpellDB.RECUPERATE
            end
        end
    end
    cachedClassBuffs, cachedClassBuffsAt = out, now
    return out
end
