-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")

local UIRenderer, UIFrameFactory, UIAnimations, UIHealthBar, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter, UINameplateOverlay, DefensiveEngine, GapCloserEngine, TargetFrameAnchor, KeyPressDetector, SpellDB, CustomQueueOpts, SpellSearch, DotTracker, MaintenanceTracker, CastInterruptTracker

-- Hot path cache for OnUpdateTick (upvalued at file scope so all methods share them)
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime
local GetCVar = GetCVar
local math_max = math.max

-- Update loop state (declared at file scope so event handlers defined anywhere in this
-- file can set the flags; the OnUpdateTick closure reads the same upvalues).
local spellQueueDirty = true
local defensiveQueueDirty = true
-- Shared read-only empty queue for suppressed states (vehicle/possess) - renderers
-- only iterate their input, so one constant replaces two fresh tables per tick.
local EMPTY_QUEUE = {}
local lastFullUpdate = 0
local IDLE_CHECK_INTERVAL = 0.5  -- Check every 0.5s when idle (no recent events)
local OOC_DIRTY_UPDATE_INTERVAL = 0.15   -- OOC dirty queue cadence (~6.7Hz)
local OOC_DEFENSIVE_IDLE_INTERVAL = 1.0  -- OOC defensive full rebuild cadence (1Hz)
local OOC_EVENT_DIRTY_THROTTLE = 0.2     -- Coalesce OOC cooldown/usability event bursts
local lastOOCDirtyEvent = 0
local OOC_ACTIONBAR_THROTTLE = 0.25      -- Coalesce OOC action-bar churn (cities/macros)
local lastOOCActionBarEvent = 0
local lastPartyLowCount = 0              -- Edge detector for the party-health handler

-- CVar cache (only needed by OnUpdateTick, but kept here for co-location with the rest)
local cachedUpdateRate = nil
local lastCVarCheck = 0
local CVAR_CHECK_INTERVAL = 5.0  -- Only re-check CVar every 5 seconds

local function NotifyOptionsChange()
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
    if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
end

