-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spanish - Spain (esES) - ~5% of player base

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "esES")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "General"
L["System"] = "Sistema"
L["Offensive"] = "Ofensivos"
L["Defensives"] = "Defensivos"
L["Blacklist"] = "Lista negra"
L["Hotkey Overrides"] = "Atajos"
L["Add"] = "Agregar"
L["Clear All"] = "Borrar todo"
L["Clear All Blacklist desc"] = "Eliminar todos los hechizos de la lista negra"
L["Clear All Hotkeys desc"] = "Eliminar todos los atajos personalizados"

-- General Options
L["Max Icons"] = "Iconos máx"
L["Icon Size"] = "Tamaño de icono"
L["Spacing"] = "Espaciado"
L["Primary Spell Scale"] = "Escala del hechizo principal"
L["Queue Orientation"] = "Orientación de cola"
L["Gamepad Icon Style"] = "Estilo de icono del mando"
L["Gamepad Icon Style desc"] = "Elegir el estilo de iconos de botones para mandos/controladores."
L["Generic"] = "Genérico (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Cruz/Círculo/Cuadrado/Triángulo)"
L["Show Offensive Hotkeys"] = "Mostrar atajos"
L["Show Offensive Hotkeys desc"] = "Mostrar texto de atajos en iconos ofensivos."
L["Show Defensive Hotkeys"] = "Mostrar atajos"
L["Show Defensive Hotkeys desc"] = "Mostrar texto de atajos en iconos defensivos."
L["Insert Procced Defensives"] = "Insertar defensivos activados"
L["Insert Procced Defensives desc"] = "Mostrar habilidades defensivas activadas (Embestida victoriosa, sanaciones gratuitas) a cualquier nivel de salud."
L["Frame Opacity"] = "Opacidad del marco"
L["Queue Icon Fade"] = "Desvanecimiento de icono de cola"
L["Hide Out of Combat"] = "Ocultar cola fuera de combate"
L["Insert Procced Abilities"] = "Mostrar todas las habilidades activadas"
L["Include All Available Abilities"] = "Incluir habilidades ocultas"
L["Highlight Mode"] = "Modo de resaltado"
L["All Glows"] = "Todos los brillos"
L["Primary Only"] = "Solo principal"
L["Proc Only"] = "Solo proc"
L["No Glows"] = "Sin brillos"
L["Show Key Press Flash"] = "Flash de tecla"
L["Show Key Press Flash desc"] = "Hacer parpadear el icono al pulsar su atajo correspondiente."

-- Blacklist
L["Remove"] = "Eliminar"
L["No spells currently blacklisted"] = "No hay hechizos en lista negra. Mayús+Clic derecho en un hechizo en la cola para agregarlo."
L["Blacklisted Spells"] = "Hechizos en lista negra"
L["Add Spell to Blacklist"] = "Agregar hechizo a la lista negra"

-- Hotkey Overrides
L["Custom Hotkey"] = "Atajo personalizado"
L["No custom hotkeys set"] = "No hay atajos personalizados configurados. Clic derecho en un hechizo para establecer un atajo."
L["Add Hotkey Override"] = "Agregar atajo personalizado"
L["Hotkey"] = "Atajo"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "Introducir el texto del atajo a mostrar (ej: 1, F1, S-2, Ctrl+Q)"
L["Custom Hotkeys"] = "Atajos personalizados"

-- Defensives
L["Enable Defensive Suggestions"] = "Activar sugerencias defensivas"
L["Add to %s"] = "Agregar a %s"

-- Orientation values
L["Up"] = "Arriba"
L["Dn"] = "Abajo"

-- Descriptions
L["General description"] = "Configurar la apariencia y el comportamiento de la cola de hechizos."
L["Icon Layout"] = "Diseño de iconos"
L["Visibility"] = "Visibilidad"
L["Queue Content"] = "Contenido de cola"
L["Appearance"] = "Apariencia"
L["Display"] = "Pantalla"

-- Tooltip mode dropdown
L["Tooltips"] = "Tooltips"
L["Tooltips desc"] = "Cuándo mostrar información de hechizos al pasar el cursor"
L["Never"] = "Nunca"
L["Out of Combat Only"] = "Solo fuera de combate"
L["Always"] = "Siempre"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Modo de visualización"
L["Defensive Display Mode desc"] = "Salud baja: Mostrar solo cuando la salud baja de los umbrales\nSolo en combate: Siempre mostrar en combate\nSiempre: Mostrar en todo momento"
L["When Health Low"] = "Salud baja"
L["In Combat Only"] = "Solo en combate"

