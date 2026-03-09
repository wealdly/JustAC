-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Russian (ruRU) - 9.6% of player base

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "ruRU")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "Основное"
L["Settings"] = "Настройки"
L["Offensive"] = "Атакующие"
L["Defensives"] = "Защитные"
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
L["Input Preference"] = "Предпочтение ввода"
L["Input Preference desc"] = "Выберите тип отображаемых клавиш. Авто-определение показывает кнопки геймпада при подключении, иначе клавиатуру."
L["Auto-Detect"] = "Авто-определение"
L["Keyboard"] = "Клавиатура"
L["Gamepad"] = "Геймпад"
L["Generic"] = "Общие (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (Крест/Круг/Квадрат/Треугольник)"
L["Insert Procced Defensives"] = "Вставить сработавшие защитные"
L["Insert Procced Defensives desc"] = "Показывать сработавшие защитные способности (Победный раж, бесплатные исцеления) при любом уровне здоровья."
L["Frame Opacity"] = "Прозрачность рамки"
L["Queue Icon Fade"] = "Затухание иконок очереди"
L["Insert Procced Abilities"] = "Показать все сработавшие способности"
L["Include All Available Abilities"] = "Включить скрытые способности"
L["Highlight Mode"] = "Режим подсветки"
L["All Glows"] = "Все свечения"
L["Primary Only"] = "Только основное"
L["Proc Only"] = "Только проки"
L["No Glows"] = "Без свечения"
L["Show Key Press Flash"] = "Вспышка клавиши"
L["Show Key Press Flash desc"] = "Подсветка иконки при нажатии соответствующей клавиши."
L["Grey Out While Casting"] = "Затемнить при произнесении"
L["Grey Out While Casting desc"] = "Обесцветить иконки очереди при длительном произнесении заклинания. Произносимое заклинание остаётся цветным."
L["Grey Out While Channeling"] = "Затемнить при направлении"
L["Grey Out While Channeling desc"] = "Обесцветить иконки очереди при направлении заклинания. Направляемое заклинание остаётся цветным с анимацией заполнения."

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
L["Show Defensive Icons"] = "Показать защитные иконки"
L["Add to %s"] = "Добавить в %s"

-- Orientation values
L["Up"] = "Вверх"
L["Dn"] = "Вниз"

-- Descriptions
L["General description"] = "Настройки, общие для стандартной очереди и оверлея."
L["Shared Behavior"] = "Общее поведение"
L["Icon Layout"] = "Расположение иконок"
L["Visibility"] = "Видимость"
L["Appearance"] = "Внешний вид"
L["Offensive Display"] = "Отображение атаки"
L["Defensive Display"] = "Отображение защиты"

-- Tooltip mode dropdown
L["Tooltips"] = "Подсказки"
L["Tooltips desc"] = "Когда показывать подсказки заклинаний при наведении"
L["Never"] = "Никогда"
L["Out of Combat Only"] = "Только вне боя"
L["Always"] = "Всегда"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "Видимость защитных"
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
L["Frame Opacity desc"] = "Общая прозрачность рамки"
L["Queue Icon Fade desc"] = "Обесцвечивание иконок очереди (0 = цвет, 1 = серый)"
L["Hide When Mounted"] = "Скрыть на транспорте"
L["Hide When Mounted desc"] = "Скрыть на транспортном средстве"
L["Require Hostile Target"] = "Требуется враждебная цель"
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
L["Restore Defensive Defaults desc"] = "Сбросить список защитных на стандартные заклинания для вашего класса"

