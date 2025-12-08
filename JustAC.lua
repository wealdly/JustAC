-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIManager, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter

-- Class-specific defensive spell defaults (spellIDs in priority order)
-- Two tiers: self-heals (weave into rotation) and major cooldowns (emergency)
-- Self-heals trigger at higher threshold, cooldowns at lower threshold
-- NOTE: Include options from multiple specs - IsSpellAvailable will filter to what player knows

-- Quick self-heals: fast/cheap abilities to maintain health during combat
local CLASS_SELFHEAL_DEFAULTS = {
    -- Death Knight: Death Strike is core, Death Pact is talent
    DEATHKNIGHT = {49998, 48743, 48707},             -- Death Strike, Death Pact, AMS (magic absorb)
    
    -- Demon Hunter: Havoc has no real heals, Veng has Soul Cleave
    -- Blur moved here as it's short CD and good mitigation
    DEMONHUNTER = {198589, 228477, 212084},          -- Blur, Soul Cleave (Veng), Fel Devastation (Veng)
    
    -- Druid: Renewal (talent), Frenzied Regen (Bear), Regrowth (all specs can cast)
    DRUID = {108238, 22842, 8936, 18562},            -- Renewal, Frenzied Regen, Regrowth, Swiftmend
    
    -- Evoker: Living Flame heals, Emerald Blossom, Verdant Embrace
    EVOKER = {361469, 355913, 360995},               -- Living Flame, Emerald Blossom, Verdant Embrace
    
    -- Hunter: Exhilaration is main heal, Mend Pet doesn't help player
    HUNTER = {109304, 264735},                       -- Exhilaration, Survival of the Fittest
    
    -- Mage: No real heals, only defensives. Ice Barrier, Blazing Barrier, Prismatic Barrier
    MAGE = {11426, 235313, 235450},                  -- Ice Barrier, Blazing Barrier, Prismatic Barrier
    
    -- Monk: Expel Harm is great, Vivify for MW, Chi Wave talent
    MONK = {322101, 116670, 115098},                 -- Expel Harm, Vivify, Chi Wave
    
    -- Paladin: Word of Glory (free with HP), Flash of Light, Lay on Hands (long CD but full heal)
    PALADIN = {85673, 19750, 633},                   -- Word of Glory, Flash of Light, Lay on Hands
    
    -- Priest: Desperate Prayer, PW:Shield, Shadow Mend/Flash Heal
    PRIEST = {19236, 17, 186263},                    -- Desperate Prayer, PW:Shield, Shadow Mend
    
    -- Rogue: Crimson Vial is the only real heal, Feint for mitigation
    ROGUE = {185311, 1966},                          -- Crimson Vial, Feint
    
    -- Shaman: Healing Surge works for all specs, Astral Shift is short-ish CD
    SHAMAN = {8004, 108271},                         -- Healing Surge, Astral Shift
    
    -- Warlock: Drain Life, Mortal Coil, Health Funnel (if has pet)
    WARLOCK = {234153, 6789, 755},                   -- Drain Life, Mortal Coil, Health Funnel
    
    -- Warrior: Victory Rush procs after kills, Impending Victory (talent), Ignore Pain
    WARRIOR = {34428, 202168, 190456},               -- Victory Rush, Impending Victory, Ignore Pain
}

