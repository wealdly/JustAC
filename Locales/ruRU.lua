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
L["Queue Settings"] = "Настройки очереди"
L["Defensives"] = "Защитные"
L["Priority Lists"] = "Списки приоритетов"
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
L["Queue Orientation"] = "Макет очереди"
L["Gamepad Icon Style"] = "Стиль иконок геймпада"
L["Gamepad Icon Style desc"] = "Выберите стиль иконок кнопок для геймпада/контроллера."
L["Generic"] = "Общие (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Крест/Круг/Квадрат/Треугольник)"
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
L["Queue Orientation desc"] = "Направление очереди и расположение панели (защитные способности + полоса здоровья)"
L["Highlight Mode desc"] = "Какие эффекты свечения показывать на иконках заклинаний"
L["Single-Button Assistant Warning"] = "Внимание: Разместите Помощник одной кнопки на любой панели действий для работы JustAC."
L["Frame Opacity desc"] = "Общая прозрачность рамки"
L["Queue Icon Fade desc"] = "Обесцвечивание иконок очереди (0 = цвет, 1 = серый)"
L["Hide Out of Combat desc"] = "Скрыть очередь вне боя"
L["Hide When Mounted"] = "Скрыть на транспорте"
L["Hide When Mounted desc"] = "Скрыть на транспортном средстве"
L["Require Hostile Target"] = "Требуется враждебная цель"
L["Require Hostile Target desc"] = "Показывать только при выборе враждебной цели (только вне боя)"
L["Allow Item Abilities"] = "Разрешить способности предметов"
L["Allow Item Abilities desc"] = "Показывать способности аксессуаров и используемых предметов в атакующей очереди"
L["Insert Procced Abilities desc"] = "Добавить светящиеся проки в очередь"
L["Include All Available Abilities desc"] = "Включить способности за условиями макросов"
L["Panel Interaction"] = "Взаимодействие с панелью"
L["Panel Interaction desc"] = "Как панель реагирует на мышь"
L["Unlocked"] = "Разблокировано"
L["Locked"] = "Заблокировано"
L["Click Through"] = "Сквозной клик"
L["Enable Defensive Suggestions desc"] = "Показывать защитные предложения по здоровью"
L["Custom Hotkey desc"] = "Текст для отображения как горячая клавиша (например, 'F1', 'Ctrl+Q', 'Мышь4')"
L["Move up desc"] = "Переместить выше в приоритете"
L["Move down desc"] = "Переместить ниже в приоритете"
L["Restore Class Defaults desc"] = "Сбросить список самолечения на стандартные заклинания для вашего класса"
L["Restore Cooldowns Defaults desc"] = "Сбросить список перезарядок на стандартные заклинания для вашего класса"

-- Additional sections
L["Self-Heal Priority List"] = "Список приоритетов самолечения (проверяется первым)"
L["Self-Heal Priority desc"] = "Быстрые исцеления для ротации."
L["Restore Class Defaults"] = "Восстановить настройки класса"
L["Major Cooldowns Priority List"] = "Список приоритетов больших перезарядок (экстренные)"
L["Major Cooldowns Priority desc"] = "Экстренная защита когда самолечение недоступно."

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "Показать полосу здоровья"
L["Show Health Bar desc"] = "Компактная полоса здоровья рядом с очередью"
L["disabled when Defensive Queue is enabled"] = "отключено при включённой защитной очереди"
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
-- Compound layout labels (queue direction + sidebar placement)
L["Left, Sidebar Above"] = "Влево, панель сверху"
L["Left, Sidebar Below"] = "Влево, панель снизу"
L["Right, Sidebar Above"] = "Вправо, панель сверху"
L["Right, Sidebar Below"] = "Вправо, панель снизу"
L["Up, Sidebar Left"] = "Вверх, панель слева"
L["Up, Sidebar Right"] = "Вверх, панель справа"
L["Down, Sidebar Left"] = "Вниз, панель слева"
L["Down, Sidebar Right"] = "Вниз, панель справа"

-- Target frame anchor
L["Target Frame Anchor"] = "Привязка к рамке цели"
L["Target Frame Anchor desc"] = "Привязать очередь к стандартной рамке цели вместо фиксированной позиции на экране"
L["Target Frame Replaced"] = "Стандартная рамка цели не обнаружена (заменена другим аддоном)"
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
L["Display Mode"] = "Режим отображения"
L["Display Mode desc"] = "Стандартная очередь показывает основную панель, Оверлей табличек привязывает иконки к табличке, Оба режима включает всё, Выключено скрывает всё."
L["Standard Queue"] = "Стандартная очередь"
L["Both"] = "Оба режима"

-- Item Features
L["Items"] = "Предметы"
L["Allow Items in Spell Lists"] = "Разрешить предметы в списках заклинаний"
L["Allow Items in Spell Lists desc"] = "Разрешить добавление расходников (зелья, камни здоровья) в защитные списки. Поиск также проверит сумки и панели действий."
L["Auto-Insert Health Potions"] = "Авто-вставка зелий здоровья"
L["Auto-Insert Health Potions desc"] = "Автоматически предлагать зелье исцеления при критически низком здоровье, даже без ручного добавления."

