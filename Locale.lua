-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Localization Module

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "enUS", true)
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "General"
L["System"] = "System"
L["Offensive"] = "Offensives"
L["Offensive Info"] = "DPS rotation queue from Blizzard's Assisted Combat.\n|cff00ff00• Procs|r: Glowing abilities inserted automatically\n|cff888888• Blacklist|r: Hide unwanted spells from queue"
L["Defensives"] = "Defensives"
L["Blacklist"] = "Blacklist"
L["Hotkey Overrides"] = "Hotkeys"

-- General Options
L["Max Icons"] = "Max Icons"
L["Icon Size"] = "Icon Size"
L["Spacing"] = "Spacing"
L["Primary Spell Scale"] = "Primary Spell Scale"
L["UI Scale"] = "UI Scale"
L["Queue Orientation"] = "Queue Orientation"
L["Gamepad Icon Style"] = "Gamepad Icon Style"
L["Gamepad Icon Style desc"] = "Choose the button icon style for gamepad/controller keybinds."
L["Generic"] = "Generic (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Cross/Circle/Square/Triangle)"
L["Lock Panel"] = "Lock Panel"
L["Show Offensive Hotkeys"] = "Show Hotkeys"
L["Show Offensive Hotkeys desc"] = "Display keybind text on offensive queue icons. Disabling skips hotkey detection for better performance."
L["Show Defensive Hotkeys"] = "Show Hotkeys"
L["Show Defensive Hotkeys desc"] = "Display keybind text on defensive icons. Disabling skips hotkey detection for better performance."
L["Insert Procced Defensives"] = "Insert Procced Defensives"
L["Insert Procced Defensives desc"] = "Show procced defensive abilities (Victory Rush, free heals) at any health level."
L["Debug Mode"] = "Debug Mode"
L["Frame Opacity"] = "Frame Opacity"
L["Queue Icon Fade"] = "Queue Icon Fade"
L["Hide Out of Combat"] = "Hide Out of Combat"
L["Insert Procced Abilities"] = "Insert Procced Abilities"
L["Include All Available Abilities"] = "Include Macro-Hidden Abilities"
L["Stabilization Window"] = "Stabilization Window"
L["Highlight Primary Spell"] = "Highlight Primary Spell"
L["Show Tooltips"] = "Show Tooltips"
L["Tooltips in Combat"] = "Tooltips in Combat"

-- Blacklist
L["Hide from Queue"] = "Hide from Queue"
L["Remove"] = "Remove"
L["No spells currently blacklisted"] = "No spells currently blacklisted. Shift+Right-click a spell in the queue to add it."
L["Blacklisted Spells"] = "Blacklisted Spells"
L["Blacklist description"] = "Shift+Right-click a spell icon in the queue to add it to this list. You can then customize where it should be hidden."
L["Hide spell desc"] = "Hide this spell from queue positions 2+. Position 1 (Blizzard's primary suggestion) is never filtered."
L["Add Spell to Blacklist"] = "Add Spell to Blacklist"
L["Spell ID"] = "Spell ID"
L["Enter the spell ID to blacklist"] = "Enter the spell ID to blacklist (e.g., 48707)"
L["Add"] = "Add"

-- Hotkey Overrides
L["Custom Hotkey"] = "Custom Hotkey"
L["No custom hotkeys set"] = "No custom hotkeys set. Right-click a spell in the queue to set a custom hotkey display."
L["Custom Hotkey Displays"] = "Custom Hotkey Displays"
L["Hotkey override description"] = "Set custom hotkey text for spells when automatic detection fails or for personal preference.\n\n|cff00ff00Right-click|r a spell icon in the queue to set a custom hotkey.\n|cffff6666Shift+Right-click|r to blacklist a spell."
L["Add Hotkey Override"] = "Add Hotkey Override"
L["Enter the spell ID to add a hotkey override for"] = "Enter the spell ID for the hotkey override (e.g., 48707)"
L["Hotkey"] = "Hotkey"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "Enter the hotkey text to display (e.g., 1, F1, S-2, Ctrl+Q)"
L["Custom Hotkeys"] = "Custom Hotkeys"

-- Defensives
L["Enable Defensive Suggestions"] = "Enable Defensive Suggestions"
L["Defensive Icon"] = "Defensive Icon"
L["Only In Combat"] = "Only In Combat"
L["Defensive Self-Heals"] = "Defensive Self-Heals"
L["Defensive Cooldowns"] = "Defensive Cooldowns"
L["Defensive description"] = "Shows defensive spell suggestions based on your health and display mode settings.\n|cff00ff00• Procced abilities|r: Victory Rush, free heals shown at ANY health\n|cff00ff00• Self-Heals|r: Quick heals shown below Self-Heal Threshold\n|cffff6666• Major Cooldowns|r: Emergency defensives below Cooldown Threshold"
L["Add to %s"] = "Add to %s"

-- Orientation values
L["Horizontal"] = "Horizontal"
L["Vertical"] = "Vertical"
L["Up"] = "Up"
L["Dn"] = "Dn"

-- Descriptions
L["General description"] = "Configure the appearance and behavior of the spell queue display."
L["Icon Layout"] = "Icon Layout"
L["Visibility"] = "Visibility"
L["Queue Content"] = "Queue Content"
L["Appearance"] = "Appearance"
L["Display Behavior"] = "Display Behavior"
L["Display"] = "Display"
L["Visual Effects"] = "Visual Effects"
L["Threshold Settings"] = "Threshold Settings"

-- Tooltip mode dropdown
L["Tooltips"] = "Tooltips"
L["Tooltips desc"] = "When to show spell tooltips on hover"
L["Never"] = "Never"
L["Out of Combat Only"] = "Out of Combat Only"
L["Always"] = "Always"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Display Mode"
L["Defensive Display Mode desc"] = "When Health Low: Show only when health drops below thresholds\nIn Combat Only: Always show while in combat\nAlways: Show at all times"
L["When Health Low"] = "When Health Low"
L["In Combat Only"] = "In Combat Only"

-- Detailed descriptions
L["Max Icons desc"] = "Maximum spell icons to display (1 = primary, 2+ = queue)"
L["Icon Size desc"] = "Base size of spell icons in pixels"
L["Spacing desc"] = "Gap between icons in pixels"
L["UI Scale desc"] = "Scale multiplier for the entire frame"
L["Primary Spell Scale desc"] = "Scale multiplier for the primary spell icon"
L["Queue Orientation desc"] = "Direction the queue grows from the primary spell"
L["Highlight Primary Spell desc"] = "Show animated glow on the primary spell"
L["Show Tooltips desc"] = "Display spell tooltips on hover"
L["Single-Button Assistant Warning"] = "Warning: Place the Single-Button Assistant on any action bar for JustAC to work properly."
L["Tooltips in Combat desc"] = "Show tooltips during combat"
L["Frame Opacity desc"] = "Global transparency for the entire frame"
L["Queue Icon Fade desc"] = "Desaturation for queue icons (0 = color, 1 = grayscale)"
L["Hide Out of Combat"] = "Hide Out of Combat"
L["Hide Out of Combat desc"] = "Hide the spell queue when not in combat"
L["Hide for Healer Specs"] = "Hide for Healer Specs"
L["Hide for Healer Specs desc"] = "Hide when in a healer specialization"
L["Hide When Mounted"] = "Hide When Mounted"
L["Hide When Mounted desc"] = "Hide while mounted"
L["Require Hostile Target"] = "Require Hostile Target"
L["Require Hostile Target desc"] = "Only show when targeting a hostile unit (out of combat only)"
L["Hide Item Abilities"] = "Hide Item Abilities"
L["Hide Item Abilities desc"] = "Hide trinket and item abilities from the queue"
L["Insert Procced Abilities desc"] = "Add glowing proc abilities from your spellbook to the queue"
L["Include All Available Abilities desc"] = "Include spells hidden behind macro conditionals like [mod:shift] in primary recommendation."
L["Stabilization Window desc"] = "Seconds to wait before changing primary spell (reduces flickering)"
L["Lock Panel desc"] = "Disable dragging and right-click menus"
L["Debug Mode desc"] = "Show debug info in chat"
L["Enable Defensive Suggestions desc"] = "Show defensive spells when health drops below thresholds."
L["Only In Combat desc"] = "Only show defensive suggestions while in combat"
L["Icon Position desc"] = "Where to place defensive icons relative to the queue"
L["Custom Hotkey desc"] = "Text to display as hotkey (e.g., 'F1', 'Ctrl+Q', 'Mouse4')"
L["Move up desc"] = "Move up in priority"
L["Move down desc"] = "Move down in priority"
L["Add spell desc"] = "Enter a spell ID (e.g., 48707) to add"
L["Add"] = "Add"
L["Restore Class Defaults desc"] = "Reset the self-heal list to default spells for your class"
L["Restore Cooldowns Defaults desc"] = "Reset the cooldown list to default spells for your class"

-- Additional sections
L["Icon Position"] = "Icon Position"
L["Side 1 (Health Bar)"] = "Side 1 (Health Bar)"
L["Side 2"] = "Side 2"
L["Leading Edge"] = "Leading Edge"
L["Self-Heal Priority List"] = "Self-Heal Priority List (checked first)"
L["Self-Heal Priority desc"] = "First usable spell is shown. Reorder to set priority."
L["Restore Class Defaults"] = "Restore Class Defaults"
L["Major Cooldowns Priority List"] = "Major Cooldowns Priority List (emergency)"
L["Major Cooldowns Priority desc"] = "First usable spell is shown. Reorder to set priority."

-- Defensive thresholds
L["Threshold Settings"] = "Health Thresholds"
L["Self-Heal Threshold"] = "Self-Heal Threshold"
L["Self-Heal Threshold desc"] = "Show self-heals below this health %"
L["Major Cooldown Threshold"] = "Major Cooldown Threshold"
L["Major Cooldown Threshold desc"] = "Show major defensives below this health %"
L["Pet Heal Threshold"] = "Pet Heal Threshold"
L["Pet Heal Threshold desc"] = "Show pet heals below this pet health %"
L["Threshold Note"] = "|cff888888In combat, health may be hidden. Uses low-health overlay (~35%) as fallback.|r"

