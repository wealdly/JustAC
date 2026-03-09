-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: German (deDE) - 8.8% of player base

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "deDE")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "Allgemein"
L["Settings"] = "Einstellungen"
L["Offensive"] = "Offensivfähigkeiten"
L["Defensives"] = "Verteidigungsfähigkeiten"
L["Blacklist"] = "Sperrliste"
L["Hotkey Overrides"] = "Hotkeys"
L["Add"] = "Hinzufügen"
L["Clear All"] = "Alle löschen"
L["Clear All Blacklist desc"] = "Alle Zauber von der Sperrliste entfernen"
L["Clear All Hotkeys desc"] = "Alle benutzerdefinierten Hotkeys entfernen"

-- General Options
L["Max Icons"] = "Max. Symbole"
L["Icon Size"] = "Symbolgröße"
L["Spacing"] = "Abstand"
L["Primary Spell Scale"] = "Hauptzauber-Skalierung"
L["Queue Orientation"] = "Warteschlangen-Layout"
L["Gamepad Icon Style"] = "Gamepad-Symbolstil"
L["Gamepad Icon Style desc"] = "Wähle den Tastensymbolstil für Gamepad-/Controller-Tastenbelegungen."
L["Input Preference"] = "Eingabemethode"
L["Input Preference desc"] = "Wähle, welche Tastenbelegung angezeigt wird. Automatisch zeigt Controller-Belegungen wenn ein Gamepad verbunden ist, sonst Tastatur."
L["Auto-Detect"] = "Automatisch"
L["Keyboard"] = "Tastatur"
L["Gamepad"] = "Gamepad"
L["Generic"] = "Generisch (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Kreuz/Kreis/Quadrat/Dreieck)"
L["Insert Procced Defensives"] = "Ausgelöste Defensiven einfügen"
L["Insert Procced Defensives desc"] = "Ausgelöste Defensivfähigkeiten (Siegesrausch, kostenlose Heilungen) bei jeder Gesundheitsstufe anzeigen."
L["Frame Opacity"] = "Rahmen-Transparenz"
L["Queue Icon Fade"] = "Warteschlangen-Symbol ausblenden"
L["Insert Procced Abilities"] = "Ausgelöste Fähigkeiten einfügen"
L["Include All Available Abilities"] = "Versteckte Fähigkeiten einbeziehen"
L["Highlight Mode"] = "Hervorhebungsmodus"
L["All Glows"] = "Alle Leuchteffekte"
L["Primary Only"] = "Nur Primär"
L["Proc Only"] = "Nur Proc"
L["No Glows"] = "Keine Leuchteffekte"
L["Show Key Press Flash"] = "Tastendruck-Blitz"
L["Show Key Press Flash desc"] = "Symbol beim Drücken der zugehörigen Taste aufblitzen lassen."
L["Grey Out While Casting"] = "Beim Wirken ausgrauen"
L["Grey Out While Casting desc"] = "Warteschlangen-Symbole beim Wirken entsättigen. Der gewirkte Zauber bleibt farbig."
L["Grey Out While Channeling"] = "Beim Kanalisieren ausgrauen"
L["Grey Out While Channeling desc"] = "Warteschlangen-Symbole beim Kanalisieren entsättigen. Der kanalisierte Zauber bleibt farbig mit einer Füllanimation."

-- Blacklist
L["Remove"] = "Entfernen"
L["No spells currently blacklisted"] = "Keine Zauber gesperrt. Umschalt+Rechtsklick auf einen Zauber in der Warteschlange zum Hinzufügen."
L["Blacklisted Spells"] = "Gesperrte Zauber"
L["Add Spell to Blacklist"] = "Zauber zur Sperrliste hinzufügen"

-- Hotkey Overrides
L["Custom Hotkey"] = "Benutzerdefinierte Taste"
L["No custom hotkeys set"] = "Keine benutzerdefinierten Tasten gesetzt. Rechtsklick auf einen Zauber zum Festlegen."
L["Add Hotkey Override"] = "Hotkey-Überschreibung hinzufügen"
L["Hotkey"] = "Hotkey"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "Anzuzeigenden Hotkey-Text eingeben (z.B. 1, F1, S-2, Strg+Q)"
L["Custom Hotkeys"] = "Benutzerdefinierte Hotkeys"

