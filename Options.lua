local _, ns = ...
local L = ns.L

local category

local function Refresh()
  ns.ClearItemCache()
  ns.MarkEquippedDirty()
  ns.RestyleOverlays()
  ns.Dirty()
  if ns.UpdateGroupWindow then ns.UpdateGroupWindow() end
  if ns.RefreshBagAddons then ns.RefreshBagAddons() end
  if ns.UpdateCheck then ns.UpdateCheck() end
end

local function Points(v) return ("%d"):format(v) end

local function PositionOptions()
  return { { "BOTTOM", L["Bottom"] }, { "TOP", L["Top"] }, { "CENTER", L["Center"] } }
end
local function ColorOptions()
  return { { "quality", L["Item quality"] }, { "white", L["White"] }, { "gap", L["Gap to your average"] } }
end

local PAGES = {
  { title = "Item level", tip = "Where the item level appears on item icons.", items = {
    { header = "Windows" },
    { key = "showCharacter", name = "Character frame", tip = "Item level on every equipped slot.", onChange = Refresh },
    { key = "showAverage", name = "Average on the character frame", tip = "Your average item level in the free bottom left corner of the character frame, below the wrist slot. Blizzard's Forever character frame does not show it. Empty slots count as 0, like the game counts them; Geardon shows how many are empty.", onChange = Refresh },
    { key = "markWeakest", name = "Mark the weakest slot", tip = "The equipped item with the lowest item level gets its number in orange: the best place for your next upgrade.", parent = "showCharacter", onChange = Refresh },
    { key = "behindMarker", name = "Mark slots behind your level", tip = "An equipped item whose item level is far below your level gets its number in red. The tooltip of your average on the character frame and the gear check (/gd check) list these slots.", parent = "showCharacter", onChange = Refresh },
    { key = "behindLevels", kind = "slider", name = "Behind: levels below yours", tip = "An item counts as behind when its item level is more than this many below your level. Default 8: at level 30, items below item level 22.", min = 3, max = 20, step = 1, format = Points, parent = "behindMarker", onChange = Refresh },
    { key = "showInspect", name = "Inspect frame", tip = "Item level per slot and the average of the inspected player. Blizzard's Forever inspect frame shows neither.", onChange = Refresh },
    { key = "showBags", name = "Bags", tip = "Item level on weapons and armor in your bags.", onChange = Refresh },
    { key = "bagAddons", name = "Baganator and Bagnon", tip = "Also in the bags of Baganator and Bagnon. Baganator: choose Geardon in its icon corner options and as its upgrade plugin.", parent = "showBags", onChange = Refresh },
    { key = "boeMarker", name = "BoE in bags", tip = "BoE in the top right corner of items that bind when equipped and are not bound yet.", parent = "showBags", onChange = Refresh },
    { key = "showBank", name = "Bank", tip = "Item level on weapons and armor in your bank.", onChange = Refresh },
    { key = "showLoot", name = "Loot window", tip = "Item level on loot, before you take it.", onChange = Refresh },
    { key = "showFlyout", name = "Equipment flyout", tip = "Item level on the items you can put in a slot, in the flyout of the character frame (hold Alt over a slot). Blizzard marks upgrades there itself.", parent = "showCharacter", onChange = Refresh },
    { key = "showMerchant", name = "Merchant", tip = "Item level and upgrade arrow on gear a merchant sells and in the buyback tab.", onChange = Refresh },
    { key = "showRewards", name = "Quest rewards", tip = "Item level on quest rewards, at the quest giver and in the quest details of the map.", onChange = Refresh },
    { header = "Chat" },
    { key = "chatChange", name = "Chat line when your item level changes", tip = "One line in the chat when your average changes, with the slots that changed, e.g. Item level 24.3 -> 25.1 (Head +6). Not on login; quick swaps make one line.", onChange = Refresh },
  } },
  { title = "Look", tip = "Position, size and colour of the numbers.", items = {
    { header = "All places" },
    { key = "numberColor", kind = "dropdown", name = "Number colour", tip = "Item quality: the colour of the item (green, blue, purple). White: always white. Gap to your average: green above your average, white up to the behind levels below it, orange further below.", options = ColorOptions, onChange = Refresh },
    { key = "showGrey", name = "Also on grey items", tip = "Poor (grey) items are vendor junk; off: no number on them.", onChange = Refresh },
    { key = "minQualityUncommon", name = "Only Uncommon and better", tip = "Numbers only on Uncommon (green), Rare and Epic items; tooltips still show every item.", onChange = Refresh },
    { header = "Character frame" },
    { key = "numberPositionChar", kind = "dropdown", name = "Position (character frame)", tip = "Where the number sits on the slots of the character frame, the inspect frame and the equipment flyout.", options = PositionOptions, onChange = Refresh },
    { key = "numberSizeChar", kind = "slider", name = "Size (character frame)", tip = "Size of the number on the character frame, the inspect frame and the equipment flyout. Default 12.", min = 8, max = 18, step = 1, format = Points, onChange = Refresh },
    { header = "Bags" },
    { key = "numberPosition", kind = "dropdown", name = "Position (bags)", tip = "Where the number sits on items in your bags, your bank and the bags of Baganator and Bagnon.", options = PositionOptions, onChange = Refresh },
    { key = "numberSize", kind = "slider", name = "Size (bags)", tip = "Size of the number in your bags and your bank. Default 12.", min = 8, max = 18, step = 1, format = Points, onChange = Refresh },
    { header = "Loot, rewards and merchants" },
    { key = "numberPositionOther", kind = "dropdown", name = "Position (loot, rewards, merchants)", tip = "Where the number sits on loot, quest rewards and merchant items.", options = PositionOptions, onChange = Refresh },
    { key = "numberSizeOther", kind = "slider", name = "Size (loot, rewards, merchants)", tip = "Size of the number on loot, quest rewards and merchant items. Default 12.", min = 8, max = 18, step = 1, format = Points, onChange = Refresh },
  } },
  { title = "Upgrade arrow", tip = "When an item gets the upgrade arrow.", items = {
    { header = "Arrow" },
    { key = "upgradeArrow", name = "Green arrow on upgrades", tip = "Bags, bank, loot and quest rewards: a green arrow when the item has a higher item level than what you wear in that slot and you can wear it now (class, armor type, level). Rings, trinkets and one-hand weapons compare with the weaker of your two.", onChange = Refresh },
    { key = "arrowUncertain", name = "Yellow arrow when unsure", tip = "In Forever the stats come from item level and quality. A higher item level of a lower quality than yours may be weaker: yellow arrow, the tooltip says why. The same when the item would replace a piece of a set whose bonus you have. Off: no arrow then.", parent = "upgradeArrow", onChange = Refresh },
    { header = "What counts" },
    { key = "arrowWeaponMatch", name = "Only weapon types you use", tip = "A weapon gets the arrow only if you wear one of its type now (e.g. a hunter with a polearm: no arrow on swords; a bow, gun or crossbow for a bow). An empty slot takes any weapon.", onChange = Refresh },
    { key = "arrowBestArmor", name = "Only your best armor type", tip = "Armor gets the arrow only in the best type you can wear: from what you know (mail or plate from level 40 for some classes) and what you wear. Off: anything you can wear.", onChange = Refresh },
    { key = "arrowMainStats", name = "Only items with your main stats", tip = "No arrow on items whose stats none of your class's specs use (e.g. Intellect and Spirit for a rogue). Items without stats keep the arrow.", onChange = Refresh },
  } },
  { title = "Tooltips", tip = "Item level and comparison in item and player tooltips.", items = {
    { header = "Items" },
    { key = "tooltipLevel", name = "Item level line", tip = "Adds Item level 18 to item tooltips, only when the game's tooltip has no item level line of its own.", onChange = Refresh },
    { key = "tooltipCompare", name = "Compare with your item", tip = "Adds the difference to what you wear in that slot, e.g. +3 vs. Head (15). Rings, trinkets and one-hand weapons compare with the weaker of your two, an empty slot counts as 0.", onChange = Refresh },
    { key = "tooltipStatSplit", name = "Stat split", tip = "How the item's primary stats are split, e.g. Agility 60% · Stamina 40%, from the stats the game shows.", onChange = Refresh },
    { header = "Players" },
    { key = "unitTooltip", name = "Item level of players", tip = "Average item level in the tooltip of group members Geardon has inspected or that use Geardon.", onChange = Refresh },
    { key = "mouseoverLevel", name = "Players you point at or target", tip = "Also inspects players outside your group when you point at them or target them, and adds their item level to the open tooltip: out of combat, never while the inspect window is open, one player every few seconds. In combat the last known value is shown.", parent = "unitTooltip", onChange = Refresh },
  } },
  { title = "Group", tip = "Item level of your group: inspected out of combat or sent by Geardon.", items = {
    { header = "Sources" },
    { key = "groupScan", name = "Inspect group members", tip = "Inspects one group member at a time, only out of combat, not while Blizzard's inspect window is open and only players close enough to be seen. A player is inspected again after 10 minutes or when their gear changes.", onChange = Refresh },
    { key = "groupShare", name = "Share with Geardon users", tip = "Sends your average item level to your group and reads what other Geardon users send (one short addon message, only to your group). They then need no inspect.", onChange = Refresh },
    { header = "Window" },
    { kind = "button", name = "Group window", button = "Show / hide", onClick = function() ns.ToggleGroupWindow() end, tip = "Small window with every member's item level, highest first, and the group average. It opens only here or with /gd group." },
    { kind = "button", name = "Window position", button = "Reset", onClick = function() ns.ResetGroupWindow() end, tip = "Puts the group window back to its default place." },
  } },
}