-- Major cooldowns: big defensives for dangerous situations
local CLASS_COOLDOWN_DEFAULTS = {
    -- Death Knight: AMS for magic, IBF for physical, Vampiric Blood (Blood)
    DEATHKNIGHT = {48792, 49028, 55233},             -- IBF, Dancing Rune Weapon (Blood), Vampiric Blood (Blood)
    
    -- Demon Hunter: Netherwalk (talent), Metamorphosis (Havoc has leech), Darkness
    DEMONHUNTER = {196555, 187827, 196718},          -- Netherwalk, Metamorphosis, Darkness
    
    -- Druid: Barkskin (all), Survival Instincts (Feral/Guardian), Ironbark (Resto)
    DRUID = {22812, 61336, 102342},                  -- Barkskin, Survival Instincts, Ironbark
    
    -- Evoker: Obsidian Scales, Renewing Blaze, Zephyr (raid CD)
    EVOKER = {363916, 374348, 374227},               -- Obsidian Scales, Renewing Blaze, Zephyr
    
    -- Hunter: Turtle is immunity, Fortitude of the Bear (talent), Exhil in emergencies
    HUNTER = {186265, 388035},                       -- Aspect of the Turtle, Fortitude of the Bear
    
    -- Mage: Ice Block, Alter Time, Greater Invisibility, Mirror Image
    MAGE = {45438, 342245, 110959, 55342},           -- Ice Block, Alter Time, Greater Invis, Mirror Image
    
    -- Monk: Fortifying Brew, Dampen Harm, Diffuse Magic, Touch of Karma (WW)
    MONK = {115203, 122278, 122783, 122470},         -- Fort Brew, Dampen Harm, Diffuse Magic, Touch of Karma
    
    -- Paladin: Divine Shield, Divine Protection, Ardent Defender (Prot), Guardian (Prot)
    PALADIN = {642, 498, 31850, 86659},              -- Divine Shield, Divine Protection, Ardent Defender, Guardian
    
    -- Priest: Dispersion (Shadow), Fade, Desperate Prayer (moved from heals for emergency)
    PRIEST = {47585, 586, 213602},                   -- Dispersion, Fade, Greater Fade
    
    -- Rogue: Cloak of Shadows (magic), Evasion (physical), Vanish (drop aggro)
    ROGUE = {31224, 5277, 1856},                     -- Cloak of Shadows, Evasion, Vanish
    
    -- Shaman: Already used Astral Shift, add Earth Elemental, Spirit Link (Resto)
    SHAMAN = {198103, 108280, 204331},               -- Earth Elemental, Healing Tide, Counterstrike Totem
    
    -- Warlock: Unending Resolve, Dark Pact, Nether Ward (talent)
    WARLOCK = {104773, 108416, 212295},              -- Unending Resolve, Dark Pact, Nether Ward
    
    -- Warrior: Shield Wall (Prot), Die by the Sword (Arms/Fury), Rallying Cry, Spell Reflect
    WARRIOR = {871, 118038, 97462, 23920},           -- Shield Wall, Die by the Sword, Rallying Cry, Spell Reflect
}

-- Expose defaults for Options module
JustAC.CLASS_SELFHEAL_DEFAULTS = CLASS_SELFHEAL_DEFAULTS
JustAC.CLASS_COOLDOWN_DEFAULTS = CLASS_COOLDOWN_DEFAULTS