-- Defensive display options
L["Show Health Bar"] = "Show Health Bar"
L["Show Health Bar desc"] = "Show a compact health bar next to the queue"
L["Defensive Icon Scale"] = "Defensive Icon Scale"
L["Defensive Icon Scale desc"] = "Scale multiplier for defensive icons"
L["Defensive Max Icons"] = "Maximum Icons"
L["Defensive Max Icons desc"] = "Defensive spells to show at once (1-3)"
L["Profiles"] = "Profiles"
L["Profiles desc"] = "Character and spec profile management"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Spec-Based Switching"
L["Auto-switch profile by spec"] = "Auto-switch profile by spec"
L["(No change)"] = "(No change)"
L["(Disabled)"] = "(Disabled)"
L["About"] = "About"
L["About JustAssistedCombat"] = "About JustAssistedCombat"
L["Developer"] = "Developer"

-- Orientation values (full names)
L["Left to Right"] = "Left to Right"
L["Right to Left"] = "Right to Left"
L["Bottom to Top"] = "Bottom to Top"
L["Top to Bottom"] = "Top to Bottom"

-- Slash commands help
L["Slash Commands"] = "|cffffff00Slash Commands:|r\n|cff88ff88/jac|r - Open options\n|cff88ff88/jac toggle|r - Pause/resume\n|cff88ff88/jac debug|r - Toggle debug mode\n|cff88ff88/jac test|r - Test Blizzard API\n|cff88ff88/jac formcheck|r - Check form detection\n|cff88ff88/jac find <spell>|r - Locate spell\n|cff88ff88/jac reset|r - Reset position\n\nType |cff88ff88/jac help|r for full command list"

-- About text (function will concatenate with version)
L["About Text"] = "Enhances WoW's Assisted Combat system with advanced features for better gameplay experience.\n\n|cffffff00Key Features:|r\n• Smart hotkey detection with custom override support\n• Advanced macro parsing with conditional modifiers\n• Intelligent spell filtering and blacklist management\n• Enhanced visual feedback and tooltips\n• Seamless integration with Blizzard's native highlights\n• Zero performance impact on global cooldowns\n\n|cffffff00How It Works:|r\nJustAC automatically detects your action bar setup and displays the recommended rotation with proper hotkeys. When automatic detection fails, you can set custom hotkey displays via right-click.\n\n|cffffff00Optional Enhancements:|r\n|cffffffff/console assistedMode 1|r - Enables Blizzard's assisted combat system\n|cffffffff/console assistedCombatHighlight 1|r - Adds native button highlighting\n\nThese console commands enhance the experience but are not required for JustAC to function."

-- Additional UI strings
L["Remove"] = "Remove"
L["Hotkey Overrides"] = "Hotkeys"
L["Hotkey Overrides Info"] = "Set custom hotkey text when auto-detection fails.\n\n|cff00ff00Right-click|r a spell to set a hotkey."
L["Custom Hotkey Displays"] = "Custom Hotkey Displays"
L["Blacklist"] = "Blacklist"
L["Blacklist Info"] = "Hide spells from the queue.\n\n|cffff6666Shift+Right-click|r a spell to toggle blacklist."
L["Blacklisted Spells"] = "Blacklisted Spells"
L["Defensives"] = "Defensives"
L["Defensives Info"] = "Survival spells shown when health drops.\n|cff00ff00• Self-Heals|r: Below self-heal threshold\n|cffff6666• Major Cooldowns|r: Below cooldown threshold"
L["Restore Class Defaults name"] = "Restore Class Defaults"
L["Restore Class Defaults desc"] = "Reset the cooldown list to default spells for your class"

-- Spell search UI (used in multiple panels)
L["Search spell name or ID"] = "Search spell name or ID"
L["Search spell desc"] = "Type spell name or ID (2+ chars to search)"
L["Select spell to add"] = "Select a spell from the filtered results to add it"
L["Select spell to blacklist"] = "Select a spell from the filtered results to blacklist it"
L["Add spell manual desc"] = "Add spell by ID or exact name"
L["Add spell dropdown desc"] = "Add spell by ID or exact name (for spells not in dropdown)"
L["Select spell for hotkey"] = "Select a spell from the filtered results"
L["Add hotkey desc"] = "Add hotkey override for the selected spell"
L["No matches"] = "No matches - try a different search"
L["Please search and select a spell first"] = "Please search and select a spell first"
L["Please enter a hotkey value"] = "Please enter a hotkey value"

