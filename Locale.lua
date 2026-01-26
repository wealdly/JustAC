-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Localization Module

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "enUS", true)
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "General"
L["System"] = "System"
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
L["Lock Panel"] = "Lock Panel"
L["Debug Mode"] = "Debug Mode"
L["Frame Opacity"] = "Frame Opacity"
L["Queue Icon Fade"] = "Queue Icon Fade"
L["Hide Out of Combat"] = "Hide Out of Combat"
L["Insert Procced Abilities"] = "Insert Procced Abilities"
L["Include All Available Abilities"] = "Include All Available Abilities"
L["Stabilization Window"] = "Stabilization Window"
L["Highlight Primary Spell"] = "Highlight Primary Spell"
L["Show Tooltips"] = "Show Tooltips"
L["Tooltips in Combat"] = "Tooltips in Combat"

-- Hotkey Options
L["Hotkey Options"] = "Hotkey Options"
L["Hotkey Font"] = "Hotkey Font"
L["Font for hotkey text"] = "Font for hotkey text"
L["Hotkey Size"] = "Hotkey Size"
L["Size of hotkey text"] = "Size of hotkey text"
L["Hotkey Color"] = "Hotkey Color"
L["Color of hotkey text"] = "Color of hotkey text"
L["Parent Anchor"] = "Parent Anchor"
L["Anchor point of hotkey text relative to icon"] = "Anchor point of hotkey text relative to icon"
L["Hotkey Anchor"] = "Hotkey Anchor"
L["Which point on the hotkey text attaches to the anchor"] = "Which point on the hotkey text attaches to the anchor"
L["First X Offset"] = "First X Offset"
L["Horizontal offset for first icon hotkey text"] = "Horizontal offset for first icon hotkey text"
L["First Y Offset"] = "First Y Offset"
L["Vertical offset for first icon hotkey text"] = "Vertical offset for first icon hotkey text"
L["Queue X Offset"] = "Queue X Offset"
L["Horizontal offset for queued icons hotkey text"] = "Horizontal offset for queued icons hotkey text"
L["Queue Y Offset"] = "Queue Y Offset"
L["Vertical offset for queued icons hotkey text"] = "Vertical offset for queued icons hotkey text"
L["Outline Mode"] = "Outline Mode"
L["Font outline and rendering flags for hotkey text"] = "Font outline and rendering flags for hotkey text"
L["None"] = "None"
L["Outline"] = "Outline"
L["Thick Outline"] = "Thick Outline"
L["Monochrome"] = "Monochrome"
L["Outline + Monochrome"] = "Outline + Monochrome"
L["Thick Outline + Monochrome"] = "Thick Outline + Monochrome"

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
L["Defensive description"] = "Shows a defensive spell suggestion when health is low.\n|cff00ff00• Procced abilities|r: Victory Rush, free heals shown at ANY health\n|cff00ff00• Self-Heals|r: Quick heals shown at ~35% health\n|cffff6666• Major Cooldowns|r: Emergency defensives at ~20% health"
L["Add to %s"] = "Add to %s"

-- Orientation values
L["Horizontal"] = "Horizontal"
L["Vertical"] = "Vertical"
L["Up"] = "Up"
L["Dn"] = "Dn"

-- Descriptions
L["General description"] = "Configure the appearance and behavior of the spell queue display."
L["Icon Layout"] = "Icon Layout"
L["Display Behavior"] = "Display Behavior"
L["Visual Effects"] = "Visual Effects"
L["Threshold Settings"] = "Threshold Settings"

-- Detailed descriptions
L["Max Icons desc"] = "Maximum number of spell icons to show in the queue (position 1 is primary, 2+ is queue)"
L["Icon Size desc"] = "Base size of spell icons in pixels (higher = larger icons)"
L["Spacing desc"] = "Space between icons in pixels (higher = more spread out)"
L["UI Scale desc"] = "Scale multiplier for the entire UI frame (0.5 = half size, 2.0 = double size)"
L["Primary Spell Scale desc"] = "Scale multiplier for the primary (position 1) and defensive (position 0) icons"
L["Queue Orientation desc"] = "Direction the spell queue grows from the primary spell"
L["Highlight Primary Spell desc"] = "Show animated glow on the primary spell (position 1)"
L["Show Tooltips desc"] = "Display spell tooltips on hover"
L["Single-Button Assistant Warning"] = "Warning: Place the Single-Button Assistant on any action bar for JustAC to work properly."
L["Tooltips in Combat desc"] = "Show tooltips during combat (requires Show Tooltips)"
L["Frame Opacity desc"] = "Global opacity for the entire frame including defensive icon (1.0 = fully visible, 0.0 = invisible)"
L["Queue Icon Fade desc"] = "Desaturation for icons in positions 2+ (0 = full color, 1 = grayscale)"
L["Hide Out of Combat"] = "Hide Out of Combat"
L["Hide Out of Combat desc"] = "Hide the entire spell queue when not in combat (does not affect defensive icon)"
L["Hide for Healer Specs"] = "Hide for Healer Specs"
L["Hide for Healer Specs desc"] = "Automatically hide the spell queue when you are in a healer specialization"
L["Hide When Mounted"] = "Hide When Mounted"
L["Hide When Mounted desc"] = "Hide the spell queue while mounted"
L["Hide Item Abilities"] = "Hide Item Abilities"
L["Hide Item Abilities desc"] = "Hide abilities from equipped items (trinkets, engineering tinkers) from the queue"
L["Insert Procced Abilities desc"] = "Insert procced (glowing) offensive abilities from your spellbook into the queue. Useful for abilities like Fel Blade that may not appear in Blizzard's rotation list."
L["Include All Available Abilities desc"] = "Include abilities hidden behind macro conditionals (e.g., [mod:shift]) in recommendations. Disable if you only want abilities directly visible on your action bars."
L["Stabilization Window desc"] = "How long (in seconds) to wait before changing the primary spell recommendation. Higher values reduce flickering but may feel less responsive. Only applies when 'Include All Available Abilities' is enabled."
L["Lock Panel desc"] = "Block dragging and right-click menus (tooltips still work if enabled). Toggle via right-click on move handle."
L["Debug Mode desc"] = "Show detailed addon information in chat for troubleshooting"
L["Enable Defensive Suggestions desc"] = "Show a defensive spell suggestion when health is low. Procced abilities (Victory Rush, free heals) show at any health."
L["Only In Combat desc"] = "ON: Hide out of combat (unless you have a proc).\nOFF: Always visible, show heals based on health."
L["Icon Position desc"] = "Where to place the defensive icon relative to the spell queue"
L["Custom Hotkey desc"] = "Text to display as hotkey (e.g., 'F1', 'Ctrl+Q', 'Mouse4')"
L["Move up desc"] = "Move up in priority"
L["Move down desc"] = "Move down in priority"
L["Add spell desc"] = "Enter a spell ID (e.g., 48707) to add"
L["Add"] = "Add"
L["Restore Class Defaults desc"] = "Reset the self-heal list to default spells for your class"
L["Restore Cooldowns Defaults desc"] = "Reset the cooldown list to default spells for your class"

