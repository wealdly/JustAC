-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Russian (ruRU) - 9.6% of player base

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "ruRU")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "Основное"
L["System"] = "Система"
L["Offensive"] = "Атакующие"
L["Defensives"] = "Защита"
L["Blacklist"] = "Черный список"
L["Hotkey Overrides"] = "Горячие клавиши"
L["Add"] = "Добавить"
L["Clear All"] = "Очистить все"
L["Clear All Blacklist desc"] = "Удалить все заклинания из черного списка"
L["Clear All Hotkeys desc"] = "Удалить все пользовательские горячие клавиши"

-- General Options
L["Max Icons"] = "Макс. иконок"
L["Icon Size"] = "Размер иконок"
L["Spacing"] = "Расстояние"
L["Primary Spell Scale"] = "Масштаб главного заклинания"
L["Queue Orientation"] = "Ориентация очереди"
L["Gamepad Icon Style"] = "Стиль иконок геймпада"
L["Gamepad Icon Style desc"] = "Выберите стиль иконок кнопок для геймпада/контроллера."
L["Generic"] = "Общие (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Крест/Круг/Квадрат/Треугольник)"
L["Show Offensive Hotkeys"] = "Показывать клавиши"
L["Show Offensive Hotkeys desc"] = "Показывать текст горячих клавиш на иконках атакующих заклинаний."
L["Show Defensive Hotkeys"] = "Показывать клавиши"
L["Show Defensive Hotkeys desc"] = "Показывать текст горячих клавиш на защитных иконках."
L["Insert Procced Defensives"] = "Вставить сработавшие защитные"
L["Insert Procced Defensives desc"] = "Показывать сработавшие защитные способности (Победный раж, бесплатные исцеления) при любом уровне здоровья."
L["Frame Opacity"] = "Прозрачность рамки"
L["Queue Icon Fade"] = "Затухание иконок очереди"
L["Hide Out of Combat"] = "Скрыть очередь вне боя"
L["Insert Procced Abilities"] = "Показать все сработавшие способности"
L["Include All Available Abilities"] = "Включить скрытые способности"
L["Highlight Mode"] = "Режим подсветки"
L["All Glows"] = "Все свечения"
L["Primary Only"] = "Только основное"
L["Proc Only"] = "Только проки"
L["No Glows"] = "Без свечения"
L["Show Key Press Flash"] = "Вспышка клавиши"
L["Show Key Press Flash desc"] = "Подсветка иконки при нажатии соответствующей клавиши."

-- Blacklist
L["Remove"] = "Удалить"
L["No spells currently blacklisted"] = "Нет заклинаний в черном списке. Shift+ПКМ на заклинание в очереди, чтобы добавить."
L["Blacklisted Spells"] = "Заклинания в черном списке"
L["Add Spell to Blacklist"] = "Добавить заклинание в черный список"

-- Hotkey Overrides
L["Custom Hotkey"] = "Своя горячая клавиша"
L["No custom hotkeys set"] = "Нет пользовательских горячих клавиш. ПКМ на заклинание, чтобы установить."
L["Add Hotkey Override"] = "Добавить переопределение клавиши"
L["Hotkey"] = "Горячая клавиша"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "Введите текст горячей клавиши (например, 1, F1, S-2, Ctrl+Q)"
L["Custom Hotkeys"] = "Пользовательские клавиши"

-- Defensives
L["Enable Defensive Suggestions"] = "Включить защитные подсказки"
L["Add to %s"] = "Добавить в %s"

-- Orientation values
L["Up"] = "Вверх"
L["Dn"] = "Вниз"

-- Descriptions
L["General description"] = "Настроить внешний вид и поведение очереди заклинаний."
L["Icon Layout"] = "Расположение иконок"
L["Visibility"] = "Видимость"
L["Queue Content"] = "Содержимое очереди"
L["Appearance"] = "Внешний вид"
L["Display"] = "Отображение"

-- Tooltip mode dropdown
L["Tooltips"] = "Подсказки"
L["Tooltips desc"] = "Когда показывать подсказки заклинаний при наведении"
L["Never"] = "Никогда"
L["Out of Combat Only"] = "Только вне боя"
L["Always"] = "Всегда"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Режим отображения"
L["Defensive Display Mode desc"] = "При низком здоровье: Показывать только ниже порогов\nТолько в бою: Всегда показывать в бою\nВсегда: Показывать постоянно"
L["When Health Low"] = "При низком здоровье"
L["In Combat Only"] = "Только в бою"

