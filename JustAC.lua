-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Main Addon Module
local JustAC = LibStub("AceAddon-3.0"):NewAddon("JustAssistedCombat", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceDB = LibStub("AceDB-3.0")

local UIRenderer, UIFrameFactory, UIAnimations, UIHealthBar, SpellQueue, ActionBarScanner, BlizzardAPI, FormCache, Options, MacroParser, RedundancyFilter, UINameplateOverlay, DefensiveEngine, GapCloserEngine, TargetFrameAnchor, KeyPressDetector, SpellDB

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
        showOffensiveHotkeys = true, -- Legacy; migrated to textOverlays.hotkey.show on load
        gamepadIconStyle = "xbox",    -- Gamepad button icons: "generic", "xbox", "playstation"
        inputPreference = "auto",       -- Keybind input: "auto", "keyboard", "gamepad"
        debugMode = false,
        isManualMode = false,
        tooltipMode = "always",       -- "never", "outOfCombat", or "always"
        glowMode = "all",                 -- "all", "primaryOnly", "procOnly", "none"
        showFlash = true,                 -- Flash icon on matching key press
        showUsabilityTint = true,         -- Tint icons by usability state (blue=no resources, gray=unavailable)
        showRangeTint = true,             -- Red tint icons when target is out of range
        showCastingHighlight = true,      -- White border on icon while its spell is actively being cast
        firstIconScale = 1.0,
        queueIconDesaturation = 0,
        frameOpacity = 1.0,            -- Global opacity for entire frame (0.0-1.0)
        hideQueueOutOfCombat = false,  -- Hide the entire queue when out of combat
        hideQueueWhenMounted = false,  -- Hide the queue while mounted
        displayMode = "queue",         -- "disabled" / "queue" / "overlay" / "both"
        requireHostileTarget = false,  -- Only show queue when targeting a hostile unit
        showHealthBar = false,         -- Legacy (migrated to defensives.showHealthBar; cleared on load)
        showPetHealthBar = false,      -- Legacy (migrated to defensives.showPetHealthBar; cleared on load)
        hideItemAbilities = false,     -- Hide equipped item abilities (trinkets, tinkers)
        blacklistPosition1 = false,    -- Apply blacklist to position 1 (Blizzard's primary suggestion)
        panelLocked = false,              -- Legacy (migrated to panelInteraction)
        panelInteraction = "unlocked",    -- "unlocked", "locked", "clickthrough"
        queueOrientation = "LEFT",        -- Queue growth direction: LEFT, RIGHT, UP, DOWN
        targetFrameAnchor = "DISABLED",     -- Anchor to target frame: DISABLED, TOP, BOTTOM, LEFT, RIGHT
        showSpellbookProcs = true,        -- Show procced spells from spellbook (not just rotation list)
        includeHiddenAbilities = true,    -- Include abilities hidden behind macro conditionals
        blacklistedSpells = {},            -- Per-spec spell blacklist: blacklistedSpells["WARRIOR_1"] = {[spellID] = true}
        hotkeyOverrides = {},             -- Profile-level hotkey display overrides (included in profile copy)
        interruptMode = "ccPrefer",        -- Interrupt reminder mode: "disabled", "kickOnly", "ccPrefer" ("importantOnly" reserved for future)
        interruptAlertSound = "none",      -- Alert sound when interrupt icon first appears; see INTERRUPT_ALERT_SOUNDS in UIRenderer.lua
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
            maxIcons          = 3,       -- 1-5 DPS queue slots
            reverseAnchor     = false,   -- false = RIGHT (default), true = LEFT
            expansion         = "down",   -- "out" (horizontal), "up" (vertical up), "down" (vertical down)
            iconSize          = 32,
            iconSpacing       = 2,   -- px between successive icons in the cluster
            opacity           = 1.0, -- icon opacity (0.1–1.0)
            showGlow          = true,
            glowMode          = "all",
            firstIconScale    = 1.0,
            queueIconDesaturation = 0,
            showHotkey        = true, -- Legacy; migrated to textOverlays.hotkey.show on load
            showDefensives       = true,
            maxDefensiveIcons    = 3,    -- 1-5
            defensiveDisplayMode = "always", -- "healthBased", "combatOnly", "always"
            defensiveGlowMode    = "all",
            defensiveIconScale   = 1.0,
            showHealthBar        = true,
            showPetHealthBar     = true,
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
            showHotkeys = true,       -- Legacy (migrated; cleared on load)
            position = "SIDE1",       -- SIDE1 (health bar side), SIDE2, or LEADING (opposite grab tab)
            showHealthBar = true,    -- Display compact health bar above main queue
            showPetHealthBar = true, -- Display compact pet health bar (pet classes only)
            iconScale = 1.0,          -- Scale for defensive icons (same range as Primary Spell Scale)
            maxIcons = 4,             -- Number of defensive icons to show (1-7)
            classSpells = {},         -- Per-spec spell lists: classSpells["WARRIOR_1"] = {defensiveSpells={...}, petHealSpells={...}}
            displayMode = "always", -- "healthBased" (show when low), "combatOnly" (always in combat), "always"
            glowMode = "all",    -- "all", "primaryOnly", "procOnly", "none"
            detached = false,                                    -- Give defensives their own independent draggable frame
            detachedPosition = { point = "CENTER", x = 0, y = 100 }, -- Saved position of the detached defensive frame
            detachedOrientation = "LEFT",                        -- Icon growth direction for detached frame (LEFT/RIGHT/UP/DOWN)
        },
        -- Gap-closer feature (suggest movement spells when target is out of melee range)
        gapClosers = {
            enabled = true,
            showGlow = true,          -- Glow on gap-closer icons (on by default)
            classSpells = {},         -- Per-spec spell lists: classSpells["WARRIOR_1"] = {100, 6544}
        },
    },
    char = {
        lastKnownSpec = nil,
        firstRun = true,
        blacklistedSpells = {},   -- Legacy: migrated to profile on load; kept as schema for migration detection
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

    local profile = self.db and self.db.profile
    if not profile then return end

    -- ── Blacklist migration: db.char → db.profile (per-spec keyed) ──────
    -- Old storage: charData.blacklistedSpells = {[spellID] = true, ...}
    -- New storage: profile.blacklistedSpells = {["CLASS_N"] = {[spellID] = true}, ...}
    -- Migrate char data into the current spec's list (same pattern as hotkeyOverrides migration).
    if not profile.blacklistedSpells then profile.blacklistedSpells = {} end

    if charData.blacklistedSpells and next(charData.blacklistedSpells) then
        local SpellDB = LibStub("JustAC-SpellDB", true)
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

    -- Handle ancient flat profile.blacklistedSpells format (pre-4.x: flat {[spellID]=true})
    -- Detect by checking if any key is numeric (spec-keyed tables have string keys like "WARRIOR_1")
    local hasNumericKey = false
    for key, _ in pairs(profile.blacklistedSpells) do
        if type(key) == "number" or (type(key) == "string" and tonumber(key)) then
            hasNumericKey = true
            break
        end
    end
    if hasNumericKey then
        local SpellDB = LibStub("JustAC-SpellDB", true)
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

    -- Normalize per-spec blacklist tables (string keys → numeric keys)
    for specKey, spellTable in pairs(profile.blacklistedSpells) do
        if type(spellTable) == "table" then
            local normalized = {}
            for key, value in pairs(spellTable) do
                local spellID = tonumber(key)
                if spellID and spellID > 0 and value then
                    normalized[spellID] = true
                end
            end
            profile.blacklistedSpells[specKey] = normalized
        end
    end

    -- ── Defensive classSpells migration: per-class → per-spec keying ────
    -- Old storage: classSpells["WARRIOR"] = {defensiveSpells={...}, ...}
    -- New storage: classSpells["WARRIOR_1"] = {defensiveSpells={...}, ...}
    -- One-time: copy class-level data to all specs of that class, then remove
    -- the class-level key.
    if profile.defensives and profile.defensives.classSpells then
        local _, playerClass = UnitClass("player")
        if playerClass then
            local cs = profile.defensives.classSpells
            local classData = cs[playerClass]
            if classData and type(classData) == "table" then
                -- Check if any list has data (defensiveSpells, petHealSpells, petRezSpells)
                local hasData = false
                for _, v in pairs(classData) do
                    if type(v) == "table" and #v > 0 then hasData = true; break end
                end
                if hasData then
                    -- Copy to all specs (max 4) that don't already have data
                    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 4
                    for i = 1, numSpecs do
                        local specKey = playerClass .. "_" .. i
                        if not cs[specKey] or not next(cs[specKey]) then
                            cs[specKey] = {}
                            for listKey, spellList in pairs(classData) do
                                if type(spellList) == "table" then
                                    cs[specKey][listKey] = {}
                                    for idx, spellID in ipairs(spellList) do
                                        cs[specKey][listKey][idx] = spellID
                                    end
                                end
                            end
                        end
                    end
                end
                -- Remove class-level key to prevent re-migration
                cs[playerClass] = nil
            end
        end
    end

    -- ── Hotkey overrides normalization ───────────────────────────────────
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

    -- ── Legacy setting migrations ───────────────────────────────────────
    -- Migrate panelLocked boolean → panelInteraction string
    if profile.panelLocked == true and (not profile.panelInteraction or profile.panelInteraction == "unlocked") then
        profile.panelInteraction = "locked"
    end
    -- Migrate legacy hotkey show/hide settings → per-queue textOverlays.hotkey.show (one-time)
    -- Main queue: showOffensiveHotkeys → textOverlays.hotkey.show
    -- NOTE: defensives.showHotkeys is NOT migrated here — it was a separate
    -- per-category toggle that no longer exists. Merging it into the unified
    -- toggle would hide ALL hotkeys (offensive + defensive) for users who only
    -- intended to hide defensive hotkeys. Fail-open: show hotkeys by default.
    if profile.textOverlays and profile.textOverlays.hotkey then
        if profile.showOffensiveHotkeys == false then
            profile.textOverlays.hotkey.show = false
        end
    end
    -- Nameplate overlay: nameplateOverlay.showHotkey → nameplateOverlay.textOverlays.hotkey.show
    local npo = profile.nameplateOverlay
    if npo and npo.textOverlays and npo.textOverlays.hotkey then
        if npo.showHotkey == false then
            npo.textOverlays.hotkey.show = false
        end
    end
    -- Migrate showInterrupt + ccRegularMobs → interruptMode (one-time)
    if profile.showInterrupt ~= nil or profile.ccRegularMobs ~= nil then
        if profile.showInterrupt == false then
            profile.interruptMode = "disabled"
        elseif profile.ccRegularMobs == false then
            profile.interruptMode = "kickOnly"
        else
            profile.interruptMode = "ccPrefer"
        end
    end
    if npo and (npo.showInterrupt ~= nil or npo.ccRegularMobs ~= nil) then
        if npo.showInterrupt == false then
            npo.interruptMode = "disabled"
        elseif npo.ccRegularMobs == false then
            npo.interruptMode = "kickOnly"
        else
            npo.interruptMode = "ccPrefer"
        end
    end
    -- Centralization migration: per-surface settings → single central setting
    -- interruptMode: overlay had its own copy → use profile-level only
    if npo and npo.interruptMode ~= nil then
        -- If user customized the overlay's interrupt mode, adopt it as the central value
        -- (only if the main queue is still at default, otherwise main queue wins)
        if profile.interruptMode == "ccPrefer" and npo.interruptMode ~= "ccPrefer" then
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
        -- User had standalone health bar enabled with defensives off — move to defensives setting
        profile.defensives.showHealthBar = true
    end
    if profile.showPetHealthBar == true and profile.defensives and not profile.defensives.enabled then
        profile.defensives.showPetHealthBar = true
    end
    profile.showHealthBar = nil
    profile.showPetHealthBar = nil
    -- Migrate legacy tooltip settings → tooltipMode (one-time)
    if profile.tooltipMode == nil then
        if profile.showTooltips == false then
            profile.tooltipMode = "never"
        elseif profile.tooltipsInCombat then
            profile.tooltipMode = "always"
        else
            profile.tooltipMode = "outOfCombat"
        end
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

function JustAC:OnInitialize()
    self.db = AceDB:New("JustACDB", defaults, JustACGlobal and JustACGlobal.useDefaultProfile or nil)

    -- Initialize binding globals before combat (prevents taint)
    if not _G.BINDING_NAME_JUSTAC_CAST_FIRST then
        _G.BINDING_NAME_JUSTAC_CAST_FIRST = "JustAC: Cast First Spell"
        _G.BINDING_HEADER_JUSTAC = "JustAssistedCombat"
    end
    
    self:NormalizeSavedData()

    self:LoadModules()
    self:InitializeDefensiveSpells()
    
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")
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
    self:RegisterEvent("GAME_PAD_CONNECTED", "OnGamePadChanged")
    self:RegisterEvent("GAME_PAD_DISCONNECTED", "OnGamePadChanged")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
    self:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST", "ForceUpdate")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowChange")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowChange")
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellIconChanged")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("ACTION_RANGE_CHECK_UPDATE", "OnActionRangeUpdate")
    self:RegisterEvent("ACTION_USABLE_CHANGED", "OnActionUsableChanged")
    self:RegisterEvent("UNIT_PET", "OnPetChanged")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("UNIT_ENTERED_VEHICLE",      "OnVehicleChanged")
    self:RegisterEvent("UNIT_EXITED_VEHICLE",       "OnVehicleChanged")
    self:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR",  "OnVehicleChanged")
    self:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR", "OnOverrideBarChanged")
    self:RegisterEvent("UPDATE_POSSESS_BAR",        "OnPossessBarChanged")

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

