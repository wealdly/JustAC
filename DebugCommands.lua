-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Debug Commands Module - Provides diagnostic commands for testing and troubleshooting
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 21)
if not DebugCommands then return end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------
function DebugCommands.ShowHelp(addon)
    addon:Print("Available commands:")
    addon:Print("/jac - Open options panel")
    addon:Print("/jac toggle - Pause/resume display")
    addon:Print("/jac debug - Toggle debug mode")
    addon:Print("/jac reset - Reset frame position")
    addon:Print("/jac profile <name> - Switch profile")
    addon:Print("/jac profile list - List profiles")
    addon:Print("/jac find [spell] - Find spell on action bars (defaults to AC suggestion)")
    addon:Print("/jac inspect modules - Check module health")
    addon:Print("/jac inspect cooldown [spell] - Test cooldown APIs (defaults to AC suggestion)")
    addon:Print("/jac inspect defensives - Diagnose defensive system")
    addon:Print("/jac inspect interrupts - Diagnose interrupt/CC queue state")
    addon:Print("/jac inspect burst - Dump burst injection priority list")
    addon:Print("/jac inspect auras - Diagnose aura cache state")
    addon:Print("/jac inspect buffs - Diagnose pre-combat buff checklist (out of combat)")
    addon:Print("/jac inspect perf - Queue build rate statistics (requires debug mode)")
    addon:Print("/jac inspect perf reset - Reset build counters")
    addon:Print("/jac inspect rank - Queue context inference and per-spell ordering ranks")
    addon:Print("/jac inspect chargediag [spell] - Arm a 60s charge-event/secrecy probe")
    addon:Print("/jac inspect castdiag - Arm a one-shot cast-interruptibility probe")
    addon:Print("/jac inspect healthprobe - Sweep every OOC health-detection channel (run while hurt)")
    addon:Print("/jac inspect validate [arm] - Validate every secrecy/API assumption; arm = diff on combat enter/exit")
    addon:Print("/jac help - Show this help")
end

