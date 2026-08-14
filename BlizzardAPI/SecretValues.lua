-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Secret Value Utilities, Feature Availability, Secrecy API Wrappers (12.0+)
-- Extends the JustAC-BlizzardAPI library. Loaded by JustAC.toc after CooldownTracking.lua.
local SUBMAJOR, SUBMINOR = "JustAC-BlizzardAPI-SecretValues", 2
local Sub = LibStub:NewLibrary(SUBMAJOR, SUBMINOR)
if not Sub then return end
local BlizzardAPI = LibStub("JustAC-BlizzardAPI")

-- Hot path cache
local GetTime    = GetTime
local pcall      = pcall
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local C_SpellActivationOverlay_IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local IsSecretValue = BlizzardAPI.IsSecretValue
local Unsecret      = BlizzardAPI.Unsecret

--------------------------------------------------------------------------------
-- Feature Availability (12.0+ secret value graceful degradation)
--------------------------------------------------------------------------------

-- Aura access is NOT cached here: BlizzardAPI.AreAurasSecret() is one live C
-- call that flips exactly at combat edges (validated in-game 12.0.7), so it is
-- consulted directly wherever aura availability matters.
local featureAvailability = {
    healthAccess = true,
    procAccess = true,
    lastCheck = 0,
}
local FEATURE_CHECK_INTERVAL = 30.0  -- Safety net only; events (PLAYER_REGEN_*) are the primary trigger

-- UnitHealth("player") confirmed NOT secret as of 12.0 Alpha 6
local function TestHealthAccess()
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    return not IsSecretValue(health) and not IsSecretValue(maxHealth)
end

-- IsSpellOverlayed may return secret boolean in 12.0
-- GetRotationSpells() returns a flat array of spell ID numbers (not objects)
local function TestProcAccess()
    if not C_SpellActivationOverlay_IsSpellOverlayed then return true end

    local ok, result = pcall(function()
        if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
            local spells = C_AssistedCombat.GetRotationSpells()
            if spells and spells[1] then
                local hasProc = C_SpellActivationOverlay_IsSpellOverlayed(spells[1])
                if IsSecretValue(hasProc) then return false end
            end
        end
        return true
    end)

    if not ok then return true end
    return result
end

