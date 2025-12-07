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
L["Hotkey Overrides"] = "Hotkey Overrides"

-- General Options
L["Max Icons"] = "Max Icons"
L["Icon Size"] = "Icon Size"
L["Spacing"] = "Spacing"
L["Primary Spell Scale"] = "Primary Spell Scale"
L["Queue Orientation"] = "Queue Orientation"
L["Lock Panel"] = "Lock Panel"
L["Debug Mode"] = "Debug Mode"
L["Frame Opacity"] = "Frame Opacity"
L["Queue Icon Fade"] = "Queue Icon Fade"
L["Hide Queue Out of Combat"] = "Hide Queue Out of Combat"
L["Show All Procced Abilities"] = "Show All Procced Abilities"
L["Include Hidden Abilities"] = "Include Hidden Abilities"
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

-- Hotkey Overrides
L["Custom Hotkey"] = "Custom Hotkey"
L["No custom hotkeys set"] = "No custom hotkeys set. Right-click a spell in the queue to set a custom hotkey display."
L["Custom Hotkey Displays"] = "Custom Hotkey Displays"
L["Hotkey override description"] = "Set custom hotkey text for spells when automatic detection fails or for personal preference.\n\n|cff00ff00Right-click|r a spell icon in the queue to set a custom hotkey.\n|cffff6666Shift+Right-click|r to blacklist a spell."

