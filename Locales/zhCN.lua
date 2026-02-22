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
L["Defensives"] = "防御"
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
L["Queue Orientation"] = "队列方向"
L["Gamepad Icon Style"] = "手柄图标样式"
L["Gamepad Icon Style desc"] = "选择手柄/控制器按键的图标显示样式。"
L["Generic"] = "通用 (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (叉/圆/方/三角)"
L["Show Offensive Hotkeys"] = "显示快捷键"
L["Show Offensive Hotkeys desc"] = "在进攻队列图标上显示快捷键文字。"
L["Show Defensive Hotkeys"] = "显示快捷键"
L["Show Defensive Hotkeys desc"] = "在防御图标上显示快捷键文字。"
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
L["Defensive Display Mode"] = "显示模式"
L["Defensive Display Mode desc"] = "生命值低时：仅在生命值低于阈值时显示\n战斗中：战斗时始终显示\n始终：一直显示"
L["When Health Low"] = "生命值低时"
L["In Combat Only"] = "仅战斗中"

-- Detailed descriptions
L["Max Icons desc"] = "显示的最大法术图标数量（1 = 主要，2+ = 队列）"
L["Icon Size desc"] = "法术图标的基本大小（像素）"
L["Spacing desc"] = "图标之间的间距（像素）"
L["Primary Spell Scale desc"] = "主法术图标的缩放倍数"
L["Queue Orientation desc"] = "队列从主法术延伸的方向"
L["Highlight Mode desc"] = "法术图标上显示的发光效果类型"
L["Single-Button Assistant Warning"] = "警告：请将单键助手放置在任意动作条上，以使JustAC正常工作。"
L["Frame Opacity desc"] = "整个框体的全局透明度"
L["Queue Icon Fade desc"] = "队列图标的去色程度（0 = 彩色，1 = 灰度）"
L["Hide Out of Combat desc"] = "脱战时隐藏法术队列"
L["Hide When Mounted"] = "骑乘时隐藏"
L["Hide When Mounted desc"] = "骑乘时隐藏"
L["Require Hostile Target"] = "需要敌对目标"
L["Require Hostile Target desc"] = "仅在选定敌对单位时显示（仅脱战时生效）"
L["Allow Item Abilities"] = "Allow Item Abilities"
L["Allow Item Abilities desc"] = "Show trinket and on-use item abilities in the offensive queue"
L["Insert Procced Abilities desc"] = "将法术书中发光的触发技能添加到队列"
L["Include All Available Abilities desc"] = "在主要推荐中包含隐藏在宏条件（如[mod:shift]）后面的法术。"
L["Panel Interaction"] = "面板交互"
L["Panel Interaction desc"] = "控制面板对鼠标输入的响应方式"
L["Unlocked"] = "已解锁"
L["Locked"] = "已锁定"
L["Click Through"] = "点击穿透"
L["Enable Defensive Suggestions desc"] = "当生命值低于阈值时显示防御法术。"
L["Icon Position desc"] = "防御图标相对于队列的位置"
L["Custom Hotkey desc"] = "要显示的快捷键文字（例如：'F1'、'Ctrl+Q'、'鼠标4'）"
L["Move up desc"] = "提高优先级"
L["Move down desc"] = "降低优先级"
L["Restore Class Defaults desc"] = "将自我治疗列表重置为职业默认法术"
L["Restore Cooldowns Defaults desc"] = "将冷却列表重置为职业默认法术"

-- Additional sections
L["Icon Position"] = "图标位置"
L["Self-Heal Priority List"] = "自我治疗优先列表（优先检查）"
L["Self-Heal Priority desc"] = "第一个可用的法术将被显示。拖动排序设置优先级。"
L["Restore Class Defaults"] = "恢复职业默认"
L["Major Cooldowns Priority List"] = "大招冷却优先列表（紧急情况）"
L["Major Cooldowns Priority desc"] = "第一个可用的法术将被显示。拖动排序设置优先级。"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "显示生命条"
L["Show Health Bar desc"] = "在队列旁显示紧凑型生命条"
L["disabled when Defensive Queue is enabled"] = "disabled when Defensive Queue is enabled"
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
-- Orientation values (full names)
L["Left to Right"] = "从左到右"
L["Right to Left"] = "从右到左"
L["Bottom to Top"] = "从下到上"
L["Top to Bottom"] = "从上到下"

-- Target frame anchor
L["Target Frame Anchor"] = "目标框体锚点"
L["Target Frame Anchor desc"] = "将队列附着在默认目标框体上，而不是固定的屏幕位置"
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
