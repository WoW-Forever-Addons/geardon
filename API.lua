local _, ns = ...

---------------------------------------------------------------------------
-- (1.2.1) For other addons: is an item an upgrade for you? Questdon marks quest rewards with it (pin tooltips,
-- quest book, the reward suggestion) before you take the quest. Same judgement as the arrow on the icons.
--   GeardonAPI.IsUpgrade(item) -> upgrade (true/false), uncertain (true when Geardon shows the yellow arrow:
--   set piece, lower quality, a stat check), or nil while the item is not known yet (asked from the server).
--   item: an item link, "item:<id>" or an item ID.
---------------------------------------------------------------------------
local API = type(rawget(_G, "GeardonAPI")) == "table" and rawget(_G, "GeardonAPI") or {}
GeardonAPI = API
-- (2, 26.11.2026, Daniel: AH lists with the percent) GeardonAPI.UpgradePercent(item) -> percent (whole number, better
--   than what you wear in that slot; nil when the slot is empty, the item goes by item level or a value is unknown),
--   upgrade, uncertain, wearable (false: you cannot wear it or not in your weapon / armor type), emptySlot, soon (the
--   level from which it is an upgrade). nil while the item is not known yet.
API.version = 2

function API.UpgradePercent(item)
  if type(item) == "number" then item = "item:" .. item end
  if type(item) ~= "string" or not ns.Usable(item) then return nil end
  local ok, info = pcall(ns.ItemInfo, item)
  if not ok or type(info) ~= "table" or not ns.IsGear(info) then return nil end
  local ok2, pct, up, uncertain, wearable, empty, soon = pcall(ns.UpgradePercent, info)
  if not ok2 then return nil end
  return pct, up and true or false, uncertain and true or false, wearable and true or false, empty and true or false, soon
end

function API.IsUpgrade(item)
  if type(item) == "number" then item = "item:" .. item end
  if type(item) ~= "string" or not ns.Usable(item) then return nil end
  local ok, info = pcall(ns.ItemInfo, item)
  if not ok or type(info) ~= "table" then return nil end
  local ok2, up, uncertain = pcall(ns.IsUpgrade, info)
  if not ok2 then return nil end
  return up and true or false, uncertain and true or false
end
