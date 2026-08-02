-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2026 wealdly
-- JustAC: Options/Defensives - Defensive queue settings tab + spell list management
local Defensives = LibStub:NewLibrary("JustAC-OptionsDefensives", 4)
if not Defensives then return end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local SpellQueue = LibStub("JustAC-SpellQueue", true)
local SpellSearch = LibStub("JustAC-OptionsSpellSearch", true)
local L = LibStub("AceLocale-3.0"):GetLocale("JustAssistedCombat")
local W = LibStub("JustAC-OptionsWidgets")

-- Pre-combat buff options -------------------------------------------------------------
-- categories[cat]: false = off, a stat string = preference, nil = auto (optimal/recency).
local PB_STAT_ORDER = { "off", "auto", "haste", "crit", "mastery", "versatility" }

local function pbCategories(addon)
    local pb = addon.db.profile.precombatBuffs
    pb.categories = pb.categories or {}
    return pb.categories
end

-- Apply an options change immediately: drop the buff cache, then rebuild the queues.
local function pbApply(addon)
    local PE = LibStub("JustAC-PrecombatEngine", true)
    if PE and PE.ClearCache then PE.ClearCache() end
    addon:ForceUpdateAll()
end

local function pbDisabled(addon)
    return addon.db.profile.precombatBuffs.enabled == false
end

-- Label an option with the specific bag item it resolves to - "Haste  Flask of Tempered
-- Swiftness" (green, matching the OOC buff glow). Answers "which flask does this pick?".
-- Falls back to the plain label when nothing owned fits that option.
local function pbOptLabel(cat, statPref, base)
    local SDB = LibStub("JustAC-SpellDB", true)
    local entry = SDB and SDB.GetBestOwnedBuff and SDB.GetBestOwnedBuff(cat, statPref)
    local nm = entry and entry.id and (GetItemInfo(entry.id))
    return nm and (base .. "  |cff2ecc71" .. nm .. "|r") or base
end

-- Stat-preference dropdown (flask/food): Off / Auto / a secondary stat. Each option shows
-- the specific bag item it resolves to, so the list itself answers "which flask for haste?".
-- withSpeed adds a Speed option - the Speed secondary stat (a rating that always stacks);
-- both food and flask can grant it. Kept opt-in (never surfaces under Auto), since Speed is
-- niche and most specs wouldn't want it auto-picked over their combat stat.
local function pbStatSelect(addon, cat, name, order, withSpeed)
    local sorting = withSpeed
        and { "off", "auto", "haste", "crit", "mastery", "versatility", "speed" }
        or PB_STAT_ORDER
    return {
        type = "select", name = name, order = order, sorting = sorting,
        values = function()
            local vals = {
                off = L["Off"],
                auto = pbOptLabel(cat, nil, L["Auto"]),
                haste = pbOptLabel(cat, "haste", L["Haste"]),
                crit = pbOptLabel(cat, "crit", L["Crit"]),
                mastery = pbOptLabel(cat, "mastery", L["Mastery"]),
                versatility = pbOptLabel(cat, "versatility", L["Versatility"]),
            }
            if withSpeed then vals.speed = pbOptLabel(cat, "speed", L["Speed"]) end
            return vals
        end,
        disabled = function() return pbDisabled(addon) end,
        get = function()
            local v = pbCategories(addon)[cat]
            if v == false then return "off" elseif type(v) == "string" then return v end
            return "auto"
        end,
        set = function(_, val)
            local c = pbCategories(addon)
            if val == "off" then c[cat] = false
            elseif val == "auto" then c[cat] = nil
            else c[cat] = val end
            pbApply(addon)
        end,
    }
end

