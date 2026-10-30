local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) One chat line when your average item level changes:
-- "Item level 24.3 -> 25.1 (Head +6)" (option chatChange). Quiet on login and
-- loading screens (the first complete read only sets the baseline), and
-- gear swaps in quick succession (an equipment set, several items from a
-- quest) make one line: every change waits DEBOUNCE seconds for the next.
---------------------------------------------------------------------------
local DEBOUNCE = 2
local QUIET_AFTER_LOGIN = 5
local MAX_SLOTS = 3

local base       -- { avg, levels = { slotName = level } }
local gen, quietUntil, tries = 0, 0, 0
local stats = { lines = 0, checks = 0 }
ns.changeStats = stats

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

-- Snapshot of the counted slots (and the ranged slot), nil while an item is still loading.
local function Snapshot()
  local eq = ns.Equipped()
  local levels = {}
  for name, e in pairs(eq) do
    if e.pending then return nil end
    if name ~= "ShirtSlot" and name ~= "TabardSlot" then levels[name] = e.level end
  end
  if next(levels) == nil then return nil end
  local avg = ns.PlayerAverage()
  if not avg then return nil end
  return { avg = avg, levels = levels }
end

local function Signed(diff)
  if diff > 0 then return "+" .. ns.FormatLevel(diff) end
  return "-" .. ns.FormatLevel(-diff)
end

