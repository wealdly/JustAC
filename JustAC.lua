-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIManager, UIRenderer, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter

-- Class-specific defensive spell defaults (spellIDs in priority order)
-- Two tiers: self-heals (weave into rotation) and major cooldowns (emergency)
-- Self-heals trigger at higher threshold, cooldowns at lower threshold
-- NOTE: Include options from multiple specs - IsSpellAvailable will filter to what player knows

-- Quick self-heals: fast/cheap abilities to maintain health during combat
local CLASS_SELFHEAL_DEFAULTS = {
    -- 12.0 DESIGN: Instant-cast, self-targeted heals/absorbs that work in emergencies
    -- Fewer spells = better tracking overhead. Prioritize class-wide abilities.
    -- Order matters: first usable spell is shown
    -- Exception: Spells that can PROC instant (Regrowth) are included for proc detection
    
    -- Death Knight: Death Strike is #1 priority (generates runic power refund at low HP)
    DEATHKNIGHT = {49998},                           -- Death Strike
    
    -- Demon Hunter: Blur is instant mitigation, Soul Cleave for Vengeance
    DEMONHUNTER = {198589, 228477},                  -- Blur, Soul Cleave (Veng only)
    
    -- Druid: Regrowth (Predatory Swiftness proc!), Frenzied Regen (Bear), Renewal, Barkskin
    -- Regrowth is cast-time normally, but Predatory Swiftness makes it instant and it glows
    DRUID = {8936, 22842, 108238, 22812},            -- Regrowth, Frenzied Regen, Renewal, Barkskin
    
    -- Evoker: Obsidian Scales (instant absorb), Verdant Embrace (instant heal)
    EVOKER = {363916, 360995},                       -- Obsidian Scales, Verdant Embrace
    
    -- Hunter: Exhilaration is the only real self-heal
    HUNTER = {109304},                               -- Exhilaration
    
    -- Mage: Barriers are instant absorbs - pick one based on spec (talent choice)
    -- Ice Barrier is baseline for Frost, others are spec-specific
    MAGE = {11426, 235313, 235450},                  -- Ice Barrier, Blazing Barrier, Prismatic Barrier
    
    -- Monk: Expel Harm is instant, strong heal
    MONK = {322101},                                 -- Expel Harm
    
    -- Paladin: Word of Glory (free with Holy Power), Divine Protection (instant)
    PALADIN = {85673, 498},                          -- Word of Glory, Divine Protection
    
    -- Priest: Desperate Prayer (instant, strong), Power Word: Shield (instant absorb)
    PRIEST = {19236, 17},                            -- Desperate Prayer, PW:Shield
    
    -- Rogue: Crimson Vial is the only heal, Feint for mitigation
    ROGUE = {185311, 1966},                          -- Crimson Vial, Feint
    
    -- Shaman: Healing Surge has cast time but procs instant at low health
    -- Astral Shift is instant damage reduction
    SHAMAN = {108271, 8004},                         -- Astral Shift, Healing Surge
    
    -- Warlock: Dark Pact (instant absorb), Drain Life (channeled but heals)
    WARLOCK = {108416, 234153},                      -- Dark Pact, Drain Life
    
    -- Warrior: Victory Rush (proc), Impending Victory (talent), Ignore Pain
    WARRIOR = {34428, 202168, 190456},               -- Victory Rush, Impending Victory, Ignore Pain
}

-- Major cooldowns: big defensives for critical situations (~20% health)
-- These are "oh shit" buttons - longer cooldowns, bigger impact
local CLASS_COOLDOWN_DEFAULTS = {
    -- Death Knight: IBF is the big one, AMS for magic damage
    DEATHKNIGHT = {48792, 48707},                    -- Icebound Fortitude, Anti-Magic Shell
    
    -- Demon Hunter: Netherwalk (immunity), Darkness (AoE DR)
    DEMONHUNTER = {196555, 196718},                  -- Netherwalk, Darkness
    
    -- Druid: Survival Instincts (Feral/Guardian), Barkskin already in self-heals
    DRUID = {61336},                                 -- Survival Instincts
    
    -- Evoker: Renewing Blaze (heal over time + death save)
    EVOKER = {374348},                               -- Renewing Blaze
    
    -- Hunter: Turtle is immunity, Fortitude of the Bear (talent)
    HUNTER = {186265, 388035},                       -- Aspect of the Turtle, Fortitude of the Bear
    
    -- Mage: Ice Block (immunity), Greater Invisibility (DR + threat drop)
    MAGE = {45438, 110959},                          -- Ice Block, Greater Invisibility
    
    -- Monk: Fortifying Brew, Touch of Karma (WW), Diffuse Magic
    MONK = {115203, 122470, 122783},                 -- Fortifying Brew, Touch of Karma, Diffuse Magic
    
    -- Paladin: Divine Shield (immunity), Lay on Hands (full heal)
    PALADIN = {642, 633},                            -- Divine Shield, Lay on Hands
    
    -- Priest: Dispersion (Shadow), Fade (threat + DR talents)
    PRIEST = {47585, 586},                           -- Dispersion, Fade
    
    -- Rogue: Cloak of Shadows (magic immunity), Evasion (dodge)
    ROGUE = {31224, 5277},                           -- Cloak of Shadows, Evasion
    
    -- Shaman: Earth Elemental (taunt), already have Astral Shift in self-heals
    SHAMAN = {198103},                               -- Earth Elemental
    
    -- Warlock: Unending Resolve (big DR)
    WARLOCK = {104773},                              -- Unending Resolve
    
    -- Warrior: Shield Wall (Prot), Die by the Sword (Arms/Fury), Rallying Cry
    WARRIOR = {871, 118038, 97462},                  -- Shield Wall, Die by the Sword, Rallying Cry
}

-- Pet heal spells: for classes with permanent pets (Hunter, Warlock)
-- These are shown when PET health is low, not player health
-- Exhilaration (109304) heals both player AND pet, so it's in both lists
local CLASS_PETHEAL_DEFAULTS = {
    HUNTER = {136, 109304},                          -- Mend Pet, Exhilaration (heals pet too)
    WARLOCK = {755},                                 -- Health Funnel
}

-- Expose defaults for Options module
JustAC.CLASS_SELFHEAL_DEFAULTS = CLASS_SELFHEAL_DEFAULTS
JustAC.CLASS_COOLDOWN_DEFAULTS = CLASS_COOLDOWN_DEFAULTS
JustAC.CLASS_PETHEAL_DEFAULTS = CLASS_PETHEAL_DEFAULTS

local defaults = {
    profile = {
        framePosition = {
            point = "CENTER",
            x = 0,
            y = -150,
        },
        maxIcons = 4,
        iconSize = 36,
        iconSpacing = 1,
        debugMode = false,
        isManualMode = false,
        showTooltips = true,
        tooltipsInCombat = true,
        focusEmphasis = true,
        firstIconScale = 1.2,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueOutOfCombat = false,  -- Hide the entire queue when out of combat
        hideQueueForHealers = false,   -- Hide the entire queue when in a healer spec
        hideQueueWhenMounted = false,  -- Hide the queue while mounted
        hideItemAbilities = false,     -- Hide equipped item abilities (trinkets, tinkers)
        panelLocked = false,              -- Lock panel interactions in combat
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            position = "LEADING",     -- SIDE1 (health bar side), SIDE2, or LEADING (opposite grab tab)
            showHealthBar = false,    -- Display compact health bar above main queue
            iconScale = 1.2,          -- Scale for defensive icons (same range as Primary Spell Scale)
            maxIcons = 1,             -- Number of defensive icons to show (1-3)
            selfHealThreshold = 80,   -- Show self-heals when health drops below this
            cooldownThreshold = 60,   -- Show major cooldowns when health drops below this
            petHealThreshold = 50,    -- Show pet heals when PET health drops below this
            selfHealSpells = {},      -- Populated from CLASS_SELFHEAL_DEFAULTS on first run
            cooldownSpells = {},      -- Populated from CLASS_COOLDOWN_DEFAULTS on first run
            petHealSpells = {},       -- Populated from CLASS_PETHEAL_DEFAULTS on first run
            showOnlyInCombat = false, -- false = always visible, true = only in combat with thresholds
            alwaysShowDefensive = false, -- true = show defensive queue even at full health (shows procs/off-cooldown spells)
        },
    },
    char = {
        lastKnownSpec = nil,
        firstRun = true,
        blacklistedSpells = {},   -- Character-specific spell blacklist
        hotkeyOverrides = {},     -- Character-specific hotkey overrides
    },
    global = {
        version = "2.6",
    },
}