-------------------------------------------------------------------------------
-- German (deDE) - 8.8% of player base
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "deDE")
if L then
    -- General UI
    L["JustAssistedCombat"] = "JustAssistedCombat"
    L["General"] = "Allgemein"
    L["System"] = "System"
    L["Defensives"] = "Verteidigungsfähigkeiten"
    L["Blacklist"] = "Sperrliste"
    L["Hotkey Overrides"] = "Hotkeys"
    L["Add"] = "Hinzufügen"

    -- General Options
    L["Max Icons"] = "Max. Symbole"
    L["Icon Size"] = "Symbolgröße"
    L["Spacing"] = "Abstand"
    L["UI Scale"] = "UI-Skalierung"
    L["Primary Spell Scale"] = "Hauptzauber-Skalierung"
    L["Queue Orientation"] = "Warteschlangen-Ausrichtung"
    L["Lock Panel"] = "Panel sperren"
    L["Debug Mode"] = "Debug-Modus"
    L["Frame Opacity"] = "Rahmen-Transparenz"
    L["Queue Icon Fade"] = "Warteschlangen-Symbol ausblenden"
    L["Hide Out of Combat"] = "Warteschlange außerhalb des Kampfes ausblenden"
    L["Insert Procced Abilities"] = "Ausgelöste Fähigkeiten einfügen"
    L["Include All Available Abilities"] = "Versteckte Fähigkeiten einbeziehen"
    L["Stabilization Window"] = "Stabilisierungsfenster"
    L["Highlight Primary Spell"] = "Hauptzauber hervorheben"
    L["Show Tooltips"] = "Tooltips anzeigen"
    L["Tooltips in Combat"] = "Tooltips im Kampf"

    -- Blacklist
    L["Hide from Queue"] = "Aus Warteschlange ausblenden"
    L["Remove"] = "Entfernen"
    L["No spells currently blacklisted"] = "Keine Zauber gesperrt. Umschalt+Rechtsklick auf einen Zauber in der Warteschlange zum Hinzufügen."
    L["Blacklisted Spells"] = "Gesperrte Zauber"
    L["Blacklist description"] = "Umschalt+Rechtsklick auf ein Zauber-Symbol in der Warteschlange, um es zu dieser Liste hinzuzufügen."
    L["Hide spell desc"] = "Diesen Zauber aus Warteschlangenpositionen 2+ ausblenden. Position 1 wird nie gefiltert."

    -- Hotkey Overrides
    L["Custom Hotkey"] = "Benutzerdefinierte Taste"
    L["No custom hotkeys set"] = "Keine benutzerdefinierten Tasten gesetzt. Rechtsklick auf einen Zauber zum Festlegen."
    L["Custom Hotkey Displays"] = "Benutzerdefinierte Tastenbelegungen"
    L["Hotkey override description"] = "Benutzerdefinierten Tastentext für Zauber festlegen.\n\n|cff00ff00Rechtsklick|r um Taste festzulegen.\n|cffff6666Umschalt+Rechtsklick|r zum Sperren."

    -- Defensives
    L["Enable Defensive Suggestions"] = "Verteidigungsvorschläge aktivieren"
    L["Self-Heal Threshold"] = "Selbstheilungs-Schwellwert"
    L["Cooldown Threshold"] = "Cooldown-Schwellwert"
    L["Only In Combat"] = "Nur im Kampf"
    L["Defensive Self-Heals"] = "Selbstheilungen"
    L["Defensive Cooldowns"] = "Große Cooldowns"
    L["Defensive description"] = "Defensiv-Symbol mit zwei Prioritätsstufen:\n|cff00ff00• Selbstheilungen|r: Schnelle Heilungen\n|cffff6666• Große Abklingzeiten|r: Notfall-Defensiven"
    L["Add to %s"] = "Zu %s hinzufügen"

    -- Orientation values
    L["Horizontal"] = "Horizontal"
    L["Vertical"] = "Vertikal"
    L["Up"] = "Hoch"
    L["Dn"] = "Runter"

    -- Descriptions
    L["General description"] = "Aussehen und Verhalten der Zauber-Warteschlange konfigurieren."
    L["Icon Layout"] = "Symbol-Layout"
    L["Visibility"] = "Sichtbarkeit"
    L["Queue Content"] = "Warteschlangen-Inhalt"
    L["Appearance"] = "Aussehen"
    L["Display Behavior"] = "Anzeigeverhalten"
    L["Display"] = "Anzeige"
    L["Visual Effects"] = "Visuelle Effekte"
    L["Threshold Settings"] = "Schwellenwert-Einstellungen"

    -- Tooltip mode dropdown
    L["Tooltips"] = "Tooltips"
    L["Tooltips desc"] = "Wann Zauber-Tooltips beim Überfahren angezeigt werden sollen"
    L["Never"] = "Nie"
    L["Out of Combat Only"] = "Nur außerhalb des Kampfes"
    L["Always"] = "Immer"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Maximale Zaubersymbole (1 = Haupt, 2+ = Warteschlange)"
    L["Icon Size desc"] = "Basisgröße der Symbole in Pixeln"
    L["Spacing desc"] = "Abstand zwischen Symbolen in Pixeln"
    L["UI Scale desc"] = "Skalierungsmultiplikator für den gesamten Rahmen"
    L["Primary Spell Scale desc"] = "Skalierungsfaktor für das Hauptzauber-Symbol"
    L["Queue Orientation desc"] = "Wachstumsrichtung der Warteschlange"
    L["Highlight Primary Spell desc"] = "Leuchten auf dem Hauptzauber anzeigen"
    L["Show Tooltips desc"] = "Tooltips beim Überfahren anzeigen"
    L["Tooltips in Combat desc"] = "Tooltips während des Kampfes anzeigen"
    L["Frame Opacity desc"] = "Transparenz für den gesamten Rahmen"
    L["Queue Icon Fade desc"] = "Entsättigung für Warteschlangen-Symbole (0 = Farbe, 1 = Grau)"
    L["Hide Out of Combat desc"] = "Warteschlange außerhalb des Kampfes ausblenden"
    L["Insert Procced Abilities desc"] = "Leuchtende Proc-Fähigkeiten zur Warteschlange hinzufügen"
    L["Include All Available Abilities desc"] = "Hinter Makro-Bedingungen versteckte Fähigkeiten einbeziehen"
    L["Stabilization Window desc"] = "Sekunden vor Änderung des Hauptzaubers (reduziert Flackern)"
    L["Lock Panel desc"] = "Ziehen und Rechtsklick-Menüs deaktivieren"
    L["Debug Mode desc"] = "Debug-Infos im Chat anzeigen"
    L["Enable Defensive Suggestions desc"] = "Defensiv-Vorschläge basierend auf Gesundheit anzeigen"
    L["Self-Heal Threshold desc"] = "Selbstheilung unter diesem Gesundheits-% anzeigen"
    L["Cooldown Threshold desc"] = "Große Defensiven unter diesem Gesundheits-% anzeigen"
    L["Only In Combat desc"] = "Defensiv-Vorschläge nur im Kampf anzeigen"
    L["Icon Position desc"] = "Position der Defensiv-Symbole"
    L["Custom Hotkey desc"] = "Text, der als Hotkey angezeigt werden soll (z.B. 'F1', 'Strg+Q', 'Maus4')"
    L["Move up desc"] = "In der Priorität nach oben verschieben"
    L["Move down desc"] = "In der Priorität nach unten verschieben"
    L["Add spell desc"] = "Eine Zauber-ID eingeben (z.B. 48707) zum Hinzufügen"
    L["Add"] = "Hinzufügen"
    L["Restore Class Defaults desc"] = "Die Selbstheilungsliste auf Standard-Zauber für Ihre Klasse zurücksetzen"
    L["Restore Cooldowns Defaults desc"] = "Die Cooldown-Liste auf Standard-Zauber für Ihre Klasse zurücksetzen"

    -- Additional sections
    L["Icon Position"] = "Symbol-Position"
    L["Self-Heal Priority List"] = "Selbstheilungs-Prioritätsliste (zuerst geprüft)"
    L["Self-Heal Priority desc"] = "Schnelle Heilungen für Ihre Rotation."
    L["Restore Class Defaults"] = "Klassen-Standardwerte wiederherstellen"
    L["Major Cooldowns Priority List"] = "Große Cooldowns-Prioritätsliste (Notfall)"
    L["Major Cooldowns Priority desc"] = "Notfall-Defensiven wenn Selbstheilung nicht verfügbar."

    -- Defensive thresholds
    L["Self-Heal Threshold"] = "Selbstheilungs-Schwellwert"
    L["Self-Heal Threshold desc"] = "Selbstheilung unter diesem Gesundheits-% anzeigen"
    L["Major Cooldown Threshold"] = "Große Cooldown-Schwelle"
    L["Major Cooldown Threshold desc"] = "Große Defensiven unter diesem Gesundheits-% anzeigen"
    L["Pet Heal Threshold"] = "Begleiter-Heilschwelle"
    L["Pet Heal Threshold desc"] = "Begleiter-Heilung unter diesem Begleiter-Gesundheits-% anzeigen"
    L["Threshold Note"] = "|cff888888Im Kampf kann Gesundheit verborgen sein. Fällt zurück auf Niedrig-Gesundheit-Erkennung (~35%).|r"

    -- Defensive display options
    L["Show Health Bar"] = "Gesundheitsleiste anzeigen"
    L["Show Health Bar desc"] = "Kompakte Gesundheitsleiste neben der Warteschlange"
    L["Defensive Icon Scale"] = "Defensiv-Symbol-Skalierung"
    L["Defensive Icon Scale desc"] = "Skalierungsmultiplikator für Defensiv-Symbole"
    L["Defensive Max Icons"] = "Maximale Symbole"
    L["Defensive Max Icons desc"] = "Anzahl Defensiv-Zauber gleichzeitig (1-3)"
    L["Profiles"] = "Profile"
    L["Profiles desc"] = "Charakter- und Spezialisierungsprofilverwaltung"
    L["About"] = "Über"
    L["About JustAssistedCombat"] = "Über JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Links nach Rechts"
    L["Right to Left"] = "Rechts nach Links"
    L["Bottom to Top"] = "Unten nach Oben"
    L["Top to Bottom"] = "Oben nach Unten"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Befehle:|r\n|cff88ff88/jac|r - Optionen öffnen\n|cff88ff88/jac toggle|r - Pausieren/Fortsetzen\n|cff88ff88/jac debug|r - Debug-Modus umschalten\n|cff88ff88/jac test|r - Blizzard-API testen\n|cff88ff88/jac formcheck|r - Formerkennung prüfen\n|cff88ff88/jac find <zauber>|r - Zauber finden\n|cff88ff88/jac reset|r - Position zurücksetzen\n\nGeben Sie |cff88ff88/jac help|r für die vollständige Befehlsliste ein"

    -- About text
    L["About Text"] = "Verbessert WoWs Assistiertes Kampfsystem mit erweiterten Funktionen für besseres Spielerlebnis.\n\n|cffffff00Hauptmerkmale:|r\n• Intelligente Hotkey-Erkennung mit benutzerdefinierter Überschreibung\n• Erweiterte Makro-Analyse mit bedingten Modifikatoren\n• Intelligente Zauberfilterung und Sperrlisten-Verwaltung\n• Verbesserte visuelle Rückmeldung und Tooltips\n• Nahtlose Integration mit Blizzards nativen Hervorhebungen\n• Keine Auswirkungen auf globale Abklingzeiten\n\n|cffffff00Funktionsweise:|r\nJustAC erkennt automatisch Ihre Aktionsleisten-Einrichtung und zeigt die empfohlene Rotation mit richtigen Hotkeys an. Wenn die automatische Erkennung fehlschlägt, können Sie benutzerdefinierte Hotkey-Anzeigen per Rechtsklick festlegen.\n\n|cffffff00Optionale Verbesserungen:|r\n|cffffffff/console assistedMode 1|r - Aktiviert Blizzards Assistiertes Kampfsystem\n|cffffffff/console assistedCombatHighlight 1|r - Fügt native Button-Hervorhebung hinzu\n\nDiese Konsolenbefehle verbessern das Erlebnis, sind aber nicht erforderlich, damit JustAC funktioniert."

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Benutzerdefinierten Tastentext festlegen.\n\n|cff00ff00Rechtsklick|r um Hotkey festzulegen."
    L["Blacklist Info"] = "Zauber aus der Warteschlange ausblenden.\n\n|cffff6666Umschalt+Rechtsklick|r zum Umschalten."
    L["Defensives Info"] = "Zweistufiges Prioritätssystem:\n|cff00ff00• Selbstheilungen|r: Unter Selbstheilungs-Schwelle\n|cffff6666• Große Cooldowns|r: Unter Cooldown-Schwelle"
    L["Restore Class Defaults name"] = "Klassen-Standardwerte wiederherstellen"
end

