local _, ns = ...

---------------------------------------------------------------------------
-- Bags and bank: item level on equipment, green arrow on upgrades.
-- The item buttons are found through the container frames' own item lists
-- (read only); each button says which bag and slot it shows.
---------------------------------------------------------------------------
local stats = { bagUpdates = 0, bankUpdates = 0, bagButtons = 0, bankButtons = 0 }
ns.bagStats = stats

local function Link(bag, slot)
  if not (bag and slot) then return nil end
  local get = (C_Container and C_Container.GetContainerItemLink) or rawget(_G, "GetContainerItemLink")
  return ns.Str(ns.Call(get, bag, slot))
end

-- Item buttons of a container frame, via its EnumerateValidItems.
-- One list per frame, reused on every poll (no new table each second).
local lists = setmetatable({}, { __mode = "k" })
local current, currentOut
local function Collect(iter, state, start)
  local n = 0
  -- container frames yield (index, button), the bank's pool (button, true)
  for a, b in iter, state, start do
    if n >= 400 then break end
    local button = type(a) == "table" and a or b
    if type(button) == "table" then n = n + 1 currentOut[n] = button end
  end
  for i = #currentOut, n + 1, -1 do currentOut[i] = nil end
end
local function Enumerate() return current:EnumerateValidItems() end

local function Buttons(frame)
  local out = lists[frame]
  if not out then out = {} lists[frame] = out end
  current, currentOut = frame, out
  local ok, iter, state, start = pcall(Enumerate)
  if not ok or type(iter) ~= "function" then wipe(out) return out end
  if not pcall(Collect, iter, state, start) then wipe(out) end
  current, currentOut = nil, nil
  return out
end

local function UpdateButtons(list, bagOf, slotOf, on)
  local count = 0
  for _, button in ipairs(list) do
    if on then
      local bag, slot = bagOf(button), slotOf(button)
      local link = Link(bag, slot)
      if ns.ShowItemLevel(button, link, true, "bags", bag, slot) == true then count = count + 1 end
    else
      ns.HideLevel(button)
    end
  end
  return count
end

local function BagOf(button) return ns.Num(ns.Method(button, "GetBagID")) end
local function SlotOf(button) return ns.Num(ns.Method(button, "GetID")) end

local containerNames = { "ContainerFrameCombinedBags" }
for i = 1, 13 do containerNames[#containerNames + 1] = "ContainerFrame" .. i end

local function UpdateContainer(frame)
  stats.bagUpdates = stats.bagUpdates + 1
  local list = Buttons(frame)
  stats.bagButtons = UpdateButtons(list, BagOf, SlotOf, ns.db.showBags)
end

ns.OnInit(function()
  local found = 0
  for _, name in ipairs(containerNames) do
    local frame = ns.Frame(name)
    if frame then
      found = found + 1
      ns.Watch("bag:" .. name, frame, function() UpdateContainer(frame) end, 1)
    end
  end
  stats.containers = found
end)

---------------------------------------------------------------------------
-- Bank (Forever: Blizzard's bank panel with tabs)
---------------------------------------------------------------------------
local function BankBagOf(button) return ns.Num(ns.Method(button, "GetBankTabID")) end
local function BankSlotOf(button) return ns.Num(ns.Method(button, "GetContainerSlotID")) end

local function UpdateBank(panel)
  stats.bankUpdates = stats.bankUpdates + 1
  local list = Buttons(panel)
  stats.bankButtons = UpdateButtons(list, BankBagOf, BankSlotOf, ns.db.showBank)
end

ns.OnInit(function()
  local panel = ns.Frame("BankPanel") or ns.Frame("BankFrame.BankPanel")
  stats.bank = panel and "found" or "missing"
  if panel then ns.Watch("bank", panel, function() UpdateBank(panel) end, 1) end
  -- tab or page switch reuses the buttons without an event
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "BankPanelMixin.PageInfoChanged", function() ns.Dirty("bank") end, ns)
  end
end)

local function BagsDirty()
  for key in pairs(ns.Watchers()) do
    if key:find("^bag:") or key == "bank" then ns.Dirty(key) end
  end
end
ns.BagsDirty = BagsDirty
ns.On("BAG_UPDATE_DELAYED", BagsDirty)
ns.On("PLAYERBANKSLOTS_CHANGED", BagsDirty)
ns.On("PLAYER_EQUIPMENT_CHANGED", BagsDirty) -- arrows follow what you wear
