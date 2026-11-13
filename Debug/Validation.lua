-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end
local ProbeLogEmit = DebugCommands._Capture.ProbeLogEmit
local ProbeLogStore = DebugCommands._Capture.ProbeLogStore
local LogProxy = DebugCommands._Capture.LogProxy
local IsSecret = DebugCommands._Common.IsSecret
local SafeSecret = DebugCommands._Common.SafeSecret
local ProbeRead = DebugCommands._Common.ProbeRead
local ClassifyRead = DebugCommands._Common.ClassifyRead
local NameplateCastBar = DebugCommands._Common.NameplateCastBar
local SpellLabel = DebugCommands._Common.SpellLabel
local ProbeColour = DebugCommands._Common.ProbeColour
local RotationIds = DebugCommands._Common.RotationIds

--------------------------------------------------------------------------------
-- One configured health or power threshold, using the production helper.
--------------------------------------------------------------------------------
function DebugCommands.ThresholdDiagnostics(addon, arg)
    local profile = addon:GetProfile()
    local pre = profile and profile.precombatBuffs
    local kind, value
    if not arg or arg == "" then
        kind, value = "health", pre and pre.topoffThreshold
    else
        kind, value = arg:match("^(%a+)%s+(%d+%.?%d*)$")
        value = tonumber(value)
    end

    if (kind ~= "health" and kind ~= "power") or not value or value <= 0 or value > 100 then
        addon:Print("Usage: /jac inspect threshold health|power <percent 1-100>; omit arguments for configured topoff")
        return
    end
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local gate
    if BAPI then
        if kind == "health" then gate = BAPI.IsUnitHealthBelow else gate = BAPI.IsUnitPowerBelow end
    end
    if not gate then
        addon:Print("threshold: health/power helper unavailable")
        return
    end
    local ok, below, source = pcall(gate, "player", value)
    if not ok then
        addon:Print("threshold: read failed: " .. SafeSecret(below))
        return
    end
    local verdict = "unknown"
    if not IsSecret(below) then
        if below == true then verdict = "true" elseif below == false then verdict = "false" end
    end
    addon:Print(string.format("  player %s below %g%%: %s (combat=%s)",
        kind, value, verdict, tostring(UnitAffectingCombat("player"))))
    if source then addon:Print("  health decision source: " .. SafeSecret(source)) end
    if kind == "health" and pre and value == pre.topoffThreshold then
        addon:Print("  topoff enabled: " .. tostring(pre.topoffHeal == true)
            .. "; threshold only - learned ability, readiness and other offer gates still apply")
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
    local nm = SpellLabel

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
            numStr = IsSecret(st) and "|cffff6600startTime SECRET|r" or ("startTime=" .. tostring(st))
            if not IsSecret(act) and act ~= nil then
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
                elseif IsSecret(v) then
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

--- Bounded aura-enumeration capability check. Denied/secret reads are not counts;
--- readable instance multiplicity alone does not establish a combat stack route.
local function CountPlayerAuraInstances()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local n = 0
    for i = 1, 60 do
        local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if IsSecret(data) then return data end
        if data == nil then return n end
        n = n + 1
    end
    return nil -- Reaching the scan cap cannot establish a complete count.
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
            local info = caa and caa.partyHealthInfo and caa.partyHealthInfo.unitInfo
            local player = info and info["player"]
            return player and player.frequency end,
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
-- Assumption Validation Suite
-- /jac inspect validate       - one-shot sweep of every load-bearing API read
-- /jac inspect validate arm   - also re-captures on combat enter/exit and prints
--                               only what changed class (readable/secret/sealed)
-- Every probe is classified: ok:<value> | secret | SEALED (threw) | nil | absent.
-- Nothing is written or branched on a secret; reads are pcall-guarded.
--------------------------------------------------------------------------------

-- C_Secrets function count at last full audit (12.0.7, 2026-07-05). If the live
-- count differs, the secrecy surface changed and every assumption needs re-audit.
-- Re-checked against the 12.1.0 generated docs before that patch shipped: the
-- C_Secrets surface is unchanged, so this guard should stay quiet across it.
local SECRETS_SURFACE_COUNT = 27