-------------------------------------------------------------------------------
-- French (frFR) - 5.6% of player base
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "frFR")
if L then
    -- General UI
    L["JustAssistedCombat"] = "JustAssistedCombat"
    L["General"] = "Général"
    L["System"] = "Système"
    L["Defensives"] = "Défensifs"
    L["Blacklist"] = "Liste noire"
    L["Hotkey Overrides"] = "Raccourcis"
    L["Add"] = "Ajouter"

    -- General Options
    L["Max Icons"] = "Icônes max"
    L["Icon Size"] = "Taille des icônes"
    L["Spacing"] = "Espacement"
    L["UI Scale"] = "Échelle de l'interface"
    L["Primary Spell Scale"] = "Échelle du sort principal"
    L["Queue Orientation"] = "Orientation de la file"
    L["Lock Panel"] = "Verrouiller le panneau"
    L["Debug Mode"] = "Mode débogage"
    L["Frame Opacity"] = "Opacité du cadre"
    L["Queue Icon Fade"] = "Fondu des icônes de file"
    L["Hide Out of Combat"] = "Masquer la file hors combat"
    L["Insert Procced Abilities"] = "Afficher toutes les capacités déclenchées"
    L["Include All Available Abilities"] = "Inclure les capacités cachées"
    L["Stabilization Window"] = "Fenêtre de stabilisation"
    L["Highlight Primary Spell"] = "Mettre en évidence le sort principal"
    L["Show Tooltips"] = "Afficher les infobulles"
    L["Tooltips in Combat"] = "Infobulles en combat"

    -- Blacklist
    L["Hide from Queue"] = "Masquer de la file"
    L["Remove"] = "Supprimer"
    L["No spells currently blacklisted"] = "Aucun sort dans la liste noire. Maj+Clic droit sur un sort dans la file pour l'ajouter."
    L["Blacklisted Spells"] = "Sorts en liste noire"
    L["Blacklist description"] = "Maj+Clic droit sur une icône de sort dans la file pour l'ajouter à cette liste."
    L["Hide spell desc"] = "Masquer ce sort des positions 2+. La position 1 n'est jamais filtrée."

    -- Hotkey Overrides
    L["Custom Hotkey"] = "Raccourci personnalisé"
    L["No custom hotkeys set"] = "Aucun raccourci personnalisé défini. Clic droit sur un sort pour définir un raccourci."
    L["Custom Hotkey Displays"] = "Affichages de raccourcis personnalisés"
    L["Hotkey override description"] = "Définir un texte de raccourci personnalisé pour les sorts.\n\n|cff00ff00Clic droit|r pour définir un raccourci.\n|cffff6666Maj+Clic droit|r pour mettre en liste noire."

    -- Defensives
    L["Enable Defensive Suggestions"] = "Activer les suggestions défensives"
    L["Self-Heal Threshold"] = "Seuil d'auto-soin"
    L["Cooldown Threshold"] = "Seuil de temps de recharge"
    L["Only In Combat"] = "Seulement en combat"
    L["Defensive Self-Heals"] = "Auto-soins défensifs"
    L["Defensive Cooldowns"] = "Temps de recharge défensifs"
    L["Defensive description"] = "Icône défensive avec deux niveaux de priorité:\n|cff00ff00• Auto-soins|r: Soins rapides\n|cffff6666• Temps de recharge majeurs|r: Défensifs d'urgence"
    L["Add to %s"] = "Ajouter à %s"

    -- Orientation values
    L["Horizontal"] = "Horizontal"
    L["Vertical"] = "Vertical"
    L["Up"] = "Haut"
    L["Dn"] = "Bas"

    -- Descriptions
    L["General description"] = "Configurer l'apparence et le comportement de la file de sorts."
    L["Icon Layout"] = "Disposition des icônes"
    L["Visibility"] = "Visibilité"
    L["Queue Content"] = "Contenu de la file"
    L["Appearance"] = "Apparence"
    L["Display Behavior"] = "Comportement d'affichage"
    L["Display"] = "Affichage"
    L["Visual Effects"] = "Effets visuels"
    L["Threshold Settings"] = "Paramètres de seuil"

    -- Tooltip mode dropdown
    L["Tooltips"] = "Infobulles"
    L["Tooltips desc"] = "Quand afficher les infobulles de sort au survol"
    L["Never"] = "Jamais"
    L["Out of Combat Only"] = "Hors combat uniquement"
    L["Always"] = "Toujours"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Nombre maximum d'icônes de sort dans la file (position 1 = sort principal, 2+ = file d'attente)"
    L["Icon Size desc"] = "Taille de base des icônes de sort en pixels (plus élevé = icônes plus grandes)"
    L["Spacing desc"] = "Espace entre les icônes en pixels (plus élevé = plus d'espacement)"
    L["UI Scale desc"] = "Multiplicateur d'échelle pour l'ensemble de l'interface (0.5 = moitié de la taille, 2.0 = double taille)"
    L["Primary Spell Scale desc"] = "Multiplicateur d'échelle pour les icônes principales (position 1) et défensives (position 0)"
    L["Queue Orientation desc"] = "Direction dans laquelle la file de sorts s'étend à partir du sort principal"
    L["Highlight Primary Spell desc"] = "Afficher une lueur animée sur le sort principal (position 1)"
    L["Show Tooltips desc"] = "Afficher les infobulles de sort au survol"
    L["Tooltips in Combat desc"] = "Afficher les infobulles pendant le combat (nécessite Afficher les infobulles)"
    L["Frame Opacity desc"] = "Opacité globale pour l'ensemble du cadre, y compris l'icône défensive (1.0 = complètement visible, 0.0 = invisible)"
    L["Queue Icon Fade desc"] = "Désaturation pour les icônes en positions 2+ (0 = couleur complète, 1 = niveaux de gris)"
    L["Hide Out of Combat desc"] = "Masquer toute la file de sorts hors combat (n'affecte pas l'icône défensive)"
    L["Insert Procced Abilities desc"] = "Scanner le grimoire pour les capacités offensives déclenchées (lumineuses) et les afficher dans la file. Utile pour les capacités comme 'Lame gangrenée' qui peuvent ne pas apparaître dans la liste de rotation de Blizzard."
    L["Include All Available Abilities desc"] = "Inclure les capacités cachées derrière des conditions de macro (par ex. [mod:shift]) dans les recommandations. Active la stabilisation pour réduire le scintillement. Désactiver si vous voulez uniquement les capacités directement visibles sur vos barres d'action."
    L["Stabilization Window desc"] = "Combien de temps (en secondes) attendre avant de changer la recommandation de sort principal. Des valeurs plus élevées réduisent le scintillement mais peuvent sembler moins réactives. S'applique uniquement lorsque 'Inclure les capacités cachées' est activé."
    L["Lock Panel desc"] = "Bloquer le glissement et les menus contextuels (les infobulles fonctionnent toujours si activées). Basculer via clic droit sur la poignée de déplacement."
    L["Debug Mode desc"] = "Afficher les informations détaillées de l'addon dans le chat pour le dépannage"
    L["Enable Defensive Suggestions desc"] = "Afficher une suggestion de sort défensif lorsque la santé est basse"
    L["Self-Heal Threshold desc"] = "Afficher les suggestions d'auto-soin lorsque la santé tombe en dessous de ce pourcentage (plus élevé = se déclenche plus tôt)"
    L["Cooldown Threshold desc"] = "Afficher les suggestions de temps de recharge majeurs lorsque la santé tombe en dessous de ce pourcentage (plus élevé = se déclenche plus tôt)"
    L["Only In Combat desc"] = "ACTIVÉ: Masquer hors combat, afficher selon les seuils en combat.\nDÉSACTIVÉ: Toujours visible hors combat (auto-soins), basé sur les seuils en combat."
    L["Icon Position desc"] = "Où placer l'icône défensive par rapport à la file de sorts"
    L["Custom Hotkey desc"] = "Texte à afficher comme raccourci (par ex. 'F1', 'Ctrl+Q', 'Souris4')"
    L["Move up desc"] = "Monter dans la priorité"
    L["Move down desc"] = "Descendre dans la priorité"
    L["Add spell desc"] = "Entrer un ID de sort (par ex. 48707) à ajouter"
    L["Add"] = "Ajouter"
    L["Restore Class Defaults desc"] = "Réinitialiser la liste d'auto-soin aux sorts par défaut pour votre classe"
    L["Restore Cooldowns Defaults desc"] = "Réinitialiser la liste de temps de recharge aux sorts par défaut pour votre classe"

    -- Additional sections
    L["Icon Position"] = "Position de l'icône"
    L["Self-Heal Priority List"] = "Liste de priorité d'auto-soin (vérifiée en premier)"
    L["Self-Heal Priority desc"] = "Soins rapides pour votre rotation."
    L["Restore Class Defaults"] = "Restaurer les valeurs par défaut de la classe"
    L["Major Cooldowns Priority List"] = "Liste de priorité des temps de recharge majeurs (urgence)"
    L["Major Cooldowns Priority desc"] = "Défensifs d'urgence quand auto-soins indisponibles."

    -- Defensive thresholds
    L["Self-Heal Threshold"] = "Seuil d'auto-soin"
    L["Self-Heal Threshold desc"] = "Afficher auto-soins sous ce % de santé"
    L["Major Cooldown Threshold"] = "Seuil de temps de recharge majeur"
    L["Major Cooldown Threshold desc"] = "Afficher défensifs majeurs sous ce % de santé"
    L["Pet Heal Threshold"] = "Seuil de soin du familier"
    L["Pet Heal Threshold desc"] = "Afficher soins familier sous ce % de santé familier"
    L["Threshold Note"] = "|cff888888En combat, la santé peut être cachée. Détection santé basse (~35%) utilisée.|r"

    -- Defensive display options
    L["Show Health Bar"] = "Afficher la barre de santé"
    L["Show Health Bar desc"] = "Barre de santé compacte à côté de la file"
    L["Defensive Icon Scale"] = "Échelle de l'icône défensive"
    L["Defensive Icon Scale desc"] = "Multiplicateur d'échelle pour les icônes défensives"
    L["Defensive Max Icons"] = "Icônes maximum"
    L["Defensive Max Icons desc"] = "Sorts défensifs à afficher (1-3)"
    L["Profiles"] = "Profils"
    L["Profiles desc"] = "Gestion des profils de personnage et de spécialisation"
    L["About"] = "À propos"
    L["About JustAssistedCombat"] = "À propos de JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Gauche à droite"
    L["Right to Left"] = "Droite à gauche"
    L["Bottom to Top"] = "Bas vers haut"
    L["Top to Bottom"] = "Haut vers bas"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Commandes:|r\n|cff88ff88/jac|r - Ouvrir les options\n|cff88ff88/jac toggle|r - Pause/Reprendre\n|cff88ff88/jac debug|r - Basculer le mode débogage\n|cff88ff88/jac test|r - Tester l'API Blizzard\n|cff88ff88/jac formcheck|r - Vérifier la détection de forme\n|cff88ff88/jac find <sort>|r - Localiser le sort\n|cff88ff88/jac reset|r - Réinitialiser la position\n\nTapez |cff88ff88/jac help|r pour la liste complète des commandes"

    -- About text
    L["About Text"] = "Améliore le système de Combat Assisté de WoW avec des fonctionnalités avancées pour une meilleure expérience de jeu.\n\n|cffffff00Fonctionnalités clés:|r\n• Détection intelligente des raccourcis avec personnalisation\n• Analyse avancée des macros avec modificateurs conditionnels\n• Filtrage intelligent des sorts et gestion de liste noire\n• Retour visuel et infobulles améliorés\n• Intégration transparente avec les surbrillances natives de Blizzard\n• Aucun impact sur les temps de recharge globaux\n\n|cffffff00Fonctionnement:|r\nJustAC détecte automatiquement votre configuration de barre d'action et affiche la rotation recommandée avec les bons raccourcis. Lorsque la détection automatique échoue, vous pouvez définir des affichages de raccourcis personnalisés via clic droit.\n\n|cffffff00Améliorations optionnelles:|r\n|cffffffff/console assistedMode 1|r - Active le système de combat assisté de Blizzard\n|cffffffff/console assistedCombatHighlight 1|r - Ajoute la surbrillance native des boutons\n\nCes commandes de console améliorent l'expérience mais ne sont pas nécessaires pour que JustAC fonctionne."

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Définir un raccourci personnalisé.\n\n|cff00ff00Clic droit|r pour définir un raccourci."
    L["Blacklist Info"] = "Masquer des sorts de la file.\n\n|cffff6666Maj+Clic droit|r pour basculer."
    L["Defensives Info"] = "Système de priorité à deux niveaux:\n|cff00ff00• Auto-soins|r: Sous le seuil d'auto-soin\n|cffff6666• Cooldowns majeurs|r: Sous le seuil de cooldown"
    L["Restore Class Defaults name"] = "Restaurer les valeurs par défaut de la classe"
end