-- Helper: Only print if debug mode is enabled
function JustAC:DebugPrint(msg)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print(msg)
    end
end

-- Normalize saved data: convert string keys to numbers, simplify formats
-- This fixes issues where SavedVariables serialize numeric keys as strings
function JustAC:NormalizeSavedData()
    local charData = self.db and self.db.char
    if not charData then return end
    
    -- Normalize blacklistedSpells: string keys -> number, any truthy value -> true
    if charData.blacklistedSpells then
        local normalized = {}
        for key, value in pairs(charData.blacklistedSpells) do
            local spellID = tonumber(key)
            if spellID and spellID > 0 and value then
                normalized[spellID] = true  -- Simplified format
            end
        end
        charData.blacklistedSpells = normalized
    end
    
    -- Normalize hotkeyOverrides: string keys -> number
    if charData.hotkeyOverrides then
        local normalized = {}
        for key, value in pairs(charData.hotkeyOverrides) do
            local spellID = tonumber(key)
            if spellID and spellID > 0 and type(value) == "string" and value ~= "" then
                normalized[spellID] = value
            end
        end
        charData.hotkeyOverrides = normalized
    end
    
    -- Migration: Move old profile data to char if it exists
    local profile = self.db and self.db.profile
    if profile then
        if profile.blacklistedSpells and next(profile.blacklistedSpells) then
            for spellID, value in pairs(profile.blacklistedSpells) do
                if not charData.blacklistedSpells[spellID] then
                    charData.blacklistedSpells[tonumber(spellID) or spellID] = value
                end
            end
            profile.blacklistedSpells = nil  -- Clear old data
        end
        if profile.hotkeyOverrides and next(profile.hotkeyOverrides) then
            for spellID, value in pairs(profile.hotkeyOverrides) do
                if not charData.hotkeyOverrides[spellID] then
                    charData.hotkeyOverrides[tonumber(spellID) or spellID] = value
                end
            end
            profile.hotkeyOverrides = nil  -- Clear old data
        end
    end
end

function JustAC:OnInitialize()
    -- AceDB handles per-character profiles automatically
    self.db = AceDB:New("JustACDB", defaults)
    
    -- Initialize binding globals early (at ADDON_LOADED, before any combat)
    -- This prevents taint from modifying _G during gameplay
    if not _G.BINDING_NAME_JUSTAC_CAST_FIRST then
        _G.BINDING_NAME_JUSTAC_CAST_FIRST = "JustAC: Cast First Spell"
        _G.BINDING_HEADER_JUSTAC = "JustAssistedCombat"
    end
    
    -- Normalize saved data (fix string keys, simplify formats)
    self:NormalizeSavedData()
    
    -- Initialize class-specific defensive spells on first run
    self:InitializeDefensiveSpells()
    
    self:LoadModules()
    
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    
    if Options and Options.Initialize then
        Options.Initialize(self)
    end
end

function JustAC:OnEnable()
    if not UIManager or not UIManager.CreateMainFrame then
        self:Print("Error: UIManager module not loaded properly")
        return
    end
    
    UIManager.CreateMainFrame(self)
    if not self.mainFrame then
        self:Print("Error: Failed to create main frame")
        return
    end
    
    -- Create key press detection frame for activation flash
    self:CreateKeyPressDetector()
    
    UIManager.CreateSpellIcons(self)
    
    -- Create health bar if enabled (must be after CreateSpellIcons)
    if UIManager.CreateHealthBar then
        UIManager.CreateHealthBar(self)
    end
    
    -- Match animation state to current combat status
    if UnitAffectingCombat("player") then
        if UIManager.UnfreezeAllGlows then UIManager.UnfreezeAllGlows(self) end
    else
        if UIManager.FreezeAllGlows then UIManager.FreezeAllGlows(self) end
    end
    
    self:InitializeCaches()
    self:StartUpdates()
    
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    
    -- Health monitoring for defensive suggestions
    self:RegisterEvent("UNIT_HEALTH", "OnHealthChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChange")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "OnActionBarChanged")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "OnActionBarChanged")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "OnSpecialBarChanged")
    
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshiftFormChanged")
    -- UPDATE_SHAPESHIFT_FORMS (plural): fires when form bar is rebuilt (login, talents)
    -- Critical: GetShapeshiftForm() returns nil until this fires
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", "OnShapeshiftFormsRebuilt")
    
    -- Buffs like Metamorphosis change spell overrides; throttle to prevent flicker
    self.lastAuraInvalidation = 0
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsUpdated")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
    
    -- Immediate update after casting via AC button
    self:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST", "ForceUpdate")
    
    -- Proc detection: Blizzard overlay glow events for faster proc response
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowChange")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowChange")
    
    -- Spell icon/override changes (transformations like Hot Streak Pyroblast)
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellIconChanged")
    
    -- Target changes affect execute-range abilities and macro conditionals
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    
    -- Pet state for RedundancyFilter pet-related checks
    self:RegisterEvent("UNIT_PET", "OnPetChanged")
    
    -- Equipment changes affect item spell detection (trinkets, tinkers)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    
    -- Cast completion for immediate post-cast refresh (faster than OnUpdate tick)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    
    -- Vehicle state changes invalidate action bar layout entirely
    self:RegisterEvent("UNIT_ENTERED_VEHICLE", "OnVehicleChanged")
    self:RegisterEvent("UNIT_EXITED_VEHICLE", "OnVehicleChanged")
    
    -- Blizzard's EventRegistry fires when recommendations change
    if EventRegistry then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            self:ForceUpdate()
        end, self)
        EventRegistry:RegisterCallback("AssistedCombatManager.RotationSpellsUpdated", function()
            if SpellQueue and SpellQueue.ClearAvailabilityCache then
                SpellQueue.ClearAvailabilityCache()
            end
            self:ForceUpdate()
        end, self)
        -- Primary "action spell" changed (first recommended spell)
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function()
            self:ForceUpdate()
        end, self)
    end
    
    if self.db.char.firstRun then
        self.db.char.firstRun = false
    end
    
    self:ScheduleTimer("DelayedValidation", 2)
end