function JustAC:DelayedValidation()
    self:ValidateAssistedCombatSetup()
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
    if Options then
        if Options.UpdateBlacklistOptions then Options.UpdateBlacklistOptions(self) end
        if Options.UpdateGapCloserOptions then Options.UpdateGapCloserOptions(self) end
        if Options.UpdateDefensivesOptions then Options.UpdateDefensivesOptions(self) end
        if Options.UpdateHotkeyOverrideOptions then Options.UpdateHotkeyOverrideOptions(self) end
    end
end

-- Only on explicit profile reset (not change/copy)
-- Character data (blacklist, spec profiles) is intentionally preserved;
-- Profile-level data (hotkey overrides, settings) is cleared — that's what a reset does.
-- AceDB already resets profile-level settings to defaults.
function JustAC:OnProfileReset()
    self:RefreshConfig()
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
        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
        if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
    end
end

-- Defensive Engine wrapper methods (delegated to DefensiveEngine module)
function JustAC:OnHealthChanged(event, unit)
    if DefensiveEngine then DefensiveEngine.OnHealthChanged(self, event, unit) end
end
function JustAC:InitializeDefensiveSpells()
    if DefensiveEngine then
        DefensiveEngine.InitializeDefensiveSpells(self)
    end
    if GapCloserEngine then
        GapCloserEngine.InitializeGapClosers(self)
    end
