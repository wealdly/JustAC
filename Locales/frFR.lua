-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: French (frFR) - 5.6% of player base

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "frFR")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "Général"
L["System"] = "Système"
L["Offensive"] = "Offensifs"
L["Defensives"] = "Défensifs"
L["Blacklist"] = "Liste noire"
L["Hotkey Overrides"] = "Raccourcis"
L["Add"] = "Ajouter"
L["Clear All"] = "Tout effacer"
L["Clear All Blacklist desc"] = "Retirer tous les sorts de la liste noire"
L["Clear All Hotkeys desc"] = "Supprimer tous les raccourcis personnalisés"

-- General Options
L["Max Icons"] = "Icônes max"
L["Icon Size"] = "Taille des icônes"
L["Spacing"] = "Espacement"
L["Primary Spell Scale"] = "Échelle du sort principal"
L["Queue Orientation"] = "Orientation de la file"
L["Gamepad Icon Style"] = "Style d'icônes manette"
L["Gamepad Icon Style desc"] = "Choisir le style d'icônes des boutons pour les raccourcis manette/contrôleur."
L["Generic"] = "Générique (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Croix/Cercle/Carré/Triangle)"
L["Show Offensive Hotkeys"] = "Afficher les raccourcis"
L["Show Offensive Hotkeys desc"] = "Afficher le texte des raccourcis sur les icônes offensives."
L["Show Defensive Hotkeys"] = "Afficher les raccourcis"
L["Show Defensive Hotkeys desc"] = "Afficher le texte des raccourcis sur les icônes défensives."
L["Insert Procced Defensives"] = "Insérer les défensifs déclenchés"
L["Insert Procced Defensives desc"] = "Afficher les capacités défensives déclenchées (Charge victorieuse, soins gratuits) à tout niveau de santé."
L["Frame Opacity"] = "Opacité du cadre"
L["Queue Icon Fade"] = "Fondu des icônes de file"
L["Hide Out of Combat"] = "Masquer la file hors combat"
L["Insert Procced Abilities"] = "Afficher toutes les capacités déclenchées"
L["Include All Available Abilities"] = "Inclure les capacités cachées"
L["Highlight Mode"] = "Mode de mise en évidence"
L["All Glows"] = "Toutes les lueurs"
L["Primary Only"] = "Principal uniquement"
L["Proc Only"] = "Proc uniquement"
L["No Glows"] = "Aucune lueur"
L["Show Key Press Flash"] = "Flash touche pressée"
L["Show Key Press Flash desc"] = "Faire clignoter l'icône lorsque vous appuyez sur le raccourci correspondant."

-- Blacklist
L["Remove"] = "Supprimer"
L["No spells currently blacklisted"] = "Aucun sort dans la liste noire. Maj+Clic droit sur un sort dans la file pour l'ajouter."
L["Blacklisted Spells"] = "Sorts en liste noire"
L["Add Spell to Blacklist"] = "Ajouter un sort à la liste noire"

-- Hotkey Overrides
L["Custom Hotkey"] = "Raccourci personnalisé"
L["No custom hotkeys set"] = "Aucun raccourci personnalisé défini. Clic droit sur un sort pour définir un raccourci."
L["Add Hotkey Override"] = "Ajouter un raccourci personnalisé"
L["Hotkey"] = "Raccourci"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "Entrer le texte du raccourci à afficher (par ex. 1, F1, S-2, Ctrl+Q)"
L["Custom Hotkeys"] = "Raccourcis personnalisés"

-- Defensives
L["Enable Defensive Suggestions"] = "Activer les suggestions défensives"
L["Add to %s"] = "Ajouter à %s"

-- Orientation values
L["Up"] = "Haut"
L["Dn"] = "Bas"

-- Descriptions
L["General description"] = "Configurer l'apparence et le comportement de la file de sorts."
L["Icon Layout"] = "Disposition des icônes"
L["Visibility"] = "Visibilité"
L["Queue Content"] = "Contenu de la file"
L["Appearance"] = "Apparence"
L["Display"] = "Affichage"