-- Monitor key presses to trigger flash on matching queue icons
function JustAC:CreateKeyPressDetector()
    if self.keyPressFrame then return end
    
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)  -- Don't consume the key
    self.keyPressFrame = frame
    
    -- Cache function references at creation time (avoid table lookups in hot path)
    local StartFlash = UIManager and UIManager.StartFlash
    local IsShiftKeyDown = IsShiftKeyDown
    local IsControlKeyDown = IsControlKeyDown
    local IsAltKeyDown = IsAltKeyDown
    
    frame:SetScript("OnKeyDown", function(self, key)
        local addon = JustAC
        if not addon or not StartFlash then return end
        
        -- Skip pure modifier keys early
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end
        
        -- Normalize key name (WoW uses uppercase)
        local pressedKey = key:upper()
        
        -- Check modifiers and build the full binding string
        local hasShift = IsShiftKeyDown()
        local hasCtrl = IsControlKeyDown()
        local hasAlt = IsAltKeyDown()
        
        -- Build full key only if modifiers are pressed (avoid string concat otherwise)
        local fullKey
        if hasShift or hasCtrl or hasAlt then
            -- Build modifier prefix efficiently (avoid intermediate strings)
            if hasShift and hasCtrl and hasAlt then
                fullKey = "SHIFT-CTRL-ALT-" .. pressedKey
            elseif hasShift and hasCtrl then
                fullKey = "SHIFT-CTRL-" .. pressedKey
            elseif hasShift and hasAlt then
                fullKey = "SHIFT-ALT-" .. pressedKey
            elseif hasCtrl and hasAlt then
                fullKey = "CTRL-ALT-" .. pressedKey
            elseif hasShift then
                fullKey = "SHIFT-" .. pressedKey
            elseif hasCtrl then
                fullKey = "CTRL-" .. pressedKey
            else -- hasAlt
                fullKey = "ALT-" .. pressedKey
            end
        else
            fullKey = pressedKey
        end
        
        -- Helper function to check if hotkey matches pressed key (handles MOD- prefix)
        local function HotkeyMatches(hotkey)
            if not hotkey then return false end
            if hotkey == fullKey then return true end
            -- MOD- prefix matches any modifier (SHIFT/CTRL/ALT) + base key
            if hotkey:match("^MOD%-") and (hasShift or hasCtrl or hasAlt) then
                local baseKey = hotkey:gsub("^MOD%-", "")
                return (pressedKey == baseKey)
            end
            return false
        end
        
        -- Flash feedback for all queue icons that match the pressed key
        -- Special handling: don't flash slots 2+ if they show the spell that WAS in slot 1
        -- (that means the spell just moved from slot 1 and we already executed it)
        local iconsToFlash = {}
        local now = GetTime()
        local HOTKEY_GRACE_PERIOD = 0.15  -- Grace period for spell position changes
        local slot1PrevSpellID = nil  -- Track which spell was in slot 1 (to avoid flashing after move)
        
        local spellIcons = addon.spellIcons
        if spellIcons then
            -- Check slot 1 and track which spell was previously there
            local icon1 = spellIcons[1]
            if icon1 and icon1:IsShown() then
                -- Track which spell USED to be in slot 1 (before it moved to slot 2+)
                if icon1.hotkeyChangeTime and (now - icon1.hotkeyChangeTime) < HOTKEY_GRACE_PERIOD then
                    slot1PrevSpellID = icon1.previousSpellID
                end
                
                if HotkeyMatches(icon1.normalizedHotkey) then
                    iconsToFlash[#iconsToFlash + 1] = icon1
                end
            end
            
            -- Check slots 2+ but skip if this is the spell that just moved from slot 1
            for i = 2, #spellIcons do
                local icon = spellIcons[i]
                if icon and icon:IsShown() then
                    local matched = HotkeyMatches(icon.normalizedHotkey)
                    
                    -- Skip if this is the SAME SPELL that was in slot 1 (it just moved)
                    -- Don't skip if it's a different spell with the same hotkey
                    if matched and slot1PrevSpellID and icon.spellID == slot1PrevSpellID then
                        matched = false  -- Don't flash - this is the spell we just cast
                    end
                    
                    if matched then
                        iconsToFlash[#iconsToFlash + 1] = icon
                    end
                end
            end
        end
        
        -- Check defensive icon
        local defIcon = addon.defensiveIcon
        if defIcon and defIcon:IsShown() then
            if HotkeyMatches(defIcon.normalizedHotkey) then
                iconsToFlash[#iconsToFlash + 1] = defIcon
            end
        end
        
        -- Flash all matched icons
        for _, icon in ipairs(iconsToFlash) do
            StartFlash(icon)
        end
    end)
end

function JustAC:InitializeCaches()
    -- Clear all caches for clean slate on login/reload
    if SpellQueue then
        if SpellQueue.ClearSpellCache then SpellQueue.ClearSpellCache() end
        if SpellQueue.ClearAvailabilityCache then SpellQueue.ClearAvailabilityCache() end
    end
    
    if FormCache and FormCache.OnPlayerLogin then
        FormCache.OnPlayerLogin()
    end
    
    if ActionBarScanner then
        if ActionBarScanner.RebuildKeybindCache then
            ActionBarScanner.RebuildKeybindCache()
        end
        
        if ActionBarScanner.OnUIChanged then
            ActionBarScanner.OnUIChanged()
        end
    end
    
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    
    if RedundancyFilter and RedundancyFilter.InvalidateCache then
        RedundancyFilter.InvalidateCache()
    end
    
    -- Check feature availability (12.0+ secret values may disable some features)
    if BlizzardAPI and BlizzardAPI.RefreshFeatureAvailability then
        BlizzardAPI.RefreshFeatureAvailability()
    end
end

function JustAC:DelayedValidation()
    self:ValidateAssistedCombatSetup()
end

function JustAC:OnCVarUpdate(event, cvarName, value)
    if cvarName == "assistedMode" or cvarName == "assistedCombatHighlight" or cvarName == "assistedCombatIconUpdateRate" then
        self:ValidateAssistedCombatSetup()
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
    
    if EventRegistry then
        EventRegistry:UnregisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", self)
        EventRegistry:UnregisterCallback("AssistedCombatManager.RotationSpellsUpdated", self)
        EventRegistry:UnregisterCallback("AssistedCombatManager.OnSetActionSpell", self)
    end
    
    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

function JustAC:RefreshConfig()
    -- Silently refresh on profile change
    
    -- Clear character-specific data on profile reset (blacklist, hotkey overrides)
    -- This ensures a clean slate when resetting to defaults
    if self.db and self.db.char then
        self.db.char.blacklistedSpells = {}
        self.db.char.hotkeyOverrides = {}
    end
    
    -- Reinitialize defensive spells if lists are empty (profile reset/change)
    self:InitializeDefensiveSpells()
    
    self:UpdateFrameSize()
    if self.mainFrame then
        local profile = self:GetProfile()
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
        self:SavePosition()
    end
    self:ForceUpdate()
end

function JustAC:ShowWelcomeMessage()
    -- Only show if debug mode enabled
    if not self.db or not self.db.profile or not self.db.profile.debugMode then return end
    
    local assistedMode = GetCVarBool("assistedMode") or false
    if assistedMode then
        self:Print("Assisted Combat mode active")
    else
        self:Print("Tip: Enable /console assistedMode 1")
    end
end

-- Initialize class-specific defensive spells on first profile use
function JustAC:InitializeDefensiveSpells()
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end
    
    local _, playerClass = UnitClass("player")
    if not playerClass then return end
    
    -- Initialize self-heal spells if empty
    if not profile.defensives.selfHealSpells or #profile.defensives.selfHealSpells == 0 then
        local healDefaults = CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            profile.defensives.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                profile.defensives.selfHealSpells[i] = spellID
            end
        end
    end
    
    -- Initialize cooldown spells if empty
    if not profile.defensives.cooldownSpells or #profile.defensives.cooldownSpells == 0 then
        local cdDefaults = CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            profile.defensives.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                profile.defensives.cooldownSpells[i] = spellID
            end
        end
    end
    
    -- Initialize pet heal spells if empty (Hunter/Warlock)
    if not profile.defensives.petHealSpells or #profile.defensives.petHealSpells == 0 then
        local petDefaults = CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            profile.defensives.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                profile.defensives.petHealSpells[i] = spellID
            end
        end
    end
    
    -- Register all defensive spells for local cooldown tracking (12.0 workaround)
    self:RegisterDefensivesForTracking()
end

-- Register all configured defensive spells for local cooldown tracking
-- This enables 12.0 compatibility when C_Spell.GetSpellCooldown returns secrets
function JustAC:RegisterDefensivesForTracking()
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if not BlizzardAPI or not BlizzardAPI.RegisterDefensiveSpell then return end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end
    
    -- Clear existing registrations (for profile changes)
    if BlizzardAPI.ClearTrackedDefensives then
        BlizzardAPI.ClearTrackedDefensives()
    end
    
    -- Register all self-heal spells
    if profile.defensives.selfHealSpells then
        for _, spellID in ipairs(profile.defensives.selfHealSpells) do
            BlizzardAPI.RegisterDefensiveSpell(spellID)
        end
    end
    
    -- Register all cooldown spells
    if profile.defensives.cooldownSpells then
        for _, spellID in ipairs(profile.defensives.cooldownSpells) do
            BlizzardAPI.RegisterDefensiveSpell(spellID)
        end
    end
    
    -- Register all pet heal spells
    if profile.defensives.petHealSpells then
        for _, spellID in ipairs(profile.defensives.petHealSpells) do
            BlizzardAPI.RegisterDefensiveSpell(spellID)
        end
    end
end

-- Restore defaults for a specific defensive list (for Options UI)
function JustAC:RestoreDefensiveDefaults(listType)
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end
    
    local _, playerClass = UnitClass("player")
    if not playerClass then return end
    
    if listType == "selfheal" then
        local healDefaults = CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            profile.defensives.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                profile.defensives.selfHealSpells[i] = spellID
            end
        end
    elseif listType == "cooldown" then
        local cdDefaults = CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            profile.defensives.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                profile.defensives.cooldownSpells[i] = spellID
            end
        end
    elseif listType == "petheal" then
        local petDefaults = CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            profile.defensives.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                profile.defensives.petHealSpells[i] = spellID
            end
        end
    end
    
    -- Re-register for local cooldown tracking after list changes
    self:RegisterDefensivesForTracking()
    
    -- Refresh defensive icon
    self:OnHealthChanged(nil, "player")
end

-- Called on UNIT_HEALTH event and ForceUpdateAll
-- Simplified logic:
--   "Only In Combat" ON:  Hide out of combat. In combat: threshold-based (self-heals at ≤80%, cooldowns at ≤60%)
--   "Only In Combat" OFF: Show out of combat (self-heals). In combat: threshold-based (same as above)

function JustAC:OnHealthChanged(event, unit)
    -- Respond to player or pet health changes
    if unit ~= "player" and unit ~= "pet" then return end
    
    -- Update health bar if enabled
    if UIManager and UIManager.UpdateHealthBar then
        UIManager.UpdateHealthBar(self)
    end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives or not profile.defensives.enabled then 
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
        return 
    end
    
    -- Check if health API is accessible (12.0+ secret values may block this)
    -- Removed IsDefensivesFeatureAvailable check - we now use LowHealthFrame fallback
    -- which works even when UnitHealth() returns secrets
    
    local inCombat = UnitAffectingCombat("player")
    local showOnlyInCombat = profile.defensives.showOnlyInCombat
    
    -- Use safe health detection that falls back to LowHealthFrame when secrets block API
    local healthPercent, isEstimated = nil, false
    if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
        healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
    end
    
    -- Detect low health state for defensive suggestions
    -- Get thresholds from profile settings
    local selfHealThreshold = profile.defensives.selfHealThreshold or 80
    local cooldownThreshold = profile.defensives.cooldownThreshold or 60

    local isCritical, isLow
    if isEstimated then
        -- Using LowHealthFrame: low = overlay showing, critical = high alpha
        local lowState, critState = false, false
        if BlizzardAPI.GetLowHealthState then
            lowState, critState = BlizzardAPI.GetLowHealthState()
        end
        isCritical = critState
        isLow = lowState
    elseif healthPercent then
        -- Using exact health: apply user-configured thresholds
        isLow = healthPercent <= selfHealThreshold
        isCritical = healthPercent <= cooldownThreshold
    else
        isCritical = false
        isLow = false
    end
    
    -- Check pet health for pet classes (Hunter, Warlock)
    local petHealthPercent = BlizzardAPI and BlizzardAPI.GetPetHealthPercent and BlizzardAPI.GetPetHealthPercent()
    local petHealThreshold = profile.defensives.petHealThreshold or 70
    local petNeedsHeal = petHealthPercent and petHealthPercent <= petHealThreshold
    
    -- Get defensive spell queue - pass our pre-calculated health state
    -- This is critical because GetPlayerHealthPercentSafe returns 100 when LowHealthFrame isn't detected
    -- but UpdateDefensiveQueue uses GetLowHealthState directly for more accurate detection
    -- Exclude spells showing in VISIBLE DPS queue slots (avoid duplication)
    local dpsQueueExclusions = {}
    if SpellQueue and SpellQueue.GetCurrentSpellQueue then
        local dpsQueue = SpellQueue.GetCurrentSpellQueue()
        local maxDpsIcons = profile.maxIcons or 4
        -- Only exclude spells in visible slots (1 through maxIcons)
        for i = 1, math.min(#dpsQueue, maxDpsIcons) do
            if dpsQueue[i] then
                dpsQueueExclusions[dpsQueue[i]] = true
            end
        end
    end
    local defensiveQueue = self:GetDefensiveSpellQueue(isLow, isCritical, inCombat, dpsQueueExclusions)
    
    -- Pet heals: append if pet needs healing and we have room
    local maxIcons = profile.defensives.maxIcons or 1
    if petNeedsHeal and #defensiveQueue < maxIcons then
        local petHeals = self:GetUsableDefensiveSpells(profile.defensives.petHealSpells, maxIcons - #defensiveQueue, {})
        for _, entry in ipairs(petHeals) do
            defensiveQueue[#defensiveQueue + 1] = entry
        end
    end
    
    -- Show or hide defensive icons
    if #defensiveQueue > 0 then
        -- Use multi-icon system if icons array exists, otherwise fall back to single icon
        if self.defensiveIcons and #self.defensiveIcons > 0 and UIManager and UIManager.ShowDefensiveIcons then
            UIManager.ShowDefensiveIcons(self, defensiveQueue)
        elseif self.defensiveIcon and UIManager and UIManager.ShowDefensiveIcon then
            -- Fallback to single icon
            UIManager.ShowDefensiveIcon(self, defensiveQueue[1].spellID, defensiveQueue[1].isItem)
        end
    else
        if self.defensiveIcons and #self.defensiveIcons > 0 and UIManager and UIManager.HideDefensiveIcons then
            UIManager.HideDefensiveIcons(self)
        elseif self.defensiveIcon and UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
    end
end

-- Get any procced defensive/heal spell (Victory Rush, free heal procs, etc.)
-- This runs at ANY health level since procs should be used when available
-- Returns spell ID if found, nil otherwise
function JustAC:GetProccedDefensiveSpell()
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end
    
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    
    -- Check for any procced defensive spells from spellbook
    if ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs and #defensiveProcs > 0 then
            for _, spellID in ipairs(defensiveProcs) do
                if spellID and spellID > 0 then
                    -- Double-check the proc is still active (guard against stale activeProcs entries)
                    local stillProcced = BlizzardAPI and BlizzardAPI.IsSpellProcced and BlizzardAPI.IsSpellProcced(spellID)
                    if stillProcced then
                        -- Check if known and usable
                        local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                        if isKnown then
                            -- Pass isDefensiveCheck=true to skip DPS-relevance filter
                            local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID, profile, true)
                            if not isRedundant then
                                -- Use IsSpellOnRealCooldown which handles secret values
                                local onCooldown = BlizzardAPI.IsSpellOnRealCooldown and BlizzardAPI.IsSpellOnRealCooldown(spellID)
                                if not onCooldown then
                                    return spellID
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Also check configured spell lists for any procced spells
    local spellLists = {
        profile.defensives.selfHealSpells,
        profile.defensives.cooldownSpells,
    }
    for _, spellList in ipairs(spellLists) do
        if spellList then
            for _, spellID in ipairs(spellList) do
                if spellID and spellID > 0 then
                    -- Check if spell is procced (glowing)
                    if BlizzardAPI and BlizzardAPI.IsSpellProcced and BlizzardAPI.IsSpellProcced(spellID) then
                        local isKnown = BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                        if isKnown then
                            local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID, profile, true)
                            if not isRedundant then
                                -- Use IsSpellOnRealCooldown which handles secret values
                                local onCooldown = BlizzardAPI.IsSpellOnRealCooldown and BlizzardAPI.IsSpellOnRealCooldown(spellID)
                                if not onCooldown then
                                    return spellID
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- Get the first usable spell from a given spell list
-- Prioritizes procced spells (e.g., Victory Rush after kill, free heal procs)
-- Also scans spellbook for any procced defensive abilities not in the list
-- Filters: known, not on cooldown, not redundant (buff already active)

function JustAC:GetBestDefensiveSpell(spellList)
    if not spellList then return nil end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end
    
    -- Debug: log entry into this function
    if profile.debugMode then
        self:DebugPrint("GetBestDefensiveSpell called with " .. #spellList .. " spells in list")
    end
    
    -- LibStub lookups are fast table accesses, no caching wrapper needed
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    
    -- First check: any procced defensive spells from spellbook (highest priority)
    -- These are free/instant abilities that should be used immediately
    if ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs then
            for _, spellID in ipairs(defensiveProcs) do
                if spellID and spellID > 0 then
                    -- Check if known and usable
                    local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                    if isKnown then
                        -- Pass isDefensiveCheck=true to skip DPS-relevance filter
                        local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID, self.db.profile, true)
                        if not isRedundant then
                            -- Use GetSpellCooldownValues which sanitizes secrets to 0
                            local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)
                            local onCooldown = start and start > 0 and duration and duration > 1.5
                            if not onCooldown then
                                -- Procced defensive spell found - use it!
                                return spellID
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Second check: configured spell list (user priority order)
    for i, spellID in ipairs(spellList) do
        if spellID and spellID > 0 then
            -- Debug: log every spell being checked
            if self.db and self.db.profile and self.db.profile.debugMode then
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                self:DebugPrint(string.format("Checking defensive spell %d/%d: %s (%d)", i, #spellList, name, spellID))
            end
            
            -- Check if spell is known/available
            local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
            
            if not isKnown then
                if self.db and self.db.profile and self.db.profile.debugMode then
                    local spellInfo = C_Spell.GetSpellInfo(spellID)
                    local name = spellInfo and spellInfo.name or "Unknown"
                    self:DebugPrint(string.format("  SKIP: %s - not known/available", name))
                end
            elseif isKnown then
                -- Skip if buff already active (redundant) - pass isDefensiveCheck=true
                local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID, self.db.profile, true)
                if isRedundant then
                    if self.db and self.db.profile and self.db.profile.debugMode then
                        local spellInfo = C_Spell.GetSpellInfo(spellID)
                        local name = spellInfo and spellInfo.name or "Unknown"
                        self:DebugPrint(string.format("  SKIP: %s - redundant (buff active)", name))
                    end
                elseif not isRedundant then
                    -- Check if spell is on a real cooldown (not just GCD)
                    local onCooldown = BlizzardAPI.IsSpellOnRealCooldown and BlizzardAPI.IsSpellOnRealCooldown(spellID)
                    
                    -- Debug: log cooldown check results
                    if self.db and self.db.profile and self.db.profile.debugMode then
                        local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)
                        local spellInfo = C_Spell.GetSpellInfo(spellID)
                        local name = spellInfo and spellInfo.name or "Unknown"
                        if onCooldown then
                            self:DebugPrint(string.format("  SKIP: %s - on cooldown (start=%s, duration=%s)", 
                                name, tostring(start or 0), tostring(duration or 0)))
                        else
                            self:DebugPrint(string.format("  PASS: %s - onCooldown=false, start=%s, duration=%s", 
                                name, tostring(start or 0), tostring(duration or 0)))
                        end
                    end
                    
                    if not onCooldown then
                        -- Prioritize procced spells immediately
                        if BlizzardAPI and BlizzardAPI.IsSpellProcced and BlizzardAPI.IsSpellProcced(spellID) then
                            return spellID
                        end
                        
                        -- Return first off-cooldown, non-redundant spell
                        return spellID
                    end
                end
            end
        end
    end
    
    -- No usable spells found
    return nil
end

-- Get multiple usable spells from a list (for multi-icon display)
-- Returns up to maxCount spells, prioritizing procced spells first
-- alreadyAdded is a set of spellIDs already in the queue (to avoid duplicates)
function JustAC:GetUsableDefensiveSpells(spellList, maxCount, alreadyAdded)
    if not spellList or maxCount <= 0 then return {} end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return {} end
    
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    local results = {}
    alreadyAdded = alreadyAdded or {}
    
    -- Track what we add locally (don't modify passed alreadyAdded - caller does that)
    local addedHere = {}
    
    -- First pass: collect procced spells (highest priority)
    for _, spellID in ipairs(spellList) do
        if #results >= maxCount then break end
        if spellID and spellID > 0 and not alreadyAdded[spellID] and not addedHere[spellID] then
            local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
            if isKnown then
                local isProcced = BlizzardAPI and BlizzardAPI.IsSpellProcced and BlizzardAPI.IsSpellProcced(spellID)
                if isProcced then
                    local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID, profile, true)
                    if not isRedundant then
                        -- For defensives: show procced spells even if on cooldown (cooldown will display on icon)
                        results[#results + 1] = {spellID = spellID, isItem = false, isProcced = true}
                        addedHere[spellID] = true
                    end
                end
            end
        end
    end
    
    -- Second pass: collect remaining usable spells
    for _, spellID in ipairs(spellList) do
        if #results >= maxCount then break end
        if spellID and spellID > 0 and not alreadyAdded[spellID] and not addedHere[spellID] then
            local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
            if isKnown then
                local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID, profile, true)
                if not isRedundant then
                    -- For defensives: show spells even if on cooldown (cooldown displays on icon)
                    local isProcced = BlizzardAPI and BlizzardAPI.IsSpellProcced and BlizzardAPI.IsSpellProcced(spellID)
                    results[#results + 1] = {spellID = spellID, isItem = false, isProcced = isProcced}
                    addedHere[spellID] = true
                end
            end
        end
    end
    
    return results
end

-- Build the defensive spell queue (up to maxIcons spells)
-- Priority order: procced spells > self-heals (if low) > cooldowns (if critical)
-- Returns array of {spellID, isItem, isProcced} entries
-- Parameters are optional - if not provided, will calculate internally (less accurate for secrets)
-- passedExclusions: optional table of spellIDs to exclude (e.g., spells already in DPS queue)
function JustAC:GetDefensiveSpellQueue(passedIsLow, passedIsCritical, passedInCombat, passedExclusions)
    local profile = self:GetProfile()
    if not profile or not profile.defensives or not profile.defensives.enabled then return {} end

    local maxIcons = profile.defensives.maxIcons or 1
    local results = {}
    local alreadyAdded = {}

    -- Copy exclusions into alreadyAdded set (avoid duplicating spells from DPS queue)
    if passedExclusions then
        for spellID, _ in pairs(passedExclusions) do
            alreadyAdded[spellID] = true
        end
    end
    
    -- Use passed values if provided (more accurate when caller has better health state info)
    -- Otherwise calculate internally (fallback for direct calls)
    local isLow, isCritical, inCombat
    if passedIsLow ~= nil then
        isLow = passedIsLow
        isCritical = passedIsCritical or false
        inCombat = passedInCombat or UnitAffectingCombat("player")
    else
        -- Fallback: calculate internally (may be inaccurate if health is secret)
        local healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
        inCombat = UnitAffectingCombat("player")
        if isEstimated then
            -- When estimated, get state directly from LowHealthFrame
            local lowState, critState = false, false
            if BlizzardAPI.GetLowHealthState then
                lowState, critState = BlizzardAPI.GetLowHealthState()
            end
            isLow = lowState
            isCritical = critState
        else
            -- Using exact health: apply user-configured thresholds
            local selfHealThreshold = profile.defensives.selfHealThreshold or 80
            local cooldownThreshold = profile.defensives.cooldownThreshold or 60
            isLow = healthPercent <= selfHealThreshold
            isCritical = healthPercent <= cooldownThreshold
        end
    end
    
    local showOnlyInCombat = profile.defensives.showOnlyInCombat
    
    -- PRIORITY 1: Procced spells (shown at ANY health level)
    -- Check spellbook procs first
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    
    if ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs then
            for _, spellID in ipairs(defensiveProcs) do
                if #results >= maxIcons then break end
                if spellID and spellID > 0 and not alreadyAdded[spellID] then
                    local stillProcced = BlizzardAPI and BlizzardAPI.IsSpellProcced(spellID)
                    if stillProcced then
                        local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable(spellID)
                        if isKnown then
                            local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant(spellID, profile, true)
                            if not isRedundant then
                                local onCooldown = BlizzardAPI.IsSpellOnRealCooldown(spellID)
                                if not onCooldown then
                                    results[#results + 1] = {spellID = spellID, isItem = false, isProcced = true}
                                    alreadyAdded[spellID] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Check configured lists for procced spells
    if #results < maxIcons then
        local procs = self:GetUsableDefensiveSpells(profile.defensives.selfHealSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(procs) do
            if entry.isProcced then
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
    end
    if #results < maxIcons then
        local procs = self:GetUsableDefensiveSpells(profile.defensives.cooldownSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(procs) do
            if entry.isProcced then
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
    end
    
    -- "Only In Combat" check - if out of combat and no procs, return what we have (procs only)
    if showOnlyInCombat and not inCombat then
        return results
    end
    
    -- "Always Show" check - if enabled and we have room, add available spells regardless of health
    -- This shows off-cooldown defensives even at full health (useful for proactive play)
    local alwaysShow = profile.defensives.alwaysShowDefensive
    if alwaysShow and not isLow and not isCritical and #results < maxIcons then
        -- Add self-heals first (typically shorter cooldowns)
        local spells = self:GetUsableDefensiveSpells(profile.defensives.selfHealSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(spells) do
            results[#results + 1] = entry
            alreadyAdded[entry.spellID] = true
        end
        -- Then cooldowns if still have room
        if #results < maxIcons then
            local cooldowns = self:GetUsableDefensiveSpells(profile.defensives.cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(cooldowns) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        -- Return early - we've added what's available at full health
        return results
    end
    
    -- PRIORITY 2: Based on health level, add self-heals and cooldowns
    if isCritical then
        -- Critical: add cooldowns first, then self-heals
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(profile.defensives.cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(profile.defensives.selfHealSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        -- Add healing potion if room
        if #results < maxIcons then
            local potionID = self:FindHealingPotionOnActionBar()
            if potionID and not alreadyAdded[potionID] then
                results[#results + 1] = {spellID = potionID, isItem = true, isProcced = false}
                alreadyAdded[potionID] = true
            end
        end
    elseif isLow then
        -- Low: add self-heals, then cooldowns if room
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(profile.defensives.selfHealSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(profile.defensives.cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
    end
    
    return results
end

-- Healthstone item ID (always prioritized - free resource from Warlocks)
local HEALTHSTONE_ITEM_ID = 5512

-- Check if an item is a healing consumable by examining its spell effect
-- Returns true if the item appears to restore health
local function IsHealingConsumable(itemID)
    if not itemID then return false end
    
    -- Healthstone is always a healing consumable
    if itemID == HEALTHSTONE_ITEM_ID then return true end
    
    -- Check item class/subclass: must be Consumable (0) -> Potion (1)
    local _, _, _, _, _, _, classID, subclassID = GetItemInfo(itemID)
    if not classID or classID ~= 0 or subclassID ~= 1 then 
        return false 
    end
    
    -- Check the item's spell - healing potions restore health
    local spellName, spellID = GetItemSpell(itemID)
    if not spellName then return false end
    
    -- Common healing potion spell names contain these keywords
    local lowerName = spellName:lower()
    if lowerName:find("heal") or lowerName:find("restore") or lowerName:find("life") then
        return true
    end
    
    -- Check spell description for health restoration
    if spellID then
        local desc = GetSpellDescription(spellID)
        if desc then
            local lowerDesc = desc:lower()
            if lowerDesc:find("restore") and lowerDesc:find("health") then
                return true
            end
            if lowerDesc:find("heal") then
                return true
            end
        end
    end
    
    return false
end

-- Scan action bars for a usable healing consumable
-- Prioritizes: 1) Healthstones (free), 2) Any healing potion found
-- Returns: itemID, actionSlot (or nil if none found)
function JustAC:FindHealingPotionOnActionBar()
    local bestPotion = nil
    local bestSlot = nil
    
    for slot = 1, 180 do  -- All action bar slots including bonus bars
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then
            -- Check if we have the item and it's not on cooldown
            local count = GetItemCount(id) or 0
            if count > 0 then
                local start, duration = GetItemCooldown(id)
                local onCooldown = start and start > 0 and duration and duration > 1.5
                
                if not onCooldown then
                    -- Healthstone gets highest priority (free resource)
                    if id == HEALTHSTONE_ITEM_ID then
                        return id, slot
                    end
                    
                    -- Check if it's a healing consumable
                    if not bestPotion and IsHealingConsumable(id) then
                        bestPotion = id
                        bestSlot = slot
                    end
                end
            end
        end
    end
    
    return bestPotion, bestSlot
end

function JustAC:LoadModules()
    UIManager = LibStub("JustAC-UIManager", true)
    UIRenderer = LibStub("JustAC-UIRenderer", true)
    SpellQueue = LibStub("JustAC-SpellQueue", true)
    ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    FormCache = LibStub("JustAC-FormCache", true)
    Options = LibStub("JustAC-Options", true)
    MacroParser = LibStub("JustAC-MacroParser", true)
    RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    
    if not UIManager then self:Print("Error: UIManager module not found"); UIManager = {} end
    if not UIRenderer then self:Print("Error: UIRenderer module not found"); UIRenderer = {} end
    if not SpellQueue then self:Print("Error: SpellQueue module not found"); SpellQueue = {} end
    if not ActionBarScanner then self:Print("Warning: ActionBarScanner module not found"); ActionBarScanner = {} end
    if not BlizzardAPI then BlizzardAPI = self:CreateFallbackAPI() end
    if not FormCache then self:Print("Warning: FormCache module not found") end
    if not MacroParser then self:Print("Warning: MacroParser module not found") end
    if not RedundancyFilter then self:Print("Warning: RedundancyFilter module not found") end
end

function JustAC:CreateFallbackAPI()
    local self_ref = self
    return {
        GetNextCastSpell = function()
            if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
                local success, result = pcall(C_AssistedCombat.GetNextCastSpell, true)
                return success and result and type(result) == "number" and result > 0 and result or nil
            end
            return nil
        end,
        GetRotationSpells = function()
            if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
                local success, result = pcall(C_AssistedCombat.GetRotationSpells)
                return success and result and type(result) == "table" and #result > 0 and result or nil
            end
            return nil
        end,
        GetSpellInfo = function(spellID)
            if not spellID or spellID == 0 then return nil end
            if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(spellID) end
            local name, _, icon = GetSpellInfo(spellID)
            return name and {name = name, iconID = icon} or nil
        end,
        GetProfile = function()
            return self_ref.db and self_ref.db.profile or nil
        end,
        GetDebugMode = function()
            local profile = self_ref.db and self_ref.db.profile
            return profile and profile.debugMode or false
        end,
        IsSpellAvailable = function(spellID)
            if not spellID or spellID == 0 then return false end
            -- Check if spell is actually known to the player
            if IsSpellKnown then
                if IsSpellKnown(spellID) then return true end
                if IsSpellKnown(spellID, true) then return true end  -- Pet spells
            end
            -- Check spellbook
            if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
                if C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player) then
                    return true
                end
            end
            return false
        end,
        ClearAvailabilityCache = function() end,
    }
end

function JustAC:SetHotkeyOverride(spellID, hotkeyText)
    if not spellID or spellID == 0 then return end
    local charData = self.db and self.db.char
    if not charData then return end
    
    if not charData.hotkeyOverrides then
        charData.hotkeyOverrides = {}
    end
    
    if hotkeyText and hotkeyText:trim() ~= "" then
        charData.hotkeyOverrides[spellID] = hotkeyText:trim()
        local spellInfo = self:GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:DebugPrint("Hotkey: " .. spellName .. " = '" .. hotkeyText:trim() .. "'")
    else
        charData.hotkeyOverrides[spellID] = nil
        local spellInfo = self:GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:DebugPrint("Hotkey removed: " .. spellName)
    end
    
    -- Refresh defensive icon if it's showing this spell
    if self.defensiveIcon and self.defensiveIcon:IsShown() and self.defensiveIcon.spellID == spellID then
        UIManager.ShowDefensiveIcon(self, spellID, false)
    end
    
    -- Refresh options panel if open
    local Options = LibStub("JustAC-Options", true)
    if Options and Options.UpdateHotkeyOverrideOptions then
        Options.UpdateHotkeyOverrideOptions(self)
    end
    
    self:ForceUpdate()
end

function JustAC:GetHotkeyOverride(spellID)
    if not spellID or spellID == 0 then return nil end
    local charData = self.db and self.db.char
    if not charData or not charData.hotkeyOverrides then return nil end
    return charData.hotkeyOverrides[spellID]
end

function JustAC:OpenHotkeyOverrideDialog(spellID)
    if UIManager and UIManager.OpenHotkeyOverrideDialog then
        UIManager.OpenHotkeyOverrideDialog(self, spellID)
    end
end

function JustAC:GetProfile() return self.db and self.db.profile end
function JustAC:GetCachedSpellInfo(spellID) return SpellQueue and SpellQueue.GetCachedSpellInfo and SpellQueue.GetCachedSpellInfo(spellID) or nil end
function JustAC:IsSpellBlacklisted(spellID)
    if not SpellQueue or not SpellQueue.IsSpellBlacklisted then return false end
    return SpellQueue.IsSpellBlacklisted(spellID)
end
function JustAC:GetBlacklistedSpells() return SpellQueue and SpellQueue.GetBlacklistedSpells and SpellQueue.GetBlacklistedSpells() or {} end

function JustAC:ToggleSpellBlacklist(spellID)
    if SpellQueue and SpellQueue.ToggleSpellBlacklist then
        SpellQueue.ToggleSpellBlacklist(spellID)
        self:ForceUpdate()
    end
end

function JustAC:UpdateSpellQueue()
    if not self.db or not self.db.profile or self.db.profile.isManualMode or not self.mainFrame or not SpellQueue or not UIManager then return end

    local currentSpells = SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue() or {}
    UIManager.RenderSpellQueue(self, currentSpells)
end

function JustAC:PLAYER_ENTERING_WORLD()
    self:InitializeCaches()
    
    if FormCache and FormCache.OnPlayerLogin then
        FormCache.OnPlayerLogin()
    end
    
    local currentSpec = GetSpecialization()
    if currentSpec ~= self.db.char.lastKnownSpec then
        self.db.char.lastKnownSpec = currentSpec
    end
    
    self:ForceUpdate()
    
    -- Force update after delay to ensure Assisted Combat API has fully initialized
    -- The API may not return spells immediately after PLAYER_ENTERING_WORLD
    C_Timer.After(1.0, function() self:ForceUpdate() end)
    
    -- Check if Single-Button Assistant is placed on action bar (required for stable API behavior)
    C_Timer.After(2, function()
        if C_ActionBar and C_ActionBar.HasAssistedCombatActionButtons then
            local hasButton = C_ActionBar.HasAssistedCombatActionButtons()
            if not hasButton then
                local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat", true)
                if L and L["Single-Button Assistant Warning"] then
                    self:Print("|cffff8800" .. L["Single-Button Assistant Warning"] .. "|r")
                else
                    self:Print("|cffff8800Warning: Place the Single-Button Assistant on any action bar for JustAC to work properly.|r")
                end
            end
        end
    end)
end

function JustAC:OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: animate glows
        if UIRenderer and UIRenderer.SetCombatState then
            UIRenderer.SetCombatState(true)
        end
        if UIManager and UIManager.UnfreezeAllGlows then
            UIManager.UnfreezeAllGlows(self)
        end
        self:ForceUpdateAll()  -- Update both combat and defensive queues
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: freeze glows to reduce distraction
        if UIRenderer and UIRenderer.SetCombatState then
            UIRenderer.SetCombatState(false)
        end
        if UIManager and UIManager.FreezeAllGlows then
            UIManager.FreezeAllGlows(self)
        end
        -- Invalidate aura cache to force fresh check now that aura API is available
        local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
        if RedundancyFilter and RedundancyFilter.InvalidateCache then
            RedundancyFilter.InvalidateCache()
        end
        -- Clear in-combat activation tracking (like proc detection)
        if RedundancyFilter and RedundancyFilter.ClearActivationTracking then
            RedundancyFilter.ClearActivationTracking()
        end
        self:ForceUpdateAll()  -- Update both (hide defensive if showOnlyInCombat)
    end
end

function JustAC:OnSpecChange()
    -- Spec changes affect everything: spells, macros, keybinds
    if SpellQueue and SpellQueue.OnSpecChange then SpellQueue.OnSpecChange() end
    if SpellQueue and SpellQueue.ClearAvailabilityCache then SpellQueue.ClearAvailabilityCache() end
    if SpellQueue and SpellQueue.ClearSpellCache then SpellQueue.ClearSpellCache() end
    
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    
    if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
        ActionBarScanner.InvalidateHotkeyCache()
    end
    
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    
    self.db.char.lastKnownSpec = GetSpecialization()
    self:ForceUpdate()
end

function JustAC:OnSpellsChanged()
    if SpellQueue and SpellQueue.OnSpellsChanged then SpellQueue.OnSpellsChanged() end
    if SpellQueue and SpellQueue.ClearAvailabilityCache then SpellQueue.ClearAvailabilityCache() end
    
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    
    if ActionBarScanner and ActionBarScanner.InvalidateKeybindCache then
        ActionBarScanner.InvalidateKeybindCache()
    end
    
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    
    self:ForceUpdate()
end

-- Spell icon/override changed (transformations like Pyroblast → Hot Streak)
-- This fires when spell appearances change due to buffs, procs, or talents
function JustAC:OnSpellIconChanged()
    -- Invalidate hotkey cache since spell→slot mappings may have changed
    if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
        ActionBarScanner.InvalidateHotkeyCache()
    end
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormChanged()
    -- Form changes affect macro conditionals and spell overrides
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
        ActionBarScanner.InvalidateHotkeyCache()
    end
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormsRebuilt()
    -- Form bar rebuilt (login, talent change) - GetShapeshiftForm() now reliable
    local FormCache = LibStub("JustAC-FormCache", true)
    if FormCache then
        FormCache.InvalidateCache()
        FormCache.InvalidateSpellMapping()
    end
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
        ActionBarScanner.InvalidateHotkeyCache()
    end
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    self:ForceUpdate()
end

function JustAC:OnUnitAura(event, unit)
    if unit ~= "player" then return end
    
    local now = GetTime()
    if now - (self.lastAuraInvalidation or 0) > 0.5 then
        self.lastAuraInvalidation = now
        -- Aura changes affect RedundancyFilter's buff/form detection
        -- Note: Hotkey cache is NOT invalidated here - auras don't move slots
        -- SPELL_UPDATE_ICON handles spell transformations separately
        if RedundancyFilter and RedundancyFilter.InvalidateCache then
            RedundancyFilter.InvalidateCache()
        end
    end
end

function JustAC:OnActionBarChanged()
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then
        ActionBarScanner.OnKeybindsChanged()
    end
    
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    
    self:ForceUpdate()
end

function JustAC:OnSpecialBarChanged()
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then ActionBarScanner.OnSpecialBarChanged() end
    self:ForceUpdate()
end

-- Vehicle enter/exit completely changes actionbar layout
function JustAC:OnVehicleChanged(event, unit)
    if unit ~= "player" then return end
    
    -- Invalidate all caches: actionbar layout is completely different in vehicles
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then
        ActionBarScanner.OnSpecialBarChanged()
    end
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    self:ForceUpdate()
end

function JustAC:OnBindingsUpdated()
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then
        ActionBarScanner.OnKeybindsChanged()
        self:ForceUpdate()
    end
end

-- Proc glow events: Blizzard shows/hides overlay for proc abilities
-- More responsive than waiting for UNIT_AURA throttle
function JustAC:OnProcGlowChange(event, spellID)
    -- Update event-driven proc tracking in ActionBarScanner
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
    
    -- Procs don't change spell availability (IsSpellKnown), only priority
    -- spellAvailabilityCache has 2s TTL which handles any edge cases
    self:ForceUpdate()
    
    -- CRITICAL: Also update defensive icon immediately (ForceUpdate only updates main queue)
    self:OnHealthChanged(nil, "player")
end

-- Target changes: only ForceUpdate needed
-- MacroParser deliberately ignores [exists], [harm], [help], [dead] conditionals
-- for keybind detection (see MacroParser line 483), so no cache invalidation needed
function JustAC:OnTargetChanged()
    self:ForceUpdate()
end

-- Pet summon/dismiss affects pet-related spell suggestions
function JustAC:OnPetChanged(event, unit)
    if unit ~= "player" then return end
    -- Pet state changed - UnitExists("pet") is O(1), no cache to invalidate
    self:ForceUpdate()
end

-- Equipment change affects item spell detection (trinkets, engineering tinkers)
function JustAC:OnEquipmentChanged(event, slot, hasCurrent)
    -- Refresh item spell cache if BlizzardAPI is available
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI and BlizzardAPI.RefreshItemSpellCache then
        BlizzardAPI.RefreshItemSpellCache()
    end
    self:ForceUpdate()
end

-- Post-cast refresh: trigger update right after spell completion
-- More responsive than waiting for next OnUpdate tick
function JustAC:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    
    -- Record activation for redundancy filter (mirrors proc detection system)
    if UnitAffectingCombat("player") and RedundancyFilter and RedundancyFilter.RecordSpellActivation then
        RedundancyFilter.RecordSpellActivation(spellID)
    end
    
    -- Small delay to let game state settle, then refresh
    if self.castSuccessTimer then self:CancelTimer(self.castSuccessTimer) end
    self.castSuccessTimer = self:ScheduleTimer("ForceUpdate", 0.02)
end

-- Cooldown changes affect both combat queue and defensive suggestions
function JustAC:OnCooldownUpdate()
    -- Throttle to prevent spam
    if self.cooldownTimer then self:CancelTimer(self.cooldownTimer); self.cooldownTimer = nil end
    self.cooldownTimer = self:ScheduleTimer("ForceUpdateAll", 0.1)
end

-- Update both queues
function JustAC:ForceUpdateAll()
    if self.cooldownTimer then self:CancelTimer(self.cooldownTimer); self.cooldownTimer = nil end
    
    -- Update combat queue
    if SpellQueue and SpellQueue.ForceUpdate then SpellQueue.ForceUpdate() end
    self:UpdateSpellQueue()
    
    -- Re-evaluate defensive suggestion (cooldowns may have changed)
    self:OnHealthChanged(nil, "player")
end

function JustAC:ScheduleUpdate()
    if self.cooldownTimer then self:CancelTimer(self.cooldownTimer); self.cooldownTimer = nil end
    self.cooldownTimer = self:ScheduleTimer("ForceUpdate", 0.1)
end

function JustAC:ForceUpdate()
    if self.cooldownTimer then self:CancelTimer(self.cooldownTimer); self.cooldownTimer = nil end
    if SpellQueue and SpellQueue.ForceUpdate then SpellQueue.ForceUpdate() end
    self:UpdateSpellQueue()
end

function JustAC:OpenOptionsPanel()
    -- Refresh dynamic options before opening panel
    local Options = LibStub("JustAC-Options", true)
    if Options then
        if self.InitializeDefensiveSpells then
            self:InitializeDefensiveSpells()
        end
        if Options.UpdateBlacklistOptions then Options.UpdateBlacklistOptions(self) end
        if Options.UpdateHotkeyOverrideOptions then Options.UpdateHotkeyOverrideOptions(self) end
        if Options.UpdateDefensivesOptions then Options.UpdateDefensivesOptions(self) end
    end
    
    -- Version-aware settings panel opening
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI and BlizzardAPI.IsMidnightOrLater() then
        -- 12.0+: Use AceConfigDialog directly (Settings.OpenToCategory changed signature)
        local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
        if AceConfigDialog then
            AceConfigDialog:Open("JustAssistedCombat")
        end
    else
        -- Pre-12.0: Original Settings.OpenToCategory works with string
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory("JustAssistedCombat")
        end
    end
end

function JustAC:StartUpdates()
    if self.updateFrame then return end
    
    self.updateFrame = CreateFrame("Frame")
    self.updateTimeLeft = 0
    
    self.updateFrame:SetScript("OnUpdate", function(_, elapsed)
        self.updateTimeLeft = (self.updateTimeLeft or 0) - elapsed
        
        local inCombat = UnitAffectingCombat("player")
        local baseUpdateRate = tonumber(GetCVar("assistedCombatIconUpdateRate")) or 0.05
        
        -- Faster in combat for responsiveness, slower OOC since events drive most updates
        local updateRate
        if inCombat then
            updateRate = math.max(baseUpdateRate, 0.03)  -- Keep fast for combat responsiveness
        else
            updateRate = math.max(baseUpdateRate * 2.5, 0.15)  -- Slower OOC, events handle changes
        end
        
        if self.updateTimeLeft <= 0 then
            self.updateTimeLeft = updateRate
            self:UpdateSpellQueue()
        end
    end)
end

function JustAC:StopUpdates()
    if self.updateFrame then
        self.updateFrame:SetScript("OnUpdate", nil)
        self.updateFrame = nil
    end
end

function JustAC:UpdateFrameSize()
    if UIManager and UIManager.UpdateFrameSize then UIManager.UpdateFrameSize(self) end
    if UIManager and UIManager.UpdateHealthBarSize then UIManager.UpdateHealthBarSize(self) end
    self:ForceUpdate()
end

function JustAC:SavePosition()
    if UIManager and UIManager.SavePosition then UIManager.SavePosition(self) end
    self:ForceUpdate()
end