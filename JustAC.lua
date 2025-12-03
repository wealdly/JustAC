-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIManager, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter

-- Class-specific defensive spell defaults (spellIDs in priority order)
-- Two tiers: self-heals (weave into rotation) and major cooldowns (emergency)
-- Self-heals trigger at higher threshold, cooldowns at lower threshold

-- Quick self-heals: fast/cheap abilities to maintain health during combat
local CLASS_SELFHEAL_DEFAULTS = {
    DEATHKNIGHT = {49998, 48743},                    -- Death Strike, Death Pact
    DEMONHUNTER = {228477, 203551},                  -- Soul Cleave (Veng), Chaos Strike (heal proc)
    DRUID = {108238, 18562, 8936},                   -- Renewal, Swiftmend, Regrowth
    EVOKER = {361469, 355913},                       -- Living Flame, Emerald Blossom
    HUNTER = {109304, 264735},                       -- Exhilaration, Survival of the Fittest
    MAGE = {55342},                                  -- Mirror Image (damage reduction)
    MONK = {115072, 322101, 116670},                 -- Expel Harm, Expel Harm, Vivify
    PALADIN = {633, 19750, 85673},                   -- Lay on Hands, Flash of Light, Word of Glory
    PRIEST = {19236, 17},                            -- Desperate Prayer, Power Word: Shield
    ROGUE = {185311, 1966},                          -- Crimson Vial, Feint
    SHAMAN = {8004, 188070},                         -- Healing Surge, Healing Rain
    WARLOCK = {234153, 6789, 104773},                -- Drain Life, Mortal Coil, Unending Resolve
    WARRIOR = {34428, 202168},                       -- Victory Rush, Impending Victory
}