-- Defensives
L["Show Defensive Icons"] = "Defensiv-Symbole anzeigen"
L["Add to %s"] = "Zu %s hinzufügen"

-- Orientation values
L["Up"] = "Hoch"
L["Dn"] = "Runter"

-- Descriptions
L["General description"] = "Einstellungen, die für beide Oberflächen gelten."
L["Shared Behavior"] = "Gemeinsames Verhalten"
L["Icon Layout"] = "Symbol-Layout"
L["Visibility"] = "Sichtbarkeit"
L["Appearance"] = "Aussehen"
L["Offensive Display"] = "Offensiv-Anzeige"
L["Defensive Display"] = "Defensiv-Anzeige"

-- Tooltip mode dropdown
L["Tooltips"] = "Tooltips"
L["Tooltips desc"] = "Wann Zauber-Tooltips beim Überfahren angezeigt werden sollen"
L["Never"] = "Nie"
L["Out of Combat Only"] = "Nur außerhalb des Kampfes"
L["Always"] = "Immer"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Defensiv-Sichtbarkeit"
L["Defensive Display Mode desc"] = "Bei niedriger Gesundheit: Nur anzeigen wenn Gesundheit unter Schwellwerte fällt\nNur im Kampf: Immer im Kampf anzeigen\nImmer: Jederzeit anzeigen"
L["When Health Low"] = "Bei niedriger Gesundheit"
L["In Combat Only"] = "Nur im Kampf"

-- Detailed descriptions
L["Max Icons desc"] = "Maximale Zaubersymbole (1 = Haupt, 2+ = Warteschlange)"
L["Icon Size desc"] = "Basisgröße der Symbole in Pixeln"
L["Spacing desc"] = "Abstand zwischen Symbolen in Pixeln"
L["Primary Spell Scale desc"] = "Skalierungsfaktor für das Hauptzauber-Symbol"
L["Queue Orientation desc"] = "Wachstumsrichtung und Seitenleisten-Position (Defensiv-Symbole + Lebensleiste)"
L["Highlight Mode desc"] = "Welche Leuchteffekte auf Zaubersymbolen angezeigt werden"
L["Frame Opacity desc"] = "Transparenz für den gesamten Rahmen"
L["Queue Icon Fade desc"] = "Entsättigung für Warteschlangen-Symbole (0 = Farbe, 1 = Grau)"
L["Hide When Mounted"] = "Auf Reittier ausblenden"
L["Hide When Mounted desc"] = "Ausblenden während auf einem Reittier"
L["Require Hostile Target"] = "Feindliches Ziel erforderlich"
L["Allow Item Abilities"] = "Gegenstandsfähigkeiten erlauben"
L["Allow Item Abilities desc"] = "Schmuckstück- und Gegenstandsfähigkeiten in der Offensiv-Warteschlange anzeigen"
L["Insert Procced Abilities desc"] = "Leuchtende Proc-Fähigkeiten zur Warteschlange hinzufügen"
L["Include All Available Abilities desc"] = "Hinter Makro-Bedingungen versteckte Fähigkeiten einbeziehen"
L["Panel Interaction"] = "Panel-Interaktion"
L["Panel Interaction desc"] = "Steuert wie das Panel auf Mauseingaben reagiert"
L["Unlocked"] = "Entsperrt"
L["Locked"] = "Gesperrt"
L["Click Through"] = "Durchklicken"
L["Enable Defensive Suggestions desc"] = "Defensiv-Vorschläge basierend auf Gesundheit anzeigen"
L["Custom Hotkey desc"] = "Text, der als Hotkey angezeigt werden soll (z.B. 'F1', 'Strg+Q', 'Maus4')"
L["Move up desc"] = "In der Priorität nach oben verschieben"
L["Move down desc"] = "In der Priorität nach unten verschieben"
L["Restore Defensive Defaults desc"] = "Die Defensivliste auf Standard-Zauber für Ihre Klasse zurücksetzen"

