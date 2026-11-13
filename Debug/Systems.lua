-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end
local IsSecret = DebugCommands._Common.IsSecret
local SafeSecret = DebugCommands._Common.SafeSecret
local ProbeRead = DebugCommands._Common.ProbeRead
local PlayerHealthBar = DebugCommands._Common.PlayerHealthBar
local SpellLabel = DebugCommands._Common.SpellLabel
local ProbeCell = DebugCommands._Common.ProbeCell
local ProbeLogEmit = DebugCommands._Capture.ProbeLogEmit

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

    -- IsAvailable() is the authority, not the CVar. On 12.1.0 the assistedMode CVar reads
    -- false while IsAvailable() returns true and the rotation is live - it was the master
    -- switch when this line was written, and no longer answers for the API. Reporting the
    -- CVar first put a red DISABLED directly under a healthy "C_AssistedCombat: OK", which
    -- is a diagnostic sending you after a problem you do not have. Lead with the truth and
    -- keep the CVar as a footnote, distinguishing "off" from "no such CVar".
    local available, reason
    if C_AssistedCombat and C_AssistedCombat.IsAvailable then
        available, reason = C_AssistedCombat.IsAvailable()
    end
    addon:Print("  IsAvailable(): " .. (available and "|cff00ff00YES|r"
        or ("|cffff0000NO|r" .. (reason and (" (" .. tostring(reason) .. ")") or ""))))

    local cvar = GetCVar("assistedMode")
    addon:Print("  assistedMode CVar: " .. (cvar == nil and "|cff808080not present on this client|r"
        or (GetCVarBool("assistedMode") and "|cff00ff00on|r" or "|cffffff00off|r")
           .. " |cff808080(informational - IsAvailable() decides)|r"))

    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    if BlizzardAPI then
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
            addon:Print("  Current Health: unreadable (not a threshold verdict)")
        end
    end
    DebugCommands.ThresholdDiagnostics(addon)

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
        addon:Print("  Petless choice: " .. ProbeCell(function() return BlizzardAPI.IsPetlessByChoice() end)
            .. " (nil = unknown, optional reminder suppressed)")
        local DE = LibStub("JustAC-DefensiveEngine", true)
        local list = DE and DE.GetClassSpellList(addon, "petRezSpells") or {}
        local available = 0
        for _, id in ipairs(list) do
            if BlizzardAPI.IsSpellAvailable(id) then available = available + 1 end
        end
        addon:Print("  Pet summon/rez list: " .. #list .. " configured, " .. available .. " learned")
        if DE and DE.GetPetReminderState then
            local eligible, reason = DE.GetPetReminderState(addon)
            addon:Print("  Pet reminder: eligible=" .. tostring(eligible) .. " reason=" .. SafeSecret(reason))
            addon:Print("  Placement still requires an enabled surface and a spare icon; OOC uses the main precombat bar.")
        end
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

    addon:Print("5. C_Spell.GetSpellCooldown (raw isOnGCD / isActive):")
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
    addon:Print("6. Readiness (engine reads):")
    if BlizzardAPI and BlizzardAPI.IsSpellReady then
        local ready, why = BlizzardAPI.IsSpellReady(spellID)
        addon:Print("   IsSpellReady: " .. (ready and "|cff00ff00true (ready)|r" or "|cffff6600false (on CD)|r")
            .. "  - " .. tostring(why))
    end
    if BlizzardAPI and BlizzardAPI.IsSpellOnCooldown then
        addon:Print("   IsSpellOnCooldown (ignore-GCD probe): " .. tostring(BlizzardAPI.IsSpellOnCooldown(spellID)))
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

        local localCD = BlizzardAPI and BlizzardAPI.IsSpellOnCooldown and BlizzardAPI.IsSpellOnCooldown(sid)
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
        local immStr = ""
        if stype == "cc" and BlizzardAPI and BlizzardAPI.IsTargetCCImmune then
            immStr = string.format("  mech=%s immune=%s", tostring(entry.mech),
                tostring(BlizzardAPI.IsTargetCCImmune(entry.mech)))
        end
        addon:Print(string.format("  %d. %s (%d) [%s]  %sIsIntOnCD=%s|r  localCD=%s  IsReady=%s  usable=%s  isOnGCD=%s%s",
            i, name, sid, stype,
            cdColor, cdStr,
            tostring(localCD), tostring(ready), tostring(usable), isOnGCDStr, immStr))
    end

    -- The two things this probe could not previously answer, and which decide everything:
    -- WHICH spell the tracker actually picked, and what the icon then did with it. A list of
    -- healthy candidates plus a missing icon tells you nothing about where the chain broke -
    -- selection, show, texture, or alpha are four different bugs with one symptom.
    local CIT = LibStub("JustAC-CastInterruptTracker", true)
    local prof = addon.db and addon.db.profile
    if CIT and CIT.EvaluateInterrupt and SpellDB and SpellDB.ResolveInterruptSpells then
        local mode = (prof and prof.interruptMode) or "kickPrefer"
        local ok, res = pcall(CIT.EvaluateInterrupt, SpellDB.ResolveInterruptSpells(), mode, GetTime())
        if ok and res then
            local pickName = res.spellID and SpellLabel(res.spellID) or "none"
            addon:Print(string.format("verdict: shouldShow=%s  pick=%s  castBar=%s",
                res.shouldShow and "|cff00ff00true|r" or "|cffff6600false|r",
                pickName, res.castBar and "found" or "|cff888888nil|r"))
            if res.spellID and SpellDB.IsInterruptTypeSpell then
                -- Decides the ALPHA PATH: a kick goes through the secret sink and is hidden on
                -- a non-interruptible cast; a CC takes the plain path and must stay visible.
                addon:Print("   alpha path: " .. (SpellDB.IsInterruptTypeSpell(res.spellID)
                    and "|cffffff00secret sink|r (kick - hides on non-interruptible)"
                    or "|cff00ff00plain|r (cc - should be visible)"))
            end
        else
            addon:Print("verdict: |cffff6600EvaluateInterrupt threw|r")
        end
    end

    -- Cast-bar discovery. CC substitution needs a BRANCHABLE interruptibility answer, and in
    -- 12.x exactly one exists: Blizzard hides the nameplate cast bar's spell Icon on a
    -- non-interruptible cast, and Icon:IsShown() is a concrete non-secret boolean. Everything
    -- else (BorderShield, barType, UnitCastingInfo's notInterruptible) is secret.
    -- That signal has three ways to vanish, and all three look identical from the outside:
    --   * no nameplate for the target        -> nothing to read
    --   * HideIconWhenNotInterruptible=false -> the CLASSIC cast bar style deliberately does
    --     not hide the icon (Blizzard_NamePlates.lua ShouldHideIconWhenNotInterruptible),
    --     so the signal is switched off at the source
    --   * look ~= "UNITFRAME" / showIcon=false -> a reskin, or the player turned the icon off
    -- Without the signal we fail OPEN to "interruptible", pick the kick, and the secret alpha
    -- sink then hides it - a ding with no icon, and no CC offered.
    if CIT and CIT.DebugFindCastBar then
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit("target", false)
        local bar, src = CIT.DebugFindCastBar(np)
        addon:Print(string.format("cast bar: nameplate=%s  bar=%s  source=%s",
            np and "|cff00ff00yes|r" or "|cffff6600NO|r",
            bar and "|cff00ff00found|r" or "|cffff6600none|r", tostring(src)))
        if bar then
            local function f(fn) return ProbeRead(fn) end
            addon:Print(string.format(
                "   HideIconWhenNotInterruptible=%s  showIcon=%s  look=%s  Icon:IsShown=%s",
                f(function() return bar.HideIconWhenNotInterruptible end),
                f(function() return bar.showIcon end),
                f(function() return bar.look end),
                f(function() return bar.Icon and bar.Icon:IsShown() end)))
            local okH, hide = pcall(function() return bar.HideIconWhenNotInterruptible end)
            if okH and hide == false then
                addon:Print("   |cffff6600CLASSIC cast bar style|r - Blizzard does not hide the icon"
                    .. " on this style, so the only readable interruptibility signal does not exist."
                    .. " Switch the nameplate cast bar style to restore CC substitution.")
            end
        end
    end

    local icon = addon.interruptIcon
    if icon then
        local tex = icon.iconTexture
        addon:Print(string.format("icon: shown=%s  alpha=%s  spellID=%s  texShown=%s  tex=%s",
            tostring(icon:IsShown()), ProbeRead(function() return icon:GetAlpha() end),
            tostring(icon.spellID), tex and tostring(tex:IsShown()) or "no texture object",
            tex and ProbeRead(function() return tex:GetTexture() end) or "-"))
        -- The soothe cue is a SEPARATE frame pinned over this icon at +16, so a slot left at a
        -- non-zero alpha covers the kick/CC completely. Its slot alphas are secret once the
        -- enrage sink has written them, hence ProbeRead rather than a bare GetAlpha.
        local cue = icon.sootheCue
        if cue then
            local parts = {}
            for i = 1, 5 do
                local s = cue.slots and cue.slots[i]
                parts[#parts + 1] = s and ProbeRead(function() return s:GetAlpha() end) or "-"
            end
            -- The filter decides how many slots ever hold an aura, and therefore how much of
            -- this overlay is sitting over position 0 at any moment. "err" alphas are normal:
            -- a slot frame descends from a container button, so reading one is denied.
            -- Pipes DOUBLED for display: "|" opens a chat escape, so an aura filter string
            -- prints with its components eaten - "HELPFUL|RAID_..." came out as
            -- "HELPFULAID_..." because |R is the colour-reset code. Any probe printing a
            -- filter string has to do this.
            local shownFilter = tostring(cue._filter):gsub("|", "||")
            addon:Print("soothe overlay: shown=" .. tostring(cue:IsShown())
                .. "  filter=" .. shownFilter
                .. "  slots=" .. tostring(cue.slots and #cue.slots or 0)
                .. " (pool batches at 10; only maxFrameCount can be live)"
                .. "  alphas=" .. table.concat(parts, ","))
            if cue._filter == "HELPFUL" then
                addon:Print("   |cffff6600narrow filter refused|r - a slot exists for EVERY target"
                    .. " buff, not just enrages")
            end
        end
    else
        addon:Print("icon: |cff888888addon.interruptIcon is nil (standard queue not built?)|r")
    end

    addon:Print("")
    addon:Print("Target interrupt-worthy: " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetInterruptWorthy and BlizzardAPI.IsTargetInterruptWorthy()))
    addon:Print("Target CC-immune (boss/minion; per-mechanic above): " .. tostring(BlizzardAPI and BlizzardAPI.IsTargetCCImmune and BlizzardAPI.IsTargetCCImmune())
        .. "  (signal: " .. tostring(BlizzardAPI and BlizzardAPI.GetCCImmuneSignal and BlizzardAPI.GetCCImmuneSignal()) .. ")")
    -- Already crowd-controlled: this alone suppresses every CC suggestion, and on a
    -- practice mob you CC repeatedly it is the most likely reason a working substitution
    -- looks intermittent - the second cast genuinely should not be offered a CC.
    -- IN COMBAT THIS CANNOT ANSWER: GetUnitAuraInstanceIDs is RequiresUnitAuraAccess as of
    -- 12.1.0, so it fails open to false and a CC is offered onto an already-CC'd target.
    -- Reported as "unavailable" rather than "false" so the probe does not present a
    -- fail-open default as a measurement.
    local ccKnown = not (BlizzardAPI and BlizzardAPI.AreAurasSecret and BlizzardAPI.AreAurasSecret())
    local alreadyCC = (BlizzardAPI and BlizzardAPI.IsUnitCrowdControlled
        and BlizzardAPI.IsUnitCrowdControlled("target")) or false
    addon:Print("Target already CC'd: "
        .. (ccKnown and tostring(alreadyCC) or "|cffff6600unavailable in combat|r (reads false)")
        .. (ccKnown and alreadyCC and "  |cffff6600<- CC suggestions suppressed while true|r" or ""))

    -- The two debounce windows. Both are deliberate, both silence the slot, and neither
    -- was visible here before - so a report of "inconsistent" could not be told apart from
    -- a detection failure.
    if CIT and CIT.DebugSuppression then
        local sinceInt, intWin, sinceCC, ccWin = CIT.DebugSuppression()
        local intHot, ccHot = sinceInt < intWin, sinceCC < ccWin
        addon:Print(string.format("suppression: sinceInterrupt=%.1fs/%.1f%s  sinceCC=%.1fs/%.1f%s",
            sinceInt, intWin, intHot and " |cffff6600ACTIVE|r" or "",
            sinceCC, ccWin, ccHot and " |cffff6600ACTIVE|r" or ""))
    end

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
    addon:Print("  complete: " .. tostring(auras.complete == true)
        .. " (only a complete read can prove absence)")
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
            local status, text, auraData = ProbeRead(function()
                return C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            end)
            if status == "err" or status == "secret" then
                addon:Print("  Enumeration " .. status .. ": " .. text .. " (count incomplete)")
                break
            end
            if status == "nil" then break end
            count = count + 1
            if count <= 20 then
                addon:Print("  [" .. i .. "] ID:" .. ProbeCell(function() return auraData.spellId end)
                    .. " Name:" .. ProbeCell(function() return auraData.name end))
            end
        end
    else
        for i = 1, 40 do
            local ok, name, _, _, _, _, _, _, _, _, spellId = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok then
                addon:Print("  Enumeration err: " .. SafeSecret(name) .. " (count incomplete)")
                break
            end
            if not name and not spellId then break end
            count = count + 1
            if count <= 20 then
                addon:Print("  [" .. i .. "] ID:" .. SafeSecret(spellId) .. " Name:" .. SafeSecret(name))
            end
        end
    end
    addon:Print("  Buffs enumerated: " .. count)

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

    local profile = addon:GetProfile()
    local pre = profile and profile.precombatBuffs or {}
    addon:Print("  Aura secrecy: " .. ProbeCell(function()
        return LibStub("JustAC-BlizzardAPI").AreAurasSecret()
    end))
    addon:Print("  Offers enabled: " .. tostring(Engine.IsOfferingNow(profile)))
    for _, cat in ipairs(SpellDB.GetPrecombatBuffCategories()) do
        local items = SpellDB.GetPrecombatBuffItems(cat) or {}
        local pref = pre.categories and pre.categories[cat]
        local satisfied, known = Engine.IsCategorySatisfied(cat)
        local best = SpellDB.GetBestOwnedBuff(cat, type(pref) == "string" and pref or nil)
        local bestName = best and ((best.source == "spell" and SpellLabel(best.id))
            or (C_Item.GetItemInfo(best.id)) or ("item " .. best.id))
        local statTag = best and best.stat and (" |cff888888[" .. best.stat .. "]|r") or ""
        local state = pref == false and "|cff888888disabled|r"
            or (known ~= true and "|cffffff00unknown (offer suppressed)|r")
            or (satisfied and "|cff00ff00active|r")
            or (best and "|cffff6666MISSING|r" or "|cff888888missing, none owned|r")
        addon:Print(string.format("%s (%d known): %s%s%s", cat, #items, state,
            bestName and ("  best owned: " .. bestName) or "", statTag))
    end

    local missing = Engine.GetMissingBuffs(pre.categories)
    addon:Print("---- eligible checklist (before visibility/icon limits) ----")
    if #missing == 0 then
        addon:Print("|cff888888No eligible offers: active, disabled, unknown or none usable/owned.|r")
    else
        for _, m in ipairs(missing) do
            local nm = (C_Item.GetItemInfo(m.entry.id)) or ("item " .. m.entry.id)
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
        for _, s in ipairs(Engine.GetMissingClassBuffs(pre.topoffHeal,
                pre.topoffThreshold, pre.stealth, pre.categories) or {}) do
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
            local a = ProbeCell(function() return get and get(id) end)
            addon:Print(string.format("  %s known=%s auraByCastId=%s", SpellName(id),
                tostring(IsPlayerSpell(id)), a))
        end
        -- Discovery dump: every readable helpful aura on the player, so a differing
        -- aura id (cast id != aura id) shows up by name.
        local auras = BAPI and BAPI.GetAuras and BAPI.GetAuras("player", "HELPFUL")
        if auras then
            for i = 1, #auras do
                addon:Print("  helpful: " .. ProbeCell(function() return auras[i].name end)
                    .. " (" .. ProbeCell(function() return auras[i].spellId end) .. ")")
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
        local hotUp = ProbeCell(function() return get and get(SpellDB.RECUPERATE_AURA) end)
        local activeUp = ProbeCell(function() return get and get(sid) end)
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
            .. " (topoff threshold " .. tostring(pre.topoffThreshold or "?") .. "%)"
            .. (dead and "  |cffff6666DEAD/GHOST|r" or ""))
        addon:Print("  health event activity: recent=" .. tostring(activity or false)
            .. " sustained=" .. tostring(sustained or false) .. " (sustained drives the offer)")
        DebugCommands.ThresholdDiagnostics(addon)
        -- Fill-width probe: Blizzard's player frame sets its health fill from the
        -- secret value engine-side. If the fill texture's LAID-OUT width reads as a
        -- plain number, width/barWidth = exact health fraction even where UnitHealth
        -- is secret - that would replace the activity heuristic outright.
        local function FillRatio()
            local hb = PlayerHealthBar()
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
        for _, s in ipairs(Engine.GetMissingClassBuffs(pre.topoffHeal,
                pre.topoffThreshold, pre.stealth, pre.categories) or {}) do
            if s == sid then surfaced = true break end
        end
        addon:Print("  would surface: " .. (surfaced and "|cff00ff00YES|r" or "|cffff6666NO|r"))
    end
    addon:Print("============================")
end

--------------------------------------------------------------------------------
-- AoE-context probe
--------------------------------------------------------------------------------
--- /jac inspect range - settle which range API answers against the CURRENT target.
--- The SPELL path (C_Spell.IsSpellInRange) feeds IsTargetWithin - so the gap closer,
--- the melee sink, and off-bar hotkey reds. The SLOT path (C_ActionBar.IsActionInRange)
--- feeds on-bar hotkey reds. Run it three times: on a fresh target while the gap
--- closer shows, after it wedges, and right after retargeting - whichever column
--- changes between runs is the culprit.
function DebugCommands.RangeProbe(addon)
    local BlizzardAPI = LibStub("JustAC-BlizzardAPI", true)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local SpellQueue = LibStub("JustAC-SpellQueue", true)
    local ActionBarScanner = LibStub("JustAC-ActionBarScanner", true)
    local GapCloser = LibStub("JustAC-GapCloserEngine", true)
    addon:Print("=== Range probe ===")
    if not UnitExists("target") then
        addon:Print("No target - target the mob first, then run this again.")
        return
    end
    local isSecret = BlizzardAPI and BlizzardAPI.IsSecretValue
    local function fmt(v)
        if v == nil then return "|cff888888nil|r" end
        if isSecret and isSecret(v) then return "|cffff00ffSECRET|r" end
        if v == true or v == 1 then return "|cff2ecc71in|r" end
        return "|cffff6666OUT|r"
    end
    local function nameOf(id)
        local info = BlizzardAPI and BlizzardAPI.GetCachedSpellInfo and BlizzardAPI.GetCachedSpellInfo(id)
        return (info and info.name) or ("spell " .. tostring(id))
    end

    -- 1. The melee/near verdicts the gap closer consumes.
    addon:Print(string.format("  Attack production: swing=%s spell=%s ability=%s sink=%s combat=%s",
        fmt(BlizzardAPI.IsTargetInSwingRange(0)), fmt(BlizzardAPI.SpellInRange(6603, "target")),
        fmt(BlizzardAPI.AbilityInRange(6603, "target")),
        tostring(addon.db.profile.orderSinkCooldowns ~= false), tostring(UnitAffectingCombat("player"))))
    if SpellDB and SpellDB.IsTargetWithin then
        local parts = {}
        for _, y in ipairs({ 5, 8, 10, 25, 40 }) do
            local v = SpellDB.IsTargetWithin(y)
            parts[#parts + 1] = y .. "yd=" .. (v == nil and "|cff888888nil|r" or tostring(v))
        end
        addon:Print("  IsTargetWithin: " .. table.concat(parts, "  "))
    end

    -- 2. Every known range reference, raw spell-path answer.
    if SpellDB and SpellDB.DebugRangeProbes then
        local probes = SpellDB.DebugRangeProbes()
        addon:Print("  References (" .. #probes .. " known):")
        for i = 1, #probes do
            local p = probes[i]
            addon:Print(string.format("    %s (%d, %dyd): %s", nameOf(p.id), p.id, p.ref, fmt(p.r)))
        end
    end

    -- 3. Current queue spells: spell path vs slot path side by side.
    local queue = SpellQueue and SpellQueue.GetCurrentSpellQueue and SpellQueue.GetCurrentSpellQueue() or {}
    addon:Print("  Queue (spell path / slot path):")
    for i = 1, math.min(#queue, 6) do
        local sid = queue[i]
        if sid and sid > 0 then
            local spellR = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(sid, "target")
            local slot = ActionBarScanner and ActionBarScanner.GetDirectSlotForSpell
                and ActionBarScanner.GetDirectSlotForSpell(sid)
            local slotR
            if slot and C_ActionBar and C_ActionBar.IsActionInRange then
                slotR = C_ActionBar.IsActionInRange(slot, "target")
            end
            addon:Print(string.format("    %d. %s: spell=%s  slot=%s%s", i, nameOf(sid), fmt(spellR),
                slot and fmt(slotR) or "|cff888888no direct slot|r",
                slot and (" (#" .. slot .. ")") or ""))
        end
    end

    -- 4. The gap-closer verdict, plus each candidate's OWN gates - the verdict can
    -- flip on the candidate's own cast range (e.g. Wild Charge's ~25yd cap) while
    -- every melee-band reading above stays constant, so print the discriminators.
    if GapCloser and GapCloser.GetGapCloserSpell then
        local gid = GapCloser.GetGapCloserSpell(addon, {})
        addon:Print("  Gap closer verdict: " .. (gid and (nameOf(gid) .. " (" .. gid .. ")") or "|cff888888none|r"))
        if GapCloser.MarkGapCloserSpellIDs then
            local set = {}
            GapCloser.MarkGapCloserSpellIDs(addon, set)
            for id in pairs(set) do
                local ownR = BlizzardAPI and BlizzardAPI.SpellInRange and BlizzardAPI.SpellInRange(id)
                local ready = BlizzardAPI and BlizzardAPI.IsSpellReady and BlizzardAPI.IsSpellReady(id)
                addon:Print(string.format("    candidate %s (%d): own-range=%s  ready=%s",
                    nameOf(id), id, ownR == nil and "|cff888888nil|r" or fmt(ownR), tostring(ready)))
            end
        end
    end
end

--- /jac inspect aoe - Test whether we can count nearby enemies DIRECTLY (nameplate
--- enumeration + per-unit checks) without tripping 12.0 secret values, i.e. an
--- AC-independent AoE signal. Every value is tested with issecretvalue BEFORE it is
--- branched on, so the probe itself never trips a secret.
function DebugCommands.AoeDiagnostics(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    addon:Print("|cff00ccff== AoE-context probe (secret-safe enemy counting) ==|r")
    local pc = UnitAffectingCombat("player")
    addon:Print("player in combat: " .. (IsSecret(pc) and "|cffff6600SECRET|r"
        or "|cff00ff00" .. tostring(pc) .. "|r"))

    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        addon:Print("|cffff6600C_NamePlate.GetNamePlates unavailable|r")
        return
    end
    local plates = C_NamePlate.GetNamePlates()
    local total = plates and #plates or 0
    addon:Print("nameplates enumerated: " .. total
        .. "  (count secret=" .. tostring(IsSecret(total)) .. ")")

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
        if IsSecret(ex) then
            sExists = true
        elseif ex then
            nUnits = nUnits + 1
            local ca = UnitCanAttack("player", u)   -- value first, secret-test before branching
            if IsSecret(ca) then
                sHostile = true
            elseif ca then
                nHostile = nHostile + 1
                local r = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(RANGE_PROBE, u)
                if IsSecret(r) then sRange = true elseif r then nRange = nRange + 1 end
                local ic = UnitAffectingCombat(u)              -- engaged with anyone
                if IsSecret(ic) then sCombat = true elseif ic then nCombat = nCombat + 1 end
                local threatFn = _G.UnitThreatSituation         -- on its threat table = fighting ME
                if threatFn then
                    local ts = threatFn("player", u)
                    if IsSecret(ts) then sThreat = true elseif ts ~= nil then nThreat = nThreat + 1 end
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

    -- Threshold-gate layer cost. A MISS is a curve evaluation plus a FontString
    -- round-trip; a HIT is a table lookup. Misses per second is the number that
    -- matters - it should sit near (distinct thresholds asked) x (memo wipes/s),
    -- not scale with how many spells are in the queue.
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if BAPI and BAPI.GetThresholdGateStats then
        local hits, misses, wipes, curves = BAPI.GetThresholdGateStats()
        local total = hits + misses
        local elapsed = sqStats and sqStats.resetTime > 0 and (now - sqStats.resetTime) or nil
        addon:Print(string.format("Threshold gates: |cffadd8e6%d|r calls (%d miss / %d hit, %.0f%% cached), %d curves cached",
            total, misses, hits, total > 0 and (hits / total * 100) or 0, curves or 0))
        if elapsed and elapsed > 0 then
            addon:Print(string.format("  |cffadd8e6%.1f|r evaluations/s (%d memo windows over %.0fs)",
                misses / elapsed, wipes, elapsed))
        end
    end

    -- Which health band the defensive cluster is ordering by, and WHICH SOURCE
    -- answered. The source is the line that matters if this ever degrades: "gate"
    -- is the direct read, "percent" the unrestricted-context exact read, and
    -- "vignette" the estimate that cannot see the mitigation band at all.
    local DE = LibStub("JustAC-DefensiveEngine", true)
    if DE and DE.GetHealthBandInfo then
        local band, source, bounds = DE.GetHealthBandInfo()
        local BAND_NAMES = { "PANIC", "MAJOR", "MITIGATE", "HEALTHY" }
        addon:Print(string.format("Health band: |cffadd8e6%s|r (band %d, source=%s, boundaries %s)",
            BAND_NAMES[band] or "?", band or -1, tostring(source),
            bounds and table.concat(bounds, "/") .. "%" or "?"))
        if source == "vignette" then
            addon:Print("  |cffffff00vignette fallback: MITIGATE is unreachable here - expected if the gate layer is blocked|r")
        end
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
-- Maintenance slot recorder (/jac inspect maintlog)
--------------------------------------------------------------------------------
-- Samples tracker state to JustACGlobal so a whole fight can be read off disk instead of
-- pasted out of chat. Intermittent faults - a tracker stuck "down" for minutes, a bind that
-- never retries - are invisible in a snapshot and obvious in a sequence.
-- SavedVariables flush on /reload or logout ONLY: play, then /reload, then read the file.
local MAINTLOG_MAX = 400          -- bounded transitions, not elapsed seconds
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
--- the duration object resolves, and that needs a bound instance - so:
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
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local hasDur = "?"
    if BAPI and BAPI.GetAuraDurationObject and type(inst) == "number" then
        hasDur = (BAPI.GetAuraDurationObject("player", inst) ~= nil) and "1" or "0"
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

--- /jac inspect maintlog [on|off|clear] - sample maintenance state 10/s, save transitions.
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
    if maintLogTicker then
        addon:Print("maintlog: already ON")
        return
    end
    -- 10/s: the reported lag is sub-second, which 1/s sampling cannot resolve at all.
    -- Cheap because the sample is change-only (see MaintLogSample).
    lastMaintPayload = nil
    maintLogTicker = C_Timer.NewTicker(0.1, function()
        local ok, err = pcall(MaintLogSample)
        if not ok then
            maintLogTicker:Cancel()
            maintLogTicker = nil
            addon:Print("maintlog: stopped after sample error: " .. SafeSecret(err))
        end
    end)
    addon:Print("maintlog: |cff00ff00ON|r - sampling 10/s, transitions only. Press the buff a few")
    addon:Print("times (first application AND refreshes), then |cffffff00/jac inspect maintlog off|r and |cffffff00/reload|r.")
end

--- /jac inspect enemies - why does the direct enemy count read what it reads?
--- GetEngagedEnemyCount skips a nameplate unit when ANY of three reads comes back secret,
--- which turns a hidden read into a silent, permanent zero. This prints each read per
--- plate with its secrecy, so the one that fails is visible. Run it IN COMBAT with a pack.
function DebugCommands.EnemyCountProbe(addon)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local tag = SafeSecret
    addon:Print(string.format("|cff00ccff== enemy count ==|r  GetEngagedEnemyCount=%s  combat=%s",
        tostring(BAPI and BAPI.GetEngagedEnemyCount and BAPI.GetEngagedEnemyCount()),
        tostring(UnitAffectingCombat("player"))))
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
    addon:Print(string.format("  nameplates on screen: %d   (nameplateShowEnemies=%s)",
        #plates, tostring(GetCVar and GetCVar("nameplateShowEnemies"))))
    -- Shortest range probe this character knows (melee attacks are 5yd).
    local SDB = LibStub("JustAC-SpellDB", true)
    local probeID, probeYards
    for _, pr in ipairs(SDB and SDB.DebugRangeProbes and SDB.DebugRangeProbes() or {}) do
        if not probeYards or pr.ref < probeYards then probeID, probeYards = pr.id, pr.ref end
    end
    local shown = 0
    for i = 1, 40 do
        local u = "nameplate" .. i
        local ex = UnitExists(u)
        if ex == nil or (issecretvalue and issecretvalue(ex)) or ex then
            shown = shown + 1
            if shown <= 8 then
                -- Candidate replacement for the threat test: "in combat" + "close enough".
                -- near = the player's shortest known range probe, asked of THIS unit.
                local near = "?"
                if probeID and C_Spell and C_Spell.IsSpellInRange then
                    near = tag(C_Spell.IsSpellInRange(probeID, u))
                end
                addon:Print(string.format("  %-12s exists=%s canAttack=%s threat=%s inCombat=%s near(%s)=%s",
                    u, tag(ex), tag(UnitCanAttack("player", u)),
                    tag(UnitThreatSituation and UnitThreatSituation("player", u)),
                    tag(UnitAffectingCombat(u)), tostring(probeYards), near))
            end
        end
    end
    if shown == 0 then
        addon:Print("  |cffff6600no nameplate units at all|r - enemy nameplates are off, or none are in view")
    end
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
    addon:Print(string.format("|cff00ccff== ccdb ==|r %d mob-type/mechanic pair(s) recorded "
        .. "(%d sighting(s) to confirm).", count, threshold))
    if targetNPC then
        addon:Print(string.format("  current target npcID=%d sightings (mech:count)=%s%s",
            targetNPC, sightings or "none",
            byName and " |cff888888(recovered by name - lookups only, never recorded)|r" or ""))
    else
        addon:Print("  current target npcID unknown (GUID is secret in combat, and no name "
            .. "match yet - target this mob out of combat once to learn it). Inside dungeons "
            .. "identity is secret even out of combat, so there only this target learns.")
    end
    addon:Print("  signal on this target: "
        .. tostring(B.GetCCImmuneSignal and B.GetCCImmuneSignal()))
end

--------------------------------------------------------------------------------
-- /jac inspect audioalerts - the combat audio alert manager as a SIGNAL SOURCE
--------------------------------------------------------------------------------
-- Blizzard's combat audio alert system announces player/target health, player/target casts,
-- party health and player debuffs. To do that it must COMPUTE those things - and it is
-- ordinary untainted Lua on an ordinary Frame (`CombatAudioAlertManager`, toplevel, plain
-- mixin), NOT one of the forbidden aura containers. It caches what it computed:
--
--   lastUnitHealthPercent[unit]      lastPlayerPowerPercent[...]     partyHealthInfo
--   lastUnitHealthAnnouncePercent    lastPlayerPowerAnnouncePercent  lastInterruptedCast
--   unitCastStartUnitsLookup         unitCastEndUnitsLookup          unitHealthUnitsLookup
--
-- Why this is worth measuring rather than assuming: untainted control flow CAN launder a
-- secret into a plain value, and we already ship a technique that depends on it -
-- `item.isActive` on the Cooldown Manager is "an ordinary boolean assigned by untainted
-- control flow" and reads PLAIN in combat (MaintenanceTracker.ViewerBuffActive). If health
-- and power percents survive the same way, they are branchable numbers - the exact thing
-- every note we have says does not exist.
--
-- Same conditionality as the Cooldown Manager, and the same trap: this only computes while
-- the FEATURE IS ON. A category the player left off caches nothing, and a stale cache from a
-- category switched off mid-session would be worse than nothing - so report the settings
-- FIRST and never interpret a value without them.
function DebugCommands.AudioAlertProbe(addon)
    addon:Print("=== combat audio alerts as a signal source ===")
    local mgr = CombatAudioAlertManager
    if not mgr then
        addon:Print("|cffff6600CombatAudioAlertManager missing|r - addon not loaded this session")
        return
    end
    addon:Print("manager: present  initDone=" .. tostring(rawget(mgr, "initDone")))

    -- WHICH CATEGORIES ARE ON. Everything below is meaningless without this: an off category
    -- never populates its cache, so a nil read means "disabled", not "unreadable".
    local CA = C_CombatAudioAlert
    local cats = Enum and Enum.CombatAudioAlertCategory
    if CA and CA.GetSpecSetting and type(cats) == "table" then
        local parts = {}
        for name, value in pairs(cats) do
            local st, txt = ProbeRead(function() return CA.GetSpecSetting(value) end)
            parts[#parts + 1] = string.format("%s=%s", name, st == "plain" and txt or st)
        end
        table.sort(parts)
        addon:Print("settings: " .. table.concat(parts, "  "))
    else
        addon:Print("|cff888888category settings unavailable - cannot say which caches are live|r")
    end

    -- THE CACHES. Percent-per-unit tables are the prize; the rest are cheap to read while
    -- we are here and each one is a signal in its own right if it comes back plain.
    local function report(label, fn)
        local st, txt = ProbeRead(fn)
        local colour = (st == "plain") and "|cff2ecc71" or "|cff888888"
        addon:Print(string.format("  %-38s %s%s|r%s", label, colour, st,
            (st == "plain" and txt and txt ~= "nil") and (" = " .. txt) or ""))
    end
    report("lastUnitHealthPercent[player]", function() return mgr.lastUnitHealthPercent and mgr.lastUnitHealthPercent["player"] end)
    report("lastUnitHealthPercent[target]", function() return mgr.lastUnitHealthPercent and mgr.lastUnitHealthPercent["target"] end)
    report("lastPlayerPowerPercent (count)", function()
        local t = mgr.lastPlayerPowerPercent
        if type(t) ~= "table" then return nil end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end)
    report("lastPlayerPowerPercent (first value)", function()
        local t = mgr.lastPlayerPowerPercent
        if type(t) ~= "table" then return nil end
        -- next(), not a one-iteration pairs loop: the table is keyed by power token and any
        -- entry characterises it, so say "give me one" rather than writing a loop that lies
        -- about iterating.
        return select(2, next(t))
    end)
    report("partyHealthInfo.unitCount", function()
        return mgr.partyHealthInfo and mgr.partyHealthInfo.unitCount
    end)
    report("lastInterruptedCast", function() return mgr.lastInterruptedCast end)
    report("unitCastStartUnitsLookup[target]", function()
        return mgr.unitCastStartUnitsLookup and mgr.unitCastStartUnitsLookup["target"]
    end)

    addon:Print("|cff888888green = PLAIN, i.e. branchable. A percent reading plain here is a"
        .. " number every other route says cannot exist - re-read the settings line before"
        .. " believing it, and check it TRACKS (take damage, re-run).|r")
    addon:Print("==============================================")
end

--------------------------------------------------------------------------------
-- /jac inspect hotkeys - why a queue icon has no keybind
--------------------------------------------------------------------------------
-- Reported 2026-08-12: while CHANNELING, the next recommendation shows no hotkey, and it
-- comes back the moment the channel ends. Three causes look identical on screen and this
-- probe exists to tell them apart, because guessing between them is how the wrong one gets
-- "fixed":
--
--   1. THE SPELL GENUINELY HAS NO BINDING. Nothing is broken; the recommendation is an
--      ability the player has not placed on a bar. `slot` below is nil every pass.
--   2. CACHE STARVATION. ACTIONBAR_SLOT_CHANGED fires constantly in some situations, and
--      every one of those FULL-WIPES spellSlotCache. The forward-override scan in
--      GetSpellHotkey - the only route that resolves an aura-driven transform - can only
--      work by iterating that table, so a cache wiped faster than it warms resolves
--      nothing. Watch `wipes` climbing and `slotEntries` staying near zero.
--   3. REFRESH THROTTLE. `lastHotkeyRefreshTime` is ONE module-level timestamp shared by
--      every spell, so the first lookup each interval consumes the refresh and every other
--      spell is served its stale value - which for a spell cached as "" is "" again.
--      Watch `sinceRefresh` staying pinned below the interval.
--
-- Run it WHILE the symptom is on screen. Run it again after the channel ends and diff the
-- two: what CHANGES between them is the cause, and any single reading is just a snapshot.
function DebugCommands.HotkeyProbe(addon)
    addon:Print("=== hotkey resolution ===")
    local ABS = LibStub("JustAC-ActionBarScanner", true)
    if not ABS then addon:Print("|cffff6600ActionBarScanner unavailable|r") return end

    -- The player's own cast info, as the renderer reads it (the cast bar's fields freeze
    -- when an addon replaces it). Plain for the player's own unit.
    local channeling = UnitChannelInfo("player") ~= nil
    local casting    = UnitCastingInfo("player") ~= nil
    addon:Print(string.format("state: channeling=%s casting=%s combat=%s",
        tostring(channeling), tostring(casting),
        tostring(UnitAffectingCombat and UnitAffectingCombat("player") or false)))

    local st = ABS.GetHotkeyCacheStats and ABS.GetHotkeyCacheStats()
    if st then
        -- slotEntries near zero with a climbing wipe count IS cause 2; a healthy cache with
        -- sinceRefresh pinned low is cause 3; a healthy cache and a stable count leaves 1.
        addon:Print(string.format("cache: hotkeys=%d slots=%d valid=%s  wipes=%d"
            .. "  sinceWipe=%.1fs  sinceRefresh=%.2fs",
            st.hotkeyEntries, st.slotEntries, tostring(st.valid), st.wipes,
            st.sinceWipe, st.sinceRefresh))
        if st.slotEntries == 0 then
            addon:Print("   |cffff6600slot cache EMPTY|r - the override scan has nothing to"
                .. " search, so any aura-driven transform resolves to no keybind")
        end
    end

    -- Per icon: what it is showing, what it cached, and what a FRESH lookup says right now.
    -- The cached-vs-fresh split matters: equal-and-empty means the lookup genuinely fails,
    -- while cached-empty but fresh-good means we are serving a stale blank.
    local icons = addon.spellIcons
    for i = 1, math.min(icons and #icons or 0, 4) do
        local icon = icons[i]
        local sid = icon and icon.spellID
        if sid then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
            local fresh = ABS.GetSpellHotkey and ABS.GetSpellHotkey(sid) or "?"
            local slot  = ABS.GetSlotForSpell and ABS.GetSlotForSpell(sid)
            local shownText = icon.hotkeyText and icon.hotkeyText:GetText() or ""
            addon:Print(string.format("  [%d] %-22s cached=%-8s fresh=%-8s slot=%-5s onScreen=%s",
                i, (info and info.name) or ("id " .. sid),
                (icon.cachedHotkey ~= nil and icon.cachedHotkey ~= "") and icon.cachedHotkey or "<empty>",
                (fresh ~= "") and fresh or "<empty>",
                tostring(slot or "none"),
                (shownText ~= "") and shownText or "<blank>"))
            -- WHICH LINK BROKE. Five of them fail independently and all five look the same
            -- on screen, so the chain is printed whenever the answer came back empty.
            if fresh == "" and ABS.DebugResolveHotkey then
                local r = ABS.DebugResolveHotkey(sid)
                addon:Print(string.format("       chain: name=%s slot=%s macro=%s%s parse=%s"
                    .. " mods=%s baseKey=%s",
                    r.name and "ok" or "|cffff0000NIL|r",
                    r.slot and tostring(r.slot) or "|cffff0000NIL|r",
                    tostring(r.isMacro or false),
                    r.macroName and ("(" .. r.macroName .. ")") or "",
                    r.isMacro and (r.macroFound and "ok" or "|cffff0000NIL|r") or "-",
                    r.modifiers and tostring(r.modifiers) or "-",
                    r.baseKey and tostring(r.baseKey) or "|cffff0000NIL|r"))
            end
        end
    end
    addon:Print("Run again AFTER the channel ends and compare - the field that changes is the cause.")
    addon:Print("=========================")
end

function DebugCommands.CurseDiagnostics(addon)
    local MT = LibStub("JustAC-MaintenanceTracker", true)
    local function read(fn, ...)
        if not fn then return "unavailable" end
        local ok, value = pcall(fn, ...)
        if not ok then return "denied:" .. SafeSecret(value) end
        if IsSecret(value) then return "secret" end
        if value == nil then return "unknown" end
        return SafeSecret(value), value
    end
    local function metadata(info)
        if IsSecret(info) then return "secret" end
        if type(info) ~= "table" then return "unknown" end
        local fields = {}
        for _, key in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID",
            "category", "flags", "selfAura", "hasAura", "isKnown" }) do
            fields[#fields + 1] = key .. "=" .. read(function() return info[key] end)
        end
        fields[#fields + 1] = "linkedSpellIDs=" .. read(function()
            local ids = info.linkedSpellIDs
            if IsSecret(ids) then return ids end
            if type(ids) ~= "table" then return nil end
            local out = {}
            for i = 1, math.min(#ids, 32) do out[i] = read(function() return ids[i] end) end
            if #ids > 32 then out[#out + 1] = "truncated" end
            return table.concat(out, ",")
        end)
        return table.concat(fields, " ")
    end
    addon:Print("CURSE context combat=" .. read(UnitAffectingCombat, "player")
        .. " target=" .. read(UnitExists, "target")
        .. " hostile=" .. read(UnitCanAttack, "player", "target"))
    local viewers = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    local wanted = {}
    for _, name in ipairs(viewers) do
        local viewer = _G[name]
        addon:Print("CURSE viewer=" .. name .. " shown=" .. read(viewer and viewer.IsShown, viewer))
    end
    for _, id in ipairs({ 702, 980, 1714, 1490, 603, 704, 17862, 18223 }) do
        local active = read(MT and MT.IsTrackedAuraActive, id)
        local mapped = {}
        local entry = { cast = id, aura = id, stateKey = "tracked:" .. id }
        if MT and MT.ResolveCooldownIDs then
            local ok, ids = pcall(MT.ResolveCooldownIDs, entry)
            if not ok then
                mapped[1] = "denied:" .. SafeSecret(ids)
            elseif IsSecret(ids) then
                mapped[1] = "secret"
            elseif type(ids) == "table" then
                for cid, category in pairs(ids) do
                    mapped[#mapped + 1] = SafeSecret(cid) .. ":" .. SafeSecret(category)
                    if not IsSecret(cid) and type(cid) == "number" then wanted[cid] = true end
                end
                table.sort(mapped)
            else
                mapped[1] = "unknown"
            end
        else
            mapped[1] = "unavailable"
        end
        addon:Print(string.format("CURSE spell=%d tracked=%s mappings=%s",
            id, active, #mapped > 0 and table.concat(mapped, ",") or "none"))
    end
    local matched = {}
    local catalog = {}
    for cid in pairs(wanted) do
        local status, info = read(C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
        if type(info) == "table" then status = metadata(info) end
        catalog[#catalog + 1] = "CURSE catalog cid=" .. cid .. " " .. status
    end
    table.sort(catalog)
    for _, row in ipairs(catalog) do addon:Print(row) end
    for _, name in ipairs(viewers) do
        local viewer = _G[name]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            local rows = {}
            local matchCount = 0
            local ok, err = pcall(function()
                for item in pool:EnumerateActive() do
                    local cid = read(item.GetCooldownID, item)
                    local number = tonumber(cid)
                    if number and wanted[number] then
                        matched[number] = true
                        matchCount = matchCount + 1
                        rows[#rows + 1] = string.format(
                            "CURSE item viewer=%s cid=%s shown=%s active=%s spell=%s linked=%s auraUnit=%s activeSpell=%s",
                            name, cid, read(item.IsShown, item),
                            read(function() return item.isActive end),
                            read(item.GetSpellID, item), read(item.GetLinkedSpell, item),
                            read(item.GetAuraDataUnit, item),
                            read(function() return item.isActiveSpell end))
                    end
                end
            end)
            table.sort(rows)
            for _, row in ipairs(rows) do addon:Print(row) end
            if not ok then addon:Print("CURSE items viewer=" .. name .. " denied:" .. SafeSecret(err)) end
            addon:Print("CURSE items viewer=" .. name .. " matches=" .. matchCount)
        else
            addon:Print("CURSE items viewer=" .. name .. " pool=unavailable")
        end
    end
    local missing = {}
    for cid in pairs(wanted) do
        if not matched[cid] then missing[#missing + 1] = tostring(cid) end
    end
    table.sort(missing)
    addon:Print("CURSE unmatched=" .. (#missing > 0 and table.concat(missing, ",") or "none"))
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
    local function plainNum(x)
        return type(x) == "number" and not IsSecret(x)
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
    local function RB(v)  -- ReadableBool: true/false when plain, "SECRET" when not
        if v == nil then return "nil" end
        if IsSecret(v) then return "SECRET" end
        return v and "T" or "F"
    end
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local class = select(2, UnitClass("player"))
    local groups = SpellDB and SpellDB.CLASS_MAINTAINED_BUFFS and SpellDB.CLASS_MAINTAINED_BUFFS[class]

    -- ENGINE REGISTRY vs CURATED TABLE (12.1.0+). The whole reason to adopt
    -- GetGroupBuffItems is that curation cannot keep up with patches, so the useful
    -- output is the DIFFERENCE: an engine entry the curated groups do not claim is
    -- coverage we only get from the engine, and a curated group with no engine
    -- counterpart is either an aura-variant detail the registry omits or curation
    -- that has gone stale.
    local engine = BlizzardAPI and BlizzardAPI.GetGroupBuffItems and BlizzardAPI.GetGroupBuffItems()
    if not engine then
        addon:Print("|cff888888engine registry: C_CooldownViewer.GetGroupBuffItems unavailable"
            .. " (pre-12.1.0) - curated table is the only source|r")
    else
        local covered = {}
        for _, grp in ipairs(groups or {}) do
            for _, id in ipairs(grp.group) do covered[id] = true end
            for _, id in ipairs(grp.auraIDs or {}) do covered[id] = true end
        end
        addon:Print(string.format("|cff00ccffengine registry:|r %d entries", #engine))
        for i = 1, #engine do
            local it = engine[i]
            addon:Print(string.format("   %-28s (%d) known=%s hideByDefault=%s  %s",
                tostring(it.name), it.spellID, tostring(it.isKnown), tostring(it.hideByDefault),
                covered[it.spellID] and "|cff888888curated|r"
                    or (it.isKnown and "|cff2ecc71NEW - engine-only coverage|r" or "not known")))
        end
    end
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
                            if sid == nil or IsSecret(sid) then
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
-- /jac inspect topoff [off] - watch the between-pulls heal reminder decide.
-- Samples every 0.25s and prints only TRANSITIONS, so a flicker shows up as a
-- pair of lines with a timestamp gap instead of a wall of text. Every input the
-- decision uses is listed side by side, so the oscillating one is obvious.
--------------------------------------------------------------------------------
function DebugCommands.TopoffWatch(addon, arg)
    if DebugCommands._topoffWatch then
        DebugCommands._topoffWatch:SetScript("OnUpdate", nil)
        DebugCommands._topoffWatch = nil
        addon:Print("topoff watch: OFF")
        addon:Print("/reload to flush transitions to JustACGlobal.probeLog")
        if arg == "off" then return end
    elseif arg == "off" then
        addon:Print("topoff watch: not running")
        return
    end

    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local Engine = LibStub("JustAC-PrecombatEngine", true)
    if not (BAPI and Engine) then addon:Print("topoff watch: modules unavailable") return end

    local f = CreateFrame("Frame")
    DebugCommands._topoffWatch = f
    local last, t = nil, 0
    local function sample(e)
        t = t + e
        if t < 0.25 then return end
        t = 0
        local profile = addon.db and addon.db.profile
        local offerTopoff = profile and profile.precombatBuffs and profile.precombatBuffs.topoffHeal == true
        local topoffPct = profile and profile.precombatBuffs and profile.precombatBuffs.topoffThreshold
        -- Ask the engine for the live list, exactly as the defensive queue does.
        local list = Engine.GetMissingClassBuffs and Engine.GetMissingClassBuffs(offerTopoff, topoffPct,
            profile and profile.precombatBuffs and profile.precombatBuffs.stealth,
            profile and profile.precombatBuffs and profile.precombatBuffs.categories) or {}
        local offered = Engine.offeredTopoffHeal
        local inList = false
        for i = 1, #list do if list[i] == offered then inList = true break end end

        -- Guard THEN call - an `and` chain yields one value and dropped `estimated`, so this
        -- reported an estimate as though it were a measured percent.
        local pct, estimated
        if BAPI.GetPlayerHealthPercentSafe then pct, estimated = BAPI.GetPlayerHealthPercentSafe() end
        local state = table.concat({
            "offer=" .. tostring(offered),
            "inList=" .. tostring(inList),
            "full=" .. tostring(BAPI.IsUnitFullHealth and BAPI.IsUnitFullHealth("player")),
            "below" .. tostring(topoffPct or "?") .. "=" .. tostring(BAPI.IsUnitHealthBelow
                and topoffPct and BAPI.IsUnitHealthBelow("player", topoffPct)),
            "sustainedRegen=" .. tostring(BAPI.HasSustainedPlayerHealthActivity and BAPI.HasSustainedPlayerHealthActivity()),
            "recentEvent=" .. tostring(BAPI.HasRecentPlayerHealthActivity and BAPI.HasRecentPlayerHealthActivity()),
            "postCombat=" .. tostring(BAPI.IsInPostCombatDowntime and BAPI.IsInPostCombatDowntime()),
            "allyLowKey=" .. tostring(BAPI.IsUnitLow and BAPI.IsUnitLow("player")),
            "pct=" .. tostring(pct) .. (estimated and "(est)" or "(exact)"),
        }, " ")
        if state ~= last then
            last = state
            addon:Print(string.format("|cff888888[%.1f]|r %s", GetTime() % 1000, state))
            ProbeLogEmit(string.format("%.2f TOPOFF %s", GetTime(), state))
        end
    end
    f:SetScript("OnUpdate", function(_, e)
        local ok, err = pcall(sample, e)
        if not ok then
            ProbeLogEmit("TOPOFF ERROR: " .. SafeSecret(err))
            DebugCommands.TopoffWatch(addon, "off")
            addon:Print("topoff watch: sample failed: " .. SafeSecret(err))
        end
    end)
    addon:Print("|cff00ff00topoff watch: ON|r - stand damaged out of combat and watch which value flips with the icon. /jac inspect topoff off")
end
