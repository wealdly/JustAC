-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIManager, UIRenderer, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter

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
        focusEmphasis = true,
        firstIconScale = 1.2,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueOutOfCombat = false,  -- Hide the entire queue when out of combat
        hideQueueForHealers = false,   -- Hide the entire queue when in a healer spec
        hideQueueWhenMounted = false,  -- Hide the queue while mounted
        requireHostileTarget = false,  -- Only show queue when targeting a hostile unit
        hideItemAbilities = false,     -- Hide equipped item abilities (trinkets, tinkers)
        panelLocked = false,              -- Lock panel interactions in combat
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            showProcs = true,         -- Show procced defensives (Victory Rush, free heals) at any health
            showHotkeys = true,       -- Show hotkey text on defensive icons
            position = "SIDE1",       -- SIDE1 (health bar side), SIDE2, or LEADING (opposite grab tab)
            showHealthBar = true,     -- Display compact health bar above main queue
            iconScale = 1.2,          -- Scale for defensive icons (same range as Primary Spell Scale)
            maxIcons = 3,             -- Number of defensive icons to show (1-3)
            selfHealThreshold = 80,   -- Show self-heals when health drops below this
            cooldownThreshold = 60,   -- Show major cooldowns when health drops below this
            petHealThreshold = 50,    -- Show pet heals when PET health drops below this
            selfHealSpells = {},      -- Populated from CLASS_SELFHEAL_DEFAULTS on first run
            cooldownSpells = {},      -- Populated from CLASS_COOLDOWN_DEFAULTS on first run
            petHealSpells = {},       -- Populated from CLASS_PETHEAL_DEFAULTS on first run
            displayMode = "combatOnly", -- "healthBased" (show when low), "combatOnly" (always in combat), "always"
        },
        hotkeyText = {
            font = "Friz Quadrata TT",   -- LibSharedMedia font name
            size = 12,                    -- Font size
            color = { r = 1, g = 1, b = 1, a = 1 },  -- White by default
            anchor = "TOPRIGHT",          -- Text anchoring relative to icon
            anchorPoint = "TOPRIGHT",     -- Text anchor point
            firstXOffset = -3,            -- First icon X offset
            firstYOffset = -3,            -- First icon Y offset
            queueXOffset = -2,            -- Queue icons X offset
            queueYOffset = -2,            -- Queue icons Y offset
        },
    },
    char = {
        lastKnownSpec = nil,
        firstRun = true,
        blacklistedSpells = {},   -- Character-specific spell blacklist
        hotkeyOverrides = {},     -- Character-specific hotkey overrides
        specProfilesEnabled = true,   -- Auto-switch profiles by spec (enabled by default)
        specProfiles = {},        -- [specIndex] = "profileName" | "DISABLED" | nil
    },
    global = {
        version = "2.6",
    },
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
    if not UIManager or not UIManager.CreateMainFrame then
        self:Print("Error: UIManager module not loaded properly")
        return
    end
    
    UIManager.CreateMainFrame(self)
    if not self.mainFrame then
        self:Print("Error: Failed to create main frame")
        return
    end

    UIManager.CreateSpellIcons(self)

    -- Must be after CreateSpellIcons
    if UIManager.CreateHealthBar then
        UIManager.CreateHealthBar(self)
    end

    if UnitAffectingCombat("player") then
        if UIManager.UnfreezeAllGlows then UIManager.UnfreezeAllGlows(self) end
    else
        if UIManager.FreezeAllGlows then UIManager.FreezeAllGlows(self) end
    end
    
    self:InitializeCaches()
    self:StartUpdates()

    -- Create key press detector for flash feedback
    self:CreateKeyPressDetector()

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
    
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    
    if RedundancyFilter and RedundancyFilter.InvalidateCache then
        RedundancyFilter.InvalidateCache()
    end

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

    self:DebugPrint("Entered disabled mode for current spec")
end

function JustAC:ExitDisabledMode()
    if not self.isDisabledMode then return end
    self.isDisabledMode = false

    self:StartUpdates()

    if self.mainFrame then
        self.mainFrame:Show()
    end

    self:ForceUpdateAll()
    self:DebugPrint("Exited disabled mode")
