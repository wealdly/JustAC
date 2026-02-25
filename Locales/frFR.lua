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
L["Queue Settings"] = "Paramètres de file"
L["Defensives"] = "Défensifs"
L["Priority Lists"] = "Listes de priorité"
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
L["Queue Orientation"] = "Disposition de la file"
L["Gamepad Icon Style"] = "Style d'icônes manette"
L["Gamepad Icon Style desc"] = "Choisir le style d'icônes des boutons pour les raccourcis manette/contrôleur."
L["Generic"] = "Générique (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Croix/Cercle/Carré/Triangle)"
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
L["Queue Orientation desc"] = "Direction de la file et placement de la barre latérale (défensifs + barre de vie)"
L["Highlight Mode desc"] = "Quels effets lumineux afficher sur les icônes"
L["Single-Button Assistant Warning"] = "Avertissement : Placez l'Assistant à touche unique sur une barre d'action pour que JustAC fonctionne correctement."
L["Frame Opacity desc"] = "Opacité globale pour l'ensemble du cadre"
L["Queue Icon Fade desc"] = "Désaturation pour les icônes en file (0 = couleur, 1 = niveaux de gris)"
L["Hide Out of Combat desc"] = "Masquer toute la file de sorts hors combat"
L["Hide When Mounted"] = "Masquer sur monture"
L["Hide When Mounted desc"] = "Masquer sur une monture"
L["Require Hostile Target"] = "Cible hostile requise"
L["Require Hostile Target desc"] = "Afficher uniquement avec une cible hostile (hors combat uniquement)"
L["Allow Item Abilities"] = "Autoriser les capacités d'objets"
L["Allow Item Abilities desc"] = "Afficher les capacités de bijoux et objets utilisables dans la file offensive"
L["Insert Procced Abilities desc"] = "Ajouter les capacités déclenchées du grimoire à la file"
L["Include All Available Abilities desc"] = "Inclure les capacités cachées derrière des conditions de macro"
L["Panel Interaction"] = "Interaction du panneau"
L["Panel Interaction desc"] = "Comment le panneau réagit aux entrées souris"
L["Unlocked"] = "Déverrouillé"
L["Locked"] = "Verrouillé"
L["Click Through"] = "Clic traversant"
L["Enable Defensive Suggestions desc"] = "Afficher les sorts défensifs quand la santé est basse"
L["Custom Hotkey desc"] = "Texte à afficher comme raccourci (par ex. 'F1', 'Ctrl+Q', 'Souris4')"
L["Move up desc"] = "Monter dans la priorité"
L["Move down desc"] = "Descendre dans la priorité"
L["Restore Class Defaults desc"] = "Réinitialiser la liste d'auto-soin aux sorts par défaut"
L["Restore Cooldowns Defaults desc"] = "Réinitialiser la liste de temps de recharge aux sorts par défaut"

-- Additional sections
L["Self-Heal Priority List"] = "Liste de priorité d'auto-soin (vérifiée en premier)"
L["Self-Heal Priority desc"] = "Soins rapides pour votre rotation."
L["Restore Class Defaults"] = "Restaurer les valeurs par défaut"
L["Major Cooldowns Priority List"] = "Liste de priorité des temps de recharge majeurs (urgence)"
L["Major Cooldowns Priority desc"] = "Défensifs d'urgence quand auto-soins indisponibles."

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "Afficher la barre de santé"
L["Show Health Bar desc"] = "Barre de santé compacte à côté de la file"
L["disabled when Defensive Queue is enabled"] = "désactivé quand la file défensive est activée"
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
-- Compound layout labels (queue direction + sidebar placement)
L["Left, Sidebar Above"] = "Gauche, barre latérale en haut"
L["Left, Sidebar Below"] = "Gauche, barre latérale en bas"
L["Right, Sidebar Above"] = "Droite, barre latérale en haut"
L["Right, Sidebar Below"] = "Droite, barre latérale en bas"
L["Up, Sidebar Left"] = "Haut, barre latérale à gauche"
L["Up, Sidebar Right"] = "Haut, barre latérale à droite"
L["Down, Sidebar Left"] = "Bas, barre latérale à gauche"
L["Down, Sidebar Right"] = "Bas, barre latérale à droite"

