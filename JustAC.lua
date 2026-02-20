-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIRenderer, UIFrameFactory, UIAnimations, UIHealthBar, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter, UINameplateOverlay

-- Class default tables are stored in SpellDB.lua for consistency
-- Access via JustAC.CLASS_*_DEFAULTS (set in OnInitialize after SpellDB loads)

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
        showOffensiveHotkeys = true, -- Show hotkey text on offensive queue icons
        gamepadIconStyle = "xbox",    -- Gamepad button icons: "generic", "xbox", "playstation"
        debugMode = false,
        isManualMode = false,
        tooltipMode = "always",       -- "never", "outOfCombat", or "always"
        glowMode = "all",                 -- "all", "primaryOnly", "procOnly", "none"
        showFlash = true,                 -- Flash icon on matching key press
        firstIconScale = 1.2,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueOutOfCombat = false,  -- Hide the entire queue when out of combat
        hideQueueForHealers = false,   -- Hide the entire queue when in a healer spec
        hideQueueWhenMounted = false,  -- Hide the queue while mounted
        displayMode = "queue",         -- "disabled" / "queue" / "overlay" / "both"
        requireHostileTarget = false,  -- Only show queue when targeting a hostile unit
        hideItemAbilities = false,     -- Hide equipped item abilities (trinkets, tinkers)
        enableItemFeatures = true,     -- Master toggle for all item-related features
        panelLocked = false,              -- Legacy (migrated to panelInteraction)
        panelInteraction = "unlocked",    -- "unlocked", "locked", "clickthrough"
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        targetFrameAnchor = "DISABLED",     -- Anchor to target frame: DISABLED, TOP, BOTTOM, LEFT, RIGHT
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals
        hotkeyOverrides = {},             -- Profile-level hotkey display overrides (included in profile copy)
        -- Nameplate Overlay feature (independent queue cluster on target nameplate)
        nameplateOverlay = {
            maxIcons          = 3,       -- 1-3 DPS queue slots
            anchor            = "RIGHT", -- LEFT, RIGHT
            expansion         = "out",   -- "out" (horizontal), "up" (vertical up), "down" (vertical down)
            healthBarPosition = "outside", -- "outside" (far end of cluster) or "inside" (nameplate end); up/down only
            iconSize          = 32,
            showGlow          = true,
            glowMode          = "all",
            showHotkey        = true,
            showDefensives       = true,
            maxDefensiveIcons    = 3,    -- 1-3
            defensiveDisplayMode = "combatOnly", -- "combatOnly", "always"
            defensiveShowProcs   = true,
            showHealthBar        = true,
        },
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            showProcs = true,         -- Show procced defensives (Victory Rush, free heals) at any health
            glowMode = "procOnly",     -- "all", "primaryOnly", "procOnly", "none"
            showFlash = true,         -- Flash icon on matching key press
            showHotkeys = true,       -- Show hotkey text on defensive icons
            position = "SIDE1",       -- SIDE1 (health bar side), SIDE2, or LEADING (opposite grab tab)
            showHealthBar = false,    -- Display compact health bar above main queue
            showPetHealthBar = false, -- Display compact pet health bar (pet classes only)
            iconScale = 1.2,          -- Scale for defensive icons (same range as Primary Spell Scale)
            maxIcons = 3,             -- Number of defensive icons to show (1-3)
            -- NOTE: In 12.0 combat, UnitHealth() is secret. These thresholds only
            -- apply out of combat. In combat, we fall back to Blizzard's LowHealthFrame
            -- overlay which provides two binary states: "low" (~35%) and "critical" (~20%).
            selfHealThreshold = 80,   -- Out-of-combat only: show self-heals below this %
            cooldownThreshold = 60,   -- Out-of-combat only: show major cooldowns below this %
            petHealThreshold = 50,    -- Out-of-combat only: show pet heals below this pet %
            allowItems = false,       -- Allow manual item insertion in defensive spell lists
            autoInsertPotions = true,  -- Auto-insert health potions at critical health
            classSpells = {},         -- Per-class spell lists: classSpells["WARRIOR"] = {selfHealSpells={...}, cooldownSpells={...}, petHealSpells={}}
            displayMode = "combatOnly", -- "healthBased" (show when low), "combatOnly" (always in combat), "always"
        },
    },
    char = {
        lastKnownSpec = nil,
        firstRun = true,
        blacklistedSpells = {},   -- Character-specific spell blacklist
        hotkeyOverrides = {},     -- Legacy: migrated to profile on load; kept as schema for migration detection
        specProfilesEnabled = true,   -- Auto-switch profiles by spec (enabled by default)
        specProfiles = {},        -- [specIndex] = "profileName" | "DISABLED" | nil
    },
    global = {},
}

function JustAC:DebugPrint(msg)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print(msg)
    end
end

-- SavedVariables serialize numeric keys as strings; normalize on load
function JustAC:NormalizeSavedData()
    local charData = self.db and self.db.char
    if not charData then return end
    
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
        -- Normalize profile.hotkeyOverrides (SavedVariables serialise numeric keys as strings)
        if profile.hotkeyOverrides then
            local normalized = {}
            for key, value in pairs(profile.hotkeyOverrides) do
                local spellID = tonumber(key)
                if spellID and spellID > 0 and type(value) == "string" and value ~= "" then
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
                if spellID and spellID > 0 and type(value) == "string" and value ~= "" and not profile.hotkeyOverrides[spellID] then
                    profile.hotkeyOverrides[spellID] = value
                end
            end
            charData.hotkeyOverrides = {}  -- Clear after migration
        end
        -- Migrate panelLocked boolean → panelInteraction string
        if profile.panelLocked == true and (not profile.panelInteraction or profile.panelInteraction == "unlocked") then
            profile.panelInteraction = "locked"
        end
    end
end

function JustAC:OnInitialize()
    self.db = AceDB:New("JustACDB", defaults)

    -- Initialize binding globals before combat (prevents taint)
    if not _G.BINDING_NAME_JUSTAC_CAST_FIRST then
        _G.BINDING_NAME_JUSTAC_CAST_FIRST = "JustAC: Cast First Spell"
        _G.BINDING_HEADER_JUSTAC = "JustAssistedCombat"
    end
    
    -- Set CLASS_*_DEFAULTS references from SpellDB
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if SpellDB then
        JustAC.CLASS_SELFHEAL_DEFAULTS = SpellDB.CLASS_SELFHEAL_DEFAULTS
        JustAC.CLASS_COOLDOWN_DEFAULTS = SpellDB.CLASS_COOLDOWN_DEFAULTS
        JustAC.CLASS_PETHEAL_DEFAULTS = SpellDB.CLASS_PETHEAL_DEFAULTS
        JustAC.CLASS_PET_REZ_DEFAULTS = SpellDB.CLASS_PET_REZ_DEFAULTS
    end
    
    self:NormalizeSavedData()
    self:InitializeDefensiveSpells()

    self:LoadModules()
    
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")
    
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

    -- Apply target frame anchor if enabled (before icons so position is correct)
    self:UpdateTargetFrameAnchor()

    UIFrameFactory.CreateSpellIcons(self)

    -- Must be after CreateSpellIcons
    if UIHealthBar and UIHealthBar.CreateHealthBar then
        UIHealthBar.CreateHealthBar(self)
    end
    if UIHealthBar and UIHealthBar.CreatePetHealthBar then
        UIHealthBar.CreatePetHealthBar(self)
    end

    if UnitAffectingCombat("player") then
        if UIAnimations and UIAnimations.ResumeAllGlows then UIAnimations.ResumeAllGlows(self) end
    else
        if UIAnimations and UIAnimations.PauseAllGlows then UIAnimations.PauseAllGlows(self) end
    end
    
    self:InitializeCaches()
    self:StartUpdates()

    -- Create key press detector for flash feedback
    self:CreateKeyPressDetector()

    -- Nameplate overlay (fully independent of main panel)
    if UINameplateOverlay then UINameplateOverlay.Create(self) end
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED",   "OnNamePlateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNamePlateRemoved")

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    self:RegisterEvent("UNIT_HEALTH", "OnHealthChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChange")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "OnActionBarChanged")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "OnActionBarChanged")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "OnSpecialBarChanged")
    
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshiftFormChanged")
    -- GetShapeshiftForm() returns nil until this fires
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", "OnShapeshiftFormsRebuilt")

    -- Throttle to prevent flicker from buff-based spell overrides
    self.lastAuraInvalidation = 0
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsUpdated")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
    self:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST", "ForceUpdate")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowChange")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowChange")
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellIconChanged")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("UNIT_PET", "OnPetChanged")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("UNIT_ENTERED_VEHICLE", "OnVehicleChanged")
    self:RegisterEvent("UNIT_EXITED_VEHICLE", "OnVehicleChanged")

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
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function()
            self:ForceUpdate()
        end, self)
    end
    
    if self.db.char.firstRun then
        self.db.char.firstRun = false
        local numSpecs = GetNumSpecializations()
        for i = 1, numSpecs do
            local role = GetSpecializationRole(i)
            if role == "HEALER" then
                self.db.char.specProfiles[i] = "DISABLED"
            end
        end
    end
    
    self:ScheduleTimer("DelayedValidation", 2)
