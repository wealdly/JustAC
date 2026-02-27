-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Simplified Chinese (zhCN) - China mainland

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "zhCN")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "常规"
L["System"] = "系统"
L["Offensive"] = "进攻"
L["Queue Settings"] = "队列设置"
L["Defensives"] = "防御"
L["Priority Lists"] = "优先级列表"
L["Blacklist"] = "黑名单"
L["Hotkey Overrides"] = "快捷键"
L["Add"] = "添加"
L["Clear All"] = "全部清除"
L["Clear All Blacklist desc"] = "从黑名单中移除所有法术"
L["Clear All Hotkeys desc"] = "移除所有自定义快捷键"

-- General Options
L["Max Icons"] = "最大图标数"
L["Icon Size"] = "图标大小"
L["Spacing"] = "间距"
L["Primary Spell Scale"] = "主法术缩放"
L["Queue Orientation"] = "队列布局"
L["Gamepad Icon Style"] = "手柄图标样式"
L["Gamepad Icon Style desc"] = "选择手柄/控制器按键的图标显示样式。"
L["Generic"] = "通用 (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (叉/圆/方/三角)"
L["Insert Procced Defensives"] = "插入触发的防御技能"
L["Insert Procced Defensives desc"] = "在任何生命值时显示触发的防御技能（如胜利冲击、免费治疗）。"
L["Frame Opacity"] = "框体透明度"
L["Queue Icon Fade"] = "队列图标淡化"
L["Hide Out of Combat"] = "脱战时隐藏"
L["Insert Procced Abilities"] = "插入触发技能"
L["Include All Available Abilities"] = "包含宏隐藏技能"
L["Highlight Mode"] = "高亮模式"
L["All Glows"] = "全部发光"
L["Primary Only"] = "仅主要"
L["Proc Only"] = "仅触发"
L["No Glows"] = "无发光"
L["Show Key Press Flash"] = "按键闪光"
L["Show Key Press Flash desc"] = "按下对应快捷键时闪烁图标。"

-- Blacklist
L["Remove"] = "移除"
L["No spells currently blacklisted"] = "当前没有被屏蔽的法术。在队列中Shift+右键点击法术进行添加。"
L["Blacklisted Spells"] = "被屏蔽的法术"
L["Add Spell to Blacklist"] = "添加法术到黑名单"

-- Hotkey Overrides
L["Custom Hotkey"] = "自定义快捷键"
L["No custom hotkeys set"] = "没有设置自定义快捷键。右键点击队列中的法术进行设置。"
L["Add Hotkey Override"] = "添加快捷键覆盖"
L["Hotkey"] = "快捷键"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "输入要显示的快捷键文字（例如：1、F1、S-2、Ctrl+Q）"
L["Custom Hotkeys"] = "自定义快捷键"

-- Defensives
L["Enable Defensive Suggestions"] = "启用防御建议"
L["Add to %s"] = "添加到%s"

-- Orientation values
L["Up"] = "上"
L["Dn"] = "下"

-- Descriptions
L["General description"] = "配置法术队列的外观和行为。"
L["Icon Layout"] = "图标布局"
L["Visibility"] = "可见性"
L["Queue Content"] = "队列内容"
L["Appearance"] = "外观"
L["Display"] = "显示"

-- Tooltip mode dropdown
L["Tooltips"] = "提示信息"
L["Tooltips desc"] = "何时显示法术提示"
L["Never"] = "从不"
L["Out of Combat Only"] = "仅脱战时"
L["Always"] = "始终"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "防御可见性"
L["Defensive Display Mode desc"] = "生命值低时：仅在生命值低于阈值时显示\n战斗中：战斗时始终显示\n始终：一直显示"
L["When Health Low"] = "生命值低时"
L["In Combat Only"] = "仅战斗中"

