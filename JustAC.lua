-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIRenderer, UIFrameFactory, UIAnimations, UIHealthBar, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter, UINameplateOverlay, DefensiveEngine

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
        iconSize = 42,
        iconSpacing = 1,
        showOffensiveHotkeys = true, -- Show hotkey text on offensive queue icons
        gamepadIconStyle = "xbox",    -- Gamepad button icons: "generic", "xbox", "playstation"
        debugMode = false,
        isManualMode = false,
        tooltipMode = "always",       -- "never", "outOfCombat", or "always"
        glowMode = "all",                 -- "all", "primaryOnly", "procOnly", "none"
        showFlash = true,                 -- Flash icon on matching key press
        firstIconScale = 1.0,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueOutOfCombat = false,  -- Hide the entire queue when out of combat
        hideQueueForHealers = false,   -- Hide the entire queue when in a healer spec
        hideQueueWhenMounted = false,  -- Hide the queue while mounted
        displayMode = "queue",         -- "disabled" / "queue" / "overlay" / "both"
        requireHostileTarget = false,  -- Only show queue when targeting a hostile unit
        showHealthBar = false,         -- Standalone health bar (only shown when defensives disabled)
        hideItemAbilities = false,     -- Hide equipped item abilities (trinkets, tinkers)
        panelLocked = false,              -- Legacy (migrated to panelInteraction)
        panelInteraction = "unlocked",    -- "unlocked", "locked", "clickthrough"
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        targetFrameAnchor = "TOP",          -- Anchor to target frame: DISABLED, TOP, BOTTOM, LEFT, RIGHT
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals
        hotkeyOverrides = {},             -- Profile-level hotkey display overrides (included in profile copy)
        interruptMode = "important",      -- Interrupt reminder: "important" (lethal casts), "all", or "off"
        ccAllCasts = true,                -- CC non-important casts on non-boss mobs (saves true interrupt)
        -- Nameplate Overlay feature (independent queue cluster on target nameplate)
        nameplateOverlay = {
            maxIcons          = 3,       -- 1-5 DPS queue slots
            reverseAnchor     = false,   -- false = RIGHT (default), true = LEFT
            expansion         = "out",   -- "out" (horizontal), "up" (vertical up), "down" (vertical down)
            healthBarPosition = "outside", -- "outside" (far end of cluster) or "inside" (nameplate end); up/down only
            iconSize          = 32,
            iconSpacing       = 2,   -- px between successive icons in the cluster
            opacity           = 1.0, -- icon opacity (0.1–1.0)
            showGlow          = true,
            glowMode          = "all",
            showHotkey        = true,
            showFlash         = true, -- key-press flash feedback
            showDefensives       = true,
            maxDefensiveIcons    = 3,    -- 1-5
            defensiveDisplayMode = "always", -- "combatOnly", "always"
            showHealthBar        = true,
            interruptMode        = "important", -- "important", "all", or "off"
            ccAllCasts           = true,        -- CC non-important casts on non-boss mobs
        },
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            showProcs = true,         -- Show procced defensives (Victory Rush, free heals) at any health
            glowMode = "all",          -- "all", "primaryOnly", "procOnly", "none"
            showFlash = true,         -- Flash icon on matching key press
            showHotkeys = true,       -- Show hotkey text on defensive icons
            position = "SIDE1",       -- SIDE1 (health bar side), SIDE2, or LEADING (opposite grab tab)
            showHealthBar = true,    -- Display compact health bar above main queue
            showPetHealthBar = true, -- Display compact pet health bar (pet classes only)
            iconScale = 1.0,          -- Scale for defensive icons (same range as Primary Spell Scale)
            maxIcons = 4,             -- Number of defensive icons to show (1-7)
            -- NOTE: In 12.0 combat, UnitHealth() is secret. These thresholds only
            -- apply out of combat. In combat, we fall back to Blizzard's LowHealthFrame
            -- overlay which provides two binary states: "low" (~35%) and "critical" (~20%).
            selfHealThreshold = 80,   -- Out-of-combat only: show self-heals below this %
            cooldownThreshold = 60,   -- Out-of-combat only: show major cooldowns below this %
            petHealThreshold = 50,    -- Out-of-combat only: show pet heals below this pet %
            allowItems = true,        -- Allow manual item insertion in defensive spell lists
            autoInsertPotions = true,  -- Auto-insert health potions at critical health
            classSpells = {},         -- Per-class spell lists: classSpells["WARRIOR"] = {selfHealSpells={...}, cooldownSpells={...}, petHealSpells={}}
            displayMode = "always", -- "healthBased" (show when low), "combatOnly" (always in combat), "always"
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
        JustAC.CLASS_INTERRUPT_DEFAULTS = SpellDB.CLASS_INTERRUPT_DEFAULTS
    end
    
    self:NormalizeSavedData()

    self:LoadModules()
    self:InitializeDefensiveSpells()
    
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
            if SpellQueue then
                if SpellQueue.ClearAvailabilityCache then
                    SpellQueue.ClearAvailabilityCache()
                end
                if SpellQueue.InvalidateRotationCache then
                    SpellQueue.InvalidateRotationCache()
                end
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
    -- No trailing ForceUpdate needed — UpdateFrameSize already calls ForceUpdateAll
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