-- Additional sections
L["Defensive Priority List"] = "Defensiv-Prioritätsliste"
L["Defensive Priority desc"] = "Einheitliche Prioritätsreihenfolge — Selbstheilung und Cooldowns in einer Liste. Ziehen zum Sortieren."
L["Restore Class Defaults"] = "Klassen-Standardwerte wiederherstellen"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bars"] = "Lebensleisten anzeigen"
L["Show Health Bars desc"] = "Kompakte Spieler- und Begleiter-Lebensleisten neben der Warteschlange"
L["Defensive Icon Scale"] = "Defensiv-Symbol-Skalierung"
L["Defensive Icon Scale desc"] = "Skalierungsmultiplikator für Defensiv-Symbole"
L["Defensive Max Icons"] = "Maximale Symbole"
L["Defensive Max Icons desc"] = "Anzahl Defensiv-Zauber gleichzeitig"
L["Profiles"] = "Profile"
L["Profiles desc"] = "Charakter- und Spezialisierungsprofilverwaltung"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Spezialisierungsbasiertes Wechseln"
L["Auto-switch profile by spec"] = "Profil automatisch nach Spezialisierung wechseln"
L["(No change)"] = "(Keine Änderung)"
L["(Disabled)"] = "(Deaktiviert)"
-- New character default profile
L["New Character Defaults"] = "Standardeinstellungen für neue Charaktere"
L["Use Default profile for new characters"] = "Standardprofil für neue Charaktere verwenden"
L["Use Default profile for new characters desc"] = "Wenn aktiviert, starten neue Charaktere mit dem gemeinsamen Standardprofil anstatt ein eigenes zu erhalten. Betrifft nur Charaktere, die JustAC noch nie geladen haben."
-- Compound layout labels (queue direction + sidebar placement)
L["Left, Sidebar Above"] = "Links, Seitenleiste oben"
L["Left, Sidebar Below"] = "Links, Seitenleiste unten"
L["Right, Sidebar Above"] = "Rechts, Seitenleiste oben"
L["Right, Sidebar Below"] = "Rechts, Seitenleiste unten"
L["Up, Sidebar Left"] = "Hoch, Seitenleiste links"
L["Up, Sidebar Right"] = "Hoch, Seitenleiste rechts"
L["Down, Sidebar Left"] = "Runter, Seitenleiste links"
L["Down, Sidebar Right"] = "Runter, Seitenleiste rechts"

-- Target frame anchor
L["Target Frame Anchor"] = "Zielrahmen-Anker"
L["Target Frame Anchor desc"] = "Warteschlange am Standard-Zielrahmen verankern statt an einer festen Bildschirmposition"
L["Target Frame Replaced"] = "Standard-Zielrahmen nicht erkannt (durch ein anderes Addon ersetzt)"
L["Disabled"] = "Deaktiviert"
L["Top"] = "Oben"
L["Bottom"] = "Unten"
L["Left"] = "Links"
L["Right"] = "Rechts"

-- Additional UI strings
L["Hotkey Overrides Info"] = "Benutzerdefinierten Tastentext festlegen.\n\n|cff00ff00Rechtsklick|r um Hotkey festzulegen."
L["Blacklist Info"] = "Zauber aus der Warteschlange ausblenden.\n\n|cffff6666Umschalt+Rechtsklick|r zum Umschalten."
L["Restore Class Defaults name"] = "Klassen-Standardwerte wiederherstellen"

-- Spell search UI
L["Search spell name or ID"] = "Zaubername oder ID suchen"
L["Search spell desc"] = "Zaubername oder ID eingeben (2+ Zeichen zum Suchen)"
L["Select spell to add"] = "Zauber aus den Ergebnissen zum Hinzufügen auswählen"
L["Select spell to blacklist"] = "Zauber aus den Ergebnissen zum Sperren auswählen"
L["Add spell manual desc"] = "Zauber per ID oder exaktem Namen hinzufügen"
L["Add spell dropdown desc"] = "Zauber per ID oder exaktem Namen hinzufügen (für Zauber nicht in der Liste)"
L["Select spell for hotkey"] = "Zauber aus den Ergebnissen auswählen"
L["Add hotkey desc"] = "Hotkey-Überschreibung für den ausgewählten Zauber hinzufügen"
L["No matches"] = "Keine Treffer - versuche eine andere Suche"
L["Please search and select a spell first"] = "Bitte zuerst einen Zauber suchen und auswählen"
L["Please enter a hotkey value"] = "Bitte einen Hotkey-Wert eingeben"