end

function JustAC:InitializeCaches()
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
    
    self:InvalidateCaches({macros = true, auras = true})

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

-- Minimal mode: stops updates but keeps spec change listener active
function JustAC:EnterDisabledMode()
    if self.isDisabledMode then return end
    self.isDisabledMode = true

    self:StopUpdates()

    if self.mainFrame then
        self.mainFrame:Hide()
    end

    -- Hide defensive icons
    if self.defensiveIcons then
        for _, icon in ipairs(self.defensiveIcons) do
            if icon then icon:Hide() end
        end
    end
    if self.defensiveIcon then
        self.defensiveIcon:Hide()
    end

    -- Hide health bar
    if UIHealthBar and UIHealthBar.Hide then
        UIHealthBar.Hide()
    end
    if UIHealthBar and UIHealthBar.HidePet then
        UIHealthBar.HidePet()
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

    -- Restore health bar if setting is enabled
    local profile = self:GetProfile()
    if UIHealthBar and profile and profile.defensives then
        if profile.defensives.showHealthBar and UIHealthBar.Show then
            UIHealthBar.Show()
        end
        if profile.defensives.showPetHealthBar and UIHealthBar.UpdatePetVisibility then
            UIHealthBar.UpdatePetVisibility(self)
        end
    end

    -- Restore nameplate overlay if enabled
    if UINameplateOverlay then UINameplateOverlay.UpdateAnchor(self) end

    self:ForceUpdateAll()
    self:DebugPrint("Exited disabled mode")
end

function JustAC:RefreshConfig()
    -- Migrate old profile-level data (blacklist/hotkeys/panelLocked) if switching to an un-migrated profile
    self:NormalizeSavedData()
    -- Blacklist/spec profiles are character-specific; hotkey overrides travel with the profile
    self:InitializeDefensiveSpells()

    self:UpdateFrameSize()
    if self.mainFrame then
        local profile = self:GetProfile()
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
        -- Save before anchoring so we preserve UIParent-relative coords as fallback
        self:SavePosition()
        self:UpdateTargetFrameAnchor()
    end
    if UINameplateOverlay then
        UINameplateOverlay.Destroy(self)
        UINameplateOverlay.Create(self)
    end
    self:ForceUpdate()
end

-- Only on explicit profile reset (not change/copy)
-- Character data (blacklist, spec profiles) is intentionally preserved;
-- Profile-level data (hotkey overrides, settings) is cleared — that's what a reset does.
-- AceDB already resets profile-level settings to defaults.
function JustAC:OnProfileReset()
    self:RefreshConfig()
end

function JustAC:ShowWelcomeMessage()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then return end
    self:Print("Debug mode active")
end

-- Returns the spell list for a given type ("selfHealSpells", "cooldownSpells", "petHealSpells")
-- for the current player class from the per-class nested structure.
function JustAC:GetClassSpellList(listKey)
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end

    local _, playerClass = UnitClass("player")
    if not playerClass then return nil end

    local classSpells = profile.defensives.classSpells
    if not classSpells or not classSpells[playerClass] then return nil end

    return classSpells[playerClass][listKey]
end

