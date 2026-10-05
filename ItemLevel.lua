local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Item level of items, equipped slots, averages and the comparison with
-- what you wear. In Forever an item stores only item level, quality and its
-- stat split; the game computes the stats from them, so the item level is
-- the item's strength.
-- Only game functions that return plain values (no secret values) are used:
-- C_Item.GetDetailedItemLevelInfo, C_Item.GetCurrentItemLevel,
-- C_Item.GetItemInfo(Instant), C_PlayerInfo.CanUseItem.
---------------------------------------------------------------------------

-- Inventory slots (fallback numbers; GetInventorySlotInfo wins when it answers)
local SLOT_FALLBACK = {
  HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5, WaistSlot = 6,
  LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12,
  Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17,
  RangedSlot = 18, TabardSlot = 19,
}
ns.SLOT = {}
for name, id in pairs(SLOT_FALLBACK) do ns.SLOT[name] = id end

-- Order of the character and inspect frames (button name suffixes).
ns.SLOT_ORDER = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot",
  "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
  "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

-- Slots that count for the average (like Blizzard: 16 slots, no shirt, tabard
-- or ranged; a two-hand weapon counts twice while the off hand is empty).
local AVG_SLOTS = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot", "HandsSlot",
  "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
  "MainHandSlot", "SecondaryHandSlot" }
ns.AVG_SLOTS = AVG_SLOTS
ns.AVG_COUNT = #AVG_SLOTS

-- Game names of the slots (localized global strings), English fallback.
local SLOT_LABEL = {
  HeadSlot = { "HEADSLOT", "Head" }, NeckSlot = { "NECKSLOT", "Neck" }, ShoulderSlot = { "SHOULDERSLOT", "Shoulder" },
  BackSlot = { "BACKSLOT", "Back" }, ChestSlot = { "CHESTSLOT", "Chest" }, ShirtSlot = { "SHIRTSLOT", "Shirt" },
  TabardSlot = { "TABARDSLOT", "Tabard" }, WristSlot = { "WRISTSLOT", "Wrist" }, HandsSlot = { "HANDSSLOT", "Hands" },
  WaistSlot = { "WAISTSLOT", "Waist" }, LegsSlot = { "LEGSSLOT", "Legs" }, FeetSlot = { "FEETSLOT", "Feet" },
  Finger0Slot = { "FINGER0SLOT", "Finger" }, Finger1Slot = { "FINGER1SLOT", "Finger" },
  Trinket0Slot = { "TRINKET0SLOT", "Trinket" }, Trinket1Slot = { "TRINKET1SLOT", "Trinket" },
  MainHandSlot = { "MAINHANDSLOT", "Main Hand" }, SecondaryHandSlot = { "SECONDARYHANDSLOT", "Off Hand" },
  RangedSlot = { "RANGEDSLOT", "Ranged" },
}
local SLOT_NAME_BY_ID = {}
function ns.SlotLabel(slotName)
  local e = SLOT_LABEL[slotName]
  if not e then return tostring(slotName) end
  local g = ns.Str(rawget(_G, e[1]))
  return g or L[e[2]]
end
function ns.SlotLabelByID(id) return ns.SlotLabel(SLOT_NAME_BY_ID[id]) end
function ns.SlotNameByID(id) return id and SLOT_NAME_BY_ID[id] or nil end

function ns.ResolveSlots()
  for name in pairs(SLOT_FALLBACK) do
    local id = ns.Num(ns.Results(GetInventorySlotInfo, name))
    if id and id > 0 then ns.SLOT[name] = id end
  end
  wipe(SLOT_NAME_BY_ID)
  for name, id in pairs(ns.SLOT) do SLOT_NAME_BY_ID[id] = name end
end
ns.ResolveSlots()
ns.OnInit(ns.ResolveSlots)