local defaults = {
    profile = {
        framePosition = {
            point = "CENTER",
            x = 0,
            y = -150,
        },
        maxIcons = 5,
        iconSize = 36,
        iconSpacing = 1,
        debugMode = false,
        isManualMode = false,
        blacklistedSpells = {},
        hotkeyOverrides = {},
        showTooltips = true,
        tooltipsInCombat = false,
        focusEmphasis = true,
        firstIconScale = 1.3,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueOutOfCombat = false,  -- Hide the entire queue when out of combat
        hideQueueForHealers = false,   -- Hide the entire queue when in a healer spec
        panelLocked = false,              -- Lock panel interactions in combat
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals (with stabilization)
        stabilizationWindow = 0.20,       -- Seconds to wait before changing position 1 (0-0.35)
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            position = "LEFT",        -- LEFT, ABOVE, or BELOW the primary spell
            selfHealThreshold = 80,   -- Show self-heals when health drops below this
            cooldownThreshold = 60,   -- Show major cooldowns when health drops below this
            selfHealSpells = {},      -- Populated from CLASS_SELFHEAL_DEFAULTS on first run
            cooldownSpells = {},      -- Populated from CLASS_COOLDOWN_DEFAULTS on first run
            showOnlyInCombat = true,  -- false = always visible, true = only in combat with thresholds
        },
    },
    char = {
        lastKnownSpec = nil,
        firstRun = true,
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
    local profile = self.db and self.db.profile
    if not profile then return end
    
    -- Normalize blacklistedSpells: string keys -> number, any truthy value -> true
    if profile.blacklistedSpells then
        local normalized = {}
        for key, value in pairs(profile.blacklistedSpells) do
            local spellID = tonumber(key)
            if spellID and spellID > 0 and value then
                normalized[spellID] = true  -- Simplified format
            end
        end
        profile.blacklistedSpells = normalized
    end
    
    -- Normalize hotkeyOverrides: string keys -> number
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
end

function JustAC:OnInitialize()
    -- AceDB handles per-character profiles automatically
    self.db = AceDB:New("JustACDB", defaults)
    
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
    
    if not _G.BINDING_NAME_JUSTAC_CAST_FIRST then
        _G.BINDING_NAME_JUSTAC_CAST_FIRST = "JustAC: Cast First Spell"
        _G.BINDING_HEADER_JUSTAC = "JustAssistedCombat"
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
            local modPrefix = ""
            if hasShift then modPrefix = "SHIFT-" end
            if hasCtrl then modPrefix = modPrefix .. "CTRL-" end
            if hasAlt then modPrefix = modPrefix .. "ALT-" end
            fullKey = modPrefix .. pressedKey
        else
            fullKey = pressedKey
        end
        
        -- Snapshot which icons to flash RIGHT NOW before the queue updates
        -- This ensures we flash where the ability WAS, not where it moves to
        local iconToFlash = nil  -- Only flash ONE icon (the first/primary match)
        local now = GetTime()
        local HOTKEY_GRACE_PERIOD = 0.15  -- Match previous hotkey for 150ms after change
        
        -- Check each visible icon's cached normalized hotkey
        -- Priority: find the FIRST (lowest index) matching icon - that's the one Blizzard activates
        local spellIcons = addon.spellIcons
        if spellIcons then
            for i = 1, #spellIcons do
                local icon = spellIcons[i]
                if icon and icon:IsShown() then
                    local cachedHotkey = icon.normalizedHotkey
                    local matched = cachedHotkey and (cachedHotkey == fullKey or cachedHotkey == pressedKey)
                    
                    -- Also check previous hotkey if it changed very recently
                    -- This handles the case where spell moved out of slot just before keypress registered
                    if not matched and icon.previousNormalizedHotkey and icon.hotkeyChangeTime then
                        if (now - icon.hotkeyChangeTime) < HOTKEY_GRACE_PERIOD then
                            local prevHotkey = icon.previousNormalizedHotkey
                            matched = prevHotkey == fullKey or prevHotkey == pressedKey
                        end
                    end
                    
                    if matched then
                        iconToFlash = icon
                        break  -- Stop at first match - that's the primary ability
                    end
                end
            end
        end
        
        -- Check defensive icon only if no spell icon matched
        if not iconToFlash then
            local defIcon = addon.defensiveIcon
            if defIcon and defIcon:IsShown() then
                local cachedHotkey = defIcon.normalizedHotkey
                local matched = cachedHotkey and (cachedHotkey == fullKey or cachedHotkey == pressedKey)
                
                if not matched and defIcon.previousNormalizedHotkey and defIcon.hotkeyChangeTime then
                    if (now - defIcon.hotkeyChangeTime) < HOTKEY_GRACE_PERIOD then
                        local prevHotkey = defIcon.previousNormalizedHotkey
                        matched = prevHotkey == fullKey or prevHotkey == pressedKey
                    end
                end
                
                if matched then
                    iconToFlash = defIcon
                end
            end
        end
        
        -- Flash the single matched icon
        if iconToFlash then
            StartFlash(iconToFlash)
        end
    end)
end

function JustAC:InitializeCaches()
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
    end
    
    -- Refresh defensive icon
    self:OnHealthChanged(nil, "player")
end