-- Target frame anchor
L["Target Frame Anchor"] = "Ancrage cadre de cible"
L["Target Frame Anchor desc"] = "Attacher la file au cadre de cible par défaut au lieu d'une position fixe"
L["Target Frame Replaced"] = "Cadre de cible standard non détecté (remplacé par un autre addon)"
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
L["Display Mode"] = "Mode d'affichage"
L["Display Mode desc"] = "File standard affiche le panneau principal, Overlay de plaque attache les icônes à la plaque, Les deux active tout, Désactivé masque tout."
L["Standard Queue"] = "File standard"
L["Both"] = "Les deux"

-- Item Features
L["Items"] = "Objets"
L["Allow Items in Spell Lists"] = "Autoriser les objets dans les listes de sorts"
L["Allow Items in Spell Lists desc"] = "Ajouter des consommables (potions, pierres de soins) aux listes défensives. La recherche inclura aussi les sacs et barres d'action."
L["Auto-Insert Health Potions"] = "Insertion auto des potions de soin"
L["Auto-Insert Health Potions desc"] = "Suggérer automatiquement une potion de soin quand la santé est critique, même sans ajout manuel."

-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "Résurrection/Invocation du familier (priorité)"
L["Pet Rez/Summon Priority desc"] = "Affiché quand le familier est mort ou absent. Haute priorité — fiable en combat."
L["Restore Pet Rez Defaults desc"] = "Réinitialiser les sorts de résurrection du familier aux valeurs par défaut"
L["Pet Heal Priority List"] = "Soin du familier (priorité)"
L["Pet Heal Priority desc"] = "Affiché quand la santé du familier est basse. La santé du familier peut être cachée en combat."
L["Restore Pet Heal Defaults desc"] = "Réinitialiser les sorts de soin du familier aux valeurs par défaut"
L["Show Pet Health Bar"] = "Barre de santé du familier"
L["Show Pet Health Bar desc"] = "Barre de santé compacte du familier (classes avec familier). Couleur sarcelle. Se masque sans familier actif."

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "Overlay"
L["Nameplate Overlay desc"] = "Attacher les icônes directement à la plaque de nom de la cible. Indépendant du panneau principal — l'un ou les deux peuvent être activés."
L["Offensive Slots"] = "Emplacements offensifs"
L["Offensive Queue"] = "File offensive"
L["Defensive Suggestions"] = "Suggestions défensives"
L["Reverse Anchor"] = "Inverser l'ancrage"
L["Reverse Anchor desc"] = "Par défaut les icônes DPS apparaissent à droite de la plaque. Activer pour les placer à gauche. Les icônes défensives sont toujours du côté opposé."
L["Nameplate Icon Size"] = "Taille des icônes"
L["Nameplate Show Defensives"] = "Afficher les icônes défensives"
L["Nameplate Show Defensives desc"] = "Afficher les icônes défensives du côté opposé de la plaque."
L["Nameplate Defensive Display Mode"] = "Visibilité défensive"
L["Nameplate Defensive Display Mode desc"] = "En combat uniquement : icônes défensives seulement en combat.\nToujours : afficher en permanence."
L["Nameplate Defensive Count"] = "Emplacements défensifs"
L["Show Interrupt Reminder"] = "Rappel d'interruption"
L["Show Interrupt Reminder desc"] = "Afficher une icône de rappel quand la cible lance un sort interruptible."
L["CC Regular Mobs"] = "Préférer CC sur les mobs normaux"
L["CC Regular Mobs desc"] = "Sur les mobs non-boss, préférer le contrôle de foule (étourdissements, incapacitations) à l'interruption. Sur les boss, toujours utiliser l'interruption."
L["Nameplate Show Health Bar"] = "Afficher la barre de santé"
L["Nameplate Show Health Bar desc"] = "Barre de santé compacte au-dessus des icônes défensives. Se masque sans défensifs visibles."
L["Health Bar Position"] = "Position de la barre"
L["Health Bar Position desc"] = "Position de la barre par rapport aux icônes. Extérieur : au-delà du bord des icônes. Intérieur : entre la plaque et l'icône 1."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Réinitialiser"
L["Reset General desc"] = "Réinitialiser tous les paramètres généraux à leurs valeurs par défaut."
L["Reset Offensive desc"] = "Réinitialiser les paramètres offensifs. La liste noire n'est pas affectée."
L["Reset Overlay desc"] = "Réinitialiser tous les paramètres de l'Overlay à leurs valeurs par défaut."
L["Reset Defensives desc"] = "Réinitialiser les paramètres défensifs. Les listes de sorts ne sont pas affectées."

