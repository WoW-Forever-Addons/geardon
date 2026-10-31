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
  -- (1.2.0, Daniel 10.10.) also bindType (14th: 2 = bind on equip) and setID (16th) of GetItemInfo
  -- (1.3.0) and sellPrice (11th, copper per item)
  local name, _, quality, baseLevel, reqLevel, _, _, _, _, _, sellPrice, _, _, bindType, _, setID = ns.Results(getInfo, link)
  if not ns.Str(name) then Request(itemID) return nil end
  local level = ns.Num(ns.Results(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link))
    or ns.Num(baseLevel)
  if not level then stats.noLevel = stats.noLevel + 1 end
  setID = ns.Num(setID)
  local info = {
    itemID = itemID, level = level, quality = ns.Num(quality), reqLevel = ns.Num(reqLevel) or 0,
    equipLoc = ns.Str(equipLoc), classID = ns.Num(classID), subclassID = ns.Num(subclassID),
    bindType = ns.Num(bindType), setID = (setID and setID > 0) and setID or nil, link = link,
    sellPrice = ns.Num(sellPrice) or 0,
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
-- (Leistungsrunde 6) what the last read gave per slot (link, level), to tell whether a new read changed anything, and
-- whether an item of yours is still loading (a judgement against it is not kept, see ns.Judge)
local wasLink, wasLevel = {}, {}
local equippedPending = true
local function ReadEquipped()
  wipe(wasLink) wipe(wasLevel)
  for name, e in pairs(equipped) do wasLink[name], wasLevel[name] = e.link, e.level or false end
  wipe(equipped)
  local items, missing, pending, changed = 0, 0, 0, false
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
        classID = info and info.classID, subclassID = info and info.subclassID, setID = info and info.setID,
        pending = info == nil or level == nil }
      items = items + 1
      if info == nil or level == nil then pending = pending + 1 end
      if wasLink[name] ~= link or wasLevel[name] ~= (level or false) then changed = true end
    elseif id and ns.Call(GetInventoryItemTexture, "player", id) ~= nil then
      missing = missing + 1 -- an item is there, its link not yet
    end
  end
  for name in pairs(wasLink) do if not equipped[name] then changed = true end end
  equippedPending = missing > 0 or pending > 0
  equippedDirty = items == 0 or missing > 0
  if equippedDirty then lastIncomplete = ns.Num(ns.Value(GetTime)) or 0 end
  return changed
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
ns.On("LEARNED_SPELL_IN_TAB", ns.BumpVersion)       -- (1.2.0) classic event: mail or plate learned at 40

function ns.Equipped()
  if equippedDirty then
    local now = ns.Num(ns.Value(GetTime)) or 0
    -- a read that came back empty or incomplete is tried again after a second
    if next(equipped) == nil and lastIncomplete > 0 and now - lastIncomplete < 1 then return equipped end
    local before = next(equipped) ~= nil
    -- (Leistungsrunde 6) also when a read finds other links or levels than the last one (an item that finished
    -- loading, an upgrade seen through the item location): kept judgements are of the old gear
    local changed = ReadEquipped()
    if (not before and next(equipped) ~= nil) or (before and changed) then ns.BumpVersion() end
  end
  return equipped
end
-- true when your gear is read and none of it is still loading
function ns.EquippedComplete()
  ns.Equipped()
  return not equippedDirty and not equippedPending
end
function ns.MarkEquippedDirty() equippedDirty = true end
ns.On("PLAYER_EQUIPMENT_CHANGED", function() equippedDirty = true end)
ns.On("PLAYER_ENTERING_WORLD", function() equippedDirty = true lastIncomplete = 0 ns.BumpVersion() end)
-- (D16, 31.10.2026) only "player": Core.lua drops the other units before any protected call
ns.On("UNIT_INVENTORY_CHANGED", function() equippedDirty = true end, { player = true })
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

-- The slots an item competes for (shared tables: callers only read them).
local BOTH_HANDS, MAIN_HAND, RANGED_SLOT = { "MainHandSlot", "SecondaryHandSlot" }, { "MainHandSlot" }, { "RangedSlot" }
function ns.TargetSlots(equipLoc)
  local t = INVTYPE[equipLoc or ""]
  if type(t) == "table" then return t end
  if t == "WEAPON" then
    return DualWield() and BOTH_HANDS or MAIN_HAND
  elseif t == "TWOHAND" then
    return MAIN_HAND
  elseif t == "RANGED" then
    -- Forever has a ranged slot; without one ranged weapons go to the main hand
    local btn = ns.Frame("CharacterRangedSlot")
    if btn or equipped.RangedSlot then return RANGED_SLOT end
    return MAIN_HAND
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