local defaults = {
    profile = {
        framePosition = {
            point = "CENTER",
            x = 0,
            y = -150,
        },
        maxIcons = 4,
        iconSize = 42,
        iconSpacing = 1,
        gamepadIconStyle = "xbox",    -- Gamepad button icons: "generic", "xbox", "playstation"
        inputPreference = "auto",       -- Keybind input: "auto", "keyboard", "gamepad"
        debugMode = false,
        isManualMode = false,
        tooltipMode = "always",       -- "never", "outOfCombat", or "always"
        glowMode = "all",                 -- Shared highlight mode: "all", "primaryOnly", "procOnly", "none".
                                          -- Per-surface glow keys default "shared" = follow this one.
        showFlash = true,                 -- Flash icon on matching key press
        showUsabilityTint = true,         -- Tint icons by state (blue=no resources, gray=unavailable, red=out of range)
        showImportantCastCue = false,     -- Warn when a nearby mob casts an engine-flagged "important" spell
        showCastingHighlight = true,      -- White border on icon while its spell is actively being cast
        greyOutWhileCasting = true,       -- Grey out icons while the player is casting or channeling a spell
        firstIconScale = 1.0,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueWhenMounted = false,  -- Hide the queue while mounted
        displayMode = "queue",         -- "disabled" / "queue" / "overlay" / "both"
        queueVisibility = "always",    -- "always", "combatOnly", or "requireHostile"
        hideItemAbilities = false,     -- Hide equipped item abilities (trinkets, tinkers)
        panelInteraction = "unlocked",    -- "unlocked", "locked", "clickthrough"
        clickToCastOOC = true,            -- Left-click defensive-queue icons out of combat to cast/use them
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        targetFrameAnchor = "DISABLED",     -- Anchor to target frame: DISABLED, TOP, BOTTOM, LEFT, RIGHT
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        -- Queue-ordering settings: apply to positions 2+ of both the custom list and
        -- Blizzard's default rotation. All smart ordering off = exact source order.
        orderProcsFirst = true,           -- Surface procced abilities ahead of source order
        contextOrder = "simc",            -- "off" | "ac" (match Blizzard's pick) | "simc" (theorycraft priority; falls back to "ac" without spec data)
        orderSinkCooldowns = true,        -- Push on-cooldown abilities to the end of the queue
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals
        blacklistedSpells = {},            -- Per-spec spell blacklist: blacklistedSpells["WARRIOR_1"] = {[spellID] = true}
        hotkeyOverrides = {},             -- Profile-level hotkey display overrides (included in profile copy)
        interruptMode = "kickPrefer",      -- Interrupt reminder mode: "disabled", "kickOnly", "kickPrefer", "ccPrefer"
        showSootheCue = true,              -- Enrage-cleanse cue on the interrupt icon (soothe classes only)
        includeFears = false,              -- Offer fear-type CC as interrupt substitutes (breaks on damage, scatters packs)
        interruptAlertSound = "None",       -- Alert sound (LSM key); "None" = disabled
        burstCueGlow = true,               -- Purple glow on the spec's major cooldown when a burst window is called for
        casterFiller = {},                 -- [specKey]=true: suppress melee-weave suggestions for this healer spec
        -- Healer group-heal surface. Off until the player opts in; the signal it
        -- rides (Blizzard's party health alert) is a setting they must enable too.
        healing = {
            enabled = false,
            emergencyCount = 3,       -- allies below lowThreshold before the emergency heal claims the Sustain slot
            lowThreshold = 80,        -- an ally this hurt is worth an area heal
            urgentThreshold = 50,     -- an ally this hurt is an emergency on their own
        },
        -- Cue dots on queue icons. showMoveCastDot is deliberately NOT declared here:
        -- nil means "per-spec auto" (ranged/healer on, melee off) - see MoveCastDotEnabled.
        -- Off by default: the arrow keys off AC re-recommending an active DoT, and not
        -- every spec's rotation re-recommends on those terms - unreliable spec-dependent.
        showDotSpreadArrow = false,        -- Switch-target arrow on the AC slot when its DoT is already up
        showOffGcdDot = false,             -- Amber dot marking off-GCD (weave-in) abilities
        -- Tank maintenance slot + crowd-control escape (defensive "position 0")
        showMaintenanceSlot = true,        -- Tank mitigation-upkeep slot (tank specs, combat only)
        showCCBreak = false,               -- Experimental: Sustain slot becomes your CC-escape while held by CC
        ccBreakMacro = "",                 -- Macro name to suggest for form-escapable CC ("" = none)
        showPetHealCue = true,             -- Pet-heal reminder in the Sustain slot (pet classes)
        petHealThreshold = 50,             -- Pet health % that arms the pet-heal cue (10-90)
        -- Blizzard Cooldown Manager integration (opt-in)
        cooldownManagerEnable = false,     -- Let JustAC manage Cooldown Manager viewer visibility
        hideCdmEssential = false,          -- Hide the Essential Cooldowns viewer
        hideCdmUtility = false,            -- Hide the Utility Cooldowns viewer
        hideCdmTrackedBuff = false,        -- Hide the Tracked Buffs viewer
        hideCdmTrackedBar = false,         -- Hide the Tracked Bars viewer
        -- Text overlay settings: apply universally to all icons (main queue, defensive, nameplate, interrupt)
        textOverlays = {
            hotkey = {
                show      = true,
                fontScale = 1.0,
                color     = {r = 1, g = 1, b = 1, a = 1},
                anchor    = "TOPRIGHT",    -- TOPRIGHT, TOPLEFT, TOP, CENTER, BOTTOMRIGHT, BOTTOMLEFT
            },
            cooldown = {
                show      = true,
                fontScale = 1.0,
                color     = {r = 1, g = 1, b = 1, a = 0.5},
                -- anchor not exposed: CooldownFrameTemplate manages it (always centered)
            },
            charges = {
                show      = true,
                fontScale = 1.0,
                color     = {r = 1, g = 1, b = 1, a = 1},
                anchor    = "BOTTOMRIGHT", -- BOTTOMRIGHT, BOTTOMLEFT, BOTTOM
            },
        },
        -- Nameplate Overlay feature (independent queue cluster on target nameplate)
        nameplateOverlay = {
            maxIcons          = 3,       -- 1-7 DPS queue slots
            reverseAnchor     = false,   -- false = RIGHT (default), true = LEFT
            expansion         = "down",   -- "out" (horizontal), "up" (vertical up), "down" (vertical down)
            iconSize          = 32,
            iconSpacing       = 2,   -- px between successive icons in the cluster
            opacity           = 1.0, -- icon opacity (0.1–1.0)
            glowMode          = "shared",
            firstIconScale    = 1.0,
            queueIconDesaturation = 0,
            queueVisibility   = "always", -- "always", "combatOnly", or "requireHostile"
            hideWhenMounted   = false,
            showDefensives       = true,
            maxDefensiveIcons    = 3,    -- 1-7
            defensiveDisplayMode = "always", -- "healthBased", "combatOnly", "always"
            defensiveGlowMode    = "shared",
            defensiveIconScale   = 1.0,
            showHealthBar        = true,
            showPetHealthBar     = true,
            showPowerBar         = false,  -- Resource bar (primary power + segmented point resource); anchors to the health bars
            -- Overlay-specific overrides (icons are smaller, so labels may need different sizing/positioning)
            textOverlays = {
                hotkey   = { fontScale = 1.0 },
                cooldown = { fontScale = 1.0 },
                charges  = { fontScale = 1.0 },
            },
        },
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            showProcs = true,         -- Show procced defensives (Victory Rush, free heals) at any health
            emergencyPotionChoice = 0, -- Emergency healing potion pick (0 = automatic/highest)
            position = "SIDE1",       -- SIDE1 (health bar side) or SIDE2 (legacy saved "LEADING" reads as SIDE1)
            showHealthBar = true,    -- Display compact health bar above main queue
            showPetHealthBar = true, -- Display compact pet health bar (pet classes only)
            showTargetHealthBar = true, -- Display compact target health bar opposite the player/pet bars (hostile targets only)
            showPowerBar = false,     -- Resource bar (primary power + segmented point resource); anchors to the health bars
            iconScale = 1.0,          -- Scale for defensive icons (same range as Primary Spell Scale)
            maxIcons = 4,             -- Number of defensive icons to show (1-7)
            classSpells = {},         -- Per-spec spell lists: classSpells["WARRIOR_1"] = {defensiveSpells={...}, petHealSpells={...}}
            itemSettings = {},        -- Per-item settings: itemSettings[itemID] = {linkedAura=spellID, combatHide=bool}
            spellSettings = {},       -- Per-spell settings: spellSettings[spellID] = {procPriority=bool, alwaysShow=bool, holdUntilCharged=bool}
            displayMode = "always", -- "healthBased" (show when low), "combatOnly" (always in combat), "always"
            -- Hold back panic buttons (bubbles / big instant heals / potions) above the
            -- low-health threshold. ON by default: at 80% health a bubble or a Lay on Hands is
            -- never the right press, so listing it live is bad advice. Safe to default on only
            -- since pre-emptive walls were exempted (tier 4 in SpellDB.GetDefenseTier) - before
            -- that this also parked Shield Wall and friends, which you press BEFORE the hit.
            hideEmergencyUntilLow = true,
            glowMode = "shared", -- "shared" (follow the top-level glowMode), or its own "all"/"primaryOnly"/"procOnly"/"none"
            detached = false,                                    -- Give defensives their own independent draggable frame
            detachedPosition = { point = "CENTER", x = 0, y = 100 }, -- Saved position of the detached defensive frame
            detachedOrientation = "LEFT",                        -- Icon growth direction for detached frame (LEFT/RIGHT/UP/DOWN)
        },
        -- Pre-combat buff checklist (out of combat only; secure click-to-use overlay)
        precombatBuffs = {
            enabled = true,
            -- Out-of-combat health top-off reminder: offer a cheap self-heal between pulls
            -- while below full. OFF by default - it is a reminder-to-heal aid, not everyone
            -- wants it, and the below-full signal is a proxy in secret zones (see
            -- PrecombatEngine hurt detection).
            topoffHeal = false,
            topoffThreshold = 90,   -- Health % below which the top-off nudge shows (emergency band below 35% is fixed)
            -- per-category override: [cat]=false off, [cat]="haste"/… stat pref, nil=auto/on.
            -- Speed is a food preference (stat="speed"), not its own category. XP is a utility
            -- category - default OFF (explicit false, so "on" must be a truthy value to
            -- override the AceDB default).
            categories = { xp = false },
        },
        -- Gap-closer feature (suggest movement spells when target is out of melee range)
        gapClosers = {
            enabled = true,
            farOnly = true,           -- Only suggest when the gap is real (not merely out of melee)
            showGlow = true,          -- Glow on gap-closer icons (when enabled)
            classSpells = {},         -- Per-spec spell lists: classSpells["WARRIOR_1"] = {100, 6544}
        },
    },
    char = {
        firstRun = true,
        specProfilesEnabled = true,   -- Auto-switch profiles by spec (enabled by default)
        specProfiles = {},        -- [specIndex] = "profileName" | "DISABLED" | nil
    },
}

function JustAC:DebugPrint(msg)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print(msg)
    end
end

-------------------------------------------------------------------------------
-- Data migration helpers for NormalizeSavedData
-- Each function is a no-op when nothing to migrate.
-- Entry point: NormalizeSavedData() below.  Addon startup: OnInitialize() below.
-------------------------------------------------------------------------------
local function MigrateBlacklist(profile, charData)
    if not profile.blacklistedSpells then profile.blacklistedSpells = {} end

    local SpellDB = LibStub("JustAC-SpellDB", true)

    -- db.char.blacklistedSpells → db.profile.blacklistedSpells (per-spec keyed)
    if charData.blacklistedSpells and next(charData.blacklistedSpells) then
        local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
        if specKey then
            if not profile.blacklistedSpells[specKey] then
                profile.blacklistedSpells[specKey] = {}
            end
            for key, value in pairs(charData.blacklistedSpells) do
                local spellID = tonumber(key)
                if spellID and spellID > 0 and value and not profile.blacklistedSpells[specKey][spellID] then
                    profile.blacklistedSpells[specKey][spellID] = true
                end
            end
            charData.blacklistedSpells = {}  -- Clear after migration
        end
    end

    -- Flat profile.blacklistedSpells format (pre-4.x: {[spellID]=true}) → spec-keyed
    local hasNumericKey = false
    for key, _ in pairs(profile.blacklistedSpells) do
        if type(key) == "number" or (type(key) == "string" and tonumber(key)) then
            hasNumericKey = true
            break
        end
    end
    if hasNumericKey then
        local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
        if specKey then
            local oldFlat = {}
            local newStructured = {}
            for key, value in pairs(profile.blacklistedSpells) do
                local spellID = tonumber(key)
                if spellID and spellID > 0 and value then
                    oldFlat[spellID] = true
                elseif type(key) == "string" and type(value) == "table" then
                    newStructured[key] = value  -- Preserve any already-migrated spec entries
                end
            end
            profile.blacklistedSpells = newStructured
            if not profile.blacklistedSpells[specKey] then
                profile.blacklistedSpells[specKey] = {}
            end
            for spellID, _ in pairs(oldFlat) do
                if not profile.blacklistedSpells[specKey][spellID] then
                    profile.blacklistedSpells[specKey][spellID] = true
                end
            end
        end
    end

    -- Normalize per-spec blacklist tables (SavedVariables may load numeric keys as strings).
    -- Preserve the entry value as-is - `true` (all positions) or `{ fixedQueue = true }`
    -- (positions 2+ only) - and keep both spells (positive IDs) and items (negative IDs).
    for specKey, spellTable in pairs(profile.blacklistedSpells) do
        if type(spellTable) == "table" then
            local normalized = {}
            for key, value in pairs(spellTable) do
                local id = tonumber(key)
                if id and id ~= 0 and value then
                    normalized[id] = value
                end
            end
            profile.blacklistedSpells[specKey] = normalized
        end
    end
end

local function MigrateHotkeyOverrides(profile, charData)
    -- Normalize profile.hotkeyOverrides (SavedVariables serialize numeric keys as
    -- strings). Negative IDs are items - they must survive normalization; the old
    -- `> 0` filter silently dropped every item override on login.
    if profile.hotkeyOverrides then
        local normalized = {}
        for key, value in pairs(profile.hotkeyOverrides) do
            local spellID = tonumber(key)
            if spellID and spellID ~= 0 and type(value) == "string" and value ~= "" then
                normalized[spellID] = value
            end
        end
        profile.hotkeyOverrides = normalized
    end
    -- One-time migration: char.hotkeyOverrides → profile.hotkeyOverrides
    -- (hotkey overrides moved to profile level so they are included in profile copies)
    if charData.hotkeyOverrides and next(charData.hotkeyOverrides) then
        if not profile.hotkeyOverrides then profile.hotkeyOverrides = {} end
        for key, value in pairs(charData.hotkeyOverrides) do
            local spellID = tonumber(key)
            if spellID and spellID ~= 0 and type(value) == "string" and value ~= "" and not profile.hotkeyOverrides[spellID] then
                profile.hotkeyOverrides[spellID] = value
            end
        end
        charData.hotkeyOverrides = {}  -- Clear after migration
    end
end

local function MigrateLegacySettings(profile)
    local npo = profile.nameplateOverlay
    -- Migrate panelLocked boolean → panelInteraction string
    if profile.panelLocked == true and (not profile.panelInteraction or profile.panelInteraction == "unlocked") then
        profile.panelInteraction = "locked"
    end
    -- Migrate legacy hotkey show/hide settings → per-queue textOverlays.hotkey.show (one-time)
    -- Main queue: showOffensiveHotkeys → textOverlays.hotkey.show
    -- NOTE: defensives.showHotkeys is deliberately dropped, not migrated - it was a
    -- separate per-category toggle that no longer exists. Merging it into the unified
    -- toggle would hide ALL hotkeys (offensive + defensive) for users who only
    -- intended to hide defensive hotkeys. Fail-open: show hotkeys by default.
    if profile.textOverlays and profile.textOverlays.hotkey then
        if profile.showOffensiveHotkeys == false then
            profile.textOverlays.hotkey.show = false
        end
    end
    -- (Legacy nameplateOverlay.showHotkey is cleared with the other npo legacy keys
    -- below; overlay label visibility is central now, so there is nothing to carry over.)
    -- Migrate showInterrupt + ccRegularMobs → interruptMode (one-time)
    if profile.showInterrupt ~= nil or profile.ccRegularMobs ~= nil then
        if profile.showInterrupt == false then
            profile.interruptMode = "disabled"
        elseif profile.ccRegularMobs == false then
            profile.interruptMode = "kickOnly"
        else
            profile.interruptMode = "kickPrefer"
        end
    end
    if npo and (npo.showInterrupt ~= nil or npo.ccRegularMobs ~= nil) then
        if npo.showInterrupt == false then
            npo.interruptMode = "disabled"
        elseif npo.ccRegularMobs == false then
            npo.interruptMode = "kickOnly"
        else
            npo.interruptMode = "kickPrefer"
        end
    end
    -- ccShielded → kickPrefer (renamed mode, same behavior)
    if profile.interruptMode == "ccShielded" then profile.interruptMode = "kickPrefer" end
    -- Centralization migration: per-surface settings → single central setting
    -- interruptMode: overlay had its own copy → use profile-level only
    if npo and npo.interruptMode ~= nil then
        if npo.interruptMode == "ccShielded" then npo.interruptMode = "kickPrefer" end
        -- If user customized the overlay's interrupt mode, adopt it as the central value
        -- (only if the main queue is still at default, otherwise main queue wins)
        if profile.interruptMode == "kickPrefer" and npo.interruptMode ~= "kickPrefer" then
            profile.interruptMode = npo.interruptMode
        end
        npo.interruptMode = nil
    end
    -- replaceQuestIndicator: removed as option (always active when overlay enabled)
    if npo and npo.replaceQuestIndicator ~= nil then npo.replaceQuestIndicator = nil end
    -- showFlash: overlay + defensives had their own copies → use profile-level only
    if npo and npo.showFlash ~= nil then npo.showFlash = nil end
    if profile.defensives and profile.defensives.showFlash ~= nil then
        -- If user disabled defensive flash, adopt that as the central value
        if profile.showFlash ~= false and profile.defensives.showFlash == false then
            profile.showFlash = false
        end
        profile.defensives.showFlash = nil
    end
    -- textOverlays: overlay had full parallel copy → central show/color/anchor, keep overlay fontScale
    if npo and npo.textOverlays then
        local npoOv = npo.textOverlays
        -- Strip centralized fields from overlay (show, color, anchor are now central)
        for _, key in ipairs({"hotkey", "cooldown", "charges"}) do
            if npoOv[key] then
                npoOv[key].show = nil
                npoOv[key].color = nil
                npoOv[key].anchor = nil
                -- Keep fontScale if it exists; remove entry entirely if only fontScale remains at default
            end
        end
    end
    -- showHealthBar/showPetHealthBar: General tab fallbacks → defensives owns these
    if profile.showHealthBar == true and profile.defensives and not profile.defensives.enabled then
        -- User had standalone health bar enabled with defensives off - move to defensives setting
        profile.defensives.showHealthBar = true
    end
    if profile.showPetHealthBar == true and profile.defensives and not profile.defensives.enabled then
        profile.defensives.showPetHealthBar = true
    end
    profile.showHealthBar = nil
    profile.showPetHealthBar = nil
    -- Migrate legacy tooltip settings → tooltipMode (one-time). "Still at default"
    -- heuristic: tooltipMode has a profile default, so it never reads nil - only act
    -- when it is untouched and an explicit legacy opt-out was saved. (Values equal to
    -- the old defaults never persisted, so showTooltips==false is the only signal.)
    if profile.tooltipMode == "always" and profile.showTooltips == false then
        profile.tooltipMode = "never"
    end
    -- Nil legacy keys so they don't persist in saved data after migration
    profile.showTooltips = nil
    profile.tooltipsInCombat = nil
    profile.showOffensiveHotkeys = nil
    profile.showInterrupt = nil
    profile.ccRegularMobs = nil
    if profile.defensives then profile.defensives.showHotkeys = nil end
    if npo then npo.showInterrupt = nil; npo.ccRegularMobs = nil; npo.showHotkey = nil end
end

local function MigrateSoundKeys(profile)
    -- interruptAlertSound old camelCase keys → LSM keys (4.17.0)
    local OLD_SOUND_TO_LSM = {
        -- Kept sounds (old camelCase → new LSM key)
        shing = "JAC: Shing!", wham = "JAC: Wham!", simonChime = "JAC: Simon Chime",
        shortCircuit = "JAC: Short Circuit", pvpFlag = "JAC: PvP Flag",
        dwarfHorn = "JAC: Dwarf Horn", grimrailHorn = "JAC: Grimrail Horn",
        felNova = "JAC: Fel Nova",
        -- Removed sounds → fall back to None
        pvpFlagHorde = "None", pvpAlliance = "None", pvpHorde = "None",
        thunderCrack = "None", warDrums = "None", scourgeHorn = "None",
        explosion = "None", cheer = "None", felPortal = "None",
        humm = "None", cartoonFX = "None", rubberDucky = "None",
        pygmyDrums = "None", squireHorn = "None", gruntlingHorn = "None",
        none = "None",
    }
    local oldSound = profile.interruptAlertSound
    if oldSound and OLD_SOUND_TO_LSM[oldSound] then
        profile.interruptAlertSound = OLD_SOUND_TO_LSM[oldSound]
    end
end

-- Migrate legacy hideQueueOutOfCombat / requireHostileTarget bools to the unified
-- queueVisibility key.  Safe to call multiple times; no-op when already migrated.
local function MigrateQueueVisibility(profile)
    -- If the new key is still at the default "always" but a legacy bool is set,
    -- the user previously configured combat-only or hostile-target gating.
    if profile.queueVisibility == "always" then
        if profile.hideQueueOutOfCombat then
            profile.queueVisibility = "combatOnly"
        elseif profile.requireHostileTarget then
            profile.queueVisibility = "requireHostile"
        end
    end
    -- Clear legacy keys regardless (they are superseded by queueVisibility)
    profile.hideQueueOutOfCombat = nil
    profile.requireHostileTarget = nil
end

-- Migrate legacy defensives.showOnlyInCombat / alwaysShowDefensive bools → the
-- unified defensives.displayMode key. Uses the "still at default" heuristic
-- (mirrors MigrateQueueVisibility): the AceDB default "always" shadows the raw
-- key, so a legacy bool only counts when displayMode is still at that default.
local function MigrateDefensiveDisplayMode(profile)
    local def = profile.defensives
    if not def then return end
    if def.displayMode == "always" then
        if def.showOnlyInCombat then
            def.displayMode = "combatOnly"
        elseif def.alwaysShowDefensive == false then
            def.displayMode = "healthBased"
        end
        -- alwaysShowDefensive true (or unset) → leave at the "always" default
    end
    def.showOnlyInCombat = nil
    def.alwaysShowDefensive = nil
end

-- Per-surface highlight modes now default "shared" (follow the top-level glowMode).
-- One-time stamped pin: where the shared mode had been changed away from "all" while
-- a per-surface mode still sat on its old independent default, store that old
-- effective value so the profile keeps looking exactly as it did. Stamped because
-- re-running would re-pin values the user has since deliberately set to "shared".
local function MigrateSharedGlow(profile)
    if profile.sharedGlowMigrated then return end
    profile.sharedGlowMigrated = true
    local shared = profile.glowMode or "all"
    -- Old effective values under the independent-default scheme: defensives and
    -- overlay-offensive defaulted "all"; overlay-defensive fell back to
    -- overlay-offensive, then "all". Pin only where following the shared value
    -- would change what the player sees.
    local function pin(tbl, key, oldEffective)
        if tbl and (tbl[key] == nil or tbl[key] == "shared") and oldEffective ~= shared then
            tbl[key] = oldEffective
        end
    end
    local npo = profile.nameplateOverlay
    local npoOld = (npo and npo.glowMode ~= nil and npo.glowMode ~= "shared") and npo.glowMode or "all"
    pin(profile.defensives, "glowMode", "all")
    if npo then
        pin(npo, "defensiveGlowMode", npoOld)
        pin(npo, "glowMode", "all")
    end
end

-- Merge the retired split toggles: channel grey-out folded into the casting toggle,
-- range tint folded into the usability tint. An explicit false on either half keeps
-- the merged toggle off (the user disliked the effect; don't force it back on).
local function MigrateMergedToggles(profile)
    if profile.greyOutWhileChanneling == false then
        profile.greyOutWhileCasting = false
    end
    profile.greyOutWhileChanneling = nil
    if profile.showRangeTint == false then
        profile.showUsabilityTint = false
    end
    profile.showRangeTint = nil
end

-- Migrate the legacy orderContextAware bool → the contextOrder select. Only a saved
-- false matters (contextOrder still at its "simc" default): the Options set cleared
-- the bool on every write, so a surviving false means the user turned the old toggle
-- off and never touched the new dropdown.
local function MigrateContextOrder(profile)
    if profile.contextOrder == "simc" and profile.orderContextAware == false then
        profile.contextOrder = "off"
    end
    profile.orderContextAware = nil
end

-- Migrate legacy nameplateOverlay.showGlow bool → nameplateOverlay.glowMode.
-- Only a saved showGlow=false changes an untouched glowMode (to "none"). "Untouched"
-- means either historical default: "all" (pre-shared saved value) or "shared" (the
-- current profile default, which is what a never-customized glowMode reads as).
local function MigrateOverlayGlowMode(profile)
    local npo = profile.nameplateOverlay
    if not npo then return end
    if (npo.glowMode == "all" or npo.glowMode == "shared") and npo.showGlow == false then
        npo.glowMode = "none"
    end
    npo.showGlow = nil
end

-- SavedVariables serialize numeric keys as strings; normalize on load.
-- Calls migration helpers in dependency order; each is a no-op if already migrated.
function JustAC:NormalizeSavedData()
    local charData = self.db and self.db.char
    if not charData then return end
    local profile = self.db and self.db.profile
    if not profile then return end

    MigrateBlacklist(profile, charData)
    MigrateHotkeyOverrides(profile, charData)
    MigrateLegacySettings(profile)
    MigrateSoundKeys(profile)
    MigrateQueueVisibility(profile)
    MigrateDefensiveDisplayMode(profile)
    MigrateOverlayGlowMode(profile)
    MigrateContextOrder(profile)
    MigrateMergedToggles(profile)
    MigrateSharedGlow(profile)
end

function JustAC:OnInitialize()
    self.db = AceDB:New("JustACDB", defaults, JustACGlobal and JustACGlobal.useDefaultProfile or nil)

    -- Initialize binding globals before combat (prevents taint)
    if not _G.BINDING_NAME_JUSTAC_CAST_FIRST then
        _G.BINDING_NAME_JUSTAC_CAST_FIRST = "JustAC: Cast First Spell"
        _G.BINDING_HEADER_JUSTAC = "JustAssistedCombat"
    end
    -- Situational-set toggles (Bindings.xml). Names read from the locale so the Key
    -- Bindings UI is translated; the set's own label is shown next to it once named.
    for slot = 1, 3 do
        _G["BINDING_NAME_JUSTAC_TOGGLE_SET" .. slot] = string.format(L["Toggle Situational Set"], slot)
    end
    
    self:NormalizeSavedData()

    self:LoadModules()
    self:InitializeDefensiveSpells()
    
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    -- Reset: AceDB restores profile defaults itself; character data (blacklist,
    -- spec profiles) is intentionally preserved - a refresh is all that's needed.
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileDeleted")
    
    if Options and Options.Initialize then
        Options.Initialize(self)
    end
end

function JustAC:OnEnable()
    if not UIFrameFactory or not UIFrameFactory.CreateMainFrame then
        self:Print("Error: UIFrameFactory module not loaded properly")
        return
    end
    
    UIFrameFactory.CreateMainFrame(self)
    if not self.mainFrame then
        self:Print("Error: Failed to create main frame")
        return
    end

    -- Safety: clamp saved position to screen bounds (handles resolution/scale changes)
    if TargetFrameAnchor then TargetFrameAnchor.ClampFrameToScreen(self) end

    -- Apply target frame anchor if enabled (before icons so position is correct)
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end

    UIFrameFactory.CreateSpellIcons(self)

    -- Must be after CreateSpellIcons
    if UIHealthBar and UIHealthBar.CreateHealthBar then
        UIHealthBar.CreateHealthBar(self)
    end
    if UIHealthBar and UIHealthBar.CreatePetHealthBar then
        UIHealthBar.CreatePetHealthBar(self)
    end
    if UIHealthBar and UIHealthBar.CreateTargetHealthBar then
        UIHealthBar.CreateTargetHealthBar(self)
    end
    if UIHealthBar and UIHealthBar.CreatePowerBar then
        UIHealthBar.CreatePowerBar(self)
    end

    local PrecombatOverlay = LibStub("JustAC-PrecombatOverlay", true)
    if PrecombatOverlay and PrecombatOverlay.Init then PrecombatOverlay.Init(self) end

    if UnitAffectingCombat("player") then
        if UIAnimations and UIAnimations.ResumeAllGlows then UIAnimations.ResumeAllGlows(self) end
    else
        if UIAnimations and UIAnimations.PauseAllGlows then UIAnimations.PauseAllGlows(self) end
    end
    
    self:InitializeCaches()
    self:StartUpdates()

    -- Create key press detector for flash feedback
    if KeyPressDetector then KeyPressDetector.Create(self) end

    -- Nameplate overlay (fully independent of main panel)
    if UINameplateOverlay then UINameplateOverlay.Create(self) end
    -- ── Nameplate ────────────────────────────────────────────────────────────────────
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED",   "OnNamePlateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNamePlateRemoved")

    -- ── Combat / character state ─────────────────────────────────────────────────
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChange")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")

    -- ── Unit-filtered events ─────────────────────────────────────────────────────
    -- These UNIT_* events fire for every unit in the area (constant churn in
    -- crowded cities). AceEvent has no RegisterUnitEvent, so a dedicated frame
    -- filters to player/pet/target at the C level before any Lua runs.
    local UNIT_EVENT_HANDLERS = {
        UNIT_HEALTH                  = "OnHealthChanged",
        UNIT_POWER_FREQUENT          = "OnPowerChanged",
        UNIT_DISPLAYPOWER            = "OnPowerTypeChanged",
        UNIT_MAXPOWER                = "OnPowerTypeChanged",
        UNIT_AURA                    = "OnUnitAura",
        UNIT_SPELLCAST_SUCCEEDED     = "OnSpellcastSucceeded",
        UNIT_SPELLCAST_START         = "OnPlayerCastStart",
        UNIT_SPELLCAST_STOP          = "OnPlayerCastStop",
        UNIT_SPELLCAST_CHANNEL_START = "OnPlayerChannelStart",
        UNIT_SPELLCAST_CHANNEL_STOP  = "OnPlayerChannelStop",
        UNIT_PET                     = "OnPetChanged",
        UNIT_ENTERED_VEHICLE         = "OnVehicleChanged",
        UNIT_EXITED_VEHICLE          = "OnVehicleChanged",
    }
    if not self.unitEventFrame then
        self.unitEventFrame = CreateFrame("Frame")
        self.unitEventFrame:SetScript("OnEvent", function(_, event, ...)
            local handler = UNIT_EVENT_HANDLERS[event]
            if handler then self[handler](self, event, ...) end
        end)
        -- RegisterUnitEvent allows max two units; target health (health bar only)
        -- gets its own frame.
        self.targetHealthFrame = CreateFrame("Frame")
        self.targetHealthFrame:SetScript("OnEvent", function(_, event, unit)
            self:OnHealthChanged(event, unit)
        end)
        -- Party health: edge triggers for the group-heal pass. The PAYLOAD IS
        -- NEVER READ - the handler only marks the defensive queue dirty, and the
        -- rebuild asks Blizzard's alert manager who is low. Two frames because
        -- RegisterUnitEvent takes at most two units each.
        -- EDGE, not event: UNIT_HEALTH on four party members is a near-continuous
        -- stream in group combat, and dirtying on every event ran the full
        -- defensive rebuild at the update-loop cap instead of its 0.5s combat
        -- cadence. Every consumer keys off the low COUNT (heal injection: >0,
        -- emergency claim: >= threshold), which changes only at threshold
        -- crossings - so dirty only when the count itself moves. The count read
        -- is plain and allocation-free (see GetPartyLowCount).
        self.partyHealthFrames = { CreateFrame("Frame"), CreateFrame("Frame") }
        for _, f in ipairs(self.partyHealthFrames) do
            f:SetScript("OnEvent", function()
                -- Cheap gate first: no heal surface, no work. isDisabledMode is
                -- checked because live health events re-showing hidden icons in
                -- disabled mode is a bug this addon has had once already.
                if self.isDisabledMode then return end
                local p = self.db and self.db.profile
                if not (p and p.healing and p.healing.enabled) then return end
                local n = (BlizzardAPI and BlizzardAPI.GetPartyLowCount
                    and BlizzardAPI.GetPartyLowCount()) or 0
                if n ~= lastPartyLowCount then
                    lastPartyLowCount = n
                    defensiveQueueDirty = true
                end
            end)
        end
    end
    local uf = self.unitEventFrame
    uf:RegisterUnitEvent("UNIT_HEALTH", "player", "pet")
    uf:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    uf:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    uf:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    uf:RegisterUnitEvent("UNIT_AURA", "player", "target")
    uf:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    uf:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    uf:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    uf:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    uf:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    uf:RegisterUnitEvent("UNIT_PET", "player")
    uf:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    uf:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    self.targetHealthFrame:RegisterUnitEvent("UNIT_HEALTH", "target")
    self.partyHealthFrames[1]:RegisterUnitEvent("UNIT_HEALTH", "party1", "party2")
    self.partyHealthFrames[2]:RegisterUnitEvent("UNIT_HEALTH", "party3", "party4")

    -- ── Action bar + keybinds ───────────────────────────────────────────────────
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "OnActionBarChanged")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "OnActionBarChanged")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "OnSpecialBarChanged")
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsUpdated")
    self:RegisterEvent("GAME_PAD_CONNECTED", "OnGamePadChanged")
    self:RegisterEvent("GAME_PAD_DISCONNECTED", "OnGamePadChanged")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")

    -- ── Auras + form state ─────────────────────────────────────────────────────────
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshiftFormChanged")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", "OnShapeshiftFormsRebuilt")  -- GetShapeshiftForm() returns nil until this fires
    -- Throttle to prevent flicker from buff-based spell overrides
    self.lastAuraInvalidation = 0

    -- ── Assisted combat signals + proc glows ───────────────────────────────────────
    self:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST", "ForceUpdate")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowChange")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowChange")
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellIconChanged")

    -- ── Target + range + usability ────────────────────────────────────────────────
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("ACTION_USABLE_CHANGED", "OnActionUsableChanged")

    -- ── Pet + equipment ────────────────────────────────────────────────────────────
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagUpdate")

    -- ── Vehicle + override bars ──────────────────────────────────────────────────
    -- Vehicle enter/exit rides on UNIT_ENTERED/EXITED_VEHICLE (unit-filtered);
    -- override/possess events below cover bar-content changes.
    self:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR", "OnOverrideBarChanged")
    self:RegisterEvent("UPDATE_POSSESS_BAR",        "OnPossessBarChanged")

    -- ── Encounter / instance ──────────────────────────────────────────────────────
    -- 12.0.5: aura instance IDs re-randomize at encounter/M+/PvP start - flush stale maps
    self:RegisterEvent("ENCOUNTER_START",      "OnEncounterStart")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnEncounterStart")
    self:RegisterEvent("PVP_MATCH_ACTIVE",     "OnEncounterStart")

    if EventRegistry then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            self:ForceUpdate()
        end, self)
        EventRegistry:RegisterCallback("AssistedCombatManager.RotationSpellsUpdated", function()
            if SpellQueue then
                if BlizzardAPI and BlizzardAPI.ClearAvailabilityCache then
                    BlizzardAPI.ClearAvailabilityCache()
                end
                if SpellQueue.InvalidateRotationCache then
                    SpellQueue.InvalidateRotationCache()
                end
            end
            -- Re-cache base cooldowns for any new rotation spells (talent change, etc.)
            if BlizzardAPI and BlizzardAPI.PreCacheRotationCooldowns then
                BlizzardAPI.PreCacheRotationCooldowns()
            end
            -- BOTH queues. This fires when Blizzard's spell data becomes real after a
            -- reload, and the availability cache just cleared above is what the DEFENSIVE
            -- build gates on too - but only the offensive queue was marked dirty here, so
            -- the defensive cluster's first correct build waited on the 1s idle timer
            -- and showed up seconds after the rotation (user-reported).
            self:ForceUpdateAll()
        end, self)
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function()
            self:ForceUpdate()
        end, self)
    end
    
    -- Healer specs are enabled by default (the assist queue is their damage
    -- rotation; heals are filtered from the tail). Earlier versions auto-wrote
    -- "DISABLED" for healer specs at first run - characters carrying that
    -- stored state keep it, and the one-time hint in OnSpecChange plus
    -- /jac enable are their way back in.
    self.db.char.firstRun = false

    self:ScheduleTimer("ValidateAssistedCombatSetup", 2)