--------------------------------------------------------------------------------
-- OOC Health Detection Probe
-- One-shot sweep of every plausible channel for reading player health out of
-- combat in 12.0.7 secret-restricted zones. Run while HURT in the open world;
-- every read is pcall-guarded, nothing is written or branched on a secret.
--------------------------------------------------------------------------------
function DebugCommands.HealthProbe(addon)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local IsSecret = BlizzardAPI and BlizzardAPI.IsSecretValue or function() return false end
    local function safe(v)
        if IsSecret(v) then return "<secret>" end
        local ok, s = pcall(tostring, v)
        return ok and s or "<?>"
    end
    -- Read via pcall; classify: SEALED (threw), <secret>, or the plain value.
    local function rd(fn)
        local ok, v = pcall(fn)
        if not ok then return "|cffff6666SEALED|r" end
        if IsSecret(v) then return "|cffff6600<secret>|r" end
        return "|cff00ff00" .. safe(v) .. "|r"
    end

    addon:Print("===== OOC Health Probe (run while HURT) =====")

    -- A. Context: which restriction regime are we in, and why?
    local name, instanceType = GetInstanceInfo()
    addon:Print("A. context:")
    addon:Print("  zone=" .. safe(name) .. " instanceType=" .. safe(instanceType)
        .. " inCombat=" .. tostring(InCombatLockdown()))
    addon:Print("  HasSecretRestrictions=" .. rd(function() return C_Secrets.HasSecretRestrictions() end)
        .. " ShouldAurasBeSecret=" .. rd(function() return C_Secrets.ShouldAurasBeSecret() end))
    addon:Print("  warModeDesired=" .. rd(function() return C_PvP.IsWarModeDesired() end)
        .. " warModeActive=" .. rd(function() return C_PvP.IsWarModeActive() end)
        .. "  (tests the war-mode-causes-it hypothesis)")

    -- B. Raw unit APIs: which values are actually secret right now?
    addon:Print("B. raw APIs:")
    addon:Print("  UnitHealth=" .. rd(function() return UnitHealth("player") end)
        .. " UnitHealthMax=" .. rd(function() return UnitHealthMax("player") end))
    addon:Print("  UnitPower=" .. rd(function() return UnitPower("player") end)
        .. " UnitPowerMax=" .. rd(function() return UnitPowerMax("player") end)
        .. " UnitIsDeadOrGhost=" .. rd(function() return UnitIsDeadOrGhost("player") end))
    addon:Print("  UnitGetTotalAbsorbs=" .. rd(function() return UnitGetTotalAbsorbs("player") end)
        .. " UnitGetIncomingHeals=" .. rd(function() return UnitGetIncomingHeals("player") end))

    -- C. Alternative APIs: call them, don't just check existence. A readable
    --    (possibly quantized) percent here is the sanctioned clean fix.
    addon:Print("C. candidate APIs (called live):")
    if UnitHealthPercent then
        addon:Print("  UnitHealthPercent('player')=" .. rd(function() return UnitHealthPercent("player") end)
            .. "  ('player', true)=" .. rd(function() return UnitHealthPercent("player", true) end))
    else
        addon:Print("  UnitHealthPercent: absent")
    end
    if UnitPercentHealthFromGUID then
        addon:Print("  UnitPercentHealthFromGUID(playerGUID)=" .. rd(function()
            return UnitPercentHealthFromGUID(UnitGUID("player")) end))
    else
        addon:Print("  UnitPercentHealthFromGUID: absent")
    end
    addon:Print("  C_UnitHealth=" .. tostring(type(C_UnitHealth))
        .. " UnitCastingDuration=" .. tostring(type(UnitCastingDuration))
        .. "  (duration-object pattern; a health analog would be the clean fix)")

    -- D. Secret-handling API surface: function names are plain strings - list them.
    --    An unnoticed comparison/percent helper here would be the sanctioned answer.
    local function dumpKeys(label, t)
        if type(t) ~= "table" then addon:Print("  " .. label .. ": absent"); return end
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        addon:Print("  " .. label .. " (" .. #keys .. "): " .. table.concat(keys, ", "))
    end
    addon:Print("D. secret-API surface:")
    dumpKeys("C_Secrets", C_Secrets)
    dumpKeys("C_CurveUtil", C_CurveUtil)

    -- E. Frame-derived reads: Blizzard frames consume the secret engine-side;
    --    is any RESULTING widget state an ordinary number?
    addon:Print("E. frame-derived reads:")
    local hb = PlayerFrame and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
    hb = hb or (PlayerFrame and PlayerFrame.healthbar)
    if hb then
        addon:Print("  PlayerFrame bar: GetValue=" .. rd(function() return hb:GetValue() end)
            .. " minmax=" .. rd(function() local _, mx = hb:GetMinMaxValues(); return mx end))
        addon:Print("    fillWidth=" .. rd(function()
                local tex = hb:GetStatusBarTexture(); return tex and tex:GetWidth() end)
            .. " barWidth=" .. rd(function() return hb:GetWidth() end)
            .. "  (both plain numbers = ratio is readable health!)")
        addon:Print("    fillTexCoordRight=" .. rd(function()
                local tex = hb:GetStatusBarTexture()
                if not tex then return nil end
                local _, _, _, _, _, _, r = tex:GetTexCoord(); return r end))
        local txt = hb.TextString or hb.text or (hb.HealthBarText)
        addon:Print("    statusText=" .. (txt and rd(function() return txt:GetText() end) or "|cff888888no fontstring|r")
            .. "  (needs status text enabled in Blizzard options)")
    else
        addon:Print("  PlayerFrame health bar: not found")
    end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit("player", false)
    local phb = plate and plate.UnitFrame and plate.UnitFrame.healthBar
    if phb then
        addon:Print("  personal-plate bar: GetValue=" .. rd(function() return phb:GetValue() end)
            .. " fillWidth=" .. rd(function()
                local tex = phb:GetStatusBarTexture(); return tex and tex:GetWidth() end)
            .. " barWidth=" .. rd(function() return phb:GetWidth() end))
    else
        addon:Print("  personal-plate bar: not shown (enable Personal Resource Display to test)")
    end

    addon:Print("F. verdict guide: any GREEN number in E that tracks your real health")
    addon:Print("   percent = a readable channel; all SEALED/<secret> = heuristics stay.")
    addon:Print("=============================================")
end

--------------------------------------------------------------------------------
-- Profile Management
--------------------------------------------------------------------------------
function DebugCommands.ManageProfile(addon, profileAction)
    if not profileAction then
        addon:Print("Usage: /jac profile <name> or /jac profile list")
        return
    end
    
    if profileAction == "list" then
        local profiles = addon.db:GetProfiles()
        if profiles then
            addon:Print("Available profiles:")
            for _, name in ipairs(profiles) do
                local current = (name == addon.db:GetCurrentProfile()) and " |cff00ff00(current)|r" or ""
                addon:Print("  " .. name .. current)
            end
        else
            addon:Print("No profiles available")
        end
    else
        -- SetProfile silently creates unknown profiles; check existence so a
        -- typo doesn't create an empty profile and "reset" all settings.
        local exists = false
        for _, name in ipairs(addon.db:GetProfiles()) do
            if name == profileAction then
                exists = true
                break
            end
        end
        if exists then
            addon.db:SetProfile(profileAction)
            addon:Print("Switched to profile: " .. profileAction)
        else
            addon:Print("Profile not found: " .. profileAction)
        end
    end
end

--------------------------------------------------------------------------------
-- Module Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.ModuleDiagnostics(addon)
    addon:Print("=== JustAC Module Diagnostics ===")

    local modules = {
        {"JustAC-BlizzardAPI", "BlizzardAPI"},
        {"JustAC-FormCache", "FormCache"},
        {"JustAC-MacroParser", "MacroParser"},
        {"JustAC-ActionBarScanner", "ActionBarScanner"},
        {"JustAC-RedundancyFilter", "RedundancyFilter"},
        {"JustAC-SpellQueue", "SpellQueue"},
        {"JustAC-UIRenderer", "UIRenderer"},
        {"JustAC-UIFrameFactory", "UIFrameFactory"},
        {"JustAC-UIAnimations", "UIAnimations"},
        {"JustAC-UIHealthBar", "UIHealthBar"},
        {"JustAC-Options", "Options"},
    }
    
    for _, moduleInfo in ipairs(modules) do
        local libName, displayName = moduleInfo[1], moduleInfo[2]
        local module = LibStub(libName, true)
        if module then
            addon:Print("|cff00ff00✓|r " .. displayName)
        else
            addon:Print("|cffff0000✗|r " .. displayName .. " - NOT LOADED")
        end
    end

    addon:Print("")
    addon:Print("Assisted Combat API:")
    local hasAPI = C_AssistedCombat and C_AssistedCombat.GetRotationSpells
    addon:Print("  C_AssistedCombat: " .. (hasAPI and "|cff00ff00OK|r" or "|cffff0000MISSING|r"))

    local assistedMode = GetCVarBool("assistedMode")
    addon:Print("  assistedMode CVar: " .. (assistedMode and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI then
        if BlizzardAPI.IS_MIDNIGHT_OR_LATER then
            addon:Print("  WoW Version: |cffffff0012.0+ (Midnight)|r")
        end
        
        if BlizzardAPI.GetFeatureAvailability then
            local features = BlizzardAPI.GetFeatureAvailability()
            local secretCount = 0
            if not features.healthAccess then secretCount = secretCount + 1 end
            if not features.auraAccess then secretCount = secretCount + 1 end
            if not features.procAccess then secretCount = secretCount + 1 end
            if secretCount > 0 then
                addon:Print("  Secret Values: |cffffff00" .. secretCount .. " API(s) returning secrets|r")
            else
                addon:Print("  Secret Values: |cff00ff00None detected|r")
            end
        end
    end

    addon:Print("")
    addon:Print("Database: " .. (addon.db and addon.db.profile and "|cff00ff00OK|r" or "|cffff0000FAILED|r"))
    addon:Print("Debug Mode: " .. (addon.db and addon.db.profile and addon.db.profile.debugMode and "|cff00ff00ON|r" or "OFF"))
    
    addon:Print("===========================")
end

--------------------------------------------------------------------------------
-- Find Spell on Action Bars
--------------------------------------------------------------------------------
function DebugCommands.FindSpell(addon, spellArg)
    local spellName = type(spellArg) == "string" and spellArg:match("^%s*(.-)%s*$") or spellArg
    if spellName == "" then spellName = nil end
    local contextSpellID = nil  -- spell ID when using AC context default
    if not spellName then
        -- Context default: use AC next cast suggestion
        if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local ok, nextID = pcall(C_AssistedCombat.GetNextCastSpell)
            if ok and nextID and type(nextID) == "number" then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(nextID)
                if info and info.name then
                    spellName = info.name
                    contextSpellID = nextID
                end
            end
        end
        if not spellName then
            addon:Print("Usage: /jac find [spell]")
            addon:Print("No active AC suggestion found. Specify a spell name to search.")
            return
        end
    end
    
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local MacroParser = LibStub("JustAC-MacroParser", true)
    
    addon:Print("=== Searching for: " .. spellName .. " ===")

    -- Re-use the ID we already have from the context path, or look it up by name
    local spellInfo
    if contextSpellID then
        spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(contextSpellID)
    else
        spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellName)
    end
    if spellInfo then
        addon:Print("Spell ID: " .. spellInfo.spellID .. " | Name: " .. spellInfo.name)
    else
        addon:Print("Could not find spell info for: " .. spellName)
    end
    
    local lowerSpellName = spellName:lower()
    local foundAnything = false
    
    for slot = 1, 180 do
        if HasAction(slot) then
            local actionType, actionID = GetActionInfo(slot)

            if actionType == "spell" and actionID then
                local slotSpellInfo = C_Spell.GetSpellInfo(actionID)
                if slotSpellInfo and slotSpellInfo.name and slotSpellInfo.name:lower():find(lowerSpellName, 1, true) then
                    local bar = math.ceil(slot / 12)
                    local button = ((slot - 1) % 12) + 1
                    local key = GetBindingKey("ACTIONBUTTON" .. button) or ""
                    addon:Print(string.format("  Slot %d (Bar %d, Btn %d): %s [%s]", 
                        slot, bar, button, slotSpellInfo.name, key ~= "" and key or "no key"))
                    foundAnything = true
                end
            end

            if actionType == "macro" then
                local macroName = GetActionText(slot)
                if macroName then
                    local _, _, body = GetMacroInfo(macroName)
                    if body and body:lower():find(lowerSpellName, 1, true) then
                        local bar = math.ceil(slot / 12)
                        local button = ((slot - 1) % 12) + 1
                        local key = GetBindingKey("ACTIONBUTTON" .. button) or ""

                        local casts = false
                        if MacroParser and spellInfo then
                            local entry = MacroParser.GetMacroSpellInfo(slot, spellInfo.spellID, spellInfo.name)
                            casts = entry and entry.found
                        end
                        
                        local castStr = casts and "|cff00ff00CASTS|r" or "|cffffff00mentions|r"
                        addon:Print(string.format("  Slot %d (Bar %d, Btn %d): Macro '%s' %s spell [%s]",
                            slot, bar, button, macroName, castStr, key ~= "" and key or "no key"))
                        foundAnything = true
                    end
                end
            end
        end
    end
    
    if not foundAnything then
        addon:Print("No matches found on action bars")
    end
    
    if spellInfo and ActionBarScanner and ActionBarScanner.GetSpellHotkey then
        local hotkey = ActionBarScanner.GetSpellHotkey(spellInfo.spellID)
        addon:Print("")
        addon:Print("ActionBarScanner result: " .. (hotkey and hotkey ~= "" and ("'" .. hotkey .. "'") or "(none)"))
    end
    
    addon:Print("=============================")
end

--------------------------------------------------------------------------------
-- Defensive System Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.DefensiveDiagnostics(addon)
    addon:Print("=== Defensive System Diagnostics ===")
    
    local profile = addon.db and addon.db.profile
    if not profile then
        addon:Print("|cffff0000ERROR: No profile loaded|r")
        return
    end
    
    local defSettings = profile.defensives or {}
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)

    addon:Print("Settings:")
    addon:Print("  Enabled: " .. (defSettings.enabled and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    addon:Print("  Display Mode: " .. (defSettings.displayMode or "healthBased"))
    addon:Print("  Position: " .. (defSettings.position or "LEFT"))

    addon:Print("")
    addon:Print("Defensive Icons:")
    local defensiveIcons = addon.defensiveIcons or (addon.defensiveIcon and {addon.defensiveIcon}) or {}
    if #defensiveIcons == 0 then
        addon:Print("  Frames: |cffff0000NOT CREATED|r")
    else
        for i, icon in ipairs(defensiveIcons) do
            addon:Print("  [Position " .. i .. "]")
            -- Visibility is Shown AND alpha > 0: icons are born Shown at alpha 0 and
            -- driven by alpha (combat-safe), so IsShown alone doesn't prove visible.
            local alphaPct = math.floor((icon:GetAlpha() or 0) * 100 + 0.5)
            addon:Print("    Visible: " .. (icon:IsShown() and "|cff00ff00shown|r" or "|cffff0000HIDDEN|r")
                .. " (alpha " .. alphaPct .. "%)")
            addon:Print("    CurrentID: " .. tostring(icon.currentID or "nil"))
            addon:Print("    SpellID: " .. tostring(icon.spellID or "nil"))
            addon:Print("    isItem: " .. tostring(icon.isItem or "nil"))

            if icon.cooldown then
                addon:Print("    Cooldown frame: |cff00ff00EXISTS|r")
                addon:Print("      CD Visible: " .. (icon.cooldown:IsShown() and "|cff00ff00YES|r" or "|cffff0000NO|r"))
                addon:Print("      DrawSwipe: " .. tostring(icon.cooldown:GetDrawSwipe()))
                addon:Print("      DrawEdge: " .. tostring(icon.cooldown:GetDrawEdge()))

                local cdStart, cdDuration = icon.cooldown:GetCooldownTimes()
                if cdStart and cdDuration and BlizzardAPI and (BlizzardAPI.IsSecretValue(cdStart) or BlizzardAPI.IsSecretValue(cdDuration)) then
                    -- In combat GetCooldownTimes() returns secret numbers; arithmetic would taint.
                    addon:Print("      CD Active: |cffff6600SECRET|r (combat)")
                elseif cdStart and cdDuration then
                    cdStart = cdStart / 1000  -- Convert from ms
                    cdDuration = cdDuration / 1000
                    if cdDuration > 0 then
                        local remaining = (cdStart + cdDuration) - GetTime()
                        addon:Print(string.format("      CD Active: |cff00ff00YES|r (%.1fs remaining)", remaining))
                    else
                        addon:Print("      CD Active: NO (duration=0)")
                    end
                else
                    addon:Print("      CD Active: NO (no times)")
                end
            else
                addon:Print("    Cooldown frame: |cffff0000MISSING|r")
            end
        end
    end

    addon:Print("")
    addon:Print("Health API:")
    if BlizzardAPI then
        local healthPct = BlizzardAPI.GetPlayerHealthPercent and BlizzardAPI.GetPlayerHealthPercent()
        if healthPct then
            if BlizzardAPI.IsSecretValue(healthPct) then
                addon:Print("  Current Health: |cffff6600SECRET|r")
            else
                addon:Print("  Current Health: " .. string.format("%.1f%%", healthPct))
            end
        else
            addon:Print("  Current Health: |cffff0000nil|r")
        end
    end

    local inCombat = UnitAffectingCombat("player")
    addon:Print("  In Combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))

    addon:Print("")
    addon:Print("Positioning (pixels):")
    local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
    if UIHealthBar then
        local barSpacing = UIHealthBar.BAR_SPACING or 3
        local barHeight = UIHealthBar.BAR_HEIGHT or 6
        local healthBarOffset = barHeight + (barSpacing * 2)
        addon:Print("  BAR_SPACING: " .. barSpacing)
        addon:Print("  BAR_HEIGHT: " .. barHeight)
        addon:Print("  Gap DPS->HealthBar: " .. barSpacing .. "px")
        addon:Print("  Gap HealthBar->Defensive: " .. (healthBarOffset - barSpacing - barHeight) .. "px")
        addon:Print("  (Should be equal: " .. barSpacing .. "px each)")
    end

    addon:Print("")
    addon:Print("Configured Spells:")
    local _, playerClass = UnitClass("player")
    local defensives = addon:GetClassSpellList("defensiveSpells") or {}
    local petHeals = addon:GetClassSpellList("petHealSpells") or {}
    local petRez = addon:GetClassSpellList("petRezSpells") or {}
    addon:Print("  Class: " .. (playerClass or "UNKNOWN"))
    addon:Print("  Defensives: " .. #defensives .. " spells")
    if #petRez > 0 then
        addon:Print("  Pet Rez/Summon: " .. #petRez .. " spells")
    end
    if #petHeals > 0 then
        addon:Print("  Pet Heals: " .. #petHeals .. " spells")
    end

    -- Pet status (reliable in combat: UnitExists/UnitIsDead are NOT secret)
    if BlizzardAPI and BlizzardAPI.GetPetStatus then
        local petStatus = BlizzardAPI.GetPetStatus()
        addon:Print("  Pet Status: " .. (petStatus or "N/A"))
        if petStatus == "alive" and BlizzardAPI.GetPetHealthPercent then
            local petHP = BlizzardAPI.GetPetHealthPercent()
            addon:Print("  Pet Health: " .. (petHP and string.format("%.0f%%", petHP) or "secret"))
        end
    end

    -- GetHaste(): verified SECRET in combat (2026-07-01) - not usable for live
    -- recharge/CD scaling; kept here as a probe in case a patch changes it.
    addon:Print("")
    addon:Print("Haste API:")
    if GetHaste then ---@diagnostic disable-line: undefined-global
        local haste = GetHaste() ---@diagnostic disable-line: undefined-global
        if BlizzardAPI and BlizzardAPI.IsSecretValue(haste) then
            addon:Print("  GetHaste(): |cffff6600SECRET|r")
        else
            addon:Print("  GetHaste(): " .. string.format("%.2f%%", haste))
        end
    else
        addon:Print("  GetHaste(): |cffff0000not available|r")
    end
    
    addon:Print("======================================")
end

--------------------------------------------------------------------------------
-- Cooldown API Testing (diagnose GCD vs spell cooldown issues)
--------------------------------------------------------------------------------
function DebugCommands.TestCooldownAPIs(addon, spellArg)
    local spellID = nil
    local spellName = nil
    local normalizedArg = type(spellArg) == "string" and spellArg:match("^%s*(.-)%s*$") or spellArg
    if normalizedArg == "" then normalizedArg = nil end

    if not normalizedArg then
        -- Context default: use AC next cast suggestion
        if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local ok, nextID = pcall(C_AssistedCombat.GetNextCastSpell)
            if ok and nextID and type(nextID) == "number" then
                spellID = nextID
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                spellName = (info and info.name) or ("ID:" .. spellID)
            end
        end
        if not spellID then
            addon:Print("Usage: /jac inspect cooldown [spell]")
            addon:Print("No active AC suggestion found. Specify a spell name to inspect.")
            return
        end
    else
        spellName = normalizedArg

        -- Spellbook search is more accurate than brute-force ID iteration
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            -- Iterate through player's spellbook slots
            for i = 1, 1000 do
                local spellInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
                if not spellInfo then
                    break -- End of spellbook
                end
                if spellInfo.name and spellInfo.name:lower() == spellName:lower() then
                    spellID = spellInfo.spellID
                    break
                end
            end
        end

        -- Fallback: brute-force ID search
        if not spellID and C_Spell and C_Spell.GetSpellInfo then
            for i = 1, 500000 do
                local spellInfo = C_Spell.GetSpellInfo(i)
                if spellInfo and spellInfo.name and spellInfo.name:lower() == spellName:lower() then
                    spellID = i
                    break
                end
            end
        end

        if not spellID then
            addon:Print("|cffff0000Spell not found:|r " .. spellName)
            addon:Print("Tip: Make sure the spell is in your spellbook or try the exact spell name")
            return
        end
    end

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)

    -- Secret values can't be used in string operations
    local function SafeFormat(value, isSecret)
        if isSecret then
            return "SECRET"
        elseif value == nil then
            return "nil"
        else
            -- Use pcall to safely convert to string
            local ok, result = pcall(tostring, value)
            return ok and result or "ERROR"
        end
    end

    addon:Print("=== Cooldown API Test: " .. spellName .. " (ID: " .. spellID .. ") ===")
    addon:Print("")

    addon:Print("1. C_SpellBook.GetSpellCooldown:")
    if C_SpellBook and C_SpellBook.GetSpellCooldown then
        local ok, cd = pcall(C_SpellBook.GetSpellCooldown, spellID)
        if ok and cd then
            local startSecret = BlizzardAPI.IsSecretValue(cd.startTime)
            local durSecret = BlizzardAPI.IsSecretValue(cd.duration)

            addon:Print("   startTime: " .. SafeFormat(cd.startTime, startSecret) ..
                (startSecret and " |cffff6600(SECRET)|r" or ""))
            addon:Print("   duration: " .. SafeFormat(cd.duration, durSecret) ..
                (durSecret and " |cffff6600(SECRET)|r" or ""))

            if not startSecret and not durSecret and cd.startTime and cd.duration and cd.duration > 0 then
                local remaining = (cd.startTime + cd.duration) - GetTime()
                addon:Print(string.format("   remaining: %.2fs", remaining))
            end
        else
            addon:Print("   |cffff0000ERROR or nil|r")
        end
    else
        addon:Print("   |cffff0000API not available|r")
    end

    addon:Print("")

    addon:Print("2. BlizzardAPI.GetSpellCooldown (C_Spell):")
    if BlizzardAPI and BlizzardAPI.GetSpellCooldown then
        local start, dur = BlizzardAPI.GetSpellCooldown(spellID)
        local startSecret = BlizzardAPI.IsSecretValue(start)
        local durSecret = BlizzardAPI.IsSecretValue(dur)

        addon:Print("   start: " .. SafeFormat(start, startSecret) ..
            (startSecret and " |cffff6600(SECRET)|r" or ""))
        addon:Print("   duration: " .. SafeFormat(dur, durSecret) ..
            (durSecret and " |cffff6600(SECRET)|r" or ""))

        if not startSecret and not durSecret and start and dur and dur > 0 then
            local remaining = (start + dur) - GetTime()
            addon:Print(string.format("   remaining: %.2fs", remaining))
        end
    else
        addon:Print("   |cffff0000API not available|r")
    end

    addon:Print("")

    addon:Print("3. Action Bar Cooldown:")
    if ActionBarScanner and ActionBarScanner.GetSlotForSpell then
        local slot = ActionBarScanner.GetSlotForSpell(spellID)
        if slot then
            local direct = ActionBarScanner.GetDirectSlotForSpell
                and ActionBarScanner.GetDirectSlotForSpell(spellID)
            local actionType = GetActionInfo and GetActionInfo(slot) or "?"
            addon:Print("   Slot: " .. slot .. " (" .. tostring(actionType) .. ")  Direct: "
                .. (direct and "|cff00ff00YES|r (slot drives swipe+GCD)"
                    or "|cffff6600NO|r (macro/unbound: swipe from local numbers, GCD via fallback)"))
            if ActionBarScanner.GetActionBarCooldown then
                local start, dur = ActionBarScanner.GetActionBarCooldown(spellID)
                local startSecret = BlizzardAPI.IsSecretValue(start)
                local durSecret = BlizzardAPI.IsSecretValue(dur)

                addon:Print("   start: " .. SafeFormat(start, startSecret) ..
                    (startSecret and " |cffff6600(SECRET)|r" or ""))
                addon:Print("   duration: " .. SafeFormat(dur, durSecret) ..
                    (durSecret and " |cffff6600(SECRET)|r" or ""))

                if not startSecret and not durSecret and start and dur and dur > 0 then
                    local remaining = (start + dur) - GetTime()
                    addon:Print(string.format("   remaining: %.2fs", remaining))
                end
            end
        else
            addon:Print("   |cff888888Not on action bar|r")
        end
    else
        addon:Print("   |cffff0000ActionBarScanner not available|r")
    end

    addon:Print("")

    addon:Print("4. GCD (dummy spell 61304):")
    if BlizzardAPI and BlizzardAPI.GetGCDInfo then
        local gcdStart, gcdDur = BlizzardAPI.GetGCDInfo()
        local startSecret = BlizzardAPI.IsSecretValue(gcdStart)
        local durSecret = BlizzardAPI.IsSecretValue(gcdDur)

        addon:Print("   start: " .. SafeFormat(gcdStart, startSecret) ..
            (startSecret and " |cffff6600(SECRET)|r" or ""))
        addon:Print("   duration: " .. SafeFormat(gcdDur, durSecret) ..
            (durSecret and " |cffff6600(SECRET)|r" or ""))

        if not startSecret and not durSecret and gcdStart and gcdDur and gcdDur > 0 then
            local remaining = (gcdStart + gcdDur) - GetTime()
            addon:Print(string.format("   remaining: %.2fs", remaining))
        end
    else
        addon:Print("   |cffff0000API not available|r")
    end

    addon:Print("")

    addon:Print("5. C_Spell.GetSpellCooldown (raw isOnGCD + local CD tracking):")
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and cd then
            local isOnGCDSecret = BlizzardAPI.IsSecretValue(cd.isOnGCD)
            local durSecret = BlizzardAPI.IsSecretValue(cd.duration)
            local startSecret = BlizzardAPI.IsSecretValue(cd.startTime)

            local isOnGCDStr
            if isOnGCDSecret then
                isOnGCDStr = "SECRET"
            elseif cd.isOnGCD == nil then
                isOnGCDStr = "nil (ambiguous - off CD OR unflagged CD running)"
            elseif cd.isOnGCD == true then
                isOnGCDStr = "true (GCD only - spell ready once GCD clears)"
            elseif cd.isOnGCD == false then
                isOnGCDStr = "false (real CD running - Blizzard-flagged spell)"
            else
                isOnGCDStr = tostring(cd.isOnGCD)
            end
            addon:Print("   isOnGCD: " .. isOnGCDStr)
            addon:Print("   duration: " .. SafeFormat(cd.duration, durSecret) ..
                (durSecret and " |cffff6600(SECRET)|r" or ""))
            addon:Print("   startTime: " .. SafeFormat(cd.startTime, startSecret) ..
                (startSecret and " |cffff6600(SECRET)|r" or ""))
        else
            addon:Print("   |cffff0000pcall failed or nil|r")
        end
    else
        addon:Print("   |cffff0000C_Spell.GetSpellCooldown not available|r")
    end

    addon:Print("")
    addon:Print("6. Local CD tracking (JustAC in-combat timer):")
    if BlizzardAPI and BlizzardAPI.IsSpellOnLocalCooldown then
        local localCD = BlizzardAPI.IsSpellOnLocalCooldown(spellID)
        addon:Print("   IsSpellOnLocalCooldown: " .. (localCD and "|cffff6600true (CD active)|r" or "|cff00ff00false (no local CD)|r"))
    else
        addon:Print("   |cffff0000BlizzardAPI.IsSpellOnLocalCooldown not available|r")
    end
    if BlizzardAPI and BlizzardAPI.IsSpellReady then
        local ready = BlizzardAPI.IsSpellReady(spellID)
        addon:Print("   IsSpellReady: " .. (ready and "|cff00ff00true (ready)|r" or "|cffff6600false (on CD)|r"))
    end
    if BlizzardAPI and BlizzardAPI.DebugTrackingState then
        local cat, maxCh, curCh, localCD = BlizzardAPI.DebugTrackingState(spellID)
        addon:Print("   Tracked: " .. (cat and ("|cff00ff00" .. tostring(cat) .. "|r") or "|cffff0000NO (not registered)|r"))
        if maxCh then
            addon:Print("   Charge cache: maxCharges=" .. tostring(maxCh) ..
                (curCh and (", current=" .. tostring(curCh)) or "") .. ", localCD=" .. tostring(localCD))
        else
            addon:Print("   Charge cache: |cffff6600none|r, localCD=" .. tostring(localCD))
        end
        local displayID = BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(spellID)
        if displayID and displayID ~= spellID then
            local dcat = BlizzardAPI.DebugTrackingState(displayID)
            addon:Print("   (display ID " .. tostring(displayID) .. " tracked: " ..
                (dcat and ("|cff00ff00" .. tostring(dcat) .. "|r") or "|cffff0000NO|r") .. ")")
        end
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if SpellDB and SpellDB.IsInterruptOnCooldown then
        local intCD = SpellDB.IsInterruptOnCooldown(spellID)
        addon:Print("   IsInterruptOnCooldown: " .. (intCD and "|cffff6600true (blocked)|r" or "|cff00ff00false (usable)|r"))
    end

    addon:Print("")
    addon:Print("Cast the spell and run this command again to see cooldown behavior!")
    addon:Print("===========================================")
end

--------------------------------------------------------------------------------
-- Interrupt Queue Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.InterruptDiagnostics(addon)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)

    addon:Print("=== Interrupt Queue Diagnostics ===")

    local resolvedInts = addon and addon.resolvedInterrupts
    if not resolvedInts or #resolvedInts == 0 then
        addon:Print("|cffff6600No resolved interrupt spells. Try /reload or check spec.|r")
        return
    end

    addon:Print("Resolved interrupt/CC list (" .. #resolvedInts .. " entries):")
    for i, entry in ipairs(resolvedInts) do
        local sid, stype = entry.spellID, entry.type
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
        local name = (spellInfo and spellInfo.name) or "?"

        local localCD = BlizzardAPI and BlizzardAPI.IsSpellOnLocalCooldown and BlizzardAPI.IsSpellOnLocalCooldown(sid)
        local ready = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(sid)
        local intCD = SpellDB and SpellDB.IsInterruptOnCooldown and SpellDB.IsInterruptOnCooldown(sid)
        local usable = BlizzardAPI and BlizzardAPI.IsSpellUsable and BlizzardAPI.IsSpellUsable(sid, stype ~= "cc")

        local isOnGCD = nil
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, cd = pcall(C_Spell.GetSpellCooldown, sid)
            if ok and cd then isOnGCD = cd.isOnGCD end
        end

        local isOnGCDStr = "nil"
        if BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(isOnGCD) then
            isOnGCDStr = "SECRET"
        elseif isOnGCD == true then
            isOnGCDStr = "|cffffff00true|r"
        elseif isOnGCD == false then
            isOnGCDStr = "|cffff6600false|r"
        end

        local cdColor = intCD and "|cffff6600" or "|cff00ff00"
        local cdStr = intCD and "ON_CD" or "ready"
        addon:Print(string.format("  %d. %s (%d) [%s]  %sIsIntOnCD=%s|r  localCD=%s  IsReady=%s  usable=%s  isOnGCD=%s",
            i, name, sid, stype,
            cdColor, cdStr,
            tostring(localCD), tostring(ready), tostring(usable), isOnGCDStr))
    end

    addon:Print("")
    addon:Print("Target interrupt-worthy: " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetInterruptWorthy and BlizzardAPI.IsTargetInterruptWorthy()))
    addon:Print("Target CC-immune: " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetCCImmune and BlizzardAPI.IsTargetCCImmune()))
    local interruptMode = addon.db and addon.db.profile and (addon.db.profile.interruptMode or "kickPrefer") or "n/a"
    addon:Print("Interrupt mode: " .. interruptMode)
    addon:Print("===================================")
end

--------------------------------------------------------------------------------
-- Aura Cache Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.AuraDiagnostics(addon)
    addon:Print("=== Aura Cache Diagnostics ===")

    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    if not RedundancyFilter then
        addon:Print("|cffff0000RedundancyFilter not loaded|r")
        return
    end

    local auras = nil
    if RedundancyFilter.GetAuraCache then
        auras = RedundancyFilter.GetAuraCache()
    end

    if not auras then
        addon:Print("|cffff0000Could not access aura cache|r")
        return
    end

    local function countTable(t)
        if not t then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    local inCombat = UnitAffectingCombat("player")
    addon:Print("")
    addon:Print("Aura Cache Status:")
    addon:Print("  In Combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))
    addon:Print("  hasSecrets: " .. tostring(auras.hasSecrets or false))
    addon:Print("  byID entries: " .. countTable(auras.byID))
    addon:Print("  byName entries: " .. countTable(auras.byName))

    addon:Print("")
    addon:Print("Cached auras by ID (first 20):")
    if auras.byID then
        local shown = 0
        local total = countTable(auras.byID)
        for spellID in pairs(auras.byID) do
            if shown < 20 then
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                local name = (spellInfo and spellInfo.name) or "?"
                addon:Print("  " .. tostring(spellID) .. " (" .. name .. ")")
                shown = shown + 1
            end
        end
        if total > 20 then
            addon:Print("  ... (" .. (total - 20) .. " more)")
        end
    else
        addon:Print("  (empty)")
    end

    addon:Print("")
    addon:Print("All player buffs (first 20):")
    local count = 0
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            count = count + 1
            if count <= 20 then
                local spellId = auraData.spellId or "?"
                local name = auraData.name or "SECRET"
                addon:Print("  [" .. i .. "] ID:" .. tostring(spellId) .. " Name:" .. tostring(name))
            end
        end
    else
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
            if not name and not spellId then break end
            count = count + 1
            if count <= 20 then
                addon:Print("  [" .. i .. "] ID:" .. tostring(spellId or "?") .. " Name:" .. tostring(name or "SECRET"))
            end
        end
    end
    addon:Print("  Total buffs: " .. count)

    addon:Print("==============================")
end

--------------------------------------------------------------------------------
-- Burst Injection Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.BurstDiagnostics(addon)
    addon:Print("=== Burst Injection Diagnostics ===")

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local BurstInjectionEngine = LibStub("JustAC-BurstInjectionEngine", true)

    if not BurstInjectionEngine then
        addon:Print("|cffff0000BurstInjectionEngine not loaded|r")
        return
    end

    local specKey = BurstInjectionEngine.GetBurstSpecKey()
    addon:Print("Spec key: " .. (specKey or "|cffff0000unknown|r"))

    local profile = addon and addon.db and addon.db.profile
    local bi = profile and profile.burstInjection
    local enabled = bi and bi.enabled or false
    addon:Print("Enabled: " .. (enabled and "|cff00ff00YES|r" or "|cff888888NO|r"))

    addon:Print("Trigger source: " .. (bi and bi.triggerSpells and specKey
        and bi.triggerSpells[specKey] and #bi.triggerSpells[specKey] > 0
        and "|cffadd8e6Custom overrides|r" or "|cff888888SpellDB defaults|r"))

    -- Aura-based window status
    local burstActive = BurstInjectionEngine.IsBurstActive and BurstInjectionEngine.IsBurstActive(addon)
    addon:Print("Burst window: " .. (burstActive and "|cffb048f8ACTIVE (trigger aura detected)|r" or "|cff888888inactive|r"))

    -- ── Injection priority list ──
    addon:Print("")
    addon:Print("Injection Priority List (first usable wins):")
    local injectionSpells = bi and bi.injectionSpells and specKey and bi.injectionSpells[specKey]
    local defaults = SpellDB and SpellDB.CLASS_BURST_INJECTION_DEFAULTS and specKey
        and SpellDB.CLASS_BURST_INJECTION_DEFAULTS[specKey]
    local spellList = injectionSpells and #injectionSpells > 0 and injectionSpells or defaults
    local isCustom = injectionSpells and #injectionSpells > 0
    addon:Print("  Source: " .. (isCustom and "|cffadd8e6Custom (profile)|r" or "|cff888888SpellDB defaults|r"))

    if spellList and #spellList > 0 then
        for i, spellID in ipairs(spellList) do
            local name = "?"
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then name = spellInfo.name end

            local resolvedID = BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(spellID) or spellID
            local resolvedTag = (resolvedID ~= spellID) and (" -> " .. resolvedID) or ""

            local known = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(resolvedID)
            local knownTag = known and "|cff00ff00known|r" or "|cffff6666not known|r"

            local ready = known and BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(resolvedID)
            local readyTag = ""
            if known then
                readyTag = ready and " |cff00ff00READY|r" or " |cffff6600on CD|r"
            end

            addon:Print("  " .. i .. ". " .. name .. " (" .. spellID .. resolvedTag .. ") " .. knownTag .. readyTag)
        end
    else
        addon:Print("  |cff888888(none configured)|r")
    end

    -- ── Explicit trigger overrides ──
    addon:Print("")
    local triggerSpells = bi and bi.triggerSpells and specKey and bi.triggerSpells[specKey]
    if triggerSpells and #triggerSpells > 0 then
        addon:Print("Explicit Trigger Spells (override):")
        for i, spellID in ipairs(triggerSpells) do
            local name = "?"
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then name = spellInfo.name end
            addon:Print("  " .. i .. ". " .. name .. " (" .. spellID .. ")")
        end
    end

    -- ── Active trigger spells ──
    addon:Print("")
    addon:Print("Active Burst Triggers:")
    local detected = BurstInjectionEngine.GetDetectedTriggers(addon)
    if detected and #detected > 0 then
        for i, entry in ipairs(detected) do
            local cdTag = entry.baseCd > 0 and (" - " .. entry.baseCd .. "s CD") or ""
            addon:Print("  " .. i .. ". " .. entry.name .. " (" .. entry.spellID .. ")" .. cdTag)
        end
    else
        addon:Print("  |cff888888(none - no triggers defined for this spec)|r")
    end

    -- ── SpellDB trigger defaults for reference ──
    if SpellDB and SpellDB.CLASS_BURST_TRIGGER_DEFAULTS and specKey then
        local rawDefaults = SpellDB.CLASS_BURST_TRIGGER_DEFAULTS[specKey]
        if rawDefaults and #rawDefaults > 0 then
            addon:Print("")
            addon:Print("SpellDB Trigger Defaults (" .. specKey .. "):")
            for i, spellID in ipairs(rawDefaults) do
                local name = "?"
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                if spellInfo and spellInfo.name then name = spellInfo.name end
                local known = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(spellID)
                local knownTag = known and "|cff00ff00known|r" or "|cffff6666not known|r"
                addon:Print("  " .. i .. ". " .. name .. " (" .. spellID .. ") " .. knownTag)
            end
        end
    end

    addon:Print("==================================")
end

--------------------------------------------------------------------------------
-- Pre-combat buff checklist diagnostics
--------------------------------------------------------------------------------
function DebugCommands.PrecombatBuffDiagnostics(addon)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local Engine  = LibStub("JustAC-PrecombatEngine", true)
    addon:Print("===== Pre-combat Buffs =====")
    if not SpellDB or not SpellDB.GetPrecombatBuffCategories or not Engine then
        addon:Print("|cffff6666PrecombatEngine / data not loaded.|r")
        return
    end
    if InCombatLockdown() then
        addon:Print("|cffffff00In combat - detection is out-of-combat only. Re-run after combat.|r")
        return
    end

    for _, cat in ipairs(SpellDB.GetPrecombatBuffCategories()) do
        local items = SpellDB.GetPrecombatBuffItems(cat) or {}
        local satisfied = Engine.IsCategorySatisfied(cat)
        local best = SpellDB.GetBestOwnedBuff(cat)
        local bestName = best and ((GetItemInfo(best.id)) or ("item " .. best.id))
        local statTag = best and best.stat and (" |cff888888[" .. best.stat .. "]|r") or ""
        local state = satisfied and "|cff00ff00active|r"
            or (best and "|cffff6666MISSING|r" or "|cff888888missing, none owned|r")
        addon:Print(string.format("%s (%d known): %s%s%s", cat, #items, state,
            bestName and ("  best owned: " .. bestName) or "", statTag))
    end

    local missing = Engine.GetMissingBuffs()
    addon:Print("---- would surface ----")
    if #missing == 0 then
        addon:Print("|cff00ff00Nothing missing (or nothing owned to fix it).|r")
    else
        for _, m in ipairs(missing) do
            local nm = (GetItemInfo(m.entry.id)) or ("item " .. m.entry.id)
            addon:Print("  " .. m.category .. " -> " .. nm)
        end
    end

    -- Recuperate gate-by-gate probe (health-conditioned class buff)
    addon:Print("---- Recuperate ----")
    if not SpellDB.RECUPERATE then
        addon:Print("|cffff6666SpellDB.RECUPERATE not defined (old data?).|r")
    else
        local sid = SpellDB.RECUPERATE
        local known = IsPlayerSpell(sid)
        local knownAlt = (IsSpellKnown and IsSpellKnown(sid)) or false
        local restricted = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
        local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        local hotUp = get and get(SpellDB.RECUPERATE_AURA) ~= nil
        local activeUp = get and get(sid) ~= nil
        local BAPI = LibStub("JustAC-BlizzardAPI", true)
        local pct = BAPI and BAPI.GetPlayerHealthPercent and BAPI.GetPlayerHealthPercent()
        local safePct, estimated
        if BAPI and BAPI.GetPlayerHealthPercentSafe then
            safePct, estimated = BAPI.GetPlayerHealthPercentSafe()
        end
        local hasRestrictions = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
        addon:Print("  known: IsPlayerSpell=" .. tostring(known) .. " IsSpellKnown=" .. tostring(knownAlt))
        addon:Print("  aura restricted: " .. tostring(restricted or false)
            .. "  secret restrictions: " .. tostring(hasRestrictions or false))
        addon:Print("  HoT (" .. tostring(SpellDB.RECUPERATE_AURA) .. ") up: " .. tostring(hotUp)
            .. "  active aura (" .. sid .. ") up: " .. tostring(activeUp))
        local activity = BAPI and BAPI.HasRecentPlayerHealthActivity and BAPI.HasRecentPlayerHealthActivity()
        local sustained = BAPI and BAPI.HasSustainedPlayerHealthActivity and BAPI.HasSustainedPlayerHealthActivity()
        addon:Print("  health exact: " .. (pct and string.format("%.1f%%", pct) or "|cffff6666unreadable|r")
            .. "  safe: " .. (safePct and string.format("%.1f%%", safePct) or "nil")
            .. (estimated and " |cffffff00(vignette estimate)|r" or "")
            .. " (offer below 90%)" .. (dead and "  |cffff6666DEAD/GHOST|r" or ""))
        addon:Print("  health event activity: recent=" .. tostring(activity or false)
            .. " sustained=" .. tostring(sustained or false) .. " (sustained drives the offer)")
        -- Fill-width probe: Blizzard's player frame sets its health fill from the
        -- secret value engine-side. If the fill texture's LAID-OUT width reads as a
        -- plain number, width/barWidth = exact health fraction even where UnitHealth
        -- is secret - that would replace the activity heuristic outright.
        local function FillRatio()
            local hb = PlayerFrame and PlayerFrame.PlayerFrameContent
                and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
                and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            hb = hb or (PlayerFrame and PlayerFrame.healthbar)
            if not hb then return "|cff888888no healthbar frame found|r" end
            local ok, ratio = pcall(function()
                local tex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
                local w = tex and tex:GetWidth()
                local full = hb:GetWidth()
                if w and full and full > 0 then return (w / full) * 100 end
                return nil
            end)
            if not ok then return "|cffff6666SEALED (read threw - idea dead)|r" end
            if not ratio then return "|cff888888no width available|r" end
            return string.format("|cff00ff00%.1f%% (READABLE - compare to your real health!)|r", ratio)
        end
        addon:Print("  health-bar fill-width probe: " .. FillRatio())
        local surfaced = false
        for _, s in ipairs(Engine.GetMissingClassBuffs() or {}) do
            if s == sid then surfaced = true break end
        end
        addon:Print("  would surface: " .. (surfaced and "|cff00ff00YES|r" or "|cffff6666NO|r"))
    end
    addon:Print("============================")
end

--------------------------------------------------------------------------------
-- Fixed-Queue Context Rank Diagnostics
--------------------------------------------------------------------------------
-- Dumps the inferred combat context (from the AC pick, post execute-latch and
-- sticky-multi smoothing) and each queue spell's profile-distance rank. Every
-- value shown is non-secret by construction, so this is safe to run in combat.
function DebugCommands.ContextRankDiagnostics(addon)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not SpellQueue or not SpellQueue.DebugContextState then
        addon:Print("|cffff0000SpellQueue not loaded|r")
        return
    end

    local function spellName(id)
        if id < 0 then
            local name = GetItemInfo and GetItemInfo(-id)
            return name or ("item " .. -id)
        end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name) or "?"
    end

    local ctx = SpellQueue.DebugContextState()
    addon:Print("=== Fixed-Queue Context Rank ===")
    if ctx.pickID then
        addon:Print("AC pick: " .. spellName(ctx.pickID) .. " (" .. ctx.pickID .. ")")
    else
        addon:Print("AC pick: |cff888888none|r")
    end
    addon:Print(string.format("Context: arch=%s range=%s role=%s%s",
        tostring(ctx.arch), tostring(ctx.range), tostring(ctx.role),
        ctx.stickyApplied and " |cffadd8e6(sticky multi)|r" or ""))
    addon:Print(string.format("Execute: %s%s  OutOfMelee: %s",
        tostring(ctx.execute),
        ctx.executeLatched and " |cffadd8e6(latched)|r" or "",
        tostring(ctx.outOfMelee)))

    local profile = addon.db and addon.db.profile
    if profile and profile.orderContextAware == false then
        addon:Print("|cffffff00Context-aware ordering is OFF - ranks below are not applied.|r")
    end

    addon:Print("")
    addon:Print("Queue (rank 0 = best match ... 9 = uncastable sink; the AC slot is never reordered):")
    local queue = SpellQueue.GetCurrentSpellQueue()
    if not queue or #queue == 0 then
        addon:Print("  |cff888888(empty)|r")
        addon:Print("================================")
        return
    end
    for i, sid in ipairs(queue) do
        if sid > 0 then
            local arch = SpellDB and SpellDB.GetArch and SpellDB.GetArch(sid)
            local range = SpellDB and SpellDB.GetRange and SpellDB.GetRange(sid)
            local role = SpellDB and SpellDB.GetRole and SpellDB.GetRole(sid)
            local gate = SpellDB and SpellDB.GetGate and SpellDB.GetGate(sid)
            local rankTag = (i == 1) and "|cff888888AC slot|r"
                or ("rank=" .. tostring(SpellQueue.DebugRankSpell and SpellQueue.DebugRankSpell(sid)))
            addon:Print(string.format("  %d. %s (%d)  arch=%s range=%s role=%s gate=%s  %s",
                i, spellName(sid), sid, tostring(arch), tostring(range), tostring(role), tostring(gate), rankTag))
        else
            addon:Print(string.format("  %d. %s (item)  rank=1 (neutral)", i, spellName(sid)))
        end
    end
    addon:Print("================================")
end

--------------------------------------------------------------------------------
-- Performance Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.PerformanceDiagnostics(addon, subCommand)
    local SpellQueue    = LibStub("JustAC-SpellQueue", true)
    local DefEngine     = LibStub("JustAC-DefensiveEngine", true)
    local now = GetTime()

    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.debugMode then
        addon:Print("|cffffff00Enable debug mode first: /jac debug|r")
        return
    end

    local normalizedSub = nil
    if type(subCommand) == "string" then
        normalizedSub = subCommand:match("^%s*(.-)%s*$")
        if normalizedSub == "" then normalizedSub = nil end
        if normalizedSub then normalizedSub = normalizedSub:lower() end
    end

    if normalizedSub and normalizedSub ~= "reset" then
        addon:Print("|cffffff00Unknown subcommand:|r " .. normalizedSub)
        addon:Print("Usage: /jac inspect perf [reset]")
        return
    end

    if normalizedSub == "reset" then
        if SpellQueue and SpellQueue.ResetBuildStats then SpellQueue.ResetBuildStats() end
        if DefEngine and DefEngine.ResetBuildStats then DefEngine.ResetBuildStats() end
        if addon and addon.ResetOOCEventCoalesceStats then addon:ResetOOCEventCoalesceStats() end
        addon:Print("|cff00ff00Build counters reset.|r")
        return
    end

    addon:Print("=== JustAC Queue Build Statistics ===")

    local sqStats = SpellQueue and SpellQueue.GetBuildStats and SpellQueue.GetBuildStats()
    if sqStats then
        local elapsed = sqStats.resetTime > 0 and (now - sqStats.resetTime) or now
        local rate = elapsed > 0 and (sqStats.buildCount / elapsed) or 0
        addon:Print(string.format("Offensive queue builds: |cffadd8e6%d|r (|cffadd8e6%.1f/s|r over %.0fs)",
            sqStats.buildCount, rate, elapsed))
    else
        addon:Print("  SpellQueue stats: |cffff0000not available|r")
    end

    local defStats = DefEngine and DefEngine.GetBuildStats and DefEngine.GetBuildStats()
    if defStats then
        local elapsed = defStats.resetTime > 0 and (now - defStats.resetTime) or now
        local rate = elapsed > 0 and (defStats.buildCount / elapsed) or 0
        addon:Print(string.format("Defensive queue builds: |cffadd8e6%d|r (|cffadd8e6%.1f/s|r over %.0fs)",
            defStats.buildCount, rate, elapsed))
    else
        addon:Print("  DefensiveEngine stats: |cffff0000not available|r")
    end

    local inCombat = UnitAffectingCombat("player")
    addon:Print("In combat: " .. (inCombat and "|cffff6600YES|r" or "NO"))

    local coalesceStats = addon and addon.GetOOCEventCoalesceStats and addon:GetOOCEventCoalesceStats()
    if coalesceStats then
        local function printCoalesceLine(label, bucket)
            local applied = (bucket and bucket.applied) or 0
            local coalesced = (bucket and bucket.coalesced) or 0
            local total = applied + coalesced
            local coalescePct = total > 0 and (coalesced * 100 / total) or 0
            local throttle = (bucket and bucket.throttle) or 0
            addon:Print(string.format("OOC %s events: applied |cffadd8e6%d|r, coalesced |cffadd8e6%d|r (%.0f%%, throttle %.2fs)",
                label, applied, coalesced, coalescePct, throttle))
        end
        printCoalesceLine("cooldown", coalesceStats.cooldown)
        printCoalesceLine("usability", coalesceStats.usability)
        printCoalesceLine("actionbar", coalesceStats.actionbar)
    end

    if profile then
        local updateCVar = GetCVar and GetCVar("assistedCombatIconUpdateRate")
        if updateCVar then
            addon:Print("Update CVar (assistedCombatIconUpdateRate): |cffffff00" .. updateCVar .. "s|r")
        end
        local maxIcons = profile.maxIcons or 4
        addon:Print("Max icons (offensive): " .. maxIcons)
        local defEnabled = profile.defensives and profile.defensives.enabled
        addon:Print("Defensives enabled: " .. (defEnabled and "|cff00ff00YES|r" or "NO"))
    end

    addon:Print("|cff888888Use '/jac inspect perf reset' to reset counters.|r")
    addon:Print("======================================")
end

--------------------------------------------------------------------------------
-- Charge API Diagnostics (SPELL_UPDATE_CHARGES / GetSpellCharges secrecy probe)
--------------------------------------------------------------------------------
-- Settles whether a charge-refund correction is buildable in combat:
--   Q1: does SPELL_UPDATE_CHARGES fire in combat, and is its payload readable?
--   Q2: which C_Spell.GetSpellCharges fields are non-secret in combat?
--   Q3: does any readable field cleanly distinguish "recharging" from "charges
--       full"? (recharge inactive ⟺ full would give a definitive refund fix)
-- Arm, enter combat, spend a charge, let it recharge. Auto-disarms after 60s
-- or 12 logged events.
function DebugCommands.ChargeDiagnostics(addon, spellArg)
    if DebugCommands._chargeDiag then
        addon:Print("|cffffff00chargediag already armed (/reload to cancel).|r")
        return
    end
    if not (C_Spell and C_Spell.GetSpellCharges) then
        addon:Print("|cffff0000C_Spell.GetSpellCharges not available|r")
        return
    end

    -- Print-safe conversion; "<secret>" for secret values. Event args and struct
    -- fields can be secret in ways IsSecretValue misses, so force the value
    -- through compare+concat and catch the throw (same approach as castdiag).
    local function safe(v)
        if v == nil then return "nil" end
        local ok, s = pcall(function()
            local str = tostring(v)
            local _ = (str == "")
            return str .. ""
        end)
        if ok and type(s) == "string" then return s end
        return "<secret>"
    end

    -- Resolve probe spells: named arg, else every charge spell in the spellbook.
    local probeSpells = {}
    local normalizedArg = type(spellArg) == "string" and spellArg:match("^%s*(.-)%s*$") or nil
    if normalizedArg == "" then normalizedArg = nil end
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local lowerArg = normalizedArg and normalizedArg:lower()
        for i = 1, 1000 do
            local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
            if not info then break end
            if info.spellID and info.name then
                if lowerArg then
                    if info.name:lower() == lowerArg then
                        probeSpells[1] = info.spellID
                        break
                    end
                else
                    local ok, ci = pcall(C_Spell.GetSpellCharges, info.spellID)
                    if ok and ci then
                        -- maxCharges is NeverSecret; arithmetic throws if that changes
                        local okMax, isMulti = pcall(function() return ci.maxCharges > 1 end)
                        if okMax and isMulti and #probeSpells < 4 then
                            probeSpells[#probeSpells + 1] = info.spellID
                        end
                    end
                end
            end
        end
    end
    if #probeSpells == 0 then
        if normalizedArg then
            addon:Print("|cffff0000Spell not found in spellbook:|r " .. normalizedArg)
        else
            addon:Print("|cffff6600No charge spells found in spellbook. Name one: /jac inspect chargediag <spell>|r")
        end
        return
    end

    local function dumpCharges(label, spellID)
        local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local name = (info and info.name) or "?"
        local ok, ci = pcall(C_Spell.GetSpellCharges, spellID)
        if not ok or not ci then
            addon:Print(string.format("  [%s] %s (%d): GetSpellCharges -> nil", label, name, spellID))
            return
        end
        local parts = {}
        for k, v in pairs(ci) do
            parts[#parts + 1] = tostring(k) .. "=" .. safe(v)
        end
        table.sort(parts)
        addon:Print(string.format("  [%s] %s (%d): %s", label, name, spellID, table.concat(parts, "  ")))
    end

    local f = CreateFrame("Frame")
    DebugCommands._chargeDiag = f
    local armT = GetTime()
    local fires = 0
    local MAX_FIRES = 12
    local probeSet = {}
    for _, sid in ipairs(probeSpells) do probeSet[sid] = true end

    local function disarm(msg)
        f:UnregisterAllEvents(); f:SetScript("OnEvent", nil); f:SetScript("OnUpdate", nil)
        DebugCommands._chargeDiag = nil
        addon:Print(msg)
    end

    addon:Print("|cff00ff00=== chargediag ARMED (60s) ===|r monitoring " .. #probeSpells .. " charge spell(s):")
    for _, sid in ipairs(probeSpells) do dumpCharges("baseline", sid) end
    addon:Print("  In combat: spend a charge, then let it recharge. Watching SPELL_UPDATE_CHARGES.")

    f:RegisterEvent("SPELL_UPDATE_CHARGES")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "SPELL_UPDATE_COOLDOWN" then
            -- Fallback trigger question only; this event is spammy, so log it
            -- solely when the payload names a probe spell. pcall: payload may be
            -- secret, and indexing with a secret key throws.
            local ok, isProbe = pcall(function() return probeSet[arg1] == true end)
            if not (ok and isProbe) then return end
        end
        fires = fires + 1
        addon:Print(string.format("|cffadd8e6[%+.2fs]|r %s payload=%s inCombat=%s",
            GetTime() - armT, event, safe(arg1), tostring(UnitAffectingCombat("player"))))
        for _, sid in ipairs(probeSpells) do dumpCharges("now", sid) end
        if fires >= MAX_FIRES then
            disarm("|cffffff00chargediag: max events logged - disarmed. Re-arm to continue.|r")
        end
    end)
    f:SetScript("OnUpdate", function()
        if GetTime() - armT > 60 then
            disarm("|cffffff00chargediag: 60s window ended - disarmed.|r")
        end
    end)
end

--------------------------------------------------------------------------------
-- Cast Interruptibility Diagnostics
--------------------------------------------------------------------------------
-- One-shot cast-interruptibility diagnostic. Settles two assumptions the interrupt
-- tracker is built on: (Q1) do INTERRUPTIBLE/NOT_INTERRUPTIBLE events fire at cast
-- START, or only on a mid-cast transition? (Q2) does an addon-created CastingBar
-- resolve the secret notInterruptible? Arm it, then target a caster - ideally one whose
-- cast is non-interruptible from the start (the hard case).
function DebugCommands.CastDiagnostics(addon)
    if DebugCommands._castDiag then
        addon:Print("|cffffff00castdiag already armed - target a caster (or /reload to cancel).|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._castDiag = f
    local armT = GetTime()
    local log, started, startedT, probed = {}, false, 0, false
    local castSpellID, probeLines = nil, {}

    addon:Print("|cff00ff00=== castdiag ARMED ===|r Target a caster. Reads .notInterruptible MID-cast.")
    -- NOTE: do NOT set HideIconWhenNotInterruptible on a cast bar - if that bar has been
    -- tainted by any third-party addon (skinning the target frame, replacing the nameplate),
    -- the resulting IsInterruptable() call throws on the secret barType. The icon-hidden
    -- signal only works on an UNtainted, Blizzard-driven bar. Verified 2026-06-28.

    local function stamp(label) log[#log + 1] = string.format("%+.3fs %s", GetTime() - armT, label) end

    -- Convert any value to a print-safe string. Returns "<secret>" for secret values,
    -- secret-tainted strings, or anything tostring can't handle - never lets a secret
    -- reach AceConsole's concat (which errors on secrets).
    local function safe(v)
        if v == nil then return "nil" end
        -- IsSecretValue misses event-arg secrets, so don't trust it. Instead force the value
        -- through the operations a secret throws on (compare + concat) and catch the error.
        local ok, s = pcall(function()
            local str = tostring(v)
            local _ = (str == "")  -- comparison throws if str is a secret string
            return str .. ""       -- concat throws if secret; returns a clean copy otherwise
        end)
        if ok and type(s) == "string" then return s end
        return "<secret>"
    end

    -- Capture .notInterruptible DURING the cast. The field is only valid while casting;
    -- reading it after STOP (as the old report did) always came back false. THIS is the
    -- value CastInterruptTracker line 155 uses to suppress the kick.
    local function captureProbes()
        if probed then return end
        probed = true
        local function probeBar(label, bar)
            if not bar then probeLines[#probeLines + 1] = label .. ": absent"; return end
            local niOk, ni = pcall(function() return bar.notInterruptible and true or false end)
            probeLines[#probeLines + 1] = string.format("%s .notInterruptible (MID-cast): ok=%s value=%s  <- true=can't interrupt",
                label, tostring(niOk), niOk and safe(ni) or "-")
        end
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
        probeBar("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
        probeBar("nameplate.castBar", np and np.UnitFrame and np.UnitFrame.castBar)
        -- Read the icon-hidden check on the BLIZZARD bars DIRECTLY, even if a third-party addon
        -- hides them and shows its own. If a hidden Blizzard bar still reports
        -- notInterruptible=true on a shielded cast, it is still Blizzard-DRIVEN and readable.
        -- hasIcon/flag must be present for the check to work.
        local function probeIconHidden(label, bar)
            if not bar then probeLines[#probeLines + 1] = "  " .. label .. ": absent"; return end
            local hasIcon = bar.Icon ~= nil
            local flag = bar.HideIconWhenNotInterruptible
            local sOk, shown = pcall(function() return bar.Icon and bar.Icon:IsShown() and true or false end)
            local cOk, chk = pcall(function() return (bar.Icon and bar.HideIconWhenNotInterruptible and not bar.Icon:IsShown()) and true or false end)
            probeLines[#probeLines + 1] = string.format("  %s icon-hidden: hasIcon=%s flag=%s iconShown=%s => notInterruptible=%s",
                label, tostring(hasIcon), tostring(flag), sOk and safe(shown) or "?", cOk and safe(chk) or "?")
        end
        probeIconHidden("TargetFrame.spellbar (Blizzard)", TargetFrame and TargetFrame.spellbar)
        probeIconHidden("nameplate UnitFrame.castBar (Blizzard,capU)", np and np.UnitFrame and np.UnitFrame.castBar)
        -- LIVENESS of the (possibly hidden) Blizzard bar: a replacing addon that merely
        -- Hide()s it leaves its UNTAINTED event handlers running - the icon-hidden read
        -- above then stays trustworthy even invisible. An addon that unregistered its
        -- events leaves the state frozen-stale (must never be trusted: stale iconShown
        -- would read as "interruptible" = wrongly-shown kick). Verdict rules:
        --   eventsRegistered + castingFlag tracking THIS cast = LIVE (signal usable)
        --   eventsRegistered=false = EVENT-DEAD (unusable)
        local function probeLiveness(label, bar)
            if not bar then return end
            local regOk, regged = pcall(function() return bar:IsEventRegistered("UNIT_SPELLCAST_START") and true or false end)
            local cOk, castingF = pcall(function() return (bar.casting or bar.channeling) and true or false end)
            local shOk, shownF  = pcall(function() return bar:IsShown() and true or false end)
            local vOk, visible  = pcall(function() return bar:IsVisible() and true or false end)
            local verdict
            if regOk and regged and cOk and castingF then
                verdict = "|cff00ff00LIVE - hidden-bar icon signal trustworthy|r"
            elseif regOk and not regged then
                verdict = "|cffff6600EVENT-DEAD (events unregistered) - unusable|r"
            elseif cOk and not castingF then
                verdict = "|cffff6600STALE (casting flag not tracking this cast) - unusable|r"
            else
                verdict = "|cffff6600INCONCLUSIVE (reads sealed)|r"
            end
            probeLines[#probeLines + 1] = string.format(
                "  %s liveness: eventsReg=%s castingFlag=%s shown=%s visible=%s",
                label, regOk and safe(regged) or "?", cOk and safe(castingF) or "?",
                shOk and safe(shownF) or "?", vOk and safe(visible) or "?")
            probeLines[#probeLines + 1] = "    => " .. verdict
        end
        probeLiveness("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
        probeLiveness("nameplate UnitFrame.castBar", np and np.UnitFrame and np.UnitFrame.castBar)
        -- Focus-frame bar: a second untainted Blizzard bar if the player has focus=target
        if FocusFrame and FocusFrame.spellbar then
            probeIconHidden("FocusFrame.spellbar (Blizzard)", FocusFrame.spellbar)
            probeLiveness("FocusFrame.spellbar", FocusFrame.spellbar)
        end
        -- BYPASS PROBE: does a replacing cast-bar addon expose its OWN interruptibility on its
        -- bar? Such bars commonly live at nameplate.unitFrame.castBar (lowercase). If a field
        -- reads a clean boolean matching the actual cast (and its shield is visually correct),
        -- we could read its answer instead of Blizzard's. Compare to what its bar shows.
        local puf = np and np.unitFrame
        local pcb = puf and puf.castBar
        if pcb then
            local function rd(field)
                local ok, v = pcall(function() return pcb[field] end)
                return ok and safe(v) or "ERR"
            end
            probeLines[#probeLines + 1] = string.format("3rd-party castBar fields: canInterrupt=%s notInterruptible=%s IsInterruptible=%s",
                rd("canInterrupt"), rd("notInterruptible"), rd("IsInterruptible"))
            local sOk, sh = pcall(function() return pcb.Icon and pcb.Icon:IsShown() and true or false end)
            probeLines[#probeLines + 1] = "3rd-party castBar: hasIcon=" .. tostring(pcb.Icon ~= nil) ..
                " iconShown=" .. (sOk and safe(sh) or "?") .. " HideIconFlag=" .. tostring(pcb.HideIconWhenNotInterruptible)
        else
            probeLines[#probeLines + 1] = "3rd-party castBar: not found (nameplate.unitFrame.castBar absent)"
        end
        -- The AUTHORITATIVE verdict: what the addon's own IsTargetCastInterruptible returns.
        local CIT = LibStub and LibStub("JustAC-CastInterruptTracker", true)
        if CIT and CIT.DebugInterruptState then
            local okc, isCasting, interruptible, src = pcall(CIT.DebugInterruptState)
            probeLines[#probeLines + 1] = string.format("IsTargetCastInterruptible(): isCasting=%s interruptible=%s  via=%s",
                okc and safe(isCasting) or "ERR", okc and safe(interruptible) or "-", okc and safe(src) or "-")
        end
        local worthy = BlizzardAPI and BlizzardAPI.IsTargetInterruptWorthy and BlizzardAPI.IsTargetInterruptWorthy()
        probeLines[#probeLines + 1] = "IsTargetInterruptWorthy(): " .. tostring(worthy)
        local ic = addon.interruptIcon
        local sOk, shown = pcall(function() return ic and ic:IsShown() and true or false end)
        local aOk, alpha = pcall(function() return ic and ic:GetAlpha() end)
        probeLines[#probeLines + 1] = "JustAC Kick icon: shown=" .. (sOk and tostring(shown) or "?") ..
            " alpha=" .. (aOk and safe(alpha) or "?") .. "  (alpha 0 on a non-kickable cast = SetAlphaFromBoolean works)"
        addon:Print(string.format("|cff888888[castdiag captured mid-cast at +%.2fs; full result on cast end]|r", GetTime() - startedT))
    end

    local function report()
        if DebugCommands._castDiag ~= f then return end
        -- Clean up FIRST so any print error cannot re-fire every frame.
        f:UnregisterAllEvents(); f:SetScript("OnEvent", nil); f:SetScript("OnUpdate", nil)
        DebugCommands._castDiag = nil
        local pok, perr = pcall(function()
            addon:Print("|cff00ff00=== castdiag RESULT ===|r")
            for _, line in ipairs(log) do addon:Print("  " .. line) end
            local sawInterEvt = false
            for _, line in ipairs(log) do if line:find("INTERRUPTIBLE") then sawInterEvt = true break end end
            addon:Print("  Q1 interruptible event this cast: " ..
                (sawInterEvt and "|cff00ff00YES - events may suffice|r" or "|cffff6600NO - initial state needs secret resolution|r"))
            if #probeLines > 0 then
                addon:Print("  |cffffd100--- MID-CAST reads (what the addon actually uses) ---|r")
                for _, l in ipairs(probeLines) do addon:Print("  " .. l) end
            else
                addon:Print("  |cffff6600(no mid-cast capture - cast ended in <0.3s)|r")
            end
            -- Q2: the cast's spellID from the event - if readable, a spell-keyed lookup is viable.
            local idStr = safe(castSpellID)
            addon:Print("  Q2 event spellID: " .. idStr ..
                (idStr == "<secret>" and " |cffff6600(secret -> spell-DB approach dead)|r"
                 or " |cff00ff00(readable -> spell-DB approach viable)|r"))
            -- Q3: BorderShield:IsShown() - Blizzard's display derivation. shown=true would
            -- mean non-interruptible if it reads as a concrete (non-secret) boolean.
            addon:Print("  Q3 cast-bar BorderShield IsShown (true expected on a shielded cast):")
            local function probeShield(label, bar)
                if not bar then addon:Print("    " .. label .. ": |cff888888absent|r"); return end
                -- (post-STOP read - kept only for the BorderShield secret check; the meaningful
                -- .notInterruptible value is the MID-CAST capture printed above.)
                local shield = bar.BorderShield or bar.Shield
                if shield and shield.IsShown then
                    local ok, shown = pcall(shield.IsShown, shield)
                    addon:Print(string.format("    %s BorderShield IsShown (post-cast): ok=%s shown=%s", label, tostring(ok), ok and safe(shown) or "-"))
                end
            end
            probeShield("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
            local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
            probeShield("nameplate.UnitFrame.castBar", np and np.UnitFrame and np.UnitFrame.castBar)
            -- Q4: cast-bar color. If Blizzard sets it by branching on the secret (a plain
            -- constant result), GetStatusBarColor() is NON-secret -> we can read interruptibility
            -- directly (yellow ~ interruptible, grey ~ not). If it reads <secret>, it's piped.
            -- base StatusBarColor was white; the grey/yellow lives on the fill texture's
            -- ATLAS or vertex color. If either is a readable constant that differs by
            -- interruptibility, that's the full fix.
            addon:Print("  Q4 cast-bar fill appearance (readable + differs by cast = full fix):")
            local function probeColor(label, bar)
                if not bar then addon:Print("    " .. label .. ": |cff888888absent|r"); return end
                local _, r, g, b = pcall(bar.GetStatusBarColor, bar)
                local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
                local atlas, vr, vg, vb = "n/a", nil, nil, nil
                if tex then
                    local aok, a = pcall(tex.GetAtlas, tex); if aok then atlas = a end
                    local vok, x, y, z = pcall(tex.GetVertexColor, tex); if vok then vr, vg, vb = x, y, z end
                end
                addon:Print(string.format("    %s: barColor=%s/%s/%s vertex=%s/%s/%s",
                    label, safe(r), safe(g), safe(b), safe(vr), safe(vg), safe(vb)))
                addon:Print("      atlas=" .. safe(atlas))
            end
            probeColor("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
            probeColor("nameplate.UnitFrame.castBar", np and np.UnitFrame and np.UnitFrame.castBar)
            -- Q5: can we PASS the secret shield state into display sinks without reading it?
            -- SetDesaturated greys the icon (non-occluding - keybind stays visible); SetShown
            -- drives a non-covering border/badge. ok = that cue is viable.
            -- Which secret-accepting sinks can drive a cue? ok = that visual is usable.
            -- VertexColor (color tint) is the most obvious; Alpha (fade) next; Desaturated
            -- (grey) is the subtle baseline; Shown is known-rejected. The secret bool is
            -- forwarded to each, never read.
            addon:Print("  Q5 secret-passthrough sinks (ok = that cue is usable):")
            local function probePass(label, bar)
                local shield = bar and (bar.BorderShield or bar.Shield)
                if not (shield and shield.IsShown) then addon:Print("    " .. label .. ": |cff888888no shield|r"); return end
                if not DebugCommands._probeTex then
                    DebugCommands._probeTex = UIParent:CreateTexture(nil, "OVERLAY"); DebugCommands._probeTex:Hide()
                end
                local tex = DebugCommands._probeTex
                local s = shield:IsShown()  -- secret bool; forwarded to sinks, never read
                local function t(fn) return pcall(fn) and "|cff00ff00ok|r" or "|cffff6600REJECT|r" end
                addon:Print(string.format("    %s: VertexColor=%s Alpha=%s Desaturated=%s Shown=%s", label,
                    t(function() tex:SetVertexColor(1, s, s) end),
                    t(function() tex:SetAlpha(s) end),
                    t(function() tex:SetDesaturated(s) end),
                    t(function() tex:SetShown(s) end)))
            end
            probePass("TargetFrame.spellbar", TargetFrame and TargetFrame.spellbar)
        end)
        if not pok then addon:Print("|cffff0000castdiag error (handled):|r " .. safe(perr)) end
    end

    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    -- Interruptible events registered BROADLY (no unit filter): the game may fire them with
    -- a "nameplateN" token instead of "target", which a target-filtered registration misses.
    -- We match back to the current target via UnitIsUnit (non-secret).
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    f:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")

    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Log only if it pertains to the current target, whatever token the game used.
            if unit and UnitIsUnit and UnitIsUnit(unit, "target") then
                stamp(event:gsub("UNIT_SPELLCAST_", "") .. " (target via " .. tostring(unit) .. ")")
            end
            return
        end
        stamp((event:gsub("UNIT_SPELLCAST_", "")))
        if (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") and not started then
            started = true
            startedT = GetTime()
            castSpellID = spellID  -- raw; safe() converts at print time (may be secret)
        elseif (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP") and started then
            report()
        end
    end)

    f:SetScript("OnUpdate", function()
        local now = GetTime()
        if not started then
            if now - armT > 30 then
                addon:Print("|cffff6600castdiag timed out (no cast in 30s). Disarmed.|r")
                f:UnregisterAllEvents(); f:SetScript("OnUpdate", nil); f:SetScript("OnEvent", nil)
                DebugCommands._castDiag = nil
            end
            return
        end
        if not probed and (now - startedT) >= 0.3 then captureProbes() end  -- read .notInterruptible MID-cast
        if (now - startedT) > 8 then report() end                          -- long/channel cast with no STOP
    end)
end

--------------------------------------------------------------------------------
-- Assumption Validation Suite
-- /jac inspect validate       - one-shot sweep of every load-bearing API read
-- /jac inspect validate arm   - also re-captures on combat enter/exit and prints
--                               only what changed class (readable/secret/sealed)
-- Every probe is classified: ok:<value> | secret | SEALED (threw) | nil | absent.
-- Nothing is written or branched on a secret; reads are pcall-guarded.
--------------------------------------------------------------------------------

-- C_Secrets function count at last full audit (12.0.7, 2026-07-05). If the live
-- count differs, the secrecy surface changed and every assumption needs re-audit.
local SECRETS_SURFACE_COUNT = 27

local function ValidateClassify(fn)
    local ok, v = pcall(fn)
    if not ok then return "SEALED", "|cffff6666SEALED|r" end
    if v == nil then return "nil", "|cff888888nil|r" end
    -- Force compare+concat: catches secrets IsSecretValue misses (struct fields,
    -- event args) - same approach as chargediag/castdiag.
    local ok2, s = pcall(function()
        local str = tostring(v)
        local _ = (str == "")
        return str .. ""
    end)
    if not ok2 or type(s) ~= "string" then return "secret", "|cffff6600<secret>|r" end
    -- Booleans are state, not noise: track the VALUE so a predicate flipping
    -- false->true in combat shows in the diff. Numbers (cooldown clocks etc.)
    -- churn constantly - class-only for those.
    if type(v) == "boolean" then return "ok:" .. s, "|cff00ff00" .. s .. "|r" end
    if #s > 24 then s = s:sub(1, 24) .. ".." end
    return "ok", "|cff00ff00" .. s .. "|r"
end

-- First rotation spell if plainly readable, else the GCD reference spell.
local function ValidateProbeSpell()
    local ok, sid = pcall(function()
        return C_AssistedCombat.GetRotationSpells()[1] + 0
    end)
    if ok and type(sid) == "number" then return sid end
    return 61304
end

-- First occupied action slot with a plainly readable HasAction.
local function ValidateProbeSlot()
    for i = 1, 120 do
        local ok, has = pcall(function() return HasAction(i) == true end)
        if ok and has then return i end
    end
    return 1
end

local function BuildValidateProbes()
    local probes = {}
    local function add(key, fn) probes[#probes + 1] = { key, fn } end
    local sid = ValidateProbeSpell()
    local slot = ValidateProbeSlot()
    local CS = C_Secrets

    -- Secrecy predicates (full documented surface, correct args). Plain booleans
    -- by contract; any class other than ok/absent here is itself a finding.
    if type(CS) == "table" then
        add("secrets.HasSecretRestrictions", function() return CS.HasSecretRestrictions() end)
        add("secrets.ShouldAurasBeSecret", function() return CS.ShouldAurasBeSecret() end)
        add("secrets.ShouldCooldownsBeSecret", function() return CS.ShouldCooldownsBeSecret() end)
        add("secrets.ShouldUnitStatsBeSecret", function() return CS.ShouldUnitStatsBeSecret() end)
        add("secrets.ShouldUnitHealthMaxBeSecret", function() return CS.ShouldUnitHealthMaxBeSecret("player") end)
        add("secrets.ShouldUnitPowerBeSecret", function() return CS.ShouldUnitPowerBeSecret("player") end)
        add("secrets.ShouldUnitIdentityBeSecret", function() return CS.ShouldUnitIdentityBeSecret("target") end)
        add("secrets.ShouldUnitSpellCastingBeSecret", function() return CS.ShouldUnitSpellCastingBeSecret("target") end)
        add("secrets.ShouldUnitComparisonBeSecret", function() return CS.ShouldUnitComparisonBeSecret("player", "target") end)
        add("secrets.ShouldUnitThreatStateBeSecret", function() return CS.ShouldUnitThreatStateBeSecret("player", "target") end)
        add("secrets.ShouldSpellCooldownBeSecret", function() return CS.ShouldSpellCooldownBeSecret(sid) end)
        add("secrets.ShouldSpellAuraBeSecret", function() return CS.ShouldSpellAuraBeSecret(sid) end)
        add("secrets.ShouldActionCooldownBeSecret", function() return CS.ShouldActionCooldownBeSecret(slot) end)
        add("secrets.CanCompareUnitTokens", function() return CS.CanCompareUnitTokens("player", "target") end)
        -- SecrecyLevel: 0=NeverSecret 1=AlwaysSecret 2=ContextuallySecret
        add("secrets.SpellCooldownSecrecy", function() return CS.GetSpellCooldownSecrecy(sid) end)
        add("secrets.SpellAuraSecrecy", function() return CS.GetSpellAuraSecrecy(sid) end)
        add("secrets.SpellCastSecrecy", function() return CS.GetSpellCastSecrecy(sid) end)
        add("secrets.PowerTypeSecrecy", function() return CS.GetPowerTypeSecrecy(0) end)
    else
        add("secrets.C_Secrets", function() return nil end)
    end

    add("health.UnitHealth", function() return UnitHealth("player") end)
    add("health.UnitHealthMax", function() return UnitHealthMax("player") end)
    add("health.UnitHealthMissing", function() return UnitHealthMissing and UnitHealthMissing("player") end)
    add("health.UnitHealthPercent", function() return UnitHealthPercent and UnitHealthPercent("player") end)
    add("health.UnitPower", function() return UnitPower("player") end)
    add("health.UnitPowerMax", function() return UnitPowerMax("player") end)
    add("health.absorbs", function() return UnitGetTotalAbsorbs("player") end)
    add("health.targetHealth", function() return UnitHealth("target") end)

    add("aura.helpfulCount", function()
        local n = 0
        for i = 1, 40 do
            if not C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL") then break end
            n = n + 1
        end
        return n
    end)
    for _, field in ipairs({ "name", "spellId", "duration", "expirationTime", "applications" }) do
        add("aura.player1." .. field, function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
            return a and a[field]
        end)
    end
    add("aura.durationObjSecret", function()
        local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
        if not a then return nil end
        local d = C_UnitAuras.GetAuraDuration("player", a.auraInstanceID)
        return d and d:HasSecretValues()  -- ReturnsNeverSecret by contract
    end)
    -- Per-aura secrecy: docs say per-spell flags override the global rule
    -- (ShouldAurasBeSecret=true while an exempt buff stays readable).
    add("aura.player1.shouldBeSecret", function()
        return CS and CS.ShouldUnitAuraIndexBeSecret("player", 1, "HELPFUL")
    end)
    add("aura.player1.auraSecrecy", function()
        local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
        return a and CS and CS.GetSpellAuraSecrecy(a.spellId)  -- spellId may be secret; accepted per docs
    end)
    add("aura.target1.spellId", function()
        local a = C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL")
        return a and a.spellId
    end)
    -- Live fronts for the static SelfAuras/AuraStacks tables (SpellDB accessors).
    -- maxStacks probes a KNOWN stacking aura (Ironfur): the API throws (SEALED)
    -- for spells without a stacking record - verified 2026-07-05 with Cat Form.
    add("aura.isSelfBuffAPI", function() return C_Spell.IsSelfBuff(sid) end)
    add("aura.maxStacksIronfur", function() return C_UnitAuras.GetSpellMaxCumulativeAuraApplications(192081) end)

    add("cd.probeSpell", function() return sid end)
    add("cd.start", function() return C_Spell.GetSpellCooldown(sid).startTime end)
    add("cd.duration", function() return C_Spell.GetSpellCooldown(sid).duration end)
    add("cd.isEnabled", function() return C_Spell.GetSpellCooldown(sid).isEnabled end)
    add("cd.chargesCurrent", function()
        local c = C_Spell.GetSpellCharges(sid)
        return c and c.currentCharges
    end)
    add("cd.chargesMax", function()
        local c = C_Spell.GetSpellCharges(sid)
        return c and c.maxCharges  -- NeverSecret by contract
    end)
    add("cd.castCount", function() return C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(sid) end)
    add("cd.durationObjSecret", function()
        local d = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
        return d and d:HasSecretValues()
    end)
    add("cd.usable", function() return C_Spell.IsSpellUsable(sid) end)
    add("cd.inRange", function() return C_Spell.IsSpellInRange(sid, "target") end)
    add("cd.overrideSpell", function() return C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(sid) end)

    add("ac.next", function() return C_AssistedCombat.GetNextCastSpell() end)
    add("ac.rot1", function() return C_AssistedCombat.GetRotationSpells()[1] end)
    add("ac.rotCount", function() return #C_AssistedCombat.GetRotationSpells() end)
    add("ac.available", function() return (C_AssistedCombat.IsAvailable()) end)
    add("proc.overlayed", function() return C_SpellActivationOverlay.IsSpellOverlayed(sid) end)

    add("action.probeSlot", function() return slot end)
    add("action.cdStart", function() return (GetActionCooldown(slot)) end)
    add("action.usable", function() return (IsUsableAction(slot)) end)
    add("action.inRange", function() return IsActionInRange(slot) end)
    add("action.isInterrupt", function() return C_ActionBar.IsInterruptAction and C_ActionBar.IsInterruptAction(slot) end)
    add("action.durationObjSecret", function()
        local d = C_ActionBar.GetActionCooldownDuration and C_ActionBar.GetActionCooldownDuration(slot)
        return d and d:HasSecretValues()
    end)

    add("cast.playerName", function() return (UnitCastingInfo("player")) end)
    add("cast.targetName", function() return (UnitCastingInfo("target")) end)
    add("cast.targetNotInterruptible", function() return select(8, UnitCastingInfo("target")) end)

    add("viewer.available", function() return (C_CooldownViewer.IsCooldownViewerAvailable()) end)
    add("viewer.essentialCount", function()
        return #C_CooldownViewer.GetCooldownViewerCategorySet(Enum.CooldownViewerCategory.Essential, false)
    end)

    -- What the addon's own gates believe - should agree with the raw reads above.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.GetFeatureAvailability then
        add("gate.health", function() return BAPI.GetFeatureAvailability().healthAccess end)
        add("gate.aura", function() return BAPI.GetFeatureAvailability().auraAccess end)
        add("gate.proc", function() return BAPI.GetFeatureAvailability().procAccess end)
    end

    return probes
end

local function PrintValidateEnv(addon)
    local function vs(fn)
        local ok, v = pcall(fn)
        if not ok then return "SEALED" end
        local ok2, s = pcall(tostring, v)
        return ok2 and s or "<secret>"
    end
    addon:Print("  where: zone=" .. vs(function() return (GetInstanceInfo()) end)
        .. " type=" .. vs(function() return select(2, GetInstanceInfo()) end)
        .. " diff=" .. vs(function() return select(4, GetInstanceInfo()) end)
        .. " map=" .. vs(function() return C_Map.GetBestMapForUnit("player") end)
        .. " instID=" .. vs(function() return select(8, GetInstanceInfo()) end))
    addon:Print("  state: combat=" .. tostring(UnitAffectingCombat("player"))
        .. " resting=" .. vs(IsResting)
        .. " group=" .. (IsInRaid() and "raid" or IsInGroup() and "party" or "solo")
        .. " spec=" .. vs(function() return select(2, GetSpecializationInfo(GetSpecialization())) end)
        .. " form=" .. vs(GetShapeshiftFormID)
        .. " level=" .. vs(function() return UnitLevel("player") end))
    addon:Print("  pvp: warMode=" .. vs(C_PvP.IsWarModeActive)
        .. " zonePvP=" .. vs(function() return (C_PvP.GetZonePVPInfo()) end)
        .. "  client: " .. vs(function() local v, b = GetBuildInfo(); return v .. "." .. b end))
end

-- Runs all probes; returns snapshot {key -> class} plus ordered key list.
local function RunValidateSnapshot(addon, printAll)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.RefreshFeatureAvailability then pcall(BAPI.RefreshFeatureAvailability) end
    local probes = BuildValidateProbes()
    local snap, order = {}, {}
    local curGroup, parts
    local function flush()
        if curGroup and parts and #parts > 0 then
            addon:Print("  " .. curGroup .. ": " .. table.concat(parts, " "))
        end
        parts = {}
    end
    for _, p in ipairs(probes) do
        local key, fn = p[1], p[2]
        local class, disp = ValidateClassify(fn)
        snap[key] = class
        order[#order + 1] = key
        if printAll then
            local group, rest = key:match("^([^.]+)%.(.+)$")
            if group ~= curGroup then
                flush()
                curGroup = group
            end
            parts[#parts + 1] = rest .. "=" .. disp
            if #parts >= 5 then flush() end
        end
    end
    if printAll then flush() end
    return snap, order
end

local function DiffValidate(addon, base, now, order)
    local changed = 0
    for _, key in ipairs(order) do
        if base[key] ~= now[key] then
            changed = changed + 1
            addon:Print(string.format("  |cffffff00%s|r: %s -> %s", key,
                tostring(base[key]), tostring(now[key])))
        end
    end
    addon:Print(string.format("  %d probe class change(s); %d held.", changed, #order - changed))
end

function DebugCommands.ValidateAssumptions(addon, arg)
    local armed = arg == "arm"
    if armed and DebugCommands._validate then
        addon:Print("|cffffff00validate already armed (/reload to cancel).|r")
        return
    end

    addon:Print("===== assumption validation (" .. (armed and "armed" or "one-shot") .. ") =====")
    PrintValidateEnv(addon)

    -- Secrecy surface drift check: the one signal that all cached verdicts are stale.
    local fnCount = 0
    if type(C_Secrets) == "table" then
        for _, v in pairs(C_Secrets) do
            if type(v) == "function" then fnCount = fnCount + 1 end
        end
    end
    if fnCount ~= SECRETS_SURFACE_COUNT then
        addon:Print(string.format(
            "|cffff0000C_Secrets surface changed: %d functions (audited at %d) - re-audit all secrecy assumptions!|r",
            fnCount, SECRETS_SURFACE_COUNT))
    end

    -- Render-sink availability (existence only; these consume secrets, never return them).
    local sink = DebugCommands._validateSinkProbe
    if not sink then
        sink = { tex = UIParent:CreateTexture(), cd = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate") }
        sink.tex:Hide(); sink.cd:Hide()
        DebugCommands._validateSinkProbe = sink
    end
    local function has(obj, m) return type(obj) == "table" and type(obj[m]) == "function" and "yes" or "|cffff6666NO|r" end
    addon:Print("  sinks: SetAlphaFromBoolean=" .. has(sink.tex, "SetAlphaFromBoolean")
        .. " SetVertexColorFromBoolean=" .. has(sink.tex, "SetVertexColorFromBoolean")
        .. " SetCooldownFromDurationObject=" .. has(sink.cd, "SetCooldownFromDurationObject")
        .. " C_CurveUtil=" .. has(C_CurveUtil, "EvaluateColorFromBoolean"))

    local base, order = RunValidateSnapshot(addon, true)

    if not armed then
        addon:Print("Tip: '/jac inspect validate arm' re-captures on combat enter/exit and prints the diff.")
        addon:Print("=============================================")
        return
    end

    local f = CreateFrame("Frame")
    DebugCommands._validate = f
    local armT = GetTime()
    local combatSnap
    local pendingCaptureAt
    local settleCaptureAt

    local function disarm(msg)
        f:UnregisterAllEvents(); f:SetScript("OnEvent", nil); f:SetScript("OnUpdate", nil)
        DebugCommands._validate = nil
        addon:Print(msg)
    end

    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            pendingCaptureAt = GetTime() + 0.5  -- let secrecy state settle
        elseif combatSnap then
            settleCaptureAt = nil
            addon:Print("|cff00ff00validate: combat ended - post-combat vs in-combat:|r")
            PrintValidateEnv(addon)
            local post = RunValidateSnapshot(addon, false)
            DiffValidate(addon, combatSnap, post, order)
            disarm("validate: done.")
        end
    end)
    f:SetScript("OnUpdate", function()
        local now = GetTime()
        if pendingCaptureAt and now >= pendingCaptureAt then
            pendingCaptureAt = nil
            addon:Print("|cff00ff00validate: in-combat capture (+0.5s) - changes vs baseline:|r")
            PrintValidateEnv(addon)
            combatSnap = RunValidateSnapshot(addon, false)
            DiffValidate(addon, base, combatSnap, order)
            settleCaptureAt = now + 4.5  -- settle check: does anything flip late?
        end
        if settleCaptureAt and now >= settleCaptureAt then
            settleCaptureAt = nil
            local settled = RunValidateSnapshot(addon, false)
            addon:Print("|cff00ff00validate: settle check (~+5s vs +0.5s capture):|r")
            DiffValidate(addon, combatSnap, settled, order)
            combatSnap = settled  -- exit diff compares against the latest state
        end
        if now - armT > 600 then
            disarm("|cffffff00validate: 10min window ended - disarmed.|r")
        end
    end)
    if UnitAffectingCombat("player") then pendingCaptureAt = GetTime() end
    addon:Print("|cff00ff00validate ARMED:|r enter (and leave) combat to capture diffs. 10min window.")
end