-- Tooltip mode dropdown
L["Tooltips"] = "Infobulles"
L["Tooltips desc"] = "Quand afficher les infobulles de sort au survol"
L["Never"] = "Jamais"
L["Out of Combat Only"] = "Hors combat uniquement"
L["Always"] = "Toujours"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Mode d'affichage"
L["Defensive Display Mode desc"] = "Santé basse : Afficher uniquement sous les seuils\nEn combat uniquement : Toujours afficher en combat\nToujours : Afficher en permanence"
L["When Health Low"] = "Santé basse"
L["In Combat Only"] = "En combat uniquement"

-- Detailed descriptions
L["Max Icons desc"] = "Nombre maximum d'icônes de sort (1 = principal, 2+ = file)"
L["Icon Size desc"] = "Taille de base des icônes en pixels"
L["Spacing desc"] = "Espace entre les icônes en pixels"
L["Primary Spell Scale desc"] = "Multiplicateur d'échelle pour l'icône principale"
L["Queue Orientation desc"] = "Direction dans laquelle la file s'étend"
L["Highlight Mode desc"] = "Quels effets lumineux afficher sur les icônes"
L["Single-Button Assistant Warning"] = "Avertissement : Placez l'Assistant à touche unique sur une barre d'action pour que JustAC fonctionne correctement."
L["Frame Opacity desc"] = "Opacité globale pour l'ensemble du cadre"
L["Queue Icon Fade desc"] = "Désaturation pour les icônes en file (0 = couleur, 1 = niveaux de gris)"
L["Hide Out of Combat desc"] = "Masquer toute la file de sorts hors combat"
L["Hide When Mounted"] = "Masquer sur monture"
L["Hide When Mounted desc"] = "Masquer sur une monture"
L["Require Hostile Target"] = "Cible hostile requise"
L["Require Hostile Target desc"] = "Afficher uniquement avec une cible hostile (hors combat uniquement)"
L["Allow Item Abilities"] = "Allow Item Abilities"
L["Allow Item Abilities desc"] = "Show trinket and on-use item abilities in the offensive queue"
L["Insert Procced Abilities desc"] = "Ajouter les capacités déclenchées du grimoire à la file"
L["Include All Available Abilities desc"] = "Inclure les capacités cachées derrière des conditions de macro"
L["Panel Interaction"] = "Interaction du panneau"
L["Panel Interaction desc"] = "Comment le panneau réagit aux entrées souris"
L["Unlocked"] = "Déverrouillé"
L["Locked"] = "Verrouillé"
L["Click Through"] = "Clic traversant"
L["Enable Defensive Suggestions desc"] = "Afficher les sorts défensifs quand la santé est basse"
L["Icon Position desc"] = "Où placer les icônes défensives par rapport à la file"
L["Custom Hotkey desc"] = "Texte à afficher comme raccourci (par ex. 'F1', 'Ctrl+Q', 'Souris4')"
L["Move up desc"] = "Monter dans la priorité"
L["Move down desc"] = "Descendre dans la priorité"
L["Restore Class Defaults desc"] = "Réinitialiser la liste d'auto-soin aux sorts par défaut"
L["Restore Cooldowns Defaults desc"] = "Réinitialiser la liste de temps de recharge aux sorts par défaut"

