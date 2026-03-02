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
L["Queue Settings"] = "佇列設定"
L["Defensives"] = "防禦"
L["Priority Lists"] = "優先級列表"
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
L["Queue Orientation"] = "佇列佈局"
L["Gamepad Icon Style"] = "手把圖示樣式"
L["Gamepad Icon Style desc"] = "選擇手把/控制器按鍵的圖示顯示樣式。"
L["Generic"] = "通用 (1/2/3/4)"
L["Xbox"] = "Xbox (A/B/X/Y)"
L["PlayStation"] = "PlayStation (叉/圈/方/三角)"
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
L["Defensive Display Mode"] = "防禦可見性"
L["Defensive Display Mode desc"] = "生命值低時：僅在生命值低於閾值時顯示\n戰鬥中：戰鬥時始終顯示\n始終：一直顯示"
L["When Health Low"] = "生命值低時"
L["In Combat Only"] = "僅戰鬥中"

-- Detailed descriptions
L["Max Icons desc"] = "顯示的最大法術圖示數量（1 = 主要，2+ = 佇列）"
L["Icon Size desc"] = "法術圖示的基本大小（像素）"
L["Spacing desc"] = "圖示之間的間距（像素）"
L["Primary Spell Scale desc"] = "主法術圖示的縮放倍數"
L["Queue Orientation desc"] = "佇列增長方向和側欄位置（防禦技能 + 生命值條）"
L["Highlight Mode desc"] = "法術圖示上顯示的發光效果類型"
L["Single-Button Assistant Warning"] = "警告：請將單鍵助手放置在任意動作條上，以使JustAC正常運作。"
L["Frame Opacity desc"] = "整個框架的全域透明度"
L["Queue Icon Fade desc"] = "佇列圖示的去色程度（0 = 彩色，1 = 灰階）"
L["Hide Out of Combat desc"] = "脫戰時隱藏法術佇列"
L["Hide When Mounted"] = "騎乘時隱藏"
L["Hide When Mounted desc"] = "騎乘時隱藏"
L["Require Hostile Target"] = "需要敵對目標"
L["Require Hostile Target desc"] = "僅在選定敵對單位時顯示（僅脫戰時生效）"
L["Allow Item Abilities"] = "允許物品技能"
L["Allow Item Abilities desc"] = "在進攻佇列中顯示飾品和可使用物品的技能"
L["Insert Procced Abilities desc"] = "將法術書中發光的觸發技能加入佇列"
L["Include All Available Abilities desc"] = "在主要推薦中包含隱藏在巨集條件（如[mod:shift]）後面的法術。"
L["Panel Interaction"] = "面板互動"
L["Panel Interaction desc"] = "控制面板對滑鼠輸入的回應方式"
L["Unlocked"] = "已解鎖"
L["Locked"] = "已鎖定"
L["Click Through"] = "點擊穿透"
L["Enable Defensive Suggestions desc"] = "當生命值低於閾值時顯示防禦法術。"
L["Custom Hotkey desc"] = "要顯示的快捷鍵文字（例如：'F1'、'Ctrl+Q'、'滑鼠4'）"
L["Move up desc"] = "提高優先順序"
L["Move down desc"] = "降低優先順序"
L["Restore Class Defaults desc"] = "將自我治療清單重設為職業預設法術"
L["Restore Cooldowns Defaults desc"] = "將冷卻清單重設為職業預設法術"

-- Additional sections
L["Self-Heal Priority List"] = "自我治療優先清單（優先檢查）"
L["Self-Heal Priority desc"] = "第一個可用的法術將被顯示。拖曳排序設定優先順序。"
L["Restore Class Defaults"] = "恢復職業預設"
L["Major Cooldowns Priority List"] = "大招冷卻優先清單（緊急情況）"
L["Major Cooldowns Priority desc"] = "第一個可用的法術將被顯示。拖曳排序設定優先順序。"

-- Defensive thresholds