end

function JustAC:InitializeCaches()
    if FormCache and FormCache.OnPlayerLogin then
        FormCache.OnPlayerLogin()
    end

    if ActionBarScanner then
        if ActionBarScanner.RebuildKeybindCache then
            ActionBarScanner.RebuildKeybindCache()
        end

        if ActionBarScanner.OnSpecialBarChanged then
            ActionBarScanner.OnSpecialBarChanged()
        end
    end

    self:InvalidateCaches({spells = true, macros = true, auras = true})

    if BlizzardAPI and BlizzardAPI.RefreshFeatureAvailability then
        BlizzardAPI.RefreshFeatureAvailability()
    end

    -- Seed debug mode from profile (event-only cache, no timer)
    if BlizzardAPI and BlizzardAPI.RefreshDebugMode then
        BlizzardAPI.RefreshDebugMode()
    end

    -- Rebuild item-spell cache after short delay to cover cold item data on login
    self:ScheduleTimer(function()
        if BlizzardAPI and BlizzardAPI.RefreshItemSpellCache then
            BlizzardAPI.RefreshItemSpellCache()
        end
    end, 3)
end

function JustAC:OnCVarUpdate(event, cvarName, value)
    if cvarName == "assistedMode" or cvarName == "assistedCombatHighlight" or cvarName == "assistedCombatIconUpdateRate" then
        self:ValidateAssistedCombatSetup()
        -- Invalidate cached update rate so OnUpdate picks up the new CVar value immediately
        if cvarName == "assistedCombatIconUpdateRate" then
            cachedUpdateRate = nil
        end
    end