-------------------------------------------------------------------------------
-- Russian (ruRU) - 9.6% of player base
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "ruRU")
if L then
    -- General UI
    L["JustAssistedCombat"] = "JustAssistedCombat"
    L["General"] = "Основное"
    L["System"] = "Система"
    L["Defensives"] = "Защита"
    L["Blacklist"] = "Черный список"
    L["Hotkey Overrides"] = "Горячие клавиши"
    L["Add"] = "Добавить"

    -- General Options
    L["Max Icons"] = "Макс. иконок"
    L["Icon Size"] = "Размер иконок"
    L["Spacing"] = "Расстояние"
    L["UI Scale"] = "Масштаб интерфейса"
    L["Primary Spell Scale"] = "Масштаб главного заклинания"
    L["Queue Orientation"] = "Ориентация очереди"
    L["Lock Panel"] = "Заблокировать панель"
    L["Debug Mode"] = "Режим отладки"
    L["Frame Opacity"] = "Прозрачность рамки"
    L["Queue Icon Fade"] = "Затухание иконок очереди"
    L["Hide Out of Combat"] = "Скрыть очередь вне боя"
    L["Insert Procced Abilities"] = "Показать все сработавшие способности"
    L["Include All Available Abilities"] = "Включить скрытые способности"
    L["Stabilization Window"] = "Окно стабилизации"
    L["Highlight Primary Spell"] = "Подсветить главное заклинание"
    L["Show Tooltips"] = "Показывать подсказки"
    L["Tooltips in Combat"] = "Подсказки в бою"

    -- Blacklist
    L["Hide from Queue"] = "Скрыть из очереди"
    L["Remove"] = "Удалить"
    L["No spells currently blacklisted"] = "Нет заклинаний в черном списке. Shift+ПКМ на заклинание в очереди, чтобы добавить."
    L["Blacklisted Spells"] = "Заклинания в черном списке"
    L["Blacklist description"] = "Shift+ПКМ на иконку заклинания в очереди, чтобы добавить его в этот список."
    L["Hide spell desc"] = "Скрыть это заклинание с позиций 2+. Позиция 1 никогда не фильтруется."

    -- Hotkey Overrides
    L["Custom Hotkey"] = "Своя горячая клавиша"
    L["No custom hotkeys set"] = "Нет пользовательских горячих клавиш. ПКМ на заклинание, чтобы установить."
    L["Custom Hotkey Displays"] = "Отображение пользовательских клавиш"
    L["Hotkey override description"] = "Установить пользовательский текст горячей клавиши для заклинаний.\n\n|cff00ff00ПКМ|r чтобы установить клавишу.\n|cffff6666Shift+ПКМ|r чтобы добавить в черный список."

    -- Defensives
    L["Enable Defensive Suggestions"] = "Включить защитные подсказки"
    L["Self-Heal Threshold"] = "Порог самолечения"
    L["Cooldown Threshold"] = "Порог перезарядки"
    L["Only In Combat"] = "Только в бою"
    L["Defensive Self-Heals"] = "Защитное самолечение"
    L["Defensive Cooldowns"] = "Защитные перезарядки"
    L["Defensive description"] = "Защитная иконка с двумя уровнями приоритета:\n|cff00ff00• Самолечение|r: Быстрое исцеление\n|cffff6666• Большие перезарядки|r: Экстренная защита"
    L["Add to %s"] = "Добавить в %s"

    -- Orientation values
    L["Horizontal"] = "Горизонтально"
    L["Vertical"] = "Вертикально"
    L["Up"] = "Вверх"
    L["Dn"] = "Вниз"

    -- Descriptions
    L["General description"] = "Настроить внешний вид и поведение очереди заклинаний."
    L["Icon Layout"] = "Расположение иконок"
    L["Visibility"] = "Видимость"
    L["Queue Content"] = "Содержимое очереди"
    L["Appearance"] = "Внешний вид"
    L["Display Behavior"] = "Поведение отображения"
    L["Display"] = "Отображение"
    L["Visual Effects"] = "Визуальные эффекты"
    L["Threshold Settings"] = "Настройки порогов"

    -- Tooltip mode dropdown
    L["Tooltips"] = "Подсказки"
    L["Tooltips desc"] = "Когда показывать подсказки заклинаний при наведении"
    L["Never"] = "Никогда"
    L["Out of Combat Only"] = "Только вне боя"
    L["Always"] = "Всегда"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Максимум иконок (1 = основное, 2+ = очередь)"
    L["Icon Size desc"] = "Базовый размер иконок в пикселях"
    L["Spacing desc"] = "Расстояние между иконками в пикселях"
    L["UI Scale desc"] = "Множитель масштаба рамки"
    L["Primary Spell Scale desc"] = "Множитель масштаба основной иконки"
    L["Queue Orientation desc"] = "Направление роста очереди"
    L["Highlight Primary Spell desc"] = "Свечение на основном заклинании"
    L["Show Tooltips desc"] = "Показывать подсказки при наведении"
    L["Tooltips in Combat desc"] = "Показывать подсказки в бою"
    L["Frame Opacity desc"] = "Общая прозрачность рамки"
    L["Queue Icon Fade desc"] = "Обесцвечивание иконок очереди (0 = цвет, 1 = серый)"
    L["Hide Out of Combat desc"] = "Скрыть очередь вне боя"
    L["Insert Procced Abilities desc"] = "Добавить светящиеся проки в очередь"
    L["Include All Available Abilities desc"] = "Включить способности за условиями макросов"
    L["Stabilization Window desc"] = "Секунды до смены основного заклинания (уменьшает мерцание)"
    L["Lock Panel desc"] = "Отключить перетаскивание и меню"
    L["Debug Mode desc"] = "Показывать отладку в чате"
    L["Enable Defensive Suggestions desc"] = "Показывать защитные предложения по здоровью"
    L["Self-Heal Threshold desc"] = "Показывать самолечение ниже этого % здоровья"
    L["Cooldown Threshold desc"] = "Показывать защитные ниже этого % здоровья"
    L["Only In Combat desc"] = "Защитные только в бою"
    L["Icon Position desc"] = "Позиция защитных иконок"
    L["Custom Hotkey desc"] = "Текст для отображения как горячая клавиша (например, 'F1', 'Ctrl+Q', 'Мышь4')"
    L["Move up desc"] = "Переместить выше в приоритете"
    L["Move down desc"] = "Переместить ниже в приоритете"
    L["Add spell desc"] = "Введите ID заклинания (например, 48707) для добавления"
    L["Add"] = "Добавить"
    L["Restore Class Defaults desc"] = "Сбросить список самолечения на стандартные заклинания для вашего класса"
    L["Restore Cooldowns Defaults desc"] = "Сбросить список перезарядок на стандартные заклинания для вашего класса"

    -- Additional sections
    L["Icon Position"] = "Позиция иконки"
    L["Self-Heal Priority List"] = "Список приоритетов самолечения (проверяется первым)"
    L["Self-Heal Priority desc"] = "Быстрые исцеления для ротации."
    L["Restore Class Defaults"] = "Восстановить настройки класса"
    L["Major Cooldowns Priority List"] = "Список приоритетов больших перезарядок (экстренные)"
    L["Major Cooldowns Priority desc"] = "Экстренная защита когда самолечение недоступно."

    -- Defensive thresholds
    L["Self-Heal Threshold"] = "Порог самолечения"
    L["Self-Heal Threshold desc"] = "Показывать самолечение ниже этого % здоровья"
    L["Major Cooldown Threshold"] = "Порог большой перезарядки"
    L["Major Cooldown Threshold desc"] = "Показывать защитные ниже этого % здоровья"
    L["Pet Heal Threshold"] = "Порог лечения питомца"
    L["Pet Heal Threshold desc"] = "Показывать лечение питомца ниже этого % здоровья питомца"
    L["Threshold Note"] = "|cff888888В бою здоровье может быть скрыто. Обнаружение низкого здоровья (~35%).|r"

    -- Defensive display options
    L["Show Health Bar"] = "Показать полосу здоровья"
    L["Show Health Bar desc"] = "Компактная полоса здоровья рядом с очередью"
    L["Defensive Icon Scale"] = "Масштаб защитной иконки"
    L["Defensive Icon Scale desc"] = "Множитель масштаба для защитных иконок"
    L["Defensive Max Icons"] = "Максимум иконок"
    L["Defensive Max Icons desc"] = "Защитных заклинаний одновременно (1-3)"
    L["Profiles"] = "Профили"
    L["Profiles desc"] = "Управление профилями персонажа и специализации"
    L["About"] = "О аддоне"
    L["About JustAssistedCombat"] = "О JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Слева направо"
    L["Right to Left"] = "Справа налево"
    L["Bottom to Top"] = "Снизу вверх"
    L["Top to Bottom"] = "Сверху вниз"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Команды:|r\n|cff88ff88/jac|r - Открыть настройки\n|cff88ff88/jac toggle|r - Пауза/возобновление\n|cff88ff88/jac debug|r - Переключить режим отладки\n|cff88ff88/jac test|r - Тестировать API Blizzard\n|cff88ff88/jac formcheck|r - Проверить определение формы\n|cff88ff88/jac find <заклинание>|r - Найти заклинание\n|cff88ff88/jac reset|r - Сбросить позицию\n\nВведите |cff88ff88/jac help|r для полного списка команд"

    -- About text
    L["About Text"] = "Улучшает систему Вспомогательного боя WoW с расширенными функциями для лучшего игрового опыта.\n\n|cffffff00Основные возможности:|r\n• Умное определение горячих клавиш с переопределением\n• Расширенный анализ макросов с условными модификаторами\n• Интеллектуальная фильтрация заклинаний и управление черным списком\n• Улучшенная визуальная обратная связь и подсказки\n• Бесшовная интеграция с нативными подсветками Blizzard\n• Нулевое влияние на глобальные перезарядки\n\n|cffffff00Как работает:|r\nJustAC автоматически определяет настройку панели действий и показывает рекомендуемую ротацию с правильными горячими клавишами. Когда автоопределение не срабатывает, вы можете установить пользовательские горячие клавиши правым кликом.\n\n|cffffff00Опциональные улучшения:|r\n|cffffffff/console assistedMode 1|r - Включает систему вспомогательного боя Blizzard\n|cffffffff/console assistedCombatHighlight 1|r - Добавляет нативную подсветку кнопок\n\nЭти консольные команды улучшают опыт, но не требуются для работы JustAC."

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Установить пользовательскую клавишу.\n\n|cff00ff00Правый клик|r для установки."
    L["Blacklist Info"] = "Скрыть заклинания из очереди.\n\n|cffff6666Shift+Правый клик|r для переключения."
    L["Defensives Info"] = "Двухуровневая система приоритетов:\n|cff00ff00• Самолечение|r: Ниже порога самолечения\n|cffff6666• Большие перезарядки|r: Ниже порога перезарядки"
    L["Restore Class Defaults name"] = "Восстановить настройки класса"
end

