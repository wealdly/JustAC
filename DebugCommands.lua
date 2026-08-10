-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Debug Commands Module - Provides diagnostic commands for testing and troubleshooting
local DebugCommands = LibStub:NewLibrary("JustAC-DebugCommands", 37)
if not DebugCommands then return end

-- Print-safe stringify: "nil" for nil, "<secret>" for secret values, else the
-- plain string. Event args and struct fields can be secret in ways IsSecretValue
-- misses, so force the value through the operations a secret throws on (compare +
-- concat) inside a pcall and treat any throw as secret.
local function SafeSecret(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function()
        local str = tostring(v)
        local _ = (str == "")
        return str .. ""
    end)
    if ok and type(s) == "string" then return s end
    return "<secret>"
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------
function DebugCommands.ShowHelp(addon)
    addon:Print("Available commands:")
    addon:Print("/jac - Open options panel")
    addon:Print("/jac toggle - Pause/resume display")
    addon:Print("/jac debug - Toggle debug mode")
    addon:Print("/jac reset - Unlock, undock and re-centre the panel (use if you can't find or move it)")
    addon:Print("/jac enable - Enable the addon for the current spec (if it was disabled)")
    addon:Print("/jac profile <name> - Switch profile")
    addon:Print("/jac profile list - List profiles")
    addon:Print("/jac find [spell] - Find spell on action bars (defaults to AC suggestion)")
    addon:Print("/jac why <spell> - Explain why a spell is or isn't showing in the queue")
    addon:Print("/jac inspect modules - Check module health")
    addon:Print("/jac inspect cooldown [spell] - Test cooldown APIs (defaults to AC suggestion)")
    addon:Print("/jac inspect defensives - Diagnose defensive system")
    addon:Print("/jac inspect interrupts - Diagnose interrupt/CC queue state")
    addon:Print("/jac inspect burst - Burst-ready cue state")
    addon:Print("/jac inspect auras - Diagnose aura cache state")
    addon:Print("/jac inspect buffs - Diagnose pre-combat buff checklist (out of combat)")
    addon:Print("/jac inspect perf - Queue build rate statistics (requires debug mode)")
    addon:Print("/jac inspect perf reset - Reset build counters")
    addon:Print("/jac inspect rank - Queue context inference and per-spell ordering ranks")
    addon:Print("/jac inspect dots - Maintained-DoT tracking state for the current target")
    addon:Print("/jac inspect gates - SimC gate layer: buff-window tracker + live gate eval (run in combat)")
    addon:Print("/jac inspect aoe - Probe secret-safe enemy counting (AC-independent AoE detection)")
    addon:Print("/jac inspect resource - Probe secret-safe resource inference from usability")
    addon:Print("/jac inspect rotation - Probe whether GetRotationSpells' tail is live-ordered (A/B across state)")
    addon:Print("/jac inspect resourcepoints - Probe whether class resource points (combo/holy power/chi) read plain")
    addon:Print("/jac inspect secrecy - Measure which combat values actually read plain vs secret (run in AND out of combat)")
    addon:Print("/jac inspect stacks - Out of combat: is a stacking buff N aura instances or one secret counter?")
    addon:Print("/jac inspect maintenance - Can the tank maintenance slot bind its aura exactly? (run IN combat)")
    addon:Print("/jac inspect maintlog [on|off|clear] - Record maintenance state 1/s to SavedVariables")
    addon:Print("/jac inspect enrage [off] - Probe secret-safe enrage detection (DispelType 9 color curve)")
    addon:Print("/jac inspect durprobe [spell] - Verify the scratch-Cooldown readiness probe on a spell")
    addon:Print("/jac inspect locwatch - Arm a 10min loss-of-control capture (get CC'd; prints real locType)")
    addon:Print("/jac inspect chargediag [spell] - Arm a 60s charge-event/secrecy probe")
    addon:Print("/jac inspect castdiag - Arm a one-shot cast-interruptibility probe")
    addon:Print("/jac inspect healthprobe - Sweep every OOC health-detection channel (run while hurt)")
    addon:Print("/jac inspect healthgate - Toggle live on-screen swatches proving the curve gate tracks health")
    addon:Print("/jac inspect healprobe [arm|show|watch] - Heal-mode party probes: low-bridge, roster gates, curves, dispel filter, AC feed")
    addon:Print("/jac inspect validate [arm] - Validate every secrecy/API assumption; arm = diff on combat enter/exit")
    addon:Print("/jac inspect audit [off|clear] - ARM the 68887 probe battery: auto-snapshots on combat enter/exit to SavedVariables")
    addon:Print("/jac inspect selfcast - Arm a capture of own-cast info secrecy (cast + channel something)")
    addon:Print("/jac inspect auraids - One-shot: are aura instance-ID lists plain/countable in combat?")
    addon:Print("/jac inspect blank - Why the queue last went empty (run right after it vanishes)")
    addon:Print("/jac inspect ccdb [clear] - Mob types learned to be CC-immune (persists across sessions)")
    addon:Print("/jac inspect cdfields - One-shot: NeverSecret cooldown fields + proc overlay per rotation spell")
    addon:Print("/jac inspect secrecymap - One-shot OOC: per-spell/power SecrecyLevel exemption dump")
    addon:Print("/jac inspect frames - One-shot: laundered frame booleans (low HP, capped power, absorbs)")
    addon:Print("/jac inspect cvitems - One-shot: Cooldown Manager item booleans (CD flash, buff active, pandemic)")
    addon:Print("/jac inspect enginesig - One-shot: unused engine signals (batch auras, spell classifiers, cast-on-me, absorb clamps)")
    addon:Print("/jac hud - Toggle a live diagnostic HUD (context, source, AC pick, buff windows)")
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

    -- F. The SANCTIONED secret-safe gate: map the secret health fraction through a
    --    non-secret step curve to an alpha, then sink that (secret) alpha straight
    --    into SetAlpha - never read, never branched. This is the exact idiom that
    --    already ships in UISootheCue (enrage gate) and ApplyExecuteColor (execute
    --    cue); the only open question is whether it round-trips for the PLAYER, OOC,
    --    in a secret zone. If it does, the OOC top-off suggestion can be gated on
    --    TRUE health across the whole 0-99% range, retiring the UNIT_HEALTH cadence
    --    heuristic (HasSustainedPlayerHealthActivity) and the ~35% vignette entirely.
    addon:Print("F. curve-gated alpha (UnitHealthPercent + C_CurveUtil -> SetAlpha):")
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor and UnitHealthPercent) then
        addon:Print("  |cffff6666unavailable|r (C_CurveUtil / UnitHealthPercent / Step missing)")
    else
        -- Reused throwaway swatch (never shown) so the probe leaks nothing across runs.
        DebugCommands._probeSwatch = DebugCommands._probeSwatch or UIParent:CreateTexture(nil, "BACKGROUND")
        local swatch = DebugCommands._probeSwatch
        -- ponytail: UnitHealthPercent's curve-input domain is unconfirmed - ApplyExecuteColor
        -- treats it as the 0-1 fraction, MIDNIGHT research notes 0-100. Test BOTH; the one
        -- whose swatch alpha tracks real health (visible while hurt) is the live domain.
        local function buildGate(hidePoint)
            local c = cu.CreateColorCurve()
            c:SetType(stepType)
            c:AddPoint(0,         CreateColor(1, 1, 1, 1))   -- below full -> show (a=1)
            c:AddPoint(hidePoint, CreateColor(0, 0, 0, 0))   -- at full    -> hide (a=0)
            return c
        end
        for _, dom in ipairs({ { "fraction", 1.0 }, { "0-100", 100 } }) do
            local label, hide = dom[1], dom[2]
            local ok, color = pcall(UnitHealthPercent, "player", false, buildGate(hide))
            if not ok then
                addon:Print("  " .. label .. " domain: |cffff6666SEALED|r (call threw)")
            elseif type(color) ~= "table" or not color.GetRGBA then
                addon:Print("  " .. label .. " domain: returned " .. safe(color) .. " (not a color)")
            else
                local aOk = pcall(function() swatch:SetAlpha(color.a) end)
                addon:Print("  " .. label .. " domain: color OK, .a=" ..
                    (IsSecret(color.a) and "|cffff6600<secret>|r" or safe(color.a)) ..
                    "  SetAlpha=" .. (aOk and "|cff00ff00OK|r" or "|cffff6666threw|r"))
            end
        end
        addon:Print("  verdict: 'color OK ... SetAlpha=OK' = the reliable gate works;")
        addon:Print("  a <secret> .a is EXPECTED and fine (it is what feeds SetAlpha).")
    end

    addon:Print("G. verdict guide: any GREEN number in E that tracks your real health")
    addon:Print("   percent = a readable channel; all SEALED/<secret> = heuristics stay.")
    addon:Print("=============================================")
end

--------------------------------------------------------------------------------
-- Live health-gate preview (toggle)
-- The one-shot HealthProbe confirms UnitHealthPercent+curve->SetAlpha round-trips
-- but CANNOT show that the (secret) alpha actually tracks health, nor which curve
-- input domain is live. This drops two on-screen swatches - one per domain - whose
-- alpha is driven every frame by the gate curve (alpha 1 below full, 0 at full).
-- Watch while healing: the swatch VISIBLE while hurt and GONE at full marks the
-- correct domain and proves the production gate works. Run again to remove.
--------------------------------------------------------------------------------
function DebugCommands.HealthGatePreview(addon)
    if DebugCommands._healthGateFrame then
        DebugCommands._healthGateFrame:Hide()
        DebugCommands._healthGateFrame:SetParent(nil)
        DebugCommands._healthGateFrame = nil
        addon:Print("Health-gate preview: OFF")
        return
    end
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and cu.CreateColorCurve and stepType and CreateColor and UnitHealthPercent) then
        addon:Print("Health-gate preview: |cffff6666unavailable|r (curve API missing)")
        return
    end

    -- Gate curve: alpha 1 below the hide-point, 0 at/above it (one per domain hypothesis).
    local function gate(hidePoint)
        local c = cu.CreateColorCurve()
        c:SetType(stepType)
        c:AddPoint(0,         CreateColor(1, 1, 1, 1))
        c:AddPoint(hidePoint, CreateColor(0, 0, 0, 0))
        return c
    end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(240, 90)
    f:SetPoint("CENTER", 0, 220)

    local function swatch(xoff, label, hidePoint)
        local box = f:CreateTexture(nil, "ARTWORK")
        box:SetColorTexture(0.1, 0.9, 0.2, 1)  -- solid green; the GATE drives its alpha
        box:SetSize(96, 56)
        box:SetPoint("TOPLEFT", xoff, -24)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOM", box, "TOP", 0, 2)
        fs:SetText(label)
        return { tex = box, curve = gate(hidePoint) }
    end

    f._swatches = { swatch(8, "fraction", 1.0), swatch(136, "0-100", 100) }

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    title:SetText("visible while HURT, gone at FULL = live domain")

    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.1 then return end
        self._t = 0
        for _, s in ipairs(self._swatches) do
            -- Never read the color; sink its (secret) alpha straight into SetAlpha.
            local ok, color = pcall(UnitHealthPercent, "player", false, s.curve)
            if ok and type(color) == "table" then
                pcall(function() s.tex:SetAlpha(color.a) end)
            end
        end
    end)

    DebugCommands._healthGateFrame = f
    addon:Print("Health-gate preview: ON (top-center). Take damage, then heal to full.")
    addon:Print("The swatch VISIBLE while hurt and GONE at full marks the live domain.")
    addon:Print("Run /jac inspect healthgate again to remove it.")
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
-- /jac why <spell> - walk the offensive-queue filter pipeline for one spell and
-- print a verdict per stage, so "my ability is missing" gets a concrete reason.
-- Mirrors the real order in SpellQueue.CategorizeAndAssembleRotation; every
-- possibly-secret read is guarded.
--------------------------------------------------------------------------------
function DebugCommands.WhyDiagnostics(addon, spellArg)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local RedundancyFilter = LibStub("JustAC-RedundancyFilter", true)
    local DotTracker = LibStub("JustAC-DotTracker", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not (BlizzardAPI and SpellQueue) then
        addon:Print("|cffff6666Required modules not loaded.|r")
        return
    end
    if not spellArg or spellArg == "" then
        addon:Print("Usage: /jac why <spellID or spell name>")
        return
    end

    local spellID = tonumber(spellArg)
    if not spellID and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        spellID = C_Spell.GetSpellIDForSpellIdentifier(spellArg)
    end
    if not spellID then
        addon:Print("|cffff6666Spell not found:|r " .. tostring(spellArg))
        return
    end
    local profile = addon.db and addon.db.profile
    if not profile then return end

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = (info and info.name) or ("Spell " .. spellID)
    addon:Print("=== Why: " .. name .. " (" .. spellID .. ") ===")

    local function line(label, ok, detail)
        addon:Print("  " .. (ok and "|cff2ecc71PASS|r " or "|cffff6666FAIL|r ") .. label
            .. (detail and (" - " .. detail) or ""))
    end
    local function note(text)
        addon:Print("  |cffaaaaaa....|r " .. text)
    end

    -- Source: custom queue membership for the current spec
    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    local cq = specKey and profile.customQueue and profile.customQueue[specKey]
    local cqLen
    if cq and cq.enabled and cq.spells and #cq.spells > 0 then
        cqLen = #cq.spells
        local pos
        for i, sid in ipairs(cq.spells) do
            if sid == spellID then pos = i; break end
        end
        addon:Print(pos and ("  Source: Custom Queue entry #" .. pos .. " of " .. cqLen)
            or "  Source: Custom Queue is active but this spell is NOT in its list - only listed spells appear")
    else
        addon:Print("  Source: Blizzard rotation (no Custom Queue for this spec)")
    end

    -- 1. Availability + variant resolution (full drop when unknown) - the SAME
    -- resolution the queue's list normalization uses, so verdicts can't drift.
    local effectiveID, source = spellID, nil
    if BlizzardAPI.ResolveKnownSpellID then
        effectiveID, source = BlizzardAPI.ResolveKnownSpellID(spellID)
    end
    local avail = effectiveID ~= nil
    line("Known", avail,
        (source == "stored" and "known as entered")
        or (source == "override" and ("known via talent override " .. tostring(effectiveID)))
        or (source == "base" and ("known via base spell " .. tostring(effectiveID)))
        or "this character doesn't know it (unlearned, other spec, or a talent-variant ID) - never shown")
    effectiveID = effectiveID or spellID

    local displayID = (BlizzardAPI.GetDisplaySpellID and BlizzardAPI.GetDisplaySpellID(effectiveID)) or effectiveID

    -- 2. Blacklist (full drop)
    local blk = SpellQueue.IsSpellBlacklisted and SpellQueue.IsSpellBlacklisted(spellID)
    line("Not blacklisted", not blk, blk and "Shift+Right-click its icon to un-blacklist" or nil)

    -- 2b. Gap-closer management: while the feature is ON, listed gap-closers are
    -- reserved for the slot-1 out-of-range injection and suppressed from the queue.
    if SpellQueue.IsGapCloserSpell and SpellQueue.IsGapCloserSpell(spellID) then
        local gcOn = profile.gapClosers and profile.gapClosers.enabled
        local pinned = SpellQueue.IsPinnedAlwaysShow
            and (SpellQueue.IsPinnedAlwaysShow(spellID) or SpellQueue.IsPinnedAlwaysShow(effectiveID))
        if gcOn and not pinned then
            line("Not gap-closer-managed", false,
                "it's in your Gap-Closers list, so it only appears as the slot-1 suggestion when the target is out of melee range. To also keep it in the queue: pin it with Always Show (Custom Queue) or turn Gap-Closers off")
        elseif gcOn and pinned then
            note("Gap-closer entry, pinned with Always Show - stays in the queue and still injects at slot 1 out of range")
        else
            note("Gap-closer list entry, but the feature is off - flows through the queue normally")
        end
    end

    -- 3. Item-ability filter (full drop when off)
    if BlizzardAPI.IsItemSpell and BlizzardAPI.IsItemSpell(displayID) then
        line("Item abilities allowed", not profile.hideItemAbilities,
            profile.hideItemAbilities and "General tab: Allow Item Abilities is OFF" or "equipped-item ability")
    end

    -- 4. Redundancy (full drop)
    if RedundancyFilter and RedundancyFilter.IsSpellRedundant then
        local redundant, reason = RedundancyFilter.IsSpellRedundant(displayID, profile)
        line("Not redundant", not redundant, redundant and (reason or "hidden by the redundancy filter") or nil)
    end

    -- 5. Sink signals (reorder to the back of the queue, never a drop). Uses the
    -- queue's OWN exported predicates so this report matches what the build did.
    local ready, readySource = BlizzardAPI.IsSpellReady(displayID)
    line("Off cooldown", ready, readySource .. (ready and "" or " - sinks behind ready abilities"))
    local unusableHard = SpellQueue.IsUnusableNonResource and SpellQueue.IsUnusableNonResource(displayID)
    local _, noRes = BlizzardAPI.IsSpellUsable(displayID, true)
    line("Usable", not unusableHard,
        unusableHard and "form/stance/conditions block it right now - sinks behind usable abilities"
        or (noRes and "only lacking resources (does not sink)" or nil))
    local outOfRange = SpellQueue.IsConfirmedOutOfRange and SpellQueue.IsConfirmedOutOfRange(displayID) or false
    if outOfRange then
        line("In range of target", false, "sinks behind in-range abilities")
    else
        note("Range: in range, no range requirement, or unreadable (does not sink)")
    end
    local dotParked = DotTracker and DotTracker.IsDotActiveOnCurrentTarget
        and DotTracker.IsDotActiveOnCurrentTarget(displayID) or false
    if dotParked then
        line("DoT not already on target", false,
            "active on target - parked at the back; returns for the pandemic refresh window")
    end
    local heldUntilCharged = SpellQueue.IsHeldUntilCharged
        and SpellQueue.IsHeldUntilCharged(spellID) or false
    if heldUntilCharged then
        line("Charges banked", false,
            "Hold Until Charged is on for this ability - parked at the back until every "
            .. "charge is back")
    end

    -- SimC ordering context (blended: context fit first, SimC theorycraft rank refines)
    if profile.contextOrder == "simc" then
        local RI = LibStub("JustAC-RotationImport", true)
        local rec = RI and RI.GetEntry and RI.GetEntry(spellID)
        local ctx = SpellQueue.DebugRankSpell and SpellQueue.DebugRankSpell(spellID)
        local ctxNote = ctx and (" (context fit " .. ctx .. ", lower = closer to Blizzard's pick)") or ""
        addon:Print(rec
            and ("  SimC ordering: context fit first, then theorycraft rank #" .. tostring(rec.rank)
                 .. " as a tiebreaker" .. ctxNote)
            or ("  SimC ordering: not in the imported list - sorts by context fit, after ranked "
                 .. "abilities in the same fit" .. ctxNote))
    end

    -- Live verdict: where is it right now?
    local maxIcons = (SpellQueue.GetEffectiveMaxIcons and SpellQueue.GetEffectiveMaxIcons(profile))
        or profile.maxIcons or 4
    local queue = SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue()
    local found
    if type(queue) == "table" then
        for i = 1, #queue do
            local q = queue[i]
            if not BlizzardAPI.IsSecretValue(q)
               and (q == spellID or q == displayID or q == effectiveID) then
                found = i
                break
            end
        end
    end
    if found then
        addon:Print("  |cff2ecc71Currently shown|r at queue position " .. found .. ".")
    elseif not avail or blk then
        addon:Print("  |cffff6666Not shown|r - see the FAIL line above.")
    elseif not ready or unusableHard or outOfRange or dotParked then
        local capNote = (cqLen and cqLen > maxIcons)
            and (" Your list has " .. cqLen .. " entries but only " .. maxIcons
                .. " icons are shown - raise Max Icons (Standard Queue tab) or trim the list.")
            or ""
        addon:Print("  |cffff6666Not visible right now|r - it sank to the back (see FAIL lines) and didn't fit the "
            .. maxIcons .. " shown icons." .. capNote)
    else
        addon:Print("  Not in this queue build - it may be the AC slot itself (position 1 is unreadable in combat), "
            .. "or a duplicate of a spell already shown.")
    end
    addon:Print("==============================")
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
    local defensiveIcons = addon.defensiveIcons or {}
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

        -- Fallback: client name→ID resolver (replaces a 500k-ID brute-force scan
        -- that hitched the client for seconds)
        if not spellID and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
            spellID = C_Spell.GetSpellIDForSpellIdentifier(spellName)
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
    addon:Print("Target CC-immune: " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetCCImmune and BlizzardAPI.IsTargetCCImmune())
        .. "  (signal: " .. tostring(BlizzardAPI and BlizzardAPI.GetCCImmuneSignal and BlizzardAPI.GetCCImmuneSignal()) .. ")")
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
                -- spellId/name are secret in combat; SafeSecret pcalls the tostring.
                addon:Print("  [" .. i .. "] ID:" .. SafeSecret(auraData.spellId) .. " Name:" .. SafeSecret(auraData.name))
            end
        end
    else
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
            if not name and not spellId then break end
            count = count + 1
            if count <= 20 then
                addon:Print("  [" .. i .. "] ID:" .. SafeSecret(spellId) .. " Name:" .. SafeSecret(name))
            end
        end
    end
    addon:Print("  Total buffs: " .. count)

    addon:Print("==============================")
end