-- Detailed descriptions
L["Max Icons desc"] = "显示的最大法术图标数量（1 = 主要，2+ = 队列）"
L["Icon Size desc"] = "法术图标的基本大小（像素）"
L["Spacing desc"] = "图标之间的间距（像素）"
L["Primary Spell Scale desc"] = "主法术图标的缩放倍数"
L["Queue Orientation desc"] = "队列增长方向和侧栏位置（防御技能 + 生命值条）"
L["Highlight Mode desc"] = "法术图标上显示的发光效果类型"
L["Single-Button Assistant Warning"] = "警告：请将单键助手放置在任意动作条上，以使JustAC正常工作。"
L["Frame Opacity desc"] = "整个框体的全局透明度"
L["Queue Icon Fade desc"] = "队列图标的去色程度（0 = 彩色，1 = 灰度）"
L["Hide Out of Combat desc"] = "脱战时隐藏法术队列"
L["Hide When Mounted"] = "骑乘时隐藏"
L["Hide When Mounted desc"] = "骑乘时隐藏"
L["Require Hostile Target"] = "需要敌对目标"
L["Require Hostile Target desc"] = "仅在选定敌对单位时显示（仅脱战时生效）"
L["Allow Item Abilities"] = "允许物品技能"
L["Allow Item Abilities desc"] = "在进攻队列中显示饰品和可使用物品的技能"
L["Insert Procced Abilities desc"] = "将法术书中发光的触发技能添加到队列"
L["Include All Available Abilities desc"] = "在主要推荐中包含隐藏在宏条件（如[mod:shift]）后面的法术。"
L["Panel Interaction"] = "面板交互"
L["Panel Interaction desc"] = "控制面板对鼠标输入的响应方式"
L["Unlocked"] = "已解锁"
L["Locked"] = "已锁定"
L["Click Through"] = "点击穿透"
L["Enable Defensive Suggestions desc"] = "当生命值低于阈值时显示防御法术。"
L["Custom Hotkey desc"] = "要显示的快捷键文字（例如：'F1'、'Ctrl+Q'、'鼠标4'）"
L["Move up desc"] = "提高优先级"
L["Move down desc"] = "降低优先级"
L["Restore Class Defaults desc"] = "将自我治疗列表重置为职业默认法术"
L["Restore Cooldowns Defaults desc"] = "将冷却列表重置为职业默认法术"

-- Additional sections
L["Self-Heal Priority List"] = "自我治疗优先列表（优先检查）"
L["Self-Heal Priority desc"] = "第一个可用的法术将被显示。拖动排序设置优先级。"
L["Restore Class Defaults"] = "恢复职业默认"
L["Major Cooldowns Priority List"] = "大招冷却优先列表（紧急情况）"
L["Major Cooldowns Priority desc"] = "第一个可用的法术将被显示。拖动排序设置优先级。"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "显示生命条"
L["Show Health Bar desc"] = "在队列旁显示紧凑型生命条"
L["disabled when Defensive Queue is enabled"] = "防御队列启用时已禁用"
L["Defensive Icon Scale"] = "图标缩放"
L["Defensive Icon Scale desc"] = "防御法术图标的缩放倍数"
L["Defensive Max Icons"] = "最大图标数"
L["Defensive Max Icons desc"] = "显示的最大防御图标数量（1-3）"
L["Profiles"] = "配置文件"
L["Profiles desc"] = "角色和专精配置管理"
-- Per-spec profile switching
L["Spec-Based Switching"] = "按专精切换"
L["Auto-switch profile by spec"] = "按专精自动切换配置"
L["(No change)"] = "（不变）"
L["(Disabled)"] = "（已禁用）"
-- Compound layout labels (queue direction + sidebar placement)
L["Left, Sidebar Above"] = "向左，侧栏在上"
L["Left, Sidebar Below"] = "向左，侧栏在下"
L["Right, Sidebar Above"] = "向右，侧栏在上"
L["Right, Sidebar Below"] = "向右，侧栏在下"
L["Up, Sidebar Left"] = "向上，侧栏在左"
L["Up, Sidebar Right"] = "向上，侧栏在右"
L["Down, Sidebar Left"] = "向下，侧栏在左"
L["Down, Sidebar Right"] = "向下，侧栏在右"

-- Target frame anchor
L["Target Frame Anchor"] = "目标框体锚点"
L["Target Frame Anchor desc"] = "将队列附着在默认目标框体上，而不是固定的屏幕位置"
L["Target Frame Replaced"] = "未检测到标准目标框体（已被其他插件替换）"
L["Disabled"] = "已禁用"
L["Top"] = "上方"
L["Bottom"] = "下方"
L["Left"] = "左侧"
L["Right"] = "右侧"