-- Additional sections
L["Icon Position"] = "Position de l'icône"
L["Self-Heal Priority List"] = "Liste de priorité d'auto-soin (vérifiée en premier)"
L["Self-Heal Priority desc"] = "Soins rapides pour votre rotation."
L["Restore Class Defaults"] = "Restaurer les valeurs par défaut"
L["Major Cooldowns Priority List"] = "Liste de priorité des temps de recharge majeurs (urgence)"
L["Major Cooldowns Priority desc"] = "Défensifs d'urgence quand auto-soins indisponibles."

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "Afficher la barre de santé"
L["Show Health Bar desc"] = "Barre de santé compacte à côté de la file"
L["disabled when Defensive Queue is enabled"] = "disabled when Defensive Queue is enabled"
L["Defensive Icon Scale"] = "Échelle de l'icône défensive"
L["Defensive Icon Scale desc"] = "Multiplicateur d'échelle pour les icônes défensives"
L["Defensive Max Icons"] = "Icônes maximum"
L["Defensive Max Icons desc"] = "Sorts défensifs à afficher (1-3)"
L["Profiles"] = "Profils"
L["Profiles desc"] = "Gestion des profils de personnage et de spécialisation"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Changement par spécialisation"
L["Auto-switch profile by spec"] = "Changer de profil automatiquement par spécialisation"
L["(No change)"] = "(Pas de changement)"
L["(Disabled)"] = "(Désactivé)"
-- Orientation values (full names)
L["Left to Right"] = "Gauche à droite"
L["Right to Left"] = "Droite à gauche"
L["Bottom to Top"] = "Bas vers haut"
L["Top to Bottom"] = "Haut vers bas"

-- Target frame anchor
L["Target Frame Anchor"] = "Ancrage cadre de cible"
L["Target Frame Anchor desc"] = "Attacher la file au cadre de cible par défaut au lieu d'une position fixe"
L["Disabled"] = "Désactivé"
L["Top"] = "Haut"
L["Bottom"] = "Bas"
L["Left"] = "Gauche"
L["Right"] = "Droite"

-- Additional UI strings
L["Hotkey Overrides Info"] = "Définir un raccourci personnalisé.\n\n|cff00ff00Clic droit|r pour définir un raccourci."
L["Blacklist Info"] = "Masquer des sorts de la file.\n\n|cffff6666Maj+Clic droit|r pour basculer."
L["Restore Class Defaults name"] = "Restaurer les valeurs par défaut"

-- Spell search UI
L["Search spell name or ID"] = "Rechercher nom ou ID de sort"
L["Search spell desc"] = "Entrer nom ou ID de sort (2+ caractères pour chercher)"
L["Select spell to add"] = "Sélectionner un sort des résultats pour l'ajouter"
L["Select spell to blacklist"] = "Sélectionner un sort des résultats pour le mettre en liste noire"
L["Add spell manual desc"] = "Ajouter un sort par ID ou nom exact"
L["Add spell dropdown desc"] = "Ajouter un sort par ID ou nom exact (pour les sorts hors liste)"
L["Select spell for hotkey"] = "Sélectionner un sort des résultats"
L["Add hotkey desc"] = "Ajouter un raccourci personnalisé pour le sort sélectionné"
L["No matches"] = "Aucun résultat - essayez une autre recherche"
L["Please search and select a spell first"] = "Veuillez d'abord rechercher et sélectionner un sort"
L["Please enter a hotkey value"] = "Veuillez entrer une valeur de raccourci"

-- Display Mode (Standard Queue / Nameplate Overlay / Both / Disabled)
L["Display Mode"] = "Display Mode"
L["Display Mode desc"] = "Choose what to display: Standard Queue shows the main panel, Nameplate Overlay attaches icons to the target nameplate, Both enables all displays, Disabled hides everything."
L["Standard Queue"] = "Standard Queue"
L["Both"] = "Both"

-- Item Features
L["Items"] = "Items"
L["Allow Items in Spell Lists"] = "Allow Items in Spell Lists"
L["Allow Items in Spell Lists desc"] = "Enable adding consumables (potions, healthstones) to defensive spell lists. When enabled, the search dropdown will also scan your bags and action bars for items."
L["Auto-Insert Health Potions"] = "Auto-Insert Health Potions"
L["Auto-Insert Health Potions desc"] = "Automatically suggest a healing potion from your action bars when health is critically low, even if not manually added to your spell lists."