end
function JustAC:RestoreDefensiveDefaults(listType)
    if DefensiveEngine then DefensiveEngine.RestoreDefensiveDefaults(self, listType) end
end
function JustAC:GetClassSpellList(listKey)
    if DefensiveEngine then return DefensiveEngine.GetClassSpellList(self, listKey) end
end

function JustAC:UpdateAlternateControlState()
    -- Detect when the player is controlling a vehicle (replaces action bars),
    -- possessing an NPC via Mind Control / similar effects, or using an
    -- override action bar (quest vehicles, NPC control). In any of these cases
    -- our normal rotation spells are completely wrong, so suppress all rendering.
    self.playerInAlternateControl = (UnitHasVehicleUI and UnitHasVehicleUI("player") or false)
        or (HasVehicleActionBar and HasVehicleActionBar() or false)
        or (HasOverrideActionBar and HasOverrideActionBar() or false)
        or (IsPossessBarVisible and IsPossessBarVisible() or false)
end

function JustAC:UpdateDefensiveCooldowns()
    if self.playerInAlternateControl then
        -- Clear defensive icons immediately; leave them hidden until we regain control.
        if UIRenderer then UIRenderer.HideDefensiveIcons(self) end
        return
    end
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
    SpellDB = LibStub("JustAC-SpellDB", true)
    
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
        if UINameplateOverlay and UINameplateOverlay.InvalidateHotkeyCache then UINameplateOverlay.InvalidateHotkeyCache() end
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

    -- Suppress queue while controlling a vehicle or possessing an NPC.
    -- Our rotation spells are meaningless in these states; render an empty queue
    -- so all icons hide cleanly through the normal renderer path.
    if self.playerInAlternateControl then
        UIRenderer.RenderSpellQueue(self, {})
        if UINameplateOverlay then UINameplateOverlay.Render(self, {}) end
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
    if UINameplateOverlay and UINameplateOverlay.RefreshInterruptSpells then
        UINameplateOverlay.RefreshInterruptSpells()
    end
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
        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
        if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
    elseif event == "PLAYER_REGEN_ENABLED" then
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
        if UIAnimations and UIAnimations.PauseAllGlows then
            UIAnimations.PauseAllGlows(self)
        end
        self:InvalidateCaches({auras = true})
        if RedundancyFilter and RedundancyFilter.ClearActivationTracking then
            RedundancyFilter.ClearActivationTracking()
        end
        -- Re-resolve interrupt spells if deferred from combat
        if self.interruptRefreshPending then
            self:RefreshInterruptSpells()
        end
        -- Re-apply anchor and rebuild layout if either was changed during combat.
        -- UpdateFrameSize subsumes UpdateTargetFrameAnchor + ForceUpdateAll.
        if self.pendingLayoutRebuild then
            self.pendingLayoutRebuild = false
            self:UpdateFrameSize()
        else
            if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
            self:ForceUpdateAll()
        end
        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
        if AceConfigRegistry then AceConfigRegistry:NotifyChange("JustAssistedCombat") end
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
    -- Populate gap closer defaults for the new spec if empty
    if GapCloserEngine and GapCloserEngine.InitializeGapClosers then
        GapCloserEngine.InitializeGapClosers(self)
    end
    -- Invalidate options spellbook cache so it rebuilds for the new spec
    local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
    if SpellSearch and SpellSearch.InvalidateSpellbookCache then
        SpellSearch.InvalidateSpellbookCache()
    end
    self:InvalidateCaches({spells = true, macros = true, hotkeys = true})
    self:RefreshInterruptSpells()
    self:ForceUpdate()