--- @return string class the diff key - what a CHANGE between snapshots means
--- @return string display the coloured cell
local function ValidateClassify(fn)
    local status, text, v = ProbeRead(fn, 24)
    local cell = ProbeColour(status) .. (status == "err" and "SEALED" or text) .. "|r"
    if status == "err" then return "SEALED", cell end
    if status == "nil" then return "nil", cell end
    if status == "secret" then return "secret", cell end
    -- Booleans are state, not noise: track the VALUE so a predicate flipping
    -- false->true in combat shows in the diff. Numbers (cooldown clocks etc.)
    -- churn constantly - class-only for those.
    if type(v) == "boolean" then return "ok:" .. text, cell end
    return "ok", cell
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
        return NameplateCastBar(np)
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

    -- TECHNIQUE SELF-TESTS. Everything above measures what the client will TELL us;
    -- these measure whether the mechanisms the addon is BUILT ON still work. That is
    -- a different failure and a much quieter one: when a threshold curve or the
    -- zero-gate stops answering, nothing errors - every caller fails open, the
    -- addon silently reverts to its estimates, and the only symptom is that cues
    -- feel slightly wrong. Each check below has a KNOWN answer, so "ok" means the
    -- mechanism actually produced the right result, not merely that the API exists.
    add("tech.curveAPI", function()
        return (C_CurveUtil and C_CurveUtil.CreateCurve
            and Enum.LuaCurveType.Linear ~= nil) and true or false
    end)
    add("tech.curveShape", function()
        -- A 50% threshold curve, evaluated with PLAIN inputs either side of it. The
        -- domain is the 0-1 fraction; below the threshold reads high, at/above reads
        -- zero. Backwards or flat here means every threshold gate in the addon is
        -- silently inverted or dead.
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Linear)
        c:AddPoint(0, 100); c:AddPoint(0.499, 100); c:AddPoint(0.501, 0); c:AddPoint(1, 0)
        return (c:Evaluate(0.4) >= 1 and c:Evaluate(0.6) < 1) and "ok" or "BROKEN"
    end)
    add("tech.zeroGate", function()
        -- The zero-gate, end to end on PLAIN numbers: truncate-when-zero collapses 0
        -- to nil and leaves a non-zero alone, and a FontString hands the result back
        -- readable. Both halves must hold - this is what turns a secret into a
        -- branchable boolean everywhere in the addon.
        if not (C_StringUtil and C_StringUtil.TruncateWhenZero) then return "no API" end
        local fs = DebugCommands._validateFS
        if not fs then
            fs = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
            fs:Hide(); DebugCommands._validateFS = fs
        end
        fs:SetText(C_StringUtil.TruncateWhenZero(0) or "")
        local emptyReadsNil = fs:GetText() == nil
        fs:SetText(C_StringUtil.TruncateWhenZero(42) or "")
        local valueReadsBack = fs:GetText() ~= nil
        return (emptyReadsNil and valueReadsBack) and "ok" or "BROKEN"
    end)
    add("tech.zeroGatePlain", function()
        -- The addon's own wrapper on its PLAIN fast path (0 is zero). Only proves the
        -- module loaded and the fast path is sane; the secret-widget path needs a live
        -- secret, which durcurve exercises. Disagreeing with the raw check above
        -- localises a break to our code rather than the client.
        return BAPI and BAPI.IsSecretZero and BAPI.IsSecretZero(0)
    end)
    add("tech.thresholdGate", function()
        return BAPI and BAPI.IsThresholdGateAvailable and BAPI.IsThresholdGateAvailable()
    end)
    add("tech.durationEval", function()
        -- The three Evaluate* entry points the duration thresholds ride on. Method
        -- presence only: a real verdict needs a live aura, which durcurve does.
        local d = C_Spell.GetSpellCooldownDuration(sid)
        if not d then return "no durObj" end
        return (d.EvaluateRemainingPercent and d.EvaluateRemainingDuration
            and d.EvaluateTotalDuration) and "ok" or "MISSING"
    end)
    add("tech.stackCount", function()
        return (C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount) ~= nil
    end)
    add("tech.groupBuffItems", function()
        return (C_CooldownViewer and C_CooldownViewer.GetGroupBuffItems) ~= nil
    end)

    return probes
end

local function PrintValidateEnv(addon)
    -- SafeSecret, not tostring: tostring propagates secrecy silently, so the old body
    -- could print a secret as if it were a plain value.
    local function vs(fn)
        local ok, v = pcall(fn)
        return ok and SafeSecret(v) or "SEALED"
    end
    addon:Print("  where: zone=" .. vs(function() return (GetInstanceInfo()) end)
        .. " type=" .. vs(function() return select(2, GetInstanceInfo()) end)
        .. " diff=" .. vs(function() return select(4, GetInstanceInfo()) end)
        .. " map=" .. vs(function() return C_Map.GetBestMapForUnit("player") end)
        .. " instID=" .. vs(function() return select(8, GetInstanceInfo()) end))
    addon:Print("  state: combat=" .. tostring(UnitAffectingCombat("player"))
        .. " resting=" .. vs(IsResting)
        .. " group=" .. (IsInRaid() and "raid" or IsInGroup() and "party" or "solo")
        .. " spec=" .. vs(function() return select(2, C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())) end)
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

--------------------------------------------------------------------------------
-- The optional research companion replaces this battery with its wider sweep.
--------------------------------------------------------------------------------
function DebugCommands.RunProbeBattery(addon, tag, includeStatic)
    local started = debugprofilestop and debugprofilestop()
    local session = DebugCommands._diagnosticSession
    local failures = 0
    local proxy = LogProxy(addon)
    ProbeLogEmit(string.format("===== %s @ %.1f research=unavailable =====", tag, GetTime()))
    local function run(method)
        local ok, err = pcall(DebugCommands[method], proxy)
        if not ok then
            failures = failures + 1
            ProbeLogEmit("PROBE ERROR " .. method .. ": " .. SafeSecret(err))
        end
    end
    if includeStatic then run("SecrecyMapProbe") end
    run("ValidateAssumptions")
    run("DurationProbe")
    if session then
        session.failures = session.failures + failures
        if started then
            local elapsed = debugprofilestop() - started
            session.batteries = (session.batteries or 0) + 1
            session.batteryMs = (session.batteryMs or 0) + elapsed
            session.batteryMaxMs = math.max(session.batteryMaxMs or 0, elapsed)
        end
    end
    addon:Print(string.format("audit: %s snapshot captured (%d failures, %d log lines held).",
        tag, failures, #ProbeLogStore()))
end