-- Where an equip location goes. "WEAPON" depends on dual wield.
local INVTYPE = {
  INVTYPE_HEAD = { "HeadSlot" }, INVTYPE_NECK = { "NeckSlot" }, INVTYPE_SHOULDER = { "ShoulderSlot" },
  INVTYPE_CHEST = { "ChestSlot" }, INVTYPE_ROBE = { "ChestSlot" }, INVTYPE_WAIST = { "WaistSlot" },
  INVTYPE_LEGS = { "LegsSlot" }, INVTYPE_FEET = { "FeetSlot" }, INVTYPE_WRIST = { "WristSlot" },
  INVTYPE_HAND = { "HandsSlot" }, INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
  INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" }, INVTYPE_CLOAK = { "BackSlot" },
  INVTYPE_WEAPON = "WEAPON", INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
  INVTYPE_2HWEAPON = "TWOHAND", INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
  INVTYPE_SHIELD = { "SecondaryHandSlot" }, INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
  INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED", INVTYPE_RELIC = "RANGED",
}
ns.INVTYPE = INVTYPE

---------------------------------------------------------------------------
-- Item facts from a link (or item ID). Cached per link; nil while the game
-- has not loaded the item yet (it is requested, GET_ITEM_INFO_RECEIVED
-- refreshes the frames).
---------------------------------------------------------------------------
local cache, cacheSize = {}, 0
local stats = { lookups = 0, pending = 0, noLevel = 0 }
ns.itemStats = stats

local function ItemIDOf(link)
  if type(link) == "number" then return link end
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local function Request(itemID)
  if not itemID then return end
  stats.pending = stats.pending + 1
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

function ns.ItemInfo(link)
  if link == nil or not ns.Usable(link) then return nil end
  local hit = cache[link]
  if hit then return hit end
  stats.lookups = stats.lookups + 1
  local itemID = ItemIDOf(link)
  if not itemID then return nil end
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local _, _, _, equipLoc, _, classID, subclassID = ns.Results(getInstant, link)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, quality, baseLevel, reqLevel = ns.Results(getInfo, link)
  if not ns.Str(name) then Request(itemID) return nil end
  local level = ns.Num(ns.Results(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link))
    or ns.Num(baseLevel)
  if not level then stats.noLevel = stats.noLevel + 1 end
  local info = {
    itemID = itemID, level = level, quality = ns.Num(quality), reqLevel = ns.Num(reqLevel) or 0,
    equipLoc = ns.Str(equipLoc), classID = ns.Num(classID), subclassID = ns.Num(subclassID),
  }
  if cacheSize > 3000 then wipe(cache) cacheSize = 0 end
  cache[link] = info
  cacheSize = cacheSize + 1
  return info
end

function ns.ClearItemCache() wipe(cache) cacheSize = 0 end

-- Equipment that gets a number: weapons and armor with an equip slot that
-- counts (no shirt, tabard, bag, ammo, quiver), grey only with the option.
function ns.IsGear(info)
  if type(info) ~= "table" or not info.level or info.level <= 1 then return false end
  if info.classID ~= 2 and info.classID ~= 4 then return false end
  if not (info.equipLoc and INVTYPE[info.equipLoc]) then return false end
  if info.quality == 0 and not (ns.db and ns.db.showGrey) then return false end
  return true
end

local qualityCache = {}
function ns.QualityColor(quality)
  quality = ns.Num(quality) or 1
  local c = qualityCache[quality]
  if c then return c[1], c[2], c[3] end
  local r, g, b = ns.QualityColorRaw(quality)
  qualityCache[quality] = { r, g, b }
  return r, g, b
end

function ns.QualityColorRaw(quality)
  if C_Item and C_Item.GetItemQualityColor then
    local r, g, b = ns.Results(C_Item.GetItemQualityColor, quality)
    if ns.Num(r) and ns.Num(g) and ns.Num(b) then return r, g, b end
  end
  local c = rawget(_G, "ITEM_QUALITY_COLORS")
  c = type(c) == "table" and c[quality]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  return 1, 1, 1
end

---------------------------------------------------------------------------
-- Your own equipment. Read again after PLAYER_EQUIPMENT_CHANGED.
---------------------------------------------------------------------------
local equipped, equippedDirty = {}, true  -- slotName -> { level, quality, link, equipLoc }