-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "Воскрешение/Призыв питомца (приоритет)"
L["Pet Rez/Summon Priority desc"] = "Показывается, когда питомец мёртв или отсутствует. Высокий приоритет — надёжно в бою."
L["Restore Pet Rez Defaults desc"] = "Сбросить заклинания воскрешения питомца на стандартные для класса"
L["Pet Heal Priority List"] = "Исцеление питомца (приоритет)"
L["Pet Heal Priority desc"] = "Показывается, когда здоровье питомца низкое. Здоровье питомца может быть скрыто в бою."
L["Restore Pet Heal Defaults desc"] = "Сбросить заклинания исцеления питомца на стандартные для класса"
L["Show Pet Health Bar"] = "Полоса здоровья питомца"
L["Show Pet Health Bar desc"] = "Компактная полоса здоровья питомца (только для классов с питомцем). Бирюзовый цвет. Скрывается без активного питомца."

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "Оверлей"
L["Nameplate Overlay desc"] = "Прикреплять иконки очереди к табличке цели. Полностью независимо от основной панели — можно включить одно или оба."
L["Offensive Slots"] = "Атакующие слоты"
L["Offensive Queue"] = "Атакующая очередь"
L["Defensive Suggestions"] = "Защитные подсказки"
L["Reverse Anchor"] = "Обратная привязка"
L["Reverse Anchor desc"] = "По умолчанию DPS-иконки справа от таблички. Включите для размещения слева. Защитные иконки всегда на противоположной стороне."
L["Nameplate Icon Size"] = "Размер иконок"
L["Nameplate Show Defensives"] = "Показать защитные иконки"
L["Nameplate Show Defensives desc"] = "Показывать защитные иконки на противоположной стороне таблички."
L["Nameplate Defensive Display Mode"] = "Видимость защитных"
L["Nameplate Defensive Display Mode desc"] = "Только в бою: защитные иконки только в бою.\nВсегда: показывать постоянно."
L["Nameplate Defensive Count"] = "Защитные слоты"
L["Show Interrupt Reminder"] = "Напоминание о прерывании"
L["Show Interrupt Reminder desc"] = "Показывать иконку напоминания когда цель произносит прерываемое заклинание."
L["CC Regular Mobs"] = "Предпочитать CC на обычных мобах"
L["CC Regular Mobs desc"] = "На обычных мобах предпочитать контроль толпы (оглушения, обездвиживания) вместо прерывания. На боссах всегда используется прерывание."
L["Nameplate Show Health Bar"] = "Показать полосу здоровья"
L["Nameplate Show Health Bar desc"] = "Компактная полоса здоровья над защитными иконками. Скрывается автоматически без видимых защитных."
L["Health Bar Position"] = "Положение полосы"
L["Health Bar Position desc"] = "Положение полосы здоровья относительно иконок. Снаружи: за дальним краем иконок. Внутри: между табличкой и иконкой 1."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Сбросить настройки"
L["Reset General desc"] = "Сбросить все основные настройки на значения по умолчанию."
L["Reset Offensive desc"] = "Сбросить настройки атаки. Чёрный список не затрагивается."
L["Reset Overlay desc"] = "Сбросить все настройки Оверлея на значения по умолчанию."
L["Reset Defensives desc"] = "Сбросить защитные настройки. Списки заклинаний не затрагиваются."

-- Icon Labels (21 keys)
L["Icon Labels"] = "Надписи на иконках"
L["Icon Labels desc"] = "Настройка размера шрифта, цвета и положения текстовых надписей на иконках. Стандартная очередь и Оверлей табличек настраиваются отдельно."
L["Hotkey Text"] = "Текст клавиши"
L["Cooldown Text"] = "Отсчёт перезарядки"
L["Charge Count"] = "Количество зарядов"
L["Show"] = "Показать"
L["Font Scale"] = "Масштаб шрифта"
L["Font Scale desc"] = "Множитель базового размера шрифта (1.0 = размер по умолчанию)."
L["Text Color"] = "Цвет"
L["Text Color desc"] = "Цвет и прозрачность этого текстового элемента."
L["Text Anchor"] = "Положение"
L["Hotkey Anchor desc"] = "Где на иконке отображается надпись клавиши."
L["Charge Anchor desc"] = "Где на иконке отображается количество зарядов."
L["Top Right"] = "Сверху справа"
L["Top Left"] = "Сверху слева"
L["Top Center"] = "Сверху по центру"
L["Center"] = "По центру"
L["Bottom Right"] = "Снизу справа"
L["Bottom Left"] = "Снизу слева"
L["Bottom Center"] = "Снизу по центру"
L["Reset Icon Labels desc"] = "Сбросить все настройки надписей на иконках к значениям по умолчанию."

-- Expansion Direction / positioning (7 keys)
L["Outside"] = "Снаружи"
L["Inside"] = "Внутри"
L["Expansion Direction"] = "Направление расширения"
L["Expansion Direction desc"] = "Направление укладки иконок при нескольких слотах. Горизонтально расширяется от таблички. Вверх/вниз укладывает над/под слотом 1."
L["Horizontal (Out)"] = "Горизонтально (наружу)"
L["Vertical - Up"] = "Вертикально - Вверх"
L["Vertical - Down"] = "Вертикально - Вниз"

-- Gap-Closers
L["Gap-Closers"] = "Сближение"
L["Enable Gap-Closer Suggestions"] = "Включить подсказки сближения"
L["Enable Gap-Closer Suggestions desc"] = "Предлагает способности сближения, когда цель вне дальности ближнего боя. Показывается на позиции 2, перед проками."
L["Gap-Closer Priority List"] = "Список приоритетов сближения"
L["Gap-Closer Priority desc"] = "Отображается первое доступное заклинание. Измените порядок для установки приоритета."
L["Restore Gap-Closer Defaults desc"] = "Сбросить список сближения до стандартных заклинаний класса и специализации"
L["No Gap-Closer Spells"] = "Заклинания сближения не настроены. Используйте выпадающий список или нажмите «Восстановить настройки класса»."
L["Show Gap-Closer Glow"] = "Подсветка сближения"
L["Show Gap-Closer Glow desc"] = "Красная подсветка иконок сближения, показывающая их доступность."