-- Called on UNIT_HEALTH event and ForceUpdateAll
-- Simplified logic:
--   "Only In Combat" ON:  Hide out of combat. In combat: threshold-based (self-heals at ≤80%, cooldowns at ≤60%)
--   "Only In Combat" OFF: Show out of combat (self-heals). In combat: threshold-based (same as above)

function JustAC:OnHealthChanged(event, unit)
    if unit ~= "player" then return end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives or not profile.defensives.enabled then 
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
        return 
    end
    
    local inCombat = UnitAffectingCombat("player")
    local showOnlyInCombat = profile.defensives.showOnlyInCombat
    
    -- If "Only In Combat" is enabled and we're out of combat, hide the icon
    if showOnlyInCombat and not inCombat then
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
        return
    end
    
    local healthPercent = BlizzardAPI and BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
    if not healthPercent then return end
    
    local cooldownThreshold = profile.defensives.cooldownThreshold or 60
    local selfHealThreshold = profile.defensives.selfHealThreshold or 80
    
    local defensiveSpell = nil
    local isItem = false
    
    -- Determine which spell to show based on health
    local isCritical = healthPercent <= cooldownThreshold
    local isLow = healthPercent <= selfHealThreshold
    
    -- Out of combat with "Only In Combat" OFF: always show self-heals (switch to cooldowns if critical)
    -- In combat (regardless of setting): threshold-based behavior
    if not inCombat and not showOnlyInCombat then
        -- Out of combat, always visible mode: show self-heals, cooldowns if critical
        if isCritical then
            defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.cooldownSpells)
            if not defensiveSpell then
                local potionID = self:FindHealingPotionOnActionBar()
                if potionID then
                    defensiveSpell = potionID
                    isItem = true
                end
            end
            if not defensiveSpell then
                defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.selfHealSpells)
            end
        else
            -- Always show self-heals out of combat
            defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.selfHealSpells)
        end
    else
        -- In combat: threshold-based visibility
        -- Critical health: cooldowns > potions > self-heals
        -- Low health: self-heals only
        -- Above threshold: hide
        if isCritical then
            defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.cooldownSpells)
            if not defensiveSpell then
                local potionID = self:FindHealingPotionOnActionBar()
                if potionID then
                    defensiveSpell = potionID
                    isItem = true
                end
            end
            if not defensiveSpell then
                defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.selfHealSpells)
            end
        elseif isLow then
            defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.selfHealSpells)
        end
        -- If health is above selfHealThreshold, defensiveSpell stays nil and icon hides
    end
    
    -- Show or hide the defensive icon
    if defensiveSpell then
        if UIManager and UIManager.ShowDefensiveIcon then
            UIManager.ShowDefensiveIcon(self, defensiveSpell, isItem)
        end
    else
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
    end
end

-- Get the first usable spell from a given spell list
-- Prioritizes procced spells (e.g., Victory Rush after kill, free heal procs)
-- Also scans spellbook for any procced defensive abilities not in the list
-- Filters: known, not on cooldown, not redundant (buff already active)

function JustAC:GetBestDefensiveSpell(spellList)
    if not spellList then return nil end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end
    
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
                        local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID)
                        if not isRedundant then
                            local start, duration = BlizzardAPI.GetSpellCooldown(spellID)
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
            -- Check if spell is known/available
            local isKnown = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
            
            if isKnown then
                -- Skip if buff already active (redundant)
                local isRedundant = RedundancyFilter and RedundancyFilter.IsSpellRedundant and RedundancyFilter.IsSpellRedundant(spellID)
                if not isRedundant then
                    -- Check if spell is off cooldown
                    local start, duration = BlizzardAPI.GetSpellCooldown(spellID)
                    local onCooldown = start and start > 0 and duration and duration > 1.5  -- Ignore GCD
                    
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
    SpellQueue = LibStub("JustAC-SpellQueue", true)
    ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    FormCache = LibStub("JustAC-FormCache", true)
    Options = LibStub("JustAC-Options", true)
    MacroParser = LibStub("JustAC-MacroParser", true)
    RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    
    if not UIManager then self:Print("Error: UIManager module not found"); UIManager = {} end
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
    local profile = self:GetProfile()
    if not profile then return end
    
    if not profile.hotkeyOverrides then
        profile.hotkeyOverrides = {}
    end
    
    if hotkeyText and hotkeyText:trim() ~= "" then
        profile.hotkeyOverrides[spellID] = hotkeyText:trim()
        local spellInfo = self:GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:DebugPrint("Hotkey: " .. spellName .. " = '" .. hotkeyText:trim() .. "'")
    else
        profile.hotkeyOverrides[spellID] = nil
        local spellInfo = self:GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:DebugPrint("Hotkey removed: " .. spellName)
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
    local profile = self:GetProfile()
    if not profile or not profile.hotkeyOverrides then return nil end
    return profile.hotkeyOverrides[spellID]
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
end

