-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Spanish - Mexico/Latin America (esMX)
-- Uses same translations as esES; Mexican Spanish UI text is identical

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "esMX")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "General"
L["Settings"] = "Configuración"
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
L["Queue Orientation"] = "Diseño de cola"
L["Gamepad Icon Style"] = "Estilo de icono del mando"
L["Gamepad Icon Style desc"] = "Elegir el estilo de iconos de botones para mandos/controladores."
L["Input Preference"] = "Preferencia de entrada"
L["Input Preference desc"] = "Elegir qué tipo de atajo mostrar. Auto-Detectar muestra atajos de mando cuando está conectado, o atajos de teclado en caso contrario."
L["Auto-Detect"] = "Auto-Detectar"
L["Keyboard"] = "Teclado"
L["Gamepad"] = "Mando"
L["Generic"] = "Genérico (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Cruz/Círculo/Cuadrado/Triángulo)"
L["Insert Procced Defensives"] = "Insertar defensivos activados"
L["Insert Procced Defensives desc"] = "Mostrar habilidades defensivas activadas (Embestida victoriosa, sanaciones gratuitas) a cualquier nivel de salud."
L["Frame Opacity"] = "Opacidad del marco"
L["Queue Icon Fade"] = "Desvanecimiento de icono de cola"
L["Insert Procced Abilities"] = "Mostrar todas las habilidades activadas"
L["Include All Available Abilities"] = "Incluir habilidades ocultas"
L["Highlight Mode"] = "Modo de resaltado"
L["All Glows"] = "Todos los brillos"
L["Primary Only"] = "Solo principal"
L["Proc Only"] = "Solo proc"
L["No Glows"] = "Sin brillos"
L["Show Key Press Flash"] = "Flash de tecla"
L["Show Key Press Flash desc"] = "Hacer parpadear el icono al pulsar su atajo correspondiente."
L["Grey Out While Casting"] = "Oscurecer al lanzar"
L["Grey Out While Casting desc"] = "Desaturar los iconos de la cola mientras lanzas un hechizo. El hechizo lanzado conserva su color."
L["Grey Out While Channeling"] = "Oscurecer al canalizar"
L["Grey Out While Channeling desc"] = "Desaturar los iconos de la cola mientras canalizas un hechizo. El hechizo canalizado conserva su color con una animación de llenado."

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
L["Show Defensive Icons"] = "Mostrar iconos defensivos"
L["Add to %s"] = "Agregar a %s"

-- Orientation values
L["Up"] = "Arriba"
L["Dn"] = "Abajo"

-- Descriptions
L["General description"] = "Ajustes compartidos entre la cola estándar y la superposición."
L["Shared Behavior"] = "Comportamiento compartido"
L["Icon Layout"] = "Diseño de iconos"
L["Visibility"] = "Visibilidad"
L["Appearance"] = "Apariencia"
L["Offensive Display"] = "Visualización ofensiva"
L["Defensive Display"] = "Visualización defensiva"

-- Tooltip mode dropdown
L["Tooltips"] = "Tooltips"
L["Tooltips desc"] = "Cuándo mostrar información de hechizos al pasar el cursor"
L["Never"] = "Nunca"
L["Out of Combat Only"] = "Solo fuera de combate"
L["Always"] = "Siempre"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Visibilidad defensiva"
L["Defensive Display Mode desc"] = "Salud baja: Mostrar solo cuando la salud baja de los umbrales\nSolo en combate: Siempre mostrar en combate\nSiempre: Mostrar en todo momento"
L["When Health Low"] = "Salud baja"
L["In Combat Only"] = "Solo en combate"