-- Defensive Engine wrapper methods (delegated to DefensiveEngine module)
function JustAC:OnHealthChanged(event, unit)
    if DefensiveEngine then DefensiveEngine.OnHealthChanged(self, event, unit) end
end
function JustAC:InitializeDefensiveSpells()
    if DefensiveEngine then DefensiveEngine.InitializeDefensiveSpells(self) end
end
function JustAC:RestoreDefensiveDefaults(listType)
    if DefensiveEngine then DefensiveEngine.RestoreDefensiveDefaults(self, listType) end
end
function JustAC:GetClassSpellList(listKey)
    if DefensiveEngine then return DefensiveEngine.GetClassSpellList(self, listKey) end
end

function JustAC:UpdateDefensiveCooldowns()
    if DefensiveEngine then DefensiveEngine.UpdateDefensiveCooldowns(self) end
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
    DefensiveEngine = LibStub("JustAC-DefensiveEngine", true)
    if not DefensiveEngine then self:Print("Warning: DefensiveEngine module not found") end
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

function JustAC:PLAYER_ENTERING_WORLD()
    self:InitializeCaches()

    if FormCache and FormCache.OnPlayerLogin then
        FormCache.OnPlayerLogin()
    end

    -- Apply spec-based profile/disabled state on world entry (not just on spec change events)
    self:OnSpecChange()

    -- Re-assert target frame anchor after loading screens (WoW can reset frame positions)
    self:UpdateTargetFrameAnchor()

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
        if DefensiveEngine then DefensiveEngine.InvalidatePotionCache() end
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
        -- Re-apply anchor in case it was changed during combat (InCombatLockdown blocked it)
        self:UpdateTargetFrameAnchor()
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
    if DefensiveEngine then DefensiveEngine.InvalidatePotionCache() end
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

    -- Guard: respect Edit Mode "Buffs on Top" setting.
    -- TOP anchor conflicts when buffs are above the target frame; BOTTOM conflicts when below.
    local buffsOnTop = TargetFrame and TargetFrame.buffsOnTop
    if (buffsOnTop == true and anchor == "TOP") or (buffsOnTop == false and anchor == "BOTTOM") then
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

        -- Check standard queue interrupt icon
        local intIcon = addon.interruptIcon
        if intIcon and intIcon:IsShown() and intIcon.normalizedHotkey == normalizedKey then
            iconsToFlash[#iconsToFlash + 1] = intIcon
        end

        -- Check nameplate DPS overlay icons (same flash logic as main queue)
        local npIcons = addon.nameplateIcons
        local npo = profile and profile.nameplateOverlay
        if npIcons and (not npo or npo.showFlash ~= false) then
            for _, npIcon in ipairs(npIcons) do
                if npIcon and npIcon:IsShown() and npIcon.normalizedHotkey == normalizedKey then
                    iconsToFlash[#iconsToFlash + 1] = npIcon
                end
            end
        end

        -- Check nameplate defensive overlay icons
        local npDefFlash = not npo or npo.showFlash ~= false
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
    -- Re-apply target frame anchor after resize (SetSize doesn't move the frame, but
    -- the anchor guard IsShown check may not have fired before the first render)
    self:UpdateTargetFrameAnchor()
    -- ForceUpdateAll (not ForceUpdate) so OnHealthChanged fires → ResizeToCount
    -- runs immediately, keeping health bar width in sync with visible defensive icons.
    self:ForceUpdateAll()
end

function JustAC:SavePosition()
    if UIFrameFactory and UIFrameFactory.SavePosition then UIFrameFactory.SavePosition(self) end
    self:ForceUpdate()
end