-- Defensive display options
L["Show Health Bar"] = "顯示生命條"
L["Show Health Bar desc"] = "在佇列旁顯示緊湊型生命條"
L["disabled when Defensive Queue is enabled"] = "防禦佇列啟用時已停用"
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
-- Compound layout labels (queue direction + sidebar placement)
L["Left, Sidebar Above"] = "向左，側欄在上"
L["Left, Sidebar Below"] = "向左，側欄在下"
L["Right, Sidebar Above"] = "向右，側欄在上"
L["Right, Sidebar Below"] = "向右，側欄在下"
L["Up, Sidebar Left"] = "向上，側欄在左"
L["Up, Sidebar Right"] = "向上，側欄在右"
L["Down, Sidebar Left"] = "向下，側欄在左"
L["Down, Sidebar Right"] = "向下，側欄在右"

-- Target frame anchor
L["Target Frame Anchor"] = "目標框架錨點"
L["Target Frame Anchor desc"] = "將佇列附著在預設目標框架上，而不是固定的螢幕位置"
L["Target Frame Replaced"] = "未偵測到標準目標框架（已被其他插件替換）"
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
L["Display Mode"] = "顯示模式"
L["Display Mode desc"] = "標準佇列顯示主面板，名條覆蓋層將圖示附著到名條上，兩者都啟用所有顯示，停用隱藏全部。"
L["Standard Queue"] = "標準佇列"
L["Both"] = "兩者都"

-- Item Features
L["Items"] = "物品"
L["Allow Items in Spell Lists"] = "允許法術清單中的物品"
L["Allow Items in Spell Lists desc"] = "允許將消耗品（藥水、治療石）新增到防禦法術清單中。啟用後搜尋也會掃描背包和動作條。"
L["Auto-Insert Health Potions"] = "自動插入治療藥水"
L["Auto-Insert Health Potions desc"] = "生命值極低時自動推薦動作條上的治療藥水，即使未手動新增。"

-- Pet Rez/Summon and Pet Heal lists (pet classes only)
L["Pet Rez/Summon Priority List"] = "寵物復活/召喚優先清單"
L["Pet Rez/Summon Priority desc"] = "寵物死亡或不在時顯示。高優先順序——戰鬥中可靠。"
L["Restore Pet Rez Defaults desc"] = "將寵物復活/召喚法術重設為職業預設"
L["Pet Heal Priority List"] = "寵物治療優先清單"
L["Pet Heal Priority desc"] = "寵物生命值低時顯示。寵物生命值在戰鬥中可能被隱藏。"
L["Restore Pet Heal Defaults desc"] = "將寵物治療法術重設為職業預設"
L["Show Pet Health Bar"] = "顯示寵物生命條"
L["Show Pet Health Bar desc"] = "顯示緊湊型寵物生命條（僅限寵物職業）。青色。無寵物時自動隱藏。"

-- Nameplate Overlay (16 keys)
L["Nameplate Overlay"] = "覆蓋層"
L["Nameplate Overlay desc"] = "將佇列圖示直接附著到目標名條上。完全獨立於主面板——可單獨或同時啟用。"
L["Offensive Slots"] = "最大圖示數"
L["Offensive Queue"] = "進攻佇列"
L["Defensive Suggestions"] = "防禦建議"
L["Reverse Anchor"] = "反轉錨點"
L["Reverse Anchor desc"] = "預設DPS圖示出現在名條右側。啟用後放在左側。防禦圖示始終在相反側。"
L["Nameplate Icon Size"] = "圖示大小"
L["Nameplate Show Defensives"] = "顯示防禦圖示"
L["Nameplate Show Defensives desc"] = "在名條的相反側顯示防禦圖示。"
L["Nameplate Defensive Display Mode"] = "防禦可見性"
L["Nameplate Defensive Display Mode desc"] = "僅戰鬥中：僅在戰鬥中顯示防禦圖示。\n始終：一直顯示。"
L["Nameplate Defensive Count"] = "最大圖示數"
L["Interrupt Mode"] = "打斷提醒"
L["Interrupt Mode desc"] = "控制打斷提醒圖示何時出現及建議使用哪個技能。"
L["Sounds"] = "聲音"
L["Interrupt Alert"] = "打斷提示音"
L["Interrupt Mode Disabled"] = "已停用 — 不顯示打斷圖標"
L["Interrupt Mode Kick Only"] = "僅踢技 — 對可打斷施法建議踢技"
L["Interrupt Mode CC Shielded"] = "踢技 + 控制 — 也對不可打斷施法建議暈眩/恐懼"
L["Interrupt Mode CC Prefer"] = "優先控制 — 暈眩優於踢技；Boss使用踢技"
L["Nameplate Show Health Bars"] = "顯示生命條"
L["Nameplate Show Health Bars desc"] = "在防禦圖示上方顯示緊湊型玩家和寵物生命條。無寵物時寵物生命條自動隱藏。無防禦技能可見時自動隱藏。"