-- Detailed descriptions
L["Max Icons desc"] = "Максимум иконок (1 = основное, 2+ = очередь)"
L["Icon Size desc"] = "Базовый размер иконок в пикселях"
L["Spacing desc"] = "Расстояние между иконками в пикселях"
L["Primary Spell Scale desc"] = "Множитель масштаба основной иконки"
L["Queue Orientation desc"] = "Направление роста очереди"
L["Highlight Mode desc"] = "Какие эффекты свечения показывать на иконках заклинаний"
L["Single-Button Assistant Warning"] = "Внимание: Разместите Помощник одной кнопки на любой панели действий для работы JustAC."
L["Frame Opacity desc"] = "Общая прозрачность рамки"
L["Queue Icon Fade desc"] = "Обесцвечивание иконок очереди (0 = цвет, 1 = серый)"
L["Hide Out of Combat desc"] = "Скрыть очередь вне боя"
L["Hide When Mounted"] = "Скрыть на транспорте"
L["Hide When Mounted desc"] = "Скрыть на транспортном средстве"
L["Require Hostile Target"] = "Требуется враждебная цель"
L["Require Hostile Target desc"] = "Показывать только при выборе враждебной цели (только вне боя)"
L["Allow Item Abilities"] = "Allow Item Abilities"
L["Allow Item Abilities desc"] = "Show trinket and on-use item abilities in the offensive queue"
L["Insert Procced Abilities desc"] = "Добавить светящиеся проки в очередь"
L["Include All Available Abilities desc"] = "Включить способности за условиями макросов"
L["Panel Interaction"] = "Взаимодействие с панелью"
L["Panel Interaction desc"] = "Как панель реагирует на мышь"
L["Unlocked"] = "Разблокировано"
L["Locked"] = "Заблокировано"
L["Click Through"] = "Сквозной клик"
L["Enable Defensive Suggestions desc"] = "Показывать защитные предложения по здоровью"
L["Icon Position desc"] = "Позиция защитных иконок"
L["Custom Hotkey desc"] = "Текст для отображения как горячая клавиша (например, 'F1', 'Ctrl+Q', 'Мышь4')"
L["Move up desc"] = "Переместить выше в приоритете"
L["Move down desc"] = "Переместить ниже в приоритете"
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

-- Defensive display options
L["Show Health Bar"] = "Показать полосу здоровья"
L["Show Health Bar desc"] = "Компактная полоса здоровья рядом с очередью"
L["disabled when Defensive Queue is enabled"] = "disabled when Defensive Queue is enabled"
L["Defensive Icon Scale"] = "Масштаб защитной иконки"
L["Defensive Icon Scale desc"] = "Множитель масштаба для защитных иконок"
L["Defensive Max Icons"] = "Максимум иконок"
L["Defensive Max Icons desc"] = "Защитных заклинаний одновременно (1-3)"
L["Profiles"] = "Профили"
L["Profiles desc"] = "Управление профилями персонажа и специализации"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Переключение по специализации"
L["Auto-switch profile by spec"] = "Автопереключение профиля по специализации"
L["(No change)"] = "(Без изменений)"
L["(Disabled)"] = "(Отключено)"
-- Orientation values (full names)
L["Left to Right"] = "Слева направо"
L["Right to Left"] = "Справа налево"
L["Bottom to Top"] = "Снизу вверх"
L["Top to Bottom"] = "Сверху вниз"

-- Target frame anchor
L["Target Frame Anchor"] = "Привязка к рамке цели"
L["Target Frame Anchor desc"] = "Привязать очередь к стандартной рамке цели вместо фиксированной позиции на экране"
L["Disabled"] = "Выключено"
L["Top"] = "Сверху"
L["Bottom"] = "Снизу"
L["Left"] = "Слева"
L["Right"] = "Справа"

-- Additional UI strings
L["Hotkey Overrides Info"] = "Установить пользовательскую клавишу.\n\n|cff00ff00Правый клик|r для установки."
L["Blacklist Info"] = "Скрыть заклинания из очереди.\n\n|cffff6666Shift+Правый клик|r для переключения."
L["Restore Class Defaults name"] = "Восстановить настройки класса"

-- Spell search UI
L["Search spell name or ID"] = "Поиск по названию или ID заклинания"
L["Search spell desc"] = "Введите название или ID заклинания (2+ символов для поиска)"
L["Select spell to add"] = "Выберите заклинание из результатов для добавления"
L["Select spell to blacklist"] = "Выберите заклинание из результатов для блокировки"
L["Add spell manual desc"] = "Добавить заклинание по ID или точному названию"
L["Add spell dropdown desc"] = "Добавить заклинание по ID или точному названию (для отсутствующих в списке)"
L["Select spell for hotkey"] = "Выберите заклинание из результатов"
L["Add hotkey desc"] = "Добавить переопределение клавиши для выбранного заклинания"
L["No matches"] = "Нет совпадений - попробуйте другой запрос"
L["Please search and select a spell first"] = "Сначала найдите и выберите заклинание"
L["Please enter a hotkey value"] = "Введите значение горячей клавиши"

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
