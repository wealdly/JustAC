-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: French (frFR) - 5.6% of player base

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "frFR")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "Général"
L["Settings"] = "Paramètres"
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
L["Queue Orientation"] = "Disposition de la file"
L["Gamepad Icon Style"] = "Style d'icônes manette"
L["Gamepad Icon Style desc"] = "Choisir le style d'icônes des boutons pour les raccourcis manette/contrôleur."
L["Input Preference"] = "Préférence d'entrée"
L["Input Preference desc"] = "Choisir le type de raccourci à afficher. Auto-Détecter affiche les raccourcis manette quand connectée, sinon les raccourcis clavier."
L["Auto-Detect"] = "Auto-Détecter"
L["Keyboard"] = "Clavier"
L["Gamepad"] = "Manette"
L["Generic"] = "Générique (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Croix/Cercle/Carré/Triangle)"
L["Insert Procced Defensives"] = "Insérer les défensifs déclenchés"
L["Insert Procced Defensives desc"] = "Afficher les capacités défensives déclenchées (Charge victorieuse, soins gratuits) à tout niveau de santé."
L["Frame Opacity"] = "Opacité du cadre"
L["Queue Icon Fade"] = "Fondu des icônes de file"
L["Insert Procced Abilities"] = "Afficher toutes les capacités déclenchées"
L["Include All Available Abilities"] = "Inclure les capacités cachées"
L["Highlight Mode"] = "Mode de mise en évidence"
L["All Glows"] = "Toutes les lueurs"
L["Primary Only"] = "Principal uniquement"
L["Proc Only"] = "Proc uniquement"
L["No Glows"] = "Aucune lueur"
L["Show Key Press Flash"] = "Flash touche pressée"
L["Show Key Press Flash desc"] = "Faire clignoter l'icône lorsque vous appuyez sur le raccourci correspondant."
L["Grey Out While Casting"] = "Griser pendant l'incantation"
L["Grey Out While Casting desc"] = "Désaturer les icônes de file pendant l'incantation. Le sort en cours reste en couleur."
L["Grey Out While Channeling"] = "Griser pendant la canalisation"
L["Grey Out While Channeling desc"] = "Désaturer les icônes de file pendant la canalisation. Le sort canalisé reste en couleur avec une animation de remplissage."

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
L["Show Defensive Icons"] = "Afficher les icônes défensives"
L["Add to %s"] = "Ajouter à %s"

-- Orientation values
L["Up"] = "Haut"
L["Dn"] = "Bas"

-- Descriptions
L["General description"] = "Paramètres partagés entre la file standard et l'overlay."
L["Shared Behavior"] = "Comportement partagé"
L["Icon Layout"] = "Disposition des icônes"
L["Visibility"] = "Visibilité"
L["Appearance"] = "Apparence"
L["Offensive Display"] = "Affichage offensif"
L["Defensive Display"] = "Affichage défensif"

-- Tooltip mode dropdown
L["Tooltips"] = "Infobulles"
L["Tooltips desc"] = "Quand afficher les infobulles de sort au survol"
L["Never"] = "Jamais"
L["Out of Combat Only"] = "Hors combat uniquement"
L["Always"] = "Toujours"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Visibilité défensive"
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
L["Frame Opacity desc"] = "Opacité globale pour l'ensemble du cadre"
L["Queue Icon Fade desc"] = "Désaturation pour les icônes en file (0 = couleur, 1 = niveaux de gris)"
L["Hide When Mounted"] = "Masquer sur monture"
L["Hide When Mounted desc"] = "Masquer sur une monture"
L["Require Hostile Target"] = "Cible hostile requise"
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
L["Restore Defensive Defaults desc"] = "Réinitialiser la liste défensive aux sorts par défaut"