end

function JustAC:OnSpellsChanged()
    if SpellQueue and SpellQueue.OnSpellsChanged then SpellQueue.OnSpellsChanged() end
    -- Invalidate options spellbook cache so new/removed spells appear in search
    local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
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
    -- Form changes swap the active action bar (Druid Cat/Bear/etc.), so the
    -- melee range reference slot may now point at a different spell or be
    -- absent entirely.  Invalidate so ResolveMeleeReference re-queries the
    -- correct form-bar slots on the next GetGapCloserSpell call.
    if GapCloserEngine then
        GapCloserEngine.InvalidateGapCloserCache()
        GapCloserEngine.ClearRangeState()
    end
    self:InvalidateCaches({macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnShapeshiftFormsRebuilt()
    self:InvalidateCaches({forms = true, macros = true, hotkeys = true})
    self:ForceUpdate()
end

function JustAC:OnUnitAura(event, unit, updateInfo)
    if unit ~= "player" then return end

    -- Any player aura change (including mount removal) must break the mainHidden early
    -- exit in OnUpdate so the queue can re-evaluate IsMounted() / visibility conditions.
    self:MarkQueueDirty()

    -- 12.0: Pass updateInfo to RedundancyFilter for incremental instance map updates
    -- This captures addedAuras (new aura identity) and removedAuraInstanceIDs (cleanup)
    -- BEFORE cache invalidation, so the map is current when RefreshAuraCache runs
    if RedundancyFilter and RedundancyFilter.OnUnitAuraUpdate then
        RedundancyFilter.OnUnitAuraUpdate(updateInfo)
    end

    local now = GetTime()
    if now - (self.lastAuraInvalidation or 0) > 0.5 then
        self.lastAuraInvalidation = now
        self:InvalidateCaches({auras = true})
    end
end

function JustAC:OnActionBarChanged()
    self:InvalidateCaches({hotkeys = true, macros = true})
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    self:ForceUpdate()
end

function JustAC:OnSpecialBarChanged()
    if ActionBarScanner and ActionBarScanner.OnSpecialBarChanged then ActionBarScanner.OnSpecialBarChanged() end
    self:ForceUpdate()
end

function JustAC:OnVehicleChanged(event, unit)
    if unit ~= "player" then return end

    self:UpdateAlternateControlState()
    self:InvalidateCaches({macros = true, hotkeys = true})
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    self:ForceUpdate()
end

function JustAC:OnOverrideBarChanged()
    -- Fires when an override action bar appears or disappears (quest vehicles, NPC control).
    self:UpdateAlternateControlState()
    self:InvalidateCaches({macros = true, hotkeys = true})
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    self:ForceUpdate()
end

function JustAC:OnPossessBarChanged()
    -- Fires when Mind Control / possess effects begin or end.
    self:UpdateAlternateControlState()
    self:InvalidateCaches({macros = true, hotkeys = true})
    if BlizzardAPI and BlizzardAPI.InvalidateSlotUsabilityCache then
        BlizzardAPI.InvalidateSlotUsabilityCache()
    end
    self:ForceUpdate()
end

function JustAC:OnBindingsUpdated()
    if ActionBarScanner and ActionBarScanner.OnKeybindsChanged then
        ActionBarScanner.OnKeybindsChanged()
        self:ForceUpdate()
    end
end

function JustAC:OnGamePadChanged()
    -- Input device changed — re-select preferred bindings (auto mode)
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

    -- Procs affect rotation and defensive priorities — ForceUpdateAll marks both
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
    -- ForceUpdateAll marks both queues dirty; OnUpdate renders on next tick.
    self:ForceUpdateAll()
end

function JustAC:OnActionUsableChanged(_, changes)
    if BlizzardAPI and BlizzardAPI.OnActionUsableChanged then
        BlizzardAPI.OnActionUsableChanged(changes)
    end
    self:ForceUpdateAll()
end

function JustAC:OnActionRangeUpdate(_, slot, isInRange, checksRange)
    if GapCloserEngine then
        local isRefSlot = GapCloserEngine.OnActionRangeUpdate(slot, isInRange, checksRange)
        -- Only rebuild the queue when the melee reference slot changes range.
        -- This prevents every random ability's range event from triggering
        -- a gap-closer re-evaluation.  Trigger on both directions so we
        -- show the gap closer instantly on out-of-range AND remove it
        -- promptly on return-to-range.
        if isRefSlot then
            if SpellQueue then SpellQueue.ForceUpdate() end
            self:MarkQueueDirty()
        end
    end
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

-- Delegated to TargetFrameAnchor module (thin wrappers for external callers)
function JustAC:ClampFrameToScreen()
    if TargetFrameAnchor then TargetFrameAnchor.ClampFrameToScreen(self) end
end
function JustAC:IsStandardTargetFrame()
    if TargetFrameAnchor then return TargetFrameAnchor.IsStandardTargetFrame(self) end
    return false
end
function JustAC:UpdateTargetFrameAnchor()
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
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
    if BlizzardAPI and BlizzardAPI.RefreshItemSpellCache then
        BlizzardAPI.RefreshItemSpellCache()
    end
    self:ForceUpdate()
end

function JustAC:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    if UnitAffectingCombat("player") and RedundancyFilter and RedundancyFilter.RecordSpellActivation then
        RedundancyFilter.RecordSpellActivation(spellID)
    end

    -- If a CC spell landed, suppress the interrupt icon for CC_APPLIED_SUPPRESS seconds so
    -- the next CC suggestion doesn't flash before the game registers the CC state on target.
    -- spellID from UNIT_SPELLCAST_SUCCEEDED is NeverSecret (player's own cast).
    if SpellDB and SpellDB.IsCrowdControlSpell(spellID) then
        -- UINameplateOverlay.NotifyCCApplied() delegates to UIRenderer.NotifyCCApplied() internally,
        -- so one call covers both renderers (debounce state is now shared in UIRenderer).
        if UIRenderer and UIRenderer.NotifyCCApplied then UIRenderer.NotifyCCApplied() end
        -- Notify CC-failure learning: after a short delay, IsTargetCCImmune
        -- will check if UnitIsCrowdControlled("target") became true.
        if BlizzardAPI and BlizzardAPI.NotifyCCCastOnTarget then
            BlizzardAPI.NotifyCCCastOnTarget()
        end
    end

    -- Cast completed — dirty flags ensure next OnUpdate tick rebuilds both queues.
    -- No deferred timer needed; the natural OnUpdate cadence provides sufficient
    -- settle time (~30-50ms) for game state to update after the cast.
    self:ForceUpdateAll()
end

function JustAC:OnCooldownUpdate()
    -- SPELL_UPDATE_COOLDOWN fires ~10x per cast (GCD cascade). ForceUpdateAll
    -- is idempotent — repeated calls just set dirty flags that are already set.
    self:ForceUpdateAll()
end

--- Marks queues dirty and ensures the next OnUpdate tick processes immediately.
--- All rendering goes through the unified OnUpdate loop (no synchronous renders).
--- Multiple calls per frame are idempotent — setting dirty flags is a no-op when already set.
function JustAC:ForceUpdate(includeDefensives)
    spellQueueDirty = true
    if includeDefensives then defensiveQueueDirty = true end
    -- Process on very next OnUpdate tick (~7-16ms at typical framerates)
    if self.updateTimeLeft then self.updateTimeLeft = 0 end
end

function JustAC:ForceUpdateAll()
    self:ForceUpdate(true)
end

function JustAC:OpenOptionsPanel()
    if Options then
        if self.InitializeDefensiveSpells then
            self:InitializeDefensiveSpells()
        end
        if Options.UpdateBlacklistOptions then Options.UpdateBlacklistOptions(self) end
        if Options.UpdateHotkeyOverrideOptions then Options.UpdateHotkeyOverrideOptions(self) end
        if Options.UpdateDefensivesOptions then Options.UpdateDefensivesOptions(self) end
        if Options.UpdateGapCloserOptions then Options.UpdateGapCloserOptions(self) end
    end

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

--------------------------------------------------------------------------------
-- Update Cycle Architecture
--
-- All rendering is driven by a single OnUpdate loop. No synchronous rendering
-- occurs in event handlers — they only set dirty flags and reset the timer.
--
-- Tier 1 (spell queue):    CVar rate, min 0.03s  (~20-33Hz) — rotation + render
-- Tier 2 (cooldown swipes): 0.08s fixed           (~12Hz)   — CD widget params
-- Tier 3 (defensives):      2× CVar rate           (~10Hz)  — health evaluation
-- Tier 4 (idle/OOC):       0.5s                    (2Hz)    — nothing happening
--
-- ForceUpdate() / ForceUpdateAll() set dirty flags + updateTimeLeft = 0
-- so the next frame processes. Multiple calls per frame are idempotent.
--------------------------------------------------------------------------------

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

        -- Freeze updates while the frame is being dragged (smooth drag, no wasted work)
        if self.isDragging then
            self.updateTimeLeft = 0.1
            return
        end

        -- Early exit: skip all work if UI is completely hidden (saves CPU when mounted, etc.)
        local mainFrame = self.mainFrame
        local mainHidden = not mainFrame or not mainFrame:IsShown()
        local defIcons = self.defensiveIcons
        local defHidden = (not defIcons or #defIcons == 0)
            and (not self.defensiveFrame or not self.defensiveFrame:IsShown())
        local npHidden = not self.nameplateIcons or #self.nameplateIcons == 0
        if mainHidden and defHidden and npHidden
                and not spellQueueDirty then
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
            -- Out of combat: idle when clean, near-combat rate when dirty
            if not spellQueueDirty and not defensiveQueueDirty then
                updateRate = IDLE_CHECK_INTERVAL
            else
                updateRate = math_max(cachedUpdateRate, 0.05)
            end
        end

        self.updateTimeLeft = updateRate

        -- Always update spell queue (Blizzard doesn't provide events for rotation changes)
        -- When dirty, bypass SpellQueue's internal throttle so event-driven updates
        -- get the same low-latency path as explicit ForceUpdate() calls.
        if spellQueueDirty and SpellQueue and SpellQueue.ForceUpdate then
            SpellQueue.ForceUpdate()
        end
        self:UpdateSpellQueue()
        spellQueueDirty = false

        -- Only update defensive cooldowns if dirty or periodic check
        if defensiveQueueDirty or (now - lastFullUpdate) > IDLE_CHECK_INTERVAL then
            -- Full queue rebuild: nil event bypasses DefensiveEngine throttle.
            -- Always rebuild (not just cooldown swipes) so "always" and "combatOnly"
            -- modes surface new icons promptly when cooldowns expire.
            self:OnHealthChanged(nil, "player")
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
    if TargetFrameAnchor then TargetFrameAnchor.UpdateTargetFrameAnchor(self) end
    -- ForceUpdateAll (not ForceUpdate) so OnHealthChanged fires → ResizeToCount
    -- runs immediately, keeping health bar width in sync with visible defensive icons.
    self:ForceUpdateAll()
end

function JustAC:SavePosition()
    if UIFrameFactory and UIFrameFactory.SavePosition then UIFrameFactory.SavePosition(self) end
end