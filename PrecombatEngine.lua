-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- PrecombatEngine.lua - Out-of-combat buff checklist. Detects pre-combat buffs (flask,
-- food, augment rune, weapon enchant) the player is missing AND owns something to fix.
-- Detection is aura-based and runs only out of combat, so it never touches the 12.0
-- secret-value wall (auras and item counts are plain values out of combat).

local PrecombatEngine = LibStub:NewLibrary("JustAC-PrecombatEngine", 7)
if not PrecombatEngine then return end

local SpellDB = LibStub("JustAC-SpellDB", true)
local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

local InCombatLockdown = InCombatLockdown
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local C_UnitAuras = C_UnitAuras
local ipairs = ipairs
local GetTime = GetTime
local type = type
local UnitClass = UnitClass
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local IsPlayerSpell = IsPlayerSpell or IsSpellKnown

-- Top-off "between pulls" reminder fires below this (exact read, OOC only) - toggle-gated.
local RECUPERATE_HEALTH_PCT = 90
-- Emergency floor: at/below this (the never-secret low-health vignette) the heal ALWAYS
-- shows, regardless of the top-off toggle - a critical-health survival cue.
local LOW_HEALTH_PCT = 35

-- Re-offer a buff once it has this much time left, rather than waiting for it to lapse
-- outright. FLAT time remaining, not a fraction of the duration: what matters is whether
-- the buff outlasts the pull, and a 60-minute flask with 20 minutes on it needs nothing.
-- Wider in a group, where a recast covers everyone and wants to land while people are
-- still standing around rather than mid-pull. Applies to EVERY out-of-combat category -
-- flasks, food, runes, oils, poisons, imbues, raid buffs - so they all age out the same way.
local PRECOMBAT_REFRESH_SOLO  = 180   -- 3 minutes
local PRECOMBAT_REFRESH_GROUP = 300   -- 5 minutes

local function RefreshWindow()
    local inGroup = IsInGroup and IsInGroup()
    -- Group-membership probes can come back secret in instanced contexts; unreadable means
    -- we cannot establish a group, and the narrower window is the one that nags less.
    if issecretvalue and issecretvalue(inGroup) then return PRECOMBAT_REFRESH_SOLO end
    return inGroup and PRECOMBAT_REFRESH_GROUP or PRECOMBAT_REFRESH_SOLO
end

-- Is this aura close enough to lapsing to be worth re-applying now?
-- A permanent aura (duration 0) never lapses. Unreadable timing answers "no": a buff we
-- cannot time is one we must not nag about, since the cost of a false cue is a wasted
-- flask. Same rule the class-buff path uses, so one window governs everything.
local function IsLapsing(aura)
    if not aura then return false end
    local dur, exp = aura.duration, aura.expirationTime
    if issecretvalue and (issecretvalue(dur) or issecretvalue(exp)) then return false end
    if type(dur) ~= "number" or type(exp) ~= "number" or dur <= 0 then return false end
    return (exp - GetTime()) <= RefreshWindow()
end

-- Main-hand temp enchant (weapon oil / shaman imbue) present AND not about to run out.
-- Its expiry comes back as milliseconds REMAINING, not a timestamp - the one place in this
-- file where the window is not compared against expirationTime.
local function MainHandEnchantHolds()
    if not GetWeaponEnchantInfo then return false end
    local has, expiryMs = GetWeaponEnchantInfo()
    if not has then return false end
    if issecretvalue and issecretvalue(expiryMs) then return true end
    if type(expiryMs) ~= "number" then return true end
    return (expiryMs / 1000) > RefreshWindow()
end

-- True if the player currently has any aura whose spellId is in the set AND it is not
-- already inside the refresh window. Iterates the player's helpful auras (usually < 40),
-- so cost is independent of how big the set is - which matters because the food set can
-- hold a few hundred Well Fed buff ids.
local function HasAnyAura(buffSet)
    if not buffSet or not BlizzardAPI or not BlizzardAPI.GetAuras then return false end
    local auras = BlizzardAPI.GetAuras("player", "HELPFUL")
    if not auras then return false end
    for i = 1, #auras do
        local spellId = auras[i].spellId
        -- 12.0.7: some aura spellIds are secret even out of combat; a secret table
        -- key throws, so skip those auras (their identity is unknowable here).
        -- Keep scanning past a lapsing match: a category can be satisfied by more than one
        -- buff, and a fresher one elsewhere in the list still counts.
        if spellId and not (issecretvalue and issecretvalue(spellId))
           and buffSet[spellId] and not IsLapsing(auras[i]) then return true end
    end
    return false
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