-- Right after login or a loading screen the game may not hand out the links
-- of your gear yet: an empty or incomplete read is repeated (at most once a
-- second) instead of being kept until the next gear change.
local lastIncomplete = 0
local function ReadEquipped()
  wipe(equipped)
  local items, missing = 0, 0
  for _, name in ipairs(ns.SLOT_ORDER) do
    local id = ns.SLOT[name]
    local link = id and ns.Str(ns.Call(GetInventoryItemLink, "player", id))
    if link then
      local info = ns.ItemInfo(link)
      local level = info and info.level
      -- the item location knows upgrades that a link may not carry
      if ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetCurrentItemLevel then
        local ok, loc = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, id)
        local cur = ok and loc and ns.Num(ns.Call(C_Item.GetCurrentItemLevel, loc))
        if cur and cur > 0 then level = cur end
      end
      equipped[name] = { link = link, level = level, quality = info and info.quality, equipLoc = info and info.equipLoc,
        pending = info == nil or level == nil }
      items = items + 1
    elseif id and ns.Call(GetInventoryItemTexture, "player", id) ~= nil then
      missing = missing + 1 -- an item is there, its link not yet
    end
  end
  equippedDirty = items == 0 or missing > 0
  if equippedDirty then lastIncomplete = ns.Num(ns.Value(GetTime)) or 0 end
end

-- Goes up whenever arrows or numbers may change for the same item (gear,
-- level, options): overlays skip buttons whose item and version are unchanged.
ns.version = 1
function ns.BumpVersion() ns.version = ns.version + 1 end
ns.On("PLAYER_EQUIPMENT_CHANGED", ns.BumpVersion)
ns.On("PLAYER_LEVEL_UP", ns.BumpVersion)
ns.On("PLAYER_LEVEL_CHANGED", ns.BumpVersion)       -- fires after the level is updated
ns.On("SKILL_LINES_CHANGED", ns.BumpVersion)        -- weapon skills, armor, dual wield
ns.On("LEARNED_SPELL_IN_SKILL_LINE", ns.BumpVersion)

function ns.Equipped()
  if equippedDirty then
    local now = ns.Num(ns.Value(GetTime)) or 0
    -- a read that came back empty or incomplete is tried again after a second
    if next(equipped) == nil and lastIncomplete > 0 and now - lastIncomplete < 1 then return equipped end
    local before = next(equipped) ~= nil
    ReadEquipped()
    if not before and next(equipped) ~= nil then ns.BumpVersion() end
  end
  return equipped
end
function ns.MarkEquippedDirty() equippedDirty = true end
ns.On("PLAYER_EQUIPMENT_CHANGED", function() equippedDirty = true end)
ns.On("PLAYER_ENTERING_WORLD", function() equippedDirty = true lastIncomplete = 0 ns.BumpVersion() end)
ns.On("UNIT_INVENTORY_CHANGED", function(_, unit)
  if unit == "player" then equippedDirty = true end
end)
ns.On("GET_ITEM_INFO_RECEIVED", function()
  -- only when one of your own items was still loading do the arrows change
  for _, e in pairs(equipped) do
    if e.pending then equippedDirty = true ns.BumpVersion() return end
  end
end)

-- Average of a slotName -> { level, equipLoc } table (own or inspected).
-- Returns average, counted slots with an item, and the weakest slot name.
function ns.Average(levels)
  local sum, have, weakest, weakLevel = 0, 0, nil, nil
  for _, name in ipairs(AVG_SLOTS) do
    local e = levels[name]
    local lv = e and ns.Num(e.level)
    if lv then
      sum, have = sum + lv, have + 1
      if not weakLevel or lv < weakLevel then weakest, weakLevel = name, lv end
    end
  end
  local mh, oh = levels.MainHandSlot, levels.SecondaryHandSlot
  if mh and mh.level and not oh and mh.equipLoc == "INVTYPE_2HWEAPON" then
    sum = sum + mh.level
    have = have + 1
  end
  if have == 0 then return nil, 0, nil end
  return sum / ns.AVG_COUNT, have, weakest
end

-- Your average: the game's number when it has one, else ours.
function ns.PlayerAverage()
  local avg, equippedAvg = ns.Results(GetAverageItemLevel)
  equippedAvg = ns.Num(equippedAvg) or ns.Num(avg)
  if equippedAvg and equippedAvg > 0 then return equippedAvg, "game" end
  local own = ns.Average(ns.Equipped())
  return own, "own"