-- Reset buttons (5 keys)
L["Reset to Defaults"] = "還原預設"
L["Reset General desc"] = "將所有一般設定重設為預設值。"
L["Reset Offensive desc"] = "重設進攻顯示和內容設定。黑名單不受影響。"
L["Reset Overlay desc"] = "將所有覆蓋層設定重設為預設值。"
L["Reset Defensives desc"] = "重設防禦顯示和行為設定。法術清單不受影響。"

-- Icon Labels (21 keys)
L["Icon Labels"] = "圖示標籤"
L["Hotkey Text"] = "快捷鍵文字"
L["Cooldown Text"] = "冷卻倒數"
L["Charge Count"] = "充能次數"
L["Show"] = "顯示"
L["Font Scale"] = "字型縮放"
L["Font Scale desc"] = "基準字型大小的倍數（1.0 = 預設大小）。"
L["Text Color"] = "顏色"
L["Text Color desc"] = "此文字元素的顏色和透明度。"
L["Text Anchor"] = "位置"
L["Hotkey Anchor desc"] = "快捷鍵標籤在圖示上的顯示位置。"
L["Charge Anchor desc"] = "充能次數在圖示上的顯示位置。"
L["Top Right"] = "右上"
L["Top Left"] = "左上"
L["Top Center"] = "上方置中"
L["Center"] = "置中"
L["Bottom Right"] = "右下"
L["Bottom Left"] = "左下"
L["Bottom Center"] = "下方置中"
L["Reset Icon Labels desc"] = "將所有圖示標籤設定重設為預設值。"

-- Expansion Direction / positioning (5 keys)
L["Expansion Direction"] = "擴展方向"
L["Expansion Direction desc"] = "多欄位時圖示的堆疊方向。水平方向從名條向外擴展。垂直向上/向下在欄位1上方/下方堆疊。"
L["Horizontal (Out)"] = "水平（向外）"
L["Vertical - Up"] = "垂直 - 向上"
L["Vertical - Down"] = "垂直 - 向下"

-- Gap-Closers
L["Gap-Closers"] = "衝鋒技能"
L["Enable Gap-Closer Suggestions"] = "啟用衝鋒技能建議"
L["Enable Gap-Closer Suggestions desc"] = "當目標超出近戰範圍時建議使用衝鋒技能。顯示在第2位置，在觸發效果之前。"
L["Gap-Closer Priority List"] = "衝鋒技能優先級列表"
L["Gap-Closer Priority desc"] = "顯示第一個可用法術。重新排序以設定優先級。"
L["Restore Gap-Closer Defaults desc"] = "將衝鋒技能列表重設為職業和專精的預設法術"
L["No Gap-Closer Spells"] = "未設定衝鋒技能法術。使用下方下拉選單添加，或點擊恢復職業預設。"
L["Reset Gap-Closers desc"] = "重設衝鋒技能設定為預設值。法術清單不受影響。"
L["Show Gap-Closer Glow"] = "顯示衝鋒技能發光"
L["Show Gap-Closer Glow desc"] = "在衝鋒技能圖示上顯示紅色發光效果以突顯其可用性。"
L["Gap-Closer Behavior Note"] = "目標超出範圍時，衝鋒技能會替換位置1。"
L["Gap-Closer Ranged Spec Note"] = "此專精沒有預設衝鋒技能。如有需要可在下方手動新增法術。"
L["Melee Range Reference"] = "近戰範圍參考"
L["Melee Range Spell desc"] = "當此技能超出範圍時觸發衝鋒技能。必須在動作條上。"
L["Melee Range Spell ID"] = "覆蓋法術ID"
L["Melee Range Spell Override desc"] = "法術ID覆蓋（留空 = 自動）"
L["Default"] = "預設"
L["Unknown"] = "未知"
L["None"] = "無"

-- Blacklist Position 1
L["Blacklist Position 1"] = "套用至位置1"
L["Blacklist Position 1 desc"] = "將黑名單也套用到位置1（暴雪的主要建議）。警告：隱藏主法術可能導致循環停滯——暴雪的系統會等待其施放後才繼續。"
