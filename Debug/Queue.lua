-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- Extends JustAC-DebugCommands; loaded explicitly by JustAC.toc.
local DebugCommands = LibStub("JustAC-DebugCommands", true)
if not DebugCommands then return end
local IsSecret = DebugCommands._Common.IsSecret
local SafeSecret = DebugCommands._Common.SafeSecret
local ProbeRead = DebugCommands._Common.ProbeRead
local SpellLabel = DebugCommands._Common.SpellLabel

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
            profile.hideItemAbilities and "Offensive tab: Allow Item Abilities is OFF" or "equipped-item ability")
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
        or (noRes and "lacking resources - sinks behind affordable abilities" or nil))
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
    local heldByDial = SpellQueue.IsHeldByHold
        and SpellQueue.IsHeldByHold(spellID) or false
    if heldByDial then
        line("Hold released", false,
            "a Hold Until dial is set for this ability and its condition is not met - "
            .. "parked at the back until it is")
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
    local queueContext = SpellQueue.DebugContextState and SpellQueue.DebugContextState()
    if queueContext and queueContext.pullOpenerID == displayID then
        note("Forever pull opener: Lightning Bolt is preferred before combat; its combat-only Maelstrom requirement is waived")
    end
    if queueContext and queueContext.efficiencyID == displayID then
        note("Efficiency: " .. tostring(queueContext.efficiencyReason)
            .. " using this free attack")
    end
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
    local FW = LibStub("JustAC-FightWindow", true)
    local stuck = FW and FW.StuckSeconds and (FW.StuckSeconds(effectiveID) or FW.StuckSeconds(displayID))
    if stuck then
        addon:Print(string.format("  |cffffcc00Stuck pick|r - the game asked for this for %.0fs this session while "
            .. "you pressed other things and never pressed it. Is it on your bars and bound?", stuck))
    end
    addon:Print("==============================")
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
            local name = C_Item.GetItemInfo(-id)
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
    -- Wasted-cooldown guard. Prints WHY it is off as well as whether it is: the
    -- enemy count and the boss read are the two clauses that silently keep it off,
    -- and a guard that never fires looks identical to one that is broken.
    -- Fetched locally: BlizzardAPI is not a file-local here, and reading it bare
    -- would be a nil global (a probe that errors instead of reporting).
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local dyingWhy
    if ctx.dying then
        dyingWhy = "|cffff8800sinking burst cooldowns|r"
    elseif (ctx.enemies or 0) ~= 1 then
        dyingWhy = string.format("|cff888888off - engaged enemies = %d (needs exactly 1)|r",
            ctx.enemies or 0)
    elseif BAPI and BAPI.IsTargetBoss and BAPI.IsTargetBoss() then
        dyingWhy = "|cff888888off - target is a boss (execute phase, burn everything)|r"
    elseif not UnitExists("target") then
        dyingWhy = "|cff888888off - no target|r"
    else
        dyingWhy = "|cff888888off - target above the threshold (or gate unavailable)|r"
    end
    addon:Print("Dying-target guard: " .. dyingWhy)
    addon:Print("Efficiency (last build): " .. tostring(ctx.efficiencyReason or "not evaluated")
        .. "; promoted=" .. tostring(ctx.efficiencyID))
    addon:Print("  Resource decision: " .. tostring(ctx.efficiencyResourceDecision)
        .. "; estimate source=" .. tostring(ctx.efficiencyRecoverySource)
        .. "; combat/base seconds to full=" .. tostring(ctx.efficiencyFullSeconds)
        .. "/" .. tostring(ctx.efficiencyBaseFullSeconds))
    addon:Print("  Free attacks: " .. tostring(ctx.efficiencyCandidates)
        .. "; chosen reach=" .. tostring(ctx.efficiencyRange))
    addon:Print("  Fallback mana below configured threshold=" .. tostring(ctx.efficiencyManaBelow)
        .. "; detected enemies=" .. tostring(ctx.enemies))

    -- State the ACTIVE ordering mode, not just the disabled case. In "simc" - the default -
    -- the sort key is a COMPOSITE (context * stride + SimC position), applied within buckets
    -- that run procs -> normal -> unavailable. Printing the bare context rank there shows the
    -- major key only, so a spell sunk for being uncastable reads as a mis-sorted one. That is
    -- how a healthy queue (Rip rank=4 below Rake rank=5, because Rip was in the sunk bucket)
    -- looks like an ordering bug.
    local profile = addon.db and addon.db.profile
    local mode = (profile and profile.contextOrder) or "simc"
    if mode == "off" then
        addon:Print("|cffffff00Ordering: OFF|r - source order; ranks below are NOT applied.")
    elseif mode == "ac" then
        addon:Print("|cff00ff00Ordering: ac|r - the rank below IS the sort key.")
    else
        addon:Print("|cff00ff00Ordering: simc|r - sort key is |cffffff00ctx*stride + simc|r, "
            .. "bucketed procs -> normal -> unavailable. The rank below is the ctx part only.")
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
            -- In simc mode show the SimC component too: context alone cannot explain the
            -- order, and the pair does - two spells sharing a context rank are separated by
            -- it, and one sitting below a worse context rank was bucketed, not mis-sorted.
            local rankTag
            if i == 1 then
                rankTag = "|cff888888AC slot|r"
            else
                rankTag = "rank=" .. tostring(SpellQueue.DebugRankSpell and SpellQueue.DebugRankSpell(sid))
                if mode ~= "off" and mode ~= "ac" then
                    local RI = LibStub("JustAC-RotationImport", true)
                    local simcCtx = (ctx.arch == "aoe" and "aoe")
                        or (ctx.arch == "cleave" and "cleave") or "st"
                    local rec = RI and RI.GetEntry and RI.GetEntry(sid, simcCtx)
                    rankTag = rankTag .. " simc=" .. tostring((rec and rec.rank) or "unranked")
                end
            end
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
        local getDuration = SpellDB and (SpellDB.GetTargetAuraDuration or SpellDB.GetTargetDotDuration)
        local est = getDuration and getDuration(e.spellID)
        -- engine= is what DECIDED when it is not nil; est/pandemicIn is the
        -- cast-time projection it replaced. They diverge on a pandemic-refreshed
        -- DoT, where the projection fires early - the case this exists to fix.
        local engine = (e.enginePandemic == nil) and "|cff888888n/a (estimate used)|r"
            or (e.enginePandemic and "|cffffaa00INSIDE pandemic|r" or "|cff2ecc71live|r")
        addon:Print(string.format("  %s (%d)  %s  src=%s  expiresIn=%.1fs%s  est=%s  engine=%s",
            spellName(e.spellID), e.spellID,
            e.active and "|cffff5555active|r" or "|cff55ff55inactive|r",
            e.source or "unknown",
            e.expiresIn,
            e.pandemicIn and string.format("  pandemicIn=%.1fs", e.pandemicIn) or "",
            est and (est .. "s") or "unknown", engine))
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
    if not (RI and RI.HasRotation and RI.HasRotation() and BAPI) then
        addon:Print("|cffff6600No SimC gate data for this spec.|r")
        return
    end

    local nm = SpellLabel

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

    for _, ctx in ipairs({"st", "cleave", "aoe"}) do
        DebugCommands.SimcGateProbe(addon, ctx)
    end
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
    addon:Print("|cff00ccff== Resource-inference probe ==|r")

    -- 1. The direct read we're routing around (expected SECRET in combat).
    if UnitPower and UnitPowerType then
        local pt = UnitPowerType("player")
        local val = UnitPower("player", pt)
        addon:Print("UnitPower direct read: " .. (IsSecret(val)
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
        local secHit = IsSecret(usable) or IsSecret(noPower)
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
-- Fight window (/jac inspect window [selftest])
--------------------------------------------------------------------------------
function DebugCommands.FightWindowDump(addon, arg)
    local FW = LibStub("JustAC-FightWindow", true)
    if not FW then addon:Print("fight window not loaded") return end
    if arg == "selftest" then
        addon:Print("fight window selftest: " .. (FW.SelfTest() and "|cff00ff00pass|r" or "|cffff0000FAIL|r"))
        return
    end
    local arch, range = FW.MultiContext()
    addon:Print("|cff00ccff== fight window ==|r  multi-target context: "
        .. (arch and (arch .. "/" .. tostring(range)) or "none"))
    local rows = 0
    FW.ForEach(function(age, kind, id, tag)
        rows = rows + 1
        local info = id and id > 0 and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        addon:Print(string.format("  -%4.1fs  %s  %s%s", age,
            kind == "S" and "|cff00ff00served|r" or kind == "U" and "used  " or "|cff888888target|r",
            kind == "T" and "" or ((info and info.name or "?") .. " (" .. tostring(id) .. ")"),
            tag and ("  [" .. tag .. "]") or ""))
    end)
    if rows == 0 then addon:Print("  (empty - it fills in combat and clears when the fight ends)") end
end

--------------------------------------------------------------------------------
-- Assisted-combat pick recorder (/jac inspect picklog)
--------------------------------------------------------------------------------
-- Research probe for Documentation/ASSISTED_COMBAT_DATA_PLAN.md step 5. Blizzard's rotation
-- steps and their conditions are known offline, but the NUMERIC condition types are not
-- decoded. This records the game's pick next to every fact the addon can read, so
-- tools/audit_assisted_combat.py --decode can line the two up: a step that fired tells us
-- its conditions held, and the facts here say what was true at that moment.
-- Ships no rule data - the join happens offline. Same recorder shape as maintlog: plain
-- values only, change-only, ring-bounded, flushed by /reload.
local PICKLOG_MAX = 3000
local pickLogTicker = nil
local lastPickPayload = nil
local POWER_BANDS  = { 25, 50, 75 }
local HEALTH_BANDS = { 20, 35, 80 }

--- Do the imported conditions on this spell rule it out right now? The `why` codes
--- explained every OTHER reason the game's pick could lose its place, so a pick sunk by
--- its own gates showed up as "-" and looked like the queue misbehaving.
local function PickGated(RI, SQ, spellID, cur, resName, max)
    if not (RI and RI.GetEntry and SQ and SQ._SimcGateBlocks) then return false end
    local rec = RI.GetEntry(spellID)
    return (rec and rec.gates and SQ._SimcGateBlocks(rec.gates, cur, resName, max)) or false
end

local function PickLogSample()
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    local SDB = LibStub("JustAC-SpellDB", true)
    if not (BAPI and SDB) then return end
    local pick = BAPI.GetAnyNextCastSpell and BAPI.GetAnyNextCastSpell()
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    -- The assist's own wait placeholder comes back as a pick id (passive, timer icon
    -- 134377 - the renderer's WAIT test). For the log a wait is pick=0.
    if pick and BAPI.IsWaitPlaceholder and BAPI.IsWaitPlaceholder(pick) then pick = nil end
    if not pick and not inCombat then return end   -- a WAIT is a tick in combat
    -- What a wait means: mid-cast, GCD running, or truly nothing (pooling / all on cooldown).
    local waitWhy = ""
    if not pick then
        local casting = UnitCastingInfo("player") or UnitChannelInfo("player")
        waitWhy = casting and " w=cast" or (BAPI.IsSpellOnGCD and BAPI.IsSpellOnGCD(61304) and " w=gcd") or " w=idle"
    end
    -- Safe Lead dry run: what WOULD lead, and on which evidence class (plan phase 1).
    -- A trailing "!" on that field means the swap actually HAPPENED this tick, which is
    -- the difference between a proposal and the queue you were looking at.
    local SQ = LibStub("JustAC-SpellQueue", true)
    local slID, slCls
    if SQ and SQ.SafeLeadCandidate then slID, slCls = SQ.SafeLeadCandidate() end
    local cur, max, resName = nil, nil, nil
    if BAPI.GetClassResourcePoints then cur, max, resName = BAPI.GetClassResourcePoints() end
    local function n(v) return (type(v) == "number" and not issecretvalue(v)) and tostring(v) or "-" end
    -- What JustAC itself is leading with, and whether that entry is one only the game can
    -- time (delegated). With My List Leads on, lead ~= pick is normal; a DELEGATED lead that
    -- is not the pick is the queue promoting something it cannot know the moment for.
    local RI = LibStub("JustAC-RotationImport", true)
    local queue = SQ and SQ.GetCurrentSpellQueue and SQ.GetCurrentSpellQueue()
    local lead = type(queue) == "table" and queue[1] or nil
    if type(lead) ~= "number" or issecretvalue(lead) then lead = nil end
    local rec = lead and RI and RI.GetEntry and RI.GetEntry(lead)
    -- When the game's pick is NOT what we lead with, say why the pick lost its place:
    -- R not ready, S cannot afford, H held by a user dial, T its DoT is already up,
    -- B blacklisted, O out of range, U unusable for a non-resource reason, P the LEAD has a
    -- proc overlay, G one of its own imported conditions says no (a cooldown that is not
    -- ready, a threshold unmet, a group none of whose branches hold), "-" none of these.
    -- @N = the pick's own slot in the queue (0 = absent).
    local why = ""
    if pick and lead and lead ~= pick then
        local shown = BAPI.GetDisplaySpellID and BAPI.GetDisplaySpellID(pick) or pick
        if lead ~= shown then
            local DT = LibStub("JustAC-DotTracker", true)
            local _, notEnough = BAPI.IsSpellUsable(shown, true)
            why = ((BAPI.IsSpellReady and not BAPI.IsSpellReady(shown)) and "R" or "")
                .. (notEnough and "S" or "")
                .. ((SQ.IsHeldByHold and SQ.IsHeldByHold(shown)) and "H" or "")
                .. ((DT and DT.IsDotActiveOnCurrentTarget and DT.IsDotActiveOnCurrentTarget(shown)) and "T" or "")
                .. ((SQ.IsSpellBlacklisted and SQ.IsSpellBlacklisted(pick)) and "B" or "")
                .. ((SQ.IsConfirmedOutOfRange and SQ.IsConfirmedOutOfRange(shown)) and "O" or "")
                .. ((SQ.IsUnusableNonResource and SQ.IsUnusableNonResource(shown)) and "U" or "")
                .. ((BAPI.IsSpellProcced and BAPI.IsSpellProcced(lead)) and "P" or "")
                .. (PickGated(RI, SQ, shown, cur, resName, max) and "G" or "")
            -- Where the pick actually sits: @N in the visible queue, @0 when it is not there at all.
            local at = 0
            for i = 2, #queue do
                if queue[i] == pick or queue[i] == shown then at = i break end
            end
            why = " why=" .. (why ~= "" and why or "-") .. "@" .. at
        end
    end
    -- Slot 2 is where the default mode shows what the ADDON adds to the game's pick.
    local second = type(queue) == "table" and queue[2] or nil
    -- The context the queue actually ranked with; "*" = carried by the fight window.
    local ctxState = SQ and SQ.DebugContextState and SQ.DebugContextState()
    if type(second) ~= "number" or issecretvalue(second) then second = nil end
    local payload = string.format("%s pick=%d combat=%s enemies=%s pts=%s/%s pow=%s thp=%s lead=%s%s%s arch=%s second=%s ctx=%s%s sl=%s%s",
        tostring(SDB.GetSpecKey and SDB.GetSpecKey() or "?"),
        pick or 0,
        inCombat and "1" or "0",
        n(BAPI.GetEngagedEnemyCount and BAPI.GetEngagedEnemyCount()),
        n(cur), n(max),
        n(BAPI.GetPowerBand and BAPI.GetPowerBand("player", POWER_BANDS)),
        n(UnitExists("target") and BAPI.GetHealthBand and BAPI.GetHealthBand("target", HEALTH_BANDS) or nil),
        n(lead), (rec and rec.delegated) and "D" or (rec and "" or "?"), why,
        tostring(lead and SDB.GetArch and SDB.GetArch(lead) or "-"), n(second),
        tostring(ctxState and ctxState.arch or "-"), (ctxState and ctxState.stickyApplied) and "*" or "",
        slID and (tostring(slCls) .. ":" .. tostring(slID)) or "-",
        ((SQ.IsSafeLead and lead and SQ.IsSafeLead(lead)) and "!" or "") .. waitWhy)
    if payload == lastPickPayload then return end
    lastPickPayload = payload
    _G.JustACGlobal = _G.JustACGlobal or {}
    local log = _G.JustACGlobal.pickLog or {}
    _G.JustACGlobal.pickLog = log
    log[#log + 1] = string.format("%.2f %s", GetTime(), payload)
    if #log > PICKLOG_MAX then
        local keep, half = {}, math.floor(PICKLOG_MAX / 2)
        for i = #log - half + 1, #log do keep[#keep + 1] = log[i] end
        _G.JustACGlobal.pickLog = keep
    end
end

--- /jac inspect picklog [on|off|clear] - record the game's pick + readable facts, 5/s.
function DebugCommands.PickLog(addon, arg)
    arg = arg and arg:lower() or nil
    if arg == "clear" then
        if _G.JustACGlobal then _G.JustACGlobal.pickLog = nil end
        addon:Print("picklog: |cffffff00cleared|r")
        return
    end
    if arg == "off" or (not arg and pickLogTicker) then
        if pickLogTicker then pickLogTicker:Cancel() end
        pickLogTicker = nil
        local n = (_G.JustACGlobal and _G.JustACGlobal.pickLog and #_G.JustACGlobal.pickLog) or 0
        addon:Print(string.format("picklog: |cffff6600OFF|r - %d samples held. |cff888888/reload to flush them to SavedVariables.|r", n))
        return
    end
    lastPickPayload = nil
    if pickLogTicker then addon:Print("picklog: already ON"); return end
    pickLogTicker = C_Timer.NewTicker(0.2, function()
        local ok, err = pcall(PickLogSample)
        if not ok then
            pickLogTicker:Cancel()
            pickLogTicker = nil
            addon:Print("picklog: stopped after sample error: " .. SafeSecret(err))
        end
    end)
    addon:Print("picklog: |cff00ff00ON|r - fight normally (single target AND packs), then")
    addon:Print("|cffffff00/jac inspect picklog off|r, |cffffff00/reload|r, and run tools/audit_assisted_combat.py --decode")
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

--------------------------------------------------------------------------------
-- /jac inspect simcgates [st|aoe|cleave] - evaluate this spec's SimC gates live.
-- The verification tool for the threshold layer feeding the rotation: every entry
-- carrying an EVALUABLE gate is listed with the gate's inputs and the verdict the
-- queue acts on, so a wrong gate is visible instead of quietly reordering things.
-- "-"/nil anywhere means unevaluable, which always fails OPEN (never blocks).
-- Countable resource gates are listed but not evaluated here - they need the live
-- point count the queue passes in.
--------------------------------------------------------------------------------
function DebugCommands.SimcGateProbe(addon, arg)
    local RI   = LibStub("JustAC-RotationImport", true)
    local SQ   = LibStub("JustAC-SpellQueue", true)
    local BAPI = LibStub("JustAC-BlizzardAPI", true)
    if not (RI and RI.GetRotationGated and SQ and SQ._GateVerdict and SQ._SimcGateBlocks and BAPI) then
        addon:Print("simcgates: modules unavailable")
        return
    end
    local ctx = (arg == "aoe" or arg == "cleave") and arg or "st"
    local blocks = SQ._SimcGateBlocks

    addon:Print(string.format("|cff00ff00=== simc gates (%s) ===|r thresholdGate=%s target=%s",
        ctx, tostring(BAPI.IsThresholdGateAvailable and BAPI.IsThresholdGateAvailable()),
        UnitExists("target") and (UnitName("target") or "?") or "none"))

    -- Real inputs, so the verdict shown is the one the queue actually computes.
    local resCount, resMax, resName
    if BAPI.GetClassResourcePoints then
        resCount, resMax, resName = BAPI.GetClassResourcePoints()
    end
    addon:Print(string.format("  countable resource: %s cur=%s max=%s",
        tostring(resName), tostring(resCount), tostring(resMax)))
    addon:Print("  Imported conditions only: player hold overrides, finisher caps and final ordering are not applied.")

    local queueContext = SQ.DebugContextState and SQ.DebugContextState()
    if queueContext and queueContext.pullOpenerID then
        addon:Print("  OOC pull override: Lightning Bolt preferred; below are the imported combat gates, not its waived Maelstrom pull gate")
    end
    local list = RI.GetRotationGated(ctx) or {}
    local shown, blocked = 0, 0
    local gateCtx = {strict=false, resCount=resCount, resMax=resMax, resName=resName}
    for i = 1, #list do
        local e = list[i]
        local gates = e and e.gates
        if gates then
            -- Each gate describes itself, so a GROUP can describe its members the same
            -- way. Without this a nested condition printed nothing and its whole entry
            -- silently vanished from the probe.
            local DescribeGate
            DescribeGate = function(g)
                if g.t == "any" or g.t == "all" then
                    local sub = {}
                    for k = 1, #(g.g or {}) do
                        sub[#sub + 1] = DescribeGate(g.g[k])
                    end
                    if #sub == 0 then return tostring(g.t) .. "(empty)" end
                    return "(" .. table.concat(sub, g.t == "any" and " or " or " and ") .. ")"
                end
                if g.t == "targets" then
                    return string.format("engaged enemies%s%s [observed=%s]", tostring(g.op),
                        tostring(g.n), tostring(BAPI.GetEngagedEnemyCount and BAPI.GetEngagedEnemyCount()))
                elseif g.t == "totem" then
                    local occupied
                    if BAPI.IsTotemSlotOccupied then occupied = BAPI.IsTotemSlotOccupied(g.slot) end
                    return string.format("totem slot %s wants %s [occupied=%s]",
                        tostring(g.slot), g.neg and "empty" or "occupied", tostring(occupied))
                elseif g.t == "unconfirmed" then
                    return "fight-length mana pacing: unconfirmed (branch does not authorize a cast)"
                elseif g.t == "power" then
                    -- Ask the RUNTIME for the threshold rather than recomputing it -
                    -- a probe that mirrors the logic drifts from it.
                    -- Guard THEN call: `local a, b = X and X.fn()` truncates to a single
                    -- value, so `pt` came back nil and UnitPowerMax below was asked for the
                    -- player's PRIMARY power rather than this gate's resource.
                    local pctVal, pt
                    if SQ.PowerGateThreshold then pctVal, pt = SQ.PowerGateThreshold(g) end
                    local below = pctVal and BAPI.IsUnitPowerBelow
                        and BAPI.IsUnitPowerBelow("player", pctVal, pt)
                    return string.format("%s%s%s%d [max=%s -> %s%%] below=%s",
                        g.res, g.deficit and ".deficit" or "", g.op, g.n,
                        tostring(pt and UnitPowerMax("player", pt)),
                        pctVal and string.format("%.1f", pctVal) or "-", tostring(below))
                elseif g.t == "execute" and g.pct then
                    return string.format("target.hp%s%d below=%s", g.op, g.pct,
                        tostring(BAPI.IsUnitHealthBelow and BAPI.IsUnitHealthBelow("target", g.pct)))
                elseif g.t == "health" and g.pct then
                    return string.format("my.hp%s%d below=%s", g.op, g.pct,
                        tostring(BAPI.IsUnitHealthBelow and BAPI.IsUnitHealthBelow("player", g.pct)))
                elseif g.t == "cd" and g.id then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(g.id)
                    return string.format("cd(%s) wants %s [running=%s]",
                        (info and info.name) or tostring(g.id),
                        g.neg and "running" or "ready",
                        tostring(BAPI.IsSpellOnCooldown and BAPI.IsSpellOnCooldown(g.id)))
                elseif g.t == "stealth" then
                    return string.format("%sstealthed [now %s]", g.neg and "!" or "",
                        tostring(IsStealthed and IsStealthed() or false))
                elseif g.t == "stack" and g.id and g.n then
                    -- Ask the runtime's own verdict, then show the raw ">= n" read
                    -- beside it: the two disagree exactly when the operator logic is
                    -- wrong, which is the part worth being able to see.
                    local unit = g.tgt and "target" or "player"
                    local holds, atN
                    if SQ._StackHolds then holds = SQ._StackHolds(unit, g) end
                    if BAPI.GetAuraStackAtLeast then atN = BAPI.GetAuraStackAtLeast(unit, g.id, g.n) end
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(g.id)
                    return string.format("%s(%s).stack%s%d [>=%d is %s] holds=%s",
                        (info and info.name) or tostring(g.id), unit,
                        g.op, g.n, g.n, tostring(atN), tostring(holds))
                elseif g.t == "resource" then
                    local value = resCount
                    if g.deficit and type(resMax) == "number" and type(resCount) == "number" then
                        value = resMax - resCount
                    elseif g.deficit then
                        value = nil
                    end
                    return string.format("%s%s%s%d [is=%s]", g.res,
                        g.deficit and ".deficit" or "", g.op, g.n,
                        (g.res == resName) and tostring(value) or "other resource")
                end
                return (g.neg and "!" or "") .. tostring(g.t)
                    .. (g.id and ("[" .. tostring(g.id) .. "]") or "")
            end
            local parts = {}
            for gi = 1, #gates do
                local g = gates[gi]
                local status, text, verdict = ProbeRead(function() return SQ._GateVerdict(g, gateCtx) end)
                local colour = "|cff888888"
                if status == "plain" and verdict == true then
                    colour = "|cff00ff00"
                elseif status == "plain" and verdict == false then
                    colour = "|cffff6600"
                end
                parts[#parts + 1] = colour .. DescribeGate(g) .. " verdict=" .. status .. ":" .. text .. "|r"
            end
            if #parts == 0 then parts[1] = "no gates" end
            shown = shown + 1
            local isBlocked = blocks(gates, resCount, resName, resMax)
            if isBlocked then blocked = blocked + 1 end
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(e.id)
            addon:Print(string.format("  %s|r %s %s {%s}",
                isBlocked and "|cffff6600BLOCK" or "|cff2ecc71ok   ",
                (info and info.name) or tostring(e.id),
                e.delegated and "|cff888888(delegated)|r" or "",
                table.concat(parts, ", ")))
        end
    end
    addon:Print(string.format("=== %d imported entr%s, %d blocked right now ===",
        shown, shown == 1 and "y" or "ies", blocked))
    if shown == 0 then
        addon:Print("|cff888888No imported entries for this context.|r")
    end
end
