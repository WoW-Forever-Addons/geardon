local _, ns = ...

---------------------------------------------------------------------------
-- Loot window and quest rewards: item level and upgrade arrow on the item
-- icons, so you see before you take it whether it is better than yours.
---------------------------------------------------------------------------
local stats = { lootUpdates = 0, lootItems = 0, rewardUpdates = 0, rewardItems = 0 }
ns.lootStats = stats

---------------------------------------------------------------------------
-- Loot (Blizzard's scrolling loot list; each element knows its loot slot)
---------------------------------------------------------------------------
local function UpdateLoot(lootFrame)
  stats.lootUpdates = stats.lootUpdates + 1
  local box = rawget(lootFrame, "ScrollBox")
  if type(box) ~= "table" then return end
  local elements = {}
  pcall(function()
    box:ForEachFrame(function(element) elements[#elements + 1] = element end)
  end)
  local n = 0
  for _, element in ipairs(elements) do
    local button = rawget(element, "Item")
    if type(button) == "table" then
      local slot = ns.Num(ns.Method(element, "GetSlotIndex"))
      local link = ns.db.showLoot and slot and ns.Str(ns.Call(GetLootSlotLink, slot))
      if ns.ShowItemLevel(button, link or nil, true, "other") == true then n = n + 1 end
    end
  end
  stats.lootItems = n
end

ns.OnInit(function()
  local frame = ns.Frame("LootFrame")
  stats.loot = frame and "found" or "missing"
  if frame then ns.Watch("loot", frame, function() UpdateLoot(frame) end, 0.5) end
end)
ns.On("LOOT_SLOT_CLEARED", function() ns.Dirty("loot") end)

---------------------------------------------------------------------------
-- (26.11.2026, Daniel: "das gleiche, wenn ein item droppt zum rollen") Group loot rolls: Blizzard's GroupLootFrame1 to 4
-- (Need, Greed, Pass); the arrow and item level on the item's icon (IconFrame), the roll's item by frame.rollID. The
-- tooltip on that icon is GameTooltip, so the verdict with its percent shows there as everywhere (Tooltip.lua).
---------------------------------------------------------------------------
stats.rollUpdates, stats.rollItems = 0, 0
local function UpdateRoll(frame)
  stats.rollUpdates = stats.rollUpdates + 1
  local button = rawget(frame, "IconFrame")
  if type(button) ~= "table" then return end
  local roll = ns.Num(rawget(frame, "rollID"))
  local link = ns.db.showLoot and roll and ns.Method(frame, "IsShown") and ns.Str(ns.Call(rawget(_G, "GetLootRollItemLink"), roll))
  if ns.ShowItemLevel(button, link or nil, true, "other") == true then stats.rollItems = stats.rollItems + 1 end
end

ns.OnInit(function()
  local n = 0
  for i = 1, 4 do
    local frame = ns.Frame("GroupLootFrame" .. i)
    if frame then
      n = n + 1
      ns.Watch("roll" .. i, frame, function() UpdateRoll(frame) end, 0.5)
    end
  end
  stats.rolls = n
end)
for _, e in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS" }) do
  ns.On(e, function() for i = 1, 4 do ns.Dirty("roll" .. i) end end)
end

---------------------------------------------------------------------------
-- Quest rewards: quest giver window (QuestInfoRewardsFrame) and the quest
-- details in the map (MapQuestInfoRewardsFrame).
---------------------------------------------------------------------------
local function UpdateRewards(rewards, fromLog)
  stats.rewardUpdates = stats.rewardUpdates + 1
  local buttons = rawget(rewards, "RewardButtons")
  if type(buttons) ~= "table" then return end
  local n = 0
  for _, button in ipairs(buttons) do
    local link
    if ns.db.showRewards and rawget(button, "objectType") == "item" and ns.Method(button, "IsShown") then
      local kind, id = rawget(button, "type"), ns.Num(ns.Method(button, "GetID"))
      if type(kind) == "string" and id then
        local info = ns.Frame("QuestInfoFrame")
        if info and rawget(info, "questLog") then fromLog = true end
        local get = fromLog and rawget(_G, "GetQuestLogItemLink") or rawget(_G, "GetQuestItemLink")
        link = ns.Str(ns.Call(get, kind, id))
      end
    end
    if ns.ShowItemLevel(button, link, true, "other") == true then n = n + 1 end
  end
  stats.rewardItems = n
end

ns.OnInit(function()
  local quest = ns.Frame("QuestInfoRewardsFrame")
  if quest then ns.Watch("rewards", quest, function() UpdateRewards(quest, false) end, 0.5) end
  local map = ns.Frame("MapQuestInfoRewardsFrame")
  if map then ns.Watch("mapRewards", map, function() UpdateRewards(map, true) end, 0.5) end
  stats.rewards = (quest and "quest " or "") .. (map and "map" or "")
end)
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE" }) do
  ns.On(e, function() ns.Dirty("rewards") ns.Dirty("mapRewards") end)
end