local function RefreshFeatureAvailability()
    local now = GetTime()
    if now - featureAvailability.lastCheck < FEATURE_CHECK_INTERVAL then
        return
    end

    local oldHealthAccess = featureAvailability.healthAccess
    local oldProcAccess = featureAvailability.procAccess

    featureAvailability.healthAccess = TestHealthAccess()
    featureAvailability.procAccess = TestProcAccess()
    featureAvailability.lastCheck = now

    local debugMode = BlizzardAPI.GetDebugMode()
    if debugMode then
        local addon = BlizzardAPI.GetAddon and BlizzardAPI.GetAddon()
        if addon and addon.Print then
            if oldHealthAccess ~= featureAvailability.healthAccess then
                addon:Print("Health API access: " .. (featureAvailability.healthAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
            if oldProcAccess ~= featureAvailability.procAccess then
                addon:Print("Proc API access: " .. (featureAvailability.procAccess and "AVAILABLE" or "BLOCKED (secrets)"))
            end
        end
    end
end

function BlizzardAPI.IsProcFeatureAvailable()
    RefreshFeatureAvailability()
    return featureAvailability.procAccess
end

function BlizzardAPI.RefreshFeatureAvailability()
    featureAvailability.lastCheck = 0
    RefreshFeatureAvailability()
end

function BlizzardAPI.GetFeatureAvailability()
    RefreshFeatureAvailability()
    return {
        healthAccess = featureAvailability.healthAccess,
        auraAccess = not BlizzardAPI.AreAurasSecret(),
        procAccess = featureAvailability.procAccess,
    }
end

-- IsSecretValue() and Unsecret() are defined in BlizzardAPI.lua (root)
-- so all submodules can upvalue them. No additional definitions needed here.

--------------------------------------------------------------------------------
-- API-Specific Secret-Aware Helpers
--------------------------------------------------------------------------------

-- Branchable "is this (possibly secret) amount zero or absent?" - the
-- scratch-FontString emptiness gate, in-game validated 2026-08-10
-- (`/jac inspect textlaunder`). The legal mechanics it composes:
--   * C_StringUtil.TruncateWhenZero accepts secrets and yields an EMPTY STRING for
--     zero, a (secret) string otherwise - the engine makes the only decision. It is
--     documented Nilable = false, so it never returns nil; keep the `or ""` anyway,
--     it costs nothing and the contract could widen.
--   * The nil this gate actually branches on comes one step later, from GetText's
--     empty-collapse - and THAT is measured, not contracted (GetText is likewise
--     documented Nilable = false). In-game 2026-08-10. Treat it as a field fact with
--     a self-test behind it, never as a guarantee.
--   * SetText("") reads back as PLAIN nil even on a widget whose Text aspect
--     is already poisoned, so ONE pooled widget is safe here: the sticky-aspect
--     trap only bites PLAIN-content readback, which this never does.
--   * Truthiness of the secret-string readback is legal (non-boolean rule).
-- Returns true (zero/absent), false (non-zero), or NIL when the technique is
-- unavailable on this client - callers MUST treat nil as "no answer" and fall
-- back to their heuristics, never as either verdict.
local zeroScratch
local zeroCanClear      -- widget supports ClearText (12.1+) and it worked once
local zeroProbeArg      -- hoisted: a per-call closure would allocate on a hot path
local function ZeroProbe()
    -- Clear FIRST where the client allows it (12.1 ClearText is documented as
    -- removing the Text secret aspect). Then the zero branch reads back from a
    -- widget carrying no aspect at all, instead of resting on the observation
    -- that a POISONED widget's empty readback still comes back plain. Same
    -- answer either way today; this one stays right if that ever changes.
    if zeroCanClear then zeroScratch:ClearText() end
    -- Resolved per call, not at file load: C_StringUtil may not exist yet when this
    -- file runs, and a nil captured then would disable the gate for the session.
    zeroScratch:SetText(C_StringUtil.TruncateWhenZero(zeroProbeArg) or "")
    return zeroScratch:GetText()
end

local function NewScratchFontString()
    local ok, holder = pcall(CreateFrame, "Frame")
    if not ok or not holder then return nil end
    holder:Hide()
    local okFS, fs = pcall(holder.CreateFontString, holder, nil, "BACKGROUND", "GameFontNormal")
    if not okFS or not fs then return nil end
    -- A FontString with no font ERRORS on SetText. The template above supplies one,
    -- but a broken/replaced font object would take the whole gate down, so make sure.
    if not fs:GetFontObject() and not fs:GetFont() then
        pcall(fs.SetFontObject, fs, GameFontNormal)
    end
    return fs
end

local function GetZeroScratch()
    if zeroScratch then return zeroScratch end
    local fs = NewScratchFontString()
    if not fs then return nil end
    -- Probed ONCE here, not per call: a per-probe pcall would double the cost of
    -- the hot path to guard a method that either exists and works or does not.
    zeroCanClear = fs.ClearText ~= nil and pcall(fs.ClearText, fs) or false
    zeroScratch = fs
    return fs
end

-- Does GetText still hand text back AT ALL? A dead readback and a genuine zero arrive as
-- the same nil, so without this the gate would answer "zero" for every secret in the game.
--
-- KNOW WHAT THIS DOES AND DOES NOT CATCH - it is a partial guard, deliberately kept.
--   CATCHES a CALLER-level denial: GetText stops answering this addon regardless of widget.
--     That is the shape 12.1.0 used on the aura family (RequiresUnitAuraAccess), so it is a
--     real thing that happens, and a clean widget detects it.
--   MISSES an OBJECT-conditional denial. RequiresFontStringTextAccess - the predicate the
--     two getters either side of GetText already carry - is a property of the OBJECT, so a
--     widget that never held a secret would keep answering while the poisoned one returned
--     nothing. This check would say "fine" and the gate would still lie.
-- Catching that second shape means probing with a widget that HAS held a secret, i.e.
-- secretwrap'd input, and it would need a THIRD scratch string: the plain == compare below
-- must never run against a readback from a widget that has carried a secret.
-- Not built, because there is no present-day defect - GetText carries only
-- SecretReturnsForAspect{Text} today, no Requires* predicate at all - and the fix would rest
-- on a schema flag that appears nowhere in the generated docs. Revisit if GetText's
-- annotations change; that is the trigger, not a hunch.
--
-- Its OWN widget, never given a secret. The note above explains that the sticky Text aspect
-- only bites PLAIN-content readback - which is exactly what this is - so this test must
-- never run on the poisoned one. Same shape as BuildStepCurve's self-test: plain inputs,
-- proving the technique before it is trusted.
local checkScratch
local CHECK_TEXT = "1"
local function TextReadbackWorks()
    if checkScratch == nil then checkScratch = NewScratchFontString() or false end
    if not checkScratch then return false end
    local ok, back = pcall(function()
        checkScratch:SetText(CHECK_TEXT)
        return checkScratch:GetText()
    end)
    return ok and back == CHECK_TEXT
end

function BlizzardAPI.IsSecretZero(v)
    if v == nil then return true end
    if not (IsSecretValue and IsSecretValue(v)) then
        -- Plain fast path: no widget needed, and non-numbers are "no answer".
        if type(v) == "number" then return v == 0 end
        return nil
    end
    if not (C_StringUtil and C_StringUtil.TruncateWhenZero) then return nil end
    if not GetZeroScratch() then return nil end
    zeroProbeArg = v
    local ok, text = pcall(ZeroProbe)
    zeroProbeArg = nil          -- never hold a secret alive in an upvalue
    if not ok then return nil end
    -- Truthiness on a (secret) string is legal - the non-boolean rule.
    --
    -- Text CAME BACK: the readback demonstrably works, so this is a real non-zero and
    -- no verification is needed. The common branch stays exactly as cheap as before.
    if text then return false end
    -- Text did NOT come back, and that is AMBIGUOUS - a genuine zero and a GetText that
    -- has stopped answering are the same nil. Only here is the extra round-trip worth
    -- paying for. Deliberately live rather than cached: the access predicates flip at
    -- combat edges, so a once-per-session check would pass out of combat and then let
    -- this lie for the whole fight, which is the exact failure it exists to catch.
    if not TextReadbackWorks() then return nil end
    return true
end

--- Is the zero-gate's readback still answering? Exported so the failure it guards against
--- is REPORTABLE: without this, a dead readback and a gate that was never available both
--- present as "no answer", and the difference decides whether a patch broke the layer or
--- the client simply never had it. Plain inputs, no secret - safe to call anywhere.
function BlizzardAPI.IsTextReadbackWorking()
    return TextReadbackWorks()
end

--- 12.1.0: GetAuraDataByIndex is ACCESS-DENIED to a tainted caller while auras are secret -
--- it throws rather than returning secrets, and the denial applies even where the caller has
--- already read that aura's fields plainly. So the pcall is not belt-and-braces: this is
--- reached from RefreshAuraCache's NOT-secret branch, where a readable NeverSecret aura in
--- combat still cannot be re-read by index. nil,nil is the existing "timing unknown" answer.
function BlizzardAPI.GetAuraTiming(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil, nil end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok or not aura then return nil, nil end
    return Unsecret(aura.duration), Unsecret(aura.expirationTime)
end

--------------------------------------------------------------------------------
-- Batch aura reads (12.0 C_UnitAuras.GetUnitAuras)
--
-- MEASURED in combat with restrictions latched (follower-dungeon boss, 12.0.7):
-- the returned TABLE and its length are PLAIN; only the per-aura FIELDS are
-- secret. That is the documented `ConditionalSecretContents` behaviour, and it
-- means one C call replaces the up-to-40 GetAuraDataByIndex calls every caller
-- used to make. Field-level secrecy is unchanged, so each caller keeps its own
-- secret handling - this helper only supplies the list.
--------------------------------------------------------------------------------

local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras

--- Array of AuraData for unit/filter, or nil if auras can't be enumerated at all.
--- Falls back to the index loop on clients without the batch call.
function BlizzardAPI.GetAuras(unit, filter)
    if not unit then return nil end
    if GetUnitAuras then
        local ok, list = pcall(GetUnitAuras, unit, filter)
        if ok and type(list) == "table" then return list end
        -- Fall through to the index loop: a throw here means this unit/filter
        -- combination is rejected, not that the API is missing.
    end
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not byIndex then return nil end
    local list = {}
    for i = 1, 40 do
        local ok, data = pcall(byIndex, unit, i, filter)
        if not ok then
            -- DENIED, not empty. 12.1.0 made these calls throw for a tainted caller
            -- (RequiresUnitAuraAccess), and a denial refuses index 1 exactly like it
            -- refuses index 40. Returning the empty `list` here hands back a TRUTHY
            -- table of length 0, which every `if not list then` guard waves through
            -- and every counter reads as a confident "no such auras" - turning this
            -- function's whole fail-open contract into its opposite. Nil means
            -- "could not tell", which is what the callers are written against.
            return i > 1 and list or nil
        end
        if not data then break end
        list[i] = data
    end
    return list
end

-- Unknown category tokens FAIL OPEN: the engine silently IGNORES a token it does
-- not recognise and returns the unfiltered set rather than erroring (measured -
-- a bogus token returned all 31 helpful auras while BIG_DEFENSIVE returned 1).
-- So a token retired by a future patch would degrade into a permanently-true
-- gate instead of a visible failure. Guard: if a narrowed filter ever returns
-- exactly as many auras as its own base filter - with more than one aura in
-- play, since a single aura could legitimately be the match - the token is not
-- being honoured and that filter is abandoned for the session.
local filterVerdict = {}   -- filter string -> true (honoured) | false (ignored)

--- Count of auras matching an engine category filter, or nil when the filter
--- cannot be trusted. nil means "unknown" - callers fail open.
function BlizzardAPI.CountAuras(unit, filter)
    unit = unit or "player"
    if filterVerdict[filter] == false then return nil end
    local list = BlizzardAPI.GetAuras(unit, filter)
    if not list then return nil end
    local n = #list
    -- Only a narrowed filter can be ignored, and only a multi-aura sample can
    -- reveal it. Once proven honoured, stop paying for the second call.
    local base = filter and filter:match("^[^|]+")
    if n > 1 and base and base ~= filter and filterVerdict[filter] == nil then
        local all = BlizzardAPI.GetAuras(unit, base)
        if all and #all == n then
            filterVerdict[filter] = false
            return nil
        end
        filterVerdict[filter] = true
    end
    return n
end

--- True when the unit has a major defensive cooldown up. The engine does the
--- classification, so this needs no curated list and reads no secret: only the
--- COUNT is consulted, never an aura's identity. nil = unknown (fail open).
function BlizzardAPI.HasBigDefensive(unit)
    local n = BlizzardAPI.CountAuras(unit or "player", "HELPFUL|BIG_DEFENSIVE")
    if n == nil then return nil end
    return n > 0
end


