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
      if ns.ShowItemLevel(button, link or nil, true) == true then n = n + 1 end
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
    if ns.ShowItemLevel(button, link, true) == true then n = n + 1 end
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