-- Display Mode (Standard Queue / Nameplate Overlay / Both / Disabled)
L["Display Mode"] = "Anzeigemodus"
L["Display Mode desc"] = "Anzeige wählen: Standard-Warteschlange zeigt das Hauptpanel, Namensplaketten-Overlay heftet Symbole an die Namensplakette, Beides aktiviert alle Anzeigen, Deaktiviert blendet alles aus."
L["Standard Queue"] = "Standard-Warteschlange"
L["Both"] = "Beides"
L["Queue Visibility"] = "Warteschlangen-Sichtbarkeit"
L["Queue Visibility desc"] = "Immer: Jederzeit anzeigen.\nNur im Kampf: Außerhalb des Kampfes ausblenden.\nFeindliches Ziel erforderlich: Nur anzeigen wenn ein angreifbarer Feind anvisiert wird."


-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "Begleiter-Wiederbelebung/Beschwörung (Priorität)"
L["Pet Rez/Summon Priority desc"] = "Wird angezeigt wenn Begleiter tot oder abwesend. Hohe Priorität — zuverlässig im Kampf."
L["Restore Pet Rez Defaults desc"] = "Begleiter-Wiederbelebungszauber auf Klassen-Standard zurücksetzen"
L["Pet Heal Priority List"] = "Begleiter-Heilung (Priorität)"
L["Pet Heal Priority desc"] = "Wird angezeigt wenn Begleiter-Gesundheit niedrig. Begleiter-Gesundheit kann im Kampf verborgen sein."
L["Restore Pet Heal Defaults desc"] = "Begleiter-Heilzauber auf Klassen-Standard zurücksetzen"
L["Show Pet Health Bar"] = "Begleiter-Lebensleiste anzeigen"
L["Show Pet Health Bar desc"] = "Kompakte Begleiter-Lebensleiste (nur Begleiterklassen). Türkis gefärbt. Wird ohne aktiven Begleiter ausgeblendet."

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "Overlay"
L["Offensive Queue"] = "Offensiv-Warteschlange"
L["Defensive Queue"] = "Defensiv-Warteschlange"
L["Reverse Anchor"] = "Anker umkehren"
L["Reverse Anchor desc"] = "Standardmäßig erscheinen DPS-Symbole rechts der Namensplakette. Aktivieren um sie links zu platzieren. Defensiv-Symbole erscheinen immer auf der gegenüberliegenden Seite."
L["Nameplate Show Defensives desc"] = "Defensiv-Symbole auf der gegenüberliegenden Seite der Namensplakette anzeigen."
L["Interrupt Mode"] = "Unterbrechungserinnerung"
L["Interrupt Mode desc"] = "Steuert wann das Unterbrechungserinnerungssymbol erscheint und welche Fähigkeit vorgeschlagen wird."
L["Sounds"] = "Töne"
L["Interrupt Alert"] = "Unterbrechungsalarm"
L["Interrupt Alert Sound desc"] = "Einen Sound abspielen, wenn das Unterbrechungssymbol erstmals erscheint."
L["Interrupt Mode Disabled"] = "Deaktiviert — Keine Unterbrechungssymbole"
L["Interrupt Mode Kick Only"] = "Nur Kick — Kick bei unterbrechbaren Zaubern"
L["Interrupt Mode CC Shielded"] = "Kick + CC — Auch Betäubung/Furcht bei geschützten Zaubern"
L["Interrupt Mode CC Prefer"] = "CC bevorzugen — Betäubung statt Kick; Kick bei Bossen"
L["Nameplate Show Health Bars desc"] = "Kompakte Spieler- und Begleiter-Lebensleisten über den Defensiv-Symbolen anzeigen. Begleiter-Leiste wird ohne aktiven Begleiter ausgeblendet. Automatisch ausgeblendet wenn keine Defensiven sichtbar."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Auf Standard zurücksetzen"
L["Reset General desc"] = "Alle allgemeinen Einstellungen auf Standardwerte zurücksetzen."
L["Reset Layout desc"] = "Layout-Einstellungen auf Standard zurücksetzen."
L["Reset Offensive Display desc"] = "Offensiv-Anzeigeeinstellungen auf Standard zurücksetzen."
L["Reset Defensive Display desc"] = "Defensiv-Anzeigeeinstellungen auf Standard zurücksetzen."