-- Off / Auto dropdown for categories with no stat choice (augment rune, weapon enchant, xp,
-- speed). The Auto option is labelled with the winning bag item. `defaultOff` flips the
-- default so xp/speed stay off until chosen (stored as an explicit truthy value, since a nil
-- would revert to the AceDB `false` default).
local function pbOnOffSelect(addon, cat, name, order, defaultOff, desc)
    return {
        type = "select", name = name, order = order, desc = desc, sorting = { "off", "auto" },
        values = function()
            return { off = L["Off"], auto = pbOptLabel(cat, nil, L["Auto"]) }
        end,
        disabled = function() return pbDisabled(addon) end,
        get = function()
            local v = pbCategories(addon)[cat]
            if defaultOff then return v == true and "auto" or "off" end
            return v == false and "off" or "auto"
        end,
        set = function(_, val)
            if defaultOff then
                pbCategories(addon)[cat] = (val == "auto") or false
            else
                pbCategories(addon)[cat] = (val == "off") and false or nil
            end
            pbApply(addon)
        end,
    }
end

--- Returns true when the current spec has a maintenance mitigation buff (tank specs with a
--- curated entry). Brewmaster is a tank but has no entry, so this is spec-level, not role-level.
local function HasMaintenanceDefensive()
    local SDB = LibStub("JustAC-SpellDB", true)
    return (SDB and SDB.GetMaintenanceDefensive and SDB.GetMaintenanceDefensive() ~= nil) or false
end

--- Returns true when the player's class has pet rez/summon defaults.
local function IsPetRezClass()
    local _, pc = UnitClass("player")
    local SDB = LibStub("JustAC-SpellDB", true)
    return SDB and SDB.CLASS_PET_REZ_DEFAULTS and SDB.CLASS_PET_REZ_DEFAULTS[pc]
end

--- Returns true when the player's class has pet heal defaults.
local function IsPetHealClass()
    local _, pc = UnitClass("player")
    local SDB = LibStub("JustAC-SpellDB", true)
    return SDB and SDB.CLASS_PETHEAL_DEFAULTS and SDB.CLASS_PETHEAL_DEFAULTS[pc]
end