-- Additional sections
L["Icon Position"] = "Icon Position"
L["Self-Heal Priority List"] = "Self-Heal Priority List (checked first)"
L["Self-Heal Priority desc"] = "Quick heals/absorbs to weave into your rotation. First usable spell is suggested."
L["Restore Class Defaults"] = "Restore Class Defaults"
L["Major Cooldowns Priority List"] = "Major Cooldowns Priority List (emergency)"
L["Major Cooldowns Priority desc"] = "Big defensives for emergencies. Only checked if no self-heal is available and health is critically low."
L["Profiles"] = "Profiles"
L["Profiles desc"] = "Character and spec profile management"
L["About"] = "About"
L["About JustAssistedCombat"] = "About JustAssistedCombat"

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
L["Hotkey Overrides Info"] = "Set custom hotkey text for spells when automatic detection fails or for personal preference.\n\n|cff00ff00Right-click|r a spell icon in the queue to set a custom hotkey."
L["Custom Hotkey Displays"] = "Custom Hotkey Displays"
L["Blacklist"] = "Blacklist"
L["Blacklist Info"] = "Hide spells from the suggestion queue.\n\n|cffff6666Shift+Right-click|r a spell icon in the queue to add or remove it from the blacklist."
L["Blacklisted Spells"] = "Blacklisted Spells"
L["Defensives"] = "Defensives"
L["Defensives Info"] = "Position 0 defensive icon with two-tier priority:\n|cff00ff00• Self-Heals|r: Quick heals shown when health drops below threshold\n|cffff6666• Major Cooldowns|r: Emergency defensives when critically low\n\nIcon appears with a green glow. Out of combat behavior is controlled by 'Only In Combat' toggle."
L["Display Behavior"] = "Display Behavior"
L["Restore Class Defaults name"] = "Restore Class Defaults"
L["Restore Class Defaults desc"] = "Reset the cooldown list to default spells for your class"

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

    -- Hotkey Options
    L["Hotkey Options"] = "Hotkey-Optionen"
    L["Hotkey Font"] = "Hotkey-Schriftart"
    L["Font for hotkey text"] = "Schriftart für Hotkey-Text"
    L["Hotkey Size"] = "Hotkey-Größe"
    L["Size of hotkey text"] = "Größe des Hotkey-Texts"
    L["Hotkey Color"] = "Hotkey-Farbe"
    L["Color of hotkey text"] = "Farbe des Hotkey-Texts"
    L["Parent Anchor"] = "Elternanker"
    L["Anchor point of hotkey text relative to icon"] = "Ankerpunkt des Hotkey-Texts relativ zum Symbol"
    L["Hotkey Anchor"] = "Hotkey-Anker"
    L["Which point on the hotkey text attaches to the anchor"] = "Welcher Punkt des Hotkey-Texts am Anker befestigt wird"
    L["First X Offset"] = "Erster X-Versatz"
    L["Horizontal offset for first icon hotkey text"] = "Horizontaler Versatz für den ersten Hotkey-Text"
    L["First Y Offset"] = "Erster Y-Versatz"
    L["Vertical offset for first icon hotkey text"] = "Vertikaler Versatz für den ersten Hotkey-Text"
    L["Queue X Offset"] = "Warteschlangen-X-Versatz"
    L["Horizontal offset for queued icons hotkey text"] = "Horizontaler Versatz für Hotkey-Text in der Warteschlange"
    L["Queue Y Offset"] = "Warteschlangen-Y-Versatz"
    L["Vertical offset for queued icons hotkey text"] = "Vertikaler Versatz für Hotkey-Text in der Warteschlange"
    L["Outline Mode"] = "Konturenmodus"
    L["Font outline and rendering flags for hotkey text"] = "Kontur- und Rendering-Modi für Hotkey-Text"
    L["None"] = "Keine"
    L["Outline"] = "Kontur"
    L["Thick Outline"] = "Dicke Kontur"
    L["Monochrome"] = "Monochrom"
    L["Outline + Monochrome"] = "Kontur + Monochrom"
    L["Thick Outline + Monochrome"] = "Dicke Kontur + Monochrom"

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
    L["Display Behavior"] = "Anzeigeverhalten"
    L["Visual Effects"] = "Visuelle Effekte"
    L["Threshold Settings"] = "Schwellenwert-Einstellungen"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Maximale Anzahl von Zaubersymbolen in der Warteschlange (Position 1 = Hauptzauber, 2+ = Warteschlange)"
    L["Icon Size desc"] = "Basisgröße der Zaubersymbole in Pixeln (höher = größere Symbole)"
    L["Spacing desc"] = "Abstand zwischen Symbolen in Pixeln (höher = mehr Abstand)"
    L["UI Scale desc"] = "Skalierungsmultiplikator für das gesamte UI-Rahmen (0.5 = halbe Größe, 2.0 = doppelte Größe)"
    L["Primary Spell Scale desc"] = "Skalierungsfaktor für die primären (Position 1) und defensiven (Position 0) Symbole"
    L["Queue Orientation desc"] = "Richtung, in die die Zauber-Warteschlange vom Hauptzauber aus wächst"
    L["Highlight Primary Spell desc"] = "Animiertes Leuchten auf dem Hauptzauber anzeigen (Position 1)"
    L["Show Tooltips desc"] = "Zauber-Tooltips beim Überfahren anzeigen"
    L["Tooltips in Combat desc"] = "Tooltips während des Kampfes anzeigen (erfordert Tooltips anzeigen)"
    L["Frame Opacity desc"] = "Globale Transparenz für den gesamten Rahmen einschließlich defensivem Symbol (1.0 = vollständig sichtbar, 0.0 = unsichtbar)"
    L["Queue Icon Fade desc"] = "Entsättigung für Symbole in Position 2+ (0 = volle Farbe, 1 = Graustufen)"
    L["Hide Out of Combat desc"] = "Die gesamte Zauber-Warteschlange außerhalb des Kampfes ausblenden (betrifft nicht defensives Symbol)"
    L["Insert Procced Abilities desc"] = "Zauberbuch nach ausgelösten (leuchtenden) offensiven Fähigkeiten durchsuchen und in der Warteschlange anzeigen. Nützlich für Fähigkeiten wie 'Teufelsklinge', die möglicherweise nicht in Blizzards Rotationsliste erscheinen."
    L["Include All Available Abilities desc"] = "Fähigkeiten einbeziehen, die hinter Makro-Bedingungen versteckt sind (z.B. [mod:shift]). Ermöglicht Stabilisierung zur Reduzierung von Flackern. Deaktivieren, wenn nur direkt sichtbare Fähigkeiten auf Ihren Aktionsleisten gewünscht werden."
    L["Stabilization Window desc"] = "Wie lange (in Sekunden) gewartet werden soll, bevor die primäre Zauberempfehlung geändert wird. Höhere Werte reduzieren Flackern, können sich jedoch weniger reaktionsschnell anfühlen. Gilt nur, wenn 'Versteckte Fähigkeiten einbeziehen' aktiviert ist."
    L["Lock Panel desc"] = "Ziehen und Rechtsklick-Menüs blockieren (Tooltips funktionieren weiterhin, wenn aktiviert). Umschalten über Rechtsklick auf Verschiebegriff."
    L["Debug Mode desc"] = "Detaillierte Addon-Informationen im Chat zur Fehlerbehebung anzeigen"
    L["Enable Defensive Suggestions desc"] = "Verteidigungszauber-Vorschlag anzeigen, wenn die Gesundheit niedrig ist"
    L["Self-Heal Threshold desc"] = "Selbstheilungsvorschläge anzeigen, wenn die Gesundheit unter diesen Prozentsatz fällt (höher = früher ausgelöst)"
    L["Cooldown Threshold desc"] = "Große Cooldown-Vorschläge anzeigen, wenn die Gesundheit unter diesen Prozentsatz fällt (höher = früher ausgelöst)"
    L["Only In Combat desc"] = "AN: Außerhalb des Kampfes ausblenden, basierend auf Schwellenwerten im Kampf anzeigen.\nAUS: Außerhalb des Kampfes immer sichtbar (Selbstheilungen), schwellenwertbasiert im Kampf."
    L["Icon Position desc"] = "Wo das defensive Symbol relativ zur Zauber-Warteschlange platziert werden soll"
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
    L["Self-Heal Priority desc"] = "Schnelle Heilungen/Absorptionen zum Einweben in Ihre Rotation. Erster verwendbarer Zauber wird vorgeschlagen."
    L["Restore Class Defaults"] = "Klassen-Standardwerte wiederherstellen"
    L["Major Cooldowns Priority List"] = "Große Cooldowns-Prioritätsliste (Notfall)"
    L["Major Cooldowns Priority desc"] = "Große Defensivfähigkeiten für Notfälle. Wird nur geprüft, wenn keine Selbstheilung verfügbar ist und die Gesundheit kritisch niedrig ist."
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
    L["Hotkey Overrides Info"] = "Benutzerdefinierten Tastentext für Zauber festlegen, wenn die automatische Erkennung fehlschlägt oder nach persönlicher Präferenz.\n\n|cff00ff00Rechtsklick|r auf ein Zauber-Symbol in der Warteschlange, um einen benutzerdefinierten Hotkey festzulegen."
    L["Blacklist Info"] = "Zauber aus der Vorschlagswarteschlange ausblenden.\n\n|cffff6666Umschalt+Rechtsklick|r auf ein Zauber-Symbol, um es zur Sperrliste hinzuzufügen oder zu entfernen."
    L["Defensives Info"] = "Position 0 defensives Symbol mit zweistufiger Priorität:\n|cff00ff00• Selbstheilungen|r: Schnelle Heilungen, die angezeigt werden, wenn die Gesundheit unter den Schwellenwert fällt\n|cffff6666• Große Abklingzeiten|r: Notfall-Defensiven bei kritisch niedriger Gesundheit\n\nSymbol erscheint mit grünem Leuchten. Verhalten außerhalb des Kampfes wird durch Umschalter 'Nur im Kampf' gesteuert."
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

    -- Hotkey Options
    L["Hotkey Options"] = "Options des raccourcis"
    L["Hotkey Font"] = "Police du raccourci"
    L["Font for hotkey text"] = "Police pour le texte des raccourcis"
    L["Hotkey Size"] = "Taille du raccourci"
    L["Size of hotkey text"] = "Taille du texte des raccourcis"
    L["Hotkey Color"] = "Couleur du raccourci"
    L["Color of hotkey text"] = "Couleur du texte des raccourcis"
    L["Parent Anchor"] = "Ancre parente"
    L["Anchor point of hotkey text relative to icon"] = "Point d'ancrage du texte des raccourcis par rapport à l'icône"
    L["Hotkey Anchor"] = "Ancre du raccourci"
    L["Which point on the hotkey text attaches to the anchor"] = "Quel point du texte du raccourci se fixe à l'ancre"
    L["First X Offset"] = "Décalage X initial"
    L["Horizontal offset for first icon hotkey text"] = "Décalage horizontal pour le texte du premier raccourci"
    L["First Y Offset"] = "Décalage Y initial"
    L["Vertical offset for first icon hotkey text"] = "Décalage vertical pour le texte du premier raccourci"
    L["Queue X Offset"] = "Décalage X en file"
    L["Horizontal offset for queued icons hotkey text"] = "Décalage horizontal pour le texte des raccourcis en file"
    L["Queue Y Offset"] = "Décalage Y en file"
    L["Vertical offset for queued icons hotkey text"] = "Décalage vertical pour le texte des raccourcis en file"
    L["Outline Mode"] = "Mode contour"
    L["Font outline and rendering flags for hotkey text"] = "Contours et options de rendu pour le texte des raccourcis"
    L["None"] = "Aucun"
    L["Outline"] = "Contour"
    L["Thick Outline"] = "Contour épais"
    L["Monochrome"] = "Monochrome"
    L["Outline + Monochrome"] = "Contour + Monochrome"
    L["Thick Outline + Monochrome"] = "Contour épais + Monochrome"

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
    L["Display Behavior"] = "Comportement d'affichage"
    L["Visual Effects"] = "Effets visuels"
    L["Threshold Settings"] = "Paramètres de seuil"

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
    L["Self-Heal Priority desc"] = "Soins rapides/absorptions à intégrer dans votre rotation. Le premier sort utilisable est suggéré."
    L["Restore Class Defaults"] = "Restaurer les valeurs par défaut de la classe"
    L["Major Cooldowns Priority List"] = "Liste de priorité des temps de recharge majeurs (urgence)"
    L["Major Cooldowns Priority desc"] = "Grands défensifs pour les urgences. Vérifié uniquement si aucun auto-soin n'est disponible et que la santé est critique."
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
    L["Hotkey Overrides Info"] = "Définir un texte de raccourci personnalisé pour les sorts lorsque la détection automatique échoue ou selon vos préférences.\n\n|cff00ff00Clic droit|r sur une icône de sort dans la file pour définir un raccourci personnalisé."
    L["Blacklist Info"] = "Masquer les sorts de la file de suggestions.\n\n|cffff6666Maj+Clic droit|r sur une icône de sort pour l'ajouter ou le retirer de la liste noire."
    L["Defensives Info"] = "Icône défensive position 0 avec priorité à deux niveaux:\n|cff00ff00• Auto-soins|r: Soins rapides affichés lorsque la santé tombe sous le seuil\n|cffff6666• Temps de recharge majeurs|r: Défensifs d'urgence lorsque critique\n\nL'icône apparaît avec une lueur verte. Le comportement hors combat est contrôlé par le bouton 'Seulement en combat'."
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

    -- Hotkey Options
    L["Hotkey Options"] = "Параметры клавиш"
    L["Hotkey Font"] = "Шрифт клавиши"
    L["Font for hotkey text"] = "Шрифт для текста клавиши"
    L["Hotkey Size"] = "Размер клавиши"
    L["Size of hotkey text"] = "Размер текста клавиши"
    L["Hotkey Color"] = "Цвет клавиши"
    L["Color of hotkey text"] = "Цвет текста клавиши"
    L["Parent Anchor"] = "Якорь родителя"
    L["Anchor point of hotkey text relative to icon"] = "Точка привязки текста клавиши относительно иконки"
    L["Hotkey Anchor"] = "Якорь клавиши"
    L["Which point on the hotkey text attaches to the anchor"] = "Какая точка текста клавиши привязывается к якорю"
    L["First X Offset"] = "Смещение X первой"
    L["Horizontal offset for first icon hotkey text"] = "Горизонтальное смещение текста первой клавиши"
    L["First Y Offset"] = "Смещение Y первой"
    L["Vertical offset for first icon hotkey text"] = "Вертикальное смещение текста первой клавиши"
    L["Queue X Offset"] = "Смещение X очереди"
    L["Horizontal offset for queued icons hotkey text"] = "Горизонтальное смещение текста клавиш в очереди"
    L["Queue Y Offset"] = "Смещение Y очереди"
    L["Vertical offset for queued icons hotkey text"] = "Вертикальное смещение текста клавиш в очереди"
    L["Outline Mode"] = "Режим контура"
    L["Font outline and rendering flags for hotkey text"] = "Контур и параметры рендеринга текста клавиши"
    L["None"] = "Нет"
    L["Outline"] = "Контур"
    L["Thick Outline"] = "Толстый контур"
    L["Monochrome"] = "Монохром"
    L["Outline + Monochrome"] = "Контур + Монохром"
    L["Thick Outline + Monochrome"] = "Толстый контур + Монохром"

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
    L["Display Behavior"] = "Поведение отображения"
    L["Visual Effects"] = "Визуальные эффекты"
    L["Threshold Settings"] = "Настройки порогов"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Максимальное количество иконок заклинаний в очереди (позиция 1 = основное, 2+ = очередь)"
    L["Icon Size desc"] = "Базовый размер иконок заклинаний в пикселях (больше = крупнее иконки)"
    L["Spacing desc"] = "Расстояние между иконками в пикселях (больше = больше промежуток)"
    L["UI Scale desc"] = "Множитель масштаба для всего интерфейса (0.5 = половина размера, 2.0 = двойной размер)"
    L["Primary Spell Scale desc"] = "Множитель масштаба для основных (позиция 1) и защитных (позиция 0) иконок"
    L["Queue Orientation desc"] = "Направление роста очереди заклинаний от основного заклинания"
    L["Highlight Primary Spell desc"] = "Показать анимированное свечение на основном заклинании (позиция 1)"
    L["Show Tooltips desc"] = "Показывать подсказки заклинаний при наведении"
    L["Tooltips in Combat desc"] = "Показывать подсказки во время боя (требуется Показывать подсказки)"
    L["Frame Opacity desc"] = "Общая прозрачность всей рамки, включая защитную иконку (1.0 = полностью видима, 0.0 = невидима)"
    L["Queue Icon Fade desc"] = "Обесцвечивание для иконок в позициях 2+ (0 = полный цвет, 1 = оттенки серого)"
    L["Hide Out of Combat desc"] = "Скрыть всю очередь заклинаний вне боя (не влияет на защитную иконку)"
    L["Insert Procced Abilities desc"] = "Сканировать книгу заклинаний на сработавшие (светящиеся) атакующие способности и показывать их в очереди. Полезно для способностей вроде 'Клинок Скверны', которые могут не появиться в ротации Blizzard."
    L["Include All Available Abilities desc"] = "Включить способности, скрытые за условиями макроса (например, [mod:shift]) в рекомендации. Включает стабилизацию для уменьшения мерцания. Отключите, если хотите только способности, видимые на панелях действий."
    L["Stabilization Window desc"] = "Как долго (в секундах) ждать перед изменением рекомендации основного заклинания. Большие значения уменьшают мерцание, но могут казаться менее отзывчивыми. Применяется только когда включено 'Включить скрытые способности'."
    L["Lock Panel desc"] = "Блокировать перетаскивание и контекстные меню (подсказки работают, если включены). Переключить правым кликом на ручке перемещения."
    L["Debug Mode desc"] = "Показывать подробную информацию аддона в чате для устранения неполадок"
    L["Enable Defensive Suggestions desc"] = "Показывать предложение защитного заклинания при низком здоровье"
    L["Self-Heal Threshold desc"] = "Показывать предложения самолечения, когда здоровье падает ниже этого процента (больше = срабатывает раньше)"
    L["Cooldown Threshold desc"] = "Показывать предложения больших перезарядок, когда здоровье падает ниже этого процента (больше = срабатывает раньше)"
    L["Only In Combat desc"] = "ВКЛ: Скрыто вне боя, показывать по порогам в бою.\nВЫКЛ: Всегда видимо вне боя (самолечение), по порогам в бою."
    L["Icon Position desc"] = "Где разместить защитную иконку относительно очереди заклинаний"
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
    L["Self-Heal Priority desc"] = "Быстрое исцеление/поглощение для вплетения в ротацию. Предлагается первое доступное заклинание."
    L["Restore Class Defaults"] = "Восстановить настройки класса"
    L["Major Cooldowns Priority List"] = "Список приоритетов больших перезарядок (экстренные)"
    L["Major Cooldowns Priority desc"] = "Большие защитные для экстренных случаев. Проверяется только если нет самолечения и здоровье критически низкое."
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
    L["Hotkey Overrides Info"] = "Установить пользовательский текст горячей клавиши для заклинаний при сбое автоопределения или по личному предпочтению.\n\n|cff00ff00Правый клик|r на иконку заклинания в очереди для установки пользовательской горячей клавиши."
    L["Blacklist Info"] = "Скрыть заклинания из очереди предложений.\n\n|cffff6666Shift+Правый клик|r на иконку заклинания для добавления или удаления из черного списка."
    L["Defensives Info"] = "Защитная иконка позиция 0 с двухуровневым приоритетом:\n|cff00ff00• Самолечение|r: Быстрое исцеление показывается при падении здоровья ниже порога\n|cffff6666• Большие перезарядки|r: Экстренная защита при критически низком здоровье\n\nИконка появляется с зеленым свечением. Поведение вне боя контролируется переключателем 'Только в бою'."
    L["Restore Class Defaults name"] = "Восстановить настройки класса"