-- Major cooldowns: big defensives for dangerous situations
local CLASS_COOLDOWN_DEFAULTS = {
    DEATHKNIGHT = {48707, 48792, 49028, 55233},      -- AMS, IBF, Dancing Rune Weapon, Vampiric Blood
    DEMONHUNTER = {198589, 187827, 196555},          -- Blur, Metamorphosis, Netherwalk
    DRUID = {22812, 61336, 102342},                  -- Barkskin, Survival Instincts, Ironbark
    EVOKER = {363916, 374348, 370960},               -- Obsidian Scales, Renewing Blaze, Emerald Communion
    HUNTER = {186265, 264735},                       -- Aspect of the Turtle, Survival of the Fittest
    MAGE = {45438, 110909, 342245},                  -- Ice Block, Alter Time, Alter Time
    MONK = {122278, 122783, 115203},                 -- Dampen Harm, Diffuse Magic, Fortifying Brew
    PALADIN = {642, 498, 31850, 86659},              -- Divine Shield, Divine Protection, Ardent Defender, Guardian
    PRIEST = {47585, 586, 33206},                    -- Dispersion, Fade, Pain Suppression
    ROGUE = {1856, 31224, 5277},                     -- Vanish, Cloak of Shadows, Evasion
    SHAMAN = {108271, 204331, 198103},               -- Astral Shift, Counterstrike Totem, Earth Elemental
    WARLOCK = {104773, 108416, 212295},              -- Unending Resolve, Dark Pact, Nether Ward
    WARRIOR = {871, 12975, 118038, 23920},           -- Shield Wall, Last Stand, Die by the Sword, Spell Reflection
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
        iconSpacing = 2,
        debugMode = false,
        isManualMode = false,
        blacklistedSpells = {},
        hotkeyOverrides = {},
        greyoutNoHotkey = true,
        showTooltips = true,
        tooltipsInCombat = false,
        focusEmphasis = true,
        firstIconScale = 1.4,
        glowAlpha = 0.75,
        glowColorR = 0.3,
        glowColorG = 0.7,
        glowColorB = 1.0,
        queueIconDesaturation = 0.35,
        autoEnableAssistedMode = true,
        -- Defensives feature (two tiers: self-heals and major cooldowns)
        defensives = {
            enabled = true,
            selfHealThreshold = 70,   -- Show self-heals when health drops below this
            cooldownThreshold = 50,   -- Show major cooldowns when health drops below this
            selfHealSpells = {},      -- Populated from CLASS_SELFHEAL_DEFAULTS on first run
            cooldownSpells = {},      -- Populated from CLASS_COOLDOWN_DEFAULTS on first run
            glowColorR = 0.0,
            glowColorG = 1.0,
            glowColorB = 0.0,
            showOnlyUsable = true,
            showOnlyInCombat = true,
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

function JustAC:OnInitialize()
    -- AceDB handles per-character profiles automatically
    self.db = AceDB:New("JustACDB", defaults)
    
    -- Initialize class-specific defensive spells on first run
    self:InitializeDefensiveSpells()
    
    self:LoadModules()
    
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    
    if Options and Options.Initialize then
        Options.Initialize(self)
    end
    
    self:Print("JustAssistedCombat v" .. (self.db.global.version or "2.5") .. " initialized.")
end

function JustAC:OnEnable()
    self:SetupAssistedCombatCVars()
    
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
    
    -- Target changes affect execute-range abilities and macro conditionals
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    
    -- Pet state for RedundancyFilter pet-related checks
    self:RegisterEvent("UNIT_PET", "OnPetChanged")
    
    -- Cast completion for immediate post-cast refresh (faster than OnUpdate tick)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    
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
    end
    
    if not _G.BINDING_NAME_JUSTAC_CAST_FIRST then
        _G.BINDING_NAME_JUSTAC_CAST_FIRST = "JustAC: Cast First Spell"
        _G.BINDING_HEADER_JUSTAC = "JustAssistedCombat"
    end
    
    if self.db.char.firstRun then
        self:ScheduleTimer("ShowWelcomeMessage", 3)
        self.db.char.firstRun = false
    end
    
    self:ScheduleTimer("DelayedValidation", 2)
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

function JustAC:SetupAssistedCombatCVars()
    local profile = self:GetProfile()
    if not profile or not profile.autoEnableAssistedMode then return end
    
    local assistedMode = GetCVarBool("assistedMode")
    if not assistedMode then
        SetCVar("assistedMode", "1")
    end
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
    end
    
    if self.mainFrame then
        self.mainFrame:Hide()
    end
end

function JustAC:RefreshConfig()
    self:Print("Profile changed - refreshing configuration")
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
    local assistedMode = GetCVarBool("assistedMode") or false
    local assistedHighlight = GetCVarBool("assistedCombatHighlight") or false
    
    if assistedMode then
        self:Print("Assisted Combat mode detected and active!")
        if assistedHighlight then
            self:Print("Both JustAC and Blizzard highlights are enabled - they work great together!")
        else
            self:Print("JustAC provides enhanced rotation display with macro parsing and hotkeys.")
        end
    else
        self:Print("Welcome! JustAC enhances WoW's assisted combat system.")
        self:Print("For best results, enable: /console assistedMode 1")
        self:Print("Optional highlighting: /console assistedCombatHighlight 1")
    end
    self:Print("Type /jac for options, right-click icons to set custom hotkeys.")
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

-- Called on UNIT_HEALTH event - efficient, only fires when health actually changes
-- Hysteresis: once defensive icon shows, only hide when health recovers to near-full
local DEFENSIVE_HIDE_THRESHOLD = 90  -- Must reach 90% health to hide the icon

function JustAC:OnHealthChanged(event, unit)
    if unit ~= "player" then return end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives or not profile.defensives.enabled then return end
    
    -- Only show in combat if configured
    if profile.defensives.showOnlyInCombat and not UnitAffectingCombat("player") then
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
        self.defensiveIconActive = false
        return
    end
    
    local healthPercent = BlizzardAPI and BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
    if not healthPercent then return end  -- Fail-safe if secrets block access
    
    local defensiveSpell = nil
    
    -- Hysteresis: once showing, only hide when health reaches near-full (prevents flicker)
    if self.defensiveIconActive and healthPercent >= DEFENSIVE_HIDE_THRESHOLD then
        -- Health recovered enough, hide the icon
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
        self.defensiveIconActive = false
        return
    end
    
    -- Two-tier priority: self-heals first (higher threshold), then cooldowns (lower threshold)
    if healthPercent <= profile.defensives.selfHealThreshold then
        -- First try self-heals (quick abilities to weave into rotation)
        defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.selfHealSpells)
    end
    
    -- If no self-heal available and health is critically low, try major cooldowns
    if not defensiveSpell and healthPercent <= profile.defensives.cooldownThreshold then
        defensiveSpell = self:GetBestDefensiveSpell(profile.defensives.cooldownSpells)
    end
    
    -- Show or hide the defensive icon
    if defensiveSpell then
        if UIManager and UIManager.ShowDefensiveIcon then
            UIManager.ShowDefensiveIcon(self, defensiveSpell)
        end
        self.defensiveIconActive = true
    elseif not self.defensiveIconActive then
        -- Only hide if not already in hysteresis mode (health between threshold and 90%)
        if UIManager and UIManager.HideDefensiveIcon then
            UIManager.HideDefensiveIcon(self)
        end
    end
end

-- Get the first usable spell from a given spell list
function JustAC:GetBestDefensiveSpell(spellList)
    if not spellList then return nil end
    
    local profile = self:GetProfile()
    if not profile or not profile.defensives then return nil end
    
    for i, spellID in ipairs(spellList) do
        if spellID and spellID > 0 then
            -- Check if spell is known
            local spellInfo = BlizzardAPI and BlizzardAPI.GetSpellInfo and BlizzardAPI.GetSpellInfo(spellID)
            if spellInfo then
                -- Check if usable (not on CD, has resources) if configured
                if profile.defensives.showOnlyUsable then
                    local isUsable = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                    local start, duration
                    if BlizzardAPI and BlizzardAPI.GetSpellCooldown then
                        start, duration = BlizzardAPI.GetSpellCooldown(spellID)
                    end
                    local onCooldown = start and start > 0 and duration and duration > 1.5  -- Ignore GCD
                    
                    if isUsable and not onCooldown then
                        return spellID
                    end
                else
                    return spellID
                end
            end
        end
    end
    
    return nil
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
            if C_Spell and C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(spellID)
                return info and info.name ~= nil
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
        self:Print("Set custom hotkey '" .. hotkeyText:trim() .. "' for " .. spellName)
    else
        profile.hotkeyOverrides[spellID] = nil
        local spellInfo = self:GetCachedSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        self:Print("Removed custom hotkey for " .. spellName)
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
    return SpellQueue.IsSpellBlacklisted(spellID, "combatAssist") or SpellQueue.IsSpellBlacklisted(spellID, "fixedQueue")
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
        if ActionBarScanner and ActionBarScanner.InvalidateHotkeyCache then
            ActionBarScanner.InvalidateHotkeyCache()
        end
        -- Aura changes affect RedundancyFilter's buff/form detection
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

function JustAC:OnBindingsUpdated()
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then
        ActionBarScanner.OnKeybindsChanged()
        self:ForceUpdate()
    end
end

-- Proc glow events: Blizzard shows/hides overlay for proc abilities
-- More responsive than waiting for UNIT_AURA throttle
function JustAC:OnProcGlowChange(event, spellID)
    -- Proc changed, refresh immediately for responsiveness
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