-------------------------------------------------------------------------------
-- Spanish (esES) - Spain - ~5% of player base
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "esES")
if L then
    L["Display"] = "Pantalla"
    -- General UI
    L["JustAssistedCombat"] = "JustAssistedCombat"
    L["General"] = "General"
    L["System"] = "Sistema"
    L["Defensives"] = "Defensivos"
    L["Blacklist"] = "Lista negra"
    L["Hotkey Overrides"] = "Atajos"
    L["Add"] = "Agregar"

    -- General Options
    L["Max Icons"] = "Iconos máx"
    L["Icon Size"] = "Tamaño de icono"
    L["Spacing"] = "Espaciado"
    L["UI Scale"] = "Escala de la interfaz"
    L["Primary Spell Scale"] = "Escala del hechizo principal"
    L["Queue Orientation"] = "Orientación de cola"
    L["Lock Panel"] = "Bloquear panel"
    L["Debug Mode"] = "Modo de depuración"
    L["Frame Opacity"] = "Opacidad del marco"
    L["Queue Icon Fade"] = "Desvanecimiento de icono de cola"
    L["Hide Out of Combat"] = "Ocultar cola fuera de combate"
    L["Insert Procced Abilities"] = "Mostrar todas las habilidades activadas"
    L["Include All Available Abilities"] = "Incluir habilidades ocultas"
    L["Stabilization Window"] = "Ventana de estabilización"
    L["Highlight Primary Spell"] = "Resaltar hechizo principal"
    L["Show Tooltips"] = "Mostrar información"
    L["Tooltips in Combat"] = "Información en combate"

    -- Blacklist
    L["Hide from Queue"] = "Ocultar de la cola"
    L["Remove"] = "Eliminar"
    L["No spells currently blacklisted"] = "No hay hechizos en lista negra. Mayús+Clic derecho en un hechizo en la cola para agregarlo."
    L["Blacklisted Spells"] = "Hechizos en lista negra"
    L["Blacklist description"] = "Mayús+Clic derecho en un icono de hechizo en la cola para agregarlo a esta lista."
    L["Hide spell desc"] = "Ocultar este hechizo de las posiciones 2+. La posición 1 nunca se filtra."

    -- Hotkey Overrides
    L["Custom Hotkey"] = "Atajo personalizado"
    L["No custom hotkeys set"] = "No hay atajos personalizados configurados. Clic derecho en un hechizo para establecer un atajo."
    L["Custom Hotkey Displays"] = "Visualización de atajos personalizados"
    L["Hotkey override description"] = "Establecer texto de atajo personalizado para hechizos.\n\n|cff00ff00Clic derecho|r para establecer un atajo.\n|cffff6666Mayús+Clic derecho|r para poner en lista negra."

    -- Defensives
    L["Enable Defensive Suggestions"] = "Activar sugerencias defensivas"
    L["Self-Heal Threshold"] = "Umbral de autocuración"
    L["Cooldown Threshold"] = "Umbral de reutilización"
    L["Only In Combat"] = "Solo en combate"
    L["Defensive Self-Heals"] = "Autocuraciones defensivas"
    L["Defensive Cooldowns"] = "Reutilizaciones defensivas"
    L["Defensive description"] = "Icono defensivo con dos niveles de prioridad:\n|cff00ff00• Autocuraciones|r: Curaciones rápidas\n|cffff6666• Reutilizaciones mayores|r: Defensivos de emergencia"
    L["Add to %s"] = "Agregar a %s"

    -- Orientation values
    L["Horizontal"] = "Horizontal"
    L["Vertical"] = "Vertical"
    L["Up"] = "Arriba"
    L["Dn"] = "Abajo"

    -- Descriptions
    L["General description"] = "Configurar la apariencia y el comportamiento de la cola de hechizos."
    L["Icon Layout"] = "Diseño de iconos"
    L["Visibility"] = "Visibilidad"
    L["Queue Content"] = "Contenido de cola"
    L["Appearance"] = "Apariencia"
    L["Display Behavior"] = "Comportamiento de visualización"
    L["Visual Effects"] = "Efectos visuales"
    L["Threshold Settings"] = "Configuración de umbrales"

    -- Tooltip mode dropdown
    L["Tooltips"] = "Tooltips"
    L["Tooltips desc"] = "Cuándo mostrar información de hechizos al pasar el cursor"
    L["Never"] = "Nunca"
    L["Out of Combat Only"] = "Solo fuera de combate"
    L["Always"] = "Siempre"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Iconos máximos a mostrar (1 = principal, 2+ = cola)"
    L["Icon Size desc"] = "Tamaño base de los iconos en píxeles"
    L["Spacing desc"] = "Espacio entre iconos en píxeles"
    L["UI Scale desc"] = "Multiplicador de escala global"
    L["Primary Spell Scale desc"] = "Escala para iconos principales y defensivos"
    L["Queue Orientation desc"] = "Dirección de crecimiento de la cola"
    L["Highlight Primary Spell desc"] = "Brillo animado en el hechizo principal"
    L["Show Tooltips desc"] = "Información de hechizos al pasar cursor"
    L["Tooltips in Combat desc"] = "Mostrar información durante combate"
    L["Frame Opacity desc"] = "Transparencia global del marco"
    L["Queue Icon Fade desc"] = "Desaturación de iconos en cola (0-1)"
    L["Hide Out of Combat desc"] = "Ocultar cola fuera de combate"
    L["Insert Procced Abilities desc"] = "Añadir habilidades con proc brillante a la cola"
    L["Include All Available Abilities desc"] = "Incluir habilidades ocultas de macros en recomendaciones"
    L["Stabilization Window desc"] = "Segundos antes de cambiar hechizo principal (reduce parpadeo)"
    L["Lock Panel desc"] = "Desactivar arrastre y menús de clic derecho"
    L["Debug Mode desc"] = "Información de depuración en el chat"
    L["Enable Defensive Suggestions desc"] = "Mostrar defensivos cuando la salud es baja"
    L["Self-Heal Threshold desc"] = "Mostrar autocuraciones bajo este % de salud"
    L["Cooldown Threshold desc"] = "Mostrar reutilizaciones bajo este % de salud"
    L["Only In Combat desc"] = "Ocultar fuera de combate (autocuraciones siempre visibles si desactivado)"
    L["Icon Position desc"] = "Posición del icono defensivo"
    L["Custom Hotkey desc"] = "Texto personalizado (ej: F1, Ctrl+Q)"
    L["Move up desc"] = "Subir prioridad"
    L["Move down desc"] = "Bajar prioridad"
    L["Add spell desc"] = "ID del hechizo (ej: 48707)"
    L["Restore Class Defaults desc"] = "Restablecer autocuraciones de clase"
    L["Restore Cooldowns Defaults desc"] = "Restablecer reutilizaciones de clase"

    -- Additional sections
    L["Icon Position"] = "Posición del icono"
    L["Self-Heal Priority List"] = "Prioridad de autocuración (primero)"
    L["Self-Heal Priority desc"] = "Curaciones rápidas para tu rotación."
    L["Restore Class Defaults"] = "Restablecer valores predeterminados de clase"
    L["Major Cooldowns Priority List"] = "Prioridad de reutilizaciones (emergencia)"
    L["Major Cooldowns Priority desc"] = "Defensivos de emergencia cuando la salud está crítica."

    -- Defensive thresholds
    L["Self-Heal Threshold"] = "Umbral de autocuración"
    L["Self-Heal Threshold desc"] = "Mostrar autocuraciones bajo este % de salud"
    L["Major Cooldown Threshold"] = "Umbral de reutilización mayor"
    L["Major Cooldown Threshold desc"] = "Mostrar reutilizaciones bajo este % de salud"
    L["Pet Heal Threshold"] = "Umbral de mascota"
    L["Pet Heal Threshold desc"] = "Mostrar curaciones de mascota bajo este % de salud"
    L["Threshold Note"] = "|cff888888En combate, la salud puede ser secreta. Se usa indicador de salud baja (~35%).|r"

    -- Defensive display options
    L["Show Health Bar"] = "Mostrar barra de salud"
    L["Show Health Bar desc"] = "Barra de salud compacta junto a la cola"
    L["Defensive Icon Scale"] = "Escala de icono defensivo"
    L["Defensive Icon Scale desc"] = "Escala de iconos defensivos"
    L["Defensive Max Icons"] = "Iconos máximos"
    L["Defensive Max Icons desc"] = "Iconos defensivos a mostrar (1-3)"
    L["Profiles"] = "Perfiles"
    L["Profiles desc"] = "Gestión de perfiles"
    L["About"] = "Acerca de"
    L["About JustAssistedCombat"] = "Acerca de JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Izquierda a derecha"
    L["Right to Left"] = "Derecha a izquierda"
    L["Bottom to Top"] = "Abajo hacia arriba"
    L["Top to Bottom"] = "Arriba hacia abajo"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Comandos:|r\n|cff88ff88/jac|r - Abrir opciones\n|cff88ff88/jac toggle|r - Pausar/reanudar\n|cff88ff88/jac debug|r - Alternar modo depuración\n|cff88ff88/jac test|r - Probar API Blizzard\n|cff88ff88/jac formcheck|r - Comprobar detección de forma\n|cff88ff88/jac find <hechizo>|r - Localizar hechizo\n|cff88ff88/jac reset|r - Restablecer posición\n\nEscribe |cff88ff88/jac help|r para la lista completa de comandos"

    -- About text
    L["About Text"] = "Mejora el sistema de Combate Asistido de WoW con funciones avanzadas para una mejor experiencia de juego.\n\n|cffffff00Características clave:|r\n• Detección inteligente de atajos con personalización\n• Análisis avanzado de macros con modificadores condicionales\n• Filtrado inteligente de hechizos y gestión de lista negra\n• Retroalimentación visual e información mejoradas\n• Integración perfecta con resaltados nativos de Blizzard\n• Cero impacto en los tiempos de reutilización globales\n\n|cffffff00Cómo funciona:|r\nJustAC detecta automáticamente tu configuración de barra de acción y muestra la rotación recomendada con los atajos correctos. Cuando la detección automática falla, puedes establecer visualizaciones de atajos personalizados mediante clic derecho.\n\n|cffffff00Mejoras opcionales:|r\n|cffffffff/console assistedMode 1|r - Habilita el sistema de combate asistido de Blizzard\n|cffffffff/console assistedCombatHighlight 1|r - Añade resaltado nativo de botones\n\nEstos comandos de consola mejoran la experiencia pero no son necesarios para que JustAC funcione."

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Establecer texto de atajo personalizado para hechizos cuando la detección automática falla o por preferencia personal.\n\n|cff00ff00Clic derecho|r en un icono de hechizo en la cola para establecer un atajo personalizado."
    L["Blacklist Info"] = "Ocultar hechizos de la cola de sugerencias.\n\n|cffff6666Shift+Clic derecho|r en un icono de hechizo para agregarlo o quitarlo de la lista negra."
    L["Defensives Info"] = "Icono defensivo posición 0 con prioridad de dos niveles:\n|cff00ff00• Autocuraciones|r: Curaciones rápidas mostradas cuando la salud cae bajo el umbral\n|cffff6666• Tiempos de reutilización mayores|r: Defensivos de emergencia cuando críticamente bajo\n\nEl icono aparece con un brillo verde. El comportamiento fuera de combate está controlado por el interruptor 'Solo en combate'."
    L["Restore Class Defaults name"] = "Restablecer valores predeterminados de clase"