-- Additional sections
L["Defensive Priority List"] = "Liste de priorité défensive"
L["Defensive Priority desc"] = "Ordre de priorité unifié — auto-soins et temps de recharge en une seule liste. Réorganisez pour définir la priorité."
L["Restore Class Defaults"] = "Restaurer les valeurs par défaut"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bars"] = "Afficher les barres de santé"
L["Show Health Bars desc"] = "Barres de santé compactes du joueur et du familier à côté de la file"
L["Defensive Icon Scale"] = "Échelle de l'icône défensive"
L["Defensive Icon Scale desc"] = "Multiplicateur d'échelle pour les icônes défensives"
L["Defensive Max Icons"] = "Icônes maximum"
L["Defensive Max Icons desc"] = "Sorts défensifs à afficher"
L["Profiles"] = "Profils"
L["Profiles desc"] = "Gestion des profils de personnage et de spécialisation"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Changement par spécialisation"
L["Auto-switch profile by spec"] = "Changer de profil automatiquement par spécialisation"
L["(No change)"] = "(Pas de changement)"
L["(Disabled)"] = "(Désactivé)"
-- New character default profile
L["New Character Defaults"] = "Paramètres par défaut des nouveaux personnages"
L["Use Default profile for new characters"] = "Utiliser le profil par défaut pour les nouveaux personnages"
L["Use Default profile for new characters desc"] = "Si activé, les nouveaux personnages démarrent sur le profil par défaut partagé plutôt que d'en obtenir un propre. N'affecte que les personnages n'ayant jamais chargé JustAC."
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
L["Select spell for hotkey"] = "Sélectionner un sort ou objet des résultats"
L["Add hotkey desc"] = "Ajouter un raccourci personnalisé pour le sort ou l'objet sélectionné"
L["No matches"] = "Aucun résultat - essayez une autre recherche"
L["Please search and select a spell first"] = "Veuillez d'abord rechercher et sélectionner un sort ou objet"
L["Please enter a hotkey value"] = "Veuillez entrer une valeur de raccourci"
L["Select Spell..."] = "Sélectionner sort/objet..."
L["No spell selected"] = "Aucun sort ou objet sélectionné"
L["Set Override..."] = "Définir remplacement..."

-- Display Mode (Standard Queue / Nameplate Overlay / Both / Disabled)
L["Display Mode"] = "Mode d'affichage"
L["Display Mode desc"] = "File standard affiche le panneau principal, Overlay de plaque attache les icônes à la plaque, Les deux active tout, Désactivé masque tout."
L["Standard Queue"] = "File standard"
L["Both"] = "Les deux"
L["Queue Visibility"] = "Visibilité de la file"
L["Queue Visibility desc"] = "Toujours : afficher en permanence.\nEn combat uniquement : masquer hors combat.\nCible hostile requise : afficher uniquement en ciblant un ennemi attaquable."


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
L["Offensive Queue"] = "File offensive"
L["Defensive Queue"] = "File défensive"
L["Reverse Anchor"] = "Inverser l'ancrage"
L["Reverse Anchor desc"] = "Par défaut les icônes DPS apparaissent à droite de la plaque. Activer pour les placer à gauche. Les icônes défensives sont toujours du côté opposé."
L["Nameplate Show Defensives desc"] = "Afficher les icônes défensives du côté opposé de la plaque."
L["Interrupt Mode"] = "Rappel d'interruption"
L["Interrupt Mode desc"] = "Contrôle quand l'icône de rappel d'interruption apparaît et quelle capacité suggérer."
L["Sounds"] = "Sons"
L["Interrupt Alert"] = "Alerte d'interruption"
L["Interrupt Alert Sound desc"] = "Jouer un son lorsque l'icône d'interruption apparaît pour la première fois."
L["Interrupt Mode Disabled"] = "Désactivé — Aucune icône d'interruption"
L["Interrupt Mode Kick Only"] = "Kick uniquement — Suggérer le kick sur sorts interruptibles"
L["Interrupt Mode CC Shielded"] = "Kick + CC — Aussi étourdir/effrayer les sorts protégés"
L["Interrupt Mode CC Prefer"] = "Préférer CC — Étourdissements plutôt que kicks ; kick sur boss"
L["Nameplate Show Health Bars desc"] = "Afficher des barres de santé compactes du joueur et du familier au-dessus des icônes défensives. La barre du familier se masque sans familier actif. Se masque automatiquement sans défensifs visibles."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Réinitialiser"
L["Reset General desc"] = "Réinitialiser tous les paramètres généraux à leurs valeurs par défaut."
L["Reset Layout desc"] = "Réinitialiser les paramètres de disposition."
L["Reset Offensive Display desc"] = "Réinitialiser les paramètres d'affichage offensif."
L["Reset Defensive Display desc"] = "Réinitialiser les paramètres d'affichage défensif."