-- Detailed descriptions
L["Max Icons desc"] = "Iconos máximos a mostrar (1 = principal, 2+ = cola)"
L["Icon Size desc"] = "Tamaño base de los iconos en píxeles"
L["Spacing desc"] = "Espacio entre iconos en píxeles"
L["Primary Spell Scale desc"] = "Escala para iconos principales y defensivos"
L["Queue Orientation desc"] = "Dirección de la cola y ubicación de la barra lateral (defensivos + barra de vida)"
L["Highlight Mode desc"] = "Qué efectos de brillo mostrar en los iconos de hechizos"
L["Frame Opacity desc"] = "Transparencia global del marco"
L["Queue Icon Fade desc"] = "Desaturación de iconos en cola (0 = color, 1 = escala de grises)"
L["Hide When Mounted"] = "Ocultar en montura"
L["Hide When Mounted desc"] = "Ocultar mientras se usa una montura"
L["Require Hostile Target"] = "Requiere objetivo hostil"
L["Allow Item Abilities"] = "Permitir habilidades de objetos"
L["Allow Item Abilities desc"] = "Mostrar habilidades de abalorios y objetos usables en la cola ofensiva"
L["Insert Procced Abilities desc"] = "Añadir habilidades con proc brillante a la cola"
L["Include All Available Abilities desc"] = "Incluir habilidades ocultas de macros en recomendaciones"
L["Panel Interaction"] = "Interacción del panel"
L["Panel Interaction desc"] = "Cómo el panel responde a la entrada del ratón"
L["Unlocked"] = "Desbloqueado"
L["Locked"] = "Bloqueado"
L["Click Through"] = "Clic transparente"
L["Enable Defensive Suggestions desc"] = "Mostrar defensivos cuando la salud es baja"
L["Custom Hotkey desc"] = "Texto personalizado (ej: F1, Ctrl+Q)"
L["Move up desc"] = "Subir prioridad"
L["Move down desc"] = "Bajar prioridad"
L["Restore Defensive Defaults desc"] = "Restablecer los defensivos de clase"

-- Additional sections
L["Defensive Priority List"] = "Lista de prioridad defensiva"
L["Defensive Priority desc"] = "Orden de prioridad unificado — autocuraciones y enfriamientos en una lista. Reordena para establecer prioridad."
L["Restore Class Defaults"] = "Restablecer valores predeterminados de clase"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bars"] = "Mostrar barras de salud"
L["Show Health Bars desc"] = "Barras de salud compactas del jugador y mascota junto a la cola"
L["Defensive Icon Scale"] = "Escala de icono defensivo"
L["Defensive Icon Scale desc"] = "Escala de iconos defensivos"
L["Defensive Max Icons"] = "Iconos máximos"
L["Defensive Max Icons desc"] = "Iconos defensivos a mostrar"
L["Profiles"] = "Perfiles"
L["Profiles desc"] = "Gestión de perfiles"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Cambio por especialización"
L["Auto-switch profile by spec"] = "Cambiar perfil automáticamente por especialización"
L["(No change)"] = "(Sin cambio)"
L["(Disabled)"] = "(Desactivado)"
-- Compound layout labels (queue direction + sidebar placement)
L["Left, Sidebar Above"] = "Izquierda, barra lateral arriba"
L["Left, Sidebar Below"] = "Izquierda, barra lateral abajo"
L["Right, Sidebar Above"] = "Derecha, barra lateral arriba"
L["Right, Sidebar Below"] = "Derecha, barra lateral abajo"
L["Up, Sidebar Left"] = "Arriba, barra lateral izquierda"
L["Up, Sidebar Right"] = "Arriba, barra lateral derecha"
L["Down, Sidebar Left"] = "Abajo, barra lateral izquierda"
L["Down, Sidebar Right"] = "Abajo, barra lateral derecha"