-- Defensives
L["Enable Defensive Suggestions"] = "Enable Defensive Suggestions"
L["Self-Heal Threshold"] = "Self-Heal Threshold"
L["Cooldown Threshold"] = "Cooldown Threshold"
L["Only In Combat"] = "Only In Combat"
L["Defensive Self-Heals"] = "Defensive Self-Heals"
L["Defensive Cooldowns"] = "Defensive Cooldowns"
L["Defensive description"] = "Position 0 defensive icon with two-tier priority:\n|cff00ff00• Self-Heals|r: Quick heals shown when health drops below threshold\n|cffff6666• Major Cooldowns|r: Emergency defensives when critically low\n\nIcon appears with a green glow. Out of combat behavior is controlled by 'Only In Combat' toggle."
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
L["Primary Spell Scale desc"] = "Scale multiplier for the primary (position 1) and defensive (position 0) icons"
L["Queue Orientation desc"] = "Direction the spell queue grows from the primary spell"
L["Highlight Primary Spell desc"] = "Show animated glow on the primary spell (position 1)"
L["Show Tooltips desc"] = "Display spell tooltips on hover"
L["Tooltips in Combat desc"] = "Show tooltips during combat (requires Show Tooltips)"
L["Frame Opacity desc"] = "Global opacity for the entire frame including defensive icon (1.0 = fully visible, 0.0 = invisible)"
L["Queue Icon Fade desc"] = "Desaturation for icons in positions 2+ (0 = full color, 1 = grayscale)"
L["Hide Queue Out of Combat desc"] = "Hide the entire spell queue when not in combat (does not affect defensive icon)"
L["Show All Procced Abilities desc"] = "Scan spellbook for procced (glowing) offensive abilities and show them in the queue. Useful for abilities like Fel Blade that may not appear in Blizzard's rotation list."
L["Include Hidden Abilities desc"] = "Include abilities hidden behind macro conditionals (e.g., [mod:shift]) in recommendations. Enables stabilization to reduce flickering. Disable if you only want abilities directly visible on your action bars."
L["Stabilization Window desc"] = "How long (in seconds) to wait before changing the primary spell recommendation. Higher values reduce flickering but may feel less responsive. Only applies when 'Include Hidden Abilities' is enabled."
L["Lock Panel desc"] = "Block dragging and right-click menus (tooltips still work if enabled). Toggle via right-click on move handle."
L["Debug Mode desc"] = "Show detailed addon information in chat for troubleshooting"
L["Enable Defensive Suggestions desc"] = "Show a defensive spell suggestion when health is low"
L["Self-Heal Threshold desc"] = "Show self-heal suggestions when health falls below this percentage (higher = triggers sooner)"
L["Cooldown Threshold desc"] = "Show major cooldown suggestions when health falls below this percentage (higher = triggers sooner)"
L["Only In Combat desc"] = "ON: Hide out of combat, show based on thresholds in combat.\nOFF: Always visible out of combat (self-heals), threshold-based in combat."
L["Icon Position desc"] = "Where to place the defensive icon relative to the spell queue"
L["Custom Hotkey desc"] = "Text to display as hotkey (e.g., 'F1', 'Ctrl+Q', 'Mouse4')"
L["Move up desc"] = "Move up in priority"
L["Move down desc"] = "Move down in priority"
L["Add spell desc"] = "Enter a spell ID (e.g., 48707) to add"
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
L["Hotkey Overrides"] = "Hotkey Overrides"
L["Hotkey Overrides Info"] = "Set custom hotkey text for spells when automatic detection fails or for personal preference.\n\n|cff00ff00Right-click|r a spell icon in the queue to set a custom hotkey.\n|cffff6666Shift+Right-click|r to blacklist a spell."
L["Custom Hotkey Displays"] = "Custom Hotkey Displays"
L["Blacklist"] = "Blacklist"
L["Blacklist Info"] = "Shift+Right-click a spell icon in the queue to add it to this list. You can then customize where it should be hidden."
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
    L["Hotkey Overrides"] = "Tastenbelegung"

    -- General Options
    L["Max Icons"] = "Max. Symbole"
    L["Icon Size"] = "Symbolgröße"
    L["Spacing"] = "Abstand"
    L["Primary Spell Scale"] = "Hauptzauber-Skalierung"
    L["Queue Orientation"] = "Warteschlangen-Ausrichtung"
    L["Lock Panel"] = "Panel sperren"
    L["Debug Mode"] = "Debug-Modus"
    L["Frame Opacity"] = "Rahmen-Transparenz"
    L["Queue Icon Fade"] = "Warteschlangen-Symbol ausblenden"
    L["Hide Queue Out of Combat"] = "Warteschlange außerhalb des Kampfes ausblenden"
    L["Show All Procced Abilities"] = "Alle ausgelösten Fähigkeiten anzeigen"
    L["Include Hidden Abilities"] = "Versteckte Fähigkeiten einbeziehen"
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
    L["Display Behavior"] = "Anzeigeverhalten"
    L["Visual Effects"] = "Visuelle Effekte"
    L["Threshold Settings"] = "Schwellenwert-Einstellungen"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Maximale Anzahl von Zaubersymbolen in der Warteschlange (Position 1 = Hauptzauber, 2+ = Warteschlange)"
    L["Icon Size desc"] = "Basisgröße der Zaubersymbole in Pixeln (höher = größere Symbole)"
    L["Spacing desc"] = "Abstand zwischen Symbolen in Pixeln (höher = mehr Abstand)"
    L["Primary Spell Scale desc"] = "Skalierungsfaktor für die primären (Position 1) und defensiven (Position 0) Symbole"
    L["Queue Orientation desc"] = "Richtung, in die die Zauber-Warteschlange vom Hauptzauber aus wächst"
    L["Highlight Primary Spell desc"] = "Animiertes Leuchten auf dem Hauptzauber anzeigen (Position 1)"
    L["Show Tooltips desc"] = "Zauber-Tooltips beim Überfahren anzeigen"
    L["Tooltips in Combat desc"] = "Tooltips während des Kampfes anzeigen (erfordert Tooltips anzeigen)"
    L["Frame Opacity desc"] = "Globale Transparenz für den gesamten Rahmen einschließlich defensivem Symbol (1.0 = vollständig sichtbar, 0.0 = unsichtbar)"
    L["Queue Icon Fade desc"] = "Entsättigung für Symbole in Position 2+ (0 = volle Farbe, 1 = Graustufen)"
    L["Hide Queue Out of Combat desc"] = "Die gesamte Zauber-Warteschlange außerhalb des Kampfes ausblenden (betrifft nicht defensives Symbol)"
    L["Show All Procced Abilities desc"] = "Zauberbuch nach ausgelösten (leuchtenden) offensiven Fähigkeiten durchsuchen und in der Warteschlange anzeigen. Nützlich für Fähigkeiten wie 'Teufelsklinge', die möglicherweise nicht in Blizzards Rotationsliste erscheinen."
    L["Include Hidden Abilities desc"] = "Fähigkeiten einbeziehen, die hinter Makro-Bedingungen versteckt sind (z.B. [mod:shift]). Ermöglicht Stabilisierung zur Reduzierung von Flackern. Deaktivieren, wenn nur direkt sichtbare Fähigkeiten auf Ihren Aktionsleisten gewünscht werden."
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
    L["Hotkey Overrides Info"] = "Benutzerdefinierten Tastentext für Zauber festlegen, wenn die automatische Erkennung fehlschlägt oder nach persönlicher Präferenz.\n\n|cff00ff00Rechtsklick|r auf ein Zauber-Symbol in der Warteschlange, um einen benutzerdefinierten Hotkey festzulegen.\n|cffff6666Umschalt+Rechtsklick|r zum Sperren eines Zaubers."
    L["Blacklist Info"] = "Umschalt+Rechtsklick auf ein Zauber-Symbol in der Warteschlange, um es zu dieser Liste hinzuzufügen. Sie können dann anpassen, wo es ausgeblendet werden soll."
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
    L["Hotkey Overrides"] = "Raccourcis personnalisés"

    -- General Options
    L["Max Icons"] = "Icônes max"
    L["Icon Size"] = "Taille des icônes"
    L["Spacing"] = "Espacement"
    L["Primary Spell Scale"] = "Échelle du sort principal"
    L["Queue Orientation"] = "Orientation de la file"
    L["Lock Panel"] = "Verrouiller le panneau"
    L["Debug Mode"] = "Mode débogage"
    L["Frame Opacity"] = "Opacité du cadre"
    L["Queue Icon Fade"] = "Fondu des icônes de file"
    L["Hide Queue Out of Combat"] = "Masquer la file hors combat"
    L["Show All Procced Abilities"] = "Afficher toutes les capacités déclenchées"
    L["Include Hidden Abilities"] = "Inclure les capacités cachées"
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
    L["Display Behavior"] = "Comportement d'affichage"
    L["Visual Effects"] = "Effets visuels"
    L["Threshold Settings"] = "Paramètres de seuil"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Nombre maximum d'icônes de sort dans la file (position 1 = sort principal, 2+ = file d'attente)"
    L["Icon Size desc"] = "Taille de base des icônes de sort en pixels (plus élevé = icônes plus grandes)"
    L["Spacing desc"] = "Espace entre les icônes en pixels (plus élevé = plus d'espacement)"
    L["Primary Spell Scale desc"] = "Multiplicateur d'échelle pour les icônes principales (position 1) et défensives (position 0)"
    L["Queue Orientation desc"] = "Direction dans laquelle la file de sorts s'étend à partir du sort principal"
    L["Highlight Primary Spell desc"] = "Afficher une lueur animée sur le sort principal (position 1)"
    L["Show Tooltips desc"] = "Afficher les infobulles de sort au survol"
    L["Tooltips in Combat desc"] = "Afficher les infobulles pendant le combat (nécessite Afficher les infobulles)"
    L["Frame Opacity desc"] = "Opacité globale pour l'ensemble du cadre, y compris l'icône défensive (1.0 = complètement visible, 0.0 = invisible)"
    L["Queue Icon Fade desc"] = "Désaturation pour les icônes en positions 2+ (0 = couleur complète, 1 = niveaux de gris)"
    L["Hide Queue Out of Combat desc"] = "Masquer toute la file de sorts hors combat (n'affecte pas l'icône défensive)"
    L["Show All Procced Abilities desc"] = "Scanner le grimoire pour les capacités offensives déclenchées (lumineuses) et les afficher dans la file. Utile pour les capacités comme 'Lame gangrenée' qui peuvent ne pas apparaître dans la liste de rotation de Blizzard."
    L["Include Hidden Abilities desc"] = "Inclure les capacités cachées derrière des conditions de macro (par ex. [mod:shift]) dans les recommandations. Active la stabilisation pour réduire le scintillement. Désactiver si vous voulez uniquement les capacités directement visibles sur vos barres d'action."
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
    L["Hotkey Overrides Info"] = "Définir un texte de raccourci personnalisé pour les sorts lorsque la détection automatique échoue ou selon vos préférences.\n\n|cff00ff00Clic droit|r sur une icône de sort dans la file pour définir un raccourci personnalisé.\n|cffff6666Maj+Clic droit|r pour ajouter à la liste noire."
    L["Blacklist Info"] = "Maj+Clic droit sur une icône de sort dans la file pour l'ajouter à cette liste. Vous pouvez ensuite personnaliser où il doit être masqué."
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

    -- General Options
    L["Max Icons"] = "Макс. иконок"
    L["Icon Size"] = "Размер иконок"
    L["Spacing"] = "Расстояние"
    L["Primary Spell Scale"] = "Масштаб главного заклинания"
    L["Queue Orientation"] = "Ориентация очереди"
    L["Lock Panel"] = "Заблокировать панель"
    L["Debug Mode"] = "Режим отладки"
    L["Frame Opacity"] = "Прозрачность рамки"
    L["Queue Icon Fade"] = "Затухание иконок очереди"
    L["Hide Queue Out of Combat"] = "Скрыть очередь вне боя"
    L["Show All Procced Abilities"] = "Показать все сработавшие способности"
    L["Include Hidden Abilities"] = "Включить скрытые способности"
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
    L["Display Behavior"] = "Поведение отображения"
    L["Visual Effects"] = "Визуальные эффекты"
    L["Threshold Settings"] = "Настройки порогов"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Максимальное количество иконок заклинаний в очереди (позиция 1 = основное, 2+ = очередь)"
    L["Icon Size desc"] = "Базовый размер иконок заклинаний в пикселях (больше = крупнее иконки)"
    L["Spacing desc"] = "Расстояние между иконками в пикселях (больше = больше промежуток)"
    L["Primary Spell Scale desc"] = "Множитель масштаба для основных (позиция 1) и защитных (позиция 0) иконок"
    L["Queue Orientation desc"] = "Направление роста очереди заклинаний от основного заклинания"
    L["Highlight Primary Spell desc"] = "Показать анимированное свечение на основном заклинании (позиция 1)"
    L["Show Tooltips desc"] = "Показывать подсказки заклинаний при наведении"
    L["Tooltips in Combat desc"] = "Показывать подсказки во время боя (требуется Показывать подсказки)"
    L["Frame Opacity desc"] = "Общая прозрачность всей рамки, включая защитную иконку (1.0 = полностью видима, 0.0 = невидима)"
    L["Queue Icon Fade desc"] = "Обесцвечивание для иконок в позициях 2+ (0 = полный цвет, 1 = оттенки серого)"
    L["Hide Queue Out of Combat desc"] = "Скрыть всю очередь заклинаний вне боя (не влияет на защитную иконку)"
    L["Show All Procced Abilities desc"] = "Сканировать книгу заклинаний на сработавшие (светящиеся) атакующие способности и показывать их в очереди. Полезно для способностей вроде 'Клинок Скверны', которые могут не появиться в ротации Blizzard."
    L["Include Hidden Abilities desc"] = "Включить способности, скрытые за условиями макроса (например, [mod:shift]) в рекомендации. Включает стабилизацию для уменьшения мерцания. Отключите, если хотите только способности, видимые на панелях действий."
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
    L["Hotkey Overrides Info"] = "Установить пользовательский текст горячей клавиши для заклинаний при сбое автоопределения или по личному предпочтению.\n\n|cff00ff00Правый клик|r на иконку заклинания в очереди для установки пользовательской горячей клавиши.\n|cffff6666Shift+Правый клик|r для добавления в черный список."
    L["Blacklist Info"] = "Shift+Правый клик на иконку заклинания в очереди для добавления в этот список. Затем вы можете настроить, где оно должно быть скрыто."
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
    L["Hotkey Overrides"] = "Atajos personalizados"

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
    L["Hide Queue Out of Combat"] = "Ocultar cola fuera de combate"
    L["Show All Procced Abilities"] = "Mostrar todas las habilidades activadas"
    L["Include Hidden Abilities"] = "Incluir habilidades ocultas"
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
    L["Display Behavior"] = "Comportamiento de visualización"
    L["Visual Effects"] = "Efectos visuales"
    L["Threshold Settings"] = "Configuración de umbrales"

    -- Detailed descriptions (new)
    L["Max Icons desc"] = "Número máximo de iconos de hechizo en la cola (posición 1 = principal, 2+ = cola)"
    L["Icon Size desc"] = "Tamaño base de los iconos de hechizo en píxeles (mayor = iconos más grandes)"
    L["Spacing desc"] = "Espacio entre iconos en píxeles (mayor = más separación)"
    L["Primary Spell Scale desc"] = "Multiplicador de escala para los iconos principales (posición 1) and defensivos (posición 0)"
    L["Queue Orientation desc"] = "Dirección en la que la cola de hechizos crece desde el hechizo principal"
    L["Highlight Primary Spell desc"] = "Mostrar brillo animado en el hechizo principal (posición 1)"
    L["Show Tooltips desc"] = "Mostrar información de hechizos al pasar el cursor"
    L["Tooltips in Combat desc"] = "Mostrar información durante el combate (requiere Mostrar información)"
    L["Frame Opacity desc"] = "Opacidad global para todo el marco incluyendo icono defensivo (1.0 = completamente visible, 0.0 = invisible)"
    L["Queue Icon Fade desc"] = "Desaturación para iconos en posiciones 2+ (0 = color completo, 1 = escala de grises)"
    L["Hide Queue Out of Combat desc"] = "Ocultar toda la cola de hechizos fuera de combate (no afecta al icono defensivo)"
    L["Show All Procced Abilities desc"] = "Escanear grimorio en busca de habilidades ofensivas activadas (brillantes) y mostrarlas en la cola. Útil para habilidades como Hoja vil que pueden no aparecer en la lista de rotación de Blizzard."
    L["Include Hidden Abilities desc"] = "Incluir habilidades ocultas detrás de condicionales de macro (p.ej., [mod:shift]) en recomendaciones. Habilita estabilización para reducir parpadeo. Desactivar si solo quieres habilidades directamente visibles en tus barras de acción."
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
    L["Hotkey Overrides Info"] = "Establecer texto de atajo personalizado para hechizos cuando la detección automática falla o por preferencia personal.\n\n|cff00ff00Clic derecho|r en un icono de hechizo en la cola para establecer un atajo personalizado.\n|cffff6666Shift+Clic derecho|r para agregar a lista negra."
    L["Blacklist Info"] = "Shift+Clic derecho en un icono de hechizo en la cola para agregarlo a esta lista. Luego puedes personalizar dónde debe ocultarse."
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
    L["Hotkey Overrides"] = "Atajos personalizados"

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
    L["Hide Queue Out of Combat"] = "Ocultar cola fuera de combate"
    L["Show All Procced Abilities"] = "Mostrar todas las habilidades activadas"
    L["Include Hidden Abilities"] = "Incluir habilidades ocultas"
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
    L["Display Behavior"] = "Comportamiento de visualización"
    L["Visual Effects"] = "Efectos visuales"
    L["Threshold Settings"] = "Configuración de umbrales"

    -- Detailed descriptions (same as esES)
    L["Max Icons desc"] = "Número máximo de iconos de hechizo en la cola (posición 1 = principal, 2+ = cola)"
    L["Icon Size desc"] = "Tamaño base de los iconos de hechizo en píxeles (mayor = iconos más grandes)"
    L["Spacing desc"] = "Espacio entre iconos en píxeles (mayor = más separación)"
    L["Primary Spell Scale desc"] = "Multiplicador de escala para los iconos principales (posición 1) y defensivos (posición 0)"
    L["Queue Orientation desc"] = "Dirección en la que la cola de hechizos crece desde el hechizo principal"
    L["Highlight Primary Spell desc"] = "Mostrar brillo animado en el hechizo principal (posición 1)"
    L["Show Tooltips desc"] = "Mostrar información de hechizos al pasar el cursor"
    L["Tooltips in Combat desc"] = "Mostrar información durante el combate (requiere Mostrar información)"
    L["Frame Opacity desc"] = "Opacidad global para todo el marco incluyendo icono defensivo (1.0 = completamente visible, 0.0 = invisible)"
    L["Queue Icon Fade desc"] = "Desaturación para iconos en posiciones 2+ (0 = color completo, 1 = escala de grises)"
    L["Hide Queue Out of Combat desc"] = "Ocultar toda la cola de hechizos fuera de combate (no afecta al icono defensivo)"
    L["Show All Procced Abilities desc"] = "Escanear grimorio en busca de habilidades ofensivas activadas (brillantes) y mostrarlas en la cola. Útil para habilidades como Hoja vil que pueden no aparecer en la lista de rotación de Blizzard."
    L["Include Hidden Abilities desc"] = "Incluir habilidades ocultas detrás de condicionales de macro (p.ej., [mod:shift]) en recomendaciones. Habilita estabilización para reducir parpadeo. Desactivar si solo quieres habilidades directamente visibles en tus barras de acción."
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
    L["Hotkey Overrides Info"] = "Establecer texto de atajo personalizado para hechizos cuando la detección automática falla o por preferencia personal.\n\n|cff00ff00Clic derecho|r en un icono de hechizo en la cola para establecer un atajo personalizado.\n|cffff6666Shift+Clic derecho|r para agregar a lista negra."
    L["Blacklist Info"] = "Shift+Clic derecho en un icono de hechizo en la cola para agregarlo a esta lista. Luego puedes personalizar dónde debe ocultarse."
    L["Defensives Info"] = "Icono defensivo posición 0 con prioridad de dos niveles:\n|cff00ff00• Autocuraciones|r: Curaciones rápidas mostradas cuando la salud cae bajo el umbral\n|cffff6666• Tiempos de reutilización mayores|r: Defensivos de emergencia cuando críticamente bajo\n\nEl icono aparece con un brillo verde. El comportamiento fuera de combate está controlado por el interruptor 'Solo en combate'."
    L["Restore Class Defaults name"] = "Restablecer valores predeterminados de clase"
end