-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "Pet Rez/Summon Priority List"
L["Pet Rez/Summon Priority desc"] = "Shown when pet is dead or missing. High priority - reliable in combat."
L["Restore Pet Rez Defaults desc"] = "Reset pet rez/summon spells to class defaults"
L["Pet Heal Priority List"] = "Pet Heal Priority List"
L["Pet Heal Priority desc"] = "Shown when pet health is low. Best-effort - pet health may be hidden in combat."
L["Restore Pet Heal Defaults desc"] = "Reset pet heal spells to class defaults"
L["Show Pet Health Bar"] = "Show Pet Health Bar"
L["Show Pet Health Bar desc"] = "Show a compact pet health bar (pet classes only). Uses teal color. Auto-hides when no pet is active."

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "Overlay"
L["Nameplate Overlay desc"] = "Attach queue icons directly to the target's nameplate. Fully independent of the main panel - either or both can be enabled."
L["Offensive Slots"] = "Offensive Slots"
L["Offensive Queue"] = "Offensive Queue"
L["Defensive Suggestions"] = "Defensive Suggestions"
L["Show Hotkeys"] = "Show Hotkeys"
L["Reverse Anchor"] = "Reverse Anchor"
L["Reverse Anchor desc"] = "By default DPS icons appear on the right side of the nameplate. Enable to place them on the left instead. Defensive icons always appear on the opposite side."
L["Nameplate Icon Size"] = "Icon Size"
L["Nameplate Show Defensives"] = "Show Defensive Icons"
L["Nameplate Show Defensives desc"] = "Show defensive queue icons on the opposite side of the nameplate."
L["Nameplate Defensive Display Mode"] = "Defensive Visibility"
L["Nameplate Defensive Display Mode desc"] = "In Combat Only: show defensive icons only while in combat.\nAlways: show at all times."
L["Nameplate Defensive Count"] = "Defensive Slots"
L["Interrupt Mode"] = "Interrupt Reminder"
L["Interrupt Mode desc"] = "When to show the interrupt icon. Important Only: only for lethal/must-interrupt casts (uses C_Spell.IsSpellImportant). All Casts: any interruptible cast. Off: disabled."
L["Interrupt Important"] = "Important Only"
L["Interrupt All"] = "All Casts"
L["Interrupt Off"] = "Off"
L["CC All Casts"] = "CC Non-Important Casts"
L["CC All Casts desc"] = "Use crowd-control abilities (stuns, incapacitates) to interrupt non-important casts on CC-able mobs, saving your true interrupt lockout for important/lethal casts."
L["Nameplate Show Health Bar"] = "Show Health Bar"
L["Nameplate Show Health Bar desc"] = "Show a compact player health bar above the defensive icon cluster. Hides automatically when no defensives are visible."
L["Health Bar Position"] = "Bar Position"
L["Health Bar Position desc"] = "Controls where the health bar appears relative to the icon cluster. Outside: beyond the far edge of icons. Inside: between the nameplate and icon 1."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Reset to Defaults"
L["Reset General desc"] = "Reset all General settings to their default values."
L["Reset Offensive desc"] = "Reset offensive display and content settings to defaults. The blacklist is not affected."
L["Reset Overlay desc"] = "Reset all Overlay settings to their default values."
L["Reset Defensives desc"] = "Reset Defensive display and behavior settings to defaults. Spell lists are not affected."

-- Expansion Direction / positioning (7 keys)
L["Outside"] = "Outside"
L["Inside"] = "Inside"
L["Expansion Direction"] = "Expansion Direction"
L["Expansion Direction desc"] = "Direction icons stack when there are multiple slots. Horizontal expands away from the nameplate. Vertical Up/Down stacks icons above/below slot 1."
L["Horizontal (Out)"] = "Horizontal (Out)"
L["Vertical - Up"] = "Vertical - Up"
L["Vertical - Down"] = "Vertical - Down"