end

function JustAC:RefreshConfig()
    -- Blacklist/hotkey overrides are character-specific, persist across profile changes
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

-- Only on explicit profile reset (not change/copy)
function JustAC:OnProfileReset()
    if self.db and self.db.char then
        self.db.char.blacklistedSpells = {}
        self.db.char.hotkeyOverrides = {}
    end

    -- Then do standard config refresh
    self:RefreshConfig()
end

function JustAC:ShowWelcomeMessage()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then return end
    
    local assistedMode = GetCVarBool("assistedMode") or false
    if assistedMode then
        self:Print("Assisted Combat mode active")
    else
        self:Print("Tip: Enable /console assistedMode 1")
    end
end

function JustAC:InitializeDefensiveSpells()
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end
    
    local _, playerClass = UnitClass("player")
    if not playerClass then return end
    
    if not profile.defensives.selfHealSpells or #profile.defensives.selfHealSpells == 0 then
        local healDefaults = JustAC.CLASS_SELFHEAL_DEFAULTS and JustAC.CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            profile.defensives.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                profile.defensives.selfHealSpells[i] = spellID
            end
        end
    end

    if not profile.defensives.cooldownSpells or #profile.defensives.cooldownSpells == 0 then
        local cdDefaults = JustAC.CLASS_COOLDOWN_DEFAULTS and JustAC.CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            profile.defensives.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                profile.defensives.cooldownSpells[i] = spellID
            end
        end
    end

    if not profile.defensives.petHealSpells or #profile.defensives.petHealSpells == 0 then
        local petDefaults = JustAC.CLASS_PETHEAL_DEFAULTS and JustAC.CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            profile.defensives.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                profile.defensives.petHealSpells[i] = spellID
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

    if profile.defensives.selfHealSpells then
        for _, spellID in ipairs(profile.defensives.selfHealSpells) do
            BlizzardAPI.RegisterDefensiveSpell(spellID)
        end
    end

    if profile.defensives.cooldownSpells then
        for _, spellID in ipairs(profile.defensives.cooldownSpells) do
            BlizzardAPI.RegisterDefensiveSpell(spellID)
        end
    end

    if profile.defensives.petHealSpells then
        for _, spellID in ipairs(profile.defensives.petHealSpells) do
            BlizzardAPI.RegisterDefensiveSpell(spellID)
        end
    end
end

function JustAC:RestoreDefensiveDefaults(listType)
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return end
    
    local _, playerClass = UnitClass("player")
    if not playerClass then return end
    
    if listType == "selfheal" then
        local healDefaults = JustAC.CLASS_SELFHEAL_DEFAULTS and JustAC.CLASS_SELFHEAL_DEFAULTS[playerClass]
        if healDefaults then
            profile.defensives.selfHealSpells = {}
            for i, spellID in ipairs(healDefaults) do
                profile.defensives.selfHealSpells[i] = spellID
            end
        end
    elseif listType == "cooldown" then
        local cdDefaults = JustAC.CLASS_COOLDOWN_DEFAULTS and JustAC.CLASS_COOLDOWN_DEFAULTS[playerClass]
        if cdDefaults then
            profile.defensives.cooldownSpells = {}
            for i, spellID in ipairs(cdDefaults) do
                profile.defensives.cooldownSpells[i] = spellID
            end
        end
    elseif listType == "petheal" then
        local petDefaults = JustAC.CLASS_PETHEAL_DEFAULTS and JustAC.CLASS_PETHEAL_DEFAULTS[playerClass]
        if petDefaults then
            profile.defensives.petHealSpells = {}
            for i, spellID in ipairs(petDefaults) do
                profile.defensives.petHealSpells[i] = spellID
            end
        end
    end

    self:RegisterDefensivesForTracking()
    self:OnHealthChanged(nil, "player")
end

-- Throttle for UNIT_HEALTH events (fires very frequently in combat)
local lastHealthUpdate = 0
local HEALTH_UPDATE_THROTTLE = 0.1  -- 100ms minimum between defensive queue updates
-- Pooled table to avoid GC pressure in OnHealthChanged
local dpsQueueExclusions = {}