local function Status()
  local lines = {}
  local version = ns.Version()
  if version ~= "?" then lines[#lines + 1] = L["Version %s"]:format(version) end
  local avg = ns.PlayerAverage()
  if avg then lines[#lines + 1] = L["Your item level: %s"]:format(ns.FormatAverage(avg)) end
  local _, _, weak = ns.Average(ns.Equipped())
  local e = weak and ns.Equipped()[weak]
  if e and e.level then
    lines[#lines + 1] = L["Weakest slot: %s (%s)"]:format(ns.SlotLabel(weak), ns.FormatLevel(e.level))
  end
  local behind = ns.BehindSlots and ns.BehindLimit() and #(ns.BehindSlots()) or 0
  if behind > 0 then lines[#lines + 1] = L["Slots behind your level: %d"]:format(behind) end
  return lines
end

local TOOLS = {
  { "Group window", "Show / hide", function() ns.ToggleGroupWindow() end, "Shows or hides the group window. /gd group" },
  { "Inspect group again", "Inspect", function() ns.RescanGroup(true) end, "Forgets inspected values and inspects your group again, out of combat. /gd scan" },
  { "Gear check", "Show / hide", function() ns.ShowCheck() end, "Slots behind your level, dungeons for your level and bag items worse than yours. Only a list: nothing is sold or deleted. /gd check" },
  { "Diagnostics", "Show", function() ns.ShowDiag() end, "Window with a report to copy for bug reports. /gd diag, in the chat: /gd diag chat" },
}
for _, t in ipairs(TOOLS) do t[3] = ns.Guard("tool", t[3]) end

local function Build()
  category = ns.BuildSettings({ name = "Geardon", status = Status, tools = TOOLS, pages = PAGES })
end

function ns.OpenOptions()
  if ns.InCombat() then
    ns.Print(L["Options cannot be opened in combat."])
    return
  end
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  else
    ns.PrintHelp()
  end
end

ns.OnInit(Build)

ns.On("PLAYER_LOGIN", function()
  if ns.firstRun then
    ns.Print(L["Item level is now on your character frame, bags, loot and tooltips. Your group's item level: /gd group. Options: /gd, commands: /gd help."])
  end
end)