function Defensives.CreateTabArgs(addon)
    return {
        type = "group",
        name = L["Defensives"],
        order = 5,
        args = {
            -- Defensive queue CONTENT behavior (cross-surface: standard queue + overlay).
            -- Moved out of the General tab. Frame/display settings (enable, health bars,
            -- display mode, positioning) live in Standard Queue -> Defensive Display.
            queueContentGroup = {
                type = "group",
                inline = true,
                name = L["Defensive Queue"],
                order = 5,
                args = {
                    showDefensiveProcs = W.toggle(addon, "defensives.showProcs", {
                        name = L["Insert Procced Defensives"],
                        desc = W.spellDesc("Insert Procced Defensives desc", 34428),  -- Victory Rush
                        order = 1, width = "full", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        disabled = function(a)
                            local dm = a.db.profile.displayMode or "queue"
                            if dm == "disabled" then return true end
                            local standardEnabled = a.db.profile.defensives.enabled
                            local npo = a.db.profile.nameplateOverlay
                            local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                            return not standardEnabled and not overlayEnabled
                        end,
                    }),
                    -- CONTENT behaviour, not display: it reorders which defensives the queue
                    -- recommends. Lived under Standard Queue -> Defensive Display, which was
                    -- wrong on the tab's own stated split, and worse than untidy - it is read in
                    -- GetDefensiveSpellQueue, the SHARED builder, so it governs the nameplate
                    -- overlay too. An overlay-only player had to open the Standard Queue tab to
                    -- change how their overlay behaves.
                    hideEmergencyUntilLow = W.toggle(addon, "defensives.hideEmergencyUntilLow", {
                        name = L["Hide Emergency Until Low"], desc = L["Hide Emergency Until Low desc"],
                        order = 2, width = "full", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        -- Same cross-surface gate as the toggle above (the old one only knew
                        -- about the standard queue), plus: meaningless in "When Health Low"
                        -- mode, where everything is already gated on health.
                        disabled = function(a)
                            local dm = a.db.profile.displayMode or "queue"
                            if dm == "disabled" then return true end
                            local npo = a.db.profile.nameplateOverlay
                            local overlayEnabled = (dm == "overlay" or dm == "both") and npo and npo.showDefensives
                            if not a.db.profile.defensives.enabled and not overlayEnabled then return true end
                            return (a.db.profile.defensives.displayMode or "always") == "healthBased"
                        end,
                    }),
                },
            },
            precombatGroup = {
                type = "group",
                inline = true,
                name = L["Pre-combat Buffs"],
                order = 10,
                -- Pre-combat suggestions render on the defensive bar; with defensives
                -- disabled they have no surface, so the whole section grays out.
                disabled = function() return not addon.db.profile.defensives.enabled end,
                args = {
                    pbEnabled = {
                        type = "toggle",
                        name = L["Enable Pre-combat Buffs"],
                        desc = L["Pre-combat Buffs desc"],
                        order = 1,
                        width = "full",
                        get = function() return addon.db.profile.precombatBuffs.enabled ~= false end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.enabled = v
                            pbApply(addon)
                        end,
                    },
                    topoffHeal = {
                        type = "toggle",
                        name = L["Health Top-off"],
                        desc = L["Health Top-off desc"],
                        order = 2,
                        width = "full",
                        disabled = function() return pbDisabled(addon) end,
                        get = function() return addon.db.profile.precombatBuffs.topoffHeal == true end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.topoffHeal = v
                            pbApply(addon)
                        end,
                    },
                    -- Only meaningful since the cue moved onto a health curve: before that the
                    -- threshold was honoured solely where an exact health read works (rested
                    -- areas), and degraded to "below full" everywhere else - so a slider would
                    -- have been a lie in the open world. Stepped in 5s for the same reason as
                    -- the pet slider: each distinct value builds and caches its own curve.
                    topoffThreshold = {
                        type = "range",
                        name = L["Health Top-off Threshold"],
                        desc = L["Health Top-off Threshold desc"],
                        order = 2.1, width = "full",
                        min = 50, max = 95, step = 5,
                        disabled = function()
                            return pbDisabled(addon)
                                or addon.db.profile.precombatBuffs.topoffHeal ~= true
                        end,
                        get = function() return addon.db.profile.precombatBuffs.topoffThreshold or 90 end,
                        set = function(_, v)
                            addon.db.profile.precombatBuffs.topoffThreshold = v
                            pbApply(addon)
                        end,
                    },
                    flask = pbStatSelect(addon, "flask", L["Flask"], 10, true),
                    food = pbStatSelect(addon, "food", L["Food"], 11, true),
                    augmentRune = pbOnOffSelect(addon, "augmentRune", L["Augment Rune"], 12, false),
                    weaponEnchant = pbOnOffSelect(addon, "weaponEnchant", L["Weapon Enchant"], 13, false),
                    xp = pbOnOffSelect(addon, "xp", L["XP"], 15, true, L["XP desc"]),
                },
            },
            spellListGroup = {
                type = "group",
                inline = true,
                name = SpellSearch.SpecHeader("Defensive Spells"),
                order = 20,
                args = {
                    selfHealHeader = {
                        type = "header",
                        name = L["Defensive Priority List"],
                        order = 20,
                    },
                    selfHealInfo = {
                        type = "description",
                        name = L["Defensive Priority desc"],
                        order = 21,
                        fontSize = "small"
                    },
                    restoreSelfHealDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults"],
                        desc = L["Restore Defensive Defaults desc"],
                        order = 42,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("defensive")
                            Defensives.UpdateDefensivesOptions(addon)
                        end,
                    },
                    -- SUSTAIN (60-79) - defensive "position 0". NOT tank-only: the tank mitigation
                    -- buff is one member, crowd-control escape (below) is another and works on any
                    -- spec, and the pet-heal cue is a third. Only the mitigation-buff TOGGLE is
                    -- tank-gated; the section is not.
                    -- Shown but greyed off-spec, unlike the class-gated pet sections below which
                    -- hide: spec is switchable, so a Feral still needs to discover it exists.
                    maintenanceHeader = {
                        type = "header",
                        name = L["Sustain"],
                        order = 60,
                    },
                    maintenanceInfo = {
                        type = "description",
                        -- The section is universal - crowd-control escape claims this slot on
                        -- ANY spec - so the tank-only caveat belongs to the mitigation-buff
                        -- toggle below, not to the header. Attaching it here told every
                        -- non-tank the whole slot was unavailable to them, which was wrong.
                        name = function()
                            if HasMaintenanceDefensive() then return L["Sustain desc"] end
                            return L["Sustain desc"] .. "\n\n"
                                .. "|cffff9900The mitigation-buff part is tank-only; your escape "
                                .. "from crowd control still uses this slot.|r"
                        end,
                        order = 61,
                        fontSize = "small",
                    },
                    -- SUSTAIN MEMBER 3: pet heal (69). Hidden rather than greyed for non-pet
                    -- classes - class is not switchable, so there is nothing to discover, unlike
                    -- the mitigation buff above which a Feral might switch into.
                    -- No AceDB default: same convention as showMaintenanceSlot/showCCBreak -
                    -- `default = true` here plus `~= false` at the read site.
                    showPetHealCue = W.toggle(addon, "showPetHealCue", {
                        name = L["Pet Heal Cue"],
                        desc = L["Pet Heal Cue desc"],
                        order = 69, width = "double", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        hidden = function() return not IsPetHealClass() end,
                    }),
                    -- Stepped in 5s deliberately: the threshold becomes a curve point, and each
                    -- distinct value builds and caches its own curve. A continuous slider would
                    -- mint one per pixel dragged; 5% steps cap it at ~16 for the whole session.
                    petHealThreshold = W.range(addon, "petHealThreshold", {
                        name = L["Pet Heal Threshold"],
                        desc = L["Pet Heal Threshold desc"],
                        order = 69.1, width = "double", min = 10, max = 90, step = 5, default = 50,
                        onSet = function() addon:ForceUpdateAll() end,
                        hidden = function() return not IsPetHealClass() end,
                        disabled = function(a) return a.db.profile.showPetHealCue == false end,
                    }),
                    showMaintenanceSlot = W.toggle(addon, "showMaintenanceSlot", {
                        name = L["Maintenance Slot"],
                        desc = L["Maintenance Slot desc"],
                        order = 62, width = "normal", default = true,
                        onSet = function() addon:ForceUpdateAll() end,
                        -- Mirrors the defensive-queue gate used above: dead when every surface
                        -- is off, or when no defensive display is actually showing, since the
                        -- slot renders inside that cluster.
                        disabled = function(a)
                            if not HasMaintenanceDefensive() then return true end
                            local dm = a.db.profile.displayMode or "queue"
                            if dm == "disabled" then return true end
                            local standardEnabled = a.db.profile.defensives.enabled
                            local npo = a.db.profile.nameplateOverlay
                            local overlayEnabled = (dm == "overlay" or dm == "both")
                                and npo and npo.showDefensives
                            return not standardEnabled and not overlayEnabled
                        end,
                    }),
                    -- CROWD-CONTROL ESCAPE (70-71) - a MEMBER of Sustain above, not a rival
                    -- section. It used to be kept separate because that section was branded as
                    -- tank maintenance and grouping the two would have implied CC escape needed a
                    -- tank; naming the slot Sustain removed that reason. It keeps its own header
                    -- purely as a visual divider - the toggles below are its own, and it works on
                    -- any spec whether or not the mitigation-buff toggle is on.
                    ccBreakHeader = {
                        type = "header",
                        name = L["CC Escape"],
                        order = 70,
                    },
                    ccBreakInfo = {
                        type = "description",
                        name = L["CC Escape info"],
                        order = 70.5,
                        fontSize = "small",
                    },
                    showCCBreak = W.toggle(addon, "showCCBreak", {
                        name = L["CC Break"],
                        desc = L["CC Break desc"],
                        order = 71, width = "normal", default = false,
                        onSet = function(a) a:ForceUpdateAll() end,
                    }),
                    -- DRUID ONLY. Roots, snares and slows are broken by shapeshifting, but that
                    -- break is engine behaviour attached to the shift action, not a spell effect,
                    -- so no generated table can find it. The player designates their /cancelform
                    -- macro; the slot then surfaces ITS keybind. A select (not auto-detect) is the
                    -- point: the player owns which macro, so a macro that also casts something is
                    -- their informed choice - and the description shows the body so it is visible.
                    ccBreakMacro = {
                        type = "select",
                        name = L["CC Break Macro"],
                        desc = L["CC Break Macro desc"],
                        order = 72,
                        width = "double",
                        hidden = function()
                            return select(2, UnitClass("player")) ~= "DRUID"
                                or not addon.db.profile.showCCBreak
                        end,
                        values = function()
                            local out = { [""] = NONE or "None" }
                            if not GetMacroInfo then return out end
                            -- Global macros then per-character; names are what the runtime matches
                            -- against action slots, so store names, not shifting indices.
                            for idx = 1, 138 do
                                local name, _, body = GetMacroInfo(idx)
                                if name and body and body:lower():find("/cancelform", 1, true) then
                                    out[name] = name
                                end
                            end
                            return out
                        end,
                        get = function() return addon.db.profile.ccBreakMacro or "" end,
                        set = function(_, val)
                            addon.db.profile.ccBreakMacro = (val ~= "" and val) or nil
                            addon:ForceUpdateAll()
                        end,
                    },
                    ccBreakMacroBody = {
                        type = "description",
                        order = 72.5,
                        fontSize = "small",
                        hidden = function()
                            return select(2, UnitClass("player")) ~= "DRUID"
                                or not addon.db.profile.showCCBreak
                                or not addon.db.profile.ccBreakMacro
                        end,
                        name = function()
                            local m = addon.db.profile.ccBreakMacro
                            local body
                            if m and GetMacroInfo then
                                body = select(3, GetMacroInfo(m))
                            end
                            if not body then return L["CC Break Macro missing"] end
                            return "|cff888888" .. body:gsub("\n", " | ") .. "|r"
                        end,
                    },
                    -- Dynamic defensiveSpells entries added by UpdateDefensivesOptions
                    -- PET REZ/SUMMON PRIORITY LIST (80+, pet classes only)
                    petRezHeader = {
                        type = "header",
                        name = L["Pet Rez/Summon Priority List"],
                        order = 80,
                        hidden = function() return not IsPetRezClass() end,
                    },
                    petRezInfo = {
                        type = "description",
                        name = L["Pet Rez/Summon Priority desc"],
                        order = 81,
                        fontSize = "small",
                        hidden = function() return not IsPetRezClass() end,
                    },
                    restorePetRezDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults name"],
                        desc = L["Restore Pet Rez Defaults desc"],
                        order = 102,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("petrez")
                            Defensives.UpdateDefensivesOptions(addon)
                        end,
                        hidden = function() return not IsPetRezClass() end,
                    },
                    -- Dynamic petRezSpells entries added by UpdateDefensivesOptions
                    -- PET HEAL PRIORITY LIST (110+, pet classes only)
                    petHealHeader = {
                        type = "header",
                        name = L["Pet Heal Priority List"],
                        order = 110,
                        hidden = function() return not IsPetHealClass() end,
                    },
                    petHealInfo = {
                        type = "description",
                        name = L["Pet Heal Priority desc"],
                        order = 111,
                        fontSize = "small",
                        hidden = function() return not IsPetHealClass() end,
                    },
                    restorePetHealDefaults = {
                        type = "execute",
                        name = L["Restore Class Defaults name"],
                        desc = L["Restore Pet Heal Defaults desc"],
                        order = 132,
                        width = "normal",
                        func = function()
                            addon:RestoreDefensiveDefaults("petheal")
                            Defensives.UpdateDefensivesOptions(addon)
                        end,
                        hidden = function() return not IsPetHealClass() end,
                    },
                    -- Dynamic petHealSpells entries added by UpdateDefensivesOptions
                },
            },
        },
    }