-- Detailed descriptions
L["Max Icons desc"] = "Iconos máximos a mostrar (1 = principal, 2+ = cola)"
L["Icon Size desc"] = "Tamaño base de los iconos en píxeles"
L["Spacing desc"] = "Espacio entre iconos en píxeles"
L["Primary Spell Scale desc"] = "Escala para iconos principales y defensivos"
L["Queue Orientation desc"] = "Dirección de crecimiento de la cola"
L["Highlight Mode desc"] = "Qué efectos de brillo mostrar en los iconos de hechizos"
L["Single-Button Assistant Warning"] = "Advertencia: Coloca el Asistente de un solo botón en cualquier barra de acción para que JustAC funcione correctamente."
L["Frame Opacity desc"] = "Transparencia global del marco"
L["Queue Icon Fade desc"] = "Desaturación de iconos en cola (0 = color, 1 = escala de grises)"
L["Hide Out of Combat desc"] = "Ocultar cola fuera de combate"
L["Hide When Mounted"] = "Ocultar en montura"
L["Hide When Mounted desc"] = "Ocultar mientras se usa una montura"
L["Require Hostile Target"] = "Requiere objetivo hostil"
L["Require Hostile Target desc"] = "Solo mostrar con un objetivo hostil seleccionado (solo fuera de combate)"
L["Allow Item Abilities"] = "Allow Item Abilities"
L["Allow Item Abilities desc"] = "Show trinket and on-use item abilities in the offensive queue"
L["Insert Procced Abilities desc"] = "Añadir habilidades con proc brillante a la cola"
L["Include All Available Abilities desc"] = "Incluir habilidades ocultas de macros en recomendaciones"
L["Panel Interaction"] = "Interacción del panel"
L["Panel Interaction desc"] = "Cómo el panel responde a la entrada del ratón"
L["Unlocked"] = "Desbloqueado"
L["Locked"] = "Bloqueado"
L["Click Through"] = "Clic transparente"
L["Enable Defensive Suggestions desc"] = "Mostrar defensivos cuando la salud es baja"
L["Icon Position desc"] = "Posición del icono defensivo"
L["Custom Hotkey desc"] = "Texto personalizado (ej: F1, Ctrl+Q)"
L["Move up desc"] = "Subir prioridad"
L["Move down desc"] = "Bajar prioridad"
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

-- Defensive display options
L["Show Health Bar"] = "Mostrar barra de salud"
L["Show Health Bar desc"] = "Barra de salud compacta junto a la cola"
L["disabled when Defensive Queue is enabled"] = "disabled when Defensive Queue is enabled"
L["Defensive Icon Scale"] = "Escala de icono defensivo"
L["Defensive Icon Scale desc"] = "Escala de iconos defensivos"
L["Defensive Max Icons"] = "Iconos máximos"
L["Defensive Max Icons desc"] = "Iconos defensivos a mostrar (1-3)"
L["Profiles"] = "Perfiles"
L["Profiles desc"] = "Gestión de perfiles"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Cambio por especialización"
L["Auto-switch profile by spec"] = "Cambiar perfil automáticamente por especialización"
L["(No change)"] = "(Sin cambio)"
L["(Disabled)"] = "(Desactivado)"
-- Orientation values (full names)
L["Left to Right"] = "Izquierda a derecha"
L["Right to Left"] = "Derecha a izquierda"
L["Bottom to Top"] = "Abajo hacia arriba"
L["Top to Bottom"] = "Arriba hacia abajo"

-- Target frame anchor
L["Target Frame Anchor"] = "Anclaje al marco de objetivo"
L["Target Frame Anchor desc"] = "Anclar la cola al marco de objetivo predeterminado en lugar de una posición fija en pantalla"
L["Disabled"] = "Desactivado"
L["Top"] = "Arriba"
L["Bottom"] = "Abajo"
L["Left"] = "Izquierda"
L["Right"] = "Derecha"

-- Additional UI strings
L["Hotkey Overrides Info"] = "Atajos personalizados para hechizos.\n|cff00ff00Clic derecho|r para establecer."
L["Blacklist Info"] = "Ocultar hechizos de la cola.\n|cffff6666Shift+Clic derecho|r para alternar."
L["Restore Class Defaults name"] = "Restablecer valores predeterminados de clase"

-- Spell search UI
L["Search spell name or ID"] = "Buscar nombre o ID de hechizo"
L["Search spell desc"] = "Escribir nombre o ID de hechizo (2+ caracteres para buscar)"
L["Select spell to add"] = "Seleccionar un hechizo de los resultados para agregar"
L["Select spell to blacklist"] = "Seleccionar un hechizo de los resultados para la lista negra"
L["Add spell manual desc"] = "Agregar hechizo por ID o nombre exacto"
L["Add spell dropdown desc"] = "Agregar hechizo por ID o nombre exacto (para hechizos fuera de la lista)"
L["Select spell for hotkey"] = "Seleccionar un hechizo de los resultados"
L["Add hotkey desc"] = "Agregar atajo personalizado para el hechizo seleccionado"
L["No matches"] = "Sin resultados - intenta otra búsqueda"
L["Please search and select a spell first"] = "Primero busca y selecciona un hechizo"
L["Please enter a hotkey value"] = "Introduce un valor de atajo"

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