-- (1.2.0, Daniel 10.10.) Quality of what the item would replace: the slot's item; a two-hand weapon
-- replaces both hands (the better quality of the two counts, so "higher quality" is never overstated).
-- nil: the slot is empty.
function ns.ReplacedQuality(info, slot)
  local eq = ns.Equipped()
  local e = eq[slot or ""]
  local q = e and e.quality
  if info and info.equipLoc == "INVTYPE_2HWEAPON" then
    local oh = eq.SecondaryHandSlot
    if oh and oh.quality and (not q or oh.quality > q) then q = oh.quality end
  end
  return q
end

-- (1.2.0) Your level, read once per version (the version goes up with
-- PLAYER_LEVEL_UP and PLAYER_LEVEL_CHANGED).
local levelCache, levelVer = 0, nil
function ns.PlayerLevel()
  if levelVer ~= ns.version then
    levelCache, levelVer = ns.Num(ns.Value(UnitLevel, "player")) or 0, ns.version
  end
  return levelCache
end

-- Can you wear it now? (class, armor type, weapon skill and level)
-- (1.3.0) ignoreLevel: could you wear it once you have its level?
function ns.CanWear(info, ignoreLevel)
  if type(info) ~= "table" then return false end
  local level = ns.PlayerLevel()
  if info.reqLevel and info.reqLevel > level and not ignoreLevel then return false end
  if C_PlayerInfo and C_PlayerInfo.CanUseItem then
    local v = ns.Value(C_PlayerInfo.CanUseItem, info.itemID)
    if v == false then return false end
  end
  return true
end