function JustAC:OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: animate glows
        if UIManager and UIManager.UnfreezeAllGlows then
            UIManager.UnfreezeAllGlows(self)
        end
        self:ForceUpdateAll()  -- Update both combat and defensive queues
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: freeze glows to reduce distraction
        if UIManager and UIManager.FreezeAllGlows then
            UIManager.FreezeAllGlows(self)
        end
        self:ForceUpdateAll()  -- Update both (hide defensive if showOnlyInCombat)
    end
end

function JustAC:OnSpecChange()
    if SpellQueue and SpellQueue.OnSpecChange then SpellQueue.OnSpecChange() end
    if SpellQueue and SpellQueue.ClearAvailabilityCache then SpellQueue.ClearAvailabilityCache() end
    if SpellQueue and SpellQueue.ClearSpellCache then SpellQueue.ClearSpellCache() end
    self.db.char.lastKnownSpec = GetSpecialization()
    self:ForceUpdate()
end

function JustAC:OnSpellsChanged()
    if SpellQueue and SpellQueue.OnSpellsChanged then SpellQueue.OnSpellsChanged() end
    if SpellQueue and SpellQueue.ClearAvailabilityCache then SpellQueue.ClearAvailabilityCache() end
    if ActionBarScanner and ActionBarScanner.InvalidateKeybindCache then ActionBarScanner.InvalidateKeybindCache() end
    self:ForceUpdate()
end

-- Spell icon/override changed (transformations like Pyroblast → Hot Streak)
-- This fires when spell appearances change due to buffs, procs, or talents
function JustAC:OnSpellIconChanged()
    -- Invalidate hotkey cache since spell→slot mappings may have changed
    if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
        ActionBarScanner.InvalidateHotkeyCache()
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
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then ActionBarScanner.OnKeybindsChanged() end
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
-- Procs often change spell overrides (e.g., Pyroblast → Hot Streak Pyroblast)
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
    
    -- Proc glows don't move spells - only affects availability, not slot mappings
    if SpellQueue and SpellQueue.ClearAvailabilityCache then
        SpellQueue.ClearAvailabilityCache()
    end
    self:ForceUpdate()
end

-- Target changes affect execute-range abilities and [exists] conditionals
function JustAC:OnTargetChanged()
    -- Macro conditionals may depend on target, refresh hotkey display
    if MacroParser and MacroParser.InvalidateMacroCache then
        MacroParser.InvalidateMacroCache()
    end
    self:ForceUpdate()
end

-- Pet summon/dismiss affects RedundancyFilter pet-related checks
function JustAC:OnPetChanged(event, unit)
    if unit ~= "player" then return end
    
    -- Pet state changed, invalidate redundancy cache
    if RedundancyFilter and RedundancyFilter.InvalidateCache then
        RedundancyFilter.InvalidateCache()
    end
    self:ForceUpdate()
end

-- Post-cast refresh: trigger update right after spell completion
-- More responsive than waiting for next OnUpdate tick
function JustAC:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    
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
    Settings.OpenToCategory("JustAssistedCombat")
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
    self:ForceUpdate()
end

function JustAC:SavePosition()
    if UIManager and UIManager.SavePosition then UIManager.SavePosition(self) end
    self:ForceUpdate()
end