-- Migrate pre-3.25 flat spell lists (selfHealSpells/cooldownSpells/petHealSpells)
-- into the new per-class classSpells structure. Safe to call multiple times.
function JustAC:MigrateDefensiveSpellsToClassSpells()
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end

    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    local def = profile.defensives
    local hasFlatData = (def.selfHealSpells and #def.selfHealSpells > 0)
        or (def.cooldownSpells and #def.cooldownSpells > 0)
        or (def.petHealSpells and #def.petHealSpells > 0)

    if not hasFlatData then return end

    -- Ensure classSpells table exists
    if not def.classSpells then def.classSpells = {} end

    -- Only migrate if this class doesn't already have nested data
    if not def.classSpells[playerClass] then
        def.classSpells[playerClass] = {}
    end
    local cs = def.classSpells[playerClass]

    -- Move flat lists into per-class structure (don't overwrite existing)
    if def.selfHealSpells and #def.selfHealSpells > 0 and (not cs.selfHealSpells or #cs.selfHealSpells == 0) then
        cs.selfHealSpells = {}
        for i, spellID in ipairs(def.selfHealSpells) do
            cs.selfHealSpells[i] = spellID
        end
    end

    if def.cooldownSpells and #def.cooldownSpells > 0 and (not cs.cooldownSpells or #cs.cooldownSpells == 0) then
        cs.cooldownSpells = {}
        for i, spellID in ipairs(def.cooldownSpells) do
            cs.cooldownSpells[i] = spellID
        end
    end

    if def.petHealSpells and #def.petHealSpells > 0 and (not cs.petHealSpells or #cs.petHealSpells == 0) then
        cs.petHealSpells = {}
        for i, spellID in ipairs(def.petHealSpells) do
            cs.petHealSpells[i] = spellID
        end
    end

    -- Clear flat keys so migration won't re-trigger
    def.selfHealSpells = nil
    def.cooldownSpells = nil
    def.petHealSpells = nil

    self:DebugPrint("Migrated flat defensive spells to classSpells[" .. playerClass .. "]")
end

function JustAC:InitializeDefensiveSpells()
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end

    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    -- Migrate legacy flat lists on first load
    self:MigrateDefensiveSpellsToClassSpells()

    -- Ensure classSpells table structure exists
    local def = profile.defensives
    if not def.classSpells then def.classSpells = {} end
    if not def.classSpells[playerClass] then def.classSpells[playerClass] = {} end
    local cs = def.classSpells[playerClass]

    if not cs.selfHealSpells or #cs.selfHealSpells == 0 then
        local healDefaults = JustAC.CLASS_SELFHEAL_DEFAULTS and JustAC.CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            cs.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                cs.selfHealSpells[i] = spellID
            end
        end
    end

    if not cs.cooldownSpells or #cs.cooldownSpells == 0 then
        local cdDefaults = JustAC.CLASS_COOLDOWN_DEFAULTS and JustAC.CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            cs.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                cs.cooldownSpells[i] = spellID
            end
        end
    end

    if not cs.petHealSpells or #cs.petHealSpells == 0 then
        local petDefaults = JustAC.CLASS_PETHEAL_DEFAULTS and JustAC.CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            cs.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                cs.petHealSpells[i] = spellID
            end
        end
    end

    if not cs.petRezSpells or #cs.petRezSpells == 0 then
        local rezDefaults = JustAC.CLASS_PET_REZ_DEFAULTS and JustAC.CLASS_PET_REZ_DEFAULTS[playerClass]
        if rezDefaults then
            cs.petRezSpells = {}
            for i, spellID in ipairs(rezDefaults) do
                cs.petRezSpells[i] = spellID
            end
        end
    end

    self:RegisterDefensivesForTracking()
end

-- Enables 12.0 compatibility when C_Spell.GetSpellCooldown returns secrets
function JustAC:RegisterDefensivesForTracking()
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if not BlizzardAPI or not BlizzardAPI.RegisterDefensiveSpell then return end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end

    if BlizzardAPI.ClearTrackedDefensives then
        BlizzardAPI.ClearTrackedDefensives()
    end

    -- Table-driven iteration: register all defensive spell lists
    local spellListTypes = { "selfHealSpells", "cooldownSpells", "petHealSpells", "petRezSpells" }
    for _, listType in ipairs(spellListTypes) do
        local spellList = self:GetClassSpellList(listType)
        if spellList then
            for _, entry in ipairs(spellList) do
                -- Only register positive entries (spells) — negative entries are items
                if entry and entry > 0 then
                    BlizzardAPI.RegisterDefensiveSpell(entry)
                end
            end
        end
    end
end

function JustAC:RestoreDefensiveDefaults(listType)
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end
    
    local _, playerClass = UnitClass("player")
    if not playerClass then return end

    -- Ensure classSpells structure exists
    if not profile.defensives.classSpells then profile.defensives.classSpells = {} end
    if not profile.defensives.classSpells[playerClass] then profile.defensives.classSpells[playerClass] = {} end
    local cs = profile.defensives.classSpells[playerClass]
    
    if listType == "selfheal" then
        local healDefaults = JustAC.CLASS_SELFHEAL_DEFAULTS and JustAC.CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            cs.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                cs.selfHealSpells[i] = spellID
            end
        end
    elseif listType == "cooldown" then
        local cdDefaults = JustAC.CLASS_COOLDOWN_DEFAULTS and JustAC.CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            cs.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                cs.cooldownSpells[i] = spellID
            end
        end
    elseif listType == "petheal" then
        local petDefaults = JustAC.CLASS_PETHEAL_DEFAULTS and JustAC.CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            cs.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                cs.petHealSpells[i] = spellID
            end
        end
    elseif listType == "petrez" then
        local rezDefaults = JustAC.CLASS_PET_REZ_DEFAULTS and JustAC.CLASS_PET_REZ_DEFAULTS[playerClass]
        if rezDefaults then
            cs.petRezSpells = {}
            for i, spellID in ipairs(rezDefaults) do
                cs.petRezSpells[i] = spellID
            end
        end
    end

    self:RegisterDefensivesForTracking()
    self:OnHealthChanged(nil, "player")
end

-- Throttle for UNIT_HEALTH events (fires very frequently in combat)
local lastHealthUpdate = 0
local HEALTH_UPDATE_THROTTLE = 0.1  -- 100ms minimum between defensive queue updates
-- Pooled tables to avoid GC pressure in OnHealthChanged / GetDefensiveSpellQueue
local dpsQueueExclusions = {}
local defensiveAlreadyAdded = {}
-- Pooled tables for GetUsableDefensiveSpells (avoids per-call allocations)
local usableResults = {}
local usableAddedHere = {}

function JustAC:OnHealthChanged(event, unit)
    if self.isDisabledMode then return end
    if unit ~= "player" and unit ~= "pet" then return end

    local profile = self:GetProfile()
    local def = profile and profile.defensives

    -- Resolve overlay state once (UINameplateOverlay may not be loaded)
    local npo = UINameplateOverlay and (profile and profile.nameplateOverlay)
    local overlayDM = profile and profile.displayMode or "queue"
    local overlayActive = npo and (overlayDM == "overlay" or overlayDM == "both")

    -- Early exit: nothing at all to do for health events
    local needsAnyWork = (def and (def.enabled or def.showHealthBar or def.showPetHealthBar))
        or (overlayActive and (npo.showHealthBar or npo.showDefensives))
    if not needsAnyWork then return end

    -- Health bars are cheap; update them without throttling
    if def then
        if def.showHealthBar and UIHealthBar and UIHealthBar.Update then UIHealthBar.Update(self) end
        if def.showPetHealthBar and UIHealthBar and UIHealthBar.UpdatePet then UIHealthBar.UpdatePet(self) end
    end
    if overlayActive and npo.showHealthBar then UINameplateOverlay.UpdateHealthBar() end

    -- Throttle defensive queue updates (expensive: table allocations, spell lookups)
    local now = GetTime()
    if event and now - lastHealthUpdate < HEALTH_UPDATE_THROTTLE then return end
    lastHealthUpdate = now

    -- Skip queue work if neither path needs it
    local needsDefensives = (def and def.enabled) or (overlayActive and npo.showDefensives)
    if not needsDefensives then return end

    -- Health state — computed once, shared by main panel and overlay paths
    local inCombat = UnitAffectingCombat("player")

    -- Falls back to LowHealthFrame when UnitHealth() returns secrets
    local healthPercent, isEstimated = nil, false
    if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
        healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
    end

    local selfHealThreshold = def and def.selfHealThreshold or 80
    local cooldownThreshold = def and def.cooldownThreshold or 60

    -- 12.0: UnitHealth() is secret in combat (PvE and PvP). When isEstimated=true,
    -- thresholds above are ignored — we use Blizzard's LowHealthFrame binary states:
    --   "low"  = ~35% health → shows self-heals
    --   "critical" = ~20% health → shows major cooldowns
    -- Thresholds only matter out of combat (between pulls, open world, etc.)
    local isCritical, isLow
    if isEstimated then
        local lowState, critState = false, false
        if BlizzardAPI.GetLowHealthState then
            lowState, critState = BlizzardAPI.GetLowHealthState()
        end
        isCritical = critState
        isLow = lowState
    elseif healthPercent then
        isLow = healthPercent <= selfHealThreshold
        isCritical = healthPercent <= cooldownThreshold
    else
        isCritical = false
        isLow = false
    end

    -- 12.0: UnitHealth("pet") is secret in combat → GetPetHealthPercent() returns nil.
    -- Pet heals only trigger out of combat (between pulls, open world). This is by design.
    local petHealthPercent = BlizzardAPI and BlizzardAPI.GetPetHealthPercent and BlizzardAPI.GetPetHealthPercent()
    local petHealThreshold = def and def.petHealThreshold or 50
    local petNeedsHeal = petHealthPercent and petHealthPercent <= petHealThreshold

    -- UnitIsDead/UnitExists are NOT secret — pet rez/summon works reliably in combat
    local petStatus = BlizzardAPI and BlizzardAPI.GetPetStatus and BlizzardAPI.GetPetStatus()
    local petNeedsRez = (petStatus == "dead" or petStatus == "missing")

    -- DPS exclusions shared by both paths (reuse pooled table)
    wipe(dpsQueueExclusions)
    if SpellQueue and SpellQueue.GetCurrentSpellQueue then
        local dpsQueue = SpellQueue.GetCurrentSpellQueue()
        local maxDpsIcons = profile.maxIcons or 4
        for i = 1, math.min(#dpsQueue, maxDpsIcons) do
            if dpsQueue[i] then dpsQueueExclusions[dpsQueue[i]] = true end
        end
    end

    -- Main panel defensive queue (gated by defensives.enabled)
    if def and def.enabled then
        local defensiveQueue = self:GetDefensiveSpellQueue(isLow, isCritical, inCombat, dpsQueueExclusions)
        local maxIcons = def.maxIcons or 1

        -- Pet rez/summon: HIGH priority — pet dead or missing (reliable in combat)
        -- Uses defensiveAlreadyAdded from GetDefensiveSpellQueue to avoid duplicates
        if petNeedsRez and #defensiveQueue < maxIcons then
            local petRez = self:GetUsableDefensiveSpells(self:GetClassSpellList("petRezSpells"), maxIcons - #defensiveQueue, defensiveAlreadyAdded)
            for _, entry in ipairs(petRez) do
                defensiveQueue[#defensiveQueue + 1] = entry
                defensiveAlreadyAdded[entry.spellID] = true
            end
        end

        -- Pet heals: LOWER priority — out-of-combat only (health is secret in combat)
        if petNeedsHeal and not petNeedsRez and #defensiveQueue < maxIcons then
            local petHeals = self:GetUsableDefensiveSpells(self:GetClassSpellList("petHealSpells"), maxIcons - #defensiveQueue, defensiveAlreadyAdded)
            for _, entry in ipairs(petHeals) do
                defensiveQueue[#defensiveQueue + 1] = entry
                defensiveAlreadyAdded[entry.spellID] = true
            end
        end

        if #defensiveQueue > 0 then
            if self.defensiveIcons and #self.defensiveIcons > 0 and UIRenderer and UIRenderer.ShowDefensiveIcons then
                UIRenderer.ShowDefensiveIcons(self, defensiveQueue)
            elseif self.defensiveIcon and UIRenderer and UIRenderer.ShowDefensiveIcon then
                UIRenderer.ShowDefensiveIcon(self, defensiveQueue[1].spellID, defensiveQueue[1].isItem, self.defensiveIcon)
            end
        else
            if self.defensiveIcons and #self.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
                UIRenderer.HideDefensiveIcons(self)
            elseif self.defensiveIcon and UIRenderer and UIRenderer.HideDefensiveIcon then
                UIRenderer.HideDefensiveIcon(self.defensiveIcon)
            end
        end
    else
        -- Defensives disabled on main panel: ensure icons are hidden
        if self.defensiveIcons and #self.defensiveIcons > 0 and UIRenderer and UIRenderer.HideDefensiveIcons then
            UIRenderer.HideDefensiveIcons(self)
        elseif self.defensiveIcon and UIRenderer and UIRenderer.HideDefensiveIcon then
            UIRenderer.HideDefensiveIcon(self.defensiveIcon)
        end
    end

    -- Nameplate overlay defensive queue — independent of defensives.enabled.
    -- Uses its own display mode and icon count settings. GetDefensiveSpellQueue wipes
    -- defensiveAlreadyAdded at the start of each call, so no bleed from the main panel path.
    if overlayActive and npo.showDefensives then
        local npoDisplayMode = npo.defensiveDisplayMode or "combatOnly"
        local npoMaxIcons    = npo.maxDefensiveIcons or 1
        local npoShowProcs   = npo.defensiveShowProcs ~= false
        local npoQueue = self:GetDefensiveSpellQueue(isLow, isCritical, inCombat, dpsQueueExclusions, npoDisplayMode, npoMaxIcons, npoShowProcs)
        if #npoQueue > 0 then
            UINameplateOverlay.RenderDefensives(self, npoQueue)
        else
            UINameplateOverlay.HideDefensiveIcons()
        end
    end
end

-- Returns any procced defensive spell (Victory Rush, etc.) at ANY health level
function JustAC:GetProccedDefensiveSpell()
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end

    -- Check if proc detection is enabled
    if profile.defensives.showProcs == false then return nil end

    -- Use module-level cached references (populated in LoadModules)
    if ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs and #defensiveProcs > 0 then
            for _, spellID in ipairs(defensiveProcs) do
                if spellID and spellID > 0 then
                    local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
                    if isUsable and isProcced then
                        return spellID
                    end
                end
            end
        end
    end

    local selfHealSpells = self:GetClassSpellList("selfHealSpells")
    local cooldownSpells = self:GetClassSpellList("cooldownSpells")
    for pass = 1, 2 do
        local spellList = pass == 1 and selfHealSpells or cooldownSpells
        if spellList then
            for _, entry in ipairs(spellList) do
                -- Items (negative entries) can't proc, skip them
                if entry and entry > 0 then
                    local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(entry, profile)
                    if isUsable and isProcced then
                        return entry
                    end
                end
            end
        end
    end
    
    return nil
end

-- First usable spell from list, prioritizing procs (Victory Rush, free heal procs)
function JustAC:GetBestDefensiveSpell(spellList)
    if not spellList then return nil end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end

    local debugMode = profile.debugMode
    if debugMode then
        self:DebugPrint("GetBestDefensiveSpell called with " .. #spellList .. " spells in list")
    end

    -- Procced spells from spellbook take priority (free/instant)
    if profile.defensives.showProcs ~= false and ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs then
            for _, spellID in ipairs(defensiveProcs) do
                if spellID and spellID > 0 then
                    local isUsable = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
                    if isUsable then
                        return spellID
                    end
                end
            end
        end
    end

    for i, entry in ipairs(spellList) do
        if entry and entry > 0 then
            local isUsable, isKnown, isRedundant, onCooldown, isProcced = BlizzardAPI.CheckDefensiveSpellState(entry, profile)
            
            if debugMode then
                local spellInfo = C_Spell.GetSpellInfo(entry)
                local name = spellInfo and spellInfo.name or "Unknown"
                self:DebugPrint(string.format("Checking defensive spell %d/%d: %s (%d)", i, #spellList, name, entry))
                
                if not isKnown then
                    self:DebugPrint(string.format("  SKIP: %s - not known/available", name))
                elseif isRedundant then
                    self:DebugPrint(string.format("  SKIP: %s - redundant (buff active)", name))
                elseif onCooldown then
                    local start, duration = BlizzardAPI.GetSpellCooldownValues(entry)
                    self:DebugPrint(string.format("  SKIP: %s - on cooldown (start=%s, duration=%s)", 
                        name, tostring(start or 0), tostring(duration or 0)))
                else
                    local start, duration = BlizzardAPI.GetSpellCooldownValues(entry)
                    self:DebugPrint(string.format("  PASS: %s - onCooldown=false, start=%s, duration=%s", 
                        name, tostring(start or 0), tostring(duration or 0)))
                end
            end

            if isUsable then
                return entry
            end
        elseif entry and entry < 0 then
            -- Negative entry = item ID
            local itemID = -entry
            local isUsable = BlizzardAPI.CheckDefensiveItemState(itemID, profile)

            if debugMode then
                local itemName = GetItemInfo(itemID) or "Unknown Item"
                self:DebugPrint(string.format("Checking defensive item %d/%d: %s (item:%d)", i, #spellList, itemName, itemID))
                if isUsable then
                    self:DebugPrint(string.format("  PASS: %s - usable", itemName))
                else
                    self:DebugPrint(string.format("  SKIP: %s - not usable", itemName))
                end
            end

            if isUsable then
                return itemID, true  -- return itemID, isItem=true
            end
        end
    end

    return nil
end

-- Returns up to maxCount usable spells/items, prioritizing procs
-- Uses module-level pooled tables (usableResults/usableAddedHere) to avoid per-call allocations
-- IMPORTANT: Caller must consume results before next call (table is reused)
-- List entries: positive = spell ID, negative = item ID (-itemID)
function JustAC:GetUsableDefensiveSpells(spellList, maxCount, alreadyAdded)
    wipe(usableResults)
    if not spellList or maxCount <= 0 then return usableResults end

    local profile = self:GetProfile()
    if not profile or not profile.defensives then return usableResults end

    alreadyAdded = alreadyAdded or {}
    wipe(usableAddedHere)

    -- First pass: add procced spells (higher priority) - items can't proc
    for _, entry in ipairs(spellList) do
        if #usableResults >= maxCount then break end
        if entry and entry > 0 and not alreadyAdded[entry] and not usableAddedHere[entry] then
            local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(entry, profile)
            if isUsable and isProcced then
                usableResults[#usableResults + 1] = {spellID = entry, isItem = false, isProcced = true}
                usableAddedHere[entry] = true
            end
        end
    end

    -- Second pass: add non-procced usable spells AND usable items
    local itemsEnabled = profile.enableItemFeatures
    for _, entry in ipairs(spellList) do
        if #usableResults >= maxCount then break end
        if entry and entry > 0 and not alreadyAdded[entry] and not usableAddedHere[entry] then
            -- Positive entry = spell
            local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(entry, profile)
            if isUsable then
                usableResults[#usableResults + 1] = {spellID = entry, isItem = false, isProcced = isProcced}
                usableAddedHere[entry] = true
            end
        elseif itemsEnabled and entry and entry < 0 and not alreadyAdded[entry] and not usableAddedHere[entry] then
            -- Negative entry = item (stored as -itemID)
            local itemID = -entry
            local isUsable = BlizzardAPI.CheckDefensiveItemState(itemID, profile)
            if isUsable then
                usableResults[#usableResults + 1] = {spellID = itemID, isItem = true, isProcced = false}
                usableAddedHere[entry] = true
                -- Also mark the positive itemID to prevent FindHealingPotionOnActionBar duplicates
                usableAddedHere[itemID] = true
            end
        end
    end

    return usableResults
end

-- Display order: instant procs first, then by health threshold (higher priority first)
function JustAC:GetDefensiveSpellQueue(passedIsLow, passedIsCritical, passedInCombat, passedExclusions, overrideDisplayMode, overrideMaxIcons, overrideShowProcs)
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return {} end

    local maxIcons = overrideMaxIcons or profile.defensives.maxIcons or 1
    local showProcs = (overrideShowProcs ~= nil) and overrideShowProcs or (profile.defensives.showProcs ~= false)
    local results = {}
    -- Reuse pooled table for tracking added spells
    wipe(defensiveAlreadyAdded)
    local alreadyAdded = defensiveAlreadyAdded

    if passedExclusions then
        for spellID, _ in pairs(passedExclusions) do
            alreadyAdded[spellID] = true
        end
    end

    local isLow, isCritical, inCombat
    if passedIsLow ~= nil then
        isLow = passedIsLow
        isCritical = passedIsCritical or false
        inCombat = passedInCombat or UnitAffectingCombat("player")
    else
        local healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
        inCombat = UnitAffectingCombat("player")
        if isEstimated then
            local lowState, critState = false, false
            if BlizzardAPI.GetLowHealthState then
                lowState, critState = BlizzardAPI.GetLowHealthState()
            end
            isLow = lowState
            isCritical = critState
        else
            local selfHealThreshold = profile.defensives.selfHealThreshold or 80
            local cooldownThreshold = profile.defensives.cooldownThreshold or 60
            isLow = healthPercent <= selfHealThreshold
            isCritical = healthPercent <= cooldownThreshold
        end
    end

    local displayMode = overrideDisplayMode or profile.defensives.displayMode
    if not displayMode then
        local showOnlyInCombat = profile.defensives.showOnlyInCombat
        local alwaysShow = profile.defensives.alwaysShowDefensive
        if alwaysShow and showOnlyInCombat then
            displayMode = "combatOnly"
        elseif alwaysShow then
            displayMode = "always"
        else
            displayMode = "healthBased"
        end
    end

    -- Procced spells shown at ANY health level
    if showProcs and ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
        local defensiveProcs = ActionBarScanner.GetDefensiveProccedSpells()
        if defensiveProcs then
            for _, spellID in ipairs(defensiveProcs) do
                if #results >= maxIcons then break end
                if spellID and spellID > 0 and not alreadyAdded[spellID] then
                    local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
                    if isUsable and isProcced then
                        results[#results + 1] = {spellID = spellID, isItem = false, isProcced = true}
                        alreadyAdded[spellID] = true
                    end
                end
            end
        end
    end

    -- Resolve per-class spell lists once for this update cycle
    local selfHealSpells = self:GetClassSpellList("selfHealSpells")
    local cooldownSpells = self:GetClassSpellList("cooldownSpells")

    if #results < maxIcons then
        local procs = self:GetUsableDefensiveSpells(selfHealSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(procs) do
            if entry.isProcced then
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
    end
    if #results < maxIcons then
        local procs = self:GetUsableDefensiveSpells(cooldownSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(procs) do
            if entry.isProcced then
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
    end

    if displayMode == "combatOnly" and not inCombat then
        return results
    end

    local showAllAvailable = (displayMode == "always") or (displayMode == "combatOnly" and inCombat)
    if showAllAvailable and not isLow and not isCritical and #results < maxIcons then
        local spells = self:GetUsableDefensiveSpells(selfHealSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(spells) do
            results[#results + 1] = entry
            alreadyAdded[entry.spellID] = true
        end
        if #results < maxIcons then
            local cooldowns = self:GetUsableDefensiveSpells(cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(cooldowns) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        return results
    end

    if isCritical then
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(selfHealSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        if #results < maxIcons and profile.enableItemFeatures and profile.defensives.autoInsertPotions ~= false then
            local potionID = self:FindHealingPotionOnActionBar()
            if potionID and not alreadyAdded[potionID] then
                results[#results + 1] = {spellID = potionID, isItem = true, isProcced = false}
                alreadyAdded[potionID] = true
            end
        end
    elseif isLow then
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(selfHealSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        if #results < maxIcons then
            local spells = self:GetUsableDefensiveSpells(cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(spells) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
    end
    
    return results
end

local HEALTHSTONE_ITEM_ID = 5512

-- Cached healing potion result (invalidated by OnActionBarChanged and leaving combat)
local cachedPotionID = nil
local cachedPotionSlot = nil
local potionCacheValid = false

local function InvalidatePotionCache()
    potionCacheValid = false
end

local function IsHealingConsumable(itemID)
    if not itemID then return false end
    if itemID == HEALTHSTONE_ITEM_ID then return true end

    local _, _, _, _, _, _, classID, subclassID = GetItemInfo(itemID)
    if not classID or classID ~= 0 or subclassID ~= 1 then
        return false
    end

    local spellName, spellID = GetItemSpell(itemID)
    if not spellName then return false end

    local lowerName = spellName:lower()
    if lowerName:find("heal") or lowerName:find("restore") or lowerName:find("life") then
        return true
    end

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

-- Returns itemID, actionSlot for first usable healing consumable (Healthstone prioritized)
-- Uses cached result from last action bar scan; call InvalidatePotionCache() on bar/bag changes
function JustAC:FindHealingPotionOnActionBar()
    if potionCacheValid then
        -- Still check cooldown/count on cached result (these change in combat)
        if cachedPotionID then
            local count = GetItemCount(cachedPotionID) or 0
            if count > 0 then
                local start, duration = GetItemCooldown(cachedPotionID)
                local onCooldown = false
                if start and duration then
                    local startIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(start)
                    local durIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(duration)
                    if not startIsSecret and not durIsSecret then
                        onCooldown = start > 0 and duration > 1.5
                    end
                end
                if not onCooldown then
                    return cachedPotionID, cachedPotionSlot
                end
            end
        end
        return nil, nil
    end

    -- Full 180-slot scan (expensive, only on cache miss)
    local bestPotion = nil
    local bestSlot = nil

    for slot = 1, 180 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then
            local count = GetItemCount(id) or 0
            if count > 0 then
                local start, duration = GetItemCooldown(id)
                -- Fail-open: if values are secret or nil, assume NOT on cooldown (show item)
                local onCooldown = false
                if start and duration then
                    local startIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(start)
                    local durIsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(duration)
                    if not startIsSecret and not durIsSecret then
                        onCooldown = start > 0 and duration > 1.5
                    end
                    -- If secret, onCooldown stays false (fail-open: show the item)
                end

                if not onCooldown then
                    if id == HEALTHSTONE_ITEM_ID then
                        cachedPotionID = id
                        cachedPotionSlot = slot
                        potionCacheValid = true
                        return id, slot
                    end

                    if not bestPotion and IsHealingConsumable(id) then
                        bestPotion = id
                        bestSlot = slot
                    end
                end
            end
        end
    end

    cachedPotionID = bestPotion
    cachedPotionSlot = bestSlot
    potionCacheValid = true
    return bestPotion, bestSlot
end

function JustAC:LoadModules()
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
end

function JustAC:SetHotkeyOverride(spellID, hotkeyText)
    if not spellID or spellID == 0 then return end
    local profile = self:GetProfile()
    if not profile then return end

    if not profile.hotkeyOverrides then
        profile.hotkeyOverrides = {}
    end

    if hotkeyText and hotkeyText:trim() ~= "" then
        profile.hotkeyOverrides[spellID] = hotkeyText:trim()
        local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:DebugPrint("Hotkey: " .. spellName .. " = '" .. hotkeyText:trim() .. "'")
    else
        profile.hotkeyOverrides[spellID] = nil
        local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:DebugPrint("Hotkey removed: " .. spellName)
    end

    if self.defensiveIcon and self.defensiveIcon:IsShown() and self.defensiveIcon.spellID == spellID then
        UIRenderer.ShowDefensiveIcon(self, spellID, false, self.defensiveIcon)
    end

    local Options = LibStub("JustAC-Options", true)
    if Options and Options.UpdateHotkeyOverrideOptions then
        Options.UpdateHotkeyOverrideOptions(self)
    end
    
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
function JustAC:IsSpellBlacklisted(spellID)
    if not SpellQueue or not SpellQueue.IsSpellBlacklisted then return false end
    return SpellQueue.IsSpellBlacklisted(spellID)
end
function JustAC:GetBlacklistedSpells() return SpellQueue and SpellQueue.GetBlacklistedSpells and SpellQueue.GetBlacklistedSpells() or {} end

-- Centralized cache invalidation with flags
function JustAC:InvalidateCaches(flags)
    flags = flags or {}
    
    if flags.spells or flags.all then
        if SpellQueue and SpellQueue.ClearSpellCache then SpellQueue.ClearSpellCache() end
        if SpellQueue and SpellQueue.ClearAvailabilityCache then SpellQueue.ClearAvailabilityCache() end
    end
    
    if flags.macros or flags.all then
        if MacroParser and MacroParser.InvalidateMacroCache then MacroParser.InvalidateMacroCache() end
    end
    
    if flags.hotkeys or flags.all then
        if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then ActionBarScanner.InvalidateHotkeyCache() end
        if UIRenderer and UIRenderer.InvalidateHotkeyCache then UIRenderer.InvalidateHotkeyCache() end
    end
    
    if flags.forms or flags.all then
        if FormCache and FormCache.InvalidateCache then FormCache.InvalidateCache() end
        if FormCache and FormCache.InvalidateSpellMapping then FormCache.InvalidateSpellMapping() end
    end
    
    if flags.auras or flags.all then
        if RedundancyFilter and RedundancyFilter.InvalidateCache then RedundancyFilter.InvalidateCache() end
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

    -- Always build queue to keep caches warm (redundancy filter, aura tracking, etc.)
    -- even when frame is hidden - this ensures instant response when frame becomes visible
    -- Renderer will skip expensive operations (hotkey lookups, icon updates) when hidden
    local currentSpells = SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue() or {}
    if UIRenderer and UIRenderer.RenderSpellQueue then
        UIRenderer.RenderSpellQueue(self, currentSpells)
    end
    if UINameplateOverlay then UINameplateOverlay.Render(self, currentSpells) end
end

function JustAC:UpdateDefensiveCooldowns()
    if self.isDisabledMode then return end
    if not self.db or not self.db.profile or self.db.profile.isManualMode then return end

    -- Update cooldowns on all visible main-panel defensive icons (requires defensives.enabled)
    local def = self.db.profile.defensives
    if def and def.enabled then
        if self.defensiveIcons and #self.defensiveIcons > 0 then
            for _, icon in ipairs(self.defensiveIcons) do
                if icon and icon:IsShown() then
                    UIRenderer.UpdateButtonCooldowns(icon)
                end
            end
        elseif self.defensiveIcon and self.defensiveIcon:IsShown() then
            UIRenderer.UpdateButtonCooldowns(self.defensiveIcon)
        end
    end

    -- Update cooldowns on nameplate overlay defensive icons.
    -- These are only rendered on UNIT_HEALTH events (which are suppressed in combat when
    -- health is a secret value), so their cooldowns would freeze without this explicit poll.
    if self.nameplateDefIcons and #self.nameplateDefIcons > 0 then
        for _, icon in ipairs(self.nameplateDefIcons) do
            if icon and icon:IsShown() then
                UIRenderer.UpdateButtonCooldowns(icon)
            end
        end
    end
end

function JustAC:PLAYER_ENTERING_WORLD()
    self:InitializeCaches()
    
    if FormCache and FormCache.OnPlayerLogin then
        FormCache.OnPlayerLogin()
    end
    
    -- Apply spec-based profile/disabled state on world entry (not just on spec change events)
    self:OnSpecChange()

    self:ForceUpdateAll()

    -- API may not return spells immediately after PLAYER_ENTERING_WORLD
    C_Timer.After(1.0, function() self:ForceUpdateAll() end)

    -- Single-Button Assistant required for stable API behavior
    -- Skip warning if the current spec is disabled (user doesn't need the button for specs they won't use)
    C_Timer.After(2, function()
        if self.isDisabledMode then return end
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
        if UIAnimations and UIAnimations.ResumeAllGlows then
            UIAnimations.ResumeAllGlows(self)
        end
        self:ForceUpdateAll()  -- Update both combat and defensive queues
    elseif event == "PLAYER_REGEN_ENABLED" then
        InvalidatePotionCache()
        if UIRenderer and UIRenderer.SetCombatState then
            UIRenderer.SetCombatState(false)
        end
        if UIAnimations and UIAnimations.PauseAllGlows then
            UIAnimations.PauseAllGlows(self)
        end
        self:InvalidateCaches({auras = true})
        if RedundancyFilter and RedundancyFilter.ClearActivationTracking then
            RedundancyFilter.ClearActivationTracking()
        end
        self:ForceUpdateAll()
    end
end

function JustAC:OnSpecChange()
    local newSpec = GetSpecialization()
    if not newSpec then return end

    self.db.char.lastKnownSpec = newSpec

    if self.db.char.specProfilesEnabled and self.db.char.specProfiles then
        local target = self.db.char.specProfiles[newSpec]

        if target == "DISABLED" then
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
    self:InvalidateCaches({spells = true, macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnSpellsChanged()
    if SpellQueue and SpellQueue.OnSpellsChanged then SpellQueue.OnSpellsChanged() end
    self:InvalidateCaches({spells = true, macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnSpellIconChanged()
    self:InvalidateCaches({hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormChanged()
    self:InvalidateCaches({macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormsRebuilt()
    self:InvalidateCaches({forms = true, macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnUnitAura(event, unit)
    if unit ~= "player" then return end

    local now = GetTime()
    if now - (self.lastAuraInvalidation or 0) > 0.5 then
        self.lastAuraInvalidation = now
        self:InvalidateCaches({auras = true})
    end
end

function JustAC:OnActionBarChanged()
    InvalidatePotionCache()
    self:InvalidateCaches({hotkeys = true, macros = true})
    self:ForceUpdate()
end

function JustAC:OnSpecialBarChanged()
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then ActionBarScanner.OnSpecialBarChanged() end
    self:ForceUpdate()
end

function JustAC:OnVehicleChanged(event, unit)
    if unit ~= "player" then return end

    self:InvalidateCaches({macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnBindingsUpdated()
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

    -- Mark both queues dirty - procs affect rotation and defensive priorities
    self:MarkQueueDirty()
    self:MarkDefensiveDirty()
    self:ForceUpdate()
    self:OnHealthChanged(nil, "player")
end

function JustAC:OnTargetChanged()
    self:MarkQueueDirty()
    self:UpdateTargetFrameAnchor()
    if UINameplateOverlay then UINameplateOverlay.UpdateAnchor(self) end
    -- ForceUpdateAll so the defensive overlay re-renders immediately on target switch
    -- rather than waiting for the next UNIT_HEALTH event (which may not fire in combat
    -- when health is a secret value).
    self:ForceUpdateAll()
end

function JustAC:OnNamePlateAdded(_, nameplateUnit)
    if UINameplateOverlay and UnitIsUnit(nameplateUnit, "target") then ---@diagnostic disable-line: undefined-global
        UINameplateOverlay.UpdateAnchor(self)
        -- ForceUpdateAll so the defensive overlay re-renders as soon as the plate appears.
        -- ForceUpdate (DPS-only) isn't enough — defensive icons are driven by OnHealthChanged.
        self:ForceUpdateAll()
    end
end

function JustAC:OnNamePlateRemoved(_, nameplateUnit)
    if UINameplateOverlay and UnitIsUnit(nameplateUnit, "target") then ---@diagnostic disable-line: undefined-global
        UINameplateOverlay.UpdateAnchor(self)
        -- clear icons immediately when the target plate disappears
        self:ForceUpdate()
    end
end

function JustAC:UpdateTargetFrameAnchor()
    if not self.mainFrame then return end
    -- Guard against taint: TargetFrame is secure; SetPoint against it in combat
    -- can spread taint to the action bar system causing "action blocked" errors
    if InCombatLockdown() then return end
    local profile = self:GetProfile()
    if not profile then return end

    local anchor = profile.targetFrameAnchor
    if not anchor or anchor == "DISABLED" then
        -- Restore to saved position if we were previously anchored
        if self.targetframe_anchored then
            self.targetframe_anchored = false
            self.mainFrame:ClearAllPoints()
            self.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
        end
        return
    end

    -- Anchor to Blizzard's default TargetFrame (even when hidden — it holds position)
    -- Offsets account for TargetFrame's 232x100 template size, HitRectInsets
    -- (top=4, bottom=9), and space for auras/castbar below the frame
    if TargetFrame then
        self.targetframe_anchored = true
        self.mainFrame:ClearAllPoints()
        if anchor == "TOP" then
            self.mainFrame:SetPoint("BOTTOM", TargetFrame, "TOP", 0, 2)
        elseif anchor == "BOTTOM" then
            self.mainFrame:SetPoint("TOP", TargetFrame, "BOTTOM", 0, -2)
        elseif anchor == "LEFT" then
            self.mainFrame:SetPoint("RIGHT", TargetFrame, "LEFT", -2, 0)
        elseif anchor == "RIGHT" then
            self.mainFrame:SetPoint("LEFT", TargetFrame, "RIGHT", 2, 0)
        end
    else
        -- TargetFrame not available (shouldn't happen) — fall back to saved position
        if self.targetframe_anchored then
            self.targetframe_anchored = false
        end
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint(profile.framePosition.point, profile.framePosition.x, profile.framePosition.y)
    end
end

function JustAC:OnPetChanged(event, unit)
    if unit ~= "player" then return end
    -- Pet summoned/dismissed/died — update pet health bar visibility and defensive queue
    if UIHealthBar and UIHealthBar.UpdatePetVisibility then
        UIHealthBar.UpdatePetVisibility(self)
    end
    self:OnHealthChanged(nil, "pet")
    self:ForceUpdate()
end

function JustAC:OnEquipmentChanged(event, slot, hasCurrent)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI and BlizzardAPI.RefreshItemSpellCache then
        BlizzardAPI.RefreshItemSpellCache()
    end
    self:ForceUpdate()
end

function JustAC:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    -- Cast completed - mark both queues dirty for immediate update
    self:MarkQueueDirty()
    self:MarkDefensiveDirty()

    if UnitAffectingCombat("player") and RedundancyFilter and RedundancyFilter.RecordSpellActivation then
        RedundancyFilter.RecordSpellActivation(spellID)
    end

    if self.castSuccessTimer then self:CancelTimer(self.castSuccessTimer) end
    self.castSuccessTimer = self:ScheduleTimer("ForceUpdate", 0.02)
end

-- Pooled table for key press flash matching (avoids GC pressure on every key press)
local iconsToFlash = {}

-- Monitor key presses to trigger flash on matching queue icons
function JustAC:CreateKeyPressDetector()
    if self.keyPressFrame then return end

    local frame = CreateFrame("Frame", "JustACKeyPressFrame", UIParent)
    frame:SetPropagateKeyboardInput(true)
    self.keyPressFrame = frame

    -- Cache function references at creation time (avoid table lookups in hot path)
    local StartFlash = UIAnimations and UIAnimations.StartFlash
    local IsShiftKeyDown = IsShiftKeyDown
    local IsControlKeyDown = IsControlKeyDown
    local IsAltKeyDown = IsAltKeyDown
    local wipe = wipe
    local GetTime = GetTime

    frame:SetScript("OnKeyDown", function(_, key)
        local addon = JustAC
        if not addon or not StartFlash then return end

        -- Skip pure modifier keys early
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end

        -- Build normalized key with modifiers (matches format in UIRenderer)
        local modKey = ""
        local shift = IsShiftKeyDown()
        local ctrl = IsControlKeyDown()
        local alt = IsAltKeyDown()

        if ctrl and shift then
            modKey = "CTRL-SHIFT-"
        elseif shift and alt then
            modKey = "SHIFT-ALT-"
        elseif ctrl and alt then
            modKey = "CTRL-ALT-"
        elseif shift then
            modKey = "SHIFT-"
        elseif ctrl then
            modKey = "CTRL-"
        elseif alt then
            modKey = "ALT-"
        end

        local normalizedKey = modKey .. key:upper()

        -- Reuse pooled table to avoid GC pressure
        wipe(iconsToFlash)
        local now = GetTime()
        local HOTKEY_GRACE_PERIOD = 0.15
        local slot1PrevSpellID = nil

        local profile = addon.db and addon.db.profile

        -- Check offensive icons (if flash enabled)
        local spellIcons = addon.spellIcons
        if spellIcons and (not profile or profile.showFlash ~= false) then
            -- Check slot 1 first (special handling for spell change timing)
            local icon1 = spellIcons[1]
            if icon1 and icon1:IsShown() and icon1.spellID then
                -- Grace period uses spellChangeTime (not hotkeyChangeTime) because
                -- the hotkey often stays the same when spell changes (same action bar slot)
                local inGracePeriod = icon1.spellChangeTime and (now - icon1.spellChangeTime) < HOTKEY_GRACE_PERIOD
                if icon1.previousSpellID and inGracePeriod then
                    slot1PrevSpellID = icon1.previousSpellID
                end

                -- Match: current hotkey, previous hotkey, OR any match during grace period
                local matched = icon1.normalizedHotkey == normalizedKey
                if not matched and inGracePeriod then
                    -- During grace period, also accept previous hotkey
                    -- (user pressed key for the spell that just got cast)
                    matched = icon1.previousNormalizedHotkey == normalizedKey
                end
                if matched then
                    iconsToFlash[#iconsToFlash + 1] = icon1
                end
            end

            -- Check remaining slots
            for i = 2, #spellIcons do
                local icon = spellIcons[i]
                if icon and icon:IsShown() and icon.spellID then
                    -- Inline match check
                    local matched = icon.normalizedHotkey == normalizedKey

                    -- Skip if same spell that was in slot 1 (just moved)
                    if matched and slot1PrevSpellID and icon.spellID == slot1PrevSpellID then
                        matched = false
                    end

                    if matched then
                        iconsToFlash[#iconsToFlash + 1] = icon
                    end
                end
            end
        end

        -- Check defensive icons (if flash enabled)
        local defFlash = not profile or not profile.defensives or profile.defensives.showFlash ~= false
        if defFlash then
            local defIcons = addon.defensiveIcons
            if defIcons then
                for _, defIcon in ipairs(defIcons) do
                    if defIcon and defIcon:IsShown() and defIcon.normalizedHotkey == normalizedKey then
                        iconsToFlash[#iconsToFlash + 1] = defIcon
                    end
                end
            end

            -- Legacy single defensive icon
            local defIcon = addon.defensiveIcon
            if defIcon and defIcon:IsShown() and defIcon.normalizedHotkey == normalizedKey then
                iconsToFlash[#iconsToFlash + 1] = defIcon
            end
        end

        -- Check nameplate DPS overlay icons (same flash logic as main queue)
        local npIcons = addon.nameplateIcons
        if npIcons and (not profile or profile.showFlash ~= false) then
            for _, npIcon in ipairs(npIcons) do
                if npIcon and npIcon:IsShown() and npIcon.normalizedHotkey == normalizedKey then
                    iconsToFlash[#iconsToFlash + 1] = npIcon
                end
            end
        end

        -- Check nameplate defensive overlay icons
        local npDefFlash = not profile or not profile.defensives or profile.defensives.showFlash ~= false
        if npDefFlash then
            local npDefIcons = addon.nameplateDefIcons
            if npDefIcons then
                for _, npDefIcon in ipairs(npDefIcons) do
                    if npDefIcon and npDefIcon:IsShown() and npDefIcon.normalizedHotkey == normalizedKey then
                        iconsToFlash[#iconsToFlash + 1] = npDefIcon
                    end
                end
            end
        end

        -- Flash all matched icons
        for _, icon in ipairs(iconsToFlash) do
            StartFlash(icon)
        end
    end)
end

function JustAC:OnCooldownUpdate()
    if self.cooldownTimer then self:CancelTimer(self.cooldownTimer); self.cooldownTimer = nil end
    self.cooldownTimer = self:ScheduleTimer("ForceUpdateAll", 0.1)
end

function JustAC:ForceUpdateAll()
    if self.cooldownTimer then self:CancelTimer(self.cooldownTimer); self.cooldownTimer = nil end
    if SpellQueue and SpellQueue.ForceUpdate then SpellQueue.ForceUpdate() end
    self:UpdateSpellQueue()
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
    local Options = LibStub("JustAC-Options", true)
    if Options then
        if self.InitializeDefensiveSpells then
            self:InitializeDefensiveSpells()
        end
        if Options.UpdateBlacklistOptions then Options.UpdateBlacklistOptions(self) end
        if Options.UpdateHotkeyOverrideOptions then Options.UpdateHotkeyOverrideOptions(self) end
        if Options.UpdateDefensivesOptions then Options.UpdateDefensivesOptions(self) end
    end

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI and BlizzardAPI.IsMidnightOrLater() then
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

-- Dirty flags for event-driven optimization
-- When set, next OnUpdate will process; cleared after processing
local spellQueueDirty = true
local defensiveQueueDirty = true
local lastFullUpdate = 0
local IDLE_CHECK_INTERVAL = 0.5  -- Check every 0.5s when idle (no recent events)

-- Cache expensive CVar lookup (rarely changes, no need to query every frame)
local cachedUpdateRate = nil
local lastCVarCheck = 0
local CVAR_CHECK_INTERVAL = 5.0  -- Only re-check CVar every 5 seconds

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

    -- Pre-cache references to avoid table lookups in hot path
    local UnitAffectingCombat = UnitAffectingCombat
    local GetTime = GetTime
    local GetCVar = GetCVar
    local math_max = math.max

    self.updateFrame:SetScript("OnUpdate", function(_, elapsed)
        local timeLeft = (self.updateTimeLeft or 0) - elapsed
        self.updateTimeLeft = timeLeft

        -- Fast path: skip all work if not time to update yet
        -- This is the most common case - exit as early as possible
        if timeLeft > 0 then
            return
        end

        -- Early exit: skip all work if UI is completely hidden (saves CPU when mounted, etc.)
        local mainFrame = self.mainFrame
        local mainHidden = not mainFrame or not mainFrame:IsShown()
        local defIcons = self.defensiveIcons
        local defHidden = not defIcons or #defIcons == 0
        local npHidden = not self.nameplateIcons or #self.nameplateIcons == 0
        if mainHidden and defHidden and not self.defensiveIcon and npHidden then
            self.updateTimeLeft = IDLE_CHECK_INTERVAL
            return
        end

        local inCombat = UnitAffectingCombat("player")

        -- Cache CVar lookup (expensive string operation + registry lookup)
        local now = GetTime()
        if not cachedUpdateRate or (now - lastCVarCheck) > CVAR_CHECK_INTERVAL then
            cachedUpdateRate = tonumber(GetCVar("assistedCombatIconUpdateRate")) or 0.05
            lastCVarCheck = now
        end

        local updateRate
        if inCombat then
            updateRate = math_max(cachedUpdateRate, 0.03)
        else
            -- Out of combat: use longer interval unless dirty
            if not spellQueueDirty and not defensiveQueueDirty then
                updateRate = IDLE_CHECK_INTERVAL
            else
                updateRate = math_max(cachedUpdateRate * 2.5, 0.15)
            end
        end

        self.updateTimeLeft = updateRate

        -- Always update spell queue (Blizzard doesn't provide events for rotation changes)
        -- But SpellQueue.GetCurrentSpellQueue has internal 0.1s throttle
        self:UpdateSpellQueue()
        spellQueueDirty = false

        -- Only update defensive cooldowns if dirty or periodic check
        if defensiveQueueDirty or (now - lastFullUpdate) > IDLE_CHECK_INTERVAL then
            self:UpdateDefensiveCooldowns()
            defensiveQueueDirty = false
            lastFullUpdate = now
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
    if UIFrameFactory and UIFrameFactory.UpdateFrameSize then UIFrameFactory.UpdateFrameSize(self) end
    if UIHealthBar and UIHealthBar.UpdateSize then UIHealthBar.UpdateSize(self) end
    if UIHealthBar and UIHealthBar.UpdatePetSize then UIHealthBar.UpdatePetSize(self) end
    self:ForceUpdate()
end

function JustAC:SavePosition()
    if UIFrameFactory and UIFrameFactory.SavePosition then UIFrameFactory.SavePosition(self) end
    self:ForceUpdate()
end