---------------------------------------------------------------------------
-- (1.2.0, Daniel 10.10.) The verdict for one item against what you wear.
-- In Forever the stats come from item level x quality x slot (a budget table
-- like RandPropPoints, foreverchanges.pro/items). That table could not be read
-- from a source we can check, so no budget is computed here. What holds
-- without numbers: a higher item level of the same or a higher quality, or
-- the same item level of a higher quality, is more budget ("sure"). A higher
-- item level of a lower quality may or may not be: "check" (yellow arrow,
-- tooltip says why). A lower item level of a higher quality gets no arrow, the
-- tooltip says to compare the stats.
-- Returns nil (no gear, nothing to compare) or a table:
--   diff, slot, eqLevel, loses2H  as ns.Compare
--   upgrade = true      arrow wanted
--   check = "quality" | "set" | "quality+set"   unsure: yellow arrow; (1.3.0) "+pair" or "pair": with a partner
--   partner, pairGain   (1.3.0) the bag item for the other hand and what both hands gain over your two-hand weapon
--   block = "level" | "wear" | "unique" | "twohand" | "lower" | "weapon" | "armor" | "stats" | "statvalue"   why there is no arrow
--   note = "quality"    lower item level but higher quality (tooltip hint only)
--   note = "statvalue"  (1.2.2) an arrow on a lower item level: its stats are worth more to your class
--   soon = level        (1.3.0) block "level", but an upgrade once you reach that level (option arrowSoon,
--                       at most soonLevels above yours): grey arrow, tooltip names the level
---------------------------------------------------------------------------
-- into: optional table to fill (reused on hot paths, no garbage per item).
-- (Leistungsrunde 6, offen/sonstiges.md "Judge-Merker") A judgement is kept per link until the version goes up
-- (gear, level, talents, skills, options, a loading screen, DonData's "gear" notice) or the options table changes;
-- at most 500, then all are dropped. Not kept: a judgement that read something not known yet (your gear or its
-- tooltip data still loading, unknown stats or value, a unique flag, bag items for the pair still loading), one during
-- which the version went up, and any with DonDataAPI 3 that gives no notices (ns.JudgeMemoOK). A one-hand item
-- against your two-hand weapon is kept only while the bag index is the same (its partner comes from your bags).
-- Without into the kept table itself is returned: callers only read it; with into it is copied there.
local MEMO_MAX = 500
local memo, memoN, memoVer, memoDb = {}, 0, nil, nil
local NONE = {} -- kept "no judgement" (no slot to compare with)
local judgeStats = { computed = 0, hits = 0, notKept = 0, wipes = 0 }
ns.judgeStats = judgeStats
local incomplete = false
function ns.JudgeIncomplete() incomplete = true end
function ns.ForgetJudge(link)
  if link and memo[link] then memo[link] = nil memoN = memoN - 1 end
end
local FIELDS = { "diff", "slot", "eqLevel", "loses2H", "upgrade", "check", "block", "note", "soon", "partner", "pairGain" }
local function CopyInto(src, dst)
  for i = 1, #FIELDS do local k = FIELDS[i] dst[k] = src[k] end
  return dst
end
local function BagReads() return ns.checkStats and ns.checkStats.indexReads end

local Compute
function ns.Judge(info, into)
  if not ns.IsGear(info) then return nil end
  local link = info.link
  local keep = link ~= nil and ns.JudgeMemoOK ~= nil and ns.JudgeMemoOK()
  if keep then
    if memoVer ~= ns.version or memoDb ~= ns.db then
      if memoN > 0 then wipe(memo) end
      memoN, memoVer, memoDb = 0, ns.version, ns.db
    end
    local m = memo[link]
    if m and m.reads then
      if ns.BagGear then ns.BagGear() end -- the index as it is now (it reads the bags again after a change)
      if m.reads ~= BagReads() or memoVer ~= ns.version then m = nil end
    end
    if m then
      judgeStats.hits = judgeStats.hits + 1
      if m == NONE then return nil end
      if into then return CopyInto(m, into) end
      return m
    end
  end
  local ver = ns.version
  incomplete = false
  local v = Compute(info, into or {})
  judgeStats.computed = judgeStats.computed + 1
  if keep then
    if not incomplete and ns.version == ver and memoVer == ver and ns.EquippedComplete() and ns.version == ver then
      if memoN >= MEMO_MAX then wipe(memo) memoN = 0 judgeStats.wipes = judgeStats.wipes + 1 end
      local k = NONE
      if v then
        k = into and CopyInto(v, {}) or v
        if v.loses2H then k.reads = BagReads() end
      end
      if not memo[link] then memoN = memoN + 1 end
      memo[link] = k
    else
      judgeStats.notKept = judgeStats.notKept + 1
    end
  end
  return v
end

function Compute(info, v)
  local diff, slot, eqLevel, loses2H = ns.Compare(info)
  if not diff then return nil end
  -- (1.4.0, Kritikrunde) with DonData's judgement a ring, trinket or one-hand weapon goes against the weaker of your two
  -- by value, not by item level (the same slot Questdon's reward glow takes)
  if not loses2H and ns.WeakerByValue then
    local s2, lv2 = ns.WeakerByValue(info, slot)
    if s2 and s2 ~= slot then slot, eqLevel, diff = s2, lv2, info.level - lv2 end
  end
  v.diff, v.slot, v.eqLevel, v.loses2H = diff, slot, eqLevel, loses2H
  v.upgrade, v.check, v.block, v.note, v.soon, v.partner, v.pairGain = nil, nil, nil, nil, nil, nil, nil
  local q, eqQ = info.quality, ns.ReplacedQuality(info, slot)
  local higherQ = q and eqQ and q > eqQ
  local lowerQ = q and eqQ and q < eqQ
  -- (1.2.2, Daniel 17.10.) the stat value for your class decides when both items' stats are known: armour,
  -- rings, necks and trinkets by their stats alone (the item level only when the stats are worth the same);
  -- weapons keep the item level (damage), the stats only settle a lower or higher quality; a caster's melee weapon
  -- or staff is a stat weapon (ns.StatWeapon) and goes by its stats like armor
  local sc = ns.StatCompare and ns.StatCompare(info, slot)
  local weapon = info.classID == 2 and not (ns.StatWeapon and ns.StatWeapon(info))
  -- (1.4.0, Daniel 31.10.2026) with DonData's judgement (DonDataAPI 3) the weapon's DPS is in the value: weapons go by
  -- it like armor, the item level only breaks a tie
  if sc ~= nil and ns.SharedGear and ns.SharedGear() then weapon = false end
  local statsUp = sc == 1 and diff <= 0 and (not weapon or higherQ)
  local statsDown = sc == -1 and (not weapon or lowerQ)
  if loses2H then sc = nil end
  -- (1.3.0) instead of your two-hand weapon, together with the best item for the other hand in your bags
  local partner
  if loses2H and ns.PairPartner then
    partner = ns.PairPartner(info)
    if partner and not ((info.level + partner.info.level) / 2 > (eqLevel or 0)) then partner = nil end
  end
  -- one item's stats against the whole two-hand weapon say nothing: the pair is the yellow arrow's question
  if partner then statsUp, statsDown = false, false end
  local tooLow = info.reqLevel and info.reqLevel - ns.PlayerLevel() or 0
  -- (1.3.0) a few levels too low: judged as if you had the level, then marked "soon"
  local soon = tooLow > 0 and ns.db and ns.db.arrowSoon ~= false and tooLow <= (tonumber(ns.db.soonLevels) or 3)
  if tooLow > 0 and not soon then
    v.block = "level"
  elseif not ns.CanWear(info, soon) then
    v.block = "wear"
  elseif ns.UniqueWorn and ns.UniqueWorn(info, slot) then
    v.block = "unique" -- (1.3.0) a copy of this unique item is in your other slot
  elseif loses2H and not partner then
    v.block = "twohand" -- a one-hand or off-hand item alone would take your two-hand weapon away
  elseif not (diff > 0 or (diff == 0 and higherQ) or statsUp or partner) then
    v.block = "lower"
    if higherQ and diff < 0 then v.note = "quality" end
  elseif not partner and ns.WeaponTypeOK and not ns.WeaponTypeOK(info, slot) then
    v.block = "weapon"
  elseif ns.ArmorTypeOK and not ns.ArmorTypeOK(info) then
    v.block = "armor"
  elseif ns.MainStatsOK and ns.MainStatsOK(info) == false then
    v.block = "stats"
  elseif statsDown then
    v.block = "statvalue"
  else
    v.upgrade = true
    if statsUp and diff < 0 then v.note = "statvalue" end
    -- a lower quality is no doubt any more when the stats were compared
    local unsure = lowerQ and sc == nil
    local set = ns.SetPieceAtStake and ns.SetPieceAtStake(slot, info)
    if unsure and set then v.check = "quality+set"
    elseif unsure then v.check = "quality"
    elseif set then v.check = "set" end
    if partner then
      v.check = v.check and (v.check .. "+pair") or "pair"
      v.partner, v.pairGain = partner.link, (info.level + partner.info.level) / 2 - (eqLevel or 0)
    end
    if soon then v.upgrade, v.block, v.soon = nil, "level", info.reqLevel end
  end
  return v
end

-- Upgrade arrow: higher than what you wear and wearable now. Second value:
-- true when the arrow is the yellow "check" one.
-- (1.3.0) Third value: the level from which it is an upgrade (grey arrow), when it is one soon.
local scratch = {}
function ns.IsUpgrade(info)
  local v = ns.Judge(info, scratch)
  if not (v and v.upgrade) then
    local soon = v and v.soon
    if soon and v.check and ns.db and ns.db.arrowUncertain == false then soon = nil end
    return false, false, soon
  end
  if v.check then
    if ns.db and ns.db.arrowUncertain == false then return false end
    return true, true
  end
  return true, false
end

-- Decimal separator of the client (Blizzard's DECIMAL_SEPERATOR: comma in deDE, frFR, esES, ptBR, ruRU).
local function Decimal(s)
  local sep = rawget(_G, "DECIMAL_SEPERATOR")
  if type(sep) ~= "string" or sep == "" then sep = ns.Value(GetLocale) == "deDE" and "," or "." end
  if sep ~= "." then return (s:gsub("%.", (sep:gsub("%%", "%%%%")))) end
  return s
end

-- Item level of one item (whole number, a decimal only when it has one).
function ns.FormatLevel(level)
  level = ns.Num(level)
  if not level then return "" end
  if math.abs(level - math.floor(level + 0.5)) < 0.05 then return ("%d"):format(math.floor(level + 0.5)) end
  return Decimal(("%.1f"):format(level))
end

-- (1.3.0) Money: the game's coin text with icons, else "1g 2s 3c".
function ns.Money(copper)
  copper = math.floor(ns.Num(copper) or 0)
  local fn = rawget(_G, "GetCoinTextureString") or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
  local s = ns.Str(ns.Call(fn, copper))
  if s then return s end
  local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if sv > 0 then out[#out + 1] = sv .. "s" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
  return table.concat(out, " ")
end

-- Averages: always one decimal, so a list of players lines up (23,0 / 22,4).
function ns.FormatAverage(level)
  level = ns.Num(level)
  if not level then return "" end
  return Decimal(("%.1f"):format(level))
end
