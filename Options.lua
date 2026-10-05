local _, ns = ...
local L = ns.L

local category

local function Refresh()
  ns.ClearItemCache()
  ns.MarkEquippedDirty()
  ns.RestyleOverlays()
  ns.Dirty()
  if ns.UpdateGroupWindow then ns.UpdateGroupWindow() end
end

local function Points(v) return ("%d"):format(v) end

local function PositionOptions()
  return { { "BOTTOM", L["Bottom"] }, { "TOP", L["Top"] }, { "CENTER", L["Center"] } }
end
local function ColorOptions()
  return { { "quality", L["Item quality"] }, { "white", L["White"] } }
end

local PAGES = {
  { title = "Item level", tip = "Where the item level appears on item icons.", items = {
    { header = "Windows" },
    { key = "showCharacter", name = "Character frame", tip = "Item level on every equipped slot.", onChange = Refresh },
    { key = "showAverage", name = "Average on the character frame", tip = "Your average item level in the free bottom left corner of the character frame, below the wrist slot. Blizzard's Forever character frame does not show it. Empty slots count as 0, like the game counts them; Geardon shows how many are empty.", onChange = Refresh },
    { key = "markWeakest", name = "Mark the weakest slot", tip = "The equipped item with the lowest item level gets its number in orange: the best place for your next upgrade.", parent = "showCharacter", onChange = Refresh },
    { key = "showInspect", name = "Inspect frame", tip = "Item level per slot and the average of the inspected player. Blizzard's Forever inspect frame shows neither.", onChange = Refresh },
    { key = "showBags", name = "Bags", tip = "Item level on weapons and armor in your bags.", onChange = Refresh },
    { key = "showBank", name = "Bank", tip = "Item level on weapons and armor in your bank.", onChange = Refresh },
    { key = "showLoot", name = "Loot window", tip = "Item level on loot, before you take it.", onChange = Refresh },
    { key = "showFlyout", name = "Equipment flyout", tip = "Item level on the items you can put in a slot, in the flyout of the character frame (hold Alt over a slot). Blizzard marks upgrades there itself.", parent = "showCharacter", onChange = Refresh },
    { key = "showMerchant", name = "Merchant", tip = "Item level and upgrade arrow on gear a merchant sells and in the buyback tab.", onChange = Refresh },
    { key = "showRewards", name = "Quest rewards", tip = "Item level on quest rewards, at the quest giver and in the quest details of the map.", onChange = Refresh },
    { header = "Look" },
    { key = "numberPosition", kind = "dropdown", name = "Position on the icon", tip = "Where the number sits on the item icon.", options = PositionOptions, onChange = Refresh },
    { key = "numberColor", kind = "dropdown", name = "Number colour", tip = "Item quality: the colour of the item (green, blue, purple). White: always white.", options = ColorOptions, onChange = Refresh },
    { key = "numberSize", kind = "slider", name = "Number size", tip = "Size of the number on the icons. Default 12.", min = 8, max = 18, step = 1, format = Points, onChange = Refresh },
    { key = "upgradeArrow", name = "Green arrow on upgrades", tip = "Bags, bank, loot and quest rewards: a green arrow when the item has a higher item level than what you wear in that slot and you can wear it now (class, armor type, level). Rings, trinkets and one-hand weapons compare with the weaker of your two.", onChange = Refresh },
    { key = "showGrey", name = "Also on grey items", tip = "Poor (grey) items are vendor junk; off: no number on them.", onChange = Refresh },
  } },
  { title = "Tooltips", tip = "Item level and comparison in item and player tooltips.", items = {
    { header = "Items" },
    { key = "tooltipLevel", name = "Item level line", tip = "Adds Item level 18 to item tooltips, only when the game's tooltip has no item level line of its own.", onChange = Refresh },
    { key = "tooltipCompare", name = "Compare with your item", tip = "Adds the difference to what you wear in that slot, e.g. +3 vs. Head (15). Rings, trinkets and one-hand weapons compare with the weaker of your two, an empty slot counts as 0.", onChange = Refresh },
    { header = "Players" },
    { key = "unitTooltip", name = "Item level of players", tip = "Average item level in the tooltip of group members Geardon has inspected or that use Geardon.", onChange = Refresh },
  } },
  { title = "Group", tip = "Item level of your group: inspected out of combat or sent by Geardon.", items = {
    { header = "Sources" },
    { key = "groupScan", name = "Inspect group members", tip = "Inspects one group member at a time, only out of combat, not while Blizzard's inspect window is open and only players close enough to be seen. A player is inspected again after 10 minutes or when their gear changes.", onChange = Refresh },
    { key = "groupShare", name = "Share with Geardon users", tip = "Sends your average item level to your group and reads what other Geardon users send (one short addon message, only to your group). They then need no inspect.", onChange = Refresh },
    { header = "Window" },
    { key = "groupWindow", name = "Group window in a party", tip = "Small window with every member's item level, highest first, and the group average. Closing it hides it until your next group; /gd group shows it again.", onChange = Refresh },
    { key = "groupWindowRaid", name = "Also in a raid", tip = "The group window also in a raid (up to 40 rows).", parent = "groupWindow", onChange = Refresh },
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
  return lines
end

local TOOLS = {
  { "Group window", "Show / hide", function() ns.ToggleGroupWindow() end, "Shows or hides the group window. /gd group" },
  { "Inspect group again", "Inspect", function() ns.RescanGroup(true) end, "Forgets inspected values and inspects your group again, out of combat. /gd scan" },
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
    ns.Print(L["Item level is now on your character frame, bags, loot and tooltips; in a group a small window shows everyone's. Options: /gd, commands: /gd help."])
  end
end)