end

function Defensives.UpdateDefensivesOptions(addon)
    local optionsTable = addon and addon.optionsTable
    if not optionsTable or not SpellQueue then return end

    local spellListGroup = optionsTable.args.defensives.args.spellListGroup
    if not spellListGroup then return end
    local spellListArgs = spellListGroup.args

    -- Clear dynamic entries, preserve static ones. ANY statically-declared control in
    -- spellListGroup must be listed here or it is silently deleted on the next refresh -
    -- the entry still exists in CreateTabArgs, so it appears once and then vanishes, which
    -- is a confusing way to lose an option.
    local staticKeys = {
        selfHealHeader = true, selfHealInfo = true, restoreSelfHealDefaults = true,
        maintenanceHeader = true, maintenanceInfo = true, showMaintenanceSlot = true,
        ccBreakHeader = true, ccBreakInfo = true, showCCBreak = true,
        ccBreakMacro = true, ccBreakMacroBody = true,
        -- (Cooldown Manager controls moved to General -> Settings; they are a game-wide client
        -- setting, not a defensive one, and this tab no longer declares them.)
        showPetHealCue = true, petHealThreshold = true,
        petRezHeader = true, petRezInfo = true, restorePetRezDefaults = true,
        petHealHeader = true, petHealInfo = true, restorePetHealDefaults = true,
    }
    SpellSearch.ClearDynamicArgs(spellListArgs, staticKeys)

    local defensives = addon.db.profile.defensives
    if not defensives then return end

    local DefensiveEngine = LibStub("JustAC-DefensiveEngine", true)
    local specKey, playerClass
    if DefensiveEngine and DefensiveEngine.GetDefensiveSpecKey then
        specKey, playerClass = DefensiveEngine.GetDefensiveSpecKey()
    else
        local _
        _, playerClass = UnitClass("player")
    end

    -- Resolve spell lists using spec→class fallback
    local defensiveSpells, petRezSpells, petHealSpells
    local targetKey = specKey  -- prefer spec key
    if targetKey and defensives.classSpells and defensives.classSpells[targetKey] then
        defensiveSpells = defensives.classSpells[targetKey].defensiveSpells
        petRezSpells = defensives.classSpells[targetKey].petRezSpells
        petHealSpells = defensives.classSpells[targetKey].petHealSpells
    elseif playerClass and defensives.classSpells and defensives.classSpells[playerClass] then
        -- Class-level fallback (legacy data not yet migrated to per-spec)
        targetKey = playerClass
        defensiveSpells = defensives.classSpells[playerClass].defensiveSpells
        petRezSpells = defensives.classSpells[playerClass].petRezSpells
        petHealSpells = defensives.classSpells[playerClass].petHealSpells
    end

    -- Determine if this is a pet class (has rez or heal defaults)
    local SpellDB = LibStub("JustAC-SpellDB", true)
    local isPetClass = SpellDB and SpellDB.ClassHasPetDefaults(playerClass)

    local updateFunc = function()
        Defensives.UpdateDefensivesOptions(addon)
        -- Re-register all defensive spells for local CD tracking (new additions included)
        local DefensiveEngine = LibStub("JustAC-DefensiveEngine", true)
        if DefensiveEngine and DefensiveEngine.RegisterDefensivesForTracking then
            DefensiveEngine.RegisterDefensivesForTracking(addon)
        end
        addon:ForceUpdateAll()
    end

    -- Unified defensive spells (order 22.0-39.9, allowing 180 entries)
    SpellSearch.CreateSpellListEntries(addon, spellListArgs, defensiveSpells, "defensive", 22, updateFunc)
    SpellSearch.CreateAddSpellButton(addon, spellListArgs, defensiveSpells, "defensive", 40, "Defensives", updateFunc, false)

    -- Pet Rez/Summon spells (order 82.0-99.9, pet classes only)
    if isPetClass and petRezSpells then
        SpellSearch.CreateSpellListEntries(addon, spellListArgs, petRezSpells, "petrez", 82, updateFunc)
        SpellSearch.CreateAddSpellButton(addon, spellListArgs, petRezSpells, "petrez", 100, "Pet Rez/Summon", updateFunc, true)
    end

    -- Pet Heal spells (order 112.0-129.9, pet classes only)
    if isPetClass and petHealSpells then
        SpellSearch.CreateSpellListEntries(addon, spellListArgs, petHealSpells, "petheal", 112, updateFunc)
        SpellSearch.CreateAddSpellButton(addon, spellListArgs, petHealSpells, "petheal", 130, "Pet Heals", updateFunc, false)
    end

    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("JustAssistedCombat")
    end
end