-- Additional UI strings
L["Hotkey Overrides Info"] = "当自动检测失败时设置自定义快捷键文字。\n\n|cff00ff00右键点击|r法术图标设置快捷键。"
L["Blacklist Info"] = "从队列中隐藏法术。\n\n|cffff6666Shift+右键点击|r法术图标切换屏蔽。"
L["Restore Class Defaults name"] = "恢复职业默认"

-- Spell search UI
L["Search spell name or ID"] = "搜索法术名称或ID"
L["Search spell desc"] = "输入法术名称或ID（2个以上字符开始搜索）"
L["Select spell to add"] = "从筛选结果中选择要添加的法术"
L["Select spell to blacklist"] = "从筛选结果中选择要屏蔽的法术"
L["Add spell manual desc"] = "通过ID或精确名称添加法术"
L["Add spell dropdown desc"] = "通过ID或精确名称添加法术（用于不在下拉列表中的法术）"
L["Select spell for hotkey"] = "从筛选结果中选择法术"
L["Add hotkey desc"] = "为所选法术添加快捷键覆盖"
L["No matches"] = "无匹配结果 - 请尝试其他搜索"
L["Please search and select a spell first"] = "请先搜索并选择一个法术"
L["Please enter a hotkey value"] = "请输入快捷键值"

-- Display Mode (Standard Queue / Nameplate Overlay / Both / Disabled)
L["Display Mode"] = "显示模式"
L["Display Mode desc"] = "标准队列显示主面板，姓名板叠加层将图标附着到姓名板上，两者都启用所有显示，禁用隐藏全部。"
L["Standard Queue"] = "标准队列"
L["Both"] = "两者都"

-- Item Features
L["Items"] = "物品"
L["Allow Items in Spell Lists"] = "允许法术列表中的物品"
L["Allow Items in Spell Lists desc"] = "允许将消耗品（药水、治疗石）添加到防御法术列表中。启用后搜索也会扫描背包和动作条。"
L["Auto-Insert Health Potions"] = "自动插入治疗药水"
L["Auto-Insert Health Potions desc"] = "生命值极低时自动推荐动作条上的治疗药水，即使未手动添加。"

-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "宠物复活/召唤优先列表"
L["Pet Rez/Summon Priority desc"] = "宠物死亡或不在时显示。高优先级——战斗中可靠。"
L["Restore Pet Rez Defaults desc"] = "将宠物复活/召唤法术重置为职业默认"
L["Pet Heal Priority List"] = "宠物治疗优先列表"
L["Pet Heal Priority desc"] = "宠物生命值低时显示。宠物生命值在战斗中可能被隐藏。"
L["Restore Pet Heal Defaults desc"] = "将宠物治疗法术重置为职业默认"
L["Show Pet Health Bar"] = "显示宠物生命条"
L["Show Pet Health Bar desc"] = "显示紧凑型宠物生命条（仅限宠物职业）。青色。无宠物时自动隐藏。"

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "叠加层"
L["Nameplate Overlay desc"] = "将队列图标直接附着到目标姓名板上。完全独立于主面板——可单独或同时启用。"
L["Offensive Slots"] = "最大图标数"
L["Offensive Queue"] = "进攻队列"
L["Defensive Suggestions"] = "防御建议"
L["Reverse Anchor"] = "反转锚点"
L["Reverse Anchor desc"] = "默认DPS图标出现在姓名板右侧。启用后放在左侧。防御图标始终在相反侧。"
L["Nameplate Icon Size"] = "图标大小"
L["Nameplate Show Defensives"] = "显示防御图标"
L["Nameplate Show Defensives desc"] = "在姓名板的相反侧显示防御图标。"
L["Nameplate Defensive Display Mode"] = "防御可见性"
L["Nameplate Defensive Display Mode desc"] = "仅战斗中：仅在战斗中显示防御图标。\n始终：一直显示。"
L["Nameplate Defensive Count"] = "最大图标数"
L["Interrupt Mode"] = "打断提醒"
L["Interrupt Mode desc"] = "控制打断提醒图标何时出现及建议使用哪个技能。"
L["Sounds"] = "声音"
L["Interrupt Alert"] = "打断提示音"
L["Interrupt Mode Disabled"] = "已禁用"
L["Interrupt Mode Kick Only"] = "仅打断"
L["Interrupt Mode CC Prefer"] = "小怪优先控制"
L["Nameplate Show Health Bars"] = "显示生命条"
L["Nameplate Show Health Bars desc"] = "在防御图标上方显示紧凑型玩家和宠物生命条。无宠物时宠物生命条自动隐藏。无防御技能可见时自动隐藏。"