-- Target frame anchor
L["Target Frame Anchor"] = "Anclaje al marco de objetivo"
L["Target Frame Anchor desc"] = "Anclar la cola al marco de objetivo predeterminado en lugar de una posición fija en pantalla"
L["Target Frame Replaced"] = "Marco de objetivo estándar no detectado (reemplazado por otro addon)"
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
L["Display Mode"] = "Modo de visualización"
L["Display Mode desc"] = "Cola estándar muestra el panel principal, Overlay de placa adjunta iconos a la placa de nombre, Ambos activa todos los modos, Desactivado oculta todo."
L["Standard Queue"] = "Cola estándar"
L["Both"] = "Ambos"
L["Queue Visibility"] = "Visibilidad de la cola"
L["Queue Visibility desc"] = "Siempre: Mostrar en todo momento.\nSolo en combate: Ocultar fuera de combate.\nRequiere objetivo hostil: Mostrar solo con un enemigo atacable seleccionado."


-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "Resurrección/Invocación de mascota (prioridad)"
L["Pet Rez/Summon Priority desc"] = "Se muestra cuando la mascota está muerta o ausente. Alta prioridad — fiable en combate."
L["Restore Pet Rez Defaults desc"] = "Restablecer hechizos de resurrección de mascota a valores predeterminados"
L["Pet Heal Priority List"] = "Sanación de mascota (prioridad)"
L["Pet Heal Priority desc"] = "Se muestra cuando la salud de la mascota es baja. La salud de la mascota puede estar oculta en combate."
L["Restore Pet Heal Defaults desc"] = "Restablecer hechizos de sanación de mascota a valores predeterminados"
L["Show Pet Health Bar"] = "Mostrar barra de salud de mascota"
L["Show Pet Health Bar desc"] = "Barra de salud compacta de mascota (solo clases con mascota). Color turquesa. Se oculta sin mascota activa."

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "Overlay"
L["Offensive Queue"] = "Cola ofensiva"
L["Defensive Queue"] = "Cola defensiva"
L["Reverse Anchor"] = "Invertir anclaje"
L["Reverse Anchor desc"] = "Por defecto los iconos DPS aparecen a la derecha de la placa. Activar para colocarlos a la izquierda. Los iconos defensivos siempre aparecen en el lado opuesto."
L["Nameplate Show Defensives desc"] = "Mostrar iconos defensivos en el lado opuesto de la placa."
L["Interrupt Mode"] = "Recordatorio de interrupción"
L["Interrupt Mode desc"] = "Controla cuándo aparece el icono de recordatorio de interrupción y qué habilidad sugiere."
L["Sounds"] = "Sonidos"
L["Interrupt Alert"] = "Alerta de interrupción"
L["Interrupt Alert Sound desc"] = "Reproducir un sonido cuando el icono de interrupción aparece por primera vez."
L["Interrupt Mode Disabled"] = "Desactivado — Sin iconos de interrupción"
L["Interrupt Mode Kick Only"] = "Solo Kick — Sugerir kick en lanzamientos interrumpibles"
L["Interrupt Mode CC Shielded"] = "Kick + CC — También aturdir/temer lanzamientos protegidos"
L["Interrupt Mode CC Prefer"] = "Preferir CC — Aturdimientos sobre kicks; kick en jefes"
L["Nameplate Show Health Bars desc"] = "Mostrar barras de salud compactas del jugador y mascota sobre los iconos defensivos. La barra de mascota se oculta sin mascota activa. Se oculta automáticamente sin defensivos visibles."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Restablecer valores"
L["Reset General desc"] = "Restablecer todos los ajustes generales a sus valores predeterminados."
L["Reset Layout desc"] = "Restablecer ajustes de diseño a sus valores predeterminados."
L["Reset Offensive Display desc"] = "Restablecer ajustes de visualización ofensiva a sus valores predeterminados."
L["Reset Defensive Display desc"] = "Restablecer ajustes de visualización defensiva a sus valores predeterminados."