end

-------------------------------------------------------------------------------
-- Spanish (esMX) - Mexico/Latin America
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "esMX")
if L then
    L["Display"] = "Pantalla"
    -- Use same translations as esES (Spanish from Spain)
    -- Mexican Spanish is very similar, main differences are in slang/colloquialisms
    -- For UI text, esES translations work perfectly fine
    
    -- General UI
    L["JustAssistedCombat"] = "JustAssistedCombat"
    L["General"] = "General"
    L["System"] = "Sistema"
    L["Defensives"] = "Defensivos"
    L["Blacklist"] = "Lista negra"
    L["Hotkey Overrides"] = "Atajos"
    L["Add"] = "Agregar"

    -- General Options
    L["Max Icons"] = "Iconos máx"
    L["Icon Size"] = "Tamaño de icono"
    L["Spacing"] = "Espaciado"
    L["Primary Spell Scale"] = "Escala del hechizo principal"
    L["Queue Orientation"] = "Orientación de cola"
    L["Lock Panel"] = "Bloquear panel"
    L["Debug Mode"] = "Modo de depuración"
    L["Frame Opacity"] = "Opacidad del marco"
    L["Queue Icon Fade"] = "Desvanecimiento de icono de cola"
    L["Hide Out of Combat"] = "Ocultar cola fuera de combate"
    L["Insert Procced Abilities"] = "Mostrar todas las habilidades activadas"
    L["Include All Available Abilities"] = "Incluir habilidades ocultas"
    L["Stabilization Window"] = "Ventana de estabilización"
    L["Highlight Primary Spell"] = "Resaltar hechizo principal"
    L["Show Tooltips"] = "Mostrar información"
    L["Tooltips in Combat"] = "Información en combate"

    -- Blacklist
    L["Hide from Queue"] = "Ocultar de la cola"
    L["Remove"] = "Eliminar"
    L["No spells currently blacklisted"] = "No hay hechizos en lista negra. Mayús+Clic derecho en un hechizo en la cola para agregarlo."
    L["Blacklisted Spells"] = "Hechizos en lista negra"
    L["Blacklist description"] = "Mayús+Clic derecho en un icono de hechizo en la cola para agregarlo a esta lista."
    L["Hide spell desc"] = "Ocultar este hechizo de las posiciones 2+. La posición 1 nunca se filtra."

    -- Hotkey Overrides
    L["Custom Hotkey"] = "Atajo personalizado"
    L["No custom hotkeys set"] = "No hay atajos personalizados configurados. Clic derecho en un hechizo para establecer un atajo."
    L["Custom Hotkey Displays"] = "Visualización de atajos personalizados"
    L["Hotkey override description"] = "Establecer texto de atajo personalizado para hechizos.\n\n|cff00ff00Clic derecho|r para establecer un atajo.\n|cffff6666Mayús+Clic derecho|r para poner en lista negra."

    -- Defensives
    L["Enable Defensive Suggestions"] = "Activar sugerencias defensivas"
    L["Self-Heal Threshold"] = "Umbral de autocuración"
    L["Cooldown Threshold"] = "Umbral de reutilización"
    L["Only In Combat"] = "Solo en combate"
    L["Defensive Self-Heals"] = "Autocuraciones defensivas"
    L["Defensive Cooldowns"] = "Reutilizaciones defensivas"
    L["Defensive description"] = "Icono defensivo con dos niveles de prioridad:\n|cff00ff00• Autocuraciones|r: Curaciones rápidas\n|cffff6666• Reutilizaciones mayores|r: Defensivos de emergencia"
    L["Add to %s"] = "Agregar a %s"

    -- Orientation values
    L["Horizontal"] = "Horizontal"
    L["Vertical"] = "Vertical"
    L["Up"] = "Arriba"
    L["Dn"] = "Abajo"

    -- Descriptions
    L["General description"] = "Configurar la apariencia y el comportamiento de la cola de hechizos."
    L["Icon Layout"] = "Diseño de iconos"
    L["Visibility"] = "Visibilidad"
    L["Queue Content"] = "Contenido de cola"
    L["Appearance"] = "Apariencia"
    L["Display Behavior"] = "Comportamiento de visualización"
    L["Visual Effects"] = "Efectos visuales"
    L["Threshold Settings"] = "Configuración de umbrales"

    -- Tooltip mode dropdown
    L["Tooltips"] = "Tooltips"
    L["Tooltips desc"] = "Cuándo mostrar información de hechizos al pasar el cursor"
    L["Never"] = "Nunca"
    L["Out of Combat Only"] = "Solo fuera de combate"
    L["Always"] = "Siempre"

    -- Detailed descriptions (same as esES)
    L["Max Icons desc"] = "Iconos máximos a mostrar (1 = principal, 2+ = cola)"
    L["Icon Size desc"] = "Tamaño base de los iconos en píxeles"
    L["Spacing desc"] = "Espacio entre iconos en píxeles"
    L["UI Scale desc"] = "Multiplicador de escala global"
    L["Primary Spell Scale desc"] = "Escala para iconos principales y defensivos"
    L["Queue Orientation desc"] = "Dirección de crecimiento de la cola"
    L["Highlight Primary Spell desc"] = "Brillo animado en el hechizo principal"
    L["Show Tooltips desc"] = "Información de hechizos al pasar cursor"
    L["Tooltips in Combat desc"] = "Mostrar información durante combate"
    L["Frame Opacity desc"] = "Transparencia global del marco"
    L["Queue Icon Fade desc"] = "Desaturación de iconos en cola (0-1)"
    L["Hide Out of Combat desc"] = "Ocultar cola fuera de combate"
    L["Insert Procced Abilities desc"] = "Añadir habilidades con proc brillante a la cola"
    L["Include All Available Abilities desc"] = "Incluir habilidades ocultas de macros en recomendaciones"
    L["Stabilization Window desc"] = "Segundos antes de cambiar hechizo principal (reduce parpadeo)"
    L["Lock Panel desc"] = "Desactivar arrastre y menús de clic derecho"
    L["Debug Mode desc"] = "Información de depuración en el chat"
    L["Enable Defensive Suggestions desc"] = "Mostrar defensivos cuando la salud es baja"
    L["Self-Heal Threshold desc"] = "Mostrar autocuraciones bajo este % de salud"
    L["Cooldown Threshold desc"] = "Mostrar reutilizaciones bajo este % de salud"
    L["Only In Combat desc"] = "Ocultar fuera de combate (autocuraciones siempre visibles si desactivado)"
    L["Icon Position desc"] = "Posición del icono defensivo"
    L["Custom Hotkey desc"] = "Texto personalizado (ej: F1, Ctrl+Q)"
    L["Move up desc"] = "Subir prioridad"
    L["Move down desc"] = "Bajar prioridad"
    L["Add spell desc"] = "ID del hechizo (ej: 48707)"
    L["Restore Class Defaults desc"] = "Restablecer autocuraciones de clase"
    L["Restore Cooldowns Defaults desc"] = "Restablecer reutilizaciones de clase"

    -- Additional sections
    L["Icon Position"] = "Posición del icono"
    L["Self-Heal Priority List"] = "Prioridad de autocuración (primero)"
    L["Self-Heal Priority desc"] = "Curaciones rápidas para tu rotación."
    L["Restore Class Defaults"] = "Restablecer valores predeterminados de clase"
    L["Major Cooldowns Priority List"] = "Prioridad de reutilizaciones (emergencia)"
    L["Major Cooldowns Priority desc"] = "Defensivos de emergencia cuando la salud está crítica."

    -- Defensive thresholds
    L["Self-Heal Threshold"] = "Umbral de autocuración"
    L["Self-Heal Threshold desc"] = "Mostrar autocuraciones bajo este % de salud"
    L["Major Cooldown Threshold"] = "Umbral de reutilización mayor"
    L["Major Cooldown Threshold desc"] = "Mostrar reutilizaciones bajo este % de salud"
    L["Pet Heal Threshold"] = "Umbral de mascota"
    L["Pet Heal Threshold desc"] = "Mostrar curaciones de mascota bajo este % de salud"
    L["Threshold Note"] = "|cff888888En combate, la salud puede ser secreta. Se usa indicador de salud baja (~35%).|r"

    -- Defensive display options
    L["Show Health Bar"] = "Mostrar barra de salud"
    L["Show Health Bar desc"] = "Barra de salud compacta junto a la cola"
    L["Defensive Icon Scale"] = "Escala de icono defensivo"
    L["Defensive Icon Scale desc"] = "Escala de iconos defensivos"
    L["Defensive Max Icons"] = "Iconos máximos"
    L["Defensive Max Icons desc"] = "Iconos defensivos a mostrar (1-3)"
    L["Profiles"] = "Perfiles"
    L["Profiles desc"] = "Gestión de perfiles"
    L["About"] = "Acerca de"
    L["About JustAssistedCombat"] = "Acerca de JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Izquierda a derecha"
    L["Right to Left"] = "Derecha a izquierda"
    L["Bottom to Top"] = "Abajo hacia arriba"
    L["Top to Bottom"] = "Arriba hacia abajo"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Comandos:|r\n/jac - Opciones\n/jac toggle - Pausar\n/jac debug - Depuración\n/jac test - Probar API\n/jac reset - Restablecer\n\n|cff88ff88/jac help|r para todos"

    -- About text
    L["About Text"] = "Mejora Combate Asistido con detección de atajos, análisis de macros y filtrado de hechizos.\n\n|cffffff00Comandos opcionales:|r\n/console assistedMode 1\n/console assistedCombatHighlight 1"

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Atajos personalizados para hechizos.\n|cff00ff00Clic derecho|r para establecer."
    L["Blacklist Info"] = "Ocultar hechizos de la cola.\n|cffff6666Shift+Clic derecho|r para alternar."
    L["Defensives Info"] = "|cff00ff00Autocuraciones|r en umbral alto\n|cffff6666Reutilizaciones|r en salud crítica"
    L["Restore Class Defaults name"] = "Restablecer valores predeterminados de clase"