end

function JustAC:ValidateAssistedCombatSetup()
    if BlizzardAPI and BlizzardAPI.ValidateAssistedCombatSetup then
        BlizzardAPI.ValidateAssistedCombatSetup()
    end
end

function JustAC:OnDisable()
    self:StopUpdates()
    self:CancelAllTimers()

    -- AceEvent unregisters its own events on disable; mirror for our unit frames
    if self.unitEventFrame then self.unitEventFrame:UnregisterAllEvents() end
    if self.targetHealthFrame then self.targetHealthFrame:UnregisterAllEvents() end
    
    if EventRegistry then
        EventRegistry:UnregisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", self)
        EventRegistry:UnregisterCallback("AssistedCombatManager.RotationSpellsUpdated", self)
        EventRegistry:UnregisterCallback("AssistedCombatManager.OnSetActionSpell", self)
    end
    
    -- Tear down nameplate overlay (restores nameplateShowEnemies CVar)
    if UINameplateOverlay then UINameplateOverlay.Destroy(self) end

    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

-- Minimal mode: stops updates but keeps spec change listener active
function JustAC:EnterDisabledMode()
    if self.isDisabledMode then return end
    self.isDisabledMode = true

    self:StopUpdates()

    if self.mainFrame then
        self.mainFrame:Hide()
    end

    local profile = self:GetProfile()
    local isDetached = profile and profile.defensives and profile.defensives.detached
    if self.defensiveFrame and not isDetached then
        self.defensiveFrame:Hide()
    end

    -- Hide defensive icons (when not detached; detached frame shows regardless of displayMode)
    if not isDetached and self.defensiveIcons then
        for _, icon in ipairs(self.defensiveIcons) do
            if icon then icon:Hide() end
        end
    end

    -- Hide health bar
    if UIHealthBar and UIHealthBar.Hide then
        UIHealthBar.Hide()
    end
    if UIHealthBar and UIHealthBar.HidePet then
        UIHealthBar.HidePet()
    end
    if UIHealthBar and UIHealthBar.HideTarget then
        UIHealthBar.HideTarget()
    end
    if UIHealthBar and UIHealthBar.HidePower then
        UIHealthBar.HidePower()
    end

    -- Hide nameplate overlay
    if UINameplateOverlay then UINameplateOverlay.HideAll() end

    self:DebugPrint("Entered disabled mode for current spec")
end

function JustAC:ExitDisabledMode()
    if not self.isDisabledMode then return end
    self.isDisabledMode = false

    self:StartUpdates()

    if self.mainFrame then
        self.mainFrame:Show()
    end

    if self.defensiveFrame then
        self.defensiveFrame:Show()
    end

    -- Restore health bar if setting is enabled
    local profile = self:GetProfile()
    if UIHealthBar and profile and profile.defensives then
        if profile.defensives.showHealthBar and UIHealthBar.Show then
            UIHealthBar.Show()
        end
        if profile.defensives.showPetHealthBar and UIHealthBar.UpdatePetVisibility then
            UIHealthBar.UpdatePetVisibility(self)
        end
        if profile.defensives.showTargetHealthBar and UIHealthBar.UpdateTargetVisibility then
            UIHealthBar.UpdateTargetVisibility(self)
        end
        -- Power bars: EnterDisabledMode hides them and nothing else Show()s the
        -- primary (UpdatePower early-outs while hidden) - the secondary would
        -- re-show alone on the next UNIT_DISPLAYPOWER, orphaning its segments.
        if UIHealthBar.ShowPower then
            UIHealthBar.ShowPower(self)
        end
    end

    -- Restore nameplate overlay if enabled
    if UINameplateOverlay then UINameplateOverlay.UpdateAnchor(self) end

    -- Re-enable warm start: clear any stale startup/disabled-period availability
    -- cache entries before first target so defensives don't appear one cadence late.
    self:InvalidateCaches({spells = true})
    self:OnHealthChanged(nil, "player")

    self:ForceUpdateAll()
    self:DebugPrint("Exited disabled mode")
end

function JustAC:RefreshConfig()
    -- Migrate old profile-level data (blacklist/hotkeys/panelLocked) if switching to an un-migrated profile
    self:NormalizeSavedData()
    -- Situational sets: the OFF flags are session state, but membership lives on the
    -- PROFILE - a profile switch with a set off would silently hide the NEW profile's
    -- members under the old flag. Every set comes back on, same as login/spec change.
    if SpellQueue and SpellQueue.ResetSets then SpellQueue.ResetSets() end
    if UIRenderer and UIRenderer.RefreshSetIndicator then UIRenderer.RefreshSetIndicator(self) end
    -- Blacklist/spec profiles are character-specific; hotkey overrides travel with the profile
    self:InitializeDefensiveSpells()
    -- Burst-trigger overrides live on the profile; the spec key alone doesn't
    -- move on a profile switch, so wipe the cache explicitly.
    if SpellQueue and SpellQueue.InvalidateBurstTriggers then
        SpellQueue.InvalidateBurstTriggers()
    end
    -- FULL rotation invalidation (no keepSetupIfUnchanged): Always Show / Hold Until
    -- Charged pins live on the profile, and the setup pass that resolves them is
    -- skipped for an unchanged spec-level list - a profile switch must force it.
    if SpellQueue and SpellQueue.InvalidateRotationCache then
        SpellQueue.InvalidateRotationCache()
    end

    self:UpdateFrameSize()
    if self.mainFrame then
        local profile = self:GetProfile()
        self.mainFrame:ClearAllPoints()
        UIFrameFactory.ApplySavedPosition(self, profile)
        -- Save before anchoring so we preserve UIParent-relative coords as fallback
        self:SavePosition()
        if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
    end
    if self.defensiveFrame then
        local profile = self:GetProfile()
        local defPos = profile.defensives and profile.defensives.detachedPosition
        if defPos then
            self.defensiveFrame:ClearAllPoints()
            self.defensiveFrame:SetPoint(defPos.point or "CENTER", UIParent, defPos.point or "CENTER", defPos.x or 0, defPos.y or 100)
        end
    end
    if UINameplateOverlay then
        UINameplateOverlay.Destroy(self)
        UINameplateOverlay.Create(self)
    end

    -- Refresh debug mode cache (profile may have different debugMode value)
    if BlizzardAPI and BlizzardAPI.RefreshDebugMode then
        BlizzardAPI.RefreshDebugMode()
    end

    -- Refresh options panel dynamic entries if it's been initialized
    if Options and Options.RefreshAllDynamic then
        Options.RefreshAllDynamic(self)
    end
end

-- Clean up spec-profile mappings that reference a deleted profile.
-- AceDB fires OnProfileDeleted(db, profileKey) after removing the profile data.
function JustAC:OnProfileDeleted(event, db, deletedName)
    if not self.db or not self.db.char or not self.db.char.specProfiles then return end
    local changed = false
    for specIndex, profileName in pairs(self.db.char.specProfiles) do
        if profileName == deletedName then
            self.db.char.specProfiles[specIndex] = nil
            changed = true
        end
    end
    if changed then
        self:DebugPrint("Cleared spec-profile mappings for deleted profile: " .. tostring(deletedName))
        NotifyOptionsChange()
    end
end

-- Defensive Engine wrapper methods (delegated to DefensiveEngine module)
function JustAC:OnHealthChanged(event, unit)
    -- Real player UNIT_HEALTH events (not the synthetic periodic calls with
    -- event=nil) stamp the never-secret "health is changing" activity signal:
    -- OOC regen fires these while below full and goes silent at full.
    if event and unit == "player" and BlizzardAPI and BlizzardAPI.NotePlayerHealthEvent then
        BlizzardAPI.NotePlayerHealthEvent()
    end
    -- Target health bar lives outside the defensive system; handle it here so
    -- target health never enters DefensiveEngine (which only acts on player/pet).
    if unit == "target" then
        if UIHealthBar and UIHealthBar.UpdateTarget then UIHealthBar.UpdateTarget(self) end
        return
    end
    -- Propagate the handled/skipped verdict: false = the 0.1s rebuild throttle
    -- swallowed this call, so the update loop must keep its dirty flag and retry.
    if DefensiveEngine then return DefensiveEngine.OnHealthChanged(self, event, unit) end
end

-- Player power/resource bar: value on UNIT_POWER_FREQUENT, color on UNIT_DISPLAYPOWER
-- (power-type change, e.g. Druid form). Player-only; throttled inside UIHealthBar.
function JustAC:OnPowerChanged(event, unit)
    if unit ~= "player" then return end
    if UIHealthBar and UIHealthBar.UpdatePower then UIHealthBar.UpdatePower(self) end
    if UINameplateOverlay and UINameplateOverlay.UpdatePowerBar then UINameplateOverlay.UpdatePowerBar(self) end
end

function JustAC:OnPowerTypeChanged(event, unit)
    if unit ~= "player" then return end
    if UIHealthBar and UIHealthBar.UpdatePowerColor then UIHealthBar.UpdatePowerColor(self) end
    if UIHealthBar and UIHealthBar.UpdatePower then UIHealthBar.UpdatePower(self) end
    if UINameplateOverlay and UINameplateOverlay.UpdatePowerColor then UINameplateOverlay.UpdatePowerColor(self) end
end

