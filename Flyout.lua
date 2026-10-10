local _, ns = ...

---------------------------------------------------------------------------
-- Equipment flyout of the character frame (Alt over a slot, or the small
-- arrow next to it): item level on every item you could put in that slot.
-- Blizzard draws its own upgrade arrow there, so ours stays off.
-- Merchants: item level and upgrade arrow on gear for sale and in buyback.
---------------------------------------------------------------------------
local stats = { flyoutUpdates = 0, flyoutItems = 0, merchantUpdates = 0, merchantItems = 0 }
ns.flyoutStats = stats

local function FlyoutLink(location)
  location = ns.Num(location)
  if not location or location < 0 then return nil end
  local special = ns.Num(rawget(_G, "EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION"))
  if special and location >= special then return nil end
  local data = ns.Call(rawget(_G, "EquipmentManager_GetLocationData"), location)
  if type(data) ~= "table" or not ns.Num(data.slot) then return nil end
  if data.isBags then
    local get = (C_Container and C_Container.GetContainerItemLink) or rawget(_G, "GetContainerItemLink")
    return ns.Str(ns.Call(get, data.bag, data.slot))
  end
  return ns.Str(ns.Call(GetInventoryItemLink, "player", data.slot))
end

local function UpdateFlyout(frame)
  stats.flyoutUpdates = stats.flyoutUpdates + 1
  local buttons = rawget(frame, "buttons")
  if type(buttons) ~= "table" then return end
  local n = 0
  for _, button in ipairs(buttons) do
    local link
    if ns.db.showFlyout and ns.db.showCharacter and ns.Method(button, "IsShown") then
      link = FlyoutLink(rawget(button, "location"))
    end
    if ns.ShowItemLevel(button, link, false, "character") == true then n = n + 1 end
  end
  stats.flyoutItems = n
end

ns.OnInit(function()
  local frame = ns.Frame("EquipmentFlyoutFrame")
  stats.flyout = frame and "found" or "missing"
  if frame then ns.Watch("flyout", frame, function() UpdateFlyout(frame) end, 0.3) end
end)

---------------------------------------------------------------------------
-- Merchant (10 items per page, buyback tab 12)
---------------------------------------------------------------------------
local function UpdateMerchant(frame)
  stats.merchantUpdates = stats.merchantUpdates + 1
  local buyback = ns.Num(rawget(frame, "selectedTab")) == 2
  local page = ns.Num(rawget(frame, "page")) or 1
  local per = buyback and (ns.Num(rawget(_G, "BUYBACK_ITEMS_PER_PAGE")) or 12)
    or (ns.Num(rawget(_G, "MERCHANT_ITEMS_PER_PAGE")) or 10)
  local n = 0
  for i = 1, 12 do
    local item = ns.Frame("MerchantItem" .. i)
    local button = item and rawget(item, "ItemButton")
    if type(button) == "table" then
      local link
      if ns.db.showMerchant and i <= per and ns.Method(item, "IsShown") then
        if buyback then
          link = ns.Str(ns.Call(rawget(_G, "GetBuybackItemLink"), i))
        else
          link = ns.Str(ns.Call(rawget(_G, "GetMerchantItemLink"), (page - 1) * per + i))
        end
      end
      if ns.ShowItemLevel(button, link, true, "other") == true then n = n + 1 end
    end
  end
  stats.merchantItems = n
end

ns.OnInit(function()
  local frame = ns.Frame("MerchantFrame")
  stats.merchant = frame and "found" or "missing"
  if frame then ns.Watch("merchant", frame, function() UpdateMerchant(frame) end, 0.5) end
end)
ns.On("MERCHANT_UPDATE", function() ns.Dirty("merchant") end)