-- Optimistic post-click suppression for weapon enhancements. Applying one is a server
-- round trip, so GetWeaponEnchantInfo keeps reporting "no enchant" for a beat after the
-- click - long enough that the suggestion lingers, still clickable, and a double-click
-- burns a second stone (the click applies in one go; it isn't a harmless cursor arm).
-- Treat the category as satisfied for a moment after a click so the icon clears at once.
-- Purely a display latch: if the application never landed, the window lapses and the
-- suggestion returns on the next rebuild.
local ENCHANT_APPLY_GRACE = 2
local enchantAppliedAt = -1e9

--- Called by the click overlay the instant a weapon enhancement is used.
function PrecombatEngine.NoteWeaponEnchantApplied()
    enchantAppliedAt = GetTime()
    PrecombatEngine.ClearCache()
end

--- Mid-application guard: is an application in progress right now? Every category here is
--- satisfied by an AURA (or a weapon enchant) that only lands when the cast/channel COMPLETES,
--- so while you are eating, applying a poison or imbue, or using an oil, the category still
--- reads "missing". One more click then cancels the channel (wasting the food) or burns a
--- second consumable - and ANY suggestion cancels it, not just the one being applied.
---
--- The suggestions STAY on screen through the wait (you are still out of combat, and the icon
--- is what tells you what you're waiting on); it's the CLICK that has to stop. The click
--- overlay disarms every layer while this is true - see UIPrecombatOverlay.
---
--- Eating counts even though it is aura-based (no cast bar, no UnitChannelInfo) - but only
--- for the ~10s it takes Well Fed to land, not the whole meal. The buff persists once you
--- stand up, so waiting out the rest of the food aura buys nothing.
--- OOC-only system, and we only test truthiness (never compare/concat), so this is secret-safe.
function PrecombatEngine.IsBusyApplying()
    if UnitCastingInfo and UnitCastingInfo("player") then return true end
    if UnitChannelInfo and UnitChannelInfo("player") then return true end
    if SpellDB and SpellDB.IsEatingForBuff then
        return SpellDB.IsEatingForBuff()
    end
    return false
end

--- Is the buff category already satisfied? Weapon enchant is read off the weapon (temp
--- enchant); every other category from the player's auras. Out of combat only.
function PrecombatEngine.IsCategorySatisfied(category)
    -- 12.0.7: in aura-restricted contexts (PvP instances - restriction is per-context,
    -- not per-combat) every aura reads as secret, so nothing can be verified. Report
    -- satisfied so we never nag someone to re-consume a buff they may already have.
    -- Live gate; false in normal content keeps this a no-op.
    if BlizzardAPI and BlizzardAPI.AreAurasSecret() then
        return true
    end
    if category == "weaponEnchant" then
        if GetTime() - enchantAppliedAt < ENCHANT_APPLY_GRACE then return true end
        return MainHandEnchantHolds()
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
-- group we find the option that's currently ACTIVE and re-suggest it once it is close enough
-- to lapsing to be worth a recast; if none is up we fall back to the group's default. Only
-- spells the player knows (IsPlayerSpell) surface, so it self-gates by class. Out of combat
-- only; cached. Shares the flat refresh window with the consumable categories (IsLapsing);
-- every buff in this table runs 30-60 minutes, so no short-duration floor is needed.

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

local IsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue or function() return false end

-- Unit-state probes (exists / connected / dead / in-range) can return a SECRET BOOLEAN even
-- out of combat: secrecy is per-CONTEXT, not per-combat, so an instanced context secrets them
-- while player auras still read fine - which is exactly why the `restricted` aura gate upstream
-- does NOT cover this. A bare `if UnitInRange(unit) then` on a secret boolean THROWS.
-- Resolve to a real boolean when readable, nil when secret; every caller treats nil as
-- "can't tell" and skips the member (fail-silent - never cue what we can't verify).
local function ReadableBool(v)
    if v == nil then return nil end
    if IsSecret(v) then return nil end
    return v and true or false
end

-- Does `unit` carry any of `auraIDs` as a HELPFUL aura? Reads the unit's aura list directly -
-- deliberately NOT BlizzardAPI.IsAuraActive, which serves the player-only RedundancyFilter
-- cache when it's warm and would report every party member as buffed.
-- `auraIDs` is a LIST because a buff need not apply its own cast id - some trigger a
-- per-class sub-aura instead, and matching only the cast id would report a fully buffed
-- player as missing forever.
-- Fail-SILENT: an unreadable (secret) spellId means we can't prove the buff is missing, so
-- we report "has it". Note this bails on the FIRST unreadable entry rather than skipping it:
-- skipping could walk past the buff itself and produce a false "missing" cue. The cost is
-- that the party check goes quiet wherever auras are secret - the right trade for a feature
-- whose only failure mode would otherwise be nagging about a buff that is already up.
local function UnitHasHelpfulAura(unit, auraIDs)
    if not auraIDs or not BlizzardAPI or not BlizzardAPI.GetAuras then return true end
    local auras = BlizzardAPI.GetAuras(unit, "HELPFUL")
    if not auras then return true end
    for i = 1, #auras do
        local sid = auras[i].spellId
        if sid == nil or IsSecret(sid) then return true end
        for j = 1, #auraIDs do
            if sid == auraIDs[j] then return true end
        end
    end
    return false
end

-- True when a PARTY member who could actually receive the buff right now is missing it.
-- Party only (party1-4): raid scale would be up to 39 unit scans per refresh and would
-- cue constantly for people out of range or freshly resurrected, so raids are skipped
-- outright. Dead / disconnected / out-of-range members are excluded so every cue is one
-- the player can act on immediately. Note UnitInRange is ~40yd while these buffs reach
-- further - the mismatch errs toward silence, never toward a false cue.
local function PartyMemberMissingBuff(auraIDs)
    -- Group-membership probes go through the same readable-boolean gate: anything we can't
    -- read plainly means we can't establish there's a party to check, so offer nothing.
    if ReadableBool(IsInGroup and IsInGroup()) ~= true then return false end
    if ReadableBool(IsInRaid and IsInRaid()) ~= false then return false end
    for i = 1, 4 do
        local unit = "party" .. i
        if ReadableBool(UnitExists(unit)) == true then
            -- Compare against explicit true/false, never a bare truthiness test: a secret
            -- probe resolves to nil here and the member is skipped, which is the only safe
            -- reading of "we cannot tell whether they are buffable".
            local connected = ReadableBool(UnitIsConnected(unit))
            local dead      = ReadableBool(UnitIsDeadOrGhost(unit))
            local inRange   = ReadableBool(UnitInRange(unit))
            if connected == true and dead == false and inRange == true
               and not UnitHasHelpfulAura(unit, auraIDs) then
                return true
            end
        end
    end
    return false
end

--- @param offerTopoff boolean|nil  include the OOC top-off self-heal (gated by the
---   precombatBuffs.topoffHeal option; passed by the caller which owns the profile). Poisons
---   and imbues are unaffected - only the health top-off reminder honors this flag.
function PrecombatEngine.GetMissingClassBuffs(offerTopoff)
    local now = GetTime()
    if cachedClassBuffs and (now - cachedClassBuffsAt) < 0.5 then
        return cachedClassBuffs
    end
    local out = {}
    -- Which spell (if any) this pass offered as the health top-off, so the renderer can tell it
    -- apart from the poisons/imbues alongside it and drive its alpha from the health curve.
    -- Cleared on RECOMPUTE only: an early return from the cache above must keep the value that
    -- produced that cache, or the cue would blink off for the rest of the cache window.
    PrecombatEngine.offeredTopoffHeal = nil
    local groups = (not InCombatLockdown()) and SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS
    local class = groups and select(2, UnitClass("player"))
    groups = class and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    -- 12.0.7: in aura-restricted contexts the by-ID probe returns nil for secret-flagged
    -- auras (RequiresNonSecretAura), so every class buff would look lapsed - offer nothing.
    local restricted = BlizzardAPI and BlizzardAPI.AreAurasSecret()
    if groups and get and not restricted then
        for _, grp in ipairs(groups) do
            local active, aura
            for _, spellID in ipairs(grp.group) do
                if IsPlayerSpell(spellID) then
                    local a = get(spellID)
                    -- A buff that applies a per-class sub-aura instead of its own cast id
                    -- is invisible to the cast-id probe - fall back to its declared aura
                    -- family. `active` stays the CAST id (that's what gets suggested);
                    -- only the detection changes.
                    if not a and grp.auraIDs then
                        for _, auraID in ipairs(grp.auraIDs) do
                            a = get(auraID)
                            if a then break end
                        end
                    end
                    if a then active, aura = spellID, a; break end
                end
            end
            if active then
                local offered = IsLapsing(aura)
                if offered then out[#out + 1] = active end
                -- Group buff the player already has, but a party member is missing it
                -- (joined late, released, or was out of range when it went out). One
                -- re-cast covers everyone, so offer it even though the player's own
                -- copy is nowhere near lapsing.
                if not offered and grp.raidWide
                   and PartyMemberMissingBuff(grp.auraIDs or grp.group) then
                    out[#out + 1] = active
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
    -- ride the group loop above. Suggest the known imbue while the main hand is bare or the
    -- enchant is inside the refresh window - the same read IsCategorySatisfied uses for oils.
    if not InCombatLockdown() then
        local imbue = KnownWeaponImbue()
        if imbue and not MainHandEnchantHolds() then out[#out + 1] = imbue end
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
    -- Two tiers, so a critical-health cue can never be accidentally disabled:
    --   * EMERGENCY (<= ~35%): ALWAYS on, even with the top-off toggle OFF. The low-health
    --     vignette is never secret (and a low exact read counts too), so a critical-health
    --     player is always shown the heal.
    --   * TOP-OFF (35-100%): the opt-in "top off between pulls" reminder, gated by the toggle
    --     (offerTopoff). Health is secret out of combat in the open world, so detect below-full
    --     from never-secret signals: the exact read where available (rested/cities), else
    --     sustained regen ticks (health only regenerates BELOW full - airtight, and it goes
    --     false the moment you hit full) plus a short post-combat window to bridge the
    --     regen-start delay.
    if not InCombatLockdown() and not restricted and get and recupKnown
        and not get(SpellDB.RECUPERATE_AURA) then
        local hurt = false
        if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
            local pct, estimated = BlizzardAPI.GetPlayerHealthPercentSafe()
            if pct and pct <= LOW_HEALTH_PCT then
                hurt = true                                  -- emergency floor: always on
            elseif offerTopoff then
                if pct and not estimated then
                    hurt = pct < RECUPERATE_HEALTH_PCT       -- exact 35-90%
                elseif (BlizzardAPI.HasSustainedPlayerHealthActivity and BlizzardAPI.HasSustainedPlayerHealthActivity())
                    or (BlizzardAPI.IsInPostCombatDowntime and BlizzardAPI.IsInPostCombatDowntime()) then
                    hurt = true                              -- secret: regen / post-combat
                end
            end
        end
        -- Same secret-boolean hazard as the party probes above: UnitIsDeadOrGhost can come
        -- back secret, and a bare truthiness test on it throws. "Not KNOWN to be dead" is
        -- the right fail direction here - a secret must not swallow a critical-health cue.
        if hurt and ReadableBool(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) ~= true
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
                PrecombatEngine.offeredTopoffHeal = heal
            else
                -- Recuperate (1231411) is a universal all-class heal, castable in
                -- any form; druids see it DISPLAYED as Frenzied Regeneration in
                -- bear, but the base carries no form requirement, so it is always
                -- a valid recovery offer. (Do NOT gate on the display override's
                -- legacy bear requirement - that hides a castable heal.)
                out[#out + 1] = SpellDB.RECUPERATE
                PrecombatEngine.offeredTopoffHeal = SpellDB.RECUPERATE
            end
        end
    end
    cachedClassBuffs, cachedClassBuffsAt = out, now
    return out
end