function JustAC:InitializeDefensiveSpells()
    if DefensiveEngine then
        DefensiveEngine.InitializeDefensiveSpells(self)
    end
    if GapCloserEngine then
        GapCloserEngine.InitializeGapClosers(self)
    end
    -- Migrate the retired burst-injection settings: per-spec trigger overrides feed
    -- the new burst-trigger list; the old table is dropped (injection lists retire).
    -- The cue glow itself now defaults ON, so no opt-in carry-over is needed.
    local profile = self.db and self.db.profile
    if profile and profile.burstInjection then
        local oldTriggers = profile.burstInjection.triggerSpells
        if oldTriggers then
            for specKey, list in pairs(oldTriggers) do
                if type(list) == "table" and #list > 0 then
                    profile.burstTriggers = profile.burstTriggers or {}
                    if not profile.burstTriggers[specKey] then
                        local copy = {}
                        for i, id in ipairs(list) do copy[i] = id end
                        profile.burstTriggers[specKey] = copy
                    end
                end
            end
        end
        profile.burstInjection = nil
    end
    -- Warm the base-cooldown cache for the rotation while we're out of combat
    -- (base CDs are secret in combat; the cache backs IsSpellReady's fallbacks).
    if BlizzardAPI and BlizzardAPI.PreCacheRotationCooldowns then
        BlizzardAPI.PreCacheRotationCooldowns()
    end
    if CustomQueueOpts and CustomQueueOpts.EnsureInitialized then
        CustomQueueOpts.EnsureInitialized(self)
    end
end
function JustAC:RestoreDefensiveDefaults(listType)
    if DefensiveEngine then DefensiveEngine.RestoreDefensiveDefaults(self, listType) end
end
function JustAC:GetClassSpellList(listKey)
    if DefensiveEngine then return DefensiveEngine.GetClassSpellList(self, listKey) end
end

function JustAC:UpdateAlternateControlState()
    -- Controlling a vehicle or possessing an NPC replaces WHO you cast as: the player's own
    -- rotation is meaningless there, so nothing renders at all.
    --
    -- An override action BAR on its own is deliberately NOT in this list. A debuff can swap
    -- your buttons out for a few seconds while you stay yourself (an aura applying
    -- OVERRIDE_SPELLS), and the rotation is exactly what you press the moment it ends -
    -- hiding the whole queue for that reads as the addon breaking, right when someone is
    -- watching it to see what comes next. Those abilities are merely uncastable, which is
    -- what the usability tint says: the entries hold their place, dimmed, and light back up
    -- when the debuff falls off. Same treatment as loss of control - see
    -- BlizzardAPI.IsPlayerAbilityLockout, which keeps them from being FILTERED for being
    -- uncastable. Quest bars that override without a vehicle land here too, and a dimmed
    -- queue beside them is the cheaper mistake.
    self.playerInAlternateControl = (UnitHasVehicleUI and UnitHasVehicleUI("player") or false)
        or (HasVehicleActionBar and HasVehicleActionBar() or false)
        or (IsPossessBarVisible and IsPossessBarVisible() or false)
end

function JustAC:LoadModules()
    -- Each module already resolved its own inter-module deps at load time.
    -- This function resolves them into JustAC.lua's own local upvalues,
    -- which can't be done at file-load time because JustAC.lua loads last.
    UIRenderer = LibStub("JustAC-UIRenderer", true)
    UIFrameFactory = LibStub("JustAC-UIFrameFactory", true)
    UIAnimations = LibStub("JustAC-UIAnimations", true)
    UIHealthBar = LibStub("JustAC-UIHealthBar", true)
    SpellQueue = LibStub("JustAC-SpellQueue", true)
    ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    FormCache = LibStub("JustAC-FormCache", true)
    Options = LibStub("JustAC-Options", true)
    MacroParser = LibStub("JustAC-MacroParser", true)
    RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    SpellDB = LibStub("JustAC-SpellDB", true)
    DotTracker = LibStub("JustAC-DotTracker", true)
    CustomQueueOpts = LibStub("JustAC-OptionsCustomQueue", true)
    SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
    MaintenanceTracker = LibStub("JustAC-MaintenanceTracker", true)
    CastInterruptTracker = LibStub("JustAC-CastInterruptTracker", true)
    
    if not UIRenderer then self:Print("Error: UIRenderer module not found"); self:Disable(); return end
    if not UIFrameFactory then self:Print("Error: UIFrameFactory module not found"); self:Disable(); return end
    if not UIAnimations then self:Print("Error: UIAnimations module not found"); self:Disable(); return end
    if not SpellQueue then self:Print("Error: SpellQueue module not found"); self:Disable(); return end
    if not BlizzardAPI then self:Print("Error: BlizzardAPI module not found"); self:Disable(); return end
    if not ActionBarScanner then self:Print("Warning: ActionBarScanner module not found"); ActionBarScanner = {} end
    if not FormCache then self:Print("Warning: FormCache module not found") end
    if not MacroParser then self:Print("Warning: MacroParser module not found") end
    if not RedundancyFilter then self:Print("Warning: RedundancyFilter module not found") end
    UINameplateOverlay = LibStub("JustAC-UINameplateOverlay", true)
    if not UINameplateOverlay then self:Print("Warning: UINameplateOverlay module not found") end
    DefensiveEngine = LibStub("JustAC-DefensiveEngine", true)
    if not DefensiveEngine then self:Print("Warning: DefensiveEngine module not found") end
    GapCloserEngine = LibStub("JustAC-GapCloserEngine", true)
    if not GapCloserEngine then self:Print("Warning: GapCloserEngine module not found") end
    TargetFrameAnchor = LibStub("JustAC-TargetFrameAnchor", true)
    if not TargetFrameAnchor then self:Print("Warning: TargetFrameAnchor module not found") end
    KeyPressDetector = LibStub("JustAC-KeyPressDetector", true)
    if not KeyPressDetector then self:Print("Warning: KeyPressDetector module not found") end
end

function JustAC:SetHotkeyOverride(spellID, hotkeyText)
    if not spellID or spellID == 0 then return end
    local profile = self:GetProfile()
    if not profile then return end

    if not profile.hotkeyOverrides then
        profile.hotkeyOverrides = {}
    end

    local displayName
    if spellID < 0 then
        local itemName = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(-spellID)
        displayName = itemName or ("Item #" .. (-spellID))
    else
        local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
        displayName = spellInfo and spellInfo.name or "Unknown"
    end

    if hotkeyText and hotkeyText:trim() ~= "" then
        profile.hotkeyOverrides[spellID] = hotkeyText:trim()
        self:DebugPrint("Hotkey: " .. displayName .. " = '" .. hotkeyText:trim() .. "'")
    else
        profile.hotkeyOverrides[spellID] = nil
        self:DebugPrint("Hotkey removed: " .. displayName)
    end

    if Options and Options.UpdateHotkeyOverrideOptions then
        Options.UpdateHotkeyOverrideOptions(self)
    end

    -- Icons cache their hotkey string and re-read only when told to; an override typed
    -- for a spell already showing a key never appeared until a binding change or icon
    -- reuse (audit-found). The hotkeys group clears every surface's cache.
    self:InvalidateCaches({hotkeys = true})
    self:ForceUpdate()
end

function JustAC:GetHotkeyOverride(spellID)
    if not spellID or spellID == 0 then return nil end
    local profile = self:GetProfile()
    if not profile or not profile.hotkeyOverrides then return nil end
    return profile.hotkeyOverrides[spellID]
end

function JustAC:OpenHotkeyOverrideDialog(spellID)
    if UIRenderer and UIRenderer.OpenHotkeyOverrideDialog then
        UIRenderer.OpenHotkeyOverrideDialog(self, spellID)
    end
end

function JustAC:GetProfile() return self.db and self.db.profile end

-- Per-category cache invalidation callbacks. Defined once; called by InvalidateCaches.
-- Closures capture the module upvalues by reference, so they see post-LoadModules values.
local CACHE_INVALIDATORS = {
    spells = function()
        if BlizzardAPI and BlizzardAPI.ClearSpellCache then BlizzardAPI.ClearSpellCache() end
        if BlizzardAPI and BlizzardAPI.ClearAvailabilityCache then BlizzardAPI.ClearAvailabilityCache() end
    end,
    macros = function()
        if MacroParser and MacroParser.InvalidateMacroCache then MacroParser.InvalidateMacroCache() end
    end,
    hotkeys = function()
        if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then ActionBarScanner.InvalidateHotkeyCache() end
        if UIRenderer and UIRenderer.InvalidateHotkeyCache then UIRenderer.InvalidateHotkeyCache() end
        if UINameplateOverlay and UINameplateOverlay.InvalidateHotkeyCache then UINameplateOverlay.InvalidateHotkeyCache() end
    end,
    forms = function()
        if FormCache and FormCache.InvalidateCache then FormCache.InvalidateCache() end
        if FormCache and FormCache.InvalidateSpellMapping then FormCache.InvalidateSpellMapping() end
    end,
    auras = function()
        if RedundancyFilter and RedundancyFilter.InvalidateCache then RedundancyFilter.InvalidateCache() end
    end,
}

-- Centralized cache invalidation with flags
function JustAC:InvalidateCaches(flags)
    flags = flags or {}
    if flags.all then
        for _, invalidate in pairs(CACHE_INVALIDATORS) do invalidate() end
        return
    end
    for cat, invalidate in pairs(CACHE_INVALIDATORS) do
        if flags[cat] then invalidate() end
    end
end

function JustAC:ToggleSpellBlacklist(spellID)
    if SpellQueue and SpellQueue.ToggleSpellBlacklist then
        SpellQueue.ToggleSpellBlacklist(spellID)
        self:ForceUpdate()
    end
end


function JustAC:UpdateSpellQueue()
    if self.isDisabledMode then return end
    if not self.db or not self.db.profile or self.db.profile.isManualMode or not self.mainFrame or not SpellQueue or not UIRenderer then return end

    -- Suppress queue while controlling a vehicle or possessing an NPC.
    -- Our rotation spells are meaningless in these states; render an empty queue
    -- so all icons hide cleanly through the normal renderer path.
    if self.playerInAlternateControl then
        if SpellQueue.NoteQueueBlank then
            SpellQueue.NoteQueueBlank("alternate control (vehicle / possess)")
        end
        -- EMPTY_QUEUE is a shared read-only constant (renderers only iterate it);
        -- two fresh tables per tick here ran at 40-66/sec for a whole vehicle ride.
        UIRenderer.RenderSpellQueue(self, EMPTY_QUEUE)
        if UINameplateOverlay then UINameplateOverlay.Render(self, EMPTY_QUEUE) end
        return
    end

    -- Always build queue to keep caches warm (redundancy filter, aura tracking, etc.)
    -- even when frame is hidden - this ensures instant response when frame becomes visible
    -- Renderer will skip expensive operations (hotkey lookups, icon updates) when hidden
    local currentSpells = SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue() or {}
    if UIRenderer and UIRenderer.RenderSpellQueue then
        UIRenderer.RenderSpellQueue(self, currentSpells)
    end
    if UINameplateOverlay then
        UINameplateOverlay.Render(self, currentSpells)
        -- Re-render cached defensive icons on the same tick so both queues
        -- appear simultaneously (defensive evaluation runs on a slower cadence).
        if UINameplateOverlay.RefreshDefensives then
            UINameplateOverlay.RefreshDefensives(self)
        end
    end
end

function JustAC:PLAYER_ENTERING_WORLD()
    self:InitializeCaches()

    -- Re-apply the cosmetic Cooldown Manager hide. Blizzard rebuilds those viewers across
    -- loading screens, so a one-shot at login would be lost on the first zone change.
    if MaintenanceTracker and MaintenanceTracker.ApplyViewerVisibility and self.db and self.db.profile then
        MaintenanceTracker.ApplyViewerVisibility(self.db.profile)
    end

    -- Re-evaluate vehicle/possess state after loading screens (may enter a phased vehicle zone).
    self:UpdateAlternateControlState()

    -- Refresh creature type cache in case there is a pre-existing target on world enter.
    if BlizzardAPI then
        -- Clear instance CC immunity cache on zone/instance change so stale data
        -- from the previous instance doesn't suppress valid CC targets.
        if BlizzardAPI.ResetInstanceCCCache then BlizzardAPI.ResetInstanceCCCache() end
        BlizzardAPI.RefreshTargetCreatureType()
    end

    -- Apply spec-based profile/disabled state on world entry (not just on spec change events)
    self:OnSpecChange()

    -- Re-check bounds after loading screens (resolution/scale may differ per character)
    if TargetFrameAnchor then TargetFrameAnchor.ClampFrameToScreen(self) end

    -- Re-check whether the standard TargetFrame is active (addons may replace it)
    if TargetFrameAnchor then TargetFrameAnchor.InvalidateCache() end
    -- Re-assert target frame anchor after loading screens (WoW can reset frame positions)
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end

    -- Docking state decides whether the target health bar is built at all (it would
    -- duplicate the target frame's own readout), and the re-check above can flip it -
    -- e.g. a unit-frame addon that loaded since. Rebuild so the bar matches.
    if UIHealthBar and UIHealthBar.UpdateTargetSize then UIHealthBar.UpdateTargetSize(self) end

    self:ForceUpdateAll()

    -- API may not return spells immediately after PLAYER_ENTERING_WORLD.
    -- Clear availability cache so stale false entries from the initial query
    -- (when spell APIs weren't ready yet) don't suppress the defensive queue.
    C_Timer.After(1.0, function()
        self:InvalidateCaches({spells = true})
        self:ForceUpdateAll()
    end)
end

--- Re-resolve interrupt spell list from SpellDB.
--- In combat, IsSpellAvailable() may return false due to 12.0 secret restrictions,
--- which would wipe a previously good list. Defer to PLAYER_REGEN_ENABLED instead.
function JustAC:RefreshInterruptSpells()
    if UnitAffectingCombat("player") then
        self.interruptRefreshPending = true
        return
    end
    self.interruptRefreshPending = nil
    local newList = SpellDB and SpellDB.ResolveInterruptSpells and SpellDB.ResolveInterruptSpells()
    if newList then
        self.resolvedInterrupts = newList
    end
    if SpellDB and SpellDB.ResolveSootheSpells then
        self.resolvedSoothe = SpellDB.ResolveSootheSpells()  -- nil for non-soothe classes; refreshes on talent change
    end
    if UINameplateOverlay and UINameplateOverlay.RefreshInterruptSpells then
        UINameplateOverlay.RefreshInterruptSpells()
    end
end

function JustAC:OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- First-engage warmup: availability cache can contain startup false entries
        -- (before spell APIs are fully ready), which suppresses defensives until
        -- a later refresh. Clear on combat entry so first target evaluates fresh.
        if BlizzardAPI and BlizzardAPI.ClearAvailabilityCache then
            BlizzardAPI.ClearAvailabilityCache()
        end
        -- Entering combat: animate glows
        if UIRenderer and UIRenderer.SetCombatState then
            UIRenderer.SetCombatState(true)
        end
        -- Force-refresh feature availability immediately (secrets become active on combat entry)
        if BlizzardAPI and BlizzardAPI.RefreshFeatureAvailability then
            BlizzardAPI.RefreshFeatureAvailability()
        end
        if UIAnimations and UIAnimations.ResumeAllGlows then
            UIAnimations.ResumeAllGlows(self)
        end
        self:ForceUpdateAll()  -- Update both combat and defensive queues
        NotifyOptionsChange()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Open the post-combat bridge window: covers the few-second delay before OOC
        -- health regen starts ticking, after which sustained-regen detection carries the
        -- top-off heal reminder (see PrecombatEngine hurt detection / StateHelpers).
        if BlizzardAPI and BlizzardAPI.NotePlayerLeftCombat then
            BlizzardAPI.NotePlayerLeftCombat()
        end
        -- Backfill instance CC cache: if a CC failed on a target whose NPC ID
        -- wasn't known during combat (tab-targeted mid-fight), BackfillCCImmunity
        -- reads the GUID now that combat ended and persists the mob type.
        -- Must run BEFORE RefreshTargetCreatureType clears per-target state.
        if BlizzardAPI and BlizzardAPI.BackfillCCImmunity then
            BlizzardAPI.BackfillCCImmunity()
        end
        -- UnitCreatureType() is readable again out of combat; refresh for next pull
        if BlizzardAPI and BlizzardAPI.RefreshTargetCreatureType then
            BlizzardAPI.RefreshTargetCreatureType()
        end
        -- Reset per-target CC-failure learning for the next combat session
        -- (instance-level NPC ID cache is intentionally preserved across pulls)
        if BlizzardAPI and BlizzardAPI.ResetCCFailureLearning then
            BlizzardAPI.ResetCCFailureLearning()
        end
        if UIRenderer and UIRenderer.SetCombatState then
            UIRenderer.SetCombatState(false)
        end
        -- Force-refresh feature availability immediately (secrets lifted on combat exit)
        if BlizzardAPI and BlizzardAPI.RefreshFeatureAvailability then
            BlizzardAPI.RefreshFeatureAvailability()
        end
        if UIAnimations and UIAnimations.PauseAllGlows then
            UIAnimations.PauseAllGlows(self)
        end
        self:InvalidateCaches({auras = true})
        if RedundancyFilter and RedundancyFilter.ClearActivationTracking then
            RedundancyFilter.ClearActivationTracking()
        end
        -- Drop DoT tracking so no stale suppression carries into the next pull.
        if DotTracker and DotTracker.Reset then
            DotTracker.Reset()
        end
        -- Pre-cache base cooldowns for rotation spells (secret in combat)
        if BlizzardAPI and BlizzardAPI.PreCacheRotationCooldowns then
            BlizzardAPI.PreCacheRotationCooldowns()
        end
        -- Check if custom queue is stale (rotation changed since last snapshot)
        if CustomQueueOpts and CustomQueueOpts.CheckStaleNotification then
            CustomQueueOpts.CheckStaleNotification(self)
        end
        -- Re-resolve interrupt spells if deferred from combat
        if self.interruptRefreshPending then
            self:RefreshInterruptSpells()
        end
        -- Re-apply anchor in case the target frame moved during combat.
        if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
        self:ForceUpdateAll()
        NotifyOptionsChange()
    end
end

function JustAC:OnSpecChange(event, unit)
    -- PLAYER_SPECIALIZATION_CHANGED also fires for group members mid-combat;
    -- only the player's spec affects our state. (Also called directly, no args.)
    if unit and unit ~= "player" then return end
    local newSpec = GetSpecialization()
    if not newSpec then return end

    -- Re-run migrations now that the spec is KNOWN. The blacklist migrations key old data
    -- under the current spec, so at OnInitialize (ADDON_LOADED, spec often still nil on a
    -- fresh login) they can only skip - leaving a pre-4.x flat blacklist unconsulted for
    -- the whole session. Every helper is a no-op once migrated, so this is a few table
    -- scans on a spec change, not repeated work.
    self:NormalizeSavedData()

    -- The tracked aura instance belongs to the OLD spec's maintenance buff; keeping it would
    -- point the new spec's slot at a buff it does not use.
    if MaintenanceTracker and MaintenanceTracker.Reset then MaintenanceTracker.Reset() end
    -- Layout anchors are computed once at frame creation; a spec swap can add or drop the
    -- maintenance slot, so re-seat them here the same way RefreshConfig does.
    self:UpdateFrameSize()

    if self.db.char.specProfilesEnabled and self.db.char.specProfiles then
        local target = self.db.char.specProfiles[newSpec]

        if target == "DISABLED" then
            -- One-line breadcrumb, once per spec per character: the first-run
            -- default disables healer specs silently, which reads as "addon
            -- broken" to anyone who installed it on a healer.
            if GetSpecializationRole(newSpec) == "HEALER" then
                self.db.char.healerHintShown = self.db.char.healerHintShown or {}
                if not self.db.char.healerHintShown[newSpec] then
                    self.db.char.healerHintShown[newSpec] = true
                    self:Print("This spec is disabled for this character. |cff2ecc71/jac enable|r turns the assist queue back on.")
                end
            end
            self:EnterDisabledMode()
            return
        end

        if self.isDisabledMode then
            self:ExitDisabledMode()
        end

        if target and target ~= "" and target ~= self.db:GetCurrentProfile() then
            -- SetProfile triggers RefreshConfig via OnProfileChanged callback;
            -- cache invalidation below still runs for spec-dependent state
            pcall(function() self.db:SetProfile(target) end)
        end
    elseif self.isDisabledMode then
        self:ExitDisabledMode()
    end

    if SpellQueue and SpellQueue.OnSpecChange then SpellQueue.OnSpecChange() end
    -- Situational sets come back ACTIVE on login and spec change (this handler runs on
    -- world entry too): a set switched off for last night's trash must not silently hide
    -- the same cooldowns from today's boss.
    if SpellQueue and SpellQueue.ResetSets then SpellQueue.ResetSets() end
    if UIRenderer and UIRenderer.RefreshSetIndicator then UIRenderer.RefreshSetIndicator(self) end
    -- Re-initialize all per-spec engines: defensive lists + cooldown-tracking
    -- registration, gap closers, custom queue defaults.
    -- The defensive re-init is required: without it the old spec's spells stay
    -- registered for cooldown tracking and the new spec's list is never seeded.
    self:InitializeDefensiveSpells()
    -- Check if custom queue is stale for the new spec
    if CustomQueueOpts and CustomQueueOpts.CheckStaleNotification then
        CustomQueueOpts.CheckStaleNotification(self)
    end
    -- Invalidate options spellbook cache so it rebuilds for the new spec
    if SpellSearch and SpellSearch.InvalidateSpellbookCache then
        SpellSearch.InvalidateSpellbookCache()
    end

    -- Keep dynamic options panels in sync with current spec when users are
    -- browsing Blizzard Settings (not only slash-open path).
    if Options and Options.RefreshAllDynamic then
        Options.RefreshAllDynamic(self)
    end

    -- forms=true: a spec swap can change which form spells you know, so refresh
    -- FormCache's form-spell map instead of waiting on its 30s TTL / a co-firing
    -- UPDATE_SHAPESHIFT_FORMS.
    self:InvalidateCaches({spells = true, macros = true, hotkeys = true, forms = true})
    self:RefreshInterruptSpells()
    self:ForceUpdateAll()
end

function JustAC:OnSpellsChanged()
    if SpellQueue and SpellQueue.OnSpellsChanged then SpellQueue.OnSpellsChanged() end
    -- The engine group-buff registry caches `isKnown`, which a talent or spec change
    -- moves. Its own 5s window would heal this eventually; flushing here means the
    -- buff list is right on the first rebuild after the change rather than the second.
    if BlizzardAPI and BlizzardAPI.FlushGroupBuffItems then
        BlizzardAPI.FlushGroupBuffItems()
    end
    -- Invalidate options spellbook cache so new/removed spells appear in search
    if SpellSearch and SpellSearch.InvalidateSpellbookCache then
        SpellSearch.InvalidateSpellbookCache()
    end
    self:InvalidateCaches({spells = true, macros = true, hotkeys = true})
    self:RefreshInterruptSpells()
    self:ForceUpdateAll()
end

function JustAC:OnSpellIconChanged()
    self:InvalidateCaches({hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormChanged()
    -- UPDATE_SHAPESHIFT_FORM also fires for stance-bar state updates (cooldowns,
    -- usability) with no actual form change - skip those, the invalidation below
    -- is expensive (full macro + hotkey rebuild).
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    if form == self.lastShapeshiftForm then return end
    self.lastShapeshiftForm = form
    -- Form changes (Druid Cat/Bear/etc.) can change which abilities are usable; clear the
    -- cached gap-closer list and reset the range debounce so the next GetGapCloserSpell
    -- re-evaluates fresh. (Melee detection is now form-independent via IsSpellInRange, so
    -- there's no action-slot to re-query.)
    if GapCloserEngine then
        GapCloserEngine.InvalidateGapCloserCache()
        GapCloserEngine.ClearRangeState()
    end
    if FormCache and FormCache.InvalidateCache then FormCache.InvalidateCache() end
    -- Defensive: bar-paging forms co-fire UPDATE_BONUS_ACTIONBAR which refreshes
    -- the scanner's form/bonus state hash, but don't depend on that ordering -
    -- make form state self-invalidating.
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then
        ActionBarScanner.OnSpecialBarChanged()
    end
    self:InvalidateCaches({macros = true, hotkeys = true})
    -- Include defensives: form gates usability (e.g. bear-only defensives),
    -- so re-evaluate immediately rather than waiting for the next health event.
    self:ForceUpdate(true)
end

function JustAC:OnShapeshiftFormsRebuilt()
    -- Form list rebuilt - indices may be renumbered, so the dedup compare in
    -- OnShapeshiftFormChanged must re-evaluate on the next event.
    self.lastShapeshiftForm = nil
    self:InvalidateCaches({forms = true, macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnUnitAura(event, unit, updateInfo)
    if unit == "target" then
        -- Target debuff changes feed only the DoT tracker (cast->instance bridge
        -- and live removal). Kept off the player-aura path below to avoid its
        -- cache invalidation churn on every enemy aura tick. Mark the queue dirty
        -- so a dropped/expiring DoT un-sinks promptly.
        if DotTracker and DotTracker.OnTargetAuraUpdate then
            if DotTracker.OnTargetAuraUpdate(unit, updateInfo) then
                self:MarkQueueDirty()
            end
        end
        return
    end
    if unit ~= "player" then return end

    -- Any player aura change (including mount removal) must break the mainHidden early
    -- exit in OnUpdate so the queue can re-evaluate IsMounted() / visibility conditions.
    self:MarkQueueDirty()

    -- Maintenance buff: bind a pending cast to its new aura instance, and catch removal so
    -- the button glows the moment the buff actually drops rather than on a guessed timer.
    if MaintenanceTracker and MaintenanceTracker.OnPlayerAuraUpdate then
        if MaintenanceTracker.OnPlayerAuraUpdate(updateInfo) then
            defensiveQueueDirty = true
        end
    end

    -- OOC the pre-combat suggestions and their click layers are AURA-driven (the eating aura,
    -- Well Fed, flask, poison...), so a player aura change has to rebuild the defensive queue
    -- too. Without this the mid-eat click disarm waits for the 0.5s idle cycle, leaving exactly
    -- the spam-click window that restarts the eat. OOC-gated: aura churn in combat is heavy and
    -- the pre-combat system is inactive there anyway.
    if not UnitAffectingCombat("player") then defensiveQueueDirty = true end

    -- 12.0: Pass updateInfo to RedundancyFilter for incremental instance map updates
    -- This captures addedAuras (new aura identity) and removedAuraInstanceIDs (cleanup)
    -- BEFORE cache invalidation, so the map is current when RefreshAuraCache runs
    if RedundancyFilter and RedundancyFilter.OnUnitAuraUpdate then
        RedundancyFilter.OnUnitAuraUpdate(updateInfo)
    end

    local now = GetTime()
    if now - (self.lastAuraInvalidation or 0) > 0.1 then
        self.lastAuraInvalidation = now
        self:InvalidateCaches({auras = true})
        -- Reset update timer in combat so proc-driven AC changes surface promptly
        -- instead of waiting for the next CVar-rate poll.  Throttled to 10x/sec
        -- by lastAuraInvalidation - safe even in heavy multi-aura combat.
        if UnitAffectingCombat("player") and self.updateTimeLeft then
            self.updateTimeLeft = 0
        end
    end
end

function JustAC:OnActionBarChanged(event, slot)
    local inCombat = UnitAffectingCombat("player")
    if not inCombat then
        local now = GetTime()
        if (now - lastOOCActionBarEvent) < OOC_ACTIONBAR_THROTTLE then
            spellQueueDirty = true
            defensiveQueueDirty = true
            return
        end
        lastOOCActionBarEvent = now
    end

    -- ACTIONBAR_SLOT_CHANGED fires constantly in cities (dynamic macro icons
    -- re-evaluating). A single-slot change only drops that slot's parsed macros;
    -- hotkey caches are spell-keyed so they're always cleared (a slot change can
    -- move a spell's best keybind), but they rebuild from the warm macro cache.
    if event == "ACTIONBAR_SLOT_CHANGED" and slot and slot > 0
        and MacroParser and MacroParser.InvalidateMacroSlot then
        MacroParser.InvalidateMacroSlot(slot)
        self:InvalidateCaches({hotkeys = true})
    else
        self:InvalidateCaches({hotkeys = true, macros = true})
    end
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    if ActionBarScanner and ActionBarScanner.InvalidateAssistedSlot then
        ActionBarScanner.InvalidateAssistedSlot()
    end
    -- In combat, dirty-flag only: [mod]-macro bursts fire this many times per
    -- second, and the immediate-wake path made each one a full pass. The poll
    -- picks the flag up within one tick; OOC keeps the immediate wake (no poll).
    if inCombat then
        spellQueueDirty = true
    else
        self:ForceUpdate()
    end
end

function JustAC:OnSpecialBarChanged()
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then ActionBarScanner.OnSpecialBarChanged() end
    -- Bonus-bar paging (Druid Cat/Bear, etc.) remaps the action slots, so the
    -- slot-usability cache and its slot->tracked-spell reverse map must refresh -
    -- OnShapeshiftFormChanged relies on this co-firing handler to do it.
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    self:ForceUpdate()
end

local function HandleAlternateControlChange(self)
    self:UpdateAlternateControlState()
    self:InvalidateCaches({macros = true, hotkeys = true})
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    -- Vehicle/override/possess bars change the slot universe: refresh the
    -- scanner's state hash and assisted slot too, not just macro/hotkey caches.
    if ActionBarScanner then
        if ActionBarScanner.OnSpecialBarChanged then ActionBarScanner.OnSpecialBarChanged() end
        if ActionBarScanner.InvalidateAssistedSlot then ActionBarScanner.InvalidateAssistedSlot() end
    end
    self:ForceUpdate()
end

function JustAC:OnVehicleChanged(event, unit)
    if unit ~= "player" then return end
    HandleAlternateControlChange(self)
end

function JustAC:OnOverrideBarChanged()
    -- Fires when an override action bar appears or disappears (quest vehicles, NPC control).
    HandleAlternateControlChange(self)
end

function JustAC:OnPossessBarChanged()
    -- Fires when Mind Control / possess effects begin or end.
    HandleAlternateControlChange(self)
end

--- WoW 12.0.5: aura instance IDs are re-randomized on encounter/M+ start.
--- Flush all instance→spell maps so stale IDs don't cause IsSpellRedundant()
--- to incorrectly suppress spells after the re-randomization.
--- The maps are rebuilt immediately from the next UNIT_AURA addedAuras batch.
function JustAC:OnEncounterStart()
    if RedundancyFilter and RedundancyFilter.FlushInstanceMaps then
        RedundancyFilter.FlushInstanceMaps()
    end
    -- Same 12.0.5 re-randomization affects the DoT tracker's target-debuff instance
    -- IDs; drop them so stale entries can't briefly mis-report a DoT as still live.
    if DotTracker and DotTracker.Reset then
        DotTracker.Reset()
    end
    -- And the maintenance slot's aura bindings: a stale instance dying reads as the
    -- buff dropping, which is the false "re-press" glow that module guards against.
    if MaintenanceTracker and MaintenanceTracker.FlushInstanceBindings then
        MaintenanceTracker.FlushInstanceBindings()
    end
    self:MarkQueueDirty()
end

function JustAC:OnBindingsUpdated()
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then
        ActionBarScanner.OnKeybindsChanged()
        self:ForceUpdate()
    end
end

function JustAC:OnGamePadChanged()
    -- Input device changed - re-select preferred bindings (auto mode)
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then
        ActionBarScanner.OnKeybindsChanged()
        self:ForceUpdate()
    end
end

function JustAC:OnProcGlowChange(event, spellID)
    if ActionBarScanner then
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
            if ActionBarScanner.OnProcShow then
                ActionBarScanner.OnProcShow(spellID)
            end
        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            if ActionBarScanner.OnProcHide then
                ActionBarScanner.OnProcHide(spellID)
            end
        end
    end

    -- Procs affect rotation and defensive priorities - ForceUpdateAll marks both
    -- queues dirty; OnUpdate loop handles rendering + defensive re-evaluation.
    self:ForceUpdateAll()
end

function JustAC:OnTargetChanged()
    -- Clear gap-closer range state on target switch.  The melee reference
    -- spell's slot is re-resolved lazily on the next GetGapCloserSpell call
    -- (via IsActionInRange), so no seeding pass is needed.
    if GapCloserEngine then
        GapCloserEngine.ClearRangeState()
    end
    -- Refresh per-target creature type cache for CC immunity detection.
    -- UnitCreatureType is secreted in combat; RefreshTargetCreatureType clears the
    -- cache on every target switch and only populates it when the value is readable.
    if BlizzardAPI then
        BlizzardAPI.RefreshTargetCreatureType()
        if BlizzardAPI.ResetTargetCastState then BlizzardAPI.ResetTargetCastState() end
    end
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
    if UINameplateOverlay then UINameplateOverlay.UpdateAnchor(self) end
    -- Target health bar: show/hide for the new target (hostile-only).
    if UIHealthBar and UIHealthBar.UpdateTargetVisibility then
        UIHealthBar.UpdateTargetVisibility(self)
    end
    -- Invalidate rotation cache so Blizzard is re-queried for the new target
    -- (prevents stale spells from previous target persisting). keepSetupIfUnchanged:
    -- the rotation is spec-level, so when the refetched list is identical the heavy
    -- setup half (pins / tracking / seeding) is skipped instead of rerun per swap.
    if SpellQueue and SpellQueue.InvalidateRotationCache then
        SpellQueue.InvalidateRotationCache(true)
    end
    -- DoT tracking is current-target only; the new target starts fresh.
    if DotTracker and DotTracker.Reset then
        DotTracker.Reset()
    end
    -- ForceUpdateAll marks both queues dirty; OnUpdate renders on next tick.
    self:ForceUpdateAll()
end

-- Shared by the cooldown and usability event handlers: both fire in bursts (~10x per
-- cast in combat via the GCD cascade, and again OOC as things come off cooldown). In
-- combat, dirty flags only - the 20-33Hz poll picks them up within one tick, and
-- zeroing the timer per event woke the loop on every frame of a burst. OOC, coalesce
-- the burst and let the 0.5s idle cycle pick it up rather than waking the loop
-- dozens of times.
local function MarkQueuesDirtyThrottled()
    if not UnitAffectingCombat("player") then
        local now = GetTime()
        if (now - lastOOCDirtyEvent) < OOC_EVENT_DIRTY_THROTTLE then
            return
        end
        lastOOCDirtyEvent = now
    end

    spellQueueDirty = true
    defensiveQueueDirty = true
end

function JustAC:OnActionUsableChanged(_, changes)
    -- Cache update is always immediate (used by GetActionBarUsability on next render).
    if BlizzardAPI and BlizzardAPI.OnActionUsableChanged then
        BlizzardAPI.OnActionUsableChanged(changes)
    end
    MarkQueuesDirtyThrottled()
end

-- Both handlers compare FRAMES, not unit tokens: the old UnitIsUnit(nameplateUnit, "target")
-- threw on addon-restricted maps (raids/dungeons), where plates churn most - see
-- BlizzardAPI.SafeUnitIsUnit. includeForbidden stays false to match UINameplateOverlay.
function JustAC:OnNamePlateAdded(_, nameplateUnit)
    local GetPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    -- `plate and` matters: with no target both lookups return nil and nil == nil would fire.
    local plate = GetPlate and nameplateUnit and GetPlate(nameplateUnit, false)
    if UINameplateOverlay and plate and plate == GetPlate("target", false) then
        UINameplateOverlay.UpdateAnchor(self)
        -- ForceUpdateAll so the defensive overlay re-renders as soon as the plate appears.
        -- ForceUpdate (DPS-only) isn't enough - defensive icons are driven by OnHealthChanged.
        self:ForceUpdateAll()
    end
end

function JustAC:OnNamePlateRemoved()
    -- The removed unit's plate is already released, so it cannot be compared to the
    -- target's. Detach only while anchored and the target no longer has a plate.
    if UINameplateOverlay and UINameplateOverlay.IsAnchored()
        and not (C_NamePlate and C_NamePlate.GetNamePlateForUnit("target", false)) then
        UINameplateOverlay.UpdateAnchor(self)
        self:ForceUpdate()  -- clear icons immediately
    end
end

-- Delegated to TargetFrameAnchor module (thin wrappers for the options panel)
function JustAC:IsStandardTargetFrame()
    if TargetFrameAnchor then return TargetFrameAnchor.IsStandardTargetFrame(self) end
    return false
end
function JustAC:UpdateTargetFrameAnchor()
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
end

function JustAC:OnPetChanged(event, unit)
    if unit ~= "player" then return end
    -- Pet summoned/dismissed/died - update pet health bar visibility and defensive queue
    if UIHealthBar and UIHealthBar.UpdatePetVisibility then
        UIHealthBar.UpdatePetVisibility(self)
    end
    -- Pet bar just showed/hid: re-anchor the resource bars to the new outermost shown
    -- bar so they don't leave a gap over the hidden pet slot (matches the overlay).
    if UIHealthBar and UIHealthBar.ReanchorPower then
        UIHealthBar.ReanchorPower(self)
    end
    -- Overlay counterpart: its bar anchoring only runs when the defensive COUNT
    -- changes, which a pet summon/dismiss doesn't touch - force the next pass to
    -- re-run it (shows the pet bar / closes the gap it left).
    if UINameplateOverlay and UINameplateOverlay.InvalidateBarLayout then
        UINameplateOverlay.InvalidateBarLayout()
    end
    self:OnHealthChanged(nil, "pet")
    self:ForceUpdate()
end

function JustAC:OnEquipmentChanged(event, slot, hasCurrent)
    if BlizzardAPI and BlizzardAPI.RefreshItemSpellCache then
        BlizzardAPI.RefreshItemSpellCache()
    end
    -- Equipment can change defensive item availability (trinkets/belt/gloves),
    -- so refresh both queues immediately instead of waiting for defensive cadence.
    self:ForceUpdateAll()
end

-- Bags changed (loot, used a potion, leveled into a new tier) - mark the emergency
-- healing-item scan stale so it re-resolves the best owned pot on the next OOC build.
function JustAC:OnBagUpdate()
    if SpellDB and SpellDB.MarkHealingBagsDirty then
        SpellDB.MarkHealingBagsDirty()
    end
end

function JustAC:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    if UnitAffectingCombat("player") and RedundancyFilter and RedundancyFilter.RecordSpellActivation then
        RedundancyFilter.RecordSpellActivation(spellID)
    end

    -- Applied-latch for the pre-combat buff offers (poisons, shields, imbues): clears
    -- the clickable offer at cast COMPLETION instead of a server beat later when the
    -- aura registers - the beat where a second click re-applies for nothing. The
    -- callee filters to maintained ids, so this is a table lookup for everything else.
    local PE = LibStub("JustAC-PrecombatEngine", true)
    if PE and PE.NoteClassBuffApplied then PE.NoteClassBuffApplied(spellID) end

    -- Record maintained-DoT applications so the queue can sink them while the
    -- debuff is live on the target (identity from our own NeverSecret cast).
    if UnitAffectingCombat("player") and DotTracker and DotTracker.OnCastSucceeded then
        DotTracker.OnCastSucceeded(spellID)
    end

    -- Arm the maintenance-buff bridge. NOT combat-gated, unlike the DoT tracker: binding the
    -- instance out of combat is what gives the button a live timer the moment a pull starts.
    if MaintenanceTracker and MaintenanceTracker.OnCastSucceeded then
        -- Pressing the upkeep button changes what the slot must draw RIGHT NOW (fresh swipe,
        -- glow off), so redraw on the next tick instead of waiting for the periodic defensive
        -- rebuild. The aura event cannot cover this: refreshing an already-bound buff changes
        -- nothing the tracker can see, so it reports no change and never marks us dirty.
        if MaintenanceTracker.OnCastSucceeded(spellID) then defensiveQueueDirty = true end
    end

    -- Defensive item use latch: in-combat item cooldowns are secret, so an
    -- observed use is the readiness signal until combat ends.
    if BlizzardAPI and BlizzardAPI.NoteDefensiveItemUse then
        BlizzardAPI.NoteDefensiveItemUse(spellID)
    end

    -- Gap-closer post-fire debounce: while the confirmed charge/leap travels, the
    -- engine must not offer the next gap closer (the melee probe lags the flight).
    if GapCloserEngine and GapCloserEngine.NoteSpellcastSucceeded then
        GapCloserEngine.NoteSpellcastSucceeded(self, spellID)
    end

    -- If a CC spell landed, suppress the interrupt icon for CC_APPLIED_SUPPRESS seconds so
    -- the next CC suggestion doesn't flash before the game registers the CC state on target.
    -- spellID from UNIT_SPELLCAST_SUCCEEDED reads plain for the player's own cast (the event is
    -- SecretWhenUnitSpellCastRestricted, which exempts us) - not NeverSecret; a per-spell
    -- AlwaysSecret override can still apply, so the IsSecretValue guard stays.
    if SpellDB and SpellDB.IsCrowdControlSpell(spellID) then
        -- One call covers both renderers: the CC debounce state lives in UIRenderer and the
        -- overlay reads it from there. (The overlay used to carry a forwarder for this; it had
        -- no callers and is gone - do not re-add one, call UIRenderer directly.)
        if CastInterruptTracker and CastInterruptTracker.NotifyCCApplied then CastInterruptTracker.NotifyCCApplied() end
        -- Notify CC-failure learning: if the target was mid-cast, check shortly after
        -- whether that cast actually stopped.
        -- Guard: skip for pure interrupt spells (Kick, Wind Shear, etc.) - they apply a lockout
        -- but no CC mechanic, so the failure check would always fire and permanently mark
        -- the target as CC-immune, suppressing CC fallbacks (e.g. Blind after Kick).
        if BlizzardAPI and BlizzardAPI.NotifyCCCastOnTarget
            and not (SpellDB and SpellDB.IsInterruptTypeSpell(spellID)) then
            BlizzardAPI.NotifyCCCastOnTarget()
        end
    end

    -- Cast completed - dirty flags ensure next OnUpdate tick rebuilds both queues.
    -- No deferred timer needed; the natural OnUpdate cadence provides sufficient
    -- settle time (~30-50ms) for game state to update after the cast.
    self:ForceUpdateAll()
end

-- OOC only: PrecombatEngine hides its suggestions while a cast/channel is running, so an extra
-- click can't cancel the channel (wasting the food) or burn a second consumable. That guard is
-- only as fast as the next queue rebuild - and out of combat that is the 0.5s idle cycle, which
-- would leave the icon clickable for up to half a second after the cast begins, exactly the
-- double-click window the guard exists to close. Rebuild on the transition instead (and on stop,
-- so an interrupted channel brings the suggestion straight back). In combat the pre-combat
-- system is inactive, so we skip the extra rebuilds entirely.
local function MarkPrecombatGuardDirty()
    if not UnitAffectingCombat("player") then defensiveQueueDirty = true end
end

-- Event-driven cast/channel spell ID caching - avoids polling UnitCastingInfo/UnitChannelInfo
-- every render frame. spellID from UNIT_SPELLCAST_* for "player" is NeverSecret.
function JustAC:OnPlayerCastStart(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if UIRenderer and UIRenderer.SetCastSpellID then UIRenderer.SetCastSpellID(spellID) end
    MarkPrecombatGuardDirty()
end

function JustAC:OnPlayerCastStop(event, unit)
    if unit ~= "player" then return end
    if UIRenderer and UIRenderer.SetCastSpellID then UIRenderer.SetCastSpellID(nil) end
    MarkPrecombatGuardDirty()
end

function JustAC:OnPlayerChannelStart(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if UIRenderer and UIRenderer.SetChannelSpellID then UIRenderer.SetChannelSpellID(spellID) end
    -- OOC the loop only ticks when dirty: without this the channel grey-out/fill
    -- doesn't paint (or clear, below) until some other event happens to fire.
    self:MarkQueueDirty()
    MarkPrecombatGuardDirty()
end

function JustAC:OnPlayerChannelStop(event, unit)
    if unit ~= "player" then return end
    if UIRenderer and UIRenderer.SetChannelSpellID then UIRenderer.SetChannelSpellID(nil) end
    self:MarkQueueDirty()
    MarkPrecombatGuardDirty()
end

function JustAC:OnCooldownUpdate()
    MarkQueuesDirtyThrottled()
end

--- Marks queues dirty and ensures the next OnUpdate tick processes immediately.
--- All rendering goes through the unified OnUpdate loop (no synchronous renders).
--- Multiple calls per frame are idempotent - setting dirty flags is a no-op when already set.
function JustAC:ForceUpdate(includeDefensives)
    spellQueueDirty = true
    if includeDefensives then defensiveQueueDirty = true end
    -- Process on very next OnUpdate tick (~7-16ms at typical framerates)
    if self.updateTimeLeft then self.updateTimeLeft = 0 end
end

function JustAC:ForceUpdateAll()
    self:ForceUpdate(true)
end

--- Keybind entry for a situational set (Bindings.xml). Flips the set, tells the player
--- which way it went, and prods the queue. Insecure and combat-safe by construction.
function JustAC:ToggleSituationalSet(slot)
    if not SpellQueue or not SpellQueue.ToggleSet then return end
    local active = SpellQueue.ToggleSet(slot)
    local name = self:GetSituationalSetName(slot)
    if active == nil then
        self:Print(string.format(L["Set Empty"], name))
        return
    end
    self:Print(string.format(active and L["Set Enabled"] or L["Set Disabled"], name))
    if UIRenderer and UIRenderer.RefreshSetIndicator then UIRenderer.RefreshSetIndicator(self) end
    self:ForceUpdate()
end

--- The player's label for a set slot, or a numbered default.
function JustAC:GetSituationalSetName(slot)
    local profile = self:GetProfile()
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local sets = profile and specKey and profile.situationalSets and profile.situationalSets[specKey]
    local s = sets and sets[slot]
    if s and s.name and s.name ~= "" then return s.name end
    return string.format(L["Set Default Name"], slot)
end

function JustAC:OpenOptionsPanel()
    if Options then
        if self.InitializeDefensiveSpells then
            self:InitializeDefensiveSpells()
        end
        if Options.RefreshAllDynamic then Options.RefreshAllDynamic(self) end
    end

    if BlizzardAPI and BlizzardAPI.IS_MIDNIGHT_OR_LATER then
        local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
        if AceConfigDialog then
            AceConfigDialog:Open("JustAssistedCombat")
        end
    else
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory("JustAssistedCombat")
        end
    end
end

--------------------------------------------------------------------------------
-- Update Cycle Architecture
--
-- All rendering is driven by a single OnUpdate loop. No synchronous rendering
-- occurs in event handlers - they only set dirty flags and reset the timer.
--
-- Tier 1 (spell queue):     combat: CVar rate clamped to 0.03-0.05s (20-33Hz);
--                           OOC: event-dirty at max(CVar, 0.15s), else idle
-- Tier 2 (widget refresh):  UIFrameFactory.COOLDOWN_UPDATE_INTERVAL (0.08s, ~12Hz)
--                           inside the render pass - CD swipes, charges, hotkey re-lookup
-- Tier 3 (defensive rebuild): event-dirty (health/aura/cooldown/usability/cast events),
--                           with a periodic fallback: 0.5s in combat, 1.0s OOC
-- Tier 4 (idle/OOC):        0.5s - nothing happening
--
-- ForceUpdate() / ForceUpdateAll() set dirty flags + updateTimeLeft = 0
-- so the next frame processes. Multiple calls per frame are idempotent.
--------------------------------------------------------------------------------

-- Extracted from StartUpdates so the update body is readable independently of its
-- registration boilerplate.  Upvalues: JustAC (addon), SpellQueue, and the
-- update-loop state vars declared at the top of this file.
local function OnUpdateTick(_, elapsed)
    local timeLeft = (JustAC.updateTimeLeft or 0) - elapsed
    JustAC.updateTimeLeft = timeLeft

    -- Fast path: skip all work if not time to update yet
    -- This is the most common case - exit as early as possible
    if timeLeft > 0 then
        return
    end

    -- Freeze updates while the frame is being dragged (smooth drag, no wasted work).
    -- Trust but verify: press-grab drags end in an OnMouseUp, which - unlike the old
    -- OnDragStop - is not guaranteed if the handler is torn down mid-press. A stuck
    -- flag would freeze the whole panel forever, and with the left button up there
    -- IS no drag - so clear it and carry on instead of trusting it blindly.
    if JustAC.isDragging then
        if IsMouseButtonDown("LeftButton") then
            JustAC.updateTimeLeft = 0.1
            return
        end
        JustAC.isDragging = false
    end

    -- Early exit: skip all work if UI is completely hidden (saves CPU when mounted, etc.)
    local mainFrame = JustAC.mainFrame
    local mainHidden = not mainFrame or not mainFrame:IsShown()
    local defIcons = JustAC.defensiveIcons
    local defHidden = (not defIcons or #defIcons == 0)
        and (not JustAC.defensiveFrame or not JustAC.defensiveFrame:IsShown())
    local npHidden = not JustAC.nameplateIcons or #JustAC.nameplateIcons == 0
    if mainHidden and defHidden and npHidden
            and not spellQueueDirty then
        JustAC.updateTimeLeft = IDLE_CHECK_INTERVAL
        return
    end

    local inCombat = UnitAffectingCombat("player")

    -- Cache CVar lookup (expensive string operation + registry lookup)
    local now = GetTime()
    if not cachedUpdateRate or (now - lastCVarCheck) > CVAR_CHECK_INTERVAL then
        local rawRate = tonumber(GetCVar("assistedCombatIconUpdateRate"))
        cachedUpdateRate = rawRate ~= nil and rawRate or 0.05
        lastCVarCheck = now
    end

    local updateRate
    if inCombat then
        -- Clamp to [0.03, 0.05] (33–20Hz). GetNextCastSpell is queried live each
        -- tick, so a faster poll is always fresher than Blizzard's CVar-gated cache.
        -- Ceiling decouples us from assistedCombatIconUpdateRate, whose default
        -- Blizzard can raise across patches (Clamp 0–1) and which would otherwise
        -- bottleneck the queue and make ability updates feel sluggish.
        updateRate = cachedUpdateRate
        if updateRate < 0.03 then updateRate = 0.03
        elseif updateRate > 0.05 then updateRate = 0.05 end
    else
        -- Out of combat: idle when clean, near-combat rate when dirty
        if not spellQueueDirty and not defensiveQueueDirty then
            updateRate = IDLE_CHECK_INTERVAL
        else
            updateRate = math_max(cachedUpdateRate, OOC_DIRTY_UPDATE_INTERVAL)
        end
    end

    JustAC.updateTimeLeft = updateRate

    -- Combat keeps polling (Blizzard doesn't provide reliable rotation-change events).
    -- Out of combat, skip queue rebuild/render unless an event marked it dirty.
    -- The mid-channel hold lives in SpellQueue.GetCurrentSpellQueue (content freezes,
    -- rendering continues so the channel grey-out/fill paints). Rendering must NOT be
    -- skipped here while channeling - that was how the channeled spell kept looking
    -- available for the whole channel. Dirty is preserved through the hold so the
    -- first post-channel tick rebuilds immediately even out of combat.
    local channeling = BlizzardAPI and BlizzardAPI.IsPlayerChanneling
        and BlizzardAPI.IsPlayerChanneling()
    local shouldUpdateSpellQueue = inCombat or spellQueueDirty
    if shouldUpdateSpellQueue then
        -- When dirty OUT of combat, bypass SpellQueue's internal throttle so rare
        -- event-driven updates render immediately. In combat, let the internal
        -- 0.03s floor stand: the GCD cascade fires ~10 cooldown/usability events
        -- per cast, and the bypass turned that into a full build on consecutive
        -- frames - the 20-33Hz poll already bounds latency at one tick.
        if spellQueueDirty and not inCombat and not channeling and SpellQueue and SpellQueue.ForceUpdate then
            SpellQueue.ForceUpdate()
        end
        JustAC:UpdateSpellQueue()
        if not channeling then spellQueueDirty = false end
    end

    -- Only update defensive cooldowns if dirty or periodic check
    local defensiveInterval = inCombat and IDLE_CHECK_INTERVAL or OOC_DEFENSIVE_IDLE_INTERVAL
    if defensiveQueueDirty or (now - lastFullUpdate) > defensiveInterval then
        -- Full queue rebuild (not just cooldown swipes) so "always" and "combatOnly"
        -- modes surface new icons promptly when cooldowns expire. Clear the dirty
        -- flag only when the rebuild actually ran: DefensiveEngine's 0.1s throttle
        -- can skip this call (e.g. the first frame after combat exit), and eating
        -- the flag then deferred the rebuild to the 1s idle cycle.
        if JustAC:OnHealthChanged(nil, "player") ~= false then
            defensiveQueueDirty = false
            lastFullUpdate = now
        end
    end
end

function JustAC:MarkQueueDirty()
    spellQueueDirty = true
end

function JustAC:MarkDefensiveDirty()
    defensiveQueueDirty = true
end

function JustAC:StartUpdates()
    if self.updateFrame then return end

    self.updateFrame = CreateFrame("Frame")
    self.updateTimeLeft = 0
    self.updateFrame:SetScript("OnUpdate", OnUpdateTick)
end

function JustAC:StopUpdates()
    if self.updateFrame then
        self.updateFrame:SetScript("OnUpdate", nil)
        self.updateFrame = nil
    end
end

function JustAC:UpdateFrameSize()
    if UIFrameFactory and UIFrameFactory.UpdateFrameSize then UIFrameFactory.UpdateFrameSize(self) end
    if UIHealthBar and UIHealthBar.UpdateSize then UIHealthBar.UpdateSize(self) end
    if UIHealthBar and UIHealthBar.UpdatePetSize then UIHealthBar.UpdatePetSize(self) end
    if UIHealthBar and UIHealthBar.UpdatePowerSize then UIHealthBar.UpdatePowerSize(self) end
    -- Re-apply target frame anchor after resize (SetSize doesn't move the frame, but
    -- the anchor guard IsShown check may not have fired before the first render)
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
    -- AFTER the anchor pass, never before: whether the target bar gets built at all depends
    -- on targetframe_anchored, and this call is what several config paths (layout reset,
    -- profile switch) rely on to rebuild it. Reading the flag first would build against the
    -- OLD dock state and leave a duplicate bar - or no bar - until the next zone change.
    if UIHealthBar and UIHealthBar.UpdateTargetSize then UIHealthBar.UpdateTargetSize(self) end
    -- ForceUpdateAll (not ForceUpdate) so OnHealthChanged fires → ResizeToCount
    -- runs immediately, keeping health bar width in sync with visible defensive icons.
    self:ForceUpdateAll()
end

function JustAC:SavePosition()
    if UIFrameFactory and UIFrameFactory.SavePosition then UIFrameFactory.SavePosition(self) end
end