-- Icon Labels (21 keys)
L["Icon Labels"] = "Symbolbeschriftungen"
L["Hotkey Text"] = "Hotkey-Text"
L["Cooldown Text"] = "Abklingzeit-Countdown"
L["Charge Count"] = "Aufladungen"
L["Show"] = "Anzeigen"
L["Font Scale"] = "Schriftskalierung"
L["Font Scale desc"] = "Multiplikator für die Basis-Schriftgröße (1.0 = Standardgröße)."
L["Text Color"] = "Farbe"
L["Text Color desc"] = "Farbe und Deckkraft dieses Textelements."
L["Text Anchor"] = "Position"
L["Hotkey Anchor desc"] = "Wo auf dem Symbol die Hotkey-Beschriftung erscheint."
L["Charge Anchor desc"] = "Wo auf dem Symbol die Aufladungsanzeige erscheint."
L["Top Right"] = "Oben rechts"
L["Top Left"] = "Oben links"
L["Top Center"] = "Oben Mitte"
L["Center"] = "Mitte"
L["Bottom Right"] = "Unten rechts"
L["Bottom Left"] = "Unten links"
L["Bottom Center"] = "Unten Mitte"
L["Reset Icon Labels desc"] = "Alle Symbolbeschriftungs-Einstellungen auf Standardwerte zurücksetzen."

-- Expansion Direction / positioning (5 keys)
L["Expansion Direction"] = "Erweiterungsrichtung"
L["Expansion Direction desc"] = "Stapelrichtung der Symbole bei mehreren Plätzen. Horizontal erweitert von der Namensplakette weg. Vertikal hoch/runter stapelt über/unter Platz 1."
L["Horizontal (Out)"] = "Horizontal (raus)"
L["Vertical - Up"] = "Vertikal - Hoch"
L["Vertical - Down"] = "Vertikal - Runter"

-- Gap-Closers
L["Gap-Closers"] = "Annäherung"
L["Enable Gap-Closer Suggestions"] = "Annäherungs-Vorschläge aktivieren"
L["Enable Gap-Closer Suggestions desc"] = "Schlägt Fähigkeiten vor, wenn das Ziel außer Nahkampfreichweite ist. An Position 2, vor Procs."
L["Gap-Closer Priority List"] = "Prioritätsliste der Annäherung"
L["Gap-Closer Priority desc"] = "Der erste verwendbare Zauber wird angezeigt. Reihenfolge ändern, um Priorität festzulegen."
L["Restore Gap-Closer Defaults desc"] = "Annäherungsliste auf Klassen-Standardzauber zurücksetzen"
L["No Gap-Closer Spells"] = "Keine Annäherungszauber konfiguriert. Dropdown nutzen oder Klassen-Standards wiederherstellen."
L["Reset Gap-Closers desc"] = "Annäherungs-Einstellungen zurücksetzen. Die Zauberliste wird nicht beeinflusst."
L["Show Gap-Closer Glow"] = "Annäherungsleuchten anzeigen"
L["Show Gap-Closer Glow desc"] = "Goldenes Leuchten auf Annäherungssymbolen anzeigen, um deren Verfügbarkeit hervorzuheben."
L["Gap-Closer Behavior Note"] = "Annäherungszauber ersetzen Position 1, wenn das Ziel außer Reichweite ist."
L["Gap-Closer Ranged Spec Note"] = "Keine Standard-Annäherungszauber für diese Spezialisierung. Bei Bedarf können unten manuell Zauber hinzugefügt werden."
L["Melee Range Reference"] = "Nahkampfreichweiten-Referenz"
L["Melee Range Spell desc"] = "Annäherungszauber werden ausgelöst, wenn diese Fähigkeit außer Reichweite ist. Muss in der Aktionsleiste sein."
L["Melee Range Spell Override desc"] = "Zauber-ID-Überschreibung (leer = automatisch)"
L["Default"] = "Standard"
L["Override"] = "Überschreibung"
L["Clear Override"] = "Überschreibung löschen"
L["Search Spell"] = "Zauber suchen"
L["Unknown"] = "Unbekannt"
L["None"] = "Keiner"

-- Blacklist Position 1
L["Blacklist Position 1"] = "Auf Position 1 anwenden"
L["Blacklist Position 1 desc"] = "Die Sperrliste auch auf Position 1 (Blizzards Hauptvorschlag) anwenden. Warnung: Das Ausblenden des Hauptzaubers kann die Rotation stoppen — Blizzards System wartet auf dessen Ausführung."