-- Icon Labels (21 keys)
L["Icon Labels"] = "Etiquetas de icono"
L["Hotkey Text"] = "Texto de atajo"
L["Cooldown Text"] = "Cuenta regresiva"
L["Charge Count"] = "Cantidad de cargas"
L["Show"] = "Mostrar"
L["Font Scale"] = "Escala de fuente"
L["Font Scale desc"] = "Multiplicador aplicado al tamaño de fuente base (1.0 = tamaño predeterminado)."
L["Text Color"] = "Color"
L["Text Color desc"] = "Color y opacidad de este elemento de texto."
L["Text Anchor"] = "Posición"
L["Hotkey Anchor desc"] = "Dónde aparece la etiqueta de atajo en el icono."
L["Charge Anchor desc"] = "Dónde aparece la cantidad de cargas en el icono."
L["Top Right"] = "Arriba derecha"
L["Top Left"] = "Arriba izquierda"
L["Top Center"] = "Arriba centro"
L["Center"] = "Centro"
L["Bottom Right"] = "Abajo derecha"
L["Bottom Left"] = "Abajo izquierda"
L["Bottom Center"] = "Abajo centro"
L["Reset Icon Labels desc"] = "Restablecer todas las configuraciones de etiquetas de icono a sus valores predeterminados."

-- Expansion Direction / positioning (5 keys)
L["Expansion Direction"] = "Dirección de expansión"
L["Expansion Direction desc"] = "Dirección de apilamiento de iconos. Horizontal se expande desde la placa. Vertical arriba/abajo apila sobre/bajo el espacio 1."
L["Horizontal (Out)"] = "Horizontal (hacia fuera)"
L["Vertical - Up"] = "Vertical - Arriba"
L["Vertical - Down"] = "Vertical - Abajo"

-- Gap-Closers
L["Gap-Closers"] = "Acercadores"
L["Enable Gap-Closer Suggestions"] = "Activar sugerencias de acercamiento"
L["Enable Gap-Closer Suggestions desc"] = "Sugiere habilidades para acercarse cuando el objetivo está fuera del alcance cuerpo a cuerpo. Mostrado en posición 2, antes de los procs."
L["Gap-Closer Priority List"] = "Lista de prioridad de acercadores"
L["Gap-Closer Priority desc"] = "Se muestra el primer hechizo utilizable. Reordenar para establecer prioridad."
L["Restore Gap-Closer Defaults desc"] = "Restablecer la lista de acercadores a los hechizos predeterminados de tu clase y especialización"
L["No Gap-Closer Spells"] = "No hay hechizos acercadores configurados. Usa el desplegable para añadir uno o haz clic en Restaurar valores predeterminados de clase."
L["Reset Gap-Closers desc"] = "Restablecer configuración de acercadores. La lista de hechizos no se ve afectada."
L["Show Gap-Closer Glow"] = "Brillo de acercadores"
L["Show Gap-Closer Glow desc"] = "Muestra un brillo dorado en los íconos acercadores para resaltar que están disponibles."
L["Gap-Closer Behavior Note"] = "Los acercadores reemplazan la posición 1 cuando el objetivo está fuera de alcance."
L["Gap-Closer Ranged Spec Note"] = "Sin acercadores predeterminados para esta especialización. Puedes añadir hechizos manualmente abajo si es necesario."
L["Melee Range Reference"] = "Referencia de alcance cuerpo a cuerpo"
L["Melee Range Spell desc"] = "Los acercadores se activan cuando esta habilidad está fuera de alcance. Debe estar en tu barra de acción."
L["Melee Range Spell Override desc"] = "Anular ID de hechizo (vacío = automático)"
L["Default"] = "Predeterminado"
L["Override"] = "Personalizar"
L["Clear Override"] = "Borrar personalización"
L["Search Spell"] = "Buscar hechizo"
L["Unknown"] = "Desconocido"
L["None"] = "Ninguno"

-- Blacklist Position 1
L["Blacklist Position 1"] = "Aplicar a posición 1"
L["Blacklist Position 1 desc"] = "Aplicar también la lista negra a la posición 1 (la sugerencia principal de Blizzard). Advertencia: ocultar el hechizo principal puede bloquear la rotación — el sistema de Blizzard espera a que se lance."