-- Icon Labels (21 keys)
L["Icon Labels"] = "Libellés des icônes"
L["Icon Labels desc"] = "Personnaliser la taille de police, la couleur et la position des libellés de texte des icônes. File standard et Overlay de plaque de nom sont configurés indépendamment."
L["Hotkey Text"] = "Texte de raccourci"
L["Cooldown Text"] = "Compte à rebours"
L["Charge Count"] = "Nombre de charges"
L["Show"] = "Afficher"
L["Font Scale"] = "Échelle de police"
L["Font Scale desc"] = "Multiplicateur appliqué à la taille de police de base (1.0 = taille par défaut)."
L["Text Color"] = "Couleur"
L["Text Color desc"] = "Couleur et opacité de cet élément de texte."
L["Text Anchor"] = "Position"
L["Hotkey Anchor desc"] = "Emplacement du libellé du raccourci sur l'icône."
L["Charge Anchor desc"] = "Emplacement du nombre de charges sur l'icône."
L["Top Right"] = "Haut droite"
L["Top Left"] = "Haut gauche"
L["Top Center"] = "Haut centre"
L["Center"] = "Centre"
L["Bottom Right"] = "Bas droite"
L["Bottom Left"] = "Bas gauche"
L["Bottom Center"] = "Bas centre"
L["Reset Icon Labels desc"] = "Réinitialiser tous les paramètres de libellés des icônes à leurs valeurs par défaut."

-- Expansion Direction / positioning (7 keys)
L["Outside"] = "Extérieur"
L["Inside"] = "Intérieur"
L["Expansion Direction"] = "Direction d'expansion"
L["Expansion Direction desc"] = "Direction d'empilement des icônes. Horizontal s'étend depuis la plaque. Vertical haut/bas empile au-dessus/en dessous de l'emplacement 1."
L["Horizontal (Out)"] = "Horizontal (vers l'ext.)"
L["Vertical - Up"] = "Vertical - Haut"
L["Vertical - Down"] = "Vertical - Bas"

-- Gap-Closers
L["Gap-Closers"] = "Approche"
L["Enable Gap-Closer Suggestions"] = "Activer les suggestions d'approche"
L["Enable Gap-Closer Suggestions desc"] = "Suggère des capacités d'approche quand la cible est hors de portée de mêlée. Affiché en position 2, avant les procs."
L["Gap-Closer Priority List"] = "Liste de priorité des approches"
L["Gap-Closer Priority desc"] = "Le premier sort utilisable est affiché. Réordonner pour définir la priorité."
L["Restore Gap-Closer Defaults desc"] = "Réinitialiser la liste d'approche aux sorts par défaut de votre classe et spécialisation"
L["No Gap-Closer Spells"] = "Aucun sort d'approche configuré. Utilisez le menu déroulant ou cliquez sur Restaurer les défauts de classe."
L["Show Gap-Closer Glow"] = "Lueur d'approche"
L["Show Gap-Closer Glow desc"] = "Affiche une lueur rouge sur les icônes d'approche pour indiquer leur disponibilité."
