-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2024-2025 wealdly
-- JustAC: Traditional Chinese (zhTW) - Taiwan/Hong Kong

local L = LibStub("AceLocale-3.0"):NewLocale("JustAssistedCombat", "zhTW")
if not L then return end

-- General UI
L["JustAssistedCombat"] = "JustAssistedCombat"
L["General"] = "一般"
L["System"] = "系統"
L["Offensive"] = "進攻"
L["Defensives"] = "防禦"
L["Blacklist"] = "黑名單"
L["Hotkey Overrides"] = "快捷鍵"
L["Add"] = "新增"
L["Clear All"] = "全部清除"
L["Clear All Blacklist desc"] = "從黑名單中移除所有法術"
L["Clear All Hotkeys desc"] = "移除所有自訂快捷鍵"

-- General Options
L["Max Icons"] = "最大圖示數"
L["Icon Size"] = "圖示大小"
L["Spacing"] = "間距"
L["Primary Spell Scale"] = "主要法術縮放"
L["Queue Orientation"] = "佇列方向"
L["Gamepad Icon Style"] = "手把圖示樣式"
L["Gamepad Icon Style desc"] = "選擇手把/控制器按鍵的圖示顯示樣式。"
L["Generic"] = "通用 (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (叉/圈/方/三角)"
L["Show Offensive Hotkeys"] = "顯示快捷鍵"
L["Show Offensive Hotkeys desc"] = "在進攻佇列圖示上顯示快捷鍵文字。"
L["Show Defensive Hotkeys"] = "顯示快捷鍵"
L["Show Defensive Hotkeys desc"] = "在防禦圖示上顯示快捷鍵文字。"
L["Insert Procced Defensives"] = "插入觸發的防禦技能"
L["Insert Procced Defensives desc"] = "在任何生命值時顯示觸發的防禦技能（如勝利衝擊、免費治療）。"
L["Frame Opacity"] = "框架透明度"
L["Queue Icon Fade"] = "佇列圖示淡化"
L["Hide Out of Combat"] = "脫戰時隱藏"
L["Insert Procced Abilities"] = "插入觸發技能"
L["Include All Available Abilities"] = "包含巨集隱藏技能"
L["Highlight Mode"] = "高亮模式"
L["All Glows"] = "全部發光"
L["Primary Only"] = "僅主要"
L["Proc Only"] = "僅觸發"
L["No Glows"] = "無發光"
L["Show Key Press Flash"] = "按鍵閃光"
L["Show Key Press Flash desc"] = "按下對應快捷鍵時閃爍圖示。"

-- Blacklist
L["Remove"] = "移除"
L["No spells currently blacklisted"] = "目前沒有被封鎖的法術。在佇列中Shift+右鍵點擊法術進行新增。"
L["Blacklisted Spells"] = "被封鎖的法術"
L["Add Spell to Blacklist"] = "新增法術至黑名單"

-- Hotkey Overrides
L["Custom Hotkey"] = "自訂快捷鍵"
L["No custom hotkeys set"] = "沒有設定自訂快捷鍵。右鍵點擊佇列中的法術進行設定。"
L["Add Hotkey Override"] = "新增快捷鍵覆蓋"
L["Hotkey"] = "快捷鍵"
L["Enter the hotkey text to display (e.g. 1, F1, S-2)"] = "輸入要顯示的快捷鍵文字（例如：1、F1、S-2、Ctrl+Q）"
L["Custom Hotkeys"] = "自訂快捷鍵"

-- Defensives
L["Enable Defensive Suggestions"] = "啟用防禦建議"
L["Add to %s"] = "新增至%s"

-- Orientation values
L["Up"] = "上"
L["Dn"] = "下"

-- Descriptions
L["General description"] = "設定法術佇列的外觀與行為。"
L["Icon Layout"] = "圖示佈局"
L["Visibility"] = "可見性"
L["Queue Content"] = "佇列內容"
L["Appearance"] = "外觀"
L["Display"] = "顯示"

-- Tooltip mode dropdown
L["Tooltips"] = "提示資訊"
L["Tooltips desc"] = "何時顯示法術提示"
L["Never"] = "從不"
L["Out of Combat Only"] = "僅脫戰時"
L["Always"] = "始終"

-- Defensive display mode dropdown
L["Defensive Display Mode"] = "顯示模式"
L["Defensive Display Mode desc"] = "生命值低時：僅在生命值低於閾值時顯示\n戰鬥中：戰鬥時始終顯示\n始終：一直顯示"
L["When Health Low"] = "生命值低時"
L["In Combat Only"] = "僅戰鬥中"