-- Additional sections
L["Defensive Priority List"] = "Список приоритетов защитных"
L["Defensive Priority desc"] = "Единый порядок приоритетов — самолечение и перезарядки в одном списке. Перетащите для изменения приоритета."
L["Restore Class Defaults"] = "Восстановить настройки класса"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bars"] = "Показать полосы здоровья"
L["Show Health Bars desc"] = "Компактные полосы здоровья игрока и питомца рядом с очередью"
L["Defensive Icon Scale"] = "Масштаб защитной иконки"
L["Defensive Icon Scale desc"] = "Множитель масштаба для защитных иконок"
L["Defensive Max Icons"] = "Максимум иконок"
L["Defensive Max Icons desc"] = "Защитных заклинаний одновременно"
L["Profiles"] = "Профили"
L["Profiles desc"] = "Управление профилями персонажа и специализации"
-- Per-spec profile switching
L["Spec-Based Switching"] = "Переключение по специализации"
L["Auto-switch profile by spec"] = "Автопереключение профиля по специализации"
L["(No change)"] = "(Без изменений)"
L["(Disabled)"] = "(Отключено)"
-- New character default profile
L["New Character Defaults"] = "Настройки новых персонажей"
L["Use Default profile for new characters"] = "Использовать профиль «По умолчанию» для новых персонажей"
L["Use Default profile for new characters desc"] = "Если включено, новые персонажи начинают с общим профилем «По умолчанию», а не с собственным. Влияет только на персонажей, которые ещё ни разу не загружали JustAC."
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
L["Queue Visibility"] = "Видимость очереди"
L["Queue Visibility desc"] = "Всегда: показывать постоянно.\nТолько в бою: скрывать вне боя.\nВраждебная цель: показывать только при выборе атакуемого врага."


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
L["Offensive Queue"] = "Атакующая очередь"
L["Defensive Queue"] = "Защитная очередь"
L["Reverse Anchor"] = "Обратная привязка"
L["Reverse Anchor desc"] = "По умолчанию DPS-иконки справа от таблички. Включите для размещения слева. Защитные иконки всегда на противоположной стороне."
L["Nameplate Show Defensives desc"] = "Показывать защитные иконки на противоположной стороне таблички."
L["Interrupt Mode"] = "Напоминание прерывания"
L["Interrupt Mode desc"] = "Управляет когда появляется иконка напоминания прерывания и какую способность предлагать."
L["Sounds"] = "Звуки"
L["Interrupt Alert"] = "Оповещение прерывания"
L["Interrupt Alert Sound desc"] = "Воспроизвести звук при первом появлении иконки прерывания."
L["Interrupt Mode Disabled"] = "Выключено — Без иконок прерывания"
L["Interrupt Mode Kick Only"] = "Только кик — Кик на прерываемые касты"
L["Interrupt Mode CC Shielded"] = "Кик + КО — Также оглушение/страх на защищённые касты"
L["Interrupt Mode CC Prefer"] = "Предпочесть КО — Оглушения вместо киков; кик на боссах"
L["Nameplate Show Health Bars desc"] = "Компактные полосы здоровья игрока и питомца над защитными иконками. Полоса питомца скрывается без активного питомца. Автоматически скрывается без видимых защитных."

-- Reset buttons (5 keys)
L["Reset to Defaults"] = "Сбросить настройки"
L["Reset General desc"] = "Сбросить все основные настройки на значения по умолчанию."
L["Reset Layout desc"] = "Сбросить настройки макета на значения по умолчанию."
L["Reset Offensive Display desc"] = "Сбросить настройки отображения атаки на значения по умолчанию."
L["Reset Defensive Display desc"] = "Сбросить настройки отображения защиты на значения по умолчанию."

-- Icon Labels (21 keys)
L["Icon Labels"] = "Надписи на иконках"
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

-- Expansion Direction / positioning (5 keys)
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
L["Reset Gap-Closers desc"] = "Сбросить настройки сближения. Список заклинаний не затрагивается."
L["Show Gap-Closer Glow"] = "Подсветка сближения"
L["Show Gap-Closer Glow desc"] = "Золотая подсветка иконок сближения, показывающая их доступность."
L["Gap-Closer Behavior Note"] = "Заклинания сближения заменяют позицию 1, когда цель вне зоны досягаемости."
L["Gap-Closer Ranged Spec Note"] = "Нет стандартных заклинаний сближения для этой специализации. При необходимости можно добавить заклинания вручную ниже."
L["Melee Range Reference"] = "Ориентир ближнего боя"
L["Melee Range Spell desc"] = "Заклинания сближения срабатывают, когда эта способность вне досягаемости. Должна быть на панели действий."
L["Melee Range Spell Override desc"] = "Переопределение ID заклинания (пусто = авто)"
L["Default"] = "По умолчанию"
L["Override"] = "Переопределить"
L["Clear Override"] = "Сбросить переопределение"
L["Search Spell"] = "Поиск заклинания"
L["Unknown"] = "Неизвестно"
L["None"] = "Нет"

-- Blacklist Position 1
L["Blacklist Position 1"] = "Применить к позиции 1"
L["Blacklist Position 1 desc"] = "Применить чёрный список к позиции 1 (основная рекомендация Blizzard). Внимание: скрытие основного заклинания может остановить ротацию — система Blizzard ждёт его применения."