-- "Head +6, Hands -2" (empty slots count as 0), at most MAX_SLOTS, biggest change first.
local function SlotChanges(old, new)
  local list, seen = {}, {}
  for _, name in ipairs(ns.SLOT_ORDER) do
    if not seen[name] and name ~= "ShirtSlot" and name ~= "TabardSlot" then
      seen[name] = true
      local a, b = old[name] or 0, new[name] or 0
      if math.abs(a - b) >= 0.5 then list[#list + 1] = { name = name, diff = b - a } end
    end
  end
  table.sort(list, function(x, y) return math.abs(x.diff) > math.abs(y.diff) end)
  local out = {}
  for i = 1, math.min(MAX_SLOTS, #list) do
    out[#out + 1] = ("%s %s"):format(ns.SlotLabel(list[i].name), Signed(list[i].diff))
  end
  if #list > MAX_SLOTS then out[#out + 1] = "..." end
  return table.concat(out, ", ")
end

local function Check()
  stats.checks = stats.checks + 1
  local snap = Snapshot()
  if not snap then
    -- items still loading: look again (a few times)
    if tries < 5 then tries = tries + 1 ns.After(1, Check) end
    return
  end
  tries = 0
  if not base or Now() < quietUntil then base = snap return end
  local old = base
  base = snap
  local a, b = ns.FormatAverage(old.avg), ns.FormatAverage(snap.avg)
  if a == b or not ns.db.chatChange then return end
  local slots = SlotChanges(old.levels, snap.levels)
  if slots ~= "" then
    ns.Print(L["Item level %s -> %s (%s)"]:format(a, b, slots))
  else
    ns.Print(L["Item level %s -> %s"]:format(a, b))
  end
  stats.lines = stats.lines + 1
end

local function Changed()
  gen = gen + 1
  local mine = gen
  ns.After(DEBOUNCE, function() if mine == gen then Check() end end)
end

ns.On("PLAYER_EQUIPMENT_CHANGED", Changed)
ns.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", Changed)
ns.On("PLAYER_ENTERING_WORLD", function()
  -- login or loading screen: the next complete read is the new baseline, no line
  quietUntil = Now() + QUIET_AFTER_LOGIN
  base = nil
  Changed()
end)

-- (tests) the current baseline
function ns.ChangeBaseline() return base end

---------------------------------------------------------------------------
-- (1.3.0) One chat line when an upgrade comes into your bags (loot, quest,
-- mail, trade): "Upgrade in your bags: [Helm] (Head +6)" (option chatUpgrade).
-- Every link is told once per session. What is in your bags or worn at login
-- or after a loading screen counts as seen (no lines on login), and so does
-- everything you wear: swapping gear or an equipment set never makes a line.
-- Items that are still loading are looked at when they arrive.
---------------------------------------------------------------------------
local MAX_LINES, MAX_SEEN = 3, 2000
local QUIET_BAGS = 15 -- bags that come late after a loading screen still count as the baseline
local seen, seenCount, ready = {}, 0, false
local upGen, quietBags, bankOpen = 0, 0, false

-- The link without its level and specialization fields (item:id:enchant:gems:suffix:unique:level:spec:...):
-- a level-up changes those in every link, the item is still the same.
local function Key(link)
  local s = link:match("item:([%-%d:]*)")
  if not s then return link end
  local f, i = {}, 0
  for part in (s .. ":"):gmatch("([^:]*):") do
    i = i + 1
    if i ~= 9 and i ~= 10 then f[#f + 1] = part end
    if i > 12 then break end
  end
  return table.concat(f, ":")
end
ns.UpgradeKey = Key -- (tests)

local function See(link)
  local k = Key(link)
  if seen[k] then return end
  seen[k], seenCount = true, seenCount + 1
end

local function SeeWorn()
  for _, e in pairs(ns.Equipped()) do
    if e.link then See(e.link) end
  end
end

local function NumBagSlots()
  local c = Constants and Constants.InventoryConstants
  return (type(c) == "table" and ns.Num(c.NumBagSlots)) or ns.Num(rawget(_G, "NUM_BAG_SLOTS")) or 4
end

-- Every link in your bags now, loaded or not, is seen.
local function Baseline()
  local get = (C_Container and C_Container.GetContainerItemLink) or rawget(_G, "GetContainerItemLink")
  local num = (C_Container and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
  for bag = 0, NumBagSlots() do
    for slot = 1, ns.Num(ns.Call(num, bag)) or 0 do
      local link = ns.Str(ns.Call(get, bag, slot))
      if link then See(link) end
    end
  end
  SeeWorn()
  ready = true
end
ns.BagUpgradeBaseline = Baseline -- (tests)

-- "Head +6", "Head, better stats" (and ", compare in the tooltip" for a yellow arrow).
function ns.UpgradeWhat(v)
  local where = ns.SlotLabel(v.slot)
  local text
  if v.pairGain then
    text = L["both hands +%s"]:format(ns.FormatLevel(math.floor(v.pairGain * 10 + 0.5) / 10))
    return text
  elseif v.diff and v.diff > 0 then
    text = ("%s +%s"):format(where, ns.FormatLevel(math.floor(v.diff * 10 + 0.5) / 10))
  else
    text = L["%s, better stats"]:format(where)
  end
  if v.check then text = text .. ", " .. L["compare in the tooltip"] end
  return text
end

function ns.CheckBagUpgrades()
  stats.bagChecks = (stats.bagChecks or 0) + 1
  if not ready then return end
  -- right after a loading screen, and while the bank is open (moving your own items), nothing is new
  if seenCount > MAX_SEEN or bankOpen or Now() < quietBags then
    if seenCount > MAX_SEEN then wipe(seen) seenCount = 0 end
    Baseline()
    return
  end
  SeeWorn()
  local lines = 0
  for _, g in ipairs(ns.BagGear and ns.BagGear() or {}) do
    if not seen[Key(g.link)] then
      See(g.link)
      local v = ns.db.chatUpgrade and ns.Judge(g.info)
      local up = v and v.upgrade and not (v.check and ns.db.arrowUncertain == false)
      if up and lines < MAX_LINES then
        ns.Print(L["Upgrade in your bags: %s (%s)"]:format(g.link, ns.UpgradeWhat(v)))
        lines = lines + 1
        stats.bagLines = (stats.bagLines or 0) + 1
      end
    end
  end
end

local function BagsChanged()
  upGen = upGen + 1
  local mine = upGen
  ns.After(0.5, function() if mine == upGen then ns.CheckBagUpgrades() end end)
end
ns.On("BAG_UPDATE_DELAYED", BagsChanged)
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID) if ready and ns.BagItemPending and ns.BagItemPending(itemID) then BagsChanged() end end)
ns.On("PLAYER_ENTERING_WORLD", function()
  ready = false
  quietBags = Now() + QUIET_BAGS
  ns.After(QUIET_AFTER_LOGIN, Baseline)
end)
ns.On("BANKFRAME_OPENED", function() bankOpen = true end)
ns.On("BANKFRAME_CLOSED", function() bankOpen = false ns.After(0.6, function() if not bankOpen and ready then Baseline() end end) end)