-- Detailed descriptions
L["Max Icons desc"] = "顯示的最大法術圖示數量（1 = 主要，2+ = 佇列）"
L["Icon Size desc"] = "法術圖示的基本大小（像素）"
L["Spacing desc"] = "圖示之間的間距（像素）"
L["Primary Spell Scale desc"] = "主法術圖示的縮放倍數"
L["Queue Orientation desc"] = "佇列從主法術延伸的方向"
L["Highlight Mode desc"] = "法術圖示上顯示的發光效果類型"
L["Single-Button Assistant Warning"] = "警告：請將單鍵助手放置在任意動作條上，以使JustAC正常運作。"
L["Frame Opacity desc"] = "整個框架的全域透明度"
L["Queue Icon Fade desc"] = "佇列圖示的去色程度（0 = 彩色，1 = 灰階）"
L["Hide Out of Combat desc"] = "脫戰時隱藏法術佇列"
L["Hide When Mounted"] = "騎乘時隱藏"
L["Hide When Mounted desc"] = "騎乘時隱藏"
L["Require Hostile Target"] = "需要敵對目標"
L["Require Hostile Target desc"] = "僅在選定敵對單位時顯示（僅脫戰時生效）"
L["Allow Item Abilities"] = "Allow Item Abilities"
L["Allow Item Abilities desc"] = "Show trinket and on-use item abilities in the offensive queue"
L["Insert Procced Abilities desc"] = "將法術書中發光的觸發技能加入佇列"
L["Include All Available Abilities desc"] = "在主要推薦中包含隱藏在巨集條件（如[mod:shift]）後面的法術。"
L["Panel Interaction"] = "面板互動"
L["Panel Interaction desc"] = "控制面板對滑鼠輸入的回應方式"
L["Unlocked"] = "已解鎖"
L["Locked"] = "已鎖定"
L["Click Through"] = "點擊穿透"
L["Enable Defensive Suggestions desc"] = "當生命值低於閾值時顯示防禦法術。"
L["Icon Position desc"] = "防禦圖示相對於佇列的位置"
L["Custom Hotkey desc"] = "要顯示的快捷鍵文字（例如：'F1'、'Ctrl+Q'、'滑鼠4'）"
L["Move up desc"] = "提高優先順序"
L["Move down desc"] = "降低優先順序"
L["Restore Class Defaults desc"] = "將自我治療清單重設為職業預設法術"
L["Restore Cooldowns Defaults desc"] = "將冷卻清單重設為職業預設法術"

-- Additional sections
L["Icon Position"] = "圖示位置"
L["Self-Heal Priority List"] = "自我治療優先清單（優先檢查）"
L["Self-Heal Priority desc"] = "第一個可用的法術將被顯示。拖曳排序設定優先順序。"
L["Restore Class Defaults"] = "恢復職業預設"
L["Major Cooldowns Priority List"] = "大招冷卻優先清單（緊急情況）"
L["Major Cooldowns Priority desc"] = "第一個可用的法術將被顯示。拖曳排序設定優先順序。"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "顯示生命條"
L["Show Health Bar desc"] = "在佇列旁顯示緊湊型生命條"
L["disabled when Defensive Queue is enabled"] = "disabled when Defensive Queue is enabled"
L["Defensive Icon Scale"] = "圖示縮放"
L["Defensive Icon Scale desc"] = "防禦法術圖示的縮放倍數"
L["Defensive Max Icons"] = "最大圖示數"
L["Defensive Max Icons desc"] = "顯示的最大防禦圖示數量（1-3）"
L["Profiles"] = "設定檔"
L["Profiles desc"] = "角色和專精設定管理"
-- Per-spec profile switching
L["Spec-Based Switching"] = "按專精切換"
L["Auto-switch profile by spec"] = "按專精自動切換設定"
L["(No change)"] = "（不變）"
L["(Disabled)"] = "（已停用）"
-- Orientation values (full names)
L["Left to Right"] = "從左到右"
L["Right to Left"] = "從右到左"
L["Bottom to Top"] = "從下到上"
L["Top to Bottom"] = "從上到下"

-- Target frame anchor
L["Target Frame Anchor"] = "目標框架錨點"
L["Target Frame Anchor desc"] = "將佇列附著在預設目標框架上，而不是固定的螢幕位置"
L["Disabled"] = "已停用"
L["Top"] = "上方"
L["Bottom"] = "下方"
L["Left"] = "左側"
L["Right"] = "右側"

-- Additional UI strings
L["Hotkey Overrides Info"] = "當自動偵測失敗時設定自訂快捷鍵文字。\n\n|cff00ff00右鍵點擊|r法術圖示設定快捷鍵。"
L["Blacklist Info"] = "從佇列中隱藏法術。\n\n|cffff6666Shift+右鍵點擊|r法術圖示切換封鎖。"
L["Restore Class Defaults name"] = "恢復職業預設"

-- Spell search UI
L["Search spell name or ID"] = "搜尋法術名稱或ID"
L["Search spell desc"] = "輸入法術名稱或ID（2個以上字元開始搜尋）"
L["Select spell to add"] = "從篩選結果中選擇要新增的法術"
L["Select spell to blacklist"] = "從篩選結果中選擇要封鎖的法術"
L["Add spell manual desc"] = "透過ID或精確名稱新增法術"
L["Add spell dropdown desc"] = "透過ID或精確名稱新增法術（用於不在下拉選單中的法術）"
L["Select spell for hotkey"] = "從篩選結果中選擇法術"
L["Add hotkey desc"] = "為所選法術新增快捷鍵覆蓋"
L["No matches"] = "無符合結果 - 請嘗試其他搜尋"
L["Please search and select a spell first"] = "請先搜尋並選擇一個法術"
L["Please enter a hotkey value"] = "請輸入快捷鍵值"

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