end

---------------------------------------------------------------------------
-- Comparison with what you wear
---------------------------------------------------------------------------
local function DualWield()
  return ns.Value(rawget(_G, "CanDualWield")) == true
end

-- The slots an item competes for.
function ns.TargetSlots(equipLoc)
  local t = INVTYPE[equipLoc or ""]
  if type(t) == "table" then return t end
  if t == "WEAPON" then
    return DualWield() and { "MainHandSlot", "SecondaryHandSlot" } or { "MainHandSlot" }
  elseif t == "TWOHAND" then
    return { "MainHandSlot" }
  elseif t == "RANGED" then
    -- Forever has a ranged slot; without one ranged weapons go to the main hand
    local btn = ns.Frame("CharacterRangedSlot")
    if btn or equipped.RangedSlot then return { "RangedSlot" } end
    return { "MainHandSlot" }
  end
  return nil
end

-- Difference to the weaker of the slots the item would go to (an empty
-- slot counts as 0). Returns diff, slotName, equippedLevel or nil.
function ns.Compare(info)
  if not ns.IsGear(info) then return nil end
  local slots = ns.TargetSlots(info.equipLoc)
  if not slots then return nil end
  local eq = ns.Equipped()
  local mh, oh = eq.MainHandSlot, eq.SecondaryHandSlot
  local wears2H = mh and mh.equipLoc == "INVTYPE_2HWEAPON"
  local bestSlot, bestLevel, bestLoses2H
  for _, name in ipairs(slots) do
    local e = eq[name]
    local lv, loses2H = (e and e.level) or 0, false
    if info.equipLoc == "INVTYPE_2HWEAPON" then
      -- a two-hand weapon replaces both hands (an empty hand counts as 0)
      if not wears2H then lv = ((mh and mh.level or 0) + (oh and oh.level or 0)) / 2 end
    elseif wears2H and (name == "MainHandSlot" or name == "SecondaryHandSlot") then
      -- a one-hand or off-hand item would take the two-hand weapon away
      lv, loses2H = mh.level or 0, true
    end
    if not bestLevel or lv < bestLevel then bestSlot, bestLevel, bestLoses2H = name, lv, loses2H end
  end
  if not bestSlot then return nil end
  if bestLoses2H then bestSlot = "MainHandSlot" end
  return info.level - bestLevel, bestSlot, bestLevel, bestLoses2H or nil
end

-- Can you wear it now? (class, armor type, weapon skill and level)
function ns.CanWear(info)
  if type(info) ~= "table" then return false end
  local level = ns.Num(ns.Value(UnitLevel, "player")) or 0
  if info.reqLevel and info.reqLevel > level then return false end
  if C_PlayerInfo and C_PlayerInfo.CanUseItem then
    local v = ns.Value(C_PlayerInfo.CanUseItem, info.itemID)
    if v == false then return false end
  end
  return true
end

-- Green arrow: higher than what you wear and wearable now.
function ns.IsUpgrade(info)
  if not ns.CanWear(info) then return false end
  local diff, _, _, replaces2H = ns.Compare(info)
  -- a one-hand or off-hand item alone would take your two-hand weapon away: no arrow
  return diff ~= nil and diff > 0 and not replaces2H
end

-- Decimal comma in the German client.
local function Decimal(s)
  if ns.Value(GetLocale) == "deDE" then return (s:gsub("%.", ",")) end
  return s
end

-- Item level of one item (whole number, a decimal only when it has one).
function ns.FormatLevel(level)
  level = ns.Num(level)
  if not level then return "" end
  if math.abs(level - math.floor(level + 0.5)) < 0.05 then return ("%d"):format(math.floor(level + 0.5)) end
  return Decimal(("%.1f"):format(level))
end

-- Averages: always one decimal, so a list of players lines up (23,0 / 22,4).
function ns.FormatAverage(level)
  level = ns.Num(level)
  if not level then return "" end
  return Decimal(("%.1f"):format(level))
end