end

-------------------------------------------------------------------------------
-- Spanish (esES) - Spain - ~5% of player base
-------------------------------------------------------------------------------
L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "esES")
if L then
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

    -- Hotkey Options
    L["Hotkey Options"] = "Opciones de tecla rápida"
    L["Hotkey Font"] = "Fuente de la tecla"
    L["Font for hotkey text"] = "Fuente para el texto de la tecla"
    L["Hotkey Size"] = "Tamaño de la tecla"
    L["Size of hotkey text"] = "Tamaño del texto de la tecla"
    L["Hotkey Color"] = "Color de la tecla"
    L["Color of hotkey text"] = "Color del texto de la tecla"
    L["Parent Anchor"] = "Ancla del padre"
    L["Anchor point of hotkey text relative to icon"] = "Punto de anclaje del texto respecto al icono"
    L["Hotkey Anchor"] = "Ancla de la tecla"
    L["Which point on the hotkey text attaches to the anchor"] = "Qué punto del texto se engancha al ancla"
    L["First X Offset"] = "Desplazamiento X inicial"
    L["Horizontal offset for first icon hotkey text"] = "Desplazamiento horizontal del primer texto de tecla"
    L["First Y Offset"] = "Desplazamiento Y inicial"
    L["Vertical offset for first icon hotkey text"] = "Desplazamiento vertical del primer texto de tecla"
    L["Queue X Offset"] = "Desplazamiento X en cola"
    L["Horizontal offset for queued icons hotkey text"] = "Desplazamiento horizontal del texto de teclas en cola"
    L["Queue Y Offset"] = "Desplazamiento Y en cola"
    L["Vertical offset for queued icons hotkey text"] = "Desplazamiento vertical del texto de teclas en cola"
    L["Outline Mode"] = "Modo de contorno"
    L["Font outline and rendering flags for hotkey text"] = "Contorno y opciones de renderizado del texto de la tecla"
    L["None"] = "Ninguno"
    L["Outline"] = "Contorno"
    L["Thick Outline"] = "Contorno grueso"
    L["Monochrome"] = "Monocromo"
    L["Outline + Monochrome"] = "Contorno + Monocromo"
    L["Thick Outline + Monochrome"] = "Contorno grueso + Monocromo"

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
    L["Display Behavior"] = "Comportamiento de visualización"
    L["Visual Effects"] = "Efectos visuales"
    L["Threshold Settings"] = "Configuración de umbrales"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Número máximo de iconos de hechizo en la cola (posición 1 = principal, 2+ = cola)"
    L["Icon Size desc"] = "Tamaño base de los iconos de hechizo en píxeles (mayor = iconos más grandes)"
    L["Spacing desc"] = "Espacio entre iconos en píxeles (mayor = más separación)"
    L["UI Scale desc"] = "Multiplicador de escala para toda la interfaz (0.5 = mitad de tamaño, 2.0 = doble tamaño)"
    L["Primary Spell Scale desc"] = "Multiplicador de escala para los iconos principales (posición 1) and defensivos (posición 0)"
    L["Queue Orientation desc"] = "Dirección en la que la cola de hechizos crece desde el hechizo principal"
    L["Highlight Primary Spell desc"] = "Mostrar brillo animado en el hechizo principal (posición 1)"
    L["Show Tooltips desc"] = "Mostrar información de hechizos al pasar el cursor"
    L["Tooltips in Combat desc"] = "Mostrar información durante el combate (requiere Mostrar información)"
    L["Frame Opacity desc"] = "Opacidad global para todo el marco incluyendo icono defensivo (1.0 = completamente visible, 0.0 = invisible)"
    L["Queue Icon Fade desc"] = "Desaturación para iconos en posiciones 2+ (0 = color completo, 1 = escala de grises)"
    L["Hide Out of Combat desc"] = "Ocultar toda la cola de hechizos fuera de combate (no afecta al icono defensivo)"
    L["Insert Procced Abilities desc"] = "Escanear grimorio en busca de habilidades ofensivas activadas (brillantes) y mostrarlas en la cola. Útil para habilidades como Hoja vil que pueden no aparecer en la lista de rotación de Blizzard."
    L["Include All Available Abilities desc"] = "Incluir habilidades ocultas detrás de condicionales de macro (p.ej., [mod:shift]) en recomendaciones. Habilita estabilización para reducir parpadeo. Desactivar si solo quieres habilidades directamente visibles en tus barras de acción."
    L["Stabilization Window desc"] = "Cuánto tiempo (en segundos) esperar antes de cambiar la recomendación de hechizo principal. Valores más altos reducen el parpadeo pero pueden sentirse menos receptivos. Solo aplica cuando 'Incluir habilidades ocultas' está habilitado."
    L["Lock Panel desc"] = "Bloquear arrastre y menús de clic derecho (la información sigue funcionando si está habilitada). Alternar mediante clic derecho en el asa de movimiento."
    L["Debug Mode desc"] = "Mostrar información detallada del addon en el chat para solución de problemas"
    L["Enable Defensive Suggestions desc"] = "Mostrar sugerencia de hechizo defensivo cuando la salud es baja"
    L["Self-Heal Threshold desc"] = "Mostrar sugerencias de autocuración cuando la salud cae por debajo de este porcentaje (mayor = se activa antes)"
    L["Cooldown Threshold desc"] = "Mostrar sugerencias de tiempo de reutilización mayor cuando la salud cae por debajo de este porcentaje (mayor = se activa antes)"
    L["Only In Combat desc"] = "ACTIVADO: Ocultar fuera de combate, mostrar según umbrales en combate.\nDESACTIVADO: Siempre visible fuera de combate (autocuraciones), basado en umbrales en combate."
    L["Icon Position desc"] = "Dónde colocar el icono defensivo en relación con la cola de hechizos"
    L["Custom Hotkey desc"] = "Texto a mostrar como atajo (p.ej., 'F1', 'Ctrl+Q', 'Ratón4')"
    L["Move up desc"] = "Subir en prioridad"
    L["Move down desc"] = "Bajar en prioridad"
    L["Add spell desc"] = "Introducir un ID de hechizo (p.ej., 48707) para agregar"
    L["Restore Class Defaults desc"] = "Restablecer la lista de autocuración a hechizos predeterminados para tu clase"
    L["Restore Cooldowns Defaults desc"] = "Restablecer la lista de tiempos de reutilización a hechizos predeterminados para tu clase"

    -- Additional sections
    L["Icon Position"] = "Posición del icono"
    L["Self-Heal Priority List"] = "Lista de prioridad de autocuración (comprobada primero)"
    L["Self-Heal Priority desc"] = "Curaciones rápidas/absorciones para entrelazar en tu rotación. Se sugiere el primer hechizo utilizable."
    L["Restore Class Defaults"] = "Restablecer valores predeterminados de clase"
    L["Major Cooldowns Priority List"] = "Lista de prioridad de tiempos de reutilización mayores (emergencia)"
    L["Major Cooldowns Priority desc"] = "Defensivos grandes para emergencias. Solo se comprueba si no hay autocuración disponible y la salud está críticamente baja."
    L["Profiles"] = "Perfiles"
    L["Profiles desc"] = "Gestión de perfiles de personaje y especialización"
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

    -- Hotkey Options
    L["Hotkey Options"] = "Opciones de tecla rápida"
    L["Hotkey Font"] = "Fuente de la tecla"
    L["Font for hotkey text"] = "Fuente para el texto de la tecla"
    L["Hotkey Size"] = "Tamaño de la tecla"
    L["Size of hotkey text"] = "Tamaño del texto de la tecla"
    L["Hotkey Color"] = "Color de la tecla"
    L["Color of hotkey text"] = "Color del texto de la tecla"
    L["Parent Anchor"] = "Ancla del padre"
    L["Anchor point of hotkey text relative to icon"] = "Punto de anclaje del texto respecto al icono"
    L["Hotkey Anchor"] = "Ancla de la tecla"
    L["Which point on the hotkey text attaches to the anchor"] = "Qué punto del texto se engancha al ancla"
    L["First X Offset"] = "Desplazamiento X inicial"
    L["Horizontal offset for first icon hotkey text"] = "Desplazamiento horizontal del primer texto de tecla"
    L["First Y Offset"] = "Desplazamiento Y inicial"
    L["Vertical offset for first icon hotkey text"] = "Desplazamiento vertical del primer texto de tecla"
    L["Queue X Offset"] = "Desplazamiento X en cola"
    L["Horizontal offset for queued icons hotkey text"] = "Desplazamiento horizontal del texto de teclas en cola"
    L["Queue Y Offset"] = "Desplazamiento Y en cola"
    L["Vertical offset for queued icons hotkey text"] = "Desplazamiento vertical del texto de teclas en cola"
    L["Outline Mode"] = "Modo de contorno"
    L["Font outline and rendering flags for hotkey text"] = "Contorno y opciones de renderizado del texto de la tecla"
    L["None"] = "Ninguno"
    L["Outline"] = "Contorno"
    L["Thick Outline"] = "Contorno grueso"
    L["Monochrome"] = "Monocromo"
    L["Outline + Monochrome"] = "Contorno + Monocromo"
    L["Thick Outline + Monochrome"] = "Contorno grueso + Monocromo"

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
    L["Display Behavior"] = "Comportamiento de visualización"
    L["Visual Effects"] = "Efectos visuales"
    L["Threshold Settings"] = "Configuración de umbrales"

    -- Detailed descriptions (same as esES)
    L["Max Icons desc"] = "Número máximo de iconos de hechizo en la cola (posición 1 = principal, 2+ = cola)"
    L["Icon Size desc"] = "Tamaño base de los iconos de hechizo en píxeles (mayor = iconos más grandes)"
    L["Spacing desc"] = "Espacio entre iconos en píxeles (mayor = más separación)"
    L["UI Scale desc"] = "Multiplicador de escala para toda la interfaz (0.5 = mitad de tamaño, 2.0 = doble tamaño)"
    L["Primary Spell Scale desc"] = "Multiplicador de escala para los iconos principales (posición 1) y defensivos (posición 0)"
    L["Queue Orientation desc"] = "Dirección en la que la cola de hechizos crece desde el hechizo principal"
    L["Highlight Primary Spell desc"] = "Mostrar brillo animado en el hechizo principal (posición 1)"
    L["Show Tooltips desc"] = "Mostrar información de hechizos al pasar el cursor"
    L["Tooltips in Combat desc"] = "Mostrar información durante el combate (requiere Mostrar información)"
    L["Frame Opacity desc"] = "Opacidad global para todo el marco incluyendo icono defensivo (1.0 = completamente visible, 0.0 = invisible)"
    L["Queue Icon Fade desc"] = "Desaturación para iconos en posiciones 2+ (0 = color completo, 1 = escala de grises)"
    L["Hide Out of Combat desc"] = "Ocultar toda la cola de hechizos fuera de combate (no afecta al icono defensivo)"
    L["Insert Procced Abilities desc"] = "Escanear grimorio en busca de habilidades ofensivas activadas (brillantes) y mostrarlas en la cola. Útil para habilidades como Hoja vil que pueden no aparecer en la lista de rotación de Blizzard."
    L["Include All Available Abilities desc"] = "Incluir habilidades ocultas detrás de condicionales de macro (p.ej., [mod:shift]) en recomendaciones. Habilita estabilización para reducir parpadeo. Desactivar si solo quieres habilidades directamente visibles en tus barras de acción."
    L["Stabilization Window desc"] = "Cuánto tiempo (en segundos) esperar antes de cambiar la recomendación de hechizo principal. Valores más altos reducen el parpadeo pero pueden sentirse menos receptivos. Solo aplica cuando 'Incluir habilidades ocultas' está habilitado."
    L["Lock Panel desc"] = "Bloquear arrastre y menús de clic derecho (la información sigue funcionando si está habilitada). Alternar mediante clic derecho en el asa de movimiento."
    L["Debug Mode desc"] = "Mostrar información detallada del addon en el chat para solución de problemas"
    L["Enable Defensive Suggestions desc"] = "Mostrar sugerencia de hechizo defensivo cuando la salud es baja"
    L["Self-Heal Threshold desc"] = "Mostrar sugerencias de autocuración cuando la salud cae por debajo de este porcentaje (mayor = se activa antes)"
    L["Cooldown Threshold desc"] = "Mostrar sugerencias de tiempo de reutilización mayor cuando la salud cae por debajo de este porcentaje (mayor = se activa antes)"
    L["Only In Combat desc"] = "ACTIVADO: Ocultar fuera de combate, mostrar según umbrales en combate.\nDESACTIVADO: Siempre visible fuera de combate (autocuraciones), basado en umbrales en combate."
    L["Icon Position desc"] = "Dónde colocar el icono defensivo en relación con la cola de hechizos"
    L["Custom Hotkey desc"] = "Texto a mostrar como atajo (p.ej., 'F1', 'Ctrl+Q', 'Ratón4')"
    L["Move up desc"] = "Subir en prioridad"
    L["Move down desc"] = "Bajar en prioridad"
    L["Add spell desc"] = "Introducir un ID de hechizo (p.ej., 48707) para agregar"
    L["Restore Class Defaults desc"] = "Restablecer la lista de autocuración a hechizos predeterminados para tu clase"
    L["Restore Cooldowns Defaults desc"] = "Restablecer la lista de tiempos de reutilización a hechizos predeterminados para tu clase"

    -- Additional sections
    L["Icon Position"] = "Posición del icono"
    L["Self-Heal Priority List"] = "Lista de prioridad de autocuración (comprobada primero)"
    L["Self-Heal Priority desc"] = "Curaciones rápidas/absorciones para entrelazar en tu rotación. Se sugiere el primer hechizo utilizable."
    L["Restore Class Defaults"] = "Restablecer valores predeterminados de clase"
    L["Major Cooldowns Priority List"] = "Lista de prioridad de tiempos de reutilización mayores (emergencia)"
    L["Major Cooldowns Priority desc"] = "Defensivos grandes para emergencias. Solo se comprueba si no hay autocuración disponible y la salud está críticamente baja."
    L["Profiles"] = "Perfiles"
    L["Profiles desc"] = "Gestión de perfiles de personaje y especialización"
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

    -- Hotkey Options
    L["Hotkey Options"] = "Opções de Atalho"
    L["Hotkey Font"] = "Fonte do Atalho"
    L["Font for hotkey text"] = "Fonte para o texto do atalho"
    L["Hotkey Size"] = "Tamanho do Atalho"
    L["Size of hotkey text"] = "Tamanho do texto do atalho"
    L["Hotkey Color"] = "Cor do Atalho"
    L["Color of hotkey text"] = "Cor do texto do atalho"
    L["Parent Anchor"] = "Âncora do Pai"
    L["Anchor point of hotkey text relative to icon"] = "Ponto de ancoragem do texto em relação ao ícone"
    L["Hotkey Anchor"] = "Âncora do Atalho"
    L["Which point on the hotkey text attaches to the anchor"] = "Qual ponto do texto do atalho se fixa à âncora"
    L["First X Offset"] = "Deslocamento X Inicial"
    L["Horizontal offset for first icon hotkey text"] = "Deslocamento horizontal para o texto do primeiro atalho"
    L["First Y Offset"] = "Deslocamento Y Inicial"
    L["Vertical offset for first icon hotkey text"] = "Deslocamento vertical para o texto do primeiro atalho"
    L["Queue X Offset"] = "Deslocamento X da Fila"
    L["Horizontal offset for queued icons hotkey text"] = "Deslocamento horizontal para o texto dos atalhos na fila"
    L["Queue Y Offset"] = "Deslocamento Y da Fila"
    L["Vertical offset for queued icons hotkey text"] = "Deslocamento vertical para o texto dos atalhos na fila"
    L["Outline Mode"] = "Modo de Contorno"
    L["Font outline and rendering flags for hotkey text"] = "Contorno e opções de renderização para o texto do atalho"
    L["None"] = "Nenhum"
    L["Outline"] = "Contorno"
    L["Thick Outline"] = "Contorno Grosso"
    L["Monochrome"] = "Monocromático"
    L["Outline + Monochrome"] = "Contorno + Monocromático"
    L["Thick Outline + Monochrome"] = "Contorno Grosso + Monocromático"

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
    L["Display Behavior"] = "Comportamento de exibição"
    L["Visual Effects"] = "Efeitos visuais"
    L["Threshold Settings"] = "Configurações de limite"

    -- Detailed descriptions
    L["Max Icons desc"] = "Número máximo de ícones de magia na fila (posição 1 = principal, 2+ = fila)"
    L["Icon Size desc"] = "Tamanho base dos ícones de magia em pixels (maior = ícones maiores)"
    L["Spacing desc"] = "Espaço entre ícones em pixels (maior = mais espaçamento)"
    L["Primary Spell Scale desc"] = "Multiplicador de escala para os ícones principais (posição 1) e defensivos (posição 0)"
    L["Queue Orientation desc"] = "Direção em que a fila de magias cresce a partir da magia principal"
    L["Highlight Primary Spell desc"] = "Mostrar brilho animado na magia principal (posição 1)"
    L["Show Tooltips desc"] = "Mostrar dicas de magias ao passar o cursor"
    L["Tooltips in Combat desc"] = "Mostrar dicas durante o combate (requer Mostrar dicas)"
    L["Frame Opacity desc"] = "Opacidade global para todo o quadro incluindo ícone defensivo (1.0 = completamente visível, 0.0 = invisível)"
    L["Queue Icon Fade desc"] = "Dessaturação para ícones nas posições 2+ (0 = cor completa, 1 = escala de cinza)"
    L["Hide Out of Combat desc"] = "Ocultar toda a fila de magias fora de combate (não afeta o ícone defensivo)"
    L["Insert Procced Abilities desc"] = "Escanear grimório em busca de habilidades ofensivas ativadas (brilhantes) e mostrá-las na fila. Útil para habilidades como Lâmina Vil que podem não aparecer na lista de rotação da Blizzard."
    L["Include All Available Abilities desc"] = "Incluir habilidades ocultas atrás de condicionais de macro (ex: [mod:shift]) nas recomendações. Ativa estabilização para reduzir oscilação. Desative se quiser apenas habilidades diretamente visíveis nas suas barras de ação."
    L["Stabilization Window desc"] = "Quanto tempo (em segundos) esperar antes de mudar a recomendação de magia principal. Valores mais altos reduzem a oscilação mas podem parecer menos responsivos. Aplica-se apenas quando 'Incluir habilidades ocultas' está ativado."
    L["Lock Panel desc"] = "Bloquear arrasto e menus de clique direito (as dicas ainda funcionam se ativadas). Alternar via clique direito na alça de movimento."
    L["Debug Mode desc"] = "Mostrar informações detalhadas do addon no chat para solução de problemas"
    L["Enable Defensive Suggestions desc"] = "Mostrar sugestão de magia defensiva quando a vida está baixa"
    L["Self-Heal Threshold desc"] = "Mostrar sugestões de autocura quando a vida cai abaixo desta porcentagem (maior = ativa mais cedo)"
    L["Cooldown Threshold desc"] = "Mostrar sugestões de recarga maior quando a vida cai abaixo desta porcentagem (maior = ativa mais cedo)"
    L["Only In Combat desc"] = "ATIVADO: Ocultar fora de combate, mostrar com base nos limites em combate.\nDESATIVADO: Sempre visível fora de combate (autocuras), baseado em limites em combate."
    L["Icon Position desc"] = "Onde colocar o ícone defensivo em relação à fila de magias"
    L["Custom Hotkey desc"] = "Texto a ser exibido como atalho (ex: 'F1', 'Ctrl+Q', 'Mouse4')"
    L["Move up desc"] = "Subir na prioridade"
    L["Move down desc"] = "Descer na prioridade"
    L["Add spell desc"] = "Digite um ID de magia (ex: 48707) para adicionar"
    L["Add"] = "Adicionar"
    L["Restore Class Defaults desc"] = "Redefinir a lista de autocura para magias padrão da sua classe"
    L["Restore Cooldowns Defaults desc"] = "Redefinir a lista de recargas para magias padrão da sua classe"

    -- Additional sections
    L["Icon Position"] = "Posição do ícone"
    L["Self-Heal Priority List"] = "Lista de prioridade de autocura (verificada primeiro)"
    L["Self-Heal Priority desc"] = "Curas rápidas/absorções para intercalar na sua rotação. A primeira magia utilizável é sugerida."
    L["Restore Class Defaults"] = "Restaurar padrões da classe"
    L["Major Cooldowns Priority List"] = "Lista de prioridade de recargas maiores (emergência)"
    L["Major Cooldowns Priority desc"] = "Defensivos grandes para emergências. Verificado apenas se não houver autocura disponível e a vida estiver criticamente baixa."
    L["Profiles"] = "Perfis"
    L["Profiles desc"] = "Gerenciamento de perfis de personagem e especialização"
    L["About"] = "Sobre"
    L["About JustAssistedCombat"] = "Sobre JustAssistedCombat"

    -- Orientation values (full names)
    L["Left to Right"] = "Esquerda para direita"
    L["Right to Left"] = "Direita para esquerda"
    L["Bottom to Top"] = "Baixo para cima"
    L["Top to Bottom"] = "Cima para baixo"

    -- Slash commands help
    L["Slash Commands"] = "|cffffff00Comandos:|r\n|cff88ff88/jac|r - Abrir opções\n|cff88ff88/jac toggle|r - Pausar/retomar\n|cff88ff88/jac debug|r - Alternar modo de depuração\n|cff88ff88/jac test|r - Testar API Blizzard\n|cff88ff88/jac formcheck|r - Verificar detecção de forma\n|cff88ff88/jac find <magia>|r - Localizar magia\n|cff88ff88/jac reset|r - Redefinir posição\n\nDigite |cff88ff88/jac help|r para a lista completa de comandos"

    -- About text
    L["About Text"] = "Aprimora o sistema de Combate Assistido do WoW com recursos avançados para uma melhor experiência de jogo.\n\n|cffffff00Recursos principais:|r\n• Detecção inteligente de atalhos com personalização\n• Análise avançada de macros com modificadores condicionais\n• Filtragem inteligente de magias e gerenciamento de lista negra\n• Feedback visual e dicas aprimoradas\n• Integração perfeita com destaques nativos da Blizzard\n• Zero impacto nos tempos de recarga globais\n\n|cffffff00Como funciona:|r\nJustAC detecta automaticamente sua configuração de barra de ação e exibe a rotação recomendada com os atalhos corretos. Quando a detecção automática falha, você pode definir exibições de atalhos personalizados via clique direito.\n\n|cffffff00Melhorias opcionais:|r\n|cffffffff/console assistedMode 1|r - Ativa o sistema de combate assistido da Blizzard\n|cffffffff/console assistedCombatHighlight 1|r - Adiciona destaque nativo de botões\n\nEstes comandos de console melhoram a experiência mas não são necessários para o funcionamento do JustAC."

    -- Additional UI strings
    L["Hotkey Overrides Info"] = "Definir texto de atalho personalizado para magias quando a detecção automática falha ou por preferência pessoal.\n\n|cff00ff00Clique direito|r em um ícone de magia na fila para definir um atalho personalizado."
    L["Blacklist Info"] = "Ocultar magias da fila de sugestões.\n\n|cffff6666Shift+Clique direito|r em um ícone de magia para adicioná-lo ou removê-lo da lista negra."
    L["Defensives Info"] = "Ícone defensivo posição 0 com prioridade de dois níveis:\n|cff00ff00• Autocuras|r: Curas rápidas mostradas quando a vida cai abaixo do limite\n|cffff6666• Recargas maiores|r: Defensivos de emergência quando criticamente baixo\n\nO ícone aparece com um brilho verde. O comportamento fora de combate é controlado pelo botão 'Apenas em combate'."
    L["Restore Class Defaults name"] = "Restaurar padrões da classe"
end