end

-------------------------------------------------------------------------------
-- Portuguese (ptBR) - Brazil - ~8-10% of player base
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "ptBR")
if L then
    -- General UI
    L["JustAssistedCombat"] = "JustAssistedCombat"
    L["General"] = "Geral"
    L["System"] = "Sistema"
    L["Defensives"] = "Defensivos"
    L["Blacklist"] = "Lista negra"
    L["Hotkey Overrides"] = "Atalhos"
    L["Add"] = "Adicionar"

    -- General Options
    L["Max Icons"] = "Ícones máx"
    L["Icon Size"] = "Tamanho do ícone"
    L["Spacing"] = "Espaçamento"
    L["Primary Spell Scale"] = "Escala da magia principal"
    L["Queue Orientation"] = "Orientação da fila"
    L["Lock Panel"] = "Travar painel"
    L["Debug Mode"] = "Modo de depuração"
    L["Frame Opacity"] = "Opacidade do quadro"
    L["Queue Icon Fade"] = "Esmaecimento do ícone da fila"
    L["Hide Out of Combat"] = "Ocultar fila fora de combate"
    L["Insert Procced Abilities"] = "Mostrar todas as habilidades ativadas"
    L["Include All Available Abilities"] = "Incluir habilidades ocultas"
    L["Stabilization Window"] = "Janela de estabilização"
    L["Highlight Primary Spell"] = "Destacar magia principal"
    L["Show Tooltips"] = "Mostrar dicas"
    L["Tooltips in Combat"] = "Dicas em combate"

    -- Blacklist
    L["Hide from Queue"] = "Ocultar da fila"
    L["Remove"] = "Remover"
    L["No spells currently blacklisted"] = "Nenhuma magia na lista negra. Shift+Clique direito em uma magia na fila para adicionar."
    L["Blacklisted Spells"] = "Magias na lista negra"
    L["Blacklist description"] = "Shift+Clique direito em um ícone de magia na fila para adicioná-lo a esta lista."
    L["Hide spell desc"] = "Ocultar esta magia das posições 2+. A posição 1 nunca é filtrada."

    -- Hotkey Overrides
    L["Custom Hotkey"] = "Atalho personalizado"
    L["No custom hotkeys set"] = "Nenhum atalho personalizado definido. Clique direito em uma magia para definir um atalho."
    L["Custom Hotkey Displays"] = "Exibições de atalhos personalizados"
    L["Hotkey override description"] = "Definir texto de atalho personalizado para magias.\n\n|cff00ff00Clique direito|r para definir um atalho.\n|cffff6666Shift+Clique direito|r para colocar na lista negra."

    -- Defensives
    L["Enable Defensive Suggestions"] = "Ativar sugestões defensivas"
    L["Self-Heal Threshold"] = "Limite de autocura"
    L["Cooldown Threshold"] = "Limite de recarga"
    L["Only In Combat"] = "Apenas em combate"
    L["Defensive Self-Heals"] = "Autocuras defensivas"
    L["Defensive Cooldowns"] = "Recargas defensivas"
    L["Defensive description"] = "Ícone defensivo com dois níveis de prioridade:\n|cff00ff00• Autocuras|r: Curas rápidas\n|cffff6666• Recargas maiores|r: Defensivos de emergência"
    L["Add to %s"] = "Adicionar a %s"

    -- Orientation values
    L["Horizontal"] = "Horizontal"
    L["Vertical"] = "Vertical"
    L["Up"] = "Cima"
    L["Dn"] = "Baixo"

    -- Descriptions
    L["General description"] = "Configurar a aparência e o comportamento da fila de magias."
    L["Icon Layout"] = "Layout dos ícones"
    L["Visibility"] = "Visibilidade"
    L["Queue Content"] = "Conteúdo da fila"
    L["Appearance"] = "Aparência"
    L["Display Behavior"] = "Comportamento de exibição"
    L["Display"] = "Exibição"
    L["Visual Effects"] = "Efeitos visuais"
    L["Threshold Settings"] = "Configurações de limite"

    -- Tooltip mode dropdown
    L["Tooltips"] = "Dicas"
    L["Tooltips desc"] = "Quando mostrar dicas de magias ao passar o cursor"
    L["Never"] = "Nunca"
    L["Out of Combat Only"] = "Apenas fora de combate"
    L["Always"] = "Sempre"

    -- Detailed descriptions
    L["Max Icons desc"] = "Ícones máximos a exibir (1 = principal, 2+ = fila)"
    L["Icon Size desc"] = "Tamanho base dos ícones em pixels"
    L["Spacing desc"] = "Espaço entre ícones em pixels"
    L["Primary Spell Scale desc"] = "Escala para ícones principais e defensivos"
    L["Queue Orientation desc"] = "Direção de crescimento da fila"
    L["Highlight Primary Spell desc"] = "Brilho animado na magia principal"
    L["Show Tooltips desc"] = "Dicas de magias ao passar o cursor"
    L["Tooltips in Combat desc"] = "Mostrar dicas durante combate"
    L["Frame Opacity desc"] = "Transparência global do quadro"
    L["Queue Icon Fade desc"] = "Dessaturação de ícones na fila (0-1)"
    L["Hide Out of Combat desc"] = "Ocultar fila fora de combate"
    L["Insert Procced Abilities desc"] = "Adicionar habilidades com proc brilhante à fila"
    L["Include All Available Abilities desc"] = "Incluir habilidades ocultas de macros nas recomendações"
    L["Stabilization Window desc"] = "Segundos antes de mudar magia principal (reduz oscilação)"
    L["Lock Panel desc"] = "Desativar arrasto e menus de clique direito"
    L["Debug Mode desc"] = "Informações de depuração no chat"
    L["Enable Defensive Suggestions desc"] = "Mostrar defensivos quando a vida está baixa"
    L["Self-Heal Threshold desc"] = "Mostrar autocuras abaixo deste % de vida"
    L["Cooldown Threshold desc"] = "Mostrar recargas abaixo deste % de vida"
    L["Only In Combat desc"] = "Ocultar fora de combate (autocuras sempre visíveis se desativado)"
    L["Icon Position desc"] = "Posição do ícone defensivo"
    L["Custom Hotkey desc"] = "Texto personalizado (ex: F1, Ctrl+Q)"
    L["Move up desc"] = "Subir prioridade"
    L["Move down desc"] = "Descer prioridade"
    L["Add spell desc"] = "ID da magia (ex: 48707)"
    L["Add"] = "Adicionar"
    L["Restore Class Defaults desc"] = "Redefinir autocuras da classe"
    L["Restore Cooldowns Defaults desc"] = "Redefinir recargas da classe"

    -- Additional sections
    L["Icon Position"] = "Posição do ícone"
    L["Self-Heal Priority List"] = "Prioridade de autocura (primeiro)"
    L["Self-Heal Priority desc"] = "Curas rápidas para sua rotação."
    L["Restore Class Defaults"] = "Restaurar padrões da classe"
    L["Major Cooldowns Priority List"] = "Prioridade de recargas (emergência)"
    L["Major Cooldowns Priority desc"] = "Defensivos de emergência quando a vida está crítica."

    -- Defensive thresholds
    L["Self-Heal Threshold"] = "Limite de autocura"
    L["Self-Heal Threshold desc"] = "Mostrar autocuras abaixo deste % de vida"
    L["Major Cooldown Threshold"] = "Limite de recarga maior"
    L["Major Cooldown Threshold desc"] = "Mostrar recargas abaixo deste % de vida"
    L["Pet Heal Threshold"] = "Limite de pet"
    L["Pet Heal Threshold desc"] = "Mostrar curas de pet abaixo deste % de vida"
    L["Threshold Note"] = "|cff888888Em combate, a vida pode ser secreta. Usa-se indicador de vida baixa (~35%).|r"

    -- Defensive display options
    L["Show Health Bar"] = "Mostrar barra de vida"
    L["Show Health Bar desc"] = "Barra de vida compacta junto à fila"
    L["Defensive Icon Scale"] = "Escala do ícone defensivo"
    L["Defensive Icon Scale desc"] = "Escala de ícones defensivos"
    L["Defensive Max Icons"] = "Ícones máximos"
    L["Defensive Max Icons desc"] = "Ícones defensivos a mostrar (1-3)"
    L["Profiles"] = "Perfis"
    L["Profiles desc"] = "Gerenciamento de perfis"
    L["About"] = "Sobre"
    L["About JustAssistedCombat"] = "Sobre JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Esquerda para direita"
    L["Right to Left"] = "Direita para esquerda"
    L["Bottom to Top"] = "Baixo para cima"
    L["Top to Bottom"] = "Cima para baixo"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Comandos:|r\n/jac - Opções\n/jac toggle - Pausar\n/jac debug - Depuração\n/jac test - Testar API\n/jac reset - Redefinir\n\n|cff88ff88/jac help|r para todos"

    -- About text
    L["About Text"] = "Aprimora Combate Assistido com detecção de atalhos, análise de macros e filtragem de magias.\n\n|cffffff00Comandos opcionais:|r\n/console assistedMode 1\n/console assistedCombatHighlight 1"

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Atalhos personalizados para magias.\n|cff00ff00Clique direito|r para definir."
    L["Blacklist Info"] = "Ocultar magias da fila.\n|cffff6666Shift+Clique direito|r para alternar."
    L["Defensives Info"] = "|cff00ff00Autocuras|r em limite alto\n|cffff6666Recargas|r em vida crítica"
    L["Restore Class Defaults name"] = "Restaurar padrões da classe"
end