--------------------------------------------------------------------------------
-- Burst-Ready Cue Diagnostics
--------------------------------------------------------------------------------
function DebugCommands.BurstDiagnostics(addon)
    addon:Print("=== Burst-Ready Cue Diagnostics ===")

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)

    local specKey = SpellDB and SpellDB.GetSpecKey and SpellDB.GetSpecKey()
    addon:Print("Spec key: " .. (specKey or "|cffff0000unknown|r"))

    local profile = addon and addon.db and addon.db.profile
    local cueOn = profile and profile.burstCueGlow == true
    addon:Print("Cue glow: " .. (cueOn and "|cff00ff00ON|r" or "|cff888888off (default)|r"))

    -- Effective trigger list: cue fires when one of these is visible in the queue
    -- and off cooldown (ready-but-absent triggers get pinned to the tail).
    -- Source chain: profile override -> SimC sync anchors -> curated defaults.
    addon:Print("")
    local defaults, source
    if SpellQueue and SpellQueue.GetBurstTriggerInfo then
        defaults, source = SpellQueue.GetBurstTriggerInfo()
    end
    addon:Print("Burst Triggers (" .. (specKey or "?") .. ", source: "
        .. (source or "|cff888888none|r") .. "):")
    if defaults and #defaults > 0 then
        for i, spellID in ipairs(defaults) do
            local name = "?"
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then name = spellInfo.name end

            local resolvedID = BlizzardAPI and BlizzardAPI.ResolveSpellID and BlizzardAPI.ResolveSpellID(spellID) or spellID
            local resolvedTag = (resolvedID ~= spellID) and (" -> " .. resolvedID) or ""

            local known = BlizzardAPI and BlizzardAPI.IsSpellAvailable and BlizzardAPI.IsSpellAvailable(resolvedID)
            local knownTag = known and "|cff00ff00known|r" or "|cffff6666not known|r"

            local stateTag = ""
            if known then
                local onCd = BlizzardAPI and BlizzardAPI.IsSpellOnCooldown and BlizzardAPI.IsSpellOnCooldown(resolvedID)
                stateTag = onCd and " |cffff6600on CD|r" or " |cff00ff00READY|r"
                -- The cue table is keyed by the QUEUE entry id (display form) plus the
                -- raw AC pick - probe all three forms so this mirrors the runtime keys.
                local displayID = BlizzardAPI and BlizzardAPI.GetDisplaySpellID
                    and BlizzardAPI.GetDisplaySpellID(resolvedID) or resolvedID
                if SpellQueue and SpellQueue.IsBurstCue
                   and (SpellQueue.IsBurstCue(spellID) or SpellQueue.IsBurstCue(resolvedID)
                        or SpellQueue.IsBurstCue(displayID)) then
                    stateTag = stateTag .. " |cffb048f8CUED|r"
                end
            end

            addon:Print("  " .. i .. ". " .. name .. " (" .. spellID .. resolvedTag .. ") " .. knownTag .. stateTag)
        end
    else
        addon:Print("  |cff888888(none defined for this spec)|r")
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

    -- Class maintained buffs (poisons/shields): dump the AC demand chain the picks
    -- defer to, so a wrong pick can be traced to its source (api read / queue head /
    -- rotation list / default fallback).
    local class = select(2, UnitClass("player"))
    local groups = SpellDB.CLASS_MAINTAINED_BUFFS and class
        and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function SpellName(id)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name or "spell") .. " (" .. id .. ")"
    end
    local anyNext = BAPI and BAPI.GetAnyNextCastSpell and BAPI.GetAnyNextCastSpell()
    local SQ = LibStub("JustAC-SpellQueue", true)
    local queue = SQ and SQ.GetCurrentSpellQueue and SQ.GetCurrentSpellQueue()
    local head = type(queue) == "table" and queue[1] or nil
    if head and issecretvalue and issecretvalue(head) then head = nil end
    if groups then
        addon:Print("---- class buffs (AC deference) ----")
        addon:Print("  AC demand: api(any)=" .. (anyNext and SpellName(anyNext) or "|cff888888nil|r")
            .. "  queue[1]=" .. (head and SpellName(head) or "|cff888888nil|r"))
        local rot = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
        for gi, grp in ipairs(groups) do
            local inRot = {}
            for _, id in ipairs(grp.group) do
                if rot then
                    for i = 1, #rot do
                        if rot[i] == id then inRot[#inRot + 1] = SpellName(id) break end
                    end
                end
            end
            addon:Print(string.format("  group %d: rotation-listed: %s", gi,
                #inRot > 0 and table.concat(inRot, ", ") or "|cff888888none|r"))
        end
        for _, s in ipairs(Engine.GetMissingClassBuffs(addon.db.profile.precombatBuffs.topoffHeal) or {}) do
            addon:Print("  offering: " .. SpellName(s))
        end
    end

    -- TEMPORARY probe: Paladin Auras as maintained-buff candidates. A data audit
    -- (2026-08-09) found 465/32223/183435 fit the maintained-group pattern, but
    -- Auras are stance-style toggles - before adding a PALADIN group we must see
    -- (a) whether the by-cast-id aura probe detects an active Aura (else the group
    -- would false-nag every paladin), and (b) whether AC ever demands one (the
    -- demand line above). Run with each Aura active in turn, and once with none.
    if class == "PALADIN" then
        addon:Print("---- paladin aura probe ----")
        addon:Print("  AC demand: api(any)=" .. (anyNext and SpellName(anyNext) or "|cff888888nil|r")
            .. "  queue[1]=" .. (head and SpellName(head) or "|cff888888nil|r"))
        local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        for _, id in ipairs({ 465, 32223, 183435 }) do
            local a = get and get(id)
            addon:Print(string.format("  %s known=%s auraByCastId=%s", SpellName(id),
                tostring(IsPlayerSpell(id)), a and "|cff00ff00YES|r" or "|cffff6666no|r"))
        end
        -- Discovery dump: every readable helpful aura on the player, so a differing
        -- aura id (cast id != aura id) shows up by name.
        local auras = BAPI and BAPI.GetAuras and BAPI.GetAuras("player", "HELPFUL")
        if auras then
            for i = 1, #auras do
                local sid, nm = auras[i].spellId, auras[i].name
                if sid and not (issecretvalue and issecretvalue(sid))
                   and not (nm and issecretvalue and issecretvalue(nm)) then
                    addon:Print("  helpful: " .. tostring(nm) .. " (" .. sid .. ")")
                end
            end
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
        for _, s in ipairs(Engine.GetMissingClassBuffs(addon.db.profile.precombatBuffs.topoffHeal) or {}) do
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
    if profile and profile.contextOrder == "off" then
        addon:Print("|cffffff00Context ordering is OFF - ranks below are not applied.|r")
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
-- DoT Tracker Diagnostics
--------------------------------------------------------------------------------
--- Dumps the maintained-DoT tracking state for the current target: which tracked
--- DoTs are considered live (sunk), whether presence is confirmed via the aura
--- instance bridge or the post-cast window, and the pandemic-refresh countdown.
--- Every value is non-secret (our own cast timing + NeverSecret instance IDs).
function DebugCommands.DotDiagnostics(addon)
    local DotTracker = LibStub("JustAC-DotTracker", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    if not DotTracker or not DotTracker.DebugState then
        addon:Print("|cffff0000DotTracker not loaded|r")
        return
    end

    local function spellName(id)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        return (info and info.name) or "?"
    end

    local s = DotTracker.DebugState()
    addon:Print("=== Maintained DoT Tracking (current target) ===")
    addon:Print(string.format("Target: %s  |  pending casts: %d",
        s.hasTarget and "yes" or "|cff888888none|r", s.pending))
    if not s.hasTarget then
        addon:Print("|cff888888(no target)|r")
        addon:Print("================================")
        return
    end
    if #s.entries == 0 then
        addon:Print("  |cff888888No tracked DoTs applied to this target.|r")
        addon:Print("================================")
        return
    end
    for _, e in ipairs(s.entries) do
        local est = SpellDB and SpellDB.GetTargetDotDuration and SpellDB.GetTargetDotDuration(e.spellID)
        addon:Print(string.format("  %s (%d)  %s  src=%s  expiresIn=%.1fs%s  est=%s",
            spellName(e.spellID), e.spellID,
            e.active and "|cffff5555SUNK|r" or "|cff55ff55shown|r",
            e.confirmed and "instance" or "window",
            e.expiresIn,
            e.pandemicIn and string.format("  pandemicIn=%.1fs", e.pandemicIn) or "",
            est and (est .. "s") or "unknown"))
    end
    addon:Print("================================")
end

--------------------------------------------------------------------------------
-- SimC Gate Diagnostics
--------------------------------------------------------------------------------
--- /jac inspect gates - SimC gate layer: the self-buff-window tracker plus a LIVE
--- per-entry gate evaluation for the current spec. Run it in combat to watch the
--- secret-safe signals (cooldown / dot / proc / buff-window) actually fire, so we
--- can tell whether the gate layer works against the 12.0 secret limits or silently
--- does nothing.
function DebugCommands.GateDiagnostics(addon)
    local RI = LibStub("JustAC-RotationImport", true)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local DotTracker = LibStub("JustAC-DotTracker", true)
    if not (RI and RI.HasRotation and RI.HasRotation()) then
        addon:Print("|cffff6600No SimC gate data for this spec.|r")
        return
    end

    local function nm(id)
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        return (n or "?") .. " (" .. tostring(id) .. ")"
    end

    addon:Print("|cff00ccff== SimC gate diagnostics ==|r")

    -- Buff windows the AC pick IMPLIES - revealed even when the aura is secret (the probe below
    -- can't see secret auras). Siblings gated on these promote off the pick.
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local pickWindows = (SpellQueue and SpellQueue.DebugContextState and SpellQueue.DebugContextState() or {}).pickWindows
    if pickWindows and next(pickWindows) then
        local names = {}
        for id in pairs(pickWindows) do names[#names + 1] = nm(id) end
        addon:Print("|cffffff00AC pick implies window up:|r " .. table.concat(names, ", "))
    end

    -- Self-buff windows (engine-truth via duration-object probe).
    local stList = RI.GetRotation and RI.GetRotation("st")
    local snap = stList and BAPI and BAPI.GetBuffWindowSnapshot and BAPI.GetBuffWindowSnapshot(stList)
    if snap and #snap > 0 then
        addon:Print("|cffffff00Self-buffs on the ST list:|r")
        for _, w in ipairs(snap) do
            addon:Print(string.format("  %s  %s", nm(w.id),
                w.active and "|cff00ff00ACTIVE|r" or "|cff888888--|r"))
        end
    end

    -- Live per-entry gate evaluation for each context.
    local function gateStr(e)
        if not e.gates or #e.gates == 0 then
            return e.delegated and "|cff888888delegated, no gates|r" or "no gates"
        end
        local parts, negBlocked = {}, false
        for _, g in ipairs(e.gates) do
            if g.t == "cd" then
                local ok = BAPI.IsSpellReady and BAPI.IsSpellReady(e.id)
                parts[#parts + 1] = "cd=" .. (ok and "|cff00ff00rdy|r" or "|cffff6600cd|r")
            elseif g.t == "dot" then
                local live = DotTracker and DotTracker.IsDotActiveOnCurrentTarget
                    and DotTracker.IsDotActiveOnCurrentTarget(g.id)
                parts[#parts + 1] = "dot=" .. (live and "|cffff6600up|r" or "|cff00ff00refresh|r")
            elseif g.t == "proc" then
                local ok = BAPI.IsSpellProcced and BAPI.IsSpellProcced(e.id)
                parts[#parts + 1] = "proc=" .. (ok and "|cff00ff00Y|r" or "|cff888888n|r")
            elseif g.t == "buff" then
                local ok = BAPI.IsBuffWindowActive and BAPI.IsBuffWindowActive(g.id)
                local viaPick = pickWindows and pickWindows[g.id]
                local state = ok and "|cff00ff00up|r"
                    or (viaPick and "|cff00ff00up(pick)|r" or "|cff888888--|r")
                if g.neg and ok then negBlocked = true end
                parts[#parts + 1] = (g.neg and "!" or "") .. "buff[" .. tostring(g.id) .. "]=" .. state
            elseif g.t == "targets" then
                parts[#parts + 1] = "|cff888888targets|r"
            elseif g.t == "execute" then
                parts[#parts + 1] = "|cff888888execute|r"
            end
        end
        local s = table.concat(parts, " ")
        if negBlocked then s = s .. " |cffff6600[neg-blocked]|r" end
        if e.delegated then s = s .. " |cff888888[deleg]|r" end
        return s
    end

    for _, ctx in ipairs({ "st", "aoe" }) do
        local entries = RI.GetRotationGated and RI.GetRotationGated(ctx)
        if entries then
            addon:Print("|cffffff00" .. ctx:upper() .. ":|r")
            for _, e in ipairs(entries) do
                addon:Print("  " .. nm(e.id) .. "  " .. gateStr(e))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Duration-object boolean probe (secret-safe readiness)
--------------------------------------------------------------------------------
--- /jac inspect durprobe [spell] - verify the scratch-Cooldown IsShown() technique:
--- feed a DurationObject (real cooldown / self-buff aura) into a hidden Cooldown
--- frame and read IsShown() as a plain, branchable boolean. The remaining TIME stays
--- secret, but the active/inactive boolean is readable - which is all a gate needs.
--- Run it in combat with a cooldown down and a self-buff up to confirm both read
--- correctly; this boolean is the foundation the SimC gate layer will branch on.
function DebugCommands.DurationProbe(addon, arg)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function sec(v)
        return (BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v)) and true or false
    end

    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        addon:Print("|cffff6600C_Spell.GetSpellCooldownDuration unavailable - can't probe|r")
        return
    end

    -- Reusable Cooldown frame under a HIDDEN holder (never renders). Its shown state
    -- is driven by SetCooldownFromDurationObject, so IsShown() is a plain boolean =
    -- "cooldown/aura active" without ever reading the secret remaining time.
    local scratch = DebugCommands._durScratch
    if not scratch then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        scratch = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
        DebugCommands._durScratch = scratch
    end
    local function durActive(durObj)
        if durObj == nil or not scratch.SetCooldownFromDurationObject then return nil end
        scratch:SetCooldownFromDurationObject(durObj)
        local shown = scratch:IsShown()
        scratch:SetCooldown(0, 0)
        return shown
    end
    local function boolTag(b, t, f)
        if b == nil then return "|cff888888nil|r" end
        return b and ("|cff00ff00" .. t .. "|r") or ("|cffcccccc" .. f .. "|r")
    end
    local function nm(id)
        local n = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        return (n or "?") .. " (" .. tostring(id) .. ")"
    end

    addon:Print("|cff00ccff== duration-object boolean probe ==|r")
    addon:Print("combat: " .. (UnitAffectingCombat("player")
        and "|cff00ff00YES|r" or "|cff888888no (probe is only meaningful in combat)|r"))

    -- Which spells: explicit arg, else AC's rotation list (first 6).
    local ids = {}
    if arg and arg ~= "" then
        local id = tonumber(arg)
        if not id and C_Spell.GetSpellIDForSpellIdentifier then
            id = C_Spell.GetSpellIDForSpellIdentifier(arg)
        end
        if id then ids[1] = id end
    end
    if #ids == 0 and BAPI and BAPI.GetRotationSpells then
        local list = BAPI.GetRotationSpells()
        if list then for i = 1, math.min(6, #list) do ids[i] = list[i] end end
    end
    if #ids == 0 then
        addon:Print("no spells to probe - pass a spellID/name, or use a spec with a rotation")
        return
    end

    addon:Print("|cffffff00Cooldown (ignore-GCD duration object -> IsShown):|r")
    for _, id in ipairs(ids) do
        local onCD = durActive(C_Spell.GetSpellCooldownDuration(id, true))
        -- Cross-check the numeric API so you can see what is secret vs. what we read.
        local numStr = "no data"
        local ci = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
        if ci then
            local st, act = ci.startTime, ci.isActive
            numStr = sec(st) and "|cffff6600startTime SECRET|r" or ("startTime=" .. tostring(st))
            if not sec(act) and act ~= nil then
                numStr = numStr .. " isActive=" .. tostring(act)
            end
        end
        local secrecy = C_Secrets and C_Secrets.GetSpellCooldownSecrecy
            and C_Secrets.GetSpellCooldownSecrecy(id)
        addon:Print(string.format("  %-26s probe=%s  %s%s", nm(id),
            boolTag(onCD, "ON-CD", "ready"), numStr,
            secrecy ~= nil and ("  secrecy=" .. tostring(secrecy)) or ""))
    end

    -- Direct method sweep (68887 audit): the docs claim IsActive/IsZero/HasStarted/
    -- HasExpired/HasSecretValues return PLAIN booleans even on a secret-backed
    -- duration object. If IsActive() reads plain in combat and agrees with the
    -- scratch probe, it supersedes the scratch-Cooldown technique entirely.
    local function methodSweep(label, durObj, scratchResult)
        if durObj == nil then
            addon:Print("  " .. label .. ": |cff888888no duration object|r")
            return
        end
        local parts = {}
        for _, m in ipairs({ "IsActive", "IsZero", "HasStarted", "HasExpired", "HasSecretValues" }) do
            local fn = durObj[m]
            if type(fn) ~= "function" then
                parts[#parts + 1] = m .. "=|cff888888absent|r"
            else
                local ok, v = pcall(fn, durObj)
                if not ok then
                    parts[#parts + 1] = m .. "=|cffff6600THREW|r"
                elseif sec(v) then
                    parts[#parts + 1] = m .. "=|cffff6600SECRET|r"
                else
                    parts[#parts + 1] = m .. "=|cff00ff00" .. tostring(v) .. "|r"
                end
            end
        end
        addon:Print(string.format("  %s: %s  (scratch says %s)", label,
            table.concat(parts, " "), tostring(scratchResult)))
    end
    addon:Print("|cffffff00DurationObject method sweep (plain per 68887 docs - verify):|r")
    do
        local id = ids[1]
        local durObj = C_Spell.GetSpellCooldownDuration(id, true)
        methodSweep("cd " .. nm(id), durObj, durActive(durObj))
    end

    addon:Print("|cffffff00Self-buffs present (aura duration object -> IsShown):|r")
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetAuraDuration) then
        addon:Print("  |cffff6600C_UnitAuras.GetAuraDuration unavailable|r")
        return
    end
    local anyAura = false
    for _, id in ipairs(ids) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
        local instId = aura and aura.auraInstanceID
        if instId then
            local durObj = C_UnitAuras.GetAuraDuration("player", instId)
            local active = durActive(durObj)
            addon:Print(string.format("  %-26s probe=%s", nm(id), boolTag(active, "ACTIVE", "expired")))
            if not anyAura then -- method sweep on the first aura duration object only
                methodSweep("aura " .. nm(id), durObj, active)
            end
            anyAura = true
        end
    end
    if not anyAura then
        addon:Print("  |cff888888(none of the probed spells are active self-buffs right now)|r")
    end
    addon:Print("|cff888888Goal: in combat, numeric SECRET but probe still reads ON-CD/ready + ACTIVE.|r")
end

--------------------------------------------------------------------------------
-- Enrage-detection probe
--------------------------------------------------------------------------------
--- /jac inspect enrage [off] - validate the DispelType==9 (Enrage) secret-safe path.
--- dispelName hides Enrage, but GetAuraDispelTypeColor maps an aura's NUMERIC dispel
--- type (9 = Enrage) through a color curve; auraInstanceID is NeverSecret, and the
--- combat-secret color sinks into SetVertexColor (AllowedWhenTainted) with no read.
--- This arms a LIVE on-screen row - one slot per target buff - each slot lit WHITE ==
--- that buff is a DispelType-9 enrage. Pull a confirmed-soothe-able mob and watch a
--- slot light up: that is the whole "target enraged -> Soothe cue" chain, proven, with
--- zero reads. The text scan also decodes each buff's type where readable (OOC) to
--- calibrate the number line (a Magic buff -> type=1 == its dispelName).
--- '/jac inspect enrage off' hides the row.
function DebugCommands.EnrageProbe(addon, arg)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function sec(v)
        return (BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v)) and true or false
    end

    local cu       = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    local gadtc    = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
    local gadbi    = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not (cu and cu.CreateColorCurve and stepType and CreateColor and gadtc and gadbi) then
        addon:Print("|cffff6600Missing API (need CreateColorCurve + LuaCurveType.Step + GetAuraDispelTypeColor)|r")
        return
    end

    if arg == "off" then
        if DebugCommands._enrSwatch then DebugCommands._enrSwatch:Hide() end
        addon:Print("enrage live indicator hidden.")
        return
    end

    addon:Print("|cff00ccff== enrage probe (DispelType 9 via GetAuraDispelTypeColor) ==|r")

    -- Selector curve the real feature uses: white/alpha 1 only when dispel type == 9.
    local sel = cu.CreateColorCurve()
    sel:SetType(stepType)
    sel:AddPoint(0,  CreateColor(0, 0, 0, 0))
    sel:AddPoint(9,  CreateColor(1, 1, 1, 1))
    sel:AddPoint(10, CreateColor(0, 0, 0, 0))

    -- Identity curve: r = dispelTypeId/32 (Step holds each point), so OOC we can read the
    -- raw dispel type back for calibration (a Magic buff should decode to 1, etc.).
    local ident = cu.CreateColorCurve()
    ident:SetType(stepType)
    for k = 0, 15 do ident:AddPoint(k, CreateColor(k / 32, 0, 0, 1)) end

    -- Text scan: decode each unit's HELPFUL auras where readable (secret in combat).
    local function scan(unit)
        if not UnitExists(unit) then return end
        addon:Print("|cffffff00" .. unit .. ":|r")
        local any = false
        for i = 1, 40 do
            local a = gadbi(unit, i, "HELPFUL")
            if not a then break end
            any = true
            local decoded, note, idc
            if pcall(function() idc = gadtc(unit, a.auraInstanceID, ident) end) and idc then
                if sec(idc.r) then note = "SECRET" else decoded = math.floor((idc.r or 0) * 32 + 0.5) end
            else
                note = "call-failed"
            end
            local name = (a.name and not sec(a.name)) and tostring(a.name) or "|cff888888?secret?|r"
            local dn   = a.dispelName
            local dnStr = (dn and not sec(dn) and dn ~= "") and (" dispelName=" .. dn) or ""
            local dtStr = decoded and ("type=" .. decoded .. (decoded == 9 and " |cffff3333<ENRAGE>|r" or ""))
                                  or ("type=|cffff6600" .. tostring(note) .. "|r")
            addon:Print(string.format("  [%s] %-20s %s%s", tostring(a.auraInstanceID), name, dtStr, dnStr))
        end
        if not any then addon:Print("  |cff888888(no HELPFUL auras)|r") end
    end
    scan("player")
    scan("target")

    -- Feature-path gates. The scans above answer "is this enrage DETECTABLE"; they say nothing
    -- about why the cue is not on screen, which is a different question with six separate ways
    -- to fail. Walk them in the order the real code does and name the first one that is false.
    addon:Print("|cff00ccff== soothe cue gates ==|r")
    local function gate(label, ok, detail)
        addon:Print(string.format("  %s %s%s", ok and "|cff00ff00PASS|r" or "|cffff3333FAIL|r",
            label, detail and (" |cff888888(" .. detail .. ")|r") or ""))
        return ok
    end

    local UISootheCue = LibStub("JustAC-UISootheCue", true)
    local SDB = LibStub("JustAC-SpellDB", true)
    local profile = addon.db and addon.db.profile

    gate("UISootheCue library loaded", UISootheCue ~= nil)
    if UISootheCue then
        gate("UISootheCue.Available() (API + selector curve)", UISootheCue.Available())
    end

    -- interruptMode "disabled" destroys the interrupt icon, and the cue is parented to it -
    -- so a disabled kick reminder silently takes the soothe cue with it.
    local mode = profile and profile.interruptMode or "kickPrefer"
    gate("interruptMode ~= disabled", mode ~= "disabled", "mode=" .. tostring(mode))
    local dm = profile and profile.displayMode or "queue"
    addon:Print(string.format("  |cff888888displayMode=%s (the standard-queue cue needs queue/both; "
        .. "overlay has its own)|r", tostring(dm)))

    local soothe = addon.resolvedSoothe
    local sid = soothe and soothe[1] and soothe[1].spellID
    if gate("ResolveSootheSpells() returned a spell", sid ~= nil,
            sid and ("spellID=" .. sid) or "nil - no known soothe for this spec") and SDB then
        -- The `live` gate inside DriveCue: an on-cooldown soothe blanks every slot, so a stuck
        -- cooldown state looks exactly like "detection broken".
        local onCD = SDB.IsInterruptOnCooldown and SDB.IsInterruptOnCooldown(sid)
        gate("soothe not on cooldown (DriveCue 'live' gate)", not onCD,
             onCD and "IsSpellReady says NOT ready" or "ready")
    end

    local intIcon = addon.interruptIcon
    gate("interrupt icon exists (cue anchor)", intIcon ~= nil)
    if intIcon then
        local cue = intIcon.sootheCue
        gate("cue frame created", cue ~= nil)
        if cue then gate("cue frame shown", cue:IsShown()) end
    end

    gate("target exists", UnitExists("target"))
    gate("target attackable", UnitExists("target") and UnitCanAttack("player", "target") or false)

    -- Live on-screen indicator: a slot per target HELPFUL aura, driven each frame by the
    -- selector via SetVertexColor. A slot lit WHITE == that buff is a DispelType-9 enrage.
    -- Works IN COMBAT: the secret color sinks straight into the fill; we never read it.
    local sw = DebugCommands._enrSwatch
    if not sw then
        sw = CreateFrame("Frame", nil, UIParent)
        sw:SetSize(8 * 30 + 12, 54)
        sw:SetPoint("CENTER", 0, 170)
        sw:SetFrameStrata("HIGH")
        local bg = sw:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
        local t = sw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("TOP", 0, -3)
        t:SetText("enrage test: a slot glows = DispelType-9 enrage   (/jac inspect enrage off)")
        sw.slots = {}
        for i = 1, 8 do
            local s = CreateFrame("Frame", nil, sw)
            s:SetSize(26, 26)
            s:SetPoint("BOTTOMLEFT", 6 + (i - 1) * 30, 5)
            local d = s:CreateTexture(nil, "BACKGROUND"); d:SetAllPoints(); d:SetColorTexture(0.16, 0.16, 0.16, 1)
            local f = s:CreateTexture(nil, "ARTWORK");    f:SetAllPoints(); f:SetColorTexture(1, 1, 1, 1)
            local l = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l:SetPoint("TOP", s, "BOTTOM", 0, -1)
            s.fill = f; s.lbl = l
            sw.slots[i] = s
        end
        DebugCommands._enrSwatch = sw
    end
    sw.sel = sel
    sw:SetScript("OnUpdate", function(self, e)
        self._t = (self._t or 0) + e
        if self._t < 0.1 then return end
        self._t = 0
        for i = 1, 8 do
            local s = self.slots[i]
            local a = UnitExists("target") and C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL") or nil
            if a then
                s:Show()
                s.lbl:SetText(tostring(a.auraInstanceID))
                pcall(function()
                    local c = C_UnitAuras.GetAuraDispelTypeColor("target", a.auraInstanceID, self.sel)
                    s.fill:SetVertexColor(c.r, c.g, c.b, c.a)
                end)
            else
                s:Hide()
            end
        end
    end)
    sw:Show()

    addon:Print("|cff888888Live row armed. Pull your confirmed-soothe-able mob - the slot for the enrage buff should glow WHITE (selector fires at type 9): full chain proven, no reads. '/jac inspect enrage off' to hide.|r")
end

--------------------------------------------------------------------------------
-- AoE-context probe
--------------------------------------------------------------------------------
--- /jac inspect aoe - Test whether we can count nearby enemies DIRECTLY (nameplate
--- enumeration + per-unit checks) without tripping 12.0 secret values, i.e. an
--- AC-independent AoE signal. Every value is tested with issecretvalue BEFORE it is
--- branched on, so the probe itself never trips a secret.
function DebugCommands.AoeDiagnostics(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function sec(v)
        return (BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v)) and true or false
    end

    addon:Print("|cff00ccff== AoE-context probe (secret-safe enemy counting) ==|r")
    local pc = UnitAffectingCombat("player")
    addon:Print("player in combat: " .. (sec(pc) and "|cffff6600SECRET|r"
        or "|cff00ff00" .. tostring(pc) .. "|r"))

    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        addon:Print("|cffff6600C_NamePlate.GetNamePlates unavailable|r")
        return
    end
    local plates = C_NamePlate.GetNamePlates()
    local total = plates and #plates or 0
    addon:Print("nameplates enumerated: " .. total
        .. "  (count secret=" .. tostring(sec(total)) .. ")")

    -- Nameplate FRAMES are restricted in 12.0 (their fields read secret/nil), so
    -- resolve via the unit TOKENS directly (nameplate1..40) and filter: hostile,
    -- then within AoE range. Range - not "in combat" - is the useful AoE proxy,
    -- since you AoE targets that are NEAR you before they're engaged.
    local nUnits, nHostile, nRange, nCombat, nThreat = 0, 0, 0, 0, 0
    local sExists, sHostile, sRange, sCombat, sThreat = false, false, false, false, false
    local RANGE_PROBE = 1822  -- Rake (melee ~5yd); placeholder AoE-range check
    for i = 1, 40 do
        local u = "nameplate" .. i
        local ex = UnitExists(u)
        if sec(ex) then
            sExists = true
        elseif ex then
            nUnits = nUnits + 1
            local ca = UnitCanAttack("player", u)   -- value first, secret-test before branching
            if sec(ca) then
                sHostile = true
            elseif ca then
                nHostile = nHostile + 1
                local r = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(RANGE_PROBE, u)
                if sec(r) then sRange = true elseif r then nRange = nRange + 1 end
                local ic = UnitAffectingCombat(u)              -- engaged with anyone
                if sec(ic) then sCombat = true elseif ic then nCombat = nCombat + 1 end
                local threatFn = _G.UnitThreatSituation         -- on its threat table = fighting ME
                if threatFn then
                    local ts = threatFn("player", u)
                    if sec(ts) then sThreat = true elseif ts ~= nil then nThreat = nThreat + 1 end
                end
            end
        end
    end

    local function line(label, n, s)
        addon:Print(string.format("  %-36s %d  %s", label, n,
            s and "|cffff6600<hit SECRET>|r" or "|cff00ff00secret-safe|r"))
    end
    line("nameplate units", nUnits, sExists)
    line("hostile (UnitCanAttack)", nHostile, sHostile)
    line("+ in melee range", nRange, sRange)
    line("+ engaged (UnitAffectingCombat)", nCombat, sCombat)
    line("+ fighting me (UnitThreatSituation)", nThreat, sThreat)

    -- Compare with AC's own context signal (the thing we're trying to replicate
    -- WITHOUT AC). AC's pick + its archetype is exactly how the queue infers AoE today.
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local pick = BAPI and BAPI.GetNextCastSpell and BAPI.GetNextCastSpell()
    local arch = pick and SpellDB and SpellDB.GetArch and SpellDB.GetArch(pick)
    addon:Print(string.format("|cffffff00AC view:|r pick=%s  archetype=|cff00ccff%s|r",
        pick and tostring(pick) or "none", tostring(arch or "?")))
    addon:Print("|cff888888Pull 1 vs 3+ mobs and re-run: does the direct hostile count track "
        .. "reality (secret-safe), and does it agree with AC's archetype?|r")
end

--------------------------------------------------------------------------------
-- Resource-inference probe
--------------------------------------------------------------------------------
--- /jac inspect resource - Test whether we can infer resource availability from
--- per-ability usability WITHOUT reading the (secret) resource value. Confirms the
--- direct UnitPower read is secret, then checks C_Spell.IsSpellUsable's
--- insufficientPower flag per rotation ability (secret-tested before use).
function DebugCommands.ResourceDiagnostics(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function sec(v)
        return (BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v)) and true or false
    end

    addon:Print("|cff00ccff== Resource-inference probe ==|r")

    -- 1. The direct read we're routing around (expected SECRET in combat).
    if UnitPower and UnitPowerType then
        local pt = UnitPowerType("player")
        local val = UnitPower("player", pt)
        addon:Print("UnitPower direct read: " .. (sec(val)
            and "|cffff6600SECRET (can't read)|r" or "|cff00ff00" .. tostring(val) .. "|r"))
    end

    -- 2. Per-ability usability: C_Spell.IsSpellUsable -> (usable, insufficientPower).
    local RI = LibStub("JustAC-RotationImport", true)
    local list = (RI and RI.GetRotation and RI.GetRotation("st"))
        or (BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells())
    if not list or #list == 0 then
        addon:Print("|cffff6600no spell list for this spec|r")
        return
    end

    -- Static resource cost per ability (NeverSecret spell data), so the ladder is visible.
    local function costStr(id)
        local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(id)
        if type(costs) ~= "table" or #costs == 0 then return "-" end
        local parts = {}
        for _, c in ipairs(costs) do
            local pn = (c.name or ""):lower():gsub("_", ""):sub(1, 6)
            parts[#parts + 1] = tostring(c.cost or "?") .. (pn ~= "" and (" " .. pn) or "")
        end
        return table.concat(parts, "+")
    end

    local anySecret = false
    addon:Print("|cffffff00ability | cost | cd | usable | resource|r")
    for _, id in ipairs(list) do
        local ready = BAPI.IsSpellReady and BAPI.IsSpellReady(id)
        local usable, noPower = C_Spell.IsSpellUsable(id)
        local secHit = sec(usable) or sec(noPower)
        if secHit then anySecret = true end
        local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or id
        local tag
        if secHit then
            tag = "|cffff6600SECRET|r"
        else
            tag = (ready and "rdy" or "|cff888888cd|r")
                .. " | " .. (usable and "|cff00ff00usable|r" or "no")
                .. " | " .. (noPower and "|cffffcc00LOW|r" or "|cff00ff00ok|r")
        end
        addon:Print(string.format("  %-20s %-12s %s", tostring(name), costStr(id), tag))
    end
    if anySecret then
        addon:Print("|cffff6600IsSpellUsable returned SECRET - resource inference not viable.|r")
    else
        addon:Print("|cff888888'LOW' = blocked by resource specifically. Spend down and re-run: "
            .. "the costliest ability still 'ok' brackets your resource - no secret read needed. "
            .. "(Pooled accumulators like combo points don't hard-gate, so they show no floor.)|r")
    end
end

--------------------------------------------------------------------------------
-- Rotation-order probe: is GetRotationSpells' tail LIVE?
--------------------------------------------------------------------------------
--- /jac inspect rotation - settle whether C_AssistedCombat.GetRotationSpells() is a LIVE
--- priority list (positions 2+ re-ordered against the secret state each call) or a static
--- rotation set where only [1] tracks the live pick. Dumps the current list beside the
--- GetNextCastSpell pick, then diffs against the previous run so you can A/B it: run, change
--- state (burn a proc, dump resources, add or drop a target), run again. If positions 2+
--- reorder between runs, Blizzard is handing us its own "what to press after slot 1" and we
--- could lean on it directly instead of inferring; if only [1] moves, only the pick is live.
--- Spell IDs and the pick are NeverSecret, so nothing here reads a secret value.
local lastRotationSnap  -- { ids = {...}, pick = id } from the previous invocation
function DebugCommands.RotationOrderProbe(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function nm(id)
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or ("spell " .. tostring(id))
    end
    if not (BAPI and BAPI.GetRotationSpells) then
        addon:Print("GetRotationSpells API unavailable")
        return
    end
    local list = BAPI.GetRotationSpells()
    local pick = BAPI.GetNextCastSpell and BAPI.GetNextCastSpell()
    if not list or #list == 0 then
        addon:Print("|cffff6600GetRotationSpells returned nothing|r - target an enemy / enter combat and retry")
        return
    end

    addon:Print(string.format("|cff00ccff== Rotation-order probe ==|r  %d entries   pick (GetNextCastSpell): %s",
        #list, pick and nm(pick) or "|cff888888none|r"))
    for i = 1, #list do
        local mark = (pick and list[i] == pick) and "  |cff2ecc71<- AC pick|r" or ""
        addon:Print(string.format("  %2d. %-26s (%d)%s", i, nm(list[i]), list[i], mark))
    end
    if pick then
        addon:Print("  [1] tracks the live pick: " .. (list[1] == pick
            and "|cff2ecc71yes|r" or "|cffff6666NO (list[1] != GetNextCastSpell)|r"))
    end

    -- Single-run verdict: an ascending-by-spell-ID list is the rotation SET sorted by id, not a
    -- priority order - so its tail carries no ranking and only GetNextCastSpell is live.
    local idSorted = true
    for i = 2, #list do
        if list[i] < list[i - 1] then idSorted = false break end
    end
    if idSorted then
        addon:Print("  |cffffd100order is ascending by spell ID|r - the id-sorted rotation SET, not a "
            .. "priority list; only GetNextCastSpell carries live priority (tail unusable for ordering)")
    end

    -- Diff vs the previous run to expose whether the TAIL re-orders with state.
    local prev = lastRotationSnap
    if prev then
        local now = {}
        for i = 1, #list do now[list[i]] = i end
        local prevSet = {}
        for i = 1, #prev.ids do prevSet[prev.ids[i]] = i end
        local addedIds, removedIds = {}, {}
        for i = 1, #list do if not prevSet[list[i]] then addedIds[#addedIds + 1] = list[i] end end
        for i = 1, #prev.ids do if not now[prev.ids[i]] then removedIds[#removedIds + 1] = prev.ids[i] end end
        -- Pair a same-NAME add+remove as one form/talent VARIANT swap (Moonfire 8921<->155625 on
        -- shifting to cat form), so it reads as a swap instead of a spurious add+remove.
        local swaps, added, removed, usedAdd = {}, {}, {}, {}
        for _, rid in ipairs(removedIds) do
            local paired = false
            for j, aid in ipairs(addedIds) do
                if not usedAdd[j] and nm(aid) == nm(rid) then
                    usedAdd[j] = true
                    swaps[#swaps + 1] = string.format("%s %d->%d", nm(rid), rid, aid)
                    paired = true
                    break
                end
            end
            if not paired then removed[#removed + 1] = nm(rid) .. " (" .. rid .. ")" end
        end
        for j, aid in ipairs(addedIds) do
            if not usedAdd[j] then added[#added + 1] = nm(aid) .. " (" .. aid .. ")" end
        end

        local sameSeq = (#list == #prev.ids)
        if sameSeq then
            for i = 1, #list do
                if list[i] ~= prev.ids[i] then sameSeq = false break end
            end
        end

        -- Tail relative-order test: among ids in BOTH prev[2..] and now, did any pair swap
        -- relative order? (excludes prev's old head, which a cast would legitimately consume).
        local commonTail = {}
        for i = 2, #prev.ids do
            if now[prev.ids[i]] then commonTail[#commonTail + 1] = prev.ids[i] end
        end
        local tailReordered = false
        for a = 1, #commonTail do
            for b = a + 1, #commonTail do
                if now[commonTail[a]] > now[commonTail[b]] then tailReordered = true break end
            end
            if tailReordered then break end
        end

        addon:Print("|cffffff00vs last run:|r")
        addon:Print("  pick: " .. (prev.pick == pick and "unchanged"
            or ("changed " .. (prev.pick and nm(prev.pick) or "none")
                .. " -> " .. (pick and nm(pick) or "none"))))
        if #swaps > 0 then addon:Print("  variant swap (same name, form/talent): " .. table.concat(swaps, ", ")) end
        if #added > 0 then addon:Print("  added: " .. table.concat(added, ", ")) end
        if #removed > 0 then addon:Print("  removed: " .. table.concat(removed, ", ")) end
        if sameSeq then
            addon:Print("  order: |cff888888identical to last run|r - change your state between runs to test")
        elseif tailReordered then
            addon:Print("  order: |cff2ecc71TAIL REORDERED|r - positions 2+ re-prioritized: evidence "
                .. "GetRotationSpells is LIVE-ordered, so its tail could feed the queue directly")
        else
            addon:Print("  order: changed, but positions 2+ kept their relative order (looks like the "
                .. "head just advanced / set changed) - no live-tail evidence this round")
        end
    else
        addon:Print("|cff888888baseline captured.|r Change your state (burn a proc, dump resources, "
            .. "add/drop a target) and run |cffffd100/jac inspect rotation|r again to see if positions 2+ move")
    end

    local ids = {}
    for i = 1, #list do ids[i] = list[i] end
    lastRotationSnap = { ids = ids, pick = pick }
end

--------------------------------------------------------------------------------
-- Class resource-point probe: can we read the resource COUNT without a secret?
--------------------------------------------------------------------------------
--- /jac inspect resourcepoints - discrete class resources (combo points, holy power, chi,
--- soul shards, runes, essence, arcane charges) are drawn as one widget PER POINT. Blizzard's
--- own bars branch on the secret UnitPower in privileged code - `point:SetActive(i <= count)`
--- - and leave the answer behind as ORDINARY frame state (an `isActive` field plus shown /
--- alpha visuals). If those read back PLAIN for an addon we get an exact resource count for
--- free, no secret touched - the same idiom as the scratch-Cooldown IsShown() readiness probe.
--- That would let the rotation actually evaluate builder/spender gates instead of delegating.
--- Dumps every point with its state + secrecy, and the derived count to eyeball against your
--- real resource. Read-only, so no taint risk.
-- Mirrors BlizzardAPI.GetClassResourcePoints' per-bar shape table. Enum semantics belong to the
-- BAR, not the field name: Paladin and DK both use `visualState` with DIFFERENT enums.
local RESOURCE_BAR_FRAMES = {
    -- 12.x PRD builds its own class frame as the global `prdClassFrame` (live whenever PRD is on).
    { "prdClassFrame", class="DRUID",   event="UNIT_POWER_FREQUENT" },
    { "prdClassFrame", class="ROGUE",   event="UNIT_POWER_FREQUENT" },
    { "prdClassFrame", class="MONK",    event="UNIT_POWER_FREQUENT" },
    { "prdClassFrame", class="WARLOCK", event="UNIT_POWER_FREQUENT" },
    { "prdClassFrame", class="MAGE",    event="UNIT_POWER_FREQUENT" },
    { "prdClassFrame", class="EVOKER",  event="UNIT_POWER_FREQUENT" },
    { "prdClassFrame", class="PALADIN", event="UNIT_POWER_FREQUENT", indexed="rune",
      state="visualState", min=1, max=3, isFilled=function(v) return v > 1 end },
    { "prdClassFrame", class="DEATHKNIGHT", event="RUNE_POWER_UPDATE", array="Runes",
      state="visualState", min=1, max=4, isFilled=function(v) return v == 4 end },
    { "DruidComboPointBarFrame", class="DRUID", event="UNIT_POWER_FREQUENT" }, { "RogueComboPointBarFrame", class="ROGUE", event="UNIT_POWER_FREQUENT" }, { "MonkHarmonyBarFrame", class="MONK", event="UNIT_POWER_FREQUENT" },
    { "WarlockPowerFrame", class="WARLOCK", event="UNIT_POWER_FREQUENT" }, { "MageArcaneChargesFrame", class="MAGE", event="UNIT_POWER_FREQUENT" }, { "EssencePlayerFrame", class="EVOKER", event="UNIT_POWER_FREQUENT" },
    { "PaladinPowerBarFrame", class="PALADIN", event="UNIT_POWER_FREQUENT", indexed = "rune", state = "visualState", min = 1, max = 3,
      isFilled = function(v) return v > 1 end },
    { "RuneFrame", class="DEATHKNIGHT", event="RUNE_POWER_UPDATE", array = "Runes", state = "visualState", min = 1, max = 4,
      isFilled = function(v) return v == 4 end },
    -- Personal Resource Display equivalents (separate globals, same shapes). These keep updating
    -- when an addon that replaces the player unit frame hides Blizzard's own bars.
    { "ClassNameplateBarFeralDruidFrame", class="DRUID", event="UNIT_POWER_FREQUENT" }, { "ClassNameplateBarRogueFrame", class="ROGUE", event="UNIT_POWER_FREQUENT" },
    { "ClassNameplateBarWindwalkerMonkFrame", class="MONK", event="UNIT_POWER_FREQUENT" }, { "ClassNameplateBarWarlockFrame", class="WARLOCK", event="UNIT_POWER_FREQUENT" },
    { "ClassNameplateBarMageFrame", class="MAGE", event="UNIT_POWER_FREQUENT" }, { "ClassNameplateBarDracthyrFrame", class="EVOKER", event="UNIT_POWER_FREQUENT" },
    { "ClassNameplateBarPaladinFrame", class="PALADIN", event="UNIT_POWER_FREQUENT", indexed = "rune", state = "visualState", min = 1, max = 3,
      isFilled = function(v) return v > 1 end },
    { "DeathKnightResourceOverlayFrame", class="DEATHKNIGHT", event="RUNE_POWER_UPDATE", array = "Runes", state = "visualState", min = 1, max = 4,
      isFilled = function(v) return v == 4 end },
}
function DebugCommands.ResourcePointProbe(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local function sec(v)
        return (BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(v)) and true or false
    end
    addon:Print("|cff00ccff== Class resource-point probe ==|r")

    -- Context: the personal resource display re-parents these same bars, so note its state.
    -- GetNamePlateForUnit's 2nd arg is includeForbidden - the personal plate is a FORBIDDEN
    -- frame, so passing false returns nil and the PRD looks "off" while plainly on screen.
    -- The CVar is the authoritative switch; also report the 12.x PRD frames directly.
    local prdOn = GetCVarBool and GetCVarBool("nameplateShowSelf")
    local function frameState(f) return f and (f:IsShown() and "|cff00ff00shown|r" or "hidden") or "|cff888888nil|r" end
    addon:Print(string.format("  personal resource display: %s   PersonalResourceDisplayFrame=%s  prdClassFrame=%s",
        prdOn and "|cff00ff00ON|r" or "|cff888888off|r",
        frameState(_G.PersonalResourceDisplayFrame), frameState(_G.prdClassFrame)))

    local found, framesSeen = 0, {}
    local _, playerClass = UnitClass("player")
    for _, def in ipairs(RESOURCE_BAR_FRAMES) do
        local name = def[1]
        -- Only this character's bars; another class's global exists but is never initialised.
        local bar = (def.class == playerClass) and _G[name] or nil
        local points = bar and bar.classResourceButtonTable
        if bar and (not points or #points == 0) and def.array then
            local a = bar[def.array]
            if type(a) == "table" and #a > 0 then points = a end
        end
        if bar and (not points or #points == 0) and def.indexed then
            points = {}
            for i = 1, 10 do
                local p = bar[def.indexed .. i]
                if not p then break end
                points[i] = p
            end
        end
        if bar then framesSeen[#framesSeen + 1] = name end
        if type(points) == "table" and #points > 0 then
            found = found + 1
            local shown = bar:IsShown()
            local reg = def.event and bar.IsEventRegistered and bar:IsEventRegistered(def.event)
            addon:Print(string.format("|cffffff00%s|r  points=%d  barShown=%s  %s=%s%s",
                name, #points, SafeSecret(shown), def.event or "evt", SafeSecret(reg),
                (shown or reg) and "" or "  |cffff6600(hidden+unregistered -> frozen)|r"))
            -- Classes store the filled flag under different names (Druid isActive, Monk active,
            -- Rogue isFull); show whichever reads as a real boolean, and which field it came from.
            local BOOL_FIELDS = { "isActive", "active", "isFull", "isCharged" }
            local FILL_FIELDS = { "fillAmount" }   -- numeric 0..1 (Warlock fractional shards)
            local active, readable, anySecret, usedField = 0, 0, false, nil
            for i = 1, #points do
                -- raw = what the widget actually stores; val = the filled-ness we derive from it.
                -- Showing both matters: a bare "visualState=0" hides whether the enum was 1 or 4.
                local p, val, from, raw = points[i], nil, nil, nil
                for _, f in ipairs(BOOL_FIELDS) do
                    local v = p and p[f]
                    if sec(v) then anySecret = true end
                    if val == nil and type(v) == "boolean" then val, from, raw = (v and 1 or 0), f, v end
                end
                for _, f in ipairs(FILL_FIELDS) do
                    local v = p and p[f]
                    if sec(v) then anySecret = true end
                    if val == nil and type(v) == "number" and v >= 0 and v <= 1 then val, from, raw = v, f, v end
                end
                if val == nil and def.state and def.isFilled then
                    local v = p and p[def.state]
                    if sec(v) then anySecret = true end
                    if type(v) == "number" and v % 1 == 0 and v >= def.min and v <= def.max then
                        val, from, raw = (def.isFilled(v) and 1 or 0), def.state, v
                    end
                end
                if val ~= nil then
                    readable = readable + 1
                    usedField = usedField or from
                    active = active + val
                end
                addon:Print(string.format("   %2d. %s raw=%s -> filled=%s  IsShown=%s  alpha=%s", i,
                    from or "|cffff6600<no readable field>|r", SafeSecret(raw), SafeSecret(val),
                    SafeSecret(p and p:IsShown()), SafeSecret(p and p:GetAlpha())))
            end
            if anySecret then
                addon:Print("   |cffff6600a point field reads SECRET - count not derivable|r")
            elseif readable == #points then
                -- %.10g, not %d: fractional fills (a partly-charged shard) are real and must show.
                addon:Print(string.format("   |cff2ecc71derived count = %.10g|r (field '%s')"
                    .. "  <- compare to your real resource; if it matches, this is readable",
                    active, tostring(usedField)))
            else
                addon:Print(string.format("   |cffff6600only %d/%d points expose a boolean flag|r"
                    .. " - this bar's shape is unmapped, so the reader returns nil (fails open)",
                    readable, #points))
            end
        end
    end
    if found == 0 then
        if #framesSeen > 0 then
            -- The frame is a CLASS-wide global, so its existence says nothing about this SPEC:
            -- it is created for every Monk but only populated for the one with chi. Zero points
            -- usually means "this spec has no such resource", not a mapping gap. Don't blame a
            -- "continuous resource" either; that misdiagnoses e.g. Holy Power, which is discrete
            -- but uses an unmapped widget layout.
            addon:Print("|cffff6600bar frame(s) present but no readable points|r: "
                .. table.concat(framesSeen, ", ")
                .. " - most likely this SPEC has no such resource (the frame is class-wide and"
                .. " stays empty), or the bar is hidden, or its widget layout is unmapped."
                .. " Fails open.")
        else
            addon:Print("|cffff6600no discrete class-resource bar found|r - this spec likely uses a"
                .. " continuous resource (energy/rage/mana), which is bar-fill rather than points.")
        end
    end
end

--------------------------------------------------------------------------------
-- Secrecy census: MEASURE what is readable instead of inferring it from source
--------------------------------------------------------------------------------
--- /jac inspect secrecy - the empirical answer to "can we read X in combat?".
--- Reading source tells us what SHOULD be secret; it has twice been wrong in our favour
--- (the scratch-Cooldown IsShown() readiness probe and the class-resource point read are
--- both unintended engine behaviour that no amount of source reading would have predicted).
--- So: actually call each candidate and measure it.
---
--- Three columns, because they can DISAGREE and the disagreement is the interesting part:
---   secret?     - what issecretvalue() claims. Safe to call on anything.
---   branchable? - whether `if v then end` actually runs. This is the measurement that
---                 matters: it is what a gate in the queue would really do.
---   comparable? - whether `v > 0` runs. Ordering is what a threshold test needs, and it
---                 can fail where plain truthiness succeeds.
--- Every probe is wrapped in pcall, so an unreadable value reports instead of erroring.
--- CONTROL CASES are included on purpose and labelled: entries we are confident are plain
--- and entries we are confident are secret. If a control comes back the wrong way, the
--- probe itself (or our whole model) is wrong - check those lines first.
--- Run it OUT of combat and again IN combat; the difference is the whole point.
-- Built ONCE at file load, deliberately NOT lazily on first probe run. Creating a frame from
-- a slash-command stack means creating it inside JustAC's taint, and if that happens in
-- combat the taint can spread through the frame hierarchy - which surfaced as an unrelated
-- addon being "blocked from an action". Load time is before any of that. Unparented for the
-- same reason: nothing here is ever shown, so it needs no parent and must not touch UIParent.
local secrecyScratchBar
do
    local f = CreateFrame("Frame")
    f:Hide()
    local bar = CreateFrame("StatusBar", nil, f)   -- native StatusBar, NOT SmoothStatusBarMixin
    bar:SetSize(100, 10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    secrecyScratchBar = bar
end

--- First active Cooldown Manager item frame, or nil. Its OnUpdate only runs while the viewer
--- is SHOWN, so a nil here means "not laid out", never "secret".
local function FirstCooldownViewerItem()
    local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer",
                      "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    for i = 1, #VIEWERS do
        local v = _G[VIEWERS[i]]
        local pool = v and v.itemFramePool
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                -- Active is not enough: items are assigned an id by layoutIndex, so a pooled
                -- frame can be active with cooldownID still nil. Require the id.
                local ok, id = pcall(function() return item and item:GetCooldownID() end)
                if ok and id then return item end
            end
        end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CLOSED 2026-07-20: the combat log is NOT available to us in 12.0.
-- Registering COMBAT_LOG_EVENT_UNFILTERED produces "AddOn 'JustAC' has been blocked" -
-- from a slash command AND from addon load, so it is a hard restriction, not taint.
-- That kills the combat log as a data source, and with it the only route to exact aura
-- STACK counts (aura.applications reads SECRET in combat; SPELL_AURA_APPLIED_DOSE would
-- have carried the count plainly). Coherent with the secret-value system: the combat log
-- would otherwise hand back every exact number secrets exist to hide.
-- Do not re-add a CLEU listener anywhere in this addon.
-- ─────────────────────────────────────────────────────────────────────────────

--- How many HELPFUL aura instances are on the player. Counting INSTANCES needs no secret
--- read: the table's presence is plain even in combat, and auraInstanceID is NeverSecret -
--- it is only the contents (spellId, applications, duration) that go secret. This is the
--- test that decides whether a stacking self-buff is countable: an aura that applies as N
--- separate instances can be counted exactly via the same bridge DotTracker already uses,
--- while one instance carrying a stack counter cannot, because the counter is secret.
local function CountPlayerAuraInstances()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local n = 0
    for i = 1, 60 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not data then break end
        n = n + 1
    end
    return n
end

--- Classify one candidate read. Never throws.
local function ClassifyRead(fn)
    local ok, v = pcall(fn)
    if not ok then
        return string.format("|cffff6600ERROR|r %s", tostring(v):gsub("^.-:%d+: ", ""):sub(1, 52))
    end
    if v == nil then return "|cff888888nil|r (absent - not evidence either way)" end

    local isSecret = (issecretvalue and issecretvalue(v)) and true or false
    -- `if v then` is ALLOWED on a secret NUMBER (its truthiness is always true, so it leaks
    -- nothing) but THROWS on a secret BOOLEAN (there, truthiness IS the secret). That is the
    -- whole rule: the engine permits exactly the operations that leak no information. So this
    -- column is only interesting when the value is a boolean.
    local branchOk = pcall(function() if v then return 1 end return 0 end)
    -- Ordering is only meaningful for numbers - `false > 0` is a TYPE error, not secrecy, and
    -- reporting that as "n" made plain booleans look blocked in the first run of this probe.
    local isNum = (type(v) == "number") or (isSecret and not pcall(function() return v == true end))
    local cmpOk = isNum and pcall(function() return v > 0 end) or false

    local shown
    if isSecret then
        shown = "|cffff6600SECRET|r"
    else
        local s = tostring(v)
        shown = "|cff2ecc71plain|r=" .. (#s > 24 and (s:sub(1, 24) .. "..") or s)
    end
    return string.format("%s [%s] branch:%s cmp:%s", shown, type(v),
        branchOk and "|cff2ecc71y|r" or "|cffff6600n THROWS|r",
        isNum and (cmpOk and "|cff2ecc71y|r" or "|cffff6600n|r") or "|cff888888-|r")
end

--- /jac inspect stacks - settle whether a stacking self-buff is N aura INSTANCES or ONE
--- instance carrying a counter. Run it OUT OF COMBAT, where spellId and applications are
--- both plain, so this reads the answer directly instead of inferring it.
--- Multi-instance -> countable in combat via the instance bridge DotTracker already uses
--- (auraInstanceID is NeverSecret). One-instance-with-counter -> dead, the counter is secret.
function DebugCommands.StacksProbe(addon)
    if InCombatLockdown() then
        addon:Print("|cffff6600Run this OUT of combat|r - in combat spellId and applications are")
        addon:Print("secret and the whole point is to read them directly.")
        return
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        addon:Print("|cffff6600C_UnitAuras unavailable|r")
        return
    end

    local bySpell, order = {}, {}
    for i = 1, 60 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not d then break end
        local sid = d.spellId
        if type(sid) == "number" then
            local e = bySpell[sid]
            if not e then
                e = { instances = 0, apps = d.applications, name = d.name, ids = {} }
                bySpell[sid] = e
                order[#order + 1] = sid
            end
            e.instances = e.instances + 1
            e.ids[#e.ids + 1] = d.auraInstanceID
        end
    end

    addon:Print("== aura stack shape (out of combat) ==")
    addon:Print("|cff888888apply a stacking buff a few times, then re-run|r")
    local multi = 0
    for _, sid in ipairs(order) do
        local e = bySpell[sid]
        -- The distinction that decides everything: more than one INSTANCE of the same
        -- spellId means each application is its own aura (countable via the bridge);
        -- one instance with applications > 1 means a secret counter (not countable).
        local shape
        if e.instances > 1 then
            shape = string.format("|cff2ecc71MULTI-INSTANCE x%d|r -> countable in combat", e.instances)
            multi = multi + 1
        elseif (e.apps or 1) > 1 then
            shape = string.format("|cffff6600STACKING counter=%d|r -> NOT countable (secret in combat)", e.apps)
        else
            shape = "single"
        end
        if e.instances > 1 or (e.apps or 1) > 1 then
            addon:Print(string.format("  %7d %-26s %s", sid, tostring(e.name):sub(1, 26), shape))
        end
    end
    addon:Print(string.format("|cff888888%d spell(s) apply as multiple instances.|r", multi))
end

function DebugCommands.SecrecyProbe(addon)
    local pf = _G.PlayerFrame
    local pfHealth = pf and (pf.healthBar or pf.healthbar)
    local ct = _G.CombatText
    local caa = _G.CombatAudioAlertManager

    -- {label, fn, note}. Order groups related hypotheses together.
    local PROBES = {
        { "-- CONTROLS (validate the probe itself) --" },
        { "LowHealthFrame:IsShown()", function() return _G.LowHealthFrame and _G.LowHealthFrame:IsShown() end,
          "expect PLAIN - we already ship this" },
        { "UnitHealth('player')", function() return UnitHealth("player") end,
          "expect SECRET in combat" },
        { "UnitHealthMax('player')", function() return UnitHealthMax("player") end },
        { "UnitPower('player')", function() return UnitPower("player") end,
          "expect SECRET in combat" },
        { "UnitPowerMax('player')", function() return UnitPowerMax("player") end },

        { "-- CURVE FAMILY (we called this closed - verify) --" },
        { "UnitHealthPercent(scaleTo100)", function()
            return UnitHealthPercent and UnitHealthPercent("player", nil,
                _G.CurveConstants and _G.CurveConstants.ScaleTo100) end },
        { "UnitPowerPercent(scaleTo100)", function()
            return UnitPowerPercent and UnitPowerPercent("player", nil,
                _G.CurveConstants and _G.CurveConstants.ScaleTo100) end },

        { "-- STATUSBAR GEOMETRY (we called this closed - verify) --" },
        { "PlayerFrame health:GetValue()", function() return pfHealth and pfHealth:GetValue() end },
        { "PlayerFrame healthTex:GetWidth()", function()
            return pfHealth and pfHealth:GetStatusBarTexture():GetWidth() end },
        { "PlayerFrame healthTex:GetTexCoord()", function()
            local a = { pfHealth:GetStatusBarTexture():GetTexCoord() }; return a[7] end,
          "the line 12.0_COMPATIBILITY says reads secret" },
        { "scratch bar GetValue() after SetValue(secret)", function()
            secrecyScratchBar:SetMinMaxValues(0, 100)
            secrecyScratchBar:SetValue(UnitHealth("player"))
            return secrecyScratchBar:GetValue() end },
        { "scratch bar texture:GetWidth()", function()
            secrecyScratchBar:SetMinMaxValues(0, UnitHealthMax("player"))
            secrecyScratchBar:SetValue(UnitHealth("player"))
            return secrecyScratchBar:GetStatusBarTexture():GetWidth() end,
          "if PLAIN: narrow the band = chooseable threshold = binary search" },
        { "scratch bar texture:IsShown()", function()
            return secrecyScratchBar:GetStatusBarTexture():IsShown() end },

        { "-- AURA TIMING (the pandemic 'close to lapsing' logic rests on this) --" },
        { "aura[1] table itself", function()
            return C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL") ~= nil end },
        { "aura[1].expirationTime", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.expirationTime end,
          "RedundancyFilter caches this OOC to compute pandemic - is that still possible?" },
        { "aura[1].duration", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.duration end },
        { "aura[1].applications (stacks)", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.applications end },
        { "aura[1].spellId", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.spellId end },

        { "-- AURA INSTANCES (does a stacking buff = N instances or 1 with a counter?) --" },
        { "player HELPFUL instance count", function() return CountPlayerAuraInstances() end,
          "cast Ironfur twice: +2 = multi-instance (countable), +1 then +0 = stacking (dead)" },
        { "aura[1].auraInstanceID", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.auraInstanceID end,
          "DotTracker relies on this being NeverSecret - verify it holds in combat" },
        { "IsAuraFilteredOutByInstanceID readable", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
            if not (a and a.auraInstanceID and C_UnitAuras.IsAuraFilteredOutByInstanceID) then return nil end
            return C_UnitAuras.IsAuraFilteredOutByInstanceID("player", a.auraInstanceID, "HELPFUL|PLAYER") end,
          "the bridge that identifies an instance as OURS without reading spellId" },

        { "-- SECRET BOOLEANS (branch:n here is the crash class) --" },
        { "aura[1].canApplyAura (bool field)", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.canApplyAura end,
          "a secret BOOLEAN throws on `if v then` - unlike a secret number" },
        { "aura[1].isHelpful (bool field)", function()
            local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL"); return a and a.isHelpful end },
        { "party1 aura presence (bool)", function()
            return C_UnitAuras.GetPlayerAuraBySpellID and
                (C_UnitAuras.GetAuraDataBySpellName and
                 C_UnitAuras.GetAuraDataBySpellName("party1", "x", "HELPFUL") ~= nil) end,
          "the shape that crashed PrecombatEngine:235" },

        { "-- ABSORB GLOWS (if/else Show/Hide -> expect PLAIN) --" },
        { "which PlayerFrame health bar exists", function()
            local pfh = _G.PlayerFrame and (_G.PlayerFrame.healthBar or _G.PlayerFrame.healthbar)
            if not pfh then return "no healthBar/healthbar" end
            local keys = {}
            for _, k in ipairs({ "overAbsorbGlow", "overHealAbsorbGlow", "healAbsorbBar",
                                "totalAbsorb", "myHealPrediction" }) do
                if pfh[k] ~= nil then keys[#keys + 1] = k end
            end
            return (#keys > 0) and table.concat(keys, ",") or "none of the absorb subwidgets"
            end,
          "tells us whether the nils below are a wrong path or a real absence" },
        { "overAbsorbGlow:IsShown()", function()
            return pfHealth and pfHealth.overAbsorbGlow and pfHealth.overAbsorbGlow:IsShown() end },
        { "overHealAbsorbGlow:IsShown()", function()
            return pfHealth and pfHealth.overHealAbsorbGlow and pfHealth.overHealAbsorbGlow:IsShown() end },
        { "healAbsorbBar.LeftShadow:IsShown()", function()
            return pfHealth and pfHealth.healAbsorbBar and pfHealth.healAbsorbBar.LeftShadow
                and pfHealth.healAbsorbBar.LeftShadow:IsShown() end,
          "SetShown(expr) -> expect SECRET. If plain, our screening rule is WRONG" },

        { "-- COMBAT TEXT (fixed 20%; needs floating combat text ON) --" },
        { "CombatText:IsVisible()", function() return ct and ct:IsVisible() end,
          "if false, lowHealth/lowMana never update - false negative" },
        { "CombatText.lowHealth", function() return ct and ct.lowHealth end },
        { "CombatText.lowMana", function() return ct and ct.lowMana end,
          "first branchable MANA signal, if it holds" },

        { "-- COMBAT AUDIO ALERTS (needs the accessibility setting + a party) --" },
        { "CAA partyHealthInfo.unitCount", function()
            return caa and caa.partyHealthInfo and caa.partyHealthInfo.unitCount end },
        { "CAA unitInfo['player'] present", function()
            return caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
                and (caa.partyHealthInfo.unitInfo["player"] ~= nil) end },
        { "CAA unitInfo['player'].frequency", function()
            return caa.partyHealthInfo.unitInfo["player"].frequency end,
          "Lerp'd from health % -> expect SECRET. If PLAIN this IS the health number" },

        { "-- COOLDOWN VIEWER pandemic window (needs Cooldown Manager shown) --" },
        { "cooldown viewer item found", function()
            local it = FirstCooldownViewerItem(); return it ~= nil end,
          "if false, everything below is nil for layout reasons, not secrecy" },
        { "item.PandemicIcon (aura in pandemic)", function()
            local it = FirstCooldownViewerItem(); return it and (it.PandemicIcon ~= nil) end,
          "if PLAIN this is a remaining-TIME threshold the cd probe cannot give" },
        { "item:GetCooldownID()", function()
            local it = FirstCooldownViewerItem(); return it and it:GetCooldownID() end,
          "the plain join key - layout data" },
        { "item:GetSpellID()", function()
            local it = FirstCooldownViewerItem(); return it and it:GetSpellID() end,
          "expect SECRET while an aura is active - do NOT join on this" },

        { "-- UNIT API SIBLINGS --" },
        { "UnitGetTotalAbsorbs('player')", function() return UnitGetTotalAbsorbs("player") end },
        { "UnitGetTotalHealAbsorbs('player')", function() return UnitGetTotalHealAbsorbs("player") end },
        { "UnitStagger('player')", function() return UnitStagger("player") end },
        { "UnitThreatSituation('player','target')", function()
            return UnitThreatSituation("player", "target") end },
        { "UnitIsDeadOrGhost('target')", function() return UnitIsDeadOrGhost("target") end },
    }

    addon:Print("== secrecy census ==  |cff2ecc71plain|r/|cffff6600SECRET|r, branch = `if v then`, cmp = `v > 0`")
    addon:Print(string.format("  in combat: %s   issecretvalue available: %s",
        InCombatLockdown() and "|cff2ecc71YES|r" or "|cffff6600no - rerun IN combat|r",
        issecretvalue and "yes" or "|cffff6600NO|r"))

    for i = 1, #PROBES do
        local p = PROBES[i]
        if not p[2] then
            addon:Print("|cff66ccff" .. p[1] .. "|r")
        else
            local note = p[3] and ("  |cff888888// " .. p[3] .. "|r") or ""
            addon:Print(string.format("  %-38s %s%s", p[1], ClassifyRead(p[2]), note))
        end
    end
    addon:Print("|cff888888Run once OUT of combat and once IN combat - the delta is the finding.|r")
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

    -- Print-safe conversion; "<secret>" for secret values (shared helper).
    local safe = SafeSecret

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

    -- Convert any value to a print-safe string (shared helper): "<secret>" for secret
    -- values, secret-tainted strings, or anything tostring can't handle - never lets a
    -- secret reach AceConsole's concat (which errors on secrets).
    local safe = SafeSecret

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
        local BlizzardAPI = LibStub and LibStub("JustAC-BlizzardAPI", true)
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
    -- We match back to the current target via SafeUnitIsUnit - UnitIsUnit is NOT non-secret.
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    f:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")

    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Log only if it pertains to the current target, whatever token the game used.
            -- These events are registered WITHOUT a unit filter, so `unit` can be a COMPOUND
            -- token (eg. "boss1target") - and the docs say compound comparisons are ALWAYS
            -- secret, on any map, not just restricted ones. Unreadable defaults to false:
            -- this is a diagnostic, so skipping an entry beats throwing mid-probe.
            if unit and BlizzardAPI and BlizzardAPI.SafeUnitIsUnit
                and BlizzardAPI.SafeUnitIsUnit(unit, "target", false) then
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
    -- Lives in C_Spell, NOT C_UnitAuras. Probing the wrong namespace called a nil field, and
    -- the resulting error was recorded as "the API throws" - a false negative. Verify before
    -- concluding anything about this function's availability.
    add("aura.maxStacksIronfur", function() return C_Spell.GetSpellMaxCumulativeAuraApplications(192081) end)

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

    -- Loss of control: the defensive queue skips its castability gate while CC'd
    -- (a stun reports the whole book uncastable). That rests on the active count
    -- being plainly readable - if this ever classes secret, the queue silently
    -- reverts to hiding every defensive for the CC's duration.
    add("loc.activeCount", function()
        return C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount()
    end)
    add("loc.gate", function()
        local B = LibStub("JustAC-BlizzardAPI", true)
        return B and B.IsLossOfControlActive and B.IsLossOfControlActive()
    end)
    -- A bar-swapping debuff reports NO loss-of-control entry, so loc.gate above stays false
    -- while every ability is uncastable. This is the read that catches it, and the lockout
    -- gate is what keeps the queue from being filtered away in that state.
    -- Important-cast channels. C_Spell.IsSpellImportant is the engine's own "lethal if not
    -- interrupted" flag and is AllowedWhenTainted, but an NPC's cast spell id is expected to
    -- be secret in combat, which would make the verdict secret too - display-only. These
    -- three reads decide whether a BRANCH is available (a suggestion) or only a cue:
    --   cast.importantVerdict - the verdict itself, from the target's cast id
    --   castbar.importantAnim - Blizzard's flash animation: SetPlaying(secret) is a DIFFERENT
    --                           laundering channel from SetShown, and the shape that worked
    --                           for the scratch-Cooldown readiness probe. Best hope.
    --   castbar.importantShown - predicted SECRET: Blizzard uses SetShown(expr), which the
    --                           resource sweep established does not launder.
    -- Both castbar reads need the target's own nameplate up AND Blizzard's
    -- highlightImportantCasts setting on; castbar.highlight reports whether it is.
    add("cast.importantVerdict", function()
        local id = select(9, UnitCastingInfo("target"))
        return C_Spell.IsSpellImportant(id)
    end)
    local function TargetCastBar()
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit("target")
        return np and np.UnitFrame and np.UnitFrame.castBar
    end
    add("castbar.spellID", function() return TargetCastBar().spellID end)
    add("castbar.highlight", function() return TargetCastBar().highlightImportantCasts end)
    add("castbar.importantAnim", function()
        return TargetCastBar().ImportantCastFlashAnim:IsPlaying()
    end)
    add("castbar.importantShown", function()
        return TargetCastBar().ImportantCastIndicator:IsShown()
    end)
    add("bar.override", function() return HasOverrideActionBar() end)
    add("bar.vehicle", function() return HasVehicleActionBar() end)
    add("lockout.gate", function()
        local B = LibStub("JustAC-BlizzardAPI", true)
        return B and B.IsPlayerAbilityLockout and B.IsPlayerAbilityLockout()
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

-- SecrecyLevel enum, hoisted: 0 = the direct lookup always works for that spell.
local SECRECY_LEVEL = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }

--------------------------------------------------------------------------------
-- Maintenance slot recorder (/jac inspect maintlog)
--------------------------------------------------------------------------------
-- Samples tracker state to JustACGlobal so a whole fight can be read off disk instead of
-- pasted out of chat. Intermittent faults - a tracker stuck "down" for minutes, a bind that
-- never retries - are invisible in a snapshot and obvious in a sequence.
-- SavedVariables flush on /reload or logout ONLY: play, then /reload, then read the file.
local MAINTLOG_MAX = 400          -- ~6.5 min at 1s; bounded so it cannot bloat the file
local maintLogTicker = nil
local lastMaintPayload = nil   -- change-only guard for MaintLogSample

local function MaintLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.maintLog = g.maintLog or {}
    return g.maintLog
end

--- One compact sample. Only plain values - never persist a secret, and never let a probe
--- throw: a recorder that breaks combat is worse than no recorder.
---
--- `dur` is the field that localises a swipe delay. The renderer can only draw a swipe once
--- GetDurationObject returns something, and that needs a bound instance - so:
---   inst=nil                -> the bind is late (bridge/exact-path problem)
---   inst set but dur=nil    -> bound to an instance with no duration object (wrong instance,
---                              or the aura went away)
---   inst set and dur=1      -> the data was ready and any remaining lag is the RENDERER
--- Emitted change-only by the caller, so these lines are transitions with real timestamps.
local function MaintLogSample()
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    if not (MT and MT.GetState) then return end
    local okS, state, _, inst = pcall(MT.GetState)
    if not okS then return end
    local d = (MT.GetBridgeDiag and select(2, pcall(MT.GetBridgeDiag))) or nil
    local hasDur = "?"
    if MT.GetDurationObject and type(inst) == "number" then
        local okD, dur = pcall(MT.GetDurationObject, inst)
        hasDur = (okD and dur ~= nil) and "1" or "0"
    elseif type(inst) ~= "number" then
        hasDur = "-"
    end
    -- eff = the effective duration the clock is actually using (2nd return of
    -- GetEstimatedCooldown). Logged because every projected timer is built on it, and a
    -- poisoned learnedDuration silently shortens the sweep and fires the refresh cue early -
    -- measured once at ~4.2s against Ironfur's true 7.0s. nc = projected stack count.
    local eff, nc = "-", "-"
    if MT.GetEstimatedCooldown then
        local okE, _, len = pcall(MT.GetEstimatedCooldown)
        if okE and type(len) == "number" then eff = string.format("%.1f", len) end
    end
    if MT.GetProjectedStacks then
        local okN, n = pcall(MT.GetProjectedStacks)
        if okN and type(n) == "number" then nc = tostring(n) end
    end
    local payload = string.format("%s inst=%s dur=%s eff=%s nc=%s combat=%s b=%s/%s/%s cand=%s",
        tostring(state),
        (type(inst) == "number") and tostring(inst) or "nil",
        hasDur,
        eff,
        nc,
        (UnitAffectingCombat and UnitAffectingCombat("player")) and "1" or "0",
        d and tostring(d.batches or 0) or "?",
        d and tostring(d.bound or 0) or "?",
        d and tostring(d.ambiguous or 0) or "?",
        d and tostring(d.lastCandidates or 0) or "?")
    -- Change-only: at 10/s a clock-sampled log would be all duplicates and would ring out
    -- of the interesting window in 40s. Transitions are what a latency question needs.
    if payload == lastMaintPayload then return end
    lastMaintPayload = payload
    local log = MaintLogStore()
    log[#log + 1] = string.format("%.2f %s", GetTime(), payload)
    -- Ring: drop the oldest half in one pass rather than table.remove per sample (O(n) each).
    if #log > MAINTLOG_MAX then
        local keep, half = {}, math.floor(MAINTLOG_MAX / 2)
        for i = #log - half + 1, #log do keep[#keep + 1] = log[i] end
        _G.JustACGlobal.maintLog = keep
    end
end

--- /jac inspect maintlog [on|off|clear] - record maintenance-slot state once a second.
function DebugCommands.MaintenanceLog(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.maintLog = nil end
        addon:Print("maintlog: |cffffff00cleared|r")
        return
    end
    if arg == "off" or (not arg and maintLogTicker) then
        if maintLogTicker then maintLogTicker:Cancel() end
        maintLogTicker = nil
        local n = (_G.JustACGlobal and _G.JustACGlobal.maintLog and #_G.JustACGlobal.maintLog) or 0
        addon:Print(string.format("maintlog: |cffff6600OFF|r - %d samples held.", n))
        addon:Print("|cff888888/reload to flush them to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua|r")
        return
    end
    if not C_Timer or not C_Timer.NewTicker then
        addon:Print("|cffff6600C_Timer unavailable|r")
        return
    end
    -- 10/s: the reported lag is sub-second, which 1/s sampling cannot resolve at all.
    -- Cheap because the sample is change-only (see MaintLogSample).
    lastMaintPayload = nil
    maintLogTicker = C_Timer.NewTicker(0.1, function() pcall(MaintLogSample) end)
    addon:Print("maintlog: |cff00ff00ON|r - sampling 10/s, transitions only. Press the buff a few")
    addon:Print("times (first application AND refreshes), then |cffffff00/jac inspect maintlog off|r and |cffffff00/reload|r.")
end

--- /jac inspect maintenance - can the tank maintenance slot bind its aura EXACTLY in combat,
--- instead of guessing via the cast->instance bridge? Three questions, one call:
---   Q1 Is this spec's aura secret at all? GetSpellAuraSecrecy == 0 means the direct lookup
---      always works and the bridge is dead code for that spec.
---   Q2 Is the spell in the player's Cooldown Manager tracked set? No entry -> no join.
---   Q3 Does the CDM item frame hand back a PLAIN auraInstanceID? Blizzard's viewer is
---      untainted, so it legally reads the secret spellId and caches the instance id as an
---      ordinary field - we read the materialized number, never the secret.
--- Run it IN COMBAT with the buff up: that is the only state where Q1 and Q3 mean anything.
function DebugCommands.MaintenanceProbe(addon)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    local entry = SpellDB and SpellDB.GetMaintenanceDefensive and SpellDB.GetMaintenanceDefensive()
    if not entry then
        addon:Print("|cffff6600No maintenance entry for this spec|r - tank specs only (Brewmaster absent by design)")
        return
    end

    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false
    addon:Print("== maintenance slot probe ==")
    addon:Print(string.format("cast=%d aura=%d stacks=%s combat=%s",
        entry.cast, entry.aura, tostring(entry.stacks or false), tostring(inCombat)))
    if not inCombat then
        addon:Print("|cffff6600Out of combat|r - Q1/Q3 only mean something mid-fight. Re-run with the buff up.")
    end

    -- Q1: per-spell aura secrecy.
    local CS = C_Secrets
    if CS and CS.GetSpellAuraSecrecy then
        local function Sec(id)
            local ok, lvl = pcall(CS.GetSpellAuraSecrecy, id)
            if not ok then return "err" end
            local label = (type(lvl) == "number" and SECRECY_LEVEL[lvl]) or "?"
            return SafeSecret(lvl) .. " (" .. label .. ")"
        end
        addon:Print("Q1 secrecy: aura -> " .. Sec(entry.aura) .. "   cast -> " .. Sec(entry.cast))
        addon:Print("|cff888888   0 means no bridge is needed for this spec at all|r")
        addon:Print("|cff888888   (static per-SPELL property - same answer whether the buff is up or not)|r")
    else
        addon:Print("Q1 secrecy: |cffff6600C_Secrets.GetSpellAuraSecrecy unavailable|r")
    end

    -- The direct path, for contrast: nil in combat is exactly why the bridge exists.
    local direct
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local okD, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, entry.aura)
        direct = okD and d and d.auraInstanceID or nil
    end
    addon:Print("direct GetPlayerAuraBySpellID -> " .. SafeSecret(direct))

    -- Q2/Q3. NEVER call item:GetSpellID() - it returns the SECRET auraSpellID first. Only
    -- GetCooldownInfo (static layout data) and GetAuraSpellInstanceID (already materialized
    -- plain by untainted code) are safe to touch here.
    -- Match the WHOLE associated id set against BOTH our ids: 4 of the 5 specs have
    -- cast ~= aura, so matching on one id alone would silently miss them.
    local function MatchesEntry(info)
        if type(info) ~= "table" then return false end
        local function hit(v)
            return type(v) == "number" and (v == entry.cast or v == entry.aura)
        end
        if hit(info.spellID) or hit(info.overrideSpellID)
           or hit(info.overrideTooltipSpellID) or hit(info.linkedSpellID) then return true end
        local ls = info.linkedSpellIDs
        if type(ls) == "table" then
            for i = 1, #ls do if hit(ls[i]) then return true end end
        end
        return false
    end

    -- Q2 the FRAME-INDEPENDENT way. GetCooldownViewerCategorySet is pure data - it answers
    -- "is this spell tracked at all" even when every viewer is hidden, which the frame walk
    -- below cannot. 4 categories: 0 Essential, 1 Utility, 2 TrackedBuff, 3 TrackedBar.
    local CV = C_CooldownViewer
    local trackedCooldownID = nil
    local trackedIDs = {}
    local trackedViewer = nil
    if CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo then
        local CATS = { [0] = "Essential", [1] = "Utility", [2] = "TrackedBuff", [3] = "TrackedBar" }
        local hitCat, total = nil, 0
        for cat = 0, 3 do
            local okC, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
            if okC and type(ids) == "table" then
                total = total + #ids
                for j = 1, #ids do
                    local okN, info = pcall(CV.GetCooldownViewerCooldownInfo, ids[j])
                    -- Collect EVERY category hit. The same spell carries a different
                    -- cooldownID per category, so stopping at the first found the Utility id
                    -- and missed TrackedBar, where these buffs live by default.
                    if okN and MatchesEntry(info) then
                        hitCat = (hitCat and (hitCat .. ", ") or "")
                                 .. string.format("%s=%s", CATS[cat], tostring(ids[j]))
                        if trackedCooldownID == nil and type(ids[j]) == "number" then
                            trackedCooldownID = ids[j]
                        end
                        trackedViewer = trackedViewer or ({ [0] = "EssentialCooldownViewer",
                                           [1] = "UtilityCooldownViewer",
                                           [2] = "BuffIconCooldownViewer",
                                           [3] = "BuffBarCooldownViewer" })[cat]
                        -- The real join key, as a SET: frames expose GetCooldownID() and the
                        -- spell can appear on more than one bar under different ids.
                        if type(ids[j]) == "number" then trackedIDs[ids[j]] = true end
                    end
                end
            end
        end
        if hitCat then
            -- "ELIGIBLE", not "tracked": allowUnlearned=true returns everything the category
            -- COULD contain, not the subset the player put on their bar. Q3 is what decides
            -- whether a frame actually exists. Conflating the two cost a debugging round.
            addon:Print(string.format("Q2 |cff2ecc71ELIGIBLE|r for %s  |cff888888(%d ids in category data; Q3 says if it is on the bar)|r", hitCat, total))
        else
            addon:Print(string.format("Q2 |cffff6600NOT in any category set|r |cff888888(%d ids scanned)|r", total))
            addon:Print("|cff888888   spell genuinely absent from the Cooldown Manager data -> join impossible|r")
        end
    else
        addon:Print("Q2 |cffff6600C_CooldownViewer category API unavailable|r")
    end

    -- Why the viewers may be hidden. A hidden viewer never computes auraInstanceID at all:
    -- OnShow registers UNIT_AURA, OnHide unregisters it. So Q3 REQUIRES a shown viewer.
    local okV, cvarOn = pcall(function()
        return C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("cooldownViewerEnabled")
    end)
    local okAv, avail, why = pcall(function()
        if CV and CV.IsCooldownViewerAvailable then return CV.IsCooldownViewerAvailable() end
    end)
    addon:Print(string.format("CooldownManager: cvar=%s available=%s %s",
        okV and tostring(cvarOn) or "err",
        okAv and tostring(avail) or "err",
        (okAv and why) and tostring(why) or ""))

    local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer",
                      "EssentialCooldownViewer", "UtilityCooldownViewer" }
    local found, scanned = nil, 0
    local seenIDs = {}
    for i = 1, #VIEWERS do
        local name = VIEWERS[i]
        local v = _G[name]
        local shown = (v and v.IsShown and v:IsShown()) and true or false
        local pool = v and v.itemFramePool
        local n = 0
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                n = n + 1
                scanned = scanned + 1
                -- Join on cooldownID (from the category set above), NOT on the frame's spell
                -- ids: GetCooldownID survives a hidden viewer, GetCooldownInfo appears not to.
                local okC, cid = pcall(item.GetCooldownID, item)
                if okC and type(cid) == "number" then
                    seenIDs[#seenIDs + 1] = cid
                end
                local isMatch = okC and type(cid) == "number" and trackedIDs[cid] and true or false
                if not isMatch and not next(trackedIDs) then
                    -- No cooldownID to join on: fall back to the spell-id set.
                    local okI, info = pcall(item.GetCooldownInfo, item)
                    isMatch = okI and MatchesEntry(info)
                end
                if isMatch and not found then
                    local okA, inst = pcall(item.GetAuraSpellInstanceID, item)
                    local okU, unit = pcall(item.GetAuraDataUnit, item)
                    found = {
                        viewer = name, shown = shown, cid = cid,
                        inst = (okA and type(inst) == "number") and inst or nil,
                        instStr = okA and SafeSecret(inst) or "err",
                        plain = okA and type(inst) == "number",
                        unit = okU and tostring(unit) or "err",
                    }
                end
            end
        end
        -- alpha matters as much as shown: a viewer kept SHOWN at alpha 0 stays populated
        -- (pool laid out, auraInstanceID live) while being invisible to the player. Hidden
        -- is what empties the pool, not transparent.
        local okA, av = pcall(function() return v and v.GetAlpha and v:GetAlpha() end)
        addon:Print(string.format("  %-24s shown=%-5s alpha=%-4s items=%d",
            name, tostring(shown), okA and tostring(av) or "?", n))
    end

    if not found then
        local want = {}
        for id in pairs(trackedIDs) do want[#want + 1] = tostring(id) end
        table.sort(want)
        addon:Print(string.format("Q3 |cffff6600no live item frame|r (want any of %s, %d active items walked)",
            (#want > 0) and table.concat(want, "/") or "none", scanned))
        addon:Print("|cff888888   active frame cooldownIDs: " .. table.concat(seenIDs, ",") .. "|r")
        addon:Print("|cff888888   id absent -> the viewer is not feeding ids; id present -> match logic is wrong|r")
        if trackedViewer then
            local v = _G[trackedViewer]
            local vShown = (v and v.IsShown and v:IsShown()) and true or false
            if vShown then
                addon:Print(string.format("|cffffff00   %s IS shown but our id is not on it - add the spell to that bar in Edit Mode|r",
                    trackedViewer))
            else
                -- shown=false has TWO causes and they need different fixes. This message used to
                -- assert "not laid out", which cost a debugging session when the real cause was
                -- the panel's visibility dropdown set to Always Hidden - the panel WAS laid out.
                -- JustAC is never a candidate: its own cosmetic hide only ever sets alpha 0
                -- (MaintenanceTracker.ApplyViewerAlpha), which leaves IsShown() true.
                addon:Print(string.format("|cffffff00   our id belongs to %s, which is HIDDEN. Two causes:|r", trackedViewer))
                addon:Print("|cffffff00     1. the panel's Edit Mode visibility is set to Always Hidden -> set it to Always Show|r")
                addon:Print("|cffffff00     2. the panel is not enabled in this Edit Mode layout -> enable it|r")
                addon:Print("|cff888888     Either way a hidden viewer serves no ids and cannot be revived from addon|r")
                addon:Print("|cff888888     code (Documentation/AURA_IDENTITY_12.0.md). JustAC's own hide is alpha-only|r")
                addon:Print("|cff888888     and keeps it feeding, so hide it there rather than in Edit Mode.|r")
            end
        end
    else
        addon:Print(string.format("Q3 frame |cff2ecc71MATCH|r in %s (cooldownID=%s shown=%s)",
            found.viewer, tostring(found.cid), tostring(found.shown)))
        if not found.shown then
            -- Frames keep their cooldownID after hiding (OnHide clears nothing), so a match on
            -- a hidden viewer is expected - and useless: OnHide also unregisters UNIT_AURA, so
            -- any auraInstanceID it still holds is FROZEN at hide time. The tracker rejects
            -- these; a stale id that looks valid is worse than none.
            addon:Print("|cffff6600   viewer HIDDEN - id retained but aura data is frozen; tracker ignores this|r")
        end
        addon:Print(string.format("Q3 GetAuraSpellInstanceID -> %s  plain=%s  unit=%s",
            found.instStr, tostring(found.plain), found.unit))
        if found.plain and found.unit == "player" then
            addon:Print("|cff2ecc71   IDENTITY AVAILABLE|r - exact bind works, bridge becomes fallback")
        else
            addon:Print("|cffff6600   unusable|r - nil/secret instance, or the frame is scanning another unit")
        end
    end

    -- Q4: the per-instance secrecy route - no Blizzard frame, no UI dependency at all.
    -- GetUnitAuraInstanceIDs returns a PLAIN table of ids (no secret annotation on its return,
    -- unlike GetUnitAuras which carries ConditionalSecretContents), and
    -- ShouldUnitAuraInstanceBeSecret answers per id with a plain bool. For instances it reports
    -- NON-secret, GetAuraDataByAuraInstanceID's spellId is readable and comparable - which is
    -- exact identity. sortRule is pinned to Unsorted(0): the other rules order by secret data.
    local UA, CSec = C_UnitAuras, C_Secrets
    if UA and UA.GetUnitAuraInstanceIDs and CSec and CSec.ShouldUnitAuraInstanceBeSecret then
        local okIDs, ids = pcall(UA.GetUnitAuraInstanceIDs, "player", "HELPFUL|PLAYER", nil, 0, 0)
        if okIDs and type(ids) == "table" then
            local readable, secretN, hit = 0, 0, nil
            for i = 1, #ids do
                local id = ids[i]
                local okS, isAuraSecret = pcall(CSec.ShouldUnitAuraInstanceBeSecret, "player", id)
                if okS and isAuraSecret == false then
                    readable = readable + 1
                    -- Contractually non-secret, but compare inside pcall anyway: being wrong
                    -- here throws, and this probe must never be the thing that breaks combat.
                    local okD, d = pcall(UA.GetAuraDataByAuraInstanceID, "player", id)
                    if okD and d then
                        local okC, isOurs = pcall(function()
                            return d.spellId == entry.aura or d.spellId == entry.cast
                        end)
                        if okC and isOurs and not hit then hit = id end
                    end
                elseif okS then
                    secretN = secretN + 1
                end
            end
            addon:Print(string.format("Q4 instances: %d total, %d readable, %d secret",
                #ids, readable, secretN))
            if hit then
                addon:Print(string.format("   |cff2ecc71EXACT IDENTITY|r via instance %d - no frame, no CDM needed", hit))
            elseif #ids == 0 then
                addon:Print("   |cffff6600enumerated ZERO|r - auras silently absent, not secret")
            elseif readable > 0 then
                addon:Print("   |cffff6600readable instances exist, none is ours|r - ours is among the secret set")
            else
                addon:Print("   |cffff6600every instance secret|r - route closed for this unit/filter")
            end
        else
            addon:Print("Q4 |cffff6600GetUnitAuraInstanceIDs call failed|r")
        end
    else
        addon:Print("Q4 |cffff6600per-instance secrecy API unavailable|r (needs GetUnitAuraInstanceIDs + ShouldUnitAuraInstanceBeSecret)")
    end

    -- Q5: which aura FILTERS does our buff actually match? The bridge currently asks
    -- "HELPFUL|PLAYER", which every trinket proc also satisfies - that breadth IS the mis-bind.
    -- If our aura also carries a narrower flag (BIG_DEFENSIVE is the hope), the bridge can ask
    -- for that instead and stop matching unrelated procs. Run OUT of combat, where we can
    -- resolve the true instance first: testing filters against a guessed instance proves nothing.
    do
        local UAf = C_UnitAuras
        local known = nil
        if UAf and UAf.GetPlayerAuraBySpellID then
            local okD, d = pcall(UAf.GetPlayerAuraBySpellID, entry.aura)
            known = okD and d and d.auraInstanceID or nil
        end
        -- The question is NOT "what does our aura match" - it is "does any narrower filter
        -- SEPARATE our aura from the other player-helpful auras". That is answerable without
        -- knowing which instance is ours: count how many of the whole HELPFUL|PLAYER set match
        -- each narrow token. A token matched by exactly 1 of N is a discriminating filter and
        -- can replace "HELPFUL|PLAYER" in the bridge; a token matched by all N or none is
        -- useless. This works IN COMBAT, where the exact-instance version cannot.
        local TOKENS = { "BIG_DEFENSIVE", "IMPORTANT", "EXTERNAL_DEFENSIVE", "CANCELABLE",
                         "NOT_CANCELABLE", "RAID", "RAID_IN_COMBAT", "CROWD_CONTROL" }
        if UAf and UAf.IsAuraFilteredOutByInstanceID and UAf.GetUnitAuraInstanceIDs then
            local okIDs, ids = pcall(UAf.GetUnitAuraInstanceIDs, "player", "HELPFUL|PLAYER", nil, 0, 0)
            if okIDs and type(ids) == "table" and #ids > 0 then
                local parts = {}
                for t = 1, #TOKENS do
                    local n, ourHit = 0, false
                    for i = 1, #ids do
                        local okF, out = pcall(UAf.IsAuraFilteredOutByInstanceID, "player", ids[i], TOKENS[t])
                        if okF and out == false then
                            n = n + 1
                            if known and ids[i] == known then ourHit = true end
                        end
                    end
                    if n > 0 then
                        parts[#parts + 1] = string.format("%s=%d%s", TOKENS[t], n, ourHit and "*" or "")
                    end
                end
                addon:Print(string.format("Q5 of %d player-helpful auras: %s", #ids,
                    (#parts > 0) and table.concat(parts, " ") or "|cffff6600no narrow token matches any|r"))
                addon:Print("|cff888888   a token matching exactly 1 discriminates -> use it in the bridge"
                    .. (known and "; * = confirmed ours" or "") .. "|r")
            else
                addon:Print("Q5 |cffff6600no player-helpful auras enumerated|r")
            end
        else
            addon:Print("Q5 filters: |cffff6600filter API unavailable|r")
        end
    end

    -- Bridge health. If `ambiguous` dominates `bound`, the single-candidate guard is refusing
    -- every batch and the tracker can never bind in combat - which presents as a false "down".
    if MT and MT.GetBridgeDiag then
        local okG, d = pcall(MT.GetBridgeDiag)
        if okG and type(d) == "table" then
            addon:Print(string.format("bridge: batches=%d bound=%d ambiguous=%d lastCand=%d maxCand=%d",
                d.batches or 0, d.bound or 0, d.ambiguous or 0, d.lastCandidates or 0, d.maxCandidates or 0))
            -- Needs a real sample before crying starvation: measured in game, "1 ambiguous,
            -- 0 bound" simply means the first clean batch has not arrived yet, and it bound
            -- normally seconds later. Only a sustained run of ambiguity is evidence.
            if (d.ambiguous or 0) >= 6 and (d.bound or 0) == 0 then
                addon:Print("   |cffff0000guard may be starving the bind|r - many batches, never bound")
            end
        end
    end

    -- Cross-check. A disagreement here IS the wrong-stacks bug, caught in the act.
    if MT and MT.GetState then
        local okS, state, _, inst = pcall(MT.GetState)
        if okS then
            addon:Print(string.format("tracker: state=%s instance=%s", tostring(state), SafeSecret(inst)))
            if found and found.plain and type(inst) == "number" then
                if inst == found.inst then
                    addon:Print("|cff2ecc71   AGREES with Cooldown Manager|r")
                else
                    addon:Print("|cffff0000   DISAGREES - bridge bound the WRONG aura (this is the stacks bug)|r")
                end
            end
        end
    end

    -- Q6: loss-of-control readout. Answers "why no CC break" directly - what the game reports
    -- while you are held, whether locType reads plain or secret, and what the tracker resolves.
    local LOC = C_LossOfControl
    if LOC and LOC.GetActiveLossOfControlDataCount then
        local okC, n = pcall(LOC.GetActiveLossOfControlDataCount)
        addon:Print(string.format("Q6 loss-of-control: count=%s", okC and SafeSecret(n) or "err"))
        if okC and type(n) == "number" and n > 0 and LOC.GetActiveLossOfControlData then
            for i = 1, n do
                local okD, d = pcall(LOC.GetActiveLossOfControlData, i)
                if okD and d then
                    local lt = d.locType
                    addon:Print(string.format("   [%d] locType=%s%s displayType=%s",
                        i, SafeSecret(lt),
                        BlizzardAPI and BlizzardAPI.IsSecretValue and BlizzardAPI.IsSecretValue(lt)
                            and " |cffff6600(SECRET)|r" or "",
                        SafeSecret(d.displayType)))
                end
            end
        end
        local sid, item = nil, nil
        if MT and MT.GetCCBreak then sid, item = MT.GetCCBreak() end
        local macro = MT and MT.GetCCBreakMacro and MT.GetCCBreakMacro(addon.db.profile)
        addon:Print(string.format("   resolved: spell=%s item=%s macro=%s",
            tostring(sid), tostring(item), tostring(macro)))
        -- The selected macro and whether it actually yields a keybind: "" means it is not on a
        -- bound action-bar slot, so the slot correctly shows nothing. This is the other half of
        -- "macro set but nothing appears".
        local chosen = addon.db.profile.ccBreakMacro
        if chosen and chosen ~= "" then
            local ABS = LibStub("JustAC-ActionBarScanner", true)
            local key = ABS and ABS.GetMacroHotkey and ABS.GetMacroHotkey(chosen) or "?"
            addon:Print(string.format("   macro '%s' keybind=%s%s", chosen,
                (key ~= "" and key ~= "?") and key or "|cffff6600(none - not on a bound action bar slot)|r",
                (key == "?") and " (scanner unavailable)" or ""))
        end
        if not sid and not macro then
            addon:Print("|cff888888   nothing resolved. If locType above shows a string I don't map")
            addon:Print("|cff888888   (STUN/ROOT/FEAR are UNVERIFIED guesses), that is the bug - report it.|r")
        end
    else
        addon:Print("Q6 loss-of-control: |cffff6600C_LossOfControl unavailable|r")
    end
end

--- /jac inspect locwatch - ARM a loss-of-control capture. CC is a 2-4s window that a hand-run
--- probe keeps missing, so listen for the event instead and dump the REAL data the instant it
--- lands: the actual locType string (which the source cannot confirm), whether it reads secret,
--- and whether any of our mappings/breakers resolve. This is what settles "macro set, nothing
--- shows" - get CC'd once and it prints the truth.
function DebugCommands.LossOfControlWatch(addon)
    if DebugCommands._locWatch then
        DebugCommands._locWatch:UnregisterAllEvents()
        DebugCommands._locWatch:SetScript("OnEvent", nil)
        DebugCommands._locWatch = nil
        addon:Print("|cffffff00locwatch: disarmed.|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._locWatch = f
    local armT = GetTime()
    local fires = 0
    local LOC = C_LossOfControl
    local MT = LibStub("JustAC-MaintenanceTracker", true)

    -- Scratch Cooldown for laundering a DurationObject into a plain shown-boolean.
    local function scratchShown(durObj)
        if durObj == nil then return "|cff888888nil-dur|r" end
        local sc = DebugCommands._locScratch
        if not sc then
            local holder = CreateFrame("Frame", nil, UIParent)
            holder:Hide()
            sc = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
            DebugCommands._locScratch = sc
        end
        if not sc.SetCooldownFromDurationObject then return "|cff888888no-api|r" end
        sc:SetCooldownFromDurationObject(durObj)
        local shown = sc:IsShown()
        sc:SetCooldown(0, 0)
        return tostring(shown)
    end
    -- First few rotation spells for the per-spell lockout boolean check.
    local lockoutIds = {}
    do
        local BAPI = LibStub("JustAC-BlizzardAPI", true)
        local list = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
        if list then for i = 1, math.min(3, #list) do lockoutIds[i] = list[i] end end
    end

    f:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    f:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    f:RegisterEvent("PLAYER_CONTROL_LOST")
    f:RegisterEvent("PLAYER_CONTROL_GAINED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
            addon:Print(string.format("|cff00ccff%s|r  UIParent.isOutOfControl=%s", event,
                ClassifyRead(function() return UIParent.isOutOfControl end)))
            return
        end
        if not (LOC and LOC.GetActiveLossOfControlDataCount) then return end
        local okC, n = pcall(LOC.GetActiveLossOfControlDataCount)
        if not okC or type(n) ~= "number" or n < 1 then return end
        fires = fires + 1
        addon:Print(string.format("|cff00ff00LOC fired|r (%s) count=%d combat=%s", event, n,
            tostring(UnitAffectingCombat("player"))))
        for i = 1, n do
            local okD, d = pcall(LOC.GetActiveLossOfControlData, i)
            if okD and d then
                addon:Print(string.format("  [%d] locType=%s displayType=%s spellID=%s priority=%s auraInst=%s",
                    i, SafeSecret(d.locType), SafeSecret(d.displayType), SafeSecret(d.spellID),
                    SafeSecret(d.priority), SafeSecret(d.auraInstanceID)))
                addon:Print(string.format("      timeRemaining=%s duration=%s lockoutSchool=%s",
                    ClassifyRead(function() return d.timeRemaining end),
                    ClassifyRead(function() return d.duration end),
                    ClassifyRead(function() return d.lockoutSchool end)))
            end
        end
        -- Duration object route + slows: speed is expected SECRET in combat
        -- (SecretWhenUnitStatsRestricted) - measure, don't assume.
        if LOC.GetActiveLossOfControlDuration then
            local okDur, durObj = pcall(LOC.GetActiveLossOfControlDuration, "player", 1)
            if okDur and durObj then
                addon:Print(string.format("  durObj[1]: HasSecretValues=%s scratchShown=%s",
                    ClassifyRead(function() return durObj:HasSecretValues() end), scratchShown(durObj)))
            end
        end
        addon:Print("  GetUnitSpeed(player)=" .. ClassifyRead(function() return (GetUnitSpeed("player")) end))
        for _, id in ipairs(lockoutIds) do
            local okL, li = pcall(C_Spell.GetSpellLossOfControlCooldownInfo, id)
            addon:Print(string.format("  lockout %s: isActive=%s", tostring(id),
                (okL and li) and ClassifyRead(function() return li.isActive end) or "|cff888888no-info|r"))
        end
        local sid = MT and MT.GetCCBreak and MT.GetCCBreak()
        local macro = MT and MT.GetCCBreakMacro and MT.GetCCBreakMacro(addon.db.profile)
        addon:Print(string.format("  -> resolves: spell=%s macro=%s", tostring(sid), tostring(macro)))
        if fires >= 120 or GetTime() - armT > 1800 then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._locWatch = nil
            addon:Print("|cffffff00locwatch: window ended.|r")
        end
    end)
    addon:Print("|cff00ff00=== locwatch ARMED (30min) ===|r get stunned/rooted/DAZED; it prints the real locType on the spot.")
    addon:Print("|cff888888  ALL entries dump (a snare may hide behind displayType NONE). Run again to disarm early.|r")
end

--------------------------------------------------------------------------------
-- 68887 signal-audit probes (Documentation/PROBE_PLAN_68887.md, Session 1)
--------------------------------------------------------------------------------

--- Rotation ids helper for the audit probes (first n, fail-open to empty).
local function RotationIds(n)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local list = BAPI and BAPI.GetRotationSpells and BAPI.GetRotationSpells()
    local ids = {}
    if list then for i = 1, math.min(n, #list) do ids[i] = list[i] end end
    return ids
end

--- /jac inspect selfcast - ARM a capture of the player's own cast info. Claim
--- (68887 docs): SecretWhenUnitSpellCastRestricted only fires for non-player
--- units, so UnitCastingInfo/UnitChannelInfo("player") read PLAIN in combat.
--- Cast anything (hardcast + a channel) in AND out of combat; disarm = run again.
function DebugCommands.SelfCastProbe(addon)
    if DebugCommands._selfCast then
        DebugCommands._selfCast:UnregisterAllEvents()
        DebugCommands._selfCast:SetScript("OnEvent", nil)
        DebugCommands._selfCast = nil
        addon:Print("|cffffff00selfcast: disarmed.|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._selfCast = f
    local armT, fires, kicks = GetTime(), 0, 0
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    -- 4th payload arg. MEASURED 2026-07-25 - it is two different things depending on
    -- the event, which is why both are captured and labelled separately:
    --   UNIT_SPELLCAST_STOP        -> a PLAIN small integer (castBarID). Always
    --                                 present, so it says nothing about interrupts.
    --   UNIT_SPELLCAST_INTERRUPTED -> nil, or a SECRET string (the interrupter's
    --                                 GUID). THIS is the real signal: non-nil means
    --                                 the cast was actually interrupted rather than
    --                                 having merely ended. Both cases were observed
    --                                 in one fight, so the distinction is live.
    -- The value stays sealed, but presence-vs-nil is readable without reading it
    -- (issecretvalue(arg) or arg ~= nil) - which is all CastInterruptTracker needs
    -- to replace its 1s debounce guess. Channels fire CHANNEL_STOP, not INTERRUPTED.
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    f:SetScript("OnEvent", function(_, event, _, _, _, interruptedBy)
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if kicks >= 20 then return end
            kicks = kicks + 1
            -- Never branch on the value: only ask whether the slot is occupied.
            local occupied = (issecretvalue and issecretvalue(interruptedBy)) or interruptedBy ~= nil
            local meaning = (event == "UNIT_SPELLCAST_STOP")
                and "castBarID - expect always-present, NOT an interrupt signal"
                or "interrupter GUID - occupied=true means genuinely interrupted"
            addon:Print(string.format("|cff00ccff%s|r combat=%s arg4-occupied=%s (%s) [%s]",
                event, tostring(UnitAffectingCombat("player")), tostring(occupied),
                ClassifyRead(function() return interruptedBy end), meaning))
            return
        end
        fires = fires + 1
        local isChannel = event ~= "UNIT_SPELLCAST_START"
        addon:Print(string.format("|cff00ff00%s|r combat=%s", event, tostring(UnitAffectingCombat("player"))))
        local info = { (isChannel and UnitChannelInfo or UnitCastingInfo)("player") }
        -- UnitCastingInfo: name,text,texture,startTimeMs,endTimeMs,isTradeskill,castID,notInterruptible,spellID
        -- UnitChannelInfo: name,text,texture,startTimeMs,endTimeMs,isTradeskill,notInterruptible,spellID,isEmpowered,numEmpowerStages
        local FIELDS = isChannel
            and { "name", 4, "startTimeMs", 5, "endTimeMs", 7, "notInterruptible", 8, "spellID", 9, "isEmpowered", 10, "numEmpowerStages" }
            or  { "name", 4, "startTimeMs", 5, "endTimeMs", 7, "castID", 8, "notInterruptible", 9, "spellID" }
        addon:Print("  name=" .. ClassifyRead(function() return info[1] end))
        for i = 2, #FIELDS, 2 do
            local idx, fname = FIELDS[i], FIELDS[i + 1]
            addon:Print(string.format("  %s=%s", fname, ClassifyRead(function() return info[idx] end)))
        end
        -- The doc asymmetry: UnitCastingDuration SecretReturns=true, UnitChannelDuration unannotated.
        if UnitCastingDuration then
            addon:Print("  castDur:HasSecretValues=" .. ClassifyRead(function()
                local d = UnitCastingDuration("player"); return d and d:HasSecretValues() end))
        end
        if UnitChannelDuration then
            addon:Print("  chanDur:HasSecretValues=" .. ClassifyRead(function()
                local d = UnitChannelDuration("player"); return d and d:HasSecretValues() end))
        end
        local sid = info[isChannel and 8 or 9]
        if sid and C_Spell.IsCurrentSpell then
            addon:Print("  IsCurrentSpell=" .. ClassifyRead(function() return C_Spell.IsCurrentSpell(sid) end))
        end
        if fires >= 12 or GetTime() - armT > 300 then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._selfCast = nil
            addon:Print("|cffffff00selfcast: window ended.|r")
        end
    end)
    addon:Print("|cff00ff00=== selfcast ARMED (5min/12 casts) ===|r hardcast + channel something, in and out of combat.")
    addon:Print("|cff888888  Also logs target STOP vs INTERRUPTED arg4 - kick a target's cast to see the two differ.|r")
end

--------------------------------------------------------------------------------
-- /jac inspect healprobe [arm|show] - heal-mode Phase 0 probe battery.
-- Everything the planned healer queue would branch on, measured on live party
-- units (follower-dungeon NPC allies included). Three modes:
--   (none) one-shot census - run once OUT of combat, again IN combat with the
--          party taking damage; the delta is the finding.
--   show   toggle an on-screen swatch row proving the party health-curve alpha
--          sink tracks each member (eyes are the only readback - the alpha
--          itself is secret).
--   arm    toggle a 5-minute capture of cast-target secrecy and party
--          UNIT_AURA instance plumbing (cast HoTs on party members while armed).
-- Reads only: never writes a CVar, never assigns a Blizzard frame field.
--------------------------------------------------------------------------------

-- Urgency bands mirroring the planned party cue: bright below 35%, dim up to
-- 90%, invisible above. Module-level constant - the curve caches by identity.
local HEALPROBE_BANDS = { { 0, 1 }, { 0.35, 0.65 }, { 0.9, 0 } }
local HEALPROBE_UNITS = { "player", "party1", "party2", "party3", "party4" }
local HEALPROBE_PARTY = { party1 = true, party2 = true, party3 = true, party4 = true }

--- Compact classifier for per-unit grid lines (ClassifyRead is too wide there).
local function HealCR(fn)
    local ok, v = pcall(fn)
    if not ok then return "|cffff6600ERR|r" end
    if v == nil then return "|cff888888nil|r" end
    if issecretvalue and issecretvalue(v) then return "|cffff6600SECRET|r" end
    local s = tostring(v)
    return "|cff2ecc71" .. (#s > 14 and (s:sub(1, 14) .. "..") or s) .. "|r"
end

--- `show`: one swatch per party slot, alpha handed to the engine per tick.
local function HealProbeSwatches(addon)
    if DebugCommands._healSwatchFrame then
        DebugCommands._healSwatchFrame:Hide()
        DebugCommands._healSwatchFrame:SetParent(nil)
        DebugCommands._healSwatchFrame = nil
        addon:Print("healprobe swatches: OFF")
        return
    end
    local UFF = LibStub("JustAC-UIFrameFactory", true)
    if not (UFF and UFF.SetAlphaFromHealthCurve) then
        addon:Print("healprobe: |cffff6666UIFrameFactory unavailable|r")
        return
    end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(5 * 64 + 8, 76)
    f:SetPoint("CENTER", 0, 200)
    f._swatches = {}
    for i, unit in ipairs(HEALPROBE_UNITS) do
        local box = f:CreateTexture(nil, "ARTWORK")
        box:SetColorTexture(0.15, 0.85, 0.3, 1)  -- solid green; the curve drives alpha
        box:SetSize(56, 40)
        box:SetPoint("TOPLEFT", (i - 1) * 64 + 8, -16)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOP", box, "BOTTOM", 0, -2)
        fs:SetText(unit)
        f._swatches[i] = { tex = box, unit = unit }
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)
    title:SetText("bright<35% dim<90% gone at full - row = party order")
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.1 then return end
        self._t = 0
        for _, s in ipairs(self._swatches) do
            -- The helper sinks the secret alpha engine-side; false = no unit or
            -- technique dead, either way the swatch must not stick visible.
            if not UFF.SetAlphaFromHealthCurve(s.tex, s.unit, HEALPROBE_BANDS, true) then
                pcall(s.tex.SetAlpha, s.tex, 0)
            end
        end
    end)
    DebugCommands._healSwatchFrame = f
    addon:Print("healprobe swatches: ON (top-center). Let party members take damage.")
    addon:Print("|cff888888A swatch tracking ITS member's health = curve sink works on that unit class.|r")
    addon:Print("|cff888888Run /jac inspect healprobe show again to remove.|r")
end

--- `arm`: capture cast-target secrecy + party aura-instance plumbing.
local function HealProbeCapture(addon)
    if DebugCommands._healCapture then
        DebugCommands._healCapture:UnregisterAllEvents()
        DebugCommands._healCapture:SetScript("OnEvent", nil)
        DebugCommands._healCapture = nil
        addon:Print("|cffffff00healprobe: disarmed.|r")
        return
    end
    local f = CreateFrame("Frame")
    DebugCommands._healCapture = f
    local armT, sent, added = GetTime(), 0, 0
    f:RegisterEvent("UNIT_SPELLCAST_SENT")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
        if GetTime() - armT > 300 then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._healCapture = nil
            addon:Print("|cffffff00healprobe: capture window ended.|r")
            return
        end
        if event == "UNIT_SPELLCAST_SENT" then
            -- Args: unit, targetName, castGUID, spellID. The target NAME is the
            -- HoT-attribution backbone; its secrecy is annotated ConditionalSecret,
            -- so this capture is the only way to learn the 12.0 condition.
            if unit ~= "player" or sent >= 10 then return end
            sent = sent + 1
            local sName = arg4 and C_Spell.GetSpellName and C_Spell.GetSpellName(arg4)
            addon:Print(string.format("|cff00ccffSENT|r %s target=%s combat=%s",
                tostring(sName or arg4), ClassifyRead(function() return arg2 end),
                tostring(UnitAffectingCombat("player"))))
        elseif event == "UNIT_AURA" then
            if not HEALPROBE_PARTY[unit] or added >= 20 then return end
            local info = arg2
            local list = info and info.addedAuras
            if type(list) ~= "table" then return end
            for i = 1, #list do
                added = added + 1
                local a = list[i]
                -- instanceID plain = the cast->instance bridge can bind on party
                -- units; the HELPFUL|PLAYER filter verdict is the ours-detector.
                addon:Print(string.format("|cff00ff00+aura|r %s instID=%s spellId=%s fromMe=%s oursFilter=%s",
                    unit,
                    ClassifyRead(function() return a.auraInstanceID end),
                    HealCR(function() return a.spellId end),
                    HealCR(function() return a.isFromPlayerOrPlayerPet end),
                    HealCR(function()
                        return C_UnitAuras.IsAuraFilteredOutByInstanceID
                            and C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, a.auraInstanceID, "HELPFUL|PLAYER")
                    end)))
            end
        end
    end)
    addon:Print("|cff00ff00=== healprobe ARMED (5min) ===|r Cast HoTs on party members, in and out of combat.")
    addon:Print("|cff888888SENT target plain + party instID plain + oursFilter plain bool = HoT upkeep bridge works.|r")
end

--- `watch`: edge-triggered watcher for the party-low table. The one-shot census
--- can't catch "someone is below the threshold RIGHT NOW" while the user is busy
--- healing; this polls at 0.25s and prints only TRANSITIONS. A read that throws
--- or returns secret is itself the verdict (laundering failed) and is printed
--- loudly rather than swallowed.
local function HealProbeWatch(addon)
    if DebugCommands._healWatch then
        DebugCommands._healWatch:SetScript("OnUpdate", nil)
        DebugCommands._healWatch = nil
        addon:Print("|cffffff00healprobe watch: OFF.|r")
        return
    end
    local caa = _G.CombatAudioAlertManager
    if not caa then
        addon:Print("healprobe watch: |cffff6666alert manager frame not found|r")
        return
    end
    local cvar = tostring(GetCVar and GetCVar("CAAPartyHealthPercent") or "?")
    if cvar == "0" then
        addon:Print("|cffff6600Party health alert CVar is 0 - enable the accessibility setting first.|r")
    end
    local f = CreateFrame("Frame")
    DebugCommands._healWatch = f
    local last, lastCount, armT = {}, nil, GetTime()
    addon:Print(string.format("|cff00ff00=== healprobe watch ON (5min, threshold-CVar=%s) ===|r pull; transitions print as they happen.", cvar))
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.25 then return end
        self._t = 0
        if GetTime() - armT > 300 then
            f:SetScript("OnUpdate", nil)
            DebugCommands._healWatch = nil
            addon:Print("|cffffff00healprobe watch: window ended.|r")
            return
        end
        -- unitCount: a plain int per the source; secret/throw = failed laundering.
        local okC, count = pcall(function()
            return caa.partyHealthInfo and caa.partyHealthInfo.unitCount end)
        local countState = not okC and "ERROR"
            or (issecretvalue and issecretvalue(count)) and "SECRET"
            or tostring(count)
        if countState ~= lastCount then
            local bad = (countState == "ERROR" or countState == "SECRET")
            addon:Print(string.format("%sunitCount -> %s|r  combat=%s",
                bad and "|cffff6600" or "|cff2ecc71", countState,
                tostring(UnitAffectingCombat("player"))))
            lastCount = countState
        end
        for _, u in ipairs(HEALPROBE_UNITS) do
            local okK, present = pcall(function()
                local ui = caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
                return ui and (ui[u] ~= nil) or false end)
            local state = not okK and "ERROR"
                or (issecretvalue and issecretvalue(present)) and "SECRET"
                or tostring(present)
            if state ~= last[u] then
                local bad = (state == "ERROR" or state == "SECRET")
                -- true/false transitions are the PASS signal; ERROR/SECRET is the
                -- laundering-failed verdict the whole emergency tier hangs on.
                addon:Print(string.format("%slow[%s] -> %s|r  combat=%s",
                    bad and "|cffff6600" or "|cff2ecc71", u, state,
                    tostring(UnitAffectingCombat("player"))))
                last[u] = state
            end
        end
    end)
end

--- `cvar [index]`: the auto-setup taint experiment. Writes the party-health
--- threshold CVar from ADDON (tainted) code - the exact thing the sweep memory
--- warns might taint the alert manager's cached compare. If, after this write,
--- keys still flip plain during a fight (`watch`) and `/jac inspect errors`
--- stays clean, a managed-CVar setup toggle (nameplate-overlay save/restore
--- pattern) is safe to ship. Recovery if it breaks: re-set the threshold from
--- Blizzard's accessibility settings, or /reload.
local function HealProbeCVarWrite(addon, arg)
    if InCombatLockdown() then
        addon:Print("|cffff6600Run the cvar write OUT of combat.|r")
        return
    end
    local cur = tostring(GetCVar and GetCVar("CAAPartyHealthPercent") or "?")
    local idx = arg and arg:match("^cvar%s+(%d+)$")
    if not idx then
        addon:Print(string.format("Usage: /jac inspect healprobe cvar <index>  (current=%s; 0 disables)", cur))
        addon:Print("|cff888888Writes the threshold CVar from addon code to test the taint theory.|r")
        return
    end
    local ok, err = pcall(SetCVar, "CAAPartyHealthPercent", idx)
    addon:Print(string.format("SetCVar CAAPartyHealthPercent %s -> %s : %s",
        cur, idx, ok and "|cff2ecc71written|r" or ("|cffff6600FAILED|r " .. tostring(err))))
    if ok then
        addon:Print("Now: `healprobe watch`, pull, let members drop below the threshold, then `/jac inspect errors`.")
        addon:Print("|cff888888Keys flipping plain + zero taint errors = managed auto-setup is shippable.|r")
    end
end

function DebugCommands.HealProbe(addon, arg)
    if arg == "show" then return HealProbeSwatches(addon) end
    if arg == "arm" then return HealProbeCapture(addon) end
    if arg == "watch" then return HealProbeWatch(addon) end
    if arg and arg:match("^cvar") then return HealProbeCVarWrite(addon, arg) end

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local UFF = LibStub("JustAC-UIFrameFactory", true)
    local caa = _G.CombatAudioAlertManager
    local caaApi = _G.C_CombatAudioAlert

    addon:Print("== heal-mode probe ==  run OOC, then IN combat while the party takes damage")
    local role = GetSpecialization() and GetSpecializationRole(GetSpecialization())
    addon:Print(string.format("  combat=%s grouped=%s members=%s role=%s",
        tostring(InCombatLockdown()), tostring(IsInGroup()),
        tostring(GetNumGroupMembers()), tostring(role)))

    -- A. The one branchable ally-low signal: key-existence in the accessibility
    -- alert manager's table, inserted by untainted code. Values stay untouched.
    addon:Print("|cff66ccffA. party-low bridge (audio-alert manager)|r")
    addon:Print(string.format("  manager=%s IsEnabled=%s threshold-CVar=%s (0 = feature off; volume CVar mutes the voice)",
        tostring(caa ~= nil),
        HealCR(function() return caaApi and caaApi.IsEnabled and caaApi.IsEnabled() end),
        HealCR(function() return GetCVar("CAAPartyHealthPercent") end)))
    addon:Print("  unitCount=" .. ClassifyRead(function()
        return caa and caa.partyHealthInfo and caa.partyHealthInfo.unitCount end))
    addon:Print("  keys-iterable=" .. ClassifyRead(function()
        local ui = caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
        if not ui then return nil end
        local n = 0
        for _ in pairs(ui) do n = n + 1 end
        return n end))
    for _, u in ipairs(HEALPROBE_UNITS) do
        addon:Print(string.format("  low[%s]=%s", u, ClassifyRead(function()
            local ui = caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
            if not ui then return nil end
            return ui[u] ~= nil end)))
    end
    -- Same signal through the shipping wrapper: these must agree with the raw
    -- reads above, or the wrapper's guards are wrong.
    if BlizzardAPI and BlizzardAPI.GetPartyLowCount then
        local parts = {}
        for _, u in ipairs(HEALPROBE_UNITS) do
            parts[#parts + 1] = u:gsub("party", "p") .. "=" .. tostring(BlizzardAPI.IsUnitLow(u))
        end
        addon:Print(string.format("  |cff888888via BlizzardAPI:|r available=%s count=%s  %s",
            tostring(BlizzardAPI.IsPartyLowAvailable()),
            tostring(BlizzardAPI.GetPartyLowCount()), table.concat(parts, " ")))
    end

    -- B. Plain per-unit gates the queue would branch on.
    addon:Print("|cff66ccffB. roster gates (per unit: exists/conn/dead/role/name/maxHP/threat/cmp)|r")
    for _, u in ipairs(HEALPROBE_UNITS) do
        addon:Print(string.format("  %-7s %s %s %s %s %s %s %s", u,
            HealCR(function() return UnitExists(u) end),
            HealCR(function() return UnitIsConnected(u) end),
            HealCR(function() return UnitIsDeadOrGhost(u) end),
            HealCR(function() return UnitGroupRolesAssigned(u) end),
            HealCR(function() return UnitName(u) end),
            HealCR(function() return UnitHealthMax(u) end),
            HealCR(function() return UnitThreatSituation(u) end)
            .. "/" .. HealCR(function()
                return C_Secrets and C_Secrets.CanCompareUnitTokens
                    and C_Secrets.CanCompareUnitTokens("player", u) end)))
    end

    -- C. Availability of the display-only curve sink per unit (the alpha itself
    -- is secret - `show` mode is the eyes-on proof; this only asks "did the
    -- helper wire up").
    addon:Print("|cff66ccffC. health-curve alpha sink availability|r")
    if UFF and UFF.SetAlphaFromHealthCurve then
        DebugCommands._healScratch = DebugCommands._healScratch or CreateFrame("Frame")
        local parts = {}
        for _, u in ipairs(HEALPROBE_UNITS) do
            local ok = UFF.SetAlphaFromHealthCurve(DebugCommands._healScratch, u, HEALPROBE_BANDS, true)
            parts[#parts + 1] = u .. "=" .. (ok and "|cff2ecc71ok|r" or "|cffff6600no|r")
        end
        addon:Print("  " .. table.concat(parts, " "))
    else
        addon:Print("  |cffff6666UIFrameFactory unavailable|r")
    end

    -- D. Engine aura filters on party units. CountAuras carries the shipped
    -- token-verdict guard: nil = token not trusted (or unit unreadable). The
    -- verdict needs >1 aura in play, so only in-combat runs are conclusive.
    addon:Print("|cff66ccffD. aura filters (harmful / player-dispellable / my-HoTs)|r")
    if BlizzardAPI and BlizzardAPI.CountAuras then
        for _, u in ipairs(HEALPROBE_UNITS) do
            local harm = BlizzardAPI.CountAuras(u, "HARMFUL")
            local disp = BlizzardAPI.CountAuras(u, "HARMFUL|RAID_PLAYER_DISPELLABLE")
            local mine = BlizzardAPI.CountAuras(u, "HELPFUL|PLAYER")
            local warn = (harm and disp and harm > 1 and disp == harm)
                and "  |cffff6600token may be ignored (narrowed==base)|r" or ""
            addon:Print(string.format("  %-7s harmful=%s dispellable=%s myhots=%s%s",
                u, tostring(harm), tostring(disp), tostring(mine), warn))
        end
        addon:Print("|cff888888  cast a HoT on a member and re-run: their myhots must move 0->1|r")
    else
        addon:Print("  |cffff6666BlizzardAPI unavailable|r")
    end

    -- E. What Assisted Combat feeds this spec (works even while spec-disabled -
    -- these are direct API reads, not the queue).
    addon:Print("|cff66ccffE. Assisted Combat on this spec|r")
    local AC = C_AssistedCombat
    if AC then
        local okA, avail, reason = pcall(AC.IsAvailable)
        addon:Print(string.format("  IsAvailable=%s reason=%s",
            okA and tostring(avail) or "ERR", okA and tostring(reason) or "-"))
        local okN, pick = pcall(AC.GetNextCastSpell, false)
        local pickName = okN and pick and C_Spell.GetSpellName and C_Spell.GetSpellName(pick)
        local pickTag = ""
        if okN and pick and SpellDB and SpellDB.IsHealingSpell then
            pickTag = SpellDB.IsHealingSpell(pick) and " |cff2ecc71[heal]|r" or " [dps]"
        end
        addon:Print(string.format("  next=%s %s%s", tostring(okN and pick or "ERR"),
            tostring(pickName or ""), pickTag))
        local okR, rot = pcall(AC.GetRotationSpells)
        if okR and type(rot) == "table" then
            addon:Print(string.format("  rotation pool: %d spells%s", #rot,
                #rot == 0 and " (some specs return empty OOC)" or ""))
            for i = 1, math.min(#rot, 12) do
                local id = rot[i]
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local tag = (SpellDB and SpellDB.IsHealingSpell and SpellDB.IsHealingSpell(id))
                    and "|cff2ecc71heal|r" or "dps"
                addon:Print(string.format("    %2d. %7d %-24s %s", i, id, tostring(nm), tag))
            end
        else
            addon:Print("  rotation pool: unavailable")
        end
    else
        addon:Print("  |cffff6666C_AssistedCombat unavailable|r")
    end
    addon:Print("|cff888888Also: `healprobe show` = live swatches, `healprobe arm` = cast/aura capture.|r")
end

--- /jac inspect ccdb [clear] - what the addon has learned about CC-immune mob types, and
--- the escape hatch. The table only ever grows on the engine's own "Immune" announcement,
--- so a wrong entry should be rare - but it survives sessions, so it must be inspectable.
function DebugCommands.CCImmunityDB(addon, arg)
    local B = LibStub("JustAC-BlizzardAPI", true)
    if not (B and B.GetCCImmunityDBInfo) then return end
    if arg == "clear" then
        B.ClearCCImmunityDB()
        addon:Print("|cff00ccff== ccdb ==|r cleared.")
        return
    end
    local count, targetNPC, sightings, threshold, byName = B.GetCCImmunityDBInfo()
    addon:Print(string.format("|cff00ccff== ccdb ==|r %d mob type(s) confirmed CC-immune "
        .. "(%d sighting(s) to confirm).", count, threshold))
    if targetNPC then
        addon:Print(string.format("  current target npcID=%d sightings=%s%s",
            targetNPC, tostring(sightings or 0),
            byName and " |cff888888(recovered by name - lookups only, never recorded)|r" or ""))
    else
        addon:Print("  current target npcID unknown (GUID is secret in combat, and no name "
            .. "match yet - target this mob out of combat once to learn it).")
    end
    addon:Print("  signal on this target: "
        .. tostring(B.GetCCImmuneSignal and B.GetCCImmuneSignal()))
end

--- /jac inspect blank - why did the queue last go empty? Three branches can blank it and
--- the result looks identical, so SpellQueue records the branch at the moment of the flip.
--- Run it right after the icons vanish; the bar/form state captured alongside is what tells
--- an ordinary hide apart from an effect that swapped the action bar out from under you.
function DebugCommands.QueueBlankReport(addon)
    local SQ = LibStub("JustAC-SpellQueue", true)
    local info = SQ and SQ.GetQueueBlankInfo and SQ.GetQueueBlankInfo()
    if not info then
        addon:Print("|cff00ccff== blank ==|r the queue has not gone empty since login.")
        return
    end
    addon:Print(string.format("|cff00ccff== blank ==|r %.1fs ago: |cffffff00%s|r",
        GetTime() - info.at, tostring(info.reason)))
    addon:Print(string.format("  combat=%s overrideBar=%s vehicleBar=%s possessBar=%s formID=%s",
        tostring(info.inCombat), tostring(info.override), tostring(info.vehicle),
        tostring(info.possess), tostring(info.formID)))
end

--- /jac inspect auraids - one-shot: is C_UnitAuras.GetUnitAuraInstanceIDs a plain,
--- countable, iterable list in combat? (Claim: yes.) Run OOC for baseline, then in
--- combat, then dungeon. GetUnitAuras - the batch call whose docs say the TABLE is
--- plain and only the fields are secret - is measured by `enginesig` instead.
function DebugCommands.AuraInstanceIdsProbe(addon)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then
        addon:Print("|cffff6600GetUnitAuraInstanceIDs unavailable|r")
        return
    end
    addon:Print(string.format("|cff00ccff== auraids ==|r combat=%s", tostring(UnitAffectingCombat("player"))))
    for _, unit in ipairs({ "player", "target" }) do
        if unit == "player" or UnitExists(unit) then
            for _, filter in ipairs({ "HELPFUL", "HARMFUL", "HARMFUL|CROWD_CONTROL" }) do
                local ok, t = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
                if not ok then
                    addon:Print(string.format("  %s %s: |cffff6600THREW|r", unit, filter))
                elseif t == nil then
                    addon:Print(string.format("  %s %s: nil", unit, filter))
                else
                    local cnt = ClassifyRead(function() return #t end)
                    local first = ClassifyRead(function() return t[1] end)
                    addon:Print(string.format("  %s %s: count=%s first=%s", unit, filter, cnt, first))
                    if t[1] and C_UnitAuras.GetAuraDuration then
                        addon:Print("    dur[1]:HasSecretValues=" .. ClassifyRead(function()
                            local d = C_UnitAuras.GetAuraDuration(unit, t[1]); return d and d:HasSecretValues() end))
                    end
                end
            end
        end
    end
    addon:Print("|cff888888Goal: count/first read plain in combat -> plain aura counts for gates.|r")
end

--- /jac inspect cdfields - one-shot: the NeverSecret fields inside otherwise-secret
--- cooldown structs (maxCharges, charge isActive, isEnabled, isOnGCD) plus
--- IsSpellOverlayed proc boolean and GetSpellCastCount. Run OOC, then in combat.
function DebugCommands.CooldownFieldsProbe(addon)
    local ids = RotationIds(8)
    if #ids == 0 then
        addon:Print("no rotation spells - use a spec with a rotation")
        return
    end
    addon:Print(string.format("|cff00ccff== cdfields ==|r combat=%s", tostring(UnitAffectingCombat("player"))))
    addon:Print("|cff888888isOnGCD is only trustworthy inside SPELL_UPDATE_COOLDOWN - treat as indicative here.|r")
    for _, id in ipairs(ids) do
        local nmS = (C_Spell.GetSpellName and C_Spell.GetSpellName(id) or "?") .. "(" .. id .. ")"
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
        addon:Print("  " .. nmS)
        if ch then
            addon:Print(string.format("    charges: maxCharges=%s isActive=%s",
                ClassifyRead(function() return ch.maxCharges end),
                ClassifyRead(function() return ch.isActive end)))
        end
        if cd then
            addon:Print(string.format("    cooldown: isEnabled=%s isOnGCD=%s",
                ClassifyRead(function() return cd.isEnabled end),
                ClassifyRead(function() return cd.isOnGCD end)))
        end
        if C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
            addon:Print("    overlayed=" .. ClassifyRead(function() return C_SpellActivationOverlay.IsSpellOverlayed(id) end))
        end
        if C_Spell.GetSpellCastCount then
            addon:Print("    castCount=" .. ClassifyRead(function() return C_Spell.GetSpellCastCount(id) end))
        end
    end
end

--- /jac inspect secrecymap - one-shot, OOC: per-spell SecrecyLevel from C_Secrets
--- (NeverSecret=0 / AlwaysSecret=1 / ContextuallySecret=2). The predicate docs say
--- individual spells/power types may be flagged NeverSecret, overriding combat
--- restrictions - any hit gets a plain fast path forever. Dumps exceptions only.
function DebugCommands.SecrecyMapProbe(addon)
    if not (C_Secrets and C_Secrets.GetSpellCooldownSecrecy) then
        addon:Print("|cffff6600C_Secrets.GetSpell*Secrecy unavailable|r")
        return
    end
    local counts, exceptions, total = { [0] = 0, [1] = 0, [2] = 0 }, {}, 0
    local seen = {}
    local function probeSpell(id)
        if not id or seen[id] then return end
        seen[id] = true
        total = total + 1
        local levels = {}
        for tag, fn in pairs({ cd = C_Secrets.GetSpellCooldownSecrecy,
                               aura = C_Secrets.GetSpellAuraSecrecy,
                               cast = C_Secrets.GetSpellCastSecrecy }) do
            local ok, lv = pcall(fn, id)
            if ok and type(lv) == "number" then
                counts[lv] = (counts[lv] or 0) + 1
                if lv ~= 2 then levels[#levels + 1] = tag .. "=" .. lv end
            end
        end
        if #levels > 0 then
            exceptions[#exceptions + 1] = string.format("%s(%d): %s",
                C_Spell.GetSpellName and C_Spell.GetSpellName(id) or "?", id, table.concat(levels, " "))
        end
    end
    -- Spellbook sweep (player bank) + rotation list.
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum.SpellBookSpellBank then
        for i = 1, 400 do
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Player)
            if not ok or not info then break end
            probeSpell(info.spellID)
        end
    end
    for _, id in ipairs(RotationIds(20)) do probeSpell(id) end
    addon:Print(string.format("|cff00ccff== secrecymap ==|r %d spells: Never=%d Always=%d Contextual=%d",
        total, counts[0] or 0, counts[1] or 0, counts[2] or 0))
    if #exceptions == 0 then
        addon:Print("  no per-spell exemptions found (everything ContextuallySecret)")
    else
        for i = 1, math.min(#exceptions, 30) do addon:Print("  " .. exceptions[i]) end
        if #exceptions > 30 then addon:Print(string.format("  ...and %d more", #exceptions - 30)) end
    end
    -- Power types 0..29.
    if C_Secrets.GetPowerTypeSecrecy then
        local pt = {}
        for p = 0, 29 do
            local ok, lv = pcall(C_Secrets.GetPowerTypeSecrecy, p)
            if ok and type(lv) == "number" and lv ~= 2 then pt[#pt + 1] = p .. "=" .. lv end
        end
        addon:Print("  power-type exemptions: " .. (#pt > 0 and table.concat(pt, " ") or "none"))
    end
end

--- /jac inspect frames - one-shot triples for the laundered frame-state booleans
--- found at 68887 (control-flow Show/Hide -> plain IsShown). Run while: hurt <35%,
--- resource capped, absorb up, in a party with a hurt member. Spam it as state
--- changes; every read is guarded. MUST be re-run with a unit-frame replacement
--- addon enabled before any feature ships on these (frozen-frame precedent).
function DebugCommands.FrameStateProbe(addon)
    local function walk(root, ...)
        local node = _G[root]
        for i = 1, select("#", ...) do
            if node == nil then return nil end
            node = node[select(i, ...)]
        end
        return node
    end
    local function report(label, fn)
        addon:Print("  " .. label .. " = " .. ClassifyRead(fn))
    end
    addon:Print(string.format("|cff00ccff== frames ==|r combat=%s", tostring(UnitAffectingCombat("player"))))

    report("LowHealthFrame:IsShown (<=35% hp)", function() return LowHealthFrame and LowHealthFrame:IsShown() end)
    report("cvar doNotFlashLowHealthWarning", function() return GetCVarBool("doNotFlashLowHealthWarning") end)

    local main = { "PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain" }
    report("AnimatedLoss:IsShown (dmg<0.25s & no absorb)", function()
        local f = walk(main[1], main[2], main[3], "HealthBarsContainer", "PlayerFrameHealthBarAnimatedLoss")
        return f and f:IsShown()
    end)
    report("HealAbsorbBar:IsShown", function()
        local f = walk(main[1], main[2], main[3], "HealthBarsContainer", "HealthBar", "HealAbsorbBar")
        return f and f:IsShown()
    end)
    local function manaChild(...)
        return walk(main[1], main[2], main[3], "ManaBarArea", "ManaBar", ...)
    end
    report("FullPowerFrame.active", function() local f = manaChild("FullPowerFrame") return f and f.active end)
    report("FullPowerFrame pulse (capped)", function()
        local f = manaChild("FullPowerFrame", "PulseFrame", "PulseAnim") return f and f:IsPlaying()
    end)
    report("FullPowerFrame:GetAlpha", function() local f = manaChild("FullPowerFrame") return f and f:GetAlpha() end)
    report("FeedbackFrame gain glow (>10% gain)", function()
        local t = manaChild("FeedbackFrame", "GainGlowTexture") return t and t:IsShown()
    end)
    report("FeedbackFrame loss glow (>10% spend)", function()
        local t = manaChild("FeedbackFrame", "LossGlowTexture") return t and t:IsShown()
    end)
    report("cvar showBuilderFeedback", function() return GetCVarBool("showBuilderFeedback") end)
    report("cvar showSpenderFeedback", function() return GetCVarBool("showSpenderFeedback") end)

    if IsInGroup() then
        for i = 1, 4 do
            local pf = walk("PartyFrame", "MemberFrame" .. i)
            if pf and pf:IsShown() then
                report("Party" .. i .. " portrait rgb (red=(1,0,0) -> <=20%)", function()
                    local r, g, b = pf.Portrait:GetVertexColor()
                    return string.format("%.2f,%.2f,%.2f", r, g, b)
                end)
            end
        end
    else
        addon:Print("  |cff888888party portrait probes skipped (not in a group)|r")
    end

    -- 2026-07-24 secrecymap found power types 4,5,7,9,12,16,19 (combo points, runes,
    -- shards, holy power, chi, arcane charges, essence) flagged NeverSecret. If a
    -- direct UnitPower read on those is truly plain in combat, it supersedes the
    -- whole point-widget frame reader. Only types the class actually has print.
    if UnitPower and UnitHasPowerType then
        for _, pt in ipairs({ 4, 5, 7, 9, 12, 16, 19 }) do
            local okH, has = pcall(UnitHasPowerType, "player", pt)
            if okH and has == true then
                report("UnitPower(player," .. pt .. ") [NeverSecret-flagged discrete]",
                    function() return UnitPower("player", pt) end)
            end
        end
        -- Slows post-mortem (15:22 session: slows provably NOT in LoC data): the only
        -- conceivable in-combat speed signal left is position-delta dead reckoning.
        -- Record UnitPosition's per-context behavior (known nil in instances; secrecy
        -- in combat unmeasured) so that route can be judged before building anything.
        report("UnitPosition(player) [slow-detect dead-reckoning feasibility]", function()
            local y, x = UnitPosition("player")
            if y == nil then return "nil (instanced?)" end
            return string.format("%.1f,%.1f", y, x)
        end)
        -- LoC lockout counterfactual: validated TRUE during a stun (14:5x session);
        -- this samples the not-CC'd baseline so we know it reads false when free.
        report("LoC count / lockout[rot1].isActive (expect 0/false when free)", function()
            local n = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount
                and C_LossOfControl.GetActiveLossOfControlDataCount() or "?"
            local ids = RotationIds(1)
            local li = ids[1] and C_Spell.GetSpellLossOfControlCooldownInfo
                and C_Spell.GetSpellLossOfControlCooldownInfo(ids[1])
            return tostring(n) .. " / " .. tostring(li and li.isActive)
        end)
        -- Cross-check vs the shipped reader (direct fast path where wired, point
        -- widgets otherwise - notably DK, where UnitPower read a constant 6 in
        -- combat 2026-07-24, i.e. total runes not ready runes).
        report("GetClassResourcePoints (shipped reader)", function()
            local BAPI = LibStub("JustAC-BlizzardAPI", true)
            if not (BAPI and BAPI.GetClassResourcePoints) then return nil end
            local c, m, r = BAPI.GetClassResourcePoints()
            if c == nil then return "unknown" end
            return string.format("%s/%s %s", tostring(c), tostring(m), tostring(r))
        end)
    end
end

--- /jac inspect cvitems - one-shot over Cooldown Manager viewer items: the
--- laundered per-spell booleans (CooldownFlash:IsShown = on real non-GCD CD,
--- isActive = tracked buff up, PandemicIcon = engine pandemic window on target
--- debuffs). Requires the Cooldown Manager enabled in Edit Mode.
function DebugCommands.CooldownViewerItemsProbe(addon)
    -- Buff viewers FIRST: their isActive/PandemicIcon are the interesting bits, and
    -- the 2026-07-24 session showed Essential/Utility items exhausting the cap
    -- (their isActive just means "spell known/tracked", always true).
    local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer",
                      "EssentialCooldownViewer", "UtilityCooldownViewer" }
    addon:Print(string.format("|cff00ccff== cvitems ==|r combat=%s", tostring(UnitAffectingCombat("player"))))
    local any, printed = false, 0
    for _, vName in ipairs(VIEWERS) do
        local v = _G[vName]
        local pool = v and v.itemFramePool
        if pool and pool.EnumerateActive then
            local shown = v:IsShown()
            addon:Print(string.format("  %s shown=%s", vName, tostring(shown)))
            for item in pool:EnumerateActive() do
                local ok, cdID = pcall(function() return item:GetCooldownID() end)
                if ok and cdID and printed < 20 then
                    any = true
                    printed = printed + 1
                    local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                        and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    local sid = info and info.spellID
                    local nmS = sid and (C_Spell.GetSpellName(sid) or "?") .. "(" .. sid .. ")" or "cd" .. cdID
                    addon:Print(string.format("    %s flash=%s isActive=%s pandemic=%s", nmS,
                        ClassifyRead(function() return item.CooldownFlash and item.CooldownFlash:IsShown() end),
                        ClassifyRead(function() return item.isActive end),
                        ClassifyRead(function() return item.PandemicIcon and item.PandemicIcon:IsShown() end)))
                end
            end
        end
    end
    if not any then
        addon:Print("  |cffff6600no active viewer items - enable the Cooldown Manager in Edit Mode|r")
    elseif printed >= 20 then
        addon:Print("  |cff888888(truncated at 20 items)|r")
    end
end

--- /jac inspect enginesig - one-shot over four engine-side signals the addon does
--- not use yet. Each is cheap to adopt IF it measures the way the docs read, and
--- each is worthless if it does not, so they get measured before anything is built:
---
---  1. C_UnitAuras.GetUnitAuras(unit, filter) - the BATCH aura call. Docs mark the
---     return ConditionalSecretContents, i.e. the table (and #length) plain with only
---     the FIELDS secret. If so it replaces the 40x GetAuraDataByIndex index loops in
---     RedundancyFilter/PrecombatEngine/StateHelpers, and #auras under a category
---     filter becomes a plain, branchable count ("target has a big defensive up").
---  2. C_Spell.IsSpellImportant / IsSpellCrowdControl / C_UnitAuras.AuraIsBigDefensive
---     - engine spell classifiers, all SecretArguments=AllowedWhenTainted, so they
---     accept a SECRET spellID. IsSpellImportant is Blizzard's own "lethal if not
---     interrupted" flag - exactly what interrupt ranking wants and cannot get from a
---     secret cast id. Probed with both a plain id and a secret one.
---  3. PlayerIsSpellTarget(unit) - "this unit's cast is aimed at the player".
---     SecretReturns=true unconditionally, so display-sink only (SetAlphaFromBoolean),
---     never a gate. Confirm it does not throw and is genuinely secret.
---  4. CreateUnitHealPredictionCalculator - a secret-aware arithmetic object. Its
---     `clamped` second returns are ENGINE-COMPUTED comparisons between two secret
---     numbers (absorb vs missing health, heal-absorb vs current health), which we
---     cannot derive ourselves at any price. Secret booleans, so display-only.
---
--- Run OOC for a baseline, then in combat, ideally targeting something with a
--- defensive up and something crowd-controlled.
function DebugCommands.EngineSignalsProbe(addon)
    local function report(label, fn)
        addon:Print("  " .. label .. " = " .. ClassifyRead(fn))
    end
    addon:Print(string.format("|cff00ccff== enginesig ==|r combat=%s",
        tostring(UnitAffectingCombat("player"))))

    -- 1. Batch aura call. The count is the whole point: a plain # under a narrow
    -- filter is a gate we can branch on with zero secret reads.
    local UA = C_UnitAuras
    if not (UA and UA.GetUnitAuras) then
        addon:Print("  |cffff6600GetUnitAuras unavailable|r")
    else
        local FILTERS = { "HELPFUL", "HARMFUL", "HELPFUL|BIG_DEFENSIVE",
                          "HELPFUL|EXTERNAL_DEFENSIVE", "HARMFUL|CROWD_CONTROL",
        -- Control row. 2026-07-25 run: every category filter returned 0 on both
        -- units in every sample, which is ambiguous - either nothing matched, or
        -- the token is unrecognised and the engine silently returns an empty list.
        -- A deliberately bogus token settles it: if this returns the same count as
        -- plain HELPFUL, extra tokens are being IGNORED and every 0 above is
        -- meaningless; if it returns 0, tokens really are parsed and the 0s are real.
                          "HELPFUL|JAC_NOT_A_REAL_TOKEN" }
        for _, unit in ipairs({ "player", "target" }) do
            if unit == "player" or UnitExists(unit) then
                for _, filter in ipairs(FILTERS) do
                    local ok, t = pcall(UA.GetUnitAuras, unit, filter)
                    if not ok then
                        addon:Print(string.format("  getUnitAuras %s %s: |cffff6600THREW|r", unit, filter))
                    elseif type(t) ~= "table" then
                        addon:Print(string.format("  getUnitAuras %s %s: %s", unit, filter, tostring(t)))
                    else
                        addon:Print(string.format("  getUnitAuras %s %s: count=%s spellId[1]=%s",
                            unit, filter,
                            ClassifyRead(function() return #t end),
                            ClassifyRead(function() return t[1] and t[1].spellId end)))
                    end
                end
            end
        end
    end

    -- 1b. The shipped helpers built on the above. This is the check on the
    -- ignored-token guard in CountAuras: if a category token ever stops being
    -- honoured, CountAuras must return nil (not a full-set count) and
    -- HasBigDefensive must go nil rather than silently reading true forever.
    -- Cross-read against the raw count so a divergence is visible in one line.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.CountAuras then
        addon:Print(string.format("  shipped: GetAuras#=%s CountAuras(BIG_DEFENSIVE)=%s HasBigDefensive=%s",
            ClassifyRead(function()
                local l = BAPI.GetAuras("player", "HELPFUL") return l and #l end),
            ClassifyRead(function() return BAPI.CountAuras("player", "HELPFUL|BIG_DEFENSIVE") end),
            ClassifyRead(function() return BAPI.HasBigDefensive("player") end)))
        addon:Print("  |cff888888(CountAuras nil + HasBigDefensive nil = the ignored-token guard tripped)|r")
    end

    -- 2. Classifiers, each against a KNOWN-YES / KNOWN-NO pair rather than whatever
    -- the rotation happens to hand over. The 2026-07-25 run fed IsSpellCrowdControl
    -- the first rotation id - Cat Form(768) - and got `true`, which is either a
    -- broken classifier or a semantic we have guessed wrong; with one uncalibrated
    -- sample there is no way to tell. A pair answers it: yes+no = the classifier
    -- works and we can trust it; yes+yes (or no+no) = it does not mean what the
    -- name says and nothing may be built on it. Ids are hardcoded on purpose - they
    -- need not be known by the player, only to exist.
    local CLASSIFIERS = {
        { "IsSpellImportant", C_Spell and C_Spell.IsSpellImportant,
          -- No universally-castable "lethal if not interrupted" spell exists to pin
          -- this against; a raid/dungeon boss cast is the real calibration. Pair is
          -- a floor check only: a plain damage spell must NOT read important.
          yes = { 118, "Polymorph" }, no = { 8921, "Moonfire" } },
        { "IsSpellCrowdControl", C_Spell and C_Spell.IsSpellCrowdControl,
          yes = { 118, "Polymorph" }, no = { 8921, "Moonfire" } },
        { "AuraIsBigDefensive", UA and UA.AuraIsBigDefensive,
          yes = { 871, "Shield Wall" }, no = { 8921, "Moonfire" } },
    }
    local secretID = nil
    if UA and UA.GetAuraDataByIndex then
        local okA, d = pcall(UA.GetAuraDataByIndex, "target", 1, "HARMFUL")
        if okA and d then secretID = d.spellId end
    end
    for _, c in ipairs(CLASSIFIERS) do
        local name, fn = c[1], c[2]
        if not fn then
            addon:Print("  |cffff6600" .. name .. " unavailable|r")
        else
            for _, leg in ipairs({ "yes", "no" }) do
                local id, label = c[leg][1], c[leg][2]
                report(string.format("%s(%d %s) [expect %s]", name, id, label, leg:upper()),
                    function() return fn(id) end)
            end
            if secretID ~= nil then
                report(name .. "(target aura id) [secret id]", function() return fn(secretID) end)
            end
        end
    end
    if secretID == nil then
        addon:Print("  |cff888888secret-id leg skipped (no target debuff) - re-run on a debuffed target in combat|r")
    end

    -- 3. Cast-on-me. Only meaningful while the target is mid-cast; nil otherwise is
    -- not evidence, so the label says which read it was.
    if PlayerIsSpellTarget then
        local casting = UnitExists("target")
            and (UnitCastingInfo("target") ~= nil or UnitChannelInfo("target") ~= nil)
        report(string.format("PlayerIsSpellTarget(target) [target casting=%s]", tostring(casting)),
            function() return PlayerIsSpellTarget("target") end)
    else
        addon:Print("  |cffff6600PlayerIsSpellTarget unavailable|r")
    end

    -- 4. Heal-prediction calculator. HasSecretValues is documented ReturnsNeverSecret,
    -- so it is the one plain read here and tells us whether the engine actually
    -- populated the object with secrets - without it, a plain `clamped` would be
    -- ambiguous (genuinely unrestricted, or silently never filled?).
    if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
        addon:Print("  |cffff6600UnitHealPredictionCalculator unavailable|r")
    else
        local calc = DebugCommands._healPredCalc
        if not calc then
            local okC
            okC, calc = pcall(function()
                local c = CreateUnitHealPredictionCalculator()
                -- MissingHealth is the mode that makes `clamped` mean "the absorb
                -- exceeds the health actually missing" - the comparison of two secret
                -- numbers we have no other way to obtain.
                c:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
                return c
            end)
            if not okC then
                addon:Print("  |cffff6600healPred setup failed:|r " .. tostring(calc):sub(1, 60))
                return
            end
            DebugCommands._healPredCalc = calc
        end
        for _, unit in ipairs({ "player", "target" }) do
            if unit == "player" or UnitExists(unit) then
                local okP = pcall(UnitGetDetailedHealPrediction, unit, nil, calc)
                if not okP then
                    addon:Print(string.format("  healPred %s: |cffff6600THREW|r", unit))
                else
                    addon:Print(string.format("  healPred %s: hasSecrets=%s absorbClamped=%s healAbsorbClamped=%s incomingClamped=%s",
                        unit,
                        ClassifyRead(function() return calc:HasSecretValues() end),
                        ClassifyRead(function() local _, c = calc:GetDamageAbsorbs() return c end),
                        ClassifyRead(function() local _, c = calc:GetHealAbsorbs() return c end),
                        ClassifyRead(function() local _, _, _, c = calc:GetIncomingHeals() return c end)))
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- /jac inspect audit [off|clear] - the whole Session-1 battery, hands-free.
-- Arm it once, then just fight: it snapshots every probe OOC (baseline), on
-- every combat enter, 10s into combat, and on combat exit. Output goes to
-- SavedVariables (JustACGlobal.probeLog), color codes stripped, so after
-- '/jac inspect audit off' + /reload the full transcript is readable directly
-- from WTF/.../SavedVariables/JustAC.lua. Also arms locwatch + selfcast with
-- their output redirected into the same log.
--------------------------------------------------------------------------------
local PROBE_LOG_MAX = 8000

local function ProbeLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.probeLog = g.probeLog or {}
    return g.probeLog
end

local function ProbeLogEmit(msg)
    local log = ProbeLogStore()
    log[#log + 1] = tostring(msg or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if #log > PROBE_LOG_MAX then
        local keep, half = {}, math.floor(PROBE_LOG_MAX / 2)
        for i = #log - half + 1, #log do keep[#keep + 1] = log[i] end
        _G.JustACGlobal.probeLog = keep
    end
end

--- Proxy addon whose Print goes to the log instead of chat; everything else
--- falls through to the real addon (db, methods).
local function LogProxy(addon)
    return setmetatable({ Print = function(_, msg) ProbeLogEmit(msg) end }, { __index = addon })
end

--------------------------------------------------------------------------------
-- /jac inspect enragelog [off|clear] - does the enrage signal actually fire in combat?
--
-- The colour-sink the feature uses is UNVERIFIABLE by construction: we hand a secret
-- alpha straight to SetAlpha and never read it, and GetAlpha is secret-aspect
-- protected, so there is no way to log "did it light up". The swatch in
-- '/jac inspect enrage' is eyes-only, which cannot prove reliability over a fight.
--
-- So this measures a DIFFERENT, readable signal and correlates it with the cue:
--   HELPFUL|RAID_PLAYER_DISPELLABLE = "auras with a dispel type the player can dispel"
--   (AuraUtil.AuraFilters). On a HOSTILE target for a soothe class that should mean
--   enrage specifically, and an aura COUNT is plain even in combat.
-- If that holds, it is a branchable enrage boolean and strictly better than the sink.
--
-- FAIL-OPEN GUARD, mandatory: an unrecognised filter token returns the UNFILTERED set
-- rather than erroring (measured - see the JAC_NOT_A_REAL_TOKEN line in enginesig).
-- A narrowed count that equals its base count is therefore "token ignored", NOT "every
-- aura is dispellable" - without this check the probe would confidently report an
-- enrage on every target that has any buff at all.
--
-- Change-only sampling: a whole fight collapses to a handful of transitions.
--------------------------------------------------------------------------------
local function EnrageSample()
    local api = LibStub("JustAC-BlizzardAPI", true)
    if not (api and api.GetAuras) or not UnitExists("target") then return nil end
    local base = api.GetAuras("target", "HELPFUL")
    local disp = api.GetAuras("target", "HELPFUL|RAID_PLAYER_DISPELLABLE")
    if not (base and disp) then return nil end
    local nb, nd = #base, #disp
    -- Token honoured only if it actually narrowed something at least once.
    local ignored = (nb > 1 and nd == nb)
    return nb, nd, ignored, base
end

--- Per-aura dispel-type decode for the log. Uses the IDENTITY curve (r = type/32), so a
--- readable context yields the raw type number and 9 == Enrage. In combat this reads SECRET,
--- which is itself the answer to "can we ever branch on this" - no.
--- Kept separate from the counts so a decode failure cannot break the sampling line.
local identCurve
local function DecodeDispelTypes(auras)
    local cu = C_CurveUtil ---@diagnostic disable-line: undefined-global
    local gadtc = C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if not (cu and gadtc and stepType and CreateColor and auras) then return "" end
    if not identCurve then
        identCurve = cu.CreateColorCurve()
        identCurve:SetType(stepType)
        for k = 0, 15 do identCurve:AddPoint(k, CreateColor(k / 32, 0, 0, 1)) end
    end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local out = {}
    for i = 1, #auras do
        local id = auras[i].auraInstanceID
        local part = "?"
        local c
        if pcall(function() c = gadtc("target", id, identCurve) end) and c then
            if BAPI and BAPI.IsSecretValue and BAPI.IsSecretValue(c.r) then
                part = "SECRET"
            else
                local t = math.floor((c.r or 0) * 32 + 0.5)
                part = tostring(t) .. (t == 9 and "<ENRAGE>" or "")
            end
        end
        out[#out + 1] = tostring(id) .. ":" .. part
    end
    return " types=[" .. table.concat(out, " ") .. "]"
end

function DebugCommands.EnrageLog(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.probeLog = nil end
        addon:Print("enragelog: |cffffff00log cleared|r")
        return
    end
    if arg == "off" or (not arg and DebugCommands._enrageLog) then
        if DebugCommands._enrageLog then
            DebugCommands._enrageLog:Cancel()
            DebugCommands._enrageLog = nil
        end
        addon:Print(string.format("enragelog: |cffff6600OFF|r - %d log lines held.", #ProbeLogStore()))
        addon:Print("|cff888888/reload to flush (JustACGlobal.probeLog)|r")
        return
    end

    ProbeLogEmit(string.format("===== ENRAGELOG armed @ %.1f =====", GetTime()))
    local last = nil
    DebugCommands._enrageLog = C_Timer.NewTicker(0.2, function()
        local nb, nd, ignored, auras = EnrageSample()
        -- Frame state is plain, so the cue's own verdict IS readable even though the
        -- alpha that drives it is not - this is the correlation that matters.
        local intIcon = addon.interruptIcon
        local cue = intIcon and intIcon.sootheCue
        local cueShown = (cue and cue:IsShown()) and true or false
        local key = string.format("%s|%s|%s|%s", tostring(nb), tostring(nd),
            tostring(ignored), tostring(cueShown))
        if key == last then return end
        last = key
        ProbeLogEmit(string.format(
            "ENR %.1f combat=%s target=%s helpful=%s dispellable=%s%s cueShown=%s",
            GetTime(), tostring(UnitAffectingCombat("player")),
            tostring(UnitName("target")), tostring(nb), tostring(nd),
            ignored and " |TOKEN-IGNORED|" or "", tostring(cueShown))
            .. DecodeDispelTypes(auras))
    end)
    addon:Print("enragelog: |cff00ff00ON|r - sampling target dispellable-aura count 5/s (changes only).")
    addon:Print("|cff888888Pull the mob that always enrages, then '/jac inspect enragelog off' and /reload.|r")
end

local PROBE_BATTERY = { "DurationProbe", "AuraInstanceIdsProbe", "CooldownFieldsProbe",
                        "FrameStateProbe", "CooldownViewerItemsProbe", "EngineSignalsProbe" }

local function RunProbeBattery(addon, tag, includeStatic)
    ProbeLogEmit(string.format("===== %s @ %.1f combat=%s hp-context: dead=%s =====",
        tag, GetTime(), tostring(UnitAffectingCombat("player")), tostring(UnitIsDeadOrGhost("player"))))
    local proxy = LogProxy(addon)
    if includeStatic then pcall(DebugCommands.SecrecyMapProbe, proxy) end
    for _, m in ipairs(PROBE_BATTERY) do
        pcall(DebugCommands[m], proxy)
    end
    addon:Print(string.format("audit: |cff00ff00%s|r snapshot captured (%d log lines held).",
        tag, #ProbeLogStore()))
end

--------------------------------------------------------------------------------
-- /jac inspect errors [off|clear|show] - capture Lua errors AND taint blocks to
-- SavedVariables (JustACGlobal.errorLog), so a fight's worth of errors can be read
-- off disk after a /reload instead of copied out of a chat frame.
--
-- TWO channels, deliberately: a tainted-execution failure NEVER reaches
-- seterrorhandler - the client fires ADDON_ACTION_BLOCKED/FORBIDDEN as an event
-- carrying (addonName, functionName) instead. Capturing only the Lua handler is
-- how a taint problem looks like "no errors at all" while the screen fills up.
--
-- Entries are DEDUPED by message and counted. One bad call inside a combat-frequency
-- hook produces thousands of identical errors; storing each one buries the single
-- other error that actually matters and bloats the saved file for nothing.
--------------------------------------------------------------------------------
local ERRORLOG_MAX = 250      -- distinct entries, not occurrences

local function ErrorLogStore()
    if not _G.JustACGlobal then _G.JustACGlobal = {} end
    local g = _G.JustACGlobal
    g.errorLog = g.errorLog or {}
    return g.errorLog
end

--- Record one error/block, collapsing repeats into a count + last-seen time.
local function ErrorLogRecord(kind, msg, stack)
    local log = ErrorLogStore()
    local key = kind .. "|" .. tostring(msg or "?")
    for i = 1, #log do
        if log[i].key == key then
            local e = log[i]
            e.count = e.count + 1
            e.last = GetTime()
            e.lastCombat = UnitAffectingCombat("player") and true or false
            return
        end
    end
    if #log >= ERRORLOG_MAX then return end   -- full: keep the first N, they came first
    log[#log + 1] = {
        key = key, kind = kind, count = 1,
        msg = tostring(msg or "?"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
        stack = stack and tostring(stack):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil,
        first = GetTime(), last = GetTime(),
        firstCombat = UnitAffectingCombat("player") and true or false,
    }
end

function DebugCommands.ErrorCapture(addon, arg)
    arg = arg and arg:lower() or nil

    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.errorLog = nil end
        addon:Print("errors: |cffffff00log cleared|r")
        return
    end

    if arg == "show" then
        local log = ErrorLogStore()
        if #log == 0 then addon:Print("errors: none captured.") return end
        addon:Print(string.format("errors: |cffffff00%d distinct|r", #log))
        for i = 1, math.min(#log, 10) do
            local e = log[i]
            addon:Print(string.format("|cffff6600%d.|r [%s x%d%s] %s",
                i, e.kind, e.count, e.firstCombat and " COMBAT" or "", e.msg))
        end
        if #log > 10 then addon:Print(string.format("|cff888888... %d more; /reload and read the file|r", #log - 10)) end
        return
    end

    if arg == "off" or (not arg and DebugCommands._errorCapture) then
        local f = DebugCommands._errorCapture
        if f then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._errorCapture = nil
        end
        -- The Lua handler stays chained: seterrorhandler has no unregister, and
        -- restoring a stale handler would clobber whatever installed itself after us.
        -- The flag below is what actually gates recording.
        DebugCommands._errorCaptureOn = false
        addon:Print(string.format("errors: |cffff6600OFF|r - %d distinct entries held.", #ErrorLogStore()))
        addon:Print("|cff888888/reload to flush to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua (JustACGlobal.errorLog)|r")
        return
    end

    DebugCommands._errorCaptureOn = true

    -- Chain the Lua error handler once per session; the flag gates recording so
    -- toggling off/on never stacks handlers.
    if not DebugCommands._errorHandlerHooked then
        DebugCommands._errorHandlerHooked = true
        local prev = geterrorhandler and geterrorhandler()
        if seterrorhandler then
            seterrorhandler(function(msg)
                if DebugCommands._errorCaptureOn then
                    -- debugstack(2) skips this closure and the handler frame.
                    ErrorLogRecord("LUA", msg, debugstack and debugstack(2, 12, 12))
                end
                if prev then return prev(msg) end
            end)
        end
    end

    local f = CreateFrame("Frame")
    DebugCommands._errorCapture = f
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addonName, funcName)
        if not DebugCommands._errorCaptureOn then return end
        ErrorLogRecord(event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "BLOCKED",
            string.format("%s tried to call %s", tostring(addonName), tostring(funcName)))
    end)

    addon:Print("errors: |cff00ff00ON|r - capturing Lua errors and taint blocks.")
    addon:Print("|cff888888Fight, then '/jac inspect errors off' and /reload. '/jac inspect errors show' for a quick look.|r")
    addon:Print("|cff888888Repeats are collapsed into a count, so a flood shows as one line xN.|r")
end

function DebugCommands.ProbeSession(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.probeLog = nil end
        addon:Print("audit: |cffffff00log cleared|r")
        return
    end
    if arg == "off" or (not arg and DebugCommands._probeSession) then
        local f = DebugCommands._probeSession
        if f then
            f:UnregisterAllEvents(); f:SetScript("OnEvent", nil)
            DebugCommands._probeSession = nil
        end
        if DebugCommands._probeTicker then
            DebugCommands._probeTicker:Cancel()
            DebugCommands._probeTicker = nil
        end
        -- Disarm the event captures we armed (they toggle).
        if DebugCommands._locWatch then DebugCommands.LossOfControlWatch(LogProxy(addon)) end
        if DebugCommands._selfCast then DebugCommands.SelfCastProbe(LogProxy(addon)) end
        addon:Print(string.format("audit: |cffff6600OFF|r - %d log lines held.", #ProbeLogStore()))
        addon:Print("|cff888888/reload to flush to WTF/Account/<ACCOUNT>/SavedVariables/JustAC.lua (JustACGlobal.probeLog)|r")
        return
    end

    local f = CreateFrame("Frame")
    DebugCommands._probeSession = f
    local cycles = 0
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD") -- instanced content (delves) loads via this, not ZONE_CHANGED
    f:SetScript("OnEvent", function(_, event)
        if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
            -- Restricted-map baseline: SecretOnRestrictedMaps applies OOC too,
            -- so entering a delve/dungeon deserves its own out-of-combat snapshot.
            if not UnitAffectingCombat("player") then
                RunProbeBattery(addon, "ZONE:" .. (GetZoneText() or "?"))
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            cycles = cycles + 1
            -- No battery at entry: measured 2026-07-24 that secrecy latches
            -- mid-combat, so at-entry reads look plain and prove nothing.
            ProbeLogEmit(string.format("===== COMBAT-ENTER#%d @ %.1f (marker only) =====", cycles, GetTime()))
            -- +4s catches short pulls (a 7.5s pull missed the +10s window entirely);
            -- castCount going SECRET inside the same snapshot marks whether
            -- restrictions had latched, so an early read cannot mislead.
            for _, delay in ipairs({ 4, 10 }) do
                C_Timer.After(delay, function()
                    if DebugCommands._probeSession and UnitAffectingCombat("player") then
                        RunProbeBattery(addon, "COMBAT+" .. delay .. "s#" .. cycles)
                    end
                end)
            end
        else
            RunProbeBattery(addon, "COMBAT-EXIT#" .. cycles)
            if cycles >= 20 then
                addon:Print("audit: 20 combat cycles captured - auto-stopping.")
                DebugCommands.ProbeSession(addon, "off")
            end
        end
    end)

    -- Change-only 1/s watcher for rare-edge booleans: a 110s boss fight gets only
    -- +4s/+10s battery snapshots, so a mid-fight low-health dip or damage edge is
    -- invisible to sampling. This logs TRANSITIONS only (a handful of lines/fight).
    local edgeState = {}
    local function edgeSample()
        local function walk2(root, ...)
            local node = _G[root]
            for i = 1, select("#", ...) do
                if node == nil then return nil end
                node = node[select(i, ...)]
            end
            return node
        end
        local reads = {
            lowHealth = function() return LowHealthFrame and LowHealthFrame:IsShown() end,
            animLoss = function()
                local fr = walk2("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain",
                    "HealthBarsContainer", "PlayerFrameHealthBarAnimatedLoss")
                return fr and fr:IsShown()
            end,
            powerCapped = function()
                local a = walk2("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain",
                    "ManaBarArea", "ManaBar", "FullPowerFrame", "PulseFrame", "PulseAnim")
                return a and a:IsPlaying()
            end,
            -- Polled, not event-driven: settles whether slows appear in the LoC data
            -- at all. Locwatch is armed on LOSS_OF_CONTROL_ADDED - if slows never
            -- fire that event, only a poll can see them. If this stays 0 while the
            -- player is visibly slowed, slows are NOT in LoC data and the fallback
            -- ladder (DB2 aura-type-33 list) is the only route.
            locCount = function()
                return C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount
                    and C_LossOfControl.GetActiveLossOfControlDataCount() or 0
            end,
            -- IsPlayerMoving: unannotated in the 68887 docs = plain always (verify -
            -- annotation gaps have lied before). Pairs with speedBand: moving+slow<5
            -- sustained = slowed; roots don't need this (ROOT is a real LoC type).
            moving = function() return IsPlayerMoving() end,
            -- Dead-reckoning speed band (validated feasible 15:31 session: UnitPosition
            -- plain+live in delve combat). Base run 7 yd/s, cat ~9.8; a slow while
            -- trying to move shows as run->slow band transitions. Heuristic only -
            -- backpedal (~4.5 yd/s) and /walk also land in slow<5, so a feature
            -- trigger must require the band to persist while moving.
            speedBand = function()
                local y, x = UnitPosition("player")
                local t = GetTime()
                local movingNow = IsPlayerMoving() == true
                local prev = edgeState._pos
                edgeState._pos = y and { y = y, x = x, t = t, moving = movingNow } or nil
                if not (y and prev) then return "n/a" end
                -- Only a delta whose WHOLE window was spent moving measures travel
                -- speed. Measured 18:56 session: combat stutter-stepping at 1s
                -- sampling aliases into phantom slow/still readings - a window with
                -- a stationary half-second reads as slow<5 while unimpaired.
                if not (movingNow and prev.moving) then return "idle" end
                local dt = t - prev.t
                if dt <= 0 or dt > 3 then return "idle" end
                local v = math.sqrt((y - prev.y) ^ 2 + (x - prev.x) ^ 2) / dt
                if v < 5 then return "slow<5"
                elseif v < 9 then return "run5-9"
                else return "fast>9" end
            end,
        }
        for key, fn in pairs(reads) do
            local ok, v = pcall(fn)
            if not ok then v = false end
            -- numbers and strings (speedBand) compare as-is; everything else -> boolean
            if type(v) ~= "number" and type(v) ~= "string" then v = (v == true) end
            if edgeState[key] ~= nil and edgeState[key] ~= v then
                ProbeLogEmit(string.format("EDGE %.1f %s: %s -> %s combat=%s",
                    GetTime(), key, tostring(edgeState[key]), tostring(v),
                    tostring(UnitAffectingCombat("player"))))
            end
            edgeState[key] = v
        end
    end
    DebugCommands._probeTicker = C_Timer.NewTicker(1.0, function() pcall(edgeSample) end)

    ProbeLogEmit(string.format("========== AUDIT SESSION ARMED %s (build %s) ==========",
        date("%Y-%m-%d %H:%M:%S"), (GetBuildInfo())))
    RunProbeBattery(addon, "BASELINE", true)
    -- Arm the event captures with output into the log.
    if not DebugCommands._locWatch then DebugCommands.LossOfControlWatch(LogProxy(addon)) end
    if not DebugCommands._selfCast then DebugCommands.SelfCastProbe(LogProxy(addon)) end
    addon:Print("|cff00ff00=== audit ARMED ===|r Baseline captured. Now just fight: enter/exit combat a few times,")
    addon:Print("get CC'd/dazed if you can, cast + channel, get hurt, cap a resource. Snapshots are automatic.")
    addon:Print("|cff888888  For the engine-signal leg: keep a debuffed target, kick something, and take a shield/absorb.|r")
    addon:Print("|cffffff00Then: /jac inspect audit off  ->  /reload|r  (log lands in SavedVariables/JustAC.lua)")
end

--------------------------------------------------------------------------------
-- /jac inspect glows - inventory every VISIBLE frame overlapping the defensive
-- cluster / resource-bar region, with its texture regions. Built for the
-- "orphan glow floating near the queue" class of report: run it WHILE the
-- artifact is on screen and the listing names the frame, its owner chain, its
-- texture atlas (which identifies the glow style at a glance), and whether its
-- alpha aspect is ENGINE-OWNED (HasSecretAspect) - the one mechanism in this
-- addon that can hold a frame visible against a manual SetAlpha(0).
--------------------------------------------------------------------------------
function DebugCommands.GlowInventory(addon)
    local issecret = issecretvalue
    local function plainNum(x)
        return type(x) == "number" and not (issecret and issecret(x))
    end

    -- Our anchor frames: rect sources for the search box, and ancestry roots
    -- for the ours/foreign tag.
    local roots, sources = {}, {}
    local function AddRoot(f)
        if f then roots[f] = true; sources[#sources + 1] = f end
    end
    local UIHealthBar = LibStub("JustAC-UIHealthBar", true)
    AddRoot(UIHealthBar and UIHealthBar.GetFrame and UIHealthBar.GetFrame())
    AddRoot(addon.maintenanceIcon)
    AddRoot(addon.defensiveFrame)
    AddRoot(addon.interruptIcon)
    if addon.interruptIcon then AddRoot(addon.interruptIcon.sootheCue) end
    for _, icon in ipairs(addon.defensiveIcons or {}) do AddRoot(icon) end
    for _, icon in ipairs(addon.spellIcons or {}) do AddRoot(icon) end

    local L, B, R, T
    for _, f in ipairs(sources) do
        local ok, l, b, w, h = pcall(f.GetRect, f)
        if ok and plainNum(l) and plainNum(b) and plainNum(w) and plainNum(h) then
            if not L or l < L then L = l end
            if not B or b < B then B = b end
            if not R or l + w > R then R = l + w end
            if not T or b + h > T then T = b + h end
        end
    end
    if not L then
        addon:Print("glows: no placeable anchor frames (displays disabled?) - nothing to search around")
        return
    end
    local PAD = 90
    L, B, R, T = L - PAD, B - PAD, R + PAD, T + PAD
    addon:Print(string.format("|cff00ff00=== glow inventory ===|r box (%.0f,%.0f)-(%.0f,%.0f) - run WHILE the artifact is visible", L, B, R, T))

    local function IsOurs(f)
        local depth = 0
        while f and depth < 12 do
            if roots[f] then return true end
            local ok, p = pcall(f.GetParent, f)
            f = ok and p or nil
            depth = depth + 1
        end
        return false
    end
    local function Label(f)
        local ok, n = pcall(f.GetName, f)
        if ok and n then return n end
        local okT, t = pcall(f.GetObjectType, f)
        return "(anon " .. (okT and t or "?") .. ")"
    end

    local hits, ourSecretRect, printed = 0, 0, 0
    local f = EnumerateFrames()
    while f do
        local okF, forbidden = pcall(f.IsForbidden, f)
        local okV, vis = pcall(f.IsVisible, f)
        if okF and not forbidden and okV and vis == true then
            local ok, l, b, w, h = pcall(f.GetRect, f)
            if not (ok and plainNum(l) and plainNum(b) and plainNum(w) and plainNum(h)) then
                -- Visible but unplaceable: only interesting if it is one of ours.
                if IsOurs(f) then
                    ourSecretRect = ourSecretRect + 1
                    addon:Print("|cffff6600OURS, SECRET rect (cannot place):|r " .. Label(f))
                end
            elseif w < 800 and h < 800 and l < R and l + w > L and b < T and b + h > B then
                hits = hits + 1
                if printed < 25 then
                    printed = printed + 1
                    local okA, a = pcall(f.GetAlpha, f)
                    local aStr = (okA and plainNum(a)) and string.format("%.2f", a) or "SECRET"
                    local owned = ""
                    if f.HasSecretAspect and Enum and Enum.SecretAspect and Enum.SecretAspect.Alpha then
                        local okO, o = pcall(f.HasSecretAspect, f, Enum.SecretAspect.Alpha)
                        if okO and o == true then owned = " |cffff6600[alpha ENGINE-OWNED]|r" end
                    end
                    local pChain, p, okP = {}, f, nil
                    for _ = 1, 3 do
                        okP, p = pcall(p.GetParent, p)
                        if not okP or not p then break end
                        pChain[#pChain + 1] = Label(p)
                    end
                    local okS, strata = pcall(f.GetFrameStrata, f)
                    local okLv, lvl = pcall(f.GetFrameLevel, f)
                    addon:Print(string.format("%d) %s%s %dx%d @(%.0f,%.0f) %s/%s a=%s%s < %s",
                        printed, Label(f), IsOurs(f) and " |cff2ecc71(ours)|r" or " |cffcccccc(foreign)|r",
                        w, h, l, b, okS and strata or "?", okLv and tostring(lvl) or "?", aStr, owned,
                        table.concat(pChain, " < ")))
                    local okN, numRegions = pcall(f.GetNumRegions, f)
                    for i = 1, (okN and numRegions or 0) do
                        local r = select(i, f:GetRegions())
                        local okSh, shown = pcall(r.IsShown, r)
                        if okSh and shown == true then
                            local okOT, ot = pcall(r.GetObjectType, r)
                            if okOT and ot == "Texture" then
                                local _, atlas = pcall(r.GetAtlas, r)
                                local _, tex = pcall(r.GetTexture, r)
                                local _, blend = pcall(r.GetBlendMode, r)
                                local what = (type(atlas) == "string" and atlas)
                                    or (type(tex) == "string" and tex)
                                    or (plainNum(tex) and ("fileID " .. tex))
                                    or "?"
                                -- Color forensics: vertex tint + desaturation state identify a
                                -- tinted-glow frame whose desaturation silently failed (cyan
                                -- over the gold base reads as olive/yellow).
                                local okC, vr, vg, vb = pcall(r.GetVertexColor, r)
                                local col = (okC and plainNum(vr) and plainNum(vg) and plainNum(vb))
                                    and string.format("%.2f,%.2f,%.2f", vr, vg, vb) or "secret"
                                local okD, desat = pcall(r.IsDesaturated, r)
                                addon:Print(string.format("     tex: %s (%s) tint=%s desat=%s", what,
                                    tostring(blend), col, okD and tostring(desat) or "?"))
                            end
                        end
                    end
                end
            end
        end
        f = EnumerateFrames(f)
    end
    addon:Print(string.format("=== %d visible frame(s) in the box, %d printed%s ===",
        hits, printed, ourSecretRect > 0 and (", " .. ourSecretRect .. " ours-with-secret-rect") or ""))
end

--------------------------------------------------------------------------------
-- /jac inspect groupbuff - verbose mirror of the pre-combat "party member is
-- missing my raid buff" detection (PrecombatEngine.PartyMemberMissingBuff),
-- showing every gate's actual answer per member: the readable-boolean probes
-- (nil = SECRET = member skipped), the aura-scan outcome, and where a secret
-- spellId forced the fail-silent bail. Run it when the recast nudge seems
-- wrong (nagging while everyone is buffed / silent while someone is not).
--------------------------------------------------------------------------------
function DebugCommands.GroupBuffProbe(addon)
    -- No file-local BlizzardAPI in this file - resolve it, or every gated
    -- BlizzardAPI.* read below silently short-circuits to nil.
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local issecret = issecretvalue
    local function RB(v)  -- ReadableBool: true/false when plain, "SECRET" when not
        if v == nil then return "nil" end
        if issecret and issecret(v) then return "SECRET" end
        return v and "T" or "F"
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local class = select(2, UnitClass("player"))
    local groups = SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS and SpellDB.CLASS_MAINTAINED_BUFFS[class]
    addon:Print(string.format("|cff00ff00=== group buff probe ===|r class=%s groups=%s inGroup=%s inRaid=%s combat=%s aurasRestricted=%s",
        tostring(class), groups and #groups or 0, RB(IsInGroup()), RB(IsInRaid()),
        tostring(InCombatLockdown()), tostring(BlizzardAPI and BlizzardAPI.AreAurasSecret and BlizzardAPI.AreAurasSecret())))
    if not groups then return end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for gi, grp in ipairs(groups) do
        local family = grp.auraIDs or grp.group
        local famStr = table.concat(family, "/")
        local active
        for _, spellID in ipairs(grp.group) do
            if IsPlayerSpell(spellID) and get then
                local a = get(spellID)
                if not a and grp.auraIDs then
                    for _, auraID in ipairs(grp.auraIDs) do
                        a = get(auraID); if a then break end
                    end
                end
                if a then active = spellID break end
            end
        end
        addon:Print(string.format("group %d [%s] raidWide=%s: player active=%s",
            gi, famStr, tostring(grp.raidWide or false), tostring(active)))
        if grp.raidWide then
            for i = 1, 4 do
                local unit = "party" .. i
                local okE, ex = pcall(UnitExists, unit)
                if okE and ex == true then
                    local okN, name = pcall(UnitName, unit)
                    local okP, isPlayer = pcall(UnitIsPlayer, unit)
                    local okC, conn = pcall(UnitIsConnected, unit)
                    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
                    local okR, inRange = pcall(UnitInRange, unit)
                    -- Every gate reduced to a plain STRING once; all verdicts below compare
                    -- strings, never the raw returns (a secret boolean burns any == test -
                    -- this very probe learned that in the field).
                    local connS  = okC and RB(conn) or "err"
                    local deadS  = okD and RB(dead) or "err"
                    local urS    = okR and RB(inRange) or "err"
                    local srS    = "n/a"
                    if active and C_Spell and C_Spell.IsSpellInRange then
                        local okS, sr = pcall(C_Spell.IsSpellInRange, active, unit)
                        srS = okS and RB(sr) or "err"
                    end
                    -- Point queries per family id: the real detection's primary probe now.
                    local pq = "n/a"
                    local byId = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
                    if byId then
                        pq = "ABSENT"
                        for _, fid in ipairs(family) do
                            local okQ, data = pcall(byId, unit, fid)
                            if okQ and data ~= nil then pq = "HAS " .. fid; break end
                            if not okQ then pq = "THROW"; break end
                        end
                    end
                    local auras = BlizzardAPI and BlizzardAPI.GetAuras and BlizzardAPI.GetAuras(unit, "HELPFUL")
                    local scan, secretAt, found = "no-auras", nil, nil
                    if auras then
                        scan = "MISSING"
                        for ai = 1, #auras do
                            local sid = auras[ai].spellId
                            if sid == nil or (issecret and issecret(sid)) then
                                secretAt = ai; scan = "BAIL(secret id)"; break
                            end
                            for _, fid in ipairs(family) do
                                if sid == fid then found = sid; scan = "HAS"; break end
                            end
                            if found then break end
                        end
                    end
                    local playerS = okP and RB(isPlayer) or "err"
                    addon:Print(string.format("  %s (%s): isPlayer=%s conn=%s dead=%s unitRange=%s spellRange=%s pointQuery=%s bulk=%s(%s)%s%s",
                        unit, (okN and name) or "?", playerS, connS, deadS,
                        urS, srS, pq, scan, auras and #auras or "nil",
                        found and (" " .. found) or "", secretAt and (" @" .. secretAt) or ""))
                    -- The real check's verdict for this member (new gates: NPCs excluded,
                    -- spell-range preferred over unit-range, point query over bulk scan):
                    local rangeOK = (srS == "T") or (srS ~= "F" and urS == "T")
                    local counted = playerS == "T" and connS == "T" and deadS == "F" and rangeOK
                    local missing = (pq == "ABSENT") or (pq ~= "n/a" and pq == "THROW" and scan == "MISSING")
                        or (pq == "n/a" and scan == "MISSING")
                    if counted and missing then
                        addon:Print("     |cffff6600-> this member triggers the recast nudge|r")
                    elseif not counted then
                        addon:Print("     |cff888888-> skipped by gates (not counted either way)|r")
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- /jac inspect textlaunder - test the FontString SetText->GetText laundering
-- claim (seen in a Midnight-native frames addon: "SetText accepts a secret
-- string, GetText() hands back a PLAIN string"). Our continuous-read sweep
-- concluded the opposite (Text aspect goes secret permanently). Three possible
-- verdicts, in descending order of consequence:
--   LAUNDERS   - GetText returns a PLAIN readable string: reopens the whole
--                continuous-read family. (Expect Blizzard to patch it.)
--   ZERO-GATE  - GetText returns a SECRET string, but `not result` is safe
--                (documented non-boolean truthiness rule) and empty text
--                collapses to plain nil: a legal presence/zero detector.
--   SEALED     - readback secret and truthiness throws: sweep verdict stands.
-- Run IN COMBAT with a target (or in a follower dungeon: NPC ally max-health
-- reads secret even out of combat).
--------------------------------------------------------------------------------
function DebugCommands.TextLaunderProbe(addon)
    local issecret = issecretvalue
    if not issecret then
        addon:Print("textlaunder: no issecretvalue on this client - nothing to test")
        return
    end

    -- Find a live secret value to feed the widget.
    local candidates = {
        { "UnitHealth(target)",     function() return UnitHealth("target") end },
        { "UnitHealthMax(target)",  function() return UnitHealthMax("target") end },
        { "UnitHealth(player)",     function() return UnitHealth("player") end },
        { "UnitHealthMax(party1)",  function() return UnitHealthMax("party1") end },
        { "UnitPower(player)",      function() return UnitPower("player") end },
    }
    local srcName, secretVal
    for _, c in ipairs(candidates) do
        local ok, v = pcall(c[2])
        if ok and v ~= nil and issecret(v) then
            srcName, secretVal = c[1], v
            break
        end
    end
    addon:Print("|cff00ff00=== text launder probe ===|r")
    if not secretVal then
        addon:Print("no SECRET source available here (all candidate reads plain) - get in combat with a target, or stand in a follower dungeon party, and rerun")
        return
    end
    addon:Print("secret source: " .. srcName)

    -- Secret-safe formatter for chat output: tostring() and string.format("%s")
    -- PROPAGATE secrecy silently (field-measured 2026-08-10 - the poisoned string
    -- sailed through both and only blew up in the chat library's table.concat),
    -- so every possibly-secret value must be reduced HERE, before the message.
    local function safe(v)
        if v ~= nil and issecret(v) then return "<SECRET " .. type(v) .. ">" end
        return tostring(v)
    end

    -- FRESH FontString every run: the Text aspect is STICKY - one secret SetText
    -- poisons the widget so even a plain "42" reads back secret forever after
    -- (field-measured: a pooled scratch widget failed its own control on re-run).
    -- A leaked FontString per probe run is an acceptable debug cost.
    if not DebugCommands._launderHolder then
        DebugCommands._launderHolder = CreateFrame("Frame")
        DebugCommands._launderHolder:Hide()
    end
    local fs = DebugCommands._launderHolder:CreateFontString(nil, "ARTWORK", "GameFontNormal")

    -- Control on the fresh widget: plain round-trip must be plain.
    fs:SetText("42")
    local ctrl = fs:GetText()
    addon:Print(string.format("control (fresh widget): GetText() = %s (secret=%s)",
        safe(ctrl), tostring(ctrl ~= nil and issecret(ctrl) or false)))

    -- Leg 1: secret in, what comes out?
    local okSet = pcall(fs.SetText, fs, secretVal)
    addon:Print("SetText(secret): " .. (okSet and "accepted" or "REJECTED (threw)"))
    if not okSet then
        addon:Print("|cffff6600verdict: SEALED at the door - SetText no longer accepts this secret|r")
        return
    end
    local aspect = "n/a"
    if fs.HasSecretAspect and Enum and Enum.SecretAspect and Enum.SecretAspect.Text then
        local okA, a = pcall(fs.HasSecretAspect, fs, Enum.SecretAspect.Text)
        aspect = okA and tostring(a) or "err"
    end
    local okGet, back = pcall(fs.GetText, fs)
    if not okGet then
        addon:Print("GetText() THREW - aspect=" .. aspect)
        addon:Print("|cffff6600verdict: SEALED (readback itself is blocked)|r")
        return
    end
    local backSecret = back ~= nil and issecret(back) or false
    addon:Print(string.format("GetText(): type=%s secret=%s aspect(Text)=%s value=%s",
        type(back), tostring(backSecret), aspect, safe(back)))

    if back ~= nil and not backSecret then
        addon:Print("|cffff0000verdict: LAUNDERS - plain readback of a secret. The continuous-read family just reopened; expect this to be patched, build nothing load-bearing on it.|r")
        return
    end

    -- Leg 2: secret readback - is the documented truthiness rule usable on it?
    local okTruth, truthy = pcall(function() return not back end)
    addon:Print(string.format("truthiness test (`not result`): %s -> %s",
        okTruth and "SAFE" or "THREW", okTruth and safe(truthy) or "-"))

    -- Leg 3: empty-collapse on the POISONED widget - does empty text read back
    -- as plain nil (the zero-detector's load-bearing half)?
    fs:SetText("")
    local emptyBack = fs:GetText()
    addon:Print(string.format("empty-collapse: SetText('') -> GetText() = %s (secret=%s)",
        safe(emptyBack), tostring(emptyBack ~= nil and issecret(emptyBack) or false)))

    -- Leg 4: stickiness - plain write to the poisoned widget.
    fs:SetText("42")
    local sticky = fs:GetText()
    addon:Print(string.format("sticky-aspect: plain '42' into poisoned widget -> secret=%s",
        tostring(sticky ~= nil and issecret(sticky) or false)))

    if okTruth and emptyBack == nil then
        addon:Print("|cffffff00verdict: ZERO-GATE - readback stays secret but presence/absence is branchable (truthiness + plain-nil empty-collapse). A legal zero-detector, not a laundering hole.|r")
    elseif okTruth then
        addon:Print("|cffffff00verdict: PARTIAL - truthiness is safe on the readback, but empty text does not collapse to plain nil, so the zero-detector needs the truthiness leg alone.|r")
    else
        addon:Print("|cff888888verdict: SEALED - readback secret and truthiness blocked; the sweep's conclusion stands.|r")
    end

    -- Applied check: the top-off feature's live gate. Run this AT FULL HEALTH -
    -- expect true (verifies the engine treats the deficit API's "-0 at full"
    -- quirk as zero); hurt yourself and rerun - expect false.
    -- This file has NO file-local BlizzardAPI - resolve it here (a bare reference
    -- is a nil global and silently skipped this whole block once already).
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if not UnitHealthMissing then
        addon:Print("applied: SKIPPED - UnitHealthMissing API not present on this client")
    elseif not (BAPI and BAPI.IsSecretZero) then
        addon:Print("applied: SKIPPED - BlizzardAPI.IsSecretZero unavailable")
    else
        local missing = UnitHealthMissing("player")
        local atFull
        if missing ~= nil then atFull = BAPI.IsSecretZero(missing) end
        addon:Print(string.format("applied: IsSecretZero(UnitHealthMissing(player)) = %s  (at full: expect true)",
            tostring(atFull)))
    end
end