function JustAC:OnHealthChanged(event, unit)
    if unit ~= "player" and unit ~= "pet" then return end

    -- Health bar update is cheap, always do it for visual feedback
    if UIManager and UIManager.UpdateHealthBar then
        UIManager.UpdateHealthBar(self)
    end

    -- Throttle defensive queue updates (expensive operation with table allocations)
    local now = GetTime()
    if event and now - lastHealthUpdate < HEALTH_UPDATE_THROTTLE then
        return
    end
    lastHealthUpdate = now

    local profile = self:GetProfile()
    if not profile or not profile.defensives or not profile.defensives.enabled then 
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
        return
    end

    local inCombat = UnitAffectingCombat("player")

    -- Falls back to LowHealthFrame when UnitHealth() returns secrets
    local healthPercent, isEstimated = nil, false
    if BlizzardAPI and BlizzardAPI.GetPlayerHealthPercentSafe then
        healthPercent, isEstimated = BlizzardAPI.GetPlayerHealthPercentSafe()
    end

    local selfHealThreshold = profile.defensives.selfHealThreshold or 80
    local cooldownThreshold = profile.defensives.cooldownThreshold or 60

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

    local petHealthPercent = BlizzardAPI and BlizzardAPI.GetPetHealthPercent and BlizzardAPI.GetPetHealthPercent()
    local petHealThreshold = profile.defensives.petHealThreshold or 70
    local petNeedsHeal = petHealthPercent and petHealthPercent <= petHealThreshold

    -- Exclude spells already visible in DPS queue (reuse pooled table)
    wipe(dpsQueueExclusions)
    if SpellQueue and SpellQueue.GetCurrentSpellQueue then
        local dpsQueue = SpellQueue.GetCurrentSpellQueue()
        local maxDpsIcons = profile.maxIcons or 4
        for i = 1, math.min(#dpsQueue, maxDpsIcons) do
            if dpsQueue[i] then
                dpsQueueExclusions[dpsQueue[i]] = true
            end
        end
    end
    local defensiveQueue = self:GetDefensiveSpellQueue(isLow, isCritical, inCombat, dpsQueueExclusions)

    local maxIcons = profile.defensives.maxIcons or 1
    if petNeedsHeal and #defensiveQueue < maxIcons then
        local petHeals = self:GetUsableDefensiveSpells(profile.defensives.petHealSpells, maxIcons - #defensiveQueue, {})
        for _, entry in ipairs(petHeals) do
            defensiveQueue[#defensiveQueue + 1] = entry
        end
    end

    if #defensiveQueue > 0 then
        if self.defensiveIcons and #self.defensiveIcons > 0 and UIManager and UIManager.ShowDefensiveIcons then
            UIManager.ShowDefensiveIcons(self, defensiveQueue)
        elseif self.defensiveIcon and UIManager and UIManager.ShowDefensiveIcon then
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

    local spellLists = {
        profile.defensives.selfHealSpells,
        profile.defensives.cooldownSpells,
    }
    for _, spellList in ipairs(spellLists) do
        if spellList then
            for _, spellID in ipairs(spellList) do
                if spellID and spellID > 0 then
                    local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
                    if isUsable and isProcced then
                        return spellID
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

    for i, spellID in ipairs(spellList) do
        if spellID and spellID > 0 then
            local isUsable, isKnown, isRedundant, onCooldown, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
            
            if debugMode then
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                self:DebugPrint(string.format("Checking defensive spell %d/%d: %s (%d)", i, #spellList, name, spellID))
                
                if not isKnown then
                    self:DebugPrint(string.format("  SKIP: %s - not known/available", name))
                elseif isRedundant then
                    self:DebugPrint(string.format("  SKIP: %s - redundant (buff active)", name))
                elseif onCooldown then
                    local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)
                    self:DebugPrint(string.format("  SKIP: %s - on cooldown (start=%s, duration=%s)", 
                        name, tostring(start or 0), tostring(duration or 0)))
                else
                    local start, duration = BlizzardAPI.GetSpellCooldownValues(spellID)
                    self:DebugPrint(string.format("  PASS: %s - onCooldown=false, start=%s, duration=%s", 
                        name, tostring(start or 0), tostring(duration or 0)))
                end
            end

            if isUsable then
                return spellID
            end
        end
    end

    return nil
end

-- Returns up to maxCount usable spells, prioritizing procs
function JustAC:GetUsableDefensiveSpells(spellList, maxCount, alreadyAdded)
    if not spellList or maxCount <= 0 then return {} end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return {} end

    local results = {}
    alreadyAdded = alreadyAdded or {}
    local addedHere = {}

    -- First pass: add procced spells (higher priority)
    for _, spellID in ipairs(spellList) do
        if #results >= maxCount then break end
        if spellID and spellID > 0 and not alreadyAdded[spellID] and not addedHere[spellID] then
            local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
            if isUsable and isProcced then
                results[#results + 1] = {spellID = spellID, isItem = false, isProcced = true}
                addedHere[spellID] = true
            end
        end
    end

    -- Second pass: add non-procced usable spells
    for _, spellID in ipairs(spellList) do
        if #results >= maxCount then break end
        if spellID and spellID > 0 and not alreadyAdded[spellID] and not addedHere[spellID] then
            local isUsable, _, _, _, isProcced = BlizzardAPI.CheckDefensiveSpellState(spellID, profile)
            if isUsable then
                results[#results + 1] = {spellID = spellID, isItem = false, isProcced = isProcced}
                addedHere[spellID] = true
            end
        end
    end
    
    return results
end

-- Pooled table for GetDefensiveSpellQueue (alreadyAdded is internal, results must be new since it's returned)
local defensiveAlreadyAdded = {}

-- Display order: instant procs first, then by health threshold (higher priority first)
function JustAC:GetDefensiveSpellQueue(passedIsLow, passedIsCritical, passedInCombat, passedExclusions)
    local profile = self:GetProfile()
    if not profile or not profile.defensives or not profile.defensives.enabled then return {} end

    local maxIcons = profile.defensives.maxIcons or 1
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

    local displayMode = profile.defensives.displayMode
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
    if profile.defensives.showProcs ~= false and ActionBarScanner and ActionBarScanner.GetDefensiveProccedSpells then
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

    if displayMode == "combatOnly" and not inCombat then
        return results
    end

    local showAllAvailable = (displayMode == "always") or (displayMode == "combatOnly" and inCombat)
    if showAllAvailable and not isLow and not isCritical and #results < maxIcons then
        local spells = self:GetUsableDefensiveSpells(profile.defensives.selfHealSpells, maxIcons - #results, alreadyAdded)
        for _, entry in ipairs(spells) do
            results[#results + 1] = entry
            alreadyAdded[entry.spellID] = true
        end
        if #results < maxIcons then
            local cooldowns = self:GetUsableDefensiveSpells(profile.defensives.cooldownSpells, maxIcons - #results, alreadyAdded)
            for _, entry in ipairs(cooldowns) do
                results[#results + 1] = entry
                alreadyAdded[entry.spellID] = true
            end
        end
        return results
    end

    if isCritical then
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
        if #results < maxIcons then
            local potionID = self:FindHealingPotionOnActionBar()
            if potionID and not alreadyAdded[potionID] then
                results[#results + 1] = {spellID = potionID, isItem = true, isProcced = false}
                alreadyAdded[potionID] = true
            end
        end
    elseif isLow then
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

local HEALTHSTONE_ITEM_ID = 5512

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
function JustAC:FindHealingPotionOnActionBar()
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

    if self.defensiveIcon and self.defensiveIcon:IsShown() and self.defensiveIcon.spellID == spellID then
        UIManager.ShowDefensiveIcon(self, spellID, false)
    end

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
    if self.isDisabledMode then return end
    if not self.db or not self.db.profile or self.db.profile.isManualMode or not self.mainFrame or not SpellQueue or not UIManager then return end

    -- Always build queue to keep caches warm (redundancy filter, aura tracking, etc.)
    -- even when frame is hidden - this ensures instant response when frame becomes visible
    -- Renderer will skip expensive operations (hotkey lookups, icon updates) when hidden
    local currentSpells = SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue() or {}
    UIManager.RenderSpellQueue(self, currentSpells)
end

function JustAC:UpdateDefensiveCooldowns()
    if self.isDisabledMode then return end
    if not self.db or not self.db.profile or self.db.profile.isManualMode then return end
    
    -- Update cooldowns on all visible defensive icons
    -- This ensures cooldown layers appear/disappear as quickly as the main queue
    if self.defensiveIcons and #self.defensiveIcons > 0 then
        for _, icon in ipairs(self.defensiveIcons) do
            if icon and icon:IsShown() then
                UIRenderer.UpdateButtonCooldowns(icon)
            end
        end
    elseif self.defensiveIcon and self.defensiveIcon:IsShown() then
        -- Legacy single defensive icon support
        UIRenderer.UpdateButtonCooldowns(self.defensiveIcon)
    end
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

    self:ForceUpdateAll()

    -- API may not return spells immediately after PLAYER_ENTERING_WORLD
    C_Timer.After(1.0, function() self:ForceUpdateAll() end)

    -- Single-Button Assistant required for stable API behavior
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
        if UIRenderer and UIRenderer.SetCombatState then
            UIRenderer.SetCombatState(false)
        end
        if UIManager and UIManager.FreezeAllGlows then
            UIManager.FreezeAllGlows(self)
        end
        local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
        if RedundancyFilter and RedundancyFilter.InvalidateCache then
            RedundancyFilter.InvalidateCache()
        end
        if RedundancyFilter and RedundancyFilter.ClearActivationTracking then
            RedundancyFilter.ClearActivationTracking()
        end
        self:ForceUpdateAll()
    end
end

function JustAC:OnSpecChange()
    local newSpec = GetSpecialization()
    if not newSpec then return end

    if self.db.char.specProfilesEnabled and self.db.char.specProfiles then
        local target = self.db.char.specProfiles[newSpec]

        if target == "DISABLED" then
            -- Enter minimal mode for this spec
            self:EnterDisabledMode()
            self.db.char.lastKnownSpec = newSpec
            return
        end

        if self.isDisabledMode then
            self:ExitDisabledMode()
        end

        if target and target ~= "" and target ~= self.db:GetCurrentProfile() then
            local ok = pcall(function() self.db:SetProfile(target) end)
            if ok then
                self.db.char.lastKnownSpec = newSpec
                return
            end
        end
    elseif self.isDisabledMode then
        self:ExitDisabledMode()
    end

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

    self.db.char.lastKnownSpec = newSpec
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

function JustAC:OnSpellIconChanged()
    if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
        ActionBarScanner.InvalidateHotkeyCache()
    end
    if UIManager and UIManager.InvalidateHotkeyCache then
        UIManager.InvalidateHotkeyCache()
    end
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormChanged()
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

-- This is expensive, avoid calling unless necessary
function JustAC:OnHotkeyProfileUpdate()
    if UIManager and UIManager.CreateSpellIcons then
        UIManager.CreateSpellIcons(self)
    end
    self:ForceUpdate()    
end

function JustAC:OnSpecialBarChanged()
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then ActionBarScanner.OnSpecialBarChanged() end
    self:ForceUpdate()
end

function JustAC:OnVehicleChanged(event, unit)
    if unit ~= "player" then return end

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
    self:ForceUpdate()
end

function JustAC:OnPetChanged(event, unit)
    if unit ~= "player" then return end
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
    local StartFlash = UIManager and UIManager.StartFlash
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

        local spellIcons = addon.spellIcons
        if spellIcons then
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

        -- Check defensive icons (inline match)
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
        if mainHidden and defHidden and not self.defensiveIcon then
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
    if UIManager and UIManager.UpdateFrameSize then UIManager.UpdateFrameSize(self) end
    if UIManager and UIManager.UpdateHealthBarSize then UIManager.UpdateHealthBarSize(self) end
    self:ForceUpdate()
end

function JustAC:SavePosition()
    if UIManager and UIManager.SavePosition then UIManager.SavePosition(self) end
    self:ForceUpdate()
end