-- Icon Labels (21 keys)
L["Icon Labels"] = "Libellés des icônes"
L["Hotkey Text"] = "Texte de raccourci"
L["Cooldown Text"] = "Compte à rebours"
L["Charge Count"] = "Nombre (Charges / Qté)"
L["Show"] = "Afficher"
L["Font Scale"] = "Échelle de police"
L["Font Scale desc"] = "Multiplicateur appliqué à la taille de police de base (1.0 = taille par défaut)."
L["Text Color"] = "Couleur"
L["Text Color desc"] = "Couleur et opacité de cet élément de texte."
L["Text Anchor"] = "Position"
L["Hotkey Anchor desc"] = "Emplacement du libellé du raccourci sur l'icône."
L["Charge Anchor desc"] = "Emplacement du nombre de charges ou de la quantité d'objets sur l'icône."
L["Top Right"] = "Haut droite"
L["Top Left"] = "Haut gauche"
L["Top Center"] = "Haut centre"
L["Center"] = "Centre"
L["Bottom Right"] = "Bas droite"
L["Bottom Left"] = "Bas gauche"
L["Bottom Center"] = "Bas centre"
L["Reset Icon Labels desc"] = "Réinitialiser tous les paramètres de libellés des icônes à leurs valeurs par défaut."

-- Expansion Direction / positioning (5 keys)
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
L["Reset Gap-Closers desc"] = "Réinitialiser les paramètres d'approche. La liste de sorts n'est pas affectée."
L["Show Gap-Closer Glow"] = "Lueur d'approche"
L["Show Gap-Closer Glow desc"] = "Affiche une lueur dorée sur les icônes d'approche pour indiquer leur disponibilité."
L["Gap-Closer Behavior Note"] = "Les sorts d'approche remplacent la position 1 quand la cible est hors de portée."
L["Gap-Closer Ranged Spec Note"] = "Pas de sorts d'approche par défaut pour cette spécialisation. Vous pouvez ajouter des sorts manuellement ci-dessous si nécessaire."
L["Melee Range Reference"] = "Référence de portée de mêlée"
L["Melee Range Spell desc"] = "Les sorts d'approche se déclenchent quand cette capacité est hors de portée. Doit être dans votre barre d'action."
L["Melee Range Spell Override desc"] = "Remplacement de l'ID de sort (vide = auto)"
L["Default"] = "Par défaut"
L["Override"] = "Personnaliser"
L["Clear Override"] = "Effacer la personnalisation"
L["Search Spell"] = "Rechercher un sort"
L["Unknown"] = "Inconnu"
L["None"] = "Aucun"

-- Blacklist Position 1
L["Blacklist Position 1"] = "Appliquer à la position 1"
L["Blacklist Position 1 desc"] = "Appliquer également la liste noire à la position 1 (suggestion principale de Blizzard). Avertissement : masquer le sort principal peut bloquer la rotation — le système de Blizzard attend qu'il soit lancé."

-- Performance
L["Performance"] = "Performance"
L["Disable Blizzard Highlight"] = "Désactiver le surlignage Blizzard"
L["Disable Blizzard Highlight desc"] = "Désactiver ceci améliore les performances. L'AssistedCombatManager de Blizzard exécute une boucle par image qui scanne chaque bouton de barre d'action pour afficher un effet lumineux bleu. JustAC affiche déjà ces informations dans sa propre file. Le désactiver supprime cette boucle et peut empêcher les erreurs « limite de temps d'exécution de script dépassée » sous forte charge d'addons. Ce paramètre persiste entre les sessions."