-- Reset buttons (5 keys)
L["Reset to Defaults"] = "恢复默认"
L["Reset General desc"] = "将所有常规设置重置为默认值。"
L["Reset Offensive desc"] = "重置进攻显示和内容设置。黑名单不受影响。"
L["Reset Overlay desc"] = "将所有叠加层设置重置为默认值。"
L["Reset Defensives desc"] = "重置防御显示和行为设置。法术列表不受影响。"

-- Icon Labels (21 keys)
L["Icon Labels"] = "图标标签"
L["Hotkey Text"] = "快捷键文本"
L["Cooldown Text"] = "冷却倒计时"
L["Charge Count"] = "充能次数"
L["Show"] = "显示"
L["Font Scale"] = "字体缩放"
L["Font Scale desc"] = "基准字体大小的倍数（1.0 = 默认大小）。"
L["Text Color"] = "颜色"
L["Text Color desc"] = "此文本元素的颜色和透明度。"
L["Text Anchor"] = "位置"
L["Hotkey Anchor desc"] = "快捷键标签在图标上的显示位置。"
L["Charge Anchor desc"] = "充能次数在图标上的显示位置。"
L["Top Right"] = "右上"
L["Top Left"] = "左上"
L["Top Center"] = "上方居中"
L["Center"] = "居中"
L["Bottom Right"] = "右下"
L["Bottom Left"] = "左下"
L["Bottom Center"] = "下方居中"
L["Reset Icon Labels desc"] = "将所有图标标签设置重置为默认值。"

-- Expansion Direction / positioning (5 keys)
L["Expansion Direction"] = "扩展方向"
L["Expansion Direction desc"] = "多槽位时图标的堆叠方向。水平方向从姓名板向外扩展。垂直向上/向下在槽位1上方/下方堆叠。"
L["Horizontal (Out)"] = "水平（向外）"
L["Vertical - Up"] = "垂直 - 向上"
L["Vertical - Down"] = "垂直 - 向下"

-- Gap-Closers
L["Gap-Closers"] = "冲锋技能"
L["Enable Gap-Closer Suggestions"] = "启用冲锋技能建议"
L["Enable Gap-Closer Suggestions desc"] = "当目标超出近战范围时建议使用冲锋技能。显示在第2位置，在触发效果之前。"
L["Gap-Closer Priority List"] = "冲锋技能优先级列表"
L["Gap-Closer Priority desc"] = "显示第一个可用法术。重新排序以设置优先级。"
L["Restore Gap-Closer Defaults desc"] = "将冲锋技能列表重设为职业和专精的默认法术"
L["No Gap-Closer Spells"] = "未配置冲锋技能法术。使用下方下拉菜单添加，或点击恢复职业默认。"
L["Reset Gap-Closers desc"] = "重置冲锋技能设置为默认值。法术列表不受影响。"
L["Show Gap-Closer Glow"] = "显示冲锋技能发光"
L["Show Gap-Closer Glow desc"] = "在冲锋技能图标上显示红色发光效果以突出其可用性。"
L["Gap-Closer Behavior Note"] = "目标超出范围时，冲锋技能会替换位置1。"
L["Gap-Closer Ranged Spec Note"] = "此专精没有默认冲锋技能。如有需要可在下方手动添加法术。"
L["Melee Range Reference"] = "近战范围参考"
L["Melee Range Spell desc"] = "当此技能超出范围时触发冲锋技能。必须在动作条上。"
L["Melee Range Spell ID"] = "覆盖法术ID"
L["Melee Range Spell Override desc"] = "法术ID覆盖（留空 = 自动）"
L["Default"] = "默认"
L["Unknown"] = "未知"
L["None"] = "无"

-- Blacklist Position 1
L["Blacklist Position 1"] = "应用到位置1"
L["Blacklist Position 1 desc"] = "将黑名单也应用于位置1（暴雪的主要建议）。警告：隐藏主法术可能导致循环停滞——暴雪的系统会等待其施放后才继续。"
